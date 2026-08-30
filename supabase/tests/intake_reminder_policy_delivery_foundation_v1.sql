begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, lws_internal, extensions;
select no_plan();

create temp table reminder_test_clock as
select clock_timestamp() as value;

select has_function('lws_internal', 'intake_reminder_phase_is_due_v1', array['text','timestamptz','timestamptz'], 'expiry-relative policy helper exists');
select has_function('public', 'prepare_intake_reminder_email_job_v1', array['uuid','bigint','text','uuid','text','timestamptz'], 'cycle-bound preparation RPC exists');
select has_function('public', 'get_intake_reminder_email_delivery_v1', array['uuid','timestamptz'], 'final delivery-context recheck exists');
select ok(
  has_function_privilege('service_role', 'public.prepare_intake_reminder_email_job_v1(uuid,bigint,text,uuid,text,timestamptz)', 'execute')
  and not has_function_privilege('authenticated', 'public.prepare_intake_reminder_email_job_v1(uuid,bigint,text,uuid,text,timestamptz)', 'execute')
  and not has_function_privilege('anon', 'public.get_intake_reminder_email_delivery_v1(uuid,timestamptz)', 'execute'),
  'reminder payload authority remains service-only'
);
select ok(
  exists(select 1 from pg_enum where enumtypid = 'public.quote_request_email_kind'::regtype and enumlabel = 'intake_reminder_1')
  and exists(select 1 from pg_enum where enumtypid = 'public.quote_request_email_kind'::regtype and enumlabel = 'intake_reminder_2'),
  'dedicated reminder email kinds exist'
);

select ok(
  not lws_internal.intake_reminder_phase_is_due_v1('REMINDER_1', '2030-01-04 11:59:59+00', '2030-01-08 12:00:00+00'),
  'REMINDER_1 is not due before four days remain'
);
select ok(
  lws_internal.intake_reminder_phase_is_due_v1('REMINDER_1', '2030-01-04 12:00:00+00', '2030-01-08 12:00:00+00'),
  'REMINDER_1 begins inclusively at four days remaining'
);
select ok(
  lws_internal.intake_reminder_phase_is_due_v1('REMINDER_1', '2030-01-07 11:59:59+00', '2030-01-08 12:00:00+00'),
  'REMINDER_1 remains due immediately before the final-day window'
);
select ok(
  not lws_internal.intake_reminder_phase_is_due_v1('REMINDER_1', '2030-01-07 12:00:00+00', '2030-01-08 12:00:00+00'),
  'REMINDER_1 ends exclusively when REMINDER_2 begins'
);
select ok(
  not lws_internal.intake_reminder_phase_is_due_v1('REMINDER_2', '2030-01-07 11:59:59+00', '2030-01-08 12:00:00+00'),
  'REMINDER_2 is not due before the final day'
);
select ok(
  lws_internal.intake_reminder_phase_is_due_v1('REMINDER_2', '2030-01-07 12:00:00+00', '2030-01-08 12:00:00+00'),
  'REMINDER_2 begins inclusively at one day remaining'
);
select ok(
  not lws_internal.intake_reminder_phase_is_due_v1('REMINDER_1', '2030-01-08 12:00:00+00', '2030-01-08 12:00:00+00')
  and not lws_internal.intake_reminder_phase_is_due_v1('REMINDER_2', '2030-01-08 12:00:00+00', '2030-01-08 12:00:00+00'),
  'neither reminder is due at or after expiry'
);

insert into auth.users (id, email) values
  ('fb000001-0000-4000-8000-000000000001', 'reminder-policy-owner@example.test');
insert into public.commercial_operators (operator_id, auth_user_id, display_name, role, status) values
  ('fb010001-0000-4000-8000-000000000001', 'fb000001-0000-4000-8000-000000000001', 'Reminder Policy Owner', 'owner', 'ACTIVE');

