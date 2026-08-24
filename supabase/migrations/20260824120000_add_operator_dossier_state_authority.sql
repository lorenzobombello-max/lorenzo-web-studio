create function lws_internal.operator_dossier_transition_allowed_v1(
  p_previous_state text,
  p_new_state text,
  p_state_before_trash text
)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when p_previous_state = 'ACTIVE' and p_new_state = 'ARCHIVED'
      then p_state_before_trash is null
    when p_previous_state = 'ARCHIVED' and p_new_state = 'ACTIVE'
      then p_state_before_trash is null
    when p_previous_state in ('ACTIVE', 'ARCHIVED') and p_new_state = 'TRASHED'
      then p_state_before_trash = p_previous_state
    when p_previous_state = 'TRASHED' and p_new_state in ('ACTIVE', 'ARCHIVED')
      then p_state_before_trash = p_new_state
    else false
  end
$$;

create table lws_internal.operator_dossier_states (
  quote_request_id uuid primary key
    references public.quote_requests(id) on delete cascade,
  state text not null default 'ACTIVE'
    check (state in ('ACTIVE', 'ARCHIVED', 'TRASHED')),
  revision bigint not null default 0 check (revision >= 0),
  state_before_trash text
    check (state_before_trash is null or state_before_trash in ('ACTIVE', 'ARCHIVED')),
  deletion_eligible_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint operator_dossier_states_shape_valid check (
    (
      state = 'TRASHED'
      and state_before_trash in ('ACTIVE', 'ARCHIVED')
      and deletion_eligible_at is not null
      and deletion_eligible_at > updated_at
    )
    or (
      state in ('ACTIVE', 'ARCHIVED')
      and state_before_trash is null
      and deletion_eligible_at is null
    )
  ),
  constraint operator_dossier_states_timestamps_valid
    check (updated_at >= created_at)
);

create function lws_internal.guard_operator_dossier_state_insert_v1()
returns trigger
language plpgsql
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_classification text;
begin
  select record_classification into v_classification
  from public.quote_requests
  where id = new.quote_request_id;

  if v_classification is distinct from 'production' then
    raise exception using errcode = '23514', message = 'OPERATOR_DOSSIER_PRODUCTION_ROOT_REQUIRED';
  end if;
  if new.state <> 'ACTIVE'
     or new.revision <> 0
     or new.state_before_trash is not null
     or new.deletion_eligible_at is not null then
    raise exception using errcode = '23514', message = 'OPERATOR_DOSSIER_INITIAL_STATE_INVALID';
  end if;
  return new;
end;
$$;

create function lws_internal.guard_operator_dossier_state_transition_v1()
returns trigger
language plpgsql
set search_path = lws_internal, pg_catalog
as $$
declare
  v_state_before_trash text := case
    when new.state = 'TRASHED' then new.state_before_trash
    when old.state = 'TRASHED' then old.state_before_trash
    else null
  end;
begin
  if new.quote_request_id is distinct from old.quote_request_id
     or new.created_at is distinct from old.created_at then
    raise exception using errcode = '23514', message = 'OPERATOR_DOSSIER_IDENTITY_IMMUTABLE';
  end if;
  if not lws_internal.operator_dossier_transition_allowed_v1(
    old.state,
    new.state,
    v_state_before_trash
  ) then
    raise exception using errcode = '23514', message = 'INVALID_OPERATOR_DOSSIER_TRANSITION';
  end if;
  if new.revision <> old.revision + 1 then
    raise exception using errcode = '40001', message = 'OPERATOR_DOSSIER_REVISION_MISMATCH';
  end if;
  if new.updated_at <= old.updated_at then
    raise exception using errcode = '23514', message = 'OPERATOR_DOSSIER_UPDATED_AT_INVALID';
  end if;
  return new;
end;
$$;

create trigger trg_operator_dossier_states_insert_guard
before insert on lws_internal.operator_dossier_states
for each row execute function lws_internal.guard_operator_dossier_state_insert_v1();

create trigger trg_operator_dossier_states_transition_guard
before update on lws_internal.operator_dossier_states
for each row execute function lws_internal.guard_operator_dossier_state_transition_v1();

