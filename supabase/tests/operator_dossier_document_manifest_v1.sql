begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, storage, extensions;
select plan(30);

select has_function(
  'public', 'get_operator_dossier_document_manifest_v1', array['uuid','uuid'],
  'manifest RPC exists'
);
select has_function(
  'public', 'authorize_operator_dossier_document_download_v1', array['uuid','uuid','text','uuid'],
  'exact download authorization RPC exists'
);
select ok(
  has_function_privilege('service_role', 'public.get_operator_dossier_document_manifest_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.get_operator_dossier_document_manifest_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.get_operator_dossier_document_manifest_v1(uuid,uuid)', 'execute'),
  'manifest is service-role Edge only'
);
select ok(
  has_function_privilege('service_role', 'public.authorize_operator_dossier_document_download_v1(uuid,uuid,text,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.authorize_operator_dossier_document_download_v1(uuid,uuid,text,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.authorize_operator_dossier_document_download_v1(uuid,uuid,text,uuid)', 'execute'),
  'locator authorization is service-role Edge only'
);

insert into auth.users(id, email) values
  ('d2000000-0000-4000-8000-000000000001', 'manifest-owner@example.test'),
  ('d2000000-0000-4000-8000-000000000002', 'manifest-operator@example.test'),
  ('d2000000-0000-4000-8000-000000000003', 'manifest-inactive@example.test'),
  ('d2000000-0000-4000-8000-000000000004', 'manifest-unauthorized@example.test');

insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status
) values
  ('d2010000-0000-4000-8000-000000000001', 'd2000000-0000-4000-8000-000000000001', 'Manifest Owner', 'owner', 'ACTIVE'),
  ('d2010000-0000-4000-8000-000000000002', 'd2000000-0000-4000-8000-000000000002', 'Manifest Operator', 'operator', 'ACTIVE'),
  ('d2010000-0000-4000-8000-000000000003', 'd2000000-0000-4000-8000-000000000003', 'Manifest Inactive', 'operator', 'DISABLED'),
  ('d2010000-0000-4000-8000-000000000004', 'd2000000-0000-4000-8000-000000000004', 'Manifest Unauthorized', 'operator', 'ACTIVE');

create temporary table manifest_authorities (
  scenario text primary key,
  quote_id uuid not null,
  intake_id uuid not null,
  pricing_id uuid not null,
  draft_id uuid not null,
  approval_id uuid not null,
  issuance_id uuid not null,
  artifact_id uuid not null,
  quotation_number text not null,
  docx_sha256 text not null
);

insert into manifest_authorities values
  ('accepted', 'd2100000-0000-4000-8000-000000000001', 'd2110000-0000-4000-8000-000000000001', 'd2120000-0000-4000-8000-000000000001', 'd2130000-0000-4000-8000-000000000001', 'd2140000-0000-4000-8000-000000000001', 'd2150000-0000-4000-8000-000000000001', 'd2160000-0000-4000-8000-000000000001', 'LWS-OFF-2099-0901', repeat('1', 64)),
  ('other', 'd2300000-0000-4000-8000-000000000002', 'd2110000-0000-4000-8000-000000000002', 'd2120000-0000-4000-8000-000000000002', 'd2130000-0000-4000-8000-000000000002', 'd2140000-0000-4000-8000-000000000002', 'd2150000-0000-4000-8000-000000000002', 'd2160000-0000-4000-8000-000000000002', 'LWS-OFF-2099-0902', repeat('2', 64));

insert into public.quote_requests(
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, record_classification
)
select quote_id, 'Manifest ' || scenario, scenario || '@example.test', 'business',
  'EUR 3.200 t/m EUR 6.000', 'flexible', 'Manifest fixture', true, 'approved', 'production'
from manifest_authorities;

insert into public.quote_request_intakes(
  id, quote_request_id, access_token_hash, access_token_expires_at, status,
  started_at, submitted_at, confirmation, admin_access_token_hash,
  admin_access_token_expires_at
)
select intake_id, quote_id,
  encode(extensions.digest(convert_to('manifest-access-' || scenario, 'UTF8'), 'sha256'), 'hex'),
  clock_timestamp() + interval '1 day',
  'submitted', clock_timestamp(), clock_timestamp(), true,
  encode(extensions.digest(convert_to('manifest-admin-' || scenario, 'UTF8'), 'sha256'), 'hex'),
  clock_timestamp() + interval '1 day'
