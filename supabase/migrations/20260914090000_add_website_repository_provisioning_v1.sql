alter table public.website_execution_workspaces
  drop constraint website_execution_workspace_state_valid,
  drop constraint website_execution_workspace_repository_state_valid;

alter table public.website_execution_workspaces
  add column repository_external_id bigint,
  add column repository_node_id text,
  add column repository_visibility text,
  add column repository_state text,
  add column starter_source text,
  add column starter_version text,
  add column starter_commit_sha text,
  add column repository_marker_commit_sha text,
  add column repository_bound_at timestamptz,
  add constraint website_execution_workspace_repository_external_id_valid
    check (
      repository_external_id is null
      or repository_external_id between 1 and 9007199254740991
    ),
  add constraint website_execution_workspace_repository_node_id_valid
    check (
      repository_node_id is null
      or char_length(repository_node_id) between 1 and 255
    ),
  add constraint website_execution_workspace_repository_visibility_valid
    check (repository_visibility is null or repository_visibility = 'private'),
  add constraint website_execution_workspace_repository_state_valid
    check (repository_state is null or repository_state = 'BOUND'),
  add constraint website_execution_workspace_starter_source_valid
    check (
      starter_source is null
      or starter_source ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,98}[A-Za-z0-9]/[A-Za-z0-9][A-Za-z0-9._-]{0,98}[A-Za-z0-9]$'
    ),
  add constraint website_execution_workspace_starter_version_valid
    check (
      starter_version is null
      or starter_version ~ '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$'
    ),
  add constraint website_execution_workspace_starter_commit_valid
    check (
      starter_commit_sha is null
      or starter_commit_sha ~ '^(?:[0-9a-f]{40}|[0-9a-f]{64})$'
    ),
  add constraint website_execution_workspace_marker_commit_valid
    check (
      repository_marker_commit_sha is null
      or repository_marker_commit_sha ~ '^(?:[0-9a-f]{40}|[0-9a-f]{64})$'
    ),
  add constraint website_execution_workspace_state_valid
    check (workspace_state in (
      'PENDING_REPOSITORY',
      'REPOSITORY_PROVISIONING',
      'REPOSITORY_READY',
      'REPOSITORY_FAILED',
      'READY'
    )),
  add constraint website_execution_workspace_repository_binding_shape check (
    (
      workspace_state in (
        'PENDING_REPOSITORY',
        'REPOSITORY_PROVISIONING',
        'REPOSITORY_FAILED'
      )
      and repository_owner is null
      and repository_name is null
      and preview_branch is null
      and preview_url is null
      and last_commit_sha is null
      and last_commit_at is null
      and last_build_result is null
      and last_build_at is null
      and repository_external_id is null
      and repository_node_id is null
      and repository_visibility is null
      and repository_state is null
      and starter_source is null
      and starter_version is null
      and starter_commit_sha is null
      and repository_marker_commit_sha is null
      and repository_bound_at is null
    )
    or
    (
      workspace_state = 'REPOSITORY_READY'
      and repository_owner is not null
      and repository_name is not null
      and repository_external_id is not null
      and repository_node_id is not null
      and repository_visibility = 'private'
      and repository_state = 'BOUND'
      and starter_source is not null
      and starter_version is not null
      and starter_commit_sha is not null
      and repository_marker_commit_sha is not null
      and repository_bound_at is not null
    )
    or
    (
      workspace_state = 'READY'
      and repository_owner is not null
      and repository_name is not null
      and repository_external_id is null
      and repository_node_id is null
      and repository_visibility is null
      and repository_state is null
      and starter_source is null
      and starter_version is null
      and starter_commit_sha is null
      and repository_marker_commit_sha is null
      and repository_bound_at is null
    )
  );

create unique index website_execution_workspace_repository_external_id_unique
  on public.website_execution_workspaces(repository_external_id)
  where repository_external_id is not null;

