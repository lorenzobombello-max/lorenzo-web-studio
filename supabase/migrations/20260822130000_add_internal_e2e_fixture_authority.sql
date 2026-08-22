alter table public.quote_requests
  add column record_classification text not null default 'production';

alter table public.quote_requests
  add constraint quote_requests_record_classification_valid
  check (record_classification in ('production', 'internal_e2e'));

create function public.prevent_quote_request_classification_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.record_classification is distinct from old.record_classification then
    raise exception using errcode = '23514', message = 'RECORD_CLASSIFICATION_IMMUTABLE';
  end if;
  return new;
end;
$$;

create trigger trg_quote_requests_classification_immutable
before update of record_classification on public.quote_requests
for each row execute function public.prevent_quote_request_classification_update();

create table public.internal_e2e_runs (
  id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null unique references public.quote_requests(id),
  idempotency_key uuid not null unique,
  request_fingerprint text not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  run_label text not null check (char_length(btrim(run_label)) between 1 and 120),
  status text not null default 'ACTIVE'
    check (status in ('ACTIVE', 'PASSED', 'FAILED', 'ABORTED', 'EXPIRED')),
  revision integer not null default 0 check (revision >= 0),
  created_by_operator_id uuid not null references public.commercial_operators(operator_id),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  finalized_at timestamptz,
  constraint internal_e2e_runs_expiry_valid check (expires_at > created_at),
  constraint internal_e2e_runs_terminal_shape check (
    (status = 'ACTIVE' and finalized_at is null)
    or (status <> 'ACTIVE' and finalized_at is not null)
  )
);

create table public.internal_e2e_run_events (
  id bigint generated always as identity primary key,
  run_id uuid not null references public.internal_e2e_runs(id),
  event_type text not null check (event_type in ('CREATED', 'FINALIZED')),
  resulting_status text not null check (resulting_status in ('ACTIVE', 'PASSED', 'FAILED', 'ABORTED', 'EXPIRED')),
  resulting_revision integer not null check (resulting_revision >= 0),
  actor_operator_id uuid not null references public.commercial_operators(operator_id),
  idempotency_key uuid not null,
  occurred_at timestamptz not null default clock_timestamp(),
  constraint internal_e2e_run_events_idempotency_unique unique (run_id, idempotency_key)
);

alter table public.internal_e2e_runs enable row level security;
alter table public.internal_e2e_run_events enable row level security;

create function public.prevent_internal_e2e_run_event_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception using errcode = '23514', message = 'INTERNAL_E2E_RUN_EVENT_IMMUTABLE';
end;
$$;

create trigger trg_internal_e2e_run_events_immutable
before update or delete on public.internal_e2e_run_events
for each row execute function public.prevent_internal_e2e_run_event_mutation();

