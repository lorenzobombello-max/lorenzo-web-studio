begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public', 'get_operations_manager_business_queue_v1', array['text', 'integer'],
  'Operations Manager business queue RPC exists'
);
select ok(
  exists (
    select 1 from pg_proc
    where oid = 'public.get_operations_manager_business_queue_v1(text,integer)'::regprocedure
      and prosecdef
      and provolatile = 's'
      and proconfig = array['search_path=public, auth, pg_catalog']
  ),
  'business queue is stable SECURITY DEFINER with a fixed safe search_path'
);
select is(
  pg_get_function_arguments('public.get_operations_manager_business_queue_v1(text,integer)'::regprocedure),
  'p_cursor text DEFAULT NULL::text, p_limit integer DEFAULT 25',
  'cursor defaults to null and omitted limit defaults to 25'
);
select ok(
  has_function_privilege('authenticated', 'public.get_operations_manager_business_queue_v1(text,integer)', 'execute')
  and not has_function_privilege('anon', 'public.get_operations_manager_business_queue_v1(text,integer)', 'execute')
  and not has_function_privilege('service_role', 'public.get_operations_manager_business_queue_v1(text,integer)', 'execute')
  and not has_function_privilege('public', 'public.get_operations_manager_business_queue_v1(text,integer)', 'execute'),
  'only authenticated receives RPC execute privilege'
);
select ok(
  not has_table_privilege('anon', 'public.quote_requests', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.quote_requests', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.quote_request_intakes', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.quote_request_intakes', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'lws_internal.operator_application_readmodel_v2', 'select')
  and not has_table_privilege('service_role', 'lws_internal.operator_application_readmodel_v2', 'select'),
  'source tables and private readmodel receive no new browser grants'
);
select ok(
  (select prosrc !~* '\m(insert|update|delete|merge|truncate|upsert)\M'
   from pg_proc where oid = 'public.get_operations_manager_business_queue_v1(text,integer)'::regprocedure),
  'business queue runtime contains no mutation statement'
);
select ok(
  (select prosrc !~* 'select\s+\*|readmodel\.\*|row_to_json|to_jsonb\s*\(\s*readmodel|resolve_commercial_operator_authorization|commercial_operator_project_grants|list_operator_applications_v2'
   from pg_proc where oid = 'public.get_operations_manager_business_queue_v1(text,integer)'::regprocedure),
  'runtime has no whole-row leak, inherited resolver, projectgrant, or operator-list authority'
);
select ok(
  (select strpos(prosrc, 'if v_actor_role not in') < strpos(prosrc, 'perform lws_internal.assert_operator_readmodel_integrity_v2()')
      and strpos(prosrc, 'perform lws_internal.assert_operator_readmodel_integrity_v2()') < strpos(prosrc, 'from lws_internal.operator_application_readmodel_v2')
   from pg_proc where oid = 'public.get_operations_manager_business_queue_v1(text,integer)'::regprocedure),
  'caller authorization precedes integrity assertion and readmodel consumption'
);
select ok(
  (select prosrc ~ 'jsonb_build_object' and prosrc !~* 'repair|fallbackstate|insert into.*operator_dossier_states'
   from pg_proc where oid = 'public.get_operations_manager_business_queue_v1(text,integer)'::regprocedure),
  'explicit JSON allowlists are used without repair or state creation'
);

insert into auth.users(id, email) values
  ('fb000000-0000-4000-8000-000000000001', 'queue-owner@example.test'),
  ('fb000000-0000-4000-8000-000000000002', 'queue-manager@example.test'),
  ('fb000000-0000-4000-8000-000000000003', 'queue-admin@example.test'),
  ('fb000000-0000-4000-8000-000000000004', 'queue-operator@example.test'),
  ('fb000000-0000-4000-8000-000000000005', 'queue-reviewer@example.test'),
  ('fb000000-0000-4000-8000-000000000006', 'queue-read-only@example.test'),
  ('fb000000-0000-4000-8000-000000000007', 'queue-disabled@example.test'),
  ('fb000000-0000-4000-8000-000000000008', 'queue-revoked@example.test'),
  ('fb000000-0000-4000-8000-000000000009', 'queue-unknown@example.test');

insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status, revoked_at) values
  ('fb010000-0000-4000-8000-000000000001', 'fb000000-0000-4000-8000-000000000001', 'Queue Owner', 'owner', 'ACTIVE', null),
  ('fb010000-0000-4000-8000-000000000002', 'fb000000-0000-4000-8000-000000000002', 'Queue Manager', 'operations_manager', 'ACTIVE', null),
  ('fb010000-0000-4000-8000-000000000003', 'fb000000-0000-4000-8000-000000000003', 'Queue Admin', 'admin', 'ACTIVE', null),
  ('fb010000-0000-4000-8000-000000000004', 'fb000000-0000-4000-8000-000000000004', 'Queue Operator', 'operator', 'ACTIVE', null),
  ('fb010000-0000-4000-8000-000000000005', 'fb000000-0000-4000-8000-000000000005', 'Queue Reviewer', 'reviewer', 'ACTIVE', null),
  ('fb010000-0000-4000-8000-000000000006', 'fb000000-0000-4000-8000-000000000006', 'Queue Read Only', 'read_only', 'ACTIVE', null),
  ('fb010000-0000-4000-8000-000000000007', 'fb000000-0000-4000-8000-000000000007', 'Queue Disabled', 'operations_manager', 'DISABLED', null),
  ('fb010000-0000-4000-8000-000000000008', 'fb000000-0000-4000-8000-000000000008', 'Queue Revoked', 'operations_manager', 'REVOKED', statement_timestamp());

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind, created_at,
  name, email, website_type, budget, timing, description, privacy_consent, status
) values
  ('fb100001-0000-4000-8000-000000000001', 'LWS-AAN-2099-0002', 'production', 'website', '2099-01-01T09:00:00Z', 'Fixture A', 'a@example.test', 'business', 'x', 'x', 'Queue fixture.', true, 'approved'),
  ('fb100002-0000-4000-8000-000000000002', 'LWS-AAN-2099-0001', 'production', 'website', '2099-01-01T09:00:00Z', 'Fixture B', 'b@example.test', 'business', 'x', 'x', 'Queue fixture.', true, 'approved'),
  ('fb100003-0000-4000-8000-000000000003', 'LWS-AAN-2099-0003', 'production', 'website', '2099-01-02T09:00:00Z', 'Fixture C', 'c@example.test', 'business', 'x', 'x', 'Queue fixture.', true, 'approved'),
  ('fb100004-0000-4000-8000-000000000004', 'LWS-AAN-2099-0004', 'internal_e2e', 'website', '2099-01-01T08:00:00Z', 'Fixture D', 'd@example.test', 'business', 'x', 'x', 'Queue fixture.', true, 'approved');

