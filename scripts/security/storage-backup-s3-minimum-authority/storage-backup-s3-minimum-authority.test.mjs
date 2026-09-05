import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  ACTIVATION_STATUS,
  CURRENT_STORAGE_POLICIES,
  DEDICATED_BACKUP_IDENTITY,
  KNOWN_BUCKET_BACKUP_ROUTE,
  OPEN_OBLIGATIONS,
  POLICY_DESIGN,
  SESSION_LIFECYCLE,
  SYNTHETIC_TEST_OBJECT_PLAN,
  TEST_PLAN,
  evaluateActivationUuid,
  evaluateInheritedAuthority,
  evaluateMinimumAuthorityRoute,
  evaluatePolicyDesign,
  evaluateSessionState,
  redactSecrets,
  verifyActivationArtifacts,
} from "./storage-backup-s3-minimum-authority.mjs";

const routeVerdict = (overrides = {}) => evaluateMinimumAuthorityRoute({ ...KNOWN_BUCKET_BACKUP_ROUTE, ...overrides }).verdict;
const policyVerdict = (overrides = {}) => evaluatePolicyDesign({ ...POLICY_DESIGN, ...overrides }).verdict;

test("1 known-bucket backup route rejects bucket-enumeration authority", () => {
    assert.deepEqual(KNOWN_BUCKET_BACKUP_ROUTE.allowedOperations, ["ListObjectsV2", "GetObject"]);
    assert.equal(routeVerdict(), "ACCEPT");
    assert.equal(routeVerdict({ storageBucketsSelect: true }), "REJECT");
    assert.equal(routeVerdict({ listBucketsAllowed: true }), "REJECT");
});

  test("2 auth.uid binding is required", () => assert.equal(policyVerdict({ authUidBindingRequired: false }), "REJECT"));
  test("3 email identity binding is rejected", () => assert.equal(policyVerdict({ emailIdentityBinding: true }), "REJECT"));
  test("4 ordinary user is rejected", () => assert.equal(evaluateActivationUuid("794b68ee-3f13-4fd4-9460-99f247d4e6ab", { dedicatedConfirmed: false }).verdict, "REJECT"));
  test("5 exact dedicated identity is eligible", () => assert.equal(evaluateActivationUuid("794b68ee-3f13-4fd4-9460-99f247d4e6ab", { dedicatedConfirmed: true }).verdict, "ACCEPT"));
  test("6 null UUID is rejected", () => assert.equal(evaluateActivationUuid(null, { dedicatedConfirmed: true }).verdict, "REJECT"));
  test("7 placeholder UUID is rejected", () => assert.equal(evaluateActivationUuid("__DEDICATED_BACKUP_AUTH_UUID__", { dedicatedConfirmed: true }).verdict, "REJECT"));
  test("8 malformed UUID is rejected", () => assert.equal(evaluateActivationUuid("not-a-uuid", { dedicatedConfirmed: true }).verdict, "REJECT"));
  test("9 all-zero UUID is rejected", () => assert.equal(evaluateActivationUuid("00000000-0000-0000-0000-000000000000", { dedicatedConfirmed: true }).verdict, "REJECT"));
  test("10 known application identity is rejected", () => assert.equal(evaluateActivationUuid("794b68ee-3f13-4fd4-9460-99f247d4e6ab", { dedicatedConfirmed: true, knownApplicationUuids: ["794b68ee-3f13-4fd4-9460-99f247d4e6ab"] }).verdict, "REJECT"));
  test("11 exact four buckets are accepted", () => assert.equal(routeVerdict(), "ACCEPT"));
  test("12 wildcard bucket is rejected", () => assert.equal(routeVerdict({ buckets: ["*"] }), "REJECT"));
  test("13 missing bucket is rejected", () => assert.equal(routeVerdict({ buckets: KNOWN_BUCKET_BACKUP_ROUTE.buckets.slice(1) }), "REJECT"));
  test("14 extra bucket is rejected", () => assert.equal(routeVerdict({ buckets: [...KNOWN_BUCKET_BACKUP_ROUTE.buckets, "fifth"] }), "REJECT"));
  test("15 ListBuckets is rejected", () => assert.equal(routeVerdict({ allowedOperations: ["ListBuckets", "ListObjectsV2", "GetObject"] }), "REJECT"));
  test("16 storage.buckets SELECT is rejected", () => assert.equal(routeVerdict({ storageBucketsSelect: true }), "REJECT"));
  test("17 SELECT-only policy is accepted", () => assert.equal(policyVerdict(), "ACCEPT"));
  test("18 LIST is required", () => assert.equal(routeVerdict({ allowedOperations: ["GetObject"] }), "REJECT"));
  test("19 GET is required", () => assert.equal(routeVerdict({ allowedOperations: ["ListObjectsV2"] }), "REJECT"));
  test("20 metadata-only policy is rejected", () => assert.equal(policyVerdict({ getObjectAllowed: false }), "REJECT"));
  test("21 INSERT policy is rejected", () => assert.equal(policyVerdict({ commands: ["SELECT", "INSERT"] }), "REJECT"));
  test("22 UPDATE policy is rejected", () => assert.equal(policyVerdict({ commands: ["SELECT", "UPDATE"] }), "REJECT"));
  test("23 DELETE policy is rejected", () => assert.equal(policyVerdict({ commands: ["SELECT", "DELETE"] }), "REJECT"));
  test("24 FOR ALL policy is rejected", () => assert.equal(policyVerdict({ commands: ["ALL"] }), "REJECT"));
  test("25 inherited SELECT is modeled", () => assert.equal(evaluateInheritedAuthority(CURRENT_STORAGE_POLICIES).axes.SELECT, "UNPROVEN"));
  test("26 inherited INSERT is detected", () => assert.equal(evaluateInheritedAuthority([{ ...CURRENT_STORAGE_POLICIES[0], cmd: "INSERT", identityCondition: "ANY_AUTHENTICATED" }]).axes.INSERT, "UNSAFE"));
  test("27 inherited UPDATE is detected", () => assert.equal(evaluateInheritedAuthority([{ ...CURRENT_STORAGE_POLICIES[0], cmd: "UPDATE", identityCondition: "ANY_AUTHENTICATED" }]).axes.UPDATE, "UNSAFE"));
  test("28 inherited DELETE is detected", () => assert.equal(evaluateInheritedAuthority([{ ...CURRENT_STORAGE_POLICIES[0], cmd: "DELETE", identityCondition: "ANY_AUTHENTICATED" }]).axes.DELETE, "UNSAFE"));
  test("29 permissive OR composition is modeled", () => assert.equal(evaluateInheritedAuthority([{ ...CURRENT_STORAGE_POLICIES[0], cmd: "INSERT", permissive: true, identityCondition: "ANY_AUTHENTICATED" }]).composition, "PERMISSIVE_OR"));
  test("30 unknown condition remains UNPROVEN", () => assert.equal(evaluateInheritedAuthority([{ ...CURRENT_STORAGE_POLICIES[0], cmd: "DELETE", identityCondition: "UNKNOWN" }]).axes.DELETE, "UNPROVEN"));
  test("30b missing policy inventory keeps every authority axis UNPROVEN", () => assert.deepEqual(evaluateInheritedAuthority().axes, { SELECT: "UNPROVEN", INSERT: "UNPROVEN", UPDATE: "UNPROVEN", DELETE: "UNPROVEN" }));
  test("31 service-role is rejected", () => assert.equal(policyVerdict({ serviceRoleUsed: true }), "REJECT"));
  test("32 S3 access key is rejected", () => assert.equal(policyVerdict({ s3AccessKeyUsed: true }), "REJECT"));
  test("33 DB URL is rejected", () => assert.equal(policyVerdict({ databaseUrlUsed: true }), "REJECT"));
  test("34 DB password is rejected", () => assert.equal(policyVerdict({ databasePasswordUsed: true }), "REJECT"));
  test("35 session lifecycle is required", () => assert.equal(SESSION_LIFECYCLE.required, true));
  test("36 expired token blocks Storage", () => assert.equal(evaluateSessionState("EXPIRED_TOKEN").storageCallAllowed, false));
  test("37 refresh failure blocks Storage", () => assert.equal(evaluateSessionState("REFRESH_FAILED").storageCallAllowed, false));
  test("38 wrong auth.uid blocks Storage", () => assert.equal(evaluateSessionState("WRONG_AUTH_UID").storageCallAllowed, false));
  test("39 revoked session blocks Storage", () => assert.equal(evaluateSessionState("REVOKED_SESSION").storageCallAllowed, false));
  test("40 unknown session state blocks Storage", () => assert.equal(evaluateSessionState("UNKNOWN_SESSION_STATE").storageCallAllowed, false));
  test("41 valid matching access token permits Storage", () => assert.equal(evaluateSessionState("VALID_ACCESS_TOKEN").storageCallAllowed, true));
  test("42 secret redaction covers bootstrap and session material", () => assert.equal(redactSecrets("password=hunter2 refresh_token=rt-value access_token=jwt-value"), "password=[REDACTED] refresh_token=[REDACTED] access_token=[REDACTED]"));
  test("43 positive LIST GET and checksum plans are required", () => assert.deepEqual(TEST_PLAN.positive.required, ["AUTH_UID_VERIFY", "LIST_OBJECTS_V2", "GET_OBJECT", "SHA256_COMPARE"]));
  test("44 cross-bucket and write denial plans are required", () => assert.deepEqual(TEST_PLAN.negative.required, ["FIFTH_BUCKET_LIST", "FIFTH_BUCKET_GET", "PUT", "OVERWRITE", "MULTIPART_UPLOAD", "DELETE", "COPY_DESTINATION", "MOVE", "BUCKET_CREATE", "BUCKET_UPDATE", "BUCKET_DELETE", "OPERATOR_TOKEN", "UNRELATED_APP_AUTHORITY"]));