create table public.website_repository_provisioning_operations (
  operation_id uuid primary key default gen_random_uuid(),
  website_workspace_id uuid not null
    references public.website_execution_workspaces(website_workspace_id),
  website_work_context_id uuid not null
    references public.website_work_contexts(website_work_context_id),
  actor_id uuid not null
    references public.commercial_operators(operator_id),
  idempotency_key uuid not null,
  request_fingerprint character(64) not null
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  repository_provider text not null default 'GITHUB'
    check (repository_provider = 'GITHUB'),
  repository_owner text not null
    check (repository_owner ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,98}[A-Za-z0-9]$'),
  repository_name text not null
    check (repository_name ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,98}[A-Za-z0-9]$'),
  starter_source text not null
    check (starter_source ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,98}[A-Za-z0-9]/[A-Za-z0-9][A-Za-z0-9._-]{0,98}[A-Za-z0-9]$'),
  starter_version text not null
    check (starter_version ~ '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$'),
  starter_commit_sha text not null
    check (starter_commit_sha ~ '^(?:[0-9a-f]{40}|[0-9a-f]{64})$'),
  state text not null default 'CLAIMED',
  attempt_count integer not null default 0
    check (attempt_count >= 0),
  failure_code text
    check (
      failure_code is null
      or failure_code ~ '^[A-Z][A-Z0-9_]{0,127}$'
    ),
  retry_at timestamptz,
  repository_external_id bigint
    check (
      repository_external_id is null
      or repository_external_id between 1 and 9007199254740991
    ),
  repository_node_id text
    check (
      repository_node_id is null
      or char_length(repository_node_id) between 1 and 255
    ),
  claimed_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  external_created_at timestamptz,
  bound_at timestamptz,
  constraint website_repository_operation_actor_key_unique
    unique (actor_id, idempotency_key),
  constraint website_repository_operation_state_valid check (state in (
    'CLAIMED',
    'CREATING',
    'EXTERNAL_CREATED',
    'VERIFYING',
    'BOUND',
    'RETRYABLE_FAILED',
    'BLOCKED',
    'QUARANTINED',
    'TERMINAL_FAILED'
  )),
  constraint website_repository_operation_external_identity_shape check (
    (
      repository_external_id is null
      and repository_node_id is null
      and external_created_at is null
    )
    or (
      repository_external_id is not null
      and repository_node_id is not null
      and external_created_at is not null
    )
  ),
  constraint website_repository_operation_state_identity_shape check (
    (state in ('CLAIMED', 'CREATING') and repository_external_id is null)
    or (state in ('EXTERNAL_CREATED', 'VERIFYING', 'BOUND', 'QUARANTINED')
      and repository_external_id is not null)
    or state in ('RETRYABLE_FAILED', 'BLOCKED', 'TERMINAL_FAILED')
  ),
  constraint website_repository_operation_failure_shape check (
    (state in ('RETRYABLE_FAILED', 'BLOCKED', 'QUARANTINED', 'TERMINAL_FAILED')
      and failure_code is not null)
    or
    (state not in ('RETRYABLE_FAILED', 'BLOCKED', 'QUARANTINED', 'TERMINAL_FAILED')
      and failure_code is null)
  ),
  constraint website_repository_operation_retry_shape check (
    (state = 'RETRYABLE_FAILED' and retry_at is not null)
    or (state <> 'RETRYABLE_FAILED' and retry_at is null)
  ),
  constraint website_repository_operation_bound_shape check (
    (state = 'BOUND' and bound_at is not null)
    or (state <> 'BOUND' and bound_at is null)
  ),
  constraint website_repository_operation_timestamp_shape check (
    updated_at >= claimed_at
    and (external_created_at is null or external_created_at >= claimed_at)
    and (bound_at is null or bound_at >= claimed_at)
    and (retry_at is null or retry_at >= claimed_at)
  )
);

create unique index website_repository_operation_external_id_unique
  on public.website_repository_provisioning_operations(repository_external_id)
  where repository_external_id is not null;

create unique index website_repository_operation_active_workspace_unique
  on public.website_repository_provisioning_operations(website_workspace_id)
  where state not in ('BOUND', 'TERMINAL_FAILED');

create unique index website_repository_operation_active_context_unique
  on public.website_repository_provisioning_operations(website_work_context_id)
  where state not in ('BOUND', 'TERMINAL_FAILED');

create unique index website_repository_operation_bound_workspace_unique
  on public.website_repository_provisioning_operations(website_workspace_id)
  where state = 'BOUND';

