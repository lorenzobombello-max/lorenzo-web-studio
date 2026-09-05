import { createCipheriv, createDecipheriv, createHash, randomBytes, randomUUID } from "node:crypto";
import { createReadStream, createWriteStream } from "node:fs";
import { appendFile, mkdtemp, mkdir, open, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, join, resolve, sep } from "node:path";
import { spawn } from "node:child_process";
import { pipeline } from "node:stream/promises";

export const BACKUP_TOOL_VERSION = "lws-local-backup-foundation/1.0.0";
export const ENCRYPTION_ALGORITHM = "AES-256-GCM";
export const PRODUCTION_PROJECT_REFERENCE = "xcsptvntvrizwhskaphr";
const ARTIFACT_MAGIC = Buffer.from("LWSBKP01", "ascii");
const NONCE_BYTES = 12;
const AUTH_TAG_BYTES = 16;
const SHA256_PATTERN = /^[a-f0-9]{64}$/;
const SAFE_IDENTIFIER_PATTERN = /^[A-Za-z_][A-Za-z0-9_]*$/;
const SAFE_REFERENCE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$/;
const SAFE_LOCAL_SOURCE_REFERENCE_PATTERN = /^(?:local|test)(?:-[a-z0-9]+){1,7}$/;
const FORBIDDEN_MANIFEST_KEY = /^(?:password|passwd|secret|token|jwt|api[_-]?key|service[_-]?role(?:[_-]?key)?|private[_-]?key|signing[_-]?material|connection[_-]?string|database[_-]?url|dsn)$/i;
const FORBIDDEN_MANIFEST_VALUE = /(?:postgres(?:ql)?:\/\/[^\s]*@|service[_-]?role|eyJ[a-zA-Z0-9_-]{8,}\.[a-zA-Z0-9_-]{8,}\.)/i;

export class BackupFoundationError extends Error {
  constructor(code, message = code) {
    super(message);
    this.name = "BackupFoundationError";
    this.code = code;
  }
}

const fail = (code) => { throw new BackupFoundationError(code); };

export function assertLocalSourceIdentity(environment, projectReference, {
  environmentCode = "LOCAL_OR_TEST_ENVIRONMENT_REQUIRED",
  referenceCode = "SAFE_LOCAL_PROJECT_REFERENCE_REQUIRED",
} = {}) {
  if (environment !== "LOCAL" && environment !== "TEST") fail(environmentCode);
  if (typeof projectReference !== "string" || !projectReference) fail(referenceCode);
  const normalizedReference = projectReference.toLowerCase();
  if (normalizedReference.includes(PRODUCTION_PROJECT_REFERENCE)) fail("PRODUCTION_PROJECT_BLOCKED");
  if (!SAFE_LOCAL_SOURCE_REFERENCE_PATTERN.test(projectReference)) fail(referenceCode);
  return { environment, projectReference };
}

export function assertLocalDatabaseSource(source, { restore = false } = {}) {
  if (!source || typeof source !== "object") fail("LOCAL_SOURCE_REQUIRED");
  for (const key of ["connectionString", "connection_string", "databaseUrl", "database_url", "url", "dsn"]) {
    if (source[key]) fail("CONNECTION_STRING_FORBIDDEN");
  }
  const { environment, projectReference } = assertLocalSourceIdentity(source.environment, source.projectReference);
  const host = String(source.host || "").toLowerCase();
  const port = Number(source.port);
  if (!new Set(["localhost", "127.0.0.1"]).has(host)) fail("REMOTE_DATABASE_HOST_BLOCKED");
  if (!Number.isInteger(port) || port < 1 || port > 65535) fail("LOCAL_DATABASE_PORT_INVALID");
  if (!SAFE_IDENTIFIER_PATTERN.test(String(source.database || ""))) fail("LOCAL_DATABASE_NAME_INVALID");
  if (!SAFE_IDENTIFIER_PATTERN.test(String(source.user || ""))) fail("LOCAL_DATABASE_USER_INVALID");
  if (restore && (environment !== "TEST" || !String(source.database).startsWith("lws_restore_test_"))) {
    fail("DISPOSABLE_TEST_DATABASE_REQUIRED");
  }
  return { environment, host, port, database: String(source.database), user: String(source.user), projectReference };
}