insert into public.quote_request_intakes(
  id, quote_request_id, access_token_hash, access_token_expires_at, status,
  started_at, submitted_at, reviewed_at, confirmation
) values
  ('fb200001-0000-4000-8000-000000000001', 'fb100001-0000-4000-8000-000000000001', repeat('1', 64), '2100-01-01T00:00:00Z', 'submitted', '2099-01-01T09:00:00Z', '2099-01-01T10:00:00Z', null, true),
  ('fb200002-0000-4000-8000-000000000002', 'fb100002-0000-4000-8000-000000000002', repeat('2', 64), '2100-01-01T00:00:00Z', 'reviewed', '2099-01-01T09:00:00Z', '2099-01-01T10:00:00Z', '2099-01-01T11:00:00Z', true),
  ('fb200003-0000-4000-8000-000000000003', 'fb100003-0000-4000-8000-000000000003', repeat('3', 64), '2100-01-01T00:00:00Z', 'submitted', '2099-01-02T09:00:00Z', '2099-01-02T10:00:00Z', null, true),
  ('fb200004-0000-4000-8000-000000000004', 'fb100004-0000-4000-8000-000000000004', repeat('4', 64), '2100-01-01T00:00:00Z', 'submitted', '2099-01-01T08:00:00Z', '2099-01-01T09:00:00Z', null, true);

