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
  if current_setting('lws.website_repository_command', true) is distinct from 'on' then
    raise exception using
      errcode = '55000',
      message = 'DIRECT_WEBSITE_REPOSITORY_OPERATION_WRITE_FORBIDDEN';
  end if;

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
  if row(
    new.workspace_state,new.repository_external_id,new.repository_node_id,
    new.repository_visibility,new.repository_state,new.repository_owner,
    new.repository_name,new.starter_source,new.starter_version,
    new.starter_commit_sha,new.repository_marker_commit_sha,
    new.repository_bound_at
  ) is distinct from row(
    old.workspace_state,old.repository_external_id,old.repository_node_id,
    old.repository_visibility,old.repository_state,old.repository_owner,
    old.repository_name,old.starter_source,old.starter_version,
    old.starter_commit_sha,old.repository_marker_commit_sha,
    old.repository_bound_at
  ) and current_setting('lws.website_repository_command', true) is distinct from 'on' then
    raise exception using
      errcode = '55000',
      message = 'DIRECT_WEBSITE_REPOSITORY_BINDING_WRITE_FORBIDDEN';
  end if;

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
  if current_setting('lws.website_repository_command', true) is distinct from 'on' then
    raise exception using
      errcode = '55000',
      message = 'DIRECT_WEBSITE_REPOSITORY_EVENT_WRITE_FORBIDDEN';
  end if;

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

create function lws_internal.require_website_repository_owner_v1()
returns public.commercial_operators
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

  select operator.* into v_operator
  from public.commercial_operators as operator
  where operator.auth_user_id = v_subject;

  if not found
     or v_operator.status <> 'ACTIVE'
     or v_operator.role <> 'owner' then
    raise exception using
      errcode = '42501',
      message = 'WEBSITE_REPOSITORY_OWNER_REQUIRED';
  end if;

  perform lws_internal.assert_operator_aal2_v1();
  return v_operator;
end;
$$;

create function lws_internal.website_repository_operation_result_v1(
  p_operation public.website_repository_provisioning_operations,
  p_result text
)
returns jsonb
language sql
stable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'result', p_result,
    'operation_id', p_operation.operation_id,
    'website_workspace_id', p_operation.website_workspace_id,
    'website_work_context_id', p_operation.website_work_context_id,
    'state', p_operation.state,
    'repository_provider', p_operation.repository_provider,
    'repository_owner', p_operation.repository_owner,
    'repository_name', p_operation.repository_name,
    'starter_source', p_operation.starter_source,
    'starter_version', p_operation.starter_version,
    'starter_commit_sha', p_operation.starter_commit_sha,
    'repository_external_id', p_operation.repository_external_id::text,
    'repository_node_id', p_operation.repository_node_id,
    'attempt_count', p_operation.attempt_count,
    'failure_code', p_operation.failure_code,
    'retry_at', p_operation.retry_at,
    'claimed_at', p_operation.claimed_at,
    'updated_at', p_operation.updated_at,
    'external_created_at', p_operation.external_created_at,
    'bound_at', p_operation.bound_at
  )
$$;

