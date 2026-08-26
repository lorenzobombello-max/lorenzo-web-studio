begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(24);

create temporary table fix3_fixture as
select
  '{
    "standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl",
    "additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]
  }'::jsonb as normalized_scope,
  '{
    "basis":"starter_floor","currency":"EUR","vatBasis":"exclusive",
    "knownMinimumMinor":180000,"containsFromPricing":true,
    "manualReviewRequired":false,"manualReasons":[],
    "appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":180000,
      "quantity":1,"knownMinimumContributionMinor":180000}]
  }'::jsonb as calculation,
  '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}'::jsonb as package_advice,
  '{
    "contractVersion":2,"evidenceProvenance":"budget_guard_v1",
    "categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive",
    "originalLabel":"EUR 3.200 t/m EUR 6.000",
    "status":"possibly_compatible_with_category","outsideBudgetWishes":false
  }'::jsonb as budget_evaluation;

create function pg_temp.fix3_valid(p_scope jsonb)
returns boolean
language sql
as $$
  select public.is_strict_pricing_snapshot_v2(
    2::smallint, '1.0.0', repeat('a', 64), p_scope,
    fixture.calculation, fixture.package_advice, fixture.budget_evaluation
  )
  from fix3_fixture as fixture
$$;

select ok(pg_temp.fix3_valid(normalized_scope), 'canonical producer scope remains valid')
from fix3_fixture;

select ok(not pg_temp.fix3_valid(jsonb_set(
  normalized_scope,
  '{modules}',
  '[{"id":"forms","classification":"contact","evidence":["invented_evidence"]}]'
)), 'invented module evidence is rejected')
from fix3_fixture;