update public.quote_request_intakes
set access_state = 'CANCELLED', access_token_revoked_at = statement_timestamp()
where quote_request_id = 'fb100003-0000-4000-8000-000000000003';

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind, sdf_package,
  created_at, name, email, description, privacy_consent, status
)
select
  ('fb' || lpad(series::text, 6, '0') || '-0000-4000-8000-' || lpad(series::text, 12, '0'))::uuid,
  case when series = 100 then null else 'LWS-AAN-2099-' || lpad(series::text, 4, '0') end,
  'production', 'slimme_documentenflow', 'start',
  '2099-01-03T10:00:00Z'::timestamptz + make_interval(mins => series - 100),
  'SDF Fixture ' || series, 'sdf' || series || '@example.test', 'Queue fixture.', true, 'approved'
from generate_series(100, 126) as series;

insert into public.sdf_qualification_intakes(
  intake_id, quote_request_id, status, customer_capability_digest,
  customer_capability_encrypted, customer_capability_expires_at, submitted_at
)
select
  ('fc' || lpad(series::text, 6, '0') || '-0000-4000-8000-' || lpad(series::text, 12, '0'))::uuid,
  ('fb' || lpad(series::text, 6, '0') || '-0000-4000-8000-' || lpad(series::text, 12, '0'))::uuid,
  'submitted', encode(extensions.digest(convert_to(series::text, 'UTF8'), 'sha256'), 'hex'),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  '2100-01-01T00:00:00Z',
  '2099-01-03T10:00:00Z'::timestamptz + make_interval(mins => series - 100)
from generate_series(100, 126) as series;

create temporary table queue_delivered_approval_payload as
select jsonb_build_object(
  'contract_version', 1,
  'source_quote_request_id', 'fb100001-0000-4000-8000-000000000001',
  'source_intake_id', 'fb200001-0000-4000-8000-000000000001',
  'pricing_snapshot', jsonb_build_object(
    'snapshot_id', 'fb300001-0000-4000-8000-000000000001',
    'snapshot_contract_version', 2, 'integrity_algorithm_version', 'hmac-sha256-v1',
    'integrity_key_id', 'v1', 'integrity_mac', repeat('a', 64)
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
    'source_quote_request_id', 'fb100001-0000-4000-8000-000000000001',
    'source_intake_id', 'fb200001-0000-4000-8000-000000000001',
    'customer_id', null, 'legal_name', 'Queue Fixture BV', 'contact_name', 'Queue Fixture',
    'email', 'delivered@example.test', 'address_line_1', 'Teststraat 1',
    'address_line_2', null, 'postal_code', '9000', 'city', 'Gent', 'country_code', 'BE',
    'enterprise_number', null, 'vat_number', null,
    'source_fields', jsonb_build_object('legal_name', 'fixture'), 'snapshot_sha256', repeat('b', 64)
  ),
  'project_scope', jsonb_build_object(
    'project_id', null, 'project_title', 'Queue website', 'project_type', 'website',
    'scope_summary', 'Queue fixture scope', 'requested_languages', jsonb_build_array('nl'),
    'included_page_count', 1, 'features', '[]'::jsonb, 'copywriting', null, 'seo', null,
    'hosting', null, 'maintenance', null, 'exclusions', '[]'::jsonb, 'assumptions', '[]'::jsonb,
    'indicative_timing', null, 'source_intake_id', 'fb200001-0000-4000-8000-000000000001',
    'source_pricing_snapshot_id', 'fb300001-0000-4000-8000-000000000001',
    'snapshot_sha256', repeat('c', 64)
  ),
  'vat_approval', jsonb_build_object(
    'vat_treatment', 'STANDARD', 'vat_rate', 21, 'vat_decision_source', 'accountant',
    'vat_approved_by', 'accountant:test', 'vat_approved_at', '2026-08-15T12:00:00Z'
  ),
  'payment_schedule', jsonb_build_object(
    'schedule_id', 'schedule-1', 'milestones', jsonb_build_array(jsonb_build_object(
      'sequence', 1, 'label', 'Volledige betaling', 'percentage', 100,
      'amount_minor', null, 'trigger', 'invoice', 'due_terms_days', 30, 'recurring_cycle', null
    )), 'approved_by', 'commercial:test', 'approved_at', '2026-08-15T12:00:00Z'
  ),
  'validity', jsonb_build_object(
    'valid_from', '2026-08-15', 'valid_until', '2026-09-14', 'validity_days', 30,
    'approved_by', 'commercial:test', 'approved_at', '2026-08-15T12:00:00Z'
  ),
  'legal_references', jsonb_build_object(
    'terms_reference', 'terms-v1', 'terms_version', '1.0.0', 'terms_sha256', repeat('d', 64),
    'terms_status', 'APPROVED', 'agreement_template_reference', null,
    'agreement_template_version', null, 'agreement_template_sha256', null
  )
) as payload;