create unique index website_repository_operation_bound_context_unique
  on public.website_repository_provisioning_operations(website_work_context_id)
  where state = 'BOUND';

create table public.website_repository_provisioning_events (
  event_id uuid primary key default gen_random_uuid(),
  operation_id uuid not null
    references public.website_repository_provisioning_operations(operation_id),
  website_workspace_id uuid not null
    references public.website_execution_workspaces(website_workspace_id),
  website_work_context_id uuid not null
    references public.website_work_contexts(website_work_context_id),
  actor_id uuid not null
    references public.commercial_operators(operator_id),
  request_fingerprint character(64) not null
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  event_type text not null
    check (event_type ~ '^[A-Z][A-Z0-9_]{0,127}$'),
  previous_state text,
  new_state text not null
    check (new_state in (
      'CLAIMED', 'CREATING', 'EXTERNAL_CREATED', 'VERIFYING', 'BOUND',
      'RETRYABLE_FAILED', 'BLOCKED', 'QUARANTINED', 'TERMINAL_FAILED'
    )),
  repository_provider text not null
    check (repository_provider = 'GITHUB'),
  repository_owner text not null
    check (repository_owner ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,98}[A-Za-z0-9]$'),
  repository_name text not null
    check (repository_name ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,98}[A-Za-z0-9]$'),
  repository_external_id bigint
    check (
      repository_external_id is null
      or repository_external_id between 1 and 9007199254740991
    ),
  starter_source text not null
    check (starter_source ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,98}[A-Za-z0-9]/[A-Za-z0-9][A-Za-z0-9._-]{0,98}[A-Za-z0-9]$'),
  starter_version text not null
    check (starter_version ~ '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$'),
  starter_commit_sha text not null
    check (starter_commit_sha ~ '^(?:[0-9a-f]{40}|[0-9a-f]{64})$'),
  attempt_number integer not null
    check (attempt_number >= 0),
  result_code text not null
    check (result_code ~ '^[A-Z][A-Z0-9_]{0,127}$'),
  github_request_id text
    check (
      github_request_id is null
      or github_request_id ~ '^[A-Za-z0-9._:-]{1,255}$'
    ),
  occurred_at timestamptz not null default clock_timestamp(),
  constraint website_repository_event_previous_state_valid check (
    previous_state is null
    or previous_state in (
      'CLAIMED', 'CREATING', 'EXTERNAL_CREATED', 'VERIFYING', 'BOUND',
      'RETRYABLE_FAILED', 'BLOCKED', 'QUARANTINED', 'TERMINAL_FAILED'
    )
  )
);

create function lws_internal.guard_website_repository_operation_identity_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_context_id uuid;
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = '55000',
      message = 'WEBSITE_REPOSITORY_OPERATION_IMMUTABLE';
  end if;

  select workspace.website_work_context_id
  into v_context_id
  from public.website_execution_workspaces as workspace
  where workspace.website_workspace_id = new.website_workspace_id;

  if v_context_id is distinct from new.website_work_context_id then
    raise exception using
      errcode = '23514',
      message = 'WEBSITE_REPOSITORY_OPERATION_BINDING_MISMATCH';
  end if;

  if tg_op = 'UPDATE' and (
    new.operation_id is distinct from old.operation_id
    or new.website_workspace_id is distinct from old.website_workspace_id
    or new.website_work_context_id is distinct from old.website_work_context_id
    or new.actor_id is distinct from old.actor_id
    or new.idempotency_key is distinct from old.idempotency_key
    or new.request_fingerprint is distinct from old.request_fingerprint
    or new.repository_provider is distinct from old.repository_provider
    or new.repository_owner is distinct from old.repository_owner
    or new.repository_name is distinct from old.repository_name
    or new.starter_source is distinct from old.starter_source
    or new.starter_version is distinct from old.starter_version
    or new.starter_commit_sha is distinct from old.starter_commit_sha
    or new.claimed_at is distinct from old.claimed_at
  ) then
    raise exception using
      errcode = '55000',
      message = 'WEBSITE_REPOSITORY_OPERATION_IDENTITY_IMMUTABLE';
  end if;

  if tg_op = 'UPDATE' and (
    (old.repository_external_id is not null
      and new.repository_external_id is distinct from old.repository_external_id)
    or (old.repository_node_id is not null
      and new.repository_node_id is distinct from old.repository_node_id)
    or (old.external_created_at is not null
      and new.external_created_at is distinct from old.external_created_at)
  ) then
    raise exception using
      errcode = '55000',
      message = 'WEBSITE_REPOSITORY_EXTERNAL_IDENTITY_IMMUTABLE';
  end if;

  return new;
