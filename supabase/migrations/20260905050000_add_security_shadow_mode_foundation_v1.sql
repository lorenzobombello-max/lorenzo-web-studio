create table lws_internal.security_action_enforcement_mode (
  action_code text primary key
    references lws_internal.security_action_policy(action_code) on delete restrict,
  mode text not null default 'OFF' check (mode in ('OFF', 'SHADOW', 'ENFORCE')),
  updated_at timestamptz not null default clock_timestamp(),
  constraint security_action_enforcement_mode_action_code_shape
    check (action_code ~ '^[a-z][a-z0-9_]{2,119}$')
);

revoke all privileges on table lws_internal.security_action_enforcement_mode
from public, anon, authenticated, service_role;

insert into lws_internal.security_action_enforcement_mode(action_code, mode)
select action.action_code, 'OFF'
from lws_internal.security_action_policy as action
where action.risk_level in ('HIGH', 'CRITICAL')
order by action.action_code;

do $$
begin
  if exists (
    select 1
    from lws_internal.security_action_policy as action
    full join lws_internal.security_action_enforcement_mode as enforcement using (action_code)
    where (action.risk_level in ('HIGH', 'CRITICAL')) is distinct from (enforcement.action_code is not null)
  ) then
    raise exception using errcode = '23514', message = 'SECURITY_ENFORCEMENT_MODE_POLICY_COVERAGE_INVALID';
  end if;

  if exists (
    select 1
    from lws_internal.security_action_enforcement_mode
    where mode = 'ENFORCE'
  ) then
    raise exception using errcode = '23514', message = 'SECURITY_ENFORCEMENT_MODE_AUTOMATIC_ENFORCE_DENIED';
  end if;
end;
$$;

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
    'VELOCITY_RELEASED',
    'RECOVERY_RECORDED',
    'RESTORE_REQUESTED',
    'RESTORE_APPROVED',
    'COMPENSATION_RECORDED',
    'SHADOW_EVALUATED'
  ));

