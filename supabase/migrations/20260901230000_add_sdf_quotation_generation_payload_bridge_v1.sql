create function lws_internal.assert_sdf_approval_issuance_authority_v1(
  p_business_draft_id uuid,
  p_approval_id uuid,
  p_expected_approval_version integer,
  p_expected_approval_sha256 text,
  p_require_current_vat boolean
)
returns text
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_adapter public.sdf_quotation_business_draft_adapters%rowtype;
  v_business public.quote_request_quotation_business_drafts%rowtype;
  v_promotion public.quote_request_quotation_business_approval_promotions%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_preparation public.sdf_quotation_preparation_authorities%rowtype;
  v_decision public.sdf_quotation_commercial_decisions%rowtype;
  v_submission public.sdf_qualification_intake_submissions%rowtype;
  v_request public.quote_requests%rowtype;
  v_snapshot public.quote_request_pricing_snapshots%rowtype;
  v_draft public.quote_request_quotation_approval_drafts%rowtype;
  v_terms public.quotation_terms_authorities%rowtype;
  v_vat_binding public.quotation_business_draft_vat_bindings%rowtype;
  v_vat_turnover public.quotation_vat_turnover_snapshots%rowtype;
  v_pricing jsonb;
  v_vat_context jsonb;
  v_submission_sha256 text;
  v_pricing_sha256 text;
  v_document_sha256 text;
  v_decision_sha256 text;
