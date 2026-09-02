import {
  CHILD_SERVER_CHECK_INTERVAL_MS,
  LOCAL_HEARTBEAT_STALE_MS,
  createWorkspaceEvent,
  shouldLockForLease,
  validWorkspaceEvent,
  workspaceChannelName,
} from "./operator-workspace-protocol.mjs?v=20260902-login-stability";

function leaseTime(value) {
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? timestamp : null;
}

function authorityFailure(error) {
  return error?.code === "42501" || /OPERATOR|WORKSPACE|JWT|AUTH/i.test(String(error?.message || ""));
}

export function createOperatorWorkspaceChild({
  client,
  bootstrap,
  joinedWorkspace,
  windowObject = window,
  documentObject = document,
  now = Date.now,
  setIntervalFn = setInterval,
  clearIntervalFn = clearInterval,
  onInvalidate = ()=>{},
  onLock = ()=>{},
} = {}) {
  const channel = new windowObject.BroadcastChannel(workspaceChannelName(bootstrap.workspaceId, bootstrap.epoch));
  let active = true;
  let sequence = 0;
  let lastHeartbeatAt = now();
  let leaseExpiresAt = leaseTime(joinedWorkspace.lease_expires_at);
  let verificationPending = false;
  const senderSequences = new Map();

  function publish(type, moduleKey) {
    if (!active && type !== "LOCK") return;
    channel.postMessage(createWorkspaceEvent({
      type,
      workspaceId: bootstrap.workspaceId,
      epoch: bootstrap.epoch,
      senderWindowId: bootstrap.windowId,
      sequence: sequence++,
      now: now(),
      moduleKey,
      slotKey: bootstrap.slotKey,
    }));
  }

  function lock(reason, attemptClose = false) {
    if (!active) return;
    active = false;
    publish("LOCK", bootstrap.moduleKey);
    clearIntervalFn(serverTimer);
    clearIntervalFn(safetyTimer);
    channel.close();
    onLock(reason);
    if (attemptClose) {
      try { windowObject.close(); } catch {}
    }
  }

  async function verifyServerLease() {
    if (!active || verificationPending) return;
    verificationPending = true;
    const { data, error } = await client.rpc("get_operator_workspace_status_v1", {
      p_workspace_id: bootstrap.workspaceId,
      p_epoch: bootstrap.epoch,
      p_window_id: bootstrap.windowId,
    });
    verificationPending = false;
    if (!active) return;
    if (error) {
      if (authorityFailure(error) || shouldLockForLease({ leaseExpiresAt, now: now(), serverReachable: false })) lock("WORKSPACE_UNVERIFIABLE");
      return;
    }
    const nextExpiry = leaseTime(data?.lease_expires_at);
    if (data?.valid !== true || !nextExpiry || nextExpiry <= now()) {
      lock("WORKSPACE_NOT_ACTIVE");
      return;
    }
    leaseExpiresAt = nextExpiry;
  }

  channel.addEventListener("message", (event)=>{
    const safetyEvent = event.data?.type === "SHUTDOWN" || event.data?.type === "LOCK";
    const minimumSequence = safetyEvent ? -1 : senderSequences.get(event.data?.senderWindowId) ?? -1;
    if (!validWorkspaceEvent(event.data, { workspaceId: bootstrap.workspaceId, epoch: bootstrap.epoch, minimumSequence })) return;
    senderSequences.set(event.data.senderWindowId, event.data.sequence + 1);
    if (event.data.type === "HEARTBEAT" || event.data.type === "REGISTERED") lastHeartbeatAt = now();
    if (event.data.type === "SHUTDOWN") lock("WORKSPACE_SHUTDOWN", true);
    if (event.data.type === "LOCK") lock("WORKSPACE_LOCKED");
    if (event.data.type === "INVALIDATE" && event.data.moduleKey === bootstrap.moduleKey) onInvalidate(bootstrap.moduleKey);
    if (event.data.type === "FOCUS_REQUEST" && event.data.moduleKey === bootstrap.moduleKey && event.data.slotKey === bootstrap.slotKey) windowObject.focus();
  });

  const serverTimer = setIntervalFn(()=>void verifyServerLease(), CHILD_SERVER_CHECK_INTERVAL_MS);
  const safetyTimer = setIntervalFn(()=>{
    if (shouldLockForLease({ leaseExpiresAt, now: now(), serverReachable: false })) lock("MASTER_LEASE_EXPIRED");
    else if (now() - lastHeartbeatAt >= LOCAL_HEARTBEAT_STALE_MS) void verifyServerLease();
  }, 1_000);

  documentObject.addEventListener("visibilitychange", ()=>{
    if (documentObject.visibilityState === "visible") void verifyServerLease();
  });
  publish("HELLO", bootstrap.moduleKey);

  return {
    get active() { return active; },
    dispose() {
      if (!active) return;
      active = false;
      clearIntervalFn(serverTimer);
      clearIntervalFn(safetyTimer);
      channel.close();
    },
    invalidate(moduleKey = bootstrap.moduleKey) { publish("INVALIDATE", moduleKey); },
    lock,
    verifyServerLease,
  };
}