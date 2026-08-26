create function public.get_current_operator_identity_v1()
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

  select *
  into v_operator
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

  return jsonb_build_object(
    'display_name', v_operator.display_name,
    'role', v_operator.role,
    'status', v_operator.status
  );
end;
$$;

revoke all on function public.get_current_operator_identity_v1() from public, anon, service_role;
grant execute on function public.get_current_operator_identity_v1() to authenticated;
