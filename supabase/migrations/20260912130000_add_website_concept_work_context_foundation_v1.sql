create function lws_internal.website_concept_jsonb_has_forbidden_key_v1(
  p_value jsonb
)
returns boolean
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  with recursive nodes(value) as (
    select p_value
    union all
    select child.value
    from nodes
    cross join lateral (
      select object_value as value
      from jsonb_each(
        case when jsonb_typeof(nodes.value) = 'object'
          then nodes.value else '{}'::jsonb end
      ) as object_entry(object_key, object_value)
      union all
      select array_value
      from jsonb_array_elements(
        case when jsonb_typeof(nodes.value) = 'array'
          then nodes.value else '[]'::jsonb end
      ) as array_entry(array_value)
    ) as child
  )
  select exists (
    select 1
    from nodes
    cross join lateral jsonb_object_keys(
      case when jsonb_typeof(nodes.value) = 'object'
        then nodes.value else '{}'::jsonb end
    ) as object_key(key_name)
    where lower(object_key.key_name) ~
      '(token|capability|credential|password|secret|authorization|cookie|customer_content|internal_note|service_role)'
  );
$$;

create table public.website_concepts (
  concept_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null unique
    references public.quote_requests(id),
  mode text not null default 'PRE_PROJECT'
    check (mode = 'PRE_PROJECT'),
  briefing_status text not null
    check (briefing_status in ('LIMITED', 'COMPLETE')),
  commercially_released boolean not null default false
    check (commercially_released = false),
  concept_status text not null default 'ACTIVE'
    check (concept_status in ('ACTIVE', 'PROMOTED')),
  promoted_project_id uuid unique
    references public.commercial_projects(project_id)
    deferrable initially deferred,
  revision bigint not null default 1
    check (revision > 0),
  created_by uuid not null
    references public.commercial_operators(operator_id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  promoted_at timestamptz,
  constraint website_concepts_status_shape check (
    (concept_status = 'ACTIVE'
      and promoted_project_id is null
      and promoted_at is null)
    or
    (concept_status = 'PROMOTED'
      and promoted_project_id is not null
      and promoted_at is not null)
  ),
  constraint website_concepts_timestamp_shape check (
    updated_at >= created_at
    and (promoted_at is null or promoted_at >= created_at)
  )
);

create table public.website_work_contexts (
  website_work_context_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null unique
    references public.quote_requests(id),
  concept_id uuid unique
    references public.website_concepts(concept_id)
    deferrable initially deferred,
  project_id uuid unique
    references public.commercial_projects(project_id)
    deferrable initially deferred,
  phase text not null
    check (phase in ('PRE_PROJECT', 'OFFICIAL_PROJECT')),
  revision bigint not null default 1
    check (revision > 0),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint website_work_contexts_phase_shape check (
    (phase = 'PRE_PROJECT' and concept_id is not null and project_id is null)
    or
    (phase = 'OFFICIAL_PROJECT' and project_id is not null)
  ),
  constraint website_work_contexts_timestamp_shape check (
    updated_at >= created_at
  )
);

create table public.website_concept_events (
  event_id uuid primary key default gen_random_uuid(),
  concept_id uuid not null
    references public.website_concepts(concept_id),
  website_work_context_id uuid not null
    references public.website_work_contexts(website_work_context_id),
  quote_request_id uuid not null
    references public.quote_requests(id),
  event_type text not null
    check (event_type = 'WEBSITE_CONCEPT_STARTED'),
  actor_id uuid not null
    references public.commercial_operators(operator_id),
  actor_role text not null
    check (actor_role = 'owner'),
  command_id uuid not null,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default clock_timestamp(),
  constraint website_concept_events_metadata_safe check (
    jsonb_typeof(metadata) = 'object'
    and not lws_internal.website_concept_jsonb_has_forbidden_key_v1(metadata)
  )
);

create table public.website_concept_idempotency_ledger (
  operation_id uuid primary key default gen_random_uuid(),
  actor_id uuid not null
    references public.commercial_operators(operator_id),
  quote_request_id uuid not null
    references public.quote_requests(id),
  command_type text not null
    check (command_type = 'START_WEBSITE_CONCEPT'),
  idempotency_key uuid not null,
  request_fingerprint character(64) not null
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  result_reference text not null
    check (result_reference ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'),
  result_payload jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint website_concept_idempotency_actor_key_unique
    unique (actor_id, command_type, idempotency_key),
  constraint website_concept_idempotency_dossier_command_unique
    unique (quote_request_id, command_type),
  constraint website_concept_idempotency_result_safe check (
    jsonb_typeof(result_payload) = 'object'
    and result_payload ?& array[
      'state','quote_request_id','concept_id','project_id',
      'website_work_context_id','mode','briefing_status',
      'commercially_released','revision','permitted_actions'
    ]
    and result_payload->>'state' = 'PRE_PROJECT'
    and result_payload->>'mode' = 'PRE_PROJECT'
    and result_payload->>'commercially_released' = 'false'
    and jsonb_typeof(result_payload->'revision') = 'number'
    and jsonb_typeof(result_payload->'permitted_actions') = 'array'
    and not lws_internal.website_concept_jsonb_has_forbidden_key_v1(result_payload)
  )
);

create index website_concept_events_concept_occurred_idx
  on public.website_concept_events(concept_id, occurred_at, event_id);

alter table public.website_concepts enable row level security;
alter table public.website_concepts force row level security;
alter table public.website_work_contexts enable row level security;
alter table public.website_work_contexts force row level security;
alter table public.website_concept_events enable row level security;
alter table public.website_concept_events force row level security;
alter table public.website_concept_idempotency_ledger enable row level security;
alter table public.website_concept_idempotency_ledger force row level security;

revoke all privileges on table
  public.website_concepts,
  public.website_work_contexts,
  public.website_concept_events,
  public.website_concept_idempotency_ledger
from public, anon, authenticated, service_role;

create function lws_internal.resolve_website_project_quote_request_v1(
  p_project_id uuid
)
returns uuid
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_quote_request_id uuid;
begin
  select approval.quote_request_id
  into v_quote_request_id
  from public.commercial_projects as project
  join public.quote_request_quotation_acceptances as acceptance
    on acceptance.id = project.acceptance_id
   and acceptance.issuance_id = project.quotation_issuance_id
  join public.quote_request_quotation_issuances as issuance
    on issuance.id = project.quotation_issuance_id
   and issuance.status = 'ISSUED'
  join public.quote_request_quotation_approvals as approval
    on approval.id = issuance.approval_id
  where project.project_id = p_project_id
  for key share of project, acceptance, issuance, approval;

  return v_quote_request_id;
end;
$$;

create function lws_internal.guard_website_concept_root_write_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
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
       and row(new.concept_id, new.quote_request_id, new.mode, new.commercially_released,
               new.created_by, new.created_at)
           is distinct from
           row(old.concept_id, old.quote_request_id, old.mode, old.commercially_released,
               old.created_by, old.created_at) then
      raise exception using errcode = '55000', message = 'WEBSITE_CONCEPT_IDENTITY_IMMUTABLE';
    end if;

    if tg_table_name = 'website_work_contexts'
       and row(new.website_work_context_id, new.quote_request_id, new.concept_id,
               new.created_at)
           is distinct from
           row(old.website_work_context_id, old.quote_request_id, old.concept_id,
               old.created_at) then
      raise exception using errcode = '55000', message = 'WEBSITE_WORK_CONTEXT_IDENTITY_IMMUTABLE';
    end if;

    if tg_table_name = 'website_work_contexts'
       and old.project_id is not null
       and new.project_id is distinct from old.project_id then
      raise exception using errcode = '55000', message = 'WEBSITE_WORK_CONTEXT_PROJECT_IMMUTABLE';
    end if;

    new.updated_at := clock_timestamp();
  end if;

  return new;
end;
$$;

create function lws_internal.validate_website_concept_binding_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_project_quote_request_id uuid;
begin
  perform 1
  from public.quote_requests as request
  where request.id = new.quote_request_id
    and request.record_classification = 'production'
    and request.request_kind = 'website'
  for key share;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'WEBSITE_CONCEPT_PRODUCTION_WEBSITE_REQUIRED';
  end if;

  perform 1
  from public.commercial_operators as operator
  where operator.operator_id = new.created_by
    and operator.status = 'ACTIVE'
    and operator.role = 'owner'
  for key share;

  if not found then
    raise exception using errcode = '42501', message = 'WEBSITE_CONCEPT_ACTIVE_OWNER_REQUIRED';
  end if;

  if new.promoted_project_id is not null then
    v_project_quote_request_id :=
      lws_internal.resolve_website_project_quote_request_v1(new.promoted_project_id);
    if v_project_quote_request_id is distinct from new.quote_request_id then
      raise exception using
        errcode = 'P0001',
        message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
    end if;
  end if;

  perform 1
  from public.website_work_contexts as context
  where context.concept_id = new.concept_id
    and context.quote_request_id = new.quote_request_id
    and (
      (new.concept_status = 'ACTIVE'
        and context.phase = 'PRE_PROJECT'
        and context.project_id is null)
      or
      (new.concept_status = 'PROMOTED'
        and context.phase = 'OFFICIAL_PROJECT'
        and context.project_id = new.promoted_project_id)
    )
  for key share;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;

  return null;
end;
$$;

create function lws_internal.validate_website_work_context_binding_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_project_quote_request_id uuid;
begin
  perform 1
  from public.quote_requests as request
  where request.id = new.quote_request_id
    and request.record_classification = 'production'
    and request.request_kind = 'website'
  for key share;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'WEBSITE_CONCEPT_PRODUCTION_WEBSITE_REQUIRED';
  end if;

  if new.concept_id is not null then
    perform 1
    from public.website_concepts as concept
    where concept.concept_id = new.concept_id
      and concept.quote_request_id = new.quote_request_id
      and (
        (new.phase = 'PRE_PROJECT' and concept.concept_status = 'ACTIVE')
        or
        (new.phase = 'OFFICIAL_PROJECT'
          and concept.concept_status = 'PROMOTED'
          and concept.promoted_project_id = new.project_id)
      )
    for key share;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
    end if;
  end if;

  if new.project_id is not null then
    v_project_quote_request_id :=
      lws_internal.resolve_website_project_quote_request_v1(new.project_id);
    if v_project_quote_request_id is distinct from new.quote_request_id then
      raise exception using
        errcode = 'P0001',
        message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
    end if;
  end if;

  return null;
end;
$$;

create function lws_internal.guard_website_concept_event_write_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  if tg_op <> 'INSERT' then
    raise exception using errcode = '55000', message = 'WEBSITE_CONCEPT_EVENT_IMMUTABLE';
  end if;

  if current_setting('lws.website_concept_command', true) is distinct from 'on' then
    raise exception using
      errcode = '55000',
      message = 'DIRECT_WEBSITE_CONCEPT_WRITE_FORBIDDEN';
  end if;

  perform 1
  from public.website_concepts as concept
  join public.website_work_contexts as context
    on context.website_work_context_id = new.website_work_context_id
   and context.concept_id = concept.concept_id
   and context.quote_request_id = concept.quote_request_id
  join public.commercial_operators as operator
    on operator.operator_id = new.actor_id
   and operator.status = 'ACTIVE'
   and operator.role = new.actor_role
  where concept.concept_id = new.concept_id
    and concept.quote_request_id = new.quote_request_id
    and new.actor_role = 'owner'
  for key share of concept, context, operator;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;

  return new;
end;
$$;

create function lws_internal.guard_website_concept_idempotency_write_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_concept_id uuid;
begin
  if tg_op <> 'INSERT' then
    raise exception using errcode = '55000', message = 'WEBSITE_CONCEPT_IDEMPOTENCY_IMMUTABLE';
  end if;

  if current_setting('lws.website_concept_command', true) is distinct from 'on' then
    raise exception using
      errcode = '55000',
      message = 'DIRECT_WEBSITE_CONCEPT_WRITE_FORBIDDEN';
  end if;

  begin
    v_concept_id := new.result_reference::uuid;
  exception
    when invalid_text_representation then
      raise exception using errcode = '23514', message = 'WEBSITE_CONCEPT_RESULT_INVALID';
  end;

  perform 1
  from public.website_concepts as concept
  join public.website_work_contexts as context
    on context.concept_id = concept.concept_id
   and context.quote_request_id = concept.quote_request_id
  join public.commercial_operators as operator
    on operator.operator_id = new.actor_id
   and operator.status = 'ACTIVE'
   and operator.role = 'owner'
  where concept.concept_id = v_concept_id
    and concept.quote_request_id = new.quote_request_id
    and new.result_payload->>'quote_request_id' = new.quote_request_id::text
    and new.result_payload->>'concept_id' = concept.concept_id::text
    and new.result_payload->>'website_work_context_id' = context.website_work_context_id::text
    and new.result_payload->'project_id' = 'null'::jsonb
  for key share of concept, context, operator;

  if not found then
    raise exception using errcode = '23514', message = 'WEBSITE_CONCEPT_RESULT_INVALID';
  end if;

  return new;
end;
$$;

create trigger trg_website_concepts_command_guard
before insert or update or delete on public.website_concepts
for each row execute function lws_internal.guard_website_concept_root_write_v1();

create trigger trg_website_work_contexts_command_guard
before insert or update or delete on public.website_work_contexts
for each row execute function lws_internal.guard_website_concept_root_write_v1();

create constraint trigger trg_website_concepts_binding
after insert or update on public.website_concepts
deferrable initially deferred
for each row execute function lws_internal.validate_website_concept_binding_v1();

create constraint trigger trg_website_work_contexts_binding
after insert or update on public.website_work_contexts
deferrable initially deferred
for each row execute function lws_internal.validate_website_work_context_binding_v1();

create trigger trg_website_concept_events_guard
before insert or update or delete on public.website_concept_events
for each row execute function lws_internal.guard_website_concept_event_write_v1();

create trigger trg_website_concept_idempotency_guard
before insert or update or delete on public.website_concept_idempotency_ledger
for each row execute function lws_internal.guard_website_concept_idempotency_write_v1();

revoke all on function
  lws_internal.website_concept_jsonb_has_forbidden_key_v1(jsonb),
  lws_internal.resolve_website_project_quote_request_v1(uuid),
  lws_internal.guard_website_concept_root_write_v1(),
  lws_internal.validate_website_concept_binding_v1(),
  lws_internal.validate_website_work_context_binding_v1(),
  lws_internal.guard_website_concept_event_write_v1(),
  lws_internal.guard_website_concept_idempotency_write_v1()
from public, anon, authenticated, service_role;

comment on table public.website_concepts is
  'Non-commercial Website concept authority. It contains no quotation, payment, release, publication, or customer-access authority.';
comment on table public.website_work_contexts is
  'Stable technical Website identity shared by PRE_PROJECT concepts and accepted official projects.';
comment on table public.website_concept_events is
  'Immutable concept-command audit facts with bounded non-secret metadata.';
comment on table public.website_concept_idempotency_ledger is
  'Immutable Website concept command replay authority with a safe complete result snapshot.';