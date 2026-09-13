-- LOCAL_CANDIDATE_NOT_PRODUCTION_ACTIVATABLE. DO NOT APPLY.
-- This candidate has no grants or runtime integration and must remain inert.

begin;


create schema if not exists p0_2_aggregate_telemetry;

create table p0_2_aggregate_telemetry.windows (
  window_start timestamptz primary key,
  window_end timestamptz not null,
  lifecycle text not null default 'ACTIVE',
  unexpected_5xx_count bigint not null default 0,
  auth_jwt_regression_count bigint not null default 0,
  rls_error_count bigint not null default 0,
  dossiers_regression_count bigint not null default 0,
  coverage bit(1440) not null default repeat('0', 1440)::bit(1440),
  aggregate_only boolean not null default true,
  constraint p0_2_telemetry_exact_window check (window_end = window_start + interval '24 hours'),
  constraint p0_2_telemetry_lifecycle check (lifecycle in ('ACTIVE', 'SEALED', 'INVALID')),
  constraint p0_2_telemetry_aggregate_only check (aggregate_only is true),
  constraint p0_2_telemetry_unexpected_5xx_bounded check (unexpected_5xx_count between 0 and 9007199254740991),
  constraint p0_2_telemetry_auth_jwt_bounded check (auth_jwt_regression_count between 0 and 9007199254740991),
  constraint p0_2_telemetry_rls_bounded check (rls_error_count between 0 and 9007199254740991),
  constraint p0_2_telemetry_dossiers_bounded check (dossiers_regression_count between 0 and 9007199254740991)
);

create unique index p0_2_telemetry_single_active_window
  on p0_2_aggregate_telemetry.windows ((true))
  where lifecycle = 'ACTIVE';

create function p0_2_aggregate_telemetry.reject_destructive_window_change()
returns trigger
language plpgsql
set search_path = pg_catalog, p0_2_aggregate_telemetry
as $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'P0_2_TELEMETRY_WINDOW_DELETE_FORBIDDEN';
  end if;
  if new.window_start is distinct from old.window_start
    or new.window_end is distinct from old.window_end
    or new.aggregate_only is distinct from old.aggregate_only then
    raise exception 'P0_2_TELEMETRY_WINDOW_BINDING_IMMUTABLE';
  end if;
  if old.lifecycle in ('SEALED', 'INVALID') then
    raise exception 'P0_2_TELEMETRY_TERMINAL_WINDOW_IMMUTABLE';
  end if;
  if new.unexpected_5xx_count < old.unexpected_5xx_count
    or new.auth_jwt_regression_count < old.auth_jwt_regression_count
    or new.rls_error_count < old.rls_error_count
    or new.dossiers_regression_count < old.dossiers_regression_count
    or (new.coverage | old.coverage) <> new.coverage then
    raise exception 'P0_2_TELEMETRY_AGGREGATES_MONOTONIC';
  end if;
  return new;
end;
$function$;

create trigger p0_2_telemetry_reject_destructive_update
before update on p0_2_aggregate_telemetry.windows
for each row execute function p0_2_aggregate_telemetry.reject_destructive_window_change();

create trigger p0_2_telemetry_reject_delete
before delete on p0_2_aggregate_telemetry.windows
for each row execute function p0_2_aggregate_telemetry.reject_destructive_window_change();

revoke all on schema p0_2_aggregate_telemetry from public, anon, authenticated;
revoke all on table p0_2_aggregate_telemetry.windows from public, anon, authenticated;
revoke all on function p0_2_aggregate_telemetry.reject_destructive_window_change() from public, anon, authenticated;

commit;