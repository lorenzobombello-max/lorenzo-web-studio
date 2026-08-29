begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(34);

select has_function(
  'public', 'get_sdf_finance_portfolio_v1', array[]::text[],
  'SDF finance portfolio RPC exists'
);
select ok(
  exists (
    select 1 from pg_proc
    where oid = 'public.get_sdf_finance_portfolio_v1()'::regprocedure
      and prosecdef
      and provolatile = 's'
      and proconfig = array['search_path=public, auth, pg_catalog']
  ),
  'portfolio is stable SECURITY DEFINER with a fixed safe search_path'
);
select ok(
  has_function_privilege('authenticated', 'public.get_sdf_finance_portfolio_v1()', 'execute')
  and not has_function_privilege('anon', 'public.get_sdf_finance_portfolio_v1()', 'execute')
  and not has_function_privilege('service_role', 'public.get_sdf_finance_portfolio_v1()', 'execute')
  and not has_function_privilege('public', 'public.get_sdf_finance_portfolio_v1()', 'execute'),
  'only authenticated receives entrypoint execute privilege'
);
select ok(
  not has_table_privilege('authenticated', 'public.sdf_accepted_commercial_terms', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.sdf_milestone_one_obligations', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.sdf_m1_invoice_candidates', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.sdf_m1_invoice_issuances', 'select,insert,update,delete'),
  'browser roles retain no direct SDF finance table privileges'
);
select ok(
  (select prosrc !~* '\m(insert|update|delete|merge|truncate)\M'
   from pg_proc where oid = 'public.get_sdf_finance_portfolio_v1()'::regprocedure),
  'portfolio runtime contains no mutation statement'
);

insert into auth.users(id, email) values
  ('fa000000-0000-4000-8000-000000000001', 'sdf-finance-owner@example.test'),
  ('fa000000-0000-4000-8000-000000000002', 'sdf-finance-admin@example.test'),
  ('fa000000-0000-4000-8000-000000000003', 'sdf-finance-operator@example.test'),
  ('fa000000-0000-4000-8000-000000000004', 'sdf-finance-disabled@example.test'),
  ('fa000000-0000-4000-8000-000000000005', 'sdf-finance-unknown@example.test');

insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('fa100000-0000-4000-8000-000000000001', 'fa000000-0000-4000-8000-000000000001', 'SDF Finance Owner', 'owner', 'ACTIVE'),
  ('fa100000-0000-4000-8000-000000000002', 'fa000000-0000-4000-8000-000000000002', 'SDF Finance Admin', 'admin', 'ACTIVE'),
  ('fa100000-0000-4000-8000-000000000003', 'fa000000-0000-4000-8000-000000000003', 'SDF Finance Operator', 'operator', 'ACTIVE'),
  ('fa100000-0000-4000-8000-000000000004', 'fa000000-0000-4000-8000-000000000004', 'SDF Finance Disabled', 'owner', 'DISABLED');

select set_config('request.jwt.claim.sub', 'fa000000-0000-4000-8000-000000000001', true);
select lives_ok($$select public.get_sdf_finance_portfolio_v1()$$, 'active owner can read the portfolio');
select is(public.get_sdf_finance_portfolio_v1()->>'scope', 'sdf', 'zero state preserves SDF scope');
select is((public.get_sdf_finance_portfolio_v1()->>'project_count')::integer, 0, 'zero state has zero projects');
select is(
  jsonb_build_array(
    public.get_sdf_finance_portfolio_v1()->'currency_totals',
    public.get_sdf_finance_portfolio_v1()->'projects'
  ),
  '[[],[]]'::jsonb,
  'zero state returns empty arrays without fake data'
);
select ok(
  (public.get_sdf_finance_portfolio_v1()->>'invoice_projection_available')::boolean
  and not (public.get_sdf_finance_portfolio_v1()->>'expected_payment_available')::boolean
  and not (public.get_sdf_finance_portfolio_v1()->>'payment_evidence_available')::boolean
  and not (public.get_sdf_finance_portfolio_v1()->>'confirmed_received_available')::boolean
  and not (public.get_sdf_finance_portfolio_v1()->>'outstanding_projection_available')::boolean
  and not (public.get_sdf_finance_portfolio_v1()->>'overdue_projection_available')::boolean
  and not (public.get_sdf_finance_portfolio_v1()->>'upcoming_projection_available')::boolean
  and not (public.get_sdf_finance_portfolio_v1()->>'recurring_amount_projection_available')::boolean,
  'availability flags use exact true and false semantics'
);

select set_config('request.jwt.claim.sub', 'fa000000-0000-4000-8000-000000000002', true);
select throws_ok($$select public.get_sdf_finance_portfolio_v1()$$, '42501', 'SDF_FINANCE_PORTFOLIO_OWNER_REQUIRED', 'active admin is denied');
select set_config('request.jwt.claim.sub', 'fa000000-0000-4000-8000-000000000003', true);
select throws_ok($$select public.get_sdf_finance_portfolio_v1()$$, '42501', 'SDF_FINANCE_PORTFOLIO_OWNER_REQUIRED', 'ordinary operator is denied');
select set_config('request.jwt.claim.sub', 'fa000000-0000-4000-8000-000000000004', true);
select throws_ok($$select public.get_sdf_finance_portfolio_v1()$$, '42501', 'OPERATOR_DISABLED', 'inactive owner is denied');
select set_config('request.jwt.claim.sub', 'fa000000-0000-4000-8000-000000000005', true);
select throws_ok($$select public.get_sdf_finance_portfolio_v1()$$, '42501', 'UNKNOWN_OPERATOR', 'unknown human is denied');
select set_config('request.jwt.claim.sub', '', true);
select throws_ok($$select public.get_sdf_finance_portfolio_v1()$$, '42501', 'HUMAN_JWT_REQUIRED', 'missing human JWT is denied');

insert into public.quote_requests (
  id, application_reference, record_classification, request_kind, sdf_package,
  name, email, website_type, budget, timing, description, privacy_consent, status
) values
  ('fa200001-0000-4000-8000-000000000001', 'LWS-AAN-2099-7001', 'production', 'slimme_documentenflow', 'start', 'Portfolio Start', 'start@example.test', null, null, null, 'Included START.', true, 'approved'),
  ('fa200002-0000-4000-8000-000000000002', 'LWS-AAN-2099-7002', 'production', 'slimme_documentenflow', 'groei', 'Portfolio Groei', 'groei@example.test', null, null, null, 'Included GROEI.', true, 'approved'),
  ('fa200003-0000-4000-8000-000000000003', null, 'internal_e2e', 'slimme_documentenflow', 'start', 'Internal SDF', 'internal@example.test', null, null, null, 'Excluded internal fixture.', true, 'approved'),
  ('fa200004-0000-4000-8000-000000000004', 'LWS-AAN-2099-7004', 'production', 'slimme_documentenflow', 'start', 'Unaccepted SDF', 'unaccepted@example.test', null, null, null, 'Excluded unaccepted fixture.', true, 'approved'),
  ('fa200005-0000-4000-8000-000000000005', 'LWS-AAN-2099-7005', 'production', 'slimme_documentenflow', 'start', 'Identity SDF', 'identity@example.test', null, null, null, 'Excluded identity-only fixture.', true, 'approved'),
  ('fa200006-0000-4000-8000-000000000006', 'LWS-AAN-2099-7006', 'production', 'website', null, 'Website', 'website@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Excluded Website fixture.', true, 'approved');

insert into public.sdf_quotations(quotation_id, quote_request_id, created_at) values
  ('fa300000-0000-4000-8000-000000000001', 'fa200001-0000-4000-8000-000000000001', '2099-01-01T09:00:00Z'),
  ('fa300000-0000-4000-8000-000000000002', 'fa200002-0000-4000-8000-000000000002', '2099-01-02T09:00:00Z'),
  ('fa300000-0000-4000-8000-000000000003', 'fa200003-0000-4000-8000-000000000003', '2099-01-03T09:00:00Z'),
  ('fa300000-0000-4000-8000-000000000004', 'fa200004-0000-4000-8000-000000000004', '2099-01-04T09:00:00Z');

insert into public.sdf_quotation_documents(
  quotation_id, quotation_date, valid_until, prepared_at, document_reference, document_sha256
) values
  ('fa300000-0000-4000-8000-000000000001', '2099-01-01', '2099-02-01', '2099-01-01T10:00:00Z', 'sdf/portfolio/start.docx', repeat('1',64)),
  ('fa300000-0000-4000-8000-000000000002', '2099-01-02', '2099-02-02', '2099-01-02T10:00:00Z', 'sdf/portfolio/groei.docx', repeat('2',64)),
  ('fa300000-0000-4000-8000-000000000003', '2099-01-03', '2099-02-03', '2099-01-03T10:00:00Z', 'sdf/portfolio/internal.docx', repeat('3',64));

insert into public.sdf_quotation_acceptances(quotation_id, accepted_at, document_reference, document_sha256) values
  ('fa300000-0000-4000-8000-000000000001', '2099-01-05T10:00:00Z', 'sdf/portfolio/start-accepted.docx', repeat('a',64)),
  ('fa300000-0000-4000-8000-000000000002', '2099-01-06T10:00:00Z', 'sdf/portfolio/groei-accepted.docx', repeat('b',64)),
  ('fa300000-0000-4000-8000-000000000003', '2099-01-07T10:00:00Z', 'sdf/portfolio/internal-accepted.docx', repeat('c',64));

insert into public.sdf_projects(project_id, quote_request_id, created_at) values
  ('fa400000-0000-4000-8000-000000000001', 'fa200001-0000-4000-8000-000000000001', '2099-01-08T10:00:00Z'),
  ('fa400000-0000-4000-8000-000000000005', 'fa200005-0000-4000-8000-000000000005', '2099-01-08T11:00:00Z');

select set_config('request.jwt.claim.sub', 'fa000000-0000-4000-8000-000000000001', true);
select public.create_sdf_milestone_one_foundation_v1('fa300000-0000-4000-8000-000000000001', 285000, 'fa500000-0000-4000-8000-000000000001');
select public.create_sdf_milestone_one_foundation_v1('fa300000-0000-4000-8000-000000000002', 570000, 'fa500000-0000-4000-8000-000000000002');
select public.create_sdf_milestone_one_foundation_v1('fa300000-0000-4000-8000-000000000003', 285000, 'fa500000-0000-4000-8000-000000000003');

select is((public.get_sdf_finance_portfolio_v1()->>'project_count')::integer, 2, 'only production accepted SDF dossiers with M1 authority are included');
select ok(
  not exists (
    select 1
    from jsonb_array_elements(public.get_sdf_finance_portfolio_v1()->'projects') as item(value)
    where value->>'quote_request_id' in (
      'fa200003-0000-4000-8000-000000000003',
      'fa200004-0000-4000-8000-000000000004',
      'fa200005-0000-4000-8000-000000000005',
      'fa200006-0000-4000-8000-000000000006'
    )
  ),
  'internal, unaccepted, identity-only, and Website records are excluded'
);
select is(
  (select (value->>'commitment_minor')::bigint from jsonb_array_elements(public.get_sdf_finance_portfolio_v1()->'projects') as item(value) where value->>'sdf_package' = 'start'),
  285000::bigint,
  'accepted START commitment remains exact'
);
select is(
  (select (value->>'m1_obligation_minor')::bigint from jsonb_array_elements(public.get_sdf_finance_portfolio_v1()->'projects') as item(value) where value->>'sdf_package' = 'start'),
  114000::bigint,
  'authoritative START M1 obligation remains exact'
);
select is(
  (select value->>'m1_obligation_status' from jsonb_array_elements(public.get_sdf_finance_portfolio_v1()->'projects') as item(value) where value->>'sdf_package' = 'start'),
  'EXPECTED',
  'M1 state retains obligation semantics'
);
select ok(
  (select value->>'currency' = 'EUR'
     and value->'accepted_at' <> 'null'::jsonb
     and value->'accepted_terms_created_at' <> 'null'::jsonb
     and value->'m1_obligation_created_at' <> 'null'::jsonb
   from jsonb_array_elements(public.get_sdf_finance_portfolio_v1()->'projects') as item(value)
   where value->>'sdf_package' = 'start'),
  'currency and distinct authority dates are preserved'
);
select ok(
  (select value->>'sdf_project_id' = 'fa400000-0000-4000-8000-000000000001'
   from jsonb_array_elements(public.get_sdf_finance_portfolio_v1()->'projects') as item(value)
   where value->>'sdf_package' = 'start')
  and (select value->'sdf_project_id' = 'null'::jsonb
       from jsonb_array_elements(public.get_sdf_finance_portfolio_v1()->'projects') as item(value)
       where value->>'sdf_package' = 'groei'),
  'optional identity-only SDF project does not control finance inclusion'
);
select is(
  public.get_sdf_finance_portfolio_v1()->'currency_totals'->0,
  '{"currency":"EUR","commitment_minor":855000,"m1_obligation_minor":342000,"issued_invoice_minor":0}'::jsonb,
  'currency totals preserve commitment and M1 as separate integer layers'
);
select ok(
  not (public.get_sdf_finance_portfolio_v1()->'currency_totals'->0 ?| array['revenue_minor','income_minor','received_minor','turnover_minor'])
  and not (public.get_sdf_finance_portfolio_v1() ?| array['expected_payment_minor','payment_evidence_minor','confirmed_received_minor','outstanding_minor','overdue_minor','upcoming_minor','recurring_amount_minor']),
  'unavailable payment and revenue totals are absent rather than represented as zero'
);

insert into public.sdf_invoice_template_authorities(
  template_authority_id, document_type, milestone_identity, template_id, template_version,
  document_reference, document_sha256, registration_idempotency_key,
  registration_fingerprint, created_by_operator_id, created_at
) values (
  'fa600000-0000-4000-8000-000000000001', 'INVOICE', 'M1', 'SDF_PORTFOLIO_TEST', '1',
  'sdf/portfolio/template.docx', repeat('d',64), 'fa600000-0000-4000-8000-000000000002',
  repeat('e',64), 'fa100000-0000-4000-8000-000000000001', '2099-01-09T10:00:00Z'
);

insert into public.sdf_m1_invoice_candidates(
  candidate_id, obligation_id, quotation_id, accepted_terms_id, quote_request_id,
  application_reference, template_authority_id, candidate_state, milestone_identity,
  percentage_basis_points, currency, net_amount_minor, accepted_price_basis,
  seller_snapshot, customer_snapshot, bank_snapshot, template_snapshot,
  candidate_payload_sha256, creation_idempotency_key, creation_fingerprint,
  prepared_by_operator_id, prepared_at
)
select
  'fa700000-0000-4000-8000-000000000001', obligation.obligation_id, terms.quotation_id,
  terms.accepted_terms_id, terms.quote_request_id, 'LWS-AAN-2099-7001',
  'fa600000-0000-4000-8000-000000000001', 'PREPARED', 'M1', 4000, 'EUR', 114000,
  'exclusive', '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
  repeat('1',64), 'fa700000-0000-4000-8000-000000000002', repeat('2',64),
  'fa100000-0000-4000-8000-000000000001', '2099-01-10T10:00:00Z'
from public.sdf_accepted_commercial_terms as terms
join public.sdf_milestone_one_obligations as obligation
  on obligation.accepted_terms_id = terms.accepted_terms_id
where terms.quotation_id = 'fa300000-0000-4000-8000-000000000001';

select ok(
  (select value->>'invoice_candidate_state' = 'PREPARED'
     and (value->>'invoice_candidate_net_amount_minor')::bigint = 114000
     and value->>'prepared_at' = '2099-01-10T10:00:00+00:00'
   from jsonb_array_elements(public.get_sdf_finance_portfolio_v1()->'projects') as item(value)
   where value->>'sdf_package' = 'start'),
  'candidate projection retains PREPARED state, amount, and date'
);
select ok(
  (select value->'invoice_issuance_state' = 'null'::jsonb
     and value->'issued_at' = 'null'::jsonb
     and value->'invoice_number' = 'null'::jsonb
   from jsonb_array_elements(public.get_sdf_finance_portfolio_v1()->'projects') as item(value)
   where value->>'sdf_package' = 'start')
  and (public.get_sdf_finance_portfolio_v1()->'currency_totals'->0->>'issued_invoice_minor')::bigint = 0,
  'prepared candidate is not counted as an issued invoice'
);

insert into public.sdf_m1_invoice_issuances(
  issuance_id, candidate_id, invoice_number, issue_year, sequence, issuance_state,
  vat_decision_authority_id, vat_authority_version, vat_authority_sha256,
  vat_treatment, rate_semantics, vat_rate_basis_points, invoice_literal,
  net_amount_minor, vat_amount_minor, gross_amount_minor, issuance_payload_sha256,
  docx_sha256, docx_bytes, pdf_sha256, pdf_bytes, issuance_idempotency_key,
  issuance_fingerprint, issued_by_operator_id, issued_at
)
select
  'fa800000-0000-4000-8000-000000000001', 'fa700000-0000-4000-8000-000000000001',
  'LWS-2099-7001', 2099, 7001, 'ISSUED', vat_decision_authority_id,
  decision_version, authority_sha256, 'EXEMPT', 'NOT_APPLICABLE', 0,
  'Bijzondere vrijstellingsregeling van belasting', 114000, 0, 114000,
  repeat('3',64), repeat('4',64), 4096, repeat('5',64), 2048,
  'fa800000-0000-4000-8000-000000000002', repeat('6',64),
  'fa100000-0000-4000-8000-000000000001', '2099-01-11T10:00:00Z'
from public.quotation_vat_decision_authorities
where vat_decision_authority_id = 'b1030000-0000-4000-8000-000000000001';

select ok(
  (select value->>'invoice_issuance_state' = 'ISSUED'
     and value->>'invoice_number' = 'LWS-2099-7001'
     and (value->>'issued_net_amount_minor')::bigint = 114000
     and (value->>'issued_gross_amount_minor')::bigint = 114000
     and value->>'vat_authority_version' = '1.0.0'
     and value->>'issued_at' = '2099-01-11T10:00:00+00:00'
   from jsonb_array_elements(public.get_sdf_finance_portfolio_v1()->'projects') as item(value)
   where value->>'sdf_package' = 'start'),
  'issued invoice projection retains state, safe reference, amounts, VAT version, and date'
);
select is(
  (public.get_sdf_finance_portfolio_v1()->'currency_totals'->0->>'issued_invoice_minor')::bigint,
  114000::bigint,
  'issued invoice total counts authoritative gross issuance exactly once'
);
select ok(
  (public.get_sdf_finance_portfolio_v1()->'currency_totals'->0->>'commitment_minor')::bigint = 855000
  and (public.get_sdf_finance_portfolio_v1()->'currency_totals'->0->>'m1_obligation_minor')::bigint = 342000
  and (public.get_sdf_finance_portfolio_v1()->'currency_totals'->0->>'issued_invoice_minor')::bigint = 114000,
  'commitment, obligation, and issued invoice are never added into a revenue total'
);
select ok(
  (select count(*) = 1 from pg_constraint
   where conrelid = 'public.sdf_m1_invoice_issuances'::regclass
     and contype = 'u'
     and pg_get_constraintdef(oid) = 'UNIQUE (candidate_id)')
  and (select count(*) = 1 from pg_constraint
       where conrelid = 'public.sdf_m1_invoice_issuances'::regclass
         and contype = 'u'
         and pg_get_constraintdef(oid) = 'UNIQUE (issuance_idempotency_key)'),
  'candidate and idempotency uniqueness prevent duplicate invoice counting'
);
select is(jsonb_array_length(public.get_sdf_finance_portfolio_v1()->'currency_totals'), 1, 'currency aggregation groups rows safely');
select is(public.get_sdf_finance_portfolio_v1(), public.get_sdf_finance_portfolio_v1(), 'portfolio JSON ordering is deterministic');
select ok(
  not exists (
    select 1 from jsonb_array_elements(public.get_sdf_finance_portfolio_v1()->'projects') as item(value)
    where value ?| array['name','company','email','phone','address','billing_address','customer_snapshot','seller_snapshot','bank_snapshot']
  ),
  'project rows expose no unnecessary personal or snapshot data'
);
select is((public.get_sdf_finance_portfolio_v1()->>'project_count')::integer, 2, 'invoice joins do not multiply portfolio rows');

select * from finish();
rollback;