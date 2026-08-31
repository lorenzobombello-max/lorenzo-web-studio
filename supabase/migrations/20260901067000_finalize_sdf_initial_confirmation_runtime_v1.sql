create function lws_internal.assert_sdf_initial_confirmation_runtime_finalizable_v1()
returns void
language plpgsql
stable
security definer
set search_path = lws_internal, public, pg_catalog
as $$
begin
  if exists (
    select 1
    from public.quote_request_email_jobs as legacy
    join public.quote_requests as request
      on request.id = legacy.quote_request_id
    where request.record_classification = 'production'
      and request.request_kind = 'slimme_documentenflow'
      and legacy.kind = 'customer_confirmation'
      and legacy.template_key = 'SDF_REQUEST_RECEIVED_NL_BE_v1'
      and legacy.status in ('pending', 'retry_wait', 'processing')
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'SDF_INITIAL_CONFIRMATION_ACTIVE_LEGACY_REMAINS';
  end if;

  if exists (
    select 1
    from public.quote_request_email_jobs as legacy
    join public.sdf_initial_confirmation_email_jobs as isolated
      on isolated.quote_request_id = legacy.quote_request_id
    join public.quote_requests as request
      on request.id = legacy.quote_request_id
    where request.record_classification = 'production'
      and request.request_kind = 'slimme_documentenflow'
      and legacy.kind = 'customer_confirmation'
      and legacy.template_key = 'SDF_REQUEST_RECEIVED_NL_BE_v1'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'SDF_INITIAL_CONFIRMATION_DUAL_AUTHORITY_EXISTS';
  end if;

  if exists (
    select 1
    from lws_internal.application_intake_automation_work as work
    join public.quote_requests as request
      on request.id = work.quote_request_id
    where request.record_classification = 'production'
      and request.request_kind = 'slimme_documentenflow'
      and request.confirmation_sent_at is null
      and work.phase = 'SDF_CONFIRMATION'
      and not exists (
        select 1
        from public.sdf_initial_confirmation_email_jobs as isolated
        where isolated.quote_request_id = request.id
      )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'SDF_INITIAL_CONFIRMATION_UNRESOLVED_WITHOUT_AUTHORITY';
  end if;
end;
$$;

revoke all on function lws_internal.assert_sdf_initial_confirmation_runtime_finalizable_v1()
from public, anon, authenticated, service_role;

select lws_internal.assert_sdf_initial_confirmation_runtime_finalizable_v1();

drop function public.execute_application_intake_automation_sdf_confirmation_v1(bigint, uuid);

create or replace function public.prepare_sdf_initial_confirmation_v2(
  p_work_id bigint,
  p_work_claim_token uuid
)
returns table (
  outcome text,
  authority_source text,
  job_id uuid,
  job_status text,
  next_attempt_at timestamptz,
  request_name text,
  request_email text,
  application_reference text,
  created_at timestamptz,
  request_kind text,
  template_version text
)
language plpgsql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_work lws_internal.application_intake_automation_work%rowtype;
  v_request public.quote_requests%rowtype;
  v_job public.sdf_initial_confirmation_email_jobs%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  select work.* into v_work
  from lws_internal.application_intake_automation_work as work
  where work.work_id = p_work_id
    and work.claim_token = p_work_claim_token
    and work.claim_expires_at > v_now
    and work.phase = 'SDF_CONFIRMATION'
  for update;

  if not found then
    return;
  end if;

  select request.* into v_request
  from public.quote_requests as request
  where request.id = v_work.quote_request_id
    and request.request_kind = 'slimme_documentenflow'
    and request.record_classification = 'production'
  for update;

  if not found then
    return;
  end if;

  if v_request.confirmation_sent_at is not null then
    return query select
      'already_sent'::text,
      null::text,
      null::uuid,
      null::text,
      null::timestamptz,
      v_request.name,
      v_request.email,
      v_request.application_reference,
      v_request.created_at,
      v_request.request_kind,
      null::text;
    return;
  end if;

  insert into public.sdf_initial_confirmation_email_jobs (quote_request_id)
  values (v_request.id)
  on conflict (quote_request_id) do nothing;

  select job.* into strict v_job
  from public.sdf_initial_confirmation_email_jobs as job
  where job.quote_request_id = v_request.id;

  if v_job.status = 'processing' then
    update lws_internal.application_intake_automation_work as work
    set claim_token = null,
        claimed_by = null,
        claimed_at = null,
        claim_expires_at = null,
        next_attempt_at = v_job.delivery_lease_expires_at,
        updated_at = v_now
    where work.work_id = p_work_id
      and work.claim_token = p_work_claim_token;
  elsif v_job.status = 'retry_wait' and v_job.next_attempt_at > v_now then
    update lws_internal.application_intake_automation_work as work
    set claim_token = null,
        claimed_by = null,
        claimed_at = null,
        claim_expires_at = null,
        next_attempt_at = v_job.next_attempt_at,
        updated_at = v_now
    where work.work_id = p_work_id
      and work.claim_token = p_work_claim_token;
  elsif v_job.status = 'failed' then
    update lws_internal.application_intake_automation_work as work
    set phase = 'MANUAL_REVIEW',
        claim_token = null,
        claimed_by = null,
        claimed_at = null,
        claim_expires_at = null,
        last_error_code = coalesce(
          v_job.last_error_code,
          'SDF_INITIAL_CONFIRMATION_FAILED'
        ),
        terminal_reason = coalesce(
          v_job.last_error_code,
          'SDF_INITIAL_CONFIRMATION_FAILED'
        ),
        updated_at = v_now
    where work.work_id = p_work_id
      and work.claim_token = p_work_claim_token;
  end if;

  return query select
    case
      when v_job.status in ('pending', 'retry_wait')
           and v_job.next_attempt_at <= clock_timestamp() then 'due'
      else v_job.status
    end,
    'sdf_initial'::text,
    v_job.job_id,
    v_job.status,
    v_job.next_attempt_at,
    v_request.name,
    v_request.email,
    v_request.application_reference,
    v_request.created_at,
    v_request.request_kind,
    v_job.template_version;
end;
$$;

revoke all on function public.prepare_sdf_initial_confirmation_v2(bigint, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.prepare_sdf_initial_confirmation_v2(bigint, uuid)
to service_role;