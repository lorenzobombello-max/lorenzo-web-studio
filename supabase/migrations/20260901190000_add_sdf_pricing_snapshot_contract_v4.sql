create function public.is_valid_sdf_pricing_snapshot_v4(p_value jsonb)
returns boolean
language plpgsql
immutable
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_package text;
  v_authority jsonb;
  v_authority_sha256 text;
begin
  if not public.jsonb_has_exact_keys(p_value, array[
    'commercial_decision_id', 'product_kind', 'package', 'currency',
    'implementation', 'recurring', 'pricing_authority_sha256',
    'submission_sha256', 'document_evidence_sha256'
  ])
     or p_value->>'product_kind' <> 'sdf'
     or p_value->>'package' not in ('start', 'groei', 'pro', 'maatwerk')
     or p_value->>'currency' <> 'EUR'
     or (p_value->>'commercial_decision_id') !~
       '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or (p_value->>'pricing_authority_sha256') !~ '^[0-9a-f]{64}$'
     or (p_value->>'submission_sha256') !~ '^[0-9a-f]{64}$'
     or (p_value->>'document_evidence_sha256') !~ '^[0-9a-f]{64}$'
     or not public.jsonb_has_exact_keys(
       p_value->'implementation', array['amount_minor', 'price_mode']
     )
     or not public.jsonb_has_exact_keys(
       p_value->'recurring', array['amount_minor', 'interval', 'price_mode']
     )
     or p_value->'recurring'->>'interval' <> 'month' then
    return false;
  end if;

  v_package := p_value->>'package';
  v_authority := lws_internal.get_sdf_budget_guard_pricing_authority_v2(v_package);
  v_authority_sha256 := encode(
    extensions.digest(convert_to(v_authority::text, 'UTF8'), 'sha256'), 'hex'
  );
  if p_value->>'pricing_authority_sha256' <> v_authority_sha256 then
    return false;
  end if;

  if v_package = 'maatwerk' then
    return p_value->'implementation'->>'price_mode' = 'manual'
      and p_value->'implementation'->'amount_minor' = 'null'::jsonb
      and p_value->'recurring'->>'price_mode' = 'manual'
      and p_value->'recurring'->'amount_minor' = 'null'::jsonb;
  end if;

  return p_value->'implementation'->>'price_mode' = 'fixed'
    and jsonb_typeof(p_value->'implementation'->'amount_minor') = 'number'
    and (p_value->'implementation'->>'amount_minor') ~ '^(0|[1-9][0-9]*)$'
    and (p_value->'implementation'->>'amount_minor')::bigint
      = (v_authority#>>'{implementation,amount_minor}')::bigint
    and p_value->'recurring'->>'price_mode' = 'fixed'
    and jsonb_typeof(p_value->'recurring'->'amount_minor') = 'number'
    and (p_value->'recurring'->>'amount_minor') ~ '^(0|[1-9][0-9]*)$'
    and (p_value->'recurring'->>'amount_minor')::bigint
      = (v_authority#>>'{recurring,amount_minor}')::bigint;
exception
  when others then
    return false;
end;
$$;

create function public.is_strict_pricing_snapshot_v4(
  p_intake_id uuid,
  p_snapshot_contract_version smallint,
  p_config_version text,
  p_config_hash text,
  p_sdf_pricing jsonb
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_decision public.sdf_quotation_commercial_decisions%rowtype;
begin
  if p_snapshot_contract_version is distinct from 4
     or p_config_version <> '2026-09-01-v4'
     or p_config_hash !~ '^[0-9a-f]{64}$'
     or not public.is_valid_sdf_pricing_snapshot_v4(p_sdf_pricing)
     or p_config_hash <> p_sdf_pricing->>'pricing_authority_sha256' then
    return false;
  end if;

  select * into v_decision
  from public.sdf_quotation_commercial_decisions as decision
  where decision.decision_id = (p_sdf_pricing->>'commercial_decision_id')::uuid
    and exists (
      select 1 from public.quote_request_intakes as intake
      where intake.id = p_intake_id
        and intake.quote_request_id = decision.quote_request_id
    );
  if not found then
    return false;
  end if;

  return v_decision.sdf_package = p_sdf_pricing->>'package'
    and rtrim(v_decision.pricing_authority_sha256)
      = p_sdf_pricing->>'pricing_authority_sha256'
    and rtrim(v_decision.submission_sha256) = p_sdf_pricing->>'submission_sha256'
    and rtrim(v_decision.document_evidence_sha256)
      = p_sdf_pricing->>'document_evidence_sha256'
    and (v_decision.canonical_payload->>'implementation_amount_minor')::bigint
      = (p_sdf_pricing#>>'{implementation,amount_minor}')::bigint
    and (v_decision.canonical_payload->>'recurring_amount_minor')::bigint
      = (p_sdf_pricing#>>'{recurring,amount_minor}')::bigint;
exception
  when others then
    return false;
end;
$$;

alter table public.quote_request_pricing_snapshots
  add column sdf_pricing jsonb;

alter table public.quote_request_pricing_snapshots
  drop constraint quote_request_pricing_snapshots_contract_version_valid,
  add constraint quote_request_pricing_snapshots_contract_version_valid
    check (snapshot_contract_version is null or snapshot_contract_version in (2, 3, 4)),
  drop constraint quote_request_pricing_snapshots_normalized_evidence_valid,
  add constraint quote_request_pricing_snapshots_normalized_evidence_valid check (
    (snapshot_contract_version = 4 and normalized_evidence = '{}'::jsonb)
    or (snapshot_contract_version is distinct from 4
      and jsonb_typeof(normalized_evidence) = 'object'
      and jsonb_typeof(normalized_evidence->'standardPages') = 'array'
      and jsonb_typeof(normalized_evidence->'standardPageCount') = 'number'
      and (normalized_evidence->>'standardPageCount') ~ '^\d+$'
      and jsonb_typeof(normalized_evidence->'additionalLanguages') = 'array'
      and jsonb_typeof(normalized_evidence->'unknownLanguages') = 'array'
      and jsonb_typeof(normalized_evidence->'modules') = 'array'
      and jsonb_typeof(normalized_evidence->'manualComponents') = 'array')
  ),
  drop constraint quote_request_pricing_snapshots_calculation_valid,
  add constraint quote_request_pricing_snapshots_calculation_valid check (
    (snapshot_contract_version = 4 and calculation = '{}'::jsonb)
    or (snapshot_contract_version is distinct from 4
      and jsonb_typeof(calculation) = 'object'
      and calculation->>'basis' = case when snapshot_contract_version = 3
        then 'package_floor' else 'starter_floor' end
      and calculation->>'currency' = 'EUR'
      and calculation->>'vatBasis' = 'exclusive'
      and jsonb_typeof(calculation->'knownMinimumMinor') = 'number'
      and (calculation->>'knownMinimumMinor') ~ '^\d+$'
      and jsonb_typeof(calculation->'containsFromPricing') = 'boolean'
      and jsonb_typeof(calculation->'manualReviewRequired') = 'boolean'
      and jsonb_typeof(calculation->'manualReasons') = 'array'
      and jsonb_typeof(calculation->'appliedRules') = 'array'
      and ((calculation->>'manualReviewRequired')::boolean =
        (jsonb_array_length(calculation->'manualReasons') > 0)))
  ),
  drop constraint quote_request_pricing_snapshots_package_advice_valid,
  add constraint quote_request_pricing_snapshots_package_advice_valid check (
    (snapshot_contract_version = 4 and package_advice = '{}'::jsonb)
    or (snapshot_contract_version is distinct from 4
      and jsonb_typeof(package_advice) = 'object'
      and package_advice->>'status' in ('none', 'consider_professional', 'manual_scope_review')
      and jsonb_typeof(package_advice->'reasons') = 'array'
      and package_advice->'advisoryOnly' = 'true'::jsonb
      and package_advice ? 'selectedPackage'
      and package_advice->'selectedPackage' = 'null'::jsonb)
  ),
  drop constraint quote_request_pricing_snapshots_budget_evaluation_valid,
  add constraint quote_request_pricing_snapshots_budget_evaluation_valid check (
    (snapshot_contract_version = 4 and budget_evaluation = '{}'::jsonb)
    or (snapshot_contract_version is null and jsonb_typeof(budget_evaluation) = 'object')
    or (snapshot_contract_version in (2, 3)
      and public.is_valid_pricing_budget_evaluation_v2(budget_evaluation))
  ),
  add constraint quote_request_pricing_snapshots_sdf_pricing_valid check (
    (snapshot_contract_version is distinct from 4 and sdf_pricing is null)
    or (snapshot_contract_version = 4
      and package_definition is null
      and recurring_services is null
      and public.is_strict_pricing_snapshot_v4(
        intake_id, snapshot_contract_version, config_version, config_hash, sdf_pricing
      ))
  );

create or replace function public.is_current_pricing_snapshot_integrity_valid(
  p_intake_id uuid,
  p_pricing_snapshot_id uuid,
  p_payload_reference jsonb
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.quote_request_pricing_snapshots as snapshot
    join public.quote_request_pricing_snapshot_integrity as integrity
      on integrity.snapshot_id = snapshot.id
    where snapshot.id = p_pricing_snapshot_id
      and snapshot.intake_id = p_intake_id
      and p_payload_reference->>'snapshot_id' = snapshot.id::text
      and (p_payload_reference->>'snapshot_contract_version')::smallint
        is not distinct from snapshot.snapshot_contract_version
      and p_payload_reference->>'integrity_algorithm_version' = integrity.algorithm_version
      and p_payload_reference->>'integrity_key_id' = integrity.key_id
      and p_payload_reference->>'integrity_mac' = integrity.mac
      and case snapshot.snapshot_contract_version
        when 2 then public.is_strict_pricing_snapshot_v2(
          snapshot.snapshot_contract_version, snapshot.config_version,
          snapshot.config_hash, snapshot.normalized_evidence,
          snapshot.calculation, snapshot.package_advice,
          snapshot.budget_evaluation
        )
        when 3 then public.is_strict_pricing_snapshot_v3(
          snapshot.snapshot_contract_version, snapshot.config_version,
          snapshot.config_hash, snapshot.normalized_evidence,
          snapshot.calculation, snapshot.package_advice,
          snapshot.budget_evaluation, snapshot.package_definition
        )
        when 4 then public.is_strict_pricing_snapshot_v4(
          snapshot.intake_id, snapshot.snapshot_contract_version, snapshot.config_version,
          snapshot.config_hash, snapshot.sdf_pricing
        )
        else false
      end
  )
$$;

create or replace function public.is_valid_quotation_approval_payload_v1(
  p_payload jsonb,
  p_require_approval boolean default true
)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  v_line jsonb;
  v_one_time_subtotal bigint := 0;
  v_recurring_subtotal bigint := 0;
  v_discount_total bigint := 0;
  v_totals jsonb;
begin
  if not public.jsonb_has_exact_keys(p_payload, array[
    'contract_version', 'source_quote_request_id', 'source_intake_id',
    'pricing_snapshot', 'currency', 'line_items', 'totals', 'discount',
    'customer_identity', 'project_scope', 'vat_approval', 'payment_schedule',
    'validity', 'legal_references'
  ])
    or p_payload->'contract_version' <> '1'::jsonb
    or (p_payload->>'source_quote_request_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or (p_payload->>'source_intake_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or not public.jsonb_has_exact_keys(p_payload->'pricing_snapshot', array[
      'snapshot_id', 'snapshot_contract_version', 'integrity_algorithm_version',
      'integrity_key_id', 'integrity_mac'
    ])
    or (p_payload->'pricing_snapshot'->>'snapshot_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or not public.is_jsonb_nonnegative_integer(p_payload->'pricing_snapshot'->'snapshot_contract_version')
    or (p_payload->'pricing_snapshot'->>'snapshot_contract_version')::integer not in (2, 3, 4)
    or p_payload->'pricing_snapshot'->>'integrity_algorithm_version' <> 'hmac-sha256-v1'
    or (p_payload->'pricing_snapshot'->>'integrity_key_id') !~ '^v[1-9][0-9]*$'
    or not public.is_sha256_jsonb(p_payload->'pricing_snapshot'->'integrity_mac')
    or p_payload->>'currency' <> 'EUR'
    or not public.is_valid_quotation_lines_v1(p_payload->'line_items')
    or not public.jsonb_has_exact_keys(p_payload->'totals', array[
      'one_time_subtotal_minor', 'recurring_subtotal_minor', 'discount_total_minor',
      'vat_base_minor', 'vat_amount_minor', 'total_gross_minor'
    ])
    or not public.is_valid_quotation_discount_v1(p_payload->'discount', p_require_approval)
    or not public.is_valid_quotation_identity_v1(p_payload->'customer_identity')
    or not public.is_valid_quotation_scope_v1(p_payload->'project_scope')
    or not public.is_valid_quotation_vat_approval_v1(p_payload->'vat_approval', p_require_approval)
    or not public.is_valid_quotation_legal_references_v1(p_payload->'legal_references', p_require_approval)
    or not public.is_valid_quotation_validity_v1(p_payload->'validity', p_require_approval) then
    return false;
  end if;

  if p_payload->'customer_identity'->>'source_quote_request_id'
       is distinct from p_payload->>'source_quote_request_id'
     or p_payload->'customer_identity'->>'source_intake_id'
       is distinct from p_payload->>'source_intake_id'
     or p_payload->'project_scope'->>'source_intake_id'
       is distinct from p_payload->>'source_intake_id'
     or p_payload->'project_scope'->>'source_pricing_snapshot_id'
       is distinct from p_payload->'pricing_snapshot'->>'snapshot_id' then
    return false;
  end if;

  v_totals := p_payload->'totals';
  if not (
    public.is_jsonb_nonnegative_integer(v_totals->'one_time_subtotal_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'recurring_subtotal_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'discount_total_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'vat_base_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'vat_amount_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'total_gross_minor')
  ) then
    return false;
  end if;

  for v_line in select value from jsonb_array_elements(p_payload->'line_items') loop
    if v_line->>'cost_type' = 'ONE_TIME' then
      v_one_time_subtotal := v_one_time_subtotal + (v_line->>'line_net_amount_minor')::bigint;
    else
      v_recurring_subtotal := v_recurring_subtotal + (v_line->>'line_net_amount_minor')::bigint;
    end if;
    v_discount_total := v_discount_total + (v_line->>'discount_minor')::bigint;
  end loop;

  if (v_totals->>'one_time_subtotal_minor')::bigint <> v_one_time_subtotal
     or (v_totals->>'recurring_subtotal_minor')::bigint <> v_recurring_subtotal
     or (v_totals->>'discount_total_minor')::bigint <> v_discount_total
     or (p_payload->'discount'->>'discount_value_minor')::bigint <> v_discount_total
     or (v_totals->>'vat_base_minor')::bigint <> v_one_time_subtotal
     or (v_totals->>'total_gross_minor')::bigint
       <> (v_totals->>'vat_base_minor')::bigint
       + (v_totals->>'vat_amount_minor')::bigint then
    return false;
  end if;

  return public.is_valid_quotation_payment_schedule_v1(
    p_payload->'payment_schedule', v_one_time_subtotal, p_require_approval
  );
exception
  when others then
    return false;
end;
$$;

revoke all on function public.is_valid_sdf_pricing_snapshot_v4(jsonb)
from public, anon, authenticated, service_role;
revoke all on function public.is_strict_pricing_snapshot_v4(uuid, smallint, text, text, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.is_valid_sdf_pricing_snapshot_v4(jsonb) to service_role;
grant execute on function public.is_strict_pricing_snapshot_v4(uuid, smallint, text, text, jsonb) to service_role;

comment on column public.quote_request_pricing_snapshots.sdf_pricing is
  'Contract v4 only: exact SDF setup/recurring pricing envelope bound to an immutable QF-2A commercial decision and server pricing authority.';
comment on function public.is_strict_pricing_snapshot_v4(uuid, smallint, text, text, jsonb) is
  'Strict SDF pricing snapshot contract v4 validator. Rejects website grammar, client prices, missing QF-2A lineage, and MAATWERK without fixed commercial authority.';