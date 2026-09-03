create table public.workforce_leave_requests (
  request_id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.workforce_employees(id) on delete restrict,
  leave_type text not null default 'LEAVE' check (leave_type = 'LEAVE'),
  start_date date not null,
  end_date date not null,
  day_part text not null check (day_part in ('FULL_DAY', 'AM', 'PM')),
  request_status text not null default 'REQUESTED'
    check (request_status in ('REQUESTED', 'WAITING', 'APPROVED', 'REJECTED')),
  revision bigint not null default 1 check (revision > 0),
  employee_note text check (employee_note is null or char_length(employee_note) <= 2000),
  submitted_at timestamptz not null default clock_timestamp(),
  decided_at timestamptz,
  decided_by_operator_id uuid references public.commercial_operators(operator_id) on delete restrict,
  management_note text check (management_note is null or char_length(management_note) <= 2000),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint workforce_leave_requests_date_order check (end_date >= start_date),
  constraint workforce_leave_requests_day_part_range check (
    day_part = 'FULL_DAY' or start_date = end_date
  ),
  constraint workforce_leave_requests_decision_state check (
    (request_status = 'REQUESTED' and decided_at is null and decided_by_operator_id is null)
    or
    (request_status in ('WAITING', 'APPROVED', 'REJECTED') and decided_at is not null and decided_by_operator_id is not null)
  )
);

create index workforce_leave_requests_review_queue_idx
on public.workforce_leave_requests(request_status, submitted_at, request_id);

create index workforce_leave_requests_employee_period_idx
on public.workforce_leave_requests(employee_id, start_date, end_date);

create table public.workforce_leave_request_events (
  event_id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.workforce_leave_requests(request_id) on delete restrict,
  event_type text not null check (event_type in ('SUBMITTED', 'DECISION')),
  previous_status text check (
    previous_status is null or previous_status in ('REQUESTED', 'WAITING', 'APPROVED', 'REJECTED')
  ),
  new_status text not null check (new_status in ('REQUESTED', 'WAITING', 'APPROVED', 'REJECTED')),
  actor_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  management_note text check (management_note is null or char_length(management_note) <= 2000),
  occurred_at timestamptz not null default clock_timestamp(),
  constraint workforce_leave_request_events_shape check (
    (event_type = 'SUBMITTED' and previous_status is null and new_status = 'REQUESTED')
    or
    (event_type = 'DECISION' and previous_status is not null)
  )
);

create index workforce_leave_request_events_request_time_idx
on public.workforce_leave_request_events(request_id, occurred_at, event_id);

alter table public.workforce_leave_requests enable row level security;
alter table public.workforce_leave_requests force row level security;
alter table public.workforce_leave_request_events enable row level security;
alter table public.workforce_leave_request_events force row level security;

revoke all privileges on table public.workforce_leave_requests from public, anon, authenticated, service_role;
revoke all privileges on table public.workforce_leave_request_events from public, anon, authenticated, service_role;

comment on table public.workforce_leave_requests is
  'Authoritative workforce leave request state. Only APPROVED requests produce canonical Calendar leave entries.';
comment on table public.workforce_leave_request_events is
  'Append-only leave request submission and management decision history.';

create function public.guard_workforce_leave_request_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'LEAVE_REQUEST_DELETE_DENIED';
  end if;

  if new.request_id is distinct from old.request_id
    or new.employee_id is distinct from old.employee_id
    or new.leave_type is distinct from old.leave_type
    or new.start_date is distinct from old.start_date
    or new.end_date is distinct from old.end_date
    or new.day_part is distinct from old.day_part
    or new.employee_note is distinct from old.employee_note
    or new.submitted_at is distinct from old.submitted_at
    or new.created_at is distinct from old.created_at then
    raise exception using errcode = '55000', message = 'LEAVE_REQUEST_IDENTITY_IMMUTABLE';
  end if;

  if new.revision <> old.revision + 1 or new.updated_at <= old.updated_at then
    raise exception using errcode = '40001', message = 'LEAVE_REQUEST_REVISION_CONFLICT';
  end if;

  if not (
    (old.request_status = 'REQUESTED' and new.request_status in ('WAITING', 'APPROVED', 'REJECTED'))
    or
    (old.request_status = 'WAITING' and new.request_status in ('APPROVED', 'REJECTED'))
  ) then
    raise exception using errcode = '55000', message = 'LEAVE_REQUEST_INVALID_TRANSITION';
  end if;

  return new;