from manifest_authorities;

insert into public.quote_request_pricing_snapshots(
  id, intake_id, snapshot_contract_version, config_version, config_hash,
  normalized_evidence, calculation, package_advice, budget_evaluation
)
select pricing_id, intake_id, 2, '1.0.0', repeat('5', 64),
  '{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}',
  '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":180000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000}]}',
  '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}',
  '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}'
from manifest_authorities;

insert into public.quote_request_pricing_snapshot_integrity(
  snapshot_id, algorithm_version, key_id, mac
)
select pricing_id, 'hmac-sha256-v1', 'v1', repeat('6', 64)
from manifest_authorities;

create temporary table manifest_payloads as
select authority.*,
  jsonb_build_object(
    'contract_version', 1,
    'source_quote_request_id', quote_id,
    'source_intake_id', intake_id,
    'pricing_snapshot', jsonb_build_object('snapshot_id', pricing_id, 'snapshot_contract_version', 2, 'integrity_algorithm_version', 'hmac-sha256-v1', 'integrity_key_id', 'v1', 'integrity_mac', repeat('6', 64)),
    'currency', 'EUR',
    'line_items', jsonb_build_array(jsonb_build_object('line_id', 'website', 'sequence', 1, 'product_or_service_code', 'WEBSITE', 'description', 'Websiteontwikkeling', 'quantity', 1, 'unit', 'project', 'unit_price_minor', 10000, 'discount_minor', 0, 'vat_treatment', 'STANDARD', 'vat_rate', 21, 'line_net_amount_minor', 10000, 'cost_type', 'ONE_TIME')),
    'totals', jsonb_build_object('one_time_subtotal_minor', 10000, 'recurring_subtotal_minor', 0, 'discount_total_minor', 0, 'vat_base_minor', 10000, 'vat_amount_minor', 2100, 'total_gross_minor', 12100),
    'discount', jsonb_build_object('discount_type', null, 'discount_value_minor', 0, 'discount_reason', null, 'approved_by', null, 'approved_at', null),
    'customer_identity', jsonb_build_object('source_quote_request_id', quote_id, 'source_intake_id', intake_id, 'customer_id', null, 'legal_name', 'Manifest Customer', 'contact_name', 'Manifest Customer', 'email', scenario || '@example.test', 'address_line_1', 'Teststraat 1', 'address_line_2', null, 'postal_code', '9000', 'city', 'Gent', 'country_code', 'BE', 'enterprise_number', null, 'vat_number', null, 'source_fields', jsonb_build_object('legal_name', 'fixture'), 'snapshot_sha256', repeat('7', 64)),
    'project_scope', jsonb_build_object('project_id', null, 'project_title', 'Manifest fixture', 'project_type', 'website', 'scope_summary', 'Manifest fixture', 'requested_languages', jsonb_build_array('nl'), 'included_page_count', 1, 'features', '[]'::jsonb, 'copywriting', null, 'seo', null, 'hosting', null, 'maintenance', null, 'exclusions', '[]'::jsonb, 'assumptions', '[]'::jsonb, 'indicative_timing', null, 'source_intake_id', intake_id, 'source_pricing_snapshot_id', pricing_id, 'snapshot_sha256', repeat('8', 64)),
    'vat_approval', jsonb_build_object('vat_treatment', 'STANDARD', 'vat_rate', 21, 'vat_decision_source', 'accountant', 'vat_approved_by', 'accountant:test', 'vat_approved_at', '2026-08-15T12:00:00Z'),
    'payment_schedule', jsonb_build_object('schedule_id', 'schedule-1', 'milestones', jsonb_build_array(jsonb_build_object('sequence', 1, 'label', 'Volledige betaling', 'percentage', 100, 'amount_minor', null, 'trigger', 'invoice', 'due_terms_days', 30, 'recurring_cycle', null)), 'approved_by', 'commercial:test', 'approved_at', '2026-08-15T12:00:00Z'),
    'validity', jsonb_build_object('valid_from', '2026-08-15', 'valid_until', '2026-09-14', 'validity_days', 30, 'approved_by', 'commercial:test', 'approved_at', '2026-08-15T12:00:00Z'),
    'legal_references', jsonb_build_object('terms_reference', 'terms-v1', 'terms_version', '1.0.0', 'terms_sha256', repeat('9', 64), 'terms_status', 'APPROVED', 'agreement_template_reference', null, 'agreement_template_version', null, 'agreement_template_sha256', null)
  ) as payload