end;
$$;

create function lws_internal.guard_website_repository_binding_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if old.repository_external_id is not null and (
    new.repository_external_id is distinct from old.repository_external_id
    or new.repository_node_id is distinct from old.repository_node_id
    or new.repository_visibility is distinct from old.repository_visibility
    or new.repository_state is distinct from old.repository_state
    or new.repository_owner is distinct from old.repository_owner
    or new.repository_name is distinct from old.repository_name
    or new.starter_source is distinct from old.starter_source
    or new.starter_version is distinct from old.starter_version
    or new.starter_commit_sha is distinct from old.starter_commit_sha
    or new.repository_marker_commit_sha is distinct from old.repository_marker_commit_sha
    or new.repository_bound_at is distinct from old.repository_bound_at
  ) then
    raise exception using
      errcode = '55000',
      message = 'WEBSITE_REPOSITORY_BINDING_IMMUTABLE';
  end if;
  return new;
end;
$$;

create function lws_internal.guard_website_repository_event_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_operation public.website_repository_provisioning_operations%rowtype;
begin
  if tg_op <> 'INSERT' then
    raise exception using
      errcode = '55000',
      message = 'WEBSITE_REPOSITORY_EVENT_IMMUTABLE';
  end if;

  select operation.*
  into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.operation_id = new.operation_id;

  if not found
     or v_operation.website_workspace_id is distinct from new.website_workspace_id
     or v_operation.website_work_context_id is distinct from new.website_work_context_id
     or v_operation.actor_id is distinct from new.actor_id
     or v_operation.request_fingerprint is distinct from new.request_fingerprint
     or v_operation.repository_provider is distinct from new.repository_provider
     or v_operation.repository_owner is distinct from new.repository_owner
     or v_operation.repository_name is distinct from new.repository_name
     or v_operation.starter_source is distinct from new.starter_source
     or v_operation.starter_version is distinct from new.starter_version
     or v_operation.starter_commit_sha is distinct from new.starter_commit_sha
     or (new.repository_external_id is not null
       and v_operation.repository_external_id is distinct from new.repository_external_id)
     or v_operation.state is distinct from new.new_state then
    raise exception using
      errcode = '23514',
      message = 'WEBSITE_REPOSITORY_EVENT_BINDING_MISMATCH';
  end if;

  return new;
end;
$$;

create trigger trg_website_repository_operation_identity_guard
before insert or update or delete
on public.website_repository_provisioning_operations
for each row execute function
  lws_internal.guard_website_repository_operation_identity_v1();

create trigger trg_website_repository_binding_guard
before update on public.website_execution_workspaces
for each row execute function
  lws_internal.guard_website_repository_binding_v1();

create trigger trg_website_repository_event_immutable
before insert or update or delete
on public.website_repository_provisioning_events
for each row execute function
  lws_internal.guard_website_repository_event_v1();

alter table public.website_repository_provisioning_operations enable row level security;
alter table public.website_repository_provisioning_operations force row level security;
alter table public.website_repository_provisioning_events enable row level security;
alter table public.website_repository_provisioning_events force row level security;

revoke all privileges on table
  public.website_repository_provisioning_operations,
  public.website_repository_provisioning_events
from public, anon, authenticated, service_role;

revoke all on function
  lws_internal.guard_website_repository_operation_identity_v1(),
  lws_internal.guard_website_repository_binding_v1(),
  lws_internal.guard_website_repository_event_v1()
from public, anon, authenticated, service_role;

comment on table public.website_repository_provisioning_operations is
  'Durable server-only repository provisioning authority; contains no credentials, source content, customer PII, or independent repository URL.';

comment on table public.website_repository_provisioning_events is
  'Append-only redacted repository lifecycle events correlated to one operation, workspace, and work context.';