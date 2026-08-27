begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table(
  'public', 'change_request_proposal_snapshots',
  'immutable Change Request proposal snapshot authority exists'
);
select has_function(
  'public', 'create_change_request_proposal_snapshot_v1',
  array[
    'uuid','uuid','uuid','uuid','uuid','integer','bigint','text','uuid',
    'text','text','text[]','text[]','text[]','text','text','integer','text','date',
    'text','text','text','text','bigint','bigint','bigint','bigint','bigint','bigint',
    'text','text','text','text','boolean'
  ],
  'Owner-approved proposal creation primitive exists'
);

create function pg_temp.proposal_approval_payload_v1(
  p_quote_request_id uuid,
  p_intake_id uuid,
  p_snapshot_id uuid,
  p_project_type text
)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'contract_version', 1,
    'source_quote_request_id', p_quote_request_id,
    'source_intake_id', p_intake_id,
    'pricing_snapshot', jsonb_build_object(
      'snapshot_id', p_snapshot_id,
      'snapshot_contract_version', 3,
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
      'source_quote_request_id', p_quote_request_id,
      'source_intake_id', p_intake_id, 'customer_id', null,
      'legal_name', 'Proposal Fixture BV', 'contact_name', null,
      'email', 'proposal@example.test', 'address_line_1', 'Teststraat 1',
      'address_line_2', null, 'postal_code', '9000', 'city', 'Gent',
      'country_code', 'BE', 'enterprise_number', null, 'vat_number', null,
      'source_fields', jsonb_build_object('legal_name', 'fixture'),
      'snapshot_sha256', repeat('b', 64)
    ),
    'project_scope', jsonb_build_object(
      'project_id', null, 'project_title', 'Proposal fixture',
      'project_type', p_project_type, 'scope_summary', 'Accepted fixture scope',
      'requested_languages', jsonb_build_array('nl'), 'included_page_count', 1,
      'features', jsonb_build_array('contact_form'), 'copywriting', null,
      'seo', null, 'hosting', null, 'maintenance', null,
      'exclusions', '[]'::jsonb, 'assumptions', '[]'::jsonb,
      'indicative_timing', null, 'source_intake_id', p_intake_id,
      'source_pricing_snapshot_id', p_snapshot_id,
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
  )
$$;

set local session_replication_role = replica;

insert into auth.users(id, email) values
  ('d1000000-0000-4000-8000-000000000001', 'proposal-owner@example.test'),
  ('d1000000-0000-4000-8000-000000000002', 'proposal-admin@example.test'),
  ('d1000000-0000-4000-8000-000000000003', 'proposal-operator@example.test');

insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status
) values
  ('d1010000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000001', 'Proposal Owner', 'owner', 'ACTIVE'),
  ('d1010000-0000-4000-8000-000000000002', 'd1000000-0000-4000-8000-000000000002', 'Proposal Admin', 'admin', 'ACTIVE'),
  ('d1010000-0000-4000-8000-000000000003', 'd1000000-0000-4000-8000-000000000003', 'Proposal Operator', 'operator', 'ACTIVE');

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind, sdf_package,
  name, email, website_type, budget, timing, description, privacy_consent, status
) values
  ('d1100000-0000-4000-8000-000000000001', 'LWS-AAN-2099-0201', 'production', 'website', null,
   'Website proposal fixture', 'website-proposal@example.test', 'business', 'x', 'x', 'Website fixture.', true, 'approved'),
  ('e1100000-0000-4000-8000-000000000002', 'LWS-AAN-2099-0202', 'production', 'slimme_documentenflow', 'groei',
   'SDF proposal fixture', 'sdf-proposal@example.test', null, null, null, 'SDF fixture.', true, 'approved');