from manifest_authorities as authority;

insert into public.quote_request_quotation_approval_drafts(
  id, quote_request_id, intake_id, pricing_snapshot_id, contract_version,
  approval_payload, payload_fingerprint, idempotency_key, created_by
)
select draft_id, quote_id, intake_id, pricing_id, 1, payload,
  public.quotation_approval_payload_sha256_v1(payload), gen_random_uuid(), 'test:manifest'
from manifest_payloads;

insert into public.quote_request_quotation_approvals(
  id, draft_id, quote_request_id, intake_id, pricing_snapshot_id,
  contract_version, approval_version, approved_payload, payload_sha256,
  approved_by, approved_at
)
select approval_id, draft_id, quote_id, intake_id, pricing_id, 1, 1, payload,
  public.quotation_approval_payload_sha256_v1(payload), 'test:manifest', clock_timestamp()
from manifest_payloads;

insert into public.quote_request_quotation_approval_integrity(
  approval_id, algorithm_version, key_id, mac
)
select approval_id, 'hmac-sha256-v1', 'v1', repeat('a', 64)
from manifest_authorities;

insert into public.quote_request_quotation_issuances(
  id, quotation_number, quotation_version, status, approval_id, issued_at,
  issued_by, template_id, template_version, template_sha256,
  generation_contract_version, issuance_input_sha256,
  generation_payload_sha256, docx_sha256, docx_bytes,
  prepare_idempotency_key, prepare_fingerprint, commit_idempotency_key,
  commit_fingerprint
)
select issuance_id, quotation_number, 1, 'ISSUED', approval_id, clock_timestamp(),
  'test:manifest', 'LWS_QUOTATION_NL_BE', '1.0.0-technical', repeat('b', 64),
  1, repeat('c', 64), repeat('d', 64), docx_sha256, 12345,
  gen_random_uuid(), repeat('e', 64), gen_random_uuid(), repeat('f', 64)
from manifest_authorities;

insert into storage.objects(bucket_id, name, metadata)
select 'quotation-artifacts',
  'issuances/' || issuance_id || '/docx/' || docx_sha256 || '.docx',
  '{"size":12345,"mimetype":"application/vnd.openxmlformats-officedocument.wordprocessingml.document"}'::jsonb
from manifest_authorities
where scenario = 'accepted';

insert into public.quote_request_quotation_artifacts(
  artifact_id, issuance_id, artifact_type, storage_bucket_id,
  storage_object_path, content_type, sha256, byte_count,
  registration_idempotency_key, registration_fingerprint, created_by
)
select artifact_id, issuance_id, 'DOCX', 'quotation-artifacts',
  'issuances/' || issuance_id || '/docx/' || docx_sha256 || '.docx',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  docx_sha256, 12345, gen_random_uuid(), repeat('1', 64), 'test:manifest'
from manifest_authorities;

create temporary table manifest_acceptance as
select authority.*,
  jsonb_build_object(
    'acceptance_contract_version', 1, 'issuance_id', issuance_id,
    'quotation_number', quotation_number, 'quotation_version', 1,
    'customer_identity_sha256', repeat('7', 64),
    'generation_payload_sha256', repeat('d', 64),
    'template', jsonb_build_object('template_id', 'LWS_QUOTATION_NL_BE', 'template_version', '1.0.0-technical', 'template_sha256', repeat('b', 64)),
    'docx', jsonb_build_object('sha256', docx_sha256, 'bytes', 12345),
    'acceptance_terms', jsonb_build_object('terms_id', 'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT', 'terms_version', '1.0.0-technical', 'terms_sha256', repeat('2', 64)),
    'actor', jsonb_build_object('name', 'Manifest Acceptant', 'email', 'accepted@example.test', 'organization', 'Manifest Customer', 'role', 'Bestuurder'),
    'authority_declaration', true, 'accepted_at', '2026-08-20T12:00:00.000000Z'
  ) as payload
