const { createHash, randomUUID } = require("node:crypto");
const { spawn, spawnSync } = require("node:child_process");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const baseArgs = ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-qAt"];
const actorAuthUserId = "c9bcd3ef-1e7e-4889-8a12-db827f1b97b0";
const commitSha = "1f19bf01c61c6da79fa4c7374333a91b70f9bf48";
let repositoryId = 7_400_000_000 + Math.floor(Math.random() * 100_000_000);
let seededLeaseCount = 0;
const workflowRunId = 998877;

function literal(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function query(sql) {
  const result = spawnSync("docker", [...baseArgs, "-c", sql], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout.trim().split(/\r?\n/).filter(Boolean).at(-1) || "";
}

function run(sql) {
  return new Promise((resolve) => {
    const child = spawn("docker", [...baseArgs, "-c", sql]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (data) => stdout += data);
    child.stderr.on("data", (data) => stderr += data);
    child.on("exit", (code) => resolve({ code, stdout, stderr }));
  });
}

function service(sql) {
  return `set role service_role; select set_config('request.jwt.claims','{"role":"service_role"}',false); ${sql}`;
}

function releaseLease(leaseId) {
  const claims = JSON.stringify({ sub: actorAuthUserId, role: "authenticated", aal: "aal2" });
  query(`select set_config('request.jwt.claims',${literal(claims)},false); select public.release_website_project_preview_build_v1(${literal(leaseId)}::uuid);`);
}

function bindingArgs(sessionHash, leaseId, buildId, repository = repositoryId) {
  return `${literal(sessionHash)},${literal(leaseId)}::uuid,${literal(buildId)}::uuid,${repository},${literal(commitSha)},${workflowRunId}`;
}

function seedLease() {
  if (seededLeaseCount > 0) repositoryId += 1;
  seededLeaseCount += 1;
  const suffix = randomUUID().slice(0, 8);
  const repositoryName = `preview-upload-session-${suffix}`;
  const claims = JSON.stringify({ sub: actorAuthUserId, role: "authenticated", aal: "aal2" });
  const sql = `
    begin;
    select set_config('request.jwt.claims',${literal(claims)},true);
    set local session_replication_role=replica;
    update public.commercial_operators set role='owner',status='ACTIVE',revoked_at=null where auth_user_id=${literal(actorAuthUserId)}::uuid;
    set local session_replication_role=origin;
    create temporary table upload_session_fixture as
      select (value->>'website_work_context_id')::uuid website_work_context_id,
             (value->>'workspace_id')::uuid website_workspace_id,
             null::uuid quote_request_id
      from (select public.create_task13_synthetic_context_v1() value) created;
    update upload_session_fixture fixture set quote_request_id=context.quote_request_id
      from public.website_work_contexts context where context.website_work_context_id=fixture.website_work_context_id;
    set local session_replication_role=replica;
    update public.website_execution_workspaces workspace set
      workspace_state='REPOSITORY_READY',repository_owner='lorenzo-web-solutions',repository_name=${literal(repositoryName)},
      repository_external_id=${repositoryId},repository_node_id=${literal(`R_${suffix}`)},repository_visibility='private',
      repository_state='BOUND',starter_source='lws-local-fixtures/website-starter',starter_version='1.0.0',
      starter_commit_sha=${literal(commitSha)},repository_marker_commit_sha=repeat('d',40),repository_bound_at=clock_timestamp(),
      binding_revision=1,default_branch='main',last_commit_sha=${literal(commitSha)}
    from upload_session_fixture fixture where workspace.website_workspace_id=fixture.website_workspace_id;
    set local session_replication_role=origin;
    select set_config('lws.website_repository_command','on',true);
    insert into public.website_repository_provisioning_operations(
      operation_id,website_workspace_id,website_work_context_id,actor_id,idempotency_key,request_fingerprint,
      repository_owner,repository_name,starter_source,starter_version,starter_commit_sha,state,attempt_count,
      repository_external_id,repository_node_id,claimed_at,updated_at,external_created_at,bound_at)
    select gen_random_uuid(),fixture.website_workspace_id,fixture.website_work_context_id,operator.operator_id,
      gen_random_uuid(),repeat('1',64),'lorenzo-web-solutions',${literal(repositoryName)},'lorenzo-web-solutions/website-starter',
      '1.0.0',${literal(commitSha)},'BOUND',1,${repositoryId},${literal(`R_${suffix}`)},clock_timestamp(),
      clock_timestamp(),clock_timestamp(),clock_timestamp()
    from upload_session_fixture fixture join public.commercial_operators operator on operator.auth_user_id=${literal(actorAuthUserId)}::uuid;
    select public.acquire_website_project_preview_build_v1(
      fixture.quote_request_id,${literal(commitSha)},${literal(randomUUID())}::uuid
    )::text from upload_session_fixture fixture;
    commit;`;
  return JSON.parse(query(sql));
}

function issueAndOpen(leaseId, buildId, tokenHash, sessionHash, manifest) {
  query(service(`select public.issue_website_project_preview_artifact_token_v1(
    ${literal(tokenHash)},${literal(leaseId)}::uuid,${literal(buildId)}::uuid,${repositoryId},${literal(commitSha)},${workflowRunId},300
  )::text;`));
  const manifestSql = literal(JSON.stringify(manifest));
  return query(service(`select public.open_website_project_preview_upload_session_v1(
    ${literal(tokenHash)},${literal(sessionHash)},${literal(leaseId)}::uuid,${literal(buildId)}::uuid,
    ${repositoryId},${literal(commitSha)},${workflowRunId},'index.html','PASS',${manifestSql}::jsonb,600
  )::text;`));
}

function localEnvironment() {
  const result = spawnSync(process.execPath, ["node_modules/supabase/dist/supabase.js", "status", "-o", "env"], { encoding: "utf8" });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  const apiUrl = /API_URL="([^"]+)"/.exec(result.stdout)?.[1];
  const serviceRoleKey = /SERVICE_ROLE_KEY="([^"]+)"/.exec(result.stdout)?.[1];
  if (!apiUrl || !serviceRoleKey) throw new Error("LOCAL_SUPABASE_ENV_UNAVAILABLE");
  return { apiUrl, serviceRoleKey };
}

