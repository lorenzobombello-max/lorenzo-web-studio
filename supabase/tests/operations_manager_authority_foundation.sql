begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set local search_path = public, extensions;
select no_plan();

create function pg_temp.wait_for_lock_v1(p_backend_pid integer)
returns boolean
language plpgsql
as $$
declare
  v_deadline timestamptz := clock_timestamp() + interval '5 seconds';
begin
  loop
    if exists (
      select 1
      from pg_catalog.pg_locks
      where pid = p_backend_pid
        and not granted
    ) then
      return true;
    end if;
    if clock_timestamp() >= v_deadline then
      return false;
    end if;
  end loop;
end;
$$;

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.commercial_operators'::regclass
      and conname = 'commercial_operators_role_check'
      and pg_get_constraintdef(oid) like '%operations_manager%'
      and pg_get_constraintdef(oid) like '%owner%'
      and pg_get_constraintdef(oid) like '%admin%'
      and pg_get_constraintdef(oid) like '%operator%'
      and pg_get_constraintdef(oid) like '%reviewer%'
      and pg_get_constraintdef(oid) like '%read_only%'
  ),
  'operations_manager is valid while all existing roles remain valid'
);
select has_table('lws_internal', 'operations_manager_role_events', 'private role authority events exist');
select has_function('lws_internal', 'guard_operations_manager_project_grant_v1', array[]::text[], 'role-aware project grant guard exists');
select trigger_is(
  'public', 'commercial_operator_project_grants',
  'trg_operations_manager_project_grant_guard',
  'lws_internal', 'guard_operations_manager_project_grant_v1',
  'active project grants are guarded at the table boundary'
);
select ok(
  not has_table_privilege('anon', 'lws_internal.operations_manager_role_events', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'lws_internal.operations_manager_role_events', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'lws_internal.operations_manager_role_events', 'select,insert,update,delete'),
  'runtime roles have no direct role-event authority'
);
select ok(
  has_function_privilege('authenticated', 'public.appoint_operations_manager_v1(uuid,text)', 'execute')
  and has_function_privilege('authenticated', 'public.revoke_operations_manager_v1(uuid,text,text)', 'execute')
  and has_function_privilege('authenticated', 'public.get_operations_manager_session_v1()', 'execute')
  and not has_function_privilege('anon', 'public.appoint_operations_manager_v1(uuid,text)', 'execute')
  and not has_function_privilege('service_role', 'public.appoint_operations_manager_v1(uuid,text)', 'execute'),
  'only authenticated humans can enter Operations Manager authority RPCs'
);

insert into auth.users(id, email) values
  ('e7000000-0000-4000-8000-000000000001', 'operations-owner@example.test'),
  ('e7000000-0000-4000-8000-000000000002', 'operations-admin@example.test'),
  ('e7000000-0000-4000-8000-000000000003', 'operations-operator@example.test'),
  ('e7000000-0000-4000-8000-000000000004', 'operations-reviewer@example.test'),
  ('e7000000-0000-4000-8000-000000000005', 'operations-disabled@example.test'),
  ('e7000000-0000-4000-8000-000000000006', 'operations-revoked@example.test');

insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status, revoked_at) values
  ('e7010000-0000-4000-8000-000000000001', 'e7000000-0000-4000-8000-000000000001', 'Operations Owner', 'owner', 'ACTIVE', null),
  ('e7010000-0000-4000-8000-000000000002', 'e7000000-0000-4000-8000-000000000002', 'Operations Admin', 'admin', 'ACTIVE', null),
  ('e7010000-0000-4000-8000-000000000003', 'e7000000-0000-4000-8000-000000000003', 'Operations Operator', 'operator', 'ACTIVE', null),
  ('e7010000-0000-4000-8000-000000000004', 'e7000000-0000-4000-8000-000000000004', 'Operations Reviewer', 'reviewer', 'ACTIVE', null),
  ('e7010000-0000-4000-8000-000000000005', 'e7000000-0000-4000-8000-000000000005', 'Operations Disabled', 'operator', 'DISABLED', null),
  ('e7010000-0000-4000-8000-000000000006', 'e7000000-0000-4000-8000-000000000006', 'Operations Revoked', 'operator', 'REVOKED', clock_timestamp());

