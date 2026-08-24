alter table public.commercial_operators
  drop constraint commercial_operators_role_check;

alter table public.commercial_operators
  add constraint commercial_operators_role_check
  check (role in ('owner', 'admin', 'operations_manager', 'operator', 'reviewer', 'read_only'));

create table lws_internal.operations_manager_role_events (
  event_id bigint generated always as identity primary key,
  target_operator_id uuid not null references public.commercial_operators(operator_id),
  actor_auth_user_id uuid not null references auth.users(id),
  previous_role text not null
    check (previous_role in ('admin', 'operations_manager', 'operator', 'reviewer', 'read_only')),
  new_role text not null
    check (new_role in ('operations_manager', 'operator', 'reviewer', 'read_only')),
  event_type text not null check (event_type in ('APPOINTED', 'REVOKED')),
  reason text not null check (char_length(btrim(reason)) between 1 and 500),
  occurred_at timestamptz not null default clock_timestamp(),
  constraint operations_manager_role_event_transition_valid check (
    (event_type = 'APPOINTED'
      and previous_role in ('admin', 'operator', 'reviewer', 'read_only')
      and new_role = 'operations_manager')
    or
    (event_type = 'REVOKED'
      and previous_role = 'operations_manager'
      and new_role in ('operator', 'reviewer', 'read_only'))
  )
);

alter table lws_internal.operations_manager_role_events enable row level security;
alter table lws_internal.operations_manager_role_events force row level security;

revoke all on table lws_internal.operations_manager_role_events
from public, anon, authenticated, service_role;
revoke all on sequence lws_internal.operations_manager_role_events_event_id_seq
from public, anon, authenticated, service_role;

create function lws_internal.prevent_operations_manager_role_event_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'OPERATIONS_MANAGER_ROLE_EVENT_APPEND_ONLY';
end;
$$;

create trigger trg_operations_manager_role_events_append_only
before update or delete on lws_internal.operations_manager_role_events
for each row execute function lws_internal.prevent_operations_manager_role_event_mutation_v1();

create function lws_internal.guard_operations_manager_project_grant_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_operator_role text;
  v_operator_status text;
begin
  if new.revoked_at is not null then
    return new;
  end if;

  select role, status
  into v_operator_role, v_operator_status
  from public.commercial_operators
  where operator_id = new.operator_id
  for key share;

  if not found then
    raise exception using errcode = '23503', message = 'PROJECT_GRANT_OPERATOR_NOT_FOUND';
  end if;
  if v_operator_role = 'operations_manager' then
    raise exception using errcode = '42501', message = 'OPERATIONS_MANAGER_PROJECT_GRANT_DENIED';
  end if;

  return new;
end;
$$;

create trigger trg_operations_manager_project_grant_guard
before insert or update on public.commercial_operator_project_grants
for each row execute function lws_internal.guard_operations_manager_project_grant_v1();

