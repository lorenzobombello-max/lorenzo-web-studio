create function public.record_website_project_preview_ready_v1(
  p_quote_request_id uuid,
  p_project_id uuid,
  p_preview_build_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_authorization record;
  v_project public.commercial_projects%rowtype;
  v_build lws_internal.website_project_preview_builds%rowtype;
  v_previous_state text;
  v_expected_revision bigint;
begin
  if p_quote_request_id is null
     or p_project_id is null
     or p_preview_build_id is null
     or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'WEBSITE_PREVIEW_READY_INPUT_INVALID';
  end if;

  select * into strict v_authorization
  from public.resolve_commercial_operator_authorization_v1(
    p_project_id,
    'record_preview_ready',
    true
  );
  perform lws_internal.assert_operator_aal2_v1();

  select project.* into v_project
  from public.commercial_projects as project
  where project.project_id = p_project_id
  for update;
  if not found then
    raise exception using errcode = '23503', message = 'PROJECT_NOT_FOUND';
  end if;

  select build.* into v_build
  from lws_internal.website_project_preview_builds as build
  join lws_internal.website_project_preview_build_leases as preview_lease
    on preview_lease.preview_lease_id = build.lease_id
   and preview_lease.actor_auth_user_id = build.actor_auth_user_id
   and preview_lease.quote_request_id = build.quote_request_id
   and preview_lease.website_work_context_id = build.website_work_context_id
   and preview_lease.website_workspace_id = build.website_workspace_id
   and preview_lease.expected_commit_sha = build.commit_sha
  join lws_internal.website_project_files_write_leases as source_lease
    on source_lease.lease_id = preview_lease.source_write_lease_id
   and source_lease.actor_auth_user_id = build.actor_auth_user_id
   and source_lease.quote_request_id = build.quote_request_id
   and source_lease.website_work_context_id = build.website_work_context_id
   and source_lease.website_workspace_id = build.website_workspace_id
   and source_lease.expected_commit_sha = build.commit_sha
  join public.website_work_contexts as context
    on context.website_work_context_id = build.website_work_context_id
   and context.quote_request_id = build.quote_request_id
  join public.website_execution_workspaces as workspace
    on workspace.website_workspace_id = build.website_workspace_id
   and workspace.website_work_context_id = build.website_work_context_id
   and workspace.quote_request_id = build.quote_request_id
  and workspace.repository_owner = source_lease.repository_owner
  and workspace.repository_name = source_lease.repository_name
  and workspace.binding_revision = source_lease.binding_revision
  and workspace.last_commit_sha = build.commit_sha
  where build.preview_build_id = p_preview_build_id
    and build.quote_request_id = p_quote_request_id
    and context.project_id = p_project_id
    and context.phase = 'OFFICIAL_PROJECT'
    and workspace.project_id = p_project_id
    and build.build_status in ('PASS', 'PASS_WITH_WARNINGS')
  for update of build;
  if not found then
    raise exception using errcode = '23514', message = 'WEBSITE_PREVIEW_BUILD_BINDING_INVALID';
  end if;

  select event.previous_state, event.project_revision - 1
  into v_previous_state, v_expected_revision
  from public.workflow_events as event
  where event.project_id = p_project_id
    and event.command_id = p_idempotency_key
    and event.new_state = 'PREVIEW_READY';

  if not found then
    if v_project.current_state <> 'PROJECT_RELEASED' then
      raise exception using errcode = 'P0001', message = 'WEBSITE_PREVIEW_READY_STATE_INVALID';
    end if;
    v_previous_state := v_project.current_state;
    v_expected_revision := v_project.revision;
  end if;

  return lws_internal.execute_commercial_command_core_v1(
    v_authorization.audit_actor,
    p_project_id,
    'record_preview_ready',
    v_previous_state,
    v_expected_revision,
    p_idempotency_key,
    jsonb_build_object(
      'content_reference', v_build.artifact_path,
      'content_sha256', v_build.artifact_sha256
    )
  );
end;
$$;

revoke all on function public.record_website_project_preview_ready_v1(uuid, uuid, uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.record_website_project_preview_ready_v1(uuid, uuid, uuid, uuid)
to authenticated;

comment on function public.record_website_project_preview_ready_v1(uuid, uuid, uuid, uuid) is
  'AAL2 owner/operator action that derives preview evidence from one successful dossier-bound server build before invoking the requirements-gated commercial transition.';