create function public.claim_website_repository_provisioning_v1(
  p_website_workspace_id uuid,
  p_website_work_context_id uuid,
  p_idempotency_key uuid,
  p_starter_source text,
  p_starter_version text,
  p_starter_commit_sha text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_context public.website_work_contexts%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_repository_owner text;
  v_repository_name text;
  v_fingerprint character(64);
begin
  if p_website_workspace_id is null
     or p_website_work_context_id is null
     or p_idempotency_key is null
     or p_starter_source !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,98}[A-Za-z0-9]/[A-Za-z0-9][A-Za-z0-9._-]{0,98}[A-Za-z0-9]$'
     or p_starter_version !~ '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$'
     or p_starter_commit_sha !~ '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' then
    raise exception using
      errcode = '22023',
      message = 'INVALID_WEBSITE_REPOSITORY_CLAIM';
  end if;

  v_operator := lws_internal.require_website_repository_owner_v1();

  select workspace.* into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_workspace_id = p_website_workspace_id
  for update;

  select context.* into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id = p_website_work_context_id
  for update;

  if v_workspace.website_workspace_id is null
     or v_context.website_work_context_id is null
     or v_workspace.website_work_context_id is distinct from v_context.website_work_context_id
     or v_workspace.quote_request_id is distinct from v_context.quote_request_id
     or v_context.phase <> 'PRE_PROJECT'
     or v_context.project_id is not null then
    raise exception using
      errcode = '42501',
      message = 'WEBSITE_REPOSITORY_CONTEXT_DENIED';
  end if;

  v_repository_owner := case
    when exists (
      select 1 from public.quote_requests as request
      where request.id = v_context.quote_request_id
        and request.record_classification = 'internal_e2e'
    ) then 'lorenzo-web-solutions-lab'
    else 'lorenzo-web-solutions'
  end;
  v_repository_name := 'lws-web-' || replace(lower(v_context.website_work_context_id::text), '-', '');

  if split_part(p_starter_source, '/', 1) <> v_repository_owner then
    raise exception using
      errcode = '22023',
      message = 'WEBSITE_REPOSITORY_STARTER_OWNER_INVALID';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'authority_version', 'website_repository_provisioning_v1',
    'website_workspace_id', p_website_workspace_id,
    'website_work_context_id', p_website_work_context_id,
    'repository_name', v_repository_name,
    'starter_source', p_starter_source,
    'starter_version', p_starter_version,
    'starter_commit_sha', p_starter_commit_sha
  )::text, 'UTF8'), 'sha256'), 'hex')::character(64);

  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.actor_id = v_operator.operator_id
    and operation.idempotency_key = p_idempotency_key;

  if found then
    if v_operation.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return lws_internal.website_repository_operation_result_v1(
      v_operation, 'REPLAY'
    );
  end if;

  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.website_workspace_id = p_website_workspace_id
     or operation.website_work_context_id = p_website_work_context_id
  order by operation.claimed_at desc
  limit 1;

  if found and v_operation.state not in ('BOUND', 'TERMINAL_FAILED') then
    return lws_internal.website_repository_operation_result_v1(
      v_operation, 'IN_PROGRESS'
    );
  end if;
  if found and v_operation.state = 'BOUND' then
    return lws_internal.website_repository_operation_result_v1(
      v_operation, 'REPLAY'
    );
  end if;

  if v_workspace.workspace_state not in ('PENDING_REPOSITORY', 'REPOSITORY_FAILED') then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_REPOSITORY_LIFECYCLE_INVALID';
  end if;

  perform set_config('lws.website_repository_command', 'on', true);
  insert into public.website_repository_provisioning_operations(
    website_workspace_id,website_work_context_id,actor_id,idempotency_key,
    request_fingerprint,repository_provider,repository_owner,repository_name,
    starter_source,starter_version,starter_commit_sha,state,attempt_count
  ) values (
    p_website_workspace_id,p_website_work_context_id,v_operator.operator_id,
    p_idempotency_key,v_fingerprint,'GITHUB',v_repository_owner,
    v_repository_name,p_starter_source,p_starter_version,p_starter_commit_sha,
    'CLAIMED',0
  ) returning * into v_operation;

  update public.website_execution_workspaces
  set workspace_state='REPOSITORY_PROVISIONING',updated_at=clock_timestamp()
  where website_workspace_id=p_website_workspace_id;

  insert into public.website_repository_provisioning_events(
    operation_id,website_workspace_id,website_work_context_id,actor_id,
    request_fingerprint,event_type,previous_state,new_state,
    repository_provider,repository_owner,repository_name,starter_source,
    starter_version,starter_commit_sha,attempt_number,result_code
  ) values (
    v_operation.operation_id,p_website_workspace_id,p_website_work_context_id,
    v_operator.operator_id,v_fingerprint,'REPOSITORY_PROVISIONING_CLAIMED',
    null,'CLAIMED','GITHUB',v_repository_owner,v_repository_name,
    p_starter_source,p_starter_version,p_starter_commit_sha,0,'CLAIMED'
  );
  perform set_config('lws.website_repository_command', '', true);

  return lws_internal.website_repository_operation_result_v1(
    v_operation, 'CLAIMED'
  );
