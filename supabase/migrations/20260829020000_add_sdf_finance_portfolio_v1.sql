create function public.get_sdf_finance_portfolio_v1()
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
    raise exception using errcode = '42501', message = 'SDF_FINANCE_PORTFOLIO_OWNER_REQUIRED';
  end if;

  with portfolio_rows as (
    select
      request.id as quote_request_id,
      request.application_reference,
      terms.quotation_id,
      project.project_id as sdf_project_id,
      terms.sdf_package,
      terms.currency,
      terms.accepted_implementation_amount_minor as commitment_minor,
      acceptance.accepted_at,
      terms.created_at as accepted_terms_created_at,
      obligation.amount_minor as m1_obligation_minor,
      obligation.obligation_state as m1_obligation_status,
      obligation.created_at as m1_obligation_created_at,
      candidate.candidate_state,
      candidate.prepared_at,
      candidate.net_amount_minor as candidate_net_amount_minor,
      issuance.issuance_state,
      issuance.issued_at,
      issuance.invoice_number,
      issuance.net_amount_minor as issued_net_amount_minor,
      issuance.gross_amount_minor as issued_gross_amount_minor,
      issuance.vat_authority_version
    from public.sdf_accepted_commercial_terms as terms
    join public.quote_requests as request
      on request.id = terms.quote_request_id
    join public.sdf_quotation_acceptances as acceptance
      on acceptance.quotation_id = terms.quotation_id
    join public.sdf_milestone_one_obligations as obligation
      on obligation.accepted_terms_id = terms.accepted_terms_id
      and obligation.quotation_id = terms.quotation_id
    left join public.sdf_projects as project
      on project.quote_request_id = request.id
    left join public.sdf_m1_invoice_candidates as candidate
      on candidate.obligation_id = obligation.obligation_id
    left join public.sdf_m1_invoice_issuances as issuance
      on issuance.candidate_id = candidate.candidate_id
    where request.record_classification = 'production'
      and request.request_kind = 'slimme_documentenflow'
      and request.sdf_package in ('start', 'groei', 'maatwerk')
      and request.sdf_package = terms.sdf_package
  ), currency_rows as (
    select
      currency,
      sum(commitment_minor) as commitment_minor,
      sum(m1_obligation_minor) as m1_obligation_minor,
      sum(issued_gross_amount_minor) filter (where issuance_state = 'ISSUED') as issued_invoice_minor
    from portfolio_rows
    group by currency
  )
  select jsonb_build_object(
    'scope', 'sdf',
    'project_count', (select count(*) from portfolio_rows),
    'invoice_projection_available', true,
    'expected_payment_available', false,
    'payment_evidence_available', false,
    'confirmed_received_available', false,
    'outstanding_projection_available', false,
    'overdue_projection_available', false,
    'upcoming_projection_available', false,
    'recurring_amount_projection_available', false,
    'currency_totals', coalesce((
      select jsonb_agg(jsonb_build_object(
        'currency', currency,
        'commitment_minor', commitment_minor,
        'm1_obligation_minor', m1_obligation_minor,
        'issued_invoice_minor', coalesce(issued_invoice_minor, 0)
      ) order by currency)
      from currency_rows
    ), '[]'::jsonb),
    'projects', coalesce((
      select jsonb_agg(jsonb_build_object(
        'quote_request_id', quote_request_id,
        'application_reference', application_reference,
        'quotation_id', quotation_id,
        'sdf_project_id', sdf_project_id,
        'sdf_package', sdf_package,
        'currency', currency,
        'commitment_minor', commitment_minor,
        'accepted_at', accepted_at,
        'accepted_terms_created_at', accepted_terms_created_at,
        'm1_obligation_minor', m1_obligation_minor,
        'm1_obligation_status', m1_obligation_status,
        'm1_obligation_created_at', m1_obligation_created_at,
        'invoice_candidate_state', candidate_state,
        'invoice_candidate_net_amount_minor', candidate_net_amount_minor,
        'prepared_at', prepared_at,
        'invoice_issuance_state', issuance_state,
        'issued_at', issued_at,
        'invoice_number', invoice_number,
        'issued_net_amount_minor', issued_net_amount_minor,
        'issued_gross_amount_minor', issued_gross_amount_minor,
        'vat_authority_version', vat_authority_version
      ) order by accepted_terms_created_at desc, quotation_id desc)
      from portfolio_rows
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_sdf_finance_portfolio_v1()
from public, anon, authenticated, service_role;

grant execute on function public.get_sdf_finance_portfolio_v1()
to authenticated;

comment on function public.get_sdf_finance_portfolio_v1() is
  'Owner-only SDF finance portfolio. Keeps accepted commitment, M1 obligation, invoice candidate, and issued invoice semantically separate; payment and recurring projections remain unavailable.';