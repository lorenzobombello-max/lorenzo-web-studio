begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(57);

select has_table('public', 'business_expense_documents', 'business expense document junction exists');
select has_function(
  'public', 'link_business_expense_document_v1',
  array['uuid','uuid','text'],
  'owner link RPC exists'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.business_expense_documents'::regclass),
  'junction has RLS enabled'
);
select ok(
  exists (
    select 1 from pg_proc
    where oid = 'public.link_business_expense_document_v1(uuid,uuid,text)'::regprocedure
      and prosecdef
      and proconfig = array['search_path=public, auth, pg_catalog']
  ),
  'link RPC is SECURITY DEFINER with a fixed safe search_path'
);
select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'business_expense_documents'
      and column_name = 'id' and data_type = 'uuid' and is_nullable = 'NO'
  ),
  'link has a required UUID identity'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.business_expense_documents'::regclass
      and conname = 'business_expense_documents_expense_fk'
      and confrelid = 'public.business_expenses'::regclass
  ),
  'expense foreign key exists'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.business_expense_documents'::regclass
      and conname = 'business_expense_documents_document_fk'
      and confrelid = 'public.supplier_documents'::regclass
  ),
  'supplier document foreign key exists'
);
select ok(
  (select count(*) = 3 from pg_constraint
   where conrelid = 'public.business_expense_documents'::regclass and contype = 'f')
  and not exists (
    select 1 from pg_constraint c
    join pg_class target on target.oid = c.confrelid
    where c.conrelid = 'public.business_expense_documents'::regclass
      and c.contype = 'f'
      and target.relname not in ('business_expenses', 'supplier_documents', 'commercial_operators')
  ),
  'junction has no other domain foreign key'
);
select ok(
  (select bool_and(confdeltype = 'r') from pg_constraint
   where conrelid = 'public.business_expense_documents'::regclass and contype = 'f'),
  'all junction foreign keys explicitly restrict parent deletion'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.business_expense_documents'::regclass
      and conname = 'business_expense_documents_pair_unique'
      and contype = 'u'
  ),
  'expense and document pair is unique independent of relation type'
);
select matches(
  (select pg_get_constraintdef(oid) from pg_constraint
   where conrelid = 'public.business_expense_documents'::regclass
     and conname = 'business_expense_documents_relation_type_valid'),
  'INVOICE.*CREDIT_NOTE.*RECEIPT.*CONTRACT.*OTHER',
  'relation type constraint contains exactly the evidence relation types'
);
select ok(
  (select pg_get_constraintdef(oid) not like '%PAYMENT_EVIDENCE%'
   from pg_constraint
   where conrelid = 'public.business_expense_documents'::regclass
     and conname = 'business_expense_documents_relation_type_valid'),
  'PAYMENT_EVIDENCE relation type is absent'
);
select ok(
  not has_table_privilege('authenticated', 'public.business_expense_documents', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.business_expense_documents', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.business_expense_documents', 'select,insert,update,delete')
  and not has_table_privilege('public', 'public.business_expense_documents', 'select,insert,update,delete'),
  'browser and service roles have no direct junction privileges'
);
select ok(
  has_function_privilege('authenticated', 'public.link_business_expense_document_v1(uuid,uuid,text)', 'execute')
  and not has_function_privilege('anon', 'public.link_business_expense_document_v1(uuid,uuid,text)', 'execute')
  and not has_function_privilege('service_role', 'public.link_business_expense_document_v1(uuid,uuid,text)', 'execute')
  and not has_function_privilege('public', 'public.link_business_expense_document_v1(uuid,uuid,text)', 'execute'),
  'only authenticated receives guarded link RPC execution'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'business_expense_documents'
      and column_name in ('allocated_amount_minor', 'percentage', 'share', 'line_amount', 'tax_amount')
  ),
  'junction contains no amount allocation authority'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'business_expense_documents'
      and column_name in ('paid', 'unpaid', 'paid_at', 'payment_reference', 'due_date', 'outstanding', 'overdue', 'payment_evidence_id')
  ),
  'junction contains no payment authority'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'business_expense_documents'
      and column_name in ('vat_rate', 'vat_amount', 'vat_amount_minor', 'deductible_vat')
  ),
  'junction contains no VAT authority'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'business_expense_documents'
      and column_name in ('bank_transaction_id', 'bank_reference', 'iban', 'reconciliation_id')
  ),
  'junction contains no banking authority'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'business_expense_documents'
      and column_name in ('gmail_message_id', 'gmail_attachment_id', 'drive_file_id')
  ),
  'junction contains no Gmail or Drive authority'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'business_expense_documents'
      and column_name in (
        'commercial_project_id', 'project_id', 'sdf_project_id',
        'customer_request_id', 'recurring_service_id'
      )
  ),
  'junction has no commercial project SDF customer request or recurring dependency'
);
select ok(
  (select prosrc !~* 'supplier_name' from pg_proc
   where oid = 'public.link_business_expense_document_v1(uuid,uuid,text)'::regprocedure),
  'link RPC does not compare supplier strings'
);
select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.business_expense_documents'::regclass
      and tgname = 'trg_business_expense_documents_immutable'
      and tgenabled <> 'D'
  ),
  'junction immutability trigger is enabled'
);

