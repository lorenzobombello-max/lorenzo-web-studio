create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

create temporary table assignment_concurrency_fixture (
  quote_request_id uuid not null,
  application_reference text not null,
  race_a_idempotency_key uuid not null,
  race_b_idempotency_key uuid not null,
  owner_user_id uuid not null,
  race_a_user_id uuid not null,
  race_b_user_id uuid not null,
  owner_operator_id uuid not null,
  race_a_operator_id uuid not null,
  race_b_operator_id uuid not null,
  owner_user_email text not null,
  race_a_user_email text not null,
  race_b_user_email text not null,
  setup_connection_result text,
  setup_result text
) on commit preserve rows;

with run_identity as materialized (
  select
    gen_random_uuid() as run_token,
    gen_random_uuid() as owner_user_id,
    gen_random_uuid() as race_a_user_id,
    gen_random_uuid() as race_b_user_id,
    gen_random_uuid() as owner_operator_id,
    gen_random_uuid() as race_a_operator_id,
    gen_random_uuid() as race_b_operator_id
), candidates as materialized (
  select floor(random() * 100000000)::bigint as reference_number
  from generate_series(1, 100)
)
insert into assignment_concurrency_fixture (
  quote_request_id, application_reference,
  race_a_idempotency_key, race_b_idempotency_key,
  owner_user_id, race_a_user_id, race_b_user_id,
  owner_operator_id, race_a_operator_id, race_b_operator_id,
  owner_user_email, race_a_user_email, race_b_user_email
)
select
  gen_random_uuid(),
  format(
    'LWS-AAN-%s-%s',
    lpad((reference_number / 10000)::text, 4, '0'),
    lpad((reference_number % 10000)::text, 4, '0')
  ),
  gen_random_uuid(),
  gen_random_uuid(),
  run_identity.owner_user_id,
  run_identity.race_a_user_id,
  run_identity.race_b_user_id,
  run_identity.owner_operator_id,
  run_identity.race_a_operator_id,
  run_identity.race_b_operator_id,
  format('assignment-race-owner+%s@example.test', run_identity.run_token),
  format('assignment-race-a+%s@example.test', run_identity.run_token),
  format('assignment-race-b+%s@example.test', run_identity.run_token)
from candidates
cross join run_identity
where not exists (
  select 1
  from lws_internal.dossier_identity_anchors
  where application_reference = format(
    'LWS-AAN-%s-%s',
    lpad((reference_number / 10000)::text, 4, '0'),
    lpad((reference_number % 10000)::text, 4, '0')
  )
)
limit 1;

do $fixture_setup$
declare
  v_connection_result text;
  v_setup_result text;
begin
  v_connection_result := extensions.dblink_connect(
    'assignment_concurrency_setup',
    'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=assignment_concurrency_setup'
  );

  select extensions.dblink_exec(
    'assignment_concurrency_setup',
    format($setup$
      insert into auth.users(id, email) values
        (%L, %L),
        (%L, %L),
        (%L, %L);
      insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
        (%L, %L, 'Assignment Race Owner', 'owner', 'ACTIVE'),
        (%L, %L, 'Assignment Race A', 'operator', 'ACTIVE'),
        (%L, %L, 'Assignment Race B', 'operator', 'ACTIVE');
      insert into public.quote_requests(
        id, application_reference, record_classification, request_kind,
        name, email, website_type, budget, timing, description, privacy_consent, status
      ) values (
        %L, %L, 'production', 'website',
        'Assignment race fixture', 'assignment-race@example.test', 'business',
        'Meer dan EUR 6.000', 'flexible', 'Assignment race fixture.', true, 'approved'
      );
    $setup$,
      owner_user_id, owner_user_email,
      race_a_user_id, race_a_user_email,
      race_b_user_id, race_b_user_email,
      owner_operator_id, owner_user_id,
      race_a_operator_id, race_a_user_id,
      race_b_operator_id, race_b_user_id,
      quote_request_id, application_reference
    )
  )
  into v_setup_result
  from assignment_concurrency_fixture;

  update assignment_concurrency_fixture
  set setup_connection_result = v_connection_result,
      setup_result = v_setup_result;
end;
$fixture_setup$;

begin;

set local search_path = public, extensions;
select plan(85);

create function pg_temp.wait_for_assignment_lock_v1(p_backend_pid integer)
returns boolean
language plpgsql
as $$
declare
  v_deadline timestamptz := clock_timestamp() + interval '5 seconds';
