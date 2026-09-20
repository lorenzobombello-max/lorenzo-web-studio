begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public', 'resume_operator_workspace_v1', array['uuid','bigint','uuid','uuid'],
  'master refresh resume authority exists'
);
select has_function(
  'public', 'recover_operator_workspace_v1', array['uuid','bigint','uuid','uuid'],
  'expired workspace recovery authority exists'
);
select ok(
  has_function_privilege('authenticated', 'public.resume_operator_workspace_v1(uuid,bigint,uuid,uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.recover_operator_workspace_v1(uuid,bigint,uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.resume_operator_workspace_v1(uuid,bigint,uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.recover_operator_workspace_v1(uuid,bigint,uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.resume_operator_workspace_v1(uuid,bigint,uuid,uuid)', 'execute'),
  'only authenticated humans can request workspace resume and recovery'
);

insert into auth.users(id, email) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'workspace-refresh-owner@example.test'),
  ('bd2ab636-0d42-4069-8a12-db827f1b97b0', 'workspace-refresh-other@example.test')
on conflict (id) do nothing;

select set_config('request.jwt.claim.sub', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', true);
select set_config('request.jwt.claims', '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}', true);
insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('f3610000-0000-4000-8000-000000000001', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'Refresh Owner', 'owner', 'ACTIVE'),
  ('f3610000-0000-4000-8000-000000000002', 'bd2ab636-0d42-4069-8a12-db827f1b97b0', 'Refresh Other', 'owner', 'ACTIVE')
on conflict (auth_user_id) do update
set role = excluded.role, status = excluded.status;

delete from public.operator_workspace_sessions
where operator_id in (
  select operator_id from public.commercial_operators
  where auth_user_id in (
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'::uuid,
    'bd2ab636-0d42-4069-8a12-db827f1b97b0'::uuid
  )
);

create temporary table refresh_workspace_fixture(
  workspace_id uuid,
  epoch bigint,
  master_window_id uuid,
  renewal_token uuid
);

select set_config('request.jwt.claim.sub', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', true);
select set_config('request.jwt.claims', '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}', true);
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

select set_config('request.jwt.claim.sub', 'bd2ab636-0d42-4069-8a12-db827f1b97b0', true);
select set_config('request.jwt.claims', '{"sub":"bd2ab636-0d42-4069-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}', true);
select ok(
  not (public.resume_operator_workspace_v1(
    (select workspace_id from refresh_workspace_fixture),
    (select epoch from refresh_workspace_fixture),
    (select master_window_id from refresh_workspace_fixture),
    'f3620000-0000-4000-8000-000000000099'
  )->>'resumed')::boolean,
  'different Operator cannot reclaim an existing workspace'
);

select set_config('request.jwt.claim.sub', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', true);
select set_config('request.jwt.claims', '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}', true);
create temporary table first_resume as
select public.resume_operator_workspace_v1(
  (select workspace_id from refresh_workspace_fixture),
  (select epoch from refresh_workspace_fixture),
  (select master_window_id from refresh_workspace_fixture),
  'f3620000-0000-4000-8000-000000000002'
) result;

select ok((select (result->>'resumed')::boolean from first_resume), 'normal master refresh resumes server authority');
select is(
  (select jsonb_array_length(result->'window_claims') from first_resume),
  6,
  'resume returns every authorized server-owned child claim'
);
select ok(
  (select bool_and(claim ?& array['window_id', 'module_key', 'slot_key'])
   from first_resume, jsonb_array_elements(result->'window_claims') claim),
  'resumed child claims expose only their bounded window and slot identity'
);
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

select throws_ok(
  format(
    'select public.recover_operator_workspace_v1(%L, %s, %L, %L)',
    (select workspace_id from refresh_workspace_fixture), (select epoch from refresh_workspace_fixture),
    (select master_window_id from refresh_workspace_fixture), (select renewal_token from refresh_workspace_fixture)
  ),
  '42501', 'WORKSPACE_STILL_ACTIVE', 'recovery rejects authority that is still active'
);
select throws_ok(
  format(
    'select public.recover_operator_workspace_v1(%L, %s, %L, %L)',
    (select workspace_id from refresh_workspace_fixture), (select epoch from refresh_workspace_fixture),
    (select master_window_id from refresh_workspace_fixture), 'f3620000-0000-4000-8000-000000000099'
  ),
  '42501', 'MASTER_RECOVERY_NOT_AUTHORIZED', 'recovery rejects a stale renewal capability'
);
select set_config('request.jwt.claim.sub', 'bd2ab636-0d42-4069-8a12-db827f1b97b0', true);
select set_config('request.jwt.claims', '{"sub":"bd2ab636-0d42-4069-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}', true);
select throws_ok(
  format(
    'select public.recover_operator_workspace_v1(%L, %s, %L, %L)',
    (select workspace_id from refresh_workspace_fixture), (select epoch from refresh_workspace_fixture),
    (select master_window_id from refresh_workspace_fixture), (select renewal_token from refresh_workspace_fixture)
  ),
  '42501', 'WORKSPACE_NOT_AVAILABLE', 'different Operator cannot recover foreign workspace authority'
);
select set_config('request.jwt.claim.sub', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', true);
select set_config('request.jwt.claims', '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}', true);

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
select throws_ok(
  format(
    'select public.recover_operator_workspace_v1(%L, %s, %L, %L)',
    (select workspace_id from refresh_workspace_fixture), (select epoch from refresh_workspace_fixture),
    (select master_window_id from refresh_workspace_fixture), (select renewal_token from refresh_workspace_fixture)
  ),
  '42501', 'WORKSPACE_REVOKED', 'explicitly revoked workspace authority cannot recover'
);

create temporary table expired_workspace_fixture(
  workspace_id uuid,
  epoch bigint,
  master_window_id uuid,
  renewal_token uuid
);

select set_config('request.jwt.claim.sub', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', true);
select set_config('request.jwt.claims', '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}', true);
insert into expired_workspace_fixture
select
  (result->>'workspace_id')::uuid,
  (result->>'epoch')::bigint,
  (result->>'master_window_id')::uuid,
  (result->>'renewal_token')::uuid
from (select public.acquire_operator_workspace_v1('f3620000-0000-4000-8000-000000000010') result) acquired;

update public.operator_workspace_sessions
set lease_expires_at = clock_timestamp() - interval '1 second'
where workspace_id = (select workspace_id from expired_workspace_fixture);

create temporary table recovered_workspace as
select public.recover_operator_workspace_v1(
  (select workspace_id from expired_workspace_fixture),
  (select epoch from expired_workspace_fixture),
  (select master_window_id from expired_workspace_fixture),
  (select renewal_token from expired_workspace_fixture)
) result;

select ok((select (result->>'recovered')::boolean from recovered_workspace), 'naturally expired workspace recovers with its exact master capability');
select isnt(
  (select result->>'workspace_id' from recovered_workspace),
  (select workspace_id::text from expired_workspace_fixture),
  'recovery creates a fresh workspace identity'
);
select is(
  (select result->'window_claims' from recovered_workspace),
  '[]'::jsonb,
  'recovery never transfers stale child claims into the fresh epoch'
);
select is(
  (public.recover_operator_workspace_v1(
    (select workspace_id from expired_workspace_fixture),
    (select epoch from expired_workspace_fixture),
    (select master_window_id from expired_workspace_fixture),
    (select renewal_token from expired_workspace_fixture)
  )->>'reason'),
  'SERVER_MASTER_EXISTS',
  'recovery rejects replacement when another active master now owns authority'
);

select * from finish();
rollback;