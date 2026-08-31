begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(29);

select has_function(
  'lws_internal',
  'ensure_sdf_qualification_intake_invited_v1',
  array['uuid','text','text','uuid','text','text','uuid','boolean'],
  'internal SDF invitation domain authority exists'
);
select ok(
  not has_function_privilege('service_role', 'lws_internal.ensure_sdf_qualification_intake_invited_v1(uuid,text,text,uuid,text,text,uuid,boolean)', 'execute'),
  'service role cannot call the internal domain authority directly'
);
select ok(
  has_function_privilege('service_role', 'public.execute_application_intake_automation_sdf_intake_v1(bigint,uuid,text,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.execute_application_intake_automation_sdf_intake_v1(bigint,uuid,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.execute_application_intake_automation_sdf_intake_v1(bigint,uuid,text,text)', 'execute'),
  'only service role can enter the automatic SDF executor'
);
select hasnt_function(
  'public',
  'execute_application_intake_automation_sdf_intake_v1',
  array['bigint','uuid'],
  'legacy executor without capability material is removed'
);

select public.activate_application_intake_automation_v1('SDF-AUTOMATIC-INTAKE-TEST');
update lws_internal.application_intake_automation_config
set cutover_at = fixture.activated_at,
    activated_at = fixture.activated_at
from (select clock_timestamp() - interval '1 hour' as activated_at) as fixture
where singleton;

insert into public.quote_requests(
  id, request_kind, sdf_package, created_at, name, email, description,
  privacy_consent, status, record_classification, approval_token_hash,
  approval_token_expires_at, confirmation_sent_at
) values
  (
    'f6000000-0000-4000-8000-000000000006', 'slimme_documentenflow', 'start',
    clock_timestamp() - interval '10 minutes', 'Historical work 6 shape',
    'work6@example.test', 'Automatic SDF historical recovery fixture', true,
    'pending', 'production', repeat('6', 64), clock_timestamp() + interval '1 day',
    clock_timestamp() - interval '4 minutes'
  ),
  (
    'f1200000-0000-4000-8000-000000000012', 'slimme_documentenflow', 'groei',
    clock_timestamp() - interval '10 minutes', 'Current work 12 shape',
    'work12@example.test', 'Automatic SDF current recovery fixture', true,
    'pending', 'production', repeat('c', 64), clock_timestamp() + interval '1 day',
    clock_timestamp() - interval '4 minutes'
  );

update lws_internal.application_intake_automation_work as work
set phase = 'SDF_INTAKE',
    approved_at = request.confirmation_sent_at,
    intake_due_at = request.confirmation_sent_at + interval '120 seconds',
    next_attempt_at = request.confirmation_sent_at + interval '120 seconds'
from public.quote_requests as request
where request.id = work.quote_request_id
  and request.id in (
    'f6000000-0000-4000-8000-000000000006',
    'f1200000-0000-4000-8000-000000000012'
  );

select is(
  (select count(*)::integer from public.sdf_qualification_intakes where quote_request_id in ('f6000000-0000-4000-8000-000000000006','f1200000-0000-4000-8000-000000000012')),
  0,
  'work-6 and work-12 shaped fixtures start without an intake'
);
select is(
  (select count(*)::integer from public.sdf_qualification_intake_email_jobs),
  0,
  'work-6 and work-12 shaped fixtures start without an invitation job'
);

create temporary table automatic_claims as
select *
from public.claim_application_intake_automation_work_v1(
  'f0000000-0000-4000-8000-000000000001',
  5
);

select is((select count(*)::integer from automatic_claims), 2, 'both due SDF states are claimable without an existing intake');
select is((select count(*)::integer from automatic_claims where phase = 'SDF_INTAKE'), 2, 'both claims retain the SDF intake phase');

create temporary table automatic_results as
select
  claim.work_id,
  claim.quote_request_id,
  public.execute_application_intake_automation_sdf_intake_v1(
    claim.work_id,
    claim.claim_token,
    case when claim.quote_request_id = 'f6000000-0000-4000-8000-000000000006' then repeat('6', 64) else repeat('c', 64) end,
    case when claim.quote_request_id = 'f6000000-0000-4000-8000-000000000006'
      then 'v1.FFFFFFFFFFFFFFFF.FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'
      else 'v1.CCCCCCCCCCCCCCCC.CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC'
    end
  ) as result
from automatic_claims as claim;

select is((select count(*)::integer from automatic_results where result->>'outcome' = 'invitation_pending'), 2, 'automatic execution prepares both invitation authorities');
select is((select count(*)::integer from public.sdf_qualification_intakes), 2, 'automatic execution creates exactly one intake per request');
select is((select count(*)::integer from public.sdf_qualification_intake_events where event_kind = 'INVITED'), 2, 'automatic execution creates exactly one invited event per request');
select is((select count(*)::integer from public.sdf_qualification_intake_email_jobs where kind = 'invitation'), 2, 'automatic execution creates exactly one invitation job per request');
select is((select count(*)::integer from public.sdf_qualification_intake_events where event_kind = 'INVITED' and actor_class = 'system' and actor_operator_id is null), 2, 'automatic invitation audit uses system actor with no fake operator');
select is((select count(*)::integer from public.sdf_qualification_intake_events where actor_class = 'operator'), 0, 'automatic invitation audit attributes no Owner or operator');
select is((select count(distinct result->>'job_id')::integer from automatic_results), 2, 'each request receives one stable provider job identity');

