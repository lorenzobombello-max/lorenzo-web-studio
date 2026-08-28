begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(68);

select has_table(
  'public',
  'quote_request_quotation_business_approval_promotions',
  'immutable business approval promotion binding exists'
);
select has_table(
  'public',
  'quote_request_quotation_business_approval_promotion_operations',
  'immutable promotion operation ledger exists'
);
select has_function(
  'public',
  'resolve_quotation_business_approval_promotion_context_v1',
  array['uuid', 'uuid', 'bigint'],
  'trusted promotion context resolver exists'
);
select has_function(
  'public',
  'promote_quotation_business_draft_to_approval_v1',
  array['uuid', 'uuid', 'bigint', 'uuid', 'uuid', 'jsonb'],
  'transactional promotion writer exists'
);
select has_function(
  'public',
  'resolve_first_customer_quotation_orchestration_v1',
  array['uuid', 'uuid'],
  'first-customer orchestration resolves frozen server context'
);
select has_function(
  'public',
  'resolve_quotation_generation_vat_binding_v1',
  array['uuid'],
  'generation resolves VAT only through the approval promotion binding'
);
select ok(
  pg_get_functiondef('public.build_quotation_preview_payload_v1(uuid,jsonb,jsonb,text)'::regprocedure)
    like '%project_quotation_generation_payload_v1%',
  'preview uses the guarded generation projector'
);
select ok(
  pg_get_functiondef('public.build_quotation_issue_payload_v1(uuid,jsonb,jsonb,text)'::regprocedure)
    like '%build_quotation_issue_payload_v1_unchecked_d3e4%',
  'issue delegates to the path using the guarded generation projector'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.resolve_quotation_business_approval_promotion_context_v1(uuid,uuid,bigint)',
    'execute'
  ),
  'service role can resolve trusted promotion context'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.resolve_quotation_business_approval_promotion_context_v1(uuid,uuid,bigint)',
    'execute'
  ),
  'authenticated clients cannot resolve trusted promotion context'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.resolve_quotation_business_approval_promotion_context_v1(uuid,uuid,bigint)',
    'execute'
  ),
  'anonymous clients cannot resolve trusted promotion context'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.promote_quotation_business_draft_to_approval_v1(uuid,uuid,bigint,uuid,uuid,jsonb)',
    'execute'
  ),
  'service role can write a verified promotion'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.promote_quotation_business_draft_to_approval_v1(uuid,uuid,bigint,uuid,uuid,jsonb)',
    'execute'
  ),
  'authenticated clients cannot write a promotion'
);
select ok(
  not has_table_privilege(
    'service_role',
    'public.quote_request_quotation_business_approval_promotions',
    'insert'
  ),
  'service role cannot insert promotion bindings directly'
);
select ok(
  not has_table_privilege(
    'service_role',
    'public.quote_request_quotation_business_approval_promotion_operations',
    'insert'
  ),
  'service role cannot insert promotion operations directly'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.quote_request_quotation_business_approval_promotions',
    'select'
  ),
  'authenticated clients cannot read promotion bindings directly'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.resolve_first_customer_quotation_orchestration_v1(uuid,uuid)',
    'execute'
  ),
  'service role can resolve first-customer orchestration context'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.resolve_first_customer_quotation_orchestration_v1(uuid,uuid)',
    'execute'
  ),
  'authenticated browser clients cannot resolve orchestration context'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.resolve_first_customer_quotation_orchestration_v1(uuid,uuid)',
    'execute'
  ),
  'anonymous clients cannot resolve orchestration context'
);

insert into auth.users (id, email) values
  ('ca100000-0000-4000-8000-000000000001', 'promotion-owner@example.test'),
  ('ca100000-0000-4000-8000-000000000002', 'promotion-admin@example.test'),
  ('ca100000-0000-4000-8000-000000000003', 'promotion-operator@example.test');

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values
  ('ca110000-0000-4000-8000-000000000001', 'ca100000-0000-4000-8000-000000000001', 'Promotion Owner', 'owner', 'ACTIVE'),
  ('ca110000-0000-4000-8000-000000000002', 'ca100000-0000-4000-8000-000000000002', 'Promotion Admin', 'admin', 'ACTIVE'),
  ('ca110000-0000-4000-8000-000000000003', 'ca100000-0000-4000-8000-000000000003', 'Promotion Operator', 'operator', 'ACTIVE');

insert into public.quote_requests (
  id, name, email, company, website_type, budget, timing, description,
  privacy_consent, status, billing_address, billing_postal_code,
  billing_city, billing_country
) values
  ('ca120001-0000-4000-8000-000000000001', 'Create Contact', 'create@example.test', 'Create BV', 'business', 'test', 'flexible', 'create fixture', true, 'approved', 'Teststraat 1', '9000', 'Gent', 'BE'),
  ('ca120002-0000-4000-8000-000000000002', 'Adopt Contact', 'adopt@example.test', 'Adopt BV', 'business', 'test', 'flexible', 'adopt fixture', true, 'approved', 'Teststraat 2', '9000', 'Gent', 'BE');

insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at,
  status, started_at, submitted_at, confirmation,
  admin_access_token_hash, admin_access_token_expires_at
) values
  ('ca130000-0000-4000-8000-000000000001', 'ca120001-0000-4000-8000-000000000001', repeat('1',64), clock_timestamp()+interval '1 day', 'submitted', clock_timestamp(), clock_timestamp(), true, repeat('f',64), clock_timestamp()+interval '1 day'),
  ('ca130000-0000-4000-8000-000000000002', 'ca120002-0000-4000-8000-000000000002', repeat('2',64), clock_timestamp()+interval '1 day', 'submitted', clock_timestamp(), clock_timestamp(), true, repeat('e',64), clock_timestamp()+interval '1 day');

