const { spawn, spawnSync } = require("node:child_process");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const baseArgs = ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At"];
const requestId = "fd710001-0000-4000-8000-000000000001";
const jobId = "fd720001-0000-4000-8000-000000000001";
const leaseToken = "fd730001-0000-4000-8000-000000000001";
const globalWorkerId = "fd740001-0000-4000-8000-000000000001";
const targetedWorkerId = "fd740002-0000-4000-8000-000000000002";

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

function jsonLines(result) {
  if (result.code !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.startsWith("{") && line.endsWith("}"))
    .map((line) => JSON.parse(line));
}

function cleanup() {
  query(`
    begin;
    set local session_replication_role = replica;
    delete from lws_internal.sdf_initial_confirmation_recovery_events where quote_request_id = '${requestId}';
    delete from public.sdf_initial_confirmation_email_jobs where quote_request_id = '${requestId}';
    delete from lws_internal.application_intake_automation_work where quote_request_id = '${requestId}';
    delete from lws_internal.operator_dossier_assignments where quote_request_id = '${requestId}';
    delete from lws_internal.operator_dossier_states where quote_request_id = '${requestId}';
    delete from lws_internal.dossier_identity_anchors where quote_request_id = '${requestId}';
    delete from public.quote_requests where id = '${requestId}';
    commit;
  `);
}

function setup() {
  cleanup();
  query(`
    insert into public.quote_requests (
      id, created_at, record_classification, request_kind, sdf_package, name, email,
      description, privacy_consent, status, approval_token_hash,
      approval_token_expires_at
    ) values (
      '${requestId}', clock_timestamp() - interval '2 hours', 'production', 'slimme_documentenflow', 'start',
      'Recovery concurrency fixture', 'sdf-recovery-race@example.test',
      'Bounded stale recovery race fixture.', true, 'pending', repeat('7', 64),
      clock_timestamp() + interval '1 day'
    );
    insert into lws_internal.application_intake_automation_work (
      quote_request_id, phase, approval_due_at, attempt_count, next_attempt_at
    ) values (
      '${requestId}', 'SDF_CONFIRMATION', clock_timestamp() - interval '2 hours',
      5, clock_timestamp() - interval '1 hour'
    )
    on conflict (quote_request_id) do update
    set phase = excluded.phase,
        attempt_count = excluded.attempt_count,
        next_attempt_at = excluded.next_attempt_at,
        claim_token = null,
        claimed_by = null,
        claimed_at = null,
        claim_expires_at = null;
    insert into public.sdf_initial_confirmation_email_jobs (
      job_id, quote_request_id, status, attempt_count, next_attempt_at,
      locked_at, delivery_lease_token, delivery_lease_expires_at
    ) values (
      '${jobId}', '${requestId}', 'processing', 1,
      clock_timestamp() - interval '1 hour', clock_timestamp() - interval '1 hour',
      '${leaseToken}', clock_timestamp() - interval '50 minutes'
    );
  `);
  return query(`select work_id from lws_internal.application_intake_automation_work where quote_request_id = '${requestId}'`);
}

function recoverySql(workId, reference) {
  return `
    set role service_role;
    select public.recover_stale_sdf_initial_confirmation_work_v1(
      ${workId}, '${jobId}', '${reference}'
    )::text;
  `;
}

function targetedClaimSql(workId) {
  return `
    set role service_role;
    select row_to_json(claimed)::text
    from public.claim_application_intake_automation_work_by_id_v1(
      '${targetedWorkerId}', ${workId}
    ) claimed;
  `;
}

function globalClaimSql() {
  return `
    set role service_role;
    select row_to_json(claimed)::text
    from public.claim_application_intake_automation_work_v1('${globalWorkerId}', 5) claimed;
  `;
}

function state(workId) {
  return JSON.parse(query(`
    select json_build_object(
      'event_count', (select count(*) from lws_internal.sdf_initial_confirmation_recovery_events where work_id = ${workId}),
      'isolated_job_count', (select count(*) from public.sdf_initial_confirmation_email_jobs where quote_request_id = '${requestId}'),
      'job_id', job.job_id,
      'job_status', job.status,
      'job_attempt_count', job.attempt_count,
      'job_leased', job.delivery_lease_token is not null,
      'work_phase', work.phase,
      'work_attempt_count', work.attempt_count,
      'work_claimed', work.claim_token is not null,
      'provider_key', 'sdf-initial-confirmation/' || job.job_id::text
    )
    from lws_internal.application_intake_automation_work work
    join public.sdf_initial_confirmation_email_jobs job on job.quote_request_id = work.quote_request_id
    where work.work_id = ${workId}
  `));
}

