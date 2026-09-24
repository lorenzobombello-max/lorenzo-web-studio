-- GIT-001C: extend the preview-build lease/status contract for asynchronous,
-- multi-file builds (see checkpoint 009-git001c-astro-preview-build-plan.md
-- §14/§16). LOCAL-ONLY at authoring time: this migration is written to be
-- applied first against an isolated local Supabase instance, never directly
-- against production. It only touches the preview-build-specific schema
-- introduced in 20260920120000_add_website_project_files_write_authority_v1.sql;
-- it does not alter the general-purpose
-- website_project_files_write_leases/reads tables used by the synchronous
-- file read/write paths.

-- 1) Preview-build leases previously inherited their expiry from the
--    general-purpose 30-second file-write lease. A real async build
--    (fetch -> build -> upload -> finalize) needs its own, longer-lived
--    envelope (20 minutes, per the fase-gewogen begroting in checkpoint
--    §11/§14.3), independent of - and never widening - the unrelated,
--    still-30-second general file-write lease used elsewhere.
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
    'expiresAt', v_preview.expires_at
  );
end;
$$;

-- 2) build_status must allow an in-progress/asynchronous lifecycle and a
--    non-fatal "completed with blocked assets" status - see checkpoint
--    §14.3: a preview build with one or more rejected assets (e.g. blocked
--    SVGs) must never be reported as an unqualified PASS.
alter table lws_internal.website_project_preview_builds
  drop constraint if exists website_project_preview_builds_build_status_check;
alter table lws_internal.website_project_preview_builds
  add constraint website_project_preview_builds_build_status_check
  check (build_status in ('BUILD_IN_PROGRESS', 'PASS', 'PASS_WITH_WARNINGS', 'FAILED'));

-- 3) artifact_bytes previously bounded a single HTML file (<=1 MiB). A
--    multi-file static build needs the aggregate ceiling from checkpoint
--    §11 (50 MiB per build); per-file limits (5 MiB) are enforced by the
--    manifest validator (website-project-preview-artifact-manifest.ts),
--    not by this column.
alter table lws_internal.website_project_preview_builds
  drop constraint if exists website_project_preview_builds_artifact_bytes_check;
alter table lws_internal.website_project_preview_builds
  add constraint website_project_preview_builds_artifact_bytes_check
  check (artifact_bytes between 0 and 52428800);

-- 4) One row per accepted file in a build's manifest (path, hash, size).
--    Superset of the single `artifact_path`/`artifact_sha256` columns
--    above, which remain as the build's primary/entry document for
--    backward compatibility with the existing single-file contract.
create table lws_internal.website_project_preview_build_artifacts (
  artifact_id uuid primary key default gen_random_uuid(),
  preview_build_id uuid not null
    references lws_internal.website_project_preview_builds(preview_build_id)
    on delete cascade,
  relative_path text not null check (length(relative_path) between 1 and 1024),
  content_type text not null check (length(content_type) between 1 and 255),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  bytes bigint not null check (bytes between 0 and 5242880),
  created_at timestamptz not null default clock_timestamp(),
  unique (preview_build_id, relative_path)
);

alter table lws_internal.website_project_preview_build_artifacts enable row level security;
alter table lws_internal.website_project_preview_build_artifacts force row level security;
revoke all on table lws_internal.website_project_preview_build_artifacts
from public, anon, authenticated, service_role;

-- 5) Previewhost session: maps a server-issued, opaque session identifier
--    to exactly one build, with its own kijksessie-TTL (30 minutes,
--    checkpoint §14.2) - deliberately independent of the build-lease TTL
--    above and of the 24-hour artifact-retention window (also §14.2).
--    Only a hash of the session token is stored, never the token itself.
create table lws_internal.website_project_preview_sessions (
  preview_session_id uuid primary key default gen_random_uuid(),
  preview_build_id uuid not null
    references lws_internal.website_project_preview_builds(preview_build_id)
    on delete cascade,
  session_token_hash text not null unique check (session_token_hash ~ '^[0-9a-f]{64}$'),
  actor_auth_user_id uuid not null,
  issued_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  revoked_at timestamptz
);

alter table lws_internal.website_project_preview_sessions enable row level security;
alter table lws_internal.website_project_preview_sessions force row level security;
revoke all on table lws_internal.website_project_preview_sessions
from public, anon, authenticated, service_role;

comment on table lws_internal.website_project_preview_build_artifacts is
  'GIT-001C: per-file manifest entries for an asynchronous, multi-file preview build. Populated by a not-yet-implemented finalize RPC rewrite (see checkpoint §16.3) - schema only at this stage.';
comment on table lws_internal.website_project_preview_sessions is
  'GIT-001C: previewhost session -> build binding for the host-only, SameSite=Lax cookie flow (checkpoint §14.2). No serving Edge Function exists yet - schema only at this stage, pending the hosting-route decision (checkpoint §16.6 U1).';