from manifest_authorities as authority where scenario = 'accepted';

insert into public.quote_request_quotation_acceptances(
  id, issuance_id, quotation_number, quotation_version,
  customer_identity_sha256, customer_legal_name, generation_payload_sha256,
  template_id, template_version, template_sha256, docx_sha256, docx_bytes,
  acceptance_contract_version, acceptance_terms_id, acceptance_terms_version,
  acceptance_terms_sha256, accepting_name, accepting_email,
  accepting_organization, accepting_role, authority_declaration,
  acceptance_payload, acceptance_payload_sha256, semantic_request_fingerprint,
  accepted_at, created_at
)
select 'd2170000-0000-4000-8000-000000000001', issuance_id, quotation_number, 1,
  repeat('7', 64), 'Manifest Customer', repeat('d', 64),
  'LWS_QUOTATION_NL_BE', '1.0.0-technical', repeat('b', 64), docx_sha256, 12345,
  1, 'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT', '1.0.0-technical', repeat('2', 64),
  'Manifest Acceptant', 'accepted@example.test', 'Manifest Customer', 'Bestuurder', true,
  payload, public.quotation_acceptance_payload_sha256_v1(payload), repeat('3', 64),
  '2026-08-20T12:00:00Z', '2026-08-20T12:00:00Z'
from manifest_acceptance;

insert into public.commercial_customers(customer_id, acceptance_id, identity_sha256)
values ('d2180000-0000-4000-8000-000000000001', 'd2170000-0000-4000-8000-000000000001', repeat('4', 64));
insert into public.commercial_projects(
  project_id, customer_id, quotation_issuance_id, acceptance_id,
  accepted_total_minor, currency, m1_minor, m2_minor, m3_minor,
  current_state, revision
) values (
  'd2190000-0000-4000-8000-000000000001', 'd2180000-0000-4000-8000-000000000001',
  'd2150000-0000-4000-8000-000000000001', 'd2170000-0000-4000-8000-000000000001',
  10000, 'EUR', 4000, 4000, 2000, 'QUOTE_ACCEPTED', 1
);

select set_config('lws.operator_dossier_assignment_command', 'on', true);
with transition_time as (select clock_timestamp() as value)
update lws_internal.operator_dossier_assignments
set assignee_operator_id = 'd2010000-0000-4000-8000-000000000002',
  assigned_at = transition_time.value, revision = 1, updated_at = transition_time.value
from transition_time
where quote_request_id = 'd2100000-0000-4000-8000-000000000001';
select set_config('lws.operator_dossier_assignment_command', '', true);

