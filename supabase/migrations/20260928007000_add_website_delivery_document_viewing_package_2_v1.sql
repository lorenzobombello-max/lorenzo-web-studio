insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'website-delivery-document-views',
  'website-delivery-document-views',
  false,
  10485760,
  array['application/pdf']::text[]
);

alter table public.website_delivery_document_artifacts
add constraint website_delivery_artifact_view_binding_unique unique(
  artifact_id, project_id, preview_version_id, document_version, docx_sha256
);

create table public.website_delivery_document_view_derivatives (
  view_derivative_id uuid primary key default gen_random_uuid(),
  artifact_id uuid not null unique,
  project_id uuid not null,
  preview_version_id uuid not null,
  document_version integer not null check (document_version > 0),
  source_docx_sha256 char(64) not null check (source_docx_sha256 ~ '^[0-9a-f]{64}$'),
  storage_bucket_id text not null check (storage_bucket_id = 'website-delivery-document-views'),
  storage_object_path text not null,
  content_type text not null check (content_type = 'application/pdf'),
  pdf_sha256 char(64) not null check (pdf_sha256 ~ '^[0-9a-f]{64}$'),
  pdf_bytes bigint not null check (pdf_bytes > 0 and pdf_bytes <= 10485760),
  registration_idempotency_key uuid not null unique,
  created_by text not null check (nullif(btrim(created_by), '') is not null),
  created_at timestamptz not null default clock_timestamp(),
  constraint website_delivery_view_source_binding foreign key(
    artifact_id, project_id, preview_version_id, document_version, source_docx_sha256
  ) references public.website_delivery_document_artifacts(
    artifact_id, project_id, preview_version_id, document_version, docx_sha256
  ),
  constraint website_delivery_view_storage_object_unique unique(storage_bucket_id, storage_object_path),
  constraint website_delivery_view_receipt_binding_unique unique(
    view_derivative_id, artifact_id, project_id, preview_version_id,
    document_version, source_docx_sha256, pdf_sha256, pdf_bytes
  ),
  constraint website_delivery_view_path_coherent check (
    storage_object_path = 'projects/' || project_id::text || '/versions/' || document_version::text
      || '/views/' || rtrim(source_docx_sha256) || '/' || rtrim(pdf_sha256) || '.pdf'
  )
);

create table public.website_delivery_document_access_receipts (
  access_receipt_id uuid primary key default gen_random_uuid(),
  view_derivative_id uuid not null,
  artifact_id uuid not null,
  project_id uuid not null,
  preview_version_id uuid not null,
  document_version integer not null check (document_version > 0),
  source_docx_sha256 char(64) not null check (source_docx_sha256 ~ '^[0-9a-f]{64}$'),
  served_pdf_sha256 char(64) not null check (served_pdf_sha256 ~ '^[0-9a-f]{64}$'),
  served_pdf_bytes bigint not null check (served_pdf_bytes > 0 and served_pdf_bytes <= 10485760),
  viewer_kind text not null check (viewer_kind in ('OPERATOR', 'CUSTOMER')),
  operator_auth_user_id uuid references auth.users(id),
  preview_session_id uuid references public.preview_sessions(preview_session_id),
  served_by text not null check (nullif(btrim(served_by), '') is not null),
  served_at timestamptz not null default clock_timestamp(),
  constraint website_delivery_receipt_view_binding foreign key(
    view_derivative_id, artifact_id, project_id, preview_version_id,
    document_version, source_docx_sha256, served_pdf_sha256, served_pdf_bytes
  ) references public.website_delivery_document_view_derivatives(
    view_derivative_id, artifact_id, project_id, preview_version_id,
    document_version, source_docx_sha256, pdf_sha256, pdf_bytes
  ),
  constraint website_delivery_receipt_viewer_shape check (
    (viewer_kind = 'OPERATOR' and operator_auth_user_id is not null and preview_session_id is null)
    or (viewer_kind = 'CUSTOMER' and operator_auth_user_id is null and preview_session_id is not null)
  )
);

create trigger trg_website_delivery_view_derivatives_immutable
before update or delete on public.website_delivery_document_view_derivatives
for each row execute function public.prevent_website_delivery_document_mutation_v1();

create trigger trg_website_delivery_access_receipts_immutable
before update or delete on public.website_delivery_document_access_receipts
for each row execute function public.prevent_website_delivery_document_mutation_v1();

create function public.register_website_delivery_document_view_v1(
  p_artifact_id uuid,
  p_pdf_sha256 text,
  p_pdf_bytes bigint,
  p_content_type text,
  p_idempotency_key uuid,
  p_actor text
)
returns jsonb
language plpgsql
security definer
set search_path = public, storage, pg_catalog
as $$
declare
  v_source public.website_delivery_document_artifacts%rowtype;
  v_existing public.website_delivery_document_view_derivatives%rowtype;
  v_view public.website_delivery_document_view_derivatives%rowtype;
  v_path text;
  v_metadata jsonb;
