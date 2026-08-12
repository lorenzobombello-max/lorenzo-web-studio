alter table public.quote_request_intakes
  drop constraint quote_request_intakes_package_definition_valid;

alter table public.quote_request_intakes
  add constraint quote_request_intakes_package_definition_valid
  check (
    selected_package_definition_id is null
    or selected_package_definition_id in (
      'starter_v1', 'professional_v1', 'professional_v2'
    )
  );

create or replace function public.is_strict_pricing_snapshot_v3(
  p_snapshot_contract_version smallint,
  p_config_version text,
  p_config_hash text,
  p_normalized_scope jsonb,
  p_calculation jsonb,
  p_package_advice jsonb,
  p_budget_evaluation jsonb,
  p_package_definition jsonb
)
returns boolean
language plpgsql
stable
set search_path = public
as $$
declare
  v_package_id text;
  v_floor bigint;
  v_page_limit integer;
  v_corrections integer;
  v_page_count integer;
  v_extra_pages integer;
  v_extra_page_amount integer;
  v_extra_page_mode text;
  v_floor_rule jsonb;
  v_extra_rule jsonb;
  v_starter_entitlements constant jsonb := '[
    "responsive_design", "technical_foundation", "navigation",
    "browser_compatibility", "technical_seo_base", "testing_and_delivery",
    "standard_contact_form", "social_links", "google_maps", "whatsapp",
    "normal_gallery_reviews", "public_downloads",
    "supplied_content_media_processing", "normal_ai_image_support",
    "primary_language"
  ]'::jsonb;
  v_professional_v2_entitlements constant jsonb := '[
    "responsive_design", "technical_foundation", "navigation",
    "browser_compatibility", "technical_seo_base", "testing_and_delivery",
    "standard_contact_form", "social_links", "google_maps", "whatsapp",
    "normal_gallery_reviews", "public_downloads",
    "supplied_content_media_processing", "normal_ai_image_support",
    "primary_language", "blog_news"
  ]'::jsonb;
begin
  if p_snapshot_contract_version <> 3
     or p_config_version not in ('2.0.0', '2026-08-12-v1')
     or p_config_hash !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(p_package_definition) <> 'object'
     or not (p_package_definition ?& array[
       'id', 'version', 'label', 'priceMode', 'floorMinor',
       'standardPageLimit', 'includedCorrectionRounds',
       'entitlementSetId', 'entitlements'
     ])
     or (select count(*) from jsonb_object_keys(p_package_definition)) <> 9
     or p_package_definition->>'priceMode' <> 'from'
     or p_package_definition->>'entitlementSetId' <> 'normal_web_v1' then
    return false;
  end if;

  v_package_id := p_package_definition->>'id';
  if v_package_id = 'starter_v1' then
    v_floor := 180000;
    v_page_limit := 5;
    v_corrections := 1;
    if p_package_definition->'version' <> '1'::jsonb
       or p_package_definition->>'label' <> 'Starter'
       or p_package_definition->'entitlements' <> v_starter_entitlements then
      return false;
    end if;
  elsif v_package_id = 'professional_v1' then
    v_floor := 320000;
    v_page_limit := 12;
    v_corrections := 2;
    if p_config_version <> '2.0.0'
       or p_package_definition->'version' <> '1'::jsonb
       or p_package_definition->>'label' <> 'Professional'
       or p_package_definition->'entitlements' <> v_starter_entitlements then
      return false;
    end if;
  elsif v_package_id = 'professional_v2' then
    v_floor := 350000;
    v_page_limit := 10;
    v_corrections := 2;
    if p_config_version <> '2026-08-12-v1'
       or p_package_definition->'version' <> '2'::jsonb
       or p_package_definition->>'label' <> 'Professional'
       or p_package_definition->'entitlements' <>
         v_professional_v2_entitlements then
      return false;
    end if;
  else
    return false;
  end if;

  if p_config_version = '2026-08-12-v1' then
    v_extra_page_amount := 22500;
    v_extra_page_mode := 'fixed';
  else
    v_extra_page_amount := 20000;
    v_extra_page_mode := 'from';
  end if;

  if (p_package_definition->>'floorMinor')::bigint <> v_floor
     or (p_package_definition->>'standardPageLimit')::integer <> v_page_limit
     or (p_package_definition->>'includedCorrectionRounds')::integer <>
       v_corrections
     or jsonb_typeof(p_normalized_scope) <> 'object'
     or jsonb_typeof(p_normalized_scope->'standardPages') <> 'array'
     or jsonb_typeof(p_normalized_scope->'standardPageCount') <> 'number'
     or (p_normalized_scope->>'standardPageCount') !~ '^\d+$'
     or jsonb_array_length(p_normalized_scope->'standardPages') <>
       (p_normalized_scope->>'standardPageCount')::integer
     or jsonb_typeof(p_calculation) <> 'object'
     or not (p_calculation ?& array[
       'basis', 'currency', 'vatBasis', 'knownMinimumMinor',
       'containsFromPricing', 'manualReviewRequired', 'manualReasons',
       'appliedRules'
     ])
     or (select count(*) from jsonb_object_keys(p_calculation)) <> 8
     or p_calculation->>'basis' <> 'package_floor'
     or p_calculation->>'currency' <> 'EUR'
     or p_calculation->>'vatBasis' <> 'exclusive'
     or jsonb_typeof(p_calculation->'appliedRules') <> 'array'
     or jsonb_array_length(p_calculation->'appliedRules') < 1
     or not public.is_valid_pricing_budget_evaluation_v2(p_budget_evaluation)
     or jsonb_typeof(p_package_advice) <> 'object'
     or p_package_advice->'advisoryOnly' <> 'true'::jsonb
     or p_package_advice->'selectedPackage' <> 'null'::jsonb then
    return false;
  end if;

  v_page_count := (p_normalized_scope->>'standardPageCount')::integer;
  v_extra_pages := greatest(0, v_page_count - v_page_limit);
  v_floor_rule := p_calculation->'appliedRules'->0;
  if v_floor_rule->>'ruleId' <> v_package_id || '_floor'
     or v_floor_rule->>'mode' <> 'from'
     or v_floor_rule->'amountMinor' <> to_jsonb(v_floor)
     or v_floor_rule->'quantity' <> '1'::jsonb
     or v_floor_rule->'knownMinimumContributionMinor' <> to_jsonb(v_floor) then
    return false;
  end if;

  select rule.value into v_extra_rule
  from jsonb_array_elements(p_calculation->'appliedRules') as rule(value)
  where rule.value->>'ruleId' = 'extra_standard_page';

  if (v_extra_pages = 0 and v_extra_rule is not null)
     or (v_extra_pages > 0 and (
       v_extra_rule is null
       or v_extra_rule->>'mode' <> v_extra_page_mode
       or v_extra_rule->'amountMinor' <> to_jsonb(v_extra_page_amount)
       or v_extra_rule->'quantity' <> to_jsonb(v_extra_pages)
       or v_extra_rule->'knownMinimumContributionMinor' <>
         to_jsonb(v_extra_pages * v_extra_page_amount)
     )) then
    return false;
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_calculation->'appliedRules') as rule(value)
    where jsonb_typeof(rule.value) <> 'object'
      or rule.value->>'mode' not in ('included', 'fixed', 'from', 'manual')
      or (rule.value->>'quantity') !~ '^[1-9]\d*$'
      or (rule.value->>'knownMinimumContributionMinor') !~ '^\d+$'
      or (
        rule.value->>'mode' in ('fixed', 'from')
        and (rule.value->>'amountMinor') !~ '^[1-9]\d*$'
      )
      or (
        rule.value->>'mode' in ('included', 'manual')
        and rule.value ? 'amountMinor'
      )
  ) or (
    select count(*) <> count(distinct rule.value->>'ruleId')
    from jsonb_array_elements(p_calculation->'appliedRules') as rule(value)
  ) or (p_calculation->>'knownMinimumMinor')::bigint <> (
    select sum((rule.value->>'knownMinimumContributionMinor')::bigint)
    from jsonb_array_elements(p_calculation->'appliedRules') as rule(value)
  ) then
    return false;
  end if;
  return true;
