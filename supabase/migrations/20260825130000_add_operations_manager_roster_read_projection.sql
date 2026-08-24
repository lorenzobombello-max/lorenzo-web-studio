create function public.get_operations_manager_roster_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_actor_role text;
  v_actor_status text;
  v_roster jsonb;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select role, status
  into v_actor_role, v_actor_status
  from public.commercial_operators
  where auth_user_id = v_subject;

  if not found then
    raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR';
  end if;
  if v_actor_status = 'DISABLED' then
    raise exception using errcode = '42501', message = 'OPERATOR_DISABLED';
  end if;
  if v_actor_status = 'REVOKED' then
    raise exception using errcode = '42501', message = 'OPERATOR_REVOKED';
  end if;
  if v_actor_status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;
  if v_actor_role not in ('owner', 'operations_manager') then
    raise exception using errcode = '42501', message = 'OPERATIONS_MANAGER_ROSTER_READER_REQUIRED';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'operator_id', operator.operator_id,
    'display_name', operator.display_name,
    'role', operator.role,
    'status', operator.status,
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'event_type', event.event_type,
        'occurred_at', event.occurred_at
      ) order by event.occurred_at, event.event_id)
      from lws_internal.operations_manager_role_events as event
      where event.target_operator_id = operator.operator_id
    ), '[]'::jsonb)
  ) order by operator.display_name, operator.operator_id), '[]'::jsonb)
  into v_roster
  from public.commercial_operators as operator;

  return v_roster;
end;
$$;

revoke all on function public.get_operations_manager_roster_v1()
from public, anon, authenticated, service_role;

grant execute on function public.get_operations_manager_roster_v1()
to authenticated;

comment on function public.get_operations_manager_roster_v1() is
  'Read-only global operator roster for active owners and Operations Managers; exposes only operator_id, display_name, role, status, and minimal appointment history.';