begin
  if p_artifact_id is null or p_idempotency_key is null
     or p_pdf_sha256 is null or p_pdf_sha256 !~ '^[0-9a-f]{64}$'
     or p_pdf_bytes is null or p_pdf_bytes <= 0 or p_pdf_bytes > 10485760
     or p_content_type <> 'application/pdf'
     or nullif(btrim(p_actor), '') is null then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_VIEW_INPUT_INVALID';
  end if;

  select * into v_existing
  from public.website_delivery_document_view_derivatives
  where registration_idempotency_key = p_idempotency_key;
  if found then
    if v_existing.artifact_id <> p_artifact_id
       or v_existing.pdf_sha256 <> p_pdf_sha256
       or v_existing.pdf_bytes <> p_pdf_bytes
       or v_existing.content_type <> p_content_type then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_VIEW_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'view_derivative_id', v_existing.view_derivative_id,
      'artifact_id', v_existing.artifact_id,
      'project_id', v_existing.project_id,
      'preview_version_id', v_existing.preview_version_id,
      'document_version', v_existing.document_version,
      'source_docx_sha256', rtrim(v_existing.source_docx_sha256),
      'storage_bucket_id', v_existing.storage_bucket_id,
      'storage_object_path', v_existing.storage_object_path,
      'content_type', v_existing.content_type,
      'pdf_sha256', rtrim(v_existing.pdf_sha256),
      'pdf_bytes', v_existing.pdf_bytes,
      'was_created', false
    );
  end if;

  select * into v_source
  from public.website_delivery_document_artifacts
  where artifact_id = p_artifact_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_ARTIFACT_NOT_FOUND';
  end if;

  v_path := 'projects/' || v_source.project_id::text || '/versions/' || v_source.document_version::text
    || '/views/' || rtrim(v_source.docx_sha256) || '/' || p_pdf_sha256 || '.pdf';
  select metadata into v_metadata
  from storage.objects
  where bucket_id = 'website-delivery-document-views' and name = v_path;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_VIEW_OBJECT_NOT_FOUND';
  end if;
  if coalesce(v_metadata->>'mimetype', '') <> p_content_type
     or coalesce(v_metadata->>'size', '') !~ '^[0-9]+$'
     or (v_metadata->>'size')::bigint <> p_pdf_bytes then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_VIEW_OBJECT_METADATA_MISMATCH';
  end if;

  select * into v_existing
  from public.website_delivery_document_view_derivatives
  where artifact_id = p_artifact_id;
  if found then
    if v_existing.pdf_sha256 <> p_pdf_sha256
       or v_existing.pdf_bytes <> p_pdf_bytes
       or v_existing.storage_object_path <> v_path then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_VIEW_CONFLICT';
    end if;
    return jsonb_build_object(
      'view_derivative_id', v_existing.view_derivative_id,
      'artifact_id', v_existing.artifact_id,
      'project_id', v_existing.project_id,
      'preview_version_id', v_existing.preview_version_id,
      'document_version', v_existing.document_version,
      'source_docx_sha256', rtrim(v_existing.source_docx_sha256),
      'storage_bucket_id', v_existing.storage_bucket_id,
      'storage_object_path', v_existing.storage_object_path,
      'content_type', v_existing.content_type,
      'pdf_sha256', rtrim(v_existing.pdf_sha256),
      'pdf_bytes', v_existing.pdf_bytes,
      'was_created', false
    );
  end if;

  insert into public.website_delivery_document_view_derivatives(
    artifact_id, project_id, preview_version_id, document_version,
    source_docx_sha256, storage_bucket_id, storage_object_path, content_type,
    pdf_sha256, pdf_bytes, registration_idempotency_key, created_by
  ) values (
    v_source.artifact_id, v_source.project_id, v_source.preview_version_id,
    v_source.document_version, v_source.docx_sha256,
    'website-delivery-document-views', v_path, p_content_type,
    p_pdf_sha256, p_pdf_bytes, p_idempotency_key, btrim(p_actor)
  ) returning * into v_view;

  return jsonb_build_object(
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
    'pdf_bytes', v_view.pdf_bytes,
    'was_created', true
  );
end;
$$;

create function public.resolve_website_delivery_document_view_v1(
  p_project_id uuid,
  p_preview_version_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_view public.website_delivery_document_view_derivatives%rowtype;
begin
  if p_project_id is null or p_preview_version_id is null then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_VIEW_INPUT_INVALID';
  end if;
  select * into v_view
  from public.website_delivery_document_view_derivatives
  where project_id = p_project_id and preview_version_id = p_preview_version_id
  order by document_version desc
  limit 1;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_VIEW_NOT_FOUND';
  end if;
  return jsonb_build_object(
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

create function public.register_website_delivery_document_access_receipt_v1(
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

alter table public.website_delivery_document_view_derivatives enable row level security;
alter table public.website_delivery_document_view_derivatives force row level security;
alter table public.website_delivery_document_access_receipts enable row level security;
alter table public.website_delivery_document_access_receipts force row level security;

revoke all on table public.website_delivery_document_view_derivatives from public, anon, authenticated, service_role;
revoke all on table public.website_delivery_document_access_receipts from public, anon, authenticated, service_role;
revoke all on function public.register_website_delivery_document_view_v1(uuid,text,bigint,text,uuid,text) from public, anon, authenticated, service_role;
revoke all on function public.resolve_website_delivery_document_view_v1(uuid,uuid) from public, anon, authenticated, service_role;
revoke all on function public.register_website_delivery_document_access_receipt_v1(uuid,text,uuid,uuid,text,bigint,text) from public, anon, authenticated, service_role;
grant execute on function public.register_website_delivery_document_view_v1(uuid,text,bigint,text,uuid,text) to service_role;
grant execute on function public.resolve_website_delivery_document_view_v1(uuid,uuid) to service_role;
grant execute on function public.register_website_delivery_document_access_receipt_v1(uuid,text,uuid,uuid,text,bigint,text) to service_role;

comment on table public.website_delivery_document_view_derivatives is
  'Immutable private PDF viewing derivatives of registered website delivery DOCX artifacts; never rendered on read.';
comment on table public.website_delivery_document_access_receipts is
  'Append-only evidence that exact verified delivery-document PDF bytes were served to an authorized viewer; not evidence of reading or acceptance.';