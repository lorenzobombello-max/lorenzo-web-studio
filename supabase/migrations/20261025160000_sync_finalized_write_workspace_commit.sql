alter function public.finalize_website_project_files_write_v1(uuid,text,text,text,boolean)
  set schema lws_internal;
alter function lws_internal.finalize_website_project_files_write_v1(uuid,text,text,text,boolean)
  rename to finalize_project_files_write_legacy_v1;
revoke all on function lws_internal.finalize_project_files_write_legacy_v1(uuid,text,text,text,boolean)
  from public, anon, authenticated, service_role;

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
  v_hint lws_internal.website_project_files_write_leases%rowtype;
  v_lease lws_internal.website_project_files_write_leases%rowtype;
  v_operator public.commercial_operators%rowtype;
  v_context public.website_work_contexts%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_work jsonb;
  v_result jsonb;
begin
  if v_subject is null or coalesce(auth.jwt()->>'role', '') <> 'authenticated' then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  if p_lease_id is null then
    raise exception using errcode = '22023', message = 'PROJECT_FILES_LEASE_ID_REQUIRED';
  end if;
  -- The unlocked lookup supplies only lock-routing identities; revalidate below.
  select * into v_hint from lws_internal.website_project_files_write_leases
  where lease_id = p_lease_id and actor_auth_user_id = v_subject;
  if not found then
    raise exception using errcode = '42501', message = 'PROJECT_FILES_LEASE_NOT_OWNED';
  end if;

  -- Match acquisition's operator -> context -> workspace -> operation lock order.
  select * into v_operator from public.commercial_operators
  where auth_user_id = v_subject for update;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role <> 'owner'
     or v_operator.revoked_at is not null
     or v_operator.operator_id is distinct from v_hint.actor_operator_id then
    raise exception using errcode = '42501', message = 'WEBSITE_REPOSITORY_OWNER_REQUIRED';
  end if;
  perform lws_internal.assert_operator_aal2_v1();
  v_work := public.get_operator_website_work_v1(v_hint.quote_request_id);
  if v_work->>'state' is null
     or v_work->>'state' not in ('PRE_PROJECT', 'OFFICIAL_PROJECT')
     or not coalesce(v_work->'permitted_actions' ? 'OPEN_WEBSITE', false)
     or nullif(v_work->>'website_work_context_id', '')::uuid
        is distinct from v_hint.website_work_context_id then
    raise exception using errcode = 'P0001', message = 'WEBSITE_WORKSPACE_NOT_ELIGIBLE';
  end if;
  select * into v_context from public.website_work_contexts
  where website_work_context_id = v_hint.website_work_context_id
    and quote_request_id = v_hint.quote_request_id for update;
  if not found or v_context.phase is distinct from v_work->>'mode'
     or v_context.concept_id is distinct from nullif(v_work->>'concept_id', '')::uuid
     or v_context.project_id is distinct from nullif(v_work->>'project_id', '')::uuid then
    raise exception using errcode = 'P0001', message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;
  select * into v_workspace from public.website_execution_workspaces
  where website_workspace_id = v_hint.website_workspace_id
    and website_work_context_id = v_context.website_work_context_id
    and quote_request_id = v_hint.quote_request_id
    and project_id is not distinct from v_context.project_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_WORKSPACE_NOT_FOUND';
  end if;
  select * into v_operation from public.website_repository_provisioning_operations
  where operation_id = lws_internal.get_website_repository_canonical_durable_operation_id_v1(
    v_workspace.website_workspace_id, v_context.website_work_context_id)
  for update;
  if not found or v_operation.state is distinct from 'BOUND'
     or v_operation.operation_id is distinct from v_hint.marker_operation_id
     or row(v_operation.repository_provider, v_operation.repository_owner,
            v_operation.repository_name, v_operation.repository_external_id,
            v_operation.repository_node_id)
        is distinct from row(v_workspace.repository_provider, v_workspace.repository_owner,
            v_workspace.repository_name, v_workspace.repository_external_id,
            v_workspace.repository_node_id) then
    raise exception using errcode = 'P0001', message = 'REPOSITORY_BINDING_STALE';
  end if;
  select * into v_lease from lws_internal.website_project_files_write_leases
  where lease_id = p_lease_id for update;
  if not found or v_lease.actor_auth_user_id is distinct from v_subject
     or v_lease.actor_operator_id is distinct from v_operator.operator_id
     or row(v_lease.quote_request_id, v_lease.website_work_context_id,
            v_lease.website_workspace_id, v_lease.marker_operation_id)
        is distinct from row(v_hint.quote_request_id, v_hint.website_work_context_id,
            v_hint.website_workspace_id, v_hint.marker_operation_id) then
    raise exception using errcode = '42501', message = 'PROJECT_FILES_LEASE_NOT_OWNED';
  end if;
  if v_workspace.workspace_state is distinct from 'REPOSITORY_READY'
     or v_workspace.repository_state is distinct from 'BOUND'
     or v_workspace.repository_visibility is distinct from 'private'
     or v_workspace.repository_bound_at is null
     or v_workspace.repository_marker_commit_sha is null
     or v_workspace.binding_revision < 1
     or row(v_workspace.binding_revision, v_workspace.repository_provider,
            v_workspace.repository_owner, v_workspace.repository_name,
            v_workspace.repository_external_id, v_workspace.repository_node_id,
            v_workspace.default_branch)
        is distinct from row(v_lease.binding_revision, v_lease.repository_provider,
            v_lease.repository_owner, v_lease.repository_name,
            v_lease.repository_external_id, v_lease.repository_node_id,
            v_lease.default_branch)
     or v_lease.repository_ref is distinct from 'heads/' || v_workspace.default_branch
     or v_lease.ref_label is distinct from v_workspace.default_branch then
    raise exception using errcode = 'P0001', message = 'REPOSITORY_BINDING_STALE';
  end if;
  if v_workspace.last_commit_sha is distinct from p_expected_commit_sha
     and not (v_lease.finalized_at is not null
       and v_workspace.last_commit_sha is not distinct from v_lease.finalized_commit_sha
       and v_lease.finalized_commit_sha is not distinct from p_commit_sha) then
    raise exception using errcode = 'P0001', message = 'PROJECT_FILES_STALE_REVISION';
  end if;
  if v_lease.finalized_at is not null
     and v_workspace.last_commit_sha is distinct from p_commit_sha then
    -- Only an already-finalized write may repair its old projection.
    if exists (
      select 1 from lws_internal.website_project_files_write_leases other
      where other.website_workspace_id = v_workspace.website_workspace_id
        and other.lease_id <> p_lease_id
        and ((other.finalized_at is null and other.released_at is null
              and other.expires_at > clock_timestamp())
          or other.finalized_at >= v_lease.finalized_at)
    ) then
      raise exception using errcode = 'P0001', message = 'PROJECT_FILES_STALE_REVISION';
    end if;
  end if;
  -- Preserve the original parameter, lease expiry and finalized-result checks.
  v_result := lws_internal.finalize_project_files_write_legacy_v1(
    p_lease_id, p_path, p_expected_commit_sha, p_commit_sha, p_created);
  update public.website_execution_workspaces
  set last_commit_sha = p_commit_sha
  where website_workspace_id = v_workspace.website_workspace_id
    and last_commit_sha is distinct from p_commit_sha;
  return v_result;
end;
$$;

revoke all on function public.finalize_website_project_files_write_v1(uuid,text,text,text,boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.finalize_website_project_files_write_v1(uuid,text,text,text,boolean)
  to authenticated;
comment on function public.finalize_website_project_files_write_v1(uuid,text,text,text,boolean) is
  'Atomically finalizes a write and advances its workspace projection; exact finalized replay may reconcile a legacy projection under current authority and binding locks.';
