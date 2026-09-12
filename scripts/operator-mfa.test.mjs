import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  MFA_OPERATOR_SUBJECTS,
  createOperatorMfaDialog,
  createOperatorMfaService,
  isMfaOperatorSubject,
  mountOperatorAal2VerificationButton,
} from "../assets/js/operator-mfa.mjs";

function clientFor(subject, { level = "aal1", factors = [] } = {}) {
  const calls = [];
  let currentLevel = level;
  return {
    calls,
    client: {
      auth: {
        getSession: async () => ({ data: { session: { user: { id: subject } } }, error: null }),
        mfa: {
          getAuthenticatorAssuranceLevel: async () => ({ data: { currentLevel }, error: null }),
          listFactors: async () => ({ data: { totp: factors }, error: null }),
          enroll: async () => ({ data: { id: "factor-1", totp: { qr_code: "data:image/svg+xml,test" } }, error: null }),
          challenge: async (input) => { calls.push(["challenge", input]); return { data: { id: "challenge-1" }, error: null }; },
          verify: async (input) => { calls.push(["verify", input]); currentLevel = "aal2"; return { data: {}, error: null }; },
          unenroll: async (input) => { calls.push(["unenroll", input]); return { data: {}, error: null }; },
        },
      },
    },
  };
}

function dialogDocument() {
  const createNode = () => ({
    dataset: {},
    disabled: false,
    hidden: false,
    open: false,
    textContent: "",
    value: "",
    listeners: new Map(),
    addEventListener(type, listener) { this.listeners.set(type, listener); },
    focus() {},
    removeAttribute(name) { delete this[name]; },
  });
  const selectors = [
    "[data-operator-mfa-form]",
    "[data-operator-mfa-title]",
    "[data-operator-mfa-description]",
    "[data-operator-mfa-qr-wrap]",
    "[data-operator-mfa-qr]",
    "[data-operator-mfa-code]",
    "[data-operator-mfa-message]",
    "[data-operator-mfa-submit]",
    "[data-operator-mfa-cancel]",
  ];
  const nodes = Object.fromEntries(selectors.map((selector)=>[selector, createNode()]));
  const dialog = createNode();
  dialog.querySelector = (selector)=>nodes[selector];
  dialog.showModal = ()=>{ dialog.open = true; };
  dialog.close = ()=>{ dialog.open = false; };
  const status = createNode();
  status.children = [];
  status.querySelector = (selector)=>status.children.find((node)=>selector === "[data-operator-mfa-verify]" && "operatorMfaVerify" in node.dataset) || null;
  status.prepend = (node)=>status.children.unshift(node);
  const documentObject = {
    body: { append() {} },
    createElement(tagName) {
      if (tagName !== "div") return createNode();
      const host = {};
      Object.defineProperty(host, "innerHTML", { set() { host.firstElementChild = dialog; } });
      return host;
    },
    querySelector: (selector)=>selector === ".topbar__status" ? status : null,
  };
  return {
    dialog,
    documentObject,
    nodes,
    dispatch: (selector, type, event = {})=>nodes[selector].listeners.get(type)?.(event),
  };
}

test("only OP-01 and OP-02 are MFA eligible", () => {
  assert.equal(isMfaOperatorSubject(MFA_OPERATOR_SUBJECTS[0]), true);
  assert.equal(isMfaOperatorSubject(MFA_OPERATOR_SUBJECTS[1]), true);
  assert.equal(isMfaOperatorSubject("d0247fd9-60d5-40bc-a905-6b02024b6420"), false);
});

for (const subject of MFA_OPERATOR_SUBJECTS) {
  test(`${subject} can enroll, challenge, verify, and reach aal2`, async () => {
    const harness = clientFor(subject);
    const service = createOperatorMfaService(harness.client);
    assert.equal((await service.startEnrollment()).status, "pending");
    assert.equal((await service.verifyEnrollment("123456")).currentLevel, "aal2");
    assert.deepEqual(harness.calls.map(([name])=>name), ["challenge", "verify"]);
  });
}

