create table lws_internal.sdf_generic_acceptance_bridges (
  acceptance_id uuid primary key
    references public.quote_request_quotation_acceptances(id) on delete restrict,
  quotation_id uuid not null unique
    references public.sdf_quotation_acceptances(quotation_id) on delete restrict,
  issuance_id uuid not null unique
    references public.quote_request_quotation_issuances(id) on delete restrict,
  approval_id uuid not null
    references public.quote_request_quotation_approvals(id) on delete restrict,
  business_draft_id uuid not null
    references public.quote_request_quotation_business_drafts(business_draft_id) on delete restrict,
  artifact_id uuid not null
    references public.quote_request_quotation_artifacts(artifact_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

create function lws_internal.guard_sdf_generic_acceptance_bridge_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'SDF_GENERIC_ACCEPTANCE_BRIDGE_IMMUTABLE';
end;
$$;

create trigger trg_sdf_generic_acceptance_bridges_immutable
before update or delete on lws_internal.sdf_generic_acceptance_bridges
for each row execute function lws_internal.guard_sdf_generic_acceptance_bridge_v1();

alter table lws_internal.sdf_generic_acceptance_bridges enable row level security;
alter table lws_internal.sdf_generic_acceptance_bridges force row level security;

revoke all privileges on table lws_internal.sdf_generic_acceptance_bridges
from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_sdf_generic_acceptance_bridge_v1()
from public, anon, authenticated, service_role;

create function lws_internal.project_generic_acceptance_to_sdf_v1(
  p_acceptance_id uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_acceptance public.quote_request_quotation_acceptances%rowtype;
  v_issuance public.quote_request_quotation_issuances%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_request public.quote_requests%rowtype;
  v_promotion public.quote_request_quotation_business_approval_promotions%rowtype;
  v_promotion_operation public.quote_request_quotation_business_approval_promotion_operations%rowtype;
  v_business public.quote_request_quotation_business_drafts%rowtype;
  v_adapter public.sdf_quotation_business_draft_adapters%rowtype;
  v_preparation public.sdf_quotation_preparation_authorities%rowtype;
  v_decision public.sdf_quotation_commercial_decisions%rowtype;
  v_quotation public.sdf_quotations%rowtype;
  v_artifact public.quote_request_quotation_artifacts%rowtype;
  v_document public.sdf_quotation_documents%rowtype;
  v_sdf_acceptance public.sdf_quotation_acceptances%rowtype;
  v_bridge lws_internal.sdf_generic_acceptance_bridges%rowtype;
  v_terms public.sdf_accepted_commercial_terms%rowtype;
  v_obligation public.sdf_milestone_one_obligations%rowtype;
  v_pricing jsonb;
  v_implementation_amount bigint;
  v_document_reference text;
  v_creation_key uuid;
  v_creation_fingerprint text;
begin
  if p_acceptance_id is null then
    raise exception using errcode = '22023', message = 'SDF_ACCEPTANCE_BRIDGE_INPUT_INVALID';
  end if;

  select * into v_acceptance
  from public.quote_request_quotation_acceptances
  where id = p_acceptance_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'ACCEPTANCE_NOT_FOUND';
  end if;

  select * into strict v_issuance
  from public.quote_request_quotation_issuances
  where id = v_acceptance.issuance_id;
  select * into strict v_approval
  from public.quote_request_quotation_approvals
  where id = v_issuance.approval_id;
  select * into strict v_request
  from public.quote_requests
  where id = v_approval.quote_request_id;

  if v_request.request_kind <> 'slimme_documentenflow' then
    return false;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_acceptance_id::text, 0)
  );

  select * into v_promotion
  from public.quote_request_quotation_business_approval_promotions
  where approval_id = v_approval.id;
  if not found then
    raise exception using errcode = '42501', message = 'SDF_ACCEPTANCE_LINEAGE_INVALID';
  end if;
  select * into strict v_promotion_operation
  from public.quote_request_quotation_business_approval_promotion_operations
  where approval_id = v_approval.id;
  select * into strict v_business
  from public.quote_request_quotation_business_drafts
  where business_draft_id = v_promotion.business_draft_id;
  select * into strict v_adapter
  from public.sdf_quotation_business_draft_adapters
  where business_draft_id = v_business.business_draft_id;
  select * into strict v_preparation
  from public.sdf_quotation_preparation_authorities
  where authority_id = v_adapter.preparation_authority_id;
  select * into strict v_decision
  from public.sdf_quotation_commercial_decisions
  where decision_id = v_adapter.commercial_decision_id;
  select * into strict v_quotation
  from public.sdf_quotations
  where quotation_id = v_preparation.quotation_id;
  select * into v_artifact
  from public.quote_request_quotation_artifacts
  where issuance_id = v_issuance.id and artifact_type = 'DOCX';
  if not found then
    raise exception using errcode = '42501', message = 'SDF_ACCEPTANCE_LINEAGE_INVALID';
  end if;

  if v_issuance.approval_id is distinct from v_approval.id
     or v_acceptance.issuance_id is distinct from v_issuance.id
     or v_acceptance.quotation_number is distinct from v_issuance.quotation_number
     or v_acceptance.quotation_version is distinct from v_issuance.quotation_version
     or rtrim(v_acceptance.docx_sha256) is distinct from rtrim(v_issuance.docx_sha256)
     or v_acceptance.docx_bytes is distinct from v_issuance.docx_bytes
    or v_promotion_operation.business_draft_id is distinct from v_promotion.business_draft_id
    or v_promotion_operation.operation_type <> 'PROMOTE_BUSINESS_DRAFT'
     or v_business.quote_request_id is distinct from v_request.id
     or v_business.intake_id is distinct from v_approval.intake_id
     or v_adapter.quote_request_id is distinct from v_request.id
     or v_adapter.generic_intake_id is distinct from v_approval.intake_id
     or v_adapter.business_draft_id is distinct from v_business.business_draft_id
     or v_preparation.quote_request_id is distinct from v_request.id
     or v_decision.quote_request_id is distinct from v_request.id
     or v_decision.preparation_authority_id is distinct from v_preparation.authority_id
     or v_decision.quotation_id is distinct from v_quotation.quotation_id
     or v_decision.sdf_package is distinct from v_request.sdf_package
     or v_quotation.quote_request_id is distinct from v_request.id
     or v_artifact.issuance_id is distinct from v_issuance.id
     or rtrim(v_artifact.sha256) is distinct from rtrim(v_acceptance.docx_sha256)
     or v_artifact.byte_count is distinct from v_acceptance.docx_bytes
     or v_artifact.storage_bucket_id <> 'quotation-artifacts'
     or v_artifact.content_type <>
       'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
     or v_approval.approved_by is distinct from
       'OPERATOR:' || v_promotion_operation.operator_id::text then
    raise exception using errcode = '42501', message = 'SDF_ACCEPTANCE_LINEAGE_INVALID';
  end if;

  v_document_reference := v_artifact.storage_object_path;
  select * into v_document
  from public.sdf_quotation_documents
  where quotation_id = v_quotation.quotation_id;
  if found then
    if v_document.quotation_date is distinct from
         (v_approval.approved_payload->'validity'->>'valid_from')::date
       or v_document.valid_until is distinct from
         (v_approval.approved_payload->'validity'->>'valid_until')::date
       or v_document.prepared_at is distinct from v_issuance.issued_at
       or v_document.document_reference is distinct from v_document_reference
       or rtrim(v_document.document_sha256) is distinct from rtrim(v_artifact.sha256) then
      raise exception using errcode = 'P0001', message = 'SDF_QUOTATION_DOCUMENT_CONFLICT';
    end if;
  else
    insert into public.sdf_quotation_documents(
      quotation_id, quotation_date, valid_until, prepared_at,
      document_reference, document_sha256
    ) values (
      v_quotation.quotation_id,
      (v_approval.approved_payload->'validity'->>'valid_from')::date,
      (v_approval.approved_payload->'validity'->>'valid_until')::date,
      v_issuance.issued_at, v_document_reference, rtrim(v_artifact.sha256)
    );
  end if;

  select * into v_sdf_acceptance
  from public.sdf_quotation_acceptances
  where quotation_id = v_quotation.quotation_id;
  if found then
    if v_sdf_acceptance.accepted_at is distinct from v_acceptance.accepted_at
       or v_sdf_acceptance.document_reference is distinct from v_document_reference
       or rtrim(v_sdf_acceptance.document_sha256) is distinct from
         rtrim(v_acceptance.docx_sha256) then
      raise exception using errcode = 'P0001', message = 'SDF_QUOTATION_ACCEPTANCE_CONFLICT';
    end if;
  else
    insert into public.sdf_quotation_acceptances(
      quotation_id, accepted_at, document_reference, document_sha256
    ) values (
      v_quotation.quotation_id, v_acceptance.accepted_at,
      v_document_reference, rtrim(v_acceptance.docx_sha256)
    );
  end if;

  select * into v_bridge
  from lws_internal.sdf_generic_acceptance_bridges
  where acceptance_id = v_acceptance.id
     or quotation_id = v_quotation.quotation_id
     or issuance_id = v_issuance.id;
  if found then
    if v_bridge.acceptance_id is distinct from v_acceptance.id
       or v_bridge.quotation_id is distinct from v_quotation.quotation_id
       or v_bridge.issuance_id is distinct from v_issuance.id
       or v_bridge.approval_id is distinct from v_approval.id
       or v_bridge.business_draft_id is distinct from v_business.business_draft_id
       or v_bridge.artifact_id is distinct from v_artifact.artifact_id then
      raise exception using errcode = 'P0001', message = 'SDF_ACCEPTANCE_BRIDGE_CONFLICT';
    end if;
  else
    insert into lws_internal.sdf_generic_acceptance_bridges(
      acceptance_id, quotation_id, issuance_id, approval_id,
      business_draft_id, artifact_id
    ) values (
      v_acceptance.id, v_quotation.quotation_id, v_issuance.id, v_approval.id,
      v_business.business_draft_id, v_artifact.artifact_id
    );
  end if;

  v_implementation_amount :=
    (v_approval.approved_payload->'totals'->>'one_time_subtotal_minor')::bigint;
  v_pricing := public.get_sdf_package_pricing_authority_v1(v_request.sdf_package);
  v_creation_key := md5(
    'sdf-generic-acceptance-bridge:v1:' || v_acceptance.id::text
  )::uuid;
  v_creation_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'acceptedImplementationAmountMinor', v_implementation_amount,
    'quotationId', v_quotation.quotation_id
  )::text, 'UTF8'), 'sha256'), 'hex');

  select * into v_terms
  from public.sdf_accepted_commercial_terms
  where quotation_id = v_quotation.quotation_id;
  if found then
    if v_terms.quote_request_id is distinct from v_request.id
       or v_terms.sdf_package is distinct from v_request.sdf_package
       or v_terms.accepted_implementation_amount_minor is distinct from v_implementation_amount
       or v_terms.currency is distinct from v_pricing->>'currency'
       or v_terms.vat_basis is distinct from v_pricing->>'vat_basis'
       or v_terms.pricing_authority_version is distinct from
         (v_pricing->>'authority_version')::smallint
       or rtrim(v_terms.creation_fingerprint) is distinct from v_creation_fingerprint then
      raise exception using errcode = 'P0001', message = 'SDF_ACCEPTED_TERMS_CONFLICT';
    end if;
  else
    insert into public.sdf_accepted_commercial_terms(
      quotation_id, quote_request_id, sdf_package,
      accepted_implementation_amount_minor, currency, vat_basis,
      pricing_authority_version, creation_idempotency_key,
      creation_fingerprint, created_by_operator_id
    ) values (
      v_quotation.quotation_id, v_request.id, v_request.sdf_package,
      v_implementation_amount, v_pricing->>'currency', v_pricing->>'vat_basis',
      (v_pricing->>'authority_version')::smallint, v_creation_key,
      v_creation_fingerprint, v_promotion_operation.operator_id
    ) returning * into v_terms;
  end if;

  select * into v_obligation
  from public.sdf_milestone_one_obligations
  where quotation_id = v_quotation.quotation_id;
  if found then
    if v_obligation.accepted_terms_id is distinct from v_terms.accepted_terms_id
       or v_obligation.milestone_identity <> 'M1'
       or v_obligation.percentage_basis_points <> 4000
       or v_obligation.amount_minor is distinct from
         ((v_implementation_amount::numeric * 4000) / 10000)::bigint
       or v_obligation.currency is distinct from v_terms.currency
       or v_obligation.vat_basis is distinct from v_terms.vat_basis
       or v_obligation.obligation_state <> 'EXPECTED'
       or v_obligation.obligation_origin <> 'QUOTATION_ACCEPTANCE' then
      raise exception using errcode = 'P0001', message = 'SDF_MILESTONE_ONE_CONFLICT';
    end if;
  else
    insert into public.sdf_milestone_one_obligations(
      quotation_id, accepted_terms_id, milestone_identity,
      percentage_basis_points, amount_minor, currency, vat_basis,
      obligation_state, obligation_origin
    ) values (
      v_quotation.quotation_id, v_terms.accepted_terms_id, 'M1', 4000,
      ((v_implementation_amount::numeric * 4000) / 10000)::bigint,
      v_terms.currency, v_terms.vat_basis, 'EXPECTED', 'QUOTATION_ACCEPTANCE'
    );
  end if;

  return true;
