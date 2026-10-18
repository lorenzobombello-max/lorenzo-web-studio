create or replace function public.create_website_project_preview_session_v1(
  p_preview_build_id uuid,
  p_session_token_hash text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $function$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_candidate lws_internal.website_project_preview_builds%rowtype;
  v_work jsonb;
  v_context public.website_work_contexts%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_canonical_operation_id uuid;
  v_source_lease_id uuid;
  v_source_lease lws_internal.website_project_files_write_leases%rowtype;
  v_preview_lease lws_internal.website_project_preview_build_leases%rowtype;
  v_build lws_internal.website_project_preview_builds%rowtype;
  v_artifact_id uuid;
  v_session lws_internal.website_project_preview_sessions%rowtype;
begin
  if v_subject is null
     or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select operator.* into v_operator
  from public.commercial_operators as operator
  where operator.auth_user_id = v_subject
  for update;
  if not found
     or v_operator.status <> 'ACTIVE'
     or v_operator.role <> 'owner'
     or v_operator.revoked_at is not null then
    raise exception using
      errcode = '42501', message = 'WEBSITE_REPOSITORY_OWNER_REQUIRED';
  end if;
  perform lws_internal.assert_operator_aal2_v1();

  select build.* into v_candidate
  from lws_internal.website_project_preview_builds as build
  where build.preview_build_id = p_preview_build_id
    and build.actor_auth_user_id = v_subject
    and build.build_status in ('PASS', 'PASS_WITH_WARNINGS');
  if not found then
    raise exception using
      errcode = '42501', message = 'PROJECT_PREVIEW_BUILD_NOT_READY';
  end if;
  if p_session_token_hash is null
     or p_session_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using
      errcode = '22023', message = 'PROJECT_PREVIEW_SESSION_TOKEN_INVALID';
  end if;

  begin
    v_work := public.get_operator_website_work_v1(v_candidate.quote_request_id);
  exception
    when sqlstate 'P0001' then
      raise exception using
        errcode = '42501', message = 'PROJECT_PREVIEW_BUILD_NOT_READY';
  end;
  if v_work->>'state' not in ('PRE_PROJECT', 'OFFICIAL_PROJECT')
     or not (v_work->'permitted_actions' ? 'OPEN_WEBSITE')
     or nullif(v_work->>'website_work_context_id', '') is null then
    raise exception using
      errcode = '42501', message = 'PROJECT_PREVIEW_BUILD_NOT_READY';
  end if;

  select context.* into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id =
        (v_work->>'website_work_context_id')::uuid
    and context.quote_request_id = v_candidate.quote_request_id
  for update;
  if not found
     or v_context.phase is distinct from v_work->>'mode'
     or v_context.concept_id is distinct from
        nullif(v_work->>'concept_id', '')::uuid
     or v_context.project_id is distinct from
        nullif(v_work->>'project_id', '')::uuid then
    raise exception using
      errcode = '42501', message = 'PROJECT_PREVIEW_BUILD_NOT_READY';
  end if;

  select workspace.* into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_work_context_id = v_context.website_work_context_id
    and workspace.quote_request_id = v_candidate.quote_request_id
    and workspace.project_id is not distinct from v_context.project_id
  for update;
  if not found
     or v_workspace.workspace_state <> 'REPOSITORY_READY'
     or v_workspace.repository_provider <> 'GITHUB'
     or v_workspace.repository_owner is null
     or v_workspace.repository_name is null
     or v_workspace.repository_external_id is null
     or v_workspace.repository_node_id is null
     or v_workspace.repository_visibility <> 'private'
     or v_workspace.repository_state <> 'BOUND'
     or v_workspace.repository_marker_commit_sha is null
     or v_workspace.repository_bound_at is null
     or v_workspace.default_branch is null
     or v_workspace.last_commit_sha is null
     or v_workspace.binding_revision < 1 then
    raise exception using
      errcode = '42501', message = 'PROJECT_PREVIEW_BUILD_NOT_READY';
  end if;

  begin
    v_canonical_operation_id :=
      lws_internal.get_website_repository_canonical_durable_operation_id_v1(
        v_workspace.website_workspace_id,
        v_context.website_work_context_id
      );
  exception
    when sqlstate 'P0001' then
      raise exception using
        errcode = '42501', message = 'PROJECT_PREVIEW_BUILD_NOT_READY';
  end;

  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.operation_id = v_canonical_operation_id
  for update;
  if not found
     or v_operation.state <> 'BOUND'
     or v_operation.website_workspace_id <> v_workspace.website_workspace_id
     or v_operation.website_work_context_id <> v_context.website_work_context_id
     or v_operation.repository_provider is distinct from
        v_workspace.repository_provider
     or v_operation.repository_owner is distinct from
        v_workspace.repository_owner
     or v_operation.repository_name is distinct from
        v_workspace.repository_name
     or v_operation.repository_external_id is distinct from
        v_workspace.repository_external_id
     or v_operation.repository_node_id is distinct from
        v_workspace.repository_node_id then
    raise exception using
      errcode = '42501', message = 'PROJECT_PREVIEW_BUILD_NOT_READY';
  end if;

  select preview_lease.* into v_preview_lease
  from lws_internal.website_project_preview_build_leases as preview_lease
  where preview_lease.preview_lease_id = v_candidate.lease_id
  for update;
  if not found then
    raise exception using
      errcode = '42501', message = 'PROJECT_PREVIEW_BUILD_NOT_READY';
  end if;

  v_source_lease_id := v_preview_lease.source_write_lease_id;

  select source_lease.* into v_source_lease
  from lws_internal.website_project_files_write_leases as source_lease
  where source_lease.lease_id = v_source_lease_id
  for update;
  if not found then
    raise exception using
      errcode = '42501', message = 'PROJECT_PREVIEW_BUILD_NOT_READY';
  end if;

  if v_preview_lease.source_write_lease_id <> v_source_lease.lease_id then
    raise exception using
      errcode = '42501', message = 'PROJECT_PREVIEW_BUILD_NOT_READY';
  end if;

  select build.* into v_build
  from lws_internal.website_project_preview_builds as build
  where build.preview_build_id = p_preview_build_id
    and build.lease_id = v_preview_lease.preview_lease_id
  for update;
  if not found
     or v_build.actor_auth_user_id <> v_subject
     or v_build.build_status not in ('PASS', 'PASS_WITH_WARNINGS')
     or v_build.quote_request_id <> v_candidate.quote_request_id
     or v_build.quote_request_id <> v_context.quote_request_id
     or v_build.website_work_context_id <> v_context.website_work_context_id
     or v_build.website_workspace_id <> v_workspace.website_workspace_id
     or v_build.commit_sha <> v_workspace.last_commit_sha
     or v_preview_lease.actor_auth_user_id <> v_subject
     or v_preview_lease.quote_request_id <> v_build.quote_request_id
     or v_preview_lease.website_work_context_id <>
        v_build.website_work_context_id
     or v_preview_lease.website_workspace_id <> v_build.website_workspace_id
     or v_preview_lease.expected_commit_sha <> v_build.commit_sha
     or v_source_lease.actor_auth_user_id <> v_subject
     or v_source_lease.actor_operator_id <> v_operator.operator_id
     or v_source_lease.quote_request_id <> v_build.quote_request_id
     or v_source_lease.website_work_context_id <>
        v_build.website_work_context_id
     or v_source_lease.website_workspace_id <> v_build.website_workspace_id
     or v_source_lease.expected_commit_sha <> v_build.commit_sha
     or v_source_lease.binding_revision <> v_workspace.binding_revision
     or v_source_lease.repository_provider <>
        v_workspace.repository_provider
     or v_source_lease.repository_owner <> v_workspace.repository_owner
     or v_source_lease.repository_name <> v_workspace.repository_name
     or v_source_lease.repository_external_id <>
        v_workspace.repository_external_id
     or v_source_lease.repository_node_id <> v_workspace.repository_node_id
     or v_source_lease.default_branch <> v_workspace.default_branch
     or v_source_lease.repository_ref <>
        'heads/' || v_workspace.default_branch
     or v_source_lease.ref_label <> v_workspace.default_branch
     or v_source_lease.marker_operation_id <> v_canonical_operation_id then
    raise exception using
      errcode = '42501', message = 'PROJECT_PREVIEW_BUILD_NOT_READY';
  end if;

  select artifact.artifact_id into v_artifact_id
  from lws_internal.website_project_preview_build_artifacts as artifact
  where artifact.preview_build_id = v_build.preview_build_id
  order by artifact.artifact_id
  limit 1
  for key share;
  if not found then
    raise exception using
      errcode = '42501', message = 'PROJECT_PREVIEW_BUILD_NOT_READY';
  end if;

  insert into lws_internal.website_project_preview_sessions (
    preview_build_id, session_token_hash, actor_auth_user_id, expires_at
  ) values (
    v_build.preview_build_id,
    p_session_token_hash,
    v_subject,
    clock_timestamp() + interval '30 minutes'
  )
  returning * into v_session;

  return jsonb_build_object(
    'previewSessionId', v_session.preview_session_id,
    'expiresAt', v_session.expires_at
  );
end;
$function$;

alter function public.create_website_project_preview_session_v1(uuid, text)
  owner to postgres;

revoke all on function
  public.create_website_project_preview_session_v1(uuid, text)
from public, anon, authenticated, service_role;

grant execute on function
  public.create_website_project_preview_session_v1(uuid, text)
to authenticated;

create or replace function public.open_existing_website_project_preview_v1(
  p_quote_request_id uuid,
  p_session_token_hash text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $function$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_work jsonb;
  v_context public.website_work_contexts%rowtype;
  v_workspace public.website_execution_workspaces%rowtype;
  v_operation public.website_repository_provisioning_operations%rowtype;
  v_canonical_operation_id uuid;
  v_build lws_internal.website_project_preview_builds%rowtype;
  v_artifact_id uuid;
  v_session lws_internal.website_project_preview_sessions%rowtype;
begin
  if p_quote_request_id is null
      or p_session_token_hash is null
      or p_session_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using
      errcode = '22023', message = 'PROJECT_PREVIEW_OPEN_INPUT_INVALID';
  end if;
  if v_subject is null
     or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select operator.* into v_operator
  from public.commercial_operators as operator
  where operator.auth_user_id = v_subject
  for update;
  if not found
     or v_operator.status <> 'ACTIVE'
     or v_operator.role <> 'owner'
     or v_operator.revoked_at is not null then
    raise exception using
      errcode = '42501', message = 'WEBSITE_REPOSITORY_OWNER_REQUIRED';
  end if;
  perform lws_internal.assert_operator_aal2_v1();

  v_work := public.get_operator_website_work_v1(p_quote_request_id);
  if v_work->>'state' not in ('PRE_PROJECT', 'OFFICIAL_PROJECT')
     or not (v_work->'permitted_actions' ? 'OPEN_WEBSITE')
     or nullif(v_work->>'website_work_context_id', '') is null then
    raise exception using
      errcode = 'P0001', message = 'WEBSITE_WORKSPACE_NOT_ELIGIBLE';
  end if;

  select context.* into v_context
  from public.website_work_contexts as context
  where context.website_work_context_id =
        (v_work->>'website_work_context_id')::uuid
    and context.quote_request_id = p_quote_request_id;
  if not found
     or v_context.phase is distinct from v_work->>'mode'
     or v_context.concept_id is distinct from
        nullif(v_work->>'concept_id', '')::uuid
     or v_context.project_id is distinct from
        nullif(v_work->>'project_id', '')::uuid then
    raise exception using
      errcode = 'P0001', message = 'WEBSITE_WORK_CONTEXT_BINDING_MISMATCH';
  end if;

  select workspace.* into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.website_work_context_id = v_context.website_work_context_id
    and workspace.quote_request_id = p_quote_request_id
    and workspace.project_id is not distinct from v_context.project_id
  for update;
  if not found
     or v_workspace.workspace_state <> 'REPOSITORY_READY'
     or v_workspace.repository_state <> 'BOUND'
     or v_workspace.repository_provider <> 'GITHUB'
     or v_workspace.repository_owner is null
     or v_workspace.repository_name is null
     or v_workspace.repository_external_id is null
     or v_workspace.repository_node_id is null
     or v_workspace.repository_visibility <> 'private'
    or v_workspace.repository_marker_commit_sha is null
    or v_workspace.repository_bound_at is null
     or v_workspace.binding_revision < 1
    or v_workspace.default_branch is null
     or v_workspace.last_commit_sha is null then
    raise exception using
      errcode = 'P0001', message = 'PROJECT_PREVIEW_REPOSITORY_NOT_READY';
  end if;

  v_canonical_operation_id :=
    lws_internal.get_website_repository_canonical_durable_operation_id_v1(
      v_workspace.website_workspace_id,
      v_context.website_work_context_id
    );
  select operation.* into v_operation
  from public.website_repository_provisioning_operations as operation
  where operation.operation_id = v_canonical_operation_id
  for update;
  if not found
     or v_operation.state <> 'BOUND'
     or v_operation.repository_provider is distinct from v_workspace.repository_provider
     or v_operation.repository_owner is distinct from v_workspace.repository_owner
     or v_operation.repository_name is distinct from v_workspace.repository_name
     or v_operation.repository_external_id is distinct from v_workspace.repository_external_id
     or v_operation.repository_node_id is distinct from v_workspace.repository_node_id then
    raise exception using
      errcode = 'P0001', message = 'PROJECT_PREVIEW_REPOSITORY_NOT_READY';
  end if;

  select build.* into v_build
  from lws_internal.website_project_preview_builds as build
  join lws_internal.website_project_preview_build_leases as preview_lease
    on preview_lease.preview_lease_id = build.lease_id
   and preview_lease.quote_request_id = build.quote_request_id
   and preview_lease.website_work_context_id = build.website_work_context_id
   and preview_lease.website_workspace_id = build.website_workspace_id
   and preview_lease.expected_commit_sha = build.commit_sha
  join lws_internal.website_project_files_write_leases as source_lease
    on source_lease.lease_id = preview_lease.source_write_lease_id
   and source_lease.quote_request_id = build.quote_request_id
   and source_lease.website_work_context_id = build.website_work_context_id
   and source_lease.website_workspace_id = build.website_workspace_id
   and source_lease.expected_commit_sha = build.commit_sha
  where build.quote_request_id = p_quote_request_id
    and build.website_work_context_id = v_context.website_work_context_id
    and build.website_workspace_id = v_workspace.website_workspace_id
    and build.build_status in ('PASS', 'PASS_WITH_WARNINGS')
    and build.commit_sha = v_workspace.last_commit_sha
    and source_lease.binding_revision = v_workspace.binding_revision
    and source_lease.repository_provider = v_workspace.repository_provider
    and source_lease.repository_owner = v_workspace.repository_owner
    and source_lease.repository_name = v_workspace.repository_name
    and source_lease.repository_external_id = v_workspace.repository_external_id
    and source_lease.repository_node_id = v_workspace.repository_node_id
    and source_lease.default_branch = v_workspace.default_branch
    and source_lease.marker_operation_id = v_canonical_operation_id
    and exists (
      select 1
      from lws_internal.website_project_preview_build_artifacts as artifact
      where artifact.preview_build_id = build.preview_build_id
    )
  order by
    build.built_at desc,
    build.preview_build_id desc
  limit 1
  for update of build;
  if not found then
    raise exception using
      errcode = 'P0001', message = 'PROJECT_PREVIEW_BUILD_NOT_FOUND';
  end if;

  select artifact.artifact_id into v_artifact_id
  from lws_internal.website_project_preview_build_artifacts as artifact
  where artifact.preview_build_id = v_build.preview_build_id
  order by artifact.artifact_id
  limit 1
  for key share;
  if not found then
    raise exception using
      errcode = 'P0001', message = 'PROJECT_PREVIEW_BUILD_NOT_FOUND';
  end if;

  insert into lws_internal.website_project_preview_sessions (
    preview_build_id, session_token_hash, actor_auth_user_id, expires_at
  ) values (
    v_build.preview_build_id,
    p_session_token_hash,
    v_subject,
    clock_timestamp() + interval '30 minutes'
  )
  returning * into v_session;

  return jsonb_build_object(
    'previewSessionId', v_session.preview_session_id,
    'previewBuildId', v_build.preview_build_id,
    'buildStatus', v_build.build_status,
    'builtCommitSha', v_build.commit_sha,
    'currentCommitSha', v_workspace.last_commit_sha,
    'builtAt', v_build.built_at,
    'expiresAt', v_session.expires_at,
    'isCurrentCommit', v_build.commit_sha = v_workspace.last_commit_sha,
    'quoteRequestId', p_quote_request_id,
    'websiteWorkContextId', v_context.website_work_context_id,
    'websiteWorkspaceId', v_workspace.website_workspace_id,
    'bindingRevision', v_workspace.binding_revision
  );
end;
$function$;

alter function public.open_existing_website_project_preview_v1(uuid, text)
  owner to postgres;

revoke all on function
  public.open_existing_website_project_preview_v1(uuid, text)
from public, anon, authenticated, service_role;

grant execute on function
  public.open_existing_website_project_preview_v1(uuid, text)
to authenticated;

comment on function public.open_existing_website_project_preview_v1(uuid, text) is
  'OWNER+AAL2 dossier-bound reopening of the latest valid preview build for the workspace current commit, with atomic fresh hashed viewer-session issuance.';

create index website_project_preview_sessions_unrevoked_build_id_idx
  on lws_internal.website_project_preview_sessions (preview_build_id)
  where revoked_at is null;

create or replace function public.sweep_expired_website_project_preview_artifacts_v1(
  p_retention_hours integer default 24
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $function$
declare
  v_retention_cutoff timestamptz :=
    clock_timestamp() - make_interval(hours => p_retention_hours);
  v_expired_build_id uuid;
  v_expired_build_ids uuid[] := array[]::uuid[];
  v_expired_lease_count integer;
  v_expired_session_count integer;
  v_deleted_artifact_count integer;
begin
  update lws_internal.website_project_preview_build_leases as lease
  set released_at = clock_timestamp()
  where lease.released_at is null
    and lease.expires_at <= clock_timestamp()
    and not exists (
      select 1 from lws_internal.website_project_preview_builds as build
      where build.lease_id = lease.preview_lease_id
    );
  get diagnostics v_expired_lease_count = row_count;

  for v_expired_build_id in
    select build.preview_build_id
    from (
      select artifact.preview_build_id
      from lws_internal.website_project_preview_build_artifacts as artifact
      union
      select session.preview_build_id
      from lws_internal.website_project_preview_sessions as session
      where session.revoked_at is null
    ) as pending_build
    join lws_internal.website_project_preview_builds as build
      on build.preview_build_id = pending_build.preview_build_id
    where build.built_at <= v_retention_cutoff
    order by build.preview_build_id
    for update of build
  loop
    v_expired_build_ids :=
      array_append(v_expired_build_ids, v_expired_build_id);
  end loop;

  update lws_internal.website_project_preview_sessions as session
  set revoked_at = clock_timestamp()
  where session.revoked_at is null
    and session.preview_build_id = any(v_expired_build_ids);
  get diagnostics v_expired_session_count = row_count;

  delete from lws_internal.website_project_preview_build_artifacts as artifact
  where artifact.preview_build_id = any(v_expired_build_ids);
  get diagnostics v_deleted_artifact_count = row_count;

  return jsonb_build_object(
    'expiredLeasesReleased', v_expired_lease_count,
    'expiredSessionsRevoked', v_expired_session_count,
    'orphanedArtifactRowsDeleted', v_deleted_artifact_count
  );
end;
$function$;

alter function
  public.sweep_expired_website_project_preview_artifacts_v1(integer)
owner to postgres;

revoke all on function
  public.sweep_expired_website_project_preview_artifacts_v1(integer)
from public, anon, authenticated, service_role;

grant execute on function
  public.sweep_expired_website_project_preview_artifacts_v1(integer)
to service_role;
