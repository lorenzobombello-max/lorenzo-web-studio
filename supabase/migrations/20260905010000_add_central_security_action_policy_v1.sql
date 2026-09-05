create table lws_internal.security_action_policy (
  action_code text primary key,
  domain text not null,
  risk_level text not null check (risk_level in ('READ_ONLY', 'HIGH', 'CRITICAL')),
  enabled boolean not null default true,
  requires_aal2 boolean not null default false,
  requires_dual_control boolean not null default false,
  max_per_hour integer check (max_per_hour is null or max_per_hour > 0),
  max_per_day integer check (max_per_day is null or max_per_day > 0),
  cooldown_seconds integer check (cooldown_seconds is null or cooldown_seconds >= 0),
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid references auth.users(id),
  constraint security_action_policy_action_code_shape
    check (action_code ~ '^[a-z][a-z0-9_]{2,119}$'),
  constraint security_action_policy_domain_shape
    check (domain ~ '^[A-Z][A-Z0-9_]{1,79}$'),
  constraint security_action_policy_velocity_shape
    check (max_per_hour is null or max_per_day is null or max_per_hour <= max_per_day),
  constraint security_action_policy_read_only_shape
    check (
      risk_level <> 'READ_ONLY'
      or (
        enabled
        and not requires_aal2
        and not requires_dual_control
        and max_per_hour is null
        and max_per_day is null
        and cooldown_seconds is null
      )
    )
);

create table lws_internal.security_kill_switch (
  scope text primary key check (scope in (
    'GLOBAL',
    'PURGE',
    'FINANCE_FINALIZATION',
    'IDENTITY_PRIVILEGE',
    'RECRUITMENT',
    'DOCUMENT_DISPOSITION',
    'SENSITIVE_EXPORT'
  )),
  is_active boolean not null default false,
  reason text,
  activated_at timestamptz,
  activated_by uuid references auth.users(id),
  released_at timestamptz,
  released_by uuid references auth.users(id),
  constraint security_kill_switch_state_shape check (
    (
      is_active
      and reason is not null
      and char_length(btrim(reason)) between 1 and 500
      and activated_at is not null
      and activated_by is not null
      and released_at is null
      and released_by is null
    )
    or (
      not is_active
      and (
        (activated_at is null and activated_by is null and released_at is null and released_by is null and reason is null)
        or
        (activated_at is not null and activated_by is not null and released_at is not null and released_by is not null
          and reason is not null and char_length(btrim(reason)) between 1 and 500)
      )
    )
  )
);

