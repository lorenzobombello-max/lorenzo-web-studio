begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(14);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, budget_category_scheme, budget_category_code
) values (
  '33000000-0000-0000-0000-000000000001',
  'Phase 31C concurrency',
  'phase31c@example.test',
  'business',
  'EUR 3.200 t/m EUR 6.000',
  'flexible',
  'Phase 31C authoritative evidence fixture.',
  true,
  'approved',
  'budget_guard_v1',
  '3200_to_6000_inclusive'
);

insert into public.quote_request_intakes (
  quote_request_id, access_token_hash, access_token_expires_at
) values (
  '33000000-0000-0000-0000-000000000001',
  repeat('8', 64),
  clock_timestamp() + interval '1 day'
);

create temporary table phase31c_fixture as
select
  '{
    "business_description":"A complete business description",
    "target_audience":"Small businesses",
    "primary_conversion_goal":"Request a quote",
    "website_goals":["leads"],
    "requested_pages":["home","quote_request"],
    "requested_features":["quote_form"],
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
    "confirmation":true
  }'::jsonb as sparse_submit,
  '{
    "quote_form_details":{
      "structure_scope":"basic_single_section",
      "file_uploads":false,
      "database_workflow":false,
      "automated_processing":false,
      "review_approval":false,
      "custom_logic":false,
      "form_count":1
    }
  }'::jsonb as evidence_a,
  '{
    "quote_form_details":{
      "structure_scope":"extended_standard_structure",
      "file_uploads":true,
      "database_workflow":false,
      "automated_processing":false,
      "review_approval":false,
      "custom_logic":false,
      "form_count":2
    }
  }'::jsonb as evidence_b,
  '{
    "snapshotContractVersion":2,
    "pricingConfigVersion":"1.0.0",
    "pricingConfigHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "normalizedScope":{
      "standardPages":["home"],
      "standardPageCount":1,
      "primaryLanguage":"nl",
      "additionalLanguages":[],
      "unknownLanguages":[],
      "modules":[{
        "id":"forms",
        "classification":"simple",
        "evidence":["requested_pages.quote_request","requested_features.quote_form"]
      }],
      "manualComponents":[]
    },
    "calculation":{
      "basis":"starter_floor",
      "currency":"EUR",
      "vatBasis":"exclusive",
      "knownMinimumMinor":200000,
      "containsFromPricing":true,
      "manualReviewRequired":false,
      "manualReasons":[],
      "appliedRules":[]
    },
    "packageAdvice":{
      "status":"none",
      "reasons":[],
      "advisoryOnly":true,
      "selectedPackage":null
    },
    "budgetEvaluation":{
      "contractVersion":2,
      "evidenceProvenance":"budget_guard_v1",
      "categoryScheme":"budget_guard_v1",
      "categoryCode":"3200_to_6000_inclusive",
      "originalLabel":"EUR 3.200 t/m EUR 6.000",
      "status":"possibly_compatible_with_category",
      "outsideBudgetWishes":false
    }
  }'::jsonb as snapshot_a;

create temporary table phase31c_initial_draft as
select result.*
from phase31c_fixture as fixture
cross join lateral public.update_quote_request_intake_with_evidence(
  repeat('8', 64),
  'save_draft',
  fixture.sparse_submit - 'confirmation',
  fixture.evidence_a,
  null,
  null
) as result;

select is(
  (select outcome from phase31c_initial_draft),
  'saved',
  'draft A is stored before authoritative inspection'
);

create temporary table phase31c_authoritative_a as
select inspection.intake_data || fixture.sparse_submit as submit_data
from phase31c_fixture as fixture
cross join lateral public.inspect_quote_request_intake_details_v3(
  repeat('8', 64)
) as inspection;

create temporary table phase31c_concurrent_draft as
select result.*
from phase31c_fixture as fixture
cross join lateral public.update_quote_request_intake_with_evidence(
  repeat('8', 64),
  'save_draft',
  '{}'::jsonb,
  fixture.evidence_b,
  null,
  null
) as result;

select is(
  (select outcome from phase31c_concurrent_draft),
  'saved',
  'concurrent draft B commits after inspection of A'
);
select is(
  (
    select quote_form_details->>'structure_scope'
    from public.quote_request_intakes
    where access_token_hash = repeat('8', 64)
  ),
  'extended_standard_structure',
  'database contains evidence B immediately before v3 finalization'
);

create temporary table phase31c_submit_result as
select result.*
from phase31c_fixture as fixture
cross join phase31c_authoritative_a as authoritative
cross join lateral public.update_quote_request_intake_v3(
  repeat('8', 64),
  'submit',
  authoritative.submit_data,
  repeat('9', 64),
  clock_timestamp() + interval '1 day',
  fixture.snapshot_a
) as result;

select is((select outcome from phase31c_submit_result), 'submitted', 'v3 submits authoritative state A');
select is(
  (
    select status::text
    from public.quote_request_intakes
    where access_token_hash = repeat('8', 64)
  ),
  'submitted',
  'submitted lifecycle status commits with snapshot A'
);
select is(
  (
    select quote_form_details->>'structure_scope'
    from public.quote_request_intakes
    where access_token_hash = repeat('8', 64)
  ),
  'basic_single_section',
  'complete authoritative payload A overwrites concurrent evidence B'
);
select is(
  (
    select normalized_evidence->'modules'->0->>'classification'
    from public.quote_request_pricing_snapshots as snapshot
    inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id
    where intake.access_token_hash = repeat('8', 64)
  ),
  'simple',
  'immutable snapshot stores the classification calculated from evidence A'
);
select is(
  (
    select count(*)::integer
    from public.quote_request_pricing_snapshots as snapshot
    inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id
    where intake.access_token_hash = repeat('8', 64)
  ),
  1,
  'first successful submit creates exactly one snapshot'
);
select is(
  (
    select count(*)::integer
    from public.quote_request_pricing_snapshots as snapshot
    left join public.quote_request_intakes as intake on intake.id = snapshot.intake_id
    where intake.id is null
  ),
  0,
  'interleaving leaves no orphan snapshot'
);

create temporary table phase31c_retry_result as
select result.*
from phase31c_fixture as fixture
cross join lateral public.update_quote_request_intake_v3(
  repeat('8', 64),
  'submit',
  fixture.evidence_b,
  null,
  null,
  jsonb_set(
    fixture.snapshot_a,
    '{pricingConfigHash}',
    to_jsonb(repeat('b', 64))
  )
) as result;

select is((select outcome from phase31c_retry_result), 'already_submitted', 'retry remains idempotent');
select is(
  (select pricing_snapshot->>'pricingConfigHash' from phase31c_retry_result),
  repeat('a', 64),
  'retry returns the historical snapshot without a new config hash'
);
select is(
  (
    select quote_form_details->>'structure_scope'
    from public.quote_request_intakes
    where access_token_hash = repeat('8', 64)
  ),
  'basic_single_section',
  'retry cannot merge changed evidence into submitted state'
);
select is(
  (
    select count(*)::integer
    from public.quote_request_pricing_snapshots as snapshot
    inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id
    where intake.access_token_hash = repeat('8', 64)
  ),
  1,
  'retry cannot create a second snapshot'
);
select is(
  (
    select config_hash
    from public.quote_request_pricing_snapshots as snapshot
    inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id
    where intake.access_token_hash = repeat('8', 64)
  ),
  repeat('a', 64),
  'retry cannot replace the historical snapshot hash'
);

select * from finish();
rollback;