begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public',
  'get_operations_manager_roster_v1',
  array[]::text[],
  'Operations Manager roster RPC exists'
);
select ok(
  exists (
    select 1
    from pg_proc as procedure
    where procedure.oid = 'public.get_operations_manager_roster_v1()'::regprocedure
      and procedure.prosecdef
      and procedure.provolatile = 's'
      and procedure.proconfig = array['search_path=public, auth, pg_catalog']
  ),
  'roster RPC is stable SECURITY DEFINER with a fixed safe search_path'
);
select ok(
  has_function_privilege('authenticated', 'public.get_operations_manager_roster_v1()', 'execute')
  and not has_function_privilege('anon', 'public.get_operations_manager_roster_v1()', 'execute')
  and not has_function_privilege('service_role', 'public.get_operations_manager_roster_v1()', 'execute')
  and not has_function_privilege('public', 'public.get_operations_manager_roster_v1()', 'execute'),
  'only authenticated callers receive roster RPC execute privilege'
);
select ok(
  not has_table_privilege('anon', 'public.commercial_operators', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.commercial_operators', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.commercial_operators', 'select,insert,update,delete'),
  'roster migration does not broaden direct commercial operator table privileges'
);
select ok(
  not has_table_privilege('anon', 'lws_internal.operations_manager_role_events', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'lws_internal.operations_manager_role_events', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'lws_internal.operations_manager_role_events', 'select,insert,update,delete'),
  'roster migration does not broaden direct authority history privileges'
);
select ok(
  (select prosrc !~* '\m(insert|update|delete)\M'
   from pg_proc
   where oid = 'public.get_operations_manager_roster_v1()'::regprocedure),
  'roster runtime contains no mutation statement'
);
select ok(
  (select prosrc !~* 'select\s+\*'
   from pg_proc
   where oid = 'public.get_operations_manager_roster_v1()'::regprocedure),
  'roster RPC contains no SELECT star dependency'
);

insert into auth.users(id, email) values
  ('e8000000-0000-4000-8000-000000000001', 'roster-owner@example.test'),
  ('e8000000-0000-4000-8000-000000000002', 'roster-manager@example.test'),
  ('e8000000-0000-4000-8000-000000000003', 'roster-admin@example.test'),
  ('e8000000-0000-4000-8000-000000000004', 'roster-operator@example.test'),
  ('e8000000-0000-4000-8000-000000000005', 'roster-reviewer@example.test'),
  ('e8000000-0000-4000-8000-000000000006', 'roster-read-only@example.test'),
  ('e8000000-0000-4000-8000-000000000007', 'roster-disabled-manager@example.test'),
  ('e8000000-0000-4000-8000-000000000008', 'roster-revoked-manager@example.test'),
  ('e8000000-0000-4000-8000-000000000009', 'roster-unknown@example.test');

insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status, revoked_at
) values
  ('e8010000-0000-4000-8000-000000000001', 'e8000000-0000-4000-8000-000000000001', 'Roster Owner', 'owner', 'ACTIVE', null),
  ('e8010000-0000-4000-8000-000000000002', 'e8000000-0000-4000-8000-000000000002', 'Roster Manager', 'operations_manager', 'ACTIVE', null),
  ('e8010000-0000-4000-8000-000000000003', 'e8000000-0000-4000-8000-000000000003', 'Roster Admin', 'admin', 'ACTIVE', null),
  ('e8010000-0000-4000-8000-000000000004', 'e8000000-0000-4000-8000-000000000004', 'Roster Operator', 'operator', 'ACTIVE', null),
  ('e8010000-0000-4000-8000-000000000005', 'e8000000-0000-4000-8000-000000000005', 'Roster Reviewer', 'reviewer', 'ACTIVE', null),
  ('e8010000-0000-4000-8000-000000000006', 'e8000000-0000-4000-8000-000000000006', 'Roster Read Only', 'read_only', 'ACTIVE', null),
  ('e8010000-0000-4000-8000-000000000007', 'e8000000-0000-4000-8000-000000000007', 'Roster Disabled Manager', 'operations_manager', 'DISABLED', null),
  ('e8010000-0000-4000-8000-000000000008', 'e8000000-0000-4000-8000-000000000008', 'Roster Revoked Manager', 'operations_manager', 'REVOKED', clock_timestamp());

