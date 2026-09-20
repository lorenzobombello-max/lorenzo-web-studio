create function public.claim_production_website_repository_provisioning_v1(
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

create function public.bind_production_website_repository_v1(
  p_quote_request_id uuid,
  p_operation_id uuid,
  p_verification jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_result jsonb;
  v_marker_sha text;
begin
  if p_quote_request_id is null or p_operation_id is null then
    raise exception using errcode = '22023', message = 'INVALID_PRODUCTION_REPOSITORY_BIND';
  end if;

  perform lws_internal.require_website_repository_owner_v1();

  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  join public.website_execution_workspaces as workspace
    on workspace.website_workspace_id = operation.website_workspace_id
  join public.quote_requests as request
    on request.id = workspace.quote_request_id
  where operation.operation_id = p_operation_id
    and workspace.quote_request_id = p_quote_request_id
    and operation.website_work_context_id = workspace.website_work_context_id
    and request.record_classification = 'production'
    and request.request_kind = 'website'
  for update of operation;

  if not found then
    raise exception using errcode = '42501', message = 'PRODUCTION_REPOSITORY_BIND_DENIED';
  end if;

  v_result := public.bind_website_repository_v1(p_operation_id, p_verification);
  v_marker_sha := p_verification->>'repository_marker_commit_sha';

  perform set_config('lws.website_repository_command', 'on', true);
  update public.website_execution_workspaces
  set last_commit_sha = v_marker_sha,
      last_commit_at = coalesce(last_commit_at, clock_timestamp()),
      updated_at = clock_timestamp()
  where website_workspace_id = v_operation.website_workspace_id
    and website_work_context_id = v_operation.website_work_context_id
    and workspace_state = 'REPOSITORY_READY'
    and repository_marker_commit_sha = v_marker_sha
    and (last_commit_sha is null or last_commit_sha = v_marker_sha);
  perform set_config('lws.website_repository_command', '', true);

  if not found then
    raise exception using errcode = 'P0001', message = 'PRODUCTION_REPOSITORY_COMMIT_BINDING_FAILED';
  end if;

  return v_result;
exception when others then
  perform set_config('lws.website_repository_command', '', true);
  raise;
end;
$$;

revoke all on function public.claim_production_website_repository_provisioning_v1(
  uuid, uuid, uuid, uuid, text, text, text
) from public, anon, service_role;
grant execute on function public.claim_production_website_repository_provisioning_v1(
  uuid, uuid, uuid, uuid, text, text, text
) to authenticated;

revoke all on function public.bind_production_website_repository_v1(
  uuid, uuid, jsonb
) from public, anon, service_role;
grant execute on function public.bind_production_website_repository_v1(
  uuid, uuid, jsonb
) to authenticated;

comment on function public.claim_production_website_repository_provisioning_v1(
  uuid, uuid, uuid, uuid, text, text, text
) is 'OWNER+AAL2 production PRE_PROJECT repository claim bound to one active Website dossier, context, and workspace; no commercial lifecycle gate or mutation.';

comment on function public.bind_production_website_repository_v1(
  uuid, uuid, jsonb
) is 'Binds a verified production repository and records its marker commit as the initial Project Files commit without commercial lifecycle mutation.';
