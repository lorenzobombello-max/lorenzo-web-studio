create table lws_internal.website_project_files_read_acquisitions (
  acquisition_id uuid primary key default gen_random_uuid(),
  actor_operator_id uuid not null
    references public.commercial_operators(operator_id),
  actor_auth_user_id uuid not null,
  website_work_context_id uuid not null
    references public.website_work_contexts(website_work_context_id),
  read_kind text not null check (read_kind in ('DIRECTORY', 'FILE')),
  acquired_at timestamptz not null default clock_timestamp()
);

create index website_project_files_read_acquisitions_window_idx
  on lws_internal.website_project_files_read_acquisitions(
    actor_auth_user_id, website_work_context_id, read_kind, acquired_at
  );

create table lws_internal.website_project_files_read_leases (
  lease_id uuid primary key default gen_random_uuid(),
  actor_operator_id uuid not null
    references public.commercial_operators(operator_id),
  actor_auth_user_id uuid not null,
  quote_request_id uuid not null references public.quote_requests(id),
  website_work_context_id uuid not null
    references public.website_work_contexts(website_work_context_id),
  website_workspace_id uuid not null
    references public.website_execution_workspaces(website_workspace_id),
  read_kind text not null check (read_kind in ('DIRECTORY', 'FILE')),
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
  acquired_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  released_at timestamptz,
  constraint website_project_files_read_lease_lifetime check (
    expires_at = acquired_at + interval '15 seconds'
  ),
  constraint website_project_files_read_lease_release check (
    released_at is null or released_at >= acquired_at
  )
);

create index website_project_files_read_leases_actor_active_idx
  on lws_internal.website_project_files_read_leases(
    actor_auth_user_id, expires_at
  ) where released_at is null;

alter table lws_internal.website_project_files_read_acquisitions
  enable row level security;
alter table lws_internal.website_project_files_read_acquisitions
  force row level security;
alter table lws_internal.website_project_files_read_leases
  enable row level security;
alter table lws_internal.website_project_files_read_leases
  force row level security;

revoke all privileges on table
  lws_internal.website_project_files_read_acquisitions,
  lws_internal.website_project_files_read_leases
from public, anon, authenticated, service_role;

