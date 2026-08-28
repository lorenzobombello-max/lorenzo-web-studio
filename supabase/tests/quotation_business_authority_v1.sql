begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set local search_path = public, extensions;

select plan(78);

select has_table('public', 'quotation_seller_authorities', 'seller authority exists');
select has_table('public', 'quotation_terms_authorities', 'terms authority exists');
select has_table('public', 'quotation_vat_decision_authorities', 'VAT decision authority exists');
select has_table('public', 'quote_request_quotation_business_drafts', 'business draft audit authority exists');
select has_function(
  'public', 'resolve_quotation_seller_authority_v1', array[]::text[],
  'seller resolver exists'
);
select has_function(
  'public', 'upsert_quotation_business_draft_v1',
  array['uuid', 'uuid', 'bigint', 'uuid', 'jsonb'],
  'canonical business payload builder exists'
);
select has_function(
  'lws_internal', 'assert_quotation_frozen_rule_coverage_v1',
  array['jsonb', 'jsonb'],
  'internal frozen rule coverage invariant exists'
);
select has_function(
  'public', 'activate_quotation_business_authority_version_v1',
  array['uuid', 'text', 'jsonb', 'text'],
  'atomic authority version activation exists'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.activate_quotation_business_authority_version_v1(uuid,text,jsonb,text)',
    'execute'
  ),
  'service role can activate governed authority versions'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.activate_quotation_business_authority_version_v1(uuid,text,jsonb,text)',
    'execute'
  ),
  'browser operators cannot activate authority versions directly'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.upsert_quotation_business_draft_v1(uuid,uuid,bigint,uuid,jsonb)',
    'execute'
  ),
  'anon cannot build quotation business drafts'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.upsert_quotation_business_draft_v1(uuid,uuid,bigint,uuid,jsonb)',
    'execute'
  ),
  'browser operators cannot bypass the server boundary'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.upsert_quotation_business_draft_v1(uuid,uuid,bigint,uuid,jsonb)',
    'execute'
  ),
  'service role can invoke the server authority'
);

select is(
  (select seller_identity->>'email' from public.resolve_quotation_seller_authority_v1()),
  'info@lorenzowebsolution.be',
  'official seller email is governed server-side'
);
select is(
  (select seller_identity->>'legal_name' from public.resolve_quotation_seller_authority_v1()),
  'Lorenzo Bombello',
  'existing legal seller identity is preserved'
);
select ok(
  public.is_valid_quotation_generation_seller_v1(
    (select seller_identity from public.resolve_quotation_seller_authority_v1())
  ),
  'resolved seller satisfies the existing generation validator'
);
select throws_ok(
  $$update public.quotation_seller_authorities set seller_identity = '{}'::jsonb$$,
  '55000', 'QUOTATION_BUSINESS_AUTHORITY_IMMUTABLE',
  'seller identity is immutable'
);
select throws_ok(
  $$delete from public.quotation_terms_authorities$$,
  '55000', 'QUOTATION_BUSINESS_AUTHORITY_IMMUTABLE',
  'terms authority is immutable'
);
insert into public.quotation_vat_decision_authorities (
  vat_decision_authority_id, decision_code, decision_version, vat_treatment,
  vat_rate, authority_source_identifier, status, approved_by, approved_at
) values (
  'ba000000-0000-4000-8000-000000000001', 'TEST_STANDARD', '1.0.0',
  'STANDARD', 21, 'TEST_ONLY', 'APPROVED', 'TEST', '2026-08-28T00:00:00Z'
);
select throws_ok(
  $$delete from public.quotation_vat_decision_authorities$$,
  '55000', 'QUOTATION_BUSINESS_AUTHORITY_IMMUTABLE',
  'VAT authority is immutable'
);
select throws_ok(
  $$update public.quotation_business_policy_authorities set default_validity_days = 31$$,
  '55000', 'QUOTATION_BUSINESS_AUTHORITY_IMMUTABLE',
  'policy content remains directly immutable'
);
select ok(
  not has_table_privilege('service_role', 'public.quotation_seller_authorities', 'insert'),
  'service role cannot insert seller authority directly'
);
select ok(
  not has_table_privilege('service_role', 'public.quote_request_quotation_business_drafts', 'insert'),
  'service role cannot bypass business draft RPC'
);
select is(
  (select count(*)::integer from public.quotation_seller_authorities where status = 'APPROVED'),
  1,
  'exactly one approved seller identity is registered'
);

insert into auth.users (id, email) values
  ('ba100000-0000-4000-8000-000000000001', 'quotation-owner@example.test'),
  ('ba100000-0000-4000-8000-000000000002', 'quotation-admin@example.test'),
  ('ba100000-0000-4000-8000-000000000003', 'quotation-operator@example.test'),
  ('ba100000-0000-4000-8000-000000000004', 'quotation-inactive@example.test');

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values
  ('ba110000-0000-4000-8000-000000000001', 'ba100000-0000-4000-8000-000000000001', 'Quotation Owner', 'owner', 'ACTIVE'),
  ('ba110000-0000-4000-8000-000000000002', 'ba100000-0000-4000-8000-000000000002', 'Quotation Admin', 'admin', 'ACTIVE'),
  ('ba110000-0000-4000-8000-000000000003', 'ba100000-0000-4000-8000-000000000003', 'Quotation Operator', 'operator', 'ACTIVE'),
  ('ba110000-0000-4000-8000-000000000004', 'ba100000-0000-4000-8000-000000000004', 'Quotation Inactive', 'owner', 'DISABLED');

