create function public.evaluate_sdf_budget_guard_capacity_preview_v1(p_customer_capability_digest text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_intake public.sdf_qualification_intakes%rowtype;
  v_request_kind text;
  v_capacity jsonb;
  v_evaluation jsonb;
begin
  select intake.*
  into v_intake
  from public.sdf_qualification_intakes intake
  where intake.customer_capability_digest = p_customer_capability_digest
    and intake.customer_capability_revoked_at is null
    and intake.customer_capability_expires_at > statement_timestamp();

  if not found then
    raise exception using errcode = '42501', message = 'SDF_INTAKE_ACCESS_DENIED';
  end if;

  select request.request_kind
  into v_request_kind
  from public.quote_requests request
  where request.id = v_intake.quote_request_id;

  if v_request_kind is distinct from 'slimme_documentenflow' then
    raise exception using errcode = '23514', message = 'SDF_REQUEST_KIND_REQUIRED';
  end if;

  if not lws_internal.sdf_payload_valid_v3(v_intake.draft_answers, true) then
    return jsonb_build_object(
      'preview_status', 'INCOMPLETE',
      'preview_kind', 'CAPACITY_ONLY',
      'minimum_capacity_package', null,
      'maatwerk_required_by_capacity', false,
      'normalized_capacity', null,
      'reasons', jsonb_build_array(),
      'final_decision_pending', true,
      'pending_authorities', jsonb_build_array('complexity_level', 'exceptional_scope')
    );
  end if;

  v_capacity := lws_internal.get_sdf_budget_guard_capacity_input_v1(v_intake.draft_answers);
  v_evaluation := lws_internal.evaluate_sdf_budget_guard_v1(
    (v_capacity->>'flow_count')::bigint,
    (v_capacity->>'document_type_count')::bigint,
    (v_capacity->>'pages_per_month')::bigint,
    (v_capacity->>'user_count')::bigint
  );

  return jsonb_build_object(
    'preview_status', 'READY',
    'preview_kind', 'CAPACITY_ONLY',
    'minimum_capacity_package', v_evaluation->>'package',
    'maatwerk_required_by_capacity', v_evaluation->>'package' = 'maatwerk',
    'normalized_capacity', v_capacity,
    'reasons', jsonb_build_array(
      jsonb_build_object('dimension','flow_count','value',v_capacity->'flow_count','minimum_capacity_package',lws_internal.evaluate_sdf_budget_guard_v1((v_capacity->>'flow_count')::bigint,1,1,1)->>'package'),
      jsonb_build_object('dimension','document_type_count','value',v_capacity->'document_type_count','minimum_capacity_package',lws_internal.evaluate_sdf_budget_guard_v1(1,(v_capacity->>'document_type_count')::bigint,1,1)->>'package'),
      jsonb_build_object('dimension','normalized_monthly_pages','value',v_capacity->'pages_per_month','minimum_capacity_package',lws_internal.evaluate_sdf_budget_guard_v1(1,1,(v_capacity->>'pages_per_month')::bigint,1)->>'package'),
      jsonb_build_object('dimension','user_count','value',v_capacity->'user_count','minimum_capacity_package',lws_internal.evaluate_sdf_budget_guard_v1(1,1,1,(v_capacity->>'user_count')::bigint)->>'package')
    ),
    'final_decision_pending', true,
    'pending_authorities', jsonb_build_array('complexity_level', 'exceptional_scope')
  );
end;
$$;

revoke all on function public.evaluate_sdf_budget_guard_capacity_preview_v1(text) from public;
grant execute on function public.evaluate_sdf_budget_guard_capacity_preview_v1(text) to anon, authenticated, service_role;

comment on function public.evaluate_sdf_budget_guard_capacity_preview_v1(text) is
  'Capability-bound preliminary SDF capacity preview over the current server draft. This is not the final six-dimensional commercial decision.';