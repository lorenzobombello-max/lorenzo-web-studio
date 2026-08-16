begin;
select plan(13);

select has_function('public', 'is_valid_pricing_budget_evaluation_v2', array['jsonb']);
select ok(exists(
  select 1 from pg_trigger where tgname = 'trg_pricing_snapshot_budget_evidence' and not tgisinternal
), 'v2 snapshot binding trigger exists');

select ok(public.is_valid_pricing_budget_evaluation_v2(jsonb_build_object(
  'contractVersion', 2, 'evidenceProvenance', 'budget_guard_v2',
  'categoryScheme', 'budget_guard_v2', 'categoryCode', 'below_1800',
  'originalLabel', 'Minder dan EUR 1.800',
  'status', 'below_starter_starting_price', 'outsideBudgetWishes', true
)), 'v2 below 1800 category is valid');

select ok(public.is_valid_pricing_budget_evaluation_v2(jsonb_build_object(
  'contractVersion', 2, 'evidenceProvenance', 'budget_guard_v2',
  'categoryScheme', 'budget_guard_v2', 'categoryCode', '1800_to_below_3500',
  'originalLabel', 'EUR 1.800 tot minder dan EUR 3.500',
  'status', 'possibly_compatible_with_category', 'outsideBudgetWishes', false
)), 'v2 lower bounded category is valid');

select ok(public.is_valid_pricing_budget_evaluation_v2(jsonb_build_object(
  'contractVersion', 2, 'evidenceProvenance', 'budget_guard_v2',
  'categoryScheme', 'budget_guard_v2', 'categoryCode', '3500_to_6000_inclusive',
  'originalLabel', 'EUR 3.500 t/m EUR 6.000',
  'status', 'possibly_compatible_with_category', 'outsideBudgetWishes', false
)), 'v2 upper bounded category is valid');

select ok(public.is_valid_pricing_budget_evaluation_v2(jsonb_build_object(
  'contractVersion', 2, 'evidenceProvenance', 'budget_guard_v2',
  'categoryScheme', 'budget_guard_v2', 'categoryCode', 'above_6000',
  'originalLabel', 'Meer dan EUR 6.000',
  'status', 'unbounded_category_indeterminate', 'outsideBudgetWishes', null
)), 'v2 above 6000 category is valid');

select ok(public.is_valid_pricing_budget_evaluation_v2(jsonb_build_object(
  'contractVersion', 2, 'evidenceProvenance', 'budget_guard_v1',
  'categoryScheme', 'budget_guard_v1', 'categoryCode', '3200_to_6000_inclusive',
  'originalLabel', 'EUR 3.200 t/m EUR 6.000',
  'status', 'possibly_compatible_with_category', 'outsideBudgetWishes', false
)), 'historical v1 remains valid');

select isnt(public.is_valid_pricing_budget_evaluation_v2(jsonb_build_object(
  'contractVersion', 2, 'evidenceProvenance', 'budget_guard_v2',
  'categoryScheme', 'budget_guard_v2', 'categoryCode', '1800_to_below_3200',
  'originalLabel', 'EUR 1.800 tot minder dan EUR 3.200',
  'status', 'possibly_compatible_with_category', 'outsideBudgetWishes', false
)), true, 'v1 code cannot be mixed into v2');

select lives_ok($$insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description, privacy_consent,
  status, budget_category_scheme, budget_category_code
) values (
  'b6200000-0000-4000-8000-000000000001', 'Budget v2', 'budget-v2@example.test',
  'Bedrijfswebsite', 'EUR 1.800 tot minder dan EUR 3.500', 'Flexibel / nog te bepalen',
  'Budget Guard v2 fixture', true, 'approved', 'budget_guard_v2', '1800_to_below_3500'
)$$, 'new request accepts coherent v2 evidence');

select throws_ok($$insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description, privacy_consent,
  status, budget_category_scheme, budget_category_code
) values (
  'b6200000-0000-4000-8000-000000000002', 'Mixed budget', 'mixed@example.test',
  'Bedrijfswebsite', 'EUR 1.800 tot minder dan EUR 3.200', 'Flexibel / nog te bepalen',
  'Mixed fixture', true, 'approved', 'budget_guard_v2', '1800_to_below_3200'
)$$, '23514', null, 'table constraint rejects mixed v1/v2 evidence');

select ok(exists(
  select 1 from pg_constraint where conname = 'quote_requests_budget_category_v2_coherent'
), 'request coherence constraint remains present');

select ok(exists(
  select 1 from pg_constraint where conname = 'quote_request_intakes_budget_category_v2_coherent'
), 'intake coherence constraint remains present');

select ok(exists(
  select 1 from pg_constraint where conname = 'quote_request_pricing_snapshots_budget_evaluation_valid'
), 'snapshot validation constraint remains present');

select * from finish();
rollback;