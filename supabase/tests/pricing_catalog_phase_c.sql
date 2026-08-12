begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(3);

create temporary table phase_c_professional_v2 as
select
  '{
    "standardPages":["home","about","services","portfolio","team","pricing","faq","contact","reviews","blog","jobs","gallery"],
    "standardPageCount":12,"primaryLanguage":"nl","additionalLanguages":[],
    "unknownLanguages":[],"modules":[],"manualComponents":[]
  }'::jsonb as normalized_scope,
  '{
    "basis":"package_floor","currency":"EUR","vatBasis":"exclusive",
    "knownMinimumMinor":395000,"containsFromPricing":true,
    "manualReviewRequired":false,"manualReasons":[],"appliedRules":[
      {"ruleId":"professional_v2_floor","mode":"from","amountMinor":350000,
       "quantity":1,"knownMinimumContributionMinor":350000},
      {"ruleId":"extra_standard_page","mode":"fixed","amountMinor":22500,
       "quantity":2,"knownMinimumContributionMinor":45000}
    ]
  }'::jsonb as calculation,
  '{"status":"manual_scope_review","reasons":["standard_page_count_above_professional_scope"],"advisoryOnly":true,"selectedPackage":null}'::jsonb as package_advice,
  '{
    "contractVersion":2,"evidenceProvenance":"budget_guard_v1",
    "categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive",
    "originalLabel":"EUR 3.200 t/m EUR 6.000",
    "status":"possibly_compatible_with_category","outsideBudgetWishes":false
  }'::jsonb as budget_evaluation,
  '{
    "id":"professional_v2","version":2,"label":"Professional","priceMode":"from",
    "floorMinor":350000,"standardPageLimit":10,"includedCorrectionRounds":2,
    "entitlementSetId":"normal_web_v1","entitlements":[
      "responsive_design","technical_foundation","navigation","browser_compatibility",
      "technical_seo_base","testing_and_delivery","standard_contact_form","social_links",
      "google_maps","whatsapp","normal_gallery_reviews","public_downloads",
      "supplied_content_media_processing","normal_ai_image_support","primary_language",
      "blog_news"
    ]
  }'::jsonb as package_definition;

select ok(public.is_strict_pricing_snapshot_v3(
  3::smallint, '2026-08-12-v1', repeat('a', 64), normalized_scope,
  calculation, package_advice, budget_evaluation, package_definition
), 'Professional v2 with fixed EUR 225 page overage is valid')
from phase_c_professional_v2;

select ok(not public.is_strict_pricing_snapshot_v3(
  3::smallint, '2026-08-12-v1', repeat('a', 64), normalized_scope,
  jsonb_set(calculation, '{appliedRules,0,amountMinor}', '320000'::jsonb),
  package_advice, budget_evaluation, package_definition
), 'Professional v2 cannot use the historical EUR 3.200 floor')
from phase_c_professional_v2;

select ok(public.is_strict_pricing_snapshot_v3(
  3::smallint,
  '2.0.0',
  repeat('b', 64),
  '{
    "standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl",
    "additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]
  }'::jsonb,
  '{
    "basis":"package_floor","currency":"EUR","vatBasis":"exclusive",
    "knownMinimumMinor":320000,"containsFromPricing":true,
    "manualReviewRequired":false,"manualReasons":[],
    "appliedRules":[{"ruleId":"professional_v1_floor","mode":"from",
      "amountMinor":320000,"quantity":1,"knownMinimumContributionMinor":320000}]
  }'::jsonb,
  '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}'::jsonb,
  '{
    "contractVersion":2,"evidenceProvenance":"budget_guard_v1",
    "categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive",
    "originalLabel":"EUR 3.200 t/m EUR 6.000",
    "status":"possibly_compatible_with_category","outsideBudgetWishes":false
  }'::jsonb,
  '{
    "id":"professional_v1","version":1,"label":"Professional","priceMode":"from",
    "floorMinor":320000,"standardPageLimit":12,"includedCorrectionRounds":2,
    "entitlementSetId":"normal_web_v1","entitlements":[
      "responsive_design","technical_foundation","navigation","browser_compatibility",
      "technical_seo_base","testing_and_delivery","standard_contact_form","social_links",
      "google_maps","whatsapp","normal_gallery_reviews","public_downloads",
      "supplied_content_media_processing","normal_ai_image_support","primary_language"
    ]
  }'::jsonb
), 'historical Professional v1 remains valid under config 2.0.0');

select * from finish();
rollback;
