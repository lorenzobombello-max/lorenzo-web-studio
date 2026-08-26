begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(46);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status
) values
  ('10000000-0000-0000-0000-000000000001', 'Legacy test', 'legacy@example.test', 'business', 'EUR 1.500 - EUR 3.000', 'flexible', 'Legacy compatibility test request.', true, 'approved'),
  ('10000001-0000-0000-0000-000000000002', 'V2 draft test', 'draft@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'V2 draft compatibility test request.', true, 'approved'),
  ('10000002-0000-0000-0000-000000000003', 'V2 submit test', 'submit@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'V2 submit snapshot test request.', true, 'approved'),
  ('10000003-0000-0000-0000-000000000004', 'Malformed test', 'malformed@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Malformed snapshot rollback test request.', true, 'approved'),
  ('10000004-0000-0000-0000-000000000005', 'Constraint test', 'constraint@example.test', 'business', 'Minder dan EUR 1.800', 'flexible', 'Budget constraint compatibility test request.', true, 'approved');

insert into public.quote_request_intakes (
  quote_request_id, access_token_hash, access_token_expires_at,
  budget_update_category
) values
  ('10000000-0000-0000-0000-000000000001', repeat('a', 64), clock_timestamp() + interval '1 day', 'EUR 1.500 - EUR 3.000'),
  ('10000001-0000-0000-0000-000000000002', repeat('b', 64), clock_timestamp() + interval '1 day', null),
  ('10000002-0000-0000-0000-000000000003', repeat('c', 64), clock_timestamp() + interval '1 day', null),
  ('10000003-0000-0000-0000-000000000004', repeat('d', 64), clock_timestamp() + interval '1 day', null),
  ('10000004-0000-0000-0000-000000000005', repeat('e', 64), clock_timestamp() + interval '1 day', 'Tot EUR 1.500');

select lives_ok(
  $$update public.quote_request_intakes set budget_update_category = 'Tot EUR 1.500' where access_token_hash = repeat('e', 64)$$,
  'legacy lower budget label remains valid'
);
select lives_ok(
  $$update public.quote_request_intakes set budget_update_category = 'EUR 1.500 - EUR 3.000' where access_token_hash = repeat('e', 64)$$,
  'legacy middle budget label remains valid'
);
select lives_ok(
  $$update public.quote_request_intakes set budget_update_category = 'EUR 3.000 - EUR 6.000' where access_token_hash = repeat('e', 64)$$,
  'legacy upper budget label remains valid'
);
select lives_ok(
  $$update public.quote_request_intakes set budget_update_category = 'Meer dan EUR 6.000' where access_token_hash = repeat('e', 64)$$,
  'legacy unbounded budget label remains valid'
);

select lives_ok(
  $$update public.quote_request_intakes set budget_update_category = 'Minder dan EUR 1.800', budget_update_category_scheme = 'budget_guard_v1', budget_update_category_code = 'below_1800' where access_token_hash = repeat('e', 64)$$,
  'new below-1800 category is valid'
);
select lives_ok(
  $$update public.quote_request_intakes set budget_update_category = 'EUR 1.800 tot minder dan EUR 3.200', budget_update_category_code = '1800_to_below_3200' where access_token_hash = repeat('e', 64)$$,
  'new 1800-to-below-3200 category is valid'
);
select lives_ok(
  $$update public.quote_request_intakes set budget_update_category = 'EUR 3.200 t/m EUR 6.000', budget_update_category_code = '3200_to_6000_inclusive' where access_token_hash = repeat('e', 64)$$,
  'new category 3 includes exactly EUR 6,000'
);
select lives_ok(
  $$update public.quote_request_intakes set budget_update_category = 'Meer dan EUR 6.000', budget_update_category_code = 'above_6000' where access_token_hash = repeat('e', 64)$$,
  'new above-6000 category is valid'
);
select throws_matching(
  $$update public.quote_request_intakes set budget_update_category = 'Unknown range' where access_token_hash = repeat('e', 64)$$,
  '.*quote_request_intakes_(budget_update_category_valid|budget_category_v2_coherent).*',
  'unknown budget label is rejected'
);
select throws_matching(
  $$update public.quote_request_intakes set budget_update_category_code = '6000_and_above' where access_token_hash = repeat('e', 64)$$,
  '.*quote_request_intakes_budget_category_v2_coherent.*',
  'unknown budget code is rejected'
);

create temporary table phase2_quote_result as
select *
from public.create_quote_request_idempotent_v2(
  '20000000-0000-0000-0000-000000000001',
  repeat('9', 64),
  'V2 quote test',
  'individual',
  null,
  null,
  'not_checked',
  null,
  'not_checked',
  null,
  null,
  null,
  null,
  null,
  null,
  'quote-v2@example.test',
  null,
  'business',
  'EUR 3.200 t/m EUR 6.000',
  'flexible',
  'V2 quote creation compatibility test request.',
  true,
  repeat('8', 64),
  clock_timestamp() + interval '1 day',
  repeat('7', 64),
  'phase2-test',
  'budget_guard_v1',
  '3200_to_6000_inclusive'
);

select is(
  (select was_created from phase2_quote_result),
  true,
  'new quote caller can use the additive v2 RPC'
);
select is(
  (
    select request.budget_category_code
    from public.quote_requests as request
    inner join phase2_quote_result as result on result.request_id = request.id
  ),
  '3200_to_6000_inclusive',
  'quote v2 RPC stores the stable category without changing legacy RPCs'
);

select is(
  (
    select outcome
    from public.update_quote_request_intake(
      repeat('a', 64),
      'save_draft',
      '{"budget_update_category":"EUR 1.500 - EUR 3.000"}'::jsonb
    )
  ),
  'saved',
  'legacy RPC caller without Budget Guard data still saves'
);
select is(
  (
    select intake_data->>'budget_update_category'
    from public.inspect_quote_request_intake_details(repeat('a', 64))
  ),
  'EUR 1.500 - EUR 3.000',
  'legacy draft restores its original category without conversion'
);
select is(
  (select count(*)::integer from public.quote_request_pricing_snapshots),
  0,
  'legacy save does not calculate or create a snapshot'
);

select is(
  (
    select outcome
    from public.update_quote_request_intake_v2(
      repeat('b', 64),
      'save_draft',
      '{
        "budget_update_category":"EUR 3.200 t/m EUR 6.000",
        "budget_update_category_scheme":"budget_guard_v1",
        "budget_update_category_code":"3200_to_6000_inclusive",
        "primary_language":"nl",
        "additional_languages":["fr"]
      }'::jsonb
    )
  ),
  'saved',
  'v2 caller can save additive Budget Guard fields without a snapshot'
);
select is(
  (
    select intake_data->>'budget_update_category_code'
    from public.inspect_quote_request_intake_details_v2(repeat('b', 64))
  ),
  '3200_to_6000_inclusive',
  'v2 draft restores its stable category code'
);
select is(
  (
    select pricing_snapshot
    from public.inspect_quote_request_intake_details_v2(repeat('b', 64))
  ),
  null::jsonb,
  'draft preview is not stored as a historical snapshot'
);
select throws_matching(
  $$
    select *
    from public.update_quote_request_intake_v2(
      repeat('b', 64),
      'save_draft',
      '{}'::jsonb,
      null,
      null,
      '{"preview":true}'::jsonb
    )
  $$,
  'PRICING_SNAPSHOT_NOT_ALLOWED_FOR_DRAFT',
  'draft action rejects a historical snapshot'
);
select is(
  (
    select outcome
    from public.update_quote_request_intake_v2(
      repeat('b', 64),
      'save_draft',
      '{"additional_languages":null}'::jsonb
    )
  ),
  'saved',
  'v2 draft safely accepts null additive fields'
);
select is(
  (
    select intake_data->'additional_languages'
    from public.inspect_quote_request_intake_details_v2(repeat('b', 64))
  ),
  'null'::jsonb,
  'null additive field restores as null without legacy conversion'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.update_quote_request_intake_v2(text,text,jsonb,text,timestamp with time zone,jsonb)',
    'execute'
  ),
  'anon cannot execute intake v2 RPC'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.update_quote_request_intake_v2(text,text,jsonb,text,timestamp with time zone,jsonb)',
    'execute'
  ),
  'authenticated cannot execute intake v2 RPC'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.update_quote_request_intake_v2(text,text,jsonb,text,timestamp with time zone,jsonb)',
    'execute'
  ),
  'service role can execute intake v2 RPC'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.create_quote_request_idempotent_v2(uuid,text,text,text,text,text,text,text,text,timestamp with time zone,text,text,text,text,text,text,text,text,text,text,text,boolean,text,timestamp with time zone,text,text,text,text)',
    'execute'
  ),
  'anon cannot execute quote v2 RPC'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_quote_request_idempotent_v2(uuid,text,text,text,text,text,text,text,text,timestamp with time zone,text,text,text,text,text,text,text,text,text,text,text,boolean,text,timestamp with time zone,text,text,text,text)',
    'execute'
  ),
  'authenticated cannot execute quote v2 RPC'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.create_quote_request_idempotent_v2(uuid,text,text,text,text,text,text,text,text,timestamp with time zone,text,text,text,text,text,text,text,text,text,text,text,boolean,text,timestamp with time zone,text,text,text,text)',
    'execute'
  ),
  'service role can execute quote v2 RPC'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.inspect_quote_request_intake_details_v2(text)',
    'execute'
  ),
  'anon cannot execute intake inspection v2 RPC'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.inspect_quote_request_intake_details_v2(text)',
    'execute'
  ),
  'authenticated cannot execute intake inspection v2 RPC'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.inspect_quote_request_intake_details_v2(text)',
    'execute'
  ),
  'service role can execute intake inspection v2 RPC'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.inspect_submitted_intake_for_admin_v2(text)',
    'execute'
  ),
  'anon cannot execute admin inspection v2 RPC'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.inspect_submitted_intake_for_admin_v2(text)',
    'execute'
  ),
  'authenticated cannot execute admin inspection v2 RPC'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.inspect_submitted_intake_for_admin_v2(text)',
    'execute'
  ),
  'service role can execute admin inspection v2 RPC'
);

