import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migration = new URL("../supabase/migrations/20261027220000_add_website_project_preview_dispatch_v1.sql", import.meta.url);
const sql = await readFile(migration, "utf8");
function body(name) {
  const escaped = name.replaceAll(".", "\\.");
  const match = sql.match(new RegExp(`create function ${escaped}\\([\\s\\S]*?as \\$\\$([\\s\\S]*?)\\$\\$;`, "i"));
  assert.ok(match, `Missing function ${name}`);
  return match[1];
}

function before(text, first, second) {
  assert.ok(text.includes(first), `Missing ${first}`);
  assert.ok(text.includes(second), `Missing ${second}`);
  assert.ok(text.indexOf(first) < text.indexOf(second), `${first} must precede ${second}`);
}

// Structural regression guards only; SQL execution and contention require PostgreSQL.
test("R1: acquisition and expiry enter the same transaction gate before taking row locks", () => {
  assert.match(body("lws_internal.lock_preview_lifecycle_v1"),
    /pg_advisory_xact_lock\(hashtextextended\('website-project-preview-lifecycle:v1',0\)\)/);
  assert.doesNotMatch(sql, /'preview-dispatch:'/);
  before(body("public.acquire_website_project_preview_build_v1"),
    "lock_preview_lifecycle_v1()", "acquire_preview_pre_dispatch_v1(");
  before(body("public.expire_website_project_preview_dispatches_v1"),
    "lock_preview_lifecycle_v1()", "for item in select");
});

test("R1: source and preview locks precede dispatch locks, including failure and legacy paths", () => {
  const leases = body("lws_internal.lock_preview_leases_v1");
  before(leases, "lock_preview_lifecycle_v1()", "for update");
  before(leases, "website_project_files_write_leases where lease_id=l.source_write_lease_id for update",
    "website_project_preview_build_leases where preview_lease_id=p_lease_id for update");
  for (const name of ["lws_internal.fail_preview_dispatch_v1",
    "public.record_website_project_preview_dispatch_v1", "public.finish_website_project_preview_failure_v1"]) {
    before(body(name), "lock_preview_leases_v1(p_lease_id)",
      "website_project_preview_dispatches where preview_lease_id=p_lease_id for update");
  }
  const binding = body("lws_internal.assert_preview_dispatch_binding_v1");
  before(binding, "lock_preview_lifecycle_v1()", "for share");
  before(binding, "public.website_work_contexts", "public.website_execution_workspaces where");
  before(binding, "for share", "lock_preview_leases_v1(p_lease_id)");
  before(body("lws_internal.assert_preview_legacy_finalizer_v1"),
    "lock_preview_leases_v1(p_lease_id)", "if exists");
  before(body("public.finalize_website_project_preview_upload_session_v1"),
    "assert_website_project_preview_run_v1(", "finalize_preview_upload_pre_dispatch_v1(");
});

test("R2: managed release is rejected before legacy delegation, without deleting dedup authority", () => {
  const release = body("public.release_website_project_preview_build_v1");
  before(release, "lock_preview_leases_v1(p_lease_id)", "if exists");
  before(release, "PROJECT_PREVIEW_MANAGED_RELEASE_FORBIDDEN", "release_preview_pre_dispatch_v1(p_lease_id)");
  assert.doesNotMatch(release, /delete |set state=/i);
  assert.match(sql, /grant execute on function public\.release_website_project_preview_build_v1\(uuid\) to authenticated/);
});

test("R3: authorization checks expiry after the last blocking locks and immediately before claims", () => {
  assert.match(body("lws_internal.assert_preview_lease_current_v1"),
    /released_at is not null or l\.expires_at <= clock_timestamp\(\)/);
  for (const [name, lock, mutation] of [
    ["public.claim_website_project_preview_dispatch_v1", "for share", "insert into"],
    ["public.claim_website_project_preview_run_v1", "for update", "update lws_internal"],
  ]) {
    const claim = body(name);
    before(claim, lock, "assert_preview_lease_current_v1(p_lease_id)");
    assert.match(claim, new RegExp(`perform lws_internal\\.assert_preview_lease_current_v1\\(p_lease_id\\);\\s+${mutation}`));
  }
  before(body("lws_internal.assert_preview_dispatch_binding_v1"),
    "lock_preview_leases_v1(p_lease_id)", "assert_preview_lease_current_v1(p_lease_id)");
});

