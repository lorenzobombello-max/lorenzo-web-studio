begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(32);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, budget_category_scheme, budget_category_code
) values
  ('d2200000-0000-4000-8000-000000000001', 'Reset active', 'reset-active@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Reset active fixture.', true, 'approved', 'budget_guard_v2', 'above_6000'),
  ('d2200000-0000-4000-8000-000000000002', 'Reset submitted', 'reset-submitted@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Reset submitted fixture.', true, 'approved', 'budget_guard_v2', 'above_6000'),
  ('d2200000-0000-4000-8000-000000000003', 'Reset reviewed', 'reset-reviewed@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Reset reviewed fixture.', true, 'approved', 'budget_guard_v2', 'above_6000'),
  ('d2200000-0000-4000-8000-000000000004', 'Reset expired', 'reset-expired@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Reset expired fixture.', true, 'approved', 'budget_guard_v2', 'above_6000'),
  ('d2200000-0000-4000-8000-000000000005', 'Reset revoked', 'reset-revoked@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Reset revoked fixture.', true, 'approved', 'budget_guard_v2', 'above_6000'),
  ('d2200000-0000-4000-8000-000000000006', 'Reset other', 'reset-other@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Reset other fixture.', true, 'approved', 'budget_guard_v2', 'above_6000');

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_token_revoked_at, started_at, submitted_at, reviewed_at, created_at,
  business_description, target_audience, has_existing_website, existing_website_url,
  elements_to_keep, improvement_areas, website_goals, primary_conversion_goal,
  requested_pages, other_pages, requested_features, shop_required, shop_details,
  booking_required, booking_details, languages, design_styles, brand_status,
  logo_status, brand_colors, inspiration_sites, disliked_styles, content_status,
  image_status, image_support, domain_status, domain_name, hosting_status,
  hosting_support, maintenance_interest, seo_priority, seo_keywords, social_channels,
  integrations, deadline_date, deadline_reason, budget_confirmed,
  budget_update_category, budget_notes, priorities, additional_notes, confirmation,
  primary_language, additional_languages, page_scope_details, quote_form_details,
  multilingual_details, download_details, content_media_details, newsletter_details,
  hosting_maintenance_details, deadline_details, seo_details,
  budget_update_category_scheme, budget_update_category_code,
  selected_package_definition_id, draft_revision
) values (
  'd2210000-0000-4000-8000-000000000001', 'd2200000-0000-4000-8000-000000000001',
  'in_progress', repeat('a', 64), clock_timestamp() + interval '1 day', null,
  clock_timestamp() - interval '2 hours', null, null, clock_timestamp() - interval '3 hours',
  'Filled business', 'Filled audience', true, 'https://example.test', 'Keep', 'Improve',
  array['generate_leads'], 'Request quote', array['home','portfolio'], 'Other page',
  array['quote_form','multilingual'], true, '{"approx_product_count":5,"categories":true,"online_payments":true,"shipping":true,"pickup":false,"existing_catalog":false}'::jsonb,
  true, '{"tier":"widget","type":"appointments","existing_system":false,"existing_system_name":null,"calendar_integration":true}'::jsonb, array['nl','fr'], array['modern'], 'complete',
  'available', array['black'], array['https://example.test'], 'Disliked', 'complete',
  'sufficient', array['stock'], 'has_domain', 'example.test', 'has_hosting', 'yes',
  'yes', 'high', array['keyword'], array['linkedin'], array['crm'], date '2027-01-01',
  'Launch', true, 'Meer dan EUR 6.000', 'Budget notes', array['usability'], 'Notes', true,
  'nl', array['fr'], '{"portfolio":"normal"}'::jsonb,
  '{"structure_scope":"simple","form_count":1,"file_uploads":false,"database_workflow":false,"automated_processing":false,"review_approval":false,"custom_logic":false}'::jsonb,
  '{"final_translations_supplied":true,"same_structure":true,"translation_required":false,"seo_per_language":false,"advanced_seo_research":false,"language_specific_integrations":false,"complex_scope":false}'::jsonb,
  '{"access":"public"}'::jsonb,
  '{"copywriting_scope":"unknown","copy_page_count":1,"image_work_scope":"none","paid_stock_handling":false,"branding_tier":"existing"}'::jsonb,
  '{"scope":"new_service_setup","analytics":"standard","custom_integration":false}'::jsonb,
  '{"maintenance_interest":"yes","domain_service":"existing","maintenance_plan":"none"}'::jsonb,
  '{"commercially_critical":false,"hard_deadline":false}'::jsonb,
  '{"scope":"included","extra_language_seo":false,"advanced_language_seo":false}'::jsonb,
  'budget_guard_v2', 'above_6000', 'professional_v2', 5
);

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_token_revoked_at, started_at, submitted_at, reviewed_at, created_at,
  business_description, confirmation, admin_access_token_hash,
  admin_access_token_expires_at, draft_revision
) values
  ('d2210000-0000-4000-8000-000000000002', 'd2200000-0000-4000-8000-000000000002', 'submitted', repeat('b',64), clock_timestamp()+interval '1 day', null, clock_timestamp()-interval '2 hours', clock_timestamp()-interval '1 hour', null, clock_timestamp()-interval '3 hours', 'Submitted stays', true, repeat('1',64), clock_timestamp()+interval '1 day', 4),
  ('d2210000-0000-4000-8000-000000000003', 'd2200000-0000-4000-8000-000000000003', 'reviewed', repeat('7',64), clock_timestamp()+interval '1 day', null, clock_timestamp()-interval '3 hours', clock_timestamp()-interval '2 hours', clock_timestamp()-interval '1 hour', clock_timestamp()-interval '4 hours', 'Reviewed stays', true, repeat('2',64), clock_timestamp()+interval '1 day', 7),
  ('d2210000-0000-4000-8000-000000000004', 'd2200000-0000-4000-8000-000000000004', 'in_progress', repeat('8',64), clock_timestamp()-interval '1 minute', null, clock_timestamp()-interval '2 hours', null, null, clock_timestamp()-interval '3 hours', 'Expired stays', false, null, null, 2),
  ('d2210000-0000-4000-8000-000000000005', 'd2200000-0000-4000-8000-000000000005', 'in_progress', repeat('9',64), clock_timestamp()+interval '1 day', clock_timestamp()-interval '1 minute', clock_timestamp()-interval '2 hours', null, null, clock_timestamp()-interval '3 hours', 'Revoked stays', false, null, null, 2),
  ('d2210000-0000-4000-8000-000000000006', 'd2200000-0000-4000-8000-000000000006', 'in_progress', repeat('f',64), clock_timestamp()+interval '1 day', null, clock_timestamp()-interval '2 hours', null, null, clock_timestamp()-interval '3 hours', 'Other stays', false, null, null, 9);