insert into public.quote_request_quotation_approvals(
  id, draft_id, quote_request_id, intake_id, pricing_snapshot_id,
  contract_version, approval_version, approved_payload, payload_sha256,
  approved_by, approved_at
)
select
  fixture.approval_id, fixture.draft_id, fixture.quote_request_id,
  fixture.intake_id, fixture.snapshot_id, 1, 1, fixture.payload,
  public.quotation_approval_payload_sha256_v1(fixture.payload),
  'proposal:test', '2026-08-28T10:00:00Z'
from (
  select
    'd1200000-0000-4000-8000-000000000001'::uuid as approval_id,
    'd1210000-0000-4000-8000-000000000001'::uuid as draft_id,
    'd1100000-0000-4000-8000-000000000001'::uuid as quote_request_id,
    'd1220000-0000-4000-8000-000000000001'::uuid as intake_id,
    'd1230000-0000-4000-8000-000000000001'::uuid as snapshot_id,
    pg_temp.proposal_approval_payload_v1(
      'd1100000-0000-4000-8000-000000000001',
      'd1220000-0000-4000-8000-000000000001',
      'd1230000-0000-4000-8000-000000000001', 'website'
    ) as payload
  union all
  select
    'd1200000-0000-4000-8000-000000000002',
    'd1210000-0000-4000-8000-000000000002',
    'e1100000-0000-4000-8000-000000000002',
    'd1220000-0000-4000-8000-000000000002',
    'd1230000-0000-4000-8000-000000000002',
    pg_temp.proposal_approval_payload_v1(
      'e1100000-0000-4000-8000-000000000002',
      'd1220000-0000-4000-8000-000000000002',
      'd1230000-0000-4000-8000-000000000002', 'slimme_documentenflow'
    )
) as fixture;

insert into public.quote_request_quotation_issuances(
  id, quotation_number, quotation_version, status, approval_id,
  issued_at, issued_by, template_id, template_version, template_sha256,
  generation_contract_version, issuance_input_sha256,
  generation_payload_sha256, docx_sha256, docx_bytes,
  prepare_idempotency_key, prepare_fingerprint,
  commit_idempotency_key, commit_fingerprint
) values
  ('d1300000-0000-4000-8000-000000000001', 'LWS-OFF-2099-0201', 1, 'ISSUED', 'd1200000-0000-4000-8000-000000000001',
   '2026-08-28T10:00:00Z', 'proposal:test', 'LWS_QUOTATION_NL_BE', '1.0.0-technical', repeat('1',64),
   1, repeat('2',64), repeat('3',64), repeat('4',64), 1000,
   'd1310000-0000-4000-8000-000000000001', repeat('5',64),
   'd1320000-0000-4000-8000-000000000001', repeat('6',64)),
  ('d1300000-0000-4000-8000-000000000002', 'LWS-OFF-2099-0202', 1, 'ISSUED', 'd1200000-0000-4000-8000-000000000002',
   '2026-08-28T10:00:00Z', 'proposal:test', 'LWS_QUOTATION_NL_BE', '1.0.0-technical', repeat('1',64),
   1, repeat('2',64), repeat('3',64), repeat('4',64), 1000,
   'd1310000-0000-4000-8000-000000000002', repeat('5',64),
   'd1320000-0000-4000-8000-000000000002', repeat('6',64));

insert into public.commercial_projects(
  project_id, customer_id, quotation_issuance_id, acceptance_id,
  accepted_total_minor, currency, m1_minor, m2_minor, m3_minor,
  current_state, revision
) values
  ('d1400000-0000-4000-8000-000000000001', 'd1410000-0000-4000-8000-000000000001',
   'd1300000-0000-4000-8000-000000000001', 'd1420000-0000-4000-8000-000000000001',
   10000, 'EUR', 4000, 4000, 2000, 'PROJECT_RELEASED', 4),
  ('d1400000-0000-4000-8000-000000000002', 'd1410000-0000-4000-8000-000000000002',
   'd1300000-0000-4000-8000-000000000002', 'd1420000-0000-4000-8000-000000000002',
   10000, 'EUR', 4000, 4000, 2000, 'PROJECT_RELEASED', 2);

