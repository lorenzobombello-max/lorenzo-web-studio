begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('public', 'operator_workspace_sessions', 'Operator workspace epochs persist server-side');
select columns_are(
  'public', 'operator_workspace_sessions',
  array['workspace_id','operator_id','epoch','master_window_id','renewal_token_hash','lease_expires_at','status','created_at','updated_at','revoked_at'],
  'workspace authority stores no auth token, JWT, password, or role snapshot'
);
select has_table('public', 'operator_workspace_window_claims', 'managed module slots persist server-side');
select columns_are(
  'public', 'operator_workspace_window_claims',
  array['workspace_id','window_id','module_key','claimed_at','slot_key'],
  'window claims contain only workspace module and slot identity'
);
select has_function('public', 'acquire_operator_workspace_v1', array['uuid'], 'master workspace acquisition exists');
select has_function('public', 'renew_operator_workspace_lease_v1', array['uuid','bigint','uuid','uuid'], 'capability-bound master renewal exists');
select has_function('public', 'join_operator_workspace_v1', array['uuid','bigint','uuid','text'], 'managed child join exists');
select has_function('public', 'join_operator_workspace_v1', array['uuid','bigint','uuid','text','text'], 'generic module-slot child join exists');
select has_function('public', 'get_operator_workspace_status_v1', array['uuid','bigint','uuid'], 'child lease validation exists');
select has_function('public', 'get_operator_calendar_v1', array['date','date'], 'narrow caller-authorized calendar projection exists');
select has_function('public', 'list_operator_workforce_v1', array[]::text[], 'narrow caller-authorized Personnel projection exists');
select has_function('public', 'revoke_operator_workspace_v1', array['uuid','bigint','uuid','uuid'], 'master shutdown authority exists');
select ok(
  not has_table_privilege('anon', 'public.operator_workspace_sessions', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.operator_workspace_sessions', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.operator_workspace_sessions', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.operator_workspace_window_claims', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.operator_workspace_window_claims', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.operator_workspace_window_claims', 'select,insert,update,delete'),
  'runtime roles have no direct workspace-table authority'
);
select ok(
  has_function_privilege('authenticated', 'public.acquire_operator_workspace_v1(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.renew_operator_workspace_lease_v1(uuid,bigint,uuid,uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.join_operator_workspace_v1(uuid,bigint,uuid,text)', 'execute')
  and has_function_privilege('authenticated', 'public.join_operator_workspace_v1(uuid,bigint,uuid,text,text)', 'execute')
  and has_function_privilege('authenticated', 'public.get_operator_workspace_status_v1(uuid,bigint,uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.get_operator_calendar_v1(date,date)', 'execute')
  and has_function_privilege('authenticated', 'public.list_operator_workforce_v1()', 'execute')
  and has_function_privilege('authenticated', 'public.revoke_operator_workspace_v1(uuid,bigint,uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.acquire_operator_workspace_v1(uuid)', 'execute'),
  'only authenticated humans can enter workspace RPCs'
);
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.operator_workspace_sessions'::regclass)
  and (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.operator_workspace_window_claims'::regclass),
  'workspace authority tables have forced RLS'
);

insert into auth.users(id, email) values
  ('f3000000-0000-4000-8000-000000000001', 'workspace-master@example.test'),
  ('f3000000-0000-4000-8000-000000000002', 'workspace-other@example.test'),
  ('f3000000-0000-4000-8000-000000000003', 'workspace-disabled@example.test');

insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('f3010000-0000-4000-8000-000000000001', 'f3000000-0000-4000-8000-000000000001', 'Workspace Master', 'owner', 'ACTIVE'),
  ('f3010000-0000-4000-8000-000000000002', 'f3000000-0000-4000-8000-000000000002', 'Workspace Other', 'admin', 'ACTIVE'),
  ('f3010000-0000-4000-8000-000000000003', 'f3000000-0000-4000-8000-000000000003', 'Workspace Disabled', 'owner', 'DISABLED');

select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.acquire_operator_workspace_v1('f3020000-0000-4000-8000-000000000001')$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'unauthenticated workspace acquisition is denied'
);

