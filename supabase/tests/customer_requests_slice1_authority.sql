begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set local search_path = public, extensions;
select no_plan();

create function pg_temp.wait_for_customer_request_lock_v1(p_backend_pid integer)
returns boolean
language plpgsql
as $$
declare
  v_deadline timestamptz := clock_timestamp() + interval '5 seconds';
begin
  loop
    if exists (
      select 1 from pg_catalog.pg_locks
      where pid = p_backend_pid and not granted
    ) then
      return true;
    end if;
    if clock_timestamp() >= v_deadline then
      return false;
    end if;
  end loop;
end;
$$;

select has_table('public', 'customer_requests', 'customer request aggregate exists');
select has_table('public', 'customer_request_events', 'customer request event history exists');
select has_table('lws_internal', 'customer_request_reference_counters', 'private annual reference authority exists');
select has_table('lws_internal', 'customer_request_commands', 'private idempotency ledger exists');
select has_function(
  'lws_internal', 'create_customer_request_core_v1',
  array['uuid','uuid','uuid','uuid','uuid','uuid','jsonb'],
  'private customer request creation authority exists'
);
select has_function(
  'lws_internal', 'transition_customer_request_core_v1',
  array['uuid','text','bigint','uuid','jsonb'],
  'private customer request lifecycle authority exists'
);
select ok(
  (select array_agg(procedure.oid::regprocedure::text order by procedure.oid::regprocedure::text)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname like '%customer_request%'
  ) = array[
    'cleanup_expired_customer_request_uploads_v1(integer,uuid)',
    'complete_customer_request_upload_request_v1(text,uuid)',
    'create_customer_request_smoke_fixture_v1(uuid,uuid)',
    'create_customer_request_smoke_fixture_v1(uuid)',
    'create_customer_request_upload_request_v1(uuid,text,timestamp with time zone,uuid)',
    'create_sdf_customer_request_v1(uuid,uuid,text,text,text,text)',
    'finalize_customer_request_uploaded_file_v1(text,uuid,text,bigint,text,boolean,uuid)',
    'get_customer_request_v1(uuid)',
    'get_customer_requests_for_dossier_v1(text,text,integer)',
    'list_customer_request_uploaded_files_v1(text)',
    'prepare_customer_request_upload_v1(text,text,text,bigint,uuid)',
    'resolve_customer_request_authorization_v1(uuid,text)',
    'resolve_customer_request_upload_capability_v1(text)',
    'revoke_customer_request_upload_request_v1(uuid,text,uuid)',
    'transition_customer_request_v1(uuid,text,bigint,uuid,jsonb)'
  ]::text[]
  and has_function_privilege('authenticated', 'public.get_customer_request_v1(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.get_customer_requests_for_dossier_v1(text,text,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.transition_customer_request_v1(uuid,text,bigint,uuid,jsonb)', 'execute')
  and has_function_privilege('authenticated', 'public.create_customer_request_smoke_fixture_v1(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.create_sdf_customer_request_v1(uuid,uuid,text,text,text,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.create_customer_request_smoke_fixture_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.resolve_customer_request_authorization_v1(uuid,text)', 'execute')
  and not has_function_privilege('anon', 'public.get_customer_request_v1(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.get_customer_requests_for_dossier_v1(text,text,integer)', 'execute')
  and not has_function_privilege('anon', 'public.transition_customer_request_v1(uuid,text,bigint,uuid,jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.create_customer_request_smoke_fixture_v1(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.create_sdf_customer_request_v1(uuid,uuid,text,text,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.create_customer_request_smoke_fixture_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.resolve_customer_request_authorization_v1(uuid,text)', 'execute')
  and not has_function_privilege('service_role', 'public.get_customer_request_v1(uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.get_customer_requests_for_dossier_v1(text,text,integer)', 'execute')
  and not has_function_privilege('service_role', 'public.transition_customer_request_v1(uuid,text,bigint,uuid,jsonb)', 'execute')
  and not has_function_privilege('service_role', 'public.create_customer_request_smoke_fixture_v1(uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.create_sdf_customer_request_v1(uuid,uuid,text,text,text,text)', 'execute')
  and not has_function_privilege('service_role', 'public.create_customer_request_smoke_fixture_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.resolve_customer_request_authorization_v1(uuid,text)', 'execute'),
  'public Customer Request functions and runtime execution match the exact capability allowlist'
);
select ok(
  not has_function_privilege('anon', 'lws_internal.create_customer_request_core_v1(uuid,uuid,uuid,uuid,uuid,uuid,jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'lws_internal.create_customer_request_core_v1(uuid,uuid,uuid,uuid,uuid,uuid,jsonb)', 'execute')
  and not has_function_privilege('service_role', 'lws_internal.create_customer_request_core_v1(uuid,uuid,uuid,uuid,uuid,uuid,jsonb)', 'execute')
  and not has_function_privilege('anon', 'lws_internal.transition_customer_request_core_v1(uuid,text,bigint,uuid,jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'lws_internal.transition_customer_request_core_v1(uuid,text,bigint,uuid,jsonb)', 'execute')
  and not has_function_privilege('service_role', 'lws_internal.transition_customer_request_core_v1(uuid,text,bigint,uuid,jsonb)', 'execute'),
  'private core functions grant no runtime execution authority'
);
select is(
  (select count(*)::integer
   from pg_catalog.pg_class as relation
   join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
   where (namespace.nspname, relation.relname) in (
     ('public', 'customer_requests'),
     ('public', 'customer_request_events'),
     ('lws_internal', 'customer_request_reference_counters'),
     ('lws_internal', 'customer_request_commands')
   ) and relation.relrowsecurity),
  4,
  'RLS is enabled on all Slice 1 tables'
);
select is(
  (select count(*)::integer
   from pg_catalog.pg_class as relation
   join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
   where (namespace.nspname, relation.relname) in (
     ('public', 'customer_requests'),
     ('public', 'customer_request_events'),
     ('lws_internal', 'customer_request_reference_counters'),
     ('lws_internal', 'customer_request_commands')
   ) and relation.relforcerowsecurity),
  4,
  'RLS is forced on all Slice 1 tables'
);
select is(
  (select count(*)::integer
   from information_schema.role_table_grants
   where (table_schema, table_name) in (
     ('public', 'customer_requests'),
     ('public', 'customer_request_events'),
     ('lws_internal', 'customer_request_reference_counters'),
     ('lws_internal', 'customer_request_commands')
   )
   and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
   and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')),
  0,
  'runtime roles receive no direct Slice 1 table privileges'
);

set local session_replication_role = replica;

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind,
  name, email, website_type, budget, timing, description, privacy_consent, status
) values
  ('c1100000-0000-4000-8000-000000000001', 'LWS-AAN-2031-0101', 'production', 'website',
   'Customer request fixture A', 'request-a@example.test', 'business', 'x', 'x', 'Fixture A.', true, 'approved'),
  ('c1100002-0000-4000-8000-000000000002', 'LWS-AAN-2031-0102', 'production', 'website',
   'Customer request fixture B', 'request-b@example.test', 'business', 'x', 'x', 'Fixture B.', true, 'approved'),
  ('c1100003-0000-4000-8000-000000000003', 'LWS-AAN-2031-0103', 'internal_e2e', 'website',
   'Non-production fixture', 'request-c@example.test', 'business', 'x', 'x', 'Fixture C.', true, 'approved');

insert into public.quote_request_intakes(
  id, quote_request_id, access_token_hash, access_token_expires_at,
  status, started_at, submitted_at, confirmation
) values
  ('c1200000-0000-4000-8000-000000000001', 'c1100000-0000-4000-8000-000000000001', repeat('1',64), '2032-01-01T00:00:00Z', 'submitted', '2031-02-01T09:00:00Z', '2031-02-01T10:00:00Z', true),
  ('c1200000-0000-4000-8000-000000000002', 'c1100002-0000-4000-8000-000000000002', repeat('2',64), '2032-01-01T00:00:00Z', 'submitted', '2031-02-02T09:00:00Z', '2031-02-02T10:00:00Z', true),
  ('c1200000-0000-4000-8000-000000000003', 'c1100003-0000-4000-8000-000000000003', repeat('3',64), '2032-01-01T00:00:00Z', 'submitted', '2031-02-03T09:00:00Z', '2031-02-03T10:00:00Z', true);

create function pg_temp.customer_request_approval_payload_v1(
  p_quote_request_id uuid,
  p_intake_id uuid,
  p_snapshot_id uuid
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
      'snapshot_contract_version', 2,
      'integrity_algorithm_version', 'hmac-sha256-v1',
      'integrity_key_id', 'v1',
      'integrity_mac', repeat('a', 64)
    ),
    'currency', 'EUR',
    'line_items', jsonb_build_array(jsonb_build_object(
      'line_id', 'website',
      'sequence', 1,
      'product_or_service_code', 'WEBSITE',
      'description', 'Websiteontwikkeling',
      'quantity', 1,
      'unit', 'project',
      'unit_price_minor', 10000,
      'discount_minor', 0,
      'vat_treatment', 'STANDARD',
      'vat_rate', 21,
      'line_net_amount_minor', 10000,
      'cost_type', 'ONE_TIME'
    )),
    'totals', jsonb_build_object(
      'one_time_subtotal_minor', 10000,
      'recurring_subtotal_minor', 0,
      'discount_total_minor', 0,
      'vat_base_minor', 10000,
      'vat_amount_minor', 2100,
      'total_gross_minor', 12100
    ),
    'discount', jsonb_build_object(
      'discount_type', null,
      'discount_value_minor', 0,
      'discount_reason', null,
      'approved_by', null,
      'approved_at', null
    ),
    'customer_identity', jsonb_build_object(
      'source_quote_request_id', p_quote_request_id,
      'source_intake_id', p_intake_id,
      'customer_id', null,
      'legal_name', 'Customer Request Fixture BV',
      'contact_name', 'Fixture',
      'email', 'fixture@example.test',
      'address_line_1', 'Teststraat 1',
      'address_line_2', null,
      'postal_code', '9000',
      'city', 'Gent',
      'country_code', 'BE',
      'enterprise_number', null,
      'vat_number', null,
      'source_fields', jsonb_build_object('legal_name', 'fixture'),
      'snapshot_sha256', repeat('b', 64)
    ),
    'project_scope', jsonb_build_object(
      'project_id', null,
      'project_title', 'Customer request fixture',
      'project_type', 'website',
      'scope_summary', 'Fixture scope',
      'requested_languages', jsonb_build_array('nl'),
      'included_page_count', 1,
      'features', '[]'::jsonb,
      'copywriting', null,
      'seo', null,
      'hosting', null,
      'maintenance', null,
      'exclusions', '[]'::jsonb,
      'assumptions', '[]'::jsonb,
      'indicative_timing', null,
      'source_intake_id', p_intake_id,
      'source_pricing_snapshot_id', p_snapshot_id,
      'snapshot_sha256', repeat('c', 64)
    ),
    'vat_approval', jsonb_build_object(
      'vat_treatment', 'STANDARD',
      'vat_rate', 21,
      'vat_decision_source', 'accountant',
      'vat_approved_by', 'accountant:test',
      'vat_approved_at', '2031-01-01T12:00:00Z'
    ),
    'payment_schedule', jsonb_build_object(
      'schedule_id', 'schedule-1',
      'milestones', jsonb_build_array(jsonb_build_object(
        'sequence', 1,
        'label', 'Volledige betaling',
        'percentage', 100,
        'amount_minor', null,
        'trigger', 'invoice',
        'due_terms_days', 30,
        'recurring_cycle', null
      )),
      'approved_by', 'commercial:test',
      'approved_at', '2031-01-01T12:00:00Z'
    ),
    'validity', jsonb_build_object(
      'valid_from', '2031-01-01',
      'valid_until', '2031-01-31',
      'validity_days', 30,
      'approved_by', 'commercial:test',
      'approved_at', '2031-01-01T12:00:00Z'
    ),
    'legal_references', jsonb_build_object(
      'terms_reference', 'terms-v1',
      'terms_version', '1.0.0',
      'terms_sha256', repeat('d', 64),
      'terms_status', 'APPROVED',
      'agreement_template_reference', null,
      'agreement_template_version', null,
      'agreement_template_sha256', null
    )
  )
$$;

insert into public.quote_request_quotation_approvals(
  id, draft_id, quote_request_id, intake_id, pricing_snapshot_id, contract_version,
  approval_version, approved_payload, payload_sha256, approved_by, approved_at
)
select
  fixture.approval_id,
  fixture.draft_id,
  fixture.quote_request_id,
  fixture.intake_id,
  fixture.snapshot_id,
  1,
  1,
  payload.value,
  public.quotation_approval_payload_sha256_v1(payload.value),
  'fixture',
  fixture.approved_at
from (values
  ('c1300000-0000-4000-8000-000000000001'::uuid, 'c1310000-0000-4000-8000-000000000001'::uuid, 'c1100000-0000-4000-8000-000000000001'::uuid, 'c1200000-0000-4000-8000-000000000001'::uuid, 'c1320000-0000-4000-8000-000000000001'::uuid, '2031-02-01T11:00:00Z'::timestamptz),
  ('c1300000-0000-4000-8000-000000000002'::uuid, 'c1310000-0000-4000-8000-000000000002'::uuid, 'c1100002-0000-4000-8000-000000000002'::uuid, 'c1200000-0000-4000-8000-000000000002'::uuid, 'c1320000-0000-4000-8000-000000000002'::uuid, '2031-02-02T11:00:00Z'::timestamptz),
  ('c1300000-0000-4000-8000-000000000003'::uuid, 'c1310000-0000-4000-8000-000000000003'::uuid, 'c1100003-0000-4000-8000-000000000003'::uuid, 'c1200000-0000-4000-8000-000000000003'::uuid, 'c1320000-0000-4000-8000-000000000003'::uuid, '2031-02-03T11:00:00Z'::timestamptz)
) as fixture(approval_id, draft_id, quote_request_id, intake_id, snapshot_id, approved_at)
cross join lateral (
  select pg_temp.customer_request_approval_payload_v1(
    fixture.quote_request_id, fixture.intake_id, fixture.snapshot_id
  ) as value
) as payload;

insert into public.quote_request_quotation_issuances(
  id, quotation_number, quotation_version, status, approval_id, issued_at, issued_by,
  template_id, template_version, template_sha256, generation_contract_version,
  issuance_input_sha256, generation_payload_sha256, docx_sha256, docx_bytes,
  prepare_idempotency_key, prepare_fingerprint, commit_idempotency_key, commit_fingerprint
) values
  ('c1400000-0000-4000-8000-000000000001', 'LWS-OFF-2031-0101', 1, 'ISSUED', 'c1300000-0000-4000-8000-000000000001', '2031-02-01T12:00:00Z', 'fixture', 'T', '1', repeat('1',64), 1, repeat('2',64), repeat('3',64), repeat('4',64), 1, 'c1410000-0000-4000-8000-000000000001', repeat('5',64), 'c1420000-0000-4000-8000-000000000001', repeat('6',64)),
  ('c1400000-0000-4000-8000-000000000002', 'LWS-OFF-2031-0102', 1, 'ISSUED', 'c1300000-0000-4000-8000-000000000002', '2031-02-02T12:00:00Z', 'fixture', 'T', '1', repeat('7',64), 1, repeat('8',64), repeat('9',64), repeat('a',64), 1, 'c1410000-0000-4000-8000-000000000002', repeat('b',64), 'c1420000-0000-4000-8000-000000000002', repeat('c',64)),
  ('c1400000-0000-4000-8000-000000000003', 'LWS-OFF-2031-0103', 1, 'ISSUED', 'c1300000-0000-4000-8000-000000000003', '2031-02-03T12:00:00Z', 'fixture', 'T', '1', repeat('d',64), 1, repeat('e',64), repeat('f',64), repeat('0',64), 1, 'c1410000-0000-4000-8000-000000000003', repeat('1',64), 'c1420000-0000-4000-8000-000000000003', repeat('2',64));

create function pg_temp.customer_request_acceptance_payload_v1(
  p_issuance_id uuid,
  p_quotation_number text,
  p_identity_sha256 text,
  p_generation_sha256 text,
  p_template_sha256 text,
  p_docx_sha256 text,
  p_acceptance_terms_sha256 text,
  p_accepting_name text,
  p_accepting_email text,
  p_accepting_organization text,
  p_accepted_at timestamptz
)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'acceptance_contract_version', 1,
    'issuance_id', p_issuance_id,
    'quotation_number', p_quotation_number,
    'quotation_version', 1,
    'customer_identity_sha256', p_identity_sha256,
    'generation_payload_sha256', p_generation_sha256,
    'template', jsonb_build_object(
      'template_id', 'T',
      'template_version', '1',
      'template_sha256', p_template_sha256
    ),
    'docx', jsonb_build_object('sha256', p_docx_sha256, 'bytes', 1),
    'acceptance_terms', jsonb_build_object(
      'terms_id', 'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT',
      'terms_version', '1.0.0-technical',
      'terms_sha256', p_acceptance_terms_sha256
    ),
    'actor', jsonb_build_object(
      'name', p_accepting_name,
      'email', p_accepting_email,
      'organization', p_accepting_organization,
      'role', 'owner'
    ),
    'authority_declaration', true,
    'accepted_at', to_char(p_accepted_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  )
$$;

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
  fixture.acceptance_id,
  fixture.issuance_id,
  fixture.quotation_number,
  1,
  fixture.identity_sha256,
  fixture.organization,
  fixture.generation_sha256,
  'T',
  '1',
  fixture.template_sha256,
  fixture.docx_sha256,
  1,
  1,
  'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT',
  '1.0.0-technical',
  fixture.terms_sha256,
  fixture.accepting_name,
  fixture.accepting_email,
  fixture.organization,
  'owner',
  true,
  payload.value,
  public.quotation_acceptance_payload_sha256_v1(payload.value),
  fixture.semantic_fingerprint,
  fixture.accepted_at,
  fixture.accepted_at
from (values
  ('c1500000-0000-4000-8000-000000000001'::uuid, 'c1400000-0000-4000-8000-000000000001'::uuid, 'LWS-OFF-2031-0101', repeat('1',64), repeat('3',64), repeat('1',64), repeat('4',64), repeat('5',64), 'A', 'a@example.test', 'A BV', repeat('7',64), '2031-02-01T13:00:00Z'::timestamptz),
  ('c1500000-0000-4000-8000-000000000002'::uuid, 'c1400000-0000-4000-8000-000000000002'::uuid, 'LWS-OFF-2031-0102', repeat('2',64), repeat('9',64), repeat('7',64), repeat('a',64), repeat('b',64), 'B', 'b@example.test', 'B BV', repeat('d',64), '2031-02-02T13:00:00Z'::timestamptz),
  ('c1500000-0000-4000-8000-000000000003'::uuid, 'c1400000-0000-4000-8000-000000000003'::uuid, 'LWS-OFF-2031-0103', repeat('3',64), repeat('f',64), repeat('d',64), repeat('0',64), repeat('1',64), 'C', 'c@example.test', 'C BV', repeat('3',64), '2031-02-03T13:00:00Z'::timestamptz)
) as fixture(
  acceptance_id, issuance_id, quotation_number, identity_sha256,
  generation_sha256, template_sha256, docx_sha256, terms_sha256,
  accepting_name, accepting_email, organization, semantic_fingerprint, accepted_at
)
cross join lateral (
  select pg_temp.customer_request_acceptance_payload_v1(
    fixture.issuance_id, fixture.quotation_number, fixture.identity_sha256,
    fixture.generation_sha256, fixture.template_sha256, fixture.docx_sha256,
    fixture.terms_sha256, fixture.accepting_name, fixture.accepting_email,
    fixture.organization, fixture.accepted_at
  ) as value
) as payload;

insert into public.commercial_customers(customer_id, acceptance_id, identity_sha256) values
  ('c1600000-0000-4000-8000-000000000001', 'c1500000-0000-4000-8000-000000000001', repeat('1',64)),
  ('c1600000-0000-4000-8000-000000000002', 'c1500000-0000-4000-8000-000000000002', repeat('2',64)),
  ('c1600000-0000-4000-8000-000000000003', 'c1500000-0000-4000-8000-000000000003', repeat('3',64));

insert into public.commercial_projects(
  project_id, customer_id, quotation_issuance_id, acceptance_id,
  accepted_total_minor, currency, m1_minor, m2_minor, m3_minor, current_state, revision
) values
  ('c1700000-0000-4000-8000-000000000001', 'c1600000-0000-4000-8000-000000000001', 'c1400000-0000-4000-8000-000000000001', 'c1500000-0000-4000-8000-000000000001', 10000, 'EUR', 4000, 4000, 2000, 'PROJECT_RELEASED', 1),
  ('c1700000-0000-4000-8000-000000000002', 'c1600000-0000-4000-8000-000000000002', 'c1400000-0000-4000-8000-000000000002', 'c1500000-0000-4000-8000-000000000002', 10000, 'EUR', 4000, 4000, 2000, 'PROJECT_RELEASED', 1),
  ('c1700000-0000-4000-8000-000000000003', 'c1600000-0000-4000-8000-000000000003', 'c1400000-0000-4000-8000-000000000003', 'c1500000-0000-4000-8000-000000000003', 10000, 'EUR', 4000, 4000, 2000, 'PROJECT_RELEASED', 1);

insert into public.customer_feedback(
  feedback_id, project_id, preview_access_id, feedback_type,
  subject, customer_message, status
) values
  ('c1800000-0000-4000-8000-000000000001', 'c1700000-0000-4000-8000-000000000001', 'c1810000-0000-4000-8000-000000000001', 'CONTENT', 'A', 'A message', 'NEW'),
  ('c1800000-0000-4000-8000-000000000002', 'c1700000-0000-4000-8000-000000000002', 'c1810000-0000-4000-8000-000000000002', 'CONTENT', 'B', 'B message', 'NEW');

insert into public.change_orders(
  change_order_id, project_id, original_quotation_issuance_id, feedback_id,
  change_request_reference, status
) values
  ('c1900000-0000-4000-8000-000000000001', 'c1700000-0000-4000-8000-000000000001', 'c1400000-0000-4000-8000-000000000001', 'c1800000-0000-4000-8000-000000000001', 'LWS-WIJ-2031-0001', 'ACCEPTED'),
  ('c1900000-0000-4000-8000-000000000002', 'c1700000-0000-4000-8000-000000000002', 'c1400000-0000-4000-8000-000000000002', 'c1800000-0000-4000-8000-000000000002', 'LWS-WIJ-2031-0002', 'PROPOSED');

set local session_replication_role = origin;

select throws_ok(
  $$select lws_internal.create_customer_request_core_v1('c1100003-0000-4000-8000-000000000003','c1600000-0000-4000-8000-000000000003','c1700000-0000-4000-8000-000000000003',null,null,'ca000000-0000-4000-8000-000000000001','{"source":"CUSTOMER_PORTAL","request_type":"OTHER","title":"Not production","description":"No","submitted_at":"2031-02-03T14:00:00Z","submitter_type":"CUSTOMER"}'::jsonb)$$,
  '23514', 'PRODUCTION_QUOTE_REQUEST_REQUIRED', 'non-production quote request is rejected'
);
select throws_ok(
  $$select lws_internal.create_customer_request_core_v1('c1100000-0000-4000-8000-000000000001','c1600000-0000-4000-8000-000000000002','c1700000-0000-4000-8000-000000000001',null,null,'ca000000-0000-4000-8000-000000000002','{"source":"CUSTOMER_PORTAL","request_type":"OTHER","title":"Wrong customer","description":"No","submitted_at":"2031-02-01T14:00:00Z","submitter_type":"CUSTOMER"}'::jsonb)$$,
  '23514', 'CUSTOMER_REQUEST_BINDING_MISMATCH', 'project to customer mismatch is rejected'
);
select throws_ok(
  $$select lws_internal.create_customer_request_core_v1('c1100002-0000-4000-8000-000000000002','c1600000-0000-4000-8000-000000000001','c1700000-0000-4000-8000-000000000001',null,null,'ca000000-0000-4000-8000-000000000003','{"source":"CUSTOMER_PORTAL","request_type":"OTHER","title":"Wrong quote","description":"No","submitted_at":"2031-02-01T14:00:00Z","submitter_type":"CUSTOMER"}'::jsonb)$$,
  '23514', 'CUSTOMER_REQUEST_BINDING_MISMATCH', 'project to quote request chain mismatch is rejected'
);
select throws_ok(
  $$select lws_internal.create_customer_request_core_v1('c1100000-0000-4000-8000-000000000001','c1600000-0000-4000-8000-000000000001','c1700000-0000-4000-8000-000000000001','c1800000-0000-4000-8000-000000000002',null,'ca000000-0000-4000-8000-000000000004','{"source":"CUSTOMER_FEEDBACK","request_type":"CONTENT_CHANGE","title":"Wrong feedback","description":"No","submitted_at":"2031-02-01T14:00:00Z","submitter_type":"CUSTOMER"}'::jsonb)$$,
  '23514', 'CUSTOMER_REQUEST_FEEDBACK_MISMATCH', 'feedback from another project is rejected'
);
select throws_ok(
  $$select lws_internal.create_customer_request_core_v1('c1100000-0000-4000-8000-000000000001','c1600000-0000-4000-8000-000000000001','c1700000-0000-4000-8000-000000000001',null,'c1900000-0000-4000-8000-000000000002','ca000000-0000-4000-8000-000000000005','{"source":"OPERATOR","request_type":"NEW_FEATURE","title":"Wrong change order","description":"No","submitted_at":"2031-02-01T14:00:00Z","submitter_type":"OPERATOR"}'::jsonb)$$,
  '23514', 'CUSTOMER_REQUEST_CHANGE_ORDER_MISMATCH', 'change order from another project and issuance is rejected'
);
select throws_ok(
  $$select lws_internal.create_customer_request_core_v1('c1100000-0000-4000-8000-000000000001','c1600000-0000-4000-8000-000000000001','c1700000-0000-4000-8000-000000000001',null,null,'ca000000-0000-4000-8000-000000000006','{"request_reference":"LWS-VRZ-2031-9999","source":"OPERATOR","request_type":"OTHER","title":"Injected reference","description":"No","submitted_at":"2031-02-01T14:00:00Z","submitter_type":"OPERATOR"}'::jsonb)$$,
  '22023', 'CLIENT_REQUEST_REFERENCE_FORBIDDEN', 'client-supplied request reference is rejected'
);
select throws_ok(
  $$select lws_internal.create_customer_request_core_v1('c1100000-0000-4000-8000-000000000001','c1600000-0000-4000-8000-000000000001','c1700000-0000-4000-8000-000000000001',null,null,'ca000000-0000-4000-8000-000000000007','{"source":"CUSTOMER_PORTAL","request_type":"INVALID","title":"Invalid type","description":"No","submitted_at":"2031-02-01T14:00:00Z","submitter_type":"CUSTOMER"}'::jsonb)$$,
  '23514', 'INVALID_CUSTOMER_REQUEST', 'unknown request type is rejected'
);

create temporary table created_request_a as
select lws_internal.create_customer_request_core_v1(
  'c1100000-0000-4000-8000-000000000001',
  'c1600000-0000-4000-8000-000000000001',
  'c1700000-0000-4000-8000-000000000001',
  'c1800000-0000-4000-8000-000000000001', null,
  'ca100000-0000-4000-8000-000000000001',
  '{"source":"CUSTOMER_FEEDBACK","request_type":"CONTENT_CHANGE","title":"Hero text aanpassen","description":"Pas de publieke hero aan.","priority":"HIGH","submitted_at":"2030-12-31T23:00:00Z","submitter_type":"CUSTOMER"}'::jsonb
) as result;

select matches((select result->>'request_reference' from created_request_a), '^LWS-VRZ-2031-0001$', 'Brussels year and first annual sequence determine the reference');
select is((select result->>'status' from created_request_a), 'NEW', 'creation starts in NEW');
select is((select (result->>'revision')::bigint from created_request_a), 0::bigint, 'creation starts at revision zero');
select is((select count(*)::integer from public.customer_request_events where request_id = (select (result->>'request_id')::uuid from created_request_a) and event_type = 'CREATED' and request_revision = 0), 1, 'creation appends one revision-zero event');
select is((select count(*)::integer from lws_internal.customer_request_commands where idempotency_key = 'ca100000-0000-4000-8000-000000000001'), 1, 'creation records one private command');

create temporary table replay_request_a as
select lws_internal.create_customer_request_core_v1(
  'c1100000-0000-4000-8000-000000000001',
  'c1600000-0000-4000-8000-000000000001',
  'c1700000-0000-4000-8000-000000000001',
  'c1800000-0000-4000-8000-000000000001', null,
  'ca100000-0000-4000-8000-000000000001',
  '{"source":"CUSTOMER_FEEDBACK","request_type":"CONTENT_CHANGE","title":"Hero text aanpassen","description":"Pas de publieke hero aan.","priority":"HIGH","submitted_at":"2030-12-31T23:00:00Z","submitter_type":"CUSTOMER"}'::jsonb
) as result;
select ok(
  (select result - 'replayed' from replay_request_a) = (select result - 'replayed' from created_request_a)
  and (select (result->>'replayed')::boolean from replay_request_a),
  'identical create replay returns the original result with replayed true'
);
select throws_ok(
  $$select lws_internal.create_customer_request_core_v1('c1100000-0000-4000-8000-000000000001','c1600000-0000-4000-8000-000000000001','c1700000-0000-4000-8000-000000000001',null,null,'ca100000-0000-4000-8000-000000000001','{"source":"OPERATOR","request_type":"OTHER","title":"Different","description":"Different","submitted_at":"2031-01-01T00:00:00Z","submitter_type":"OPERATOR"}'::jsonb)$$,
  'P0001', 'IDEMPOTENCY_CONFLICT', 'same create key with different normalized input conflicts'
);

create temporary table created_request_b as
select lws_internal.create_customer_request_core_v1(
  'c1100000-0000-4000-8000-000000000001',
  'c1600000-0000-4000-8000-000000000001',
  'c1700000-0000-4000-8000-000000000001', null, null,
  'ca100000-0000-4000-8000-000000000002',
  '{"source":"OPERATOR","request_type":"TECHNICAL_CHANGE","title":"Caching aanpassen","description":"Technische wijziging.","submitted_at":"2031-01-01T00:00:01Z","submitter_type":"OPERATOR"}'::jsonb
) as result;
select is(
  right((select result->>'request_reference' from created_request_b), 4)::integer,
  right((select result->>'request_reference' from created_request_a), 4)::integer + 1,
  'separate requests receive monotonic annual references'
);
select throws_ok(
  $$update public.customer_requests set request_reference = 'LWS-VRZ-2031-9999' where request_id = (select (result->>'request_id')::uuid from created_request_a)$$,
  '23514', 'CUSTOMER_REQUEST_REFERENCE_IMMUTABLE', 'request reference cannot be changed'
);
select throws_ok(
  $$update public.customer_requests set request_reference = null where request_id = (select (result->>'request_id')::uuid from created_request_a)$$,
  '23514', 'CUSTOMER_REQUEST_REFERENCE_IMMUTABLE', 'request reference cannot be removed'
);

create temporary table first_transition as
select lws_internal.transition_customer_request_core_v1(
  (select (result->>'request_id')::uuid from created_request_a),
  'TRIAGE', 0, 'ca200000-0000-4000-8000-000000000001', '{"priority":"URGENT"}'::jsonb
) as result;
select ok(
  (select result->>'status' = 'TRIAGED' and (result->>'revision')::bigint = 1 from first_transition)
  and (select status = 'TRIAGED' and priority = 'URGENT' and revision = 1 from public.customer_requests where request_id = (select (result->>'request_id')::uuid from created_request_a)),
  'triage changes status and priority with exactly one revision increment'
);
select is((select event_type from public.customer_request_events where request_id = (select (result->>'request_id')::uuid from created_request_a) and request_revision = 1), 'TRIAGED', 'triage appends the matching event');

create temporary table transition_snapshot as
select updated_at, (select count(*) from public.customer_request_events where request_id = request.request_id) as event_count
from public.customer_requests as request
where request_id = (select (result->>'request_id')::uuid from created_request_a);
create temporary table replay_transition as
select lws_internal.transition_customer_request_core_v1(
  (select (result->>'request_id')::uuid from created_request_a),
  'TRIAGE', 0, 'ca200000-0000-4000-8000-000000000001', '{"priority":"URGENT"}'::jsonb
) as result;
select ok(
  (select (result->>'replayed')::boolean from replay_transition)
  and (select updated_at from public.customer_requests where request_id = (select (result->>'request_id')::uuid from created_request_a)) = (select updated_at from transition_snapshot)
  and (select count(*) from public.customer_request_events where request_id = (select (result->>'request_id')::uuid from created_request_a)) = (select event_count from transition_snapshot),
  'transition replay changes neither updated_at nor event history'
);
select throws_ok(
  $$select lws_internal.transition_customer_request_core_v1((select (result->>'request_id')::uuid from created_request_a),'START',0,'ca200000-0000-4000-8000-000000000002','{}'::jsonb)$$,
  '40001', 'CONCURRENT_MODIFICATION', 'stale expected revision is rejected'
);
select throws_ok(
  $$select lws_internal.transition_customer_request_core_v1((select (result->>'request_id')::uuid from created_request_a),'RESOLVE',1,'ca200000-0000-4000-8000-000000000003','{"resolution_summary":"Too early"}'::jsonb)$$,
  'P0001', 'INVALID_CUSTOMER_REQUEST_TRANSITION', 'TRIAGED cannot resolve directly'
);
select lives_ok(
  $$select lws_internal.transition_customer_request_core_v1((select (result->>'request_id')::uuid from created_request_a),'START',1,'ca200000-0000-4000-8000-000000000004','{}'::jsonb)$$,
  'TRIAGED transitions to IN_PROGRESS'
);
select lives_ok(
  $$select lws_internal.transition_customer_request_core_v1((select (result->>'request_id')::uuid from created_request_a),'REQUIRE_CUSTOMER_RESPONSE',2,'ca200000-0000-4000-8000-000000000005','{}'::jsonb)$$,
  'IN_PROGRESS transitions to WAITING_CUSTOMER'
);
select lives_ok(
  $$select lws_internal.transition_customer_request_core_v1((select (result->>'request_id')::uuid from created_request_a),'RESUME',3,'ca200000-0000-4000-8000-000000000006','{}'::jsonb)$$,
  'WAITING_CUSTOMER transitions back to IN_PROGRESS'
);
select lives_ok(
  $$select lws_internal.transition_customer_request_core_v1((select (result->>'request_id')::uuid from created_request_a),'SIGNAL_SCOPE_IMPACT',4,'ca200000-0000-4000-8000-000000000007','{"linked_change_order_id":"c1900000-0000-4000-8000-000000000001"}'::jsonb)$$,
  'IN_PROGRESS transitions to WAITING_CHANGE_ORDER with a coherent link'
);
select lives_ok(
  $$select lws_internal.transition_customer_request_core_v1((select (result->>'request_id')::uuid from created_request_a),'ACCEPT_CHANGE_ORDER',5,'ca200000-0000-4000-8000-000000000008','{}'::jsonb)$$,
  'WAITING_CHANGE_ORDER resumes only for its accepted coherent change order'
);
select lives_ok(
  $$select lws_internal.transition_customer_request_core_v1((select (result->>'request_id')::uuid from created_request_a),'RESOLVE',6,'ca200000-0000-4000-8000-000000000009','{"resolution_summary":"Hero aangepast en gevalideerd."}'::jsonb)$$,
  'IN_PROGRESS transitions to RESOLVED with a resolution'
);
select ok(
  (select status = 'RESOLVED' and revision = 7 and resolution_summary = 'Hero aangepast en gevalideerd.' and resolved_at is not null from public.customer_requests where request_id = (select (result->>'request_id')::uuid from created_request_a))
  and (select array_agg(event_type order by request_revision) = array['CREATED','TRIAGED','STARTED','CUSTOMER_RESPONSE_REQUIRED','CUSTOMER_WAIT_ENDED','SCOPE_IMPACT_SIGNALED','CHANGE_ORDER_ACCEPTED','RESOLVED']::text[] from public.customer_request_events where request_id = (select (result->>'request_id')::uuid from created_request_a)),
  'successful lifecycle stores exact revisions and event vocabulary'
);
select throws_ok(
  $$select lws_internal.transition_customer_request_core_v1((select (result->>'request_id')::uuid from created_request_a),'CANCEL',7,'ca200000-0000-4000-8000-000000000010','{}'::jsonb)$$,
  'P0001', 'CUSTOMER_REQUEST_TERMINAL', 'RESOLVED is terminal'
);

select lives_ok(
  $$select lws_internal.transition_customer_request_core_v1((select (result->>'request_id')::uuid from created_request_b),'CANCEL',0,'ca200000-0000-4000-8000-000000000011','{}'::jsonb)$$,
  'any non-terminal request can be cancelled'
);
select throws_ok(
  $$select lws_internal.transition_customer_request_core_v1((select (result->>'request_id')::uuid from created_request_b),'TRIAGE',1,'ca200000-0000-4000-8000-000000000012','{}'::jsonb)$$,
  'P0001', 'CUSTOMER_REQUEST_TERMINAL', 'CANCELLED is terminal'
);

select throws_ok(
  $$insert into public.customer_request_events(request_id,event_type,request_revision,payload) values ((select (result->>'request_id')::uuid from created_request_a),'CREATED',99,'{"token":"secret"}'::jsonb)$$,
  '23514', 'CUSTOMER_REQUEST_EVENT_PAYLOAD_UNSAFE', 'event payload rejects token material'
);
select throws_ok(
  $$insert into public.customer_request_events(request_id,event_type,request_revision,payload) values ((select (result->>'request_id')::uuid from created_request_a),'CREATED',99,'{"customer_content":"full content"}'::jsonb)$$,
  '23514', 'CUSTOMER_REQUEST_EVENT_PAYLOAD_UNSAFE', 'event payload rejects full customer content'
);
select throws_ok(
  $$insert into public.customer_request_events(request_id,event_type,request_revision,payload) values ((select (result->>'request_id')::uuid from created_request_a),'CREATED',99,jsonb_build_object('summary',repeat('x',2049)))$$,
  '23514', 'CUSTOMER_REQUEST_EVENT_PAYLOAD_UNSAFE', 'event payload is size bounded'
);
select throws_ok(
  $$update public.customer_request_events set payload = '{}'::jsonb where request_id = (select (result->>'request_id')::uuid from created_request_a)$$,
  '55000', 'CUSTOMER_REQUEST_EVENTS_APPEND_ONLY', 'event history cannot be updated'
);
select throws_ok(
  $$delete from public.customer_request_events where request_id = (select (result->>'request_id')::uuid from created_request_a)$$,
  '55000', 'CUSTOMER_REQUEST_EVENTS_APPEND_ONLY', 'event history cannot be deleted'
);
select throws_ok(
  $$update lws_internal.customer_request_commands set result_payload = '{}'::jsonb where idempotency_key = 'ca100000-0000-4000-8000-000000000001'$$,
  '55000', 'CUSTOMER_REQUEST_COMMANDS_APPEND_ONLY', 'command ledger cannot be updated'
);
select throws_ok(
  $$delete from lws_internal.customer_request_commands where idempotency_key = 'ca100000-0000-4000-8000-000000000001'$$,
  '55000', 'CUSTOMER_REQUEST_COMMANDS_APPEND_ONLY', 'command ledger cannot be deleted'
);
select throws_ok(
  $$update public.customer_requests set status = 'NEW' where request_id = (select (result->>'request_id')::uuid from created_request_a)$$,
  '55000', 'DIRECT_CUSTOMER_REQUEST_WRITE_FORBIDDEN', 'direct aggregate status writes are denied'
);
select throws_ok(
  $$delete from public.customer_requests where request_id = (select (result->>'request_id')::uuid from created_request_a)$$,
  '55000', 'DIRECT_CUSTOMER_REQUEST_WRITE_FORBIDDEN', 'direct aggregate deletion is denied'
);

select is(
  extensions.dblink_connect(
    'customer_request_concurrency_setup',
    'host=' || host(inet_server_addr()) || ' port=' || current_setting('port')
      || ' dbname=' || current_database()
      || ' user=postgres password=postgres application_name=customer_request_concurrency_setup'
  ),
  'OK', 'concurrency setup connection opens'
);
select lives_ok(
  $test$select extensions.dblink_exec(
    'customer_request_concurrency_setup',
    $setup$
      set session_replication_role = replica;
      insert into public.customer_requests(
        request_id, request_reference, quote_request_id, customer_id, project_id,
        source, request_type, title, description, status, submitted_at, submitter_type
      ) values (
        'cb000000-0000-4000-8000-000000000001', 'LWS-VRZ-2099-9998',
        'c1100000-0000-4000-8000-000000000001', 'c1600000-0000-4000-8000-000000000001',
        'c1700000-0000-4000-8000-000000000001', 'OPERATOR', 'OTHER',
        'Concurrent request', 'Concurrent transition fixture.', 'NEW',
        '2099-01-01T00:00:00Z', 'OPERATOR'
      );
      set session_replication_role = origin;
    $setup$
  )$test$,
  'committed concurrency fixture is created outside the pgTAP transaction'
);
select is(extensions.dblink_connect('customer_request_race_a', 'host=' || host(inet_server_addr()) || ' port=' || current_setting('port') || ' dbname=' || current_database() || ' user=postgres password=postgres application_name=customer_request_race_a'), 'OK', 'first race connection opens');
select is(extensions.dblink_connect('customer_request_race_b', 'host=' || host(inet_server_addr()) || ' port=' || current_setting('port') || ' dbname=' || current_database() || ' user=postgres password=postgres application_name=customer_request_race_b'), 'OK', 'second race connection opens');
create temporary table customer_request_race_pids(backend_pid integer not null) on commit drop;
insert into customer_request_race_pids
select backend_pid from extensions.dblink('customer_request_race_b', 'select pg_backend_pid()') as connection(backend_pid integer);
select is(extensions.dblink_exec('customer_request_race_a', 'begin'), 'BEGIN', 'first race transaction starts');
select is(
  (select result->>'revision' from extensions.dblink(
    'customer_request_race_a',
    $$select lws_internal.transition_customer_request_core_v1('cb000000-0000-4000-8000-000000000001','TRIAGE',0,'cb100000-0000-4000-8000-000000000001','{}'::jsonb)$$
  ) as transition(result jsonb)),
  '1', 'first transition succeeds while retaining its row lock'
);
select ok(
  extensions.dblink_send_query(
    'customer_request_race_b',
    $$select lws_internal.transition_customer_request_core_v1('cb000000-0000-4000-8000-000000000001','TRIAGE',0,'cb100000-0000-4000-8000-000000000002','{}'::jsonb)$$
  ) = 1,
  'second concurrent transition starts'
);
select ok(pg_temp.wait_for_customer_request_lock_v1((select backend_pid from customer_request_race_pids)), 'second transition waits on the aggregate row lock');
select is(extensions.dblink_exec('customer_request_race_a', 'commit'), 'COMMIT', 'first transition commits first');
select throws_ok(
  $$select * from extensions.dblink_get_result('customer_request_race_b') as transition(result jsonb)$$,
  '40001', 'CONCURRENT_MODIFICATION', 'second transition resumes and loses on expected revision'
);
select ok(
  (select status = 'TRIAGED' and revision = 1 from public.customer_requests where request_id = 'cb000000-0000-4000-8000-000000000001')
  and (select count(*) = 1 from public.customer_request_events where request_id = 'cb000000-0000-4000-8000-000000000001'),
  'concurrent race leaves one winner, one revision, and one event'
);
select is(extensions.dblink_disconnect('customer_request_race_a'), 'OK', 'first race connection closes');
select is(extensions.dblink_disconnect('customer_request_race_b'), 'OK', 'second race connection closes');
select lives_ok(
  $test$select extensions.dblink_exec(
    'customer_request_concurrency_setup',
    $cleanup$
      set session_replication_role = replica;
      delete from lws_internal.customer_request_commands where request_id = 'cb000000-0000-4000-8000-000000000001';
      delete from public.customer_request_events where request_id = 'cb000000-0000-4000-8000-000000000001';
      delete from public.customer_requests where request_id = 'cb000000-0000-4000-8000-000000000001';
      set session_replication_role = origin;
    $cleanup$
  )$test$,
  'committed concurrency fixture is removed'
);
select is(extensions.dblink_disconnect('customer_request_concurrency_setup'), 'OK', 'concurrency setup connection closes');

select * from finish();
rollback;