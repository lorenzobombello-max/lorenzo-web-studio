create or replace function public.acquire_operator_workspace_v1(p_master_window_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_existing public.operator_workspace_sessions%rowtype;
  v_workspace public.operator_workspace_sessions%rowtype;
  v_renewal_token uuid := gen_random_uuid();
  v_now timestamptz := clock_timestamp();
begin
  if p_master_window_id is null then
    raise exception using errcode = '22023', message = 'MASTER_WINDOW_ID_REQUIRED';
  end if;
  v_operator := lws_internal.require_active_workspace_operator_v1();

  perform 1 from public.commercial_operators
  where operator_id = v_operator.operator_id
  for update;

  update public.operator_workspace_sessions
  set status = 'EXPIRED', updated_at = v_now
  where operator_id = v_operator.operator_id
    and status = 'ACTIVE'
    and lease_expires_at <= v_now;

  select * into v_existing
  from public.operator_workspace_sessions
  where operator_id = v_operator.operator_id
    and status = 'ACTIVE'
    and lease_expires_at > v_now;

  if found then
    return jsonb_build_object(
      'acquired', false,
      'workspace_id', v_existing.workspace_id,
      'epoch', v_existing.epoch,
      'master_window_id', v_existing.master_window_id,
      'lease_expires_at', v_existing.lease_expires_at
    );
  end if;

  insert into public.operator_workspace_sessions(
    operator_id, master_window_id, renewal_token_hash, lease_expires_at, created_at, updated_at
  ) values (
    v_operator.operator_id, p_master_window_id, digest(v_renewal_token::text, 'sha256'),
    v_now + interval '13 seconds', v_now, v_now
  ) returning * into v_workspace;

  return jsonb_build_object(
    'acquired', true,
    'workspace_id', v_workspace.workspace_id,
    'epoch', v_workspace.epoch,
    'master_window_id', v_workspace.master_window_id,
    'renewal_token', v_renewal_token,
    'lease_expires_at', v_workspace.lease_expires_at
  );
end;
$$;

create or replace function public.renew_operator_workspace_lease_v1(
  p_workspace_id uuid,
  p_epoch bigint,
  p_master_window_id uuid,
  p_renewal_token uuid
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
  v_now timestamptz := clock_timestamp();
begin
  v_operator := lws_internal.require_active_workspace_operator_v1();
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
  if v_workspace.master_window_id <> p_master_window_id
    or p_renewal_token is null
    or v_workspace.renewal_token_hash <> digest(p_renewal_token::text, 'sha256') then
    raise exception using errcode = '42501', message = 'MASTER_RENEWAL_NOT_AUTHORIZED';
  end if;

  update public.operator_workspace_sessions
  set lease_expires_at = v_now + interval '13 seconds', updated_at = v_now
  where workspace_id = v_workspace.workspace_id
  returning * into v_workspace;

  return jsonb_build_object(
    'valid', true,
    'workspace_id', v_workspace.workspace_id,
    'epoch', v_workspace.epoch,
    'lease_expires_at', v_workspace.lease_expires_at
  );
end;
$$;
