begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(12);

select has_function(
  'public', 'get_pricing_snapshot_integrity_for_operator_v1', array['uuid'],
  'operator pricing snapshot integrity read RPC exists'
);
select is(
  pg_get_function_result(
    'public.get_pricing_snapshot_integrity_for_operator_v1(uuid)'::regprocedure
  ),
  'TABLE(algorithm_version text, key_id text, mac text)',
  'RPC returns exactly the three required integrity fields'
);
select ok(
  (select prosecdef and provolatile = 's'
   from pg_proc
   where oid = 'public.get_pricing_snapshot_integrity_for_operator_v1(uuid)'::regprocedure),
  'RPC is stable and SECURITY DEFINER'
);
select ok(
  (select proconfig @> array['search_path=public, pg_catalog']
   from pg_proc
   where oid = 'public.get_pricing_snapshot_integrity_for_operator_v1(uuid)'::regprocedure),
  'RPC pins an explicit safe search path'
);
select ok(
  not has_function_privilege(
    'anon', 'public.get_pricing_snapshot_integrity_for_operator_v1(uuid)', 'execute'
  ),
  'anon cannot execute the operator integrity RPC'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.get_pricing_snapshot_integrity_for_operator_v1(uuid)', 'execute'
  ),
  'authenticated cannot execute the operator integrity RPC'
);
select ok(
  has_function_privilege(
    'service_role', 'public.get_pricing_snapshot_integrity_for_operator_v1(uuid)', 'execute'
  ),
  'service role can execute the operator integrity RPC'
);
select ok(
  not has_table_privilege(
    'service_role', 'public.quote_request_pricing_snapshot_integrity', 'select'
  ),
  'service role retains no direct integrity table read privilege'
);
select ok(
  not has_table_privilege(
    'anon', 'public.quote_request_pricing_snapshot_integrity', 'select'
  ) and not has_table_privilege(
    'authenticated', 'public.quote_request_pricing_snapshot_integrity', 'select'
  ),
  'browser roles retain no direct integrity table read privilege'
);

create temporary table operator_integrity_fixture as
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

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, budget_category_scheme, budget_category_code
) values (
  'f3590000-0000-4000-8000-000000000001', 'Operator integrity fixture',
  'operator-integrity@example.test', 'business', 'EUR 3.200 t/m EUR 6.000',
  'flexible', 'Local operator integrity read fixture.', true, 'approved',
  'budget_guard_v1', '3200_to_6000_inclusive'
);

insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at, status,
  started_at, submitted_at, confirmation
) values (
  'f3591000-0000-4000-8000-000000000001',
  'f3590000-0000-4000-8000-000000000001', repeat('1', 64),
  clock_timestamp() + interval '1 day', 'submitted', clock_timestamp(),
  clock_timestamp(), true
);

insert into public.quote_request_pricing_snapshots (
  id, intake_id, snapshot_contract_version, config_version, config_hash,
  normalized_evidence, calculation, package_advice, budget_evaluation
)
select
  'f3592000-0000-4000-8000-000000000001'::uuid,
  'f3591000-0000-4000-8000-000000000001'::uuid,
  2, '1.0.0', repeat('a', 64), normalized_scope, calculation,
  package_advice, budget_evaluation
from operator_integrity_fixture;

insert into public.quote_request_pricing_snapshot_integrity (
  snapshot_id, algorithm_version, key_id, mac
) values (
  'f3592000-0000-4000-8000-000000000001',
  'hmac-sha256-v1', 'v1', repeat('c', 64)
);

select is(
  (select count(*)::integer
   from public.get_pricing_snapshot_integrity_for_operator_v1(
     'f3592999-0000-4000-8000-000000000099'
   )),
  0,
  'missing snapshot integrity returns no row'
);

set local role service_role;
select is(
  (select row_to_json(result)::jsonb
   from public.get_pricing_snapshot_integrity_for_operator_v1(
     'f3592000-0000-4000-8000-000000000001'
   ) as result),
  jsonb_build_object(
    'algorithm_version', 'hmac-sha256-v1',
    'key_id', 'v1',
    'mac', repeat('c', 64)
  ),
  'service-side route receives exactly the persisted integrity proof'
);
reset role;

select throws_ok(
  $$update public.quote_request_pricing_snapshot_integrity
    set mac = repeat('d', 64)
    where snapshot_id = 'f3592000-0000-4000-8000-000000000001'$$,
  '55000', 'PRICING_SNAPSHOT_IMMUTABLE',
  'integrity proof remains immutable'
);

select * from finish();
rollback;