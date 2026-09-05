import assert from "node:assert/strict";
import test from "node:test";
import {
  EXPECTED_PREACTIVATION_STATE,
  OPEN_PREACTIVATION_OBLIGATIONS,
  POLICY_NAME,
  PRODUCTION_PROJECT_REFERENCE,
  TRUSTED_RECOVERY_ARTIFACT,
  analyzeProductionPolicies,
  canonicalizeRecoveryArtifactContent,
  computeRecoveryArtifactSha256,
  evaluateProductionPreactivation,
} from "./storage-backup-production-preactivation.mjs";

const ownerPolicy = Object.freeze({
  schemaname: "storage",
  tablename: "objects",
  policyname: "recruitment_cvs_owner_read_v1",
  permissive: "PERMISSIVE",
  roles: ["authenticated"],
  cmd: "SELECT",
  qual: "((bucket_id = 'recruitment-cvs'::text) AND (EXISTS (SELECT 1 FROM commercial_operators operator WHERE ((operator.auth_user_id = auth.uid()) AND (operator.status = 'ACTIVE'::text) AND (operator.role = 'owner'::text)))))",
  with_check: null,
});

const artifactContent = (factOverrides = {}, artifactOverrides = {}) => ({
  recovery_artifact_id: TRUSTED_RECOVERY_ARTIFACT.id,
  recovery_artifact_type: TRUSTED_RECOVERY_ARTIFACT.type,
  recovered_at: "2026-09-05T21:16:05.885Z",
  source_reference: TRUSTED_RECOVERY_ARTIFACT.sourceReference,
  evidence_version: TRUSTED_RECOVERY_ARTIFACT.version,
  facts: {
    policyInventoryObservedAt: "2026-09-05T21:14:14.066Z",
    authIdentityNameObservedAt: "2026-09-05T21:15:46.005Z",
    projectReference: PRODUCTION_PROJECT_REFERENCE,
    projectIdentityVerified: true,
    policyInventoryRead: true,
    inventoryComplete: true,
    policies: [ownerPolicy],
    policyRowCount: 1,
    targetPolicyNameCollision: false,
    schemaCompatible: true,
    schemaCompatibilitySource: "P0-6E.4 prior live evidence",
    modelACompatible: true,
    modelA: {
      buckets: [
        "customer-request-quarantine",
        "quotation-artifacts",
        "recruitment-cvs",
        "supplier-documents",
      ],
      listBuckets: false,
      storageBucketsSelect: false,
      operations: ["ListObjectsV2", "GetObject"],
    },
    identityNameCollision: "ABSENT",
    authUserState: "ABSENT_EXPECTED",
    authUuidState: "ABSENT_EXPECTED",
    candidateState: "INERT",
    productionMutation: false,
    storageCall: false,
    containsSecrets: false,
    containsPersonalData: false,
    ...factOverrides,
  },
  ...artifactOverrides,
});

const completeArtifact = () => ({
  ...artifactContent(),
  recovery_artifact_sha256: TRUSTED_RECOVERY_ARTIFACT.sha256,
});

const callerReference = (artifact = completeArtifact(), overrides = {}) => ({
  recoveryArtifactId: artifact.recovery_artifact_id,
  recoveryArtifactSha256: artifact.recovery_artifact_sha256,
  ...overrides,
});

const evaluate = (artifact = completeArtifact(), callerOverrides = {}) => (
  evaluateProductionPreactivation(callerReference(artifact, callerOverrides), artifact)
);

const tamperedArtifact = (factOverrides = {}, artifactOverrides = {}) => ({
  ...artifactContent(factOverrides, artifactOverrides),
  recovery_artifact_sha256: TRUSTED_RECOVERY_ARTIFACT.sha256,
});

test("1 incomplete inventory is NO-GO and every authority axis is UNPROVEN", () => {
  const report = evaluate(tamperedArtifact({ inventoryComplete: false }));
  assert.equal(report.verdict, "NO-GO");
  assert.deepEqual(report.authority.axes, { SELECT: "UNPROVEN", INSERT: "UNPROVEN", UPDATE: "UNPROVEN", DELETE: "UNPROVEN" });
});

test("2 target policy-name collision is NO-GO", () => {
  const collision = { ...ownerPolicy, policyname: POLICY_NAME };
  assert.equal(analyzeProductionPolicies([ownerPolicy, collision], true).targetPolicyCollision, "PRESENT");
  assert.equal(evaluate(tamperedArtifact({ policies: [ownerPolicy, collision], policyRowCount: 2 })).verdict, "NO-GO");
});

test("3 generic authenticated SELECT is unsafe", () => {
  const policy = { ...ownerPolicy, policyname: "generic_read", qual: "true" };
  const report = analyzeProductionPolicies([policy], true);
  assert.equal(report.axes.SELECT, "UNSAFE");
});

