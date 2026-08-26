begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(39);

select has_table('public','sdf_accepted_commercial_terms','accepted SDF commercial terms table exists');
select columns_are(
  'public','sdf_accepted_commercial_terms',
  array[
    'accepted_terms_id','quotation_id','quote_request_id','sdf_package',
    'accepted_implementation_amount_minor','currency','vat_basis',
    'pricing_authority_version','creation_idempotency_key','creation_fingerprint',
    'created_by_operator_id','created_at'
  ],
  'accepted terms contain only immutable commercial snapshot and creation authority'
);
select has_table('public','sdf_milestone_one_obligations','SDF milestone-one obligation table exists');
select columns_are(
  'public','sdf_milestone_one_obligations',
  array[
    'obligation_id','quotation_id','accepted_terms_id','milestone_identity',
    'percentage_basis_points','amount_minor','currency','vat_basis',
    'obligation_state','obligation_origin','created_at'
  ],
  'milestone-one obligation contains only expected-layer authority'
);
select has_function(
  'public','create_sdf_milestone_one_foundation_v1',array['uuid','bigint','uuid'],
  'transactional SDF milestone-one creation RPC exists'
);
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.sdf_accepted_commercial_terms'::regclass)
  and (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.sdf_milestone_one_obligations'::regclass),
  'both financial authority tables have forced RLS'
);
select ok(
  not has_table_privilege('anon','public.sdf_accepted_commercial_terms','select')
  and not has_table_privilege('authenticated','public.sdf_accepted_commercial_terms','insert')
  and not has_table_privilege('service_role','public.sdf_accepted_commercial_terms','insert')
  and not has_table_privilege('anon','public.sdf_milestone_one_obligations','select')
  and not has_table_privilege('authenticated','public.sdf_milestone_one_obligations','insert')
  and not has_table_privilege('service_role','public.sdf_milestone_one_obligations','insert'),
  'no runtime role can write financial authority tables directly'
);
select ok(
  has_function_privilege('authenticated','public.create_sdf_milestone_one_foundation_v1(uuid,bigint,uuid)','execute')
  and not has_function_privilege('anon','public.create_sdf_milestone_one_foundation_v1(uuid,bigint,uuid)','execute')
  and not has_function_privilege('service_role','public.create_sdf_milestone_one_foundation_v1(uuid,bigint,uuid)','execute'),
  'only authenticated humans may enter the guarded creation RPC'
);
select ok(
  not exists(
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name in ('sdf_accepted_commercial_terms','sdf_milestone_one_obligations')
      and column_name in (
        'invoice_id','invoice_number','invoice_reference','invoice_date','due_date',
        'payment_evidence_id','received_amount_minor','received_at','transaction_reference',
        'reconciliation_id','fully_received_at','project_id','project_started_at',
        'milestone_two_amount_minor','milestone_three_amount_minor','activation_at','recurring_started_at'
      )
  ),
  'foundation contains no invoice, payment, project-start, later milestone, activation, or recurring fields'
);

insert into auth.users(id,email) values
  ('e1000000-0000-4000-8000-000000000001','m1-owner@example.test'),
  ('e1000000-0000-4000-8000-000000000002','m1-operator@example.test');
insert into public.commercial_operators(operator_id,auth_user_id,display_name,role,status) values
  ('e1100000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001','M1 Owner','owner','ACTIVE'),
  ('e1100000-0000-4000-8000-000000000002','e1000000-0000-4000-8000-000000000002','M1 Operator','operator','ACTIVE');

insert into public.quote_requests(id,request_kind,sdf_package,name,email,website_type,budget,timing,description,privacy_consent,status) values
  ('e2000000-0000-4000-8000-000000000001','slimme_documentenflow','start','M1 START','m1-start@example.test',null,null,null,'M1 START fixture.',true,'approved'),
  ('e2000001-0000-4000-8000-000000000002','slimme_documentenflow','groei','M1 GROEI','m1-groei@example.test',null,null,null,'M1 GROEI fixture.',true,'approved'),
  ('e2000002-0000-4000-8000-000000000003','slimme_documentenflow','maatwerk','M1 MAATWERK','m1-maatwerk@example.test',null,null,null,'M1 MAATWERK fixture.',true,'approved'),
  ('e2000003-0000-4000-8000-000000000004','slimme_documentenflow','start','M1 no acceptance','m1-none@example.test',null,null,null,'M1 no acceptance fixture.',true,'approved'),
  ('e2000004-0000-4000-8000-000000000005','website',null,'M1 Website','m1-website@example.test','business','Meer dan EUR 6.000','flexible','M1 Website isolation fixture.',true,'approved');

