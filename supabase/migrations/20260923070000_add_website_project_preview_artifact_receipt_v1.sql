-- GIT-001C local artifact receipt authority. Tokens are short-lived,
-- hash-only, bound to one lease/build/repository/commit/workflow run, and
-- consumed by one atomic UPDATE before any artifact bytes are accepted.
create table lws_internal.website_project_preview_artifact_tokens (
  token_hash text primary key check (token_hash ~ '^[0-9a-f]{64}$'),
  preview_lease_id uuid not null
    references lws_internal.website_project_preview_build_leases(preview_lease_id)
    on delete cascade,
  build_id uuid not null,
  repository_external_id bigint not null check (repository_external_id > 0),
  commit_sha text not null check (commit_sha ~ '^[0-9a-f]{40}$'),
  workflow_run_id bigint not null check (workflow_run_id > 0),
  issued_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  unique (preview_lease_id, build_id)
);

alter table lws_internal.website_project_preview_artifact_tokens enable row level security;
alter table lws_internal.website_project_preview_artifact_tokens force row level security;
revoke all on table lws_internal.website_project_preview_artifact_tokens
from public, anon, authenticated, service_role;

create function public.issue_website_project_preview_artifact_token_v1(
  p_token_hash text,
  p_lease_id uuid,
  p_build_id uuid,
  p_repository_external_id bigint,
  p_commit_sha text,
  p_workflow_run_id bigint,
  p_ttl_seconds integer default 300
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_lease lws_internal.website_project_preview_build_leases%rowtype;
  v_source lws_internal.website_project_files_write_leases%rowtype;
  v_expires_at timestamptz;
begin
  if coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_ARTIFACT_BROKER_FORBIDDEN';
  end if;
  if p_token_hash !~ '^[0-9a-f]{64}$' or p_build_id is null
    or p_repository_external_id is null or p_repository_external_id <= 0
    or p_commit_sha !~ '^[0-9a-f]{40}$'
    or p_workflow_run_id is null or p_workflow_run_id <= 0
    or p_ttl_seconds not between 1 and 300
  then
    raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_ARTIFACT_AUTHORITY_INVALID';
  end if;
  select * into v_lease
  from lws_internal.website_project_preview_build_leases
  where preview_lease_id = p_lease_id
  for update;
  if not found or v_lease.released_at is not null
    or v_lease.expires_at <= clock_timestamp()
    or v_lease.expected_commit_sha <> p_commit_sha
  then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_LEASE_INVALID';
  end if;
  select * into strict v_source
  from lws_internal.website_project_files_write_leases
  where lease_id = v_lease.source_write_lease_id;
  if v_source.repository_external_id <> p_repository_external_id then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_REPOSITORY_MISMATCH';
  end if;
  v_expires_at := least(
    v_lease.expires_at,
    clock_timestamp() + make_interval(secs => p_ttl_seconds)
  );
  insert into lws_internal.website_project_preview_artifact_tokens (
    token_hash, preview_lease_id, build_id, repository_external_id,
    commit_sha, workflow_run_id, expires_at
  ) values (
    p_token_hash, p_lease_id, p_build_id, p_repository_external_id,
    p_commit_sha, p_workflow_run_id, v_expires_at
  );
  return jsonb_build_object('expiresAt', v_expires_at);
end;
$$;

create function public.consume_website_project_preview_artifact_token_v1(
  p_token_hash text,
  p_lease_id uuid,
  p_build_id uuid,
  p_repository_external_id bigint,
  p_commit_sha text,
  p_workflow_run_id bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_token lws_internal.website_project_preview_artifact_tokens%rowtype;
begin
  if coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_ARTIFACT_RECEIPT_FORBIDDEN';
  end if;
  update lws_internal.website_project_preview_artifact_tokens
  set consumed_at = clock_timestamp()
  where token_hash = p_token_hash
    and preview_lease_id = p_lease_id
    and build_id = p_build_id
    and repository_external_id = p_repository_external_id
    and commit_sha = p_commit_sha
    and workflow_run_id = p_workflow_run_id
    and consumed_at is null
    and expires_at > clock_timestamp()
  returning * into v_token;
  if not found then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_ARTIFACT_TOKEN_INVALID';
  end if;
  return jsonb_build_object(
    'leaseId', v_token.preview_lease_id,
    'buildId', v_token.build_id,
    'commitSha', v_token.commit_sha
  );
end;
$$;

revoke all on function
  public.issue_website_project_preview_artifact_token_v1(text,uuid,uuid,bigint,text,bigint,integer),
  public.consume_website_project_preview_artifact_token_v1(text,uuid,uuid,bigint,text,bigint)
from public, anon, authenticated;
grant execute on function
  public.issue_website_project_preview_artifact_token_v1(text,uuid,uuid,bigint,text,bigint,integer),
  public.consume_website_project_preview_artifact_token_v1(text,uuid,uuid,bigint,text,bigint)
to service_role;

update storage.buckets
set file_size_limit = 5242880,
    allowed_mime_types = array[
      'text/html', 'text/css', 'text/javascript', 'application/json',
      'application/xml', 'text/plain', 'image/png', 'image/jpeg',
      'image/gif', 'image/webp', 'image/avif', 'image/x-icon',
      'font/woff', 'font/woff2', 'application/octet-stream'
    ]::text[]
where id = 'website-project-previews';