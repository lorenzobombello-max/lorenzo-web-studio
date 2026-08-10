alter function public.is_strict_pricing_snapshot_v2(
  smallint, text, text, jsonb, jsonb, jsonb, jsonb
) rename to is_structurally_valid_pricing_snapshot_v2;

create function public.has_canonical_pricing_snapshot_v2_semantics(
  p_normalized_scope jsonb,
  p_calculation jsonb,
  p_package_advice jsonb
)
returns boolean
language plpgsql
stable
set search_path = public
as $$
declare
  v_item jsonb;
  v_rule_id text;
  v_mode text;
  v_page_count integer;
  v_manual_rule_count integer := 0;
  v_expected_manual_reason_count integer;
begin
  v_page_count := (p_normalized_scope->>'standardPageCount')::integer;

  if exists (
       select 1
       from jsonb_array_elements_text(p_normalized_scope->'standardPages') as page(value)
       where page.value not in (
         'home', 'about', 'services', 'portfolio', 'team', 'pricing', 'faq',
         'contact', 'reviews', 'blog', 'jobs', 'gallery', 'products'
       )
     )
     or jsonb_array_length(p_normalized_scope->'standardPages') <> (
       select count(distinct page.value)
       from jsonb_array_elements_text(p_normalized_scope->'standardPages') as page(value)
     )
     or (
       p_normalized_scope->'primaryLanguage' <> 'null'::jsonb
       and p_normalized_scope->>'primaryLanguage' not in ('nl', 'fr', 'en', 'de', 'it', 'es')
     )
     or exists (
       select 1
       from jsonb_array_elements_text(p_normalized_scope->'additionalLanguages') as language(value)
       where language.value not in ('nl', 'fr', 'en', 'de', 'it', 'es')
     )
     or jsonb_array_length(p_normalized_scope->'additionalLanguages') <> (
       select count(distinct language.value)
       from jsonb_array_elements_text(p_normalized_scope->'additionalLanguages') as language(value)
     )
     or exists (
       select 1
       from jsonb_array_elements_text(p_normalized_scope->'unknownLanguages') as language(value)
       where btrim(language.value) = ''
     )
     or jsonb_array_length(p_normalized_scope->'unknownLanguages') <> (
       select count(distinct language.value)
       from jsonb_array_elements_text(p_normalized_scope->'unknownLanguages') as language(value)
     )
     or exists (
       select 1
       from jsonb_array_elements_text(p_normalized_scope->'manualComponents') as component(value)
       where component.value not in (
         'customer_login', 'external_integration', 'secured_downloads',
         'professional_photography', 'unresolved_search', 'rush_review',
         'substantial_copywriting', 'exceptional_image_work',
         'paid_stock_handling', 'complex_gallery_scope',
         'complex_reviews_scope', 'complex_blog_scope', 'complex_jobs_scope',
         'other_page_scope', 'unknown_page_scope', 'newsletter_manual',
         'extensive_seo'
       )
     )
     or jsonb_array_length(p_normalized_scope->'manualComponents') <> (
       select count(distinct component.value)
       from jsonb_array_elements_text(p_normalized_scope->'manualComponents') as component(value)
     )
  then
    return false;
  end if;

  for v_item in select value from jsonb_array_elements(p_normalized_scope->'modules') loop
    if not (
      (v_item->>'id' = 'shop' and v_item->>'classification' = 'manual')
      or (v_item->>'id' = 'booking' and v_item->>'classification' = 'manual')
      or (v_item->>'id' = 'forms' and v_item->>'classification' in ('contact', 'simple', 'extended', 'manual'))
      or (v_item->>'id' = 'multilingual' and v_item->>'classification' in ('normal', 'manual'))
      or (v_item->>'id' = 'content_media' and v_item->>'classification' in ('included', 'manual'))
      or (v_item->>'id' = 'hosting_maintenance' and v_item->>'classification' = 'manual')
      or (v_item->>'id' = 'seo' and v_item->>'classification' in ('included', 'manual'))
    ) then
      return false;
    end if;
  end loop;

  if jsonb_array_length(p_normalized_scope->'modules') <> (
       select count(distinct module.value->>'id')
       from jsonb_array_elements(p_normalized_scope->'modules') as module(value)
     )
  then
    return false;
  end if;

  for v_item in select value from jsonb_array_elements(p_calculation->'appliedRules') loop
    v_rule_id := v_item->>'ruleId';
    v_mode := v_item->>'mode';

    if (v_item->>'quantity')::numeric <= 0
       or not (
         (v_rule_id = 'starter_floor' and v_mode = 'from')
         or (v_rule_id = 'extra_standard_page' and v_mode = 'fixed')
         or (v_rule_id = 'extra_language' and v_mode = 'from')
         or (v_rule_id = 'contact_form' and v_mode = 'included')
         or (v_rule_id = 'simple_quote_form' and v_mode = 'fixed')
         or (v_rule_id = 'extended_quote_form' and v_mode = 'from')
         or (v_rule_id in (
           'complex_form_manual', 'shop_manual', 'booking_manual',
           'multilingual_manual', 'hosting_maintenance_manual', 'extensive_seo',
           'customer_login', 'external_integration', 'secured_downloads',
           'professional_photography', 'unresolved_search', 'rush_review',
           'substantial_copywriting', 'exceptional_image_work',
           'paid_stock_handling', 'complex_gallery_scope',
           'complex_reviews_scope', 'complex_blog_scope', 'complex_jobs_scope',
           'other_page_scope', 'unknown_page_scope', 'newsletter_manual'
         ) and v_mode = 'manual')
         or (v_rule_id in ('content_media_included', 'seo_included') and v_mode = 'included')
       )
       or (v_mode in ('included', 'manual') and (v_item->>'quantity')::numeric <> 1)
       or (v_rule_id in ('starter_floor', 'simple_quote_form', 'extended_quote_form')
         and (v_item->>'quantity')::numeric <> 1)
       or (v_mode in ('fixed', 'from') and (v_item->>'amountMinor')::numeric <= 0)
    then
      return false;
    end if;

    if v_mode = 'manual' then
      v_manual_rule_count := v_manual_rule_count + 1;
    end if;
  end loop;

  if jsonb_array_length(p_calculation->'appliedRules') <> (
       select count(distinct rule.value->>'ruleId')
       from jsonb_array_elements(p_calculation->'appliedRules') as rule(value)
     )
     or (
       select count(*)
       from jsonb_array_elements(p_calculation->'appliedRules') as rule(value)
       where rule.value->>'ruleId' = 'starter_floor'
     ) <> 1
  then
    return false;
  end if;

  if exists (
    with expected_rules(rule_id, quantity) as (
      select 'starter_floor'::text, 1::numeric
      union all
      select 'extra_standard_page', (v_page_count - 5)::numeric
      where v_page_count > 5
      union all
      select
        case
          when module.value->>'id' = 'shop' then 'shop_manual'
          when module.value->>'id' = 'booking' then 'booking_manual'
          when module.value->>'id' = 'forms' and module.value->>'classification' = 'contact' then 'contact_form'
          when module.value->>'id' = 'forms' and module.value->>'classification' = 'simple' then 'simple_quote_form'
          when module.value->>'id' = 'forms' and module.value->>'classification' = 'extended' then 'extended_quote_form'
          when module.value->>'id' = 'forms' then 'complex_form_manual'
          when module.value->>'id' = 'multilingual' and module.value->>'classification' = 'normal' then 'extra_language'
          when module.value->>'id' = 'multilingual' then 'multilingual_manual'
          when module.value->>'id' = 'content_media' and module.value->>'classification' = 'included' then 'content_media_included'
          when module.value->>'id' = 'hosting_maintenance' then 'hosting_maintenance_manual'
          when module.value->>'id' = 'seo' and module.value->>'classification' = 'included' then 'seo_included'
        end,
        case
          when module.value->>'id' = 'multilingual' and module.value->>'classification' = 'normal'
          then jsonb_array_length(p_normalized_scope->'additionalLanguages')::numeric
          else 1::numeric
        end
      from jsonb_array_elements(p_normalized_scope->'modules') as module(value)
      where not (
        module.value->>'id' in ('content_media', 'seo')
        and module.value->>'classification' = 'manual'
      )
      union all
      select component.value, 1::numeric
      from jsonb_array_elements_text(p_normalized_scope->'manualComponents') as component(value)
    ), actual_rules(rule_id, quantity) as (
      select rule.value->>'ruleId', (rule.value->>'quantity')::numeric
      from jsonb_array_elements(p_calculation->'appliedRules') as rule(value)
    ), differences as (
      (select * from expected_rules except select * from actual_rules)
      union all
      (select * from actual_rules except select * from expected_rules)
    )
    select 1 from differences
  ) then
    return false;
  end if;

  if v_page_count <= 5 then
    if p_package_advice->>'status' <> 'none'
       or p_package_advice->'reasons' <> '[]'::jsonb
    then return false; end if;
  elsif v_page_count <= 12 then
    if p_package_advice->>'status' <> 'consider_professional'
       or p_package_advice->'reasons' <> '["standard_page_count_above_starter_scope"]'::jsonb
    then return false; end if;
  else
    if p_package_advice->>'status' <> 'manual_scope_review'
       or p_package_advice->'reasons' <> '["standard_page_count_above_professional_scope"]'::jsonb
    then return false; end if;
  end if;

  for v_item in select value from jsonb_array_elements(p_calculation->'manualReasons') loop
    v_rule_id := v_item #>> '{}';
    if v_rule_id = 'standard_page_count_above_professional_scope' then
      if v_page_count <= 12 then return false; end if;
    elsif not exists (
      select 1
      from jsonb_array_elements(p_calculation->'appliedRules') as rule(value)
      where rule.value->>'ruleId' = v_rule_id
        and rule.value->>'mode' = 'manual'
    ) then
      return false;
    end if;
  end loop;

  v_expected_manual_reason_count := v_manual_rule_count + case when v_page_count > 12 then 1 else 0 end;
  if jsonb_array_length(p_calculation->'manualReasons') <> v_expected_manual_reason_count then
    return false;
  end if;

  return true;
