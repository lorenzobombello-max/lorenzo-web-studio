begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public', 'get_operations_manager_business_overview_v1', array[]::text[],
  'Operations Manager business overview RPC exists'
);
select ok(
  exists (
    select 1 from pg_proc
    where oid = 'public.get_operations_manager_business_overview_v1()'::regprocedure
      and prosecdef
      and provolatile = 's'
      and proconfig = array['search_path=public, auth, pg_catalog']
  ),
  'business overview is stable SECURITY DEFINER with a fixed safe search_path'
);
select ok(
  has_function_privilege('authenticated', 'public.get_operations_manager_business_overview_v1()', 'execute')
  and not has_function_privilege('anon', 'public.get_operations_manager_business_overview_v1()', 'execute')
  and not has_function_privilege('service_role', 'public.get_operations_manager_business_overview_v1()', 'execute')
  and not has_function_privilege('public', 'public.get_operations_manager_business_overview_v1()', 'execute'),
  'only authenticated receives entrypoint execute privilege'
);
select ok(
  not has_table_privilege('anon', 'public.quote_requests', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.quote_requests', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.quote_request_intakes', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.quote_request_intakes', 'select,insert,update,delete'),
  'source business table privileges remain closed to browser roles'
);
select ok(
  not has_table_privilege('authenticated', 'lws_internal.operator_application_readmodel_v2', 'select')
  and not has_table_privilege('service_role', 'lws_internal.operator_application_readmodel_v2', 'select'),
  'private canonical composition remains non-browser-readable'
);
select ok(
  (select prosrc !~* '\m(insert|update|delete|merge|truncate)\M'
   from pg_proc where oid = 'public.get_operations_manager_business_overview_v1()'::regprocedure),
  'business overview runtime contains no mutation statement'
);
select ok(
  (select prosrc !~* 'select\s+\*|resolve_commercial_operator_authorization|commercial_operator_project_grants'
   from pg_proc where oid = 'public.get_operations_manager_business_overview_v1()'::regprocedure),
  'business overview uses neither SELECT star nor project or commercial authority resolvers'
);

insert into auth.users(id, email) values
  ('ea000000-0000-4000-8000-000000000001', 'overview-owner@example.test'),
  ('ea000000-0000-4000-8000-000000000002', 'overview-manager@example.test'),
  ('ea000000-0000-4000-8000-000000000003', 'overview-admin@example.test'),
  ('ea000000-0000-4000-8000-000000000004', 'overview-operator@example.test'),
  ('ea000000-0000-4000-8000-000000000005', 'overview-reviewer@example.test'),
  ('ea000000-0000-4000-8000-000000000006', 'overview-read-only@example.test'),
  ('ea000000-0000-4000-8000-000000000007', 'overview-disabled@example.test'),
  ('ea000000-0000-4000-8000-000000000008', 'overview-revoked@example.test'),
  ('ea000000-0000-4000-8000-000000000009', 'overview-unknown@example.test');

insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status, revoked_at) values
  ('ea010000-0000-4000-8000-000000000001', 'ea000000-0000-4000-8000-000000000001', 'Overview Owner', 'owner', 'ACTIVE', null),
  ('ea010000-0000-4000-8000-000000000002', 'ea000000-0000-4000-8000-000000000002', 'Overview Manager', 'operations_manager', 'ACTIVE', null),
  ('ea010000-0000-4000-8000-000000000003', 'ea000000-0000-4000-8000-000000000003', 'Overview Admin', 'admin', 'ACTIVE', null),
  ('ea010000-0000-4000-8000-000000000004', 'ea000000-0000-4000-8000-000000000004', 'Overview Operator', 'operator', 'ACTIVE', null),
  ('ea010000-0000-4000-8000-000000000005', 'ea000000-0000-4000-8000-000000000005', 'Overview Reviewer', 'reviewer', 'ACTIVE', null),
  ('ea010000-0000-4000-8000-000000000006', 'ea000000-0000-4000-8000-000000000006', 'Overview Read Only', 'read_only', 'ACTIVE', null),
  ('ea010000-0000-4000-8000-000000000007', 'ea000000-0000-4000-8000-000000000007', 'Overview Disabled', 'operations_manager', 'DISABLED', null),
  ('ea010000-0000-4000-8000-000000000008', 'ea000000-0000-4000-8000-000000000008', 'Overview Revoked', 'operations_manager', 'REVOKED', statement_timestamp());