create temporary table replay_results as
select
  result.quote_request_id,
  public.execute_application_intake_automation_sdf_intake_v1(
    result.work_id,
    claim.claim_token,
    repeat('d', 64),
    'v1.DDDDDDDDDDDDDDDD.DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD'
  ) as replay
from automatic_results as result
join automatic_claims as claim using (work_id, quote_request_id);

select is((select count(*)::integer from public.sdf_qualification_intakes), 2, 'same-claim execution creates no duplicate intake');
select is((select count(*)::integer from public.sdf_qualification_intake_events where event_kind = 'INVITED'), 2, 'same-claim execution creates no duplicate event');
select is((select count(*)::integer from public.sdf_qualification_intake_email_jobs where kind = 'invitation'), 2, 'same-claim execution creates no duplicate invitation job');
select is(
  (select count(*)::integer from replay_results replay join automatic_results original using (quote_request_id) where replay.replay->>'job_id' = original.result->>'job_id'),
  2,
  'same-claim execution reuses the stable provider job identity'
);

create temporary table delivery_claims as
select result.quote_request_id, claimed.*
from automatic_results as result
cross join lateral public.claim_sdf_qualification_email_job_v1((result.result->>'job_id')::uuid) as claimed;
select is((select count(*)::integer from delivery_claims), 2, 'both automatic invitation jobs enter the existing delivery lease path');

select public.complete_sdf_qualification_email_job_v1(
  job_id,
  delivery_lease_token,
  quote_request_id <> 'f6000000-0000-4000-8000-000000000006',
  true,
  case when quote_request_id = 'f6000000-0000-4000-8000-000000000006' then 'RESEND_HTTP_503' else null end,
  case when quote_request_id = 'f1200000-0000-4000-8000-000000000012' then 'provider-work-12' else null end
)
from delivery_claims;

select is((select job.status::text from public.sdf_qualification_intake_email_jobs job join public.sdf_qualification_intakes intake using (intake_id) where intake.quote_request_id = 'f6000000-0000-4000-8000-000000000006'), 'retry_wait', 'retryable provider failure retains normal retry semantics');
select is((select job.status::text from public.sdf_qualification_intake_email_jobs job join public.sdf_qualification_intakes intake using (intake_id) where intake.quote_request_id = 'f1200000-0000-4000-8000-000000000012'), 'sent', 'successful automatic invitation follows the existing sent completion path');
select is((select phase from lws_internal.application_intake_automation_work where quote_request_id = 'f1200000-0000-4000-8000-000000000012'), 'COMPLETED', 'sent invitation completes SDF automation work');
select is((select count(*)::integer from public.sdf_qualification_intake_email_jobs), 2, 'delivery completion creates no duplicate job');

select is(
  (select count(*)::integer from public.claim_application_intake_automation_work_by_id_v1(
    'f0000000-0000-4000-8000-000000000002',
    (select work_id from lws_internal.application_intake_automation_work where quote_request_id = 'f1200000-0000-4000-8000-000000000012')
  )),
  0,
  'sent SDF work cannot be claimed again'
);

update lws_internal.application_intake_automation_work
set phase = 'SDF_INTAKE',
    attempt_count = 0,
    next_attempt_at = clock_timestamp() - interval '1 minute'
where quote_request_id = 'f1200000-0000-4000-8000-000000000012';
create temporary table stale_sent_claim as
select * from public.claim_application_intake_automation_work_by_id_v1(
  'f0000000-0000-4000-8000-000000000003',
  (select work_id from lws_internal.application_intake_automation_work where quote_request_id = 'f1200000-0000-4000-8000-000000000012')
);
select is((select count(*)::integer from stale_sent_claim), 1, 'stale sent SDF work shape remains reconcilable');
create temporary table stale_sent_result as
select public.execute_application_intake_automation_sdf_intake_v1(
  work_id,
  claim_token,
  repeat('e', 64),
  'v1.EEEEEEEEEEEEEEEE.EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE'
) as result
from stale_sent_claim;
select is((select result->>'outcome' from stale_sent_result), 'already_sent', 'sent job re-execution returns already-sent without provider authority');
select is((select result->>'job_id' from stale_sent_result), (select result->>'job_id' from automatic_results where quote_request_id = 'f1200000-0000-4000-8000-000000000012'), 'sent reconciliation preserves provider semantic job identity');
select is((select phase from lws_internal.application_intake_automation_work where quote_request_id = 'f1200000-0000-4000-8000-000000000012'), 'COMPLETED', 'sent reconciliation restores completed work state');

select * from finish();
rollback;