insert into lws_internal.operations_manager_role_events(
  target_operator_id, actor_auth_user_id, previous_role, new_role,
  event_type, reason, occurred_at
) values
  (
    'e8010000-0000-4000-8000-000000000002',
    'e8000000-0000-4000-8000-000000000001',
    'operator', 'operations_manager', 'APPOINTED', 'Manager A appointed.',
    '2026-08-24T10:00:00Z'
  ),
  (
    'e8010000-0000-4000-8000-000000000002',
    'e8000000-0000-4000-8000-000000000001',
    'operations_manager', 'operator', 'REVOKED', 'Manager A revoked.',
    '2026-08-24T11:00:00Z'
  ),
  (
    'e8010000-0000-4000-8000-000000000003',
    'e8000000-0000-4000-8000-000000000001',
    'admin', 'operations_manager', 'APPOINTED', 'Operator B separate event.',
    '2026-08-24T10:30:00Z'
  );

set local session_replication_role = replica;
insert into public.commercial_projects(
  project_id, customer_id, quotation_issuance_id, acceptance_id,
  accepted_total_minor, currency, m1_minor, m2_minor, m3_minor, current_state, revision
) values (
  'e8100000-0000-4000-8000-000000000001',
  'e8110000-0000-4000-8000-000000000001',
  'e8120000-0000-4000-8000-000000000001',
  'e8130000-0000-4000-8000-000000000001',
  10000, 'EUR', 4000, 4000, 2000, 'QUOTE_ACCEPTED', 1
);
set local session_replication_role = origin;

select set_config('request.jwt.claim.sub', 'e8000000-0000-4000-8000-000000000001', true);
select ok(
  jsonb_typeof(public.get_operations_manager_roster_v1()) = 'array'
  and jsonb_array_length((
    select row_data->'history'
    from jsonb_array_elements(public.get_operations_manager_roster_v1()) as roster(row_data)
    where row_data->>'operator_id' = 'e8010000-0000-4000-8000-000000000002'
  )) = 2,
  'ACTIVE owner can read the global roster with authority history'
);
select set_config('request.jwt.claim.sub', 'e8000000-0000-4000-8000-000000000002', true);
select ok(
  jsonb_typeof(public.get_operations_manager_roster_v1()) = 'array'
  and jsonb_array_length((
    select row_data->'history'
    from jsonb_array_elements(public.get_operations_manager_roster_v1()) as roster(row_data)
    where row_data->>'operator_id' = 'e8010000-0000-4000-8000-000000000002'
  )) = 2,
  'ACTIVE Operations Manager can read the global roster with authority history'
);

