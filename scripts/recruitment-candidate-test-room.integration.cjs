const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const { createHash } = require("node:crypto");

const container = "supabase_db_xcsptvntvrizwhskaphr";
const baseArgs = ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At", "-c"];
const ownerUserId = "f9400000-0000-4000-8000-000000000001";
const ownerOperatorId = "f9410000-0000-4000-8000-000000000001";

function execute(sql, expectFailure = false) {
  const result = spawnSync("docker", [...baseArgs, sql], { encoding: "utf8" });
  if (expectFailure) {
    if (result.status === 0) throw new Error(`EXPECTED_SQL_FAILURE:${result.stdout}`);
    return result.stderr;
  }
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout.trim().split(/\r?\n/).filter(Boolean).at(-1) || "";
}

function ownerCall(expression, expectFailure = false) {
  return execute(`set role authenticated; select set_config('request.jwt.claim.sub','${ownerUserId}',false); select ${expression}`, expectFailure);
}

function candidateCall(expression, expectFailure = false) {
  return execute(`set role anon; select ${expression}`, expectFailure);
}

function serviceCall(expression, expectFailure = false) {
  return execute(`set role service_role; select ${expression}`, expectFailure);
}

function cleanup() {
  execute(`
    begin;
    set local session_replication_role = replica;
    delete from public.recruitment_candidate_invitation_email_jobs where assignment_id in (
      select assignment_id from public.recruitment_test_assignments where assigned_by_operator_id = '${ownerOperatorId}'
    );
    delete from public.recruitment_test_assignment_items where assignment_id in (
      select assignment_id from public.recruitment_test_assignments where assigned_by_operator_id = '${ownerOperatorId}'
    );
    delete from public.recruitment_test_history where assignment_id in (
      select assignment_id from public.recruitment_test_assignments where assigned_by_operator_id = '${ownerOperatorId}'
    );
    delete from public.recruitment_test_assignments where assigned_by_operator_id = '${ownerOperatorId}';
    delete from public.recruitment_test_candidates where created_by_operator_id = '${ownerOperatorId}';
    delete from public.commercial_operators where operator_id = '${ownerOperatorId}';
    delete from auth.users where id = '${ownerUserId}';
    commit;
    select 'CLEAN';
  `);
}

