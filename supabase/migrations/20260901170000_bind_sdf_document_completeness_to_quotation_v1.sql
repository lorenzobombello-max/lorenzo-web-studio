alter table public.sdf_quotation_preparation_authorities
  add column document_evidence_sha256 char(64),
  add constraint sdf_quotation_preparation_document_evidence_sha256_valid
    check (document_evidence_sha256 is null or document_evidence_sha256 ~ '^[0-9a-f]{64}$');

create function lws_internal.evaluate_sdf_document_completeness_v1(p_quote_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_requirement_state jsonb;
  v_canonical_requirements jsonb;
  v_canonical_document_state jsonb;
  v_required_count integer;
  v_satisfied_count integer;
  v_missing_count integer;
  v_is_complete boolean;
  v_evidence_sha256 text;
  v_classification_reason text;
begin
  if p_quote_request_id is null or not exists (
    select 1
    from public.quote_requests
    where id = p_quote_request_id
      and request_kind = 'slimme_documentenflow'
      and record_classification = 'production'
  ) then
    raise exception using errcode = '23514', message = 'SDF_PRODUCTION_DOSSIER_REQUIRED';
  end if;

  v_requirement_state := lws_internal.get_sdf_document_requirements_v1(p_quote_request_id);
  select
    count(*)::integer,
    count(*) filter (where requirement->>'status' = 'SATISFIED')::integer
  into v_required_count, v_satisfied_count
  from jsonb_array_elements(v_requirement_state->'requirements') requirement;
  v_missing_count := v_required_count - v_satisfied_count;
  v_is_complete := v_required_count > 0 and v_missing_count = 0;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'requirement_id', required.requirement_id,
      'document_type', required.document_type,
      'required_count', required.required_count,
      'requirement_status', required.requirement_status,
      'source', required.source,
      'valid_evidence_count', (state.value->>'valid_evidence_count')::integer,
      'derived_status', state.value->>'status',
      'evidence', coalesce(evidence.items, '[]'::jsonb)
    ) order by required.document_type, required.requirement_id
  ), '[]'::jsonb)
  into v_canonical_requirements
  from public.sdf_document_requirements required
  join lateral (
    select value
    from jsonb_array_elements(v_requirement_state->'requirements') value
    where value->>'requirement_id' = required.requirement_id::text
  ) state on true
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'uploaded_file_id', bound.uploaded_file_id,
        'document_inbox_item_id', bound.document_inbox_item_id,
        'customer_request_id', provenance.customer_request_id,
        'file_sha256', rtrim(uploaded.sha256),
        'uploaded_file_status', uploaded.status,
        'inbox_lifecycle_status', inbox.lifecycle_status
      ) order by bound.uploaded_file_id, bound.document_inbox_item_id
    ) as items
    from public.sdf_document_requirement_evidence bound
    join public.document_inbox_customer_request_upload_sources provenance
      on provenance.uploaded_file_id = bound.uploaded_file_id
     and provenance.quote_request_id = bound.quote_request_id
     and provenance.document_inbox_item_id = bound.document_inbox_item_id
    join public.customer_request_uploaded_files uploaded
      on uploaded.uploaded_file_id = bound.uploaded_file_id
    join public.document_inbox_items inbox
      on inbox.id = bound.document_inbox_item_id
    where bound.requirement_id = required.requirement_id
      and bound.quote_request_id = required.quote_request_id
      and uploaded.status = 'ACCEPTED'
      and inbox.lifecycle_status in ('RECEIVED', 'REVIEW_REQUIRED', 'APPROVED', 'PROCESSED')
  ) evidence on true
  where required.quote_request_id = p_quote_request_id;

  v_canonical_document_state := jsonb_build_object(
    'version', 1,
    'quote_request_id', p_quote_request_id,
    'requirements', v_canonical_requirements
  );
  v_evidence_sha256 := encode(
    extensions.digest(convert_to(v_canonical_document_state::text, 'UTF8'), 'sha256'),
    'hex'
  );
  v_classification_reason := case
    when v_required_count = 0 then 'NO_REQUIREMENTS'
    when v_missing_count > 0 then 'REQUIREMENTS_MISSING'
    else 'COMPLETE'
  end;

  return jsonb_build_object(
    'quote_request_id', p_quote_request_id,
    'required_count', v_required_count,
    'satisfied_count', v_satisfied_count,
    'missing_count', v_missing_count,
    'is_complete', v_is_complete,
    'evidence_sha256', v_evidence_sha256,
    'classification_reason', v_classification_reason
  );
