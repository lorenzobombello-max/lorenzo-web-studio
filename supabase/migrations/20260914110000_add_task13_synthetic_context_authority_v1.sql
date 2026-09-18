create or replace function lws_internal.validate_website_concept_binding_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_project_quote_request_id uuid;
begin
  perform 1
  from public.quote_requests as request
  where request.id = new.quote_request_id
    and request.request_kind = 'website'
    and (
      request.record_classification = 'production'
      or (
        request.record_classification = 'internal_e2e'
        and current_setting(
          'lws.task13_synthetic_context_command', true
        ) = 'on'
      )
    )
  for key share;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'WEBSITE_CONCEPT_PRODUCTION_WEBSITE_REQUIRED';
  end if;

  perform 1
  from public.commercial_operators as operator
  where operator.operator_id = new.created_by
    and operator.status = 'ACTIVE'
    and operator.role = 'owner'
  for key share;

  if not found then
    raise exception using errcode = '42501', message = 'WEBSITE_CONCEPT_ACTIVE_OWNER_REQUIRED';
  end if;

  if new.promoted_project_id is not null then
    v_project_quote_request_id :=
      lws_internal.resolve_website_project_quote_request_v1(new.promoted_project_id);
    if v_project_quote_request_id is distinct from new.quote_request_id then
      raise exception using
        errcode = 'P0001',
        message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
    end if;
  end if;

  perform 1
  from public.website_work_contexts as context
  where context.concept_id = new.concept_id
    and context.quote_request_id = new.quote_request_id
    and (
      (new.concept_status = 'ACTIVE'
        and context.phase = 'PRE_PROJECT'
        and context.project_id is null)
      or
      (new.concept_status = 'PROMOTED'
        and context.phase = 'OFFICIAL_PROJECT'
        and context.project_id = new.promoted_project_id)
    )
  for key share;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;

  return null;
end;
$$;

create or replace function lws_internal.validate_website_work_context_binding_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_project_quote_request_id uuid;
begin
  perform 1
  from public.quote_requests as request
  where request.id = new.quote_request_id
    and request.request_kind = 'website'
    and (
      request.record_classification = 'production'
      or (
        request.record_classification = 'internal_e2e'
        and current_setting(
          'lws.task13_synthetic_context_command', true
        ) = 'on'
      )
    )
  for key share;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'WEBSITE_CONCEPT_PRODUCTION_WEBSITE_REQUIRED';
  end if;

  if new.concept_id is not null then
    perform 1
    from public.website_concepts as concept
    where concept.concept_id = new.concept_id
      and concept.quote_request_id = new.quote_request_id
      and (
        (new.phase = 'PRE_PROJECT' and concept.concept_status = 'ACTIVE')
        or
        (new.phase = 'OFFICIAL_PROJECT'
          and concept.concept_status = 'PROMOTED'
          and concept.promoted_project_id = new.project_id)
      )
    for key share;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
    end if;
  end if;

  if new.project_id is not null then
    v_project_quote_request_id :=
      lws_internal.resolve_website_project_quote_request_v1(new.project_id);
    if v_project_quote_request_id is distinct from new.quote_request_id then
      raise exception using
        errcode = 'P0001',
        message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
    end if;
  end if;

  return null;
end;
$$;

create function public.create_task13_synthetic_context_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_quote_request_id uuid := gen_random_uuid();
  v_concept_id uuid := gen_random_uuid();
  v_website_work_context_id uuid := gen_random_uuid();
  v_workspace_id uuid := gen_random_uuid();
begin
  v_operator := lws_internal.require_website_repository_owner_v1();

  set constraints
    trg_website_concepts_binding,
    trg_website_work_contexts_binding
  deferred;
  perform set_config('lws.task13_synthetic_context_command', 'on', true);
  perform set_config('lws.website_concept_command', 'on', true);

  insert into public.quote_requests(
    id,application_reference,record_classification,request_kind,name,email,
    website_type,budget,timing,description,privacy_consent,status
  ) values (
    v_quote_request_id,null,'internal_e2e','website',
    'Task 13 synthetic repository island','task13-synthetic@invalid.local',
    'business','Interne test','Interne test',
    'Server-authorized isolated Task 13 repository bootstrap context.',true,
    'approved'
  );

  insert into public.website_concepts(
    concept_id,quote_request_id,mode,briefing_status,commercially_released,
    concept_status,revision,created_by
  ) values (
    v_concept_id,v_quote_request_id,'PRE_PROJECT','LIMITED',false,
    'ACTIVE',1,v_operator.operator_id
  );

  insert into public.website_work_contexts(
    website_work_context_id,quote_request_id,concept_id,project_id,phase,revision
  ) values (
    v_website_work_context_id,v_quote_request_id,v_concept_id,null,
    'PRE_PROJECT',1
  );

  insert into public.website_concept_events(
    concept_id,website_work_context_id,quote_request_id,event_type,
    actor_id,actor_role,command_id,metadata
  ) values (
    v_concept_id,v_website_work_context_id,v_quote_request_id,
    'WEBSITE_CONCEPT_STARTED',v_operator.operator_id,'owner',gen_random_uuid(),
    jsonb_build_object(
      'authority_version','task13_synthetic_context_v1',
      'environment','TEST',
      'record_classification','internal_e2e'
    )
  );

  insert into public.website_execution_workspaces(
    website_workspace_id,website_work_context_id,project_id,quote_request_id,
    workspace_state,repository_provider,repository_owner,repository_name,
    default_branch,preview_branch,created_by,provisioned_by,provisioned_at
  ) values (
    v_workspace_id,v_website_work_context_id,null,v_quote_request_id,
    'PENDING_REPOSITORY','GITHUB',null,null,'main',null,
    v_operator.operator_id,v_operator.operator_id,clock_timestamp()
  );

  set constraints
    trg_website_concepts_binding,
    trg_website_work_contexts_binding
  immediate;
  perform set_config('lws.website_concept_command', '', true);
  perform set_config('lws.task13_synthetic_context_command', '', true);

  return jsonb_build_object(
    'website_work_context_id',v_website_work_context_id,
    'workspace_id',v_workspace_id,
    'record_classification','internal_e2e',
    'environment','TEST'
  );
exception when others then
  perform set_config('lws.website_concept_command', '', true);
  perform set_config('lws.task13_synthetic_context_command', '', true);
  raise;
end;
$$;

revoke all on function public.create_task13_synthetic_context_v1()
from public, anon, authenticated, service_role;

grant execute on function public.create_task13_synthetic_context_v1()
to authenticated;

comment on function public.create_task13_synthetic_context_v1() is
  'Creates one server-generated, OWNER+AAL2-only internal_e2e Task 13 website context and pending repository workspace without customer, project, SDF, or GitHub target input.';
