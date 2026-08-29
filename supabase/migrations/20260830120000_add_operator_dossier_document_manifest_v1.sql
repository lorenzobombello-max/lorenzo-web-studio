create function lws_internal.assert_operator_dossier_document_reader_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_allowed boolean := false;
begin
  if p_actor_auth_user_id is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select * into v_operator
  from public.commercial_operators
  where auth_user_id = p_actor_auth_user_id;

  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status = 'DISABLED' then raise exception using errcode = '42501', message = 'OPERATOR_DISABLED'; end if;
  if v_operator.status = 'REVOKED' then raise exception using errcode = '42501', message = 'OPERATOR_REVOKED'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;

  if not exists (
    select 1 from public.quote_requests
    where id = p_quote_request_id and record_classification = 'production'
  ) then
    raise exception using errcode = '42501', message = 'DOSSIER_DOCUMENT_READER_REQUIRED';
  end if;

  if v_operator.role in ('owner', 'admin', 'operations_manager') then
    v_allowed := true;
  elsif v_operator.role = 'operator' then
    select true into v_allowed
    from lws_internal.operator_dossier_assignments as assignment
    where assignment.quote_request_id = p_quote_request_id
      and assignment.assignee_operator_id = v_operator.operator_id;
  end if;

  if not coalesce(v_allowed, false) then
    select true into v_allowed
    from public.commercial_operator_project_grants as project_grant
    join public.commercial_projects as project
      on project.project_id = project_grant.project_id
    join public.quote_request_quotation_issuances as issuance
      on issuance.id = project.quotation_issuance_id
    join public.quote_request_quotation_approvals as approval
      on approval.id = issuance.approval_id
    where project_grant.operator_id = v_operator.operator_id
      and project_grant.revoked_at is null
      and approval.quote_request_id = p_quote_request_id;
  end if;

  if not coalesce(v_allowed, false) then
    raise exception using errcode = '42501', message = 'DOSSIER_DOCUMENT_READER_REQUIRED';
  end if;
end;
$$;

create function public.get_operator_dossier_document_manifest_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid
)
returns table (
  document_id uuid,
  source_type text,
  document_type text,
  artifact_type text,
  title text,
  filename text,
  status text,
  created_at timestamptz,
  accepted_at timestamptz,
  source_record_id uuid,
  version text,
  sha256 text,
  quote_request_id uuid,
  customer_id uuid,
  project_id uuid,
  can_open boolean,
  can_download boolean
)
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
begin
  perform lws_internal.assert_operator_dossier_document_reader_v1(
    p_actor_auth_user_id,
    p_quote_request_id
  );

  return query
  with quotation_rows as (
    select
      issuance.id,
      issuance.quotation_number,
      issuance.quotation_version,
      issuance.status as issuance_status,
      issuance.issued_at,
      issuance.created_at,
      rtrim(issuance.docx_sha256) as docx_sha256,
      approval.quote_request_id,
      acceptance.accepted_at,
      project.customer_id,
      project.project_id
    from public.quote_request_quotation_issuances as issuance
    join public.quote_request_quotation_approvals as approval
      on approval.id = issuance.approval_id
    left join public.quote_request_quotation_acceptances as acceptance
      on acceptance.issuance_id = issuance.id
    left join public.commercial_projects as project
      on project.quotation_issuance_id = issuance.id
    where approval.quote_request_id = p_quote_request_id
  ), manifest as (
    select
      quotation.id as document_id,
      'QUOTATION'::text as source_type,
      'QUOTATION'::text as document_type,
      null::text as artifact_type,
      quotation.quotation_number as title,
      null::text as filename,
      case when quotation.accepted_at is not null then 'ACCEPTED' else quotation.issuance_status end as status,
      coalesce(quotation.issued_at, quotation.created_at) as created_at,
      quotation.accepted_at,
      quotation.id as source_record_id,
      quotation.quotation_version::text as version,
      quotation.docx_sha256 as sha256,
      quotation.quote_request_id,
      quotation.customer_id,
      quotation.project_id,
      false as can_open,
      false as can_download
    from quotation_rows as quotation

    union all

    select
      artifact.artifact_id,
      'QUOTATION_ARTIFACT'::text,
      'QUOTATION'::text,
      artifact.artifact_type,
      quotation.quotation_number || ' - ' || artifact.artifact_type,
      quotation.quotation_number || '-v' || quotation.quotation_version::text || '.' || lower(artifact.artifact_type),
      case when quotation.accepted_at is not null then 'ACCEPTED' else quotation.issuance_status end,
      artifact.created_at,
      quotation.accepted_at,
      artifact.artifact_id,
      quotation.quotation_version::text,
      rtrim(artifact.sha256),
      quotation.quote_request_id,
      quotation.customer_id,
      quotation.project_id,
      storage_object.id is not null,
      storage_object.id is not null
    from public.quote_request_quotation_artifacts as artifact
    join quotation_rows as quotation on quotation.id = artifact.issuance_id
    left join storage.objects as storage_object
      on storage_object.bucket_id = artifact.storage_bucket_id
      and storage_object.name = artifact.storage_object_path

    union all

    select
      uploaded_file.uploaded_file_id,
      'CUSTOMER_UPLOAD'::text,
      'CUSTOMER_UPLOAD'::text,
      null::text,
      uploaded_file.original_file_name,
      uploaded_file.original_file_name,
      uploaded_file.status,
      coalesce(uploaded_file.accepted_at, uploaded_file.prepared_at),
      null::timestamptz,
      uploaded_file.uploaded_file_id,
      null::text,
      rtrim(uploaded_file.sha256),
      customer_request.quote_request_id,
      customer_request.customer_id,
      customer_request.project_id,
      storage_object.id is not null,
      storage_object.id is not null
    from public.customer_request_uploaded_files as uploaded_file
    join public.customer_requests as customer_request
      on customer_request.request_id = uploaded_file.customer_request_id
    left join storage.objects as storage_object
      on storage_object.bucket_id = uploaded_file.storage_bucket_id
      and storage_object.name = uploaded_file.storage_object_path
    where customer_request.quote_request_id = p_quote_request_id
      and uploaded_file.status = 'ACCEPTED'
  )
  select manifest.*
  from manifest
  order by manifest.created_at desc, manifest.document_id;
