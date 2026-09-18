create function public.get_task13_repository_recovery_authority_v1(
  p_operation_id uuid,
  p_website_work_context_id uuid,
  p_website_workspace_id uuid
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
  v_context public.website_work_contexts%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_request public.quote_requests%rowtype;
  v_concept public.website_concepts%rowtype;
begin
  if p_operation_id is null
     or p_website_work_context_id is null
     or p_website_workspace_id is null then
    raise exception using
      errcode='22023',message='TASK13_RECOVERY_AUTHORITY_IDENTITY_REQUIRED';
  end if;

  v_operator := lws_internal.require_website_repository_owner_v1();

  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.operation_id=p_operation_id;
  if not found then
    raise exception using
      errcode='P0002',message='TASK13_RECOVERY_OPERATION_NOT_FOUND';
  end if;
  if v_operation.actor_id is distinct from v_operator.operator_id
     or v_operation.website_work_context_id is distinct from
        p_website_work_context_id
     or v_operation.website_workspace_id is distinct from
        p_website_workspace_id then
    raise exception using
      errcode='42501',message='TASK13_RECOVERY_AUTHORITY_MISMATCH';
  end if;

  select context.* into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id=p_website_work_context_id;
  select workspace.* into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_workspace_id=p_website_workspace_id;
  if v_context.website_work_context_id is null
     or v_workspace.website_workspace_id is null
     or v_workspace.website_work_context_id is distinct from
        v_context.website_work_context_id
     or v_workspace.quote_request_id is distinct from v_context.quote_request_id
     or v_context.phase <> 'PRE_PROJECT'
     or v_context.concept_id is null
     or v_context.project_id is not null
     or v_workspace.project_id is not null then
    raise exception using
      errcode='42501',message='TASK13_RECOVERY_AUTHORITY_MISMATCH';
  end if;

  select request.* into v_request
  from public.quote_requests as request
  where request.id=v_context.quote_request_id;
  select concept.* into v_concept
  from public.website_concepts as concept
  where concept.concept_id=v_context.concept_id
    and concept.quote_request_id=v_context.quote_request_id;
  if v_request.id is null
     or v_concept.concept_id is null
     or v_request.record_classification <> 'internal_e2e'
     or v_request.request_kind <> 'website'
     or v_concept.mode <> 'PRE_PROJECT'
     or v_concept.commercially_released <> false then
    raise exception using
      errcode='42501',message='TASK13_RECOVERY_AUTHORITY_MISMATCH';
  end if;

  return jsonb_build_object(
    'operation_found',true,
    'operation_id',v_operation.operation_id,
    'website_work_context_id',v_operation.website_work_context_id,
    'website_workspace_id',v_operation.website_workspace_id,
    'operation_state',v_operation.state,
    'failure_code',v_operation.failure_code,
    'external_created_at_present',v_operation.external_created_at is not null,
    'repository_external_id',v_operation.repository_external_id::text,
    'target_owner',v_operation.repository_owner,
    'target_repository_name',v_operation.repository_name,
    'bound_at_present',v_operation.bound_at is not null,
    'quarantine_present',
      v_operation.state='QUARANTINED'
      or v_operation.quarantined_at is not null
      or v_operation.quarantine_evidence_sha256 is not null,
    'customer_binding_present',
      v_context.project_id is not null
      or v_concept.promoted_project_id is not null,
    'dossier_binding_present',
      v_request.application_reference is not null,
    'repository_binding_present',
      v_workspace.repository_external_id is not null
      or v_workspace.repository_node_id is not null
      or v_workspace.repository_bound_at is not null
      or v_workspace.repository_state is not null
  );
end;
$$;

revoke all on function
  public.get_task13_repository_recovery_authority_v1(uuid,uuid,uuid)
from public,anon,authenticated,service_role;

grant execute on function
  public.get_task13_repository_recovery_authority_v1(uuid,uuid,uuid)
to authenticated;

comment on function
  public.get_task13_repository_recovery_authority_v1(uuid,uuid,uuid) is
  'Read-only OWNER+AAL2 Task 13 recovery authority by exact operation, work-context and workspace identity; exposes closed metadata and binding-presence booleans without an idempotency key.';