insert into public.quote_requests (
  id, record_classification, request_kind, name, company, email, website_type,
  budget, timing, description, privacy_consent, status
) values
  ('fb100001-0000-4000-8000-000000000001', 'production', 'website', 'Before Window', null, 'before@example.test', 'business', 'EUR 3.000', 'flexible', 'Policy fixture.', true, 'approved'),
  ('fb100002-0000-4000-8000-000000000002', 'production', 'website', 'Invited Due', 'Invited BV', 'invited@example.test', 'business', 'EUR 3.000', 'flexible', 'Policy fixture.', true, 'approved'),
  ('fb100003-0000-4000-8000-000000000003', 'production', 'website', 'Progress Due', 'Progress BV', 'progress@example.test', 'business', 'EUR 3.000', 'flexible', 'Policy fixture.', true, 'approved'),
  ('fb100004-0000-4000-8000-000000000004', 'production', 'website', 'Submitted Recheck', null, 'submitted@example.test', 'business', 'EUR 3.000', 'flexible', 'Recheck fixture.', true, 'approved'),
  ('fb100005-0000-4000-8000-000000000005', 'production', 'website', 'Cancelled Recheck', null, 'cancelled@example.test', 'business', 'EUR 3.000', 'flexible', 'Recheck fixture.', true, 'approved'),
  ('fb100006-0000-4000-8000-000000000006', 'production', 'website', 'Interrupted Recheck', null, 'interrupted@example.test', 'business', 'EUR 3.000', 'flexible', 'Recheck fixture.', true, 'approved'),
  ('fb100007-0000-4000-8000-000000000007', 'production', 'website', 'Expired Recheck', null, 'expired@example.test', 'business', 'EUR 3.000', 'flexible', 'Recheck fixture.', true, 'approved'),
  ('fb100008-0000-4000-8000-000000000008', 'production', 'website', 'Resume Cycle', null, 'resume@example.test', 'business', 'EUR 3.000', 'flexible', 'Cycle fixture.', true, 'approved'),
  ('fb100009-0000-4000-8000-000000000009', 'production', 'website', 'Reactivate Cycle', null, 'reactivate@example.test', 'business', 'EUR 3.000', 'flexible', 'Cycle fixture.', true, 'approved');

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_state, lifecycle_revision, started_at, confirmation, created_at
) values
  ('fb200001-0000-4000-8000-000000000001', 'fb100001-0000-4000-8000-000000000001', 'invited', repeat('1',64), (select value + interval '5 days' from reminder_test_clock), 'ACTIVE', 0, null, false, (select value - interval '2 days' from reminder_test_clock)),
  ('fb200002-0000-4000-8000-000000000002', 'fb100002-0000-4000-8000-000000000002', 'invited', repeat('2',64), (select value + interval '3 days' from reminder_test_clock), 'ACTIVE', 0, null, false, (select value - interval '4 days' from reminder_test_clock)),
  ('fb200003-0000-4000-8000-000000000003', 'fb100003-0000-4000-8000-000000000003', 'in_progress', repeat('3',64), (select value + interval '12 hours' from reminder_test_clock), 'ACTIVE', 0, (select value - interval '1 day' from reminder_test_clock), false, (select value - interval '6 days' from reminder_test_clock)),
  ('fb200004-0000-4000-8000-000000000004', 'fb100004-0000-4000-8000-000000000004', 'invited', repeat('4',64), (select value + interval '3 days' from reminder_test_clock), 'ACTIVE', 0, null, false, (select value - interval '4 days' from reminder_test_clock)),
  ('fb200005-0000-4000-8000-000000000005', 'fb100005-0000-4000-8000-000000000005', 'invited', repeat('5',64), (select value + interval '3 days' from reminder_test_clock), 'ACTIVE', 0, null, false, (select value - interval '4 days' from reminder_test_clock)),
  ('fb200006-0000-4000-8000-000000000006', 'fb100006-0000-4000-8000-000000000006', 'invited', repeat('6',64), (select value + interval '3 days' from reminder_test_clock), 'ACTIVE', 0, null, false, (select value - interval '4 days' from reminder_test_clock)),
  ('fb200007-0000-4000-8000-000000000007', 'fb100007-0000-4000-8000-000000000007', 'invited', repeat('7',64), (select value + interval '3 days' from reminder_test_clock), 'ACTIVE', 0, null, false, (select value - interval '4 days' from reminder_test_clock)),
  ('fb200008-0000-4000-8000-000000000008', 'fb100008-0000-4000-8000-000000000008', 'invited', repeat('8',64), (select value + interval '3 days' from reminder_test_clock), 'ACTIVE', 0, null, false, (select value - interval '4 days' from reminder_test_clock)),
  ('fb200009-0000-4000-8000-000000000009', 'fb100009-0000-4000-8000-000000000009', 'invited', repeat('9',64), (select value - interval '1 hour' from reminder_test_clock), 'ACTIVE', 0, null, false, (select value - interval '7 days' from reminder_test_clock));

