create function public.list_operator_workforce_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_result jsonb;
begin
  v_operator := lws_internal.require_active_workspace_operator_v1();
  if v_operator.role not in ('owner', 'admin', 'operations_manager') then
    raise exception using errcode = '42501', message = 'WORKFORCE_MANAGEMENT_READER_REQUIRED';
  end if;

  select jsonb_build_object(
    'employees', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'employee_id', employee.id,
          'display_name', employee.display_name,
          'role_title', employee.role_title,
          'team_name', employee.team_name,
          'employment_status', employee.employment_status,
          'start_date', employee.start_date
        ) order by lower(employee.display_name), employee.id
      ) filter (where employee.id is not null),
      '[]'::jsonb
    )
  ) into v_result
  from public.workforce_employees as employee;

  return v_result;
end;
$$;

revoke all on function public.list_operator_workforce_v1()
from public, anon, authenticated, service_role;
grant execute on function public.list_operator_workforce_v1() to authenticated;

comment on function public.list_operator_workforce_v1() is
  'Caller-JWT read-only Personnel list with minimum non-sensitive workforce fields for active management readers.';