select set_config('request.jwt.claim.sub', 'f3000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.acquire_operator_workspace_v1('f3020000-0000-4000-8000-000000000003')$$,
  '42501', 'OPERATOR_NOT_ACTIVE', 'DISABLED Operator cannot acquire a workspace'
);
select throws_ok(
  $$select public.get_operator_calendar_v1('2026-09-01', '2026-09-07')$$,
  '42501', 'OPERATOR_NOT_ACTIVE', 'DISABLED Operator cannot read standalone calendar authority'
);
select throws_ok(
  $$select public.list_operator_workforce_v1()$$,
  '42501', 'OPERATOR_NOT_ACTIVE', 'DISABLED Operator cannot read standalone Personnel authority'
);
select throws_ok(
  $$select public.join_operator_workspace_v1('f3020000-0000-4000-8000-000000000003', 1, 'f3030000-0000-4000-8000-000000000008', 'recruitment', 'main')$$,
  '42501', 'OPERATOR_NOT_ACTIVE', 'DISABLED Operator cannot join standalone Recruitment authority'
);
select throws_ok(
  $$select public.join_operator_workspace_v1('f3020000-0000-4000-8000-000000000003', 1, 'f3030000-0000-4000-8000-000000000012', 'workforce', 'main')$$,
  '42501', 'OPERATOR_NOT_ACTIVE', 'DISABLED Operator cannot join standalone Personnel authority'
);
select throws_ok(
  $$select public.join_operator_workspace_v1('f3020000-0000-4000-8000-000000000003', 1, 'f3030000-0000-4000-8000-000000000014', 'finance', 'main')$$,
  '42501', 'OPERATOR_NOT_ACTIVE', 'DISABLED Operator cannot join standalone Finance authority'
);
select throws_ok(
  $$select public.join_operator_workspace_v1('f3020000-0000-4000-8000-000000000003', 1, 'f3030000-0000-4000-8000-000000000016', 'dossiers', 'main')$$,
  '42501', 'OPERATOR_NOT_ACTIVE', 'DISABLED Operator cannot join standalone Dossiers authority'
);

create temporary table workspace_fixture as
select null::uuid workspace_id, null::bigint epoch, null::uuid renewal_token;
truncate workspace_fixture;

select set_config('request.jwt.claim.sub', 'f3000000-0000-4000-8000-000000000001', true);
insert into workspace_fixture
select
  (result->>'workspace_id')::uuid,
  (result->>'epoch')::bigint,
  (result->>'renewal_token')::uuid
from (select public.acquire_operator_workspace_v1('f3020000-0000-4000-8000-000000000001') result) acquired;

select ok((select workspace_id is not null from workspace_fixture), 'active authorized Operator acquires a workspace');
select ok((select renewal_token is not null from workspace_fixture), 'new master receives an ephemeral renewal capability');
select ok(
  (select lease_expires_at > created_at and lease_expires_at <= created_at + interval '15 seconds 500 milliseconds'
   from public.operator_workspace_sessions where workspace_id = (select workspace_id from workspace_fixture)),
  'server timestamp establishes a lease no longer than fifteen seconds'
);
select is(
  (select count(*)::integer from public.operator_workspace_sessions where operator_id = 'f3010000-0000-4000-8000-000000000001' and status = 'ACTIVE'),
  1,
  'one Operator has one active workspace epoch'
);
select ok(
  (public.acquire_operator_workspace_v1('f3020000-0000-4000-8000-000000000099')->>'acquired')::boolean = false,
  'a duplicate dashboard observes the existing epoch without becoming a second master'
);
select is(
  public.acquire_operator_workspace_v1('f3020000-0000-4000-8000-000000000099')->>'renewal_token',
  null,
  'duplicate master response never exposes the renewal capability'
);

