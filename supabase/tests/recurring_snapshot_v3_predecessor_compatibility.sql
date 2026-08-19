begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(4);

create function pg_temp.assert_approved_strict_v3_predecessor(p_definition text)
returns void
language plpgsql
as $$
begin
  if encode(extensions.digest(convert_to(p_definition, 'UTF8'), 'sha256'), 'hex') <>
    '7f24bf90b5ed7617b8fd0a425af82768e9570f60e69b831f9ee78038d24fe8c0' then
    raise exception 'STRICT_V3_APPROVED_PREDECESSOR_NOT_FOUND';
  end if;
end;
$$;

select lives_ok(
  $$select pg_temp.assert_approved_strict_v3_predecessor(
    pg_get_functiondef(
      'public.is_strict_pricing_snapshot_v3(smallint,text,text,jsonb,jsonb,jsonb,jsonb,jsonb)'::regprocedure
    )
  )$$,
  'exact 20260818044749 predecessor is accepted'
);

select throws_matching(
  $$select pg_temp.assert_approved_strict_v3_predecessor(
    replace(
      pg_get_functiondef(
        'public.is_strict_pricing_snapshot_v3(smallint,text,text,jsonb,jsonb,jsonb,jsonb,jsonb)'::regprocedure
      ),
      'v_floor := 180000',
      'v_floor := 180001'
    )
  )$$,
  'STRICT_V3_APPROVED_PREDECESSOR_NOT_FOUND',
  'tampered predecessor remains fail-closed'
);

select ok(public.is_strict_pricing_snapshot_v3(
  3::smallint,
  '2026-08-16-v3',
  repeat('a', 64),
  '{
    "standardPages":["home"],"standardPageCount":1,"primaryLanguage":null,
    "additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]
  }'::jsonb,
  '{
    "basis":"package_floor","currency":"EUR","vatBasis":"exclusive",
    "knownMinimumMinor":180000,"containsFromPricing":true,
    "manualReviewRequired":false,"manualReasons":[],
    "appliedRules":[{
      "ruleId":"starter_v1_floor","mode":"from","amountMinor":180000,
      "quantity":1,"knownMinimumContributionMinor":180000
    }]
  }'::jsonb,
  '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}'::jsonb,
  '{
    "contractVersion":2,"evidenceProvenance":"budget_guard_v2",
    "categoryScheme":"budget_guard_v2","categoryCode":"above_6000",
    "originalLabel":"Meer dan EUR 6.000",
    "status":"unbounded_category_indeterminate","outsideBudgetWishes":null
  }'::jsonb,
  '{
    "id":"starter_v1","version":1,"label":"Starter","priceMode":"from",
    "floorMinor":180000,"standardPageLimit":5,"includedCorrectionRounds":1,
    "entitlementSetId":"normal_web_v1","entitlements":[
      "responsive_design","technical_foundation","navigation","browser_compatibility",
      "technical_seo_base","testing_and_delivery","standard_contact_form","social_links",
      "google_maps","whatsapp","normal_gallery_reviews","public_downloads",
      "supplied_content_media_processing","normal_ai_image_support","primary_language"
    ]
  }'::jsonb
), 'resulting strict V3 function retains active Snapshot V3 behavior');

select has_column(
  'public',
  'quote_request_pricing_snapshots',
  'recurring_services',
  'recurring-services persistence remains installed'
);

select * from finish();
rollback;
