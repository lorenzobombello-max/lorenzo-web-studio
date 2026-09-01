create function lws_internal.assert_sdf_approval_issuance_authority_v1(
  p_business_draft_id uuid,
  p_approval_id uuid,
  p_expected_approval_version integer,
  p_expected_approval_sha256 text
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
     or p_expected_approval_sha256 !~ '^[0-9a-f]{64}$' then
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
     or v_decision.vat_classification_id is distinct from
       (v_vat_context->>'classification_id')::uuid
     or v_decision.vat_turnover_snapshot_id is distinct from
       (v_vat_context->>'turnover_snapshot_id')::uuid then
    raise exception using errcode = '55000', message = 'SDF_VAT_AUTHORITY_CONTEXT_MISMATCH';
  end if;

  return 'OPERATOR:' || v_operator.operator_id::text;
exception
  when no_data_found or too_many_rows then
    raise exception using errcode = '55000', message = 'SDF_ISSUANCE_LINEAGE_STALE';
end;
$$;

revoke all on function lws_internal.assert_sdf_approval_issuance_authority_v1(
  uuid, uuid, integer, text
) from public, anon, authenticated, service_role;

create function public.prepare_sdf_quotation_issuance_v1(
  p_business_draft_id uuid,
  p_approval_id uuid,
  p_expected_approval_version integer,
  p_expected_approval_sha256 text,
  p_generation_contract_version smallint,
  p_idempotency_key uuid
)
returns table (
  issuance_id uuid,
  quotation_number text,
  quotation_version integer,
  status text,
  generation_contract_version smallint,
  issuance_input_sha256 text,
  generation_payload_sha256 text,
  was_created boolean
)
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_issuance public.quote_request_quotation_issuances%rowtype;
  v_operation public.quote_request_quotation_issuance_operations%rowtype;
  v_fingerprint text;
  v_actor text;
  v_issue_year smallint;
  v_sequence integer;
begin
  if p_generation_contract_version <> 1 or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'SDF_ISSUANCE_INPUT_INVALID';
  end if;
  v_actor := lws_internal.assert_sdf_approval_issuance_authority_v1(
    p_business_draft_id, p_approval_id, p_expected_approval_version,
    p_expected_approval_sha256
  );
  v_issue_year := extract(year from clock_timestamp() at time zone 'Europe/Brussels')::smallint;
  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'approvalId', p_approval_id,
    'businessDraftId', p_business_draft_id,
    'expectedApprovalSha256', p_expected_approval_sha256,
    'expectedApprovalVersion', p_expected_approval_version,
    'generationContractVersion', p_generation_contract_version,
    'issuanceInputSha256', p_expected_approval_sha256,
    'issueYear', v_issue_year,
    'operatorActor', v_actor
  )::text, 'UTF8'), 'sha256'), 'hex');

  select * into strict v_approval
  from public.quote_request_quotation_approvals
  where id = p_approval_id
  for update;
  select * into v_operation
  from public.quote_request_quotation_issuance_operations
  where idempotency_key = p_idempotency_key;
  if found then
    if v_operation.operation_type <> 'PREPARE'
       or v_operation.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    select * into strict v_issuance
    from public.quote_request_quotation_issuances
    where id = v_operation.issuance_id;
    return query select v_issuance.id, v_issuance.quotation_number,
      v_issuance.quotation_version, v_issuance.status,
      v_issuance.generation_contract_version,
      rtrim(v_issuance.issuance_input_sha256),
      rtrim(v_issuance.generation_payload_sha256), false;
    return;
  end if;

  select * into v_issuance
  from public.quote_request_quotation_issuances
  where approval_id = p_approval_id;
  if found then
    if v_issuance.prepare_fingerprint = v_fingerprint then
      return query select v_issuance.id, v_issuance.quotation_number,
        v_issuance.quotation_version, v_issuance.status,
        v_issuance.generation_contract_version,
        rtrim(v_issuance.issuance_input_sha256),
        rtrim(v_issuance.generation_payload_sha256), false;
      return;
    end if;
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  end if;

  insert into public.quotation_number_counters as counter (year, next_sequence)
  values (v_issue_year, 2)
  on conflict (year) do update
    set next_sequence = counter.next_sequence + 1,
        updated_at = clock_timestamp()
    where counter.next_sequence <= 9999
  returning next_sequence - 1 into v_sequence;
  if v_sequence is null or v_sequence not between 1 and 9999 then
    raise exception using errcode = 'P0001', message = 'QUOTATION_NUMBER_CONFLICT';
  end if;

  begin
    insert into public.quote_request_quotation_issuances (
      quotation_number, quotation_version, status, approval_id,
      generation_contract_version, issuance_input_sha256,
      generation_payload_sha256, prepare_idempotency_key, prepare_fingerprint
    ) values (
      'LWS-OFF-' || v_issue_year::text || '-' || lpad(v_sequence::text, 4, '0'),
      1, 'PREPARED', p_approval_id, p_generation_contract_version,
      p_expected_approval_sha256, null, p_idempotency_key, v_fingerprint
    ) returning * into v_issuance;
  exception when unique_violation then
    raise exception using errcode = 'P0001', message = 'CONCURRENT_ISSUANCE_CONFLICT';
  end;

  insert into public.quote_request_quotation_issuance_operations (
    idempotency_key, operation_type, request_fingerprint, issuance_id
  ) values (p_idempotency_key, 'PREPARE', v_fingerprint, v_issuance.id);

  return query select v_issuance.id, v_issuance.quotation_number,
    v_issuance.quotation_version, v_issuance.status,
    v_issuance.generation_contract_version,
    rtrim(v_issuance.issuance_input_sha256),
    rtrim(v_issuance.generation_payload_sha256), true;
