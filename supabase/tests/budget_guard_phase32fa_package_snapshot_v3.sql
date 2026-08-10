begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(28);

select has_column('public', 'quote_request_intakes', 'selected_package_definition_id', 'durable package evidence exists');
select has_column('public', 'quote_request_pricing_snapshots', 'package_definition', 'snapshot v3 package definition exists');
select has_function('public', 'is_strict_pricing_snapshot_v3', array['smallint','text','text','jsonb','jsonb','jsonb','jsonb','jsonb'], 'v3 semantic validator exists');
select has_function('public', 'update_quote_request_intake_v5', array['text','text','jsonb','text','timestamp with time zone','jsonb','jsonb'], 'v5 submit boundary exists');
select has_function('public', 'inspect_quote_request_intake_details_v4', array['text'], 'package-aware intake inspection exists');
select has_function('public', 'inspect_customer_pricing_read_v3', array['text'], 'customer v3 pricing projection exists');
select has_function('public', 'inspect_admin_pricing_read_v3', array['text'], 'admin v3 pricing projection exists');

select ok(not has_function_privilege('anon', 'public.update_quote_request_intake_v5(text,text,jsonb,text,timestamp with time zone,jsonb,jsonb)', 'execute'), 'anon cannot submit authoritative v3');
select ok(not has_function_privilege('authenticated', 'public.inspect_customer_pricing_read_v3(text)', 'execute'), 'authenticated cannot bypass Edge customer read');
select ok(has_function_privilege('service_role', 'public.update_quote_request_intake_v5(text,text,jsonb,text,timestamp with time zone,jsonb,jsonb)', 'execute'), 'service role can execute v5 submit');
select ok(has_function_privilege('service_role', 'public.inspect_customer_pricing_read_v3(text)', 'execute'), 'service role can execute customer v3 source');

create temporary table phase32fa_fixture as
select
  '{
    "standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl",
    "additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]
  }'::jsonb as normalized_scope,
  '{
    "basis":"package_floor","currency":"EUR","vatBasis":"exclusive",
    "knownMinimumMinor":320000,"containsFromPricing":true,
    "manualReviewRequired":false,"manualReasons":[],
    "appliedRules":[{"ruleId":"professional_v1_floor","mode":"from",
      "amountMinor":320000,"quantity":1,"knownMinimumContributionMinor":320000}]
  }'::jsonb as calculation,
  '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}'::jsonb as package_advice,
  '{
    "contractVersion":2,"evidenceProvenance":"budget_guard_v1",
    "categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive",
    "originalLabel":"EUR 3.200 t/m EUR 6.000",
    "status":"possibly_compatible_with_category","outsideBudgetWishes":false
  }'::jsonb as budget_evaluation,
  '{
    "id":"professional_v1","version":1,"label":"Professional","priceMode":"from",
    "floorMinor":320000,"standardPageLimit":12,"includedCorrectionRounds":2,
    "entitlementSetId":"normal_web_v1","entitlements":[
      "responsive_design","technical_foundation","navigation","browser_compatibility",
      "technical_seo_base","testing_and_delivery","standard_contact_form","social_links",
      "google_maps","whatsapp","normal_gallery_reviews","public_downloads",
      "supplied_content_media_processing","normal_ai_image_support","primary_language"
    ]
  }'::jsonb as package_definition;

select ok(public.is_strict_pricing_snapshot_v3(
  3::smallint, '2.0.0', repeat('a',64), normalized_scope, calculation,
  package_advice, budget_evaluation, package_definition
), 'canonical Professional v3 is valid') from phase32fa_fixture;

select ok(not public.is_strict_pricing_snapshot_v3(
  3::smallint, '2.0.0', repeat('a',64), normalized_scope, calculation,
  package_advice, budget_evaluation,
  jsonb_set(package_definition, '{floorMinor}', '180000'::jsonb)
), 'tampered package floor is rejected') from phase32fa_fixture;