exception
  when no_data_found or too_many_rows then
    raise exception using errcode = '42501', message = 'SDF_ACCEPTANCE_LINEAGE_INVALID';
end;
$$;

revoke all on function lws_internal.project_generic_acceptance_to_sdf_v1(uuid)
from public, anon, authenticated, service_role;

create or replace function public.submit_quotation_acceptance_capability_v1(
  p_token_digest text,
  p_expected_terms_id text,
  p_expected_terms_version text,
  p_accepting_name text,
  p_accepting_email text,
  p_accepting_organization text,
  p_accepting_role text,
  p_authority_declaration boolean,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_c public.quote_request_quotation_acceptance_capabilities%rowtype;
  v_i public.quote_request_quotation_issuances%rowtype;
  v_a public.quote_request_quotation_approvals%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_result record;
  v_fp text;
begin
  if p_token_digest !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('state', 'INVALID_OR_EXPIRED_LINK');
  end if;
  v_fp := encode(extensions.digest(convert_to(jsonb_build_object(
    'termsId', p_expected_terms_id,
    'termsVersion', p_expected_terms_version,
    'name', btrim(p_accepting_name),
    'email', lower(btrim(p_accepting_email)),
    'organization', nullif(btrim(p_accepting_organization), ''),
    'role', nullif(btrim(p_accepting_role), ''),
    'declaration', p_authority_declaration
  )::text, 'UTF8'), 'sha256'), 'hex');
  select * into v_c
  from public.quote_request_quotation_acceptance_capabilities
  where token_digest = p_token_digest
  for update;
  if not found then
    return jsonb_build_object('state', 'INVALID_OR_EXPIRED_LINK');
  end if;
  if v_c.status = 'CONSUMED' then
    if v_c.consumed_request_fingerprint <> v_fp then
      return jsonb_build_object('state', 'VALIDATION_FAILED');
    end if;
    perform lws_internal.project_generic_acceptance_to_sdf_v1(v_c.acceptance_id);
    return jsonb_build_object(
      'state', 'ACCEPTED',
      'acceptance_id', v_c.acceptance_id,
      'was_created', false
    );
  end if;
  if v_c.status <> 'ACTIVE' or clock_timestamp() >= v_c.expires_at then
    return jsonb_build_object('state', 'INVALID_OR_EXPIRED_LINK');
  end if;
  select * into strict v_i
  from public.quote_request_quotation_issuances
  where id = v_c.issuance_id
  for update;
  select * into strict v_a
  from public.quote_request_quotation_approvals
  where id = v_i.approval_id;
  select * into strict v_intake
  from public.quote_request_intakes
  where id = v_a.intake_id;
  select * into v_result
  from public.accept_quotation_v1(
    v_i.id, v_i.quotation_version,
    v_a.approved_payload->'customer_identity'->>'snapshot_sha256',
    p_expected_terms_id, p_expected_terms_version, p_accepting_name,
    p_accepting_email, p_accepting_organization, p_accepting_role,
    p_authority_declaration, p_idempotency_key,
    v_intake.admin_access_token_hash
  );
  perform lws_internal.project_generic_acceptance_to_sdf_v1(v_result.acceptance_id);
  perform set_config('lws.acceptance_capability_transition', 'CONSUME', true);
  update public.quote_request_quotation_acceptance_capabilities
  set status = 'CONSUMED', acceptance_id = v_result.acceptance_id,
      consumed_request_fingerprint = v_fp, consumed_at = clock_timestamp()
  where id = v_c.id
  returning * into v_c;
  perform set_config('lws.acceptance_capability_transition', '', true);
  insert into public.quote_request_quotation_acceptance_capability_events(
    capability_id, issuance_id, event_type, actor, event_at, evidence
  ) values (
    v_c.id, v_c.issuance_id, 'CONSUMED', 'public-orchestration',
    v_c.consumed_at, jsonb_build_object('acceptanceId', v_result.acceptance_id)
  );
  return jsonb_build_object(
    'state', 'ACCEPTED',
    'acceptance_id', v_result.acceptance_id,
    'quotation_number', v_result.quotation_number,
    'was_created', v_result.was_created
  );
exception
  when others then
    if sqlstate in ('22023', '42501', 'P0001') then
      return jsonb_build_object('state', 'VALIDATION_FAILED');
    end if;
    raise;
end;
$$;

revoke all on function public.submit_quotation_acceptance_capability_v1(
  text, text, text, text, text, text, text, boolean, uuid
) from public, anon, authenticated;
grant execute on function public.submit_quotation_acceptance_capability_v1(
  text, text, text, text, text, text, text, boolean, uuid
) to service_role;

comment on table lws_internal.sdf_generic_acceptance_bridges is
  'Private immutable binding from one generic quotation acceptance to the exact frozen SDF quotation, issuance, approval, business draft, and DOCX artifact authority.';
comment on function lws_internal.project_generic_acceptance_to_sdf_v1(uuid) is
  'Private idempotent projector that validates frozen SDF lineage and atomically creates quotation document evidence, acceptance evidence, accepted commercial terms, and one EXPECTED M1 obligation.';
comment on function public.submit_quotation_acceptance_capability_v1(
  text, text, text, text, text, text, text, boolean, uuid
) is
  'Service-role orchestration. Capability acceptance, bounded SDF evidence projection, CONSUMED transition and event append execute in one PostgreSQL transaction; replay repairs missing SDF projection and explicitly returns was_created false.';