set local session_replication_role = replica;
insert into public.quote_request_quotation_approvals(
  id, draft_id, quote_request_id, intake_id, pricing_snapshot_id, contract_version,
  approval_version, approved_payload, payload_sha256, approved_by, approved_at
)
select
  'fb310001-0000-4000-8000-000000000001', 'fb310002-0000-4000-8000-000000000002',
  'fb100001-0000-4000-8000-000000000001', 'fb200001-0000-4000-8000-000000000001',
  'fb300001-0000-4000-8000-000000000001', 1, 1, payload,
  public.quotation_approval_payload_sha256_v1(payload), 'queue:test', statement_timestamp()
from queue_delivered_approval_payload;

insert into public.quote_request_quotation_issuances(
  id, quotation_number, quotation_version, status, approval_id, issued_at, issued_by,
  template_id, template_version, template_sha256, generation_contract_version,
  issuance_input_sha256, generation_payload_sha256, docx_sha256, docx_bytes,
  prepare_idempotency_key, prepare_fingerprint, commit_idempotency_key, commit_fingerprint
) values (
  'fb320001-0000-4000-8000-000000000001', 'LWS-OFF-2099-9002', 1, 'ISSUED',
  'fb310001-0000-4000-8000-000000000001', statement_timestamp(), 'queue:test',
  'LWS_QUOTATION_NL_BE', '1.0.0-technical', repeat('3', 64), 1,
  repeat('4', 64), repeat('5', 64), repeat('6', 64), 12345,
  'fb320002-0000-4000-8000-000000000002', repeat('7', 64),
  'fb320003-0000-4000-8000-000000000003', repeat('8', 64)
);

create temporary table queue_delivered_acceptance_payload as
select jsonb_build_object(
  'acceptance_contract_version', 1,
  'issuance_id', 'fb320001-0000-4000-8000-000000000001',
  'quotation_number', 'LWS-OFF-2099-9002', 'quotation_version', 1,
  'customer_identity_sha256', repeat('b', 64), 'generation_payload_sha256', repeat('5', 64),
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
    'name', 'Queue Fixture', 'email', 'delivered@example.test',
    'organization', 'Queue Fixture BV', 'role', 'Bestuurder'
  ),
  'authority_declaration', true, 'accepted_at', '2026-08-20T12:00:00.000000Z'
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
  'fb330001-0000-4000-8000-000000000001', 'fb320001-0000-4000-8000-000000000001',
  'LWS-OFF-2099-9002', 1, repeat('b', 64), 'Queue Fixture BV', repeat('5', 64),
  'LWS_QUOTATION_NL_BE', '1.0.0-technical', repeat('3', 64), repeat('6', 64), 12345,
  1, 'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT', '1.0.0-technical', repeat('9', 64),
  'Queue Fixture', 'delivered@example.test', 'Queue Fixture BV', 'Bestuurder', true,
  payload, public.quotation_acceptance_payload_sha256_v1(payload), repeat('f', 64),
  '2026-08-20T12:00:00Z', '2026-08-20T12:00:00Z'
