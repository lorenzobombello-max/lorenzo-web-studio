create table public.project_requirement_verifications (
  verification_id uuid primary key default gen_random_uuid(),
  requirement_id uuid not null,
  project_id uuid not null,
  requirement_revision bigint not null check (requirement_revision > 0),
  rule_key text not null check (rule_key ~ '^[a-z][a-z0-9_]{0,63}$'),
  rule_version integer not null check (rule_version > 0),
  result text not null check (result in ('PASS', 'FAIL', 'UNKNOWN')),
  evidence_reference jsonb not null check (jsonb_typeof(evidence_reference) = 'object'),
  input_sha256 char(64) not null check (input_sha256 ~ '^[0-9a-f]{64}$'),
  verified_by text not null check (verified_by = 'SYSTEM:requirements_verifier'),
  verified_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz,
  constraint project_requirement_verifications_requirement_fk
    foreign key (requirement_id, project_id)
    references public.project_requirements(requirement_id, project_id),
  constraint project_requirement_verifications_expiry_valid
    check (expires_at is null or expires_at > verified_at)
);

create index project_requirement_verifications_current_idx
  on public.project_requirement_verifications(requirement_id, verified_at desc);

alter table public.project_requirement_verifications enable row level security;
alter table public.project_requirement_verifications force row level security;

create function lws_internal.guard_project_requirement_verification_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op <> 'INSERT' then
    raise exception using errcode = '55000', message = 'REQUIREMENT_VERIFICATION_IMMUTABLE';
  end if;
  if current_setting('lws.requirement_verification_command', true) is distinct from 'on' then
    raise exception using errcode = '55000', message = 'DIRECT_REQUIREMENT_VERIFICATION_FORBIDDEN';
  end if;
  return new;
end;
$$;

create trigger trg_project_requirement_verification_guard
before insert or update or delete on public.project_requirement_verifications
for each row execute function lws_internal.guard_project_requirement_verification_v1();

