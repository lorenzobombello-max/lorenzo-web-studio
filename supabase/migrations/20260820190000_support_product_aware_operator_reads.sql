create or replace function public.list_operator_applications_v1(
  p_limit integer default 100,
  p_offset integer default 0
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
  if p_limit is null or p_limit < 1 or p_limit > 200 or p_offset is null or p_offset < 0 then
    raise exception using errcode = '22023', message = 'INVALID_PAGINATION';
  end if;

  return coalesce((
    select jsonb_agg(
      to_jsonb(application_row)
      order by application_row.submitted_at desc, application_row.quote_request_id
    )
    from (
      select
        qr.id as quote_request_id,
        qr.application_reference,
        qr.request_kind,
        qr.name,
        qr.company,
        qr.email,
        qr.website_type,
        qr.budget,
        qr.timing,
        case when qr.request_kind = 'website' then intake.status::text else null end as intake_status,
        case when qr.request_kind = 'website' then intake.submitted_at else qr.created_at end as submitted_at,
        acceptance.id as acceptance_id,
        acceptance.quotation_number,
        acceptance.accepted_at,
        project.project_id,
        project.current_state as project_state,
        project.revision as project_revision
      from public.quote_requests as qr
      left join public.quote_request_intakes as intake
        on intake.quote_request_id = qr.id
       and qr.request_kind = 'website'
      left join lateral (
        select accepted.id, accepted.quotation_number, accepted.accepted_at
        from public.quote_request_quotation_approvals as approval
        join public.quote_request_quotation_issuances as issuance on issuance.approval_id = approval.id
        join public.quote_request_quotation_acceptances as accepted on accepted.issuance_id = issuance.id
        where qr.request_kind = 'website'
          and approval.quote_request_id = qr.id
        order by accepted.accepted_at desc
        limit 1
      ) as acceptance on true
      left join public.commercial_projects as project on project.acceptance_id = acceptance.id
      where (qr.request_kind = 'website' and intake.status in ('submitted', 'reviewed'))
         or qr.request_kind = 'slimme_documentenflow'
      order by submitted_at desc, qr.id
      limit p_limit offset p_offset
    ) as application_row
  ), '[]'::jsonb);
end;
$$;

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
    'request_kind', qr.request_kind,
    'name', qr.name,
    'company', qr.company,
    'email', qr.email,
    'phone', qr.phone,
    'website_type', qr.website_type,
    'budget', qr.budget,
    'timing', qr.timing,
    'description', qr.description,
    'intake_status', case when qr.request_kind = 'website' then intake.status else null end,
    'submitted_at', case when qr.request_kind = 'website' then intake.submitted_at else qr.created_at end,
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
  left join public.quote_request_intakes as intake
    on intake.quote_request_id = qr.id
   and qr.request_kind = 'website'
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
    where qr.request_kind = 'website'
      and approval.quote_request_id = qr.id
    order by approval.approved_at desc
    limit 1
  ) as quotation on true
  left join public.commercial_projects as project on project.acceptance_id = quotation.acceptance_id
  where ((qr.request_kind = 'website' and intake.status in ('submitted', 'reviewed'))
      or qr.request_kind = 'slimme_documentenflow')
    and (p_quote_request_id is null or qr.id = p_quote_request_id)
    and (p_application_reference is null or qr.application_reference = p_application_reference);

  if v_result is null then
    raise exception using errcode = 'P0001', message = 'APPLICATION_NOT_FOUND';
  end if;
  return v_result;
end;
$$;

comment on function public.list_operator_applications_v1(integer, integer) is
  'Owner/admin-only product-aware application list. Website rows retain submitted intake semantics; Documentenflow rows project directly from quote requests.';
comment on function public.get_operator_application_v1(uuid, text) is
  'Owner/admin-only product-aware dossier. Website evidence remains intake-backed; Documentenflow exposes shared quote-request fields without Website artifacts.';