from queue_delivered_acceptance_payload;

insert into public.commercial_projects(
  project_id, customer_id, quotation_issuance_id, acceptance_id,
  accepted_total_minor, currency, m1_minor, m2_minor, m3_minor, current_state, revision
) values (
  'fb340001-0000-4000-8000-000000000001', 'fb340002-0000-4000-8000-000000000002',
  'fb320001-0000-4000-8000-000000000001', 'fb330001-0000-4000-8000-000000000001',
  10000, 'EUR', 4000, 4000, 2000, 'DELIVERED', 1
);
set local session_replication_role = origin;

select set_config('request.jwt.claim.sub', 'fb000000-0000-4000-8000-000000000001', true);
select lives_ok($$select public.get_operations_manager_business_queue_v1()$$, 'ACTIVE owner is allowed');
select set_config('request.jwt.claim.sub', 'fb000000-0000-4000-8000-000000000002', true);
select lives_ok($$select public.get_operations_manager_business_queue_v1()$$, 'ACTIVE Operations Manager is allowed');
select set_config('request.jwt.claim.sub', 'fb000000-0000-4000-8000-000000000003', true);
select throws_ok($$select public.get_operations_manager_business_queue_v1()$$, '42501', 'OPERATIONS_MANAGER_BUSINESS_QUEUE_READER_REQUIRED', 'admin is denied');
select set_config('request.jwt.claim.sub', 'fb000000-0000-4000-8000-000000000004', true);
select throws_ok($$select public.get_operations_manager_business_queue_v1()$$, '42501', 'OPERATIONS_MANAGER_BUSINESS_QUEUE_READER_REQUIRED', 'operator is denied');
select set_config('request.jwt.claim.sub', 'fb000000-0000-4000-8000-000000000005', true);
select throws_ok($$select public.get_operations_manager_business_queue_v1()$$, '42501', 'OPERATIONS_MANAGER_BUSINESS_QUEUE_READER_REQUIRED', 'reviewer is denied');
select set_config('request.jwt.claim.sub', 'fb000000-0000-4000-8000-000000000006', true);
select throws_ok($$select public.get_operations_manager_business_queue_v1()$$, '42501', 'OPERATIONS_MANAGER_BUSINESS_QUEUE_READER_REQUIRED', 'read_only is denied');
select set_config('request.jwt.claim.sub', 'fb000000-0000-4000-8000-000000000007', true);
select throws_ok($$select public.get_operations_manager_business_queue_v1()$$, '42501', 'OPERATOR_DISABLED', 'DISABLED manager is denied');
select set_config('request.jwt.claim.sub', 'fb000000-0000-4000-8000-000000000008', true);
select throws_ok($$select public.get_operations_manager_business_queue_v1()$$, '42501', 'OPERATOR_REVOKED', 'REVOKED manager is denied');
select set_config('request.jwt.claim.sub', 'fb000000-0000-4000-8000-000000000009', true);
select throws_ok($$select public.get_operations_manager_business_queue_v1()$$, '42501', 'UNKNOWN_OPERATOR', 'unknown human is denied');
select set_config('request.jwt.claim.sub', '', true);
select throws_ok($$select public.get_operations_manager_business_queue_v1()$$, '42501', 'HUMAN_JWT_REQUIRED', 'unauthenticated caller is denied');

