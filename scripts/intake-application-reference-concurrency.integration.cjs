const { spawn, spawnSync } = require("node:child_process");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const psqlArgs = ["exec", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At", "-c"];
const fixtureCount = 12;

function query(sql) {
  const result = spawnSync("docker", [...psqlArgs, sql], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout.trim();
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

const requestValues = [];
const intakeValues = [];
const requestIds = [];
const intakeIds = [];
for (let index = 1; index <= fixtureCount; index += 1) {
  const suffix = String(index).padStart(12, "0");
  const tokenCharacter = "123456789abc"[index - 1];
  const requestId = `19b3${String(index).padStart(4, "0")}-0000-4000-8000-${suffix}`;
  const intakeId = `19b4${String(index).padStart(4, "0")}-0000-4000-8000-${suffix}`;
  requestIds.push(requestId);
  intakeIds.push(intakeId);
  requestValues.push(`('${requestId}','Concurrent ${index}','concurrent-${index}@example.test','business','Meer dan EUR 6.000','flexible','Concurrency fixture',true,'approved','budget_guard_v2','above_6000')`);
  intakeValues.push(`('${intakeId}','${requestId}',repeat('${tokenCharacter}',64),clock_timestamp()+interval '1 day')`);
}

query(`
  begin;
  set local session_replication_role = replica;
  delete from public.quote_request_intakes where id in (${intakeIds.map((id)=>`'${id}'`).join(",")});
  delete from lws_internal.intake_identity_anchors where quote_request_id in (${requestIds.map((id)=>`'${id}'`).join(",")});
  delete from lws_internal.application_intake_automation_work where quote_request_id in (${requestIds.map((id)=>`'${id}'`).join(",")});
  delete from lws_internal.operator_dossier_assignment_commands where quote_request_id in (${requestIds.map((id)=>`'${id}'`).join(",")});
  delete from lws_internal.operator_dossier_assignment_events where quote_request_id in (${requestIds.map((id)=>`'${id}'`).join(",")});
  delete from lws_internal.operator_dossier_assignments where quote_request_id in (${requestIds.map((id)=>`'${id}'`).join(",")});
  delete from lws_internal.operator_dossier_state_events where quote_request_id in (${requestIds.map((id)=>`'${id}'`).join(",")});
  delete from lws_internal.operator_dossier_states where quote_request_id in (${requestIds.map((id)=>`'${id}'`).join(",")});
  delete from lws_internal.dossier_identity_anchors where quote_request_id in (${requestIds.map((id)=>`'${id}'`).join(",")});
  delete from public.quote_requests where id in (${requestIds.map((id)=>`'${id}'`).join(",")});
  set local session_replication_role = origin;
  insert into public.quote_requests(id,name,email,website_type,budget,timing,description,privacy_consent,status,budget_category_scheme,budget_category_code)
  values ${requestValues.join(",")};
  insert into public.quote_request_intakes(id,quote_request_id,access_token_hash,access_token_expires_at)
  values ${intakeValues.join(",")};
  commit;
`);

Promise.all(Array.from({ length: fixtureCount }, (_, offset) => {
  const suffix = String(offset + 1).padStart(12, "0");
  const tokenCharacter = "123456789abc"[offset];
  return run(`select outcome from public.update_quote_request_intake(
    repeat('${tokenCharacter}',64),'submit',
    '{"business_description":"Complete concurrent submission","target_audience":"Local businesses","primary_conversion_goal":"Request quote","website_goals":["generate_leads"],"requested_pages":["home"],"requested_features":[],"design_styles":["modern"],"brand_status":"complete","logo_status":"available","content_status":"complete","image_status":"sufficient","domain_status":"has_domain","hosting_status":"has_hosting","maintenance_interest":"no","seo_priority":"basic","priorities":["usability"],"confirmation":true}'::jsonb,
    repeat('${tokenCharacter}',64),clock_timestamp()+interval '1 day');`);
})).then((results) => {
  const failures = results.filter((result) => result.code !== 0);
  if (failures.length) throw new Error(`CONCURRENT_SUBMIT_FAILURE:${JSON.stringify(failures)}`);

  const summary = query(`
    select json_build_object(
      'count',count(*),
      'unique_count',count(distinct application_reference),
      'format_count',count(*) filter(where application_reference ~ '^LWS-AAN-[0-9]{4}-[0-9]{4}$'),
      'year_count',count(distinct substring(application_reference from 9 for 4)),
      'min_sequence',min(right(application_reference,4)::integer),
      'max_sequence',max(right(application_reference,4)::integer)
    )
    from public.quote_requests
    where id in (${requestIds.map((id)=>`'${id}'`).join(",")});
  `);
  const parsed = JSON.parse(summary);
  if (parsed.count !== fixtureCount || parsed.unique_count !== fixtureCount || parsed.format_count !== fixtureCount) {
    throw new Error(`CONCURRENT_REFERENCE_UNIQUENESS_INVALID:${summary}`);
  }
  if (parsed.year_count !== 1 || parsed.max_sequence - parsed.min_sequence !== fixtureCount - 1) {
    throw new Error(`CONCURRENT_REFERENCE_MONOTONICITY_INVALID:${summary}`);
  }

  process.stdout.write(JSON.stringify({ test_context: "LOCAL_TEST_ONLY", concurrent_submissions: fixtureCount, ...parsed }) + "\n");
}).catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});