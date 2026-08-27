alter table public.internal_e2e_runs
  add constraint internal_e2e_runs_id_quote_request_unique
  unique (id, quote_request_id);

alter table public.customer_requests
  alter column customer_id drop not null,
  alter column project_id drop not null,
  add column internal_e2e_run_id uuid;

alter table public.customer_requests
  add constraint customer_requests_internal_e2e_binding_fk
    foreign key (internal_e2e_run_id, quote_request_id)
    references public.internal_e2e_runs(id, quote_request_id),
  add constraint customer_requests_internal_e2e_run_unique
    unique (internal_e2e_run_id),
  add constraint customer_requests_authority_binding_valid check (
    (
      internal_e2e_run_id is null
      and customer_id is not null
      and project_id is not null
    )
    or
    (
      internal_e2e_run_id is not null
      and customer_id is null
      and project_id is null
      and source_feedback_id is null
      and linked_change_order_id is null
      and source = 'OPERATOR'
      and submitter_type = 'OPERATOR'
      and request_type = 'FILE_DELIVERY'
      and priority = 'LOW'
      and title = 'LWS-SMOKE-TEST-UPLOAD-LINK-20260827'
      and description = 'Synthetic internal Customer Request Upload Link capability lifecycle smoke fixture. No customer data and no file upload.'
    )
  );

