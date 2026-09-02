begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('public','sdf_invoice_number_counters','SDF invoice year counter exists');
select has_table('public','sdf_invoice_template_authorities','existing Drive invoice template bindings have a private authority table');
select has_table('public','sdf_m1_invoice_candidates','policy-neutral M1 invoice candidates have a product-specific table');
select has_table('public','sdf_m1_invoice_issuances','future immutable issuance evidence has a dormant table');
select has_table('public','sdf_m1_payment_receipts','SDF M1 payment receipts have an append-only authority table');
select has_table('public','sdf_m1_project_start_authorities','SDF project start has a separate immutable authority table');
select has_table('public','sdf_invoice_master_bindings','proven Drive invoice master has a singleton authority table');
select has_column('public','sdf_m1_invoice_candidates','application_reference','candidate snapshots the separate human dossier reference');
select has_function('public','allocate_sdf_invoice_number_v1',array['smallint'],'internal SDF invoice number allocator exists');
select has_function('public','register_sdf_invoice_template_authority_v1',array['text','text','text','text','uuid'],'template binding RPC exists');
select has_function('public','prepare_sdf_m1_invoice_candidate_v1',array['uuid','uuid','uuid'],'candidate preparation RPC exists');
select has_function('public','issue_sdf_m1_invoice_v1',array['uuid','smallint','uuid'],'fail-closed issuance boundary exists');
select has_function(
  'public','resolve_sdf_m1_invoice_vat_authority_v1',array['uuid','date'],
  'invoice VAT authority preflight exists'
);
select has_function(
  'public','bind_sdf_quotation_vat_authority_v1',array['uuid','date'],
  'accepted quotation VAT authority binding RPC exists'
);
select has_function(
  'public','issue_sdf_m1_invoice_v2',array['uuid','smallint','uuid','text','bigint','text','bigint'],
  'artifact-aware guarded invoice issuance RPC exists'
);
select has_function(
  'public','record_sdf_m1_payment_receipt_v1',array['uuid','bigint','text','text','uuid'],
  'guarded cumulative SDF M1 payment receipt RPC exists'
);
select has_function(
  'public','get_sdf_m1_payment_state_v1',array['uuid'],
  'server-side SDF M1 payment state projection exists'
);
select has_function(
  'public','authorize_sdf_project_start_v1',array['uuid','uuid','uuid'],
  'full-payment-only SDF project start authority RPC exists'
);
select has_column('public','sdf_m1_invoice_issuances','vat_decision_authority_id','issuance freezes VAT authority ID');
select has_column('public','sdf_m1_invoice_issuances','vat_authority_sha256','issuance freezes VAT authority hash');
select has_column('public','sdf_m1_invoice_issuances','rate_semantics','issuance distinguishes exemption from zero-rate');
select has_column('public','sdf_m1_invoice_issuances','invoice_literal','issuance freezes the official literal');

