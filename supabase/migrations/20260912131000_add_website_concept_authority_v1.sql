create function lws_internal.website_briefing_status_v1(
  p_quote_request_id uuid
)
returns text
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select case when exists (
    select 1
    from public.quote_request_intakes as intake
    where intake.quote_request_id = p_quote_request_id
      and intake.status in ('submitted', 'reviewed')
      and intake.submitted_at is not null
  ) then 'COMPLETE' else 'LIMITED' end;
$$;

create function public.get_operator_website_work_v1(
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_aal text := coalesce(auth.jwt() ->> 'aal', '');
  v_operator public.commercial_operators%rowtype;
  v_request public.quote_requests%rowtype;
  v_dossier_state text;
  v_concept public.website_concepts%rowtype;
  v_context public.website_work_contexts%rowtype;
  v_context_count bigint;
  v_project public.commercial_projects%rowtype;
  v_project_count bigint;
  v_project_quote_request_id uuid;
  v_briefing_status text;
  v_commercially_released boolean := false;
  v_permitted_actions jsonb := '[]'::jsonb;
begin
  if p_quote_request_id is null then
    raise exception using errcode = '22023', message = 'QUOTE_REQUEST_ID_REQUIRED';
  end if;
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select *
  into v_operator
  from public.commercial_operators as operator
  where operator.auth_user_id = v_subject;

  if not found then
    raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR';
  end if;
  if v_operator.status = 'DISABLED' then
    raise exception using errcode = '42501', message = 'OPERATOR_DISABLED';
  end if;
  if v_operator.status = 'REVOKED' then
    raise exception using errcode = '42501', message = 'OPERATOR_REVOKED';
  end if;
  if v_operator.status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;
  if v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'APPLICATION_SCOPE_DENIED';
  end if;

  select *
  into v_request
  from public.quote_requests as request
  where request.id = p_quote_request_id;

  select state.state
  into v_dossier_state
  from lws_internal.operator_dossier_states as state
  where state.quote_request_id = p_quote_request_id;

  select *
  into v_concept
  from public.website_concepts as concept
  where concept.quote_request_id = p_quote_request_id;

  select count(*)
  into v_context_count
  from public.website_work_contexts as context
  where context.quote_request_id = p_quote_request_id
     or (v_concept.concept_id is not null
       and context.concept_id = v_concept.concept_id);

  if v_context_count > 1 then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;

  select *
  into v_context
  from public.website_work_contexts as context
  where context.quote_request_id = p_quote_request_id
     or (v_concept.concept_id is not null
       and context.concept_id = v_concept.concept_id)
  order by (context.quote_request_id = p_quote_request_id) desc
  limit 1;

  select count(*)
  into v_project_count
  from public.commercial_projects as project
  join public.quote_request_quotation_acceptances as acceptance
    on acceptance.id = project.acceptance_id
   and acceptance.issuance_id = project.quotation_issuance_id
  join public.quote_request_quotation_issuances as issuance
    on issuance.id = project.quotation_issuance_id
   and issuance.status = 'ISSUED'
  join public.quote_request_quotation_approvals as approval
    on approval.id = issuance.approval_id
  where approval.quote_request_id = p_quote_request_id;

  if v_project_count > 1 then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;

  select project.*
  into v_project
  from public.commercial_projects as project
  join public.quote_request_quotation_acceptances as acceptance
    on acceptance.id = project.acceptance_id
   and acceptance.issuance_id = project.quotation_issuance_id
  join public.quote_request_quotation_issuances as issuance
    on issuance.id = project.quotation_issuance_id
   and issuance.status = 'ISSUED'
  join public.quote_request_quotation_approvals as approval
    on approval.id = issuance.approval_id
  where approval.quote_request_id = p_quote_request_id
  order by project.created_at, project.project_id
  limit 1;

  if v_project.project_id is not null then
    v_project_quote_request_id :=
      lws_internal.resolve_website_project_quote_request_v1(v_project.project_id);
    if v_project_quote_request_id is distinct from p_quote_request_id then
      raise exception using
        errcode = 'P0001',
        message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
    end if;
  end if;

  if v_concept.concept_id is not null then
    if v_context.website_work_context_id is null
       or v_context.quote_request_id is distinct from p_quote_request_id
       or v_context.concept_id is distinct from v_concept.concept_id then
      raise exception using
        errcode = 'P0001',
        message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
    end if;

    if v_concept.concept_status = 'ACTIVE' then
      if v_context.phase <> 'PRE_PROJECT'
         or v_context.project_id is not null
         or v_project.project_id is not null then
        raise exception using
          errcode = 'P0001',
          message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
      end if;

      v_briefing_status :=
        lws_internal.website_briefing_status_v1(p_quote_request_id);

      return jsonb_build_object(
        'state', 'PRE_PROJECT',
        'quote_request_id', p_quote_request_id,
        'concept_id', v_concept.concept_id,
        'project_id', null,
        'website_work_context_id', v_context.website_work_context_id,
        'mode', 'PRE_PROJECT',
        'briefing_status', v_briefing_status,
        'commercially_released', false,
        'revision', v_context.revision,
        'permitted_actions', jsonb_build_array('OPEN_WEBSITE')
      );
    end if;

    if v_concept.concept_status <> 'PROMOTED'
       or v_project.project_id is null
       or v_concept.promoted_project_id is distinct from v_project.project_id
       or v_context.phase <> 'OFFICIAL_PROJECT'
       or v_context.project_id is distinct from v_project.project_id then
      raise exception using
        errcode = 'P0001',
        message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
    end if;
  elsif v_context.website_work_context_id is not null
        and (
          v_project.project_id is null
          or v_context.quote_request_id is distinct from p_quote_request_id
          or v_context.phase <> 'OFFICIAL_PROJECT'
          or v_context.project_id is distinct from v_project.project_id
          or v_context.concept_id is not null
        ) then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;

  if v_project.project_id is not null then
    v_briefing_status :=
      lws_internal.website_briefing_status_v1(p_quote_request_id);
    v_commercially_released := v_project.current_state = any(array[
      'PROJECT_RELEASED',
      'PREVIEW_READY',
      'M2_PAYMENT_RECEIVED',
      'FINAL_APPROVAL_RECORDED',
      'FULL_PAYMENT_RECEIVED',
      'FINAL_TRANSFER_AUTHORIZED',
      'DELIVERED',
      'ARCHIVED'
    ]);

    if v_request.record_classification = 'production'
       and v_request.request_kind = 'website'
       and v_dossier_state = 'ACTIVE'
       and exists (
         select 1
         from public.audit_events as event
         where event.project_id = v_project.project_id
           and event.event_type = 'PROJECT_WORK_STARTED'
       ) then
      v_permitted_actions := jsonb_build_array('OPEN_WEBSITE');
    end if;

    return jsonb_build_object(
      'state', 'OFFICIAL_PROJECT',
      'quote_request_id', p_quote_request_id,
      'concept_id', v_concept.concept_id,
      'project_id', v_project.project_id,
      'website_work_context_id', v_context.website_work_context_id,
      'mode', 'OFFICIAL_PROJECT',
      'briefing_status', v_briefing_status,
      'commercially_released', v_commercially_released,
      'revision', coalesce(v_context.revision, v_project.revision),
      'permitted_actions', v_permitted_actions
    );
  end if;

  if v_context.website_work_context_id is not null then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;

  if v_operator.role = 'owner'
     and v_aal = 'aal2'
     and v_request.id is not null
     and v_request.record_classification = 'production'
     and v_request.request_kind = 'website'
     and v_dossier_state = 'ACTIVE' then
    v_permitted_actions := jsonb_build_array('CAN_START_WEBSITE_CONCEPT');
  end if;

  return jsonb_build_object(
    'state', 'NONE',
    'quote_request_id', p_quote_request_id,
    'concept_id', null,
    'project_id', null,
    'website_work_context_id', null,
    'mode', null,
    'briefing_status', null,
    'commercially_released', false,
    'revision', 1,
    'permitted_actions', v_permitted_actions
  );
end;
$$;

alter function public.get_operator_application_v1(uuid, text)
  rename to get_operator_application_v1_pre_website_work;

create function public.get_operator_application_v1(
  p_quote_request_id uuid default null,
  p_application_reference text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_result jsonb;
  v_quote_request_id uuid;
begin
  v_result := public.get_operator_application_v1_pre_website_work(
    p_quote_request_id,
    p_application_reference
  );
  v_quote_request_id := nullif(v_result->>'quote_request_id', '')::uuid;

  if v_result->>'request_kind' <> 'website' then
    return v_result;
  end if;

  return v_result || jsonb_build_object(
    'website_work', public.get_operator_website_work_v1(v_quote_request_id)
  );
end;
$$;

revoke all on function
  lws_internal.website_briefing_status_v1(uuid),
  public.get_operator_website_work_v1(uuid),
  public.get_operator_application_v1_pre_website_work(uuid, text),
  public.get_operator_application_v1(uuid, text)
from public, anon, authenticated, service_role;

grant execute on function public.get_operator_website_work_v1(uuid)
to authenticated;
grant execute on function public.get_operator_application_v1(uuid, text)
to authenticated;

comment on function lws_internal.website_briefing_status_v1(uuid) is
  'Server-derived Website briefing completeness from submitted or reviewed intake evidence.';
comment on function public.get_operator_website_work_v1(uuid) is
  'Closed server-authoritative Website work projection for readable Operator dossiers.';
comment on function public.get_operator_application_v1(uuid, text) is
  'Existing Operator application detail with the closed server-authoritative website_work projection appended.';