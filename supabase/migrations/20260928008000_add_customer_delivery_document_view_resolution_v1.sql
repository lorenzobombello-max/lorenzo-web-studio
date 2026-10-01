create function public.resolve_customer_website_delivery_document_view_v1(
  p_session_digest char(64),
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_session public.preview_sessions%rowtype;
  v_view public.website_delivery_document_view_derivatives%rowtype;
begin
  if p_project_id is null or btrim(p_session_digest::text) !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '42501', message = 'ACCESS_DENIED';
  end if;

  select session.* into v_session
  from public.preview_sessions session
  join public.preview_access access
    on access.preview_access_id = session.preview_access_id
   and access.project_id = session.project_id
  join public.preview_versions preview
    on preview.preview_version_id = access.preview_version_id
   and preview.project_id = access.project_id
  where session.session_digest = p_session_digest
    and session.project_id = p_project_id
    and session.revoked_at is null
    and session.expires_at > clock_timestamp()
    and access.status = 'ACTIVE'
    and access.revoked_at is null
    and access.expires_at > clock_timestamp()
    and preview.status = 'CURRENT';
  if not found then
    raise exception using errcode = '42501', message = 'ACCESS_DENIED';
  end if;

  select derivative.* into v_view
  from public.website_delivery_document_view_derivatives derivative
  join public.preview_access access
    on access.preview_access_id = v_session.preview_access_id
   and access.project_id = derivative.project_id
   and access.preview_version_id = derivative.preview_version_id
  where derivative.project_id = p_project_id
  order by derivative.document_version desc
  limit 1;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_VIEW_NOT_FOUND';
  end if;

  return jsonb_build_object(
    'preview_session_id', v_session.preview_session_id,
    'view_derivative_id', v_view.view_derivative_id,
    'artifact_id', v_view.artifact_id,
    'project_id', v_view.project_id,
    'preview_version_id', v_view.preview_version_id,
    'document_version', v_view.document_version,
    'source_docx_sha256', rtrim(v_view.source_docx_sha256),
    'storage_bucket_id', v_view.storage_bucket_id,
    'storage_object_path', v_view.storage_object_path,
    'content_type', v_view.content_type,
    'pdf_sha256', rtrim(v_view.pdf_sha256),
    'pdf_bytes', v_view.pdf_bytes
  );
end;
$$;

revoke all on function public.resolve_customer_website_delivery_document_view_v1(char,uuid)
from public, anon, authenticated, service_role;
grant execute on function public.resolve_customer_website_delivery_document_view_v1(char,uuid)
to service_role;

comment on function public.resolve_customer_website_delivery_document_view_v1(char,uuid) is
  'Resolves one exact private delivery-document PDF only for an active customer session bound to the CURRENT preview version.';