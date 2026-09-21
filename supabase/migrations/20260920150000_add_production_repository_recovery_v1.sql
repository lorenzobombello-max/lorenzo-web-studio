create function public.get_production_website_repository_recovery_authority_v1(
  p_quote_request_id uuid,
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
  if p_quote_request_id is null
     or p_website_work_context_id is null
     or p_website_workspace_id is null then
    raise exception using
      errcode = '22023', message = 'PRODUCTION_REPOSITORY_RECOVERY_IDENTITY_REQUIRED';
  end if;

  v_operator := lws_internal.require_website_repository_owner_v1();

  select context.* into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id = p_website_work_context_id
    and context.quote_request_id = p_quote_request_id;

  select workspace.* into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_workspace_id = p_website_workspace_id
    and workspace.website_work_context_id = p_website_work_context_id
    and workspace.quote_request_id = p_quote_request_id;

  select request.* into v_request
  from public.quote_requests as request
  where request.id = p_quote_request_id;

  select concept.* into v_concept
  from public.website_concepts as concept
  where concept.concept_id = v_context.concept_id
    and concept.quote_request_id = p_quote_request_id;

  if v_context.website_work_context_id is null
     or v_workspace.website_workspace_id is null
     or v_request.id is null
     or v_concept.concept_id is null
     or v_context.phase <> 'PRE_PROJECT'
     or v_context.project_id is not null
     or v_workspace.project_id is not null
     or v_request.record_classification <> 'production'
     or v_request.request_kind <> 'website'
     or v_concept.mode <> 'PRE_PROJECT'
     or v_concept.commercially_released <> false
     or v_concept.promoted_project_id is not null
     or v_workspace.workspace_state <> 'REPOSITORY_FAILED'
     or v_workspace.repository_external_id is not null
     or v_workspace.repository_node_id is not null
     or v_workspace.repository_state is not null
     or v_workspace.repository_bound_at is not null then
    raise exception using
      errcode = '42501', message = 'PRODUCTION_REPOSITORY_RECOVERY_AUTHORITY_MISMATCH';
  end if;

  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.website_work_context_id = p_website_work_context_id
    and operation.website_workspace_id = p_website_workspace_id
  order by operation.updated_at desc, operation.operation_id desc
  limit 1;

  if not found
     or v_operation.actor_id is distinct from v_operator.operator_id
     or v_operation.state <> 'TERMINAL_FAILED'
     or v_operation.failure_code <> 'REPOSITORY_PROVIDER_FAILED'
     or v_operation.external_created_at is null
     or v_operation.repository_provider <> 'GITHUB'
     or v_operation.repository_external_id is null
     or v_operation.repository_node_id is null
     or v_operation.repository_owner is null
     or v_operation.repository_name is null
     or v_operation.bound_at is not null
     or v_operation.quarantined_at is not null
     or v_operation.quarantine_evidence_sha256 is not null then
    raise exception using
      errcode = '42501', message = 'PRODUCTION_REPOSITORY_RECOVERY_AUTHORITY_MISMATCH';
  end if;

  return jsonb_build_object(
    'operation_id', v_operation.operation_id,
    'website_work_context_id', v_operation.website_work_context_id,
    'website_workspace_id', v_operation.website_workspace_id,
    'repository_external_id', v_operation.repository_external_id::text,
    'repository_node_id', v_operation.repository_node_id,
    'repository_owner', v_operation.repository_owner,
    'repository_name', v_operation.repository_name,
    'starter_source', v_operation.starter_source,
    'starter_version', v_operation.starter_version,
    'starter_commit_sha', v_operation.starter_commit_sha
  );
end;
$$;

create function public.finalize_production_website_repository_recovery_v1(
  p_quote_request_id uuid,
  p_operation_id uuid,
  p_verification jsonb,
  p_actor_auth_user_id uuid,
  p_actor_aal text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_context public.website_work_contexts%rowtype;
  v_request public.quote_requests%rowtype;
  v_concept public.website_concepts%rowtype;
  v_external_id bigint;
  v_marker_sha text;
  v_previous_state text;
begin
  if p_quote_request_id is null
     or p_operation_id is null
     or p_actor_auth_user_id is null
     or jsonb_typeof(p_verification) <> 'object'
     or not p_verification ?& array[
       'operation_id','website_workspace_id','website_work_context_id',
       'repository_external_id','repository_node_id','repository_owner',
       'repository_name','repository_visibility','default_branch',
       'starter_source','starter_version','starter_commit_sha',
       'repository_marker_commit_sha'
     ]
     or exists (
       select 1 from jsonb_object_keys(p_verification) as supplied(key)
       where supplied.key <> all(array[
         'operation_id','website_workspace_id','website_work_context_id',
         'repository_external_id','repository_node_id','repository_owner',
         'repository_name','repository_visibility','default_branch',
         'starter_source','starter_version','starter_commit_sha',
         'repository_marker_commit_sha'
       ])
     )
     or exists (
       select 1 from jsonb_each(p_verification) as supplied(key,value)
       where jsonb_typeof(supplied.value) <> 'string'
     )
     or p_verification->>'repository_external_id' !~ '^[1-9][0-9]{0,15}$'
     or p_verification->>'repository_node_id' !~ '^[A-Za-z0-9_-]{6,255}$'
     or p_verification->>'repository_visibility' <> 'private'
     or p_verification->>'default_branch' <> 'main'
     or p_verification->>'repository_marker_commit_sha' !~
       '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' then
    raise exception using
      errcode = '22023', message = 'INVALID_PRODUCTION_REPOSITORY_RECOVERY_BINDING';
  end if;

  if coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
  end if;
  if p_actor_aal is distinct from 'aal2' then
    raise exception using errcode = '42501', message = 'AAL2_REQUIRED';
  end if;

  select operator.* into v_operator
  from public.commercial_operators as operator
  where operator.auth_user_id = p_actor_auth_user_id
    and operator.status = 'ACTIVE'
    and operator.role = 'owner'
    and operator.revoked_at is null;
  if not found then
    raise exception using errcode = '42501', message = 'WEBSITE_REPOSITORY_OWNER_REQUIRED';
  end if;

  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.operation_id = p_operation_id
  for update;
  if not found or v_operation.actor_id is distinct from v_operator.operator_id then
    raise exception using
      errcode = '42501', message = 'PRODUCTION_REPOSITORY_RECOVERY_OPERATION_DENIED';
  end if;

  select workspace.* into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_workspace_id = v_operation.website_workspace_id
    and workspace.quote_request_id = p_quote_request_id
  for update;
  select context.* into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id = v_operation.website_work_context_id;
  select request.* into v_request
  from public.quote_requests as request
  where request.id = p_quote_request_id;
  select concept.* into v_concept
  from public.website_concepts as concept
  where concept.concept_id = v_context.concept_id
    and concept.quote_request_id = p_quote_request_id;

  if v_workspace.website_workspace_id is null
     or v_context.website_work_context_id is null
     or v_request.id is null
     or v_concept.concept_id is null
     or v_workspace.website_work_context_id is distinct from v_context.website_work_context_id
     or v_workspace.quote_request_id is distinct from v_context.quote_request_id
     or v_context.phase <> 'PRE_PROJECT'
     or v_context.project_id is not null
     or v_workspace.project_id is not null
     or v_request.record_classification <> 'production'
     or v_request.request_kind <> 'website'
     or v_concept.mode <> 'PRE_PROJECT'
     or v_concept.commercially_released <> false
     or v_concept.promoted_project_id is not null then
    raise exception using
      errcode = '42501', message = 'PRODUCTION_REPOSITORY_RECOVERY_AUTHORITY_MISMATCH';
  end if;

  v_external_id := (p_verification->>'repository_external_id')::bigint;
  v_marker_sha := p_verification->>'repository_marker_commit_sha';
  if p_verification->>'operation_id' is distinct from v_operation.operation_id::text
     or p_verification->>'website_workspace_id' is distinct from v_operation.website_workspace_id::text
     or p_verification->>'website_work_context_id' is distinct from v_operation.website_work_context_id::text
     or v_external_id is distinct from v_operation.repository_external_id
     or p_verification->>'repository_node_id' is distinct from v_operation.repository_node_id
     or p_verification->>'repository_owner' is distinct from v_operation.repository_owner
     or p_verification->>'repository_name' is distinct from v_operation.repository_name
     or p_verification->>'starter_source' is distinct from v_operation.starter_source
     or p_verification->>'starter_version' is distinct from v_operation.starter_version
     or p_verification->>'starter_commit_sha' is distinct from v_operation.starter_commit_sha then
    raise exception using
      errcode = 'P0001', message = 'PRODUCTION_REPOSITORY_RECOVERY_BINDING_MISMATCH';
  end if;

  if v_operation.state = 'BOUND' then
    if v_workspace.workspace_state <> 'REPOSITORY_READY'
       or v_workspace.repository_state <> 'BOUND'
       or v_workspace.repository_external_id is distinct from v_external_id
       or v_workspace.repository_node_id is distinct from p_verification->>'repository_node_id'
       or v_workspace.repository_marker_commit_sha is distinct from v_marker_sha
       or v_workspace.last_commit_sha is distinct from v_marker_sha then
      raise exception using
        errcode = 'P0001', message = 'PRODUCTION_REPOSITORY_RECOVERY_BINDING_MISMATCH';
    end if;
    return lws_internal.website_repository_operation_result_v1(v_operation, 'REPLAY');
  end if;

  if v_operation.state <> 'TERMINAL_FAILED'
     or v_operation.failure_code <> 'REPOSITORY_PROVIDER_FAILED'
     or v_operation.external_created_at is null
     or v_operation.repository_external_id is null
     or v_operation.repository_node_id is null
     or v_operation.bound_at is not null
     or v_operation.quarantined_at is not null
     or v_operation.quarantine_evidence_sha256 is not null
     or v_workspace.workspace_state <> 'REPOSITORY_FAILED'
     or v_workspace.repository_external_id is not null
     or v_workspace.repository_node_id is not null
     or v_workspace.repository_state is not null
     or v_workspace.repository_bound_at is not null then
    raise exception using
      errcode = 'P0001', message = 'PRODUCTION_REPOSITORY_RECOVERY_TRANSITION_INVALID';
  end if;

  perform set_config('lws.website_repository_command', 'on', true);
  v_previous_state := v_operation.state;
  update public.website_execution_workspaces
  set workspace_state = 'REPOSITORY_READY',
      repository_owner = v_operation.repository_owner,
      repository_name = v_operation.repository_name,
      repository_external_id = v_operation.repository_external_id,
      repository_node_id = v_operation.repository_node_id,
      repository_visibility = 'private',
      repository_state = 'BOUND',
      default_branch = 'main',
      starter_source = v_operation.starter_source,
      starter_version = v_operation.starter_version,
      starter_commit_sha = v_operation.starter_commit_sha,
      repository_marker_commit_sha = v_marker_sha,
      repository_bound_at = clock_timestamp(),
      last_commit_sha = v_marker_sha,
      last_commit_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where website_workspace_id = v_operation.website_workspace_id;

  update public.website_repository_provisioning_operations
  set state = 'BOUND', failure_code = null, retry_at = null,
      retry_action = null, provider_retry_after_at = null,
      bound_at = clock_timestamp(), updated_at = clock_timestamp()
  where operation_id = p_operation_id
  returning * into v_operation;

  insert into public.website_repository_provisioning_events(
    operation_id, website_workspace_id, website_work_context_id, actor_id,
    request_fingerprint, event_type, previous_state, new_state,
    repository_provider, repository_owner, repository_name,
    repository_external_id, starter_source, starter_version,
    starter_commit_sha, attempt_number, result_code
  ) values (
    v_operation.operation_id, v_operation.website_workspace_id,
    v_operation.website_work_context_id, v_operator.operator_id,
    v_operation.request_fingerprint, 'REPOSITORY_BOUND', v_previous_state,
    'BOUND', v_operation.repository_provider, v_operation.repository_owner,
    v_operation.repository_name, v_operation.repository_external_id,
    v_operation.starter_source, v_operation.starter_version,
    v_operation.starter_commit_sha, v_operation.attempt_count, 'BOUND'
  );
  perform set_config('lws.website_repository_command', '', true);
  return lws_internal.website_repository_operation_result_v1(v_operation, 'BOUND');
exception when others then
  perform set_config('lws.website_repository_command', '', true);
  raise;
end;
$$;

create function public.get_website_execution_workspace_v5(
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_v4 jsonb;
  v_workspace public.website_execution_workspaces%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_retry_allowed boolean := false;
  v_recovery_required boolean := false;
begin
  v_v4 := public.get_website_execution_workspace_v4(p_quote_request_id);

  select workspace.* into v_workspace
  from public.website_execution_workspaces as workspace
  join public.quote_requests as request on request.id = workspace.quote_request_id
  where workspace.quote_request_id = p_quote_request_id
    and request.record_classification = 'production'
    and request.request_kind = 'website';

  if found then
    select operation.* into v_operation
    from public.website_repository_provisioning_operations as operation
    where operation.website_workspace_id = v_workspace.website_workspace_id
      and operation.website_work_context_id = v_workspace.website_work_context_id
    order by operation.updated_at desc, operation.operation_id desc
    limit 1;

    if found and v_operation.state = 'TERMINAL_FAILED' then
      v_recovery_required := v_operation.repository_external_id is not null
        or v_operation.repository_node_id is not null
        or v_operation.external_created_at is not null;
      v_retry_allowed := not v_recovery_required;
    end if;
  end if;

  return jsonb_set(
    jsonb_set(
      jsonb_set(v_v4, '{contract_version}', '5'::jsonb),
      '{workspace,capabilities}',
      coalesce(v_v4 #> '{workspace,capabilities}', '{}'::jsonb) ||
        jsonb_build_object(
          'repository_retry_allowed', v_retry_allowed,
          'repository_recovery_required', v_recovery_required
        ),
      false
    ),
    '{workspace,repository_recovery_operation_id}',
    case when v_recovery_required
      then to_jsonb(v_operation.operation_id::text)
      else 'null'::jsonb
    end,
    true
  );
end;
$$;

-- GIT-001 migration-sequence transient-risk closure: EXECUTE on these two
-- functions is deliberately NOT granted here. Supabase applies pending
-- migration files sequentially with no cross-file transaction wrapping the
-- pending set, so granting EXECUTE in this same file would make the
-- pre-lineage-hardening recovery/finalize authority reachable by ordinary
-- authenticated/service_role callers the instant this migration completes,
-- for however long it takes 20260920231950 (lineage hardening) to also
-- complete. 20260920231950 already ends with the authoritative
-- `revoke all` / `grant execute` block for the complete hardened surface
-- (including these two functions), so EXECUTE is granted for the first
-- time only once the canonical durable-identity resolver is installed.
-- Until then these functions exist but are unreachable by any externally
-- facing role, matching the technical quiescence barrier established by
-- 20260920135900.
revoke all on function public.get_production_website_repository_recovery_authority_v1(
  uuid, uuid, uuid
) from public, anon, authenticated, service_role;

revoke all on function public.finalize_production_website_repository_recovery_v1(
  uuid, uuid, jsonb, uuid, text
) from public, anon, authenticated, service_role;

revoke all on function public.get_website_execution_workspace_v5(uuid)
from public, anon;
grant execute on function public.get_website_execution_workspace_v5(uuid)
to authenticated;

comment on function public.get_production_website_repository_recovery_authority_v1(
  uuid, uuid, uuid
) is 'Read-only OWNER+AAL2 production PRE_PROJECT authority for recovering the latest failed operation with durable external repository identity; accepts no idempotency key.';

comment on function public.finalize_production_website_repository_recovery_v1(
  uuid, uuid, jsonb, uuid, text
) is 'Service-only atomic production existing-repository recovery binding using server-verified repository proof; creates no repository and performs no commercial lifecycle mutation.';

comment on function public.get_website_execution_workspace_v5(uuid) is
  'Workspace projection with mutually exclusive server-authoritative repository retry and existing-repository recovery capabilities.';