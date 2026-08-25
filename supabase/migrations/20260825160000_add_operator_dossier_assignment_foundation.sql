create table lws_internal.operator_dossier_assignments (
  quote_request_id uuid primary key
    references public.quote_requests(id) on delete restrict,
  assignee_operator_id uuid
    references public.commercial_operators(operator_id) on delete restrict,
  revision bigint not null default 0 check (revision >= 0),
  assigned_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint operator_dossier_assignments_shape_valid check (
    (assignee_operator_id is null and assigned_at is null)
    or (assignee_operator_id is not null and assigned_at is not null)
  ),
  constraint operator_dossier_assignments_timestamps_valid check (
    updated_at >= created_at
    and (assigned_at is null or assigned_at >= created_at)
  )
);

create table lws_internal.operator_dossier_assignment_events (
  event_id bigint generated always as identity primary key,
  quote_request_id uuid not null
    references public.quote_requests(id) on delete restrict,
  event_type text not null check (event_type in ('ASSIGNED', 'REASSIGNED')),
  previous_assignee_operator_id uuid
    references public.commercial_operators(operator_id) on delete restrict,
  new_assignee_operator_id uuid not null
    references public.commercial_operators(operator_id) on delete restrict,
  actor_operator_id uuid not null
    references public.commercial_operators(operator_id) on delete restrict,
  reason text,
  previous_revision bigint not null check (previous_revision >= 0),
  resulting_revision bigint not null check (resulting_revision = previous_revision + 1),
  occurred_at timestamptz not null default clock_timestamp(),
  idempotency_key uuid not null unique,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint operator_dossier_assignment_event_transition_valid check (
    (event_type = 'ASSIGNED'
      and previous_assignee_operator_id is null)
    or
    (event_type = 'REASSIGNED'
      and previous_assignee_operator_id is not null
      and previous_assignee_operator_id <> new_assignee_operator_id
      and char_length(btrim(reason)) between 1 and 500)
  ),
  constraint operator_dossier_assignment_event_reason_valid check (
    reason is null or char_length(btrim(reason)) between 1 and 500
  )
);

create table lws_internal.operator_dossier_assignment_commands (
  idempotency_key uuid primary key,
  quote_request_id uuid not null
    references public.quote_requests(id) on delete restrict,
  actor_operator_id uuid not null
    references public.commercial_operators(operator_id) on delete restrict,
  assignee_operator_id uuid not null
    references public.commercial_operators(operator_id) on delete restrict,
  expected_revision bigint not null check (expected_revision >= 0),
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  result_payload jsonb not null check (jsonb_typeof(result_payload) = 'object'),
  created_at timestamptz not null default clock_timestamp()
);

alter table lws_internal.operator_dossier_assignments enable row level security;
alter table lws_internal.operator_dossier_assignments force row level security;
alter table lws_internal.operator_dossier_assignment_events enable row level security;
alter table lws_internal.operator_dossier_assignment_events force row level security;
alter table lws_internal.operator_dossier_assignment_commands enable row level security;
alter table lws_internal.operator_dossier_assignment_commands force row level security;

revoke all on table
  lws_internal.operator_dossier_assignments,
  lws_internal.operator_dossier_assignment_events,
  lws_internal.operator_dossier_assignment_commands
from public, anon, authenticated, service_role;
revoke all on sequence lws_internal.operator_dossier_assignment_events_event_id_seq
from public, anon, authenticated, service_role;

create function lws_internal.prevent_operator_dossier_assignment_ledger_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'OPERATOR_DOSSIER_ASSIGNMENT_LEDGER_APPEND_ONLY';
end;
$$;

create trigger trg_operator_dossier_assignment_events_append_only
before update or delete on lws_internal.operator_dossier_assignment_events
for each row execute function lws_internal.prevent_operator_dossier_assignment_ledger_mutation_v1();

create trigger trg_operator_dossier_assignment_commands_append_only
before update or delete on lws_internal.operator_dossier_assignment_commands
for each row execute function lws_internal.prevent_operator_dossier_assignment_ledger_mutation_v1();