end;
$$;

create function public.commit_sdf_quotation_issuance_v1(
  p_business_draft_id uuid,
  p_approval_id uuid,
  p_expected_approval_version integer,
  p_expected_approval_sha256 text,
  p_issuance_id uuid,
  p_commit_idempotency_key uuid,
  p_generation_payload_sha256 text,
  p_template_id text,
  p_template_version text,
  p_template_sha256 text,
  p_generation_contract_version smallint,
  p_docx_sha256 text,
  p_docx_bytes bigint,
  p_pdf_sha256 text,
  p_pdf_bytes bigint
)
returns table (
  issuance_id uuid,
  quotation_number text,
  quotation_version integer,
  status text,
  generation_payload_sha256 text,
  issued_at timestamptz,
  was_committed boolean
)
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_issuance public.quote_request_quotation_issuances%rowtype;
  v_operation public.quote_request_quotation_issuance_operations%rowtype;
  v_fingerprint text;
  v_actor text;
begin
  if p_issuance_id is null or p_commit_idempotency_key is null
     or p_generation_payload_sha256 is null
     or p_generation_payload_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'GENERATION_PAYLOAD_HASH_MISMATCH';
  end if;
  if nullif(btrim(p_template_id), '') is null
     or nullif(btrim(p_template_version), '') is null
     or p_template_sha256 is null
     or p_template_sha256 !~ '^[0-9a-f]{64}$'
     or p_generation_contract_version <> 1 then
    raise exception using errcode = '22023', message = 'TEMPLATE_IDENTITY_INVALID';
  end if;
  if p_docx_sha256 is null or p_docx_sha256 !~ '^[0-9a-f]{64}$'
     or (p_pdf_sha256 is not null and p_pdf_sha256 !~ '^[0-9a-f]{64}$') then
    raise exception using errcode = '22023', message = 'ARTIFACT_HASH_INVALID';
  end if;
  if p_docx_bytes is null or p_docx_bytes <= 0
     or (p_pdf_sha256 is null) <> (p_pdf_bytes is null)
     or (p_pdf_bytes is not null and p_pdf_bytes <= 0) then
    raise exception using errcode = '22023', message = 'ARTIFACT_BYTES_INVALID';
  end if;

  v_actor := lws_internal.assert_sdf_approval_issuance_authority_v1(
    p_business_draft_id, p_approval_id, p_expected_approval_version,
    p_expected_approval_sha256
  );
  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'approvalId', p_approval_id,
    'businessDraftId', p_business_draft_id,
    'docxBytes', p_docx_bytes,
    'docxSha256', p_docx_sha256,
    'expectedApprovalSha256', p_expected_approval_sha256,
    'expectedApprovalVersion', p_expected_approval_version,
    'generationContractVersion', p_generation_contract_version,
    'generationPayloadSha256', p_generation_payload_sha256,
    'issuanceId', p_issuance_id,
    'issuanceInputSha256', p_expected_approval_sha256,
    'operatorActor', v_actor,
    'pdfBytes', p_pdf_bytes,
    'pdfSha256', p_pdf_sha256,
    'templateId', p_template_id,
    'templateSha256', p_template_sha256,
    'templateVersion', p_template_version
  )::text, 'UTF8'), 'sha256'), 'hex');

  select * into v_issuance
  from public.quote_request_quotation_issuances
  where id = p_issuance_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_NOT_FOUND';
  end if;
  if v_issuance.approval_id is distinct from p_approval_id then
    raise exception using errcode = '42501', message = 'SDF_ISSUANCE_CROSS_DOSSIER';
  end if;

  select * into v_operation
  from public.quote_request_quotation_issuance_operations
  where idempotency_key = p_commit_idempotency_key;
  if found then
    if v_operation.operation_type <> 'COMMIT'
       or v_operation.request_fingerprint <> v_fingerprint
       or v_operation.issuance_id <> p_issuance_id then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return query select v_issuance.id, v_issuance.quotation_number,
      v_issuance.quotation_version, v_issuance.status,
      rtrim(v_issuance.generation_payload_sha256), v_issuance.issued_at, false;
    return;
  end if;

  if v_issuance.status = 'VOID' then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_VOID';
  end if;
  if v_issuance.status <> 'PREPARED' then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_ALREADY_COMPLETED';
  end if;
  if rtrim(v_issuance.issuance_input_sha256) <> p_expected_approval_sha256
     or v_issuance.generation_contract_version <> p_generation_contract_version then
    raise exception using errcode = 'P0001', message = 'PREPARATION_INPUT_HASH_MISMATCH';
  end if;

  perform set_config('lws.quotation_issuance_transition', 'COMMIT_V2', true);
  update public.quote_request_quotation_issuances
  set status = 'ISSUED', generation_payload_sha256 = p_generation_payload_sha256,
      issued_at = clock_timestamp(), issued_by = v_actor,
      template_id = p_template_id, template_version = p_template_version,
      template_sha256 = p_template_sha256,
      docx_sha256 = p_docx_sha256, docx_bytes = p_docx_bytes,
      pdf_sha256 = p_pdf_sha256, pdf_bytes = p_pdf_bytes,
      commit_idempotency_key = p_commit_idempotency_key,
      commit_fingerprint = v_fingerprint
  where id = p_issuance_id
  returning * into v_issuance;
  perform set_config('lws.quotation_issuance_transition', '', true);

  insert into public.quote_request_quotation_issuance_operations (
    idempotency_key, operation_type, request_fingerprint, issuance_id
  ) values (p_commit_idempotency_key, 'COMMIT', v_fingerprint, v_issuance.id);

  return query select v_issuance.id, v_issuance.quotation_number,
    v_issuance.quotation_version, v_issuance.status,
    rtrim(v_issuance.generation_payload_sha256), v_issuance.issued_at, true;
end;
$$;

revoke all on function public.prepare_sdf_quotation_issuance_v1(
  uuid, uuid, integer, text, smallint, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.prepare_sdf_quotation_issuance_v1(
  uuid, uuid, integer, text, smallint, uuid
) to authenticated;

revoke all on function public.commit_sdf_quotation_issuance_v1(
  uuid, uuid, integer, text, uuid, uuid, text, text, text, text,
  smallint, text, bigint, text, bigint
) from public, anon, authenticated, service_role;
grant execute on function public.commit_sdf_quotation_issuance_v1(
  uuid, uuid, integer, text, uuid, uuid, text, text, text, text,
  smallint, text, bigint, text, bigint
) to authenticated;

comment on function public.prepare_sdf_quotation_issuance_v1(
  uuid, uuid, integer, text, smallint, uuid
) is
  'Owner-only QF-3B PREPARE bridge using the existing atomic numbering and issuance ledgers.';
comment on function public.commit_sdf_quotation_issuance_v1(
  uuid, uuid, integer, text, uuid, uuid, text, text, text, text,
  smallint, text, bigint, text, bigint
) is
  'Owner-only QF-3B COMMIT bridge using the existing issuance state and artifact hash contract.';