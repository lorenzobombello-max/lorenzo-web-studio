-- LOCAL_INERT_LIFECYCLE_CANDIDATE_NOT_PRODUCTION_ACTIVATABLE. DO NOT APPLY.
-- The unconditional guard keeps all role, function, ownership, and grant changes inert.

begin;


do $lws_p0_2_telemetry_private_roles$
begin
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'p0_2_telemetry_private_owner') then
    execute 'create role p0_2_telemetry_private_owner nologin noinherit';
  end if;
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'p0_2_telemetry_lifecycle_controller') then
    execute 'create role p0_2_telemetry_lifecycle_controller nologin noinherit';
  end if;
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'p0_2_telemetry_runtime_writer') then
    execute 'create role p0_2_telemetry_runtime_writer nologin noinherit';
  end if;
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'p0_2_telemetry_report_reader') then
    execute 'create role p0_2_telemetry_report_reader nologin noinherit';
  end if;
end;
$lws_p0_2_telemetry_private_roles$;

grant p0_2_telemetry_private_owner to postgres;
grant create on database postgres to p0_2_telemetry_private_owner;

alter schema p0_2_aggregate_telemetry owner to p0_2_telemetry_private_owner;
alter table p0_2_aggregate_telemetry.windows owner to p0_2_telemetry_private_owner;
alter function p0_2_aggregate_telemetry.reject_destructive_window_change()
  owner to p0_2_telemetry_private_owner;
alter function p0_2_aggregate_telemetry.increment_p0_2_aggregate_telemetry_counter_v1(timestamptz, text, integer, bigint, bigint, text)
  owner to p0_2_telemetry_private_owner;
alter function p0_2_aggregate_telemetry.cover_p0_2_aggregate_telemetry_minute_v1(timestamptz, integer, bigint, bigint, text)
  owner to p0_2_telemetry_private_owner;

