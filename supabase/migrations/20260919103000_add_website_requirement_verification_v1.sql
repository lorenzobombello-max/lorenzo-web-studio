create table public.website_requirement_verification_commands (
  operation_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null,
  website_work_context_id uuid not null,
  requirements_board_id uuid not null,
  requirement_id uuid not null,
  idempotency_key uuid not null unique,
  request_fingerprint character(64) not null
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  result jsonb not null
    check (jsonb_typeof(result) = 'object'
      and not lws_internal.website_concept_jsonb_has_forbidden_key_v1(result)),
  created_at timestamptz not null default clock_timestamp(),
  constraint website_requirement_verification_commands_requirement_fk
    foreign key (requirement_id, requirements_board_id, website_work_context_id, quote_request_id)
    references public.website_requirements(
      requirement_id, requirements_board_id, website_work_context_id, quote_request_id
    )
);

alter table public.website_requirement_verification_commands enable row level security;
alter table public.website_requirement_verification_commands force row level security;
revoke all privileges on table public.website_requirement_verification_commands
from public, anon, authenticated, service_role;

create function lws_internal.guard_website_requirement_verification_command_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op <> 'INSERT' then
    raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_VERIFICATION_COMMAND_IMMUTABLE';
  end if;
  if current_setting('lws.website_requirement_verification_command', true) is distinct from 'on' then
    raise exception using errcode = '55000', message = 'DIRECT_WEBSITE_REQUIREMENT_VERIFICATION_COMMAND_FORBIDDEN';
  end if;
  return new;
end;
$$;

create trigger trg_website_requirement_verification_commands_guard
before insert or update or delete on public.website_requirement_verification_commands
for each row execute function lws_internal.guard_website_requirement_verification_command_v1();

