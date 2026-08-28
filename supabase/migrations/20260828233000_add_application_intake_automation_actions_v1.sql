create function lws_internal.reconcile_application_intake_automation_review_v1()
returns trigger
language plpgsql
security definer
set search_path = lws_internal, pg_catalog
as $$
begin
  if new.status = 'approved'
     and old.status is distinct from new.status
     and new.reviewed_at is not null then
    update lws_internal.application_intake_automation_work as automation_work
    set phase = 'INTAKE',
        approved_at = new.reviewed_at,
        intake_due_at = new.reviewed_at + interval '120 seconds',
        attempt_count = 0,
        next_attempt_at = new.reviewed_at + interval '120 seconds',
        claim_token = null,
        claimed_by = null,
        claimed_at = null,
        claim_expires_at = null,
        last_error_code = null,
        terminal_reason = null
    where automation_work.quote_request_id = new.id
      and automation_work.phase = 'APPROVAL';
  elsif new.status = 'rejected'
        and old.status is distinct from new.status then
    update lws_internal.application_intake_automation_work as automation_work
    set phase = 'STOPPED',
        claim_token = null,
        claimed_by = null,
        claimed_at = null,
        claim_expires_at = null,
        last_error_code = null,
        terminal_reason = 'REQUEST_REJECTED'
    where automation_work.quote_request_id = new.id
      and automation_work.phase = 'APPROVAL';
  end if;

  return new;
end;
$$;

create trigger trg_quote_requests_reconcile_automation_review_v1
after update of status, reviewed_at on public.quote_requests
for each row execute function lws_internal.reconcile_application_intake_automation_review_v1();

create function lws_internal.reconcile_application_intake_automation_intake_v1()
returns trigger
language plpgsql
security definer
set search_path = lws_internal, pg_catalog
as $$
begin
  if new.access_state = 'CANCELLED' then
    update lws_internal.application_intake_automation_work as automation_work
    set phase = 'STOPPED',
        claim_token = null,
        claimed_by = null,
        claimed_at = null,
        claim_expires_at = null,
        last_error_code = null,
        terminal_reason = 'INTAKE_CANCELLED'
    where automation_work.quote_request_id = new.quote_request_id
      and automation_work.phase = 'INTAKE';
  else
    update lws_internal.application_intake_automation_work as automation_work
    set phase = 'COMPLETED',
        claim_token = null,
        claimed_by = null,
        claimed_at = null,
        claim_expires_at = null,
        last_error_code = null,
        terminal_reason = null
    where automation_work.quote_request_id = new.quote_request_id
      and automation_work.phase = 'INTAKE';
  end if;

  return new;
end;
$$;

create trigger trg_quote_request_intakes_reconcile_automation_v1
after insert or update on public.quote_request_intakes
for each row execute function lws_internal.reconcile_application_intake_automation_intake_v1();

create function public.execute_application_intake_automation_approval_v1(
  p_work_id bigint,
  p_claim_token uuid
)
returns table (
  outcome text,
  confirmation_job_id uuid,
  request_name text,
  request_email text,
  reviewed_at timestamptz
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
    v_transition.reviewed_at::timestamptz;
end;
$$;

create function public.execute_application_intake_automation_intake_v1(
  p_work_id bigint,
  p_claim_token uuid,
  p_access_token_hash text,
  p_encrypted_token text
)
returns table (
  outcome text,
  invitation_job_id uuid,
  request_name text,
  request_company text,
  request_email text,
  intake_id uuid,
  access_token_expires_at timestamptz
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
  v_existing_intake public.quote_request_intakes%rowtype;
  v_invitation record;
  v_now timestamptz;
begin
  if p_access_token_hash is null
     or p_access_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using
      errcode = '22023',
      message = 'INVALID_ACCESS_TOKEN_HASH';
  end if;
  if p_encrypted_token is null
     or p_encrypted_token !~ '^v1\.[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{40,}$' then
    raise exception using
      errcode = '22023',
      message = 'INVALID_ENCRYPTED_TOKEN';
  end if;

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

  select intake.* into v_existing_intake
  from public.quote_request_intakes as intake
  where intake.quote_request_id = v_request.id
  for update;

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
     or v_request.status is distinct from 'approved'::public.quote_request_status
     or v_request.approval_token_hash is null
     or v_request.approval_token_expires_at is null
     or v_request.approval_token_expires_at <= v_now
     or v_work.phase is distinct from 'INTAKE'
     or v_work.approved_at is null
     or v_work.intake_due_at is null
     or v_work.intake_due_at > v_now
     or v_work.claim_token is distinct from p_claim_token
     or v_work.claim_expires_at is null
     or v_work.claim_expires_at <= v_now then
    return;
  end if;

  if found and v_existing_intake.access_state = 'CANCELLED' then
    update lws_internal.application_intake_automation_work as automation_work
    set phase = 'STOPPED',
        claim_token = null,
        claimed_by = null,
        claimed_at = null,
        claim_expires_at = null,
        last_error_code = null,
        terminal_reason = 'INTAKE_CANCELLED'
    where automation_work.work_id = v_work.work_id;

    return query select
      'stopped'::text,
      null::uuid,
      null::text,
      null::text,
      null::text,
      v_existing_intake.id,
      v_existing_intake.access_token_expires_at;
    return;
  end if;

  select invitation.* into v_invitation
  from public.create_quote_request_intake_invitation(
    v_request.approval_token_hash,
    p_access_token_hash,
    p_encrypted_token
  ) as invitation;

  if not found
     or v_invitation.request_id is distinct from v_request.id
     or v_invitation.outcome not in ('invitation_created', 'already_invited')
     or v_invitation.intake_id is null
     or v_invitation.invitation_job_id is null then
    return;
  end if;

  update lws_internal.application_intake_automation_work as automation_work
  set phase = 'COMPLETED',
      claim_token = null,
      claimed_by = null,
      claimed_at = null,
      claim_expires_at = null,
      last_error_code = null,
      terminal_reason = null
  where automation_work.work_id = v_work.work_id
    and automation_work.quote_request_id = v_request.id;

  return query select
    'intake_completed'::text,
    v_invitation.invitation_job_id::uuid,
    v_invitation.request_name::text,
    v_invitation.request_company::text,
    v_invitation.request_email::text,
    v_invitation.intake_id::uuid,
    v_invitation.access_token_expires_at::timestamptz;
end;
$$;

revoke all on function public.execute_application_intake_automation_approval_v1(bigint, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.execute_application_intake_automation_intake_v1(bigint, uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.execute_application_intake_automation_approval_v1(bigint, uuid)
  to service_role;
grant execute on function public.execute_application_intake_automation_intake_v1(bigint, uuid, text, text)
  to service_role;

revoke all on function lws_internal.reconcile_application_intake_automation_review_v1()
  from public, anon, authenticated, service_role;
revoke all on function lws_internal.reconcile_application_intake_automation_intake_v1()
  from public, anon, authenticated, service_role;