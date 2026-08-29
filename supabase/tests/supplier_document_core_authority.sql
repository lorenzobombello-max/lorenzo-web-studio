begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, storage, extensions;

select plan(53);

select has_table('public', 'supplier_documents', 'supplier document core authority exists');
select has_function(
  'public', 'create_supplier_document_v1',
  array['text','text','text','date','text','text','bigint','text','text'],
  'owner supplier document registration RPC exists'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.supplier_documents'::regclass),
  'supplier documents have RLS enabled'
);
select ok(
  exists (
    select 1 from pg_proc
    where oid = 'public.create_supplier_document_v1(text,text,text,date,text,text,bigint,text,text)'::regprocedure
      and prosecdef
      and proconfig = array['search_path=public, storage, auth, pg_catalog']
  ),
  'registration RPC is SECURITY DEFINER with a fixed safe search_path'
);
select ok(
  not has_table_privilege('authenticated', 'public.supplier_documents', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.supplier_documents', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.supplier_documents', 'select,insert,update,delete')
  and not has_table_privilege('public', 'public.supplier_documents', 'select,insert,update,delete'),
  'browser and service roles have no direct supplier document table privileges'
);
select ok(
  has_function_privilege('authenticated', 'public.create_supplier_document_v1(text,text,text,date,text,text,bigint,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.create_supplier_document_v1(text,text,text,date,text,text,bigint,text,text)', 'execute')
  and not has_function_privilege('service_role', 'public.create_supplier_document_v1(text,text,text,date,text,text,bigint,text,text)', 'execute')
  and not has_function_privilege('public', 'public.create_supplier_document_v1(text,text,text,date,text,text,bigint,text,text)', 'execute'),
  'only authenticated receives guarded registration RPC execution'
);
select is((select count(*)::integer from storage.buckets where id = 'supplier-documents'), 1, 'private supplier document bucket exists');
select is((select public from storage.buckets where id = 'supplier-documents'), false, 'supplier document bucket is private');
select is((select file_size_limit from storage.buckets where id = 'supplier-documents'), 10485760::bigint, 'bucket enforces ten MiB maximum');
select is(
  (select allowed_mime_types from storage.buckets where id = 'supplier-documents'),
  array['application/pdf','image/png','image/jpeg']::text[],
  'bucket permits only supported supplier document MIME types'
);
select is(
  (select count(*)::integer from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and (coalesce(qual, '') like '%supplier-documents%'
       or coalesce(with_check, '') like '%supplier-documents%')),
  0, 'supplier document bucket has no browser Storage policy'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'supplier_documents'
      and column_name in (
        'business_expense_id', 'commercial_project_id', 'project_id', 'sdf_project_id',
        'customer_request_id', 'uploaded_file_id', 'quotation_artifact_id'
      )
  ),
  'supplier document identity is standalone from expense project customer and quotation records'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'supplier_documents'
      and column_name in ('paid', 'unpaid', 'paid_at', 'payment_reference', 'payment_evidence_id')
  ),
  'supplier documents add no payment authority'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'supplier_documents'
      and column_name in ('vat_rate', 'vat_amount_minor', 'deductible_vat', 'vat_posting_id')
  ),
  'supplier documents add no VAT authority'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'supplier_documents'
      and column_name in ('bank_transaction_id', 'bank_reference', 'iban')
  ),
  'supplier documents add no banking authority'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'supplier_documents'
      and column_name in ('amount_minor', 'currency', 'correction_amount_minor', 'original_invoice_id')
  ),
  'credit notes and other documents carry no financial correction semantics'
);
select ok(
  (select prosrc !~* '(business_expenses|commercial_projects|sdf_projects|customer_request_uploaded_files|quote_request_quotation_artifacts|recurring_services|payment_evidence)'
   from pg_proc
   where oid = 'public.create_supplier_document_v1(text,text,text,date,text,text,bigint,text,text)'::regprocedure),
  'registration RPC has no expense project customer quotation recurring or payment dependency'
);

insert into auth.users(id, email) values
  ('f6100000-0000-4000-8000-000000000001', 'supplier-doc-owner@example.test'),
  ('f6100000-0000-4000-8000-000000000002', 'supplier-doc-admin@example.test'),
  ('f6100000-0000-4000-8000-000000000003', 'supplier-doc-disabled@example.test'),
  ('f6100000-0000-4000-8000-000000000004', 'supplier-doc-revoked@example.test');

insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status, revoked_at
) values
  ('f6110000-0000-4000-8000-000000000001', 'f6100000-0000-4000-8000-000000000001', 'Supplier Document Owner', 'owner', 'ACTIVE', null),
  ('f6110000-0000-4000-8000-000000000002', 'f6100000-0000-4000-8000-000000000002', 'Supplier Document Admin', 'admin', 'ACTIVE', null),
  ('f6110000-0000-4000-8000-000000000003', 'f6100000-0000-4000-8000-000000000003', 'Supplier Document Disabled', 'owner', 'DISABLED', null),
  ('f6110000-0000-4000-8000-000000000004', 'f6100000-0000-4000-8000-000000000004', 'Supplier Document Revoked', 'owner', 'REVOKED', clock_timestamp());

