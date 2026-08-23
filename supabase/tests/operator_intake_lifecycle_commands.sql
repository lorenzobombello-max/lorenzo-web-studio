begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(32);

select has_function(
  'public',
  'execute_operator_intake_lifecycle_command_v1',
  array['uuid','text','bigint','uuid','text'],
  'operator intake lifecycle command RPC exists'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.execute_operator_intake_lifecycle_command_v1(uuid,text,bigint,uuid,text)',
    'execute'
  ),
  'authenticated role can enter guarded lifecycle RPC'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.execute_operator_intake_lifecycle_command_v1(uuid,text,bigint,uuid,text)',
    'execute'
  ) and not has_function_privilege(
    'service_role',
    'public.execute_operator_intake_lifecycle_command_v1(uuid,text,bigint,uuid,text)',
    'execute'
  ),
  'anonymous and service roles cannot execute operator lifecycle commands'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.get_operator_application_v1_phase3_predecessor(uuid,text)',
    'execute'
  ),
  'service role cannot bypass the lifecycle-aware operator detail wrapper'
);

insert into auth.users (id, email) values
  ('f3000000-0000-4000-8000-000000000001', 'phase3-owner@example.test'),
  ('f3000000-0000-4000-8000-000000000002', 'phase3-admin@example.test'),
  ('f3000000-0000-4000-8000-000000000003', 'phase3-operator@example.test'),
  ('f3000000-0000-4000-8000-000000000004', 'phase3-disabled@example.test'),
  ('f3000000-0000-4000-8000-000000000005', 'phase3-customer@example.test');

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values
  ('f3010000-0000-4000-8000-000000000001', 'f3000000-0000-4000-8000-000000000001', 'Phase 3 Owner', 'owner', 'ACTIVE'),
  ('f3010000-0000-4000-8000-000000000002', 'f3000000-0000-4000-8000-000000000002', 'Phase 3 Admin', 'admin', 'ACTIVE'),
  ('f3010000-0000-4000-8000-000000000003', 'f3000000-0000-4000-8000-000000000003', 'Phase 3 Operator', 'operator', 'ACTIVE'),
  ('f3010000-0000-4000-8000-000000000004', 'f3000000-0000-4000-8000-000000000004', 'Phase 3 Disabled', 'admin', 'DISABLED');

insert into public.quote_requests (
  id, application_reference, record_classification, request_kind,
  name, email, website_type, budget, timing, description,
  privacy_consent, status
) values
  ('f3100000-0000-4000-8000-000000000001', 'LWS-AAN-2099-0301', 'production', 'website', 'Lifecycle Active', 'active@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Active lifecycle fixture.', true, 'approved'),
  ('f3100000-0000-4000-8000-000000000002', 'LWS-AAN-2099-0302', 'production', 'website', 'Lifecycle Expired', 'expired@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Expired lifecycle fixture.', true, 'approved');

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_state, lifecycle_revision, started_at, submitted_at, confirmation,
  created_at
) values
  ('f3200000-0000-4000-8000-000000000001', 'f3100000-0000-4000-8000-000000000001', 'submitted', repeat('3',64), '2099-08-30T12:00:00Z', 'ACTIVE', 0, clock_timestamp(), clock_timestamp(), true, clock_timestamp()),
  ('f3200000-0000-4000-8000-000000000002', 'f3100000-0000-4000-8000-000000000002', 'in_progress', repeat('4',64), '2020-01-01T00:00:00Z', 'ACTIVE', 0, '2019-12-26T00:00:00Z', null, false, '2019-12-25T00:00:00Z');