select set_config('request.jwt.claim.sub', 'e8000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.get_operations_manager_roster_v1()$$,
  '42501', 'OPERATIONS_MANAGER_ROSTER_READER_REQUIRED', 'admin cannot read the roster'
);
select set_config('request.jwt.claim.sub', 'e8000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$select public.get_operations_manager_roster_v1()$$,
  '42501', 'OPERATIONS_MANAGER_ROSTER_READER_REQUIRED', 'operator cannot read the roster'
);
select set_config('request.jwt.claim.sub', 'e8000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select public.get_operations_manager_roster_v1()$$,
  '42501', 'OPERATIONS_MANAGER_ROSTER_READER_REQUIRED', 'reviewer cannot read the roster'
);
select set_config('request.jwt.claim.sub', 'e8000000-0000-4000-8000-000000000006', true);
select throws_ok(
  $$select public.get_operations_manager_roster_v1()$$,
  '42501', 'OPERATIONS_MANAGER_ROSTER_READER_REQUIRED', 'read_only operator cannot read the roster'
);
select set_config('request.jwt.claim.sub', 'e8000000-0000-4000-8000-000000000007', true);
select throws_ok(
  $$select public.get_operations_manager_roster_v1()$$,
  '42501', 'OPERATOR_DISABLED', 'DISABLED Operations Manager cannot read the roster'
);
select set_config('request.jwt.claim.sub', 'e8000000-0000-4000-8000-000000000008', true);
select throws_ok(
  $$select public.get_operations_manager_roster_v1()$$,
  '42501', 'OPERATOR_REVOKED', 'REVOKED Operations Manager cannot read the roster'
);
select set_config('request.jwt.claim.sub', 'e8000000-0000-4000-8000-000000000009', true);
select throws_ok(
  $$select public.get_operations_manager_roster_v1()$$,
  '42501', 'UNKNOWN_OPERATOR', 'human without server-side operator authority cannot read the roster'
);
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.get_operations_manager_roster_v1()$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'unauthenticated caller cannot read the roster'
);

select set_config('request.jwt.claim.sub', 'e8000000-0000-4000-8000-000000000002', true);
select ok(
  not exists (
    select 1
    from jsonb_array_elements(public.get_operations_manager_roster_v1()) as roster(row_data)
    cross join lateral jsonb_object_keys(roster.row_data) as key_name
    where key_name not in ('operator_id', 'display_name', 'role', 'status', 'history')
  )
  and not exists (
    select 1
    from jsonb_array_elements(public.get_operations_manager_roster_v1()) as roster(row_data)
    where (select count(*) from jsonb_object_keys(roster.row_data)) <> 5
  ),
  'every roster row has exactly the five allowlisted fields'
);
select ok(
  not (public.get_operations_manager_roster_v1()::text ~* 'auth_user_id|email|actor|reason|project_id|customer|dossier|financial|grant|jwt|session'),
  'roster output contains no forbidden identity, history, business, grant, or session fields'
);
select ok(
  exists (
    select 1 from jsonb_array_elements(public.get_operations_manager_roster_v1()) as roster(row_data)
    where row_data->>'operator_id' = 'e8010000-0000-4000-8000-000000000001'
      and row_data->>'display_name' = 'Roster Owner'
      and row_data->>'role' = 'owner'
      and row_data->>'status' = 'ACTIVE'
      and row_data->'history' = '[]'::jsonb
  ),
  'owner row is visible with display_name, opaque operator_id, and empty history'
);
select ok(
  exists (
    select 1 from jsonb_array_elements(public.get_operations_manager_roster_v1()) as roster(row_data)
    where row_data->>'operator_id' = 'e8010000-0000-4000-8000-000000000007'
      and row_data->>'status' = 'DISABLED'
  ),
  'DISABLED target remains visible'
);
select ok(
  exists (
    select 1 from jsonb_array_elements(public.get_operations_manager_roster_v1()) as roster(row_data)
    where row_data->>'operator_id' = 'e8010000-0000-4000-8000-000000000008'
      and row_data->>'status' = 'REVOKED'
  ),
  'REVOKED target remains visible'
);
select ok(
  (select count(distinct row_data->>'role')
   from jsonb_array_elements(public.get_operations_manager_roster_v1()) as roster(row_data)
   where row_data->>'operator_id' like 'e8010000-%') = 6,
  'owner, manager, admin, operator, reviewer, and read_only target roles are visible'
);
select ok(
  not exists (
    select 1
    from jsonb_array_elements(public.get_operations_manager_roster_v1()) as roster(row_data)
    cross join lateral jsonb_array_elements(roster.row_data->'history') as history(event_data)
    cross join lateral jsonb_object_keys(history.event_data) as key_name
    where key_name not in ('event_type', 'occurred_at')
  )
  and not exists (
    select 1
    from jsonb_array_elements(public.get_operations_manager_roster_v1()) as roster(row_data)
    cross join lateral jsonb_array_elements(roster.row_data->'history') as history(event_data)
    where (select count(*) from jsonb_object_keys(history.event_data)) <> 2
  ),
  'every history item contains exactly event_type and occurred_at'
);
select is(
  (select row_data->'history'
   from jsonb_array_elements(public.get_operations_manager_roster_v1()) as roster(row_data)
   where row_data->>'operator_id' = 'e8010000-0000-4000-8000-000000000002'),
  jsonb_build_array(
    jsonb_build_object('event_type', 'APPOINTED', 'occurred_at', '2026-08-24T10:00:00+00:00'::timestamptz),
    jsonb_build_object('event_type', 'REVOKED', 'occurred_at', '2026-08-24T11:00:00+00:00'::timestamptz)
  ),
  'history is target-bound and deterministically ordered by occurred_at ascending'
);
select ok(
  not exists (
    select 1
    from jsonb_array_elements(public.get_operations_manager_roster_v1()) as roster(row_data)
    cross join lateral jsonb_array_elements(roster.row_data->'history') as history(event_data)
    where roster.row_data->>'operator_id' = 'e8010000-0000-4000-8000-000000000003'
      and history.event_data->>'event_type' = 'REVOKED'
  ),
  'event history from operator A does not leak into operator B'
);
select ok(
  not (public.get_operations_manager_roster_v1()::text ~* 'target_operator_id|actor_auth_user_id|reason|previous_role|new_role|event_id'),
  'history exposes no join key, actor, reason, transition fields, or event identifier'
);

