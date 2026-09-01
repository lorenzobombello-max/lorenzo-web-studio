create function public.promote_sdf_quotation_business_draft_to_approval_v1(
  p_business_draft_id uuid,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_approval_id uuid,
  p_integrity jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_adapter public.sdf_quotation_business_draft_adapters%rowtype;
  v_business public.quote_request_quotation_business_drafts%rowtype;
  v_preparation public.sdf_quotation_preparation_authorities%rowtype;
  v_decision public.sdf_quotation_commercial_decisions%rowtype;
  v_submission public.sdf_qualification_intake_submissions%rowtype;
  v_request public.quote_requests%rowtype;
  v_snapshot public.quote_request_pricing_snapshots%rowtype;
  v_draft public.quote_request_quotation_approval_drafts%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_operation public.quote_request_quotation_approval_operations%rowtype;
  v_promotion_operation public.quote_request_quotation_business_approval_promotion_operations%rowtype;
  v_promotion public.quote_request_quotation_business_approval_promotions%rowtype;
  v_terms public.quotation_terms_authorities%rowtype;
  v_pricing jsonb;
  v_vat_context jsonb;
  v_payload jsonb;
  v_payload_sha256 text;
  v_submission_sha256 text;
  v_pricing_sha256 text;
  v_document_sha256 text;
  v_decision_sha256 text;
  v_approval_fingerprint text;
  v_promotion_fingerprint text;
  v_version integer;
  v_result jsonb;
  v_actor text;
begin
  if p_business_draft_id is null
     or p_expected_revision is null or p_expected_revision < 1
     or p_idempotency_key is null or p_approval_id is null
     or p_integrity is null then
    raise exception using errcode = '22023', message = 'SDF_APPROVAL_INPUT_INVALID';
  end if;

  v_operator := lws_internal.assert_sdf_owner_v1();
  v_actor := 'OPERATOR:' || v_operator.operator_id::text;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_business_draft_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key::text, 0)
  );

  select * into v_adapter
  from public.sdf_quotation_business_draft_adapters
  where business_draft_id = p_business_draft_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'SDF_BUSINESS_DRAFT_NOT_FOUND';
  end if;

  select * into strict v_business
  from public.quote_request_quotation_business_drafts
  where business_draft_id = v_adapter.business_draft_id;
  if v_business.business_revision is distinct from p_expected_revision then
    raise exception using errcode = 'P0001', message = 'STALE_BUSINESS_REVISION';
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

  if v_adapter.quote_request_id is distinct from v_business.quote_request_id
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
     or v_draft.pricing_snapshot_id is distinct from v_adapter.pricing_snapshot_id then
    raise exception using errcode = '42501', message = 'SDF_APPROVAL_CROSS_DOSSIER';
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

  v_payload := v_business.canonical_payload;
  v_payload_sha256 := public.quotation_approval_payload_sha256_v1(v_payload);
  if rtrim(v_business.canonical_payload_sha256) is distinct from v_payload_sha256
     or v_draft.contract_version <> 1
     or v_draft.approval_payload is distinct from v_payload
     or v_draft.payload_fingerprint is distinct from v_payload_sha256
     or v_business.terms_authority_id is distinct from v_decision.terms_authority_id
     or v_business.vat_decision_authority_id is distinct from v_decision.vat_decision_authority_id
     or v_payload->'payment_schedule' is distinct from v_decision.payment_schedule then
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  end if;

  if not public.is_current_pricing_snapshot_integrity_valid(
       v_business.intake_id, v_business.pricing_snapshot_id,
       v_payload->'pricing_snapshot'
     )
     or not public.is_valid_quotation_approval_payload_v1(v_payload, true)
     or not public.is_valid_quotation_vat_approval_v1(v_payload->'vat_approval', true)
     or not public.is_valid_quotation_payment_schedule_v1(
       v_payload->'payment_schedule',
       (v_payload->'totals'->>'one_time_subtotal_minor')::bigint, true
     )
     or not public.is_valid_quotation_validity_v1(v_payload->'validity', true)
     or not public.is_valid_quotation_legal_references_v1(v_payload->'legal_references', true)
     or not public.is_valid_quotation_identity_v1(v_payload->'customer_identity')
     or not public.is_valid_quotation_scope_v1(v_payload->'project_scope') then
    raise exception using errcode = '22023', message = 'SDF_APPROVAL_VALIDATION_FAILED';
  end if;
  perform public.assert_quotation_business_draft_vat_binding_v1(
    v_business.business_draft_id, true
  );
  select * into v_terms
  from public.quotation_terms_authorities
  where terms_authority_id = v_decision.terms_authority_id and status = 'APPROVED';
  if not found then
    raise exception using errcode = 'P0001', message = 'QUOTATION_TERMS_NOT_APPROVED';
  end if;
  v_vat_context := public.resolve_quotation_vat_authority_v1(
    v_request.id, (clock_timestamp() at time zone 'Europe/Brussels')::date
  );
  if not public.is_sdf_vat_context_binding_valid_v1(
       v_decision.vat_decision_authority_id, v_vat_context
     )
     or v_decision.vat_context_sha256 is distinct from v_vat_context->>'context_sha256'
     or v_decision.vat_classification_id is distinct from (v_vat_context->>'classification_id')::uuid
     or v_decision.vat_turnover_snapshot_id is distinct from (v_vat_context->>'turnover_snapshot_id')::uuid then
    raise exception using errcode = '55000', message = 'SDF_VAT_AUTHORITY_CONTEXT_MISMATCH';
  end if;

  if not public.jsonb_has_exact_keys(
       p_integrity, array['algorithmVersion', 'keyId', 'mac', 'root']
     )
     or p_integrity->>'algorithmVersion' <> 'hmac-sha256-v1'
     or p_integrity->>'keyId' !~ '^v[1-9][0-9]*$'
     or not public.is_sha256_jsonb(p_integrity->'mac')
     or p_integrity->'root' <> public.quotation_approval_integrity_root_v1(
       p_approval_id, v_payload_sha256, v_draft.contract_version,
       v_draft.quote_request_id, v_draft.intake_id, v_draft.pricing_snapshot_id
     ) then
    raise exception using errcode = 'P0001', message = 'PRICING_INTEGRITY_INVALID';
  end if;

  v_promotion_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'approvalId', p_approval_id,
    'businessDraftId', v_business.business_draft_id,
    'businessRevision', v_business.business_revision,
    'commercialDecisionId', v_adapter.commercial_decision_id,
    'decisionSha256', v_decision_sha256,
    'documentEvidenceSha256', v_document_sha256,
    'operatorId', v_operator.operator_id,
    'payloadSha256', v_payload_sha256,
    'pricingAuthoritySha256', v_pricing_sha256,
    'pricingSnapshotId', v_business.pricing_snapshot_id,
    'submissionSha256', v_submission_sha256
  )::text, 'UTF8'), 'sha256'), 'hex');
  v_approval_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'approvalId', p_approval_id,
    'draftId', v_draft.id,
    'payloadSha256', v_payload_sha256
  )::text, 'UTF8'), 'sha256'), 'hex');

  select * into v_promotion_operation
  from public.quote_request_quotation_business_approval_promotion_operations
  where idempotency_key = p_idempotency_key;
  if found then
    if v_promotion_operation.business_draft_id is distinct from v_business.business_draft_id
       or v_promotion_operation.approval_id is distinct from p_approval_id
       or rtrim(v_promotion_operation.request_fingerprint) is distinct from v_promotion_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_promotion_operation.result_payload || jsonb_build_object('was_created', false);
  end if;

  select * into v_promotion
  from public.quote_request_quotation_business_approval_promotions
  where business_draft_id = v_business.business_draft_id;
  if found then
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  end if;
  if exists (
    select 1 from public.quote_request_quotation_approvals
    where draft_id = v_draft.id
  ) then
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  end if;
  select * into v_operation
  from public.quote_request_quotation_approval_operations
  where idempotency_key = p_idempotency_key;
  if found then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
  end if;

  select coalesce(max(approval.approval_version), 0) + 1 into v_version
  from public.quote_request_quotation_approvals as approval
  where approval.intake_id = v_draft.intake_id;
  insert into public.quote_request_quotation_approvals (
    id, draft_id, quote_request_id, intake_id, pricing_snapshot_id,
    contract_version, approval_version, approved_payload, payload_sha256,
    approved_by, approved_at
  ) values (
    p_approval_id, v_draft.id, v_draft.quote_request_id, v_draft.intake_id,
    v_draft.pricing_snapshot_id, v_draft.contract_version, v_version,
    v_payload, v_payload_sha256, v_actor, clock_timestamp()
  ) returning * into v_approval;
  insert into public.quote_request_quotation_approval_integrity (
    approval_id, algorithm_version, key_id, mac
  ) values (
    v_approval.id, p_integrity->>'algorithmVersion',
    p_integrity->>'keyId', p_integrity->>'mac'
  );
  insert into public.quote_request_quotation_approval_operations (
    idempotency_key, operation_type, request_fingerprint, draft_id, approval_id
  ) values (
    p_idempotency_key, 'APPROVE', v_approval_fingerprint,
    v_draft.id, v_approval.id
  );
  insert into public.quote_request_quotation_business_approval_promotions (
    business_draft_id, approval_id
  ) values (v_business.business_draft_id, v_approval.id);

  v_result := jsonb_build_object(
    'business_draft_id', v_business.business_draft_id,
    'business_revision', v_business.business_revision,
    'approval_id', v_approval.id,
    'approval_version', v_approval.approval_version,
    'status', 'APPROVED',
    'approved_at', v_approval.approved_at,
    'was_created', true
  );
  insert into public.quote_request_quotation_business_approval_promotion_operations (
    idempotency_key, operation_type, operator_id, business_draft_id,
    expected_revision, request_fingerprint, approval_id, result_payload
  ) values (
    p_idempotency_key, 'PROMOTE_BUSINESS_DRAFT', v_operator.operator_id,
    v_business.business_draft_id, p_expected_revision,
    v_promotion_fingerprint, v_approval.id, v_result
  );
  return v_result;
exception
  when unique_violation then
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  when no_data_found or too_many_rows then
    raise exception using errcode = '55000', message = 'SDF_APPROVAL_LINEAGE_STALE';
end;
$$;

revoke all on function public.promote_sdf_quotation_business_draft_to_approval_v1(
  uuid, bigint, uuid, uuid, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.promote_sdf_quotation_business_draft_to_approval_v1(
  uuid, bigint, uuid, uuid, jsonb
) to authenticated;

comment on function public.promote_sdf_quotation_business_draft_to_approval_v1(
  uuid, bigint, uuid, uuid, jsonb
) is
  'Owner-only QF-3A CREATE bridge. Revalidates immutable SDF business lineage and all generic commercial validators before appending to the existing approval and promotion ledgers without a legacy website admin capability.';