insert into public.quote_requests (
  id, name, email, company, website_type, budget, timing, description,
  privacy_consent, status, billing_address, billing_postal_code,
  billing_city, billing_country
) values (
  'ba120000-0000-4000-8000-000000000001', 'Business Contact',
  'customer@example.test', 'Canonical Customer BV', 'business',
  'EUR 3.200 t/m EUR 6.000', 'flexible', 'Quotation business authority fixture',
  true, 'approved', 'Teststraat 1', '9000', 'Gent', 'BE'
);

insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at,
  status, started_at, submitted_at, confirmation,
  admin_access_token_hash, admin_access_token_expires_at
) values (
  'ba130000-0000-4000-8000-000000000001',
  'ba120000-0000-4000-8000-000000000001', repeat('1', 64),
  clock_timestamp() + interval '1 day', 'submitted', clock_timestamp(),
  clock_timestamp(), true, repeat('f', 64), clock_timestamp() + interval '1 day'
);

insert into public.quote_request_pricing_snapshots (
  id, intake_id, snapshot_contract_version, config_version, config_hash,
  normalized_evidence, calculation, package_advice, budget_evaluation
) values (
  'ba140000-0000-4000-8000-000000000001',
  'ba130000-0000-4000-8000-000000000001', 2, '1.0.0', repeat('1', 64),
  '{
    "standardPages":["home","about","services","portfolio","contact","products"],
    "standardPageCount":6,"primaryLanguage":"nl","additionalLanguages":[],
    "unknownLanguages":[],
    "modules":[{"id":"forms","classification":"contact","evidence":["contact_form_intent"]}],
    "manualComponents":["customer_login"]
  }',
  '{
    "basis":"starter_floor","currency":"EUR","vatBasis":"exclusive",
    "knownMinimumMinor":200000,"containsFromPricing":true,
    "manualReviewRequired":true,"manualReasons":["customer_login"],
    "appliedRules":[
      {"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000},
      {"ruleId":"extra_standard_page","mode":"fixed","amountMinor":20000,"quantity":1,"knownMinimumContributionMinor":20000},
      {"ruleId":"contact_form","mode":"included","quantity":1,"knownMinimumContributionMinor":0},
      {"ruleId":"customer_login","mode":"manual","quantity":1,"knownMinimumContributionMinor":0}
    ]
  }',
  '{"status":"consider_professional","reasons":["standard_page_count_above_starter_scope"],"advisoryOnly":true,"selectedPackage":null}',
  '{
    "contractVersion":2,"evidenceProvenance":"budget_guard_v1",
    "categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive",
    "originalLabel":"EUR 3.200 t/m EUR 6.000",
    "status":"manual_review_required","outsideBudgetWishes":null
  }'
);

insert into public.quote_request_pricing_snapshot_integrity (
  snapshot_id, algorithm_version, key_id, mac
) values (
  'ba140000-0000-4000-8000-000000000001', 'hmac-sha256-v1', 'v1', repeat('a', 64)
);

insert into public.quote_requests (
  id, name, email, company, website_type, budget, timing, description,
  privacy_consent, status, billing_address, billing_postal_code,
  billing_city, billing_country
)
select
  'ba121000-0000-4000-8000-000000000002', name, 'invalid-snapshot@example.test',
  company, website_type, budget, timing, description, privacy_consent, status,
  billing_address, billing_postal_code, billing_city, billing_country
from public.quote_requests where id = 'ba120000-0000-4000-8000-000000000001';

insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at,
  status, started_at, submitted_at, confirmation,
  admin_access_token_hash, admin_access_token_expires_at
) values (
  'ba130000-0000-4000-8000-000000000002',
  'ba121000-0000-4000-8000-000000000002', repeat('2', 64),
  clock_timestamp() + interval '1 day', 'submitted', clock_timestamp(),
  clock_timestamp(), true, repeat('e', 64), clock_timestamp() + interval '1 day'
);

insert into public.quote_request_pricing_snapshots (
  id, intake_id, snapshot_contract_version, config_version, config_hash,
  normalized_evidence, calculation, package_advice, budget_evaluation
)
select
  'ba140000-0000-4000-8000-000000000002',
  'ba130000-0000-4000-8000-000000000002', snapshot_contract_version,
  config_version, config_hash, normalized_evidence, calculation,
  jsonb_set(package_advice, '{reasons}', '["noncanonical_reason"]'), budget_evaluation
from public.quote_request_pricing_snapshots
where id = 'ba140000-0000-4000-8000-000000000001';

insert into public.quote_request_pricing_snapshot_integrity (
  snapshot_id, algorithm_version, key_id, mac
) values (
  'ba140000-0000-4000-8000-000000000002', 'hmac-sha256-v1', 'v1', repeat('b', 64)
);

insert into public.quotation_terms_authorities (
  terms_authority_id, terms_id, terms_version, terms_sha256, source_path,
  status, effective_from, approved_by, approved_at,
  retired_by, retired_at, retirement_reason
) values (
  'ba150000-0000-4000-8000-000000000001', 'TEST_RETIRED_TERMS', '1.0',
  repeat('e', 64), 'TEST_ONLY', 'RETIRED', '2026-08-28', 'TEST', '2026-08-28T00:00:00Z',
  'TEST', '2026-08-28T00:00:00Z', 'TEST_ONLY'
);