set local session_replication_role = replica;
insert into public.commercial_projects(
  project_id, customer_id, quotation_issuance_id, acceptance_id,
  accepted_total_minor, currency, m1_minor, m2_minor, m3_minor, current_state, revision
) values (
  'e7100000-0000-4000-8000-000000000001',
  'e7110000-0000-4000-8000-000000000001',
  'e7120000-0000-4000-8000-000000000001',
  'e7130000-0000-4000-8000-000000000001',
  10000, 'EUR', 4000, 4000, 2000, 'QUOTE_ACCEPTED', 1
), (
  'e7100000-0000-4000-8000-000000000002',
  'e7110000-0000-4000-8000-000000000002',
  'e7120000-0000-4000-8000-000000000002',
  'e7130000-0000-4000-8000-000000000002',
  10000, 'EUR', 4000, 4000, 2000, 'QUOTE_ACCEPTED', 1
), (
  'e7100000-0000-4000-8000-000000000003',
  'e7110000-0000-4000-8000-000000000003',
  'e7120000-0000-4000-8000-000000000003',
  'e7130000-0000-4000-8000-000000000003',
  10000, 'EUR', 4000, 4000, 2000, 'QUOTE_ACCEPTED', 1
);
set local session_replication_role = origin;

insert into public.commercial_operator_project_grants(
  operator_id, project_id, access_level, granted_by
) values
  ('e7010000-0000-4000-8000-000000000003', 'e7100000-0000-4000-8000-000000000001', 'operator', 'e7010000-0000-4000-8000-000000000001'),
  ('e7010000-0000-4000-8000-000000000004', 'e7100000-0000-4000-8000-000000000001', 'reviewer', 'e7010000-0000-4000-8000-000000000001');
select ok(
  (select revoked_at is null from public.commercial_operator_project_grants
   where operator_id = 'e7010000-0000-4000-8000-000000000003'
     and project_id = 'e7100000-0000-4000-8000-000000000001'),
  'appointment target starts with an active project grant'
);

select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.appoint_operations_manager_v1('e7010000-0000-4000-8000-000000000003', 'Unauthenticated appointment.')$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'unauthenticated appointment is denied'
);
select set_config('request.jwt.claim.sub', 'e7000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.appoint_operations_manager_v1('e7010000-0000-4000-8000-000000000003', 'Admin appointment.')$$,
  '42501', 'OWNER_REQUIRED', 'admin cannot appoint an Operations Manager'
);
select set_config('request.jwt.claim.sub', 'e7000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.appoint_operations_manager_v1('e7010000-0000-4000-8000-000000000004', 'Operator appointment.')$$,
  '42501', 'OWNER_REQUIRED', 'operator cannot appoint an Operations Manager'
);
select is(
  (select operator_id::text from public.resolve_commercial_operator_authorization_v1(
    'e7100000-0000-4000-8000-000000000001', 'READ_PROJECT', false
  )),
  'e7010000-0000-4000-8000-000000000003',
  'active retained project grant authorizes project read before appointment'
);
select set_config('request.jwt.claim.sub', 'e7000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$select public.appoint_operations_manager_v1('e7010000-0000-4000-8000-000000000001', 'Owner target.')$$,
  '42501', 'OWNER_ROLE_IMMUTABLE', 'owner role cannot be changed by appointment'
);
select throws_ok(
  $$select public.appoint_operations_manager_v1('e7010000-0000-4000-8000-000000000005', 'Disabled target.')$$,
  '42501', 'TARGET_OPERATOR_NOT_ACTIVE', 'disabled target cannot be appointed'
);
select throws_ok(
  $$select public.appoint_operations_manager_v1('e7010000-0000-4000-8000-000000000006', 'Revoked target.')$$,
  '42501', 'TARGET_OPERATOR_NOT_ACTIVE', 'revoked target cannot be appointed'
);

