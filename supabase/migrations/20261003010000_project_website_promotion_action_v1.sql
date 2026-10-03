alter function public.get_operator_website_work_v1(uuid)
  set schema lws_internal;
alter function lws_internal.get_operator_website_work_v1(uuid)
  rename to get_operator_website_work_v1_legacy_promotion_transition_v1;

revoke all on function
  lws_internal.get_operator_website_work_v1_legacy_promotion_transition_v1(uuid)
from public, anon, authenticated, service_role;

create function public.get_operator_website_work_v1(
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_context public.website_work_contexts%rowtype;
  v_project_count bigint := 0;
begin
  begin
    return lws_internal.get_operator_website_work_v1_legacy_promotion_transition_v1(
      p_quote_request_id
    );
  exception
    when sqlstate 'P0001' then
      if sqlerrm <> 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH' then
        raise;
      end if;

      select context.*
      into v_context
      from public.website_work_contexts as context
      join public.website_concepts as concept
        on concept.concept_id = context.concept_id
       and concept.quote_request_id = context.quote_request_id
      join public.quote_requests as request
        on request.id = context.quote_request_id
       and request.record_classification = 'production'
       and request.request_kind = 'website'
      where context.quote_request_id = p_quote_request_id
        and context.phase = 'PRE_PROJECT'
        and context.project_id is null
        and concept.concept_status = 'ACTIVE'
        and not exists (
          select 1
          from public.website_work_contexts as other_context
          where (
              other_context.quote_request_id = p_quote_request_id
              or other_context.concept_id = context.concept_id
            )
            and other_context.website_work_context_id <>
                context.website_work_context_id
        )
        and not exists (
          select 1
          from public.website_execution_workspaces as workspace
          where workspace.website_work_context_id =
              context.website_work_context_id
            and (
              workspace.quote_request_id is distinct from p_quote_request_id
              or workspace.project_id is not null
            )
        );

      if not found then
        raise;
      end if;

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
       and approval.quote_request_id = p_quote_request_id
      where lws_internal.resolve_website_project_quote_request_v1(
          project.project_id
        ) = p_quote_request_id;

      if v_project_count <> 1 then
        raise;
      end if;

      return jsonb_build_object(
        'state', 'PRE_PROJECT',
        'quote_request_id', p_quote_request_id,
        'concept_id', v_context.concept_id,
        'project_id', null,
        'website_work_context_id', v_context.website_work_context_id,
        'mode', 'PRE_PROJECT',
        'briefing_status',
          lws_internal.website_briefing_status_v1(p_quote_request_id),
        'commercially_released', false,
        'revision', v_context.revision,
        'permitted_actions', jsonb_build_array('OPEN_WEBSITE')
      );
  end;
end;
$$;

revoke all on function public.get_operator_website_work_v1(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.get_operator_website_work_v1(uuid)
to authenticated;

create function public.get_website_execution_workspace_v6(
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_v5 jsonb;
  v_owner_eligible boolean := false;
  v_aal2_eligible boolean := false;
  v_context_eligible boolean := false;
  v_project_count bigint := 0;
  v_permitted_actions jsonb := '[]'::jsonb;
begin
  v_v5 := public.get_website_execution_workspace_v5(p_quote_request_id);

  select exists (
    select 1
    from public.commercial_operators as operator
    where operator.auth_user_id = auth.uid()
      and operator.status = 'ACTIVE'
      and operator.role = 'owner'
      and operator.revoked_at is null
  ) into v_owner_eligible;

  if v_owner_eligible then
    begin
      perform lws_internal.assert_operator_aal2_v1();
      v_aal2_eligible := true;
    exception
      when sqlstate '42501' then
        v_aal2_eligible := false;
    end;
  end if;

  if v_owner_eligible and v_aal2_eligible
     and v_v5->>'mode' = 'PRE_PROJECT' then
    select exists (
      select 1
      from public.website_work_contexts as context
      join public.website_concepts as concept
        on concept.concept_id = context.concept_id
       and concept.quote_request_id = context.quote_request_id
      where context.website_work_context_id =
          (v_v5->>'website_work_context_id')::uuid
        and context.quote_request_id = p_quote_request_id
        and context.phase = 'PRE_PROJECT'
        and context.project_id is null
        and context.revision = (v_v5->>'context_revision')::bigint
        and concept.concept_status = 'ACTIVE'
        and not exists (
          select 1
          from public.website_execution_workspaces as workspace
          where workspace.website_work_context_id = context.website_work_context_id
            and (
              workspace.quote_request_id is distinct from p_quote_request_id
              or workspace.project_id is not null
            )
        )
    ) into v_context_eligible;

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
     and approval.quote_request_id = p_quote_request_id
    join public.quote_requests as request
      on request.id = approval.quote_request_id
     and request.record_classification = 'production'
     and request.request_kind = 'website';

    if v_context_eligible and v_project_count = 1 then
      v_permitted_actions := jsonb_build_array('promote_website_concept');
    end if;
  end if;

  return (v_v5 - 'contract_version') || jsonb_build_object(
    'contract_version', 6,
    'permitted_actions', v_permitted_actions
  );
end;
$$;

revoke all on function public.get_website_execution_workspace_v6(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.get_website_execution_workspace_v6(uuid)
to authenticated;

comment on function public.get_website_execution_workspace_v6(uuid) is
  'Website execution projection with the real promote_website_concept action only for active OWNER+AAL2 and one eligible accepted production project lineage.';

comment on function public.get_operator_website_work_v1(uuid) is
  'Website work projection extended only for the explicit PRE_PROJECT promotion transition with one eligible accepted production project.';