select set_config('request.jwt.claim.sub', 'fb000000-0000-4000-8000-000000000002', true);
create temporary table queue_result as
select public.get_operations_manager_business_queue_v1() as value;

select is(jsonb_array_length(value->'items'), 25, 'omitted limit returns the default 25 items') from queue_result;
select is((value->>'has_more')::boolean, true, 'default page reports additional open rows') from queue_result;
select ok((value->>'as_of')::timestamptz is not null, 'one server-side as_of timestamp is returned') from queue_result;
select is(
  (select array_agg(key order by key) from jsonb_object_keys(value) as key),
  array['as_of','has_more','items','next_cursor']::text[],
  'top-level output has exactly four allowlisted keys'
) from queue_result;
select ok(
  not (value ?| array['total_count','open_count','counts_by_source','counts_by_status']),
  'aggregate fields are not duplicated into Candidate B'
) from queue_result;
select ok(
  not exists (
    select 1 from queue_result, jsonb_array_elements(value->'items') as item
    where (select array_agg(key order by key) from jsonb_object_keys(item) as key)
       <> array['received_at','reference','source','status']::text[]
  ),
  'every item has exactly reference, source, status, and received_at'
);
select ok(
  not exists (
    select 1 from queue_result, jsonb_array_elements(value->'items') as item
    where item ?| array[
      'quote_request_id','id','name','customer_name','organization','organization_name',
      'email','phone','address','website_url','reason','notes','budget','quotation_amount',
      'vat','payment_amount','finance','project','dossier','revision','zone','operator_id','role','grant'
    ]
  ),
  'items expose no IDs, PII, finance, project, dossier, lifecycle, operator, or grant detail'
);
select ok(
  not exists (
    select 1 from queue_result, jsonb_array_elements(value->'items') as item
    where item->>'source' not in ('website', 'slimme_documentenflow')
       or item->>'status' in ('CANCELLED', 'ARCHIVED')
       or nullif(item->>'reference', '') is null
       or nullif(item->>'received_at', '') is null
  ),
  'visible rows satisfy source, open-status, reference, and received_at contracts'
);
select is(
  (select item->>'reference' from queue_result, jsonb_array_elements(value->'items') as item
   where item->>'reference' = 'LWS-AAN-2099-0002'),
  'LWS-AAN-2099-0002',
  'application_reference is the preferred visible reference'
);
select is(
  (select item->>'source' from queue_result, jsonb_array_elements(value->'items') as item
   where item->>'reference' = 'LWS-AAN-2099-0002'),
  'website',
  'website source is mapped directly from request_kind'
);
select is(
  (select item->>'status' from queue_result, jsonb_array_elements(value->'items') as item
   where item->>'reference' = 'LWS-AAN-2099-0002'),
  'DELIVERED',
  'canonical DELIVERED status remains open and visible'
);
select is(
  (select item->>'received_at' from queue_result, jsonb_array_elements(value->'items') as item
   where item->>'reference' = 'LWS-AAN-2099-0002'),
  '2099-01-01T10:00:00+00:00',
  'website received_at is the canonical intake submitted_at'
);
select is(
  (select item->>'status' from queue_result, jsonb_array_elements(value->'items') as item
   where item->>'reference' = 'LWS-AAN-2099-0001'),
  'REVIEWED',
  'another canonical open status is included without remapping'
);
select ok(
  not exists (
    select 1 from queue_result, jsonb_array_elements(value->'items') as item
    where item->>'reference' in ('LWS-AAN-2099-0003', 'LWS-AAN-2099-0004')
  ),
  'CANCELLED and internal_e2e records are excluded'
);
select is(
  (select item->>'source' from queue_result, jsonb_array_elements(value->'items') as item
   where item->>'reference' = '#FB000100'),
  'slimme_documentenflow',
  'SDF uses generated support_reference when application_reference is absent'
);
select is(
  (select item->>'received_at' from queue_result, jsonb_array_elements(value->'items') as item
   where item->>'reference' = '#FB000100'),
  '2099-01-03T10:00:00+00:00',
  'SDF received_at is canonical quote request created_at'
);
select is(
  (select (value->'items'->0)->>'reference' from queue_result),
  'LWS-AAN-2099-0001',
  'oldest timestamp is first and equal timestamps use reference ASC'
);
select is(
  (select (value->'items'->1)->>'reference' from queue_result),
  'LWS-AAN-2099-0002',
  'status does not override received_at/reference ordering'
);

