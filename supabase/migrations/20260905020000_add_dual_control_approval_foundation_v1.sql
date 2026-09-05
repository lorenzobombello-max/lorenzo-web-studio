do $$
declare
  v_legacy_exists boolean;
  v_canonical_exists boolean;
begin
  lock table lws_internal.security_action_policy in share row exclusive mode;

  select exists (
    select 1 from lws_internal.security_action_policy
    where action_code = 'permanently_delete_pending_intake'
  ), exists (
    select 1 from lws_internal.security_action_policy
    where action_code = 'permanently_delete_pending_intake_v1'
  ) into v_legacy_exists, v_canonical_exists;

  if v_legacy_exists and not v_canonical_exists then
    update lws_internal.security_action_policy
    set action_code = 'permanently_delete_pending_intake_v1'
    where action_code = 'permanently_delete_pending_intake';
  elsif not v_legacy_exists and v_canonical_exists then
    null;
  elsif v_legacy_exists and v_canonical_exists then
    raise exception using errcode = 'P0001', message = 'PENDING_INTAKE_DELETE_ACTION_CODE_CONFLICT';
  else
    raise exception using errcode = 'P0001', message = 'PENDING_INTAKE_DELETE_ACTION_CODE_MISSING';
  end if;

  if (select count(*) from lws_internal.security_action_policy
      where action_code = 'permanently_delete_pending_intake') <> 0
    or (select count(*) from lws_internal.security_action_policy
        where action_code = 'permanently_delete_pending_intake_v1') <> 1 then
    raise exception using errcode = 'P0001', message = 'PENDING_INTAKE_DELETE_ACTION_CODE_CANONICALIZATION_FAILED';
  end if;
end;
$$;

update lws_internal.security_action_policy
set requires_dual_control = action_code in (
  'purge_dossier_v1',
  'purge_sdf_dossier_v1',
  'permanently_delete_pending_intake_v1',
  'appoint_operations_manager_v1',
  'set_commercial_operator_status_v1',
  'confirm_payment',
  'release_project',
  'authorize_final_transfer',
  'issue_and_deliver_approved_quotation'
),
updated_at = clock_timestamp();

create table lws_internal.security_action_approvals (
  id uuid primary key default gen_random_uuid(),
  action_code text not null references lws_internal.security_action_policy(action_code),
  domain text not null,
  object_reference_fingerprint char(64) not null
    check (object_reference_fingerprint ~ '^[0-9a-f]{64}$'),
  requested_by uuid not null references auth.users(id),
  requested_at timestamptz not null default clock_timestamp(),
  request_fingerprint char(64) not null unique
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null,
  status text not null default 'PENDING'
    check (status in ('PENDING', 'APPROVED', 'REJECTED', 'EXPIRED', 'CANCELLED', 'EXECUTED')),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  rejected_by uuid references auth.users(id),
  rejected_at timestamptz,
  rejection_reason text,
  executed_at timestamptz,
  safe_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  constraint security_action_approvals_expiry_shape
    check (expires_at > requested_at),
  constraint security_action_approvals_safe_metadata_shape
    check (
      jsonb_typeof(safe_metadata) = 'object'
      and pg_column_size(safe_metadata) <= 2048
      and safe_metadata - array['correlation_id', 'reason_code', 'source']::text[] = '{}'::jsonb
      and (safe_metadata -> 'correlation_id' is null or jsonb_typeof(safe_metadata -> 'correlation_id') = 'string')
      and (safe_metadata -> 'reason_code' is null or jsonb_typeof(safe_metadata -> 'reason_code') = 'string')
      and (safe_metadata -> 'source' is null or jsonb_typeof(safe_metadata -> 'source') = 'string')
    ),
  constraint security_action_approvals_actor_separation
    check (
      (approved_by is null or requested_by <> approved_by)
      and (rejected_by is null or requested_by <> rejected_by)
    ),
  constraint security_action_approvals_state_shape
    check (
      (status in ('PENDING', 'EXPIRED', 'CANCELLED')
        and approved_by is null and approved_at is null
        and rejected_by is null and rejected_at is null and rejection_reason is null
        and executed_at is null)
      or
      (status = 'APPROVED'
        and approved_by is not null and approved_at is not null
        and rejected_by is null and rejected_at is null and rejection_reason is null
        and executed_at is null)
      or
      (status = 'REJECTED'
        and approved_by is null and approved_at is null
        and rejected_by is not null and rejected_at is not null
        and char_length(btrim(rejection_reason)) between 1 and 500
        and executed_at is null)
      or
      (status = 'EXECUTED'
        and approved_by is not null and approved_at is not null
        and rejected_by is null and rejected_at is null and rejection_reason is null
        and executed_at is not null)
    )
);

