import { pathToFileURL } from "node:url";

export const CONSTRAINT_NAME = "commercial_operators_backup_identity_not_active_owner_v1";
export const ACTIVATION_STATUS = "LOCAL_CANDIDATE_NOT_PRODUCTION_ACTIVATABLE";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const ZERO_UUID = "00000000-0000-0000-0000-000000000000";

function fail(code) {
  throw new Error(code);
}

export function requireExactBackupAuthUuid(value) {
  if (typeof value !== "string" || !UUID_PATTERN.test(value) || value === ZERO_UUID) {
    fail("OWNER_MAPPING_GUARD_UUID_REQUIRED");
  }
  return value;
}

export function violatesOwnerMappingGuard(row, backupAuthUuid) {
  const exactUuid = requireExactBackupAuthUuid(backupAuthUuid);
  return row?.auth_user_id === exactUuid && row?.status === "ACTIVE" && row?.role === "owner";
}

export function generateOwnerMappingGuardSql(backupAuthUuid) {
  const exactUuid = requireExactBackupAuthUuid(backupAuthUuid);
  return `-- ${ACTIVATION_STATUS}. DO NOT APPLY.
-- Remove the executable guard only in a separately reviewed activation artifact.

begin;

do $lws_backup_owner_mapping_activation_guard$
begin
  raise exception 'LWS_BACKUP_OWNER_MAPPING_GUARD_NOT_PRODUCTION_ACTIVATABLE';
end;
$lws_backup_owner_mapping_activation_guard$;

alter table public.commercial_operators
  add constraint ${CONSTRAINT_NAME}
  check (
    auth_user_id <> '${exactUuid}'::uuid
    or status <> 'ACTIVE'
    or role <> 'owner'
  ) not valid;

alter table public.commercial_operators
  validate constraint ${CONSTRAINT_NAME};

commit;
`;
}

export function verifyOwnerMappingGuardCandidate(sql, backupAuthUuid) {
  const candidate = String(sql ?? "");
  let exactUuid = null;
  try {
    exactUuid = requireExactBackupAuthUuid(backupAuthUuid);
  } catch {
    return Object.freeze({ structureValid: false, activationReady: false, verdict: "NO-GO" });
  }

  const checks = Object.freeze({
    inertMarker: candidate.includes(ACTIVATION_STATUS),
    executableStop: /raise\s+exception\s+'LWS_BACKUP_OWNER_MAPPING_GUARD_NOT_PRODUCTION_ACTIVATABLE'/i.test(candidate),
    exactTable: /alter\s+table\s+public\.commercial_operators/i.test(candidate),
    exactConstraint: new RegExp(`add\\s+constraint\\s+${CONSTRAINT_NAME}\\b`, "i").test(candidate),
    exactUuidOnce: (candidate.match(new RegExp(exactUuid, "g")) ?? []).length === 1,
    rowLocalCheck: /check\s*\(\s*auth_user_id\s*<>\s*'[0-9a-f-]+'::uuid\s*or\s*status\s*<>\s*'ACTIVE'\s*or\s*role\s*<>\s*'owner'\s*\)/i.test(candidate),
    notValidThenValidate: /\)\s*not\s+valid\s*;[\s\S]*validate\s+constraint\s+commercial_operators_backup_identity_not_active_owner_v1\s*;/i.test(candidate),
    noTriggerFunctionOrPolicy: !/create\s+(?:or\s+replace\s+)?function|create\s+trigger|create\s+policy|grant\b|revoke\b/i.test(candidate),
  });
  const structureValid = Object.values(checks).every(Boolean);
  return Object.freeze({ structureValid, activationReady: false, verdict: "NO-GO", checks });
}

function readUuidArgument(args) {
  const index = args.indexOf("--auth-uuid");
  if (index < 0 || index === args.length - 1 || args.length !== 2) fail("OWNER_MAPPING_GUARD_UUID_REQUIRED");
  return args[index + 1];
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.stdout.write(generateOwnerMappingGuardSql(readUuidArgument(process.argv.slice(2))));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}