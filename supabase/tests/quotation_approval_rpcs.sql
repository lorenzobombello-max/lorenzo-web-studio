begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(37);

select has_function(
  'public', 'upsert_quotation_approval_draft_v1',
  array['uuid','uuid','uuid','jsonb','uuid','text','text'],
  'versioned draft upsert RPC exists'
);
select has_function(
  'public', 'approve_quotation_commercial_envelope_v1',
  array['uuid','uuid','jsonb','uuid','text','text','jsonb'],
  'versioned commercial approval RPC exists'
);
select has_table(
  'public', 'quote_request_quotation_approval_operations',
  'immutable approval operation ledger exists'
);
select ok(
  not has_function_privilege('anon', 'public.upsert_quotation_approval_draft_v1(uuid,uuid,uuid,jsonb,uuid,text,text)', 'execute'),
  'anon cannot execute draft RPC'
);
select ok(
  not has_function_privilege('authenticated', 'public.approve_quotation_commercial_envelope_v1(uuid,uuid,jsonb,uuid,text,text,jsonb)', 'execute'),
  'authenticated cannot execute approval RPC'
);
select ok(
  has_function_privilege('service_role', 'public.upsert_quotation_approval_draft_v1(uuid,uuid,uuid,jsonb,uuid,text,text)', 'execute'),
  'service role can execute draft RPC'
);
select ok(
  has_function_privilege('service_role', 'public.approve_quotation_commercial_envelope_v1(uuid,uuid,jsonb,uuid,text,text,jsonb)', 'execute'),
  'service role can execute approval RPC'
);
select ok(
  not has_table_privilege('service_role', 'public.quote_request_quotation_approval_operations', 'insert'),
  'service role cannot bypass operation RPC'
);

create temporary table d3e2_fixture as
select jsonb_build_object(
  'contract_version', 1,
  'source_quote_request_id', 'd3e20000-0000-4000-8000-000000000001',
  'source_intake_id', 'd3e21000-0000-4000-8000-000000000001',
  'pricing_snapshot', jsonb_build_object(
    'snapshot_id', 'd3e22000-0000-4000-8000-000000000001',
    'snapshot_contract_version', 2,
    'integrity_algorithm_version', 'hmac-sha256-v1',
    'integrity_key_id', 'v1',
    'integrity_mac', repeat('a', 64)
  ),
  'currency', 'EUR',
  'line_items', jsonb_build_array(jsonb_build_object(
    'line_id', 'website', 'sequence', 1,
    'product_or_service_code', 'WEBSITE',
    'description', 'Websiteontwikkeling', 'quantity', 1, 'unit', 'project',
    'unit_price_minor', 100000, 'discount_minor', 0,
    'vat_treatment', 'STANDARD', 'vat_rate', 21,
    'line_net_amount_minor', 100000, 'cost_type', 'ONE_TIME'
  )),
  'totals', jsonb_build_object(
    'one_time_subtotal_minor', 100000, 'recurring_subtotal_minor', 0,
    'discount_total_minor', 0, 'vat_base_minor', 100000,
    'vat_amount_minor', 21000, 'total_gross_minor', 121000
  ),
  'discount', jsonb_build_object(
    'discount_type', null, 'discount_value_minor', 0,
    'discount_reason', null, 'approved_by', null, 'approved_at', null
  ),
  'customer_identity', jsonb_build_object(
    'source_quote_request_id', 'd3e20000-0000-4000-8000-000000000001',
    'source_intake_id', 'd3e21000-0000-4000-8000-000000000001',
    'customer_id', null, 'legal_name', 'Test Customer', 'contact_name', null,
    'email', 'test@example.test', 'address_line_1', 'Teststraat 1',
    'address_line_2', null, 'postal_code', '9000', 'city', 'Gent',
    'country_code', 'BE', 'enterprise_number', null, 'vat_number', null,
    'source_fields', jsonb_build_object('legal_name', 'quote_request.company'),
    'snapshot_sha256', repeat('b', 64)
  ),
  'project_scope', jsonb_build_object(
    'project_id', null, 'project_title', 'Test website',
    'project_type', 'website', 'scope_summary', 'Fictieve scope',
    'requested_languages', jsonb_build_array('nl'), 'included_page_count', 5,
    'features', jsonb_build_array('contact_form'), 'copywriting', null,
    'seo', null, 'hosting', null, 'maintenance', null,
    'exclusions', '[]'::jsonb, 'assumptions', '[]'::jsonb,
    'indicative_timing', null,
    'source_intake_id', 'd3e21000-0000-4000-8000-000000000001',
    'source_pricing_snapshot_id', 'd3e22000-0000-4000-8000-000000000001',
    'snapshot_sha256', repeat('c', 64)
  ),
  'vat_approval', jsonb_build_object(
    'vat_treatment', 'STANDARD', 'vat_rate', 21,
    'vat_decision_source', 'accountant',
    'vat_approved_by', 'accountant:test',
    'vat_approved_at', '2026-08-15T12:00:00Z'
  ),
  'payment_schedule', jsonb_build_object(
    'schedule_id', 'schedule-1',
    'milestones', jsonb_build_array(jsonb_build_object(
      'sequence', 1, 'label', 'Volledige betaling', 'percentage', 100,
      'amount_minor', null, 'trigger', 'invoice',
      'due_terms_days', 30, 'recurring_cycle', null
    )),
    'approved_by', 'commercial:test',
    'approved_at', '2026-08-15T12:00:00Z'
  ),
  'validity', jsonb_build_object(
    'valid_from', '2026-08-15', 'valid_until', '2026-09-14',
    'validity_days', 30, 'approved_by', 'commercial:test',
    'approved_at', '2026-08-15T12:00:00Z'
  ),
  'legal_references', jsonb_build_object(
    'terms_reference', 'terms-v1', 'terms_version', '1.0.0',
    'terms_sha256', repeat('d', 64), 'terms_status', 'APPROVED',
    'agreement_template_reference', null,
    'agreement_template_version', null,
    'agreement_template_sha256', null
  )
) as payload,
'{
  "standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl",
  "additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]
}'::jsonb as normalized_scope,
'{
  "basis":"starter_floor","currency":"EUR","vatBasis":"exclusive",
  "knownMinimumMinor":180000,"containsFromPricing":true,
  "manualReviewRequired":false,"manualReasons":[],
  "appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":180000,
    "quantity":1,"knownMinimumContributionMinor":180000}]
}'::jsonb as calculation,
'{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}'::jsonb as package_advice,
'{
  "contractVersion":2,"evidenceProvenance":"budget_guard_v1",
  "categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive",
  "originalLabel":"EUR 3.200 t/m EUR 6.000",
  "status":"possibly_compatible_with_category","outsideBudgetWishes":false
}'::jsonb as budget_evaluation;

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status
) values (
  'd3e20000-0000-4000-8000-000000000001', 'D3E2 test',
  'd3e2@example.test', 'business', 'EUR 3.200 t/m EUR 6.000',
  'flexible', 'D3E2 quotation approval RPC fixture', true, 'approved'
);

insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at,
  status, started_at, submitted_at, confirmation,
  admin_access_token_hash, admin_access_token_expires_at
) values (
  'd3e21000-0000-4000-8000-000000000001',
  'd3e20000-0000-4000-8000-000000000001', repeat('1', 64),
  clock_timestamp() + interval '1 day', 'submitted', clock_timestamp(),
  clock_timestamp(), true, repeat('f', 64), clock_timestamp() + interval '1 day'
);

insert into public.quote_request_pricing_snapshots (
  id, intake_id, snapshot_contract_version, config_version, config_hash,
  normalized_evidence, calculation, package_advice, budget_evaluation
)
select 'd3e22000-0000-4000-8000-000000000001',
  'd3e21000-0000-4000-8000-000000000001', 2, '1.0.0', repeat('1', 64),
  normalized_scope, calculation, package_advice, budget_evaluation
from d3e2_fixture;

insert into public.quote_request_pricing_snapshot_integrity (
  snapshot_id, algorithm_version, key_id, mac
) values (
  'd3e22000-0000-4000-8000-000000000001',
  'hmac-sha256-v1', 'v1', repeat('a', 64)
);

select is(
  (select was_created from public.upsert_quotation_approval_draft_v1(
    'd3e20000-0000-4000-8000-000000000001',
    'd3e21000-0000-4000-8000-000000000001',
    'd3e22000-0000-4000-8000-000000000001',
    (select payload from d3e2_fixture),
    'd3e23000-0000-4000-8000-000000000001', repeat('f', 64), 'admin:test'
  )), true, 'valid draft is created'
);

