create table lws_internal.security_recovery_policy (
  action_code text primary key
    references lws_internal.security_action_policy(action_code) on delete restrict,
  recovery_class text not null
    check (recovery_class in ('RESTORABLE', 'COMPENSATABLE', 'IRREVERSIBLE')),
  retention_seconds integer check (retention_seconds is null or retention_seconds > 0),
  minimum_pre_execution_retention_seconds integer not null default 0
    check (minimum_pre_execution_retention_seconds >= 0),
  requires_restore_approval boolean not null,
  restore_requires_aal2 boolean not null,
  requires_retained_source boolean not null,
  requires_trash_first boolean not null,
  requires_dual_control_before_execution boolean not null,
  requires_backup_dependency boolean not null,
  compensating_action_code text
    check (compensating_action_code is null or compensating_action_code ~ '^[a-z][a-z0-9_]{2,99}$'),
  enabled boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint security_recovery_policy_class_shape check (
    (
      recovery_class = 'RESTORABLE'
      and retention_seconds is not null
      and minimum_pre_execution_retention_seconds = 0
      and requires_restore_approval
      and restore_requires_aal2
      and requires_retained_source
      and compensating_action_code is null
    )
    or (
      recovery_class = 'COMPENSATABLE'
      and retention_seconds is null
      and minimum_pre_execution_retention_seconds = 0
      and not requires_restore_approval
      and not restore_requires_aal2
      and not requires_retained_source
      and compensating_action_code is not null
    )
    or (
      recovery_class = 'IRREVERSIBLE'
      and retention_seconds is null
      and not requires_restore_approval
      and not restore_requires_aal2
      and not requires_retained_source
      and compensating_action_code is null
    )
  )
);

create table lws_internal.security_recovery_records (
  recovery_record_id uuid primary key default gen_random_uuid(),
  action_code text not null references lws_internal.security_recovery_policy(action_code),
  recovery_class text not null
    check (recovery_class in ('RESTORABLE', 'COMPENSATABLE', 'IRREVERSIBLE')),
  object_reference uuid not null,
  object_reference_fingerprint char(64) not null
    check (object_reference_fingerprint ~ '^[0-9a-f]{64}$'),
  actor_auth_user_id uuid not null references auth.users(id),
  recovery_state text not null check (recovery_state in (
    'AVAILABLE',
    'RESTORE_REQUESTED',
    'RESTORE_APPROVED',
    'RESTORED',
    'COMPENSATION_REQUIRED',
    'IRREVERSIBLE_RECORDED',
    'EXPIRED'
  )),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz,
  safe_metadata jsonb not null default '{}'::jsonb,
  constraint security_recovery_records_identity_unique
    unique (action_code, object_reference_fingerprint),
  constraint security_recovery_records_metadata_safe check (
    jsonb_typeof(safe_metadata) = 'object'
    and pg_column_size(safe_metadata) <= 2048
    and safe_metadata - array['correlation_id', 'reason_code', 'source', 'dependency_code']::text[] = '{}'::jsonb
    and (safe_metadata -> 'correlation_id' is null or jsonb_typeof(safe_metadata -> 'correlation_id') = 'string')
    and (safe_metadata -> 'reason_code' is null or jsonb_typeof(safe_metadata -> 'reason_code') = 'string')
    and (safe_metadata -> 'source' is null or jsonb_typeof(safe_metadata -> 'source') = 'string')
    and (safe_metadata -> 'dependency_code' is null or jsonb_typeof(safe_metadata -> 'dependency_code') = 'string')
  ),
  constraint security_recovery_records_state_shape check (
    (
      recovery_class = 'RESTORABLE'
      and recovery_state in ('AVAILABLE', 'RESTORE_REQUESTED', 'RESTORE_APPROVED', 'RESTORED', 'EXPIRED')
      and expires_at is not null
      and expires_at > created_at
    )
    or (
      recovery_class = 'COMPENSATABLE'
      and recovery_state = 'COMPENSATION_REQUIRED'
      and expires_at is null
    )
    or (
      recovery_class = 'IRREVERSIBLE'
      and recovery_state = 'IRREVERSIBLE_RECORDED'
      and expires_at is null
    )
  )
);

create table lws_internal.security_restore_requests (
  restore_request_id uuid primary key default gen_random_uuid(),
  recovery_record_id uuid not null unique
    references lws_internal.security_recovery_records(recovery_record_id) on delete restrict,
  action_code text not null references lws_internal.security_recovery_policy(action_code),
  object_reference_fingerprint char(64) not null
    check (object_reference_fingerprint ~ '^[0-9a-f]{64}$'),
  requested_by uuid not null references auth.users(id),
  requested_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  request_fingerprint char(64) not null unique
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  status text not null default 'PENDING'
    check (status in ('PENDING', 'APPROVED', 'EXPIRED', 'CANCELLED')),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  safe_metadata jsonb not null default '{}'::jsonb,
  constraint security_restore_requests_expiry_shape check (expires_at > requested_at),
  constraint security_restore_requests_actor_separation
    check (approved_by is null or approved_by <> requested_by),
  constraint security_restore_requests_state_shape check (
    (status in ('PENDING', 'EXPIRED', 'CANCELLED') and approved_by is null and approved_at is null)
    or (status = 'APPROVED' and approved_by is not null and approved_at is not null)
  ),
  constraint security_restore_requests_metadata_safe check (
    jsonb_typeof(safe_metadata) = 'object'
    and pg_column_size(safe_metadata) <= 2048
    and safe_metadata - array['correlation_id', 'reason_code', 'source']::text[] = '{}'::jsonb
  )
);