create function lws_internal.guard_operator_dossier_assignment_state_v1()
returns trigger
language plpgsql
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_classification text;
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'OPERATOR_DOSSIER_ASSIGNMENT_STATE_IMMUTABLE';
  end if;

  if tg_op = 'INSERT' then
    select record_classification into v_classification
    from public.quote_requests
    where id = new.quote_request_id;

    if v_classification is distinct from 'production'
       or new.assignee_operator_id is not null
       or new.revision <> 0
       or new.assigned_at is not null then
      raise exception using errcode = '23514', message = 'OPERATOR_DOSSIER_ASSIGNMENT_INITIAL_STATE_INVALID';
    end if;
    return new;
  end if;

  if current_setting('lws.operator_dossier_assignment_command', true) is distinct from 'on' then
    raise exception using errcode = '55000', message = 'DIRECT_ASSIGNMENT_STATE_WRITE_FORBIDDEN';
  end if;
  if new.quote_request_id is distinct from old.quote_request_id
     or new.created_at is distinct from old.created_at
     or new.assignee_operator_id is null then
    raise exception using errcode = '23514', message = 'OPERATOR_DOSSIER_ASSIGNMENT_STATE_INVALID';
  end if;
  if new.revision <> old.revision + 1 then
    raise exception using errcode = '40001', message = 'OPERATOR_DOSSIER_ASSIGNMENT_REVISION_MISMATCH';
  end if;
  if new.updated_at <= old.updated_at
     or new.assigned_at is null
     or new.assigned_at <> new.updated_at then
    raise exception using errcode = '23514', message = 'OPERATOR_DOSSIER_ASSIGNMENT_TIMESTAMP_INVALID';
  end if;
  return new;
end;
$$;

create trigger trg_operator_dossier_assignment_state_guard
before insert or update or delete on lws_internal.operator_dossier_assignments
for each row execute function lws_internal.guard_operator_dossier_assignment_state_v1();

create function lws_internal.create_operator_dossier_assignment_for_quote_request_v1()
returns trigger
language plpgsql
security definer
set search_path = lws_internal, pg_catalog
as $$
begin
  if new.record_classification = 'production' then
    insert into lws_internal.operator_dossier_assignments (quote_request_id)
    values (new.id);
  end if;
  return new;
end;
$$;

create trigger trg_quote_requests_create_operator_dossier_assignment
after insert on public.quote_requests
for each row execute function lws_internal.create_operator_dossier_assignment_for_quote_request_v1();

insert into lws_internal.operator_dossier_assignments (quote_request_id, created_at, updated_at)
select request.id, authority_time.created_at, authority_time.created_at
from public.quote_requests as request
cross join lateral (select clock_timestamp() as created_at) as authority_time
where request.record_classification = 'production'
on conflict (quote_request_id) do nothing;

create function lws_internal.resolve_operator_dossier_reference_v1(p_dossier_reference text)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_reference text := upper(btrim(coalesce(p_dossier_reference, '')));
  v_matches uuid[];
begin
  if v_reference ~ '^[0-9A-F]{8}$' then
    v_reference := '#' || v_reference;
  end if;
  if v_reference !~ '^(LWS-AAN-[0-9]{4}-[0-9]{4}|#[0-9A-F]{8})$' then
    raise exception using errcode = '22023', message = 'INVALID_DOSSIER_REFERENCE';
  end if;

  select array_agg(request.id order by request.id)
  into v_matches
  from public.quote_requests as request
  where request.record_classification = 'production'
    and (
      request.application_reference = v_reference
      or request.support_reference = v_reference
    );

  if coalesce(cardinality(v_matches), 0) = 0 then
    raise exception using errcode = 'P0001', message = 'DOSSIER_NOT_FOUND';
  end if;
  if cardinality(v_matches) <> 1 then
    raise exception using errcode = 'P0001', message = 'AMBIGUOUS_DOSSIER_REFERENCE';
  end if;
  return v_matches[1];
end;
$$;