insert into public.customer_feedback(
  feedback_id, project_id, preview_access_id, feedback_type,
  subject, customer_message, status, revision, submitted_at
)
select
  format('d15%s0000-0000-4000-8000-00000000000%s', fixture.ordinal, fixture.ordinal)::uuid,
  'd1400000-0000-4000-8000-000000000001',
  format('d16%s0000-0000-4000-8000-00000000000%s', fixture.ordinal, fixture.ordinal)::uuid,
  'FUNCTIONALITY', 'Proposal fixture ' || fixture.ordinal,
  'Customer prose is source evidence only.', 'POTENTIAL_SCOPE_CHANGE', 1,
  '2026-08-28T10:00:00Z'
from generate_series(1, 5) as fixture(ordinal);

insert into public.customer_feedback(
  feedback_id, project_id, preview_access_id, feedback_type,
  subject, customer_message, status, revision, submitted_at
) values (
  'd1560000-0000-4000-8000-000000000006',
  'd1400000-0000-4000-8000-000000000002',
  'd1660000-0000-4000-8000-000000000006',
  'FUNCTIONALITY', 'SDF proposal fixture', 'SDF source evidence.',
  'POTENTIAL_SCOPE_CHANGE', 1, '2026-08-28T10:00:00Z'
);

insert into public.change_orders(
  change_order_id, project_id, original_quotation_issuance_id,
  feedback_id, change_request_reference, separate_amount_minor, status
)
select
  format('d17%s0000-0000-4000-8000-00000000000%s', fixture.ordinal, fixture.ordinal)::uuid,
  'd1400000-0000-4000-8000-000000000001',
  'd1300000-0000-4000-8000-000000000001',
  format('d15%s0000-0000-4000-8000-00000000000%s', fixture.ordinal, fixture.ordinal)::uuid,
  'CR-PROPOSAL-' || fixture.ordinal, null, 'CHANGE_ORDER_REQUIRED'
from generate_series(1, 5) as fixture(ordinal);

insert into public.change_orders(
  change_order_id, project_id, original_quotation_issuance_id,
  feedback_id, change_request_reference, separate_amount_minor, status
) values (
  'd1760000-0000-4000-8000-000000000006',
  'd1400000-0000-4000-8000-000000000002',
  'd1300000-0000-4000-8000-000000000002',
  'd1560000-0000-4000-8000-000000000006',
  'CR-PROPOSAL-SDF', null, 'CHANGE_ORDER_REQUIRED'
);

insert into public.customer_requests(
  request_id, request_reference, quote_request_id, customer_id, project_id,
  source, request_type, title, description, status, priority,
  submitted_at, submitter_type, source_feedback_id, linked_change_order_id,
  revision
) values (
  'd1800000-0000-4000-8000-000000000001', 'LWS-VRZ-2099-0201',
  'd1100000-0000-4000-8000-000000000001',
  'd1410000-0000-4000-8000-000000000001',
  'd1400000-0000-4000-8000-000000000001',
  'CUSTOMER_FEEDBACK', 'NEW_FEATURE', 'Customer prose fixture',
  'This prose is not an approved commercial scope.', 'WAITING_CHANGE_ORDER',
  'NORMAL', '2026-08-28T10:00:00Z', 'CUSTOMER',
  'd1510000-0000-4000-8000-000000000001',
  'd1710000-0000-4000-8000-000000000001', 1
);

set local session_replication_role = origin;

