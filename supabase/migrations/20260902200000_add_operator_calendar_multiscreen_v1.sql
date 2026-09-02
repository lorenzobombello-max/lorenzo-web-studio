create function lws_internal.operator_workspace_module_authorized_v1(p_role text, p_module_key text)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select case lower(btrim(coalesce(p_module_key, '')))
    when 'messages' then p_role = 'owner'
    when 'calendar' then p_role in ('owner', 'admin', 'operations_manager')
    else false
  end;
$$;

revoke all on function lws_internal.operator_workspace_module_authorized_v1(text,text)
from public, anon, authenticated, service_role;

create function public.get_operator_calendar_v1(p_start_date date, p_end_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  return public.list_workforce_calendar_v1(v_subject, p_start_date, p_end_date);
end;
$$;

revoke all on function public.get_operator_calendar_v1(date,date)
from public, anon, authenticated, service_role;
grant execute on function public.get_operator_calendar_v1(date,date) to authenticated;

create or replace function public.join_operator_workspace_v1(
  p_workspace_id uuid,
  p_epoch bigint,
  p_window_id uuid,
  p_module_key text,
  p_slot_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_workspace public.operator_workspace_sessions%rowtype;
  v_claim public.operator_workspace_window_claims%rowtype;
  v_module_key text := lower(btrim(coalesce(p_module_key, '')));
  v_slot_key text := lower(btrim(coalesce(p_slot_key, '')));
  v_now timestamptz := clock_timestamp();
begin
  if p_window_id is null then raise exception using errcode = '22023', message = 'WINDOW_ID_REQUIRED'; end if;
  if v_module_key !~ '^[a-z][a-z0-9-]{0,47}$' then raise exception using errcode = '22023', message = 'WORKSPACE_MODULE_INVALID'; end if;
  if v_slot_key !~ '^[a-z][a-z0-9-]{0,47}$' then raise exception using errcode = '22023', message = 'WORKSPACE_SLOT_INVALID'; end if;

  v_operator := lws_internal.require_active_workspace_operator_v1();
  if v_module_key not in ('messages', 'calendar') then
    raise exception using errcode = '42501', message = 'WORKSPACE_MODULE_NOT_ENABLED';
  end if;
  if not lws_internal.operator_workspace_module_authorized_v1(v_operator.role, v_module_key) then
    raise exception using errcode = '42501', message = 'WORKSPACE_MODULE_NOT_AUTHORIZED';
  end if;

  select * into v_workspace
  from public.operator_workspace_sessions
  where workspace_id = p_workspace_id
    and epoch = p_epoch
    and operator_id = v_operator.operator_id
  for update;
  if not found then raise exception using errcode = '42501', message = 'WORKSPACE_NOT_AVAILABLE'; end if;
  if v_workspace.status <> 'ACTIVE' or v_workspace.lease_expires_at <= v_now then
    raise exception using errcode = '42501', message = 'WORKSPACE_NOT_ACTIVE';
  end if;

  select * into v_claim
  from public.operator_workspace_window_claims
  where workspace_id = v_workspace.workspace_id
    and module_key = v_module_key
    and slot_key = v_slot_key;

  if found then
    return jsonb_build_object(
      'joined', v_claim.window_id = p_window_id,
      'workspace_id', v_workspace.workspace_id,
      'epoch', v_workspace.epoch,
      'window_id', v_claim.window_id,
      'module_key', v_claim.module_key,
      'slot_key', v_claim.slot_key,
      'lease_expires_at', v_workspace.lease_expires_at
    );
  end if;

  insert into public.operator_workspace_window_claims(workspace_id, window_id, module_key, slot_key, claimed_at)
  values(v_workspace.workspace_id, p_window_id, v_module_key, v_slot_key, v_now)
  returning * into v_claim;

  return jsonb_build_object(
    'joined', true,
    'workspace_id', v_workspace.workspace_id,
    'epoch', v_workspace.epoch,
    'window_id', v_claim.window_id,
    'module_key', v_claim.module_key,
    'slot_key', v_claim.slot_key,
    'lease_expires_at', v_workspace.lease_expires_at
  );
end;
$$;

create or replace function public.get_operator_workspace_status_v1(
  p_workspace_id uuid,
  p_epoch bigint,
  p_window_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_workspace public.operator_workspace_sessions%rowtype;
  v_claim public.operator_workspace_window_claims%rowtype;
  v_now timestamptz := clock_timestamp();
  v_module_authorized boolean := false;
  v_valid boolean;
begin
  v_operator := lws_internal.require_active_workspace_operator_v1();
  select * into v_workspace
  from public.operator_workspace_sessions
  where workspace_id = p_workspace_id
    and epoch = p_epoch
    and operator_id = v_operator.operator_id;
  if not found then raise exception using errcode = '42501', message = 'WORKSPACE_NOT_AVAILABLE'; end if;

  select * into v_claim
  from public.operator_workspace_window_claims
  where workspace_id = v_workspace.workspace_id
    and window_id = p_window_id;

  if found then
    v_module_authorized := lws_internal.operator_workspace_module_authorized_v1(v_operator.role, v_claim.module_key);
  end if;

  v_valid := found
    and v_module_authorized
    and v_workspace.status = 'ACTIVE'
    and v_workspace.lease_expires_at > v_now;

  return jsonb_build_object(
    'valid', v_valid,
    'workspace_id', v_workspace.workspace_id,
    'epoch', v_workspace.epoch,
    'status', case
      when found and not v_module_authorized then 'MODULE_NOT_AUTHORIZED'
      when v_workspace.status = 'ACTIVE' and v_workspace.lease_expires_at <= v_now then 'EXPIRED'
      else v_workspace.status
    end,
    'module_key', case when found then v_claim.module_key else null end,
    'slot_key', case when found then v_claim.slot_key else null end,
    'lease_expires_at', v_workspace.lease_expires_at,
    'server_time', v_now
  );
end;
$$;
