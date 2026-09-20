create table lws_internal.website_project_files_write_acquisitions (
  acquisition_id uuid primary key default gen_random_uuid(),
  actor_operator_id uuid not null
    references public.commercial_operators(operator_id),
  actor_auth_user_id uuid not null,
  quote_request_id uuid not null references public.quote_requests(id),
  website_work_context_id uuid not null
    references public.website_work_contexts(website_work_context_id),
  write_path text not null,
  expected_commit_sha text not null
    check (expected_commit_sha ~ '^[0-9a-f]{40}$'),
  idempotency_key uuid not null,
  acquired_at timestamptz not null default clock_timestamp()
);

create index website_project_files_write_acquisitions_window_idx
  on lws_internal.website_project_files_write_acquisitions(
    actor_auth_user_id,
    website_work_context_id,
    acquired_at
  );

create table lws_internal.website_project_files_write_leases (
  lease_id uuid primary key default gen_random_uuid(),
  actor_operator_id uuid not null
    references public.commercial_operators(operator_id),
  actor_auth_user_id uuid not null,
  quote_request_id uuid not null references public.quote_requests(id),
  website_work_context_id uuid not null
    references public.website_work_contexts(website_work_context_id),
  website_workspace_id uuid not null
    references public.website_execution_workspaces(website_workspace_id),
  binding_revision bigint not null check (binding_revision > 0),
  repository_provider text not null check (repository_provider = 'GITHUB'),
  repository_owner text not null,
  repository_name text not null,
  repository_external_id bigint not null,
  repository_node_id text not null,
  default_branch text not null,
  repository_ref text not null,
  ref_label text not null,
  marker_operation_id uuid not null
    references public.website_repository_provisioning_operations(operation_id),
  write_path text not null,
  expected_commit_sha text not null
    check (expected_commit_sha ~ '^[0-9a-f]{40}$'),
  idempotency_key uuid not null,
  acquired_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  finalized_at timestamptz,
  finalized_commit_sha text
    check (finalized_commit_sha is null or finalized_commit_sha ~ '^[0-9a-f]{40}$'),
  finalized_created boolean,
  released_at timestamptz,
  constraint website_project_files_write_lease_lifetime check (
    expires_at = acquired_at + interval '30 seconds'
  ),
  constraint website_project_files_write_lease_release check (
    released_at is null or released_at >= acquired_at
  ),
  constraint website_project_files_write_lease_finalize check (
    finalized_at is null or finalized_at >= acquired_at
  ),
  constraint website_project_files_write_lease_finalize_payload check (
    (finalized_at is null and finalized_commit_sha is null and finalized_created is null)
    or
    (finalized_at is not null and finalized_commit_sha is not null and finalized_created is not null)
  ),
  constraint website_project_files_write_idempotency_unique unique (
    actor_auth_user_id,
    website_work_context_id,
    idempotency_key
  )
);

create index website_project_files_write_leases_actor_active_idx
  on lws_internal.website_project_files_write_leases(
    actor_auth_user_id,
    expires_at
  ) where released_at is null;

alter table lws_internal.website_project_files_write_acquisitions
  enable row level security;
alter table lws_internal.website_project_files_write_acquisitions
  force row level security;
alter table lws_internal.website_project_files_write_leases
  enable row level security;
alter table lws_internal.website_project_files_write_leases
  force row level security;

revoke all privileges on table
  lws_internal.website_project_files_write_acquisitions,
  lws_internal.website_project_files_write_leases
from public, anon, authenticated, service_role;

