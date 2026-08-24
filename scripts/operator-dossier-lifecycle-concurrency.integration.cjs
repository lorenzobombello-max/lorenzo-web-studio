const { spawn, spawnSync } = require("node:child_process");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const baseArgs = ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At"];
const ownerUserId = "f5000000-0000-4000-8000-000000000001";
const adminUserId = "f5000000-0000-4000-8000-000000000002";
const ownerOperatorId = "f5010000-0000-4000-8000-000000000001";
const adminOperatorId = "f5010000-0000-4000-8000-000000000002";
const commandQuoteRequestId = "f5100000-0000-4000-8000-000000000001";
const blockerQuoteRequestId = "d3752349-3489-4c19-bd03-f0cc076b5607";
const blockerProjectId = "f5300000-0000-4000-8000-000000000001";

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
    }
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
      )`);
    if (proof === "t") return true;
  }
  throw new Error(`LOCK_WAIT_NOT_PROVEN:${applicationName}:${blockerApplicationName}`);
}

function issueCapability(actorAuthUserId, quoteRequestId, eventType, expectedRevision, idempotencyKey, reason) {
  return query(`set role service_role;
    select public.issue_operator_dossier_lifecycle_edge_capability_v1(
      '${actorAuthUserId}','${quoteRequestId}','${eventType}',${expectedRevision},'${idempotencyKey}','${reason}'
    )`);
}

function cleanupFixtures() {
  query(`
    begin;
    set local session_replication_role = replica;
    delete from public.sdf_projects where project_id = '${blockerProjectId}';
    delete from lws_internal.operator_dossier_edge_capabilities
      where actor_auth_user_id in ('${ownerUserId}','${adminUserId}');
    delete from lws_internal.operator_dossier_state_events
      where quote_request_id in ('${commandQuoteRequestId}','${blockerQuoteRequestId}');
    delete from lws_internal.operator_dossier_states
      where quote_request_id in ('${commandQuoteRequestId}','${blockerQuoteRequestId}');
    delete from public.quote_requests where id in ('${commandQuoteRequestId}','${blockerQuoteRequestId}');
    delete from public.commercial_operators where operator_id in ('${ownerOperatorId}','${adminOperatorId}');
    delete from auth.users where id in ('${ownerUserId}','${adminUserId}');
    commit;
    select 'CLEAN';
  `);
}

async function main() {
  let holdingSession = null;
  if (container !== "supabase_db_xcsptvntvrizwhskaphr" || query("select current_database()") !== "postgres") {
    throw new Error("LOCAL_TEST_ENVIRONMENT_REQUIRED");
  }
  try {
    cleanupFixtures();
    query(`
      insert into auth.users(id,email) values
        ('${ownerUserId}','concurrency-owner@example.test'),
        ('${adminUserId}','concurrency-admin@example.test');
      insert into public.commercial_operators(operator_id,auth_user_id,display_name,role,status) values
        ('${ownerOperatorId}','${ownerUserId}','Concurrency Owner','owner','ACTIVE'),
        ('${adminOperatorId}','${adminUserId}','Concurrency Admin','admin','ACTIVE');
      insert into public.quote_requests(
        id,application_reference,record_classification,request_kind,name,email,website_type,budget,timing,description,privacy_consent,status
      ) values (
        '${commandQuoteRequestId}','LWS-AAN-2099-0501','production','website','Concurrency dossier','concurrency@example.test','business','Meer dan EUR 6.000','flexible','Concurrency command fixture.',true,'approved'
      );
      insert into public.quote_requests(id,request_kind,sdf_package,created_at,name,email,description,privacy_consent,status)
      values('${blockerQuoteRequestId}','slimme_documentenflow','groei','2026-08-18T06:40:00.735922Z','Legacy authority fixture','legacy-concurrency@example.test','Concurrent blocker fixture.',true,'approved')
    `);

    const archiveCapability = issueCapability(
      adminUserId, commandQuoteRequestId, "ARCHIVED", 0,
      "f5200000-0000-4000-8000-000000000001", "Concurrent archive"
    );
    holdingSession = startHoldingSession(`
      set application_name = 'lws_revoke_holder';
      begin;
      set local role authenticated;
      select set_config('request.jwt.claim.sub','${ownerUserId}',true);
      select public.set_commercial_operator_status_v1('${adminOperatorId}','REVOKED');
      select 'REVOKE_LOCK_HELD';
    `, "REVOKE_LOCK_HELD");
    await holdingSession.ready;
    const commandPromise = run(`
      set application_name = 'lws_revoke_waiter';
      begin;
      set local role authenticated;
      select set_config('request.jwt.claim.sub','${adminUserId}',true);
      select public.execute_operator_dossier_lifecycle_command_v1(
        '${commandQuoteRequestId}','ARCHIVED',0,
        'f5200000-0000-4000-8000-000000000001','Concurrent archive','${archiveCapability}'
      );
      commit;
    `);
    await proveBlocked("lws_revoke_waiter", "lws_revoke_holder");
    const revokeResult = await holdingSession.release();
    holdingSession = null;
    const commandResult = await commandPromise;
    if (revokeResult.code !== 0) throw new Error(`REVOCATION_TRANSACTION_FAILED:${JSON.stringify(revokeResult)}`);
    if (commandResult.code === 0 || !commandResult.stderr.includes("OPERATOR_REVOKED")) {
      throw new Error(`REVOKED_COMMAND_NOT_FAIL_CLOSED:${JSON.stringify(commandResult)}`);
    }
    if (query(`select state from lws_internal.operator_dossier_states where quote_request_id='${commandQuoteRequestId}'`) !== "ACTIVE") {
      throw new Error("REVOKED_COMMAND_MUTATED_DOSSIER");
    }

    const trashCapability = issueCapability(
      ownerUserId, blockerQuoteRequestId, "TRASHED", 0,
      "f5200000-0000-4000-8000-000000000002", "Concurrent trash"
    );
    holdingSession = startHoldingSession(`
      set application_name = 'lws_blocker_holder';
      begin;
      insert into public.sdf_projects(project_id,quote_request_id)
      values('${blockerProjectId}','${blockerQuoteRequestId}');
      select 'BLOCKER_LOCK_HELD';
    `, "BLOCKER_LOCK_HELD");
    await holdingSession.ready;
    const trashPromise = run(`
      set application_name = 'lws_trash_waiter';
      begin;
      set local role authenticated;
      select set_config('request.jwt.claim.sub','${ownerUserId}',true);
      select public.execute_operator_dossier_lifecycle_command_v1(
        '${blockerQuoteRequestId}','TRASHED',0,
        'f5200000-0000-4000-8000-000000000002','Concurrent trash','${trashCapability}'
      );
      commit;
    `);
    await proveBlocked("lws_trash_waiter", "lws_blocker_holder");
    const blockerResult = await holdingSession.release();
    holdingSession = null;
    const trashResult = await trashPromise;
    if (blockerResult.code !== 0) throw new Error(`BLOCKER_TRANSACTION_FAILED:${JSON.stringify(blockerResult)}`);
    if (trashResult.code === 0 || !trashResult.stderr.includes("LEGACY_TEST_CLEANUP_SDF_BLOCKER_PRESENT")) {
      throw new Error(`CONCURRENT_TRASH_NOT_BLOCKED:${JSON.stringify(trashResult)}`);
    }
    if (query(`select state from lws_internal.operator_dossier_states where quote_request_id='${blockerQuoteRequestId}'`) !== "ACTIVE") {
      throw new Error("BLOCKED_TRASH_MUTATED_DOSSIER");
    }

    process.stdout.write(JSON.stringify({
      test_context: "LOCAL_TEST_ONLY",
      revoke_lock_wait_proven: true,
      revoked_command: "OPERATOR_REVOKED",
      revoked_command_state: "ACTIVE",
      blocker_lock_wait_proven: true,
      concurrent_trash: "LEGACY_TEST_CLEANUP_SDF_BLOCKER_PRESENT",
      concurrent_trash_state: "ACTIVE"
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
