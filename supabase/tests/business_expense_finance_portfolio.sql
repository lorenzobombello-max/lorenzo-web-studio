begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(56);

select has_function(
  'public', 'get_business_expense_portfolio_v1', array[]::text[],
  'business expense portfolio RPC exists'
);
select ok(
  exists (
    select 1 from pg_proc
    where oid = 'public.get_business_expense_portfolio_v1()'::regprocedure
      and prosecdef
      and provolatile = 's'
      and proconfig = array['search_path=public, auth, pg_catalog']
  ),
  'portfolio RPC is stable SECURITY DEFINER with a fixed safe search_path'
);
select ok(
  has_function_privilege('authenticated', 'public.get_business_expense_portfolio_v1()', 'execute')
  and not has_function_privilege('anon', 'public.get_business_expense_portfolio_v1()', 'execute')
  and not has_function_privilege('service_role', 'public.get_business_expense_portfolio_v1()', 'execute')
  and not has_function_privilege('public', 'public.get_business_expense_portfolio_v1()', 'execute'),
  'only authenticated receives guarded portfolio execution'
);
select ok(
  not has_table_privilege('authenticated', 'public.business_expenses', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.business_expenses', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.business_expenses', 'select,insert,update,delete')
  and not has_table_privilege('public', 'public.business_expenses', 'select,insert,update,delete'),
  'business expense direct table grants remain absent'
);
select ok(
  not has_table_privilege('authenticated', 'public.supplier_documents', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.supplier_documents', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.supplier_documents', 'select,insert,update,delete')
  and not has_table_privilege('public', 'public.supplier_documents', 'select,insert,update,delete'),
  'supplier document direct table grants remain absent'
);
select ok(
  not has_table_privilege('authenticated', 'public.business_expense_documents', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.business_expense_documents', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.business_expense_documents', 'select,insert,update,delete')
  and not has_table_privilege('public', 'public.business_expense_documents', 'select,insert,update,delete'),
  'expense document link direct table grants remain absent'
);

insert into auth.users(id, email) values
  ('f6d00000-0000-4000-8000-000000000001', 'portfolio-owner@example.test'),
  ('f6d00000-0000-4000-8000-000000000002', 'portfolio-admin@example.test'),
  ('f6d00000-0000-4000-8000-000000000003', 'portfolio-disabled@example.test'),
  ('f6d00000-0000-4000-8000-000000000004', 'portfolio-revoked@example.test'),
  ('f6d00000-0000-4000-8000-000000000005', 'portfolio-unknown@example.test');

insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status, revoked_at
) values
  ('f6d10000-0000-4000-8000-000000000001', 'f6d00000-0000-4000-8000-000000000001', 'Portfolio Owner', 'owner', 'ACTIVE', null),
  ('f6d10000-0000-4000-8000-000000000002', 'f6d00000-0000-4000-8000-000000000002', 'Portfolio Admin', 'admin', 'ACTIVE', null),
  ('f6d10000-0000-4000-8000-000000000003', 'f6d00000-0000-4000-8000-000000000003', 'Portfolio Disabled', 'owner', 'DISABLED', null),
  ('f6d10000-0000-4000-8000-000000000004', 'f6d00000-0000-4000-8000-000000000004', 'Portfolio Revoked', 'owner', 'REVOKED', clock_timestamp());

select throws_ok(
  $$select public.get_business_expense_portfolio_v1()$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'anonymous portfolio access is denied'
);
select set_config('request.jwt.claim.sub', 'f6d00000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select public.get_business_expense_portfolio_v1()$$,
  '42501', 'UNKNOWN_OPERATOR', 'unknown operator is denied'
);
select set_config('request.jwt.claim.sub', 'f6d00000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.get_business_expense_portfolio_v1()$$,
  '42501', 'BUSINESS_EXPENSE_FINANCE_PORTFOLIO_OWNER_REQUIRED', 'active non-owner is denied'
);
select set_config('request.jwt.claim.sub', 'f6d00000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.get_business_expense_portfolio_v1()$$,
  '42501', 'OPERATOR_DISABLED', 'disabled owner is denied'
);
select set_config('request.jwt.claim.sub', 'f6d00000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$select public.get_business_expense_portfolio_v1()$$,
  '42501', 'OPERATOR_REVOKED', 'revoked owner is denied'
);