select throws_ok(
  $$select public.appoint_operations_manager_v1('e8010000-0000-4000-8000-000000000003', 'Roster must not appoint.')$$,
  '42501', 'OWNER_REQUIRED', 'roster reader gains no appointment authority'
);
select throws_ok(
  $$select public.revoke_operations_manager_v1('e8010000-0000-4000-8000-000000000002', 'Roster must not revoke.', 'operator')$$,
  '42501', 'OWNER_REQUIRED', 'roster reader gains no revocation authority'
);
select throws_ok(
  $$select public.set_commercial_operator_status_v1('e8010000-0000-4000-8000-000000000003', 'DISABLED')$$,
  '42501', 'OWNER_REQUIRED', 'roster reader gains no operator status mutation authority'
);
select throws_ok(
  $$select * from public.resolve_commercial_operator_authorization_v1('e8100000-0000-4000-8000-000000000001', 'READ_PROJECT', false)$$,
  '42501', 'PROJECT_SCOPE_DENIED', 'roster reader gains no project read authority'
);
select throws_ok(
  $$select * from public.resolve_commercial_operator_authorization_v1('e8100000-0000-4000-8000-000000000001', 'prepare_milestone_1', true)$$,
  '42501', 'PROJECT_SCOPE_DENIED', 'roster reader gains no project mutation authority'
);
select throws_ok(
  $$insert into public.commercial_operator_project_grants(operator_id, project_id, access_level) values('e8010000-0000-4000-8000-000000000002', 'e8100000-0000-4000-8000-000000000001', 'read_only')$$,
  '42501', 'OPERATIONS_MANAGER_PROJECT_GRANT_DENIED', 'roster reader cannot receive an active project grant'
);
select throws_ok(
  $$select public.execute_operator_dossier_lifecycle_command_v1('e8200000-0000-4000-8000-000000000001', 'ARCHIVED', 0, 'e8210000-0000-4000-8000-000000000001', 'Roster must not mutate dossiers.', 'e8220000-0000-4000-8000-000000000001')$$,
  '42501', 'APPLICATION_SCOPE_DENIED', 'roster reader gains no dossier lifecycle authority'
);
select throws_ok(
  $$select public.get_commercial_project_view_v2('e8100000-0000-4000-8000-000000000001')$$,
  '42501', 'PROJECT_SCOPE_DENIED', 'roster reader gains no project or finance projection authority'
);

select * from finish();
rollback;