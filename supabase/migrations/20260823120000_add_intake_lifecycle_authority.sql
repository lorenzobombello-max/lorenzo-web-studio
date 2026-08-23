alter table public.quote_request_intakes
  add column access_state text not null default 'ACTIVE',
  add column lifecycle_revision bigint not null default 0;

alter table public.quote_request_intakes
  add constraint quote_request_intakes_access_state_valid
    check (access_state in ('ACTIVE', 'INTERRUPTED', 'CANCELLED')),
  add constraint quote_request_intakes_lifecycle_revision_nonnegative
    check (lifecycle_revision >= 0);

create table public.quote_request_intake_lifecycle_events (
  id bigint generated always as identity primary key,
  intake_id uuid not null references public.quote_request_intakes(id) on delete cascade,
  event_type text not null check (event_type in ('INTERRUPTED', 'RESUMED', 'CANCELLED', 'REACTIVATED')),
  previous_access_state text not null check (previous_access_state in ('ACTIVE', 'INTERRUPTED', 'CANCELLED')),
  new_access_state text not null check (new_access_state in ('ACTIVE', 'INTERRUPTED', 'CANCELLED')),
  previous_expires_at timestamptz not null,
  new_expires_at timestamptz not null,
  actor_operator_id uuid not null references public.commercial_operators(operator_id),
  reason text not null check (char_length(btrim(reason)) between 1 and 500),
  occurred_at timestamptz not null default clock_timestamp(),
  idempotency_key uuid not null,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  evidence jsonb not null default '{}'::jsonb,
  constraint quote_request_intake_lifecycle_events_idempotency_key
    unique (intake_id, idempotency_key),
  constraint quote_request_intake_lifecycle_events_evidence_safe
    check (
      jsonb_typeof(evidence) = 'object'
      and not (evidence ?| array[
        'token', 'access_token', 'access_token_hash', 'admin_access_token_hash',
        'approval_token', 'approval_token_hash', 'service_role_key'
      ])
    ),
  constraint quote_request_intake_lifecycle_events_transition_valid
    check (
      (
        event_type = 'INTERRUPTED'
        and previous_access_state = 'ACTIVE'
        and new_access_state = 'INTERRUPTED'
        and previous_expires_at = new_expires_at
        and previous_expires_at > occurred_at
      )
      or (
        event_type = 'RESUMED'
        and previous_access_state = 'INTERRUPTED'
        and new_access_state = 'ACTIVE'
        and previous_expires_at = new_expires_at
        and previous_expires_at > occurred_at
      )
      or (
        event_type = 'CANCELLED'
        and previous_access_state in ('ACTIVE', 'INTERRUPTED')
        and new_access_state = 'CANCELLED'
        and previous_expires_at = new_expires_at
        and previous_expires_at > occurred_at
      )
      or (
        event_type = 'REACTIVATED'
        and previous_access_state in ('ACTIVE', 'INTERRUPTED')
        and new_access_state = 'ACTIVE'
        and previous_expires_at <= occurred_at
        and new_expires_at > occurred_at
      )
    )
);

create index idx_quote_request_intake_lifecycle_events_intake
  on public.quote_request_intake_lifecycle_events (intake_id, occurred_at desc, id desc);

create function public.prevent_quote_request_intake_lifecycle_event_mutation()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'INTAKE_LIFECYCLE_EVENT_IMMUTABLE';
end;
$$;

create trigger trg_quote_request_intake_lifecycle_events_immutable
before update or delete on public.quote_request_intake_lifecycle_events
for each row execute function public.prevent_quote_request_intake_lifecycle_event_mutation();

create function public.quote_request_intake_default_expires_at_v1(
  p_created_at timestamptz
)
returns timestamptz
language sql
immutable
set search_path = pg_catalog
as $$
  select p_created_at + interval '7 days'
$$;

create function public.resolve_quote_request_intake_effective_access_v1(
  p_access_state text,
  p_access_token_expires_at timestamptz,
  p_server_now timestamptz default clock_timestamp()
)
returns text
language plpgsql
stable
set search_path = pg_catalog
as $$
begin
  if p_access_state not in ('ACTIVE', 'INTERRUPTED', 'CANCELLED')
     or p_access_token_expires_at is null
     or p_server_now is null then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_ACCESS_STATE';
  end if;

  if p_access_state = 'CANCELLED' then
    return 'CANCELLED';
  elsif p_access_token_expires_at <= p_server_now then
    return 'EXPIRED';
  elsif p_access_state = 'INTERRUPTED' then
    return 'INTERRUPTED';
  end if;

  return 'ACTIVE';
end;
$$;