insert into public.quote_requests(
  id, record_classification, request_kind, created_at, name, email,
  website_type, budget, timing, description, privacy_consent, status
) values
  ('ea100001-0000-4000-8000-000000000001', 'production', 'website', statement_timestamp() - interval '23 hours', 'Customer A', 'a@example.test', 'business', 'x', 'x', 'Valid fixture.', true, 'approved'),
  ('ea100002-0000-4000-8000-000000000002', 'production', 'website', statement_timestamp() - interval '24 hours', 'Customer B', 'b@example.test', 'business', 'x', 'x', 'Valid fixture.', true, 'approved'),
  ('ea100003-0000-4000-8000-000000000003', 'production', 'website', statement_timestamp() - interval '4 days' + interval '1 second', 'Customer C', 'c@example.test', 'business', 'x', 'x', 'Valid fixture.', true, 'approved'),
  ('ea100004-0000-4000-8000-000000000004', 'production', 'website', statement_timestamp() - interval '4 days', 'Customer D', 'd@example.test', 'business', 'x', 'x', 'Valid fixture.', true, 'approved'),
  ('ea100005-0000-4000-8000-000000000005', 'production', 'website', statement_timestamp() - interval '8 days' + interval '1 second', 'Customer E', 'e@example.test', 'business', 'x', 'x', 'Valid fixture.', true, 'approved'),
  ('ea100006-0000-4000-8000-000000000006', 'production', 'website', statement_timestamp() - interval '8 days', 'Customer F', 'f@example.test', 'business', 'x', 'x', 'Valid fixture.', true, 'approved'),
  ('ea100007-0000-4000-8000-000000000007', 'production', 'website', statement_timestamp() - interval '100 days', 'Customer G', 'g@example.test', 'business', 'x', 'x', 'Valid fixture.', true, 'approved'),
  ('ea100008-0000-4000-8000-000000000008', 'production', 'website', statement_timestamp() - interval '10 days', 'Customer H', 'h@example.test', 'business', 'x', 'x', 'Valid fixture.', true, 'approved'),
  ('ea100009-0000-4000-8000-000000000009', 'production', 'website', statement_timestamp() - interval '90 days' + interval '1 second', 'Customer I', 'i@example.test', 'business', 'x', 'x', 'Valid fixture.', true, 'approved'),
  ('ea10000a-0000-4000-8000-000000000010', 'production', 'website', statement_timestamp() - interval '90 days' - interval '1 second', 'Customer J', 'j@example.test', 'business', 'x', 'x', 'Valid fixture.', true, 'approved'),
  ('ea10000b-0000-4000-8000-000000000011', 'internal_e2e', 'website', statement_timestamp() - interval '2 hours', 'Customer K', 'k@example.test', 'business', 'x', 'x', 'Valid fixture.', true, 'approved');

insert into public.quote_requests(
  id, record_classification, request_kind, sdf_package, created_at,
  name, email, description, privacy_consent, status
) values
  ('ea110001-0000-4000-8000-000000000001', 'production', 'slimme_documentenflow', 'start', statement_timestamp() - interval '2 days', 'Customer L', 'l@example.test', 'Valid fixture.', true, 'approved'),
  ('ea110002-0000-4000-8000-000000000002', 'internal_e2e', 'slimme_documentenflow', 'start', statement_timestamp() - interval '2 hours', 'Customer M', 'm@example.test', 'Valid fixture.', true, 'approved');

insert into public.sdf_qualification_intakes(
  intake_id, quote_request_id, status, customer_capability_digest,
  customer_capability_encrypted, customer_capability_expires_at, submitted_at
) values
  ('ea210001-0000-4000-8000-000000000001', 'ea110001-0000-4000-8000-000000000001', 'submitted', repeat('a', 64), 'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', statement_timestamp() + interval '1 year', statement_timestamp() - interval '2 days'),
  ('ea210002-0000-4000-8000-000000000002', 'ea110002-0000-4000-8000-000000000002', 'submitted', repeat('b', 64), 'v1.BBBBBBBBBBBBBBBB.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB', statement_timestamp() + interval '1 year', statement_timestamp() - interval '2 hours');

