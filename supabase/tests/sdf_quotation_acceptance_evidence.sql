begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(25);

select has_table('public','sdf_quotation_documents','SDF quotation document evidence table exists');
select columns_are(
  'public','sdf_quotation_documents',
  array['quotation_id','quotation_date','valid_until','prepared_at','document_reference','document_sha256'],
  'quotation document evidence has only identity, linkage, dates, reference, and hash'
);
select has_table('public','sdf_quotation_acceptances','SDF quotation acceptance evidence table exists');
select columns_are(
  'public','sdf_quotation_acceptances',
  array['quotation_id','accepted_at','document_reference','document_sha256'],
  'quotation acceptance evidence has only identity, linkage, acceptance time, reference, and hash'
);
select ok(
  not exists(
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name in ('sdf_quotation_documents','sdf_quotation_acceptances')
      and column_name in (
        'status','implementation_amount_minor','recurring_amount_minor','package_price_minor',
        'vat_amount_minor','total_minor','pricing_snapshot_id','milestone','project_status',
        'project_started_at','phase_a_at','phase_b_at','activated_at','recurring_started_at'
      )
  ),
  'evidence contains no generic status, pricing, project, delivery, activation, or recurring fields'
);
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.sdf_quotation_documents'::regclass)
  and (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.sdf_quotation_acceptances'::regclass),
  'both evidence tables have forced RLS'
);
select ok(
  not has_table_privilege('anon','public.sdf_quotation_documents','select')
  and not has_table_privilege('authenticated','public.sdf_quotation_documents','select')
  and not has_table_privilege('service_role','public.sdf_quotation_documents','insert')
  and not has_table_privilege('anon','public.sdf_quotation_acceptances','select')
  and not has_table_privilege('authenticated','public.sdf_quotation_acceptances','select')
  and not has_table_privilege('service_role','public.sdf_quotation_acceptances','insert'),
  'evidence has no direct runtime read or write privileges'
);

insert into public.quote_requests (id,request_kind,sdf_package,name,email,website_type,budget,timing,description,privacy_consent,status) values
  ('d5100000-0000-4000-8000-000000000001','slimme_documentenflow','groei','SDF evidence fixture','sdf-evidence@example.test',null,null,null,'SDF evidence fixture.',true,'approved'),
  ('d5100000-0000-4000-8000-000000000002','website',null,'Website evidence fixture','website-evidence@example.test','business','Meer dan EUR 6.000','flexible','Website isolation fixture.',true,'approved');

insert into public.sdf_quotations(quotation_id,quote_request_id,created_at) values
  ('d5200000-0000-4000-8000-000000000001','d5100000-0000-4000-8000-000000000001','2099-01-02T09:00:00Z');