create function public.create_internal_e2e_run_v1(
  p_idempotency_key uuid,
  p_request_fingerprint text,
  p_run_label text,
  p_ttl_minutes integer,
  p_approval_token_hash text,
  p_intake_access_token_hash text,
  p_admin_access_token_hash text
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
  v_request_id uuid;
  v_intake_id uuid;
  v_now timestamptz := clock_timestamp();
  v_expires_at timestamptz;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator from public.commercial_operators where auth_user_id = v_subject;
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;
  if v_operator.role <> 'owner' then raise exception using errcode = '42501', message = 'INTERNAL_E2E_OWNER_REQUIRED'; end if;
  if p_idempotency_key is null
     or p_request_fingerprint !~ '^[0-9a-f]{64}$'
     or char_length(btrim(coalesce(p_run_label, ''))) not between 1 and 120
     or p_ttl_minutes not between 5 and 240
     or p_approval_token_hash !~ '^[0-9a-f]{64}$'
     or p_intake_access_token_hash !~ '^[0-9a-f]{64}$'
     or p_admin_access_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_INTERNAL_E2E_REQUEST';
  end if;

  select * into v_run
  from public.internal_e2e_runs
  where idempotency_key = p_idempotency_key;
  if found then
    if v_run.request_fingerprint is distinct from p_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    select id into v_intake_id from public.quote_request_intakes where quote_request_id = v_run.quote_request_id;
    return jsonb_build_object(
      'run_id', v_run.id,
      'quote_request_id', v_run.quote_request_id,
      'intake_id', v_intake_id,
      'status', v_run.status,
      'revision', v_run.revision,
      'expires_at', v_run.expires_at,
      'was_created', false
    );
  end if;

  v_request_id := gen_random_uuid();
  v_intake_id := gen_random_uuid();
  v_expires_at := v_now + make_interval(mins => p_ttl_minutes);

  insert into public.quote_requests (
    id, name, email, website_type, budget, timing, description, privacy_consent,
    status, approval_token_hash, approval_token_expires_at, record_classification
  ) values (
    v_request_id, 'Internal E2E fixture', 'internal-e2e@invalid.local', 'Website op maat',
    'Interne test', 'Interne test', 'Server-authorized internal E2E fixture.', true,
    'approved', p_approval_token_hash, v_expires_at, 'internal_e2e'
  );

  insert into public.quote_request_intakes (
    id, quote_request_id, status, access_token_hash, access_token_expires_at, started_at
  ) values (
    v_intake_id, v_request_id, 'in_progress', p_intake_access_token_hash, v_expires_at, v_now
  );

  insert into public.internal_e2e_runs (
    quote_request_id, idempotency_key, request_fingerprint, run_label,
    created_by_operator_id, created_at, expires_at
  ) values (
    v_request_id, p_idempotency_key, p_request_fingerprint, btrim(p_run_label),
    v_operator.operator_id, v_now, v_expires_at
  ) returning * into v_run;

  insert into public.internal_e2e_run_events (
    run_id, event_type, resulting_status, resulting_revision, actor_operator_id, idempotency_key
  ) values (
    v_run.id, 'CREATED', 'ACTIVE', 0, v_operator.operator_id, p_idempotency_key
  );

  return jsonb_build_object(
    'run_id', v_run.id,
    'quote_request_id', v_request_id,
    'intake_id', v_intake_id,
    'status', v_run.status,
    'revision', v_run.revision,
    'expires_at', v_run.expires_at,
    'was_created', true
  );
end;
$$;

create function public.finalize_internal_e2e_run_v1(
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

revoke all on table public.internal_e2e_runs from public, anon, authenticated, service_role;
revoke all on table public.internal_e2e_run_events from public, anon, authenticated, service_role;
revoke all on function public.prevent_quote_request_classification_update() from public, anon, authenticated, service_role;
revoke all on function public.prevent_internal_e2e_run_event_mutation() from public, anon, authenticated, service_role;
revoke all on function public.create_internal_e2e_run_v1(uuid, text, text, integer, text, text, text) from public, anon, authenticated, service_role;
revoke all on function public.finalize_internal_e2e_run_v1(uuid, text, integer, uuid) from public, anon, authenticated, service_role;
grant execute on function public.create_internal_e2e_run_v1(uuid, text, text, integer, text, text, text) to authenticated;
grant execute on function public.finalize_internal_e2e_run_v1(uuid, text, integer, uuid) to authenticated;

comment on column public.quote_requests.record_classification is
  'Server-authoritative immutable business-record classification. Public creation defaults to production.';
comment on table public.internal_e2e_runs is
  'Owner-created production E2E fixture lifecycle. Finalization preserves evidence and revokes capabilities.';

create or replace function public.assign_application_reference_on_intake_submit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year smallint;
  v_sequence integer;
  v_request public.quote_requests%rowtype;
begin
  if old.status = new.status or new.status <> 'submitted' then return new; end if;

  select * into strict v_request from public.quote_requests where id = new.quote_request_id;
  if v_request.record_classification = 'internal_e2e' or v_request.application_reference is not null then
    return new;
  end if;

  v_year := extract(year from new.submitted_at at time zone 'Europe/Brussels')::smallint;
  insert into public.application_reference_counters as counter (reference_year, last_value)
  values (v_year, 1)
  on conflict (reference_year) do update set last_value = counter.last_value + 1
  returning last_value into v_sequence;
  if v_sequence > 9999 then
    raise exception using errcode = '22003', message = 'APPLICATION_REFERENCE_SEQUENCE_EXHAUSTED';
  end if;

  update public.quote_requests
  set application_reference = format('LWS-AAN-%s-%s', v_year, lpad(v_sequence::text, 4, '0'))
  where id = new.quote_request_id and application_reference is null;
  return new;
end;
$$;

alter function public.list_operator_applications_v1(integer, integer)
  rename to list_operator_applications_production_source_v1;
alter function public.get_operator_application_v1(uuid, text)
  rename to get_operator_application_production_source_v1;
alter function public.promote_operator_application_v1(uuid, uuid, text)
  rename to promote_operator_application_production_source_v1;

revoke all on function public.list_operator_applications_production_source_v1(integer, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.get_operator_application_production_source_v1(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.promote_operator_application_production_source_v1(uuid, uuid, text)
  from public, anon, authenticated, service_role;

create function public.assert_internal_e2e_application_reader_v1()
returns void
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
begin
  if v_subject is null then raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED'; end if;
  select * into v_operator from public.commercial_operators where auth_user_id = v_subject;
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status = 'DISABLED' then raise exception using errcode = '42501', message = 'OPERATOR_DISABLED'; end if;
  if v_operator.status = 'REVOKED' then raise exception using errcode = '42501', message = 'OPERATOR_REVOKED'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;
  if v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'APPLICATION_SCOPE_DENIED';
  end if;
end;
$$;

create function public.list_operator_applications_v1(
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
begin
  perform public.assert_internal_e2e_application_reader_v1();
  if p_limit is null or p_limit < 1 or p_limit > 200 or p_offset is null or p_offset < 0 then
    raise exception using errcode = '22023', message = 'INVALID_PAGINATION';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(application_row) order by application_row.submitted_at desc, application_row.quote_request_id)
    from (
      select
        qr.id as quote_request_id,
        qr.application_reference,
        qr.request_kind,
        qr.name,
        qr.company,
        qr.email,
        qr.website_type,
        qr.budget,
        qr.timing,
        case when qr.request_kind = 'website' then intake.status::text else null end as intake_status,
        case when qr.request_kind = 'website' then intake.submitted_at else qr.created_at end as submitted_at,
        acceptance.id as acceptance_id,
        acceptance.quotation_number,
        acceptance.accepted_at,
        project.project_id,
        project.current_state as project_state,
        project.revision as project_revision
      from public.quote_requests as qr
      left join public.quote_request_intakes as intake
        on intake.quote_request_id = qr.id and qr.request_kind = 'website'
      left join lateral (
        select accepted.id, accepted.quotation_number, accepted.accepted_at
        from public.quote_request_quotation_approvals as approval
        join public.quote_request_quotation_issuances as issuance on issuance.approval_id = approval.id
        join public.quote_request_quotation_acceptances as accepted on accepted.issuance_id = issuance.id
        where qr.request_kind = 'website' and approval.quote_request_id = qr.id
        order by accepted.accepted_at desc
        limit 1
      ) as acceptance on true
      left join public.commercial_projects as project on project.acceptance_id = acceptance.id
      where qr.record_classification = 'production'
        and ((qr.request_kind = 'website' and intake.status in ('submitted', 'reviewed'))
          or qr.request_kind = 'slimme_documentenflow')
      order by submitted_at desc, qr.id
      limit p_limit offset p_offset
    ) as application_row
  ), '[]'::jsonb);
end;
$$;

create function public.get_operator_application_v1(
  p_quote_request_id uuid default null,
  p_application_reference text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_classification text;
begin
  perform public.assert_internal_e2e_application_reader_v1();
  if (p_quote_request_id is null) = (p_application_reference is null) then
    raise exception using errcode = '22023', message = 'EXACTLY_ONE_APPLICATION_LOCATOR_REQUIRED';
  end if;
  if p_application_reference is not null and p_application_reference !~ '^LWS-AAN-[0-9]{4}-[0-9]{4}$' then
    raise exception using errcode = '22023', message = 'INVALID_APPLICATION_REFERENCE';
  end if;
  select record_classification into v_classification
  from public.quote_requests
  where (p_quote_request_id is null or id = p_quote_request_id)
    and (p_application_reference is null or application_reference = p_application_reference);
  if v_classification = 'internal_e2e' then
    raise exception using errcode = 'P0001', message = 'APPLICATION_NOT_FOUND';
  end if;
  return public.get_operator_application_production_source_v1(p_quote_request_id, p_application_reference);
end;
$$;

create function public.promote_operator_application_v1(
  p_idempotency_key uuid,
  p_quote_request_id uuid default null,
  p_application_reference text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_classification text;
begin
  perform public.assert_internal_e2e_application_reader_v1();
  if p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if (p_quote_request_id is null) = (p_application_reference is null) then
    raise exception using errcode = '22023', message = 'EXACTLY_ONE_APPLICATION_LOCATOR_REQUIRED';
  end if;
  select record_classification into v_classification
  from public.quote_requests
  where (p_quote_request_id is null or id = p_quote_request_id)
    and (p_application_reference is null or application_reference = p_application_reference);
  if v_classification = 'internal_e2e' then
    raise exception using errcode = 'P0001', message = 'INTERNAL_E2E_PROMOTION_DENIED';
  end if;
  return public.promote_operator_application_production_source_v1(
    p_idempotency_key, p_quote_request_id, p_application_reference
  );
end;
$$;

create function public.prevent_internal_e2e_quotation_write()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if exists (
    select 1 from public.quote_requests
    where id = new.quote_request_id and record_classification = 'internal_e2e'
  ) then
    raise exception using errcode = 'P0001', message = 'INTERNAL_E2E_QUOTATION_DENIED';
  end if;
  return new;
end;
$$;

create trigger trg_quotation_approval_drafts_deny_internal_e2e
before insert or update on public.quote_request_quotation_approval_drafts
for each row execute function public.prevent_internal_e2e_quotation_write();
create trigger trg_quotation_approvals_deny_internal_e2e
before insert or update on public.quote_request_quotation_approvals
for each row execute function public.prevent_internal_e2e_quotation_write();

revoke all on function public.assert_internal_e2e_application_reader_v1() from public, anon, authenticated, service_role;
revoke all on function public.prevent_internal_e2e_quotation_write() from public, anon, authenticated, service_role;
revoke all on function public.list_operator_applications_v1(integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.get_operator_application_v1(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.promote_operator_application_v1(uuid, uuid, text) from public, anon, authenticated, service_role;
grant execute on function public.list_operator_applications_v1(integer, integer) to authenticated;
grant execute on function public.get_operator_application_v1(uuid, text) to authenticated;
grant execute on function public.promote_operator_application_v1(uuid, uuid, text) to authenticated;

create function public.get_quote_request_email_classification_v1(p_job_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select qr.record_classification
  from public.quote_request_email_jobs job
  join public.quote_requests qr on qr.id = job.quote_request_id
  where job.id = p_job_id
$$;

revoke all on function public.get_quote_request_email_classification_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_quote_request_email_classification_v1(uuid) to service_role;