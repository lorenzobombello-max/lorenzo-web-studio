begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(17);

create temporary table fix2_fixture as
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

create function pg_temp.fix2_valid(
  p_normalized_scope jsonb default null,
  p_calculation jsonb default null,
  p_package_advice jsonb default null,
  p_budget_evaluation jsonb default null
)
returns boolean
language sql
as $$
  select public.is_strict_pricing_snapshot_v2(
    2::smallint,
    '1.0.0',
    repeat('a', 64),
    coalesce(p_normalized_scope, fixture.normalized_scope),
    coalesce(p_calculation, fixture.calculation),
    coalesce(p_package_advice, fixture.package_advice),
    coalesce(p_budget_evaluation, fixture.budget_evaluation)
  )
  from fix2_fixture as fixture
$$;

select ok(pg_temp.fix2_valid(), 'canonical one-page automatic snapshot remains valid');

select ok(not pg_temp.fix2_valid(
  p_package_advice => jsonb_set(
    jsonb_set(package_advice, '{status}', '"consider_professional"'),
    '{reasons}',
    '["invented_reason"]'
  )
), 'package advice must match the exact page-count matrix')
from fix2_fixture;

select ok(not pg_temp.fix2_valid(
  p_normalized_scope => jsonb_set(
    normalized_scope,
    '{modules}',
    '[{"id":"invented","classification":"manual","evidence":[]}]'
  )
), 'unknown module IDs are rejected')
from fix2_fixture;

select ok(not pg_temp.fix2_valid(
  p_normalized_scope => jsonb_set(
    normalized_scope,
    '{modules}',
    '[{"id":"forms","classification":"invented","evidence":[]}]'
  )
), 'unknown module classifications are rejected')
from fix2_fixture;

select ok(not pg_temp.fix2_valid(
  p_calculation => jsonb_set(
    calculation,
    '{appliedRules}',
    '[
      {"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000},
      {"ruleId":"invented","mode":"included","quantity":1,"knownMinimumContributionMinor":0}
    ]'
  )
), 'unknown rule IDs are rejected')
from fix2_fixture;

select ok(not pg_temp.fix2_valid(
  p_calculation => jsonb_set(calculation, '{appliedRules,0,mode}', '"fixed"')
), 'canonical rule IDs require their canonical modes')
from fix2_fixture;

select ok(not pg_temp.fix2_valid(
  p_calculation => jsonb_set(
    calculation,
    '{appliedRules}',
    '[
      {"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000},
      {"ruleId":"extra_standard_page","mode":"fixed","amountMinor":20000,"quantity":0,"knownMinimumContributionMinor":0}
    ]'
  )
), 'zero-quantity rules are rejected')
from fix2_fixture;

select ok(not pg_temp.fix2_valid(
  p_calculation => jsonb_set(
    calculation,
    '{appliedRules}',
    (calculation->'appliedRules') || (calculation->'appliedRules')
  )
), 'duplicate rule IDs are rejected')
from fix2_fixture;

select ok(not pg_temp.fix2_valid(
  p_calculation => jsonb_set(
    calculation,
    '{appliedRules}',
    (calculation->'appliedRules') || '[{"ruleId":"contact_form","mode":"included","quantity":1,"knownMinimumContributionMinor":0}]'
  )
), 'canonical rules unrelated to normalized scope are rejected')
from fix2_fixture;

select ok(not pg_temp.fix2_valid(
  p_normalized_scope => jsonb_set(
    normalized_scope,
    '{modules}',
    '[{"id":"forms","classification":"contact","evidence":["contact_form_intent"]}]'
  )
), 'rules required by normalized scope cannot be omitted')
from fix2_fixture;

select ok(not pg_temp.fix2_valid(
  p_calculation => jsonb_set(
    jsonb_set(calculation, '{manualReviewRequired}', 'true'),
    '{manualReasons}',
    '["invented_reason"]'
  ),
  p_budget_evaluation => jsonb_set(
    jsonb_set(budget_evaluation, '{status}', '"manual_review_required"'),
    '{outsideBudgetWishes}',
    'null'
  )
), 'manual reasons must identify a canonical manual rule or the 13-page boundary')
from fix2_fixture;