select is(
  public.appoint_operations_manager_v1(
    'e7010000-0000-4000-8000-000000000003',
    'Owner appoints daily operations authority.'
  )->>'role',
  'operations_manager',
  'Owner can appoint an ACTIVE commercial operator'
);
select is(
  (select role from public.commercial_operators where operator_id = 'e7010000-0000-4000-8000-000000000003'),
  'operations_manager',
  'appointment stores the Operations Manager role'
);
select ok(
  (select revoked_at is not null from public.commercial_operator_project_grants
   where operator_id = 'e7010000-0000-4000-8000-000000000003'
     and project_id = 'e7100000-0000-4000-8000-000000000001'),
  'appointment revokes every active target project grant'
);
select ok(
  (select revoked_at is null from public.commercial_operator_project_grants
   where operator_id = 'e7010000-0000-4000-8000-000000000004'
     and project_id = 'e7100000-0000-4000-8000-000000000001'),
  'appointment preserves unrelated operator project grants'
);
select ok(
  exists (
    select 1 from lws_internal.operations_manager_role_events
    where target_operator_id = 'e7010000-0000-4000-8000-000000000003'
      and actor_auth_user_id = 'e7000000-0000-4000-8000-000000000001'
      and previous_role = 'operator'
      and new_role = 'operations_manager'
      and event_type = 'APPOINTED'
      and reason = 'Owner appoints daily operations authority.'
      and occurred_at is not null
  ),
  'appointment event records actor, transition, reason, and timestamp'
);
select throws_ok(
  $$update lws_internal.operations_manager_role_events set reason = 'Changed'$$,
  '55000', 'OPERATIONS_MANAGER_ROLE_EVENT_APPEND_ONLY', 'role events cannot be updated'
);
select throws_ok(
  $$delete from lws_internal.operations_manager_role_events$$,
  '55000', 'OPERATIONS_MANAGER_ROLE_EVENT_APPEND_ONLY', 'role events cannot be deleted'
);

select set_config('request.jwt.claim.sub', 'e7000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select * from public.resolve_commercial_operator_authorization_v1('e7100000-0000-4000-8000-000000000001', 'READ_PROJECT', false)$$,
  '42501', 'PROJECT_SCOPE_DENIED', 'Operations Manager cannot read a project through its old grant'
);
select throws_ok(
  $$select * from public.resolve_commercial_operator_authorization_v1('e7100000-0000-4000-8000-000000000001', 'prepare_milestone_1', true)$$,
  '42501', 'PROJECT_SCOPE_DENIED', 'Operations Manager cannot mutate a project through its old grant'
);
select throws_ok(
  $$insert into public.commercial_operator_project_grants(operator_id, project_id, access_level, granted_by) values('e7010000-0000-4000-8000-000000000003', 'e7100000-0000-4000-8000-000000000002', 'read_only', 'e7010000-0000-4000-8000-000000000001')$$,
  '42501', 'OPERATIONS_MANAGER_PROJECT_GRANT_DENIED', 'active project grant insert for Operations Manager is denied'
);
insert into public.commercial_operator_project_grants(
  operator_id, project_id, access_level, granted_by, revoked_at
) values (
  'e7010000-0000-4000-8000-000000000003',
  'e7100000-0000-4000-8000-000000000002',
  'read_only',
  'e7010000-0000-4000-8000-000000000001',
  clock_timestamp()
);
select ok(
  (select revoked_at is not null from public.commercial_operator_project_grants
   where operator_id = 'e7010000-0000-4000-8000-000000000003'
     and project_id = 'e7100000-0000-4000-8000-000000000002'),
  'revoked historical project grant for Operations Manager is allowed'
);
select throws_ok(
  $$update public.commercial_operator_project_grants set revoked_at = null where operator_id = 'e7010000-0000-4000-8000-000000000003' and project_id = 'e7100000-0000-4000-8000-000000000002'$$,
  '42501', 'OPERATIONS_MANAGER_PROJECT_GRANT_DENIED', 'revoked Operations Manager grant cannot be reactivated'
);
insert into public.commercial_operator_project_grants(
  operator_id, project_id, access_level, granted_by
) values (
  'e7010000-0000-4000-8000-000000000004',
  'e7100000-0000-4000-8000-000000000003',
  'reviewer',
  'e7010000-0000-4000-8000-000000000001'
);
select throws_ok(
  $$update public.commercial_operator_project_grants set operator_id = 'e7010000-0000-4000-8000-000000000003' where operator_id = 'e7010000-0000-4000-8000-000000000004' and project_id = 'e7100000-0000-4000-8000-000000000003'$$,
  '42501', 'OPERATIONS_MANAGER_PROJECT_GRANT_DENIED', 'active grant cannot be reassigned to Operations Manager'
);
select is(
  public.get_operations_manager_session_v1(),
  jsonb_build_object(
    'operator_id', 'e7010000-0000-4000-8000-000000000003'::uuid,
    'role', 'operations_manager'
  ),
  'ACTIVE Operations Manager receives minimal identity proof'
);
select is(
  (select count(*)::integer from jsonb_object_keys(public.get_operations_manager_session_v1())),
  2,
  'session probe discloses only operator_id and role'
);
select throws_ok(
  $$select public.set_commercial_operator_status_v1('e7010000-0000-4000-8000-000000000004', 'DISABLED')$$,
  '42501', 'OWNER_REQUIRED', 'Operations Manager inherits no owner status authority'
);
select throws_ok(
  $$select public.assert_internal_e2e_application_reader_v1()$$,
  '42501', 'APPLICATION_SCOPE_DENIED', 'Operations Manager inherits no dossier read authority'
);

