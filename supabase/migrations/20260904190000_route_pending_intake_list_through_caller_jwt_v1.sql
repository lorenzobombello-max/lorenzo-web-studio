create or replace function public.list_operator_pending_intakes_v1(
  p_actor_auth_user_id uuid,
  p_retention_state text default 'ACTIVE'
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
  return lws_internal.project_operator_dossier_seen_v1(
    public.list_operator_pending_intakes_v1_pre_dos_r1_current_seen(
      p_actor_auth_user_id,
      p_retention_state
    ),
    p_actor_auth_user_id
  );
end;
$$;

revoke all on function public.list_operator_pending_intakes_v1(uuid, text)
from public, anon, authenticated, service_role;
grant execute on function public.list_operator_pending_intakes_v1(uuid, text)
to authenticated;

comment on function public.list_operator_pending_intakes_v1(uuid, text) is
  'Authenticated read-only pending-intake projection bound to the caller Auth UUID.';