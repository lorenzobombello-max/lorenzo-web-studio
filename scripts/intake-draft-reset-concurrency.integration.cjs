const { spawn, spawnSync } = require("node:child_process");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const psqlArgs = ["exec", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At", "-c"];
const requestId = "d22c0000-0000-4000-8000-000000000001";
const intakeId = "d22c1000-0000-4000-8000-000000000001";
const tokenHash = "d22c".repeat(16);

function query(sql) {
  const result = spawnSync("docker", [...psqlArgs, sql], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout.trim().split(/\r?\n/).filter(Boolean).at(-1) || "";
}

function run(sql) {
  return new Promise((resolve) => {
    const child = spawn("docker", [...psqlArgs, sql]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (data) => stdout += data);
    child.stderr.on("data", (data) => stderr += data);
    child.on("exit", (code) => resolve({ code, stdout: stdout.trim(), stderr: stderr.trim() }));
  });
}

query(`
  begin;
  set local session_replication_role = replica;
  delete from public.quote_request_intakes where id='${intakeId}';
  delete from lws_internal.intake_identity_anchors where quote_request_id='${requestId}';
  delete from lws_internal.application_intake_automation_work where quote_request_id='${requestId}';
  delete from lws_internal.operator_dossier_assignment_commands where quote_request_id='${requestId}';
  delete from lws_internal.operator_dossier_assignment_events where quote_request_id='${requestId}';
  delete from lws_internal.operator_dossier_assignments where quote_request_id='${requestId}';
  delete from lws_internal.operator_dossier_state_events where quote_request_id='${requestId}';
  delete from lws_internal.operator_dossier_states where quote_request_id='${requestId}';
  delete from lws_internal.dossier_identity_anchors where quote_request_id='${requestId}';
  delete from public.quote_requests where id='${requestId}';
  set local session_replication_role = origin;
  insert into public.quote_requests(id,name,email,website_type,budget,timing,description,privacy_consent,status,budget_category_scheme,budget_category_code)
  values ('${requestId}','Concurrent reset','concurrent-reset@example.test','business','Meer dan EUR 6.000','flexible','Local concurrency fixture',true,'approved','budget_guard_v2','above_6000');
  insert into public.quote_request_intakes(id,quote_request_id,access_token_hash,access_token_expires_at,status,started_at,business_description,draft_revision)
  values ('${intakeId}','${requestId}','${tokenHash}',clock_timestamp()+interval '1 day','in_progress',clock_timestamp()-interval '1 hour','Original revision five',5);
  commit;
`);

Promise.all([
  run(`select outcome || '|' || draft_revision from public.reset_quote_request_intake_draft_v1('${tokenHash}',5);`),
  run(`select outcome || '|' || draft_revision from public.save_quote_request_intake_draft_v2('${tokenHash}',5,'{"business_description":"Concurrent stale save"}'::jsonb,'{}'::jsonb);`)
]).then((results) => {
  const failures = results.filter((result) => result.code !== 0);
  if (failures.length) throw new Error(`CONCURRENT_RESET_SAVE_FAILURE:${JSON.stringify(failures)}`);
  const outcomes = results.map((result) => result.stdout.split(/\r?\n/).filter(Boolean).at(-1)).sort();
  const validOutcomePair = outcomes.join(",") === "reset|6,stale_revision|6" || outcomes.join(",") === "saved|6,stale_revision|6";
  if (!validOutcomePair) throw new Error(`CONCURRENT_RESET_SAVE_OUTCOME_INVALID:${JSON.stringify(outcomes)}`);

  const state = JSON.parse(query(`select json_build_object(
    'revision',draft_revision,
    'business_description',business_description,
    'intake_count',(select count(*) from public.quote_request_intakes where id='${intakeId}'),
    'request_count',(select count(*) from public.quote_requests where id='${requestId}')
  ) from public.quote_request_intakes where id='${intakeId}';`));
  if (state.revision !== 6 || state.intake_count !== 1 || state.request_count !== 1) {
    throw new Error(`CONCURRENT_RESET_SAVE_STATE_INVALID:${JSON.stringify(state)}`);
  }

  const staleRetry = query(`select outcome from public.save_quote_request_intake_draft_v2('${tokenHash}',5,'{"business_description":"Old tab retry"}'::jsonb,'{}'::jsonb);`);
  if (staleRetry !== "stale_revision") throw new Error(`TWO_TAB_STALE_RETRY_INVALID:${staleRetry}`);

  process.stdout.write(JSON.stringify({
    test_context: "LOCAL_TEST_ONLY",
    concurrent_calls: 2,
    outcomes,
    stale_retry: staleRetry,
    ...state
  }) + "\n");
}).catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
