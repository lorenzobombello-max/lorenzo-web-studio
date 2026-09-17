create or replace function lws_internal.website_repository_transition_allowed_v1(
  p_old_state text,p_new_state text
)
returns boolean
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select p_old_state=p_new_state or (p_old_state,p_new_state) in (
    ('CLAIMED','CREATING'),
    ('CREATING','EXTERNAL_CREATED'),('CREATING','RETRYABLE_FAILED'),
    ('CREATING','RETRY_SCHEDULED'),('CREATING','BLOCKED'),
    ('CREATING','QUARANTINED'),('CREATING','TERMINAL_FAILED'),
    ('EXTERNAL_CREATED','VERIFYING'),
    ('VERIFYING','BOUND'),('VERIFYING','RETRYABLE_FAILED'),
    ('VERIFYING','RETRY_SCHEDULED'),('VERIFYING','BLOCKED'),
    ('VERIFYING','QUARANTINED'),('VERIFYING','TERMINAL_FAILED'),
    ('RETRYABLE_FAILED','RETRY_SCHEDULED'),('RETRYABLE_FAILED','CREATING'),
    ('RETRYABLE_FAILED','VERIFYING'),
    ('RETRY_SCHEDULED','CREATING'),('RETRY_SCHEDULED','VERIFYING'),
    ('BLOCKED','CREATING'),('BLOCKED','VERIFYING'),
    ('QUARANTINED','VERIFYING'),('QUARANTINED','TERMINAL_FAILED'),
    ('TERMINAL_FAILED','BOUND')
  )
$$;

