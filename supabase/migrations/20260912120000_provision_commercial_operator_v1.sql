begin;

create table lws_internal.commercial_operator_provisioning_events (
  event_id bigint generated always as identity primary key,
  target_operator_id uuid not null unique
    references public.commercial_operators(operator_id),
  target_auth_user_id uuid not null unique references auth.users(id),
  actor_operator_id uuid not null references public.commercial_operators(operator_id),
  actor_auth_user_id uuid not null references auth.users(id),
  event_type text not null check (event_type = 'COMMERCIAL_OPERATOR_PROVISIONED'),
  target_role text not null
    check (target_role in ('admin', 'operator', 'reviewer', 'read_only')),
  target_status text not null check (target_status = 'ACTIVE'),
  occurred_at timestamptz not null default clock_timestamp(),
  metadata jsonb not null check (
    public.jsonb_has_exact_keys(metadata, array['contract_version', 'display_name'])
    and metadata->>'contract_version' = '1'
    and char_length(btrim(metadata->>'display_name')) between 1 and 120
  )
);

alter table lws_internal.commercial_operator_provisioning_events enable row level security;
alter table lws_internal.commercial_operator_provisioning_events force row level security;

revoke all on table lws_internal.commercial_operator_provisioning_events
from public, anon, authenticated, service_role;
revoke all on sequence lws_internal.commercial_operator_provisioning_events_event_id_seq
from public, anon, authenticated, service_role;

create function lws_internal.guard_commercial_operator_provisioning_event_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'COMMERCIAL_OPERATOR_PROVISIONING_EVENT_APPEND_ONLY';
end;
$$;

revoke all on function lws_internal.guard_commercial_operator_provisioning_event_v1()
from public, anon, authenticated, service_role;

create trigger trg_commercial_operator_provisioning_events_append_only
before update or delete on lws_internal.commercial_operator_provisioning_events
for each row execute function lws_internal.guard_commercial_operator_provisioning_event_v1();

create function public.provision_commercial_operator_v1(
  p_target_auth_user_id uuid,
  p_display_name text,
  p_role text,
  p_status text
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
  v_display_name text := btrim(coalesce(p_display_name, ''));
  v_created_at timestamptz;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  perform lws_internal.assert_operator_aal2_v1();

  select * into v_actor
  from public.commercial_operators
  where auth_user_id = v_subject;
  if not found then
    raise exception using errcode = '42501', message = 'PROVISIONING_OWNER_REQUIRED';
  end if;
  if v_actor.status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;
  if v_actor.role <> 'owner' then
    raise exception using errcode = '42501', message = 'PROVISIONING_OWNER_REQUIRED';
  end if;

    if p_target_auth_user_id is null
      or char_length(v_display_name) not between 1 and 120
      or p_role is null
      or p_role not in ('admin', 'operator', 'reviewer', 'read_only')
      or p_status is null
      or p_status <> 'ACTIVE' then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_PROVISIONING_REQUEST';
  end if;

  if not exists (
    select 1
    from auth.users
    where id = p_target_auth_user_id
  ) then
    raise exception using errcode = '23503', message = 'TARGET_AUTH_USER_NOT_FOUND';
  end if;
  if not exists (
    select 1
    from auth.users
    where id = p_target_auth_user_id
      and email_confirmed_at is not null
  ) then
    raise exception using errcode = '42501', message = 'TARGET_AUTH_EMAIL_NOT_CONFIRMED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_target_auth_user_id::text, 0)
  );

  select * into v_target
  from public.commercial_operators
  where auth_user_id = p_target_auth_user_id
  for update;
  if found then
    if v_target.display_name = v_display_name
       and v_target.role = p_role
       and v_target.status = p_status then
      return jsonb_build_object(
        'operator_id', v_target.operator_id,
        'auth_user_id', v_target.auth_user_id,
        'display_name', v_target.display_name,
        'role', v_target.role,
        'status', v_target.status,
        'replayed', true
      );
    end if;
    raise exception using errcode = '23505', message = 'OPERATOR_BINDING_CONFLICT';
  end if;

  insert into public.commercial_operators (
    auth_user_id,
    display_name,
    role,
    status
  ) values (
    p_target_auth_user_id,
    v_display_name,
    p_role,
    p_status
  ) returning * into v_target;

  insert into lws_internal.commercial_operator_provisioning_events (
    target_operator_id,
    target_auth_user_id,
    actor_operator_id,
    actor_auth_user_id,
    event_type,
    target_role,
    target_status,
    metadata
  ) values (
    v_target.operator_id,
    v_target.auth_user_id,
    v_actor.operator_id,
    v_subject,
    'COMMERCIAL_OPERATOR_PROVISIONED',
    v_target.role,
    v_target.status,
    jsonb_build_object(
      'contract_version', 1,
      'display_name', v_target.display_name
    )
  ) returning occurred_at into v_created_at;

  return jsonb_build_object(
    'operator_id', v_target.operator_id,
    'auth_user_id', v_target.auth_user_id,
    'display_name', v_target.display_name,
    'role', v_target.role,
    'status', v_target.status,
    'provisioned_at', v_created_at,
    'replayed', false
  );
end;
$$;

revoke all on function public.provision_commercial_operator_v1(uuid, text, text, text)
from public, anon, service_role;
grant execute on function public.provision_commercial_operator_v1(uuid, text, text, text)
to authenticated;

comment on table lws_internal.commercial_operator_provisioning_events is
  'Append-only audit authority for owner-AAL2 commercial operator provisioning.';
comment on function public.provision_commercial_operator_v1(uuid, text, text, text) is
  'Provisions one confirmed Auth user through an ACTIVE owner AAL2 caller without direct table grants.';

commit;