create function pg_temp.quotation_business_input(
  p_rule_id text default 'extra_standard_page',
  p_quantity numeric default 1,
  p_discount_minor bigint default 0,
  p_discount_reason text default null,
  p_percentage numeric default 100,
  p_amount_minor bigint default null,
  p_terms_authority_id uuid default 'b1010000-0000-4000-8000-000000000001',
  p_vat_authority_id uuid default 'ba000000-0000-4000-8000-000000000001',
  p_validity_days integer default null
)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'commercial_lines', jsonb_build_array(jsonb_build_object(
      'rule_id', p_rule_id,
      'quantity', p_quantity,
      'description_context', 'Governed quotation line'
    )),
    'discount', jsonb_build_object(
      'discount_type', case when p_discount_minor = 0 then null else 'FIXED_AMOUNT' end,
      'discount_value_minor', p_discount_minor,
      'discount_reason', p_discount_reason
    ),
    'scope', jsonb_build_object(
      'project_title', 'Canonical website',
      'project_type', 'website',
      'scope_summary', 'Frozen exact quotation scope',
      'requested_languages', jsonb_build_array('nl'),
      'included_page_count', 6,
      'features', jsonb_build_array('contact_form'),
      'copywriting', null,
      'seo', null,
      'hosting', null,
      'maintenance', null,
      'exclusions', '[]'::jsonb,
      'assumptions', '[]'::jsonb,
      'indicative_timing', null
    ),
    'vat_decision_authority_id', p_vat_authority_id,
    'terms_authority_id', p_terms_authority_id,
    'payment_schedule', jsonb_build_object(
      'milestones', jsonb_build_array(jsonb_build_object(
        'sequence', 1,
        'label', 'Volledige betaling',
        'percentage', case when p_amount_minor is null then p_percentage else null end,
        'amount_minor', p_amount_minor,
        'trigger', 'invoice',
        'due_terms_days', 30,
        'recurring_cycle', null
      ))
    ),
    'validity_days', p_validity_days
  )
$$;

select ok(
  (select public.is_structurally_valid_pricing_snapshot_v2(
    snapshot_contract_version, config_version, config_hash, normalized_evidence,
    calculation, package_advice, budget_evaluation
  ) from public.quote_request_pricing_snapshots
  where id = 'ba140000-0000-4000-8000-000000000001'),
  'behavior fixture is structurally valid pricing v2'
);
select ok(
  (select public.has_canonical_pricing_snapshot_v2_semantics(
    normalized_evidence, calculation, package_advice
  ) from public.quote_request_pricing_snapshots
  where id = 'ba140000-0000-4000-8000-000000000001'),
  'behavior fixture has canonical pricing v2 semantics'
);
select ok(
  public.is_current_pricing_snapshot_integrity_valid(
    'ba130000-0000-4000-8000-000000000001',
    'ba140000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'snapshot_id', 'ba140000-0000-4000-8000-000000000001',
      'snapshot_contract_version', 2,
      'integrity_algorithm_version', 'hmac-sha256-v1',
      'integrity_key_id', 'v1',
      'integrity_mac', repeat('a', 64)
    )
  ),
  'behavior fixture is a valid frozen pricing snapshot'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000003', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000001', pg_temp.quotation_business_input()
  )$$,
  '42501', 'QUOTATION_BUSINESS_SCOPE_DENIED',
  'active non-privileged operator cannot prepare quotation business authority'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000004', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000002', pg_temp.quotation_business_input()
  )$$,
  '42501', 'QUOTATION_BUSINESS_SCOPE_DENIED',
  'inactive owner cannot prepare quotation business authority'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000099', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000003', pg_temp.quotation_business_input()
  )$$,
  '42501', 'QUOTATION_BUSINESS_SCOPE_DENIED',
  'unknown actor cannot prepare quotation business authority'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000004',
    pg_temp.quotation_business_input() || '{"seller_email":"attacker@example.test"}'::jsonb
  )$$,
  '22023', 'QUOTATION_BUSINESS_INPUT_INVALID',
  'seller identity override is rejected structurally'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000022',
    pg_temp.quotation_business_input() || jsonb_build_object('terms_sha256', repeat('0', 64))
  )$$,
  '22023', 'QUOTATION_BUSINESS_INPUT_INVALID',
  'terms hash injection is rejected structurally'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000002',
    0, 'ba160000-0000-4000-8000-000000000023', pg_temp.quotation_business_input()
  )$$,
  'P0001', 'PRICING_INTEGRITY_INVALID',
  'persisted snapshot outside the strict integrity contract fails closed'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000005',
    jsonb_set(pg_temp.quotation_business_input(), '{commercial_lines,0,unit_price_minor}', '1')
  )$$,
  '22023', 'COMMERCIAL_LINE_INPUT_INVALID',
  'client price override is rejected structurally'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000006', pg_temp.quotation_business_input('starter_floor')
  )$$,
  'P0001', 'PRICING_RULE_NOT_EXACT', 'FROM pricing fails closed'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000007', pg_temp.quotation_business_input('customer_login')
  )$$,
  'P0001', 'PRICING_RULE_NOT_EXACT', 'MANUAL pricing fails closed'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000008', pg_temp.quotation_business_input('contact_form')
  )$$,
  'P0001', 'PRICING_RULE_NOT_EXACT', 'INCLUDED pricing fails closed'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000009', pg_temp.quotation_business_input('extra_standard_page', 2)
  )$$,
  'P0001', 'PRICING_RULE_QUANTITY_MISMATCH', 'frozen quantity cannot be overridden'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000010', pg_temp.quotation_business_input('extra_standard_page', 1, -1)
  )$$,
  '22023', 'DISCOUNT_INVALID', 'negative discount is rejected'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000011', pg_temp.quotation_business_input('extra_standard_page', 1, 1000)
  )$$,
  '22023', 'DISCOUNT_REASON_REQUIRED', 'positive discount requires a reason'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000012', pg_temp.quotation_business_input('extra_standard_page', 1, 0, null, 99)
  )$$,
  '22023', 'PAYMENT_SCHEDULE_INVALID', '99 percent payment schedule is rejected'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000013', pg_temp.quotation_business_input('extra_standard_page', 1, 0, null, 101)
  )$$,
  '22023', 'PAYMENT_SCHEDULE_INVALID', '101 percent payment schedule is rejected'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000014', pg_temp.quotation_business_input('extra_standard_page', 1, 0, null, null, 19999)
  )$$,
  '22023', 'PAYMENT_SCHEDULE_INVALID', 'amount payment schedule must equal authoritative total'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000015',
    pg_temp.quotation_business_input('extra_standard_page', 1, 0, null, 100, null, 'ba150000-0000-4000-8000-000000000001')
  )$$,
  'P0001', 'QUOTATION_TERMS_NOT_APPROVED', 'retired terms fail closed'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000016',
    pg_temp.quotation_business_input('extra_standard_page', 1, 0, null, 100, null, 'ba150000-0000-4000-8000-000000000099')
  )$$,
  'P0001', 'QUOTATION_TERMS_NOT_APPROVED', 'unknown terms fail closed'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000017',
    pg_temp.quotation_business_input('extra_standard_page', 1, 0, null, 100, null, 'b1010000-0000-4000-8000-000000000001', 'ba000000-0000-4000-8000-000000000099')
  )$$,
  'P0001', 'QUOTATION_VAT_DECISION_NOT_APPROVED', 'unknown VAT authority fails closed'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000018', pg_temp.quotation_business_input('extra_standard_page', 1, 0, null, 100, null, 'b1010000-0000-4000-8000-000000000001', 'ba000000-0000-4000-8000-000000000001', 0)
  )$$,
  '22023', 'VALIDITY_DAYS_INVALID', 'invalid validity override is rejected'
);

