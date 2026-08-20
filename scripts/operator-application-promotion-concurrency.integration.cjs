const { readFileSync } = require("node:fs");
const { spawn, spawnSync } = require("node:child_process");
const { join } = require("node:path");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const baseArgs = ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At"];
const fixturePath = join(__dirname, "..", "supabase", "tests", "operator_application_handoff.sql");

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

const fixture = spawnSync("docker", [...baseArgs, "-v", "HANDOFF_FIXTURE_ONLY=1"], {
  encoding: "utf8",
  input: readFileSync(fixturePath, "utf8")
});
if (fixture.status !== 0) throw new Error(fixture.stderr || fixture.stdout);

function promotion(idempotencyKey) {
  return `begin;
    set local role authenticated;
    select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000002',true);
    select (result->>'project_id') || '|' || (result->>'was_created')
    from (select public.promote_operator_application_v1(
      '${idempotencyKey}',null,'LWS-AAN-2099-0001'
    ) as result) as promotion;
    commit;`;
}

Promise.all([
  run(promotion("a1900000-0000-4000-8000-000000000001")),
  run(promotion("a1900000-0000-4000-8000-000000000002"))
]).then((results) => {
  const failures = results.filter((result) => result.code !== 0);
  if (failures.length) throw new Error(`CONCURRENT_PROMOTION_FAILURE:${JSON.stringify(failures)}`);
  const outcomes = results.map((result) => result.stdout.trim().split(/\r?\n/).filter((line) => line.includes("|")).at(-1));
  const projectIds = new Set(outcomes.map((outcome) => outcome.split("|")[0]));
  const creationFlags = outcomes.map((outcome) => outcome.split("|")[1]).sort();
  if (projectIds.size !== 1 || creationFlags.join(",") !== "false,true") {
    throw new Error(`CONCURRENT_PROMOTION_OUTCOME_INVALID:${JSON.stringify(outcomes)}`);
  }

  const summary = JSON.parse(query(`select json_build_object(
    'projects',(select count(*) from public.commercial_projects),
    'customers',(select count(*) from public.commercial_customers),
    'workflow_events',(select count(*) from public.workflow_events),
    'audit_events',(select count(*) from public.audit_events),
    'ledger_entries',(select count(*) from public.idempotency_ledger),
    'acceptance_hash_valid',(select acceptance_payload_sha256=public.quotation_acceptance_payload_sha256_v1(acceptance_payload) from public.quote_request_quotation_acceptances where id='a1700000-0000-4000-8000-000000000001'),
    'approval_hash_valid',(select payload_sha256=public.quotation_approval_payload_sha256_v1(approved_payload) from public.quote_request_quotation_approvals where id='a1500000-0000-4000-8000-000000000001')
  )`));
  if (summary.projects !== 1 || summary.customers !== 1 || summary.workflow_events !== 1 || summary.audit_events !== 1 || summary.ledger_entries !== 1 || !summary.acceptance_hash_valid || !summary.approval_hash_valid) {
    throw new Error(`CONCURRENT_PROMOTION_STATE_INVALID:${JSON.stringify(summary)}`);
  }
  process.stdout.write(JSON.stringify({ test_context: "LOCAL_TEST_ONLY", concurrent_promotions: 2, project_id: [...projectIds][0], ...summary }) + "\n");
}).catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});