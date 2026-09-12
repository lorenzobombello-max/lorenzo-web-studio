create function lws_internal.project_requirement_permitted_actions_v1(
  p_requirement_id uuid,
  p_quote_request_id uuid,
  p_project_id uuid,
  p_is_management boolean
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_requirement public.project_requirements%rowtype;
  v_board public.project_requirements_boards%rowtype;
  v_other_active boolean;
  v_verification_current boolean := false;
  v_rule jsonb;
begin
  if p_requirement_id is null or p_quote_request_id is null
     or p_project_id is null or p_is_management is null then
    return '[]'::jsonb;
  end if;

  select * into v_requirement
  from public.project_requirements
  where requirement_id = p_requirement_id
    and project_id = p_project_id;
  if not found then
    return '[]'::jsonb;
  end if;

  select * into v_board
  from public.project_requirements_boards
  where requirements_board_id = v_requirement.requirements_board_id
    and project_id = p_project_id
    and quote_request_id = p_quote_request_id
    and status = 'FINALIZED';
  if not found
     or v_requirement.status not in ('PENDING', 'ACTIVE', 'BLOCKED', 'COMPLETED')
     or v_requirement.completion_mode not in ('AUTO', 'OPERATOR', 'HYBRID', 'EXTERNAL')
     or v_board.source_approval_id::text <> v_requirement.source_reference->>'authority_id'
     or v_board.source_payload_sha256 <> v_requirement.source_reference->>'source_sha256'
     or not lws_internal.validate_project_requirement_source_v1(
       p_project_id, p_quote_request_id, v_requirement.source_reference
     ) then
    return '[]'::jsonb;
  end if;

  if v_requirement.completion_mode = 'OPERATOR' then
    if v_requirement.completion_rule_key is not null
       or v_requirement.completion_rule_version is not null then
      return '[]'::jsonb;
    end if;
  else
    v_rule := lws_internal.project_requirement_rule_v1(
      v_requirement.completion_rule_key,
      v_requirement.completion_rule_version
    );
    if v_rule is null or not (v_rule->'modes' ? v_requirement.completion_mode) then
      return '[]'::jsonb;
    end if;
  end if;

  select exists (
    select 1
    from public.project_requirements
    where project_id = p_project_id
      and status = 'ACTIVE'
      and requirement_id <> p_requirement_id
  ) into v_other_active;

  if v_requirement.status in ('PENDING', 'BLOCKED') then
    if v_other_active then
      return '[]'::jsonb;
    end if;
    return '["start_project_requirement"]'::jsonb;
  end if;

  if v_requirement.status = 'ACTIVE' then
    if v_other_active then
      return '[]'::jsonb;
    end if;
    if v_requirement.completion_mode = 'OPERATOR' then
      return '["block_project_requirement","complete_project_requirement"]'::jsonb;
    end if;
    if v_requirement.completion_mode = 'HYBRID' then
      v_verification_current :=
        v_requirement.verification_result = 'PASS'
        and lws_internal.project_requirement_verification_is_current_v1(
          v_requirement.requirement_id
        );
      if v_verification_current then
        return '["block_project_requirement","complete_project_requirement"]'::jsonb;
      end if;
    end if;
    return '["block_project_requirement"]'::jsonb;
  end if;

  if not p_is_management then
    return '[]'::jsonb;
  end if;
  v_verification_current :=
    lws_internal.project_requirement_verification_is_current_v1(
      v_requirement.requirement_id
    );
  if not v_verification_current then
    return '[]'::jsonb;
  end if;
  return '["reopen_project_requirement"]'::jsonb;
exception when others then
  return '[]'::jsonb;
end;
$$;

create or replace function public.get_project_requirements_board_v1(
  p_quote_request_id uuid,
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_auth record;
  v_board public.project_requirements_boards%rowtype;
  v_customer text;
  v_dossier_reference text;
  v_assigned_operator_id uuid;
  v_assigned_operator_name text;
  v_items jsonb := '[]'::jsonb;
  v_board_json jsonb := 'null'::jsonb;
  v_empty_state text := 'NO_BOARD';
  v_required_total integer := 0;
  v_is_management boolean;
  v_can_create_item boolean := false;
  v_can_finalize boolean := false;
  v_readiness jsonb;
begin
  select * into strict v_auth
  from public.resolve_project_requirement_authorization_v1(
    p_quote_request_id, p_project_id, 'READ_BOARD', false
  );
  v_is_management := v_auth.operator_role in ('owner', 'admin', 'operations_manager');
  select acceptance.customer_legal_name, quote_request.application_reference,
    assignment.assignee_operator_id, assigned_operator.display_name
  into v_customer, v_dossier_reference, v_assigned_operator_id, v_assigned_operator_name
  from public.commercial_projects as project
  join public.quote_request_quotation_acceptances as acceptance
    on acceptance.id = project.acceptance_id and acceptance.issuance_id = project.quotation_issuance_id
  join public.quote_request_quotation_issuances as issuance on issuance.id = project.quotation_issuance_id
  join public.quote_request_quotation_approvals as approval on approval.id = issuance.approval_id
  join public.quote_requests as quote_request on quote_request.id = approval.quote_request_id
  left join lws_internal.operator_dossier_assignments as assignment
    on assignment.quote_request_id = quote_request.id
  left join public.commercial_operators as assigned_operator
    on assigned_operator.operator_id = assignment.assignee_operator_id
  where project.project_id = p_project_id and quote_request.id = p_quote_request_id;

  select * into v_board
  from public.project_requirements_boards
  where project_id = p_project_id and quote_request_id = p_quote_request_id
    and status in ('DRAFT', 'FINALIZED')
  order by created_at desc limit 1;
  if found then
    v_empty_state := null;
    v_board_json := jsonb_build_object(
      'requirements_board_id', v_board.requirements_board_id,
      'status', v_board.status, 'revision', v_board.revision,
      'finalized_at', v_board.finalized_at
    );
    select count(*) filter (where required)::integer,
      coalesce(jsonb_agg(jsonb_build_object(
        'requirement_id', requirement_id, 'item_number', item_number,
        'title', title, 'description', description, 'category', category,
        'source', jsonb_build_object(
          'authority_type', source_reference->>'authority_type',
          'label', case source_reference->>'authority_type'
            when 'ACCEPTED_PROJECT_SCOPE' then 'Geaccepteerde projectscope'
            when 'ACCEPTED_LINE_ITEM' then 'Geaccepteerde offerteregel ' ||
              (((string_to_array(source_reference->>'json_path', '.'))[2])::integer + 1)::text
          end
        ),
        'linked_page_or_module', linked_page_or_module, 'status', status,
        'completion_mode', completion_mode, 'sort_order', sort_order,
        'required', required, 'started_at', started_at, 'completed_at', completed_at,
        'verification_result', verification_result, 'blocked_reason', blocked_reason,
        'revision', revision,
        'permitted_actions', lws_internal.project_requirement_permitted_actions_v1(
          requirement_id, p_quote_request_id, p_project_id, v_is_management
        )
      ) order by sort_order, item_number), '[]'::jsonb)
    into v_required_total, v_items
    from public.project_requirements
    where requirements_board_id = v_board.requirements_board_id and project_id = p_project_id;
    if v_board.status = 'DRAFT' then
      v_can_create_item := true;
      v_can_finalize := v_is_management and v_required_total > 0;
    end if;
  end if;
  v_readiness := lws_internal.evaluate_project_requirements_readiness_v1(p_project_id);
  return jsonb_build_object(
    'contract_version', 1, 'quote_request_id', p_quote_request_id, 'project_id', p_project_id,
    'context', jsonb_build_object(
      'customer', v_customer, 'dossier_reference', v_dossier_reference,
      'project_reference', p_project_id,
      'assigned_operator', case when v_assigned_operator_id is null then 'null'::jsonb
        else jsonb_build_object('operator_id', v_assigned_operator_id, 'display_name', v_assigned_operator_name) end
    ),
    'board', v_board_json, 'items', v_items, 'empty_state', v_empty_state,
    'readiness', v_readiness,
    'actions', jsonb_build_object(
      'can_create_board', v_board.requirements_board_id is null,
      'can_create_item', v_can_create_item, 'can_finalize', v_can_finalize
    )
  );
end;
$$;

revoke all on function lws_internal.project_requirement_permitted_actions_v1(
  uuid, uuid, uuid, boolean
) from public, anon, authenticated, service_role;

comment on function lws_internal.project_requirement_permitted_actions_v1(
  uuid, uuid, uuid, boolean
) is 'Fail-closed server action projection for one authorized requirements board item.';
comment on function public.get_project_requirements_board_v1(uuid, uuid) is
  'Bounded Requirements Board projection with server-authoritative permitted actions.';
