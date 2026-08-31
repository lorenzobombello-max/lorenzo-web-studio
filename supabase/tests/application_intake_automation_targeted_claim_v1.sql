begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(20);

select has_function(
  'public',
  'claim_application_intake_automation_work_by_id_v1',
  array['uuid', 'bigint'],
  'targeted work claim RPC exists'
);
select has_function(
  'public',
  'claim_application_intake_automation_work_v1',
  array['uuid', 'integer'],
  'global work claim RPC remains signature-compatible'
);
select ok(
  has_function_privilege('service_role', 'public.claim_application_intake_automation_work_by_id_v1(uuid,bigint)', 'execute'),
  'service role can execute the targeted claim RPC'
);
select ok(
  not has_function_privilege('anon', 'public.claim_application_intake_automation_work_by_id_v1(uuid,bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.claim_application_intake_automation_work_by_id_v1(uuid,bigint)', 'execute')
  and not has_function_privilege('public', 'public.claim_application_intake_automation_work_by_id_v1(uuid,bigint)', 'execute'),
  'targeted claim RPC is unavailable to anon authenticated and PUBLIC'
);
select ok(
  not has_function_privilege('service_role', 'lws_internal.claim_application_intake_automation_work_internal_v1(uuid,integer,bigint)', 'execute'),
  'canonical internal claim implementation is not directly executable by service role'
);

select lives_ok(
  $test$do $fixture$
    begin
      if not (select active from lws_internal.application_intake_automation_config where singleton) then
        perform public.activate_application_intake_automation_v1('TARGETED-CLAIM-V1-TEST');
      end if;
    end
  $fixture$;$test$,
  'automation is active for the targeted claim fixture'
);
update lws_internal.application_intake_automation_config
set cutover_at = fixture.activated_at,
    activated_at = fixture.activated_at
from (select clock_timestamp() - interval '1 hour' as activated_at) as fixture
where singleton;

insert into public.quote_requests (
  id, request_kind, created_at, name, email, website_type, budget, timing, description,
  privacy_consent, status, record_classification,
  approval_token_hash, approval_token_expires_at
) values
  (
    'e1200001-0000-4000-8000-000000000001', 'website', clock_timestamp() - interval '10 minutes',
    'Targeted claim first', 'targeted-first@example.test', 'business', 'Meer dan EUR 6.000', 'flexible',
    'Targeted claim first fixture',
    true, 'pending', 'production', repeat('1', 64), clock_timestamp() + interval '1 day'
  ),
  (
    'e1200002-0000-4000-8000-000000000002', 'website', clock_timestamp() - interval '9 minutes',
    'Targeted claim target', 'targeted-target@example.test', 'business', 'Meer dan EUR 6.000', 'flexible',
    'Targeted claim target fixture',
    true, 'pending', 'production', repeat('2', 64), clock_timestamp() + interval '1 day'
  ),
  (
    'e1200003-0000-4000-8000-000000000003', 'website', clock_timestamp() - interval '8 minutes',
    'Targeted claim leased', 'targeted-leased@example.test', 'business', 'Meer dan EUR 6.000', 'flexible',
    'Targeted claim leased fixture',
    true, 'pending', 'production', repeat('3', 64), clock_timestamp() + interval '1 day'
  );

create temporary table target_ids as
select quote_request_id, work_id
from lws_internal.application_intake_automation_work
where quote_request_id in (
  'e1200001-0000-4000-8000-000000000001',
  'e1200002-0000-4000-8000-000000000002',
  'e1200003-0000-4000-8000-000000000003'
);

create temporary table targeted_claim as
select *
from public.claim_application_intake_automation_work_by_id_v1(
  'e1210000-0000-4000-8000-000000000001',
  (select work_id from target_ids where quote_request_id = 'e1200002-0000-4000-8000-000000000002')
);

select is((select count(*)::integer from targeted_claim), 1, 'eligible target returns exactly one claim');
select is(
  (select quote_request_id from targeted_claim),
  'e1200002-0000-4000-8000-000000000002'::uuid,
  'targeted claim returns only the requested work item'
);
select is((select phase from targeted_claim), 'APPROVAL', 'targeted claim preserves the canonical phase');
select ok((select claim_token is not null from targeted_claim), 'targeted claim creates a claim token');
select ok(
  (select claim_expires_at between clock_timestamp() + interval '85 seconds' and clock_timestamp() + interval '90 seconds' from targeted_claim),
  'targeted claim creates the canonical 90-second lease'
);
select is(
  (select attempt_count from lws_internal.application_intake_automation_work where quote_request_id = 'e1200002-0000-4000-8000-000000000002'),
  1,
  'targeted claim increments attempt count once'
);
select is(
  (select count(*)::integer from lws_internal.application_intake_automation_work where quote_request_id = 'e1200001-0000-4000-8000-000000000001' and claim_token is null and attempt_count = 0),
  1,
  'targeted claim leaves an earlier unrelated eligible row untouched'
);
select is(
  (select count(*)::integer from public.claim_application_intake_automation_work_by_id_v1(
    'e1210000-0000-4000-8000-000000000002',
    (select work_id from target_ids where quote_request_id = 'e1200002-0000-4000-8000-000000000002')
  )),
  0,
  'an actively leased target cannot be claimed again'
);
select is(
  (select count(*)::integer from public.claim_application_intake_automation_work_by_id_v1(
    'e1210000-0000-4000-8000-000000000003',
    9223372036854775807
  )),
  0,
  'an unknown target returns no claim'
);

update lws_internal.application_intake_automation_work
set claim_token = 'e1220000-0000-4000-8000-000000000003',
    claimed_by = 'e1210000-0000-4000-8000-000000000003',
    claimed_at = clock_timestamp(),
    claim_expires_at = clock_timestamp() + interval '5 minutes'
where quote_request_id = 'e1200003-0000-4000-8000-000000000003';

select is(
  (select count(*)::integer from public.claim_application_intake_automation_work_by_id_v1(
    'e1210000-0000-4000-8000-000000000004',
    (select work_id from target_ids where quote_request_id = 'e1200003-0000-4000-8000-000000000003')
  )),
  0,
  'a pre-existing active lease remains exclusive'
);

create temporary table global_claim as
select *
from public.claim_application_intake_automation_work_v1(
  'e1210000-0000-4000-8000-000000000005',
  5
);
select is((select count(*)::integer from global_claim), 1, 'global wrapper still claims remaining eligible work');
select is(
  (select quote_request_id from global_claim),
  'e1200001-0000-4000-8000-000000000001'::uuid,
  'global wrapper preserves FIFO eligibility behavior'
);
select throws_ok(
  $$select * from public.claim_application_intake_automation_work_by_id_v1('e1210000-0000-4000-8000-000000000006', null)$$,
  '22023',
  'INVALID_AUTOMATION_WORK_ID',
  'null target fails closed'
);
select throws_ok(
  $$select * from public.claim_application_intake_automation_work_by_id_v1(null, 1)$$,
  '22023',
  'INVALID_AUTOMATION_WORKER_ID',
  'null worker fails closed through the canonical implementation'
);

select * from finish();
rollback;
