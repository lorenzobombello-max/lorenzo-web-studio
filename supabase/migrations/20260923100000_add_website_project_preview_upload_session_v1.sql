create table lws_internal.website_project_preview_upload_sessions (
  session_token_hash text primary key check (session_token_hash ~ '^[0-9a-f]{64}$'),
  preview_lease_id uuid not null references lws_internal.website_project_preview_build_leases(preview_lease_id) on delete cascade,
  build_id uuid not null,
  repository_external_id bigint not null check (repository_external_id > 0),
  commit_sha text not null check (commit_sha ~ '^[0-9a-f]{40}$'),
  workflow_run_id bigint not null check (workflow_run_id > 0),
  primary_relative_path text not null,
  build_status text not null check (build_status in ('PASS', 'PASS_WITH_WARNINGS')),
  status text not null default 'OPEN' check (status in ('OPEN', 'FINALIZED', 'ABORTED')),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  finalized_at timestamptz,
  aborted_at timestamptz,
  unique (preview_lease_id, build_id)
);

create table lws_internal.website_project_preview_upload_files (
  session_token_hash text not null references lws_internal.website_project_preview_upload_sessions(session_token_hash) on delete cascade,
  relative_path text not null,
  content_type text not null,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  bytes bigint not null check (bytes between 0 and 5242880),
  state text not null default 'EXPECTED' check (state in ('EXPECTED', 'UPLOADING', 'RECEIVED')),
  claimed_at timestamptz,
  received_at timestamptz,
  primary key (session_token_hash, relative_path)
);

alter table lws_internal.website_project_preview_upload_sessions enable row level security;
alter table lws_internal.website_project_preview_upload_sessions force row level security;
alter table lws_internal.website_project_preview_upload_files enable row level security;
alter table lws_internal.website_project_preview_upload_files force row level security;
revoke all on table
  lws_internal.website_project_preview_upload_sessions,
  lws_internal.website_project_preview_upload_files
from public, anon, authenticated, service_role;

