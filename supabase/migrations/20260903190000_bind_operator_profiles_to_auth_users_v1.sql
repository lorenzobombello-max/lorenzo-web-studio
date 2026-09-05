alter table public.operator_profile_definitions
  add column auth_user_id uuid unique references auth.users(id);

do $$
declare
  v_bound_count integer;
begin
  if not exists (
    select 1 from auth.users
    where id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'
      and email = 'lorenzo@lorenzowebsolutions.be'
      and email_confirmed_at is not null
  ) then
    raise exception using errcode = '23503', message = 'OP_01_AUTH_ACCOUNT_MISMATCH';
  end if;
  if not exists (
    select 1 from auth.users
    where id = 'bd2ab636-0d42-4069-88a9-60bd97f2b335'
      and email = 'herlinde@lorenzowebsolutions.be'
      and email_confirmed_at is not null
  ) then
    raise exception using errcode = '23503', message = 'OP_02_AUTH_ACCOUNT_MISMATCH';
  end if;
  if not exists (
    select 1 from auth.users
    where id = 'd0247fd9-60d5-40bc-a905-6b02024b6420'
      and email = 'finance@lorenzowebsolutions.be'
      and email_confirmed_at is not null
  ) then
    raise exception using errcode = '23503', message = 'OP_03_AUTH_ACCOUNT_MISMATCH';
  end if;

  update public.operator_profile_definitions
  set auth_user_id = case profile_code
    when 'OP-01' then 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'::uuid
    when 'OP-02' then 'bd2ab636-0d42-4069-88a9-60bd97f2b335'::uuid
    when 'OP-03' then 'd0247fd9-60d5-40bc-a905-6b02024b6420'::uuid
  end,
  updated_at = clock_timestamp()
  where profile_code in ('OP-01', 'OP-02', 'OP-03');

  get diagnostics v_bound_count = row_count;
  if v_bound_count <> 3 then
    raise exception using errcode = 'P0001', message = 'OPERATOR_PROFILE_BINDING_INCOMPLETE';
  end if;

  if exists (
    select 1
    from public.commercial_operators
    where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'
      and (display_name <> 'Lorenzo Bombello' or role <> 'owner' or status <> 'ACTIVE')
  ) then
    raise exception using errcode = 'P0001', message = 'OP_01_AUTHORITY_CONFLICT';
  end if;
  if exists (
    select 1
    from public.commercial_operators
    where auth_user_id = 'bd2ab636-0d42-4069-88a9-60bd97f2b335'
      and (display_name <> 'Herlinde Verlodt' or role <> 'operations_manager' or status <> 'ACTIVE')
  ) then
    raise exception using errcode = 'P0001', message = 'OP_02_AUTHORITY_CONFLICT';
  end if;
  if exists (
    select 1
    from public.commercial_operators
    where auth_user_id = 'd0247fd9-60d5-40bc-a905-6b02024b6420'
  ) then
    raise exception using errcode = 'P0001', message = 'OP_03_COMMERCIAL_AUTHORITY_FORBIDDEN';
  end if;

  insert into public.commercial_operators (auth_user_id, display_name, role, status)
  select 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'Lorenzo Bombello', 'owner', 'ACTIVE'
  where not exists (
    select 1 from public.commercial_operators
    where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'
  );

  insert into public.commercial_operators (auth_user_id, display_name, role, status)
  select 'bd2ab636-0d42-4069-88a9-60bd97f2b335', 'Herlinde Verlodt', 'operations_manager', 'ACTIVE'
  where not exists (
    select 1 from public.commercial_operators
    where auth_user_id = 'bd2ab636-0d42-4069-88a9-60bd97f2b335'
  );
end;
$$;

alter table public.operator_profile_definitions
  alter column auth_user_id set not null;

create or replace function public.get_current_operator_profile_v1()
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
  from public.operator_profile_definitions as profile
  where profile.auth_user_id = v_subject;

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
  from public.operator_profile_definitions as profile
  where profile.auth_user_id = v_subject;

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

comment on column public.operator_profile_definitions.auth_user_id is
  'Immutable server-authoritative binding to the verified Supabase Auth account for this approved profile.';