create schema if not exists lws_internal authorization postgres;

create table lws_internal.application_intake_automation_config (
  singleton boolean primary key default true,
  active boolean not null default false,
  cutover_at timestamptz,
  activation_reference text,
  activated_at timestamptz,
  deactivated_at timestamptz,
  constraint application_intake_automation_config_singleton check (singleton),
  constraint application_intake_automation_config_reference_valid check (
    activation_reference is null
    or char_length(btrim(activation_reference)) between 8 and 128
  ),
  constraint application_intake_automation_config_state_valid check (
    (
      active
      and cutover_at is not null
      and activation_reference is not null
      and activated_at = cutover_at
      and deactivated_at is null
    )
    or (
      not active
      and (
        (
          cutover_at is null
          and activation_reference is null
          and activated_at is null
          and deactivated_at is null
        )
        or (
          cutover_at is not null
          and activation_reference is not null
          and activated_at = cutover_at
          and deactivated_at is not null
          and deactivated_at >= activated_at
        )
      )
    )
  )
);

create table lws_internal.application_intake_automation_control_events (
  control_event_id bigint generated always as identity primary key,
  event_type text not null
    constraint application_intake_automation_control_events_type_valid
    check (event_type in ('ACTIVATED', 'DEACTIVATED')),
  activation_reference text not null
    constraint application_intake_automation_control_events_reference_valid
    check (char_length(btrim(activation_reference)) between 8 and 128),
  cutover_at timestamptz not null,
  occurred_at timestamptz not null default clock_timestamp()
);

create table lws_internal.application_intake_automation_work (
  work_id bigint generated always as identity primary key,
  quote_request_id uuid not null unique
    references public.quote_requests(id) on delete restrict,
  phase text not null default 'APPROVAL'
    constraint application_intake_automation_work_phase_valid
    check (phase in ('APPROVAL', 'INTAKE', 'COMPLETED', 'STOPPED', 'MANUAL_REVIEW')),
  approval_due_at timestamptz not null,
  approved_at timestamptz,
  intake_due_at timestamptz,
  attempt_count integer not null default 0
    constraint application_intake_automation_work_attempt_count_valid
    check (attempt_count between 0 and 5),
  next_attempt_at timestamptz not null,
  claim_token uuid,
  claimed_by uuid,
  claimed_at timestamptz,
  claim_expires_at timestamptz,
  last_error_code text,
  terminal_reason text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint application_intake_automation_work_timing_valid check (
    (
      approved_at is null
      and intake_due_at is null
    )
    or (
      approved_at is not null
      and intake_due_at = approved_at + interval '120 seconds'
    )
  ),
  constraint application_intake_automation_work_claim_valid check (
    (
      claim_token is null
      and claimed_by is null
      and claimed_at is null
      and claim_expires_at is null
    )
    or (
      claim_token is not null
      and claimed_by is not null
      and claimed_at is not null
      and claim_expires_at is not null
      and claim_expires_at > claimed_at
    )
  ),
  constraint application_intake_automation_work_schedule_valid check (
    next_attempt_at >= approval_due_at
  ),
  constraint application_intake_automation_work_error_code_valid check (
    last_error_code is null or last_error_code ~ '^[A-Z][A-Z0-9_]{2,63}$'
  ),
  constraint application_intake_automation_work_terminal_reason_valid check (
    terminal_reason is null or terminal_reason ~ '^[A-Z][A-Z0-9_]{2,63}$'
  ),
  constraint application_intake_automation_work_updated_at_valid check (
    updated_at >= created_at
  )
);

create index application_intake_automation_work_due_idx
  on lws_internal.application_intake_automation_work (phase, next_attempt_at)
  where phase in ('APPROVAL', 'INTAKE');

insert into lws_internal.application_intake_automation_config (singleton)
values (true);

create function lws_internal.prevent_application_intake_automation_control_event_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using
    errcode = '23514',
    message = 'APPLICATION_INTAKE_AUTOMATION_CONTROL_EVENT_IMMUTABLE';
end;
$$;

create trigger trg_application_intake_automation_control_events_immutable
before update or delete on lws_internal.application_intake_automation_control_events
for each row execute function lws_internal.prevent_application_intake_automation_control_event_mutation_v1();

create function lws_internal.prevent_application_intake_automation_work_identity_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.work_id is distinct from old.work_id
     or new.quote_request_id is distinct from old.quote_request_id
     or new.approval_due_at is distinct from old.approval_due_at
     or new.created_at is distinct from old.created_at then
    raise exception using
      errcode = '23514',
      message = 'APPLICATION_INTAKE_AUTOMATION_WORK_IDENTITY_IMMUTABLE';
  end if;
  return new;
end;
$$;

create trigger trg_application_intake_automation_work_identity_immutable
before update on lws_internal.application_intake_automation_work
for each row execute function lws_internal.prevent_application_intake_automation_work_identity_mutation_v1();

create function lws_internal.set_application_intake_automation_work_updated_at_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger trg_application_intake_automation_work_updated_at
before update on lws_internal.application_intake_automation_work
for each row execute function lws_internal.set_application_intake_automation_work_updated_at_v1();

create function public.activate_application_intake_automation_v1(
  p_activation_reference text
)
returns timestamptz
language plpgsql
volatile
security definer
set search_path = lws_internal, pg_catalog
as $$
declare
  v_config lws_internal.application_intake_automation_config%rowtype;
  v_cutover_at timestamptz;
