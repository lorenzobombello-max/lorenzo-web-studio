alter function public.get_operator_application_v1(uuid, text)
  rename to get_operator_application_v1_phase3_predecessor;

create function public.get_operator_application_v1(
  p_quote_request_id uuid default null,
  p_application_reference text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_result jsonb;
  v_intake public.quote_request_intakes%rowtype;
begin
  v_result := public.get_operator_application_v1_phase3_predecessor(
    p_quote_request_id,
    p_application_reference
  );

  select * into v_intake
  from public.quote_request_intakes
  where quote_request_id = (v_result->>'quote_request_id')::uuid;

  if not found then
    return v_result || jsonb_build_object('intake_lifecycle', null);
  end if;

  return v_result || jsonb_build_object(
    'intake_lifecycle', jsonb_build_object(
      'intake_id', v_intake.id,
      'access_state', v_intake.access_state,
      'effective_access', public.resolve_quote_request_intake_effective_access_v1(
        v_intake.access_state,
        v_intake.access_token_expires_at,
        clock_timestamp()
      ),
      'access_token_expires_at', v_intake.access_token_expires_at,
      'lifecycle_revision', v_intake.lifecycle_revision
    )
  );
end;
$$;

create function public.execute_operator_intake_lifecycle_command_v1(
  p_intake_id uuid,
  p_event_type text,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_reason text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, extensions, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_existing public.quote_request_intake_lifecycle_events%rowtype;
  v_now timestamptz := clock_timestamp();
  v_effective_access text;
  v_new_access_state text;
  v_new_expires_at timestamptz;
  v_reason text := btrim(p_reason);
  v_fingerprint char(64);
  v_result jsonb;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;

  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status = 'DISABLED' then raise exception using errcode = '42501', message = 'OPERATOR_DISABLED'; end if;
  if v_operator.status = 'REVOKED' then raise exception using errcode = '42501', message = 'OPERATOR_REVOKED'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;
  if v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'APPLICATION_SCOPE_DENIED';
  end if;

  if p_intake_id is null
     or p_event_type not in ('INTERRUPTED', 'RESUMED', 'CANCELLED', 'REACTIVATED')
     or p_expected_revision is null or p_expected_revision < 0
     or p_idempotency_key is null
     or char_length(v_reason) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_LIFECYCLE_COMMAND';
  end if;

  select * into v_intake
  from public.quote_request_intakes
  where id = p_intake_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'INTAKE_NOT_FOUND';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(
    jsonb_build_object(
      'contract_version', 1,
      'operator_id', v_operator.operator_id,
      'intake_id', p_intake_id,
      'event_type', p_event_type,
      'expected_revision', p_expected_revision,
      'reason', v_reason
    )::text,
    'UTF8'
  ), 'sha256'), 'hex');

  select * into v_existing
  from public.quote_request_intake_lifecycle_events
  where intake_id = p_intake_id
    and idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'intake_id', v_existing.intake_id,
      'event_type', v_existing.event_type,
      'access_state', v_existing.new_access_state,
      'effective_access', public.resolve_quote_request_intake_effective_access_v1(
        v_existing.new_access_state,
        v_existing.new_expires_at,
        clock_timestamp()
      ),
      'access_token_expires_at', v_existing.new_expires_at,
      'lifecycle_revision', p_expected_revision + 1,
      'replayed', true
    );
  end if;

  if v_intake.lifecycle_revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;

  v_effective_access := public.resolve_quote_request_intake_effective_access_v1(
    v_intake.access_state,
    v_intake.access_token_expires_at,
    v_now
  );

  if p_event_type = 'INTERRUPTED' and v_effective_access = 'ACTIVE' then
    v_new_access_state := 'INTERRUPTED';
    v_new_expires_at := v_intake.access_token_expires_at;
  elsif p_event_type = 'RESUMED' and v_effective_access = 'INTERRUPTED' then
    v_new_access_state := 'ACTIVE';
    v_new_expires_at := v_intake.access_token_expires_at;
  elsif p_event_type = 'CANCELLED'
        and v_effective_access in ('ACTIVE', 'INTERRUPTED') then
    v_new_access_state := 'CANCELLED';
    v_new_expires_at := v_intake.access_token_expires_at;
  elsif p_event_type = 'REACTIVATED'
        and v_effective_access = 'EXPIRED'
        and v_intake.access_state in ('ACTIVE', 'INTERRUPTED') then
    v_new_access_state := 'ACTIVE';
    v_new_expires_at := public.quote_request_intake_default_expires_at_v1(v_now);
  else
    raise exception using errcode = 'P0001', message = 'INVALID_INTAKE_LIFECYCLE_TRANSITION';
  end if;

  insert into public.quote_request_intake_lifecycle_events (
    intake_id,
    event_type,
    previous_access_state,
    new_access_state,
    previous_expires_at,
    new_expires_at,
    actor_operator_id,
    reason,
    occurred_at,
    idempotency_key,
    request_fingerprint,
    evidence
  ) values (
    v_intake.id,
    p_event_type,
    v_intake.access_state,
    v_new_access_state,
    v_intake.access_token_expires_at,
    v_new_expires_at,
    v_operator.operator_id,
    v_reason,
    v_now,
    p_idempotency_key,
    v_fingerprint,
    jsonb_build_object(
      'contract_version', 1,
      'expected_lifecycle_revision', p_expected_revision
    )
  );

  update public.quote_request_intakes
  set access_state = v_new_access_state,
      access_token_expires_at = v_new_expires_at,
      lifecycle_revision = lifecycle_revision + 1,
      updated_at = v_now
  where id = v_intake.id
    and lifecycle_revision = p_expected_revision
  returning jsonb_build_object(
    'intake_id', id,
    'event_type', p_event_type,
    'access_state', access_state,
    'effective_access', public.resolve_quote_request_intake_effective_access_v1(
      access_state,
      access_token_expires_at,
      v_now
    ),
    'access_token_expires_at', access_token_expires_at,
    'lifecycle_revision', lifecycle_revision,
    'replayed', false
  ) into v_result;

  if v_result is null then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;

  return v_result;
end;
$$;

revoke all on function public.get_operator_application_v1_phase3_predecessor(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.get_operator_application_v1(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.execute_operator_intake_lifecycle_command_v1(uuid, text, bigint, uuid, text)
from public, anon, authenticated, service_role;

grant execute on function public.get_operator_application_v1(uuid, text)
to authenticated;
grant execute on function public.execute_operator_intake_lifecycle_command_v1(uuid, text, bigint, uuid, text)
to authenticated;

comment on function public.execute_operator_intake_lifecycle_command_v1(uuid, text, bigint, uuid, text) is
  'Authenticated owner/admin intake lifecycle command boundary with optimistic concurrency, idempotent replay, and immutable event evidence.';