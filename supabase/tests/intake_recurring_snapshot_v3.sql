begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(22);

select has_column('public', 'quote_request_pricing_snapshots', 'recurring_services', 'recurring services have durable snapshot storage');
select has_function('public', 'is_valid_pricing_recurring_services_v1', array['jsonb'], 'recurring service validator exists');
select ok(public.is_valid_pricing_recurring_services_v1(null), 'legacy and no-Care snapshots remain valid');
select ok(public.is_valid_pricing_recurring_services_v1('[{"productId":"care","amountMinor":4900,"unit":"month"}]'), 'Care contract is valid');
select ok(public.is_valid_pricing_recurring_services_v1('[{"productId":"care_plus","amountMinor":9900,"unit":"month"}]'), 'Care+ contract is valid');
select ok(not public.is_valid_pricing_recurring_services_v1('[{"productId":"care","amountMinor":9900,"unit":"month"}]'), 'Care amount substitution is rejected');
select ok(not public.is_valid_pricing_recurring_services_v1('[{"productId":"care","amountMinor":4900,"unit":"year"}]'), 'unsupported cadence is rejected');
select ok(not public.is_valid_pricing_recurring_services_v1('[{"productId":"care","amountMinor":4900,"unit":"month","label":"Care"}]'), 'invented recurring fields are rejected');

create temporary table recurring_snapshot_fixture (
  package_id text primary key,
  access_hash text not null,
  admin_hash text not null,
  snapshot jsonb not null
);

insert into recurring_snapshot_fixture values
('starter_v1', repeat('7',64), repeat('8',64), '{
  "snapshotContractVersion":3,"pricingConfigVersion":"2026-08-16-v3",
  "pricingConfigHash":"bca1b8581e6ac05ee7647ecbb17b94c1cd89c3b9bcde7a728e18e3f864e96cbe",
  "normalizedScope":{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":null,"additionalLanguages":[],"unknownLanguages":[],"modules":[{"id":"hosting_maintenance","classification":"catalog","evidence":["hosting_maintenance"]}],"manualComponents":[],"recurringServices":[{"productId":"care"}]},
  "calculation":{"basis":"package_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":180000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_v1_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000}]},
  "packageAdvice":{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null},
  "budgetEvaluation":{"contractVersion":2,"evidenceProvenance":"budget_guard_v2","categoryScheme":"budget_guard_v2","categoryCode":"above_6000","originalLabel":"Meer dan EUR 6.000","status":"unbounded_category_indeterminate","outsideBudgetWishes":null},
  "packageDefinition":{"id":"starter_v1","version":1,"label":"Starter","priceMode":"from","floorMinor":180000,"standardPageLimit":5,"includedCorrectionRounds":1,"entitlementSetId":"normal_web_v1","entitlements":["responsive_design","technical_foundation","navigation","browser_compatibility","technical_seo_base","testing_and_delivery","standard_contact_form","social_links","google_maps","whatsapp","normal_gallery_reviews","public_downloads","supplied_content_media_processing","normal_ai_image_support","primary_language"]},
  "recurringServices":[{"productId":"care","amountMinor":4900,"unit":"month"}]
}'::jsonb),
('professional_v2', repeat('9',64), repeat('a',64), '{
  "snapshotContractVersion":3,"pricingConfigVersion":"2026-08-16-v3",
  "pricingConfigHash":"bca1b8581e6ac05ee7647ecbb17b94c1cd89c3b9bcde7a728e18e3f864e96cbe",
  "normalizedScope":{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":null,"additionalLanguages":[],"unknownLanguages":[],"modules":[{"id":"hosting_maintenance","classification":"catalog","evidence":["hosting_maintenance"]}],"manualComponents":[],"recurringServices":[{"productId":"care_plus"}]},
  "calculation":{"basis":"package_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":350000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"professional_v2_floor","mode":"from","amountMinor":350000,"quantity":1,"knownMinimumContributionMinor":350000}]},
  "packageAdvice":{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null},
  "budgetEvaluation":{"contractVersion":2,"evidenceProvenance":"budget_guard_v2","categoryScheme":"budget_guard_v2","categoryCode":"above_6000","originalLabel":"Meer dan EUR 6.000","status":"unbounded_category_indeterminate","outsideBudgetWishes":null},
  "packageDefinition":{"id":"professional_v2","version":2,"label":"Professional","priceMode":"from","floorMinor":350000,"standardPageLimit":10,"includedCorrectionRounds":2,"entitlementSetId":"normal_web_v1","entitlements":["responsive_design","technical_foundation","navigation","browser_compatibility","technical_seo_base","testing_and_delivery","standard_contact_form","social_links","google_maps","whatsapp","normal_gallery_reviews","public_downloads","supplied_content_media_processing","normal_ai_image_support","primary_language","blog_news"]},
  "recurringServices":[{"productId":"care_plus","amountMinor":9900,"unit":"month"}]
}'::jsonb);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, budget_category_scheme, budget_category_code
) values
('19a10000-0000-4000-8000-000000000001','Care submit','care@example.test','business','Meer dan EUR 6.000','flexible','Care persistence fixture',true,'approved','budget_guard_v2','above_6000'),
('19a10000-0000-4000-8000-000000000002','Care plus submit','care-plus@example.test','business','Meer dan EUR 6.000','flexible','Care plus persistence fixture',true,'approved','budget_guard_v2','above_6000');

insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at
) values
('19a11000-0000-4000-8000-000000000001','19a10000-0000-4000-8000-000000000001',repeat('7',64),clock_timestamp()+interval '1 day'),
('19a11000-0000-4000-8000-000000000002','19a10000-0000-4000-8000-000000000002',repeat('9',64),clock_timestamp()+interval '1 day');

create function pg_temp.submit_recurring(p_package_id text)
returns table(outcome text, pricing_snapshot jsonb)
language plpgsql
as $$
declare f recurring_snapshot_fixture%rowtype;
begin
  select * into strict f from recurring_snapshot_fixture where package_id=p_package_id;
  return query select result.outcome, result.pricing_snapshot
  from public.update_quote_request_intake_v5(
    f.access_hash,'submit',jsonb_build_object(
      'business_description','Complete recurring service submission',
      'target_audience','Local businesses','primary_conversion_goal','Request quote',
      'website_goals',jsonb_build_array('generate_leads'),
      'requested_pages',jsonb_build_array('home'),'requested_features','[]'::jsonb,
      'design_styles',jsonb_build_array('modern'),'brand_status','complete',
      'logo_status','available','content_status','complete','image_status','sufficient',
      'domain_status','has_domain','hosting_status','has_hosting',
      'maintenance_interest','yes','seo_priority','basic',
      'priorities',jsonb_build_array('usability'),'confirmation',true,
      'budget_update_category','Meer dan EUR 6.000',
      'budget_update_category_scheme','budget_guard_v2',
      'budget_update_category_code','above_6000',
      'selected_package_definition_id',f.package_id,
      'hosting_maintenance_details',jsonb_build_object(
        'maintenance_plan',case when f.package_id='starter_v1' then 'care' else 'care_plus' end
      )
    ),f.admin_hash,clock_timestamp()+interval '1 day',f.snapshot,
    jsonb_build_object('algorithmVersion','hmac-sha256-v1','keyId','v1','mac',repeat('b',64))
  ) as result;
end;
$$;

select is((select outcome from pg_temp.submit_recurring('starter_v1')),'submitted','Starter + Care submits');
select is((select outcome from pg_temp.submit_recurring('professional_v2')),'submitted','Professional + Care+ submits');
select is((select recurring_services from public.quote_request_pricing_snapshots where intake_id='19a11000-0000-4000-8000-000000000001'),'[{"unit":"month","productId":"care","amountMinor":4900}]'::jsonb,'Care survives persistence');
select is((select recurring_services from public.quote_request_pricing_snapshots where intake_id='19a11000-0000-4000-8000-000000000002'),'[{"unit":"month","productId":"care_plus","amountMinor":9900}]'::jsonb,'Care+ survives persistence');
select is((select (pricing_snapshot->'recurringServices') from public.inspect_quote_request_intake_details_v4(repeat('7',64))),'[{"unit":"month","productId":"care","amountMinor":4900}]'::jsonb,'intake readback preserves Care');
select is((select integrity_snapshot->'recurringServices' from public.inspect_customer_pricing_read_v3(repeat('7',64))),'[{"unit":"month","productId":"care","amountMinor":4900}]'::jsonb,'customer integrity root preserves Care');
select is((select integrity_snapshot->'recurringServices' from public.inspect_admin_pricing_read_v3(repeat('a',64))),'[{"unit":"month","productId":"care_plus","amountMinor":9900}]'::jsonb,'admin integrity root preserves Care+');
select is((select (pricing_snapshot->'recurringServices') from pg_temp.submit_recurring('starter_v1')),'[{"unit":"month","productId":"care","amountMinor":4900}]'::jsonb,'duplicate submit returns stored recurring service');
select is((select count(*)::integer from public.quote_request_pricing_snapshots where intake_id='19a11000-0000-4000-8000-000000000001'),1,'duplicate submit creates no second snapshot');
select throws_matching($$update public.quote_request_pricing_snapshots set recurring_services='[]' where intake_id='19a11000-0000-4000-8000-000000000001'$$,'PRICING_SNAPSHOT_IMMUTABLE','recurring services inherit snapshot immutability');
select is((select (calculation->>'knownMinimumMinor')::integer from public.quote_request_pricing_snapshots where intake_id='19a11000-0000-4000-8000-000000000001'),180000,'Care does not inflate Starter one-time minimum');
select is((select (calculation->>'knownMinimumMinor')::integer from public.quote_request_pricing_snapshots where intake_id='19a11000-0000-4000-8000-000000000002'),350000,'Care+ does not inflate Professional one-time minimum');
select is((select count(*)::integer from public.quote_request_email_jobs where quote_request_id='19a10000-0000-4000-8000-000000000001' and kind='intake_submitted_notification'),1,'duplicate submit keeps one notification job');
select ok((select snapshot_present from public.inspect_customer_pricing_read_v3(repeat('7',64))),'customer pricing read remains valid');

select * from finish();
rollback;
