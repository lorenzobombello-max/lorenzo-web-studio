begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, lws_internal, extensions;
select no_plan();

create function pg_temp.set_project_files_claims_v1(
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

create function pg_temp.acquire_project_files_v1(
  p_quote_request_id uuid,
  p_read_kind text
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  if to_regprocedure(
    'public.acquire_website_project_files_read_v1(uuid,text)'
  ) is null then
    return jsonb_build_object('missing_contract', 'acquire');
  end if;
  execute 'select public.acquire_website_project_files_read_v1($1,$2)'
    into v_result
    using p_quote_request_id, p_read_kind;
  return v_result;
end;
$$;

create function pg_temp.release_project_files_v1(p_lease_id uuid)
returns void
language plpgsql
as $$
begin
  if to_regprocedure(
    'public.release_website_project_files_read_v1(uuid)'
  ) is null then
    return;
  end if;
  execute 'select public.release_website_project_files_read_v1($1)'
    using p_lease_id;
end;
$$;

create function pg_temp.get_workspace_v3(p_quote_request_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  if to_regprocedure(
    'public.get_website_execution_workspace_v3(uuid)'
  ) is null then
    return jsonb_build_object('missing_contract', 'workspace_v3');
  end if;
  execute 'select public.get_website_execution_workspace_v3($1)'
    into v_result
    using p_quote_request_id;
  return v_result;
end;
$$;

create temporary table task3_v2_before as
select pg_get_functiondef(
  'public.get_website_execution_workspace_v2(uuid)'::regprocedure
) as definition;

select has_table(
  'lws_internal', 'website_project_files_read_acquisitions',
  'private rolling rate-accounting storage exists'
);
select has_table(
  'lws_internal', 'website_project_files_read_leases',
  'private read-lease storage exists'
);
select has_function(
  'public', 'acquire_website_project_files_read_v1', array['uuid', 'text'],
  'exact project-files acquisition RPC exists'
);
select has_function(
  'public', 'release_website_project_files_read_v1', array['uuid'],
  'exact project-files release RPC exists'
);
select has_function(
  'public', 'get_website_execution_workspace_v3', array['uuid'],
  'forward-only Website Execution v3 RPC exists'
);
select has_function(
  'public', 'get_website_execution_workspace_v2', array['uuid'],
  'Website Execution v2 remains present'
);

select ok(
  coalesce((select relrowsecurity and relforcerowsecurity
    from pg_class
    where oid = to_regclass(
      'lws_internal.website_project_files_read_acquisitions'
    )), false),
  'rate-accounting storage enables and forces RLS'
);
select ok(
  coalesce((select relrowsecurity and relforcerowsecurity
    from pg_class
    where oid = to_regclass(
      'lws_internal.website_project_files_read_leases'
    )), false),
  'read-lease storage enables and forces RLS'
);
select ok(
  case when to_regclass(
    'lws_internal.website_project_files_read_acquisitions'
  ) is null then false else
    not has_table_privilege(
      'anon', 'lws_internal.website_project_files_read_acquisitions',
      'select,insert,update,delete'
    )
    and not has_table_privilege(
      'authenticated', 'lws_internal.website_project_files_read_acquisitions',
      'select,insert,update,delete'
    )
    and not has_table_privilege(
      'service_role', 'lws_internal.website_project_files_read_acquisitions',
      'select,insert,update,delete'
    )
  end,
  'rate-accounting storage has no browser or service-role table access'
);
select ok(
  case when to_regclass(
    'lws_internal.website_project_files_read_leases'
  ) is null then false else
    not has_table_privilege(
      'anon', 'lws_internal.website_project_files_read_leases',
      'select,insert,update,delete'
    )
    and not has_table_privilege(
      'authenticated', 'lws_internal.website_project_files_read_leases',
      'select,insert,update,delete'
    )
    and not has_table_privilege(
      'service_role', 'lws_internal.website_project_files_read_leases',
      'select,insert,update,delete'
    )
  end,
  'read-lease storage has no browser or service-role table access'
);

select ok(
  case when to_regprocedure(
    'public.acquire_website_project_files_read_v1(uuid,text)'
  ) is null then false else
    has_function_privilege(
      'authenticated',
      'public.acquire_website_project_files_read_v1(uuid,text)', 'execute'
    )
    and not has_function_privilege(
      'public',
      'public.acquire_website_project_files_read_v1(uuid,text)', 'execute'
    )
    and not has_function_privilege(
      'anon',
      'public.acquire_website_project_files_read_v1(uuid,text)', 'execute'
    )
    and not has_function_privilege(
      'service_role',
      'public.acquire_website_project_files_read_v1(uuid,text)', 'execute'
    )
  end,
  'acquisition RPC is executable only by authenticated callers'
);
select ok(
  case when to_regprocedure(
    'public.release_website_project_files_read_v1(uuid)'
  ) is null then false else
    has_function_privilege(
      'authenticated',
      'public.release_website_project_files_read_v1(uuid)', 'execute'
    )
    and not has_function_privilege(
      'public',
      'public.release_website_project_files_read_v1(uuid)', 'execute'
    )
    and not has_function_privilege(
      'anon',
      'public.release_website_project_files_read_v1(uuid)', 'execute'
    )
    and not has_function_privilege(
      'service_role',
      'public.release_website_project_files_read_v1(uuid)', 'execute'
    )
  end,
  'release RPC is executable only by authenticated callers'
);
select ok(
  case when to_regprocedure(
    'public.get_website_execution_workspace_v3(uuid)'
  ) is null then false else
    has_function_privilege(
      'authenticated',
      'public.get_website_execution_workspace_v3(uuid)', 'execute'
    )
    and not has_function_privilege(
      'public', 'public.get_website_execution_workspace_v3(uuid)', 'execute'
    )
    and not has_function_privilege(
      'anon', 'public.get_website_execution_workspace_v3(uuid)', 'execute'
    )
    and not has_function_privilege(
      'service_role', 'public.get_website_execution_workspace_v3(uuid)',
      'execute'
    )
  end,
  'workspace v3 RPC is executable only by authenticated callers'
);

select is(
  (select definition from task3_v2_before),
  pg_get_functiondef(
    'public.get_website_execution_workspace_v2(uuid)'::regprocedure
  ),
  'Website Execution v2 definition remains unchanged during Task 3 test setup'
);

select volatility_is(
  'public', 'acquire_website_project_files_read_v1',
  array['uuid', 'text'], 'volatile',
  'acquisition is an atomic volatile authority operation'
);
select volatility_is(
  'public', 'release_website_project_files_read_v1',
  array['uuid'], 'volatile',
  'release is an atomic volatile lease operation'
);
select volatility_is(
  'public', 'get_website_execution_workspace_v3',
  array['uuid'], 'stable',
  'workspace v3 is a read-only stable projection'
);
select is_definer(
  'public', 'acquire_website_project_files_read_v1',
  array['uuid', 'text'], 'acquisition uses the guarded definer pattern'
);
select is_definer(
  'public', 'release_website_project_files_read_v1',
  array['uuid'], 'release uses the guarded definer pattern'
);
select is_definer(
  'public', 'get_website_execution_workspace_v3',
  array['uuid'], 'workspace v3 uses the guarded definer pattern'
);
select ok(
  (select count(*) >= 4
   from regexp_matches(
     lower(pg_get_functiondef(
       'public.acquire_website_project_files_read_v1(uuid,text)'::regprocedure
     )), 'for update', 'g'
   )),
  'acquisition locks operator, context, workspace, and latest operation rows'
);
select ok(
  strpos(lower(pg_get_functiondef(
    'public.acquire_website_project_files_read_v1(uuid,text)'::regprocedure
  )), 'v_now := clock_timestamp()') >
  strpos(lower(pg_get_functiondef(
    'public.acquire_website_project_files_read_v1(uuid,text)'::regprocedure
  )), 'pg_advisory_xact_lock'),
  'rolling-window time is captured only after actor serialization'
);
select ok(
  lower(pg_get_functiondef(
    'public.get_website_execution_workspace_v3(uuid)'::regprocedure
  )) ~ 'binding_revision\s*>=\s*1'
  and lower(pg_get_functiondef(
    'public.get_website_execution_workspace_v3(uuid)'::regprocedure
  )) ~ 'default_branch\s+is\s+not\s+null',
  'workspace v3 uses acquisition-equivalent revision and ref gates'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'role', 'authenticated', 'aal', 'aal2'
  )::text,
  true
);

set local session_replication_role = replica;
update public.commercial_operators
set role = 'owner', status = 'ACTIVE', revoked_at = null
where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0';
update public.commercial_operators
set role = 'owner', status = 'ACTIVE', revoked_at = null
where auth_user_id = 'bd2ab636-0d42-4069-88a9-60bd97f2b335';
set local session_replication_role = origin;

create temporary table task3_contexts(
  context_label text primary key,
  quote_request_id uuid,
  website_work_context_id uuid not null,
  website_workspace_id uuid not null,
  repository_owner text not null,
  repository_name text not null,
  repository_external_id bigint not null,
  repository_node_id text not null,
  binding_revision bigint not null,
  marker_operation_id uuid not null
) on commit drop;

with created as (
  select public.create_task13_synthetic_context_v1() as value
)
insert into task3_contexts(
  context_label, website_work_context_id, website_workspace_id,
  repository_owner, repository_name, repository_external_id,
  repository_node_id, binding_revision, marker_operation_id
)
select
  'A', (value->>'website_work_context_id')::uuid,
  (value->>'workspace_id')::uuid, 'lws-phase-a-fixtures',
  'project-files-context-a', 7100000001, 'R_task3_context_a', 7,
  'f3300000-0000-4000-8000-000000000001'
from created;

with created as (
  select public.create_task13_synthetic_context_v1() as value
)
insert into task3_contexts(
  context_label, website_work_context_id, website_workspace_id,
  repository_owner, repository_name, repository_external_id,
  repository_node_id, binding_revision, marker_operation_id
)
select
  'B', (value->>'website_work_context_id')::uuid,
  (value->>'workspace_id')::uuid, 'lws-phase-a-fixtures',
  'project-files-context-b', 7100000002, 'R_task3_context_b', 11,
  'f3300000-0000-4000-8000-000000000002'
from created;

update task3_contexts as fixture
set quote_request_id = context.quote_request_id
from public.website_work_contexts as context
where context.website_work_context_id = fixture.website_work_context_id;

select ok(
  (select context.project_id is null
   from public.website_work_contexts as context
   join task3_contexts as fixture
     on fixture.website_work_context_id = context.website_work_context_id
   where fixture.context_label = 'A'),
  'PRE_PROJECT authority keeps project_id null'
);

select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  'P0001', 'REPOSITORY_NOT_READY',
  'PENDING_REPOSITORY denies acquisition'
);

create temporary table task3_no_workspace as
select
  (value->>'website_work_context_id')::uuid as website_work_context_id,
  (value->>'workspace_id')::uuid as website_workspace_id,
  null::uuid as quote_request_id
from (
  select public.create_task13_synthetic_context_v1() as value
) as created;
update task3_no_workspace as fixture
set quote_request_id = workspace.quote_request_id
from public.website_execution_workspaces as workspace
where workspace.website_workspace_id = fixture.website_workspace_id;
set local session_replication_role = replica;
delete from public.website_execution_workspaces as workspace
where workspace.website_workspace_id = (
  select website_workspace_id from task3_no_workspace
);
set local session_replication_role = origin;
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_no_workspace), 'DIRECTORY')$$,
  'P0001', 'WEBSITE_WORKSPACE_NOT_FOUND',
  'missing workspace denies acquisition'
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
    starter_source = 'lws-phase-a-fixtures/website-starter',
    starter_version = '1.0.0',
    starter_commit_sha = repeat(case fixture.context_label
      when 'A' then 'a' else 'b' end, 40),
    repository_marker_commit_sha = repeat(case fixture.context_label
      when 'A' then 'c' else 'd' end, 40),
    repository_bound_at = clock_timestamp(),
    binding_revision = fixture.binding_revision
