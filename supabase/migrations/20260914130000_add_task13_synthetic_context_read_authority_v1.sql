create function public.verify_task13_synthetic_context_authority_v1(
  p_website_work_context_id uuid,
  p_website_workspace_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
begin
  perform lws_internal.require_website_repository_owner_v1();

  return exists (
    select 1
    from public.website_work_contexts as context
    join public.website_execution_workspaces as workspace
      on workspace.website_work_context_id = context.website_work_context_id
     and workspace.quote_request_id = context.quote_request_id
    join public.quote_requests as request
      on request.id = context.quote_request_id
    where context.website_work_context_id = p_website_work_context_id
      and workspace.website_workspace_id = p_website_workspace_id
      and context.project_id is null
      and workspace.project_id is null
      and context.phase = 'PRE_PROJECT'
      and request.record_classification = 'internal_e2e'
      and request.request_kind = 'website'
      and request.application_reference is null
  );
end;
$$;

revoke all on function
  public.verify_task13_synthetic_context_authority_v1(uuid, uuid)
from public, anon, authenticated, service_role;

grant execute on function
  public.verify_task13_synthetic_context_authority_v1(uuid, uuid)
to authenticated;

comment on function
  public.verify_task13_synthetic_context_authority_v1(uuid, uuid) is
  'Read-only OWNER+AAL2 authority check for the isolated Task 13 synthetic context and workspace relation.';