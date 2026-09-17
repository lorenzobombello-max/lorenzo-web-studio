alter table public.website_execution_workspaces
  add column workspace_state text,
  add column provisioned_by uuid references public.commercial_operators(operator_id),
  add column provisioned_at timestamptz;

update public.website_execution_workspaces
set workspace_state = 'READY',
    provisioned_by = created_by,
    provisioned_at = created_at;

alter table public.website_execution_workspaces
  alter column workspace_state set not null,
  alter column workspace_state set default 'READY',
  alter column provisioned_by set not null,
  alter column provisioned_at set not null,
  alter column repository_owner drop not null,
  alter column repository_name drop not null,
  add constraint website_execution_workspace_state_valid
    check (workspace_state in ('PENDING_REPOSITORY', 'READY')),
  add constraint website_execution_workspace_repository_state_valid check (
    (workspace_state = 'PENDING_REPOSITORY'
      and repository_owner is null
      and repository_name is null
      and preview_branch is null
      and preview_url is null
      and last_commit_sha is null
      and last_commit_at is null
      and last_build_result is null
      and last_build_at is null)
    or
    (workspace_state = 'READY'
      and repository_owner is not null
      and repository_name is not null)
  );

create function lws_internal.guard_website_execution_workspace_provisioning_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op = 'INSERT' then
    new.provisioned_by := coalesce(new.provisioned_by, new.created_by);
    new.provisioned_at := coalesce(new.provisioned_at, new.created_at, clock_timestamp());
  elsif new.provisioned_by is distinct from old.provisioned_by
     or new.provisioned_at is distinct from old.provisioned_at then
    raise exception using
      errcode = '55000',
      message = 'WEBSITE_WORKSPACE_PROVENANCE_IMMUTABLE';
  end if;
  return new;
end;
$$;

create trigger trg_website_execution_workspace_provisioning_guard
before insert or update on public.website_execution_workspaces
for each row execute function
  lws_internal.guard_website_execution_workspace_provisioning_v1();

revoke all on function
  lws_internal.guard_website_execution_workspace_provisioning_v1()
from public, anon, authenticated, service_role;

revoke all on function lws_internal.assert_operator_aal2_v1()
from public, anon, authenticated, service_role;

create table public.website_execution_workspace_idempotency (
  operation_id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.commercial_operators(operator_id),
  quote_request_id uuid not null references public.quote_requests(id),
  command_type text not null
    check (command_type = 'PROVISION_WEBSITE_EXECUTION_WORKSPACE'),
  idempotency_key uuid not null,
  request_fingerprint character(64) not null
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  website_workspace_id uuid not null
    references public.website_execution_workspaces(website_workspace_id),
  result_payload jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint website_execution_workspace_idempotency_actor_key_unique
    unique (actor_id, command_type, idempotency_key)
);

create table public.website_execution_workspace_events (
  event_id uuid primary key default gen_random_uuid(),
  website_workspace_id uuid not null
    references public.website_execution_workspaces(website_workspace_id),
  website_work_context_id uuid not null
    references public.website_work_contexts(website_work_context_id),
  quote_request_id uuid not null references public.quote_requests(id),
  event_type text not null
    check (event_type in ('TECHNICAL_WORKSPACE_PROVISIONED', 'TECHNICAL_WORKSPACE_REUSED')),
  actor_id uuid not null references public.commercial_operators(operator_id),
  actor_role text not null check (actor_role = 'owner'),
  command_id uuid not null,
  mode text not null check (mode = 'PRE_PROJECT'),
  occurred_at timestamptz not null default clock_timestamp(),
  constraint website_execution_workspace_event_command_unique
    unique (actor_id, command_id)
);

alter table public.website_execution_workspace_idempotency enable row level security;
alter table public.website_execution_workspace_idempotency force row level security;
alter table public.website_execution_workspace_events enable row level security;
alter table public.website_execution_workspace_events force row level security;

revoke all privileges on table
  public.website_execution_workspace_idempotency,
  public.website_execution_workspace_events
from public, anon, authenticated, service_role;