from task3_contexts as fixture
where workspace.website_workspace_id = fixture.website_workspace_id;
set local session_replication_role = origin;

select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  'P0001', 'REPOSITORY_BINDING_STALE',
  'missing terminal marker operation denies acquisition'
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
  fixture.marker_operation_id, fixture.website_workspace_id,
  fixture.website_work_context_id,
  (select operator_id from public.commercial_operators
   where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
  case fixture.context_label
    when 'A' then 'f3310000-0000-4000-8000-000000000001'::uuid
    else 'f3310000-0000-4000-8000-000000000002'::uuid end,
  repeat(case fixture.context_label when 'A' then '1' else '2' end, 64),
  fixture.repository_owner, fixture.repository_name,
  'lws-phase-a-fixtures/website-starter', '1.0.0',
  repeat(case fixture.context_label when 'A' then 'a' else 'b' end, 40),
  'BOUND', 1, fixture.repository_external_id, fixture.repository_node_id,
  clock_timestamp(), clock_timestamp(), clock_timestamp(), clock_timestamp()
from task3_contexts as fixture;
select set_config('lws.website_repository_command', '', true);

select set_config('lws.website_repository_command', 'on', true);
insert into public.website_repository_provisioning_operations(
  operation_id, website_workspace_id, website_work_context_id, actor_id,
  idempotency_key, request_fingerprint, repository_owner, repository_name,
  starter_source, starter_version, starter_commit_sha, state, attempt_count,
  failure_code, claimed_at, updated_at
)
select
  'f3300000-0000-4000-8000-000000000099', fixture.website_workspace_id,
  fixture.website_work_context_id,
  (select operator_id from public.commercial_operators
   where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
  'f3310000-0000-4000-8000-000000000099', repeat('9', 64),
  fixture.repository_owner, fixture.repository_name,
  'lws-phase-a-fixtures/website-starter', '1.0.0', repeat('9', 40),
  'BLOCKED', 1, 'SYNTHETIC_NEWER_BLOCK',
  clock_timestamp() + interval '1 second',
  clock_timestamp() + interval '1 second'
from task3_contexts as fixture
where fixture.context_label = 'A';
select set_config('lws.website_repository_command', '', true);

select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  'P0001', 'REPOSITORY_BINDING_STALE',
  'newer BLOCKED operation overrides an older BOUND marker'
);
set local session_replication_role = replica;
delete from public.website_repository_provisioning_operations
where operation_id = 'f3300000-0000-4000-8000-000000000099';
delete from lws_internal.website_project_files_read_acquisitions;
delete from lws_internal.website_project_files_read_leases;
set local session_replication_role = origin;

create temporary table task3_business_before as
select jsonb_build_object(
  'operations', (select jsonb_agg(to_jsonb(operation) order by operation.operation_id)
    from public.website_repository_provisioning_operations as operation
    where operation.operation_id in (
      select marker_operation_id from task3_contexts
    )),
  'events', (select coalesce(jsonb_agg(to_jsonb(event) order by event.event_id), '[]'::jsonb)
    from public.website_repository_provisioning_events as event
    where event.website_work_context_id in (
      select website_work_context_id from task3_contexts
    )),
  'workspaces', (select jsonb_agg(to_jsonb(workspace) order by workspace.website_workspace_id)
    from public.website_execution_workspaces as workspace
    where workspace.website_workspace_id in (
      select website_workspace_id from task3_contexts
    ))
) as snapshot;

select pg_temp.set_project_files_claims_v1(null);
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'anonymous acquisition is denied'
);
select pg_temp.set_project_files_claims_v1(
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'service_role', 'aal2'
);
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'service-role invocation is denied'
);

