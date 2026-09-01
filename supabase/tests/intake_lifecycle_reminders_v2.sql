begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, lws_internal, extensions;
select no_plan();

create temp table lifecycle_test_clock as select clock_timestamp() as value;

select has_function(
  'lws_internal', 'intake_lifecycle_phase_is_due_v2',
  array['text', 'timestamptz', 'timestamptz'],
  'four-phase lifecycle policy exists'
);
select has_function(
  'public', 'list_intake_lifecycle_candidates_v2',
  array['text', 'timestamptz', 'integer'],
  'unified Website and SDF candidate projection exists'
);
select has_function(
  'public', 'claim_intake_lifecycle_email_job_v2', array['uuid'],
  'lifecycle email delivery claim exists'
);
select has_function(
  'public', 'complete_intake_lifecycle_email_job_v2',
  array['uuid', 'uuid', 'boolean', 'boolean', 'text', 'text'],
  'lifecycle email completion exists'
);
select ok(
  has_function_privilege('service_role', 'public.list_intake_lifecycle_candidates_v2(text,timestamptz,integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.list_intake_lifecycle_candidates_v2(text,timestamptz,integer)', 'execute')
  and not has_function_privilege('anon', 'public.claim_intake_lifecycle_email_job_v2(uuid)', 'execute'),
  'lifecycle authorities remain service-only'
);

select is(
  public.quote_request_intake_default_expires_at_v1('2030-01-01 12:00:00+00'),
  '2030-01-15 12:00:00+00'::timestamptz,
  'new Website intake links remain valid for 14 days'
);
select ok(
  not lws_internal.intake_lifecycle_phase_is_due_v2('REMINDER_1', '2030-01-04 11:59:59+00', '2030-01-01 12:00:00+00')
  and lws_internal.intake_lifecycle_phase_is_due_v2('REMINDER_1', '2030-01-04 12:00:00+00', '2030-01-01 12:00:00+00'),
  'REMINDER_1 starts on day 3'
);
select ok(
  not lws_internal.intake_lifecycle_phase_is_due_v2('REMINDER_2', '2030-01-08 11:59:59+00', '2030-01-01 12:00:00+00')
  and lws_internal.intake_lifecycle_phase_is_due_v2('REMINDER_2', '2030-01-08 12:00:00+00', '2030-01-01 12:00:00+00'),
  'REMINDER_2 starts on day 7'
);
select ok(
  not lws_internal.intake_lifecycle_phase_is_due_v2('FINAL_WARNING', '2030-01-14 11:59:59+00', '2030-01-01 12:00:00+00')
  and lws_internal.intake_lifecycle_phase_is_due_v2('FINAL_WARNING', '2030-01-14 12:00:00+00', '2030-01-01 12:00:00+00'),
  'FINAL_WARNING starts on day 13'
);
select ok(
  not lws_internal.intake_lifecycle_phase_is_due_v2('EXPIRY', '2030-01-15 11:59:59+00', '2030-01-01 12:00:00+00')
  and lws_internal.intake_lifecycle_phase_is_due_v2('EXPIRY', '2030-01-15 12:00:00+00', '2030-01-01 12:00:00+00'),
  'EXPIRY starts on day 14'
);

insert into public.quote_requests (
  id, record_classification, request_kind, name, email, website_type,
  budget, timing, description, privacy_consent, status
) values
  ('ec100001-0000-4000-8000-000000000001', 'production', 'website', 'Website Lifecycle', 'website-lifecycle@example.test', 'business', 'EUR 3.000', 'flexible', 'Lifecycle fixture.', true, 'approved'),
  ('ec100003-0000-4000-8000-000000000003', 'production', 'website', 'Submitted Lifecycle', 'submitted-lifecycle@example.test', 'business', 'EUR 3.000', 'flexible', 'Lifecycle fixture.', true, 'approved');

