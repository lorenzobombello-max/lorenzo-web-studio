-- Candidate 2 production activation checkpoint.
-- Hosted-Supabase compatibility: temporary membership + schema CREATE for ownership transfer;
-- CREATE and membership are revoked before commit, while private-owner USAGE is retained.

begin;


do $lws_p0_2_checkpoint_private_roles$
begin
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'p0_2_telemetry_private_owner') then
    execute 'create role p0_2_telemetry_private_owner nologin noinherit';
  end if;
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'p0_2_telemetry_checkpoint_controller') then
    execute 'create role p0_2_telemetry_checkpoint_controller nologin noinherit';
  end if;
end;
$lws_p0_2_checkpoint_private_roles$;

grant p0_2_telemetry_private_owner to postgres;
grant usage, create on schema p0_2_aggregate_telemetry to p0_2_telemetry_private_owner;

create table p0_2_aggregate_telemetry.activation_checkpoint (
  controller_state text not null,
  window_start timestamptz,
  window_end timestamptz,
  checkpoint_version bigint not null,
  updated_at timestamptz not null,
  owner_epoch bigint not null,
  owner_token_digest text,
  lease_expires_at timestamptz,
  last_heartbeat_attempt_bucket integer,
  constraint p0_2_checkpoint_state check (
    controller_state in ('STARTING', 'ACTIVE', 'SEALING', 'SEALED', 'INVALID')
  ),
  constraint p0_2_checkpoint_positive_version check (checkpoint_version >= 1),
  constraint p0_2_checkpoint_positive_owner_epoch check (owner_epoch >= 1),
  constraint p0_2_checkpoint_owner_binding check (
    (owner_token_digest is null and lease_expires_at is null)
    or (owner_token_digest ~ '^[a-f0-9]{64}$' and lease_expires_at is not null)
  ),
  constraint p0_2_checkpoint_heartbeat_bucket check (
    last_heartbeat_attempt_bucket is null
    or last_heartbeat_attempt_bucket between 0 and 1439
  ),
  constraint p0_2_checkpoint_binding check (
    (controller_state = 'STARTING' and window_start is null and window_end is null)
    or (controller_state in ('ACTIVE', 'SEALING', 'SEALED')
      and window_start is not null
      and window_end = window_start + interval '24 hours')
    or (controller_state = 'INVALID'
      and ((window_start is null and window_end is null)
        or (window_start is not null and window_end = window_start + interval '24 hours')))
  )
);

create unique index p0_2_checkpoint_singleton
  on p0_2_aggregate_telemetry.activation_checkpoint ((true));