create function public.appoint_operations_manager_v1(
  p_operator_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_actor public.commercial_operators%rowtype;
  v_target public.commercial_operators%rowtype;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_appointment_at timestamptz;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_actor
  from public.commercial_operators
  where auth_user_id = v_subject and status = 'ACTIVE';
  if not found or v_actor.role <> 'owner' then
    raise exception using errcode = '42501', message = 'OWNER_REQUIRED';
  end if;
  if char_length(v_reason) < 1 or char_length(v_reason) > 500 then
    raise exception using errcode = '22023', message = 'INVALID_AUTHORITY_REASON';
  end if;

  select * into v_target
  from public.commercial_operators
  where operator_id = p_operator_id
  for update;
  if not found then
    raise exception using errcode = '23503', message = 'TARGET_OPERATOR_NOT_FOUND';
  end if;
  if v_target.role = 'owner' then
    raise exception using errcode = '42501', message = 'OWNER_ROLE_IMMUTABLE';
  end if;
  if v_target.status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'TARGET_OPERATOR_NOT_ACTIVE';
  end if;
  if v_target.role = 'operations_manager' then
    raise exception using errcode = '22023', message = 'OPERATIONS_MANAGER_ALREADY_APPOINTED';
  end if;

  v_appointment_at := clock_timestamp();
  update public.commercial_operator_project_grants
  set revoked_at = v_appointment_at
  where operator_id = v_target.operator_id
    and revoked_at is null;

  perform set_config('lws.operator_admin', 'on', true);
  update public.commercial_operators
  set role = 'operations_manager', updated_at = v_appointment_at
  where operator_id = v_target.operator_id;
  perform set_config('lws.operator_admin', '', true);

  insert into lws_internal.operations_manager_role_events (
    target_operator_id, actor_auth_user_id, previous_role, new_role, event_type, reason, occurred_at
  ) values (
    v_target.operator_id, v_subject, v_target.role, 'operations_manager', 'APPOINTED', v_reason, v_appointment_at
  );

  return jsonb_build_object('operator_id', v_target.operator_id, 'role', 'operations_manager');
end;
$$;

create function public.revoke_operations_manager_v1(
  p_operator_id uuid,
  p_reason text,
  p_fallback_role text default 'operator'
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_actor public.commercial_operators%rowtype;
  v_target public.commercial_operators%rowtype;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_actor
  from public.commercial_operators
  where auth_user_id = v_subject and status = 'ACTIVE';
  if not found or v_actor.role <> 'owner' then
    raise exception using errcode = '42501', message = 'OWNER_REQUIRED';
  end if;
  if char_length(v_reason) < 1 or char_length(v_reason) > 500 then
    raise exception using errcode = '22023', message = 'INVALID_AUTHORITY_REASON';
  end if;
  if p_fallback_role is null
     or p_fallback_role not in ('operator', 'reviewer', 'read_only') then
    raise exception using errcode = '22023', message = 'INVALID_OPERATIONS_MANAGER_FALLBACK_ROLE';
  end if;

  select * into v_target
  from public.commercial_operators
  where operator_id = p_operator_id
  for update;
  if not found then
    raise exception using errcode = '23503', message = 'TARGET_OPERATOR_NOT_FOUND';
  end if;
  if v_target.role = 'owner' then
    raise exception using errcode = '42501', message = 'OWNER_ROLE_IMMUTABLE';
  end if;
  if v_target.role <> 'operations_manager' then
    raise exception using errcode = '22023', message = 'OPERATIONS_MANAGER_ROLE_REQUIRED';
  end if;

  perform set_config('lws.operator_admin', 'on', true);
  update public.commercial_operators
  set role = p_fallback_role, updated_at = clock_timestamp()
  where operator_id = v_target.operator_id;
  perform set_config('lws.operator_admin', '', true);

  insert into lws_internal.operations_manager_role_events (
    target_operator_id, actor_auth_user_id, previous_role, new_role, event_type, reason
  ) values (
    v_target.operator_id, v_subject, 'operations_manager', p_fallback_role, 'REVOKED', v_reason
  );

  return jsonb_build_object('operator_id', v_target.operator_id, 'role', p_fallback_role);
end;
$$;

create function public.get_operations_manager_session_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
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
  if v_operator.status = 'DISABLED' then
    raise exception using errcode = '42501', message = 'OPERATOR_DISABLED';
  end if;
  if v_operator.status = 'REVOKED' then
    raise exception using errcode = '42501', message = 'OPERATOR_REVOKED';
  end if;
  if v_operator.status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;
  if v_operator.role <> 'operations_manager' then
    raise exception using errcode = '42501', message = 'OPERATIONS_MANAGER_REQUIRED';
  end if;
  return jsonb_build_object('operator_id', v_operator.operator_id, 'role', v_operator.role);
end;
$$;

revoke all on function public.appoint_operations_manager_v1(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.revoke_operations_manager_v1(uuid, text, text)
from public, anon, authenticated, service_role;
revoke all on function public.get_operations_manager_session_v1()
from public, anon, authenticated, service_role;

grant execute on function public.appoint_operations_manager_v1(uuid, text)
to authenticated;
grant execute on function public.revoke_operations_manager_v1(uuid, text, text)
to authenticated;
grant execute on function public.get_operations_manager_session_v1()
to authenticated;

revoke all on function lws_internal.prevent_operations_manager_role_event_mutation_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_operations_manager_project_grant_v1()
from public, anon, authenticated, service_role;

comment on table lws_internal.operations_manager_role_events is
  'Immutable owner-authorized Operations Manager appointment and revocation evidence.';
comment on function public.get_operations_manager_session_v1() is
  'Minimal active human Operations Manager identity proof; grants no business authority.';