begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(51);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, budget_category_scheme, budget_category_code
) values
  ('31000000-0000-0000-0000-000000000001', 'Historical v1', 'v1@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'Historical v1 snapshot fixture.', true, 'approved', null, null),
  ('31000000-0000-0000-0000-000000000002', 'Budget Guard v2', 'v2@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Budget Guard contract v2 fixture.', true, 'approved', 'budget_guard_v1', '3200_to_6000_inclusive'),
  ('31000000-0000-0000-0000-000000000003', 'Legacy v2', 'legacy@example.test', 'business', 'EUR 1.500 - EUR 3.000', 'flexible', 'Legacy provenance contract v2 fixture.', true, 'approved', null, null),
  ('31000000-0000-0000-0000-000000000004', 'Invalid v2', 'invalid@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Invalid contract v2 rollback fixture.', true, 'approved', 'budget_guard_v1', '3200_to_6000_inclusive'),
  ('31000000-0000-0000-0000-000000000005', 'Below starter v2', 'below@example.test', 'business', 'Minder dan EUR 1.800', 'flexible', 'Tri-state true fixture.', true, 'approved', 'budget_guard_v1', 'below_1800'),
  ('31000000-0000-0000-0000-000000000006', 'Incomplete v2', 'incomplete@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Forced submit rollback fixture.', true, 'approved', 'budget_guard_v1', '3200_to_6000_inclusive');

insert into public.quote_request_intakes (
  quote_request_id, access_token_hash, access_token_expires_at,
  status, started_at, submitted_at, confirmation, budget_update_category,
  created_at
) values
  ('31000000-0000-0000-0000-000000000001', repeat('1', 64), clock_timestamp() + interval '1 day', 'submitted', clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour', true, 'EUR 3.000 - EUR 6.000', clock_timestamp() - interval '3 hours'),
  ('31000000-0000-0000-0000-000000000002', repeat('2', 64), clock_timestamp() + interval '1 day', 'invited', null, null, false, null, clock_timestamp()),
  ('31000000-0000-0000-0000-000000000003', repeat('3', 64), clock_timestamp() + interval '1 day', 'invited', null, null, false, null, clock_timestamp()),
  ('31000000-0000-0000-0000-000000000004', repeat('4', 64), clock_timestamp() + interval '1 day', 'invited', null, null, false, null, clock_timestamp()),
  ('31000000-0000-0000-0000-000000000005', repeat('5', 64), clock_timestamp() + interval '1 day', 'invited', null, null, false, null, clock_timestamp()),
  ('31000000-0000-0000-0000-000000000006', repeat('6', 64), clock_timestamp() + interval '1 day', 'invited', null, null, false, null, clock_timestamp());

create temporary table phase31b_fixture as
select
  '{
    "business_description":"A complete business description",
    "target_audience":"Small businesses",
    "primary_conversion_goal":"Request a quote",
    "website_goals":["leads"],
    "requested_pages":["home"],
    "requested_features":[],
    "design_styles":["modern"],
    "brand_status":"complete",
    "logo_status":"available",
    "content_status":"complete",
    "image_status":"sufficient",
    "domain_status":"has_domain",
    "hosting_status":"has_hosting",
    "maintenance_interest":"no",
    "seo_priority":"basic",
    "priorities":["scope"],
    "confirmation":true
  }'::jsonb as complete_data,
  '{
    "pricingConfigVersion":"1.0.0",
    "pricingConfigHash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    "normalizedScope":{
      "standardPages":["home"],
      "standardPageCount":1,
      "primaryLanguage":"nl",
      "additionalLanguages":[],
      "unknownLanguages":[],
      "modules":[],
      "manualComponents":[]
    },
    "calculation":{
      "basis":"starter_floor",
      "currency":"EUR",
      "vatBasis":"exclusive",
      "knownMinimumMinor":180000,
      "containsFromPricing":true,
      "manualReviewRequired":false,
      "manualReasons":[],
      "appliedRules":[]
    },
    "packageAdvice":{
      "status":"none",
      "reasons":[],
      "advisoryOnly":true,
      "selectedPackage":null
    }
  }'::jsonb as snapshot_base;

alter table phase31b_fixture add column budget_guard_snapshot jsonb;
alter table phase31b_fixture add column legacy_snapshot jsonb;
alter table phase31b_fixture add column below_starter_snapshot jsonb;

