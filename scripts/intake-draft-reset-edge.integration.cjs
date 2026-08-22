const { createHmac } = require("node:crypto");
const { spawnSync } = require("node:child_process");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const psqlArgs = ["exec", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At", "-c"];
const endpoint = "http://127.0.0.1:54321/functions/v1/intake-quote-request";
const requestId = "d22e0000-0000-4000-8000-000000000001";
const intakeId = "d22e1000-0000-4000-8000-000000000001";
const token = "R".repeat(43);
const tokenHash = createHmac("sha256", "local-reset-test-approval-secret-20260822")
  .update(`intake:${token}`)
  .digest("hex");

function query(sql) {
  const result = spawnSync("docker", [...psqlArgs, sql], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout.trim().split(/\r?\n/).filter(Boolean).at(-1) || "";
}

async function request(action, expectedRevision, data, requestToken = token) {
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      action,
      token: requestToken,
      ...(expectedRevision === undefined ? {} : { expected_revision: expectedRevision }),
      ...(data === undefined ? {} : { data }),
      intake_id: "ffffffff-ffff-4fff-8fff-ffffffffffff",
      access_token_hash: "0".repeat(64),
    }),
  });
  return { status: response.status, body: await response.json() };
}

query(`
  delete from public.quote_request_intakes where id='${intakeId}';
  delete from public.quote_requests where id='${requestId}';
  insert into public.quote_requests(id,name,email,website_type,budget,timing,description,privacy_consent,status,budget_category_scheme,budget_category_code)
  values ('${requestId}','Edge reset','edge-reset@example.test','business','Meer dan EUR 6.000','flexible','Local Edge fixture',true,'approved','budget_guard_v2','above_6000');
  insert into public.quote_request_intakes(id,quote_request_id,access_token_hash,access_token_expires_at,status,started_at,business_description,draft_revision)
  values ('${intakeId}','${requestId}','${tokenHash}',clock_timestamp()+interval '1 day','in_progress',clock_timestamp()-interval '1 hour','Edge original',3);
`);

(async () => {
  const inspected = await request("inspect");
  if (inspected.status !== 200 || inspected.body.intake?.id !== intakeId || inspected.body.intake?.revision !== 3 || inspected.body.data?.business_description !== "Edge original") {
    throw new Error(`EDGE_INSPECT_INVALID:${JSON.stringify(inspected)}`);
  }

  const oldClientIntake = {
    id: inspected.body.intake.id,
    status: inspected.body.intake.status,
    started_at: inspected.body.intake.started_at,
    submitted_at: inspected.body.intake.submitted_at,
    reviewed_at: inspected.body.intake.reviewed_at,
  };
  if (oldClientIntake.id !== intakeId || inspected.body.data.business_description !== "Edge original") {
    throw new Error(`EDGE_OLD_INSPECT_CONSUMPTION_INVALID:${JSON.stringify(oldClientIntake)}`);
  }

  const legacySaved = await request("save_draft", undefined, { business_description: "Legacy saved" });
  if (legacySaved.status !== 200 || legacySaved.body.state !== "saved" || legacySaved.body.code === "INVALID_EXPECTED_REVISION") {
    throw new Error(`EDGE_LEGACY_SAVE_INVALID:${JSON.stringify(legacySaved)}`);
  }
  const legacyStored = JSON.parse(query(`select json_build_object('revision',draft_revision,'business_description',business_description) from public.quote_request_intakes where id='${intakeId}';`));
  if (legacyStored.revision !== 3 || legacyStored.business_description !== "Legacy saved") {
    throw new Error(`EDGE_LEGACY_ROUTE_INVALID:${JSON.stringify(legacyStored)}`);
  }

  const saved = await request("save_draft", 3, { business_description: "Edge saved" });
  if (saved.status !== 200 || saved.body.state !== "saved" || saved.body.intake?.revision !== 4) {
    throw new Error(`EDGE_SAVE_INVALID:${JSON.stringify(saved)}`);
  }

  const staleSave = await request("save_draft", 3, { business_description: "Stale downgrade attempt" });
  if (staleSave.status !== 409 || staleSave.body.code !== "INTAKE_REVISION_CONFLICT") {
    throw new Error(`EDGE_STALE_SAVE_INVALID:${JSON.stringify(staleSave)}`);
  }

  for (const invalidRevision of [null, "4", -1, 1.5]) {
    const invalidSave = await request("save_draft", invalidRevision, { business_description: "Invalid downgrade attempt" });
    if (invalidSave.status !== 400 || invalidSave.body.code !== "INVALID_EXPECTED_REVISION") {
      throw new Error(`EDGE_INVALID_SAVE_REVISION:${JSON.stringify({ invalidRevision, invalidSave })}`);
    }
  }

  const missingResetRevision = await request("reset_draft");
  if (missingResetRevision.status !== 400 || missingResetRevision.body.code !== "INVALID_EXPECTED_REVISION") {
    throw new Error(`EDGE_MISSING_RESET_REVISION_INVALID:${JSON.stringify(missingResetRevision)}`);
  }

  const staleReset = await request("reset_draft", 3);
  if (staleReset.status !== 409 || staleReset.body.code !== "INTAKE_REVISION_CONFLICT") {
    throw new Error(`EDGE_STALE_RESET_INVALID:${JSON.stringify(staleReset)}`);
  }

  const reset = await request("reset_draft", 4);
  if (reset.status !== 200 || reset.body.state !== "reset" || reset.body.intake?.revision !== 5) {
    throw new Error(`EDGE_RESET_INVALID:${JSON.stringify(reset)}`);
  }

  const reloaded = await request("inspect");
  if (reloaded.status !== 200 || reloaded.body.intake?.id !== intakeId || reloaded.body.intake?.revision !== 5 || reloaded.body.data?.business_description !== null) {
    throw new Error(`EDGE_RESET_RELOAD_INVALID:${JSON.stringify(reloaded)}`);
  }

  const invalid = await request("reset_draft", 0, undefined, "Z".repeat(43));
  if (invalid.status !== 401 || invalid.body.code !== "INVALID_INTAKE_TOKEN") {
    throw new Error(`EDGE_INVALID_TOKEN_INVALID:${JSON.stringify(invalid)}`);
  }

  const stored = JSON.parse(query(`select json_build_object(
    'id',id,
    'quote_request_id',quote_request_id,
    'token_hash',access_token_hash,
    'revision',draft_revision,
    'business_description',business_description
  ) from public.quote_request_intakes where id='${intakeId}';`));
  if (stored.id !== intakeId || stored.quote_request_id !== requestId || stored.token_hash !== tokenHash || stored.revision !== 5 || stored.business_description !== null) {
    throw new Error(`EDGE_STORED_STATE_INVALID:${JSON.stringify(stored)}`);
  }

  process.stdout.write(JSON.stringify({
    test_context: "LOCAL_TEST_ONLY",
    inspect: inspected.status,
    old_inspect: oldClientIntake.status,
    legacy_save: legacySaved.status,
    save: saved.status,
    stale_save: staleSave.status,
    invalid_save_revisions: 4,
    missing_reset_revision: missingResetRevision.status,
    stale_reset: staleReset.status,
    reset: reset.status,
    reload: reloaded.status,
    invalid_token: invalid.status,
    revision: stored.revision,
    target_intake: stored.id
  }) + "\n");
})().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
