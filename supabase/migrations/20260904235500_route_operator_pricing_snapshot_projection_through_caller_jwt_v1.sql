create function public.get_operator_submitted_application_pricing_snapshot_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid,
  p_intake_id uuid
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
    'id', snapshot.id,
    'intake_id', snapshot.intake_id,
    'snapshot_contract_version', snapshot.snapshot_contract_version,
    'config_version', snapshot.config_version,
    'config_hash', snapshot.config_hash,
    'normalized_evidence', snapshot.normalized_evidence,
    'calculation', snapshot.calculation,
    'package_advice', snapshot.package_advice,
    'budget_evaluation', snapshot.budget_evaluation,
    'package_definition', snapshot.package_definition,
    'recurring_services', snapshot.recurring_services
  )
  into v_result
  from public.quote_request_pricing_snapshots as snapshot
  inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id
  inner join public.quote_requests as request on request.id = intake.quote_request_id
  where snapshot.intake_id = p_intake_id
    and intake.id = p_intake_id
    and intake.quote_request_id = p_quote_request_id
    and intake.status in ('submitted', 'reviewed')
    and request.id = p_quote_request_id
    and request.record_classification in ('production', 'internal_e2e')
    and request.request_kind = 'website';

  return v_result;
end;
$$;

revoke all on function public.get_operator_submitted_application_pricing_snapshot_v1(uuid, uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_operator_submitted_application_pricing_snapshot_v1(uuid, uuid, uuid)
to authenticated;

comment on function public.get_operator_submitted_application_pricing_snapshot_v1(uuid, uuid, uuid) is
  'Authenticated owner/admin submitted Website pricing snapshot projection bound to caller, request, and intake.';