for (const [number, command] of [[4, "INSERT"], [5, "UPDATE"], [6, "DELETE"]]) {
  test(`${number} generic authenticated ${command} is NO-GO`, () => {
    const policy = { ...ownerPolicy, policyname: `generic_${command.toLowerCase()}`, cmd: command, qual: "true", with_check: "true" };
    assert.equal(analyzeProductionPolicies([policy], true).axes[command], "UNSAFE");
  });
}

test("7 unrelated owner SELECT is identity-dependent and preactivation-compatible", () => {
  const report = evaluate();
  assert.equal(report.policies[0].classification, "IDENTITY_DEPENDENT");
  assert.equal(report.authority.axes.SELECT, "IDENTITY_DEPENDENT");
  assert.equal(report.verdict, "GO");
});

test("8 unknown policy condition remains UNPROVEN", () => {
  const policy = { ...ownerPolicy, policyname: "unknown_read", qual: "tenant_guard()" };
  assert.equal(analyzeProductionPolicies([policy], true).axes.SELECT, "UNPROVEN");
});

test("9 permissive OR composition is explicit", () => {
  assert.equal(analyzeProductionPolicies([ownerPolicy], true).composition, "PERMISSIVE_OR");
});

test("10 production project mismatch is NO-GO", () => {
  assert.equal(evaluate(tamperedArtifact({ projectReference: "wrong-project" })).verdict, "NO-GO");
});

test("11 schema mismatch is NO-GO", () => {
  assert.equal(evaluate(tamperedArtifact({ schemaCompatible: false })).verdict, "NO-GO");
});

test("12 MODEL A incompatibility is NO-GO", () => {
  assert.equal(evaluate(tamperedArtifact({ modelACompatible: false })).verdict, "NO-GO");
});

test("13 dedicated Auth user absence is the expected preactivation state", () => {
  assert.equal(EXPECTED_PREACTIVATION_STATE.authUser, "ABSENT_EXPECTED");
  assert.equal(evaluate().checks.authUserAbsentExpected, true);
});

test("14 dedicated Auth UUID absence is the expected preactivation state", () => {
  assert.equal(EXPECTED_PREACTIVATION_STATE.authUuid, "ABSENT_EXPECTED");
  assert.equal(evaluate().checks.authUuidAbsentExpected, true);
});

test("15 candidate must remain inert", () => {
  assert.equal(evaluate(tamperedArtifact({ candidateState: "MATERIALIZED" })).verdict, "NO-GO");
});

test("16 all read-only prerequisites safe yields preactivation GO", () => {
  assert.equal(evaluate().verdict, "GO");
});

test("17 preactivation GO never makes the candidate activatable", () => {
  const report = evaluate();
  assert.equal(report.verdict, "GO");
  assert.equal(report.candidateActivatable, false);
  assert.equal(report.activationVerdict, "NO-GO");
});

test("18 activation obligations remain open", () => {
  const report = evaluate();
  assert.deepEqual(report.openObligations, OPEN_PREACTIVATION_OBLIGATIONS);
  assert.equal(report.openObligations.every((obligation) => obligation.status !== "CLOSED"), true);
});

test("identity-name collision uncertainty is NO-GO", () => {
  assert.equal(evaluate(tamperedArtifact({ identityNameCollision: "UNPROVEN" })).verdict, "NO-GO");
});

test("FOR ALL affects all command axes", () => {
  const policy = { ...ownerPolicy, policyname: "generic_all", cmd: "ALL", qual: "true", with_check: "true" };
  assert.deepEqual(analyzeProductionPolicies([policy], true).axes, { SELECT: "UNSAFE", INSERT: "UNSAFE", UPDATE: "UNSAFE", DELETE: "UNSAFE" });
});

test("19 missing recovered artifact is NO-GO", () => {
  const report = evaluateProductionPreactivation(callerReference());
  assert.equal(report.checks.recoveredEvidenceValid, false);
  assert.equal(report.verdict, "NO-GO");
});

test("20 valid recovered evidence is evaluatable without claiming activation readiness", () => {
  const report = evaluate();
  assert.equal(report.checks.recoveredEvidenceValid, true);
  assert.equal(report.verdict, "GO");
  assert.equal(report.authority.currentInheritedAuthoritySafe, "UNPROVEN");
  assert.equal(report.authority.backupIdentityCouldInheritRecruitmentOwnerRead, "UNPROVEN");
  assert.equal(report.authority.backupIdentityWriteIsolation, true);
  assert.equal(report.candidateActivatable, false);
  assert.equal(report.activationVerdict, "NO-GO");
});

test("21 malformed recovered transcript timestamps are NO-GO", () => {
  const report = evaluate(tamperedArtifact({ policyInventoryObservedAt: "not-a-timestamp" }));
  assert.equal(report.checks.recoveredEvidenceValid, false);
  assert.equal(report.verdict, "NO-GO");
});