begin
  if p_business_draft_id is null
     or p_approval_id is null
     or p_expected_approval_version is null or p_expected_approval_version < 1
     or p_expected_approval_sha256 is null
     or p_expected_approval_sha256 !~ '^[0-9a-f]{64}$'
     or p_require_current_vat is null then
    raise exception using errcode = '22023', message = 'SDF_ISSUANCE_AUTHORITY_INPUT_INVALID';
  end if;

  v_operator := lws_internal.assert_sdf_owner_v1();

  select * into v_adapter
  from public.sdf_quotation_business_draft_adapters
  where business_draft_id = p_business_draft_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'SDF_BUSINESS_DRAFT_NOT_FOUND';
  end if;

  select * into strict v_business
  from public.quote_request_quotation_business_drafts
  where business_draft_id = v_adapter.business_draft_id;
  select * into strict v_promotion
  from public.quote_request_quotation_business_approval_promotions
  where business_draft_id = v_business.business_draft_id;
  select * into v_approval
  from public.quote_request_quotation_approvals
  where id = p_approval_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'APPROVAL_NOT_FOUND';
  end if;
  select * into strict v_preparation
  from public.sdf_quotation_preparation_authorities
  where authority_id = v_adapter.preparation_authority_id;
  select * into strict v_decision
  from public.sdf_quotation_commercial_decisions
  where decision_id = v_adapter.commercial_decision_id;
  select * into strict v_submission
  from public.sdf_qualification_intake_submissions
  where intake_id = v_preparation.qualification_intake_id
    and submission_sequence = v_preparation.submission_sequence;
  select * into strict v_request
  from public.quote_requests
  where id = v_adapter.quote_request_id;
  select * into strict v_snapshot
  from public.quote_request_pricing_snapshots
  where id = v_adapter.pricing_snapshot_id;
  select * into strict v_draft
  from public.quote_request_quotation_approval_drafts
  where id = v_adapter.approval_draft_id;

  if v_promotion.approval_id is distinct from v_approval.id
     or v_adapter.quote_request_id is distinct from v_business.quote_request_id
     or v_adapter.generic_intake_id is distinct from v_business.intake_id
     or v_adapter.pricing_snapshot_id is distinct from v_business.pricing_snapshot_id
     or v_adapter.approval_draft_id is distinct from v_business.approval_draft_id
     or v_preparation.quote_request_id is distinct from v_adapter.quote_request_id
     or v_decision.quote_request_id is distinct from v_adapter.quote_request_id
     or v_decision.preparation_authority_id is distinct from v_preparation.authority_id
     or v_decision.quotation_id is distinct from v_preparation.quotation_id
     or v_snapshot.intake_id is distinct from v_adapter.generic_intake_id
     or v_snapshot.snapshot_contract_version is distinct from 4
     or v_draft.quote_request_id is distinct from v_adapter.quote_request_id
     or v_draft.intake_id is distinct from v_adapter.generic_intake_id
     or v_draft.pricing_snapshot_id is distinct from v_adapter.pricing_snapshot_id
     or v_approval.draft_id is distinct from v_draft.id
     or v_approval.quote_request_id is distinct from v_business.quote_request_id
     or v_approval.intake_id is distinct from v_business.intake_id
     or v_approval.pricing_snapshot_id is distinct from v_business.pricing_snapshot_id then
    raise exception using errcode = '42501', message = 'SDF_ISSUANCE_CROSS_DOSSIER';
  end if;

  if v_approval.approval_version is distinct from p_expected_approval_version
     or rtrim(v_approval.payload_sha256) is distinct from p_expected_approval_sha256
     or exists (
       select 1 from public.quote_request_quotation_approvals newer
       where newer.intake_id = v_approval.intake_id
         and newer.approval_version > v_approval.approval_version
     ) then
    raise exception using errcode = 'P0001', message = 'SDF_APPROVAL_STALE';
  end if;

  v_submission_sha256 := encode(
    extensions.digest(convert_to(v_submission.answers::text, 'UTF8'), 'sha256'), 'hex'
  );
  v_pricing := lws_internal.get_sdf_budget_guard_pricing_authority_v2(v_decision.sdf_package);
  v_pricing_sha256 := encode(
    extensions.digest(convert_to(v_pricing::text, 'UTF8'), 'sha256'), 'hex'
  );
  v_document_sha256 := (
    lws_internal.evaluate_sdf_document_completeness_v1(v_request.id)->>'evidence_sha256'
  );
  v_decision_sha256 := encode(
    extensions.digest(convert_to(v_decision.canonical_payload::text, 'UTF8'), 'sha256'), 'hex'
  );

  if v_submission_sha256 is distinct from rtrim(v_adapter.submission_sha256)
     or v_submission_sha256 is distinct from rtrim(v_preparation.submission_sha256)
     or v_submission_sha256 is distinct from rtrim(v_decision.submission_sha256) then
    raise exception using errcode = '55000', message = 'SDF_QUALIFICATION_INTEGRITY_MISMATCH';
  end if;
  if v_pricing_sha256 is distinct from rtrim(v_adapter.pricing_authority_sha256)
     or v_pricing_sha256 is distinct from rtrim(v_preparation.pricing_authority_sha256)
     or v_pricing_sha256 is distinct from rtrim(v_decision.pricing_authority_sha256)
     or v_snapshot.config_hash is distinct from v_pricing_sha256 then
    raise exception using errcode = '55000', message = 'SDF_PRICING_AUTHORITY_MISMATCH';
  end if;
  if v_document_sha256 is distinct from rtrim(v_adapter.document_evidence_sha256)
     or v_document_sha256 is distinct from rtrim(v_preparation.document_evidence_sha256)
     or v_document_sha256 is distinct from rtrim(v_decision.document_evidence_sha256) then
    raise exception using errcode = '55000', message = 'SDF_DOCUMENT_EVIDENCE_MISMATCH';
  end if;
  if v_decision_sha256 is distinct from rtrim(v_adapter.decision_sha256)
     or v_decision_sha256 is distinct from rtrim(v_decision.decision_sha256) then
    raise exception using errcode = '55000', message = 'SDF_COMMERCIAL_DECISION_INTEGRITY_MISMATCH';
  end if;

  if rtrim(v_business.canonical_payload_sha256) is distinct from v_approval.payload_sha256
     or v_business.canonical_payload is distinct from v_approval.approved_payload
     or v_draft.contract_version <> 1
     or v_draft.approval_payload is distinct from v_approval.approved_payload
     or v_draft.payload_fingerprint is distinct from v_approval.payload_sha256
     or v_business.terms_authority_id is distinct from v_decision.terms_authority_id
     or v_business.vat_decision_authority_id is distinct from v_decision.vat_decision_authority_id
     or v_approval.approved_payload->'payment_schedule' is distinct from v_decision.payment_schedule then
    raise exception using errcode = 'P0001', message = 'SDF_APPROVAL_LINEAGE_STALE';
  end if;

  if not public.is_valid_quotation_approval_for_issuance_v1(v_approval.id)
     or not public.is_current_pricing_snapshot_integrity_valid(
       v_approval.intake_id, v_approval.pricing_snapshot_id,
       v_approval.approved_payload->'pricing_snapshot'
     )
     or not public.is_valid_quotation_approval_payload_v1(v_approval.approved_payload, true)
     or not public.is_valid_quotation_vat_approval_v1(v_approval.approved_payload->'vat_approval', true)
     or not public.is_valid_quotation_payment_schedule_v1(
       v_approval.approved_payload->'payment_schedule',
       (v_approval.approved_payload->'totals'->>'one_time_subtotal_minor')::bigint, true
     )
     or not public.is_valid_quotation_validity_v1(v_approval.approved_payload->'validity', true)
     or not public.is_valid_quotation_legal_references_v1(
       v_approval.approved_payload->'legal_references', true
     )
     or not public.is_valid_quotation_identity_v1(v_approval.approved_payload->'customer_identity')
     or not public.is_valid_quotation_scope_v1(v_approval.approved_payload->'project_scope') then
    raise exception using errcode = '55000', message = 'SDF_APPROVAL_INTEGRITY_INVALID';
  end if;
  perform public.assert_quotation_business_draft_vat_binding_v1(
    v_business.business_draft_id, p_require_current_vat
  );
  select * into v_terms
  from public.quotation_terms_authorities
  where terms_authority_id = v_decision.terms_authority_id and status = 'APPROVED';
  if not found then
    raise exception using errcode = 'P0001', message = 'QUOTATION_TERMS_NOT_APPROVED';
  end if;

  if p_require_current_vat then
    v_vat_context := public.resolve_quotation_vat_authority_v1(
      v_request.id, (clock_timestamp() at time zone 'Europe/Brussels')::date
    );
    if not public.is_sdf_vat_context_binding_valid_v1(
         v_decision.vat_decision_authority_id, v_vat_context
       )
       or v_decision.vat_context_sha256 is distinct from v_vat_context->>'context_sha256'
       or v_decision.vat_classification_id is distinct from
         (v_vat_context->>'classification_id')::uuid
       or v_decision.vat_turnover_snapshot_id is distinct from
         (v_vat_context->>'turnover_snapshot_id')::uuid then
      raise exception using errcode = '55000', message = 'SDF_VAT_AUTHORITY_CONTEXT_MISMATCH';
    end if;
  else
    select * into strict v_vat_binding
    from public.quotation_business_draft_vat_bindings
    where business_draft_id = v_business.business_draft_id;
    select * into strict v_vat_turnover
    from public.quotation_vat_turnover_snapshots
    where turnover_snapshot_id = v_vat_binding.turnover_snapshot_id;
    v_vat_context := public.resolve_quotation_vat_authority_v1(
      v_request.id, v_vat_turnover.measurement_watermark
    );
    if not public.is_sdf_vat_context_binding_valid_v1(
         v_decision.vat_decision_authority_id, v_vat_context
       )
       or v_decision.vat_decision_authority_id is distinct from
         v_vat_binding.vat_decision_authority_id
       or v_decision.vat_context_sha256 is distinct from v_vat_binding.context_sha256
       or v_decision.vat_classification_id is distinct from v_vat_binding.classification_id
       or v_decision.vat_turnover_snapshot_id is distinct from
         v_vat_binding.turnover_snapshot_id
       or v_vat_binding.vat_decision_authority_id is distinct from
         (v_vat_context->>'vat_decision_authority_id')::uuid
       or v_vat_binding.context_sha256 is distinct from v_vat_context->>'context_sha256'
       or v_vat_binding.classification_id is distinct from
         (v_vat_context->>'classification_id')::uuid
       or v_vat_binding.turnover_snapshot_id is distinct from
         (v_vat_context->>'turnover_snapshot_id')::uuid then
      raise exception using errcode = '55000', message = 'SDF_VAT_AUTHORITY_CONTEXT_MISMATCH';
    end if;
  end if;

  return 'OPERATOR:' || v_operator.operator_id::text;
