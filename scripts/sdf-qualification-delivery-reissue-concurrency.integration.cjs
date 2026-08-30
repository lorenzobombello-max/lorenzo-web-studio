const { spawn, spawnSync } = require("node:child_process");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const baseArgs = ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At"];
const ownerUserId = "da100000-0000-4000-8000-000000000001";
const ownerOperatorId = "da110000-0000-4000-8000-000000000001";
const quoteRequestId = "da200000-0000-4000-8000-000000000001";
const intakeId = "da300000-0000-4000-8000-000000000001";
const jobId = "da400000-0000-4000-8000-000000000001";

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

function startHoldingClaim() {
  const child = spawn("docker", baseArgs);
  let stdout = "";
  let stderr = "";
  let settled = false;
  let readyResolve;
  let readyReject;
  const ready = new Promise((resolve, reject) => {
    readyResolve = resolve;
    readyReject = reject;
  });
  const timeout = setTimeout(() => {
    if (!settled) readyReject(new Error(`CLAIM_TIMEOUT:${stderr || stdout}`));
  }, 5000);
  child.stdout.on("data", (data) => {
    stdout += data;
    if (!settled && stdout.includes("CLAIM_HELD")) {
      settled = true;
      clearTimeout(timeout);
      readyResolve();
    }
  });
  child.stderr.on("data", (data) => stderr += data);
  const exited = new Promise((resolve) => child.on("exit", (code) => {
    if (!settled) {
      settled = true;
      clearTimeout(timeout);
      readyReject(new Error(`CLAIM_EXITED:${code}:${stderr || stdout}`));
    }
    resolve({ code, stdout, stderr });
  }));
  child.stdin.write(`
    set application_name = 'sdf_delivery_claim';
    begin;
    set local role service_role;
    select job_id from public.claim_sdf_qualification_email_job_v1('${jobId}');
    select 'CLAIM_HELD';
  `);
  return {
    ready,
    release: async () => {
      child.stdin.end("commit;\n");
      return await exited;
    },
    abort: async () => {
      if (child.exitCode === null) child.stdin.end("rollback;\n");
      return await exited;
    },
  };
}

async function proveBlocked() {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (query(`
      select exists (
        select 1 from pg_stat_activity waiting
        join pg_stat_activity blocker on blocker.pid=any(pg_blocking_pids(waiting.pid))
        where waiting.application_name='sdf_delivery_reissue'
          and blocker.application_name='sdf_delivery_claim'
          and waiting.wait_event_type='Lock'
      )
    `) === "t") return;
  }
  throw new Error("SDF_DELIVERY_REISSUE_LOCK_WAIT_NOT_PROVEN");
}

function cleanup() {
  query(`
    begin;
    set local session_replication_role=replica;
    delete from public.sdf_qualification_intake_email_jobs where intake_id='${intakeId}';
    delete from public.sdf_qualification_intake_events where intake_id='${intakeId}';
    delete from public.sdf_qualification_intakes where intake_id='${intakeId}';
    delete from lws_internal.application_intake_automation_work where quote_request_id='${quoteRequestId}';
    delete from lws_internal.operator_dossier_assignments where quote_request_id='${quoteRequestId}';
    delete from lws_internal.operator_dossier_states where quote_request_id='${quoteRequestId}';
    delete from lws_internal.dossier_identity_anchors where quote_request_id='${quoteRequestId}';
    delete from public.quote_requests where id='${quoteRequestId}';
    delete from public.commercial_operators where operator_id='${ownerOperatorId}';
    delete from auth.users where id='${ownerUserId}';
    commit;
  `);
}

async function main() {
  let claim = null;
  if (query("select current_database()") !== "postgres") throw new Error("LOCAL_TEST_ENVIRONMENT_REQUIRED");
  try {
    cleanup();
    query(`
      insert into auth.users(id,email) values('${ownerUserId}','sdf-delivery-owner@example.test');
      insert into public.commercial_operators(operator_id,auth_user_id,display_name,role,status)
      values('${ownerOperatorId}','${ownerUserId}','SDF Delivery Owner','owner','ACTIVE');
      insert into public.quote_requests(id,request_kind,sdf_package,created_at,name,email,description,privacy_consent,status,record_classification,approval_token_hash,approval_token_expires_at,confirmation_sent_at)
      values('${quoteRequestId}','slimme_documentenflow','groei',clock_timestamp()-interval '5 minutes','Concurrency SDF','sdf-concurrency@example.test','Concurrency fixture',true,'pending','production',repeat('7',64),clock_timestamp()+interval '1 day',clock_timestamp()-interval '3 minutes');
      insert into public.sdf_qualification_intakes(intake_id,quote_request_id,customer_capability_digest,customer_capability_encrypted,customer_capability_expires_at)
      values('${intakeId}','${quoteRequestId}',repeat('a',64),'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',clock_timestamp()+interval '14 days');
      insert into public.sdf_qualification_intake_email_jobs(job_id,intake_id,kind,template_version,invitation_generation,status,next_attempt_at,idempotency_key,request_fingerprint,encrypted_capability)
      values('${jobId}','${intakeId}','invitation','SDF_QUALIFICATION_INTAKE_INVITATION_NL_BE_v1',1,'pending',clock_timestamp()-interval '1 second','da500000-0000-4000-8000-000000000001',repeat('b',64),'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
    `);

    claim = startHoldingClaim();
    await claim.ready;
    const reissuePromise = run(`
      set application_name = 'sdf_delivery_reissue';
      begin;
      set local role service_role;
      select set_config('request.jwt.claim.sub','${ownerUserId}',true);
      select public.reissue_sdf_qualification_intake_v1('${quoteRequestId}',repeat('c',64),'v1.CCCCCCCCCCCCCCCC.CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC','da500000-0000-4000-8000-000000000002');
      commit;
    `);
    await proveBlocked();
    const claimResult = await claim.release();
    claim = null;
    const reissueResult = await reissuePromise;
    if (claimResult.code !== 0) throw new Error(`CLAIM_FAILED:${JSON.stringify(claimResult)}`);
    if (reissueResult.code === 0 || !reissueResult.stderr.includes("SDF_INVITATION_DELIVERY_IN_PROGRESS")) {
      throw new Error(`REISSUE_NOT_BLOCKED:${JSON.stringify(reissueResult)}`);
    }
    const summary = JSON.parse(query(`
      select json_build_object(
        'generation',(select invitation_generation from public.sdf_qualification_intakes where intake_id='${intakeId}'),
        'job_status',(select status from public.sdf_qualification_intake_email_jobs where job_id='${jobId}'),
        'lease_bound',(select delivery_lease_token is not null and delivery_lease_expires_at>clock_timestamp() from public.sdf_qualification_intake_email_jobs where job_id='${jobId}')
      )
    `));
    if (summary.generation !== 1 || summary.job_status !== "processing" || summary.lease_bound !== true) {
      throw new Error(`SDF_DELIVERY_AUTHORITY_INVALID:${JSON.stringify(summary)}`);
    }
    process.stdout.write(JSON.stringify({ test_context: "LOCAL_TEST_ONLY", lock_wait_proven: true, reissue_failed_closed: true, ...summary }) + "\n");
  } finally {
    if (claim) await claim.abort();
    cleanup();
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});