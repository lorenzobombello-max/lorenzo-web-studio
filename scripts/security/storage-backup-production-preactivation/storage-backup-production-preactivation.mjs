import { createHash } from "node:crypto";
import { PRODUCTION_PROJECT_REFERENCE } from "../backup/backup-foundation.mjs";

export { PRODUCTION_PROJECT_REFERENCE };

export const POLICY_NAME = "lws_storage_backup_reader_select_v1";
export const TRUSTED_RECOVERY_ARTIFACT = Object.freeze({
  id: "p0-6e.6c-recovered-transcript-20260905",
  sha256: "f5eec339137e0b9b799c13cf7fa1d5704dbe7b6eface03fa93f38f4d564ffe0f",
  type: "P0_6E6C_RECOVERED_TRANSCRIPT",
  version: "1.0.0",
  sourceReference: "copilot-session:3f2f561f-910a-4bae-b664-e2f70f0dfd91;policy-call:call_H5To9vgxSNBdgX07bcYI4IpL;auth-call:call_qYUQ2Z9f27sDlWvbDdb07Z8p",
});
export const EXPECTED_PREACTIVATION_STATE = Object.freeze({
  authUser: "ABSENT_EXPECTED",
  authUuid: "ABSENT_EXPECTED",
  candidate: "INERT",
});
export const OPEN_PREACTIVATION_OBLIGATIONS = Object.freeze([
  Object.freeze({ id: "DEDICATED_AUTH_USER", status: "MISSING" }),
  Object.freeze({ id: "EXACT_AUTH_UUID", status: "MISSING" }),
  Object.freeze({ id: "IDENTITY_COLLISION_EXCLUSION", status: "NOT_PROVEN" }),
  Object.freeze({ id: "COMPLETE_LIVE_POLICY_INVENTORY_AT_ACTIVATION", status: "PROVEN_AT_PREACTIVATION_ONLY" }),
  Object.freeze({ id: "SESSION_BOOTSTRAP_AND_SECRET_STORE", status: "OPEN" }),
  Object.freeze({ id: "POSITIVE_AND_NEGATIVE_RUNTIME_EVIDENCE", status: "OPEN" }),
  Object.freeze({ id: "PRODUCTION_ACTIVATION", status: "NO_GO" }),
]);

const COMMANDS = Object.freeze(["SELECT", "INSERT", "UPDATE", "DELETE"]);
const AUTHENTICATED_ROLES = new Set(["authenticated", "public"]);
const RANK = Object.freeze({ SAFE: 0, IDENTITY_DEPENDENT: 1, UNPROVEN: 2, UNSAFE: 3 });

function isPermissive(value) {
  return value === true || ["PERMISSIVE", "YES"].includes(String(value).toUpperCase());
}

function appliesToAuthenticated(policy) {
  return Array.isArray(policy?.roles)
    && policy.roles.some((role) => AUTHENTICATED_ROLES.has(String(role).toLowerCase()));
}

function classifyPolicy(policy) {
  if (!appliesToAuthenticated(policy)) return "SAFE_FOR_DISTINCT_BACKUP_IDENTITY";
  const command = String(policy?.cmd ?? "").toUpperCase();
  const condition = String(command === "INSERT" ? policy?.with_check : policy?.qual ?? policy?.with_check ?? "").trim();
  if (!condition || /^(?:true|\(true\))(?:::\w+)?$/i.test(condition)) return "UNSAFE_FOR_ANY_AUTHENTICATED_IDENTITY";
  const ownerRead = command === "SELECT"
    && /bucket_id\s*=\s*'recruitment-cvs'/i.test(condition)
    && /commercial_operators/i.test(condition)
    && /auth_user_id\s*=\s*auth\.uid\(\)/i.test(condition)
    && /status\s*=\s*'ACTIVE'/i.test(condition)
    && /role\s*=\s*'owner'/i.test(condition);
  return ownerRead ? "IDENTITY_DEPENDENT" : "UNPROVEN";
}

function mergeAxis(current, next) {
  return RANK[next] > RANK[current] ? next : current;
}

function isCanonicalUtcTimestamp(value) {
  if (typeof value !== "string") return false;
  const timestamp = new Date(value);
  return !Number.isNaN(timestamp.valueOf()) && timestamp.toISOString() === value;
}

