insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) values (
  'customer-request-quarantine',
  'customer-request-quarantine',
  false,
  8388608,
  array['application/pdf', 'image/png', 'image/jpeg']::text[]
);

create table public.customer_request_upload_requests (
  upload_request_id uuid primary key default gen_random_uuid(),
  customer_request_id uuid not null references public.customer_requests(request_id),
  token_digest char(64) not null unique check (token_digest ~ '^[0-9a-f]{64}$'),
  capability_version integer not null default 1 check (capability_version = 1),
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'COMPLETED', 'REVOKED', 'EXPIRED')),
  expires_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  created_by_operator_id uuid not null references public.commercial_operators(operator_id),
  completed_at timestamptz,
  revoked_at timestamptz,
  revoked_by_operator_id uuid references public.commercial_operators(operator_id),
  revocation_reason text check (revocation_reason is null or (length(revocation_reason) between 1 and 500 and revocation_reason = btrim(revocation_reason))),
  expired_at timestamptz,
  constraint customer_request_upload_expiry_valid check (expires_at > created_at),
  constraint customer_request_upload_status_shape_valid check (
    (status = 'ACTIVE' and completed_at is null and revoked_at is null and revoked_by_operator_id is null and revocation_reason is null and expired_at is null)
    or (status = 'COMPLETED' and completed_at is not null and revoked_at is null and revoked_by_operator_id is null and revocation_reason is null and expired_at is null)
    or (status = 'REVOKED' and completed_at is null and revoked_at is not null and revoked_by_operator_id is not null and revocation_reason is not null and expired_at is null)
    or (status = 'EXPIRED' and completed_at is null and revoked_at is null and revoked_by_operator_id is null and revocation_reason is null and expired_at is not null)
  )
);

create unique index customer_request_upload_one_active_per_request
on public.customer_request_upload_requests(customer_request_id)
where status = 'ACTIVE';
create index customer_request_upload_expiry_idx
on public.customer_request_upload_requests(expires_at)
where status = 'ACTIVE';

create table public.customer_request_uploaded_files (
  uploaded_file_id uuid primary key default gen_random_uuid(),
  upload_request_id uuid not null references public.customer_request_upload_requests(upload_request_id),
  customer_request_id uuid not null references public.customer_requests(request_id),
  status text not null default 'PREPARED' check (status in ('PREPARED', 'ACCEPTED', 'REJECTED', 'EXPIRED', 'DELETED')),
  storage_bucket_id text not null default 'customer-request-quarantine' check (storage_bucket_id = 'customer-request-quarantine'),
  storage_object_path text not null unique,
  original_file_name text not null check (length(original_file_name) between 1 and 200 and original_file_name = btrim(original_file_name) and original_file_name !~ '[\\/]'),
  file_extension text not null check (file_extension in ('pdf', 'png', 'jpg', 'jpeg')),
  declared_content_type text not null check (declared_content_type in ('application/pdf', 'image/png', 'image/jpeg')),
  declared_byte_count bigint not null check (declared_byte_count between 1 and 8388608),
  observed_content_type text check (observed_content_type is null or observed_content_type in ('application/pdf', 'image/png', 'image/jpeg')),
  observed_byte_count bigint check (observed_byte_count is null or observed_byte_count between 1 and 8388608),
  sha256 char(64) check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
  prepared_at timestamptz not null default clock_timestamp(),
  accepted_at timestamptz,
  rejected_at timestamptz,
  rejection_code text check (rejection_code is null or rejection_code in ('OBJECT_NOT_FOUND', 'OBJECT_PATH_MISMATCH', 'SIZE_MISMATCH', 'MIME_MISMATCH', 'SIGNATURE_MISMATCH', 'HASH_INVALID')),
  expired_at timestamptz,
  deleted_at timestamptz,
  constraint customer_request_uploaded_file_path_valid check (
    storage_object_path = 'requests/' || customer_request_id::text || '/uploads/' || upload_request_id::text || '/files/' || uploaded_file_id::text || '.' || file_extension
  ),
  constraint customer_request_uploaded_file_type_valid check (
    (declared_content_type = 'application/pdf' and file_extension = 'pdf')
    or (declared_content_type = 'image/png' and file_extension = 'png')
    or (declared_content_type = 'image/jpeg' and file_extension in ('jpg', 'jpeg'))
  ),
  constraint customer_request_uploaded_file_status_shape_valid check (
    (status = 'PREPARED' and accepted_at is null and rejected_at is null and rejection_code is null and expired_at is null and deleted_at is null and observed_content_type is null and observed_byte_count is null and sha256 is null)
    or (status = 'ACCEPTED' and accepted_at is not null and rejected_at is null and rejection_code is null and expired_at is null and deleted_at is null and observed_content_type is not null and observed_byte_count is not null and sha256 is not null)
    or (status = 'REJECTED' and accepted_at is null and rejected_at is not null and rejection_code is not null and expired_at is null and deleted_at is null)
    or (status = 'EXPIRED' and accepted_at is null and rejected_at is null and rejection_code is null and expired_at is not null and deleted_at is null)
    or (status = 'DELETED' and deleted_at is not null)
  )
);

