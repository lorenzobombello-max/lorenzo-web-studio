begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(49);

select has_function(
  'public', 'is_valid_quotation_approval_payload_v1', array['jsonb','boolean'],
  'versioned strict quotation approval validator exists'
);
select has_function(
  'public', 'canonicalize_quotation_approval_payload_v1', array['jsonb'],
  'quotation approval canonicalizer exists'
);
select has_function(
  'public', 'quotation_approval_payload_sha256_v1', array['jsonb'],
  'quotation approval hash helper exists'
);
select has_table('public', 'quote_request_quotation_approval_drafts', 'approval drafts table exists');
select has_table('public', 'quote_request_quotation_approvals', 'immutable approvals table exists');
select has_table('public', 'quote_request_quotation_approval_integrity', 'approval integrity table exists');

select ok(not has_table_privilege('anon', 'public.quote_request_quotation_approval_drafts', 'insert'), 'anon cannot insert drafts');
select ok(not has_table_privilege('authenticated', 'public.quote_request_quotation_approval_drafts', 'update'), 'authenticated cannot update drafts');
select ok(not has_table_privilege('service_role', 'public.quote_request_quotation_approvals', 'insert'), 'service role cannot bypass future approval RPC');
select ok(not has_table_privilege('service_role', 'public.quote_request_quotation_approval_integrity', 'insert'), 'service role cannot attach proof directly');
select ok(not has_function_privilege('anon', 'public.is_valid_quotation_approval_payload_v1(jsonb,boolean)', 'execute'), 'anon cannot execute approval validator directly');
select ok(not has_function_privilege('authenticated', 'public.canonicalize_quotation_approval_payload_v1(jsonb)', 'execute'), 'authenticated cannot canonicalize approval payloads directly');
select ok(has_function_privilege('service_role', 'public.is_valid_quotation_approval_payload_v1(jsonb,boolean)', 'execute'), 'service role can use strict approval validator');

create temporary table quotation_fixture as
select jsonb_build_object(
  'contract_version', 1,
  'source_quote_request_id', 'd3e10000-0000-4000-8000-000000000001',
  'source_intake_id', 'd3e11000-0000-4000-8000-000000000001',
  'pricing_snapshot', jsonb_build_object(
    'snapshot_id', 'd3e12000-0000-4000-8000-000000000001',
    'snapshot_contract_version', 3,
    'integrity_algorithm_version', 'hmac-sha256-v1',
    'integrity_key_id', 'v1',
    'integrity_mac', repeat('a', 64)
  ),
  'currency', 'EUR',
  'line_items', jsonb_build_array(
    jsonb_build_object(
      'line_id', 'website', 'sequence', 1, 'product_or_service_code', 'WEBSITE',
      'description', 'Websiteontwikkeling', 'quantity', 1, 'unit', 'project',
      'unit_price_minor', 100000, 'discount_minor', 0,
      'vat_treatment', 'STANDARD', 'vat_rate', 21,
      'line_net_amount_minor', 100000, 'cost_type', 'ONE_TIME'
    )
  ),
  'totals', jsonb_build_object(
    'one_time_subtotal_minor', 100000, 'recurring_subtotal_minor', 0,
    'discount_total_minor', 0, 'vat_base_minor', 100000,
    'vat_amount_minor', 21000, 'total_gross_minor', 121000
  ),
  'discount', jsonb_build_object(
    'discount_type', null, 'discount_value_minor', 0, 'discount_reason', null,
    'approved_by', null, 'approved_at', null
  ),
  'customer_identity', jsonb_build_object(
    'source_quote_request_id', 'd3e10000-0000-4000-8000-000000000001',
    'source_intake_id', 'd3e11000-0000-4000-8000-000000000001',
    'customer_id', null, 'legal_name', 'Test Customer', 'contact_name', null,
    'email', 'test@example.test', 'address_line_1', 'Teststraat 1',
    'address_line_2', null, 'postal_code', '9000', 'city', 'Gent',
    'country_code', 'BE', 'enterprise_number', null, 'vat_number', null,
    'source_fields', jsonb_build_object('legal_name', 'quote_request.company'),
    'snapshot_sha256', repeat('b', 64)
  ),
  'project_scope', jsonb_build_object(
    'project_id', null, 'project_title', 'Test website', 'project_type', 'website',
    'scope_summary', 'Fictieve scope', 'requested_languages', jsonb_build_array('nl'),
    'included_page_count', 5, 'features', jsonb_build_array('contact_form'),
    'copywriting', null, 'seo', null, 'hosting', null, 'maintenance', null,
    'exclusions', '[]'::jsonb, 'assumptions', '[]'::jsonb,
    'indicative_timing', null,
    'source_intake_id', 'd3e11000-0000-4000-8000-000000000001',
    'source_pricing_snapshot_id', 'd3e12000-0000-4000-8000-000000000001',
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
    )),
    'approved_by', 'commercial:test', 'approved_at', '2026-08-15T12:00:00Z'
  ),
  'validity', jsonb_build_object(
    'valid_from', '2026-08-15', 'valid_until', '2026-09-14', 'validity_days', 30,
    'approved_by', 'commercial:test', 'approved_at', '2026-08-15T12:00:00Z'
  ),
  'legal_references', jsonb_build_object(
    'terms_reference', 'terms-v1', 'terms_version', '1.0.0',
    'terms_sha256', repeat('d', 64), 'terms_status', 'APPROVED',
    'agreement_template_reference', null, 'agreement_template_version', null,
    'agreement_template_sha256', null
  )
) as payload;

