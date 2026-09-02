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
    v_module_authorized := v_claim.module_key = 'messages' and v_operator.role = 'owner';
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