select is(
  (select count(*)::integer from public.list_intake_reminder_candidates_v1('REMINDER_1', (select value from reminder_test_clock), 100) where intake_id = 'fb200001-0000-4000-8000-000000000001'),
  0,
  'candidate projection excludes REMINDER_1 before its window'
);
select ok(
  exists(select 1 from public.list_intake_reminder_candidates_v1('REMINDER_1', (select value from reminder_test_clock), 100)
         where intake_id = 'fb200002-0000-4000-8000-000000000002' and progress_status = 'invited'),
  'invited intake is a REMINDER_1 candidate in-window'
);
select ok(
  exists(select 1 from public.list_intake_reminder_candidates_v1('REMINDER_2', (select value from reminder_test_clock), 100)
         where intake_id = 'fb200003-0000-4000-8000-000000000003' and progress_status = 'in_progress' and started_at is not null),
  'in-progress intake is a REMINDER_2 candidate in-window'
);
select is(
  (select count(*)::integer from public.claim_intake_reminder_v1('fb200001-0000-4000-8000-000000000001', 'REMINDER_1', (select value from reminder_test_clock))),
  0,
  'claim authority also rejects a phase before its timing window'
);

create temp table invited_r1_claim as
select * from public.claim_intake_reminder_v1(
  'fb200002-0000-4000-8000-000000000002', 'REMINDER_1', (select value from reminder_test_clock)
);
create temp table invited_r1_job as
select * from public.prepare_intake_reminder_email_job_v1(
  'fb200002-0000-4000-8000-000000000002', 0, 'REMINDER_1',
  (select claim_token from invited_r1_claim),
  'v1.aaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  (select value from reminder_test_clock)
);
select is((select email_job_status from invited_r1_job), 'pending', 'valid claim prepares a pending email job without delivery');
select is(
  (select kind::text from public.quote_request_email_jobs where id = (select email_job_id from invited_r1_job)),
  'intake_reminder_1',
  'REMINDER_1 uses its dedicated email kind'
);
select is(
  (select count(distinct email_job_id)::integer from (
    select email_job_id from invited_r1_job
    union all
    select email_job_id from public.prepare_intake_reminder_email_job_v1(
      'fb200002-0000-4000-8000-000000000002', 0, 'REMINDER_1',
      (select claim_token from invited_r1_claim),
      'v1.cccccccccccccccc.dddddddddddddddddddddddddddddddddddddddd',
      (select value from reminder_test_clock)
    )
  ) as attempts),
  1,
  'same-cycle REMINDER_1 preparation is idempotent'
);