insert into public.quote_request_pricing_snapshots (
  id, intake_id, snapshot_contract_version, config_version, config_hash,
  normalized_evidence, calculation, package_advice, budget_evaluation
) values
  ('ca140000-0000-4000-8000-000000000001', 'ca130000-0000-4000-8000-000000000001', 2, '1.0.0', repeat('1',64),
   '{"standardPages":["home","about","services","portfolio","contact","products"],"standardPageCount":6,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[{"id":"forms","classification":"contact","evidence":["contact_form_intent"]}],"manualComponents":[]}',
   '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":200000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000},{"ruleId":"extra_standard_page","mode":"fixed","amountMinor":20000,"quantity":1,"knownMinimumContributionMinor":20000},{"ruleId":"contact_form","mode":"included","quantity":1,"knownMinimumContributionMinor":0}]}',
   '{"status":"consider_professional","reasons":["standard_page_count_above_starter_scope"],"advisoryOnly":true,"selectedPackage":null}',
  '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}'),
  ('ca140000-0000-4000-8000-000000000002', 'ca130000-0000-4000-8000-000000000002', 2, '1.0.0', repeat('2',64),
   '{"standardPages":["home","about","services","portfolio","contact","products"],"standardPageCount":6,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[{"id":"forms","classification":"contact","evidence":["contact_form_intent"]}],"manualComponents":[]}',
   '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":200000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000},{"ruleId":"extra_standard_page","mode":"fixed","amountMinor":20000,"quantity":1,"knownMinimumContributionMinor":20000},{"ruleId":"contact_form","mode":"included","quantity":1,"knownMinimumContributionMinor":0}]}',
   '{"status":"consider_professional","reasons":["standard_page_count_above_starter_scope"],"advisoryOnly":true,"selectedPackage":null}',
  '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}');

insert into public.quote_request_pricing_snapshot_integrity (snapshot_id, algorithm_version, key_id, mac) values
  ('ca140000-0000-4000-8000-000000000001', 'hmac-sha256-v1', 'v1', repeat('a',64)),
  ('ca140000-0000-4000-8000-000000000002', 'hmac-sha256-v1', 'v1', repeat('b',64));

create temporary table promotion_payloads (fixture text primary key, payload jsonb not null);
insert into promotion_payloads values
('CREATE', '{"contract_version":1,"source_quote_request_id":"ca120001-0000-4000-8000-000000000001","source_intake_id":"ca130000-0000-4000-8000-000000000001","pricing_snapshot":{"snapshot_id":"ca140000-0000-4000-8000-000000000001","snapshot_contract_version":2,"integrity_algorithm_version":"hmac-sha256-v1","integrity_key_id":"v1","integrity_mac":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"currency":"EUR","line_items":[{"line_id":"pricing-rule:extra_standard_page","sequence":1,"product_or_service_code":"extra_standard_page","description":"Governed quotation line","quantity":1,"unit":"item","unit_price_minor":20000,"discount_minor":0,"vat_treatment":"STANDARD","vat_rate":21,"line_net_amount_minor":20000,"cost_type":"ONE_TIME"}],"totals":{"one_time_subtotal_minor":20000,"recurring_subtotal_minor":0,"discount_total_minor":0,"vat_base_minor":20000,"vat_amount_minor":4200,"total_gross_minor":24200},"discount":{"discount_type":null,"discount_value_minor":0,"discount_reason":null,"approved_by":null,"approved_at":null},"customer_identity":{"source_quote_request_id":"ca120001-0000-4000-8000-000000000001","source_intake_id":"ca130000-0000-4000-8000-000000000001","customer_id":null,"legal_name":"Create BV","contact_name":"Create Contact","email":"create@example.test","address_line_1":"Teststraat 1","address_line_2":null,"postal_code":"9000","city":"Gent","country_code":"BE","enterprise_number":null,"vat_number":null,"source_fields":{"legal_name":"quote_requests.company"},"snapshot_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"project_scope":{"project_id":null,"project_title":"Canonical website","project_type":"website","scope_summary":"Frozen exact quotation scope","requested_languages":["nl"],"included_page_count":6,"features":["contact_form"],"copywriting":null,"seo":null,"hosting":null,"maintenance":null,"exclusions":[],"assumptions":[],"indicative_timing":null,"source_intake_id":"ca130000-0000-4000-8000-000000000001","source_pricing_snapshot_id":"ca140000-0000-4000-8000-000000000001","snapshot_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"vat_approval":{"vat_treatment":"STANDARD","vat_rate":21,"vat_decision_source":"TEST_ONLY","vat_approved_by":"OPERATOR:ca110000-0000-4000-8000-000000000001","vat_approved_at":"2026-08-28T00:00:00Z"},"payment_schedule":{"schedule_id":"quotation-create","milestones":[{"sequence":1,"label":"Volledige betaling","percentage":100,"amount_minor":null,"trigger":"invoice","due_terms_days":30,"recurring_cycle":null}],"approved_by":"OPERATOR:ca110000-0000-4000-8000-000000000001","approved_at":"2026-08-28T00:00:00Z"},"validity":{"valid_from":"2026-08-28","valid_until":"2026-09-27","validity_days":30,"approved_by":"OPERATOR:ca110000-0000-4000-8000-000000000001","approved_at":"2026-08-28T00:00:00Z"},"legal_references":{"terms_reference":"LWS_GENERAL_TERMS_NL_BE","terms_version":"1.0","terms_sha256":"e3898aa99103c52354537550fda583a2dca7302329622115ecb39080a5eb4a32","terms_status":"APPROVED","agreement_template_reference":null,"agreement_template_version":null,"agreement_template_sha256":null}}');
update promotion_payloads
set payload = jsonb_set(
  jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(payload, '{line_items,0,vat_treatment}', '"EXEMPT"'),
          '{line_items,0,vat_rate}', '0'
        ),
        '{totals,vat_amount_minor}', '0'
      ),
      '{totals,total_gross_minor}', '20000'
    ),
    '{vat_approval,vat_treatment}', '"EXEMPT"'
  ),
  '{vat_approval,vat_rate}', '0'
);
update promotion_payloads
set payload = jsonb_set(
  payload,
  '{vat_approval,vat_decision_source}',
  '"FOD_FINANCIEN:0cb8f71e-6522-47c2-9134-8c15300d3507:PAGE_15"'
);

