import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  CHILD_SERVER_CHECK_INTERVAL_MS,
  LOCAL_HEARTBEAT_INTERVAL_MS,
  LOCAL_HEARTBEAT_STALE_MS,
  MASTER_SERVER_RENEWAL_INTERVAL_MS,
  SERVER_LEASE_DURATION_MS,
  createWorkspaceEvent,
  clearOperatorWorkspaceResumeHint,
  managedChildUrl,
  operatorWorkspaceResumeHint,
  parseChildBootstrap,
  readOperatorWorkspaceResumeHint,
  shouldLockForLease,
  validWorkspaceEvent,
  writeOperatorWorkspaceResumeHint,
} from "../assets/js/operator-workspace-protocol.mjs";
import { createOperatorWorkspaceChild } from "../assets/js/operator-workspace-child.mjs";
import { createOperatorWorkspaceMaster } from "../assets/js/operator-workspace-master.mjs";
import { watchOperatorSession } from "../assets/js/operator-auth-core.mjs";
import {
  OPERATOR_MODULE_DESCRIPTORS,
  getOperatorModuleDescriptor,
  resolveStandaloneOperatorModule,
  validOperatorModuleKey,
  validOperatorSlotKey,
} from "../assets/js/operator-module-registry.mjs";
import { createOperatorWindowHost } from "../assets/js/operator-window-host.mjs";
import {
  OPERATOR_WORKSPACE_OCCUPIED_MESSAGE,
  createOperatorWorkspaceStatusPresenter,
} from "../assets/js/operator-workspace-status.mjs";

const workspaceId = "f4000000-0000-4000-8000-000000000001";
const masterWindowId = "f4000000-0000-4000-8000-000000000002";
const childWindowId = "f4000000-0000-4000-8000-000000000003";
const launchNonce = "f4000000-0000-4000-8000-000000000004";
const epoch = 41;
const root = new URL("../", import.meta.url);
const read = (path)=>readFile(new URL(path, root), "utf8");

class FakeBroadcastChannel {
  static instances = [];
  constructor(name) {
    this.name = name;
    this.listeners = [];
    this.messages = [];
    FakeBroadcastChannel.instances.push(this);
  }
  addEventListener(type, listener) { if (type === "message") this.listeners.push(listener); }
  close() { this.closed = true; }
  emit(data) { for (const listener of this.listeners) listener({ data }); }
  postMessage(data) { this.messages.push(data); }
}

function timerHarness() {
  const timers = [];
  return {
    timers,
    setIntervalFn(callback, interval) {
      const timer = { callback, interval, cleared: false };
      timers.push(timer);
      return timer;
    },
    clearIntervalFn(timer) { timer.cleared = true; },
    timer(interval) { return timers.find((timer)=>timer.interval === interval && !timer.cleared); },
  };
}

function availableWebLock() {
  return { locks: { request(_name, _options, callback) { void callback({ name: "workspace" }); return Promise.resolve(); } } };
}

function childHarness({ nowValue = 10_000, rpc = async()=>({ data: { valid: true, lease_expires_at: new Date(25_000).toISOString() }, error: null }) } = {}) {
  FakeBroadcastChannel.instances = [];
  const timers = timerHarness();
  const locks = [];
  const windowObject = { BroadcastChannel: FakeBroadcastChannel, close() { this.closed = true; }, focus() {} };
  const child = createOperatorWorkspaceChild({
    client: { rpc },
    bootstrap: { workspaceId, epoch, windowId: childWindowId, moduleKey: "messages", slotKey: "main" },
    joinedWorkspace: { lease_expires_at: new Date(25_000).toISOString() },
    windowObject,
    documentObject: { visibilityState: "visible", addEventListener() {} },
    now: ()=>nowValue,
    setIntervalFn: timers.setIntervalFn,
    clearIntervalFn: timers.clearIntervalFn,
    onLock: (reason)=>locks.push(reason),
  });
  return { child, channel: FakeBroadcastChannel.instances[0], locks, timers, windowObject, setNow(value) { nowValue = value; } };
}

test("approved workspace timing remains inside the owner safety target", ()=>{
  assert.equal(LOCAL_HEARTBEAT_INTERVAL_MS, 2_000);
  assert.equal(MASTER_SERVER_RENEWAL_INTERVAL_MS, 4_000);
  assert.equal(CHILD_SERVER_CHECK_INTERVAL_MS, 4_000);
  assert.equal(LOCAL_HEARTBEAT_STALE_MS, 6_000);
  assert.equal(SERVER_LEASE_DURATION_MS, 13_000);
  assert.ok(SERVER_LEASE_DURATION_MS - MASTER_SERVER_RENEWAL_INTERVAL_MS >= 8_000);
});

test("server and browser use the same hardened lease duration", async ()=>{
  const migration = await read("supabase/migrations/20260902170000_harden_operator_workspace_lease_timing_v1.sql");
  assert.equal((migration.match(/interval '13 seconds'/g) || []).length, 2);
  assert.doesNotMatch(migration, /interval '15 seconds'/);
});

