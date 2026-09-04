create or replace function public.get_operator_dossier_facets_v2(
  p_actor_auth_user_id uuid,
  p_zone text default 'ACTIVE',
  p_operational_status text default null,
  p_request_kind text default null,
  p_search text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  if auth.uid() <> p_actor_auth_user_id then
    raise exception using errcode = '42501', message = 'OPERATOR_IDENTITY_MISMATCH';
  end if;
  return lws_internal.get_operator_dossier_facets_v2_core(
    p_actor_auth_user_id,
    p_zone,
    p_operational_status,
    p_request_kind,
    p_search
  );
end;
$$;

revoke all on function public.get_operator_dossier_facets_v2(uuid, text, text, text, text)
from public, anon, authenticated, service_role;
grant execute on function public.get_operator_dossier_facets_v2(uuid, text, text, text, text)
to authenticated;

comment on function public.get_operator_dossier_facets_v2(uuid, text, text, text, text) is
  'Authenticated read-only dossier-facets projection bound to the caller Auth UUID.';