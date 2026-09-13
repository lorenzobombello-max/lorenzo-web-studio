begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
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
    'Meer dan EUR 6.000', 'flexible', 'Synthetic accepted official Website project fixture.', true, 'approved'),
    ('c1160006-0000-4000-8000-000000000006', 'LWS-AAN-2099-9106', 'production', 'website', null,
    '2099-01-01T04:00:00Z', 'Concept rollback target', 'concept-rollback@example.test', 'business',
    'Meer dan EUR 6.000', 'flexible', 'Synthetic Website concept rollback fixture.', true, 'approved');

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
select set_config('lws.website_concept_command', 'on', true);
insert into public.website_work_contexts(
  website_work_context_id, quote_request_id, concept_id, project_id, phase, revision
) values (
  'c1c00000-0000-4000-8000-000000000005',
  'c1150005-0000-4000-8000-000000000005', null,
  'c1900000-0000-4000-8000-000000000005', 'OFFICIAL_PROJECT', 1
);
select set_config('lws.website_concept_command', '', true);
insert into public.website_execution_workspaces(
  website_workspace_id, website_work_context_id, project_id, quote_request_id,
  repository_owner, repository_name, last_commit_sha, last_commit_at,
  last_build_result, last_build_at, created_by
) values (
  'c1910000-0000-4000-8000-000000000005',
  'c1c00000-0000-4000-8000-000000000005',
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
select has_table('public', 'website_concept_events', 'Website concept event authority exists');
select has_table('public', 'website_concept_idempotency_ledger', 'Website concept idempotency authority exists');

select columns_are(
  'public', 'website_concepts',
  array[
    'concept_id','quote_request_id','mode','briefing_status',
    'commercially_released','concept_status','promoted_project_id','revision',
    'created_by','created_at','updated_at','promoted_at'
  ],
  'Website concept stores only the contracted authority fields'
);
select columns_are(
  'public', 'website_work_contexts',
  array[
    'website_work_context_id','quote_request_id','concept_id','project_id',
    'phase','revision','created_at','updated_at'
  ],
  'Website work context stores one lifecycle-neutral technical identity'
);
select columns_are(
  'public', 'website_concept_events',
  array[
    'event_id','concept_id','website_work_context_id','quote_request_id',
    'event_type','actor_id','actor_role','command_id','metadata','occurred_at'
  ],
  'Website concept event stores the complete safe audit binding'
);
select columns_are(
  'public', 'website_concept_idempotency_ledger',
  array[
    'operation_id','actor_id','quote_request_id','command_type',
    'idempotency_key','request_fingerprint','result_reference',
    'result_payload','created_at'
  ],
  'Website concept idempotency ledger stores fingerprint and complete result snapshot'
);

select is(
  (select jsonb_object_agg(column_name, data_type)
   from information_schema.columns
   where table_schema = 'public' and table_name = 'website_concepts'),
  '{"concept_id":"uuid","quote_request_id":"uuid","mode":"text","briefing_status":"text","commercially_released":"boolean","concept_status":"text","promoted_project_id":"uuid","revision":"bigint","created_by":"uuid","created_at":"timestamp with time zone","updated_at":"timestamp with time zone","promoted_at":"timestamp with time zone"}'::jsonb,
  'every Website concept column has its contracted type'
);
select is(
  (select jsonb_object_agg(column_name, data_type)
   from information_schema.columns
   where table_schema = 'public' and table_name = 'website_work_contexts'),
  '{"website_work_context_id":"uuid","quote_request_id":"uuid","concept_id":"uuid","project_id":"uuid","phase":"text","revision":"bigint","created_at":"timestamp with time zone","updated_at":"timestamp with time zone"}'::jsonb,
  'every Website work-context column has its contracted type'
);
select is(
  (select jsonb_object_agg(column_name, data_type)
   from information_schema.columns
   where table_schema = 'public' and table_name = 'website_concept_events'),
  '{"event_id":"uuid","concept_id":"uuid","website_work_context_id":"uuid","quote_request_id":"uuid","event_type":"text","actor_id":"uuid","actor_role":"text","command_id":"uuid","metadata":"jsonb","occurred_at":"timestamp with time zone"}'::jsonb,
  'every Website concept event column has its contracted type'
);
select is(
  (select jsonb_object_agg(column_name, data_type)
   from information_schema.columns
   where table_schema = 'public' and table_name = 'website_concept_idempotency_ledger'),
  '{"operation_id":"uuid","actor_id":"uuid","quote_request_id":"uuid","command_type":"text","idempotency_key":"uuid","request_fingerprint":"character","result_reference":"text","result_payload":"jsonb","created_at":"timestamp with time zone"}'::jsonb,
  'every Website concept idempotency column has its contracted type'
);
select is(
  (select array_agg(column_name::text order by ordinal_position)
   from information_schema.columns
   where table_schema = 'public' and table_name = 'website_concepts'
     and is_nullable = 'NO'),
  array[
    'concept_id','quote_request_id','mode','briefing_status',
    'commercially_released','concept_status','revision','created_by',
    'created_at','updated_at'
  ],
  'only future promotion fields are nullable on Website concepts'
);
select is(
  (select array_agg(column_name::text order by ordinal_position)
   from information_schema.columns
   where table_schema = 'public' and table_name = 'website_work_contexts'
     and is_nullable = 'NO'),
  array[
    'website_work_context_id','quote_request_id','phase','revision',
    'created_at','updated_at'
  ],
  'only concept and project alternatives are nullable on work contexts'
);
select is(
  (select count(*)
   from information_schema.columns
   where table_schema = 'public'
     and table_name in ('website_concept_events','website_concept_idempotency_ledger')
     and is_nullable = 'NO'),
  19::bigint,
  'event and idempotency snapshots have no nullable fields'
);

select col_type_is('public', 'website_concepts', 'concept_id', 'uuid', 'concept identity is uuid');
select col_type_is('public', 'website_concepts', 'quote_request_id', 'uuid', 'concept dossier binding is uuid');
select col_type_is('public', 'website_concepts', 'revision', 'bigint', 'concept revision is bigint');
select col_type_is('public', 'website_concepts', 'created_at', 'timestamp with time zone', 'concept creation is timestamptz');
select col_type_is('public', 'website_concepts', 'updated_at', 'timestamp with time zone', 'concept update is timestamptz');
select col_type_is('public', 'website_concepts', 'promoted_at', 'timestamp with time zone', 'concept promotion time is timestamptz');
select col_type_is('public', 'website_work_contexts', 'website_work_context_id', 'uuid', 'work-context identity is uuid');
select col_type_is('public', 'website_work_contexts', 'revision', 'bigint', 'work-context revision is bigint');
select col_type_is('public', 'website_concept_events', 'metadata', 'jsonb', 'event metadata is jsonb');
select col_type_is('public', 'website_concept_events', 'occurred_at', 'timestamp with time zone', 'event time is timestamptz');
select col_type_is('public', 'website_concept_idempotency_ledger', 'request_fingerprint', 'character(64)', 'request fingerprint is fixed lowercase SHA-256');
select col_type_is('public', 'website_concept_idempotency_ledger', 'result_payload', 'jsonb', 'result snapshot is jsonb');

select col_is_pk('public', 'website_concepts', 'concept_id', 'concept identity is primary');
select col_is_pk('public', 'website_work_contexts', 'website_work_context_id', 'work-context identity is primary');
select col_is_pk('public', 'website_concept_events', 'event_id', 'event identity is primary');
select col_is_pk('public', 'website_concept_idempotency_ledger', 'operation_id', 'operation identity is primary');
select col_has_default('public', 'website_concepts', 'concept_id', 'concept identity is server generated');
select col_has_default('public', 'website_concepts', 'commercially_released', 'commercial release defaults server-side');
select col_has_default('public', 'website_concepts', 'revision', 'concept revision defaults server-side');
select col_has_default('public', 'website_concepts', 'created_at', 'concept creation time is server generated');
select col_has_default('public', 'website_concepts', 'updated_at', 'concept update time is server generated');
select col_has_default('public', 'website_work_contexts', 'website_work_context_id', 'work-context identity is server generated');
select col_has_default('public', 'website_work_contexts', 'revision', 'work-context revision defaults server-side');
select col_has_default('public', 'website_concept_events', 'event_id', 'event identity is server generated');
select col_has_default('public', 'website_concept_events', 'metadata', 'event metadata defaults server-side');
select col_has_default('public', 'website_concept_events', 'occurred_at', 'event time is server generated');
select col_has_default('public', 'website_concept_idempotency_ledger', 'operation_id', 'operation identity is server generated');
select col_has_default('public', 'website_concept_idempotency_ledger', 'created_at', 'ledger time is server generated');

select is(
  (select count(*)
   from pg_constraint
   where contype = 'u'
     and conrelid in (
       to_regclass('public.website_concepts'),
       to_regclass('public.website_work_contexts'),
       to_regclass('public.website_concept_idempotency_ledger')
     )
     and pg_get_constraintdef(oid) in (
       'UNIQUE (quote_request_id)',
       'UNIQUE (promoted_project_id)',
       'UNIQUE (concept_id)',
       'UNIQUE (project_id)',
       'UNIQUE (actor_id, command_type, idempotency_key)',
       'UNIQUE (quote_request_id, command_type)'
     )),
  7::bigint,
  'concept, context, and idempotency unique bindings are complete'
);

select ok(
  (select count(*) = 12
   from pg_constraint as constraint_row
   where constraint_row.contype = 'f'
     and constraint_row.conrelid in (
       to_regclass('public.website_concepts'),
       to_regclass('public.website_work_contexts'),
       to_regclass('public.website_concept_events'),
       to_regclass('public.website_concept_idempotency_ledger')
     )
     and constraint_row.confrelid in (
       'public.quote_requests'::regclass,
       'public.commercial_projects'::regclass,
       'public.commercial_operators'::regclass,
       to_regclass('public.website_concepts'),
       to_regclass('public.website_work_contexts')
     )),
  'all twelve concept-root foreign keys are present'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = to_regclass('public.website_work_contexts')
      and contype = 'f'
      and condeferrable
      and condeferred
  ),
  'work-context concept binding can be validated atomically'
);
select ok(
  (select bool_and(relrowsecurity and relforcerowsecurity)
   from pg_class
   where oid in (
     to_regclass('public.website_concepts'),
     to_regclass('public.website_work_contexts'),
     to_regclass('public.website_concept_events'),
     to_regclass('public.website_concept_idempotency_ledger')
   )),
  'all four concept roots have forced RLS'
);
select ok(
  not exists (
    select 1
    from information_schema.table_privileges
    where table_schema = 'public'
      and table_name in (
        'website_concepts','website_work_contexts',
        'website_concept_events','website_concept_idempotency_ledger'
      )
      and grantee in ('PUBLIC','anon','authenticated','service_role')
  ),
  'public, anon, authenticated, and service_role have no direct concept-root privileges'
);