function canonicalize(value) {
  if (value === null || typeof value === "boolean" || typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number" && Number.isFinite(value)) return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalize).join(",")}]`;
  if (typeof value === "object" && [Object.prototype, null].includes(Object.getPrototypeOf(value))) {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalize(value[key])}`).join(",")}}`;
  }
  throw new TypeError("Recovery artifact contains a non-canonical value");
}

export function canonicalizeRecoveryArtifactContent(artifact) {
  if (!artifact || typeof artifact !== "object" || Array.isArray(artifact)) throw new TypeError("Recovery artifact must be an object");
  const content = Object.fromEntries(Object.entries(artifact).filter(([key]) => key !== "recovery_artifact_sha256"));
  return canonicalize(content);
}

export function computeRecoveryArtifactSha256(artifact) {
  return createHash("sha256").update(canonicalizeRecoveryArtifactContent(artifact), "utf8").digest("hex");
}

function hasExactKeys(value, expectedKeys) {
  return value !== null
    && typeof value === "object"
    && !Array.isArray(value)
    && JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...expectedKeys].sort());
}

function isRecoveredArtifactValid(callerInput, artifact) {
  if (!hasExactKeys(callerInput, ["recoveryArtifactId", "recoveryArtifactSha256"])) return false;
  if (!hasExactKeys(artifact, [
    "evidence_version",
    "facts",
    "recovered_at",
    "recovery_artifact_id",
    "recovery_artifact_sha256",
    "recovery_artifact_type",
    "source_reference",
  ])) return false;
  if (!/^[a-f0-9]{64}$/.test(String(artifact.recovery_artifact_sha256))) return false;

  let computedHash;
  try {
    computedHash = computeRecoveryArtifactSha256(artifact);
  } catch {
    return false;
  }

  const facts = artifact.facts;
  const recoveredAt = Date.parse(artifact.recovered_at);
  const latestObservation = Math.max(Date.parse(facts?.policyInventoryObservedAt), Date.parse(facts?.authIdentityNameObservedAt));

  return callerInput.recoveryArtifactId === TRUSTED_RECOVERY_ARTIFACT.id
    && callerInput.recoveryArtifactSha256 === TRUSTED_RECOVERY_ARTIFACT.sha256
    && artifact.recovery_artifact_id === TRUSTED_RECOVERY_ARTIFACT.id
    && artifact.recovery_artifact_sha256 === TRUSTED_RECOVERY_ARTIFACT.sha256
    && artifact.recovery_artifact_type === TRUSTED_RECOVERY_ARTIFACT.type
    && artifact.evidence_version === TRUSTED_RECOVERY_ARTIFACT.version
    && artifact.source_reference === TRUSTED_RECOVERY_ARTIFACT.sourceReference
    && computedHash === TRUSTED_RECOVERY_ARTIFACT.sha256
    && isCanonicalUtcTimestamp(artifact.recovered_at)
    && isCanonicalUtcTimestamp(facts?.policyInventoryObservedAt)
    && isCanonicalUtcTimestamp(facts?.authIdentityNameObservedAt)
    && recoveredAt >= latestObservation
    && facts?.projectIdentityVerified === true
    && facts?.policyInventoryRead === true
    && facts?.inventoryComplete === true
    && Number.isInteger(facts?.policyRowCount)
    && facts.policyRowCount === facts?.policies?.length
    && facts?.targetPolicyNameCollision === false
    && facts?.schemaCompatibilitySource === "P0-6E.4 prior live evidence"
    && facts?.productionMutation === false
    && facts?.storageCall === false
    && facts?.containsSecrets === false
    && facts?.containsPersonalData === false;
}

