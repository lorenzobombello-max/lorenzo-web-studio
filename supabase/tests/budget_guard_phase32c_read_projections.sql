begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(47);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, budget_category_scheme, budget_category_code
) values
  ('320c0000-0000-4000-8000-000000000001', 'Automatic read', 'auto@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Automatic v2 read fixture.', true, 'approved', 'budget_guard_v1', '3200_to_6000_inclusive'),
  ('320c0001-0000-4000-8000-000000000002', 'Manual read', 'manual@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Manual v2 read fixture.', true, 'approved', 'budget_guard_v1', '3200_to_6000_inclusive'),
  ('320c0002-0000-4000-8000-000000000003', 'Historical read', 'v1@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'Historical v1 read fixture.', true, 'approved', null, null),
  ('320c0003-0000-4000-8000-000000000004', 'Missing snapshot', 'missing@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Missing snapshot fixture.', true, 'approved', 'budget_guard_v1', '3200_to_6000_inclusive'),
  ('320c0004-0000-4000-8000-000000000005', 'Draft read', 'draft@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Wrong lifecycle fixture.', true, 'approved', 'budget_guard_v1', '3200_to_6000_inclusive'),
  ('320c0005-0000-4000-8000-000000000006', 'Expired read', 'expired@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Expired capability fixture.', true, 'approved', 'budget_guard_v1', '3200_to_6000_inclusive'),
  ('320c0006-0000-4000-8000-000000000007', 'Revoked read', 'revoked@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Revoked capability fixture.', true, 'approved', 'budget_guard_v1', '3200_to_6000_inclusive'),
  ('320c0007-0000-4000-8000-000000000008', 'Malformed read', 'malformed@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Malformed historical fixture.', true, 'approved', 'budget_guard_v1', '3200_to_6000_inclusive');

insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at,
  access_token_revoked_at, status, started_at, submitted_at, confirmation,
  admin_access_token_hash, admin_access_token_expires_at,
  admin_access_token_revoked_at, created_at
) values
  ('320c1000-0000-4000-8000-000000000001', '320c0000-0000-4000-8000-000000000001', repeat('1', 64), clock_timestamp() + interval '1 day', null, 'submitted', clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour', true, repeat('a', 64), clock_timestamp() + interval '1 day', null, clock_timestamp() - interval '3 hours'),
  ('320c1000-0000-4000-8000-000000000002', '320c0001-0000-4000-8000-000000000002', repeat('2', 64), clock_timestamp() + interval '1 day', null, 'submitted', clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour', true, repeat('b', 64), clock_timestamp() + interval '1 day', null, clock_timestamp() - interval '3 hours'),
  ('320c1000-0000-4000-8000-000000000003', '320c0002-0000-4000-8000-000000000003', repeat('3', 64), clock_timestamp() + interval '1 day', null, 'submitted', clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour', true, repeat('c', 64), clock_timestamp() + interval '1 day', null, clock_timestamp() - interval '3 hours'),
  ('320c1000-0000-4000-8000-000000000004', '320c0003-0000-4000-8000-000000000004', repeat('4', 64), clock_timestamp() + interval '1 day', null, 'submitted', clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour', true, repeat('d', 64), clock_timestamp() + interval '1 day', null, clock_timestamp() - interval '3 hours'),
  ('320c1000-0000-4000-8000-000000000005', '320c0004-0000-4000-8000-000000000005', repeat('5', 64), clock_timestamp() + interval '1 day', null, 'in_progress', clock_timestamp() - interval '1 hour', null, false, null, null, null, clock_timestamp() - interval '2 hours'),
  ('320c1000-0000-4000-8000-000000000006', '320c0005-0000-4000-8000-000000000006', repeat('6', 64), clock_timestamp() - interval '1 minute', null, 'submitted', clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour', true, repeat('e', 64), clock_timestamp() - interval '1 minute', null, clock_timestamp() - interval '3 hours'),
  ('320c1000-0000-4000-8000-000000000007', '320c0006-0000-4000-8000-000000000007', repeat('7', 64), clock_timestamp() + interval '1 day', clock_timestamp() - interval '1 minute', 'submitted', clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour', true, repeat('f', 64), clock_timestamp() + interval '1 day', clock_timestamp() - interval '1 minute', clock_timestamp() - interval '3 hours'),
  ('320c1000-0000-4000-8000-000000000008', '320c0007-0000-4000-8000-000000000008', repeat('8', 64), clock_timestamp() + interval '1 day', null, 'submitted', clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour', true, repeat('0', 64), clock_timestamp() + interval '1 day', null, clock_timestamp() - interval '3 hours');

create temporary table phase32c_snapshots as
select
  '{
    "standardPages":["home"],
    "standardPageCount":1,
    "primaryLanguage":"nl",
    "additionalLanguages":[],
    "unknownLanguages":[],
    "modules":[],
    "manualComponents":[]
  }'::jsonb as normalized_scope,
  '{
    "standardPages":["home"],
    "standardPageCount":1,
    "primaryLanguage":"nl",
    "additionalLanguages":[],
    "unknownLanguages":[],
    "modules":[{
      "id":"shop",
      "classification":"manual",
      "evidence":["requested_features.shop"]
    }],
    "manualComponents":[]
  }'::jsonb as manual_normalized_scope,
  '{
    "basis":"starter_floor",
    "currency":"EUR",
    "vatBasis":"exclusive",
    "knownMinimumMinor":220000,
    "containsFromPricing":true,
    "manualReviewRequired":false,
    "manualReasons":[],
    "appliedRules":[{
      "ruleId":"starter_floor",
      "mode":"from",
      "amountMinor":220000,
      "quantity":1,
      "knownMinimumContributionMinor":220000
    }]
  }'::jsonb as automatic_calculation,
  '{
    "basis":"starter_floor",
    "currency":"EUR",
    "vatBasis":"exclusive",
    "knownMinimumMinor":180000,
    "containsFromPricing":true,
    "manualReviewRequired":true,
    "manualReasons":["shop_manual"],
    "appliedRules":[{
      "ruleId":"starter_floor",
      "mode":"from",
      "amountMinor":180000,
      "quantity":1,
      "knownMinimumContributionMinor":180000
    },{
      "ruleId":"shop_manual",
      "mode":"manual",
      "quantity":1,
      "knownMinimumContributionMinor":0
    }]
  }'::jsonb as manual_calculation,
  '{
    "status":"none",
    "reasons":[],
    "advisoryOnly":true,
    "selectedPackage":null
  }'::jsonb as package_advice,
  '{
    "contractVersion":2,
    "evidenceProvenance":"budget_guard_v1",
    "categoryScheme":"budget_guard_v1",
    "categoryCode":"3200_to_6000_inclusive",
    "originalLabel":"EUR 3.200 t/m EUR 6.000",
    "status":"possibly_compatible_with_category",
    "outsideBudgetWishes":false
  }'::jsonb as automatic_budget,
  '{
    "contractVersion":2,
    "evidenceProvenance":"budget_guard_v1",
    "categoryScheme":"budget_guard_v1",
    "categoryCode":"3200_to_6000_inclusive",
    "originalLabel":"EUR 3.200 t/m EUR 6.000",
    "status":"manual_review_required",
    "outsideBudgetWishes":null
  }'::jsonb as manual_budget;

