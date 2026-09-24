-- The upload authority writes private objects below authorized_build_id before
-- finalization creates the distinct preview_build_id. Resolve that immutable,
-- server-bound storage prefix through session -> build -> lease.
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
  v_preview_build_id uuid;
  v_storage_build_id uuid;
  v_artifacts jsonb;
begin
  if coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_SESSION_FORBIDDEN';
  end if;

  select session.preview_build_id, lease.authorized_build_id
  into v_preview_build_id, v_storage_build_id
  from lws_internal.website_project_preview_sessions as session
  join lws_internal.website_project_preview_builds as build
    on build.preview_build_id = session.preview_build_id
  join lws_internal.website_project_preview_build_leases as lease
    on lease.preview_lease_id = build.lease_id
  where session.session_token_hash = p_session_token_hash
    and session.handoff_consumed_at is not null
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
  ) order by artifact.relative_path) into v_artifacts
  from lws_internal.website_project_preview_build_artifacts as artifact
  where artifact.preview_build_id = v_preview_build_id;

  return jsonb_build_object(
    'previewBuildId', v_preview_build_id,
    'storageBuildId', v_storage_build_id,
    'artifacts', coalesce(v_artifacts, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.resolve_website_project_preview_session_v1(text)
from public, anon, authenticated;
grant execute on function public.resolve_website_project_preview_session_v1(text)
to service_role;