exception
  when no_data_found or too_many_rows then
    raise exception using errcode = '55000', message = 'SDF_ISSUANCE_LINEAGE_STALE';
end;
$$;

create or replace function lws_internal.assert_sdf_approval_issuance_authority_v1(
  p_business_draft_id uuid,
  p_approval_id uuid,
  p_expected_approval_version integer,
  p_expected_approval_sha256 text
)
returns text
language sql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
  select lws_internal.assert_sdf_approval_issuance_authority_v1(
    p_business_draft_id,
    p_approval_id,
    p_expected_approval_version,
    p_expected_approval_sha256,
    true
  )
$$;

revoke all on function lws_internal.assert_sdf_approval_issuance_authority_v1(
  uuid, uuid, integer, text, boolean
) from public, anon, authenticated, service_role;

create function public.build_sdf_quotation_issue_payload_v1(
  p_business_draft_id uuid,
  p_approval_id uuid,
  p_expected_approval_version integer,
  p_expected_approval_sha256 text,
  p_issuance_id uuid
)
returns table (
  payload jsonb,
  payload_sha256 text
)
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_business public.quote_request_quotation_business_drafts%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_issuance public.quote_request_quotation_issuances%rowtype;
  v_template public.quotation_template_authorities%rowtype;
  v_seller public.quotation_seller_authorities%rowtype;
  v_template_identity jsonb;
  v_payload jsonb;
  v_payload_sha256 text;