create temporary table reset_identity_before as
select id, quote_request_id, access_token_hash, access_token_expires_at,
  access_token_revoked_at, created_at, started_at
from public.quote_request_intakes where access_token_hash = repeat('a',64);

create temporary table revision_save as
select * from public.save_quote_request_intake_draft_v2(
  repeat('a',64), 5,
  '{"business_description":"Revision-aware save"}'::jsonb,
  '{"primary_language":"nl"}'::jsonb
);

select is((select outcome from revision_save), 'saved', 'normal revision-aware draft save succeeds');
select is((select draft_revision from revision_save), 6::bigint, 'normal save increments revision');
select is((select draft_revision from public.inspect_quote_request_intake_details_v5(repeat('a',64))), 6::bigint, 'inspect atomically exposes current revision');
select is((select intake_data->>'business_description' from public.inspect_quote_request_intake_details_v5(repeat('a',64))), 'Revision-aware save', 'reload resumes saved draft data');

create temporary table stale_save as
select * from public.save_quote_request_intake_draft_v2(
  repeat('a',64), 5, '{"business_description":"Stale overwrite"}'::jsonb, '{}'::jsonb
);
select is((select outcome from stale_save), 'stale_revision', 'stale save is rejected');
select is((select business_description from public.quote_request_intakes where access_token_hash=repeat('a',64)), 'Revision-aware save', 'stale save cannot overwrite current data');
select is((select outcome from public.reset_quote_request_intake_draft_v1(repeat('a',64),5)), 'stale_revision', 'stale reset is rejected');

create temporary table reset_result as
select * from public.reset_quote_request_intake_draft_v1(repeat('a',64),6);
select is((select outcome from reset_result), 'reset', 'current revision reset succeeds');
select is((select draft_revision from reset_result), 7::bigint, 'reset increments revision');
select ok((select
  business_description is null and target_audience is null and has_existing_website is null
  and existing_website_url is null and elements_to_keep is null and improvement_areas is null
  and website_goals = '{}'::text[] and primary_conversion_goal is null
  and requested_pages = '{}'::text[] and other_pages is null and requested_features = '{}'::text[]
  and shop_required = false and shop_details is null and booking_required = false and booking_details is null
  and languages = array['nl']::text[] and design_styles = '{}'::text[] and brand_status is null
  and logo_status is null and brand_colors = '{}'::text[] and inspiration_sites = '{}'::text[]
  and disliked_styles is null and content_status is null and image_status is null
  and image_support = '{}'::text[] and domain_status is null and domain_name is null
  and hosting_status is null and hosting_support is null and maintenance_interest is null
  and seo_priority is null and seo_keywords = '{}'::text[] and social_channels = '{}'::text[]
  and integrations = '{}'::text[] and deadline_date is null and deadline_reason is null
  and budget_confirmed is null and budget_update_category is null and budget_notes is null
  and priorities = '{}'::text[] and additional_notes is null and confirmation = false
  and primary_language is null and additional_languages is null and page_scope_details is null
  and quote_form_details is null and multilingual_details is null and download_details is null
  and content_media_details is null and newsletter_details is null and hosting_maintenance_details is null
  and deadline_details is null and seo_details is null and budget_update_category_scheme is null
  and budget_update_category_code is null and selected_package_definition_id is null
  from public.quote_request_intakes where access_token_hash=repeat('a',64)),
  'reset clears every legacy, Phase-D, budget, and package answer to schema defaults');
