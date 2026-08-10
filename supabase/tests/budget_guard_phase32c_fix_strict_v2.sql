begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(15);

create temporary table strict_v2_fixture as
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
    "basis":"starter_floor",
    "currency":"EUR",
    "vatBasis":"exclusive",
    "knownMinimumMinor":180000,
    "containsFromPricing":true,
    "manualReviewRequired":false,
    "manualReasons":[],
    "appliedRules":[{
      "ruleId":"starter_floor",
      "mode":"from",
      "amountMinor":180000,
      "quantity":1,
      "knownMinimumContributionMinor":180000
    }]
  }'::jsonb as calculation,
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
  }'::jsonb as budget_evaluation;

create function pg_temp.strict_fixture_valid(
  p_version smallint default 2,
  p_normalized_scope jsonb default null,
  p_calculation jsonb default null,
  p_package_advice jsonb default null,
  p_budget_evaluation jsonb default null
)
returns boolean
language sql
as $$
  select public.is_strict_pricing_snapshot_v2(
    p_version,
    '1.0.0',
    repeat('a', 64),
    coalesce(p_normalized_scope, fixture.normalized_scope),
    coalesce(p_calculation, fixture.calculation),
    coalesce(p_package_advice, fixture.package_advice),
    coalesce(p_budget_evaluation, fixture.budget_evaluation)
  )
  from strict_v2_fixture as fixture
$$;

select ok(pg_temp.strict_fixture_valid(), 'canonical snapshot v2 is valid');
select ok(not pg_temp.strict_fixture_valid(p_calculation => jsonb_set(calculation, '{appliedRules}', '[42]'::jsonb)), 'numeric applied rule is rejected') from strict_v2_fixture;
select ok(not pg_temp.strict_fixture_valid(p_calculation => jsonb_set(calculation, '{appliedRules,0}', '{"ruleId":"starter_floor"}'::jsonb)), 'malformed rule object is rejected') from strict_v2_fixture;
select ok(not pg_temp.strict_fixture_valid(p_calculation => jsonb_set(calculation, '{appliedRules,0,futureInternalSecret}', 'true'::jsonb)), 'unknown rule field is rejected') from strict_v2_fixture;
select ok(not pg_temp.strict_fixture_valid(p_calculation => jsonb_set(calculation, '{manualReasons}', '[42]'::jsonb)), 'malformed manual reasons are rejected') from strict_v2_fixture;
select ok(not pg_temp.strict_fixture_valid(p_calculation => jsonb_set(jsonb_set(calculation, '{manualReviewRequired}', 'true'::jsonb), '{manualReasons}', '[]'::jsonb)), 'manual-review coherence is enforced') from strict_v2_fixture;
select ok(not pg_temp.strict_fixture_valid(p_normalized_scope => jsonb_set(normalized_scope, '{standardPages}', '"home"'::jsonb)), 'malformed normalized scope is rejected') from strict_v2_fixture;
select ok(not pg_temp.strict_fixture_valid(p_normalized_scope => normalized_scope || '{"futureInternalSecret":true}'::jsonb), 'extra normalized-scope field is rejected') from strict_v2_fixture;
select ok(not pg_temp.strict_fixture_valid(p_package_advice => jsonb_set(package_advice, '{selectedPackage}', '"Starter"'::jsonb)), 'malformed package advice is rejected') from strict_v2_fixture;
select ok(not pg_temp.strict_fixture_valid(p_budget_evaluation => jsonb_set(budget_evaluation, '{outsideBudgetWishes}', '[]'::jsonb)), 'malformed budget tri-state is rejected') from strict_v2_fixture;
select ok(not pg_temp.strict_fixture_valid(p_budget_evaluation => jsonb_set(budget_evaluation, '{evidenceProvenance}', '"future"'::jsonb)), 'unknown provenance is rejected') from strict_v2_fixture;
select ok(not pg_temp.strict_fixture_valid(p_budget_evaluation => jsonb_set(budget_evaluation, '{outsideBudgetWishes}', 'true'::jsonb)), 'incoherent budget status and tri-state are rejected') from strict_v2_fixture;
select ok(not pg_temp.strict_fixture_valid(p_version => 3::smallint), 'unsupported snapshot version is rejected');
select ok(not pg_temp.strict_fixture_valid(p_calculation => calculation - 'appliedRules'), 'missing nested key is rejected') from strict_v2_fixture;
select ok(not pg_temp.strict_fixture_valid(p_calculation => calculation || '{"futureInternalSecret":true}'::jsonb), 'forbidden extra calculation field is rejected') from strict_v2_fixture;

select * from finish();
rollback;