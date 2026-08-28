create function public.claim_application_intake_automation_work_v1(
  p_worker_id uuid,
  p_limit integer default 5
)
returns table (
  work_id bigint,
  quote_request_id uuid,
  phase text,
  claim_token uuid,
  claim_expires_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_now timestamptz;
  v_limit integer;
begin
  if p_worker_id is null then
    raise exception using
      errcode = '22023',
      message = 'INVALID_AUTOMATION_WORKER_ID';
  end if;

  v_now := clock_timestamp();
  v_limit := least(greatest(coalesce(p_limit, 5), 1), 5);

  return query
  with exhausted as (
    update lws_internal.application_intake_automation_work as exhausted_work
    set phase = 'MANUAL_REVIEW',
        claim_token = null,
        claimed_by = null,
        claimed_at = null,
        claim_expires_at = null,
        last_error_code = 'STALE_RECOVERY_EXHAUSTED',
        terminal_reason = 'STALE_RECOVERY_EXHAUSTED'
    where exhausted_work.phase in ('APPROVAL', 'INTAKE')
      and exhausted_work.attempt_count >= 5
      and exhausted_work.claim_expires_at <= v_now
    returning exhausted_work.work_id
  ),
  candidates as materialized (
    select automation_work.work_id as candidate_work_id
    from lws_internal.application_intake_automation_work as automation_work
    join public.quote_requests as request
      on request.id = automation_work.quote_request_id
    join lws_internal.application_intake_automation_config as config
      on config.singleton
    where config.active
      and config.cutover_at is not null
      and request.created_at >= config.cutover_at
      and request.record_classification = 'production'
      and request.request_kind = 'website'
      and automation_work.phase in ('APPROVAL', 'INTAKE')
      and automation_work.attempt_count < 5
      and automation_work.next_attempt_at <= v_now
      and (
        automation_work.claim_token is null
        or automation_work.claim_expires_at <= v_now
      )
      and (
        (
          automation_work.phase = 'APPROVAL'
          and request.status = 'pending'::public.quote_request_status
          and request.approval_token_hash is not null
          and request.approval_token_expires_at > v_now
          and automation_work.approval_due_at <= v_now
          and automation_work.approved_at is null
          and automation_work.intake_due_at is null
        )
        or (
          automation_work.phase = 'INTAKE'
          and request.status = 'approved'::public.quote_request_status
          and automation_work.approved_at is not null
          and automation_work.intake_due_at is not null
          and automation_work.intake_due_at <= v_now
          and not exists (
            select 1
            from public.quote_request_intakes as existing_intake
            where existing_intake.quote_request_id = automation_work.quote_request_id
          )
        )
      )
    order by automation_work.next_attempt_at, automation_work.work_id
    for update of automation_work skip locked
    limit v_limit
  ),
  claimed as (
    update lws_internal.application_intake_automation_work as automation_work
    set claim_token = gen_random_uuid(),
        claimed_by = p_worker_id,
        claimed_at = v_now,
        claim_expires_at = v_now + interval '90 seconds',
        attempt_count = automation_work.attempt_count + 1,
        last_error_code = null,
        terminal_reason = null
    from candidates
    where automation_work.work_id = candidates.candidate_work_id
    returning
      automation_work.work_id as claimed_work_id,
      automation_work.quote_request_id as claimed_quote_request_id,
      automation_work.phase as claimed_phase,
      automation_work.claim_token as issued_claim_token,
      automation_work.claim_expires_at as issued_claim_expires_at
  )
  select
    claimed.claimed_work_id,
    claimed.claimed_quote_request_id,
    claimed.claimed_phase,
    claimed.issued_claim_token,
    claimed.issued_claim_expires_at
  from claimed
  order by claimed.claimed_work_id;
end;
$$;

create function public.fail_application_intake_automation_work_v1(
  p_work_id bigint,
  p_claim_token uuid,
  p_error_code text,
  p_retryable boolean
)
returns table (
  outcome text,
  phase text,
  attempt_count integer,
  next_attempt_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = lws_internal, pg_catalog
as $$
declare
  v_work lws_internal.application_intake_automation_work%rowtype;
  v_now timestamptz;
  v_retry_delay interval;
begin
  if p_error_code is null
     or p_error_code <> all (array[
       'APPROVAL_AUTHORITY_FAILED',
       'INTAKE_AUTHORITY_FAILED',
       'MAIL_DELIVERY_RETRYABLE',
       'WORKER_INTERRUPTED',
       'AMBIGUOUS_RESULT'
     ]::text[]) then
    raise exception using
      errcode = '22023',
      message = 'INVALID_AUTOMATION_FAILURE_CODE';
  end if;

  if p_retryable is null then
    raise exception using
      errcode = '22023',
      message = 'INVALID_AUTOMATION_FAILURE_DISPOSITION';
  end if;

  select automation_work.* into v_work
  from lws_internal.application_intake_automation_work as automation_work
  where automation_work.work_id = p_work_id
    and automation_work.claim_token = p_claim_token
  for update;

  if not found then
    return;
  end if;

  v_now := clock_timestamp();
  if v_work.claim_expires_at <= v_now then
    return;
  end if;

  if not p_retryable
     or p_error_code = 'AMBIGUOUS_RESULT'
     or v_work.attempt_count >= 5 then
    update lws_internal.application_intake_automation_work as automation_work
    set phase = 'MANUAL_REVIEW',
        claim_token = null,
        claimed_by = null,
        claimed_at = null,
        claim_expires_at = null,
        last_error_code = p_error_code,
        terminal_reason = p_error_code
    where automation_work.work_id = v_work.work_id;

    return query
    select
      'manual_review'::text,
      automation_work.phase,
      automation_work.attempt_count,
      automation_work.next_attempt_at
    from lws_internal.application_intake_automation_work as automation_work
    where automation_work.work_id = v_work.work_id;
    return;
  end if;

  v_retry_delay := case v_work.attempt_count
    when 1 then interval '1 minute'
    when 2 then interval '5 minutes'
    when 3 then interval '15 minutes'
    else interval '30 minutes'
  end;

  update lws_internal.application_intake_automation_work as automation_work
  set claim_token = null,
      claimed_by = null,
      claimed_at = null,
      claim_expires_at = null,
      next_attempt_at = v_now + v_retry_delay,
      last_error_code = p_error_code,
      terminal_reason = null
  where automation_work.work_id = v_work.work_id;

  return query
  select
    'retry_scheduled'::text,
    automation_work.phase,
    automation_work.attempt_count,
    automation_work.next_attempt_at
  from lws_internal.application_intake_automation_work as automation_work
  where automation_work.work_id = v_work.work_id;
end;
$$;

revoke all on function public.claim_application_intake_automation_work_v1(uuid, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.fail_application_intake_automation_work_v1(bigint, uuid, text, boolean)
  from public, anon, authenticated, service_role;

grant execute on function public.claim_application_intake_automation_work_v1(uuid, integer)
  to service_role;
grant execute on function public.fail_application_intake_automation_work_v1(bigint, uuid, text, boolean)
  to service_role;