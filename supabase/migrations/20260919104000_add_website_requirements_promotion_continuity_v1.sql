create table public.website_concept_promotion_commands (
  idempotency_key uuid primary key,
  request_fingerprint_sha256 text not null
    check (request_fingerprint_sha256 ~ '^[0-9a-f]{64}$'),
  actor_id uuid not null references public.commercial_operators(operator_id),
  quote_request_id uuid not null references public.quote_requests(id),
  website_work_context_id uuid not null
    references public.website_work_contexts(website_work_context_id),
  expected_context_revision bigint not null check (expected_context_revision > 0),
  status text not null check (status in ('PENDING', 'COMPLETED')),
  response_payload jsonb,
  promotion_event_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  constraint website_concept_promotion_commands_completion_shape check (
    (status = 'PENDING'
      and response_payload is null
      and promotion_event_id is null
      and completed_at is null)
    or
    (status = 'COMPLETED'
      and jsonb_typeof(response_payload) = 'object'
      and promotion_event_id is not null
      and completed_at is not null)
  )
);

create table public.website_work_context_promotion_events (
  promotion_event_id uuid primary key default extensions.gen_random_uuid(),
  event_type text not null check (event_type = 'WEBSITE_WORK_CONTEXT_PROMOTED'),
  quote_request_id uuid not null references public.quote_requests(id),
  website_work_context_id uuid not null
    references public.website_work_contexts(website_work_context_id),
  concept_id uuid not null references public.website_concepts(concept_id),
  project_id uuid not null references public.commercial_projects(project_id),
  actor_id uuid not null references public.commercial_operators(operator_id),
  previous_phase text not null check (previous_phase = 'PRE_PROJECT'),
  phase text not null check (phase = 'OFFICIAL_PROJECT'),
  previous_context_revision bigint not null check (previous_context_revision > 0),
  context_revision bigint not null check (context_revision = previous_context_revision + 1),
  created_at timestamptz not null default clock_timestamp()
);

alter table public.website_concept_promotion_commands
  add constraint website_concept_promotion_commands_event_fk
  foreign key (promotion_event_id)
  references public.website_work_context_promotion_events(promotion_event_id);

create unique index website_work_context_promotion_events_context_unique
  on public.website_work_context_promotion_events(website_work_context_id);
create index website_work_context_promotion_events_quote_created_idx
  on public.website_work_context_promotion_events(
    quote_request_id, created_at, promotion_event_id
  );

alter table public.website_concept_promotion_commands enable row level security;
alter table public.website_concept_promotion_commands force row level security;
alter table public.website_work_context_promotion_events enable row level security;
alter table public.website_work_context_promotion_events force row level security;

revoke all privileges on table
  public.website_concept_promotion_commands,
  public.website_work_context_promotion_events
from public, anon, authenticated, service_role;

create function lws_internal.guard_website_concept_promotion_command_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if current_setting('lws.website_concept_promotion_command', true)
       is distinct from 'on' then
    raise exception using
      errcode = '55000',
      message = 'DIRECT_WEBSITE_CONCEPT_PROMOTION_WRITE_FORBIDDEN';
  end if;

  if tg_op = 'DELETE' then
    raise exception using
      errcode = '55000',
      message = 'WEBSITE_CONCEPT_PROMOTION_COMMAND_IMMUTABLE';
  end if;

  if tg_op = 'UPDATE' and (
    old.status <> 'PENDING'
    or new.status <> 'COMPLETED'
    or row(
      new.idempotency_key,
      new.request_fingerprint_sha256,
      new.actor_id,
      new.quote_request_id,
      new.website_work_context_id,
      new.expected_context_revision,
      new.created_at
    ) is distinct from row(
      old.idempotency_key,
      old.request_fingerprint_sha256,
      old.actor_id,
      old.quote_request_id,
      old.website_work_context_id,
      old.expected_context_revision,
      old.created_at
    )
  ) then
    raise exception using
      errcode = '55000',
      message = 'WEBSITE_CONCEPT_PROMOTION_COMMAND_IMMUTABLE';
  end if;

  return new;
end;
$$;

create function lws_internal.guard_website_work_context_promotion_event_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op <> 'INSERT' then
    raise exception using
      errcode = '55000',
      message = 'WEBSITE_WORK_CONTEXT_PROMOTION_EVENT_IMMUTABLE';
  end if;

  if current_setting('lws.website_concept_promotion_command', true)
       is distinct from 'on' then
    raise exception using
      errcode = '55000',
      message = 'DIRECT_WEBSITE_CONCEPT_PROMOTION_WRITE_FORBIDDEN';
  end if;

  return new;
