create table lws_internal.operator_dossier_edge_capabilities (
  capability_token uuid primary key default gen_random_uuid(),
  actor_auth_user_id uuid not null,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  issued_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  constraint operator_dossier_edge_capability_window_valid check (
    expires_at > issued_at and expires_at <= issued_at + interval '1 minute'
  ),
  constraint operator_dossier_edge_capability_consumption_valid check (
    consumed_at is null or consumed_at >= issued_at
  )
);

alter table lws_internal.operator_dossier_edge_capabilities enable row level security;
alter table lws_internal.operator_dossier_edge_capabilities force row level security;
revoke all on table lws_internal.operator_dossier_edge_capabilities
from public, anon, authenticated, service_role;

create function public.issue_operator_dossier_lifecycle_edge_capability_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid,
  p_event_type text,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_reason text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_reason text := btrim(p_reason);
  v_fingerprint char(64);
  v_capability uuid;
begin
  if p_actor_auth_user_id is null
     or p_quote_request_id is null
     or p_event_type not in ('ARCHIVED', 'REACTIVATED', 'TRASHED', 'RESTORED')
     or p_expected_revision is null or p_expected_revision < 0
     or p_idempotency_key is null
     or char_length(v_reason) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'INVALID_DOSSIER_LIFECYCLE_CAPABILITY_REQUEST';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(
    jsonb_build_object(
      'contract_version', 1,
      'actor_auth_user_id', p_actor_auth_user_id,
      'quote_request_id', p_quote_request_id,
      'event_type', p_event_type,
      'expected_revision', p_expected_revision,
      'idempotency_key', p_idempotency_key,
      'reason', v_reason
    )::text,
    'UTF8'
  ), 'sha256'), 'hex');

  insert into lws_internal.operator_dossier_edge_capabilities (
    actor_auth_user_id, request_fingerprint, expires_at
  ) values (
    p_actor_auth_user_id, v_fingerprint, clock_timestamp() + interval '30 seconds'
  ) returning capability_token into v_capability;

  return v_capability;
end;
$$;

revoke all on function public.issue_operator_dossier_lifecycle_edge_capability_v1(uuid, uuid, text, bigint, uuid, text)
from public, anon, authenticated, service_role;
grant execute on function public.issue_operator_dossier_lifecycle_edge_capability_v1(uuid, uuid, text, bigint, uuid, text)
to service_role;

create function lws_internal.guard_operator_dossier_blocker_creation_v1()
returns trigger
language plpgsql
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_state text;
begin
  perform 1
  from public.quote_requests
  where id = new.quote_request_id
  for key share;

  if not found then
    return new;
  end if;

  select state into v_state
  from lws_internal.operator_dossier_states
  where quote_request_id = new.quote_request_id;

  if v_state = 'TRASHED' then
    raise exception using errcode = '55000', message = 'TRASHED_DOSSIER_BLOCKER_CREATION_DENIED';
  end if;
  return new;
end;
$$;

revoke all on function lws_internal.guard_operator_dossier_blocker_creation_v1()
from public, anon, authenticated, service_role;

create trigger trg_quotation_draft_dossier_lifecycle_guard
before insert on public.quote_request_quotation_approval_drafts
for each row execute function lws_internal.guard_operator_dossier_blocker_creation_v1();

create trigger trg_sdf_project_dossier_lifecycle_guard
before insert on public.sdf_projects
for each row execute function lws_internal.guard_operator_dossier_blocker_creation_v1();

create trigger trg_sdf_quotation_dossier_lifecycle_guard
before insert on public.sdf_quotations
for each row execute function lws_internal.guard_operator_dossier_blocker_creation_v1();

