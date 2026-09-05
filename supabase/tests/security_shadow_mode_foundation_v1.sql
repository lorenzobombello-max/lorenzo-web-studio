begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

create function pg_temp.set_shadow_claims_v1(
  p_subject uuid,
  p_role text default 'authenticated',
  p_aal text default 'aal2'
)
returns void
language sql
as $$
  select set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_subject, 'role', p_role, 'aal', p_aal)::text,
    true
  )::text;
$$;

select has_table(
  'lws_internal',
  'security_action_enforcement_mode',
  'private central enforcement-mode registry exists'
);
select results_eq(
  $$select distinct mode from lws_internal.security_action_enforcement_mode order by mode$$,
  $$values ('OFF'::text)$$,
  'every bootstrapped mode defaults to OFF and never ENFORCE'
);
select is(
  (select count(*)::integer from lws_internal.security_action_enforcement_mode),
  (select count(*)::integer from lws_internal.security_action_policy where risk_level in ('HIGH', 'CRITICAL')),
  'mode registry exactly covers the P0-3A HIGH/CRITICAL registry'
);
select ok(
  to_regprocedure('lws_internal.evaluate_security_action_orchestration_v1(text,uuid,text,uuid,text,uuid)') is not null
  and to_regprocedure('lws_internal.evaluate_security_action_orchestration_v1(uuid,text,uuid,text,uuid,text,uuid)') is null,
  'orchestration API exists without a caller-controlled actor UUID'
);

insert into auth.users(id, email) values
  ('f7000000-0000-4000-8000-000000000001', 'shadow-owner@example.test'),
  ('f7000000-0000-4000-8000-000000000002', 'shadow-approver@example.test'),
  ('f7000000-0000-4000-8000-000000000003', 'shadow-disabled@example.test');

set local session_replication_role = replica;
insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status
) values
  ('f7010000-0000-4000-8000-000000000001', 'f7000000-0000-4000-8000-000000000001', 'Synthetic Shadow Owner', 'owner', 'ACTIVE'),
  ('f7010000-0000-4000-8000-000000000002', 'f7000000-0000-4000-8000-000000000002', 'Synthetic Shadow Approver', 'admin', 'ACTIVE'),
  ('f7010000-0000-4000-8000-000000000003', 'f7000000-0000-4000-8000-000000000003', 'Synthetic Shadow Disabled', 'operator', 'DISABLED');
set local session_replication_role = origin;

select pg_temp.set_shadow_claims_v1('f7000000-0000-4000-8000-000000000001');

create temporary table shadow_off_result as
select * from lws_internal.evaluate_security_action_orchestration_v1(
  'confirm_payment',
  'f7100000-0000-4000-8000-000000000001',
  repeat('a', 64),
  null,
  null,
  null
);
select is((select mode from shadow_off_result), 'OFF', 'OFF mode is returned explicitly');
select ok(
  (select would_allow and final_reason_code = 'SECURITY_ORCHESTRATION_OFF' from shadow_off_result),
  'OFF leaves security orchestration inactive'
);
select is(
  (select count(*)::integer from lws_internal.security_control_events where event_type = 'SHADOW_EVALUATED'),
  0,
  'OFF does not write a shadow event'
);

update lws_internal.security_action_enforcement_mode
set mode = 'SHADOW', updated_at = clock_timestamp()
where action_code in ('confirm_payment', 'purge_dossier_v1');

insert into lws_internal.security_action_approvals (
  id, action_code, domain, object_reference_fingerprint,
  requested_by, requested_at, request_fingerprint, expires_at,
  status, approved_by, approved_at
) values (
  'f7200000-0000-4000-8000-000000000001',
  'confirm_payment', 'FINANCE_FINALIZATION', repeat('a', 64),
  'f7000000-0000-4000-8000-000000000001', clock_timestamp(), repeat('b', 64),
  clock_timestamp() + interval '15 minutes', 'APPROVED',
  'f7000000-0000-4000-8000-000000000002', clock_timestamp()
);