end;
$$;

create trigger trg_website_concept_promotion_commands_guard
before insert or update or delete on public.website_concept_promotion_commands
for each row execute function
  lws_internal.guard_website_concept_promotion_command_v1();

create trigger trg_website_work_context_promotion_events_guard
before insert or update or delete on public.website_work_context_promotion_events
for each row execute function
  lws_internal.guard_website_work_context_promotion_event_v1();

create or replace function lws_internal.guard_website_concept_root_write_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_new jsonb := to_jsonb(new);
  v_old jsonb := to_jsonb(old);
begin
  if current_setting('lws.website_concept_command', true) is distinct from 'on' then
    raise exception using
      errcode = '55000',
      message = 'DIRECT_WEBSITE_CONCEPT_WRITE_FORBIDDEN';
  end if;

  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'WEBSITE_CONCEPT_ROOT_IMMUTABLE';
  end if;

  if tg_op = 'UPDATE' then
    if new.revision <> old.revision + 1 then
      raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
    end if;

    if tg_table_name = 'website_concepts'
       and jsonb_build_array(
         v_new->'concept_id', v_new->'quote_request_id', v_new->'mode',
         v_new->'commercially_released', v_new->'created_by', v_new->'created_at'
       ) is distinct from jsonb_build_array(
         v_old->'concept_id', v_old->'quote_request_id', v_old->'mode',
         v_old->'commercially_released', v_old->'created_by', v_old->'created_at'
       ) then
      raise exception using errcode = '55000', message = 'WEBSITE_CONCEPT_IDENTITY_IMMUTABLE';
    end if;

    if tg_table_name = 'website_work_contexts'
       and jsonb_build_array(
         v_new->'website_work_context_id', v_new->'quote_request_id',
         v_new->'concept_id', v_new->'created_at'
       ) is distinct from jsonb_build_array(
         v_old->'website_work_context_id', v_old->'quote_request_id',
         v_old->'concept_id', v_old->'created_at'
       ) then
      raise exception using errcode = '55000', message = 'WEBSITE_WORK_CONTEXT_IDENTITY_IMMUTABLE';
    end if;

    if tg_table_name = 'website_work_contexts'
       and v_old->'project_id' <> 'null'::jsonb
       and v_new->'project_id' is distinct from v_old->'project_id' then
      raise exception using errcode = '55000', message = 'WEBSITE_WORK_CONTEXT_PROJECT_IMMUTABLE';
    end if;

    new.updated_at := clock_timestamp();
  end if;

  return new;
end;
$$;

