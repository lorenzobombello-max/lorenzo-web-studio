create table public.project_requirements_boards (
  requirements_board_id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.commercial_projects(project_id),
  quote_request_id uuid not null references public.quote_requests(id),
  source_approval_id uuid not null references public.quote_request_quotation_approvals(id),
  source_payload_sha256 char(64) not null check (source_payload_sha256 ~ '^[0-9a-f]{64}$'),
  status text not null check (status in ('DRAFT', 'FINALIZED', 'SUPERSEDED')),
  revision bigint not null default 1 check (revision > 0),
  finalized_by uuid references public.commercial_operators(operator_id),
  finalized_at timestamptz,
  created_by uuid not null references public.commercial_operators(operator_id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint project_requirements_boards_identity_unique unique (requirements_board_id, project_id),
  constraint project_requirements_boards_finalization_shape check (
    (status = 'DRAFT' and finalized_by is null and finalized_at is null)
    or (status in ('FINALIZED', 'SUPERSEDED') and finalized_by is not null and finalized_at is not null)
  ),
  constraint project_requirements_boards_timestamps_valid check (
    updated_at >= created_at and (finalized_at is null or finalized_at >= created_at)
  )
);

create unique index project_requirements_boards_one_current_idx
  on public.project_requirements_boards(project_id)
  where status in ('DRAFT', 'FINALIZED');

create table public.project_requirements (
  requirement_id uuid primary key default gen_random_uuid(),
  requirements_board_id uuid not null,
  project_id uuid not null,
  item_number integer not null check (item_number > 0),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  description text not null check (char_length(btrim(description)) between 1 and 1200),
  category text not null check (category in (
    'PAGE', 'CONTENT', 'DESIGN', 'FORM', 'SEO', 'INTEGRATION', 'AUTOMATION',
    'AUTH', 'ECOMMERCE', 'DOCUMENT_FLOW', 'MULTIMEDIA', 'TECHNICAL', 'OTHER'
  )),
  source_reference jsonb not null check (jsonb_typeof(source_reference) = 'object'),
  linked_page_or_module text check (
    linked_page_or_module is null
    or (
      char_length(btrim(linked_page_or_module)) between 1 and 160
      and linked_page_or_module !~ '^[[:alpha:]][[:alnum:]+.-]*://'
      and linked_page_or_module !~ '[[:cntrl:]]'
    )
  ),
  status text not null default 'PENDING'
    check (status in ('PENDING', 'ACTIVE', 'BLOCKED', 'COMPLETED')),
  completion_mode text not null
    check (completion_mode in ('AUTO', 'OPERATOR', 'HYBRID', 'EXTERNAL')),
  completion_rule_key text check (
    completion_rule_key is null
    or completion_rule_key ~ '^[a-z][a-z0-9_]{0,63}$'
  ),
  completion_rule_version integer check (completion_rule_version is null or completion_rule_version > 0),
  sort_order integer not null check (sort_order > 0),
  required boolean not null,
  started_at timestamptz,
  completed_at timestamptz,
  completed_by text check (
    completed_by is null
    or completed_by ~ '^(OPERATOR:[0-9a-f-]{36}|SYSTEM:[a-z][a-z0-9_-]{0,63})$'
  ),
  evidence_reference jsonb check (evidence_reference is null or jsonb_typeof(evidence_reference) = 'object'),
  verification_result text not null default 'UNKNOWN'
    check (verification_result in ('PASS', 'FAIL', 'UNKNOWN', 'NOT_APPLICABLE')),
  blocked_reason text check (blocked_reason is null or char_length(btrim(blocked_reason)) between 1 and 500),
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint project_requirements_board_fk foreign key (requirements_board_id, project_id)
    references public.project_requirements_boards(requirements_board_id, project_id),
  constraint project_requirements_identity_unique unique (requirement_id, project_id),
  constraint project_requirements_item_number_unique unique (requirements_board_id, item_number),
  constraint project_requirements_sort_order_unique unique (requirements_board_id, sort_order),
  constraint project_requirements_rule_shape check (
    (completion_mode = 'OPERATOR' and completion_rule_key is null and completion_rule_version is null)
    or (completion_mode in ('AUTO', 'HYBRID', 'EXTERNAL')
      and completion_rule_key is not null and completion_rule_version is not null)
  ),
  constraint project_requirements_status_shape check (
    (status = 'PENDING' and completed_at is null and completed_by is null and blocked_reason is null)
    or (status = 'ACTIVE' and started_at is not null and completed_at is null and completed_by is null and blocked_reason is null)
    or (status = 'BLOCKED' and completed_at is null and completed_by is null and blocked_reason is not null)
    or (status = 'COMPLETED' and completed_at is not null and completed_by is not null and blocked_reason is null)
  ),
  constraint project_requirements_timestamps_valid check (
    updated_at >= created_at
    and (started_at is null or started_at >= created_at)
    and (completed_at is null or completed_at >= created_at)
  )
);

create index project_requirements_project_status_idx
  on public.project_requirements(project_id, status, sort_order);
create unique index project_requirements_one_active_idx
  on public.project_requirements(project_id)
  where status = 'ACTIVE';

alter table public.project_requirements_boards enable row level security;
alter table public.project_requirements_boards force row level security;
alter table public.project_requirements enable row level security;
alter table public.project_requirements force row level security;

revoke all privileges on table public.project_requirements_boards, public.project_requirements
from public, anon, authenticated, service_role;

create function lws_internal.guard_project_requirement_command_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if current_setting('lws.requirement_command', true) is distinct from 'on' then
    raise exception using errcode = '55000', message = 'DIRECT_REQUIREMENT_WRITE_FORBIDDEN';
  end if;
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'REQUIREMENT_DELETE_FORBIDDEN';
  end if;
  return new;
end;
$$;

create trigger trg_project_requirements_boards_command_guard
before insert or update or delete on public.project_requirements_boards
for each row execute function lws_internal.guard_project_requirement_command_v1();

create trigger trg_project_requirements_command_guard
before insert or update or delete on public.project_requirements
for each row execute function lws_internal.guard_project_requirement_command_v1();

create function lws_internal.guard_finalized_project_requirement_definition_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_board_status text;
begin
  select status into v_board_status
  from public.project_requirements_boards
  where requirements_board_id = new.requirements_board_id
    and project_id = new.project_id;

  if v_board_status <> 'FINALIZED' then
    return new;
  end if;
  if tg_op = 'INSERT'
     or new.requirement_id is distinct from old.requirement_id
     or new.requirements_board_id is distinct from old.requirements_board_id
     or new.project_id is distinct from old.project_id
     or new.item_number is distinct from old.item_number
     or new.title is distinct from old.title
     or new.description is distinct from old.description
     or new.category is distinct from old.category
     or new.source_reference is distinct from old.source_reference
     or new.linked_page_or_module is distinct from old.linked_page_or_module
     or new.completion_mode is distinct from old.completion_mode
     or new.completion_rule_key is distinct from old.completion_rule_key
     or new.completion_rule_version is distinct from old.completion_rule_version
     or new.sort_order is distinct from old.sort_order
     or new.required is distinct from old.required
     or new.created_at is distinct from old.created_at then
    raise exception using
      errcode = '55000',
      message = 'FINALIZED_REQUIREMENT_DEFINITION_IMMUTABLE';
  end if;
  return new;
end;
$$;

create trigger trg_project_requirements_definition_guard
before insert or update on public.project_requirements
for each row execute function lws_internal.guard_finalized_project_requirement_definition_v1();

create function lws_internal.validate_project_requirement_source_v1(
  p_project_id uuid,
  p_quote_request_id uuid,
  p_source_reference jsonb
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select p_project_id is not null
    and p_quote_request_id is not null
    and jsonb_typeof(p_source_reference) = 'object'
    and public.jsonb_has_exact_keys(
      p_source_reference,
      array['authority_type', 'authority_id', 'json_path', 'source_sha256']
    )
    and p_source_reference->>'authority_type' in ('ACCEPTED_PROJECT_SCOPE', 'ACCEPTED_LINE_ITEM')
    and (p_source_reference->>'authority_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and (p_source_reference->>'source_sha256') ~ '^[0-9a-f]{64}$'
    and (
      (p_source_reference->>'authority_type' = 'ACCEPTED_PROJECT_SCOPE'
        and p_source_reference->>'json_path' ~ '^project_scope(?:\.[a-z][a-z0-9_]*)*$')
      or
      (p_source_reference->>'authority_type' = 'ACCEPTED_LINE_ITEM'
        and p_source_reference->>'json_path' ~ '^line_items\.[0-9]+(?:\.[a-z][a-z0-9_]*)*$')
    )
    and exists (
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
        and approval.quote_request_id = p_quote_request_id
        and approval.id::text = p_source_reference->>'authority_id'
        and approval.payload_sha256 = p_source_reference->>'source_sha256'
        and approval.payload_sha256 = public.quotation_approval_payload_sha256_v1(approval.approved_payload)
        and approval.approved_payload #> string_to_array(p_source_reference->>'json_path', '.') is not null
    )
$$;

create function public.resolve_project_requirement_authorization_v1(
  p_quote_request_id uuid,
  p_project_id uuid,
  p_action text,
  p_require_management boolean default false
)
returns table(operator_id uuid, operator_role text, audit_actor text)
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  if p_quote_request_id is null or p_project_id is null
     or p_action not in (
       'READ_BOARD', 'CREATE_BOARD', 'CREATE_ITEM', 'FINALIZE_BOARD',
       'START_REQUIREMENT', 'BLOCK_REQUIREMENT', 'COMPLETE_REQUIREMENT', 'REOPEN_REQUIREMENT'
     ) then
    raise exception using errcode = '22023', message = 'INVALID_REQUIREMENT_AUTHORIZATION_REQUEST';
  end if;

  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;
  if not found then
    raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR';
  end if;
  if v_operator.status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;

  if not exists (
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
      and approval.quote_request_id = p_quote_request_id
  ) then
    raise exception using errcode = '42501', message = 'PROJECT_REQUIREMENT_BINDING_DENIED';
  end if;

  if v_operator.role in ('owner', 'admin', 'operations_manager') then
    null;
  elsif v_operator.role = 'operator' and not p_require_management then
    if not exists (
      select 1
      from lws_internal.operator_dossier_assignments as assignment
      join public.commercial_operator_project_grants as project_grant
        on project_grant.operator_id = v_operator.operator_id
       and project_grant.project_id = p_project_id
       and project_grant.access_level = 'operator'
       and project_grant.revoked_at is null
      where assignment.quote_request_id = p_quote_request_id
        and assignment.assignee_operator_id = v_operator.operator_id
    ) then
      raise exception using errcode = '42501', message = 'PROJECT_REQUIREMENT_ASSIGNMENT_DENIED';
    end if;
  else
    raise exception using errcode = '42501', message = 'PROJECT_REQUIREMENT_ROLE_DENIED';
  end if;

  operator_id := v_operator.operator_id;
  operator_role := v_operator.role;
  audit_actor := 'OPERATOR:' || v_operator.operator_id::text;
  return next;
end;
$$;

create function public.create_project_requirements_board_v1(
  p_quote_request_id uuid,
  p_project_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_auth record;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_existing public.idempotency_ledger%rowtype;
  v_board public.project_requirements_boards%rowtype;
  v_fingerprint char(64);
  v_result jsonb;
begin
  if p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  select * into strict v_auth
  from public.resolve_project_requirement_authorization_v1(
    p_quote_request_id, p_project_id, 'CREATE_BOARD', false
  );

  v_fingerprint := lws_internal.commercial_fingerprint_v1(jsonb_build_object(
    'contract_version', 1, 'actor', v_auth.audit_actor,
    'quote_request_id', p_quote_request_id, 'project_id', p_project_id
  ));
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing
  from public.idempotency_ledger
  where actor_id = v_auth.audit_actor and project_id = p_project_id
    and command_type = 'create_project_requirements_board'
    and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed', true);
  end if;

  select approval.* into strict v_approval
  from public.commercial_projects as project
  join public.quote_request_quotation_acceptances as acceptance
    on acceptance.id = project.acceptance_id
   and acceptance.issuance_id = project.quotation_issuance_id
  join public.quote_request_quotation_issuances as issuance
    on issuance.id = project.quotation_issuance_id
  join public.quote_request_quotation_approvals as approval
    on approval.id = issuance.approval_id
  where project.project_id = p_project_id
    and approval.quote_request_id = p_quote_request_id;

  perform set_config('lws.requirement_command', 'on', true);
  insert into public.project_requirements_boards (
    project_id, quote_request_id, source_approval_id, source_payload_sha256,
    status, created_by
  ) values (
    p_project_id, p_quote_request_id, v_approval.id, v_approval.payload_sha256,
    'DRAFT', v_auth.operator_id
  ) returning * into v_board;
  perform set_config('lws.requirement_command', '', true);

  v_result := jsonb_build_object(
    'requirements_board_id', v_board.requirements_board_id,
    'project_id', v_board.project_id,
    'quote_request_id', v_board.quote_request_id,
    'status', v_board.status,
    'revision', v_board.revision,
    'replayed', false
  );
  insert into public.audit_events(project_id, event_type, actor, command_id, metadata)
  values (p_project_id, 'REQUIREMENTS_BOARD_CREATED', v_auth.audit_actor, p_idempotency_key,
    jsonb_build_object('requirements_board_id', v_board.requirements_board_id,
      'quote_request_id', p_quote_request_id, 'source_approval_id', v_approval.id));
  insert into public.idempotency_ledger(
    actor_id, project_id, command_type, idempotency_key, request_fingerprint,
    result_reference, result_payload
  ) values (
    v_auth.audit_actor, p_project_id, 'create_project_requirements_board',
    p_idempotency_key, v_fingerprint, v_board.requirements_board_id::text, v_result
  );
  return v_result;
end;
$$;

create function public.create_project_requirement_v1(
  p_quote_request_id uuid,
  p_project_id uuid,
  p_requirements_board_id uuid,
  p_expected_board_revision bigint,
  p_item jsonb,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_auth record;
  v_board public.project_requirements_boards%rowtype;
  v_requirement public.project_requirements%rowtype;
  v_existing public.idempotency_ledger%rowtype;
  v_fingerprint char(64);
  v_result jsonb;
  v_mode text;
  v_rule_key text;
  v_rule_version integer;
begin
  if p_requirements_board_id is null or p_expected_board_revision is null
     or p_expected_board_revision < 1 or p_idempotency_key is null
     or jsonb_typeof(p_item) <> 'object'
     or not public.jsonb_has_exact_keys(p_item, array[
       'item_number', 'title', 'description', 'category', 'source_reference',
       'linked_page_or_module', 'completion_mode', 'completion_rule_key',
       'completion_rule_version', 'sort_order', 'required'
     ]) then
    raise exception using errcode = '22023', message = 'INVALID_REQUIREMENT_CREATE_COMMAND';
  end if;
  select * into strict v_auth
  from public.resolve_project_requirement_authorization_v1(
    p_quote_request_id, p_project_id, 'CREATE_ITEM', false
  );
  v_fingerprint := lws_internal.commercial_fingerprint_v1(jsonb_build_object(
    'contract_version', 1, 'actor', v_auth.audit_actor,
    'quote_request_id', p_quote_request_id, 'project_id', p_project_id,
    'requirements_board_id', p_requirements_board_id,
    'expected_board_revision', p_expected_board_revision, 'item', p_item
  ));
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing
  from public.idempotency_ledger
  where actor_id = v_auth.audit_actor and project_id = p_project_id
    and command_type = 'create_project_requirement'
    and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed', true);
  end if;

  select * into v_board
  from public.project_requirements_boards
  where requirements_board_id = p_requirements_board_id
    and project_id = p_project_id and quote_request_id = p_quote_request_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'REQUIREMENTS_BOARD_NOT_FOUND';
  end if;
  if v_board.status <> 'DRAFT' then
    raise exception using errcode = 'P0001', message = 'REQUIREMENTS_BOARD_NOT_DRAFT';
  end if;
  if v_board.revision <> p_expected_board_revision then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;
  if not lws_internal.validate_project_requirement_source_v1(
    p_project_id, p_quote_request_id, p_item->'source_reference'
  ) then
    raise exception using errcode = '23514', message = 'INVALID_REQUIREMENT_SOURCE';
  end if;

  v_mode := p_item->>'completion_mode';
  v_rule_key := nullif(p_item->>'completion_rule_key', '');
  v_rule_version := case when p_item->'completion_rule_version' = 'null'::jsonb then null
    else (p_item->>'completion_rule_version')::integer end;

  perform set_config('lws.requirement_command', 'on', true);
  insert into public.project_requirements (
    requirements_board_id, project_id, item_number, title, description, category,
    source_reference, linked_page_or_module, completion_mode,
    completion_rule_key, completion_rule_version, sort_order, required,
    verification_result
  ) values (
    p_requirements_board_id, p_project_id, (p_item->>'item_number')::integer,
    btrim(p_item->>'title'), btrim(p_item->>'description'), p_item->>'category',
    p_item->'source_reference', nullif(btrim(p_item->>'linked_page_or_module'), ''),
    v_mode, v_rule_key, v_rule_version, (p_item->>'sort_order')::integer,
    (p_item->>'required')::boolean,
    case when v_mode = 'OPERATOR' then 'NOT_APPLICABLE' else 'UNKNOWN' end
  ) returning * into v_requirement;
  update public.project_requirements_boards
  set revision = revision + 1, updated_at = clock_timestamp()
  where requirements_board_id = p_requirements_board_id
  returning * into v_board;
  perform set_config('lws.requirement_command', '', true);

  v_result := jsonb_build_object(
    'requirement_id', v_requirement.requirement_id,
    'requirements_board_id', v_requirement.requirements_board_id,
    'project_id', v_requirement.project_id,
    'item_number', v_requirement.item_number,
    'status', v_requirement.status,
    'revision', v_requirement.revision,
    'board_revision', v_board.revision,
    'replayed', false
  );
  insert into public.audit_events(project_id, event_type, actor, command_id, metadata)
  values (p_project_id, 'REQUIREMENT_CREATED', v_auth.audit_actor, p_idempotency_key,
    jsonb_build_object('requirement_id', v_requirement.requirement_id,
      'requirements_board_id', p_requirements_board_id,
      'item_number', v_requirement.item_number));
  insert into public.idempotency_ledger(
    actor_id, project_id, command_type, idempotency_key, request_fingerprint,
    result_reference, result_payload
  ) values (
    v_auth.audit_actor, p_project_id, 'create_project_requirement',
    p_idempotency_key, v_fingerprint, v_requirement.requirement_id::text, v_result
  );
  return v_result;
end;
$$;

create function public.finalize_project_requirements_board_v1(
  p_quote_request_id uuid,
  p_project_id uuid,
  p_requirements_board_id uuid,
  p_expected_revision bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_auth record;
  v_board public.project_requirements_boards%rowtype;
  v_existing public.idempotency_ledger%rowtype;
  v_fingerprint char(64);
  v_result jsonb;
begin
  if p_requirements_board_id is null or p_expected_revision is null
     or p_expected_revision < 1 or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'INVALID_REQUIREMENTS_BOARD_FINALIZE_COMMAND';
  end if;
  select * into strict v_auth
  from public.resolve_project_requirement_authorization_v1(
    p_quote_request_id, p_project_id, 'FINALIZE_BOARD', true
  );
  v_fingerprint := lws_internal.commercial_fingerprint_v1(jsonb_build_object(
    'contract_version', 1, 'actor', v_auth.audit_actor,
    'quote_request_id', p_quote_request_id, 'project_id', p_project_id,
    'requirements_board_id', p_requirements_board_id,
    'expected_revision', p_expected_revision
  ));
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing
  from public.idempotency_ledger
  where actor_id = v_auth.audit_actor and project_id = p_project_id
    and command_type = 'finalize_project_requirements_board'
    and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed', true);
  end if;

  select * into v_board
  from public.project_requirements_boards
  where requirements_board_id = p_requirements_board_id
    and project_id = p_project_id and quote_request_id = p_quote_request_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'REQUIREMENTS_BOARD_NOT_FOUND';
  end if;
  if v_board.status <> 'DRAFT' then
    raise exception using errcode = 'P0001', message = 'REQUIREMENTS_BOARD_NOT_DRAFT';
  end if;
  if v_board.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;
  if not exists (
    select 1 from public.project_requirements
    where requirements_board_id = p_requirements_board_id and project_id = p_project_id
  ) or not exists (
    select 1 from public.project_requirements
    where requirements_board_id = p_requirements_board_id and project_id = p_project_id
      and required
  ) then
    raise exception using errcode = '23514', message = 'REQUIREMENTS_BOARD_COVERAGE_INCOMPLETE';
  end if;

  perform set_config('lws.requirement_command', 'on', true);
  update public.project_requirements_boards
  set status = 'FINALIZED', revision = revision + 1,
      finalized_by = v_auth.operator_id, finalized_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where requirements_board_id = p_requirements_board_id
  returning * into v_board;
  perform set_config('lws.requirement_command', '', true);

  v_result := jsonb_build_object(
    'requirements_board_id', v_board.requirements_board_id,
    'project_id', v_board.project_id,
    'quote_request_id', v_board.quote_request_id,
    'status', v_board.status,
    'revision', v_board.revision,
    'replayed', false
  );
  insert into public.audit_events(project_id, event_type, actor, command_id, metadata)
  values (p_project_id, 'REQUIREMENTS_BOARD_FINALIZED', v_auth.audit_actor, p_idempotency_key,
    jsonb_build_object('requirements_board_id', p_requirements_board_id,
      'quote_request_id', p_quote_request_id, 'revision', v_board.revision));
  insert into public.idempotency_ledger(
    actor_id, project_id, command_type, idempotency_key, request_fingerprint,
    result_reference, result_payload
  ) values (
    v_auth.audit_actor, p_project_id, 'finalize_project_requirements_board',
    p_idempotency_key, v_fingerprint, p_requirements_board_id::text, v_result
  );
  return v_result;
end;
$$;

revoke all on function lws_internal.guard_project_requirement_command_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_finalized_project_requirement_definition_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.validate_project_requirement_source_v1(uuid, uuid, jsonb)
from public, anon, authenticated, service_role;
revoke all on function public.resolve_project_requirement_authorization_v1(uuid, uuid, text, boolean)
from public, anon, authenticated, service_role;
revoke all on function public.create_project_requirements_board_v1(uuid, uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.create_project_requirement_v1(uuid, uuid, uuid, bigint, jsonb, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.finalize_project_requirements_board_v1(uuid, uuid, uuid, bigint, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.create_project_requirements_board_v1(uuid, uuid, uuid) to authenticated;
grant execute on function public.create_project_requirement_v1(uuid, uuid, uuid, bigint, jsonb, uuid) to authenticated;
grant execute on function public.finalize_project_requirements_board_v1(uuid, uuid, uuid, bigint, uuid) to authenticated;

comment on table public.project_requirements_boards is
  'Reviewed execution-layer binding to immutable accepted quotation scope; never a second quotation or project-state authority.';
comment on table public.project_requirements is
  'Project-bound Website execution requirements with immutable accepted-source traceability.';
