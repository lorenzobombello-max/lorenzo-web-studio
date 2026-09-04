create function public.guard_reserved_operator_profile_slots_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_profile_code text := case when tg_op = 'DELETE' then old.profile_code else new.profile_code end;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    if old.profile_code in ('OP-01', 'OP-02', 'OP-03') then
      raise exception using errcode = '55000', message = 'RESERVED_OPERATOR_PROFILE_IMMUTABLE';
    end if;
    raise exception using errcode = '55000', message = 'OPERATOR_PROFILE_SLOT_IMMUTABLE';
  end if;

  if v_profile_code in ('OP-01', 'OP-02', 'OP-03') then
    raise exception using errcode = '55000', message = 'RESERVED_OPERATOR_PROFILE_IMMUTABLE';
  end if;

  if v_profile_code !~ '^OP-[0-9]{2,}$'
    or substring(v_profile_code from 4)::integer < 4 then
    raise exception using errcode = '22023', message = 'OPERATOR_PROFILE_SLOT_INVALID';
  end if;

  return new;
end;
$$;

create trigger trg_operator_profile_reserved_slots_guard
before insert or update or delete on public.operator_profile_definitions
for each row execute function public.guard_reserved_operator_profile_slots_v1();

create function public.guard_workforce_reserved_operator_link_v1()
returns trigger
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
begin
  if new.commercial_operator_id is null then
    return new;
  end if;

  if exists (
    select 1
    from public.commercial_operators as operator
    join auth.users as auth_user on auth_user.id = operator.auth_user_id
    join public.operator_profile_definitions as profile on profile.email = auth_user.email
    where operator.operator_id = new.commercial_operator_id
      and profile.profile_code in ('OP-01', 'OP-02', 'OP-03')
  ) then
    raise exception using errcode = '55000', message = 'RESERVED_OPERATOR_PROFILE_LINK_FORBIDDEN';
  end if;

  return new;
end;
$$;

create trigger trg_workforce_reserved_operator_link_guard
before insert or update of commercial_operator_id on public.workforce_employees
for each row execute function public.guard_workforce_reserved_operator_link_v1();

revoke all on function public.guard_reserved_operator_profile_slots_v1() from public, anon, authenticated, service_role;
revoke all on function public.guard_workforce_reserved_operator_link_v1() from public, anon, authenticated, service_role;

comment on function public.guard_reserved_operator_profile_slots_v1() is
  'Fail-closed protection for occupied OP-01, OP-02, and OP-03. Future slots must start at OP-04 and profile codes cannot be reused.';
comment on function public.guard_workforce_reserved_operator_link_v1() is
  'Prevents occupied OP-01, OP-02, and OP-03 identities from being assigned to a workforce employee.';