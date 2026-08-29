begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(39);

select has_table('public', 'business_expenses', 'business expense core authority exists');
select has_function(
  'public', 'create_business_expense_v1',
  array['text','text','text','bigint','text','date','text','text'],
  'owner creation RPC exists'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.business_expenses'::regclass),
  'business expense table has RLS enabled'
);
select ok(
  exists (
    select 1 from pg_proc
    where oid = 'public.create_business_expense_v1(text,text,text,bigint,text,date,text,text)'::regprocedure
      and prosecdef
      and proconfig = array['search_path=public, auth, pg_catalog']
  ),
  'creation RPC is SECURITY DEFINER with a fixed safe search_path'
);
select ok(
  has_function_privilege('authenticated', 'public.create_business_expense_v1(text,text,text,bigint,text,date,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.create_business_expense_v1(text,text,text,bigint,text,date,text,text)', 'execute')
  and not has_function_privilege('service_role', 'public.create_business_expense_v1(text,text,text,bigint,text,date,text,text)', 'execute')
  and not has_function_privilege('public', 'public.create_business_expense_v1(text,text,text,bigint,text,date,text,text)', 'execute'),
  'only authenticated receives guarded RPC execute privilege'
);
select ok(
  not has_table_privilege('authenticated', 'public.business_expenses', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.business_expenses', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.business_expenses', 'select,insert,update,delete')
  and not has_table_privilege('public', 'public.business_expenses', 'select,insert,update,delete'),
  'browser and service roles have no direct table privileges'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'business_expenses'
      and column_name in (
        'paid', 'paid_at', 'payment_state', 'payment_reference',
        'vat_rate', 'vat_amount_minor', 'deductible_vat', 'net_amount_minor', 'gross_amount_minor',
        'document_id', 'invoice_number', 'invoice_date', 'due_date', 'storage_path', 'file_sha256'
      )
  ),
  'core authority adds no payment VAT or document semantics'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'business_expenses'
      and column_name in ('project_id', 'commercial_project_id', 'sdf_project_id')
  ),
  'business expense identity is standalone from all project types'
);
select ok(
  not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.business_expenses'::regclass
      and contype = 'u'
  ),
  'no business-field uniqueness rule rejects legitimate duplicate expenses'
);

insert into auth.users(id, email) values
  ('f6000000-0000-4000-8000-000000000001', 'expense-owner@example.test'),
  ('f6000000-0000-4000-8000-000000000002', 'expense-admin@example.test'),
  ('f6000000-0000-4000-8000-000000000003', 'expense-disabled@example.test'),
  ('f6000000-0000-4000-8000-000000000004', 'expense-revoked@example.test');

insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status, revoked_at
) values
  ('f6010000-0000-4000-8000-000000000001', 'f6000000-0000-4000-8000-000000000001', 'Expense Owner', 'owner', 'ACTIVE', null),
  ('f6010000-0000-4000-8000-000000000002', 'f6000000-0000-4000-8000-000000000002', 'Expense Admin', 'admin', 'ACTIVE', null),
  ('f6010000-0000-4000-8000-000000000003', 'f6000000-0000-4000-8000-000000000003', 'Expense Disabled', 'owner', 'DISABLED', null),
  ('f6010000-0000-4000-8000-000000000004', 'f6000000-0000-4000-8000-000000000004', 'Expense Revoked', 'owner', 'REVOKED', clock_timestamp());

select throws_ok(
  $$select public.create_business_expense_v1('Supplier','Purpose','software',1000,'EUR','2026-08-29')$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'missing human JWT is denied'
);

select set_config('request.jwt.claim.sub', 'f6000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.create_business_expense_v1('Supplier','Purpose','software',1000,'EUR','2026-08-29')$$,
  '42501', 'BUSINESS_EXPENSE_OWNER_REQUIRED', 'active non-owner is denied'
);

select set_config('request.jwt.claim.sub', 'f6000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.create_business_expense_v1('Supplier','Purpose','software',1000,'EUR','2026-08-29')$$,
  '42501', 'OPERATOR_DISABLED', 'disabled owner is denied'
);

select set_config('request.jwt.claim.sub', 'f6000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$select public.create_business_expense_v1('Supplier','Purpose','software',1000,'EUR','2026-08-29')$$,
  '42501', 'OPERATOR_REVOKED', 'revoked owner is denied'
);

select set_config('request.jwt.claim.sub', 'f6000000-0000-4000-8000-000000000001', true);
create temporary table created_expense as
select public.create_business_expense_v1(
  '  Example Supplier  ', '  Annual development tool  ', ' SOFTWARE ', 12345,
  ' eur ', '2026-08-29', 'production', '  OPS-2026-001  '
) as id;

