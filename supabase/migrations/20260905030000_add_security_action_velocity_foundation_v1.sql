do $$
begin
  if exists (
    select 1
    from lws_internal.security_action_policy
    where risk_level in ('HIGH', 'CRITICAL')
      and (
        max_per_hour is null
        or max_per_day is null
        or cooldown_seconds is null
        or max_per_hour > max_per_day
      )
  ) then
    raise exception using errcode = 'P0001', message = 'SECURITY_VELOCITY_POLICY_INCOMPLETE';
  end if;
end;
$$;

create table lws_internal.security_action_velocity (
  velocity_id bigint generated always as identity primary key,
  actor_auth_user_id uuid not null references auth.users(id),
  action_code text not null references lws_internal.security_action_policy(action_code),
  domain text not null check (domain ~ '^[A-Z][A-Z0-9_]{1,79}$'),
  object_reference_fingerprint char(64) not null
    check (object_reference_fingerprint ~ '^[0-9a-f]{64}$'),
  idempotency_fingerprint char(64) not null
    check (idempotency_fingerprint ~ '^[0-9a-f]{64}$'),
  consumed_at timestamptz not null default clock_timestamp(),
  unique (actor_auth_user_id, action_code, idempotency_fingerprint)
);

create index security_action_velocity_count_idx
  on lws_internal.security_action_velocity(actor_auth_user_id, action_code, consumed_at desc);

revoke all privileges on table lws_internal.security_action_velocity
from public, anon, authenticated, service_role;
revoke all privileges on sequence lws_internal.security_action_velocity_velocity_id_seq
from public, anon, authenticated, service_role;

alter table lws_internal.security_control_events
  drop constraint security_control_events_event_type_check;
alter table lws_internal.security_control_events
  add constraint security_control_events_event_type_check check (event_type in (
    'POLICY_BOOTSTRAPPED',
    'POLICY_CHANGED',
    'SWITCH_ACTIVATED',
    'SWITCH_RELEASED',
    'APPROVAL_REQUESTED',
    'APPROVAL_GRANTED',
    'APPROVAL_REJECTED',
    'APPROVAL_CANCELLED',
    'APPROVAL_EXPIRED',
    'APPROVAL_EXECUTED',
    'VELOCITY_CONSUMED',
    'VELOCITY_BLOCKED',
    'VELOCITY_RELEASED'
  ));

create function lws_internal.resolve_security_velocity_actor_v1()
returns uuid
language plpgsql
stable
security definer
set search_path = lws_internal, auth, pg_catalog
as $$
declare
  v_actor uuid := auth.uid();
  v_status text;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select operator.status into v_status
  from public.commercial_operators as operator
  where operator.auth_user_id = v_actor;
  if not found then
    raise exception using errcode = '42501', message = 'SECURITY_VELOCITY_OPERATOR_REQUIRED';
  elsif v_status = 'DISABLED' then
    raise exception using errcode = '42501', message = 'OPERATOR_DISABLED';
  elsif v_status = 'REVOKED' then
    raise exception using errcode = '42501', message = 'OPERATOR_REVOKED';
  elsif v_status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;

  return v_actor;
end;
$$;

revoke all on function lws_internal.resolve_security_velocity_actor_v1()
from public, anon, authenticated, service_role;

create function lws_internal.evaluate_security_action_velocity_v1(
  p_action_code text,
  p_domain text
)
returns table (
  allowed boolean,
  reason_code text,
  current_hour_count integer,
  current_day_count integer,
  cooldown_remaining_seconds integer,
  circuit_breaker_active boolean
)
language plpgsql
stable
security definer
set search_path = lws_internal, auth, pg_catalog
as $$
declare
  v_actor uuid := lws_internal.resolve_security_velocity_actor_v1();
  v_action_code text := btrim(coalesce(p_action_code, ''));
  v_domain text := upper(btrim(coalesce(p_domain, '')));
  v_now timestamptz := clock_timestamp();
  v_policy lws_internal.security_action_policy%rowtype;
  v_policy_evaluation record;
  v_domain_switch_active boolean;
  v_global_switch_active boolean;
  v_hour_count integer;
  v_day_count integer;
  v_last_action_at timestamptz;
  v_cooldown_remaining integer := 0;