end;
$$;

create function public.authorize_operator_dossier_document_download_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid,
  p_source_type text,
  p_document_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_result jsonb;
begin
  perform lws_internal.assert_operator_dossier_document_reader_v1(
    p_actor_auth_user_id,
    p_quote_request_id
  );

  if p_source_type = 'QUOTATION_ARTIFACT' then
    select jsonb_build_object(
      'state', 'AUTHORIZED',
      'document_id', artifact.artifact_id,
      'source_type', p_source_type,
      'storage_bucket_id', artifact.storage_bucket_id,
      'storage_object_path', artifact.storage_object_path,
      'filename', issuance.quotation_number || '-v' || issuance.quotation_version::text || '.' || lower(artifact.artifact_type),
      'expires_in_seconds', 60
    ) into v_result
    from public.quote_request_quotation_artifacts as artifact
    join public.quote_request_quotation_issuances as issuance
      on issuance.id = artifact.issuance_id
    join public.quote_request_quotation_approvals as approval
      on approval.id = issuance.approval_id
    join storage.objects as storage_object
      on storage_object.bucket_id = artifact.storage_bucket_id
      and storage_object.name = artifact.storage_object_path
    where artifact.artifact_id = p_document_id
      and approval.quote_request_id = p_quote_request_id;
  elsif p_source_type = 'CUSTOMER_UPLOAD' then
    select jsonb_build_object(
      'state', 'AUTHORIZED',
      'document_id', uploaded_file.uploaded_file_id,
      'source_type', p_source_type,
      'storage_bucket_id', uploaded_file.storage_bucket_id,
      'storage_object_path', uploaded_file.storage_object_path,
      'filename', uploaded_file.original_file_name,
      'expires_in_seconds', 60
    ) into v_result
    from public.customer_request_uploaded_files as uploaded_file
    join public.customer_requests as customer_request
      on customer_request.request_id = uploaded_file.customer_request_id
    join storage.objects as storage_object
      on storage_object.bucket_id = uploaded_file.storage_bucket_id
      and storage_object.name = uploaded_file.storage_object_path
    where uploaded_file.uploaded_file_id = p_document_id
      and uploaded_file.status = 'ACCEPTED'
      and customer_request.quote_request_id = p_quote_request_id;
  elsif p_source_type = 'QUOTATION' then
    raise exception using errcode = '42501', message = 'DOSSIER_DOCUMENT_NOT_DOWNLOADABLE';
  else
    raise exception using errcode = '42501', message = 'DOSSIER_DOCUMENT_SOURCE_INVALID';
  end if;

  if v_result is null then
    raise exception using errcode = '42501', message = 'DOSSIER_DOCUMENT_ACCESS_DENIED';
  end if;

  return v_result;
end;
$$;

revoke all on function lws_internal.assert_operator_dossier_document_reader_v1(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.get_operator_dossier_document_manifest_v1(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.authorize_operator_dossier_document_download_v1(uuid, uuid, text, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.get_operator_dossier_document_manifest_v1(uuid, uuid)
to service_role;
grant execute on function public.authorize_operator_dossier_document_download_v1(uuid, uuid, text, uuid)
to service_role;

comment on function public.get_operator_dossier_document_manifest_v1(uuid, uuid) is
  'Read-only, server-authorized dossier document projection. It exposes no private Storage locator and creates no document authority.';
comment on function public.authorize_operator_dossier_document_download_v1(uuid, uuid, text, uuid) is
  'Service-only exact dossier/document binding check that releases a private locator solely to the signed-download Edge boundary.';