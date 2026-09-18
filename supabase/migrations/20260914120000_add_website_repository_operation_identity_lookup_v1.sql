create function public.get_website_repository_operation_by_identity_v1(
  p_website_workspace_id uuid,
  p_website_work_context_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_workspace_context_id uuid;
  v_match_count integer;
begin
  if p_website_workspace_id is null
     or p_website_work_context_id is null
     or p_idempotency_key is null then
    raise exception using
      errcode = '22023',
      message = 'WEBSITE_REPOSITORY_OPERATION_IDENTITY_REQUIRED';
  end if;

  v_operator := lws_internal.require_website_repository_owner_v1();

  select workspace.website_work_context_id
  into v_workspace_context_id
  from public.website_execution_workspaces as workspace
  where workspace.website_workspace_id = p_website_workspace_id;

  if not found
     or v_workspace_context_id is distinct from p_website_work_context_id then
    raise exception using errcode = '42501', message = 'AUTHORITY_MISMATCH';
  end if;

  select count(*)::integer
  into v_match_count
  from public.website_repository_provisioning_operations as operation
  where operation.website_workspace_id = p_website_workspace_id
    and operation.website_work_context_id = p_website_work_context_id
    and operation.idempotency_key = p_idempotency_key;

  if v_match_count > 1 then
    raise exception using errcode = 'P0003', message = 'AMBIGUOUS_OPERATION';
  end if;

  if v_match_count = 0 then
    if exists (
      select 1
      from public.website_repository_provisioning_operations as operation
      where operation.actor_id = v_operator.operator_id
        and operation.idempotency_key = p_idempotency_key
        and (
          operation.website_workspace_id is distinct from p_website_workspace_id
          or operation.website_work_context_id is distinct from p_website_work_context_id
        )
    ) then
      raise exception using errcode = '42501', message = 'AUTHORITY_MISMATCH';
    end if;
    raise exception using
      errcode = 'P0002',
      message = 'WEBSITE_REPOSITORY_OPERATION_NOT_FOUND';
  end if;

  select operation.*
  into strict v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.website_workspace_id = p_website_workspace_id
    and operation.website_work_context_id = p_website_work_context_id
    and operation.idempotency_key = p_idempotency_key;

  if v_operation.actor_id <> v_operator.operator_id then
    raise exception using
      errcode = '42501',
      message = 'WEBSITE_REPOSITORY_OPERATION_DENIED';
  end if;

  return jsonb_build_object(
    'operation_id', v_operation.operation_id,
    'state', v_operation.state,
    'website_workspace_id', v_operation.website_workspace_id,
    'website_work_context_id', v_operation.website_work_context_id,
    'claimed_at', v_operation.claimed_at,
    'first_attempt_at', v_operation.first_attempt_at,
    'external_created_at', v_operation.external_created_at,
    'bound_at', v_operation.bound_at,
    'repository_external_id', v_operation.repository_external_id::text,
    'repository_name', v_operation.repository_name,
    'repository_owner', v_operation.repository_owner,
    'repository_visibility', (
      select workspace.repository_visibility
      from public.website_execution_workspaces as workspace
      where workspace.website_workspace_id = v_operation.website_workspace_id
    ),
    'failure_code', v_operation.failure_code,
    'retry_at', v_operation.retry_at,
    'quarantine_evidence_sha256', v_operation.quarantine_evidence_sha256,
    'quarantined_at', v_operation.quarantined_at,
    'quarantine_reason', v_operation.quarantine_reason,
    'quarantine_alert_due_at', v_operation.quarantine_alert_due_at,
    'quarantine_alerted_at', v_operation.quarantine_alerted_at,
    'quarantine_resolution', v_operation.quarantine_resolution,
    'quarantine_resolved_at', v_operation.quarantine_resolved_at
  );
end;
$$;

revoke all on function
  public.get_website_repository_operation_by_identity_v1(uuid,uuid,uuid)
from public,anon,authenticated,service_role;

grant execute on function
  public.get_website_repository_operation_by_identity_v1(uuid,uuid,uuid)
to authenticated;

comment on function
  public.get_website_repository_operation_by_identity_v1(uuid,uuid,uuid) is
  'Read-only OWNER+AAL2 lookup for one repository operation by exact workspace, work-context and idempotency identity.';