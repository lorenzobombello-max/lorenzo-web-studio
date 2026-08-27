create table lws_internal.internal_e2e_accepted_file_cleanup_authorizations (
  cleanup_authorization_id uuid primary key default gen_random_uuid(),
  idempotency_key uuid not null unique,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  run_id uuid not null references public.internal_e2e_runs(id),
  customer_request_id uuid not null references public.customer_requests(request_id),
  upload_request_id uuid not null references public.customer_request_upload_requests(upload_request_id),
  uploaded_file_id uuid not null unique references public.customer_request_uploaded_files(uploaded_file_id),
  actor_operator_id uuid not null references public.commercial_operators(operator_id),
  result_payload jsonb not null check (
    jsonb_typeof(result_payload) = 'object'
    and not (result_payload ?| array['token', 'token_digest', 'signed_url', 'credential', 'secret', 'service_role_key'])
  ),
  authorized_at timestamptz not null default clock_timestamp()
);

create table lws_internal.internal_e2e_accepted_file_cleanup_finalizations (
  idempotency_key uuid primary key,
  cleanup_authorization_id uuid not null unique
    references lws_internal.internal_e2e_accepted_file_cleanup_authorizations(cleanup_authorization_id),
  actor_operator_id uuid not null references public.commercial_operators(operator_id),
  result_payload jsonb not null check (
    jsonb_typeof(result_payload) = 'object'
    and not (result_payload ?| array['token', 'token_digest', 'signed_url', 'credential', 'secret', 'service_role_key'])
  ),
  finalized_at timestamptz not null default clock_timestamp()
);

create function lws_internal.prevent_internal_e2e_file_cleanup_audit_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'INTERNAL_E2E_FILE_CLEANUP_AUDIT_APPEND_ONLY';
end;
$$;

create trigger trg_internal_e2e_file_cleanup_authorizations_immutable
before update or delete on lws_internal.internal_e2e_accepted_file_cleanup_authorizations
for each row execute function lws_internal.prevent_internal_e2e_file_cleanup_audit_mutation_v1();

create trigger trg_internal_e2e_file_cleanup_finalizations_immutable
before update or delete on lws_internal.internal_e2e_accepted_file_cleanup_finalizations
for each row execute function lws_internal.prevent_internal_e2e_file_cleanup_audit_mutation_v1();