create function pg_temp.create_proposal_v1(
  p_idempotency_key uuid,
  p_change_order_id uuid default 'd1710000-0000-4000-8000-000000000001',
  p_project_id uuid default 'd1400000-0000-4000-8000-000000000001',
  p_original_quotation_issuance_id uuid default 'd1300000-0000-4000-8000-000000000001',
  p_feedback_id uuid default 'd1510000-0000-4000-8000-000000000001',
  p_customer_request_id uuid default 'd1800000-0000-4000-8000-000000000001',
  p_proposal_revision integer default 1,
  p_expected_project_revision bigint default 4,
  p_expected_change_order_status text default 'CHANGE_ORDER_REQUIRED',
  p_customer_visible_change_summary text default 'Voeg een goedgekeurde contactflow toe.',
  p_reason text default 'De klant heeft deze uitbreiding nodig.',
  p_added_scope text[] default array['Contactflow'],
  p_removed_scope text[] default array[]::text[],
  p_affected_deliverables text[] default array['Website'],
  p_other_scope_impact text default null,
  p_schedule_impact text default 'Twee extra werkdagen.',
  p_additional_time_value integer default 2,
  p_additional_time_unit text default 'DAYS',
  p_adjusted_delivery_target date default '2026-09-30',
  p_pricing_classification text default 'FIXED',
  p_catalog_item_reference text default 'catalog-v2#extra-standard-page',
  p_quantity bigint default null,
  p_unit_price_minor bigint default null,
  p_fixed_price_minor bigint default 22500,
  p_authority_floor_minor bigint default null,
  p_owner_final_amount_minor bigint default null,
  p_amount_ex_vat_minor bigint default 22500,
  p_impact_direction text default 'INCREASE',
  p_currency text default 'EUR',
  p_pricing_justification text default null,
  p_payment_milestone_impact text default 'Afzonderlijk na goedkeuring.',
  p_separate_invoicing boolean default true
)
returns jsonb
language sql
as $$
  select to_jsonb(result)
  from public.create_change_request_proposal_snapshot_v1(
    p_change_order_id, p_project_id, p_original_quotation_issuance_id,
    p_feedback_id, p_customer_request_id, p_proposal_revision,
    p_expected_project_revision, p_expected_change_order_status,
    p_idempotency_key, p_customer_visible_change_summary, p_reason,
    p_added_scope, p_removed_scope, p_affected_deliverables,
    p_other_scope_impact, p_schedule_impact, p_additional_time_value,
    p_additional_time_unit, p_adjusted_delivery_target,
    p_pricing_classification, p_catalog_item_reference,
    'LWS_Master_Product_Price_Catalog_v2_2026-08-13',
    '52FA3B9664EFF84640EAB914B72768E8059B1B49708815A0095D346C8F27BACE',
    p_quantity, p_unit_price_minor, p_fixed_price_minor,
    p_authority_floor_minor, p_owner_final_amount_minor,
    p_amount_ex_vat_minor, p_impact_direction, p_currency,
    p_pricing_justification, p_payment_milestone_impact,
    p_separate_invoicing
  ) as result
$$;

select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class where oid = 'public.change_request_proposal_snapshots'::regclass),
  'proposal snapshots use RLS and FORCE RLS'
);
select ok(
  not has_table_privilege('anon', 'public.change_request_proposal_snapshots', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.change_request_proposal_snapshots', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.change_request_proposal_snapshots', 'select,insert,update,delete'),
  'runtime roles have no direct proposal table privileges'
);
select ok(
  has_function_privilege('authenticated', 'public.create_change_request_proposal_snapshot_v1(uuid,uuid,uuid,uuid,uuid,integer,bigint,text,uuid,text,text,text[],text[],text[],text,text,integer,text,date,text,text,text,text,bigint,bigint,bigint,bigint,bigint,bigint,text,text,text,text,boolean)', 'execute')
  and not has_function_privilege('anon', 'public.create_change_request_proposal_snapshot_v1(uuid,uuid,uuid,uuid,uuid,integer,bigint,text,uuid,text,text,text[],text[],text[],text,text,integer,text,date,text,text,text,text,bigint,bigint,bigint,bigint,bigint,bigint,text,text,text,text,boolean)', 'execute')
  and not has_function_privilege('service_role', 'public.create_change_request_proposal_snapshot_v1(uuid,uuid,uuid,uuid,uuid,integer,bigint,text,uuid,text,text,text[],text[],text[],text,text,integer,text,date,text,text,text,text,bigint,bigint,bigint,bigint,bigint,bigint,text,text,text,text,boolean)', 'execute'),
  'only authenticated humans can enter the Owner-guarded creation RPC'
);

