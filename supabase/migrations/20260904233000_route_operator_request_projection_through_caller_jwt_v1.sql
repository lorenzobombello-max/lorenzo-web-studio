create function public.get_operator_submitted_application_request_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  if auth.uid() <> p_actor_auth_user_id then
    raise exception using errcode = '42501', message = 'OPERATOR_IDENTITY_MISMATCH';
  end if;

  perform lws_internal.assert_operator_application_actor_v2(p_actor_auth_user_id);

  select jsonb_build_object(
    'id', request.id,
    'record_classification', request.record_classification,
    'application_reference', request.application_reference,
    'name', request.name,
    'company', request.company,
    'email', request.email,
    'phone', request.phone,
    'website_type', request.website_type,
    'budget', request.budget,
    'timing', request.timing
  )
  into v_result
  from public.quote_requests as request
  where request.id = p_quote_request_id
    and request.record_classification in ('production', 'internal_e2e')
    and request.request_kind = 'website';

  return v_result;
end;
$$;

revoke all on function public.get_operator_submitted_application_request_v1(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_operator_submitted_application_request_v1(uuid, uuid)
to authenticated;

comment on function public.get_operator_submitted_application_request_v1(uuid, uuid) is
  'Authenticated owner/admin Website request projection bound to the caller Auth UUID.';