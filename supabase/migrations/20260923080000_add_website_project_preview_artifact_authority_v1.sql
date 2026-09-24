create function public.resolve_website_project_preview_artifact_authority_v1(
  p_lease_id uuid,
  p_build_id uuid,
  p_workflow_run_id bigint
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_lease lws_internal.website_project_preview_build_leases%rowtype;
  v_source lws_internal.website_project_files_write_leases%rowtype;
begin
  if coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_ARTIFACT_BROKER_FORBIDDEN';
  end if;
  if p_build_id is null or p_workflow_run_id is null or p_workflow_run_id <= 0 then
    raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_ARTIFACT_AUTHORITY_INVALID';
  end if;
  select * into v_lease
  from lws_internal.website_project_preview_build_leases
  where preview_lease_id = p_lease_id;
  if not found or v_lease.released_at is not null or v_lease.expires_at <= clock_timestamp() then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_LEASE_INVALID';
  end if;
  select * into strict v_source
  from lws_internal.website_project_files_write_leases
  where lease_id = v_lease.source_write_lease_id;
  return jsonb_build_object(
    'repository', v_source.repository_owner || '/' || v_source.repository_name,
    'repositoryId', v_source.repository_external_id::text,
    'commitSha', v_lease.expected_commit_sha,
    'runId', p_workflow_run_id::text,
    'leaseId', v_lease.preview_lease_id,
    'buildId', p_build_id
  );
end;
$$;

revoke all on function
  public.resolve_website_project_preview_artifact_authority_v1(uuid,uuid,bigint)
from public, anon, authenticated;
grant execute on function
  public.resolve_website_project_preview_artifact_authority_v1(uuid,uuid,bigint)
to service_role;