insert into public.customer_requests(
  request_id, request_reference, quote_request_id, customer_id, project_id,
  source, request_type, title, description, status, priority,
  submitted_at, submitter_type
) values (
  'd2200000-0000-4000-8000-000000000001', 'LWS-VRZ-2099-0901',
  'd2100000-0000-4000-8000-000000000001', 'd2180000-0000-4000-8000-000000000001',
  'd2190000-0000-4000-8000-000000000001', 'OPERATOR', 'FILE_DELIVERY',
  'Klantbestand', 'Manifest upload fixture.', 'WAITING_CUSTOMER', 'NORMAL',
  clock_timestamp(), 'OPERATOR'
);
insert into public.customer_request_upload_requests(
  upload_request_id, customer_request_id, token_digest, status, expires_at,
  created_by_operator_id, completed_at
) values (
  'd2210000-0000-4000-8000-000000000001', 'd2200000-0000-4000-8000-000000000001',
  repeat('5', 64), 'COMPLETED', clock_timestamp() + interval '1 day',
  'd2010000-0000-4000-8000-000000000001', clock_timestamp()
);
insert into public.customer_request_uploaded_files(
  uploaded_file_id, upload_request_id, customer_request_id, status,
  storage_object_path, original_file_name, file_extension,
  declared_content_type, declared_byte_count, observed_content_type,
  observed_byte_count, sha256, accepted_at
) values (
  'd2220000-0000-4000-8000-000000000001', 'd2210000-0000-4000-8000-000000000001',
  'd2200000-0000-4000-8000-000000000001', 'ACCEPTED',
  'requests/d2200000-0000-4000-8000-000000000001/uploads/d2210000-0000-4000-8000-000000000001/files/d2220000-0000-4000-8000-000000000001.pdf',
  'briefing.pdf', 'pdf', 'application/pdf', 120, 'application/pdf', 120,
  repeat('6', 64), clock_timestamp()
);
insert into storage.objects(bucket_id, name, metadata) values (
  'customer-request-quarantine',
  'requests/d2200000-0000-4000-8000-000000000001/uploads/d2210000-0000-4000-8000-000000000001/files/d2220000-0000-4000-8000-000000000001.pdf',
  '{"size":120,"mimetype":"application/pdf"}'::jsonb
);

create temporary table accepted_manifest as
select * from public.get_operator_dossier_document_manifest_v1(
  'd2000000-0000-4000-8000-000000000001',
  'd2100000-0000-4000-8000-000000000001'
);

select is((select count(*)::integer from accepted_manifest), 3, 'accepted dossier has one quotation, one artifact, and one upload');
select is((select count(*)::integer from accepted_manifest where source_type = 'QUOTATION'), 1, 'quotation produces exactly one manifest row');
select is((select count(*)::integer from accepted_manifest where source_type = 'QUOTATION_ARTIFACT'), 1, 'artifact produces exactly one manifest row');
select is((select count(*)::integer from accepted_manifest where source_type = 'CUSTOMER_UPLOAD'), 1, 'accepted customer upload follows the exact quote_request chain');
select is((select count(*)::integer from accepted_manifest where status = 'ACCEPTED' and accepted_at is not null), 2, 'acceptance enriches quotation and artifact without creating a document');
select is((select count(*)::integer from accepted_manifest where document_id = 'd2170000-0000-4000-8000-000000000001'), 0, 'acceptance is not duplicated as a physical document');
select is((select sha256 from accepted_manifest where source_type = 'QUOTATION_ARTIFACT'), repeat('1', 64), 'artifact hash metadata is projected');
select is((select quote_request_id from accepted_manifest where source_type = 'CUSTOMER_UPLOAD'), 'd2100000-0000-4000-8000-000000000001'::uuid, 'customer upload is bound to the requested dossier');
select ok((select bool_and(can_open and can_download) from accepted_manifest where source_type in ('QUOTATION_ARTIFACT','CUSTOMER_UPLOAD')), 'stored binary rows are openable and downloadable');
select ok((select not can_open and not can_download from accepted_manifest where source_type = 'QUOTATION'), 'quotation metadata has no fake download capability');
select ok((select row_to_json(row_value)::text !~ 'storage_(bucket|object|path)|quotation-artifacts|customer-request-quarantine' from accepted_manifest as row_value limit 1), 'manifest DTO exposes no raw storage locator');
select is((select count(*)::integer from accepted_manifest where source_type not in ('QUOTATION','QUOTATION_ARTIFACT','CUSTOMER_UPLOAD')), 0, 'manifest contains only approved source types');
select ok((select prosrc !~ 'sdf_m1_invoice|intake_upload|commercial_documents|supplier_documents|business_expenses|document_inbox_items' from pg_proc where oid = 'public.get_operator_dossier_document_manifest_v1(uuid,uuid)'::regprocedure), 'excluded authorities are absent from the manifest implementation');