create temporary table shadow_allow_result as
select * from lws_internal.evaluate_security_action_orchestration_v1(
  'confirm_payment',
  'f7100000-0000-4000-8000-000000000001',
  repeat('a', 64),
  'f7200000-0000-4000-8000-000000000001',
  repeat('b', 64),
  null
);
select ok(
  (select mode = 'SHADOW' and would_allow and final_reason_code = 'SECURITY_ORCHESTRATION_WOULD_ALLOW'
   from shadow_allow_result),
  'SHADOW fully evaluates an allowed action without executing it'
);
select ok(
  (select (policy_result ->> 'evaluated')::boolean
    and (approval_result ->> 'evaluated')::boolean
    and (velocity_result ->> 'evaluated')::boolean
    and (recovery_result ->> 'evaluated')::boolean
   from shadow_allow_result),
  'SHADOW evaluates policy, approval, velocity, and recovery layers'
);
select is(
  (select status from lws_internal.security_action_approvals where id = 'f7200000-0000-4000-8000-000000000001'),
  'APPROVED',
  'SHADOW does not mark approval EXECUTED'
);
select is(
  (select count(*)::integer from lws_internal.security_action_velocity
   where actor_auth_user_id = 'f7000000-0000-4000-8000-000000000001'),
  0,
  'SHADOW does not consume velocity'
);
select ok(
  not (select is_active from lws_internal.security_kill_switch where scope = 'FINANCE_FINALIZATION'),
  'SHADOW does not activate the circuit breaker'
);
select is(
  (select count(*)::integer from lws_internal.security_recovery_records
   where actor_auth_user_id = 'f7000000-0000-4000-8000-000000000001'),
  0,
  'SHADOW does not create or consume a recovery record'
);
select is(
  (select count(*)::integer from lws_internal.security_control_events
   where event_type = 'SHADOW_EVALUATED' and action_code = 'confirm_payment'),
  1,
  'SHADOW writes exactly one append-only event for one evaluation'
);
select is(
  (select actor_auth_user_id::text from lws_internal.security_control_events
   where event_type = 'SHADOW_EVALUATED' and action_code = 'confirm_payment'),
  'f7000000-0000-4000-8000-000000000001',
  'shadow event actor is server-derived from auth.uid()'
);
select ok(
  (select metadata - array[
      'mode', 'would_allow', 'reason_code', 'blocking_layer',
      'policy_reason_code', 'approval_reason_code',
      'velocity_reason_code', 'recovery_reason_code'
    ]::text[] = '{}'::jsonb
   from lws_internal.security_control_events
   where event_type = 'SHADOW_EVALUATED' and action_code = 'confirm_payment'),
  'shadow metadata contains only the approved safe orchestration fields'
);
select throws_ok(
  $$update lws_internal.security_control_events
    set metadata = '{}'::jsonb
    where event_type = 'SHADOW_EVALUATED' and action_code = 'confirm_payment'$$,
  '55000',
  'SECURITY_CONTROL_EVENT_APPEND_ONLY',
  'shadow events retain the existing append-only guard'
);

create temporary table shadow_approval_deny_result as
select * from lws_internal.evaluate_security_action_orchestration_v1(
  'confirm_payment',
  'f7100000-0000-4000-8000-000000000002',
  repeat('c', 64),
  null,
  null,
  null
);
select ok(
  (select mode = 'SHADOW' and not would_allow
    and final_reason_code = 'SECURITY_APPROVAL_BINDING_REQUIRED'
   from shadow_approval_deny_result),
  'SHADOW reports would_allow=false without becoming an execution blocker'
);
select is(
  (select approval_result ->> 'reason_code' from shadow_approval_deny_result),
  'SECURITY_APPROVAL_BINDING_REQUIRED',
  'missing approval failure is visible in the approval layer'
);

update lws_internal.security_kill_switch
set is_active = true,
    reason = 'Synthetic shadow policy test',
    activated_at = clock_timestamp(),
    activated_by = 'f7000000-0000-4000-8000-000000000001',
    released_at = null,
    released_by = null
where scope = 'FINANCE_FINALIZATION';
create temporary table shadow_policy_deny_result as
select * from lws_internal.evaluate_security_action_orchestration_v1(
  'confirm_payment',
  'f7100000-0000-4000-8000-000000000001',
  repeat('a', 64),
  'f7200000-0000-4000-8000-000000000001',
  repeat('b', 64),
  null
);
select is(
  (select policy_result ->> 'reason_code' from shadow_policy_deny_result),
  'DOMAIN_KILL_SWITCH_ACTIVE',
  'kill-switch failure is visible in would_allow evaluation'
);
select ok(not (select would_allow from shadow_policy_deny_result), 'active kill switch makes would_allow false');
update lws_internal.security_kill_switch
set is_active = false,
    reason = 'Synthetic shadow policy test released',
    released_at = clock_timestamp(),
    released_by = 'f7000000-0000-4000-8000-000000000001'
where scope = 'FINANCE_FINALIZATION';