create temporary table proposal_side_effect_before as
select
  (select row(status, separate_amount_minor)::text from public.change_orders where change_order_id = 'd1710000-0000-4000-8000-000000000001') as change_order_state,
  (select row(status, revision)::text from public.customer_requests where request_id = 'd1800000-0000-4000-8000-000000000001') as customer_request_state,
  (select count(*) from public.quote_request_pricing_snapshots) as pricing_count,
  (select count(*) from public.commercial_documents) as document_count,
  (select count(*) from public.quote_request_quotation_email_orchestrations) as mail_count,
  (select count(*) from public.payment_expectations) as payment_count,
  (select count(*) from public.sdf_accepted_commercial_terms) as sdf_count;

select set_config('request.jwt.claim.sub', 'd1000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000001')$$,
  '42501', 'CHANGE_REQUEST_PROPOSAL_OWNER_REQUIRED',
  'non-Owner operator cannot finalize a commercial proposal'
);

select set_config('request.jwt.claim.sub', 'd1000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000002', p_change_order_id => 'd1790000-0000-4000-8000-000000000009')$$,
  '23503', 'CHANGE_REQUEST_PROPOSAL_CHANGE_ORDER_NOT_FOUND',
  'change order must exist'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000003', p_project_id => 'd1400000-0000-4000-8000-000000000002')$$,
  '23514', 'CHANGE_REQUEST_PROPOSAL_PROJECT_MISMATCH',
  'project and change order provenance must agree'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000004', p_original_quotation_issuance_id => 'd1300000-0000-4000-8000-000000000002')$$,
  '23514', 'CHANGE_REQUEST_PROPOSAL_QUOTATION_MISMATCH',
  'original quotation issuance must agree with project and change order'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000005', p_feedback_id => 'd1520000-0000-4000-8000-000000000002')$$,
  '23514', 'CHANGE_REQUEST_PROPOSAL_FEEDBACK_MISMATCH',
  'feedback provenance must agree with the change order'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000006', p_customer_request_id => 'd1890000-0000-4000-8000-000000000009')$$,
  '23514', 'CHANGE_REQUEST_PROPOSAL_CUSTOMER_REQUEST_MISMATCH',
  'unknown or incoherent Customer Request provenance is rejected'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000007', p_expected_project_revision => 3)$$,
  '40001', 'CHANGE_REQUEST_PROPOSAL_STALE_REVISION',
  'stale project revision is rejected'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000008', p_customer_visible_change_summary => '')$$,
  '23514', 'CHANGE_REQUEST_PROPOSAL_SCOPE_REQUIRED',
  'Customer Request prose alone cannot replace approved customer-visible scope'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000009', p_pricing_classification => 'BLOCKED')$$,
  '23514', 'CHANGE_REQUEST_PROPOSAL_PRICING_CLASSIFICATION_INVALID',
  'BLOCKED pricing cannot produce a proposal'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000010', p_pricing_classification => 'UNCLASSIFIED')$$,
  '23514', 'CHANGE_REQUEST_PROPOSAL_PRICING_CLASSIFICATION_INVALID',
  'UNCLASSIFIED pricing cannot produce a proposal'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000011', p_fixed_price_minor => 22000)$$,
  '23514', 'CHANGE_REQUEST_PROPOSAL_PRICING_SHAPE_INVALID',
  'FIXED requires exact coherent authority and final amounts'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000012', p_pricing_classification => 'UNIT', p_fixed_price_minor => null, p_quantity => 2, p_unit_price_minor => 10000, p_amount_ex_vat_minor => 19999)$$,
  '23514', 'CHANGE_REQUEST_PROPOSAL_PRICING_SHAPE_INVALID',
  'UNIT arithmetic is verified server-side'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000013', p_pricing_classification => 'FROM', p_fixed_price_minor => null, p_authority_floor_minor => 20000, p_owner_final_amount_minor => null, p_amount_ex_vat_minor => 20000)$$,
  '23514', 'CHANGE_REQUEST_PROPOSAL_PRICING_SHAPE_INVALID',
  'FROM requires an Owner-final amount'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000014', p_pricing_classification => 'FROM', p_fixed_price_minor => null, p_authority_floor_minor => 20000, p_owner_final_amount_minor => 19000, p_amount_ex_vat_minor => 19000)$$,
  '23514', 'CHANGE_REQUEST_PROPOSAL_PRICING_SHAPE_INVALID',
  'FROM final amount cannot undercut its authority floor'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000015', p_pricing_classification => 'MANUAL', p_fixed_price_minor => null, p_owner_final_amount_minor => null, p_amount_ex_vat_minor => 10000, p_pricing_justification => null)$$,
  '23514', 'CHANGE_REQUEST_PROPOSAL_PRICING_SHAPE_INVALID',
  'MANUAL requires Owner-final amount and justification'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000016', p_pricing_classification => 'INCLUDED', p_fixed_price_minor => null, p_amount_ex_vat_minor => 1, p_impact_direction => null)$$,
  '23514', 'CHANGE_REQUEST_PROPOSAL_PRICING_SHAPE_INVALID',
  'INCLUDED requires an exact zero-cost amount'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000017', p_amount_ex_vat_minor => -1)$$,
  '23514', 'CHANGE_REQUEST_PROPOSAL_PRICING_SHAPE_INVALID',
  'negative money representation is rejected'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000018', p_currency => 'USD')$$,
  '23514', 'CHANGE_REQUEST_PROPOSAL_CURRENCY_INVALID',
  'currency is fixed to EUR authority'
);

