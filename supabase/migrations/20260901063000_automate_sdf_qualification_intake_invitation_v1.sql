create function lws_internal.ensure_sdf_qualification_intake_invited_v1(
  p_quote_request_id uuid,
  p_customer_capability_digest text,
  p_encrypted_capability text,
  p_idempotency_key uuid,
  p_request_fingerprint text,
  p_actor_class text,
  p_actor_operator_id uuid,
  p_reuse_existing boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_request public.quote_requests%rowtype;
  v_intake public.sdf_qualification_intakes%rowtype;
  v_event public.sdf_qualification_intake_events%rowtype;
  v_job public.sdf_qualification_intake_email_jobs%rowtype;
  v_event_id uuid := gen_random_uuid();
  v_occurred_at timestamptz := clock_timestamp();
  v_due timestamptz;
  v_result jsonb;
begin
  if p_quote_request_id is null
     or p_idempotency_key is null
     or p_customer_capability_digest !~ '^[0-9a-f]{64}$'
     or p_encrypted_capability !~ '^v1\.[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{40,}$'
     or p_request_fingerprint !~ '^[0-9a-f]{64}$'
     or (p_actor_class = 'operator' and p_actor_operator_id is null)
     or (p_actor_class = 'system' and p_actor_operator_id is not null)
     or p_actor_class not in ('operator', 'system') then
    raise exception using errcode = '22023', message = 'INVALID_SDF_INTAKE_INVITATION_REQUEST';
  end if;

  select * into v_event
  from public.sdf_qualification_intake_events
  where idempotency_key = p_idempotency_key;
  if found then
    if v_event.request_fingerprint <> p_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    select * into strict v_intake
    from public.sdf_qualification_intakes
    where intake_id = v_event.intake_id;
    select * into strict v_job
    from public.sdf_qualification_intake_email_jobs
    where intake_id = v_intake.intake_id
      and kind = 'invitation'
      and invitation_generation = v_intake.invitation_generation;
    return v_event.result_snapshot || jsonb_build_object(
      'job_id', v_job.job_id,
      'encrypted_capability', coalesce(v_job.encrypted_capability, v_intake.customer_capability_encrypted),
      'customer_capability_digest', v_intake.customer_capability_digest
    );
  end if;

  select * into v_request
  from public.quote_requests
  where id = p_quote_request_id
  for update;
  if not found or v_request.request_kind <> 'slimme_documentenflow' then
    raise exception using errcode = '23514', message = 'SDF_REQUEST_KIND_REQUIRED';
  end if;
    if (p_actor_class = 'system' and v_request.record_classification <> 'production')
      or v_request.status = 'rejected' then
    raise exception using errcode = '55000', message = 'SDF_REQUEST_CLOSED';
  end if;

  select * into v_intake
  from public.sdf_qualification_intakes
  where quote_request_id = p_quote_request_id;
  if found then
    if not p_reuse_existing then
      raise exception using errcode = '23505', message = 'SDF_INTAKE_ALREADY_EXISTS';
    end if;
    select * into v_job
    from public.sdf_qualification_intake_email_jobs
    where intake_id = v_intake.intake_id
      and kind = 'invitation'
      and invitation_generation = v_intake.invitation_generation;
    if not found then
      raise exception using errcode = '55000', message = 'SDF_INVITATION_AUTHORITY_INCOMPLETE';
    end if;
    return jsonb_build_object(
      'intake_id', v_intake.intake_id,
      'quote_request_id', p_quote_request_id,
      'status', v_intake.status,
      'invitation_generation', v_intake.invitation_generation,
      'expires_at', v_intake.customer_capability_expires_at,
      'event_id', (
        select event_id
        from public.sdf_qualification_intake_events
        where intake_id = v_intake.intake_id and event_kind = 'INVITED'
        order by occurred_at, event_id
        limit 1
      ),
      'job_id', v_job.job_id,
      'encrypted_capability', coalesce(v_job.encrypted_capability, v_intake.customer_capability_encrypted),
      'customer_capability_digest', v_intake.customer_capability_digest,
      'replayed', true
    );
  end if;

  v_due := coalesce(v_request.confirmation_sent_at + interval '120 seconds', 'infinity'::timestamptz);
  insert into public.sdf_qualification_intakes(
    quote_request_id,
    customer_capability_digest,
    customer_capability_encrypted,
    customer_capability_expires_at
  ) values (
    p_quote_request_id,
    p_customer_capability_digest,
    p_encrypted_capability,
    clock_timestamp() + interval '14 days'
  ) returning * into v_intake;

  v_result := jsonb_build_object(
    'intake_id', v_intake.intake_id,
    'quote_request_id', p_quote_request_id,
    'status', 'invited',
    'invitation_generation', v_intake.invitation_generation,
    'expires_at', v_intake.customer_capability_expires_at,
    'event_id', v_event_id,
    'occurred_at', v_occurred_at,
    'replayed', false
  );
  insert into public.sdf_qualification_intake_events(
    event_id, intake_id, event_kind, to_status, actor_class, actor_operator_id,
    idempotency_key, request_fingerprint, result_snapshot, occurred_at
  ) values (
    v_event_id, v_intake.intake_id, 'INVITED', 'invited', p_actor_class,
    p_actor_operator_id, p_idempotency_key, p_request_fingerprint, v_result,
    v_occurred_at
  );
  insert into public.sdf_qualification_intake_email_jobs(
    intake_id, kind, template_version, invitation_generation, status,
    next_attempt_at, idempotency_key, request_fingerprint, encrypted_capability
  ) values (
    v_intake.intake_id, 'invitation',
    'SDF_QUALIFICATION_INTAKE_INVITATION_NL_BE_v1',
    v_intake.invitation_generation, 'pending', v_due, p_idempotency_key,
    p_request_fingerprint, p_encrypted_capability
  ) returning * into v_job;

  return v_result || jsonb_build_object(
    'job_id', v_job.job_id,
    'encrypted_capability', p_encrypted_capability,
    'customer_capability_digest', p_customer_capability_digest
  );
end;
$$;

revoke all on function lws_internal.ensure_sdf_qualification_intake_invited_v1(uuid,text,text,uuid,text,text,uuid,boolean) from public, anon, authenticated, service_role;

create or replace function public.allow_sdf_qualification_intake_v1(
  p_quote_request_id uuid,
  p_customer_capability_digest text,
  p_encrypted_capability text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_fingerprint char(64);
begin
  v_operator := lws_internal.assert_sdf_owner_v1();
  if p_quote_request_id is null
     or p_idempotency_key is null
     or p_customer_capability_digest !~ '^[0-9a-f]{64}$'
     or p_encrypted_capability !~ '^v1\.[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{40,}$' then
    raise exception using errcode = '22023', message = 'INVALID_SDF_INTAKE_ALLOW_REQUEST';
  end if;
  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'v', 1,
    'request', p_quote_request_id,
    'action', 'allow_sdf_qualification_intake'
  )::text, 'UTF8'), 'sha256'), 'hex');
  return lws_internal.ensure_sdf_qualification_intake_invited_v1(
    p_quote_request_id,
    p_customer_capability_digest,
    p_encrypted_capability,
    p_idempotency_key,
    v_fingerprint,
    'operator',
    v_operator.operator_id,
    false
  ) - 'job_id' - 'encrypted_capability' - 'customer_capability_digest';
