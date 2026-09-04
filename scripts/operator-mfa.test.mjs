import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  MFA_OPERATOR_SUBJECTS,
  createOperatorMfaService,
  isMfaOperatorSubject,
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