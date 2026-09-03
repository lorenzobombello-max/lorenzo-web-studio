const { spawn, spawnSync } = require("node:child_process");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const baseArgs = ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At"];
const requestId = "f6300000-0000-4000-8000-000000000001";
const workerId = "f6300000-0000-4000-8000-000000000002";

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

function jsonRows(output) {
  return output.split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.startsWith("{") && line.endsWith("}"))
    .map((line) => JSON.parse(line));
}

function cleanup() {
  query(`
    begin;
    set local session_replication_role = replica;
    delete from public.sdf_qualification_intake_email_jobs where intake_id in (select intake_id from public.sdf_qualification_intakes where quote_request_id = '${requestId}');
    delete from public.sdf_qualification_intake_events where intake_id in (select intake_id from public.sdf_qualification_intakes where quote_request_id = '${requestId}');
    delete from public.sdf_qualification_intakes where quote_request_id = '${requestId}';
    delete from lws_internal.application_intake_automation_work where quote_request_id = '${requestId}';
    delete from lws_internal.operator_dossier_assignment_commands where quote_request_id = '${requestId}';
    delete from lws_internal.operator_dossier_assignment_events where quote_request_id = '${requestId}';
    delete from lws_internal.operator_dossier_assignments where quote_request_id = '${requestId}';
    delete from lws_internal.operator_dossier_state_events where quote_request_id = '${requestId}';
    delete from lws_internal.operator_dossier_states where quote_request_id = '${requestId}';
    delete from lws_internal.dossier_identity_anchors where quote_request_id = '${requestId}';
    delete from public.quote_requests where id = '${requestId}';
    commit;
  `);
}

async function main() {
  cleanup();
  const originalConfig = JSON.parse(query(`select row_to_json(config)::text from lws_internal.application_intake_automation_config config where singleton`));
  try {
    query(`
      select public.activate_application_intake_automation_v1('SDF-AUTOMATIC-CONCURRENCY-V1');
      update lws_internal.application_intake_automation_config
      set cutover_at = fixture.activated_at, activated_at = fixture.activated_at
      from (select clock_timestamp() - interval '1 hour' as activated_at) fixture
      where singleton;
      insert into public.quote_requests(
        id, request_kind, sdf_package, created_at, name, email, description,
        privacy_consent, status, record_classification, approval_token_hash,
        approval_token_expires_at, confirmation_sent_at
      ) values (
        '${requestId}', 'slimme_documentenflow', 'groei', clock_timestamp() - interval '10 minutes',
        'SDF automatic concurrency', 'sdf-auto-race@example.test', 'Concurrent ensure fixture',
        true, 'pending', 'production', repeat('a', 64), clock_timestamp() + interval '1 day',
        clock_timestamp() - interval '4 minutes'
      );
      update lws_internal.application_intake_automation_work work
      set phase = 'SDF_INTAKE', approved_at = request.confirmation_sent_at,
          intake_due_at = request.confirmation_sent_at + interval '120 seconds',
          next_attempt_at = request.confirmation_sent_at + interval '120 seconds'
      from public.quote_requests request
      where request.id = work.quote_request_id and request.id = '${requestId}';
    `);
    const claim = JSON.parse(query(`
      select row_to_json(claimed)::text
      from public.claim_application_intake_automation_work_v1('${workerId}', 1) claimed
      where claimed.quote_request_id = '${requestId}'
    `));
    const executionSql = `
      set role service_role;
      select public.execute_application_intake_automation_sdf_intake_v1(
        ${claim.work_id}, '${claim.claim_token}', repeat('b', 64),
        'v1.BBBBBBBBBBBBBBBB.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
      )::text;
    `;
    const executionResults = await Promise.all([run(executionSql), run(executionSql)]);
    for (const result of executionResults) if (result.code !== 0) throw new Error(result.stderr || result.stdout);
    const authorities = executionResults.flatMap((result) => jsonRows(result.stdout));
    if (authorities.length !== 2) throw new Error(`EXPECTED_TWO_EXECUTION_RESULTS:${JSON.stringify(authorities)}`);
    if (new Set(authorities.map((authority) => authority.job_id)).size !== 1) throw new Error(`JOB_IDENTITY_DIVERGED:${JSON.stringify(authorities)}`);

    const counts = JSON.parse(query(`
      select json_build_object(
        'intakes', (select count(*) from public.sdf_qualification_intakes where quote_request_id = '${requestId}'),
        'events', (select count(*) from public.sdf_qualification_intake_events event join public.sdf_qualification_intakes intake using (intake_id) where intake.quote_request_id = '${requestId}' and event.event_kind = 'INVITED'),
        'jobs', (select count(*) from public.sdf_qualification_intake_email_jobs job join public.sdf_qualification_intakes intake using (intake_id) where intake.quote_request_id = '${requestId}' and job.kind = 'invitation'),
        'system_events', (select count(*) from public.sdf_qualification_intake_events event join public.sdf_qualification_intakes intake using (intake_id) where intake.quote_request_id = '${requestId}' and event.actor_class = 'system' and event.actor_operator_id is null)
      )::text
    `));
    if (counts.intakes !== 1 || counts.events !== 1 || counts.jobs !== 1 || counts.system_events !== 1) {
      throw new Error(`EXACT_ONCE_VIOLATION:${JSON.stringify(counts)}`);
    }

    const jobId = authorities[0].job_id;
    const deliverySql = `set role service_role; select row_to_json(claimed)::text from public.claim_sdf_qualification_email_job_v1('${jobId}') claimed;`;
    const deliveryResults = await Promise.all([run(deliverySql), run(deliverySql)]);
    for (const result of deliveryResults) if (result.code !== 0) throw new Error(result.stderr || result.stdout);
    const deliveryClaims = deliveryResults.flatMap((result) => jsonRows(result.stdout));
    if (deliveryClaims.length !== 1) throw new Error(`EXPECTED_ONE_DELIVERY_WINNER:${JSON.stringify(deliveryClaims)}`);

    console.log("SDF automatic intake concurrent ensure and delivery claim: PASS");
  } finally {
    cleanup();
    query(`
      update lws_internal.application_intake_automation_config
      set active = ${originalConfig.active},
          cutover_at = ${originalConfig.cutover_at ? `'${originalConfig.cutover_at}'::timestamptz` : "null"},
          activation_reference = ${originalConfig.activation_reference ? `'${originalConfig.activation_reference.replaceAll("'", "''")}'` : "null"},
          activated_at = ${originalConfig.activated_at ? `'${originalConfig.activated_at}'::timestamptz` : "null"}
      where singleton;
    `);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