select ok(pg_temp.fix2_valid(
  p_normalized_scope => '{
    "standardPages":["home","about","services","portfolio","contact","products"],
    "standardPageCount":6,
    "primaryLanguage":"nl",
    "additionalLanguages":[],
    "unknownLanguages":[],
    "modules":[],
    "manualComponents":[]
  }',
  p_calculation => '{
    "basis":"starter_floor","currency":"EUR","vatBasis":"exclusive",
    "knownMinimumMinor":200000,"containsFromPricing":true,
    "manualReviewRequired":false,"manualReasons":[],
    "appliedRules":[
      {"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000},
      {"ruleId":"extra_standard_page","mode":"fixed","amountMinor":20000,"quantity":1,"knownMinimumContributionMinor":20000}
    ]
  }',
  p_package_advice => '{
    "status":"consider_professional",
    "reasons":["standard_page_count_above_starter_scope"],
    "advisoryOnly":true,"selectedPackage":null
  }'
), 'canonical six-page advisory snapshot remains valid');

select ok(pg_temp.fix2_valid(
  p_normalized_scope => '{
    "standardPages":["home","about","services","portfolio","team","pricing","faq","contact","reviews","blog","jobs","gallery","products"],
    "standardPageCount":13,
    "primaryLanguage":"nl",
    "additionalLanguages":[],
    "unknownLanguages":[],
    "modules":[],
    "manualComponents":[]
  }',
  p_calculation => '{
    "basis":"starter_floor","currency":"EUR","vatBasis":"exclusive",
    "knownMinimumMinor":340000,"containsFromPricing":true,
    "manualReviewRequired":true,
    "manualReasons":["standard_page_count_above_professional_scope"],
    "appliedRules":[
      {"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000},
      {"ruleId":"extra_standard_page","mode":"fixed","amountMinor":20000,"quantity":8,"knownMinimumContributionMinor":160000}
    ]
  }',
  p_package_advice => '{
    "status":"manual_scope_review",
    "reasons":["standard_page_count_above_professional_scope"],
    "advisoryOnly":true,"selectedPackage":null
  }',
  p_budget_evaluation => '{
    "contractVersion":2,"evidenceProvenance":"budget_guard_v1",
    "categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive",
    "originalLabel":"EUR 3.200 t/m EUR 6.000",
    "status":"manual_review_required","outsideBudgetWishes":null
  }'
), 'canonical thirteen-page manual snapshot remains valid');

select ok(pg_temp.fix2_valid(
  p_normalized_scope => jsonb_set(
    normalized_scope,
    '{modules}',
    '[{"id":"forms","classification":"contact","evidence":["contact_form_intent"]}]'
  ),
  p_calculation => jsonb_set(
    calculation,
    '{appliedRules}',
    (calculation->'appliedRules') || '[{"ruleId":"contact_form","mode":"included","quantity":1,"knownMinimumContributionMinor":0}]'
  )
), 'canonical included module rule remains valid')
from fix2_fixture;

select ok(pg_temp.fix2_valid(
  p_normalized_scope => jsonb_set(
    normalized_scope,
    '{modules}',
    '[{"id":"shop","classification":"manual","evidence":["shop_required"]}]'
  ),
  p_calculation => jsonb_set(
    jsonb_set(
      jsonb_set(calculation, '{manualReviewRequired}', 'true'),
      '{manualReasons}',
      '["shop_manual"]'
    ),
    '{appliedRules}',
    (calculation->'appliedRules') || '[{"ruleId":"shop_manual","mode":"manual","quantity":1,"knownMinimumContributionMinor":0}]'
  ),
  p_budget_evaluation => jsonb_set(
    jsonb_set(budget_evaluation, '{status}', '"manual_review_required"'),
    '{outsideBudgetWishes}',
    'null'
  )
), 'canonical manual module rule remains valid')
from fix2_fixture;

select ok(not pg_temp.fix2_valid(
  p_normalized_scope => jsonb_set(
    normalized_scope,
    '{manualComponents}',
    '["invented_component"]'
  )
), 'unknown manual component IDs are rejected')
from fix2_fixture;

select ok(not pg_temp.fix2_valid(
  p_normalized_scope => jsonb_set(
    normalized_scope,
    '{standardPages}',
    '["invented_page"]'
  )
), 'unknown normalized standard-page IDs are rejected')
from fix2_fixture;

select * from finish();
rollback;