insert into promotion_payloads
select 'ADOPT', replace(replace(replace(replace(payload::text, 'ca120001-0000-4000-8000-000000000001', 'ca120002-0000-4000-8000-000000000002'), 'ca130000-0000-4000-8000-000000000001', 'ca130000-0000-4000-8000-000000000002'), 'ca140000-0000-4000-8000-000000000001', 'ca140000-0000-4000-8000-000000000002'), 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')::jsonb
from promotion_payloads where fixture='CREATE';

insert into public.quote_request_quotation_approval_drafts (
  id, quote_request_id, intake_id, pricing_snapshot_id, contract_version,
  approval_payload, payload_fingerprint, idempotency_key, created_by
)
select case fixture when 'CREATE' then 'ca160000-0000-4000-8000-000000000001'::uuid else 'ca160000-0000-4000-8000-000000000002'::uuid end,
  (payload->>'source_quote_request_id')::uuid, (payload->>'source_intake_id')::uuid,
  (payload->'pricing_snapshot'->>'snapshot_id')::uuid, 1, payload,
  public.quotation_approval_payload_sha256_v1(payload),
  case fixture when 'CREATE' then 'ca161000-0000-4000-8000-000000000001'::uuid else 'ca161000-0000-4000-8000-000000000002'::uuid end,
  'TEST'
from promotion_payloads;

insert into public.quote_request_quotation_business_drafts (
  business_draft_id, approval_draft_id, quote_request_id, intake_id,
  pricing_snapshot_id, business_revision, operator_id, seller_authority_id,
  terms_authority_id, vat_decision_authority_id, template_authority_id,
  policy_authority_id, canonical_payload, canonical_payload_sha256,
  request_fingerprint, idempotency_key, result_payload, prepared_by_actor, prepared_at
)
select case fixture when 'CREATE' then 'ca170000-0000-4000-8000-000000000001'::uuid else 'ca170000-0000-4000-8000-000000000002'::uuid end,
  case fixture when 'CREATE' then 'ca160000-0000-4000-8000-000000000001'::uuid else 'ca160000-0000-4000-8000-000000000002'::uuid end,
  (payload->>'source_quote_request_id')::uuid, (payload->>'source_intake_id')::uuid,
  (payload->'pricing_snapshot'->>'snapshot_id')::uuid, 1,
  'ca110000-0000-4000-8000-000000000001',
  (select seller_authority_id from public.quotation_seller_authorities where status='APPROVED'),
  (select terms_authority_id from public.quotation_terms_authorities where status='APPROVED'),
  'b1030000-0000-4000-8000-000000000001',
  (select id from public.quotation_template_authorities where status='APPROVED'),
  (select policy_authority_id from public.quotation_business_policy_authorities where status='APPROVED'),
  payload, public.quotation_approval_payload_sha256_v1(payload), repeat('c',64),
  case fixture when 'CREATE' then 'ca171000-0000-4000-8000-000000000001'::uuid else 'ca171000-0000-4000-8000-000000000002'::uuid end,
  jsonb_build_object('fixture', fixture), 'OPERATOR:ca110000-0000-4000-8000-000000000001', clock_timestamp()
from promotion_payloads;

insert into public.quotation_vat_transaction_classifications (
  classification_id, quote_request_id, context_sha256, classification_code,
  source_reference, source_sha256, classified_by, classified_at
)
select
  case id
    when 'ca120001-0000-4000-8000-000000000001'::uuid
      then 'ca151000-0000-4000-8000-000000000001'::uuid
    else 'ca151000-0000-4000-8000-000000000002'::uuid
  end,
  id, public.quotation_vat_context_sha256_v1(id),
  'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION',
  'TEST_ONLY:PROMOTION_CLASSIFICATION', repeat('5',64), 'TEST', clock_timestamp()
from public.quote_requests
where id in (
  'ca120001-0000-4000-8000-000000000001',
  'ca120002-0000-4000-8000-000000000002'
);
insert into public.quotation_vat_turnover_snapshots (
  turnover_snapshot_id, vat_decision_authority_id, threshold_year,
  measurement_watermark, governed_turnover_minor, currency, state,
  source_reference, source_sha256, recorded_by, recorded_at
) values (
  'ca152000-0000-4000-8000-000000000001',
  'b1030000-0000-4000-8000-000000000001', 2026,
  (clock_timestamp() at time zone 'Europe/Brussels')::date,
  1000000, 'EUR', 'BELOW_OR_AT_THRESHOLD',
  'TEST_ONLY:PROMOTION_TURNOVER', repeat('6',64), 'TEST', clock_timestamp()
);
select throws_ok(
  $$insert into public.quotation_business_draft_vat_bindings (
    business_draft_id, vat_decision_authority_id, authority_family,
    decision_code, decision_version, authority_sha256, vat_treatment,
    rate_semantics, invoice_literal, context_sha256, classification_id,
    turnover_snapshot_id
  )
  select business.business_draft_id, authority.vat_decision_authority_id,
    'MISMATCHED_FAMILY', authority.decision_code, authority.decision_version,
    authority.authority_sha256, authority.vat_treatment,
    authority.rate_semantics, authority.invoice_literal,
    classification.context_sha256, classification.classification_id,
    'ca152000-0000-4000-8000-000000000001'
  from public.quote_request_quotation_business_drafts as business
  join public.quotation_vat_transaction_classifications as classification
    on classification.quote_request_id = business.quote_request_id
  cross join public.quotation_vat_decision_authorities as authority
  where business.business_draft_id = 'ca170000-0000-4000-8000-000000000001'
    and authority.vat_decision_authority_id = 'b1030000-0000-4000-8000-000000000001'$$,
  'P0001', 'APPROVAL_CONFLICT',
  'binding insert rejects family inconsistent with the resolved authority'
);
select throws_ok(
  $$insert into public.quotation_business_draft_vat_bindings (
    business_draft_id, vat_decision_authority_id, authority_family,
    decision_code, decision_version, authority_sha256, vat_treatment,
    rate_semantics, invoice_literal, context_sha256, classification_id,
    turnover_snapshot_id
  )
  select business.business_draft_id, authority.vat_decision_authority_id,
    authority.authority_family, 'MISMATCHED_DECISION', authority.decision_version,
    authority.authority_sha256, authority.vat_treatment,
    authority.rate_semantics, authority.invoice_literal,
    classification.context_sha256, classification.classification_id,
    'ca152000-0000-4000-8000-000000000001'
  from public.quote_request_quotation_business_drafts as business
  join public.quotation_vat_transaction_classifications as classification
    on classification.quote_request_id = business.quote_request_id
  cross join public.quotation_vat_decision_authorities as authority
  where business.business_draft_id = 'ca170000-0000-4000-8000-000000000001'
    and authority.vat_decision_authority_id = 'b1030000-0000-4000-8000-000000000001'$$,
  'P0001', 'APPROVAL_CONFLICT',
  'binding insert rejects decision code inconsistent with the resolved authority'
);
select throws_ok(
  $$insert into public.quotation_business_draft_vat_bindings (
    business_draft_id, vat_decision_authority_id, authority_family,
    decision_code, decision_version, authority_sha256, vat_treatment,
    rate_semantics, invoice_literal, context_sha256, classification_id,
    turnover_snapshot_id
  )
  select business.business_draft_id, authority.vat_decision_authority_id,
    authority.authority_family, authority.decision_code, 'MISMATCHED_VERSION',
    authority.authority_sha256, authority.vat_treatment,
    authority.rate_semantics, authority.invoice_literal,
    classification.context_sha256, classification.classification_id,
    'ca152000-0000-4000-8000-000000000001'
  from public.quote_request_quotation_business_drafts as business
  join public.quotation_vat_transaction_classifications as classification
    on classification.quote_request_id = business.quote_request_id
  cross join public.quotation_vat_decision_authorities as authority
  where business.business_draft_id = 'ca170000-0000-4000-8000-000000000001'
    and authority.vat_decision_authority_id = 'b1030000-0000-4000-8000-000000000001'$$,
  'P0001', 'APPROVAL_CONFLICT',
  'binding insert rejects decision version inconsistent with the authority'
);
select throws_ok(
  $$insert into public.quotation_business_draft_vat_bindings (
    business_draft_id, vat_decision_authority_id, authority_family,
    decision_code, decision_version, authority_sha256, vat_treatment,
    rate_semantics, invoice_literal, context_sha256, classification_id,
    turnover_snapshot_id
  )
  select business.business_draft_id, authority.vat_decision_authority_id,
    authority.authority_family, authority.decision_code, authority.decision_version,
    repeat('0',64), authority.vat_treatment, authority.rate_semantics,
    authority.invoice_literal, classification.context_sha256,
    classification.classification_id, 'ca152000-0000-4000-8000-000000000001'
  from public.quote_request_quotation_business_drafts as business
  join public.quotation_vat_transaction_classifications as classification
    on classification.quote_request_id = business.quote_request_id
  cross join public.quotation_vat_decision_authorities as authority
  where business.business_draft_id = 'ca170000-0000-4000-8000-000000000001'
    and authority.vat_decision_authority_id = 'b1030000-0000-4000-8000-000000000001'$$,
  'P0001', 'APPROVAL_CONFLICT',
  'binding insert rejects authority hash mismatch'
);
select throws_ok(
  $$insert into public.quotation_business_draft_vat_bindings (
    business_draft_id, vat_decision_authority_id, authority_family,
    decision_code, decision_version, authority_sha256, vat_treatment,
    rate_semantics, invoice_literal, context_sha256, classification_id,
    turnover_snapshot_id
  )
  select business.business_draft_id, authority.vat_decision_authority_id,
    authority.authority_family, authority.decision_code, authority.decision_version,
    authority.authority_sha256, 'ZERO_RATE', 'PERCENT', '0% BTW',
    classification.context_sha256, classification.classification_id,
    'ca152000-0000-4000-8000-000000000001'
  from public.quote_request_quotation_business_drafts as business
  join public.quotation_vat_transaction_classifications as classification
    on classification.quote_request_id = business.quote_request_id
  cross join public.quotation_vat_decision_authorities as authority
  where business.business_draft_id = 'ca170000-0000-4000-8000-000000000001'
    and authority.vat_decision_authority_id = 'b1030000-0000-4000-8000-000000000001'$$,
  'P0001', 'APPROVAL_CONFLICT',
  'binding insert rejects treatment semantics and literal mismatch'
);
insert into public.quotation_business_draft_vat_bindings (
  business_draft_id, vat_decision_authority_id, authority_family, decision_code, decision_version,
  authority_sha256, vat_treatment, rate_semantics, invoice_literal,
  context_sha256, classification_id, turnover_snapshot_id
)
select
  business.business_draft_id,
  authority.vat_decision_authority_id,
  authority.authority_family,
  authority.decision_code,
  authority.decision_version,
  authority.authority_sha256,
  authority.vat_treatment,
  authority.rate_semantics,
  authority.invoice_literal,
  classification.context_sha256,
  classification.classification_id,
  'ca152000-0000-4000-8000-000000000001'
from public.quote_request_quotation_business_drafts as business
join public.quotation_vat_transaction_classifications as classification
  on classification.quote_request_id = business.quote_request_id
cross join public.quotation_vat_decision_authorities as authority
where authority.vat_decision_authority_id = 'b1030000-0000-4000-8000-000000000001';

select is(
  (select authority_family from public.quotation_business_draft_vat_bindings limit 1),
  'LWS_OUTGOING_VAT',
  'draft binding explicitly freezes the resolved authority family'
);
select is(
  (select decision_code from public.quotation_business_draft_vat_bindings limit 1),
  'BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION',
  'draft binding explicitly freezes the resolved decision code'
);

create function pg_temp.promotion_proof(p_approval_id uuid, p_fixture text)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'algorithmVersion', 'hmac-sha256-v1', 'keyId', 'v1', 'mac', repeat('d',64),
    'root', public.quotation_approval_integrity_root_v1(
      p_approval_id, public.quotation_approval_payload_sha256_v1(payload), 1::smallint,
      (payload->>'source_quote_request_id')::uuid,
      (payload->>'source_intake_id')::uuid,
      (payload->'pricing_snapshot'->>'snapshot_id')::uuid
    )
  ) from promotion_payloads where fixture = p_fixture