select pg_temp.set_project_files_claims_v1(
  'bd2ab636-0d42-4069-88a9-60bd97f2b335'
);
set local session_replication_role = replica;
update public.commercial_operators set role = 'admin'
where auth_user_id = 'bd2ab636-0d42-4069-88a9-60bd97f2b335';
set local session_replication_role = origin;
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  '42501', 'WEBSITE_REPOSITORY_OWNER_REQUIRED',
  'active non-owner acquisition is denied'
);
set local session_replication_role = replica;
update public.commercial_operators
set role = 'owner', status = 'REVOKED', revoked_at = clock_timestamp()
where auth_user_id = 'bd2ab636-0d42-4069-88a9-60bd97f2b335';
set local session_replication_role = origin;
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  '42501', 'WEBSITE_REPOSITORY_OWNER_REQUIRED',
  'inactive or revoked owner acquisition is denied'
);

set local session_replication_role = replica;
update public.commercial_operators
set role = 'owner', status = 'ACTIVE', revoked_at = null
where auth_user_id = 'bd2ab636-0d42-4069-88a9-60bd97f2b335';
set local session_replication_role = origin;
select pg_temp.set_project_files_claims_v1(
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'authenticated', 'aal1'
);
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  '42501', 'AAL2_REQUIRED', 'AAL1 owner acquisition is denied'
);