select set_config('request.jwt.claim.sub', 'f6d00000-0000-4000-8000-000000000001', true);
create temporary table zero_portfolio as
select public.get_business_expense_portfolio_v1() as payload;

select is((select payload->>'scope' from zero_portfolio), 'business_expenses', 'portfolio scope is stable');
select is((select (payload->>'expense_count')::integer from zero_portfolio), 0, 'zero state has no production expenses');
select is((select payload->'currency_totals' from zero_portfolio), '[]'::jsonb, 'zero state currency totals are empty');
select is((select payload->'expenses' from zero_portfolio), '[]'::jsonb, 'zero state expense list is empty');
select is(
  (select payload->'availability' from zero_portfolio),
  '{"vat_available":false,"overdue_available":false,"upcoming_available":false,"paid_date_available":false,"paid_amount_available":false,"recurring_available":false,"outstanding_available":false,"bank_actuals_available":false,"payment_state_available":false,"deductible_vat_available":false,"confirmed_cash_out_available":false}'::jsonb,
  'zero state availability remains explicit and semantically unavailable'
);
select ok((select payload->'bank_actuals' = 'null'::jsonb from zero_portfolio), 'zero state bank actuals are null, not zero');

-- The live authority currently permits EUR only; this transaction-local relaxation exercises currency separation without changing production schema.
alter table public.business_expenses
drop constraint business_expenses_currency_valid;

insert into public.business_expenses(
  id, supplier_name, description, category, amount_minor, currency,
  expense_date, status, record_classification, created_by_operator_id, created_at
) values
  ('f6d20000-0000-4000-8000-000000000001', 'Expense Supplier A', 'Primary recorded expense', 'software', 1000, 'EUR', '2026-08-29', 'RECORDED', 'production', 'f6d10000-0000-4000-8000-000000000001', '2026-08-29 10:00:00+00'),
  ('f6d20000-0000-4000-8000-000000000002', 'Expense Supplier B', 'Second recorded expense', 'office', 2000, 'EUR', '2026-08-28', 'RECORDED', 'production', 'f6d10000-0000-4000-8000-000000000001', '2026-08-29 09:00:00+00'),
  ('f6d20000-0000-4000-8000-000000000003', 'Expense Supplier C', 'Cancelled retained expense', 'other', 5000, 'EUR', '2026-08-27', 'CANCELLED', 'production', 'f6d10000-0000-4000-8000-000000000001', '2026-08-29 08:00:00+00'),
  ('f6d20000-0000-4000-8000-000000000004', 'USD Supplier', 'Separate currency expense', 'other', 3000, 'USD', '2026-08-26', 'RECORDED', 'production', 'f6d10000-0000-4000-8000-000000000001', '2026-08-29 07:00:00+00'),
  ('f6d20000-0000-4000-8000-000000000005', 'Internal Supplier', 'Internal fixture expense', 'other', 999999, 'EUR', '2026-08-30', 'RECORDED', 'internal_e2e', 'f6d10000-0000-4000-8000-000000000001', '2026-08-29 11:00:00+00');

insert into public.supplier_documents(
  id, document_type, supplier_name, original_file_name, mime_type, byte_count,
  storage_object_path, sha256, record_classification, created_by_operator_id
) values
  ('f6d30000-0000-4000-8000-000000000001', 'INVOICE', 'Document Supplier X', 'invoice.pdf', 'application/pdf', 101, 'documents/' || repeat('a', 64) || '.pdf', repeat('a', 64), 'production', 'f6d10000-0000-4000-8000-000000000001'),
  ('f6d30000-0000-4000-8000-000000000002', 'CREDIT_NOTE', 'Document Supplier A', 'credit.pdf', 'application/pdf', 102, 'documents/' || repeat('b', 64) || '.pdf', repeat('b', 64), 'production', 'f6d10000-0000-4000-8000-000000000001'),
  ('f6d30000-0000-4000-8000-000000000003', 'OTHER', 'Document Supplier A', 'other.pdf', 'application/pdf', 103, 'documents/' || repeat('c', 64) || '.pdf', repeat('c', 64), 'production', 'f6d10000-0000-4000-8000-000000000001');