insert into public.quote_request_pricing_snapshots (
  intake_id, snapshot_contract_version, config_version, config_hash,
  normalized_evidence, calculation, package_advice, budget_evaluation
)
select '320c1000-0000-4000-8000-000000000001'::uuid, 2, '1.0.0', repeat('a', 64), normalized_scope, automatic_calculation, package_advice, automatic_budget
from phase32c_snapshots
union all
select '320c1000-0000-4000-8000-000000000002'::uuid, 2, '1.0.0', repeat('b', 64), manual_normalized_scope, manual_calculation, package_advice, manual_budget
from phase32c_snapshots
union all
select '320c1000-0000-4000-8000-000000000003'::uuid, null, '1.0.0', repeat('c', 64), normalized_scope, automatic_calculation, package_advice,
  '{"categoryCode":"3200_to_6000_inclusive","status":"possibly_compatible_with_category","outsideBudgetWishes":[]}'::jsonb
from phase32c_snapshots
union all
select '320c1000-0000-4000-8000-000000000008'::uuid, 2, '1.0.0', repeat('d', 64), normalized_scope,
  jsonb_set(automatic_calculation, '{appliedRules}', '[42]'::jsonb), package_advice, automatic_budget
from phase32c_snapshots;

select has_function('public', 'inspect_customer_pricing_read_v1', array['text'], 'customer pricing read projection exists');
select has_function('public', 'inspect_admin_pricing_read_v1', array['text'], 'admin pricing read projection exists');
select ok(not has_function_privilege('anon', 'public.inspect_customer_pricing_read_v1(text)', 'execute'), 'anon cannot execute customer pricing projection');
select ok(not has_function_privilege('authenticated', 'public.inspect_customer_pricing_read_v1(text)', 'execute'), 'authenticated cannot execute customer pricing projection');
select ok(not has_function_privilege('service_role', 'public.inspect_customer_pricing_read_v1(text)', 'execute'), 'service role cannot bypass integrity through legacy customer projection');
select ok(not has_function_privilege('anon', 'public.inspect_admin_pricing_read_v1(text)', 'execute'), 'anon cannot execute admin pricing projection');
select ok(not has_function_privilege('authenticated', 'public.inspect_admin_pricing_read_v1(text)', 'execute'), 'authenticated cannot execute admin pricing projection');
select ok(not has_function_privilege('service_role', 'public.inspect_admin_pricing_read_v1(text)', 'execute'), 'service role cannot bypass integrity through legacy admin projection');
select ok(not has_function_privilege('anon', 'public.inspect_quote_request_intake_details_v3(text)', 'execute'), 'anon cannot execute full customer snapshot RPC');
select ok(not has_function_privilege('authenticated', 'public.inspect_submitted_intake_for_admin_v3(text)', 'execute'), 'authenticated cannot execute full admin snapshot RPC');
select ok(not has_function_privilege('anon', 'public.is_strict_pricing_snapshot_v2(smallint,text,text,jsonb,jsonb,jsonb,jsonb)', 'execute'), 'anon cannot execute strict snapshot predicate');
select ok(not has_function_privilege('authenticated', 'public.is_strict_pricing_snapshot_v2(smallint,text,text,jsonb,jsonb,jsonb,jsonb)', 'execute'), 'authenticated cannot execute strict snapshot predicate');
select ok(has_function_privilege('service_role', 'public.is_strict_pricing_snapshot_v2(smallint,text,text,jsonb,jsonb,jsonb,jsonb)', 'execute'), 'service role can execute strict snapshot predicate');