begin
  loop
    if exists (
      select 1 from pg_catalog.pg_locks
      where pid = p_backend_pid and not granted
    ) then
      return true;
    end if;
    if clock_timestamp() >= v_deadline then
      return false;
    end if;
  end loop;
end;
$$;

select has_table('lws_internal', 'operator_dossier_assignments', 'private assignment state exists');
select has_table('lws_internal', 'operator_dossier_assignment_events', 'private assignment audit exists');
select has_table('lws_internal', 'operator_dossier_assignment_commands', 'private assignment idempotency ledger exists');
select has_function(
  'public', 'assign_operator_dossier_v1',
  array['text','uuid','bigint','uuid','text'],
  'assignment command RPC exists'
);
select has_function(
  'public', 'get_operator_dossier_assignment_v1',
  array['text'],
  'assignment detail RPC exists'
);
select ok(
  has_function_privilege('authenticated', 'public.assign_operator_dossier_v1(text,uuid,bigint,uuid,text)', 'execute')
  and has_function_privilege('authenticated', 'public.get_operator_dossier_assignment_v1(text)', 'execute')
  and not has_function_privilege('anon', 'public.assign_operator_dossier_v1(text,uuid,bigint,uuid,text)', 'execute')
  and not has_function_privilege('service_role', 'public.assign_operator_dossier_v1(text,uuid,bigint,uuid,text)', 'execute'),
  'only authenticated humans can enter assignment RPCs'
);
select ok(
  not has_table_privilege('authenticated', 'lws_internal.operator_dossier_assignments', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'lws_internal.operator_dossier_assignment_events', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'lws_internal.operator_dossier_assignment_commands', 'select,insert,update,delete'),
  'authenticated has no direct assignment table rights'
);
select is(
  (select count(*)::integer from pg_catalog.pg_class
   where oid in (
     'lws_internal.operator_dossier_assignments'::regclass,
     'lws_internal.operator_dossier_assignment_events'::regclass,
     'lws_internal.operator_dossier_assignment_commands'::regclass
   ) and relrowsecurity),
  3, 'RLS is enabled on all assignment tables'
);
select is(
  (select count(*)::integer from pg_catalog.pg_class
   where oid in (
     'lws_internal.operator_dossier_assignments'::regclass,
     'lws_internal.operator_dossier_assignment_events'::regclass,
     'lws_internal.operator_dossier_assignment_commands'::regclass
   ) and relforcerowsecurity),
  3, 'RLS is forced on all assignment tables'
);
select is(
  (select count(*)::integer from information_schema.role_table_grants
   where table_schema = 'lws_internal'
     and table_name in (
       'operator_dossier_assignments',
       'operator_dossier_assignment_events',
       'operator_dossier_assignment_commands'
     )
     and grantee in ('PUBLIC', 'anon', 'authenticated')
     and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')),
  0, 'PUBLIC, anon, and authenticated have no direct assignment table privileges'
);
select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'unassign_operator_dossier_v1'
  ),
  'no public dossier unassign function exists'
);

insert into auth.users(id, email) values
  ('a6000000-0000-4000-8000-000000000001', 'assignment-owner@example.test'),
  ('a6000000-0000-4000-8000-000000000002', 'assignment-manager@example.test'),
  ('a6000000-0000-4000-8000-000000000003', 'assignment-operator-a@example.test'),
  ('a6000000-0000-4000-8000-000000000004', 'assignment-operator-b@example.test'),
  ('a6000000-0000-4000-8000-000000000005', 'assignment-admin@example.test'),
  ('a6000000-0000-4000-8000-000000000006', 'assignment-disabled@example.test'),
  ('a6000000-0000-4000-8000-000000000007', 'assignment-revoked@example.test'),
  ('a6000000-0000-4000-8000-000000000008', 'assignment-customer@example.test'),
  ('a6000000-0000-4000-8000-000000000009', 'assignment-reviewer@example.test'),
  ('a6000000-0000-4000-8000-000000000010', 'assignment-read-only@example.test');

insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status, revoked_at
) values
  ('a6010000-0000-4000-8000-000000000001', 'a6000000-0000-4000-8000-000000000001', 'Assignment Owner', 'owner', 'ACTIVE', null),
  ('a6010000-0000-4000-8000-000000000002', 'a6000000-0000-4000-8000-000000000002', 'Assignment Manager', 'operations_manager', 'ACTIVE', null),
  ('a6010000-0000-4000-8000-000000000003', 'a6000000-0000-4000-8000-000000000003', 'Assignment Operator A', 'operator', 'ACTIVE', null),
  ('a6010000-0000-4000-8000-000000000004', 'a6000000-0000-4000-8000-000000000004', 'Assignment Operator B', 'operator', 'ACTIVE', null),
  ('a6010000-0000-4000-8000-000000000005', 'a6000000-0000-4000-8000-000000000005', 'Assignment Admin', 'admin', 'ACTIVE', null),
  ('a6010000-0000-4000-8000-000000000006', 'a6000000-0000-4000-8000-000000000006', 'Assignment Disabled', 'operator', 'DISABLED', null),
  ('a6010000-0000-4000-8000-000000000007', 'a6000000-0000-4000-8000-000000000007', 'Assignment Revoked', 'operator', 'REVOKED', clock_timestamp()),
  ('a6010000-0000-4000-8000-000000000008', 'a6000000-0000-4000-8000-000000000009', 'Assignment Reviewer', 'reviewer', 'ACTIVE', null),
  ('a6010000-0000-4000-8000-000000000009', 'a6000000-0000-4000-8000-000000000010', 'Assignment Read Only', 'read_only', 'ACTIVE', null);

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind,
  sdf_package, name, email, website_type, budget, timing,
  description, privacy_consent, status
) values
  ('a6100000-0000-4000-8000-000000000001', 'LWS-AAN-2099-0601', 'production', 'website', null,
   'Assignment fixture one', 'assignment-one@example.test', 'business', 'Meer dan EUR 6.000', 'flexible',
   'Assignment fixture one.', true, 'approved'),
  ('a6110000-0000-4000-8000-000000000002', 'LWS-AAN-2099-0602', 'production', 'slimme_documentenflow', 'start',
   'Assignment fixture two', 'assignment-two@example.test', null, null, null,
    'Assignment fixture two.', true, 'approved'),
    ('a6120000-0000-4000-8000-000000000003', 'LWS-AAN-2099-0603', 'production', 'website', null,
    'Replay fixture', 'assignment-replay@example.test', 'business', 'Meer dan EUR 6.000', 'flexible',
    'Disabled assignee replay fixture.', true, 'approved');

select ok(
  exists (
    select 1 from lws_internal.operator_dossier_assignments
    where quote_request_id = 'a6100000-0000-4000-8000-000000000001'
      and assignee_operator_id is null and revision = 0 and assigned_at is null
  ),
  'production dossier creation provisions canonical unassigned state'
);
select throws_ok(
  $$select public.get_operator_dossier_assignment_v1('LWS-AAN-2099-0601')$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'detail requires authenticated human'
);

select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000003',0,'a6200000-0000-4000-8000-000000000001',null)$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'assignment requires authenticated human'
);
select set_config('request.jwt.claim.sub', 'a6000000-0000-4000-8000-000000000008', true);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000003',0,'a6200000-0000-4000-8000-000000000002',null)$$,
  '42501', 'UNKNOWN_OPERATOR', 'customer identity cannot assign dossiers'
);
select set_config('request.jwt.claim.sub', 'a6000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000003',0,'a6200000-0000-4000-8000-000000000025',null)$$,
  '42501', 'DOSSIER_ASSIGNMENT_ACTOR_REQUIRED', 'active operator does not inherit assignment authority'
);
select set_config('request.jwt.claim.sub', 'a6000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000003',0,'a6200000-0000-4000-8000-000000000003',null)$$,
  '42501', 'DOSSIER_ASSIGNMENT_ACTOR_REQUIRED', 'active admin does not inherit assignment authority'
);
select set_config('request.jwt.claim.sub', 'a6000000-0000-4000-8000-000000000006', true);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000003',0,'a6200000-0000-4000-8000-000000000004',null)$$,
  '42501', 'OPERATOR_DISABLED', 'disabled actor cannot assign dossiers'
);
select set_config('request.jwt.claim.sub', 'a6000000-0000-4000-8000-000000000007', true);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000003',0,'a6200000-0000-4000-8000-000000000005',null)$$,
  '42501', 'OPERATOR_REVOKED', 'revoked actor cannot assign dossiers'
);
select set_config('request.jwt.claim.sub', 'a6000000-0000-4000-8000-000000000009', true);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000003',0,'a6200000-0000-4000-8000-000000000016',null)$$,
  '42501', 'DOSSIER_ASSIGNMENT_ACTOR_REQUIRED', 'reviewer actor cannot assign dossiers'
);
select set_config('request.jwt.claim.sub', 'a6000000-0000-4000-8000-000000000010', true);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000003',0,'a6200000-0000-4000-8000-000000000017',null)$$,
  '42501', 'DOSSIER_ASSIGNMENT_ACTOR_REQUIRED', 'read-only actor cannot assign dossiers'
);

