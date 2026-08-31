create or replace function public.execute_application_intake_automation_sdf_confirmation_v1(
  p_work_id bigint,
  p_claim_token uuid
)
returns table (
  outcome text,
  confirmation_job_id uuid,
  request_name text,
  request_email text,
  application_reference text,
  created_at timestamptz,
  request_kind text,
  template_key text,
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
  v_job public.quote_request_email_jobs%rowtype;
begin
  select work.* into v_work
  from lws_internal.application_intake_automation_work as work
  where work.work_id = p_work_id
    and work.claim_token = p_claim_token
    and work.claim_expires_at > clock_timestamp()
  for update;

  if not found or v_work.phase <> 'SDF_CONFIRMATION' then
    return;
  end if;

  select request.* into v_request
  from public.quote_requests as request
  where request.id = v_work.quote_request_id
    and request.request_kind = 'slimme_documentenflow'
    and request.record_classification = 'production'
  for update;

  if not found or v_request.confirmation_sent_at is not null then
    return;
  end if;

  if exists (
    select 1
    from public.sdf_initial_confirmation_email_jobs as isolated
    where isolated.quote_request_id = v_request.id
  ) then
    return;
  end if;

  insert into public.quote_request_email_jobs (
    quote_request_id,
    kind,
    next_attempt_at,
    template_key,
    template_version
  )
  select
    v_request.id,
    'customer_confirmation',
    clock_timestamp(),
    'SDF_REQUEST_RECEIVED_NL_BE_v1',
    'v1'
  where not exists (
    select 1
    from public.quote_request_email_jobs as existing
    where existing.quote_request_id = v_request.id
      and existing.kind = 'customer_confirmation'
  )
  on conflict do nothing;

  select job.* into strict v_job
  from public.quote_request_email_jobs as job
  where job.quote_request_id = v_request.id
    and job.kind = 'customer_confirmation'
    and job.template_key = 'SDF_REQUEST_RECEIVED_NL_BE_v1'
    and job.template_version = 'v1';

  return query select
    'confirmation_pending'::text,
    v_job.id,
    v_request.name,
    v_request.email,
    v_request.application_reference,
    v_request.created_at,
    v_request.request_kind,
    v_job.template_key,
    v_job.template_version;
end;
$$;

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
  v_legacy public.quote_request_email_jobs%rowtype;
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

  select legacy.* into v_legacy
  from public.quote_request_email_jobs as legacy
  where legacy.quote_request_id = v_request.id
    and legacy.kind = 'customer_confirmation'
    and legacy.template_key = 'SDF_REQUEST_RECEIVED_NL_BE_v1'
  order by legacy.created_at, legacy.id
  limit 1;

  if found then
    if v_legacy.status = 'sent' then
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

    if v_legacy.status = 'failed' then
      update lws_internal.application_intake_automation_work as work
      set phase = 'MANUAL_REVIEW',
          claim_token = null,
          claimed_by = null,
          claimed_at = null,
          claim_expires_at = null,
          last_error_code = coalesce(
            v_legacy.last_error_code,
            'SDF_LEGACY_INITIAL_CONFIRMATION_FAILED'
          ),
          terminal_reason = coalesce(
            v_legacy.last_error_code,
            'SDF_LEGACY_INITIAL_CONFIRMATION_FAILED'
          ),
          updated_at = v_now
      where work.work_id = p_work_id
        and work.claim_token = p_work_claim_token;
    end if;

    return query select
      case
        when v_legacy.status in ('pending', 'retry_wait')
             and v_legacy.next_attempt_at <= v_now then 'due'
        else v_legacy.status::text
      end,
      'legacy'::text,
      v_legacy.id,
      v_legacy.status::text,
      v_legacy.next_attempt_at,
      v_request.name,
      v_request.email,
      v_request.application_reference,
      v_request.created_at,
      v_request.request_kind,
      v_legacy.template_version;
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