select is((select intake_status from public.inspect_customer_pricing_read_v1(repeat('1', 64))), 'submitted', 'valid customer capability returns submitted lifecycle');
select is((select known_minimum_minor from public.inspect_customer_pricing_read_v1(repeat('1', 64))), 220000::bigint, 'customer source returns exact historical amount');
select is((select snapshot_contract_version from public.inspect_customer_pricing_read_v1(repeat('1', 64))), 2::smallint, 'customer source identifies snapshot v2');
select is((select outside_budget_wishes from public.inspect_customer_pricing_read_v1(repeat('1', 64))), false, 'customer source preserves false tri-state');
select ok(position('config_hash' in pg_get_function_result('public.inspect_customer_pricing_read_v1(text)'::regprocedure)) = 0, 'customer source schema excludes config hash');
select ok(position('normalized_scope' in pg_get_function_result('public.inspect_customer_pricing_read_v1(text)'::regprocedure)) = 0, 'customer source schema excludes normalized scope');
select is((select manual_review_required from public.inspect_customer_pricing_read_v1(repeat('2', 64))), true, 'customer source preserves manual-review flag');
select is((select manual_reason_count from public.inspect_customer_pricing_read_v1(repeat('2', 64))), 1, 'customer source returns reason count without technical reasons');
select is((select count(*)::integer from public.inspect_customer_pricing_read_v1(repeat('5', 64))), 0, 'customer projection rejects wrong lifecycle');
select is((select count(*)::integer from public.inspect_customer_pricing_read_v1(repeat('6', 64))), 0, 'expired customer capability returns no row');
select is((select count(*)::integer from public.inspect_customer_pricing_read_v1(repeat('7', 64))), 0, 'revoked customer capability returns no row');
select is((select count(*)::integer from public.inspect_customer_pricing_read_v1(repeat('9', 64))), 0, 'invalid customer capability returns no row');
select is((select snapshot_present from public.inspect_customer_pricing_read_v1(repeat('4', 64))), false, 'submitted intake without snapshot returns explicit missing state');
select is((select snapshot_contract_version from public.inspect_customer_pricing_read_v1(repeat('3', 64))), null::smallint, 'historical v1 remains version null');
select is((select snapshot_present from public.inspect_customer_pricing_read_v1(repeat('3', 64))), false, 'customer suppresses historical v1 snapshots');