insert into public.sdf_quotations(quotation_id,quote_request_id,created_at) values
  ('e3000000-0000-4000-8000-000000000001','e2000000-0000-4000-8000-000000000001','2099-01-01T09:00:00Z'),
  ('e3000000-0000-4000-8000-000000000002','e2000001-0000-4000-8000-000000000002','2099-01-01T09:00:00Z'),
  ('e3000000-0000-4000-8000-000000000003','e2000002-0000-4000-8000-000000000003','2099-01-01T09:00:00Z'),
  ('e3000000-0000-4000-8000-000000000004','e2000003-0000-4000-8000-000000000004','2099-01-01T09:00:00Z');

insert into public.sdf_quotation_documents(quotation_id,quotation_date,valid_until,prepared_at,document_reference,document_sha256) values
  ('e3000000-0000-4000-8000-000000000001','2099-01-01','2099-02-01','2099-01-01T10:00:00Z','sdf/m1/start/quotation.docx',repeat('1',64)),
  ('e3000000-0000-4000-8000-000000000002','2099-01-01','2099-02-01','2099-01-01T10:00:00Z','sdf/m1/groei/quotation.docx',repeat('2',64)),
  ('e3000000-0000-4000-8000-000000000003','2099-01-01','2099-02-01','2099-01-01T10:00:00Z','sdf/m1/maatwerk/quotation.docx',repeat('3',64));
insert into public.sdf_quotation_acceptances(quotation_id,accepted_at,document_reference,document_sha256) values
  ('e3000000-0000-4000-8000-000000000001','2099-01-02T10:00:00Z','sdf/m1/start/accepted.docx',repeat('a',64)),
  ('e3000000-0000-4000-8000-000000000002','2099-01-02T10:00:00Z','sdf/m1/groei/accepted.docx',repeat('b',64)),
  ('e3000000-0000-4000-8000-000000000003','2099-01-02T10:00:00Z','sdf/m1/maatwerk/accepted.docx',repeat('c',64));

select set_config('request.jwt.claim.sub','e1000000-0000-4000-8000-000000000001',true);

select throws_ok(
  $$select public.create_sdf_milestone_one_foundation_v1('e3000000-0000-4000-8000-000000000004',285000,'e4000000-0000-4000-8000-000000000004')$$,
  '23503','SDF_QUOTATION_ACCEPTANCE_REQUIRED','accepted terms and M1 cannot exist without active acceptance evidence'
);
select is((select count(*)::integer from public.sdf_accepted_commercial_terms where quotation_id='e3000000-0000-4000-8000-000000000004'),0,'failed acceptance prerequisite leaves no accepted terms');
select is((select count(*)::integer from public.sdf_milestone_one_obligations where quotation_id='e3000000-0000-4000-8000-000000000004'),0,'failed acceptance prerequisite leaves no obligation');

select throws_ok(
  $$select public.create_sdf_milestone_one_foundation_v1('e3000000-0000-4000-8000-000000000001',570000,'e4000000-0000-4000-8000-000000000011')$$,
  '23514','SDF_ACCEPTED_AMOUNT_MISMATCH','START rejects an amount incoherent with pricing authority v1'
);
select lives_ok(
  $$select public.create_sdf_milestone_one_foundation_v1('e3000000-0000-4000-8000-000000000001',285000,'e4000000-0000-4000-8000-000000000001')$$,
  'START accepted terms and M1 are created atomically'
);
select is(
  (select jsonb_build_array(quote_request_id,sdf_package,accepted_implementation_amount_minor,currency,vat_basis,pricing_authority_version) from public.sdf_accepted_commercial_terms where quotation_id='e3000000-0000-4000-8000-000000000001'),
  '["e2000000-0000-4000-8000-000000000001","start",285000,"EUR","exclusive",1]'::jsonb,
  'START accepted commercial terms preserve exact package, value, currency, VAT basis, and authority version'
);
select is(
  (select jsonb_build_array(milestone_identity,percentage_basis_points,amount_minor,currency,vat_basis,obligation_state,obligation_origin) from public.sdf_milestone_one_obligations where quotation_id='e3000000-0000-4000-8000-000000000001'),
  '["M1",4000,114000,"EUR","exclusive","EXPECTED","QUOTATION_ACCEPTANCE"]'::jsonb,
  'START creates exactly one expected M1 of EUR 1,140 excl. VAT'
);

select lives_ok(
  $$select public.create_sdf_milestone_one_foundation_v1('e3000000-0000-4000-8000-000000000002',570000,'e4000000-0000-4000-8000-000000000002')$$,
  'GROEI accepted terms and M1 are created atomically'
);
select is((select amount_minor from public.sdf_milestone_one_obligations where quotation_id='e3000000-0000-4000-8000-000000000002'),228000::bigint,'GROEI creates M1 of EUR 2,280 excl. VAT');