create function public.execute_operator_dossier_lifecycle_command_v1(
  p_quote_request_id uuid,
  p_event_type text,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_reason text,
  p_edge_capability uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_root_id uuid;
  v_state lws_internal.operator_dossier_states%rowtype;
  v_existing lws_internal.operator_dossier_state_events%rowtype;
  v_capability lws_internal.operator_dossier_edge_capabilities%rowtype;
  v_now timestamptz := clock_timestamp();
  v_reason text := btrim(p_reason);
  v_new_state text;
  v_event_state_before_trash text;
  v_fingerprint char(64);
  v_result jsonb;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject
  for share;

  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status = 'DISABLED' then raise exception using errcode = '42501', message = 'OPERATOR_DISABLED'; end if;
  if v_operator.status = 'REVOKED' then raise exception using errcode = '42501', message = 'OPERATOR_REVOKED'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;
  if v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'APPLICATION_SCOPE_DENIED';
  end if;

  if p_quote_request_id is null
     or p_event_type not in ('ARCHIVED', 'REACTIVATED', 'TRASHED', 'RESTORED')
     or p_expected_revision is null or p_expected_revision < 0
     or p_idempotency_key is null
    or p_edge_capability is null
     or char_length(v_reason) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'INVALID_DOSSIER_LIFECYCLE_COMMAND';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(
    jsonb_build_object(
      'contract_version', 1,
      'actor_auth_user_id', v_subject,
      'quote_request_id', p_quote_request_id,
      'event_type', p_event_type,
      'expected_revision', p_expected_revision,
      'idempotency_key', p_idempotency_key,
      'reason', v_reason
    )::text,
    'UTF8'
  ), 'sha256'), 'hex');

  select * into v_capability
  from lws_internal.operator_dossier_edge_capabilities
  where capability_token = p_edge_capability
  for update;

  if not found
     or v_capability.actor_auth_user_id <> v_subject
     or v_capability.request_fingerprint <> v_fingerprint
     or v_capability.expires_at <= clock_timestamp()
     or v_capability.consumed_at is not null then
    raise exception using errcode = '42501', message = 'EDGE_DOSSIER_CAPABILITY_REQUIRED';
  end if;

  update lws_internal.operator_dossier_edge_capabilities
  set consumed_at = clock_timestamp()
  where capability_token = p_edge_capability;

  select id into v_root_id
  from public.quote_requests
  where id = p_quote_request_id
    and record_classification = 'production'
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'DOSSIER_NOT_FOUND';
  end if;

  select * into v_state
  from lws_internal.operator_dossier_states
  where quote_request_id = v_root_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'DOSSIER_NOT_FOUND';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(
    jsonb_build_object(
      'contract_version', 1,
      'operator_id', v_operator.operator_id,
      'quote_request_id', p_quote_request_id,
      'event_type', p_event_type,
      'expected_revision', p_expected_revision,
      'reason', v_reason
    )::text,
    'UTF8'
  ), 'sha256'), 'hex');

  select * into v_existing
  from lws_internal.operator_dossier_state_events
  where quote_request_id = p_quote_request_id
    and idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'quote_request_id', v_existing.quote_request_id,
      'event_type', v_existing.event_type,
      'state', v_existing.new_state,
      'state_before_trash', case when v_existing.new_state = 'TRASHED' then v_existing.state_before_trash else null end,
      'deletion_eligible_at', v_existing.deletion_eligible_at,
      'revision', v_existing.new_revision,
      'replayed', true
    );
  end if;

  if v_state.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;

  if p_event_type = 'ARCHIVED' and v_state.state = 'ACTIVE' then
    v_new_state := 'ARCHIVED';
    v_event_state_before_trash := null;
  elsif p_event_type = 'REACTIVATED' and v_state.state = 'ARCHIVED' then
    v_new_state := 'ACTIVE';
    v_event_state_before_trash := null;
  elsif p_event_type = 'TRASHED' and v_state.state in ('ACTIVE', 'ARCHIVED') then
    perform lws_internal.assert_legacy_test_cleanup_candidate_v1(p_quote_request_id);
    v_new_state := 'TRASHED';
    v_event_state_before_trash := v_state.state;
  elsif p_event_type = 'RESTORED' and v_state.state = 'TRASHED' then
    if v_state.state_before_trash is null
       or v_state.state_before_trash not in ('ACTIVE', 'ARCHIVED') then
      raise exception using errcode = 'P0001', message = 'INVALID_OPERATOR_DOSSIER_RESTORE';
    end if;
    v_new_state := v_state.state_before_trash;
    v_event_state_before_trash := v_state.state_before_trash;
  else
    raise exception using errcode = 'P0001', message = 'INVALID_OPERATOR_DOSSIER_TRANSITION';
  end if;

  insert into lws_internal.operator_dossier_state_events (
    quote_request_id,
    event_type,
    previous_state,
    new_state,
    state_before_trash,
    previous_revision,
    new_revision,
    deletion_eligible_at,
    actor_operator_id,
    reason,
    occurred_at,
    idempotency_key,
    request_fingerprint,
    evidence
  ) values (
    p_quote_request_id,
    p_event_type,
    v_state.state,
    v_new_state,
    v_event_state_before_trash,
    v_state.revision,
    v_state.revision + 1,
    null,
    v_operator.operator_id,
    v_reason,
    v_now,
    p_idempotency_key,
    v_fingerprint,
    jsonb_build_object(
      'contract_version', 1,
      'expected_revision', p_expected_revision
    )
  );

  update lws_internal.operator_dossier_states
  set state = v_new_state,
      revision = revision + 1,
      state_before_trash = case when v_new_state = 'TRASHED' then v_event_state_before_trash else null end,
      deletion_eligible_at = null,
      updated_at = v_now
  where quote_request_id = p_quote_request_id
    and revision = p_expected_revision
  returning jsonb_build_object(
    'quote_request_id', quote_request_id,
    'event_type', p_event_type,
    'state', state,
    'state_before_trash', state_before_trash,
    'deletion_eligible_at', deletion_eligible_at,
    'revision', revision,
    'replayed', false
  ) into v_result;

  if v_result is null then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;

  return v_result;
end;
$$;

revoke all on function public.execute_operator_dossier_lifecycle_command_v1(uuid, text, bigint, uuid, text, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.execute_operator_dossier_lifecycle_command_v1(uuid, text, bigint, uuid, text, uuid)
to authenticated;

comment on function public.execute_operator_dossier_lifecycle_command_v1(uuid, text, bigint, uuid, text, uuid) is
  'Edge-capability-gated authenticated owner/admin dossier-zone command boundary with revision guards, idempotent audit events, exact-11 trash preflight, restore-to-prior-state semantics, and no purge authority.';