function assertCanonicalState(current, expectedAttemptCount, expectedClaimed) {
  if (current.event_count !== 1) throw new Error(`EVENT_COUNT_MISMATCH:${JSON.stringify(current)}`);
  if (current.isolated_job_count !== 1) throw new Error(`JOB_COUNT_MISMATCH:${JSON.stringify(current)}`);
  if (current.job_id !== jobId) throw new Error(`JOB_ID_CHANGED:${JSON.stringify(current)}`);
  if (current.job_status !== "retry_wait" || current.job_attempt_count !== 1 || current.job_leased) {
    throw new Error(`JOB_STATE_MISMATCH:${JSON.stringify(current)}`);
  }
  if (current.work_phase !== "SDF_CONFIRMATION") throw new Error(`WORK_PHASE_CHANGED:${JSON.stringify(current)}`);
  if (current.work_attempt_count !== expectedAttemptCount || current.work_claimed !== expectedClaimed) {
    throw new Error(`WORK_STATE_MISMATCH:${JSON.stringify(current)}`);
  }
  if (current.provider_key !== `sdf-initial-confirmation/${jobId}`) {
    throw new Error(`PROVIDER_KEY_CHANGED:${JSON.stringify(current)}`);
  }
}

async function main() {
  cleanup();
  const originalConfig = query(`
    select row_to_json(config)::text
    from lws_internal.application_intake_automation_config config
    where singleton
  `);

  try {
    query(`
      select public.activate_application_intake_automation_v1('SDF-RECOVERY-CONCURRENCY-V1');
      update lws_internal.application_intake_automation_config
      set cutover_at = fixture.activated_at,
          activated_at = fixture.activated_at
      from (select clock_timestamp() - interval '1 day' as activated_at) fixture
      where singleton;
    `);

    let workId = setup();
    const recoveryRace = await Promise.all([
      run(recoverySql(workId, "RECOVERY-RACE-FIRST")),
      run(recoverySql(workId, "RECOVERY-RACE-SECOND")),
    ]);
    const recoveryOutcomes = recoveryRace.flatMap(jsonLines).map((value) => value.outcome).sort();
    if (JSON.stringify(recoveryOutcomes) !== JSON.stringify(["already_recovered", "recovered"])) {
      throw new Error(`RECOVERY_RACE_MISMATCH:${JSON.stringify(recoveryOutcomes)}`);
    }
    assertCanonicalState(state(workId), 0, false);

    workId = setup();
    const mixedRace = await Promise.all([
      run(recoverySql(workId, "RECOVERY-VERSUS-CLAIMS")),
      run(targetedClaimSql(workId)),
      run(globalClaimSql()),
    ]);
    const recoveryResult = jsonLines(mixedRace[0]);
    if (recoveryResult.length !== 1 || recoveryResult[0].outcome !== "recovered") {
      throw new Error(`RECOVERY_DID_NOT_WIN_AUTHORITY:${JSON.stringify(recoveryResult)}`);
    }
    const mixedClaims = [...jsonLines(mixedRace[1]), ...jsonLines(mixedRace[2])];
    if (mixedClaims.length > 1) throw new Error(`MULTIPLE_MIXED_CLAIMS:${JSON.stringify(mixedClaims)}`);
    assertCanonicalState(state(workId), mixedClaims.length, mixedClaims.length === 1);

    workId = setup();
    const recovered = jsonLines(await run(recoverySql(workId, "RECOVERY-BEFORE-CLAIM-RACE")));
    if (recovered.length !== 1 || recovered[0].outcome !== "recovered") {
      throw new Error(`PRE_CLAIM_RECOVERY_FAILED:${JSON.stringify(recovered)}`);
    }
    const claimRace = await Promise.all([
      run(globalClaimSql()),
      run(targetedClaimSql(workId)),
    ]);
    const claims = claimRace.flatMap(jsonLines);
    if (claims.length !== 1) throw new Error(`EXPECTED_ONE_POST_RECOVERY_WINNER:${JSON.stringify(claims)}`);
    if (String(claims[0].work_id) !== workId) throw new Error(`WRONG_WORK_CLAIMED:${JSON.stringify(claims[0])}`);
    assertCanonicalState(state(workId), 1, true);

    console.log("SDF initial-confirmation bounded recovery concurrency: PASS");
  } finally {
    cleanup();
    const config = JSON.parse(originalConfig);
    query(`
      update lws_internal.application_intake_automation_config
      set active = ${config.active},
          cutover_at = ${config.cutover_at ? `'${config.cutover_at}'::timestamptz` : "null"},
          activation_reference = ${config.activation_reference ? `'${config.activation_reference.replaceAll("'", "''")}'` : "null"},
          activated_at = ${config.activated_at ? `'${config.activated_at}'::timestamptz` : "null"},
          deactivated_at = ${config.deactivated_at ? `'${config.deactivated_at}'::timestamptz` : "null"}
      where singleton;
    `);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
