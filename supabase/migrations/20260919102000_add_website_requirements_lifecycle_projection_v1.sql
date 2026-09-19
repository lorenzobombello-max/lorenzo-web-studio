drop index public.website_requirements_one_active_context_idx;
create unique index website_requirements_one_active_context_idx
  on public.website_requirements(website_work_context_id)
  where status = 'ACTIVE';

create table public.website_requirement_command_ledger (
  operation_id uuid primary key default gen_random_uuid(),
  actor_id text not null
    check (actor_id ~ '^OPERATOR:[0-9a-f-]{36}$'),
  quote_request_id uuid not null,
  website_work_context_id uuid not null,
  requirements_board_id uuid not null,
  requirement_id uuid not null,
  command_type text not null
    check (command_type in ('START', 'BLOCK', 'COMPLETE', 'REOPEN', 'RESOLVE_SOURCE')),
  idempotency_key uuid not null,
  request_fingerprint character(64) not null
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  result jsonb not null
    check (jsonb_typeof(result) = 'object'
      and not lws_internal.website_concept_jsonb_has_forbidden_key_v1(result)),
  created_at timestamptz not null default clock_timestamp(),
  constraint website_requirement_command_ledger_requirement_fk
    foreign key (requirement_id, requirements_board_id, website_work_context_id, quote_request_id)
    references public.website_requirements(
      requirement_id, requirements_board_id, website_work_context_id, quote_request_id
    ),
  constraint website_requirement_command_ledger_actor_command_key_unique
    unique (actor_id, command_type, idempotency_key)
);

alter table public.website_requirement_command_ledger enable row level security;
alter table public.website_requirement_command_ledger force row level security;
revoke all privileges on table public.website_requirement_command_ledger
from public, anon, authenticated, service_role;

create function lws_internal.guard_website_requirement_command_ledger_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op <> 'INSERT' then
    raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_COMMAND_LEDGER_IMMUTABLE';
  end if;
  if current_setting('lws.website_requirement_lifecycle_command', true) is distinct from 'on' then
    raise exception using errcode = '55000', message = 'DIRECT_WEBSITE_REQUIREMENT_COMMAND_LEDGER_WRITE_FORBIDDEN';
  end if;
  return new;
end;
$$;

create trigger trg_website_requirement_command_ledger_guard
before insert or update or delete on public.website_requirement_command_ledger
for each row execute function lws_internal.guard_website_requirement_command_ledger_v1();

create or replace function lws_internal.guard_website_requirement_command_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if current_setting('lws.website_requirement_command', true) is distinct from 'on' then
    raise exception using errcode = '55000', message = 'DIRECT_WEBSITE_REQUIREMENT_WRITE_FORBIDDEN';
  end if;

  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_ROOT_IMMUTABLE';
  end if;

  if tg_op = 'UPDATE' then
    if new.revision <> old.revision + 1 then
      raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
    end if;

    if new.website_work_context_id is distinct from old.website_work_context_id
       or new.quote_request_id is distinct from old.quote_request_id then
      raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_IDENTITY_IMMUTABLE';
    end if;

    if tg_table_name = 'website_requirements_boards'
       and new.requirements_board_id is distinct from old.requirements_board_id then
      raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_IDENTITY_IMMUTABLE';
    end if;

    if tg_table_name = 'website_requirements' then
      if new.requirement_id is distinct from old.requirement_id
         or new.requirements_board_id is distinct from old.requirements_board_id then
        raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_IDENTITY_IMMUTABLE';
      end if;

      if old.status <> 'PENDING'
         and current_setting('lws.website_requirement_source_resolution', true) is distinct from 'on'
         and (
           new.source_key is distinct from old.source_key
           or new.source_reference is distinct from old.source_reference
           or new.source_value_sha256 is distinct from old.source_value_sha256
           or new.item_number is distinct from old.item_number
           or new.sort_order is distinct from old.sort_order
           or new.title is distinct from old.title
           or new.description is distinct from old.description
           or new.category is distinct from old.category
           or new.linked_page_or_module is distinct from old.linked_page_or_module
           or new.completion_mode is distinct from old.completion_mode
           or new.completion_rule_key is distinct from old.completion_rule_key
           or new.completion_rule_version is distinct from old.completion_rule_version
           or new.required is distinct from old.required
           or new.created_at is distinct from old.created_at
         ) then
        raise exception using errcode = '55000', message = 'STARTED_WEBSITE_REQUIREMENT_DEFINITION_IMMUTABLE';
      end if;
    end if;
  end if;

  return new;
end;
$$;

