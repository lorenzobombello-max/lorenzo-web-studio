export const REQUIRED_BUCKETS = Object.freeze([
  "customer-request-quarantine",
  "quotation-artifacts",
  "recruitment-cvs",
  "supplier-documents",
]);

export const KNOWN_BUCKET_BACKUP_ROUTE = Object.freeze({
  id: "MODEL_A_KNOWN_BUCKET_OBJECT_ONLY",
  bucketSource: "STATIC_EXACT_ALLOWLIST",
  buckets: REQUIRED_BUCKETS,
  allowedOperations: Object.freeze(["ListObjectsV2", "GetObject"]),
  storageObjectsSelect: true,
  storageBucketsSelect: false,
  listBucketsAllowed: false,
});

export const ACTIVATION_STATUS = "DESIGN_ONLY_NOT_ACTIVATABLE";

export const DEDICATED_BACKUP_IDENTITY = Object.freeze({
  name: "lws-storage-backup-reader",
  type: "SUPABASE_AUTH_USER",
  binding: "EXACT_AUTH_UID_UUID",
  sharedWithApplicationUser: false,
});

export const POLICY_DESIGN = Object.freeze({
  name: "lws_storage_backup_reader_select_v1",
  table: "storage.objects",
  role: "authenticated",
  commands: Object.freeze(["SELECT"]),
  authUidBindingRequired: true,
  emailIdentityBinding: false,
  buckets: REQUIRED_BUCKETS,
  listObjectsV2Allowed: true,
  getObjectAllowed: true,
  storageBucketsPolicy: false,
  operationHelperRequired: false,
  serviceRoleUsed: false,
  s3AccessKeyUsed: false,
  databaseUrlUsed: false,
  databasePasswordUsed: false,
  rollbackExactPolicyOnly: true,
});

export const CURRENT_STORAGE_POLICIES = Object.freeze([
  Object.freeze({
    name: "recruitment_cvs_owner_read_v1",
    table: "storage.objects",
    role: "authenticated",
    cmd: "SELECT",
    permissive: true,
    buckets: Object.freeze(["recruitment-cvs"]),
    identityCondition: "ACTIVE_COMMERCIAL_OPERATOR_OWNER",
  }),
]);

export const SESSION_LIFECYCLE = Object.freeze({
  required: true,
  accessToken: "SHORT_LIVED_S3_SESSION_TOKEN",
  refreshToken: "ROTATING_SINGLE_USE",
  refreshBeforeStorageWhenExpired: true,
  abortStorageOnRefreshFailure: true,
  verifyExactAuthUidBeforeStorage: true,
  rateLimit: "TOKEN_REFRESH_1800_PER_HOUR_PER_IP_BURST_30",
});

export const TEST_PLAN = Object.freeze({
  positive: Object.freeze({
    required: Object.freeze(["AUTH_UID_VERIFY", "LIST_OBJECTS_V2", "GET_OBJECT", "SHA256_COMPARE"]),
  }),
  negative: Object.freeze({
    required: Object.freeze([
      "FIFTH_BUCKET_LIST",
      "FIFTH_BUCKET_GET",
      "PUT",
      "OVERWRITE",
      "MULTIPART_UPLOAD",
      "DELETE",
      "COPY_DESTINATION",
      "MOVE",
      "BUCKET_CREATE",
      "BUCKET_UPDATE",
      "BUCKET_DELETE",
      "OPERATOR_TOKEN",
      "UNRELATED_APP_AUTHORITY",
    ]),
  }),
});

export const SYNTHETIC_TEST_OBJECT_PLAN = Object.freeze({
  customerData: false,
  generatedLocally: true,
  preActivationUploadByExistingAuthorizedOperator: true,
  backupIdentityWriteUsed: false,
  checksumAlgorithm: "SHA-256",
  removeAfterEvidenceCapture: true,
});

export const OPEN_OBLIGATIONS = Object.freeze([
  Object.freeze({ id: "DEDICATED_AUTH_USER", status: "MISSING" }),
  Object.freeze({ id: "EXACT_AUTH_UUID", status: "MISSING" }),
  Object.freeze({ id: "IDENTITY_COLLISION_EXCLUSION", status: "NOT_PROVEN" }),
  Object.freeze({ id: "COMPLETE_LIVE_POLICY_INVENTORY_AT_ACTIVATION", status: "OPEN" }),
  Object.freeze({ id: "SESSION_BOOTSTRAP_AND_SECRET_STORE", status: "OPEN" }),
  Object.freeze({ id: "POSITIVE_AND_NEGATIVE_RUNTIME_EVIDENCE", status: "OPEN" }),
  Object.freeze({ id: "PRODUCTION_ACTIVATION", status: "NO_GO" }),
]);

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ZERO_UUID = "00000000-0000-0000-0000-000000000000";
const COMMANDS = Object.freeze(["SELECT", "INSERT", "UPDATE", "DELETE"]);