create function lws_internal.evaluate_security_action_orchestration_v1(
  p_action_code text,
  p_object_reference uuid default null,
  p_object_reference_fingerprint text default null,
  p_approval_id uuid default null,
  p_request_fingerprint text default null,
  p_recovery_record_id uuid default null
)
returns table (
  action_code text,
  mode text,
  would_allow boolean,
  final_reason_code text,
  policy_result jsonb,
  approval_result jsonb,
  velocity_result jsonb,
  recovery_result jsonb,
  evaluated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = lws_internal, public, auth, pg_catalog
as $$
declare
  v_action_code text := btrim(coalesce(p_action_code, ''));
  v_mode text;
  v_actor uuid;
  v_policy record;
  v_approval record;
  v_velocity record;
  v_recovery record;
  v_recovery_policy lws_internal.security_recovery_policy%rowtype;
  v_policy_allowed boolean := false;
  v_approval_allowed boolean := false;
  v_velocity_allowed boolean := false;
  v_recovery_allowed boolean := false;
  v_policy_reason text := 'SECURITY_ACTION_POLICY_NOT_EVALUATED';
  v_approval_reason text := 'SECURITY_APPROVAL_NOT_EVALUATED';
  v_velocity_reason text := 'SECURITY_VELOCITY_NOT_EVALUATED';
  v_recovery_reason text := 'SECURITY_RECOVERY_NOT_EVALUATED';
  v_policy_result jsonb := '{}'::jsonb;
  v_approval_result jsonb := '{}'::jsonb;
  v_velocity_result jsonb := '{}'::jsonb;
  v_recovery_result jsonb := '{}'::jsonb;
  v_would_allow boolean;
  v_final_reason text;
  v_blocking_layer text;
  v_evaluated_at timestamptz := clock_timestamp();
begin
  if coalesce(auth.jwt() ->> 'role', '') = 'service_role' then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  v_actor := lws_internal.resolve_security_velocity_actor_v1();

  select enforcement.mode into v_mode
  from lws_internal.security_action_enforcement_mode as enforcement
  where enforcement.action_code = v_action_code;

  if not found then
    return query select
      v_action_code,
      'OFF'::text,
      false,
      'SECURITY_ORCHESTRATION_CONFIGURATION_MISSING'::text,
      jsonb_build_object('evaluated', false, 'allowed', false, 'reason_code', 'SECURITY_ACTION_NOT_REGISTERED'),
      jsonb_build_object('evaluated', false, 'allowed', false, 'reason_code', 'SECURITY_APPROVAL_NOT_EVALUATED'),
      jsonb_build_object('evaluated', false, 'allowed', false, 'reason_code', 'SECURITY_VELOCITY_NOT_EVALUATED'),
      jsonb_build_object('evaluated', false, 'allowed', false, 'reason_code', 'SECURITY_RECOVERY_NOT_EVALUATED'),
      v_evaluated_at;
    return;
  end if;

  if v_mode = 'OFF' then
    return query select
      v_action_code,
      v_mode,
      true,
      'SECURITY_ORCHESTRATION_OFF'::text,
      jsonb_build_object('evaluated', false, 'allowed', true, 'reason_code', 'SECURITY_ORCHESTRATION_OFF'),
      jsonb_build_object('evaluated', false, 'allowed', true, 'reason_code', 'SECURITY_ORCHESTRATION_OFF'),
      jsonb_build_object('evaluated', false, 'allowed', true, 'reason_code', 'SECURITY_ORCHESTRATION_OFF'),
      jsonb_build_object('evaluated', false, 'allowed', true, 'reason_code', 'SECURITY_ORCHESTRATION_OFF'),
      v_evaluated_at;
    return;
  end if;

  begin
    select * into v_policy
    from lws_internal.evaluate_security_action_v1(v_action_code);

    if not found then
      v_policy_reason := 'SECURITY_ACTION_POLICY_RESULT_MISSING';
    else
      v_policy_allowed := v_policy.allowed;
      v_policy_reason := v_policy.reason_code;
      if v_policy.requires_aal2 and coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
        v_policy_allowed := false;
        v_policy_reason := 'AAL2_REQUIRED';
      end if;
      v_policy_result := jsonb_build_object(
        'evaluated', true,
        'allowed', v_policy_allowed,
        'reason_code', v_policy_reason,
        'risk_level', v_policy.risk_level,
        'requires_aal2', v_policy.requires_aal2,
        'requires_dual_control', v_policy.requires_dual_control
      );
    end if;
  exception when others then
    v_policy_allowed := false;
    v_policy_reason := 'SECURITY_ACTION_POLICY_EVALUATION_ERROR';
  end;
  if v_policy_result = '{}'::jsonb then
    v_policy_result := jsonb_build_object('evaluated', true, 'allowed', false, 'reason_code', v_policy_reason);
  end if;

  if coalesce(v_policy.requires_dual_control, true) then
    if p_approval_id is null
      or p_request_fingerprint is null
      or p_object_reference_fingerprint is null then
      v_approval_reason := 'SECURITY_APPROVAL_BINDING_REQUIRED';
    else
      begin
        select * into v_approval
        from lws_internal.evaluate_security_action_approval_v1(
          p_approval_id,
          v_action_code,
          p_object_reference_fingerprint,
          p_request_fingerprint
        );
        v_approval_allowed := coalesce(v_approval.allowed, false) and exists (
          select 1
          from lws_internal.security_action_approvals as approval
          where approval.id = p_approval_id
            and approval.requested_by = v_actor
        );
        v_approval_reason := case
          when coalesce(v_approval.allowed, false) and not v_approval_allowed
            then 'SECURITY_APPROVAL_REQUESTER_MISMATCH'
          else coalesce(v_approval.reason_code, 'SECURITY_APPROVAL_RESULT_MISSING')
        end;
      exception when others then
        v_approval_allowed := false;
        v_approval_reason := 'SECURITY_APPROVAL_EVALUATION_ERROR';
      end;
    end if;
    v_approval_result := jsonb_build_object(
      'evaluated', true,
      'required', true,
      'allowed', v_approval_allowed,
      'reason_code', v_approval_reason,
      'approval_id', p_approval_id
    );
  else
    v_approval_allowed := true;
    v_approval_reason := 'SECURITY_APPROVAL_NOT_REQUIRED';
    v_approval_result := jsonb_build_object(
      'evaluated', true,
      'required', false,
      'allowed', true,
      'reason_code', v_approval_reason
    );
  end if;

  begin
    select * into v_velocity
    from lws_internal.evaluate_security_action_velocity_v1(v_action_code, v_policy.domain);
    v_velocity_allowed := coalesce(v_velocity.allowed, false);
    v_velocity_reason := coalesce(v_velocity.reason_code, 'SECURITY_VELOCITY_RESULT_MISSING');
    v_velocity_result := jsonb_build_object(
      'evaluated', true,
      'allowed', v_velocity_allowed,
      'reason_code', v_velocity_reason,
      'current_hour_count', coalesce(v_velocity.current_hour_count, 0),
      'current_day_count', coalesce(v_velocity.current_day_count, 0),
      'cooldown_remaining_seconds', coalesce(v_velocity.cooldown_remaining_seconds, 0),
      'circuit_breaker_active', coalesce(v_velocity.circuit_breaker_active, false)
    );
  exception when others then
    v_velocity_allowed := false;
    v_velocity_reason := 'SECURITY_VELOCITY_EVALUATION_ERROR';
    v_velocity_result := jsonb_build_object(
      'evaluated', true,
      'allowed', false,
      'reason_code', v_velocity_reason,
      'circuit_breaker_active', false
    );
  end;

  select * into v_recovery_policy
  from lws_internal.security_recovery_policy as recovery
  where recovery.action_code = v_action_code and recovery.enabled;
  if not found then
    v_recovery_reason := 'SECURITY_RECOVERY_POLICY_NOT_AVAILABLE';
    v_recovery_result := jsonb_build_object(
      'evaluated', true,
      'allowed', false,
      'reason_code', v_recovery_reason
    );
  elsif v_action_code in (
    'purge_dossier_v1',
    'purge_sdf_dossier_v1',
    'permanently_delete_pending_intake_v1'
  ) then
    begin
      select * into v_recovery
      from lws_internal.evaluate_security_destructive_execution_v1(
        p_recovery_record_id,
        v_action_code,
        p_object_reference,
        p_object_reference_fingerprint
      );
      v_recovery_allowed := coalesce(v_recovery.allowed, false);
      v_recovery_reason := coalesce(v_recovery.reason_code, 'SECURITY_DESTRUCTIVE_RESULT_MISSING');
      v_recovery_result := jsonb_build_object(
        'evaluated', true,
        'allowed', v_recovery_allowed,
        'reason_code', v_recovery_reason,
        'recovery_class', v_recovery_policy.recovery_class,
        'retention_satisfied', coalesce(v_recovery.retention_satisfied, false),
        'trash_first_satisfied', coalesce(v_recovery.trash_first_satisfied, false),
        'backup_dependency_satisfied', coalesce(v_recovery.backup_dependency_satisfied, false),
        'dual_control_satisfied', coalesce(v_recovery.dual_control_satisfied, false)
      );
    exception when others then
      v_recovery_allowed := false;
      v_recovery_reason := 'SECURITY_DESTRUCTIVE_EVALUATION_ERROR';
      v_recovery_result := jsonb_build_object(
        'evaluated', true,
        'allowed', false,
        'reason_code', v_recovery_reason,
        'recovery_class', v_recovery_policy.recovery_class,
        'backup_dependency_satisfied', false
      );
    end;
  else
    v_recovery_allowed := true;
    v_recovery_reason := 'SECURITY_RECOVERY_POLICY_READY';
    v_recovery_result := jsonb_build_object(
      'evaluated', true,
      'allowed', true,
      'reason_code', v_recovery_reason,
      'recovery_class', v_recovery_policy.recovery_class,
      'requires_backup_dependency', v_recovery_policy.requires_backup_dependency,
      'requires_trash_first', v_recovery_policy.requires_trash_first
    );
  end if;

  v_would_allow := v_policy_allowed
    and v_approval_allowed
    and v_velocity_allowed
    and v_recovery_allowed;
  if not v_policy_allowed then
    v_final_reason := v_policy_reason;
    v_blocking_layer := 'POLICY';
  elsif not v_approval_allowed then
    v_final_reason := v_approval_reason;
    v_blocking_layer := 'APPROVAL';
  elsif not v_velocity_allowed then
    v_final_reason := v_velocity_reason;
    v_blocking_layer := 'VELOCITY';
  elsif not v_recovery_allowed then
    v_final_reason := v_recovery_reason;
    v_blocking_layer := 'RECOVERY';
  else
    v_final_reason := 'SECURITY_ORCHESTRATION_WOULD_ALLOW';
    v_blocking_layer := null;
  end if;

  if v_mode = 'SHADOW' then
    insert into lws_internal.security_control_events (
      actor_auth_user_id,
      event_type,
      domain,
      action_code,
      object_reference_fingerprint,
      occurred_at,
      metadata
    ) values (
      v_actor,
      'SHADOW_EVALUATED',
      v_policy.domain,
      v_action_code,
      p_object_reference_fingerprint,
      v_evaluated_at,
      jsonb_strip_nulls(jsonb_build_object(
        'mode', v_mode,
        'would_allow', v_would_allow,
        'reason_code', v_final_reason,
        'blocking_layer', v_blocking_layer,
        'policy_reason_code', v_policy_reason,
        'approval_reason_code', v_approval_reason,
        'velocity_reason_code', v_velocity_reason,
        'recovery_reason_code', v_recovery_reason
      ))
    );
  end if;

  return query select
    v_action_code,
    v_mode,
    v_would_allow,
    v_final_reason,
    v_policy_result,
    v_approval_result,
    v_velocity_result,
    v_recovery_result,
    v_evaluated_at;
end;
$$;

revoke all on function lws_internal.evaluate_security_action_orchestration_v1(
  text, uuid, text, uuid, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function lws_internal.evaluate_security_action_orchestration_v1(
  text, uuid, text, uuid, text, uuid
) to service_role;

comment on table lws_internal.security_action_enforcement_mode is
  'Private P0-3E orchestration mode registry. P0-3A remains the sole action policy registry. Every HIGH/CRITICAL action starts OFF; no production action is wired by this migration.';
comment on function lws_internal.evaluate_security_action_orchestration_v1(
  text, uuid, text, uuid, text, uuid
) is
  'Private P0-3E read-only security-layer orchestration with append-only SHADOW_EVALUATED audit only. Actor derives from auth.uid(); no approval, velocity, recovery, breaker, or business state is consumed.';