update phase31b_fixture
set
  budget_guard_snapshot = snapshot_base || '{
    "snapshotContractVersion":2,
    "budgetEvaluation":{
      "contractVersion":2,
      "evidenceProvenance":"budget_guard_v1",
      "categoryScheme":"budget_guard_v1",
      "categoryCode":"3200_to_6000_inclusive",
      "originalLabel":"EUR 3.200 t/m EUR 6.000",
      "status":"possibly_compatible_with_category",
      "outsideBudgetWishes":false
    }
  }'::jsonb,
  legacy_snapshot = snapshot_base || '{
    "snapshotContractVersion":2,
    "budgetEvaluation":{
      "contractVersion":2,
      "evidenceProvenance":"legacy_label",
      "categoryScheme":null,
      "categoryCode":null,
      "originalLabel":"EUR 1.500 - EUR 3.000",
      "status":"legacy_category_not_safely_comparable",
      "outsideBudgetWishes":null
    }
  }'::jsonb,
  below_starter_snapshot = snapshot_base || '{
    "snapshotContractVersion":2,
    "budgetEvaluation":{
      "contractVersion":2,
      "evidenceProvenance":"budget_guard_v1",
      "categoryScheme":"budget_guard_v1",
      "categoryCode":"below_1800",
      "originalLabel":"Minder dan EUR 1.800",
      "status":"below_starter_starting_price",
      "outsideBudgetWishes":true
    }
  }'::jsonb;

insert into public.quote_request_pricing_snapshots (
  intake_id, config_version, config_hash, normalized_evidence,
  calculation, package_advice, budget_evaluation
)
select
  intake.id,
  '1.0.0',
  repeat('e', 64),
  fixture.snapshot_base->'normalizedScope',
  fixture.snapshot_base->'calculation',
  fixture.snapshot_base->'packageAdvice',
  '{
    "categoryCode":"3200_to_6000_inclusive",
    "status":"possibly_compatible_with_category",
    "outsideBudgetWishes":[]
  }'::jsonb
from public.quote_request_intakes as intake
cross join phase31b_fixture as fixture
where intake.access_token_hash = repeat('1', 64);

select ok(
  not (
    select attribute.attnotnull
    from pg_attribute as attribute
    where attribute.attrelid = 'public.quote_request_pricing_snapshots'::regclass
      and attribute.attname = 'snapshot_contract_version'
  ),
  'contract version column is nullable and requires no backfill'
);
select is(
  (
    select pg_get_expr(default_value.adbin, default_value.adrelid)
    from pg_attrdef as default_value
    inner join pg_attribute as attribute
      on attribute.attrelid = default_value.adrelid
     and attribute.attnum = default_value.adnum
    where default_value.adrelid = 'public.quote_request_pricing_snapshots'::regclass
      and attribute.attname = 'snapshot_contract_version'
  ),
  null::text,
  'contract version column has no backfill default'
);
select is(
  (select snapshot_contract_version from public.quote_request_pricing_snapshots),
  null::smallint,
  'historical snapshot remains contract v1 without synthesized version'
);
select is(
  (select budget_evaluation->'outsideBudgetWishes' from public.quote_request_pricing_snapshots),
  '[]'::jsonb,
  'historical v1 array shape remains unchanged and valid'
);
select is(
  (
    select pricing_snapshot->'budgetEvaluation'->'outsideBudgetWishes'
    from public.inspect_quote_request_intake_details_v2(repeat('1', 64))
  ),
  '[]'::jsonb,
  'existing inspect v2 still reads historical v1 snapshots'
);
select is(
  (
    select pricing_snapshot->'snapshotContractVersion'
    from public.inspect_quote_request_intake_details_v3(repeat('1', 64))
  ),
  'null'::jsonb,
  'inspect v3 identifies historical v1 without rewriting it'
);