insert into auth.users(id, email) values
  ('f6200000-0000-4000-8000-000000000001', 'link-owner@example.test'),
  ('f6200000-0000-4000-8000-000000000002', 'link-admin@example.test'),
  ('f6200000-0000-4000-8000-000000000003', 'link-disabled@example.test'),
  ('f6200000-0000-4000-8000-000000000004', 'link-revoked@example.test');

insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status, revoked_at
) values
  ('f6210000-0000-4000-8000-000000000001', 'f6200000-0000-4000-8000-000000000001', 'Link Owner', 'owner', 'ACTIVE', null),
  ('f6210000-0000-4000-8000-000000000002', 'f6200000-0000-4000-8000-000000000002', 'Link Admin', 'admin', 'ACTIVE', null),
  ('f6210000-0000-4000-8000-000000000003', 'f6200000-0000-4000-8000-000000000003', 'Link Disabled', 'owner', 'DISABLED', null),
  ('f6210000-0000-4000-8000-000000000004', 'f6200000-0000-4000-8000-000000000004', 'Link Revoked', 'owner', 'REVOKED', clock_timestamp());

insert into public.business_expenses(
  id, supplier_name, description, category, amount_minor, currency,
  expense_date, status, record_classification, created_by_operator_id
) values
  ('f6220000-0000-4000-8000-000000000001', 'Expense Supplier A', 'Production expense A', 'software', 1000, 'EUR', '2026-08-29', 'RECORDED', 'production', 'f6210000-0000-4000-8000-000000000001'),
  ('f6220000-0000-4000-8000-000000000002', 'Expense Supplier B', 'Production expense B', 'office', 2000, 'EUR', '2026-08-29', 'RECORDED', 'production', 'f6210000-0000-4000-8000-000000000001'),
  ('f6220000-0000-4000-8000-000000000003', 'Expense Supplier C', 'Production expense C', 'other', 3000, 'EUR', '2026-08-29', 'RECORDED', 'production', 'f6210000-0000-4000-8000-000000000001'),
  ('f6220000-0000-4000-8000-000000000004', 'E2E Supplier A', 'Internal expense A', 'other', 1, 'EUR', '2026-08-29', 'RECORDED', 'internal_e2e', 'f6210000-0000-4000-8000-000000000001'),
  ('f6220000-0000-4000-8000-000000000005', 'E2E Supplier B', 'Internal expense B', 'other', 1, 'EUR', '2026-08-29', 'RECORDED', 'internal_e2e', 'f6210000-0000-4000-8000-000000000001');

insert into public.supplier_documents(
  id, document_type, supplier_name, original_file_name, mime_type, byte_count,
  storage_object_path, sha256, record_classification, created_by_operator_id
) values
  ('f6230000-0000-4000-8000-000000000001', 'INVOICE', 'Different Supplier', 'invoice-a.pdf', 'application/pdf', 101, 'documents/' || repeat('1', 64) || '.pdf', repeat('1', 64), 'production', 'f6210000-0000-4000-8000-000000000001'),
  ('f6230000-0000-4000-8000-000000000002', 'CREDIT_NOTE', 'Supplier B', 'credit.pdf', 'application/pdf', 102, 'documents/' || repeat('2', 64) || '.pdf', repeat('2', 64), 'production', 'f6210000-0000-4000-8000-000000000001'),
  ('f6230000-0000-4000-8000-000000000003', 'RECEIPT', 'Supplier C', 'receipt.pdf', 'application/pdf', 103, 'documents/' || repeat('3', 64) || '.pdf', repeat('3', 64), 'production', 'f6210000-0000-4000-8000-000000000001'),
  ('f6230000-0000-4000-8000-000000000004', 'CONTRACT', 'Supplier D', 'contract.pdf', 'application/pdf', 104, 'documents/' || repeat('4', 64) || '.pdf', repeat('4', 64), 'production', 'f6210000-0000-4000-8000-000000000001'),
  ('f6230000-0000-4000-8000-000000000005', 'OTHER', 'Supplier E', 'other.pdf', 'application/pdf', 105, 'documents/' || repeat('5', 64) || '.pdf', repeat('5', 64), 'production', 'f6210000-0000-4000-8000-000000000001'),
  ('f6230000-0000-4000-8000-000000000006', 'INVOICE', 'E2E Supplier A', 'e2e-a.pdf', 'application/pdf', 106, 'documents/' || repeat('6', 64) || '.pdf', repeat('6', 64), 'internal_e2e', 'f6210000-0000-4000-8000-000000000001'),
  ('f6230000-0000-4000-8000-000000000007', 'OTHER', 'E2E Supplier B', 'e2e-b.pdf', 'application/pdf', 107, 'documents/' || repeat('7', 64) || '.pdf', repeat('7', 64), 'internal_e2e', 'f6210000-0000-4000-8000-000000000001');

