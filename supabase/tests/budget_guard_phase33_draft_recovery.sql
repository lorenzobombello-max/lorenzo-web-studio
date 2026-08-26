begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(15);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, budget_category_scheme, budget_category_code
) values
  (
    '33000000-0000-4000-8000-000000000001', 'Professional v2 draft',
    'professional-v2-draft@example.test', 'business', 'Meer dan EUR 6.000',
    'flexible', 'Professional v2 draft fixture.', true, 'approved',
    'budget_guard_v2', 'above_6000'
  ),
  (
    '33000001-0000-4000-8000-000000000002', 'Failed draft retry',
    'failed-draft-retry@example.test', 'business', 'Meer dan EUR 6.000',
    'flexible', 'Failed draft retry fixture.', true, 'approved',
    'budget_guard_v2', 'above_6000'
  );

insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at,
  status, started_at, submitted_at, confirmation, created_at
) values
  (
    '33001000-0000-4000-8000-000000000001',
    '33000000-0000-4000-8000-000000000001', repeat('3', 64),
    clock_timestamp() + interval '1 day', 'invited', null, null, false,
    clock_timestamp()
  ),
  (
    '33001000-0000-4000-8000-000000000002',
    '33000001-0000-4000-8000-000000000002', repeat('4', 64),
    clock_timestamp() + interval '1 day', 'invited', null, null, false,
    clock_timestamp()
  );

create temporary table phase33_saved as
select *
from public.update_quote_request_intake_with_evidence(
  repeat('3', 64),
  'save_draft',
  '{"business_description":"Saved Professional v2 draft","budget_update_category":"Meer dan EUR 6.000"}'::jsonb,
  '{
    "primary_language":"nl",
    "additional_languages":["fr","en"],
    "multilingual_details":{
      "final_translations_supplied":true,"same_structure":true,
      "translation_required":false,"seo_per_language":false,
      "advanced_seo_research":false,"language_specific_integrations":false,
      "complex_scope":false
    },
    "newsletter_details":{"scope":"new_service_setup","analytics":"standard","custom_integration":false},
    "content_media_details":{
      "copywriting_scope":"unknown","image_work_scope":"none",
      "paid_stock_handling":true,"branding_tier":"existing"
    },
    "hosting_maintenance_details":{
      "maintenance_interest":"yes","domain_service":"existing","maintenance_plan":"none"
    },
    "seo_details":{"scope":"included","extra_language_seo":false,"advanced_language_seo":false},
    "budget_update_category":"Meer dan EUR 6.000",
    "budget_update_category_scheme":"budget_guard_v2",
    "budget_update_category_code":"above_6000",
    "selected_package_definition_id":"professional_v2"
  }'::jsonb
);

select is((select outcome from phase33_saved), 'saved', 'A: Professional v2 save_draft succeeds');
select is((select intake_status from phase33_saved), 'in_progress', 'A: successful draft enters in_progress');
select is(
  (select business_description from public.quote_request_intakes where access_token_hash = repeat('3', 64)),
  'Saved Professional v2 draft',
  'A: valid draft data is persisted'
);
select is(
  (select selected_package_definition_id from public.quote_request_intakes where access_token_hash = repeat('3', 64)),
  'professional_v2',
  'A: Professional v2 package evidence is persisted'
);
select is(
  (select intake_data->>'business_description' from public.inspect_quote_request_intake_details_v4(repeat('3', 64))),
  'Saved Professional v2 draft',
  'B: reload inspection restores saved draft data'
);
select is(
  (select intake_data->>'selected_package_definition_id' from public.inspect_quote_request_intake_details_v4(repeat('3', 64))),
  'professional_v2',
  'B: reload inspection restores Professional v2 package evidence'
);

select throws_matching(
  $$select * from public.update_quote_request_intake_with_evidence(
    repeat('4', 64),
    'save_draft',
    '{"unexpected":true}'::jsonb,
    '{"primary_language":"fr","selected_package_definition_id":"professional_v2"}'::jsonb
  )$$,
  'INVALID_INTAKE_DATA',
  'C: forced legacy write failure is surfaced'
);

select is(
  (select status::text from public.quote_request_intakes where access_token_hash = repeat('4', 64)),
  'invited',
  'E: failed save does not change lifecycle status'
);
select is(
  (select started_at from public.quote_request_intakes where access_token_hash = repeat('4', 64)),
  null::timestamptz,
  'E: failed save does not partially set started_at'
);
select is(
  (select primary_language from public.quote_request_intakes where access_token_hash = repeat('4', 64)),
  null::text,
  'E: failed save rolls back evidence fields'
);
select is(
  (select selected_package_definition_id from public.quote_request_intakes where access_token_hash = repeat('4', 64)),
  null::text,
  'E: failed save rolls back package evidence'
);
select is(
  (select intake_status from public.inspect_quote_request_intake_details_v4(repeat('4', 64))),
  'invited',
  'C: intake remains accessible after failed save'
);

create temporary table phase33_retry as
select *
from public.update_quote_request_intake_with_evidence(
  repeat('4', 64),
  'save_draft',
  '{"business_description":"Retry succeeded","budget_update_category":"Meer dan EUR 6.000"}'::jsonb,
  '{
    "primary_language":"nl",
    "content_media_details":{
      "copywriting_scope":"unknown","image_work_scope":"none",
      "paid_stock_handling":true,"branding_tier":"existing"
    },
    "budget_update_category":"Meer dan EUR 6.000",
    "budget_update_category_scheme":"budget_guard_v2",
    "budget_update_category_code":"above_6000",
    "selected_package_definition_id":"professional_v2"
  }'::jsonb
);

select is((select outcome from phase33_retry), 'saved', 'D: retry after failed save succeeds');
select is(
  (select intake_data->>'business_description' from public.inspect_quote_request_intake_details_v4(repeat('4', 64))),
  'Retry succeeded',
  'D: retry state is coherent and reloadable'
);
select is(
  (select count(*)::integer from public.quote_request_intakes where quote_request_id = '33000001-0000-4000-8000-000000000002'),
  1,
  'D: retry does not create duplicate intake records'
);

select * from finish();
rollback;