select ok(
  (select bool_and(relrowsecurity and relforcerowsecurity)
   from pg_class
   where oid in (
     'public.sdf_invoice_number_counters'::regclass,
     'public.sdf_invoice_template_authorities'::regclass,
     'public.sdf_m1_invoice_candidates'::regclass,
     'public.sdf_m1_invoice_issuances'::regclass,
     'public.sdf_invoice_master_bindings'::regclass,
     'public.sdf_m1_payment_receipts'::regclass,
     'public.sdf_m1_project_start_authorities'::regclass
   )),
  'all SDF invoice foundation tables have forced RLS'
);
select results_eq(
  $$select document_reference,drive_file_id,rtrim(document_sha256)
    from public.sdf_invoice_master_bindings$$,
  $$values (
    '03_Algemene_sjablonen/02_Factuursjabloon.docx'::text,
    '1j3yiSWsWermVnPEkNBcKfAGp20E1NvEC'::text,
    '52dc454bec5d0e09fc9f4b85a1f1877b65f7d3aea166ed195da598cb7b4536d6'::text
  )$$,
  'runtime binds the exact proven singleton invoice master path, Drive ID, and SHA-256'
);
select ok(
  not has_table_privilege('anon','public.sdf_m1_invoice_candidates','select')
  and not has_table_privilege('authenticated','public.sdf_m1_invoice_candidates','insert')
  and not has_table_privilege('service_role','public.sdf_m1_invoice_candidates','insert')
  and not has_table_privilege('authenticated','public.sdf_m1_invoice_issuances','insert')
  and not has_table_privilege('authenticated','public.sdf_m1_payment_receipts','insert')
  and not has_table_privilege('service_role','public.sdf_m1_payment_receipts','insert')
  and not has_table_privilege('authenticated','public.sdf_m1_project_start_authorities','insert'),
  'runtime roles cannot read or write private candidate and issuance tables directly'
);
select ok(
  exists(
    select 1
    from pg_constraint
    where conrelid='public.sdf_m1_invoice_issuances'::regclass
      and confrelid='public.sdf_m1_invoice_candidates'::regclass
      and contype='f'
  )
  and exists(
    select 1
    from pg_constraint
    where conrelid='public.sdf_m1_invoice_candidates'::regclass
      and confrelid='public.sdf_milestone_one_obligations'::regclass
      and contype='f'
  ),
  'future invoice identity resolves through candidate to the immutable M1 obligation chain'
);
select ok(
  not exists(
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name in ('sdf_m1_invoice_candidates','sdf_m1_invoice_issuances')
      and column_name in (
        'received_amount_minor','received_at','bank_transaction_reference',
        'payment_state','reconciliation_id','reconciled_at','project_started_at'
      )
  ),
  'invoice foundation contains no RECEIVED, RECONCILED, or project-start contract'
);
select ok(
  has_function_privilege('authenticated','public.prepare_sdf_m1_invoice_candidate_v1(uuid,uuid,uuid)','execute')
  and has_function_privilege('authenticated','public.issue_sdf_m1_invoice_v1(uuid,smallint,uuid)','execute')
  and not has_function_privilege('anon','public.prepare_sdf_m1_invoice_candidate_v1(uuid,uuid,uuid)','execute')
  and not has_function_privilege('service_role','public.prepare_sdf_m1_invoice_candidate_v1(uuid,uuid,uuid)','execute')
  and has_function_privilege('authenticated','public.record_sdf_m1_payment_receipt_v1(uuid,bigint,text,text,uuid)','execute')
  and not has_function_privilege('anon','public.record_sdf_m1_payment_receipt_v1(uuid,bigint,text,text,uuid)','execute')
  and not has_function_privilege('service_role','public.record_sdf_m1_payment_receipt_v1(uuid,bigint,text,text,uuid)','execute')
  and has_function_privilege('authenticated','public.authorize_sdf_project_start_v1(uuid,uuid,uuid)','execute')
  and not has_function_privilege('anon','public.authorize_sdf_project_start_v1(uuid,uuid,uuid)','execute')
  and not has_function_privilege('authenticated','public.allocate_sdf_invoice_number_v1(smallint)','execute'),
  'only authenticated humans enter guarded RPCs and no runtime role can call the allocator'
);

select is(
  (select jsonb_build_array(invoice_number,sequence) from public.allocate_sdf_invoice_number_v1(2099::smallint)),
  '["LWS-2099-0001",1]'::jsonb,
  'first sequence of a calendar year is LWS-YYYY-0001'
);
select is(
  (select jsonb_build_array(invoice_number,sequence) from public.allocate_sdf_invoice_number_v1(2099::smallint)),
  '["LWS-2099-0002",2]'::jsonb,
  'same-year sequence increments exactly once'
);
select is(
  (select jsonb_build_array(invoice_number,sequence) from public.allocate_sdf_invoice_number_v1(2100::smallint)),
  '["LWS-2100-0001",1]'::jsonb,
  'new calendar year resets to sequence 0001'
);
select is((select count(*)::integer from public.sdf_invoice_number_counters),2,'counter has one independent row per issue year');
truncate table public.sdf_invoice_number_counters;

insert into auth.users(id,email) values
  ('f1000000-0000-4000-8000-000000000001','invoice-owner@example.test'),
  ('f1000000-0000-4000-8000-000000000002','invoice-operator@example.test');
insert into public.commercial_operators(operator_id,auth_user_id,display_name,role,status) values
  ('f1100000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000001','Invoice Owner','owner','ACTIVE'),
  ('f1100000-0000-4000-8000-000000000002','f1000000-0000-4000-8000-000000000002','Invoice Operator','operator','ACTIVE');

insert into public.quote_requests(
  id,application_reference,request_kind,sdf_package,name,company,email,customer_type,enterprise_number,
  enterprise_validation_status,vat_number,vat_validation_status,vat_validated_at,billing_address,
  billing_postal_code,billing_city,billing_country,billing_email,website_type,budget,
  timing,description,privacy_consent,status
) values
  (
    'f2000000-0000-4000-8000-000000000001','LWS-AAN-2099-9001','slimme_documentenflow','start','Ada Contact','Ada BV',
    'ada@example.test','business','0123456789','format_valid_not_externally_verified','BE0123456789','valid','2099-01-01T08:00:00Z',
    'Klantstraat 1','9000','Gent','BE','billing@example.test',null,null,null,
    'SDF M1 invoice candidate fixture.',true,'approved'
  );
insert into public.quote_requests(
  id,request_kind,name,email,website_type,budget,timing,description,privacy_consent,status
) values (
  'f2000001-0000-4000-8000-000000000002','website','Website Customer','website@example.test',
  'business','Meer dan EUR 6.000','flexible','Website isolation fixture.',true,'approved'
);
insert into public.quote_requests(
  id,request_kind,sdf_package,name,email,description,privacy_consent,status
) values (
  'f2000002-0000-4000-8000-000000000003','slimme_documentenflow','start','Legacy SDF',
  'legacy-sdf@example.test','Accepted SDF fixture without application reference.',true,'approved'
);
insert into public.quote_request_intakes(
  id,quote_request_id,access_token_hash,access_token_expires_at,status,started_at,submitted_at,confirmation
) values (
  'f2100000-0000-4000-8000-000000000002','f2000001-0000-4000-8000-000000000002',
  repeat('2',64),'2099-02-01T00:00:00Z','submitted','2099-01-01T09:00:00Z','2099-01-01T10:00:00Z',true
);