create temp table invited_r2_claim as
select * from public.claim_intake_reminder_v1(
  'fb200002-0000-4000-8000-000000000002', 'REMINDER_2',
  (select value + interval '2 days 12 hours' from reminder_test_clock)
);
create temp table invited_r2_job as
select * from public.prepare_intake_reminder_email_job_v1(
  'fb200002-0000-4000-8000-000000000002', 0, 'REMINDER_2',
  (select claim_token from invited_r2_claim),
  'v1.eeeeeeeeeeeeeeee.ffffffffffffffffffffffffffffffffffffffff',
  (select value + interval '2 days 12 hours' from reminder_test_clock)
);
select is((select email_job_status from invited_r2_job), 'pending', 'REMINDER_1 evidence does not block REMINDER_2 preparation');
select is(
  (select email_job_id from public.prepare_intake_reminder_email_job_v1(
    'fb200002-0000-4000-8000-000000000002', 0, 'REMINDER_2',
    (select claim_token from invited_r2_claim),
    'v1.kkkkkkkkkkkkkkkk.llllllllllllllllllllllllllllllllllllllll',
    (select value + interval '2 days 12 hours' from reminder_test_clock)
  )),
  (select email_job_id from invited_r2_job),
  'same-cycle REMINDER_2 preparation returns the existing job'
);
select is(
  (select count(*)::integer from public.quote_request_email_jobs
   where reminder_intake_id = 'fb200002-0000-4000-8000-000000000002' and reminder_access_cycle = 0),
  2,
  'two reminder phases produce exactly two same-cycle jobs'
);

select is(
  (select count(*)::integer from public.claim_quote_request_email_job((select email_job_id from invited_r1_job))),
  1,
  'existing delivery claim pipeline activates an eligible reminder job'
);
select is(
  (select job_status from public.complete_quote_request_email_job(
    (select email_job_id from invited_r1_job), true, false, null, 'local-provider-id'
  )),
  'sent',
  'existing completion pipeline records a simulated successful delivery'
);
select ok(
  exists(select 1 from lws_internal.intake_reminder_evidence
         where intake_id = 'fb200002-0000-4000-8000-000000000002'
           and access_cycle = 0 and reminder_phase = 'REMINDER_1'
           and state = 'SENT' and email_job_id = (select email_job_id from invited_r1_job)),
  'job completion atomically finalizes reminder evidence'
);
select is(
  (select encrypted_payload from public.quote_request_email_jobs where id = (select email_job_id from invited_r1_job)),
  null,
  'successful reminder completion clears encrypted capability payload'
);

create temp table recheck_claims as
select fixture.intake_id, claim.claim_token
from (values
  ('fb200004-0000-4000-8000-000000000004'::uuid),
  ('fb200005-0000-4000-8000-000000000005'::uuid),
  ('fb200006-0000-4000-8000-000000000006'::uuid),
  ('fb200007-0000-4000-8000-000000000007'::uuid)
) as fixture(intake_id)
cross join lateral public.claim_intake_reminder_v1(
  fixture.intake_id, 'REMINDER_1', (select value from reminder_test_clock)
) as claim;

create temp table recheck_jobs as
select claims.intake_id, prepared.email_job_id
from recheck_claims as claims
cross join lateral public.prepare_intake_reminder_email_job_v1(
  claims.intake_id, 0, 'REMINDER_1', claims.claim_token,
  'v1.gggggggggggggggg.hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh',
  (select value from reminder_test_clock)
) as prepared;

update public.quote_request_intakes
set status = 'submitted',
    started_at = (select value - interval '1 day' from reminder_test_clock),
    submitted_at = (select value from reminder_test_clock),
    confirmation = true
where id = 'fb200004-0000-4000-8000-000000000004';
update public.quote_request_intakes set access_state = 'CANCELLED'
where id = 'fb200005-0000-4000-8000-000000000005';
update public.quote_request_intakes set access_state = 'INTERRUPTED'
where id = 'fb200006-0000-4000-8000-000000000006';
update public.quote_request_intakes set access_token_expires_at = (select value - interval '1 second' from reminder_test_clock)
where id = 'fb200007-0000-4000-8000-000000000007';

