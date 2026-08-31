begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, lws_internal, extensions;

select plan(34);

select has_table(
  'lws_internal',
  'sdf_initial_confirmation_recovery_events',
  'immutable SDF recovery evidence exists'
);
select has_function(
  'public',
  'recover_stale_sdf_initial_confirmation_work_v1',
  array['bigint', 'uuid', 'text'],
  'bounded stale SDF recovery RPC exists'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.recover_stale_sdf_initial_confirmation_work_v1(bigint,uuid,text)',
    'execute'
  ),
  'service role can execute recovery'
);
select ok(
  not has_function_privilege('anon', 'public.recover_stale_sdf_initial_confirmation_work_v1(bigint,uuid,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.recover_stale_sdf_initial_confirmation_work_v1(bigint,uuid,text)', 'execute')
  and not has_function_privilege('public', 'public.recover_stale_sdf_initial_confirmation_work_v1(bigint,uuid,text)', 'execute'),
  'recovery is unavailable to client and PUBLIC roles'
);
select ok(
  coalesce((
    select relrowsecurity and relforcerowsecurity
    from pg_class
    where oid = 'lws_internal.sdf_initial_confirmation_recovery_events'::regclass
  ), false),
  'recovery evidence enables and forces RLS'
);
select is(
  (
    select count(*)::integer
    from information_schema.role_table_grants
    where table_schema = 'lws_internal'
      and table_name = 'sdf_initial_confirmation_recovery_events'
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  0,
  'recovery evidence grants no direct table privileges'
);
select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'lws_internal.sdf_initial_confirmation_recovery_events'::regclass
      and tgname = 'trg_sdf_initial_confirmation_recovery_events_immutable'
      and not tgisinternal
  ),
  'recovery evidence has an immutable mutation guard'
);

insert into public.quote_requests (
  id, record_classification, request_kind, sdf_package, name, email,
  website_type, budget, timing, description, privacy_consent, status, approval_token_hash,
  approval_token_expires_at
) values
  (
    'fd610001-0000-4000-8000-000000000001', 'production',
    'slimme_documentenflow', 'start', 'Recovery authority fixture',
    'sdf-recovery@example.test', null, null, null, 'Bounded stale recovery fixture.', true,
    'pending', repeat('6', 64), clock_timestamp() + interval '1 day'
  ),
  (
    'fd610002-0000-4000-8000-000000000002', 'internal_e2e',
    'slimme_documentenflow', 'start', 'Non-production recovery fixture',
    'sdf-recovery-internal@example.test', null, null, null, 'Non-production rejection fixture.', true,
    'pending', repeat('7', 64), clock_timestamp() + interval '1 day'
  ),
  (
    'fd610003-0000-4000-8000-000000000003', 'production',
    'website', null, 'Website recovery fixture',
    'website-recovery@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Website rejection fixture.', true,
    'pending', repeat('8', 64), clock_timestamp() + interval '1 day'
  );

insert into lws_internal.application_intake_automation_work (
  quote_request_id, phase, approval_due_at, attempt_count, next_attempt_at
) values
  ('fd610001-0000-4000-8000-000000000001', 'SDF_CONFIRMATION', clock_timestamp() - interval '2 hours', 5, clock_timestamp() - interval '1 hour'),
  ('fd610002-0000-4000-8000-000000000002', 'SDF_CONFIRMATION', clock_timestamp() - interval '2 hours', 5, clock_timestamp() - interval '1 hour'),
  ('fd610003-0000-4000-8000-000000000003', 'SDF_CONFIRMATION', clock_timestamp() - interval '2 hours', 5, clock_timestamp() - interval '1 hour')
on conflict (quote_request_id) do update
set phase = excluded.phase,
    attempt_count = excluded.attempt_count,
    next_attempt_at = excluded.next_attempt_at;

insert into public.sdf_initial_confirmation_email_jobs (
  job_id, quote_request_id, status, attempt_count, next_attempt_at,
  locked_at, delivery_lease_token, delivery_lease_expires_at
) values (
  'fd620001-0000-4000-8000-000000000001',
  'fd610001-0000-4000-8000-000000000001',
  'processing', 1, clock_timestamp() - interval '1 hour',
  clock_timestamp() - interval '1 hour',
  'fd630001-0000-4000-8000-000000000001',
  clock_timestamp() - interval '50 minutes'
);

create temporary table recovery_target as
select work_id, quote_request_id
from lws_internal.application_intake_automation_work
where quote_request_id = 'fd610001-0000-4000-8000-000000000001';

