create table public.operator_profile_definitions (
  profile_code text primary key check (profile_code in ('OP-01', 'OP-02', 'OP-03')),
  email text not null unique check (email = lower(email) and email = btrim(email)),
  display_name text not null check (char_length(btrim(display_name)) between 1 and 120),
  profile_role text not null check (profile_role in ('owner', 'operations_manager', 'finance')),
  role_label text not null check (char_length(btrim(role_label)) between 1 and 120),
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'DISABLED')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint operator_profile_definition_exact_role check (
    (profile_code = 'OP-01' and profile_role = 'owner' and role_label = 'Owner')
    or (profile_code = 'OP-02' and profile_role = 'operations_manager' and role_label = 'Management / HR & Operations')
    or (profile_code = 'OP-03' and profile_role = 'finance' and role_label = 'Finance')
  )
);

alter table public.operator_profile_definitions enable row level security;
alter table public.operator_profile_definitions force row level security;
revoke all on table public.operator_profile_definitions from public, anon, authenticated, service_role;

insert into public.operator_profile_definitions (
  profile_code,
  email,
  display_name,
  profile_role,
  role_label
)
values
  ('OP-01', 'lorenzo@lorenzowebsolutions.be', 'Lorenzo Bombello', 'owner', 'Owner'),
  ('OP-02', 'herlinde@lorenzowebsolutions.be', 'Herlinde Verlodt', 'operations_manager', 'Management / HR & Operations'),
  ('OP-03', 'finance@lorenzowebsolutions.be', 'Daisy Defraine', 'finance', 'Finance');

create function public.get_current_operator_profile_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_profile public.operator_profile_definitions%rowtype;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select profile.*
  into v_profile
  from auth.users as auth_user
  join public.operator_profile_definitions as profile
    on auth_user.email = profile.email
  where auth_user.id = v_subject
    and auth_user.email_confirmed_at is not null;

  if not found then
    raise exception using errcode = '42501', message = 'OPERATOR_PROFILE_NOT_CONFIGURED';
  end if;
  if v_profile.status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_PROFILE_INACTIVE';
  end if;

  return jsonb_build_object(
    'profile_code', v_profile.profile_code,
    'display_name', v_profile.display_name,
    'email', v_profile.email,
    'role', v_profile.profile_role,
    'role_label', v_profile.role_label,
    'status', v_profile.status
  );
end;
$$;

revoke all on function public.get_current_operator_profile_v1() from public, anon, service_role;
grant execute on function public.get_current_operator_profile_v1() to authenticated;

create or replace function public.get_current_operator_identity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_profile public.operator_profile_definitions%rowtype;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;

  if found then
    if v_operator.status = 'DISABLED' then
      raise exception using errcode = '42501', message = 'OPERATOR_DISABLED';
    end if;
    if v_operator.status = 'REVOKED' then
      raise exception using errcode = '42501', message = 'OPERATOR_REVOKED';
    end if;
    if v_operator.status <> 'ACTIVE' then
      raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
    end if;
    return jsonb_build_object(
      'display_name', v_operator.display_name,
      'role', v_operator.role,
      'status', v_operator.status
    );
  end if;

  select profile.*
  into v_profile
  from auth.users as auth_user
  join public.operator_profile_definitions as profile
    on auth_user.email = profile.email
  where auth_user.id = v_subject
    and auth_user.email_confirmed_at is not null;

  if not found or v_profile.status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR';
  end if;

  return jsonb_build_object(
    'display_name', v_profile.display_name,
    'role', 'profile_only',
    'status', 'ACTIVE'
  );
end;
$$;