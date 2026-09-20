create or replace function public.resume_operator_workspace_v1(
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
  v_window_claims jsonb;
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

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'window_id', claim.window_id,
        'module_key', claim.module_key,
        'slot_key', claim.slot_key
      ) order by claim.module_key, claim.slot_key
    ),
    '[]'::jsonb
  ) into v_window_claims
  from public.operator_workspace_window_claims as claim
  where claim.workspace_id = v_workspace.workspace_id
    and lws_internal.operator_workspace_module_authorized_v1(v_operator.role, claim.module_key);

  return jsonb_build_object(
    'resumed', true,
    'workspace_id', v_workspace.workspace_id,
    'epoch', v_workspace.epoch,
    'master_window_id', v_workspace.master_window_id,
    'renewal_token', v_renewal_token,
    'lease_expires_at', v_workspace.lease_expires_at,
    'window_claims', v_window_claims
  );
end;
$$;

create function public.recover_operator_workspace_v1(
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
  v_previous public.operator_workspace_sessions%rowtype;
  v_existing public.operator_workspace_sessions%rowtype;
  v_workspace public.operator_workspace_sessions%rowtype;
  v_renewal_token uuid := gen_random_uuid();
  v_now timestamptz := clock_timestamp();
begin
  if p_workspace_id is null or p_epoch is null or p_master_window_id is null or p_renewal_token is null then
    raise exception using errcode = '22023', message = 'WORKSPACE_RECOVERY_IDENTITY_REQUIRED';
  end if;

  v_operator := lws_internal.require_active_workspace_operator_v1();
  perform 1 from public.commercial_operators
  where operator_id = v_operator.operator_id
  for update;

  select * into v_previous
  from public.operator_workspace_sessions
  where workspace_id = p_workspace_id
    and epoch = p_epoch
    and operator_id = v_operator.operator_id
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'WORKSPACE_NOT_AVAILABLE';
  end if;
  if v_previous.status = 'REVOKED' then
    raise exception using errcode = '42501', message = 'WORKSPACE_REVOKED';
  end if;
  if v_previous.master_window_id <> p_master_window_id
    or v_previous.renewal_token_hash <> digest(p_renewal_token::text, 'sha256') then
    raise exception using errcode = '42501', message = 'MASTER_RECOVERY_NOT_AUTHORIZED';
  end if;
  if v_previous.status = 'ACTIVE' and v_previous.lease_expires_at > v_now then
    raise exception using errcode = '42501', message = 'WORKSPACE_STILL_ACTIVE';
  end if;
  if v_previous.status not in ('ACTIVE', 'EXPIRED') then
    raise exception using errcode = '42501', message = 'WORKSPACE_RECOVERY_NOT_ALLOWED';
  end if;

  select * into v_existing
  from public.operator_workspace_sessions
  where operator_id = v_operator.operator_id
    and status = 'ACTIVE'
    and lease_expires_at > v_now
    and workspace_id <> v_previous.workspace_id
  for update;

  if found then
    return jsonb_build_object(
      'recovered', false,
      'reason', 'SERVER_MASTER_EXISTS',
      'workspace_id', v_existing.workspace_id,
      'epoch', v_existing.epoch,
      'lease_expires_at', v_existing.lease_expires_at
    );
  end if;

  update public.operator_workspace_sessions
  set status = 'EXPIRED', updated_at = v_now
  where workspace_id = v_previous.workspace_id
    and status = 'ACTIVE';

  insert into public.operator_workspace_sessions(
    operator_id, master_window_id, renewal_token_hash, lease_expires_at, created_at, updated_at
  ) values (
    v_operator.operator_id, p_master_window_id, digest(v_renewal_token::text, 'sha256'),
    v_now + interval '13 seconds', v_now, v_now
  ) returning * into v_workspace;

  return jsonb_build_object(
    'recovered', true,
    'workspace_id', v_workspace.workspace_id,
    'epoch', v_workspace.epoch,
    'master_window_id', v_workspace.master_window_id,
    'renewal_token', v_renewal_token,
    'lease_expires_at', v_workspace.lease_expires_at,
    'window_claims', '[]'::jsonb
  );
end;
$$;

revoke all on function public.resume_operator_workspace_v1(uuid, bigint, uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.recover_operator_workspace_v1(uuid, bigint, uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.resume_operator_workspace_v1(uuid, bigint, uuid, uuid) to authenticated;
grant execute on function public.recover_operator_workspace_v1(uuid, bigint, uuid, uuid) to authenticated;

comment on function public.resume_operator_workspace_v1(uuid, bigint, uuid, uuid) is
  'Transfers a still-active workspace master capability and returns only currently authorized server-owned child claims.';
comment on function public.recover_operator_workspace_v1(uuid, bigint, uuid, uuid) is
  'Replaces only the authenticated master its capability-bound naturally expired workspace; revoked, foreign, stale, and concurrently replaced workspaces fail closed.';