create function lws_internal.resolve_website_requirement_actor_v1(
  p_quote_request_id uuid,
  p_management_only boolean,
  p_require_aal2 boolean
)
returns table(operator_id uuid, operator_role text, actor_id text, is_management boolean)
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_assignee_id uuid;
begin
  if v_auth_user_id is null or p_quote_request_id is null then
    raise exception using errcode = '42501', message = 'WEBSITE_REQUIREMENTS_ACCESS_DENIED';
  end if;

  select operator.* into v_operator
  from public.commercial_operators as operator
  where operator.auth_user_id = v_auth_user_id
    and operator.status = 'ACTIVE';
  if not found then
    raise exception using errcode = '42501', message = 'WEBSITE_REQUIREMENTS_ACCESS_DENIED';
  end if;

  if v_operator.role not in ('owner', 'admin', 'operations_manager', 'operator') then
    raise exception using errcode = '42501', message = 'WEBSITE_REQUIREMENT_ROLE_DENIED';
  end if;
  if p_management_only and v_operator.role not in ('owner', 'operations_manager') then
    raise exception using errcode = '42501', message = 'WEBSITE_REQUIREMENT_ROLE_DENIED';
  end if;
  if not p_management_only and p_require_aal2 and v_operator.role = 'admin' then
    raise exception using errcode = '42501', message = 'WEBSITE_REQUIREMENT_ROLE_DENIED';
  end if;

  if v_operator.role = 'operator' then
    select assignment.assignee_operator_id into v_assignee_id
    from lws_internal.operator_dossier_assignments as assignment
    where assignment.quote_request_id = p_quote_request_id;
    if v_assignee_id is distinct from v_operator.operator_id then
      raise exception using errcode = '42501', message = 'WEBSITE_REQUIREMENT_ASSIGNMENT_DENIED';
    end if;
  end if;

  if p_require_aal2 and coalesce(auth.jwt()->>'aal', '') <> 'aal2' then
    raise exception using errcode = '42501', message = 'AAL2_REQUIRED';
  end if;

  return query select
    v_operator.operator_id,
    v_operator.role,
    'OPERATOR:' || v_operator.operator_id::text,
    v_operator.role in ('owner', 'operations_manager');
end;
$$;