select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba100000-0000-4000-8000-000000000001', 'ba130000-0000-4000-8000-000000000001',
    0, 'ba160000-0000-4000-8000-000000000019', pg_temp.quotation_business_input()
  )$$,
  'P0001', 'QUOTATION_PRICING_FROM_UNRESOLVED',
  'snapshot with known minimum 200000 cannot quote only its FIXED 20000 component'
);

select throws_ok(
  $$select lws_internal.assert_quotation_frozen_rule_coverage_v1(
    '{"knownMinimumMinor":30000,"appliedRules":[
      {"ruleId":"fixed-a","mode":"fixed","amountMinor":10000,"quantity":1,"knownMinimumContributionMinor":10000},
      {"ruleId":"fixed-b","mode":"fixed","amountMinor":20000,"quantity":1,"knownMinimumContributionMinor":20000}
    ]}',
    '[{"rule_id":"fixed-a","quantity":1,"description_context":"A"}]'
  )$$,
  'P0001', 'QUOTATION_FIXED_RULE_COVERAGE_INCOMPLETE',
  'omitted relevant FIXED rule is rejected'
);
select throws_ok(
  $$select lws_internal.assert_quotation_frozen_rule_coverage_v1(
    '{"knownMinimumMinor":180000,"appliedRules":[
      {"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000}
    ]}', '[]'
  )$$,
  'P0001', 'QUOTATION_PRICING_FROM_UNRESOLVED',
  'unresolved FROM rule blocks canonical quotation pricing'
);
select throws_ok(
  $$select lws_internal.assert_quotation_frozen_rule_coverage_v1(
    '{"knownMinimumMinor":0,"appliedRules":[
      {"ruleId":"customer_login","mode":"manual","quantity":1,"knownMinimumContributionMinor":0}
    ]}', '[]'
  )$$,
  'P0001', 'QUOTATION_PRICING_MANUAL_UNRESOLVED',
  'unresolved MANUAL rule blocks canonical quotation pricing'
);
select is(
  lws_internal.assert_quotation_frozen_rule_coverage_v1(
    '{"knownMinimumMinor":0,"appliedRules":[
      {"ruleId":"contact_form","mode":"included","quantity":1,"knownMinimumContributionMinor":0}
    ]}', '[]'
  ),
  0::bigint,
  'INCLUDED-only evidence creates no standalone priced line'
);
select is(
  lws_internal.assert_quotation_frozen_rule_coverage_v1(
    '{"knownMinimumMinor":30000,"appliedRules":[
      {"ruleId":"fixed-a","mode":"fixed","amountMinor":10000,"quantity":1,"knownMinimumContributionMinor":10000},
      {"ruleId":"fixed-b","mode":"fixed","amountMinor":20000,"quantity":1,"knownMinimumContributionMinor":20000}
    ]}',
    '[
      {"rule_id":"fixed-a","quantity":1,"description_context":"A"},
      {"rule_id":"fixed-b","quantity":1,"description_context":"B"}
    ]'
  ),
  30000::bigint,
  'complete exclusively FIXED frozen calculation is coverage-valid'
);
select throws_ok(
  $$select lws_internal.assert_quotation_frozen_rule_coverage_v1(
    '{"knownMinimumMinor":40000,"appliedRules":[
      {"ruleId":"fixed-a","mode":"fixed","amountMinor":10000,"quantity":1,"knownMinimumContributionMinor":10000},
      {"ruleId":"fixed-b","mode":"fixed","amountMinor":20000,"quantity":1,"knownMinimumContributionMinor":20000}
    ]}',
    '[
      {"rule_id":"fixed-a","quantity":1,"description_context":"A"},
      {"rule_id":"fixed-b","quantity":1,"description_context":"B"}
    ]'
  )$$,
  'P0001', 'QUOTATION_KNOWN_MINIMUM_MISMATCH',
  'selected exact total below authoritative known minimum is rejected'
);