select ok(public.is_valid_quotation_approval_payload_v1(payload, true), 'minimal valid approved payload passes') from quotation_fixture;
select ok(public.is_valid_quotation_approval_payload_v1(payload, false), 'minimal valid draft payload passes') from quotation_fixture;
select is(length(public.quotation_approval_payload_sha256_v1(payload)), 64, 'canonical payload hash is 64 hex characters') from quotation_fixture;
select is(
  public.quotation_approval_payload_sha256_v1(payload),
  public.quotation_approval_payload_sha256_v1(payload::text::jsonb),
  'canonical hash is stable across JSONB round trip'
) from quotation_fixture;

select ok(public.is_valid_quotation_approval_payload_v1(
  jsonb_set(payload, '{project_scope,project_id}', '"PRJ-TEST"'), true
), 'non-null project ID is supported') from quotation_fixture;
select ok(public.is_valid_quotation_approval_payload_v1(
  jsonb_set(payload, '{customer_identity,customer_id}', '"CUS-TEST"'), true
), 'non-null customer ID is supported') from quotation_fixture;
select ok(public.is_valid_quotation_approval_payload_v1(
  jsonb_set(
    jsonb_set(payload, '{line_items,0,cost_type}', '"RECURRING"'),
    '{totals}',
    '{"one_time_subtotal_minor":0,"recurring_subtotal_minor":100000,"discount_total_minor":0,"vat_base_minor":0,"vat_amount_minor":0,"total_gross_minor":0}'
  ), true
), 'recurring-only quotation lines remain separate from one-time totals') from quotation_fixture;
select ok(public.is_valid_quotation_approval_payload_v1(
  jsonb_set(
    jsonb_set(
      jsonb_set(payload, '{line_items}', (payload->'line_items') || jsonb_build_array(jsonb_build_object(
        'line_id','hosting','sequence',2,'product_or_service_code','HOSTING',
        'description','Hosting','quantity',1,'unit','year','unit_price_minor',12000,
        'discount_minor',0,'vat_treatment','STANDARD','vat_rate',21,
        'line_net_amount_minor',12000,'cost_type','RECURRING'
      ))),
      '{totals,recurring_subtotal_minor}', '12000'
    ),
    '{payment_schedule}', payload->'payment_schedule'
  ), true
), 'one-time and recurring lines validate together') from quotation_fixture;