insert into public.sdf_quotations(quotation_id,quote_request_id,created_at) values
  ('f3000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000001','2099-01-01T09:00:00Z'),
  ('f3000000-0000-4000-8000-000000000003','f2000002-0000-4000-8000-000000000003','2099-01-01T09:00:00Z');
insert into public.sdf_quotation_documents(
  quotation_id,quotation_date,valid_until,prepared_at,document_reference,document_sha256
) values (
  'f3000000-0000-4000-8000-000000000001','2099-01-01','2099-02-01','2099-01-01T10:00:00Z',
  'sdf/quotations/f3000000-0000-4000-8000-000000000001/document.docx',repeat('1',64)
), (
  'f3000000-0000-4000-8000-000000000003','2099-01-01','2099-02-01','2099-01-01T10:00:00Z',
  'sdf/quotations/f3000000-0000-4000-8000-000000000003/document.docx',repeat('3',64)
);
insert into public.sdf_quotation_acceptances(quotation_id,accepted_at,document_reference,document_sha256) values (
  'f3000000-0000-4000-8000-000000000001','2099-01-02T10:00:00Z',
  'sdf/quotations/f3000000-0000-4000-8000-000000000001/accepted.docx',repeat('a',64)
), (
  'f3000000-0000-4000-8000-000000000003','2099-01-02T10:00:00Z',
  'sdf/quotations/f3000000-0000-4000-8000-000000000003/accepted.docx',repeat('c',64)
);

select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000001',true);
select lives_ok(
  $$select public.create_sdf_milestone_one_foundation_v1(
    'f3000000-0000-4000-8000-000000000001',285000,'f4000000-0000-4000-8000-000000000001'
  )$$,
  'existing accepted quotation creates immutable EXPECTED M1 authority'
);
select lives_ok(
  $$select public.create_sdf_milestone_one_foundation_v1(
    'f3000000-0000-4000-8000-000000000003',285000,'f4000000-0000-4000-8000-000000000003'
  )$$,
  'legacy accepted SDF evidence can exist before invoice candidate eligibility'
);

select lives_ok(
  $$select public.register_sdf_invoice_template_authority_v1(
    'LWS_GENERIC_INVOICE_MASTER','current-2026-09-02',
    '03_Algemene_sjablonen/02_Factuursjabloon.docx','52dc454bec5d0e09fc9f4b85a1f1877b65f7d3aea166ed195da598cb7b4536d6',
    'f5000000-0000-4000-8000-000000000001'
  )$$,
  'existing Drive document identity and hash can be registered without replacing its bytes'
);
select is(
  (public.register_sdf_invoice_template_authority_v1(
    'LWS_GENERIC_INVOICE_MASTER','current-2026-09-02',
    '03_Algemene_sjablonen/02_Factuursjabloon.docx','52dc454bec5d0e09fc9f4b85a1f1877b65f7d3aea166ed195da598cb7b4536d6',
    'f5000000-0000-4000-8000-000000000001'
  )->>'was_created')::boolean,
  false,
  'same template registration replays idempotently'
);
select throws_ok(
  $$select public.register_sdf_invoice_template_authority_v1(
    'LWS_GENERIC_INVOICE_MASTER','current-2026-09-02',
    'drive/invoices/other.docx',repeat('c',64),
    'f5000000-0000-4000-8000-000000000001'
  )$$,
  'P0001','IDEMPOTENCY_CONFLICT','template idempotency key rejects changed bytes or reference'
);

