import {
  LOCAL_HEARTBEAT_INTERVAL_MS,
  MASTER_SERVER_RENEWAL_INTERVAL_MS,
  SERVER_LEASE_DURATION_MS,
  createWindowId,
  createWorkspaceEvent,
  managedChildUrl,
  operatorWorkspaceResumeHint,
  validUuid,
  validWorkspaceEvent,
  workspaceChannelName,
  workspaceReservationWindowName,
} from "./operator-workspace-protocol.mjs?v=20260913-user-gesture-handoff-r1";
import { resolveStandaloneOperatorModule, validOperatorSlotKey } from "./operator-module-registry.mjs?v=20260917-pre-project-workspace-r2";

async function requestLocalMasterLock(navigatorObject) {
  if (!navigatorObject?.locks?.request) return { acquired: false, release() {} };
  let releaseLock;
  let resolveAcquisition;
  const acquired = new Promise((resolve)=>{ resolveAcquisition = resolve; });
  navigatorObject.locks.request("lws-operator-workspace-master-v1", { ifAvailable: true }, (lock)=>{
    resolveAcquisition(Boolean(lock));
    if (!lock) return undefined;
    return new Promise((resolve)=>{ releaseLock = resolve; });
  }).catch(()=>resolveAcquisition(false));
  return { acquired: await acquired, release: ()=>releaseLock?.() };
}

function leaseTime(value) {
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? timestamp : null;
}

function authorityFailure(error) {
  return error?.code === "42501" || /OPERATOR|WORKSPACE|JWT|AUTH/i.test(String(error?.message || ""));
}

function expiredWorkspace(error) {
  return error?.code === "42501" && error?.message === "WORKSPACE_NOT_ACTIVE";
}

function validWindowClaims(value) {
  if (!Array.isArray(value)) return null;
  const claims = new Map();
  for (const claim of value) {
    if (!claim || typeof claim !== "object" || Array.isArray(claim)
      || Object.keys(claim).length !== 3 || !validUuid(claim.window_id)
      || !resolveStandaloneOperatorModule(claim.module_key)
      || !validOperatorSlotKey(claim.slot_key)) return null;
    const key = `${claim.module_key}:${claim.slot_key}`;
    if (claims.has(key)) return null;
    claims.set(key, { windowId: claim.window_id, reference: null });
  }
  return claims;
}

function inactiveWorkspaceMaster(reason) {
  return Object.freeze({
    active: false,
    reason,
    resumeHint: null,
    bindModuleButton() {},
    dispose() {},
    invalidate() {},
    lockWorkspace() {},
    openOperatorModuleWindow(_moduleKey, _slotKey, _reservationId, onLaunchFailure = ()=>{}) {
      onLaunchFailure("WORKSPACE_INACTIVE");
      return false;
    },
    shutdownWorkspace() { return Promise.resolve(false); },
    unbindModuleButton() { return false; },
  });
}

// A module-window launch must never fail silently. Every safe failure code
// below is machine-readable and non-sensitive; the rendered message never
// includes raw provider/browser error text.
const LAUNCH_FAILURE_MESSAGE = "Venster kon niet worden geopend.";
const LAUNCH_FAILURE_MESSAGE_ATTRIBUTE = "data-operator-window-launch-message";

function presentLaunchFailure(button, code) {
  if (!button || typeof button.insertAdjacentElement !== "function") return;
  const doc = button.ownerDocument;
  if (!doc || typeof doc.createElement !== "function") return;
  let node = button.nextElementSibling;
  if (!node || typeof node.hasAttribute !== "function" || !node.hasAttribute(LAUNCH_FAILURE_MESSAGE_ATTRIBUTE)) {
    node = doc.createElement("p");
    node.setAttribute(LAUNCH_FAILURE_MESSAGE_ATTRIBUTE, "");
    node.setAttribute("role", "status");
    node.setAttribute("aria-live", "polite");
    node.className = "action-message action-message--dark";
    button.insertAdjacentElement("afterend", node);
  }
  node.textContent = `${LAUNCH_FAILURE_MESSAGE} (${code})`;
}

export function createOperatorWorkspaceRecovery({
  acquire,
  onMaster = ()=>{},
  setTimeoutFn = setTimeout,
  clearTimeoutFn = clearTimeout,
  retryDelayMs = 100,
} = {}) {
  if (typeof acquire !== "function") throw new Error("OPERATOR_WORKSPACE_RECOVERY_ACQUIRE_REQUIRED");
  let disposed = false;
  let pending = false;
  let retryTimer = null;
  let currentMaster = null;

  async function retry() {
    if (disposed || pending || currentMaster?.active) return currentMaster;
    if (retryTimer) {
      clearTimeoutFn(retryTimer);
      retryTimer = null;
    }
    pending = true;
    let candidate;
    try {
      candidate = await acquire();
    } finally {
      pending = false;
    }
    if (disposed) {
      candidate?.dispose();
      return candidate;
    }
    currentMaster = candidate;
    onMaster(candidate);
    if (!candidate?.active && candidate?.reason === "SERVER_MASTER_EXISTS") {
      retryTimer = setTimeoutFn(()=>{
        retryTimer = null;
        void retry();
      }, retryDelayMs);
    }
    return candidate;
  }

  return {
    start: retry,
    retry,
    dispose() {
      if (disposed) return;
      disposed = true;
      if (retryTimer) clearTimeoutFn(retryTimer);
      retryTimer = null;
    },
  };
}

