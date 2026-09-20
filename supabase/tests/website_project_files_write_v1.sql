begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, lws_internal, extensions;
select no_plan();

create function pg_temp.set_project_files_write_claims_v1(
  p_subject uuid,
  p_role text default 'authenticated',
  p_aal text default 'aal2'
)
returns void
language sql
as $$
  select set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_subject, 'role', p_role, 'aal', p_aal)::text,
    true
  )::text;
$$;

create function pg_temp.acquire_project_files_write_v1(
  p_quote_request_id uuid,
  p_path text,
  p_expected_commit_sha text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  if to_regprocedure(
    'public.acquire_website_project_files_write_v1(uuid,text,text,uuid)'
  ) is null then
    return jsonb_build_object('missing_contract', 'acquire_write');
  end if;
  execute
    'select public.acquire_website_project_files_write_v1($1,$2,$3,$4)'
    into v_result
    using p_quote_request_id, p_path, p_expected_commit_sha, p_idempotency_key;
  return v_result;
end;
$$;

create function pg_temp.finalize_project_files_write_v1(
  p_lease_id uuid,
  p_path text,
  p_expected_commit_sha text,
  p_commit_sha text,
  p_created boolean
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  if to_regprocedure(
    'public.finalize_website_project_files_write_v1(uuid,text,text,text,boolean)'
  ) is null then
    return jsonb_build_object('missing_contract', 'finalize_write');
  end if;
  execute
    'select public.finalize_website_project_files_write_v1($1,$2,$3,$4,$5)'
    into v_result
    using p_lease_id, p_path, p_expected_commit_sha, p_commit_sha, p_created;
  return v_result;
end;
$$;

create function pg_temp.release_project_files_write_v1(p_lease_id uuid)
returns void
language plpgsql
as $$
begin
  if to_regprocedure(
    'public.release_website_project_files_write_v1(uuid)'
  ) is null then
    return;
  end if;
  execute 'select public.release_website_project_files_write_v1($1)'
    using p_lease_id;
end;
$$;

select has_table(
  'lws_internal', 'website_project_files_write_acquisitions',
  'private write rate-accounting storage exists'
);
select has_table(
  'lws_internal', 'website_project_files_write_leases',
  'private write lease storage exists'
);
select has_function(
  'public', 'acquire_website_project_files_write_v1',
  array['uuid', 'text', 'text', 'uuid'],
  'write acquisition RPC exists'
);
select has_function(
  'public', 'finalize_website_project_files_write_v1',
  array['uuid', 'text', 'text', 'text', 'boolean'],
  'write finalize RPC exists'
);
select has_function(
  'public', 'release_website_project_files_write_v1',
  array['uuid'],
  'write release RPC exists'
);
select has_table(
  'lws_internal', 'website_project_preview_build_leases',
  'private preview lease storage exists'
);
select has_table(
  'lws_internal', 'website_project_preview_builds',
  'immutable preview build audit exists'
);
select has_function(
  'public', 'acquire_website_project_preview_build_v1',
  array['uuid', 'text', 'uuid'],
  'preview acquisition RPC exists'
);
select has_function(
  'public', 'finalize_website_project_preview_build_v1',
  array['uuid', 'text', 'text', 'text', 'bigint', 'text'],
  'preview finalize RPC exists'
);
select has_function(
  'public', 'release_website_project_preview_build_v1',
  array['uuid'],
  'preview release RPC exists'
);
select ok(
  coalesce((select relrowsecurity and relforcerowsecurity
    from pg_class
    where oid = to_regclass(
      'lws_internal.website_project_preview_build_leases'
    )), false)
  and coalesce((select relrowsecurity and relforcerowsecurity
    from pg_class
    where oid = to_regclass(
      'lws_internal.website_project_preview_builds'
    )), false),
  'preview lease and audit storage enable and force RLS'
);
select ok(
  (select bool_and(
    has_function_privilege('authenticated', procedure, 'execute')
    and not has_function_privilege('anon', procedure, 'execute')
    and not has_function_privilege('service_role', procedure, 'execute')
    and not exists (
      select 1
      from pg_proc as definition,
      lateral aclexplode(coalesce(
        definition.proacl,
        acldefault('f', definition.proowner)
      )) as privilege
      where definition.oid = procedure
        and privilege.grantee = 0
        and privilege.privilege_type = 'EXECUTE'
    )
  ) from unnest(array[
    'public.acquire_website_project_preview_build_v1(uuid,text,uuid)'::regprocedure,
    'public.finalize_website_project_preview_build_v1(uuid,text,text,text,bigint,text)'::regprocedure,
    'public.release_website_project_preview_build_v1(uuid)'::regprocedure
  ]) as procedure),
  'preview lease RPCs grant execute only to authenticated callers'
);
select ok(
  exists (
    select 1 from storage.buckets
    where id = 'website-project-previews'
      and name = 'website-project-previews'
      and public = false
      and file_size_limit = 1048576
      and allowed_mime_types = array['text/html']::text[]
  ),
  'preview artifacts use one bounded private HTML bucket'
);

select ok(
  coalesce((select relrowsecurity and relforcerowsecurity
    from pg_class
    where oid = to_regclass(
      'lws_internal.website_project_files_write_acquisitions'
    )), false),
  'write acquisitions storage enables and forces RLS'
);
select ok(
  coalesce((select relrowsecurity and relforcerowsecurity
    from pg_class
    where oid = to_regclass(
      'lws_internal.website_project_files_write_leases'
    )), false),
  'write lease storage enables and forces RLS'
);
select ok(
  (select bool_and(
    has_function_privilege('authenticated', procedure, 'execute')
    and not has_function_privilege('anon', procedure, 'execute')
    and not has_function_privilege('service_role', procedure, 'execute')
    and not exists (
      select 1
      from pg_proc as definition,
      lateral aclexplode(coalesce(
        definition.proacl,
        acldefault('f', definition.proowner)
      )) as privilege
      where definition.oid = procedure
        and privilege.grantee = 0
        and privilege.privilege_type = 'EXECUTE'
    )
  ) from unnest(array[
    'public.acquire_website_project_files_write_v1(uuid,text,text,uuid)'::regprocedure,
    'public.finalize_website_project_files_write_v1(uuid,text,text,text,boolean)'::regprocedure,
    'public.release_website_project_files_write_v1(uuid)'::regprocedure
  ]) as procedure),
  'write lease RPCs grant execute only to authenticated callers'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'role', 'authenticated',
    'aal', 'aal2'
  )::text,
  true
);

set local session_replication_role = replica;
update public.commercial_operators
set role = 'owner', status = 'ACTIVE', revoked_at = null
where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0';
set local session_replication_role = origin;

create temporary table task8_write_fixture as
select
  (value->>'website_work_context_id')::uuid as website_work_context_id,
  (value->>'workspace_id')::uuid as website_workspace_id,
  null::uuid as quote_request_id,
  'lws-task8-write-fixtures'::text as repository_owner,
  'project-files-write-a'::text as repository_name,
  7300000001::bigint as repository_external_id,
  'R_task8_write_a'::text as repository_node_id,
  9::bigint as binding_revision,
  'f8300000-0000-4000-8000-000000000001'::uuid as marker_operation_id,
  'a'::text as sha_char
from (
  select public.create_task13_synthetic_context_v1() as value
) created;

update task8_write_fixture as fixture
set quote_request_id = context.quote_request_id
from public.website_work_contexts as context
where context.website_work_context_id = fixture.website_work_context_id;

select pg_temp.set_project_files_write_claims_v1(
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'
);

select throws_ok(
  $$select pg_temp.acquire_project_files_write_v1(
    (select quote_request_id from task8_write_fixture),
    'src/main.ts',
    repeat('a',40),
    'f8310000-0000-4000-8000-000000000001')$$,
  'P0001', 'REPOSITORY_NOT_READY',
  'workspace must be repository-ready before write acquisition'
);

set local session_replication_role = replica;
update public.website_execution_workspaces as workspace
set workspace_state = 'REPOSITORY_READY',
    repository_owner = fixture.repository_owner,
    repository_name = fixture.repository_name,
    repository_external_id = fixture.repository_external_id,
    repository_node_id = fixture.repository_node_id,
    repository_visibility = 'private',
    repository_state = 'BOUND',
    starter_source = 'lws-task8-write-fixtures/website-starter',
    starter_version = '1.0.0',
    starter_commit_sha = repeat(fixture.sha_char, 40),
    repository_marker_commit_sha = repeat('d', 40),
    repository_bound_at = clock_timestamp(),
    binding_revision = fixture.binding_revision,
    default_branch = 'main',
    last_commit_sha = repeat(fixture.sha_char, 40)
from task8_write_fixture as fixture
where workspace.website_workspace_id = fixture.website_workspace_id;
set local session_replication_role = origin;

select throws_ok(
  $$select pg_temp.acquire_project_files_write_v1(
    (select quote_request_id from task8_write_fixture),
    'src/main.ts',
    repeat('a',40),
    'f8310000-0000-4000-8000-000000000001')$$,
  'P0001', 'REPOSITORY_BINDING_STALE',
  'missing BOUND marker operation denies write acquisition'
);

select set_config('lws.website_repository_command', 'on', true);
insert into public.website_repository_provisioning_operations(
  operation_id, website_workspace_id, website_work_context_id, actor_id,
  idempotency_key, request_fingerprint, repository_owner, repository_name,
  starter_source, starter_version, starter_commit_sha, state, attempt_count,
  repository_external_id, repository_node_id, claimed_at, updated_at,
  external_created_at, bound_at
)
select
  fixture.marker_operation_id,
  fixture.website_workspace_id,
  fixture.website_work_context_id,
  (select operator_id from public.commercial_operators
   where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
  'f8310000-0000-4000-8000-000000000099',
  repeat('1', 64),
  fixture.repository_owner,
  fixture.repository_name,
  'lws-task8-write-fixtures/website-starter',
  '1.0.0',
  repeat(fixture.sha_char, 40),
  'BOUND',
  1,
  fixture.repository_external_id,
  fixture.repository_node_id,
  clock_timestamp(),
  clock_timestamp(),
  clock_timestamp(),
  clock_timestamp()
from task8_write_fixture as fixture;
select set_config('lws.website_repository_command', '', true);

create temporary table task8_write_acquire as
select pg_temp.acquire_project_files_write_v1(
  (select quote_request_id from task8_write_fixture),
  'src/main.ts',
  repeat('a',40),
  'f8310000-0000-4000-8000-000000000001'
) as payload;

select ok(
  ((select payload->>'leaseId' from task8_write_acquire)::uuid is not null)
  and (select payload->>'repositoryRef' from task8_write_acquire) = 'heads/main'
  and (select payload->>'refLabel' from task8_write_acquire) = 'main',
  'write acquisition returns authority shape compatible with project files service'
);

select is(
  (select payload->>'leaseId' from task8_write_acquire),
  (
    select pg_temp.acquire_project_files_write_v1(
      (select quote_request_id from task8_write_fixture),
      'src/main.ts',
      repeat('a',40),
      'f8310000-0000-4000-8000-000000000001'
    )->>'leaseId'
  ),
  'same identity and idempotency replay returns same write lease'
);

select throws_ok(
  $$select pg_temp.acquire_project_files_write_v1(
    (select quote_request_id from task8_write_fixture),
    'src/main.ts',
    repeat('b',40),
    'f8310000-0000-4000-8000-000000000001')$$,
  'P0001', 'PROJECT_FILES_STALE_REVISION',
  'same idempotency with a different expected commit is rejected'
);

insert into lws_internal.website_project_files_write_acquisitions(
  actor_operator_id,
  actor_auth_user_id,
  quote_request_id,
  website_work_context_id,
  write_path,
  expected_commit_sha,
  idempotency_key,
  acquired_at
)
select
  (select operator_id from public.commercial_operators
   where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  fixture.quote_request_id,
  fixture.website_work_context_id,
  'src/fill-' || item::text || '.ts',
  repeat('a',40),
  gen_random_uuid(),
  clock_timestamp()
from task8_write_fixture as fixture,
generate_series(1, 10) as item;

select throws_ok(
  $$select pg_temp.acquire_project_files_write_v1(
    (select quote_request_id from task8_write_fixture),
    'src/rate-limit.ts',
    repeat('a',40),
    'f8310000-0000-4000-8000-000000000002')$$,
  'P0001', 'PROJECT_FILES_RATE_LIMITED',
  'rolling write acquisition budget rate-limits bursts'
);

delete from lws_internal.website_project_files_write_acquisitions;

insert into lws_internal.website_project_files_write_leases(
  actor_operator_id,
  actor_auth_user_id,
  quote_request_id,
  website_work_context_id,
  website_workspace_id,
  binding_revision,
  repository_provider,
  repository_owner,
  repository_name,
  repository_external_id,
  repository_node_id,
  default_branch,
  repository_ref,
  ref_label,
  marker_operation_id,
  write_path,
  expected_commit_sha,
  idempotency_key,
  acquired_at,
  expires_at
)
select
  (select operator_id from public.commercial_operators
   where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  fixture.quote_request_id,
  fixture.website_work_context_id,
  fixture.website_workspace_id,
  fixture.binding_revision,
  'GITHUB',
  fixture.repository_owner,
  fixture.repository_name,
  fixture.repository_external_id,
  fixture.repository_node_id,
  'main',
  'heads/main',
  'main',
  fixture.marker_operation_id,
  'src/concurrency-' || item::text || '.ts',
  repeat('a',40),
  case item
    when 1 then 'f8310000-0000-4000-8000-000000000010'::uuid
    else 'f8310000-0000-4000-8000-000000000011'::uuid end,
  lease_time.acquired_at,
  lease_time.acquired_at + interval '30 seconds'
from task8_write_fixture as fixture,
generate_series(1, 2) as item,
lateral (select clock_timestamp() as acquired_at) as lease_time;

select throws_ok(
  $$select pg_temp.acquire_project_files_write_v1(
    (select quote_request_id from task8_write_fixture),
    'src/concurrency.ts',
    repeat('a',40),
    'f8310000-0000-4000-8000-000000000003')$$,
  'P0001', 'PROJECT_FILES_CONCURRENCY_LIMITED',
  'write lease concurrency is capped per caller'
);

delete from lws_internal.website_project_files_write_leases
where idempotency_key in (
  'f8310000-0000-4000-8000-000000000010',
  'f8310000-0000-4000-8000-000000000011'
);

select ok(
  (
    select pg_temp.finalize_project_files_write_v1(
      (select payload->>'leaseId' from task8_write_acquire)::uuid,
      'src/main.ts',
      repeat('a',40),
      repeat('b',40),
      false
    )->>'commitSha'
  ) = repeat('b',40),
  'finalize binds one durable commit result for the acquired lease'
);

select pg_temp.release_project_files_write_v1(
  (select payload->>'leaseId' from task8_write_acquire)::uuid
);
select ok(
  exists (
    select 1
    from lws_internal.website_project_files_write_leases
    where lease_id =
      (select (payload->>'leaseId')::uuid from task8_write_acquire)
      and released_at is not null
      and finalized_at is not null
      and finalized_commit_sha = repeat('b',40)
      and finalized_created = false
  ),
  'finalized write lease is durably closed and remains auditable'
);

select * from finish();
rollback;