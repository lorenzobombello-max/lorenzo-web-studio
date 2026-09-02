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
} from "./operator-workspace-protocol.mjs?v=20260902-lifecycle-round2";
import { resolveStandaloneOperatorModule, validOperatorSlotKey } from "./operator-module-registry.mjs?v=20260902-login-stability";

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
  resumeHint = null,
} = {}) {
  const localLock = await requestLocalMasterLock(navigatorObject);
  if (!localLock.acquired) return Object.freeze({ active: false, reason: "LOCAL_MASTER_EXISTS" });

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
      return Object.freeze({ active: false, reason: "WORKSPACE_RESUME_FAILED" });
    }
    resumed = !error && data?.resumed === true;
  }
  if (!resumed) ({ data, error } = await client.rpc("acquire_operator_workspace_v1", { p_master_window_id: masterWindowId }));
  if (!error && data?.acquired === false) {
    const leaseExpiry = Date.parse(data.lease_expires_at);
    const retryDelay = Number.isFinite(leaseExpiry)
      ? Math.min(Math.max(leaseExpiry - now() + 100, 100), SERVER_LEASE_DURATION_MS + 100)
      : 0;
    if (retryDelay > 0) {
      await new Promise((resolve)=>setTimeoutFn(resolve, retryDelay));
      ({ data, error } = await client.rpc("acquire_operator_workspace_v1", { p_master_window_id: masterWindowId }));
    }
  }
  if (error || (resumed ? data?.resumed !== true : data?.acquired !== true)
    || !validUuid(data.workspace_id) || !validUuid(data.renewal_token)) {
    localLock.release();
    return Object.freeze({ active: false, reason: data?.acquired === false ? "SERVER_MASTER_EXISTS" : "WORKSPACE_ACQUIRE_FAILED" });
  }
  const memory = {
    workspaceId: data.workspace_id,
    epoch: Number(data.epoch),
    masterWindowId,
    renewalToken: data.renewal_token,
  };
  const channel = new windowObject.BroadcastChannel(workspaceChannelName(memory.workspaceId, memory.epoch));
  let sequence = 0;
  let active = true;
  const childWindows = new Map();
  const openButtons = new Map();
  let renewalPending = false;
  let leaseExpiresAt = leaseTime(data.lease_expires_at);

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

  async function renew() {
    if (!active || renewalPending) return;
    renewalPending = true;
    const { data, error } = await client.rpc("renew_operator_workspace_lease_v1", {
      p_workspace_id: memory.workspaceId,
      p_epoch: memory.epoch,
      p_master_window_id: memory.masterWindowId,
      p_renewal_token: memory.renewalToken,
    });
    renewalPending = false;
    if (error) {
      if (authorityFailure(error) || !leaseExpiresAt || now() >= leaseExpiresAt) lockWorkspace("MASTER_RENEWAL_FAILED");
      return;
    }
    const nextExpiry = leaseTime(data?.lease_expires_at);
    if (data?.valid !== true || !nextExpiry || nextExpiry <= now()) {
      lockWorkspace("MASTER_RENEWAL_FAILED");
      return;
    }
    leaseExpiresAt = nextExpiry;
  }

  const heartbeatTimer = setIntervalFn(()=>publish("HEARTBEAT"), LOCAL_HEARTBEAT_INTERVAL_MS);
  const renewalTimer = setIntervalFn(()=>void renew(), MASTER_SERVER_RENEWAL_INTERVAL_MS);
  const safetyTimer = setIntervalFn(()=>{
    if (!leaseExpiresAt || now() >= leaseExpiresAt) lockWorkspace("MASTER_LEASE_EXPIRED");
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

  function openOperatorModuleWindow(moduleKey, slotKey = "main") {
    const descriptor = resolveStandaloneOperatorModule(moduleKey);
    if (!active || !descriptor || !validOperatorSlotKey(slotKey)) return false;
    const childKey = `${moduleKey}:${slotKey}`;
    const existing = childWindows.get(childKey);
    if (existing?.reference && !existing.reference.closed) {
      existing.reference.focus();
      publish("FOCUS_REQUEST", moduleKey, slotKey);
      return true;
    }
    const windowId = existing?.windowId || createWindowId(windowObject.crypto);
    const url = managedChildUrl({
      workspaceId: memory.workspaceId,
      epoch: memory.epoch,
      windowId,
      launchNonce: createWindowId(windowObject.crypto),
      moduleKey,
      slotKey,
    }, windowObject.location.origin);
    const reference = windowObject.open(url.href, `lws-operator-${moduleKey}-${slotKey}-${memory.workspaceId}`, "popup");
    childWindows.set(childKey, { windowId, reference });
    reference?.focus();
    return Boolean(reference);
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
    const listener = ()=>openOperatorModuleWindow(moduleKey, slotKey);
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

  channel.addEventListener("message", (event)=>{
    if (!validWorkspaceEvent(event.data, { workspaceId: memory.workspaceId, epoch: memory.epoch })) return;
    if (event.data.type === "HELLO") publish("REGISTERED", event.data.moduleKey, event.data.slotKey);
    if (event.data.type === "INVALIDATE" && resolveStandaloneOperatorModule(event.data.moduleKey)) onInvalidate(event.data.moduleKey);
  });

  async function shutdownWorkspace() {
    if (!active) return;
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
    resumeHint: operatorWorkspaceResumeHint({ workspaceId: memory.workspaceId, epoch: memory.epoch, masterWindowId: memory.masterWindowId }),
    workspaceId: memory.workspaceId,
    epoch: memory.epoch,
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