select throws_ok(
  format(
    'select public.renew_operator_workspace_lease_v1(%L, %s, %L, %L)',
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3020000-0000-4000-8000-000000000002', gen_random_uuid()
  ),
  '42501', 'MASTER_RENEWAL_NOT_AUTHORIZED', 'child cannot impersonate the master or renew liveness'
);
select ok(
  (public.renew_operator_workspace_lease_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3020000-0000-4000-8000-000000000001', (select renewal_token from workspace_fixture)
  )->>'valid')::boolean,
  'master renews its own valid lease with its memory-only capability'
);

select set_config('request.jwt.claim.sub', 'f3000000-0000-4000-8000-000000000002', true);
select throws_ok(
  format(
    'select public.renew_operator_workspace_lease_v1(%L, %s, %L, %L)',
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3020000-0000-4000-8000-000000000001', (select renewal_token from workspace_fixture)
  ),
  '42501', 'WORKSPACE_NOT_AVAILABLE', 'unrelated Operator cannot renew another workspace'
);
select throws_ok(
  format(
    'select public.join_operator_workspace_v1(%L, %s, %L, %L)',
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000002', 'calendar'
  ),
  '42501', 'WORKSPACE_NOT_AVAILABLE', 'unrelated Operator cannot join another workspace'
);
select throws_ok(
  format(
    'select public.join_operator_workspace_v1(%L, %s, %L, %L, %L)',
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000009', 'recruitment', 'main'
  ),
  '42501', 'WORKSPACE_MODULE_NOT_AUTHORIZED', 'active non-owner cannot join owner-only Recruitment'
);
select throws_ok(
  format(
    'select public.join_operator_workspace_v1(%L, %s, %L, %L, %L)',
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000014', 'finance', 'main'
  ),
  '42501', 'WORKSPACE_MODULE_NOT_AUTHORIZED', 'active non-owner cannot join owner-only Finance'
);
select throws_ok(
  format(
    'select public.join_operator_workspace_v1(%L, %s, %L, %L, %L)',
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000016', 'dossiers', 'main'
  ),
  '42501', 'WORKSPACE_MODULE_NOT_AUTHORIZED', 'active non-owner cannot join owner-only Dossiers'
);

