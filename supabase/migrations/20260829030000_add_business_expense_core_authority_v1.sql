create table public.business_expenses (
  id uuid primary key default gen_random_uuid(),
  supplier_name text not null,
  description text not null,
  category text not null,
  amount_minor bigint not null,
  currency char(3) not null,
  expense_date date not null,
  status text not null default 'RECORDED',
  internal_reference text,
  record_classification text not null default 'production',
  created_by_operator_id uuid not null references public.commercial_operators(operator_id),
  created_at timestamptz not null default clock_timestamp(),
  constraint business_expenses_supplier_name_valid check (
    supplier_name = btrim(supplier_name)
    and length(supplier_name) between 1 and 200
  ),
  constraint business_expenses_description_valid check (
    description = btrim(description)
    and length(description) between 1 and 1000
  ),
  constraint business_expenses_category_valid check (
    category in (
      'software', 'hosting', 'telecom', 'accounting', 'hardware',
      'marketing', 'insurance', 'education', 'office', 'transport', 'other'
    )
  ),
  constraint business_expenses_amount_minor_valid check (amount_minor > 0),
  constraint business_expenses_currency_valid check (currency = 'EUR'),
  constraint business_expenses_status_valid check (status in ('RECORDED', 'CANCELLED')),
  constraint business_expenses_internal_reference_valid check (
    internal_reference is null
    or (
      internal_reference = btrim(internal_reference)
      and length(internal_reference) between 1 and 200
    )
  ),
  constraint business_expenses_record_classification_valid check (
    record_classification in ('production', 'internal_e2e')
  )
);

alter table public.business_expenses enable row level security;

create function public.create_business_expense_v1(
  p_supplier_name text,
  p_description text,
  p_category text,
  p_amount_minor bigint,
  p_currency text,
  p_expense_date date,
  p_record_classification text default 'production',
  p_internal_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_expense_id uuid;
  v_supplier_name text := btrim(p_supplier_name);
  v_description text := btrim(p_description);
  v_category text := lower(btrim(p_category));
  v_currency text := upper(btrim(p_currency));
  v_internal_reference text := nullif(btrim(p_internal_reference), '');
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select *
  into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;

  if not found then
    raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR';
  end if;
  if v_operator.status = 'DISABLED' then
    raise exception using errcode = '42501', message = 'OPERATOR_DISABLED';
  end if;
  if v_operator.status = 'REVOKED' then
    raise exception using errcode = '42501', message = 'OPERATOR_REVOKED';
  end if;
  if v_operator.status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;
  if v_operator.role <> 'owner' then
    raise exception using errcode = '42501', message = 'BUSINESS_EXPENSE_OWNER_REQUIRED';
  end if;

  if v_supplier_name is null or length(v_supplier_name) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'INVALID_BUSINESS_EXPENSE_SUPPLIER';
  end if;
  if v_description is null or length(v_description) not between 1 and 1000 then
    raise exception using errcode = '22023', message = 'INVALID_BUSINESS_EXPENSE_DESCRIPTION';
  end if;
  if v_category is null or v_category not in (
    'software', 'hosting', 'telecom', 'accounting', 'hardware',
    'marketing', 'insurance', 'education', 'office', 'transport', 'other'
  ) then
    raise exception using errcode = '22023', message = 'INVALID_BUSINESS_EXPENSE_CATEGORY';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception using errcode = '22023', message = 'INVALID_BUSINESS_EXPENSE_AMOUNT';
  end if;
  if v_currency is distinct from 'EUR' then
    raise exception using errcode = '22023', message = 'INVALID_BUSINESS_EXPENSE_CURRENCY';
  end if;
  if p_expense_date is null then
    raise exception using errcode = '22023', message = 'INVALID_BUSINESS_EXPENSE_DATE';
  end if;
  if p_record_classification is null
     or p_record_classification not in ('production', 'internal_e2e') then
    raise exception using errcode = '22023', message = 'INVALID_BUSINESS_EXPENSE_CLASSIFICATION';
  end if;
  if v_internal_reference is not null and length(v_internal_reference) > 200 then
    raise exception using errcode = '22023', message = 'INVALID_BUSINESS_EXPENSE_INTERNAL_REFERENCE';
  end if;

  insert into public.business_expenses (
    supplier_name, description, category, amount_minor, currency,
    expense_date, internal_reference, record_classification,
    created_by_operator_id
  ) values (
    v_supplier_name, v_description, v_category, p_amount_minor, v_currency,
    p_expense_date, v_internal_reference, p_record_classification,
    v_operator.operator_id
  )
  returning id into v_expense_id;

  return v_expense_id;
end;
$$;

revoke all on table public.business_expenses
from public, anon, authenticated, service_role;

revoke all on function public.create_business_expense_v1(
  text, text, text, bigint, text, date, text, text
)
from public, anon, authenticated, service_role;

grant execute on function public.create_business_expense_v1(
  text, text, text, bigint, text, date, text, text
)
to authenticated;

comment on table public.business_expenses is
  'Standalone LWS business expense authority. Excludes customer revenue, owner-private expenses, documents, payments, bank transactions and VAT authority.';

comment on column public.business_expenses.amount_minor is
  'Authoritative business expense commitment/base amount in integer minor units; not a net, VAT, gross or paid amount.';

comment on column public.business_expenses.expense_date is
  'Date on which the business expense is economically recorded; not an invoice, due, creation or payment date.';

comment on column public.business_expenses.status is
  'Record lifecycle status only; never a payment state.';

comment on column public.business_expenses.internal_reference is
  'Optional internal recognition reference; never a supplier invoice authority.';

comment on function public.create_business_expense_v1(
  text, text, text, bigint, text, date, text, text
) is
  'Owner-only creation boundary for standalone LWS business expenses.';