create function public.provision_website_execution_workspace_v1(
  p_quote_request_id uuid,
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
  v_request public.quote_requests%rowtype;
  v_dossier_state text;
  v_work jsonb;
  v_context public.website_work_contexts%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_existing public.website_execution_workspace_idempotency%rowtype;
  v_fingerprint character(64);
  v_created boolean := false;
  v_result jsonb;
begin
  if p_quote_request_id is null or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'INVALID_WEBSITE_WORKSPACE_PROVISION_COMMAND';
  end if;
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select operator.* into v_operator
  from public.commercial_operators as operator
  where operator.auth_user_id = v_subject;

  if not found or v_operator.status <> 'ACTIVE' or v_operator.role <> 'owner' then
    raise exception using errcode = '42501', message = 'WEBSITE_WORKSPACE_OWNER_REQUIRED';
  end if;
  begin
    perform lws_internal.assert_operator_aal2_v1();
  exception
    when insufficient_privilege then
      if sqlerrm = 'MFA_OPERATOR_NOT_ELIGIBLE' then
        raise exception using errcode = '42501', message = 'AAL2_REQUIRED';
      end if;
      raise;
  end;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'authority_version', 'website_execution_workspace_provision_v1',
    'actor_id', v_operator.operator_id,
    'command_type', 'PROVISION_WEBSITE_EXECUTION_WORKSPACE',
    'quote_request_id', p_quote_request_id
  )::text, 'UTF8'), 'sha256'), 'hex')::character(64);

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'WEBSITE_EXECUTION_WORKSPACE_PROVISION:' || v_operator.operator_id::text
      || ':' || p_idempotency_key::text,
    0
  ));

  select ledger.* into v_existing
  from public.website_execution_workspace_idempotency as ledger
  where ledger.actor_id = v_operator.operator_id
    and ledger.command_type = 'PROVISION_WEBSITE_EXECUTION_WORKSPACE'
    and ledger.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed', true);
  end if;

  select request.* into v_request
  from public.quote_requests as request
  where request.id = p_quote_request_id
  for key share;

  select state.state into v_dossier_state
  from lws_internal.operator_dossier_states as state
  where state.quote_request_id = p_quote_request_id;

  if v_request.id is null
     or v_request.record_classification <> 'production'
     or v_request.request_kind <> 'website'
     or v_dossier_state is distinct from 'ACTIVE' then
    raise exception using errcode = 'P0001', message = 'WEBSITE_WORKSPACE_NOT_ELIGIBLE';
  end if;

  v_work := public.get_operator_website_work_v1(p_quote_request_id);
  if v_work->>'state' <> 'PRE_PROJECT'
     or v_work->>'mode' <> 'PRE_PROJECT'
     or nullif(v_work->>'project_id', '') is not null
     or (v_work->>'commercially_released')::boolean
     or not (v_work->'permitted_actions' ? 'OPEN_WEBSITE') then
    raise exception using errcode = 'P0001', message = 'WEBSITE_WORKSPACE_NOT_ELIGIBLE';
  end if;

  select context.* into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id = (v_work->>'website_work_context_id')::uuid
    and context.quote_request_id = p_quote_request_id
    and context.phase = 'PRE_PROJECT'
    and context.project_id is null
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;

  select workspace.* into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_work_context_id = v_context.website_work_context_id;

  if not found then
    insert into public.website_execution_workspaces(
      website_work_context_id, project_id, quote_request_id,
      workspace_state, repository_provider, repository_owner, repository_name,
      default_branch, preview_branch, created_by, provisioned_by, provisioned_at
    ) values (
      v_context.website_work_context_id, null, p_quote_request_id,
      'PENDING_REPOSITORY', 'GITHUB', null, null,
      'main', null, v_operator.operator_id, v_operator.operator_id, clock_timestamp()
    ) returning * into v_workspace;
    v_created := true;
  end if;

  v_result := jsonb_build_object(
    'website_workspace_id', v_workspace.website_workspace_id,
    'website_work_context_id', v_workspace.website_work_context_id,
    'quote_request_id', v_workspace.quote_request_id,
    'project_id', v_workspace.project_id,
    'mode', 'PRE_PROJECT',
    'workspace_state', v_workspace.workspace_state,
    'created', v_created
  );

  insert into public.website_execution_workspace_events(
    website_workspace_id, website_work_context_id, quote_request_id,
    event_type, actor_id, actor_role, command_id, mode
  ) values (
    v_workspace.website_workspace_id, v_context.website_work_context_id,
    p_quote_request_id,
    case when v_created then 'TECHNICAL_WORKSPACE_PROVISIONED'
      else 'TECHNICAL_WORKSPACE_REUSED' end,
    v_operator.operator_id, 'owner', p_idempotency_key, 'PRE_PROJECT'
  );

  insert into public.website_execution_workspace_idempotency(
    actor_id, quote_request_id, command_type, idempotency_key,
    request_fingerprint, website_workspace_id, result_payload
  ) values (
    v_operator.operator_id, p_quote_request_id,
    'PROVISION_WEBSITE_EXECUTION_WORKSPACE', p_idempotency_key,
    v_fingerprint, v_workspace.website_workspace_id, v_result
  );

  return v_result || jsonb_build_object('replayed', false);
