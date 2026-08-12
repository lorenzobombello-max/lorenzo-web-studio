begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(20);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status
) values
  ('d6000000-0000-4000-8000-000000000001', 'D60 draft', 'd60-draft@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'D60 draft fixture.', true, 'approved'),
  ('d6000000-0000-4000-8000-000000000002', 'D60 submit', 'd60-submit@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'D60 submit fixture.', true, 'approved');

insert into public.quote_request_intakes (
  quote_request_id, access_token_hash, access_token_expires_at,
  status, confirmation
) values
  ('d6000000-0000-4000-8000-000000000001', repeat('6', 64), clock_timestamp() + interval '1 day', 'invited', false),
  ('d6000000-0000-4000-8000-000000000002', repeat('7', 64), clock_timestamp() + interval '1 day', 'invited', false);

select has_function(
  'public',
  'is_valid_phase_d_intake_evidence',
  array['quote_request_intakes'],
  'D60 closed-schema validator exists'
);
select has_trigger(
  'public',
  'quote_request_intakes',
  'quote_request_intakes_validate_phase_d_evidence',
  'D60 evidence trigger exists'
);
select ok(
  has_function_privilege('service_role', 'public.update_quote_request_intake_evidence(text,jsonb)', 'execute'),
  'service role can execute the D60 evidence bridge'
);
select ok(
  not has_function_privilege('service_role', 'public.update_quote_request_intake_evidence_v1(text,jsonb)', 'execute'),
  'service role cannot bypass D60 through the retired bridge'
);

create temporary table d60_save_result as
select * from public.update_quote_request_intake_evidence(
  repeat('6', 64),
  '{
    "page_scope_details":{"portfolio":"dynamic","gallery":"advanced","reviews":"live","search":"advanced"},
    "multilingual_details":{"translation_required":true,"seo_per_language":true,"advanced_seo_research":false},
    "download_details":{"access":"document_flow"},
    "content_media_details":{"copywriting_scope":"substantial","copy_page_count":4,"image_work_scope":"ai_set","paid_stock_handling":true,"branding_tier":"extended"},
    "newsletter_details":{"scope":"automation_or_segmentation","analytics":"advanced","custom_integration":true},
    "hosting_maintenance_details":{"domain_service":"complex_migration","maintenance_plan":"care_plus"},
    "seo_details":{"scope":"complex","extra_language_seo":true,"advanced_language_seo":true}
  }'::jsonb
);

select is((select outcome from d60_save_result), 'saved', 'D60 evidence bridge accepts the complete exposed schema');
select is(
  (select intake_data->'page_scope_details'->>'portfolio' from public.inspect_quote_request_intake_details_v4(repeat('6', 64))),
  'dynamic',
  'inspect returns the dynamic portfolio tier'
);
select is(
  (select intake_data->'content_media_details'->>'branding_tier' from public.inspect_quote_request_intake_details_v4(repeat('6', 64))),
  'extended',
  'inspect returns the branding tier'
);
select is(
  (select intake_data->'hosting_maintenance_details'->>'maintenance_plan' from public.inspect_quote_request_intake_details_v4(repeat('6', 64))),
  'care_plus',
  'inspect returns the recurring maintenance selection'
);

select lives_ok(
  $$update public.quote_request_intakes
    set shop_required = true,
        shop_details = '{"approx_product_count":24,"categories":true,"online_payments":true,"shipping":true,"pickup":false,"existing_catalog":false,"complex_product_count":2,"payment_provider_count":2,"shipping_scope":"complex","customer_accounts":true,"catalog_import":true,"erp_api":false}'::jsonb
    where access_token_hash = repeat('6', 64)$$,
  'legacy mutation path accepts the closed D60 shop schema'
);
select lives_ok(
  $$update public.quote_request_intakes
    set booking_required = true,
        booking_details = '{"tier":"advanced","type":"appointments","existing_system":true,"existing_system_name":"Calendly","calendar_integration":true}'::jsonb
    where access_token_hash = repeat('6', 64)$$,
  'legacy mutation path accepts the closed D60 booking schema'
);
select throws_matching(
  $$update public.quote_request_intakes
    set shop_details = shop_details || '{"payment_provider_count":0}'::jsonb
    where access_token_hash = repeat('6', 64)$$,
  'INVALID_PHASE_D_INTAKE_EVIDENCE',
  'shop tier ranges are enforced in the database'
);
select throws_matching(
  $$update public.quote_request_intakes
    set booking_details = booking_details || '{"existing_system_name":null}'::jsonb
    where access_token_hash = repeat('6', 64)$$,
  'INVALID_PHASE_D_INTAKE_EVIDENCE',
  'booking existing-system dependency is enforced in the database'
);
select throws_matching(
  $$select * from public.update_quote_request_intake_evidence(
    repeat('6', 64),
    '{"page_scope_details":{"portfolio":"complex"}}'::jsonb
  )$$,
  'INVALID_PHASE_D_INTAKE_EVIDENCE',
  'evidence bridge rejects an invalid portfolio tier'
);
select throws_matching(
  $$select * from public.update_quote_request_intake_evidence(
    repeat('6', 64),
    '{"newsletter_details":{"analytics":"enterprise"}}'::jsonb
  )$$,
  'INVALID_PHASE_D_INTAKE_EVIDENCE',
  'evidence bridge rejects an unknown analytics tier'
);
select throws_matching(
  $$select * from public.update_quote_request_intake_evidence(
    repeat('6', 64),
    '{"content_media_details":{"catalogPrice":12345}}'::jsonb
  )$$,
  'INVALID_PHASE_D_INTAKE_EVIDENCE',
  'closed evidence objects reject client-supplied pricing data'
);

create temporary table d60_submit_result as
select * from public.update_quote_request_intake_with_evidence(
  repeat('7', 64),
  'submit',
  '{
    "business_description":"Complete D60 submit description",
    "target_audience":"Local businesses",
    "primary_conversion_goal":"Request a quote",
    "website_goals":["generate_leads"],
    "requested_pages":["home","portfolio"],
    "requested_features":["downloads"],
    "design_styles":["modern"],
    "brand_status":"complete",
    "logo_status":"available",
    "content_status":"complete",
    "image_status":"sufficient",
    "domain_status":"has_domain",
    "hosting_status":"has_hosting",
    "maintenance_interest":"no",
    "seo_priority":"basic",
    "priorities":["usability"],
    "confirmation":true,
    "budget_update_category":"EUR 3.200 t/m EUR 6.000"
  }'::jsonb,
  '{
    "selected_package_definition_id":"professional_v1",
    "primary_language":"nl",
    "page_scope_details":{"portfolio":"dynamic"},
    "download_details":{"access":"portal"},
    "budget_update_category":"EUR 3.200 t/m EUR 6.000",
    "budget_update_category_scheme":"budget_guard_v1",
    "budget_update_category_code":"3200_to_6000_inclusive"
  }'::jsonb,
  repeat('8', 64),
  clock_timestamp() + interval '1 day'
);

select is((select outcome from d60_submit_result), 'submitted', 'D60 evidence submits through the transactional orchestrator');
select is(
  (select status::text from public.quote_request_intakes where access_token_hash = repeat('7', 64)),
  'submitted',
  'D60 submit closes the intake lifecycle'
);
select is(
  (select intake_data->'download_details'->>'access' from public.inspect_quote_request_intake_details_v4(repeat('7', 64))),
  'portal',
  'submitted D60 evidence remains readable'
);
select is(
  (select selected_package_definition_id from public.quote_request_intakes where access_token_hash = repeat('7', 64)),
  'professional_v1',
  'selected package survives D60 submit'
);
select throws_matching(
  $$select * from public.update_quote_request_intake_evidence(
    repeat('6', 64),
    '{"knownMinimumMinor":12345}'::jsonb
  )$$,
  'AUTHORITATIVE_PRICING_DATA_NOT_ALLOWED',
  'authoritative pricing remains server-only'
);

select * from finish();
rollback;