create function lws_internal.website_requirement_rule_v1(
  p_rule_key text,
  p_rule_version integer
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when p_rule_key = 'website_route_present' and p_rule_version = 1 then
      '{"evidence_type":"REPOSITORY_ROUTE","modes":["HYBRID"],"target_kind":"DIRECTORY_PATH","freshness_hours":null}'::jsonb
    when p_rule_key = 'website_module_present' and p_rule_version = 1 then
      '{"evidence_type":"REPOSITORY_FILE","modes":["HYBRID"],"target_kind":"FILE_PATH","freshness_hours":null}'::jsonb
    when p_rule_key = 'website_test_suite_passed' and p_rule_version = 1 then
      '{"evidence_type":"TEST_RUN","modes":["AUTO","HYBRID"],"target_kind":"SUITE_ID","freshness_hours":24}'::jsonb
    when p_rule_key = 'approved_content_present' and p_rule_version = 1 then
      '{"evidence_type":"CONTENT_MARKER","modes":["HYBRID"],"target_kind":"FILE_PATH","freshness_hours":null}'::jsonb
    else null
  end
$$;

create function lws_internal.website_requirement_canonical_json_v1(p_value jsonb)
returns text
language plpgsql
immutable
strict
set search_path = pg_catalog
as $$
declare
  v_type text := jsonb_typeof(p_value);
  v_result text;
begin
  if v_type in ('null', 'boolean', 'number') then
    return p_value::text;
  elsif v_type = 'string' then
    return to_jsonb(normalize(p_value #>> '{}', NFKC))::text;
  elsif v_type = 'array' then
    select '[' || coalesce(string_agg(
      lws_internal.website_requirement_canonical_json_v1(value), ',' order by ordinal
    ), '') || ']'
    into v_result
    from jsonb_array_elements(p_value) with ordinality as elements(value, ordinal);
    return v_result;
  elsif v_type = 'object' then
    select '{' || coalesce(string_agg(
      to_jsonb(key)::text || ':' || lws_internal.website_requirement_canonical_json_v1(value),
      ',' order by key
    ), '') || '}'
    into v_result
    from jsonb_each(p_value) as members(key, value);
    return v_result;
  end if;
  raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REQUIREMENT_VERIFICATION_EVIDENCE';
end;
$$;

create function lws_internal.website_requirement_evidence_sha256_v1(p_evidence jsonb)
returns character(64)
language sql
immutable
strict
set search_path = lws_internal, extensions, pg_catalog
as $$
  select encode(digest(
    convert_to(lws_internal.website_requirement_canonical_json_v1(p_evidence), 'UTF8'),
    'sha256'
  ), 'hex')::character(64)
$$;

create function lws_internal.website_requirement_path_is_canonical_v1(p_path text)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select p_path is not null
    and char_length(p_path) between 1 and 160
    and p_path = btrim(p_path)
    and p_path !~ '^[[:alpha:]][[:alnum:]+.-]*:'
    and p_path !~ '^/'
    and p_path !~ '\\'
    and p_path !~ '[[:cntrl:]]'
    and p_path !~ '(^|/)(\.|\.\.)(/|$)'
    and p_path !~ '//'
    and p_path !~ '/$'
$$;

create function lws_internal.website_requirement_assert_service_role_v1()
returns void
language plpgsql
stable
security definer
set search_path = auth, pg_catalog
as $$
begin
  if coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'TRUSTED_WEBSITE_REQUIREMENTS_VERIFIER_REQUIRED';
  end if;
end;
$$;

create function public.get_website_requirement_verification_authority_v1(
  p_quote_request_id uuid,
  p_website_work_context_id uuid,
  p_requirement_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_context public.website_work_contexts%rowtype;
  v_board public.website_requirements_boards%rowtype;
  v_requirement public.website_requirements%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_rule jsonb;
  v_target_kind text;
begin
  perform lws_internal.website_requirement_assert_service_role_v1();
  if p_quote_request_id is null or p_website_work_context_id is null
     or p_requirement_id is null or p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REQUIREMENT_VERIFICATION_COMMAND';
  end if;

  select * into v_context
  from public.website_work_contexts
  where website_work_context_id = p_website_work_context_id
    and quote_request_id = p_quote_request_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_REQUIREMENT_NOT_FOUND';
  end if;
  select * into v_board
  from public.website_requirements_boards
  where website_work_context_id = p_website_work_context_id
    and quote_request_id = p_quote_request_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_REQUIREMENTS_BOARD_NOT_FOUND';
  end if;
  select * into v_requirement
  from public.website_requirements
  where requirement_id = p_requirement_id
    and requirements_board_id = v_board.requirements_board_id
    and website_work_context_id = p_website_work_context_id
    and quote_request_id = p_quote_request_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_REQUIREMENT_NOT_FOUND';
  end if;
  if v_requirement.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;
  if v_requirement.source_review_state <> 'CURRENT' then
    raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_SOURCE_REVIEW_REQUIRED';
  end if;
  v_rule := lws_internal.website_requirement_rule_v1(
    v_requirement.completion_rule_key, v_requirement.completion_rule_version
  );
  if v_rule is null then
    raise exception using errcode = '22023', message = 'UNKNOWN_WEBSITE_REQUIREMENT_RULE';
  end if;
  if not (v_rule->'modes' ? v_requirement.completion_mode) then
    raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_VERIFICATION_MODE_UNSUPPORTED';
  end if;
  if v_requirement.linked_page_or_module is null then
    raise exception using errcode = '23514', message = 'WEBSITE_REQUIREMENT_RULE_MISMATCH';
  end if;
  v_target_kind := v_rule->>'target_kind';
  if (v_target_kind in ('DIRECTORY_PATH', 'FILE_PATH')
      and not lws_internal.website_requirement_path_is_canonical_v1(v_requirement.linked_page_or_module))
     or (v_target_kind = 'SUITE_ID'
      and v_requirement.linked_page_or_module !~ '^[a-z][a-z0-9_-]{0,79}$') then
    raise exception using errcode = '23514', message = 'WEBSITE_REQUIREMENT_RULE_MISMATCH';
  end if;

  select * into v_workspace
  from public.website_execution_workspaces
  where website_work_context_id = p_website_work_context_id
    and quote_request_id = p_quote_request_id
    and project_id is not distinct from v_context.project_id;
  if not found then
    raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_WORKSPACE_NOT_READY';
  end if;
  select * into v_operation
  from public.website_repository_provisioning_operations
  where website_workspace_id = v_workspace.website_workspace_id
    and website_work_context_id = p_website_work_context_id
  order by updated_at desc, operation_id desc
  limit 1;
  if v_workspace.workspace_state <> 'REPOSITORY_READY'
     or v_workspace.repository_provider <> 'GITHUB'
     or v_workspace.repository_owner is null or v_workspace.repository_name is null
     or v_workspace.repository_external_id is null or v_workspace.repository_node_id is null
     or v_workspace.default_branch is null or v_workspace.last_commit_sha is null
     or v_workspace.binding_revision < 1
     or not found or v_operation.state <> 'BOUND'
     or v_operation.repository_provider is distinct from v_workspace.repository_provider
     or v_operation.repository_owner is distinct from v_workspace.repository_owner
     or v_operation.repository_name is distinct from v_workspace.repository_name
     or v_operation.repository_external_id is distinct from v_workspace.repository_external_id
     or v_operation.repository_node_id is distinct from v_workspace.repository_node_id then
    raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_WORKSPACE_NOT_READY';
  end if;

  return jsonb_build_object(
    'contract_version', 1,
    'quote_request_id', p_quote_request_id,
    'website_work_context_id', p_website_work_context_id,
    'requirements_board_id', v_board.requirements_board_id,
    'requirement_id', p_requirement_id,
    'requirement_revision', v_requirement.revision,
    'completion_mode', v_requirement.completion_mode,
    'rule_key', v_requirement.completion_rule_key,
    'rule_version', v_requirement.completion_rule_version,
    'source_value_sha256', v_requirement.source_value_sha256,
    'source_review_state', v_requirement.source_review_state,
    'verification_target', jsonb_build_object(
      'kind', v_target_kind, 'value', v_requirement.linked_page_or_module
    ),
    'workspace', jsonb_build_object(
      'website_workspace_id', v_workspace.website_workspace_id,
      'binding_revision', v_workspace.binding_revision,
      'repository_provider', v_workspace.repository_provider,
      'repository_owner', v_workspace.repository_owner,
      'repository_name', v_workspace.repository_name,
      'repository_external_id', v_workspace.repository_external_id::text,
      'repository_node_id', v_workspace.repository_node_id,
      'repository_ref', 'heads/' || v_workspace.default_branch,
      'ref_label', v_workspace.default_branch,
      'last_commit_sha', v_workspace.last_commit_sha,
      'workspace_state', v_workspace.workspace_state,
      'repository_operation_state', 'COMPLETE'
    )
  );
end;
$$;

create function lws_internal.website_requirement_verification_is_current_v1(
  p_requirement_id uuid,
  p_allow_completed_hybrid_bridge boolean default false
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_requirement public.website_requirements%rowtype;
  v_verification public.website_requirement_verifications%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_rule jsonb;
  v_revision_matches boolean;
begin
  select * into v_requirement
  from public.website_requirements
  where requirement_id = p_requirement_id;
  if not found or v_requirement.source_review_state <> 'CURRENT'
     or v_requirement.completion_mode not in ('AUTO', 'HYBRID') then
    return false;
  end if;
  v_rule := lws_internal.website_requirement_rule_v1(
    v_requirement.completion_rule_key, v_requirement.completion_rule_version
  );
  if v_rule is null or not (v_rule->'modes' ? v_requirement.completion_mode) then
    return false;
  end if;
  select * into v_verification
  from public.website_requirement_verifications
  where requirement_id = p_requirement_id
    and requirements_board_id = v_requirement.requirements_board_id
    and website_work_context_id = v_requirement.website_work_context_id
    and quote_request_id = v_requirement.quote_request_id
  order by verified_at desc, verification_id desc
  limit 1;
    if not found or v_verification.result <> 'PASS'
      or v_requirement.verification_result <> 'PASS'
     or v_verification.rule_key <> v_requirement.completion_rule_key
     or v_verification.rule_version <> v_requirement.completion_rule_version
     or v_verification.evidence_reference->>'evidence_type' <> v_rule->>'evidence_type'
     or v_verification.evidence_reference->>'requirement_source_sha256' <> v_requirement.source_value_sha256
     or v_verification.evidence_reference->>'website_work_context_id' <> v_requirement.website_work_context_id::text
     or (v_verification.expires_at is not null and v_verification.expires_at <= clock_timestamp()) then
    return false;
  end if;

  v_revision_matches := v_verification.requirement_revision = v_requirement.revision;
  if not v_revision_matches and p_allow_completed_hybrid_bridge
     and v_requirement.completion_mode = 'HYBRID' and v_requirement.status = 'COMPLETED'
     and v_verification.requirement_revision = v_requirement.revision - 1 then
    v_revision_matches := exists (
      select 1
      from public.website_requirement_events as event
      where event.requirement_id = v_requirement.requirement_id
        and event.requirements_board_id = v_requirement.requirements_board_id
        and event.website_work_context_id = v_requirement.website_work_context_id
        and event.quote_request_id = v_requirement.quote_request_id
        and event.event_type = 'WEBSITE_REQUIREMENT_COMPLETED'
        and event.metadata->>'previous_revision' = v_verification.requirement_revision::text
        and event.metadata->>'new_revision' = v_requirement.revision::text
    );
  end if;
  if not v_revision_matches then return false; end if;

  select * into v_workspace
  from public.website_execution_workspaces
  where website_workspace_id = v_verification.website_workspace_id
    and website_work_context_id = v_requirement.website_work_context_id
    and quote_request_id = v_requirement.quote_request_id;
  if not found then return false; end if;
  select * into v_operation
  from public.website_repository_provisioning_operations
  where website_workspace_id = v_workspace.website_workspace_id
    and website_work_context_id = v_requirement.website_work_context_id
  order by updated_at desc, operation_id desc
  limit 1;
  return found
    and v_workspace.workspace_state = 'REPOSITORY_READY'
    and v_operation.state = 'BOUND'
    and v_operation.repository_provider is not distinct from v_workspace.repository_provider
    and v_operation.repository_owner is not distinct from v_workspace.repository_owner
    and v_operation.repository_name is not distinct from v_workspace.repository_name
    and v_operation.repository_external_id is not distinct from v_workspace.repository_external_id
    and v_operation.repository_node_id is not distinct from v_workspace.repository_node_id
    and v_verification.binding_revision = v_workspace.binding_revision
    and v_workspace.binding_revision::text = v_verification.evidence_reference->>'binding_revision'
    and 'heads/' || v_workspace.default_branch = v_verification.evidence_reference->>'repository_ref'
    and v_workspace.last_commit_sha = v_verification.canonical_commit_sha
    and v_workspace.last_commit_sha = v_verification.evidence_reference->>'commit_sha';
end;
$$;

create or replace function lws_internal.website_requirement_current_pass_v1(p_requirement_id uuid)
returns boolean
language sql
stable
security definer
set search_path = lws_internal, pg_catalog
as $$
  select lws_internal.website_requirement_verification_is_current_v1(p_requirement_id, false)
$$;

create or replace function lws_internal.website_requirements_readiness_v1(p_website_work_context_id uuid)
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
  elsif exists (
    select 1 from public.website_requirements as requirement
    where requirement.website_work_context_id = p_website_work_context_id
      and requirement.required and requirement.source_review_state = 'CURRENT'
      and requirement.status = 'COMPLETED'
      and requirement.completion_mode in ('AUTO', 'HYBRID')
      and not lws_internal.website_requirement_verification_is_current_v1(
        requirement.requirement_id, requirement.completion_mode = 'HYBRID'
      )
  ) then
    return jsonb_build_object('ready_for_preview', false, 'readiness', 'BLOCKED', 'reason', 'REQUIREMENT_VERIFICATION_STALE');
  elsif (v_progress->>'required_open')::integer > 0 then
    return jsonb_build_object('ready_for_preview', false, 'readiness', 'BLOCKED', 'reason', 'REQUIRED_REQUIREMENTS_OPEN');
  end if;
  return jsonb_build_object('ready_for_preview', true, 'readiness', 'READY', 'reason', 'ALL_REQUIRED_REQUIREMENTS_COMPLETED');
end;
$$;

create function public.record_website_requirement_verification_v1(
  p_quote_request_id uuid,
  p_website_work_context_id uuid,
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
  v_actor constant text := 'SYSTEM:website_requirements_verifier';
  v_context public.website_work_contexts%rowtype;
  v_board public.website_requirements_boards%rowtype;
  v_requirement public.website_requirements%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_existing public.website_requirement_verification_commands%rowtype;
  v_verification public.website_requirement_verifications%rowtype;
  v_rule jsonb;
  v_details jsonb;
  v_evidence_type text;
  v_observed_at timestamptz;
  v_expires_at timestamptz;
  v_evidence_sha256 character(64);
  v_fingerprint character(64);
  v_previous_status text;
  v_previous_revision bigint;
  v_auto_completed boolean := false;
  v_result jsonb;
  v_event_metadata jsonb;
begin
  perform lws_internal.website_requirement_assert_service_role_v1();
  if p_quote_request_id is null or p_website_work_context_id is null
     or p_requirement_id is null or p_expected_revision is null or p_expected_revision < 1
     or p_rule_key is null or p_rule_version is null or p_rule_version < 1
     or p_result not in ('PASS', 'FAIL', 'UNKNOWN') or p_idempotency_key is null
     or jsonb_typeof(p_evidence_reference) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REQUIREMENT_VERIFICATION_COMMAND';
  end if;
  v_rule := lws_internal.website_requirement_rule_v1(p_rule_key, p_rule_version);
  if v_rule is null then
    raise exception using errcode = '22023', message = 'UNKNOWN_WEBSITE_REQUIREMENT_RULE';
  end if;
  if not public.jsonb_has_exact_keys(p_evidence_reference, array[
    'contract_version', 'evidence_type', 'website_work_context_id',
    'website_workspace_id', 'binding_revision', 'repository_ref', 'commit_sha',
    'requirement_source_sha256', 'observed_at', 'details'
    ]) or p_evidence_reference->'contract_version' <> '1'::jsonb
      or jsonb_typeof(p_evidence_reference->'evidence_type') <> 'string'
      or jsonb_typeof(p_evidence_reference->'website_work_context_id') <> 'string'
      or jsonb_typeof(p_evidence_reference->'website_workspace_id') <> 'string'
      or jsonb_typeof(p_evidence_reference->'binding_revision') <> 'number'
      or jsonb_typeof(p_evidence_reference->'repository_ref') <> 'string'
      or jsonb_typeof(p_evidence_reference->'commit_sha') <> 'string'
      or jsonb_typeof(p_evidence_reference->'requirement_source_sha256') <> 'string'
      or jsonb_typeof(p_evidence_reference->'observed_at') <> 'string'
     or jsonb_typeof(p_evidence_reference->'details') <> 'object' then
    raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REQUIREMENT_VERIFICATION_EVIDENCE';
  end if;
  v_evidence_type := p_evidence_reference->>'evidence_type';
  v_details := p_evidence_reference->'details';
  if v_evidence_type <> v_rule->>'evidence_type' then
    raise exception using errcode = '23514', message = 'WEBSITE_REQUIREMENT_RULE_MISMATCH';
  end if;
  if p_evidence_reference->>'observed_at' is null
     or p_evidence_reference->>'observed_at'
       !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?Z$' then
    raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REQUIREMENT_VERIFICATION_EVIDENCE';
  end if;
  begin
    v_observed_at := (p_evidence_reference->>'observed_at')::timestamptz;
  exception when others then
    raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REQUIREMENT_VERIFICATION_EVIDENCE';
  end;
  if v_evidence_type in ('REPOSITORY_ROUTE', 'REPOSITORY_FILE') then
    if not public.jsonb_has_exact_keys(v_details, array['path', 'object_type', 'object_sha'])
       or jsonb_typeof(v_details->'path') <> 'string'
       or jsonb_typeof(v_details->'object_type') <> 'string'
       or jsonb_typeof(v_details->'object_sha') <> 'string'
       or not lws_internal.website_requirement_path_is_canonical_v1(v_details->>'path')
       or v_details->>'object_sha' !~ '^[0-9a-f]{40}$'
       or (v_evidence_type = 'REPOSITORY_ROUTE' and v_details->>'object_type' <> 'tree')
       or (v_evidence_type = 'REPOSITORY_FILE' and v_details->>'object_type' <> 'blob') then
      raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REQUIREMENT_VERIFICATION_EVIDENCE';
    end if;
  elsif v_evidence_type = 'TEST_RUN' then
    if not public.jsonb_has_exact_keys(v_details, array['suite_id', 'suite_version', 'run_id'])
       or jsonb_typeof(v_details->'suite_id') <> 'string'
       or jsonb_typeof(v_details->'suite_version') <> 'number'
       or jsonb_typeof(v_details->'run_id') <> 'string'
       or v_details->>'suite_id' !~ '^[a-z][a-z0-9_-]{0,79}$'
       or v_details->>'suite_version' <> '1'
       or char_length(v_details->>'run_id') not between 1 and 120 then
      raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REQUIREMENT_VERIFICATION_EVIDENCE';
    end if;
    v_expires_at := v_observed_at + interval '24 hours';
  elsif v_evidence_type = 'CONTENT_MARKER' then
    if not public.jsonb_has_exact_keys(v_details, array['path', 'marker_key', 'marker_version', 'marker_sha256'])
       or jsonb_typeof(v_details->'path') <> 'string'
       or jsonb_typeof(v_details->'marker_key') <> 'string'
       or jsonb_typeof(v_details->'marker_version') <> 'number'
       or jsonb_typeof(v_details->'marker_sha256') <> 'string'
       or not lws_internal.website_requirement_path_is_canonical_v1(v_details->>'path')
       or v_details->>'marker_key' <> 'LWS_APPROVED_CONTENT'
       or v_details->>'marker_version' <> '1'
       or v_details->>'marker_sha256' !~ '^[0-9a-f]{64}$' then
      raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REQUIREMENT_VERIFICATION_EVIDENCE';
    end if;
  else
    raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REQUIREMENT_VERIFICATION_EVIDENCE';
  end if;
  if v_observed_at > clock_timestamp() + interval '5 minutes'
     or (v_evidence_type = 'TEST_RUN' and v_observed_at < clock_timestamp() - interval '24 hours')
     or (v_evidence_type <> 'TEST_RUN' and v_observed_at < clock_timestamp() - interval '5 minutes') then
    raise exception using errcode = '22023', message = 'WEBSITE_REQUIREMENT_VERIFICATION_STALE';
  end if;

  v_evidence_sha256 := lws_internal.website_requirement_evidence_sha256_v1(p_evidence_reference);
  v_fingerprint := lws_internal.website_requirements_sha256_hex_v1(jsonb_build_array(
    1, v_actor, p_quote_request_id, p_website_work_context_id, p_requirement_id,
    p_expected_revision, p_rule_key, p_rule_version, p_result, v_evidence_sha256
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing
  from public.website_requirement_verification_commands
  where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'WEBSITE_REQUIREMENT_VERIFICATION_IDEMPOTENCY_CONFLICT';
    end if;
    return (v_existing.result - 'replayed') || jsonb_build_object('replayed', true);
  end if;

  select * into v_context
  from public.website_work_contexts
  where website_work_context_id = p_website_work_context_id
    and quote_request_id = p_quote_request_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_REQUIREMENT_NOT_FOUND';
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
  select * into v_workspace
  from public.website_execution_workspaces
  where website_work_context_id = p_website_work_context_id
    and quote_request_id = p_quote_request_id
    and project_id is not distinct from v_context.project_id
  for update;
  if not found then
    raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_WORKSPACE_NOT_READY';
  end if;
  select * into v_operation
  from public.website_repository_provisioning_operations
  where website_workspace_id = v_workspace.website_workspace_id
    and website_work_context_id = p_website_work_context_id
  order by updated_at desc, operation_id desc
  limit 1 for update;

  if v_requirement.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;
  if v_requirement.source_review_state <> 'CURRENT' then
    raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_SOURCE_REVIEW_REQUIRED';
  end if;
  if v_requirement.completion_mode = 'OPERATOR'
     or not (v_rule->'modes' ? v_requirement.completion_mode) then
    raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_VERIFICATION_MODE_UNSUPPORTED';
  end if;
  if v_requirement.completion_rule_key <> p_rule_key
     or v_requirement.completion_rule_version <> p_rule_version
     or v_requirement.linked_page_or_module is distinct from
       coalesce(v_details->>'path', v_details->>'suite_id') then
    raise exception using errcode = '23514', message = 'WEBSITE_REQUIREMENT_RULE_MISMATCH';
  end if;
    if v_workspace.workspace_state <> 'REPOSITORY_READY'
      or v_workspace.repository_provider <> 'GITHUB' or v_operation.state <> 'BOUND'
      or v_operation.repository_provider is distinct from v_workspace.repository_provider
      or v_operation.repository_owner is distinct from v_workspace.repository_owner
      or v_operation.repository_name is distinct from v_workspace.repository_name
      or v_operation.repository_external_id is distinct from v_workspace.repository_external_id
      or v_operation.repository_node_id is distinct from v_workspace.repository_node_id then
    raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_WORKSPACE_NOT_READY';
  end if;
  if p_evidence_reference->>'website_work_context_id' <> p_website_work_context_id::text
     or p_evidence_reference->>'website_workspace_id' <> v_workspace.website_workspace_id::text then
    raise exception using errcode = '23514', message = 'WEBSITE_REQUIREMENT_WORKSPACE_MISMATCH';
  end if;
  if p_evidence_reference->>'binding_revision' <> v_workspace.binding_revision::text then
    raise exception using errcode = '23514', message = 'WEBSITE_REQUIREMENT_BINDING_MISMATCH';
  end if;
  if p_evidence_reference->>'repository_ref' <> 'heads/' || v_workspace.default_branch then
    raise exception using errcode = '23514', message = 'WEBSITE_REQUIREMENT_REF_MISMATCH';
  end if;
  if p_evidence_reference->>'commit_sha' <> v_workspace.last_commit_sha then
    raise exception using errcode = '23514', message = 'WEBSITE_REQUIREMENT_COMMIT_MISMATCH';
  end if;
  if p_evidence_reference->>'requirement_source_sha256' <> v_requirement.source_value_sha256 then
    raise exception using errcode = '23514', message = 'WEBSITE_REQUIREMENT_SOURCE_MISMATCH';
  end if;
  if v_evidence_type = 'CONTENT_MARKER'
     and v_details->>'marker_sha256' <> lws_internal.website_requirements_sha256_hex_v1(
       'LWS_APPROVED_CONTENT_V1:' || v_requirement.source_value_sha256
     ) then
    raise exception using errcode = '23514', message = 'WEBSITE_REQUIREMENT_SOURCE_MISMATCH';
  end if;

  v_previous_status := v_requirement.status;
  v_previous_revision := v_requirement.revision;
  v_auto_completed := v_requirement.completion_mode = 'AUTO'
    and p_result = 'PASS' and v_requirement.status in ('PENDING', 'ACTIVE', 'BLOCKED');
  perform set_config('lws.website_requirement_history_command', 'on', true);
  insert into public.website_requirement_verifications(
    requirement_id, requirements_board_id, website_work_context_id, quote_request_id,
    website_workspace_id, binding_revision, canonical_commit_sha, requirement_revision,
    rule_key, rule_version, result, evidence_reference, evidence_sha256,
    verified_by, verified_at, expires_at
  ) values (
    p_requirement_id, v_board.requirements_board_id, p_website_work_context_id, p_quote_request_id,
    v_workspace.website_workspace_id, v_workspace.binding_revision, v_workspace.last_commit_sha,
    v_requirement.revision + 1, p_rule_key, p_rule_version, p_result,
    p_evidence_reference, v_evidence_sha256, v_actor, clock_timestamp(), v_expires_at
  ) returning * into v_verification;

  perform set_config('lws.website_requirement_command', 'on', true);
  update public.website_requirements
  set status = case when v_auto_completed then 'COMPLETED' else status end,
      completed_at = case when v_auto_completed then clock_timestamp() else completed_at end,
      completed_by = case when v_auto_completed then v_actor else completed_by end,
      blocked_reason = case when v_auto_completed then null else blocked_reason end,
      evidence_summary = p_evidence_reference,
      verification_result = p_result,
      revision = revision + 1,
      updated_at = clock_timestamp()
  where requirement_id = p_requirement_id
  returning * into v_requirement;
  update public.website_requirements_boards
  set revision = revision + 1, updated_at = clock_timestamp()
  where requirements_board_id = v_board.requirements_board_id
  returning * into v_board;

  v_event_metadata := jsonb_build_object(
    'verification_id', v_verification.verification_id,
    'requirements_board_id', v_board.requirements_board_id,
    'requirement_id', p_requirement_id,
    'rule_key', p_rule_key,
    'rule_version', p_rule_version,
    'evidence_type', v_evidence_type,
    'evidence_sha256', v_evidence_sha256,
    'result', p_result,
    'previous_status', v_previous_status,
    'new_status', v_requirement.status,
    'previous_revision', v_previous_revision,
    'new_revision', v_requirement.revision,
    'board_revision', v_board.revision,
    'auto_completed', v_auto_completed
  );
  insert into public.website_requirement_events(
    requirements_board_id, website_work_context_id, quote_request_id, requirement_id,
    event_type, actor_id, command_id, prior_revision, new_revision, metadata
  ) values (
    v_board.requirements_board_id, p_website_work_context_id, p_quote_request_id,
    p_requirement_id, 'WEBSITE_REQUIREMENT_VERIFICATION_RECORDED', v_actor,
    p_idempotency_key, v_previous_revision, v_requirement.revision, v_event_metadata
  );
  if v_auto_completed then
    insert into public.website_requirement_events(
      requirements_board_id, website_work_context_id, quote_request_id, requirement_id,
      event_type, actor_id, command_id, prior_revision, new_revision, metadata
    ) values (
      v_board.requirements_board_id, p_website_work_context_id, p_quote_request_id,
      p_requirement_id, 'WEBSITE_REQUIREMENT_AUTO_COMPLETED', v_actor,
      p_idempotency_key, v_previous_revision, v_requirement.revision, v_event_metadata
    );
  end if;

  v_result := jsonb_build_object(
    'contract_version', 1,
    'verification_id', v_verification.verification_id,
    'quote_request_id', p_quote_request_id,
    'website_work_context_id', p_website_work_context_id,
    'requirements_board_id', v_board.requirements_board_id,
    'requirement_id', p_requirement_id,
    'requirement_revision', v_requirement.revision,
    'board_revision', v_board.revision,
    'rule_key', p_rule_key,
    'rule_version', p_rule_version,
    'result', p_result,
    'status', v_requirement.status,
    'auto_completed', v_auto_completed,
    'replayed', false
  );
  perform set_config('lws.website_requirement_verification_command', 'on', true);
  insert into public.website_requirement_verification_commands(
    quote_request_id, website_work_context_id, requirements_board_id, requirement_id,
    idempotency_key, request_fingerprint, result
  ) values (
    p_quote_request_id, p_website_work_context_id, v_board.requirements_board_id,
    p_requirement_id, p_idempotency_key, v_fingerprint, v_result
  );
  return v_result;
end;
$$;

revoke all on function lws_internal.guard_website_requirement_verification_command_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirement_rule_v1(text, integer)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirement_canonical_json_v1(jsonb)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirement_evidence_sha256_v1(jsonb)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirement_path_is_canonical_v1(text)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirement_assert_service_role_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirement_verification_is_current_v1(uuid, boolean)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirement_current_pass_v1(uuid)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.website_requirements_readiness_v1(uuid)
from public, anon, authenticated, service_role;

revoke all on function public.get_website_requirement_verification_authority_v1(uuid, uuid, uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.record_website_requirement_verification_v1(
  uuid, uuid, uuid, bigint, text, integer, text, jsonb, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.get_website_requirement_verification_authority_v1(uuid, uuid, uuid, bigint)
to service_role;
grant execute on function public.record_website_requirement_verification_v1(
  uuid, uuid, uuid, bigint, text, integer, text, jsonb, uuid
) to service_role;