create index customer_request_uploaded_files_request_idx
on public.customer_request_uploaded_files(upload_request_id, prepared_at);

create table lws_internal.customer_request_upload_operations (
  idempotency_key uuid primary key,
  operation_type text not null check (operation_type in ('CREATE', 'REVOKE', 'PREPARE', 'FINALIZE', 'COMPLETE', 'CLEANUP')),
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  upload_request_id uuid references public.customer_request_upload_requests(upload_request_id),
  uploaded_file_id uuid references public.customer_request_uploaded_files(uploaded_file_id),
  result_payload jsonb not null check (jsonb_typeof(result_payload) = 'object' and not (result_payload ?| array['token', 'token_digest', 'signed_url', 'credential', 'secret', 'service_role_key'])),
  created_at timestamptz not null default clock_timestamp()
);

create function lws_internal.guard_customer_request_upload_request_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'CUSTOMER_REQUEST_UPLOAD_REQUEST_DELETE_FORBIDDEN';
  end if;
  if new.upload_request_id is distinct from old.upload_request_id
      or new.customer_request_id is distinct from old.customer_request_id
      or new.token_digest is distinct from old.token_digest
      or new.capability_version is distinct from old.capability_version
      or new.expires_at is distinct from old.expires_at
      or new.created_at is distinct from old.created_at
      or new.created_by_operator_id is distinct from old.created_by_operator_id then
    raise exception using errcode = '23514', message = 'CUSTOMER_REQUEST_UPLOAD_IDENTITY_IMMUTABLE';
  end if;
  if current_setting('lws.customer_request_upload_transition', true) is distinct from 'on' then
    raise exception using errcode = '55000', message = 'DIRECT_CUSTOMER_REQUEST_UPLOAD_WRITE_FORBIDDEN';
  end if;
  return new;
end;
$$;

create function lws_internal.guard_customer_request_uploaded_file_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'CUSTOMER_REQUEST_UPLOADED_FILE_DELETE_FORBIDDEN';
  end if;
  if new.uploaded_file_id is distinct from old.uploaded_file_id
      or new.upload_request_id is distinct from old.upload_request_id
      or new.customer_request_id is distinct from old.customer_request_id
      or new.storage_bucket_id is distinct from old.storage_bucket_id
      or new.storage_object_path is distinct from old.storage_object_path
      or new.original_file_name is distinct from old.original_file_name
      or new.file_extension is distinct from old.file_extension
      or new.declared_content_type is distinct from old.declared_content_type
      or new.declared_byte_count is distinct from old.declared_byte_count
      or new.prepared_at is distinct from old.prepared_at then
    raise exception using errcode = '23514', message = 'CUSTOMER_REQUEST_UPLOADED_FILE_IDENTITY_IMMUTABLE';
  end if;
  if current_setting('lws.customer_request_upload_transition', true) is distinct from 'on' then
    raise exception using errcode = '55000', message = 'DIRECT_CUSTOMER_REQUEST_UPLOAD_WRITE_FORBIDDEN';
  end if;
  return new;
end;
$$;

create function lws_internal.prevent_customer_request_upload_operation_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'CUSTOMER_REQUEST_UPLOAD_OPERATIONS_APPEND_ONLY';
end;
$$;

create trigger trg_customer_request_upload_request_guard
before update or delete on public.customer_request_upload_requests
for each row execute function lws_internal.guard_customer_request_upload_request_v1();
create trigger trg_customer_request_uploaded_file_guard
before update or delete on public.customer_request_uploaded_files
for each row execute function lws_internal.guard_customer_request_uploaded_file_v1();
create trigger trg_customer_request_upload_operations_immutable
before update or delete on lws_internal.customer_request_upload_operations
for each row execute function lws_internal.prevent_customer_request_upload_operation_mutation_v1();