select set_config('lws.website_concept_command', 'on', true);
select throws_ok(
  $$insert into public.website_concepts(
      quote_request_id, mode, briefing_status, concept_status, revision, created_by
    ) values (
      'c1120002-0000-4000-8000-000000000002', 'OFFICIAL_PROJECT', 'LIMITED',
      'ACTIVE', 1, 'c1010000-0000-4000-8000-000000000001'
    )$$,
  '23514', null,
  'concept mode is fixed to PRE_PROJECT'
);
select throws_ok(
  $$insert into public.website_concepts(
      quote_request_id, mode, briefing_status, commercially_released,
      concept_status, revision, created_by
    ) values (
      'c1120002-0000-4000-8000-000000000002', 'PRE_PROJECT', 'LIMITED', true,
      'ACTIVE', 1, 'c1010000-0000-4000-8000-000000000001'
    )$$,
  '23514', null,
  'concept commercial release is fixed false'
);
select throws_ok(
  $$insert into public.website_concepts(
      quote_request_id, mode, briefing_status, concept_status, revision, created_by
    ) values (
      'c1120002-0000-4000-8000-000000000002', 'PRE_PROJECT', 'LIMITED',
      'ACTIVE', 0, 'c1010000-0000-4000-8000-000000000001'
    )$$,
  '23514', null,
  'concept revision must be positive'
);
select throws_ok(
  $$insert into public.website_concepts(
      quote_request_id, mode, briefing_status, concept_status, revision, created_by
    ) values (
      'c1120002-0000-4000-8000-000000000002', 'PRE_PROJECT', 'LIMITED',
      'PROMOTED', 1, 'c1010000-0000-4000-8000-000000000001'
    )$$,
  '23514', null,
  'PROMOTED concept requires project and promotion timestamp'
);
select throws_ok(
  $$insert into public.website_concepts(
      quote_request_id, mode, briefing_status, concept_status, revision, created_by,
      created_at, updated_at
    ) values (
      'c1120002-0000-4000-8000-000000000002', 'PRE_PROJECT', 'LIMITED',
      'ACTIVE', 1, 'c1010000-0000-4000-8000-000000000001',
      '2099-01-02T00:00:00Z', '2099-01-01T00:00:00Z'
    )$$,
  '23514', null,
  'concept timestamps cannot move before creation'
);
select throws_ok(
  $$insert into public.website_work_contexts(
      quote_request_id, concept_id, project_id, phase, revision
    ) values (
      'c1120002-0000-4000-8000-000000000002', null, null, 'PRE_PROJECT', 1
    )$$,
  '23514', null,
  'PRE_PROJECT context requires a concept and forbids a project'
);
select throws_ok(
  $$insert into public.website_work_contexts(
      quote_request_id, concept_id, project_id, phase, revision
    ) values (
      'c1120002-0000-4000-8000-000000000002', null,
      'c1900000-0000-4000-8000-000000000005', 'OFFICIAL_PROJECT', 0
    )$$,
  '23514', null,
  'work-context revision must be positive'
);
insert into public.website_concepts(
  concept_id, quote_request_id, mode, briefing_status, concept_status,
  revision, created_by
) values (
  'c1b00000-0000-4000-8000-000000000001',
  'c1110001-0000-4000-8000-000000000001',
  'PRE_PROJECT', 'COMPLETE', 'ACTIVE', 1,
  'c1010000-0000-4000-8000-000000000001'
);
insert into public.website_work_contexts(
  website_work_context_id, quote_request_id, concept_id, project_id, phase, revision
) values (
  'c1c00000-0000-4000-8000-000000000001',
  'c1110001-0000-4000-8000-000000000001',
  'c1b00000-0000-4000-8000-000000000001', null, 'PRE_PROJECT', 1
);
insert into public.website_concept_events(
  event_id, concept_id, website_work_context_id, quote_request_id, event_type,
  actor_id, actor_role, command_id, metadata
) values (
  'c1d00000-0000-4000-8000-000000000001',
  'c1b00000-0000-4000-8000-000000000001',
  'c1c00000-0000-4000-8000-000000000001',
  'c1110001-0000-4000-8000-000000000001',
  'WEBSITE_CONCEPT_STARTED', 'c1010000-0000-4000-8000-000000000001',
  'owner', 'c1a00000-0000-4000-8000-000000000011',
  jsonb_build_object('briefing_status', 'COMPLETE')
);
insert into public.website_concept_idempotency_ledger(
  operation_id, actor_id, quote_request_id, command_type, idempotency_key,
  request_fingerprint, result_reference, result_payload
) values (
  'c1e00000-0000-4000-8000-000000000001',
  'c1010000-0000-4000-8000-000000000001',
  'c1110001-0000-4000-8000-000000000001',
  'START_WEBSITE_CONCEPT', 'c1a00000-0000-4000-8000-000000000011',
  repeat('a', 64), 'c1b00000-0000-4000-8000-000000000001',
  jsonb_build_object(
    'state', 'PRE_PROJECT',
    'quote_request_id', 'c1110001-0000-4000-8000-000000000001',
    'concept_id', 'c1b00000-0000-4000-8000-000000000001',
    'project_id', null,
    'website_work_context_id', 'c1c00000-0000-4000-8000-000000000001',
    'mode', 'PRE_PROJECT',
    'briefing_status', 'COMPLETE',
    'commercially_released', false,
    'revision', 1,
    'permitted_actions', jsonb_build_array('OPEN_WEBSITE')
  )
);
set constraints all immediate;
set constraints all deferred;
select set_config('lws.website_concept_command', '', true);