create function public.open_website_project_preview_upload_session_v1(
  p_receipt_token_hash text,
  p_session_token_hash text,
  p_lease_id uuid,
  p_build_id uuid,
  p_repository_external_id bigint,
  p_commit_sha text,
  p_workflow_run_id bigint,
  p_primary_relative_path text,
  p_build_status text,
  p_manifest jsonb,
  p_ttl_seconds integer default 600
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_token lws_internal.website_project_preview_artifact_tokens%rowtype;
  v_lease lws_internal.website_project_preview_build_leases%rowtype;
  v_entry jsonb;
  v_count integer := 0;
  v_total bigint := 0;
  v_expires_at timestamptz;
  v_primary_found boolean := false;
begin
  if coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_UPLOAD_SESSION_FORBIDDEN';
  end if;
  if p_receipt_token_hash !~ '^[0-9a-f]{64}$' or p_session_token_hash !~ '^[0-9a-f]{64}$'
    or p_build_id is null or p_repository_external_id <= 0 or p_commit_sha !~ '^[0-9a-f]{40}$'
    or p_workflow_run_id <= 0 or p_build_status not in ('PASS', 'PASS_WITH_WARNINGS')
    or p_ttl_seconds not between 1 and 600 or jsonb_typeof(p_manifest) <> 'array'
    or jsonb_array_length(p_manifest) < 1 or jsonb_array_length(p_manifest) > 500
  then
    raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_UPLOAD_SESSION_INVALID';
  end if;

  update lws_internal.website_project_preview_artifact_tokens
  set consumed_at = clock_timestamp()
  where token_hash = p_receipt_token_hash and preview_lease_id = p_lease_id and build_id = p_build_id
    and repository_external_id = p_repository_external_id and commit_sha = p_commit_sha
    and workflow_run_id = p_workflow_run_id and consumed_at is null and expires_at > clock_timestamp()
  returning * into v_token;
  if not found then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_ARTIFACT_TOKEN_INVALID';
  end if;

  select * into v_lease from lws_internal.website_project_preview_build_leases
  where preview_lease_id = p_lease_id for update;
  if not found or v_lease.released_at is not null or v_lease.expires_at <= clock_timestamp()
    or v_lease.expected_commit_sha <> p_commit_sha
  then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_LEASE_INVALID';
  end if;

  for v_entry in select * from jsonb_array_elements(p_manifest)
  loop
    if not (v_entry ? 'relative_path' and v_entry ? 'content_type' and v_entry ? 'sha256' and v_entry ? 'bytes')
      or (v_entry->>'relative_path') !~ '^[A-Za-z0-9._/-]+$' or left(v_entry->>'relative_path', 1) = '/'
      or (v_entry->>'relative_path') like '%..%' or (v_entry->>'sha256') !~ '^[0-9a-f]{64}$'
      or (v_entry->>'bytes')::bigint not between 0 and 5242880
    then
      raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_UPLOAD_MANIFEST_INVALID';
    end if;
    v_count := v_count + 1;
    v_total := v_total + (v_entry->>'bytes')::bigint;
    v_primary_found := v_primary_found or v_entry->>'relative_path' = p_primary_relative_path;
  end loop;
  if v_total > 52428800 or not v_primary_found then
    raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_UPLOAD_MANIFEST_INVALID';
  end if;

  v_expires_at := least(v_lease.expires_at, clock_timestamp() + make_interval(secs => p_ttl_seconds));
  insert into lws_internal.website_project_preview_upload_sessions (
    session_token_hash, preview_lease_id, build_id, repository_external_id, commit_sha,
    workflow_run_id, primary_relative_path, build_status, expires_at
  ) values (
    p_session_token_hash, p_lease_id, p_build_id, p_repository_external_id, p_commit_sha,
    p_workflow_run_id, p_primary_relative_path, p_build_status, v_expires_at
  );
  insert into lws_internal.website_project_preview_upload_files (
    session_token_hash, relative_path, content_type, sha256, bytes
  )
  select p_session_token_hash, entry->>'relative_path', entry->>'content_type',
    entry->>'sha256', (entry->>'bytes')::bigint
  from jsonb_array_elements(p_manifest) entry;
  if (select count(*) from lws_internal.website_project_preview_upload_files where session_token_hash = p_session_token_hash) <> v_count then
    raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_UPLOAD_MANIFEST_DUPLICATE';
  end if;
  return jsonb_build_object('expiresAt', v_expires_at);
end;
$$;

create function public.claim_website_project_preview_upload_file_v1(
  p_session_token_hash text, p_lease_id uuid, p_build_id uuid, p_repository_external_id bigint,
  p_commit_sha text, p_workflow_run_id bigint, p_relative_path text, p_content_type text,
  p_sha256 text, p_bytes bigint
)
returns jsonb language plpgsql volatile security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
begin
  if coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_UPLOAD_FILE_FORBIDDEN';
  end if;
  perform 1 from lws_internal.website_project_preview_upload_sessions
  where session_token_hash = p_session_token_hash and preview_lease_id = p_lease_id and build_id = p_build_id
    and repository_external_id = p_repository_external_id and commit_sha = p_commit_sha
    and workflow_run_id = p_workflow_run_id and status = 'OPEN' and expires_at > clock_timestamp()
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_UPLOAD_SESSION_INVALID';
  end if;
  update lws_internal.website_project_preview_upload_files set state = 'UPLOADING', claimed_at = clock_timestamp()
  where session_token_hash = p_session_token_hash and relative_path = p_relative_path and state = 'EXPECTED'
    and content_type = p_content_type and sha256 = p_sha256 and bytes = p_bytes;
  if not found then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_UPLOAD_FILE_INVALID';
  end if;
  return jsonb_build_object('relativePath', p_relative_path);
end;
$$;

create function public.complete_website_project_preview_upload_file_v1(
  p_session_token_hash text, p_lease_id uuid, p_build_id uuid, p_repository_external_id bigint,
  p_commit_sha text, p_workflow_run_id bigint, p_relative_path text
)
returns jsonb language plpgsql volatile security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
begin
  if coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_UPLOAD_FILE_FORBIDDEN';
  end if;
  perform 1 from lws_internal.website_project_preview_upload_sessions
  where session_token_hash = p_session_token_hash and preview_lease_id = p_lease_id and build_id = p_build_id
    and repository_external_id = p_repository_external_id and commit_sha = p_commit_sha
    and workflow_run_id = p_workflow_run_id and status = 'OPEN' and expires_at > clock_timestamp()
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_UPLOAD_SESSION_INVALID';
  end if;
  update lws_internal.website_project_preview_upload_files set state = 'RECEIVED', received_at = clock_timestamp()
  where session_token_hash = p_session_token_hash and relative_path = p_relative_path and state = 'UPLOADING';
  if not found then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_UPLOAD_FILE_INVALID';
  end if;
  return jsonb_build_object('relativePath', p_relative_path);
end;
$$;

create function public.abort_website_project_preview_upload_session_v1(
  p_session_token_hash text, p_lease_id uuid, p_build_id uuid, p_repository_external_id bigint,
  p_commit_sha text, p_workflow_run_id bigint
)
returns jsonb language plpgsql volatile security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare v_paths jsonb;
begin
  if coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_UPLOAD_SESSION_FORBIDDEN';
  end if;
  update lws_internal.website_project_preview_upload_sessions set status = 'ABORTED', aborted_at = coalesce(aborted_at, clock_timestamp())
  where session_token_hash = p_session_token_hash and preview_lease_id = p_lease_id and build_id = p_build_id
    and repository_external_id = p_repository_external_id and commit_sha = p_commit_sha
    and workflow_run_id = p_workflow_run_id and status in ('OPEN', 'ABORTED');
  if not found then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_UPLOAD_SESSION_INVALID';
  end if;
  select coalesce(jsonb_agg(relative_path order by relative_path), '[]'::jsonb) into v_paths
  from lws_internal.website_project_preview_upload_files
  where session_token_hash = p_session_token_hash and state in ('UPLOADING', 'RECEIVED');
  return jsonb_build_object('uploadedPaths', v_paths);
end;
$$;

create function public.finalize_website_project_preview_upload_session_v1(
  p_session_token_hash text, p_lease_id uuid, p_build_id uuid, p_repository_external_id bigint,
  p_commit_sha text, p_workflow_run_id bigint
)
returns jsonb language plpgsql volatile security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_session lws_internal.website_project_preview_upload_sessions%rowtype;
  v_lease lws_internal.website_project_preview_build_leases%rowtype;
  v_preview_build_id uuid;
  v_total bigint;
  v_primary_sha text;
begin
  if coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_UPLOAD_FINALIZE_FORBIDDEN';
  end if;
  select * into v_session from lws_internal.website_project_preview_upload_sessions
  where session_token_hash = p_session_token_hash and preview_lease_id = p_lease_id and build_id = p_build_id
    and repository_external_id = p_repository_external_id and commit_sha = p_commit_sha
    and workflow_run_id = p_workflow_run_id for update;
  if not found or v_session.status <> 'OPEN' or v_session.expires_at <= clock_timestamp() then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_UPLOAD_SESSION_INVALID';
  end if;
  if exists (select 1 from lws_internal.website_project_preview_upload_files where session_token_hash = p_session_token_hash and state <> 'RECEIVED') then
    raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_UPLOAD_SESSION_INCOMPLETE';
  end if;
  select * into v_lease from lws_internal.website_project_preview_build_leases
  where preview_lease_id = p_lease_id for update;
  if not found or v_lease.released_at is not null or v_lease.expires_at <= clock_timestamp()
    or v_lease.expected_commit_sha <> p_commit_sha
  then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_LEASE_INVALID';
  end if;
  select sum(bytes), max(sha256) filter (where relative_path = v_session.primary_relative_path)
  into v_total, v_primary_sha from lws_internal.website_project_preview_upload_files
  where session_token_hash = p_session_token_hash;
  if v_primary_sha is null then
    raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_UPLOAD_SESSION_INCOMPLETE';
  end if;
  insert into lws_internal.website_project_preview_builds (
    preview_build_id, lease_id, actor_auth_user_id, quote_request_id, website_work_context_id,
    website_workspace_id, commit_sha, artifact_path, artifact_sha256, artifact_bytes, build_status
  ) values (
    gen_random_uuid(), p_lease_id, v_lease.actor_auth_user_id, v_lease.quote_request_id, v_lease.website_work_context_id,
    v_lease.website_workspace_id, p_commit_sha, v_session.primary_relative_path, v_primary_sha, v_total, v_session.build_status
  ) returning preview_build_id into v_preview_build_id;
  insert into lws_internal.website_project_preview_build_artifacts (preview_build_id, relative_path, content_type, sha256, bytes)
  select v_preview_build_id, relative_path, content_type, sha256, bytes
  from lws_internal.website_project_preview_upload_files where session_token_hash = p_session_token_hash;
  update lws_internal.website_project_preview_build_leases set released_at = clock_timestamp() where preview_lease_id = p_lease_id;
  update lws_internal.website_project_preview_upload_sessions set status = 'FINALIZED', finalized_at = clock_timestamp()
  where session_token_hash = p_session_token_hash;
  return jsonb_build_object('previewBuildId', v_preview_build_id, 'buildStatus', v_session.build_status);
end;
$$;

revoke all on function
  public.open_website_project_preview_upload_session_v1(text,text,uuid,uuid,bigint,text,bigint,text,text,jsonb,integer),
  public.claim_website_project_preview_upload_file_v1(text,uuid,uuid,bigint,text,bigint,text,text,text,bigint),
  public.complete_website_project_preview_upload_file_v1(text,uuid,uuid,bigint,text,bigint,text),
  public.abort_website_project_preview_upload_session_v1(text,uuid,uuid,bigint,text,bigint),
  public.finalize_website_project_preview_upload_session_v1(text,uuid,uuid,bigint,text,bigint)
from public, anon, authenticated;
grant execute on function
  public.open_website_project_preview_upload_session_v1(text,text,uuid,uuid,bigint,text,bigint,text,text,jsonb,integer),
  public.claim_website_project_preview_upload_file_v1(text,uuid,uuid,bigint,text,bigint,text,text,text,bigint),
  public.complete_website_project_preview_upload_file_v1(text,uuid,uuid,bigint,text,bigint,text),
  public.abort_website_project_preview_upload_session_v1(text,uuid,uuid,bigint,text,bigint),
  public.finalize_website_project_preview_upload_session_v1(text,uuid,uuid,bigint,text,bigint)
to service_role;