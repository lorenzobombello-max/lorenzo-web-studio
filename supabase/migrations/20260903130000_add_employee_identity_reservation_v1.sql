create sequence public.employee_identity_number_seq
  as bigint
  minvalue 4
  start with 4
  no cycle;

revoke all privileges on sequence public.employee_identity_number_seq from public, anon, authenticated, service_role;

create table public.employee_identity_reservations (
  employee_identity_id uuid primary key default gen_random_uuid(),
  employee_number text not null unique,
  display_name text not null check (nullif(btrim(display_name), '') is not null),
  identity_status text not null default 'PRE_EMPLOYMENT'
    check (identity_status in ('PRE_EMPLOYMENT', 'ACTIVATED')),
  workforce_employee_id uuid unique references public.workforce_employees(id) on delete restrict,
  allocated_at timestamptz not null default clock_timestamp(),
  activated_at timestamptz,
  constraint employee_identity_reservations_number_format
    check (employee_number ~ '^LWS-[0-9]{5}$'),
  constraint employee_identity_reservations_activation_state
    check (
      (identity_status = 'PRE_EMPLOYMENT' and workforce_employee_id is null and activated_at is null)
      or
      (identity_status = 'ACTIVATED' and workforce_employee_id is not null and activated_at is not null)
    ),
  constraint employee_identity_reservations_identity_number_key
    unique (employee_identity_id, employee_number),
  constraint employee_identity_reservations_activation_binding_key
    unique (employee_identity_id, employee_number, workforce_employee_id)
);

create table public.employee_number_allocation_ledger (
  allocation_id uuid primary key default gen_random_uuid(),
  employee_identity_id uuid not null unique,
  employee_number text not null unique,
  allocated_at timestamptz not null default clock_timestamp(),
  allocation_reason text not null check (nullif(btrim(allocation_reason), '') is not null),
  constraint employee_number_allocation_ledger_number_format
    check (employee_number ~ '^LWS-[0-9]{5}$'),
  constraint employee_number_allocation_ledger_identity_number_fkey
    foreign key (employee_identity_id, employee_number)
    references public.employee_identity_reservations(employee_identity_id, employee_number)
    on delete restrict
);

create table public.employee_identity_activation_events (
  activation_event_id uuid primary key default gen_random_uuid(),
  employee_identity_id uuid not null unique,
  workforce_employee_id uuid not null unique
    references public.workforce_employees(id) on delete restrict,
  employee_number text not null unique,
  activated_at timestamptz not null default clock_timestamp(),
  constraint employee_identity_activation_events_number_format
    check (employee_number ~ '^LWS-[0-9]{5}$'),
  constraint employee_identity_activation_events_binding_fkey
    foreign key (employee_identity_id, employee_number, workforce_employee_id)
    references public.employee_identity_reservations(
      employee_identity_id,
      employee_number,
      workforce_employee_id
    )
    on delete restrict
);

alter table public.employee_identity_reservations enable row level security;
alter table public.employee_identity_reservations force row level security;
alter table public.employee_number_allocation_ledger enable row level security;
alter table public.employee_number_allocation_ledger force row level security;
alter table public.employee_identity_activation_events enable row level security;
alter table public.employee_identity_activation_events force row level security;

revoke all privileges on table public.employee_identity_reservations from public, anon, authenticated, service_role;
revoke all privileges on table public.employee_number_allocation_ledger from public, anon, authenticated, service_role;
revoke all privileges on table public.employee_identity_activation_events from public, anon, authenticated, service_role;

create function public.guard_employee_identity_reservation_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'EMPLOYEE_IDENTITY_RESERVATION_IMMUTABLE';
  end if;

  if new.employee_identity_id is distinct from old.employee_identity_id
    or new.employee_number is distinct from old.employee_number
    or new.display_name is distinct from old.display_name
    or new.allocated_at is distinct from old.allocated_at then
    raise exception using errcode = '55000', message = 'EMPLOYEE_IDENTITY_RESERVATION_IMMUTABLE';
  end if;

  if old.identity_status = 'PRE_EMPLOYMENT'
    and old.workforce_employee_id is null
    and old.activated_at is null
    and new.identity_status = 'ACTIVATED'
    and new.workforce_employee_id is not null
    and new.activated_at is not null then
    return new;
  end if;

  raise exception using errcode = '55000', message = 'EMPLOYEE_IDENTITY_BINDING_IMMUTABLE';
end;
$$;

create trigger trg_employee_identity_reservations_guard
before update or delete on public.employee_identity_reservations
for each row execute function public.guard_employee_identity_reservation_mutation_v1();

create function public.prevent_employee_number_allocation_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'EMPLOYEE_NUMBER_ALLOCATION_IMMUTABLE';
end;
$$;

create trigger trg_employee_number_allocation_ledger_immutable
before update or delete on public.employee_number_allocation_ledger
for each row execute function public.prevent_employee_number_allocation_mutation_v1();

create function public.prevent_employee_identity_activation_event_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'EMPLOYEE_IDENTITY_ACTIVATION_EVENT_IMMUTABLE';
end;
$$;