update lws_internal.security_action_policy
set max_per_hour = 1, max_per_day = 3, cooldown_seconds = 0
where action_code = 'confirm_payment';
insert into lws_internal.security_action_velocity(
  actor_auth_user_id, action_code, domain, object_reference_fingerprint,
  idempotency_fingerprint, consumed_at
) values (
  'f7000000-0000-4000-8000-000000000001',
  'confirm_payment', 'FINANCE_FINALIZATION', repeat('a', 64),
  repeat('d', 64), clock_timestamp()
);
create temporary table shadow_velocity_deny_result as
select * from lws_internal.evaluate_security_action_orchestration_v1(
  'confirm_payment',
  'f7100000-0000-4000-8000-000000000001',
  repeat('a', 64),
  'f7200000-0000-4000-8000-000000000001',
  repeat('b', 64),
  null
);
select is(
  (select velocity_result ->> 'reason_code' from shadow_velocity_deny_result),
  'SECURITY_VELOCITY_HOUR_LIMIT_REACHED',
  'velocity failure is visible in would_allow evaluation'
);
select is(
  (select count(*)::integer from lws_internal.security_action_velocity
   where actor_auth_user_id = 'f7000000-0000-4000-8000-000000000001'
     and action_code = 'confirm_payment'),
  1,
  'velocity-denied SHADOW run does not increase the ledger'
);
select ok(
  not (select is_active from lws_internal.security_kill_switch where scope = 'FINANCE_FINALIZATION'),
  'velocity-denied SHADOW run does not activate the circuit breaker'
);

create temporary table shadow_recovery_deny_result as
select * from lws_internal.evaluate_security_action_orchestration_v1(
  'purge_dossier_v1',
  null,
  repeat('e', 64),
  null,
  null,
  null
);
select is(
  (select recovery_result ->> 'reason_code' from shadow_recovery_deny_result),
  'SECURITY_DESTRUCTIVE_BINDING_INVALID',
  'recovery/pre-execution failure is visible in SHADOW'
);

set local session_replication_role = replica;
insert into lws_internal.operator_dossier_states(
  quote_request_id, state, revision, state_before_trash,
  deletion_eligible_at, created_at, updated_at
) values (
  'f7300000-0000-4000-8000-000000000001', 'TRASHED', 1, 'ACTIVE', null,
  clock_timestamp() - interval '40 days', clock_timestamp() - interval '31 days'
);
insert into lws_internal.operator_dossier_state_events(
  quote_request_id, event_type, previous_state, new_state, state_before_trash,
  previous_revision, new_revision, deletion_eligible_at, actor_operator_id,
  reason, occurred_at, idempotency_key, request_fingerprint
) values (
  'f7300000-0000-4000-8000-000000000001', 'TRASHED', 'ACTIVE', 'TRASHED', 'ACTIVE',
  0, 1, null, 'f7010000-0000-4000-8000-000000000001',
  'Synthetic elapsed shadow trash', clock_timestamp() - interval '31 days',
  'f7310000-0000-4000-8000-000000000001', repeat('f', 64)
);
set local session_replication_role = origin;

insert into lws_internal.security_recovery_records (
  recovery_record_id, action_code, recovery_class, object_reference,
  object_reference_fingerprint, actor_auth_user_id, recovery_state
) values (
  'f7400000-0000-4000-8000-000000000001',
  'purge_dossier_v1', 'IRREVERSIBLE', 'f7300000-0000-4000-8000-000000000001',
  repeat('1', 64), 'f7000000-0000-4000-8000-000000000001', 'IRREVERSIBLE_RECORDED'
);
insert into lws_internal.security_action_approvals (
  id, action_code, domain, object_reference_fingerprint,
  requested_by, requested_at, request_fingerprint, expires_at,
  status, approved_by, approved_at
) values (
  'f7500000-0000-4000-8000-000000000001',
  'purge_dossier_v1', 'PURGE', repeat('1', 64),
  'f7000000-0000-4000-8000-000000000001', clock_timestamp(), repeat('2', 64),
  clock_timestamp() + interval '15 minutes', 'APPROVED',
  'f7000000-0000-4000-8000-000000000002', clock_timestamp()
);

create temporary table shadow_purge_result as
select * from lws_internal.evaluate_security_action_orchestration_v1(
  'purge_dossier_v1',
  'f7300000-0000-4000-8000-000000000001',
  repeat('1', 64),
  'f7500000-0000-4000-8000-000000000001',
  repeat('2', 64),
  'f7400000-0000-4000-8000-000000000001'
);
select ok(
  (select not would_allow
    and final_reason_code = 'BACKUP_EVIDENCE_UNAVAILABLE'
    and (recovery_result ->> 'retention_satisfied')::boolean
    and (recovery_result ->> 'trash_first_satisfied')::boolean
    and not (recovery_result ->> 'backup_dependency_satisfied')::boolean
   from shadow_purge_result),
  'elapsed purge remains would_allow=false solely without authoritative backup evidence'
);
select is(
  (select status from lws_internal.security_action_approvals where id = 'f7500000-0000-4000-8000-000000000001'),
  'APPROVED',
  'purge SHADOW does not consume its approval'
);
select is(
  (select recovery_state from lws_internal.security_recovery_records
   where recovery_record_id = 'f7400000-0000-4000-8000-000000000001'),
  'IRREVERSIBLE_RECORDED',
  'purge SHADOW does not consume its recovery record'
);
select is(
  (select state from lws_internal.operator_dossier_states
   where quote_request_id = 'f7300000-0000-4000-8000-000000000001'),
  'TRASHED',
  'purge SHADOW does not mutate business lifecycle state'
);