function main() {
  assert.equal(execute("select current_database()"), "postgres");
  try {
    cleanup();
    execute(`
      insert into auth.users(id,email) values('${ownerUserId}','recruitment-owner@example.test');
      insert into public.commercial_operators(operator_id,auth_user_id,display_name,role,status)
      values('${ownerOperatorId}','${ownerUserId}','Recruitment Test Owner','owner','ACTIVE');
    `);
    assert.match(execute("set role anon; select * from public.recruitment_test_candidates", true), /permission denied/);
    assert.match(execute("set role authenticated; select public.list_owner_recruitment_candidate_tests_v1()", true), /RECRUITMENT_OWNER_REQUIRED/);

    assert.match(ownerCall("public.create_recruitment_test_candidate_v1('Blocked','blocked@example.invalid','Development')", true), /permission denied/);
    const firstToken = "a".repeat(64);
    const secondToken = "b".repeat(64);
    const firstDigest = createHash("sha256").update(firstToken).digest("hex");
    const secondDigest = createHash("sha256").update(secondToken).digest("hex");
    const encryptedOne = `v1.${"A".repeat(16)}.${"A".repeat(107)}`;
    const encryptedTwo = `v1.${"B".repeat(16)}.${"B".repeat(107)}`;
    const firstAssignment = JSON.parse(serviceCall(`public.create_recruitment_candidate_invitation_v2('${ownerUserId}','Synthetic Ada','ada@example.invalid','Development','${firstDigest}','${encryptedOne}')`));
    const secondAssignment = JSON.parse(serviceCall(`public.create_recruitment_candidate_invitation_v2('${ownerUserId}','Synthetic Noor','noor@example.invalid','Security','${secondDigest}','${encryptedTwo}')`));
    assert.equal(firstAssignment.status, "BESCHIKBAAR");
    assert.ok([4, 5].includes(firstAssignment.selection_count));
    assert.ok([4, 5].includes(secondAssignment.selection_count));

    const firstClaim = JSON.parse(serviceCall(`public.claim_recruitment_candidate_invitation_email_v2('${firstAssignment.job_id}')`));
    assert.equal(firstClaim.outcome, "claimed");
    assert.equal(firstClaim.selection_count, firstAssignment.selection_count);
    assert.equal(JSON.parse(serviceCall(`public.complete_recruitment_candidate_invitation_email_v2('${firstAssignment.job_id}','${firstClaim.delivery_lease_token}',true,false,null,'local-message-1')`)).status, "sent");
    const secondClaim = JSON.parse(serviceCall(`public.claim_recruitment_candidate_invitation_email_v2('${secondAssignment.job_id}')`));
    assert.equal(JSON.parse(serviceCall(`public.complete_recruitment_candidate_invitation_email_v2('${secondAssignment.job_id}','${secondClaim.delivery_lease_token}',true,false,null,'local-message-2')`)).status, "sent");

    const firstOpen = JSON.parse(candidateCall(`public.get_recruitment_candidate_test_v1('${firstToken}')`));
    const secondOpen = JSON.parse(candidateCall(`public.get_recruitment_candidate_test_v1('${secondToken}')`));
    assert.equal(firstOpen.candidate_id, firstAssignment.candidate_id);
    assert.equal(secondOpen.candidate_id, secondAssignment.candidate_id);
    assert.equal(firstOpen.tests.length, firstAssignment.selection_count);
    assert.equal(secondOpen.tests.length, secondAssignment.selection_count);
    assert.ok(firstOpen.tests.every((test)=>test.test_code.startsWith("TEST-DEV-")));
    assert.ok(secondOpen.tests.every((test)=>test.test_code.startsWith("TEST-SEC-")));
    assert.match(candidateCall(`public.get_recruitment_candidate_test_v1('${"0".repeat(64)}')`, true), /RECRUITMENT_CANDIDATE_ACCESS_DENIED/);
    assert.match(execute("set role anon; select * from public.recruitment_test_assignment_items", true), /permission denied/);

    const selectionBefore = JSON.stringify(firstOpen.tests.map((test)=>test.test_code));
    const selectionAfter = JSON.stringify(JSON.parse(candidateCall(`public.get_recruitment_candidate_test_v1('${firstToken}')`)).tests.map((test)=>test.test_code));
    assert.equal(selectionAfter, selectionBefore);
    assert.match(execute(`update public.recruitment_test_assignment_items set position=position where assignment_id='${firstAssignment.assignment_id}'`, true), /RECRUITMENT_TEST_SELECTION_IMMUTABLE/);

    const draft = { [`${firstOpen.tests[0].test_code}__approach`]: "Synthetisch conceptantwoord." };
    const completeAnswers = Object.fromEntries(firstOpen.tests.map((test)=>[`${test.test_code}__approach`, `Synthetisch antwoord voor ${test.title}.`]));
    assert.equal(JSON.parse(candidateCall(`public.save_recruitment_candidate_test_v1('${firstToken}','${JSON.stringify(draft)}')`)).status, "BEZIG");
    assert.match(candidateCall(`public.submit_recruitment_candidate_test_v1('${firstToken}','${JSON.stringify(draft)}')`, true), /RECRUITMENT_TEST_ANSWERS_INCOMPLETE/);
    assert.equal(JSON.parse(candidateCall(`public.submit_recruitment_candidate_test_v1('${firstToken}','${JSON.stringify(completeAnswers)}')`)).status, "INGEDIEND");
    assert.match(candidateCall(`public.save_recruitment_candidate_test_v1('${firstToken}','${JSON.stringify(draft)}')`, true), /RECRUITMENT_TEST_NOT_EDITABLE/);

    const ownerRows = JSON.parse(ownerCall("public.list_owner_recruitment_candidate_tests_v1()"));
    const ownerResult = ownerRows.find((item)=>item.assignment_id === firstAssignment.assignment_id);
    assert.deepEqual(ownerResult.submitted_answers, completeAnswers);
    assert.equal(ownerResult.invitation_status, "sent");
    assert.equal(ownerResult.selected_tests.length, firstAssignment.selection_count);
    assert.deepEqual(ownerResult.history.map((event)=>event.to_status), ["GEPLAND", "BESCHIKBAAR", "BEZIG", "INGEDIEND"]);
    assert.equal(JSON.parse(ownerCall(`public.review_recruitment_candidate_test_v1('${firstAssignment.assignment_id}','Geschikt voor vervolggesprek.')`)).status, "BEOORDEELD");
    assert.match(execute(`update public.recruitment_test_history set actor_type='OWNER' where assignment_id='${firstAssignment.assignment_id}'`, true), /RECRUITMENT_TEST_HISTORY_APPEND_ONLY/);

    const reviewed = JSON.parse(ownerCall("public.list_owner_recruitment_candidate_tests_v1()"))
      .find((item)=>item.assignment_id === firstAssignment.assignment_id);
    assert.equal(reviewed.assignment_status, "BEOORDEELD");
    assert.equal(reviewed.review_notes, "Geschikt voor vervolggesprek.");
    assert.deepEqual(reviewed.history.map((event)=>event.to_status), ["GEPLAND", "BESCHIKBAAR", "BEZIG", "INGEDIEND", "BEOORDEELD"]);
    process.stdout.write(JSON.stringify({ context: "LOCAL_TEST_ONLY", candidates: 2, profile_banks: true, selection_count: [firstAssignment.selection_count, secondAssignment.selection_count], selection_stable: true, invitation_sent: true, isolation: true, draft: true, immutable_after_submit: true, history_append_only: true, final_status: reviewed.assignment_status }));
  } finally {
    cleanup();
  }
}

main();