select lives_ok($$select public.get_operations_manager_business_queue_v1(null, 1)$$, 'limit 1 is accepted');
select lives_ok($$select public.get_operations_manager_business_queue_v1(null, 100)$$, 'limit 100 is accepted');
select throws_ok($$select public.get_operations_manager_business_queue_v1(null, 0)$$, '22023', 'INVALID_OPERATIONS_MANAGER_BUSINESS_QUEUE_LIMIT', 'zero limit fails closed');
select throws_ok($$select public.get_operations_manager_business_queue_v1(null, -1)$$, '22023', 'INVALID_OPERATIONS_MANAGER_BUSINESS_QUEUE_LIMIT', 'negative limit fails closed');
select throws_ok($$select public.get_operations_manager_business_queue_v1(null, 101)$$, '22023', 'INVALID_OPERATIONS_MANAGER_BUSINESS_QUEUE_LIMIT', 'limit above 100 fails closed');
select throws_ok($$select public.get_operations_manager_business_queue_v1(null, null)$$, '22023', 'INVALID_OPERATIONS_MANAGER_BUSINESS_QUEUE_LIMIT', 'explicit null limit fails closed');
select throws_ok($$select public.get_operations_manager_business_queue_v1('not-a-cursor', 1)$$, '22023', 'INVALID_OPERATIONS_MANAGER_BUSINESS_QUEUE_CURSOR', 'malformed cursor fails closed');
select throws_ok(
  $$select public.get_operations_manager_business_queue_v1(encode(convert_to('{"received_at":"2099-01-01T00:00:00Z","reference":"LWS-AAN-2099-0001","extra":true}','UTF8'),'hex'), 1)$$,
  '22023', 'INVALID_OPERATIONS_MANAGER_BUSINESS_QUEUE_CURSOR',
  'cursor with an extra key fails closed'
);

create temporary table queue_page_one as
select public.get_operations_manager_business_queue_v1(null, 1) as value;
create temporary table queue_page_two as
select public.get_operations_manager_business_queue_v1(
  (select value->>'next_cursor' from queue_page_one), 1
) as value;
select is((select (value->'items'->0)->>'reference' from queue_page_one), 'LWS-AAN-2099-0001', 'page one returns first keyset record');
select is((select (value->'items'->0)->>'reference' from queue_page_two), 'LWS-AAN-2099-0002', 'page two advances without duplicate or gap');
select isnt(
  (select (value->'items'->0)->>'reference' from queue_page_one),
  (select (value->'items'->0)->>'reference' from queue_page_two),
  'adjacent pages contain no duplicate'
);
select is((select (value->>'has_more')::boolean from queue_page_one), true, 'limit plus one sets has_more accurately');
select ok(
  (select convert_from(decode(value->>'next_cursor', 'hex'), 'UTF8')::jsonb
      ?& array['received_at','reference'] from queue_page_one),
  'cursor contains only the public keyset position contract'
);
select ok(
  (select convert_from(decode(value->>'next_cursor', 'hex'), 'UTF8') !~*
      '[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
   from queue_page_one),
  'cursor contains no UUID'
);
select is(
  public.get_operations_manager_business_queue_v1(null, 100)->>'next_cursor',
  null,
  'next_cursor is null when no more rows remain'
);
select is(
  (public.get_operations_manager_business_queue_v1(
    encode(convert_to(jsonb_build_object(
      'received_at', '2199-01-01T00:00:00+00:00',
      'reference', 'LWS-AAN-2199-9999'
    )::text, 'UTF8'), 'hex'), 25
  )->'items'),
  '[]'::jsonb,
  'cursor beyond the fixture returns an empty queue'
);
select is(
  (public.get_operations_manager_business_queue_v1(
    encode(convert_to(jsonb_build_object(
      'received_at', '2199-01-01T00:00:00+00:00',
      'reference', 'LWS-AAN-2199-9999'
    )::text, 'UTF8'), 'hex'), 25
  )->>'has_more')::boolean,
  false,
  'empty queue has_more is false'
);

