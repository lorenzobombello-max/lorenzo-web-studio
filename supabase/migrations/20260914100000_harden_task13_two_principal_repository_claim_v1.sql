create or replace function lws_internal.website_repository_operation_result_v1(
  p_operation public.website_repository_provisioning_operations,
  p_result text
)
returns jsonb
language sql
stable
set search_path = public, pg_catalog
as $$
  select jsonb_build_object(
    'result', p_result,
    'operation_id', p_operation.operation_id,
    'website_workspace_id', p_operation.website_workspace_id,
    'website_work_context_id', p_operation.website_work_context_id,
    'state', p_operation.state,
    'repository_provider', p_operation.repository_provider,
    'repository_owner', p_operation.repository_owner,
    'repository_name', p_operation.repository_name,
    'starter_source', p_operation.starter_source,
    'starter_version', p_operation.starter_version,
    'starter_commit_sha', p_operation.starter_commit_sha,
    'repository_external_id', p_operation.repository_external_id::text,
    'repository_node_id', p_operation.repository_node_id,
    'repository_visibility', workspace.repository_visibility,
    'default_branch', workspace.default_branch,
    'repository_marker_commit_sha', workspace.repository_marker_commit_sha,
    'attempt_count', p_operation.attempt_count,
    'failure_code', p_operation.failure_code,
    'retry_at', p_operation.retry_at,
    'first_attempt_at', p_operation.first_attempt_at,
    'retry_window_expires_at', p_operation.retry_window_expires_at,
    'provider_retry_after_at', p_operation.provider_retry_after_at,
    'retry_action', p_operation.retry_action,
    'quarantine_evidence_sha256', p_operation.quarantine_evidence_sha256,
    'quarantined_at', p_operation.quarantined_at,
    'quarantine_reason', p_operation.quarantine_reason,
    'quarantine_alert_due_at', p_operation.quarantine_alert_due_at,
    'quarantine_alerted_at', p_operation.quarantine_alerted_at,
    'quarantine_resolution', p_operation.quarantine_resolution,
    'quarantine_resolved_at', p_operation.quarantine_resolved_at,
    'claimed_at', p_operation.claimed_at,
    'updated_at', p_operation.updated_at,
    'external_created_at', p_operation.external_created_at,
    'bound_at', p_operation.bound_at
  )
  from public.website_execution_workspaces as workspace
  where workspace.website_workspace_id = p_operation.website_workspace_id
$$;