for (const subject of MFA_OPERATOR_SUBJECTS) {
  test(`${subject} aal1 step-up challenges a verified factor and verifies aal2`, async () => {
    const harness = clientFor(subject, {
      factors: [{ id: "verified-factor", status: "verified" }],
    });
    const service = createOperatorMfaService(harness.client);
    assert.equal((await service.startStepUp()).status, "challenge");
    assert.equal((await service.verifyStepUp("654321")).currentLevel, "aal2");
  });
}

test("aal1 step-up without a verified factor fails closed without enrollment", async () => {
  const harness = clientFor(MFA_OPERATOR_SUBJECTS[0]);
  const service = createOperatorMfaService(harness.client);
  assert.equal((await service.startStepUp()).status, "enrollment_required");
  assert.deepEqual(harness.calls, []);
});

test("failed and cancelled step-up attempts clear temporary challenge state", async () => {
  const harness = clientFor(MFA_OPERATOR_SUBJECTS[0], {
    factors: [{ id: "verified-factor", status: "verified" }],
  });
  const service = createOperatorMfaService(harness.client);
  assert.equal((await service.startStepUp()).status, "challenge");
  await assert.rejects(service.verifyStepUp("invalid"), /MFA_CODE_INVALID/);
  await assert.rejects(service.verifyStepUp("654321"), /MFA_CODE_INVALID/);

  assert.equal((await service.startStepUp()).status, "challenge");
  service.cancelStepUp();
  await assert.rejects(service.verifyStepUp("654321"), /MFA_CODE_INVALID/);
  assert.deepEqual(harness.calls.map(([name])=>name), ["challenge", "challenge"]);
});

test("standalone AAL2 verification challenges, verifies, and returns only success", async () => {
  const harness = clientFor(MFA_OPERATOR_SUBJECTS[0], {
    factors: [{ id: "verified-factor", status: "verified" }],
  });
  const ui = dialogDocument();
  const controller = createOperatorMfaDialog({ client: harness.client, documentObject: ui.documentObject });
  const verification = controller.verifyAal2Only();
  await new Promise(setImmediate);
  assert.equal(ui.dialog.open, true);
  ui.nodes["[data-operator-mfa-code]"].value = "654321";
  await ui.dispatch("[data-operator-mfa-form]", "submit", { preventDefault() {} });
  assert.equal(await verification, true);
  assert.deepEqual(harness.calls.map(([name])=>name), ["challenge", "verify"]);
  assert.equal(ui.nodes["[data-operator-mfa-code]"].value, "");
});

test("standalone AAL2 verification passes directly when assurance is already aal2", async () => {
  const harness = clientFor(MFA_OPERATOR_SUBJECTS[0], { level: "aal2" });
  const ui = dialogDocument();
  const controller = createOperatorMfaDialog({ client: harness.client, documentObject: ui.documentObject });
  assert.equal(await controller.verifyAal2Only(), true);
  assert.equal(ui.dialog.open, false);
  assert.deepEqual(harness.calls, []);
});

test("standalone AAL2 verification fails closed without enrollment and blocks concurrent flows", async () => {
  const missingFactorHarness = clientFor(MFA_OPERATOR_SUBJECTS[0]);
  const missingFactorController = createOperatorMfaDialog({ client: missingFactorHarness.client, documentObject: dialogDocument().documentObject });
  await assert.rejects(missingFactorController.verifyAal2Only(), /MFA_VERIFIED_FACTOR_REQUIRED/);
  assert.deepEqual(missingFactorHarness.calls, []);

  const harness = clientFor(MFA_OPERATOR_SUBJECTS[0], { factors: [{ id: "verified-factor", status: "verified" }] });
  const ui = dialogDocument();
  const controller = createOperatorMfaDialog({ client: harness.client, documentObject: ui.documentObject });
  const first = controller.verifyAal2Only();
  await assert.rejects(controller.verifyAal2Only(), /MFA_FLOW_ACTIVE/);
  await new Promise(setImmediate);
  await ui.dispatch("[data-operator-mfa-cancel]", "click");
  await assert.rejects(first, /MFA_CANCELLED/);
  await assert.rejects(controller.service.verifyStepUp("654321"), /MFA_CODE_INVALID/);
});

