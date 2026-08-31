const { spawn, spawnSync } = require("node:child_process");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const baseArgs = [
  "exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres",
  "-v", "ON_ERROR_STOP=1", "-At",
];
const ownerUserId = "fd000000-0000-4000-8000-000000000001";
const ownerOperatorId = "fd010000-0000-4000-8000-000000000001";
const quotationWinsRequestId = "fd020000-0000-4000-8000-000000000001";
const purgeWinsRequestId = "fd020002-0000-4000-8000-000000000002";
const quotationWinsId = "fd030000-0000-4000-8000-000000000001";
const purgeLosesKey = "fd040000-0000-4000-8000-000000000001";
const purgeWinsKey = "fd040000-0000-4000-8000-000000000002";

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

function startHoldingSession(sql, readyMarker) {
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
    if (!settled) readyReject(new Error(`SESSION_READY_TIMEOUT:${readyMarker}:${stderr || stdout}`));
  }, 5000);
  child.stdout.on("data", (data) => {
    stdout += data;
    if (!settled && stdout.includes(readyMarker)) {
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
      readyReject(new Error(`SESSION_EXITED_BEFORE_READY:${readyMarker}:${code}:${stderr || stdout}`));
    }
    resolve({ code, stdout, stderr });
  }));
  child.stdin.write(`${sql}\n`);
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

async function proveBlocked(applicationName, blockerApplicationName) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const proof = query(`
      select exists (
        select 1
        from pg_stat_activity waiting
        join pg_stat_activity blocker
          on blocker.pid = any(pg_blocking_pids(waiting.pid))
        where waiting.application_name = '${applicationName}'
          and blocker.application_name = '${blockerApplicationName}'
          and waiting.wait_event_type = 'Lock'
      )
    `);
    if (proof === "t") return;
  }
  throw new Error(`LOCK_WAIT_NOT_PROVEN:${applicationName}:${blockerApplicationName}`);
}

function cleanupFixtures() {
  query(`
    begin;
    set local session_replication_role = replica;
    delete from public.sdf_quotations
    where quote_request_id in ('${quotationWinsRequestId}','${purgeWinsRequestId}');
    delete from lws_internal.sdf_initial_confirmation_recovery_events
    where quote_request_id in ('${quotationWinsRequestId}','${purgeWinsRequestId}');
    delete from public.sdf_initial_confirmation_email_jobs
    where quote_request_id in ('${quotationWinsRequestId}','${purgeWinsRequestId}');
    delete from lws_internal.application_intake_automation_work
    where quote_request_id in ('${quotationWinsRequestId}','${purgeWinsRequestId}');
    delete from lws_internal.dossier_purge_tombstones
    where quote_request_id in ('${quotationWinsRequestId}','${purgeWinsRequestId}');
    delete from lws_internal.operator_dossier_assignment_commands
    where quote_request_id in ('${quotationWinsRequestId}','${purgeWinsRequestId}');
    delete from lws_internal.operator_dossier_assignment_events
    where quote_request_id in ('${quotationWinsRequestId}','${purgeWinsRequestId}');
    delete from lws_internal.operator_dossier_assignments
    where quote_request_id in ('${quotationWinsRequestId}','${purgeWinsRequestId}');
    delete from lws_internal.operator_dossier_states
    where quote_request_id in ('${quotationWinsRequestId}','${purgeWinsRequestId}');
    delete from public.quote_requests
    where id in ('${quotationWinsRequestId}','${purgeWinsRequestId}');
    delete from lws_internal.dossier_identity_anchors
    where quote_request_id in ('${quotationWinsRequestId}','${purgeWinsRequestId}');
    delete from public.commercial_operators where operator_id = '${ownerOperatorId}';
    delete from auth.users where id = '${ownerUserId}';
    commit;
    select 'CLEAN';
  `);
}

function createFixtures() {
  query(`
    insert into auth.users(id,email)
    values('${ownerUserId}','sdf-purge-race-owner@example.test');
    insert into public.commercial_operators(
      operator_id,auth_user_id,display_name,role,status
    ) values('${ownerOperatorId}','${ownerUserId}','SDF Purge Race Owner','owner','ACTIVE');
    insert into public.quote_requests(
      id,record_classification,request_kind,sdf_package,name,email,
      description,privacy_consent,status
    ) values
      ('${quotationWinsRequestId}','production','slimme_documentenflow','start',
       'Quotation wins','quotation-wins@example.test','Local race fixture.',true,'approved'),
      ('${purgeWinsRequestId}','production','slimme_documentenflow','groei',
       'Purge wins','purge-wins@example.test','Local race fixture.',true,'approved');
    update lws_internal.operator_dossier_states
    set state='TRASHED',revision=revision+1,state_before_trash='ACTIVE',
        deletion_eligible_at=null,updated_at=clock_timestamp()
    where quote_request_id='${purgeWinsRequestId}';
  `);
}