create function public.acquire_website_project_files_read_v1(
  p_quote_request_id uuid,
  p_read_kind text
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
  v_rate_limit integer;
  v_rate_count bigint;
  v_active_leases bigint;
  v_lease lws_internal.website_project_files_read_leases%rowtype;
begin
  if p_quote_request_id is null then
    raise exception using
      errcode = '22023', message = 'QUOTE_REQUEST_ID_REQUIRED';
  end if;
  if p_read_kind is null or p_read_kind not in ('DIRECTORY', 'FILE') then
    raise exception using
      errcode = '22023', message = 'PROJECT_FILES_READ_KIND_INVALID';
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

  perform pg_advisory_xact_lock(
    hashtextextended('website-project-files:' || v_subject::text, 0)
  );
  v_now := clock_timestamp();

  delete from lws_internal.website_project_files_read_acquisitions
  where acquired_at <= v_now - interval '5 minutes';

  select count(*)
  into v_active_leases
  from lws_internal.website_project_files_read_leases as lease
  where lease.actor_auth_user_id = v_subject
    and lease.released_at is null
    and lease.expires_at > v_now;

  if v_active_leases >= 4 then
    raise exception using
      errcode = 'P0001', message = 'PROJECT_FILES_CONCURRENCY_LIMITED';
  end if;

  v_rate_limit := case p_read_kind when 'DIRECTORY' then 30 else 10 end;
  select count(*)
  into v_rate_count
  from lws_internal.website_project_files_read_acquisitions as acquisition
  where acquisition.actor_auth_user_id = v_subject
    and acquisition.website_work_context_id = v_context.website_work_context_id
    and acquisition.read_kind = p_read_kind
    and acquisition.acquired_at > v_now - interval '60 seconds'
    and acquisition.acquired_at <= v_now;

  if v_rate_count >= v_rate_limit then
    raise exception using
      errcode = 'P0001', message = 'PROJECT_FILES_RATE_LIMITED';
  end if;

  insert into lws_internal.website_project_files_read_acquisitions(
    actor_operator_id, actor_auth_user_id, website_work_context_id,
    read_kind, acquired_at
  ) values (
    v_operator.operator_id, v_subject, v_context.website_work_context_id,
    p_read_kind, v_now
  );

  insert into lws_internal.website_project_files_read_leases(
    actor_operator_id, actor_auth_user_id, quote_request_id,
    website_work_context_id, website_workspace_id, read_kind,
    binding_revision, repository_provider, repository_owner,
    repository_name, repository_external_id, repository_node_id,
    default_branch, repository_ref, ref_label, marker_operation_id,
    acquired_at, expires_at
  ) values (
    v_operator.operator_id, v_subject, p_quote_request_id,
    v_context.website_work_context_id, v_workspace.website_workspace_id,
    p_read_kind, v_workspace.binding_revision,
    v_workspace.repository_provider, v_workspace.repository_owner,
    v_workspace.repository_name, v_workspace.repository_external_id,
    v_workspace.repository_node_id, v_workspace.default_branch,
    'heads/' || v_workspace.default_branch, v_workspace.default_branch,
    v_operation.operation_id, v_now, v_now + interval '15 seconds'
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

create function public.release_website_project_files_read_v1(
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
  v_lease lws_internal.website_project_files_read_leases%rowtype;
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
  from lws_internal.website_project_files_read_leases as lease
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

  update lws_internal.website_project_files_read_leases
  set released_at = coalesce(released_at, clock_timestamp())
  where lease_id = p_lease_id
    and released_at is null;
end;
$$;

create function public.get_website_execution_workspace_v3(
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_v2 jsonb;
  v_context public.website_work_contexts%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_operation_state text;
  v_failure_category text;
  v_recovery_guidance text;
  v_binding_verified boolean := false;
  v_owner_eligible boolean := false;
  v_workspace_result jsonb;
begin
  v_v2 := public.get_website_execution_workspace_v2(p_quote_request_id);

  select context.*
  into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id =
        nullif(v_v2->>'website_work_context_id', '')::uuid
    and context.quote_request_id = p_quote_request_id;

  select workspace.*
  into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_work_context_id = v_context.website_work_context_id
    and workspace.quote_request_id = p_quote_request_id
    and workspace.project_id is not distinct from v_context.project_id;

  if not found then
    return (v_v2 - 'workspace') || jsonb_build_object(
      'contract_version', 3,
      'workspace', null
    );
  end if;

  select operation.*
  into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.website_workspace_id = v_workspace.website_workspace_id
    and operation.website_work_context_id = v_context.website_work_context_id
  order by operation.updated_at desc, operation.operation_id desc
  limit 1;

  v_operation_state := case
    when v_operation.state = 'BOUND' then 'COMPLETE'
    when v_operation.state in (
      'CLAIMED', 'CREATING', 'EXTERNAL_CREATED', 'VERIFYING',
      'RETRYABLE_FAILED', 'RETRY_SCHEDULED', 'BLOCKED', 'QUARANTINED',
      'TERMINAL_FAILED'
    ) then v_operation.state
    else null
  end;

  v_failure_category := case
    when v_operation_state = 'QUARANTINED' then 'QUARANTINED'
    when v_operation_state = 'BLOCKED' then 'BLOCKED'
    when v_operation_state = 'TERMINAL_FAILED' then 'TERMINAL'
    when v_operation_state in ('RETRYABLE_FAILED', 'RETRY_SCHEDULED')
      then 'RETRYABLE'
    else null
  end;

  v_binding_verified :=
    v_workspace.workspace_state = 'REPOSITORY_READY'
    and v_operation.state = 'BOUND'
    and v_workspace.binding_revision >= 1
    and v_workspace.default_branch is not null
    and v_workspace.repository_provider = 'GITHUB'
    and v_workspace.repository_owner is not null
    and v_workspace.repository_name is not null
    and v_workspace.repository_external_id is not null
    and v_workspace.repository_node_id is not null
    and v_workspace.repository_visibility = 'private'
    and v_workspace.repository_state = 'BOUND'
    and v_workspace.repository_marker_commit_sha is not null
    and v_workspace.repository_bound_at is not null
    and v_operation.repository_provider is not distinct from
        v_workspace.repository_provider
    and v_operation.repository_owner is not distinct from
        v_workspace.repository_owner
    and v_operation.repository_name is not distinct from
        v_workspace.repository_name
    and v_operation.repository_external_id is not distinct from
        v_workspace.repository_external_id
    and v_operation.repository_node_id is not distinct from
        v_workspace.repository_node_id;

  select exists (
    select 1
    from public.commercial_operators as operator
    where operator.auth_user_id = auth.uid()
      and operator.status = 'ACTIVE'
      and operator.role = 'owner'
      and operator.revoked_at is null
  ) into v_owner_eligible;

  v_recovery_guidance := case
    when v_operation_state = 'QUARANTINED'
      then 'RECONCILIATION_REQUIRED'
    when v_operation_state in ('BLOCKED', 'TERMINAL_FAILED')
      then 'CONTACT_OWNER'
    when v_operation_state in ('RETRYABLE_FAILED', 'RETRY_SCHEDULED')
      then 'REFRESH_LATER'
    when v_workspace.workspace_state = 'READY'
      then 'RECONCILIATION_REQUIRED'
    when v_workspace.workspace_state = 'REPOSITORY_FAILED'
      then 'CONTACT_OWNER'
    when v_workspace.workspace_state in (
      'PENDING_REPOSITORY', 'REPOSITORY_PROVISIONING'
    ) or v_operation_state in (
      'CLAIMED', 'CREATING', 'EXTERNAL_CREATED', 'VERIFYING'
    ) then 'WAIT'
    when v_binding_verified then null
    else 'RECONCILIATION_REQUIRED'
  end;

  v_workspace_result := jsonb_build_object(
    'website_workspace_id', v_workspace.website_workspace_id,
    'website_work_context_id', v_workspace.website_work_context_id,
    'project_id', v_workspace.project_id,
    'quote_request_id', v_workspace.quote_request_id,
    'workspace_state', v_workspace.workspace_state,
    'repository_operation_state', v_operation_state,
    'repository_failure_category', v_failure_category,
    'repository_recovery_guidance', v_recovery_guidance,
    'repository_provider', v_workspace.repository_provider,
    'repository_owner', v_workspace.repository_owner,
    'repository_name', v_workspace.repository_name,
    'repository_navigation_url', case
      when v_workspace.repository_provider = 'GITHUB'
        and v_workspace.repository_owner is not null
        and v_workspace.repository_name is not null
      then 'https://github.com/' || v_workspace.repository_owner || '/' ||
        v_workspace.repository_name
      else null
    end,
    'default_branch', v_workspace.default_branch,
    'preview_branch', v_workspace.preview_branch,
    'preview_url', v_workspace.preview_url,
    'last_commit_sha', v_workspace.last_commit_sha,
    'last_commit_at', v_workspace.last_commit_at,
    'last_build_result', v_workspace.last_build_result,
    'last_build_at', v_workspace.last_build_at,
    'binding_revision', v_workspace.binding_revision,
    'provisioned_by', v_workspace.provisioned_by,
    'provisioned_at', v_workspace.provisioned_at,
    'created_at', v_workspace.created_at,
    'updated_at', v_workspace.updated_at,
    'capabilities', jsonb_build_object(
      'project_files_read', v_binding_verified and v_owner_eligible
    )
  );

  return (v_v2 - 'workspace') || jsonb_build_object(
    'contract_version', 3,
    'workspace', v_workspace_result
  );
end;
$$;

revoke all on function
  public.acquire_website_project_files_read_v1(uuid, text),
  public.release_website_project_files_read_v1(uuid),
  public.get_website_execution_workspace_v3(uuid)
from public, anon, authenticated, service_role;

grant execute on function
  public.acquire_website_project_files_read_v1(uuid, text),
  public.release_website_project_files_read_v1(uuid),
  public.get_website_execution_workspace_v3(uuid)
to authenticated;

comment on table lws_internal.website_project_files_read_acquisitions is
  'Private five-minute project-file read accounting for exact rolling budgets.';
comment on table lws_internal.website_project_files_read_leases is
  'Private short-lived immutable repository read authority snapshots.';
comment on function public.acquire_website_project_files_read_v1(uuid, text) is
  'Caller-JWT ACTIVE OWNER+AAL2 project-file read authority acquisition.';
comment on function public.release_website_project_files_read_v1(uuid) is
  'Same-caller idempotent release of a project-file read lease.';
comment on function public.get_website_execution_workspace_v3(uuid) is
  'Forward-only closed Website Execution v3 projection with safe project-file eligibility.';