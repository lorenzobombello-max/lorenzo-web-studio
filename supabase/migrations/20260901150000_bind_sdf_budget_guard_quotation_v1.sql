alter table public.sdf_quotation_preparation_authorities
  drop constraint sdf_quotation_preparation_authorities_sdf_package_check,
  add constraint sdf_quotation_preparation_authorities_sdf_package_check
    check (sdf_package in ('start', 'groei', 'pro', 'maatwerk'));

alter table public.sdf_quotation_preparation_authorities
  drop constraint sdf_quotation_preparation_authorities_taxonomy_version_check,
  add constraint sdf_quotation_preparation_authorities_taxonomy_version_check
    check (taxonomy_version in ('sdf_qualification_intake/1.0.0', 'sdf_qualification_intake/2.0.0', 'sdf_qualification_intake/3.0.0'));

create function lws_internal.get_sdf_budget_guard_pricing_authority_v2(p_sdf_package text)
returns jsonb
language plpgsql
immutable
strict
set search_path = lws_internal, pg_catalog
as $$
declare
  v_contract jsonb := lws_internal.get_sdf_budget_guard_contract_v1();
  v_package_contract jsonb;
  v_price_mode text;
  v_implementation_minor bigint;
  v_recurring_minor bigint;
begin
  if p_sdf_package = 'maatwerk' then
    v_price_mode := 'manual';
  elsif p_sdf_package in ('start', 'groei', 'pro') then
    v_package_contract := v_contract->p_sdf_package;
    v_price_mode := 'fixed';
    v_implementation_minor := (v_package_contract->>'setup_price')::bigint * 100;
    v_recurring_minor := (v_package_contract->>'monthly_price')::bigint * 100;
  else
    raise exception using errcode = '22023', message = 'INVALID_SDF_BUDGET_GUARD_PACKAGE';
  end if;

  return jsonb_build_object(
    'authority_version', 2,
    'package', p_sdf_package,
    'currency', 'EUR',
    'vat_basis', 'exclusive',
    'implementation', jsonb_build_object(
      'price_mode', v_price_mode,
      'amount_minor', v_implementation_minor
    ),
    'recurring', jsonb_build_object(
      'price_mode', v_price_mode,
      'amount_minor', v_recurring_minor,
      'billing_period', 'month',
      'commercial_package_price', p_sdf_package <> 'maatwerk',
      'active_recurring_obligation', false
    )
  );
end;
$$;

create function lws_internal.get_sdf_budget_guard_quotation_binding_v1(p_answers jsonb)
returns jsonb
language plpgsql
immutable
set search_path = lws_internal, pg_catalog
as $$
declare
  v_capacities jsonb;
  v_evaluation jsonb;
  v_package text;
  v_pricing jsonb;
begin
  v_capacities := lws_internal.get_sdf_budget_guard_capacity_input_v1(p_answers);
  v_evaluation := lws_internal.evaluate_sdf_budget_guard_v1(
    (v_capacities->>'flow_count')::bigint,
    (v_capacities->>'document_type_count')::bigint,
    (v_capacities->>'pages_per_month')::bigint,
    (v_capacities->>'user_count')::bigint
  );
  v_package := v_evaluation->>'package';
  v_pricing := lws_internal.get_sdf_budget_guard_pricing_authority_v2(v_package);

  return jsonb_build_object(
    'capacities', v_capacities,
    'evaluation', v_evaluation,
    'package', v_package,
    'pricing', v_pricing
  );
end;
$$;