create temporary table shadow_event_count_before_enforce as
select count(*)::integer as event_count
from lws_internal.security_control_events
where event_type = 'SHADOW_EVALUATED' and action_code = 'confirm_payment';

update lws_internal.security_action_enforcement_mode
set mode = 'ENFORCE', updated_at = clock_timestamp()
where action_code = 'confirm_payment';
create temporary table enforce_deny_result as
select * from lws_internal.evaluate_security_action_orchestration_v1(
  'confirm_payment',
  'f7100000-0000-4000-8000-000000000002',
  repeat('c', 64),
  null,
  null,
  null
);
select ok(
  (select mode = 'ENFORCE' and not would_allow
    and final_reason_code = 'SECURITY_APPROVAL_BINDING_REQUIRED'
   from enforce_deny_result),
  'ENFORCE semantics fail closed when required security state is missing'
);
select is(
  (select count(*)::integer from lws_internal.security_control_events
   where event_type = 'SHADOW_EVALUATED' and action_code = 'confirm_payment'),
  (select event_count from shadow_event_count_before_enforce),
  'ENFORCE evaluation is distinguishable and does not emit a shadow event'
);

select pg_temp.set_shadow_claims_v1(
  'f7000000-0000-4000-8000-000000000001',
  'service_role',
  'aal2'
);
select throws_ok(
  $$select * from lws_internal.evaluate_security_action_orchestration_v1(
    'confirm_payment', null, repeat('a', 64), null, null, null
  )$$,
  '42501',
  'HUMAN_JWT_REQUIRED',
  'service-role claims cannot spoof an operator actor even with a subject'
);
select pg_temp.set_shadow_claims_v1('f7000000-0000-4000-8000-000000000003');
select throws_ok(
  $$select * from lws_internal.evaluate_security_action_orchestration_v1(
    'confirm_payment', null, repeat('a', 64), null, null, null
  )$$,
  '42501',
  'OPERATOR_DISABLED',
  'disabled operator cannot evaluate orchestration'
);

select ok(
  not has_function_privilege('public', 'lws_internal.evaluate_security_action_orchestration_v1(text,uuid,text,uuid,text,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'lws_internal.evaluate_security_action_orchestration_v1(text,uuid,text,uuid,text,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'lws_internal.evaluate_security_action_orchestration_v1(text,uuid,text,uuid,text,uuid)', 'EXECUTE'),
  'PUBLIC, anon, and authenticated have no privileged orchestration execute grant'
);
select ok(
  (select proconfig @> array['search_path=lws_internal, public, auth, pg_catalog']
   from pg_proc
   where oid = 'lws_internal.evaluate_security_action_orchestration_v1(text,uuid,text,uuid,text,uuid)'::regprocedure),
  'orchestration evaluator has a fixed trusted search_path'
);
select ok(
  (select provolatile = 'v' and prosecdef
   from pg_proc
   where oid = 'lws_internal.evaluate_security_action_orchestration_v1(text,uuid,text,uuid,text,uuid)'::regprocedure),
  'orchestration is volatile only for append-only shadow auditing and is SECURITY DEFINER'
);
select ok(
  (select pg_get_functiondef(
      'lws_internal.evaluate_security_action_orchestration_v1(text,uuid,text,uuid,text,uuid)'::regprocedure
    ) not ilike all(array[
      '%claim_security_action_execution_v1%',
      '%consume_security_action_velocity_v1%',
      '%record_security_recovery_v1%',
      '%request_security_restore_v1%',
      '%approve_security_restore_v1%',
      '%record_security_compensating_event_v1%'
    ])),
  'SHADOW orchestration cannot call any approval, velocity, or recovery consumer'
);
select ok(
  not exists (
    select 1
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname <> 'lws_internal'
      and procedure.prokind = 'f'
      and pg_get_functiondef(procedure.oid) ilike '%evaluate_security_action_orchestration_v1%'
  ),
  'no existing public or production database handler calls orchestration'
);

select * from finish();
rollback;