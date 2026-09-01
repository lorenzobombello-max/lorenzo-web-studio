create function public.get_sdf_quotation_delivery_transport_context_v1(
  p_business_draft_id uuid,
  p_approval_id uuid,
  p_expected_approval_version integer,
  p_expected_approval_sha256 text,
  p_issuance_id uuid,
  p_artifact_id uuid,
  p_expected_artifact_sha256 text,
  p_expected_artifact_bytes bigint
)
returns table (
  issuance_id uuid,
  capability_id uuid,
  orchestration_id uuid,
  email_job_id uuid,
  recipient_email text,
  content_version text,
  client_name text,
  quotation_number text,
  quotation_version integer,
  project_title text,
  valid_until date,
  stored_token_digest text,
  encrypted_token text,
  job_status text,
  attempt_count integer,
  sent_at timestamptz,
  artifact_id uuid,
  artifact_sha256 text,
  artifact_bytes bigint
)
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, storage, extensions, pg_catalog
as $$
declare
  v_actor text;
  v_issuance public.quote_request_quotation_issuances%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_artifact public.quote_request_quotation_artifacts%rowtype;
  v_capability public.quote_request_quotation_acceptance_capabilities%rowtype;
  v_orchestration public.quote_request_quotation_email_orchestrations%rowtype;
  v_job public.quote_request_email_jobs%rowtype;
  v_storage_metadata jsonb;
  v_expected_path text;
  v_recipient_email text;
  v_authority_sha256 text;
  v_delivery_key uuid;