$$;

select throws_ok(
  $$select public.resolve_quotation_business_approval_promotion_context_v1('ca100000-0000-4000-8000-000000000003','ca130000-0000-4000-8000-000000000001',1)$$,
  '42501', 'QUOTATION_BUSINESS_SCOPE_DENIED', 'non-owner/admin cannot resolve promotion context'
);
select throws_ok(
  $$select public.resolve_quotation_business_approval_promotion_context_v1('ca100000-0000-4000-8000-000000000001','ca130000-0000-4000-8000-000000000001',0)$$,
  'P0001', 'STALE_BUSINESS_REVISION', 'stale business revision fails closed'
);
select is(
  public.resolve_quotation_business_approval_promotion_context_v1('ca100000-0000-4000-8000-000000000001','ca130000-0000-4000-8000-000000000001',1)->>'mode',
  'CREATE', 'zero legacy approvals selects CREATE'
);

set local session_replication_role = replica;
update public.quotation_business_draft_vat_bindings
set authority_family = 'MISMATCHED_FAMILY'
where business_draft_id = 'ca170000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select throws_ok(
  $$select public.resolve_quotation_business_approval_promotion_context_v1('ca100000-0000-4000-8000-000000000001','ca130000-0000-4000-8000-000000000001',1)$$,
  'P0001', 'APPROVAL_CONFLICT', 'frozen VAT authority family mismatch fails before approval writer'
);
select is(
  (select count(*)::integer from public.quote_request_quotation_approvals where intake_id='ca130000-0000-4000-8000-000000000001'),
  0,
  'family mismatch creates no approval'
);
set local session_replication_role = replica;
update public.quotation_business_draft_vat_bindings
set authority_family = 'LWS_OUTGOING_VAT', decision_code = 'MISMATCHED_DECISION'
where business_draft_id = 'ca170000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select throws_ok(
  $$select public.resolve_quotation_business_approval_promotion_context_v1('ca100000-0000-4000-8000-000000000001','ca130000-0000-4000-8000-000000000001',1)$$,
  'P0001', 'APPROVAL_CONFLICT', 'frozen VAT decision code mismatch fails before approval writer'
);
select is(
  (select count(*)::integer from public.quote_request_quotation_approvals where intake_id='ca130000-0000-4000-8000-000000000001'),
  0,
  'decision code mismatch creates no approval'
);
set local session_replication_role = replica;
update public.quotation_business_draft_vat_bindings
set decision_code = 'BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION'
where business_draft_id = 'ca170000-0000-4000-8000-000000000001';
set local session_replication_role = origin;

