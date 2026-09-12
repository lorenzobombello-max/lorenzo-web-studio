create function public.get_project_requirements_board_v1(
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
  v_required_completed integer := 0;
  v_required_open integer := 0;
  v_required_blocked integer := 0;
  v_active_requirement_id uuid;
  v_active_item_number integer;
  v_readiness_reason text := 'REQUIREMENTS_BOARD_MISSING';
  v_is_management boolean;
  v_can_create_item boolean := false;
  v_can_finalize boolean := false;
begin
  select * into strict v_auth
  from public.resolve_project_requirement_authorization_v1(
    p_quote_request_id, p_project_id, 'READ_BOARD', false
  );
  v_is_management := v_auth.operator_role in ('owner', 'admin', 'operations_manager');

  select
    acceptance.customer_legal_name,
    quote_request.application_reference,
    assignment.assignee_operator_id,
    assigned_operator.display_name
  into
    v_customer,
    v_dossier_reference,
    v_assigned_operator_id,
    v_assigned_operator_name
  from public.commercial_projects as project
  join public.quote_request_quotation_acceptances as acceptance
    on acceptance.id = project.acceptance_id
   and acceptance.issuance_id = project.quotation_issuance_id
  join public.quote_request_quotation_issuances as issuance
    on issuance.id = project.quotation_issuance_id
  join public.quote_request_quotation_approvals as approval
    on approval.id = issuance.approval_id
  join public.quote_requests as quote_request
    on quote_request.id = approval.quote_request_id
  left join lws_internal.operator_dossier_assignments as assignment
    on assignment.quote_request_id = quote_request.id
  left join public.commercial_operators as assigned_operator
    on assigned_operator.operator_id = assignment.assignee_operator_id
  where project.project_id = p_project_id
    and quote_request.id = p_quote_request_id;

  select * into v_board
  from public.project_requirements_boards
  where project_id = p_project_id
    and quote_request_id = p_quote_request_id
    and status in ('DRAFT', 'FINALIZED')
  order by created_at desc
  limit 1;

  if found then
    v_empty_state := null;
    v_board_json := jsonb_build_object(
      'requirements_board_id', v_board.requirements_board_id,
      'status', v_board.status,
      'revision', v_board.revision,
      'finalized_at', v_board.finalized_at
    );

    select
      count(*) filter (where required)::integer,
      count(*) filter (where required and status = 'COMPLETED')::integer,
      count(*) filter (where required and status in ('PENDING', 'ACTIVE'))::integer,
      count(*) filter (where required and status = 'BLOCKED')::integer,
      (array_agg(requirement_id order by sort_order, item_number)
        filter (where status = 'ACTIVE'))[1],
      max(item_number) filter (where status = 'ACTIVE'),
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'requirement_id', requirement_id,
            'item_number', item_number,
            'title', title,
            'description', description,
            'category', category,
            'source', jsonb_build_object(
              'authority_type', source_reference->>'authority_type',
              'label', case source_reference->>'authority_type'
                when 'ACCEPTED_PROJECT_SCOPE' then 'Geaccepteerde projectscope'
                when 'ACCEPTED_LINE_ITEM' then
                  'Geaccepteerde offerteregel ' ||
                  (((string_to_array(source_reference->>'json_path', '.'))[2])::integer + 1)::text
              end
            ),
            'linked_page_or_module', linked_page_or_module,
            'status', status,
            'completion_mode', completion_mode,
            'sort_order', sort_order,
            'required', required,
            'started_at', started_at,
            'completed_at', completed_at,
            'verification_result', verification_result,
            'blocked_reason', blocked_reason,
            'revision', revision,
            'permitted_actions', '[]'::jsonb
          ) order by sort_order, item_number
        ),
        '[]'::jsonb
      )
    into
      v_required_total,
      v_required_completed,
      v_required_open,
      v_required_blocked,
      v_active_requirement_id,
      v_active_item_number,
      v_items
    from public.project_requirements
    where requirements_board_id = v_board.requirements_board_id
      and project_id = p_project_id;

    if v_board.status = 'DRAFT' then
      v_readiness_reason := 'REQUIREMENTS_BOARD_NOT_FINALIZED';
      v_can_create_item := true;
      v_can_finalize := v_is_management and v_required_total > 0;
    else
      v_readiness_reason := 'REQUIREMENT_VERIFICATION_PENDING';
    end if;
  end if;

  return jsonb_build_object(
    'contract_version', 1,
    'quote_request_id', p_quote_request_id,
    'project_id', p_project_id,
    'context', jsonb_build_object(
      'customer', v_customer,
      'dossier_reference', v_dossier_reference,
      'project_reference', p_project_id,
      'assigned_operator', case when v_assigned_operator_id is null then 'null'::jsonb
        else jsonb_build_object(
          'operator_id', v_assigned_operator_id,
          'display_name', v_assigned_operator_name
        ) end
    ),
    'board', v_board_json,
    'items', v_items,
    'empty_state', v_empty_state,
    'readiness', jsonb_build_object(
      'required_total', v_required_total,
      'required_completed', v_required_completed,
      'required_open', v_required_open,
      'required_blocked', v_required_blocked,
      'active_requirement_id', v_active_requirement_id,
      'active_item_number', v_active_item_number,
      'ready_for_preview', false,
      'readiness', 'UNKNOWN',
      'reason', v_readiness_reason
    ),
    'actions', jsonb_build_object(
      'can_create_board', v_board.requirements_board_id is null,
      'can_create_item', v_can_create_item,
      'can_finalize', v_can_finalize
    )
  );
end;
$$;

revoke all on function public.get_project_requirements_board_v1(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_project_requirements_board_v1(uuid, uuid)
to authenticated;

comment on function public.get_project_requirements_board_v1(uuid, uuid) is
  'Bounded Requirements Board projection with server authorization and fail-closed pre-verification readiness.';
