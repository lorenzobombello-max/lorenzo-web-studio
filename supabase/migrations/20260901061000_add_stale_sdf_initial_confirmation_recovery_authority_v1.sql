create table lws_internal.sdf_initial_confirmation_recovery_events (
  recovery_event_id bigint generated always as identity primary key,
  work_id bigint not null unique
    references lws_internal.application_intake_automation_work(work_id) on delete restrict,
  quote_request_id uuid not null
    references public.quote_requests(id) on delete restrict,
  job_id uuid not null unique
    references public.sdf_initial_confirmation_email_jobs(job_id) on delete restrict,
  recovery_generation integer not null default 1
    constraint sdf_initial_confirmation_recovery_events_generation_check
    check (recovery_generation = 1),
  original_work_attempt_count integer not null
    constraint sdf_initial_confirmation_recovery_events_work_attempt_check
    check (original_work_attempt_count = 5),
  original_work_claim_token uuid,
  original_work_claimed_by uuid,
  original_work_claimed_at timestamptz,
  original_work_claim_expires_at timestamptz,
  original_job_attempt_count integer not null
    constraint sdf_initial_confirmation_recovery_events_job_attempt_check
    check (original_job_attempt_count between 1 and 4),
  original_job_locked_at timestamptz not null,
  original_delivery_lease_token uuid not null,
  original_delivery_lease_expires_at timestamptz not null,
  recovery_reference text not null
    constraint sdf_initial_confirmation_recovery_events_reference_check
    check (char_length(btrim(recovery_reference)) between 8 and 128),
  provider_idempotency_key text not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint sdf_initial_confirmation_recovery_events_provider_key_check
    check (provider_idempotency_key = 'sdf-initial-confirmation/' || job_id::text),
  constraint sdf_initial_confirmation_recovery_events_work_claim_check
    check (
      (
        original_work_claim_token is null
        and original_work_claimed_by is null
        and original_work_claimed_at is null
        and original_work_claim_expires_at is null
      )
      or (
        original_work_claim_token is not null
        and original_work_claimed_by is not null
        and original_work_claimed_at is not null
        and original_work_claim_expires_at is not null
      )
    )
);

create function lws_internal.prevent_sdf_initial_confirmation_recovery_event_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'SDF_INITIAL_CONFIRMATION_RECOVERY_EVENT_IMMUTABLE';
end;
$$;

create trigger trg_sdf_initial_confirmation_recovery_events_immutable
before update or delete on lws_internal.sdf_initial_confirmation_recovery_events
for each row execute function lws_internal.prevent_sdf_initial_confirmation_recovery_event_mutation_v1();

alter table lws_internal.sdf_initial_confirmation_recovery_events enable row level security;
alter table lws_internal.sdf_initial_confirmation_recovery_events force row level security;

