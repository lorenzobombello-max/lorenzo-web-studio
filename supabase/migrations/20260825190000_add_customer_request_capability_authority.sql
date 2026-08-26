create function public.resolve_customer_request_authorization_v1(
  p_request_id uuid,
  p_action text
)
returns table(operator_id uuid, operator_role text, audit_actor text)
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_request public.customer_requests%rowtype;
  v_allowed boolean := false;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject
  for share;

  if not found then
    raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR';
  end if;
  if v_operator.status = 'DISABLED' then
    raise exception using errcode = '42501', message = 'OPERATOR_DISABLED';
  end if;
  if v_operator.status = 'REVOKED' then
    raise exception using errcode = '42501', message = 'OPERATOR_REVOKED';
  end if;
  if v_operator.status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;
  if p_action is null or p_action not in ('VIEW', 'TRIAGE', 'WORK', 'TRANSITION') then
    raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST_ACTION';
  end if;

  select * into v_request
  from public.customer_requests
  where request_id = p_request_id
  for share;

  if not found then
    raise exception using errcode = '42501', message = 'CUSTOMER_REQUEST_ACCESS_DENIED';
  end if;

  if v_operator.role in ('owner', 'operations_manager') then
    v_allowed := true;
  elsif v_operator.role = 'operator' and p_action in ('VIEW', 'WORK') then
    select true into v_allowed
    from lws_internal.operator_dossier_assignments as assignment
    where assignment.quote_request_id = v_request.quote_request_id
      and assignment.assignee_operator_id = v_operator.operator_id
    for share;
  elsif v_operator.role = 'reviewer' and p_action = 'VIEW' then
    select true into v_allowed
    from public.commercial_operator_project_grants as project_grant
    where project_grant.operator_id = v_operator.operator_id
      and project_grant.project_id = v_request.project_id
      and project_grant.access_level in ('operator', 'reviewer')
      and project_grant.revoked_at is null
    for share;
  elsif v_operator.role = 'read_only' and p_action = 'VIEW' then
    select true into v_allowed
    from public.commercial_operator_project_grants as project_grant
    where project_grant.operator_id = v_operator.operator_id
      and project_grant.project_id = v_request.project_id
      and project_grant.access_level in ('operator', 'reviewer', 'read_only')
      and project_grant.revoked_at is null
    for share;
  end if;

  if not coalesce(v_allowed, false) then
    raise exception using errcode = '42501', message = 'CUSTOMER_REQUEST_ACCESS_DENIED';
  end if;

  return query
  select
    v_operator.operator_id,
    v_operator.role,
    'OPERATOR:' || v_operator.operator_id::text;
end;
$$;

create function public.get_customer_request_v1(p_request_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_authorization record;
  v_result jsonb;
begin
  select * into strict v_authorization
  from public.resolve_customer_request_authorization_v1(p_request_id, 'VIEW');

  select jsonb_build_object(
    'request_id', request.request_id,
    'request_reference', request.request_reference,
    'source', request.source,
    'request_type', request.request_type,
    'title', request.title,
    'description', request.description,
    'status', request.status,
    'priority', request.priority,
    'submitted_at', request.submitted_at,
    'revision', request.revision,
    'updated_at', request.updated_at
  ) into strict v_result
  from public.customer_requests as request
  where request.request_id = p_request_id;

  return v_result;
end;
$$;

create function public.transition_customer_request_v1(
  p_request_id uuid,
  p_command_type text,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_authorization record;
  v_action text;
begin
  v_action := case
    when p_command_type = 'TRIAGE' then 'TRIAGE'
    when p_command_type in ('START', 'REQUIRE_CUSTOMER_RESPONSE', 'RESUME') then 'WORK'
    else 'TRANSITION'
  end;

  select * into strict v_authorization
  from public.resolve_customer_request_authorization_v1(p_request_id, v_action);

  return lws_internal.transition_customer_request_core_v1(
    p_request_id,
    p_command_type,
    p_expected_revision,
    p_idempotency_key,
    p_payload
  );
end;
$$;

revoke all on function public.resolve_customer_request_authorization_v1(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.get_customer_request_v1(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.transition_customer_request_v1(uuid, text, bigint, uuid, jsonb)
from public, anon, authenticated, service_role;

grant execute on function public.get_customer_request_v1(uuid)
to authenticated;
grant execute on function public.transition_customer_request_v1(uuid, text, bigint, uuid, jsonb)
to authenticated;

comment on function public.resolve_customer_request_authorization_v1(uuid, text) is
  'Server-derived ACTIVE operator authorization for one Customer Request and the fixed VIEW, TRIAGE, WORK, or TRANSITION action family.';
comment on function public.get_customer_request_v1(uuid) is
  'Minimal authenticated Customer Request projection after request-scoped VIEW authorization.';
comment on function public.transition_customer_request_v1(uuid, text, bigint, uuid, jsonb) is
  'Authenticated Customer Request transition boundary; authorization precedes the existing private revision-guarded core.';