test("22 synthetic recovery booleans without artifact are NO-GO", () => {
  const report = evaluateProductionPreactivation({ inventoryComplete: true, projectIdentityVerified: true, policyInventoryRead: true });
  assert.equal(report.verdict, "NO-GO");
});

test("23 synthetic recovery labels without artifact are NO-GO", () => {
  const report = evaluateProductionPreactivation({ evidenceSource: "RECOVERED_TRANSCRIPT_EVIDENCE", recoveryClassification: "B_PARTIAL_LOCAL_WORK_RECOVERABLE" });
  assert.equal(report.verdict, "NO-GO");
});

test("24 valid artifact and correct trusted hash are evaluatable", () => {
  assert.equal(evaluate().checks.recoveredEvidenceValid, true);
});

test("25 artifact mutation after hashing is NO-GO", () => {
  assert.equal(evaluate(tamperedArtifact({ policyRowCount: 2 })).verdict, "NO-GO");
});

test("26 wrong hash is NO-GO", () => {
  const artifact = { ...completeArtifact(), recovery_artifact_sha256: "0".repeat(64) };
  assert.equal(evaluateProductionPreactivation(callerReference(artifact), artifact).verdict, "NO-GO");
});

test("27 missing hash is NO-GO", () => {
  const artifact = { ...completeArtifact() };
  delete artifact.recovery_artifact_sha256;
  assert.equal(evaluateProductionPreactivation({ recoveryArtifactId: artifact.recovery_artifact_id }, artifact).verdict, "NO-GO");
});

test("28 malformed hash is NO-GO", () => {
  const artifact = { ...completeArtifact(), recovery_artifact_sha256: "not-a-sha256" };
  assert.equal(evaluateProductionPreactivation(callerReference(artifact), artifact).verdict, "NO-GO");
});

test("29 wrong artifact type is NO-GO", () => {
  assert.equal(evaluate(tamperedArtifact({}, { recovery_artifact_type: "UNTRUSTED" })).verdict, "NO-GO");
});

test("30 wrong evidence version is NO-GO", () => {
  assert.equal(evaluate(tamperedArtifact({}, { evidence_version: "2.0.0" })).verdict, "NO-GO");
});

for (const [number, field, value] of [
  [31, "inventoryComplete", true],
  [32, "projectIdentityVerified", true],
  [33, "policyInventoryRead", true],
  [34, "targetPolicyNameCollision", false],
]) {
  test(`${number} caller override of ${field} is denied`, () => {
    assert.equal(evaluate(completeArtifact(), { [field]: value }).verdict, "NO-GO");
  });
}

test("35 invalid artifact recovered_at is NO-GO", () => {
  assert.equal(evaluate(tamperedArtifact({}, { recovered_at: "not-a-timestamp" })).verdict, "NO-GO");
});

test("36 canonical serialization is deterministic across key order", () => {
  const artifact = completeArtifact();
  const reordered = Object.fromEntries(Object.entries(artifact).reverse());
  assert.equal(canonicalizeRecoveryArtifactContent(artifact), canonicalizeRecoveryArtifactContent(reordered));
});

test("37 identical artifact content produces the same hash", () => {
  assert.equal(computeRecoveryArtifactSha256(completeArtifact()), computeRecoveryArtifactSha256(completeArtifact()));
});

test("38 one artifact field difference produces another hash", () => {
  assert.notEqual(computeRecoveryArtifactSha256(completeArtifact()), computeRecoveryArtifactSha256(tamperedArtifact({ policyRowCount: 2 })));
});

test("39 valid artifact preserves read-only preactivation GO", () => {
  assert.equal(evaluate().verdict, "GO");
});

test("40 activation remains NO-GO", () => {
  const report = evaluate();
  assert.equal(report.candidateActivatable, false);
  assert.equal(report.activationVerdict, "NO-GO");
});

test("41 inherited SELECT safety remains UNPROVEN", () => {
  assert.equal(evaluate().authority.currentInheritedAuthoritySafe, "UNPROVEN");
});

test("42 recruitment owner-read inheritance remains UNPROVEN", () => {
  assert.equal(evaluate().authority.backupIdentityCouldInheritRecruitmentOwnerRead, "UNPROVEN");
});

test("43 recovery artifact older than its observations is NO-GO", () => {
  assert.equal(evaluate(tamperedArtifact({}, { recovered_at: "2026-09-05T21:14:00.000Z" })).verdict, "NO-GO");
});

test("44 ambiguous recovery artifact source is NO-GO", () => {
  assert.equal(evaluate(tamperedArtifact({}, { source_reference: "copilot-session:ambiguous" })).verdict, "NO-GO");
});