create function public.get_operator_dossier_assignment_v1(p_dossier_reference text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_actor_role text;
  v_actor_status text;
  v_quote_request_id uuid;
  v_assignment lws_internal.operator_dossier_assignments%rowtype;
  v_display_name text;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select role, status into v_actor_role, v_actor_status
  from public.commercial_operators
  where auth_user_id = v_subject;
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_actor_status = 'DISABLED' then raise exception using errcode = '42501', message = 'OPERATOR_DISABLED'; end if;
  if v_actor_status = 'REVOKED' then raise exception using errcode = '42501', message = 'OPERATOR_REVOKED'; end if;
  if v_actor_status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;
  if v_actor_role not in ('owner', 'operations_manager') then
    raise exception using errcode = '42501', message = 'DOSSIER_ASSIGNMENT_READER_REQUIRED';
  end if;

  v_quote_request_id := lws_internal.resolve_operator_dossier_reference_v1(p_dossier_reference);
  select * into v_assignment
  from lws_internal.operator_dossier_assignments
  where quote_request_id = v_quote_request_id;
  if not found then
    raise exception using errcode = '23514', message = 'OPERATOR_DOSSIER_ASSIGNMENT_STATE_REQUIRED';
  end if;

  if v_assignment.assignee_operator_id is not null then
    select display_name into strict v_display_name
    from public.commercial_operators
    where operator_id = v_assignment.assignee_operator_id;
  end if;

  return jsonb_build_object(
    'assignment_state', case when v_assignment.assignee_operator_id is null then 'UNASSIGNED' else 'ASSIGNED' end,
    'assignee_operator_id', v_assignment.assignee_operator_id,
    'assignee_display_name', v_display_name,
    'revision', v_assignment.revision,
    'assigned_at', v_assignment.assigned_at
  );
end;
$$;

create function public.assign_operator_dossier_v1(
  p_dossier_reference text,
  p_assignee_operator_id uuid,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_actor public.commercial_operators%rowtype;
  v_assignee public.commercial_operators%rowtype;
  v_quote_request_id uuid;
  v_assignment lws_internal.operator_dossier_assignments%rowtype;
  v_existing lws_internal.operator_dossier_assignment_commands%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_fingerprint char(64);
  v_now timestamptz;
  v_event_type text;
  v_previous_assignee_operator_id uuid;
  v_result jsonb;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_actor
  from public.commercial_operators
  where auth_user_id = v_subject
  for share;
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_actor.status = 'DISABLED' then raise exception using errcode = '42501', message = 'OPERATOR_DISABLED'; end if;
  if v_actor.status = 'REVOKED' then raise exception using errcode = '42501', message = 'OPERATOR_REVOKED'; end if;
  if v_actor.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;
  if v_actor.role not in ('owner', 'operations_manager') then
    raise exception using errcode = '42501', message = 'DOSSIER_ASSIGNMENT_ACTOR_REQUIRED';
  end if;
  if p_assignee_operator_id is null
     or p_expected_revision is null or p_expected_revision < 0
     or p_idempotency_key is null
     or char_length(coalesce(v_reason, '')) > 500 then
    raise exception using errcode = '22023', message = 'INVALID_DOSSIER_ASSIGNMENT_COMMAND';
  end if;

  v_quote_request_id := lws_internal.resolve_operator_dossier_reference_v1(p_dossier_reference);
  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'contract_version', 1,
    'actor_operator_id', v_actor.operator_id,
    'quote_request_id', v_quote_request_id,
    'assignee_operator_id', p_assignee_operator_id,
    'expected_revision', p_expected_revision,
    'reason', v_reason
  )::text, 'UTF8'), 'sha256'), 'hex');

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key::text, 0)
  );

  select * into v_existing
  from lws_internal.operator_dossier_assignment_commands
  where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed', true);
  end if;

  select * into v_assignee
  from public.commercial_operators
  where operator_id = p_assignee_operator_id
  for share;
  if not found then
    raise exception using errcode = '23503', message = 'ASSIGNEE_OPERATOR_NOT_FOUND';
  end if;
  if v_assignee.status <> 'ACTIVE' or v_assignee.role <> 'operator' then
    raise exception using errcode = '42501', message = 'ASSIGNEE_NOT_ELIGIBLE';
  end if;

  select * into v_assignment
  from lws_internal.operator_dossier_assignments
  where quote_request_id = v_quote_request_id
  for update;
  if not found then
    raise exception using errcode = '23514', message = 'OPERATOR_DOSSIER_ASSIGNMENT_STATE_REQUIRED';
  end if;

  if v_assignment.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;

  if v_assignment.assignee_operator_id = p_assignee_operator_id then
    v_result := jsonb_build_object(
      'assignment_state', 'ASSIGNED',
      'assignee_operator_id', v_assignment.assignee_operator_id,
      'revision', v_assignment.revision,
      'assigned_at', v_assignment.assigned_at,
      'no_change', true,
      'replayed', false
    );
    insert into lws_internal.operator_dossier_assignment_commands (
      idempotency_key, quote_request_id, actor_operator_id, assignee_operator_id,
      expected_revision, request_fingerprint, result_payload
    ) values (
      p_idempotency_key, v_quote_request_id, v_actor.operator_id, p_assignee_operator_id,
      p_expected_revision, v_fingerprint, v_result
    );
    return v_result;
  end if;

  if v_assignment.assignee_operator_id is not null and v_reason is null then
    raise exception using errcode = '22023', message = 'REASSIGNMENT_REASON_REQUIRED';
  end if;

  v_event_type := case when v_assignment.assignee_operator_id is null then 'ASSIGNED' else 'REASSIGNED' end;
  v_previous_assignee_operator_id := v_assignment.assignee_operator_id;
  v_now := clock_timestamp();
  perform set_config('lws.operator_dossier_assignment_command', 'on', true);
  update lws_internal.operator_dossier_assignments
  set assignee_operator_id = p_assignee_operator_id,
      revision = revision + 1,
      assigned_at = v_now,
      updated_at = v_now
  where quote_request_id = v_quote_request_id
  returning * into v_assignment;
  perform set_config('lws.operator_dossier_assignment_command', '', true);

  insert into lws_internal.operator_dossier_assignment_events (
    quote_request_id, event_type, previous_assignee_operator_id,
    new_assignee_operator_id, actor_operator_id, reason,
    previous_revision, resulting_revision, occurred_at,
    idempotency_key, request_fingerprint
  ) values (
    v_quote_request_id, v_event_type,
    v_previous_assignee_operator_id,
    p_assignee_operator_id, v_actor.operator_id, v_reason,
    p_expected_revision, v_assignment.revision, v_now,
    p_idempotency_key, v_fingerprint
  );

  v_result := jsonb_build_object(
    'assignment_state', 'ASSIGNED',
    'assignee_operator_id', v_assignment.assignee_operator_id,
    'revision', v_assignment.revision,
    'assigned_at', v_assignment.assigned_at,
    'no_change', false,
    'replayed', false
  );

  insert into lws_internal.operator_dossier_assignment_commands (
    idempotency_key, quote_request_id, actor_operator_id, assignee_operator_id,
    expected_revision, request_fingerprint, result_payload
  ) values (
    p_idempotency_key, v_quote_request_id, v_actor.operator_id, p_assignee_operator_id,
    p_expected_revision, v_fingerprint, v_result
  );
  return v_result;
end;
$$;

revoke all on function
  lws_internal.prevent_operator_dossier_assignment_ledger_mutation_v1(),
  lws_internal.guard_operator_dossier_assignment_state_v1(),
  lws_internal.create_operator_dossier_assignment_for_quote_request_v1(),
  lws_internal.resolve_operator_dossier_reference_v1(text),
  public.get_operator_dossier_assignment_v1(text),
  public.assign_operator_dossier_v1(text, uuid, bigint, uuid, text)
from public, anon, authenticated, service_role;

grant execute on function
  public.get_operator_dossier_assignment_v1(text),
  public.assign_operator_dossier_v1(text, uuid, bigint, uuid, text)
to authenticated;

comment on function public.get_operator_dossier_assignment_v1(text) is
  'Minimal assignment card projection for active owners and Operations Managers; exposes no account identity or personnel data.';
comment on function public.assign_operator_dossier_v1(text, uuid, bigint, uuid, text) is
  'Human assignment/reassignment command for active owners and Operations Managers; assignee eligibility is always ACTIVE role=operator.';