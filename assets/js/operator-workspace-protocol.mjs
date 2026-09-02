export const LOCAL_HEARTBEAT_INTERVAL_MS = 2_000;
export const MASTER_SERVER_RENEWAL_INTERVAL_MS = 4_000;
export const CHILD_SERVER_CHECK_INTERVAL_MS = 4_000;
export const LOCAL_HEARTBEAT_STALE_MS = 6_000;
export const SERVER_LEASE_DURATION_MS = 13_000;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MODULE_OR_SLOT_KEY = /^[a-z][a-z0-9-]{0,47}$/;
const EVENT_TYPES = new Set(["HELLO", "REGISTERED", "HEARTBEAT", "SHUTDOWN", "LOCK", "INVALIDATE", "FOCUS_REQUEST"]);
const EVENT_KEYS = new Set(["type", "workspaceId", "epoch", "senderWindowId", "sequence", "timestamp", "moduleKey", "slotKey"]);
const MASTER_RESUME_STATE_KEY = "lwsOperatorWorkspaceResumeV1";

export function validUuid(value) {
  return UUID.test(String(value || ""));
}

export function createWindowId(cryptoObject = globalThis.crypto) {
  const value = cryptoObject?.randomUUID?.();
  if (!validUuid(value)) throw new Error("WINDOW_ID_UNAVAILABLE");
  return value;
}

export function workspaceChannelName(workspaceId, epoch) {
  if (!validUuid(workspaceId) || !Number.isSafeInteger(epoch) || epoch < 1) throw new Error("INVALID_WORKSPACE_CHANNEL");
  return `lws-operator-workspace-v1:${workspaceId}:${epoch}`;
}

export function managedChildUrl({ workspaceId, epoch, windowId, launchNonce, moduleKey, slotKey = "main" }, origin = "https://operator.local") {
  if (![workspaceId, windowId, launchNonce].every(validUuid) || !Number.isSafeInteger(epoch) || epoch < 1
    || !MODULE_OR_SLOT_KEY.test(moduleKey) || !MODULE_OR_SLOT_KEY.test(slotKey)) {
    throw new Error("INVALID_CHILD_BOOTSTRAP");
  }
  const url = new URL("/operator/window/", origin);
  url.searchParams.set("module", moduleKey);
  url.hash = new URLSearchParams({ workspace: workspaceId, epoch: String(epoch), window: windowId, launch: launchNonce, slot: slotKey }).toString();
  return url;
}

export function parseChildBootstrap(urlLike, origin = "https://operator.local") {
  const url = new URL(urlLike, origin);
  const fragment = new URLSearchParams(url.hash.replace(/^#/, ""));
  const workspaceId = fragment.get("workspace");
  const windowId = fragment.get("window");
  const launchNonce = fragment.get("launch");
  const moduleKey = url.searchParams.get("module");
  const slotKey = fragment.get("slot");
  const epoch = Number(fragment.get("epoch"));
  if (url.pathname !== "/operator/window/" || !MODULE_OR_SLOT_KEY.test(moduleKey) || !MODULE_OR_SLOT_KEY.test(slotKey)) return null;
  if (![workspaceId, windowId, launchNonce].every(validUuid) || !Number.isSafeInteger(epoch) || epoch < 1) return null;
  return Object.freeze({ workspaceId, epoch, windowId, launchNonce, moduleKey, slotKey });
}

export function createWorkspaceEvent({ type, workspaceId, epoch, senderWindowId, sequence, now = Date.now(), moduleKey, slotKey }) {
  const event = { type, workspaceId, epoch, senderWindowId, sequence, timestamp: now };
  if (moduleKey !== undefined) event.moduleKey = moduleKey;
  if (slotKey !== undefined) event.slotKey = slotKey;
  if (!validWorkspaceEvent(event, { workspaceId, epoch })) throw new Error("INVALID_WORKSPACE_EVENT");
  return Object.freeze(event);
}

export function validWorkspaceEvent(event, { workspaceId, epoch, minimumSequence = -1 }) {
  if (!event || typeof event !== "object" || Array.isArray(event)) return false;
  if (Object.keys(event).some((key)=>!EVENT_KEYS.has(key))) return false;
  if (!EVENT_TYPES.has(event.type) || event.workspaceId !== workspaceId || event.epoch !== epoch) return false;
  if (!validUuid(event.senderWindowId) || !Number.isSafeInteger(event.sequence) || event.sequence < 0 || event.sequence < minimumSequence) return false;
  if (!Number.isFinite(event.timestamp) || event.timestamp < 0) return false;
  if (event.moduleKey !== undefined && !MODULE_OR_SLOT_KEY.test(event.moduleKey)) return false;
  if (event.slotKey !== undefined && !MODULE_OR_SLOT_KEY.test(event.slotKey)) return false;
  return true;
}

export function shouldLockForLease({ leaseExpiresAt, now = Date.now(), serverReachable, serverValid }) {
  if (!Number.isFinite(leaseExpiresAt)) return true;
  if (serverReachable && serverValid === false) return true;
  return now >= leaseExpiresAt;
}

export function operatorWorkspaceResumeHint(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)
    || Object.keys(value).length !== 3 || !validUuid(value.workspaceId)
    || !Number.isSafeInteger(value.epoch) || value.epoch < 1 || !validUuid(value.masterWindowId)) return null;
  return Object.freeze({ workspaceId: value.workspaceId, epoch: value.epoch, masterWindowId: value.masterWindowId });
}

export function readOperatorWorkspaceResumeHint(historyObject) {
  return operatorWorkspaceResumeHint(historyObject?.state?.[MASTER_RESUME_STATE_KEY]);
}

export function writeOperatorWorkspaceResumeHint(historyObject, hint) {
  const validated = operatorWorkspaceResumeHint(hint);
  if (!validated || typeof historyObject?.replaceState !== "function") return false;
  const state = historyObject.state && typeof historyObject.state === "object" && !Array.isArray(historyObject.state)
    ? historyObject.state : {};
  historyObject.replaceState({ ...state, [MASTER_RESUME_STATE_KEY]: validated }, "");
  return true;
}

export function clearOperatorWorkspaceResumeHint(historyObject) {
  if (typeof historyObject?.replaceState !== "function") return false;
  const state = historyObject.state && typeof historyObject.state === "object" && !Array.isArray(historyObject.state)
    ? { ...historyObject.state } : {};
  delete state[MASTER_RESUME_STATE_KEY];
  historyObject.replaceState(state, "");
  return true;
}