select pg_temp.set_project_files_claims_v1(
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'
);
create temporary table task3_authority as
select pg_temp.acquire_project_files_v1(
  (select quote_request_id from task3_contexts where context_label = 'A'),
  'DIRECTORY'
) as payload;

select is(
  (select array_agg(key order by key)
   from task3_authority
   cross join lateral jsonb_object_keys(payload) as key),
  array[
    'actorAuthUserId', 'bindingRevision', 'defaultBranch', 'expiresAt',
    'leaseId', 'markerOperationId', 'quoteRequestId', 'refLabel',
    'repositoryExternalId', 'repositoryName', 'repositoryNodeId',
    'repositoryOwner', 'repositoryProvider', 'repositoryRef',
    'websiteWorkContextId', 'websiteWorkspaceId'
  ]::text[],
  'acquisition returns the exact immutable authority keys'
);
select is(
  (select payload->>'repositoryProvider' from task3_authority),
  'GITHUB', 'authority provider is exactly GITHUB'
);
select is(
  (select payload->>'repositoryRef' from task3_authority),
  'heads/main', 'authority repository ref is server-derived'
);
select ok(
  (select payload->>'quoteRequestId' = fixture.quote_request_id::text
      and payload->>'websiteWorkContextId' = fixture.website_work_context_id::text
      and payload->>'websiteWorkspaceId' = fixture.website_workspace_id::text
      and payload->>'repositoryExternalId' = fixture.repository_external_id::text
      and payload->>'repositoryNodeId' = fixture.repository_node_id
      and payload->>'markerOperationId' = fixture.marker_operation_id::text
      and (payload->>'bindingRevision')::bigint = fixture.binding_revision
   from task3_authority
   cross join task3_contexts as fixture
   where fixture.context_label = 'A'),
  'quote A resolves only canonical context A repository authority'
);
select ok(
  (select payload->>'websiteWorkContextId' <> fixture.website_work_context_id::text
      and payload->>'websiteWorkspaceId' <> fixture.website_workspace_id::text
      and payload->>'repositoryExternalId' <> fixture.repository_external_id::text
      and payload->>'repositoryNodeId' <> fixture.repository_node_id
      and payload->>'markerOperationId' <> fixture.marker_operation_id::text
      and (payload->>'bindingRevision')::bigint <> fixture.binding_revision
   from task3_authority
   cross join task3_contexts as fixture
   where fixture.context_label = 'B'),
  'quote A cannot acquire any context B repository coordinate'
);
select is(
  (select extract(epoch from (expires_at - acquired_at))::integer
   from lws_internal.website_project_files_read_leases
   where lease_id = (select (payload->>'leaseId')::uuid from task3_authority)),
  15, 'lease lifetime is exactly 15 seconds'
);

