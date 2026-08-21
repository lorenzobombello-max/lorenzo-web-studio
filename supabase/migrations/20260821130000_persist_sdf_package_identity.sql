alter table public.quote_requests
  add column sdf_package text;

alter table public.quote_requests
  add constraint quote_requests_sdf_package_shape_check
    check (
      (request_kind = 'website' and sdf_package is null)
      or (
        request_kind = 'slimme_documentenflow'
        and (sdf_package is null or sdf_package in ('start', 'groei', 'maatwerk'))
      )
    ) not valid;

alter table public.quote_requests
  validate constraint quote_requests_sdf_package_shape_check;

comment on column public.quote_requests.sdf_package is
  'Canonical Slimme Documentenflow package identity: start, groei or maatwerk. Null is retained only for historical dossiers and Website requests.';

drop function public.create_quote_request_idempotent(
  uuid, text, text, text, text, text, text, text, text, text, timestamptz,
  text, text, text, text, text, text, text, text, text, text, text, boolean,
  text, timestamptz, text, text
);

create function public.create_quote_request_idempotent(
  p_idempotency_key uuid,
  p_request_fingerprint text,
  p_request_kind text,
  p_sdf_package text,
  p_name text,
  p_customer_type text,
  p_company text,
  p_enterprise_number text,
  p_enterprise_validation_status text,
  p_vat_number text,
  p_vat_validation_status text,
  p_vat_validated_at timestamptz,
  p_billing_address text,
  p_billing_postal_code text,
  p_billing_city text,
  p_billing_country text,
  p_billing_email text,
  p_email text,
  p_phone text,
  p_website_type text,
  p_budget text,
  p_timing text,
  p_description text,
  p_privacy_consent boolean,
  p_approval_token_hash text,
  p_approval_token_expires_at timestamptz,
  p_client_ip_hash text,
  p_user_agent text
)
returns table (
  request_id uuid,
  request_created_at timestamptz,
  was_created boolean,
  admin_job_id uuid,
  admin_job_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.quote_requests%rowtype;
  v_job public.quote_request_email_jobs%rowtype;
  v_was_created boolean := false;
begin
  if p_request_kind is null or p_request_kind not in ('website', 'slimme_documentenflow') then
    raise exception using errcode = '22023', message = 'INVALID_REQUEST_KIND';
  end if;
  if p_request_kind = 'website'
     and (p_sdf_package is not null or p_website_type is null or p_budget is null or p_timing is null) then
    raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REQUEST_SHAPE';
  end if;
  if p_request_kind = 'slimme_documentenflow'
     and (
       p_sdf_package is null
       or p_sdf_package not in ('start', 'groei', 'maatwerk')
       or p_website_type is not null
       or p_budget is not null
       or p_timing is not null
     ) then
    raise exception using errcode = '22023', message = 'INVALID_DOCUMENTENFLOW_REQUEST_SHAPE';
  end if;

  insert into public.quote_requests (
    idempotency_key, request_fingerprint, request_kind, sdf_package, name, customer_type, company,
    enterprise_number, enterprise_validation_status, vat_number, vat_validation_status, vat_validated_at,
    billing_address, billing_postal_code, billing_city, billing_country, billing_email,
    email, phone, website_type, budget, timing, description, privacy_consent, status,
    approval_token_hash, approval_token_expires_at, client_ip_hash, user_agent
  ) values (
    p_idempotency_key, p_request_fingerprint, p_request_kind, p_sdf_package, p_name, p_customer_type, p_company,
    p_enterprise_number, p_enterprise_validation_status, p_vat_number, p_vat_validation_status, p_vat_validated_at,
    p_billing_address, p_billing_postal_code, p_billing_city, p_billing_country, p_billing_email,
    p_email, p_phone, p_website_type, p_budget, p_timing, p_description, p_privacy_consent, 'pending',
    p_approval_token_hash, p_approval_token_expires_at, p_client_ip_hash, p_user_agent
  )
  on conflict (idempotency_key) where idempotency_key is not null do nothing
  returning * into v_request;

  v_was_created := found;

  if not v_was_created then
    select * into v_request
    from public.quote_requests
    where idempotency_key = p_idempotency_key;

    if not found then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_LOOKUP_FAILED';
    end if;

    if v_request.request_fingerprint is distinct from p_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
  end if;

  insert into public.quote_request_email_jobs (quote_request_id, kind)
  values (v_request.id, 'admin_notification')
  on conflict (quote_request_id, kind) do nothing;

  select * into v_job
  from public.quote_request_email_jobs
  where quote_request_id = v_request.id
    and kind = 'admin_notification';

  return query
  select v_request.id, v_request.created_at, v_was_created, v_job.id, v_job.status::text;
end;
$$;

revoke all
on function public.create_quote_request_idempotent(
  uuid, text, text, text, text, text, text, text, text, text, text, timestamptz,
  text, text, text, text, text, text, text, text, text, text, text, boolean,
  text, timestamptz, text, text
)
from public, anon, authenticated;

grant execute
on function public.create_quote_request_idempotent(
  uuid, text, text, text, text, text, text, text, text, text, text, timestamptz,
  text, text, text, text, text, text, text, text, text, text, text, boolean,
  text, timestamptz, text, text
)
to service_role;

comment on function public.create_quote_request_idempotent(
  uuid, text, text, text, text, text, text, text, text, text, text, timestamptz,
  text, text, text, text, text, text, text, text, text, text, text, boolean,
  text, timestamptz, text, text
) is 'Product-aware idempotent commercial request storage. New Documentenflow requests require canonical package identity; Website requests reject it.';

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
    'sdf_package', qr.sdf_package,
    'name', qr.name,
    'customer_type', qr.customer_type,
    'company', qr.company,
    'email', qr.email,
    'phone', qr.phone,
    'enterprise_number', qr.enterprise_number,
    'enterprise_validation_status', qr.enterprise_validation_status,
    'vat_number', qr.vat_number,
    'vat_validation_status', qr.vat_validation_status,
    'vat_validated_at', qr.vat_validated_at,
    'billing_address', qr.billing_address,
    'billing_postal_code', qr.billing_postal_code,
    'billing_city', qr.billing_city,
    'billing_country', qr.billing_country,
    'billing_email', qr.billing_email,
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

comment on function public.get_operator_application_v1(uuid, text) is
  'Owner/admin-only product-aware dossier with Customer Core and SDF package identity. Website evidence remains isolated and intake-backed.';