test("managed child URL contains bootstrap identity but no browser authority", ()=>{
  const url = managedChildUrl({ workspaceId, epoch, windowId: childWindowId, launchNonce, moduleKey: "messages", slotKey: "main" });
  assert.equal(url.pathname, "/operator/window/");
  assert.equal(url.searchParams.get("module"), "messages");
  assert.equal(url.searchParams.has("role"), false);
  assert.equal(url.searchParams.has("token"), false);
  assert.match(url.hash, /workspace=/);
  assert.deepEqual(parseChildBootstrap(url), { workspaceId, epoch, windowId: childWindowId, launchNonce, moduleKey: "messages", slotKey: "main" });
});

test("child bootstrap parses generic module identity and rejects malformed identifiers", ()=>{
  const valid = managedChildUrl({ workspaceId, epoch, windowId: childWindowId, launchNonce, moduleKey: "messages", slotKey: "main" });
  valid.searchParams.set("module", "finance");
  assert.equal(parseChildBootstrap(valid)?.moduleKey, "finance");
  valid.hash = "#workspace=not-a-uuid";
  assert.equal(parseChildBootstrap(valid), null);
});

test("registry resolves only registered standalone-safe modules", ()=>{
  assert.equal(OPERATOR_MODULE_DESCRIPTORS.length, 8);
  assert.equal(resolveStandaloneOperatorModule("messages")?.initializer, "initializeOperatorMessages");
  assert.equal(resolveStandaloneOperatorModule("calendar")?.initializer, "initializeOperatorCalendar");
  assert.equal(resolveStandaloneOperatorModule("recruitment")?.initializer, "initializeOperatorRecruitment");
  assert.equal(resolveStandaloneOperatorModule("workforce")?.initializer, "initializeOperatorWorkforce");
  assert.equal(resolveStandaloneOperatorModule("finance")?.initializer, "initializeOperatorFinance");
  assert.equal(resolveStandaloneOperatorModule("dossiers")?.initializer, "initializeOperatorDossiers");
  assert.equal(resolveStandaloneOperatorModule("unknown"), null);
});

