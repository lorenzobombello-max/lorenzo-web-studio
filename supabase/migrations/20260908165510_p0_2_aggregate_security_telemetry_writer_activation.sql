-- LOCAL_INERT_WRITER_CANDIDATE_NOT_PRODUCTION_ACTIVATABLE. DO NOT APPLY.
-- This candidate models two private aggregate RPCs and grants no runtime access.

begin;


create function p0_2_aggregate_telemetry.increment_p0_2_aggregate_telemetry_counter_v1(
  p_window_start timestamptz,
  p_category text,
  p_increment integer,
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
  affected_rows integer := 0;
  v_checkpoint_version bigint;
begin
  select checkpoint_version
    into v_checkpoint_version
    from p0_2_aggregate_telemetry.activation_checkpoint
   where controller_state = 'ACTIVE'
     and window_start = p_window_start
     and checkpoint_version = p_expected_checkpoint_version
     and mod(checkpoint_version, 2) = 1
     and owner_epoch = p_owner_epoch
     and owner_token_digest = p_owner_token_digest
   for update;
  if not found then
    return jsonb_build_object('applied', false, 'windowInvalid', true);
  end if;

  if p_increment is distinct from 1
    or p_category is null
    or p_category not in ('unexpected_5xx', 'auth_jwt_regression', 'rls_error', 'dossiers_regression') then
    update p0_2_aggregate_telemetry.windows
       set lifecycle = 'INVALID'
     where window_start = p_window_start
       and lifecycle = 'ACTIVE';
    return jsonb_build_object('applied', false, 'windowInvalid', true);
  end if;

  begin
    update p0_2_aggregate_telemetry.windows
       set unexpected_5xx_count = unexpected_5xx_count + case when p_category = 'unexpected_5xx' then 1 else 0 end,
           auth_jwt_regression_count = auth_jwt_regression_count + case when p_category = 'auth_jwt_regression' then 1 else 0 end,
           rls_error_count = rls_error_count + case when p_category = 'rls_error' then 1 else 0 end,
           dossiers_regression_count = dossiers_regression_count + case when p_category = 'dossiers_regression' then 1 else 0 end
     where window_start = p_window_start
       and lifecycle = 'ACTIVE';
    get diagnostics affected_rows = row_count;
  exception when others then
    update p0_2_aggregate_telemetry.windows
       set lifecycle = 'INVALID'
     where window_start = p_window_start
       and lifecycle = 'ACTIVE';
    return jsonb_build_object('applied', false, 'windowInvalid', true);
  end;

  if affected_rows <> 1 then
    return jsonb_build_object('applied', false, 'windowInvalid', true);
  end if;
  return jsonb_build_object('applied', true, 'windowInvalid', false);
end;
$function$;

create function p0_2_aggregate_telemetry.cover_p0_2_aggregate_telemetry_minute_v1(
  p_window_start timestamptz,
  p_minute_bucket integer,
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
  affected_rows integer := 0;
  v_checkpoint_version bigint;
begin
  select checkpoint_version
    into v_checkpoint_version
    from p0_2_aggregate_telemetry.activation_checkpoint
   where controller_state = 'ACTIVE'
     and window_start = p_window_start
     and checkpoint_version = p_expected_checkpoint_version
     and mod(checkpoint_version, 2) = 1
     and owner_epoch = p_owner_epoch
     and owner_token_digest = p_owner_token_digest
   for update;
  if not found then
    return jsonb_build_object('applied', false, 'windowInvalid', true);
  end if;

  if p_minute_bucket is null or p_minute_bucket < 0 or p_minute_bucket > 1439 then
    update p0_2_aggregate_telemetry.windows
       set lifecycle = 'INVALID'
     where window_start = p_window_start
       and lifecycle = 'ACTIVE';
    return jsonb_build_object('applied', false, 'windowInvalid', true);
  end if;

  begin
    update p0_2_aggregate_telemetry.windows
       set coverage = set_bit(coverage, p_minute_bucket, 1)
     where window_start = p_window_start
       and lifecycle = 'ACTIVE';
    get diagnostics affected_rows = row_count;
  exception when others then
    update p0_2_aggregate_telemetry.windows
       set lifecycle = 'INVALID'
     where window_start = p_window_start
       and lifecycle = 'ACTIVE';
    return jsonb_build_object('applied', false, 'windowInvalid', true);
  end;

  if affected_rows <> 1 then
    return jsonb_build_object('applied', false, 'windowInvalid', true);
  end if;
  return jsonb_build_object('applied', true, 'windowInvalid', false);
end;
$function$;

revoke all on function p0_2_aggregate_telemetry.increment_p0_2_aggregate_telemetry_counter_v1(timestamptz, text, integer, bigint, bigint, text)
  from public, anon, authenticated;
revoke all on function p0_2_aggregate_telemetry.cover_p0_2_aggregate_telemetry_minute_v1(timestamptz, integer, bigint, bigint, text)
  from public, anon, authenticated;

commit;