export function evaluateActivationUuid(uuid, evidence = {}) {
  const knownApplicationUuids = Array.isArray(evidence.knownApplicationUuids)
    ? evidence.knownApplicationUuids.map((knownUuid) => knownUuid.toLowerCase())
    : [];
  const normalizedUuid = typeof uuid === "string" ? uuid.toLowerCase() : "";
  const accepted = UUID_PATTERN.test(normalizedUuid)
    && normalizedUuid !== ZERO_UUID
    && evidence.dedicatedConfirmed === true
    && !knownApplicationUuids.includes(normalizedUuid);

  return Object.freeze({ uuid: accepted ? normalizedUuid : null, verdict: accepted ? "ACCEPT" : "REJECT" });
}

export function evaluatePolicyDesign(policy) {
  const exactCommands = Array.isArray(policy?.commands)
    && policy.commands.length === 1
    && policy.commands[0] === "SELECT";
  const accepted = policy?.table === "storage.objects"
    && policy?.role === "authenticated"
    && exactCommands
    && policy.authUidBindingRequired === true
    && policy.emailIdentityBinding === false
    && policy.listObjectsV2Allowed === true
    && policy.getObjectAllowed === true
    && policy.storageBucketsPolicy === false
    && policy.serviceRoleUsed === false
    && policy.s3AccessKeyUsed === false
    && policy.databaseUrlUsed === false
    && policy.databasePasswordUsed === false;

  return Object.freeze({ verdict: accepted ? "ACCEPT" : "REJECT" });
}

export function evaluateInheritedAuthority(policies) {
  if (!Array.isArray(policies)) {
    return Object.freeze({
      axes: Object.freeze(Object.fromEntries(COMMANDS.map((command) => [command, "UNPROVEN"]))),
      composition: "UNPROVEN",
    });
  }

  const axes = Object.fromEntries(COMMANDS.map((command) => [command, "SAFE"]));
  let composition = "NONE";

  for (const policy of Array.isArray(policies) ? policies : []) {
    const command = String(policy?.cmd ?? "").toUpperCase();
    const affectedCommands = command === "ALL" ? COMMANDS : [command];
    if (policy?.permissive === true) composition = "PERMISSIVE_OR";

    for (const affectedCommand of affectedCommands) {
      if (!COMMANDS.includes(affectedCommand)) continue;
      if (policy.identityCondition === "ANY_AUTHENTICATED") axes[affectedCommand] = "UNSAFE";
      else if (policy.identityCondition !== "EXCLUDES_DEDICATED_BACKUP_UUID" && axes[affectedCommand] !== "UNSAFE") {
        axes[affectedCommand] = "UNPROVEN";
      }
    }
  }

  return Object.freeze({ axes: Object.freeze(axes), composition });
}

export function evaluateSessionState(state) {
  const storageCallAllowed = state === "VALID_ACCESS_TOKEN";
  return Object.freeze({ state, storageCallAllowed, storageCalls: storageCallAllowed ? 1 : 0 });
}

export function redactSecrets(value) {
  return String(value).replace(/\b(password|refresh_token|access_token)=\S+/gi, "$1=[REDACTED]");
}