select set_config('request.jwt.claim.sub', 'a6000000-0000-4000-8000-000000000001', true);
select is(
  public.get_operator_dossier_assignment_v1('LWS-AAN-2099-0601')->>'assignment_state',
  'UNASSIGNED', 'owner reads minimal unassigned detail'
);
select is(
  (select count(*)::integer from jsonb_object_keys(public.get_operator_dossier_assignment_v1('LWS-AAN-2099-0601'))),
  5, 'detail exposes exactly five assignment fields'
);
select ok(
  public.get_operator_dossier_assignment_v1('LWS-AAN-2099-0601')->>'assignment_state' = 'UNASSIGNED'
  and public.get_operator_dossier_assignment_v1('LWS-AAN-2099-0601')->'assignee_operator_id' = 'null'::jsonb
  and public.get_operator_dossier_assignment_v1('LWS-AAN-2099-0601')->'assignee_display_name' = 'null'::jsonb,
  'never-assigned detail represents UNASSIGNED with nullable assignee fields'
);
select set_config('request.jwt.claim.sub', 'a6000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.get_operator_dossier_assignment_v1('LWS-AAN-2099-0601')$$,
  '42501', 'DOSSIER_ASSIGNMENT_READER_REQUIRED', 'operator cannot read management assignment detail'
);

select set_config('request.jwt.claim.sub', 'a6000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000099',0,'a6200000-0000-4000-8000-000000000006',null)$$,
  '23503', 'ASSIGNEE_OPERATOR_NOT_FOUND', 'unknown assignee is rejected'
);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000006',0,'a6200000-0000-4000-8000-000000000007',null)$$,
  '42501', 'ASSIGNEE_NOT_ELIGIBLE', 'disabled operator assignee is rejected'
);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000005',0,'a6200000-0000-4000-8000-000000000026',null)$$,
  '42501', 'ASSIGNEE_NOT_ELIGIBLE', 'active admin assignee is rejected'
);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000002',0,'a6200000-0000-4000-8000-000000000008',null)$$,
  '42501', 'ASSIGNEE_NOT_ELIGIBLE', 'Operations Manager assignee is rejected'
);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000008',0,'a6200000-0000-4000-8000-000000000018',null)$$,
  '42501', 'ASSIGNEE_NOT_ELIGIBLE', 'reviewer assignee is rejected'
);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000009',0,'a6200000-0000-4000-8000-000000000019',null)$$,
  '42501', 'ASSIGNEE_NOT_ELIGIBLE', 'read-only assignee is rejected'
);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000001',0,'a6200000-0000-4000-8000-000000000020',null)$$,
  '42501', 'ASSIGNEE_NOT_ELIGIBLE', 'owner cannot self-assign through a role bypass'
);
select set_config('request.jwt.claim.sub', 'a6000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000002',0,'a6200000-0000-4000-8000-000000000021',null)$$,
  '42501', 'ASSIGNEE_NOT_ELIGIBLE', 'Operations Manager cannot self-assign through a role bypass'
);
select set_config('request.jwt.claim.sub', 'a6000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601',null,0,'a6200000-0000-4000-8000-000000000022',null)$$,
  '22023', 'INVALID_DOSSIER_ASSIGNMENT_COMMAND', 'NULL assignee mutation is denied'
);

create temporary table first_assignment_result as
select public.assign_operator_dossier_v1(
  'LWS-AAN-2099-0601', 'a6010000-0000-4000-8000-000000000003', 0,
  'a6200000-0000-4000-8000-000000000009', null
) as result;
select is((select result->>'no_change' from first_assignment_result), 'false', 'owner performs first assignment');
select is(
  (select revision from lws_internal.operator_dossier_assignments where quote_request_id = 'a6100000-0000-4000-8000-000000000001'),
  1::bigint, 'first assignment increments revision once'
);
select ok(
  exists (
    select 1 from lws_internal.operator_dossier_assignment_events
    where quote_request_id = 'a6100000-0000-4000-8000-000000000001'
      and event_type = 'ASSIGNED'
      and previous_assignee_operator_id is null
      and new_assignee_operator_id = 'a6010000-0000-4000-8000-000000000003'
      and actor_operator_id = 'a6010000-0000-4000-8000-000000000001'
      and reason is null and previous_revision = 0 and resulting_revision = 1
  ),
  'first assignment writes complete immutable transition evidence'
);
select is(
  (select count(*)::integer from public.commercial_operator_project_grants where operator_id = 'a6010000-0000-4000-8000-000000000003'),
  0, 'assignment creates no project grant'
);