create table lws_internal.security_compensating_events (
  compensating_event_id uuid primary key default gen_random_uuid(),
  original_recovery_record_id uuid not null
    references lws_internal.security_recovery_records(recovery_record_id) on delete restrict,
  previous_compensating_event_id uuid
    references lws_internal.security_compensating_events(compensating_event_id) on delete restrict,
  original_action_code text not null references lws_internal.security_recovery_policy(action_code),
  compensating_action_code text not null
    check (compensating_action_code ~ '^[a-z][a-z0-9_]{2,99}$'),
  object_reference_fingerprint char(64) not null
    check (object_reference_fingerprint ~ '^[0-9a-f]{64}$'),
  actor_auth_user_id uuid not null references auth.users(id),
  approved_by_auth_user_id uuid not null references auth.users(id),
  approval_id uuid not null references lws_internal.security_action_approvals(id) on delete restrict,
  event_fingerprint char(64) not null unique
    check (event_fingerprint ~ '^[0-9a-f]{64}$'),
  occurred_at timestamptz not null default clock_timestamp(),
  safe_metadata jsonb not null default '{}'::jsonb,
  constraint security_compensating_events_actor_separation
    check (actor_auth_user_id <> approved_by_auth_user_id),
  constraint security_compensating_events_metadata_safe check (
    jsonb_typeof(safe_metadata) = 'object'
    and pg_column_size(safe_metadata) <= 2048
    and safe_metadata - array['correlation_id', 'reason_code', 'source']::text[] = '{}'::jsonb
  )
);

create index security_recovery_records_lookup_idx
  on lws_internal.security_recovery_records(action_code, object_reference, expires_at);
create index security_compensating_events_chain_idx
  on lws_internal.security_compensating_events(original_recovery_record_id, occurred_at);

revoke all privileges on table
  lws_internal.security_recovery_policy,
  lws_internal.security_recovery_records,
  lws_internal.security_restore_requests,
  lws_internal.security_compensating_events
from public, anon, authenticated, service_role;

create function lws_internal.guard_security_recovery_record_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'SECURITY_RECOVERY_RECORD_DELETE_FORBIDDEN';
  end if;
  if new.recovery_record_id <> old.recovery_record_id
    or new.action_code <> old.action_code
    or new.recovery_class <> old.recovery_class
    or new.object_reference <> old.object_reference
    or new.object_reference_fingerprint <> old.object_reference_fingerprint
    or new.actor_auth_user_id <> old.actor_auth_user_id
    or new.created_at <> old.created_at
    or new.expires_at is distinct from old.expires_at
    or new.safe_metadata <> old.safe_metadata then
    raise exception using errcode = '55000', message = 'SECURITY_RECOVERY_RECORD_BINDING_IMMUTABLE';
  end if;
  if (old.recovery_state, new.recovery_state) in (
    ('AVAILABLE', 'RESTORE_REQUESTED'),
    ('AVAILABLE', 'EXPIRED'),
    ('RESTORE_REQUESTED', 'RESTORE_APPROVED'),
    ('RESTORE_REQUESTED', 'EXPIRED'),
    ('RESTORE_APPROVED', 'RESTORED'),
    ('RESTORE_APPROVED', 'EXPIRED')
  ) then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'SECURITY_RECOVERY_RECORD_TRANSITION_FORBIDDEN';
end;
$$;

create trigger trg_security_recovery_record_guard
before update or delete on lws_internal.security_recovery_records
for each row execute function lws_internal.guard_security_recovery_record_v1();

create function lws_internal.guard_security_restore_request_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'SECURITY_RESTORE_REQUEST_DELETE_FORBIDDEN';
  end if;
  if new.restore_request_id <> old.restore_request_id
    or new.recovery_record_id <> old.recovery_record_id
    or new.action_code <> old.action_code
    or new.object_reference_fingerprint <> old.object_reference_fingerprint
    or new.requested_by <> old.requested_by
    or new.requested_at <> old.requested_at
    or new.expires_at <> old.expires_at
    or new.request_fingerprint <> old.request_fingerprint
    or new.safe_metadata <> old.safe_metadata then
    raise exception using errcode = '55000', message = 'SECURITY_RESTORE_REQUEST_BINDING_IMMUTABLE';
  end if;
  if old.status = 'PENDING' and new.status in ('APPROVED', 'EXPIRED', 'CANCELLED') then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'SECURITY_RESTORE_REQUEST_TRANSITION_FORBIDDEN';
end;
$$;

