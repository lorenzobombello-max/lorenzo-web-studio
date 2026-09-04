alter function public.get_operator_dossier_substance_v1(uuid, uuid)
  set schema lws_internal;

alter function lws_internal.get_operator_dossier_substance_v1(uuid, uuid)
  rename to get_operator_dossier_substance_v1_core;

revoke all on function lws_internal.get_operator_dossier_substance_v1_core(uuid, uuid)
from public, anon, authenticated, service_role;

create function public.get_operator_dossier_substance_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = lws_internal, public, auth, pg_catalog
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  if auth.uid() <> p_actor_auth_user_id then
    raise exception using errcode = '42501', message = 'OPERATOR_IDENTITY_MISMATCH';
  end if;
  return lws_internal.get_operator_dossier_substance_v1_core(
    p_actor_auth_user_id,
    p_quote_request_id
  );
end;
$$;

revoke all on function public.get_operator_dossier_substance_v1(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_operator_dossier_substance_v1(uuid, uuid)
to authenticated;

comment on function public.get_operator_dossier_substance_v1(uuid, uuid) is
  'Authenticated read-only dossier-substance projection bound to the caller Auth UUID.';