create function public.recover_stale_sdf_initial_confirmation_work_v1(
  p_work_id bigint,
  p_expected_job_id uuid,
  p_recovery_reference text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_work lws_internal.application_intake_automation_work%rowtype;
  v_request public.quote_requests%rowtype;
  v_job public.sdf_initial_confirmation_email_jobs%rowtype;
  v_event lws_internal.sdf_initial_confirmation_recovery_events%rowtype;
  v_now timestamptz := clock_timestamp();
  v_reference text := btrim(p_recovery_reference);
begin
  if p_work_id is null or p_expected_job_id is null then
    raise exception using
      errcode = '22023',
      message = 'INVALID_SDF_INITIAL_CONFIRMATION_RECOVERY_TARGET';
  end if;
  if v_reference is null or char_length(v_reference) not between 8 and 128 then
    raise exception using
      errcode = '22023',
      message = 'INVALID_SDF_INITIAL_CONFIRMATION_RECOVERY_REFERENCE';
  end if;

  select work.* into v_work
  from lws_internal.application_intake_automation_work as work
  where work.work_id = p_work_id
  for update;

  if not found then
    return jsonb_build_object('outcome', 'not_eligible', 'reason', 'WORK_NOT_FOUND');
  end if;

  select event.* into v_event
  from lws_internal.sdf_initial_confirmation_recovery_events as event
  where event.work_id = v_work.work_id;

  if found then
    if v_event.job_id is distinct from p_expected_job_id then
      return jsonb_build_object('outcome', 'not_eligible', 'reason', 'EXPECTED_JOB_MISMATCH');
    end if;
    return jsonb_build_object(
      'outcome', 'already_recovered',
      'recovery_event_id', v_event.recovery_event_id,
      'work_id', v_event.work_id,
      'quote_request_id', v_event.quote_request_id,
      'job_id', v_event.job_id,
      'recovery_generation', v_event.recovery_generation,
      'provider_idempotency_key', v_event.provider_idempotency_key,
      'recovered_at', v_event.created_at
    );
  end if;

  select request.* into v_request
  from public.quote_requests as request
  where request.id = v_work.quote_request_id
  for update;

  select job.* into v_job
  from public.sdf_initial_confirmation_email_jobs as job
  where job.job_id = p_expected_job_id
    and job.quote_request_id = v_work.quote_request_id
  for update;

  if v_work.phase <> 'SDF_CONFIRMATION'
     or v_work.attempt_count <> 5
     or (
       v_work.claim_token is not null
       and v_work.claim_expires_at > v_now
     )
     or not found
     or v_request.record_classification <> 'production'
     or v_request.request_kind <> 'slimme_documentenflow'
     or v_request.confirmation_sent_at is not null
     or v_job.status <> 'processing'
     or v_job.delivery_lease_token is null
     or v_job.locked_at is null
     or v_job.delivery_lease_expires_at is null
     or v_job.delivery_lease_expires_at > v_now
     or v_job.attempt_count >= v_job.max_attempts
     or v_job.sent_at is not null
     or v_job.provider_message_id is not null
     or v_now >= v_job.locked_at + interval '24 hours'
     or exists (
       select 1
       from public.quote_request_email_jobs as legacy
       where legacy.quote_request_id = v_request.id
         and legacy.kind = 'customer_confirmation'
     ) then
    return jsonb_build_object('outcome', 'not_eligible', 'reason', 'STATE_MISMATCH');
  end if;

  insert into lws_internal.sdf_initial_confirmation_recovery_events (
    work_id,
    quote_request_id,
    job_id,
    original_work_attempt_count,
    original_work_claim_token,
    original_work_claimed_by,
    original_work_claimed_at,
    original_work_claim_expires_at,
    original_job_attempt_count,
    original_job_locked_at,
    original_delivery_lease_token,
    original_delivery_lease_expires_at,
    recovery_reference,
    provider_idempotency_key,
    created_at
  ) values (
    v_work.work_id,
    v_work.quote_request_id,
    v_job.job_id,
    v_work.attempt_count,
    v_work.claim_token,
    v_work.claimed_by,
    v_work.claimed_at,
    v_work.claim_expires_at,
    v_job.attempt_count,
    v_job.locked_at,
    v_job.delivery_lease_token,
    v_job.delivery_lease_expires_at,
    v_reference,
    'sdf-initial-confirmation/' || v_job.job_id::text,
    v_now
  )
  returning * into v_event;

  update public.sdf_initial_confirmation_email_jobs as job
  set status = 'retry_wait',
      next_attempt_at = v_now,
      locked_at = null,
      delivery_lease_token = null,
      delivery_lease_expires_at = null,
      last_error_code = 'STALE_PROCESSING_LEASE',
      updated_at = v_now
  where job.job_id = v_job.job_id;

  update lws_internal.application_intake_automation_work as work
  set attempt_count = 0,
      next_attempt_at = v_now,
      claim_token = null,
      claimed_by = null,
      claimed_at = null,
      claim_expires_at = null,
      last_error_code = 'SDF_INITIAL_CONFIRMATION_RECOVERY_ARMED',
      terminal_reason = null,
      updated_at = v_now
  where work.work_id = v_work.work_id;

  return jsonb_build_object(
    'outcome', 'recovered',
    'recovery_event_id', v_event.recovery_event_id,
    'work_id', v_event.work_id,
    'quote_request_id', v_event.quote_request_id,
    'job_id', v_event.job_id,
    'recovery_generation', v_event.recovery_generation,
    'original_work_attempt_count', v_event.original_work_attempt_count,
    'rearmed_work_attempt_count', 0,
    'job_attempt_count', v_event.original_job_attempt_count,
    'provider_idempotency_key', v_event.provider_idempotency_key,
    'recovered_at', v_event.created_at
  );
end;
$$;

revoke all on table lws_internal.sdf_initial_confirmation_recovery_events
from public, anon, authenticated, service_role;

revoke all on function lws_internal.prevent_sdf_initial_confirmation_recovery_event_mutation_v1()
from public, anon, authenticated, service_role;

revoke all on function public.recover_stale_sdf_initial_confirmation_work_v1(bigint, uuid, text)
from public, anon, authenticated, service_role;

grant execute on function public.recover_stale_sdf_initial_confirmation_work_v1(bigint, uuid, text)
to service_role;

do $$
declare
  v_sequence text;
begin
  v_sequence := pg_catalog.pg_get_serial_sequence(
    'lws_internal.sdf_initial_confirmation_recovery_events',
    'recovery_event_id'
  );
  execute pg_catalog.format(
    'revoke all on sequence %s from public, anon, authenticated, service_role',
    v_sequence
  );
end;
$$;