end;
$$;

create or replace function public.get_website_execution_workspace_v2(
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_work jsonb;
  v_context public.website_work_contexts%rowtype;
  v_legacy jsonb;
  v_workspace public.website_execution_workspaces%rowtype;
  v_workspace_json jsonb;
begin
  if p_quote_request_id is null then
    raise exception using errcode = '22023', message = 'WEBSITE_WORKSPACE_LOCATOR_REQUIRED';
  end if;

  v_work := public.get_operator_website_work_v1(p_quote_request_id);
  if v_work->>'state' not in ('PRE_PROJECT', 'OFFICIAL_PROJECT')
     or not (v_work->'permitted_actions' ? 'OPEN_WEBSITE')
     or nullif(v_work->>'website_work_context_id', '') is null then
    raise exception using errcode = 'P0001', message = 'WEBSITE_WORKSPACE_NOT_ELIGIBLE';
  end if;

  select * into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id = (v_work->>'website_work_context_id')::uuid
    and context.quote_request_id = p_quote_request_id;

  if not found
     or v_context.phase is distinct from v_work->>'mode'
     or v_context.concept_id is distinct from nullif(v_work->>'concept_id', '')::uuid
     or v_context.project_id is distinct from nullif(v_work->>'project_id', '')::uuid then
    raise exception using errcode = 'P0001', message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;

  select workspace.* into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_work_context_id = v_context.website_work_context_id;

  if found then
    v_workspace_json := jsonb_build_object(
      'website_workspace_id', v_workspace.website_workspace_id,
      'website_work_context_id', v_workspace.website_work_context_id,
      'project_id', v_workspace.project_id,
      'quote_request_id', v_workspace.quote_request_id,
      'workspace_state', v_workspace.workspace_state,
      'repository_provider', v_workspace.repository_provider,
      'repository_owner', v_workspace.repository_owner,
      'repository_name', v_workspace.repository_name,
      'default_branch', v_workspace.default_branch,
      'preview_branch', v_workspace.preview_branch,
      'preview_url', v_workspace.preview_url,
      'last_commit_sha', v_workspace.last_commit_sha,
      'last_commit_at', v_workspace.last_commit_at,
      'last_build_result', v_workspace.last_build_result,
      'last_build_at', v_workspace.last_build_at,
      'binding_revision', v_workspace.binding_revision,
      'provisioned_by', v_workspace.provisioned_by,
      'provisioned_at', v_workspace.provisioned_at,
      'created_at', v_workspace.created_at,
      'updated_at', v_workspace.updated_at
    );
  end if;

  if v_context.phase = 'PRE_PROJECT' then
    return jsonb_build_object(
      'contract_version', 2,
      'mode', 'PRE_PROJECT',
      'quote_request_id', p_quote_request_id,
      'concept_id', v_context.concept_id,
      'project_id', null,
      'website_work_context_id', v_context.website_work_context_id,
      'context_revision', v_context.revision,
      'briefing_status', v_work->>'briefing_status',
      'commercially_released', false,
      'project', null,
      'start_gate', null,
      'workspace', v_workspace_json,
      'requirements', jsonb_build_object(
        'state', 'NOT_AVAILABLE',
        'message', 'Requirements volgen na intake-sync.'
      )
    );
  end if;

  v_legacy := public.get_website_execution_workspace_v1(
    p_quote_request_id,
    v_context.project_id
  );
  return v_legacy || jsonb_build_object(
    'contract_version', 2,
    'mode', 'OFFICIAL_PROJECT',
    'quote_request_id', p_quote_request_id,
    'concept_id', v_context.concept_id,
    'project_id', v_context.project_id,
    'website_work_context_id', v_context.website_work_context_id,
    'context_revision', v_context.revision,
    'briefing_status', v_work->>'briefing_status',
    'commercially_released', (v_work->>'commercially_released')::boolean,
    'workspace', v_workspace_json,
    'requirements', jsonb_build_object(
      'state', 'PROJECT_BOUND',
      'message', null
    )
  );
end;
$$;

revoke all on function public.provision_website_execution_workspace_v1(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.provision_website_execution_workspace_v1(uuid, uuid)
to authenticated;

comment on column public.website_execution_workspaces.workspace_state is
  'Server-owned repository provisioning lifecycle; PENDING_REPOSITORY has no external binding.';
comment on function public.provision_website_execution_workspace_v1(uuid, uuid) is
  'Owner-only AAL2 command that idempotently provisions one PRE_PROJECT technical workspace without external side effects.';