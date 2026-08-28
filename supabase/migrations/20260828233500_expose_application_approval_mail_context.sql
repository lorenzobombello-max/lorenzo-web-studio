drop function public.execute_application_intake_automation_approval_v1(bigint, uuid);

create function public.execute_application_intake_automation_approval_v1(
  p_work_id bigint,
  p_claim_token uuid
)
returns table (
  outcome text,
  confirmation_job_id uuid,
  request_name text,
  request_email text,
  reviewed_at timestamptz,
  created_at timestamptz,
  website_type text
)
language plpgsql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_quote_request_id uuid;
  v_work lws_internal.application_intake_automation_work%rowtype;
  v_request public.quote_requests%rowtype;
  v_config lws_internal.application_intake_automation_config%rowtype;
  v_transition record;
  v_now timestamptz;
begin
  select automation_work.quote_request_id into v_quote_request_id
  from lws_internal.application_intake_automation_work as automation_work
  where automation_work.work_id = p_work_id;

  if not found then
    return;
  end if;

  select request.* into v_request
  from public.quote_requests as request
  where request.id = v_quote_request_id
  for update;

  if not found then
    return;
  end if;

  select automation_work.* into v_work
  from lws_internal.application_intake_automation_work as automation_work
  where automation_work.work_id = p_work_id
    and automation_work.quote_request_id = v_request.id
  for update;

  if not found then
    return;
  end if;

  select config.* into v_config
  from lws_internal.application_intake_automation_config as config
  where config.singleton;

  v_now := clock_timestamp();
  if not v_config.active
     or v_config.cutover_at is null
     or v_request.created_at < v_config.cutover_at
     or v_request.record_classification is distinct from 'production'
     or v_request.request_kind is distinct from 'website'
     or v_request.status is distinct from 'pending'::public.quote_request_status
     or v_request.approval_token_hash is null
     or v_request.approval_token_expires_at is null
     or v_request.approval_token_expires_at <= v_now
     or v_work.phase is distinct from 'APPROVAL'
     or v_work.approval_due_at > v_now
     or v_work.approved_at is not null
     or v_work.intake_due_at is not null
     or v_work.claim_token is distinct from p_claim_token
     or v_work.claim_expires_at is null
     or v_work.claim_expires_at <= v_now then
    return;
  end if;

  select transition.* into v_transition
  from public.transition_quote_request_review(
    v_request.approval_token_hash,
    'approved'
  ) as transition;

  if not found
     or v_transition.request_id is distinct from v_request.id
     or v_transition.review_status is distinct from 'approved'
     or v_transition.reviewed_at is null
     or v_transition.confirmation_job_id is null then
    return;
  end if;

  update lws_internal.application_intake_automation_work as automation_work
  set phase = 'INTAKE',
      approved_at = v_transition.reviewed_at,
      intake_due_at = v_transition.reviewed_at + interval '120 seconds',
      attempt_count = 0,
      next_attempt_at = v_transition.reviewed_at + interval '120 seconds',
      claim_token = null,
      claimed_by = null,
      claimed_at = null,
      claim_expires_at = null,
      last_error_code = null,
      terminal_reason = null
  where automation_work.work_id = v_work.work_id
    and automation_work.quote_request_id = v_request.id;

  return query select
    'approval_completed'::text,
    v_transition.confirmation_job_id::uuid,
    v_transition.request_name::text,
    v_transition.request_email::text,
    v_transition.reviewed_at::timestamptz,
    v_request.created_at::timestamptz,
    v_request.website_type::text;
end;
$$;

alter function public.execute_application_intake_automation_approval_v1(bigint, uuid)
  owner to postgres;
revoke all on function public.execute_application_intake_automation_approval_v1(bigint, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.execute_application_intake_automation_approval_v1(bigint, uuid)
  to service_role;