create or replace function public.claim_website_repository_provisioning_v1(
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
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_context public.website_work_contexts%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_repository_owner text;
  v_repository_name text;
  v_fingerprint character(64);
  v_now timestamptz;
begin
  if p_website_workspace_id is null
     or p_website_work_context_id is null
     or p_idempotency_key is null
     or p_starter_source !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,98}[A-Za-z0-9]/[A-Za-z0-9][A-Za-z0-9._-]{0,98}[A-Za-z0-9]$'
     or p_starter_version !~ '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$'
     or p_starter_commit_sha !~ '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' then
    raise exception using
      errcode = '22023',
      message = 'INVALID_WEBSITE_REPOSITORY_CLAIM';
  end if;

  v_operator := lws_internal.require_website_repository_owner_v1();

  select workspace.* into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_workspace_id = p_website_workspace_id
  for update;

  select context.* into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id = p_website_work_context_id
  for update;

  if v_workspace.website_workspace_id is null
     or v_context.website_work_context_id is null
     or v_workspace.website_work_context_id is distinct from v_context.website_work_context_id
     or v_workspace.quote_request_id is distinct from v_context.quote_request_id
     or v_context.phase <> 'PRE_PROJECT'
     or v_context.project_id is not null then
    raise exception using
      errcode = '42501',
      message = 'WEBSITE_REPOSITORY_CONTEXT_DENIED';
  end if;

  v_repository_owner := case
    when exists (
      select 1 from public.quote_requests as request
      where request.id = v_context.quote_request_id
        and request.record_classification = 'internal_e2e'
    ) then 'lorenzo-web-solutions-lab'
    else 'lorenzo-web-solutions'
  end;
  v_repository_name := 'lws-web-' || replace(lower(v_context.website_work_context_id::text), '-', '');

  if p_starter_source <> 'lorenzo-web-solutions/lws-website-starter' then
    raise exception using
      errcode = '22023',
      message = 'WEBSITE_REPOSITORY_STARTER_OWNER_INVALID';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'authority_version', 'website_repository_provisioning_v1',
    'website_workspace_id', p_website_workspace_id,
    'website_work_context_id', p_website_work_context_id,
    'repository_name', v_repository_name,
    'starter_source', p_starter_source,
    'starter_version', p_starter_version,
    'starter_commit_sha', p_starter_commit_sha
  )::text, 'UTF8'), 'sha256'), 'hex')::character(64);

  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.actor_id = v_operator.operator_id
    and operation.idempotency_key = p_idempotency_key;

  if found then
    if v_operation.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return lws_internal.website_repository_operation_result_v1(
      v_operation, 'REPLAY'
    );
  end if;

  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.website_workspace_id = p_website_workspace_id
     or operation.website_work_context_id = p_website_work_context_id
  order by operation.claimed_at desc
  limit 1;

  if found and v_operation.state not in ('BOUND', 'TERMINAL_FAILED') then
    return lws_internal.website_repository_operation_result_v1(
      v_operation, 'IN_PROGRESS'
    );
  end if;
  if found and v_operation.state = 'BOUND' then
    return lws_internal.website_repository_operation_result_v1(
      v_operation, 'REPLAY'
    );
  end if;

  if v_workspace.workspace_state not in ('PENDING_REPOSITORY', 'REPOSITORY_FAILED') then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_REPOSITORY_LIFECYCLE_INVALID';
  end if;

  perform set_config('lws.website_repository_command', 'on', true);
  v_now := clock_timestamp();
  insert into public.website_repository_provisioning_operations(
    website_workspace_id,website_work_context_id,actor_id,idempotency_key,
    request_fingerprint,repository_provider,repository_owner,repository_name,
    starter_source,starter_version,starter_commit_sha,state,attempt_count,
    first_attempt_at,retry_window_expires_at
  ) values (
    p_website_workspace_id,p_website_work_context_id,v_operator.operator_id,
    p_idempotency_key,v_fingerprint,'GITHUB',v_repository_owner,
    v_repository_name,p_starter_source,p_starter_version,p_starter_commit_sha,
    'CLAIMED',1,v_now,v_now + interval '24 hours'
  ) returning * into v_operation;

  update public.website_execution_workspaces
  set workspace_state='REPOSITORY_PROVISIONING',updated_at=clock_timestamp()
  where website_workspace_id=p_website_workspace_id;

  insert into public.website_repository_provisioning_events(
    operation_id,website_workspace_id,website_work_context_id,actor_id,
    request_fingerprint,event_type,previous_state,new_state,
    repository_provider,repository_owner,repository_name,starter_source,
    starter_version,starter_commit_sha,attempt_number,result_code
  ) values (
    v_operation.operation_id,p_website_workspace_id,p_website_work_context_id,
    v_operator.operator_id,v_fingerprint,'REPOSITORY_PROVISIONING_CLAIMED',
    null,'CLAIMED','GITHUB',v_repository_owner,v_repository_name,
    p_starter_source,p_starter_version,p_starter_commit_sha,1,'CLAIMED'
  );
  update public.website_repository_provisioning_operations
  set state='CREATING',updated_at=clock_timestamp()
  where operation_id=v_operation.operation_id
  returning * into v_operation;
  insert into public.website_repository_provisioning_events(
    operation_id,website_workspace_id,website_work_context_id,actor_id,
    request_fingerprint,event_type,previous_state,new_state,
    repository_provider,repository_owner,repository_name,starter_source,
    starter_version,starter_commit_sha,attempt_number,result_code
  ) values (
    v_operation.operation_id,p_website_workspace_id,p_website_work_context_id,
    v_operator.operator_id,v_fingerprint,'REPOSITORY_CREATION_STARTED',
    'CLAIMED','CREATING','GITHUB',v_repository_owner,v_repository_name,
    p_starter_source,p_starter_version,p_starter_commit_sha,1,'CREATING'
  );
  perform set_config('lws.website_repository_command', '', true);

  return lws_internal.website_repository_operation_result_v1(
    v_operation, 'CLAIMED'
  );
exception when others then
  perform set_config('lws.website_repository_command', '', true);
  raise;
end;
$$;

revoke all on function
  public.claim_website_repository_provisioning_v1(uuid,uuid,uuid,text,text,text)
from public, anon, authenticated, service_role;

grant execute on function
  public.claim_website_repository_provisioning_v1(uuid,uuid,uuid,text,text,text)
to authenticated;
