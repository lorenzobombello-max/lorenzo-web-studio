create table public.operator_workspace_sessions (
  workspace_id uuid primary key default gen_random_uuid(),
  operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  epoch bigint generated always as identity unique,
  master_window_id uuid not null,
  renewal_token_hash bytea not null,
  lease_expires_at timestamptz not null,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'EXPIRED', 'REVOKED')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  constraint operator_workspace_session_state_shape check (
    (status = 'ACTIVE' and revoked_at is null)
    or (status = 'EXPIRED' and revoked_at is null)
    or (status = 'REVOKED' and revoked_at is not null)
  )
);

create unique index operator_workspace_one_active_epoch_idx
  on public.operator_workspace_sessions(operator_id)
  where status = 'ACTIVE';
create index operator_workspace_lease_expiry_idx
  on public.operator_workspace_sessions(lease_expires_at)
  where status = 'ACTIVE';

create table public.operator_workspace_window_claims (
  workspace_id uuid not null references public.operator_workspace_sessions(workspace_id) on delete cascade,
  window_id uuid not null,
  module_key text not null check (module_key = 'messages'),
  claimed_at timestamptz not null default clock_timestamp(),
  primary key(workspace_id, module_key),
  unique(workspace_id, window_id)
);

alter table public.operator_workspace_sessions enable row level security;
alter table public.operator_workspace_sessions force row level security;
alter table public.operator_workspace_window_claims enable row level security;
alter table public.operator_workspace_window_claims force row level security;

revoke all on table public.operator_workspace_sessions from public, anon, authenticated, service_role;
revoke all on table public.operator_workspace_window_claims from public, anon, authenticated, service_role;

create function lws_internal.require_active_workspace_operator_v1()
returns public.commercial_operators
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

  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;

  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_NOT_ACTIVE'; end if;
  return v_operator;
end;
$$;

create function public.acquire_operator_workspace_v1(p_master_window_id uuid)
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
    v_now + interval '15 seconds', v_now, v_now
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

create function public.renew_operator_workspace_lease_v1(
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
  set lease_expires_at = v_now + interval '15 seconds', updated_at = v_now
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

create function public.join_operator_workspace_v1(
  p_workspace_id uuid,
  p_epoch bigint,
  p_window_id uuid,
  p_module_key text
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
  v_now timestamptz := clock_timestamp();
begin
  if p_window_id is null then raise exception using errcode = '22023', message = 'WINDOW_ID_REQUIRED'; end if;
  if v_module_key <> 'messages' then raise exception using errcode = '22023', message = 'WORKSPACE_MODULE_NOT_SUPPORTED'; end if;
  v_operator := lws_internal.require_active_workspace_operator_v1();
  if v_operator.role <> 'owner' then
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
    and module_key = v_module_key;

  if found then
    return jsonb_build_object(
      'joined', v_claim.window_id = p_window_id,
      'workspace_id', v_workspace.workspace_id,
      'epoch', v_workspace.epoch,
      'window_id', v_claim.window_id,
      'module_key', v_claim.module_key,
      'lease_expires_at', v_workspace.lease_expires_at
    );
  end if;

  insert into public.operator_workspace_window_claims(workspace_id, window_id, module_key, claimed_at)
  values(v_workspace.workspace_id, p_window_id, v_module_key, v_now)
  returning * into v_claim;

  return jsonb_build_object(
    'joined', true,
    'workspace_id', v_workspace.workspace_id,
    'epoch', v_workspace.epoch,
    'window_id', v_claim.window_id,
    'module_key', v_claim.module_key,
    'lease_expires_at', v_workspace.lease_expires_at
  );
end;
$$;

create function public.get_operator_workspace_status_v1(
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

  v_valid := found and v_workspace.status = 'ACTIVE' and v_workspace.lease_expires_at > v_now;
  return jsonb_build_object(
    'valid', v_valid,
    'workspace_id', v_workspace.workspace_id,
    'epoch', v_workspace.epoch,
    'status', case when v_workspace.status = 'ACTIVE' and v_workspace.lease_expires_at <= v_now then 'EXPIRED' else v_workspace.status end,
    'lease_expires_at', v_workspace.lease_expires_at,
    'server_time', v_now
  );
end;
$$;

create function public.revoke_operator_workspace_v1(
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
  if v_workspace.master_window_id <> p_master_window_id
    or p_renewal_token is null
    or v_workspace.renewal_token_hash <> digest(p_renewal_token::text, 'sha256') then
    raise exception using errcode = '42501', message = 'MASTER_RENEWAL_NOT_AUTHORIZED';
  end if;

  if v_workspace.status = 'ACTIVE' then
    update public.operator_workspace_sessions
    set status = 'REVOKED', revoked_at = v_now, updated_at = v_now
    where workspace_id = v_workspace.workspace_id;
  end if;

  return jsonb_build_object(
    'revoked', true,
    'workspace_id', v_workspace.workspace_id,
    'epoch', v_workspace.epoch,
    'revoked_at', v_now
  );
end;
$$;

revoke all on function lws_internal.require_active_workspace_operator_v1()
from public, anon, authenticated, service_role;
revoke all on function public.acquire_operator_workspace_v1(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.renew_operator_workspace_lease_v1(uuid, bigint, uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.join_operator_workspace_v1(uuid, bigint, uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.get_operator_workspace_status_v1(uuid, bigint, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.revoke_operator_workspace_v1(uuid, bigint, uuid, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.acquire_operator_workspace_v1(uuid) to authenticated;
grant execute on function public.renew_operator_workspace_lease_v1(uuid, bigint, uuid, uuid) to authenticated;
grant execute on function public.join_operator_workspace_v1(uuid, bigint, uuid, text) to authenticated;
grant execute on function public.get_operator_workspace_status_v1(uuid, bigint, uuid) to authenticated;
grant execute on function public.revoke_operator_workspace_v1(uuid, bigint, uuid, uuid) to authenticated;

comment on table public.operator_workspace_sessions is
  'Ephemeral Operator-only managed-window workspace epochs with capability-bound master liveness.';
comment on table public.operator_workspace_window_claims is
  'One authoritative managed child slot per Operator workspace module.';
comment on function public.acquire_operator_workspace_v1(uuid) is
  'Creates one ACTIVE Operator workspace epoch or reports the existing epoch without exposing its renewal capability.';
comment on function public.renew_operator_workspace_lease_v1(uuid, bigint, uuid, uuid) is
  'Renews master liveness only for the authenticated owner of the matching in-memory capability.';
comment on function public.join_operator_workspace_v1(uuid, bigint, uuid, text) is
  'Validates Operator/module authority and atomically claims the managed child slot.';
comment on function public.get_operator_workspace_status_v1(uuid, bigint, uuid) is
  'Returns server-authoritative lease status only to a joined child of the same Operator.';
comment on function public.revoke_operator_workspace_v1(uuid, bigint, uuid, uuid) is
  'Capability-bound explicit workspace shutdown for the authenticated master Operator.';