select lives_ok(
  $$select public.prepare_sdf_m1_invoice_candidate_v1(
    (select obligation_id from public.sdf_milestone_one_obligations where quotation_id='f3000000-0000-4000-8000-000000000001'),
    (select template_authority_id from public.sdf_invoice_template_authorities where template_id='LWS_GENERIC_INVOICE_MASTER'),
    'f6000000-0000-4000-8000-000000000001'
  )$$,
  'owner prepares a policy-neutral M1 invoice candidate'
);
select throws_ok(
  $$select public.prepare_sdf_m1_invoice_candidate_v1(
    (select obligation_id from public.sdf_milestone_one_obligations where quotation_id='f3000000-0000-4000-8000-000000000003'),
    (select template_authority_id from public.sdf_invoice_template_authorities where template_id='LWS_GENERIC_INVOICE_MASTER'),
    'f6000000-0000-4000-8000-000000000003'
  )$$,
  '23514','SDF_APPLICATION_REFERENCE_REQUIRED',
  'candidate preparation fails closed when no existing immutable dossier reference is available'
);
select ok(
  (select candidate.candidate_state='PREPARED'
    and candidate.milestone_identity='M1'
    and candidate.percentage_basis_points=4000
    and candidate.currency='EUR'
    and candidate.net_amount_minor=114000
    and candidate.accepted_price_basis='exclusive'
    and candidate.quotation_id='f3000000-0000-4000-8000-000000000001'
    and candidate.accepted_terms_id=terms.accepted_terms_id
    and candidate.quote_request_id='f2000000-0000-4000-8000-000000000001'
    and candidate.application_reference='LWS-AAN-2099-9001'
   from public.sdf_m1_invoice_candidates as candidate
   join public.sdf_accepted_commercial_terms as terms
     on terms.accepted_terms_id=candidate.accepted_terms_id),
  'candidate preserves accepted quotation, terms, EXPECTED M1, 40 percent, EUR, and net amount'
);
select ok(
  (select candidate_id::text <> quote_request_id::text
    and application_reference <> candidate_id::text
    and application_reference <> quote_request_id::text
   from public.sdf_m1_invoice_candidates),
  'dossier reference, candidate UUID, and application UUID remain separate identities'
);
select throws_ok(
  $$update public.quote_requests
    set application_reference='LWS-AAN-2099-9002'
    where id='f2000000-0000-4000-8000-000000000001'$$,
  '23514','APPLICATION_REFERENCE_IMMUTABLE',
  'snapshotted human dossier reference cannot later be reassigned at its source'
);
select is((select count(*)::integer from public.sdf_invoice_number_counters),0,'candidate preparation consumes no definitive invoice number');
select is((select count(*)::integer from public.sdf_m1_invoice_issuances),0,'candidate preparation creates no issuance evidence');
select ok(
  (select seller_snapshot = jsonb_build_object(
    'legal_name','Lorenzo Bombello','trade_name','Lorenzo Web Solutions',
    'address_line_1','Grote Baan 164 bus 1002','postal_code','9920','city','Lievegem',
    'country_code','BE','enterprise_number','0742.361.487',
    'vat_identification_number','BE 0742.361.487'
  ) from public.sdf_m1_invoice_candidates),
  'candidate snapshots only the existing seller identity authority'
);
select ok(
  (select bank_snapshot = jsonb_build_object('bank','KBC','iban','BE42 7380 5510 8954','bic','KREDBEBB')
   from public.sdf_m1_invoice_candidates),
  'candidate snapshots the existing bank authority'
);
select ok(
  (select customer_snapshot->>'legal_name'='Ada BV'
    and customer_snapshot->>'billing_email'='billing@example.test'
    and customer_snapshot->>'enterprise_number'='0123456789'
    and customer_snapshot->>'vat_identification_number'='BE0123456789'
   from public.sdf_m1_invoice_candidates),
  'candidate snapshots persisted customer and billing identity without a fiscal computation'
);
select ok(
  (select not (seller_snapshot || customer_snapshot || bank_snapshot || template_snapshot)
    ?| array['vat_treatment','vat_rate','vat_rate_basis_points','vat_amount_minor','gross_amount_minor']
   from public.sdf_m1_invoice_candidates),
  'candidate contains no VAT treatment, rate, VAT amount, or gross fallback'
);
select ok(
  (select template_snapshot->>'document_reference'='03_Algemene_sjablonen/02_Factuursjabloon.docx'
    and template_snapshot->>'document_sha256'='52dc454bec5d0e09fc9f4b85a1f1877b65f7d3aea166ed195da598cb7b4536d6'
   from public.sdf_m1_invoice_candidates),
  'candidate immutably binds the registered existing Drive document identity and hash'
);
select is(
  (public.prepare_sdf_m1_invoice_candidate_v1(
    (select obligation_id from public.sdf_milestone_one_obligations where quotation_id='f3000000-0000-4000-8000-000000000001'),
    (select template_authority_id from public.sdf_invoice_template_authorities where template_id='LWS_GENERIC_INVOICE_MASTER'),
    'f6000000-0000-4000-8000-000000000001'
  )->>'was_created')::boolean,
  false,
  'same candidate request replays idempotently'
);
select is((select count(*)::integer from public.sdf_m1_invoice_candidates),1,'idempotent retry creates no duplicate candidate');
select ok(
  not exists(
    select 1
    from public.sdf_m1_invoice_candidates as candidate
    join public.quote_requests as request on request.id = candidate.quote_request_id
    where request.request_kind <> 'slimme_documentenflow'
  ),
  'Website requests never enter SDF invoice candidates'
);

select throws_ok(
  $$update public.sdf_m1_invoice_candidates set net_amount_minor=1$$,
  '55000','SDF_INVOICE_FOUNDATION_IMMUTABLE','candidate rejects UPDATE'
);
select throws_ok(
  $$delete from public.sdf_invoice_template_authorities$$,
  '55000','SDF_INVOICE_FOUNDATION_IMMUTABLE','Drive template authority rejects DELETE'
);