select set_config('request.jwt.claim.sub', 'e7000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$select public.get_operations_manager_session_v1()$$,
  '42501', 'OPERATIONS_MANAGER_REQUIRED', 'probe rejects every other active role'
);
select set_config('request.jwt.claim.sub', 'e7000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select public.get_operations_manager_session_v1()$$,
  '42501', 'OPERATOR_DISABLED', 'probe rejects disabled operator'
);
select set_config('request.jwt.claim.sub', 'e7000000-0000-4000-8000-000000000006', true);
select throws_ok(
  $$select public.get_operations_manager_session_v1()$$,
  '42501', 'OPERATOR_REVOKED', 'probe rejects revoked operator'
);

select set_config('request.jwt.claim.sub', 'e7000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.revoke_operations_manager_v1('e7010000-0000-4000-8000-000000000003', 'Admin revocation.')$$,
  '42501', 'OWNER_REQUIRED', 'non-Owner cannot revoke an Operations Manager'
);
select set_config('request.jwt.claim.sub', 'e7000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$select public.revoke_operations_manager_v1('e7010000-0000-4000-8000-000000000003', 'Invalid owner fallback.', 'owner')$$,
  '22023', 'INVALID_OPERATIONS_MANAGER_FALLBACK_ROLE', 'owner fallback is denied'
);
select throws_ok(
  $$select public.revoke_operations_manager_v1('e7010000-0000-4000-8000-000000000003', 'Invalid manager fallback.', 'operations_manager')$$,
  '22023', 'INVALID_OPERATIONS_MANAGER_FALLBACK_ROLE', 'operations_manager fallback is denied'
);
select throws_ok(
  $$select public.revoke_operations_manager_v1('e7010000-0000-4000-8000-000000000003', 'Unproven admin fallback.', 'admin')$$,
  '22023', 'INVALID_OPERATIONS_MANAGER_FALLBACK_ROLE', 'admin fallback is denied fail closed'
);
select is(
  public.revoke_operations_manager_v1(
    'e7010000-0000-4000-8000-000000000003',
    'Owner returns manager to safe default role.'
  )->>'role',
  'operator',
  'revocation defaults to operator'
);
select ok(
  (select revoked_at is not null from public.commercial_operator_project_grants
   where operator_id = 'e7010000-0000-4000-8000-000000000003'
     and project_id = 'e7100000-0000-4000-8000-000000000001'),
  'revocation to operator does not restore the old project grant'
);
select ok(
  exists (
    select 1 from lws_internal.operations_manager_role_events
    where target_operator_id = 'e7010000-0000-4000-8000-000000000003'
      and actor_auth_user_id = 'e7000000-0000-4000-8000-000000000001'
      and previous_role = 'operations_manager'
      and new_role = 'operator'
      and event_type = 'REVOKED'
      and reason = 'Owner returns manager to safe default role.'
  ),
  'revocation event records the correct role transition'
);

