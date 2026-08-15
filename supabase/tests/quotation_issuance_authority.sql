begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(59);

select has_table('public', 'quotation_number_counters', 'dedicated quotation counter exists');
select has_table('public', 'quote_request_quotation_issuances', 'issuance registry exists');
select has_table('public', 'quote_request_quotation_issuance_operations', 'issuance operation ledger exists');
select has_function('public', 'prepare_quotation_issuance_v1', array['uuid','smallint','smallint','text','uuid','text','text'], 'versioned prepare RPC exists');
select has_function('public', 'commit_quotation_issuance_v1', array['uuid','uuid','text','text','text','text','smallint','text','bigint','text','bigint','text','text'], 'versioned commit RPC exists');
select has_function('public', 'void_quotation_issuance_v1', array['uuid','text','text','uuid','text'], 'versioned void RPC exists');
select ok(not has_function_privilege('anon', 'public.prepare_quotation_issuance_v1(uuid,smallint,smallint,text,uuid,text,text)', 'execute'), 'anon cannot prepare');
select ok(not has_function_privilege('authenticated', 'public.commit_quotation_issuance_v1(uuid,uuid,text,text,text,text,smallint,text,bigint,text,bigint,text,text)', 'execute'), 'authenticated cannot commit');
select ok(not has_function_privilege('anon', 'public.void_quotation_issuance_v1(uuid,text,text,uuid,text)', 'execute'), 'anon cannot void');
select ok(has_function_privilege('service_role', 'public.prepare_quotation_issuance_v1(uuid,smallint,smallint,text,uuid,text,text)', 'execute'), 'service role can prepare');
select ok(has_function_privilege('service_role', 'public.commit_quotation_issuance_v1(uuid,uuid,text,text,text,text,smallint,text,bigint,text,bigint,text,text)', 'execute'), 'service role can commit');
select ok(has_function_privilege('service_role', 'public.void_quotation_issuance_v1(uuid,text,text,uuid,text)', 'execute'), 'service role can void');
select ok(not has_table_privilege('service_role', 'public.quotation_number_counters', 'update'), 'service role cannot mutate counter directly');
select ok(not has_table_privilege('service_role', 'public.quote_request_quotation_issuances', 'insert'), 'service role cannot insert issuance directly');
select ok(not has_table_privilege('service_role', 'public.quote_request_quotation_issuances', 'update'), 'service role cannot update issuance directly');
select ok(not has_table_privilege('service_role', 'public.quote_request_quotation_issuances', 'delete'), 'service role cannot delete issuance directly');