end;
$$;

create or replace function public.authorize_sdf_quotation_preparation_v1(p_quote_request_id uuid,p_idempotency_key uuid)
returns jsonb language plpgsql volatile security definer set search_path=public,lws_internal,auth,extensions,pg_catalog as $$
declare v_operator public.commercial_operators%rowtype; v_request public.quote_requests%rowtype; v_intake public.sdf_qualification_intakes%rowtype; v_submission public.sdf_qualification_intake_submissions%rowtype; v_completion public.sdf_qualification_intake_events%rowtype; v_existing public.sdf_quotation_preparation_authorities%rowtype; v_quotation_id uuid; v_binding jsonb; v_document_completeness jsonb; v_package text; v_pricing jsonb; v_pricing_hash char(64); v_submission_hash char(64); v_document_evidence_hash char(64); v_fingerprint char(64);
begin
  v_operator:=lws_internal.assert_sdf_owner_v1();
  select * into v_request from public.quote_requests where id=p_quote_request_id for update;
  if not found or v_request.request_kind<>'slimme_documentenflow' then raise exception using errcode='23514',message='SDF_REQUEST_KIND_REQUIRED'; end if;
  if v_request.status='rejected' then raise exception using errcode='55000',message='SDF_QUOTATION_PREPARATION_NOT_ELIGIBLE'; end if;
  if exists(select 1 from lws_internal.operator_dossier_states where quote_request_id=p_quote_request_id and state='TRASHED') then raise exception using errcode='55000',message='SDF_QUOTATION_PREPARATION_NOT_ELIGIBLE'; end if;
  select * into v_intake from public.sdf_qualification_intakes where quote_request_id=p_quote_request_id for update;
  if not found or v_intake.status<>'qualification_complete' then raise exception using errcode='55000',message='SDF_QUALIFICATION_COMPLETE_REQUIRED'; end if;
  select * into strict v_submission from public.sdf_qualification_intake_submissions where intake_id=v_intake.intake_id and submission_sequence=v_intake.latest_submission_sequence;
  select * into strict v_completion from public.sdf_qualification_intake_events where intake_id=v_intake.intake_id and event_kind='QUALIFICATION_COMPLETE' and submission_sequence=v_submission.submission_sequence order by occurred_at desc limit 1;
  v_submission_hash:=encode(extensions.digest(convert_to(v_submission.answers::text,'UTF8'),'sha256'),'hex');
  if v_submission_hash<>v_submission.payload_sha256 or v_submission.taxonomy_version<>v_intake.taxonomy_version then raise exception using errcode='55000',message='SDF_QUALIFICATION_INTEGRITY_MISMATCH'; end if;

  if v_submission.taxonomy_version='sdf_qualification_intake/3.0.0' then
    v_binding:=lws_internal.get_sdf_budget_guard_quotation_binding_v1(v_submission.answers);
    v_package:=v_binding->>'package';
    v_pricing:=v_binding->'pricing';
    v_document_completeness:=lws_internal.evaluate_sdf_document_completeness_v1(p_quote_request_id);
    v_document_evidence_hash:=v_document_completeness->>'evidence_sha256';
  else
    if v_request.sdf_package is null then raise exception using errcode='55000',message='SDF_QUOTATION_PREPARATION_NOT_ELIGIBLE'; end if;
    v_package:=v_request.sdf_package;
    v_pricing:=public.get_sdf_package_pricing_authority_v1(v_package);
    v_document_evidence_hash:=null;
  end if;

  v_pricing_hash:=encode(extensions.digest(convert_to(v_pricing::text,'UTF8'),'sha256'),'hex');
  v_fingerprint:=encode(extensions.digest(convert_to(
    case when v_submission.taxonomy_version='sdf_qualification_intake/3.0.0'
      then jsonb_build_object('v',3,'request',p_quote_request_id,'intake',v_intake.intake_id,'taxonomy',v_submission.taxonomy_version,'submission',v_submission.payload_sha256,'completion',v_completion.event_id,'package',v_package,'pricing',v_pricing_hash,'document_evidence',v_document_evidence_hash)
      else jsonb_build_object('v',1,'request',p_quote_request_id,'intake',v_intake.intake_id,'submission',v_submission.payload_sha256,'completion',v_completion.event_id,'package',v_package,'pricing',v_pricing_hash)
    end::text,'UTF8'),'sha256'),'hex');
  select * into v_existing from public.sdf_quotation_preparation_authorities where idempotency_key=p_idempotency_key;
  if found then if v_existing.request_fingerprint<>v_fingerprint then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT'; end if; return jsonb_build_object('authority_id',v_existing.authority_id,'quotation_id',v_existing.quotation_id,'status','QUOTATION_PREPARATION_ELIGIBLE','sdf_package',v_existing.sdf_package,'document_evidence_sha256',rtrim(v_existing.document_evidence_sha256),'replayed',true); end if;
  if v_submission.taxonomy_version='sdf_qualification_intake/3.0.0' and (v_document_completeness->>'is_complete')::boolean is distinct from true then raise exception using errcode='55000',message='SDF_DOCUMENT_COMPLETENESS_REQUIRED'; end if;
  if exists(select 1 from public.sdf_quotations where quote_request_id=p_quote_request_id) or exists(select 1 from public.sdf_quotation_preparation_authorities where quote_request_id=p_quote_request_id) then raise exception using errcode='55000',message='SDF_QUOTATION_PREPARATION_CONFLICT'; end if;
  insert into public.sdf_quotations(quote_request_id) values(p_quote_request_id) returning quotation_id into v_quotation_id;
  insert into public.sdf_quotation_preparation_authorities(quote_request_id,quotation_id,qualification_intake_id,taxonomy_version,submission_sequence,submission_sha256,completion_event_id,sdf_package,pricing_authority_version,pricing_authority_sha256,document_evidence_sha256,actor_operator_id,actor_role,idempotency_key,request_fingerprint) values(p_quote_request_id,v_quotation_id,v_intake.intake_id,v_submission.taxonomy_version,v_submission.submission_sequence,v_submission.payload_sha256,v_completion.event_id,v_package,(v_pricing->>'authority_version')::integer,v_pricing_hash,v_document_evidence_hash,v_operator.operator_id,'owner',p_idempotency_key,v_fingerprint) returning * into v_existing;
  return jsonb_build_object('authority_id',v_existing.authority_id,'quotation_id',v_existing.quotation_id,'status','QUOTATION_PREPARATION_ELIGIBLE','sdf_package',v_existing.sdf_package,'document_evidence_sha256',rtrim(v_existing.document_evidence_sha256),'replayed',false);
end;
$$;

revoke all on function lws_internal.evaluate_sdf_document_completeness_v1(uuid)
from public, anon, authenticated, service_role;

comment on function lws_internal.evaluate_sdf_document_completeness_v1(uuid) is
  'Private deterministic snapshot evaluator for immutable SDF requirements and currently valid same-dossier document evidence. Zero requirements fails closed.';
comment on column public.sdf_quotation_preparation_authorities.document_evidence_sha256 is
  'Canonical DFQ-2B document evidence hash required and fingerprint-bound by new V3 quotation preparation decisions; legacy V1/V2 remains null.';