create trigger trg_security_restore_request_guard
before update or delete on lws_internal.security_restore_requests
for each row execute function lws_internal.guard_security_restore_request_v1();

create trigger trg_security_compensating_event_append_only
before update or delete on lws_internal.security_compensating_events
for each row execute function lws_internal.guard_security_control_event_append_only_v1();

create function lws_internal.assert_security_recovery_aal2_v1()
returns void
language plpgsql
stable
security definer
set search_path = auth, pg_catalog
as $$
begin
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception using errcode = '42501', message = 'AAL2_REQUIRED';
  end if;
end;
$$;

create function lws_internal.security_retained_source_available_v1(
  p_action_code text,
  p_object_reference uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select case p_action_code
    when 'archive_project' then exists (
      select 1
      from public.commercial_projects as project
      where project.project_id = p_object_reference
        and project.current_state = 'ARCHIVED'
    )
    else false
  end;
$$;

create function lws_internal.evaluate_security_destructive_execution_v1(
  p_recovery_record_id uuid,
  p_action_code text,
  p_object_reference uuid,
  p_object_reference_fingerprint text
)
returns table (
  allowed boolean,
  reason_code text,
  action_code text,
  retention_satisfied boolean,
  trash_first_satisfied boolean,
  backup_dependency_satisfied boolean,
  dual_control_satisfied boolean
)
language plpgsql
stable
security definer
set search_path = lws_internal, public, auth, pg_catalog
as $$
declare
  v_actor uuid := lws_internal.resolve_security_velocity_actor_v1();
  v_action_code text := btrim(coalesce(p_action_code, ''));
  v_policy lws_internal.security_recovery_policy%rowtype;
  v_record lws_internal.security_recovery_records%rowtype;
  v_lifecycle_state text;
  v_lifecycle_revision bigint;
  v_retained_since timestamptz;
  v_retention_satisfied boolean := false;
  v_trash_satisfied boolean := false;
  v_dual_control_satisfied boolean := false;
begin
  if not exists (
    select 1 from public.commercial_operators as operator
    where operator.auth_user_id = v_actor and operator.role = 'owner'
  ) then
    raise exception using errcode = '42501', message = 'SECURITY_DESTRUCTIVE_EXECUTION_OWNER_REQUIRED';
  end if;
  perform lws_internal.assert_security_recovery_aal2_v1();

  if p_recovery_record_id is null
    or p_object_reference is null
    or p_object_reference_fingerprint is null
    or p_object_reference_fingerprint !~ '^[0-9a-f]{64}$' then
    return query select false, 'SECURITY_DESTRUCTIVE_BINDING_INVALID', v_action_code,
      false, false, false, false;
    return;
  end if;

  select * into v_policy
  from lws_internal.security_recovery_policy as policy
  where policy.action_code = v_action_code
    and policy.enabled
    and policy.action_code in (
      'purge_dossier_v1',
      'purge_sdf_dossier_v1',
      'permanently_delete_pending_intake_v1'
    );
  if not found
    or v_policy.recovery_class <> 'IRREVERSIBLE'
    or not v_policy.requires_trash_first
    or v_policy.minimum_pre_execution_retention_seconds <= 0
    or not v_policy.requires_backup_dependency
    or not v_policy.requires_dual_control_before_execution then
    return query select false, 'SECURITY_DESTRUCTIVE_POLICY_INVALID', v_action_code,
      false, false, false, false;
    return;
  end if;

  select * into v_record
  from lws_internal.security_recovery_records as recovery
  where recovery.recovery_record_id = p_recovery_record_id;
  if not found
    or v_record.action_code <> v_action_code
    or v_record.object_reference <> p_object_reference
    or v_record.object_reference_fingerprint <> p_object_reference_fingerprint
    or v_record.actor_auth_user_id <> v_actor
    or v_record.recovery_class <> 'IRREVERSIBLE'
    or v_record.recovery_state <> 'IRREVERSIBLE_RECORDED' then
    return query select false, 'SECURITY_DESTRUCTIVE_BINDING_MISMATCH', v_action_code,
      false, false, false, false;
    return;
  end if;

  if v_action_code in ('purge_dossier_v1', 'purge_sdf_dossier_v1') then
    select state.state, state.revision
    into v_lifecycle_state, v_lifecycle_revision
    from lws_internal.operator_dossier_states as state
    where state.quote_request_id = p_object_reference;
    if not found or v_lifecycle_state <> 'TRASHED' then
      return query select false, 'SECURITY_DESTRUCTIVE_TRASH_FIRST_REQUIRED', v_action_code,
        false, false, false, false;
      return;
    end if;
    v_trash_satisfied := true;

    select event.occurred_at into v_retained_since
    from lws_internal.operator_dossier_state_events as event
    where event.quote_request_id = p_object_reference
      and event.event_type = 'TRASHED'
      and event.new_state = 'TRASHED'
      and event.new_revision = v_lifecycle_revision
    order by event.event_id desc
    limit 1;
  else
    select retention.retention_state, retention.archived_at
    into v_lifecycle_state, v_retained_since
    from lws_internal.operator_pending_intake_retention as retention
    where retention.intake_id = p_object_reference;
    if not found or v_lifecycle_state <> 'ARCHIVED' then
      return query select false, 'SECURITY_DESTRUCTIVE_TRASH_FIRST_REQUIRED', v_action_code,
        false, false, false, false;
      return;
    end if;
    v_trash_satisfied := true;
  end if;

  if v_retained_since is null then
    return query select false, 'SECURITY_DESTRUCTIVE_TRASH_TIMESTAMP_REQUIRED', v_action_code,
      false, v_trash_satisfied, false, false;
    return;
  end if;

  v_retention_satisfied :=
    v_retained_since + make_interval(secs => v_policy.minimum_pre_execution_retention_seconds)
      <= clock_timestamp();
  if not v_retention_satisfied then
    return query select false, 'SECURITY_DESTRUCTIVE_RETENTION_ACTIVE', v_action_code,
      false, v_trash_satisfied, false, false;
    return;
  end if;

  select exists (
    select 1
    from lws_internal.security_action_approvals as approval
    where approval.action_code = v_action_code
      and approval.object_reference_fingerprint = p_object_reference_fingerprint
      and approval.requested_by = v_actor
      and approval.approved_by is not null
      and approval.approved_by <> v_actor
      and approval.status = 'APPROVED'
      and approval.expires_at > clock_timestamp()
  ) into v_dual_control_satisfied;
  if not v_dual_control_satisfied then
    return query select false, 'SECURITY_DESTRUCTIVE_DUAL_CONTROL_REQUIRED', v_action_code,
      true, v_trash_satisfied, false, false;
    return;
  end if;

  return query select false, 'BACKUP_EVIDENCE_UNAVAILABLE', v_action_code,
    true, v_trash_satisfied, false, true;
end;
$$;

create function lws_internal.record_security_recovery_v1(
  p_action_code text,
  p_object_reference uuid,
  p_object_reference_fingerprint text,
  p_safe_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
volatile
security definer
set search_path = lws_internal, public, auth, pg_catalog
as $$
declare
  v_actor uuid := lws_internal.resolve_security_velocity_actor_v1();
  v_policy lws_internal.security_recovery_policy%rowtype;
  v_record_id uuid;
begin
  if not exists (
    select 1 from public.commercial_operators as operator
    where operator.auth_user_id = v_actor and operator.role in ('owner', 'admin')
  ) then
    raise exception using errcode = '42501', message = 'SECURITY_RECOVERY_AUTHORITY_REQUIRED';
  end if;
  perform lws_internal.assert_security_recovery_aal2_v1();
  if p_object_reference is null
    or p_object_reference_fingerprint is null
    or p_object_reference_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'SECURITY_RECOVERY_OBJECT_BINDING_INVALID';
  end if;

  select recovery.* into v_policy
  from lws_internal.security_recovery_policy as recovery
  join lws_internal.security_action_policy as action using (action_code)
  where recovery.action_code = btrim(coalesce(p_action_code, ''))
    and recovery.enabled
    and action.enabled
    and action.risk_level in ('HIGH', 'CRITICAL');
  if not found then
    raise exception using errcode = '55000', message = 'SECURITY_RECOVERY_POLICY_NOT_AVAILABLE';
  end if;

  if v_policy.recovery_class = 'RESTORABLE'
    and not lws_internal.security_retained_source_available_v1(v_policy.action_code, p_object_reference) then
    raise exception using errcode = '55000', message = 'SECURITY_RECOVERY_RETAINED_SOURCE_REQUIRED';
  end if;

  insert into lws_internal.security_recovery_records (
    action_code, recovery_class, object_reference, object_reference_fingerprint,
    actor_auth_user_id, recovery_state, expires_at, safe_metadata
  ) values (
    v_policy.action_code,
    v_policy.recovery_class,
    p_object_reference,
    p_object_reference_fingerprint,
    v_actor,
    case v_policy.recovery_class
      when 'RESTORABLE' then 'AVAILABLE'
      when 'COMPENSATABLE' then 'COMPENSATION_REQUIRED'
      else 'IRREVERSIBLE_RECORDED'
    end,
    case when v_policy.recovery_class = 'RESTORABLE'
      then clock_timestamp() + make_interval(secs => v_policy.retention_seconds)
      else null
    end,
    coalesce(p_safe_metadata, '{}'::jsonb)
  ) returning recovery_record_id into v_record_id;

  insert into lws_internal.security_control_events (
    actor_auth_user_id, event_type, domain, action_code,
    object_reference_fingerprint, metadata
  )
  select v_actor, 'RECOVERY_RECORDED', action.domain, v_policy.action_code,
    p_object_reference_fingerprint,
    jsonb_build_object('recovery_record_id', v_record_id, 'recovery_class', v_policy.recovery_class)
  from lws_internal.security_action_policy as action
  where action.action_code = v_policy.action_code;

  return v_record_id;
end;
$$;

create function lws_internal.evaluate_security_recovery_v1(
  p_recovery_record_id uuid,
  p_action_code text,
  p_object_reference_fingerprint text
)
returns table (
  eligible boolean,
  reason_code text,
  recovery_class text,
  expires_at timestamptz,
  retained_source_available boolean
)
language plpgsql
stable
security definer
set search_path = lws_internal, public, auth, pg_catalog
as $$
declare
  v_actor uuid := lws_internal.resolve_security_velocity_actor_v1();
  v_record lws_internal.security_recovery_records%rowtype;
  v_policy lws_internal.security_recovery_policy%rowtype;
  v_source_available boolean := false;
begin
  if not exists (
    select 1 from public.commercial_operators as operator
    where operator.auth_user_id = v_actor and operator.role in ('owner', 'admin')
  ) then
    raise exception using errcode = '42501', message = 'SECURITY_RECOVERY_AUTHORITY_REQUIRED';
  end if;

  select * into v_record
  from lws_internal.security_recovery_records as recovery
  where recovery.recovery_record_id = p_recovery_record_id;
  if not found
    or v_record.action_code <> btrim(coalesce(p_action_code, ''))
    or v_record.object_reference_fingerprint <> p_object_reference_fingerprint then
    return query select false, 'SECURITY_RECOVERY_BINDING_MISMATCH', null::text, null::timestamptz, false;
    return;
  end if;

  select * into v_policy
  from lws_internal.security_recovery_policy as policy
  where policy.action_code = v_record.action_code and policy.enabled;
  if not found then
    return query select false, 'SECURITY_RECOVERY_POLICY_NOT_AVAILABLE', v_record.recovery_class, v_record.expires_at, false;
    return;
  end if;
  if v_record.recovery_class = 'IRREVERSIBLE' then
    return query select false, 'SECURITY_RECOVERY_IRREVERSIBLE', v_record.recovery_class, null::timestamptz, false;
    return;
  elsif v_record.recovery_class = 'COMPENSATABLE' then
    return query select false, 'SECURITY_RECOVERY_COMPENSATION_REQUIRED', v_record.recovery_class, null::timestamptz, false;
    return;
  end if;

  if v_policy.restore_requires_aal2 then
    perform lws_internal.assert_security_recovery_aal2_v1();
  end if;
  if v_record.expires_at <= clock_timestamp() or v_record.recovery_state = 'EXPIRED' then
    return query select false, 'SECURITY_RECOVERY_RETENTION_EXPIRED', v_record.recovery_class, v_record.expires_at, false;
    return;
  end if;
  if v_record.recovery_state <> 'AVAILABLE' then
    return query select false, 'SECURITY_RECOVERY_STATE_NOT_AVAILABLE', v_record.recovery_class, v_record.expires_at, false;
    return;
  end if;

  v_source_available := lws_internal.security_retained_source_available_v1(
    v_record.action_code,
    v_record.object_reference
  );
  if not v_source_available then
    return query select false, 'SECURITY_RECOVERY_RETAINED_SOURCE_REQUIRED', v_record.recovery_class, v_record.expires_at, false;
    return;
  end if;

  return query select true, 'SECURITY_RECOVERY_ELIGIBLE', v_record.recovery_class, v_record.expires_at, true;
end;
$$;

create function lws_internal.request_security_restore_v1(
  p_recovery_record_id uuid,
  p_action_code text,
  p_object_reference_fingerprint text,
  p_request_fingerprint text,
  p_safe_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
volatile
security definer
set search_path = lws_internal, public, auth, pg_catalog
as $$
declare
  v_actor uuid := lws_internal.resolve_security_velocity_actor_v1();
  v_evaluation record;
  v_record lws_internal.security_recovery_records%rowtype;
  v_request_id uuid;
begin
  if not exists (
    select 1 from public.commercial_operators as operator
    where operator.auth_user_id = v_actor and operator.role in ('owner', 'admin')
  ) then
    raise exception using errcode = '42501', message = 'SECURITY_RECOVERY_AUTHORITY_REQUIRED';
  end if;
  if p_request_fingerprint is null or p_request_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'SECURITY_RESTORE_REQUEST_FINGERPRINT_INVALID';
  end if;
  if exists (
    select 1 from lws_internal.security_restore_requests
    where recovery_record_id = p_recovery_record_id
  ) then
    raise exception using errcode = '55000', message = 'SECURITY_RESTORE_REQUEST_DUPLICATE';
  end if;

  select * into v_evaluation
  from lws_internal.evaluate_security_recovery_v1(
    p_recovery_record_id, p_action_code, p_object_reference_fingerprint
  );
  if not coalesce(v_evaluation.eligible, false) then
    raise exception using errcode = '55000', message = coalesce(v_evaluation.reason_code, 'SECURITY_RECOVERY_DENIED');
  end if;

  select * into strict v_record
  from lws_internal.security_recovery_records
  where recovery_record_id = p_recovery_record_id
  for update;

  insert into lws_internal.security_restore_requests (
    recovery_record_id, action_code, object_reference_fingerprint,
    requested_by, expires_at, request_fingerprint, safe_metadata
  ) values (
    v_record.recovery_record_id, v_record.action_code, v_record.object_reference_fingerprint,
    v_actor, least(v_record.expires_at, clock_timestamp() + interval '15 minutes'),
    p_request_fingerprint, coalesce(p_safe_metadata, '{}'::jsonb)
  ) returning restore_request_id into v_request_id;

  update lws_internal.security_recovery_records
  set recovery_state = 'RESTORE_REQUESTED'
  where recovery_record_id = v_record.recovery_record_id;

  insert into lws_internal.security_control_events (
    actor_auth_user_id, event_type, domain, action_code,
    object_reference_fingerprint, metadata
  )
  select v_actor, 'RESTORE_REQUESTED', action.domain, v_record.action_code,
    v_record.object_reference_fingerprint,
    jsonb_build_object('recovery_record_id', v_record.recovery_record_id, 'restore_request_id', v_request_id)
  from lws_internal.security_action_policy as action
  where action.action_code = v_record.action_code;

  return v_request_id;
end;
$$;

create function lws_internal.approve_security_restore_v1(
  p_restore_request_id uuid,
  p_action_code text,
  p_object_reference_fingerprint text
)
returns boolean
language plpgsql
volatile
security definer
set search_path = lws_internal, public, auth, pg_catalog
as $$
declare
  v_actor uuid := lws_internal.assert_security_approval_actor_aal2_v1();
  v_request lws_internal.security_restore_requests%rowtype;
  v_record lws_internal.security_recovery_records%rowtype;
begin
  select * into v_request
  from lws_internal.security_restore_requests
  where restore_request_id = p_restore_request_id
  for update;
  if not found
    or v_request.action_code <> btrim(coalesce(p_action_code, ''))
    or v_request.object_reference_fingerprint <> p_object_reference_fingerprint then
    raise exception using errcode = '55000', message = 'SECURITY_RESTORE_BINDING_MISMATCH';
  end if;
  if v_request.status <> 'PENDING' then
    raise exception using errcode = '55000', message = 'SECURITY_RESTORE_REQUEST_NOT_PENDING';
  end if;
  if v_request.expires_at <= clock_timestamp() then
    raise exception using errcode = '55000', message = 'SECURITY_RESTORE_REQUEST_EXPIRED';
  end if;
  if v_request.requested_by = v_actor then
    raise exception using errcode = '42501', message = 'SECURITY_RESTORE_SELF_APPROVAL_FORBIDDEN';
  end if;

  select * into strict v_record
  from lws_internal.security_recovery_records
  where recovery_record_id = v_request.recovery_record_id
  for update;
  if v_record.expires_at <= clock_timestamp()
    or not lws_internal.security_retained_source_available_v1(v_record.action_code, v_record.object_reference) then
    raise exception using errcode = '55000', message = 'SECURITY_RECOVERY_RETAINED_SOURCE_REQUIRED';
  end if;

  update lws_internal.security_restore_requests
  set status = 'APPROVED', approved_by = v_actor, approved_at = clock_timestamp()
  where restore_request_id = v_request.restore_request_id;
  update lws_internal.security_recovery_records
  set recovery_state = 'RESTORE_APPROVED'
  where recovery_record_id = v_record.recovery_record_id;

  insert into lws_internal.security_control_events (
    actor_auth_user_id, event_type, domain, action_code,
    object_reference_fingerprint, metadata
  )
  select v_actor, 'RESTORE_APPROVED', action.domain, v_record.action_code,
    v_record.object_reference_fingerprint,
    jsonb_build_object('recovery_record_id', v_record.recovery_record_id, 'restore_request_id', v_request.restore_request_id)
  from lws_internal.security_action_policy as action
  where action.action_code = v_record.action_code;

  return true;
end;
$$;

create function lws_internal.record_security_compensating_event_v1(
  p_original_recovery_record_id uuid,
  p_compensating_action_code text,
  p_approval_id uuid,
  p_event_fingerprint text,
  p_previous_compensating_event_id uuid default null,
  p_safe_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
volatile
security definer
set search_path = lws_internal, public, auth, pg_catalog
as $$
declare
  v_actor uuid := lws_internal.resolve_security_velocity_actor_v1();
  v_record lws_internal.security_recovery_records%rowtype;
  v_policy lws_internal.security_recovery_policy%rowtype;
  v_approval lws_internal.security_action_approvals%rowtype;
  v_event_id uuid;
begin
  if not exists (
    select 1 from public.commercial_operators as operator
    where operator.auth_user_id = v_actor and operator.role in ('owner', 'admin')
  ) then
    raise exception using errcode = '42501', message = 'SECURITY_RECOVERY_AUTHORITY_REQUIRED';
  end if;
  perform lws_internal.assert_security_recovery_aal2_v1();
  if p_event_fingerprint is null or p_event_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'SECURITY_COMPENSATION_FINGERPRINT_INVALID';
  end if;

  select * into v_record
  from lws_internal.security_recovery_records
  where recovery_record_id = p_original_recovery_record_id;
  select * into v_policy
  from lws_internal.security_recovery_policy
  where action_code = v_record.action_code;
  if not found or v_record.recovery_class <> 'COMPENSATABLE'
    or v_record.recovery_state <> 'COMPENSATION_REQUIRED'
    or v_policy.compensating_action_code <> btrim(coalesce(p_compensating_action_code, '')) then
    raise exception using errcode = '55000', message = 'SECURITY_COMPENSATION_POLICY_MISMATCH';
  end if;

  select * into v_approval
  from lws_internal.security_action_approvals
  where id = p_approval_id;
  if not found
    or v_approval.action_code <> v_record.action_code
    or v_approval.object_reference_fingerprint <> v_record.object_reference_fingerprint
    or v_approval.requested_by <> v_actor
    or v_approval.approved_by is null
    or v_approval.approved_by = v_actor
    or v_approval.status not in ('APPROVED', 'EXECUTED')
    or v_approval.expires_at <= clock_timestamp() then
    raise exception using errcode = '55000', message = 'SECURITY_COMPENSATION_APPROVAL_REQUIRED';
  end if;

  if p_previous_compensating_event_id is not null and not exists (
    select 1 from lws_internal.security_compensating_events
    where compensating_event_id = p_previous_compensating_event_id
      and original_recovery_record_id = p_original_recovery_record_id
  ) then
    raise exception using errcode = '55000', message = 'SECURITY_COMPENSATION_CHAIN_INVALID';
  end if;

  insert into lws_internal.security_compensating_events (
    original_recovery_record_id, previous_compensating_event_id,
    original_action_code, compensating_action_code, object_reference_fingerprint,
    actor_auth_user_id, approved_by_auth_user_id, approval_id,
    event_fingerprint, safe_metadata
  ) values (
    v_record.recovery_record_id, p_previous_compensating_event_id,
    v_record.action_code, v_policy.compensating_action_code, v_record.object_reference_fingerprint,
    v_actor, v_approval.approved_by, v_approval.id,
    p_event_fingerprint, coalesce(p_safe_metadata, '{}'::jsonb)
  ) returning compensating_event_id into v_event_id;

  insert into lws_internal.security_control_events (
    actor_auth_user_id, event_type, domain, action_code,
    object_reference_fingerprint, metadata
  )
  select v_actor, 'COMPENSATION_RECORDED', action.domain, v_record.action_code,
    v_record.object_reference_fingerprint,
    jsonb_build_object(
      'recovery_record_id', v_record.recovery_record_id,
      'compensating_event_id', v_event_id,
      'compensating_action_code', v_policy.compensating_action_code,
      'approved_by', v_approval.approved_by
    )
  from lws_internal.security_action_policy as action
  where action.action_code = v_record.action_code;

  return v_event_id;
end;
$$;

revoke all on function lws_internal.guard_security_recovery_record_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_security_restore_request_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.assert_security_recovery_aal2_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.security_retained_source_available_v1(text, uuid)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.evaluate_security_destructive_execution_v1(uuid, text, uuid, text)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.record_security_recovery_v1(text, uuid, text, jsonb)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.evaluate_security_recovery_v1(uuid, text, text)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.request_security_restore_v1(uuid, text, text, text, jsonb)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.approve_security_restore_v1(uuid, text, text)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.record_security_compensating_event_v1(uuid, text, uuid, text, uuid, jsonb)
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
    'VELOCITY_RELEASED',
    'RECOVERY_RECORDED',
    'RESTORE_REQUESTED',
    'RESTORE_APPROVED',
    'COMPENSATION_RECORDED'
  ));

insert into lws_internal.security_recovery_policy (
  action_code, recovery_class, retention_seconds,
  minimum_pre_execution_retention_seconds,
  requires_restore_approval, restore_requires_aal2, requires_retained_source, requires_trash_first,
  requires_dual_control_before_execution, requires_backup_dependency,
  compensating_action_code
)
values
  ('purge_dossier_v1', 'IRREVERSIBLE', null, 2592000, false, false, false, true, true, true, null),
  ('purge_sdf_dossier_v1', 'IRREVERSIBLE', null, 2592000, false, false, false, true, true, true, null),
  ('permanently_delete_pending_intake_v1', 'IRREVERSIBLE', null, 604800, false, false, false, true, true, true, null),
  ('appoint_operations_manager_v1', 'COMPENSATABLE', null, 0, false, false, false, false, true, false, 'revoke_operations_manager_v1'),
  ('revoke_operations_manager_v1', 'COMPENSATABLE', null, 0, false, false, false, false, false, false, 'reappoint_operations_manager_v1'),
  ('set_commercial_operator_status_v1', 'COMPENSATABLE', null, 0, false, false, false, false, true, false, 'correct_commercial_operator_status_v1'),
  ('revoke_operator_workspace_v1', 'COMPENSATABLE', null, 0, false, false, false, false, false, false, 'restore_operator_workspace_v1'),
  ('record_payment_evidence', 'COMPENSATABLE', null, 0, false, false, false, false, false, false, 'correct_payment_evidence'),
  ('reconcile_payment', 'COMPENSATABLE', null, 0, false, false, false, false, false, false, 'reverse_payment_reconciliation'),
  ('confirm_payment', 'COMPENSATABLE', null, 0, false, false, false, false, true, false, 'reverse_payment_confirmation'),
  ('release_project', 'IRREVERSIBLE', null, 86400, false, false, false, false, true, true, null),
  ('authorize_final_transfer', 'IRREVERSIBLE', null, 86400, false, false, false, false, true, true, null),
  ('record_delivery', 'IRREVERSIBLE', null, 3600, false, false, false, false, true, false, null),
  ('archive_project', 'RESTORABLE', 2592000, 0, true, true, true, false, false, false, null),
  ('issue_and_deliver_approved_quotation', 'IRREVERSIBLE', null, 3600, false, false, false, false, true, true, null),
  ('cancel_intake', 'COMPENSATABLE', null, 0, false, false, false, false, false, false, 'reinstate_cancelled_intake'),
  ('approve_document_inbox_item_v1', 'COMPENSATABLE', null, 0, false, false, false, false, false, false, 'correct_document_inbox_disposition_v1'),
  ('reject_document_inbox_item_v1', 'COMPENSATABLE', null, 0, false, false, false, false, false, false, 'correct_document_inbox_disposition_v1'),
  ('process_document_inbox_item_v1', 'COMPENSATABLE', null, 0, false, false, false, false, false, false, 'correct_document_inbox_processing_v1'),
  ('invite_recruitment_test_candidate', 'COMPENSATABLE', null, 0, false, false, false, false, false, false, 'revoke_recruitment_test_invitation'),
  ('reject_recruitment_open_application', 'COMPENSATABLE', null, 0, false, false, false, false, false, false, 'reopen_recruitment_application'),
  ('decide_operator_leave_request_v1', 'COMPENSATABLE', null, 0, false, false, false, false, false, false, 'correct_operator_leave_decision_v1'),
  ('create_dossier_document_access', 'IRREVERSIBLE', null, 0, false, false, false, false, true, false, null),
  ('create_recruitment_cv_access', 'IRREVERSIBLE', null, 0, false, false, false, false, true, false, null),
  ('export_application_dossier_pdf', 'IRREVERSIBLE', null, 0, false, false, false, false, true, false, null);

do $$
begin
  if exists (
    select action.action_code
    from lws_internal.security_action_policy as action
    where action.risk_level in ('HIGH', 'CRITICAL')
    except
    select recovery.action_code
    from lws_internal.security_recovery_policy as recovery
  ) or exists (
    select recovery.action_code
    from lws_internal.security_recovery_policy as recovery
    except
    select action.action_code
    from lws_internal.security_action_policy as action
    where action.risk_level in ('HIGH', 'CRITICAL')
  ) or exists (
    select 1
    from lws_internal.security_recovery_policy as recovery
    join lws_internal.security_action_policy as action using (action_code)
    where (action.requires_dual_control and not recovery.requires_dual_control_before_execution)
      or (
        recovery.recovery_class = 'RESTORABLE'
        and action.requires_aal2
        and not recovery.restore_requires_aal2
      )
  ) or exists (
    select 1
    from lws_internal.security_recovery_policy
    where action_code in ('purge_dossier_v1', 'purge_sdf_dossier_v1')
      and (
        recovery_class <> 'IRREVERSIBLE'
        or not requires_trash_first
        or minimum_pre_execution_retention_seconds < 2592000
        or not requires_dual_control_before_execution
        or not requires_backup_dependency
      )
  ) or exists (
    select 1
    from lws_internal.security_recovery_policy
    where action_code = 'permanently_delete_pending_intake_v1'
      and (
        recovery_class <> 'IRREVERSIBLE'
        or not requires_trash_first
        or minimum_pre_execution_retention_seconds < 604800
        or not requires_dual_control_before_execution
        or not requires_backup_dependency
      )
  ) then
    raise exception using errcode = 'P0001', message = 'SECURITY_RECOVERY_POLICY_COVERAGE_INCOMPLETE';
  end if;
end;
$$;

comment on table lws_internal.security_recovery_policy is
  'Private recovery classification for every P0-3A HIGH/CRITICAL action. Purge retention is a pre-execution cooling-off requirement, never evidence that a tombstone can restore deleted data.';
comment on table lws_internal.security_recovery_records is
  'Metadata-only recovery records. Business payloads, documents, credentials, and personal data are not duplicated.';
comment on table lws_internal.security_compensating_events is
  'Append-only correction chain; original action records remain immutable and no business mutation is performed.';
comment on function lws_internal.approve_security_restore_v1(uuid, text, text) is
  'Approves only a bound restore request backed by retained primary data. This foundation performs no production restore.';
comment on function lws_internal.evaluate_security_destructive_execution_v1(uuid, text, uuid, text) is
  'Private pre-execution gate for the three physical delete actions. Reads server lifecycle timestamps and fails closed because no authoritative object-bound backup evidence source exists; performs no delete.';