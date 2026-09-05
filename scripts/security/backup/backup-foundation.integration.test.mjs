import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { createLocalBackup, verifyLocalRestore } from "./backup-foundation.mjs";

const enabled = process.env.LWS_RUN_LOCAL_BACKUP_INTEGRATION === "1";
const container = process.env.LWS_LOCAL_POSTGRES_CONTAINER || "supabase_db_xcsptvntvrizwhskaphr";
const sourceDatabase = "lws_backup_source_test_p06b";
const restoreDatabase = "lws_restore_test_p06b";

function docker(args, { encoding = "utf8" } = {}) {
  const result = spawnSync("docker", args, { encoding, maxBuffer: 16 * 1024 * 1024, windowsHide: true });
  if (result.status !== 0) throw new Error(`LOCAL_DOCKER_COMMAND_FAILED:${args[1] || "unknown"}`);
  return result.stdout;
}

function databaseCommand(command, database, extra = []) {
  return docker(["exec", container, command, "--username", "postgres", "--dbname", database, ...extra]);
}

test("real local PostgreSQL export encrypt restore and cleanup uses synthetic data only", { skip: !enabled }, async (t) => {
  const outputDirectory = await mkdtemp(join(tmpdir(), "lws-backup-integration-"));
  const containerPlaintext = `/tmp/${sourceDatabase}.dump`;
  t.after(async () => {
    docker(["exec", container, "dropdb", "--username", "postgres", "--if-exists", sourceDatabase]);
    docker(["exec", container, "dropdb", "--username", "postgres", "--if-exists", restoreDatabase]);
    docker(["exec", container, "rm", "-f", containerPlaintext]);
    await rm(outputDirectory, { recursive: true, force: true });
  });

  docker(["exec", container, "dropdb", "--username", "postgres", "--if-exists", sourceDatabase]);
  docker(["exec", container, "createdb", "--username", "postgres", sourceDatabase]);
  databaseCommand("psql", sourceDatabase, ["--command", "create schema synthetic_backup; create table synthetic_backup.probe(id integer primary key, label text not null); insert into synthetic_backup.probe values (1, 'synthetic-only');"]);

  const commandRunner = async (command, args) => {
    if (command === "pg_dump") {
      const plaintextPath = args.find((value) => value.startsWith("--file=")).slice(7);
      const bytes = docker(["exec", container, "pg_dump", "--username", "postgres", "--dbname", sourceDatabase, "--format=custom", "--no-owner", "--no-privileges"], { encoding: null });
      await writeFile(plaintextPath, bytes);
      return { stdout: "" };
    }
    const database = args.find((value) => value.startsWith("--dbname="))?.slice(9) || args.at(-1);
    if (command === "dropdb") {
      docker(["exec", container, "dropdb", "--username", "postgres", "--if-exists", database]);
      return { stdout: "" };
    }
    if (command === "createdb") {
      docker(["exec", container, "createdb", "--username", "postgres", database]);
      return { stdout: "" };
    }
    if (command === "pg_restore") {
      const plaintextPath = args.at(-1);
      docker(["cp", plaintextPath, `${container}:${containerPlaintext}`]);
      docker(["exec", container, "pg_restore", "--username", "postgres", `--dbname=${database}`, "--exit-on-error", "--no-owner", "--no-privileges", containerPlaintext]);
      docker(["exec", container, "rm", "-f", containerPlaintext]);
      return { stdout: "" };
    }
    if (command === "psql") {
      const stdout = databaseCommand("psql", database, ["--tuples-only", "--no-align", "--command", "select json_build_object('schema_count', count(distinct schemaname), 'object_count', count(*)) from pg_catalog.pg_tables where schemaname not in ('pg_catalog', 'information_schema')"]);
      return { stdout };
    }
    throw new Error("UNEXPECTED_LOCAL_COMMAND");
  };

  const encryptionKey = randomBytes(32);
  const backup = await createLocalBackup({
    source: { environment: "TEST", host: "127.0.0.1", port: 54322, database: sourceDatabase, user: "postgres", projectReference: "local-docker-synthetic" },
    outputDirectory,
    encryptionKey,
    encryptionKeyReference: "local-integration-key-v1",
    retentionUntil: new Date(Date.now() + 86400000),
    schemaMigrationReference: "synthetic-local-schema-v1",
    commandRunner,
  });
  const verified = await verifyLocalRestore({
    packageDirectory: outputDirectory,
    manifestFilename: basename(backup.manifestPath),
    target: { environment: "TEST", host: "127.0.0.1", port: 54322, database: restoreDatabase, user: "postgres", projectReference: "local-docker-restore" },
    encryptionKey,
    encryptionKeyReference: "local-integration-key-v1",
    commandRunner,
  });
  assert.equal(verified.verification_status, "VERIFIED_LOCAL_SYNTHETIC");
  assert.ok(verified.verification_result.schema_count >= 1);
  assert.ok(verified.verification_result.object_count >= 1);
});