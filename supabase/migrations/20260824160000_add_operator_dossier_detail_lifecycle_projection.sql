alter function public.get_operator_application_v1(uuid, text)
  rename to get_operator_application_v1_pre_dossier_lifecycle_detail;

create function public.get_operator_application_v1(
  p_quote_request_id uuid default null,
  p_application_reference text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_result jsonb;
  v_quote_request_id uuid;
  v_state text;
  v_revision bigint;
begin
  v_result := public.get_operator_application_v1_pre_dossier_lifecycle_detail(
    p_quote_request_id,
    p_application_reference
  );
  v_quote_request_id := nullif(v_result->>'quote_request_id', '')::uuid;

  select state.state, state.revision
  into v_state, v_revision
  from lws_internal.operator_dossier_states as state
  where state.quote_request_id = v_quote_request_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'OPERATOR_DOSSIER_STATE_REQUIRED';
  end if;
  if v_state not in ('ACTIVE', 'ARCHIVED', 'TRASHED')
     or v_revision is null
     or v_revision < 0 then
    raise exception using errcode = '23514', message = 'INVALID_OPERATOR_DOSSIER_STATE_PROJECTION';
  end if;

  return v_result || jsonb_build_object(
    'dossier_lifecycle', jsonb_build_object(
      'state', v_state,
      'revision', v_revision
    )
  );
end;
$$;

revoke all on function public.get_operator_application_v1_pre_dossier_lifecycle_detail(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.get_operator_application_v1(uuid, text)
from public, anon, authenticated, service_role;

grant execute on function public.get_operator_application_v1(uuid, text)
to authenticated;

comment on function public.get_operator_application_v1(uuid, text) is
  'Owner/admin application detail with minimal authoritative dossier lifecycle state and revision projection.';