test("R3: acquisition cannot return an expired or released authority after a legacy lock wait", () => {
  const acquire = body("public.acquire_website_project_preview_build_v1");
  before(acquire, "acquire_preview_pre_dispatch_v1(", "assert_preview_lease_current_v1(");
  before(acquire, "assert_preview_lease_current_v1(", "return a;");
});

test("expiry transition metadata stays internal to preserve existing public failure results", () => {
  for (const name of ["public.record_website_project_preview_dispatch_v1",
    "public.finish_website_project_preview_failure_v1"]) {
    assert.match(body(name), /return lws_internal\.fail_preview_dispatch_v1\([^;]+\) - 'transitioned';/);
  }
});

test("expiry count depends on a new DEADLINE_EXCEEDED transition, not a terminal replay", () => {
  const failure = body("lws_internal.fail_preview_dispatch_v1");
  assert.match(failure, /if d\.finished_at is not null then return jsonb_build_object\('transitioned',false/);
  assert.match(failure, /return jsonb_build_object\('transitioned',true,'state','FAILED'/);
  const expiry = body("public.expire_website_project_preview_dispatches_v1");
  assert.match(expiry, /outcome:=lws_internal\.fail_preview_dispatch_v1/);
  assert.match(expiry, /if outcome->>'transitioned' = 'true' and outcome->>'reason' = 'DEADLINE_EXCEEDED' then\s+expired_count:=expired_count\+1;\s+end if/);
});

test("rollback keeps original acquisition/release function identities and revokes direct bypass", () => {
  for (const [name, signature, retained] of [
    ["acquire_website_project_preview_build_v1", "uuid,text,uuid", "acquire_preview_pre_dispatch_v1"],
    ["release_website_project_preview_build_v1", "uuid", "release_preview_pre_dispatch_v1"],
  ]) {
    assert.ok(sql.includes(`alter function public.${name}(${signature}) set schema lws_internal;`));
    assert.ok(sql.includes(`rename to ${retained};`));
    assert.ok(sql.includes(`revoke all on function lws_internal.${retained}(${signature}) from public,anon,authenticated,service_role;`));
  }
  assert.doesNotMatch(sql, /drop (?:function|table)|delete from .*schema_migrations/i);
});

test("durable preview claims and terminal guards are supplied as a local migration", async () => {
  const sql = await readFile(migration, "utf8").catch((error) => {
    if (error.code !== "ENOENT") throw error;
    return "";
  });
  assert.match(sql, /create table lws_internal\.website_project_preview_dispatches/);
  assert.match(sql, /unique\s*\(\s*authorized_build_id\s*\)/i);
  for (const name of [
    "claim_website_project_preview_dispatch_v1",
    "record_website_project_preview_dispatch_v1",
    "claim_website_project_preview_run_v1",
    "finish_website_project_preview_failure_v1",
    "expire_website_project_preview_dispatches_v1",
    "get_website_project_preview_dispatch_completion_v1",
    "get_website_project_preview_failed_storage_paths_v1",
  ]) assert.ok(sql.includes(`function public.${name}(`), name);
  assert.match(sql, /assert_operator_aal2_v1/);
  assert.match(sql, /p_run_attempt is distinct from 1/);
  assert.match(sql, /pg_advisory_xact_lock/);
  assert.match(sql, /on conflict \(preview_lease_id\) do nothing/);
  assert.match(sql, /force row level security/i);
  assert.match(sql, /DISPATCH_UNKNOWN/);
  assert.match(sql, /DEADLINE_EXCEEDED/);
  assert.match(sql, /PROJECT_PREVIEW_MANAGED_FINALIZER_REQUIRED/);
  assert.doesNotMatch(sql, /cron\.schedule|create extension/i);
});