create table lws_internal.security_control_events (
  event_id bigint generated always as identity primary key,
  actor_auth_user_id uuid references auth.users(id),
  event_type text not null check (event_type in (
    'POLICY_BOOTSTRAPPED',
    'POLICY_CHANGED',
    'SWITCH_ACTIVATED',
    'SWITCH_RELEASED',
    'APPROVAL_REQUESTED',
    'APPROVAL_GRANTED',
    'APPROVAL_REJECTED',
    'VELOCITY_BLOCKED',
    'VELOCITY_RELEASED'
  )),
  domain text,
  action_code text,
  object_reference_fingerprint text check (
    object_reference_fingerprint is null
    or object_reference_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  occurred_at timestamptz not null default clock_timestamp(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object')
);

revoke all privileges on table
  lws_internal.security_action_policy,
  lws_internal.security_kill_switch,
  lws_internal.security_control_events
from public, anon, authenticated, service_role;
revoke all privileges on sequence lws_internal.security_control_events_event_id_seq
from public, anon, authenticated, service_role;

create function lws_internal.guard_security_control_event_append_only_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'SECURITY_CONTROL_EVENT_APPEND_ONLY';
end;
$$;

revoke all on function lws_internal.guard_security_control_event_append_only_v1()
from public, anon, authenticated, service_role;

create trigger trg_security_control_events_append_only
before update or delete on lws_internal.security_control_events
for each row execute function lws_internal.guard_security_control_event_append_only_v1();

create function lws_internal.assert_security_control_owner_aal2_v1()
returns uuid
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_aal text := coalesce(auth.jwt() ->> 'aal', '');
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  if v_aal <> 'aal2' then
    raise exception using errcode = '42501', message = 'AAL2_REQUIRED';
  end if;
  if not exists (
    select 1
    from public.commercial_operators as operator
    where operator.auth_user_id = v_subject
      and operator.status = 'ACTIVE'
      and operator.role = 'owner'
  ) then
    raise exception using errcode = '42501', message = 'SECURITY_CONTROL_OWNER_REQUIRED';
  end if;
  return v_subject;
end;
$$;

revoke all on function lws_internal.assert_security_control_owner_aal2_v1()
from public, anon, authenticated, service_role;

create function lws_internal.evaluate_security_action_v1(p_action_code text)
returns table (
  allowed boolean,
  reason_code text,
  action_code text,
  domain text,
  risk_level text,
  requires_aal2 boolean,
  requires_dual_control boolean,
  max_per_hour integer,
  max_per_day integer,
  cooldown_seconds integer
)
language plpgsql
stable
security definer
set search_path = lws_internal, pg_catalog
as $$
declare
  v_policy lws_internal.security_action_policy%rowtype;
  v_global_active boolean;
  v_domain_active boolean;
begin
  select * into v_policy
  from lws_internal.security_action_policy as policy
  where policy.action_code = btrim(p_action_code);

  if not found then
    return query select false, 'SECURITY_ACTION_NOT_REGISTERED', btrim(p_action_code), null::text,
      null::text, false, false, null::integer, null::integer, null::integer;
    return;
  end if;

  if not v_policy.enabled then
    return query select false, 'SECURITY_ACTION_DISABLED', v_policy.action_code, v_policy.domain,
      v_policy.risk_level, v_policy.requires_aal2, v_policy.requires_dual_control,
      v_policy.max_per_hour, v_policy.max_per_day, v_policy.cooldown_seconds;
    return;
  end if;

  if v_policy.risk_level = 'READ_ONLY' then
    return query select true, 'READ_ONLY_ACTION', v_policy.action_code, v_policy.domain,
      v_policy.risk_level, false, false, null::integer, null::integer, null::integer;
    return;
  end if;

  select switch.is_active into v_global_active
  from lws_internal.security_kill_switch as switch
  where switch.scope = 'GLOBAL';
  if not found then
    return query select false, 'SECURITY_SWITCH_CONFIGURATION_MISSING', v_policy.action_code, v_policy.domain,
      v_policy.risk_level, v_policy.requires_aal2, v_policy.requires_dual_control,
      v_policy.max_per_hour, v_policy.max_per_day, v_policy.cooldown_seconds;
    return;
  end if;

  select coalesce((
    select switch.is_active
    from lws_internal.security_kill_switch as switch
    where switch.scope = v_policy.domain
  ), false) into v_domain_active;

  return query select
    not (v_global_active or v_domain_active),
    case
      when v_global_active then 'GLOBAL_KILL_SWITCH_ACTIVE'
      when v_domain_active then 'DOMAIN_KILL_SWITCH_ACTIVE'
      else 'SECURITY_ACTION_ALLOWED'
    end,
    v_policy.action_code,
    v_policy.domain,
    v_policy.risk_level,
    v_policy.requires_aal2,
    v_policy.requires_dual_control,
    v_policy.max_per_hour,
    v_policy.max_per_day,
    v_policy.cooldown_seconds;
end;
$$;

revoke all on function lws_internal.evaluate_security_action_v1(text)
from public, anon, authenticated, service_role;
grant execute on function lws_internal.evaluate_security_action_v1(text) to service_role;

create function public.set_security_kill_switch_v1(
  p_scope text,
  p_active boolean,
  p_reason text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_actor uuid := lws_internal.assert_security_control_owner_aal2_v1();
  v_scope text := upper(btrim(coalesce(p_scope, '')));
  v_reason text := btrim(coalesce(p_reason, ''));
  v_previous boolean;
  v_now timestamptz := clock_timestamp();
begin
  if v_scope not in (
    'GLOBAL', 'PURGE', 'FINANCE_FINALIZATION', 'IDENTITY_PRIVILEGE',
    'RECRUITMENT', 'DOCUMENT_DISPOSITION', 'SENSITIVE_EXPORT'
  ) or char_length(v_reason) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'INVALID_SECURITY_KILL_SWITCH_REQUEST';
  end if;

  select is_active into strict v_previous
  from lws_internal.security_kill_switch
  where scope = v_scope
  for update;

  update lws_internal.security_kill_switch
  set is_active = p_active,
      reason = v_reason,
      activated_at = case when p_active then v_now else activated_at end,
      activated_by = case when p_active then v_actor else activated_by end,
      released_at = case when p_active then null else v_now end,
      released_by = case when p_active then null else v_actor end
  where scope = v_scope;

  insert into lws_internal.security_control_events (
    actor_auth_user_id, event_type, domain, metadata
  ) values (
    v_actor,
    case when p_active then 'SWITCH_ACTIVATED' else 'SWITCH_RELEASED' end,
    v_scope,
    jsonb_build_object('previous_active', v_previous, 'active', p_active)
  );

  return jsonb_build_object('scope', v_scope, 'active', p_active, 'changed', v_previous is distinct from p_active);
end;
$$;

create function public.upsert_security_action_policy_v1(
  p_action_code text,
  p_domain text,
  p_risk_level text,
  p_enabled boolean,
  p_requires_aal2 boolean,
  p_requires_dual_control boolean,
  p_max_per_hour integer default null,
  p_max_per_day integer default null,
  p_cooldown_seconds integer default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_actor uuid := lws_internal.assert_security_control_owner_aal2_v1();
  v_action_code text := lower(btrim(coalesce(p_action_code, '')));
  v_domain text := upper(btrim(coalesce(p_domain, '')));
  v_risk_level text := upper(btrim(coalesce(p_risk_level, '')));
begin
  insert into lws_internal.security_action_policy (
    action_code, domain, risk_level, enabled, requires_aal2,
    requires_dual_control, max_per_hour, max_per_day, cooldown_seconds,
    updated_at, updated_by
  ) values (
    v_action_code, v_domain, v_risk_level, p_enabled, p_requires_aal2,
    p_requires_dual_control, p_max_per_hour, p_max_per_day,
    p_cooldown_seconds, clock_timestamp(), v_actor
  )
  on conflict (action_code) do update set
    domain = excluded.domain,
    risk_level = excluded.risk_level,
    enabled = excluded.enabled,
    requires_aal2 = excluded.requires_aal2,
    requires_dual_control = excluded.requires_dual_control,
    max_per_hour = excluded.max_per_hour,
    max_per_day = excluded.max_per_day,
    cooldown_seconds = excluded.cooldown_seconds,
    updated_at = excluded.updated_at,
    updated_by = excluded.updated_by;

  insert into lws_internal.security_control_events (
    actor_auth_user_id, event_type, domain, action_code, metadata
  ) values (
    v_actor,
    'POLICY_CHANGED',
    v_domain,
    v_action_code,
    jsonb_build_object(
      'risk_level', v_risk_level,
      'enabled', p_enabled,
      'requires_aal2', p_requires_aal2,
      'requires_dual_control', p_requires_dual_control,
      'max_per_hour', p_max_per_hour,
      'max_per_day', p_max_per_day,
      'cooldown_seconds', p_cooldown_seconds
    )
  );

  return jsonb_build_object('action_code', v_action_code, 'domain', v_domain, 'updated', true);
end;
$$;

revoke all on function public.set_security_kill_switch_v1(text, boolean, text)
from public, anon, service_role;
revoke all on function public.upsert_security_action_policy_v1(text, text, text, boolean, boolean, boolean, integer, integer, integer)
from public, anon, service_role;
grant execute on function public.set_security_kill_switch_v1(text, boolean, text) to authenticated;
grant execute on function public.upsert_security_action_policy_v1(text, text, text, boolean, boolean, boolean, integer, integer, integer) to authenticated;

insert into lws_internal.security_kill_switch(scope)
values
  ('GLOBAL'),
  ('PURGE'),
  ('FINANCE_FINALIZATION'),
  ('IDENTITY_PRIVILEGE'),
  ('RECRUITMENT'),
  ('DOCUMENT_DISPOSITION'),
  ('SENSITIVE_EXPORT');

insert into lws_internal.security_action_policy (
  action_code, domain, risk_level, enabled, requires_aal2,
  requires_dual_control, max_per_hour, max_per_day, cooldown_seconds
)
values
  ('purge_dossier_v1', 'PURGE', 'CRITICAL', true, true, true, 1, 3, 900),
  ('purge_sdf_dossier_v1', 'PURGE', 'CRITICAL', true, true, true, 1, 3, 900),
  ('permanently_delete_pending_intake', 'PURGE', 'CRITICAL', true, true, true, 1, 3, 900),
  ('appoint_operations_manager_v1', 'IDENTITY_PRIVILEGE', 'CRITICAL', true, true, true, 1, 2, 600),
  ('revoke_operations_manager_v1', 'IDENTITY_PRIVILEGE', 'HIGH', true, true, false, 2, 5, 60),
  ('set_commercial_operator_status_v1', 'IDENTITY_PRIVILEGE', 'CRITICAL', true, true, true, 1, 3, 600),
  ('revoke_operator_workspace_v1', 'IDENTITY_PRIVILEGE', 'HIGH', true, true, false, 10, 30, 0),
  ('record_payment_evidence', 'FINANCE_FINALIZATION', 'HIGH', true, true, false, 10, 30, 0),
  ('reconcile_payment', 'FINANCE_FINALIZATION', 'HIGH', true, true, false, 10, 30, 0),
  ('confirm_payment', 'FINANCE_FINALIZATION', 'CRITICAL', true, true, true, 3, 10, 60),
  ('release_project', 'FINANCE_FINALIZATION', 'CRITICAL', true, true, true, 3, 10, 60),
  ('authorize_final_transfer', 'FINANCE_FINALIZATION', 'CRITICAL', true, true, true, 3, 10, 60),
  ('record_delivery', 'FINANCE_FINALIZATION', 'HIGH', true, true, false, 10, 30, 0),
  ('archive_project', 'FINANCE_FINALIZATION', 'HIGH', true, true, false, 10, 30, 0),
  ('issue_and_deliver_approved_quotation', 'FINANCE_FINALIZATION', 'CRITICAL', true, true, true, 3, 10, 60),
  ('cancel_intake', 'DOCUMENT_DISPOSITION', 'HIGH', true, true, false, 10, 30, 0),
  ('approve_document_inbox_item_v1', 'DOCUMENT_DISPOSITION', 'HIGH', true, true, false, 10, 50, 0),
  ('reject_document_inbox_item_v1', 'DOCUMENT_DISPOSITION', 'HIGH', true, true, false, 10, 50, 0),
  ('process_document_inbox_item_v1', 'DOCUMENT_DISPOSITION', 'HIGH', true, true, false, 10, 50, 0),
  ('invite_recruitment_test_candidate', 'RECRUITMENT', 'HIGH', true, true, false, 10, 50, 0),
  ('reject_recruitment_open_application', 'RECRUITMENT', 'HIGH', true, true, false, 10, 50, 0),
  ('decide_operator_leave_request_v1', 'WORKFORCE', 'HIGH', true, true, false, 10, 30, 0),
  ('create_dossier_document_access', 'SENSITIVE_EXPORT', 'HIGH', true, true, false, 20, 50, 0),
  ('create_recruitment_cv_access', 'SENSITIVE_EXPORT', 'HIGH', true, true, false, 20, 50, 0),
  ('export_application_dossier_pdf', 'SENSITIVE_EXPORT', 'HIGH', true, true, false, 20, 50, 0);

insert into lws_internal.security_control_events (
  event_type, domain, action_code, metadata
)
select
  'POLICY_BOOTSTRAPPED',
  policy.domain,
  policy.action_code,
  jsonb_build_object('risk_level', policy.risk_level)
from lws_internal.security_action_policy as policy;

comment on table lws_internal.security_kill_switch is
  'ACTIVE means registered HIGH or CRITICAL mutations in the matching scope must be blocked once enforcement is wired.';
comment on function lws_internal.evaluate_security_action_v1(text) is
  'Private fail-closed policy evaluation contract. P0-3A does not call it from any existing business action.';
comment on function public.set_security_kill_switch_v1(text, boolean, text) is
  'Owner-only AAL2 control-plane mutation; it does not wire or execute a business mutation.';