begin
  select * into v_policy
  from lws_internal.security_action_policy as policy
  where policy.action_code = v_action_code;
  if not found then
    return query select false, 'SECURITY_ACTION_NOT_REGISTERED', 0, 0, 0, false;
    return;
  end if;
  if v_policy.domain <> v_domain then
    return query select false, 'SECURITY_VELOCITY_DOMAIN_MISMATCH', 0, 0, 0, false;
    return;
  end if;
  if v_policy.risk_level not in ('HIGH', 'CRITICAL')
    or v_policy.max_per_hour is null
    or v_policy.max_per_day is null
    or v_policy.cooldown_seconds is null
    or v_policy.max_per_hour > v_policy.max_per_day then
    return query select false, 'SECURITY_VELOCITY_POLICY_INVALID', 0, 0, 0, false;
    return;
  end if;

  select is_active into v_global_switch_active
  from lws_internal.security_kill_switch
  where scope = 'GLOBAL';
  if not found then
    return query select false, 'SECURITY_SWITCH_CONFIGURATION_MISSING', 0, 0, 0, false;
    return;
  end if;
  select is_active into v_domain_switch_active
  from lws_internal.security_kill_switch
  where scope = v_policy.domain;
  if not found then
    return query select false, 'SECURITY_VELOCITY_DOMAIN_SWITCH_MISSING', 0, 0, 0, v_global_switch_active;
    return;
  end if;

  select * into v_policy_evaluation
  from lws_internal.evaluate_security_action_v1(v_policy.action_code);
  if not found or not v_policy_evaluation.allowed then
    return query select false,
      coalesce(v_policy_evaluation.reason_code, 'SECURITY_ACTION_POLICY_DENIED'),
      0, 0, 0, v_global_switch_active or v_domain_switch_active;
    return;
  end if;

  select
    count(*) filter (
      where velocity.consumed_at >= date_trunc('hour', v_now)
        and velocity.consumed_at <= v_now
    )::integer,
    count(*) filter (
      where velocity.consumed_at >= date_trunc('day', v_now)
        and velocity.consumed_at <= v_now
    )::integer,
    max(velocity.consumed_at) filter (where velocity.consumed_at <= v_now)
  into v_hour_count, v_day_count, v_last_action_at
  from lws_internal.security_action_velocity as velocity
  where velocity.actor_auth_user_id = v_actor
    and velocity.action_code = v_policy.action_code;

  if v_last_action_at is not null and v_policy.cooldown_seconds > 0 then
    v_cooldown_remaining := greatest(0, ceil(extract(epoch from (
      v_last_action_at + make_interval(secs => v_policy.cooldown_seconds) - v_now
    )))::integer);
  end if;

  if v_cooldown_remaining > 0 then
    return query select false, 'SECURITY_VELOCITY_COOLDOWN_ACTIVE',
      v_hour_count, v_day_count, v_cooldown_remaining, false;
  elsif v_hour_count >= v_policy.max_per_hour then
    return query select false, 'SECURITY_VELOCITY_HOUR_LIMIT_REACHED',
      v_hour_count, v_day_count, 0, false;
  elsif v_day_count >= v_policy.max_per_day then
    return query select false, 'SECURITY_VELOCITY_DAY_LIMIT_REACHED',
      v_hour_count, v_day_count, 0, false;
  end if;

  return query select true, 'SECURITY_VELOCITY_ALLOWED',
    v_hour_count, v_day_count, 0, false;
end;
$$;

create function lws_internal.consume_security_action_velocity_v1(
  p_action_code text,
  p_domain text,
  p_object_reference_fingerprint text,
  p_idempotency_fingerprint text
)
returns table (
  allowed boolean,
  reason_code text,
  current_hour_count integer,
  current_day_count integer,
  cooldown_remaining_seconds integer,
  circuit_breaker_active boolean
)
language plpgsql
volatile
security definer
set search_path = lws_internal, pg_catalog
as $$
declare
  v_actor uuid := lws_internal.resolve_security_velocity_actor_v1();
  v_action_code text := btrim(coalesce(p_action_code, ''));
  v_domain text := upper(btrim(coalesce(p_domain, '')));
  v_evaluation record;
  v_policy lws_internal.security_action_policy%rowtype;
  v_breaker_activated boolean := false;
