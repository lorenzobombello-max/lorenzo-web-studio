alter function public.get_operator_application_v1(uuid, text)
  rename to get_operator_application_v1_pre_quotation_delivery;

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
  v_delivery_status public.quote_request_email_status;
begin
  v_result := public.get_operator_application_v1_pre_quotation_delivery(
    p_quote_request_id,
    p_application_reference
  );

  if jsonb_typeof(v_result->'quotation') <> 'object' then
    return v_result;
  end if;

  select job.status
  into v_delivery_status
  from public.quote_request_quotation_approvals as approval
  join public.quote_request_quotation_issuances as issuance
    on issuance.approval_id = approval.id
  join public.quote_request_quotation_email_orchestrations as orchestration
    on orchestration.issuance_id = issuance.id
   and orchestration.email_type = 'QUOTATION_DELIVERY'
  join public.quote_request_email_jobs as job
    on job.id = orchestration.email_job_id
  where approval.quote_request_id = (v_result->>'quote_request_id')::uuid
    and issuance.quotation_number = v_result->'quotation'->>'quotation_number'
    and issuance.quotation_version = (v_result->'quotation'->>'quotation_version')::integer
  order by orchestration.created_at desc, orchestration.id desc
  limit 1;

  return jsonb_set(
    v_result,
    '{quotation,delivery}',
    case when v_delivery_status is null then 'null'::jsonb else jsonb_build_object(
      'status', v_delivery_status::text,
      'retryable', v_delivery_status = 'retry_wait',
      'manual_review_required', v_delivery_status = 'failed'
    ) end,
    true
  );
end;
$$;

revoke all on function public.get_operator_application_v1_pre_quotation_delivery(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.get_operator_application_v1(uuid, text)
from public, anon, authenticated, service_role;

grant execute on function public.get_operator_application_v1(uuid, text)
to authenticated;

comment on function public.get_operator_application_v1(uuid, text) is
  'Owner/admin application detail with server-authoritative quotation delivery status semantics.';