create function public.authorize_internal_e2e_accepted_file_cleanup_v1(
  p_run_id uuid,
  p_request_id uuid,
  p_upload_request_id uuid,
  p_uploaded_file_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_file public.customer_request_uploaded_files%rowtype;
  v_upload_request_status text;
  v_existing lws_internal.internal_e2e_accepted_file_cleanup_authorizations%rowtype;
  v_fingerprint text;
  v_authorization_id uuid := gen_random_uuid();
  v_result jsonb;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;
  if not found then
    raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR';
  end if;
  if v_operator.status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;
  if v_operator.role <> 'owner' then
    raise exception using errcode = '42501', message = 'INTERNAL_E2E_OWNER_REQUIRED';
  end if;
  if p_run_id is null or p_request_id is null or p_upload_request_id is null
      or p_uploaded_file_id is null or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'INVALID_INTERNAL_E2E_FILE_CLEANUP_REQUEST';
  end if;

  v_fingerprint := lws_internal.customer_request_fingerprint_v1(jsonb_build_object(
    'authority', 'INTERNAL_E2E_ACCEPTED_FILE_CLEANUP_V1',
    'runId', p_run_id,
    'requestId', p_request_id,
    'uploadRequestId', p_upload_request_id,
    'uploadedFileId', p_uploaded_file_id
  ));

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing
  from lws_internal.internal_e2e_accepted_file_cleanup_authorizations
  where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed', true);
  end if;

  select uploaded_file.* into v_file
  from public.internal_e2e_runs as run
  join public.quote_requests as quote_request
    on quote_request.id = run.quote_request_id
   and quote_request.record_classification = 'internal_e2e'
  join public.customer_requests as customer_request
    on customer_request.internal_e2e_run_id = run.id
   and customer_request.request_id = p_request_id
  join public.customer_request_upload_requests as upload_request
    on upload_request.customer_request_id = customer_request.request_id
   and upload_request.upload_request_id = p_upload_request_id
  join public.customer_request_uploaded_files as uploaded_file
    on uploaded_file.customer_request_id = customer_request.request_id
   and uploaded_file.upload_request_id = upload_request.upload_request_id
   and uploaded_file.uploaded_file_id = p_uploaded_file_id
  where run.id = p_run_id
    and run.status = 'ACTIVE'
    and run.expires_at > clock_timestamp()
  for update of uploaded_file, upload_request;
  if not found then
    raise exception using errcode = '42501', message = 'INTERNAL_E2E_CLEANUP_BINDING_REQUIRED';
  end if;
  select status into strict v_upload_request_status
  from public.customer_request_upload_requests
  where upload_request_id = p_upload_request_id;
  if v_upload_request_status not in ('REVOKED', 'COMPLETED') then
    raise exception using errcode = 'P0001', message = 'INTERNAL_E2E_UPLOAD_REQUEST_TERMINAL_REQUIRED';
  end if;
  if v_file.status = 'DELETED' then
    raise exception using errcode = 'P0001', message = 'INTERNAL_E2E_FILE_ALREADY_DELETED';
  end if;
  if v_file.status <> 'ACCEPTED' then
    raise exception using errcode = 'P0001', message = 'ACCEPTED_INTERNAL_E2E_FILE_REQUIRED';
  end if;
  if exists (
    select 1
    from lws_internal.internal_e2e_accepted_file_cleanup_authorizations
    where uploaded_file_id = v_file.uploaded_file_id
  ) then
    raise exception using errcode = 'P0001', message = 'INTERNAL_E2E_FILE_CLEANUP_ALREADY_AUTHORIZED';
  end if;

  v_result := jsonb_build_object(
    'state', 'AUTHORIZED',
    'cleanup_authorization_id', v_authorization_id,
    'run_id', p_run_id,
    'request_id', p_request_id,
    'upload_request_id', p_upload_request_id,
    'uploaded_file_id', v_file.uploaded_file_id,
    'storage_bucket_id', v_file.storage_bucket_id,
    'storage_object_path', v_file.storage_object_path,
    'replayed', false
  );
  insert into lws_internal.internal_e2e_accepted_file_cleanup_authorizations(
    cleanup_authorization_id, idempotency_key, request_fingerprint, run_id,
    customer_request_id, upload_request_id, uploaded_file_id,
    actor_operator_id, result_payload
  ) values (
    v_authorization_id, p_idempotency_key, v_fingerprint, p_run_id,
    p_request_id, p_upload_request_id, p_uploaded_file_id,
    v_operator.operator_id, v_result
  );
  return v_result;
end;
$$;

create function public.finalize_internal_e2e_accepted_file_cleanup_v1(
  p_cleanup_authorization_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, storage, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_authorization lws_internal.internal_e2e_accepted_file_cleanup_authorizations%rowtype;
  v_existing lws_internal.internal_e2e_accepted_file_cleanup_finalizations%rowtype;
  v_file public.customer_request_uploaded_files%rowtype;
  v_result jsonb;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;
  if not found then
    raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR';
  end if;
  if v_operator.status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;
  if v_operator.role <> 'owner' then
    raise exception using errcode = '42501', message = 'INTERNAL_E2E_OWNER_REQUIRED';
  end if;
  if p_cleanup_authorization_id is null or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'INVALID_INTERNAL_E2E_FILE_CLEANUP_FINALIZATION';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing
  from lws_internal.internal_e2e_accepted_file_cleanup_finalizations
  where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.cleanup_authorization_id <> p_cleanup_authorization_id then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed', true);
  end if;

  select * into v_authorization
  from lws_internal.internal_e2e_accepted_file_cleanup_authorizations
  where cleanup_authorization_id = p_cleanup_authorization_id;
  if not found then
    raise exception using errcode = '42501', message = 'INTERNAL_E2E_CLEANUP_AUTHORIZATION_REQUIRED';
  end if;
  if exists (
    select 1
    from lws_internal.internal_e2e_accepted_file_cleanup_finalizations
    where cleanup_authorization_id = p_cleanup_authorization_id
  ) then
    raise exception using errcode = 'P0001', message = 'INTERNAL_E2E_FILE_CLEANUP_ALREADY_FINALIZED';
  end if;

  select * into v_file
  from public.customer_request_uploaded_files
  where uploaded_file_id = v_authorization.uploaded_file_id
    and upload_request_id = v_authorization.upload_request_id
    and customer_request_id = v_authorization.customer_request_id
  for update;
  if not found or v_file.status <> 'ACCEPTED' then
    raise exception using errcode = 'P0001', message = 'ACCEPTED_INTERNAL_E2E_FILE_REQUIRED';
  end if;
  if exists (
    select 1 from storage.objects
    where bucket_id = v_file.storage_bucket_id
      and name = v_file.storage_object_path
  ) then
    raise exception using errcode = 'P0001', message = 'INTERNAL_E2E_STORAGE_OBJECT_STILL_EXISTS';
  end if;

  perform set_config('lws.customer_request_upload_transition', 'on', true);
  update public.customer_request_uploaded_files
  set status = 'DELETED', deleted_at = clock_timestamp()
  where uploaded_file_id = v_file.uploaded_file_id
    and status = 'ACCEPTED'
  returning * into v_file;
  perform set_config('lws.customer_request_upload_transition', '', true);
  if not found then
    raise exception using errcode = 'P0001', message = 'ACCEPTED_INTERNAL_E2E_FILE_REQUIRED';
  end if;

  v_result := jsonb_build_object(
    'state', 'DELETED',
    'cleanup_authorization_id', v_authorization.cleanup_authorization_id,
    'run_id', v_authorization.run_id,
    'request_id', v_authorization.customer_request_id,
    'upload_request_id', v_authorization.upload_request_id,
    'uploaded_file_id', v_authorization.uploaded_file_id,
    'deleted_at', v_file.deleted_at,
    'replayed', false
  );
  insert into lws_internal.internal_e2e_accepted_file_cleanup_finalizations(
    idempotency_key, cleanup_authorization_id, actor_operator_id, result_payload
  ) values (
    p_idempotency_key, p_cleanup_authorization_id, v_operator.operator_id, v_result
  );
  return v_result;
end;
$$;

alter table lws_internal.internal_e2e_accepted_file_cleanup_authorizations enable row level security;
alter table lws_internal.internal_e2e_accepted_file_cleanup_finalizations enable row level security;

revoke all privileges on table
  lws_internal.internal_e2e_accepted_file_cleanup_authorizations,
  lws_internal.internal_e2e_accepted_file_cleanup_finalizations
from public, anon, authenticated, service_role;
revoke all on function lws_internal.prevent_internal_e2e_file_cleanup_audit_mutation_v1()
from public, anon, authenticated, service_role;
revoke all on function public.authorize_internal_e2e_accepted_file_cleanup_v1(uuid,uuid,uuid,uuid,uuid)
from public, anon, authenticated, service_role;
revoke all on function public.finalize_internal_e2e_accepted_file_cleanup_v1(uuid,uuid)
from public, anon, authenticated, service_role;
grant execute on function public.authorize_internal_e2e_accepted_file_cleanup_v1(uuid,uuid,uuid,uuid,uuid)
to authenticated;
grant execute on function public.finalize_internal_e2e_accepted_file_cleanup_v1(uuid,uuid)
to authenticated;

comment on table lws_internal.internal_e2e_accepted_file_cleanup_authorizations is
  'Append-only Owner authorization audit for deleting exactly one accepted internal E2E quarantine object.';
comment on table lws_internal.internal_e2e_accepted_file_cleanup_finalizations is
  'Append-only proof that exact Storage object absence preceded the retained file row transition to DELETED.';
comment on function public.authorize_internal_e2e_accepted_file_cleanup_v1(uuid,uuid,uuid,uuid,uuid) is
  'Owner-only synthetic binding check that returns one server-derived private Storage object identity.';
comment on function public.finalize_internal_e2e_accepted_file_cleanup_v1(uuid,uuid) is
  'Owner-only ACCEPTED-to-DELETED transition after authoritative verification that the exact object is absent.';