end;
$$;

create trigger trg_workforce_leave_requests_guard
before update or delete on public.workforce_leave_requests
for each row execute function public.guard_workforce_leave_request_mutation_v1();

create function public.prevent_workforce_leave_request_event_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'LEAVE_REQUEST_EVENT_IMMUTABLE';
end;
$$;

create trigger trg_workforce_leave_request_events_immutable
before update or delete on public.workforce_leave_request_events
for each row execute function public.prevent_workforce_leave_request_event_mutation_v1();

create function public.require_workforce_leave_owner_v1(p_actor_id uuid)
returns public.commercial_operators
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
begin
  if p_actor_id is null then
    raise exception using errcode = '42501', message = 'LEAVE_MANAGEMENT_ACTOR_REQUIRED';
  end if;

  select * into v_operator
  from public.commercial_operators
  where auth_user_id = p_actor_id;

  if not found or v_operator.status <> 'ACTIVE' or v_operator.role <> 'owner' then
    raise exception using errcode = '42501', message = 'LEAVE_MANAGEMENT_OWNER_REQUIRED';
  end if;

  return v_operator;
end;
$$;

revoke all on function public.require_workforce_leave_owner_v1(uuid)
from public, anon, authenticated, service_role;

create function public.submit_workforce_leave_request_v1(
  p_actor_id uuid,
  p_employee_id uuid,
  p_start_date date,
  p_end_date date,
  p_day_part text,
  p_employee_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_employee public.workforce_employees%rowtype;
  v_operator public.commercial_operators%rowtype;
  v_request_id uuid;
begin
  if p_employee_id is null then
    raise exception using errcode = '22023', message = 'LEAVE_EMPLOYEE_REQUIRED';
  end if;
  if p_start_date is null or p_end_date is null then
    raise exception using errcode = '22023', message = 'LEAVE_DATE_RANGE_REQUIRED';
  end if;
  if p_start_date > p_end_date then
    raise exception using errcode = '22023', message = 'LEAVE_DATE_RANGE_REVERSED';
  end if;
  if p_end_date - p_start_date > 365 then
    raise exception using errcode = '22023', message = 'LEAVE_DATE_RANGE_TOO_LARGE';
  end if;
  if p_day_part not in ('FULL_DAY', 'AM', 'PM') then
    raise exception using errcode = '22023', message = 'LEAVE_DAY_PART_INVALID';
  end if;
  if p_day_part <> 'FULL_DAY' and p_start_date <> p_end_date then
    raise exception using errcode = '22023', message = 'LEAVE_PARTIAL_DAY_RANGE_INVALID';
  end if;
  if p_employee_note is not null and char_length(p_employee_note) > 2000 then
    raise exception using errcode = '22023', message = 'LEAVE_EMPLOYEE_NOTE_TOO_LONG';
  end if;

  if exists (
    select 1
    from public.employee_identity_reservations
    where employee_identity_id = p_employee_id
      and identity_status = 'PRE_EMPLOYMENT'
  ) then
    raise exception using errcode = '42501', message = 'LEAVE_PRE_EMPLOYMENT_NOT_ELIGIBLE';
  end if;

  select * into v_employee
  from public.workforce_employees
  where id = p_employee_id
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = 'LEAVE_EMPLOYEE_NOT_FOUND';
  end if;
  if v_employee.employment_status <> 'ACTIVE'
    or v_employee.start_date > p_start_date
    or (v_employee.end_date is not null and v_employee.end_date < p_end_date) then
    raise exception using errcode = '42501', message = 'LEAVE_EMPLOYEE_NOT_ACTIVE_FOR_PERIOD';
  end if;
  if v_employee.commercial_operator_id is null then
    raise exception using errcode = '42501', message = 'LEAVE_EMPLOYEE_SELF_BINDING_REQUIRED';
  end if;

  select * into v_operator
  from public.commercial_operators
  where operator_id = v_employee.commercial_operator_id;

  if not found or v_operator.auth_user_id <> p_actor_id or v_operator.status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'LEAVE_EMPLOYEE_SELF_REQUIRED';
  end if;

  insert into public.workforce_leave_requests(
    employee_id,
    start_date,
    end_date,
    day_part,
    employee_note
  ) values (
    p_employee_id,
    p_start_date,
    p_end_date,
    p_day_part,
    nullif(btrim(p_employee_note), '')
  )
  returning request_id into v_request_id;

  insert into public.workforce_leave_request_events(
    request_id,
    event_type,
    previous_status,
    new_status,
    actor_operator_id
  ) values (
    v_request_id,
    'SUBMITTED',
    null,
    'REQUESTED',
    v_operator.operator_id
  );

  return jsonb_build_object(
    'request_id', v_request_id,
    'request_status', 'REQUESTED',
    'revision', 1
  );
end;
$$;

revoke all on function public.submit_workforce_leave_request_v1(uuid, uuid, date, date, text, text)
from public, anon, authenticated, service_role;
grant execute on function public.submit_workforce_leave_request_v1(uuid, uuid, date, date, text, text)
to service_role;

comment on function public.submit_workforce_leave_request_v1(uuid, uuid, date, date, text, text) is
  'Service-only leave submission requiring an active workforce employee bound to the same active operator auth identity.';

create function public.list_workforce_leave_requests_v1(
  p_actor_id uuid,
  p_start_date date,
  p_end_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_result jsonb;
begin
  perform public.require_workforce_leave_owner_v1(p_actor_id);

  if p_start_date is null or p_end_date is null then
    raise exception using errcode = '22023', message = 'LEAVE_DATE_RANGE_REQUIRED';
  end if;
  if p_start_date > p_end_date then
    raise exception using errcode = '22023', message = 'LEAVE_DATE_RANGE_REVERSED';
  end if;
  if p_end_date - p_start_date > 365 then
    raise exception using errcode = '22023', message = 'LEAVE_DATE_RANGE_TOO_LARGE';
  end if;

  select jsonb_build_object(
    'start_date', p_start_date,
    'end_date', p_end_date,
    'counters', jsonb_build_object(
      'requested', count(*) filter (where request.request_status = 'REQUESTED'),
      'waiting', count(*) filter (where request.request_status = 'WAITING'),
      'approved', count(*) filter (where request.request_status = 'APPROVED'),
      'rejected', count(*) filter (where request.request_status = 'REJECTED')
    ),
    'requests', coalesce(jsonb_agg(
      jsonb_build_object(
        'request_id', request.request_id,
        'employee_id', request.employee_id,
        'employee_number', identity.employee_number,
        'display_name', employee.display_name,
        'leave_type', request.leave_type,
        'start_date', request.start_date,
        'end_date', request.end_date,
        'day_part', request.day_part,
        'request_status', request.request_status,
        'revision', request.revision,
        'employee_note', request.employee_note,
        'submitted_at', request.submitted_at,
        'decided_at', request.decided_at,
        'decided_by_operator_id', request.decided_by_operator_id,
        'management_note', request.management_note,
        'capacity_context', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'date', context_date,
            'employees_total', (
              select count(*)
              from public.workforce_employees as active_employee
              where active_employee.employment_status = 'ACTIVE'
                and active_employee.start_date <= context_date
                and (active_employee.end_date is null or active_employee.end_date >= context_date)
            ),
            'approved_leave_count', (
              select count(*)
              from public.workforce_calendar_entries as calendar_entry
              where calendar_entry.calendar_date = context_date
                and calendar_entry.status = 'LEAVE'
            ),
            'sick_count', (
              select count(*)
              from public.workforce_calendar_entries as calendar_entry
              where calendar_entry.calendar_date = context_date
                and calendar_entry.status = 'SICK'
            ),
            'other_absence_count', (
              select count(*)
              from public.workforce_calendar_entries as calendar_entry
              where calendar_entry.calendar_date = context_date
                and calendar_entry.status = 'OTHER_ABSENCE'
            ),
            'requested_count', (
              select count(*)
              from public.workforce_leave_requests as pending_request
              where pending_request.request_status = 'REQUESTED'
                and context_date between pending_request.start_date and pending_request.end_date
            ),
            'waiting_count', (
              select count(*)
              from public.workforce_leave_requests as pending_request
              where pending_request.request_status = 'WAITING'
                and context_date between pending_request.start_date and pending_request.end_date
            )
          ) order by context_date), '[]'::jsonb)
          from generate_series(request.start_date, request.end_date, interval '1 day') as date_series(context_date)
        ),
        'history', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'event_id', event.event_id,
            'event_type', event.event_type,
            'previous_status', event.previous_status,
            'new_status', event.new_status,
            'actor_operator_id', event.actor_operator_id,
            'actor_display_name', actor.display_name,
            'management_note', event.management_note,
            'occurred_at', event.occurred_at
          ) order by event.occurred_at, event.event_id), '[]'::jsonb)
          from public.workforce_leave_request_events as event
          join public.commercial_operators as actor on actor.operator_id = event.actor_operator_id
          where event.request_id = request.request_id
        )
      ) order by
        case request.request_status when 'REQUESTED' then 0 when 'WAITING' then 1 else 2 end,
        request.submitted_at desc,
        request.request_id
    ) filter (where request.request_id is not null), '[]'::jsonb)
  ) into v_result
  from public.workforce_leave_requests as request
  join public.workforce_employees as employee on employee.id = request.employee_id
  left join public.employee_identity_reservations as identity
    on identity.workforce_employee_id = request.employee_id
      and identity.identity_status = 'ACTIVATED'
  where request.start_date <= p_end_date
    and request.end_date >= p_start_date;

  return v_result;
