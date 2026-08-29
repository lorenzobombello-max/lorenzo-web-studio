create function public.get_business_expense_portfolio_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_actor_role text;
  v_actor_status text;
  v_result jsonb;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select role, status
  into v_actor_role, v_actor_status
  from public.commercial_operators
  where auth_user_id = v_subject;

  if not found then
    raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR';
  end if;
  if v_actor_status = 'DISABLED' then
    raise exception using errcode = '42501', message = 'OPERATOR_DISABLED';
  end if;
  if v_actor_status = 'REVOKED' then
    raise exception using errcode = '42501', message = 'OPERATOR_REVOKED';
  end if;
  if v_actor_status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;
  if v_actor_role <> 'owner' then
    raise exception using errcode = '42501', message = 'BUSINESS_EXPENSE_FINANCE_PORTFOLIO_OWNER_REQUIRED';
  end if;

  with portfolio_rows as (
    select
      expense.id,
      expense.supplier_name,
      expense.description,
      expense.category,
      expense.amount_minor,
      expense.currency,
      expense.expense_date,
      expense.status,
      expense.created_at,
      (
        select count(*)
        from public.business_expense_documents as link
        where link.business_expense_id = expense.id
          and link.record_classification = 'production'
      ) as document_count,
      coalesce((
        select jsonb_agg(relation.relation_type order by relation.relation_type)
        from (
          select distinct link.relation_type
          from public.business_expense_documents as link
          where link.business_expense_id = expense.id
            and link.record_classification = 'production'
        ) as relation
      ), '[]'::jsonb) as relation_types
    from public.business_expenses as expense
    where expense.record_classification = 'production'
  ), currency_rows as (
    select
      currency,
      coalesce(sum(amount_minor) filter (where status = 'RECORDED'), 0) as active_expense_minor
    from portfolio_rows
    group by currency
  )
  select jsonb_build_object(
    'scope', 'business_expenses',
    'expense_count', (select count(*) from portfolio_rows),
    'currency_totals', coalesce((
      select jsonb_agg(jsonb_build_object(
        'currency', currency,
        'active_expense_minor', active_expense_minor
      ) order by currency)
      from currency_rows
    ), '[]'::jsonb),
    'expenses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'supplier_name', supplier_name,
        'description', description,
        'category', category,
        'amount_minor', amount_minor,
        'currency', currency,
        'expense_date', expense_date,
        'status', status,
        'document_count', document_count,
        'relation_types', relation_types
      ) order by expense_date desc, created_at desc, id desc)
      from portfolio_rows
    ), '[]'::jsonb),
    'availability', jsonb_build_object(
      'payment_state_available', false,
      'paid_amount_available', false,
      'paid_date_available', false,
      'confirmed_cash_out_available', false,
      'outstanding_available', false,
      'overdue_available', false,
      'upcoming_available', false,
      'vat_available', false,
      'deductible_vat_available', false,
      'bank_actuals_available', false,
      'recurring_available', false
    ),
    'bank_actuals', null
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_business_expense_portfolio_v1()
from public, anon, authenticated, service_role;

grant execute on function public.get_business_expense_portfolio_v1()
to authenticated;

comment on function public.get_business_expense_portfolio_v1() is
  'Owner-only production business-expense portfolio. Lists RECORDED and CANCELLED records, totals only RECORDED amount_minor per currency, summarizes document links without binary metadata, and marks payment, VAT, banking, outstanding and recurring authority unavailable.';