select is(
  public.assign_operator_dossier_v1(
    'LWS-AAN-2099-0601', 'a6010000-0000-4000-8000-000000000003', 1,
    'a6200000-0000-4000-8000-000000000010', 'Ignored no-op context'
  )->>'no_change',
  'true', 'same assignee is an explicit no-op'
);
select ok(
  (select revision = 1 from lws_internal.operator_dossier_assignments where quote_request_id = 'a6100000-0000-4000-8000-000000000001')
  and (select count(*) = 1 from lws_internal.operator_dossier_assignment_events where quote_request_id = 'a6100000-0000-4000-8000-000000000001'),
  'same-assignee no-op changes neither revision nor audit events'
);
select is(
  public.assign_operator_dossier_v1(
    'LWS-AAN-2099-0601', 'a6010000-0000-4000-8000-000000000003', 1,
    'a6200000-0000-4000-8000-000000000010', 'Ignored no-op context'
  )->>'replayed',
  'true', 'same no-op command replays from the command ledger'
);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000003',1,'a6200000-0000-4000-8000-000000000010','Changed no-op context')$$,
  'P0001', 'IDEMPOTENCY_CONFLICT', 'changed replay is rejected'
);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000004',0,'a6200000-0000-4000-8000-000000000011','Stale reassignment')$$,
  '40001', 'CONCURRENT_MODIFICATION', 'stale expected revision is rejected'
);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0601','a6010000-0000-4000-8000-000000000004',1,'a6200000-0000-4000-8000-000000000012','   ')$$,
  '22023', 'REASSIGNMENT_REASON_REQUIRED', 'reassignment requires a nonblank reason'
);

select set_config('request.jwt.claim.sub', 'a6000000-0000-4000-8000-000000000002', true);
select is(
  public.assign_operator_dossier_v1(
    'LWS-AAN-2099-0601', 'a6010000-0000-4000-8000-000000000004', 1,
    'a6200000-0000-4000-8000-000000000013', '  Capacity rebalance  '
  )->>'revision',
  '2', 'Operations Manager can reassign an assigned dossier'
);
select ok(
  (select assignee_operator_id = 'a6010000-0000-4000-8000-000000000004' and revision = 2
   from lws_internal.operator_dossier_assignments where quote_request_id = 'a6100000-0000-4000-8000-000000000001'),
  'reassignment stores canonical operator identity and next revision'
);
select ok(
  exists (
    select 1 from lws_internal.operator_dossier_assignment_events
    where idempotency_key = 'a6200000-0000-4000-8000-000000000013'
      and event_type = 'REASSIGNED'
      and previous_assignee_operator_id = 'a6010000-0000-4000-8000-000000000003'
      and new_assignee_operator_id = 'a6010000-0000-4000-8000-000000000004'
      and actor_operator_id = 'a6010000-0000-4000-8000-000000000002'
      and reason = 'Capacity rebalance'
      and previous_revision = 1 and resulting_revision = 2
  ),
  'reassignment audit records actor, transition, normalized reason, and revisions'
);
select is(
  public.get_operator_dossier_assignment_v1('LWS-AAN-2099-0601')->>'assignee_display_name',
  'Assignment Operator B', 'manager detail identifies the assigned operator by safe display name'
);
select ok(
  not (public.get_operator_dossier_assignment_v1('LWS-AAN-2099-0601') ?| array['auth_user_id','email','role','status']),
  'detail leaks no account identity, email, role, or status'
);
select ok(
  (select assignee_operator_id = 'a6010000-0000-4000-8000-000000000004' and revision = 2
   from lws_internal.operator_dossier_assignments
   where quote_request_id = 'a6100000-0000-4000-8000-000000000001'),
  'failed NULL mutation cannot return an assigned dossier to UNASSIGNED'
);
select is(
  public.assign_operator_dossier_v1(
    'LWS-AAN-2099-0602', 'a6010000-0000-4000-8000-000000000004', 0,
    'a6200000-0000-4000-8000-000000000023', null
  )->>'assignment_state',
  'ASSIGNED', 'SDF dossier accepts the canonical assignment command'
);
select ok(
  public.get_operator_dossier_assignment_v1('LWS-AAN-2099-0602')->>'assignment_state' = 'ASSIGNED'
  and public.get_operator_dossier_assignment_v1('LWS-AAN-2099-0602')->>'assignee_operator_id' = 'a6010000-0000-4000-8000-000000000004'
  and public.get_operator_dossier_assignment_v1('LWS-AAN-2099-0602')->>'revision' = '1',
  'SDF detail uses the same assignment state shape as website detail'
);
select is(
  (select quote_request_id from lws_internal.operator_dossier_assignment_commands
   where idempotency_key = 'a6200000-0000-4000-8000-000000000023'),
  'a6110000-0000-4000-8000-000000000002'::uuid,
  'SDF assignment binds to canonical quote_request_id without a separate model'
);