begin
  if p_object_reference_fingerprint is null
    or p_object_reference_fingerprint !~ '^[0-9a-f]{64}$'
    or p_idempotency_fingerprint is null
    or p_idempotency_fingerprint !~ '^[0-9a-f]{64}$' then
    return query select false, 'SECURITY_VELOCITY_FINGERPRINT_INVALID', 0, 0, 0, false;
    return;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    v_actor::text || '|' || v_action_code,
    0
  ));

  select * into v_evaluation
  from lws_internal.evaluate_security_action_velocity_v1(
    v_action_code, v_domain
  );

  if exists (
    select 1
    from lws_internal.security_action_velocity as velocity
    where velocity.actor_auth_user_id = v_actor
      and velocity.action_code = v_action_code
      and velocity.idempotency_fingerprint = p_idempotency_fingerprint
  ) then
    return query select false, 'SECURITY_VELOCITY_REPLAY_DENIED',
      v_evaluation.current_hour_count, v_evaluation.current_day_count,
      v_evaluation.cooldown_remaining_seconds, v_evaluation.circuit_breaker_active;
    return;
  end if;

  if not coalesce(v_evaluation.allowed, false) then
    select * into v_policy
    from lws_internal.security_action_policy
    where action_code = v_action_code;

    if v_evaluation.reason_code = 'SECURITY_VELOCITY_DAY_LIMIT_REACHED'
      and v_policy.risk_level = 'CRITICAL'
      and v_policy.domain <> 'GLOBAL' then
      update lws_internal.security_kill_switch
      set is_active = true,
          reason = 'AUTOMATIC_CRITICAL_DAILY_VELOCITY_THRESHOLD',
          activated_at = clock_timestamp(),
          activated_by = v_actor,
          released_at = null,
          released_by = null
      where scope = v_policy.domain
        and not is_active;
      v_breaker_activated := found;

      if v_breaker_activated then
        insert into lws_internal.security_control_events (
          actor_auth_user_id, event_type, domain, action_code,
          object_reference_fingerprint, metadata
        ) values (
          v_actor, 'SWITCH_ACTIVATED', v_policy.domain, v_policy.action_code,
          p_object_reference_fingerprint,
          jsonb_build_object(
            'reason_code', 'AUTOMATIC_CRITICAL_DAILY_VELOCITY_THRESHOLD',
            'source', 'consume_security_action_velocity_v1'
          )
        );
      end if;
    end if;

    insert into lws_internal.security_control_events (
      actor_auth_user_id, event_type, domain, action_code,
      object_reference_fingerprint, metadata
    ) values (
      v_actor, 'VELOCITY_BLOCKED', coalesce(v_policy.domain, v_domain), v_action_code,
      p_object_reference_fingerprint,
      jsonb_build_object(
        'reason_code', coalesce(v_evaluation.reason_code, 'SECURITY_VELOCITY_DENIED'),
        'current_hour_count', coalesce(v_evaluation.current_hour_count, 0),
        'current_day_count', coalesce(v_evaluation.current_day_count, 0),
        'circuit_breaker_activated', v_breaker_activated
      )
    );

    return query select false,
      coalesce(v_evaluation.reason_code, 'SECURITY_VELOCITY_DENIED'),
      coalesce(v_evaluation.current_hour_count, 0),
      coalesce(v_evaluation.current_day_count, 0),
      coalesce(v_evaluation.cooldown_remaining_seconds, 0),
      coalesce(v_evaluation.circuit_breaker_active, false) or v_breaker_activated;
    return;
  end if;

  insert into lws_internal.security_action_velocity (
    actor_auth_user_id, action_code, domain,
    object_reference_fingerprint, idempotency_fingerprint
  ) values (
    v_actor, v_action_code, v_domain,
    p_object_reference_fingerprint, p_idempotency_fingerprint
  );

  insert into lws_internal.security_control_events (
    actor_auth_user_id, event_type, domain, action_code,
    object_reference_fingerprint, metadata
  ) values (
    v_actor, 'VELOCITY_CONSUMED', v_domain, v_action_code,
    p_object_reference_fingerprint,
    jsonb_build_object(
      'current_hour_count', v_evaluation.current_hour_count + 1,
      'current_day_count', v_evaluation.current_day_count + 1
    )
  );

  return query select true, 'SECURITY_VELOCITY_CONSUMED',
    v_evaluation.current_hour_count + 1,
    v_evaluation.current_day_count + 1,
    0, false;
end;
$$;

revoke all on function lws_internal.evaluate_security_action_velocity_v1(text, text)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.consume_security_action_velocity_v1(text, text, text, text)
from public, anon, authenticated, service_role;

comment on table lws_internal.security_action_velocity is
  'Private payload-free velocity ledger for future server-side enforcement; P0-3C wires no business action.';
comment on function lws_internal.consume_security_action_velocity_v1(text, text, text, text) is
  'Private atomic velocity reservation. Actor authority is derived only from auth.uid(); future wiring must preserve the authenticated caller JWT. Critical daily overflow may activate only the existing domain kill switch, never GLOBAL.';
