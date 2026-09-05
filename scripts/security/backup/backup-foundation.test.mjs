import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  BACKUP_TOOL_VERSION,
  BackupFoundationError,
  assertLocalDatabaseSource,
  createLocalBackup,
  decryptFile,
  manifestSha256,
  PRODUCTION_PROJECT_REFERENCE,
  readManifest,
  sha256File,
  validateManifest,
  verifyLocalRestore,
} from "./backup-foundation.mjs";
import { OFFSITE_BACKUP_CONTRACT } from "./offsite-provider-contract.mjs";

const source = Object.freeze({
  environment: "TEST",
  host: "127.0.0.1",
  port: 54322,
  database: "postgres",
  user: "postgres",
  projectReference: "local-supabase-test",
});
const target = Object.freeze({ ...source, database: "lws_restore_test_backup", projectReference: "local-restore-test" });
const syntheticDump = Buffer.from("PGDMP\nCREATE TABLE public.synthetic_backup_probe(id integer);\n", "utf8");

function expectCode(code) {
  return (error) => error instanceof BackupFoundationError && error.code === code;
}

async function fixture(t, overrides = {}) {
  const root = await mkdtemp(join(tmpdir(), "lws-backup-test-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const calls = [];
  let plaintextPath;
  const commandRunner = async (command, args) => {
    calls.push({ command, args });
    if (command === "pg_dump") {
      plaintextPath = args.find((value) => value.startsWith("--file=")).slice(7);
      await writeFile(plaintextPath, syntheticDump);
    }
    if (command === "psql") return { stdout: JSON.stringify({ schema_count: 1, object_count: 1 }) };
    return { stdout: "" };
  };
  const encryptionKey = overrides.encryptionKey || randomBytes(32);
  const logs = [];
  const backup = await createLocalBackup({
    source,
    outputDirectory: root,
    encryptionKey,
    encryptionKeyReference: "local-test-key-v1",
    databasePassword: "synthetic-password-never-logged",
    retentionUntil: "2026-10-05T12:00:00.000Z",
    schemaMigrationReference: "local-schema-head-test",
    now: () => new Date("2026-09-05T12:00:00.000Z"),
    backupIdFactory: () => "lws-db-local-test-001",
    commandRunner,
    logger: (event) => logs.push(event),
    ...overrides,
  });
  return { root, calls, plaintextPath, encryptionKey, logs, backup, commandRunner };
}

test("1 local database export foundation creates a synthetic package", async (t) => {
  const value = await fixture(t);
  assert.equal(value.calls[0].command, "pg_dump");
  assert.equal(value.backup.manifest.backup_type, "FULL_LOGICAL");
});

test("2 remote database hosts and connection strings are blocked before command execution", async () => {
  let called = false;
  await assert.rejects(createLocalBackup({
    source: { ...source, host: "db.example.test" }, outputDirectory: ".", encryptionKey: randomBytes(32),
    encryptionKeyReference: "local-key-v1", retentionUntil: "2026-10-05T12:00:00.000Z",
    schemaMigrationReference: "local-schema-head", commandRunner: async () => { called = true; },
  }), expectCode("REMOTE_DATABASE_HOST_BLOCKED"));
  assert.equal(called, false);
  await assert.rejects(createLocalBackup({
    source: { ...source, connectionString: "postgresql://user:password@localhost/postgres" }, outputDirectory: ".", encryptionKey: randomBytes(32),
    encryptionKeyReference: "local-key-v1", retentionUntil: "2026-10-05T12:00:00.000Z", schemaMigrationReference: "local-schema-head",
  }), expectCode("CONNECTION_STRING_FORBIDDEN"));
});

test("3 production project reference is blocked", async () => {
  await assert.rejects(createLocalBackup({
    source: { ...source, projectReference: PRODUCTION_PROJECT_REFERENCE }, outputDirectory: ".", encryptionKey: randomBytes(32),
    encryptionKeyReference: "local-key-v1", retentionUntil: "2026-10-05T12:00:00.000Z", schemaMigrationReference: "local-schema-head",
  }), expectCode("PRODUCTION_PROJECT_BLOCKED"));
});

test("4 plaintext checksum matches the synthetic export", async (t) => {
  const { backup } = await fixture(t);
  const expectedPath = join(dirname(backup.manifestPath), "expected.dump");
  await writeFile(expectedPath, syntheticDump);
  assert.equal(backup.manifest.database_export_sha256, await sha256File(expectedPath));
});

test("5 authenticated encrypted artifact is created", async (t) => {
  const { backup } = await fixture(t);
  assert.equal(existsSync(backup.encryptedArtifactPath), true);
  assert.equal((await readFile(backup.encryptedArtifactPath)).subarray(0, 8).toString("ascii"), "LWSBKP01");
});

test("6 plaintext export is removed after encryption", async (t) => {
  const { plaintextPath } = await fixture(t);
  assert.equal(existsSync(plaintextPath), false);
});

test("7 encrypted checksum matches the artifact", async (t) => {
  const { backup } = await fixture(t);
  assert.equal(backup.manifest.encrypted_artifact_sha256, await sha256File(backup.encryptedArtifactPath));
});

test("8 manifest contains every required contract field", async (t) => {
  const { backup } = await fixture(t);
  const schema = JSON.parse(await readFile(new URL("./backup-package.schema.json", import.meta.url), "utf8"));
  for (const field of ["backup_id", "backup_type", "source_environment", "source_project_reference", "captured_at", "database_export_filename", "database_export_sha256", "encrypted_artifact_sha256", "manifest_sha256", "encryption_algorithm", "encryption_key_reference", "retention_until", "created_by_tool_version", "schema_migration_reference", "verification_status"]) {
    assert.ok(backup.manifest[field], field);
    assert.ok(schema.required.includes(field), field);
  }
  assert.equal(backup.manifest.created_by_tool_version, BACKUP_TOOL_VERSION);
});

test("9 manifest rejects secret fields and credential-bearing values", async (t) => {
  const { backup } = await fixture(t);
  const withPassword = { ...backup.manifest, password: "not-allowed", manifest_sha256: "" };
  withPassword.manifest_sha256 = manifestSha256(withPassword);
  assert.throws(() => validateManifest(withPassword), expectCode("MANIFEST_SECRET_FIELD_BLOCKED"));
  const withConnection = { ...backup.manifest, source_project_reference: "postgresql://user:pass@localhost/db", manifest_sha256: "" };
  withConnection.manifest_sha256 = manifestSha256(withConnection);
  assert.throws(() => validateManifest(withConnection), expectCode("MANIFEST_SECRET_VALUE_BLOCKED"));
  const gitignore = await readFile(new URL("../../../.gitignore", import.meta.url), "utf8");
  assert.match(gitignore, /^\.local-backups\/$/m);
});

test("10 wrong encryption key fails authenticated decryption", async (t) => {
  const { root, backup, commandRunner } = await fixture(t);
  await assert.rejects(verifyLocalRestore({ packageDirectory: root, manifestFilename: backup.manifestPath.split(/[\\/]/).pop(), target, encryptionKey: randomBytes(32), encryptionKeyReference: "local-test-key-v1", commandRunner }), expectCode("DECRYPTION_AUTHENTICATION_FAILED"));
});

test("11 corrupted encrypted artifact fails before restore", async (t) => {
  const { root, backup, encryptionKey, commandRunner } = await fixture(t);
  const bytes = await readFile(backup.encryptedArtifactPath);
  bytes[25] ^= 0xff;
  await writeFile(backup.encryptedArtifactPath, bytes);
  await assert.rejects(verifyLocalRestore({ packageDirectory: root, manifestFilename: backup.manifestPath.split(/[\\/]/).pop(), target, encryptionKey, encryptionKeyReference: "local-test-key-v1", commandRunner }), expectCode("ENCRYPTED_ARTIFACT_CHECKSUM_MISMATCH"));
});

test("12 corrupted manifest fails its own checksum", async (t) => {
  const { backup } = await fixture(t);
  const manifest = JSON.parse(await readFile(backup.manifestPath, "utf8"));
  manifest.verification_status = "CORRUPTED";
  await writeFile(backup.manifestPath, JSON.stringify(manifest));
  await assert.rejects(readManifest(backup.manifestPath), expectCode("MANIFEST_CHECKSUM_MISMATCH"));
});

test("13 encrypted package restores only through disposable local test flow", async (t) => {
  const value = await fixture(t);
  const verified = await verifyLocalRestore({ packageDirectory: value.root, manifestFilename: value.backup.manifestPath.split(/[\\/]/).pop(), target, encryptionKey: value.encryptionKey, encryptionKeyReference: "local-test-key-v1", commandRunner: value.commandRunner });
  assert.equal(verified.verification_status, "VERIFIED_LOCAL_SYNTHETIC");
  assert.deepEqual(value.calls.slice(1).map(({ command }) => command), ["dropdb", "createdb", "pg_restore", "psql", "dropdb"]);
});

test("14 restore records schema and object sanity checks", async (t) => {
  const value = await fixture(t);
  const verified = await verifyLocalRestore({ packageDirectory: value.root, manifestFilename: value.backup.manifestPath.split(/[\\/]/).pop(), target, encryptionKey: value.encryptionKey, encryptionKeyReference: "local-test-key-v1", commandRunner: value.commandRunner });
  assert.deepEqual(verified.verification_result, { restore_environment: "TEST", schema_count: 1, object_count: 1 });
});

test("15 temporary decrypted plaintext is removed", async (t) => {
  const value = await fixture(t);
  let restoredPlaintextPath;
  const runner = async (command, args, context) => {
    if (command === "pg_restore") restoredPlaintextPath = args.at(-1);
    return value.commandRunner(command, args, context);
  };
  await verifyLocalRestore({ packageDirectory: value.root, manifestFilename: value.backup.manifestPath.split(/[\\/]/).pop(), target, encryptionKey: value.encryptionKey, encryptionKeyReference: "local-test-key-v1", commandRunner: runner });
  assert.ok(restoredPlaintextPath);
  assert.equal(existsSync(restoredPlaintextPath), false);
  const cleanupFailure = await fixture(t, { backupIdFactory: () => "lws-db-local-test-002" });
  let cleanupPlaintextPath;
  let dropCalls = 0;
  const failingCleanupRunner = async (command, args, context) => {
    if (command === "pg_restore") cleanupPlaintextPath = args.at(-1);
    if (command === "dropdb" && ++dropCalls === 2) throw new BackupFoundationError("SYNTHETIC_DROP_FAILED");
    return cleanupFailure.commandRunner(command, args, context);
  };
  await assert.rejects(verifyLocalRestore({ packageDirectory: cleanupFailure.root, manifestFilename: cleanupFailure.backup.manifestPath.split(/[\\/]/).pop(), target, encryptionKey: cleanupFailure.encryptionKey, encryptionKeyReference: "local-test-key-v1", commandRunner: failingCleanupRunner }), expectCode("RESTORE_DATABASE_CLEANUP_FAILED"));
  assert.equal(existsSync(cleanupPlaintextPath), false);
  assert.equal((await readManifest(cleanupFailure.backup.manifestPath)).verification_status, "ENCRYPTED_UNVERIFIED");
});

test("16 offsite contract has no network upload implementation", async () => {
  const sourceText = await readFile(new URL("./offsite-provider-contract.mjs", import.meta.url), "utf8");
  assert.equal(OFFSITE_BACKUP_CONTRACT.network_transport_implemented, false);
  assert.doesNotMatch(sourceText, /\bfetch\s*\(|https?:\/\/|\.request\s*\(|\.send\s*\(/);
});

test("17 backup foundation has no external provider dependency", async () => {
  const packageJson = await readFile(new URL("../../../package.json", import.meta.url), "utf8");
  const sourceText = await readFile(new URL("./offsite-provider-contract.mjs", import.meta.url), "utf8");
  assert.doesNotMatch(`${packageJson}\n${sourceText}`, /@aws-sdk|backblaze|azure-storage|google-cloud\/storage/i);
  assert.equal(OFFSITE_BACKUP_CONTRACT.provider_dependency, null);
});

test("18 guarded CLI exits non-zero without invoking a remote export", () => {
  const key = randomBytes(32).toString("base64");
  const cliPath = fileURLToPath(new URL("./create-local-backup.mjs", import.meta.url));
  const result = spawnSync(process.execPath, [cliPath, "--environment", "TEST", "--host", "remote.example.test", "--port", "5432", "--database", "postgres", "--user", "postgres", "--source-project-reference", "test-remote-host", "--output", ".", "--key-reference", "local-key", "--retention-days", "1", "--schema-migration-reference", "test-head"], { encoding: "utf8", env: { ...process.env, LWS_LOCAL_BACKUP_ENCRYPTION_KEY_B64: key } });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /REMOTE_DATABASE_HOST_BLOCKED/);
});

test("19 operational logs contain no credentials", async (t) => {
  const { logs, encryptionKey } = await fixture(t);
  const serialized = JSON.stringify(logs);
  assert.doesNotMatch(serialized, /synthetic-password-never-logged/);
  assert.doesNotMatch(serialized, new RegExp(encryptionKey.toString("base64").replace(/[+/]/g, "\\$&")));
  assert.doesNotMatch(serialized, /postgres(?:ql)?:\/\//i);
});

test("20 P0-6A truth and P0-3D fail-closed purge remain intact", async () => {
  const policy = await readFile(new URL("../../../docs/security/LWS_RECOVERY_AND_DISASTER_RECOVERY_POLICY_V1.md", import.meta.url), "utf8");
  const evidence = await readFile(new URL("../../../docs/security/LWS_AUTHORITATIVE_BACKUP_EVIDENCE_CONTRACT_V1.md", import.meta.url), "utf8");
  const migration = await readFile(new URL("../../../supabase/migrations/20260905040000_add_security_recovery_retention_foundation_v1.sql", import.meta.url), "utf8");
  assert.match(policy, /Independent\/offsite backup \| `MISSING`/);
  assert.match(policy, /Database restore test \| `MISSING`/);
  assert.match(policy, /`P0-3D_PURGE_UNBLOCK: NO-GO`/);
  assert.match(evidence, /AUTHORITATIVE_OBJECT_BACKUP_EVIDENCE_PRESENT: MISSING/);
  assert.match(migration, /return query select false, 'BACKUP_EVIDENCE_UNAVAILABLE'/);
});

test("21 exact environment and opaque local source contract rejects every remote form", async () => {
  assert.equal(assertLocalDatabaseSource({ ...source, environment: "LOCAL" }).environment, "LOCAL");
  assert.equal(assertLocalDatabaseSource({ ...source, environment: "TEST" }).environment, "TEST");
  for (const environment of ["local", "test", "Local", "TEST ", " LOCAL", "", null, undefined, "PRODUCTION"]) {
    assert.throws(() => assertLocalDatabaseSource({ ...source, environment }), expectCode("LOCAL_OR_TEST_ENVIRONMENT_REQUIRED"), String(environment));
  }
  for (const projectReference of ["local-safe", "test-safe-reference"]) {
    assert.equal(assertLocalDatabaseSource({ ...source, projectReference }).projectReference, projectReference);
  }
  for (const projectReference of [
    PRODUCTION_PROJECT_REFERENCE,
    `local-${PRODUCTION_PROJECT_REFERENCE}-copy`,
  ]) {
    assert.throws(() => assertLocalDatabaseSource({ ...source, projectReference }), expectCode("PRODUCTION_PROJECT_BLOCKED"), projectReference);
  }
  for (const projectReference of [
    `https://${PRODUCTION_PROJECT_REFERENCE}.supabase.co`, "https://example.com", "http://example.com",
    "remote.supabase.co", "remote.example.com", "203.0.113.10", "postgresql://user:pass@localhost/db", "", null, undefined,
  ]) {
    assert.throws(() => assertLocalDatabaseSource({ ...source, projectReference }), undefined, String(projectReference));
  }

  let createRunnerCalled = false;
  await assert.rejects(createLocalBackup({
    source: { ...source, environment: "local" }, outputDirectory: ".", encryptionKey: randomBytes(32),
    encryptionKeyReference: "local-key-v1", retentionUntil: "2026-10-05T12:00:00.000Z", schemaMigrationReference: "local-schema-head",
    commandRunner: async () => { createRunnerCalled = true; },
  }), expectCode("LOCAL_OR_TEST_ENVIRONMENT_REQUIRED"));
  assert.equal(createRunnerCalled, false);
});

test("22 invalid manifest source cannot reach restore commands or become verified", async (t) => {
  const value = await fixture(t, { backupIdFactory: () => "lws-db-local-test-003" });
  const originalCallCount = value.calls.length;
  const invalidReferences = [
    `https://${PRODUCTION_PROJECT_REFERENCE}.supabase.co`, "https://example.com", "remote.supabase.co",
    `local-${PRODUCTION_PROJECT_REFERENCE}-copy`, "postgresql://user:pass@localhost/db",
  ];
  for (const sourceProjectReference of invalidReferences) {
    const manifest = { ...value.backup.manifest, source_project_reference: sourceProjectReference, manifest_sha256: "" };
    manifest.manifest_sha256 = manifestSha256(manifest);
    await writeFile(value.backup.manifestPath, JSON.stringify(manifest));
    assert.throws(() => validateManifest(manifest), undefined, sourceProjectReference);
    await assert.rejects(verifyLocalRestore({ packageDirectory: value.root, manifestFilename: value.backup.manifestPath.split(/[\\/]/).pop(), target, encryptionKey: value.encryptionKey, encryptionKeyReference: "local-test-key-v1", commandRunner: value.commandRunner }));
    assert.equal(value.calls.length, originalCallCount);
    assert.equal(JSON.parse(await readFile(value.backup.manifestPath, "utf8")).verification_status, "ENCRYPTED_UNVERIFIED");
  }
});