select throws_ok(
  $$select public.issue_sdf_m1_invoice_v1(
    (select candidate_id from public.sdf_m1_invoice_candidates),2099::smallint,
    'f7000000-0000-4000-8000-000000000001'
  )$$,
  'P0001','QUOTATION_VAT_CONTEXT_REQUIRED','invoice authority mismatch fails before number allocation'
);
select is((select count(*)::integer from public.sdf_invoice_number_counters),0,'failed fiscal gate consumes no invoice number');
select is((select count(*)::integer from public.sdf_m1_invoice_issuances),0,'failed fiscal gate creates no issuance evidence');

select is(
  public.get_operator_application_v1('f2000000-0000-4000-8000-000000000001',null)->'sdf_m1_invoice_candidate',
  jsonb_build_object(
    'candidate_id',(select candidate_id from public.sdf_m1_invoice_candidates),
    'candidate_state','PREPARED',
    'application_reference','LWS-AAN-2099-9001',
    'milestone_identity','M1',
    'percentage_basis_points',4000,
    'currency','EUR',
    'net_amount_minor',114000,
    'template_binding_present',true,
    'invoice_number',null,
    'fiscal_authority_state','NOT_ACTIVE',
    'production_issuance_available',false,
    'prepared_at',(select prepared_at from public.sdf_m1_invoice_candidates)
  ),
  'Operator projection exposes minimal safe candidate state and explicit issuance block'
);
select is(
  public.get_operator_application_v1(null,'LWS-AAN-2099-9001')->'sdf_m1_invoice_candidate'->>'candidate_id',
  (select candidate_id::text from public.sdf_m1_invoice_candidates),
  'human application reference directly resolves the same immutable invoice candidate dossier'
);
select is(
  public.get_operator_application_v1('f2000001-0000-4000-8000-000000000002',null)->'sdf_m1_invoice_candidate',
  'null'::jsonb,
  'Website Operator detail exposes no SDF invoice candidate'
);

select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000002',true);
select throws_ok(
  $$select public.prepare_sdf_m1_invoice_candidate_v1(
    (select obligation_id from public.sdf_milestone_one_obligations limit 1),
    (select template_authority_id from public.sdf_invoice_template_authorities limit 1),
    'f6000000-0000-4000-8000-000000000099'
  )$$,
  '42501','SDF_INVOICE_AUTHORITY_DENIED','non-admin Operator cannot prepare invoice candidates'
);

select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000001',true);
insert into public.quotation_vat_transaction_classifications (
  classification_id, quote_request_id, context_sha256, classification_code,
  source_reference, source_sha256, classified_by, classified_at
) values (
  'f8000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000001',
  public.quotation_vat_context_sha256_v1('f2000000-0000-4000-8000-000000000001'),
  'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION',
  'TEST_ONLY:SDF_CLASSIFICATION', repeat('8',64), 'TEST', clock_timestamp()
);
insert into public.quotation_vat_turnover_snapshots (
  turnover_snapshot_id, vat_decision_authority_id, threshold_year,
  measurement_watermark, governed_turnover_minor, currency, state,
  source_reference, source_sha256, predecessor_snapshot_id, recorded_by, recorded_at
) values (
  'f8100000-0000-4000-8000-000000000001',
  'b1030000-0000-4000-8000-000000000001', 2026,
  (clock_timestamp() at time zone 'Europe/Brussels')::date,
  1000000, 'EUR', 'BELOW_OR_AT_THRESHOLD',
  'TEST_ONLY:SDF_TURNOVER:CURRENT', repeat('9',64), null, 'TEST', clock_timestamp()
);
select lives_ok(
  $$select public.bind_sdf_quotation_vat_authority_v1(
    'f3000000-0000-4000-8000-000000000001',
    (clock_timestamp() at time zone 'Europe/Brussels')::date
  )$$,
  'accepted quotation freezes the current canonical VAT authority'
);
select is(
  public.resolve_sdf_m1_invoice_vat_authority_v1(
    (select candidate_id from public.sdf_m1_invoice_candidates),
    (clock_timestamp() at time zone 'Europe/Brussels')::date
  )->>'authority_sha256',
  (select rtrim(authority_sha256) from public.quotation_vat_decision_authorities
   where vat_decision_authority_id='b1030000-0000-4000-8000-000000000001'),
  'invoice preflight matches frozen quotation authority ID, version, hash, context, and turnover'
);
select lives_ok(
  $$select public.issue_sdf_m1_invoice_v2(
    (select candidate_id from public.sdf_m1_invoice_candidates),
    extract(year from clock_timestamp())::smallint,
    'f7000000-0000-4000-8000-000000000002',
    repeat('a',64), 4096, repeat('b',64), 2048
  )$$,
  'guarded issuance succeeds only after frozen authority and artifact evidence match'
);
select ok(
  (select vat_decision_authority_id='b1030000-0000-4000-8000-000000000001'
      and vat_authority_version='1.0.0'
      and vat_authority_sha256=(select authority_sha256 from public.quotation_vat_decision_authorities
        where vat_decision_authority_id='b1030000-0000-4000-8000-000000000001')
      and vat_treatment='EXEMPT'
      and rate_semantics='NOT_APPLICABLE'
      and vat_rate_basis_points=0
      and invoice_literal='Bijzondere vrijstellingsregeling van belasting'
      and vat_amount_minor=0
      and gross_amount_minor=net_amount_minor
   from public.sdf_m1_invoice_issuances),
  'issuance freezes strict exemption authority and computes zero VAT without zero-rate semantics'
);
select is(
  (public.issue_sdf_m1_invoice_v2(
    (select candidate_id from public.sdf_m1_invoice_candidates),
    extract(year from clock_timestamp())::smallint,
    'f7000000-0000-4000-8000-000000000002',
    repeat('a',64), 4096, repeat('b',64), 2048
  )->>'was_created')::boolean,
  false,
  'identical issuance replays without allocating another number'
);
select is((select next_sequence from public.sdf_invoice_number_counters),2,'one successful issuance allocates exactly one number');

