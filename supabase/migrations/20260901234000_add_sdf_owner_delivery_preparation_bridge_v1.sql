create function lws_internal.sdf_delivery_operation_id_v1(
  p_authority_sha256 text,
  p_operation text
)
returns uuid
language plpgsql
immutable
set search_path = extensions, pg_catalog
as $$
declare
  v_hex text;
begin
  if p_authority_sha256 is null or p_authority_sha256 !~ '^[0-9a-f]{64}$'
     or p_operation not in ('CAPABILITY', 'DELIVERY') then
    raise exception using errcode = '22023', message = 'SDF_DELIVERY_OPERATION_ID_INVALID';
  end if;
  v_hex := encode(
    extensions.digest(
      convert_to('sdf-delivery:v1:' || p_authority_sha256 || ':' || p_operation, 'UTF8'),
      'sha256'
    ),
    'hex'
  );
  return (
    substr(v_hex, 1, 8) || '-' || substr(v_hex, 9, 4) || '-5' ||
    substr(v_hex, 14, 3) || '-8' || substr(v_hex, 18, 3) || '-' ||
    substr(v_hex, 21, 12)
  )::uuid;
end;
$$;

revoke all on function lws_internal.sdf_delivery_operation_id_v1(text, text)
from public, anon, authenticated, service_role;