create function lws_internal.website_requirements_progress_v1(p_website_work_context_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select jsonb_build_object(
    'required_total', count(*) filter (where required and source_review_state = 'CURRENT'),
    'required_completed', count(*) filter (where required and source_review_state = 'CURRENT' and status = 'COMPLETED'),
    'required_open', count(*) filter (where required and source_review_state = 'CURRENT' and status in ('PENDING', 'ACTIVE')),
    'required_blocked', count(*) filter (where required and source_review_state = 'CURRENT' and status = 'BLOCKED'),
    'review_pending', count(*) filter (where source_review_state in ('CHANGE_PENDING', 'REMOVAL_PENDING'))
  )
  from public.website_requirements
  where website_work_context_id = p_website_work_context_id
$$;

create function lws_internal.website_requirements_readiness_v1(p_website_work_context_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_board public.website_requirements_boards%rowtype;
  v_progress jsonb;
begin
  select * into v_board
  from public.website_requirements_boards
  where website_work_context_id = p_website_work_context_id;
  if not found then
    return jsonb_build_object('ready_for_preview', false, 'readiness', 'UNKNOWN', 'reason', 'REQUIREMENTS_BOARD_MISSING');
  end if;

  v_progress := lws_internal.website_requirements_progress_v1(p_website_work_context_id);
  if (v_progress->>'review_pending')::integer > 0 or v_board.sync_state = 'REVIEW_REQUIRED' then
    return jsonb_build_object('ready_for_preview', false, 'readiness', 'BLOCKED', 'reason', 'REQUIREMENTS_REVIEW_REQUIRED');
  elsif (v_progress->>'required_total')::integer = 0 then
    return jsonb_build_object('ready_for_preview', false, 'readiness', 'BLOCKED', 'reason', 'REQUIRED_REQUIREMENTS_MISSING');
  elsif (v_progress->>'required_blocked')::integer > 0 then
    return jsonb_build_object('ready_for_preview', false, 'readiness', 'BLOCKED', 'reason', 'REQUIRED_REQUIREMENT_BLOCKED');
  elsif (v_progress->>'required_open')::integer > 0 then
    return jsonb_build_object('ready_for_preview', false, 'readiness', 'BLOCKED', 'reason', 'REQUIRED_REQUIREMENTS_OPEN');
  end if;
  return jsonb_build_object('ready_for_preview', true, 'readiness', 'READY', 'reason', 'ALL_REQUIRED_REQUIREMENTS_COMPLETED');
end;
$$;

create function lws_internal.website_requirement_current_pass_v1(p_requirement_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select coalesce((
    select requirement.verification_result = 'PASS'
      and exists (
        select 1
        from public.website_requirement_verifications as verification
        where verification.requirement_id = requirement.requirement_id
          and verification.requirement_revision = requirement.revision
          and verification.result = 'PASS'
          and (verification.expires_at is null or verification.expires_at > clock_timestamp())
      )
    from public.website_requirements as requirement
    where requirement.requirement_id = p_requirement_id
  ), false)
$$;

create function lws_internal.website_requirement_permitted_actions_v1(
  p_requirement_id uuid,
  p_quote_request_id uuid,
  p_website_work_context_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_actor record;
  v_requirement public.website_requirements%rowtype;
  v_other_active boolean;
begin
  select * into strict v_actor
  from lws_internal.resolve_website_requirement_actor_v1(p_quote_request_id, false, false);
  select * into v_requirement
  from public.website_requirements
  where requirement_id = p_requirement_id
    and quote_request_id = p_quote_request_id
    and website_work_context_id = p_website_work_context_id;
  if not found then return '[]'::jsonb; end if;

  if v_requirement.source_review_state = 'CHANGE_PENDING' then
    return case when v_actor.is_management
      then '["accept_website_requirement_source_change","keep_existing_website_requirement_source"]'::jsonb
      else '[]'::jsonb end;
  elsif v_requirement.source_review_state = 'REMOVAL_PENDING' then
    return case when v_actor.is_management
      then '["keep_existing_website_requirement_source","retire_website_requirement_source"]'::jsonb
      else '[]'::jsonb end;
  elsif v_requirement.source_review_state <> 'CURRENT' then
    return '[]'::jsonb;
  end if;

  select exists (
    select 1 from public.website_requirements
    where website_work_context_id = p_website_work_context_id
      and status = 'ACTIVE' and requirement_id <> p_requirement_id
  ) into v_other_active;
  if v_requirement.status in ('PENDING', 'BLOCKED') then
    return case when v_other_active then '[]'::jsonb else '["start_website_requirement"]'::jsonb end;
  elsif v_requirement.status = 'ACTIVE' then
    if v_requirement.completion_mode = 'OPERATOR'
       or (v_requirement.completion_mode = 'HYBRID'
         and lws_internal.website_requirement_current_pass_v1(p_requirement_id)) then
      return '["block_website_requirement","complete_website_requirement"]'::jsonb;
    end if;
    return '["block_website_requirement"]'::jsonb;
  elsif v_requirement.status = 'COMPLETED' and v_actor.is_management then
    return '["reopen_website_requirement"]'::jsonb;
  end if;
  return '[]'::jsonb;
exception when others then
  return '[]'::jsonb;
end;
$$;

create function public.get_website_requirements_board_v1(
  p_quote_request_id uuid,
  p_website_work_context_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_actor record;
  v_context public.website_work_contexts%rowtype;
  v_board public.website_requirements_boards%rowtype;
  v_customer text;
  v_dossier_reference text;
  v_assigned_operator_id uuid;
  v_assigned_operator_name text;
  v_items jsonb := '[]'::jsonb;
  v_board_json jsonb := 'null'::jsonb;
  v_empty_state text := 'NO_BOARD';
begin
  if p_quote_request_id is null or p_website_work_context_id is null then
    raise exception using errcode = '42501', message = 'WEBSITE_REQUIREMENTS_ACCESS_DENIED';
  end if;
  select * into strict v_actor
  from lws_internal.resolve_website_requirement_actor_v1(p_quote_request_id, false, false);
  select * into v_context
  from public.website_work_contexts
  where website_work_context_id = p_website_work_context_id
    and quote_request_id = p_quote_request_id;
  if not found then
    raise exception using errcode = '42501', message = 'WEBSITE_REQUIREMENTS_ACCESS_DENIED';
  end if;

  select coalesce(nullif(btrim(request.company), ''), request.name),
    request.application_reference, assignment.assignee_operator_id, operator.display_name
  into v_customer, v_dossier_reference, v_assigned_operator_id, v_assigned_operator_name
  from public.quote_requests as request
  left join lws_internal.operator_dossier_assignments as assignment
    on assignment.quote_request_id = request.id
  left join public.commercial_operators as operator
    on operator.operator_id = assignment.assignee_operator_id
  where request.id = p_quote_request_id;

  select * into v_board
  from public.website_requirements_boards
  where website_work_context_id = p_website_work_context_id
    and quote_request_id = p_quote_request_id;
  if found then
    v_empty_state := null;
    v_board_json := jsonb_build_object(
      'requirements_board_id', v_board.requirements_board_id,
      'sync_state', v_board.sync_state,
      'revision', v_board.revision,
      'mapping_version', v_board.mapping_version,
      'current_intake_id', v_board.current_intake_id,
      'current_intake_revision', v_board.current_intake_revision,
      'current_intake_snapshot_sha256', v_board.current_intake_snapshot_sha256
    );
    select coalesce(jsonb_agg(jsonb_build_object(
      'requirement_id', requirement.requirement_id,
      'item_number', requirement.item_number,
      'title', requirement.title,
      'description', requirement.description,
      'category', requirement.category,
      'source', jsonb_build_object(
        'authority_type', requirement.source_reference->>'authority_type',
        'source_key', requirement.source_key,
        'intake_id', requirement.source_reference->'intake_id',
        'intake_revision', requirement.source_reference->'intake_revision',
        'submitted_at', requirement.source_reference->'submitted_at',
        'mapping_version', requirement.source_reference->'mapping_version'
      ),
      'linked_page_or_module', requirement.linked_page_or_module,
      'status', requirement.status,
      'completion_mode', requirement.completion_mode,
      'sort_order', requirement.sort_order,
      'required', requirement.required,
      'started_at', requirement.started_at,
      'completed_at', requirement.completed_at,
      'verification_result', requirement.verification_result,
      'blocked_reason', requirement.blocked_reason,
      'revision', requirement.revision,
      'source_review_state', requirement.source_review_state,
      'permitted_actions', lws_internal.website_requirement_permitted_actions_v1(
        requirement.requirement_id, p_quote_request_id, p_website_work_context_id
      )
    ) order by requirement.sort_order, requirement.item_number), '[]'::jsonb)
    into v_items
    from public.website_requirements as requirement
    where requirement.requirements_board_id = v_board.requirements_board_id;
  end if;

  return jsonb_build_object(
    'contract_version', 1,
    'quote_request_id', p_quote_request_id,
    'website_work_context_id', p_website_work_context_id,
    'project_id', v_context.project_id,
    'phase', v_context.phase,
    'context', jsonb_build_object(
      'customer', v_customer,
      'dossier_reference', v_dossier_reference,
      'assigned_operator', case when v_assigned_operator_id is null then 'null'::jsonb
        else jsonb_build_object('operator_id', v_assigned_operator_id, 'display_name', v_assigned_operator_name) end
    ),
    'board', v_board_json,
    'items', v_items,
    'progress', lws_internal.website_requirements_progress_v1(p_website_work_context_id),
    'readiness', lws_internal.website_requirements_readiness_v1(p_website_work_context_id),
    'empty_state', v_empty_state
  );
end;
$$;

create function lws_internal.transition_website_requirement_core_v1(
  p_command text,
  p_quote_request_id uuid,
  p_website_work_context_id uuid,
  p_requirement_id uuid,
  p_expected_revision bigint,
  p_reason text,
  p_attestation jsonb,
  p_resolution text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_actor record;
  v_context public.website_work_contexts%rowtype;
  v_board public.website_requirements_boards%rowtype;
  v_requirement public.website_requirements%rowtype;
  v_existing public.website_requirement_command_ledger%rowtype;
  v_sync_run public.website_requirement_sync_runs%rowtype;
  v_proposal jsonb;
  v_proposal_count integer;
  v_reason text;
  v_attestation text;
  v_canonical_attestation jsonb;
  v_fingerprint text;
  v_result jsonb;
  v_actor_id text;
  v_previous_status text;
  v_previous_source_review_state text;
  v_previous_revision bigint;
  v_event_type text;
  v_evidence_invalidated boolean := false;
  v_sync_run_id uuid;
  v_new_sync_state text;
begin
  if p_command not in ('START', 'BLOCK', 'COMPLETE', 'REOPEN', 'RESOLVE_SOURCE')
     or p_quote_request_id is null or p_website_work_context_id is null
     or p_requirement_id is null or p_expected_revision is null or p_expected_revision < 1
     or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REQUIREMENT_COMMAND';
  end if;
  if p_command = 'RESOLVE_SOURCE'
     and p_resolution not in ('ACCEPT_CHANGE', 'KEEP_EXISTING', 'RETIRE') then
    raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REQUIREMENT_SOURCE_RESOLUTION';
  end if;

  select * into strict v_actor
  from lws_internal.resolve_website_requirement_actor_v1(
    p_quote_request_id, p_command in ('REOPEN', 'RESOLVE_SOURCE'), true
  );
  v_actor_id := v_actor.actor_id;

  v_reason := lws_internal.website_requirements_normalize_text_v1(p_reason);
  if p_command = 'BLOCK' and (v_reason is null or char_length(v_reason) > 500) then
    raise exception using errcode = '22023', message = 'WEBSITE_REQUIREMENT_BLOCK_REASON_REQUIRED';
  elsif p_command in ('REOPEN', 'RESOLVE_SOURCE') and (v_reason is null or char_length(v_reason) > 500) then
    raise exception using errcode = '22023', message = 'WEBSITE_REQUIREMENT_REOPEN_REASON_REQUIRED';
  end if;

  if p_command = 'COMPLETE' then
    if p_attestation is null or jsonb_typeof(p_attestation) <> 'object'
       or (select array_agg(key order by key) from jsonb_object_keys(p_attestation) as fields(key))
          is distinct from array['attestation']::text[] then
      raise exception using errcode = '22023', message = 'WEBSITE_REQUIREMENT_ATTESTATION_REQUIRED';
    end if;
    v_attestation := lws_internal.website_requirements_normalize_text_v1(p_attestation->>'attestation');
    if v_attestation is null or char_length(v_attestation) > 500 then
      raise exception using errcode = '22023', message = 'WEBSITE_REQUIREMENT_ATTESTATION_REQUIRED';
    end if;
    v_canonical_attestation := jsonb_build_object('attestation', v_attestation);
  end if;

  v_fingerprint := lws_internal.website_requirements_sha256_hex_v1(jsonb_build_array(
    1, v_actor_id, p_command, p_quote_request_id, p_website_work_context_id,
    p_requirement_id, p_expected_revision, v_reason, v_canonical_attestation, p_resolution
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(v_actor_id || ':' || p_command || ':' || p_idempotency_key::text, 0));

  select * into v_existing
  from public.website_requirement_command_ledger
  where actor_id = v_actor_id and command_type = p_command and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'WEBSITE_REQUIREMENT_IDEMPOTENCY_CONFLICT';
    end if;
    return (v_existing.result - 'replayed') || jsonb_build_object('replayed', true);
  end if;

  select * into v_context
  from public.website_work_contexts
  where website_work_context_id = p_website_work_context_id
    and quote_request_id = p_quote_request_id
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'WEBSITE_REQUIREMENTS_ACCESS_DENIED';
  end if;
  select * into v_board
  from public.website_requirements_boards
  where website_work_context_id = p_website_work_context_id
    and quote_request_id = p_quote_request_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_REQUIREMENTS_BOARD_NOT_FOUND';
  end if;
  select * into v_requirement
  from public.website_requirements
  where requirement_id = p_requirement_id
    and requirements_board_id = v_board.requirements_board_id
    and website_work_context_id = p_website_work_context_id
    and quote_request_id = p_quote_request_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_REQUIREMENT_NOT_FOUND';
  end if;
  if v_requirement.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;

  v_previous_status := v_requirement.status;
  v_previous_source_review_state := v_requirement.source_review_state;
  v_previous_revision := v_requirement.revision;

  if p_command <> 'RESOLVE_SOURCE' and v_requirement.source_review_state <> 'CURRENT' then
    raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_SOURCE_REVIEW_REQUIRED';
  end if;

  perform set_config('lws.website_requirement_command', 'on', true);
  perform set_config('lws.website_requirement_history_command', 'on', true);
  perform set_config('lws.website_requirement_lifecycle_command', 'on', true);

  if p_command = 'START' then
    if v_requirement.status not in ('PENDING', 'BLOCKED') then
      raise exception using errcode = '55000', message = 'INVALID_WEBSITE_REQUIREMENT_TRANSITION';
    end if;
    if exists (
      select 1 from public.website_requirements
      where requirements_board_id = v_board.requirements_board_id
        and status = 'ACTIVE' and requirement_id <> p_requirement_id
    ) then
      raise exception using errcode = 'P0001', message = 'WEBSITE_ACTIVE_REQUIREMENT_CONFLICT';
    end if;
    update public.website_requirements set
      status = 'ACTIVE',
      started_at = coalesce(started_at, clock_timestamp()),
      blocked_reason = null,
      revision = revision + 1,
      updated_at = clock_timestamp()
    where requirement_id = p_requirement_id returning * into v_requirement;
    v_event_type := 'WEBSITE_REQUIREMENT_STARTED';
  elsif p_command = 'BLOCK' then
    if v_requirement.status <> 'ACTIVE' then
      raise exception using errcode = '55000', message = 'INVALID_WEBSITE_REQUIREMENT_TRANSITION';
    end if;
    update public.website_requirements set
      status = 'BLOCKED', blocked_reason = v_reason,
      revision = revision + 1, updated_at = clock_timestamp()
    where requirement_id = p_requirement_id returning * into v_requirement;
    v_event_type := 'WEBSITE_REQUIREMENT_BLOCKED';
  elsif p_command = 'COMPLETE' then
    if v_requirement.status <> 'ACTIVE' then
      raise exception using errcode = '55000', message = 'INVALID_WEBSITE_REQUIREMENT_TRANSITION';
    end if;
    if v_requirement.completion_mode = 'HYBRID'
       and not lws_internal.website_requirement_current_pass_v1(p_requirement_id) then
      raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_VERIFICATION_REQUIRED';
    elsif v_requirement.completion_mode not in ('OPERATOR', 'HYBRID') then
      raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_VERIFICATION_REQUIRED';
    end if;
    update public.website_requirements set
      status = 'COMPLETED', completed_at = clock_timestamp(),
      completed_by = v_actor_id, evidence_summary = v_canonical_attestation,
      verification_result = case when completion_mode = 'OPERATOR' then 'NOT_APPLICABLE' else verification_result end,
      blocked_reason = null, revision = revision + 1, updated_at = clock_timestamp()
    where requirement_id = p_requirement_id returning * into v_requirement;
    v_event_type := 'WEBSITE_REQUIREMENT_COMPLETED';
  elsif p_command = 'REOPEN' then
    if v_requirement.status <> 'COMPLETED' then
      raise exception using errcode = '55000', message = 'INVALID_WEBSITE_REQUIREMENT_TRANSITION';
    end if;
    v_evidence_invalidated := v_requirement.evidence_summary is not null
      or v_requirement.verification_result = 'PASS';
    update public.website_requirements set
      status = 'PENDING', started_at = null, blocked_reason = null,
      completed_at = null, completed_by = null, evidence_summary = null,
      verification_result = case when completion_mode = 'OPERATOR' then 'NOT_APPLICABLE' else 'UNKNOWN' end,
      revision = revision + 1, updated_at = clock_timestamp()
    where requirement_id = p_requirement_id returning * into v_requirement;
    v_event_type := 'WEBSITE_REQUIREMENT_REOPENED';
  else
    if (v_requirement.source_review_state = 'CHANGE_PENDING' and p_resolution not in ('ACCEPT_CHANGE', 'KEEP_EXISTING'))
       or (v_requirement.source_review_state = 'REMOVAL_PENDING' and p_resolution not in ('KEEP_EXISTING', 'RETIRE'))
       or v_requirement.source_review_state not in ('CHANGE_PENDING', 'REMOVAL_PENDING') then
      raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_SOURCE_STATE_MISMATCH';
    end if;

    select sync_run.* into v_sync_run
    from public.website_requirement_sync_runs as sync_run
    where sync_run.requirements_board_id = v_board.requirements_board_id
      and sync_run.website_work_context_id = p_website_work_context_id
      and sync_run.quote_request_id = p_quote_request_id
      and sync_run.intake_id = v_board.current_intake_id
      and sync_run.intake_revision = v_board.current_intake_revision
      and sync_run.intake_snapshot_sha256 = v_board.current_intake_snapshot_sha256
      and sync_run.mapping_version = v_board.mapping_version
    order by sync_run.created_at desc, sync_run.sync_run_id desc
    limit 1 for update;
    if not found then
      raise exception using errcode = 'P0001', message = 'WEBSITE_REQUIREMENT_SOURCE_PROPOSAL_NOT_FOUND';
    end if;
    select count(*), min(value::text)::jsonb
    into v_proposal_count, v_proposal
    from jsonb_array_elements(v_sync_run.proposed_changes) as proposals(value)
    where value->>'requirement_id' = p_requirement_id::text
      and value->>'source_key' = v_requirement.source_key;
    if v_proposal_count <> 1 or v_proposal is null then
      raise exception using errcode = 'P0001', message = 'WEBSITE_REQUIREMENT_SOURCE_PROPOSAL_NOT_FOUND';
    end if;
    if (v_requirement.source_review_state = 'CHANGE_PENDING' and v_proposal->>'action' <> 'CHANGE_PENDING')
       or (v_requirement.source_review_state = 'REMOVAL_PENDING' and v_proposal->>'action' <> 'REMOVAL_PENDING') then
      raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_SOURCE_STATE_MISMATCH';
    end if;
    v_sync_run_id := v_sync_run.sync_run_id;
    perform set_config('lws.website_requirement_source_resolution', 'on', true);

    if p_resolution = 'ACCEPT_CHANGE' then
      if v_proposal->'proposed_definition' is null
         or jsonb_typeof(v_proposal->'proposed_definition') <> 'object'
         or coalesce(v_proposal->>'proposed_source_value_sha256', '') !~ '^[0-9a-f]{64}$' then
        raise exception using errcode = 'P0001', message = 'WEBSITE_REQUIREMENT_SOURCE_PROPOSAL_NOT_FOUND';
      end if;
      v_evidence_invalidated := v_requirement.status <> 'PENDING'
        or v_requirement.evidence_summary is not null
        or v_requirement.verification_result in ('PASS', 'FAIL');
      update public.website_requirements set
        source_reference = v_proposal->'proposed_definition'->'source_reference',
        source_value_sha256 = v_proposal->>'proposed_source_value_sha256',
        title = v_proposal->'proposed_definition'->>'title',
        description = v_proposal->'proposed_definition'->>'description',
        category = v_proposal->'proposed_definition'->>'category',
        linked_page_or_module = nullif(v_proposal->'proposed_definition'->>'linked_page_or_module', 'null'),
        required = (v_proposal->'proposed_definition'->>'required')::boolean,
        completion_mode = v_proposal->'proposed_definition'->>'completion_mode',
        completion_rule_key = nullif(v_proposal->'proposed_definition'->>'completion_rule_key', 'null'),
        completion_rule_version = nullif(v_proposal->'proposed_definition'->>'completion_rule_version', 'null')::integer,
        source_review_state = 'CURRENT', status = 'PENDING',
        started_at = null, blocked_reason = null, completed_at = null, completed_by = null,
        evidence_summary = null,
        verification_result = case when v_proposal->'proposed_definition'->>'completion_mode' = 'OPERATOR' then 'NOT_APPLICABLE' else 'UNKNOWN' end,
        revision = revision + 1, updated_at = clock_timestamp()
      where requirement_id = p_requirement_id returning * into v_requirement;
      v_event_type := 'WEBSITE_REQUIREMENT_SOURCE_CHANGE_ACCEPTED';
    elsif p_resolution = 'KEEP_EXISTING' then
      update public.website_requirements set
        source_review_state = 'CURRENT', revision = revision + 1, updated_at = clock_timestamp()
      where requirement_id = p_requirement_id returning * into v_requirement;
      v_event_type := 'WEBSITE_REQUIREMENT_SOURCE_KEPT';
    else
      v_evidence_invalidated := v_requirement.status in ('ACTIVE', 'BLOCKED')
        and (v_requirement.evidence_summary is not null or v_requirement.verification_result in ('PASS', 'FAIL'));
      update public.website_requirements set
        source_review_state = 'RETIRED', required = false,
        status = case when status in ('ACTIVE', 'BLOCKED') then 'PENDING' else status end,
        started_at = case when status in ('ACTIVE', 'BLOCKED') then null else started_at end,
        blocked_reason = case when status in ('ACTIVE', 'BLOCKED') then null else blocked_reason end,
        evidence_summary = case when status in ('ACTIVE', 'BLOCKED') then null else evidence_summary end,
        verification_result = case when status in ('ACTIVE', 'BLOCKED')
          then case when completion_mode = 'OPERATOR' then 'NOT_APPLICABLE' else 'UNKNOWN' end
          else verification_result end,
        revision = revision + 1, updated_at = clock_timestamp()
      where requirement_id = p_requirement_id returning * into v_requirement;
      v_event_type := 'WEBSITE_REQUIREMENT_RETIRED';
    end if;
    perform set_config('lws.website_requirement_source_resolution', '', true);

    select case when exists (
      select 1 from public.website_requirements
      where requirements_board_id = v_board.requirements_board_id
        and source_review_state in ('CHANGE_PENDING', 'REMOVAL_PENDING')
    ) then 'REVIEW_REQUIRED' else 'CURRENT' end into v_new_sync_state;
  end if;

  update public.website_requirements_boards set
    sync_state = coalesce(v_new_sync_state, sync_state),
    revision = revision + 1, updated_at = clock_timestamp()
  where requirements_board_id = v_board.requirements_board_id
  returning * into v_board;

  insert into public.website_requirement_events(
    requirements_board_id, website_work_context_id, quote_request_id, requirement_id,
    event_type, actor_id, command_id, prior_revision, new_revision, reason, metadata
  ) values (
    v_board.requirements_board_id, p_website_work_context_id, p_quote_request_id, p_requirement_id,
    v_event_type, v_actor_id, p_idempotency_key, v_previous_revision, v_requirement.revision,
    case when p_command in ('BLOCK', 'REOPEN', 'RESOLVE_SOURCE') then v_reason else null end,
    jsonb_build_object(
      'requirements_board_id', v_board.requirements_board_id,
      'requirement_id', p_requirement_id,
      'source_key', v_requirement.source_key,
      'previous_status', v_previous_status,
      'new_status', v_requirement.status,
      'previous_source_review_state', v_previous_source_review_state,
      'new_source_review_state', v_requirement.source_review_state,
      'previous_revision', v_previous_revision,
      'new_revision', v_requirement.revision,
      'board_revision', v_board.revision,
      'reason', case when p_command in ('BLOCK', 'REOPEN', 'RESOLVE_SOURCE') then to_jsonb(v_reason) else 'null'::jsonb end,
      'resolution', case when p_command = 'RESOLVE_SOURCE' then to_jsonb(p_resolution) else 'null'::jsonb end,
      'sync_run_id', case when v_sync_run_id is null then 'null'::jsonb else to_jsonb(v_sync_run_id) end
    )
  );

  if v_evidence_invalidated then
    insert into public.website_requirement_events(
      requirements_board_id, website_work_context_id, quote_request_id, requirement_id,
      event_type, actor_id, command_id, prior_revision, new_revision, reason, metadata
    ) values (
      v_board.requirements_board_id, p_website_work_context_id, p_quote_request_id, p_requirement_id,
      'WEBSITE_REQUIREMENT_EVIDENCE_INVALIDATED', v_actor_id, p_idempotency_key,
      v_previous_revision, v_requirement.revision, v_reason,
      jsonb_build_object(
        'requirements_board_id', v_board.requirements_board_id,
        'requirement_id', p_requirement_id,
        'source_key', v_requirement.source_key,
        'previous_status', v_previous_status,
        'new_status', v_requirement.status,
        'previous_source_review_state', v_previous_source_review_state,
        'new_source_review_state', v_requirement.source_review_state,
        'previous_revision', v_previous_revision,
        'new_revision', v_requirement.revision,
        'board_revision', v_board.revision,
        'reason', case when v_reason is null then 'null'::jsonb else to_jsonb(v_reason) end,
        'resolution', case when p_command = 'RESOLVE_SOURCE' then to_jsonb(p_resolution) else 'null'::jsonb end,
        'sync_run_id', case when v_sync_run_id is null then 'null'::jsonb else to_jsonb(v_sync_run_id) end
      )
    );
  end if;

  v_result := jsonb_build_object(
    'contract_version', 1,
    'command', p_command,
    'quote_request_id', p_quote_request_id,
    'website_work_context_id', p_website_work_context_id,
    'requirements_board_id', v_board.requirements_board_id,
    'requirement_id', p_requirement_id,
    'previous_status', v_previous_status,
    'status', v_requirement.status,
    'previous_source_review_state', v_previous_source_review_state,
    'source_review_state', v_requirement.source_review_state,
    'resolution', case when p_command = 'RESOLVE_SOURCE' then to_jsonb(p_resolution) else 'null'::jsonb end,
    'requirement_revision', v_requirement.revision,
    'board_revision', v_board.revision,
    'replayed', false
  );
  insert into public.website_requirement_command_ledger(
    actor_id, quote_request_id, website_work_context_id, requirements_board_id,
    requirement_id, command_type, idempotency_key, request_fingerprint, result
  ) values (
    v_actor_id, p_quote_request_id, p_website_work_context_id, v_board.requirements_board_id,
    p_requirement_id, p_command, p_idempotency_key, v_fingerprint, v_result
  );
  return v_result;
end;
$$;

create function public.start_website_requirement_v1(
  p_quote_request_id uuid, p_website_work_context_id uuid, p_requirement_id uuid,
  p_expected_revision bigint, p_idempotency_key uuid
) returns jsonb language sql security definer
set search_path = lws_internal, pg_catalog
as $$ select lws_internal.transition_website_requirement_core_v1(
  'START', p_quote_request_id, p_website_work_context_id, p_requirement_id,
  p_expected_revision, null, null, null, p_idempotency_key
) $$;

create function public.block_website_requirement_v1(
  p_quote_request_id uuid, p_website_work_context_id uuid, p_requirement_id uuid,
  p_expected_revision bigint, p_reason text, p_idempotency_key uuid
) returns jsonb language sql security definer
set search_path = lws_internal, pg_catalog
as $$ select lws_internal.transition_website_requirement_core_v1(
  'BLOCK', p_quote_request_id, p_website_work_context_id, p_requirement_id,
  p_expected_revision, p_reason, null, null, p_idempotency_key
) $$;

create function public.complete_website_requirement_v1(
  p_quote_request_id uuid, p_website_work_context_id uuid, p_requirement_id uuid,
  p_expected_revision bigint, p_attestation jsonb, p_idempotency_key uuid
) returns jsonb language sql security definer
set search_path = lws_internal, pg_catalog
as $$ select lws_internal.transition_website_requirement_core_v1(
  'COMPLETE', p_quote_request_id, p_website_work_context_id, p_requirement_id,
  p_expected_revision, null, p_attestation, null, p_idempotency_key
) $$;

create function public.reopen_website_requirement_v1(
  p_quote_request_id uuid, p_website_work_context_id uuid, p_requirement_id uuid,
  p_expected_revision bigint, p_reason text, p_idempotency_key uuid
) returns jsonb language sql security definer
set search_path = lws_internal, pg_catalog
as $$ select lws_internal.transition_website_requirement_core_v1(
  'REOPEN', p_quote_request_id, p_website_work_context_id, p_requirement_id,
  p_expected_revision, p_reason, null, null, p_idempotency_key
) $$;

create function public.resolve_website_requirement_source_change_v1(
  p_quote_request_id uuid, p_website_work_context_id uuid, p_requirement_id uuid,
  p_expected_revision bigint, p_resolution text, p_reason text, p_idempotency_key uuid
) returns jsonb language sql security definer
set search_path = lws_internal, pg_catalog
as $$ select lws_internal.transition_website_requirement_core_v1(
  'RESOLVE_SOURCE', p_quote_request_id, p_website_work_context_id, p_requirement_id,
  p_expected_revision, p_reason, null, p_resolution, p_idempotency_key
) $$;

revoke all on function lws_internal.guard_website_requirement_command_ledger_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.resolve_website_requirement_actor_v1(uuid, boolean, boolean)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_progress_v1(uuid)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_readiness_v1(uuid)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirement_current_pass_v1(uuid)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirement_permitted_actions_v1(uuid, uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.transition_website_requirement_core_v1(
  text, uuid, uuid, uuid, bigint, text, jsonb, text, uuid
) from public, anon, authenticated, service_role;

revoke all on function public.get_website_requirements_board_v1(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.start_website_requirement_v1(uuid, uuid, uuid, bigint, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.block_website_requirement_v1(uuid, uuid, uuid, bigint, text, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.complete_website_requirement_v1(uuid, uuid, uuid, bigint, jsonb, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.reopen_website_requirement_v1(uuid, uuid, uuid, bigint, text, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.resolve_website_requirement_source_change_v1(uuid, uuid, uuid, bigint, text, text, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.get_website_requirements_board_v1(uuid, uuid) to authenticated;
grant execute on function public.start_website_requirement_v1(uuid, uuid, uuid, bigint, uuid) to authenticated;
grant execute on function public.block_website_requirement_v1(uuid, uuid, uuid, bigint, text, uuid) to authenticated;
grant execute on function public.complete_website_requirement_v1(uuid, uuid, uuid, bigint, jsonb, uuid) to authenticated;
grant execute on function public.reopen_website_requirement_v1(uuid, uuid, uuid, bigint, text, uuid) to authenticated;
grant execute on function public.resolve_website_requirement_source_change_v1(uuid, uuid, uuid, bigint, text, text, uuid) to authenticated;