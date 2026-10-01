create or replace function public.register_website_delivery_document_access_receipt_v1(
  p_view_derivative_id uuid,
  p_viewer_kind text,
  p_operator_auth_user_id uuid,
  p_preview_session_id uuid,
  p_served_pdf_sha256 text,
  p_served_pdf_bytes bigint,
  p_served_by text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_view public.website_delivery_document_view_derivatives%rowtype;
  v_receipt public.website_delivery_document_access_receipts%rowtype;
begin
  if p_view_derivative_id is null
     or p_viewer_kind not in ('OPERATOR', 'CUSTOMER')
     or p_served_pdf_sha256 is null or p_served_pdf_sha256 !~ '^[0-9a-f]{64}$'
     or p_served_pdf_bytes is null or p_served_pdf_bytes <= 0
     or nullif(btrim(p_served_by), '') is null
     or (p_viewer_kind = 'OPERATOR' and (p_operator_auth_user_id is null or p_preview_session_id is not null))
     or (p_viewer_kind = 'CUSTOMER' and (p_operator_auth_user_id is not null or p_preview_session_id is null)) then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_VIEW_RECEIPT_INPUT_INVALID';
  end if;
  select * into v_view
  from public.website_delivery_document_view_derivatives
  where view_derivative_id = p_view_derivative_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_VIEW_NOT_FOUND';
  end if;

  if v_view.pdf_sha256 <> p_served_pdf_sha256 or v_view.pdf_bytes <> p_served_pdf_bytes then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_VIEW_RECEIPT_MISMATCH';
  end if;

  perform 1
  from public.preview_versions preview
  where preview.project_id = v_view.project_id
    and preview.preview_version_id = v_view.preview_version_id
    and preview.status = 'CURRENT'
  for share;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_VIEW_NOT_CURRENT';
  end if;
  if p_viewer_kind = 'OPERATOR' and not exists (
    select 1
    from public.commercial_operators operator
    where operator.auth_user_id = p_operator_auth_user_id
      and operator.status = 'ACTIVE'
      and (
        operator.role in ('owner', 'admin')
        or exists (
          select 1 from public.commercial_operator_project_grants project_grant
          where project_grant.operator_id = operator.operator_id
            and project_grant.project_id = v_view.project_id
            and project_grant.revoked_at is null
        )
      )
  ) then
    raise exception using errcode = '42501', message = 'OPERATOR_NOT_AUTHORIZED';
  end if;
  if p_viewer_kind = 'CUSTOMER' and not exists (
    select 1
    from public.preview_sessions session
    join public.preview_access access
      on access.preview_access_id = session.preview_access_id
     and access.project_id = session.project_id
    where session.preview_session_id = p_preview_session_id
      and session.project_id = v_view.project_id
      and session.revoked_at is null
      and session.expires_at > clock_timestamp()
      and access.preview_version_id = v_view.preview_version_id
      and access.status = 'ACTIVE'
      and access.revoked_at is null
      and access.expires_at > clock_timestamp()
  ) then
    raise exception using errcode = '42501', message = 'ACCESS_DENIED';
  end if;

  insert into public.website_delivery_document_access_receipts(
    view_derivative_id, artifact_id, project_id, preview_version_id,
    document_version, source_docx_sha256, served_pdf_sha256, served_pdf_bytes,
    viewer_kind, operator_auth_user_id, preview_session_id, served_by
  ) values (
    v_view.view_derivative_id, v_view.artifact_id, v_view.project_id,
    v_view.preview_version_id, v_view.document_version, v_view.source_docx_sha256,
    v_view.pdf_sha256, v_view.pdf_bytes, p_viewer_kind,
    p_operator_auth_user_id, p_preview_session_id, btrim(p_served_by)
  ) returning * into v_receipt;

  return jsonb_build_object(
    'access_receipt_id', v_receipt.access_receipt_id,
    'view_derivative_id', v_receipt.view_derivative_id,
    'project_id', v_receipt.project_id,
    'preview_version_id', v_receipt.preview_version_id,
    'document_version', v_receipt.document_version,
    'source_docx_sha256', rtrim(v_receipt.source_docx_sha256),
    'served_pdf_sha256', rtrim(v_receipt.served_pdf_sha256),
    'served_pdf_bytes', v_receipt.served_pdf_bytes,
    'viewer_kind', v_receipt.viewer_kind,
    'served_at', v_receipt.served_at
  );
end;
$$;

revoke all on function public.register_website_delivery_document_access_receipt_v1(uuid,text,uuid,uuid,text,bigint,text) from public, anon, authenticated, service_role;
grant execute on function public.register_website_delivery_document_access_receipt_v1(uuid,text,uuid,uuid,text,bigint,text) to service_role;