select is(
  obj_description(
    'public.update_quote_request_intake_v2(text,text,jsonb,text,timestamp with time zone,jsonb)'::regprocedure,
    'pg_proc'
  ),
  'Trusted server-side mutation boundary. p_budget_guard_snapshot is authoritative only when supplied by service-role backend code; browsers and frontend clients must never construct or persist authoritative pricing snapshots directly.',
  'authoritative snapshot boundary is documented in database metadata'
);

create temporary table phase2_fixture as
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
    "confirmation":true,
    "budget_update_category":"EUR 3.200 t/m EUR 6.000",
    "budget_update_category_scheme":"budget_guard_v1",
    "budget_update_category_code":"3200_to_6000_inclusive",
    "primary_language":"nl",
    "additional_languages":[]
  }'::jsonb as intake_data,
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
      "appliedRules":[{
        "ruleId":"starter_floor",
        "mode":"from",
        "amountMinor":180000,
        "quantity":1,
        "knownMinimumContributionMinor":180000
      }]
    },
    "packageAdvice":{
      "status":"none",
      "reasons":[],
      "advisoryOnly":true,
      "selectedPackage":null
    },
    "budgetEvaluation":{
      "categoryCode":"3200_to_6000_inclusive",
      "status":"possibly_compatible_with_category",
      "outsideBudgetWishes":[]
    }
  }'::jsonb as snapshot;