test("standalone AAL2 topbar control suppresses duplicate clicks", async () => {
  const ui = dialogDocument();
  let calls = 0;
  let complete;
  const controller = { verifyAal2Only: () => { calls += 1; return new Promise((resolve)=>{ complete = resolve; }); } };
  const button = mountOperatorAal2VerificationButton({ controller, documentObject: ui.documentObject });
  const firstClick = button.listeners.get("click")();
  const secondClick = button.listeners.get("click")();
  assert.equal(calls, 1);
  complete(true);
  await Promise.all([firstClick, secondClick]);
  assert.equal(button.textContent, "AAL2 actief");
  assert.equal(mountOperatorAal2VerificationButton({ controller, documentObject: ui.documentObject }), null);
});

test("cancelled enrollment removes its unverified factor", async () => {
  const harness = clientFor(MFA_OPERATOR_SUBJECTS[0]);
  const service = createOperatorMfaService(harness.client);
  await service.startEnrollment();
  await service.cancelEnrollment();
  assert.deepEqual(harness.calls, [["unenroll", { factorId: "factor-1" }]]);
});

test("ineligible profiles cannot start enrollment", async () => {
  const harness = clientFor("d0247fd9-60d5-40bc-a905-6b02024b6420");
  await assert.rejects(createOperatorMfaService(harness.client).startEnrollment(), /MFA_OPERATOR_NOT_ELIGIBLE/);
});

test("every browser critical callsite awaits step-up before dispatch", async () => {
  const dashboard = await readFile(new URL("../assets/js/operator-dashboard.js", import.meta.url), "utf8");
  const workspace = await readFile(new URL("../assets/js/operator-workspace-master.mjs", import.meta.url), "utf8");
  assert.match(dashboard, /await requireAal2\(\);\s*const \{ data, error \} = await client\.rpc\("purge_dossier_v1"/);
  assert.match(dashboard, /await requireAal2\(\);\s*const \{ data, error \} = await client\.rpc\("purge_sdf_dossier_v1"/);
  assert.match(dashboard, /await requireAal2\(\);\s*await invoke\(buildPendingIntakeDeleteCommand/);
  assert.match(workspace, /await requireAal2\(\);[\s\S]*?client\.rpc\("revoke_operator_workspace_v1"/);
});

test("standalone AAL2 route exposes no RPC, fetch, callback, enrollment, or mutation path", async () => {
  const [mfa, guard, html] = await Promise.all([
    readFile(new URL("../assets/js/operator-mfa.mjs", import.meta.url), "utf8"),
    readFile(new URL("../assets/js/operator-dashboard-guard.mjs", import.meta.url), "utf8"),
    readFile(new URL("../operator/dashboard/index.html", import.meta.url), "utf8"),
  ]);
  const standaloneStart = mfa.indexOf("  async function verifyAal2Only() {");
  const standaloneEnd = mfa.indexOf("  form.addEventListener", standaloneStart);
  const standalone = mfa.slice(standaloneStart, standaloneEnd);
  assert.match(standalone, /service\.startStepUp\(\)/);
  assert.match(standalone, /service\.assurance\(\)/);
  assert.doesNotMatch(standalone, /enroll\(|\.rpc\(|fetch\(|callback|invoke|action/);
  assert.match(guard, /mountOperatorAal2VerificationButton\(\{ controller: mfaController \}\)/);
  assert.match(guard, /operator-mfa\.mjs\?v=20260906-aal2-standalone-r1/);
  assert.match(html, /operator-dashboard-guard\.mjs\?v=20260912-dossier-continuity-project-r1/);
});

test("database migration wraps every direct critical RPC and protects Auth UUID binding", async () => {
  const migration = await readFile(new URL("../supabase/migrations/20260904160000_require_operator_aal2_for_critical_actions_v1.sql", import.meta.url), "utf8");
  for (const rpc of [
    "purge_dossier_v1",
    "purge_sdf_dossier_v1",
    "appoint_operations_manager_v1",
    "revoke_operations_manager_v1",
    "revoke_operator_workspace_v1",
  ]) {
    assert.match(migration, new RegExp(`create function public\\.${rpc}`));
  }
  assert.equal((migration.match(/perform lws_internal\.assert_operator_aal2_v1\(\);/g) || []).length, 6);
  assert.match(migration, /before insert or update of auth_user_id on public\.commercial_operators/);
  assert.match(migration, /before insert or update of auth_user_id on public\.operator_profile_definitions/);
});