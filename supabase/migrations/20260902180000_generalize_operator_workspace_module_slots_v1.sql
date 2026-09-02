alter table public.operator_workspace_window_claims
  drop constraint operator_workspace_window_claims_module_key_check;

alter table public.operator_workspace_window_claims
  add column slot_key text not null default 'main'
  check (slot_key ~ '^[a-z][a-z0-9-]{0,47}$');

alter table public.operator_workspace_window_claims
  drop constraint operator_workspace_window_claims_pkey;

alter table public.operator_workspace_window_claims
  add primary key(workspace_id, module_key, slot_key);

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

  if v_module_key = 'messages' then
    if v_operator.role <> 'owner' then
      raise exception using errcode = '42501', message = 'WORKSPACE_MODULE_NOT_AUTHORIZED';
    end if;
  else
    raise exception using errcode = '42501', message = 'WORKSPACE_MODULE_NOT_ENABLED';
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

create or replace function public.join_operator_workspace_v1(
  p_workspace_id uuid,
  p_epoch bigint,
  p_window_id uuid,
  p_module_key text
)
returns jsonb
language sql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
  select public.join_operator_workspace_v1(
    p_workspace_id,
    p_epoch,
    p_window_id,
    p_module_key,
    'main'
  );
$$;

revoke all on function public.join_operator_workspace_v1(uuid,bigint,uuid,text,text) from public, anon;
grant execute on function public.join_operator_workspace_v1(uuid,bigint,uuid,text,text) to authenticated;
