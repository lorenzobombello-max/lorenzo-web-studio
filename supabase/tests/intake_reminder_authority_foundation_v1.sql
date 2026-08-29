begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, lws_internal, extensions;
select no_plan();

select has_table('lws_internal', 'intake_reminder_evidence', 'private reminder evidence authority exists');
select has_function('public', 'list_intake_reminder_candidates_v1', array['text','timestamptz','integer'], 'candidate projection exists');
select has_function('public', 'claim_intake_reminder_v1', array['uuid','text','timestamptz'], 'atomic reminder claim exists');
select has_function('public', 'mark_intake_reminder_sent_v1', array['uuid','bigint','text','uuid','uuid'], 'sent evidence transition exists');
select has_function('lws_internal', 'resolve_intake_reminder_access_cycle_v1', array['uuid'], 'access-cycle resolver exists');

select ok(
  has_function_privilege('service_role', 'public.list_intake_reminder_candidates_v1(text,timestamptz,integer)', 'execute')
  and has_function_privilege('service_role', 'public.claim_intake_reminder_v1(uuid,text,timestamptz)', 'execute')
  and has_function_privilege('service_role', 'public.mark_intake_reminder_sent_v1(uuid,bigint,text,uuid,uuid)', 'execute'),
  'service role can enter reminder authority RPCs'
);
select ok(
  not has_function_privilege('anon', 'public.list_intake_reminder_candidates_v1(text,timestamptz,integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.list_intake_reminder_candidates_v1(text,timestamptz,integer)', 'execute')
  and not has_function_privilege('anon', 'public.claim_intake_reminder_v1(uuid,text,timestamptz)', 'execute')
  and not has_function_privilege('authenticated', 'public.claim_intake_reminder_v1(uuid,text,timestamptz)', 'execute')
  and not has_function_privilege('anon', 'public.mark_intake_reminder_sent_v1(uuid,bigint,text,uuid,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.mark_intake_reminder_sent_v1(uuid,bigint,text,uuid,uuid)', 'execute'),
  'frontend roles cannot enter reminder authority RPCs'
);
select ok(
  not has_table_privilege('service_role', 'lws_internal.intake_reminder_evidence', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'lws_internal.intake_reminder_evidence', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'lws_internal.intake_reminder_evidence', 'select,insert,update,delete'),
  'runtime roles cannot mutate reminder evidence directly'
);
select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class where oid = 'lws_internal.intake_reminder_evidence'::regclass),
  'reminder evidence has forced RLS'
);
select is(
  (select pg_get_function_result('public.list_intake_reminder_candidates_v1(text,timestamptz,integer)'::regprocedure)
    !~* 'access_token|encrypted|secret|email'),
  true,
  'candidate projection exposes no customer capability, secret, or email address'
);

insert into auth.users (id, email) values
  ('fa000000-0000-4000-8000-000000000001', 'reminder-owner@example.test');

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values (
  'fa010000-0000-4000-8000-000000000001',
  'fa000000-0000-4000-8000-000000000001',
  'Reminder Owner', 'owner', 'ACTIVE'
);