insert into public.sdf_projects(project_id,quote_request_id) values (
  'f9000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000001'
);
set local session_replication_role = replica;
insert into public.sdf_projects(project_id,quote_request_id) values (
  'f9000000-0000-4000-8000-000000000002','f2000001-0000-4000-8000-000000000002'
);
set local session_replication_role = origin;

select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000002',true);
select throws_ok(
  $$select * from public.get_sdf_m1_payment_state_v1(
    (select issuance_id from public.sdf_m1_invoice_issuances)
  )$$,
  '42501','SDF_PAYMENT_AUTHORITY_DENIED',
  'non-admin Operator cannot read private SDF M1 payment state'
);
select throws_ok(
  $$select public.record_sdf_m1_payment_receipt_v1(
    (select issuance_id from public.sdf_m1_invoice_issuances),1,
    'TEST-TXN-M1-DENIED','TEST-EVIDENCE-M1-DENIED',
    'f9100000-0000-4000-8000-000000000099'
  )$$,
  '42501','SDF_PAYMENT_AUTHORITY_DENIED',
  'non-admin Operator cannot record SDF M1 receipt evidence'
);
select throws_ok(
  $$select public.authorize_sdf_project_start_v1(
    'f9000000-0000-4000-8000-000000000001',
    (select issuance_id from public.sdf_m1_invoice_issuances),
    'f9200000-0000-4000-8000-000000000099'
  )$$,
  '42501','SDF_PROJECT_START_AUTHORITY_DENIED',
  'non-admin Operator cannot authorize SDF project start'
);
select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000001',true);

select throws_ok(
  $$select public.authorize_sdf_project_start_v1(
    'f9000000-0000-4000-8000-000000000001','f7000000-0000-4000-8000-000000000099',
    'f9200000-0000-4000-8000-000000000001'
  )$$,
  '23503','SDF_M1_ISSUANCE_REQUIRED',
  'accepted SDF without M1 invoice issuance cannot authorize project start'
);
select results_eq(
  $$select payment_state from public.get_sdf_m1_payment_state_v1(
    (select issuance_id from public.sdf_m1_invoice_issuances)
  )$$,
  array['NOT_RECEIVED'::text],
  'M1 invoice issuance is not payment receipt evidence'
);
select throws_ok(
  $$select public.authorize_sdf_project_start_v1(
    'f9000000-0000-4000-8000-000000000001',
    (select issuance_id from public.sdf_m1_invoice_issuances),
    'f9200000-0000-4000-8000-000000000002'
  )$$,
  'P0001','SDF_M1_FULL_PAYMENT_REQUIRED',
  'issued but unpaid M1 cannot authorize project start'
);
select throws_ok(
  $$select public.authorize_sdf_project_start_v1(
    'f9000000-0000-4000-8000-000000000002',
    (select issuance_id from public.sdf_m1_invoice_issuances),
    'f9200000-0000-4000-8000-000000000003'
  )$$,
  '23514','SDF_PROJECT_LINKAGE_MISMATCH',
  'Website project linkage cannot enter SDF start authority'
);

create temporary table original_sdf_candidate_hash as
select candidate_id,candidate_payload_sha256 from public.sdf_m1_invoice_candidates;
set local session_replication_role = replica;
update public.sdf_m1_invoice_candidates set candidate_payload_sha256=repeat('0',64);
set local session_replication_role = origin;
select throws_ok(
  $$select public.record_sdf_m1_payment_receipt_v1(
    (select issuance_id from public.sdf_m1_invoice_issuances),1,
    'TEST-TXN-M1-STALE','TEST-EVIDENCE-M1-STALE',
    'f9100000-0000-4000-8000-000000000001'
  )$$,
  '55000','SDF_M1_COMMERCIAL_SNAPSHOT_STALE',
  'stale immutable candidate snapshot blocks payment registration'
);
set local session_replication_role = replica;
update public.sdf_m1_invoice_candidates as candidate
set candidate_payload_sha256=original.candidate_payload_sha256
from original_sdf_candidate_hash as original
where original.candidate_id=candidate.candidate_id;
set local session_replication_role = origin;