begin
  if p_activation_reference is null
     or char_length(btrim(p_activation_reference)) not between 8 and 128 then
    raise exception using
      errcode = '22023',
      message = 'INVALID_AUTOMATION_ACTIVATION_REFERENCE';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(17003, 1);

  select * into strict v_config
  from lws_internal.application_intake_automation_config
  where singleton
  for update;

  if v_config.active or v_config.cutover_at is not null then
    raise exception using
      errcode = 'P0001',
      message = 'APPLICATION_INTAKE_AUTOMATION_ALREADY_ACTIVATED';
  end if;

  v_cutover_at := clock_timestamp();

  update lws_internal.application_intake_automation_config
  set active = true,
      cutover_at = v_cutover_at,
      activation_reference = btrim(p_activation_reference),
      activated_at = v_cutover_at,
      deactivated_at = null
  where singleton;

  insert into lws_internal.application_intake_automation_control_events (
    event_type,
    activation_reference,
    cutover_at,
    occurred_at
  ) values (
    'ACTIVATED',
    btrim(p_activation_reference),
    v_cutover_at,
    v_cutover_at
  );

  return v_cutover_at;
end;
$$;

create function public.deactivate_application_intake_automation_v1(
  p_activation_reference text
)
returns timestamptz
language plpgsql
volatile
security definer
set search_path = lws_internal, pg_catalog
as $$
declare
  v_config lws_internal.application_intake_automation_config%rowtype;
  v_deactivated_at timestamptz;
begin
  if p_activation_reference is null
     or char_length(btrim(p_activation_reference)) not between 8 and 128 then
    raise exception using
      errcode = '22023',
      message = 'INVALID_AUTOMATION_ACTIVATION_REFERENCE';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(17003, 1);

  select * into strict v_config
  from lws_internal.application_intake_automation_config
  where singleton
  for update;

  if not v_config.active then
    raise exception using
      errcode = 'P0001',
      message = 'APPLICATION_INTAKE_AUTOMATION_NOT_ACTIVE';
  end if;

  v_deactivated_at := clock_timestamp();

  update lws_internal.application_intake_automation_config
  set active = false,
      deactivated_at = v_deactivated_at
  where singleton;

  insert into lws_internal.application_intake_automation_control_events (
    event_type,
    activation_reference,
    cutover_at,
    occurred_at
  ) values (
    'DEACTIVATED',
    btrim(p_activation_reference),
    v_config.cutover_at,
    v_deactivated_at
  );

  return v_deactivated_at;
end;
$$;

create function lws_internal.enroll_application_intake_automation_v1()
returns trigger
language plpgsql
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_cutover_at timestamptz;
begin
  perform pg_catalog.pg_advisory_xact_lock(17003, 1);

  select cutover_at into v_cutover_at
  from lws_internal.application_intake_automation_config
  where singleton
    and active;

  if v_cutover_at is null
     or new.created_at < v_cutover_at
     or new.record_classification is distinct from 'production'
     or new.request_kind is distinct from 'website'
     or new.status is distinct from 'pending'::public.quote_request_status then
    return new;
  end if;

  insert into lws_internal.application_intake_automation_work (
    quote_request_id,
    phase,
    approval_due_at,
    next_attempt_at
  ) values (
    new.id,
    'APPROVAL',
    new.created_at + interval '120 seconds',
    new.created_at + interval '120 seconds'
  )
  on conflict (quote_request_id) do nothing;

  return new;
end;
$$;

create trigger trg_quote_requests_enroll_application_intake_automation
after insert on public.quote_requests
for each row execute function lws_internal.enroll_application_intake_automation_v1();

alter table lws_internal.application_intake_automation_config enable row level security;
alter table lws_internal.application_intake_automation_config force row level security;
alter table lws_internal.application_intake_automation_control_events enable row level security;
alter table lws_internal.application_intake_automation_control_events force row level security;
alter table lws_internal.application_intake_automation_work enable row level security;
alter table lws_internal.application_intake_automation_work force row level security;

revoke all on table lws_internal.application_intake_automation_config
  from public, anon, authenticated, service_role;
revoke all on table lws_internal.application_intake_automation_control_events
  from public, anon, authenticated, service_role;
revoke all on table lws_internal.application_intake_automation_work
  from public, anon, authenticated, service_role;

do $$
declare
  v_control_event_sequence text;
  v_work_sequence text;
begin
  v_control_event_sequence := pg_catalog.pg_get_serial_sequence(
    'lws_internal.application_intake_automation_control_events',
    'control_event_id'
  );
  v_work_sequence := pg_catalog.pg_get_serial_sequence(
    'lws_internal.application_intake_automation_work',
    'work_id'
  );

  execute pg_catalog.format(
    'revoke all on sequence %s from public, anon, authenticated, service_role',
    v_control_event_sequence
  );
  execute pg_catalog.format(
    'revoke all on sequence %s from public, anon, authenticated, service_role',
    v_work_sequence
  );
end;
$$;

revoke all on function public.activate_application_intake_automation_v1(text)
  from public, anon, authenticated, service_role;
revoke all on function public.deactivate_application_intake_automation_v1(text)
  from public, anon, authenticated, service_role;
grant execute on function public.activate_application_intake_automation_v1(text) to service_role;
grant execute on function public.deactivate_application_intake_automation_v1(text) to service_role;

revoke all on function lws_internal.prevent_application_intake_automation_control_event_mutation_v1()
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.prevent_application_intake_automation_work_identity_mutation_v1()
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.set_application_intake_automation_work_updated_at_v1()
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.enroll_application_intake_automation_v1()
  from public, anon, authenticated, service_role;