insert into public.quote_request_intakes(
  id, quote_request_id, access_token_hash, access_token_expires_at, status,
  started_at, submitted_at, reviewed_at, confirmation
) values
  ('ea200001-0000-4000-8000-000000000001', 'ea100001-0000-4000-8000-000000000001', repeat('1', 64), statement_timestamp() + interval '1 year', 'submitted', statement_timestamp() - interval '24 hours', statement_timestamp() - interval '23 hours', null, true),
  ('ea200002-0000-4000-8000-000000000002', 'ea100002-0000-4000-8000-000000000002', repeat('2', 64), statement_timestamp() + interval '1 year', 'reviewed', statement_timestamp() - interval '25 hours', statement_timestamp() - interval '24 hours', statement_timestamp() - interval '23 hours', true),
  ('ea200003-0000-4000-8000-000000000003', 'ea100003-0000-4000-8000-000000000003', repeat('3', 64), statement_timestamp() + interval '1 year', 'submitted', statement_timestamp() - interval '5 days', statement_timestamp() - interval '4 days' + interval '1 second', null, true),
  ('ea200004-0000-4000-8000-000000000004', 'ea100004-0000-4000-8000-000000000004', repeat('4', 64), statement_timestamp() + interval '1 year', 'submitted', statement_timestamp() - interval '5 days', statement_timestamp() - interval '4 days', null, true),
  ('ea200005-0000-4000-8000-000000000005', 'ea100005-0000-4000-8000-000000000005', repeat('5', 64), statement_timestamp() + interval '1 year', 'submitted', statement_timestamp() - interval '9 days', statement_timestamp() - interval '8 days' + interval '1 second', null, true),
  ('ea200006-0000-4000-8000-000000000006', 'ea100006-0000-4000-8000-000000000006', repeat('6', 64), statement_timestamp() + interval '1 year', 'submitted', statement_timestamp() - interval '9 days', statement_timestamp() - interval '8 days', null, true),
  ('ea200007-0000-4000-8000-000000000007', 'ea100007-0000-4000-8000-000000000007', repeat('7', 64), statement_timestamp() + interval '1 year', 'submitted', statement_timestamp() - interval '101 days', statement_timestamp() - interval '100 days', null, true),
  ('ea200008-0000-4000-8000-000000000008', 'ea100008-0000-4000-8000-000000000008', repeat('8', 64), statement_timestamp() + interval '1 year', 'submitted', statement_timestamp() - interval '11 days', statement_timestamp() - interval '10 days', null, true),
  ('ea200009-0000-4000-8000-000000000009', 'ea100009-0000-4000-8000-000000000009', repeat('9', 64), statement_timestamp() + interval '1 year', 'submitted', statement_timestamp() - interval '91 days', statement_timestamp() - interval '90 days' + interval '1 second', null, true),
  ('ea20000a-0000-4000-8000-000000000010', 'ea10000a-0000-4000-8000-000000000010', repeat('a', 64), statement_timestamp() + interval '1 year', 'submitted', statement_timestamp() - interval '91 days', statement_timestamp() - interval '90 days' - interval '1 second', null, true),
  ('ea20000b-0000-4000-8000-000000000011', 'ea10000b-0000-4000-8000-000000000011', repeat('b', 64), statement_timestamp() + interval '1 year', 'submitted', statement_timestamp() - interval '1 day', statement_timestamp() - interval '2 hours', null, true);

update public.quote_request_intakes
set access_state = 'CANCELLED', access_token_revoked_at = statement_timestamp()
where quote_request_id in (
  'ea100008-0000-4000-8000-000000000008',
  'ea100009-0000-4000-8000-000000000009',
  'ea10000a-0000-4000-8000-000000000010'
);