select set_config('request.jwt.claim.sub', 'a6000000-0000-4000-8000-000000000001', true);
create temporary table disabled_assignee_replay_baseline as
select
  public.assign_operator_dossier_v1(
    'LWS-AAN-2099-0603', 'a6010000-0000-4000-8000-000000000003', 0,
    'a6200000-0000-4000-8000-000000000014', 'Replay remains historical'
  ) as result,
  0::bigint as revision,
  0::bigint as event_count,
  0::bigint as command_count;
update disabled_assignee_replay_baseline
set revision = (
      select revision from lws_internal.operator_dossier_assignments
      where quote_request_id = 'a6120000-0000-4000-8000-000000000003'
    ),
    event_count = (
      select count(*) from lws_internal.operator_dossier_assignment_events
      where quote_request_id = 'a6120000-0000-4000-8000-000000000003'
    ),
    command_count = (
      select count(*) from lws_internal.operator_dossier_assignment_commands
      where quote_request_id = 'a6120000-0000-4000-8000-000000000003'
    );
select public.set_commercial_operator_status_v1(
  'a6010000-0000-4000-8000-000000000003', 'DISABLED'
);
select ok(
  (select assignee_operator_id = 'a6010000-0000-4000-8000-000000000003'
          and revision = (select revision from disabled_assignee_replay_baseline)
   from lws_internal.operator_dossier_assignments
   where quote_request_id = 'a6120000-0000-4000-8000-000000000003')
  and
  (select count(*) from lws_internal.operator_dossier_assignment_events
   where quote_request_id = 'a6120000-0000-4000-8000-000000000003')
    = (select event_count from disabled_assignee_replay_baseline),
  'DISABLED assignee remains assigned without revision or event mutation'
);
select ok(
  public.get_operator_dossier_assignment_v1('LWS-AAN-2099-0603')->>'assignment_state' = 'ASSIGNED'
  and public.get_operator_dossier_assignment_v1('LWS-AAN-2099-0603')->>'assignee_operator_id' = 'a6010000-0000-4000-8000-000000000003',
  'detail continues to represent an assignment to a DISABLED assignee'
);
create temporary table disabled_assignee_replay_result as
select public.assign_operator_dossier_v1(
  'LWS-AAN-2099-0603', 'a6010000-0000-4000-8000-000000000003', 0,
  'a6200000-0000-4000-8000-000000000014', 'Replay remains historical'
) as result;
select ok(
  (select result - 'replayed' from disabled_assignee_replay_result)
    = (select result - 'replayed' from disabled_assignee_replay_baseline)
  and (select result->>'replayed' from disabled_assignee_replay_result) = 'true',
  'exact replay returns the stored assignment result after assignee disablement'
);
select ok(
  (select revision from lws_internal.operator_dossier_assignments
   where quote_request_id = 'a6120000-0000-4000-8000-000000000003')
    = (select revision from disabled_assignee_replay_baseline)
  and
  (select count(*) from lws_internal.operator_dossier_assignment_events
   where quote_request_id = 'a6120000-0000-4000-8000-000000000003')
    = (select event_count from disabled_assignee_replay_baseline)
  and
  (select count(*) from lws_internal.operator_dossier_assignment_commands
   where quote_request_id = 'a6120000-0000-4000-8000-000000000003')
    = (select command_count from disabled_assignee_replay_baseline),
  'disabled-assignee replay changes no revision, event, or command count'
);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0603','a6010000-0000-4000-8000-000000000003',0,'a6200000-0000-4000-8000-000000000014','Changed replay payload')$$,
  'P0001', 'IDEMPOTENCY_CONFLICT', 'changed replay conflicts before current assignee eligibility'
);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0603','a6010000-0000-4000-8000-000000000003',1,'a6200000-0000-4000-8000-000000000015','New command')$$,
  '42501', 'ASSIGNEE_NOT_ELIGIBLE', 'new command still rejects the disabled assignee'
);
select public.set_commercial_operator_status_v1(
  'a6010000-0000-4000-8000-000000000003', 'REVOKED'
);
select ok(
  (select assignee_operator_id = 'a6010000-0000-4000-8000-000000000003'
          and revision = (select revision from disabled_assignee_replay_baseline)
   from lws_internal.operator_dossier_assignments
   where quote_request_id = 'a6120000-0000-4000-8000-000000000003')
  and
  (select count(*) from lws_internal.operator_dossier_assignment_events
   where quote_request_id = 'a6120000-0000-4000-8000-000000000003')
    = (select event_count from disabled_assignee_replay_baseline),
  'REVOKED assignee remains assigned without revision or event mutation'
);
select ok(
  public.get_operator_dossier_assignment_v1('LWS-AAN-2099-0603')->>'assignment_state' = 'ASSIGNED'
  and public.get_operator_dossier_assignment_v1('LWS-AAN-2099-0603')->>'assignee_operator_id' = 'a6010000-0000-4000-8000-000000000003',
  'detail continues to represent an assignment to a REVOKED assignee'
);
select throws_ok(
  $$select public.assign_operator_dossier_v1('LWS-AAN-2099-0603','a6010000-0000-4000-8000-000000000003',1,'a6200000-0000-4000-8000-000000000024','New revoked command')$$,
  '42501', 'ASSIGNEE_NOT_ELIGIBLE', 'new command rejects the revoked assignee'
);