select ok(not public.is_valid_quotation_approval_payload_v1(
  jsonb_set(payload, '{line_items}', (payload->'line_items') || (payload->'line_items')), true
), 'duplicate line IDs and sequences are rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{line_items,0,quantity}', '0'), true), 'zero quantity is rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{line_items,0,quantity}', '-1'), true), 'negative quantity is rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{line_items,0,unit_price_minor}', '-1'), true), 'negative unit price is rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{line_items,0,unit_price_minor}', '10.5'), true), 'fractional minor units are rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{line_items,0,discount_minor}', '100001'), true), 'discount above line amount is rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{line_items,0,cost_type}', '"OTHER"'), true), 'invalid cost type is rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{vat_approval}', '{}'), true), 'malformed VAT approval is rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(
  jsonb_set(payload, '{vat_approval}', '{"vat_treatment":null,"vat_rate":null,"vat_decision_source":null,"vat_approved_by":null,"vat_approved_at":null}'), true
), 'unapproved VAT is rejected for approved envelope') from quotation_fixture;
select ok(public.is_valid_quotation_approval_payload_v1(
  jsonb_set(payload, '{vat_approval}', '{"vat_treatment":null,"vat_rate":null,"vat_decision_source":null,"vat_approved_by":null,"vat_approved_at":null}'), false
), 'unapproved VAT is allowed in editable draft') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{payment_schedule,milestones}', '[]'), true), 'empty payment schedule is rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{payment_schedule,milestones,0,percentage}', '90'), true), 'payment percentages not totaling 100 are rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{validity,validity_days}', '29'), true), 'validity date mismatch is rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{customer_identity,legal_name}', 'null'), true), 'missing required customer identity is rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{customer_identity,country_code}', '"BEL"'), true), 'malformed country code is rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{customer_identity,snapshot_sha256}', '"bad"'), true), 'malformed snapshot hash is rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{legal_references,terms_status}', '"UNAPPROVED"'), true), 'unapproved legal reference is rejected for approved envelope') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{contract_version}', '2'), true), 'unknown contract version is rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{pricing_snapshot,snapshot_id}', '"bad"'), true), 'malformed pricing snapshot reference is rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{extra}', 'true'), true), 'unknown top-level fields are rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{customer_identity,source_intake_id}', '"d3e11000-0000-4000-8000-000000000002"'), true), 'identity source mismatch is rejected') from quotation_fixture;
select ok(not public.is_valid_quotation_approval_payload_v1(jsonb_set(payload, '{totals,total_gross_minor}', '120999'), true), 'gross total mismatch is rejected') from quotation_fixture;

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status
) values (
  'd3e10000-0000-4000-8000-000000000001', 'D3E1 test', 'd3e1@example.test',
  'business', 'EUR 3.200 t/m EUR 6.000', 'flexible',
  'D3E1 quotation approval foundation fixture', true, 'approved'
);

insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at,
  status, started_at, submitted_at, confirmation
) values (
  'd3e11000-0000-4000-8000-000000000001',
  'd3e10000-0000-4000-8000-000000000001', repeat('1', 64),
  clock_timestamp() + interval '1 day', 'submitted', clock_timestamp(),
  clock_timestamp(), true
);

insert into public.quote_request_pricing_snapshots (
  id, intake_id, snapshot_contract_version, config_version, config_hash,
  normalized_evidence, calculation, package_advice, budget_evaluation,
  package_definition
) values (
  'd3e12000-0000-4000-8000-000000000001',
  'd3e11000-0000-4000-8000-000000000001', 3, '2.0.0', repeat('a', 64),
  '{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}',
  '{"basis":"package_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":180000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[]}',
  '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}',
  '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}',
  '{"id":"starter_v1","version":1,"label":"Starter","priceMode":"from","floorMinor":180000,"standardPageLimit":5,"includedCorrectionRounds":1,"entitlementSetId":"normal_web_v1","entitlements":["responsive_design"]}'
);