exception
  when others then
    return false;
end;
$$;

create function public.is_strict_pricing_snapshot_v2(
  p_snapshot_contract_version smallint,
  p_config_version text,
  p_config_hash text,
  p_normalized_scope jsonb,
  p_calculation jsonb,
  p_package_advice jsonb,
  p_budget_evaluation jsonb
)
returns boolean
language plpgsql
stable
set search_path = public
as $$
begin
  if not coalesce(public.is_structurally_valid_pricing_snapshot_v2(
    p_snapshot_contract_version,
    p_config_version,
    p_config_hash,
    p_normalized_scope,
    p_calculation,
    p_package_advice,
    p_budget_evaluation
  ), false) then
    return false;
  end if;

  return public.has_canonical_pricing_snapshot_v2_semantics(
    p_normalized_scope,
    p_calculation,
    p_package_advice
  );
exception
  when others then
    return false;
end;
$$;

comment on function public.is_structurally_valid_pricing_snapshot_v2(smallint, text, text, jsonb, jsonb, jsonb, jsonb) is
  'Fail-closed structural and cross-field integrity base retained from Phase 3.2C-FIX.';

comment on function public.has_canonical_pricing_snapshot_v2_semantics(jsonb, jsonb, jsonb) is
  'Versioned historical v2 contract adapter. It validates closed identifiers and semantic coherence without normalizing intake evidence or recalculating prices.';

