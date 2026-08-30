alter table public.customer_request_uploaded_files
  add constraint customer_request_uploaded_files_source_binding_unique
  unique (uploaded_file_id, customer_request_id);

alter table public.customer_requests
  add constraint customer_requests_dossier_binding_unique
  unique (request_id, quote_request_id);

create table public.document_inbox_customer_request_upload_sources (
  uploaded_file_id uuid primary key
    references public.customer_request_uploaded_files(uploaded_file_id) on delete restrict,
  source_type text not null default 'CUSTOMER_REQUEST_UPLOAD'
    check (source_type = 'CUSTOMER_REQUEST_UPLOAD'),
  customer_request_id uuid not null
    references public.customer_requests(request_id) on delete restrict,
  quote_request_id uuid not null
    references public.quote_requests(id) on delete restrict,
  document_inbox_item_id uuid not null
    references public.document_inbox_items(id) on delete restrict,
  promoted_by_operator_id uuid not null
    references public.commercial_operators(operator_id) on delete restrict,
  promoted_at timestamptz not null default clock_timestamp(),
  unique (uploaded_file_id, customer_request_id),
  unique (uploaded_file_id, customer_request_id, quote_request_id)
);

alter table public.document_inbox_customer_request_upload_sources
  add constraint document_inbox_upload_source_file_binding_fk
  foreign key (uploaded_file_id, customer_request_id)
  references public.customer_request_uploaded_files(uploaded_file_id, customer_request_id)
  on delete restrict,
  add constraint document_inbox_upload_source_dossier_binding_fk
  foreign key (customer_request_id, quote_request_id)
  references public.customer_requests(request_id, quote_request_id)
  on delete restrict;

create index document_inbox_customer_request_upload_sources_item_idx
on public.document_inbox_customer_request_upload_sources(document_inbox_item_id);

alter table public.document_inbox_customer_request_upload_sources enable row level security;
alter table public.document_inbox_customer_request_upload_sources force row level security;

revoke all on table public.document_inbox_customer_request_upload_sources
from public, anon, authenticated, service_role;