select lives_ok($$select * from public.get_operator_dossier_document_manifest_v1('d2000000-0000-4000-8000-000000000002','d2100000-0000-4000-8000-000000000001')$$, 'assigned ACTIVE operator can read the correct dossier');
select throws_ok($$select * from public.get_operator_dossier_document_manifest_v1('d2000000-0000-4000-8000-000000000002','d2300000-0000-4000-8000-000000000002')$$, '42501', 'DOSSIER_DOCUMENT_READER_REQUIRED', 'assigned operator cannot read another dossier');
select throws_ok($$select * from public.get_operator_dossier_document_manifest_v1('d2000000-0000-4000-8000-000000000003','d2100000-0000-4000-8000-000000000001')$$, '42501', 'OPERATOR_DISABLED', 'inactive operator is blocked');
select throws_ok($$select * from public.get_operator_dossier_document_manifest_v1('d2000000-0000-4000-8000-000000000004','d2100000-0000-4000-8000-000000000001')$$, '42501', 'DOSSIER_DOCUMENT_READER_REQUIRED', 'unauthorized ACTIVE operator is blocked');
select throws_ok($$select * from public.get_operator_dossier_document_manifest_v1(null,'d2100000-0000-4000-8000-000000000001')$$, '42501', 'HUMAN_JWT_REQUIRED', 'missing actor is blocked');

select is(
  public.authorize_operator_dossier_document_download_v1(
    'd2000000-0000-4000-8000-000000000001', 'd2100000-0000-4000-8000-000000000001',
    'QUOTATION_ARTIFACT', 'd2160000-0000-4000-8000-000000000001'
  )->>'storage_bucket_id',
  'quotation-artifacts', 'exact artifact authorization releases its private locator server-side'
);
select is(
  public.authorize_operator_dossier_document_download_v1(
    'd2000000-0000-4000-8000-000000000001', 'd2100000-0000-4000-8000-000000000001',
    'CUSTOMER_UPLOAD', 'd2220000-0000-4000-8000-000000000001'
  )->>'filename',
  'briefing.pdf', 'exact accepted upload authorization succeeds'
);
select throws_ok($$select public.authorize_operator_dossier_document_download_v1('d2000000-0000-4000-8000-000000000001','d2300000-0000-4000-8000-000000000002','QUOTATION_ARTIFACT','d2160000-0000-4000-8000-000000000001')$$, '42501', 'DOSSIER_DOCUMENT_ACCESS_DENIED', 'cross-dossier artifact authorization is blocked');
select throws_ok($$select public.authorize_operator_dossier_document_download_v1('d2000000-0000-4000-8000-000000000001','d2100000-0000-4000-8000-000000000001','QUOTATION_ARTIFACT','d2160000-0000-4000-8000-000000000099')$$, '42501', 'DOSSIER_DOCUMENT_ACCESS_DENIED', 'fabricated document id is blocked');
select throws_ok($$select public.authorize_operator_dossier_document_download_v1('d2000000-0000-4000-8000-000000000001','d2100000-0000-4000-8000-000000000001','INVOICE','d2160000-0000-4000-8000-000000000001')$$, '42501', 'DOSSIER_DOCUMENT_SOURCE_INVALID', 'fabricated source type is blocked');
select throws_ok($$select public.authorize_operator_dossier_document_download_v1('d2000000-0000-4000-8000-000000000001','d2100000-0000-4000-8000-000000000001','QUOTATION','d2150000-0000-4000-8000-000000000001')$$, '42501', 'DOSSIER_DOCUMENT_NOT_DOWNLOADABLE', 'metadata-only quotation cannot be downloaded');

select ok(not (select can_download from public.get_operator_dossier_document_manifest_v1('d2000000-0000-4000-8000-000000000001','d2300000-0000-4000-8000-000000000002') where source_type = 'QUOTATION_ARTIFACT'), 'missing private object disables download capability');
select throws_ok($$select public.authorize_operator_dossier_document_download_v1('d2000000-0000-4000-8000-000000000001','d2300000-0000-4000-8000-000000000002','QUOTATION_ARTIFACT','d2160000-0000-4000-8000-000000000002')$$, '42501', 'DOSSIER_DOCUMENT_ACCESS_DENIED', 'missing private object cannot be authorized');

select * from finish();
rollback;