create function pg_temp.insert_mismatched_website_context_v1()
returns void
language plpgsql
as $$
begin
  insert into public.website_concepts(
    concept_id, quote_request_id, mode, briefing_status, concept_status,
    revision, created_by
  ) values (
    'c1b00000-0000-4000-8000-000000000002',
    'c1120002-0000-4000-8000-000000000002',
    'PRE_PROJECT', 'LIMITED', 'ACTIVE', 1,
    'c1010000-0000-4000-8000-000000000001'
  );
  insert into public.website_work_contexts(
    quote_request_id, concept_id, project_id, phase, revision
  ) values (
    'c1140004-0000-4000-8000-000000000004',
    'c1b00000-0000-4000-8000-000000000002', null, 'PRE_PROJECT', 1
  );
  set constraints all immediate;
end;
$$;

create function pg_temp.insert_non_website_concept_v1()
returns void
language plpgsql
as $$
begin
  insert into public.website_concepts(
    quote_request_id, mode, briefing_status, concept_status, revision, created_by
  ) values (
    'c1130003-0000-4000-8000-000000000003', 'PRE_PROJECT', 'LIMITED',
    'ACTIVE', 1, 'c1010000-0000-4000-8000-000000000001'
  );
  set constraints all immediate;
end;
$$;

select throws_ok(
  $$insert into public.website_concepts(
      quote_request_id, mode, briefing_status, concept_status, revision, created_by
    ) values (
      'c1120002-0000-4000-8000-000000000002', 'PRE_PROJECT', 'LIMITED',
      'ACTIVE', 1, 'c1010000-0000-4000-8000-000000000001'
    )$$,
  '55000', 'DIRECT_WEBSITE_CONCEPT_WRITE_FORBIDDEN',
  'direct concept insert is denied outside the command boundary'
);
select throws_ok(
  $$update public.website_work_contexts set revision = revision + 1
    where website_work_context_id = 'c1c00000-0000-4000-8000-000000000001'$$,
  '55000', 'DIRECT_WEBSITE_CONCEPT_WRITE_FORBIDDEN',
  'direct work-context update is denied outside the command boundary'
);
select throws_ok(
  $$update public.website_concept_events set metadata = metadata
    where event_id = 'c1d00000-0000-4000-8000-000000000001'$$,
  '55000', 'WEBSITE_CONCEPT_EVENT_IMMUTABLE',
  'Website concept events cannot be updated'
);
select throws_ok(
  $$delete from public.website_concept_events
    where event_id = 'c1d00000-0000-4000-8000-000000000001'$$,
  '55000', 'WEBSITE_CONCEPT_EVENT_IMMUTABLE',
  'Website concept events cannot be deleted'
);
select throws_ok(
  $$update public.website_concept_idempotency_ledger
    set result_payload = result_payload
    where operation_id = 'c1e00000-0000-4000-8000-000000000001'$$,
  '55000', 'WEBSITE_CONCEPT_IDEMPOTENCY_IMMUTABLE',
  'Website concept idempotency rows cannot be updated'
);
select throws_ok(
  $$delete from public.website_concept_idempotency_ledger
    where operation_id = 'c1e00000-0000-4000-8000-000000000001'$$,
  '55000', 'WEBSITE_CONCEPT_IDEMPOTENCY_IMMUTABLE',
  'Website concept idempotency rows cannot be deleted'
);
select throws_ok(
  $$insert into public.website_concept_events(
      concept_id, website_work_context_id, quote_request_id, event_type,
      actor_id, actor_role, command_id
    ) values (
      'c1b00000-0000-4000-8000-000000000001',
      'c1c00000-0000-4000-8000-000000000001',
      'c1110001-0000-4000-8000-000000000001',
      'WEBSITE_CONCEPT_STARTED', 'c1010000-0000-4000-8000-000000000001',
      'owner', 'c1a00000-0000-4000-8000-000000000013'
    )$$,
  '55000', 'DIRECT_WEBSITE_CONCEPT_WRITE_FORBIDDEN',
  'direct concept event insert is denied outside the command boundary'
);
select throws_ok(
  $$insert into public.website_concept_idempotency_ledger(
      actor_id, quote_request_id, command_type, idempotency_key,
      request_fingerprint, result_reference, result_payload
    )
    select
      actor_id, quote_request_id, command_type,
      'c1a00000-0000-4000-8000-000000000013', request_fingerprint,
      result_reference, result_payload
    from public.website_concept_idempotency_ledger
    where operation_id = 'c1e00000-0000-4000-8000-000000000001'$$,
  '55000', 'DIRECT_WEBSITE_CONCEPT_WRITE_FORBIDDEN',
  'direct idempotency insert is denied outside the command boundary'
);
select set_config('lws.website_concept_command', 'on', true);
select throws_ok(
  $$insert into public.website_concept_events(
      concept_id, website_work_context_id, quote_request_id, event_type,
      actor_id, actor_role, command_id, metadata
    ) values (
      'c1b00000-0000-4000-8000-000000000001',
      'c1c00000-0000-4000-8000-000000000001',
      'c1110001-0000-4000-8000-000000000001',
      'WEBSITE_CONCEPT_STARTED', 'c1010000-0000-4000-8000-000000000001',
      'owner', 'c1a00000-0000-4000-8000-000000000012',
      '{"credential":"forbidden"}'::jsonb
    )$$,
  '23514', null,
  'event metadata rejects credential-bearing keys'
);
select throws_ok(
  $$select pg_temp.insert_mismatched_website_context_v1()$$,
  'P0001', 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH',
  'cross-dossier concept binding fails closed under validation'
);
select throws_ok(
  $$select pg_temp.insert_non_website_concept_v1()$$,
  '23514', 'WEBSITE_CONCEPT_PRODUCTION_WEBSITE_REQUIRED',
  'non-Website concept root is rejected under dossier lock'
);
select set_config('lws.website_concept_command', '', true);
set local session_replication_role = replica;
delete from public.website_concept_idempotency_ledger
where operation_id = 'c1e00000-0000-4000-8000-000000000001';
delete from public.website_concept_events
where event_id = 'c1d00000-0000-4000-8000-000000000001';
delete from public.website_work_contexts
where website_work_context_id = 'c1c00000-0000-4000-8000-000000000001';
delete from public.website_concepts
where concept_id = 'c1b00000-0000-4000-8000-000000000001';
set local session_replication_role = origin;

