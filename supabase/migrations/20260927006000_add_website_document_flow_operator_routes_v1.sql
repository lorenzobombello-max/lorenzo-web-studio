create function public.get_website_commercial_document_status_v1(
  p_quote_request_id uuid,
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_authorization record;
  v_bound_quote_request_id uuid;
  v_request_kind text;
  v_document record;
  v_candidate public.website_commercial_document_candidates%rowtype;
  v_artifact public.website_commercial_document_render_artifacts%rowtype;
  v_obligation public.commercial_obligations%rowtype;
  v_documents jsonb := '[]'::jsonb;
  v_state text;
  v_blocking_reason text;
begin
  if p_quote_request_id is null or p_project_id is null then
    raise exception using errcode = '22023', message = 'WEBSITE_COMMERCIAL_STATUS_INPUT_INVALID';
  end if;

  select * into strict v_authorization
  from public.resolve_commercial_operator_authorization_v1(
    p_project_id,
    'READ_PROJECT',
    false
  );

  select approval.quote_request_id, request.request_kind
  into strict v_bound_quote_request_id, v_request_kind
  from public.commercial_projects as project
  join public.quote_request_quotation_issuances as issuance
    on issuance.id = project.quotation_issuance_id
  join public.quote_request_quotation_approvals as approval
    on approval.id = issuance.approval_id
  join public.quote_requests as request
    on request.id = approval.quote_request_id
  where project.project_id = p_project_id;

  if v_bound_quote_request_id <> p_quote_request_id then
    raise exception using errcode = '23514', message = 'WEBSITE_COMMERCIAL_PROJECT_BINDING_MISMATCH';
  end if;
  if v_request_kind <> 'website' then
    raise exception using errcode = '23514', message = 'WEBSITE_COMMERCIAL_PRODUCT_FAMILY_INVALID';
  end if;

  for v_document in
    select * from (values
      (1, 'AGREEMENT'::text, null::smallint),
      (2, 'INVOICE_M1'::text, 1::smallint),
      (3, 'INVOICE_M2'::text, 2::smallint),
      (4, 'INVOICE_FINAL'::text, 3::smallint)
    ) as ordered_documents(ordinal, document_kind, milestone)
    order by ordinal
  loop
    v_candidate := null;
    v_artifact := null;
    v_obligation := null;

    select * into v_candidate
    from public.website_commercial_document_candidates
    where project_id = p_project_id and document_kind = v_document.document_kind;

    if not found then
      v_state := 'ABSENT';
      v_blocking_reason := 'CONCEPT_NOT_PREPARED';
    else
      if v_candidate.quote_request_id <> p_quote_request_id
         or v_candidate.candidate_status <> 'PREPARED_LOCAL_CONCEPT'
         or v_candidate.issuance_status <> 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
         or (v_document.document_kind = 'AGREEMENT' and (
           v_candidate.agreement_status is distinct from 'UNSIGNED_CONCEPT'
           or v_candidate.milestone is not null
           or v_candidate.obligation_id is not null
         ))
         or (v_document.document_kind <> 'AGREEMENT' and (
           v_candidate.agreement_status is not null
           or v_candidate.milestone is distinct from v_document.milestone
           or v_candidate.obligation_id is null
         )) then
        raise exception using errcode = '23514', message = 'WEBSITE_COMMERCIAL_REGISTRATION_INCONSISTENT';
      end if;

      if v_candidate.obligation_id is not null then
        select * into v_obligation
        from public.commercial_obligations
        where obligation_id = v_candidate.obligation_id;
        if not found
           or v_obligation.project_id <> p_project_id
           or v_obligation.obligation_type <> 'PROJECT_MILESTONE'
           or v_obligation.milestone is distinct from v_document.milestone then
          raise exception using errcode = '23514', message = 'WEBSITE_COMMERCIAL_REGISTRATION_INCONSISTENT';
        end if;
      end if;

      select * into v_artifact
      from public.website_commercial_document_render_artifacts
      where candidate_id = v_candidate.candidate_id;

      if found then
        if v_artifact.document_kind <> v_document.document_kind
           or v_artifact.generation_payload_sha256 <> v_candidate.generation_payload_sha256
           or v_artifact.render_status <> 'LOCAL_RENDER_ONLY'
           or v_artifact.issuance_status <> 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED' then
          raise exception using errcode = '23514', message = 'WEBSITE_COMMERCIAL_REGISTRATION_INCONSISTENT';
        end if;
        v_state := 'REGISTERED';
        v_blocking_reason := 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED';
      else
        v_state := 'CANDIDATE_ONLY';
        v_blocking_reason := 'LOCAL_RENDER_REGISTRATION_REQUIRED';
      end if;
    end if;

    v_documents := v_documents || jsonb_build_array(jsonb_build_object(
      'document_kind', v_document.document_kind,
      'state', v_state,
      'candidate_id', v_candidate.candidate_id,
      'candidate_status', v_candidate.candidate_status,
      'agreement_status', v_candidate.agreement_status,
      'milestone', v_candidate.milestone,
      'obligation_id', v_candidate.obligation_id,
      'candidate_issuance_status', v_candidate.issuance_status,
      'artifact_id', v_artifact.artifact_id,
      'render_status', v_artifact.render_status,
      'render_issuance_status', v_artifact.issuance_status,
      'blocking_reason', v_blocking_reason
    ));
  end loop;

  return jsonb_build_object(
    'quote_request_id', p_quote_request_id,
    'project_id', p_project_id,
    'documents', v_documents
  );
end;
$$;

revoke all on function public.get_website_commercial_document_status_v1(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_website_commercial_document_status_v1(uuid, uuid)
to authenticated;

comment on function public.get_website_commercial_document_status_v1(uuid, uuid) is
  'Read-only ordered projection of immutable Website agreement and invoice concept/render evidence.';

create function public.get_website_quotation_approval_status_v1(
  p_quote_request_id uuid,
  p_intake_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_request public.quote_requests%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_business public.quote_request_quotation_business_drafts%rowtype;
  v_promotion public.quote_request_quotation_business_approval_promotions%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
begin
  if p_quote_request_id is null or p_intake_id is null then
    raise exception using errcode = '22023', message = 'WEBSITE_QUOTATION_APPROVAL_STATUS_INPUT_INVALID';
  end if;

  select * into v_operator
  from public.commercial_operators
  where auth_user_id = auth.uid();
  if not found or v_operator.status <> 'ACTIVE'
     or v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'QUOTATION_BUSINESS_SCOPE_DENIED';
  end if;

  select * into v_request
  from public.quote_requests
  where id = p_quote_request_id;
  select * into v_intake
  from public.quote_request_intakes
  where id = p_intake_id;
  if not found or v_request.id is null
     or v_intake.quote_request_id <> v_request.id then
    raise exception using errcode = '23514', message = 'WEBSITE_QUOTATION_APPROVAL_BINDING_MISMATCH';
  end if;
  if v_request.request_kind <> 'website' then
    raise exception using errcode = '23514', message = 'WEBSITE_QUOTATION_APPROVAL_PRODUCT_FAMILY_INVALID';
  end if;

  select * into v_business
  from public.quote_request_quotation_business_drafts
  where quote_request_id = p_quote_request_id
    and intake_id = p_intake_id
  order by business_revision desc
  limit 1;
  if not found then
    return jsonb_build_object(
      'quote_request_id', p_quote_request_id,
      'intake_id', p_intake_id,
      'state', 'NO_DRAFT',
      'business_draft_id', null,
      'business_revision', null,
      'approval_id', null,
      'approval_status', null,
      'approved_at', null
    );
  end if;

  select * into v_promotion
  from public.quote_request_quotation_business_approval_promotions
  where business_draft_id = v_business.business_draft_id;
  if not found then
    return jsonb_build_object(
      'quote_request_id', p_quote_request_id,
      'intake_id', p_intake_id,
      'state', 'AWAITING_APPROVAL',
      'business_draft_id', v_business.business_draft_id,
      'business_revision', v_business.business_revision,
      'approval_id', null,
      'approval_status', null,
      'approved_at', null
    );
  end if;

  select * into v_approval
  from public.quote_request_quotation_approvals
  where id = v_promotion.approval_id;
  if not found
     or v_approval.draft_id <> v_business.approval_draft_id
     or v_approval.quote_request_id <> v_business.quote_request_id
     or v_approval.intake_id <> v_business.intake_id
     or v_approval.pricing_snapshot_id <> v_business.pricing_snapshot_id
     or v_approval.approved_payload is distinct from v_business.canonical_payload
    or rtrim(v_approval.payload_sha256) <> rtrim(v_business.canonical_payload_sha256) then
    raise exception using errcode = '23514', message = 'WEBSITE_QUOTATION_APPROVAL_STATUS_INCONSISTENT';
  end if;

  return jsonb_build_object(
    'quote_request_id', p_quote_request_id,
    'intake_id', p_intake_id,
    'state', 'APPROVED',
    'business_draft_id', v_business.business_draft_id,
    'business_revision', v_business.business_revision,
    'approval_id', v_approval.id,
    'approval_status', 'APPROVED',
    'approved_at', v_approval.approved_at
  );
end;
$$;

revoke all on function public.get_website_quotation_approval_status_v1(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_website_quotation_approval_status_v1(uuid, uuid)
to authenticated;

comment on function public.get_website_quotation_approval_status_v1(uuid, uuid) is
  'Read-only owner/admin projection of the latest dossier-bound Website quotation business draft and immutable approval promotion.';

alter function public.prepare_website_commercial_document_concept_v1(uuid, text, uuid)
rename to prepare_website_commercial_document_concept_unvalidated_v1;

revoke all on function public.prepare_website_commercial_document_concept_unvalidated_v1(uuid, text, uuid)
from public, anon, authenticated, service_role;

create function public.prepare_website_commercial_document_concept_v1(
  p_project_id uuid,
  p_document_kind text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_approved_payload jsonb;
  v_current_state text;
  v_timing jsonb;
  v_timing_number numeric;
begin
  select approval.approved_payload, project.current_state
  into v_approved_payload, v_current_state
  from public.commercial_projects project
  join public.quote_request_quotation_issuances issuance
    on issuance.id = project.quotation_issuance_id
  join public.quote_request_quotation_approvals approval
    on approval.id = issuance.approval_id
  where project.project_id = p_project_id
  for update of project;

  if found then
    v_timing := v_approved_payload->'project_scope'->'indicative_timing';
    if jsonb_typeof(v_timing) is distinct from 'number' then
      raise exception using errcode = '22023', message = 'WEBSITE_COMMERCIAL_INDICATIVE_TIMING_REQUIRED';
    end if;
    v_timing_number := (v_timing #>> '{}')::numeric;
    if v_timing_number <= 0 or trunc(v_timing_number) <> v_timing_number then
      raise exception using errcode = '22023', message = 'WEBSITE_COMMERCIAL_INDICATIVE_TIMING_REQUIRED';
    end if;

    if (p_document_kind = 'INVOICE_M1' and v_current_state is distinct from 'M1_PAYMENT_PENDING')
       or (p_document_kind = 'INVOICE_M2' and v_current_state is distinct from 'PREVIEW_READY')
       or (p_document_kind = 'INVOICE_FINAL' and v_current_state is distinct from 'FINAL_APPROVAL_RECORDED') then
      raise exception using errcode = 'P0001', message = 'WEBSITE_COMMERCIAL_PROJECT_STATE_REQUIRED';
    end if;

    if p_document_kind = 'INVOICE_M1' and not exists (
      select 1
      from public.website_commercial_document_candidates candidate
      join public.website_commercial_document_render_artifacts artifact
        on artifact.candidate_id = candidate.candidate_id
       and artifact.document_kind = candidate.document_kind
       and artifact.generation_payload_sha256 = candidate.generation_payload_sha256
      join public.website_commercial_document_templates template
        on template.document_kind = candidate.document_kind
       and artifact.template_sha256 = template.derivative_sha256
      where candidate.project_id = p_project_id
        and candidate.document_kind = 'AGREEMENT'
        and candidate.candidate_status = 'PREPARED_LOCAL_CONCEPT'
        and candidate.agreement_status = 'UNSIGNED_CONCEPT'
        and candidate.issuance_status = 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
        and artifact.render_status = 'LOCAL_RENDER_ONLY'
        and artifact.issuance_status = 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
        and not template.test_only
        and not template.fiscal_fields_resolved
        and template.issuance_status = 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
    ) then
      raise exception using errcode = 'P0001', message = 'WEBSITE_COMMERCIAL_AGREEMENT_RENDER_REQUIRED';
    end if;

    if p_document_kind in ('INVOICE_M2', 'INVOICE_FINAL') and not exists (
      select 1
      from public.website_commercial_document_candidates candidate
      join public.website_commercial_document_render_artifacts artifact
        on artifact.candidate_id = candidate.candidate_id
       and artifact.document_kind = candidate.document_kind
       and artifact.generation_payload_sha256 = candidate.generation_payload_sha256
      join public.website_commercial_document_templates template
        on template.document_kind = candidate.document_kind
       and artifact.template_sha256 = template.derivative_sha256
      where candidate.project_id = p_project_id
        and candidate.document_kind = 'INVOICE_M1'
        and candidate.candidate_status = 'PREPARED_LOCAL_CONCEPT'
        and candidate.issuance_status = 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
        and artifact.render_status = 'LOCAL_RENDER_ONLY'
        and artifact.issuance_status = 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
        and not template.test_only
        and not template.fiscal_fields_resolved
        and template.issuance_status = 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
    ) then
      raise exception using errcode = 'P0001', message = 'WEBSITE_COMMERCIAL_M1_RENDER_REQUIRED';
    end if;

    if p_document_kind = 'INVOICE_FINAL' and not exists (
      select 1
      from public.website_commercial_document_candidates candidate
      join public.website_commercial_document_render_artifacts artifact
        on artifact.candidate_id = candidate.candidate_id
       and artifact.document_kind = candidate.document_kind
       and artifact.generation_payload_sha256 = candidate.generation_payload_sha256
      join public.website_commercial_document_templates template
        on template.document_kind = candidate.document_kind
       and artifact.template_sha256 = template.derivative_sha256
      where candidate.project_id = p_project_id
        and candidate.document_kind = 'INVOICE_M2'
        and candidate.candidate_status = 'PREPARED_LOCAL_CONCEPT'
        and candidate.issuance_status = 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
        and artifact.render_status = 'LOCAL_RENDER_ONLY'
        and artifact.issuance_status = 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
        and not template.test_only
        and not template.fiscal_fields_resolved
        and template.issuance_status = 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
    ) then
      raise exception using errcode = 'P0001', message = 'WEBSITE_COMMERCIAL_M2_RENDER_REQUIRED';
    end if;
  end if;

  return public.prepare_website_commercial_document_concept_unvalidated_v1(
    p_project_id,
    p_document_kind,
    p_idempotency_key
  );
end;
$$;

revoke all on function public.prepare_website_commercial_document_concept_v1(uuid, text, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.prepare_website_commercial_document_concept_v1(uuid, text, uuid)
to service_role;

comment on function public.prepare_website_commercial_document_concept_v1(uuid, text, uuid) is
  'Service-only Website commercial concept preparation with fail-closed positive integer execution timing validation before candidate insertion.';