create trigger trg_employee_identity_activation_events_immutable
before update or delete on public.employee_identity_activation_events
for each row execute function public.prevent_employee_identity_activation_event_mutation_v1();

create function public.reserve_employee_identity_v1(
  p_display_name text,
  p_allocation_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_employee_identity_id uuid;
  v_employee_number text;
  v_sequence_value bigint;
begin
  if nullif(btrim(p_display_name), '') is null then
    raise exception using errcode = '22023', message = 'EMPLOYEE_IDENTITY_DISPLAY_NAME_REQUIRED';
  end if;
  if nullif(btrim(p_allocation_reason), '') is null then
    raise exception using errcode = '22023', message = 'EMPLOYEE_IDENTITY_ALLOCATION_REASON_REQUIRED';
  end if;

  v_sequence_value := nextval('public.employee_identity_number_seq'::regclass);
  if v_sequence_value > 99999 then
    raise exception using errcode = '22003', message = 'EMPLOYEE_IDENTITY_NUMBER_SPACE_EXHAUSTED';
  end if;
  v_employee_number := 'LWS-' || lpad(v_sequence_value::text, 5, '0');

  insert into public.employee_identity_reservations(employee_number, display_name)
  values (v_employee_number, btrim(p_display_name))
  returning employee_identity_id into v_employee_identity_id;

  insert into public.employee_number_allocation_ledger(
    employee_identity_id,
    employee_number,
    allocation_reason
  ) values (
    v_employee_identity_id,
    v_employee_number,
    btrim(p_allocation_reason)
  );

  return jsonb_build_object(
    'employee_identity_id', v_employee_identity_id,
    'employee_number', v_employee_number,
    'identity_status', 'PRE_EMPLOYMENT'
  );
end;
$$;

revoke all on function public.reserve_employee_identity_v1(text, text) from public, anon, authenticated, service_role;

create function public.activate_workforce_employee_identity_v1(
  p_employee_identity_id uuid,
  p_start_date date,
  p_employment_status text,
  p_role_title text default null,
  p_team_name text default null,
  p_end_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_identity public.employee_identity_reservations%rowtype;
  v_workforce_employee_id uuid;
  v_activated_at timestamptz := clock_timestamp();
begin
  if p_start_date is null then
    raise exception using errcode = '23502', message = 'WORKFORCE_START_DATE_REQUIRED';
  end if;
  if p_employment_status is null or p_employment_status not in ('ACTIVE', 'INACTIVE') then
    raise exception using errcode = '22023', message = 'WORKFORCE_EMPLOYMENT_STATUS_INVALID';
  end if;

  select *
  into v_identity
  from public.employee_identity_reservations
  where employee_identity_id = p_employee_identity_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'EMPLOYEE_IDENTITY_NOT_FOUND';
  end if;
  if v_identity.identity_status <> 'PRE_EMPLOYMENT'
    or v_identity.workforce_employee_id is not null then
    raise exception using errcode = '55000', message = 'EMPLOYEE_IDENTITY_ALREADY_ACTIVATED';
  end if;

  insert into public.workforce_employees(
    display_name,
    role_title,
    team_name,
    employment_status,
    start_date,
    end_date,
    commercial_operator_id
  ) values (
    v_identity.display_name,
    p_role_title,
    p_team_name,
    p_employment_status,
    p_start_date,
    p_end_date,
    null
  )
  returning id into v_workforce_employee_id;

  update public.employee_identity_reservations
  set identity_status = 'ACTIVATED',
      workforce_employee_id = v_workforce_employee_id,
      activated_at = v_activated_at
  where employee_identity_id = v_identity.employee_identity_id;

  insert into public.employee_identity_activation_events(
    employee_identity_id,
    workforce_employee_id,
    employee_number,
    activated_at
  ) values (
    v_identity.employee_identity_id,
    v_workforce_employee_id,
    v_identity.employee_number,
    v_activated_at
  );

  return jsonb_build_object(
    'employee_identity_id', v_identity.employee_identity_id,
    'employee_number', v_identity.employee_number,
    'workforce_employee_id', v_workforce_employee_id,
    'identity_status', 'ACTIVATED'
  );
end;
$$;

revoke all on function public.activate_workforce_employee_identity_v1(uuid, date, text, text, text, date) from public, anon, authenticated, service_role;

with reserved(employee_number, display_name) as (
  values
    ('LWS-00001'::text, 'Lorenzo Bombello'::text),
    ('LWS-00002'::text, 'Herlinde Verlodt'::text),
    ('LWS-00003'::text, 'Daisy Defraine'::text)
), inserted as (
  insert into public.employee_identity_reservations(employee_number, display_name)
  select employee_number, display_name
  from reserved
  order by employee_number
  returning employee_identity_id, employee_number
)
insert into public.employee_number_allocation_ledger(
  employee_identity_id,
  employee_number,
  allocation_reason
)
select
  employee_identity_id,
  employee_number,
  'OWNER_APPROVED_C3A_INITIAL_RESERVATION'
from inserted;