insert into public.business_expense_documents(
  business_expense_id, supplier_document_id, relation_type,
  record_classification, created_by_operator_id
) values
  ('f6d20000-0000-4000-8000-000000000001', 'f6d30000-0000-4000-8000-000000000001', 'INVOICE', 'production', 'f6d10000-0000-4000-8000-000000000001'),
  ('f6d20000-0000-4000-8000-000000000001', 'f6d30000-0000-4000-8000-000000000002', 'CREDIT_NOTE', 'production', 'f6d10000-0000-4000-8000-000000000001'),
  ('f6d20000-0000-4000-8000-000000000001', 'f6d30000-0000-4000-8000-000000000003', 'OTHER', 'production', 'f6d10000-0000-4000-8000-000000000001'),
  ('f6d20000-0000-4000-8000-000000000002', 'f6d30000-0000-4000-8000-000000000001', 'RECEIPT', 'production', 'f6d10000-0000-4000-8000-000000000001');

create temporary table populated_portfolio as
select public.get_business_expense_portfolio_v1() as payload;

select is((select (payload->>'expense_count')::integer from populated_portfolio), 4, 'expense count includes all production records including cancelled');
select ok((select payload::text not like '%Internal fixture expense%' from populated_portfolio), 'internal E2E expense is excluded');
select is((select jsonb_array_length(payload->'expenses') from populated_portfolio), 4, 'only production expense rows are returned');
select is((select (item->>'amount_minor')::bigint from populated_portfolio cross join lateral jsonb_array_elements(payload->'expenses') item where item->>'id' = 'f6d20000-0000-4000-8000-000000000001'), 1000::bigint, 'amount_minor remains exact');
select is((select item->>'currency' from populated_portfolio cross join lateral jsonb_array_elements(payload->'expenses') item where item->>'id' = 'f6d20000-0000-4000-8000-000000000001'), 'EUR', 'expense currency remains exact');
select is((select jsonb_array_length(payload->'currency_totals') from populated_portfolio), 2, 'multiple currencies remain separated');
select is((select jsonb_agg(item->>'currency' order by ordinal) from populated_portfolio cross join lateral jsonb_array_elements(payload->'currency_totals') with ordinality as totals(item, ordinal)), '["EUR","USD"]'::jsonb, 'currency totals are deterministically sorted');
select ok((select bool_and((item->>'active_expense_minor') ~ '^[0-9]+$') from populated_portfolio cross join lateral jsonb_array_elements(payload->'currency_totals') item), 'currency aggregation uses integer minor units without floats');
select is((select (item->>'active_expense_minor')::bigint from populated_portfolio cross join lateral jsonb_array_elements(payload->'currency_totals') item where item->>'currency' = 'EUR'), 3000::bigint, 'active EUR total includes only RECORDED expense amounts');
select isnt((select (item->>'active_expense_minor')::bigint from populated_portfolio cross join lateral jsonb_array_elements(payload->'currency_totals') item where item->>'currency' = 'EUR'), 8000::bigint, 'cancelled amount is excluded from active total');
select is((select item->>'status' from populated_portfolio cross join lateral jsonb_array_elements(payload->'expenses') item where item->>'id' = 'f6d20000-0000-4000-8000-000000000003'), 'CANCELLED', 'cancelled record remains visible with explicit status');
select is((select item->>'supplier_name' from populated_portfolio cross join lateral jsonb_array_elements(payload->'expenses') item where item->>'id' = 'f6d20000-0000-4000-8000-000000000001'), 'Expense Supplier A', 'supplier comes from business expense authority, not document metadata');
select is((select item->>'description' from populated_portfolio cross join lateral jsonb_array_elements(payload->'expenses') item where item->>'id' = 'f6d20000-0000-4000-8000-000000000001'), 'Primary recorded expense', 'expense description is returned');
select is((select item->>'category' from populated_portfolio cross join lateral jsonb_array_elements(payload->'expenses') item where item->>'id' = 'f6d20000-0000-4000-8000-000000000001'), 'software', 'expense category is returned');
select is((select item->>'expense_date' from populated_portfolio cross join lateral jsonb_array_elements(payload->'expenses') item where item->>'id' = 'f6d20000-0000-4000-8000-000000000001'), '2026-08-29', 'expense date is returned');
select is((select item->>'status' from populated_portfolio cross join lateral jsonb_array_elements(payload->'expenses') item where item->>'id' = 'f6d20000-0000-4000-8000-000000000001'), 'RECORDED', 'active expense lifecycle status is returned');
select is((select (item->>'document_count')::integer from populated_portfolio cross join lateral jsonb_array_elements(payload->'expenses') item where item->>'id' = 'f6d20000-0000-4000-8000-000000000001'), 3, 'document count is exact for multiple links');
select is((select item->'relation_types' from populated_portfolio cross join lateral jsonb_array_elements(payload->'expenses') item where item->>'id' = 'f6d20000-0000-4000-8000-000000000001'), '["CREDIT_NOTE","INVOICE","OTHER"]'::jsonb, 'relation types are unique and deterministically sorted');
select ok((select payload::text not like '%PAYMENT_EVIDENCE%' from populated_portfolio), 'PAYMENT_EVIDENCE is absent');
select ok((select payload::text !~ '(storage_object_path|storage_bucket_id|bucket_id)' from populated_portfolio), 'storage path and bucket identity are not exposed');
select ok((select payload::text not like '%sha256%' from populated_portfolio), 'SHA-256 is not exposed');
select ok((select payload::text !~ '(signed_url|binary|mime_type|byte_count)' from populated_portfolio), 'signed URL binary MIME and byte metadata are not exposed');
select is((select payload->'availability'->>'payment_state_available' from populated_portfolio), 'false', 'payment state availability is false');
select is((select payload->'availability'->>'paid_amount_available' from populated_portfolio), 'false', 'paid amount availability is false');
select is((select payload->'availability'->>'paid_date_available' from populated_portfolio), 'false', 'paid date availability is false');
select is((select payload->'availability'->>'confirmed_cash_out_available' from populated_portfolio), 'false', 'confirmed cash-out availability is false');
select is((select payload->'availability'->>'outstanding_available' from populated_portfolio), 'false', 'outstanding availability is false');
select is((select payload->'availability'->>'overdue_available' from populated_portfolio), 'false', 'overdue availability is false');
select is((select payload->'availability'->>'upcoming_available' from populated_portfolio), 'false', 'upcoming availability is false');
select is((select payload->'availability'->>'vat_available' from populated_portfolio), 'false', 'VAT availability is false');
select is((select payload->'availability'->>'deductible_vat_available' from populated_portfolio), 'false', 'deductible VAT availability is false');
select is((select payload->'availability'->>'bank_actuals_available' from populated_portfolio), 'false', 'bank actuals availability is false');
select ok((select payload->'bank_actuals' = 'null'::jsonb from populated_portfolio), 'bank actuals remain null');
select is((select payload->'availability'->>'recurring_available' from populated_portfolio), 'false', 'recurring availability is false');
select ok(
  (select prosrc !~* '(commercial_projects|sdf_projects|payment_evidence|recurring_services|customer_request)' from pg_proc
   where oid = 'public.get_business_expense_portfolio_v1()'::regprocedure),
  'portfolio has no commercial project SDF customer payment or recurring dependency'
);
select is((select (item->>'active_expense_minor')::bigint from populated_portfolio cross join lateral jsonb_array_elements(payload->'currency_totals') item where item->>'currency' = 'EUR'), 3000::bigint, 'document links never multiply the expense total');
select is((select count(*)::integer from populated_portfolio cross join lateral jsonb_array_elements(payload->'expenses') item where item->>'id' in ('f6d20000-0000-4000-8000-000000000001','f6d20000-0000-4000-8000-000000000002')), 2, 'one shared document does not merge distinct expenses');
select is((select jsonb_agg(item->>'id' order by ordinal) from populated_portfolio cross join lateral jsonb_array_elements(payload->'expenses') with ordinality as expense(item, ordinal)), '["f6d20000-0000-4000-8000-000000000001","f6d20000-0000-4000-8000-000000000002","f6d20000-0000-4000-8000-000000000003","f6d20000-0000-4000-8000-000000000004"]'::jsonb, 'expenses have deterministic date created-at and ID ordering');
select is(
  (select array_agg(key order by key) from populated_portfolio cross join lateral jsonb_object_keys(payload) key),
  array['availability','bank_actuals','currency_totals','expense_count','expenses','scope']::text[],
  'root output contract has only stable expected keys'
);

select * from finish();
rollback;