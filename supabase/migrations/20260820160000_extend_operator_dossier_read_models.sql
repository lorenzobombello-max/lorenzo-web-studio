create or replace function public.get_operator_application_v1(
  p_quote_request_id uuid default null,
  p_application_reference text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_result jsonb;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status = 'DISABLED' then raise exception using errcode = '42501', message = 'OPERATOR_DISABLED'; end if;
  if v_operator.status = 'REVOKED' then raise exception using errcode = '42501', message = 'OPERATOR_REVOKED'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;
  if v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'APPLICATION_SCOPE_DENIED';
  end if;
  if (p_quote_request_id is null) = (p_application_reference is null) then
    raise exception using errcode = '22023', message = 'EXACTLY_ONE_APPLICATION_LOCATOR_REQUIRED';
  end if;
  if p_application_reference is not null
     and p_application_reference !~ '^LWS-AAN-[0-9]{4}-[0-9]{4}$' then
    raise exception using errcode = '22023', message = 'INVALID_APPLICATION_REFERENCE';
  end if;

  select jsonb_build_object(
    'quote_request_id', qr.id,
    'application_reference', qr.application_reference,
    'name', qr.name,
    'company', qr.company,
    'email', qr.email,
    'phone', qr.phone,
    'website_type', qr.website_type,
    'budget', qr.budget,
    'timing', qr.timing,
    'description', qr.description,
    'intake_status', intake.status,
    'submitted_at', intake.submitted_at,
    'pricing', case when pricing.id is null then null else jsonb_build_object(
      'snapshot_id', pricing.id,
      'snapshot_contract_version', pricing.snapshot_contract_version,
      'selected_package', intake.selected_package_definition_id,
      'known_minimum_minor', (pricing.calculation->>'knownMinimumMinor')::bigint,
      'currency', pricing.calculation->>'currency',
      'recurring_services', coalesce(pricing.recurring_services, '[]'::jsonb),
      'budget_guard_status', pricing.budget_evaluation->>'status',
      'budget_guard_outside_wishes', pricing.budget_evaluation->'outsideBudgetWishes',
      'budget_guard_provenance', pricing.budget_evaluation->>'evidenceProvenance'
    ) end,
    'quotation', case when quotation.approval_id is null then null else jsonb_build_object(
      'approval_id', quotation.approval_id,
      'approval_version', quotation.approval_version,
      'approved_at', quotation.approved_at,
      'approved_total_minor', (quotation.approved_payload->'totals'->>'one_time_subtotal_minor')::bigint,
      'recurring_total_minor', (quotation.approved_payload->'totals'->>'recurring_subtotal_minor')::bigint,
      'quotation_number', quotation.quotation_number,
      'quotation_version', quotation.quotation_version,
      'issuance_status', quotation.issuance_status,
      'issued_at', quotation.issued_at,
      'template_id', quotation.template_id,
      'template_version', quotation.template_version,
      'docx_sha256', rtrim(quotation.docx_sha256),
      'docx_bytes', quotation.docx_bytes,
      'pdf_sha256', rtrim(quotation.pdf_sha256),
      'pdf_bytes', quotation.pdf_bytes,
      'binary_archive_available', false,
      'acceptance_id', quotation.acceptance_id,
      'acceptance_payload_sha256', rtrim(quotation.acceptance_payload_sha256),
      'accepted_at', quotation.accepted_at
    ) end,
    'acceptance', case when quotation.acceptance_id is null then null else jsonb_build_object(
      'acceptance_id', quotation.acceptance_id,
      'quotation_number', quotation.quotation_number,
      'quotation_version', quotation.quotation_version,
      'customer_legal_name', quotation.customer_legal_name,
      'accepted_at', quotation.accepted_at
    ) end,
    'project', case when project.project_id is null then null else jsonb_build_object(
      'project_id', project.project_id,
      'current_state', project.current_state,
      'revision', project.revision,
      'accepted_total_minor', project.accepted_total_minor,
      'm1_minor', project.m1_minor,
      'm2_minor', project.m2_minor,
      'm3_minor', project.m3_minor,
      'created_at', project.created_at
    ) end
  ) into v_result
  from public.quote_requests as qr
  join public.quote_request_intakes as intake on intake.quote_request_id = qr.id
  left join public.quote_request_pricing_snapshots as pricing on pricing.intake_id = intake.id
  left join lateral (
    select
      approval.id as approval_id,
      approval.approval_version,
      approval.approved_at,
      approval.approved_payload,
      issuance.id as issuance_id,
      issuance.quotation_number,
      issuance.quotation_version,
      issuance.status as issuance_status,
      issuance.issued_at,
      issuance.template_id,
      issuance.template_version,
      issuance.docx_sha256,
      issuance.docx_bytes,
      issuance.pdf_sha256,
      issuance.pdf_bytes,
      accepted.id as acceptance_id,
      accepted.customer_legal_name,
      accepted.acceptance_payload_sha256,
      accepted.accepted_at
    from public.quote_request_quotation_approvals as approval
    left join public.quote_request_quotation_issuances as issuance on issuance.approval_id = approval.id
    left join public.quote_request_quotation_acceptances as accepted on accepted.issuance_id = issuance.id
    where approval.quote_request_id = qr.id
    order by approval.approved_at desc
    limit 1
  ) as quotation on true
  left join public.commercial_projects as project on project.acceptance_id = quotation.acceptance_id
  where intake.status in ('submitted', 'reviewed')
    and (p_quote_request_id is null or qr.id = p_quote_request_id)
    and (p_application_reference is null or qr.application_reference = p_application_reference);

  if v_result is null then
    raise exception using errcode = 'P0001', message = 'APPLICATION_NOT_FOUND';
  end if;
  return v_result;
end;
$$;

create or replace function public.get_commercial_project_view_v2(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_auth record;
  v_project public.commercial_projects%rowtype;
begin
  select * into strict v_auth
  from public.resolve_commercial_operator_authorization_v1(p_project_id, 'READ_PROJECT', false);
  select * into strict v_project
  from public.commercial_projects
  where project_id = p_project_id;

  return jsonb_build_object(
    'project_id', v_project.project_id,
    'customer_id', v_project.customer_id,
    'acceptance_id', v_project.acceptance_id,
    'quotation_issuance_id', v_project.quotation_issuance_id,
    'current_state', v_project.current_state,
    'revision', v_project.revision,
    'currency', v_project.currency,
    'accepted_total_minor', v_project.accepted_total_minor,
    'm1_minor', v_project.m1_minor,
    'm2_minor', v_project.m2_minor,
    'm3_minor', v_project.m3_minor,
    'created_at', v_project.created_at,
    'updated_at', v_project.updated_at,
    'obligations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'obligation_id', obligation.obligation_id,
        'obligation_type', obligation.obligation_type,
        'milestone', obligation.milestone,
        'amount_minor', obligation.amount_minor,
        'expected_reference', obligation.expected_reference,
        'status', obligation.status,
        'created_at', obligation.created_at,
        'expected_amount_minor', expectation.expected_amount_minor,
        'evidence_count', (
          select count(*) from public.payment_evidence as evidence
          where evidence.obligation_id = obligation.obligation_id
        ),
        'reconciled_evidence_count', (
          select count(*)
          from public.payment_reconciliations as reconciliation
          join public.payment_evidence as evidence
            on evidence.payment_evidence_id = reconciliation.payment_evidence_id
          where evidence.obligation_id = obligation.obligation_id
        ),
        'latest_reconciliation_status', (
          select reconciliation.match_status
          from public.payment_reconciliations as reconciliation
          join public.payment_evidence as evidence
            on evidence.payment_evidence_id = reconciliation.payment_evidence_id
          where evidence.obligation_id = obligation.obligation_id
          order by reconciliation.decided_at desc
          limit 1
        )
      ) order by obligation.milestone nulls last, obligation.created_at)
      from public.commercial_obligations as obligation
      left join public.payment_expectations as expectation on expectation.obligation_id = obligation.obligation_id
      where obligation.project_id = p_project_id
    ), '[]'::jsonb),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'commercial_document_id', document.commercial_document_id,
        'document_type', document.document_type,
        'workflow_state', document.workflow_state,
        'template_id', document.template_id,
        'template_version', document.template_version,
        'commercial_reference', document.commercial_reference,
        'status', document.status,
        'created_at', document.created_at,
        'binary_archive_available', false
      ) order by document.created_at desc)
      from public.commercial_documents as document
      where document.project_id = p_project_id
    ), '[]'::jsonb),
    'recurring_services', coalesce((
      select jsonb_agg(jsonb_build_object(
        'recurring_service_id', service.recurring_service_id,
        'service_type', service.service_type,
        'schedule', service.schedule,
        'status', service.status,
        'created_at', service.created_at
      ) order by service.created_at)
      from public.recurring_services as service
      where service.project_id = p_project_id
    ), '[]'::jsonb),
    'timeline', coalesce((
      select jsonb_agg(to_jsonb(event_row) order by event_row.occurred_at desc, event_row.event_id desc)
      from (
        select
          'workflow:' || workflow.workflow_event_id::text as event_id,
          workflow.occurred_at,
          'STATE_TRANSITION'::text as action,
          null::text as actor,
          workflow.previous_state,
          workflow.new_state,
          workflow.command_id,
          null::text as evidence_reference
        from public.workflow_events as workflow
        where workflow.project_id = p_project_id
        union all
        select
          'audit:' || audit.audit_event_id::text,
          audit.occurred_at,
          audit.event_type,
          audit.actor,
          null::text,
          null::text,
          audit.command_id,
          audit.evidence_reference
        from public.audit_events as audit
        where audit.project_id = p_project_id
        order by occurred_at desc, event_id desc
        limit 40
      ) as event_row
    ), '[]'::jsonb)
  );
end;
$$;

comment on function public.get_operator_application_v1(uuid, text) is
  'Owner/admin-only application dossier with authoritative pricing, quotation, acceptance and project linkage. Locators never authorize access.';
comment on function public.get_commercial_project_view_v2(uuid) is
  'Server-authorized project dossier read model. Owner/admin are global; scoped operators require an active project grant.';