create temporary table fixed_proposal as
select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000101') as result;
select is((select result->>'proposal_revision' from fixed_proposal), '1', 'Owner creates a valid FIXED Website proposal');
select is((select result->>'replayed' from fixed_proposal), 'false', 'first proposal creation is not replayed');
select is(
  pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000101')->>'proposal_id',
  (select result->>'proposal_id' from fixed_proposal),
  'same actor, key, and payload replay the same proposal'
);
select is(
  pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000101')->>'replayed',
  'true', 'idempotent replay is explicitly reported'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000101', p_reason => 'Conflicting reason')$$,
  'P0001', 'IDEMPOTENCY_CONFLICT',
  'same idempotency key with different payload conflicts'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000102')$$,
  '23505', 'CHANGE_REQUEST_PROPOSAL_REVISION_CONFLICT',
  'proposal revision is unique per change order'
);
select throws_ok(
  $$select pg_temp.create_proposal_v1('d1900000-0000-4000-8000-000000000103', p_proposal_revision => 2)$$,
  '23505', 'CHANGE_REQUEST_PROPOSAL_EXPECTED_REVISION_CONFLICT',
  'one expected project revision cannot yield conflicting proposals'
);

select lives_ok(
  $$select pg_temp.create_proposal_v1(
    'd1900000-0000-4000-8000-000000000104',
    p_change_order_id => 'd1720000-0000-4000-8000-000000000002',
    p_feedback_id => 'd1520000-0000-4000-8000-000000000002',
    p_customer_request_id => null,
    p_pricing_classification => 'UNIT', p_fixed_price_minor => null,
    p_quantity => 2, p_unit_price_minor => 10000,
    p_amount_ex_vat_minor => 20000
  )$$,
  'valid UNIT proposal passes exact arithmetic validation'
);
select lives_ok(
  $$select pg_temp.create_proposal_v1(
    'd1900000-0000-4000-8000-000000000105',
    p_change_order_id => 'd1730000-0000-4000-8000-000000000003',
    p_feedback_id => 'd1530000-0000-4000-8000-000000000003',
    p_customer_request_id => null,
    p_pricing_classification => 'FROM', p_fixed_price_minor => null,
    p_authority_floor_minor => 20000, p_owner_final_amount_minor => 25000,
    p_amount_ex_vat_minor => 25000
  )$$,
  'valid FROM proposal preserves floor and Owner-final amount'
);
select lives_ok(
  $$select pg_temp.create_proposal_v1(
    'd1900000-0000-4000-8000-000000000106',
    p_change_order_id => 'd1740000-0000-4000-8000-000000000004',
    p_feedback_id => 'd1540000-0000-4000-8000-000000000004',
    p_customer_request_id => null,
    p_pricing_classification => 'MANUAL', p_fixed_price_minor => null,
    p_owner_final_amount_minor => 30000, p_amount_ex_vat_minor => 30000,
    p_pricing_justification => 'Owner beoordeelde technische complexiteit.'
  )$$,
  'valid MANUAL proposal requires and preserves Owner justification'
);