select set_config('request.jwt.claim.sub', 'f3000000-0000-4000-8000-000000000001', true);
select ok(
  jsonb_typeof(public.get_operator_calendar_v1('2026-09-01', '2026-09-07')->'employees') = 'array',
  'authorized owner reads the narrow standalone calendar projection'
);
select ok(
  jsonb_typeof(public.list_operator_workforce_v1()->'employees') = 'array',
  'authorized owner reads the narrow standalone Personnel projection'
);
select ok(
  (public.join_operator_workspace_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000001', 'messages'
  )->>'joined')::boolean,
  'valid child joins its own Operator workspace and claims messages'
);
select ok(
  (public.join_operator_workspace_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000006', 'calendar', 'main'
  )->>'joined')::boolean,
  'calendar child independently joins the same workspace beside messages'
);
select ok(
  not (public.join_operator_workspace_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000007', 'calendar', 'main'
  )->>'joined')::boolean,
  'duplicate calendar module and slot claim is rejected deterministically'
);
select ok(
  (public.join_operator_workspace_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000010', 'recruitment', 'main'
  )->>'joined')::boolean,
  'owner Recruitment child independently joins the same workspace'
);
select ok(
  not (public.join_operator_workspace_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000011', 'recruitment', 'main'
  )->>'joined')::boolean,
  'duplicate Recruitment module and slot claim is rejected deterministically'
);
select ok(
  (public.join_operator_workspace_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000012', 'workforce', 'main'
  )->>'joined')::boolean,
  'Personnel child independently joins the same workspace'
);
select ok(
  not (public.join_operator_workspace_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000013', 'workforce', 'main'
  )->>'joined')::boolean,
  'duplicate Personnel module and slot claim is rejected deterministically'
);
select ok(
  not (public.join_operator_workspace_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000002', 'messages'
  )->>'joined')::boolean,
  'duplicate Berichtenkamer claim is rejected deterministically'
);
select ok(
  (public.join_operator_workspace_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000003', 'finance', 'main'
  )->>'joined')::boolean,
  'owner Finance child independently joins the same workspace'
);
select ok(
  not (public.join_operator_workspace_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000015', 'finance', 'main'
  )->>'joined')::boolean,
  'duplicate Finance module and slot claim is rejected deterministically'
);
select ok(
  (public.join_operator_workspace_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000016', 'dossiers', 'main'
  )->>'joined')::boolean,
  'owner Dossiers child independently joins the same workspace'
);
select ok(
  not (public.join_operator_workspace_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000017', 'dossiers', 'main'
  )->>'joined')::boolean,
  'duplicate Dossiers module and slot claim is rejected deterministically'
);
select ok(
  (public.join_operator_workspace_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000004', 'messages', 'secondary'
  )->>'joined')::boolean,
  'a distinct future-approved slot has an independent deterministic claim'
);
select ok(
  not (public.join_operator_workspace_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000005', 'messages', 'secondary'
  )->>'joined')::boolean,
  'duplicate module and slot claim is rejected deterministically'
);
update public.commercial_operators
set role = 'operator'
where auth_user_id = 'f3000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.get_operator_calendar_v1('2026-09-01', '2026-09-07')$$,
  '42501', 'WORKFORCE_MANAGEMENT_READER_REQUIRED', 'unauthorized Operator cannot read standalone calendar authority'
);
select throws_ok(
  $$select public.list_operator_workforce_v1()$$,
  '42501', 'WORKFORCE_MANAGEMENT_READER_REQUIRED', 'unauthorized Operator cannot read standalone Personnel authority'
);
select ok(
  not (public.get_operator_workspace_status_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000001'
  )->>'valid')::boolean,
  'active child loses server validity immediately when current module role authority is removed'
);
select is(
  public.get_operator_workspace_status_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000001'
  )->>'status',
  'MODULE_NOT_AUTHORIZED',
  'role loss returns a generic module authorization status without browser override'
);
select ok(
  not (public.get_operator_workspace_status_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000006'
  )->>'valid')::boolean,
  'calendar child loses validity immediately when its current role authority is removed'
);
select ok(
  not (public.get_operator_workspace_status_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000010'
  )->>'valid')::boolean,
  'Recruitment child loses validity immediately when owner authority is removed'
);
select ok(
  not (public.get_operator_workspace_status_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000012'
  )->>'valid')::boolean,
  'Personnel child loses validity immediately when management-reader authority is removed'
);
update public.commercial_operators
set role = 'owner'
where auth_user_id = 'f3000000-0000-4000-8000-000000000001';
select ok(
  (public.get_operator_workspace_status_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000001'
  )->>'valid')::boolean,
  'joined child can validate the server lease'
);
select ok(
  (public.get_operator_workspace_status_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000010'
  )->>'valid')::boolean,
  'Recruitment child regains validity only after current owner authority is restored'
);
select ok(
  (public.get_operator_workspace_status_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000012'
  )->>'valid')::boolean,
  'Personnel child regains validity only after management-reader authority is restored'
);
select ok(
  (public.revoke_operator_workspace_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3020000-0000-4000-8000-000000000001', (select renewal_token from workspace_fixture)
  )->>'revoked')::boolean,
  'master shutdown revokes the workspace server-side'
);
select ok(
  not (public.get_operator_workspace_status_v1(
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000001'
  )->>'valid')::boolean,
  'revoked workspace is invalid for an existing child'
);
select throws_ok(
  format(
    'select public.join_operator_workspace_v1(%L, %s, %L, %L)',
    (select workspace_id from workspace_fixture), (select epoch from workspace_fixture),
    'f3030000-0000-4000-8000-000000000003', 'messages'
  ),
  '42501', 'WORKSPACE_NOT_ACTIVE', 'revoked workspace rejects a new child'
);

select * from finish();
rollback;