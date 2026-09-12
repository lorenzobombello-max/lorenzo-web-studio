create function public.get_operator_project_start_gate_v1(
  p_quote_request_id uuid,
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_project_view jsonb;
  v_current_state text;
  v_related_quote_request_id uuid;
  v_intake_complete boolean := false;
  v_m1_confirmed boolean := false;
  v_commercially_released boolean := false;
  v_project_start_allowed boolean := false;
  v_block_reason text;
begin
  if p_quote_request_id is null or p_project_id is null then
    raise exception using errcode = '22023', message = 'PROJECT_START_GATE_LOCATORS_REQUIRED';
  end if;

  -- This existing read performs the authoritative human/project authorization first.
  v_project_view := public.get_commercial_project_view_v2(p_project_id);
  v_current_state := v_project_view->>'current_state';

  select approval.quote_request_id
  into v_related_quote_request_id
  from public.commercial_projects as project
  join public.quote_request_quotation_issuances as issuance
    on issuance.id = project.quotation_issuance_id
  join public.quote_request_quotation_approvals as approval
    on approval.id = issuance.approval_id
  join public.quote_requests as request
    on request.id = approval.quote_request_id
   and request.request_kind = 'website'
   and request.record_classification = 'production'
  where project.project_id = p_project_id;

  if v_related_quote_request_id is null
     or v_related_quote_request_id <> p_quote_request_id then
    raise exception using errcode = 'P0001', message = 'DOSSIER_PROJECT_RELATIONSHIP_INVALID';
  end if;

  select intake.status in ('submitted', 'reviewed')
         and intake.submitted_at is not null
  into v_intake_complete
  from public.quote_request_intakes as intake
  where intake.quote_request_id = p_quote_request_id;
  v_intake_complete := coalesce(v_intake_complete, false);

  select coalesce(bool_or(milestone->>'payment_status' = 'CONFIRMED'), false)
  into v_m1_confirmed
  from jsonb_array_elements(
    coalesce(v_project_view->'financial_summary'->'milestones', '[]'::jsonb)
  ) as milestone
  where milestone->>'milestone' = '1';
  v_m1_confirmed := coalesce(v_m1_confirmed, false);

  v_commercially_released := v_current_state = any(array[
    'PROJECT_RELEASED',
    'PREVIEW_READY',
    'M2_PAYMENT_RECEIVED',
    'FINAL_APPROVAL_RECORDED',
    'FULL_PAYMENT_RECEIVED',
    'FINAL_TRANSFER_AUTHORIZED',
    'DELIVERED',
    'ARCHIVED'
  ]);
  v_project_start_allowed := v_intake_complete
    and v_m1_confirmed
    and v_current_state = 'PROJECT_RELEASED';

  v_block_reason := case
    when not v_intake_complete then 'BLOCKED_INTAKE'
    when not v_m1_confirmed then 'BLOCKED_M1_PAYMENT'
    when v_current_state = 'PROJECT_RELEASED' then 'READY_TO_START'
    when v_commercially_released then 'ADVANCED'
    else 'READY_FOR_RELEASE'
  end;

  return jsonb_build_object(
    'intake_complete', v_intake_complete,
    'm1_confirmed', v_m1_confirmed,
    'commercially_released', v_commercially_released,
    'project_start_allowed', v_project_start_allowed,
    'block_reason', v_block_reason,
    'current_project_state', v_current_state,
    'project_id', p_project_id,
    'quote_request_id', p_quote_request_id
  );
end;
$$;

revoke all on function public.get_operator_project_start_gate_v1(uuid, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.get_operator_project_start_gate_v1(uuid, uuid)
to authenticated;

comment on function public.get_operator_project_start_gate_v1(uuid, uuid) is
  'Read-only operator start gate derived from existing intake, confirmed M1 Finance, commercial release, dossier relationship, and project authorization authorities.';