create function p0_2_aggregate_telemetry.create_p0_2_aggregate_telemetry_window_v1(
  p_expected_checkpoint_version bigint,
  p_owner_epoch bigint,
  p_owner_token_digest text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, p0_2_aggregate_telemetry
as $function$
declare
  v_window_start timestamptz := date_trunc('milliseconds', statement_timestamp());
  v_window_end timestamptz;
  v_checkpoint_version bigint;
begin
  select checkpoint_version
    into v_checkpoint_version
    from p0_2_aggregate_telemetry.activation_checkpoint
   where controller_state = 'STARTING'
     and checkpoint_version = p_expected_checkpoint_version
     and owner_epoch = p_owner_epoch
     and owner_token_digest = p_owner_token_digest
     and lease_expires_at >= statement_timestamp()
   for update;
  if not found then
    return jsonb_build_object('created', false, 'windowStart', null, 'windowEnd', null);
  end if;

  if exists (
    select 1
      from p0_2_aggregate_telemetry.windows
     where lifecycle = 'ACTIVE'
  ) then
    return jsonb_build_object(
      'created', false,
      'windowStart', null,
      'windowEnd', null
    );
  end if;

  v_window_end := v_window_start + interval '24 hours';
  begin
    insert into p0_2_aggregate_telemetry.windows (
      window_start,
      window_end,
      lifecycle
    ) values (
      v_window_start,
      v_window_end,
      'ACTIVE'
    );
  exception when unique_violation then
    return jsonb_build_object(
      'created', false,
      'windowStart', null,
      'windowEnd', null
    );
  end;

  return jsonb_build_object(
    'created', true,
    'windowStart', to_char(v_window_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'windowEnd', to_char(v_window_end at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  );
end;
$function$;

create function p0_2_aggregate_telemetry.seal_p0_2_aggregate_telemetry_window_v1(
  p_window_start timestamptz,
  p_expected_checkpoint_version bigint,
  p_owner_epoch bigint,
  p_owner_token_digest text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, p0_2_aggregate_telemetry
as $function$
declare
  v_window_end timestamptz;
  v_checkpoint_version bigint;
begin
  select checkpoint_version
    into v_checkpoint_version
    from p0_2_aggregate_telemetry.activation_checkpoint
   where controller_state = 'SEALING'
     and window_start = p_window_start
     and checkpoint_version = p_expected_checkpoint_version
     and mod(p_expected_checkpoint_version, 2) = 0
     and owner_epoch = p_owner_epoch
     and owner_token_digest = p_owner_token_digest
   for update;
  if not found then
    return jsonb_build_object('sealed', false, 'windowInvalid', true);
  end if;

  select window_end
    into v_window_end
    from p0_2_aggregate_telemetry.windows
   where window_start = p_window_start
     and lifecycle = 'ACTIVE'
   for update;

  if not found then
    return jsonb_build_object('sealed', false, 'windowInvalid', true);
  end if;

  if statement_timestamp() < v_window_end then
    update p0_2_aggregate_telemetry.windows
       set lifecycle = 'INVALID'
     where window_start = p_window_start
       and lifecycle = 'ACTIVE';
    return jsonb_build_object('sealed', false, 'windowInvalid', true);
  end if;

  update p0_2_aggregate_telemetry.windows
     set lifecycle = 'SEALED'
   where window_start = p_window_start
     and lifecycle = 'ACTIVE';
  return jsonb_build_object('sealed', true, 'windowInvalid', false);
end;
$function$;

create function p0_2_aggregate_telemetry.read_p0_2_aggregate_telemetry_report_v1(
  p_window_start timestamptz,
  p_expected_checkpoint_version bigint,
  p_owner_epoch bigint,
  p_owner_token_digest text
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, p0_2_aggregate_telemetry
as $function$
  select jsonb_build_object(
    'windowStart', to_char(window_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'windowEnd', to_char(window_end at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'unexpected5xxCount', unexpected_5xx_count,
    'authJwtRegressionCount', auth_jwt_regression_count,
    'rlsErrorCount', rls_error_count,
    'dossiersRegressionCount', dossiers_regression_count,
    'aggregateOnly', true,
    'windowFullyCovered', bit_count(coverage) = 1440,
    'pass', lifecycle = 'SEALED'
      and window_end = window_start + interval '24 hours'
      and bit_count(coverage) = 1440
      and unexpected_5xx_count = 0
      and auth_jwt_regression_count = 0
      and rls_error_count = 0
      and dossiers_regression_count = 0
      and aggregate_only is true
  )
  from p0_2_aggregate_telemetry.windows
  where window_start = p_window_start
    and lifecycle in ('SEALED', 'INVALID')
    and exists (
      select 1
        from p0_2_aggregate_telemetry.activation_checkpoint
       where controller_state = 'SEALING'
         and window_start = p_window_start
         and checkpoint_version = p_expected_checkpoint_version
         and mod(p_expected_checkpoint_version, 2) = 0
         and owner_epoch = p_owner_epoch
         and owner_token_digest = p_owner_token_digest
    );
$function$;

alter function p0_2_aggregate_telemetry.create_p0_2_aggregate_telemetry_window_v1(bigint, bigint, text)
  owner to p0_2_telemetry_private_owner;
alter function p0_2_aggregate_telemetry.seal_p0_2_aggregate_telemetry_window_v1(timestamptz, bigint, bigint, text)
  owner to p0_2_telemetry_private_owner;
alter function p0_2_aggregate_telemetry.read_p0_2_aggregate_telemetry_report_v1(timestamptz, bigint, bigint, text)
  owner to p0_2_telemetry_private_owner;

revoke all on schema p0_2_aggregate_telemetry from public, anon, authenticated;
revoke all on table p0_2_aggregate_telemetry.windows from public, anon, authenticated;
revoke all on function p0_2_aggregate_telemetry.create_p0_2_aggregate_telemetry_window_v1(bigint, bigint, text)
  from public, anon, authenticated;
revoke all on function p0_2_aggregate_telemetry.increment_p0_2_aggregate_telemetry_counter_v1(timestamptz, text, integer, bigint, bigint, text)
  from public, anon, authenticated;
revoke all on function p0_2_aggregate_telemetry.cover_p0_2_aggregate_telemetry_minute_v1(timestamptz, integer, bigint, bigint, text)
  from public, anon, authenticated;
revoke all on function p0_2_aggregate_telemetry.seal_p0_2_aggregate_telemetry_window_v1(timestamptz, bigint, bigint, text)
  from public, anon, authenticated;
revoke all on function p0_2_aggregate_telemetry.read_p0_2_aggregate_telemetry_report_v1(timestamptz, bigint, bigint, text)
  from public, anon, authenticated;

grant usage on schema p0_2_aggregate_telemetry
  to p0_2_telemetry_lifecycle_controller,
     p0_2_telemetry_runtime_writer,
     p0_2_telemetry_report_reader;
grant execute on function p0_2_aggregate_telemetry.create_p0_2_aggregate_telemetry_window_v1(bigint, bigint, text)
  to p0_2_telemetry_lifecycle_controller;
grant execute on function p0_2_aggregate_telemetry.seal_p0_2_aggregate_telemetry_window_v1(timestamptz, bigint, bigint, text)
  to p0_2_telemetry_lifecycle_controller;
grant execute on function p0_2_aggregate_telemetry.increment_p0_2_aggregate_telemetry_counter_v1(timestamptz, text, integer, bigint, bigint, text)
  to p0_2_telemetry_runtime_writer;
grant execute on function p0_2_aggregate_telemetry.cover_p0_2_aggregate_telemetry_minute_v1(timestamptz, integer, bigint, bigint, text)
  to p0_2_telemetry_lifecycle_controller;
grant execute on function p0_2_aggregate_telemetry.read_p0_2_aggregate_telemetry_report_v1(timestamptz, bigint, bigint, text)
  to p0_2_telemetry_report_reader;

revoke create on database postgres from p0_2_telemetry_private_owner;
revoke p0_2_telemetry_private_owner from postgres;

commit;