select ok(not public.is_strict_pricing_snapshot_v3(
  3::smallint, '2.0.0', repeat('a',64), normalized_scope,
  jsonb_set(calculation, '{appliedRules,0,ruleId}', '"starter_floor"'::jsonb),
  package_advice, budget_evaluation, package_definition
), 'Starter floor injection into Professional is rejected') from phase32fa_fixture;

select ok(not public.is_strict_pricing_snapshot_v3(
  3::smallint, '2.0.0', repeat('a',64),
  jsonb_set(normalized_scope, '{standardPageCount}', '13'::jsonb),
  calculation, package_advice, budget_evaluation, package_definition
), 'page evidence mismatch is rejected') from phase32fa_fixture;

select throws_ok(
  $$insert into public.quote_request_intakes (
    quote_request_id, access_token_hash, access_token_expires_at,
    selected_package_definition_id
  ) values (
    gen_random_uuid(), repeat('9',64), clock_timestamp() + interval '1 day', 'professional'
  )$$,
  '23514',
  'new row for relation "quote_request_intakes" violates check constraint "quote_request_intakes_package_definition_valid"',
  'invalid package is rejected before relational persistence'
);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, budget_category_scheme, budget_category_code
) values (
  '32fa0000-0000-4000-8000-000000000001', 'Package v3',
  'package-v3@example.test', 'business', 'EUR 3.200 t/m EUR 6.000',
  'flexible', 'Package v3 fixture', true, 'approved',
  'budget_guard_v1', '3200_to_6000_inclusive'
), (
  '32fa0000-0000-4000-8000-000000000002', 'Budget mismatch',
  'budget-mismatch@example.test', 'business', 'Meer dan EUR 6.000',
  'flexible', 'Budget mismatch fixture', true, 'approved',
  'budget_guard_v1', 'above_6000'
);

insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at,
  status, started_at, submitted_at, confirmation,
  admin_access_token_hash, admin_access_token_expires_at,
  selected_package_definition_id
) values (
  '32fa1000-0000-4000-8000-000000000001',
  '32fa0000-0000-4000-8000-000000000001', repeat('1',64),
  clock_timestamp() + interval '1 day', 'submitted', clock_timestamp(),
  clock_timestamp(), true, repeat('a',64), clock_timestamp() + interval '1 day',
  'professional_v1'
), (
  '32fa1000-0000-4000-8000-000000000002',
  '32fa0000-0000-4000-8000-000000000002', repeat('2',64),
  clock_timestamp() + interval '1 day', 'invited', null, null, false,
  null, null, null
);

select is(
  (select selected_package_definition_id from public.quote_request_intakes where id = '32fa1000-0000-4000-8000-000000000001'),
  'professional_v1',
  'valid package evidence persists'
);

select throws_matching(
  $$update public.quote_request_intakes set selected_package_definition_id = 'custom' where id = '32fa1000-0000-4000-8000-000000000001'$$,
  'quote_request_intakes_package_definition_valid',
  'unknown package IDs are rejected by constraint'
);

insert into public.quote_request_pricing_snapshots (
  id, intake_id, snapshot_contract_version, config_version, config_hash,
  normalized_evidence, calculation, package_advice, budget_evaluation,
  package_definition
)
select '32fa2000-0000-4000-8000-000000000001',
  '32fa1000-0000-4000-8000-000000000001', 3, '2.0.0', repeat('a',64),
  normalized_scope, calculation, package_advice, budget_evaluation,
  package_definition
from phase32fa_fixture;

insert into public.quote_request_pricing_snapshot_integrity (
  snapshot_id, algorithm_version, key_id, mac
) values (
  '32fa2000-0000-4000-8000-000000000001',
  'hmac-sha256-v1', 'v1', repeat('b',64)
);