set local session_replication_role = replica;
update public.quote_request_quotation_business_drafts set approval_draft_id='ca160000-0000-4000-8000-000000000002' where business_draft_id='ca170000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select throws_ok(
  $$select public.resolve_quotation_business_approval_promotion_context_v1('ca100000-0000-4000-8000-000000000001','ca130000-0000-4000-8000-000000000001',1)$$,
  'P0001', 'APPROVAL_CONFLICT', 'wrong approval draft source binding fails closed'
);
set local session_replication_role = replica;
update public.quote_request_quotation_business_drafts set approval_draft_id='ca160000-0000-4000-8000-000000000001' where business_draft_id='ca170000-0000-4000-8000-000000000001';
set local session_replication_role = origin;

create temporary table create_result as
select public.promote_quotation_business_draft_to_approval_v1(
  'ca100000-0000-4000-8000-000000000001','ca130000-0000-4000-8000-000000000001',1,
  'ca180000-0000-4000-8000-000000000001','ca190000-0000-4000-8000-000000000001',
  pg_temp.promotion_proof('ca190000-0000-4000-8000-000000000001','CREATE')
) as result;
select is((select result->>'status' from create_result), 'APPROVED', 'authorized CREATE promotes successfully');
select is((select result->>'was_created' from create_result), 'true', 'CREATE reports a new immutable approval');
select is((select count(*)::integer from public.quote_request_quotation_business_approval_promotions where business_draft_id='ca170000-0000-4000-8000-000000000001'), 1, 'CREATE records exactly one binding');
select is((select count(*)::integer from public.quote_request_quotation_approvals where id='ca190000-0000-4000-8000-000000000001'), 1, 'CREATE reuses canonical approval authority');
select throws_ok(
  $$select public.resolve_first_customer_quotation_orchestration_v1(
    'ca100000-0000-4000-8000-000000000003',
    'ca120001-0000-4000-8000-000000000001'
  )$$,
  '42501', 'QUOTATION_ORCHESTRATION_SCOPE_DENIED',
  'ordinary operator cannot resolve issuance secrets or authority context'
);
create temporary table orchestration_context as
select public.resolve_first_customer_quotation_orchestration_v1(
  'ca100000-0000-4000-8000-000000000001',
  'ca120001-0000-4000-8000-000000000001'
) as result;
select is(
  (select result->>'approval_id' from orchestration_context),
  'ca190000-0000-4000-8000-000000000001',
  'orchestration resolves only the promoted approval for the request'
);
select is(
  (select result->'template'->>'authority_status' from orchestration_context),
  'APPROVED',
  'orchestration returns the frozen approved template identity'
);
select ok(
  (select result->>'admin_access_token_hash' from orchestration_context) ~ '^[0-9a-f]{64}$'
    and (select result->>'issuance_input_sha256' from orchestration_context) ~ '^[0-9a-f]{64}$'
    and (select result->'seller'->>'legal_name' from orchestration_context) = 'Lorenzo Bombello',
  'orchestration returns server-owned capability, fingerprint, and frozen seller'
);
create temporary table bound_generation_payload as
select public.project_quotation_generation_payload_v1(
  'PREVIEW', approval.id, approval.approved_payload, rtrim(approval.payload_sha256),
  '{}'::jsonb, '{}'::jsonb
) as payload
from public.quote_request_quotation_approvals as approval
where approval.id = 'ca190000-0000-4000-8000-000000000001';
select is((select payload->'vat'->>'vat_treatment' from bound_generation_payload), 'EXEMPT', 'bound generation carries frozen treatment');
select is((select payload->'vat'->>'rate_semantics' from bound_generation_payload), 'NOT_APPLICABLE', 'bound generation carries frozen rate semantics');
select is((select (payload->'vat'->>'vat_rate')::numeric from bound_generation_payload), 0::numeric, 'bound generation carries governed compatibility rate');
select is((select payload->'vat'->>'invoice_literal' from bound_generation_payload), 'Bijzondere vrijstellingsregeling van belasting', 'bound generation carries the frozen official literal');

