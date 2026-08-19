alter table public.quote_request_intakes
  drop constraint quote_request_intakes_package_definition_valid,
  add constraint quote_request_intakes_package_definition_valid
  check (
    selected_package_definition_id is null
    or selected_package_definition_id in ('starter_v1', 'professional_v1', 'professional_v2')
  );

alter table public.quote_request_pricing_snapshots
  drop constraint quote_request_pricing_snapshots_config_version_valid,
  add constraint quote_request_pricing_snapshots_config_version_valid
  check (
    config_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'
    or config_version = '2026-08-16-v3'
  );

create or replace function public.is_valid_pricing_budget_evaluation_v2(p_value jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_value) = 'object'
    and p_value ?& array[
      'contractVersion', 'evidenceProvenance', 'categoryScheme', 'categoryCode',
      'originalLabel', 'status', 'outsideBudgetWishes'
    ]
    and (select count(*) = 7 from jsonb_object_keys(p_value))
    and p_value->'contractVersion' = '2'::jsonb
    and p_value->>'evidenceProvenance' in (
      'budget_guard_v1', 'budget_guard_v2', 'legacy_label', 'missing', 'ambiguous'
    )
    and p_value->>'status' in (
      'below_starter_starting_price',
      'known_minimum_exceeds_category_upper_bound',
      'possibly_compatible_with_category',
      'unbounded_category_indeterminate',
      'legacy_category_not_safely_comparable',
      'manual_review_required'
    )
    and jsonb_typeof(p_value->'outsideBudgetWishes') in ('boolean', 'null')
    and (
      (
        p_value->>'evidenceProvenance' = 'budget_guard_v1'
        and p_value->>'categoryScheme' = 'budget_guard_v1'
        and (
          (p_value->>'categoryCode' = 'below_1800' and p_value->>'originalLabel' = 'Minder dan EUR 1.800')
          or (p_value->>'categoryCode' = '1800_to_below_3200' and p_value->>'originalLabel' = 'EUR 1.800 tot minder dan EUR 3.200')
          or (p_value->>'categoryCode' = '3200_to_6000_inclusive' and p_value->>'originalLabel' = 'EUR 3.200 t/m EUR 6.000')
          or (p_value->>'categoryCode' = 'above_6000' and p_value->>'originalLabel' = 'Meer dan EUR 6.000')
        )
      )
      or (
        p_value->>'evidenceProvenance' = 'budget_guard_v2'
        and p_value->>'categoryScheme' = 'budget_guard_v2'
        and (
          (p_value->>'categoryCode' = 'below_1800' and p_value->>'originalLabel' = 'Minder dan EUR 1.800')
          or (p_value->>'categoryCode' = '1800_to_below_3500' and p_value->>'originalLabel' = 'EUR 1.800 tot minder dan EUR 3.500')
          or (p_value->>'categoryCode' = '3500_to_6000_inclusive' and p_value->>'originalLabel' = 'EUR 3.500 t/m EUR 6.000')
          or (p_value->>'categoryCode' = 'above_6000' and p_value->>'originalLabel' = 'Meer dan EUR 6.000')
        )
      )
      or (
        p_value->>'evidenceProvenance' in ('legacy_label', 'ambiguous')
        and p_value->'categoryScheme' = 'null'::jsonb
        and p_value->'categoryCode' = 'null'::jsonb
        and jsonb_typeof(p_value->'originalLabel') = 'string'
        and p_value->>'status' in ('legacy_category_not_safely_comparable', 'manual_review_required')
        and p_value->'outsideBudgetWishes' = 'null'::jsonb
      )
      or (
        p_value->>'evidenceProvenance' = 'missing'
        and p_value->'categoryScheme' = 'null'::jsonb
        and p_value->'categoryCode' = 'null'::jsonb
        and p_value->'originalLabel' = 'null'::jsonb
        and p_value->>'status' = 'manual_review_required'
        and p_value->'outsideBudgetWishes' = 'null'::jsonb
      )
    )