create function public.create_customer_request_smoke_fixture_v1(
  p_run_id uuid,
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
  v_run public.internal_e2e_runs%rowtype;
  v_old lws_internal.customer_request_commands%rowtype;
  v_fingerprint text;
  v_request_id uuid := gen_random_uuid();
  v_year smallint;
  v_sequence integer;
  v_reference text;
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
  if p_run_id is null or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST_SMOKE_FIXTURE';
  end if;

  select run.* into v_run
  from public.internal_e2e_runs as run
  join public.quote_requests as request
    on request.id = run.quote_request_id
   and request.record_classification = 'internal_e2e'
  where run.id = p_run_id
    and run.status = 'ACTIVE'
    and run.expires_at > clock_timestamp()
  for update of run;
  if not found then
    raise exception using errcode = 'P0001', message = 'ACTIVE_INTERNAL_E2E_RUN_REQUIRED';
  end if;

  v_fingerprint := lws_internal.customer_request_fingerprint_v1(jsonb_build_object(
    'authority', 'CUSTOMER_REQUEST_SMOKE_FIXTURE_V1',
    'run_id', v_run.id,
    'quote_request_id', v_run.quote_request_id
  ));

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_old
  from lws_internal.customer_request_commands
  where idempotency_key = p_idempotency_key;
  if found then
    if v_old.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_old.result_payload || jsonb_build_object('replayed', true);
  end if;
  if exists (
    select 1 from public.customer_requests
    where internal_e2e_run_id = v_run.id
  ) then
    raise exception using errcode = 'P0001', message = 'CUSTOMER_REQUEST_SMOKE_FIXTURE_EXISTS';
  end if;

  v_year := extract(year from clock_timestamp() at time zone 'Europe/Brussels')::smallint;
  insert into lws_internal.customer_request_reference_counters as counter(reference_year, last_value)
  values (v_year, 1)
  on conflict (reference_year) do update
    set last_value = counter.last_value + 1
  returning last_value into v_sequence;
  if v_sequence > 9999 then
    raise exception using errcode = '22003', message = 'CUSTOMER_REQUEST_REFERENCE_SEQUENCE_EXHAUSTED';
  end if;
  v_reference := format('LWS-VRZ-%s-%s', v_year, lpad(v_sequence::text, 4, '0'));

  insert into public.customer_requests(
    request_id, request_reference, quote_request_id, customer_id, project_id,
    internal_e2e_run_id, source, request_type, title, description, status,
    priority, submitted_at, submitter_type
  ) values (
    v_request_id, v_reference, v_run.quote_request_id, null, null,
    v_run.id, 'OPERATOR', 'FILE_DELIVERY',
    'LWS-SMOKE-TEST-UPLOAD-LINK-20260827',
    'Synthetic internal Customer Request Upload Link capability lifecycle smoke fixture. No customer data and no file upload.',
    'NEW', 'LOW', clock_timestamp(), 'OPERATOR'
  );

  insert into public.customer_request_events(request_id, event_type, request_revision, payload)
  values (
    v_request_id, 'CREATED', 0,
    jsonb_build_object(
      'source', 'OPERATOR',
      'request_type', 'FILE_DELIVERY',
      'submitter_type', 'OPERATOR',
      'fixture', 'INTERNAL_E2E'
    )
  );

  v_result := jsonb_build_object(
    'run_id', v_run.id,
    'request_id', v_request_id,
    'request_reference', v_reference,
    'status', 'NEW',
    'revision', 0,
    'replayed', false
  );
  insert into lws_internal.customer_request_commands(
    idempotency_key, request_id, command_type, request_fingerprint, result_payload
  ) values (
    p_idempotency_key, v_request_id, 'CREATE_SMOKE_FIXTURE', v_fingerprint, v_result
  );
  return v_result;
end;
$$;

revoke all on function public.create_customer_request_smoke_fixture_v1(uuid, uuid)
from public, anon, authenticated, service_role;

create function public.create_customer_request_smoke_fixture_v1(
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
  v_old lws_internal.customer_request_commands%rowtype;
  v_run_result jsonb;
  v_request_fingerprint text;
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
  if p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST_SMOKE_FIXTURE';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_old
  from lws_internal.customer_request_commands
  where idempotency_key = p_idempotency_key;
  if found then
    if v_old.command_type <> 'CREATE_SMOKE_FIXTURE'
       or not exists (
         select 1
         from public.customer_requests as request
         where request.request_id = v_old.request_id
           and request.request_id::text = v_old.result_payload->>'request_id'
           and request.internal_e2e_run_id::text = v_old.result_payload->>'run_id'
       ) then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_old.result_payload || jsonb_build_object('replayed', true);
  end if;

  v_request_fingerprint := lws_internal.customer_request_fingerprint_v1(jsonb_build_object(
    'contract_version', 1,
    'run_label', 'LWS-SMOKE-TEST-UPLOAD-LINK-20260827',
    'ttl_minutes', 60
  ));
  v_run_result := public.create_internal_e2e_run_v1(
    p_idempotency_key,
    v_request_fingerprint,
    'LWS-SMOKE-TEST-UPLOAD-LINK-20260827',
    60,
    encode(extensions.digest(extensions.gen_random_bytes(32), 'sha256'), 'hex'),
    encode(extensions.digest(extensions.gen_random_bytes(32), 'sha256'), 'hex'),
    encode(extensions.digest(extensions.gen_random_bytes(32), 'sha256'), 'hex')
  );

  return public.create_customer_request_smoke_fixture_v1(
    (v_run_result->>'run_id')::uuid,
    p_idempotency_key
  );
end;
$$;

revoke all on function public.create_customer_request_smoke_fixture_v1(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.create_customer_request_smoke_fixture_v1(uuid)
to authenticated;

create or replace function public.finalize_internal_e2e_run_v1(
  p_run_id uuid,
  p_terminal_status text,
  p_expected_revision integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_run public.internal_e2e_runs%rowtype;
  v_existing_event public.internal_e2e_run_events%rowtype;
  v_record_classification text;
  v_now timestamptz := clock_timestamp();
begin
  if v_subject is null then raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED'; end if;
  select * into v_operator from public.commercial_operators where auth_user_id = v_subject;
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;
  if v_operator.role <> 'owner' then raise exception using errcode = '42501', message = 'INTERNAL_E2E_OWNER_REQUIRED'; end if;
  if p_run_id is null or p_terminal_status not in ('PASSED', 'FAILED', 'ABORTED', 'EXPIRED')
     or p_expected_revision is null or p_expected_revision < 0 or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'INVALID_INTERNAL_E2E_REQUEST';
  end if;

  select * into v_run from public.internal_e2e_runs where id = p_run_id for update;
  if not found then raise exception using errcode = 'P0001', message = 'INTERNAL_E2E_RUN_NOT_FOUND'; end if;

  select record_classification into v_record_classification
  from public.quote_requests
  where id = v_run.quote_request_id
  for update;
  if not found or v_record_classification is distinct from 'internal_e2e' then
    raise exception using errcode = 'P0001', message = 'INTERNAL_E2E_CLASSIFICATION_REQUIRED';
  end if;

  select * into v_existing_event
  from public.internal_e2e_run_events
  where run_id = p_run_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing_event.resulting_status is distinct from p_terminal_status then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('run_id', v_run.id, 'status', v_run.status, 'revision', v_run.revision, 'finalized_at', v_run.finalized_at, 'was_finalized', false);
  end if;
  if v_run.status <> 'ACTIVE' then raise exception using errcode = 'P0001', message = 'INTERNAL_E2E_RUN_FINALIZED'; end if;
  if v_run.revision <> p_expected_revision then raise exception using errcode = 'P0001', message = 'CONCURRENT_MODIFICATION'; end if;

  if exists (
    select 1
    from public.customer_requests as request
    where request.internal_e2e_run_id = v_run.id
      and (
        request.status <> 'CANCELLED'
        or exists (
          select 1
          from public.customer_request_upload_requests as upload_request
          where upload_request.customer_request_id = request.request_id
            and upload_request.status = 'ACTIVE'
        )
        or exists (
          select 1
          from public.customer_request_uploaded_files as uploaded_file
          where uploaded_file.customer_request_id = request.request_id
            and uploaded_file.status in ('PREPARED', 'ACCEPTED')
        )
      )
  ) then
    raise exception using errcode = 'P0001', message = 'INTERNAL_E2E_CUSTOMER_REQUEST_CLEANUP_REQUIRED';
  end if;

  update public.internal_e2e_runs
  set status = p_terminal_status, revision = revision + 1, finalized_at = v_now
  where id = p_run_id
  returning * into v_run;

  update public.quote_request_intakes
  set access_token_revoked_at = coalesce(access_token_revoked_at, v_now),
      admin_access_token_revoked_at = case
        when admin_access_token_hash is null then null
        else coalesce(admin_access_token_revoked_at, v_now)
      end
  where quote_request_id = v_run.quote_request_id;
  update public.quote_requests
  set approval_token_hash = null, approval_token_expires_at = null
  where id = v_run.quote_request_id;

  insert into public.internal_e2e_run_events (
    run_id, event_type, resulting_status, resulting_revision, actor_operator_id, idempotency_key
  ) values (
    v_run.id, 'FINALIZED', v_run.status, v_run.revision, v_operator.operator_id, p_idempotency_key
  );

  return jsonb_build_object('run_id', v_run.id, 'status', v_run.status, 'revision', v_run.revision, 'finalized_at', v_run.finalized_at, 'was_finalized', true);
end;
$$;

comment on column public.customer_requests.internal_e2e_run_id is
  'Exclusive server-authored binding for synthetic Customer Request smoke fixtures; production requests remain commercially bound.';
comment on function public.create_customer_request_smoke_fixture_v1(uuid, uuid) is
  'Private run-bound helper for one fixed synthetic Customer Request inside an ACTIVE internal E2E run.';
comment on function public.create_customer_request_smoke_fixture_v1(uuid) is
  'Owner-only atomic creation and terminal-state replay of one fixed internal E2E Customer Request smoke fixture.';