insert into storage.objects(bucket_id, name, metadata) values
  ('supplier-documents', 'documents/' || repeat('1', 64) || '.pdf', jsonb_build_object('size', 101, 'mimetype', 'application/pdf', 'sha256', repeat('1', 64))),
  ('supplier-documents', 'documents/' || repeat('2', 64) || '.pdf', jsonb_build_object('size', 102, 'mimetype', 'application/pdf', 'sha256', repeat('2', 64))),
  ('supplier-documents', 'documents/' || repeat('3', 64) || '.png', jsonb_build_object('size', 103, 'mimetype', 'image/png', 'sha256', repeat('3', 64))),
  ('supplier-documents', 'documents/' || repeat('4', 64) || '.jpg', jsonb_build_object('size', 104, 'mimetype', 'image/jpeg', 'sha256', repeat('4', 64))),
  ('supplier-documents', 'documents/' || repeat('5', 64) || '.pdf', jsonb_build_object('size', 105, 'mimetype', 'application/pdf', 'sha256', repeat('5', 64))),
  ('supplier-documents', 'documents/' || repeat('6', 64) || '.pdf', jsonb_build_object('size', 106, 'mimetype', 'application/pdf', 'sha256', repeat('6', 64))),
  ('supplier-documents', 'documents/' || repeat('7', 64) || '.pdf', jsonb_build_object('size', 999, 'mimetype', 'application/pdf', 'sha256', repeat('7', 64)));

select throws_ok(
  $$select public.create_supplier_document_v1('INVOICE','Supplier',null,null,'invoice.pdf','application/pdf',101,repeat('1',64))$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'anonymous registration is denied'
);
select set_config('request.jwt.claim.sub', 'f6100000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.create_supplier_document_v1('INVOICE','Supplier',null,null,'invoice.pdf','application/pdf',101,repeat('1',64))$$,
  '42501', 'SUPPLIER_DOCUMENT_OWNER_REQUIRED', 'active non-owner is denied'
);
select set_config('request.jwt.claim.sub', 'f6100000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.create_supplier_document_v1('INVOICE','Supplier',null,null,'invoice.pdf','application/pdf',101,repeat('1',64))$$,
  '42501', 'OPERATOR_DISABLED', 'disabled owner is denied'
);
select set_config('request.jwt.claim.sub', 'f6100000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$select public.create_supplier_document_v1('INVOICE','Supplier',null,null,'invoice.pdf','application/pdf',101,repeat('1',64))$$,
  '42501', 'OPERATOR_REVOKED', 'revoked owner is denied'
);

select set_config('request.jwt.claim.sub', 'f6100000-0000-4000-8000-000000000001', true);

create temporary table invoice_document as
select public.create_supplier_document_v1(
  ' invoice ', '  Example Supplier  ', '  INV-2026-1  ', '2026-08-20',
  '  supplier-invoice.pdf  ', ' APPLICATION/PDF ', 101, repeat('1', 64), 'production'
) as id;
select ok((select id is not null from invoice_document), 'active owner registers an INVOICE');
select is((select document_type from public.supplier_documents where id = (select id from invoice_document)), 'INVOICE', 'INVOICE type is accepted and normalized');
select is((select supplier_name from public.supplier_documents where id = (select id from invoice_document)), 'Example Supplier', 'supplier name is required and normalized');
select is((select document_reference from public.supplier_documents where id = (select id from invoice_document)), 'INV-2026-1', 'nullable document reference is normalized');
select is((select document_date from public.supplier_documents where id = (select id from invoice_document)), '2026-08-20'::date, 'nullable document date remains document metadata');
select is((select original_file_name from public.supplier_documents where id = (select id from invoice_document)), 'supplier-invoice.pdf', 'original filename is required and normalized');
select is((select mime_type from public.supplier_documents where id = (select id from invoice_document)), 'application/pdf', 'MIME type is required and normalized');
select is((select byte_count from public.supplier_documents where id = (select id from invoice_document)), 101::bigint, 'positive byte count is authoritative metadata');
select is((select rtrim(sha256) from public.supplier_documents where id = (select id from invoice_document)), repeat('1', 64), 'trusted SHA-256 is stored exactly');
select is((select storage_bucket_id from public.supplier_documents where id = (select id from invoice_document)), 'supplier-documents', 'private storage bucket identity is fixed');
select is((select storage_object_path from public.supplier_documents where id = (select id from invoice_document)), 'documents/' || repeat('1', 64) || '.pdf', 'storage path is content-addressed and server-derived');
select is((select record_classification from public.supplier_documents where id = (select id from invoice_document)), 'production', 'production classification is explicit');
select is((select created_by_operator_id from public.supplier_documents where id = (select id from invoice_document)), 'f6110000-0000-4000-8000-000000000001'::uuid, 'creator is bound to owner authority');

