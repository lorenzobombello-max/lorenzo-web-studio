alter table lws_internal.website_project_preview_sessions
  add column handoff_consumed_at timestamptz;

create function public.consume_website_project_preview_handoff_v1(
  p_handoff_token_hash text,
  p_viewer_session_token_hash text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_session lws_internal.website_project_preview_sessions%rowtype;
begin
  if coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_HANDOFF_FORBIDDEN';
  end if;
  if p_handoff_token_hash !~ '^[0-9a-f]{64}$'
    or p_viewer_session_token_hash !~ '^[0-9a-f]{64}$'
    or p_handoff_token_hash = p_viewer_session_token_hash
  then
    raise exception using errcode = '22023', message = 'PROJECT_PREVIEW_HANDOFF_TOKEN_INVALID';
  end if;

  update lws_internal.website_project_preview_sessions
  set session_token_hash = p_viewer_session_token_hash,
      handoff_consumed_at = clock_timestamp()
  where session_token_hash = p_handoff_token_hash
    and handoff_consumed_at is null
    and revoked_at is null
    and expires_at > clock_timestamp()
  returning * into v_session;

  if not found then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_HANDOFF_INVALID';
  end if;
  return jsonb_build_object(
    'previewSessionId', v_session.preview_session_id,
    'expiresAt', v_session.expires_at
  );
end;
$$;

revoke all on function public.consume_website_project_preview_handoff_v1(text, text)
from public, anon, authenticated;
grant execute on function public.consume_website_project_preview_handoff_v1(text, text)
to service_role;

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
  if coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'PROJECT_PREVIEW_SESSION_FORBIDDEN';
  end if;
  select session.* into v_session
  from lws_internal.website_project_preview_sessions as session
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
  where artifact.preview_build_id = v_session.preview_build_id;

  return jsonb_build_object(
    'previewBuildId', v_session.preview_build_id,
    'artifacts', coalesce(v_artifacts, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.resolve_website_project_preview_session_v1(text)
from public, anon, authenticated;
grant execute on function public.resolve_website_project_preview_session_v1(text)
to service_role;