select ok(not pg_temp.fix3_valid('{
  "standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl",
  "additionalLanguages":["nl"],"unknownLanguages":[],
  "modules":[{"id":"multilingual","classification":"normal",
    "evidence":["additional_languages","multilingual_details"]}],
  "manualComponents":[]
}'), 'primary language cannot be duplicated as an additional language');

select ok(not pg_temp.fix3_valid('{
  "standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl",
  "additionalLanguages":["fr"],"unknownLanguages":[],
  "modules":[{"id":"multilingual","classification":"normal",
    "evidence":["multilingual_details"]}],"manualComponents":[]
}'), 'multilingual evidence must match the additional language set');

select ok(not pg_temp.fix3_valid('{
  "standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl",
  "additionalLanguages":[],"unknownLanguages":[],
  "modules":[{"id":"seo","classification":"included","evidence":["content_media"]}],
  "manualComponents":[]
}'), 'cross-module evidence is rejected');

select ok(not pg_temp.fix3_valid('{
  "standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl",
  "additionalLanguages":[],"unknownLanguages":[],
  "modules":[{"id":"forms","classification":"contact","evidence":[]}],
  "manualComponents":[]
}'), 'empty module evidence is rejected');

select has_table(
  'public', 'quote_request_pricing_snapshot_integrity',
  'immutable producer proof table exists'
);
select ok(not has_table_privilege('anon', 'public.quote_request_pricing_snapshot_integrity', 'select'), 'anon cannot read proofs');
select ok(not has_table_privilege('authenticated', 'public.quote_request_pricing_snapshot_integrity', 'select'), 'authenticated cannot read proofs');
select ok(not has_table_privilege('service_role', 'public.quote_request_pricing_snapshot_integrity', 'select'), 'service role cannot bypass proof source RPCs');
select ok(not has_table_privilege('service_role', 'public.quote_request_pricing_snapshot_integrity', 'insert'), 'service role cannot attach a proof directly');
select ok(not has_function_privilege('service_role', 'public.update_quote_request_intake_v3(text,text,jsonb,text,timestamp with time zone,jsonb)', 'execute'), 'legacy v3 writer is revoked');
select ok(has_function_privilege('service_role', 'public.update_quote_request_intake_v4(text,text,jsonb,text,timestamp with time zone,jsonb,jsonb)', 'execute'), 'service role can execute only the v4 writer');
select ok(not has_function_privilege('service_role', 'public.inspect_customer_pricing_read_v1(text)', 'execute'), 'legacy customer source cannot bypass integrity verification');
select ok(not has_function_privilege('service_role', 'public.inspect_admin_pricing_read_v1(text)', 'execute'), 'legacy admin source cannot bypass integrity verification');
select ok(not has_function_privilege('anon', 'public.inspect_customer_pricing_read_v2(text)', 'execute'), 'anon cannot execute customer integrity source');
select ok(not has_function_privilege('authenticated', 'public.inspect_admin_pricing_read_v2(text)', 'execute'), 'authenticated cannot execute admin integrity source');

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, budget_category_scheme, budget_category_code
) values
  ('32c30000-0000-4000-8000-000000000001', 'FIX3 v2', 'fix3-v2@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'FIX3 v2 fixture', true, 'approved', 'budget_guard_v1', '3200_to_6000_inclusive'),
  ('32c30001-0000-4000-8000-000000000002', 'FIX3 v1', 'fix3-v1@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'FIX3 v1 fixture', true, 'approved', null, null);

insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at, status,
  started_at, submitted_at, confirmation, admin_access_token_hash,
  admin_access_token_expires_at
) values
  ('32c31000-0000-4000-8000-000000000001', '32c30000-0000-4000-8000-000000000001', repeat('1', 64), clock_timestamp() + interval '1 day', 'submitted', clock_timestamp(), clock_timestamp(), true, repeat('a', 64), clock_timestamp() + interval '1 day'),
  ('32c31000-0000-4000-8000-000000000002', '32c30001-0000-4000-8000-000000000002', repeat('2', 64), clock_timestamp() + interval '1 day', 'submitted', clock_timestamp(), clock_timestamp(), true, repeat('b', 64), clock_timestamp() + interval '1 day');

insert into public.quote_request_pricing_snapshots (
  id, intake_id, snapshot_contract_version, config_version, config_hash,
  normalized_evidence, calculation, package_advice, budget_evaluation
)
select
  '32c32000-0000-4000-8000-000000000001'::uuid,
  '32c31000-0000-4000-8000-000000000001'::uuid,
  2, '1.0.0', repeat('a', 64), normalized_scope, calculation,
  package_advice, budget_evaluation
from fix3_fixture
union all
select
  '32c32000-0000-4000-8000-000000000002'::uuid,
  '32c31000-0000-4000-8000-000000000002'::uuid,
  null, '1.0.0', repeat('b', 64), normalized_scope, calculation,
  package_advice,
  '{"categoryCode":"3200_to_6000_inclusive","status":"possibly_compatible_with_category","outsideBudgetWishes":[]}'::jsonb
from fix3_fixture;

select is((select snapshot_present from public.inspect_customer_pricing_read_v2(repeat('1', 64))), false, 'proofless v2 is unavailable to customer Edge source');
select is((select snapshot_present from public.inspect_admin_pricing_read_v2(repeat('a', 64))), false, 'proofless v2 is unavailable to admin Edge source');
select is((select snapshot_present from public.inspect_admin_pricing_read_v2(repeat('b', 64))), true, 'historical v1 remains available to admin compatibility path');
select is((select snapshot_contract_version from public.inspect_admin_pricing_read_v2(repeat('b', 64))), null::smallint, 'historical v1 contract marker is preserved');

insert into public.quote_request_pricing_snapshot_integrity (
  snapshot_id, algorithm_version, key_id, mac
) values (
  '32c32000-0000-4000-8000-000000000001',
  'hmac-sha256-v1', 'v1', repeat('c', 64)
);

select is((select known_minimum_minor from public.inspect_customer_pricing_read_v2(repeat('1', 64))), 180000::bigint, 'proof-bearing strict v2 amount reaches only the Edge integrity source');
select is((select integrity_metadata->>'keyId' from public.inspect_customer_pricing_read_v2(repeat('1', 64))), 'v1', 'Edge source receives versioned proof metadata');
select throws_ok(
  $$update public.quote_request_pricing_snapshot_integrity set mac = repeat('d', 64)$$,
  '55000',
  'PRICING_SNAPSHOT_IMMUTABLE',
  'producer proof cannot be replaced after insertion'
);

select * from finish();
rollback;