create temporary table quotation_authority_activation_results (
  authority_type text primary key,
  result jsonb not null
);
grant select, insert on quotation_authority_activation_results to service_role;
set local role service_role;
insert into quotation_authority_activation_results values
  ('SELLER', public.activate_quotation_business_authority_version_v1(
    'ba100000-0000-4000-8000-000000000002', 'SELLER',
    jsonb_build_object(
      'seller_id', 'LORENZO_WEB_SOLUTIONS',
      'seller_version', '1.0.1-test',
      'seller_identity', (select seller_identity from public.resolve_quotation_seller_authority_v1())
    ),
    'Rollback-only lifecycle test'
  )),
  ('TERMS', public.activate_quotation_business_authority_version_v1(
    'ba100000-0000-4000-8000-000000000002', 'TERMS',
    jsonb_build_object(
      'terms_id', 'LWS_GENERAL_TERMS_NL_BE',
      'terms_version', '1.1-test',
      'terms_sha256', repeat('c', 64),
      'source_path', 'TEST_ONLY',
      'effective_from', '2026-08-28'
    ),
    'Rollback-only lifecycle test'
  )),
  ('VAT', public.activate_quotation_business_authority_version_v1(
    'ba100000-0000-4000-8000-000000000002', 'VAT',
    jsonb_build_object(
      'decision_code', 'TEST_STANDARD',
      'decision_version', '1.1-test',
      'vat_treatment', 'STANDARD',
      'vat_rate', 21,
      'authority_source_identifier', 'TEST_ONLY_V2'
    ),
    'Rollback-only lifecycle test'
  )),
  ('POLICY', public.activate_quotation_business_authority_version_v1(
    'ba100000-0000-4000-8000-000000000002', 'POLICY',
    jsonb_build_object(
      'policy_id', 'QUOTATION_BUSINESS_V1',
      'policy_version', '1.0.1-test',
      'exact_pricing_mode', 'FIXED',
      'default_validity_days', 30
    ),
    'Rollback-only lifecycle test'
  ));
reset role;

select is((select count(*)::integer from quotation_authority_activation_results), 4, 'all four authority families activate a new version');
select is((select status from public.quotation_seller_authorities where seller_authority_id = 'b1000000-0000-4000-8000-000000000001'), 'RETIRED', 'previous seller version is retired');
select is((select status from public.quotation_terms_authorities where terms_authority_id = 'b1010000-0000-4000-8000-000000000001'), 'RETIRED', 'previous terms version is retired');
select is((select status from public.quotation_vat_decision_authorities where vat_decision_authority_id = 'ba000000-0000-4000-8000-000000000001'), 'RETIRED', 'previous VAT version is retired');
select is((select status from public.quotation_business_policy_authorities where policy_authority_id = 'b1020000-0000-4000-8000-000000000001'), 'RETIRED', 'previous policy version is retired');
select is((select count(*)::integer from public.quotation_seller_authorities where seller_id = 'LORENZO_WEB_SOLUTIONS' and status = 'APPROVED'), 1, 'seller family has exactly one active version');
select is((select count(*)::integer from public.quotation_terms_authorities where terms_id = 'LWS_GENERAL_TERMS_NL_BE' and status = 'APPROVED'), 1, 'terms family has exactly one active version');
select is((select count(*)::integer from public.quotation_vat_decision_authorities where decision_code = 'TEST_STANDARD' and status = 'APPROVED'), 1, 'VAT family has exactly one active version');
select is((select count(*)::integer from public.quotation_business_policy_authorities where policy_id = 'QUOTATION_BUSINESS_V1' and status = 'APPROVED'), 1, 'policy family has exactly one active version');
select is((select seller_identity->>'email' from public.quotation_seller_authorities where seller_authority_id = 'b1000000-0000-4000-8000-000000000001'), 'info@lorenzowebsolution.be', 'retirement preserves prior seller content');

