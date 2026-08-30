create table public.workforce_employees (
  id uuid primary key default gen_random_uuid(),
  display_name text not null check (nullif(btrim(display_name), '') is not null),
  role_title text,
  team_name text,
  employment_status text not null check (employment_status in ('ACTIVE', 'INACTIVE')),
  start_date date not null,
  end_date date,
  commercial_operator_id uuid unique references public.commercial_operators(operator_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint workforce_employees_date_order check (end_date is null or end_date >= start_date)
);

create table public.workforce_calendar_entries (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.workforce_employees(id) on delete restrict,
  calendar_date date not null,
  status text not null check (status in (
    'WORKED_FULL_DAY',
    'WORKED_HALF_DAY_AM',
    'WORKED_HALF_DAY_PM',
    'LEAVE',
    'SICK',
    'OTHER_ABSENCE'
  )),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint workforce_calendar_entries_employee_date_key unique (employee_id, calendar_date)
);

alter table public.workforce_employees enable row level security;
alter table public.workforce_employees force row level security;
alter table public.workforce_calendar_entries enable row level security;
alter table public.workforce_calendar_entries force row level security;

revoke all privileges on table public.workforce_employees from public, anon, authenticated, service_role;
revoke all privileges on table public.workforce_calendar_entries from public, anon, authenticated, service_role;

comment on table public.workforce_employees is
  'Workforce person authority, separate from optional commercial operator account identity.';
comment on column public.workforce_employees.commercial_operator_id is
  'Optional account link only; a commercial operator is not implicitly a workforce employee.';
comment on table public.workforce_calendar_entries is
  'Read-only calendar presentation authority with at most one effective status per employee and date.';

create function public.list_workforce_calendar_v1(
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
  v_actor public.commercial_operators%rowtype;
  v_result jsonb;
begin
  if p_actor_id is null then
    raise exception using errcode = '42501', message = 'WORKFORCE_ACTOR_REQUIRED';
  end if;
  if p_start_date is null or p_end_date is null then
    raise exception using errcode = '22023', message = 'WORKFORCE_DATE_RANGE_REQUIRED';
  end if;
  if p_start_date > p_end_date then
    raise exception using errcode = '22023', message = 'WORKFORCE_DATE_RANGE_REVERSED';
  end if;
  if p_end_date - p_start_date > 365 then
    raise exception using errcode = '22023', message = 'WORKFORCE_DATE_RANGE_TOO_LARGE';
  end if;

  select * into v_actor
  from public.commercial_operators
  where auth_user_id = p_actor_id;
  if not found then
    raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR';
  end if;
  if v_actor.status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_NOT_ACTIVE';
  end if;
  if v_actor.role not in ('owner', 'admin', 'operations_manager') then
    raise exception using errcode = '42501', message = 'WORKFORCE_MANAGEMENT_READER_REQUIRED';
  end if;

  select jsonb_build_object(
    'start_date', p_start_date,
    'end_date', p_end_date,
    'employees', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'employee_id', employee.id,
          'display_name', employee.display_name,
          'role_title', employee.role_title,
          'team_name', employee.team_name,
          'employment_status', employee.employment_status,
          'entries', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'date', entry.calendar_date,
                'status', entry.status
              ) order by entry.calendar_date
            )
            from public.workforce_calendar_entries as entry
            where entry.employee_id = employee.id
              and entry.calendar_date between p_start_date and p_end_date
          ), '[]'::jsonb)
        ) order by lower(employee.display_name), employee.id
      ) filter (where employee.id is not null),
      '[]'::jsonb
    )
  ) into v_result
  from public.workforce_employees as employee
  where employee.start_date <= p_end_date
    and (employee.end_date is null or employee.end_date >= p_start_date);

  return v_result;
end;
$$;

revoke all on function public.list_workforce_calendar_v1(uuid, date, date)
from public, anon, authenticated, service_role;
grant execute on function public.list_workforce_calendar_v1(uuid, date, date)
to service_role;

comment on function public.list_workforce_calendar_v1(uuid, date, date) is
  'Service-only bounded workforce calendar projection for an Edge-verified active management actor auth user ID.';