select throws_ok(
  $$select public.link_business_expense_document_v1('f6220000-0000-4000-8000-000000000001','f6230000-0000-4000-8000-000000000001','INVOICE')$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'anonymous link creation is denied'
);
select set_config('request.jwt.claim.sub', 'f6200000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.link_business_expense_document_v1('f6220000-0000-4000-8000-000000000001','f6230000-0000-4000-8000-000000000001','INVOICE')$$,
  '42501', 'BUSINESS_EXPENSE_DOCUMENT_OWNER_REQUIRED', 'active non-owner is denied'
);
select set_config('request.jwt.claim.sub', 'f6200000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.link_business_expense_document_v1('f6220000-0000-4000-8000-000000000001','f6230000-0000-4000-8000-000000000001','INVOICE')$$,
  '42501', 'OPERATOR_DISABLED', 'disabled owner is denied'
);
select set_config('request.jwt.claim.sub', 'f6200000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$select public.link_business_expense_document_v1('f6220000-0000-4000-8000-000000000001','f6230000-0000-4000-8000-000000000001','INVOICE')$$,
  '42501', 'OPERATOR_REVOKED', 'revoked owner is denied'
);

select set_config('request.jwt.claim.sub', 'f6200000-0000-4000-8000-000000000001', true);
create temporary table first_link as
select public.link_business_expense_document_v1(
  'f6220000-0000-4000-8000-000000000001',
  'f6230000-0000-4000-8000-000000000001',
  ' invoice '
) as id;

select ok((select id is not null from first_link), 'active owner creates a production link');
select is((select relation_type from public.business_expense_documents where id = (select id from first_link)), 'INVOICE', 'INVOICE relation is accepted and normalized');
select is((select record_classification from public.business_expense_documents where id = (select id from first_link)), 'production', 'production classification is copied from both authorities');
select is((select created_by_operator_id from public.business_expense_documents where id = (select id from first_link)), 'f6210000-0000-4000-8000-000000000001'::uuid, 'link creator is bound to owner authority');
select is((select count(*)::integer from public.business_expense_documents where id = (select id from first_link)), 1, 'supplier name mismatch does not block a valid explicit link');

select public.link_business_expense_document_v1('f6220000-0000-4000-8000-000000000001','f6230000-0000-4000-8000-000000000002','CREDIT_NOTE');
select is((select count(*)::integer from public.business_expense_documents where relation_type = 'CREDIT_NOTE'), 1, 'CREDIT_NOTE relation is accepted without correction semantics');
select is((select count(*)::integer from public.business_expense_documents where business_expense_id = 'f6220000-0000-4000-8000-000000000001'), 2, 'one expense links to multiple supplier documents');

select public.link_business_expense_document_v1('f6220000-0000-4000-8000-000000000002','f6230000-0000-4000-8000-000000000001','RECEIPT');
select is((select count(*)::integer from public.business_expense_documents where relation_type = 'RECEIPT'), 1, 'RECEIPT relation is accepted without payment semantics');
select is((select count(*)::integer from public.business_expense_documents where supplier_document_id = 'f6230000-0000-4000-8000-000000000001'), 2, 'one supplier document links to multiple expenses');
select is((select count(distinct business_expense_id)::integer from public.business_expense_documents), 2, 'N:M expense side cardinality is proven');
select is((select count(distinct supplier_document_id)::integer from public.business_expense_documents), 2, 'N:M document side cardinality is proven');