select throws_ok(
  $$select public.execute_operator_intake_lifecycle_command_v1('f3200000-0000-4000-8000-000000000001','INTERRUPTED',0,'f3300000-0000-4000-8000-000000000001','Operator pause')$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'missing human JWT is rejected'
);
select set_config('request.jwt.claim.sub', 'f3000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select public.execute_operator_intake_lifecycle_command_v1('f3200000-0000-4000-8000-000000000001','INTERRUPTED',0,'f3300000-0000-4000-8000-000000000001','Operator pause')$$,
  '42501', 'UNKNOWN_OPERATOR', 'customer identity cannot execute operator lifecycle command'
);
select set_config('request.jwt.claim.sub', 'f3000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$select public.execute_operator_intake_lifecycle_command_v1('f3200000-0000-4000-8000-000000000001','INTERRUPTED',0,'f3300000-0000-4000-8000-000000000001','Operator pause')$$,
  '42501', 'OPERATOR_DISABLED', 'disabled operator is rejected'
);
select set_config('request.jwt.claim.sub', 'f3000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.execute_operator_intake_lifecycle_command_v1('f3200000-0000-4000-8000-000000000001','INTERRUPTED',0,'f3300000-0000-4000-8000-000000000001','Operator pause')$$,
  '42501', 'APPLICATION_SCOPE_DENIED', 'project-scoped operator cannot mutate intake lifecycle'
);

select set_config('request.jwt.claim.sub', 'f3000000-0000-4000-8000-000000000001', true);
select is(
  public.get_operator_application_v1('f3100000-0000-4000-8000-000000000001', null)->'intake_lifecycle'->>'access_state',
  'ACTIVE',
  'operator detail exposes current lifecycle state'
);
select is(
  (public.get_operator_application_v1('f3100000-0000-4000-8000-000000000001', null)->'intake_lifecycle'->>'lifecycle_revision')::bigint,
  0::bigint,
  'operator detail exposes lifecycle revision'
);

select is(
  public.execute_operator_intake_lifecycle_command_v1(
    'f3200000-0000-4000-8000-000000000001', 'INTERRUPTED', 0,
    'f3300000-0000-4000-8000-000000000001', 'Operator pause'
  )->>'access_state',
  'INTERRUPTED',
  'ACTIVE transitions to INTERRUPTED'
);
select is(
  (select lifecycle_revision from public.quote_request_intakes where id = 'f3200000-0000-4000-8000-000000000001'),
  1::bigint,
  'interrupt increments lifecycle revision'
);
select is(
  (select access_token_expires_at from public.quote_request_intakes where id = 'f3200000-0000-4000-8000-000000000001'),
  '2099-08-30T12:00:00Z'::timestamptz,
  'interrupt preserves original expiry'
);
select throws_ok(
  $$select * from public.inspect_quote_request_intake(repeat('3',64))$$,
  'P0001', 'INTAKE_ACCESS_INTERRUPTED', 'Phase 2B enforcement immediately observes interruption'
);
select is(
  public.execute_operator_intake_lifecycle_command_v1(
    'f3200000-0000-4000-8000-000000000001', 'INTERRUPTED', 0,
    'f3300000-0000-4000-8000-000000000001', 'Operator pause'
  )->>'replayed',
  'true',
  'same idempotent command returns replayed result'
);
select is(
  (select count(*)::integer from public.quote_request_intake_lifecycle_events where intake_id = 'f3200000-0000-4000-8000-000000000001'),
  1,
  'idempotent replay creates no duplicate event'
);
select throws_ok(
  $$select public.execute_operator_intake_lifecycle_command_v1('f3200000-0000-4000-8000-000000000001','INTERRUPTED',0,'f3300000-0000-4000-8000-000000000001','Changed reason')$$,
  'P0001', 'IDEMPOTENCY_CONFLICT', 'changed replay is rejected'
);
select throws_ok(
  $$select public.execute_operator_intake_lifecycle_command_v1('f3200000-0000-4000-8000-000000000001','RESUMED',0,'f3300000-0000-4000-8000-000000000002','Resume stale')$$,
  '40001', 'CONCURRENT_MODIFICATION', 'stale lifecycle revision is rejected'
);
select is(
  public.execute_operator_intake_lifecycle_command_v1(
    'f3200000-0000-4000-8000-000000000001', 'RESUMED', 1,
    'f3300000-0000-4000-8000-000000000003', 'Resume intake'
  )->>'effective_access',
  'ACTIVE',
  'INTERRUPTED resumes to effective ACTIVE'
);
select is(
  (select access_token_expires_at from public.quote_request_intakes where id = 'f3200000-0000-4000-8000-000000000001'),
  '2099-08-30T12:00:00Z'::timestamptz,
  'resume preserves original expiry'
);
select is(
  public.execute_operator_intake_lifecycle_command_v1(
    'f3200000-0000-4000-8000-000000000001', 'CANCELLED', 2,
    'f3300000-0000-4000-8000-000000000004', 'Cancel intake'
  )->>'access_state',
  'CANCELLED',
  'ACTIVE transitions to terminal CANCELLED'
);
select throws_ok(
  $$select public.execute_operator_intake_lifecycle_command_v1('f3200000-0000-4000-8000-000000000001','REACTIVATED',3,'f3300000-0000-4000-8000-000000000005','Reactivate cancelled')$$,
  'P0001', 'INVALID_INTAKE_LIFECYCLE_TRANSITION', 'CANCELLED remains terminal'
);
select throws_ok(
  $$select * from public.inspect_quote_request_intake(repeat('3',64))$$,
  'P0001', 'INTAKE_ACCESS_CANCELLED', 'Phase 2B enforcement immediately observes cancellation'
);