select ok(
  to_regprocedure('public.update_quote_request_intake_v2(text,text,jsonb,text,timestamp with time zone,jsonb)') is not null,
  'existing update v2 signature remains intact'
);
select ok(
  to_regprocedure('public.inspect_quote_request_intake_details_v2(text)') is not null
    and to_regprocedure('public.inspect_submitted_intake_for_admin_v2(text)') is not null,
  'existing inspect v2 signatures remain intact'
);
select ok(
  not has_function_privilege('anon', 'public.update_quote_request_intake_v3(text,text,jsonb,text,timestamp with time zone,jsonb)', 'execute'),
  'anon cannot execute privileged v3 submit RPC'
);
select ok(
  not has_function_privilege('authenticated', 'public.update_quote_request_intake_v3(text,text,jsonb,text,timestamp with time zone,jsonb)', 'execute'),
  'authenticated cannot execute privileged v3 submit RPC'
);
select ok(
  not has_function_privilege('service_role', 'public.update_quote_request_intake_v3(text,text,jsonb,text,timestamp with time zone,jsonb)', 'execute')
    and has_function_privilege('service_role', 'public.update_quote_request_intake_v4(text,text,jsonb,text,timestamp with time zone,jsonb,jsonb)', 'execute'),
  'service role uses privileged integrity-bound v4 submit RPC'
);
select ok(
  has_function_privilege('service_role', 'public.inspect_quote_request_intake_details_v3(text)', 'execute')
    and has_function_privilege('service_role', 'public.inspect_submitted_intake_for_admin_v3(text)', 'execute'),
  'service role can execute both inspect v3 RPCs'
);

create temporary table phase31b_budget_guard_result as
select result.*
from phase31b_fixture as fixture
cross join lateral public.update_quote_request_intake_v3(
  repeat('2', 64),
  'submit',
  fixture.complete_data || '{
    "budget_update_category":"EUR 3.200 t/m EUR 6.000",
    "budget_update_category_scheme":"budget_guard_v1",
    "budget_update_category_code":"3200_to_6000_inclusive"
  }'::jsonb,
  repeat('a', 64),
  clock_timestamp() + interval '1 day',
  fixture.budget_guard_snapshot
) as result;

select is((select outcome from phase31b_budget_guard_result), 'submitted', 'Budget Guard provenance with valid code is accepted');
select is(
  (select count(*)::integer from public.quote_request_pricing_snapshots where snapshot_contract_version = 2),
  1,
  'successful v3 submit creates exactly one contract v2 snapshot'
);
select is(
  (select pricing_snapshot->>'snapshotContractVersion' from phase31b_budget_guard_result),
  '2',
  'v3 submit returns explicit snapshot contract version 2'
);
select is(
  (select budget_evaluation->>'evidenceProvenance' from public.quote_request_pricing_snapshots where snapshot_contract_version = 2),
  'budget_guard_v1',
  'stored Budget Guard provenance is exact'
);
select is(
  (select budget_evaluation->>'categoryCode' from public.quote_request_pricing_snapshots where snapshot_contract_version = 2),
  '3200_to_6000_inclusive',
  'stored Budget Guard category code is exact'
);
select is(
  (select budget_evaluation->'outsideBudgetWishes' from public.quote_request_pricing_snapshots where snapshot_contract_version = 2),
  'false'::jsonb,
  'tri-state false is stored as a JSON boolean'
);
select is(
  (
    select pricing_snapshot->'budgetEvaluation'->'outsideBudgetWishes'
    from public.inspect_quote_request_intake_details_v3(repeat('2', 64))
  ),
  'false'::jsonb,
  'inspect v3 preserves tri-state false'
);

select throws_matching(
  $$
    select * from phase31b_fixture as fixture
    cross join lateral public.update_quote_request_intake_v3(
      repeat('4', 64), 'submit',
      fixture.complete_data || '{"budget_update_category":"EUR 3.200 t/m EUR 6.000","budget_update_category_scheme":"budget_guard_v1","budget_update_category_code":"3200_to_6000_inclusive"}'::jsonb,
      repeat('b', 64), clock_timestamp() + interval '1 day',
      jsonb_set(fixture.budget_guard_snapshot, '{budgetEvaluation,categoryCode}', 'null'::jsonb)
    )
  $$,
  'PRICING_SNAPSHOT_BUDGET_MISMATCH|quote_request_pricing_snapshots_budget_evaluation_valid',
  'Budget Guard provenance with null category code is rejected'
);
select throws_matching(
  $$
    select * from phase31b_fixture as fixture
    cross join lateral public.update_quote_request_intake_v3(
      repeat('4', 64), 'submit',
      fixture.complete_data || '{"budget_update_category":"EUR 3.200 t/m EUR 6.000","budget_update_category_scheme":"budget_guard_v1","budget_update_category_code":"3200_to_6000_inclusive"}'::jsonb,
      repeat('b', 64), clock_timestamp() + interval '1 day',
      jsonb_set(fixture.budget_guard_snapshot, '{budgetEvaluation,originalLabel}', '"EUR 1.500 - EUR 3.000"'::jsonb)
    )
  $$,
  'PRICING_SNAPSHOT_BUDGET_MISMATCH|quote_request_pricing_snapshots_budget_evaluation_valid',
  'Budget Guard provenance with a legacy label is rejected'
);
select throws_matching(
  $$
    select * from phase31b_fixture as fixture
    cross join lateral public.update_quote_request_intake_v3(
      repeat('4', 64), 'submit',
      fixture.complete_data || '{"budget_update_category":"EUR 3.200 t/m EUR 6.000","budget_update_category_scheme":"budget_guard_v1","budget_update_category_code":"3200_to_6000_inclusive"}'::jsonb,
      repeat('b', 64), clock_timestamp() + interval '1 day',
      jsonb_set(fixture.budget_guard_snapshot, '{budgetEvaluation,evidenceProvenance}', '"unknown"'::jsonb)
    )
  $$,
  'PRICING_SNAPSHOT_BUDGET_MISMATCH|quote_request_pricing_snapshots_budget_evaluation_valid',
  'unknown provenance is rejected'
);

