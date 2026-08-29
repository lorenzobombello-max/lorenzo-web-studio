create function public.finalize_supplier_document_upload_object_v1(
  p_storage_object_path text,
  p_sha256 text,
  p_mime_type text,
  p_byte_count bigint
)
returns boolean
language plpgsql
security definer
set search_path = public, storage, auth, pg_catalog
as $$
declare
  v_extension text;
  v_expected_path text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'SUPPLIER_DOCUMENT_UPLOAD_SERVICE_REQUIRED';
  end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_SUPPLIER_DOCUMENT_SHA256';
  end if;
  if p_mime_type not in ('application/pdf', 'image/png', 'image/jpeg') then
    raise exception using errcode = '22023', message = 'INVALID_SUPPLIER_DOCUMENT_MIME_TYPE';
  end if;
  if p_byte_count is null or p_byte_count not between 1 and 10485760 then
    raise exception using errcode = '22023', message = 'INVALID_SUPPLIER_DOCUMENT_BYTE_COUNT';
  end if;

  v_extension := case p_mime_type
    when 'application/pdf' then 'pdf'
    when 'image/png' then 'png'
    when 'image/jpeg' then 'jpg'
  end;
  v_expected_path := 'documents/' || p_sha256 || '.' || v_extension;
  if p_storage_object_path is distinct from v_expected_path then
    raise exception using errcode = '22023', message = 'INVALID_SUPPLIER_DOCUMENT_STORAGE_PATH';
  end if;

  update storage.objects as object
  set metadata = jsonb_set(object.metadata, '{sha256}', to_jsonb(p_sha256), true)
  where object.bucket_id = 'supplier-documents'
    and object.name = v_expected_path
    and coalesce(object.metadata->>'mimetype', '') = p_mime_type
    and coalesce(object.metadata->>'size', '') ~ '^[0-9]+$'
    and (object.metadata->>'size')::bigint = p_byte_count
    and (
      object.metadata->>'sha256' is null
      or object.metadata->>'sha256' = p_sha256
    );

  if not found then
    raise exception using errcode = 'P0001', message = 'SUPPLIER_DOCUMENT_OBJECT_METADATA_MISMATCH';
  end if;
  return true;
end;
$$;

revoke all on function public.finalize_supplier_document_upload_object_v1(text, text, text, bigint)
from public, anon, authenticated, service_role;

grant execute on function public.finalize_supplier_document_upload_object_v1(text, text, text, bigint)
to service_role;

comment on function public.finalize_supplier_document_upload_object_v1(text, text, text, bigint) is
  'Service-only finalizer for trusted supplier-document Storage metadata after server-side binary inspection. It creates no supplier-document or expense-link record.';