create table lws_internal.operator_dossier_state_events (
  event_id bigint generated always as identity primary key,
  quote_request_id uuid not null,
  event_type text not null
    check (event_type in ('ARCHIVED', 'REACTIVATED', 'TRASHED', 'RESTORED')),
  previous_state text not null
    check (previous_state in ('ACTIVE', 'ARCHIVED', 'TRASHED')),
  new_state text not null
    check (new_state in ('ACTIVE', 'ARCHIVED', 'TRASHED')),
  state_before_trash text
    check (state_before_trash is null or state_before_trash in ('ACTIVE', 'ARCHIVED')),
  previous_revision bigint not null check (previous_revision >= 0),
  new_revision bigint not null check (new_revision = previous_revision + 1),
  deletion_eligible_at timestamptz,
  actor_operator_id uuid not null references public.commercial_operators(operator_id),
  reason text not null check (char_length(btrim(reason)) between 1 and 500),
  occurred_at timestamptz not null default clock_timestamp(),
  idempotency_key uuid not null,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  evidence jsonb not null default '{}'::jsonb,
  constraint operator_dossier_state_events_idempotency_unique
    unique (quote_request_id, idempotency_key),
  constraint operator_dossier_state_events_transition_valid check (
    lws_internal.operator_dossier_transition_allowed_v1(
      previous_state,
      new_state,
      state_before_trash
    )
  ),
  constraint operator_dossier_state_events_type_valid check (
    (event_type = 'ARCHIVED' and previous_state = 'ACTIVE' and new_state = 'ARCHIVED')
    or (event_type = 'REACTIVATED' and previous_state = 'ARCHIVED' and new_state = 'ACTIVE')
    or (event_type = 'TRASHED' and previous_state in ('ACTIVE', 'ARCHIVED') and new_state = 'TRASHED')
    or (event_type = 'RESTORED' and previous_state = 'TRASHED' and new_state in ('ACTIVE', 'ARCHIVED'))
  ),
  constraint operator_dossier_state_events_retention_valid check (
    (new_state = 'TRASHED' and deletion_eligible_at is not null and deletion_eligible_at > occurred_at)
    or (new_state <> 'TRASHED' and deletion_eligible_at is null)
  ),
  constraint operator_dossier_state_events_evidence_safe check (
    jsonb_typeof(evidence) = 'object'
    and not (evidence ?| array[
      'token', 'access_token', 'access_token_hash', 'admin_access_token_hash',
      'approval_token', 'approval_token_hash', 'service_role_key'
    ])
  )
);

create function lws_internal.prevent_operator_dossier_state_event_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'OPERATOR_DOSSIER_STATE_EVENT_APPEND_ONLY';
end;
$$;

create trigger trg_operator_dossier_state_events_append_only
before update or delete on lws_internal.operator_dossier_state_events
for each row execute function lws_internal.prevent_operator_dossier_state_event_mutation_v1();

create function lws_internal.create_operator_dossier_state_for_quote_request_v1()
returns trigger
language plpgsql
security definer
set search_path = lws_internal, pg_catalog
as $$
begin
  if new.record_classification = 'production' then
    insert into lws_internal.operator_dossier_states (quote_request_id)
    values (new.id);
  end if;
  return new;
end;
$$;

create trigger trg_quote_requests_create_operator_dossier_state
after insert on public.quote_requests
for each row execute function lws_internal.create_operator_dossier_state_for_quote_request_v1();

insert into lws_internal.operator_dossier_states (
  quote_request_id,
  state,
  revision,
  created_at,
  updated_at
)
select request.id, 'ACTIVE', 0, authority_time.created_at, authority_time.created_at
from public.quote_requests as request
cross join lateral (select clock_timestamp() as created_at) as authority_time
where request.record_classification = 'production'
on conflict (quote_request_id) do nothing;

do $$
begin
  if exists (
    select 1
    from public.quote_requests as request
    left join lws_internal.operator_dossier_states as state
      on state.quote_request_id = request.id
    where request.record_classification = 'production'
      and (
        state.quote_request_id is null
        or state.state <> 'ACTIVE'
        or state.revision <> 0
      )
  ) then
    raise exception using errcode = '23514', message = 'OPERATOR_DOSSIER_STATE_BACKFILL_INCOMPLETE';
  end if;
  if exists (
    select 1
    from lws_internal.operator_dossier_states as state
    join public.quote_requests as request on request.id = state.quote_request_id
    where request.record_classification <> 'production'
  ) then
    raise exception using errcode = '23514', message = 'OPERATOR_DOSSIER_STATE_CLASSIFICATION_LEAK';
  end if;
end;
$$;

alter table lws_internal.operator_dossier_states enable row level security;
alter table lws_internal.operator_dossier_states force row level security;
alter table lws_internal.operator_dossier_state_events enable row level security;
alter table lws_internal.operator_dossier_state_events force row level security;

revoke all on table lws_internal.operator_dossier_states
from public, anon, authenticated, service_role;
revoke all on table lws_internal.operator_dossier_state_events
from public, anon, authenticated, service_role;
revoke all on function lws_internal.operator_dossier_transition_allowed_v1(text, text, text)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_operator_dossier_state_insert_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_operator_dossier_state_transition_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.prevent_operator_dossier_state_event_mutation_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.create_operator_dossier_state_for_quote_request_v1()
from public, anon, authenticated, service_role;

comment on table lws_internal.operator_dossier_states is
  'Private one-to-one dossier-zone authority for production quote request roots. CANCELLED remains a separate intake status.';
comment on table lws_internal.operator_dossier_state_events is
  'Append-only dossier-zone transition evidence. The root UUID intentionally has no FK so evidence can survive a future authorized cleanup.';
comment on function lws_internal.operator_dossier_transition_allowed_v1(text, text, text) is
  'Canonical ACTIVE, ARCHIVED, and TRASHED transition contract. It defines no runtime command and no DELETED state.';