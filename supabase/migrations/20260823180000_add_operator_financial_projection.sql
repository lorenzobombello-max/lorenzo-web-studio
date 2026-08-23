create or replace function public.get_commercial_project_view_v2(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_project public.commercial_projects%rowtype;
  v_project_view jsonb;
  v_financial_summary jsonb;
begin
  v_project_view := public.get_commercial_project_view_v2_pre_project_site(p_project_id);

  select * into strict v_project
  from public.commercial_projects
  where project_id = p_project_id;

  with milestone_rows as (
    select
      milestone.number as milestone,
      obligation.obligation_id,
      expectation.expected_amount_minor as expected_minor,
      exists (
        select 1
        from public.payment_reconciliations as reconciliation
        join public.payment_evidence as evidence
          on evidence.payment_evidence_id = reconciliation.payment_evidence_id
        where reconciliation.project_id = p_project_id
          and reconciliation.obligation_id = obligation.obligation_id
          and reconciliation.match_status = 'MATCHED'
          and evidence.project_id = p_project_id
          and evidence.obligation_id = obligation.obligation_id
          and evidence.received_amount_minor = expectation.expected_amount_minor
      ) as has_matched_payment,
      exists (
        select 1
        from public.workflow_events as event
        where event.project_id = p_project_id
          and event.new_state = case milestone.number
            when 1 then 'M1_PAYMENT_RECEIVED'
            when 2 then 'M2_PAYMENT_RECEIVED'
            when 3 then 'FULL_PAYMENT_RECEIVED'
          end
      ) as has_payment_confirmation,
      exists (
        select 1
        from public.payment_evidence as evidence
        where evidence.project_id = p_project_id
          and evidence.obligation_id = obligation.obligation_id
      ) as has_payment_evidence,
      (
        select reconciliation.match_status
        from public.payment_reconciliations as reconciliation
        join public.payment_evidence as evidence
          on evidence.payment_evidence_id = reconciliation.payment_evidence_id
        where reconciliation.project_id = p_project_id
          and reconciliation.obligation_id = obligation.obligation_id
          and evidence.project_id = p_project_id
          and evidence.obligation_id = obligation.obligation_id
        order by reconciliation.decided_at desc, reconciliation.payment_reconciliation_id desc
        limit 1
      ) as latest_reconciliation_status
    from generate_series(1, 3) as milestone(number)
    left join public.commercial_obligations as obligation
      on obligation.project_id = p_project_id
      and obligation.obligation_type = 'PROJECT_MILESTONE'
      and obligation.milestone = milestone.number
    left join public.payment_expectations as expectation
      on expectation.project_id = p_project_id
      and expectation.obligation_id = obligation.obligation_id
  )
  select jsonb_build_object(
    'currency', v_project.currency,
    'accepted_total_minor', v_project.accepted_total_minor,
    'expected_minor', coalesce(sum(expected_minor), 0),
    'invoice_projection_available', false,
    'invoiced_minor', null,
    'received_minor', coalesce(sum(
      case when has_matched_payment and has_payment_confirmation then expected_minor else 0 end
    ), 0),
    'outstanding_projection_available', false,
    'outstanding_minor', null,
    'milestones', jsonb_agg(jsonb_build_object(
      'milestone', milestone,
      'expected_minor', expected_minor,
      'payment_status', case
        when obligation_id is null then 'NOT_PREPARED'
        when has_matched_payment and has_payment_confirmation then 'CONFIRMED'
        when has_matched_payment then 'MATCHED_AWAITING_CONFIRMATION'
        when latest_reconciliation_status is not null then latest_reconciliation_status
        when has_payment_evidence then 'EVIDENCE_RECORDED'
        else 'EXPECTED'
      end,
      'confirmed_received_minor', case
        when has_matched_payment and has_payment_confirmation then expected_minor
        else 0
      end
    ) order by milestone)
  ) into v_financial_summary
  from milestone_rows;

  return v_project_view || jsonb_build_object(
    'financial_summary', v_financial_summary,
    'site', (
      select jsonb_build_object(
        'site_id', site.site_id,
        'project_id', site.project_id,
        'site_revision', site.site_revision,
        'canonical_domain', site.canonical_domain,
        'canonical_url', site.canonical_url,
        'created_at', site.created_at
      )
      from public.commercial_project_sites as site
      where site.project_id = p_project_id
      order by site.site_revision desc
      limit 1
    )
  );
end;
$$;

comment on function public.get_commercial_project_view_v2(uuid) is
  'Server-authorized project dossier with project-site binding and fail-closed expected, confirmed-received, invoice-unavailable and outstanding-unavailable financial projection.';