create or replace function public.authorize_sdf_quotation_preparation_v1(p_quote_request_id uuid,p_idempotency_key uuid)
returns jsonb language plpgsql volatile security definer set search_path=public,lws_internal,auth,extensions,pg_catalog as $$
declare v_operator public.commercial_operators%rowtype; v_request public.quote_requests%rowtype; v_intake public.sdf_qualification_intakes%rowtype; v_submission public.sdf_qualification_intake_submissions%rowtype; v_completion public.sdf_qualification_intake_events%rowtype; v_existing public.sdf_quotation_preparation_authorities%rowtype; v_quotation_id uuid; v_binding jsonb; v_package text; v_pricing jsonb; v_pricing_hash char(64); v_submission_hash char(64); v_fingerprint char(64);
begin
  v_operator:=lws_internal.assert_sdf_owner_v1();
  select * into v_request from public.quote_requests where id=p_quote_request_id for update;
  if not found or v_request.request_kind<>'slimme_documentenflow' then raise exception using errcode='23514',message='SDF_REQUEST_KIND_REQUIRED'; end if;
  if v_request.status='rejected' then raise exception using errcode='55000',message='SDF_QUOTATION_PREPARATION_NOT_ELIGIBLE'; end if;
  if exists(select 1 from lws_internal.operator_dossier_states where quote_request_id=p_quote_request_id and state='TRASHED') then raise exception using errcode='55000',message='SDF_QUOTATION_PREPARATION_NOT_ELIGIBLE'; end if;
  select * into v_intake from public.sdf_qualification_intakes where quote_request_id=p_quote_request_id for update;
  if not found or v_intake.status<>'qualification_complete' then raise exception using errcode='55000',message='SDF_QUALIFICATION_COMPLETE_REQUIRED'; end if;
  select * into strict v_submission from public.sdf_qualification_intake_submissions where intake_id=v_intake.intake_id and submission_sequence=v_intake.latest_submission_sequence;
  select * into strict v_completion from public.sdf_qualification_intake_events where intake_id=v_intake.intake_id and event_kind='QUALIFICATION_COMPLETE' and submission_sequence=v_submission.submission_sequence order by occurred_at desc limit 1;
  v_submission_hash:=encode(extensions.digest(convert_to(v_submission.answers::text,'UTF8'),'sha256'),'hex');
  if v_submission_hash<>v_submission.payload_sha256 or v_submission.taxonomy_version<>v_intake.taxonomy_version then raise exception using errcode='55000',message='SDF_QUALIFICATION_INTEGRITY_MISMATCH'; end if;

  if v_submission.taxonomy_version='sdf_qualification_intake/3.0.0' then
    v_binding:=lws_internal.get_sdf_budget_guard_quotation_binding_v1(v_submission.answers);
    v_package:=v_binding->>'package';
    v_pricing:=v_binding->'pricing';
  else
    if v_request.sdf_package is null then raise exception using errcode='55000',message='SDF_QUOTATION_PREPARATION_NOT_ELIGIBLE'; end if;
    v_package:=v_request.sdf_package;
    v_pricing:=public.get_sdf_package_pricing_authority_v1(v_package);
  end if;

  v_pricing_hash:=encode(extensions.digest(convert_to(v_pricing::text,'UTF8'),'sha256'),'hex');
  v_fingerprint:=encode(extensions.digest(convert_to(
    case when v_submission.taxonomy_version='sdf_qualification_intake/3.0.0'
      then jsonb_build_object('v',2,'request',p_quote_request_id,'intake',v_intake.intake_id,'taxonomy',v_submission.taxonomy_version,'submission',v_submission.payload_sha256,'completion',v_completion.event_id,'package',v_package,'pricing',v_pricing_hash)
      else jsonb_build_object('v',1,'request',p_quote_request_id,'intake',v_intake.intake_id,'submission',v_submission.payload_sha256,'completion',v_completion.event_id,'package',v_package,'pricing',v_pricing_hash)
    end::text,'UTF8'),'sha256'),'hex');
  select * into v_existing from public.sdf_quotation_preparation_authorities where idempotency_key=p_idempotency_key;
  if found then if v_existing.request_fingerprint<>v_fingerprint then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT'; end if; return jsonb_build_object('authority_id',v_existing.authority_id,'quotation_id',v_existing.quotation_id,'status','QUOTATION_PREPARATION_ELIGIBLE','sdf_package',v_existing.sdf_package,'replayed',true); end if;
  if exists(select 1 from public.sdf_quotations where quote_request_id=p_quote_request_id) or exists(select 1 from public.sdf_quotation_preparation_authorities where quote_request_id=p_quote_request_id) then raise exception using errcode='55000',message='SDF_QUOTATION_PREPARATION_CONFLICT'; end if;
  insert into public.sdf_quotations(quote_request_id) values(p_quote_request_id) returning quotation_id into v_quotation_id;
  insert into public.sdf_quotation_preparation_authorities(quote_request_id,quotation_id,qualification_intake_id,taxonomy_version,submission_sequence,submission_sha256,completion_event_id,sdf_package,pricing_authority_version,pricing_authority_sha256,actor_operator_id,actor_role,idempotency_key,request_fingerprint) values(p_quote_request_id,v_quotation_id,v_intake.intake_id,v_submission.taxonomy_version,v_submission.submission_sequence,v_submission.payload_sha256,v_completion.event_id,v_package,(v_pricing->>'authority_version')::integer,v_pricing_hash,v_operator.operator_id,'owner',p_idempotency_key,v_fingerprint) returning * into v_existing;
  return jsonb_build_object('authority_id',v_existing.authority_id,'quotation_id',v_existing.quotation_id,'status','QUOTATION_PREPARATION_ELIGIBLE','sdf_package',v_existing.sdf_package,'replayed',false);
end;
$$;

revoke all on function lws_internal.get_sdf_budget_guard_pricing_authority_v2(text) from public,anon,authenticated,service_role;
revoke all on function lws_internal.get_sdf_budget_guard_quotation_binding_v1(jsonb) from public,anon,authenticated,service_role;

comment on function lws_internal.get_sdf_budget_guard_pricing_authority_v2(text) is
  'Private immutable BG-3 pricing authority derived from the frozen Budget Guard contract. MAATWERK requires manual pricing and has no fixed amount.';
comment on function lws_internal.get_sdf_budget_guard_quotation_binding_v1(jsonb) is
  'Private immutable V3 qualification binding from canonical capacities through evaluator package to server pricing.';