select is(
  extensions.dblink_connect(
    'quotation_business_concurrency_setup',
    'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=quotation_business_concurrency_setup'
  ),
  'OK',
  'concurrency setup connection opens'
);
select lives_ok(
  $test$select extensions.dblink_exec(
    'quotation_business_concurrency_setup',
    $setup$
      insert into auth.users(id, email) values
        ('ba200000-0000-4000-8000-000000000001', 'quotation-concurrency-owner@example.test');
      insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
        ('ba210000-0000-4000-8000-000000000001', 'ba200000-0000-4000-8000-000000000001', 'Quotation Concurrency Owner', 'owner', 'ACTIVE');
      insert into public.quote_requests(
        id, name, email, company, website_type, budget, timing, description,
        privacy_consent, status, billing_address, billing_postal_code, billing_city, billing_country
      ) values (
        'ba220000-0000-4000-8000-000000000001', 'Concurrency Contact',
        'quotation-concurrency@example.test', 'Concurrency Customer BV', 'business',
        'EUR 3.200 t/m EUR 6.000', 'flexible', 'Concurrency fixture', true,
        'approved', 'Teststraat 2', '9000', 'Gent', 'BE'
      );
      insert into public.quote_request_intakes(
        id, quote_request_id, access_token_hash, access_token_expires_at,
        status, started_at, submitted_at, confirmation,
        admin_access_token_hash, admin_access_token_expires_at
      ) values (
        'ba230000-0000-4000-8000-000000000001', 'ba220000-0000-4000-8000-000000000001',
        repeat('3',64), clock_timestamp()+interval '1 day', 'submitted', clock_timestamp(),
        clock_timestamp(), true, repeat('d',64), clock_timestamp()+interval '1 day'
      );
      insert into public.quote_request_pricing_snapshots(
        id,intake_id,snapshot_contract_version,config_version,config_hash,
        normalized_evidence,calculation,package_advice,budget_evaluation
      ) values (
        'ba240000-0000-4000-8000-000000000001', 'ba230000-0000-4000-8000-000000000001',
        2,'1.0.0',repeat('2',64),
        '{"standardPages":["home","about","services","portfolio","contact","products"],"standardPageCount":6,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[{"id":"forms","classification":"contact","evidence":["contact_form_intent"]}],"manualComponents":[]}',
        '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":200000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000},{"ruleId":"extra_standard_page","mode":"fixed","amountMinor":20000,"quantity":1,"knownMinimumContributionMinor":20000},{"ruleId":"contact_form","mode":"included","quantity":1,"knownMinimumContributionMinor":0}]}',
        '{"status":"consider_professional","reasons":["standard_page_count_above_starter_scope"],"advisoryOnly":true,"selectedPackage":null}',
        '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}'
      );
      insert into public.quote_request_pricing_snapshot_integrity(snapshot_id,algorithm_version,key_id,mac) values
        ('ba240000-0000-4000-8000-000000000001','hmac-sha256-v1','v1',repeat('c',64));
      insert into public.quotation_vat_decision_authorities(
        vat_decision_authority_id,decision_code,decision_version,vat_treatment,vat_rate,
        authority_source_identifier,status,approved_by,approved_at
      ) values (
        'ba250000-0000-4000-8000-000000000001','CONCURRENCY_STANDARD','1.0.0',
        'STANDARD',21,'TEST_ONLY','APPROVED','TEST','2026-08-28T00:00:00Z'
      );
      with payload(value) as (values ('{
        "contract_version":1,
        "source_quote_request_id":"ba220000-0000-4000-8000-000000000001",
        "source_intake_id":"ba230000-0000-4000-8000-000000000001",
        "pricing_snapshot":{"snapshot_id":"ba240000-0000-4000-8000-000000000001","snapshot_contract_version":2,"integrity_algorithm_version":"hmac-sha256-v1","integrity_key_id":"v1","integrity_mac":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"},
        "currency":"EUR",
        "line_items":[{"line_id":"pricing-rule:extra_standard_page","sequence":1,"product_or_service_code":"extra_standard_page","description":"Governed quotation line","quantity":1,"unit":"item","unit_price_minor":20000,"discount_minor":0,"vat_treatment":"STANDARD","vat_rate":21,"line_net_amount_minor":20000,"cost_type":"ONE_TIME"}],
        "totals":{"one_time_subtotal_minor":20000,"recurring_subtotal_minor":0,"discount_total_minor":0,"vat_base_minor":20000,"vat_amount_minor":4200,"total_gross_minor":24200},
        "discount":{"discount_type":null,"discount_value_minor":0,"discount_reason":null,"approved_by":null,"approved_at":null},
        "customer_identity":{"source_quote_request_id":"ba220000-0000-4000-8000-000000000001","source_intake_id":"ba230000-0000-4000-8000-000000000001","customer_id":null,"legal_name":"Concurrency Customer BV","contact_name":"Concurrency Contact","email":"quotation-concurrency@example.test","address_line_1":"Teststraat 2","address_line_2":null,"postal_code":"9000","city":"Gent","country_code":"BE","enterprise_number":null,"vat_number":null,"source_fields":{"legal_name":"quote_requests.company"},"snapshot_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
        "project_scope":{"project_id":null,"project_title":"Canonical website","project_type":"website","scope_summary":"Frozen exact quotation scope","requested_languages":["nl"],"included_page_count":6,"features":["contact_form"],"copywriting":null,"seo":null,"hosting":null,"maintenance":null,"exclusions":[],"assumptions":[],"indicative_timing":null,"source_intake_id":"ba230000-0000-4000-8000-000000000001","source_pricing_snapshot_id":"ba240000-0000-4000-8000-000000000001","snapshot_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
        "vat_approval":{"vat_treatment":"STANDARD","vat_rate":21,"vat_decision_source":"TEST_ONLY","vat_approved_by":"OPERATOR:ba210000-0000-4000-8000-000000000001","vat_approved_at":"2026-08-28T00:00:00Z"},
        "payment_schedule":{"schedule_id":"quotation-concurrency","milestones":[{"sequence":1,"label":"Volledige betaling","percentage":100,"amount_minor":null,"trigger":"invoice","due_terms_days":30,"recurring_cycle":null}],"approved_by":"OPERATOR:ba210000-0000-4000-8000-000000000001","approved_at":"2026-08-28T00:00:00Z"},
        "validity":{"valid_from":"2026-08-28","valid_until":"2026-09-27","validity_days":30,"approved_by":"OPERATOR:ba210000-0000-4000-8000-000000000001","approved_at":"2026-08-28T00:00:00Z"},
        "legal_references":{"terms_reference":"LWS_GENERAL_TERMS_NL_BE","terms_version":"1.0","terms_sha256":"e3898aa99103c52354537550fda583a2dca7302329622115ecb39080a5eb4a32","terms_status":"APPROVED","agreement_template_reference":null,"agreement_template_version":null,"agreement_template_sha256":null}
      }'::jsonb)),
      draft as (
        insert into public.quote_request_quotation_approval_drafts(
          id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,
          approval_payload,payload_fingerprint,idempotency_key,created_by
        ) select
          'ba270000-0000-4000-8000-000000000001','ba220000-0000-4000-8000-000000000001',
          'ba230000-0000-4000-8000-000000000001','ba240000-0000-4000-8000-000000000001',
          1,value,public.quotation_approval_payload_sha256_v1(value),
          'ba260000-0000-4000-8000-000000000001','TEST'
        from payload returning id
      ), input(value) as (values ('{
        "commercial_lines":[{"rule_id":"extra_standard_page","quantity":1,"description_context":"Governed quotation line"}],
        "discount":{"discount_type":null,"discount_value_minor":0,"discount_reason":null},
        "scope":{"project_title":"Canonical website","project_type":"website","scope_summary":"Frozen exact quotation scope","requested_languages":["nl"],"included_page_count":6,"features":["contact_form"],"copywriting":null,"seo":null,"hosting":null,"maintenance":null,"exclusions":[],"assumptions":[],"indicative_timing":null},
        "vat_decision_authority_id":"ba250000-0000-4000-8000-000000000001",
        "terms_authority_id":"b1010000-0000-4000-8000-000000000001",
        "payment_schedule":{"milestones":[{"sequence":1,"label":"Volledige betaling","percentage":100,"amount_minor":null,"trigger":"invoice","due_terms_days":30,"recurring_cycle":null}]},
        "validity_days":null
      }'::jsonb))
      insert into public.quote_request_quotation_business_drafts(
        business_draft_id,approval_draft_id,quote_request_id,intake_id,pricing_snapshot_id,
        business_revision,operator_id,seller_authority_id,terms_authority_id,
        vat_decision_authority_id,template_authority_id,policy_authority_id,
        canonical_payload,canonical_payload_sha256,request_fingerprint,idempotency_key,
        result_payload,prepared_by_actor,prepared_at
      ) select
        'ba280000-0000-4000-8000-000000000001','ba270000-0000-4000-8000-000000000001',
        'ba220000-0000-4000-8000-000000000001','ba230000-0000-4000-8000-000000000001',
        'ba240000-0000-4000-8000-000000000001',1,'ba210000-0000-4000-8000-000000000001',
        'b1000000-0000-4000-8000-000000000001','b1010000-0000-4000-8000-000000000001',
        'ba250000-0000-4000-8000-000000000001',
        (select id from public.quotation_template_authorities where status='APPROVED'),
        'b1020000-0000-4000-8000-000000000001',payload.value,
        public.quotation_approval_payload_sha256_v1(payload.value),
        encode(extensions.digest(convert_to(jsonb_build_object(
          'actorAuthUserId','ba200000-0000-4000-8000-000000000001'::uuid,
          'expectedRevision',0,'input',input.value,
          'intakeId','ba230000-0000-4000-8000-000000000001'::uuid
        )::text,'UTF8'),'sha256'),'hex'),
        'ba260000-0000-4000-8000-000000000001',
        jsonb_build_object('business_revision',1,'canonical_payload_sha256',public.quotation_approval_payload_sha256_v1(payload.value),'marker','CONCURRENT_REPLAY'),
        'OPERATOR:ba210000-0000-4000-8000-000000000001','2026-08-28T00:00:00Z'
      from payload,input;
    $setup$
  )$test$,
  'committed concurrency ledger fixture is created outside the pgTAP transaction'
);
select is(extensions.dblink_connect('quotation_business_retry_a','host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=quotation_business_retry_a'),'OK','first retry connection opens');
select is(extensions.dblink_connect('quotation_business_retry_b','host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=quotation_business_retry_b'),'OK','second retry connection opens');
select ok(extensions.dblink_send_query('quotation_business_retry_a',$query$with lock_contention as materialized (
  select pg_advisory_xact_lock(hashtextextended('ba260000-0000-4000-8000-000000000001',0)), pg_sleep(1)
)
select public.upsert_quotation_business_draft_v1(
  'ba200000-0000-4000-8000-000000000001','ba230000-0000-4000-8000-000000000001',0,
  'ba260000-0000-4000-8000-000000000001','{"commercial_lines":[{"rule_id":"extra_standard_page","quantity":1,"description_context":"Governed quotation line"}],"discount":{"discount_type":null,"discount_value_minor":0,"discount_reason":null},"scope":{"project_title":"Canonical website","project_type":"website","scope_summary":"Frozen exact quotation scope","requested_languages":["nl"],"included_page_count":6,"features":["contact_form"],"copywriting":null,"seo":null,"hosting":null,"maintenance":null,"exclusions":[],"assumptions":[],"indicative_timing":null},"vat_decision_authority_id":"ba250000-0000-4000-8000-000000000001","terms_authority_id":"b1010000-0000-4000-8000-000000000001","payment_schedule":{"milestones":[{"sequence":1,"label":"Volledige betaling","percentage":100,"amount_minor":null,"trigger":"invoice","due_terms_days":30,"recurring_cycle":null}]},"validity_days":null}'
) from lock_contention$query$)=1,'first identical retry starts while holding the idempotency lock');
select ok(extensions.dblink_send_query('quotation_business_retry_b',$query$select public.upsert_quotation_business_draft_v1(
  'ba200000-0000-4000-8000-000000000001','ba230000-0000-4000-8000-000000000001',0,
  'ba260000-0000-4000-8000-000000000001','{"commercial_lines":[{"rule_id":"extra_standard_page","quantity":1,"description_context":"Governed quotation line"}],"discount":{"discount_type":null,"discount_value_minor":0,"discount_reason":null},"scope":{"project_title":"Canonical website","project_type":"website","scope_summary":"Frozen exact quotation scope","requested_languages":["nl"],"included_page_count":6,"features":["contact_form"],"copywriting":null,"seo":null,"hosting":null,"maintenance":null,"exclusions":[],"assumptions":[],"indicative_timing":null},"vat_decision_authority_id":"ba250000-0000-4000-8000-000000000001","terms_authority_id":"b1010000-0000-4000-8000-000000000001","payment_schedule":{"milestones":[{"sequence":1,"label":"Volledige betaling","percentage":100,"amount_minor":null,"trigger":"invoice","due_terms_days":30,"recurring_cycle":null}]},"validity_days":null}'
)$query$)=1,'second identical retry starts');
create temporary table quotation_business_concurrent_results as
select result from extensions.dblink_get_result('quotation_business_retry_a') as replay(result jsonb)
union all
select result from extensions.dblink_get_result('quotation_business_retry_b') as replay(result jsonb);
select is((select count(*)::integer from quotation_business_concurrent_results),2,'both concurrent retries return a result without stale revision');
select is((select count(distinct result)::integer from quotation_business_concurrent_results),1,'concurrent retries return semantically identical results');
select is((select count(*)::integer from public.quote_request_quotation_business_drafts where idempotency_key='ba260000-0000-4000-8000-000000000001'),1,'concurrent retries retain exactly one authoritative business ledger row');
select is((select count(*)::integer from public.quote_request_quotation_approval_drafts where idempotency_key='ba260000-0000-4000-8000-000000000001'),1,'concurrent retries retain exactly one approval draft');
select throws_ok(
  $$select public.upsert_quotation_business_draft_v1(
    'ba200000-0000-4000-8000-000000000001','ba230000-0000-4000-8000-000000000001',0,
    'ba260000-0000-4000-8000-000000000001',
    '{"commercial_lines":[{"rule_id":"extra_standard_page","quantity":1,"description_context":"Changed description"}],"discount":{"discount_type":null,"discount_value_minor":0,"discount_reason":null},"scope":{"project_title":"Canonical website","project_type":"website","scope_summary":"Frozen exact quotation scope","requested_languages":["nl"],"included_page_count":6,"features":["contact_form"],"copywriting":null,"seo":null,"hosting":null,"maintenance":null,"exclusions":[],"assumptions":[],"indicative_timing":null},"vat_decision_authority_id":"ba250000-0000-4000-8000-000000000001","terms_authority_id":"b1010000-0000-4000-8000-000000000001","payment_schedule":{"milestones":[{"sequence":1,"label":"Volledige betaling","percentage":100,"amount_minor":null,"trigger":"invoice","due_terms_days":30,"recurring_cycle":null}]},"validity_days":null}'
  )$$,
  'P0001','IDEMPOTENCY_CONFLICT','same idempotency key with changed valid payload fails closed'
);
select is(extensions.dblink_disconnect('quotation_business_retry_a'),'OK','first retry connection closes');
select is(extensions.dblink_disconnect('quotation_business_retry_b'),'OK','second retry connection closes');
select lives_ok(
  $test$select extensions.dblink_exec('quotation_business_concurrency_setup',$cleanup$
    set session_replication_role = replica;
    delete from public.quote_request_quotation_business_drafts where business_draft_id='ba280000-0000-4000-8000-000000000001';
    delete from public.quote_request_quotation_approval_drafts where id='ba270000-0000-4000-8000-000000000001';
    delete from public.quotation_vat_decision_authorities where vat_decision_authority_id='ba250000-0000-4000-8000-000000000001';
    delete from public.quote_request_pricing_snapshot_integrity where snapshot_id='ba240000-0000-4000-8000-000000000001';
    delete from public.quote_request_pricing_snapshots where id='ba240000-0000-4000-8000-000000000001';
    delete from public.quote_request_intakes where id='ba230000-0000-4000-8000-000000000001';
    delete from lws_internal.operator_dossier_assignments where quote_request_id='ba220000-0000-4000-8000-000000000001';
    delete from lws_internal.operator_dossier_states where quote_request_id='ba220000-0000-4000-8000-000000000001';
    delete from public.quote_requests where id='ba220000-0000-4000-8000-000000000001';
    delete from public.commercial_operators where operator_id='ba210000-0000-4000-8000-000000000001';
    delete from auth.users where id='ba200000-0000-4000-8000-000000000001';
    set session_replication_role = origin;
  $cleanup$)$test$,
  'committed concurrency fixture is removed'
);
select is(extensions.dblink_disconnect('quotation_business_concurrency_setup'),'OK','concurrency setup connection closes');

select * from finish();
rollback;