create function public.get_operator_trashed_website_intake_detail_v1(
  p_actor_auth_user_id uuid,
  p_support_reference text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_reference text;
  v_request public.quote_requests%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_state lws_internal.operator_dossier_states%rowtype;
begin
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = p_actor_auth_user_id;
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
  if v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'APPLICATION_SCOPE_DENIED';
  end if;

  v_reference := public.normalize_quote_request_support_reference_v1(p_support_reference);

  select * into v_request
  from public.quote_requests
  where support_reference = v_reference
    and record_classification = 'production'
    and request_kind = 'website';
  if not found then
    raise exception using errcode = 'P0001', message = 'APPLICATION_NOT_FOUND';
  end if;

  select * into v_state
  from lws_internal.operator_dossier_states
  where quote_request_id = v_request.id
    and state = 'TRASHED';
  if not found then
    raise exception using errcode = 'P0001', message = 'APPLICATION_NOT_FOUND';
  end if;

  select * into v_intake
  from public.quote_request_intakes
  where quote_request_id = v_request.id
    and status in ('invited', 'in_progress');
  if not found then
    raise exception using errcode = 'P0001', message = 'APPLICATION_NOT_FOUND';
  end if;

  return jsonb_build_object(
    'quote_request_id', v_request.id,
    'application_reference', v_request.application_reference,
    'support_reference', v_request.support_reference,
    'name', v_request.name,
    'company', v_request.company,
    'email', v_request.email,
    'phone', v_request.phone,
    'website_type', v_request.website_type,
    'budget', v_request.budget,
    'timing', v_request.timing,
    'description', v_request.description,
    'request_kind', v_request.request_kind,
    'intake_status', v_intake.status,
    'operational_status', upper(v_intake.status::text),
    'submitted_at', v_intake.submitted_at,
    'acceptance', null,
    'project', null,
    'project_site', null,
    'dossier_lifecycle', jsonb_build_object(
      'state', v_state.state,
      'revision', v_state.revision
    )
  );
end;
$$;

revoke all on function public.get_operator_trashed_website_intake_detail_v1(uuid, text)
from public, anon, authenticated, service_role;
grant execute on function public.get_operator_trashed_website_intake_detail_v1(uuid, text)
to service_role;

comment on function public.get_operator_trashed_website_intake_detail_v1(uuid, text) is
  'Service-role Edge fallback for owner/admin reads of canonical TRASHED Website intakes in invited or in_progress state.';