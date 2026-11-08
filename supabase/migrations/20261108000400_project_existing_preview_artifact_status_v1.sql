create function public.get_website_execution_workspace_v7(p_quote_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_projection jsonb;
  v_preview jsonb;
begin
  -- Keep the existing caller authorization and workspace binding checks.
  v_projection := public.get_website_execution_workspace_v6(p_quote_request_id);

  select jsonb_build_object(
    'preview_build_id', build.preview_build_id,
    'commit_sha', build.commit_sha,
    'build_status', build.build_status,
    'built_at', build.built_at
  ) into v_preview
  from public.website_execution_workspaces as workspace
  join lws_internal.website_project_preview_builds as build
    on build.website_workspace_id = workspace.website_workspace_id
   and build.website_work_context_id = workspace.website_work_context_id
   and build.quote_request_id = workspace.quote_request_id
   and build.commit_sha = workspace.last_commit_sha
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
   and source_lease.binding_revision = workspace.binding_revision
   and source_lease.repository_provider = workspace.repository_provider
   and source_lease.repository_owner = workspace.repository_owner
   and source_lease.repository_name = workspace.repository_name
   and source_lease.repository_external_id = workspace.repository_external_id
   and source_lease.repository_node_id = workspace.repository_node_id
   and source_lease.default_branch = workspace.default_branch
   and source_lease.marker_operation_id =
     lws_internal.get_website_repository_canonical_durable_operation_id_v1(
       workspace.website_workspace_id, workspace.website_work_context_id
     )
  where workspace.quote_request_id = p_quote_request_id
    and workspace.website_workspace_id =
      (v_projection->'workspace'->>'website_workspace_id')::uuid
    and workspace.website_work_context_id =
      (v_projection->>'website_work_context_id')::uuid
    and workspace.workspace_state = 'REPOSITORY_READY'
    and workspace.repository_state = 'BOUND'
    and build.build_status in ('PASS', 'PASS_WITH_WARNINGS')
    and exists (
      select 1
      from lws_internal.website_project_preview_build_artifacts as artifact
      where artifact.preview_build_id = build.preview_build_id
        and artifact.relative_path = build.artifact_path
    )
  order by build.built_at desc, build.preview_build_id desc
  limit 1;

  return v_projection || jsonb_build_object(
    'contract_version', 7,
    'preview_artifact', v_preview
  );
end;
$$;

revoke all on function public.get_website_execution_workspace_v7(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_website_execution_workspace_v7(uuid)
to authenticated;

comment on function public.get_website_execution_workspace_v7(uuid) is
  'Read-only existing preview artifact projection for the current authorized repository binding and commit. Does not acquire leases, create sessions, or dispatch builds.';
