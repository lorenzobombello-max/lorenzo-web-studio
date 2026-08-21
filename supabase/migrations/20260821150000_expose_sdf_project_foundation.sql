create table public.sdf_projects (
  project_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null unique references public.quote_requests(id),
  created_at timestamptz not null default clock_timestamp()
);

comment on table public.sdf_projects is
  'Private identity-only foundation for a durable SDF project linked one-to-one to an SDF application. No workflow, pricing, recurring, quotation, payment, or document semantics.';

create function public.guard_sdf_project_foundation_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_request_kind text;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    raise exception using errcode = '55000', message = 'SDF_PROJECT_IMMUTABLE';
  end if;

  select request_kind into v_request_kind
  from public.quote_requests
  where id = new.quote_request_id;

  if not found then
    raise exception using errcode = '23503', message = 'SDF_PROJECT_APPLICATION_NOT_FOUND';
  end if;
  if v_request_kind <> 'slimme_documentenflow' then
    raise exception using errcode = '23514', message = 'SDF_PROJECT_REQUIRES_SDF_APPLICATION';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_sdf_project_foundation_v1()
from public, anon, authenticated, service_role;

create trigger trg_sdf_project_foundation_guard
before insert or update or delete on public.sdf_projects
for each row execute function public.guard_sdf_project_foundation_v1();

alter table public.sdf_projects enable row level security;
alter table public.sdf_projects force row level security;

revoke all privileges on table public.sdf_projects
from public, anon, authenticated, service_role;

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
    'sdf_pricing', case
      when qr.request_kind = 'slimme_documentenflow' and qr.sdf_package is not null
        then public.get_sdf_package_pricing_authority_v1(qr.sdf_package)
      else null
    end,
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
    'project', case
      when qr.request_kind = 'slimme_documentenflow' and sdf_project.project_id is not null
        then jsonb_build_object(
          'project_id', sdf_project.project_id,
          'request_kind', qr.request_kind,
          'quote_request_id', qr.id,
          'application_reference', qr.application_reference,
          'customer_name', qr.name,
          'sdf_package', qr.sdf_package,
          'current_state', null,
          'operational_status', null,
          'created_at', sdf_project.created_at
        )
      when qr.request_kind = 'website' and project.project_id is not null
        then jsonb_build_object(
          'project_id', project.project_id,
          'current_state', project.current_state,
          'revision', project.revision,
          'accepted_total_minor', project.accepted_total_minor,
          'm1_minor', project.m1_minor,
          'm2_minor', project.m2_minor,
          'm3_minor', project.m3_minor,
          'created_at', project.created_at
        )
      else null
    end
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
  left join public.sdf_projects as sdf_project
    on sdf_project.quote_request_id = qr.id
   and qr.request_kind = 'slimme_documentenflow'
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
  'Owner/admin-only product-aware dossier with isolated Website evidence, private SDF pricing, and identity-only SDF project authority. SDF project status and lifecycle remain unavailable.';