create function lws_internal.project_requirement_rule_v1(
  p_rule_key text,
  p_rule_version integer
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when p_rule_key = 'website_test_run' and p_rule_version = 1 then
      '{"evidence_type":"TEST_RUN","modes":["AUTO","HYBRID"],"freshness_hours":24,"verifier":"SYSTEM:requirements_verifier"}'::jsonb
    when p_rule_key = 'project_work_started' and p_rule_version = 1 then
      '{"evidence_type":"COMMERCIAL_EVENT","modes":["EXTERNAL"],"event_type":"PROJECT_WORK_STARTED","verifier":"SYSTEM:requirements_verifier"}'::jsonb
    else null
  end
$$;

create function lws_internal.project_requirement_verification_is_current_v1(
  p_requirement_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_requirement public.project_requirements%rowtype;
  v_verification public.project_requirement_verifications%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
begin
  select * into v_requirement
  from public.project_requirements
  where requirement_id = p_requirement_id;
  if not found then
    return false;
  end if;
  if v_requirement.completion_mode = 'OPERATOR' then
    return v_requirement.status = 'COMPLETED'
      and v_requirement.verification_result = 'NOT_APPLICABLE'
      and public.jsonb_has_exact_keys(v_requirement.evidence_reference, array['attestation'])
      and char_length(btrim(v_requirement.evidence_reference->>'attestation')) between 1 and 500;
  end if;

  select * into v_verification
  from public.project_requirement_verifications
  where requirement_id = p_requirement_id
    and project_id = v_requirement.project_id
  order by verified_at desc, verification_id desc
  limit 1;
  if not found or v_verification.result <> 'PASS'
     or v_verification.rule_key <> v_requirement.completion_rule_key
     or v_verification.rule_version <> v_requirement.completion_rule_version
     or (v_verification.expires_at is not null and v_verification.expires_at <= clock_timestamp()) then
    return false;
  end if;

  if v_verification.evidence_reference->>'evidence_type' = 'TEST_RUN' then
    select * into v_workspace
    from public.website_execution_workspaces
    where project_id = v_requirement.project_id;
    return found
      and v_workspace.website_workspace_id::text = v_verification.evidence_reference->>'website_workspace_id'
      and v_workspace.binding_revision::text = v_verification.evidence_reference->>'binding_revision'
      and coalesce(v_workspace.preview_branch, v_workspace.default_branch) = v_verification.evidence_reference->>'branch'
      and v_workspace.last_commit_sha = v_verification.evidence_reference->>'commit_sha';
  end if;

  if v_verification.evidence_reference->>'evidence_type' = 'COMMERCIAL_EVENT' then
    return exists (
      select 1
      from public.audit_events
      where audit_event_id::text = v_verification.evidence_reference->>'event_id'
        and project_id = v_requirement.project_id
        and event_type = v_verification.evidence_reference->>'event_type'
        and event_type = 'PROJECT_WORK_STARTED'
    );
  end if;
  return false;
end;
$$;

create function lws_internal.guard_project_requirement_completion_mode_v1()
returns trigger
language plpgsql
security definer
set search_path = public, lws_internal, pg_catalog
as $$
begin
  if new.status <> 'COMPLETED' or old.status = 'COMPLETED' then
    return new;
  end if;
  if new.completion_mode = 'OPERATOR' then
    return new;
  end if;
  if new.completion_mode = 'HYBRID' then
    if new.completed_by !~ '^OPERATOR:'
       or old.verification_result <> 'PASS'
       or not lws_internal.project_requirement_verification_is_current_v1(old.requirement_id)
       or not public.jsonb_has_exact_keys(new.evidence_reference, array['attestation'])
       or char_length(btrim(new.evidence_reference->>'attestation')) not between 1 and 500 then
      raise exception using errcode = '55000', message = 'REQUIREMENT_VERIFICATION_REQUIRED';
    end if;
    return new;
  end if;
  if new.completed_by <> 'SYSTEM:requirements_verifier'
     or new.verification_result <> 'PASS' then
    raise exception using errcode = '55000', message = 'REQUIREMENT_VERIFICATION_REQUIRED';
  end if;
  return new;
end;
$$;

create trigger trg_project_requirement_completion_mode_guard
before update on public.project_requirements
for each row execute function lws_internal.guard_project_requirement_completion_mode_v1();

create function public.record_project_requirement_verification_v1(
  p_quote_request_id uuid,
  p_project_id uuid,
  p_requirement_id uuid,
  p_expected_revision bigint,
  p_rule_key text,
  p_rule_version integer,
  p_result text,
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
  v_actor constant text := 'SYSTEM:requirements_verifier';
  v_rule jsonb;
  v_requirement public.project_requirements%rowtype;
  v_board public.project_requirements_boards%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_existing public.idempotency_ledger%rowtype;
  v_verification public.project_requirement_verifications%rowtype;
  v_fingerprint char(64);
  v_observed_at timestamptz;
  v_expires_at timestamptz;
  v_input_sha256 char(64);
  v_result jsonb;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'TRUSTED_VERIFIER_REQUIRED';
  end if;
  if p_quote_request_id is null or p_project_id is null or p_requirement_id is null
     or p_expected_revision is null or p_expected_revision < 1
     or p_idempotency_key is null or p_result not in ('PASS', 'FAIL', 'UNKNOWN')
     or jsonb_typeof(p_evidence_reference) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'INVALID_REQUIREMENT_VERIFICATION_COMMAND';
  end if;
  v_rule := lws_internal.project_requirement_rule_v1(p_rule_key, p_rule_version);
  if v_rule is null then
    raise exception using errcode = '22023', message = 'UNKNOWN_REQUIREMENT_RULE';
  end if;

  if p_evidence_reference->>'evidence_type' = 'TEST_RUN' then
    if not public.jsonb_has_exact_keys(p_evidence_reference, array[
      'evidence_type', 'website_workspace_id', 'binding_revision', 'branch',
      'commit_sha', 'suite_id', 'contract_version', 'observed_at'
    ]) or v_rule->>'evidence_type' <> 'TEST_RUN'
       or p_evidence_reference->>'website_workspace_id' !~ '^[0-9a-f-]{36}$'
       or p_evidence_reference->>'binding_revision' !~ '^[1-9][0-9]*$'
       or p_evidence_reference->>'commit_sha' !~ '^[0-9a-f]{40}$'
       or char_length(btrim(p_evidence_reference->>'suite_id')) not between 1 and 80
       or p_evidence_reference->>'contract_version' !~ '^[1-9][0-9]*$' then
      raise exception using errcode = '22023', message = 'INVALID_VERIFICATION_EVIDENCE';
    end if;
    begin
      v_observed_at := (p_evidence_reference->>'observed_at')::timestamptz;
    exception when others then
      raise exception using errcode = '22023', message = 'INVALID_VERIFICATION_EVIDENCE';
    end;
    if v_observed_at > clock_timestamp() + interval '5 minutes'
       or v_observed_at <= clock_timestamp() - interval '24 hours' then
      raise exception using errcode = '22023', message = 'VERIFICATION_STALE';
    end if;
    v_expires_at := v_observed_at + interval '24 hours';
  elsif p_evidence_reference->>'evidence_type' = 'COMMERCIAL_EVENT' then
    if not public.jsonb_has_exact_keys(
      p_evidence_reference, array['evidence_type', 'event_id', 'event_type']
    ) or v_rule->>'evidence_type' <> 'COMMERCIAL_EVENT'
       or p_evidence_reference->>'event_id' !~ '^[1-9][0-9]*$'
       or p_evidence_reference->>'event_type' <> v_rule->>'event_type' then
      raise exception using errcode = '22023', message = 'INVALID_VERIFICATION_EVIDENCE';
    end if;
  else
    raise exception using errcode = '22023', message = 'INVALID_VERIFICATION_EVIDENCE';
  end if;

  v_fingerprint := lws_internal.commercial_fingerprint_v1(jsonb_build_object(
    'contract_version', 1, 'actor', v_actor,
    'quote_request_id', p_quote_request_id, 'project_id', p_project_id,
    'requirement_id', p_requirement_id, 'expected_revision', p_expected_revision,
    'rule_key', p_rule_key, 'rule_version', p_rule_version,
    'result', p_result, 'evidence_reference', p_evidence_reference
  ));
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing
  from public.idempotency_ledger
  where actor_id = v_actor and project_id = p_project_id
    and command_type = 'record_project_requirement_verification'
    and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed', true);
  end if;

  perform 1 from public.commercial_projects where project_id = p_project_id for update;
  select * into v_requirement
  from public.project_requirements
  where requirement_id = p_requirement_id and project_id = p_project_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'PROJECT_REQUIREMENT_NOT_FOUND';
  end if;
  select * into v_board
  from public.project_requirements_boards
  where requirements_board_id = v_requirement.requirements_board_id
    and project_id = p_project_id and quote_request_id = p_quote_request_id;
  if not found then
    raise exception using errcode = '42501', message = 'PROJECT_REQUIREMENT_BINDING_DENIED';
  end if;
  if v_board.status <> 'FINALIZED' then
    raise exception using errcode = '55000', message = 'REQUIREMENTS_BOARD_NOT_FINALIZED';
  end if;
  if v_requirement.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;
  if v_requirement.completion_rule_key <> p_rule_key
     or v_requirement.completion_rule_version <> p_rule_version
     or not (v_rule->'modes' ? v_requirement.completion_mode) then
    raise exception using errcode = '23514', message = 'REQUIREMENT_RULE_MISMATCH';
  end if;

  if p_evidence_reference->>'evidence_type' = 'TEST_RUN' then
    select * into v_workspace
    from public.website_execution_workspaces
    where project_id = p_project_id and quote_request_id = p_quote_request_id;
    if not found
       or v_workspace.website_workspace_id::text <> p_evidence_reference->>'website_workspace_id'
       or v_workspace.binding_revision::text <> p_evidence_reference->>'binding_revision'
       or coalesce(v_workspace.preview_branch, v_workspace.default_branch) <> p_evidence_reference->>'branch'
       or v_workspace.last_commit_sha <> p_evidence_reference->>'commit_sha' then
      raise exception using errcode = '23514', message = 'VERIFICATION_WORKSPACE_MISMATCH';
    end if;
  elsif not exists (
    select 1 from public.audit_events
    where audit_event_id::text = p_evidence_reference->>'event_id'
      and project_id = p_project_id
      and event_type = p_evidence_reference->>'event_type'
  ) then
    raise exception using errcode = '23514', message = 'VERIFICATION_EVENT_MISMATCH';
  end if;

  v_input_sha256 := lws_internal.commercial_fingerprint_v1(jsonb_build_object(
    'project_id', p_project_id, 'requirement_id', p_requirement_id,
    'rule_key', p_rule_key, 'rule_version', p_rule_version,
    'evidence_reference', p_evidence_reference
  ));
  perform set_config('lws.requirement_verification_command', 'on', true);
  insert into public.project_requirement_verifications(
    requirement_id, project_id, requirement_revision, rule_key, rule_version,
    result, evidence_reference, input_sha256, verified_by, verified_at, expires_at
  ) values (
    p_requirement_id, p_project_id, p_expected_revision, p_rule_key, p_rule_version,
    p_result, p_evidence_reference, v_input_sha256, v_actor, clock_timestamp(), v_expires_at
  ) returning * into v_verification;
  perform set_config('lws.requirement_verification_command', '', true);

  perform set_config('lws.requirement_command', 'on', true);
  update public.project_requirements
  set verification_result = p_result,
      evidence_reference = p_evidence_reference,
      status = case
        when p_result = 'PASS' and completion_mode in ('AUTO', 'EXTERNAL') then 'COMPLETED'
        else status
      end,
      completed_at = case
        when p_result = 'PASS' and completion_mode in ('AUTO', 'EXTERNAL') then clock_timestamp()
        else completed_at
      end,
      completed_by = case
        when p_result = 'PASS' and completion_mode in ('AUTO', 'EXTERNAL') then v_actor
        else completed_by
      end,
      blocked_reason = case
        when p_result = 'PASS' and completion_mode in ('AUTO', 'EXTERNAL') then null
        else blocked_reason
      end,
      revision = revision + 1,
      updated_at = clock_timestamp()
  where requirement_id = p_requirement_id
  returning * into v_requirement;
  perform set_config('lws.requirement_command', '', true);

  v_result := jsonb_build_object(
    'verification_id', v_verification.verification_id,
    'requirement_id', p_requirement_id,
    'project_id', p_project_id,
    'result', p_result,
    'status', v_requirement.status,
    'revision', v_requirement.revision,
    'replayed', false
  );
  insert into public.audit_events(project_id, event_type, actor, command_id, metadata)
  values (
    p_project_id, 'REQUIREMENT_VERIFIED', v_actor, p_idempotency_key,
    jsonb_build_object(
      'verification_id', v_verification.verification_id,
      'requirement_id', p_requirement_id,
      'rule_key', p_rule_key, 'rule_version', p_rule_version,
      'result', p_result, 'revision', v_requirement.revision
    )
  );
  if v_requirement.status = 'COMPLETED' then
    insert into public.audit_events(project_id, event_type, actor, command_id, metadata)
    values (
      p_project_id, 'REQUIREMENT_COMPLETED', v_actor, p_idempotency_key,
      jsonb_build_object(
        'requirements_board_id', v_requirement.requirements_board_id,
        'requirement_id', p_requirement_id, 'item_number', v_requirement.item_number,
        'previous_status', case v_requirement.completion_mode when 'EXTERNAL' then 'PENDING' else 'ACTIVE' end,
        'new_status', 'COMPLETED', 'revision', v_requirement.revision
      )
    );
  end if;
  insert into public.idempotency_ledger(
    actor_id, project_id, command_type, idempotency_key, request_fingerprint,
    result_reference, result_payload
  ) values (
    v_actor, p_project_id, 'record_project_requirement_verification',
    p_idempotency_key, v_fingerprint, v_verification.verification_id::text, v_result
  );
  return v_result;
end;
$$;

create function lws_internal.evaluate_project_requirements_readiness_v1(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_board public.project_requirements_boards%rowtype;
  v_required_total integer := 0;
  v_required_completed integer := 0;
  v_required_open integer := 0;
  v_required_blocked integer := 0;
  v_incoherent integer := 0;
  v_active_requirement_id uuid;
  v_active_item_number integer;
  v_readiness text := 'UNKNOWN';
  v_reason text := 'REQUIREMENTS_BOARD_MISSING';
  v_source_coherent boolean := false;
begin
  select * into v_board
  from public.project_requirements_boards
  where project_id = p_project_id and status in ('DRAFT', 'FINALIZED')
  order by created_at desc limit 1;
  if found then
    select exists (
      select 1
      from public.commercial_projects as project
      join public.quote_request_quotation_acceptances as acceptance
        on acceptance.id = project.acceptance_id
       and acceptance.issuance_id = project.quotation_issuance_id
      join public.quote_request_quotation_issuances as issuance
        on issuance.id = project.quotation_issuance_id
      join public.quote_request_quotation_approvals as approval
        on approval.id = issuance.approval_id
      where project.project_id = p_project_id
        and approval.id = v_board.source_approval_id
        and approval.quote_request_id = v_board.quote_request_id
        and approval.payload_sha256 = v_board.source_payload_sha256
        and approval.payload_sha256 = public.quotation_approval_payload_sha256_v1(
          approval.approved_payload
        )
    ) into v_source_coherent;
    select
      count(*) filter (where required)::integer,
      count(*) filter (where required and status = 'COMPLETED')::integer,
      count(*) filter (where required and status in ('PENDING', 'ACTIVE'))::integer,
      count(*) filter (where required and status = 'BLOCKED')::integer,
      count(*) filter (
        where required and status = 'COMPLETED'
          and not lws_internal.project_requirement_verification_is_current_v1(requirement_id)
      )::integer,
      (array_agg(requirement_id order by sort_order, item_number) filter (where status = 'ACTIVE'))[1],
      max(item_number) filter (where status = 'ACTIVE')
    into v_required_total, v_required_completed, v_required_open, v_required_blocked,
      v_incoherent, v_active_requirement_id, v_active_item_number
    from public.project_requirements
    where requirements_board_id = v_board.requirements_board_id and project_id = p_project_id;

    if v_board.status <> 'FINALIZED' then
      v_reason := 'REQUIREMENTS_BOARD_NOT_FINALIZED';
    elsif not v_source_coherent then
      v_reason := 'REQUIREMENTS_SOURCE_AUTHORITY_MISMATCH';
    elsif v_required_total = 0 then
      v_reason := 'REQUIRED_REQUIREMENTS_MISSING';
    elsif v_incoherent > 0 then
      v_reason := 'REQUIREMENT_VERIFICATION_STALE';
    elsif v_required_blocked > 0 then
      v_readiness := 'BLOCKED';
      v_reason := 'REQUIRED_REQUIREMENT_BLOCKED';
    elsif v_required_open > 0 then
      v_readiness := 'BLOCKED';
      v_reason := 'REQUIRED_REQUIREMENTS_OPEN';
    else
      v_readiness := 'READY';
      v_reason := 'ALL_REQUIRED_REQUIREMENTS_COMPLETED';
    end if;
  end if;
  return jsonb_build_object(
    'required_total', v_required_total,
    'required_completed', v_required_completed,
    'required_open', v_required_open,
    'required_blocked', v_required_blocked,
    'active_requirement_id', v_active_requirement_id,
    'active_item_number', v_active_item_number,
    'ready_for_preview', v_readiness = 'READY',
    'readiness', v_readiness,
    'reason', v_reason
  );
end;
$$;

create or replace function public.get_project_requirements_board_v1(
  p_quote_request_id uuid,
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_auth record;
  v_board public.project_requirements_boards%rowtype;
  v_customer text;
  v_dossier_reference text;
  v_assigned_operator_id uuid;
  v_assigned_operator_name text;
  v_items jsonb := '[]'::jsonb;
  v_board_json jsonb := 'null'::jsonb;
  v_empty_state text := 'NO_BOARD';
  v_required_total integer := 0;
  v_is_management boolean;
  v_can_create_item boolean := false;
  v_can_finalize boolean := false;
  v_readiness jsonb;
begin
  select * into strict v_auth
  from public.resolve_project_requirement_authorization_v1(
    p_quote_request_id, p_project_id, 'READ_BOARD', false
  );
  v_is_management := v_auth.operator_role in ('owner', 'admin', 'operations_manager');
  select acceptance.customer_legal_name, quote_request.application_reference,
    assignment.assignee_operator_id, assigned_operator.display_name
  into v_customer, v_dossier_reference, v_assigned_operator_id, v_assigned_operator_name
  from public.commercial_projects as project
  join public.quote_request_quotation_acceptances as acceptance
    on acceptance.id = project.acceptance_id and acceptance.issuance_id = project.quotation_issuance_id
  join public.quote_request_quotation_issuances as issuance on issuance.id = project.quotation_issuance_id
  join public.quote_request_quotation_approvals as approval on approval.id = issuance.approval_id
  join public.quote_requests as quote_request on quote_request.id = approval.quote_request_id
  left join lws_internal.operator_dossier_assignments as assignment
    on assignment.quote_request_id = quote_request.id
  left join public.commercial_operators as assigned_operator
    on assigned_operator.operator_id = assignment.assignee_operator_id
  where project.project_id = p_project_id and quote_request.id = p_quote_request_id;

  select * into v_board
  from public.project_requirements_boards
  where project_id = p_project_id and quote_request_id = p_quote_request_id
    and status in ('DRAFT', 'FINALIZED')
  order by created_at desc limit 1;
  if found then
    v_empty_state := null;
    v_board_json := jsonb_build_object(
      'requirements_board_id', v_board.requirements_board_id,
      'status', v_board.status, 'revision', v_board.revision,
      'finalized_at', v_board.finalized_at
    );
    select count(*) filter (where required)::integer,
      coalesce(jsonb_agg(jsonb_build_object(
        'requirement_id', requirement_id, 'item_number', item_number,
        'title', title, 'description', description, 'category', category,
        'source', jsonb_build_object(
          'authority_type', source_reference->>'authority_type',
          'label', case source_reference->>'authority_type'
            when 'ACCEPTED_PROJECT_SCOPE' then 'Geaccepteerde projectscope'
            when 'ACCEPTED_LINE_ITEM' then 'Geaccepteerde offerteregel ' ||
              (((string_to_array(source_reference->>'json_path', '.'))[2])::integer + 1)::text
          end
        ),
        'linked_page_or_module', linked_page_or_module, 'status', status,
        'completion_mode', completion_mode, 'sort_order', sort_order,
        'required', required, 'started_at', started_at, 'completed_at', completed_at,
        'verification_result', verification_result, 'blocked_reason', blocked_reason,
        'revision', revision, 'permitted_actions', '[]'::jsonb
      ) order by sort_order, item_number), '[]'::jsonb)
    into v_required_total, v_items
    from public.project_requirements
    where requirements_board_id = v_board.requirements_board_id and project_id = p_project_id;
    if v_board.status = 'DRAFT' then
      v_can_create_item := true;
      v_can_finalize := v_is_management and v_required_total > 0;
    end if;
  end if;
  v_readiness := lws_internal.evaluate_project_requirements_readiness_v1(p_project_id);
  return jsonb_build_object(
    'contract_version', 1, 'quote_request_id', p_quote_request_id, 'project_id', p_project_id,
    'context', jsonb_build_object(
      'customer', v_customer, 'dossier_reference', v_dossier_reference,
      'project_reference', p_project_id,
      'assigned_operator', case when v_assigned_operator_id is null then 'null'::jsonb
        else jsonb_build_object('operator_id', v_assigned_operator_id, 'display_name', v_assigned_operator_name) end
    ),
    'board', v_board_json, 'items', v_items, 'empty_state', v_empty_state,
    'readiness', v_readiness,
    'actions', jsonb_build_object(
      'can_create_board', v_board.requirements_board_id is null,
      'can_create_item', v_can_create_item, 'can_finalize', v_can_finalize
    )
  );
end;
$$;

revoke all privileges on table public.project_requirement_verifications
from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_project_requirement_verification_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.project_requirement_rule_v1(text, integer)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.project_requirement_verification_is_current_v1(uuid)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_project_requirement_completion_mode_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.evaluate_project_requirements_readiness_v1(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.record_project_requirement_verification_v1(
  uuid, uuid, uuid, bigint, text, integer, text, jsonb, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.record_project_requirement_verification_v1(
  uuid, uuid, uuid, bigint, text, integer, text, jsonb, uuid
) to service_role;

comment on table public.project_requirement_verifications is
  'Append-only trusted requirement verification references; no source code, secrets, logs, or browser claims.';
comment on function lws_internal.evaluate_project_requirements_readiness_v1(uuid) is
  'Single fail-closed requirements readiness evaluator shared by reads and the preview guard.';