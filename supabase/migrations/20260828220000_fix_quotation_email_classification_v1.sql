create or replace function public.get_quote_request_email_classification_v1(p_job_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(direct_request.record_classification, quotation_request.record_classification)
  from public.quote_request_email_jobs as job
  left join public.quote_requests as direct_request
    on direct_request.id = job.quote_request_id
  left join public.quote_request_quotation_email_orchestrations as orchestration
    on orchestration.email_job_id = job.id
  left join public.quote_request_quotation_issuances as issuance
    on issuance.id = orchestration.issuance_id
  left join public.quote_request_quotation_approvals as approval
    on approval.id = issuance.approval_id
  left join public.quote_requests as quotation_request
    on quotation_request.id = approval.quote_request_id
  where job.id = p_job_id
$$;

revoke all on function public.get_quote_request_email_classification_v1(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_quote_request_email_classification_v1(uuid)
to service_role;