select is(
  (select was_created from public.upsert_quotation_approval_draft_v1(
    'd3e20000-0000-4000-8000-000000000001',
    'd3e21000-0000-4000-8000-000000000001',
    'd3e22000-0000-4000-8000-000000000001',
    (select payload from d3e2_fixture),
    'd3e23000-0000-4000-8000-000000000001', repeat('f', 64), 'admin:test'
  )), false, 'same draft idempotency retry returns existing result'
);

select is(
  (select count(*)::integer from public.quote_request_quotation_approval_drafts),
  1, 'idempotent draft retry creates one draft'
);

select throws_ok(
  $$select * from public.upsert_quotation_approval_draft_v1(
    'd3e20000-0000-4000-8000-000000000001',
    'd3e21000-0000-4000-8000-000000000001',
    'd3e22000-0000-4000-8000-000000000001',
    jsonb_set((select payload from d3e2_fixture), '{project_scope,project_title}', '"Changed"'),
    'd3e23000-0000-4000-8000-000000000001', repeat('f', 64), 'admin:test'
  )$$,
  'P0001', 'IDEMPOTENCY_CONFLICT', 'same draft key with changed payload conflicts'
);

select is(
  (select was_created from public.upsert_quotation_approval_draft_v1(
    'd3e20000-0000-4000-8000-000000000001',
    'd3e21000-0000-4000-8000-000000000001',
    'd3e22000-0000-4000-8000-000000000001',
    jsonb_set((select payload from d3e2_fixture), '{project_scope,project_title}', '"Changed"'),
    'd3e23000-0000-4000-8000-000000000002', repeat('f', 64), 'admin:test'
  )), false, 'new idempotency key updates the mutable draft'
);

select is(
  (select payload_fingerprint from public.upsert_quotation_approval_draft_v1(
    'd3e20000-0000-4000-8000-000000000001',
    'd3e21000-0000-4000-8000-000000000001',
    'd3e22000-0000-4000-8000-000000000001',
    (select payload from d3e2_fixture),
    'd3e23000-0000-4000-8000-000000000001', repeat('f', 64), 'admin:test'
  )),
  public.quotation_approval_payload_sha256_v1((select payload from d3e2_fixture)),
  'an old draft idempotency key returns its original immutable result fingerprint'
);

select throws_ok(
  $$select * from public.upsert_quotation_approval_draft_v1(
    'd3e20000-0000-4000-8000-000000000001',
    'd3e21000-0000-4000-8000-000000000001',
    'd3e22000-0000-4000-8000-000000000001',
    jsonb_set((select payload from d3e2_fixture), '{line_items,0,quantity}', '0'),
    'd3e23000-0000-4000-8000-000000000003', repeat('f', 64), 'admin:test'
  )$$,
  '22023', 'DRAFT_VALIDATION_FAILED', 'malformed draft is rejected'
);

select throws_ok(
  $$select * from public.upsert_quotation_approval_draft_v1(
    'd3e20000-0000-4000-8000-000000000001',
    'd3e21000-0000-4000-8000-000000000001',
    'd3e22000-0000-4000-8000-000000000001',
    jsonb_set((select payload from d3e2_fixture), '{pricing_snapshot,integrity_mac}', to_jsonb(repeat('0',64))),
    'd3e23000-0000-4000-8000-000000000004', repeat('f', 64), 'admin:test'
  )$$,
  'P0001', 'PRICING_INTEGRITY_INVALID', 'invalid pricing integrity is rejected'
);

select throws_ok(
  $$select * from public.upsert_quotation_approval_draft_v1(
    'd3e20000-0000-4000-8000-000000000001',
    'd3e21000-0000-4000-8000-000000000001',
    'd3e22000-0000-4000-8000-000000000001',
    (select payload from d3e2_fixture),
    'd3e23000-0000-4000-8000-000000000005', repeat('0', 64), 'admin:test'
  )$$,
  '42501', 'UNAUTHORIZED', 'invalid admin capability is rejected'
);

update public.quote_request_quotation_approval_drafts
set approval_payload = (select payload from d3e2_fixture),
    payload_fingerprint = public.quotation_approval_payload_sha256_v1(
      (select payload from d3e2_fixture)
    ),
    idempotency_key = 'd3e23000-0000-4000-8000-000000000006';

