-- GIT-001C: complete the async preview-build DB contract - finalize (v2,
-- multi-file), status polling, previewhost session issuance/resolution,
-- and expired-lease/orphaned-artifact cleanup. Purely additive: this does
-- NOT touch, replace, or remove finalize_website_project_preview_build_v1
-- or its existing, still-used synchronous single-file caller in
-- executeCallerJwtWebsiteProjectPreviewBuildAction
-- (supabase/functions/commercial-operator-command/index.ts). That
-- synchronous path continues to work exactly as before.

-- 1) finalize_website_project_preview_build_v2: accepts the async,
--    multi-file manifest produced by
--    website-project-preview-artifact-manifest.ts. build_status may be
--    PASS, PASS_WITH_WARNINGS, or FAILED (never BUILD_IN_PROGRESS - that
--    state exists implicitly between acquire and finalize, and is never
--    itself finalized to). p_primary_relative_path identifies which
--    manifest entry represents the build's entry document (e.g.
--    'index.html'); the parent row's legacy artifact_path/artifact_sha256
--    columns mirror that one entry for backward-compatible readers of
--    those columns, while artifact_bytes on the parent row is the
--    manifest's aggregate total (not just the primary entry) - the full,
--    authoritative per-file detail lives in
--    website_project_preview_build_artifacts.
create or replace function public.finalize_website_project_preview_build_v2(
  p_lease_id uuid,
  p_expected_commit_sha text,
  p_build_status text,
  p_primary_relative_path text,
  p_manifest jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_lease lws_internal.website_project_preview_build_leases%rowtype;
  v_build_id uuid;
  v_entry jsonb;
  v_total_bytes bigint := 0;
  v_primary_sha256 text;
  v_entry_count integer := 0;
  v_effective_primary_path text := p_primary_relative_path;
begin
  select lease.* into v_lease
  from lws_internal.website_project_preview_build_leases as lease
  where lease.preview_lease_id = p_lease_id
  for update;
  if not found or v_lease.actor_auth_user_id <> auth.uid()
    or v_lease.released_at is not null or v_lease.expires_at <= clock_timestamp()
    or v_lease.expected_commit_sha <> p_expected_commit_sha
  then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_LEASE_INVALID';
  end if;

  if p_build_status not in ('PASS', 'PASS_WITH_WARNINGS', 'FAILED') then
    raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_BUILD_STATUS_INVALID';
  end if;

  if p_build_status in ('PASS', 'PASS_WITH_WARNINGS') then
    if p_manifest is null or jsonb_typeof(p_manifest) <> 'array' or jsonb_array_length(p_manifest) < 1 then
      raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_MANIFEST_EMPTY';
    end if;
    if p_primary_relative_path is null or length(p_primary_relative_path) < 1 then
      raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_PRIMARY_PATH_REQUIRED';
    end if;

    for v_entry in select * from jsonb_array_elements(p_manifest)
    loop
      v_entry_count := v_entry_count + 1;
      if not (
        v_entry ? 'relative_path' and v_entry ? 'content_type'
        and v_entry ? 'sha256' and v_entry ? 'bytes'
      ) then
        raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_MANIFEST_ENTRY_INVALID';
      end if;
      if (v_entry->>'relative_path') !~ '^[A-Za-z0-9._/-]+$'
        or length(v_entry->>'relative_path') > 1024
        or (v_entry->>'relative_path') like '%..%'
        or left(v_entry->>'relative_path', 1) = '/'
      then
        raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_MANIFEST_PATH_INVALID';
      end if;
      if (v_entry->>'sha256') !~ '^[0-9a-f]{64}$' then
        raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_MANIFEST_HASH_INVALID';
      end if;
      if (v_entry->>'bytes')::bigint < 0 or (v_entry->>'bytes')::bigint > 5242880 then
        raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_MANIFEST_SIZE_INVALID';
      end if;
      v_total_bytes := v_total_bytes + (v_entry->>'bytes')::bigint;
      if v_entry->>'relative_path' = p_primary_relative_path then
        v_primary_sha256 := v_entry->>'sha256';
      end if;
    end loop;

    if v_entry_count > 500 then
      raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_MANIFEST_TOO_MANY_FILES';
    end if;
    if v_total_bytes > 52428800 then
      raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_MANIFEST_TOTAL_TOO_LARGE';
    end if;
    if v_primary_sha256 is null then
      raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_PRIMARY_PATH_NOT_IN_MANIFEST';
    end if;
  else
    -- FAILED: no manifest/primary path is trusted or required; the
    -- legacy not-null columns are populated with fixed, inert sentinels.
    v_total_bytes := 0;
    v_primary_sha256 := repeat('0', 64);
    v_effective_primary_path := coalesce(p_primary_relative_path, 'FAILED');
  end if;

  insert into lws_internal.website_project_preview_builds (
    preview_build_id, lease_id, actor_auth_user_id, quote_request_id,
    website_work_context_id, website_workspace_id, commit_sha,
    artifact_path, artifact_sha256, artifact_bytes, build_status
  ) values (
    gen_random_uuid(), p_lease_id, v_lease.actor_auth_user_id, v_lease.quote_request_id,
    v_lease.website_work_context_id, v_lease.website_workspace_id, p_expected_commit_sha,
    v_effective_primary_path, v_primary_sha256, v_total_bytes, p_build_status
  )
  returning preview_build_id into v_build_id;

  if p_build_status in ('PASS', 'PASS_WITH_WARNINGS') then
    insert into lws_internal.website_project_preview_build_artifacts (
      preview_build_id, relative_path, content_type, sha256, bytes
    )
    select
      v_build_id,
      entry->>'relative_path',
      entry->>'content_type',
      entry->>'sha256',
      (entry->>'bytes')::bigint
    from jsonb_array_elements(p_manifest) as entry;
  end if;

  update lws_internal.website_project_preview_build_leases
  set released_at = clock_timestamp()
  where preview_lease_id = p_lease_id;

  return jsonb_build_object(
    'previewBuildId', v_build_id,
    'buildStatus', p_build_status
  );
end;
$$;

revoke all on function
  public.finalize_website_project_preview_build_v2(uuid, text, text, text, jsonb)
from public, anon;
grant execute on function
  public.finalize_website_project_preview_build_v2(uuid, text, text, text, jsonb)
to authenticated;

-- 2) Status polling for the frontend progress button. Distinguishes
--    "still building" from "lease expired without ever finalizing" so a
--    stuck/timed-out pipeline surfaces a fail-closed status rather than
--    an indefinitely-spinning UI.
create or replace function public.get_website_project_preview_build_status_v1(
  p_lease_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_lease lws_internal.website_project_preview_build_leases%rowtype;
  v_build lws_internal.website_project_preview_builds%rowtype;
begin
  select lease.* into v_lease
  from lws_internal.website_project_preview_build_leases as lease
  where lease.preview_lease_id = p_lease_id
    and lease.actor_auth_user_id = auth.uid();
  if not found then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_LEASE_INVALID';
  end if;

  select build.* into v_build
  from lws_internal.website_project_preview_builds as build
  where build.lease_id = p_lease_id;

  if not found then
    if v_lease.expires_at <= clock_timestamp() then
      return jsonb_build_object(
        'buildStatus', 'FAILED', 'previewBuildId', null, 'reason', 'LEASE_EXPIRED'
      );
    end if;
    return jsonb_build_object('buildStatus', 'BUILD_IN_PROGRESS', 'previewBuildId', null);
  end if;

  return jsonb_build_object(
    'buildStatus', v_build.build_status,
    'previewBuildId', v_build.preview_build_id
  );
end;
$$;

revoke all on function public.get_website_project_preview_build_status_v1(uuid) from public, anon;
grant execute on function public.get_website_project_preview_build_status_v1(uuid) to authenticated;

-- 3) Previewhost session issuance. Caller-JWT-authorized (the operator
--    who owns the lease/build); only ever stores a hash of the session
--    token, never the token itself (checkpoint §14.2).
create or replace function public.create_website_project_preview_session_v1(
  p_preview_build_id uuid,
  p_session_token_hash text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_build lws_internal.website_project_preview_builds%rowtype;
  v_session lws_internal.website_project_preview_sessions%rowtype;
begin
  select build.* into v_build
  from lws_internal.website_project_preview_builds as build
  where build.preview_build_id = p_preview_build_id
    and build.actor_auth_user_id = auth.uid()
    and build.build_status in ('PASS', 'PASS_WITH_WARNINGS');
  if not found then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_BUILD_NOT_READY';
  end if;
  if p_session_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_SESSION_TOKEN_INVALID';
  end if;

  insert into lws_internal.website_project_preview_sessions (
    preview_build_id, session_token_hash, actor_auth_user_id, expires_at
  ) values (
    p_preview_build_id, p_session_token_hash, auth.uid(), clock_timestamp() + interval '30 minutes'
  )
  returning * into v_session;

  return jsonb_build_object(
    'previewSessionId', v_session.preview_session_id,
    'expiresAt', v_session.expires_at
  );
end;
$$;

revoke all on function
  public.create_website_project_preview_session_v1(uuid, text)
from public, anon;
grant execute on function
  public.create_website_project_preview_session_v1(uuid, text)
to authenticated;

-- 4) Previewhost session resolution: called by the (not-yet-hosted)
--    serving layer's own trusted backend credential, never with a
--    caller JWT - validates a raw session-token hash against the stored
--    hash and returns exactly the artifact manifest needed to serve
--    assets for that one build. Deliberately revoked from
--    public/anon/authenticated; executable only as service_role.
create or replace function public.resolve_website_project_preview_session_v1(
  p_session_token_hash text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_session lws_internal.website_project_preview_sessions%rowtype;
  v_artifacts jsonb;
begin
  select session.* into v_session
  from lws_internal.website_project_preview_sessions as session
  where session.session_token_hash = p_session_token_hash
    and session.revoked_at is null
    and session.expires_at > clock_timestamp();
  if not found then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_SESSION_INVALID';
  end if;

  select jsonb_agg(jsonb_build_object(
    'relativePath', artifact.relative_path,
    'contentType', artifact.content_type,
    'sha256', artifact.sha256,
    'bytes', artifact.bytes
  )) into v_artifacts
  from lws_internal.website_project_preview_build_artifacts as artifact
  where artifact.preview_build_id = v_session.preview_build_id;

  return jsonb_build_object(
    'previewBuildId', v_session.preview_build_id,
    'artifacts', coalesce(v_artifacts, '[]'::jsonb)
  );
end;
$$;

revoke all on function
  public.resolve_website_project_preview_session_v1(text)
from public, anon, authenticated;
grant execute on function
  public.resolve_website_project_preview_session_v1(text)
to service_role;

-- 5) Cleanup: releases leases that expired without ever being finalized,
--    revokes previewhost sessions for builds past the 24-hour artifact
--    retention window (checkpoint §14.2/§14.3), and deletes their
--    now-orphaned artifact manifest rows. Intended to be invoked
--    periodically (e.g. via pg_cron or an equivalent scheduled worker -
--    the exact scheduling mechanism remains checkpoint §16.6 item U6,
--    not decided here); this migration only provides the idempotent,
--    safely re-runnable SQL logic itself.
create or replace function public.sweep_expired_website_project_preview_artifacts_v1(
  p_retention_hours integer default 24
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
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

  update lws_internal.website_project_preview_sessions as session
  set revoked_at = clock_timestamp()
  where session.revoked_at is null
    and session.preview_build_id in (
      select build.preview_build_id
      from lws_internal.website_project_preview_builds as build
      where build.built_at <= clock_timestamp() - make_interval(hours => p_retention_hours)
    );
  get diagnostics v_expired_session_count = row_count;

  with expired_builds as (
    select build.preview_build_id
    from lws_internal.website_project_preview_builds as build
    where build.built_at <= clock_timestamp() - make_interval(hours => p_retention_hours)
  )
  delete from lws_internal.website_project_preview_build_artifacts as artifact
  using expired_builds
  where artifact.preview_build_id = expired_builds.preview_build_id;
  get diagnostics v_deleted_artifact_count = row_count;

  return jsonb_build_object(
    'expiredLeasesReleased', v_expired_lease_count,
    'expiredSessionsRevoked', v_expired_session_count,
    'orphanedArtifactRowsDeleted', v_deleted_artifact_count
  );
end;
$$;

revoke all on function
  public.sweep_expired_website_project_preview_artifacts_v1(integer)
from public, anon, authenticated;
grant execute on function
  public.sweep_expired_website_project_preview_artifacts_v1(integer)
to service_role;

-- 6) Missing index: the preview_build_id foreign key on
--    website_project_preview_sessions had no supporting index (Postgres
--    does not create one automatically for FK columns), which the
--    cleanup sweep above and any future per-build session listing would
--    otherwise have to sequential-scan for.
create index if not exists website_project_preview_sessions_build_id_idx
  on lws_internal.website_project_preview_sessions (preview_build_id);
