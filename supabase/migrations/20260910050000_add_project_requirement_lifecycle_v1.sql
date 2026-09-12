create function lws_internal.transition_project_requirement_core_v1(
  p_command_type text,
  p_quote_request_id uuid,
  p_project_id uuid,
  p_requirement_id uuid,
  p_expected_revision bigint,
  p_reason text,
  p_evidence_reference jsonb,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_action text;
  v_require_management boolean;
  v_auth record;
  v_requirement public.project_requirements%rowtype;
  v_board public.project_requirements_boards%rowtype;
  v_existing public.idempotency_ledger%rowtype;
  v_fingerprint char(64);
  v_previous_status text;
  v_new_status text;
  v_event_type text;
  v_reason text := nullif(btrim(p_reason), '');
  v_now timestamptz;
  v_result jsonb;
begin
  if p_command_type not in ('START', 'BLOCK', 'COMPLETE', 'REOPEN')
     or p_quote_request_id is null or p_project_id is null
     or p_requirement_id is null or p_expected_revision is null
     or p_expected_revision < 1 or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'INVALID_REQUIREMENT_LIFECYCLE_COMMAND';
  end if;

  v_action := case p_command_type
    when 'START' then 'START_REQUIREMENT'
    when 'BLOCK' then 'BLOCK_REQUIREMENT'
    when 'COMPLETE' then 'COMPLETE_REQUIREMENT'
    when 'REOPEN' then 'REOPEN_REQUIREMENT'
  end;
  v_require_management := p_command_type = 'REOPEN';

  select * into strict v_auth
  from public.resolve_project_requirement_authorization_v1(
    p_quote_request_id, p_project_id, v_action, v_require_management
  );

  if p_command_type = 'START' then
    if p_reason is not null or p_evidence_reference is not null then
      raise exception using errcode = '22023', message = 'INVALID_REQUIREMENT_LIFECYCLE_COMMAND';
    end if;
  elsif p_command_type = 'BLOCK' then
    if v_reason is null then
      raise exception using errcode = '22023', message = 'BLOCKED_REASON_REQUIRED';
    end if;
    if char_length(v_reason) > 500 or p_evidence_reference is not null then
      raise exception using errcode = '22023', message = 'INVALID_REQUIREMENT_LIFECYCLE_COMMAND';
    end if;
  elsif p_command_type = 'COMPLETE' then
    if p_reason is not null or jsonb_typeof(p_evidence_reference) is distinct from 'object' then
      raise exception using errcode = '22023', message = 'INVALID_REQUIREMENT_COMPLETION_COMMAND';
    end if;
  elsif p_command_type = 'REOPEN' then
    if v_reason is null then
      raise exception using errcode = '22023', message = 'REOPEN_REASON_REQUIRED';
    end if;
    if char_length(v_reason) > 500 or p_evidence_reference is not null then
      raise exception using errcode = '22023', message = 'INVALID_REQUIREMENT_LIFECYCLE_COMMAND';
    end if;
  end if;

  v_fingerprint := lws_internal.commercial_fingerprint_v1(jsonb_build_object(
    'contract_version', 1,
    'actor', v_auth.audit_actor,
    'command_type', p_command_type,
    'quote_request_id', p_quote_request_id,
    'project_id', p_project_id,
    'requirement_id', p_requirement_id,
    'expected_revision', p_expected_revision,
    'reason', v_reason,
    'evidence_reference', p_evidence_reference
  ));
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing
  from public.idempotency_ledger
  where actor_id = v_auth.audit_actor
    and project_id = p_project_id
    and command_type = 'project_requirement_' || lower(p_command_type)
    and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed', true);
  end if;

  perform 1
  from public.commercial_projects
  where project_id = p_project_id
  for update;

  select * into v_requirement
  from public.project_requirements
  where requirement_id = p_requirement_id
    and project_id = p_project_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'PROJECT_REQUIREMENT_NOT_FOUND';
  end if;

  select * into v_board
  from public.project_requirements_boards
  where requirements_board_id = v_requirement.requirements_board_id
    and project_id = p_project_id
    and quote_request_id = p_quote_request_id;
  if not found then
    raise exception using errcode = '42501', message = 'PROJECT_REQUIREMENT_BINDING_DENIED';
  end if;
  if v_board.status <> 'FINALIZED' then
    raise exception using errcode = '55000', message = 'REQUIREMENTS_BOARD_NOT_FINALIZED';
  end if;
  if v_requirement.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;
  v_previous_status := v_requirement.status;

  if p_command_type = 'START' then
    if v_requirement.status not in ('PENDING', 'BLOCKED') then
      raise exception using errcode = '55000', message = 'INVALID_REQUIREMENT_TRANSITION';
    end if;
    if exists (
      select 1
      from public.project_requirements
      where project_id = p_project_id
        and status = 'ACTIVE'
        and requirement_id <> p_requirement_id
    ) then
      raise exception using errcode = 'P0001', message = 'ACTIVE_REQUIREMENT_CONFLICT';
    end if;
    v_new_status := 'ACTIVE';
    v_event_type := 'REQUIREMENT_STARTED';
  elsif p_command_type = 'BLOCK' then
    if v_requirement.status not in ('PENDING', 'ACTIVE') then
      raise exception using errcode = '55000', message = 'INVALID_REQUIREMENT_TRANSITION';
    end if;
    v_new_status := 'BLOCKED';
    v_event_type := 'REQUIREMENT_BLOCKED';
  elsif p_command_type = 'COMPLETE' then
    if v_requirement.status <> 'ACTIVE' then
      raise exception using errcode = '55000', message = 'INVALID_REQUIREMENT_TRANSITION';
    end if;
    if v_requirement.completion_mode = 'OPERATOR' then
      if not public.jsonb_has_exact_keys(p_evidence_reference, array['attestation'])
         or char_length(btrim(p_evidence_reference->>'attestation')) not between 1 and 500 then
        raise exception using errcode = '22023', message = 'OPERATOR_ATTESTATION_REQUIRED';
      end if;
    end if;
    v_new_status := 'COMPLETED';
    v_event_type := 'REQUIREMENT_COMPLETED';
  else
    if v_requirement.status <> 'COMPLETED' then
      raise exception using errcode = '55000', message = 'INVALID_REQUIREMENT_TRANSITION';
    end if;
    v_new_status := 'PENDING';
    v_event_type := 'REQUIREMENT_REOPENED';
  end if;

  v_now := clock_timestamp();
  perform set_config('lws.requirement_command', 'on', true);
  update public.project_requirements
  set status = v_new_status,
      started_at = case
        when p_command_type = 'START' then v_now
        when p_command_type = 'REOPEN' then null
        else started_at
      end,
      completed_at = case when p_command_type = 'COMPLETE' then v_now else null end,
      completed_by = case when p_command_type = 'COMPLETE' then v_auth.audit_actor else null end,
      evidence_reference = case
        when p_command_type = 'COMPLETE' then p_evidence_reference
        when p_command_type = 'REOPEN' then null
        else evidence_reference
      end,
      verification_result = case
        when p_command_type = 'REOPEN' and completion_mode = 'OPERATOR' then 'NOT_APPLICABLE'
        when p_command_type = 'REOPEN' then 'UNKNOWN'
        else verification_result
      end,
      blocked_reason = case when p_command_type = 'BLOCK' then v_reason else null end,
      revision = revision + 1,
      updated_at = v_now
  where requirement_id = p_requirement_id
  returning * into v_requirement;
  perform set_config('lws.requirement_command', '', true);

  v_result := jsonb_build_object(
    'requirement_id', v_requirement.requirement_id,
    'requirements_board_id', v_requirement.requirements_board_id,
    'project_id', v_requirement.project_id,
    'status', v_requirement.status,
    'revision', v_requirement.revision,
    'replayed', false
  );
  insert into public.audit_events(project_id, event_type, actor, command_id, metadata)
  values (
    p_project_id,
    v_event_type,
    v_auth.audit_actor,
    p_idempotency_key,
    jsonb_build_object(
      'requirements_board_id', v_requirement.requirements_board_id,
      'requirement_id', v_requirement.requirement_id,
      'item_number', v_requirement.item_number,
      'previous_status', v_previous_status,
      'new_status', v_new_status,
      'revision', v_requirement.revision,
      'reason', v_reason
    )
  );
  insert into public.idempotency_ledger(
    actor_id, project_id, command_type, idempotency_key, request_fingerprint,
    result_reference, result_payload
  ) values (
    v_auth.audit_actor,
    p_project_id,
    'project_requirement_' || lower(p_command_type),
    p_idempotency_key,
    v_fingerprint,
    p_requirement_id::text,
    v_result
  );
  return v_result;
end;
$$;

create function public.start_project_requirement_v1(
  p_quote_request_id uuid,
  p_project_id uuid,
  p_requirement_id uuid,
  p_expected_revision bigint,
  p_idempotency_key uuid
)
returns jsonb
language sql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
  select lws_internal.transition_project_requirement_core_v1(
    'START', p_quote_request_id, p_project_id, p_requirement_id,
    p_expected_revision, null, null, p_idempotency_key
  )
$$;

create function public.block_project_requirement_v1(
  p_quote_request_id uuid,
  p_project_id uuid,
  p_requirement_id uuid,
  p_expected_revision bigint,
  p_blocked_reason text,
  p_idempotency_key uuid
)
returns jsonb
language sql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
  select lws_internal.transition_project_requirement_core_v1(
    'BLOCK', p_quote_request_id, p_project_id, p_requirement_id,
    p_expected_revision, p_blocked_reason, null, p_idempotency_key
  )
$$;

create function public.complete_project_requirement_v1(
  p_quote_request_id uuid,
  p_project_id uuid,
  p_requirement_id uuid,
  p_expected_revision bigint,
  p_evidence_reference jsonb,
  p_idempotency_key uuid
)
returns jsonb
language sql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
  select lws_internal.transition_project_requirement_core_v1(
    'COMPLETE', p_quote_request_id, p_project_id, p_requirement_id,
    p_expected_revision, null, p_evidence_reference, p_idempotency_key
  )
$$;

create function public.reopen_project_requirement_v1(
  p_quote_request_id uuid,
  p_project_id uuid,
  p_requirement_id uuid,
  p_expected_revision bigint,
  p_reopen_reason text,
  p_idempotency_key uuid
)
returns jsonb
language sql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
  select lws_internal.transition_project_requirement_core_v1(
    'REOPEN', p_quote_request_id, p_project_id, p_requirement_id,
    p_expected_revision, p_reopen_reason, null, p_idempotency_key
  )
$$;

revoke all on function lws_internal.transition_project_requirement_core_v1(
  text, uuid, uuid, uuid, bigint, text, jsonb, uuid
) from public, anon, authenticated, service_role;
revoke all on function public.start_project_requirement_v1(
  uuid, uuid, uuid, bigint, uuid
) from public, anon, authenticated, service_role;
revoke all on function public.block_project_requirement_v1(
  uuid, uuid, uuid, bigint, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function public.complete_project_requirement_v1(
  uuid, uuid, uuid, bigint, jsonb, uuid
) from public, anon, authenticated, service_role;
revoke all on function public.reopen_project_requirement_v1(
  uuid, uuid, uuid, bigint, text, uuid
) from public, anon, authenticated, service_role;

grant execute on function public.start_project_requirement_v1(
  uuid, uuid, uuid, bigint, uuid
) to authenticated;
grant execute on function public.block_project_requirement_v1(
  uuid, uuid, uuid, bigint, text, uuid
) to authenticated;
grant execute on function public.complete_project_requirement_v1(
  uuid, uuid, uuid, bigint, jsonb, uuid
) to authenticated;
grant execute on function public.reopen_project_requirement_v1(
  uuid, uuid, uuid, bigint, text, uuid
) to authenticated;

comment on function lws_internal.transition_project_requirement_core_v1(
  text, uuid, uuid, uuid, bigint, text, jsonb, uuid
) is 'Private serialized lifecycle authority for finalized project requirements.';