create index security_action_approvals_pending_idx
  on lws_internal.security_action_approvals(action_code, object_reference_fingerprint, expires_at)
  where status = 'PENDING';

revoke all privileges on table lws_internal.security_action_approvals
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
    'VELOCITY_BLOCKED',
    'VELOCITY_RELEASED'
  ));

create function lws_internal.guard_security_action_approval_transition_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'SECURITY_ACTION_APPROVAL_DELETE_FORBIDDEN';
  end if;
  if new.id <> old.id
    or new.action_code <> old.action_code
    or new.domain <> old.domain
    or new.object_reference_fingerprint <> old.object_reference_fingerprint
    or new.requested_by <> old.requested_by
    or new.requested_at <> old.requested_at
    or new.request_fingerprint <> old.request_fingerprint
    or new.expires_at <> old.expires_at
    or new.safe_metadata <> old.safe_metadata
    or new.created_at <> old.created_at then
    raise exception using errcode = '55000', message = 'SECURITY_ACTION_APPROVAL_BINDING_IMMUTABLE';
  end if;
  if old.status = 'PENDING' and new.status in ('APPROVED', 'REJECTED', 'EXPIRED', 'CANCELLED') then
    return new;
  end if;
  if old.status = 'APPROVED' and new.status = 'EXECUTED' then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'SECURITY_ACTION_APPROVAL_TRANSITION_FORBIDDEN';
end;
$$;

revoke all on function lws_internal.guard_security_action_approval_transition_v1()
from public, anon, authenticated, service_role;

create trigger trg_security_action_approval_transition
before update or delete on lws_internal.security_action_approvals
for each row execute function lws_internal.guard_security_action_approval_transition_v1();

create function lws_internal.assert_security_approval_actor_aal2_v1()
returns uuid
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception using errcode = '42501', message = 'AAL2_REQUIRED';
  end if;
  if not exists (
    select 1
    from public.commercial_operators as operator
    where operator.auth_user_id = v_actor
      and operator.status = 'ACTIVE'
      and operator.role in ('owner', 'operations_manager')
  ) then
    raise exception using errcode = '42501', message = 'SECURITY_APPROVAL_AUTHORITY_REQUIRED';
  end if;
  return v_actor;
end;
$$;

revoke all on function lws_internal.assert_security_approval_actor_aal2_v1()
from public, anon, authenticated, service_role;

