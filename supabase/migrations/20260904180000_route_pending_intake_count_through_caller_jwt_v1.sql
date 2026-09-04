create or replace function public.count_operator_active_pending_intakes_v1(
  p_actor_auth_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = lws_internal, public, auth, pg_catalog
as $$
declare
  v_count bigint;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  if auth.uid() <> p_actor_auth_user_id then
    raise exception using errcode = '42501', message = 'OPERATOR_IDENTITY_MISMATCH';
  end if;
  perform lws_internal.assert_operator_application_actor_v2(p_actor_auth_user_id);
  select count(*) into v_count
  from lws_internal.operator_pending_intakes_v1
  where retention_state = 'ACTIVE';
  return jsonb_build_object('active_count', v_count);
end;
$$;

revoke all on function public.count_operator_active_pending_intakes_v1(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.count_operator_active_pending_intakes_v1(uuid)
to authenticated;

comment on function public.count_operator_active_pending_intakes_v1(uuid) is
  'Authenticated read-only active pending-intake count bound to the caller Auth UUID.';