$$;

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
  v_floor_rule jsonb;
  v_extra_rule jsonb;
  v_entitlements jsonb;
  v_extra_page_mode text;
  v_extra_page_amount bigint;
begin
  if p_snapshot_contract_version <> 3
     or p_config_version not in ('2.0.0', '2026-08-16-v3')
     or p_config_hash !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(p_package_definition) <> 'object'
     or not (p_package_definition ?& array[
       'id', 'version', 'label', 'priceMode', 'floorMinor',
       'standardPageLimit', 'includedCorrectionRounds',
       'entitlementSetId', 'entitlements'
     ])
     or (select count(*) from jsonb_object_keys(p_package_definition)) <> 9
     or p_package_definition->>'priceMode' <> 'from'
     or p_package_definition->>'entitlementSetId' <> 'normal_web_v1'
     or jsonb_typeof(p_package_definition->'entitlements') <> 'array' then
    return false;
  end if;

  v_package_id := p_package_definition->>'id';
  if v_package_id = 'starter_v1' then
    v_floor := 180000; v_page_limit := 5; v_corrections := 1;
    v_entitlements := '[
      "responsive_design", "technical_foundation", "navigation",
      "browser_compatibility", "technical_seo_base", "testing_and_delivery",
      "standard_contact_form", "social_links", "google_maps", "whatsapp",
      "normal_gallery_reviews", "public_downloads",
      "supplied_content_media_processing", "normal_ai_image_support",
      "primary_language"
    ]'::jsonb;
    if p_package_definition->>'label' <> 'Starter'
       or p_package_definition->'version' <> '1'::jsonb then return false; end if;
  elsif v_package_id = 'professional_v1' then
    v_floor := 320000; v_page_limit := 12; v_corrections := 2;
    v_entitlements := '[
      "responsive_design", "technical_foundation", "navigation",
      "browser_compatibility", "technical_seo_base", "testing_and_delivery",
      "standard_contact_form", "social_links", "google_maps", "whatsapp",
      "normal_gallery_reviews", "public_downloads",
      "supplied_content_media_processing", "normal_ai_image_support",
      "primary_language"
    ]'::jsonb;
    if p_config_version <> '2.0.0'
       or p_package_definition->>'label' <> 'Professional'
       or p_package_definition->'version' <> '1'::jsonb then return false; end if;
  elsif v_package_id = 'professional_v2' then
    v_floor := 350000; v_page_limit := 10; v_corrections := 2;
    v_entitlements := '[
      "responsive_design", "technical_foundation", "navigation",
      "browser_compatibility", "technical_seo_base", "testing_and_delivery",
      "standard_contact_form", "social_links", "google_maps", "whatsapp",
      "normal_gallery_reviews", "public_downloads",
      "supplied_content_media_processing", "normal_ai_image_support",
      "primary_language", "blog_news"
    ]'::jsonb;
    if p_config_version <> '2026-08-16-v3'
       or p_package_definition->>'label' <> 'Professional'
       or p_package_definition->'version' <> '2'::jsonb then return false; end if;
  else
    return false;
  end if;

  if (p_package_definition->>'floorMinor')::bigint <> v_floor
     or (p_package_definition->>'standardPageLimit')::integer <> v_page_limit
     or (p_package_definition->>'includedCorrectionRounds')::integer <> v_corrections
     or p_package_definition->'entitlements' <> v_entitlements
     or jsonb_typeof(p_normalized_scope) <> 'object'
     or jsonb_typeof(p_normalized_scope->'standardPages') <> 'array'
     or jsonb_typeof(p_normalized_scope->'standardPageCount') <> 'number'
     or (p_normalized_scope->>'standardPageCount') !~ '^\d+$'
     or jsonb_array_length(p_normalized_scope->'standardPages') <>
       (p_normalized_scope->>'standardPageCount')::integer
     or jsonb_typeof(p_calculation) <> 'object'
     or not (p_calculation ?& array[
       'basis', 'currency', 'vatBasis', 'knownMinimumMinor',
       'containsFromPricing', 'manualReviewRequired', 'manualReasons', 'appliedRules'
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

  if p_config_version = '2026-08-16-v3' then
    v_extra_page_mode := 'fixed';
    v_extra_page_amount := 22500;
  else
    v_extra_page_mode := 'from';
    v_extra_page_amount := 20000;
  end if;

  if (v_extra_pages = 0 and v_extra_rule is not null)
     or (v_extra_pages > 0 and (
       v_extra_rule is null
       or v_extra_rule->>'mode' <> v_extra_page_mode
       or v_extra_rule->'amountMinor' <> to_jsonb(v_extra_page_amount)
       or v_extra_rule->'quantity' <> to_jsonb(v_extra_pages)
       or v_extra_rule->'knownMinimumContributionMinor' <> to_jsonb(v_extra_pages * v_extra_page_amount)
     )) then
    return false;
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_calculation->'appliedRules') as rule(value)
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

create or replace function public.update_quote_request_intake_v5(
  p_access_token_hash text,
  p_action text,
  p_data jsonb,
  p_admin_access_token_hash text default null,
  p_admin_access_token_expires_at timestamptz default null,
  p_budget_guard_snapshot jsonb default null,
  p_pricing_snapshot_integrity jsonb default null
)
returns table (
  outcome text, intake_status text, started_at timestamptz,
  submitted_at timestamptz, updated_at timestamptz,
  notification_job_id uuid, notification_job_status text, pricing_snapshot jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result record;
  v_intake public.quote_request_intakes%rowtype;
  v_request public.quote_requests%rowtype;
  v_snapshot public.quote_request_pricing_snapshots%rowtype;
  v_snapshot_version smallint;
  v_package_id text;
  v_budget_evaluation jsonb;
  v_budget_label text;
  v_budget_scheme text;
  v_budget_code text;
  v_legacy_data jsonb;
  v_evidence_keys constant text[] := array[
    'primary_language', 'additional_languages', 'page_scope_details',
    'quote_form_details', 'multilingual_details', 'download_details',
    'content_media_details', 'newsletter_details', 'hosting_maintenance_details',
    'deadline_details', 'seo_details', 'budget_update_category_scheme',
    'budget_update_category_code', 'selected_package_definition_id'
  ];
begin
  if p_budget_guard_snapshot is null or jsonb_typeof(p_budget_guard_snapshot) <> 'object'
     or (p_budget_guard_snapshot->>'snapshotContractVersion') !~ '^\d+$' then
    raise exception using errcode = '22023', message = 'INVALID_PRICING_SNAPSHOT';
  end if;
  v_snapshot_version := (p_budget_guard_snapshot->>'snapshotContractVersion')::smallint;
  if v_snapshot_version = 2 then
    return query select * from public.update_quote_request_intake_v4(
      p_access_token_hash, p_action, p_data, p_admin_access_token_hash,
      p_admin_access_token_expires_at, p_budget_guard_snapshot,
      p_pricing_snapshot_integrity
    );
    return;
  end if;
  if p_action <> 'submit' or v_snapshot_version <> 3
     or p_data is null or jsonb_typeof(p_data) <> 'object'
     or jsonb_typeof(p_pricing_snapshot_integrity) <> 'object'
     or p_pricing_snapshot_integrity->>'algorithmVersion' <> 'hmac-sha256-v1'
     or p_pricing_snapshot_integrity->>'keyId' !~ '^v[1-9][0-9]*$'
     or p_pricing_snapshot_integrity->>'mac' !~ '^[0-9a-f]{64}$'
     or not (p_budget_guard_snapshot ?& array[
       'snapshotContractVersion', 'pricingConfigVersion', 'pricingConfigHash',
       'normalizedScope', 'calculation', 'packageAdvice', 'budgetEvaluation',
       'packageDefinition'
     ])
     or (select count(*) from jsonb_object_keys(p_budget_guard_snapshot)) <> 8
     or not public.is_strict_pricing_snapshot_v3(
       3::smallint,
       p_budget_guard_snapshot->>'pricingConfigVersion',
       p_budget_guard_snapshot->>'pricingConfigHash',
       p_budget_guard_snapshot->'normalizedScope',
       p_budget_guard_snapshot->'calculation',
       p_budget_guard_snapshot->'packageAdvice',
       p_budget_guard_snapshot->'budgetEvaluation',
       p_budget_guard_snapshot->'packageDefinition'
     ) then
    raise exception using errcode = '22023', message = 'INVALID_PRICING_SNAPSHOT_V3';
  end if;

  v_package_id := p_budget_guard_snapshot->'packageDefinition'->>'id';
  if jsonb_typeof(p_data->'selected_package_definition_id') <> 'string'
     or p_data->>'selected_package_definition_id' is distinct from v_package_id then
    raise exception using errcode = '22023', message = 'PRICING_SNAPSHOT_PACKAGE_MISMATCH';
  end if;
  v_legacy_data := p_data - v_evidence_keys;
  select * into v_result from public.update_quote_request_intake(
    p_access_token_hash, p_action, v_legacy_data,
    p_admin_access_token_hash, p_admin_access_token_expires_at
  );

  if v_result.outcome <> 'submitted' then
    select snapshot.* into v_snapshot
    from public.quote_request_pricing_snapshots as snapshot
    inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id
    where intake.access_token_hash = p_access_token_hash;
    return query select v_result.outcome, v_result.intake_status,
      v_result.started_at, v_result.submitted_at, v_result.updated_at,
      v_result.notification_job_id, v_result.notification_job_status,
      case when v_snapshot.id is null then null else jsonb_build_object(
        'snapshotContractVersion', v_snapshot.snapshot_contract_version,
        'pricingConfigVersion', v_snapshot.config_version,
        'pricingConfigHash', v_snapshot.config_hash,
        'normalizedScope', v_snapshot.normalized_evidence,
        'calculation', v_snapshot.calculation,
        'packageAdvice', v_snapshot.package_advice,
        'budgetEvaluation', v_snapshot.budget_evaluation,
        'packageDefinition', v_snapshot.package_definition,
        'createdAt', v_snapshot.created_at
      ) end;
    return;
  end if;

  select * into v_intake from public.quote_request_intakes
  where access_token_hash = p_access_token_hash for update;
  update public.quote_request_intakes set
    primary_language = case when p_data ? 'primary_language' then nullif(btrim(p_data->>'primary_language'), '') else v_intake.primary_language end,
    additional_languages = case when not (p_data ? 'additional_languages') then v_intake.additional_languages when p_data->'additional_languages' = 'null'::jsonb then null else array(select jsonb_array_elements_text(p_data->'additional_languages')) end,
    page_scope_details = case when p_data ? 'page_scope_details' then nullif(p_data->'page_scope_details', 'null'::jsonb) else v_intake.page_scope_details end,
    quote_form_details = case when p_data ? 'quote_form_details' then nullif(p_data->'quote_form_details', 'null'::jsonb) else v_intake.quote_form_details end,
    multilingual_details = case when p_data ? 'multilingual_details' then nullif(p_data->'multilingual_details', 'null'::jsonb) else v_intake.multilingual_details end,
    download_details = case when p_data ? 'download_details' then nullif(p_data->'download_details', 'null'::jsonb) else v_intake.download_details end,
    content_media_details = case when p_data ? 'content_media_details' then nullif(p_data->'content_media_details', 'null'::jsonb) else v_intake.content_media_details end,
    newsletter_details = case when p_data ? 'newsletter_details' then nullif(p_data->'newsletter_details', 'null'::jsonb) else v_intake.newsletter_details end,
    hosting_maintenance_details = case when p_data ? 'hosting_maintenance_details' then nullif(p_data->'hosting_maintenance_details', 'null'::jsonb) else v_intake.hosting_maintenance_details end,
    deadline_details = case when p_data ? 'deadline_details' then nullif(p_data->'deadline_details', 'null'::jsonb) else v_intake.deadline_details end,
    seo_details = case when p_data ? 'seo_details' then nullif(p_data->'seo_details', 'null'::jsonb) else v_intake.seo_details end,
    budget_update_category_scheme = case when p_data ? 'budget_update_category_scheme' then nullif(p_data->>'budget_update_category_scheme', '') else v_intake.budget_update_category_scheme end,
    budget_update_category_code = case when p_data ? 'budget_update_category_code' then nullif(p_data->>'budget_update_category_code', '') else v_intake.budget_update_category_code end,
    selected_package_definition_id = v_package_id
  where id = v_intake.id returning * into v_intake;

  select * into v_request from public.quote_requests
  where id = v_intake.quote_request_id;
  if v_intake.budget_update_category is not null then
    v_budget_label := v_intake.budget_update_category;
    v_budget_scheme := v_intake.budget_update_category_scheme;
    v_budget_code := v_intake.budget_update_category_code;
  else
    v_budget_label := v_request.budget;
    v_budget_scheme := v_request.budget_category_scheme;
    v_budget_code := v_request.budget_category_code;
  end if;
  v_budget_evaluation := p_budget_guard_snapshot->'budgetEvaluation';
  if not public.is_valid_pricing_budget_evaluation_v2(v_budget_evaluation)
     or v_budget_evaluation->>'originalLabel' is distinct from v_budget_label
     or (
       v_budget_evaluation->>'evidenceProvenance' in ('budget_guard_v1', 'budget_guard_v2')
       and (
         v_budget_scheme is distinct from v_budget_evaluation->>'evidenceProvenance'
         or v_budget_code is null
         or v_budget_evaluation->>'categoryScheme' is distinct from v_budget_scheme
         or v_budget_evaluation->>'categoryCode' is distinct from v_budget_code
       )
     )
     or (
       v_budget_evaluation->>'evidenceProvenance' = 'legacy_label'
       and (
         v_budget_scheme is not null or v_budget_code is not null
         or v_budget_evaluation->'categoryScheme' <> 'null'::jsonb
         or v_budget_evaluation->'categoryCode' <> 'null'::jsonb
       )
     ) then
    raise exception using errcode = '22023', message = 'PRICING_SNAPSHOT_BUDGET_MISMATCH';
  end if;

  insert into public.quote_request_pricing_snapshots (
    intake_id, snapshot_contract_version, config_version, config_hash,
    normalized_evidence, calculation, package_advice, budget_evaluation,
    package_definition
  ) values (
    v_intake.id, 3, p_budget_guard_snapshot->>'pricingConfigVersion',
    p_budget_guard_snapshot->>'pricingConfigHash',
    p_budget_guard_snapshot->'normalizedScope', p_budget_guard_snapshot->'calculation',
    p_budget_guard_snapshot->'packageAdvice', p_budget_guard_snapshot->'budgetEvaluation',
    p_budget_guard_snapshot->'packageDefinition'
  ) returning * into v_snapshot;

  insert into public.quote_request_pricing_snapshot_integrity (
    snapshot_id, algorithm_version, key_id, mac
  ) values (
    v_snapshot.id, p_pricing_snapshot_integrity->>'algorithmVersion',
    p_pricing_snapshot_integrity->>'keyId', p_pricing_snapshot_integrity->>'mac'
  );

  return query select v_result.outcome, v_result.intake_status,
    v_intake.started_at, v_intake.submitted_at, v_intake.updated_at,
    v_result.notification_job_id, v_result.notification_job_status,
    jsonb_build_object(
      'snapshotContractVersion', 3,
      'pricingConfigVersion', v_snapshot.config_version,
      'pricingConfigHash', v_snapshot.config_hash,
      'normalizedScope', v_snapshot.normalized_evidence,
      'calculation', v_snapshot.calculation,
      'packageAdvice', v_snapshot.package_advice,
      'budgetEvaluation', v_snapshot.budget_evaluation,
      'packageDefinition', v_snapshot.package_definition,
      'createdAt', v_snapshot.created_at
    );
end;
$$;