create function public.acquire_website_project_files_write_v1(
  p_quote_request_id uuid,
  p_path text,
  p_expected_commit_sha text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_now timestamptz;
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_work jsonb;
  v_context public.website_work_contexts%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_rate_count bigint;
  v_active_leases bigint;
  v_existing lws_internal.website_project_files_write_leases%rowtype;
  v_lease lws_internal.website_project_files_write_leases%rowtype;
begin
  if p_quote_request_id is null then
    raise exception using
      errcode = '22023', message = 'QUOTE_REQUEST_ID_REQUIRED';
  end if;
  if p_path is null or btrim(p_path) = '' then
    raise exception using
      errcode = '22023', message = 'INVALID_PROJECT_PATH';
  end if;
  if p_expected_commit_sha is null
     or p_expected_commit_sha !~ '^[0-9a-f]{40}$' then
    raise exception using
      errcode = '22023', message = 'PROJECT_FILES_STALE_REVISION';
  end if;
  if p_idempotency_key is null then
    raise exception using
      errcode = '22023', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if v_subject is null
     or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select operator.*
  into v_operator
  from public.commercial_operators as operator
  where operator.auth_user_id = v_subject
  for update;

  if not found
     or v_operator.status <> 'ACTIVE'
     or v_operator.role <> 'owner'
     or v_operator.revoked_at is not null then
    raise exception using
      errcode = '42501', message = 'WEBSITE_REPOSITORY_OWNER_REQUIRED';
  end if;

  perform lws_internal.assert_operator_aal2_v1();
  v_work := public.get_operator_website_work_v1(p_quote_request_id);

  if v_work->>'state' not in ('PRE_PROJECT', 'OFFICIAL_PROJECT')
     or not (v_work->'permitted_actions' ? 'OPEN_WEBSITE')
     or nullif(v_work->>'website_work_context_id', '') is null then
    raise exception using
      errcode = 'P0001', message = 'WEBSITE_WORKSPACE_NOT_ELIGIBLE';
  end if;

  select context.*
  into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id =
        (v_work->>'website_work_context_id')::uuid
    and context.quote_request_id = p_quote_request_id
  for update;

  if not found
     or v_context.phase is distinct from v_work->>'mode'
     or v_context.concept_id is distinct from
        nullif(v_work->>'concept_id', '')::uuid
     or v_context.project_id is distinct from
        nullif(v_work->>'project_id', '')::uuid then
    raise exception using
      errcode = 'P0001', message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;

  select workspace.*
  into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_work_context_id = v_context.website_work_context_id
    and workspace.quote_request_id = p_quote_request_id
    and workspace.project_id is not distinct from v_context.project_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001', message = 'WEBSITE_WORKSPACE_NOT_FOUND';
  end if;
  if v_workspace.workspace_state <> 'REPOSITORY_READY' then
    raise exception using
      errcode = 'P0001', message = 'REPOSITORY_NOT_READY';
  end if;
  if v_workspace.repository_provider <> 'GITHUB'
     or v_workspace.repository_owner is null
     or v_workspace.repository_name is null
     or v_workspace.repository_external_id is null
     or v_workspace.repository_node_id is null
     or v_workspace.repository_state <> 'BOUND'
     or v_workspace.repository_visibility <> 'private'
     or v_workspace.repository_marker_commit_sha is null
     or v_workspace.repository_bound_at is null
     or v_workspace.binding_revision < 1
     or v_workspace.default_branch is null then
    raise exception using
      errcode = 'P0001', message = 'REPOSITORY_BINDING_MISSING';
  end if;

  select operation.*
  into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.website_workspace_id = v_workspace.website_workspace_id
    and operation.website_work_context_id = v_context.website_work_context_id
  order by operation.updated_at desc, operation.operation_id desc
  limit 1
  for update;

  if not found
     or v_operation.state <> 'BOUND'
     or v_operation.repository_provider is distinct from
        v_workspace.repository_provider
     or v_operation.repository_owner is distinct from
        v_workspace.repository_owner
     or v_operation.repository_name is distinct from
        v_workspace.repository_name
     or v_operation.repository_external_id is distinct from
        v_workspace.repository_external_id
     or v_operation.repository_node_id is distinct from
        v_workspace.repository_node_id then
    raise exception using
      errcode = 'P0001', message = 'REPOSITORY_BINDING_STALE';
  end if;

  if v_workspace.last_commit_sha is not null
     and v_workspace.last_commit_sha <> p_expected_commit_sha then
    raise exception using
      errcode = 'P0001', message = 'PROJECT_FILES_STALE_REVISION';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('website-project-files-write:' || v_subject::text, 0)
  );
  v_now := clock_timestamp();

  delete from lws_internal.website_project_files_write_acquisitions
  where acquired_at <= v_now - interval '5 minutes';

  select lease.*
  into v_existing
  from lws_internal.website_project_files_write_leases as lease
  where lease.actor_auth_user_id = v_subject
    and lease.website_work_context_id = v_context.website_work_context_id
    and lease.idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_existing.quote_request_id <> p_quote_request_id
       or v_existing.write_path <> p_path
       or v_existing.expected_commit_sha <> p_expected_commit_sha
       or v_existing.website_workspace_id <> v_workspace.website_workspace_id
       or v_existing.binding_revision <> v_workspace.binding_revision
       or v_existing.repository_provider <> v_workspace.repository_provider
       or v_existing.repository_owner <> v_workspace.repository_owner
       or v_existing.repository_name <> v_workspace.repository_name
       or v_existing.repository_external_id <> v_workspace.repository_external_id
       or v_existing.repository_node_id <> v_workspace.repository_node_id
       or v_existing.marker_operation_id <> v_operation.operation_id then
      raise exception using
        errcode = 'P0001', message = 'PROJECT_FILES_STALE_REVISION';
    end if;
    if v_existing.released_at is null and v_existing.expires_at > v_now then
      return jsonb_build_object(
        'leaseId', v_existing.lease_id,
        'actorAuthUserId', v_existing.actor_auth_user_id,
        'quoteRequestId', v_existing.quote_request_id,
        'websiteWorkContextId', v_existing.website_work_context_id,
        'websiteWorkspaceId', v_existing.website_workspace_id,
        'bindingRevision', v_existing.binding_revision,
        'repositoryProvider', v_existing.repository_provider,
        'repositoryOwner', v_existing.repository_owner,
        'repositoryName', v_existing.repository_name,
        'repositoryExternalId', v_existing.repository_external_id::text,
        'repositoryNodeId', v_existing.repository_node_id,
        'defaultBranch', v_existing.default_branch,
        'repositoryRef', v_existing.repository_ref,
        'refLabel', v_existing.ref_label,
        'markerOperationId', v_existing.marker_operation_id,
        'expiresAt', v_existing.expires_at
      );
    end if;
    if v_existing.finalized_at is not null then
      return jsonb_build_object(
        'leaseId', v_existing.lease_id,
        'actorAuthUserId', v_existing.actor_auth_user_id,
        'quoteRequestId', v_existing.quote_request_id,
        'websiteWorkContextId', v_existing.website_work_context_id,
        'websiteWorkspaceId', v_existing.website_workspace_id,
        'bindingRevision', v_existing.binding_revision,
        'repositoryProvider', v_existing.repository_provider,
        'repositoryOwner', v_existing.repository_owner,
        'repositoryName', v_existing.repository_name,
        'repositoryExternalId', v_existing.repository_external_id::text,
        'repositoryNodeId', v_existing.repository_node_id,
        'defaultBranch', v_existing.default_branch,
        'repositoryRef', v_existing.repository_ref,
        'refLabel', v_existing.ref_label,
        'markerOperationId', v_existing.marker_operation_id,
        'expiresAt', v_existing.expires_at
      );
    end if;
    raise exception using
      errcode = 'P0001', message = 'PROJECT_FILES_STALE_REVISION';
  end if;

  select count(*)
  into v_active_leases
  from lws_internal.website_project_files_write_leases as lease
  where lease.actor_auth_user_id = v_subject
    and lease.released_at is null
    and lease.expires_at > v_now;

  if v_active_leases >= 2 then
    raise exception using
      errcode = 'P0001', message = 'PROJECT_FILES_CONCURRENCY_LIMITED';
  end if;

  select count(*)
  into v_rate_count
  from lws_internal.website_project_files_write_acquisitions as acquisition
  where acquisition.actor_auth_user_id = v_subject
    and acquisition.website_work_context_id = v_context.website_work_context_id
    and acquisition.acquired_at > v_now - interval '60 seconds'
    and acquisition.acquired_at <= v_now;

  if v_rate_count >= 10 then
    raise exception using
      errcode = 'P0001', message = 'PROJECT_FILES_RATE_LIMITED';
  end if;

  insert into lws_internal.website_project_files_write_acquisitions(
    actor_operator_id,
    actor_auth_user_id,
    quote_request_id,
    website_work_context_id,
    write_path,
    expected_commit_sha,
    idempotency_key,
    acquired_at
  ) values (
    v_operator.operator_id,
    v_subject,
    p_quote_request_id,
    v_context.website_work_context_id,
    p_path,
    p_expected_commit_sha,
    p_idempotency_key,
    v_now
  );

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
  ) values (
    v_operator.operator_id,
    v_subject,
    p_quote_request_id,
    v_context.website_work_context_id,
    v_workspace.website_workspace_id,
    v_workspace.binding_revision,
    v_workspace.repository_provider,
    v_workspace.repository_owner,
    v_workspace.repository_name,
    v_workspace.repository_external_id,
    v_workspace.repository_node_id,
    v_workspace.default_branch,
    'heads/' || v_workspace.default_branch,
    v_workspace.default_branch,
    v_operation.operation_id,
    p_path,
    p_expected_commit_sha,
    p_idempotency_key,
    v_now,
    v_now + interval '30 seconds'
  ) returning * into v_lease;

  return jsonb_build_object(
    'leaseId', v_lease.lease_id,
    'actorAuthUserId', v_lease.actor_auth_user_id,
    'quoteRequestId', v_lease.quote_request_id,
    'websiteWorkContextId', v_lease.website_work_context_id,
    'websiteWorkspaceId', v_lease.website_workspace_id,
    'bindingRevision', v_lease.binding_revision,
    'repositoryProvider', v_lease.repository_provider,
    'repositoryOwner', v_lease.repository_owner,
    'repositoryName', v_lease.repository_name,
    'repositoryExternalId', v_lease.repository_external_id::text,
    'repositoryNodeId', v_lease.repository_node_id,
    'defaultBranch', v_lease.default_branch,
    'repositoryRef', v_lease.repository_ref,
    'refLabel', v_lease.ref_label,
    'markerOperationId', v_lease.marker_operation_id,
    'expiresAt', v_lease.expires_at
  );