create function public.create_customer_request_upload_request_v1(
  p_request_id uuid,
  p_token_digest text,
  p_requested_expires_at timestamptz,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_authorization record;
  v_request public.customer_request_upload_requests%rowtype;
  v_operation lws_internal.customer_request_upload_operations%rowtype;
  v_expires_at timestamptz;
  v_fingerprint text;
  v_result jsonb;
begin
  if p_request_id is null or p_idempotency_key is null or p_token_digest !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_UPLOAD_REQUEST';
  end if;
  select * into strict v_authorization
  from public.resolve_customer_request_authorization_v1(p_request_id, 'WORK');
  v_fingerprint := lws_internal.customer_request_fingerprint_v1(jsonb_build_object(
    'requestId', p_request_id, 'tokenDigest', p_token_digest, 'requestedExpiresAt', p_requested_expires_at
  ));
  select * into v_operation from lws_internal.customer_request_upload_operations where idempotency_key = p_idempotency_key;
  if found then
    if v_operation.operation_type <> 'CREATE' or v_operation.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_operation.result_payload;
  end if;
  v_expires_at := coalesce(p_requested_expires_at, clock_timestamp() + interval '7 days');
  if v_expires_at <= clock_timestamp() or v_expires_at > clock_timestamp() + interval '30 days' then
    raise exception using errcode = '22023', message = 'INVALID_UPLOAD_EXPIRY';
  end if;
  perform set_config('lws.customer_request_upload_transition', 'on', true);
  update public.customer_request_upload_requests
  set status = 'EXPIRED', expired_at = clock_timestamp()
  where customer_request_id = p_request_id and status = 'ACTIVE' and expires_at <= clock_timestamp();
  perform set_config('lws.customer_request_upload_transition', '', true);
  if exists (select 1 from public.customer_request_upload_requests where customer_request_id = p_request_id and status = 'ACTIVE') then
    raise exception using errcode = 'P0001', message = 'ACTIVE_UPLOAD_REQUEST_EXISTS';
  end if;
  insert into public.customer_request_upload_requests(
    customer_request_id, token_digest, expires_at, created_by_operator_id
  ) values (
    p_request_id, p_token_digest, v_expires_at, v_authorization.operator_id
  ) returning * into v_request;
  v_result := jsonb_build_object(
    'state', 'ACTIVE', 'upload_request_id', v_request.upload_request_id,
    'expires_at', v_request.expires_at, 'was_created', true
  );
  insert into lws_internal.customer_request_upload_operations(
    idempotency_key, operation_type, request_fingerprint, upload_request_id, result_payload
  ) values (p_idempotency_key, 'CREATE', v_fingerprint, v_request.upload_request_id, v_result);
  return v_result;
end;
$$;

create function public.revoke_customer_request_upload_request_v1(
  p_upload_request_id uuid,
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_authorization record;
  v_request public.customer_request_upload_requests%rowtype;
  v_operation lws_internal.customer_request_upload_operations%rowtype;
  v_fingerprint text;
  v_result jsonb;
begin
  if p_upload_request_id is null or p_idempotency_key is null or nullif(btrim(p_reason), '') is null or length(p_reason) > 500 then
    raise exception using errcode = '22023', message = 'INVALID_UPLOAD_REVOCATION';
  end if;
  select * into v_request from public.customer_request_upload_requests where upload_request_id = p_upload_request_id for update;
  if not found then raise exception using errcode = '42501', message = 'CUSTOMER_REQUEST_ACCESS_DENIED'; end if;
  select * into strict v_authorization
  from public.resolve_customer_request_authorization_v1(v_request.customer_request_id, 'WORK');
  v_fingerprint := lws_internal.customer_request_fingerprint_v1(jsonb_build_object(
    'uploadRequestId', p_upload_request_id, 'reason', btrim(p_reason)
  ));
  select * into v_operation from lws_internal.customer_request_upload_operations where idempotency_key = p_idempotency_key;
  if found then
    if v_operation.operation_type <> 'REVOKE' or v_operation.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_operation.result_payload;
  end if;
  if v_request.status <> 'ACTIVE' or v_request.expires_at <= clock_timestamp() then
    raise exception using errcode = 'P0001', message = 'UPLOAD_REQUEST_NOT_ACTIVE';
  end if;
  perform set_config('lws.customer_request_upload_transition', 'on', true);
  update public.customer_request_upload_requests
  set status = 'REVOKED', revoked_at = clock_timestamp(), revoked_by_operator_id = v_authorization.operator_id, revocation_reason = btrim(p_reason)
  where upload_request_id = p_upload_request_id returning * into v_request;
  perform set_config('lws.customer_request_upload_transition', '', true);
  v_result := jsonb_build_object('state', 'REVOKED', 'upload_request_id', v_request.upload_request_id, 'was_revoked', true);
  insert into lws_internal.customer_request_upload_operations values (
    p_idempotency_key, 'REVOKE', v_fingerprint, v_request.upload_request_id, null, v_result, clock_timestamp()
  );
  return v_result;
end;
$$;

create function public.list_customer_request_uploaded_files_v1(p_token_digest text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_request public.customer_request_upload_requests%rowtype;
begin
  if p_token_digest !~ '^[0-9a-f]{64}$' then return jsonb_build_object('state', 'INVALID_OR_EXPIRED_LINK'); end if;
  select * into v_request from public.customer_request_upload_requests where token_digest = p_token_digest;
  if not found or v_request.status not in ('ACTIVE', 'COMPLETED') or (v_request.status = 'ACTIVE' and v_request.expires_at <= clock_timestamp()) then
    return jsonb_build_object('state', 'INVALID_OR_EXPIRED_LINK');
  end if;
  return jsonb_build_object(
    'state', v_request.status,
    'files', coalesce((select jsonb_agg(jsonb_build_object(
      'file_id', file.uploaded_file_id, 'original_file_name', file.original_file_name,
      'content_type', file.observed_content_type, 'byte_count', file.observed_byte_count,
      'sha256', rtrim(file.sha256), 'status', file.status, 'accepted_at', file.accepted_at
    ) order by file.prepared_at) from public.customer_request_uploaded_files as file
      where file.upload_request_id = v_request.upload_request_id and file.status = 'ACCEPTED'), '[]'::jsonb)
  );
end;
$$;

create function public.resolve_customer_request_upload_capability_v1(p_token_digest text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_request public.customer_request_upload_requests%rowtype;
  v_customer_request public.customer_requests%rowtype;
  v_files jsonb;
  v_file_count integer;
  v_total_bytes bigint;
  v_accepted_count integer;
begin
  if p_token_digest !~ '^[0-9a-f]{64}$' then return jsonb_build_object('state', 'INVALID_OR_EXPIRED_LINK'); end if;
  select * into v_request from public.customer_request_upload_requests where token_digest = p_token_digest;
  if not found or v_request.status not in ('ACTIVE', 'COMPLETED') or (v_request.status = 'ACTIVE' and v_request.expires_at <= clock_timestamp()) then
    return jsonb_build_object('state', 'INVALID_OR_EXPIRED_LINK');
  end if;
  select * into strict v_customer_request from public.customer_requests where request_id = v_request.customer_request_id;
  select count(*)::integer, coalesce(sum(declared_byte_count), 0), count(*) filter (where status = 'ACCEPTED')::integer
  into v_file_count, v_total_bytes, v_accepted_count
  from public.customer_request_uploaded_files
  where upload_request_id = v_request.upload_request_id and status in ('PREPARED', 'ACCEPTED');
  v_files := public.list_customer_request_uploaded_files_v1(p_token_digest)->'files';
  return jsonb_build_object(
    'state', v_request.status, 'request_reference', v_customer_request.request_reference,
    'title', v_customer_request.title, 'expires_at', v_request.expires_at,
    'file_count', v_file_count, 'accepted_file_count', v_accepted_count,
    'reserved_byte_count', v_total_bytes, 'files', v_files
  );
end;
$$;

create function public.prepare_customer_request_upload_v1(
  p_token_digest text,
  p_original_file_name text,
  p_content_type text,
  p_byte_count bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_request public.customer_request_upload_requests%rowtype;
  v_file public.customer_request_uploaded_files%rowtype;
  v_operation lws_internal.customer_request_upload_operations%rowtype;
  v_extension text;
  v_count integer;
  v_total bigint;
  v_fingerprint text;
  v_result jsonb;
begin
  if p_idempotency_key is null or p_token_digest !~ '^[0-9a-f]{64}$'
      or nullif(btrim(p_original_file_name), '') is null or length(p_original_file_name) > 200
      or p_original_file_name ~ '[\\/]' or p_byte_count not between 1 and 8388608 then
    return jsonb_build_object('state', 'VALIDATION_FAILED');
  end if;
  v_extension := substring(lower(p_original_file_name) from '\.([a-z0-9]+)$');
  if not ((p_content_type = 'application/pdf' and v_extension = 'pdf')
      or (p_content_type = 'image/png' and v_extension = 'png')
      or (p_content_type = 'image/jpeg' and v_extension in ('jpg', 'jpeg'))) then
    return jsonb_build_object('state', 'VALIDATION_FAILED');
  end if;
  v_fingerprint := lws_internal.customer_request_fingerprint_v1(jsonb_build_object(
    'tokenDigest', p_token_digest, 'fileName', btrim(p_original_file_name),
    'contentType', p_content_type, 'byteCount', p_byte_count
  ));
  select * into v_operation from lws_internal.customer_request_upload_operations where idempotency_key = p_idempotency_key;
  if found then
    if v_operation.operation_type <> 'PREPARE' or v_operation.request_fingerprint <> v_fingerprint then
      return jsonb_build_object('state', 'IDEMPOTENCY_CONFLICT');
    end if;
    return v_operation.result_payload;
  end if;
  select * into v_request from public.customer_request_upload_requests where token_digest = p_token_digest for update;
  if not found or v_request.status <> 'ACTIVE' or v_request.expires_at <= clock_timestamp() then
    return jsonb_build_object('state', 'INVALID_OR_EXPIRED_LINK');
  end if;
  select count(*)::integer, coalesce(sum(declared_byte_count), 0)
  into v_count, v_total from public.customer_request_uploaded_files
  where upload_request_id = v_request.upload_request_id and status in ('PREPARED', 'ACCEPTED');
  if v_count >= 5 or v_total + p_byte_count > 26214400 then
    return jsonb_build_object('state', 'LIMIT_EXCEEDED');
  end if;
  v_file.uploaded_file_id := gen_random_uuid();
  v_file.storage_object_path := 'requests/' || v_request.customer_request_id::text || '/uploads/' || v_request.upload_request_id::text || '/files/' || v_file.uploaded_file_id::text || '.' || v_extension;
  insert into public.customer_request_uploaded_files(
    uploaded_file_id, upload_request_id, customer_request_id, storage_object_path,
    original_file_name, file_extension, declared_content_type, declared_byte_count
  ) values (
    v_file.uploaded_file_id, v_request.upload_request_id, v_request.customer_request_id, v_file.storage_object_path,
    btrim(p_original_file_name), v_extension, p_content_type, p_byte_count
  ) returning * into v_file;
  v_result := jsonb_build_object(
    'state', 'PREPARED', 'file_id', v_file.uploaded_file_id,
    'storage_bucket_id', v_file.storage_bucket_id, 'storage_object_path', v_file.storage_object_path
  );
  insert into lws_internal.customer_request_upload_operations values (
    p_idempotency_key, 'PREPARE', v_fingerprint, v_request.upload_request_id, v_file.uploaded_file_id, v_result, clock_timestamp()
  );
  return v_result;
end;
$$;

create function public.finalize_customer_request_uploaded_file_v1(
  p_token_digest text,
  p_uploaded_file_id uuid,
  p_observed_content_type text,
  p_observed_byte_count bigint,
  p_sha256 text,
  p_signature_valid boolean,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, storage, extensions, pg_catalog
as $$
declare
  v_request public.customer_request_upload_requests%rowtype;
  v_file public.customer_request_uploaded_files%rowtype;
  v_operation lws_internal.customer_request_upload_operations%rowtype;
  v_storage_metadata jsonb;
  v_rejection text;
  v_fingerprint text;
  v_result jsonb;
begin
  if p_idempotency_key is null or p_token_digest !~ '^[0-9a-f]{64}$' or p_uploaded_file_id is null then
    return jsonb_build_object('state', 'VALIDATION_FAILED');
  end if;
  v_fingerprint := lws_internal.customer_request_fingerprint_v1(jsonb_build_object(
    'tokenDigest', p_token_digest, 'fileId', p_uploaded_file_id,
    'contentType', p_observed_content_type, 'byteCount', p_observed_byte_count,
    'sha256', p_sha256, 'signatureValid', p_signature_valid
  ));
  select * into v_operation from lws_internal.customer_request_upload_operations where idempotency_key = p_idempotency_key;
  if found then
    if v_operation.operation_type <> 'FINALIZE' or v_operation.request_fingerprint <> v_fingerprint then
      return jsonb_build_object('state', 'IDEMPOTENCY_CONFLICT');
    end if;
    return v_operation.result_payload;
  end if;
  select * into v_request from public.customer_request_upload_requests where token_digest = p_token_digest for update;
  if not found or v_request.status <> 'ACTIVE' or v_request.expires_at <= clock_timestamp() then
    return jsonb_build_object('state', 'INVALID_OR_EXPIRED_LINK');
  end if;
  select * into v_file from public.customer_request_uploaded_files
  where uploaded_file_id = p_uploaded_file_id and upload_request_id = v_request.upload_request_id
  for update;
  if not found then return jsonb_build_object('state', 'VALIDATION_FAILED'); end if;
  if p_observed_content_type is null and p_observed_byte_count is null and p_sha256 is null and p_signature_valid is null then
    if v_file.status <> 'PREPARED' then return jsonb_build_object('state', 'VALIDATION_FAILED'); end if;
    return jsonb_build_object(
      'state', 'PREPARED', 'file_id', v_file.uploaded_file_id,
      'storage_bucket_id', v_file.storage_bucket_id, 'storage_object_path', v_file.storage_object_path,
      'declared_content_type', v_file.declared_content_type, 'declared_byte_count', v_file.declared_byte_count
    );
  end if;
  if v_file.status = 'ACCEPTED' then return jsonb_build_object('state', 'VALIDATION_FAILED'); end if;
  if v_file.status <> 'PREPARED' then return jsonb_build_object('state', 'VALIDATION_FAILED'); end if;
  select objects.metadata into v_storage_metadata from storage.objects as objects
  where objects.bucket_id = v_file.storage_bucket_id and objects.name = v_file.storage_object_path;
  if not found then v_rejection := 'OBJECT_NOT_FOUND';
  elsif p_observed_byte_count is distinct from v_file.declared_byte_count
      or coalesce(v_storage_metadata->>'size', '') !~ '^[0-9]+$'
      or (v_storage_metadata->>'size')::bigint is distinct from v_file.declared_byte_count then v_rejection := 'SIZE_MISMATCH';
  elsif p_observed_content_type is distinct from v_file.declared_content_type
      or v_storage_metadata->>'mimetype' is distinct from v_file.declared_content_type then v_rejection := 'MIME_MISMATCH';
  elsif p_signature_valid is distinct from true then v_rejection := 'SIGNATURE_MISMATCH';
  elsif p_sha256 !~ '^[0-9a-f]{64}$' then v_rejection := 'HASH_INVALID';
  end if;
  perform set_config('lws.customer_request_upload_transition', 'on', true);
  if v_rejection is null then
    update public.customer_request_uploaded_files set
      status = 'ACCEPTED', observed_content_type = p_observed_content_type,
      observed_byte_count = p_observed_byte_count, sha256 = p_sha256, accepted_at = clock_timestamp()
    where uploaded_file_id = v_file.uploaded_file_id returning * into v_file;
    v_result := public.resolve_customer_request_upload_capability_v1(p_token_digest);
  else
    update public.customer_request_uploaded_files set
      status = 'REJECTED', observed_content_type = case when p_observed_content_type in ('application/pdf','image/png','image/jpeg') then p_observed_content_type end,
      observed_byte_count = case when p_observed_byte_count between 1 and 8388608 then p_observed_byte_count end,
      sha256 = case when p_sha256 ~ '^[0-9a-f]{64}$' then p_sha256 end,
      rejected_at = clock_timestamp(), rejection_code = v_rejection
    where uploaded_file_id = v_file.uploaded_file_id returning * into v_file;
    v_result := jsonb_build_object('state', 'REJECTED', 'file_id', v_file.uploaded_file_id, 'delete_object', true, 'storage_object_path', v_file.storage_object_path);
  end if;
  perform set_config('lws.customer_request_upload_transition', '', true);
  insert into lws_internal.customer_request_upload_operations values (
    p_idempotency_key, 'FINALIZE', v_fingerprint, v_request.upload_request_id, v_file.uploaded_file_id, v_result, clock_timestamp()
  );
  return v_result;
end;
$$;

create function public.complete_customer_request_upload_request_v1(
  p_token_digest text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_request public.customer_request_upload_requests%rowtype;
  v_operation lws_internal.customer_request_upload_operations%rowtype;
  v_fingerprint text;
  v_result jsonb;
begin
  if p_idempotency_key is null or p_token_digest !~ '^[0-9a-f]{64}$' then return jsonb_build_object('state', 'VALIDATION_FAILED'); end if;
  v_fingerprint := lws_internal.customer_request_fingerprint_v1(jsonb_build_object('tokenDigest', p_token_digest));
  select * into v_operation from lws_internal.customer_request_upload_operations where idempotency_key = p_idempotency_key;
  if found then
    if v_operation.operation_type <> 'COMPLETE' or v_operation.request_fingerprint <> v_fingerprint then return jsonb_build_object('state', 'IDEMPOTENCY_CONFLICT'); end if;
    return v_operation.result_payload;
  end if;
  select * into v_request from public.customer_request_upload_requests where token_digest = p_token_digest for update;
  if not found or v_request.status <> 'ACTIVE' or v_request.expires_at <= clock_timestamp() then return jsonb_build_object('state', 'INVALID_OR_EXPIRED_LINK'); end if;
  if exists (select 1 from public.customer_request_uploaded_files where upload_request_id = v_request.upload_request_id and status = 'PREPARED')
      or not exists (select 1 from public.customer_request_uploaded_files where upload_request_id = v_request.upload_request_id and status = 'ACCEPTED') then
    return jsonb_build_object('state', 'VALIDATION_FAILED');
  end if;
  perform set_config('lws.customer_request_upload_transition', 'on', true);
  update public.customer_request_upload_requests set status = 'COMPLETED', completed_at = clock_timestamp()
  where upload_request_id = v_request.upload_request_id returning * into v_request;
  perform set_config('lws.customer_request_upload_transition', '', true);
  v_result := jsonb_build_object('state', 'COMPLETED', 'completed_at', v_request.completed_at);
  insert into lws_internal.customer_request_upload_operations values (
    p_idempotency_key, 'COMPLETE', v_fingerprint, v_request.upload_request_id, null, v_result, clock_timestamp()
  );
  return v_result;
end;
$$;

create function public.cleanup_expired_customer_request_uploads_v1(
  p_batch_size integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_operation lws_internal.customer_request_upload_operations%rowtype;
  v_fingerprint text;
  v_paths jsonb;
  v_request_count integer;
  v_file_count integer;
  v_result jsonb;
begin
  if p_idempotency_key is null or p_batch_size not between 1 and 500 then raise exception using errcode = '22023', message = 'INVALID_CLEANUP_REQUEST'; end if;
  v_fingerprint := lws_internal.customer_request_fingerprint_v1(jsonb_build_object('batchSize', p_batch_size));
  select * into v_operation from lws_internal.customer_request_upload_operations where idempotency_key = p_idempotency_key;
  if found then
    if v_operation.operation_type <> 'CLEANUP' or v_operation.request_fingerprint <> v_fingerprint then raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT'; end if;
    return v_operation.result_payload;
  end if;
  perform set_config('lws.customer_request_upload_transition', 'on', true);
  with cleanup_requests as (
    select upload_request_id from public.customer_request_upload_requests
    where (status = 'ACTIVE' and expires_at <= clock_timestamp())
       or (status = 'REVOKED' and exists (
         select 1 from public.customer_request_uploaded_files as prepared_file
         where prepared_file.upload_request_id = customer_request_upload_requests.upload_request_id
           and prepared_file.status = 'PREPARED'
       ))
    order by coalesce(revoked_at, expires_at) for update skip locked limit p_batch_size
  ), updated_requests as (
    update public.customer_request_upload_requests as request set status = 'EXPIRED', expired_at = clock_timestamp()
    from cleanup_requests
    where request.upload_request_id = cleanup_requests.upload_request_id and request.status = 'ACTIVE'
    returning request.upload_request_id
  ), updated_files as (
    update public.customer_request_uploaded_files as file set status = 'EXPIRED', expired_at = clock_timestamp()
    from cleanup_requests where file.upload_request_id = cleanup_requests.upload_request_id and file.status = 'PREPARED'
    returning file.storage_object_path
  )
  select (select count(*) from updated_requests), count(*), coalesce(jsonb_agg(storage_object_path), '[]'::jsonb)
  into v_request_count, v_file_count, v_paths from updated_files;
  perform set_config('lws.customer_request_upload_transition', '', true);
  v_result := jsonb_build_object('state', 'CLEANED', 'expired_request_count', v_request_count, 'expired_file_count', v_file_count, 'delete_paths', v_paths);
  insert into lws_internal.customer_request_upload_operations values (
    p_idempotency_key, 'CLEANUP', v_fingerprint, null, null, v_result, clock_timestamp()
  );
  return v_result;
end;
$$;

create or replace function public.get_customer_request_v1(p_request_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_authorization record;
  v_result jsonb;
begin
  select * into strict v_authorization
  from public.resolve_customer_request_authorization_v1(p_request_id, 'VIEW');

  select jsonb_build_object(
    'request_id', request.request_id,
    'request_reference', request.request_reference,
    'source', request.source,
    'request_type', request.request_type,
    'title', request.title,
    'description', request.description,
    'status', request.status,
    'priority', request.priority,
    'submitted_at', request.submitted_at,
    'revision', request.revision,
    'updated_at', request.updated_at,
    'upload_request', (
      select jsonb_build_object(
        'upload_request_id', upload.upload_request_id,
        'status', upload.status,
        'expires_at', upload.expires_at
      )
      from public.customer_request_upload_requests as upload
      where upload.customer_request_id = request.request_id
        and upload.status = 'ACTIVE'
        and upload.expires_at > clock_timestamp()
      order by upload.created_at desc
      limit 1
    )
  ) into strict v_result
  from public.customer_requests as request
  where request.request_id = p_request_id;

  return v_result;
end;
$$;

alter table public.customer_request_upload_requests enable row level security;
alter table public.customer_request_uploaded_files enable row level security;
alter table lws_internal.customer_request_upload_operations enable row level security;

revoke all privileges on table public.customer_request_upload_requests, public.customer_request_uploaded_files, lws_internal.customer_request_upload_operations
from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_customer_request_upload_request_v1(), lws_internal.guard_customer_request_uploaded_file_v1(), lws_internal.prevent_customer_request_upload_operation_mutation_v1()
from public, anon, authenticated, service_role;
revoke all on function public.create_customer_request_upload_request_v1(uuid,text,timestamptz,uuid), public.revoke_customer_request_upload_request_v1(uuid,text,uuid), public.resolve_customer_request_upload_capability_v1(text), public.prepare_customer_request_upload_v1(text,text,text,bigint,uuid), public.finalize_customer_request_uploaded_file_v1(text,uuid,text,bigint,text,boolean,uuid), public.list_customer_request_uploaded_files_v1(text), public.complete_customer_request_upload_request_v1(text,uuid), public.cleanup_expired_customer_request_uploads_v1(integer,uuid)
from public, anon, authenticated, service_role;

grant execute on function public.create_customer_request_upload_request_v1(uuid,text,timestamptz,uuid), public.revoke_customer_request_upload_request_v1(uuid,text,uuid)
to authenticated;
grant execute on function public.resolve_customer_request_upload_capability_v1(text), public.prepare_customer_request_upload_v1(text,text,text,bigint,uuid), public.finalize_customer_request_uploaded_file_v1(text,uuid,text,bigint,text,boolean,uuid), public.list_customer_request_uploaded_files_v1(text), public.complete_customer_request_upload_request_v1(text,uuid), public.cleanup_expired_customer_request_uploads_v1(integer,uuid)
to service_role;

comment on table public.customer_request_upload_requests is 'One expiring, revocable public upload capability bound to exactly one Customer Request; only its HMAC digest is stored.';
comment on table public.customer_request_uploaded_files is 'Private quarantine reservations and trusted finalize observations; browser filenames and paths never convey authority.';
comment on function public.prepare_customer_request_upload_v1(text,text,text,bigint,uuid) is 'Atomically reserves one server-derived quarantine path while counting PREPARED and ACCEPTED files against hard count and aggregate limits.';
comment on function public.finalize_customer_request_uploaded_file_v1(text,uuid,text,bigint,text,boolean,uuid) is 'Accepts a reserved object only after service-role Edge supplies trusted byte, MIME, SHA-256, and file-signature observations coherent with Storage metadata.';