set local session_replication_role = replica;
update public.quotation_business_draft_vat_bindings
set vat_decision_authority_id = 'b1030000-0000-4000-8000-000000000099'
where business_draft_id = 'ca170000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select throws_ok(
  $$select public.project_quotation_generation_payload_v1(
    'PREVIEW', approval.id, approval.approved_payload, rtrim(approval.payload_sha256),
    '{}'::jsonb, '{}'::jsonb
  ) from public.quote_request_quotation_approvals as approval
  where approval.id = 'ca190000-0000-4000-8000-000000000001'$$,
  'P0001', 'APPROVAL_CONFLICT',
  'generation rejects a frozen VAT authority ID mismatch'
);
set local session_replication_role = replica;
update public.quotation_business_draft_vat_bindings
set vat_decision_authority_id = 'b1030000-0000-4000-8000-000000000001'
where business_draft_id = 'ca170000-0000-4000-8000-000000000001';
set local session_replication_role = origin;

set local session_replication_role = replica;
update public.quotation_business_draft_vat_bindings
set authority_sha256 = repeat('0',64)
where business_draft_id = 'ca170000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select throws_ok(
  $$select public.project_quotation_generation_payload_v1(
    'PREVIEW', approval.id, approval.approved_payload, rtrim(approval.payload_sha256),
    '{}'::jsonb, '{}'::jsonb
  ) from public.quote_request_quotation_approvals as approval
  where approval.id = 'ca190000-0000-4000-8000-000000000001'$$,
  'P0001', 'APPROVAL_CONFLICT',
  'generation rejects a frozen authority hash mismatch'
);
set local session_replication_role = replica;
update public.quotation_business_draft_vat_bindings
set authority_sha256 = authority.authority_sha256,
    authority_family = 'MISMATCHED_FAMILY',
    decision_code = 'MISMATCHED_DECISION',
    decision_version = 'MISMATCHED_VERSION'