comment on function public.is_strict_pricing_snapshot_v2(smallint, text, text, jsonb, jsonb, jsonb, jsonb) is
  'Shared fail-closed v2 disclosure boundary combining structural integrity with the closed historical snapshot grammar.';

revoke all
on function public.is_structurally_valid_pricing_snapshot_v2(smallint, text, text, jsonb, jsonb, jsonb, jsonb)
from public, anon, authenticated;

revoke all
on function public.has_canonical_pricing_snapshot_v2_semantics(jsonb, jsonb, jsonb)
from public, anon, authenticated;

revoke all
on function public.is_strict_pricing_snapshot_v2(smallint, text, text, jsonb, jsonb, jsonb, jsonb)
from public, anon, authenticated;

grant execute
on function public.is_structurally_valid_pricing_snapshot_v2(smallint, text, text, jsonb, jsonb, jsonb, jsonb)
to service_role;

grant execute
on function public.has_canonical_pricing_snapshot_v2_semantics(jsonb, jsonb, jsonb)
to service_role;

grant execute
on function public.is_strict_pricing_snapshot_v2(smallint, text, text, jsonb, jsonb, jsonb, jsonb)
to service_role;

create or replace function public.inspect_admin_pricing_read_v1(p_admin_access_token_hash text)
returns table (
  intake_status text,
  snapshot_present boolean,
  snapshot_contract_version smallint,
  snapshot_created_at timestamptz,
  config_version text,
  config_hash text,
  normalized_scope jsonb,
  calculation jsonb,
  package_advice jsonb,
  budget_evaluation jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    intake.status::text,
    snapshot.id is not null and validity.is_disclosable,
    case when validity.is_disclosable then snapshot.snapshot_contract_version end,
    case when validity.is_disclosable then snapshot.created_at end,
    case when validity.is_disclosable then snapshot.config_version end,
    case when validity.is_disclosable then snapshot.config_hash end,
    case when validity.is_disclosable then snapshot.normalized_evidence end,
    case when validity.is_disclosable then snapshot.calculation end,
    case when validity.is_disclosable then snapshot.package_advice end,
    case when validity.is_strict_v2 then snapshot.budget_evaluation end
  from public.quote_request_intakes as intake
  left join public.quote_request_pricing_snapshots as snapshot
    on snapshot.intake_id = intake.id
  cross join lateral (
    select
      coalesce(public.is_strict_pricing_snapshot_v2(
        snapshot.snapshot_contract_version,
        snapshot.config_version,
        snapshot.config_hash,
        snapshot.normalized_evidence,
        snapshot.calculation,
        snapshot.package_advice,
        snapshot.budget_evaluation
      ), false) as is_strict_v2,
      snapshot.snapshot_contract_version is null as is_historical_v1
  ) as contract
  cross join lateral (
    select
      contract.is_strict_v2,
      contract.is_strict_v2 or contract.is_historical_v1 as is_disclosable
  ) as validity
  where p_admin_access_token_hash ~ '^[0-9a-f]{64}$'
    and intake.admin_access_token_hash = p_admin_access_token_hash
    and intake.admin_access_token_expires_at > clock_timestamp()
    and intake.admin_access_token_revoked_at is null
    and intake.status = 'submitted'
    and intake.submitted_at is not null
  limit 1
$$;

comment on function public.inspect_admin_pricing_read_v1(text) is
  'Service-role-only admin projection. Strict v2 and historical v1 follow separate compatibility paths; the DTO parser fail-closes malformed v1 sections.';

revoke all
on function public.inspect_admin_pricing_read_v1(text)
from public, anon, authenticated;

grant execute
on function public.inspect_admin_pricing_read_v1(text)
to service_role;