create function p0_2_aggregate_telemetry.checkpoint_json_v1(
  p_controller_state text,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_checkpoint_version bigint,
  p_updated_at timestamptz,
  p_owner_epoch bigint,
  p_owner_token_digest text,
  p_lease_expires_at timestamptz,
  p_last_heartbeat_attempt_bucket integer
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $function$
  select jsonb_build_object(
    'controllerState', p_controller_state,
    'windowStart', case when p_window_start is null then null
      else to_char(p_window_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') end,
    'windowEnd', case when p_window_end is null then null
      else to_char(p_window_end at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') end,
    'checkpointVersion', p_checkpoint_version,
    'updatedAt', to_char(p_updated_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'ownerEpoch', p_owner_epoch,
    'ownerTokenDigest', p_owner_token_digest,
    'leaseExpiresAt', case when p_lease_expires_at is null then null
      else to_char(p_lease_expires_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') end,
    'lastHeartbeatAttemptBucket', p_last_heartbeat_attempt_bucket
  );
$function$;

create function p0_2_aggregate_telemetry.create_p0_2_telemetry_activation_checkpoint_v1(
  p_owner_token_digest text,
  p_lease_duration_seconds integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, p0_2_aggregate_telemetry
as $function$
declare
  v_checkpoint p0_2_aggregate_telemetry.activation_checkpoint%rowtype;
begin
  if p_owner_token_digest is null
    or p_owner_token_digest !~ '^[a-f0-9]{64}$'
    or p_lease_duration_seconds is null
    or p_lease_duration_seconds < 30
    or p_lease_duration_seconds > 3600 then
    return null;
  end if;
  begin
    insert into p0_2_aggregate_telemetry.activation_checkpoint (
      controller_state,
      window_start,
      window_end,
      checkpoint_version,
      updated_at,
      owner_epoch,
      owner_token_digest,
      lease_expires_at,
      last_heartbeat_attempt_bucket
    ) values (
      'STARTING',
      null,
      null,
      1,
      statement_timestamp(),
      1,
      p_owner_token_digest,
      statement_timestamp() + make_interval(secs => p_lease_duration_seconds),
      null
    ) returning * into v_checkpoint;
  exception when unique_violation then
    return null;
  end;

  return p0_2_aggregate_telemetry.checkpoint_json_v1(
    v_checkpoint.controller_state,
    v_checkpoint.window_start,
    v_checkpoint.window_end,
    v_checkpoint.checkpoint_version,
    v_checkpoint.updated_at,
    v_checkpoint.owner_epoch,
    v_checkpoint.owner_token_digest,
    v_checkpoint.lease_expires_at,
    v_checkpoint.last_heartbeat_attempt_bucket
  );
end;
$function$;

create function p0_2_aggregate_telemetry.read_p0_2_telemetry_activation_checkpoint_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, p0_2_aggregate_telemetry
as $function$
  select p0_2_aggregate_telemetry.checkpoint_json_v1(
    controller_state,
    window_start,
    window_end,
    checkpoint_version,
    updated_at,
    owner_epoch,
    owner_token_digest,
    lease_expires_at,
    last_heartbeat_attempt_bucket
  )
  from p0_2_aggregate_telemetry.activation_checkpoint;
$function$;

create function p0_2_aggregate_telemetry.transition_p0_2_telemetry_activation_checkpoint_v1(
  p_expected_state text,
  p_next_state text,
  p_expected_checkpoint_version bigint,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_expected_owner_epoch bigint,
  p_owner_token_digest text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, p0_2_aggregate_telemetry
as $function$
declare
  v_checkpoint p0_2_aggregate_telemetry.activation_checkpoint%rowtype;
begin
  if p_expected_owner_epoch is null
    or p_owner_token_digest is null
    or p_owner_token_digest !~ '^[a-f0-9]{64}$' then
    return null;
  end if;
  if not (
    (p_expected_state = 'STARTING' and p_next_state = 'ACTIVE')
    or (p_expected_state = 'ACTIVE' and p_next_state = 'ACTIVE')
    or (p_expected_state = 'ACTIVE' and p_next_state = 'SEALING')
    or (p_expected_state = 'SEALING' and p_next_state = 'SEALED')
  ) then
    return null;
  end if;

  if p_expected_state = 'STARTING' then
    if p_window_start is null or p_window_end is null then
      return null;
    end if;
    if p_window_end <> p_window_start + interval '24 hours' then
      return null;
    end if;
  elsif p_window_start is not null or p_window_end is not null then
    return null;
  end if;

  update p0_2_aggregate_telemetry.activation_checkpoint
     set controller_state = p_next_state,
         window_start = case when p_expected_state = 'STARTING' then p_window_start else window_start end,
         window_end = case when p_expected_state = 'STARTING' then p_window_end else window_end end,
         checkpoint_version = checkpoint_version + 1,
         updated_at = statement_timestamp()
   where controller_state = p_expected_state
     and checkpoint_version = p_expected_checkpoint_version
     and owner_epoch = p_expected_owner_epoch
     and owner_token_digest = p_owner_token_digest
     and (
       p_expected_state = 'STARTING'
       or (p_expected_state = 'ACTIVE' and p_next_state = 'ACTIVE'
         and (mod(p_expected_checkpoint_version, 2) = 1
           or lease_expires_at >= statement_timestamp()))
       or (p_expected_state = 'ACTIVE' and p_next_state = 'SEALING' and mod(p_expected_checkpoint_version, 2) = 1)
       or (p_expected_state = 'SEALING' and p_next_state = 'SEALED' and mod(p_expected_checkpoint_version, 2) = 0)
     )
  returning * into v_checkpoint;

  if not found then return null; end if;
  return p0_2_aggregate_telemetry.checkpoint_json_v1(
    v_checkpoint.controller_state,
    v_checkpoint.window_start,
    v_checkpoint.window_end,
    v_checkpoint.checkpoint_version,
    v_checkpoint.updated_at,
    v_checkpoint.owner_epoch,
    v_checkpoint.owner_token_digest,
    v_checkpoint.lease_expires_at,
    v_checkpoint.last_heartbeat_attempt_bucket
  );
end;
$function$;

create function p0_2_aggregate_telemetry.invalidate_p0_2_telemetry_activation_checkpoint_v1(
  p_expected_state text,
  p_expected_checkpoint_version bigint,
  p_expected_owner_epoch bigint,
  p_owner_token_digest text,
  p_recovery boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, p0_2_aggregate_telemetry
as $function$
declare
  v_checkpoint p0_2_aggregate_telemetry.activation_checkpoint%rowtype;
begin
  if p_expected_state not in ('STARTING', 'ACTIVE', 'SEALING') then
    return null;
  end if;

  update p0_2_aggregate_telemetry.activation_checkpoint
     set controller_state = 'INVALID',
         checkpoint_version = checkpoint_version + 1,
         updated_at = statement_timestamp(),
         owner_token_digest = null,
         lease_expires_at = null
   where controller_state = p_expected_state
     and checkpoint_version = p_expected_checkpoint_version
     and (
       (p_recovery is false
         and owner_epoch = p_expected_owner_epoch
         and owner_token_digest = p_owner_token_digest)
       or (p_recovery is true
         and p_expected_owner_epoch is null
         and p_owner_token_digest is null
         and lease_expires_at < statement_timestamp()
         and (p_expected_state in ('STARTING', 'SEALING')
           or (p_expected_state = 'ACTIVE'
             and mod(p_expected_checkpoint_version, 2) = 1)))
     )
  returning * into v_checkpoint;

  if not found then return null; end if;
  return p0_2_aggregate_telemetry.checkpoint_json_v1(
    v_checkpoint.controller_state,
    v_checkpoint.window_start,
    v_checkpoint.window_end,
    v_checkpoint.checkpoint_version,
    v_checkpoint.updated_at,
    v_checkpoint.owner_epoch,
    v_checkpoint.owner_token_digest,
    v_checkpoint.lease_expires_at,
    v_checkpoint.last_heartbeat_attempt_bucket
  );
end;
$function$;

create function p0_2_aggregate_telemetry.acquire_p0_2_telemetry_runtime_ownership_v1(
  p_expected_state text,
  p_expected_checkpoint_version bigint,
  p_expected_owner_epoch bigint,
  p_owner_token_digest text,
  p_lease_duration_seconds integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, p0_2_aggregate_telemetry
as $function$
declare
  v_checkpoint p0_2_aggregate_telemetry.activation_checkpoint%rowtype;
begin
  if p_expected_state is distinct from 'ACTIVE'
    or mod(p_expected_checkpoint_version, 2) <> 0
    or p_expected_owner_epoch is null
    or p_owner_token_digest is null
    or p_owner_token_digest !~ '^[a-f0-9]{64}$'
    or p_lease_duration_seconds is null
    or p_lease_duration_seconds < 30
    or p_lease_duration_seconds > 3600 then
    return null;
  end if;

  update p0_2_aggregate_telemetry.activation_checkpoint
     set owner_epoch = owner_epoch + 1,
         owner_token_digest = p_owner_token_digest,
         lease_expires_at = statement_timestamp() + make_interval(secs => p_lease_duration_seconds),
         updated_at = statement_timestamp()
   where controller_state = p_expected_state
     and checkpoint_version = p_expected_checkpoint_version
     and owner_epoch = p_expected_owner_epoch
     and (owner_token_digest is null or lease_expires_at < statement_timestamp())
  returning * into v_checkpoint;

  if not found then return null; end if;
  return p0_2_aggregate_telemetry.checkpoint_json_v1(
    v_checkpoint.controller_state, v_checkpoint.window_start,
    v_checkpoint.window_end, v_checkpoint.checkpoint_version,
    v_checkpoint.updated_at, v_checkpoint.owner_epoch,
    v_checkpoint.owner_token_digest, v_checkpoint.lease_expires_at,
    v_checkpoint.last_heartbeat_attempt_bucket
  );
end;
$function$;

create function p0_2_aggregate_telemetry.renew_p0_2_telemetry_runtime_ownership_v1(
  p_expected_state text,
  p_expected_checkpoint_version bigint,
  p_expected_owner_epoch bigint,
  p_owner_token_digest text,
  p_lease_duration_seconds integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, p0_2_aggregate_telemetry
as $function$
declare
  v_checkpoint p0_2_aggregate_telemetry.activation_checkpoint%rowtype;
begin
  if p_expected_state is distinct from 'ACTIVE'
    or mod(p_expected_checkpoint_version, 2) <> 0
    or p_expected_owner_epoch is null
    or p_owner_token_digest is null
    or p_owner_token_digest !~ '^[a-f0-9]{64}$'
    or p_lease_duration_seconds is null
    or p_lease_duration_seconds < 30
    or p_lease_duration_seconds > 3600 then
    return null;
  end if;
  update p0_2_aggregate_telemetry.activation_checkpoint
     set lease_expires_at = statement_timestamp() + make_interval(secs => p_lease_duration_seconds),
         updated_at = statement_timestamp()
   where controller_state = p_expected_state
     and checkpoint_version = p_expected_checkpoint_version
     and owner_epoch = p_expected_owner_epoch
     and owner_token_digest = p_owner_token_digest
     and lease_expires_at >= statement_timestamp()
  returning * into v_checkpoint;
  if not found then return null; end if;
  return p0_2_aggregate_telemetry.checkpoint_json_v1(
    v_checkpoint.controller_state, v_checkpoint.window_start,
    v_checkpoint.window_end, v_checkpoint.checkpoint_version,
    v_checkpoint.updated_at, v_checkpoint.owner_epoch,
    v_checkpoint.owner_token_digest, v_checkpoint.lease_expires_at,
    v_checkpoint.last_heartbeat_attempt_bucket
  );
end;
$function$;

create function p0_2_aggregate_telemetry.release_p0_2_telemetry_runtime_ownership_v1(
  p_expected_state text,
  p_expected_checkpoint_version bigint,
  p_expected_owner_epoch bigint,
  p_owner_token_digest text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, p0_2_aggregate_telemetry
as $function$
declare
  v_checkpoint p0_2_aggregate_telemetry.activation_checkpoint%rowtype;
begin
  if p_expected_state is distinct from 'ACTIVE'
    or mod(p_expected_checkpoint_version, 2) <> 0
    or p_expected_owner_epoch is null
    or p_owner_token_digest is null
    or p_owner_token_digest !~ '^[a-f0-9]{64}$' then
    return null;
  end if;
  update p0_2_aggregate_telemetry.activation_checkpoint
     set owner_token_digest = null,
         lease_expires_at = null,
         updated_at = statement_timestamp()
   where controller_state = p_expected_state
     and checkpoint_version = p_expected_checkpoint_version
     and owner_epoch = p_expected_owner_epoch
     and owner_token_digest = p_owner_token_digest
  returning * into v_checkpoint;
  if not found then return null; end if;
  return p0_2_aggregate_telemetry.checkpoint_json_v1(
    v_checkpoint.controller_state, v_checkpoint.window_start,
    v_checkpoint.window_end, v_checkpoint.checkpoint_version,
    v_checkpoint.updated_at, v_checkpoint.owner_epoch,
    v_checkpoint.owner_token_digest, v_checkpoint.lease_expires_at,
    v_checkpoint.last_heartbeat_attempt_bucket
  );
end;
$function$;

create function p0_2_aggregate_telemetry.claim_p0_2_telemetry_heartbeat_bucket_v1(
  p_expected_state text,
  p_expected_checkpoint_version bigint,
  p_expected_owner_epoch bigint,
  p_owner_token_digest text,
  p_minute_bucket integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, p0_2_aggregate_telemetry
as $function$
declare
  v_checkpoint p0_2_aggregate_telemetry.activation_checkpoint%rowtype;
begin
  if p_expected_state is distinct from 'ACTIVE'
    or mod(p_expected_checkpoint_version, 2) <> 0
    or p_expected_owner_epoch is null
    or p_owner_token_digest is null
    or p_owner_token_digest !~ '^[a-f0-9]{64}$'
    or p_minute_bucket is null
    or p_minute_bucket < 0
    or p_minute_bucket > 1439 then
    return null;
  end if;
  update p0_2_aggregate_telemetry.activation_checkpoint
     set checkpoint_version = checkpoint_version + 1,
         last_heartbeat_attempt_bucket = p_minute_bucket,
         updated_at = statement_timestamp()
   where controller_state = p_expected_state
     and checkpoint_version = p_expected_checkpoint_version
     and owner_epoch = p_expected_owner_epoch
     and owner_token_digest = p_owner_token_digest
     and lease_expires_at >= statement_timestamp()
     and (last_heartbeat_attempt_bucket is null
       or last_heartbeat_attempt_bucket < p_minute_bucket)
  returning * into v_checkpoint;
  if not found then return null; end if;
  return p0_2_aggregate_telemetry.checkpoint_json_v1(
    v_checkpoint.controller_state, v_checkpoint.window_start,
    v_checkpoint.window_end, v_checkpoint.checkpoint_version,
    v_checkpoint.updated_at, v_checkpoint.owner_epoch,
    v_checkpoint.owner_token_digest, v_checkpoint.lease_expires_at,
    v_checkpoint.last_heartbeat_attempt_bucket
  );
end;
$function$;

alter table p0_2_aggregate_telemetry.activation_checkpoint
  owner to p0_2_telemetry_private_owner;
alter function p0_2_aggregate_telemetry.checkpoint_json_v1(text, timestamptz, timestamptz, bigint, timestamptz, bigint, text, timestamptz, integer)
  owner to p0_2_telemetry_private_owner;
alter function p0_2_aggregate_telemetry.create_p0_2_telemetry_activation_checkpoint_v1(text, integer)
  owner to p0_2_telemetry_private_owner;
alter function p0_2_aggregate_telemetry.read_p0_2_telemetry_activation_checkpoint_v1()
  owner to p0_2_telemetry_private_owner;
alter function p0_2_aggregate_telemetry.transition_p0_2_telemetry_activation_checkpoint_v1(text, text, bigint, timestamptz, timestamptz, bigint, text)
  owner to p0_2_telemetry_private_owner;
alter function p0_2_aggregate_telemetry.invalidate_p0_2_telemetry_activation_checkpoint_v1(text, bigint, bigint, text, boolean)
  owner to p0_2_telemetry_private_owner;
alter function p0_2_aggregate_telemetry.acquire_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text, integer)
  owner to p0_2_telemetry_private_owner;
alter function p0_2_aggregate_telemetry.renew_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text, integer)
  owner to p0_2_telemetry_private_owner;
alter function p0_2_aggregate_telemetry.release_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text)
  owner to p0_2_telemetry_private_owner;
alter function p0_2_aggregate_telemetry.claim_p0_2_telemetry_heartbeat_bucket_v1(text, bigint, bigint, text, integer)
  owner to p0_2_telemetry_private_owner;

revoke all on schema p0_2_aggregate_telemetry
  from public, anon, authenticated;
revoke all on table p0_2_aggregate_telemetry.activation_checkpoint
  from public, anon, authenticated;
revoke all on function p0_2_aggregate_telemetry.checkpoint_json_v1(text, timestamptz, timestamptz, bigint, timestamptz, bigint, text, timestamptz, integer)
  from public, anon, authenticated;
revoke all on function p0_2_aggregate_telemetry.create_p0_2_telemetry_activation_checkpoint_v1(text, integer)
  from public, anon, authenticated;
revoke all on function p0_2_aggregate_telemetry.read_p0_2_telemetry_activation_checkpoint_v1()
  from public, anon, authenticated;
revoke all on function p0_2_aggregate_telemetry.transition_p0_2_telemetry_activation_checkpoint_v1(text, text, bigint, timestamptz, timestamptz, bigint, text)
  from public, anon, authenticated;
revoke all on function p0_2_aggregate_telemetry.invalidate_p0_2_telemetry_activation_checkpoint_v1(text, bigint, bigint, text, boolean)
  from public, anon, authenticated;
revoke all on function p0_2_aggregate_telemetry.acquire_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text, integer)
  from public, anon, authenticated;
revoke all on function p0_2_aggregate_telemetry.renew_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text, integer)
  from public, anon, authenticated;
revoke all on function p0_2_aggregate_telemetry.release_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text)
  from public, anon, authenticated;
revoke all on function p0_2_aggregate_telemetry.claim_p0_2_telemetry_heartbeat_bucket_v1(text, bigint, bigint, text, integer)
  from public, anon, authenticated;

grant usage on schema p0_2_aggregate_telemetry
  to p0_2_telemetry_checkpoint_controller;
grant execute on function p0_2_aggregate_telemetry.create_p0_2_telemetry_activation_checkpoint_v1(text, integer)
  to p0_2_telemetry_checkpoint_controller;
grant execute on function p0_2_aggregate_telemetry.read_p0_2_telemetry_activation_checkpoint_v1()
  to p0_2_telemetry_checkpoint_controller;
grant execute on function p0_2_aggregate_telemetry.transition_p0_2_telemetry_activation_checkpoint_v1(text, text, bigint, timestamptz, timestamptz, bigint, text)
  to p0_2_telemetry_checkpoint_controller;
grant execute on function p0_2_aggregate_telemetry.invalidate_p0_2_telemetry_activation_checkpoint_v1(text, bigint, bigint, text, boolean)
  to p0_2_telemetry_checkpoint_controller;
grant execute on function p0_2_aggregate_telemetry.acquire_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text, integer)
  to p0_2_telemetry_checkpoint_controller;
grant execute on function p0_2_aggregate_telemetry.renew_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text, integer)
  to p0_2_telemetry_checkpoint_controller;
grant execute on function p0_2_aggregate_telemetry.release_p0_2_telemetry_runtime_ownership_v1(text, bigint, bigint, text)
  to p0_2_telemetry_checkpoint_controller;
grant execute on function p0_2_aggregate_telemetry.claim_p0_2_telemetry_heartbeat_bucket_v1(text, bigint, bigint, text, integer)
  to p0_2_telemetry_checkpoint_controller;

revoke create on schema p0_2_aggregate_telemetry from p0_2_telemetry_private_owner;
revoke p0_2_telemetry_private_owner from postgres;

commit;