select set_config('request.jwt.claim.sub', 'f3000000-0000-4000-8000-000000000002', true);
select is(
  public.execute_operator_intake_lifecycle_command_v1(
    'f3200000-0000-4000-8000-000000000002', 'REACTIVATED', 0,
    'f3300000-0000-4000-8000-000000000006', 'Reactivate expired intake'
  )->>'effective_access',
  'ACTIVE',
  'admin reactivates derived EXPIRED intake'
);
select is(
  (select lifecycle_revision from public.quote_request_intakes where id = 'f3200000-0000-4000-8000-000000000002'),
  1::bigint,
  'reactivation increments lifecycle revision'
);
select ok(
  (select access_token_expires_at > clock_timestamp() + interval '6 days 23 hours'
   from public.quote_request_intakes where id = 'f3200000-0000-4000-8000-000000000002'),
  'reactivation grants a fresh seven-day expiry window'
);
select is(
  (select actor_operator_id from public.quote_request_intake_lifecycle_events where idempotency_key = 'f3300000-0000-4000-8000-000000000006'),
  'f3010000-0000-4000-8000-000000000002'::uuid,
  'immutable event records authenticated operator identity'
);
select ok(
  (select evidence = jsonb_build_object('contract_version', 1, 'expected_lifecycle_revision', 0)
   from public.quote_request_intake_lifecycle_events where idempotency_key = 'f3300000-0000-4000-8000-000000000006'),
  'immutable event stores safe command evidence'
);
select is(
  public.execute_operator_intake_lifecycle_command_v1(
    'f3200000-0000-4000-8000-000000000002', 'INTERRUPTED', 1,
    'f3300000-0000-4000-8000-000000000007', 'Pause reactivated intake'
  )->>'access_state',
  'INTERRUPTED',
  'reactivated intake can be interrupted'
);
select is(
  public.execute_operator_intake_lifecycle_command_v1(
    'f3200000-0000-4000-8000-000000000002', 'CANCELLED', 2,
    'f3300000-0000-4000-8000-000000000008', 'Cancel interrupted intake'
  )->>'access_state',
  'CANCELLED',
  'INTERRUPTED transitions to terminal CANCELLED'
);
select throws_ok(
  $$update public.quote_request_intake_lifecycle_events set reason = 'tampered' where idempotency_key = 'f3300000-0000-4000-8000-000000000006'$$,
  '55000', 'INTAKE_LIFECYCLE_EVENT_IMMUTABLE', 'lifecycle audit event remains immutable'
);
select is(
  (select count(*)::integer from public.quote_request_intake_lifecycle_events where intake_id = 'f3200000-0000-4000-8000-000000000001'),
  3,
  'interrupt, resume, and cancel each persist one event'
);

select * from finish();
rollback;