insert into public.quote_requests (
  id, record_classification, request_kind, name, email, website_type,
  budget, timing, description, privacy_consent, status
) values
  ('fa100001-0000-4000-8000-000000000001', 'production', 'website', 'Invited Active', 'invited@example.test', 'business', 'EUR 3.000', 'flexible', 'Reminder fixture.', true, 'approved'),
  ('fa100002-0000-4000-8000-000000000002', 'production', 'website', 'In Progress Active', 'progress@example.test', 'business', 'EUR 3.000', 'flexible', 'Reminder fixture.', true, 'approved'),
  ('fa100003-0000-4000-8000-000000000003', 'production', 'website', 'Submitted', 'submitted@example.test', 'business', 'EUR 3.000', 'flexible', 'Reminder fixture.', true, 'approved'),
  ('fa100004-0000-4000-8000-000000000004', 'production', 'website', 'Reviewed', 'reviewed@example.test', 'business', 'EUR 3.000', 'flexible', 'Reminder fixture.', true, 'approved'),
  ('fa100005-0000-4000-8000-000000000005', 'production', 'website', 'Cancelled', 'cancelled@example.test', 'business', 'EUR 3.000', 'flexible', 'Reminder fixture.', true, 'approved'),
  ('fa100006-0000-4000-8000-000000000006', 'production', 'website', 'Interrupted', 'interrupted@example.test', 'business', 'EUR 3.000', 'flexible', 'Reminder fixture.', true, 'approved'),
  ('fa100007-0000-4000-8000-000000000007', 'production', 'website', 'Expired', 'expired@example.test', 'business', 'EUR 3.000', 'flexible', 'Reminder fixture.', true, 'approved'),
  ('fa100008-0000-4000-8000-000000000008', 'production', 'website', 'Reactivation', 'reactivation@example.test', 'business', 'EUR 3.000', 'flexible', 'Reminder fixture.', true, 'approved'),
  ('fa100009-0000-4000-8000-000000000009', 'production', 'website', 'Resume', 'resume@example.test', 'business', 'EUR 3.000', 'flexible', 'Reminder fixture.', true, 'approved');

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_state, lifecycle_revision, started_at, submitted_at, reviewed_at,
  confirmation, created_at
) values
  ('fa200000-0000-4000-8000-000000000001', 'fa100001-0000-4000-8000-000000000001', 'invited', repeat('1',64), clock_timestamp() + interval '6 days', 'ACTIVE', 0, null, null, null, false, clock_timestamp() - interval '1 day'),
  ('fa200000-0000-4000-8000-000000000002', 'fa100002-0000-4000-8000-000000000002', 'in_progress', repeat('2',64), clock_timestamp() + interval '6 days', 'ACTIVE', 0, clock_timestamp() - interval '12 hours', null, null, false, clock_timestamp() - interval '1 day'),
  ('fa200000-0000-4000-8000-000000000003', 'fa100003-0000-4000-8000-000000000003', 'submitted', repeat('3',64), clock_timestamp() + interval '6 days', 'ACTIVE', 0, clock_timestamp() - interval '12 hours', clock_timestamp() - interval '1 hour', null, true, clock_timestamp() - interval '1 day'),
  ('fa200000-0000-4000-8000-000000000004', 'fa100004-0000-4000-8000-000000000004', 'reviewed', repeat('4',64), clock_timestamp() + interval '6 days', 'ACTIVE', 0, clock_timestamp() - interval '12 hours', clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour', true, clock_timestamp() - interval '1 day'),
  ('fa200000-0000-4000-8000-000000000005', 'fa100005-0000-4000-8000-000000000005', 'invited', repeat('5',64), clock_timestamp() + interval '6 days', 'CANCELLED', 0, null, null, null, false, clock_timestamp() - interval '1 day'),
  ('fa200000-0000-4000-8000-000000000006', 'fa100006-0000-4000-8000-000000000006', 'in_progress', repeat('6',64), clock_timestamp() + interval '6 days', 'INTERRUPTED', 0, clock_timestamp() - interval '12 hours', null, null, false, clock_timestamp() - interval '1 day'),
  ('fa200000-0000-4000-8000-000000000007', 'fa100007-0000-4000-8000-000000000007', 'invited', repeat('7',64), clock_timestamp() - interval '1 day', 'ACTIVE', 0, null, null, null, false, clock_timestamp() - interval '2 days'),
  ('fa200000-0000-4000-8000-000000000008', 'fa100008-0000-4000-8000-000000000008', 'invited', repeat('8',64), clock_timestamp() - interval '1 day', 'ACTIVE', 0, null, null, null, false, clock_timestamp() - interval '2 days'),
  ('fa200000-0000-4000-8000-000000000009', 'fa100009-0000-4000-8000-000000000009', 'invited', repeat('9',64), clock_timestamp() + interval '6 days', 'ACTIVE', 0, null, null, null, false, clock_timestamp() - interval '1 day');

create temp table email_job_count_before as
select count(*)::bigint as value from public.quote_request_email_jobs;

select ok(
  exists(select 1 from public.list_intake_reminder_candidates_v1('REMINDER_1') where intake_id = 'fa200000-0000-4000-8000-000000000001'),
  'invited ACTIVE intake is eligible'
);
select ok(
  exists(select 1 from public.list_intake_reminder_candidates_v1('REMINDER_1') where intake_id = 'fa200000-0000-4000-8000-000000000002' and started_at is not null),
  'in-progress ACTIVE intake is eligible with started timestamp'
);
select ok(
  not exists(select 1 from public.list_intake_reminder_candidates_v1('REMINDER_1') where intake_id = 'fa200000-0000-4000-8000-000000000003'),
  'submitted intake is excluded'
);
select ok(
  not exists(select 1 from public.list_intake_reminder_candidates_v1('REMINDER_1') where intake_id = 'fa200000-0000-4000-8000-000000000004'),
  'reviewed intake is excluded'
);
select ok(
  not exists(select 1 from public.list_intake_reminder_candidates_v1('REMINDER_1') where intake_id = 'fa200000-0000-4000-8000-000000000005'),
  'cancelled intake is excluded'
);
select ok(
  not exists(select 1 from public.list_intake_reminder_candidates_v1('REMINDER_1') where intake_id = 'fa200000-0000-4000-8000-000000000006'),
  'interrupted intake is excluded'
);
select ok(
  not exists(select 1 from public.list_intake_reminder_candidates_v1('REMINDER_1') where intake_id = 'fa200000-0000-4000-8000-000000000007'),
  'expired intake is excluded'
);
select ok(
  exists(select 1 from public.list_intake_reminder_candidates_v1('REMINDER_2') where intake_id = 'fa200000-0000-4000-8000-000000000001'),
  'REMINDER_1 and REMINDER_2 are independent candidate identities'
);

create temp table reminder_one_claim as
select * from public.claim_intake_reminder_v1(
  'fa200000-0000-4000-8000-000000000001', 'REMINDER_1'
);

select is((select access_cycle from reminder_one_claim), 0::bigint, 'initial invitation is access cycle zero');
select is(
  (select count(*)::integer from public.claim_intake_reminder_v1(
    'fa200000-0000-4000-8000-000000000001', 'REMINDER_1'
  )),
  0,
  'same-cycle duplicate claim is rejected while lease is active'
);
select ok(
  public.mark_intake_reminder_sent_v1(
    'fa200000-0000-4000-8000-000000000001', 0, 'REMINDER_1',
    (select claim_token from reminder_one_claim)
  ),
  'claimed reminder can become definitive sent evidence'
);
select is(
  (select count(*)::integer from public.claim_intake_reminder_v1(
    'fa200000-0000-4000-8000-000000000001', 'REMINDER_1'
  )),
  0,
  'sent evidence permanently blocks another same-cycle claim'
);

create temp table reminder_two_claim as
select * from public.claim_intake_reminder_v1(
  'fa200000-0000-4000-8000-000000000001', 'REMINDER_2'
);
select is((select count(*)::integer from reminder_two_claim), 1, 'REMINDER_2 remains independently claimable');
select is(
  (select count(*)::integer from lws_internal.intake_reminder_evidence
   where intake_id = 'fa200000-0000-4000-8000-000000000001'),
  2,
  'two phases create exactly two evidence identities'
);
select throws_ok(
  $$insert into lws_internal.intake_reminder_evidence (
      intake_id, access_cycle, reminder_phase, cycle_started_at, state,
      claim_token, claimed_at, claim_expires_at
    ) values (
      'fa200000-0000-4000-8000-000000000001', 0, 'REMINDER_1', clock_timestamp(),
      'CLAIMED', gen_random_uuid(), clock_timestamp(), clock_timestamp() + interval '5 minutes'
    )$$,
  '23505', null, 'database primary key rejects duplicate phase evidence'
);
select throws_ok(
  $$update lws_internal.intake_reminder_evidence
    set sent_at = clock_timestamp()
    where intake_id = 'fa200000-0000-4000-8000-000000000001'$$,
  '55000', 'INTAKE_REMINDER_EVIDENCE_IMMUTABLE', 'evidence cannot be mutated outside guarded transitions'
);

create temp table resume_claim as
select * from public.claim_intake_reminder_v1(
  'fa200000-0000-4000-8000-000000000009', 'REMINDER_1'
);
select ok(
  public.mark_intake_reminder_sent_v1(
    'fa200000-0000-4000-8000-000000000009', 0, 'REMINDER_1',
    (select claim_token from resume_claim)
  ),
  'resume fixture has cycle-zero sent evidence'
);

select set_config('request.jwt.claim.sub', 'fa000000-0000-4000-8000-000000000001', true);
select is(
  public.execute_operator_intake_lifecycle_command_v1(
    'fa200000-0000-4000-8000-000000000009', 'INTERRUPTED', 0,
    'fa300000-0000-4000-8000-000000000001', 'Pause before resume'
  )->>'effective_access',
  'INTERRUPTED', 'resume fixture can be interrupted'
);
select is(
  public.execute_operator_intake_lifecycle_command_v1(
    'fa200000-0000-4000-8000-000000000009', 'RESUMED', 1,
    'fa300000-0000-4000-8000-000000000002', 'Resume same access cycle'
  )->>'effective_access',
  'ACTIVE', 'resume restores access'
);
select is(
  (select access_cycle from lws_internal.resolve_intake_reminder_access_cycle_v1('fa200000-0000-4000-8000-000000000009')),
  0::bigint,
  'resume does not create a new reminder cycle'
);
select ok(
  not exists(select 1 from public.list_intake_reminder_candidates_v1('REMINDER_1') where intake_id = 'fa200000-0000-4000-8000-000000000009'),
  'same-cycle evidence remains effective after resume'
);

insert into lws_internal.intake_reminder_evidence (
  intake_id, access_cycle, reminder_phase, cycle_started_at, state,
  claim_token, claimed_at, claim_expires_at, sent_at
) values (
  'fa200000-0000-4000-8000-000000000008', 0, 'REMINDER_1',
  clock_timestamp() - interval '2 days', 'SENT',
  'fa400000-0000-4000-8000-000000000001',
  clock_timestamp() - interval '36 hours', clock_timestamp() - interval '35 hours',
  clock_timestamp() - interval '35 hours'
);
select is(
  (select access_cycle from lws_internal.resolve_intake_reminder_access_cycle_v1('fa200000-0000-4000-8000-000000000008')),
  0::bigint,
  'expired fixture begins in cycle zero'
);
select is(
  public.execute_operator_intake_lifecycle_command_v1(
    'fa200000-0000-4000-8000-000000000008', 'REACTIVATED', 0,
    'fa300000-0000-4000-8000-000000000003', 'Start a fresh access cycle'
  )->>'effective_access',
  'ACTIVE', 'reactivation restores active access'
);
select is(
  (select access_cycle from lws_internal.resolve_intake_reminder_access_cycle_v1('fa200000-0000-4000-8000-000000000008')),
  1::bigint,
  'reactivation creates the next reminder cycle'
);
select ok(
  exists(select 1 from public.list_intake_reminder_candidates_v1('REMINDER_1')
         where intake_id = 'fa200000-0000-4000-8000-000000000008' and access_cycle = 1),
  'old-cycle sent evidence does not block the reactivated cycle'
);
create temp table reactivated_claim as
select * from public.claim_intake_reminder_v1(
  'fa200000-0000-4000-8000-000000000008', 'REMINDER_1'
);
select is((select access_cycle from reactivated_claim), 1::bigint, 'reactivated reminder is claimed in cycle one');
select is(
  (select count(distinct access_cycle)::integer from lws_internal.intake_reminder_evidence
   where intake_id = 'fa200000-0000-4000-8000-000000000008'
     and reminder_phase = 'REMINDER_1'),
  2,
  'old and new reminder cycles retain independent evidence'
);
select is(
  (select cycle_started_at from reactivated_claim
   join lws_internal.intake_reminder_evidence using (intake_id, access_cycle, reminder_phase)),
  (select occurred_at from public.quote_request_intake_lifecycle_events
   where intake_id = 'fa200000-0000-4000-8000-000000000008' and event_type = 'REACTIVATED'),
  'reactivation event time is the new cycle anchor'
);

select is(
  (select count(*) from public.quote_request_email_jobs),
  (select value from email_job_count_before),
  'foundation creates no email delivery jobs'
);
select ok(
  not exists(select 1 from cron.job where jobname like '%reminder%'),
  'foundation creates no reminder cron job'
);

select * from finish();
rollback;