select ok((select id is not null from created_expense), 'owner creates a business expense through the approved path');
select is((select supplier_name from public.business_expenses where id = (select id from created_expense)), 'Example Supplier', 'supplier name is required and normalized');
select is((select description from public.business_expenses where id = (select id from created_expense)), 'Annual development tool', 'description is required and normalized');
select is((select category from public.business_expenses where id = (select id from created_expense)), 'software', 'category is server-normalized and controlled');
select is((select amount_minor from public.business_expenses where id = (select id from created_expense)), 12345::bigint, 'integer minor units remain exact');
select is((select currency from public.business_expenses where id = (select id from created_expense)), 'EUR'::bpchar, 'currency is authoritative EUR');
select is((select expense_date from public.business_expenses where id = (select id from created_expense)), '2026-08-29'::date, 'expense date is authoritative and required');
select is((select status from public.business_expenses where id = (select id from created_expense)), 'RECORDED', 'new expense lifecycle starts recorded, not paid or unpaid');
select is((select internal_reference from public.business_expenses where id = (select id from created_expense)), 'OPS-2026-001', 'internal reference is normalized without becoming invoice authority');
select is((select record_classification from public.business_expenses where id = (select id from created_expense)), 'production', 'production classification is explicit');
select is((select created_by_operator_id from public.business_expenses where id = (select id from created_expense)), 'f6010000-0000-4000-8000-000000000001'::uuid, 'creator is bound to owner operator authority');

select throws_ok(
  $$select public.create_business_expense_v1(null,'Purpose','software',1000,'EUR','2026-08-29')$$,
  '22023', 'INVALID_BUSINESS_EXPENSE_SUPPLIER', 'supplier is required'
);
select throws_ok(
  $$select public.create_business_expense_v1('Supplier','  ','software',1000,'EUR','2026-08-29')$$,
  '22023', 'INVALID_BUSINESS_EXPENSE_DESCRIPTION', 'description is required'
);
select throws_ok(
  $$select public.create_business_expense_v1('Supplier','Purpose','travel',1000,'EUR','2026-08-29')$$,
  '22023', 'INVALID_BUSINESS_EXPENSE_CATEGORY', 'unknown category is denied'
);
select throws_ok(
  $$select public.create_business_expense_v1('Supplier','Purpose','software',-1,'EUR','2026-08-29')$$,
  '22023', 'INVALID_BUSINESS_EXPENSE_AMOUNT', 'negative amount is denied'
);
select throws_ok(
  $$select public.create_business_expense_v1('Supplier','Purpose','software',0,'EUR','2026-08-29')$$,
  '22023', 'INVALID_BUSINESS_EXPENSE_AMOUNT', 'zero amount is explicitly denied'
);
select throws_ok(
  $$select public.create_business_expense_v1('Supplier','Purpose','software',1000,'USD','2026-08-29')$$,
  '22023', 'INVALID_BUSINESS_EXPENSE_CURRENCY', 'unsupported currency is denied'
);
select throws_ok(
  $$select public.create_business_expense_v1('Supplier','Purpose','software',1000,'EUR',null)$$,
  '22023', 'INVALID_BUSINESS_EXPENSE_DATE', 'expense date is required'
);
select throws_ok(
  $$select public.create_business_expense_v1('Supplier','Purpose','software',1000,'EUR','2026-08-29','fixture')$$,
  '22023', 'INVALID_BUSINESS_EXPENSE_CLASSIFICATION', 'unknown record classification is denied'
);

select public.create_business_expense_v1(
  'Equal Supplier', 'First legitimate expense', 'office', 5000, 'EUR', '2026-08-28'
);
select public.create_business_expense_v1(
  'Equal Supplier', 'Second legitimate expense', 'office', 5000, 'EUR', '2026-08-28'
);
select is(
  (select count(*)::integer from public.business_expenses where supplier_name = 'Equal Supplier'),
  2, 'equal supplier amount and date expenses may coexist'
);

select public.create_business_expense_v1(
  'Fixture Supplier', 'Isolated expense fixture', 'other', 1, 'EUR', '2026-08-29', 'internal_e2e'
);
select is(
  (select count(*)::integer from public.business_expenses where record_classification = 'internal_e2e'),
  1, 'internal E2E expenses are explicitly separable from production'
);
select is(
  (select count(*)::integer from public.business_expenses where record_classification = 'production'),
  3, 'production selection excludes internal E2E expense records'
);

select is((select count(*)::integer from public.external_costs), 0, 'expense creation has no external costs dependency');
select is((select count(*)::integer from public.recurring_services), 0, 'expense creation has no recurring services dependency');
select is((select count(*)::integer from public.payment_evidence), 0, 'expense creation has no customer payment dependency');

select throws_ok(
  $$insert into public.business_expenses(
      supplier_name, description, category, amount_minor, currency, expense_date,
      status, record_classification, created_by_operator_id
    ) values (
      'Supplier', 'Purpose', 'software', 1000, 'EUR', '2026-08-29',
      'PAID', 'production', 'f6010000-0000-4000-8000-000000000001'
    )$$,
  '23514', null, 'payment-like lifecycle status is rejected'
);

select * from finish();
rollback;