select lives_ok(
  $$select pg_temp.release_project_files_v1(
    (select (payload->>'leaseId')::uuid from task3_authority))$$,
  'same-caller release succeeds'
);
select lives_ok(
  $$select pg_temp.release_project_files_v1(
    (select (payload->>'leaseId')::uuid from task3_authority))$$,
  'same-caller repeated release is idempotent'
);

delete from lws_internal.website_project_files_read_acquisitions;
delete from lws_internal.website_project_files_read_leases;

create function pg_temp.consume_project_files_budget_v1(
  p_quote_request_id uuid, p_read_kind text, p_count integer
)
returns integer
language plpgsql
as $$
declare
  v_index integer;
  v_payload jsonb;
begin
  for v_index in 1..p_count loop
    v_payload := pg_temp.acquire_project_files_v1(
      p_quote_request_id, p_read_kind
    );
    perform pg_temp.release_project_files_v1((v_payload->>'leaseId')::uuid);
  end loop;
  return p_count;
end;
$$;

select is(
  pg_temp.consume_project_files_budget_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY', 30
  ), 30, '30 DIRECTORY acquisitions pass in the rolling window'
);
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  'P0001', 'PROJECT_FILES_RATE_LIMITED',
  '31st DIRECTORY acquisition is rate limited'
);
select lives_ok(
  $$select pg_temp.release_project_files_v1(
    (pg_temp.acquire_project_files_v1(
      (select quote_request_id from task3_contexts where context_label = 'B'),
      'DIRECTORY')->>'leaseId')::uuid)$$,
  'context B has an independent DIRECTORY budget'
);

delete from lws_internal.website_project_files_read_acquisitions;
delete from lws_internal.website_project_files_read_leases;
select is(
  pg_temp.consume_project_files_budget_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'FILE', 10
  ), 10, '10 FILE acquisitions pass in the rolling window'
);
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'FILE')$$,
  'P0001', 'PROJECT_FILES_RATE_LIMITED',
  '11th FILE acquisition is rate limited'
);

delete from lws_internal.website_project_files_read_acquisitions;
delete from lws_internal.website_project_files_read_leases;
create temporary table task3_active_leases(lease_id uuid primary key);
insert into task3_active_leases
select (pg_temp.acquire_project_files_v1(
  (select quote_request_id from task3_contexts where context_label = 'A'),
  'DIRECTORY'
)->>'leaseId')::uuid
from generate_series(1, 4);
select is(
  (select count(*)::integer from task3_active_leases), 4,
  'four unexpired actor leases are permitted'
);
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'B'),
    'DIRECTORY')$$,
  'P0001', 'PROJECT_FILES_CONCURRENCY_LIMITED',
  'fifth unexpired actor lease is concurrency limited across contexts'
);
select pg_temp.release_project_files_v1(
  (select lease_id from task3_active_leases order by lease_id limit 1)
);
select lives_ok(
  $$select pg_temp.release_project_files_v1(
    (pg_temp.acquire_project_files_v1(
      (select quote_request_id from task3_contexts where context_label = 'B'),
      'DIRECTORY')->>'leaseId')::uuid)$$,
  'release permits a later acquisition'
);
update lws_internal.website_project_files_read_leases
set acquired_at = statement_timestamp() - interval '20 seconds',
    expires_at = statement_timestamp() - interval '5 seconds'
where lease_id in (select lease_id from task3_active_leases)
  and released_at is null;
select lives_ok(
  $$select pg_temp.release_project_files_v1(
    (pg_temp.acquire_project_files_v1(
      (select quote_request_id from task3_contexts where context_label = 'B'),
      'DIRECTORY')->>'leaseId')::uuid)$$,
  'expired lease permits a later acquisition'
);
select lives_ok(
  $$select pg_temp.release_project_files_v1(
    (select lease_id from task3_active_leases order by lease_id desc limit 1))$$,
  'expired same-caller release is idempotent'
);