end;
$$;

revoke all on function public.list_workforce_leave_requests_v1(uuid, date, date)
from public, anon, authenticated, service_role;
grant execute on function public.list_workforce_leave_requests_v1(uuid, date, date)
to service_role;

comment on function public.list_workforce_leave_requests_v1(uuid, date, date) is
  'Service-only bounded owner review queue with factual absence counts and append-only decision history.';

create function public.decide_workforce_leave_request_v1(
  p_actor_id uuid,
  p_request_id uuid,
  p_expected_status text,
  p_expected_revision bigint,
  p_decision text,
  p_management_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_request public.workforce_leave_requests%rowtype;
  v_employee public.workforce_employees%rowtype;
  v_decided_at timestamptz := clock_timestamp();
begin
  v_operator := public.require_workforce_leave_owner_v1(p_actor_id);

  if p_request_id is null or p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'LEAVE_DECISION_PRECONDITION_REQUIRED';
  end if;
  if p_expected_status not in ('REQUESTED', 'WAITING', 'APPROVED', 'REJECTED') then
    raise exception using errcode = '22023', message = 'LEAVE_EXPECTED_STATUS_INVALID';
  end if;
  if p_decision not in ('WAITING', 'APPROVED', 'REJECTED') then
    raise exception using errcode = '22023', message = 'LEAVE_DECISION_INVALID';
  end if;
  if p_management_note is not null and char_length(p_management_note) > 2000 then
    raise exception using errcode = '22023', message = 'LEAVE_MANAGEMENT_NOTE_TOO_LONG';
  end if;

  select * into v_request
  from public.workforce_leave_requests
  where request_id = p_request_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'LEAVE_REQUEST_NOT_FOUND';
  end if;
  if v_request.request_status <> p_expected_status
    or v_request.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'LEAVE_REQUEST_STALE_DECISION';
  end if;
  if not (
    (v_request.request_status = 'REQUESTED' and p_decision in ('WAITING', 'APPROVED', 'REJECTED'))
    or
    (v_request.request_status = 'WAITING' and p_decision in ('APPROVED', 'REJECTED'))
  ) then
    raise exception using errcode = '55000', message = 'LEAVE_REQUEST_INVALID_TRANSITION';
  end if;

  if p_decision = 'APPROVED' then
    select * into v_employee
    from public.workforce_employees
    where id = v_request.employee_id
    for share;

    if not found or v_employee.employment_status <> 'ACTIVE'
      or v_employee.start_date > v_request.start_date
      or (v_employee.end_date is not null and v_employee.end_date < v_request.end_date) then
      raise exception using errcode = '55000', message = 'LEAVE_EMPLOYEE_NOT_ACTIVE_FOR_PERIOD';
    end if;

    if exists (
      select 1
      from public.workforce_calendar_entries
      where employee_id = v_request.employee_id
        and calendar_date between v_request.start_date and v_request.end_date
    ) then
      raise exception using errcode = '23P01', message = 'LEAVE_REQUEST_CALENDAR_CONFLICT';
    end if;

    insert into public.workforce_calendar_entries(employee_id, calendar_date, status)
    select v_request.employee_id, calendar_date::date, 'LEAVE'
    from generate_series(v_request.start_date, v_request.end_date, interval '1 day') as date_series(calendar_date);
  end if;

  update public.workforce_leave_requests
  set request_status = p_decision,
      revision = revision + 1,
      decided_at = v_decided_at,
      decided_by_operator_id = v_operator.operator_id,
      management_note = nullif(btrim(p_management_note), ''),
      updated_at = v_decided_at
  where request_id = v_request.request_id;

  insert into public.workforce_leave_request_events(
    request_id,
    event_type,
    previous_status,
    new_status,
    actor_operator_id,
    management_note,
    occurred_at
  ) values (
    v_request.request_id,
    'DECISION',
    v_request.request_status,
    p_decision,
    v_operator.operator_id,
    nullif(btrim(p_management_note), ''),
    v_decided_at
  );

  return jsonb_build_object(
    'request_id', v_request.request_id,
    'previous_status', v_request.request_status,
    'request_status', p_decision,
    'revision', v_request.revision + 1,
    'decided_at', v_decided_at
  );
end;
$$;

revoke all on function public.decide_workforce_leave_request_v1(uuid, uuid, text, bigint, text, text)
from public, anon, authenticated, service_role;
grant execute on function public.decide_workforce_leave_request_v1(uuid, uuid, text, bigint, text, text)
to service_role;

comment on function public.decide_workforce_leave_request_v1(uuid, uuid, text, bigint, text, text) is
  'Service-only owner decision with status/revision locking and transactional canonical Calendar integration.';

create function public.get_operator_leave_requests_v1(
  p_start_date date,
  p_end_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  return public.list_workforce_leave_requests_v1(v_subject, p_start_date, p_end_date);
end;
$$;

revoke all on function public.get_operator_leave_requests_v1(date, date)
from public, anon, authenticated, service_role;
grant execute on function public.get_operator_leave_requests_v1(date, date)
to authenticated;

comment on function public.get_operator_leave_requests_v1(date, date) is
  'Authenticated owner Calendar projection for the bounded leave management queue.';

create function public.decide_operator_leave_request_v1(
  p_request_id uuid,
  p_expected_status text,
  p_expected_revision bigint,
  p_decision text,
  p_management_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  return public.decide_workforce_leave_request_v1(
    v_subject,
    p_request_id,
    p_expected_status,
    p_expected_revision,
    p_decision,
    p_management_note
  );
end;
$$;

revoke all on function public.decide_operator_leave_request_v1(uuid, text, bigint, text, text)
from public, anon, authenticated, service_role;
grant execute on function public.decide_operator_leave_request_v1(uuid, text, bigint, text, text)
to authenticated;

comment on function public.decide_operator_leave_request_v1(uuid, text, bigint, text, text) is
  'Authenticated owner Calendar decision wrapper preserving server-side status and revision preconditions.';