from public.quotation_vat_decision_authorities as authority
where business_draft_id = 'ca170000-0000-4000-8000-000000000001'
  and authority.vat_decision_authority_id = quotation_business_draft_vat_bindings.vat_decision_authority_id;
set local session_replication_role = origin;
select throws_ok(
  $$select public.project_quotation_generation_payload_v1(
    'PREVIEW', approval.id, approval.approved_payload, rtrim(approval.payload_sha256),
    '{}'::jsonb, '{}'::jsonb
  ) from public.quote_request_quotation_approvals as approval
  where approval.id = 'ca190000-0000-4000-8000-000000000001'$$,
  'P0001', 'APPROVAL_CONFLICT',
  'generation rejects frozen family code or version mismatch'
);
set local session_replication_role = replica;
update public.quotation_business_draft_vat_bindings
set authority_family = authority.authority_family,
    decision_code = authority.decision_code,
    decision_version = authority.decision_version
from public.quotation_vat_decision_authorities as authority
where business_draft_id = 'ca170000-0000-4000-8000-000000000001'
  and authority.vat_decision_authority_id = quotation_business_draft_vat_bindings.vat_decision_authority_id;
set local session_replication_role = origin;
do $$
declare
  v_constraint record;
begin
  for v_constraint in
    select conname
    from pg_constraint
    where conrelid = 'public.quotation_business_draft_vat_bindings'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ~ '(vat_treatment|rate_semantics|invoice_literal)'
  loop
    execute format(
      'alter table public.quotation_business_draft_vat_bindings drop constraint %I',
      v_constraint.conname
    );
  end loop;
end;
$$;
set local session_replication_role = replica;
update public.quotation_business_draft_vat_bindings
set vat_treatment = 'ZERO_RATE',
    rate_semantics = 'PERCENT',
    invoice_literal = '0% BTW'
where business_draft_id = 'ca170000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select throws_ok(
  $$select public.project_quotation_generation_payload_v1(
    'PREVIEW', approval.id, approval.approved_payload, rtrim(approval.payload_sha256),
    '{}'::jsonb, '{}'::jsonb
  ) from public.quote_request_quotation_approvals as approval
  where approval.id = 'ca190000-0000-4000-8000-000000000001'$$,
  'P0001', 'APPROVAL_CONFLICT',
  'generation rejects frozen treatment semantics or literal mismatch'
);
set local session_replication_role = replica;
update public.quotation_business_draft_vat_bindings
set vat_treatment = 'EXEMPT',
    rate_semantics = 'NOT_APPLICABLE',
    invoice_literal = 'Bijzondere vrijstellingsregeling van belasting'
where business_draft_id = 'ca170000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
create temporary table missing_generation_vat_binding_fixture as
select *
from public.quotation_business_draft_vat_bindings
where business_draft_id = 'ca170000-0000-4000-8000-000000000001';
set local session_replication_role = replica;
delete from public.quotation_business_draft_vat_bindings
where business_draft_id = 'ca170000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select throws_ok(
  $$select public.project_quotation_generation_payload_v1(
    'PREVIEW', approval.id, approval.approved_payload, rtrim(approval.payload_sha256),
    '{}'::jsonb, '{}'::jsonb
  ) from public.quote_request_quotation_approvals as approval
  where approval.id = 'ca190000-0000-4000-8000-000000000001'$$,
  'P0001', 'QUOTATION_VAT_BINDING_REQUIRED',
  'promotion with a missing frozen VAT binding fails with the required classification'
);
insert into public.quotation_business_draft_vat_bindings (
  business_draft_id, vat_decision_authority_id, authority_family,
  decision_code, decision_version, authority_sha256, vat_treatment,
  rate_semantics, invoice_literal, context_sha256, classification_id,
  turnover_snapshot_id, created_at
)
select business_draft_id, vat_decision_authority_id, authority_family,
  decision_code, decision_version, authority_sha256, vat_treatment,
  rate_semantics, invoice_literal, context_sha256, classification_id,
  turnover_snapshot_id, created_at
from missing_generation_vat_binding_fixture;
select is(
  public.promote_quotation_business_draft_to_approval_v1(
    'ca100000-0000-4000-8000-000000000001','ca130000-0000-4000-8000-000000000001',1,
    'ca180000-0000-4000-8000-000000000001','ca199000-0000-4000-8000-000000000099','{}'
  )->>'approval_id',
  'ca190000-0000-4000-8000-000000000001', 'exact retry returns the same approval'
);
select is(
  public.promote_quotation_business_draft_to_approval_v1(
    'ca100000-0000-4000-8000-000000000001','ca130000-0000-4000-8000-000000000001',1,
    'ca180000-0000-4000-8000-000000000002','ca199000-0000-4000-8000-000000000098','{}'
  )->>'approval_id',
  'ca190000-0000-4000-8000-000000000001', 'new operation key converges on the existing promotion'
);
select throws_ok(
  $$select public.promote_quotation_business_draft_to_approval_v1('ca100000-0000-4000-8000-000000000002','ca130000-0000-4000-8000-000000000001',1,'ca180000-0000-4000-8000-000000000001','ca190000-0000-4000-8000-000000000001',pg_temp.promotion_proof('ca190000-0000-4000-8000-000000000001','CREATE'))$$,
  'P0001', 'IDEMPOTENCY_CONFLICT', 'same operation key with a different actor fails closed'
);

