begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(47);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, budget_category_scheme, budget_category_code
) values
  ('32000000-0000-0000-0000-000000000001', 'DB2 Budget Guard', 'db2-bg@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'DB2 Budget Guard fixture.', true, 'approved', 'budget_guard_v1', '3200_to_6000_inclusive'),
  ('32000000-0000-0000-0000-000000000002', 'DB2 Legacy', 'db2-legacy@example.test', 'business', 'EUR 1.500 - EUR 3.000', 'flexible', 'DB2 legacy fixture.', true, 'approved', null, null),
  ('32000000-0000-0000-0000-000000000003', 'DB2 Missing', 'db2-missing@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'DB2 missing fixture.', true, 'approved', null, null),
  ('32000000-0000-0000-0000-000000000004', 'DB2 Ambiguous', 'db2-ambiguous@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'DB2 ambiguous fixture.', true, 'approved', null, null),
  ('32000000-0000-0000-0000-000000000005', 'DB2 Invalid', 'db2-invalid@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'DB2 invalid rollback fixture.', true, 'approved', null, null),
  ('32000000-0000-0000-0000-000000000006', 'DB2 Failed', 'db2-failed@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'DB2 failed submit fixture.', true, 'approved', null, null),
  ('32000000-0000-0000-0000-000000000007', 'DB2 Historical', 'db2-v1@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'DB2 historical v1 fixture.', true, 'approved', null, null);

insert into public.quote_request_intakes (
  quote_request_id, access_token_hash, access_token_expires_at,
  status, started_at, submitted_at, confirmation, budget_update_category,
  created_at
)
select
  request_id,
  repeat(token_character, 64),
  clock_timestamp() + interval '1 day',
  (case when token_character = '7' then 'submitted' else 'invited' end)::public.quote_request_intake_status,
  case when token_character = '7' then clock_timestamp() - interval '2 hours' else null end,
  case when token_character = '7' then clock_timestamp() - interval '1 hour' else null end,
  token_character = '7',
  case when token_character = '7' then 'EUR 3.000 - EUR 6.000' else null end,
  clock_timestamp()
from (values
  ('32000000-0000-0000-0000-000000000001'::uuid, '1'),
  ('32000000-0000-0000-0000-000000000002'::uuid, '2'),
  ('32000000-0000-0000-0000-000000000003'::uuid, '3'),
  ('32000000-0000-0000-0000-000000000004'::uuid, '4'),
  ('32000000-0000-0000-0000-000000000005'::uuid, '5'),
  ('32000000-0000-0000-0000-000000000006'::uuid, '6'),
  ('32000000-0000-0000-0000-000000000007'::uuid, '7')
) as fixtures(request_id, token_character);

create temporary table db2_fixture as
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
    "snapshotContractVersion":2,
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

alter table db2_fixture add column budget_guard_snapshot jsonb;
alter table db2_fixture add column legacy_snapshot jsonb;
alter table db2_fixture add column missing_snapshot jsonb;
alter table db2_fixture add column ambiguous_snapshot jsonb;

update db2_fixture
set
  budget_guard_snapshot = snapshot_base || '{
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
  missing_snapshot = snapshot_base || '{
    "budgetEvaluation":{
      "contractVersion":2,
      "evidenceProvenance":"missing",
      "categoryScheme":null,
      "categoryCode":null,
      "originalLabel":null,
      "status":"manual_review_required",
      "outsideBudgetWishes":null
    }
  }'::jsonb,
  ambiguous_snapshot = snapshot_base || '{
    "budgetEvaluation":{
      "contractVersion":2,
      "evidenceProvenance":"ambiguous",
      "categoryScheme":null,
      "categoryCode":null,
      "originalLabel":"EUR 3.000 - EUR 6.000",
      "status":"manual_review_required",
      "outsideBudgetWishes":null
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
cross join db2_fixture as fixture
where intake.access_token_hash = repeat('7', 64);

create temporary table db2_submit_results (
  provenance text primary key,
  outcome text,
  pricing_snapshot jsonb
);

insert into db2_submit_results
select 'budget_guard_v1', result.outcome, result.pricing_snapshot
from db2_fixture as fixture
cross join lateral public.update_quote_request_intake_v3(
  repeat('1', 64),
  'submit',
  fixture.complete_data,
  repeat('a', 64),
  clock_timestamp() + interval '1 day',
  fixture.budget_guard_snapshot
) as result;

insert into db2_submit_results
select 'legacy_label', result.outcome, result.pricing_snapshot
from db2_fixture as fixture
cross join lateral public.update_quote_request_intake_v3(
  repeat('2', 64),
  'submit',
  fixture.complete_data,
  repeat('b', 64),
  clock_timestamp() + interval '1 day',
  fixture.legacy_snapshot
) as result;

insert into db2_submit_results
select 'missing', result.outcome, result.pricing_snapshot
from db2_fixture as fixture
cross join lateral public.update_quote_request_intake_v3(
  repeat('3', 64),
  'submit',
  fixture.complete_data,
  repeat('c', 64),
  clock_timestamp() + interval '1 day',
  fixture.missing_snapshot
) as result;

insert into db2_submit_results
select 'ambiguous', result.outcome, result.pricing_snapshot
from db2_fixture as fixture
cross join lateral public.update_quote_request_intake_v3(
  repeat('4', 64),
  'submit',
  fixture.complete_data,
  repeat('d', 64),
  clock_timestamp() + interval '1 day',
  fixture.ambiguous_snapshot
) as result;

select is((select outcome from db2_submit_results where provenance = 'budget_guard_v1'), 'submitted', 'budget_guard_v1 remains accepted');
select is((select pricing_snapshot->'budgetEvaluation'->>'evidenceProvenance' from db2_submit_results where provenance = 'budget_guard_v1'), 'budget_guard_v1', 'Budget Guard provenance remains exact');
select is((select outcome from db2_submit_results where provenance = 'legacy_label'), 'submitted', 'legacy_label remains accepted');
select is((select pricing_snapshot->'budgetEvaluation'->>'originalLabel' from db2_submit_results where provenance = 'legacy_label'), 'EUR 1.500 - EUR 3.000', 'legacy original label remains exact');
select is((select outcome from db2_submit_results where provenance = 'missing'), 'submitted', 'missing provenance is accepted');
select is((select pricing_snapshot->'budgetEvaluation'->>'evidenceProvenance' from db2_submit_results where provenance = 'missing'), 'missing', 'missing remains distinct');
select is((select pricing_snapshot->'budgetEvaluation'->'categoryCode' from db2_submit_results where provenance = 'missing'), 'null'::jsonb, 'missing category code is null');
select is((select pricing_snapshot->'budgetEvaluation'->'outsideBudgetWishes' from db2_submit_results where provenance = 'missing'), 'null'::jsonb, 'missing outsideBudgetWishes is null');
select is((select outcome from db2_submit_results where provenance = 'ambiguous'), 'submitted', 'ambiguous provenance is accepted');
select is((select pricing_snapshot->'budgetEvaluation'->>'evidenceProvenance' from db2_submit_results where provenance = 'ambiguous'), 'ambiguous', 'ambiguous remains distinct');
select is((select pricing_snapshot->'budgetEvaluation'->>'originalLabel' from db2_submit_results where provenance = 'ambiguous'), 'EUR 3.000 - EUR 6.000', 'ambiguous preserves original evidence label');
select is((select pricing_snapshot->'budgetEvaluation'->'categoryCode' from db2_submit_results where provenance = 'ambiguous'), 'null'::jsonb, 'ambiguous category code is null');
select is((select pricing_snapshot->'budgetEvaluation'->'outsideBudgetWishes' from db2_submit_results where provenance = 'ambiguous'), 'null'::jsonb, 'ambiguous outsideBudgetWishes is null');

select throws_matching(
  $$select * from db2_fixture as fixture cross join lateral public.update_quote_request_intake_v3(repeat('5', 64), 'submit', fixture.complete_data, repeat('5', 64), clock_timestamp() + interval '1 day', jsonb_set(fixture.missing_snapshot, '{budgetEvaluation,evidenceProvenance}', '"unknown"'::jsonb)) as result$$,
  'PRICING_SNAPSHOT_BUDGET_MISMATCH|quote_request_pricing_snapshots_budget_evaluation_valid',
  'unknown provenance is rejected'
);
select throws_matching(
  $$select * from db2_fixture as fixture cross join lateral public.update_quote_request_intake_v3(repeat('5', 64), 'submit', fixture.complete_data, repeat('5', 64), clock_timestamp() + interval '1 day', jsonb_set(fixture.missing_snapshot, '{budgetEvaluation,categoryCode}', '"below_1800"'::jsonb)) as result$$,
  'quote_request_pricing_snapshots_budget_evaluation_valid',
  'missing with a category code is rejected'
);
select throws_matching(
  $$select * from db2_fixture as fixture cross join lateral public.update_quote_request_intake_v3(repeat('5', 64), 'submit', fixture.complete_data, repeat('5', 64), clock_timestamp() + interval '1 day', jsonb_set(fixture.ambiguous_snapshot, '{budgetEvaluation,categoryCode}', '"3200_to_6000_inclusive"'::jsonb)) as result$$,
  'quote_request_pricing_snapshots_budget_evaluation_valid',
  'ambiguous with a category code is rejected'
);
select throws_matching(
  $$select * from db2_fixture as fixture cross join lateral public.update_quote_request_intake_v3(repeat('5', 64), 'submit', fixture.complete_data, repeat('5', 64), clock_timestamp() + interval '1 day', jsonb_set(fixture.missing_snapshot, '{budgetEvaluation,outsideBudgetWishes}', 'true'::jsonb)) as result$$,
  'quote_request_pricing_snapshots_budget_evaluation_valid',
  'missing with outsideBudgetWishes true is rejected'
);
select throws_matching(
  $$select * from db2_fixture as fixture cross join lateral public.update_quote_request_intake_v3(repeat('5', 64), 'submit', fixture.complete_data, repeat('5', 64), clock_timestamp() + interval '1 day', jsonb_set(fixture.missing_snapshot, '{budgetEvaluation,outsideBudgetWishes}', 'false'::jsonb)) as result$$,
  'quote_request_pricing_snapshots_budget_evaluation_valid',
  'missing with outsideBudgetWishes false is rejected'
);
select throws_matching(
  $$select * from db2_fixture as fixture cross join lateral public.update_quote_request_intake_v3(repeat('5', 64), 'submit', fixture.complete_data, repeat('5', 64), clock_timestamp() + interval '1 day', jsonb_set(fixture.ambiguous_snapshot, '{budgetEvaluation,outsideBudgetWishes}', 'true'::jsonb)) as result$$,
  'quote_request_pricing_snapshots_budget_evaluation_valid',
  'ambiguous with outsideBudgetWishes true is rejected'
);
select throws_matching(
  $$select * from db2_fixture as fixture cross join lateral public.update_quote_request_intake_v3(repeat('5', 64), 'submit', fixture.complete_data, repeat('5', 64), clock_timestamp() + interval '1 day', jsonb_set(fixture.ambiguous_snapshot, '{budgetEvaluation,outsideBudgetWishes}', 'false'::jsonb)) as result$$,
  'quote_request_pricing_snapshots_budget_evaluation_valid',
  'ambiguous with outsideBudgetWishes false is rejected'
);
select throws_matching(
  $$select * from db2_fixture as fixture cross join lateral public.update_quote_request_intake_v3(repeat('5', 64), 'submit', fixture.complete_data, repeat('5', 64), clock_timestamp() + interval '1 day', jsonb_set(fixture.missing_snapshot, '{budgetEvaluation,originalLabel}', '"EUR 3.000 - EUR 6.000"'::jsonb)) as result$$,
  'quote_request_pricing_snapshots_budget_evaluation_valid',
  'missing cannot contain a fake legacy label'
);
select throws_matching(
  $$select * from db2_fixture as fixture cross join lateral public.update_quote_request_intake_v3(repeat('5', 64), 'submit', fixture.complete_data, repeat('5', 64), clock_timestamp() + interval '1 day', jsonb_set(fixture.ambiguous_snapshot, '{budgetEvaluation,categoryScheme}', '"budget_guard_v1"'::jsonb)) as result$$,
  'quote_request_pricing_snapshots_budget_evaluation_valid',
  'ambiguous cannot contain a fake Budget Guard mapping'
);
select throws_matching(
  $$select * from db2_fixture as fixture cross join lateral public.update_quote_request_intake_v3(repeat('5', 64), 'submit', fixture.complete_data, repeat('5', 64), clock_timestamp() + interval '1 day', jsonb_set(fixture.legacy_snapshot, '{budgetEvaluation,categoryCode}', '"1800_to_below_3200"'::jsonb)) as result$$,
  'PRICING_SNAPSHOT_BUDGET_MISMATCH|quote_request_pricing_snapshots_budget_evaluation_valid',
  'legacy provenance with a fake v2 code remains rejected'
);
select throws_matching(
  $$select * from db2_fixture as fixture cross join lateral public.update_quote_request_intake_v3(repeat('5', 64), 'submit', fixture.complete_data, repeat('5', 64), clock_timestamp() + interval '1 day', jsonb_set(fixture.budget_guard_snapshot, '{budgetEvaluation,categoryCode}', 'null'::jsonb)) as result$$,
  'PRICING_SNAPSHOT_BUDGET_MISMATCH|quote_request_pricing_snapshots_budget_evaluation_valid',
  'Budget Guard provenance with a null code remains rejected'
);
select is((select status::text from public.quote_request_intakes where access_token_hash = repeat('5', 64)), 'invited', 'invalid provenance rolls back intake submission');
select is((select count(*)::integer from public.quote_request_pricing_snapshots as snapshot inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id where intake.access_token_hash = repeat('5', 64)), 0, 'invalid provenance leaves no orphan snapshot');

select is((select pricing_snapshot->'budgetEvaluation'->>'evidenceProvenance' from public.inspect_quote_request_intake_details_v3(repeat('3', 64))), 'missing', 'inspect v3 preserves missing provenance');
select is((select pricing_snapshot->'budgetEvaluation'->>'evidenceProvenance' from public.inspect_quote_request_intake_details_v3(repeat('4', 64))), 'ambiguous', 'inspect v3 preserves ambiguous provenance');
select is((select pricing_snapshot->'budgetEvaluation'->'categoryCode' from public.inspect_quote_request_intake_details_v3(repeat('3', 64))), 'null'::jsonb, 'inspect preserves missing categoryCode null');
select is((select pricing_snapshot->'budgetEvaluation'->'categoryCode' from public.inspect_quote_request_intake_details_v3(repeat('4', 64))), 'null'::jsonb, 'inspect preserves ambiguous categoryCode null');
select is((select pricing_snapshot->'budgetEvaluation'->'outsideBudgetWishes' from public.inspect_submitted_intake_for_admin_v3(repeat('c', 64))), 'null'::jsonb, 'admin inspect preserves missing outsideBudgetWishes null');
select is((select pricing_snapshot->'budgetEvaluation'->'outsideBudgetWishes' from public.inspect_submitted_intake_for_admin_v3(repeat('d', 64))), 'null'::jsonb, 'admin inspect preserves ambiguous outsideBudgetWishes null');

select is((select count(*)::integer from public.quote_request_pricing_snapshots where snapshot_contract_version = 2), 4, 'four successful contract-v2 submits each store one snapshot atomically');
select is(
  (select result.outcome from db2_fixture as fixture cross join lateral public.update_quote_request_intake_v3(repeat('3', 64), 'submit', '{}'::jsonb, null, null, jsonb_set(fixture.missing_snapshot, '{pricingConfigHash}', to_jsonb(repeat('0', 64)))) as result),
  'already_submitted',
  'idempotent retry returns already_submitted'
);
select is((select config_hash from public.quote_request_pricing_snapshots as snapshot inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id where intake.access_token_hash = repeat('3', 64)), repeat('f', 64), 'idempotent retry preserves the historical config hash');
select is((select count(*)::integer from public.quote_request_pricing_snapshots as snapshot inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id where intake.access_token_hash = repeat('3', 64)), 1, 'idempotent retry cannot create a second snapshot');
select throws_matching($$update public.quote_request_pricing_snapshots set snapshot_contract_version = 2$$, 'PRICING_SNAPSHOT_IMMUTABLE', 'snapshot immutability remains enforced');

select ok(not has_function_privilege('anon', 'public.update_quote_request_intake_v3(text,text,jsonb,text,timestamp with time zone,jsonb)', 'execute'), 'anon cannot execute v3');
select ok(not has_function_privilege('authenticated', 'public.update_quote_request_intake_v3(text,text,jsonb,text,timestamp with time zone,jsonb)', 'execute'), 'authenticated cannot execute v3');
select ok(
  not has_function_privilege('service_role', 'public.update_quote_request_intake_v3(text,text,jsonb,text,timestamp with time zone,jsonb)', 'execute')
    and has_function_privilege('service_role', 'public.update_quote_request_intake_v4(text,text,jsonb,text,timestamp with time zone,jsonb,jsonb)', 'execute'),
  'service_role uses integrity-bound v4 instead of v3'
);
select ok(to_regprocedure('public.update_quote_request_intake_v3(text,text,jsonb,text,timestamp with time zone,jsonb)') is not null, 'v3 signature remains unchanged');
select ok(
  has_function_privilege('service_role', 'public.inspect_quote_request_intake_details_v3(text)', 'execute')
    and not has_function_privilege('anon', 'public.inspect_quote_request_intake_details_v3(text)', 'execute'),
  'inspect v3 grants remain service-role-only'
);
select is((select snapshot_contract_version from public.quote_request_pricing_snapshots as snapshot inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id where intake.access_token_hash = repeat('7', 64)), null::smallint, 'historical v1 snapshot remains valid without backfill');

select throws_matching(
  $$select * from db2_fixture as fixture cross join lateral public.update_quote_request_intake_v3(repeat('6', 64), 'submit', '{"business_description":"Incomplete"}'::jsonb, repeat('6', 64), clock_timestamp() + interval '1 day', fixture.missing_snapshot) as result$$,
  'INCOMPLETE_INTAKE_SUBMISSION',
  'failed submit aborts before snapshot creation'
);
select is((select status::text from public.quote_request_intakes where access_token_hash = repeat('6', 64)), 'invited', 'failed submit rolls back intake status');
select is((select count(*)::integer from public.quote_request_pricing_snapshots as snapshot inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id where intake.access_token_hash = repeat('6', 64)), 0, 'failed submit leaves no orphan snapshot');
select is((select status::text from public.quote_request_intakes where access_token_hash = repeat('3', 64)), 'submitted', 'successful missing submit commits intake and snapshot together');

select * from finish();
rollback;