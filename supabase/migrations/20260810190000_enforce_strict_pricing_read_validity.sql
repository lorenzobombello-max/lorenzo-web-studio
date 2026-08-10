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
declare
  v_item jsonb;
  v_mode text;
  v_quantity numeric;
  v_amount numeric;
  v_contribution numeric;
  v_known_minimum numeric;
  v_manual_reason_count integer;
  v_manual_rule_count integer := 0;
  v_from_rule_count integer := 0;
  v_provenance text;
  v_category_code text;
  v_status text;
  v_outside jsonb;
begin
  if p_snapshot_contract_version is distinct from 2
     or p_config_version is null
     or p_config_version !~ '^[0-9]+\.[0-9]+\.[0-9]+$'
     or p_config_hash is null
     or p_config_hash !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(p_normalized_scope) is distinct from 'object'
     or not (p_normalized_scope ?& array[
       'standardPages', 'standardPageCount', 'primaryLanguage',
       'additionalLanguages', 'unknownLanguages', 'modules', 'manualComponents'
     ])
     or exists (
       select 1 from jsonb_object_keys(p_normalized_scope) as supplied(key)
       where supplied.key <> all(array[
         'standardPages', 'standardPageCount', 'primaryLanguage',
         'additionalLanguages', 'unknownLanguages', 'modules', 'manualComponents'
       ])
     )
     or jsonb_typeof(p_normalized_scope->'standardPages') is distinct from 'array'
     or jsonb_typeof(p_normalized_scope->'standardPageCount') is distinct from 'number'
     or (p_normalized_scope->>'standardPageCount') !~ '^\d+$'
     or (p_normalized_scope->>'standardPageCount')::numeric > 9007199254740991
     or (p_normalized_scope->>'standardPageCount')::numeric <> jsonb_array_length(p_normalized_scope->'standardPages')
     or jsonb_typeof(p_normalized_scope->'primaryLanguage') not in ('string', 'null')
     or jsonb_typeof(p_normalized_scope->'additionalLanguages') is distinct from 'array'
     or jsonb_typeof(p_normalized_scope->'unknownLanguages') is distinct from 'array'
     or jsonb_typeof(p_normalized_scope->'modules') is distinct from 'array'
     or jsonb_typeof(p_normalized_scope->'manualComponents') is distinct from 'array'
  then
    return false;
  end if;

  if exists (
       select 1 from jsonb_array_elements(p_normalized_scope->'standardPages') as entry(value)
       where jsonb_typeof(entry.value) <> 'string'
     )
     or exists (
       select 1 from jsonb_array_elements(p_normalized_scope->'additionalLanguages') as entry(value)
       where jsonb_typeof(entry.value) <> 'string'
     )
     or exists (
       select 1 from jsonb_array_elements(p_normalized_scope->'unknownLanguages') as entry(value)
       where jsonb_typeof(entry.value) <> 'string'
     )
     or exists (
       select 1 from jsonb_array_elements(p_normalized_scope->'manualComponents') as entry(value)
       where jsonb_typeof(entry.value) <> 'string'
     )
  then
    return false;
  end if;

  for v_item in select value from jsonb_array_elements(p_normalized_scope->'modules') loop
    if jsonb_typeof(v_item) <> 'object'
       or not (v_item ?& array['id', 'classification', 'evidence'])
       or exists (
         select 1 from jsonb_object_keys(v_item) as supplied(key)
         where supplied.key <> all(array['id', 'classification', 'evidence'])
       )
       or jsonb_typeof(v_item->'id') <> 'string'
       or btrim(v_item->>'id') = ''
       or jsonb_typeof(v_item->'classification') <> 'string'
       or btrim(v_item->>'classification') = ''
       or jsonb_typeof(v_item->'evidence') <> 'array'
       or exists (
         select 1 from jsonb_array_elements(v_item->'evidence') as entry(value)
         where jsonb_typeof(entry.value) <> 'string'
       )
    then
      return false;
    end if;
  end loop;

  if jsonb_typeof(p_calculation) is distinct from 'object'
     or not (p_calculation ?& array[
       'basis', 'currency', 'vatBasis', 'knownMinimumMinor',
       'containsFromPricing', 'manualReviewRequired', 'manualReasons', 'appliedRules'
     ])
     or exists (
       select 1 from jsonb_object_keys(p_calculation) as supplied(key)
       where supplied.key <> all(array[
         'basis', 'currency', 'vatBasis', 'knownMinimumMinor',
         'containsFromPricing', 'manualReviewRequired', 'manualReasons', 'appliedRules'
       ])
     )
     or p_calculation->>'basis' <> 'starter_floor'
     or p_calculation->>'currency' <> 'EUR'
     or p_calculation->>'vatBasis' <> 'exclusive'
     or jsonb_typeof(p_calculation->'knownMinimumMinor') <> 'number'
     or (p_calculation->>'knownMinimumMinor') !~ '^\d+$'
     or (p_calculation->>'knownMinimumMinor')::numeric > 9007199254740991
     or jsonb_typeof(p_calculation->'containsFromPricing') <> 'boolean'
     or jsonb_typeof(p_calculation->'manualReviewRequired') <> 'boolean'
     or jsonb_typeof(p_calculation->'manualReasons') <> 'array'
     or jsonb_typeof(p_calculation->'appliedRules') <> 'array'
     or exists (
       select 1 from jsonb_array_elements(p_calculation->'manualReasons') as entry(value)
       where jsonb_typeof(entry.value) <> 'string' or btrim(entry.value #>> '{}') = ''
     )
     or (
       select count(*) from jsonb_array_elements(p_calculation->'manualReasons') as entry(value)
     ) <> (
       select count(distinct entry.value) from jsonb_array_elements(p_calculation->'manualReasons') as entry(value)
     )
  then
    return false;
  end if;

  v_known_minimum := (p_calculation->>'knownMinimumMinor')::numeric;
  v_manual_reason_count := jsonb_array_length(p_calculation->'manualReasons');

  for v_item in select value from jsonb_array_elements(p_calculation->'appliedRules') loop
    if jsonb_typeof(v_item) <> 'object'
       or not (v_item ?& array['ruleId', 'mode', 'quantity', 'knownMinimumContributionMinor'])
       or exists (
         select 1 from jsonb_object_keys(v_item) as supplied(key)
         where supplied.key <> all(array[
           'ruleId', 'mode', 'quantity', 'amountMinor', 'knownMinimumContributionMinor'
         ])
       )
       or jsonb_typeof(v_item->'ruleId') <> 'string'
       or btrim(v_item->>'ruleId') = ''
       or jsonb_typeof(v_item->'mode') <> 'string'
       or v_item->>'mode' not in ('included', 'fixed', 'from', 'manual')
       or jsonb_typeof(v_item->'quantity') <> 'number'
       or (v_item->>'quantity') !~ '^\d+$'
       or (v_item->>'quantity')::numeric > 9007199254740991
       or jsonb_typeof(v_item->'knownMinimumContributionMinor') <> 'number'
       or (v_item->>'knownMinimumContributionMinor') !~ '^\d+$'
       or (v_item->>'knownMinimumContributionMinor')::numeric > 9007199254740991
    then
      return false;
    end if;

    v_mode := v_item->>'mode';
    v_quantity := (v_item->>'quantity')::numeric;
    v_contribution := (v_item->>'knownMinimumContributionMinor')::numeric;
    if v_mode in ('fixed', 'from') then
      if not (v_item ? 'amountMinor')
         or jsonb_typeof(v_item->'amountMinor') <> 'number'
         or (v_item->>'amountMinor') !~ '^\d+$'
         or (v_item->>'amountMinor')::numeric > 9007199254740991
      then
        return false;
      end if;
      v_amount := (v_item->>'amountMinor')::numeric;
      if v_contribution <> v_amount * v_quantity
         or v_contribution > 9007199254740991
      then
        return false;
      end if;
    elsif v_item ? 'amountMinor' or v_contribution <> 0 then
      return false;
    end if;

    if v_mode = 'manual' then
      v_manual_rule_count := v_manual_rule_count + 1;
      if not (p_calculation->'manualReasons' @> jsonb_build_array(v_item->'ruleId')) then
        return false;
      end if;
    end if;
    if v_mode = 'from' then
      v_from_rule_count := v_from_rule_count + 1;
    end if;
  end loop;

  if (p_calculation->>'containsFromPricing')::boolean is distinct from (v_from_rule_count > 0)
     or (p_calculation->>'manualReviewRequired')::boolean is distinct from (v_manual_reason_count > 0)
     or v_manual_reason_count < v_manual_rule_count
     or v_known_minimum <> coalesce((
       select sum((entry.value->>'knownMinimumContributionMinor')::numeric)
       from jsonb_array_elements(p_calculation->'appliedRules') as entry(value)
     ), 0)
  then
    return false;
  end if;

  if jsonb_typeof(p_package_advice) is distinct from 'object'
     or not (p_package_advice ?& array['status', 'reasons', 'advisoryOnly', 'selectedPackage'])
     or exists (
       select 1 from jsonb_object_keys(p_package_advice) as supplied(key)
       where supplied.key <> all(array['status', 'reasons', 'advisoryOnly', 'selectedPackage'])
     )
     or p_package_advice->>'status' not in ('none', 'consider_professional', 'manual_scope_review')
     or jsonb_typeof(p_package_advice->'reasons') <> 'array'
     or exists (
       select 1 from jsonb_array_elements(p_package_advice->'reasons') as entry(value)
       where jsonb_typeof(entry.value) <> 'string' or btrim(entry.value #>> '{}') = ''
     )
     or p_package_advice->'advisoryOnly' <> 'true'::jsonb
     or p_package_advice->'selectedPackage' <> 'null'::jsonb
     or (p_package_advice->>'status' = 'none' and jsonb_array_length(p_package_advice->'reasons') <> 0)
     or (p_package_advice->>'status' <> 'none' and jsonb_array_length(p_package_advice->'reasons') = 0)
  then
    return false;
  end if;

  if jsonb_typeof(p_budget_evaluation) is distinct from 'object'
     or not (p_budget_evaluation ?& array[
       'contractVersion', 'evidenceProvenance', 'categoryScheme',
       'categoryCode', 'originalLabel', 'status', 'outsideBudgetWishes'
     ])
     or exists (
       select 1 from jsonb_object_keys(p_budget_evaluation) as supplied(key)
       where supplied.key <> all(array[
         'contractVersion', 'evidenceProvenance', 'categoryScheme',
         'categoryCode', 'originalLabel', 'status', 'outsideBudgetWishes'
       ])
     )
     or p_budget_evaluation->'contractVersion' <> '2'::jsonb
     or jsonb_typeof(p_budget_evaluation->'evidenceProvenance') <> 'string'
     or p_budget_evaluation->>'evidenceProvenance' not in ('budget_guard_v1', 'legacy_label', 'missing', 'ambiguous')
     or jsonb_typeof(p_budget_evaluation->'status') <> 'string'
     or p_budget_evaluation->>'status' not in (
       'below_starter_starting_price', 'known_minimum_exceeds_category_upper_bound',
       'possibly_compatible_with_category', 'unbounded_category_indeterminate',
       'legacy_category_not_safely_comparable', 'manual_review_required'
     )
     or jsonb_typeof(p_budget_evaluation->'outsideBudgetWishes') not in ('boolean', 'null')
  then
    return false;
  end if;

  v_provenance := p_budget_evaluation->>'evidenceProvenance';
  v_category_code := p_budget_evaluation->>'categoryCode';
  v_status := p_budget_evaluation->>'status';
  v_outside := p_budget_evaluation->'outsideBudgetWishes';

  if v_provenance = 'budget_guard_v1' then
    if p_budget_evaluation->'categoryScheme' <> '"budget_guard_v1"'::jsonb
       or jsonb_typeof(p_budget_evaluation->'categoryCode') <> 'string'
       or v_category_code not in ('below_1800', '1800_to_below_3200', '3200_to_6000_inclusive', 'above_6000')
       or jsonb_typeof(p_budget_evaluation->'originalLabel') <> 'string'
       or not (
         (v_category_code = 'below_1800' and p_budget_evaluation->>'originalLabel' = 'Minder dan EUR 1.800')
         or (v_category_code = '1800_to_below_3200' and p_budget_evaluation->>'originalLabel' = 'EUR 1.800 tot minder dan EUR 3.200')
         or (v_category_code = '3200_to_6000_inclusive' and p_budget_evaluation->>'originalLabel' = 'EUR 3.200 t/m EUR 6.000')
         or (v_category_code = 'above_6000' and p_budget_evaluation->>'originalLabel' = 'Meer dan EUR 6.000')
       )
    then
      return false;
    end if;

    if (p_calculation->>'manualReviewRequired')::boolean then
      if v_status <> 'manual_review_required' or v_outside <> 'null'::jsonb then return false; end if;
    elsif v_category_code = 'below_1800' then
      if v_status <> 'below_starter_starting_price' or v_outside <> 'true'::jsonb then return false; end if;
    elsif v_category_code = '1800_to_below_3200' then
      if (v_known_minimum > 319999) is distinct from (v_outside = 'true'::jsonb)
        or v_status <> (case when v_known_minimum > 319999 then 'known_minimum_exceeds_category_upper_bound' else 'possibly_compatible_with_category' end)
      then return false; end if;
    elsif v_category_code = '3200_to_6000_inclusive' then
      if (v_known_minimum > 600000) is distinct from (v_outside = 'true'::jsonb)
        or v_status <> (case when v_known_minimum > 600000 then 'known_minimum_exceeds_category_upper_bound' else 'possibly_compatible_with_category' end)
      then return false; end if;
    elsif v_status <> 'unbounded_category_indeterminate' or v_outside <> 'null'::jsonb then
      return false;
    end if;
  elsif v_provenance = 'legacy_label' then
    if p_budget_evaluation->'categoryScheme' <> 'null'::jsonb
       or p_budget_evaluation->'categoryCode' <> 'null'::jsonb
       or p_budget_evaluation->>'originalLabel' not in (
         'Tot EUR 1.500', 'EUR 1.500 - EUR 3.000',
         'EUR 3.000 - EUR 6.000', 'Meer dan EUR 6.000'
       )
       or v_status <> (case when (p_calculation->>'manualReviewRequired')::boolean then 'manual_review_required' else 'legacy_category_not_safely_comparable' end)
       or v_outside <> 'null'::jsonb
    then return false; end if;
  elsif v_provenance = 'missing' then
    if p_budget_evaluation->'categoryScheme' <> 'null'::jsonb
       or p_budget_evaluation->'categoryCode' <> 'null'::jsonb
       or p_budget_evaluation->'originalLabel' <> 'null'::jsonb
       or v_status <> 'manual_review_required'
       or v_outside <> 'null'::jsonb
    then return false; end if;
  else
    if p_budget_evaluation->'categoryScheme' <> 'null'::jsonb
       or p_budget_evaluation->'categoryCode' <> 'null'::jsonb
       or jsonb_typeof(p_budget_evaluation->'originalLabel') <> 'string'
       or btrim(p_budget_evaluation->>'originalLabel') = ''
       or v_status <> 'manual_review_required'
       or v_outside <> 'null'::jsonb
    then return false; end if;
  end if;

  return true;
exception
  when others then
    return false;
end;
$$;

comment on function public.is_strict_pricing_snapshot_v2(smallint, text, text, jsonb, jsonb, jsonb, jsonb) is
  'Single fail-closed strict validity boundary for historical pricing snapshot v2 disclosure. It validates stored data without recalculation or mutation.';

revoke all
on function public.is_strict_pricing_snapshot_v2(smallint, text, text, jsonb, jsonb, jsonb, jsonb)
from public, anon, authenticated;

grant execute
on function public.is_strict_pricing_snapshot_v2(smallint, text, text, jsonb, jsonb, jsonb, jsonb)
to service_role;

create or replace function public.inspect_customer_pricing_read_v1(p_access_token_hash text)
returns table (
  intake_status text,
  snapshot_present boolean,
  snapshot_contract_version smallint,
  calculation_basis text,
  currency text,
  vat_basis text,
  known_minimum_minor bigint,
  contains_from_pricing boolean,
  manual_review_required boolean,
  manual_reason_count integer,
  budget_contract_version smallint,
  evidence_provenance text,
  budget_status text,
  outside_budget_wishes boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    intake.status::text,
    snapshot.id is not null and validity.is_valid,
    case when validity.is_valid then snapshot.snapshot_contract_version end,
    case when validity.is_valid then snapshot.calculation->>'basis' end,
    case when validity.is_valid then snapshot.calculation->>'currency' end,
    case when validity.is_valid then snapshot.calculation->>'vatBasis' end,
    case when validity.is_valid then (snapshot.calculation->>'knownMinimumMinor')::bigint end,
    case when validity.is_valid then (snapshot.calculation->>'containsFromPricing')::boolean end,
    case when validity.is_valid then (snapshot.calculation->>'manualReviewRequired')::boolean end,
    case when validity.is_valid then jsonb_array_length(snapshot.calculation->'manualReasons') end,
    case when validity.is_valid then (snapshot.budget_evaluation->>'contractVersion')::smallint end,
    case when validity.is_valid then snapshot.budget_evaluation->>'evidenceProvenance' end,
    case when validity.is_valid then snapshot.budget_evaluation->>'status' end,
    case when validity.is_valid and jsonb_typeof(snapshot.budget_evaluation->'outsideBudgetWishes') = 'boolean'
      then (snapshot.budget_evaluation->>'outsideBudgetWishes')::boolean end
  from public.quote_request_intakes as intake
  left join public.quote_request_pricing_snapshots as snapshot
    on snapshot.intake_id = intake.id
  cross join lateral (
    select coalesce(public.is_strict_pricing_snapshot_v2(
      snapshot.snapshot_contract_version,
      snapshot.config_version,
      snapshot.config_hash,
      snapshot.normalized_evidence,
      snapshot.calculation,
      snapshot.package_advice,
      snapshot.budget_evaluation
    ), false) as is_valid
  ) as validity
  where p_access_token_hash ~ '^[0-9a-f]{64}$'
    and intake.access_token_hash = p_access_token_hash
    and intake.access_token_expires_at > clock_timestamp()
    and intake.access_token_revoked_at is null
    and intake.status in ('submitted', 'reviewed')
    and intake.submitted_at is not null
  limit 1
$$;

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
    snapshot.id is not null and validity.is_valid,
    case when validity.is_valid then snapshot.snapshot_contract_version end,
    case when validity.is_valid then snapshot.created_at end,
    case when validity.is_valid then snapshot.config_version end,
    case when validity.is_valid then snapshot.config_hash end,
    case when validity.is_valid then snapshot.normalized_evidence end,
    case when validity.is_valid then snapshot.calculation end,
    case when validity.is_valid then snapshot.package_advice end,
    case when validity.is_valid then snapshot.budget_evaluation end
  from public.quote_request_intakes as intake
  left join public.quote_request_pricing_snapshots as snapshot
    on snapshot.intake_id = intake.id
  cross join lateral (
    select coalesce(public.is_strict_pricing_snapshot_v2(
      snapshot.snapshot_contract_version,
      snapshot.config_version,
      snapshot.config_hash,
      snapshot.normalized_evidence,
      snapshot.calculation,
      snapshot.package_advice,
      snapshot.budget_evaluation
    ), false) as is_valid
  ) as validity
  where p_admin_access_token_hash ~ '^[0-9a-f]{64}$'
    and intake.admin_access_token_hash = p_admin_access_token_hash
    and intake.admin_access_token_expires_at > clock_timestamp()
    and intake.admin_access_token_revoked_at is null
    and intake.status = 'submitted'
    and intake.submitted_at is not null
  limit 1
$$;