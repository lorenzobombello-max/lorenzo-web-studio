-- Forward-only commercial customer preview-session redemption.
-- Edge supplies only SHA-256 digests; raw access and session tokens never enter PostgreSQL.

create or replace function public.redeem_customer_preview_access_v1(
  p_token_digest char(64),
  p_project_id uuid,
  p_session_digest char(64)
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_catalog
as $$
declare
  v_access public.preview_access%rowtype;
  v_session public.preview_sessions%rowtype;
begin
  if p_project_id is null
    or btrim(p_token_digest::text) !~ '^[0-9a-f]{64}$'
    or btrim(p_session_digest::text) !~ '^[0-9a-f]{64}$'
  then
    raise exception using errcode = '42501', message = 'ACCESS_DENIED';
  end if;

  select access.*
  into v_access
  from public.preview_access access
  where access.token_digest = p_token_digest
    and access.project_id = p_project_id
    and access.status = 'ACTIVE'
    and access.revoked_at is null
    and access.expires_at > clock_timestamp()
  for share;

  if not found then
    raise exception using errcode = '42501', message = 'ACCESS_DENIED';
  end if;

  if not exists (
    select 1
    from public.preview_versions version
    where version.preview_version_id = v_access.preview_version_id
      and version.project_id = p_project_id
      and version.status = 'CURRENT'
  ) then
    raise exception using errcode = 'P0001', message = 'PREVIEW_VERSION_MISMATCH';
  end if;

  insert into public.preview_sessions(
    preview_access_id,
    project_id,
    session_digest,
    expires_at
  ) values (
    v_access.preview_access_id,
    p_project_id,
    p_session_digest,
    least(v_access.expires_at, clock_timestamp() + interval '1 hour')
  )
  returning * into v_session;

  return jsonb_build_object(
    'project_id', v_session.project_id,
    'preview_access_id', v_session.preview_access_id,
    'preview_version_id', v_access.preview_version_id,
    'expires_at', v_session.expires_at
  );
end
$$;

revoke all on function public.redeem_customer_preview_access_v1(char,uuid,char)
from public, anon, authenticated, service_role;

grant execute on function public.redeem_customer_preview_access_v1(char,uuid,char)
to service_role;

comment on function public.redeem_customer_preview_access_v1(char,uuid,char) is
  'Service-role-only redemption of a hashed commercial preview access credential into a bounded hashed customer session.';