insert into public.quote_requests (
  id, record_classification, request_kind, sdf_package, name, email,
  description, privacy_consent, status, approval_token_hash, approval_token_expires_at
) values (
  'ec100002-0000-4000-8000-000000000002', 'production', 'slimme_documentenflow', 'groei',
  'SDF Lifecycle', 'sdf-lifecycle@example.test', 'Lifecycle fixture.', true, 'approved',
  repeat('9', 64), (select value + interval '1 day' from lifecycle_test_clock)
);

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_state, lifecycle_revision, started_at, submitted_at, confirmation, created_at
) values
  ('ec200001-0000-4000-8000-000000000001', 'ec100001-0000-4000-8000-000000000001', 'invited', repeat('1', 64), (select value + interval '11 days' from lifecycle_test_clock), 'ACTIVE', 0, null, null, false, (select value - interval '3 days' from lifecycle_test_clock)),
  ('ec200003-0000-4000-8000-000000000003', 'ec100003-0000-4000-8000-000000000003', 'submitted', repeat('3', 64), (select value + interval '11 days' from lifecycle_test_clock), 'ACTIVE', 0, (select value - interval '2 days' from lifecycle_test_clock), (select value - interval '1 day' from lifecycle_test_clock), true, (select value - interval '3 days' from lifecycle_test_clock));

insert into public.sdf_qualification_intakes (
  intake_id, quote_request_id, status, customer_capability_digest,
  customer_capability_encrypted, customer_capability_expires_at, invited_at, created_at
) values (
  'ec200002-0000-4000-8000-000000000002', 'ec100002-0000-4000-8000-000000000002', 'invited', repeat('2', 64),
  'v1.aaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  (select value + interval '11 days' from lifecycle_test_clock),
  (select value - interval '3 days' from lifecycle_test_clock),
  (select value - interval '3 days' from lifecycle_test_clock)
);

insert into lws_internal.intake_reminder_capability_escrow (
  intake_id, access_cycle, encrypted_capability
) values (
  'ec200001-0000-4000-8000-000000000001', 0,
  'v1.aaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
);

select ok(
  exists(select 1 from public.list_intake_lifecycle_candidates_v2('REMINDER_1', (select value from lifecycle_test_clock), 100)
    where intake_id = 'ec200001-0000-4000-8000-000000000001' and request_kind = 'website')
  and exists(select 1 from public.list_intake_lifecycle_candidates_v2('REMINDER_1', (select value from lifecycle_test_clock), 100)
    where intake_id = 'ec200002-0000-4000-8000-000000000002' and request_kind = 'slimme_documentenflow'),
  'day-3 candidates include Website and SDF'
);
select ok(
  exists(select 1 from public.list_intake_lifecycle_candidates_v2('EXPIRY', (select value + interval '11 days' from lifecycle_test_clock), 100)
    where intake_id = 'ec200001-0000-4000-8000-000000000001')
  and exists(select 1 from public.list_intake_lifecycle_candidates_v2('EXPIRY', (select value + interval '11 days' from lifecycle_test_clock), 100)
    where intake_id = 'ec200002-0000-4000-8000-000000000002'),
  'day-14 expiry candidates retain both intake histories'
);
select is(
  (select count(*)::integer from public.list_intake_lifecycle_candidates_v2('REMINDER_1', (select value from lifecycle_test_clock), 100)
    where intake_id = 'ec200003-0000-4000-8000-000000000003'),
  0,
  'submitted intake receives no reminder'
);

create temp table website_claim as
select * from public.claim_intake_lifecycle_reminder_v2(
  'website', 'ec200001-0000-4000-8000-000000000001', 0,
  'REMINDER_1', (select value from lifecycle_test_clock)
);
create temp table website_job as
select * from public.prepare_intake_lifecycle_email_job_v2(
  'website', 'ec200001-0000-4000-8000-000000000001', 0,
  'REMINDER_1', (select claim_token from website_claim), (select value from lifecycle_test_clock)
);
select ok(
  exists(select 1 from website_job where outcome = 'prepared')
  and exists(select 1 from website_job job
    cross join lateral public.get_intake_lifecycle_email_delivery_v2(job.email_job_id, (select value from lifecycle_test_clock)) delivery
    where delivery.encrypted_token is not null),
  'Website reminder survives claim, preparation, and final recheck'
);
create temp table website_delivery_claim as
select * from website_job job
cross join lateral public.claim_intake_lifecycle_email_job_v2(job.email_job_id);
select is(
  public.complete_intake_lifecycle_email_job_v2(
    (select email_job_id from website_job),
    (select delivery_lease_token from website_delivery_claim),
    true, false, null, 'provider-lifecycle-test'
  )->>'status',
  'sent',
  'successful lifecycle delivery completes the leased job'
);
select ok(
  exists(select 1 from lws_internal.intake_lifecycle_evidence_v2
    where intake_id = 'ec200001-0000-4000-8000-000000000001'
      and reminder_phase = 'REMINDER_1' and state = 'SENT')
  and exists(select 1 from public.intake_lifecycle_email_jobs_v2
    where job_id = (select email_job_id from website_job)
      and status = 'sent' and encrypted_capability is null),
  'completion finalizes evidence and clears capability ciphertext'
);