delete from lws_internal.website_project_files_read_acquisitions;
delete from lws_internal.website_project_files_read_leases;
create temporary table task3_foreign_release as
select (pg_temp.acquire_project_files_v1(
  (select quote_request_id from task3_contexts where context_label = 'A'),
  'FILE'
)->>'leaseId')::uuid as lease_id;
select pg_temp.set_project_files_claims_v1(
  'bd2ab636-0d42-4069-88a9-60bd97f2b335'
);
select throws_ok(
  $$select pg_temp.release_project_files_v1(
    (select lease_id from task3_foreign_release))$$,
  '42501', 'PROJECT_FILES_LEASE_NOT_OWNED',
  'another caller cannot release the lease'
);
select pg_temp.set_project_files_claims_v1(
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'
);
select lives_ok(
  $$select pg_temp.release_project_files_v1(
    (select lease_id from task3_foreign_release))$$,
  'acquiring caller can still release after foreign denial'
);

create temporary table task3_v3 as
select pg_temp.get_workspace_v3(
  (select quote_request_id from task3_contexts where context_label = 'A')
) as payload;
select is(
  (select (payload->>'contract_version')::integer from task3_v3),
  3, 'workspace v3 contract_version is exactly 3'
);
select is(
  (select array_agg(key order by key)
   from task3_v3 cross join lateral jsonb_object_keys(payload) as key),
  array[
    'briefing_status', 'commercially_released', 'concept_id',
    'context_revision', 'contract_version', 'mode', 'project', 'project_id',
    'quote_request_id', 'requirements', 'start_gate',
    'website_work_context_id', 'workspace'
  ]::text[],
  'workspace v3 has the exact closed root DTO'
);
select is(
  (select array_agg(key order by key)
   from task3_v3
   cross join lateral jsonb_object_keys(payload->'workspace') as key),
  array[
    'binding_revision', 'capabilities', 'created_at', 'default_branch',
    'last_build_at', 'last_build_result', 'last_commit_at', 'last_commit_sha',
    'preview_branch', 'preview_url', 'project_id', 'provisioned_at',
    'provisioned_by', 'quote_request_id', 'repository_failure_category',
    'repository_name', 'repository_navigation_url',
    'repository_operation_state', 'repository_owner', 'repository_provider',
    'repository_recovery_guidance', 'updated_at', 'website_work_context_id',
    'website_workspace_id', 'workspace_state'
  ]::text[],
  'workspace v3 has the exact closed workspace DTO'
);
select is(
  (select payload->'workspace'->'capabilities'
   from task3_v3),
  jsonb_build_object('project_files_read', true),
  'exact verified ready binding enables project_files_read for owner'
);
select is(
  (select payload->'workspace'->>'repository_navigation_url'
   from task3_v3),
  'https://github.com/lws-phase-a-fixtures/project-files-context-a',
  'repository navigation URL is the allowlisted public GitHub shape'
);
select ok(
  (select not (payload::text ~* (
    'repository_external_id|repository_node_id|installation|marker_operation|'
    'credential|provider_token|local_path'
  )) from task3_v3),
  'workspace v3 exposes no repository authority or credential identifiers'
);

select is(
  (select snapshot from task3_business_before),
  jsonb_build_object(
    'operations', (select jsonb_agg(to_jsonb(operation) order by operation.operation_id)
      from public.website_repository_provisioning_operations as operation
      where operation.operation_id in (
        select marker_operation_id from task3_contexts
      )),
    'events', (select coalesce(jsonb_agg(to_jsonb(event) order by event.event_id), '[]'::jsonb)
      from public.website_repository_provisioning_events as event
      where event.website_work_context_id in (
        select website_work_context_id from task3_contexts
      )),
    'workspaces', (select jsonb_agg(to_jsonb(workspace) order by workspace.website_workspace_id)
      from public.website_execution_workspaces as workspace
      where workspace.website_workspace_id in (
        select website_workspace_id from task3_contexts
      ))
  ),
  'acquisitions and releases create zero repository or workspace mutations'
);

alter table public.website_execution_workspaces
  drop constraint website_execution_workspace_repository_binding_shape;
alter table public.website_repository_provisioning_operations
  drop constraint website_repository_operation_state_valid,
  drop constraint website_repository_operation_state_identity_shape,
  drop constraint website_repository_operation_failure_shape,
  drop constraint website_repository_operation_retry_shape,
  drop constraint website_repository_operation_bound_shape;
alter table public.website_repository_provisioning_operations
  alter column state drop not null;

set local session_replication_role = replica;
update public.website_execution_workspaces
set workspace_state = 'REPOSITORY_PROVISIONING'
where website_workspace_id = (
  select website_workspace_id from task3_contexts where context_label = 'A'
);
set local session_replication_role = origin;
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  'P0001', 'REPOSITORY_NOT_READY',
  'REPOSITORY_PROVISIONING denies acquisition'
);
set local session_replication_role = replica;
update public.website_execution_workspaces
set workspace_state = 'REPOSITORY_FAILED'
where website_workspace_id = (
  select website_workspace_id from task3_contexts where context_label = 'A'
);
set local session_replication_role = origin;
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  'P0001', 'REPOSITORY_NOT_READY',
  'REPOSITORY_FAILED denies acquisition'
);
set local session_replication_role = replica;
update public.website_execution_workspaces
set workspace_state = 'READY'
where website_workspace_id = (
  select website_workspace_id from task3_contexts where context_label = 'A'
);
set local session_replication_role = origin;
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  'P0001', 'REPOSITORY_NOT_READY',
  'legacy READY denies acquisition'
);

