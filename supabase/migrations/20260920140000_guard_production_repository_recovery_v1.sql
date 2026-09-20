create or replace function public.claim_production_website_repository_provisioning_v1(
  p_quote_request_id uuid,
  p_website_workspace_id uuid,
  p_website_work_context_id uuid,
  p_idempotency_key uuid,
  p_starter_source text,
  p_starter_version text,
  p_starter_commit_sha text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_work jsonb;
  v_request public.quote_requests%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_latest_operation public.website_repository_provisioning_operations%rowtype;
begin
  if p_quote_request_id is null
     or p_website_workspace_id is null
     or p_website_work_context_id is null then
    raise exception using errcode = '22023', message = 'INVALID_PRODUCTION_REPOSITORY_CLAIM';
  end if;

  perform lws_internal.require_website_repository_owner_v1();

  select request.* into v_request
  from public.quote_requests as request
  where request.id = p_quote_request_id
  for key share;

  v_work := public.get_operator_website_work_v1(p_quote_request_id);

  select workspace.* into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_workspace_id = p_website_workspace_id
    and workspace.website_work_context_id = p_website_work_context_id
    and workspace.quote_request_id = p_quote_request_id
  for update;

  if v_request.id is null
     or v_request.record_classification <> 'production'
     or v_request.request_kind <> 'website'
     or not found
     or v_work->>'state' <> 'PRE_PROJECT'
     or v_work->>'mode' <> 'PRE_PROJECT'
     or (v_work->>'website_work_context_id')::uuid <> p_website_work_context_id
     or nullif(v_work->>'project_id', '') is not null
     or (v_work->>'commercially_released')::boolean
     or not (v_work->'permitted_actions' ? 'OPEN_WEBSITE')
     or v_workspace.project_id is not null
     or v_workspace.workspace_state not in (
       'PENDING_REPOSITORY', 'REPOSITORY_FAILED', 'REPOSITORY_PROVISIONING',
       'REPOSITORY_READY'
     ) then
    raise exception using errcode = '42501', message = 'PRODUCTION_REPOSITORY_CONTEXT_DENIED';
  end if;

  select operation.* into v_latest_operation
  from public.website_repository_provisioning_operations as operation
  where operation.website_workspace_id = p_website_workspace_id
     or operation.website_work_context_id = p_website_work_context_id
  order by operation.claimed_at desc
  limit 1;

  if found
     and v_latest_operation.idempotency_key is distinct from p_idempotency_key
     and v_latest_operation.state = 'TERMINAL_FAILED'
     and (
       v_latest_operation.repository_external_id is not null
       or v_latest_operation.repository_node_id is not null
       or v_latest_operation.external_created_at is not null
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'PRODUCTION_REPOSITORY_RECOVERY_REQUIRED';
  end if;

  return public.claim_website_repository_provisioning_v1(
    p_website_workspace_id,
    p_website_work_context_id,
    p_idempotency_key,
    p_starter_source,
    p_starter_version,
    p_starter_commit_sha
  );
end;
$$;

comment on function public.claim_production_website_repository_provisioning_v1(
  uuid, uuid, uuid, uuid, text, text, text
) is 'OWNER+AAL2 production PRE_PROJECT claim authority; fresh provisioning is structurally denied after durable external repository identity and must use recovery.';