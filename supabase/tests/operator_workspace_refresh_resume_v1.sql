begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public', 'resume_operator_workspace_v1', array['uuid','bigint','uuid','uuid'],
  'master refresh resume authority exists'
);
select ok(
  has_function_privilege('authenticated', 'public.resume_operator_workspace_v1(uuid,bigint,uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.resume_operator_workspace_v1(uuid,bigint,uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.resume_operator_workspace_v1(uuid,bigint,uuid,uuid)', 'execute'),
  'only authenticated humans can request workspace resume'
);

insert into auth.users(id, email) values
  ('f3600000-0000-4000-8000-000000000001', 'workspace-refresh-owner@example.test'),
  ('f3600000-0000-4000-8000-000000000002', 'workspace-refresh-other@example.test');

insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('f3610000-0000-4000-8000-000000000001', 'f3600000-0000-4000-8000-000000000001', 'Refresh Owner', 'owner', 'ACTIVE'),
  ('f3610000-0000-4000-8000-000000000002', 'f3600000-0000-4000-8000-000000000002', 'Refresh Other', 'owner', 'ACTIVE');

create temporary table refresh_workspace_fixture(
  workspace_id uuid,
  epoch bigint,
  master_window_id uuid,
  renewal_token uuid
);

select set_config('request.jwt.claim.sub', 'f3600000-0000-4000-8000-000000000001', true);
insert into refresh_workspace_fixture
select
  (result->>'workspace_id')::uuid,
  (result->>'epoch')::bigint,
  (result->>'master_window_id')::uuid,
  (result->>'renewal_token')::uuid
from (select public.acquire_operator_workspace_v1('f3620000-0000-4000-8000-000000000001') result) acquired;

select ok(
  (select lease_expires_at <= created_at + interval '13 seconds 500 milliseconds'
   from public.operator_workspace_sessions where workspace_id = (select workspace_id from refresh_workspace_fixture)),
  'refresh architecture preserves the thirteen-second crash ceiling'
);

select ok(
  bool_and((public.join_operator_workspace_v1(
    (select workspace_id from refresh_workspace_fixture),
    (select epoch from refresh_workspace_fixture),
    window_id, module_key, 'main'
  )->>'joined')::boolean),
  'all six managed child modules join before master refresh'
)
from (values
  ('f3630000-0000-4000-8000-000000000001'::uuid, 'dossiers'),
  ('f3630000-0000-4000-8000-000000000002'::uuid, 'messages'),
  ('f3630000-0000-4000-8000-000000000003'::uuid, 'finance'),
  ('f3630000-0000-4000-8000-000000000004'::uuid, 'calendar'),
  ('f3630000-0000-4000-8000-000000000005'::uuid, 'workforce'),
  ('f3630000-0000-4000-8000-000000000006'::uuid, 'recruitment')
) children(window_id, module_key);

select set_config('request.jwt.claim.sub', 'f3600000-0000-4000-8000-000000000002', true);
select ok(
  not (public.resume_operator_workspace_v1(
    (select workspace_id from refresh_workspace_fixture),
    (select epoch from refresh_workspace_fixture),
    (select master_window_id from refresh_workspace_fixture),
    'f3620000-0000-4000-8000-000000000099'
  )->>'resumed')::boolean,
  'different Operator cannot reclaim an existing workspace'
);

select set_config('request.jwt.claim.sub', 'f3600000-0000-4000-8000-000000000001', true);
create temporary table first_resume as
select public.resume_operator_workspace_v1(
  (select workspace_id from refresh_workspace_fixture),
  (select epoch from refresh_workspace_fixture),
  (select master_window_id from refresh_workspace_fixture),
  'f3620000-0000-4000-8000-000000000002'
) result;

select ok((select (result->>'resumed')::boolean from first_resume), 'normal master refresh resumes server authority');
select is(
  (select result->>'workspace_id' from first_resume),
  (select workspace_id::text from refresh_workspace_fixture),
  'first refresh preserves workspace id'
);
select is(
  (select (result->>'epoch')::bigint from first_resume),
  (select epoch from refresh_workspace_fixture),
  'first refresh preserves workspace epoch'
);
select throws_ok(
  format(
    'select public.renew_operator_workspace_lease_v1(%L, %s, %L, %L)',
    (select workspace_id from refresh_workspace_fixture), (select epoch from refresh_workspace_fixture),
    (select master_window_id from refresh_workspace_fixture), (select renewal_token from refresh_workspace_fixture)
  ),
  '42501', 'MASTER_RENEWAL_NOT_AUTHORIZED', 'previous master capability is invalid immediately after refresh'
);
select ok(
  bool_and((public.get_operator_workspace_status_v1(
    (select workspace_id from refresh_workspace_fixture),
    (select epoch from refresh_workspace_fixture), window_id
  )->>'valid')::boolean),
  'all six existing children remain server-valid after master refresh'
)
from (values
  ('f3630000-0000-4000-8000-000000000001'::uuid),
  ('f3630000-0000-4000-8000-000000000002'::uuid),
  ('f3630000-0000-4000-8000-000000000003'::uuid),
  ('f3630000-0000-4000-8000-000000000004'::uuid),
  ('f3630000-0000-4000-8000-000000000005'::uuid),
  ('f3630000-0000-4000-8000-000000000006'::uuid)
) children(window_id);

update refresh_workspace_fixture
set master_window_id = 'f3620000-0000-4000-8000-000000000002',
    renewal_token = (select (result->>'renewal_token')::uuid from first_resume);

create temporary table second_resume as
select public.resume_operator_workspace_v1(
  (select workspace_id from refresh_workspace_fixture),
  (select epoch from refresh_workspace_fixture),
  (select master_window_id from refresh_workspace_fixture),
  'f3620000-0000-4000-8000-000000000003'
) result;

select ok((select (result->>'resumed')::boolean from second_resume), 'repeated master refresh remains stable');
select ok(
  not (public.resume_operator_workspace_v1(
    (select workspace_id from refresh_workspace_fixture),
    (select epoch from refresh_workspace_fixture),
    'f3620000-0000-4000-8000-000000000001',
    'f3620000-0000-4000-8000-000000000004'
  )->>'resumed')::boolean,
  'stale master hint cannot reclaim transferred authority'
);

update refresh_workspace_fixture
set master_window_id = 'f3620000-0000-4000-8000-000000000003',
    renewal_token = (select (result->>'renewal_token')::uuid from second_resume);

select ok(
  (public.revoke_operator_workspace_v1(
    (select workspace_id from refresh_workspace_fixture),
    (select epoch from refresh_workspace_fixture),
    (select master_window_id from refresh_workspace_fixture),
    (select renewal_token from refresh_workspace_fixture)
  )->>'revoked')::boolean,
  'explicit logout still revokes the resumed workspace'
);
select ok(
  not (public.resume_operator_workspace_v1(
    (select workspace_id from refresh_workspace_fixture),
    (select epoch from refresh_workspace_fixture),
    (select master_window_id from refresh_workspace_fixture),
    'f3620000-0000-4000-8000-000000000005'
  )->>'resumed')::boolean,
  'revoked workspace cannot be resurrected by a stale child or master hint'
);

select * from finish();
rollback;