create function public.finalize_recovered_website_repository_v1(
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
  if p_operation_id is null
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
     or nullif(btrim(p_verification->>'repository_node_id'),'') is null
     or char_length(p_verification->>'repository_node_id') > 255
     or p_verification->>'repository_visibility' <> 'private'
     or p_verification->>'default_branch' <> 'main' then
    raise exception using errcode='22023',message='INVALID_RECOVERED_WEBSITE_REPOSITORY_BINDING';
  end if;
  v_external_id := (p_verification->>'repository_external_id')::bigint;
  v_marker_sha := p_verification->>'repository_marker_commit_sha';
  if v_external_id > 9007199254740991
     or v_marker_sha !~ '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' then
    raise exception using errcode='22023',message='INVALID_RECOVERED_WEBSITE_REPOSITORY_BINDING';
  end if;

  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception using errcode='42501',message='TASK13_FINALIZATION_SERVICE_REQUIRED';
  end if;
  if p_actor_aal is distinct from 'aal2' then
    raise exception using errcode='42501',message='AAL2_REQUIRED';
  end if;
  select operator.* into v_operator
  from public.commercial_operators as operator
  where operator.auth_user_id=p_actor_auth_user_id
    and operator.status='ACTIVE'
    and operator.role='owner';
  if not found then
    raise exception using errcode='42501',message='WEBSITE_REPOSITORY_OWNER_REQUIRED';
  end if;
  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.operation_id=p_operation_id
  for update;
  if not found then
    raise exception using errcode='23503',message='WEBSITE_REPOSITORY_OPERATION_NOT_FOUND';
  end if;
  if v_operation.actor_id is distinct from v_operator.operator_id then
    raise exception using errcode='42501',message='WEBSITE_REPOSITORY_OPERATION_DENIED';
  end if;

  select workspace.* into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_workspace_id=v_operation.website_workspace_id
  for update;
  select context.* into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id=v_operation.website_work_context_id;
  select request.* into v_request
  from public.quote_requests as request
  where request.id=v_context.quote_request_id;
  select concept.* into v_concept
  from public.website_concepts as concept
  where concept.concept_id=v_context.concept_id
    and concept.quote_request_id=v_context.quote_request_id;

  if v_workspace.website_workspace_id is null
     or v_context.website_work_context_id is null
     or v_request.id is null
     or v_concept.concept_id is null
     or v_workspace.website_work_context_id is distinct from v_context.website_work_context_id
     or v_workspace.quote_request_id is distinct from v_context.quote_request_id
     or v_context.phase <> 'PRE_PROJECT'
     or v_context.project_id is not null
     or v_workspace.project_id is not null
     or v_request.record_classification <> 'internal_e2e'
     or v_request.request_kind <> 'website'
     or v_request.application_reference is not null
     or v_concept.mode <> 'PRE_PROJECT'
     or v_concept.commercially_released <> false
     or v_concept.promoted_project_id is not null then
    raise exception using errcode='42501',message='TASK13_FINALIZATION_AUTHORITY_MISMATCH';
  end if;

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
    raise exception using errcode='P0001',message='RECOVERED_WEBSITE_REPOSITORY_BINDING_MISMATCH';
  end if;

  if v_operation.state='BOUND' then
    if v_workspace.workspace_state <> 'REPOSITORY_READY'
       or v_workspace.repository_state <> 'BOUND'
       or v_workspace.repository_external_id is distinct from v_external_id
       or v_workspace.repository_node_id is distinct from p_verification->>'repository_node_id'
       or v_workspace.repository_owner is distinct from p_verification->>'repository_owner'
       or v_workspace.repository_name is distinct from p_verification->>'repository_name'
       or v_workspace.repository_visibility is distinct from 'private'
       or v_workspace.default_branch is distinct from 'main'
       or v_workspace.starter_source is distinct from p_verification->>'starter_source'
       or v_workspace.starter_version is distinct from p_verification->>'starter_version'
       or v_workspace.starter_commit_sha is distinct from p_verification->>'starter_commit_sha'
       or v_workspace.repository_marker_commit_sha is distinct from v_marker_sha
       or v_workspace.repository_bound_at is null then
      raise exception using errcode='P0001',message='RECOVERED_WEBSITE_REPOSITORY_BINDING_MISMATCH';
    end if;
    return lws_internal.website_repository_operation_result_v1(v_operation,'REPLAY');
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
    raise exception using errcode='P0001',message='TASK13_FINALIZATION_TRANSITION_INVALID';
  end if;

  perform set_config('lws.website_repository_command','on',true);
  v_previous_state := v_operation.state;
  update public.website_execution_workspaces
  set workspace_state='REPOSITORY_READY',
      repository_owner=v_operation.repository_owner,
      repository_name=v_operation.repository_name,
      repository_external_id=v_operation.repository_external_id,
      repository_node_id=v_operation.repository_node_id,
      repository_visibility='private',repository_state='BOUND',
      default_branch='main',starter_source=v_operation.starter_source,
      starter_version=v_operation.starter_version,
      starter_commit_sha=v_operation.starter_commit_sha,
      repository_marker_commit_sha=v_marker_sha,
      repository_bound_at=clock_timestamp(),updated_at=clock_timestamp()
  where website_workspace_id=v_operation.website_workspace_id;

  update public.website_repository_provisioning_operations
  set state='BOUND',failure_code=null,retry_at=null,retry_action=null,
      provider_retry_after_at=null,bound_at=clock_timestamp(),
      updated_at=clock_timestamp()
  where operation_id=p_operation_id
  returning * into v_operation;

  insert into public.website_repository_provisioning_events(
    operation_id,website_workspace_id,website_work_context_id,actor_id,
    request_fingerprint,event_type,previous_state,new_state,
    repository_provider,repository_owner,repository_name,
    repository_external_id,starter_source,starter_version,starter_commit_sha,
    attempt_number,result_code
  ) values (
    v_operation.operation_id,v_operation.website_workspace_id,
    v_operation.website_work_context_id,v_operator.operator_id,
    v_operation.request_fingerprint,'REPOSITORY_BOUND',v_previous_state,'BOUND',
    v_operation.repository_provider,v_operation.repository_owner,
    v_operation.repository_name,v_operation.repository_external_id,
    v_operation.starter_source,v_operation.starter_version,
    v_operation.starter_commit_sha,v_operation.attempt_count,'BOUND'
  );
  perform set_config('lws.website_repository_command','',true);
  return lws_internal.website_repository_operation_result_v1(v_operation,'BOUND');
exception when others then
  perform set_config('lws.website_repository_command','',true);
  raise;
end;
$$;

revoke all on function public.finalize_recovered_website_repository_v1(uuid,jsonb,uuid,text)
from public,anon,authenticated,service_role;
grant execute on function public.finalize_recovered_website_repository_v1(uuid,jsonb,uuid,text)
to service_role;

comment on function public.finalize_recovered_website_repository_v1(uuid,jsonb,uuid,text) is
  'Service-only atomic binding for a server-verified human OWNER+AAL2 Task 13 post-create recovery; exact BOUND replay only.';