create function public.prepare_sdf_issued_quotation_delivery_v1(
  p_business_draft_id uuid,
  p_approval_id uuid,
  p_expected_approval_version integer,
  p_expected_approval_sha256 text,
  p_issuance_id uuid,
  p_artifact_id uuid,
  p_expected_artifact_sha256 text,
  p_expected_artifact_bytes bigint,
  p_token_digest text,
  p_encrypted_token text,
  p_requested_expires_at timestamptz
)
returns table (
  orchestration_id uuid,
  email_job_id uuid,
  recipient_email text,
  client_name text,
  quotation_number text,
  quotation_version integer,
  project_title text,
  valid_until date,
  capability_id uuid,
  capability_expires_at timestamptz,
  stored_token_digest text,
  encrypted_token text,
  job_status text,
  artifact_id uuid,
  artifact_sha256 text,
  artifact_bytes bigint,
  capability_was_created boolean,
  delivery_was_created boolean
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
  v_capability_operation public.quote_request_quotation_acceptance_capability_operations%rowtype;
  v_orchestration public.quote_request_quotation_email_orchestrations%rowtype;
  v_job public.quote_request_email_jobs%rowtype;
  v_storage_metadata jsonb;
  v_deadline timestamptz;
  v_expires_at timestamptz;
  v_expected_path text;
  v_recipient_email text;
  v_authority_sha256 text;
  v_capability_fingerprint text;
  v_delivery_fingerprint text;
  v_capability_key uuid;
  v_delivery_key uuid;
begin
  if p_business_draft_id is null or p_approval_id is null
     or p_expected_approval_version is null or p_expected_approval_version < 1
     or p_expected_approval_sha256 is null
     or p_expected_approval_sha256 !~ '^[0-9a-f]{64}$'
     or p_issuance_id is null or p_artifact_id is null
     or p_expected_artifact_sha256 is null
     or p_expected_artifact_sha256 !~ '^[0-9a-f]{64}$'
     or p_expected_artifact_bytes is null or p_expected_artifact_bytes <= 0
     or p_token_digest is null or p_token_digest !~ '^[0-9a-f]{64}$'
     or p_encrypted_token is null
     or p_encrypted_token !~ '^v1\.[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{40,}$' then
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
  where id = p_issuance_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_NOT_FOUND';
  end if;
  if v_issuance.approval_id is distinct from p_approval_id then
    raise exception using errcode = '42501', message = 'SDF_DELIVERY_CROSS_DOSSIER';
  end if;
  if v_issuance.status <> 'ISSUED' then
    raise exception using errcode = 'P0001', message = 'SDF_DELIVERY_NOT_AVAILABLE';
  end if;
  if not public.is_quotation_within_validity_v1(v_issuance.id)
     or exists (
       select 1 from public.quote_request_quotation_acceptances
       where issuance_id = v_issuance.id
     ) then
    raise exception using errcode = 'P0001', message = 'SDF_DELIVERY_NOT_AVAILABLE';
  end if;

  select * into strict v_approval
  from public.quote_request_quotation_approvals
  where id = p_approval_id;

  select * into v_artifact
  from public.quote_request_quotation_artifacts
  where quote_request_quotation_artifacts.artifact_id = p_artifact_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'SDF_DELIVERY_ARTIFACT_NOT_FOUND';
  end if;
  if v_artifact.issuance_id is distinct from p_issuance_id then
    raise exception using errcode = '42501', message = 'SDF_DELIVERY_ARTIFACT_CROSS_ISSUANCE';
  end if;
  if v_artifact.artifact_type <> 'DOCX' then
    raise exception using errcode = 'P0001', message = 'SDF_DELIVERY_ARTIFACT_TYPE_INVALID';
  end if;
  if rtrim(v_artifact.sha256) is distinct from p_expected_artifact_sha256
     or rtrim(v_issuance.docx_sha256) is distinct from p_expected_artifact_sha256 then
    raise exception using errcode = 'P0001', message = 'SDF_DELIVERY_ARTIFACT_HASH_MISMATCH';
  end if;
  if v_artifact.byte_count is distinct from p_expected_artifact_bytes
     or v_issuance.docx_bytes is distinct from p_expected_artifact_bytes then
    raise exception using errcode = 'P0001', message = 'SDF_DELIVERY_ARTIFACT_BYTES_MISMATCH';
  end if;
  v_expected_path := 'issuances/' || p_issuance_id::text || '/docx/' ||
    p_expected_artifact_sha256 || '.docx';
  if v_artifact.storage_bucket_id <> 'quotation-artifacts'
     or v_artifact.storage_object_path <> v_expected_path
     or v_artifact.content_type <>
       'application/vnd.openxmlformats-officedocument.wordprocessingml.document' then
    raise exception using errcode = 'P0001', message = 'SDF_DELIVERY_ARTIFACT_METADATA_MISMATCH';
  end if;
  select objects.metadata into v_storage_metadata
  from storage.objects as objects
  where objects.bucket_id = v_artifact.storage_bucket_id
    and objects.name = v_artifact.storage_object_path;
  if not found then
    raise exception using errcode = 'P0001', message = 'SDF_DELIVERY_ARTIFACT_OBJECT_NOT_FOUND';
  end if;
  if coalesce(v_storage_metadata->>'mimetype', '') <> v_artifact.content_type
     or coalesce(v_storage_metadata->>'size', '') !~ '^[0-9]+$'
     or (v_storage_metadata->>'size')::bigint <> v_artifact.byte_count then
    raise exception using errcode = 'P0001', message = 'SDF_DELIVERY_ARTIFACT_METADATA_MISMATCH';
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
  v_capability_key := lws_internal.sdf_delivery_operation_id_v1(
    v_authority_sha256, 'CAPABILITY'
  );
  v_delivery_key := lws_internal.sdf_delivery_operation_id_v1(
    v_authority_sha256, 'DELIVERY'
  );

  select * into v_orchestration
  from public.quote_request_quotation_email_orchestrations
  where idempotency_key = v_delivery_key;
  if found then
    if v_orchestration.email_type <> 'QUOTATION_DELIVERY'
       or v_orchestration.issuance_id <> p_issuance_id then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    select * into strict v_capability
    from public.quote_request_quotation_acceptance_capabilities
    where id = v_orchestration.capability_id;
    select * into v_capability_operation
    from public.quote_request_quotation_acceptance_capability_operations
    where idempotency_key = v_capability_key;
    if not found or v_capability_operation.operation_type <> 'CREATE'
       or v_capability_operation.capability_id <> v_capability.id then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    select * into strict v_job
    from public.quote_request_email_jobs
    where id = v_orchestration.email_job_id;
    if v_job.status <> 'sent' and v_job.encrypted_payload is null then
      raise exception using errcode = 'P0001', message = 'DELIVERY_PAYLOAD_UNAVAILABLE';
    end if;
    return query select v_orchestration.id, v_job.id,
      v_orchestration.recipient_email,
      v_approval.approved_payload->'customer_identity'->>'legal_name',
      v_issuance.quotation_number, v_issuance.quotation_version,
      v_approval.approved_payload->'project_scope'->>'project_title',
      (v_approval.approved_payload->'validity'->>'valid_until')::date,
      v_capability.id, v_capability.expires_at,
      rtrim(v_capability.token_digest), v_job.encrypted_payload,
      v_job.status::text, v_artifact.artifact_id, rtrim(v_artifact.sha256),
      v_artifact.byte_count, false, false;
    return;
  end if;

  select acceptance_deadline_at into v_deadline
  from public.quotation_issuance_acceptance_deadline_v1(p_issuance_id);
  if v_deadline is null or clock_timestamp() >= v_deadline then
    raise exception using errcode = 'P0001', message = 'CAPABILITY_NOT_AVAILABLE';
  end if;
  v_expires_at := least(coalesce(p_requested_expires_at, v_deadline), v_deadline);
  if v_expires_at <= clock_timestamp() then
    raise exception using errcode = '22023', message = 'CAPABILITY_EXPIRY_INVALID';
  end if;
  v_capability_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'expiresAt', v_expires_at,
    'issuanceId', p_issuance_id,
    'tokenDigest', p_token_digest
  )::text, 'UTF8'), 'sha256'), 'hex');

  select * into v_capability_operation
  from public.quote_request_quotation_acceptance_capability_operations
  where idempotency_key = v_capability_key;
  if found then
    if v_capability_operation.operation_type <> 'CREATE'
       or v_capability_operation.request_fingerprint <> v_capability_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    select * into strict v_capability
    from public.quote_request_quotation_acceptance_capabilities
    where id = v_capability_operation.capability_id;
  else
    if exists (
      select 1 from public.quote_request_quotation_acceptance_capabilities
      where issuance_id = p_issuance_id and status = 'ACTIVE'
    ) then
      raise exception using errcode = 'P0001', message = 'ACTIVE_CAPABILITY_EXISTS';
    end if;
    begin
      insert into public.quote_request_quotation_acceptance_capabilities(
        issuance_id, token_digest, capability_version, status, expires_at, created_by
      ) values (
        p_issuance_id, p_token_digest, 1, 'ACTIVE', v_expires_at, v_actor
      ) returning * into v_capability;
    exception when unique_violation then
      raise exception using errcode = 'P0001', message = 'CAPABILITY_CONFLICT';
    end;
    insert into public.quote_request_quotation_acceptance_capability_operations(
      idempotency_key, operation_type, request_fingerprint, capability_id
    ) values (
      v_capability_key, 'CREATE', v_capability_fingerprint, v_capability.id
    );
    insert into public.quote_request_quotation_acceptance_capability_events(
      capability_id, issuance_id, event_type, actor, event_at, evidence
    ) values (
      v_capability.id, p_issuance_id, 'CREATED', v_actor, clock_timestamp(),
      jsonb_build_object('expiresAt', v_expires_at, 'capabilityVersion', 1)
    );
  end if;

  v_recipient_email := v_approval.approved_payload->'customer_identity'->>'email';
  if v_recipient_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception using errcode = 'P0001', message = 'RECIPIENT_INVALID';
  end if;
  v_recipient_email := lower(v_recipient_email);
  v_delivery_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'capabilityId', v_capability.id,
    'contentVersion', 'QUOTATION_DELIVERY_NL_BE_v1',
    'issuanceId', p_issuance_id,
    'recipient', v_recipient_email
  )::text, 'UTF8'), 'sha256'), 'hex');

  insert into public.quote_request_email_jobs(quote_request_id, kind)
  values (null, 'quotation_delivery')
  returning * into v_job;
  update public.quote_request_email_jobs
  set encrypted_payload = p_encrypted_token
  where id = v_job.id;
  select * into strict v_job
  from public.quote_request_email_jobs
  where id = v_job.id;

  insert into public.quote_request_quotation_email_orchestrations(
    email_job_id, email_type, issuance_id, capability_id, recipient_email,
    content_version, request_fingerprint, idempotency_key, created_by
  ) values (
    v_job.id, 'QUOTATION_DELIVERY', p_issuance_id, v_capability.id,
    v_recipient_email, 'QUOTATION_DELIVERY_NL_BE_v1',
    v_delivery_fingerprint, v_delivery_key, v_actor
  ) returning * into v_orchestration;

  return query select v_orchestration.id, v_job.id,
    v_orchestration.recipient_email,
    v_approval.approved_payload->'customer_identity'->>'legal_name',
    v_issuance.quotation_number, v_issuance.quotation_version,
    v_approval.approved_payload->'project_scope'->>'project_title',
    (v_approval.approved_payload->'validity'->>'valid_until')::date,
    v_capability.id, v_capability.expires_at,
    rtrim(v_capability.token_digest), v_job.encrypted_payload,
    v_job.status::text, v_artifact.artifact_id, rtrim(v_artifact.sha256),
    v_artifact.byte_count, true, true;
end;
$$;

revoke all on function public.prepare_sdf_issued_quotation_delivery_v1(
  uuid, uuid, integer, text, uuid, uuid, text, bigint, text, text, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.prepare_sdf_issued_quotation_delivery_v1(
  uuid, uuid, integer, text, uuid, uuid, text, bigint, text, text, timestamptz
) to authenticated;

comment on function public.prepare_sdf_issued_quotation_delivery_v1(
  uuid, uuid, integer, text, uuid, uuid, text, bigint, text, text, timestamptz
) is
  'Owner-only SDF delivery preparation. Validates frozen lineage and the exact archived DOCX, then atomically prepares one acceptance capability and pending quotation delivery job without transport.';