create function public.request_security_action_approval_v1(
  p_action_code text,
  p_object_reference_fingerprint text,
  p_ttl_seconds integer default 900,
  p_safe_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_actor uuid := lws_internal.assert_security_approval_actor_aal2_v1();
  v_policy lws_internal.security_action_policy%rowtype;
  v_approval_id uuid := gen_random_uuid();
  v_requested_at timestamptz := clock_timestamp();
  v_request_fingerprint text;
begin
  if p_action_code is null or p_action_code !~ '^[a-z][a-z0-9_]{2,119}$' then
    raise exception using errcode = '22023', message = 'INVALID_SECURITY_ACTION_CODE';
  end if;
  if p_object_reference_fingerprint is null
    or p_object_reference_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_OBJECT_REFERENCE_FINGERPRINT';
  end if;
  if p_ttl_seconds is null or p_ttl_seconds < 30 or p_ttl_seconds > 3600 then
    raise exception using errcode = '22023', message = 'INVALID_APPROVAL_TTL';
  end if;

  select * into v_policy
  from lws_internal.security_action_policy as policy
  where policy.action_code = p_action_code;
  if not found then
    raise exception using errcode = '22023', message = 'SECURITY_ACTION_NOT_REGISTERED';
  end if;
  if not v_policy.enabled or not v_policy.requires_dual_control then
    raise exception using errcode = '42501', message = 'DUAL_CONTROL_NOT_REQUIRED';
  end if;

  v_request_fingerprint := encode(extensions.digest(convert_to(concat_ws('|',
    'SECURITY_ACTION_APPROVAL_V1',
    v_approval_id::text,
    p_action_code,
    p_object_reference_fingerprint,
    v_actor::text,
    v_requested_at::text
  ), 'UTF8'), 'sha256'), 'hex');

  insert into lws_internal.security_action_approvals (
    id, action_code, domain, object_reference_fingerprint, requested_by,
    requested_at, request_fingerprint, expires_at, safe_metadata
  ) values (
    v_approval_id, v_policy.action_code, v_policy.domain, p_object_reference_fingerprint,
    v_actor, v_requested_at, v_request_fingerprint,
    v_requested_at + make_interval(secs => p_ttl_seconds), coalesce(p_safe_metadata, '{}'::jsonb)
  );

  insert into lws_internal.security_control_events (
    actor_auth_user_id, event_type, domain, action_code,
    object_reference_fingerprint, metadata
  ) values (
    v_actor, 'APPROVAL_REQUESTED', v_policy.domain, v_policy.action_code,
    p_object_reference_fingerprint,
    jsonb_build_object('approval_id', v_approval_id, 'request_fingerprint', v_request_fingerprint)
  );

  return jsonb_build_object(
    'approval_id', v_approval_id,
    'action_code', v_policy.action_code,
    'approval_status', 'PENDING',
    'request_fingerprint', v_request_fingerprint,
    'expires_at', v_requested_at + make_interval(secs => p_ttl_seconds)
  );
end;
$$;

create function public.approve_security_action_v1(
  p_approval_id uuid,
  p_action_code text,
  p_object_reference_fingerprint text,
  p_request_fingerprint text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_actor uuid := lws_internal.assert_security_approval_actor_aal2_v1();
  v_approval lws_internal.security_action_approvals%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  select * into v_approval
  from lws_internal.security_action_approvals
  where id = p_approval_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'SECURITY_APPROVAL_NOT_FOUND';
  end if;
  if v_approval.action_code <> p_action_code then
    raise exception using errcode = '22023', message = 'SECURITY_APPROVAL_ACTION_MISMATCH';
  end if;
  if v_approval.object_reference_fingerprint <> p_object_reference_fingerprint then
    raise exception using errcode = '22023', message = 'SECURITY_APPROVAL_OBJECT_MISMATCH';
  end if;
  if v_approval.request_fingerprint <> p_request_fingerprint then
    raise exception using errcode = '22023', message = 'SECURITY_APPROVAL_FINGERPRINT_MISMATCH';
  end if;
  if v_approval.requested_by = v_actor then
    raise exception using errcode = '42501', message = 'SECURITY_APPROVAL_SELF_APPROVAL_FORBIDDEN';
  end if;
  if v_approval.status <> 'PENDING' then
    raise exception using errcode = '55000', message = 'SECURITY_APPROVAL_NOT_PENDING';
  end if;
  if v_approval.expires_at <= v_now then
    raise exception using errcode = '55000', message = 'SECURITY_APPROVAL_EXPIRED';
  end if;

  update lws_internal.security_action_approvals
  set status = 'APPROVED', approved_by = v_actor, approved_at = v_now
  where id = p_approval_id;

  insert into lws_internal.security_control_events (
    actor_auth_user_id, event_type, domain, action_code,
    object_reference_fingerprint, metadata
  ) values (
    v_actor, 'APPROVAL_GRANTED', v_approval.domain, v_approval.action_code,
    v_approval.object_reference_fingerprint,
    jsonb_build_object('approval_id', v_approval.id, 'request_fingerprint', v_approval.request_fingerprint)
  );

  return jsonb_build_object('approval_id', v_approval.id, 'approval_status', 'APPROVED');
end;
$$;

create function public.reject_security_action_v1(
  p_approval_id uuid,
  p_action_code text,
  p_object_reference_fingerprint text,
  p_request_fingerprint text,
  p_reason text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_actor uuid := lws_internal.assert_security_approval_actor_aal2_v1();
  v_approval lws_internal.security_action_approvals%rowtype;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_now timestamptz := clock_timestamp();
begin
  if char_length(v_reason) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'SECURITY_APPROVAL_REJECTION_REASON_REQUIRED';
  end if;
  select * into v_approval
  from lws_internal.security_action_approvals
  where id = p_approval_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'SECURITY_APPROVAL_NOT_FOUND';
  end if;
  if v_approval.action_code <> p_action_code then
    raise exception using errcode = '22023', message = 'SECURITY_APPROVAL_ACTION_MISMATCH';
  end if;
  if v_approval.object_reference_fingerprint <> p_object_reference_fingerprint then
    raise exception using errcode = '22023', message = 'SECURITY_APPROVAL_OBJECT_MISMATCH';
  end if;
  if v_approval.request_fingerprint <> p_request_fingerprint then
    raise exception using errcode = '22023', message = 'SECURITY_APPROVAL_FINGERPRINT_MISMATCH';
  end if;
  if v_approval.requested_by = v_actor then
    raise exception using errcode = '42501', message = 'SECURITY_APPROVAL_SELF_APPROVAL_FORBIDDEN';
  end if;
  if v_approval.status <> 'PENDING' then
    raise exception using errcode = '55000', message = 'SECURITY_APPROVAL_NOT_PENDING';
  end if;
  if v_approval.expires_at <= v_now then
    raise exception using errcode = '55000', message = 'SECURITY_APPROVAL_EXPIRED';
  end if;

  update lws_internal.security_action_approvals
  set status = 'REJECTED', rejected_by = v_actor, rejected_at = v_now,
      rejection_reason = v_reason
  where id = p_approval_id;

  insert into lws_internal.security_control_events (
    actor_auth_user_id, event_type, domain, action_code,
    object_reference_fingerprint, metadata
  ) values (
    v_actor, 'APPROVAL_REJECTED', v_approval.domain, v_approval.action_code,
    v_approval.object_reference_fingerprint,
    jsonb_build_object('approval_id', v_approval.id, 'request_fingerprint', v_approval.request_fingerprint)
  );

  return jsonb_build_object('approval_id', v_approval.id, 'approval_status', 'REJECTED');
end;
$$;

create function lws_internal.evaluate_security_action_approval_v1(
  p_approval_id uuid,
  p_action_code text,
  p_object_reference_fingerprint text,
  p_request_fingerprint text
)
returns table (
  allowed boolean,
  approval_status text,
  reason_code text,
  approval_id uuid,
  request_fingerprint text
)
language plpgsql
stable
security definer
set search_path = lws_internal, pg_catalog
as $$
declare
  v_approval lws_internal.security_action_approvals%rowtype;
  v_policy record;
  v_effective_status text;
begin
  select * into v_approval
  from lws_internal.security_action_approvals
  where id = p_approval_id;
  if not found then
    return query select false, null::text, 'SECURITY_APPROVAL_NOT_FOUND', p_approval_id, null::text;
    return;
  end if;
  if v_approval.action_code <> p_action_code then
    return query select false, v_approval.status, 'SECURITY_APPROVAL_ACTION_MISMATCH', v_approval.id, v_approval.request_fingerprint::text;
    return;
  end if;
  if v_approval.object_reference_fingerprint <> p_object_reference_fingerprint then
    return query select false, v_approval.status, 'SECURITY_APPROVAL_OBJECT_MISMATCH', v_approval.id, v_approval.request_fingerprint::text;
    return;
  end if;
  if v_approval.request_fingerprint <> p_request_fingerprint then
    return query select false, v_approval.status, 'SECURITY_APPROVAL_FINGERPRINT_MISMATCH', v_approval.id, v_approval.request_fingerprint::text;
    return;
  end if;

  v_effective_status := case
    when v_approval.status in ('PENDING', 'APPROVED') and v_approval.expires_at <= clock_timestamp() then 'EXPIRED'
    else v_approval.status
  end;
  if v_effective_status <> 'APPROVED' then
    return query select false, v_effective_status, 'SECURITY_APPROVAL_' || v_effective_status, v_approval.id, v_approval.request_fingerprint::text;
    return;
  end if;

  select * into v_policy
  from lws_internal.evaluate_security_action_v1(v_approval.action_code);
  if not found or not v_policy.allowed or not v_policy.requires_dual_control then
    return query select false, v_effective_status,
      coalesce(v_policy.reason_code, 'SECURITY_ACTION_POLICY_DENIED'),
      v_approval.id, v_approval.request_fingerprint::text;
    return;
  end if;

  return query select true, v_effective_status, 'SECURITY_APPROVAL_ALLOWED',
    v_approval.id, v_approval.request_fingerprint::text;
end;
$$;

create function lws_internal.claim_security_action_execution_v1(
  p_approval_id uuid,
  p_action_code text,
  p_object_reference_fingerprint text,
  p_request_fingerprint text
)
returns table (
  allowed boolean,
  approval_status text,
  reason_code text,
  approval_id uuid,
  request_fingerprint text
)
language plpgsql
volatile
security definer
set search_path = lws_internal, pg_catalog
as $$
declare
  v_approval lws_internal.security_action_approvals%rowtype;
  v_claimed lws_internal.security_action_approvals%rowtype;
begin
  update lws_internal.security_action_approvals as approval
  set status = 'EXECUTED', executed_at = clock_timestamp()
  where approval.id = p_approval_id
    and approval.action_code = p_action_code
    and approval.object_reference_fingerprint = p_object_reference_fingerprint
    and approval.request_fingerprint = p_request_fingerprint
    and approval.status = 'APPROVED'
    and approval.expires_at > clock_timestamp()
  returning approval.* into v_claimed;

  if found then
    insert into lws_internal.security_control_events (
      event_type, domain, action_code, object_reference_fingerprint, metadata
    ) values (
      'APPROVAL_EXECUTED', v_claimed.domain, v_claimed.action_code,
      v_claimed.object_reference_fingerprint,
      jsonb_build_object('approval_id', v_claimed.id, 'request_fingerprint', v_claimed.request_fingerprint)
    );
    return query select true, 'EXECUTED', 'SECURITY_APPROVAL_EXECUTION_CLAIMED',
      v_claimed.id, v_claimed.request_fingerprint::text;
    return;
  end if;

  select * into v_approval
  from lws_internal.security_action_approvals
  where id = p_approval_id;
  if not found then
    return query select false, null::text, 'SECURITY_APPROVAL_NOT_FOUND', p_approval_id, null::text;
  elsif v_approval.action_code <> p_action_code then
    return query select false, v_approval.status, 'SECURITY_APPROVAL_ACTION_MISMATCH', v_approval.id, v_approval.request_fingerprint::text;
  elsif v_approval.object_reference_fingerprint <> p_object_reference_fingerprint then
    return query select false, v_approval.status, 'SECURITY_APPROVAL_OBJECT_MISMATCH', v_approval.id, v_approval.request_fingerprint::text;
  elsif v_approval.request_fingerprint <> p_request_fingerprint then
    return query select false, v_approval.status, 'SECURITY_APPROVAL_FINGERPRINT_MISMATCH', v_approval.id, v_approval.request_fingerprint::text;
  elsif v_approval.status = 'EXECUTED' then
    return query select false, 'EXECUTED', 'SECURITY_APPROVAL_ALREADY_EXECUTED', v_approval.id, v_approval.request_fingerprint::text;
  elsif v_approval.expires_at <= clock_timestamp() then
    return query select false, 'EXPIRED', 'SECURITY_APPROVAL_EXPIRED', v_approval.id, v_approval.request_fingerprint::text;
  else
    return query select false, v_approval.status, 'SECURITY_APPROVAL_' || v_approval.status, v_approval.id, v_approval.request_fingerprint::text;
  end if;
end;
$$;

revoke all on function public.request_security_action_approval_v1(text, text, integer, jsonb)
from public, anon, service_role;
revoke all on function public.approve_security_action_v1(uuid, text, text, text)
from public, anon, service_role;
revoke all on function public.reject_security_action_v1(uuid, text, text, text, text)
from public, anon, service_role;
revoke all on function lws_internal.evaluate_security_action_approval_v1(uuid, text, text, text)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.claim_security_action_execution_v1(uuid, text, text, text)
from public, anon, authenticated, service_role;

grant execute on function public.request_security_action_approval_v1(text, text, integer, jsonb) to authenticated;
grant execute on function public.approve_security_action_v1(uuid, text, text, text) to authenticated;
grant execute on function public.reject_security_action_v1(uuid, text, text, text, text) to authenticated;
grant execute on function lws_internal.evaluate_security_action_approval_v1(uuid, text, text, text) to service_role;
grant execute on function lws_internal.claim_security_action_execution_v1(uuid, text, text, text) to service_role;

comment on table lws_internal.security_action_approvals is
  'Payload-free dual-control approval records. Object binding is stored only as a SHA-256 fingerprint.';
comment on function lws_internal.claim_security_action_execution_v1(uuid, text, text, text) is
  'Atomic single-use execution claim for future server-side command wiring; P0-3B wires no business action.';