end;
$$;

create function public.finalize_website_project_files_write_v1(
  p_lease_id uuid,
  p_path text,
  p_expected_commit_sha text,
  p_commit_sha text,
  p_created boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_lease lws_internal.website_project_files_write_leases%rowtype;
begin
  if p_lease_id is null then
    raise exception using
      errcode = '22023', message = 'PROJECT_FILES_LEASE_ID_REQUIRED';
  end if;
  if p_path is null or btrim(p_path) = '' then
    raise exception using
      errcode = '22023', message = 'INVALID_PROJECT_PATH';
  end if;
  if p_expected_commit_sha is null
     or p_expected_commit_sha !~ '^[0-9a-f]{40}$'
     or p_commit_sha is null
     or p_commit_sha !~ '^[0-9a-f]{40}$'
     or p_created is null then
    raise exception using
      errcode = '22023', message = 'PROJECT_FILES_STALE_REVISION';
  end if;
  if v_subject is null
     or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select lease.*
  into v_lease
  from lws_internal.website_project_files_write_leases as lease
  where lease.lease_id = p_lease_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002', message = 'PROJECT_FILES_LEASE_NOT_FOUND';
  end if;
  if v_lease.actor_auth_user_id <> v_subject then
    raise exception using
      errcode = '42501', message = 'PROJECT_FILES_LEASE_NOT_OWNED';
  end if;
  if v_lease.write_path <> p_path
     or v_lease.expected_commit_sha <> p_expected_commit_sha then
    raise exception using
      errcode = 'P0001', message = 'PROJECT_FILES_STALE_REVISION';
  end if;

  if v_lease.finalized_at is not null then
    if v_lease.finalized_commit_sha <> p_commit_sha
       or v_lease.finalized_created is distinct from p_created then
      raise exception using
        errcode = 'P0001', message = 'PROJECT_FILES_STALE_REVISION';
    end if;
  elsif v_lease.released_at is not null
     or v_lease.expires_at <= v_now then
    raise exception using
      errcode = 'P0001', message = 'PROJECT_FILES_STALE_REVISION';
  else
    update lws_internal.website_project_files_write_leases
    set finalized_at = v_now,
        finalized_commit_sha = p_commit_sha,
        finalized_created = p_created,
        released_at = coalesce(released_at, v_now)
    where lease_id = p_lease_id;

    select lease.*
    into v_lease
    from lws_internal.website_project_files_write_leases as lease
    where lease.lease_id = p_lease_id;
  end if;

  return jsonb_build_object(
    'leaseId', v_lease.lease_id,
    'path', v_lease.write_path,
    'expectedCommitSha', v_lease.expected_commit_sha,
    'commitSha', v_lease.finalized_commit_sha,
    'created', v_lease.finalized_created,
    'finalizedAt', v_lease.finalized_at
  );
end;
$$;

create function public.release_website_project_files_write_v1(
  p_lease_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_lease lws_internal.website_project_files_write_leases%rowtype;
begin
  if p_lease_id is null then
    raise exception using
      errcode = '22023', message = 'PROJECT_FILES_LEASE_ID_REQUIRED';
  end if;
  if v_subject is null
     or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select lease.*
  into v_lease
  from lws_internal.website_project_files_write_leases as lease
  where lease.lease_id = p_lease_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002', message = 'PROJECT_FILES_LEASE_NOT_FOUND';
  end if;
  if v_lease.actor_auth_user_id <> v_subject then
    raise exception using
      errcode = '42501', message = 'PROJECT_FILES_LEASE_NOT_OWNED';
  end if;

  update lws_internal.website_project_files_write_leases
  set released_at = coalesce(released_at, clock_timestamp())
  where lease_id = p_lease_id
    and released_at is null;
end;
$$;

revoke all on function
  public.acquire_website_project_files_write_v1(uuid, text, text, uuid),
  public.finalize_website_project_files_write_v1(uuid, text, text, text, boolean),
  public.release_website_project_files_write_v1(uuid)
from public, anon, authenticated, service_role;

grant execute on function
  public.acquire_website_project_files_write_v1(uuid, text, text, uuid),
  public.finalize_website_project_files_write_v1(uuid, text, text, text, boolean),
  public.release_website_project_files_write_v1(uuid)
to authenticated;

comment on table lws_internal.website_project_files_write_acquisitions is
  'Private five-minute accounting for website project file write authority windows.';
comment on table lws_internal.website_project_files_write_leases is
  'Private short-lived immutable write authority leases bound to repository identity.';
comment on function public.acquire_website_project_files_write_v1(uuid, text, text, uuid) is
  'Caller-JWT ACTIVE OWNER+AAL2 project-file write authority acquisition with idempotent lease replay.';
comment on function public.finalize_website_project_files_write_v1(uuid, text, text, text, boolean) is
  'Caller-JWT idempotent write-lease finalization and immutable write audit closure.';
comment on function public.release_website_project_files_write_v1(uuid) is
  'Same-caller idempotent release of a project-file write lease.';

create function public.get_website_execution_workspace_v4(
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_v3 jsonb;
  v_write_enabled boolean;
begin
  v_v3 := public.get_website_execution_workspace_v3(p_quote_request_id);
  v_write_enabled := coalesce(
    (v_v3 #>> '{workspace,capabilities,project_files_read}')::boolean,
    false
  );
  return jsonb_set(
    jsonb_set(v_v3, '{contract_version}', '4'::jsonb),
    '{workspace,capabilities}',
    coalesce(v_v3 #> '{workspace,capabilities}', '{}'::jsonb) ||
      jsonb_build_object('project_files_write', v_write_enabled),
    false
  );
end;
$$;

revoke all on function
  public.get_website_execution_workspace_v4(uuid)
from public, anon;

grant execute on function
  public.get_website_execution_workspace_v4(uuid)
to authenticated;

create table lws_internal.website_project_preview_build_leases (
  preview_lease_id uuid primary key default gen_random_uuid(),
  source_write_lease_id uuid not null unique
    references lws_internal.website_project_files_write_leases(lease_id),
  actor_auth_user_id uuid not null,
  quote_request_id uuid not null references public.quote_requests(id),
  website_work_context_id uuid not null
    references public.website_work_contexts(website_work_context_id),
  website_workspace_id uuid not null
    references public.website_execution_workspaces(website_workspace_id),
  expected_commit_sha text not null check (expected_commit_sha ~ '^[0-9a-f]{40}$'),
  acquired_at timestamptz not null,
  expires_at timestamptz not null,
  released_at timestamptz
);

create table lws_internal.website_project_preview_builds (
  preview_build_id uuid primary key default gen_random_uuid(),
  lease_id uuid not null unique
    references lws_internal.website_project_preview_build_leases(preview_lease_id),
  actor_auth_user_id uuid not null,
  quote_request_id uuid not null references public.quote_requests(id),
  website_work_context_id uuid not null
    references public.website_work_contexts(website_work_context_id),
  website_workspace_id uuid not null
    references public.website_execution_workspaces(website_workspace_id),
  commit_sha text not null check (commit_sha ~ '^[0-9a-f]{40}$'),
  artifact_path text not null,
  artifact_sha256 text not null check (artifact_sha256 ~ '^[0-9a-f]{64}$'),
  artifact_bytes bigint not null check (artifact_bytes between 1 and 1048576),
  build_status text not null check (build_status = 'PASS'),
  built_at timestamptz not null default clock_timestamp()
);

alter table lws_internal.website_project_preview_build_leases enable row level security;
alter table lws_internal.website_project_preview_build_leases force row level security;
alter table lws_internal.website_project_preview_builds enable row level security;
alter table lws_internal.website_project_preview_builds force row level security;
revoke all on table
  lws_internal.website_project_preview_build_leases,
  lws_internal.website_project_preview_builds
from public, anon, authenticated, service_role;

create function public.acquire_website_project_preview_build_v1(
  p_quote_request_id uuid,
  p_expected_commit_sha text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_authority jsonb;
  v_source lws_internal.website_project_files_write_leases%rowtype;
  v_preview lws_internal.website_project_preview_build_leases%rowtype;
begin
  v_authority := public.acquire_website_project_files_write_v1(
    p_quote_request_id,
    'index.html',
    p_expected_commit_sha,
    p_idempotency_key
  );
  select source.* into strict v_source
  from lws_internal.website_project_files_write_leases as source
  where source.lease_id = (v_authority->>'leaseId')::uuid
    and source.actor_auth_user_id = auth.uid()
  for update;
  insert into lws_internal.website_project_preview_build_leases (
    source_write_lease_id, actor_auth_user_id, quote_request_id,
    website_work_context_id, website_workspace_id, expected_commit_sha,
    acquired_at, expires_at
  ) values (
    v_source.lease_id, v_source.actor_auth_user_id, v_source.quote_request_id,
    v_source.website_work_context_id, v_source.website_workspace_id,
    v_source.expected_commit_sha, v_source.acquired_at, v_source.expires_at
  )
  on conflict (source_write_lease_id) do update
  set source_write_lease_id = excluded.source_write_lease_id
  returning * into v_preview;
  return v_authority || jsonb_build_object('leaseId', v_preview.preview_lease_id);
end;
$$;

create function public.finalize_website_project_preview_build_v1(
  p_lease_id uuid,
  p_expected_commit_sha text,
  p_artifact_path text,
  p_artifact_sha256 text,
  p_artifact_bytes bigint,
  p_build_status text
)
returns void
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_lease lws_internal.website_project_preview_build_leases%rowtype;
begin
  select lease.* into v_lease
  from lws_internal.website_project_preview_build_leases as lease
  where lease.preview_lease_id = p_lease_id
  for update;
  if not found or v_lease.actor_auth_user_id <> auth.uid()
    or v_lease.released_at is not null or v_lease.expires_at <= clock_timestamp()
    or v_lease.expected_commit_sha <> p_expected_commit_sha
  then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_LEASE_INVALID';
  end if;
  if p_artifact_path !~ ('^contexts/' || v_lease.website_work_context_id ||
      '/workspaces/' || v_lease.website_workspace_id || '/commits/' ||
      p_expected_commit_sha || '/index-[0-9a-f]{64}[.]html$')
    or p_artifact_sha256 !~ '^[0-9a-f]{64}$'
    or p_artifact_bytes not between 1 and 1048576
    or p_build_status <> 'PASS'
  then
    raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_RESULT_INVALID';
  end if;
  insert into lws_internal.website_project_preview_builds (
    lease_id, actor_auth_user_id, quote_request_id, website_work_context_id,
    website_workspace_id, commit_sha, artifact_path, artifact_sha256,
    artifact_bytes, build_status
  ) values (
    v_lease.preview_lease_id, v_lease.actor_auth_user_id, v_lease.quote_request_id,
    v_lease.website_work_context_id, v_lease.website_workspace_id,
    p_expected_commit_sha, p_artifact_path, p_artifact_sha256,
    p_artifact_bytes, p_build_status
  ) on conflict (lease_id) do nothing;
  update lws_internal.website_project_preview_build_leases
  set released_at = coalesce(released_at, clock_timestamp())
  where preview_lease_id = p_lease_id;
  update lws_internal.website_project_files_write_leases
  set released_at = coalesce(released_at, clock_timestamp())
  where lease_id = v_lease.source_write_lease_id;
end;
$$;

create function public.release_website_project_preview_build_v1(p_lease_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_source_write_lease_id uuid;
begin
  update lws_internal.website_project_preview_build_leases
  set released_at = coalesce(released_at, clock_timestamp())
  where preview_lease_id = p_lease_id
    and actor_auth_user_id = auth.uid()
  returning source_write_lease_id into v_source_write_lease_id;
  if not found then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_LEASE_INVALID';
  end if;
  update lws_internal.website_project_files_write_leases
  set released_at = coalesce(released_at, clock_timestamp())
  where lease_id = v_source_write_lease_id
    and actor_auth_user_id = auth.uid();
end;
$$;

revoke all on function
  public.acquire_website_project_preview_build_v1(uuid, text, uuid),
  public.finalize_website_project_preview_build_v1(uuid, text, text, text, bigint, text),
  public.release_website_project_preview_build_v1(uuid)
from public, anon, authenticated, service_role;
grant execute on function
  public.acquire_website_project_preview_build_v1(uuid, text, uuid),
  public.finalize_website_project_preview_build_v1(uuid, text, text, text, bigint, text),
  public.release_website_project_preview_build_v1(uuid)
to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'website-project-previews', 'website-project-previews', false, 1048576,
  array['text/html']::text[]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;