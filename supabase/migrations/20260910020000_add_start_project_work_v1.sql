alter function public.get_operator_project_start_gate_v1(uuid, uuid)
  rename to get_operator_project_start_gate_pre_work_start_v1;

revoke all on function public.get_operator_project_start_gate_pre_work_start_v1(uuid, uuid)
from public, anon, authenticated, service_role;

create function public.get_operator_project_start_gate_v1(
  p_quote_request_id uuid,
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_projection jsonb;
begin
  v_projection := public.get_operator_project_start_gate_pre_work_start_v1(
    p_quote_request_id,
    p_project_id
  );

  if v_projection->>'current_project_state' = 'PROJECT_RELEASED'
     and exists (
       select 1
       from public.audit_events as event
       where event.project_id = p_project_id
         and event.event_type = 'PROJECT_WORK_STARTED'
     ) then
    v_projection := v_projection || jsonb_build_object(
      'project_start_allowed', false,
      'block_reason', 'STARTED'
    );
  end if;

  return v_projection;
end;
$$;

create function lws_internal.start_project_work_core_v1(
  p_audit_actor text,
  p_quote_request_id uuid,
  p_project_id uuid,
  p_expected_state text,
  p_expected_revision bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = lws_internal, public, extensions, pg_catalog
as $$
declare
  v_project public.commercial_projects%rowtype;
  v_existing public.idempotency_ledger%rowtype;
  v_fingerprint char(64);
  v_gate jsonb;
  v_audit_event_id bigint;
  v_occurred_at timestamptz;
  v_result jsonb;
begin
  if nullif(btrim(p_audit_actor), '') is null
     or p_quote_request_id is null
     or p_project_id is null
     or nullif(btrim(p_expected_state), '') is null
     or p_expected_revision is null
     or p_expected_revision < 0
     or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'INVALID_PROJECT_WORK_START_COMMAND';
  end if;

  v_fingerprint := lws_internal.commercial_fingerprint_v1(jsonb_build_object(
    'actor', p_audit_actor,
    'quote_request_id', p_quote_request_id,
    'project_id', p_project_id,
    'command_type', 'start_project_work',
    'expected_state', p_expected_state,
    'expected_revision', p_expected_revision
  ));

  select * into v_existing
  from public.idempotency_ledger
  where actor_id = p_audit_actor
    and project_id = p_project_id
    and command_type = 'start_project_work'
    and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload;
  end if;

  select * into v_project
  from public.commercial_projects
  where project_id = p_project_id
  for update;
  if not found then
    raise exception using errcode = '23503', message = 'PROJECT_NOT_FOUND';
  end if;

  select * into v_existing
  from public.idempotency_ledger
  where actor_id = p_audit_actor
    and project_id = p_project_id
    and command_type = 'start_project_work'
    and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload;
  end if;

  if v_project.current_state <> p_expected_state
     or v_project.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;

  if exists (
    select 1
    from public.audit_events as event
    where event.project_id = p_project_id
      and event.event_type = 'PROJECT_WORK_STARTED'
  ) then
    raise exception using errcode = 'P0001', message = 'PROJECT_WORK_ALREADY_STARTED';
  end if;

  v_gate := public.get_operator_project_start_gate_v1(
    p_quote_request_id,
    p_project_id
  );
  if not coalesce((v_gate->>'project_start_allowed')::boolean, false)
     or v_project.current_state <> 'PROJECT_RELEASED' then
    raise exception using errcode = 'P0001', message = 'PROJECT_START_BLOCKED';
  end if;

  insert into public.audit_events(
    project_id,
    event_type,
    actor,
    command_id,
    metadata
  ) values (
    p_project_id,
    'PROJECT_WORK_STARTED',
    p_audit_actor,
    p_idempotency_key,
    jsonb_build_object(
      'quote_request_id', p_quote_request_id,
      'command_type', 'start_project_work',
      'expected_state', p_expected_state,
      'expected_revision', p_expected_revision,
      'resulting_revision', v_project.revision
    )
  ) returning audit_event_id, occurred_at
  into v_audit_event_id, v_occurred_at;

  v_result := jsonb_build_object(
    'project_id', p_project_id,
    'quote_request_id', p_quote_request_id,
    'command_type', 'start_project_work',
    'event_type', 'PROJECT_WORK_STARTED',
    'current_project_state', v_project.current_state,
    'expected_revision', p_expected_revision,
    'resulting_revision', v_project.revision,
    'occurred_at', v_occurred_at
  );

  insert into public.idempotency_ledger(
    actor_id,
    project_id,
    command_type,
    idempotency_key,
    request_fingerprint,
    result_reference,
    result_payload
  ) values (
    p_audit_actor,
    p_project_id,
    'start_project_work',
    p_idempotency_key,
    v_fingerprint,
    v_audit_event_id::text,
    v_result
  );

  return v_result;
end;
$$;

create function public.start_project_work_v1(
  p_quote_request_id uuid,
  p_project_id uuid,
  p_expected_state text,
  p_expected_revision bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = lws_internal, public, auth, extensions, pg_catalog
as $$
declare
  v_authorization record;
begin
  if p_quote_request_id is null
     or p_project_id is null
     or nullif(btrim(p_expected_state), '') is null
     or p_expected_revision is null
     or p_expected_revision < 0
     or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'INVALID_PROJECT_WORK_START_COMMAND';
  end if;

  select * into strict v_authorization
  from public.resolve_commercial_operator_authorization_v1(
    p_project_id,
    'record_preview_ready',
    true
  );

  return lws_internal.start_project_work_core_v1(
    v_authorization.audit_actor,
    p_quote_request_id,
    p_project_id,
    p_expected_state,
    p_expected_revision,
    p_idempotency_key
  );
end;
$$;

revoke all on function
  public.get_operator_project_start_gate_v1(uuid, uuid),
  public.start_project_work_v1(uuid, uuid, text, bigint, uuid),
  lws_internal.start_project_work_core_v1(text, uuid, uuid, text, bigint, uuid)
from public, anon, authenticated, service_role;

grant execute on function
  public.get_operator_project_start_gate_v1(uuid, uuid),
  public.start_project_work_v1(uuid, uuid, text, bigint, uuid)
to authenticated;

comment on function public.start_project_work_v1(uuid, uuid, text, bigint, uuid) is
  'Starts authorized Website project work by consuming the derived start gate and recording one immutable audit fact without changing commercial project state.';

comment on function public.get_operator_project_start_gate_v1(uuid, uuid) is
  'Read-only operator start gate with STARTED derived from the immutable PROJECT_WORK_STARTED audit fact.';