set constraints all immediate;
set constraints all deferred;
select is(
  (select project_id
   from public.website_work_contexts
   where website_work_context_id = 'c1c00000-0000-4000-8000-000000000005'),
  'c1900000-0000-4000-8000-000000000005'::uuid,
  'official context resolves through accepted same-dossier commercial lineage'
);

create function pg_temp.insert_mismatched_official_context_v1()
returns void
language plpgsql
as $$
begin
  insert into public.website_work_contexts(
    quote_request_id, concept_id, project_id, phase, revision
  ) values (
    'c1120002-0000-4000-8000-000000000002', null,
    'c1900000-0000-4000-8000-000000000005', 'OFFICIAL_PROJECT', 1
  );
  set constraints all immediate;
end;
$$;
select set_config('lws.website_concept_command', 'on', true);
select throws_ok(
  $$select pg_temp.insert_mismatched_official_context_v1()$$,
  '23505', null,
  'a second official context for the same project fails closed'
);
select set_config('lws.website_concept_command', '', true);

\if :{?task2_schema_only}
select * from finish();
rollback;
\quit
\endif

select has_function(
  'public', 'get_operator_website_work_v1', array['uuid'],
  'Website work projection exists'
);
select has_function(
  'lws_internal', 'website_briefing_status_v1', array['uuid'],
  'Website briefing status helper exists'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_operator_website_work_v1(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.get_operator_website_work_v1(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.get_operator_website_work_v1(uuid)',
    'execute'
  ),
  'Website work projection is executable only by authenticated callers'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'lws_internal.website_briefing_status_v1(uuid)',
    'execute'
  ),
  'browser roles cannot execute the internal briefing helper'
);
select is(
  pg_temp.get_website_work_v1('c1110001-0000-4000-8000-000000000001'),
  jsonb_build_object(
    'state', 'NONE',
    'quote_request_id', 'c1110001-0000-4000-8000-000000000001',
    'concept_id', null,
    'project_id', null,
    'website_work_context_id', null,
    'mode', null,
    'briefing_status', null,
    'commercially_released', false,
    'revision', 1,
    'permitted_actions', jsonb_build_array('CAN_START_WEBSITE_CONCEPT')
  ),
  'eligible AAL2 owner receives the exact closed NONE Website work object'
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

select pg_temp.set_concept_claims_v1(
  'c1000000-0000-4000-8000-000000000001', 'aal1'
);
select is(
  pg_temp.get_website_work_v1('c1110001-0000-4000-8000-000000000001')
    ->'permitted_actions',
  '[]'::jsonb,
  'AAL1 owner receives no Website concept start action'
);
select pg_temp.set_concept_claims_v1(
  'c1000000-0000-4000-8000-000000000002', 'aal2'
);
select is(
  pg_temp.get_website_work_v1('c1110001-0000-4000-8000-000000000001')
    ->'permitted_actions',
  '[]'::jsonb,
  'admin receives no Website concept start action'
);
select pg_temp.set_concept_claims_v1(
  'c1000000-0000-4000-8000-000000000003', 'aal2'
);
select throws_ok(
  $$select public.get_operator_website_work_v1(
    'c1110001-0000-4000-8000-000000000001'
  )$$,
  '42501', 'APPLICATION_SCOPE_DENIED',
  'operations manager remains outside existing dossier detail read authority'
);
select pg_temp.set_concept_claims_v1(
  'c1000000-0000-4000-8000-000000000004', 'aal2'
);
select throws_ok(
  $$select public.get_operator_website_work_v1(
    'c1110001-0000-4000-8000-000000000001'
  )$$,
  '42501', 'APPLICATION_SCOPE_DENIED',
  'operator remains outside existing dossier detail read authority'
);
select pg_temp.set_concept_claims_v1(
  'c1000000-0000-4000-8000-000000000001', 'aal2'
);
select is(
  pg_temp.get_website_work_v1('c1130003-0000-4000-8000-000000000003')
    ->'permitted_actions',
  '[]'::jsonb,
  'non-Website dossier receives no Website concept start action'
);
select is(
  pg_temp.get_website_work_v1('c1140004-0000-4000-8000-000000000004')
    ->'permitted_actions',
  '[]'::jsonb,
  'trashed Website dossier receives no Website concept start action'
);
select is(
  pg_temp.get_website_work_v1('c1199999-0000-4000-8000-000000000099')
    ->'permitted_actions',
  '[]'::jsonb,
  'absent or purged dossier receives no Website concept start action'
);
update lws_internal.operator_dossier_states
set state = 'ARCHIVED', revision = revision + 1, updated_at = clock_timestamp()
where quote_request_id = 'c1120002-0000-4000-8000-000000000002';
select is(
  pg_temp.get_website_work_v1('c1120002-0000-4000-8000-000000000002')
    ->'permitted_actions',
  '[]'::jsonb,
  'archived Website dossier receives no Website concept start action'
);
update lws_internal.operator_dossier_states
set state = 'ACTIVE', revision = revision + 1, updated_at = clock_timestamp()
where quote_request_id = 'c1120002-0000-4000-8000-000000000002';

set local session_replication_role = replica;
insert into public.website_concepts(
  concept_id, quote_request_id, mode, briefing_status, concept_status,
  revision, created_by
) values (
  'c1b00000-0000-4000-8000-000000000002',
  'c1120002-0000-4000-8000-000000000002',
  'PRE_PROJECT', 'LIMITED', 'ACTIVE', 1,
  'c1010000-0000-4000-8000-000000000001'
);
insert into public.website_work_contexts(
  website_work_context_id, quote_request_id, concept_id, project_id, phase, revision
) values (
  'c1c00000-0000-4000-8000-000000000002',
  'c1140004-0000-4000-8000-000000000004',
  'c1b00000-0000-4000-8000-000000000002', null, 'PRE_PROJECT', 1
);
set local session_replication_role = origin;
select throws_ok(
  $$select public.get_operator_website_work_v1(
    'c1120002-0000-4000-8000-000000000002'
  )$$,
  'P0001', 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH',
  'binding inconsistency raises instead of degrading to NONE'
);
set local session_replication_role = replica;
update public.website_work_contexts
set quote_request_id = 'c1120002-0000-4000-8000-000000000002'
where website_work_context_id = 'c1c00000-0000-4000-8000-000000000002';
set local session_replication_role = origin;

select is(
  pg_temp.get_website_work_v1('c1120002-0000-4000-8000-000000000002'),
  jsonb_build_object(
    'state', 'PRE_PROJECT',
    'quote_request_id', 'c1120002-0000-4000-8000-000000000002',
    'concept_id', 'c1b00000-0000-4000-8000-000000000002',
    'project_id', null,
    'website_work_context_id', 'c1c00000-0000-4000-8000-000000000002',
    'mode', 'PRE_PROJECT',
    'briefing_status', 'LIMITED',
    'commercially_released', false,
    'revision', 1,
    'permitted_actions', jsonb_build_array('OPEN_WEBSITE')
  ),
  'readable concept receives the exact closed PRE_PROJECT Website work object'
);
select is(
  lws_internal.website_briefing_status_v1(
    'c1110001-0000-4000-8000-000000000001'
  ),
  'COMPLETE',
  'submitted intake with submitted_at derives COMPLETE briefing'
);
select is(
  lws_internal.website_briefing_status_v1(
    'c1120002-0000-4000-8000-000000000002'
  ),
  'LIMITED',
  'missing submitted intake derives LIMITED briefing'
);
select is(
  pg_temp.get_website_work_v1('c1150005-0000-4000-8000-000000000005'),
  jsonb_build_object(
    'state', 'OFFICIAL_PROJECT',
    'quote_request_id', 'c1150005-0000-4000-8000-000000000005',
    'concept_id', null,
    'project_id', 'c1900000-0000-4000-8000-000000000005',
    'website_work_context_id', 'c1c00000-0000-4000-8000-000000000005',
    'mode', 'OFFICIAL_PROJECT',
    'briefing_status', 'COMPLETE',
    'commercially_released', false,
    'revision', 1,
    'permitted_actions', jsonb_build_array('OPEN_WEBSITE')
  ),
  'eligible official Website receives the exact closed OFFICIAL_PROJECT object'
);

\if :{?task3_projection_only}
select * from finish();
rollback;
\quit
\endif

select has_function(
  'public', 'start_website_concept_v1', array['uuid', 'bigint', 'uuid'],
  'Website concept start command exists'
);
select is(
  (select count(*)
   from pg_proc
   where pronamespace = 'public'::regnamespace
     and proname = 'start_website_concept_v1'),
  1::bigint,
  'browser command exposes only the bounded uuid, bigint, uuid signature'
);
select ok(
  has_function_privilege(
    'authenticated',
    to_regprocedure('public.start_website_concept_v1(uuid,bigint,uuid)'),
    'execute'
  )
  and not has_function_privilege(
    'anon',
    to_regprocedure('public.start_website_concept_v1(uuid,bigint,uuid)'),
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    to_regprocedure('public.start_website_concept_v1(uuid,bigint,uuid)'),
    'execute'
  ),
  'only authenticated callers can execute the Website concept start command'
);
select ok(
  coalesce((
    select prosecdef
      and proconfig @> array['search_path=public, lws_internal, auth, extensions, pg_catalog']
    from pg_proc
    where oid = to_regprocedure(
      'public.start_website_concept_v1(uuid,bigint,uuid)'
    )
  ), false),
  'start command is security definer with a fixed trusted search path'
);
select ok(
  not has_function_privilege(
    'authenticated', 'lws_internal.assert_operator_aal2_v1()', 'execute'
  )
  and not has_function_privilege(
    'authenticated', 'lws_internal.website_briefing_status_v1(uuid)', 'execute'
  )
  and not has_function_privilege(
    'authenticated', 'lws_internal.guard_website_concept_root_write_v1()', 'execute'
  ),
  'authenticated callers receive no direct internal Website concept authority'
);
select pg_temp.set_concept_claims_v1(
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'aal1'
);
set local role authenticated;
select throws_ok(
  $$select public.start_website_concept_v1(
    'c1110001-0000-4000-8000-000000000001', 1,
    'c1a00000-0000-4000-8000-000000000021'
  )$$,
  '42501', 'AAL2_REQUIRED',
  'AAL1 owner cannot start a Website concept'
);
reset role;

select pg_temp.set_concept_claims_v1(
  'bd2ab636-0d42-4069-88a9-60bd97f2b335', 'aal2'
);
set local role authenticated;
select throws_ok(
  $$select public.start_website_concept_v1(
    'c1110001-0000-4000-8000-000000000001', 1,
    'c1a00000-0000-4000-8000-000000000022'
  )$$,
  '42501', 'WEBSITE_CONCEPT_OWNER_REQUIRED',
  'non-owner AAL2 operator cannot start a Website concept'
);
reset role;

select pg_temp.set_concept_claims_v1(
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'aal2'
);
set local role authenticated;
select throws_ok(
  $$select public.start_website_concept_v1(
    'c1199999-0000-4000-8000-000000000099', 1,
    'c1a00000-0000-4000-8000-000000000023'
  )$$,
  '23503', 'WEBSITE_CONCEPT_DOSSIER_NOT_FOUND',
  'unknown request cannot start a Website concept'
);
select throws_ok(
  $$select public.start_website_concept_v1(
    'c1130003-0000-4000-8000-000000000003', 1,
    'c1a00000-0000-4000-8000-000000000024'
  )$$,
  'P0001', 'WEBSITE_CONCEPT_NOT_ELIGIBLE',
  'non-Website request cannot start a Website concept'
);
select throws_ok(
  $$select public.start_website_concept_v1(
    'c1140004-0000-4000-8000-000000000004', 1,
    'c1a00000-0000-4000-8000-000000000025'
  )$$,
  'P0001', 'WEBSITE_CONCEPT_NOT_ELIGIBLE',
  'trashed Website dossier cannot start a Website concept'
);
select throws_ok(
  $$select public.start_website_concept_v1(
    'c1150005-0000-4000-8000-000000000005', 1,
    'c1a00000-0000-4000-8000-000000000026'
  )$$,
  'P0001', 'WEBSITE_CONCEPT_ALREADY_EXISTS',
  'official Website project blocks concept creation'
);
select throws_ok(
  $$select public.start_website_concept_v1(
    'c1110001-0000-4000-8000-000000000001', 2,
    'c1a00000-0000-4000-8000-000000000027'
  )$$,
  '40001', 'CONCURRENT_MODIFICATION',
  'stale Website work revision is rejected'
);
reset role;

set local role authenticated;
create temporary table concept_start_result as
select public.start_website_concept_v1(
  'c1110001-0000-4000-8000-000000000001', 1,
  'c1a00000-0000-4000-8000-000000000001'
) as result;
reset role;

select is(
  (select array_agg(key order by key)
   from concept_start_result
   cross join lateral jsonb_object_keys(result) as keys(key)),
  array[
    'briefing_status','commercially_released','concept_id','mode',
    'permitted_actions','project_id','quote_request_id','replayed','revision',
    'state','website_work_context_id'
  ],
  'start returns the exact complete Website work snapshot plus replayed'
);

select is(
  (select result->>'state' from concept_start_result),
  'PRE_PROJECT',
  'start returns PRE_PROJECT'
);
select is(
  (select result->>'replayed' from concept_start_result),
  'false',
  'first start is not marked as a replay'
);
select is(
  (select result - 'replayed' from concept_start_result),
  public.get_operator_website_work_v1(
    'c1110001-0000-4000-8000-000000000001'
  ),
  'start returns the complete authoritative post-command Website work snapshot'
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
  (select jsonb_build_array(
    (select count(*) from public.website_concept_events
     where quote_request_id = 'c1110001-0000-4000-8000-000000000001'),
    (select count(*) from public.website_concept_idempotency_ledger
     where quote_request_id = 'c1110001-0000-4000-8000-000000000001')
  )),
  '[1,1]'::jsonb,
  'start creates exactly one immutable event and one replay ledger row'
);
select is(
  (select request_fingerprint
   from public.website_concept_idempotency_ledger
   where quote_request_id = 'c1110001-0000-4000-8000-000000000001'),
  encode(extensions.digest(convert_to(jsonb_build_object(
    'authority_version', 'website_concept_start_v1',
    'actor_id', (select operator_id from public.commercial_operators
                 where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
    'command_type', 'START_WEBSITE_CONCEPT',
    'quote_request_id', 'c1110001-0000-4000-8000-000000000001'::uuid,
    'expected_website_work_revision', 1
  )::text, 'UTF8'), 'sha256'), 'hex')::character(64),
  'ledger fingerprint covers only authority version, server actor, command, request, and expected revision'
);

set local role authenticated;
create temporary table concept_replay_result as
select public.start_website_concept_v1(
  'c1110001-0000-4000-8000-000000000001', 1,
  'c1a00000-0000-4000-8000-000000000001'
) as result;
select throws_ok(
  $$select public.start_website_concept_v1(
    'c1120002-0000-4000-8000-000000000002', 1,
    'c1a00000-0000-4000-8000-000000000001'
  )$$,
  'P0001', 'IDEMPOTENCY_CONFLICT',
  'same actor and key with a changed request is rejected'
);
select throws_ok(
  $$select public.start_website_concept_v1(
    'c1110001-0000-4000-8000-000000000001', 2,
    'c1a00000-0000-4000-8000-000000000001'
  )$$,
  'P0001', 'IDEMPOTENCY_CONFLICT',
  'same actor and key with a changed expected revision is rejected'
);
select throws_ok(
  $$select public.start_website_concept_v1(
    'c1110001-0000-4000-8000-000000000001', 1,
    'c1a00000-0000-4000-8000-000000000002'
  )$$,
  'P0001', 'WEBSITE_CONCEPT_ALREADY_EXISTS',
  'different key after concept creation cannot create a second root'
);
reset role;
select is(
  (select result - 'replayed' from concept_replay_result),
  (select result - 'replayed' from concept_start_result),
  'exact replay preserves the same complete concept and context snapshot'
);
select is(
  (select result->>'replayed' from concept_replay_result),
  'true',
  'exact replay is explicitly marked replayed'
);
select is(
  (select jsonb_build_array(
    (select count(*) from public.website_concepts
     where quote_request_id = 'c1110001-0000-4000-8000-000000000001'),
    (select count(*) from public.website_work_contexts
     where quote_request_id = 'c1110001-0000-4000-8000-000000000001'),
    (select count(*) from public.website_concept_events
     where quote_request_id = 'c1110001-0000-4000-8000-000000000001'),
    (select count(*) from public.website_concept_idempotency_ledger
     where quote_request_id = 'c1110001-0000-4000-8000-000000000001')
  )),
  '[1,1,1,1]'::jsonb,
  'replay and conflict attempts leave exactly one command result'
);

select is(
  extensions.dblink_connect(
    'concept_start_setup',
    'host=' || host(inet_server_addr()) || ' port=' || current_setting('port')
      || ' dbname=' || current_database()
      || ' user=postgres password=postgres application_name=concept_start_setup'
  ),
  'OK',
  'concept concurrency setup connection opens'
);
select lives_ok(
  $test$select extensions.dblink_exec(
    'concept_start_setup',
    $setup$
      set session_replication_role = replica;
      delete from public.website_concept_idempotency_ledger
      where quote_request_id = 'c1170007-0000-4000-8000-000000000007';
      delete from public.website_concept_events
      where quote_request_id = 'c1170007-0000-4000-8000-000000000007';
      delete from public.website_work_contexts
      where quote_request_id = 'c1170007-0000-4000-8000-000000000007';
      delete from public.website_concepts
      where quote_request_id = 'c1170007-0000-4000-8000-000000000007';
      delete from lws_internal.operator_dossier_states
      where quote_request_id = 'c1170007-0000-4000-8000-000000000007';
      delete from public.quote_requests
      where id = 'c1170007-0000-4000-8000-000000000007';
      insert into public.quote_requests(
        id, application_reference, record_classification, request_kind,
        created_at, name, email, website_type, budget, timing, description,
        privacy_consent, status
      ) values (
        'c1170007-0000-4000-8000-000000000007', 'LWS-AAN-2099-9107',
        'production', 'website', '2099-01-01T03:00:00Z',
        'Concurrent concept target', 'concept-race@example.test', 'business',
        'Meer dan EUR 6.000', 'flexible',
        'Synthetic concurrent Website concept fixture.', true, 'approved'
      );
      insert into lws_internal.operator_dossier_states(
        quote_request_id, state, revision
      ) values (
        'c1170007-0000-4000-8000-000000000007', 'ACTIVE', 0
      );
      set session_replication_role = origin;
    $setup$
  )$test$,
  'committed concurrent Website dossier is created outside the pgTAP transaction'
);
select is(
  extensions.dblink_connect(
    'concept_start_a',
    'host=' || host(inet_server_addr()) || ' port=' || current_setting('port')
      || ' dbname=' || current_database()
      || ' user=postgres password=postgres application_name=concept_start_a'
  ),
  'OK',
  'first concept race connection opens'
);
select is(
  extensions.dblink_connect(
    'concept_start_b',
    'host=' || host(inet_server_addr()) || ' port=' || current_setting('port')
      || ' dbname=' || current_database()
      || ' user=postgres password=postgres application_name=concept_start_b'
  ),
  'OK',
  'second concept race connection opens'
);
select is(
  extensions.dblink_exec(
    'concept_start_a',
    $$begin;
      select set_config('request.jwt.claims',
        '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}',
        false);
      set local role authenticated$$
  ),
  'SET',
  'first concept race transaction and caller context start'
);
create temporary table concept_race_first_result as
select result
from extensions.dblink(
  'concept_start_a',
  $$select public.start_website_concept_v1(
    'c1170007-0000-4000-8000-000000000007', 1,
    'c1a00000-0000-4000-8000-000000000031'
  )$$
) as command(result jsonb);
select ok(
  extensions.dblink_exec(
    'concept_start_b',
    $$begin;
      select set_config('request.jwt.claims',
        '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}',
        false);
      set local role authenticated$$
  ) = 'SET',
  'second concept race transaction and caller context start'
);
select ok(
  extensions.dblink_send_query(
    'concept_start_b',
    $$select public.start_website_concept_v1(
      'c1170007-0000-4000-8000-000000000007', 1,
      'c1a00000-0000-4000-8000-000000000032'
    )$$
  ) = 1,
  'second concurrent first-start command begins while the winner holds its lock'
);
select is(
  extensions.dblink_exec('concept_start_a', 'commit'),
  'COMMIT',
  'first concurrent start commits'
);
select throws_ok(
  $$select * from extensions.dblink_get_result('concept_start_b')
    as command(result jsonb)$$,
  'P0001', 'WEBSITE_CONCEPT_ALREADY_EXISTS',
  'second concurrent first start resumes and cannot create another root'
);
select is(
  (select jsonb_build_array(
    (select count(*) from public.website_concepts
     where quote_request_id = 'c1170007-0000-4000-8000-000000000007'),
    (select count(*) from public.website_work_contexts
     where quote_request_id = 'c1170007-0000-4000-8000-000000000007'),
    (select count(*) from public.website_concept_events
     where quote_request_id = 'c1170007-0000-4000-8000-000000000007'),
    (select count(*) from public.website_concept_idempotency_ledger
     where quote_request_id = 'c1170007-0000-4000-8000-000000000007')
  )),
  '[1,1,1,1]'::jsonb,
  'concurrent first starts leave exactly one concept, context, event, and ledger'
);
select is(extensions.dblink_disconnect('concept_start_a'), 'OK', 'first concept race connection closes');
select is(extensions.dblink_disconnect('concept_start_b'), 'OK', 'second concept race connection closes');
select lives_ok(
  $test$select extensions.dblink_exec(
    'concept_start_setup',
    $cleanup$
      set session_replication_role = replica;
      delete from public.website_concept_idempotency_ledger
      where quote_request_id = 'c1170007-0000-4000-8000-000000000007';
      delete from public.website_concept_events
      where quote_request_id = 'c1170007-0000-4000-8000-000000000007';
      delete from public.website_work_contexts
      where quote_request_id = 'c1170007-0000-4000-8000-000000000007';
      delete from public.website_concepts
      where quote_request_id = 'c1170007-0000-4000-8000-000000000007';
      delete from lws_internal.operator_dossier_states
      where quote_request_id = 'c1170007-0000-4000-8000-000000000007';
      delete from public.quote_requests
      where id = 'c1170007-0000-4000-8000-000000000007';
      insert into public.quote_requests(
        id, application_reference, record_classification, request_kind,
        created_at, name, email, website_type, budget, timing, description,
        privacy_consent, status
      ) values (
        'c1180008-0000-4000-8000-000000000008', 'LWS-AAN-2099-9108',
        'production', 'website', '2099-01-01T02:00:00Z',
        'Rollback concept target', 'concept-rollback-committed@example.test',
        'business', 'Meer dan EUR 6.000', 'flexible',
        'Synthetic committed Website concept rollback fixture.', true, 'approved'
      );
      insert into lws_internal.operator_dossier_states(
        quote_request_id, state, revision
      ) values (
        'c1180008-0000-4000-8000-000000000008', 'ACTIVE', 0
      );
      set session_replication_role = origin;
    $cleanup$
  )$test$,
  'concurrency fixture is removed and committed rollback fixture is prepared'
);

create function pg_temp.fail_website_concept_start_event_v1()
returns trigger
language plpgsql
as $$
begin
  if new.quote_request_id = 'c1180008-0000-4000-8000-000000000008' then
    raise exception using errcode = 'P0001', message = 'TEST_CONCEPT_EVENT_FAILURE';
  end if;
  return new;
end;
$$;

create trigger aaa_test_fail_website_concept_start_event
before insert on public.website_concept_events
for each row execute function pg_temp.fail_website_concept_start_event_v1();
alter table public.website_concept_events
  enable always trigger aaa_test_fail_website_concept_start_event;

set local role authenticated;
select throws_ok(
  $$select public.start_website_concept_v1(
    'c1180008-0000-4000-8000-000000000008', 1,
    'c1a00000-0000-4000-8000-000000000028'
  )$$,
  'P0001', 'TEST_CONCEPT_EVENT_FAILURE',
  'event failure aborts the complete Website concept command'
);
reset role;
select is(
  (select jsonb_build_array(
    (select count(*) from public.website_concepts
      where quote_request_id = 'c1180008-0000-4000-8000-000000000008'),
    (select count(*) from public.website_work_contexts
      where quote_request_id = 'c1180008-0000-4000-8000-000000000008'),
    (select count(*) from public.website_concept_events
      where quote_request_id = 'c1180008-0000-4000-8000-000000000008'),
    (select count(*) from public.website_concept_idempotency_ledger
      where quote_request_id = 'c1180008-0000-4000-8000-000000000008')
  )),
  '[0,0,0,0]'::jsonb,
  'injected failure rolls concept, context, event, and ledger back together'
);
drop trigger aaa_test_fail_website_concept_start_event on public.website_concept_events;
select lives_ok(
  $test$select extensions.dblink_exec(
    'concept_start_setup',
    $cleanup$
      set session_replication_role = replica;
      delete from lws_internal.operator_dossier_states
      where quote_request_id = 'c1180008-0000-4000-8000-000000000008';
      delete from public.quote_requests
      where id = 'c1180008-0000-4000-8000-000000000008';
      set session_replication_role = origin;
    $cleanup$
  )$test$,
  'committed rollback fixture is removed'
);
select is(
  extensions.dblink_disconnect('concept_start_setup'),
  'OK',
  'concept concurrency setup connection closes'
);

\if :{?task4_command_only}
select * from finish();
rollback;
\quit
\endif

select has_function(
  'public', 'get_website_execution_workspace_v2', array['uuid'],
  'Website Execution V2 read exists'
);
select col_not_null(
  'public', 'website_execution_workspaces', 'website_work_context_id',
  'every Website workspace is anchored to a work context'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.website_execution_workspaces'::regclass
      and contype = 'f'
      and conkey = array[
        (select attnum from pg_attribute
         where attrelid = 'public.website_execution_workspaces'::regclass
           and attname = 'website_work_context_id')
      ]::smallint[]
      and confrelid = 'public.website_work_contexts'::regclass
  ),
  'Website workspace context binding has an enforced foreign key'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.website_execution_workspaces'::regclass
      and contype = 'u'
      and conkey = array[
        (select attnum from pg_attribute
         where attrelid = 'public.website_execution_workspaces'::regclass
           and attname = 'website_work_context_id')
      ]::smallint[]
  ),
  'one work context owns at most one Website workspace'
);
select is(
  (select count(*)
   from public.website_execution_workspaces as workspace
   join public.website_work_contexts as context
     on context.website_work_context_id = workspace.website_work_context_id
   where context.phase = 'OFFICIAL_PROJECT'
     and context.project_id = workspace.project_id
     and context.quote_request_id = workspace.quote_request_id),
  (select count(*) from public.website_execution_workspaces),
  'all Website workspaces resolve legacy locators from one official context'
);
select is(
  (select count(*)
   from public.commercial_projects as project
   join public.quote_request_quotation_acceptances as acceptance
     on acceptance.id = project.acceptance_id
    and acceptance.issuance_id = project.quotation_issuance_id
   join public.quote_request_quotation_issuances as issuance
     on issuance.id = project.quotation_issuance_id
    and issuance.status = 'ISSUED'
   join public.quote_request_quotation_approvals as approval
     on approval.id = issuance.approval_id
   join public.quote_requests as request on request.id = approval.quote_request_id
   left join public.website_work_contexts as context
     on context.project_id = project.project_id
    and context.quote_request_id = request.id
    and context.phase = 'OFFICIAL_PROJECT'
   where request.record_classification = 'production'
     and request.request_kind = 'website'
     and context.website_work_context_id is null),
  0::bigint,
  'every valid Website commercial project has one official work context'
);
select throws_ok(
  $$update public.website_execution_workspaces
    set quote_request_id = 'c1110001-0000-4000-8000-000000000001'
    where website_workspace_id = 'c1910000-0000-4000-8000-000000000005'$$,
  'P0001', 'WEBSITE_WORKSPACE_BINDING_MISMATCH',
  'legacy Website workspace locators cannot diverge from context authority'
);

