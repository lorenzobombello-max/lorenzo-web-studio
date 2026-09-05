import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";
import {
  ACTIVATION_STATUS,
  CONSTRAINT_NAME,
  generateOwnerMappingGuardSql,
  requireExactBackupAuthUuid,
  verifyOwnerMappingGuardCandidate,
  violatesOwnerMappingGuard,
} from "./storage-backup-owner-mapping-guard.mjs";

const BACKUP_UUID = "794b68ee-3f13-4fd4-9460-99f247d4e6ab";
const OTHER_UUID = "b0429897-0a2f-4fb2-bb15-f671c143c685";
const CLI_PATH = fileURLToPath(new URL("./storage-backup-owner-mapping-guard.mjs", import.meta.url));

test("1 missing UUID fails before SQL generation", () => {
  assert.throws(() => generateOwnerMappingGuardSql(), /OWNER_MAPPING_GUARD_UUID_REQUIRED/);
});

test("2 malformed, uppercase, zero, placeholder, and extra-text UUIDs fail closed", () => {
  for (const value of ["not-a-uuid", BACKUP_UUID.toUpperCase(), "00000000-0000-0000-0000-000000000000", "<EXACT_UUID>", `${BACKUP_UUID} `]) {
    assert.throws(() => requireExactBackupAuthUuid(value), /OWNER_MAPPING_GUARD_UUID_REQUIRED/);
  }
});

test("3 CLI emits no SQL for every invalid input shape", () => {
  const invalidArguments = [
    [],
    ["--auth-uuid", "not-a-uuid"],
    ["--auth-uuid", "00000000-0000-0000-0000-000000000000"],
    ["--auth-uuid", "<EXACT_UUID>"],
    ["--auth-uuid", BACKUP_UUID, "extra"],
  ];

  for (const args of invalidArguments) {
    const result = spawnSync(process.execPath, [CLI_PATH, ...args], { encoding: "utf8" });
    assert.equal(result.status, 1);
    assert.equal(result.stdout, "");
    assert.match(result.stderr, /OWNER_MAPPING_GUARD_UUID_REQUIRED/);
  }
});

test("4 exact UUID generates only an inert structurally valid candidate", () => {
  const sql = generateOwnerMappingGuardSql(BACKUP_UUID);
  const result = verifyOwnerMappingGuardCandidate(sql, BACKUP_UUID);
  assert.equal(result.structureValid, true);
  assert.equal(result.activationReady, false);
  assert.equal(result.verdict, "NO-GO");
  assert.match(sql, new RegExp(ACTIVATION_STATUS));
  assert.match(sql, new RegExp(CONSTRAINT_NAME));
});

test("5 INSERT of the backup UUID as ACTIVE owner is blocked", () => {
  assert.equal(violatesOwnerMappingGuard({ auth_user_id: BACKUP_UUID, status: "ACTIVE", role: "owner" }, BACKUP_UUID), true);
});

test("6 UPDATE of the backup identity from operator to ACTIVE owner is blocked", () => {
  const existing = { auth_user_id: BACKUP_UUID, status: "ACTIVE", role: "operator" };
  assert.equal(violatesOwnerMappingGuard(existing, BACKUP_UUID), false);
  assert.equal(violatesOwnerMappingGuard({ ...existing, role: "owner" }, BACKUP_UUID), true);
});

test("7 UPDATE of an existing ACTIVE owner to the backup UUID is blocked", () => {
  const existing = { auth_user_id: OTHER_UUID, status: "ACTIVE", role: "owner" };
  assert.equal(violatesOwnerMappingGuard(existing, BACKUP_UUID), false);
  assert.equal(violatesOwnerMappingGuard({ ...existing, auth_user_id: BACKUP_UUID }, BACKUP_UUID), true);
});

test("8 concurrent UPDATE paths cannot commit a forbidden final row", () => {
  const startingRow = { auth_user_id: BACKUP_UUID, status: "DISABLED", role: "operator" };
  const roleFirstIntermediate = { ...startingRow, role: "owner" };
  const statusFirstIntermediate = { ...startingRow, status: "ACTIVE" };
  assert.equal(violatesOwnerMappingGuard(roleFirstIntermediate, BACKUP_UUID), false);
  assert.equal(violatesOwnerMappingGuard({ ...roleFirstIntermediate, status: "ACTIVE" }, BACKUP_UUID), true);
  assert.equal(violatesOwnerMappingGuard(statusFirstIntermediate, BACKUP_UUID), false);
  assert.equal(violatesOwnerMappingGuard({ ...statusFirstIntermediate, role: "owner" }, BACKUP_UUID), true);
});

test("9 other operators and allowed backup-identity states are unaffected", () => {
  assert.equal(violatesOwnerMappingGuard({ auth_user_id: OTHER_UUID, status: "ACTIVE", role: "owner" }, BACKUP_UUID), false);
  assert.equal(violatesOwnerMappingGuard({ auth_user_id: BACKUP_UUID, status: "ACTIVE", role: "operator" }, BACKUP_UUID), false);
  assert.equal(violatesOwnerMappingGuard({ auth_user_id: BACKUP_UUID, status: "DISABLED", role: "owner" }, BACKUP_UUID), false);
});

test("10 candidate uses a row-local CHECK for INSERT and UPDATE without broader behavior", () => {
  const sql = generateOwnerMappingGuardSql(BACKUP_UUID);
  assert.match(sql, /check\s*\(/i);
  assert.doesNotMatch(sql, /select\b|create\s+trigger|create\s+policy|create\s+(?:or\s+replace\s+)?function/i);
  assert.match(sql, /not\s+valid;[\s\S]*validate\s+constraint/i);
});