select is(
  (select count(*)::integer from recheck_jobs as jobs
   cross join lateral public.claim_quote_request_email_job(jobs.email_job_id)),
  0,
  'final activation recheck refuses submitted, cancelled, interrupted, and expired reminders'
);
select is(
  (select count(*)::integer from public.quote_request_email_jobs as job
   join recheck_jobs on recheck_jobs.email_job_id = job.id
   where job.status = 'failed' and job.last_error_code = 'REMINDER_NOT_ELIGIBLE' and job.encrypted_payload is null),
  4,
  'all four invalidated jobs become non-sendable and discard encrypted payload'
);
select is(
  (select count(*)::integer from recheck_jobs as jobs
   cross join lateral public.get_intake_reminder_email_delivery_v1(jobs.email_job_id, (select value from reminder_test_clock))),
  0,
  'delivery context projection exposes no invalidated reminder payload'
);

insert into public.quote_request_email_jobs (
  id, quote_request_id, kind, status, sent_at,
  reminder_intake_id, reminder_access_cycle, reminder_phase, reminder_claim_token
) values
  ('fb300081-0000-4000-8000-000000000081', 'fb100008-0000-4000-8000-000000000008', 'intake_reminder_1', 'sent', (select value - interval '1 day' from reminder_test_clock), 'fb200008-0000-4000-8000-000000000008', 0, 'REMINDER_1', 'fb400081-0000-4000-8000-000000000081'),
  ('fb300091-0000-4000-8000-000000000091', 'fb100009-0000-4000-8000-000000000009', 'intake_reminder_1', 'sent', (select value - interval '2 days' from reminder_test_clock), 'fb200009-0000-4000-8000-000000000009', 0, 'REMINDER_1', 'fb400091-0000-4000-8000-000000000091'),
  ('fb300092-0000-4000-8000-000000000092', 'fb100009-0000-4000-8000-000000000009', 'intake_reminder_2', 'sent', (select value - interval '1 day' from reminder_test_clock), 'fb200009-0000-4000-8000-000000000009', 0, 'REMINDER_2', 'fb400092-0000-4000-8000-000000000092');

insert into lws_internal.intake_reminder_evidence (
  intake_id, access_cycle, reminder_phase, cycle_started_at, state,
  claim_token, claimed_at, claim_expires_at, sent_at, email_job_id
) values
  ('fb200008-0000-4000-8000-000000000008', 0, 'REMINDER_1', (select value - interval '4 days' from reminder_test_clock), 'SENT', 'fb400081-0000-4000-8000-000000000081', (select value - interval '1 day 1 hour' from reminder_test_clock), (select value - interval '1 day' from reminder_test_clock), (select value - interval '1 day' from reminder_test_clock), 'fb300081-0000-4000-8000-000000000081'),
  ('fb200009-0000-4000-8000-000000000009', 0, 'REMINDER_1', (select value - interval '7 days' from reminder_test_clock), 'SENT', 'fb400091-0000-4000-8000-000000000091', (select value - interval '2 days 1 hour' from reminder_test_clock), (select value - interval '2 days' from reminder_test_clock), (select value - interval '2 days' from reminder_test_clock), 'fb300091-0000-4000-8000-000000000091'),
  ('fb200009-0000-4000-8000-000000000009', 0, 'REMINDER_2', (select value - interval '7 days' from reminder_test_clock), 'SENT', 'fb400092-0000-4000-8000-000000000092', (select value - interval '1 day 1 hour' from reminder_test_clock), (select value - interval '1 day' from reminder_test_clock), (select value - interval '1 day' from reminder_test_clock), 'fb300092-0000-4000-8000-000000000092');

select set_config('request.jwt.claim.sub', 'fb000001-0000-4000-8000-000000000001', true);
select is(
  public.execute_operator_intake_lifecycle_command_v1(
    'fb200008-0000-4000-8000-000000000008', 'INTERRUPTED', 0,
    'fb500081-0000-4000-8000-000000000081', 'Pause same reminder cycle'
  )->>'effective_access',
  'INTERRUPTED',
  'resume fixture can be interrupted'
);
select is(
  public.execute_operator_intake_lifecycle_command_v1(
    'fb200008-0000-4000-8000-000000000008', 'RESUMED', 1,
    'fb500082-0000-4000-8000-000000000082', 'Resume same reminder cycle'
  )->>'effective_access',
  'ACTIVE',
  'resume restores access'
);
select is(
  (select access_cycle from lws_internal.resolve_intake_reminder_access_cycle_v1('fb200008-0000-4000-8000-000000000008')),
  0::bigint,
  'resume retains the existing reminder cycle'
);
select ok(
  not exists(select 1 from public.list_intake_reminder_candidates_v1('REMINDER_1', (select value from reminder_test_clock), 100)
             where intake_id = 'fb200008-0000-4000-8000-000000000008'),
  'resume does not reset already-sent REMINDER_1 evidence'
);

