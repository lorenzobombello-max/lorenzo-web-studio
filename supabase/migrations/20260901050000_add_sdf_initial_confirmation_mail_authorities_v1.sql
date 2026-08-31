create function public.prepare_sdf_initial_confirmation_v2(
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
    return query select
      case
        when v_legacy.status = 'sent' then 'already_sent'
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
        last_error_code = coalesce(v_job.last_error_code, 'SDF_INITIAL_CONFIRMATION_FAILED'),
        terminal_reason = coalesce(v_job.last_error_code, 'SDF_INITIAL_CONFIRMATION_FAILED'),
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

create function public.claim_sdf_initial_confirmation_email_job_v1(
  p_job_id uuid
)
returns table (
  job_id uuid,
  quote_request_id uuid,
  request_name text,
  request_email text,
  application_reference text,
  template_version text,
  attempt_count integer,
  provider_idempotency_key text,
  delivery_lease_token uuid,
  delivery_lease_expires_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_job public.sdf_initial_confirmation_email_jobs%rowtype;
  v_now timestamptz := clock_timestamp();
  v_lease_token uuid := gen_random_uuid();
begin
  select job.* into v_job
  from public.sdf_initial_confirmation_email_jobs as job
  where job.job_id = p_job_id
  for update;

  if not found then
    return;
  end if;

  if v_job.status = 'processing'
     and v_job.delivery_lease_expires_at <= v_now then
    if v_job.attempt_count < v_job.max_attempts then
      update public.sdf_initial_confirmation_email_jobs as job
      set status = 'retry_wait',
          next_attempt_at = v_now,
          locked_at = null,
          delivery_lease_token = null,
          delivery_lease_expires_at = null,
          last_error_code = 'STALE_PROCESSING_LEASE',
          updated_at = v_now
      where job.job_id = v_job.job_id
      returning job.* into v_job;
    else
      update public.sdf_initial_confirmation_email_jobs as job
      set status = 'failed',
          next_attempt_at = v_now,
          locked_at = null,
          delivery_lease_token = null,
          delivery_lease_expires_at = null,
          last_error_code = 'STALE_PROCESSING_LEASE_EXHAUSTED',
          updated_at = v_now
      where job.job_id = v_job.job_id;

      update lws_internal.application_intake_automation_work as work
      set phase = 'MANUAL_REVIEW',
          claim_token = null,
          claimed_by = null,
          claimed_at = null,
          claim_expires_at = null,
          last_error_code = 'STALE_PROCESSING_LEASE_EXHAUSTED',
          terminal_reason = 'STALE_PROCESSING_LEASE_EXHAUSTED',
          updated_at = v_now
      where work.quote_request_id = v_job.quote_request_id
        and work.phase = 'SDF_CONFIRMATION';

      return;
    end if;
  end if;

  if v_job.status not in ('pending', 'retry_wait')
     or v_job.next_attempt_at > v_now
     or v_job.attempt_count >= v_job.max_attempts then
    return;
  end if;

  return query
  update public.sdf_initial_confirmation_email_jobs as job
  set status = 'processing',
      attempt_count = job.attempt_count + 1,
      locked_at = v_now,
      delivery_lease_token = v_lease_token,
      delivery_lease_expires_at = v_now + interval '10 minutes',
      last_error_code = null,
      updated_at = v_now
  from public.quote_requests as request
  where job.job_id = v_job.job_id
    and request.id = job.quote_request_id
    and request.request_kind = 'slimme_documentenflow'
    and request.record_classification = 'production'
    and request.confirmation_sent_at is null
    and job.status in ('pending', 'retry_wait')
    and job.next_attempt_at <= v_now
    and job.attempt_count < job.max_attempts
    and job.template_version = 'SDF_REQUEST_RECEIVED_NL_BE_v1'
  returning
    job.job_id,
    job.quote_request_id,
    request.name,
    request.email,
    request.application_reference,
    job.template_version,
    job.attempt_count,
    'sdf-initial-confirmation/' || job.job_id::text,
    job.delivery_lease_token,
    job.delivery_lease_expires_at;
end;
$$;

revoke all on function public.claim_sdf_initial_confirmation_email_job_v1(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.claim_sdf_initial_confirmation_email_job_v1(uuid)
to service_role;

create function public.validate_sdf_initial_confirmation_email_delivery_v1(
  p_job_id uuid,
  p_delivery_lease_token uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select coalesce((
    select
      job.status = 'processing'
      and job.delivery_lease_token = p_delivery_lease_token
      and job.delivery_lease_expires_at > clock_timestamp()
      and job.sent_at is null
      and job.template_version = 'SDF_REQUEST_RECEIVED_NL_BE_v1'
      and request.request_kind = 'slimme_documentenflow'
      and request.record_classification = 'production'
      and request.confirmation_sent_at is null
    from public.sdf_initial_confirmation_email_jobs as job
    join public.quote_requests as request
      on request.id = job.quote_request_id
    where job.job_id = p_job_id
  ), false);
$$;

revoke all on function public.validate_sdf_initial_confirmation_email_delivery_v1(uuid, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.validate_sdf_initial_confirmation_email_delivery_v1(uuid, uuid)
to service_role;

create function public.complete_sdf_initial_confirmation_email_job_v1(
  p_job_id uuid,
  p_delivery_lease_token uuid,
  p_succeeded boolean,
  p_retryable boolean,
  p_error_code text,
  p_provider_message_id text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_job public.sdf_initial_confirmation_email_jobs%rowtype;
  v_now timestamptz := clock_timestamp();
  v_status text;
  v_backoff_seconds integer;
begin
  select job.* into v_job
  from public.sdf_initial_confirmation_email_jobs as job
  join public.quote_requests as request
    on request.id = job.quote_request_id
  where job.job_id = p_job_id
    and job.status = 'processing'
    and job.delivery_lease_token = p_delivery_lease_token
    and job.delivery_lease_expires_at > v_now
    and job.sent_at is null
    and job.template_version = 'SDF_REQUEST_RECEIVED_NL_BE_v1'
    and request.request_kind = 'slimme_documentenflow'
    and request.record_classification = 'production'
    and request.confirmation_sent_at is null
  for update of job;

  if not found then
    return null;
  end if;

  v_status := case
    when p_succeeded then 'sent'
    when p_retryable and v_job.attempt_count < v_job.max_attempts then 'retry_wait'
    else 'failed'
  end;

  v_backoff_seconds := least(
    3600,
    30 * power(2, greatest(v_job.attempt_count - 1, 0))::integer
  );

  update public.sdf_initial_confirmation_email_jobs as job
  set status = v_status,
      next_attempt_at = case
        when v_status = 'retry_wait' then v_now + make_interval(secs => v_backoff_seconds)
        else v_now
      end,
      locked_at = null,
      delivery_lease_token = null,
      delivery_lease_expires_at = null,
      sent_at = case when v_status = 'sent' then v_now else null end,
      provider_message_id = case
        when v_status = 'sent' then p_provider_message_id
        else job.provider_message_id
      end,
      last_error_code = case
        when v_status = 'sent' then null
        else left(coalesce(p_error_code, 'UNKNOWN_ERROR'), 120)
      end,
      updated_at = v_now
  where job.job_id = v_job.job_id;

  if v_status = 'failed' then
    update lws_internal.application_intake_automation_work as work
    set phase = 'MANUAL_REVIEW',
        claim_token = null,
        claimed_by = null,
        claimed_at = null,
        claim_expires_at = null,
        last_error_code = left(coalesce(p_error_code, 'SDF_INITIAL_CONFIRMATION_FAILED'), 64),
        terminal_reason = left(coalesce(p_error_code, 'SDF_INITIAL_CONFIRMATION_FAILED'), 64),
        updated_at = v_now
    where work.quote_request_id = v_job.quote_request_id
      and work.phase = 'SDF_CONFIRMATION';
  end if;

  return jsonb_build_object(
    'status', v_status,
    'attempt_count', v_job.attempt_count,
    'job_id', v_job.job_id,
    'provider_idempotency_key', 'sdf-initial-confirmation/' || v_job.job_id::text
  );
end;
$$;

revoke all on function public.complete_sdf_initial_confirmation_email_job_v1(uuid, uuid, boolean, boolean, text, text)
from public, anon, authenticated, service_role;

grant execute on function public.complete_sdf_initial_confirmation_email_job_v1(uuid, uuid, boolean, boolean, text, text)
to service_role;