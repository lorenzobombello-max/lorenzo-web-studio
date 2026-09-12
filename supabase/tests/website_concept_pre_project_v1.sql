begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, lws_internal, extensions;

select no_plan();

create function pg_temp.set_concept_claims_v1(p_subject uuid, p_aal text)
returns void
language sql
as $$
  select set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_subject,
      'role', 'authenticated',
      'aal', p_aal
    )::text,
    true
  )::text;
$$;

create function pg_temp.get_website_work_v1(p_quote_request_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  execute 'select public.get_operator_website_work_v1($1)'
    into v_result
    using p_quote_request_id;
  return v_result;
exception
  when undefined_function then
    return jsonb_build_object('missing_contract', 'get_operator_website_work_v1');
end;
$$;

create function pg_temp.start_website_concept_v1(
  p_quote_request_id uuid,
  p_expected_revision bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  execute 'select public.start_website_concept_v1($1, $2, $3)'
    into v_result
    using p_quote_request_id, p_expected_revision, p_idempotency_key;
  return v_result;
exception
  when undefined_function or undefined_table then
    return jsonb_build_object('missing_contract', 'start_website_concept_v1');
end;
$$;

create function pg_temp.get_website_execution_workspace_v2(p_quote_request_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  execute 'select public.get_website_execution_workspace_v2($1)'
    into v_result
    using p_quote_request_id;
  return v_result;
exception
  when undefined_function or undefined_table then
    return jsonb_build_object('missing_contract', 'get_website_execution_workspace_v2');
end;
$$;

create function pg_temp.feature_row_count_v1(p_relation text, p_quote_request_id uuid)
returns bigint
language plpgsql
as $$
declare
  v_count bigint;
begin
  execute format('select count(*) from %s where quote_request_id = $1', p_relation)
    into v_count
    using p_quote_request_id;
  return v_count;
exception
  when undefined_table or undefined_column then
    return -1;
end;
$$;

insert into auth.users(id, email) values
  ('c1000000-0000-4000-8000-000000000001', 'concept-owner@example.test'),
  ('c1000000-0000-4000-8000-000000000002', 'concept-admin@example.test'),
  ('c1000000-0000-4000-8000-000000000003', 'concept-manager@example.test'),
  ('c1000000-0000-4000-8000-000000000004', 'concept-operator@example.test');

set local session_replication_role = replica;
insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status
) values
  ('c1010000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000001', 'Concept Owner', 'owner', 'ACTIVE'),
  ('c1010000-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000002', 'Concept Admin', 'admin', 'ACTIVE'),
  ('c1010000-0000-4000-8000-000000000003', 'c1000000-0000-4000-8000-000000000003', 'Concept Manager', 'operations_manager', 'ACTIVE'),
  ('c1010000-0000-4000-8000-000000000004', 'c1000000-0000-4000-8000-000000000004', 'Concept Operator', 'operator', 'ACTIVE');
set local session_replication_role = origin;

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind, sdf_package,
  created_at, name, email, website_type, budget, timing, description,
  privacy_consent, status
) values
  ('c1110001-0000-4000-8000-000000000001', 'LWS-AAN-2099-9101', 'production', 'website', null,
   '2099-01-01T09:00:00Z', 'Concept with intake', 'concept-intake@example.test', 'business',
   'Meer dan EUR 6.000', 'flexible', 'Synthetic active Website concept fixture with submitted intake.', true, 'approved'),
  ('c1120002-0000-4000-8000-000000000002', 'LWS-AAN-2099-9102', 'production', 'website', null,
   '2099-01-01T08:00:00Z', 'Concept without intake', 'concept-no-intake@example.test', 'business',
   'Meer dan EUR 6.000', 'flexible', 'Synthetic active Website concept fixture without submitted intake.', true, 'approved'),
  ('c1130003-0000-4000-8000-000000000003', 'LWS-AAN-2099-9103', 'production', 'slimme_documentenflow', 'start',
   '2099-01-01T07:00:00Z', 'Non Website dossier', 'concept-sdf@example.test', null,
   null, null, 'Synthetic non-Website dossier fixture.', true, 'approved'),
  ('c1140004-0000-4000-8000-000000000004', 'LWS-AAN-2099-9104', 'production', 'website', null,
   '2099-01-01T06:00:00Z', 'Trashed Website dossier', 'concept-trash@example.test', 'business',
   'Meer dan EUR 6.000', 'flexible', 'Synthetic trashed Website dossier fixture.', true, 'approved'),
  ('c1150005-0000-4000-8000-000000000005', 'LWS-AAN-2099-9105', 'production', 'website', null,
   '2099-01-01T05:00:00Z', 'Official Website project', 'concept-official@example.test', 'business',
   'Meer dan EUR 6.000', 'flexible', 'Synthetic accepted official Website project fixture.', true, 'approved');

insert into public.quote_request_intakes(
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  started_at, submitted_at, confirmation
) values
  ('c1200000-0000-4000-8000-000000000001', 'c1110001-0000-4000-8000-000000000001',
   'submitted', repeat('1', 64), '2099-01-03T00:00:00Z',
   '2099-01-01T10:00:00Z', '2099-01-01T11:00:00Z', true),
  ('c1200000-0000-4000-8000-000000000005', 'c1150005-0000-4000-8000-000000000005',
   'submitted', repeat('5', 64), '2099-01-03T00:00:00Z',
   '2099-01-01T10:00:00Z', '2099-01-01T11:00:00Z', true);

update lws_internal.operator_dossier_states
set state = 'TRASHED', revision = revision + 1,
    state_before_trash = 'ACTIVE', updated_at = clock_timestamp()
where quote_request_id = 'c1140004-0000-4000-8000-000000000004';

create temporary table official_approval_payload as
select jsonb_build_object(
  'contract_version', 1,
  'source_quote_request_id', 'c1150005-0000-4000-8000-000000000005',
  'source_intake_id', 'c1200000-0000-4000-8000-000000000005',
  'pricing_snapshot', jsonb_build_object(
    'snapshot_id', 'c1300000-0000-4000-8000-000000000005',
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
    'discount_type', null, 'discount_value_minor', 0,
    'discount_reason', null, 'approved_by', null, 'approved_at', null
  ),
  'customer_identity', jsonb_build_object(
    'source_quote_request_id', 'c1150005-0000-4000-8000-000000000005',
    'source_intake_id', 'c1200000-0000-4000-8000-000000000005',
    'customer_id', null, 'legal_name', 'Official Fixture BV',
    'contact_name', 'Official Website project', 'email', 'concept-official@example.test',
    'address_line_1', 'Teststraat 1', 'address_line_2', null,
    'postal_code', '9000', 'city', 'Gent', 'country_code', 'BE',
    'enterprise_number', null, 'vat_number', null,
    'source_fields', jsonb_build_object('legal_name', 'fixture'),
    'snapshot_sha256', repeat('b', 64)
  ),
  'project_scope', jsonb_build_object(
    'project_id', null, 'project_title', 'Official Website fixture',
    'project_type', 'website', 'scope_summary', 'Accepted official Website scope',
    'requested_languages', jsonb_build_array('nl'), 'included_page_count', 1,
    'features', jsonb_build_array('contact_form'), 'copywriting', null,
    'seo', null, 'hosting', null, 'maintenance', null,
    'exclusions', '[]'::jsonb, 'assumptions', '[]'::jsonb, 'indicative_timing', null,
    'source_intake_id', 'c1200000-0000-4000-8000-000000000005',
    'source_pricing_snapshot_id', 'c1300000-0000-4000-8000-000000000005',
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
) as payload;

insert into public.quote_request_pricing_snapshots(
  id, intake_id, snapshot_contract_version, config_version, config_hash,
  normalized_evidence, calculation, package_advice, budget_evaluation
) values (
  'c1300000-0000-4000-8000-000000000005',
  'c1200000-0000-4000-8000-000000000005', 2, '1.0.0', repeat('1', 64),
  '{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}',
  '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":10000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":10000,"quantity":1,"knownMinimumContributionMinor":10000}]}',
  '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}',
  '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}'
);
insert into public.quote_request_pricing_snapshot_integrity(
  snapshot_id, algorithm_version, key_id, mac
) values (
  'c1300000-0000-4000-8000-000000000005', 'hmac-sha256-v1', 'v1', repeat('a', 64)
);
insert into public.quote_request_quotation_approval_drafts(
  id, quote_request_id, intake_id, pricing_snapshot_id, contract_version,
  approval_payload, payload_fingerprint, idempotency_key, created_by
)
select
  'c1400000-0000-4000-8000-000000000005',
  'c1150005-0000-4000-8000-000000000005',
  'c1200000-0000-4000-8000-000000000005',
  'c1300000-0000-4000-8000-000000000005', 1, payload,
  public.quotation_approval_payload_sha256_v1(payload),
  'c1400000-0000-4000-8000-000000000006', 'test:website-concept'
from official_approval_payload;
insert into public.quote_request_quotation_approvals(
  id, draft_id, quote_request_id, intake_id, pricing_snapshot_id,
  contract_version, approval_version, approved_payload, payload_sha256,
  approved_by, approved_at
)
select
  'c1500000-0000-4000-8000-000000000005',
  'c1400000-0000-4000-8000-000000000005',
  'c1150005-0000-4000-8000-000000000005',
  'c1200000-0000-4000-8000-000000000005',
  'c1300000-0000-4000-8000-000000000005', 1, 1, payload,
  public.quotation_approval_payload_sha256_v1(payload),
  'test:website-concept', clock_timestamp()
from official_approval_payload;
insert into public.quote_request_quotation_approval_integrity(
  approval_id, algorithm_version, key_id, mac
) values (
  'c1500000-0000-4000-8000-000000000005', 'hmac-sha256-v1', 'v1', repeat('e', 64)
);
insert into public.quote_request_quotation_issuances(
  id, quotation_number, quotation_version, status, approval_id,
  issued_at, issued_by, template_id, template_version, template_sha256,
  generation_contract_version, issuance_input_sha256, generation_payload_sha256,
  docx_sha256, docx_bytes, prepare_idempotency_key, prepare_fingerprint,
  commit_idempotency_key, commit_fingerprint
) values (
  'c1600000-0000-4000-8000-000000000005', 'LWS-OFF-2099-9105', 1, 'ISSUED',
  'c1500000-0000-4000-8000-000000000005', clock_timestamp(), 'test:website-concept',
  'LWS_QUOTATION_NL_BE', '1.0.0-technical', repeat('3', 64), 1,
  repeat('4', 64), repeat('5', 64), repeat('6', 64), 12345,
  'c1600000-0000-4000-8000-000000000006', repeat('7', 64),
  'c1600000-0000-4000-8000-000000000007', repeat('8', 64)
);

create temporary table official_acceptance_payload as
select jsonb_build_object(
  'acceptance_contract_version', 1,
  'issuance_id', 'c1600000-0000-4000-8000-000000000005',
  'quotation_number', 'LWS-OFF-2099-9105', 'quotation_version', 1,
  'customer_identity_sha256', repeat('b', 64),
  'generation_payload_sha256', repeat('5', 64),
  'template', jsonb_build_object(
    'template_id', 'LWS_QUOTATION_NL_BE',
    'template_version', '1.0.0-technical', 'template_sha256', repeat('3', 64)
  ),
  'docx', jsonb_build_object('sha256', repeat('6', 64), 'bytes', 12345),
  'acceptance_terms', jsonb_build_object(
    'terms_id', 'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT',
    'terms_version', '1.0.0-technical', 'terms_sha256', repeat('9', 64)
  ),
  'actor', jsonb_build_object(
    'name', 'Official Acceptant', 'email', 'concept-official@example.test',
    'organization', 'Official Fixture BV', 'role', 'Bestuurder'
  ),
  'authority_declaration', true,
  'accepted_at', '2026-08-20T12:00:00.000000Z'
) as payload;

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
select
  'c1700000-0000-4000-8000-000000000005',
  'c1600000-0000-4000-8000-000000000005', 'LWS-OFF-2099-9105', 1,
  repeat('b', 64), 'Official Fixture BV', repeat('5', 64),
  'LWS_QUOTATION_NL_BE', '1.0.0-technical', repeat('3', 64),
  repeat('6', 64), 12345, 1,
  'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT', '1.0.0-technical', repeat('9', 64),
  'Official Acceptant', 'concept-official@example.test', 'Official Fixture BV',
  'Bestuurder', true, payload,
  public.quotation_acceptance_payload_sha256_v1(payload), repeat('f', 64),
  '2026-08-20T12:00:00Z', '2026-08-20T12:00:00Z'
from official_acceptance_payload;

insert into public.commercial_customers(customer_id, acceptance_id, identity_sha256)
values (
  'c1800000-0000-4000-8000-000000000005',
  'c1700000-0000-4000-8000-000000000005', repeat('a', 64)
);
insert into public.commercial_projects(
  project_id, customer_id, quotation_issuance_id, acceptance_id,
  accepted_total_minor, currency, m1_minor, m2_minor, m3_minor,
  current_state, revision
) values (
  'c1900000-0000-4000-8000-000000000005',
  'c1800000-0000-4000-8000-000000000005',
  'c1600000-0000-4000-8000-000000000005',
  'c1700000-0000-4000-8000-000000000005',
  10000, 'EUR', 4000, 4000, 2000, 'QUOTE_ACCEPTED', 1
);
insert into public.website_execution_workspaces(
  website_workspace_id, project_id, quote_request_id,
  repository_owner, repository_name, last_commit_sha, last_commit_at,
  last_build_result, last_build_at, created_by
) values (
  'c1910000-0000-4000-8000-000000000005',
  'c1900000-0000-4000-8000-000000000005',
  'c1150005-0000-4000-8000-000000000005',
  'lorenzo-test', 'concept-official-fixture', repeat('a', 40), clock_timestamp(),
  'PASS', clock_timestamp(), 'c1010000-0000-4000-8000-000000000001'
);
insert into public.audit_events(project_id, event_type, actor, command_id, metadata)
values (
  'c1900000-0000-4000-8000-000000000005', 'PROJECT_WORK_STARTED',
  'OPERATOR:c1010000-0000-4000-8000-000000000001',
  'c1920000-0000-4000-8000-000000000005',
  '{"quote_request_id":"c1150005-0000-4000-8000-000000000005"}'::jsonb
);

create temporary table commercial_preservation_before as
select
  (select count(*) from public.quote_request_quotation_approvals) as quotation_approvals,
  (select count(*) from public.quote_request_quotation_issuances) as quotation_issuances,
  (select count(*) from public.quote_request_quotation_acceptances) as quotation_acceptances,
  (select count(*) from public.commercial_customers) as commercial_customers,
  (select count(*) from public.commercial_projects) as commercial_projects,
  (select count(*) from public.commercial_obligations) as commercial_obligations,
  (select count(*) from public.payment_expectations) as payment_expectations,
  (select count(*) from public.payment_evidence) as payment_evidence,
  (select count(*) from public.payment_reconciliations) as payment_reconciliations,
  (select count(*) from public.quote_request_email_jobs) as email_jobs,
  (select count(*) from public.preview_access) as preview_access,
  (select count(*) from public.commercial_project_sites) as project_sites,
  (select count(*) from public.audit_events where event_type in (
    'PROJECT_WORK_STARTED', 'PROJECT_RELEASED', 'PREVIEW_READY', 'CUSTOMER_APPROVED'
  )) as project_publication_events;

select pg_temp.set_concept_claims_v1(
  'c1000000-0000-4000-8000-000000000001', 'aal1'
);
select ok(
  current_setting('request.jwt.claims', true)::jsonb->>'aal' = 'aal1',
  'owner AAL1 JWT fixture is available'
);

select pg_temp.set_concept_claims_v1(
  'c1000000-0000-4000-8000-000000000001', 'aal2'
);
select ok(
  current_setting('request.jwt.claims', true)::jsonb->>'aal' = 'aal2',
  'owner AAL2 JWT fixture is available'
);
select is(
  (select count(*) from public.commercial_operators
   where status = 'ACTIVE'
     and role in ('owner', 'admin', 'operations_manager', 'operator')
     and auth_user_id in (
       'c1000000-0000-4000-8000-000000000001',
       'c1000000-0000-4000-8000-000000000002',
       'c1000000-0000-4000-8000-000000000003',
       'c1000000-0000-4000-8000-000000000004'
     )),
  4::bigint,
  'active owner, admin, operations manager, and operator identities exist'
);
select is(
  (select state from lws_internal.operator_dossier_states
  where quote_request_id = 'c1110001-0000-4000-8000-000000000001'),
  'ACTIVE',
  'production Website dossier with submitted intake is active'
);
select is(
  (select count(*) from public.quote_request_intakes
  where quote_request_id = 'c1120002-0000-4000-8000-000000000002'
     and status in ('submitted', 'reviewed')),
  0::bigint,
  'production Website dossier without submitted intake has no submitted intake'
);
select is(
  (select request_kind from public.quote_requests
  where id = 'c1130003-0000-4000-8000-000000000003'),
  'slimme_documentenflow',
  'non-Website dossier fixture remains non-Website'
);
select is(
  (select state from lws_internal.operator_dossier_states
  where quote_request_id = 'c1140004-0000-4000-8000-000000000004'),
  'TRASHED',
  'trashed production Website dossier fixture is trashed'
);

select has_table('public', 'website_concepts', 'Website concept authority exists');
select has_table('public', 'website_work_contexts', 'Website work-context authority exists');
select has_function(
  'public', 'get_operator_website_work_v1', array['uuid'],
  'Website work projection exists'
);
select has_function(
  'public', 'start_website_concept_v1', array['uuid', 'bigint', 'uuid'],
  'Website concept start command exists'
);
select has_function(
  'public', 'get_website_execution_workspace_v2', array['uuid'],
  'Website Execution V2 read exists'
);

select ok(
  pg_temp.get_website_work_v1('c1110001-0000-4000-8000-000000000001')
    ->'permitted_actions' ? 'CAN_START_WEBSITE_CONCEPT',
  'eligible AAL2 owner projection contains CAN_START_WEBSITE_CONCEPT'
);
select ok(
  public.get_operator_application_v1(
    'c1110001-0000-4000-8000-000000000001', null
  )->'website_work'->'permitted_actions' ? 'CAN_START_WEBSITE_CONCEPT',
  'eligible dossier detail contains CAN_START_WEBSITE_CONCEPT'
);

create temporary table concept_start_result as
select pg_temp.start_website_concept_v1(
  'c1110001-0000-4000-8000-000000000001', 1,
  'c1a00000-0000-4000-8000-000000000001'
) as result;

select is(
  (select result->>'state' from concept_start_result),
  'PRE_PROJECT',
  'start returns PRE_PROJECT'
);
select is(
  pg_temp.feature_row_count_v1(
    'public.website_concepts', 'c1110001-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'start creates exactly one Website concept'
);
select is(
  pg_temp.feature_row_count_v1(
    'public.website_work_contexts', 'c1110001-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'start creates exactly one Website work context'
);
select ok(
  public.get_operator_application_v1(
    'c1110001-0000-4000-8000-000000000001', null
  )->'website_work'->'permitted_actions' ? 'OPEN_WEBSITE',
  'started dossier detail contains OPEN_WEBSITE'
);
select is(
  pg_temp.get_website_execution_workspace_v2(
    'c1110001-0000-4000-8000-000000000001'
  )->>'project_id',
  null,
  'PRE_PROJECT Website workspace has no project id'
);
select is(
  pg_temp.get_website_execution_workspace_v2(
    'c1110001-0000-4000-8000-000000000001'
  )->'workspace',
  'null'::jsonb,
  'PRE_PROJECT Website workspace succeeds with no linked workspace'
);

select is(
  (select jsonb_build_array(
    after.quotation_approvals - before.quotation_approvals,
    after.quotation_issuances - before.quotation_issuances,
    after.quotation_acceptances - before.quotation_acceptances,
    after.commercial_customers - before.commercial_customers,
    after.commercial_projects - before.commercial_projects,
    after.commercial_obligations - before.commercial_obligations,
    after.payment_expectations - before.payment_expectations,
    after.payment_evidence - before.payment_evidence,
    after.payment_reconciliations - before.payment_reconciliations,
    after.email_jobs - before.email_jobs,
    after.preview_access - before.preview_access,
    after.project_sites - before.project_sites,
    after.project_publication_events - before.project_publication_events
  )
  from commercial_preservation_before as before
  cross join lateral (
    select
      (select count(*) from public.quote_request_quotation_approvals) as quotation_approvals,
      (select count(*) from public.quote_request_quotation_issuances) as quotation_issuances,
      (select count(*) from public.quote_request_quotation_acceptances) as quotation_acceptances,
      (select count(*) from public.commercial_customers) as commercial_customers,
      (select count(*) from public.commercial_projects) as commercial_projects,
      (select count(*) from public.commercial_obligations) as commercial_obligations,
      (select count(*) from public.payment_expectations) as payment_expectations,
      (select count(*) from public.payment_evidence) as payment_evidence,
      (select count(*) from public.payment_reconciliations) as payment_reconciliations,
      (select count(*) from public.quote_request_email_jobs) as email_jobs,
      (select count(*) from public.preview_access) as preview_access,
      (select count(*) from public.commercial_project_sites) as project_sites,
      (select count(*) from public.audit_events where event_type in (
        'PROJECT_WORK_STARTED', 'PROJECT_RELEASED', 'PREVIEW_READY', 'CUSTOMER_APPROVED'
      )) as project_publication_events
  ) as after),
  '[0,0,0,0,0,0,0,0,0,0,0,0,0]'::jsonb,
  'concept start preserves quotation, commercial, payment, email, preview, and publication authorities'
);

select is(
  pg_temp.get_website_work_v1(
    'c1150005-0000-4000-8000-000000000005'
  )->>'state',
  'OFFICIAL_PROJECT',
  'existing accepted Website fixture remains OFFICIAL_PROJECT'
);
select lives_ok(
  $$select public.get_website_execution_workspace_v1(
    'c1150005-0000-4000-8000-000000000005',
    'c1900000-0000-4000-8000-000000000005'
  )$$,
  'existing official project still reads its Website workspace'
);
select is(
  public.get_website_execution_workspace_v1(
    'c1150005-0000-4000-8000-000000000005',
    'c1900000-0000-4000-8000-000000000005'
  )->'workspace'->>'website_workspace_id',
  'c1910000-0000-4000-8000-000000000005',
  'official Website workspace preserves its project-bound technical binding'
);
select lives_ok(
  $$select public.get_project_requirements_board_v1(
    'c1150005-0000-4000-8000-000000000005',
    'c1900000-0000-4000-8000-000000000005'
  )$$,
  'existing official project still reads its project-bound Requirements projection'
);
select is(
  public.get_project_requirements_board_v1(
    'c1150005-0000-4000-8000-000000000005',
    'c1900000-0000-4000-8000-000000000005'
  )->>'empty_state',
  'NO_BOARD',
  'official project Requirements remains an honest project-bound empty state'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.project_requirements_boards'::regclass
      and contype = 'f'
      and confrelid = 'public.commercial_projects'::regclass
  )
  and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name in ('project_requirements_boards', 'project_requirements')
      and column_name in ('concept_id', 'website_work_context_id')
  ),
  'Requirements roots remain project-bound and are not polymorphic'
);

select * from finish();
rollback;