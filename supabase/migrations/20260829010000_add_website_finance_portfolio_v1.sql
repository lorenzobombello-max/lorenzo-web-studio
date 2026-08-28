create function public.get_website_finance_portfolio_v1()
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
    raise exception using errcode = '42501', message = 'WEBSITE_FINANCE_PORTFOLIO_OWNER_REQUIRED';
  end if;

  with website_projects as (
    select
      project.project_id,
      project.currency,
      project.accepted_total_minor,
      project.m1_minor,
      project.m2_minor,
      project.m3_minor,
      project.created_at as project_created_at,
      request.application_reference,
      request.request_kind
    from public.commercial_projects as project
    join public.quote_request_quotation_acceptances as acceptance
      on acceptance.id = project.acceptance_id
    join public.quote_request_quotation_issuances as issuance
      on issuance.id = acceptance.issuance_id
    join public.quote_request_quotation_approvals as approval
      on approval.id = issuance.approval_id
    join public.quote_requests as request
      on request.id = approval.quote_request_id
    where request.record_classification = 'production'
      and request.request_kind = 'website'
  ), projected as (
    select
      website.*,
      public.get_commercial_project_view_v2(website.project_id) as project_view
    from website_projects as website
  ), portfolio_rows as (
    select
      projected.project_id,
      projected.application_reference,
      projected.request_kind,
      projected.currency,
      projected.accepted_total_minor,
      projected.m1_minor,
      projected.m2_minor,
      projected.m3_minor,
      projected.project_created_at,
      (projected.project_view->'financial_summary'->>'expected_minor')::bigint as expected_minor,
      (projected.project_view->'financial_summary'->>'received_minor')::bigint as confirmed_received_minor,
      (
        select jsonb_agg(
          milestone.value || jsonb_build_object(
            'commitment_minor', obligation.amount_minor,
            'obligation_created_at', obligation.created_at,
            'expectation_created_at', expectation.created_at,
            'transaction_date', evidence.transaction_date,
            'verification_date', evidence.verified_at,
            'reconciliation_date', reconciliation.decided_at,
            'payment_confirmation_date', confirmation.occurred_at
          )
          order by (milestone.value->>'milestone')::smallint
        )
        from jsonb_array_elements(
          projected.project_view->'financial_summary'->'milestones'
        ) as milestone(value)
        left join public.commercial_obligations as obligation
          on obligation.project_id = projected.project_id
          and obligation.obligation_type = 'PROJECT_MILESTONE'
          and obligation.milestone = (milestone.value->>'milestone')::smallint
        left join public.payment_expectations as expectation
          on expectation.project_id = projected.project_id
          and expectation.obligation_id = obligation.obligation_id
        left join lateral (
          select payment.transaction_date, payment.verified_at
          from public.payment_evidence as payment
          where payment.project_id = projected.project_id
            and payment.obligation_id = obligation.obligation_id
          order by payment.created_at desc, payment.payment_evidence_id desc
          limit 1
        ) as evidence on true
        left join lateral (
          select matched.decided_at
          from public.payment_reconciliations as matched
          where matched.project_id = projected.project_id
            and matched.obligation_id = obligation.obligation_id
          order by matched.decided_at desc, matched.payment_reconciliation_id desc
          limit 1
        ) as reconciliation on true
        left join lateral (
          select max(event.occurred_at) as occurred_at
          from public.workflow_events as event
          where event.project_id = projected.project_id
            and event.new_state = case (milestone.value->>'milestone')::smallint
              when 1 then 'M1_PAYMENT_RECEIVED'
              when 2 then 'M2_PAYMENT_RECEIVED'
              when 3 then 'FULL_PAYMENT_RECEIVED'
            end
        ) as confirmation on true
      ) as milestones
    from projected
  ), currency_rows as (
    select
      currency,
      sum(accepted_total_minor) as total_commitment_minor,
      sum(expected_minor) as total_expected_minor,
      sum(confirmed_received_minor) as total_confirmed_received_minor
    from portfolio_rows
    group by currency
  )
  select jsonb_build_object(
    'scope', 'website',
    'invoice_projection_available', false,
    'outstanding_projection_available', false,
    'overdue_projection_available', false,
    'upcoming_projection_available', false,
    'recurring_amount_projection_available', false,
    'bank_actuals_projection_available', false,
    'bank_actuals', null,
    'currency_totals', coalesce((
      select jsonb_agg(jsonb_build_object(
        'currency', currency,
        'total_commitment_minor', total_commitment_minor,
        'total_expected_minor', total_expected_minor,
        'total_confirmed_received_minor', total_confirmed_received_minor
      ) order by currency)
      from currency_rows
    ), '[]'::jsonb),
    'projects', coalesce((
      select jsonb_agg(jsonb_build_object(
        'project_id', project_id,
        'application_reference', application_reference,
        'request_kind', request_kind,
        'currency', currency,
        'accepted_total_minor', accepted_total_minor,
        'm1_minor', m1_minor,
        'm2_minor', m2_minor,
        'm3_minor', m3_minor,
        'expected_minor', expected_minor,
        'confirmed_received_minor', confirmed_received_minor,
        'project_created_at', project_created_at,
        'milestones', milestones
      ) order by project_created_at desc, project_id desc)
      from portfolio_rows
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_website_finance_portfolio_v1()
from public, anon, authenticated, service_role;

grant execute on function public.get_website_finance_portfolio_v1()
to authenticated;

comment on function public.get_website_finance_portfolio_v1() is
  'Owner-only Website finance portfolio. Keeps commitment, expected, confirmed-received, internal evidence and unavailable bank actuals semantically separate.';