select set_config('request.jwt.claim.sub', 'd1000000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$select pg_temp.create_proposal_v1(
    'd1900000-0000-4000-8000-000000000107',
    p_change_order_id => 'd1750000-0000-4000-8000-000000000005',
    p_feedback_id => 'd1550000-0000-4000-8000-000000000005',
    p_customer_request_id => null,
    p_pricing_classification => 'INCLUDED', p_fixed_price_minor => null,
    p_amount_ex_vat_minor => 0, p_impact_direction => null
  )$$,
  'existing admin authority is equivalent to Owner for proposal approval'
);

select set_config('request.jwt.claim.sub', 'd1000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$select pg_temp.create_proposal_v1(
    'd1900000-0000-4000-8000-000000000108',
    p_change_order_id => 'd1760000-0000-4000-8000-000000000006',
    p_project_id => 'd1400000-0000-4000-8000-000000000002',
    p_original_quotation_issuance_id => 'd1300000-0000-4000-8000-000000000002',
    p_feedback_id => 'd1560000-0000-4000-8000-000000000006',
    p_customer_request_id => null, p_expected_project_revision => 2
  )$$,
  '23514', 'CHANGE_REQUEST_PROPOSAL_WEBSITE_REQUIRED',
  'SDF proposal creation fails closed without Website fallback'
);

select throws_ok(
  $$update public.change_request_proposal_snapshots set reason = 'mutated' where proposal_id = (select (result->>'proposal_id')::uuid from fixed_proposal)$$,
  '55000', 'CHANGE_REQUEST_PROPOSAL_IMMUTABLE',
  'approved proposal UPDATE is denied'
);
select throws_ok(
  $$delete from public.change_request_proposal_snapshots where proposal_id = (select (result->>'proposal_id')::uuid from fixed_proposal)$$,
  '55000', 'CHANGE_REQUEST_PROPOSAL_IMMUTABLE',
  'approved proposal DELETE is denied'
);

select is(
  (select concat_ws('|', template_version, status, canonical_filename)
   from public.resolve_current_change_request_template_v1('CHANGE_REQUEST')),
  'v2|CURRENT|08_Wijzigingsverzoek_ChangeRequest_v2.docx',
  'canonical Change Request v2 resolver remains green'
);
select is(
  (select row(change_order_state, customer_request_state, pricing_count, document_count, mail_count, payment_count, sdf_count)::text
   from proposal_side_effect_before),
  (select row(
    (select row(status, separate_amount_minor)::text from public.change_orders where change_order_id = 'd1710000-0000-4000-8000-000000000001'),
    (select row(status, revision)::text from public.customer_requests where request_id = 'd1800000-0000-4000-8000-000000000001'),
    (select count(*) from public.quote_request_pricing_snapshots),
    (select count(*) from public.commercial_documents),
    (select count(*) from public.quote_request_quotation_email_orchestrations),
    (select count(*) from public.payment_expectations),
    (select count(*) from public.sdf_accepted_commercial_terms)
  )::text),
  'proposal creation mutates no change order, Customer Request, pricing, document, mail, payment, or SDF authority'
);

select * from finish();
rollback;