export async function createOperatorWorkspaceMaster({
  client,
  windowObject = window,
  navigatorObject = navigator,
  now = Date.now,
  setIntervalFn = setInterval,
  clearIntervalFn = clearInterval,
  setTimeoutFn = setTimeout,
  onInvalidate = ()=>{},
  onInvalidWorkspace = ()=>{},
  onAvailabilityChange = ()=>{},
  onResumeHintChange = ()=>{},
  requireAal2 = async ()=>true,
  resumeHint = null,
} = {}) {
  const localLock = await requestLocalMasterLock(navigatorObject);
  if (!localLock.acquired) {
    onAvailabilityChange("unavailable");
    return inactiveWorkspaceMaster("LOCAL_MASTER_EXISTS");
  }

  const masterWindowId = createWindowId(windowObject.crypto);
  const requestedResume = operatorWorkspaceResumeHint(resumeHint);
  let data;
  let error;
  let resumed = false;
  if (requestedResume) {
    ({ data, error } = await client.rpc("resume_operator_workspace_v1", {
      p_workspace_id: requestedResume.workspaceId,
      p_epoch: requestedResume.epoch,
      p_previous_master_window_id: requestedResume.masterWindowId,
      p_new_master_window_id: masterWindowId,
    }));
    if (error && authorityFailure(error)) {
      localLock.release();
      return inactiveWorkspaceMaster("WORKSPACE_RESUME_FAILED");
    }
    resumed = !error && data?.resumed === true;
  }
  if (!resumed) ({ data, error } = await client.rpc("acquire_operator_workspace_v1", { p_master_window_id: masterWindowId }));
  if (!error && data?.acquired === false) {
    onAvailabilityChange("occupied");
    const leaseExpiry = Date.parse(data.lease_expires_at);
    const retryDelay = Number.isFinite(leaseExpiry)
      ? Math.min(Math.max(leaseExpiry - now() + 100, 100), SERVER_LEASE_DURATION_MS + 100)
      : 0;
    if (retryDelay > 0) {
      await new Promise((resolve)=>setTimeoutFn(resolve, retryDelay));
      ({ data, error } = await client.rpc("acquire_operator_workspace_v1", { p_master_window_id: masterWindowId }));
    }
  }
  const resumedClaims = resumed ? validWindowClaims(data?.window_claims) : new Map();
  if (error || (resumed ? data?.resumed !== true || !resumedClaims : data?.acquired !== true)
    || !validUuid(data.workspace_id) || !validUuid(data.renewal_token)) {
    if (error || data?.acquired !== false) onAvailabilityChange("unavailable");
    localLock.release();
    return inactiveWorkspaceMaster(data?.acquired === false ? "SERVER_MASTER_EXISTS" : "WORKSPACE_ACQUIRE_FAILED");
  }
  onAvailabilityChange("active");
  const memory = {
    workspaceId: data.workspace_id,
    epoch: Number(data.epoch),
    masterWindowId,
    renewalToken: data.renewal_token,
  };
  let channel = new windowObject.BroadcastChannel(workspaceChannelName(memory.workspaceId, memory.epoch));
  let sequence = 0;
  let active = true;
  const childWindows = resumedClaims;
  const pendingLaunches = new Map();
  const openButtons = new Map();
  let authorityCheck = null;
  let recoveryCheck = null;
  let leaseExpiresAt = leaseTime(data.lease_expires_at);

  function currentResumeHint() {
    return operatorWorkspaceResumeHint({
      workspaceId: memory.workspaceId,
      epoch: memory.epoch,
      masterWindowId: memory.masterWindowId,
    });
  }

  function publish(type, moduleKey, slotKey) {
    if (!active && type !== "SHUTDOWN" && type !== "LOCK") return;
    channel.postMessage(createWorkspaceEvent({
      type,
      workspaceId: memory.workspaceId,
      epoch: memory.epoch,
      senderWindowId: memory.masterWindowId,
      sequence: sequence++,
      now: now(),
      moduleKey,
      slotKey,
    }));
  }

  async function recoverExpiredWorkspace() {
    if (recoveryCheck) return recoveryCheck;
    recoveryCheck = (async ()=>{
    const previousWorkspaceId = memory.workspaceId;
    const previousEpoch = memory.epoch;
    const { data, error } = await client.rpc("recover_operator_workspace_v1", {
      p_workspace_id: previousWorkspaceId,
      p_epoch: previousEpoch,
      p_master_window_id: memory.masterWindowId,
      p_renewal_token: memory.renewalToken,
    });
    const nextExpiry = leaseTime(data?.lease_expires_at);
    if (error || data?.recovered !== true || !validUuid(data.workspace_id)
      || !Number.isSafeInteger(Number(data.epoch)) || Number(data.epoch) < 1
      || !validUuid(data.renewal_token) || !nextExpiry || nextExpiry <= now()
      || validWindowClaims(data.window_claims)?.size !== 0) {
      lockWorkspace("MASTER_RECOVERY_FAILED");
      return false;
    }
    publish("LOCK");
    channel.close();
    childWindows.clear();
    memory.workspaceId = data.workspace_id;
    memory.epoch = Number(data.epoch);
    memory.renewalToken = data.renewal_token;
    leaseExpiresAt = nextExpiry;
    sequence = 0;
    channel = new windowObject.BroadcastChannel(workspaceChannelName(memory.workspaceId, memory.epoch));
    bindChannel();
    onResumeHintChange(currentResumeHint());
    onAvailabilityChange("active");
    return true;
    })();
    try {
      return await recoveryCheck;
    } finally {
      recoveryCheck = null;
    }
  }

  async function renew({ recoverExpired = false } = {}) {
    if (!active) return false;
    const check = authorityCheck || (authorityCheck = (async ()=>{
      const { data, error } = await client.rpc("renew_operator_workspace_lease_v1", {
        p_workspace_id: memory.workspaceId,
        p_epoch: memory.epoch,
        p_master_window_id: memory.masterWindowId,
        p_renewal_token: memory.renewalToken,
      });
      if (error) {
        if (expiredWorkspace(error)) return "expired";
        if (authorityFailure(error) || !leaseExpiresAt || now() >= leaseExpiresAt) {
          lockWorkspace("MASTER_RENEWAL_FAILED");
        }
        return "failed";
      }
      const nextExpiry = leaseTime(data?.lease_expires_at);
      if (data?.valid !== true || !nextExpiry || nextExpiry <= now()) {
        lockWorkspace("MASTER_RENEWAL_FAILED");
        return "failed";
      }
      leaseExpiresAt = nextExpiry;
      return "valid";
    })());
    let result;
    try {
      result = await check;
    } finally {
      if (authorityCheck === check) authorityCheck = null;
    }
    if (result === "expired" && recoverExpired && active) return recoverExpiredWorkspace();
    return result === "valid";
  }

  const heartbeatTimer = setIntervalFn(()=>publish("HEARTBEAT"), LOCAL_HEARTBEAT_INTERVAL_MS);
  const renewalTimer = setIntervalFn(()=>void renew(), MASTER_SERVER_RENEWAL_INTERVAL_MS);
  const safetyTimer = setIntervalFn(()=>{
    if (!leaseExpiresAt) lockWorkspace("MASTER_LEASE_EXPIRED");
  }, 1_000);

  function lockWorkspace(reason = "WORKSPACE_INVALID") {
    if (!active) return;
    publish("LOCK");
    active = false;
    for (const button of openButtons.keys()) button.disabled = true;
    clearIntervalFn(heartbeatTimer);
    clearIntervalFn(renewalTimer);
    clearIntervalFn(safetyTimer);
    onInvalidWorkspace(reason);
  }

  async function completeOperatorModuleLaunch(moduleKey, slotKey, reservation, launchReservationId, onLaunchFailure = ()=>{}) {
    if (!await renew({ recoverExpired: true }) || !active) {
      try { reservation?.close(); } catch {}
      onLaunchFailure("LEASE_RENEWAL_FAILED");
      return false;
    }
    const childKey = `${moduleKey}:${slotKey}`;
    const existing = childWindows.get(childKey);
    if (existing?.reference && !existing.reference.closed) {
      try { reservation?.close(); } catch {}
      existing.reference.focus();
      publish("FOCUS_REQUEST", moduleKey, slotKey);
      return true;
    }
    const windowId = existing?.windowId || launchReservationId;
    const url = managedChildUrl({
      workspaceId: memory.workspaceId,
      epoch: memory.epoch,
      windowId,
      launchNonce: createWindowId(windowObject.crypto),
      moduleKey,
      slotKey,
    }, windowObject.location.origin);
    try {
      reservation.location.replace(url.href);
    } catch {
      try { reservation.close(); } catch {}
      onLaunchFailure("CHILD_NAVIGATION_FAILED");
      return false;
    }
    childWindows.set(childKey, { windowId, reference: reservation });
    reservation.focus();
    return true;
  }

  function openOperatorModuleWindow(moduleKey, slotKey = "main", reservationId, onLaunchFailure = ()=>{}) {
    const descriptor = resolveStandaloneOperatorModule(moduleKey);
    if (!active) {
      onLaunchFailure("WORKSPACE_INACTIVE");
      return false;
    }
    if (!descriptor) {
      onLaunchFailure("MODULE_INVALID");
      return false;
    }
    if (!validOperatorSlotKey(slotKey)) {
      onLaunchFailure("SLOT_INVALID");
      return false;
    }
    const childKey = `${moduleKey}:${slotKey}`;
    const pending = pendingLaunches.get(childKey);
    if (pending) {
      pending.reference.focus();
      return true;
    }
    const launchReservationId = reservationId || createWindowId(windowObject.crypto);
    const reservation = windowObject.open(
      "about:blank",
      workspaceReservationWindowName(memory.workspaceId, launchReservationId),
      "popup",
    );
    if (!reservation) {
      onLaunchFailure("POPUP_BLOCKED");
      return false;
    }
    const launch = completeOperatorModuleLaunch(moduleKey, slotKey, reservation, launchReservationId, onLaunchFailure)
      .finally(()=>pendingLaunches.delete(childKey));
    pendingLaunches.set(childKey, { reference: reservation, launch });
    return true;
  }

  function bindModuleButton(button, moduleKey, slotKey = "main") {
    if (!button) return;
    const descriptor = resolveStandaloneOperatorModule(moduleKey);
    if (!descriptor || !validOperatorSlotKey(slotKey)) {
      button.hidden = true;
      button.disabled = true;
      return;
    }
    if (openButtons.has(button)) return;
    const listener = ()=>openOperatorModuleWindow(
      button.dataset?.operatorWindowModule || moduleKey,
      button.dataset?.operatorWindowSlot || slotKey,
      undefined,
      (code)=>presentLaunchFailure(button, code),
    );
    openButtons.set(button, listener);
    button.hidden = false;
    button.disabled = !active;
    button.addEventListener("click", listener);
  }

  function unbindModuleButton(button) {
    const listener = openButtons.get(button);
    if (!listener) return false;
    button.removeEventListener("click", listener);
    openButtons.delete(button);
    return true;
  }

  function invalidate(moduleKey = "messages") {
    publish("INVALIDATE", moduleKey);
  }

  function handleChannelMessage(event) {
    if (!validWorkspaceEvent(event.data, { workspaceId: memory.workspaceId, epoch: memory.epoch })) return;
    if (event.data.type === "HELLO") publish("REGISTERED", event.data.moduleKey, event.data.slotKey);
    if (event.data.type === "INVALIDATE" && resolveStandaloneOperatorModule(event.data.moduleKey)) onInvalidate(event.data.moduleKey);
    if (event.data.type === "OPEN_REQUEST") {
      openOperatorModuleWindow(event.data.moduleKey, event.data.slotKey, event.data.reservationId);
    }
  }

  function bindChannel() {
    channel.addEventListener("message", handleChannelMessage);
  }

  bindChannel();

  async function shutdownWorkspace() {
    if (!active) return;
    try {
      await requireAal2();
    } catch {
      return false;
    }
    const revocation = client.rpc("revoke_operator_workspace_v1", {
      p_workspace_id: memory.workspaceId,
      p_epoch: memory.epoch,
      p_master_window_id: memory.masterWindowId,
      p_renewal_token: memory.renewalToken,
    });
    publish("SHUTDOWN");
    active = false;
    for (const button of openButtons.keys()) button.disabled = true;
    clearIntervalFn(heartbeatTimer);
    clearIntervalFn(renewalTimer);
    clearIntervalFn(safetyTimer);
    const result = await revocation;
    for (const child of childWindows.values()) {
      try { child.reference?.close(); } catch {}
    }
    channel.close();
    localLock.release();
    return !result.error && result.data?.revoked === true;
  }

  function dispose() {
    if (!active) return;
    active = false;
    clearIntervalFn(heartbeatTimer);
    clearIntervalFn(renewalTimer);
    clearIntervalFn(safetyTimer);
    channel.close();
    localLock.release();
  }

  publish("HEARTBEAT");
  return {
    get active() { return active; },
    resumed,
    get resumeHint() { return currentResumeHint(); },
    get workspaceId() { return memory.workspaceId; },
    get epoch() { return memory.epoch; },
    masterWindowId: memory.masterWindowId,
    bindModuleButton,
    dispose,
    invalidate,
    openOperatorModuleWindow,
    lockWorkspace,
    shutdownWorkspace,
    unbindModuleButton,
  };
}