select public.appoint_operations_manager_v1(
  'e7010000-0000-4000-8000-000000000004',
  'Owner appoints reviewer for explicit fallback proof.'
);
select is(
  public.revoke_operations_manager_v1(
    'e7010000-0000-4000-8000-000000000004',
    'Owner selects safe reviewer fallback.',
    'reviewer'
  )->>'role',
  'reviewer',
  'explicit reviewer fallback works'
);
select ok(
  (select role = 'reviewer' from public.commercial_operators
   where operator_id = 'e7010000-0000-4000-8000-000000000004')
  and
  (select revoked_at is not null from public.commercial_operator_project_grants
   where operator_id = 'e7010000-0000-4000-8000-000000000004'
     and project_id = 'e7100000-0000-4000-8000-000000000001'),
  'reviewer fallback stores the role without restoring the old project grant'
);
select set_config('request.jwt.claim.sub', 'e7000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$select public.get_operations_manager_session_v1()$$,
  '42501', 'OPERATIONS_MANAGER_REQUIRED', 'reviewer fallback removes management probe authority'
);
select set_config('request.jwt.claim.sub', 'e7000000-0000-4000-8000-000000000001', true);
select public.appoint_operations_manager_v1(
  'e7010000-0000-4000-8000-000000000004',
  'Owner reappoints reviewer for read-only fallback proof.'
);
select is(
  public.revoke_operations_manager_v1(
    'e7010000-0000-4000-8000-000000000004',
    'Owner selects safe read-only fallback.',
    'read_only'
  )->>'role',
  'read_only',
  'explicit read-only fallback works'
);

set local role authenticated;
select throws_ok(
  $$update lws_internal.operations_manager_role_events set reason = 'Direct mutation'$$,
  '42501', null, 'authenticated cannot mutate role events directly'
);
reset role;