select throws_ok(
  $$insert into public.sdf_quotation_documents(quotation_id,quotation_date,valid_until,prepared_at,document_reference,document_sha256) values ('d5200000-0000-4000-8000-000000000099','2099-01-02','2099-02-01','2099-01-02T10:00:00Z','sdf/quotations/missing/document.docx',repeat('a',64))$$,
  '23503', null, 'quotation document evidence requires an existing SDF quotation'
);
select lives_ok(
  $$insert into public.sdf_quotation_documents(quotation_id,quotation_date,valid_until,prepared_at,document_reference,document_sha256) values ('d5200000-0000-4000-8000-000000000001','2099-01-02','2099-02-01','2099-01-02T10:00:00Z','sdf/quotations/d5200000-0000-4000-8000-000000000001/document.docx',repeat('b',64))$$,
  'valid SDF quotation document evidence can be registered once'
);
select is(
  (select jsonb_build_array(quotation_date,valid_until,prepared_at,document_reference,rtrim(document_sha256)) from public.sdf_quotation_documents where quotation_id='d5200000-0000-4000-8000-000000000001'),
  '["2099-01-02", "2099-02-01", "2099-01-02T10:00:00+00:00", "sdf/quotations/d5200000-0000-4000-8000-000000000001/document.docx", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]'::jsonb,
  'quotation date, actual validity, preparation time, reference, and SHA-256 are preserved'
);
select throws_ok(
  $$insert into public.sdf_quotation_documents(quotation_id,quotation_date,valid_until,prepared_at,document_reference,document_sha256) values ('d5200000-0000-4000-8000-000000000001','2099-01-02','2099-02-01','2099-01-02T10:00:00Z','sdf/quotations/duplicate/document.docx',repeat('c',64))$$,
  '23505', null, 'a quotation has at most one current document authority'
);
select throws_ok(
  $$insert into public.sdf_quotation_documents(quotation_id,quotation_date,valid_until,prepared_at,document_reference,document_sha256) values ('d5200000-0000-4000-8000-000000000001','2099-02-02','2099-02-01','2099-01-02T10:00:00Z','sdf/quotations/invalid-validity/document.docx',repeat('d',64))$$,
  '23514', null, 'valid_until cannot precede quotation_date'
);
select throws_ok(
  $$insert into public.sdf_quotation_documents(quotation_id,quotation_date,valid_until,prepared_at,document_reference,document_sha256) values ('d5200000-0000-4000-8000-000000000001','2099-01-02','2099-02-01','2099-01-02T10:00:00Z','https://example.test/signed?token=secret',repeat('e',64))$$,
  '23514', null, 'quotation evidence rejects public or signed URL references'
);
select throws_ok(
  $$insert into public.sdf_quotation_acceptances(quotation_id,accepted_at,document_reference,document_sha256) values ('d5200000-0000-4000-8000-000000000099','2099-01-03T10:00:00Z','sdf/quotations/missing/accepted.docx',repeat('f',64))$$,
  '23503', null, 'acceptance without quotation document evidence fails'
);
select lives_ok(
  $$insert into public.sdf_quotation_acceptances(quotation_id,accepted_at,document_reference,document_sha256) values ('d5200000-0000-4000-8000-000000000001','2099-01-03T10:00:00Z','sdf/quotations/d5200000-0000-4000-8000-000000000001/accepted.docx',repeat('f',64))$$,
  'active acceptance evidence can be registered for a quotation with document evidence'
);
select throws_ok(
  $$insert into public.sdf_quotation_acceptances(quotation_id,accepted_at,document_reference,document_sha256) values ('d5200000-0000-4000-8000-000000000001','2099-01-03T11:00:00Z','sdf/quotations/d5200000-0000-4000-8000-000000000001/accepted-again.docx',repeat('1',64))$$,
  '23505', null, 'a quotation has at most one active acceptance event'
);
select throws_ok(
  $$update public.sdf_quotation_documents set prepared_at='2099-01-02T11:00:00Z' where quotation_id='d5200000-0000-4000-8000-000000000001'$$,
  '55000', 'SDF_QUOTATION_EVIDENCE_IMMUTABLE', 'quotation document evidence is immutable'
);
select throws_ok(
  $$delete from public.sdf_quotation_documents where quotation_id='d5200000-0000-4000-8000-000000000001'$$,
  '55000', 'SDF_QUOTATION_EVIDENCE_IMMUTABLE', 'quotation document evidence cannot be deleted'
);
select throws_ok(
  $$update public.sdf_quotation_acceptances set accepted_at='2099-01-03T11:00:00Z' where quotation_id='d5200000-0000-4000-8000-000000000001'$$,
  '55000', 'SDF_QUOTATION_ACCEPTANCE_IMMUTABLE', 'acceptance evidence is immutable'
);
select throws_ok(
  $$delete from public.sdf_quotation_acceptances where quotation_id='d5200000-0000-4000-8000-000000000001'$$,
  '55000', 'SDF_QUOTATION_ACCEPTANCE_IMMUTABLE', 'acceptance evidence cannot be deleted'
);
select is((select count(*)::integer from public.commercial_obligations),0,'acceptance creates no payment obligation');
select is((select count(*)::integer from public.payment_evidence),0,'acceptance creates no payment evidence');
select is((select count(*)::integer from public.commercial_projects),0,'acceptance creates no Website project');
select is((select count(*)::integer from public.sdf_projects),0,'acceptance creates no SDF project');
select is((select count(*)::integer from public.recurring_services),0,'acceptance starts no recurring service');

select * from finish();
rollback;