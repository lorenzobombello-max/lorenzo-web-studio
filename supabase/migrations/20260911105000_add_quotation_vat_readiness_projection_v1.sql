create function public.evaluate_quotation_vat_evidence_v1(
  p_quote_request_id uuid,
  p_resolution_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, lws_internal, extensions
as $$
declare
  v_request public.quote_requests%rowtype;
  v_intake_id uuid;
  v_context_sha256 text;
  v_authority_id uuid;
  v_authority_count integer;
  v_classification public.quotation_vat_transaction_classifications%rowtype;
  v_policy public.quotation_vat_classification_policies%rowtype;
  v_classification_status text;
  v_classification_reason text;
  v_policy_version text;
  v_has_current_review boolean;
  v_turnover jsonb;
  v_turnover_status text := 'MISSING';
  v_turnover_reason text := 'VAT_TURNOVER_POLICY_REQUIRED';
  v_vat_readiness text;
  v_blocking_reason text;
  v_resolved_at timestamptz;
  v_can_request_review boolean := false;
  v_can_request_turnover_refresh boolean := false;
begin
  if p_quote_request_id is null or p_resolution_date is null then
    raise exception using
      errcode = '22023', message = 'VAT_READINESS_REQUEST_INVALID';
  end if;

  begin
    select * into v_request
    from public.quote_requests
    where id = p_quote_request_id;
    if not found then
      raise exception using
        errcode = 'P0001', message = 'VAT_READINESS_REQUEST_NOT_FOUND';
    end if;

    select min(intake.id::text)::uuid into v_intake_id
    from public.quote_request_intakes intake
    where intake.quote_request_id = p_quote_request_id
      and intake.status in ('submitted', 'reviewed');

    v_context_sha256 := public.quotation_vat_context_sha256_v1(
      p_quote_request_id
    );

    select exists (
      select 1
      from public.quotation_vat_review_requests review
      where review.quote_request_id = p_quote_request_id
        and review.context_sha256 = v_context_sha256
        and review.status = 'REVIEW_REQUIRED'
    ) into v_has_current_review;

    if not lws_internal.is_iso_3166_1_alpha2_v1(v_request.billing_country) then
      v_classification_status := 'MISSING';
      v_classification_reason := 'VAT_BILLING_CONTEXT_REQUIRED';
    elsif v_request.customer_type = 'individual' then
      v_classification_status := 'REVIEW_REQUIRED';
      v_classification_reason := 'VAT_INDIVIDUAL_POLICY_REVIEW_REQUIRED';
    elsif upper(btrim(v_request.billing_country)) <> 'BE' then
      v_classification_status := 'UNSUPPORTED';
      v_classification_reason := 'VAT_POLICY_UNSUPPORTED';
    elsif v_request.customer_type is distinct from 'business' then
      v_classification_status := 'REVIEW_REQUIRED';
      v_classification_reason := 'VAT_CLASSIFICATION_REVIEW_REQUIRED';
    else
      select * into v_classification
      from public.quotation_vat_transaction_classifications classification
      where classification.quote_request_id = p_quote_request_id
        and classification.context_sha256 = v_context_sha256
        and classification.classification_code =
          'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION';

      if found then
        v_policy_version := v_classification.classification_policy_version;
        select * into v_policy
        from public.quotation_vat_classification_policies policy
        where policy.classification_policy_id =
            v_classification.classification_policy_id
          and policy.status = 'APPROVED'
          and policy.effective_from <= p_resolution_date
          and (policy.effective_until is null
            or policy.effective_until >= p_resolution_date);

        if not found
           or v_classification.classification_policy_version
             is distinct from v_policy.policy_version
           or rtrim(v_classification.classification_policy_sha256)
             is distinct from rtrim(v_policy.policy_sha256)
           or v_classification.classification_code
             is distinct from v_policy.classification_code
           or v_policy.customer_type is distinct from v_request.customer_type
           or v_policy.jurisdiction <> 'BE'
           or not lws_internal.quotation_vat_classification_policy_complete_v1(
             v_policy
           ) then
          v_classification_status := 'STALE';
          v_classification_reason := 'VAT_CONTEXT_STALE';
        else
          v_classification_status := 'READY';
          v_classification_reason := null;
        end if;
      elsif exists (
        select 1
        from public.quotation_vat_transaction_classifications classification
        where classification.quote_request_id = p_quote_request_id
      ) then
        v_classification_status := 'STALE';
        v_classification_reason := 'VAT_CONTEXT_STALE';
      elsif v_has_current_review then
        v_classification_status := 'REVIEW_REQUIRED';
        v_classification_reason := 'VAT_CLASSIFICATION_REVIEW_REQUIRED';
      else
        v_classification_status := 'MISSING';
        v_classification_reason := 'VAT_CLASSIFICATION_EVIDENCE_REQUIRED';
      end if;
    end if;

    select count(*)::integer, min(authority.vat_decision_authority_id::text)::uuid
    into v_authority_count, v_authority_id
    from public.quotation_vat_decision_authorities authority
    where authority.authority_family = 'LWS_OUTGOING_VAT'
      and authority.status = 'APPROVED'
      and authority.effective_from <= p_resolution_date
      and (authority.effective_until is null
        or authority.effective_until >= p_resolution_date);

    if v_authority_count = 1 then
      v_turnover := public.evaluate_quotation_vat_turnover_freshness_v1(
        v_authority_id,
        p_resolution_date
      );
      v_turnover_status := v_turnover->>'turnover_status';
      v_turnover_reason := v_turnover->>'blocking_reason';
    end if;

    if not lws_internal.is_iso_3166_1_alpha2_v1(v_request.billing_country) then
      v_vat_readiness := 'PENDING_EVIDENCE';
      v_blocking_reason := 'VAT_BILLING_CONTEXT_REQUIRED';
    elsif v_classification_status = 'STALE'
       or v_turnover_status = 'STALE'
       or v_turnover_reason = 'VAT_TURNOVER_SOURCE_INVALID' then
      v_vat_readiness := 'STALE';
      v_blocking_reason := case
        when v_classification_status = 'STALE' then 'VAT_CONTEXT_STALE'
        else coalesce(v_turnover_reason, 'VAT_TURNOVER_STALE')
      end;
    elsif v_classification_status = 'UNSUPPORTED' then
      v_vat_readiness := 'UNSUPPORTED';
      v_blocking_reason := 'VAT_POLICY_UNSUPPORTED';
    elsif v_classification_status = 'REVIEW_REQUIRED' then
      v_vat_readiness := 'REVIEW_REQUIRED';
      v_blocking_reason := v_classification_reason;
      v_can_request_review := not v_has_current_review;
    elsif v_classification_status = 'MISSING' then
      v_vat_readiness := 'PENDING_EVIDENCE';
      v_blocking_reason := v_classification_reason;
    elsif v_turnover_status <> 'READY' then
      v_vat_readiness := 'PENDING_EVIDENCE';
      v_blocking_reason := coalesce(
        v_turnover_reason,
        'VAT_TURNOVER_EVIDENCE_REQUIRED'
      );
      v_can_request_turnover_refresh := true;
    else
      begin
        perform public.resolve_quotation_vat_authority_v1(
          p_quote_request_id,
          p_resolution_date
        );
        v_vat_readiness := 'READY';
        v_blocking_reason := 'VAT_EVIDENCE_READY';
        v_resolved_at := clock_timestamp();
      exception
        when others then
          v_vat_readiness := 'ERROR';
          v_blocking_reason := 'VAT_READINESS_ERROR';
      end;
    end if;

    if v_turnover_status = 'MISSING'
       and v_turnover_reason = 'VAT_TURNOVER_EVIDENCE_REQUIRED' then
      v_can_request_turnover_refresh := true;
    end if;

    return jsonb_build_object(
      'quote_request_id', p_quote_request_id,
      'intake_id', v_intake_id,
      'vat_readiness', v_vat_readiness,
      'classification_status', v_classification_status,
      'turnover_status', v_turnover_status,
      'blocking_reason', v_blocking_reason,
      'policy_version', v_policy_version,
      'context_sha256', v_context_sha256,
      'resolved_at', v_resolved_at,
      'can_request_review', v_can_request_review,
      'can_request_turnover_refresh', v_can_request_turnover_refresh
    );
  exception
    when others then
      return jsonb_build_object(
        'quote_request_id', p_quote_request_id,
        'intake_id', v_intake_id,
        'vat_readiness', 'ERROR',
        'classification_status', coalesce(v_classification_status, 'MISSING'),
        'turnover_status', coalesce(v_turnover_status, 'MISSING'),
        'blocking_reason', 'VAT_READINESS_ERROR',
        'policy_version', v_policy_version,
        'context_sha256', v_context_sha256,
        'resolved_at', null,
        'can_request_review', false,
        'can_request_turnover_refresh', false
      );
  end;
end;
$$;

create function public.get_quotation_vat_readiness_v1(
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, lws_internal, auth
as $$
declare
  v_actor_auth_user_id uuid;
  v_intake_id uuid;
  v_intake_count integer;
  v_result jsonb;
begin
  if p_quote_request_id is null then
    raise exception using
      errcode = '22023', message = 'VAT_READINESS_REQUEST_INVALID';
  end if;

  v_actor_auth_user_id := auth.uid();
  if v_actor_auth_user_id is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  perform lws_internal.assert_operator_application_actor_v2(
    v_actor_auth_user_id
  );

  select count(*)::integer, min(intake.id::text)::uuid
  into v_intake_count, v_intake_id
  from public.quote_request_intakes intake
  where intake.quote_request_id = p_quote_request_id
    and intake.status in ('submitted', 'reviewed');
  if v_intake_count <> 1 then
    raise exception using
      errcode = 'P0001', message = 'VAT_READINESS_INTAKE_REQUIRED';
  end if;

  v_result := public.evaluate_quotation_vat_evidence_v1(
    p_quote_request_id,
    (clock_timestamp() at time zone 'Europe/Brussels')::date
  );

  return jsonb_build_object(
    'quote_request_id', p_quote_request_id,
    'intake_id', v_intake_id,
    'vat_readiness', v_result->'vat_readiness',
    'classification_status', v_result->'classification_status',
    'turnover_status', v_result->'turnover_status',
    'blocking_reason', v_result->'blocking_reason',
    'policy_version', v_result->'policy_version',
    'context_sha256', v_result->'context_sha256',
    'resolved_at', v_result->'resolved_at',
    'can_request_review', v_result->'can_request_review',
    'can_request_turnover_refresh', v_result->'can_request_turnover_refresh'
  );
end;
$$;

revoke all on function public.evaluate_quotation_vat_evidence_v1(uuid, date)
from public, anon, authenticated, service_role;
revoke all on function public.get_quotation_vat_readiness_v1(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.evaluate_quotation_vat_evidence_v1(uuid, date)
to service_role;
grant execute on function public.get_quotation_vat_readiness_v1(uuid)
to authenticated;

comment on function public.evaluate_quotation_vat_evidence_v1(uuid, date) is
  'Private observational VAT evidence readiness evaluator. It creates no evidence and returns no privileged source facts.';
comment on function public.get_quotation_vat_readiness_v1(uuid) is
  'Caller-bound browser-safe current Brussels-date quotation VAT readiness projection.';
