alter table public.website_work_contexts
  add constraint website_work_contexts_context_quote_unique
  unique (website_work_context_id, quote_request_id);

create table public.website_requirements_boards (
  requirements_board_id uuid primary key default gen_random_uuid(),
  website_work_context_id uuid not null,
  quote_request_id uuid not null,
  sync_state text not null default 'CURRENT'
    check (sync_state in ('CURRENT', 'REVIEW_REQUIRED')),
  mapping_version integer not null check (mapping_version > 0),
  current_intake_id uuid references public.quote_request_intakes(id),
  current_intake_revision bigint check (current_intake_revision is null or current_intake_revision > 0),
  current_intake_snapshot_sha256 character(64)
    check (current_intake_snapshot_sha256 is null or current_intake_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  revision bigint not null default 1 check (revision > 0),
  created_by uuid not null references public.commercial_operators(operator_id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint website_requirements_boards_context_unique
    unique (website_work_context_id),
  constraint website_requirements_boards_context_quote_fk
    foreign key (website_work_context_id, quote_request_id)
    references public.website_work_contexts(website_work_context_id, quote_request_id),
  constraint website_requirements_boards_authority_unique
    unique (requirements_board_id, website_work_context_id, quote_request_id),
  constraint website_requirements_boards_intake_shape check (
    (current_intake_id is null
      and current_intake_revision is null
      and current_intake_snapshot_sha256 is null)
    or
    (current_intake_id is not null
      and current_intake_revision is not null
      and current_intake_snapshot_sha256 is not null)
  ),
  constraint website_requirements_boards_timestamps_valid
    check (updated_at >= created_at)
);

create table public.website_requirements (
  requirement_id uuid primary key default gen_random_uuid(),
  requirements_board_id uuid not null,
  website_work_context_id uuid not null,
  quote_request_id uuid not null,
  source_key text not null
    check (char_length(btrim(source_key)) between 1 and 160 and source_key !~ '[[:cntrl:]]'),
  source_reference jsonb not null
    check (jsonb_typeof(source_reference) = 'object'
      and not lws_internal.website_concept_jsonb_has_forbidden_key_v1(source_reference)),
  source_value_sha256 character(64) not null
    check (source_value_sha256 ~ '^[0-9a-f]{64}$'),
  item_number integer not null check (item_number > 0),
  sort_order integer not null check (sort_order > 0),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  description text not null check (char_length(btrim(description)) between 1 and 1200),
  category text not null check (category in (
    'PAGE', 'CONTENT', 'DESIGN', 'FORM', 'SEO', 'INTEGRATION', 'AUTOMATION',
    'AUTH', 'ECOMMERCE', 'DOCUMENT_FLOW', 'MULTIMEDIA', 'TECHNICAL', 'OTHER'
  )),
  linked_page_or_module text check (
    linked_page_or_module is null
    or (char_length(btrim(linked_page_or_module)) between 1 and 160
      and linked_page_or_module !~ '^[[:alpha:]][[:alnum:]+.-]*://'
      and linked_page_or_module !~ '[[:cntrl:]]')
  ),
  status text not null default 'PENDING'
    check (status in ('PENDING', 'ACTIVE', 'BLOCKED', 'COMPLETED')),
  completion_mode text not null
    check (completion_mode in ('AUTO', 'OPERATOR', 'HYBRID', 'EXTERNAL')),
  completion_rule_key text
    check (completion_rule_key is null or completion_rule_key ~ '^[a-z][a-z0-9_]{0,63}$'),
  completion_rule_version integer
    check (completion_rule_version is null or completion_rule_version > 0),
  source_review_state text not null default 'CURRENT'
    check (source_review_state in ('CURRENT', 'CHANGE_PENDING', 'REMOVAL_PENDING', 'RETIRED')),
  required boolean not null,
  started_at timestamptz,
  completed_at timestamptz,
  completed_by text check (
    completed_by is null
    or completed_by ~ '^(OPERATOR:[0-9a-f-]{36}|SYSTEM:[a-z][a-z0-9_-]{0,63})$'
  ),
  evidence_summary jsonb
    check (evidence_summary is null
      or (jsonb_typeof(evidence_summary) = 'object'
        and not lws_internal.website_concept_jsonb_has_forbidden_key_v1(evidence_summary))),
  verification_result text not null default 'UNKNOWN'
    check (verification_result in ('PASS', 'FAIL', 'UNKNOWN', 'NOT_APPLICABLE')),
  blocked_reason text
    check (blocked_reason is null or char_length(btrim(blocked_reason)) between 1 and 500),
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint website_requirements_board_fk
    foreign key (requirements_board_id, website_work_context_id, quote_request_id)
    references public.website_requirements_boards(
      requirements_board_id, website_work_context_id, quote_request_id
    ),
  constraint website_requirements_authority_unique
    unique (requirement_id, requirements_board_id, website_work_context_id, quote_request_id),
  constraint website_requirements_rule_shape check (
    (completion_mode = 'OPERATOR'
      and completion_rule_key is null and completion_rule_version is null)
    or
    (completion_mode in ('AUTO', 'HYBRID', 'EXTERNAL')
      and completion_rule_key is not null and completion_rule_version is not null)
  ),
  constraint website_requirements_status_shape check (
    (status = 'PENDING' and completed_at is null and completed_by is null and blocked_reason is null)
    or (status = 'ACTIVE' and started_at is not null and completed_at is null
      and completed_by is null and blocked_reason is null)
    or (status = 'BLOCKED' and completed_at is null and completed_by is null
      and blocked_reason is not null)
    or (status = 'COMPLETED' and completed_at is not null
      and completed_by is not null and blocked_reason is null)
  ),
  constraint website_requirements_timestamps_valid check (
    updated_at >= created_at
    and (started_at is null or started_at >= created_at)
    and (completed_at is null or completed_at >= created_at)
  )
);

create unique index website_requirements_source_key_current_idx
  on public.website_requirements(requirements_board_id, source_key)
  where source_review_state <> 'RETIRED';
create unique index website_requirements_item_number_current_idx
  on public.website_requirements(requirements_board_id, item_number)
  where source_review_state <> 'RETIRED';
create unique index website_requirements_sort_order_current_idx
  on public.website_requirements(requirements_board_id, sort_order)
  where source_review_state <> 'RETIRED';
create unique index website_requirements_one_active_context_idx
  on public.website_requirements(website_work_context_id)
  where status = 'ACTIVE' and source_review_state <> 'RETIRED';
create index website_requirements_context_status_idx
  on public.website_requirements(website_work_context_id, status, sort_order);

create table public.website_requirement_sync_runs (
  sync_run_id uuid primary key default gen_random_uuid(),
  requirements_board_id uuid not null,
  website_work_context_id uuid not null,
  quote_request_id uuid not null,
  intake_id uuid not null references public.quote_request_intakes(id),
  intake_revision bigint not null check (intake_revision > 0),
  intake_snapshot_sha256 character(64) not null
    check (intake_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  mapping_version integer not null check (mapping_version > 0),
  request_fingerprint character(64) not null
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  created_count integer not null check (created_count >= 0),
  updated_count integer not null check (updated_count >= 0),
  retired_count integer not null check (retired_count >= 0),
  review_required_count integer not null check (review_required_count >= 0),
  actor_id text not null
    check (actor_id ~ '^(OPERATOR:[0-9a-f-]{36}|SYSTEM:[a-z][a-z0-9_-]{0,63})$'),
  command_id uuid not null,
  result jsonb not null
    check (jsonb_typeof(result) = 'object'
      and not lws_internal.website_concept_jsonb_has_forbidden_key_v1(result)),
  created_at timestamptz not null default clock_timestamp(),
  constraint website_requirement_sync_runs_board_fk
    foreign key (requirements_board_id, website_work_context_id, quote_request_id)
    references public.website_requirements_boards(
      requirements_board_id, website_work_context_id, quote_request_id
    ),
  constraint website_requirement_sync_runs_command_unique
    unique (requirements_board_id, command_id),
  constraint website_requirement_sync_runs_fingerprint_unique
    unique (requirements_board_id, request_fingerprint)
);

create index website_requirement_sync_runs_context_created_idx
  on public.website_requirement_sync_runs(website_work_context_id, created_at, sync_run_id);

create table public.website_requirement_events (
  event_id uuid primary key default gen_random_uuid(),
  requirements_board_id uuid not null,
  website_work_context_id uuid not null,
  quote_request_id uuid not null,
  requirement_id uuid,
  event_type text not null
    check (event_type ~ '^[A-Z][A-Z0-9_]{0,63}$'),
  actor_id text not null
    check (actor_id ~ '^(OPERATOR:[0-9a-f-]{36}|SYSTEM:[a-z][a-z0-9_-]{0,63})$'),
  command_id uuid not null,
  prior_revision bigint check (prior_revision is null or prior_revision > 0),
  new_revision bigint not null check (new_revision > 0),
  reason text check (reason is null or char_length(btrim(reason)) between 1 and 500),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'
      and not lws_internal.website_concept_jsonb_has_forbidden_key_v1(metadata)),
  occurred_at timestamptz not null default clock_timestamp(),
  constraint website_requirement_events_board_fk
    foreign key (requirements_board_id, website_work_context_id, quote_request_id)
    references public.website_requirements_boards(
      requirements_board_id, website_work_context_id, quote_request_id
    ),
  constraint website_requirement_events_requirement_fk
    foreign key (requirement_id, requirements_board_id, website_work_context_id, quote_request_id)
    references public.website_requirements(
      requirement_id, requirements_board_id, website_work_context_id, quote_request_id
    ),
  constraint website_requirement_events_revision_shape check (
    prior_revision is null or new_revision >= prior_revision
  )
);

create index website_requirement_events_context_occurred_idx
  on public.website_requirement_events(website_work_context_id, occurred_at, event_id);
create index website_requirement_events_requirement_occurred_idx
  on public.website_requirement_events(requirement_id, occurred_at, event_id)
  where requirement_id is not null;

create table public.website_requirement_verifications (
  verification_id uuid primary key default gen_random_uuid(),
  requirement_id uuid not null,
  requirements_board_id uuid not null,
  website_work_context_id uuid not null,
  quote_request_id uuid not null,
  website_workspace_id uuid not null,
  binding_revision bigint not null check (binding_revision > 0),
  canonical_commit_sha character(40) not null
    check (canonical_commit_sha ~ '^[0-9a-f]{40}$'),
  requirement_revision bigint not null check (requirement_revision > 0),
  rule_key text not null check (rule_key ~ '^[a-z][a-z0-9_]{0,63}$'),
  rule_version integer not null check (rule_version > 0),
  result text not null check (result in ('PASS', 'FAIL', 'UNKNOWN', 'NOT_APPLICABLE')),
  evidence_reference jsonb not null
    check (jsonb_typeof(evidence_reference) = 'object'
      and not lws_internal.website_concept_jsonb_has_forbidden_key_v1(evidence_reference)),
  evidence_sha256 character(64) not null
    check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  verified_by text not null
    check (verified_by ~ '^SYSTEM:[a-z][a-z0-9_-]{0,63}$'),
  verified_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz,
  constraint website_requirement_verifications_requirement_fk
    foreign key (requirement_id, requirements_board_id, website_work_context_id, quote_request_id)
    references public.website_requirements(
      requirement_id, requirements_board_id, website_work_context_id, quote_request_id
    ),
  constraint website_requirement_verifications_expiry_valid
    check (expires_at is null or expires_at > verified_at)
);

create index website_requirement_verifications_current_idx
  on public.website_requirement_verifications(
    requirement_id, verified_at desc, verification_id desc
  );

alter table public.website_requirements_boards enable row level security;
alter table public.website_requirements_boards force row level security;
alter table public.website_requirements enable row level security;
alter table public.website_requirements force row level security;
alter table public.website_requirement_sync_runs enable row level security;
alter table public.website_requirement_sync_runs force row level security;
alter table public.website_requirement_events enable row level security;
alter table public.website_requirement_events force row level security;
alter table public.website_requirement_verifications enable row level security;
alter table public.website_requirement_verifications force row level security;

revoke all privileges on table
  public.website_requirements_boards,
  public.website_requirements,
  public.website_requirement_sync_runs,
  public.website_requirement_events,
  public.website_requirement_verifications
from public, anon, authenticated, service_role;

create function lws_internal.guard_website_requirement_command_v1()
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
       or new.quote_request_id is distinct from old.quote_request_id
       or (tg_table_name = 'website_requirements_boards'
         and new.requirements_board_id is distinct from old.requirements_board_id)
       or (tg_table_name = 'website_requirements'
         and (new.requirement_id is distinct from old.requirement_id
           or new.requirements_board_id is distinct from old.requirements_board_id)) then
      raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_IDENTITY_IMMUTABLE';
    end if;

    if tg_table_name = 'website_requirements'
       and old.status <> 'PENDING'
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

  return new;
end;
$$;

create trigger trg_website_requirements_boards_command_guard
before insert or update or delete on public.website_requirements_boards
for each row execute function lws_internal.guard_website_requirement_command_v1();

create trigger trg_website_requirements_command_guard
before insert or update or delete on public.website_requirements
for each row execute function lws_internal.guard_website_requirement_command_v1();

create function lws_internal.guard_website_requirement_history_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op <> 'INSERT' then
    raise exception using errcode = '55000', message = 'WEBSITE_REQUIREMENT_HISTORY_IMMUTABLE';
  end if;

  if current_setting('lws.website_requirement_history_command', true) is distinct from 'on' then
    raise exception using errcode = '55000', message = 'DIRECT_WEBSITE_REQUIREMENT_HISTORY_WRITE_FORBIDDEN';
  end if;

  return new;
end;
$$;

create trigger trg_website_requirement_sync_runs_guard
before insert or update or delete on public.website_requirement_sync_runs
for each row execute function lws_internal.guard_website_requirement_history_v1();

create trigger trg_website_requirement_events_guard
before insert or update or delete on public.website_requirement_events
for each row execute function lws_internal.guard_website_requirement_history_v1();

create trigger trg_website_requirement_verifications_guard
before insert or update or delete on public.website_requirement_verifications
for each row execute function lws_internal.guard_website_requirement_history_v1();

revoke all on function lws_internal.guard_website_requirement_command_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_website_requirement_history_v1()
from public, anon, authenticated, service_role;
