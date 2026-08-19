alter table public.quote_requests
  add column application_reference text;

alter table public.quote_requests
  add constraint quote_requests_application_reference_format_valid
  check (
    application_reference is null
    or application_reference ~ '^LWS-AAN-[0-9]{4}-[0-9]{4}$'
  );

alter table public.quote_requests
  add constraint quote_requests_application_reference_unique
  unique (application_reference);

create table public.application_reference_counters (
  reference_year smallint primary key,
  last_value integer not null,
  constraint application_reference_counters_year_valid
    check (reference_year between 2026 and 9999),
  constraint application_reference_counters_value_valid
    check (last_value between 1 and 9999)
);

alter table public.application_reference_counters enable row level security;

create function public.assign_application_reference_on_intake_submit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year smallint;
  v_sequence integer;
  v_existing_reference text;
begin
  if old.status = new.status or new.status <> 'submitted' then
    return new;
  end if;

  select application_reference into strict v_existing_reference
  from public.quote_requests
  where id = new.quote_request_id;

  if v_existing_reference is not null then
    return new;
  end if;

  v_year := extract(year from new.submitted_at at time zone 'Europe/Brussels')::smallint;

  insert into public.application_reference_counters as counter (
    reference_year,
    last_value
  ) values (
    v_year,
    1
  )
  on conflict (reference_year) do update
    set last_value = counter.last_value + 1
  returning last_value into v_sequence;

  if v_sequence > 9999 then
    raise exception using
      errcode = '22003',
      message = 'APPLICATION_REFERENCE_SEQUENCE_EXHAUSTED';
  end if;

  update public.quote_requests
  set application_reference = format(
    'LWS-AAN-%s-%s',
    v_year,
    lpad(v_sequence::text, 4, '0')
  )
  where id = new.quote_request_id
    and application_reference is null;

  return new;
end;
$$;

create trigger trg_quote_request_intakes_assign_application_reference
after update of status on public.quote_request_intakes
for each row
execute function public.assign_application_reference_on_intake_submit();

create function public.prevent_application_reference_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.application_reference is not null
     and new.application_reference is distinct from old.application_reference then
    raise exception using
      errcode = '23514',
      message = 'APPLICATION_REFERENCE_IMMUTABLE';
  end if;
  return new;
end;
$$;

create trigger trg_quote_requests_application_reference_immutable
before update of application_reference on public.quote_requests
for each row
execute function public.prevent_application_reference_update();

revoke all on table public.application_reference_counters
  from public, anon, authenticated;
revoke all on function public.assign_application_reference_on_intake_submit()
  from public, anon, authenticated, service_role;
revoke all on function public.prevent_application_reference_update()
  from public, anon, authenticated, service_role;