test("Dossiers inventory enables all required modules and preserves the Intake blocker", ()=>{
  const expected = {
    profile: "PROFILE_BOUND_TO_CURRENT_AUTH_SUBJECT",
    dossiers: null,
    intake: "dossier workspace and mixed Website/SDF intake projections",
    finance: null,
    workforce: null,
    recruitment: null,
    messages: null,
    calendar: null,
  };
  assert.deepEqual(OPERATOR_MODULE_DESCRIPTORS.map(({ moduleKey })=>moduleKey), Object.keys(expected));
  for (const [moduleKey, blocker] of Object.entries(expected)) {
    const descriptor = getOperatorModuleDescriptor(moduleKey);
    assert.ok(descriptor);
    assert.equal(Boolean(resolveStandaloneOperatorModule(moduleKey)), ["messages", "calendar", "recruitment", "workforce", "finance", "dossiers"].includes(moduleKey));
    if (blocker) assert.match(descriptor.blockReason, new RegExp(blocker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
    else assert.equal(descriptor.blockReason, null);
  }
});

test("enabled descriptors always carry standalone lifecycle and server authority metadata", ()=>{
  const enabled = OPERATOR_MODULE_DESCRIPTORS.filter(({ multiScreenAllowed })=>multiScreenAllowed);
  assert.deepEqual(enabled.map(({ moduleKey })=>moduleKey).sort(), ["calendar", "dossiers", "finance", "messages", "recruitment", "workforce"]);
  for (const descriptor of enabled) {
    assert.equal(descriptor.standaloneAllowed, true);
    assert.equal(descriptor.desktopMultiWindowAllowed, true);
    assert.equal(descriptor.singletonPolicy, "module-slot");
    assert.ok(descriptor.initializer);
    assert.ok(descriptor.serverAuthority);
  }
});

test("server allowlist remains final authority and cannot be expanded by registry metadata", async ()=>{
  const authority = await read("supabase/migrations/20260902250000_add_operator_dossiers_multiscreen_v1.sql");
  assert.match(authority, /v_module_key not in \('messages', 'calendar', 'recruitment', 'workforce', 'finance', 'dossiers'\)/);
  assert.match(authority, /when 'recruitment' then p_role = 'owner'/);
  assert.match(authority, /when 'workforce' then p_role in \('owner', 'admin', 'operations_manager'\)/);
  assert.match(authority, /when 'finance' then p_role = 'owner'/);
  assert.match(authority, /when 'dossiers' then p_role = 'owner'/);
  assert.match(authority, /operator_workspace_module_authorized_v1/);
  assert.match(authority, /WORKSPACE_MODULE_NOT_AUTHORIZED/);
  assert.match(authority, /WORKSPACE_MODULE_NOT_ENABLED/);
});

test("generic module and slot keys reject path, query, uppercase, and oversized input", ()=>{
  assert.equal(validOperatorModuleKey("messages"), true);
  assert.equal(validOperatorSlotKey("secondary-2"), true);
  for (const invalid of ["", "Messages", "../messages", "main?role=owner", `a${"b".repeat(48)}`]) {
    assert.equal(validOperatorModuleKey(invalid), false);
    assert.equal(validOperatorSlotKey(invalid), false);
  }
});

test("generic host disposes module activity before clearing sensitive DOM", ()=>{
  const order = [];
  const shell = { hidden: false };
  const gate = { hidden: false };
  const locked = { hidden: true, dataset: {} };
  const sensitiveContent = { replaceChildren() { order.push("clear"); } };
  const host = createOperatorWindowHost({ gate, locked, shell, sensitiveContent });
  host.setModuleController({ dispose() { order.push("dispose"); } });
  host.lock("ROLE_CHANGED");
  host.lock("ROLE_CHANGED");
  assert.deepEqual(order, ["dispose", "clear", "clear"]);
  assert.equal(shell.hidden, true);
  assert.equal(gate.hidden, true);
  assert.equal(locked.hidden, false);
  assert.equal(locked.dataset.reason, "ROLE_CHANGED");
});

test("generic host requires every mounted module to expose cleanup", ()=>{
  const host = createOperatorWindowHost({ sensitiveContent: { replaceChildren() {} } });
  assert.throws(()=>host.setModuleController({}), /OPERATOR_MODULE_DISPOSE_REQUIRED/);
});

test("workspace events are scoped hints with no role permission token or business payload", ()=>{
  const event = createWorkspaceEvent({ type: "HEARTBEAT", workspaceId, epoch, senderWindowId: masterWindowId, sequence: 7, now: 10_000 });
  assert.equal(validWorkspaceEvent(event, { workspaceId, epoch }), true);
  assert.deepEqual(Object.keys(event).sort(), ["epoch", "senderWindowId", "sequence", "timestamp", "type", "workspaceId"]);
  assert.equal(validWorkspaceEvent({ ...event, role: "owner" }, { workspaceId, epoch }), false);
  assert.equal(validWorkspaceEvent({ ...event, workspaceId: childWindowId }, { workspaceId, epoch }), false);
  assert.equal(validWorkspaceEvent({ ...event, sequence: 6 }, { workspaceId, epoch, minimumSequence: 7 }), false);
});

test("server expiry is the hard child lock deadline even after forged local heartbeats", ()=>{
  const lease = { leaseExpiresAt: 25_000 };
  assert.equal(shouldLockForLease({ ...lease, now: 24_999, serverReachable: false }), false);
  assert.equal(shouldLockForLease({ ...lease, now: 25_000, serverReachable: false }), true);
  assert.equal(shouldLockForLease({ ...lease, now: 20_000, serverReachable: true, serverValid: false }), true);
});

test("generic child shell mounts registered modules only after independent authority checks", async ()=>{
  const [html, guard, dashboardGuard, registry, messages, css] = await Promise.all([
    read("operator/window/index.html"),
    read("assets/js/operator-window-guard.mjs"),
    read("assets/js/operator-dashboard-guard.mjs"),
    read("assets/js/operator-module-registry.mjs"),
    read("assets/js/operator-messages.mjs"),
    read("assets/css/operator-window.css"),
  ]);
  assert.match(html, /lorenzo-web-solution-logo-transparent\.png/);
  assert.match(html, /id="operatorWindowLocked"/);
  assert.match(html, /id="operatorModuleTemplate-messages"/);
  assert.match(html, /id="operatorModuleTemplate-calendar"/);
  assert.match(html, /id="operatorModuleTemplate-recruitment"/);
  assert.match(html, /id="operatorModuleTemplate-workforce"/);
  assert.match(html, /id="recruitmentVacancyDialog"/);
  assert.match(html, /id="recruitmentVacancyStatusDialog"/);
  assert.match(html, /id="recruitmentPublicationDialog"/);
  assert.match(html, /id="operatorWindowSensitiveContent" class="operator-window-main"><\/main>/);
  assert.match(guard, /requireAuthorizedOperator/);
  assert.match(guard, /get_current_operator_identity_v1/);
  assert.match(guard, /join_operator_workspace_v1/);
  assert.match(guard, /resolveStandaloneOperatorModule/);
  assert.match(guard, /mountStandaloneOperatorModule/);
  assert.match(guard, /onAuthorizationFailure: \(\)=>childCoordinator\.lock\("WORKSPACE_MODULE_NOT_AUTHORIZED"\)/);
  assert.match(guard, /p_slot_key/);
  assert.match(dashboardGuard, /createOperatorWorkspaceMaster/);
  assert.match(dashboardGuard, /shutdownWorkspace/);
  assert.match(dashboardGuard, /pushState\(window\.history\.state/);
  assert.match(dashboardGuard, /pagehide", \(\)=>workspaceMaster\?\.dispose\(\)/);
  assert.doesNotMatch(dashboardGuard, /pagehide[^\n]*shutdownWorkspace/);
  assert.match(dashboardGuard, /clearOperatorWorkspaceResumeHint\(window\.history\)[\s\S]*shutdownWorkspace/);
  assert.match(registry, /initializeOperatorMessages/);
  assert.match(registry, /initializeOperatorCalendar/);
  assert.match(registry, /initializeOperatorRecruitment/);
  assert.match(registry, /initializeOperatorWorkforce/);
  assert.match(messages, /onInvalidate/);
  assert.match(css, /operator-window-lock/);
});

test("workspace browser modules persist no authority in Web Storage", async ()=>{
  const sources = await Promise.all([
    read("assets/js/operator-workspace-protocol.mjs"),
    read("assets/js/operator-workspace-master.mjs"),
    read("assets/js/operator-workspace-child.mjs"),
    read("assets/js/operator-window-guard.mjs"),
  ]);
  for (const source of sources) assert.doesNotMatch(source, /localStorage|sessionStorage|windowObject\.name|access_token|refresh_token/);
});

test("explicit shutdown locks and attempts close synchronously", ()=>{
  const harness = childHarness();
  harness.channel.emit(createWorkspaceEvent({ type: "SHUTDOWN", workspaceId, epoch, senderWindowId: masterWindowId, sequence: 1, now: 10_001 }));
  assert.equal(harness.child.active, false);
  assert.deepEqual(harness.locks, ["WORKSPACE_SHUTDOWN"]);
  assert.equal(harness.windowObject.closed, true);
});

test("server revoke response locks the child independently of heartbeat", async ()=>{
  const harness = childHarness({ rpc: async()=>({ data: { valid: false, status: "REVOKED" }, error: null }) });
  await harness.child.verifyServerLease();
  assert.equal(harness.child.active, false);
  assert.deepEqual(harness.locks, ["WORKSPACE_NOT_ACTIVE"]);
});

test("silent master plus unreachable server locks at the confirmed lease deadline", async ()=>{
  const harness = childHarness({ rpc: async()=>({ data: null, error: { message: "Failed to fetch" } }) });
  harness.setNow(25_000);
  await harness.timers.timer(CHILD_SERVER_CHECK_INTERVAL_MS).callback();
  assert.equal(harness.child.active, false);
  assert.deepEqual(harness.locks, ["WORKSPACE_UNVERIFIABLE"]);
});

test("master tolerates a temporary transport failure only inside its confirmed lease", async ()=>{
  FakeBroadcastChannel.instances = [];
  const timers = timerHarness();
  const invalidations = [];
  let nowValue = 10_000;
  let renewResult = { data: null, error: { message: "Failed to fetch" } };
  const client = { rpc: async (name)=>name === "acquire_operator_workspace_v1"
    ? { data: { acquired: true, workspace_id: workspaceId, epoch, renewal_token: launchNonce, lease_expires_at: new Date(25_000).toISOString() }, error: null }
    : renewResult };
  const ids = [masterWindowId, childWindowId];
  const master = await createOperatorWorkspaceMaster({
    client,
    windowObject: { BroadcastChannel: FakeBroadcastChannel, crypto: { randomUUID: ()=>ids.shift() }, location: { origin: "https://operator.local" }, open() { return null; } },
    navigatorObject: availableWebLock(),
    now: ()=>nowValue,
    setIntervalFn: timers.setIntervalFn,
    clearIntervalFn: timers.clearIntervalFn,
    onInvalidWorkspace: (reason)=>invalidations.push(reason),
  });
  await timers.timer(MASTER_SERVER_RENEWAL_INTERVAL_MS).callback();
  assert.deepEqual(invalidations, []);
  nowValue = 25_000;
  timers.timer(1_000).callback();
  assert.deepEqual(invalidations, ["MASTER_LEASE_EXPIRED"]);
  assert.equal(master.openOperatorModuleWindow("messages"), false);
});

test("master authority failure locks immediately without waiting for lease expiry", async ()=>{
  FakeBroadcastChannel.instances = [];
  const timers = timerHarness();
  const invalidations = [];
  const ids = [masterWindowId, childWindowId];
  const client = { rpc: async (name)=>name === "acquire_operator_workspace_v1"
    ? { data: { acquired: true, workspace_id: workspaceId, epoch, renewal_token: launchNonce, lease_expires_at: new Date(25_000).toISOString() }, error: null }
    : { data: null, error: { code: "42501", message: "OPERATOR_NOT_ACTIVE" } } };
  await createOperatorWorkspaceMaster({
    client,
    windowObject: { BroadcastChannel: FakeBroadcastChannel, crypto: { randomUUID: ()=>ids.shift() }, location: { origin: "https://operator.local" }, open() { return null; } },
    navigatorObject: availableWebLock(),
    now: ()=>10_000,
    setIntervalFn: timers.setIntervalFn,
    clearIntervalFn: timers.clearIntervalFn,
    onInvalidWorkspace: (reason)=>invalidations.push(reason),
  });
  await timers.timer(MASTER_SERVER_RENEWAL_INTERVAL_MS).callback();
  assert.deepEqual(invalidations, ["MASTER_RENEWAL_FAILED"]);
});

test("master fails closed when Web Locks cannot enforce singleton ownership", async ()=>{
  const master = await createOperatorWorkspaceMaster({
    navigatorObject: {},
    windowObject: {},
    client: { rpc: async()=>assert.fail("server acquisition must not run") },
  });
  assert.equal(master.active, false);
  assert.equal(master.reason, "LOCAL_MASTER_EXISTS");
  assert.doesNotThrow(()=>{
    master.bindModuleButton();
    master.dispose();
    master.invalidate("dossiers");
    master.lockWorkspace("AUTH_SIGNED_OUT");
    master.unbindModuleButton();
  });
  assert.equal(master.openOperatorModuleWindow("dossiers"), false);
  assert.equal(await master.shutdownWorkspace(), false);
});

test("a denied Web Lock prevents duplicate server acquisition", async ()=>{
  let acquisitionCalls = 0;
  const master = await createOperatorWorkspaceMaster({
    navigatorObject: { locks: { request(_name, _options, callback) { return Promise.resolve(callback(null)); } } },
    windowObject: {},
    client: { rpc: async()=>{ acquisitionCalls += 1; } },
  });
  assert.equal(master.active, false);
  assert.equal(master.reason, "LOCAL_MASTER_EXISTS");
  assert.equal(acquisitionCalls, 0);
});

test("a second launch focuses the managed child without opening a duplicate", async ()=>{
  FakeBroadcastChannel.instances = [];
  const timers = timerHarness();
  const ids = [masterWindowId, childWindowId, launchNonce];
  let openCalls = 0;
  let focusCalls = 0;
  const childReference = { closed: false, focus() { focusCalls += 1; } };
  const master = await createOperatorWorkspaceMaster({
    client: { rpc: async()=>({ data: { acquired: true, workspace_id: workspaceId, epoch, renewal_token: launchNonce, lease_expires_at: new Date(25_000).toISOString() }, error: null }) },
    windowObject: {
      BroadcastChannel: FakeBroadcastChannel,
      crypto: { randomUUID: ()=>ids.shift() },
      location: { origin: "https://operator.local" },
      open() { openCalls += 1; return childReference; },
    },
    navigatorObject: availableWebLock(),
    now: ()=>10_000,
    setIntervalFn: timers.setIntervalFn,
    clearIntervalFn: timers.clearIntervalFn,
  });
  assert.equal(master.openOperatorModuleWindow("messages", "main"), true);
  assert.equal(master.openOperatorModuleWindow("messages", "main"), true);
  assert.equal(master.openOperatorModuleWindow("intake", "main"), false);
  assert.equal(openCalls, 1);
  assert.equal(focusCalls, 2);
});

test("remounted module launch controls are bound once and release detached listeners", async ()=>{
  FakeBroadcastChannel.instances = [];
  const timers = timerHarness();
  const ids = [masterWindowId];
  const listeners = new Set();
  const button = {
    hidden: true,
    disabled: true,
    addEventListener(_type, listener) { listeners.add(listener); },
    removeEventListener(_type, listener) { listeners.delete(listener); },
  };
  const master = await createOperatorWorkspaceMaster({
    client: { rpc: async()=>({ data: { acquired: true, workspace_id: workspaceId, epoch, renewal_token: launchNonce, lease_expires_at: new Date(25_000).toISOString() }, error: null }) },
    windowObject: {
      BroadcastChannel: FakeBroadcastChannel,
      crypto: { randomUUID: ()=>ids.shift() },
      location: { origin: "https://operator.local" },
      open() { return null; },
    },
    navigatorObject: availableWebLock(),
    now: ()=>10_000,
    setIntervalFn: timers.setIntervalFn,
    clearIntervalFn: timers.clearIntervalFn,
  });
  master.bindModuleButton(button, "dossiers", "main");
  master.bindModuleButton(button, "dossiers", "main");
  assert.equal(listeners.size, 1);
  assert.equal(button.hidden, false);
  assert.equal(button.disabled, false);
  assert.equal(master.unbindModuleButton(button), true);
  assert.equal(master.unbindModuleButton(button), false);
  assert.equal(listeners.size, 0);
});

test("master manages all six required modules as separate children in one workspace", async ()=>{
  FakeBroadcastChannel.instances = [];
  const timers = timerHarness();
  const ids = [
    masterWindowId,
    childWindowId,
    launchNonce,
    "f4000000-0000-4000-8000-000000000005",
    "f4000000-0000-4000-8000-000000000006",
    "f4000000-0000-4000-8000-000000000007",
    "f4000000-0000-4000-8000-000000000008",
    "f4000000-0000-4000-8000-000000000009",
    "f4000000-0000-4000-8000-000000000010",
    "f4000000-0000-4000-8000-000000000011",
    "f4000000-0000-4000-8000-000000000012",
    "f4000000-0000-4000-8000-000000000013",
    "f4000000-0000-4000-8000-000000000014",
  ];
  const opened = [];
  const references = [];
  const client = { rpc: async (name)=>name === "revoke_operator_workspace_v1"
    ? { data: { revoked: true }, error: null }
    : { data: { acquired: true, workspace_id: workspaceId, epoch, renewal_token: launchNonce, lease_expires_at: new Date(25_000).toISOString() }, error: null } };
  const master = await createOperatorWorkspaceMaster({
    client,
    windowObject: {
      BroadcastChannel: FakeBroadcastChannel,
      crypto: { randomUUID: ()=>ids.shift() },
      location: { origin: "https://operator.local" },
      open(href, name) {
        opened.push({ url: new URL(href), name });
        const reference = { closed: false, focusCalls: 0, focus() { this.focusCalls += 1; }, close() { this.closed = true; } };
        references.push(reference);
        return reference;
      },
    },
    navigatorObject: availableWebLock(),
    now: ()=>10_000,
    setIntervalFn: timers.setIntervalFn,
    clearIntervalFn: timers.clearIntervalFn,
  });

  assert.equal(master.openOperatorModuleWindow("messages"), true);
  assert.equal(master.openOperatorModuleWindow("calendar"), true);
  assert.equal(master.openOperatorModuleWindow("recruitment"), true);
  assert.equal(master.openOperatorModuleWindow("workforce"), true);
  assert.equal(master.openOperatorModuleWindow("finance"), true);
  assert.equal(master.openOperatorModuleWindow("finance"), true);
  assert.equal(master.openOperatorModuleWindow("dossiers"), true);
  assert.equal(master.openOperatorModuleWindow("dossiers"), true);
  assert.equal(opened.length, 6);
  assert.deepEqual(opened.map(({ url })=>url.searchParams.get("module")), ["messages", "calendar", "recruitment", "workforce", "finance", "dossiers"]);
  assert.equal(opened.every(({ url })=>parseChildBootstrap(url)?.workspaceId === workspaceId), true);
  assert.equal(opened.every(({ url })=>!url.searchParams.has("role") && !url.searchParams.has("token")), true);
  assert.equal(new Set(opened.map(({ name })=>name)).size, 6);
  assert.equal(references[5].focusCalls, 2);

  assert.equal(await master.shutdownWorkspace(), true);
  assert.deepEqual(references.map(({ closed })=>closed), [true, true, true, true, true, true]);
});

test("child status verification never invokes the master renewal authority", async ()=>{
  const calls = [];
  const harness = childHarness({ rpc: async (name)=>{
    calls.push(name);
    return { data: { valid: true, lease_expires_at: new Date(25_000).toISOString() }, error: null };
  } });
  await harness.child.verifyServerLease();
  assert.deepEqual(calls, ["get_operator_workspace_status_v1"]);
});

test("forged local authority payload cannot trigger status or renewal RPCs", ()=>{
  const calls = [];
  const harness = childHarness({ rpc: async (name)=>{ calls.push(name); return { data: null, error: null }; } });
  harness.channel.emit({
    ...createWorkspaceEvent({ type: "HEARTBEAT", workspaceId, epoch, senderWindowId: masterWindowId, sequence: 1, now: 10_001 }),
    role: "owner",
    token: launchNonce,
  });
  assert.deepEqual(calls, []);
  assert.equal(harness.child.active, true);
});

test("auth signout locks the managed child immediately", ()=>{
  let authStateChange;
  let unsubscribed = false;
  const harness = childHarness();
  const stopWatching = watchOperatorSession({
    auth: {
      onAuthStateChange(callback) {
        authStateChange = callback;
        return { data: { subscription: { unsubscribe() { unsubscribed = true; } } } };
      },
    },
  }, ()=>{}, ()=>harness.child.lock("AUTH_SIGNED_OUT"));
  authStateChange("SIGNED_OUT", null);
  assert.equal(harness.child.active, false);
  assert.deepEqual(harness.locks, ["AUTH_SIGNED_OUT"]);
  stopWatching();
  assert.equal(unsubscribed, true);
});

test("BroadcastChannel cannot authorize or invalidate a blocked module", async ()=>{
  FakeBroadcastChannel.instances = [];
  const timers = timerHarness();
  const invalidations = [];
  const ids = [masterWindowId];
  const master = await createOperatorWorkspaceMaster({
    client: { rpc: async()=>({ data: { acquired: true, workspace_id: workspaceId, epoch, renewal_token: launchNonce, lease_expires_at: new Date(25_000).toISOString() }, error: null }) },
    windowObject: { BroadcastChannel: FakeBroadcastChannel, crypto: { randomUUID: ()=>ids.shift() }, location: { origin: "https://operator.example" }, open: ()=>assert.fail("blocked module must not open") },
    navigatorObject: availableWebLock(),
    now: ()=>10_000,
    setIntervalFn: timers.setIntervalFn,
    clearIntervalFn: timers.clearIntervalFn,
    onInvalidate: (moduleKey)=>invalidations.push(moduleKey),
  });
  const channel = FakeBroadcastChannel.instances[0];
  channel.emit(createWorkspaceEvent({ type: "INVALIDATE", workspaceId, epoch, senderWindowId: childWindowId, sequence: 1, now: 10_001, moduleKey: "intake", slotKey: "main" }));
  assert.deepEqual(invalidations, []);
  assert.equal(master.openOperatorModuleWindow("intake"), false);
});

test("shutdown locks every managed child sharing the workspace", ()=>{
  const first = childHarness();
  const second = childHarness();
  const third = childHarness();
  const fourth = childHarness();
  const shutdown = createWorkspaceEvent({ type: "SHUTDOWN", workspaceId, epoch, senderWindowId: masterWindowId, sequence: 1, now: 10_001 });
  first.channel.emit(shutdown);
  second.channel.emit(shutdown);
  third.channel.emit(shutdown);
  fourth.channel.emit(shutdown);
  assert.deepEqual([first.locks, second.locks, third.locks, fourth.locks], [["WORKSPACE_SHUTDOWN"], ["WORKSPACE_SHUTDOWN"], ["WORKSPACE_SHUTDOWN"], ["WORKSPACE_SHUTDOWN"]]);
  assert.equal(first.windowObject.closed && second.windowObject.closed && third.windowObject.closed && fourth.windowObject.closed, true);
});

test("master crash expiry locks every managed child independently", async ()=>{
  const rpc = async()=>({ data: null, error: { message: "Failed to fetch" } });
  const first = childHarness({ nowValue: 25_000, rpc });
  const second = childHarness({ nowValue: 25_000, rpc });
  const third = childHarness({ nowValue: 25_000, rpc });
  const fourth = childHarness({ nowValue: 25_000, rpc });
  await Promise.all([first.child.verifyServerLease(), second.child.verifyServerLease(), third.child.verifyServerLease(), fourth.child.verifyServerLease()]);
  assert.deepEqual([first.locks, second.locks, third.locks, fourth.locks], [["WORKSPACE_UNVERIFIABLE"], ["WORKSPACE_UNVERIFIABLE"], ["WORKSPACE_UNVERIFIABLE"], ["WORKSPACE_UNVERIFIABLE"]]);
});

test("mobile hides every generic managed-window launcher", async ()=>{
  const css = await read("assets/css/operator-messages.css");
  assert.match(css, /@media \(max-width:640px\)[\s\S]*\[data-operator-window-module\] \{ display:none; \}/);
  assert.doesNotMatch(css, /#messagesOpenWindow \{ display:none; \}/);
});

test("multi-screen runtime remains origin-relative and production portable", async ()=>{
  const sources = await Promise.all([
    read("assets/js/operator-module-registry.mjs"),
    read("assets/js/operator-workspace-protocol.mjs"),
    read("assets/js/operator-workspace-master.mjs"),
    read("assets/js/operator-workspace-child.mjs"),
    read("assets/js/operator-window-guard.mjs"),
  ]);
  for (const source of sources) assert.doesNotMatch(source, /127\.0\.0\.1|localhost|Mailpit|Playwright|SUPABASE_SERVICE_ROLE_KEY/);
});

test("master refresh hint survives only in history state and contains no authority capability", ()=>{
  const historyObject = {
    state: { unrelated: true },
    replaceState(state) { this.state = state; },
  };
  const hint = operatorWorkspaceResumeHint({ workspaceId, epoch, masterWindowId });
  assert.deepEqual(hint, { workspaceId, epoch, masterWindowId });
  assert.equal(writeOperatorWorkspaceResumeHint(historyObject, hint), true);
  assert.deepEqual(readOperatorWorkspaceResumeHint(historyObject), hint);
  assert.deepEqual(Object.keys(readOperatorWorkspaceResumeHint(historyObject)).sort(), ["epoch", "masterWindowId", "workspaceId"]);
  assert.equal(JSON.stringify(historyObject.state).includes("token"), false);
  assert.equal(operatorWorkspaceResumeHint({ ...hint, renewalToken: launchNonce }), null);
  assert.equal(clearOperatorWorkspaceResumeHint(historyObject), true);
  assert.equal(readOperatorWorkspaceResumeHint(historyObject), null);
  assert.equal(historyObject.state.unrelated, true);
});

test("master refresh resumes the same workspace without locking children or acquiring a second epoch", async ()=>{
  FakeBroadcastChannel.instances = [];
  const timers = timerHarness();
  const nextMasterWindowId = "f4000000-0000-4000-8000-000000000005";
  const calls = [];
  const client = { rpc: async (name, parameters)=>{
    calls.push({ name, parameters });
    if (name !== "resume_operator_workspace_v1") assert.fail(`unexpected RPC ${name}`);
    return { data: {
      resumed: true,
      workspace_id: workspaceId,
      epoch,
      master_window_id: nextMasterWindowId,
      renewal_token: launchNonce,
      lease_expires_at: new Date(25_000).toISOString(),
    }, error: null };
  } };
  const master = await createOperatorWorkspaceMaster({
    client,
    resumeHint: { workspaceId, epoch, masterWindowId },
    windowObject: {
      BroadcastChannel: FakeBroadcastChannel,
      crypto: { randomUUID: ()=>nextMasterWindowId },
      location: { origin: "https://operator.local" },
      open() { return null; },
    },
    navigatorObject: availableWebLock(),
    now: ()=>10_000,
    setIntervalFn: timers.setIntervalFn,
    clearIntervalFn: timers.clearIntervalFn,
  });
  assert.equal(master.active, true);
  assert.equal(master.resumed, true);
  assert.equal(master.workspaceId, workspaceId);
  assert.deepEqual(master.resumeHint, { workspaceId, epoch, masterWindowId: nextMasterWindowId });
  assert.deepEqual(calls.map(({ name })=>name), ["resume_operator_workspace_v1"]);
  master.dispose();
  assert.equal(master.active, false);
  assert.equal(FakeBroadcastChannel.instances[0].messages.some(({ type })=>type === "LOCK" || type === "SHUTDOWN"), false);
});

test("workspace occupancy status distinguishes active, occupied, and failed acquisition", ()=>{
  const status = { hidden: true, textContent: "" };
  const present = createOperatorWorkspaceStatusPresenter(status);
  present("active");
  assert.deepEqual(status, { hidden: true, textContent: "" });
  present("occupied");
  assert.deepEqual(status, { hidden: false, textContent: OPERATOR_WORKSPACE_OCCUPIED_MESSAGE });
  present("unavailable");
  assert.deepEqual(status, { hidden: true, textContent: "" });
});

test("existing master occupancy is announced once without activating launch controls", async ()=>{
  const states = [];
  const button = { hidden: true, disabled: false, addEventListener() {} };
  const master = await createOperatorWorkspaceMaster({
    client: { rpc: async()=>({ data: { acquired: false, lease_expires_at: new Date(10_000).toISOString() }, error: null }) },
    navigatorObject: availableWebLock(),
    windowObject: { crypto: { randomUUID: ()=>masterWindowId } },
    now: ()=>10_000,
    setTimeoutFn: async (callback)=>callback(),
    onAvailabilityChange: (state)=>states.push(state),
  });
  master.bindModuleButton(button, "messages");
  assert.equal(master.active, false);
  assert.equal(master.reason, "SERVER_MASTER_EXISTS");
  assert.deepEqual(states, ["occupied"]);
  assert.equal(button.hidden, true);
});

test("normal occupied to acquired transition clears status and preserves launcher binding", async ()=>{
  const states = [];
  let calls = 0;
  const listeners = [];
  const button = { hidden: true, disabled: true, addEventListener(_type, listener) { listeners.push(listener); } };
  const master = await createOperatorWorkspaceMaster({
    client: { rpc: async()=>++calls === 1
      ? { data: { acquired: false, lease_expires_at: new Date(10_000).toISOString() }, error: null }
      : { data: { acquired: true, workspace_id: workspaceId, epoch, renewal_token: launchNonce, lease_expires_at: new Date(25_000).toISOString() }, error: null } },
    navigatorObject: availableWebLock(),
    windowObject: { BroadcastChannel: FakeBroadcastChannel, crypto: { randomUUID: ()=>masterWindowId }, location: { origin: "https://operator.local" }, open() { return null; } },
    now: ()=>10_000,
    setTimeoutFn: async (callback)=>callback(),
    onAvailabilityChange: (state)=>states.push(state),
  });
  master.bindModuleButton(button, "messages");
  assert.deepEqual(states, ["occupied", "active"]);
  assert.equal(master.active, true);
  assert.equal(button.hidden, false);
  assert.equal(button.disabled, false);
  assert.equal(listeners.length, 1);
});

test("technical acquisition failure never presents another-window occupancy", async ()=>{
  const states = [];
  const master = await createOperatorWorkspaceMaster({
    client: { rpc: async()=>({ data: null, error: { message: "Failed to fetch" } }) },
    navigatorObject: availableWebLock(),
    windowObject: { crypto: { randomUUID: ()=>masterWindowId } },
    onAvailabilityChange: (state)=>states.push(state),
  });
  assert.equal(master.reason, "WORKSPACE_ACQUIRE_FAILED");
  assert.deepEqual(states, ["unavailable"]);
});

test("dashboard exposes one responsive live Multi-Screen occupancy status for every module", async ()=>{
  const [html, css, guard] = await Promise.all([
    read("operator/dashboard/index.html"),
    read("assets/css/operator-dashboard.css"),
    read("assets/js/operator-dashboard-guard.mjs"),
  ]);
  assert.equal((html.match(/id="operatorMultiScreenStatus"/g) || []).length, 1);
  assert.match(html, /id="operatorMultiScreenStatus"[^>]*role="status"[^>]*aria-live="polite"[^>]*aria-atomic="true"[^>]*hidden/);
  assert.match(css, /\.operator-workspace-status \{[^}]*overflow-wrap:anywhere/);
  assert.match(css, /@media \(max-width:700px\)[^{]*\{[^}]*\.workspace,\.operator-workspace-status/);
  assert.match(guard, /onAvailabilityChange: presentWorkspaceStatus/);
});