create function public.promote_website_concept_v1(
  p_quote_request_id uuid,
  p_website_work_context_id uuid,
  p_expected_context_revision bigint,
  p_idempotency_key uuid
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
  v_existing public.website_concept_promotion_commands%rowtype;
  v_context public.website_work_contexts%rowtype;
  v_concept public.website_concepts%rowtype;
  v_project public.commercial_projects%rowtype;
  v_project_ids uuid[];
  v_workspace_id uuid;
  v_workspace_binding_revision bigint;
  v_requirements_board_id uuid;
  v_requirements_board_revision bigint;
  v_event_id uuid := extensions.gen_random_uuid();
  v_promoted_at timestamptz;
  v_fingerprint text;
  v_result jsonb;
begin
  if p_quote_request_id is null
     or p_website_work_context_id is null
     or p_expected_context_revision is null
     or p_expected_context_revision < 1
     or p_idempotency_key is null then
    raise exception using
      errcode = '22023',
      message = 'INVALID_WEBSITE_CONCEPT_PROMOTION_ARGUMENT';
  end if;

  if v_subject is null then
    raise exception using
      errcode = '42501',
      message = 'WEBSITE_CONCEPT_PROMOTION_ACCESS_DENIED';
  end if;

  select operator.*
  into v_operator
  from public.commercial_operators as operator
  where operator.auth_user_id = v_subject;

  if not found or v_operator.status <> 'ACTIVE' then
    raise exception using
      errcode = '42501',
      message = 'WEBSITE_CONCEPT_PROMOTION_ACCESS_DENIED';
  end if;

  if v_operator.role <> 'owner' then
    raise exception using
      errcode = '42501',
      message = 'WEBSITE_CONCEPT_PROMOTION_ROLE_DENIED';
  end if;

  perform lws_internal.assert_operator_aal2_v1();

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'contract_version', 1,
    'action', 'promote_website_concept',
    'actor_id', v_operator.operator_id,
    'quote_request_id', p_quote_request_id,
    'website_work_context_id', p_website_work_context_id,
    'expected_context_revision', p_expected_context_revision
  )::text, 'UTF8'), 'sha256'), 'hex');

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'WEBSITE_CONCEPT_PROMOTION:' || p_idempotency_key::text,
    0
  ));

  select command.*
  into v_existing
  from public.website_concept_promotion_commands as command
  where command.idempotency_key = p_idempotency_key
  FOR UPDATE;

  if found then
    if v_existing.request_fingerprint_sha256 <> v_fingerprint
       or v_existing.status <> 'COMPLETED'
       or v_existing.response_payload is null then
      raise exception using
        errcode = 'P0001',
        message = 'WEBSITE_CONCEPT_PROMOTION_IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.response_payload || jsonb_build_object('replayed', true);
  end if;

  perform set_config('lws.website_concept_promotion_command', 'on', true);

  insert into public.website_concept_promotion_commands(
    idempotency_key,
    request_fingerprint_sha256,
    actor_id,
    quote_request_id,
    website_work_context_id,
    expected_context_revision,
    status
  ) values (
    p_idempotency_key,
    v_fingerprint,
    v_operator.operator_id,
    p_quote_request_id,
    p_website_work_context_id,
    p_expected_context_revision,
    'PENDING'
  );

  select context.*
  into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id = p_website_work_context_id
  FOR UPDATE;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_WORK_CONTEXT_NOT_FOUND';
  end if;

  if v_context.quote_request_id is distinct from p_quote_request_id then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_PROMOTION_CONTEXT_MISMATCH';
  end if;

  select concept.*
  into v_concept
  from public.website_concepts as concept
  where concept.concept_id = v_context.concept_id
  FOR UPDATE;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_CONCEPT_NOT_FOUND';
  end if;

  select array_agg(eligible.project_id order by eligible.project_id)
  into v_project_ids
  from (
    select project.project_id
    from public.commercial_projects as project
    join public.quote_request_quotation_acceptances as acceptance
      on acceptance.id = project.acceptance_id
     and acceptance.issuance_id = project.quotation_issuance_id
    join public.quote_request_quotation_issuances as issuance
      on issuance.id = project.quotation_issuance_id
     and issuance.status = 'ISSUED'
    join public.quote_request_quotation_approvals as approval
      on approval.id = issuance.approval_id
     and approval.quote_request_id = p_quote_request_id
    join public.quote_requests as request
      on request.id = approval.quote_request_id
     and request.record_classification = 'production'
     and request.request_kind = 'website'
    order by project.project_id
    FOR UPDATE OF project
  ) as eligible;

  if coalesce(array_length(v_project_ids, 1), 0) = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_PROMOTION_PROJECT_NOT_FOUND';
  end if;

  if array_length(v_project_ids, 1) <> 1 then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_PROMOTION_PROJECT_AMBIGUOUS';
  end if;

  select project.*
  into v_project
  from public.commercial_projects as project
  where project.project_id = v_project_ids[1]
  FOR UPDATE;

  if lws_internal.resolve_website_project_quote_request_v1(v_project.project_id)
       is distinct from p_quote_request_id then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_PROMOTION_LINEAGE_MISMATCH';
  end if;

  select workspace.website_workspace_id, workspace.binding_revision
  into v_workspace_id, v_workspace_binding_revision
  from public.website_execution_workspaces as workspace
  where workspace.website_work_context_id = p_website_work_context_id
  FOR UPDATE;

  select board.requirements_board_id, board.revision
  into v_requirements_board_id, v_requirements_board_revision
  from public.website_requirements_boards as board
  where board.website_work_context_id = p_website_work_context_id
  FOR UPDATE;

  if v_context.phase = 'OFFICIAL_PROJECT'
     or v_concept.concept_status = 'PROMOTED' then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_CONCEPT_ALREADY_PROMOTED';
  end if;

  if v_context.phase <> 'PRE_PROJECT'
     or v_context.project_id is not null
     or v_concept.concept_status <> 'ACTIVE' then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_CONCEPT_NOT_PRE_PROJECT';
  end if;

  if v_context.revision <> p_expected_context_revision then
    raise exception using
      errcode = '40001',
      message = 'CONCURRENT_MODIFICATION';
  end if;

  if v_concept.quote_request_id is distinct from p_quote_request_id
     or v_context.concept_id is distinct from v_concept.concept_id then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_PROMOTION_CONTEXT_MISMATCH';
  end if;

  if v_workspace_id is not null and not exists (
    select 1
    from public.website_execution_workspaces as workspace
    where workspace.website_workspace_id = v_workspace_id
      and workspace.quote_request_id = p_quote_request_id
      and workspace.project_id is null
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_PROMOTION_WORKSPACE_MISMATCH';
  end if;

  set constraints
    trg_website_concepts_binding,
    trg_website_work_contexts_binding
  deferred;
  perform set_config('lws.website_concept_command', 'on', true);

  update public.website_concepts
  set concept_status = 'PROMOTED',
      promoted_project_id = v_project.project_id,
      promoted_at = clock_timestamp(),
      revision = revision + 1
  where concept_id = v_concept.concept_id;

  update public.website_work_contexts
  set phase = 'OFFICIAL_PROJECT',
      project_id = v_project.project_id,
      revision = revision + 1
  where website_work_context_id = v_context.website_work_context_id;

  if v_workspace_id is not null then
    update public.website_execution_workspaces
    set project_id = v_project.project_id,
        updated_at = clock_timestamp()
    where website_workspace_id = v_workspace_id;
  end if;

  insert into public.website_work_context_promotion_events(
    promotion_event_id,
    event_type,
    quote_request_id,
    website_work_context_id,
    concept_id,
    project_id,
    actor_id,
    previous_phase,
    phase,
    previous_context_revision,
    context_revision
  ) values (
    v_event_id,
    'WEBSITE_WORK_CONTEXT_PROMOTED',
    p_quote_request_id,
    v_context.website_work_context_id,
    v_concept.concept_id,
    v_project.project_id,
    v_operator.operator_id,
    'PRE_PROJECT',
    'OFFICIAL_PROJECT',
    v_context.revision,
    v_context.revision + 1
  )
  returning created_at into v_promoted_at;

  v_result := jsonb_build_object(
    'contract_version', 1,
    'outcome', 'PROMOTED',
    'quote_request_id', p_quote_request_id,
    'website_work_context_id', v_context.website_work_context_id,
    'concept_id', v_concept.concept_id,
    'project_id', v_project.project_id,
    'previous_phase', 'PRE_PROJECT',
    'phase', 'OFFICIAL_PROJECT',
    'previous_context_revision', v_context.revision,
    'context_revision', v_context.revision + 1,
    'website_workspace_id', v_workspace_id,
    'workspace_binding_revision', v_workspace_binding_revision,
    'requirements_board_id', v_requirements_board_id,
    'requirements_board_revision', v_requirements_board_revision,
    'promotion_event_id', v_event_id,
    'promoted_at', v_promoted_at,
    'replayed', false
  );

  update public.website_concept_promotion_commands
  set status = 'COMPLETED',
      response_payload = v_result,
      promotion_event_id = v_event_id,
      completed_at = clock_timestamp()
  where idempotency_key = p_idempotency_key;

  set constraints
    trg_website_concepts_binding,
    trg_website_work_contexts_binding
  immediate;
  perform set_config('lws.website_concept_command', '', true);
  perform set_config('lws.website_concept_promotion_command', '', true);

  return v_result;
exception
  when others then
    perform set_config('lws.website_concept_command', '', true);
    perform set_config('lws.website_concept_promotion_command', '', true);
    raise;
end;
$$;

revoke all on function
  lws_internal.guard_website_concept_promotion_command_v1(),
  lws_internal.guard_website_work_context_promotion_event_v1(),
  public.promote_website_concept_v1(uuid, uuid, bigint, uuid)
from public, anon, authenticated, service_role;

grant execute on function
  public.promote_website_concept_v1(uuid, uuid, bigint, uuid)
to authenticated;

comment on table public.website_concept_promotion_commands is
  'Server-only Website promotion idempotency ledger with exact completed-response replay.';
comment on table public.website_work_context_promotion_events is
  'Append-only audit authority for PRE_PROJECT to OFFICIAL_PROJECT Website continuity.';
comment on function public.promote_website_concept_v1(uuid, uuid, bigint, uuid) is
  'Owner-only AAL2 promotion preserving the existing Website context, workspace, requirements, and evidence identities.';