export function analyzeProductionPolicies(policies, inventoryComplete) {
  if (inventoryComplete !== true || !Array.isArray(policies)) {
    return Object.freeze({
      axes: Object.freeze(Object.fromEntries(COMMANDS.map((command) => [command, "UNPROVEN"]))),
      composition: "UNPROVEN",
      policies: Object.freeze([]),
      targetPolicyCollision: "UNPROVEN",
      currentInheritedAuthoritySafe: "UNPROVEN",
      backupIdentityCouldInheritRecruitmentOwnerRead: "UNPROVEN",
      backupIdentityWriteIsolation: "UNPROVEN",
    });
  }

  const axes = Object.fromEntries(COMMANDS.map((command) => [command, "SAFE"]));
  const classified = [];
  let permissivePolicyPresent = false;

  for (const policy of policies) {
    const classification = classifyPolicy(policy);
    const command = String(policy?.cmd ?? "").toUpperCase();
    const affectedCommands = command === "ALL" ? COMMANDS : [command];
    if (isPermissive(policy?.permissive)) permissivePolicyPresent = true;
    if (appliesToAuthenticated(policy)) {
      const axisStatus = classification === "UNSAFE_FOR_ANY_AUTHENTICATED_IDENTITY"
        ? "UNSAFE"
        : classification;
      for (const affectedCommand of affectedCommands) {
        if (COMMANDS.includes(affectedCommand)) axes[affectedCommand] = mergeAxis(axes[affectedCommand], axisStatus);
      }
    }
    classified.push(Object.freeze({
      name: String(policy?.policyname ?? ""),
      table: `${policy?.schemaname ?? ""}.${policy?.tablename ?? ""}`,
      command,
      roles: Object.freeze(Array.isArray(policy?.roles) ? [...policy.roles] : []),
      permissive: isPermissive(policy?.permissive),
      classification,
    }));
  }

  const recruitmentOwnerReadPresent = classified.some((policy) => policy.name === "recruitment_cvs_owner_read_v1"
    && policy.classification === "IDENTITY_DEPENDENT");
  const writesSafe = ["INSERT", "UPDATE", "DELETE"].every((command) => axes[command] === "SAFE");

  return Object.freeze({
    axes: Object.freeze(axes),
    composition: permissivePolicyPresent ? "PERMISSIVE_OR" : "NO_PERMISSIVE_POLICY",
    policies: Object.freeze(classified),
    targetPolicyCollision: policies.some((policy) => policy?.policyname === POLICY_NAME) ? "PRESENT" : "ABSENT",
    currentInheritedAuthoritySafe: axes.SELECT === "SAFE" && writesSafe ? "SAFE" : "UNPROVEN",
    backupIdentityCouldInheritRecruitmentOwnerRead: recruitmentOwnerReadPresent ? "UNPROVEN" : "NO",
    backupIdentityWriteIsolation: writesSafe,
  });
}

export function evaluateProductionPreactivation(callerInput, recoveryArtifact) {
  const recoveredEvidenceValid = isRecoveredArtifactValid(callerInput, recoveryArtifact);
  const evidence = recoveredEvidenceValid ? recoveryArtifact.facts : undefined;
  const authority = analyzeProductionPolicies(evidence?.policies, evidence?.inventoryComplete);
  const checks = Object.freeze({
    recoveredEvidenceValid,
    projectIdentityVerified: recoveredEvidenceValid && evidence?.projectReference === PRODUCTION_PROJECT_REFERENCE,
    inventoryComplete: recoveredEvidenceValid && evidence?.inventoryComplete === true,
    policyNameCollisionAbsent: recoveredEvidenceValid
      && evidence?.targetPolicyNameCollision === false
      && authority.targetPolicyCollision === "ABSENT",
    schemaCompatible: evidence?.schemaCompatible === true,
    modelACompatible: evidence?.modelACompatible === true,
    identityNameCollisionAbsent: evidence?.identityNameCollision === "ABSENT",
    authUserAbsentExpected: evidence?.authUserState === EXPECTED_PREACTIVATION_STATE.authUser,
    authUuidAbsentExpected: evidence?.authUuidState === EXPECTED_PREACTIVATION_STATE.authUuid,
    candidateInert: evidence?.candidateState === EXPECTED_PREACTIVATION_STATE.candidate,
    inheritedSelectCompatible: ["SAFE", "IDENTITY_DEPENDENT"].includes(authority.axes.SELECT),
    inheritedWritesSafe: ["INSERT", "UPDATE", "DELETE"].every((command) => authority.axes[command] === "SAFE"),
  });
  const preactivationReady = Object.values(checks).every(Boolean);

  return Object.freeze({
    phase: "P0-6E.6C",
    verdict: preactivationReady ? "GO" : "NO-GO",
    candidateActivatable: false,
    activationVerdict: "NO-GO",
    checks,
    authority,
    policies: authority.policies,
    openObligations: OPEN_PREACTIVATION_OBLIGATIONS,
  });
}