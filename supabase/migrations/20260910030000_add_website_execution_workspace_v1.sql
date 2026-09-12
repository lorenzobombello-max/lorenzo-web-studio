create table public.website_execution_workspaces (
  website_workspace_id uuid primary key default gen_random_uuid(),
  project_id uuid not null unique references public.commercial_projects(project_id),
  quote_request_id uuid not null references public.quote_requests(id),
  repository_provider text not null default 'GITHUB'
    check (repository_provider = 'GITHUB'),
  repository_owner text not null
    check (repository_owner ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,98}[A-Za-z0-9]$'),
  repository_name text not null
    check (repository_name ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,98}[A-Za-z0-9]$'),
  default_branch text not null default 'main'
    check (default_branch = 'main'),
  preview_branch text default 'develop'
    check (preview_branch is null or preview_branch = 'develop'),
  preview_url text
    check (preview_url is null or preview_url ~ '^https://[^[:space:]]+$'),
  last_commit_sha text
    check (last_commit_sha is null or last_commit_sha ~ '^[0-9a-f]{40}$'),
  last_commit_at timestamptz,
  last_build_result text
    check (last_build_result is null or last_build_result in ('PASS', 'FAIL', 'UNKNOWN')),
  last_build_at timestamptz,
  binding_revision bigint not null default 1 check (binding_revision > 0),
  created_by uuid not null references public.commercial_operators(operator_id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint website_execution_workspace_repo_unique
    unique (repository_provider, repository_owner, repository_name)
);

alter table public.website_execution_workspaces enable row level security;
alter table public.website_execution_workspaces force row level security;

create function public.get_website_execution_workspace_v1(
  p_quote_request_id uuid,
  p_project_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_project jsonb;
  v_start_gate jsonb;
  v_workspace public.website_execution_workspaces%rowtype;
begin
  if p_quote_request_id is null or p_project_id is null then
    raise exception using errcode = '22023', message = 'WEBSITE_WORKSPACE_LOCATORS_REQUIRED';
  end if;

  v_start_gate := public.get_operator_project_start_gate_v1(
    p_quote_request_id,
    p_project_id
  );
  v_project := public.get_commercial_project_view_v2(p_project_id);

  if not exists (
    select 1
    from public.audit_events as event
    where event.project_id = p_project_id
      and event.event_type = 'PROJECT_WORK_STARTED'
      and event.metadata->>'quote_request_id' = p_quote_request_id::text
  ) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_WORKSPACE_NOT_ELIGIBLE';
  end if;

  select workspace.*
  into v_workspace
  from public.website_execution_workspaces as workspace
  where workspace.project_id = p_project_id;

  if v_workspace.website_workspace_id is not null
     and v_workspace.quote_request_id <> p_quote_request_id then
    raise exception using errcode = 'P0001', message = 'WEBSITE_WORKSPACE_BINDING_MISMATCH';
  end if;

  return jsonb_build_object(
    'project', v_project,
    'start_gate', v_start_gate,
    'workspace', case when v_workspace.website_workspace_id is null then null
      else jsonb_build_object(
        'website_workspace_id', v_workspace.website_workspace_id,
        'project_id', v_workspace.project_id,
        'quote_request_id', v_workspace.quote_request_id,
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
        'created_at', v_workspace.created_at,
        'updated_at', v_workspace.updated_at
      )
    end
  );
end;
$$;

revoke all privileges on table public.website_execution_workspaces
from public, anon, authenticated, service_role;

revoke all on function public.get_website_execution_workspace_v1(uuid, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.get_website_execution_workspace_v1(uuid, uuid)
to authenticated;

comment on table public.website_execution_workspaces is
  'Narrow per-project technical references only; no source code, secrets, production URL, or business lifecycle state.';

comment on function public.get_website_execution_workspace_v1(uuid, uuid) is
  'Read-only Website Execution Workspace projection reusing project authorization, exact dossier binding, project-start eligibility, and commercial project site authority.';