begin
  if p_business_draft_id is null or p_approval_id is null
     or p_expected_approval_version is null or p_expected_approval_version < 1
     or p_expected_approval_sha256 is null
     or p_expected_approval_sha256 !~ '^[0-9a-f]{64}$'
     or p_issuance_id is null or p_artifact_id is null
     or p_expected_artifact_sha256 is null
     or p_expected_artifact_sha256 !~ '^[0-9a-f]{64}$'
     or p_expected_artifact_bytes is null or p_expected_artifact_bytes <= 0 then
    raise exception using errcode = '22023', message = 'SDF_DELIVERY_INPUT_INVALID';
  end if;

  v_actor := lws_internal.assert_sdf_approval_issuance_authority_v1(
    p_business_draft_id,
    p_approval_id,
    p_expected_approval_version,
    p_expected_approval_sha256
  );

  select * into v_issuance
  from public.quote_request_quotation_issuances
  where id = p_issuance_id;
  if not found or v_issuance.approval_id is distinct from p_approval_id
     or v_issuance.status <> 'ISSUED' then
    raise exception using errcode = 'P0001',
      message = 'SDF_DELIVERY_TRANSPORT_NOT_AVAILABLE';
  end if;
  if not public.is_quotation_within_validity_v1(v_issuance.id)
     or exists (
       select 1 from public.quote_request_quotation_acceptances as acceptance
       where acceptance.issuance_id = v_issuance.id
     ) then
    raise exception using errcode = 'P0001',
      message = 'SDF_DELIVERY_TRANSPORT_NOT_AVAILABLE';
  end if;

  select * into strict v_approval
  from public.quote_request_quotation_approvals
  where id = p_approval_id;

  select * into v_artifact
  from public.quote_request_quotation_artifacts
  where quote_request_quotation_artifacts.artifact_id = p_artifact_id;
  if not found or v_artifact.issuance_id is distinct from p_issuance_id
     or v_artifact.artifact_type <> 'DOCX'
     or rtrim(v_artifact.sha256) is distinct from p_expected_artifact_sha256
     or rtrim(v_issuance.docx_sha256) is distinct from p_expected_artifact_sha256
     or v_artifact.byte_count is distinct from p_expected_artifact_bytes
     or v_issuance.docx_bytes is distinct from p_expected_artifact_bytes then
    raise exception using errcode = 'P0001',
      message = 'SDF_DELIVERY_TRANSPORT_NOT_AVAILABLE';
  end if;
  v_expected_path := 'issuances/' || p_issuance_id::text || '/docx/' ||
    p_expected_artifact_sha256 || '.docx';
  if v_artifact.storage_bucket_id <> 'quotation-artifacts'
     or v_artifact.storage_object_path <> v_expected_path
     or v_artifact.content_type <>
       'application/vnd.openxmlformats-officedocument.wordprocessingml.document' then
    raise exception using errcode = 'P0001',
      message = 'SDF_DELIVERY_TRANSPORT_NOT_AVAILABLE';
  end if;
  select objects.metadata into v_storage_metadata
  from storage.objects as objects
  where objects.bucket_id = v_artifact.storage_bucket_id
    and objects.name = v_artifact.storage_object_path;
  if not found
     or coalesce(v_storage_metadata->>'mimetype', '') <> v_artifact.content_type
     or coalesce(v_storage_metadata->>'size', '') !~ '^[0-9]+$'
     or (v_storage_metadata->>'size')::bigint <> v_artifact.byte_count then
    raise exception using errcode = 'P0001',
      message = 'SDF_DELIVERY_TRANSPORT_NOT_AVAILABLE';
  end if;

  v_authority_sha256 := encode(extensions.digest(convert_to(jsonb_build_object(
    'approvalId', p_approval_id,
    'approvalSha256', p_expected_approval_sha256,
    'approvalVersion', p_expected_approval_version,
    'artifactBytes', p_expected_artifact_bytes,
    'artifactId', p_artifact_id,
    'artifactSha256', p_expected_artifact_sha256,
    'businessDraftId', p_business_draft_id,
    'issuanceId', p_issuance_id
  )::text, 'UTF8'), 'sha256'), 'hex');
  v_delivery_key := lws_internal.sdf_delivery_operation_id_v1(
    v_authority_sha256, 'DELIVERY'
  );

  select * into v_orchestration
  from public.quote_request_quotation_email_orchestrations
  where idempotency_key = v_delivery_key;
  if not found or v_orchestration.email_type <> 'QUOTATION_DELIVERY'
     or v_orchestration.issuance_id is distinct from p_issuance_id
     or v_orchestration.content_version <> 'QUOTATION_DELIVERY_NL_BE_v1'
     or v_orchestration.capability_id is null then
    raise exception using errcode = 'P0001',
      message = 'SDF_DELIVERY_TRANSPORT_NOT_AVAILABLE';
  end if;

  select * into v_capability
  from public.quote_request_quotation_acceptance_capabilities
  where id = v_orchestration.capability_id;
  if not found or v_capability.issuance_id is distinct from p_issuance_id
     or v_capability.status <> 'ACTIVE'
     or v_capability.expires_at <= clock_timestamp() then
    raise exception using errcode = 'P0001',
      message = 'SDF_DELIVERY_TRANSPORT_NOT_AVAILABLE';
  end if;

  select * into v_job
  from public.quote_request_email_jobs
  where id = v_orchestration.email_job_id;
  if not found or v_job.kind <> 'quotation_delivery' then
    raise exception using errcode = 'P0001',
      message = 'SDF_DELIVERY_TRANSPORT_NOT_AVAILABLE';
  end if;
  if v_job.status = 'sent' then
    null;
  elsif v_job.status in ('pending', 'retry_wait') then
    if v_job.next_attempt_at > clock_timestamp()
       or v_job.attempt_count >= v_job.max_attempts then
      raise exception using errcode = 'P0001',
        message = 'SDF_DELIVERY_TRANSPORT_NOT_AVAILABLE';
    end if;
  elsif v_job.status = 'processing' then
    if v_job.locked_at is null
       or v_job.locked_at >= clock_timestamp() - interval '5 minutes'
       or v_job.stale_recovery_count >= v_job.max_stale_recoveries then
      raise exception using errcode = 'P0001',
        message = 'SDF_DELIVERY_TRANSPORT_NOT_AVAILABLE';
    end if;
  else
    raise exception using errcode = 'P0001',
      message = 'SDF_DELIVERY_TRANSPORT_NOT_AVAILABLE';
  end if;
  if v_job.status <> 'sent' and v_job.encrypted_payload is null then
    raise exception using errcode = 'P0001',
      message = 'SDF_DELIVERY_PAYLOAD_UNAVAILABLE';
  end if;

  v_recipient_email := lower(
    v_approval.approved_payload->'customer_identity'->>'email'
  );
  if v_recipient_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     or v_orchestration.recipient_email is distinct from v_recipient_email then
    raise exception using errcode = 'P0001',
      message = 'SDF_DELIVERY_TRANSPORT_NOT_AVAILABLE';
  end if;

  return query select
    v_issuance.id,
    v_capability.id,
    v_orchestration.id,
    v_job.id,
    v_orchestration.recipient_email,
    v_orchestration.content_version,
    v_approval.approved_payload->'customer_identity'->>'legal_name',
    v_issuance.quotation_number,
    v_issuance.quotation_version,
    v_approval.approved_payload->'project_scope'->>'project_title',
    (v_approval.approved_payload->'validity'->>'valid_until')::date,
    rtrim(v_capability.token_digest),
    v_job.encrypted_payload,
    v_job.status::text,
    v_job.attempt_count,
    v_job.sent_at,
    v_artifact.artifact_id,
    rtrim(v_artifact.sha256),
    v_artifact.byte_count;
end;
$$;

revoke all on function public.get_sdf_quotation_delivery_transport_context_v1(
  uuid, uuid, integer, text, uuid, uuid, text, bigint
) from public, anon, authenticated, service_role;
grant execute on function public.get_sdf_quotation_delivery_transport_context_v1(
  uuid, uuid, integer, text, uuid, uuid, text, bigint
) to authenticated;

comment on function public.get_sdf_quotation_delivery_transport_context_v1(
  uuid, uuid, integer, text, uuid, uuid, text, bigint
) is
  'Owner-only read bridge for an existing prepared SDF quotation delivery. Validates frozen lineage, exact archived DOCX, ACTIVE capability, immutable orchestration, and retry-eligible existing job without claim or transport.';