select is(
  (select count(*)::integer from information_schema.routine_privileges
   where specific_schema = 'public'
     and routine_name in ('appoint_operations_manager_v1', 'revoke_operations_manager_v1', 'get_operations_manager_session_v1')
     and grantee = 'authenticated'),
  3,
  'slice exposes only the three explicit authenticated entrypoints'
);
select ok(
  not has_function_privilege('authenticated', 'public.bootstrap_first_commercial_owner_v1(uuid,text,text)', 'execute')
  and not has_table_privilege('authenticated', 'public.commercial_operators', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.commercial_operator_project_grants', 'select,insert,update,delete'),
  'Operations Manager role adds no owner bootstrap, operator table, or project grant authority'
);

select is(
  extensions.dblink_connect(
    'om_concurrency_setup',
    'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=om_concurrency_setup'
  ),
  'OK',
  'concurrency fixture connection opens'
);
select lives_ok(
  $test$select extensions.dblink_exec(
    'om_concurrency_setup',
    $setup$
      insert into auth.users(id, email) values
        ('e8000000-0000-4000-8000-000000000001', 'om-concurrency-owner@example.test'),
        ('e8000000-0000-4000-8000-000000000002', 'om-concurrency-target-a@example.test'),
        ('e8000000-0000-4000-8000-000000000003', 'om-concurrency-target-b@example.test');
      insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
        ('e8010000-0000-4000-8000-000000000001', 'e8000000-0000-4000-8000-000000000001', 'Concurrency Owner', 'owner', 'ACTIVE'),
        ('e8010000-0000-4000-8000-000000000002', 'e8000000-0000-4000-8000-000000000002', 'Concurrency Target A', 'operator', 'ACTIVE'),
        ('e8010000-0000-4000-8000-000000000003', 'e8000000-0000-4000-8000-000000000003', 'Concurrency Target B', 'operator', 'ACTIVE');
      set session_replication_role = replica;
      insert into public.commercial_projects(
        project_id, customer_id, quotation_issuance_id, acceptance_id,
        accepted_total_minor, currency, m1_minor, m2_minor, m3_minor, current_state, revision
      ) values
        ('e8100000-0000-4000-8000-000000000001', 'e8110000-0000-4000-8000-000000000001', 'e8120000-0000-4000-8000-000000000001', 'e8130000-0000-4000-8000-000000000001', 10000, 'EUR', 4000, 4000, 2000, 'QUOTE_ACCEPTED', 1),
        ('e8100000-0000-4000-8000-000000000002', 'e8110000-0000-4000-8000-000000000002', 'e8120000-0000-4000-8000-000000000002', 'e8130000-0000-4000-8000-000000000002', 10000, 'EUR', 4000, 4000, 2000, 'QUOTE_ACCEPTED', 1);
      set session_replication_role = origin;
    $setup$
  )$test$,
  'committed concurrency fixtures are created outside the pgTAP transaction'
);

select is(extensions.dblink_connect('om_scenario_a_appointment', 'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=om_scenario_a_appointment'), 'OK', 'Scenario A appointment connection opens');
select is(extensions.dblink_connect('om_scenario_a_grant', 'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=om_scenario_a_grant'), 'OK', 'Scenario A grant connection opens');
create temporary table om_concurrency_pids(connection_name text primary key, backend_pid integer not null);
insert into om_concurrency_pids
select 'scenario_a_grant', backend_pid
from extensions.dblink('om_scenario_a_grant', 'select pg_backend_pid()') as connection(backend_pid integer);
select is(extensions.dblink_exec('om_scenario_a_appointment', 'begin; set request.jwt.claim.sub = ''e8000000-0000-4000-8000-000000000001'''), 'SET', 'Scenario A appointment transaction starts');
select is(
  (select result->>'role' from extensions.dblink(
    'om_scenario_a_appointment',
    $$select public.appoint_operations_manager_v1('e8010000-0000-4000-8000-000000000002', 'Scenario A appointment wins.')$$
  ) as appointment(result jsonb)),
  'operations_manager',
  'Scenario A appointment completes while retaining its transaction lock'
);
select ok(
  extensions.dblink_send_query(
    'om_scenario_a_grant',
    $$insert into public.commercial_operator_project_grants(operator_id, project_id, access_level, granted_by) values('e8010000-0000-4000-8000-000000000002', 'e8100000-0000-4000-8000-000000000001', 'read_only', 'e8010000-0000-4000-8000-000000000001') returning operator_id$$
  ) = 1,
  'Scenario A concurrent grant insert starts'
);
select ok(pg_temp.wait_for_lock_v1((select backend_pid from om_concurrency_pids where connection_name = 'scenario_a_grant')), 'Scenario A observes grant insert waiting on the appointment parent lock');
select is(extensions.dblink_exec('om_scenario_a_appointment', 'commit'), 'COMMIT', 'Scenario A appointment commits first');
select throws_ok(
  $$select * from extensions.dblink_get_result('om_scenario_a_grant') as result(operator_id uuid)$$,
  '42501', 'OPERATIONS_MANAGER_PROJECT_GRANT_DENIED', 'Scenario A resumed active grant insert is denied'
);
select is(
  (select count(*)::integer from public.commercial_operator_project_grants where operator_id = 'e8010000-0000-4000-8000-000000000002' and revoked_at is null),
  0,
  'Scenario A leaves no active Operations Manager grant'
);

select is(extensions.dblink_connect('om_scenario_b_grant', 'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=om_scenario_b_grant'), 'OK', 'Scenario B grant connection opens');
select is(extensions.dblink_connect('om_scenario_b_appointment', 'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=om_scenario_b_appointment'), 'OK', 'Scenario B appointment connection opens');
insert into om_concurrency_pids
select 'scenario_b_appointment', backend_pid
from extensions.dblink('om_scenario_b_appointment', 'select pg_backend_pid()') as connection(backend_pid integer);
select is(extensions.dblink_exec('om_scenario_b_grant', 'begin'), 'BEGIN', 'Scenario B grant transaction starts');
select is(
  (select operator_id::text from extensions.dblink(
    'om_scenario_b_grant',
    $$insert into public.commercial_operator_project_grants(operator_id, project_id, access_level, granted_by) values('e8010000-0000-4000-8000-000000000003', 'e8100000-0000-4000-8000-000000000002', 'operator', 'e8010000-0000-4000-8000-000000000001') returning operator_id$$
  ) as grant_insert(operator_id uuid)),
  'e8010000-0000-4000-8000-000000000003',
  'Scenario B active grant is inserted while retaining the parent lock'
);
select is(extensions.dblink_exec('om_scenario_b_appointment', 'set request.jwt.claim.sub = ''e8000000-0000-4000-8000-000000000001'''), 'SET', 'Scenario B appointment identity is configured');
select ok(
  extensions.dblink_send_query(
    'om_scenario_b_appointment',
    $$select public.appoint_operations_manager_v1('e8010000-0000-4000-8000-000000000003', 'Scenario B grant wins.')$$
  ) = 1,
  'Scenario B appointment starts'
);
select ok(pg_temp.wait_for_lock_v1((select backend_pid from om_concurrency_pids where connection_name = 'scenario_b_appointment')), 'Scenario B observes appointment waiting on the grant parent lock');
select is(extensions.dblink_exec('om_scenario_b_grant', 'commit'), 'COMMIT', 'Scenario B grant commits first');
select is(
  (select result->>'role' from extensions.dblink_get_result('om_scenario_b_appointment') as appointment(result jsonb)),
  'operations_manager',
  'Scenario B appointment resumes and succeeds'
);
select ok(
  (select operator.role = 'operations_manager' and project_grant.revoked_at is not null
   from public.commercial_operators as operator
   join public.commercial_operator_project_grants as project_grant on project_grant.operator_id = operator.operator_id
   where operator.operator_id = 'e8010000-0000-4000-8000-000000000003'
     and project_grant.project_id = 'e8100000-0000-4000-8000-000000000002'),
  'Scenario B appointment neutralizes the grant that committed first'
);

select extensions.dblink_disconnect('om_scenario_a_appointment');
select extensions.dblink_disconnect('om_scenario_a_grant');
select extensions.dblink_disconnect('om_scenario_b_grant');
select extensions.dblink_disconnect('om_scenario_b_appointment');
select lives_ok(
  $test$select extensions.dblink_exec(
    'om_concurrency_setup',
    $cleanup$
      set session_replication_role = replica;
      delete from lws_internal.operations_manager_role_events where target_operator_id in ('e8010000-0000-4000-8000-000000000002', 'e8010000-0000-4000-8000-000000000003');
      delete from public.commercial_operator_project_grants where operator_id in ('e8010000-0000-4000-8000-000000000002', 'e8010000-0000-4000-8000-000000000003');
      delete from public.commercial_operators where operator_id in ('e8010000-0000-4000-8000-000000000001', 'e8010000-0000-4000-8000-000000000002', 'e8010000-0000-4000-8000-000000000003');
      delete from auth.users where id in ('e8000000-0000-4000-8000-000000000001', 'e8000000-0000-4000-8000-000000000002', 'e8000000-0000-4000-8000-000000000003');
      delete from public.commercial_projects where project_id in ('e8100000-0000-4000-8000-000000000001', 'e8100000-0000-4000-8000-000000000002');
      set session_replication_role = origin;
    $cleanup$
  )$test$,
  'committed concurrency fixtures are removed'
);
select extensions.dblink_disconnect('om_concurrency_setup');

select * from finish();
rollback;