set local session_replication_role = replica;
update public.commercial_projects
set current_state = 'ARCHIVED', revision = revision + 1, updated_at = statement_timestamp()
where project_id = 'fb340001-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select ok(
  not exists (
    select 1
    from jsonb_array_elements(public.get_operations_manager_business_queue_v1(null, 100)->'items') as item
    where item->>'reference' = 'LWS-AAN-2099-0002'
  ),
  'canonical ARCHIVED status is excluded from the open-only queue'
);

create temporary table queue_fingerprint_before as
select
  (select md5(string_agg(id::text || ':' || coalesce(application_reference, '') || ':' || status, '|' order by id))
   from public.quote_requests where id::text like 'fb%') as request_hash,
  (select md5(string_agg(quote_request_id::text || ':' || state || ':' || revision, '|' order by quote_request_id))
   from lws_internal.operator_dossier_states where quote_request_id::text like 'fb%') as dossier_hash,
  (select count(*) from lws_internal.operations_manager_role_events) as role_event_count,
  (select count(*) from public.commercial_operator_project_grants) as projectgrant_count;
select public.get_operations_manager_business_queue_v1(null, 10);
select is(
  (select request_hash from queue_fingerprint_before),
  (select md5(string_agg(id::text || ':' || coalesce(application_reference, '') || ':' || status, '|' order by id))
   from public.quote_requests where id::text like 'fb%'),
  'queue call does not mutate source business rows'
);
select is(
  (select dossier_hash from queue_fingerprint_before),
  (select md5(string_agg(quote_request_id::text || ':' || state || ':' || revision, '|' order by quote_request_id))
   from lws_internal.operator_dossier_states where quote_request_id::text like 'fb%'),
  'queue call does not mutate dossier or lifecycle state'
);
select is((select role_event_count from queue_fingerprint_before), (select count(*) from lws_internal.operations_manager_role_events), 'queue call writes no manager role event');
select is((select projectgrant_count from queue_fingerprint_before), (select count(*) from public.commercial_operator_project_grants), 'queue call writes no projectgrant');

select set_config('request.jwt.claim.sub', 'fb000000-0000-4000-8000-000000000004', true);
delete from lws_internal.operator_dossier_states
where quote_request_id = 'fb100002-0000-4000-8000-000000000002';
select throws_ok(
  $$select public.get_operations_manager_business_queue_v1()$$,
  '42501', 'OPERATIONS_MANAGER_BUSINESS_QUEUE_READER_REQUIRED',
  'unauthorized role is denied before canonical integrity is evaluated'
);
select set_config('request.jwt.claim.sub', 'fb000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.get_operations_manager_business_queue_v1()$$,
  '23514', 'OPERATOR_DOSSIER_STATE_REQUIRED',
  'authorized caller fails closed on missing canonical dossier state'
);
select is(
  (select count(*)::integer from lws_internal.operator_dossier_states
   where quote_request_id = 'fb100002-0000-4000-8000-000000000002'),
  0,
  'failed queue read does not repair or recreate missing dossier state'
);

select * from finish();
rollback;