select lives_ok(
  $$select public.record_sdf_m1_payment_receipt_v1(
    (select issuance_id from public.sdf_m1_invoice_issuances),50000,
    'TEST-TXN-M1-PARTIAL','TEST-EVIDENCE-M1-PARTIAL',
    'f9100000-0000-4000-8000-000000000002'
  )$$,
  'partial M1 payment is recorded as receipt evidence'
);
select results_eq(
  $$select payment_state,cumulative_received_minor,required_amount_minor
    from public.get_sdf_m1_payment_state_v1(
      (select issuance_id from public.sdf_m1_invoice_issuances)
    )$$,
  $$values ('PARTIAL'::text,50000::bigint,114000::bigint)$$,
  'partial receipt remains distinct from full RECEIVED'
);
select throws_ok(
  $$select public.authorize_sdf_project_start_v1(
    'f9000000-0000-4000-8000-000000000001',
    (select issuance_id from public.sdf_m1_invoice_issuances),
    'f9200000-0000-4000-8000-000000000004'
  )$$,
  'P0001','SDF_M1_FULL_PAYMENT_REQUIRED',
  'partial M1 payment cannot authorize project start'
);
select throws_ok(
  $$select public.record_sdf_m1_payment_receipt_v1(
    (select issuance_id from public.sdf_m1_invoice_issuances),70000,
    'TEST-TXN-M1-OVERPAY','TEST-EVIDENCE-M1-OVERPAY',
    'f9100000-0000-4000-8000-000000000003'
  )$$,
  '23514','SDF_M1_PAYMENT_EXCEEDS_REQUIRED',
  'payment amount exceeding required cumulative M1 fails closed'
);
select lives_ok(
  $$select public.record_sdf_m1_payment_receipt_v1(
    (select issuance_id from public.sdf_m1_invoice_issuances),64000,
    'TEST-TXN-M1-FINAL','TEST-EVIDENCE-M1-FINAL',
    'f9100000-0000-4000-8000-000000000004'
  )$$,
  'second receipt may complete the exact required M1 amount'
);
select results_eq(
  $$select payment_state,cumulative_received_minor,required_amount_minor,reconciliation_state
    from public.get_sdf_m1_payment_state_v1(
      (select issuance_id from public.sdf_m1_invoice_issuances)
    )$$,
  $$values ('RECEIVED'::text,114000::bigint,114000::bigint,'NOT_RECONCILED'::text)$$,
  'exact cumulative M1 becomes RECEIVED without simulating RECONCILED'
);
select is(
  (public.record_sdf_m1_payment_receipt_v1(
    (select issuance_id from public.sdf_m1_invoice_issuances),64000,
    'TEST-TXN-M1-FINAL','TEST-EVIDENCE-M1-FINAL',
    'f9100000-0000-4000-8000-000000000004'
  )->>'was_created')::boolean,
  false,
  'duplicate payment receipt replays idempotently'
);
select results_eq(
  $$select count(*)::integer from public.sdf_m1_payment_receipts$$,
  array[2],
  'payment replay creates no duplicate receipt event'
);
select lives_ok(
  $$select public.authorize_sdf_project_start_v1(
    'f9000000-0000-4000-8000-000000000001',
    (select issuance_id from public.sdf_m1_invoice_issuances),
    'f9200000-0000-4000-8000-000000000005'
  )$$,
  'full exact M1 RECEIVED authorizes project start'
);
select results_eq(
  $$select authority_state,required_amount_minor,received_amount_minor
    from public.sdf_m1_project_start_authorities$$,
  $$values ('START_ALLOWED'::text,114000::bigint,114000::bigint)$$,
  'project start authority freezes exact required and received M1'
);