select is(
  (
    select outcome
    from phase2_fixture as fixture
    cross join lateral public.update_quote_request_intake_v2(
      repeat('c', 64),
      'submit',
      fixture.intake_data,
      repeat('1', 64),
      clock_timestamp() + interval '1 day',
      fixture.snapshot
    )
  ),
  'submitted',
  'v2 submit atomically stores intake and Budget Guard snapshot'
);
select is(
  (select count(*)::integer from public.quote_request_pricing_snapshots),
  1,
  'exactly one submitted snapshot exists'
);
select is(
  (
    select (calculation->>'knownMinimumMinor')::integer
    from public.quote_request_pricing_snapshots
  ),
  180000,
  'known indicative minimum is stored historically'
);
select is(
  (
    select pricing_snapshot->'budgetEvaluation'->>'categoryCode'
    from public.inspect_submitted_intake_for_admin_v2(repeat('1', 64))
  ),
  '3200_to_6000_inclusive',
  'admin v2 inspection returns the stored category and snapshot'
);
select is(
  (
    select result.pricing_snapshot->'calculation'->>'knownMinimumMinor'
    from phase2_fixture as fixture
    cross join lateral public.update_quote_request_intake_v2(
      repeat('c', 64),
      'submit',
      fixture.intake_data,
      repeat('1', 64),
      clock_timestamp() + interval '1 day',
      '{"tampered":true}'::jsonb
    ) as result
  ),
  '180000',
  'idempotent resubmit returns the historical snapshot without recalculation'
);
select is(
  (select count(*)::integer from public.quote_request_pricing_snapshots),
  1,
  'idempotent resubmit cannot create a second snapshot'
);
select throws_matching(
  $$update public.quote_request_pricing_snapshots set config_version = '2.0.0'$$,
  'PRICING_SNAPSHOT_IMMUTABLE',
  'submitted historical snapshot is immutable'
);

select throws_matching(
  $$
    select *
    from public.update_quote_request_intake_v2(
      repeat('d', 64),
      'submit',
      (select intake_data from phase2_fixture),
      repeat('2', 64),
      clock_timestamp() + interval '1 day',
      jsonb_set(
        (select snapshot from phase2_fixture),
        '{pricingConfigHash}',
        '"invalid"'::jsonb
      )
    )
  $$,
  '.*quote_request_pricing_snapshots_config_hash_valid.*',
  'malformed Budget Guard snapshot is rejected'
);
select is(
  (
    select status::text
    from public.quote_request_intakes
    where access_token_hash = repeat('d', 64)
  ),
  'invited',
  'rejected snapshot rolls back the intake submission'
);
select is(
  (
    select count(*)::integer
    from public.quote_request_pricing_snapshots as snapshot
    inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id
    where intake.access_token_hash = repeat('d', 64)
  ),
  0,
  'rejected snapshot leaves no historical pricing row'
);

select is(
  (
    select constraint_definition.confdeltype::text
    from pg_constraint as constraint_definition
    where constraint_definition.conrelid = 'public.quote_request_pricing_snapshots'::regclass
      and constraint_definition.contype = 'f'
  ),
  'c',
  'snapshot foreign key explicitly uses ON DELETE CASCADE'
);

set local session_replication_role = replica;
delete from lws_internal.operator_dossier_assignments
where quote_request_id = '10000002-0000-0000-0000-000000000003';
set local session_replication_role = origin;

delete from public.quote_requests
where id = '10000002-0000-0000-0000-000000000003';

select is(
  (select count(*)::integer from public.quote_request_pricing_snapshots),
  0,
  'controlled parent deletion removes the immutable snapshot through the lifecycle cascade'
);

select * from finish();
rollback;