select throws_ok(
  $$select public.recover_stale_sdf_initial_confirmation_work_v1(null, 'fd620001-0000-4000-8000-000000000001', 'RECOVERY-NULL-WORK')$$,
  '22023',
  'INVALID_SDF_INITIAL_CONFIRMATION_RECOVERY_TARGET',
  'null target fails closed'
);
select throws_ok(
  $$select public.recover_stale_sdf_initial_confirmation_work_v1((select work_id from recovery_target), 'fd620001-0000-4000-8000-000000000001', 'short')$$,
  '22023',
  'INVALID_SDF_INITIAL_CONFIRMATION_RECOVERY_REFERENCE',
  'short recovery reference fails closed'
);
select is(
  public.recover_stale_sdf_initial_confirmation_work_v1(9223372036854775807, 'fd620001-0000-4000-8000-000000000001', 'RECOVERY-UNKNOWN-WORK')->>'reason',
  'WORK_NOT_FOUND',
  'unknown work fails closed'
);
select is(
  public.recover_stale_sdf_initial_confirmation_work_v1((select work_id from recovery_target), 'fd620002-0000-4000-8000-000000000002', 'RECOVERY-WRONG-JOB')->>'reason',
  'STATE_MISMATCH',
  'wrong expected job identity fails closed'
);

update lws_internal.application_intake_automation_work set phase = 'SDF_INTAKE' where work_id = (select work_id from recovery_target);
select is(public.recover_stale_sdf_initial_confirmation_work_v1((select work_id from recovery_target), 'fd620001-0000-4000-8000-000000000001', 'RECOVERY-WRONG-PHASE')->>'outcome', 'not_eligible', 'non-confirmation phase is rejected');
update lws_internal.application_intake_automation_work set phase = 'SDF_CONFIRMATION' where work_id = (select work_id from recovery_target);

update lws_internal.application_intake_automation_work set attempt_count = 4 where work_id = (select work_id from recovery_target);
select is(public.recover_stale_sdf_initial_confirmation_work_v1((select work_id from recovery_target), 'fd620001-0000-4000-8000-000000000001', 'RECOVERY-NOT-EXHAUSTED')->>'outcome', 'not_eligible', 'non-exhausted work is rejected');
update lws_internal.application_intake_automation_work set attempt_count = 5 where work_id = (select work_id from recovery_target);

update lws_internal.application_intake_automation_work
set claim_token = 'fd640001-0000-4000-8000-000000000001',
    claimed_by = 'fd640002-0000-4000-8000-000000000002',
    claimed_at = clock_timestamp(),
    claim_expires_at = clock_timestamp() + interval '5 minutes'
where work_id = (select work_id from recovery_target);
select is(public.recover_stale_sdf_initial_confirmation_work_v1((select work_id from recovery_target), 'fd620001-0000-4000-8000-000000000001', 'RECOVERY-ACTIVE-WORK')->>'outcome', 'not_eligible', 'active work claim is rejected');
update lws_internal.application_intake_automation_work
set claim_token = null, claimed_by = null, claimed_at = null, claim_expires_at = null
where work_id = (select work_id from recovery_target);

select is(
  public.recover_stale_sdf_initial_confirmation_work_v1(
    (select work_id from lws_internal.application_intake_automation_work where quote_request_id = 'fd610002-0000-4000-8000-000000000002'),
    'fd620002-0000-4000-8000-000000000002',
    'RECOVERY-NON-PRODUCTION'
  )->>'outcome',
  'not_eligible',
  'non-production request is rejected'
);
select is(
  public.recover_stale_sdf_initial_confirmation_work_v1(
    (select work_id from lws_internal.application_intake_automation_work where quote_request_id = 'fd610003-0000-4000-8000-000000000003'),
    'fd620003-0000-4000-8000-000000000003',
    'RECOVERY-NON-SDF'
  )->>'outcome',
  'not_eligible',
  'non-SDF request is rejected'
);

update public.quote_requests set confirmation_sent_at = clock_timestamp() where id = 'fd610001-0000-4000-8000-000000000001';
select is(public.recover_stale_sdf_initial_confirmation_work_v1((select work_id from recovery_target), 'fd620001-0000-4000-8000-000000000001', 'RECOVERY-ALREADY-SENT')->>'outcome', 'not_eligible', 'request confirmation evidence is rejected');
update public.quote_requests set confirmation_sent_at = null where id = 'fd610001-0000-4000-8000-000000000001';
update lws_internal.application_intake_automation_work
set phase = 'SDF_CONFIRMATION', attempt_count = 5
where work_id = (select work_id from recovery_target);

