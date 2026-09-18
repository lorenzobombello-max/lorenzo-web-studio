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
  first_attempt_at timestamptz not null default statement_timestamp(),
  retry_window_expires_at timestamptz not null default (statement_timestamp() + interval '24 hours'),
  provider_retry_after_at timestamptz,
  retry_action text check (retry_action is null or retry_action in ('CREATE', 'RECONCILE')),
  quarantine_evidence jsonb,
  quarantine_evidence_sha256 character(64)
    check (quarantine_evidence_sha256 is null or quarantine_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  quarantined_at timestamptz,
  quarantine_reason text
    check (quarantine_reason is null or quarantine_reason ~ '^[A-Z][A-Z0-9_]{0,127}$'),
  quarantine_alert_due_at timestamptz,
  quarantine_alerted_at timestamptz,
  quarantine_resolution text
    check (quarantine_resolution is null or quarantine_resolution in ('VERIFY_AND_BIND', 'MARK_TERMINAL_FAILED')),
  quarantine_resolved_at timestamptz,
  quarantine_resolved_by_operator_id uuid references public.commercial_operators(operator_id),
  quarantine_resolution_evidence_sha256 character(64)
    check (quarantine_resolution_evidence_sha256 is null or quarantine_resolution_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  quarantine_resolution_idempotency_key uuid,
  resume_idempotency_key uuid,
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
    'RETRY_SCHEDULED',
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
    or (state in ('EXTERNAL_CREATED', 'VERIFYING', 'BOUND')
      and repository_external_id is not null)
    or state in ('RETRYABLE_FAILED', 'RETRY_SCHEDULED', 'BLOCKED', 'QUARANTINED', 'TERMINAL_FAILED')
  ),
  constraint website_repository_operation_failure_shape check (
    (state in ('RETRYABLE_FAILED', 'RETRY_SCHEDULED', 'BLOCKED', 'QUARANTINED', 'TERMINAL_FAILED')
      and failure_code is not null)
    or
    (state not in ('RETRYABLE_FAILED', 'RETRY_SCHEDULED', 'BLOCKED', 'QUARANTINED', 'TERMINAL_FAILED')
      and failure_code is null)
  ),
  constraint website_repository_operation_retry_shape check (
    (state in ('RETRYABLE_FAILED', 'RETRY_SCHEDULED') and retry_at is not null and retry_action is not null)
    or (state = 'CREATING' and retry_at is null and retry_action = 'RECONCILE')
    or (state not in ('RETRYABLE_FAILED', 'RETRY_SCHEDULED')
      and retry_at is null and retry_action is null)
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
  ),
  constraint website_repository_operation_retry_window_shape check (
    retry_window_expires_at = first_attempt_at + interval '24 hours'
    and retry_window_expires_at > first_attempt_at
    and (provider_retry_after_at is null or provider_retry_after_at <= retry_window_expires_at)
  ),
  constraint website_repository_operation_quarantine_shape check (
    (quarantined_at is null and quarantine_evidence is null
      and quarantine_evidence_sha256 is null and quarantine_reason is null
      and quarantine_alert_due_at is null and quarantine_alerted_at is null)
    or
    (quarantined_at is not null and jsonb_typeof(quarantine_evidence) = 'object'
      and quarantine_evidence_sha256 is not null and quarantine_reason is not null
      and quarantine_alert_due_at = quarantined_at + interval '24 hours'
      and (quarantine_alerted_at is null or quarantine_alerted_at >= quarantine_alert_due_at))
  ),
  constraint website_repository_operation_resolution_shape check (
    (quarantine_resolution is null and quarantine_resolved_at is null
      and quarantine_resolved_by_operator_id is null
      and quarantine_resolution_evidence_sha256 is null
      and quarantine_resolution_idempotency_key is null)
    or
    (quarantine_resolution is not null and quarantine_resolved_at is not null
      and quarantine_resolved_by_operator_id is not null
      and quarantine_resolution_evidence_sha256 is not null
      and quarantine_resolution_idempotency_key is not null)
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

create function lws_internal.website_repository_transition_allowed_v1(
  p_old_state text,p_new_state text
)
returns boolean
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select p_old_state=p_new_state or (p_old_state,p_new_state) in (
    ('CLAIMED','CREATING'),
    ('CREATING','EXTERNAL_CREATED'),('CREATING','RETRYABLE_FAILED'),
    ('CREATING','RETRY_SCHEDULED'),('CREATING','BLOCKED'),
    ('CREATING','QUARANTINED'),('CREATING','TERMINAL_FAILED'),
    ('EXTERNAL_CREATED','VERIFYING'),
    ('VERIFYING','BOUND'),('VERIFYING','RETRYABLE_FAILED'),
    ('VERIFYING','RETRY_SCHEDULED'),('VERIFYING','BLOCKED'),
    ('VERIFYING','QUARANTINED'),('VERIFYING','TERMINAL_FAILED'),
    ('RETRYABLE_FAILED','RETRY_SCHEDULED'),('RETRYABLE_FAILED','CREATING'),
    ('RETRYABLE_FAILED','VERIFYING'),
    ('RETRY_SCHEDULED','CREATING'),('RETRY_SCHEDULED','VERIFYING'),
    ('BLOCKED','CREATING'),('BLOCKED','VERIFYING'),
    ('QUARANTINED','VERIFYING'),('QUARANTINED','TERMINAL_FAILED')
  )
$$;

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
      'RETRYABLE_FAILED', 'RETRY_SCHEDULED', 'BLOCKED', 'QUARANTINED', 'TERMINAL_FAILED'
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
      'RETRYABLE_FAILED', 'RETRY_SCHEDULED', 'BLOCKED', 'QUARANTINED', 'TERMINAL_FAILED'
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

  if tg_op = 'UPDATE' and not lws_internal.website_repository_transition_allowed_v1(
    old.state,new.state
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_REPOSITORY_TRANSITION_INVALID';
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

  if tg_op = 'UPDATE' and (
    new.first_attempt_at is distinct from old.first_attempt_at
    or new.retry_window_expires_at is distinct from old.retry_window_expires_at
  ) then
    raise exception using
      errcode = '55000',
      message = 'WEBSITE_REPOSITORY_RETRY_WINDOW_IMMUTABLE';
  end if;

  if tg_op = 'UPDATE' and old.quarantine_evidence is not null and (
    new.quarantine_evidence is distinct from old.quarantine_evidence
    or new.quarantine_evidence_sha256 is distinct from old.quarantine_evidence_sha256
    or new.quarantined_at is distinct from old.quarantined_at
    or new.quarantine_reason is distinct from old.quarantine_reason
    or new.quarantine_alert_due_at is distinct from old.quarantine_alert_due_at
  ) then
    raise exception using
      errcode = '55000',
      message = 'WEBSITE_REPOSITORY_QUARANTINE_EVIDENCE_IMMUTABLE';
  end if;

  if tg_op = 'UPDATE' and old.quarantine_resolution is not null and (
    new.quarantine_resolution is distinct from old.quarantine_resolution
    or new.quarantine_resolved_at is distinct from old.quarantine_resolved_at
    or new.quarantine_resolved_by_operator_id is distinct from old.quarantine_resolved_by_operator_id
    or new.quarantine_resolution_evidence_sha256 is distinct from old.quarantine_resolution_evidence_sha256
    or new.quarantine_resolution_idempotency_key is distinct from old.quarantine_resolution_idempotency_key
  ) then
    raise exception using
      errcode = '55000',
      message = 'WEBSITE_REPOSITORY_QUARANTINE_RESOLUTION_IMMUTABLE';
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
    'first_attempt_at', p_operation.first_attempt_at,
    'retry_window_expires_at', p_operation.retry_window_expires_at,
    'provider_retry_after_at', p_operation.provider_retry_after_at,
    'retry_action', p_operation.retry_action,
    'quarantine_evidence_sha256', p_operation.quarantine_evidence_sha256,
    'quarantined_at', p_operation.quarantined_at,
    'quarantine_reason', p_operation.quarantine_reason,
    'quarantine_alert_due_at', p_operation.quarantine_alert_due_at,
    'quarantine_alerted_at', p_operation.quarantine_alerted_at,
    'quarantine_resolution', p_operation.quarantine_resolution,
    'quarantine_resolved_at', p_operation.quarantine_resolved_at,
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
  v_now timestamptz;
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
  v_now := clock_timestamp();
  insert into public.website_repository_provisioning_operations(
    website_workspace_id,website_work_context_id,actor_id,idempotency_key,
    request_fingerprint,repository_provider,repository_owner,repository_name,
    starter_source,starter_version,starter_commit_sha,state,attempt_count,
    first_attempt_at,retry_window_expires_at
  ) values (
    p_website_workspace_id,p_website_work_context_id,v_operator.operator_id,
    p_idempotency_key,v_fingerprint,'GITHUB',v_repository_owner,
    v_repository_name,p_starter_source,p_starter_version,p_starter_commit_sha,
    'CLAIMED',1,v_now,v_now + interval '24 hours'
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
    p_starter_source,p_starter_version,p_starter_commit_sha,1,'CLAIMED'
  );
  update public.website_repository_provisioning_operations
  set state='CREATING',updated_at=clock_timestamp()
  where operation_id=v_operation.operation_id
  returning * into v_operation;
  insert into public.website_repository_provisioning_events(
    operation_id,website_workspace_id,website_work_context_id,actor_id,
    request_fingerprint,event_type,previous_state,new_state,
    repository_provider,repository_owner,repository_name,starter_source,
    starter_version,starter_commit_sha,attempt_number,result_code
  ) values (
    v_operation.operation_id,p_website_workspace_id,p_website_work_context_id,
    v_operator.operator_id,v_fingerprint,'REPOSITORY_CREATION_STARTED',
    'CLAIMED','CREATING','GITHUB',v_repository_owner,v_repository_name,
    p_starter_source,p_starter_version,p_starter_commit_sha,1,'CREATING'
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
  if v_operation.state <> 'CREATING' then
    raise exception using errcode = 'P0001', message = 'WEBSITE_REPOSITORY_TRANSITION_INVALID';
  end if;

  perform set_config('lws.website_repository_command', 'on', true);
  update public.website_repository_provisioning_operations
  set state='EXTERNAL_CREATED',repository_external_id=v_external_id,
      repository_node_id=p_repository_node_id,
      retry_action=null,
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
    'CREATING','EXTERNAL_CREATED',v_operation.repository_provider,
    v_operation.repository_owner,v_operation.repository_name,
    v_operation.repository_external_id,v_operation.starter_source,
    v_operation.starter_version,v_operation.starter_commit_sha,
    v_operation.attempt_count,'EXTERNAL_CREATED'
  );
  update public.website_repository_provisioning_operations
  set state='VERIFYING',updated_at=clock_timestamp()
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
    v_operation.request_fingerprint,'REPOSITORY_VERIFICATION_STARTED',
    'EXTERNAL_CREATED','VERIFYING',v_operation.repository_provider,
    v_operation.repository_owner,v_operation.repository_name,
    v_operation.repository_external_id,v_operation.starter_source,
    v_operation.starter_version,v_operation.starter_commit_sha,
    v_operation.attempt_count,'VERIFYING'
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
  v_previous_state text;
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
  if v_operation.state <> 'VERIFYING' then
    raise exception using errcode='P0001',message='WEBSITE_REPOSITORY_TRANSITION_INVALID';
  end if;

  perform set_config('lws.website_repository_command', 'on', true);
  v_previous_state := v_operation.state;
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
    v_operation.request_fingerprint,'REPOSITORY_BOUND',v_previous_state,'BOUND',
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
  p_github_request_id text,
  p_provider_retry_at text
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
  v_now timestamptz := clock_timestamp();
  v_provider_retry_at timestamptz;
  v_base_seconds numeric;
  v_jitter_basis_points integer;
  v_scheduled_retry_at timestamptz;
  v_evidence jsonb;
  v_evidence_sha character(64);
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
  if v_operation.state not in ('CREATING','VERIFYING') then
    raise exception using errcode='P0001',message='WEBSITE_REPOSITORY_TRANSITION_INVALID';
  end if;

  if p_provider_retry_at is not null then
    begin
      v_provider_retry_at := p_provider_retry_at::timestamptz;
      if v_provider_retry_at <= v_now then
        v_provider_retry_at := null;
      end if;
    exception when others then
      v_provider_retry_at := null;
    end;
  end if;

  v_previous_state := v_operation.state;
  v_new_state := case
    when p_failure_code in ('PROVIDER_UNAVAILABLE','RATE_LIMITED','EXTERNAL_OUTCOME_UNKNOWN')
      and v_operation.attempt_count < 5
      and v_now < v_operation.retry_window_expires_at then 'RETRY_SCHEDULED'
    when v_operation.quarantine_evidence is not null
      and p_failure_code in (
        'EXTERNAL_OUTCOME_UNKNOWN','REPOSITORY_IDENTITY_MISMATCH','MARKER_MISMATCH',
        'STARTER_PROVENANCE_MISMATCH','CROSS_CONTEXT_BIND_DENIED'
      ) then 'TERMINAL_FAILED'
    when p_failure_code = 'EXTERNAL_OUTCOME_UNKNOWN' then 'QUARANTINED'
    when p_failure_code in ('CONFIGURATION_BLOCKED','PROVIDER_UNAUTHORIZED','PROVIDER_FORBIDDEN')
      then 'BLOCKED'
    when p_failure_code in (
      'REPOSITORY_IDENTITY_MISMATCH','MARKER_MISMATCH',
      'STARTER_PROVENANCE_MISMATCH','CROSS_CONTEXT_BIND_DENIED'
    ) then 'QUARANTINED'
    else 'TERMINAL_FAILED'
  end;

  if v_new_state='RETRY_SCHEDULED' then
    v_base_seconds := least(480::numeric,30::numeric*power(2::numeric,v_operation.attempt_count-1));
    v_jitter_basis_points := (
      ('x'||substr(encode(extensions.digest(
        convert_to(v_operation.operation_id::text||':'||(v_operation.attempt_count+1)::text,'UTF8'),
        'sha256'
      ),'hex'),1,8))::bit(32)::bigint % 4001
    )::integer - 2000;
    v_scheduled_retry_at := v_now + make_interval(secs => (
      v_base_seconds*(1+v_jitter_basis_points::numeric/10000)
    )::double precision);
    if v_provider_retry_at is not null then
      v_provider_retry_at := least(
        greatest(v_provider_retry_at,v_operation.claimed_at),
        v_operation.retry_window_expires_at
      );
      v_scheduled_retry_at := v_provider_retry_at;
    else
      v_scheduled_retry_at := least(
        greatest(v_scheduled_retry_at,v_operation.claimed_at),
        v_operation.retry_window_expires_at
      );
    end if;
  end if;

  if v_new_state='QUARANTINED' then
    v_evidence := jsonb_build_object(
      'schema_version',1,
      'operation_id',v_operation.operation_id,
      'website_work_context_id',v_operation.website_work_context_id,
      'workspace_id',v_operation.website_workspace_id,
      'environment',case when v_operation.repository_owner='lorenzo-web-solutions-lab' then 'TEST' else 'PRODUCTION' end,
      'repository_owner',v_operation.repository_owner,
      'repository_name',v_operation.repository_name,
      'repository_external_id',v_operation.repository_external_id,
      'repository_node_id',v_operation.repository_node_id,
      'repository_visibility',null,
      'repository_created_at',null,
      'github_app_actor',null,
      'starter_source',v_operation.starter_source,
      'starter_version',v_operation.starter_version,
      'starter_commit_sha',v_operation.starter_commit_sha,
      'starter_tree_hash',null,
      'marker_status',p_failure_code,
      'marker_context_id',null,
      'marker_operation_id',null,
      'original_operation_fingerprint',v_operation.request_fingerprint,
      'conflicting_binding_identity',null,
      'captured_at',v_now
    );
    v_evidence_sha := encode(extensions.digest(convert_to(v_evidence::text,'UTF8'),'sha256'),'hex')::character(64);
  end if;

  perform set_config('lws.website_repository_command', 'on', true);
  update public.website_repository_provisioning_operations
  set state=v_new_state,failure_code=p_failure_code,retry_at=v_scheduled_retry_at,
      provider_retry_after_at=case when v_new_state='RETRY_SCHEDULED' then v_provider_retry_at else null end,
      retry_action=case when v_new_state='RETRY_SCHEDULED' and (repository_external_id is not null or p_failure_code='EXTERNAL_OUTCOME_UNKNOWN') then 'RECONCILE'
        when v_new_state='RETRY_SCHEDULED' then 'CREATE' else null end,
      quarantine_evidence=case when v_new_state='QUARANTINED' then v_evidence else quarantine_evidence end,
      quarantine_evidence_sha256=case when v_new_state='QUARANTINED' then v_evidence_sha else quarantine_evidence_sha256 end,
      quarantined_at=case when v_new_state='QUARANTINED' then v_now else quarantined_at end,
      quarantine_reason=case when v_new_state='QUARANTINED' then p_failure_code else quarantine_reason end,
      quarantine_alert_due_at=case when v_new_state='QUARANTINED' then v_now+interval '24 hours' else quarantine_alert_due_at end,
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

create function public.fail_website_repository_provisioning_v1(
  p_operation_id uuid,p_failure_code text,p_github_request_id text
)
returns jsonb
language sql
volatile
security definer
set search_path = public, pg_catalog
as $$
  select public.fail_website_repository_provisioning_v1(
    p_operation_id,p_failure_code,p_github_request_id,null::text
  )
$$;

create function public.resume_website_repository_provisioning_v1(
  p_operation_id uuid,p_idempotency_key uuid
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
  v_state text;
  v_previous_state text;
  v_retry_action text;
begin
  if p_operation_id is null or p_idempotency_key is null then
    raise exception using errcode='22023',message='INVALID_WEBSITE_REPOSITORY_RESUME';
  end if;
  v_operator := lws_internal.require_website_repository_owner_v1();
  select operation.* into v_operation from public.website_repository_provisioning_operations operation
  where operation.operation_id=p_operation_id for update;
  if not found then raise exception using errcode='23503',message='WEBSITE_REPOSITORY_OPERATION_NOT_FOUND'; end if;
  if v_operation.actor_id<>v_operator.operator_id then raise exception using errcode='42501',message='WEBSITE_REPOSITORY_OPERATION_DENIED'; end if;
  if v_operation.resume_idempotency_key=p_idempotency_key then
    return lws_internal.website_repository_operation_result_v1(v_operation,'REPLAY');
  end if;
  if v_operation.state not in ('RETRY_SCHEDULED','BLOCKED') then raise exception using errcode='P0001',message='WEBSITE_REPOSITORY_TRANSITION_INVALID'; end if;
  if clock_timestamp()>=v_operation.retry_window_expires_at then raise exception using errcode='P0001',message='WEBSITE_REPOSITORY_RETRY_WINDOW_EXPIRED'; end if;
  if v_operation.state='RETRY_SCHEDULED' and clock_timestamp()<v_operation.retry_at then raise exception using errcode='P0001',message='WEBSITE_REPOSITORY_RETRY_NOT_DUE'; end if;
  if v_operation.attempt_count>=5 then raise exception using errcode='P0001',message='WEBSITE_REPOSITORY_ATTEMPTS_EXHAUSTED'; end if;
  v_previous_state:=v_operation.state;
  v_retry_action:=v_operation.retry_action;
  v_state:=case when v_operation.repository_external_id is null then 'CREATING' else 'VERIFYING' end;
  perform set_config('lws.website_repository_command','on',true);
  update public.website_repository_provisioning_operations set state=v_state,
    attempt_count=attempt_count+1,failure_code=null,retry_at=null,
    provider_retry_after_at=null,
    retry_action=case
      when v_state='CREATING' and v_retry_action='RECONCILE' then 'RECONCILE'
      else null
    end,
    resume_idempotency_key=p_idempotency_key,
    updated_at=clock_timestamp() where operation_id=p_operation_id returning * into v_operation;
  insert into public.website_repository_provisioning_events(
    operation_id,website_workspace_id,website_work_context_id,actor_id,
    request_fingerprint,event_type,previous_state,new_state,
    repository_provider,repository_owner,repository_name,
    repository_external_id,starter_source,starter_version,starter_commit_sha,
    attempt_number,result_code
  ) values (
    v_operation.operation_id,v_operation.website_workspace_id,
    v_operation.website_work_context_id,v_operator.operator_id,
    v_operation.request_fingerprint,'REPOSITORY_PROVISIONING_RESUMED',
    v_previous_state,v_state,v_operation.repository_provider,
    v_operation.repository_owner,v_operation.repository_name,
    v_operation.repository_external_id,v_operation.starter_source,
    v_operation.starter_version,v_operation.starter_commit_sha,
    v_operation.attempt_count,
    case when v_retry_action='RECONCILE' then 'RESUMED_RECONCILE' else 'RESUMED_CREATE' end
  );
  perform set_config('lws.website_repository_command','',true);
  return lws_internal.website_repository_operation_result_v1(v_operation,v_state);
exception when others then perform set_config('lws.website_repository_command','',true); raise;
end;
$$;

create function public.resolve_website_repository_quarantine_v1(
  p_operation_id uuid,p_idempotency_key uuid,p_decision text,p_evidence_sha256 text
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
  v_state text;
begin
  if p_operation_id is null or p_idempotency_key is null
    or p_decision not in ('VERIFY_AND_BIND','MARK_TERMINAL_FAILED')
    or p_evidence_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='22023',message='INVALID_WEBSITE_REPOSITORY_QUARANTINE_RESOLUTION';
  end if;
  v_operator:=lws_internal.require_website_repository_owner_v1();
  select operation.* into v_operation from public.website_repository_provisioning_operations operation
  where operation.operation_id=p_operation_id for update;
  if not found then raise exception using errcode='23503',message='WEBSITE_REPOSITORY_OPERATION_NOT_FOUND'; end if;
  if v_operation.actor_id<>v_operator.operator_id then raise exception using errcode='42501',message='WEBSITE_REPOSITORY_OPERATION_DENIED'; end if;
  if v_operation.quarantine_resolution_idempotency_key=p_idempotency_key then
    if v_operation.quarantine_resolution<>p_decision or v_operation.quarantine_resolution_evidence_sha256<>p_evidence_sha256 then
      raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';
    end if;
    return lws_internal.website_repository_operation_result_v1(v_operation,'REPLAY');
  end if;
  if v_operation.state<>'QUARANTINED' then raise exception using errcode='P0001',message='WEBSITE_REPOSITORY_TRANSITION_INVALID'; end if;
  if v_operation.quarantine_evidence_sha256<>p_evidence_sha256 then raise exception using errcode='42501',message='STALE_QUARANTINE_EVIDENCE'; end if;
  v_state:=case when p_decision='VERIFY_AND_BIND' then 'VERIFYING' else 'TERMINAL_FAILED' end;
  perform set_config('lws.website_repository_command','on',true);
  update public.website_repository_provisioning_operations set state=v_state,
    failure_code=case when v_state='TERMINAL_FAILED' then failure_code else null end,
    quarantine_resolution=p_decision,quarantine_resolved_at=clock_timestamp(),
    quarantine_resolved_by_operator_id=v_operator.operator_id,
    quarantine_resolution_evidence_sha256=p_evidence_sha256,
    quarantine_resolution_idempotency_key=p_idempotency_key,updated_at=clock_timestamp()
  where operation_id=p_operation_id returning * into v_operation;
  insert into public.website_repository_provisioning_events(
    operation_id,website_workspace_id,website_work_context_id,actor_id,
    request_fingerprint,event_type,previous_state,new_state,
    repository_provider,repository_owner,repository_name,
    repository_external_id,starter_source,starter_version,starter_commit_sha,
    attempt_number,result_code
  ) values (
    v_operation.operation_id,v_operation.website_workspace_id,
    v_operation.website_work_context_id,v_operator.operator_id,
    v_operation.request_fingerprint,'REPOSITORY_QUARANTINE_RESOLVED',
    'QUARANTINED',v_state,v_operation.repository_provider,
    v_operation.repository_owner,v_operation.repository_name,
    v_operation.repository_external_id,v_operation.starter_source,
    v_operation.starter_version,v_operation.starter_commit_sha,
    v_operation.attempt_count,p_decision
  );
  perform set_config('lws.website_repository_command','',true);
  return lws_internal.website_repository_operation_result_v1(v_operation,v_state);
exception when others then perform set_config('lws.website_repository_command','',true); raise;
end;
$$;

create function public.mark_website_repository_quarantine_alerted_v1(
  p_operation_id uuid,p_evidence_sha256 text
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
begin
  if p_operation_id is null or p_evidence_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='22023',message='INVALID_WEBSITE_REPOSITORY_QUARANTINE_ALERT';
  end if;
  v_operator:=lws_internal.require_website_repository_owner_v1();
  select operation.* into v_operation from public.website_repository_provisioning_operations operation
  where operation.operation_id=p_operation_id for update;
  if not found then raise exception using errcode='23503',message='WEBSITE_REPOSITORY_OPERATION_NOT_FOUND'; end if;
  if v_operation.actor_id<>v_operator.operator_id then raise exception using errcode='42501',message='WEBSITE_REPOSITORY_OPERATION_DENIED'; end if;
  if v_operation.state<>'QUARANTINED' then raise exception using errcode='P0001',message='WEBSITE_REPOSITORY_TRANSITION_INVALID'; end if;
  if v_operation.quarantine_evidence_sha256<>p_evidence_sha256 then raise exception using errcode='42501',message='STALE_QUARANTINE_EVIDENCE'; end if;
  if v_operation.quarantine_alerted_at is not null then
    return lws_internal.website_repository_operation_result_v1(v_operation,'REPLAY');
  end if;
  if clock_timestamp()<v_operation.quarantine_alert_due_at then
    raise exception using errcode='P0001',message='WEBSITE_REPOSITORY_QUARANTINE_ALERT_NOT_DUE';
  end if;
  perform set_config('lws.website_repository_command','on',true);
  update public.website_repository_provisioning_operations
  set quarantine_alerted_at=clock_timestamp(),updated_at=clock_timestamp()
  where operation_id=p_operation_id returning * into v_operation;
  insert into public.website_repository_provisioning_events(
    operation_id,website_workspace_id,website_work_context_id,actor_id,
    request_fingerprint,event_type,previous_state,new_state,
    repository_provider,repository_owner,repository_name,
    repository_external_id,starter_source,starter_version,starter_commit_sha,
    attempt_number,result_code
  ) values (
    v_operation.operation_id,v_operation.website_workspace_id,
    v_operation.website_work_context_id,v_operator.operator_id,
    v_operation.request_fingerprint,'REPOSITORY_QUARANTINE_ALERTED',
    'QUARANTINED','QUARANTINED',v_operation.repository_provider,
    v_operation.repository_owner,v_operation.repository_name,
    v_operation.repository_external_id,v_operation.starter_source,
    v_operation.starter_version,v_operation.starter_commit_sha,
    v_operation.attempt_count,'QUARANTINE_ALERTED'
  );
  perform set_config('lws.website_repository_command','',true);
  return lws_internal.website_repository_operation_result_v1(v_operation,'QUARANTINE_ALERTED');
exception when others then perform set_config('lws.website_repository_command','',true); raise;
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
  lws_internal.website_repository_transition_allowed_v1(text,text),
  lws_internal.website_repository_operation_result_v1(
    public.website_repository_provisioning_operations,text
  ),
  public.claim_website_repository_provisioning_v1(uuid,uuid,uuid,text,text,text),
  public.record_website_repository_external_identity_v1(uuid,text,text),
  public.bind_website_repository_v1(uuid,jsonb),
  public.fail_website_repository_provisioning_v1(uuid,text,text),
  public.fail_website_repository_provisioning_v1(uuid,text,text,text),
  public.resume_website_repository_provisioning_v1(uuid,uuid),
  public.resolve_website_repository_quarantine_v1(uuid,uuid,text,text),
  public.mark_website_repository_quarantine_alerted_v1(uuid,text),
  public.get_website_repository_operation_v1(uuid)
from public,anon,authenticated,service_role;

grant execute on function
  public.claim_website_repository_provisioning_v1(uuid,uuid,uuid,text,text,text),
  public.record_website_repository_external_identity_v1(uuid,text,text),
  public.bind_website_repository_v1(uuid,jsonb),
  public.fail_website_repository_provisioning_v1(uuid,text,text),
  public.fail_website_repository_provisioning_v1(uuid,text,text,text),
  public.resume_website_repository_provisioning_v1(uuid,uuid),
  public.resolve_website_repository_quarantine_v1(uuid,uuid,text,text),
  public.mark_website_repository_quarantine_alerted_v1(uuid,text),
  public.get_website_repository_operation_v1(uuid)
to authenticated;