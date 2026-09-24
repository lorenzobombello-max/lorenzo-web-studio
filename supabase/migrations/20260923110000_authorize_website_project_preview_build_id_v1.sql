alter table lws_internal.website_project_preview_build_leases
  add column authorized_build_id uuid not null default gen_random_uuid();

create unique index website_project_preview_build_leases_authorized_build_id_key
  on lws_internal.website_project_preview_build_leases (authorized_build_id);

create or replace function public.acquire_website_project_preview_build_v1(
  p_quote_request_id uuid,
  p_expected_commit_sha text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_authority jsonb;
  v_source lws_internal.website_project_files_write_leases%rowtype;
  v_preview lws_internal.website_project_preview_build_leases%rowtype;
begin
  v_authority := public.acquire_website_project_files_write_v1(
    p_quote_request_id,
    'index.html',
    p_expected_commit_sha,
    p_idempotency_key
  );
  select source.* into strict v_source
  from lws_internal.website_project_files_write_leases as source
  where source.lease_id = (v_authority->>'leaseId')::uuid
    and source.actor_auth_user_id = auth.uid()
  for update;
  insert into lws_internal.website_project_preview_build_leases (
    source_write_lease_id, actor_auth_user_id, quote_request_id,
    website_work_context_id, website_workspace_id, expected_commit_sha,
    acquired_at, expires_at
  ) values (
    v_source.lease_id, v_source.actor_auth_user_id, v_source.quote_request_id,
    v_source.website_work_context_id, v_source.website_workspace_id,
    v_source.expected_commit_sha, v_now, v_now + interval '20 minutes'
  )
  on conflict (source_write_lease_id) do update
  set source_write_lease_id = excluded.source_write_lease_id
  returning * into v_preview;
  return v_authority || jsonb_build_object(
    'leaseId', v_preview.preview_lease_id,
    'buildId', v_preview.authorized_build_id,
    'expiresAt', v_preview.expires_at
  );
end;
$$;

create or replace function public.resolve_website_project_preview_artifact_authority_v1(
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
  if v_lease.authorized_build_id <> p_build_id then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_BUILD_AUTHORITY_INVALID';
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
    'buildId', v_lease.authorized_build_id
  );
end;
$$;

create function lws_internal.enforce_website_project_preview_authorized_build_id_v1()
returns trigger
language plpgsql
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_row jsonb := to_jsonb(new);
  v_lease_id uuid := coalesce(
    (v_row->>'preview_lease_id')::uuid,
    (v_row->>'lease_id')::uuid
  );
begin
  if not exists (
    select 1
    from lws_internal.website_project_preview_build_leases lease
    where lease.preview_lease_id = v_lease_id
      and lease.authorized_build_id = (v_row->>'build_id')::uuid
  ) then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_BUILD_AUTHORITY_INVALID';
  end if;
  return new;
end;
$$;

create trigger enforce_preview_artifact_token_authorized_build_id
before insert or update of preview_lease_id, build_id
on lws_internal.website_project_preview_artifact_tokens
for each row execute function lws_internal.enforce_website_project_preview_authorized_build_id_v1();

create trigger enforce_preview_upload_session_authorized_build_id
before insert or update of preview_lease_id, build_id
on lws_internal.website_project_preview_upload_sessions
for each row execute function lws_internal.enforce_website_project_preview_authorized_build_id_v1();

revoke all on function lws_internal.enforce_website_project_preview_authorized_build_id_v1()
from public, anon, authenticated, service_role;