update public.sdf_initial_confirmation_email_jobs
set status = 'retry_wait', locked_at = null, delivery_lease_token = null, delivery_lease_expires_at = null
where job_id = 'fd620001-0000-4000-8000-000000000001';
select is(public.recover_stale_sdf_initial_confirmation_work_v1((select work_id from recovery_target), 'fd620001-0000-4000-8000-000000000001', 'RECOVERY-NOT-PROCESSING')->>'outcome', 'not_eligible', 'non-processing job is rejected');
update public.sdf_initial_confirmation_email_jobs
set status = 'processing', locked_at = clock_timestamp() - interval '1 hour',
    delivery_lease_token = 'fd630001-0000-4000-8000-000000000001',
    delivery_lease_expires_at = clock_timestamp() - interval '50 minutes'
where job_id = 'fd620001-0000-4000-8000-000000000001';

update public.sdf_initial_confirmation_email_jobs
set locked_at = clock_timestamp(), delivery_lease_expires_at = clock_timestamp() + interval '10 minutes'
where job_id = 'fd620001-0000-4000-8000-000000000001';
select is(public.recover_stale_sdf_initial_confirmation_work_v1((select work_id from recovery_target), 'fd620001-0000-4000-8000-000000000001', 'RECOVERY-ACTIVE-LEASE')->>'outcome', 'not_eligible', 'active delivery lease is rejected');
update public.sdf_initial_confirmation_email_jobs
set locked_at = clock_timestamp() - interval '1 hour', delivery_lease_expires_at = clock_timestamp() - interval '50 minutes'
where job_id = 'fd620001-0000-4000-8000-000000000001';

update public.sdf_initial_confirmation_email_jobs set attempt_count = 5 where job_id = 'fd620001-0000-4000-8000-000000000001';
select is(public.recover_stale_sdf_initial_confirmation_work_v1((select work_id from recovery_target), 'fd620001-0000-4000-8000-000000000001', 'RECOVERY-JOB-EXHAUSTED')->>'outcome', 'not_eligible', 'exhausted delivery job is rejected');
update public.sdf_initial_confirmation_email_jobs set attempt_count = 1 where job_id = 'fd620001-0000-4000-8000-000000000001';

update public.sdf_initial_confirmation_email_jobs set provider_message_id = 'provider-evidence' where job_id = 'fd620001-0000-4000-8000-000000000001';
select is(public.recover_stale_sdf_initial_confirmation_work_v1((select work_id from recovery_target), 'fd620001-0000-4000-8000-000000000001', 'RECOVERY-PROVIDER-EVIDENCE')->>'outcome', 'not_eligible', 'provider evidence is rejected');
update public.sdf_initial_confirmation_email_jobs set provider_message_id = null where job_id = 'fd620001-0000-4000-8000-000000000001';

update public.sdf_initial_confirmation_email_jobs
set locked_at = clock_timestamp() - interval '24 hours',
    delivery_lease_expires_at = clock_timestamp() - interval '23 hours 50 minutes'
where job_id = 'fd620001-0000-4000-8000-000000000001';
select is(public.recover_stale_sdf_initial_confirmation_work_v1((select work_id from recovery_target), 'fd620001-0000-4000-8000-000000000001', 'RECOVERY-OUTSIDE-WINDOW')->>'outcome', 'not_eligible', '24-hour provider-idempotency boundary is rejected');
update public.sdf_initial_confirmation_email_jobs
set locked_at = clock_timestamp() - interval '1 hour',
    delivery_lease_expires_at = clock_timestamp() - interval '50 minutes'
where job_id = 'fd620001-0000-4000-8000-000000000001';

insert into public.quote_request_email_jobs (quote_request_id, kind)
values ('fd610001-0000-4000-8000-000000000001', 'customer_confirmation');
select is(public.recover_stale_sdf_initial_confirmation_work_v1((select work_id from recovery_target), 'fd620001-0000-4000-8000-000000000001', 'RECOVERY-LEGACY-OWNER')->>'outcome', 'not_eligible', 'legacy customer-confirmation ownership is rejected');
delete from public.quote_request_email_jobs where quote_request_id = 'fd610001-0000-4000-8000-000000000001' and kind = 'customer_confirmation';