select throws_matching(
  $$
    select * from phase31b_fixture as fixture
    cross join lateral public.update_quote_request_intake_v3(
      repeat('4', 64), 'submit',
      fixture.complete_data || '{"budget_update_category":"EUR 3.200 t/m EUR 6.000","budget_update_category_scheme":"budget_guard_v1","budget_update_category_code":"3200_to_6000_inclusive"}'::jsonb,
      repeat('b', 64), clock_timestamp() + interval '1 day',
      jsonb_set(fixture.budget_guard_snapshot, '{budgetEvaluation,outsideBudgetWishes}', '[]'::jsonb)
    )
  $$,
  'quote_request_pricing_snapshots_budget_evaluation_valid',
  'v2 outsideBudgetWishes array is rejected'
);
select throws_matching(
  $$
    select * from phase31b_fixture as fixture
    cross join lateral public.update_quote_request_intake_v3(
      repeat('4', 64), 'submit',
      fixture.complete_data || '{"budget_update_category":"EUR 3.200 t/m EUR 6.000","budget_update_category_scheme":"budget_guard_v1","budget_update_category_code":"3200_to_6000_inclusive"}'::jsonb,
      repeat('b', 64), clock_timestamp() + interval '1 day',
      jsonb_set(fixture.budget_guard_snapshot, '{budgetEvaluation,outsideBudgetWishes}', '"false"'::jsonb)
    )
  $$,
  'quote_request_pricing_snapshots_budget_evaluation_valid',
  'v2 outsideBudgetWishes string is rejected'
);
select throws_matching(
  $$
    select * from phase31b_fixture as fixture
    cross join lateral public.update_quote_request_intake_v3(
      repeat('4', 64), 'submit',
      fixture.complete_data || '{"budget_update_category":"EUR 3.200 t/m EUR 6.000","budget_update_category_scheme":"budget_guard_v1","budget_update_category_code":"3200_to_6000_inclusive"}'::jsonb,
      repeat('b', 64), clock_timestamp() + interval '1 day',
      jsonb_set(fixture.budget_guard_snapshot, '{budgetEvaluation,outsideBudgetWishes}', '{}'::jsonb)
    )
  $$,
  'quote_request_pricing_snapshots_budget_evaluation_valid',
  'v2 outsideBudgetWishes object is rejected'
);
select throws_matching(
  $$
    select * from phase31b_fixture as fixture
    cross join lateral public.update_quote_request_intake_v3(
      repeat('4', 64), 'submit',
      fixture.complete_data || '{"budget_update_category":"EUR 3.200 t/m EUR 6.000","budget_update_category_scheme":"budget_guard_v1","budget_update_category_code":"3200_to_6000_inclusive"}'::jsonb,
      repeat('b', 64), clock_timestamp() + interval '1 day',
      fixture.budget_guard_snapshot - 'snapshotContractVersion'
    )
  $$,
  'INVALID_PRICING_SNAPSHOT_V2',
  'missing required snapshot contract version is rejected'
);
select throws_matching(
  $$
    select * from phase31b_fixture as fixture
    cross join lateral public.update_quote_request_intake_v3(
      repeat('4', 64), 'submit',
      fixture.complete_data || '{"budget_update_category":"EUR 3.200 t/m EUR 6.000","budget_update_category_scheme":"budget_guard_v1","budget_update_category_code":"3200_to_6000_inclusive"}'::jsonb,
      repeat('b', 64), clock_timestamp() + interval '1 day',
      jsonb_set(fixture.budget_guard_snapshot, '{snapshotContractVersion}', '3'::jsonb)
    )
  $$,
  'INVALID_PRICING_SNAPSHOT_V2',
  'unknown snapshot contract version is rejected'
);
select throws_matching(
  $$
    select * from phase31b_fixture as fixture
    cross join lateral public.update_quote_request_intake_v3(
      repeat('4', 64), 'submit',
      fixture.complete_data || '{"budget_update_category":"EUR 3.200 t/m EUR 6.000","budget_update_category_scheme":"budget_guard_v1","budget_update_category_code":"3200_to_6000_inclusive"}'::jsonb,
      repeat('b', 64), clock_timestamp() + interval '1 day',
      fixture.budget_guard_snapshot || '{"unexpected":true}'::jsonb
    )
  $$,
  'INVALID_PRICING_SNAPSHOT_V2',
  'unknown top-level authoritative snapshot key is rejected'
);
select throws_matching(
  $$
    select * from phase31b_fixture as fixture
    cross join lateral public.update_quote_request_intake_v3(
      repeat('4', 64), 'submit',
      fixture.complete_data || '{"budget_update_category":"EUR 3.200 t/m EUR 6.000","budget_update_category_scheme":"budget_guard_v1","budget_update_category_code":"3200_to_6000_inclusive"}'::jsonb,
      repeat('b', 64), clock_timestamp() + interval '1 day',
      jsonb_set(fixture.budget_guard_snapshot, '{budgetEvaluation}', fixture.budget_guard_snapshot->'budgetEvaluation' || '{"unexpected":true}'::jsonb)
    )
  $$,
  'quote_request_pricing_snapshots_budget_evaluation_valid',
  'unknown budget evaluation key is rejected by the closed shape'
);
select is(
  (select status::text from public.quote_request_intakes where access_token_hash = repeat('4', 64)),
  'invited',
  'failed snapshot validation rolls back intake submission'
);
select is(
  (select count(*)::integer from public.quote_request_pricing_snapshots as snapshot inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id where intake.access_token_hash = repeat('4', 64)),
  0,
  'failed snapshot validation leaves no orphan snapshot'
);