insert into public.quote_request_quotation_approval_drafts (
  id, quote_request_id, intake_id, pricing_snapshot_id, approval_payload,
  payload_fingerprint, idempotency_key, created_by
)
select
  'd3e13000-0000-4000-8000-000000000001',
  'd3e10000-0000-4000-8000-000000000001',
  'd3e11000-0000-4000-8000-000000000001',
  'd3e12000-0000-4000-8000-000000000001', payload,
  public.quotation_approval_payload_sha256_v1(payload),
  'd3e14000-0000-4000-8000-000000000001', 'admin:test'
from quotation_fixture;

insert into public.quote_request_quotation_approvals (
  id, draft_id, quote_request_id, intake_id, pricing_snapshot_id,
  contract_version, approval_version, approved_payload, payload_sha256,
  approved_by, approved_at
)
select
  'd3e15000-0000-4000-8000-000000000001',
  'd3e13000-0000-4000-8000-000000000001',
  'd3e10000-0000-4000-8000-000000000001',
  'd3e11000-0000-4000-8000-000000000001',
  'd3e12000-0000-4000-8000-000000000001', 1, 1, payload,
  public.quotation_approval_payload_sha256_v1(payload),
  'admin:test', '2026-08-15T12:00:00Z'
from quotation_fixture;

select throws_matching(
  $$insert into public.quote_request_quotation_approvals (
      draft_id, quote_request_id, intake_id, pricing_snapshot_id,
      contract_version, approval_version, approved_payload, payload_sha256,
      approved_by, approved_at
    ) select
      'd3e13000-0000-4000-8000-000000000001',
      'd3e10000-0000-4000-8000-000000000001',
      'd3e11000-0000-4000-8000-000000000001',
      'd3e12000-0000-4000-8000-000000000001', 1, 1, payload,
      public.quotation_approval_payload_sha256_v1(payload),
      'admin:test', '2026-08-15T12:00:00Z'
    from quotation_fixture$$,
  'quote_request_quotation_approvals_version_unique',
  'an approval version cannot be reused for one intake'
);

select lives_ok(
  $$insert into public.quote_request_quotation_approvals (
      draft_id, quote_request_id, intake_id, pricing_snapshot_id,
      contract_version, approval_version, approved_payload, payload_sha256,
      approved_by, approved_at
    ) select
      'd3e13000-0000-4000-8000-000000000001',
      'd3e10000-0000-4000-8000-000000000001',
      'd3e11000-0000-4000-8000-000000000001',
      'd3e12000-0000-4000-8000-000000000001', 1, 2, payload,
      public.quotation_approval_payload_sha256_v1(payload),
      'admin:test', '2026-08-15T12:00:00Z'
    from quotation_fixture$$,
  'a later immutable approval version can be appended'
);

insert into public.quote_request_quotation_approval_integrity (
  approval_id, algorithm_version, key_id, mac
) values (
  'd3e15000-0000-4000-8000-000000000001',
  'hmac-sha256-v1', 'v1', repeat('e', 64)
);

select throws_ok(
  $$update public.quote_request_quotation_approvals set approved_by = 'changed'$$,
  '55000', 'QUOTATION_APPROVAL_IMMUTABLE', 'approved envelope update is rejected'
);
select throws_ok(
  $$delete from public.quote_request_quotation_approvals$$,
  '55000', 'QUOTATION_APPROVAL_IMMUTABLE', 'approved envelope delete is rejected'
);
select throws_ok(
  $$update public.quote_request_quotation_approval_integrity set mac = repeat('f', 64)$$,
  '55000', 'QUOTATION_APPROVAL_IMMUTABLE', 'approval integrity update is rejected'
);
select throws_ok(
  $$delete from public.quote_request_quotation_approval_integrity$$,
  '55000', 'QUOTATION_APPROVAL_IMMUTABLE', 'approval integrity delete is rejected'
);

select * from finish();
rollback;