async function main() {
  let holdingSession = null;
  if (query("select current_database()") !== "postgres") throw new Error("LOCAL_TEST_ENVIRONMENT_REQUIRED");
  try {
    cleanupFixtures();
    createFixtures();

    holdingSession = startHoldingSession(`
      set application_name = 'lws_sdf_quotation_winner';
      begin;
      insert into public.sdf_quotations(quotation_id,quote_request_id)
      values('${quotationWinsId}','${quotationWinsRequestId}');
      select 'QUOTATION_LOCK_HELD';
    `, "QUOTATION_LOCK_HELD");
    await holdingSession.ready;
    query(`
      update lws_internal.operator_dossier_states
      set state='TRASHED',revision=revision+1,state_before_trash='ACTIVE',
          deletion_eligible_at=null,updated_at=clock_timestamp()
      where quote_request_id='${quotationWinsRequestId}'
    `);
    const purgeWaiter = run(`
      set application_name = 'lws_sdf_purge_after_quotation';
      begin;
      set local role authenticated;
      select set_config('request.jwt.claim.sub','${ownerUserId}',true);
      select public.purge_sdf_dossier_v1(
        '${quotationWinsRequestId}','Quotation wins race','${purgeLosesKey}'
      );
      commit;
    `);
    await proveBlocked("lws_sdf_purge_after_quotation", "lws_sdf_quotation_winner");
    const quotationWinner = await holdingSession.release();
    holdingSession = null;
    const purgeAfterQuotation = await purgeWaiter;
    if (quotationWinner.code !== 0) throw new Error(`QUOTATION_WINNER_FAILED:${JSON.stringify(quotationWinner)}`);
    if (purgeAfterQuotation.code !== 0) {
      throw new Error(`PURGE_AFTER_QUOTATION_FAILED:${JSON.stringify(purgeAfterQuotation)}`);
    }
    if (query(`select count(*)=0 from public.quote_requests where id='${quotationWinsRequestId}'`) !== "t"
        || query(`select count(*)=0 from public.sdf_quotations where quotation_id='${quotationWinsId}'`) !== "t"
        || query(`select count(*)=1 from lws_internal.dossier_purge_tombstones where quote_request_id='${quotationWinsRequestId}'`) !== "t") {
      throw new Error("PURGE_AFTER_QUOTATION_LEFT_SPLIT_STATE");
    }

    holdingSession = startHoldingSession(`
      set application_name = 'lws_sdf_purge_winner';
      begin;
      set local role authenticated;
      select set_config('request.jwt.claim.sub','${ownerUserId}',true);
      select public.purge_sdf_dossier_v1(
        '${purgeWinsRequestId}','Purge wins race','${purgeWinsKey}'
      );
      select 'PURGE_LOCK_HELD';
    `, "PURGE_LOCK_HELD");
    await holdingSession.ready;
    const quotationWaiter = run(`
      set application_name = 'lws_sdf_quotation_after_purge';
      begin;
      insert into public.sdf_quotations(quotation_id,quote_request_id)
      values('fd030000-0000-4000-8000-000000000002','${purgeWinsRequestId}');
      commit;
    `);
    await proveBlocked("lws_sdf_quotation_after_purge", "lws_sdf_purge_winner");
    const purgeWinner = await holdingSession.release();
    holdingSession = null;
    const quotationLoser = await quotationWaiter;
    if (purgeWinner.code !== 0) throw new Error(`PURGE_WINNER_FAILED:${JSON.stringify(purgeWinner)}`);
    if (quotationLoser.code === 0 || !quotationLoser.stderr.includes("SDF_QUOTATION_APPLICATION_NOT_FOUND")) {
      throw new Error(`QUOTATION_DID_NOT_FAIL_CLOSED:${JSON.stringify(quotationLoser)}`);
    }
    if (query(`select count(*)=0 from public.quote_requests where id='${purgeWinsRequestId}'`) !== "t"
        || query(`select count(*)=1 from lws_internal.dossier_purge_tombstones where quote_request_id='${purgeWinsRequestId}'`) !== "t"
        || query(`select count(*)=0 from public.sdf_quotations where quote_request_id='${purgeWinsRequestId}'`) !== "t") {
      throw new Error("PURGE_WINNER_LEFT_SPLIT_STATE");
    }

    process.stdout.write(JSON.stringify({
      test_context: "LOCAL_TEST_ONLY",
      quotation_winner_lock_wait_proven: true,
      quotation_winner_result: "PURGED_WITH_FOUNDATION_CLEANUP",
      purge_winner_lock_wait_proven: true,
      purge_winner_result: "SDF_QUOTATION_APPLICATION_NOT_FOUND",
      split_state_observed: false,
    }) + "\n");
  } finally {
    if (holdingSession) await holdingSession.abort();
    cleanupFixtures();
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});