exception when others then
  perform set_config('lws.website_repository_command', '', true);
  raise;
end;
$$;

create function public.record_website_repository_external_identity_v1(
  p_operation_id uuid,
  p_repository_external_id text,
  p_repository_node_id text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_external_id bigint;
begin
  if p_operation_id is null
     or p_repository_external_id !~ '^[1-9][0-9]{0,15}$'
     or nullif(btrim(p_repository_node_id), '') is null
     or char_length(p_repository_node_id) > 255 then
    raise exception using
      errcode = '22023',
      message = 'INVALID_WEBSITE_REPOSITORY_EXTERNAL_IDENTITY';
  end if;
  v_external_id := p_repository_external_id::bigint;
  if v_external_id > 9007199254740991 then
    raise exception using
      errcode = '22023',
      message = 'INVALID_WEBSITE_REPOSITORY_EXTERNAL_IDENTITY';
  end if;

  v_operator := lws_internal.require_website_repository_owner_v1();
  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.operation_id = p_operation_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'WEBSITE_REPOSITORY_OPERATION_NOT_FOUND';
  end if;
  if v_operation.actor_id <> v_operator.operator_id then
    raise exception using errcode = '42501', message = 'WEBSITE_REPOSITORY_OPERATION_DENIED';
  end if;
  if v_operation.repository_external_id is not null then
    if v_operation.repository_external_id = v_external_id
       and v_operation.repository_node_id = p_repository_node_id then
      return lws_internal.website_repository_operation_result_v1(v_operation, 'REPLAY');
    end if;
    raise exception using errcode = 'P0001', message = 'WEBSITE_REPOSITORY_IDENTITY_MISMATCH';
  end if;
  if v_operation.state not in ('CLAIMED', 'CREATING') then
    raise exception using errcode = 'P0001', message = 'WEBSITE_REPOSITORY_TRANSITION_INVALID';
  end if;

  perform set_config('lws.website_repository_command', 'on', true);
  update public.website_repository_provisioning_operations
  set state='EXTERNAL_CREATED',repository_external_id=v_external_id,
      repository_node_id=p_repository_node_id,
      external_created_at=clock_timestamp(),updated_at=clock_timestamp()
  where operation_id=p_operation_id
  returning * into v_operation;

  insert into public.website_repository_provisioning_events(
    operation_id,website_workspace_id,website_work_context_id,actor_id,
    request_fingerprint,event_type,previous_state,new_state,
    repository_provider,repository_owner,repository_name,
    repository_external_id,starter_source,starter_version,starter_commit_sha,
    attempt_number,result_code
  ) values (
    v_operation.operation_id,v_operation.website_workspace_id,
    v_operation.website_work_context_id,v_operator.operator_id,
    v_operation.request_fingerprint,'REPOSITORY_EXTERNAL_IDENTITY_CAPTURED',
    'CLAIMED','EXTERNAL_CREATED',v_operation.repository_provider,
    v_operation.repository_owner,v_operation.repository_name,
    v_operation.repository_external_id,v_operation.starter_source,
    v_operation.starter_version,v_operation.starter_commit_sha,
    v_operation.attempt_count,'EXTERNAL_CREATED'
  );
  perform set_config('lws.website_repository_command', '', true);
  return lws_internal.website_repository_operation_result_v1(
    v_operation, 'EXTERNAL_CREATED'
  );
exception when others then
  perform set_config('lws.website_repository_command', '', true);
  raise;
end;
$$;

create function public.bind_website_repository_v1(
  p_operation_id uuid,
  p_verification jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_external_id bigint;
  v_marker_sha text;
begin
  if p_operation_id is null
     or jsonb_typeof(p_verification) <> 'object'
     or not p_verification ?& array[
       'operation_id','website_workspace_id','website_work_context_id',
       'repository_external_id','repository_node_id','repository_owner',
       'repository_name','repository_visibility','default_branch',
       'starter_source','starter_version','starter_commit_sha',
       'repository_marker_commit_sha'
     ]
     or exists (
       select 1 from jsonb_object_keys(p_verification) as supplied(key)
       where supplied.key <> all(array[
         'operation_id','website_workspace_id','website_work_context_id',
         'repository_external_id','repository_node_id','repository_owner',
         'repository_name','repository_visibility','default_branch',
         'starter_source','starter_version','starter_commit_sha',
         'repository_marker_commit_sha'
       ])
     )
     or p_verification->>'repository_external_id' !~ '^[1-9][0-9]{0,15}$' then
    raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REPOSITORY_BINDING';
  end if;

  v_external_id := (p_verification->>'repository_external_id')::bigint;
  v_marker_sha := p_verification->>'repository_marker_commit_sha';
  if v_external_id > 9007199254740991
     or v_marker_sha !~ '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' then
    raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REPOSITORY_BINDING';
  end if;

  v_operator := lws_internal.require_website_repository_owner_v1();
  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.operation_id=p_operation_id
  for update;

  if not found then
    raise exception using errcode='23503',message='WEBSITE_REPOSITORY_OPERATION_NOT_FOUND';
  end if;
  if v_operation.actor_id <> v_operator.operator_id then
    raise exception using errcode='42501',message='WEBSITE_REPOSITORY_OPERATION_DENIED';
  end if;

  select workspace.* into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_workspace_id=v_operation.website_workspace_id
  for update;

  if v_workspace.website_work_context_id is distinct from v_operation.website_work_context_id
     or p_verification->>'operation_id' <> v_operation.operation_id::text
     or p_verification->>'website_workspace_id' <> v_operation.website_workspace_id::text
     or p_verification->>'website_work_context_id' <> v_operation.website_work_context_id::text
     or v_external_id <> v_operation.repository_external_id
     or p_verification->>'repository_node_id' <> v_operation.repository_node_id
     or p_verification->>'repository_owner' <> v_operation.repository_owner
     or p_verification->>'repository_name' <> v_operation.repository_name
     or p_verification->>'repository_visibility' <> 'private'
     or p_verification->>'default_branch' <> 'main'
     or p_verification->>'starter_source' <> v_operation.starter_source
     or p_verification->>'starter_version' <> v_operation.starter_version
     or p_verification->>'starter_commit_sha' <> v_operation.starter_commit_sha
     or (
       v_operation.state = 'BOUND'
       and (
         v_workspace.repository_external_id is distinct from v_external_id
         or v_workspace.repository_node_id is distinct from p_verification->>'repository_node_id'
         or v_workspace.repository_owner is distinct from p_verification->>'repository_owner'
         or v_workspace.repository_name is distinct from p_verification->>'repository_name'
         or v_workspace.repository_visibility is distinct from p_verification->>'repository_visibility'
         or v_workspace.default_branch is distinct from p_verification->>'default_branch'
         or v_workspace.starter_source is distinct from p_verification->>'starter_source'
         or v_workspace.starter_version is distinct from p_verification->>'starter_version'
         or v_workspace.starter_commit_sha is distinct from p_verification->>'starter_commit_sha'
         or v_workspace.repository_marker_commit_sha is distinct from v_marker_sha
       )
     ) then
    raise exception using errcode='P0001',message='WEBSITE_REPOSITORY_BINDING_MISMATCH';
  end if;
  if v_operation.state = 'BOUND' then
    return lws_internal.website_repository_operation_result_v1(v_operation, 'REPLAY');
  end if;
  if v_operation.state <> 'EXTERNAL_CREATED' then
    raise exception using errcode='P0001',message='WEBSITE_REPOSITORY_TRANSITION_INVALID';
  end if;

  perform set_config('lws.website_repository_command', 'on', true);
  update public.website_repository_provisioning_operations
  set state='VERIFYING',updated_at=clock_timestamp()
  where operation_id=p_operation_id
  returning * into v_operation;

  update public.website_execution_workspaces
  set workspace_state='REPOSITORY_READY',
      repository_owner=v_operation.repository_owner,
      repository_name=v_operation.repository_name,
      repository_external_id=v_operation.repository_external_id,
      repository_node_id=v_operation.repository_node_id,
      repository_visibility='private',repository_state='BOUND',
      starter_source=v_operation.starter_source,
      starter_version=v_operation.starter_version,
      starter_commit_sha=v_operation.starter_commit_sha,
      repository_marker_commit_sha=v_marker_sha,
      repository_bound_at=clock_timestamp(),updated_at=clock_timestamp()
  where website_workspace_id=v_operation.website_workspace_id;

  update public.website_repository_provisioning_operations
  set state='BOUND',bound_at=clock_timestamp(),updated_at=clock_timestamp()
  where operation_id=p_operation_id
  returning * into v_operation;

  insert into public.website_repository_provisioning_events(
    operation_id,website_workspace_id,website_work_context_id,actor_id,
    request_fingerprint,event_type,previous_state,new_state,
    repository_provider,repository_owner,repository_name,
    repository_external_id,starter_source,starter_version,starter_commit_sha,
    attempt_number,result_code
  ) values (
    v_operation.operation_id,v_operation.website_workspace_id,
    v_operation.website_work_context_id,v_operator.operator_id,
    v_operation.request_fingerprint,'REPOSITORY_BOUND','EXTERNAL_CREATED','BOUND',
    v_operation.repository_provider,v_operation.repository_owner,
    v_operation.repository_name,v_operation.repository_external_id,
    v_operation.starter_source,v_operation.starter_version,
    v_operation.starter_commit_sha,v_operation.attempt_count,'BOUND'
  );
  perform set_config('lws.website_repository_command', '', true);
  return lws_internal.website_repository_operation_result_v1(v_operation, 'BOUND');
exception when others then
  perform set_config('lws.website_repository_command', '', true);
  raise;
end;
$$;

create function public.fail_website_repository_provisioning_v1(
  p_operation_id uuid,
  p_failure_code text,
  p_github_request_id text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_previous_state text;
  v_new_state text;
begin
  if p_operation_id is null
     or p_failure_code !~ '^[A-Z][A-Z0-9_]{0,127}$'
     or (p_github_request_id is not null
       and p_github_request_id !~ '^[A-Za-z0-9._:-]{1,255}$') then
    raise exception using errcode='22023',message='INVALID_WEBSITE_REPOSITORY_FAILURE';
  end if;
  v_operator := lws_internal.require_website_repository_owner_v1();
  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.operation_id=p_operation_id
  for update;

  if not found then
    raise exception using errcode='23503',message='WEBSITE_REPOSITORY_OPERATION_NOT_FOUND';
  end if;
  if v_operation.actor_id <> v_operator.operator_id then
    raise exception using errcode='42501',message='WEBSITE_REPOSITORY_OPERATION_DENIED';
  end if;
  if v_operation.state in ('BOUND','TERMINAL_FAILED') then
    return lws_internal.website_repository_operation_result_v1(v_operation, 'REPLAY');
  end if;

  v_previous_state := v_operation.state;
  v_new_state := case
    when p_failure_code in ('PROVIDER_UNAVAILABLE','RATE_LIMITED','EXTERNAL_OUTCOME_UNKNOWN')
      then 'RETRYABLE_FAILED'
    when p_failure_code in ('CONFIGURATION_BLOCKED','PROVIDER_UNAUTHORIZED','PROVIDER_FORBIDDEN')
      then 'BLOCKED'
    when p_failure_code in (
      'REPOSITORY_IDENTITY_MISMATCH','MARKER_MISMATCH',
      'STARTER_PROVENANCE_MISMATCH','CROSS_CONTEXT_BIND_DENIED'
    ) then 'QUARANTINED'
    else 'TERMINAL_FAILED'
  end;

  perform set_config('lws.website_repository_command', 'on', true);
  update public.website_repository_provisioning_operations
  set state=v_new_state,failure_code=p_failure_code,
      retry_at=case when v_new_state='RETRYABLE_FAILED'
        then clock_timestamp()+interval '5 minutes' else null end,
      updated_at=clock_timestamp()
  where operation_id=p_operation_id
  returning * into v_operation;

  update public.website_execution_workspaces
  set workspace_state='REPOSITORY_FAILED',updated_at=clock_timestamp()
  where website_workspace_id=v_operation.website_workspace_id;

  insert into public.website_repository_provisioning_events(
    operation_id,website_workspace_id,website_work_context_id,actor_id,
    request_fingerprint,event_type,previous_state,new_state,
    repository_provider,repository_owner,repository_name,
    repository_external_id,starter_source,starter_version,starter_commit_sha,
    attempt_number,result_code,github_request_id
  ) values (
    v_operation.operation_id,v_operation.website_workspace_id,
    v_operation.website_work_context_id,v_operator.operator_id,
    v_operation.request_fingerprint,'REPOSITORY_PROVISIONING_FAILED',
    v_previous_state,v_new_state,v_operation.repository_provider,
    v_operation.repository_owner,v_operation.repository_name,
    v_operation.repository_external_id,v_operation.starter_source,
    v_operation.starter_version,v_operation.starter_commit_sha,
    v_operation.attempt_count,p_failure_code,p_github_request_id
  );
  perform set_config('lws.website_repository_command', '', true);
  return lws_internal.website_repository_operation_result_v1(v_operation, v_new_state);
exception when others then
  perform set_config('lws.website_repository_command', '', true);
  raise;
end;
$$;

create function public.get_website_repository_operation_v1(
  p_operation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
begin
  if p_operation_id is null then
    raise exception using errcode='22023',message='WEBSITE_REPOSITORY_OPERATION_ID_REQUIRED';
  end if;
  v_operator := lws_internal.require_website_repository_owner_v1();
  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.operation_id=p_operation_id;
  if not found then
    raise exception using errcode='23503',message='WEBSITE_REPOSITORY_OPERATION_NOT_FOUND';
  end if;
  if v_operation.actor_id <> v_operator.operator_id then
    raise exception using errcode='42501',message='WEBSITE_REPOSITORY_OPERATION_DENIED';
  end if;
  return lws_internal.website_repository_operation_result_v1(v_operation, 'READ');
end;
$$;

revoke all on function
  lws_internal.require_website_repository_owner_v1(),
  lws_internal.website_repository_operation_result_v1(
    public.website_repository_provisioning_operations,text
  ),
  public.claim_website_repository_provisioning_v1(uuid,uuid,uuid,text,text,text),
  public.record_website_repository_external_identity_v1(uuid,text,text),
  public.bind_website_repository_v1(uuid,jsonb),
  public.fail_website_repository_provisioning_v1(uuid,text,text),
  public.get_website_repository_operation_v1(uuid)
from public,anon,authenticated,service_role;

grant execute on function
  public.claim_website_repository_provisioning_v1(uuid,uuid,uuid,text,text,text),
  public.record_website_repository_external_identity_v1(uuid,text,text),
  public.bind_website_repository_v1(uuid,jsonb),
  public.fail_website_repository_provisioning_v1(uuid,text,text),
  public.get_website_repository_operation_v1(uuid)
to authenticated;