create function pg_temp.approval_proof(p_approval_id uuid, p_payload jsonb)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'algorithmVersion', 'hmac-sha256-v1',
    'keyId', 'v1',
    'mac', repeat('e', 64),
    'root', public.quotation_approval_integrity_root_v1(
      p_approval_id,
      public.quotation_approval_payload_sha256_v1(p_payload),
      1::smallint,
      'd3e20000-0000-4000-8000-000000000001'::uuid,
      'd3e21000-0000-4000-8000-000000000001'::uuid,
      'd3e22000-0000-4000-8000-000000000001'::uuid
    )
  )
$$;

select is(
  (select approval_version from public.approve_quotation_commercial_envelope_v1(
    (select id from public.quote_request_quotation_approval_drafts),
    'd3e25000-0000-4000-8000-000000000001',
    (select payload from d3e2_fixture),
    'd3e24000-0000-4000-8000-000000000001', repeat('f', 64), 'admin:test',
    pg_temp.approval_proof(
      'd3e25000-0000-4000-8000-000000000001',
      (select payload from d3e2_fixture)
    )
  )), 1, 'valid draft is approved as version 1'
);

select is(
  (select count(*)::integer from public.quote_request_quotation_approval_integrity),
  1, 'approval integrity proof is created atomically'
);
select is(
  (select payload_sha256 from public.quote_request_quotation_approvals),
  public.quotation_approval_payload_sha256_v1((select payload from d3e2_fixture)),
  'stored approval payload hash is canonical and database-computed'
);

select is(
  (select was_created from public.approve_quotation_commercial_envelope_v1(
    (select id from public.quote_request_quotation_approval_drafts),
    'd3e25000-0000-4000-8000-000000000001',
    (select payload from d3e2_fixture),
    'd3e24000-0000-4000-8000-000000000001', repeat('f', 64), 'admin:test',
    pg_temp.approval_proof(
      'd3e25000-0000-4000-8000-000000000001',
      (select payload from d3e2_fixture)
    )
  )), false, 'same approval retry returns existing approval'
);
select is(
  (select count(*)::integer from public.quote_request_quotation_approvals),
  1, 'approval retry creates no duplicate'
);

select is(
  (select was_created from public.upsert_quotation_approval_draft_v1(
    'd3e20000-0000-4000-8000-000000000001',
    'd3e21000-0000-4000-8000-000000000001',
    'd3e22000-0000-4000-8000-000000000001',
    jsonb_set((select payload from d3e2_fixture), '{project_scope,project_title}', '"Revision draft"'),
    'd3e23000-0000-4000-8000-000000000007', repeat('f', 64), 'admin:test'
  )), false, 'draft can move forward after approval using a new operation key'
);

select is(
  (select was_created from public.approve_quotation_commercial_envelope_v1(
    (select id from public.quote_request_quotation_approval_drafts),
    'd3e25000-0000-4000-8000-000000000001',
    (select payload from d3e2_fixture),
    'd3e24000-0000-4000-8000-000000000001', repeat('f', 64), 'admin:test',
    pg_temp.approval_proof(
      'd3e25000-0000-4000-8000-000000000001',
      (select payload from d3e2_fixture)
    )
  )), false, 'old approval retry remains idempotent after the mutable draft advances'
);

update public.quote_request_quotation_approval_drafts
set approval_payload = (select payload from d3e2_fixture),
    payload_fingerprint = public.quotation_approval_payload_sha256_v1(
      (select payload from d3e2_fixture)
    ),
    idempotency_key = 'd3e23000-0000-4000-8000-000000000008';

select throws_ok(
  $$select * from public.approve_quotation_commercial_envelope_v1(
    (select id from public.quote_request_quotation_approval_drafts),
    'd3e25000-0000-4000-8000-000000000002',
    (select payload from d3e2_fixture),
    'd3e24000-0000-4000-8000-000000000001', repeat('f', 64), 'admin:test',
    pg_temp.approval_proof(
      'd3e25000-0000-4000-8000-000000000002',
      (select payload from d3e2_fixture)
    )
  )$$,
  'P0001', 'IDEMPOTENCY_CONFLICT', 'conflicting approval retry is rejected'
);

select is(
  (select approval_version from public.approve_quotation_commercial_envelope_v1(
    (select id from public.quote_request_quotation_approval_drafts),
    'd3e25000-0000-4000-8000-000000000002',
    (select payload from d3e2_fixture),
    'd3e24000-0000-4000-8000-000000000002', repeat('f', 64), 'admin:test',
    pg_temp.approval_proof(
      'd3e25000-0000-4000-8000-000000000002',
      (select payload from d3e2_fixture)
    )
  )), 2, 'new approval operation appends version 2'
);
select is(
  (select payload_sha256 from public.quote_request_quotation_approvals where approval_version = 1),
  public.quotation_approval_payload_sha256_v1((select payload from d3e2_fixture)),
  'prior approval version remains unchanged'
);