test("45 synthetic object, rollback, identity contract and open obligations remain explicit", () => {
    assert.equal(SYNTHETIC_TEST_OBJECT_PLAN.customerData, false);
    assert.equal(POLICY_DESIGN.rollbackExactPolicyOnly, true);
    assert.equal(DEDICATED_BACKUP_IDENTITY.name, "lws-storage-backup-reader");
    assert.equal(ACTIVATION_STATUS, "DESIGN_ONLY_NOT_ACTIVATABLE");
    assert.equal(OPEN_OBLIGATIONS.every((obligation) => obligation.status === "OPEN" || obligation.status === "MISSING" || obligation.status === "NOT_PROVEN" || obligation.status === "NO_GO"), true);
});

  test("46 inert SQL artifacts are structurally valid and activation remains NO-GO", async () => {
    const root = new URL("../../../", import.meta.url);
    const [candidateSql, rollbackSql] = await Promise.all([
      readFile(new URL("supabase/migrations-candidates/p0_6e6b_storage_backup_reader_rls.sql", root), "utf8"),
      readFile(new URL("supabase/migrations-candidates/p0_6e6b_storage_backup_reader_rls_rollback.sql", root), "utf8"),
    ]);
    const result = verifyActivationArtifacts({ candidateSql, rollbackSql });

    assert.equal(result.structureValid, true);
    assert.equal(result.activationReady, false);
    assert.equal(result.verdict, "NO-GO");
  });

  test("47 inert marker without executable guard is structurally rejected", async () => {
    const root = new URL("../../../", import.meta.url);
    const [candidateSql, rollbackSql] = await Promise.all([
      readFile(new URL("supabase/migrations-candidates/p0_6e6b_storage_backup_reader_rls.sql", root), "utf8"),
      readFile(new URL("supabase/migrations-candidates/p0_6e6b_storage_backup_reader_rls_rollback.sql", root), "utf8"),
    ]);
    const guardOnlyInComment = candidateSql.replace(
      /do \$p0_6e6b_activation_guard\$[\s\S]*?\$p0_6e6b_activation_guard\$;/,
      "-- raise exception 'P0_6E6B_DESIGN_ONLY_NOT_ACTIVATABLE';",
    );

    assert.equal(verifyActivationArtifacts({ candidateSql: guardOnlyInComment, rollbackSql }).structureValid, false);
  });

  test("48 materialized SQL can pass only when its UUID equals complete activation evidence", async () => {
    const root = new URL("../../../", import.meta.url);
    const [candidateSql, rollbackSql] = await Promise.all([
      readFile(new URL("supabase/migrations-candidates/p0_6e6b_storage_backup_reader_rls.sql", root), "utf8"),
      readFile(new URL("supabase/migrations-candidates/p0_6e6b_storage_backup_reader_rls_rollback.sql", root), "utf8"),
    ]);
    const authUuid = "794b68ee-3f13-4fd4-9460-99f247d4e6ab";
    const materializedSql = candidateSql
      .replace(/^--.*DESIGN_ONLY_NOT_ACTIVATABLE.*\r?\n/m, "")
      .replace(/do \$p0_6e6b_activation_guard\$[\s\S]*?\$p0_6e6b_activation_guard\$;\s*/, "")
      .replace("<EXACT_DEDICATED_BACKUP_AUTH_UUID_REQUIRED>", authUuid);
    const evidence = {
      authUuid,
      dedicatedConfirmed: true,
      identityCollisionExcluded: true,
      completePolicyInventory: true,
      currentPolicies: [],
      sessionLifecycleProven: true,
      positiveAndNegativeTestsProven: true,
    };

    assert.equal(verifyActivationArtifacts({ candidateSql: materializedSql, rollbackSql, activationEvidence: evidence }).verdict, "GO");
    assert.equal(verifyActivationArtifacts({ candidateSql: materializedSql.replace(authUuid, "b0429897-0a2f-4fb2-bb15-f671c143c685"), rollbackSql, activationEvidence: evidence }).verdict, "NO-GO");
  });

  test("49 placeholder is rejected from a purported materialized artifact", async () => {
    const root = new URL("../../../", import.meta.url);
    const [candidateSql, rollbackSql] = await Promise.all([
      readFile(new URL("supabase/migrations-candidates/p0_6e6b_storage_backup_reader_rls.sql", root), "utf8"),
      readFile(new URL("supabase/migrations-candidates/p0_6e6b_storage_backup_reader_rls_rollback.sql", root), "utf8"),
    ]);
    const noGuardSql = candidateSql
      .replace(/^--.*DESIGN_ONLY_NOT_ACTIVATABLE.*\r?\n/m, "")
      .replace(/do \$p0_6e6b_activation_guard\$[\s\S]*?\$p0_6e6b_activation_guard\$;\s*/, "");

    assert.equal(verifyActivationArtifacts({ candidateSql: noGuardSql, rollbackSql }).structureValid, false);
  });

  test("50 a second auth.uid binding is structurally rejected", async () => {
    const root = new URL("../../../", import.meta.url);
    const [candidateSql, rollbackSql] = await Promise.all([
      readFile(new URL("supabase/migrations-candidates/p0_6e6b_storage_backup_reader_rls.sql", root), "utf8"),
      readFile(new URL("supabase/migrations-candidates/p0_6e6b_storage_backup_reader_rls_rollback.sql", root), "utf8"),
    ]);
    const authUuid = "794b68ee-3f13-4fd4-9460-99f247d4e6ab";
    const secondUuid = "b0429897-0a2f-4fb2-bb15-f671c143c685";
    const broadenedSql = candidateSql
      .replace(/^--.*DESIGN_ONLY_NOT_ACTIVATABLE.*\r?\n/m, "")
      .replace(/do \$p0_6e6b_activation_guard\$[\s\S]*?\$p0_6e6b_activation_guard\$;\s*/, "")
      .replace("<EXACT_DEDICATED_BACKUP_AUTH_UUID_REQUIRED>", `${authUuid}'::uuid or auth.uid() = '${secondUuid}`);

    assert.equal(verifyActivationArtifacts({ candidateSql: broadenedSql, rollbackSql }).structureValid, false);
  });