select throws_ok(
  $$update lws_internal.operator_dossier_assignment_events set reason = 'Tampered' where idempotency_key = 'a6200000-0000-4000-8000-000000000013'$$,
  '55000', 'OPERATOR_DOSSIER_ASSIGNMENT_LEDGER_APPEND_ONLY', 'assignment audit is append-only'
);
select throws_ok(
  $$delete from lws_internal.operator_dossier_assignment_commands where idempotency_key = 'a6200000-0000-4000-8000-000000000010'$$,
  '55000', 'OPERATOR_DOSSIER_ASSIGNMENT_LEDGER_APPEND_ONLY', 'assignment command ledger is append-only'
);
select throws_ok(
  $$update lws_internal.operator_dossier_assignments set assignee_operator_id = 'a6010000-0000-4000-8000-000000000003' where quote_request_id = 'a6100000-0000-4000-8000-000000000001'$$,
  '55000', 'DIRECT_ASSIGNMENT_STATE_WRITE_FORBIDDEN', 'direct reassignment state writes are denied'
);
select throws_ok(
  $$update lws_internal.operator_dossier_assignments set assignee_operator_id = null where quote_request_id = 'a6100000-0000-4000-8000-000000000001'$$,
  '55000', 'DIRECT_ASSIGNMENT_STATE_WRITE_FORBIDDEN', 'unassignment is not an exposed transition'
);
select throws_ok(
  $$select public.get_operator_dossier_assignment_v1('not-a-dossier')$$,
  '22023', 'INVALID_DOSSIER_REFERENCE', 'malformed dossier reference is rejected'
);
select throws_ok(
  $$select public.get_operator_dossier_assignment_v1('LWS-AAN-2099-9999')$$,
  'P0001', 'DOSSIER_NOT_FOUND', 'unknown dossier reference is rejected'
);
select is(
  (select quote_request_id from lws_internal.operator_dossier_assignment_commands where idempotency_key = 'a6200000-0000-4000-8000-000000000013'),
  'a6100000-0000-4000-8000-000000000001'::uuid,
  'command ledger binds visible reference to canonical quote_request_id'
);