select is((select snapshot_contract_version from public.inspect_customer_pricing_read_v3(repeat('1',64))), 3::smallint, 'customer projection reads v3');
select is((select package_definition->>'id' from public.inspect_customer_pricing_read_v3(repeat('1',64))), 'professional_v1', 'customer projection receives authoritative package');
select is((select calculation_basis from public.inspect_customer_pricing_read_v3(repeat('1',64))), 'package_floor', 'customer projection receives package basis');
select is((select package_definition->>'id' from public.inspect_admin_pricing_read_v3(repeat('a',64))), 'professional_v1', 'admin projection receives package operations');
select is((select integrity_snapshot->'packageDefinition'->>'id' from public.inspect_customer_pricing_read_v3(repeat('1',64))), 'professional_v1', 'integrity root includes package definition');

create function pg_temp.raise_package_mismatch()
returns void
language plpgsql
as $$
declare
  fixture record;
begin
  select * into fixture from phase32fa_fixture;
  perform * from public.update_quote_request_intake_v5(
    repeat('f',64), 'submit',
    '{"selected_package_definition_id":"starter_v1"}'::jsonb,
    repeat('c',64), clock_timestamp() + interval '1 day',
    jsonb_build_object(
      'snapshotContractVersion',3,'pricingConfigVersion','2.0.0',
      'pricingConfigHash',repeat('a',64),'normalizedScope',fixture.normalized_scope,
      'calculation',fixture.calculation,'packageAdvice',fixture.package_advice,
      'budgetEvaluation',fixture.budget_evaluation,
      'packageDefinition',fixture.package_definition
    ),
    '{"algorithmVersion":"hmac-sha256-v1","keyId":"v1","mac":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}'::jsonb
  );
end;
$$;

select throws_matching(
  $$select pg_temp.raise_package_mismatch()$$,
  'PRICING_SNAPSHOT_PACKAGE_MISMATCH',
  'submit rejects package evidence and snapshot mismatch'
);

create function pg_temp.raise_budget_mismatch()
returns void
language plpgsql
as $$
declare
  fixture record;
begin
  select * into fixture from phase32fa_fixture;
  perform * from public.update_quote_request_intake_v5(
    repeat('2',64), 'submit',
    '{
      "business_description":"Complete package submit description",
      "target_audience":"Local businesses",
      "primary_conversion_goal":"Request a quote",
      "website_goals":["generate_leads"],"requested_pages":["home"],
      "requested_features":[],"design_styles":["modern"],
      "brand_status":"complete","logo_status":"available",
      "content_status":"complete","image_status":"sufficient",
      "domain_status":"has_domain","hosting_status":"has_hosting",
      "maintenance_interest":"no","seo_priority":"basic",
      "priorities":["usability"],"confirmation":true,
      "selected_package_definition_id":"professional_v1",
      "primary_language":"nl"
    }'::jsonb,
    repeat('d',64), clock_timestamp() + interval '1 day',
    jsonb_build_object(
      'snapshotContractVersion',3,'pricingConfigVersion','2.0.0',
      'pricingConfigHash',repeat('a',64),'normalizedScope',fixture.normalized_scope,
      'calculation',fixture.calculation,'packageAdvice',fixture.package_advice,
      'budgetEvaluation',fixture.budget_evaluation,
      'packageDefinition',fixture.package_definition
    ),
    '{"algorithmVersion":"hmac-sha256-v1","keyId":"v1","mac":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}'::jsonb
  );
end;
$$;

select throws_matching(
  $$select pg_temp.raise_budget_mismatch()$$,
  'PRICING_SNAPSHOT_BUDGET_MISMATCH',
  'submit rejects a structurally valid snapshot bound to another budget'
);
select is(
  (select status::text from public.quote_request_intakes where id = '32fa1000-0000-4000-8000-000000000002'),
  'invited',
  'budget mismatch rolls lifecycle mutation back'
);
select is(
  (select count(*)::integer from public.quote_request_pricing_snapshots where intake_id = '32fa1000-0000-4000-8000-000000000002'),
  0,
  'budget mismatch stores no snapshot'
);

select is((select count(*)::integer from public.quote_request_intakes where selected_package_definition_id is null), 1, 'missing package remains null legacy evidence');

select * from finish();
rollback;