set local session_replication_role = replica;
update public.website_execution_workspaces
set workspace_state = 'REPOSITORY_READY'
where website_workspace_id = (
  select website_workspace_id from task3_contexts where context_label = 'A'
);
set local session_replication_role = origin;

create function pg_temp.set_task3_operation_state_v1(p_state text)
returns void
language plpgsql
as $$
begin
  set local session_replication_role = replica;
  update public.website_repository_provisioning_operations
  set state = p_state
  where operation_id = (
    select marker_operation_id from task3_contexts where context_label = 'A'
  );
  set local session_replication_role = origin;
end;
$$;

select pg_temp.set_task3_operation_state_v1('BLOCKED');
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  'P0001', 'REPOSITORY_BINDING_STALE',
  'BLOCKED operation denies acquisition'
);
select pg_temp.set_task3_operation_state_v1('QUARANTINED');
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  'P0001', 'REPOSITORY_BINDING_STALE',
  'QUARANTINED operation denies acquisition'
);
select pg_temp.set_task3_operation_state_v1('RETRYABLE_FAILED');
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  'P0001', 'REPOSITORY_BINDING_STALE',
  'RETRYABLE_FAILED operation denies acquisition'
);
select pg_temp.set_task3_operation_state_v1('RETRY_SCHEDULED');
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  'P0001', 'REPOSITORY_BINDING_STALE',
  'RETRY_SCHEDULED operation denies acquisition'
);
select pg_temp.set_task3_operation_state_v1('TERMINAL_FAILED');
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  'P0001', 'REPOSITORY_BINDING_STALE',
  'TERMINAL_FAILED operation denies acquisition'
);
select pg_temp.set_task3_operation_state_v1('BOUND');

set local session_replication_role = replica;
update public.website_execution_workspaces
set repository_external_id = null
where website_workspace_id = (
  select website_workspace_id from task3_contexts where context_label = 'A'
);
set local session_replication_role = origin;
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  'P0001', 'REPOSITORY_BINDING_MISSING',
  'missing repository_external_id denies acquisition'
);
set local session_replication_role = replica;
update public.website_execution_workspaces as workspace
set repository_external_id = fixture.repository_external_id,
    repository_node_id = null
from task3_contexts as fixture
where fixture.context_label = 'A'
  and workspace.website_workspace_id = fixture.website_workspace_id;
set local session_replication_role = origin;
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  'P0001', 'REPOSITORY_BINDING_MISSING',
  'missing repository node identity denies acquisition'
);
set local session_replication_role = replica;
update public.website_execution_workspaces as workspace
set repository_node_id = fixture.repository_node_id,
    repository_marker_commit_sha = null
from task3_contexts as fixture
where fixture.context_label = 'A'
  and workspace.website_workspace_id = fixture.website_workspace_id;
set local session_replication_role = origin;
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  'P0001', 'REPOSITORY_BINDING_MISSING',
  'missing repository marker denies acquisition'
);
set local session_replication_role = replica;
update public.website_execution_workspaces as workspace
set repository_marker_commit_sha = repeat('c', 40),
    repository_external_id = fixture.repository_external_id + 100
from task3_contexts as fixture
where fixture.context_label = 'A'
  and workspace.website_workspace_id = fixture.website_workspace_id;
set local session_replication_role = origin;
select throws_ok(
  $$select pg_temp.acquire_project_files_v1(
    (select quote_request_id from task3_contexts where context_label = 'A'),
    'DIRECTORY')$$,
  'P0001', 'REPOSITORY_BINDING_STALE',
  'stale repository identity denies acquisition'
);
set local session_replication_role = replica;
update public.website_execution_workspaces as workspace
set repository_external_id = fixture.repository_external_id
from task3_contexts as fixture
where fixture.context_label = 'A'
  and workspace.website_workspace_id = fixture.website_workspace_id;
set local session_replication_role = origin;