end;
$$;

create or replace function lws_internal.claim_application_intake_automation_work_internal_v1(
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
    raise exception using errcode = '22023', message = 'INVALID_AUTOMATION_WORKER_ID';
  end if;
  v_limit := case when p_work_id is null then least(greatest(coalesce(p_limit, 5), 1), 5) else 1 end;
  return query
  with candidates as materialized (
    select work.work_id
    from lws_internal.application_intake_automation_work as work
    join public.quote_requests as request on request.id = work.quote_request_id
    join lws_internal.application_intake_automation_config as config on config.singleton
    where (p_work_id is null or work.work_id = p_work_id)
      and config.active
      and request.created_at >= config.cutover_at
      and request.record_classification = 'production'
      and request.status <> 'rejected'
      and work.phase in ('APPROVAL', 'INTAKE', 'SDF_CONFIRMATION', 'SDF_INTAKE')
      and work.attempt_count < 5
      and work.next_attempt_at <= v_now
      and (work.claim_token is null or work.claim_expires_at <= v_now)
      and (
        (request.request_kind = 'website' and work.phase in ('APPROVAL', 'INTAKE'))
        or (request.request_kind = 'slimme_documentenflow' and work.phase = 'SDF_CONFIRMATION' and request.confirmation_sent_at is null)
        or (
          request.request_kind = 'slimme_documentenflow'
          and work.phase = 'SDF_INTAKE'
          and request.confirmation_sent_at is not null
          and work.intake_due_at <= v_now
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
    returning work.work_id, work.quote_request_id, work.phase, work.claim_token, work.claim_expires_at
  )
  select claimed.work_id, claimed.quote_request_id, claimed.phase, claimed.claim_token, claimed.claim_expires_at
  from claimed
  order by claimed.work_id;
end;
$$;

create or replace function public.execute_application_intake_automation_sdf_intake_v1(
  p_work_id bigint,
  p_claim_token uuid,
  p_customer_capability_digest text,
  p_encrypted_capability text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = lws_internal, public, extensions, pg_catalog
as $$
declare
  v_work lws_internal.application_intake_automation_work%rowtype;
  v_request public.quote_requests%rowtype;
  v_ensured jsonb;
  v_fingerprint char(64);
  v_job_status text;
begin
  select * into v_work
  from lws_internal.application_intake_automation_work
  where work_id = p_work_id
    and phase = 'SDF_INTAKE'
    and claim_token = p_claim_token
    and claim_expires_at > clock_timestamp()
    and intake_due_at <= clock_timestamp()
  for update;
  if not found then return null; end if;

  select * into v_request
  from public.quote_requests
  where id = v_work.quote_request_id
    and request_kind = 'slimme_documentenflow'
    and record_classification = 'production'
    and status <> 'rejected'
    and confirmation_sent_at is not null;
  if not found then return null; end if;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'v', 1,
    'request', v_work.quote_request_id,
    'action', 'automate_sdf_qualification_intake'
  )::text, 'UTF8'), 'sha256'), 'hex');
  v_ensured := lws_internal.ensure_sdf_qualification_intake_invited_v1(
    v_work.quote_request_id,
    p_customer_capability_digest,
    p_encrypted_capability,
    p_claim_token,
    v_fingerprint,
    'system',
    null,
    true
  );

  select status::text into strict v_job_status
  from public.sdf_qualification_intake_email_jobs
  where job_id = (v_ensured->>'job_id')::uuid
  for update;
  if v_job_status = 'sent' then
    update lws_internal.application_intake_automation_work
    set phase = 'COMPLETED',
        claim_token = null,
        claimed_by = null,
        claimed_at = null,
        claim_expires_at = null,
        last_error_code = null
    where work_id = v_work.work_id;
    return jsonb_build_object(
      'outcome', 'already_sent',
      'job_id', v_ensured->>'job_id',
      'intake_id', v_ensured->>'intake_id',
      'request_id', v_request.id
    );
  end if;

  return jsonb_build_object(
    'outcome', 'invitation_pending',
    'job_id', v_ensured->>'job_id',
    'intake_id', v_ensured->>'intake_id',
    'request_id', v_request.id,
    'request_name', v_request.name,
    'request_email', v_request.email,
    'template_version', 'SDF_QUALIFICATION_INTAKE_INVITATION_NL_BE_v1',
    'encrypted_capability', v_ensured->>'encrypted_capability',
    'customer_capability_digest', v_ensured->>'customer_capability_digest',
    'expires_at', v_ensured->>'expires_at',
    'replayed', (v_ensured->>'replayed')::boolean
  );
end;
$$;

revoke all on function public.execute_application_intake_automation_sdf_intake_v1(bigint,uuid,text,text) from public, anon, authenticated;
grant execute on function public.execute_application_intake_automation_sdf_intake_v1(bigint,uuid,text,text) to service_role;

drop function public.execute_application_intake_automation_sdf_intake_v1(bigint,uuid);