create temporary table d3e3_fixture as
select jsonb_build_object(
  'contract_version', 1,
  'source_quote_request_id', 'd3e30000-0000-4000-8000-000000000001',
  'source_intake_id', 'd3e31000-0000-4000-8000-000000000001',
  'pricing_snapshot', jsonb_build_object(
    'snapshot_id', 'd3e32000-0000-4000-8000-000000000001',
    'snapshot_contract_version', 2,
    'integrity_algorithm_version', 'hmac-sha256-v1',
    'integrity_key_id', 'v1', 'integrity_mac', repeat('a', 64)
  ),
  'currency', 'EUR',
  'line_items', jsonb_build_array(jsonb_build_object(
    'line_id', 'website', 'sequence', 1, 'product_or_service_code', 'WEBSITE',
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
    'source_quote_request_id', 'd3e30000-0000-4000-8000-000000000001',
    'source_intake_id', 'd3e31000-0000-4000-8000-000000000001',
    'customer_id', null, 'legal_name', 'D3E3 Test Customer', 'contact_name', null,
    'email', 'd3e3@example.test', 'address_line_1', 'Teststraat 1',
    'address_line_2', null, 'postal_code', '9000', 'city', 'Gent',
    'country_code', 'BE', 'enterprise_number', null, 'vat_number', null,
    'source_fields', jsonb_build_object('legal_name', 'quote_request.company'),
    'snapshot_sha256', repeat('b', 64)
  ),
  'project_scope', jsonb_build_object(
    'project_id', null, 'project_title', 'D3E3 testwebsite',
    'project_type', 'website', 'scope_summary', 'Fictieve scope',
    'requested_languages', jsonb_build_array('nl'), 'included_page_count', 5,
    'features', jsonb_build_array('contact_form'), 'copywriting', null,
    'seo', null, 'hosting', null, 'maintenance', null,
    'exclusions', '[]'::jsonb, 'assumptions', '[]'::jsonb,
    'indicative_timing', null,
    'source_intake_id', 'd3e31000-0000-4000-8000-000000000001',
    'source_pricing_snapshot_id', 'd3e32000-0000-4000-8000-000000000001',
    'snapshot_sha256', repeat('c', 64)
  ),
  'vat_approval', jsonb_build_object(
    'vat_treatment', 'STANDARD', 'vat_rate', 21,
    'vat_decision_source', 'accountant', 'vat_approved_by', 'accountant:test',
    'vat_approved_at', '2026-08-15T12:00:00Z'
  ),
  'payment_schedule', jsonb_build_object(
    'schedule_id', 'schedule-1',
    'milestones', jsonb_build_array(jsonb_build_object(
      'sequence', 1, 'label', 'Volledige betaling', 'percentage', 100,
      'amount_minor', null, 'trigger', 'invoice', 'due_terms_days', 30,
      'recurring_cycle', null
    )), 'approved_by', 'commercial:test', 'approved_at', '2026-08-15T12:00:00Z'
  ),
  'validity', jsonb_build_object(
    'valid_from', '2026-08-15', 'valid_until', '2026-09-14',
    'validity_days', 30, 'approved_by', 'commercial:test',
    'approved_at', '2026-08-15T12:00:00Z'
  ),
  'legal_references', jsonb_build_object(
    'terms_reference', 'terms-v1', 'terms_version', '1.0.0',
    'terms_sha256', repeat('d', 64), 'terms_status', 'APPROVED',
    'agreement_template_reference', null, 'agreement_template_version', null,
    'agreement_template_sha256', null
  )
) as payload,
'{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}'::jsonb as normalized_scope,
'{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":180000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000}]}'::jsonb as calculation,
'{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}'::jsonb as package_advice,
'{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}'::jsonb as budget_evaluation;

insert into public.quote_requests (id, name, email, website_type, budget, timing, description, privacy_consent, status)
values ('d3e30000-0000-4000-8000-000000000001', 'D3E3 test', 'd3e3@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'D3E3 fixture', true, 'approved');

insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at, status,
  started_at, submitted_at, confirmation, admin_access_token_hash,
  admin_access_token_expires_at
) values (
  'd3e31000-0000-4000-8000-000000000001',
  'd3e30000-0000-4000-8000-000000000001', repeat('1',64),
  clock_timestamp()+interval '1 day', 'submitted', clock_timestamp(),
  clock_timestamp(), true, repeat('f',64), clock_timestamp()+interval '1 day'
);

insert into public.quote_request_pricing_snapshots (
  id, intake_id, snapshot_contract_version, config_version, config_hash,
  normalized_evidence, calculation, package_advice, budget_evaluation
)
select 'd3e32000-0000-4000-8000-000000000001',
  'd3e31000-0000-4000-8000-000000000001', 2, '1.0.0', repeat('1',64),
  normalized_scope, calculation, package_advice, budget_evaluation from d3e3_fixture;

insert into public.quote_request_pricing_snapshot_integrity (snapshot_id, algorithm_version, key_id, mac)
values ('d3e32000-0000-4000-8000-000000000001', 'hmac-sha256-v1', 'v1', repeat('a',64));

insert into public.quote_request_quotation_approval_drafts (
  id, quote_request_id, intake_id, pricing_snapshot_id, contract_version,
  approval_payload, payload_fingerprint, idempotency_key, created_by
)
select 'd3e33000-0000-4000-8000-000000000001',
  'd3e30000-0000-4000-8000-000000000001',
  'd3e31000-0000-4000-8000-000000000001',
  'd3e32000-0000-4000-8000-000000000001', 1, payload,
  public.quotation_approval_payload_sha256_v1(payload),
  'd3e34000-0000-4000-8000-000000000001', 'admin:test' from d3e3_fixture;

insert into public.quote_request_quotation_approvals (
  id, draft_id, quote_request_id, intake_id, pricing_snapshot_id,
  contract_version, approval_version, approved_payload, payload_sha256,
  approved_by, approved_at
)
select 'd3e35000-0000-4000-8000-000000000001',
  'd3e33000-0000-4000-8000-000000000001',
  'd3e30000-0000-4000-8000-000000000001',
  'd3e31000-0000-4000-8000-000000000001',
  'd3e32000-0000-4000-8000-000000000001', 1, 1, payload,
  public.quotation_approval_payload_sha256_v1(payload), 'admin:test', clock_timestamp()
from d3e3_fixture;

insert into public.quote_request_quotation_approval_integrity (approval_id, algorithm_version, key_id, mac)
values ('d3e35000-0000-4000-8000-000000000001', 'hmac-sha256-v1', 'v1', repeat('e',64));

select is((select count(*)::integer from public.quotation_number_counters), 0, 'preview/no-op consumes no number');
select throws_ok(
  $$select * from public.prepare_quotation_issuance_v1('d3e35000-0000-4000-8000-000000000001', 2026::smallint, 1::smallint, 'bad', 'd3e36000-0000-4000-8000-000000000001', repeat('f',64), 'admin:test')$$,
  '42501', 'UNAUTHORIZED', 'invalid prepare input fails before allocation'
);
select is((select count(*)::integer from public.quotation_number_counters), 0, 'failed validation consumes no number');
select is(
  (select quotation_number from public.prepare_quotation_issuance_v1(
    'd3e35000-0000-4000-8000-000000000001', 2026::smallint, 1::smallint, repeat('1',64),
    'd3e36000-0000-4000-8000-000000000001', repeat('f',64), 'admin:test'
  )), 'LWS-OFF-2026-0001', 'first annual number is 0001'
);
select is((select status from public.quote_request_quotation_issuances), 'PREPARED', 'prepare creates PREPARED registry row');
select is((select next_sequence from public.quotation_number_counters where year=2026), 2, 'prepare atomically advances counter');
select is(
  (select was_created from public.prepare_quotation_issuance_v1(
    'd3e35000-0000-4000-8000-000000000001', 2026::smallint, 1::smallint, repeat('1',64),
    'd3e36000-0000-4000-8000-000000000001', repeat('f',64), 'admin:test'
  )), false, 'same prepare key and fingerprint replays exact identity'
);
select is((select count(*)::integer from public.quote_request_quotation_issuances), 1, 'prepare retry allocates no duplicate');
select throws_ok(
  $$select * from public.prepare_quotation_issuance_v1('d3e35000-0000-4000-8000-000000000001', 2026::smallint, 1::smallint, repeat('1',64), 'd3e36000-0000-4000-8000-000000000001', repeat('0',64), 'admin:test')$$,
  '42501', 'UNAUTHORIZED', 'prepare replay revalidates admin capability'
);
select throws_ok(
  $$select * from public.prepare_quotation_issuance_v1('d3e35000-0000-4000-8000-000000000001', 2026::smallint, 1::smallint, repeat('2',64), 'd3e36000-0000-4000-8000-000000000001', repeat('f',64), 'admin:test')$$,
  'P0001', 'IDEMPOTENCY_CONFLICT', 'same prepare key with different fingerprint conflicts'
);
select throws_ok(
  $$select * from public.prepare_quotation_issuance_v1('d3e35000-0000-4000-8000-000000000001', 2026::smallint, 1::smallint, repeat('2',64), 'd3e36000-0000-4000-8000-000000000002', repeat('f',64), 'admin:test')$$,
  'P0001', 'APPROVAL_CONFLICT', 'same approval cannot receive incompatible second issuance'
);
select is((select next_sequence from public.quotation_number_counters where year=2026), 2, 'approval conflict consumes no second number');
select throws_ok(
  $$update public.quote_request_quotation_issuances set quotation_number='LWS-OFF-2026-9999'$$,
  '55000', 'QUOTATION_ISSUANCE_IMMUTABLE', 'prepared issuance cannot be directly changed'
);
select throws_ok(
  $$delete from public.quote_request_quotation_issuances$$,
  '55000', 'QUOTATION_ISSUANCE_IMMUTABLE', 'prepared issuance cannot be deleted'
);
select throws_ok(
  $$select * from public.commit_quotation_issuance_v1((select id from public.quote_request_quotation_issuances), 'd3e37000-0000-4000-8000-000000000001', repeat('2',64), 'LWS_QUOTATION_NL_BE', '1.0.0-technical', '3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE', 1::smallint, repeat('4',64), 100, null, null, 'admin:test', repeat('f',64))$$,
  'P0001', 'GENERATION_PAYLOAD_HASH_MISMATCH', 'generation payload mismatch is rejected'
);
select throws_ok(
  $$select * from public.commit_quotation_issuance_v1((select id from public.quote_request_quotation_issuances), 'd3e37000-0000-4000-8000-000000000001', repeat('1',64), '', '1.0.0', repeat('3',64), 1::smallint, repeat('4',64), 100, null, null, 'admin:test', repeat('f',64))$$,
  '22023', 'TEMPLATE_IDENTITY_INVALID', 'template identity is required'
);
select throws_ok(
  $$select * from public.commit_quotation_issuance_v1((select id from public.quote_request_quotation_issuances), 'd3e37000-0000-4000-8000-000000000001', repeat('1',64), 'LWS_QUOTATION_NL_BE', '1.0.0-technical', '3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE', 1::smallint, 'BAD', 100, null, null, 'admin:test', repeat('f',64))$$,
  '22023', 'ARTIFACT_HASH_INVALID', 'malformed DOCX hash is rejected'
);
select throws_ok(
  $$select * from public.commit_quotation_issuance_v1((select id from public.quote_request_quotation_issuances), 'd3e37000-0000-4000-8000-000000000001', repeat('1',64), 'LWS_QUOTATION_NL_BE', '1.0.0-technical', '3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE', 1::smallint, repeat('4',64), 0, null, null, 'admin:test', repeat('f',64))$$,
  '22023', 'ARTIFACT_BYTES_INVALID', 'zero DOCX bytes are rejected'
);
select is(
  (select status from public.commit_quotation_issuance_v1(
    (select id from public.quote_request_quotation_issuances),
    'd3e37000-0000-4000-8000-000000000001', repeat('1',64),
    'LWS_QUOTATION_NL_BE', '1.0.0-technical', '3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE', 1::smallint, repeat('4',64), 100,
    null, null, 'admin:test', repeat('f',64)
  )), 'ISSUED', 'valid PREPARED transitions to ISSUED'
);
select ok((select issued_at is not null and issued_by='admin:test' from public.quote_request_quotation_issuances), 'issued evidence is stored');
select is(
  (select was_committed from public.commit_quotation_issuance_v1(
    (select id from public.quote_request_quotation_issuances),
    'd3e37000-0000-4000-8000-000000000001', repeat('1',64),
    'LWS_QUOTATION_NL_BE', '1.0.0-technical', '3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE', 1::smallint, repeat('4',64), 100,
    null, null, 'admin:test', repeat('f',64)
  )), false, 'same commit retry returns ISSUED identity'
);
select throws_ok(
  $$select * from public.commit_quotation_issuance_v1((select id from public.quote_request_quotation_issuances), 'd3e37000-0000-4000-8000-000000000001', repeat('1',64), 'LWS_QUOTATION_NL_BE', '1.0.0-technical', '3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE', 1::smallint, repeat('4',64), 100, null, null, 'admin:test', repeat('0',64))$$,
  '42501', 'UNAUTHORIZED', 'commit replay revalidates admin capability'
);
select throws_ok(
  $$select * from public.commit_quotation_issuance_v1((select id from public.quote_request_quotation_issuances), 'd3e37000-0000-4000-8000-000000000002', repeat('1',64), 'LWS_QUOTATION_NL_BE', '1.0.0-technical', '3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE', 1::smallint, repeat('5',64), 100, null, null, 'admin:test', repeat('f',64))$$,
  'P0001', 'ISSUANCE_ALREADY_COMPLETED', 'incompatible second commit is rejected'
);
select throws_ok(
  $$update public.quote_request_quotation_issuances set issued_by='other'$$,
  '55000', 'QUOTATION_ISSUANCE_IMMUTABLE', 'issued row cannot be changed directly'
);
select throws_ok(
  $$delete from public.quote_request_quotation_issuances$$,
  '55000', 'QUOTATION_ISSUANCE_IMMUTABLE', 'issued row cannot be deleted'
);

insert into public.quote_request_quotation_approvals (
  id, draft_id, quote_request_id, intake_id, pricing_snapshot_id,
  contract_version, approval_version, approved_payload, payload_sha256,
  approved_by, approved_at
)
select 'd3e35000-0000-4000-8000-000000000002',
  'd3e33000-0000-4000-8000-000000000001',
  'd3e30000-0000-4000-8000-000000000001',
  'd3e31000-0000-4000-8000-000000000001',
  'd3e32000-0000-4000-8000-000000000001', 1, 2, payload,
  public.quotation_approval_payload_sha256_v1(payload), 'admin:test', clock_timestamp()
from d3e3_fixture;
insert into public.quote_request_quotation_approval_integrity (approval_id, algorithm_version, key_id, mac)
values ('d3e35000-0000-4000-8000-000000000002', 'hmac-sha256-v1', 'v1', repeat('e',64));

select is(
  (select quotation_number from public.prepare_quotation_issuance_v1(
    'd3e35000-0000-4000-8000-000000000002', 2026::smallint, 1::smallint, repeat('6',64),
    'd3e36000-0000-4000-8000-000000000003', repeat('f',64), 'admin:test'
  )), 'LWS-OFF-2026-0002', 'second annual number is 0002'
);
select is(
  (select status from public.void_quotation_issuance_v1(
    (select id from public.quote_request_quotation_issuances where approval_id='d3e35000-0000-4000-8000-000000000002'),
    'Generation failed', 'admin:test', 'd3e38000-0000-4000-8000-000000000001', repeat('f',64)
  )), 'VOID', 'PREPARED transitions to VOID'
);
select ok((select voided_at is not null and void_reason='Generation failed' from public.quote_request_quotation_issuances where approval_id='d3e35000-0000-4000-8000-000000000002'), 'void evidence is stored');
select is(
  (select was_voided from public.void_quotation_issuance_v1(
    (select id from public.quote_request_quotation_issuances where approval_id='d3e35000-0000-4000-8000-000000000002'),
    'Generation failed', 'admin:test', 'd3e38000-0000-4000-8000-000000000001', repeat('f',64)
  )), false, 'same void retry is idempotent'
);
select throws_ok(
  $$select * from public.void_quotation_issuance_v1((select id from public.quote_request_quotation_issuances where status='VOID'), 'Generation failed', 'admin:test', 'd3e38000-0000-4000-8000-000000000001', repeat('0',64))$$,
  '42501', 'UNAUTHORIZED', 'void replay revalidates admin capability'
);
select throws_ok(
  $$select * from public.void_quotation_issuance_v1((select id from public.quote_request_quotation_issuances where status='VOID'), 'Different', 'admin:test', 'd3e38000-0000-4000-8000-000000000001', repeat('f',64))$$,
  'P0001', 'IDEMPOTENCY_CONFLICT', 'conflicting void retry is rejected'
);
select throws_ok(
  $$select * from public.commit_quotation_issuance_v1((select id from public.quote_request_quotation_issuances where status='VOID'), 'd3e37000-0000-4000-8000-000000000003', repeat('6',64), 'LWS_QUOTATION_NL_BE', '1.0.0-technical', '3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE', 1::smallint, repeat('4',64), 100, null, null, 'admin:test', repeat('f',64))$$,
  'P0001', 'ISSUANCE_VOID', 'VOID cannot become ISSUED'
);
select throws_ok(
  $$update public.quote_request_quotation_issuances set status='PREPARED' where status='VOID'$$,
  '55000', 'QUOTATION_ISSUANCE_IMMUTABLE', 'VOID cannot return to PREPARED'
);
select is((select next_sequence from public.quotation_number_counters where year=2026), 3, 'VOID number remains consumed');
select throws_ok(
  $$delete from public.quote_request_quotation_issuances where status='VOID'$$,
  '55000', 'QUOTATION_ISSUANCE_IMMUTABLE', 'VOID row cannot be deleted'
);

insert into public.quote_request_quotation_approvals (
  id, draft_id, quote_request_id, intake_id, pricing_snapshot_id,
  contract_version, approval_version, approved_payload, payload_sha256,
  approved_by, approved_at
)
select 'd3e35000-0000-4000-8000-000000000003',
  'd3e33000-0000-4000-8000-000000000001',
  'd3e30000-0000-4000-8000-000000000001',
  'd3e31000-0000-4000-8000-000000000001',
  'd3e32000-0000-4000-8000-000000000001', 1, 3, payload,
  public.quotation_approval_payload_sha256_v1(payload), 'admin:test', clock_timestamp()
from d3e3_fixture;
insert into public.quote_request_quotation_approval_integrity (approval_id, algorithm_version, key_id, mac)
values ('d3e35000-0000-4000-8000-000000000003', 'hmac-sha256-v1', 'v1', repeat('e',64));
select is(
  (select quotation_number from public.prepare_quotation_issuance_v1(
    'd3e35000-0000-4000-8000-000000000003', 2027::smallint, 1::smallint, repeat('7',64),
    'd3e36000-0000-4000-8000-000000000004', repeat('f',64), 'admin:test'
  )), 'LWS-OFF-2027-0001', 'separate year starts at 0001'
);
select is((select next_sequence from public.quotation_number_counters where year=2027), 2, 'separate annual counter advances independently');
select is((select count(*)::integer from public.quote_request_quotation_issuances where quotation_number !~ '^LWS-OFF-[0-9]{4}-[0-9]{4}$'), 0, 'all quotation numbers match frozen format');
select is((select count(*)::integer from public.quote_request_quotation_issuances), 3, 'three approvals produce exactly three issuance identities');
select is((select count(distinct quotation_number)::integer from public.quote_request_quotation_issuances), 3, 'no duplicate quotation number exists');
select is((select count(*)::integer from public.quote_request_quotation_issuance_operations), 5, 'only successful prepare commit and void operations are recorded');
select throws_ok(
  $$update public.quote_request_quotation_issuance_operations set request_fingerprint=repeat('0',64)$$,
  '55000', 'QUOTATION_ISSUANCE_AUTHORITY_IMMUTABLE', 'operation ledger cannot be changed'
);
select hasnt_table('public', 'invoice_number_counters', 'invoice numbering remains untouched');

select * from finish();
rollback;
