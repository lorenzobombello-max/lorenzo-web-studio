const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const harnessPath = path.join(
  __dirname,
  "website-project-preview-current-commit-concurrency.integration.cjs",
);
const reopenTestPath = path.join(
  __dirname,
  "../supabase/tests/website_project_preview_reopen_current_commit_v1.sql",
);
const createSessionTestPath = path.join(
  __dirname,
  "../supabase/tests/website_project_preview_create_session_current_commit_v1.sql",
);

assert.equal(fs.existsSync(harnessPath), true, "preview concurrency harness is missing");

const harness = fs.readFileSync(harnessPath, "utf8");
const reopenTest = fs.readFileSync(reopenTestPath, "utf8");
const createSessionTest = fs.readFileSync(createSessionTestPath, "utf8");

for (const testSource of [reopenTest, createSessionTest]) {
  assert.match(testSource, /pg_get_userbyid\(p\.proowner\)\s*=\s*'postgres'/);
  assert.match(testSource, /p\.prosecdef/);
  assert.match(
    testSource,
    /p\.proconfig\s*=\s*array\['search_path=public, lws_internal, auth, pg_catalog'\]/,
  );
  assert.match(
    testSource,
    /aclexplode\(\s*coalesce\(p\.proacl,\s*acldefault\('f',\s*p\.proowner\)\)\s*\)/,
  );
  assert.match(testSource, /coalesce\(role\.rolname,\s*'PUBLIC'\)/);
  assert.match(testSource, /authenticated/);
  assert.match(testSource, /postgres/);
  assert.match(testSource, /service_role/);
  assert.match(testSource, /anon/);
}

for (const caseName of [
  "reopen_issuance_first",
  "reopen_update_first",
  "create_session_issuance_first",
  "create_session_update_first",
  "artifact_sweep_first",
  "artifact_issuance_first",
]) {
  assert.match(harness, new RegExp(caseName));
}

for (const requiredContract of [
  "LOCAL_TEST_ONLY",
  "PDF_PREVIEW_CONCURRENCY_CONTAINER",
  "PDF_PREVIEW_CONCURRENCY_DATABASE",
  "open_existing_website_project_preview_v1",
  "create_website_project_preview_session_v1",
  "resolve_website_project_preview_session_v1",
  "sweep_expired_website_project_preview_artifacts_v1",
  "pg_backend_pid()",
  "wait_event_type",
  "pg_blocking_pids",
  "PROJECT_PREVIEW_BUILD_NOT_FOUND",
  "PROJECT_PREVIEW_BUILD_NOT_READY",
  "cleanupFixtures",
  "assertZeroResidue",
  "ARTIFACT_ISSUANCE_FIRST_DANGLING_SESSION",
]) {
  assert.match(harness, new RegExp(requiredContract.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
}

assert.match(harness, /new Set\(\[holderPid,\s*waiterPid\]\)\.size/);
assert.match(harness, /blocking_pids/);
assert.match(harness, /finally\s*\{/);
assert.match(harness, /"ON_ERROR_STOP=1"[\s\S]{0,80}"-q",\s*"-At"/);
assert.match(harness, /"VERBOSITY=verbose"/);
assert.match(harness, /extractSqlState\(waiterResult\.stderr\)/);
assert.match(harness, /\/\^lws_p0_preview_\[a-z0-9_\]\+\$\//);
for (const residueKey of [
  "artifacts",
  "build_leases",
  "write_leases",
  "provisioning_operations",
  "work_contexts",
  "concepts",
]) {
  assert.match(
    harness,
    new RegExp(`function assertZeroResidue\\(\\)[\\s\\S]*['"]${residueKey}['"]`),
  );
}
assert.doesNotMatch(harness, /\.supabase\.co|pooler\.supabase\.com|service_role_key/i);
assert.doesNotMatch(harness, /supabase_db_xcsptvntvrizwhskaphr/);

console.log("website project preview current-commit concurrency contracts: PASS");
