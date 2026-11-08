// Isolated PostgreSQL integration runner. Never accepts a remote connection.
const { spawn, spawnSync } = require("node:child_process");
const { readFileSync, readdirSync } = require("node:fs");
const path = require("node:path");
const container = "lws-local-preview-repair-20261108";
function run(args) {
  const result = spawnSync("docker", args, { encoding: "utf8", maxBuffer: 8 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout;
}
if (["all", "all-projection"].includes(process.argv[2])) {
  run(["run", "-d", "--name", container, "--network", "none", "-e", "POSTGRES_PASSWORD=local-disposable-only",
    "public.ecr.aws/supabase/postgres:17.6.1.171"]);
  try {
    let ready = false;
    for (let attempt = 0; attempt < 60; attempt++) {
      if (spawnSync("docker", ["exec", container, "pg_isready", "-h", "127.0.0.1", "-U", "postgres"], { stdio: "ignore" }).status === 0) { ready = true; break; }
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,1000);
    }
    if (!ready) throw new Error("ISOLATED_DATABASE_NOT_READY");
    run(["run", "--rm", "--network", `container:${container}`,
      "-e", "GOTRUE_DB_DRIVER=postgres", "-e", "GOTRUE_DB_DATABASE_URL=postgres://supabase_auth_admin:local-disposable-only@127.0.0.1:5432/postgres",
      "-e", "GOTRUE_JWT_SECRET=local-disposable-preview-only-32-characters", "-e", "GOTRUE_SITE_URL=http://localhost",
      "-e", "API_EXTERNAL_URL=http://localhost", "public.ecr.aws/supabase/gotrue:v2.197.0", "gotrue", "migrate"]);
    run(["run", "--rm", "--network", `container:${container}`,
      "-e", "DATABASE_URL=postgres://supabase_storage_admin:local-disposable-only@127.0.0.1:5432/postgres",
      "-e", "AUTH_JWT_SECRET=local-disposable-preview-only-32-characters", "-e", "ANON_KEY=local",
      "-e", "SERVICE_KEY=local", "-e", "TENANT_ID=local", "-e", "REGION=local", "-e", "GLOBAL_S3_BUCKET=local",
      "public.ecr.aws/supabase/storage-api:v1.77.5", "node", "dist/scripts/migrate-call.js"]);
    for (const phase of ["migrate", process.argv[2] === "all-projection" ? "projection-test" : "test"]) {
      const result = spawnSync(process.execPath,[__filename,phase],{stdio:"inherit"});
      if (result.status !== 0) throw new Error(`LOCAL_${phase.toUpperCase()}_FAILED`);
    }
  } finally {
    run(["rm","-f","-v",container]);
    console.log("Isolated container and its volumes removed.");
  }
}
function sql(input, args = []) {
  if (run(["inspect","--format","{{.HostConfig.NetworkMode}}",container]).trim() !== "none") throw new Error("ISOLATED_DATABASE_REQUIRED");
  const result = spawnSync("docker", ["exec", "-i", container, "psql", "-X", "-U", "postgres", "-v", "ON_ERROR_STOP=1", "-q", ...args], { input, encoding: "utf8", maxBuffer: 8 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`${result.stdout.slice(-300)}\n${result.stderr}`);
  return result.stdout;
}
const root = path.join(__dirname, "..");
if (process.argv[2] === "migrate") {
  sql(readFileSync(path.join(root, "supabase/local-bootstrap/operator-auth-identities.sql"), "utf8"));
  const files = readdirSync(path.join(root, "supabase/migrations")).filter(f => f.endsWith(".sql") && (!process.argv[3] || f >= process.argv[3])).sort();
  sql(files.map(file => `\\echo ${file}\n${readFileSync(path.join(root,"supabase/migrations",file),"utf8")}`).join("\n"));
  console.log("All migrations applied to isolated PostgreSQL.");
}
module.exports = { sql };
if (process.argv[2] === "projection-test") {
  const source = readFileSync(path.join(root, "supabase/tests/website_project_preview_reopen_current_commit_v1.sql"), "utf8");
  const end = "set local session_replication_role = origin;";
  const fixture = source.slice(0, source.indexOf(end) + end.length)
    .replaceAll("c9bcd3ef-1e7e-4889-8a12-db827f1b97b0", "bb731000-0000-4000-8000-000000000001")
    .replaceAll("preview/current-pass.tar", "index.html");
  const output = sql(fixture + "\n" + readFileSync(path.join(root,
    "supabase/tests/website_execution_existing_preview_projection_v1.sql"), "utf8"));
  console.log(output);
  if (/\bnot ok\b/.test(output)) throw new Error("Existing preview projection assertions failed");
}
if (process.argv[2] === "test") (async () => {
  const scheduler = sql(readFileSync(path.join(root, "supabase/tests/website_project_preview_deadline_scheduler_v1.sql"), "utf8"));
  console.log(scheduler);
  if (/\bnot ok\b/.test(scheduler)) throw new Error("PostgreSQL deadline scheduler assertions failed");
  const source = readFileSync(path.join(root, "supabase/tests/website_project_preview_reopen_current_commit_v1.sql"), "utf8");
  let fixture = source.slice(source.indexOf("insert into auth.users"), source.indexOf("insert into lws_internal.website_project_preview_builds"));
  const actor = "c9bcd3ef-1e7e-4889-8a12-db827f1b97b0";
  const operator = sql(`select operator_id from public.commercial_operators where auth_user_id='${actor}'`, ["-At"]).trim();
  fixture = fixture.slice(fixture.indexOf("insert into public.quote_requests"));
  for (let n = 1; n <= 5; n++) {
    let f = fixture.replaceAll("eec31000", `eec3100${n}`).replaceAll("LWS-AAN-2099-9902", `LWS-AAN-2099-991${n}`)
      .replaceAll("'preview-reopen-current-commit',", `'preview-repair-${n}',`)
      .replaceAll("990003101", `99000310${n}`).replaceAll("R_preview_reopen_current_commit", `R_preview_repair_${n}`);
    f = f.replaceAll(`'eec3100${n}-0000-4000-8000-000000000001'`, `'${operator}'`);
    sql(`begin; set local session_replication_role=replica; ${f}
      update lws_internal.website_project_files_write_leases set write_path='index.html',
        finalized_at=null,finalized_commit_sha=null,finalized_created=null,released_at=null
        where lease_id='eec3100${n}-0000-4000-8000-000000000007';
      update lws_internal.website_project_preview_build_leases set expires_at=clock_timestamp()+interval '10 minutes'
        where preview_lease_id='eec3100${n}-0000-4000-8000-000000000008';
      commit;`);
  }
  console.log(sql(readFileSync(path.join(root, "supabase/tests/website_project_preview_dispatch_v1.sql"), "utf8"), [
    "-v", "lease_id=eec31001-0000-4000-8000-000000000008",
    "-v", "build_id=eec31001-0000-4000-8000-000000000009",
    "-v", `actor_id=${actor}`, "-v", `workflow_sha=${"f".repeat(40)}`,
    "-v", "unmanaged_lease_id=eec31002-0000-4000-8000-000000000008",
    "-v", "expiry_lease_id=eec31003-0000-4000-8000-000000000008",
  ]));
  const scope = sql(readFileSync(path.join(root, "supabase/tests/website_project_preview_deadline_scope_v1.sql"), "utf8"));
  console.log(scope);
  if (/\bnot ok\b/.test(scope)) throw new Error("PostgreSQL deadline scope assertions failed");
  let headFixture = fixture.slice(0, fixture.indexOf("insert into lws_internal.website_project_files_write_leases"));
  const substitutions = {
    "eec31000-0000-4000-8000-000000000001": operator,
    "eec31000-0000-4000-8000-000000000002": "7458c346-dfc9-40f3-ad0e-cb94a16636bf",
    "eec31000-0000-4000-8000-000000000004": "a88b1e87-9271-4ad1-99cc-b385b7982a8b",
    "eec31000-0000-4000-8000-000000000005": "fa057e1f-d03d-47cf-a595-317447734298",
    "eec31000-0000-4000-8000-000000000006": "33202312-6e10-4d3a-bba9-c05868105331",
    "lws-repro-fixtures": "lorenzo-web-solutions",
    "'preview-reopen-current-commit'": "'lws-web-a88b1e8792714ad199ccb385b7982a8b'",
    "990003101": "1378797607", "R_preview_reopen_current_commit": "R_kgDOUi7IJw",
  };
  for (const [from,to] of Object.entries(substitutions)) headFixture = headFixture.replaceAll(from,to);
  sql(`begin;set local session_replication_role=replica;${headFixture} commit;`);
  const output = sql(readFileSync(path.join(root, "supabase/tests/website_project_head_reconciliation_v1.sql"), "utf8"));
  console.log(output);
  if (/\bnot ok\b/.test(output)) throw new Error("PostgreSQL reconciliation assertions failed");
  function concurrentSql(input) {
    return new Promise(resolve => {
      const child = spawn("docker",["exec","-i",container,"psql","-X","-U","postgres","-Atq","-v","ON_ERROR_STOP=1"]);
      let stdout="",stderr="";
      child.stdout.on("data",chunk => stdout+=chunk);
      child.stderr.on("data",chunk => stderr+=chunk);
      child.on("close",status => resolve({status,stdout,stderr}));
      child.stdin.end(input);
    });
  }
  sql(`insert into lws_internal.website_project_preview_workflow_revisions(workflow_sha,enabled) values(repeat('f',40),true);`);
  const claims = await Promise.all([1,2].map(() => concurrentSql(`
    select set_config('request.jwt.claims','{"sub":"${actor}","role":"authenticated","aal":"aal2"}',false);
    select public.claim_website_project_preview_dispatch_v1('eec31001-0000-4000-8000-000000000008',repeat('f',40))->>'dispatchAllowed';`)));
  if (claims.some(r => r.status !== 0) || claims.filter(r => r.stdout.trim().endsWith("true")).length !== 1)
    throw new Error(`Concurrent dispatch claims failed: ${JSON.stringify(claims)}`);
  const runs = await Promise.all([101,102].map(run => concurrentSql(`
    select set_config('request.jwt.claims','{"role":"service_role"}',false);
    select public.claim_website_project_preview_run_v1('eec31001-0000-4000-8000-000000000008',
      'eec31001-0000-4000-8000-000000000009',${run},1,repeat('f',40));`)));
  if (runs.filter(r => r.status === 0).length !== 1 ||
    runs.filter(r => r.stderr.includes("PROJECT_PREVIEW_RUN_ALREADY_CLAIMED")).length !== 1)
    throw new Error(`Concurrent run claims failed: ${JSON.stringify(runs)}`);
  console.log("PASS: two competing dispatch claims and two competing run claims each have exactly one winner.");
  for (const n of [1, 2, 3]) {
    const leaseId = `eec3100${n}-0000-4000-8000-000000000008`;
    const buildId = `eec3100${n}-0000-4000-8000-000000000009`;
    if (n !== 1) sql(`select set_config('request.jwt.claims','{"sub":"${actor}","role":"authenticated","aal":"aal2"}',false);
      select public.claim_website_project_preview_dispatch_v1('${leaseId}',repeat('f',40));
      select set_config('request.jwt.claims','{"role":"service_role"}',false);
      select public.claim_website_project_preview_run_v1('${leaseId}','${buildId}',${200+n},1,repeat('f',40));`);
    const runId = sql(`select workflow_run_id from lws_internal.website_project_preview_dispatches where preview_lease_id='${leaseId}'`, ["-At"]).trim();
    const hash = String(n).repeat(64);
    sql(`insert into lws_internal.website_project_preview_upload_sessions
      (session_token_hash,preview_lease_id,build_id,repository_external_id,commit_sha,workflow_run_id,primary_relative_path,build_status,expires_at)
      values('${hash}','${leaseId}','${buildId}',99000310${n},repeat('a',40),${runId},'index.html','PASS',clock_timestamp()+interval '10 minutes');
      insert into lws_internal.website_project_preview_upload_files
      (session_token_hash,relative_path,content_type,sha256,bytes,state)
      values('${hash}','index.html','text/html',repeat('c',64),12,'RECEIVED');`);
    const success = `select public.finalize_website_project_preview_upload_session_v1('${hash}','${leaseId}','${buildId}',99000310${n},repeat('a',40),${runId});`;
    const failure = `select public.finish_website_project_preview_failure_v1('${leaseId}','${buildId}',${runId},'BUILD_FAILED',repeat('f',40));`;
    const expiry = `update lws_internal.website_project_preview_dispatches set expires_at=clock_timestamp()-interval '1 minute' where preview_lease_id='${leaseId}';
      select public.expire_website_project_preview_dispatches_v1();`;
    const first = n === 1 ? success : n === 2 ? failure : expiry;
    const second = n === 1 ? failure : success;
    await new Promise((resolve, reject) => {
      const winner = spawn("docker",["exec","-i",container,"psql","-X","-U","postgres","-Atq","-v","ON_ERROR_STOP=1"]);
      let contender, output = "", errors = "";
      winner.stdout.on("data", chunk => {
        output += chunk;
        if (!contender && output.includes("RACE_LOCK_READY")) contender = concurrentSql(
          `select set_config('request.jwt.claims','{"role":"service_role"}',false);${second}`);
      });
      winner.stderr.on("data", chunk => errors += chunk);
      winner.on("close", async code => {
        if (code !== 0 || !contender) return reject(new Error(`Terminal race setup failed: ${errors}`));
        const result = await contender;
        if (n === 1 ? result.status !== 0 : result.status === 0 || !/PROJECT_PREVIEW_/.test(result.stderr))
          return reject(new Error(`Terminal race failed: ${JSON.stringify(result)}`));
        resolve();
      });
      winner.stdin.end(`begin;select set_config('request.jwt.claims','{"role":"service_role"}',false);
        select lws_internal.lock_preview_lifecycle_v1();select 'RACE_LOCK_READY';select pg_sleep(0.5);${first}commit;`);
    });
    const state = sql(`select jsonb_build_object('state',d.state,'buildCount',(select count(*) from lws_internal.website_project_preview_builds where lease_id=d.preview_lease_id),
      'released',l.released_at is not null,'sourceReleased',s.released_at is not null,'upload',u.status)
      from lws_internal.website_project_preview_dispatches d join lws_internal.website_project_preview_build_leases l using(preview_lease_id)
      join lws_internal.website_project_files_write_leases s on s.lease_id=l.source_write_lease_id
      join lws_internal.website_project_preview_upload_sessions u using(preview_lease_id)
      where d.preview_lease_id='${leaseId}'`, ["-At"]).trim();
    const evidence = JSON.parse(state);
    if (evidence.state !== (n === 1 ? "PASS" : "FAILED") || evidence.buildCount !== 1 || !evidence.released ||
      !evidence.sourceReleased || evidence.upload !== (n === 1 ? "FINALIZED" : "ABORTED"))
      throw new Error(`Terminal race evidence invalid: ${state}`);
  }
  console.log("PASS: actual competing success/failure/expiry transactions preserve exactly one terminal build, release both leases and finalize/abort uploads.");
  for (const n of [4, 5]) {
    const leaseId = `eec3100${n}-0000-4000-8000-000000000008`;
    const buildId = `eec3100${n}-0000-4000-8000-000000000009`;
    sql(`select set_config('request.jwt.claims','{"sub":"${actor}","role":"authenticated","aal":"aal2"}',false);
      select public.claim_website_project_preview_dispatch_v1('${leaseId}',repeat('f',40));`);
    await new Promise((resolve, reject) => {
      const mutation = n === 4
        ? `update public.commercial_operators set status='REVOKED',revoked_at=clock_timestamp() where auth_user_id='${actor}';`
        : `set local session_replication_role=replica;
          update public.website_execution_workspaces set repository_external_id=990003199 where website_workspace_id='eec31005-0000-4000-8000-000000000005';`;
      const blocker = spawn("docker",["exec","-i",container,"psql","-X","-U","postgres","-Atq","-v","ON_ERROR_STOP=1"]);
      let contender, output = "", errors = "";
      blocker.stdout.on("data", chunk => {
        output += chunk;
        if (!contender && output.includes("AUTHORITY_LOCK_READY")) contender = concurrentSql(
          `select set_config('request.jwt.claims','{"role":"service_role"}',false);
          select public.claim_website_project_preview_run_v1('${leaseId}','${buildId}',${300+n},1,repeat('f',40));`);
      });
      blocker.stderr.on("data", chunk => errors += chunk);
      blocker.on("close", async code => {
        if (code !== 0 || !contender) return reject(new Error(`Authority contention setup failed: ${errors}`));
        const result = await contender;
        const reason = n === 4 ? "WEBSITE_REPOSITORY_OWNER_REQUIRED" : "REPOSITORY_BINDING_STALE";
        if (result.status === 0 || !result.stderr.includes(reason))
          return reject(new Error(`Authority contention failed: ${JSON.stringify(result)}`));
        resolve();
      });
      blocker.stdin.end(`begin;${mutation}select 'AUTHORITY_LOCK_READY';select pg_sleep(0.5);commit;`);
    });
    if (sql(`select workflow_run_id is null from lws_internal.website_project_preview_dispatches where preview_lease_id='${leaseId}'`, ["-At"]).trim() !== "t")
      throw new Error("Revoked/rebound authority claimed a run");
    if (n === 4) sql(`update public.commercial_operators set status='ACTIVE',revoked_at=null where auth_user_id='${actor}';`);
  }
  console.log("PASS: real competing owner revocation and repository rebinding reject waiting run claims without recording a run.");
  const lease = sql(`select set_config('request.jwt.claims','{"sub":"${actor}","role":"authenticated","aal":"aal2"}',false);
    select public.acquire_website_project_files_read_v1('7458c346-dfc9-40f3-ad0e-cb94a16636bf','DIRECTORY')->>'leaseId';`, ["-At"]).trim().split(/\r?\n/).at(-1);
  const blocker = spawn("docker", ["exec","-i",container,"psql","-X","-U","postgres","-At","-v","ON_ERROR_STOP=1"]);
  let tested = false;
  blocker.stdout.on("data", chunk => {
    if (tested || !chunk.toString().includes("LOCK_READY")) return;
    tested = true;
    try {
      sql(`select set_config('request.jwt.claims','{"role":"service_role"}',false);
        select public.reconcile_website_project_repository_head_v1('${lease}',repeat('a',40),repeat('b',40));`);
      process.exitCode = 1;
      console.error("Expiry after lock wait unexpectedly succeeded");
    } catch (error) {
      if (!error.message.includes("PROJECT_FILES_LEASE_EXPIRED")) { process.exitCode = 1; console.error(error); }
      else console.log("PASS: real competing operator lock outlives read authority; finalizer rejects after wait.");
    }
  });
  blocker.stderr.on("data", chunk => process.stderr.write(chunk));
  blocker.on("close", code => { if (code !== 0 || !tested) process.exitCode = 1; });
  blocker.stdin.end(`begin;select 1 from public.commercial_operators where auth_user_id='${actor}' for update;
    select 'LOCK_READY';select pg_sleep(16);commit;`);
})().catch(error => { console.error(error); process.exitCode=1; });