select public.create_supplier_document_v1('CREDIT_NOTE','Supplier',null,null,'same-name.pdf','application/pdf',102,repeat('2',64));
select public.create_supplier_document_v1('RECEIPT','Supplier',null,null,'receipt.png','image/png',103,repeat('3',64));
select public.create_supplier_document_v1('CONTRACT','Supplier',null,null,'contract.jpg','image/jpeg',104,repeat('4',64));
select public.create_supplier_document_v1('OTHER','Supplier',null,null,'same-name.pdf','application/pdf',105,repeat('5',64));
select is((select count(*)::integer from public.supplier_documents where document_type = 'CREDIT_NOTE'), 1, 'CREDIT_NOTE is accepted without correction semantics');
select is((select count(*)::integer from public.supplier_documents where document_type = 'RECEIPT'), 1, 'RECEIPT is accepted without payment semantics');
select is((select count(*)::integer from public.supplier_documents where document_type = 'CONTRACT'), 1, 'CONTRACT is accepted');
select is((select count(*)::integer from public.supplier_documents where document_type = 'OTHER'), 1, 'OTHER is accepted');
select is((select count(*)::integer from public.supplier_documents where original_file_name = 'same-name.pdf'), 2, 'filename is not unique');

select throws_ok(
  $$select public.create_supplier_document_v1('PAYMENT_EVIDENCE','Supplier',null,null,'payment.pdf','application/pdf',106,repeat('6',64))$$,
  '22023', 'INVALID_SUPPLIER_DOCUMENT_TYPE', 'PAYMENT_EVIDENCE is rejected'
);
select throws_ok(
  $$select public.create_supplier_document_v1('INVOICE','  ',null,null,'invalid.pdf','application/pdf',106,repeat('6',64))$$,
  '22023', 'INVALID_SUPPLIER_DOCUMENT_SUPPLIER', 'supplier name is required'
);
select throws_ok(
  $$select public.create_supplier_document_v1('INVOICE','Supplier',null,null,'  ','application/pdf',106,repeat('6',64))$$,
  '22023', 'INVALID_SUPPLIER_DOCUMENT_FILE_NAME', 'filename is required'
);
select throws_ok(
  $$select public.create_supplier_document_v1('INVOICE','Supplier',null,null,'invalid.pdf',null,106,repeat('6',64))$$,
  '22023', 'INVALID_SUPPLIER_DOCUMENT_MIME_TYPE', 'MIME type is required'
);
select throws_ok(
  $$select public.create_supplier_document_v1('INVOICE','Supplier',null,null,'invalid.pdf','application/pdf',0,repeat('6',64))$$,
  '22023', 'INVALID_SUPPLIER_DOCUMENT_BYTE_COUNT', 'byte count must be positive'
);
select throws_ok(
  $$select public.create_supplier_document_v1('INVOICE','Supplier',null,null,'invalid.pdf','application/pdf',106,'not-a-hash')$$,
  '22023', 'INVALID_SUPPLIER_DOCUMENT_SHA256', 'malformed SHA-256 is rejected'
);
select throws_ok(
  $$select public.create_supplier_document_v1('INVOICE','Supplier',null,null,'missing.pdf','application/pdf',108,repeat('8',64))$$,
  'P0001', 'SUPPLIER_DOCUMENT_OBJECT_NOT_FOUND', 'registration requires an existing private storage object'
);
select throws_ok(
  $$select public.create_supplier_document_v1('INVOICE','Supplier',null,null,'mismatch.pdf','application/pdf',107,repeat('7',64))$$,
  'P0001', 'SUPPLIER_DOCUMENT_OBJECT_METADATA_MISMATCH', 'trusted storage metadata must match MIME bytes and SHA-256'
);
select throws_ok(
  $$select public.create_supplier_document_v1('INVOICE','Supplier',null,null,'duplicate.pdf','application/pdf',101,repeat('1',64))$$,
  '23505', 'SUPPLIER_DOCUMENT_BINARY_DUPLICATE', 'same trusted SHA-256 is rejected as the same binary'
);
select throws_ok(
  $$select public.create_supplier_document_v1('INVOICE','Supplier',null,null,'fixture.pdf','application/pdf',106,repeat('6',64),'fixture')$$,
  '22023', 'INVALID_SUPPLIER_DOCUMENT_CLASSIFICATION', 'unknown record classification is rejected'
);

select public.create_supplier_document_v1(
  'INVOICE', 'Fixture Supplier', null, null, 'fixture.pdf',
  'application/pdf', 106, repeat('6', 64), 'internal_e2e'
);
select is((select count(*)::integer from public.supplier_documents where record_classification = 'internal_e2e'), 1, 'internal E2E documents are separable from production');
select is((select count(*)::integer from public.supplier_documents where record_classification = 'production'), 5, 'production selection excludes internal E2E document records');

select throws_ok(
  $$update public.supplier_documents set original_file_name = 'changed.pdf'$$,
  '55000', 'SUPPLIER_DOCUMENT_IMMUTABLE', 'archived document identity cannot be updated'
);
select throws_ok(
  $$delete from public.supplier_documents$$,
  '55000', 'SUPPLIER_DOCUMENT_IMMUTABLE', 'archived document identity cannot be deleted'
);

select * from finish();
rollback;