create temporary table phase31b_legacy_result as
select result.*
from phase31b_fixture as fixture
cross join lateral public.update_quote_request_intake_v3(
  repeat('3', 64),
  'submit',
  fixture.complete_data || '{"budget_update_category":"EUR 1.500 - EUR 3.000"}'::jsonb,
  repeat('c', 64),
  clock_timestamp() + interval '1 day',
  fixture.legacy_snapshot
) as result;

select is((select outcome from phase31b_legacy_result), 'submitted', 'legacy provenance with exact legacy label is accepted');
select is(
  (select pricing_snapshot->'budgetEvaluation'->'categoryCode' from phase31b_legacy_result),
  'null'::jsonb,
  'legacy contract stores categoryCode as JSON null'
);
select is(
  (select pricing_snapshot->'budgetEvaluation'->>'originalLabel' from phase31b_legacy_result),
  'EUR 1.500 - EUR 3.000',
  'legacy contract preserves the original label exactly'
);
select is(
  (select pricing_snapshot->'budgetEvaluation'->'outsideBudgetWishes' from phase31b_legacy_result),
  'null'::jsonb,
  'legacy contract stores unknown outsideBudgetWishes as JSON null'
);
select is(
  (
    select pricing_snapshot->'budgetEvaluation'->>'evidenceProvenance'
    from public.inspect_quote_request_intake_details_v3(repeat('3', 64))
  ),
  'legacy_label',
  'inspect v3 preserves legacy provenance'
);
select is(
  (
    select pricing_snapshot->'budgetEvaluation'->'categoryCode'
    from public.inspect_quote_request_intake_details_v3(repeat('3', 64))
  ),
  'null'::jsonb,
  'inspect v3 preserves legacy categoryCode null'
);
select is(
  (
    select pricing_snapshot->'budgetEvaluation'->'outsideBudgetWishes'
    from public.inspect_submitted_intake_for_admin_v3(repeat('c', 64))
  ),
  'null'::jsonb,
  'admin inspect v3 preserves legacy tri-state null'
);
select is(
  (
    select pricing_snapshot->'budgetEvaluation'->>'originalLabel'
    from public.inspect_submitted_intake_for_admin_v2(repeat('c', 64))
  ),
  'EUR 1.500 - EUR 3.000',
  'existing admin inspect v2 transparently reads contract v2 legacy evidence'
);

