begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(30);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status
) values
  ('26000000-0000-0000-0000-000000000001', 'Evidence valid', 'evidence-valid@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'Valid evidence bridge fixture.', true, 'approved'),
  ('26000000-0000-0000-0000-000000000002', 'Evidence submitted', 'evidence-submitted@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'Submitted evidence bridge fixture.', true, 'approved'),
  ('26000000-0000-0000-0000-000000000003', 'Evidence expired', 'evidence-expired@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'Expired evidence bridge fixture.', true, 'approved'),
  ('26000000-0000-0000-0000-000000000004', 'Evidence rollback', 'evidence-rollback@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'Rollback evidence bridge fixture.', true, 'approved'),
  ('26000000-0000-0000-0000-000000000005', 'Evidence legacy', 'evidence-legacy@example.test', 'business', 'EUR 1.500 - EUR 3.000', 'flexible', 'Legacy evidence bridge fixture.', true, 'approved');

insert into public.quote_request_intakes (
  quote_request_id, access_token_hash, access_token_expires_at,
  status, started_at, submitted_at, confirmation, budget_update_category,
  primary_language, created_at
) values
  ('26000000-0000-0000-0000-000000000001', repeat('1', 64), clock_timestamp() + interval '1 day', 'invited', null, null, false, null, null, clock_timestamp()),
  ('26000000-0000-0000-0000-000000000002', repeat('2', 64), clock_timestamp() + interval '1 day', 'submitted', clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour', true, null, 'nl', clock_timestamp() - interval '3 hours'),
  ('26000000-0000-0000-0000-000000000003', repeat('3', 64), clock_timestamp() - interval '1 day', 'invited', null, null, false, null, null, clock_timestamp() - interval '2 days'),
  ('26000000-0000-0000-0000-000000000004', repeat('4', 64), clock_timestamp() + interval '1 day', 'invited', null, null, false, null, null, clock_timestamp()),
  ('26000000-0000-0000-0000-000000000005', repeat('5', 64), clock_timestamp() + interval '1 day', 'invited', null, null, false, 'EUR 1.500 - EUR 3.000', null, clock_timestamp());

create temporary table phase26_valid_result as
select *
from public.update_quote_request_intake_evidence(
  repeat('1', 64),
  '{
    "primary_language":"nl",
    "additional_languages":["fr","en"],
    "page_scope_details":{"reviews":"normal","blog":"complex","jobs":"unknown","gallery":"normal"},
    "quote_form_details":{"classification":"extended","file_uploads":false,"database_workflow":false,"automated_processing":false,"review_approval":false,"custom_logic":false,"form_count":1},
    "multilingual_details":{"final_translations_supplied":true,"same_structure":true,"extensive_seo":false,"language_specific_integrations":false,"complex_scope":false},
    "download_details":{"access":"public"},
    "content_media_details":{"copywriting_scope":"light","image_work_scope":"standard","paid_stock_handling":false},
    "newsletter_details":{"scope":"simple_existing_service"},
    "hosting_maintenance_details":{"hosting_support":"advice","maintenance_interest":"maybe"},
    "deadline_details":{"commercially_critical":false,"hard_deadline":true},
    "seo_details":{"extensive_services":false},
    "budget_update_category":"EUR 3.200 t/m EUR 6.000",
    "budget_update_category_scheme":"budget_guard_v1",
    "budget_update_category_code":"3200_to_6000_inclusive"
  }'::jsonb
);

select is(
  (select outcome from phase26_valid_result),
  'saved',
  'valid raw evidence is saved'
);
select is(
  (select intake_status from phase26_valid_result),
  'in_progress',
  'evidence save follows the existing editable lifecycle'
);
select is(
  (select primary_language from public.quote_request_intakes where access_token_hash = repeat('1', 64)),
  'nl',
  'primary language is stored'
);
select is(
  (select additional_languages from public.quote_request_intakes where access_token_hash = repeat('1', 64)),
  array['fr', 'en']::text[],
  'bounded additional languages are stored'
);
select is(
  (select page_scope_details->>'blog' from public.quote_request_intakes where access_token_hash = repeat('1', 64)),
  'complex',
  'closed nested evidence is stored'
);
select is(
  (select budget_update_category_code from public.quote_request_intakes where access_token_hash = repeat('1', 64)),
  '3200_to_6000_inclusive',
  'stable category 3 code is stored'
);
select is(
  (select budget_update_category from public.quote_request_intakes where access_token_hash = repeat('1', 64)),
  'EUR 3.200 t/m EUR 6.000',
  'category 3 human label explicitly includes exactly EUR 6,000'
);
select is(
  (
    select intake_data->'deadline_details'->>'hard_deadline'
    from public.inspect_quote_request_intake_details_v2(repeat('1', 64))
  ),
  'true',
  'saved evidence can later be read through the existing v2 inspection route'
);

select is(
  (
    select outcome
    from public.update_quote_request_intake(
      repeat('5', 64),
      'save_draft',
      '{"business_description":"Legacy draft remains operational"}'::jsonb
    )
  ),
  'saved',
  'existing legacy draft RPC remains functional'
);

select throws_matching(
  $$select * from public.update_quote_request_intake_evidence(repeat('1', 64), '{"unexpected":true}'::jsonb)$$,
  'UNKNOWN_INTAKE_EVIDENCE_FIELD',
  'unknown top-level evidence key is rejected'
);
select throws_matching(
  $$
    select *
    from public.update_quote_request_intake_evidence(
      repeat('1', 64),
      '{
        "knownMinimumMinor":180000,
        "appliedRules":[],
        "manualReviewRequired":false,
        "manualReasons":[],
        "packageAdvice":{},
        "budgetEvaluation":{},
        "pricingConfigVersion":"1.0.0",
        "pricingConfigHash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "pricingSnapshot":{}
      }'::jsonb
    )
  $$,
  'AUTHORITATIVE_PRICING_DATA_NOT_ALLOWED',
  'authoritative pricing output is rejected as a class'
);
select throws_matching(
  $$select * from public.update_quote_request_intake_evidence(repeat('1', 64), '[]'::jsonb)$$,
  'INVALID_INTAKE_EVIDENCE',
  'non-object evidence payload is rejected'
);
select throws_matching(
  $$select * from public.update_quote_request_intake_evidence(repeat('1', 64), '{"page_scope_details":{"blog":"normal","internal_price":200}}'::jsonb)$$,
  'INVALID_PAGE_SCOPE_DETAILS',
  'unknown nested evidence key is rejected'
);
select throws_matching(
  $$select * from public.update_quote_request_intake_evidence(repeat('1', 64), '{"multilingual_details":{"same_structure":"yes"}}'::jsonb)$$,
  'INVALID_MULTILINGUAL_DETAILS',
  'malformed nested evidence type is rejected'
);
select throws_matching(
  $$select * from public.update_quote_request_intake_evidence(repeat('1', 64), '{"additional_languages":["nl","fr","en","de","it","es","pt","pl","sv"]}'::jsonb)$$,
  'INVALID_ADDITIONAL_LANGUAGES',
  'oversized evidence array is rejected'
);
select throws_matching(
  $$
    select *
    from public.update_quote_request_intake_evidence(
      repeat('1', 64),
      '{
        "budget_update_category":"Meer dan EUR 6.000",
        "budget_update_category_scheme":"budget_guard_v1",
        "budget_update_category_code":"3200_to_6000_inclusive"
      }'::jsonb
    )
  $$,
  'INCOHERENT_BUDGET_EVIDENCE',
  'incoherent budget label scheme and code are rejected'
);

select is(
  (
    select outcome
    from public.update_quote_request_intake_evidence(
      repeat('5', 64),
      '{"primary_language":"nl"}'::jsonb
    )
  ),
  'saved',
  'bridge can add evidence beside an existing legacy budget'
);
select is(
  (select budget_update_category from public.quote_request_intakes where access_token_hash = repeat('5', 64)),
  'EUR 1.500 - EUR 3.000',
  'legacy budget label is not rewritten or converted'
);
select is(
  (select budget_update_category_code from public.quote_request_intakes where access_token_hash = repeat('5', 64)),
  null::text,
  'legacy budget does not receive a guessed stable code'
);

select is(
  (
    select outcome
    from public.update_quote_request_intake_evidence(
      repeat('2', 64),
      '{"primary_language":"fr"}'::jsonb
    )
  ),
  'not_editable',
  'submitted intake cannot be changed through the bridge'
);
select is(
  (select primary_language from public.quote_request_intakes where access_token_hash = repeat('2', 64)),
  'nl',
  'submitted evidence remains unchanged'
);
select is(
  (
    select outcome
    from public.update_quote_request_intake_evidence(
      repeat('3', 64),
      '{"primary_language":"nl"}'::jsonb
    )
  ),
  'invalid_token',
  'expired token is rejected without mutation'
);
select throws_matching(
  $$select * from public.update_quote_request_intake_evidence('invalid', '{}'::jsonb)$$,
  'INVALID_ACCESS_TOKEN_HASH',
  'malformed token hash is rejected'
);

select throws_matching(
  $$
    select *
    from public.update_quote_request_intake_evidence(
      repeat('4', 64),
      '{
        "primary_language":"nl",
        "budget_update_category":"EUR 3.200 t/m EUR 6.000",
        "budget_update_category_scheme":"budget_guard_v1",
        "budget_update_category_code":"above_6000"
      }'::jsonb
    )
  $$,
  'INCOHERENT_BUDGET_EVIDENCE',
  'invalid mixed update fails atomically'
);
select is(
  (select primary_language from public.quote_request_intakes where access_token_hash = repeat('4', 64)),
  null::text,
  'failed evidence operation leaves no partial update'
);
select is(
  (select count(*)::integer from public.quote_request_pricing_snapshots),
  0,
  'evidence bridge creates zero pricing snapshots'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.update_quote_request_intake_evidence(text,jsonb)',
    'execute'
  ),
  'anon cannot execute evidence bridge'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.update_quote_request_intake_evidence(text,jsonb)',
    'execute'
  ),
  'authenticated cannot execute evidence bridge'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.update_quote_request_intake_evidence(text,jsonb)',
    'execute'
  ),
  'service role can execute evidence bridge'
);
select is(
  obj_description(
    'public.update_quote_request_intake_evidence(text,jsonb)'::regprocedure,
    'pg_proc'
  ),
  'Service-role-only bridge for validated raw Budget Guard evidence. It cannot submit an intake, accept authoritative pricing output, or create a pricing snapshot.',
  'database metadata documents the raw-only security boundary'
);

select * from finish();
rollback;