select is(
  public.execute_operator_intake_lifecycle_command_v1(
    'fb200009-0000-4000-8000-000000000009', 'REACTIVATED', 0,
    'fb500091-0000-4000-8000-000000000091', 'Start fresh reminder cycle'
  )->>'effective_access',
  'ACTIVE',
  'reactivation restores access with a new expiry'
);
select is(
  (select access_cycle from lws_internal.resolve_intake_reminder_access_cycle_v1('fb200009-0000-4000-8000-000000000009')),
  1::bigint,
  'reactivation advances the reminder cycle'
);
create temp table cycle_b_r1_claim as
select * from public.claim_intake_reminder_v1(
  'fb200009-0000-4000-8000-000000000009', 'REMINDER_1',
  (select value + interval '3 days 1 minute' from reminder_test_clock)
);
create temp table cycle_b_r1_job as
select * from public.prepare_intake_reminder_email_job_v1(
  'fb200009-0000-4000-8000-000000000009', 1, 'REMINDER_1',
  (select claim_token from cycle_b_r1_claim),
  'v1.iiiiiiiiiiiiiiii.jjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjj',
  (select value + interval '3 days 1 minute' from reminder_test_clock)
);
select is((select email_job_status from cycle_b_r1_job), 'pending', 'cycle B can prepare REMINDER_1 after cycle A sent both phases');
create temp table cycle_b_r2_claim as
select * from public.claim_intake_reminder_v1(
  'fb200009-0000-4000-8000-000000000009', 'REMINDER_2',
  (select value + interval '6 days 1 minute' from reminder_test_clock)
);
create temp table cycle_b_r2_job as
select * from public.prepare_intake_reminder_email_job_v1(
  'fb200009-0000-4000-8000-000000000009', 1, 'REMINDER_2',
  (select claim_token from cycle_b_r2_claim),
  'v1.mmmmmmmmmmmmmmmm.nnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnn',
  (select value + interval '6 days 1 minute' from reminder_test_clock)
);
select is((select email_job_status from cycle_b_r2_job), 'pending', 'cycle B can also prepare REMINDER_2 after cycle A sent both phases');
select is(
  (select count(*)::integer from public.quote_request_email_jobs
   where reminder_intake_id = 'fb200009-0000-4000-8000-000000000009' and reminder_access_cycle = 1),
  2,
  'reactivated cycle has independent jobs for both reminder phases'
);
select is(
  (select count(*)::integer from public.quote_request_email_jobs
   where reminder_intake_id = 'fb200009-0000-4000-8000-000000000009' and kind = 'intake_reminder_1'),
  2,
  'old-cycle email job does not block the same phase in a new cycle'
);

select ok(
  exists(
    select 1
    from lws_internal.operator_pending_intakes_v1
    where intake_id = 'fb200002-0000-4000-8000-000000000002'
      and started_at is null
      and current_reminder_cycle = 0
      and reminder_1_sent_at is not null
  ),
  'operator read model safely projects current cycle and sent timestamps'
);
select ok(
  (select pg_get_function_result('public.get_intake_reminder_email_delivery_v1(uuid,timestamptz)'::regprocedure) !~* 'access_token_hash|claim_token'),
  'delivery projection signature exposes no hash or reminder claim token'
);
select ok(
  not exists(select 1 from cron.job where jobname like '%reminder%'),
  'foundation activates no reminder cron job'
);

select * from finish();
rollback;