select public.link_business_expense_document_v1('f6220000-0000-4000-8000-000000000002','f6230000-0000-4000-8000-000000000003','CONTRACT');
select is((select count(*)::integer from public.business_expense_documents where relation_type = 'CONTRACT'), 1, 'CONTRACT relation is accepted');
select public.link_business_expense_document_v1('f6220000-0000-4000-8000-000000000003','f6230000-0000-4000-8000-000000000004','OTHER');
select is((select count(*)::integer from public.business_expense_documents where relation_type = 'OTHER'), 1, 'OTHER relation is accepted');

select throws_ok(
  $$select public.link_business_expense_document_v1('f6220000-0000-4000-8000-000000000003','f6230000-0000-4000-8000-000000000005','PAYMENT_EVIDENCE')$$,
  '22023', 'INVALID_EXPENSE_DOCUMENT_RELATION_TYPE', 'PAYMENT_EVIDENCE relation is rejected'
);
select throws_ok(
  $$select public.link_business_expense_document_v1('f6220000-0000-4000-8000-000000000001','f6230000-0000-4000-8000-000000000001','OTHER')$$,
  '23505', 'BUSINESS_EXPENSE_DOCUMENT_ALREADY_LINKED', 'duplicate expense document pair is denied regardless of relation type'
);

select public.link_business_expense_document_v1('f6220000-0000-4000-8000-000000000004','f6230000-0000-4000-8000-000000000006','INVOICE');
select is((select count(*)::integer from public.business_expense_documents where record_classification = 'internal_e2e'), 1, 'internal E2E expense and document may link');
select is((select record_classification from public.business_expense_documents where business_expense_id = 'f6220000-0000-4000-8000-000000000004'), 'internal_e2e', 'internal E2E classification is copied to the link');
select throws_ok(
  $$select public.link_business_expense_document_v1('f6220000-0000-4000-8000-000000000001','f6230000-0000-4000-8000-000000000007','OTHER')$$,
  'P0001', 'EXPENSE_DOCUMENT_CLASSIFICATION_MISMATCH', 'production expense cannot link an internal E2E document'
);
select throws_ok(
  $$select public.link_business_expense_document_v1('f6220000-0000-4000-8000-000000000005','f6230000-0000-4000-8000-000000000005','OTHER')$$,
  'P0001', 'EXPENSE_DOCUMENT_CLASSIFICATION_MISMATCH', 'internal E2E expense cannot link a production document'
);
select throws_ok(
  $$select public.link_business_expense_document_v1('f6220000-0000-4000-8000-000000000099','f6230000-0000-4000-8000-000000000005','OTHER')$$,
  'P0001', 'BUSINESS_EXPENSE_NOT_FOUND', 'missing expense is denied'
);
select throws_ok(
  $$select public.link_business_expense_document_v1('f6220000-0000-4000-8000-000000000003','f6230000-0000-4000-8000-000000000099','OTHER')$$,
  'P0001', 'SUPPLIER_DOCUMENT_NOT_FOUND', 'missing supplier document is denied'
);

select throws_ok(
  $$update public.business_expense_documents set relation_type = 'OTHER'$$,
  '55000', 'BUSINESS_EXPENSE_DOCUMENT_IMMUTABLE', 'link authority cannot be updated'
);
select throws_ok(
  $$delete from public.business_expense_documents$$,
  '55000', 'BUSINESS_EXPENSE_DOCUMENT_IMMUTABLE', 'link authority cannot be deleted'
);
select throws_ok(
  $$delete from public.business_expenses where id = 'f6220000-0000-4000-8000-000000000001'$$,
  '23503', null, 'linked expense deletion is restricted without cascade'
);
select is((select count(*)::integer from public.business_expense_documents), 6, 'failed parent deletion preserves every evidence link');
select is((select amount_minor from public.business_expenses where id = 'f6220000-0000-4000-8000-000000000001'), 1000::bigint, 'linking never changes expense amount authority');
select is((select currency from public.business_expenses where id = 'f6220000-0000-4000-8000-000000000001'), 'EUR'::bpchar, 'linking never changes expense currency authority');
select is((select expense_date from public.business_expenses where id = 'f6220000-0000-4000-8000-000000000001'), '2026-08-29'::date, 'linking never changes expense date authority');
select is((select status from public.business_expenses where id = 'f6220000-0000-4000-8000-000000000001'), 'RECORDED', 'linking never changes expense lifecycle authority');
select is((select rtrim(sha256) from public.supplier_documents where id = 'f6230000-0000-4000-8000-000000000001'), repeat('1', 64), 'linking never changes supplier document binary authority');
select is((select storage_object_path from public.supplier_documents where id = 'f6230000-0000-4000-8000-000000000001'), 'documents/' || repeat('1', 64) || '.pdf', 'linking never changes supplier document storage authority');

select * from finish();
rollback;