select throws_ok(
  $$select public.create_sdf_milestone_one_foundation_v1('e3000000-0000-4000-8000-000000000003',null,'e4000000-0000-4000-8000-000000000031')$$,
  '22004','SDF_EXACT_ACCEPTED_AMOUNT_REQUIRED','MAATWERK requires an explicit exact negotiated amount'
);
select throws_ok(
  $$select public.create_sdf_milestone_one_foundation_v1('e3000000-0000-4000-8000-000000000003',749999,'e4000000-0000-4000-8000-000000000032')$$,
  '23514','SDF_ACCEPTED_AMOUNT_BELOW_AUTHORITY_MINIMUM','MAATWERK rejects values below the starting-at authority without using that minimum as fallback'
);
select lives_ok(
  $$select public.create_sdf_milestone_one_foundation_v1('e3000000-0000-4000-8000-000000000003',812500,'e4000000-0000-4000-8000-000000000003')$$,
  'MAATWERK stores the explicitly supplied negotiated amount'
);
select is((select accepted_implementation_amount_minor from public.sdf_accepted_commercial_terms where quotation_id='e3000000-0000-4000-8000-000000000003'),812500::bigint,'MAATWERK never substitutes the starting-at minimum');
select is((select amount_minor from public.sdf_milestone_one_obligations where quotation_id='e3000000-0000-4000-8000-000000000003'),325000::bigint,'MAATWERK M1 is exact integer 40 percent of negotiated amount');

select is(
  (public.create_sdf_milestone_one_foundation_v1('e3000000-0000-4000-8000-000000000001',285000,'e4000000-0000-4000-8000-000000000001')->>'was_created')::boolean,
  false,
  'same idempotent retry returns the existing authority'
);
select is((select count(*)::integer from public.sdf_accepted_commercial_terms where quotation_id='e3000000-0000-4000-8000-000000000001'),1,'retry creates no duplicate accepted terms');
select is((select count(*)::integer from public.sdf_milestone_one_obligations where quotation_id='e3000000-0000-4000-8000-000000000001'),1,'retry creates no duplicate M1 obligation');
select throws_ok(
  $$select public.create_sdf_milestone_one_foundation_v1('e3000000-0000-4000-8000-000000000001',285005,'e4000000-0000-4000-8000-000000000001')$$,
  'P0001','IDEMPOTENCY_CONFLICT','same idempotency key with conflicting payload fails closed'
);
select throws_ok(
  $$select public.create_sdf_milestone_one_foundation_v1('e3000000-0000-4000-8000-000000000001',285005,'e4000000-0000-4000-8000-000000000012')$$,
  'P0001','SDF_ACCEPTED_TERMS_CONFLICT','same quotation with conflicting financial semantics fails closed'
);

select throws_ok($$update public.sdf_accepted_commercial_terms set accepted_implementation_amount_minor=1 where quotation_id='e3000000-0000-4000-8000-000000000001'$$,'55000','SDF_ACCEPTED_TERMS_IMMUTABLE','accepted terms reject UPDATE');
select throws_ok($$delete from public.sdf_accepted_commercial_terms where quotation_id='e3000000-0000-4000-8000-000000000001'$$,'55000','SDF_ACCEPTED_TERMS_IMMUTABLE','accepted terms reject DELETE');
select throws_ok($$update public.sdf_milestone_one_obligations set amount_minor=1 where quotation_id='e3000000-0000-4000-8000-000000000001'$$,'55000','SDF_MILESTONE_ONE_IMMUTABLE','M1 obligation rejects UPDATE');
select throws_ok($$delete from public.sdf_milestone_one_obligations where quotation_id='e3000000-0000-4000-8000-000000000001'$$,'55000','SDF_MILESTONE_ONE_IMMUTABLE','M1 obligation rejects DELETE');
select throws_ok($$update public.quote_requests set sdf_package='groei' where id='e2000000-0000-4000-8000-000000000001'$$,'55000','SDF_ACCEPTED_PACKAGE_IMMUTABLE','accepted package input cannot change after financial binding');

select set_config('request.jwt.claim.sub','e1000000-0000-4000-8000-000000000002',true);
select throws_ok(
  $$select public.create_sdf_milestone_one_foundation_v1('e3000000-0000-4000-8000-000000000002',570000,'e4000000-0000-4000-8000-000000000099')$$,
  '42501','SDF_FINANCIAL_AUTHORITY_DENIED','non-admin Operator cannot create accepted financial authority'
);

select is((select count(*)::integer from public.commercial_obligations),0,'SDF foundation does not write Website obligations');
select is((select count(*)::integer from public.payment_evidence),0,'SDF foundation creates no payment evidence');
select is((select count(*)::integer from public.payment_reconciliations),0,'SDF foundation creates no payment reconciliation');
select is((select count(*)::integer from public.sdf_projects),0,'SDF foundation creates or starts no project');
select is((select count(*)::integer from public.recurring_services),0,'SDF foundation creates no recurring service');

select * from finish();
rollback;