select throws_matching(
  $$
    select * from phase31b_fixture as fixture
    cross join lateral public.update_quote_request_intake_v3(
      repeat('4', 64), 'submit',
      fixture.complete_data || '{"budget_update_category":"EUR 1.500 - EUR 3.000"}'::jsonb,
      repeat('b', 64), clock_timestamp() + interval '1 day',
      jsonb_set(fixture.legacy_snapshot, '{budgetEvaluation,categoryCode}', '"1800_to_below_3200"'::jsonb)
    )
  $$,
  'PRICING_SNAPSHOT_BUDGET_MISMATCH|quote_request_pricing_snapshots_budget_evaluation_valid',
  'legacy provenance with a fake v2 code is rejected'
);
select throws_matching(
  $$
    select * from phase31b_fixture as fixture
    cross join lateral public.update_quote_request_intake_v3(
      repeat('4', 64), 'submit',
      fixture.complete_data || '{"budget_update_category":"EUR 1.500 - EUR 3.000"}'::jsonb,
      repeat('b', 64), clock_timestamp() + interval '1 day',
      jsonb_set(fixture.legacy_snapshot, '{budgetEvaluation,originalLabel}', '"Unknown legacy range"'::jsonb)
    )
  $$,
  'PRICING_SNAPSHOT_BUDGET_MISMATCH|quote_request_pricing_snapshots_budget_evaluation_valid',
  'unknown legacy label is rejected'
);

create temporary table phase31b_true_result as
select result.*
from phase31b_fixture as fixture
cross join lateral public.update_quote_request_intake_v3(
  repeat('5', 64),
  'submit',
  fixture.complete_data || '{
    "budget_update_category":"Minder dan EUR 1.800",
    "budget_update_category_scheme":"budget_guard_v1",
    "budget_update_category_code":"below_1800"
  }'::jsonb,
  repeat('d', 64),
  clock_timestamp() + interval '1 day',
  fixture.below_starter_snapshot
) as result;

select is((select outcome from phase31b_true_result), 'submitted', 'valid tri-state true snapshot is accepted');
select is(
  (select pricing_snapshot->'budgetEvaluation'->'outsideBudgetWishes' from phase31b_true_result),
  'true'::jsonb,
  'tri-state true is preserved as a JSON boolean'
);

select is(
  (
    select result.pricing_snapshot->>'pricingConfigHash'
    from phase31b_fixture as fixture
    cross join lateral public.update_quote_request_intake_v3(
      repeat('2', 64), 'submit', '{}'::jsonb, null, null,
      jsonb_set(fixture.budget_guard_snapshot, '{pricingConfigHash}', to_jsonb(repeat('a', 64)))
    ) as result
  ),
  repeat('f', 64),
  'idempotent resubmit returns the original historical snapshot'
);
select is(
  (select count(*)::integer from public.quote_request_pricing_snapshots as snapshot inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id where intake.access_token_hash = repeat('2', 64)),
  1,
  'idempotent resubmit cannot create a second snapshot'
);
select is(
  (select config_hash from public.quote_request_pricing_snapshots as snapshot inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id where intake.access_token_hash = repeat('2', 64)),
  repeat('f', 64),
  'idempotent resubmit cannot replace config or hash'
);
select throws_matching(
  $$update public.quote_request_pricing_snapshots set snapshot_contract_version = 2$$,
  'PRICING_SNAPSHOT_IMMUTABLE',
  'existing immutability trigger blocks all snapshot updates'
);

select throws_matching(
  $$
    select * from phase31b_fixture as fixture
    cross join lateral public.update_quote_request_intake_v3(
      repeat('6', 64), 'submit',
      '{"business_description":"Incomplete submit"}'::jsonb,
      repeat('e', 64), clock_timestamp() + interval '1 day',
      fixture.budget_guard_snapshot
    )
  $$,
  'INCOMPLETE_INTAKE_SUBMISSION',
  'forced legacy submit failure aborts before snapshot creation'
);
select is(
  (select status::text from public.quote_request_intakes where access_token_hash = repeat('6', 64)),
  'invited',
  'forced submit failure rolls back intake status'
);
select is(
  (select count(*)::integer from public.quote_request_pricing_snapshots as snapshot inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id where intake.access_token_hash = repeat('6', 64)),
  0,
  'forced submit failure leaves no orphan snapshot'
);
select is(
  (select count(*)::integer from public.quote_request_pricing_snapshots),
  4,
  'only the historical and three successful contract fixtures exist'
);

select * from finish();
rollback;