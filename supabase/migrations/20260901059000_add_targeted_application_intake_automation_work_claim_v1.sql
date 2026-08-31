create function lws_internal.claim_application_intake_automation_work_internal_v1(
  p_worker_id uuid,
  p_limit integer,
  p_work_id bigint default null
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
  v_now timestamptz := clock_timestamp();
  v_limit integer;
begin
  if p_worker_id is null then
    raise exception using
      errcode = '22023',
      message = 'INVALID_AUTOMATION_WORKER_ID';
  end if;

  v_limit := case
    when p_work_id is null then least(greatest(coalesce(p_limit, 5), 1), 5)
    else 1
  end;

  return query
  with candidates as materialized (
    select work.work_id
    from lws_internal.application_intake_automation_work as work
    join public.quote_requests as request
      on request.id = work.quote_request_id
    join lws_internal.application_intake_automation_config as config
      on config.singleton
    where (p_work_id is null or work.work_id = p_work_id)
      and config.active
      and request.created_at >= config.cutover_at
      and request.record_classification = 'production'
      and work.phase in ('APPROVAL', 'INTAKE', 'SDF_CONFIRMATION', 'SDF_INTAKE')
      and work.attempt_count < 5
      and work.next_attempt_at <= v_now
      and (work.claim_token is null or work.claim_expires_at <= v_now)
      and (
        (
          request.request_kind = 'website'
          and work.phase in ('APPROVAL', 'INTAKE')
        )
        or (
          request.request_kind = 'slimme_documentenflow'
          and work.phase = 'SDF_CONFIRMATION'
          and request.confirmation_sent_at is null
        )
        or (
          request.request_kind = 'slimme_documentenflow'
          and work.phase = 'SDF_INTAKE'
          and request.confirmation_sent_at is not null
          and work.intake_due_at <= v_now
          and exists (
            select 1
            from public.sdf_qualification_intakes as intake
            join public.sdf_qualification_intake_email_jobs as invitation
              on invitation.intake_id = intake.intake_id
            where intake.quote_request_id = request.id
              and intake.status = 'invited'
              and invitation.kind = 'invitation'
              and invitation.status in ('pending', 'retry_wait')
              and invitation.next_attempt_at <= v_now
          )
        )
      )
    order by work.next_attempt_at, work.work_id
    for update of work skip locked
    limit v_limit
  ), claimed as (
    update lws_internal.application_intake_automation_work as work
    set claim_token = gen_random_uuid(),
        claimed_by = p_worker_id,
        claimed_at = v_now,
        claim_expires_at = v_now + interval '90 seconds',
        attempt_count = work.attempt_count + 1,
        last_error_code = null
    from candidates
    where work.work_id = candidates.work_id
    returning
      work.work_id,
      work.quote_request_id,
      work.phase,
      work.claim_token,
      work.claim_expires_at
  )
  select
    claimed.work_id,
    claimed.quote_request_id,
    claimed.phase,
    claimed.claim_token,
    claimed.claim_expires_at
  from claimed
  order by claimed.work_id;
end;
$$;

create or replace function public.claim_application_intake_automation_work_v1(
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
language sql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
  select *
  from lws_internal.claim_application_intake_automation_work_internal_v1(
    p_worker_id,
    p_limit,
    null
  );
$$;

create function public.claim_application_intake_automation_work_by_id_v1(
  p_worker_id uuid,
  p_work_id bigint
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
begin
  if p_work_id is null then
    raise exception using
      errcode = '22023',
      message = 'INVALID_AUTOMATION_WORK_ID';
  end if;

  return query
  select *
  from lws_internal.claim_application_intake_automation_work_internal_v1(
    p_worker_id,
    1,
    p_work_id
  );
end;
$$;

revoke all on function lws_internal.claim_application_intake_automation_work_internal_v1(uuid, integer, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_application_intake_automation_work_v1(uuid, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_application_intake_automation_work_by_id_v1(uuid, bigint)
  from public, anon, authenticated, service_role;

grant execute on function public.claim_application_intake_automation_work_v1(uuid, integer)
  to service_role;
grant execute on function public.claim_application_intake_automation_work_by_id_v1(uuid, bigint)
  to service_role;