create or replace function public.create_quote_request_intake(
  p_approval_token_hash text,
  p_access_token_hash text
)
returns table (
  outcome text,
  intake_id uuid,
  access_token_expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.quote_requests%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_created_at timestamptz;
begin
  if p_approval_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_APPROVAL_TOKEN_HASH';
  end if;

  if p_access_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_ACCESS_TOKEN_HASH';
  end if;

  select *
    into v_request
    from public.quote_requests
    where approval_token_hash = p_approval_token_hash
    for update;

  if not found
     or v_request.status <> 'approved'
     or v_request.approval_token_expires_at is null
     or v_request.approval_token_expires_at <= now() then
    return query select 'not_allowed'::text, null::uuid, null::timestamptz;
    return;
  end if;

  select *
    into v_intake
    from public.quote_request_intakes
    where quote_request_id = v_request.id;

  if found then
    return query select 'already_exists'::text, v_intake.id, v_intake.access_token_expires_at;
    return;
  end if;

  v_created_at := clock_timestamp();

  insert into public.quote_request_intakes (
    quote_request_id,
    status,
    access_token_hash,
    access_token_expires_at,
    access_token_revoked_at,
    created_at,
    updated_at
  ) values (
    v_request.id,
    'invited',
    p_access_token_hash,
    public.quote_request_intake_default_expires_at_v1(v_created_at),
    null,
    v_created_at,
    v_created_at
  )
  returning * into v_intake;

  return query select 'created'::text, v_intake.id, v_intake.access_token_expires_at;
exception
  when unique_violation then
    select *
      into v_intake
      from public.quote_request_intakes
      where quote_request_id = v_request.id;

    if not found then
      raise;
    end if;

    return query select 'already_exists'::text, v_intake.id, v_intake.access_token_expires_at;
end;
$$;

create or replace function public.create_quote_request_intake_invitation(
  p_approval_token_hash text,
  p_access_token_hash text,
  p_encrypted_token text
)
returns table (
  outcome text,
  request_id uuid,
  request_name text,
  request_company text,
  request_email text,
  intake_id uuid,
  access_token_expires_at timestamptz,
  invitation_job_id uuid,
  invitation_job_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.quote_requests%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_job public.quote_request_email_jobs%rowtype;
  v_created_at timestamptz;
begin
  if p_approval_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_APPROVAL_TOKEN_HASH';
  end if;
  if p_access_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_ACCESS_TOKEN_HASH';
  end if;
  if p_encrypted_token !~ '^v1\.[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{40,}$' then
    raise exception using errcode = '22023', message = 'INVALID_ENCRYPTED_TOKEN';
  end if;

  select *
    into v_request
    from public.quote_requests
    where approval_token_hash = p_approval_token_hash
    for update;

  if not found
     or v_request.status <> 'approved'
     or v_request.approval_token_expires_at is null
     or v_request.approval_token_expires_at <= clock_timestamp() then
    return query select
      'not_allowed'::text,
      null::uuid, null::text, null::text, null::text,
      null::uuid, null::timestamptz, null::uuid, null::text;
    return;
  end if;

  select *
    into v_intake
    from public.quote_request_intakes
    where quote_request_id = v_request.id;

  if found then
    select *
      into v_job
      from public.quote_request_email_jobs
      where quote_request_id = v_request.id
        and kind = 'intake_invitation';

    return query select
      case when found then 'already_invited'::text else 'not_deliverable'::text end,
      v_request.id,
      v_request.name,
      v_request.company,
      v_request.email,
      v_intake.id,
      v_intake.access_token_expires_at,
      v_job.id,
      v_job.status::text;
    return;
  end if;

  v_created_at := clock_timestamp();

  insert into public.quote_request_intakes (
    quote_request_id,
    status,
    access_token_hash,
    access_token_expires_at,
    access_token_revoked_at,
    created_at,
    updated_at
  ) values (
    v_request.id,
    'invited',
    p_access_token_hash,
    public.quote_request_intake_default_expires_at_v1(v_created_at),
    null,
    v_created_at,
    v_created_at
  )
  returning * into v_intake;

  insert into public.quote_request_email_jobs (
    quote_request_id,
    kind,
    encrypted_payload
  ) values (
    v_request.id,
    'intake_invitation',
    p_encrypted_token
  )
  returning * into v_job;

  return query select
    'invitation_created'::text,
    v_request.id,
    v_request.name,
    v_request.company,
    v_request.email,
    v_intake.id,
    v_intake.access_token_expires_at,
    v_job.id,
    v_job.status::text;
end;
$$;

alter table public.quote_request_intake_lifecycle_events enable row level security;
alter table public.quote_request_intake_lifecycle_events force row level security;

revoke all privileges
on table public.quote_request_intake_lifecycle_events
from public, anon, authenticated, service_role;

revoke all
on function public.prevent_quote_request_intake_lifecycle_event_mutation()
from public, anon, authenticated, service_role;

revoke all
on function public.quote_request_intake_default_expires_at_v1(timestamptz)
from public, anon, authenticated;

revoke all
on function public.resolve_quote_request_intake_effective_access_v1(text, timestamptz, timestamptz)
from public, anon, authenticated;

grant execute
on function public.quote_request_intake_default_expires_at_v1(timestamptz)
to service_role;

grant execute
on function public.resolve_quote_request_intake_effective_access_v1(text, timestamptz, timestamptz)
to service_role;

comment on column public.quote_request_intakes.access_state is
  'Persistent customer access state. EXPIRED remains derived from access_token_expires_at at server time.';

comment on column public.quote_request_intakes.lifecycle_revision is
  'Optimistic concurrency revision reserved for controlled operator lifecycle transitions.';

comment on table public.quote_request_intake_lifecycle_events is
  'Immutable operator lifecycle evidence. It stores no customer capability or token material.';

comment on function public.resolve_quote_request_intake_effective_access_v1(text, timestamptz, timestamptz) is
  'Canonical access precedence: CANCELLED, EXPIRED, INTERRUPTED, ACTIVE.';