create function public.authorize_customer_request_upload_inbox_promotion_v1(
  p_uploaded_file_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, storage, auth, pg_catalog
as $$
declare
  v_file public.customer_request_uploaded_files%rowtype;
  v_request public.customer_requests%rowtype;
  v_authorization record;
  v_source public.document_inbox_customer_request_upload_sources%rowtype;
  v_item public.document_inbox_items%rowtype;
  v_destination_path text;
  v_source_metadata jsonb;
begin
  if p_uploaded_file_id is null then
    raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST_UPLOAD_PROMOTION';
  end if;

  select * into v_file
  from public.customer_request_uploaded_files
  where uploaded_file_id = p_uploaded_file_id
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = 'CUSTOMER_REQUEST_UPLOAD_NOT_FOUND';
  end if;

  select * into strict v_request
  from public.customer_requests
  where request_id = v_file.customer_request_id
  for share;

  select * into strict v_authorization
  from public.resolve_customer_request_authorization_v1(v_request.request_id, 'WORK');

  if v_file.status <> 'ACCEPTED' then
    raise exception using errcode = '55000', message = 'CUSTOMER_REQUEST_UPLOAD_NOT_ACCEPTED';
  end if;

  if v_file.storage_bucket_id <> 'customer-request-quarantine'
     or v_file.observed_content_type is null
     or v_file.observed_byte_count is null
     or v_file.sha256 is null then
    raise exception using errcode = '55000', message = 'CUSTOMER_REQUEST_UPLOAD_SOURCE_INVALID';
  end if;

  select metadata into v_source_metadata
  from storage.objects
  where bucket_id = v_file.storage_bucket_id
    and name = v_file.storage_object_path;

  if not found then
    raise exception using errcode = 'P0001', message = 'CUSTOMER_REQUEST_UPLOAD_SOURCE_OBJECT_NOT_FOUND';
  end if;

  select * into v_source
  from public.document_inbox_customer_request_upload_sources
  where uploaded_file_id = v_file.uploaded_file_id;

  if found then
    if v_source.customer_request_id <> v_request.request_id
       or v_source.quote_request_id <> v_request.quote_request_id then
      raise exception using errcode = '23505', message = 'CUSTOMER_REQUEST_UPLOAD_PROMOTION_CONFLICT';
    end if;
    select * into strict v_item
    from public.document_inbox_items
    where id = v_source.document_inbox_item_id;
    return jsonb_build_object(
      'state', 'PROMOTED',
      'uploaded_file_id', v_file.uploaded_file_id,
      'document_inbox_item_id', v_item.id,
      'status', v_item.lifecycle_status,
      'replayed', true
    );
  end if;

  v_destination_path := 'documents/' || rtrim(v_file.sha256) || case v_file.observed_content_type
    when 'application/pdf' then '.pdf'
    when 'image/png' then '.png'
    when 'image/jpeg' then '.jpg'
  end;

  if v_destination_path is null then
    raise exception using errcode = '55000', message = 'CUSTOMER_REQUEST_UPLOAD_SOURCE_INVALID';
  end if;

  return jsonb_build_object(
    'state', 'AUTHORIZED',
    'uploaded_file_id', v_file.uploaded_file_id,
    'customer_request_id', v_request.request_id,
    'quote_request_id', v_request.quote_request_id,
    'source_bucket_id', v_file.storage_bucket_id,
    'source_object_path', v_file.storage_object_path,
    'destination_bucket_id', 'supplier-documents',
    'destination_object_path', v_destination_path,
    'original_file_name', v_file.original_file_name,
    'mime_type', v_file.observed_content_type,
    'byte_count', v_file.observed_byte_count,
    'sha256', rtrim(v_file.sha256)
  );
end;
$$;

create function public.finalize_customer_request_upload_inbox_promotion_v1(
  p_uploaded_file_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, storage, auth, pg_catalog
as $$
declare
  v_file public.customer_request_uploaded_files%rowtype;
  v_request public.customer_requests%rowtype;
  v_authorization record;
  v_operator_id uuid;
  v_source public.document_inbox_customer_request_upload_sources%rowtype;
  v_item public.document_inbox_items%rowtype;
  v_destination_path text;
  v_destination_metadata jsonb;
  v_inserted_item boolean := false;
begin
  if p_uploaded_file_id is null then
    raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST_UPLOAD_PROMOTION';
  end if;

  select * into v_file
  from public.customer_request_uploaded_files
  where uploaded_file_id = p_uploaded_file_id
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = 'CUSTOMER_REQUEST_UPLOAD_NOT_FOUND';
  end if;

  select * into strict v_request
  from public.customer_requests
  where request_id = v_file.customer_request_id
  for share;

  select * into strict v_authorization
  from public.resolve_customer_request_authorization_v1(v_request.request_id, 'WORK');
  v_operator_id := v_authorization.operator_id;

  if v_file.status <> 'ACCEPTED'
     or v_file.storage_bucket_id <> 'customer-request-quarantine'
     or v_file.observed_content_type is null
     or v_file.observed_byte_count is null
     or v_file.sha256 is null then
    raise exception using errcode = '55000', message = 'CUSTOMER_REQUEST_UPLOAD_NOT_ACCEPTED';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_file.uploaded_file_id::text, 0));

  select * into v_source
  from public.document_inbox_customer_request_upload_sources
  where uploaded_file_id = v_file.uploaded_file_id;

  if found then
    if v_source.customer_request_id <> v_request.request_id
       or v_source.quote_request_id <> v_request.quote_request_id then
      raise exception using errcode = '23505', message = 'CUSTOMER_REQUEST_UPLOAD_PROMOTION_CONFLICT';
    end if;
    select * into strict v_item
    from public.document_inbox_items
    where id = v_source.document_inbox_item_id;
    return jsonb_build_object(
      'state', 'PROMOTED',
      'uploaded_file_id', v_file.uploaded_file_id,
      'document_inbox_item_id', v_item.id,
      'status', v_item.lifecycle_status,
      'replayed', true
    );
  end if;

  v_destination_path := 'documents/' || rtrim(v_file.sha256) || case v_file.observed_content_type
    when 'application/pdf' then '.pdf'
    when 'image/png' then '.png'
    when 'image/jpeg' then '.jpg'
  end;

  select metadata into v_destination_metadata
  from storage.objects
  where bucket_id = 'supplier-documents'
    and name = v_destination_path;

  if not found then
    raise exception using errcode = 'P0001', message = 'DOCUMENT_INBOX_PROMOTION_OBJECT_NOT_FOUND';
  end if;

  if coalesce(v_destination_metadata->>'mimetype', '') <> v_file.observed_content_type
     or coalesce(v_destination_metadata->>'size', '') !~ '^[0-9]+$'
     or (v_destination_metadata->>'size')::bigint <> v_file.observed_byte_count
     or coalesce(v_destination_metadata->>'sha256', '') <> rtrim(v_file.sha256) then
    raise exception using errcode = 'P0001', message = 'DOCUMENT_INBOX_PROMOTION_OBJECT_MISMATCH';
  end if;

  select * into v_item
  from public.document_inbox_items
  where rtrim(sha256) = rtrim(v_file.sha256)
  for update;

  if not found then
    insert into public.document_inbox_items(
      sha256,
      storage_object_path,
      original_file_name,
      mime_type,
      byte_count,
      source_type,
      source_instance,
      external_id,
      record_classification,
      created_by_operator_id
    ) values (
      rtrim(v_file.sha256),
      v_destination_path,
      v_file.original_file_name,
      v_file.observed_content_type,
      v_file.observed_byte_count,
      'CUSTOMER_REQUEST_UPLOAD',
      v_request.request_id::text,
      v_file.uploaded_file_id::text,
      'production',
      v_operator_id
    )
    returning * into v_item;
    v_inserted_item := true;
  elsif v_item.storage_object_path <> v_destination_path
     or v_item.mime_type <> v_file.observed_content_type
     or v_item.byte_count <> v_file.observed_byte_count then
    raise exception using errcode = '23505', message = 'DOCUMENT_INBOX_BINARY_IDENTITY_MISMATCH';
  end if;

  insert into public.document_inbox_customer_request_upload_sources(
    uploaded_file_id,
    customer_request_id,
    quote_request_id,
    document_inbox_item_id,
    promoted_by_operator_id
  ) values (
    v_file.uploaded_file_id,
    v_request.request_id,
    v_request.quote_request_id,
    v_item.id,
    v_operator_id
  );

  if v_inserted_item then
    insert into public.document_inbox_events(
      inbox_item_id,
      event_type,
      actor_user_id,
      stage,
      metadata
    ) values (
      v_item.id,
      'RECEIVED',
      auth.uid(),
      'RECEIVE',
      jsonb_build_object('source_type', 'CUSTOMER_REQUEST_UPLOAD')
    );
  end if;

  return jsonb_build_object(
    'state', 'PROMOTED',
    'uploaded_file_id', v_file.uploaded_file_id,
    'document_inbox_item_id', v_item.id,
    'status', v_item.lifecycle_status,
    'replayed', false
  );
end;
$$;

revoke all on function public.authorize_customer_request_upload_inbox_promotion_v1(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.finalize_customer_request_upload_inbox_promotion_v1(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.authorize_customer_request_upload_inbox_promotion_v1(uuid)
to authenticated;
grant execute on function public.finalize_customer_request_upload_inbox_promotion_v1(uuid)
to authenticated;

comment on table public.document_inbox_customer_request_upload_sources is
  'Immutable typed provenance linking accepted Customer Request uploads to deduplicated Document Inbox items.';
comment on function public.authorize_customer_request_upload_inbox_promotion_v1(uuid) is
  'Caller-JWT authorization and canonical storage contract for one accepted Customer Request upload promotion.';
comment on function public.finalize_customer_request_upload_inbox_promotion_v1(uuid) is
  'Caller-JWT, race-safe registration of a copied Customer Request upload in the existing Document Inbox.';