create temp table sdf_expiry_claim as
select * from public.claim_intake_lifecycle_reminder_v2(
  'slimme_documentenflow', 'ec200002-0000-4000-8000-000000000002', 1,
  'EXPIRY', (select value + interval '11 days' from lifecycle_test_clock)
);
create temp table sdf_expiry_job as
select * from public.prepare_intake_lifecycle_email_job_v2(
  'slimme_documentenflow', 'ec200002-0000-4000-8000-000000000002', 1,
  'EXPIRY', (select claim_token from sdf_expiry_claim), (select value + interval '11 days' from lifecycle_test_clock)
);
select ok(
  exists(select 1 from sdf_expiry_job where outcome = 'prepared')
  and exists(select 1 from sdf_expiry_job job
    cross join lateral public.get_intake_lifecycle_email_delivery_v2(job.email_job_id, (select value + interval '11 days' from lifecycle_test_clock)) delivery
    where delivery.encrypted_token is null),
  'SDF expiry survives final recheck without capability material'
);
select ok(
  not lws_internal.intake_lifecycle_is_eligible_v2(
    'website', 'ec299999-0000-4000-8000-000000000099', 0,
    'REMINDER_1', (select value from lifecycle_test_clock)
  ),
  'deleted intake identity cannot remain reminder-eligible'
);

update public.sdf_qualification_intakes
set customer_capability_revoked_at = (select value from lifecycle_test_clock)
where intake_id = 'ec200002-0000-4000-8000-000000000002';
select ok(
  not lws_internal.intake_lifecycle_is_eligible_v2(
    'slimme_documentenflow', 'ec200002-0000-4000-8000-000000000002', 1,
    'REMINDER_1', (select value from lifecycle_test_clock)
  ),
  'revoked SDF capability suppresses reminders'
);
update public.sdf_qualification_intakes
set customer_capability_revoked_at = null
where intake_id = 'ec200002-0000-4000-8000-000000000002';

select is(
  (select count(*)::integer
   from public.list_intake_lifecycle_candidates_v2(
     'REMINDER_1', (select value + interval '11 days' from lifecycle_test_clock), 100
   )
   where intake_id in (
     'ec200001-0000-4000-8000-000000000001',
     'ec200002-0000-4000-8000-000000000002'
   )),
  0,
  'expired Website and SDF intakes receive no further reminder'
);

update public.quote_request_intakes
set created_at = clock_timestamp() - interval '15 days',
    access_token_expires_at = clock_timestamp() - interval '1 second'
where id = 'ec200001-0000-4000-8000-000000000001';
update public.sdf_qualification_intakes
set created_at = clock_timestamp() - interval '15 days',
    invited_at = clock_timestamp() - interval '15 days',
    customer_capability_expires_at = clock_timestamp() - interval '1 second'
where intake_id = 'ec200002-0000-4000-8000-000000000002';

select throws_ok(
  $$select public.inspect_quote_request_intake(repeat('1', 64))$$,
  'P0001',
  'INTAKE_ACCESS_EXPIRED',
  'Website capability is unusable at day 14'
);
select throws_ok(
  $$select public.inspect_sdf_qualification_intake_v1(repeat('2', 64))$$,
  '42501',
  'SDF_INTAKE_ACCESS_DENIED',
  'SDF capability is unusable at day 14'
);

select * from finish();
rollback;
