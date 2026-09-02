create function public.resume_operator_workspace_v1(
  p_workspace_id uuid,
  p_epoch bigint,
  p_previous_master_window_id uuid,
  p_new_master_window_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_workspace public.operator_workspace_sessions%rowtype;
  v_renewal_token uuid := gen_random_uuid();
  v_now timestamptz := clock_timestamp();
begin
  if p_workspace_id is null or p_epoch is null or p_previous_master_window_id is null or p_new_master_window_id is null then
    raise exception using errcode = '22023', message = 'WORKSPACE_RESUME_IDENTITY_REQUIRED';
  end if;
  if p_previous_master_window_id = p_new_master_window_id then
    raise exception using errcode = '22023', message = 'NEW_MASTER_WINDOW_ID_REQUIRED';
  end if;

  v_operator := lws_internal.require_active_workspace_operator_v1();
  perform 1 from public.commercial_operators
  where operator_id = v_operator.operator_id
  for update;

  select * into v_workspace
  from public.operator_workspace_sessions
  where workspace_id = p_workspace_id
    and epoch = p_epoch
    and operator_id = v_operator.operator_id
  for update;

  if not found
    or v_workspace.status <> 'ACTIVE'
    or v_workspace.lease_expires_at <= v_now
    or v_workspace.master_window_id <> p_previous_master_window_id then
    return jsonb_build_object('resumed', false);
  end if;

  update public.operator_workspace_sessions
  set master_window_id = p_new_master_window_id,
      renewal_token_hash = digest(v_renewal_token::text, 'sha256'),
      lease_expires_at = v_now + interval '13 seconds',
      updated_at = v_now
  where workspace_id = v_workspace.workspace_id
  returning * into v_workspace;

  return jsonb_build_object(
    'resumed', true,
    'workspace_id', v_workspace.workspace_id,
    'epoch', v_workspace.epoch,
    'master_window_id', v_workspace.master_window_id,
    'renewal_token', v_renewal_token,
    'lease_expires_at', v_workspace.lease_expires_at
  );
end;
$$;

revoke all on function public.resume_operator_workspace_v1(uuid, bigint, uuid, uuid) from public, anon, authenticated, service_role;
grant execute on function public.resume_operator_workspace_v1(uuid, bigint, uuid, uuid) to authenticated;