insert into public.quotation_vat_turnover_snapshots (
  turnover_snapshot_id, vat_decision_authority_id, threshold_year,
  measurement_watermark, governed_turnover_minor, currency, state,
  source_reference, source_sha256, predecessor_snapshot_id, recorded_by, recorded_at
) values (
  'f8100000-0000-4000-8000-000000000002',
  'b1030000-0000-4000-8000-000000000001', 2026,
  (clock_timestamp() at time zone 'Europe/Brussels')::date + 1,
  1000000, 'EUR', 'BELOW_OR_AT_THRESHOLD',
  'TEST_ONLY:SDF_TURNOVER:NEXT', repeat('c',64),
  'f8100000-0000-4000-8000-000000000001', 'TEST', clock_timestamp()
);
select throws_ok(
  $$select public.resolve_sdf_m1_invoice_vat_authority_v1(
    (select candidate_id from public.sdf_m1_invoice_candidates),
    (clock_timestamp() at time zone 'Europe/Brussels')::date + 1
  )$$,
  'P0001','SDF_VAT_AUTHORITY_MISMATCH',
  'changed governed turnover snapshot cannot silently upgrade the frozen quotation binding'
);
set local session_replication_role = replica;
update public.sdf_quotation_vat_authority_bindings
set turnover_snapshot_id='f8100000-0000-4000-8000-000000000002'
where quotation_id='f3000000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select throws_ok(
  $$select public.issue_sdf_m1_invoice_v2(
    (select candidate_id from public.sdf_m1_invoice_candidates),
    extract(year from clock_timestamp())::smallint,
    'f7000000-0000-4000-8000-000000000003',
    repeat('a',64), 4096, repeat('b',64), 2048
  )$$,
  'P0001','SDF_VAT_AUTHORITY_MISMATCH',
  'issuance rejects frozen quotation authority mismatch before number allocation'
);
set local session_replication_role = replica;
update public.sdf_quotation_vat_authority_bindings
set turnover_snapshot_id='f8100000-0000-4000-8000-000000000001'
where quotation_id='f3000000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
insert into public.quotation_vat_turnover_snapshots (
  turnover_snapshot_id, vat_decision_authority_id, threshold_year,
  measurement_watermark, governed_turnover_minor, currency, state,
  source_reference, source_sha256, predecessor_snapshot_id, recorded_by, recorded_at
) values (
  'f8100000-0000-4000-8000-000000000003',
  'b1030000-0000-4000-8000-000000000001', 2026,
  (clock_timestamp() at time zone 'Europe/Brussels')::date + 2,
  1000001, 'EUR', 'AUTHORITY_REVIEW_REQUIRED',
  'TEST_ONLY:SDF_TURNOVER:REVIEW', repeat('d',64),
  'f8100000-0000-4000-8000-000000000002', 'TEST', clock_timestamp()
);
select throws_ok(
  $$select public.resolve_sdf_m1_invoice_vat_authority_v1(
    (select candidate_id from public.sdf_m1_invoice_candidates),
    (clock_timestamp() at time zone 'Europe/Brussels')::date + 2
  )$$,
  'P0001','AUTHORITY_REVIEW_REQUIRED',
  'turnover above EUR 10,000 blocks invoice authority without grace'
);
insert into public.quotation_vat_turnover_snapshots (
  turnover_snapshot_id, vat_decision_authority_id, threshold_year,
  measurement_watermark, governed_turnover_minor, currency, state,
  source_reference, source_sha256, predecessor_snapshot_id, recorded_by, recorded_at
) values (
  'f8100000-0000-4000-8000-000000000004',
  'b1030000-0000-4000-8000-000000000001', 2026,
  (clock_timestamp() at time zone 'Europe/Brussels')::date,
  1000001, 'EUR', 'AUTHORITY_REVIEW_REQUIRED',
  'TEST_ONLY:SDF_TURNOVER:CURRENT_REVIEW', repeat('e',64),
  null, 'TEST', clock_timestamp()
);
select throws_ok(
  $$select public.issue_sdf_m1_invoice_v2(
    (select candidate_id from public.sdf_m1_invoice_candidates),
    extract(year from clock_timestamp())::smallint,
    'f7000000-0000-4000-8000-000000000004',
    repeat('a',64), 4096, repeat('b',64), 2048
  )$$,
  'P0001','QUOTATION_VAT_THRESHOLD_AUTHORITY_REVIEW_REQUIRED',
  'issuance rejects conflicting threshold-review state before number allocation'
);
select is((select next_sequence from public.sdf_invoice_number_counters),2,'mismatch and threshold review allocate no number');

select set_config('lws.quotation_business_authority_transition','ACTIVATE_VERSION',true);
update public.quotation_vat_decision_authorities
set status='RETIRED', retired_by='TEST', retired_at=clock_timestamp(),
    retirement_reason='TEST_ONLY_INACTIVE_AUTHORITY'
where vat_decision_authority_id='b1030000-0000-4000-8000-000000000001';
select set_config('lws.quotation_business_authority_transition','',true);
select throws_ok(
  $$select public.resolve_sdf_m1_invoice_vat_authority_v1(
    (select candidate_id from public.sdf_m1_invoice_candidates),
    (clock_timestamp() at time zone 'Europe/Brussels')::date
  )$$,
  'P0001','QUOTATION_VAT_DECISION_NOT_APPROVED',
  'retired authority blocks invoice preflight'
);
select throws_ok(
  $$select public.issue_sdf_m1_invoice_v2(
    (select candidate_id from public.sdf_m1_invoice_candidates),
    extract(year from clock_timestamp())::smallint,
    'f7000000-0000-4000-8000-000000000005',
    repeat('a',64), 4096, repeat('b',64), 2048
  )$$,
  'P0001','QUOTATION_VAT_DECISION_NOT_APPROVED',
  'issuance rejects retired authority before number allocation'
);
select is((select next_sequence from public.sdf_invoice_number_counters),2,'inactive authority allocates no number');

select * from finish();
rollback;