async function storage(environment, method, buildId, path, bytes) {
  return await fetch(`${environment.apiUrl}/storage/v1/object/website-project-previews/${buildId}/${path}`, {
    method,
    headers: {
      apikey: environment.serviceRoleKey,
      authorization: `Bearer ${environment.serviceRoleKey}`,
      ...(bytes ? { "content-type": "text/html", "x-upsert": "false" } : {}),
    },
    body: bytes,
  });
}

async function main() {
  const environment = localEnvironment();
  const bytes = Buffer.from("<h1>Preview</h1>");
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  const entry = { relative_path: "index.html", content_type: "text/html", sha256, bytes: bytes.length };
  const extra = { relative_path: "style.css", content_type: "text/css", sha256: createHash("sha256").update("body{}").digest("hex"), bytes: 6 };
  const createdObjects = [];
  try {
    const incompleteAuthority = seedLease();
    const leaseId = incompleteAuthority.leaseId;
    const incompleteBuild = incompleteAuthority.buildId;
    if (!incompleteBuild) throw new Error("AUTHORIZED_BUILD_ID_MISSING");
    const mismatchedAuthority = await run(service(`select public.resolve_website_project_preview_artifact_authority_v1(
      ${literal(leaseId)}::uuid,${literal(randomUUID())}::uuid,${workflowRunId}
    )::text;`));
    if (mismatchedAuthority.code === 0 || !/PROJECT_PREVIEW_BUILD_AUTHORITY_INVALID/.test(mismatchedAuthority.stderr)) {
      throw new Error("UNAUTHORIZED_BUILD_ID_ACCEPTED");
    }
    const incompleteToken = createHash("sha256").update(randomUUID()).digest("hex");
    const incompleteSession = createHash("sha256").update(randomUUID()).digest("hex");
    issueAndOpen(leaseId, incompleteBuild, incompleteToken, incompleteSession, [entry, extra]);
    const replay = await run(service(`select public.open_website_project_preview_upload_session_v1(
      ${literal(incompleteToken)},${literal(createHash("sha256").update(randomUUID()).digest("hex"))},${literal(leaseId)}::uuid,
      ${literal(incompleteBuild)}::uuid,${repositoryId},${literal(commitSha)},${workflowRunId},'index.html','PASS',${literal(JSON.stringify([entry, extra]))}::jsonb,600
    )::text;`));
    if (replay.code === 0 || !/PROJECT_PREVIEW_ARTIFACT_TOKEN_INVALID/.test(replay.stderr)) throw new Error("RECEIPT_REPLAY_ACCEPTED");

    const claimSql = service(`select public.claim_website_project_preview_upload_file_v1(
      ${bindingArgs(incompleteSession, leaseId, incompleteBuild)},'index.html','text/html',${literal(sha256)},${bytes.length}
    )::text;`);
    const claims = await Promise.all([run(claimSql), run(claimSql)]);
    if (claims.filter((result) => result.code === 0).length !== 1
      || claims.filter((result) => /PROJECT_PREVIEW_UPLOAD_FILE_INVALID/.test(result.stderr)).length !== 1) {
      throw new Error(`EXPECTED_ONE_FILE_CLAIM_WINNER:${JSON.stringify(claims)}`);
    }
    const wrongBinding = await run(service(`select public.complete_website_project_preview_upload_file_v1(
      ${bindingArgs(incompleteSession, leaseId, incompleteBuild, repositoryId + 1)},'index.html'
    )::text;`));
    if (wrongBinding.code === 0 || !/PROJECT_PREVIEW_UPLOAD_SESSION_INVALID/.test(wrongBinding.stderr)) throw new Error("WRONG_BINDING_ACCEPTED");
    let response = await storage(environment, "POST", incompleteBuild, "index.html", bytes);
    if (!response.ok) throw new Error(`STORAGE_UPLOAD_FAILED:${response.status}:${await response.text()}`);
    createdObjects.push([incompleteBuild, "index.html"]);
    query(service(`select public.complete_website_project_preview_upload_file_v1(${bindingArgs(incompleteSession, leaseId, incompleteBuild)},'index.html')::text;`));
    const incomplete = await run(service(`select public.finalize_website_project_preview_upload_session_v1(${bindingArgs(incompleteSession, leaseId, incompleteBuild)})::text;`));
    if (incomplete.code === 0 || !/PROJECT_PREVIEW_UPLOAD_SESSION_INCOMPLETE/.test(incomplete.stderr)) throw new Error("INCOMPLETE_FINALIZE_ACCEPTED");
    const abortResult = JSON.parse(query(service(`select public.abort_website_project_preview_upload_session_v1(${bindingArgs(incompleteSession, leaseId, incompleteBuild)})::text;`)));
    for (const path of abortResult.uploadedPaths) await storage(environment, "DELETE", incompleteBuild, path);
    response = await storage(environment, "GET", incompleteBuild, "index.html");
    if (response.status !== 400 && response.status !== 404) throw new Error(`INCOMPLETE_STORAGE_LEFTOVER:${response.status}`);
    releaseLease(leaseId);

    const lateAuthority = seedLease();
    const lateLeaseId = lateAuthority.leaseId;
    const lateBuild = lateAuthority.buildId;
    if (!lateBuild) throw new Error("AUTHORIZED_BUILD_ID_MISSING");
    const lateToken = createHash("sha256").update(randomUUID()).digest("hex");
    const lateSession = createHash("sha256").update(randomUUID()).digest("hex");
    issueAndOpen(lateLeaseId, lateBuild, lateToken, lateSession, [entry]);
    query(service(`select public.claim_website_project_preview_upload_file_v1(${bindingArgs(lateSession, lateLeaseId, lateBuild)},'index.html','text/html',${literal(sha256)},${bytes.length})::text;`));
    response = await storage(environment, "POST", lateBuild, "index.html", bytes);
    if (!response.ok) throw new Error(`STORAGE_UPLOAD_FAILED:${response.status}:${await response.text()}`);
    createdObjects.push([lateBuild, "index.html"]);
    query(service(`select public.complete_website_project_preview_upload_file_v1(${bindingArgs(lateSession, lateLeaseId, lateBuild)},'index.html')::text;`));
    query(`update lws_internal.website_project_preview_upload_sessions set expires_at=clock_timestamp()-interval '1 second' where session_token_hash=${literal(lateSession)}`);
    const late = await run(service(`select public.finalize_website_project_preview_upload_session_v1(${bindingArgs(lateSession, lateLeaseId, lateBuild)})::text;`));
    if (late.code === 0 || !/PROJECT_PREVIEW_UPLOAD_SESSION_INVALID/.test(late.stderr)) throw new Error("LATE_FINALIZE_ACCEPTED");
    const lateAbort = JSON.parse(query(service(`select public.abort_website_project_preview_upload_session_v1(${bindingArgs(lateSession, lateLeaseId, lateBuild)})::text;`)));
    for (const path of lateAbort.uploadedPaths) await storage(environment, "DELETE", lateBuild, path);
    response = await storage(environment, "GET", lateBuild, "index.html");
    if (response.status !== 400 && response.status !== 404) throw new Error(`LATE_STORAGE_LEFTOVER:${response.status}`);
    releaseLease(lateLeaseId);

    const successAuthority = seedLease();
    const successLeaseId = successAuthority.leaseId;
    const successBuild = successAuthority.buildId;
    if (!successBuild) throw new Error("AUTHORIZED_BUILD_ID_MISSING");
    const successToken = createHash("sha256").update(randomUUID()).digest("hex");
    const successSession = createHash("sha256").update(randomUUID()).digest("hex");
    issueAndOpen(successLeaseId, successBuild, successToken, successSession, [entry]);
    query(service(`select public.claim_website_project_preview_upload_file_v1(${bindingArgs(successSession, successLeaseId, successBuild)},'index.html','text/html',${literal(sha256)},${bytes.length})::text;`));
    response = await storage(environment, "POST", successBuild, "index.html", bytes);
    if (!response.ok) throw new Error(`STORAGE_UPLOAD_FAILED:${response.status}:${await response.text()}`);
    createdObjects.push([successBuild, "index.html"]);
    query(service(`select public.complete_website_project_preview_upload_file_v1(${bindingArgs(successSession, successLeaseId, successBuild)},'index.html')::text;`));
    const finalized = JSON.parse(query(service(`select public.finalize_website_project_preview_upload_session_v1(${bindingArgs(successSession, successLeaseId, successBuild)})::text;`)));
    if (finalized.buildStatus !== "PASS" || !finalized.previewBuildId) throw new Error("SUCCESS_FINALIZE_INVALID");
    console.log("website preview upload session: PASS (race/replay/binding/incomplete/expiry/cleanup/finalize)");
  } finally {
    for (const [buildId, path] of createdObjects) await storage(environment, "DELETE", buildId, path).catch(() => {});
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});