create temporary table recovered as
select public.recover_stale_sdf_initial_confirmation_work_v1(
  (select work_id from recovery_target),
  'fd620001-0000-4000-8000-000000000001',
  '  TASK13-RECOVERY-TEST  '
) as result;

select is((select result->>'outcome' from recovered), 'recovered', 'eligible stale authority is recovered');
select is(
  (select jsonb_build_object('phase', phase, 'attempt_count', attempt_count, 'claimed', claim_token is not null, 'terminal_reason', terminal_reason) from lws_internal.application_intake_automation_work where work_id = (select work_id from recovery_target)),
  jsonb_build_object('phase', 'SDF_CONFIRMATION', 'attempt_count', 0, 'claimed', false, 'terminal_reason', null),
  'recovery rearms only the existing confirmation work item'
);
select is(
  (select jsonb_build_object('job_id', job_id, 'status', status, 'attempt_count', attempt_count, 'leased', delivery_lease_token is not null, 'sent_at', sent_at, 'provider_message_id', provider_message_id) from public.sdf_initial_confirmation_email_jobs where quote_request_id = 'fd610001-0000-4000-8000-000000000001'),
  jsonb_build_object('job_id', 'fd620001-0000-4000-8000-000000000001'::uuid, 'status', 'retry_wait', 'attempt_count', 1, 'leased', false, 'sent_at', null, 'provider_message_id', null),
  'recovery preserves job identity and attempt history while clearing the stale lease'
);
select is(
  (select count(*)::integer from public.sdf_initial_confirmation_email_jobs where quote_request_id = 'fd610001-0000-4000-8000-000000000001'),
  1,
  'recovery creates no second isolated job'
);
select is(
  (select jsonb_build_object('generation', recovery_generation, 'work_attempts', original_work_attempt_count, 'job_attempts', original_job_attempt_count, 'reference', recovery_reference, 'provider_key', provider_idempotency_key, 'lease_preserved', original_job_locked_at is not null and original_delivery_lease_token is not null and original_delivery_lease_expires_at is not null) from lws_internal.sdf_initial_confirmation_recovery_events where work_id = (select work_id from recovery_target)),
  jsonb_build_object('generation', 1, 'work_attempts', 5, 'job_attempts', 1, 'reference', 'TASK13-RECOVERY-TEST', 'provider_key', 'sdf-initial-confirmation/fd620001-0000-4000-8000-000000000001', 'lease_preserved', true),
  'immutable event preserves original exhaustion lease and provider identity'
);
select is(
  public.recover_stale_sdf_initial_confirmation_work_v1((select work_id from recovery_target), 'fd620001-0000-4000-8000-000000000001', 'TASK13-RECOVERY-REPLAY')->>'outcome',
  'already_recovered',
  'recovery replay is idempotent'
);
select is((select count(*)::integer from lws_internal.sdf_initial_confirmation_recovery_events where work_id = (select work_id from recovery_target)), 1, 'replay creates exactly one recovery generation');
select throws_ok(
  $$update lws_internal.sdf_initial_confirmation_recovery_events set recovery_reference = 'MUTATED-REFERENCE' where work_id = (select work_id from recovery_target)$$,
  '55000',
  'SDF_INITIAL_CONFIRMATION_RECOVERY_EVENT_IMMUTABLE',
  'recovery evidence cannot be updated'
);
select throws_ok(
  $$delete from lws_internal.sdf_initial_confirmation_recovery_events where work_id = (select work_id from recovery_target)$$,
  '55000',
  'SDF_INITIAL_CONFIRMATION_RECOVERY_EVENT_IMMUTABLE',
  'recovery evidence cannot be deleted'
);
select is(
  (select count(*)::integer from public.quote_request_email_jobs where quote_request_id = 'fd610001-0000-4000-8000-000000000001' and kind = 'customer_confirmation'),
  0,
  'recovery creates no legacy customer-confirmation authority'
);
select public.activate_application_intake_automation_v1('SDF-RECOVERY-V1-TEST');
update lws_internal.application_intake_automation_config
set cutover_at = fixture.activated_at,
    activated_at = fixture.activated_at
from (select clock_timestamp() - interval '1 day' as activated_at) as fixture
where singleton;
select is(
  (select count(*)::integer from public.claim_application_intake_automation_work_by_id_v1('fd650001-0000-4000-8000-000000000001', (select work_id from recovery_target))),
  1,
  'existing targeted authority can claim the rearmed work exactly once'
);

select * from finish();
rollback;
