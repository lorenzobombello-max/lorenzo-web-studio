const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const { after, before, test } = require("node:test");

const container = process.env.MIGRATION_01500_TEST_CONTAINER;
const database = `lws_migration_01500_${process.pid}`;
const signature =
  "public.prepare_website_delivery_document_v1(uuid,date,jsonb,text,text,date,text,date,text,uuid,text)";
const migrationPath = path.join(
  __dirname,
  "../supabase/migrations/20261012001500_preserve_website_delivery_legacy_idempotency_v1.sql",
);
const migrationSource = readFileSync(migrationPath, "utf8");
const migrationSourceLf = migrationSource.replace(/\r\n/g, "\n");
const anchor = `
  if found then
    if v_existing.project_id <> p_project_id or v_existing.generation_payload_sha256 <> v_payload_sha256 then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'candidate_id', v_existing.candidate_id, 'document_version', v_existing.document_version,
      'generation_payload', v_existing.generation_payload,
      'generation_payload_sha256', rtrim(v_existing.generation_payload_sha256), 'was_created', false
    );
  end if;
`;

function dockerPsql(targetDatabase, sql) {
  return spawnSync(
    "docker",
    [
      "exec",
      "-i",
      container ?? "",
      "psql",
      "-X",
      "-U",
      "postgres",
      "-d",
      targetDatabase,
      "-v",
      "ON_ERROR_STOP=1",
      "-At",
    ],
    { encoding: "utf8", input: sql },
  );
}

function runSql(targetDatabase, sql) {
  const result = dockerPsql(targetDatabase, sql);
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout);
  }
  return result.stdout.trim().split(/\r?\n/).filter(Boolean).at(-1) ?? "";
}

function assertLocalContainer() {
  if (!/^supabase_db_[a-z0-9_-]+$/.test(container ?? "")) {
    throw new Error("MIGRATION_01500_LOCAL_TEST_CONTAINER_REQUIRED");
  }
  const result = spawnSync(
    "docker",
    ["inspect", "--format", "{{.Name}}|{{.State.Status}}|{{.State.Health.Status}}", container],
    { encoding: "utf8" },
  );
  assert.equal(
    result.status,
    0,
    `MIGRATION_01500_LOCAL_TEST_CONTAINER_INVALID:${result.stderr || result.stdout}`,
  );
  assert.equal(result.stdout.trim(), `/${container}|running|healthy`);
}

function fixtureSql(anchorSource = anchor) {
  return `
    set check_function_bodies = off;
    create schema if not exists lws_internal;
    create or replace function ${signature}
    returns jsonb
    language plpgsql
    security definer
    set search_path = public, lws_internal, extensions, pg_catalog
    as $function$
    declare
      v_existing record;
      v_payload_sha256 text;
    begin
${anchorSource}
      return '{}'::jsonb;
    end;
    $function$;
    revoke all on function ${signature} from public;
    grant execute on function ${signature} to service_role;
    comment on function ${signature} is 'migration 01500 newline fixture';
  `;
}

function resetFixture(anchorSource = anchor) {
  runSql(database, `drop function if exists ${signature}; ${fixtureSql(anchorSource)}`);
}

function functionSnapshot() {
  return runSql(
    database,
    `
      select jsonb_build_object(
        'definition', pg_get_functiondef(function.oid),
        'owner', function.proowner,
        'acl', function.proacl,
        'security_definer', function.prosecdef,
        'config', function.proconfig,
        'comment', obj_description(function.oid, 'pg_proc')
      )::text
      from pg_proc as function
      where function.oid = '${signature}'::regprocedure;
    `,
  );
}

function applyMigration(source) {
  return dockerPsql(database, source);
}

function assertSuccess(result) {
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.deepEqual(
    JSON.parse(runSql(
      database,
      `
        select jsonb_build_object(
          'replacement_count',
          regexp_count(function.prosrc, 'v_legacy_payload jsonb := jsonb_set'),
          'owner', owner.rolname,
          'acl', function.proacl,
          'security_definer', function.prosecdef,
          'config', function.proconfig
        )::text
        from pg_proc as function
        join pg_roles as owner on owner.oid = function.proowner
        where function.oid = '${signature}'::regprocedure;
      `,
    )),
    {
      replacement_count: 1,
      owner: "postgres",
      acl: ["postgres=X/postgres", "service_role=X/postgres"],
      security_definer: true,
      config: ["search_path=public, lws_internal, extensions, pg_catalog"],
    },
  );
}

function assertSourceMismatch(result) {
  assert.notEqual(result.status, 0, "migration unexpectedly succeeded");
  assert.match(result.stderr, /WEBSITE_DELIVERY_LEGACY_IDEMPOTENCY_SOURCE_MISMATCH/);
}

before(() => {
  assertLocalContainer();
  runSql("postgres", `drop database if exists ${database} with (force);`);
  runSql("postgres", `create database ${database} template template0;`);
});

after(() => {
  runSql("postgres", `drop database if exists ${database} with (force);`);
});

test("real migration source applies with LF newlines and replaces exactly once", () => {
  resetFixture();
  assertSuccess(applyMigration(migrationSourceLf));
});

test("real migration source applies with CRLF newlines and replaces exactly once", () => {
  const anchorCrlf = anchor.replace(/\n/g, "\r\n");
  resetFixture(anchorCrlf);
  assert.equal(JSON.parse(functionSnapshot()).definition.includes(anchorCrlf), true);
  assertSuccess(applyMigration(migrationSource.replace(/\r?\n/g, "\r\n")));
});

test("real migration source fails closed when the anchor is absent", () => {
  resetFixture(anchor.replace("if found then", "if found and false then"));
  const beforeSnapshot = functionSnapshot();
  const result = applyMigration(migrationSourceLf);
  assertSourceMismatch(result);
  assert.equal(functionSnapshot(), beforeSnapshot);
});

test("real migration source fails closed when the anchor is duplicated", () => {
  resetFixture(`${anchor}\n${anchor}`);
  const beforeSnapshot = functionSnapshot();
  const result = applyMigration(migrationSourceLf);
  assertSourceMismatch(result);
  assert.equal(functionSnapshot(), beforeSnapshot);
});

test("post-verification failure rolls back function body and security metadata", () => {
  resetFixture();
  const beforeSnapshot = functionSnapshot();
  runSql(
    database,
    `
      create or replace function public.force_01500_postverify_failure()
      returns event_trigger
      language plpgsql
      as $trigger$
      begin
        if tg_tag = 'CREATE FUNCTION'
           and exists (
             select 1
             from pg_proc
             where oid = '${signature}'::regprocedure
               and prosrc like '%v_legacy_payload_sha256%'
           ) then
          alter function ${signature} security invoker;
        end if;
      end;
      $trigger$;
      create event trigger force_01500_postverify_failure
        on ddl_command_end
        execute function public.force_01500_postverify_failure();
    `,
  );
  try {
    const result = applyMigration(migrationSourceLf);
    assert.notEqual(result.status, 0, "migration unexpectedly succeeded");
    assert.match(result.stderr, /WEBSITE_DELIVERY_LEGACY_IDEMPOTENCY_POSTVERIFY_FAILED/);
    assert.equal(functionSnapshot(), beforeSnapshot);
  } finally {
    runSql(
      database,
      `
        drop event trigger if exists force_01500_postverify_failure;
        drop function if exists public.force_01500_postverify_failure();
      `,
    );
  }
});