select is(
  (select setup_connection_result from assignment_concurrency_fixture),
  'OK', 'concurrency setup connection opens'
);
select ok(
  (select fixture.setup_result = 'INSERT 0 1'
      and (select count(*) = 3
           from auth.users
           where id in (fixture.owner_user_id, fixture.race_a_user_id, fixture.race_b_user_id))
      and (select count(*) = 3
           from public.commercial_operators
           where operator_id in (fixture.owner_operator_id, fixture.race_a_operator_id, fixture.race_b_operator_id))
      and exists (
        select 1
        from public.quote_requests
        where id = fixture.quote_request_id
          and application_reference = fixture.application_reference
      )
   from assignment_concurrency_fixture as fixture),
  'committed concurrency fixture is created outside the pgTAP transaction'
);
select is(
  extensions.dblink_connect(
    'assignment_race_a',
    'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=assignment_race_a'
  ),
  'OK', 'first assignment race connection opens'
);
select is(
  extensions.dblink_connect(
    'assignment_race_b',
    'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=assignment_race_b'
  ),
  'OK', 'second assignment race connection opens'
);
create temporary table assignment_race_pids(backend_pid integer not null) on commit drop;
insert into assignment_race_pids
select backend_pid
from extensions.dblink('assignment_race_b', 'select pg_backend_pid()') as connection(backend_pid integer);
select is(
  extensions.dblink_exec(
    'assignment_race_a',
    (select format('begin; set request.jwt.claim.sub = %L', owner_user_id)
     from assignment_concurrency_fixture)
  ),
  'SET', 'first assignment race transaction starts'
);
select is(
  (select result->>'revision'
   from extensions.dblink(
     'assignment_race_a',
     (select format($sql$select public.assign_operator_dossier_v1(
       %L, %L, 0,
       %L, null
     )$sql$, application_reference, race_a_operator_id, race_a_idempotency_key)
      from assignment_concurrency_fixture)
   ) as assignment(result jsonb)),
  '1', 'first concurrent assignment succeeds while retaining its row lock'
);
select is(
  extensions.dblink_exec(
    'assignment_race_b',
    (select format('set request.jwt.claim.sub = %L', owner_user_id)
     from assignment_concurrency_fixture)
  ),
  'SET', 'second assignment race identity is configured'
);
select ok(
  extensions.dblink_send_query(
    'assignment_race_b',
    (select format($sql$select public.assign_operator_dossier_v1(
      %L, %L, 0,
      %L, null
    )$sql$, application_reference, race_b_operator_id, race_b_idempotency_key)
     from assignment_concurrency_fixture)
  ) = 1,
  'second concurrent assignment starts'
);
select ok(
  pg_temp.wait_for_assignment_lock_v1((select backend_pid from assignment_race_pids)),
  'second assignment waits on the dossier assignment row lock'
);
select is(extensions.dblink_exec('assignment_race_a', 'commit'), 'COMMIT', 'first assignment commits first');
select throws_ok(
  $$select * from extensions.dblink_get_result('assignment_race_b') as assignment(result jsonb)$$,
  '40001', 'CONCURRENT_MODIFICATION', 'second assignment resumes and loses on expected revision'
);
select ok(
  (select assignment.assignee_operator_id = fixture.race_a_operator_id
      and assignment.revision = 1
   from lws_internal.operator_dossier_assignments as assignment
   join assignment_concurrency_fixture as fixture using (quote_request_id))
  and
  (select count(*) = 1
   from lws_internal.operator_dossier_assignment_events as event
   join assignment_concurrency_fixture as fixture using (quote_request_id)),
  'concurrent race leaves one winner, one revision, and one event'
);
select is(extensions.dblink_disconnect('assignment_race_a'), 'OK', 'first race connection closes');
select is(extensions.dblink_disconnect('assignment_race_b'), 'OK', 'second race connection closes');
select lives_ok(
  format($test$select extensions.dblink_exec(
    'assignment_concurrency_setup',
    $cleanup$
      set session_replication_role = replica;
      delete from lws_internal.operator_dossier_assignment_commands where quote_request_id = %L;
      delete from lws_internal.operator_dossier_assignment_events where quote_request_id = %L;
      delete from lws_internal.operator_dossier_assignments where quote_request_id = %L;
      delete from lws_internal.operator_dossier_states where quote_request_id = %L;
      delete from public.quote_requests where id = %L;
      delete from public.commercial_operators where operator_id in (
        %L,
        %L,
        %L
      );
      delete from auth.users where id in (
        %L,
        %L,
        %L
      );
      set session_replication_role = origin;
    $cleanup$
  )$test$,
    quote_request_id, quote_request_id, quote_request_id,
    quote_request_id, quote_request_id,
    owner_operator_id, race_a_operator_id, race_b_operator_id,
    owner_user_id, race_a_user_id, race_b_user_id
  ),
  'committed concurrency fixture is removed'
)
from assignment_concurrency_fixture;
select is(extensions.dblink_disconnect('assignment_concurrency_setup'), 'OK', 'concurrency setup connection closes');

select * from finish();
rollback;