select * from public.approve_quotation_commercial_envelope_v1(
  'ca160000-0000-4000-8000-000000000002','ca190000-0000-4000-8000-000000000002',
  (select payload from promotion_payloads where fixture='ADOPT'),
  'ca181000-0000-4000-8000-000000000001',repeat('e',64),'LEGACY:TEST',
  pg_temp.promotion_proof('ca190000-0000-4000-8000-000000000002','ADOPT')
);
select throws_ok(
  $$select public.project_quotation_generation_payload_v1(
    'PREVIEW', approval.id, approval.approved_payload, rtrim(approval.payload_sha256),
    '{}'::jsonb, '{}'::jsonb
  ) from public.quote_request_quotation_approvals as approval
  where approval.id = 'ca190000-0000-4000-8000-000000000002'$$,
  'P0001', 'QUOTATION_VAT_BINDING_REQUIRED',
  'legacy EXEMPT approval without a promotion binding fails closed'
);
select is(
  (select count(*)::integer from public.quote_request_quotation_business_approval_promotions where approval_id='ca190000-0000-4000-8000-000000000002'),
  0,
  'failed legacy generation creates no silent promotion binding'
);
select is(
  (select count(*)::integer from public.quotation_business_draft_vat_bindings),
  2,
  'failed legacy generation creates no VAT binding backfill'
);
set local session_replication_role = replica;
delete from public.quote_request_quotation_approval_integrity where approval_id='ca190000-0000-4000-8000-000000000002';
set local session_replication_role = origin;
select throws_ok(
  $$select public.resolve_quotation_business_approval_promotion_context_v1('ca100000-0000-4000-8000-000000000001','ca130000-0000-4000-8000-000000000002',1)$$,
  'P0001', 'APPROVAL_CONFLICT', 'legacy candidate without integrity fails closed'
);
insert into public.quote_request_quotation_approval_integrity (approval_id,algorithm_version,key_id,mac)
values ('ca190000-0000-4000-8000-000000000002','hmac-sha256-v1','v1',repeat('d',64));
set local session_replication_role = replica;
update public.quotation_vat_decision_authorities
set status = 'RETIRED',
    retired_by = 'TEST:HISTORICAL_ADOPT',
    retired_at = clock_timestamp(),
    retirement_reason = 'TEST_ONLY'
where vat_decision_authority_id = 'b1030000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select is(
  public.resolve_quotation_business_approval_promotion_context_v1('ca100000-0000-4000-8000-000000000001','ca130000-0000-4000-8000-000000000002',1)->>'mode',
  'ADOPT', 'ADOPT validates the exact historical binding without current authority resolution'
);
set local session_replication_role = replica;
update public.quotation_vat_decision_authorities
set status = 'APPROVED',
    retired_by = null,
    retired_at = null,
    retirement_reason = null
where vat_decision_authority_id = 'b1030000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select is(
  public.resolve_quotation_business_approval_promotion_context_v1('ca100000-0000-4000-8000-000000000001','ca130000-0000-4000-8000-000000000002',1)->>'mode',
  'ADOPT', 'one exact legacy approval with integrity selects ADOPT'
);
select is(
  public.promote_quotation_business_draft_to_approval_v1(
    'ca100000-0000-4000-8000-000000000001','ca130000-0000-4000-8000-000000000002',1,
    'ca180000-0000-4000-8000-000000000003','ca190000-0000-4000-8000-000000000002',
    pg_temp.promotion_proof('ca190000-0000-4000-8000-000000000002','ADOPT')
  )->>'was_created',
  'false', 'valid exact legacy approval is adopted without replacement'
);
select is((select count(*)::integer from public.quote_request_quotation_approvals where id='ca190000-0000-4000-8000-000000000002'), 1, 'ADOPT creates no replacement approval');
select throws_ok(
  $$insert into public.quote_request_quotation_business_approval_promotions(business_draft_id,approval_id) values ('ca170000-0000-4000-8000-000000000002','ca190000-0000-4000-8000-000000000001')$$,
  '23505', null, 'one approval cannot bind to a second business authority'
);
select throws_ok(
  $$update public.quote_request_quotation_business_approval_promotions set approval_id='ca190000-0000-4000-8000-000000000002' where business_draft_id='ca170000-0000-4000-8000-000000000001'$$,
  '55000', 'QUOTATION_BUSINESS_APPROVAL_PROMOTION_IMMUTABLE', 'promotion binding is immutable'
);
select throws_ok(
  $$delete from public.quote_request_quotation_business_approval_promotion_operations where idempotency_key='ca180000-0000-4000-8000-000000000001'$$,
  '55000', 'QUOTATION_BUSINESS_APPROVAL_PROMOTION_IMMUTABLE', 'promotion operation ledger is immutable'
);
select is((select count(*)::integer from public.quote_request_quotation_business_drafts), 2, 'promotion leaves immutable business revisions unchanged');
select is((select count(*)::integer from public.quote_request_quotation_issuances), 0, 'promotion creates no issuance');
select is((select coalesce(sum(next_sequence),0)::bigint from public.quotation_number_counters), 0::bigint, 'promotion consumes no quotation number');

select * from finish();
rollback;
