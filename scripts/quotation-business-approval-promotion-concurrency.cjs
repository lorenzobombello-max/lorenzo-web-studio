const { readFileSync } = require("node:fs");
const { spawn, spawnSync } = require("node:child_process");
const { join } = require("node:path");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const baseArgs = ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At"];
const fixtureSource = readFileSync(join(__dirname, "..", "supabase", "tests", "quotation_business_approval_promotion_v1.sql"), "utf8");
const fixtureStart = fixtureSource.indexOf("insert into auth.users");
const fixtureEnd = fixtureSource.indexOf("create function pg_temp.promotion_proof");
if (fixtureStart < 0 || fixtureEnd <= fixtureStart) throw new Error("PROMOTION_FIXTURE_NOT_FOUND");
const fixture = fixtureSource.slice(fixtureStart, fixtureEnd);

function execute(sql) {
  const result = spawnSync("docker", baseArgs, { encoding: "utf8", input: sql });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout.trim().split(/\r?\n/).filter(Boolean).at(-1) || "";
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

const cleanup = `
  set session_replication_role = replica;
  delete from public.quote_request_quotation_business_approval_promotion_operations where business_draft_id::text like 'ca170000-%';
  delete from public.quote_request_quotation_business_approval_promotions where business_draft_id::text like 'ca170000-%';
  delete from public.quote_request_quotation_approval_operations where approval_id::text like 'ca190000-%';
  delete from public.quote_request_quotation_approval_integrity where approval_id::text like 'ca190000-%';
  delete from public.quote_request_quotation_approvals where id::text like 'ca190000-%';
  delete from public.quote_request_quotation_business_drafts where business_draft_id::text like 'ca170000-%';
  delete from public.quote_request_quotation_approval_drafts where id::text like 'ca160000-%';
  delete from public.quote_request_pricing_snapshot_integrity where snapshot_id::text like 'ca140000-%';
  delete from public.quote_request_pricing_snapshots where id::text like 'ca140000-%';
  delete from public.quotation_vat_decision_authorities where vat_decision_authority_id::text like 'ca150000-%';
  delete from public.quote_request_intakes where id::text like 'ca130000-%';
  delete from lws_internal.operator_dossier_assignments where quote_request_id::text like 'ca1200%';
  delete from lws_internal.operator_dossier_states where quote_request_id::text like 'ca1200%';
  delete from public.quote_requests where id::text like 'ca1200%';
  delete from public.commercial_operators where operator_id::text like 'ca110000-%';
  delete from auth.users where id::text like 'ca100000-%';
  set session_replication_role = origin;
`;

function resetFixture() {
  execute(cleanup);
  execute(fixture);
}

function promotion(intakeId, idempotencyKey, approvalId) {
  return `select (result->>'approval_id') || '|' || (result->>'was_created')
    from (
      select public.promote_quotation_business_draft_to_approval_v1(
        'ca100000-0000-4000-8000-000000000001', '${intakeId}', 1,
        '${idempotencyKey}', '${approvalId}',
        jsonb_build_object(
          'algorithmVersion', 'hmac-sha256-v1', 'keyId', 'v1', 'mac', repeat('d',64),
          'root', public.quotation_approval_integrity_root_v1(
            '${approvalId}', rtrim(business.canonical_payload_sha256), 1::smallint,
            business.quote_request_id, business.intake_id, business.pricing_snapshot_id
          )
        )
      ) as result
      from public.quote_request_quotation_business_drafts as business
      where business.intake_id = '${intakeId}'
    ) as promoted;`;
}

function outcomes(results, label) {
  const failures = results.filter((result) => result.code !== 0);
  if (failures.length) throw new Error(`${label}_FAILURE:${JSON.stringify(failures)}`);
  return results.map((result) => result.stdout.trim().split(/\r?\n/).filter((line) => line.includes("|")).at(-1));
}

async function main() {
  resetFixture();
  const raceA = outcomes(await Promise.all([
    run(promotion("ca130000-0000-4000-8000-000000000001", "ca180000-0000-4000-8000-000000000011", "ca190000-0000-4000-8000-000000000011")),
    run(promotion("ca130000-0000-4000-8000-000000000001", "ca180000-0000-4000-8000-000000000012", "ca190000-0000-4000-8000-000000000012")),
  ]), "RACE_A");
  const raceAApprovals = new Set(raceA.map((value) => value.split("|")[0]));
  const raceACreation = raceA.map((value) => value.split("|")[1]).sort().join(",");
  if (raceAApprovals.size !== 1 || raceACreation !== "false,true") {
    throw new Error(`RACE_A_OUTCOME_INVALID:${JSON.stringify(raceA)}`);
  }

  resetFixture();
  const raceB = outcomes(await Promise.all([
    run(promotion("ca130000-0000-4000-8000-000000000001", "ca170000-0000-4000-8000-000000000002", "ca190000-0000-4000-8000-000000000021")),
    run(promotion("ca130000-0000-4000-8000-000000000002", "ca170000-0000-4000-8000-000000000001", "ca190000-0000-4000-8000-000000000022")),
  ]), "RACE_B");
  if (new Set(raceB.map((value) => value.split("|")[0])).size !== 2
    || raceB.some((value) => !value.endsWith("|true"))) {
    throw new Error(`RACE_B_OUTCOME_INVALID:${JSON.stringify(raceB)}`);
  }

  const state = JSON.parse(query(`select json_build_object(
    'bindings',(select count(*) from public.quote_request_quotation_business_approval_promotions where business_draft_id::text like 'ca170000-%'),
    'operations',(select count(*) from public.quote_request_quotation_business_approval_promotion_operations where business_draft_id::text like 'ca170000-%'),
    'approvals',(select count(*) from public.quote_request_quotation_approvals where id::text like 'ca190000-%'),
    'issuances',(select count(*) from public.quote_request_quotation_issuances where approval_id::text like 'ca190000-%')
  )`));
  if (state.bindings !== 2 || state.operations !== 2 || state.approvals !== 2 || state.issuances !== 0) {
    throw new Error(`RACE_B_STATE_INVALID:${JSON.stringify(state)}`);
  }
  process.stdout.write(JSON.stringify({ test_context: "LOCAL_TEST_ONLY", race_a: raceA, race_b: raceB, ...state }) + "\n");
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
}).finally(() => {
  try {
    execute(cleanup);
  } catch (error) {
    process.stderr.write(`PROMOTION_FIXTURE_CLEANUP_FAILED:${error.message}\n`);
    process.exitCode = 1;
  }
});