create temporary table task3_matrix(
  workspace_state text,
  operation_state text,
  expected_category text,
  expected_guidance text,
  expected_files boolean
) on commit drop;
insert into task3_matrix
select
  workspace_state,
  operation_state,
  case
    when operation_state = 'QUARANTINED' then 'QUARANTINED'
    when operation_state = 'BLOCKED' then 'BLOCKED'
    when operation_state = 'TERMINAL_FAILED' then 'TERMINAL'
    when operation_state in ('RETRYABLE_FAILED', 'RETRY_SCHEDULED')
      then 'RETRYABLE'
    else null
  end,
  case
    when operation_state = 'QUARANTINED' then 'RECONCILIATION_REQUIRED'
    when operation_state in ('BLOCKED', 'TERMINAL_FAILED')
      then 'CONTACT_OWNER'
    when operation_state in ('RETRYABLE_FAILED', 'RETRY_SCHEDULED')
      then 'REFRESH_LATER'
    when workspace_state = 'READY' then 'RECONCILIATION_REQUIRED'
    when workspace_state = 'REPOSITORY_FAILED' then 'CONTACT_OWNER'
    when workspace_state in ('PENDING_REPOSITORY', 'REPOSITORY_PROVISIONING')
      or operation_state in (
        'CLAIMED', 'CREATING', 'EXTERNAL_CREATED', 'VERIFYING'
      ) then 'WAIT'
    when workspace_state = 'REPOSITORY_READY'
      and operation_state = 'COMPLETE' then null
    else 'RECONCILIATION_REQUIRED'
  end,
  workspace_state = 'REPOSITORY_READY' and operation_state = 'COMPLETE'
from unnest(array[
  'PENDING_REPOSITORY', 'REPOSITORY_PROVISIONING', 'REPOSITORY_READY',
  'REPOSITORY_FAILED', 'READY'
]) as workspace_state
cross join unnest(array[
  'CLAIMED', 'CREATING', 'EXTERNAL_CREATED', 'VERIFYING', 'COMPLETE',
  'RETRYABLE_FAILED', 'RETRY_SCHEDULED', 'BLOCKED', 'QUARANTINED',
  'TERMINAL_FAILED', null, 'UNKNOWN_PERSISTED_VALUE'
]) as operation_state;

create function pg_temp.project_task3_matrix_v1(
  p_workspace_state text,
  p_operation_state text
)
returns jsonb
language plpgsql
as $$
declare
  v_fixture task3_contexts%rowtype;
begin
  select * into v_fixture from task3_contexts where context_label = 'A';
  set local session_replication_role = replica;
  update public.website_execution_workspaces
  set workspace_state = p_workspace_state
  where website_workspace_id = v_fixture.website_workspace_id;
  update public.website_repository_provisioning_operations
  set state = case when p_operation_state = 'COMPLETE'
    then 'BOUND' else p_operation_state end,
    updated_at = clock_timestamp()
  where operation_id = v_fixture.marker_operation_id;
  set local session_replication_role = origin;
  return pg_temp.get_workspace_v3(v_fixture.quote_request_id)->'workspace';
end;
$$;

select is(
  projected.payload->>'repository_failure_category',
  matrix.expected_category,
  format('failure category matrix: %s x %s',
    matrix.workspace_state, coalesce(matrix.operation_state, 'null'))
)
from task3_matrix as matrix
cross join lateral (
  select pg_temp.project_task3_matrix_v1(
    matrix.workspace_state, matrix.operation_state
  ) as payload
) as projected;

select is(
  projected.payload->>'repository_recovery_guidance',
  matrix.expected_guidance,
  format('recovery guidance matrix: %s x %s',
    matrix.workspace_state, coalesce(matrix.operation_state, 'null'))
)
from task3_matrix as matrix
cross join lateral (
  select pg_temp.project_task3_matrix_v1(
    matrix.workspace_state, matrix.operation_state
  ) as payload
) as projected;

select is(
  (projected.payload->'capabilities'->>'project_files_read')::boolean,
  matrix.expected_files,
  format('project-files capability matrix: %s x %s',
    matrix.workspace_state, coalesce(matrix.operation_state, 'null'))
)
from task3_matrix as matrix
cross join lateral (
  select pg_temp.project_task3_matrix_v1(
    matrix.workspace_state, matrix.operation_state
  ) as payload
) as projected;

select ok(
  not exists (
    select 1
    from task3_matrix as matrix
    cross join lateral (
      select pg_temp.project_task3_matrix_v1(
        matrix.workspace_state, matrix.operation_state
      ) as payload
    ) as projected
    where matrix.operation_state = 'UNKNOWN_PERSISTED_VALUE'
      and projected.payload->>'repository_operation_state' is not null
  ),
  'unknown persisted operation state normalizes to null without escaping'
);

select ok(
  lower(pg_get_functiondef(
    'public.acquire_website_project_files_read_v1(uuid,text)'::regprocedure
  )) !~ '(insert\s+into|update|delete\s+from|merge\s+into)\s+public\.website_repository_provisioning'
  and lower(pg_get_functiondef(
    'public.acquire_website_project_files_read_v1(uuid,text)'::regprocedure
  )) !~ '(insert\s+into|update|delete\s+from|merge\s+into)\s+public\.website_execution_workspaces',
  'acquisition contains no repository-operation or workspace mutation'
);

select * from finish();
rollback;