select is((select snapshot_present from public.inspect_admin_pricing_read_v1(repeat('a', 64))), true, 'valid admin capability returns historical pricing source');
select is((select budget_evaluation->'outsideBudgetWishes' from public.inspect_admin_pricing_read_v1(repeat('a', 64))), 'false'::jsonb, 'admin source preserves exact false tri-state');
select is((select budget_evaluation->>'evidenceProvenance' from public.inspect_admin_pricing_read_v1(repeat('a', 64))), 'budget_guard_v1', 'admin source preserves exact provenance');
select is((select config_hash from public.inspect_admin_pricing_read_v1(repeat('a', 64))), repeat('a', 64), 'admin source returns approved audit hash');
select is((select count(*)::integer from public.inspect_admin_pricing_read_v1(repeat('1', 64))), 0, 'customer capability hash cannot read admin source');
select is((select count(*)::integer from public.inspect_customer_pricing_read_v1(repeat('a', 64))), 0, 'admin capability hash cannot read customer source');
select is((select count(*)::integer from public.inspect_admin_pricing_read_v1(repeat('8', 64))), 0, 'invalid admin capability returns no row');
select is((select count(*)::integer from public.inspect_admin_pricing_read_v1(repeat('e', 64))), 0, 'expired admin capability returns no row');
select is((select count(*)::integer from public.inspect_admin_pricing_read_v1(repeat('f', 64))), 0, 'revoked admin capability returns no row');
select throws_ok(
  $$
    update public.quote_request_intakes
    set admin_access_token_hash = repeat('9', 64),
        admin_access_token_expires_at = clock_timestamp() + interval '1 day'
    where id = '320c1000-0000-4000-8000-000000000005'
  $$,
  '23514',
  'new row for relation "quote_request_intakes" violates check constraint "quote_request_intakes_admin_access_submission_valid"',
  'wrong lifecycle cannot receive an admin capability'
);
select is((select count(*)::integer from public.inspect_admin_pricing_read_v1(repeat('a', 64)) where config_hash = repeat('b', 64)), 0, 'admin capability remains bound to its own dossier');
select ok(position('intake_id' in pg_get_function_result('public.inspect_admin_pricing_read_v1(text)'::regprocedure)) = 0, 'admin source schema excludes intake ID');
select ok(
  position('intake.status = ''submitted''' in lower(pg_get_functiondef('public.inspect_admin_pricing_read_v1(text)'::regprocedure))) > 0
    and position('intake.submitted_at is not null' in lower(pg_get_functiondef('public.inspect_admin_pricing_read_v1(text)'::regprocedure))) > 0,
  'admin projection enforces submitted lifecycle'
);
select ok(position('access_token' in pg_get_function_result('public.inspect_admin_pricing_read_v1(text)'::regprocedure)) = 0, 'admin source schema excludes capability metadata');
select is((select snapshot_present from public.inspect_admin_pricing_read_v1(repeat('c', 64))), true, 'admin projection forwards historical v1 to the strict DTO parser');
select is((select snapshot_contract_version from public.inspect_admin_pricing_read_v1(repeat('c', 64))), null::smallint, 'admin projection preserves the historical v1 contract marker');
select is((select budget_evaluation from public.inspect_admin_pricing_read_v1(repeat('c', 64))), null::jsonb, 'admin v1 compatibility source omits unsupported budget evaluation');

select is((select snapshot_present from public.inspect_customer_pricing_read_v1(repeat('8', 64))), false, 'customer suppresses malformed nested v2 snapshot');
select is((select snapshot_present from public.inspect_admin_pricing_read_v1(repeat('0', 64))), false, 'admin suppresses the same malformed nested v2 snapshot');

select * from finish();
rollback;