begin
  perform lws_internal.assert_sdf_approval_issuance_authority_v1(
    p_business_draft_id,
    p_approval_id,
    p_expected_approval_version,
    p_expected_approval_sha256,
    false
  );

  select * into strict v_business
  from public.quote_request_quotation_business_drafts
  where business_draft_id = p_business_draft_id;
  select * into strict v_approval
  from public.quote_request_quotation_approvals
  where id = p_approval_id;
  select * into v_issuance
  from public.quote_request_quotation_issuances
  where id = p_issuance_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_NOT_FOUND';
  end if;
  select * into strict v_template
  from public.quotation_template_authorities
  where id = v_business.template_authority_id;
  select * into strict v_seller
  from public.quotation_seller_authorities
  where seller_authority_id = v_business.seller_authority_id;

  if v_issuance.approval_id is distinct from v_approval.id
     or rtrim(v_issuance.issuance_input_sha256) is distinct from p_expected_approval_sha256
     or v_issuance.generation_contract_version is distinct from
       v_template.generation_contract_version then
    raise exception using errcode = '42501', message = 'SDF_GENERATION_CROSS_DOSSIER';
  end if;
  if v_issuance.status not in ('PREPARED', 'ISSUED') then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_STATE_CONFLICT';
  end if;
  if v_template.status <> 'APPROVED'
     or v_template.document_type <> 'QUOTATION'
     or v_template.locale <> 'nl-BE'
     or v_template.currency <> 'EUR'
     or v_template.renderer_contract_version <> 1
     or v_template.generation_contract_version <> 1
     or v_template.semantic_contract_version <> 1 then
    raise exception using errcode = 'P0001', message = 'QUOTATION_TEMPLATE_NOT_APPROVED';
  end if;
  if not public.is_valid_quotation_generation_seller_v1(v_seller.seller_identity) then
    raise exception using errcode = '22023', message = 'SELLER_IDENTITY_INVALID';
  end if;

  v_template_identity := jsonb_build_object(
    'template_id', v_template.template_id,
    'template_version', v_template.template_version,
    'template_sha256', lower(rtrim(v_template.template_sha256)),
    'authority_status', v_template.status
  );
  if not public.is_approved_quotation_template_identity_v1(v_template_identity) then
    raise exception using errcode = 'P0001', message = 'QUOTATION_TEMPLATE_NOT_APPROVED';
  end if;

  if v_issuance.status = 'ISSUED'
     and (v_issuance.template_id is distinct from v_template.template_id
       or v_issuance.template_version is distinct from v_template.template_version
       or rtrim(v_issuance.template_sha256) is distinct from
         lower(rtrim(v_template.template_sha256))) then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_STATE_CONFLICT';
  end if;

  v_payload := public.project_quotation_generation_payload_v1(
    'ISSUE',
    v_approval.id,
    v_approval.approved_payload,
    rtrim(v_approval.payload_sha256),
    v_template_identity,
    v_seller.seller_identity,
    v_issuance.id,
    v_issuance.quotation_number,
    v_issuance.quotation_version
  );
  if not public.is_valid_quotation_generation_payload_v1(v_payload) then
    raise exception using errcode = '22023', message = 'INVALID_QUOTATION_GENERATION_PAYLOAD_V1';
  end if;
  v_payload_sha256 := public.quotation_generation_payload_sha256_v1(v_payload);
  if v_issuance.status = 'ISSUED'
     and rtrim(v_issuance.generation_payload_sha256) is distinct from v_payload_sha256 then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_STATE_CONFLICT';
  end if;

  return query select v_payload, v_payload_sha256;
exception
  when no_data_found or too_many_rows then
    raise exception using errcode = '55000', message = 'SDF_GENERATION_AUTHORITY_STALE';
end;
$$;

revoke all on function public.build_sdf_quotation_issue_payload_v1(
  uuid, uuid, integer, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.build_sdf_quotation_issue_payload_v1(
  uuid, uuid, integer, text, uuid
) to authenticated;

comment on function public.build_sdf_quotation_issue_payload_v1(
  uuid, uuid, integer, text, uuid
) is
  'Owner-only QF-4B projection bridge. Reuses frozen SDF approval, template, seller, VAT, generation validation, and SHA-256 authorities without a legacy admin capability.';