export function decodeEncryptionKey(encoded) {
  if (typeof encoded !== "string" || !/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) fail("ENCRYPTION_KEY_REQUIRED");
  const key = Buffer.from(encoded, "base64");
  if (key.length !== 32) fail("ENCRYPTION_KEY_MUST_BE_32_BYTES");
  return key;
}

export async function sha256File(path) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest("hex");
}

function canonicalize(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalize).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalize(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

export function manifestSha256(manifest) {
  const unsigned = { ...manifest };
  delete unsigned.manifest_sha256;
  return createHash("sha256").update(canonicalize(unsigned), "utf8").digest("hex");
}

function assertNoSecrets(value, path = "manifest") {
  if (Array.isArray(value)) return value.forEach((item, index) => assertNoSecrets(item, `${path}[${index}]`));
  if (value && typeof value === "object") {
    for (const [key, nested] of Object.entries(value)) {
      if (FORBIDDEN_MANIFEST_KEY.test(key)) fail("MANIFEST_SECRET_FIELD_BLOCKED");
      assertNoSecrets(nested, `${path}.${key}`);
    }
    return;
  }
  if (typeof value === "string" && FORBIDDEN_MANIFEST_VALUE.test(value)) fail("MANIFEST_SECRET_VALUE_BLOCKED");
}

export function validateManifest(manifest) {
  const required = [
    "backup_id", "backup_type", "source_environment", "source_project_reference", "captured_at",
    "database_export_filename", "database_export_sha256", "encrypted_artifact_filename",
    "encrypted_artifact_sha256", "manifest_sha256", "encryption_algorithm", "encryption_key_reference",
    "retention_until", "created_by_tool_version", "schema_migration_reference", "verification_status",
  ];
  if (!manifest || typeof manifest !== "object" || required.some((key) => !manifest[key])) fail("MANIFEST_INCOMPLETE");
  assertNoSecrets(manifest);
  assertLocalSourceIdentity(manifest.source_environment, manifest.source_project_reference, {
    environmentCode: "MANIFEST_ENVIRONMENT_INVALID",
    referenceCode: "MANIFEST_SOURCE_REFERENCE_INVALID",
  });
  if (!SHA256_PATTERN.test(manifest.database_export_sha256) || !SHA256_PATTERN.test(manifest.encrypted_artifact_sha256) || !SHA256_PATTERN.test(manifest.manifest_sha256)) fail("MANIFEST_CHECKSUM_INVALID");
  if (manifest.encryption_algorithm !== ENCRYPTION_ALGORITHM) fail("MANIFEST_ENCRYPTION_ALGORITHM_INVALID");
  if (!SAFE_REFERENCE_PATTERN.test(manifest.encryption_key_reference) || !SAFE_REFERENCE_PATTERN.test(manifest.schema_migration_reference)) fail("MANIFEST_REFERENCE_INVALID");
  if (basename(manifest.database_export_filename) !== manifest.database_export_filename || basename(manifest.encrypted_artifact_filename) !== manifest.encrypted_artifact_filename) fail("MANIFEST_FILENAME_INVALID");
  if (!Number.isFinite(Date.parse(manifest.captured_at)) || Date.parse(manifest.retention_until) <= Date.parse(manifest.captured_at)) fail("MANIFEST_RETENTION_INVALID");
  if (manifestSha256(manifest) !== manifest.manifest_sha256) fail("MANIFEST_CHECKSUM_MISMATCH");
  return manifest;
}

async function writeManifest(path, manifest) {
  const next = { ...manifest, manifest_sha256: "" };
  next.manifest_sha256 = manifestSha256(next);
  const temporaryPath = `${path}.partial`;
  await writeFile(temporaryPath, `${JSON.stringify(next, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
  await rename(temporaryPath, path);
  return next;
}

export async function readManifest(path) {
  let manifest;
  try {
    manifest = JSON.parse(await readFile(path, "utf8"));
  } catch {
    fail("MANIFEST_READ_FAILED");
  }
  return validateManifest(manifest);
}

export async function encryptFile(plaintextPath, encryptedPath, key, { nonce = randomBytes(NONCE_BYTES) } = {}) {
  if (!Buffer.isBuffer(key) || key.length !== 32) fail("ENCRYPTION_KEY_MUST_BE_32_BYTES");
  if (!Buffer.isBuffer(nonce) || nonce.length !== NONCE_BYTES) fail("ENCRYPTION_NONCE_INVALID");
  const cipher = createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(ARTIFACT_MAGIC);
  await writeFile(encryptedPath, Buffer.concat([ARTIFACT_MAGIC, nonce]), { mode: 0o600 });
  try {
    await pipeline(createReadStream(plaintextPath), cipher, createWriteStream(encryptedPath, { flags: "a", mode: 0o600 }));
    await appendFile(encryptedPath, cipher.getAuthTag());
  } catch (error) {
    await rm(encryptedPath, { force: true });
    throw new BackupFoundationError("ENCRYPTION_FAILED", error instanceof Error ? error.message : "ENCRYPTION_FAILED");
  }
}

export async function decryptFile(encryptedPath, plaintextPath, key) {
  if (!Buffer.isBuffer(key) || key.length !== 32) fail("ENCRYPTION_KEY_MUST_BE_32_BYTES");
  const info = await stat(encryptedPath);
  if (info.size <= ARTIFACT_MAGIC.length + NONCE_BYTES + AUTH_TAG_BYTES) fail("ENCRYPTED_ARTIFACT_INVALID");
  const handle = await open(encryptedPath, "r");
  const prefix = Buffer.alloc(ARTIFACT_MAGIC.length + NONCE_BYTES);
  const tag = Buffer.alloc(AUTH_TAG_BYTES);
  await handle.read(prefix, 0, prefix.length, 0);
  await handle.read(tag, 0, tag.length, info.size - AUTH_TAG_BYTES);
  await handle.close();
  if (!prefix.subarray(0, ARTIFACT_MAGIC.length).equals(ARTIFACT_MAGIC)) fail("ENCRYPTED_ARTIFACT_HEADER_INVALID");
  const nonce = prefix.subarray(ARTIFACT_MAGIC.length);
  const decipher = createDecipheriv("aes-256-gcm", key, nonce);
  decipher.setAAD(ARTIFACT_MAGIC);
  decipher.setAuthTag(tag);
  try {
    await pipeline(
      createReadStream(encryptedPath, { start: prefix.length, end: info.size - AUTH_TAG_BYTES - 1 }),
      decipher,
      createWriteStream(plaintextPath, { mode: 0o600 }),
    );
  } catch {
    await rm(plaintextPath, { force: true });
    fail("DECRYPTION_AUTHENTICATION_FAILED");
  }
}

export function runLocalCommand(command, args, { env = process.env } = {}) {
  return new Promise((resolveCommand, rejectCommand) => {
    const child = spawn(command, args, { env, windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", () => {});
    child.once("error", () => rejectCommand(new BackupFoundationError("LOCAL_COMMAND_START_FAILED")));
    child.once("close", (code) => code === 0 ? resolveCommand({ stdout }) : rejectCommand(new BackupFoundationError("LOCAL_COMMAND_FAILED")));
  });
}

function commandEnvironment(password) {
  return password ? { ...process.env, PGPASSWORD: password } : { ...process.env };
}

function emit(logger, event, details = {}) {
  logger?.({ event, ...details });
}

export async function createLocalBackup(options) {
  const source = assertLocalDatabaseSource(options.source);
  if (!Buffer.isBuffer(options.encryptionKey) || options.encryptionKey.length !== 32) fail("ENCRYPTION_KEY_MUST_BE_32_BYTES");
  if (!SAFE_REFERENCE_PATTERN.test(String(options.encryptionKeyReference || ""))) fail("ENCRYPTION_KEY_REFERENCE_REQUIRED");
  if (!SAFE_REFERENCE_PATTERN.test(String(options.schemaMigrationReference || ""))) fail("SCHEMA_MIGRATION_REFERENCE_REQUIRED");
  const capturedAt = (options.now?.() || new Date()).toISOString();
  const retentionUntil = new Date(options.retentionUntil).toISOString();
  if (Date.parse(retentionUntil) <= Date.parse(capturedAt)) fail("RETENTION_MUST_BE_FUTURE");
  const backupId = options.backupIdFactory?.() || `lws-db-${capturedAt.replace(/[-:.TZ]/g, "")}-${randomUUID()}`;
  if (!SAFE_REFERENCE_PATTERN.test(backupId)) fail("BACKUP_ID_INVALID");
  const outputDirectory = resolve(options.outputDirectory);
  const encryptedArtifactFilename = `${backupId}.dump.enc`;
  const databaseExportFilename = `${backupId}.dump`;
  const manifestFilename = `${backupId}.manifest.json`;
  const encryptedArtifactPath = join(outputDirectory, encryptedArtifactFilename);
  const manifestPath = join(outputDirectory, manifestFilename);
  const temporaryDirectory = await mkdtemp(join(tmpdir(), "lws-local-backup-"));
  const plaintextPath = join(temporaryDirectory, databaseExportFilename);
  const run = options.commandRunner || runLocalCommand;
  await mkdir(outputDirectory, { recursive: true });
  try {
    emit(options.logger, "local_export_started", { backup_id: backupId, source_environment: source.environment });
    await run("pg_dump", [
      "--host", source.host, "--port", String(source.port), "--username", source.user, "--dbname", source.database,
      "--format=custom", `--file=${plaintextPath}`, "--no-owner", "--no-privileges",
    ], { env: commandEnvironment(options.databasePassword) });
    if ((await stat(plaintextPath)).size < 1) fail("DATABASE_EXPORT_EMPTY");
    const databaseExportSha256 = await sha256File(plaintextPath);
    await encryptFile(plaintextPath, encryptedArtifactPath, options.encryptionKey, options.cryptoOptions);
    const encryptedArtifactSha256 = await sha256File(encryptedArtifactPath);
    await rm(plaintextPath, { force: true });
    const manifest = await writeManifest(manifestPath, {
      backup_id: backupId,
      backup_type: options.backupType || "FULL_LOGICAL",
      source_environment: source.environment,
      source_project_reference: source.projectReference,
      captured_at: capturedAt,
      database_export_filename: databaseExportFilename,
      database_export_sha256: databaseExportSha256,
      encrypted_artifact_filename: encryptedArtifactFilename,
      encrypted_artifact_sha256: encryptedArtifactSha256,
      manifest_sha256: "",
      encryption_algorithm: ENCRYPTION_ALGORITHM,
      encryption_key_reference: options.encryptionKeyReference,
      retention_until: retentionUntil,
      created_by_tool_version: BACKUP_TOOL_VERSION,
      schema_migration_reference: options.schemaMigrationReference,
      verification_status: "ENCRYPTED_UNVERIFIED",
    });
    validateManifest(manifest);
    emit(options.logger, "local_backup_created", { backup_id: backupId, verification_status: manifest.verification_status });
    return { encryptedArtifactPath, manifestPath, manifest };
  } catch (error) {
    await rm(encryptedArtifactPath, { force: true });
    await rm(manifestPath, { force: true });
    emit(options.logger, "local_backup_failed", { code: error?.code || "BACKUP_FAILED" });
    throw error;
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
}

function safePackagePath(directory, filename) {
  const base = resolve(directory);
  const target = resolve(base, filename);
  if (!target.startsWith(`${base}${sep}`) || basename(filename) !== filename) fail("PACKAGE_PATH_INVALID");
  return target;
}

export async function verifyLocalRestore(options) {
  const target = assertLocalDatabaseSource(options.target, { restore: true });
  const manifestPath = safePackagePath(options.packageDirectory, options.manifestFilename);
  const manifest = await readManifest(manifestPath);
  if (manifest.encryption_key_reference !== options.encryptionKeyReference) fail("ENCRYPTION_KEY_REFERENCE_MISMATCH");
  const encryptedArtifactPath = safePackagePath(options.packageDirectory, manifest.encrypted_artifact_filename);
  if (await sha256File(encryptedArtifactPath) !== manifest.encrypted_artifact_sha256) fail("ENCRYPTED_ARTIFACT_CHECKSUM_MISMATCH");
  const temporaryDirectory = await mkdtemp(join(tmpdir(), "lws-local-restore-"));
  const plaintextPath = join(temporaryDirectory, manifest.database_export_filename);
  const run = options.commandRunner || runLocalCommand;
  let databaseCreated = false;
  let sanity;
  try {
    await decryptFile(encryptedArtifactPath, plaintextPath, options.encryptionKey);
    if (await sha256File(plaintextPath) !== manifest.database_export_sha256) fail("PLAINTEXT_CHECKSUM_MISMATCH");
    const environment = commandEnvironment(options.databasePassword);
    const connectionArgs = ["--host", target.host, "--port", String(target.port), "--username", target.user];
    await run("dropdb", [...connectionArgs, "--if-exists", target.database], { env: environment });
    await run("createdb", [...connectionArgs, target.database], { env: environment });
    databaseCreated = true;
    await run("pg_restore", [...connectionArgs, `--dbname=${target.database}`, "--exit-on-error", "--no-owner", "--no-privileges", plaintextPath], { env: environment });
    const sanityResult = await run("psql", [...connectionArgs, `--dbname=${target.database}`, "--tuples-only", "--no-align", "--command", "select json_build_object('schema_count', count(distinct schemaname), 'object_count', count(*)) from pg_catalog.pg_tables where schemaname not in ('pg_catalog', 'information_schema')"], { env: environment });
    try { sanity = JSON.parse(String(sanityResult.stdout || "").trim()); } catch { fail("RESTORE_SANITY_RESULT_INVALID"); }
    if (!Number.isInteger(sanity.schema_count) || sanity.schema_count < 1 || !Number.isInteger(sanity.object_count) || sanity.object_count < 1) fail("RESTORE_SANITY_CHECK_FAILED");
  } catch (error) {
    emit(options.logger, "local_restore_failed", { code: error?.code || "RESTORE_FAILED" });
    throw error;
  } finally {
    let cleanupError = null;
    try {
      if (databaseCreated) await run("dropdb", ["--host", target.host, "--port", String(target.port), "--username", target.user, "--if-exists", target.database], { env: commandEnvironment(options.databasePassword) });
    } catch {
      cleanupError = new BackupFoundationError("RESTORE_DATABASE_CLEANUP_FAILED");
      emit(options.logger, "local_restore_cleanup_failed", { code: cleanupError.code });
    }
    await rm(plaintextPath, { force: true });
    await rm(temporaryDirectory, { recursive: true, force: true });
    if (cleanupError) throw cleanupError;
  }
  const verifiedAt = (options.now?.() || new Date()).toISOString();
  const verifiedManifest = await writeManifest(manifestPath, {
    ...manifest,
    manifest_sha256: "",
    verification_status: "VERIFIED_LOCAL_SYNTHETIC",
    verified_at: verifiedAt,
    verification_result: {
      restore_environment: target.environment,
      schema_count: sanity.schema_count,
      object_count: sanity.object_count,
    },
  });
  emit(options.logger, "local_restore_verified", { backup_id: manifest.backup_id, verification_status: verifiedManifest.verification_status });
  return verifiedManifest;
}

export function parseArguments(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    if (!key?.startsWith("--") || argv[index + 1] === undefined) fail("CLI_ARGUMENT_INVALID");
    if (Object.hasOwn(result, key.slice(2))) fail("CLI_ARGUMENT_DUPLICATE");
    result[key.slice(2)] = argv[index + 1];
  }
  return result;
}