select throws_ok(
  $$select * from public.approve_quotation_commercial_envelope_v1(
    (select id from public.quote_request_quotation_approval_drafts),
    'd3e25000-0000-4000-8000-000000000003',
    jsonb_set((select payload from d3e2_fixture), '{vat_approval}',
      '{"vat_treatment":null,"vat_rate":null,"vat_decision_source":null,"vat_approved_by":null,"vat_approved_at":null}'),
    'd3e24000-0000-4000-8000-000000000003', repeat('f', 64), 'admin:test',
    '{}'::jsonb
  )$$,
  '22023', 'VAT_APPROVAL_MISSING', 'incomplete VAT approval is rejected'
);

select throws_ok(
  $$select * from public.approve_quotation_commercial_envelope_v1(
    (select id from public.quote_request_quotation_approval_drafts),
    'd3e25000-0000-4000-8000-000000000004',
    jsonb_set((select payload from d3e2_fixture), '{payment_schedule,milestones}', '[]'),
    'd3e24000-0000-4000-8000-000000000004', repeat('f', 64), 'admin:test',
    '{}'::jsonb
  )$$,
  '22023', 'PAYMENT_SCHEDULE_UNAPPROVED', 'incomplete payment approval is rejected'
);

select throws_ok(
  $$select * from public.approve_quotation_commercial_envelope_v1(
    (select id from public.quote_request_quotation_approval_drafts),
    'd3e25000-0000-4000-8000-000000000005',
    jsonb_set((select payload from d3e2_fixture), '{validity,validity_days}', '29'),
    'd3e24000-0000-4000-8000-000000000005', repeat('f', 64), 'admin:test',
    '{}'::jsonb
  )$$,
  '22023', 'VALIDITY_UNAPPROVED', 'incomplete validity approval is rejected'
);

select throws_ok(
  $$select * from public.approve_quotation_commercial_envelope_v1(
    (select id from public.quote_request_quotation_approval_drafts),
    'd3e25000-0000-4000-8000-000000000006',
    jsonb_set((select payload from d3e2_fixture), '{legal_references,terms_status}', '"UNAPPROVED"'),
    'd3e24000-0000-4000-8000-000000000006', repeat('f', 64), 'admin:test',
    '{}'::jsonb
  )$$,
  '22023', 'LEGAL_REFERENCE_UNAPPROVED', 'unapproved legal reference is rejected'
);

select throws_ok(
  $$select * from public.approve_quotation_commercial_envelope_v1(
    (select id from public.quote_request_quotation_approval_drafts),
    'd3e25000-0000-4000-8000-000000000007',
    jsonb_set((select payload from d3e2_fixture), '{customer_identity,legal_name}', 'null'),
    'd3e24000-0000-4000-8000-000000000007', repeat('f', 64), 'admin:test',
    '{}'::jsonb
  )$$,
  '22023', 'IDENTITY_SNAPSHOT_INVALID', 'invalid customer identity is rejected'
);

select throws_ok(
  $$select * from public.approve_quotation_commercial_envelope_v1(
    (select id from public.quote_request_quotation_approval_drafts),
    'd3e25000-0000-4000-8000-000000000008',
    jsonb_set((select payload from d3e2_fixture), '{pricing_snapshot,integrity_mac}', to_jsonb(repeat('0',64))),
    'd3e24000-0000-4000-8000-000000000008', repeat('f', 64), 'admin:test',
    '{}'::jsonb
  )$$,
  'P0001', 'PRICING_INTEGRITY_INVALID', 'invalid pricing proof is rejected during approval'
);

select is((select count(*)::integer from public.quote_request_quotation_approval_operations where operation_type = 'APPROVE'), 2, 'two successful approval operations are recorded');
select throws_ok(
  $$update public.quote_request_quotation_approval_operations set request_fingerprint = repeat('0',64)$$,
  '55000', 'QUOTATION_APPROVAL_OPERATION_IMMUTABLE', 'operation ledger cannot be updated'
);

select has_table('public', 'quotation_number_counters', 'later D3E3 numbering authority coexists with D3E2');
select has_table('public', 'quote_request_quotation_issuances', 'later D3E3 issuance registry coexists with D3E2');

select * from finish();
rollback;