function stripSqlComments(sql) {
  return sql.replace(/\/\*[\s\S]*?\*\//g, "").replace(/--.*$/gm, "");
}

export function verifyActivationArtifacts({ candidateSql, rollbackSql, activationEvidence = {} }) {
  const candidate = String(candidateSql ?? "");
  const rollback = String(rollbackSql ?? "");
  const executableCandidate = stripSqlComments(candidate);
  const executableRollback = stripSqlComments(rollback);
  const lowerCandidate = executableCandidate.toLowerCase();
  const lowerRollback = executableRollback.toLowerCase();
  const policyStatements = executableCandidate.match(/create\s+policy\s+[\s\S]*?;/gi) ?? [];
  const policyStatement = policyStatements[0] ?? "";
  const rollbackDropCount = (lowerRollback.match(/drop\s+policy\b/g) ?? []).length;
  const bucketClause = policyStatement.match(/bucket_id\s+in\s*\(([^)]*)\)/i)?.[1] ?? "";
  const policyBuckets = [...bucketClause.matchAll(/'([^']+)'/g)].map((match) => match[1]);
  const authUidBindingCount = (policyStatement.match(/auth\.uid\(\)\s*=/gi) ?? []).length;
  const sqlUuid = policyStatement.match(/auth\.uid\(\)\s*=\s*'([0-9a-f-]+)'::uuid/i)?.[1]?.toLowerCase() ?? null;
  const evidenceUuid = typeof activationEvidence.authUuid === "string" ? activationEvidence.authUuid.toLowerCase() : null;
  const markerPresent = candidate.includes(ACTIVATION_STATUS);
  const executableGuardPresent = /raise\s+exception\s+'P0_6E6B_DESIGN_ONLY_NOT_ACTIVATABLE'/i.test(executableCandidate);
  const placeholderPresent = executableCandidate.includes("<EXACT_DEDICATED_BACKUP_AUTH_UUID_REQUIRED>");
  const inertArtifact = markerPresent && executableGuardPresent && placeholderPresent && sqlUuid === null;
  const materializedArtifact = !markerPresent && !executableGuardPresent && !placeholderPresent && sqlUuid !== null;
  const inherited = evaluateInheritedAuthority(activationEvidence.currentPolicies);
  const uuid = evaluateActivationUuid(activationEvidence.authUuid, activationEvidence);

  const checks = Object.freeze({
    artifactModeValid: inertArtifact || materializedArtifact,
    executableDesignGuard: inertArtifact,
    materializedArtifact,
    exactlyOnePolicy: policyStatements.length === 1,
    exactPolicyName: /create\s+policy\s+lws_storage_backup_reader_select_v1\s+on\s+storage\.objects/i.test(policyStatement),
    selectOnly: /for\s+select\s+to\s+authenticated/i.test(policyStatement)
      && !/for\s+(insert|update|delete|all)\b/i.test(policyStatement),
    exactAuthUidBinding: authUidBindingCount === 1,
    exactBuckets: policyBuckets.length === REQUIRED_BUCKETS.length
      && REQUIRED_BUCKETS.every((bucket) => policyBuckets.includes(bucket)),
    noBroadAuthority: !/storage\.buckets|listbuckets|service_role|security\s+definer/i.test(executableCandidate),
    rollbackExactPolicyOnly: rollbackDropCount === 1
      && lowerRollback.includes("drop policy if exists lws_storage_backup_reader_select_v1 on storage.objects")
      && !/drop\s+(table|schema|role|function)\b/i.test(executableRollback),
    dedicatedUuidProven: uuid.verdict === "ACCEPT",
    sqlUuidMatchesEvidence: materializedArtifact && uuid.verdict === "ACCEPT" && sqlUuid === evidenceUuid,
    identityCollisionExcluded: activationEvidence.identityCollisionExcluded === true,
    completePolicyInventory: activationEvidence.completePolicyInventory === true,
    inheritedWritesSafe: activationEvidence.completePolicyInventory === true
      && ["INSERT", "UPDATE", "DELETE"].every((command) => inherited.axes[command] === "SAFE"),
    sessionLifecycleProven: activationEvidence.sessionLifecycleProven === true,
    positiveAndNegativeTestsProven: activationEvidence.positiveAndNegativeTestsProven === true,
  });
  const structureValid = [
    "artifactModeValid",
    "exactlyOnePolicy",
    "exactPolicyName",
    "selectOnly",
    "exactAuthUidBinding",
    "exactBuckets",
    "noBroadAuthority",
    "rollbackExactPolicyOnly",
  ].every((name) => checks[name]);
  const activationReady = structureValid && [
    "materializedArtifact",
    "dedicatedUuidProven",
    "sqlUuidMatchesEvidence",
    "identityCollisionExcluded",
    "completePolicyInventory",
    "inheritedWritesSafe",
    "sessionLifecycleProven",
    "positiveAndNegativeTestsProven",
  ].every((name) => checks[name]);

  return Object.freeze({
    structureValid,
    activationReady,
    verdict: activationReady ? "GO" : "NO-GO",
    checks,
    inherited,
  });
}

export function evaluateMinimumAuthorityRoute(route) {
  const exactBuckets = Array.isArray(route?.buckets)
    && route.buckets.length === REQUIRED_BUCKETS.length
    && REQUIRED_BUCKETS.every((bucket) => route.buckets.includes(bucket));
  const exactOperations = Array.isArray(route?.allowedOperations)
    && route.allowedOperations.length === 2
    && route.allowedOperations.includes("ListObjectsV2")
    && route.allowedOperations.includes("GetObject");

  const accepted = route?.bucketSource === "STATIC_EXACT_ALLOWLIST"
    && exactBuckets
    && exactOperations
    && route.storageObjectsSelect === true
    && route.storageBucketsSelect === false
    && route.listBucketsAllowed === false;

  return Object.freeze({
    routeId: route?.id ?? null,
    verdict: accepted ? "ACCEPT" : "REJECT",
  });
}