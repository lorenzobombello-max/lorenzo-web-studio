begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, storage, extensions;

select plan(20);

select has_function(
  'public', 'finalize_supplier_document_upload_object_v1',
  array['text','text','text','bigint'],
  'supplier document Storage metadata finalizer exists'
);
select ok(
  exists (
    select 1 from pg_proc
    where oid = 'public.finalize_supplier_document_upload_object_v1(text,text,text,bigint)'::regprocedure
      and prosecdef
      and proconfig = array['search_path=public, storage, auth, pg_catalog']
  ),
  'metadata finalizer is SECURITY DEFINER with fixed search path'
);
select ok(
  has_function_privilege('service_role', 'public.finalize_supplier_document_upload_object_v1(text,text,text,bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.finalize_supplier_document_upload_object_v1(text,text,text,bigint)', 'execute')
  and not has_function_privilege('anon', 'public.finalize_supplier_document_upload_object_v1(text,text,text,bigint)', 'execute')
  and not has_function_privilege('public', 'public.finalize_supplier_document_upload_object_v1(text,text,text,bigint)', 'execute'),
  'only service role receives finalizer execution'
);
select is(
  (select count(*)::integer from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and (coalesce(qual, '') like '%supplier-documents%'
       or coalesce(with_check, '') like '%supplier-documents%')),
  0,
  'supplier document bucket still has no browser Storage policy'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'storage.objects'::regclass)
  and not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and cmd in ('ALL', 'INSERT')
      and (roles = '{public}'::name[] or 'authenticated' = any(roles))
      and coalesce(with_check, '') like '%supplier-documents%'
  ),
  'authenticated browser direct insert remains denied by RLS without policy'
);

insert into storage.objects(bucket_id, name, metadata) values
  ('supplier-documents', 'documents/' || repeat('a', 64) || '.pdf', jsonb_build_object('size', 101, 'mimetype', 'application/pdf')),
  ('supplier-documents', 'documents/' || repeat('b', 64) || '.png', jsonb_build_object('size', 102, 'mimetype', 'image/png')),
  ('supplier-documents', 'documents/' || repeat('c', 64) || '.jpg', jsonb_build_object('size', 103, 'mimetype', 'image/jpeg')),
  ('supplier-documents', 'documents/' || repeat('d', 64) || '.pdf', jsonb_build_object('size', 999, 'mimetype', 'application/pdf'));

select throws_ok(
  $$select public.finalize_supplier_document_upload_object_v1('documents/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf', repeat('a',64), 'application/pdf', 101)$$,
  '42501', 'SUPPLIER_DOCUMENT_UPLOAD_SERVICE_REQUIRED',
  'non-service caller is denied'
);
select set_config('request.jwt.claim.role', 'service_role', true);

select ok(public.finalize_supplier_document_upload_object_v1('documents/' || repeat('a',64) || '.pdf', repeat('a',64), 'application/pdf', 101), 'PDF metadata finalizes');
select ok(public.finalize_supplier_document_upload_object_v1('documents/' || repeat('b',64) || '.png', repeat('b',64), 'image/png', 102), 'PNG metadata finalizes');
select ok(public.finalize_supplier_document_upload_object_v1('documents/' || repeat('c',64) || '.jpg', repeat('c',64), 'image/jpeg', 103), 'JPEG metadata finalizes');
select is((select metadata->>'sha256' from storage.objects where name = 'documents/' || repeat('a',64) || '.pdf'), repeat('a',64), 'lowercase SHA is stored in existing metadata contract');
select is((select metadata->>'mimetype' from storage.objects where name = 'documents/' || repeat('a',64) || '.pdf'), 'application/pdf', 'MIME metadata is preserved');
select is((select (metadata->>'size')::bigint from storage.objects where name = 'documents/' || repeat('a',64) || '.pdf'), 101::bigint, 'byte count metadata is preserved');
select ok(public.finalize_supplier_document_upload_object_v1('documents/' || repeat('a',64) || '.pdf', repeat('a',64), 'application/pdf', 101), 'finalization is idempotent');
select throws_ok(
  $$select public.finalize_supplier_document_upload_object_v1('documents/attacker.pdf', repeat('a',64), 'application/pdf', 101)$$,
  '22023', 'INVALID_SUPPLIER_DOCUMENT_STORAGE_PATH', 'browser-provided path cannot override canonical path'
);
select throws_ok(
  $$select public.finalize_supplier_document_upload_object_v1('documents/' || repeat('d',64) || '.pdf', repeat('d',64), 'application/pdf', 104)$$,
  'P0001', 'SUPPLIER_DOCUMENT_OBJECT_METADATA_MISMATCH', 'observed byte mismatch is rejected'
);
select throws_ok(
  $$select public.finalize_supplier_document_upload_object_v1('documents/' || repeat('e',64) || '.pdf', repeat('e',64), 'application/pdf', 105)$$,
  'P0001', 'SUPPLIER_DOCUMENT_OBJECT_METADATA_MISMATCH', 'missing object is rejected'
);
select throws_ok(
  $$select public.finalize_supplier_document_upload_object_v1('documents/' || repeat('A',64) || '.pdf', repeat('A',64), 'application/pdf', 101)$$,
  '22023', 'INVALID_SUPPLIER_DOCUMENT_SHA256', 'uppercase SHA is rejected'
);
select is((select count(*)::integer from public.supplier_documents), 0, 'upload authority creates no supplier document record');
select is((select count(*)::integer from public.business_expense_documents), 0, 'upload authority creates no expense link');
select ok(
  (select prosrc !~* '(payment|vat|bank|business_expense_documents|insert[[:space:]]+into[[:space:]]+supplier_documents)'
   from pg_proc where oid = 'public.finalize_supplier_document_upload_object_v1(text,text,text,bigint)'::regprocedure),
  'metadata finalizer introduces no document registration payment VAT banking or link mutation'
);

select * from finish();
rollback;