exception when others then
  return false;
end;
$$;

create or replace function public.update_quote_request_intake_with_evidence(
  p_access_token_hash text,
  p_action text,
  p_legacy_data jsonb,
  p_evidence_data jsonb,
  p_admin_access_token_hash text default null,
  p_admin_access_token_expires_at timestamptz default null
)
returns table (
  outcome text, intake_status text, started_at timestamptz,
  submitted_at timestamptz, updated_at timestamptz,
  notification_job_id uuid, notification_job_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evidence_result record;
  v_legacy_result record;
  v_package jsonb;
begin
  if p_action not in ('save_draft', 'submit')
     or p_evidence_data is null
     or jsonb_typeof(p_evidence_data) <> 'object' then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_EVIDENCE';
  end if;
  v_package := p_evidence_data->'selected_package_definition_id';
  if p_evidence_data ? 'selected_package_definition_id'
     and v_package <> 'null'::jsonb
     and (
       jsonb_typeof(v_package) <> 'string'
       or v_package #>> '{}' not in (
         'starter_v1', 'professional_v1', 'professional_v2'
       )
     ) then
    raise exception using errcode = '22023', message = 'INVALID_PACKAGE_DEFINITION_ID';
  end if;

  select * into v_evidence_result
  from public.update_quote_request_intake_evidence(
    p_access_token_hash,
    p_evidence_data - 'selected_package_definition_id'
  );
  if v_evidence_result.outcome <> 'saved' then
    return query select v_evidence_result.outcome,
      v_evidence_result.intake_status, v_evidence_result.started_at,
      null::timestamptz, v_evidence_result.updated_at, null::uuid, null::text;
    return;
  end if;

  if p_evidence_data ? 'selected_package_definition_id' then
    update public.quote_request_intakes
    set selected_package_definition_id = case
      when v_package = 'null'::jsonb then null else v_package #>> '{}'
    end
    where access_token_hash = p_access_token_hash;
  end if;

  select * into v_legacy_result
  from public.update_quote_request_intake(
    p_access_token_hash, p_action, p_legacy_data,
    p_admin_access_token_hash, p_admin_access_token_expires_at
  );
  if v_legacy_result.outcome not in ('saved', 'submitted') then
    raise exception using errcode = '40001',
      message = 'INTAKE_EVIDENCE_ORCHESTRATION_ROLLBACK';
  end if;
  return query select v_legacy_result.outcome, v_legacy_result.intake_status,
    v_legacy_result.started_at, v_legacy_result.submitted_at,
    v_legacy_result.updated_at, v_legacy_result.notification_job_id,
    v_legacy_result.notification_job_status;
end;
$$;