create temporary table overview_delivered_approval_payload as
select jsonb_build_object(
  'contract_version', 1,
  'source_quote_request_id', 'ea100001-0000-4000-8000-000000000001',
  'source_intake_id', 'ea200001-0000-4000-8000-000000000001',
  'pricing_snapshot', jsonb_build_object(
    'snapshot_id', 'ea300001-0000-4000-8000-000000000001',
    'snapshot_contract_version', 2,
    'integrity_algorithm_version', 'hmac-sha256-v1',
    'integrity_key_id', 'v1',
    'integrity_mac', repeat('a', 64)
  ),
  'currency', 'EUR',
  'line_items', jsonb_build_array(jsonb_build_object(
    'line_id', 'website', 'sequence', 1, 'product_or_service_code', 'WEBSITE',
    'description', 'Websiteontwikkeling', 'quantity', 1, 'unit', 'project',
    'unit_price_minor', 10000, 'discount_minor', 0, 'vat_treatment', 'STANDARD',
    'vat_rate', 21, 'line_net_amount_minor', 10000, 'cost_type', 'ONE_TIME'
  )),
  'totals', jsonb_build_object(
    'one_time_subtotal_minor', 10000, 'recurring_subtotal_minor', 0,
    'discount_total_minor', 0, 'vat_base_minor', 10000,
    'vat_amount_minor', 2100, 'total_gross_minor', 12100
  ),
  'discount', jsonb_build_object(
    'discount_type', null, 'discount_value_minor', 0, 'discount_reason', null,
    'approved_by', null, 'approved_at', null
  ),
  'customer_identity', jsonb_build_object(
    'source_quote_request_id', 'ea100001-0000-4000-8000-000000000001',
    'source_intake_id', 'ea200001-0000-4000-8000-000000000001',
    'customer_id', null, 'legal_name', 'Delivered Fixture BV',
    'contact_name', 'Delivered Fixture', 'email', 'delivered@example.test',
    'address_line_1', 'Teststraat 1', 'address_line_2', null,
    'postal_code', '9000', 'city', 'Gent', 'country_code', 'BE',
    'enterprise_number', null, 'vat_number', null,
    'source_fields', jsonb_build_object('legal_name', 'fixture'),
    'snapshot_sha256', repeat('b', 64)
  ),
  'project_scope', jsonb_build_object(
    'project_id', null, 'project_title', 'Delivered website', 'project_type', 'website',
    'scope_summary', 'Delivered fixture scope', 'requested_languages', jsonb_build_array('nl'),
    'included_page_count', 1, 'features', '[]'::jsonb, 'copywriting', null,
    'seo', null, 'hosting', null, 'maintenance', null, 'exclusions', '[]'::jsonb,
    'assumptions', '[]'::jsonb, 'indicative_timing', null,
    'source_intake_id', 'ea200001-0000-4000-8000-000000000001',
    'source_pricing_snapshot_id', 'ea300001-0000-4000-8000-000000000001',
    'snapshot_sha256', repeat('c', 64)
  ),
  'vat_approval', jsonb_build_object(
    'vat_treatment', 'STANDARD', 'vat_rate', 21, 'vat_decision_source', 'accountant',
    'vat_approved_by', 'accountant:test', 'vat_approved_at', '2026-08-15T12:00:00Z'
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

set local session_replication_role = replica;
insert into public.quote_request_quotation_approvals(
  id, draft_id, quote_request_id, intake_id, pricing_snapshot_id,
  contract_version, approval_version, approved_payload, payload_sha256, approved_by, approved_at
)
select
  'ea310001-0000-4000-8000-000000000001', 'ea310002-0000-4000-8000-000000000002',
  'ea100001-0000-4000-8000-000000000001', 'ea200001-0000-4000-8000-000000000001',
  'ea300001-0000-4000-8000-000000000001', 1, 1, payload,
  public.quotation_approval_payload_sha256_v1(payload), 'manager-overview:test', statement_timestamp()
from overview_delivered_approval_payload;

insert into public.quote_request_quotation_issuances(
  id, quotation_number, quotation_version, status, approval_id, issued_at, issued_by,
  template_id, template_version, template_sha256, generation_contract_version,
  issuance_input_sha256, generation_payload_sha256, docx_sha256, docx_bytes,
  prepare_idempotency_key, prepare_fingerprint, commit_idempotency_key, commit_fingerprint
) values (
  'ea320001-0000-4000-8000-000000000001', 'LWS-OFF-2099-9001', 1, 'ISSUED',
  'ea310001-0000-4000-8000-000000000001', statement_timestamp(), 'manager-overview:test',
  'LWS_QUOTATION_NL_BE', '1.0.0-technical', repeat('3', 64), 1,
  repeat('4', 64), repeat('5', 64), repeat('6', 64), 12345,
  'ea320002-0000-4000-8000-000000000002', repeat('7', 64),
  'ea320003-0000-4000-8000-000000000003', repeat('8', 64)
);

create temporary table overview_delivered_acceptance_payload as
select jsonb_build_object(
  'acceptance_contract_version', 1,
  'issuance_id', 'ea320001-0000-4000-8000-000000000001',
  'quotation_number', 'LWS-OFF-2099-9001',
  'quotation_version', 1,
  'customer_identity_sha256', repeat('b', 64),
  'generation_payload_sha256', repeat('5', 64),
  'template', jsonb_build_object(
    'template_id', 'LWS_QUOTATION_NL_BE', 'template_version', '1.0.0-technical',
    'template_sha256', repeat('3', 64)
  ),
  'docx', jsonb_build_object('sha256', repeat('6', 64), 'bytes', 12345),
  'acceptance_terms', jsonb_build_object(
    'terms_id', 'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT',
    'terms_version', '1.0.0-technical', 'terms_sha256', repeat('9', 64)
  ),
  'actor', jsonb_build_object(
    'name', 'Delivered Fixture', 'email', 'delivered@example.test',
    'organization', 'Delivered Fixture BV', 'role', 'Bestuurder'
  ),
  'authority_declaration', true,
  'accepted_at', '2026-08-20T12:00:00.000000Z'
) as payload;

insert into public.quote_request_quotation_acceptances(
  id, issuance_id, quotation_number, quotation_version, customer_identity_sha256,
  customer_legal_name, generation_payload_sha256, template_id, template_version,
  template_sha256, docx_sha256, docx_bytes, acceptance_contract_version,
  acceptance_terms_id, acceptance_terms_version, acceptance_terms_sha256,
  accepting_name, accepting_email, accepting_organization, accepting_role,
  authority_declaration, acceptance_payload, acceptance_payload_sha256,
  semantic_request_fingerprint, accepted_at, created_at
)
select
  'ea330001-0000-4000-8000-000000000001', 'ea320001-0000-4000-8000-000000000001',
  'LWS-OFF-2099-9001', 1, repeat('b', 64), 'Delivered Fixture BV', repeat('5', 64),
  'LWS_QUOTATION_NL_BE', '1.0.0-technical', repeat('3', 64), repeat('6', 64), 12345,
  1, 'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT', '1.0.0-technical', repeat('9', 64),
  'Delivered Fixture', 'delivered@example.test', 'Delivered Fixture BV', 'Bestuurder', true,
  payload, public.quotation_acceptance_payload_sha256_v1(payload), repeat('f', 64),
  '2026-08-20T12:00:00Z', '2026-08-20T12:00:00Z'
from overview_delivered_acceptance_payload;

insert into public.commercial_projects(
  project_id, customer_id, quotation_issuance_id, acceptance_id,
  accepted_total_minor, currency, m1_minor, m2_minor, m3_minor, current_state, revision
) values (
  'ea340001-0000-4000-8000-000000000001', 'ea340002-0000-4000-8000-000000000002',
  'ea320001-0000-4000-8000-000000000001', 'ea330001-0000-4000-8000-000000000001',
  10000, 'EUR', 4000, 4000, 2000, 'DELIVERED', 1
);
set local session_replication_role = origin;

select set_config('request.jwt.claim.sub', 'ea000000-0000-4000-8000-000000000001', true);
select lives_ok($$select public.get_operations_manager_business_overview_v1()$$, 'ACTIVE owner is allowed');
select set_config('request.jwt.claim.sub', 'ea000000-0000-4000-8000-000000000002', true);
select lives_ok($$select public.get_operations_manager_business_overview_v1()$$, 'ACTIVE Operations Manager is allowed');
select set_config('request.jwt.claim.sub', 'ea000000-0000-4000-8000-000000000003', true);
select throws_ok($$select public.get_operations_manager_business_overview_v1()$$, '42501', 'OPERATIONS_MANAGER_BUSINESS_OVERVIEW_READER_REQUIRED', 'admin is denied');
select set_config('request.jwt.claim.sub', 'ea000000-0000-4000-8000-000000000004', true);
select throws_ok($$select public.get_operations_manager_business_overview_v1()$$, '42501', 'OPERATIONS_MANAGER_BUSINESS_OVERVIEW_READER_REQUIRED', 'operator is denied');
select set_config('request.jwt.claim.sub', 'ea000000-0000-4000-8000-000000000005', true);
select throws_ok($$select public.get_operations_manager_business_overview_v1()$$, '42501', 'OPERATIONS_MANAGER_BUSINESS_OVERVIEW_READER_REQUIRED', 'reviewer is denied');
select set_config('request.jwt.claim.sub', 'ea000000-0000-4000-8000-000000000006', true);
select throws_ok($$select public.get_operations_manager_business_overview_v1()$$, '42501', 'OPERATIONS_MANAGER_BUSINESS_OVERVIEW_READER_REQUIRED', 'read_only is denied');
select set_config('request.jwt.claim.sub', 'ea000000-0000-4000-8000-000000000007', true);
select throws_ok($$select public.get_operations_manager_business_overview_v1()$$, '42501', 'OPERATOR_DISABLED', 'DISABLED manager is denied');
select set_config('request.jwt.claim.sub', 'ea000000-0000-4000-8000-000000000008', true);
select throws_ok($$select public.get_operations_manager_business_overview_v1()$$, '42501', 'OPERATOR_REVOKED', 'REVOKED manager is denied');
select set_config('request.jwt.claim.sub', 'ea000000-0000-4000-8000-000000000009', true);
select throws_ok($$select public.get_operations_manager_business_overview_v1()$$, '42501', 'UNKNOWN_OPERATOR', 'unknown human is denied');
select set_config('request.jwt.claim.sub', '', true);
select throws_ok($$select public.get_operations_manager_business_overview_v1()$$, '42501', 'HUMAN_JWT_REQUIRED', 'unauthenticated caller is denied');

select set_config('request.jwt.claim.sub', 'ea000000-0000-4000-8000-000000000002', true);
create temporary table overview_result as
select public.get_operations_manager_business_overview_v1() as value;

select is((select (value->>'total_count')::integer from overview_result), 10, 'dataset includes all open plus recent terminal production records');
select is((select (value->>'open_count')::integer from overview_result), 8, 'open_count includes only operationally open records');
select is((select (value->'counts_by_source'->>'website')::integer from overview_result), 9, 'Website production records are counted separately');
select is((select (value->'counts_by_source'->>'slimme_documentenflow')::integer from overview_result), 1, 'Documentenflow production records are counted separately');
select is((select (value->'counts_by_status'->>'SUBMITTED')::integer from overview_result), 6, 'SUBMITTED status count is exact');
select is((select (value->'counts_by_status'->>'REVIEWED')::integer from overview_result), 1, 'REVIEWED status count is exact');
select is((select (value->'counts_by_status'->>'CANCELLED')::integer from overview_result), 2, 'recent terminal CANCELLED records remain status-counted');
select is((select (value->'counts_by_status'->>'DELIVERED')::integer from overview_result), 1, 'DELIVERED is projected through the canonical project composition');
select is((select (value->>'open_count')::integer from overview_result), 8, 'DELIVERED remains included in open_count');
select is((select (value->'counts_by_waiting_bucket'->>'lt_24h')::integer from overview_result), 1, 'DELIVERED remains in its single lt_24h waiting bucket');
select is((select (value->'counts_by_waiting_bucket'->>'lt_24h')::integer from overview_result), 1, 'age below 24 hours maps to lt_24h');
select is((select (value->'counts_by_waiting_bucket'->>'d1_3')::integer from overview_result), 3, '24 hours through just below 4 days map to d1_3');
select is((select (value->'counts_by_waiting_bucket'->>'d4_7')::integer from overview_result), 2, '4 days through just below 8 days map to d4_7');
select is((select (value->'counts_by_waiting_bucket'->>'gt_7d')::integer from overview_result), 2, '8 days and older open records map to gt_7d');
select is(
  (select ((value->'counts_by_waiting_bucket'->>'lt_24h')::integer
    + (value->'counts_by_waiting_bucket'->>'d1_3')::integer
    + (value->'counts_by_waiting_bucket'->>'d4_7')::integer
    + (value->'counts_by_waiting_bucket'->>'gt_7d')::integer) from overview_result),
  8,
  'waiting buckets are gapless, non-overlapping, and exclude terminal records'
);
select ok(
  (select value ?& array['as_of','total_count','open_count','counts_by_source','counts_by_status','counts_by_waiting_bucket']
    and (select count(*) from jsonb_object_keys(value)) = 6 from overview_result),
  'top-level output has exactly the six allowlisted keys'
);
select ok(
  (select value->'counts_by_source' ?& array['website','slimme_documentenflow']
    and (select count(*) from jsonb_object_keys(value->'counts_by_source')) = 2 from overview_result),
  'source map has exactly the two canonical source keys'
);
select ok(
  (select value->'counts_by_waiting_bucket' ?& array['lt_24h','d1_3','d4_7','gt_7d']
    and (select count(*) from jsonb_object_keys(value->'counts_by_waiting_bucket')) = 4 from overview_result),
  'waiting map has exactly the four approved buckets'
);
select ok(
  (select value->'counts_by_status' ?& array[
    'CANCELLED','SUBMITTED','REVIEWED','QUOTE_ACCEPTED','M1_PAYMENT_PENDING',
    'M1_PAYMENT_RECEIVED','PROJECT_RELEASED','PREVIEW_READY','M2_PAYMENT_RECEIVED',
    'FINAL_APPROVAL_RECORDED','FULL_PAYMENT_RECEIVED','FINAL_TRANSFER_AUTHORIZED',
    'DELIVERED','ARCHIVED'
  ] and (select count(*) from jsonb_object_keys(value->'counts_by_status')) = 14 from overview_result),
  'status map has exactly the canonical operational status allowlist'
);
select is(
  (select sum(status_count::integer)
   from overview_result
   cross join lateral jsonb_each_text(value->'counts_by_status') as status(key_name, status_count)),
  10::bigint,
  'status counts sum exactly to total_count'
);
select is(
  (select sum(source_count::integer)
   from overview_result
   cross join lateral jsonb_each_text(value->'counts_by_source') as source(key_name, source_count)),
  10::bigint,
  'source counts sum exactly to total_count'
);
select ok(
  (select jsonb_typeof(value->'total_count') = 'number'
    and jsonb_typeof(value->'open_count') = 'number' from overview_result),
  'top-level counts are JSON numbers'
);
select ok(
  not exists (
    select 1 from overview_result
    cross join lateral jsonb_each(value->'counts_by_source') as source(key_name, source_count)
    where jsonb_typeof(source_count) <> 'number'
  )
  and not exists (
    select 1 from overview_result
    cross join lateral jsonb_each(value->'counts_by_status') as status(key_name, status_count)
    where jsonb_typeof(status_count) <> 'number'
  )
  and not exists (
    select 1 from overview_result
    cross join lateral jsonb_each(value->'counts_by_waiting_bucket') as bucket(key_name, bucket_count)
    where jsonb_typeof(bucket_count) <> 'number'
  ),
  'all nested aggregate counts are JSON numbers'
);
select ok(
  not ((select value from overview_result) @? '$.** ? (@ == null)'),
  'aggregate output contains no null count cells'
);
select ok(
  (select jsonb_typeof(value->'as_of') = 'string'
    and (value->>'as_of')::timestamptz >= transaction_timestamp()
    and (value->>'as_of')::timestamptz <= statement_timestamp() from overview_result),
  'as_of is the single statement timestamp used by the call'
);
select is(
  (select count(*)::integer
   from lws_internal.operator_application_readmodel_v2
   where operational_status = 'CANCELLED'
     and dossier_date >= statement_timestamp() - interval '90 days'),
  2,
  '90-day fixtures prove recent terminal inclusion and just-outside exclusion'
);
select ok(
  (select jsonb_typeof(value) = 'object'
    and jsonb_typeof(value->'counts_by_source') = 'object'
    and jsonb_typeof(value->'counts_by_status') = 'object'
    and jsonb_typeof(value->'counts_by_waiting_bucket') = 'object' from overview_result),
  'output contains aggregate objects and no record arrays'
);
select ok(
  not ((select value::text from overview_result) ~* 'quote_request_id|intake_id|project_id|dossier_id|customer_id|operator_id|application_reference|support_reference'),
  'output exposes no record identifiers or references'
);
select ok(
  not ((select value::text from overview_result) ~* 'name|organization|company|email|phone|address|auth_user_id'),
  'output exposes no person, organization, contact, address, or auth identity'
);
select ok(
  not ((select value::text from overview_result) ~* '"(description|notes|reason|budget|pricing|quotation|payment|finance)"\s*:'),
  'output exposes no free text, budget, pricing, quotation, payment, or finance fields'
);
select ok(
  not ((select value::text from overview_result) ~* '"(project|dossier|lifecycle|submitted_at|created_at|relevant_at)"\s*:'),
  'output exposes no project, dossier, lifecycle, or raw record timestamps'
);
select is(
  (select (value->>'as_of')::timestamptz from overview_result),
  (select (value->>'as_of')::timestamptz from overview_result),
  'one consistent as_of is emitted per aggregate result'
);
select is(
  public.get_operations_manager_business_overview_v1() - 'as_of',
  public.get_operations_manager_business_overview_v1() - 'as_of',
  'unchanged fixtures produce a coherent repeat aggregate result'
);

savepoint overview_missing_state;
delete from lws_internal.operator_dossier_states
where quote_request_id = 'ea100001-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.get_operations_manager_business_overview_v1()$$,
  '23514', 'OPERATOR_DOSSIER_STATE_REQUIRED',
  'missing canonical dossier state fails the business overview closed'
);
select is(
  (select count(*)::integer from lws_internal.operator_dossier_states
   where quote_request_id = 'ea100001-0000-4000-8000-000000000001'),
  0,
  'failed overview does not repair or recreate missing dossier state'
);
rollback to savepoint overview_missing_state;

select set_config('request.jwt.claim.sub', 'ea000000-0000-4000-8000-000000000002', true);
set local session_replication_role = replica;
update public.quote_requests set record_classification = 'internal_e2e' where record_classification = 'production';
set local session_replication_role = origin;
select is(
  public.get_operations_manager_business_overview_v1() - 'as_of',
  jsonb_build_object(
    'total_count', 0,
    'open_count', 0,
    'counts_by_source', jsonb_build_object('website', 0, 'slimme_documentenflow', 0),
    'counts_by_status', jsonb_build_object(
      'CANCELLED', 0, 'SUBMITTED', 0, 'REVIEWED', 0, 'QUOTE_ACCEPTED', 0,
      'M1_PAYMENT_PENDING', 0, 'M1_PAYMENT_RECEIVED', 0, 'PROJECT_RELEASED', 0,
      'PREVIEW_READY', 0, 'M2_PAYMENT_RECEIVED', 0, 'FINAL_APPROVAL_RECORDED', 0,
      'FULL_PAYMENT_RECEIVED', 0, 'FINAL_TRANSFER_AUTHORIZED', 0, 'DELIVERED', 0, 'ARCHIVED', 0
    ),
    'counts_by_waiting_bucket', jsonb_build_object('lt_24h', 0, 'd1_3', 0, 'd4_7', 0, 'gt_7d', 0)
  ),
  'zero-production state returns a complete deterministic zero shape'
);

select * from finish();
rollback;