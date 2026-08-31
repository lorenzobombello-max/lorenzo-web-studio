const { spawn, spawnSync } = require("node:child_process");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const baseArgs = ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At"];
const requestId = "e1300001-0000-4000-8000-000000000001";
const globalWorkerId = "e1310000-0000-4000-8000-000000000001";
const targetedWorkerId = "e1310000-0000-4000-8000-000000000002";

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

function cleanup() {
  query(`
    begin;
    set local session_replication_role = replica;
    delete from lws_internal.application_intake_automation_work where quote_request_id = '${requestId}';
    delete from lws_internal.dossier_identity_anchors where quote_request_id = '${requestId}';
    delete from public.quote_requests where id = '${requestId}';
    commit;
  `);
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
      select public.activate_application_intake_automation_v1('TARGETED-CLAIM-CONCURRENCY-V1');
      update lws_internal.application_intake_automation_config
      set cutover_at = fixture.activated_at,
          activated_at = fixture.activated_at
      from (select clock_timestamp() - interval '1 hour' as activated_at) fixture
      where singleton;
      insert into public.quote_requests (
        id, request_kind, created_at, name, email, website_type, budget, timing,
        description, privacy_consent, status, record_classification,
        approval_token_hash, approval_token_expires_at
      ) values (
        '${requestId}', 'website', clock_timestamp() - interval '10 minutes',
        'Targeted claim race', 'targeted-race@example.test', 'business',
        'Meer dan EUR 6.000', 'flexible', 'Targeted claim race fixture', true,
        'pending', 'production', repeat('4', 64), clock_timestamp() + interval '1 day'
      );
    `);
    const workId = query(`
      select work_id
      from lws_internal.application_intake_automation_work
      where quote_request_id = '${requestId}'
    `);

    const [globalResult, targetedResult] = await Promise.all([
      run(`
        set role service_role;
        select row_to_json(claimed)::text
        from public.claim_application_intake_automation_work_v1('${globalWorkerId}', 5) claimed;
      `),
      run(`
        set role service_role;
        select row_to_json(claimed)::text
        from public.claim_application_intake_automation_work_by_id_v1('${targetedWorkerId}', ${workId}) claimed;
      `),
    ]);

    for (const result of [globalResult, targetedResult]) {
      if (result.code !== 0) throw new Error(result.stderr || result.stdout);
    }
    const claims = `${globalResult.stdout}\n${targetedResult.stdout}`
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line.startsWith("{") && line.endsWith("}"))
      .map((line) => JSON.parse(line));
    if (claims.length !== 1) throw new Error(`EXPECTED_ONE_RACE_WINNER:${JSON.stringify(claims)}`);
    if (String(claims[0].work_id) !== workId) throw new Error(`WRONG_WORK_CLAIMED:${JSON.stringify(claims[0])}`);

    const state = JSON.parse(query(`
      select json_build_object(
        'attempt_count', attempt_count,
        'claim_count', case when claim_token is null then 0 else 1 end,
        'winner_is_known', claimed_by in ('${globalWorkerId}', '${targetedWorkerId}'),
        'lease_seconds', extract(epoch from claim_expires_at - claimed_at)::integer
      )
      from lws_internal.application_intake_automation_work
      where work_id = ${workId}
    `));
    if (state.attempt_count !== 1) throw new Error(`ATTEMPT_COUNT_MISMATCH:${JSON.stringify(state)}`);
    if (state.claim_count !== 1) throw new Error(`CLAIM_COUNT_MISMATCH:${JSON.stringify(state)}`);
    if (!state.winner_is_known) throw new Error(`UNKNOWN_WINNER:${JSON.stringify(state)}`);
    if (state.lease_seconds !== 90) throw new Error(`LEASE_MISMATCH:${JSON.stringify(state)}`);

    console.log("application intake automation global-versus-targeted claim race: PASS");
  } finally {
    cleanup();
    const config = JSON.parse(originalConfig);
    query(`
      update lws_internal.application_intake_automation_config
      set active = ${config.active},
          cutover_at = ${config.cutover_at ? `'${config.cutover_at}'::timestamptz` : "null"},
          activation_reference = ${config.activation_reference ? `'${config.activation_reference.replaceAll("'", "''")}'` : "null"},
          activated_at = ${config.activated_at ? `'${config.activated_at}'::timestamptz` : "null"}
      where singleton;
    `);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