select is(
  pg_temp.get_website_execution_workspace_v2(
    'c1110001-0000-4000-8000-000000000001'
  ),
  jsonb_build_object(
    'contract_version', 2,
    'mode', 'PRE_PROJECT',
    'quote_request_id', 'c1110001-0000-4000-8000-000000000001',
    'concept_id', (select concept_id from public.website_concepts
      where quote_request_id = 'c1110001-0000-4000-8000-000000000001'),
    'project_id', null,
    'website_work_context_id', (select website_work_context_id
      from public.website_work_contexts
      where quote_request_id = 'c1110001-0000-4000-8000-000000000001'),
    'context_revision', 1,
    'briefing_status', 'COMPLETE',
    'commercially_released', false,
    'project', null,
    'start_gate', null,
    'workspace', null,
    'requirements', jsonb_build_object(
      'state', 'NOT_AVAILABLE',
      'message', 'Requirements volgen na intake-sync.'
    )
  ),
  'PRE_PROJECT V2 returns the exact context-bound empty workspace contract'
);
select is(
  (select jsonb_build_object(
    'contract_version', projection->'contract_version',
    'mode', projection->'mode',
    'concept_id', projection->'concept_id',
    'project_id', projection->'project_id',
    'website_work_context_id', projection->'website_work_context_id',
    'project', projection->'project',
    'start_gate', projection->'start_gate',
    'workspace', projection->'workspace'
  )
  from (select pg_temp.get_website_execution_workspace_v2(
    'c1150005-0000-4000-8000-000000000005'
  ) as projection) as resolved),
  (select jsonb_build_object(
    'contract_version', 2,
    'mode', 'OFFICIAL_PROJECT',
    'concept_id', null,
    'project_id', 'c1900000-0000-4000-8000-000000000005',
    'website_work_context_id', 'c1c00000-0000-4000-8000-000000000005',
    'project', legacy->'project',
    'start_gate', legacy->'start_gate',
    'workspace', (legacy->'workspace') || jsonb_build_object(
      'website_work_context_id', 'c1c00000-0000-4000-8000-000000000005'
    )
  )
  from (select public.get_website_execution_workspace_v1(
    'c1150005-0000-4000-8000-000000000005',
    'c1900000-0000-4000-8000-000000000005'
  ) as legacy) as resolved),
  'OFFICIAL_PROJECT V2 preserves the complete V1 project and workspace projection'
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