select ok((select row(before.id,before.quote_request_id,before.access_token_hash,before.access_token_expires_at,before.access_token_revoked_at,before.created_at,before.started_at)
  is not distinct from row(after.id,after.quote_request_id,after.access_token_hash,after.access_token_expires_at,after.access_token_revoked_at,after.created_at,after.started_at)
  from reset_identity_before before join public.quote_request_intakes after on after.id=before.id),
  'reset preserves identity, capability, creation audit, and original started_at');
select is((select draft_revision from public.inspect_quote_request_intake_details_v5(repeat('a',64))), 7::bigint, 'same personal link reloads after reset');
select is((select intake_data->>'business_description' from public.inspect_quote_request_intake_details_v5(repeat('a',64))), null::text, 'old data remains absent after reset reload');

create temporary table refill as
select * from public.save_quote_request_intake_draft_v2(repeat('a',64),7,'{"business_description":"Started again"}'::jsonb,'{"primary_language":"nl"}'::jsonb);
select is((select outcome from refill), 'saved', 'draft can be filled again after reset');
select is((select draft_revision from refill), 8::bigint, 'post-reset save advances revision');
select is((select intake_data->>'business_description' from public.inspect_quote_request_intake_details_v5(repeat('a',64))), 'Started again', 'post-reset save resumes through inspect');

select is((select outcome from public.reset_quote_request_intake_draft_v1(repeat('b',64),4)), 'not_editable', 'submitted reset is rejected');
select is((select outcome from public.reset_quote_request_intake_draft_v1(repeat('7',64),7)), 'not_editable', 'reviewed reset is rejected');
select is((select outcome from public.reset_quote_request_intake_draft_v1(repeat('0',64),0)), 'invalid_token', 'unknown token is rejected');
select throws_ok($$select * from public.reset_quote_request_intake_draft_v1(repeat('8',64),2)$$, 'P0001', 'INTAKE_ACCESS_EXPIRED', 'expired token returns lifecycle denial');
select is((select outcome from public.reset_quote_request_intake_draft_v1(repeat('9',64),2)), 'invalid_token', 'revoked token is rejected');
select is((select business_description from public.quote_request_intakes where access_token_hash=repeat('f',64)), 'Other stays', 'another intake cannot be reset');
select is((select count(*)::integer from public.quote_requests where id::text like 'd2200000-%'), 6, 'reset deletes no quote request');
select is((select count(*)::integer from public.quote_request_intakes where id::text like 'd2210000-%'), 6, 'reset deletes no intake');
select is((select business_description from public.quote_request_intakes where access_token_hash=repeat('b',64)), 'Submitted stays', 'submitted answer data remains unchanged');
select is((select admin_access_token_hash from public.quote_request_intakes where access_token_hash=repeat('b',64)), repeat('1',64), 'submitted admin capability remains unchanged');
select is((select draft_revision from public.quote_request_intakes where access_token_hash=repeat('b',64)), 4::bigint, 'submitted revision remains unchanged');
select ok(position('quote_request_pricing_snapshots' in pg_get_functiondef('public.reset_quote_request_intake_draft_v1(text,bigint)'::regprocedure))=0, 'reset RPC cannot mutate pricing snapshots');
select ok(not has_function_privilege('anon','public.reset_quote_request_intake_draft_v1(text,bigint)','execute') and not has_function_privilege('authenticated','public.reset_quote_request_intake_draft_v1(text,bigint)','execute'), 'public roles cannot execute reset RPC');
select ok(has_function_privilege('service_role','public.reset_quote_request_intake_draft_v1(text,bigint)','execute'), 'service role can execute reset RPC');
select ok(not has_function_privilege('anon','public.save_quote_request_intake_draft_v2(text,bigint,jsonb,jsonb)','execute') and has_function_privilege('service_role','public.save_quote_request_intake_draft_v2(text,bigint,jsonb,jsonb)','execute'), 'revision-aware save is service-role-only');
select throws_matching($$select * from public.reset_quote_request_intake_draft_v1(repeat('a',64),-1)$$,'INVALID_EXPECTED_REVISION','negative expected revision is rejected');

select * from finish();
rollback;
