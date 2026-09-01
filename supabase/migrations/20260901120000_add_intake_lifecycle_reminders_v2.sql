create or replace function public.quote_request_intake_default_expires_at_v1(
  p_created_at timestamptz
)
returns timestamptz
language sql
immutable
set search_path = pg_catalog
as $$
  select p_created_at + interval '14 days'
$$;

create table lws_internal.intake_lifecycle_evidence_v2 (
  request_kind text not null check (request_kind in ('website', 'slimme_documentenflow')),
  intake_id uuid not null,
  lifecycle_cycle bigint not null check (lifecycle_cycle >= 0),
  reminder_phase text not null check (reminder_phase in ('REMINDER_1', 'REMINDER_2', 'FINAL_WARNING', 'EXPIRY')),
  cycle_started_at timestamptz not null,
  state text not null check (state in ('CLAIMED', 'SENT')),
  claim_token uuid not null,
  claimed_at timestamptz not null,
  claim_expires_at timestamptz not null,
  sent_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  primary key (request_kind, intake_id, lifecycle_cycle, reminder_phase),
  check (claim_expires_at > claimed_at),
  check ((state = 'CLAIMED' and sent_at is null) or (state = 'SENT' and sent_at is not null))
);

create table public.intake_lifecycle_email_jobs_v2 (
  job_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null references public.quote_requests(id) on delete cascade,
  request_kind text not null check (request_kind in ('website', 'slimme_documentenflow')),
  intake_id uuid not null,
  lifecycle_cycle bigint not null check (lifecycle_cycle >= 0),
  reminder_phase text not null check (reminder_phase in ('REMINDER_1', 'REMINDER_2', 'FINAL_WARNING', 'EXPIRY')),
  claim_token uuid not null,
  encrypted_capability text check (encrypted_capability is null or encrypted_capability ~ '^v1\.[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{40,}$'),
  status public.quote_request_email_status not null default 'pending',
  attempt_count integer not null default 0 check (attempt_count between 0 and 20),
  max_attempts integer not null default 5 check (max_attempts between 1 and 20),
  next_attempt_at timestamptz not null default clock_timestamp(),
  delivery_lease_token uuid,
  delivery_lease_expires_at timestamptz,
  sent_at timestamptz,
  provider_message_id text,
  last_error_code text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (request_kind, intake_id, lifecycle_cycle, reminder_phase),
  check ((reminder_phase = 'EXPIRY' and encrypted_capability is null) or reminder_phase <> 'EXPIRY')
);

alter table lws_internal.intake_lifecycle_evidence_v2 enable row level security;
alter table lws_internal.intake_lifecycle_evidence_v2 force row level security;
alter table public.intake_lifecycle_email_jobs_v2 enable row level security;
alter table public.intake_lifecycle_email_jobs_v2 force row level security;
revoke all on table lws_internal.intake_lifecycle_evidence_v2, public.intake_lifecycle_email_jobs_v2
from public, anon, authenticated, service_role;

create function lws_internal.intake_lifecycle_phase_is_due_v2(
  p_reminder_phase text,
  p_server_now timestamptz,
  p_cycle_started_at timestamptz
)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select case p_reminder_phase
    when 'REMINDER_1' then p_server_now >= p_cycle_started_at + interval '3 days' and p_server_now < p_cycle_started_at + interval '7 days'
    when 'REMINDER_2' then p_server_now >= p_cycle_started_at + interval '7 days' and p_server_now < p_cycle_started_at + interval '13 days'
    when 'FINAL_WARNING' then p_server_now >= p_cycle_started_at + interval '13 days' and p_server_now < p_cycle_started_at + interval '14 days'
    when 'EXPIRY' then p_server_now >= p_cycle_started_at + interval '14 days'
    else false
  end
$$;

create function lws_internal.intake_lifecycle_is_eligible_v2(
  p_request_kind text,
  p_intake_id uuid,
  p_access_cycle bigint,
  p_reminder_phase text,
  p_server_now timestamptz
)
returns boolean
language plpgsql
stable
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare v_cycle record;
begin
  if p_request_kind = 'website' then
    select * into v_cycle from lws_internal.resolve_intake_reminder_access_cycle_v1(p_intake_id);
    return exists (
      select 1 from public.quote_request_intakes intake
      join public.quote_requests request on request.id = intake.quote_request_id
        and request.record_classification = 'production' and request.request_kind = 'website'
      where intake.id = p_intake_id and v_cycle.access_cycle = p_access_cycle
        and intake.status in ('invited', 'in_progress') and intake.access_state = 'ACTIVE'
        and lws_internal.intake_lifecycle_phase_is_due_v2(p_reminder_phase, p_server_now, v_cycle.cycle_started_at)
        and ((p_reminder_phase = 'EXPIRY' and intake.access_token_expires_at <= p_server_now)
          or (p_reminder_phase <> 'EXPIRY' and intake.access_token_expires_at > p_server_now))
    );
  elsif p_request_kind = 'slimme_documentenflow' then
    return exists (
      select 1 from public.sdf_qualification_intakes intake
      join public.quote_requests request on request.id = intake.quote_request_id
        and request.record_classification = 'production' and request.request_kind = 'slimme_documentenflow'
      where intake.intake_id = p_intake_id and intake.invitation_generation = p_access_cycle
        and intake.status in ('invited', 'in_progress') and intake.customer_capability_revoked_at is null
        and lws_internal.intake_lifecycle_phase_is_due_v2(p_reminder_phase, p_server_now, intake.invited_at)
        and ((p_reminder_phase = 'EXPIRY' and intake.customer_capability_expires_at <= p_server_now)
          or (p_reminder_phase <> 'EXPIRY' and intake.customer_capability_expires_at > p_server_now))
    );
  end if;
  return false;
end;
$$;

create function public.list_intake_lifecycle_candidates_v2(
  p_reminder_phase text,
  p_server_now timestamptz default clock_timestamp(),
  p_limit integer default 100
)
returns table (
  quote_request_id uuid,
  intake_id uuid,
  request_kind text,
  access_cycle bigint,
  reminder_phase text,
  progress_status text,
  expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = lws_internal, public, pg_catalog
as $$
begin
  if p_reminder_phase not in ('REMINDER_1', 'REMINDER_2', 'FINAL_WARNING', 'EXPIRY')
     or p_server_now is null or p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_LIFECYCLE_CANDIDATE_REQUEST';
  end if;

  return query
  with candidates as (
    select request.id as quote_request_id, intake.id as intake_id, 'website'::text as request_kind,
      cycle.access_cycle, intake.status::text as progress_status,
      intake.access_token_expires_at as expires_at, cycle.cycle_started_at
    from public.quote_request_intakes intake
    join public.quote_requests request on request.id = intake.quote_request_id
      and request.record_classification = 'production' and request.request_kind = 'website'
    cross join lateral lws_internal.resolve_intake_reminder_access_cycle_v1(intake.id) cycle
    where intake.status in ('invited', 'in_progress')
      and intake.access_state = 'ACTIVE'
      and ((p_reminder_phase = 'EXPIRY' and intake.access_token_expires_at <= p_server_now)
        or (p_reminder_phase <> 'EXPIRY' and public.resolve_quote_request_intake_effective_access_v1(intake.access_state, intake.access_token_expires_at, p_server_now) = 'ACTIVE'))
    union all
    select request.id, intake.intake_id, 'slimme_documentenflow'::text,
      intake.invitation_generation::bigint, intake.status::text,
      intake.customer_capability_expires_at, intake.invited_at
    from public.sdf_qualification_intakes intake
    join public.quote_requests request on request.id = intake.quote_request_id
      and request.record_classification = 'production' and request.request_kind = 'slimme_documentenflow'
    where intake.status in ('invited', 'in_progress')
      and intake.customer_capability_revoked_at is null
      and ((p_reminder_phase = 'EXPIRY' and intake.customer_capability_expires_at <= p_server_now)
        or (p_reminder_phase <> 'EXPIRY' and intake.customer_capability_expires_at > p_server_now))
  )
  select candidate.quote_request_id, candidate.intake_id, candidate.request_kind,
    candidate.access_cycle, p_reminder_phase, candidate.progress_status, candidate.expires_at
  from candidates candidate
  left join lws_internal.intake_lifecycle_evidence_v2 evidence
    on evidence.request_kind = candidate.request_kind
    and evidence.intake_id = candidate.intake_id
    and evidence.lifecycle_cycle = candidate.access_cycle
    and evidence.reminder_phase = p_reminder_phase
  where lws_internal.intake_lifecycle_phase_is_due_v2(p_reminder_phase, p_server_now, candidate.cycle_started_at)
    and (evidence.intake_id is null or (evidence.state = 'CLAIMED' and evidence.claim_expires_at <= p_server_now))
  order by candidate.expires_at, candidate.intake_id
  limit p_limit;
end;
$$;

create function public.claim_intake_lifecycle_reminder_v2(
  p_request_kind text,
  p_intake_id uuid,
  p_access_cycle bigint,
  p_reminder_phase text,
  p_server_now timestamptz default clock_timestamp()
)
returns table (intake_id uuid, access_cycle bigint, reminder_phase text, claim_token uuid)
language plpgsql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_claim_token uuid := gen_random_uuid();
begin
  if not exists (
    select 1 from public.list_intake_lifecycle_candidates_v2(p_reminder_phase, p_server_now, 500) candidate
    where candidate.request_kind = p_request_kind and candidate.intake_id = p_intake_id and candidate.access_cycle = p_access_cycle
  ) then return; end if;

  insert into lws_internal.intake_lifecycle_evidence_v2 (
    request_kind, intake_id, lifecycle_cycle, reminder_phase, cycle_started_at,
    state, claim_token, claimed_at, claim_expires_at
  )
  select p_request_kind, p_intake_id, p_access_cycle, p_reminder_phase,
    case when p_request_kind = 'website' then cycle.cycle_started_at else intake.invited_at end,
    'CLAIMED', v_claim_token, p_server_now, p_server_now + interval '5 minutes'
  from (select 1) seed
  left join lateral lws_internal.resolve_intake_reminder_access_cycle_v1(p_intake_id) cycle on p_request_kind = 'website'
  left join public.sdf_qualification_intakes intake on intake.intake_id = p_intake_id and p_request_kind = 'slimme_documentenflow'
  on conflict on constraint intake_lifecycle_evidence_v2_pkey do update
    set claim_token = excluded.claim_token, claimed_at = excluded.claimed_at, claim_expires_at = excluded.claim_expires_at
    where intake_lifecycle_evidence_v2.state = 'CLAIMED'
      and intake_lifecycle_evidence_v2.claim_expires_at <= p_server_now;
  if not found then return; end if;
  return query select p_intake_id, p_access_cycle, p_reminder_phase, v_claim_token;
end;
$$;

create function public.prepare_intake_lifecycle_email_job_v2(
  p_request_kind text,
  p_intake_id uuid,
  p_access_cycle bigint,
  p_reminder_phase text,
  p_claim_token uuid,
  p_server_now timestamptz default clock_timestamp()
)
returns table (outcome text, email_job_id uuid)
language plpgsql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_request_id uuid;
  v_encrypted text;
  v_job public.intake_lifecycle_email_jobs_v2%rowtype;
begin
  if not exists (
    select 1 from lws_internal.intake_lifecycle_evidence_v2 evidence
    where evidence.request_kind = p_request_kind and evidence.intake_id = p_intake_id
      and evidence.lifecycle_cycle = p_access_cycle and evidence.reminder_phase = p_reminder_phase
      and evidence.state = 'CLAIMED' and evidence.claim_token = p_claim_token
  ) or not lws_internal.intake_lifecycle_is_eligible_v2(
    p_request_kind, p_intake_id, p_access_cycle, p_reminder_phase, p_server_now
  ) then return; end if;

  if p_request_kind = 'website' then
    select intake.quote_request_id into v_request_id from public.quote_request_intakes intake where intake.id = p_intake_id;
    if p_reminder_phase <> 'EXPIRY' then
      select escrow.encrypted_capability into v_encrypted from lws_internal.intake_reminder_capability_escrow escrow
      where escrow.intake_id = p_intake_id and escrow.access_cycle = p_access_cycle;
    end if;
  else
    select intake.quote_request_id,
      case when p_reminder_phase = 'EXPIRY' then null else intake.customer_capability_encrypted end
    into v_request_id, v_encrypted
    from public.sdf_qualification_intakes intake
    where intake.intake_id = p_intake_id and intake.invitation_generation = p_access_cycle;
  end if;

  if v_request_id is null then return; end if;
  if p_reminder_phase <> 'EXPIRY' and v_encrypted is null then
    return query select 'CAPABILITY_UNAVAILABLE'::text, null::uuid;
    return;
  end if;

  insert into public.intake_lifecycle_email_jobs_v2 (
    quote_request_id, request_kind, intake_id, lifecycle_cycle, reminder_phase,
    claim_token, encrypted_capability, next_attempt_at
  ) values (
    v_request_id, p_request_kind, p_intake_id, p_access_cycle, p_reminder_phase,
    p_claim_token, v_encrypted, p_server_now
  )
  on conflict (request_kind, intake_id, lifecycle_cycle, reminder_phase) do update
    set claim_token = excluded.claim_token,
        encrypted_capability = excluded.encrypted_capability,
        status = case when intake_lifecycle_email_jobs_v2.status = 'sent' then intake_lifecycle_email_jobs_v2.status else 'pending'::public.quote_request_email_status end,
        next_attempt_at = case when intake_lifecycle_email_jobs_v2.status = 'sent' then intake_lifecycle_email_jobs_v2.next_attempt_at else p_server_now end,
        updated_at = p_server_now
  returning * into v_job;

  return query select case when v_job.status = 'sent' then 'already_sent' else 'prepared' end, v_job.job_id;
end;
$$;

create function public.get_intake_lifecycle_email_delivery_v2(
  p_job_id uuid,
  p_server_now timestamptz default clock_timestamp()
)
returns table (
  email_job_id uuid, reminder_phase text, access_cycle bigint, request_kind text,
  recipient_email text, client_name text, company text, progress_status text,
  expires_at timestamptz, encrypted_token text
)
language sql
stable
security definer
set search_path = lws_internal, public, pg_catalog
as $$
  with context as (
    select intake.id as intake_id, 'website'::text as request_kind,
      intake.status::text as progress_status, intake.access_token_expires_at as expires_at
    from public.quote_request_intakes intake
    union all
    select intake.intake_id, 'slimme_documentenflow'::text,
      intake.status::text, intake.customer_capability_expires_at
    from public.sdf_qualification_intakes intake
  )
  select job.job_id, job.reminder_phase, job.lifecycle_cycle, job.request_kind,
    request.email, request.name, request.company, context.progress_status,
    context.expires_at, job.encrypted_capability
  from public.intake_lifecycle_email_jobs_v2 job
  join public.quote_requests request on request.id = job.quote_request_id and request.record_classification = 'production'
  join context on context.request_kind = job.request_kind and context.intake_id = job.intake_id
  join lws_internal.intake_lifecycle_evidence_v2 evidence
    on evidence.request_kind = job.request_kind and evidence.intake_id = job.intake_id
    and evidence.lifecycle_cycle = job.lifecycle_cycle and evidence.reminder_phase = job.reminder_phase
    and evidence.claim_token = job.claim_token and evidence.state = 'CLAIMED'
  where job.job_id = p_job_id and job.status in ('pending', 'retry_wait') and job.next_attempt_at <= p_server_now
    and lws_internal.intake_lifecycle_is_eligible_v2(
      job.request_kind, job.intake_id, job.lifecycle_cycle, job.reminder_phase, p_server_now
    )
$$;

create function public.get_intake_lifecycle_capability_v2(
  p_request_kind text,
  p_intake_id uuid,
  p_access_cycle bigint
)
returns table (outcome text, access_token_hash text)
language plpgsql
stable
security definer
set search_path = lws_internal, public, pg_catalog
as $$
begin
  if p_request_kind = 'website' then
    return query select capability.outcome, capability.access_token_hash
    from public.get_intake_reminder_capability_v1(p_intake_id, p_access_cycle) capability;
  elsif p_request_kind = 'slimme_documentenflow' then
    return query
    select 'CAPABILITY_AVAILABLE'::text, intake.customer_capability_digest::text
    from public.sdf_qualification_intakes intake
    where intake.intake_id = p_intake_id and intake.invitation_generation = p_access_cycle
      and intake.status in ('invited', 'in_progress') and intake.customer_capability_revoked_at is null
      and intake.customer_capability_expires_at > clock_timestamp();
    if not found then return query select 'CAPABILITY_UNAVAILABLE'::text, null::text; end if;
  else
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_LIFECYCLE_REQUEST_KIND';
  end if;
end;
$$;

create function public.claim_intake_lifecycle_email_job_v2(p_job_id uuid)
returns table (job_id uuid, delivery_lease_token uuid)
language plpgsql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare v_token uuid := gen_random_uuid(); v_now timestamptz := clock_timestamp();
begin
  if not exists(select 1 from public.get_intake_lifecycle_email_delivery_v2(p_job_id, v_now)) then return; end if;
  return query update public.intake_lifecycle_email_jobs_v2 job
  set status = 'processing', attempt_count = job.attempt_count + 1,
      delivery_lease_token = v_token, delivery_lease_expires_at = v_now + interval '10 minutes', updated_at = v_now
  where job.job_id = p_job_id and job.status in ('pending', 'retry_wait') and job.attempt_count < job.max_attempts
  returning job.job_id, v_token;
end;
$$;

create function public.complete_intake_lifecycle_email_job_v2(
  p_job_id uuid,
  p_delivery_lease_token uuid,
  p_succeeded boolean,
  p_retryable boolean,
  p_error_code text default null,
  p_provider_message_id text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare v_job public.intake_lifecycle_email_jobs_v2%rowtype; v_status public.quote_request_email_status; v_now timestamptz := clock_timestamp();
begin
  select * into v_job from public.intake_lifecycle_email_jobs_v2 job
  where job.job_id = p_job_id and job.status = 'processing'
    and job.delivery_lease_token = p_delivery_lease_token and job.delivery_lease_expires_at > v_now
  for update;
  if not found then return null; end if;
  v_status := case when p_succeeded then 'sent'::public.quote_request_email_status
    when p_retryable and v_job.attempt_count < v_job.max_attempts then 'retry_wait'::public.quote_request_email_status
    else 'failed'::public.quote_request_email_status end;
  update public.intake_lifecycle_email_jobs_v2 job
  set status = v_status, next_attempt_at = case when v_status = 'retry_wait' then v_now + interval '5 minutes' else v_now end,
      delivery_lease_token = null, delivery_lease_expires_at = null,
      sent_at = case when p_succeeded then v_now else job.sent_at end,
      provider_message_id = case when p_succeeded then p_provider_message_id else job.provider_message_id end,
      last_error_code = case when p_succeeded then null else left(coalesce(p_error_code, 'UNKNOWN_ERROR'), 120) end,
      encrypted_capability = case when p_succeeded then null else job.encrypted_capability end,
      updated_at = v_now
  where job.job_id = p_job_id;
  if p_succeeded then
    update lws_internal.intake_lifecycle_evidence_v2 evidence
    set state = 'SENT', sent_at = v_now
    where evidence.request_kind = v_job.request_kind and evidence.intake_id = v_job.intake_id
      and evidence.lifecycle_cycle = v_job.lifecycle_cycle and evidence.reminder_phase = v_job.reminder_phase
      and evidence.claim_token = v_job.claim_token and evidence.state = 'CLAIMED';
  end if;
  return jsonb_build_object('status', v_status, 'attempt_count', v_job.attempt_count);
end;
$$;

revoke all on function lws_internal.intake_lifecycle_phase_is_due_v2(text, timestamptz, timestamptz) from public, anon, authenticated, service_role;
revoke all on function lws_internal.intake_lifecycle_is_eligible_v2(text, uuid, bigint, text, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.list_intake_lifecycle_candidates_v2(text, timestamptz, integer) from public, anon, authenticated, service_role;
revoke all on function public.claim_intake_lifecycle_reminder_v2(text, uuid, bigint, text, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.prepare_intake_lifecycle_email_job_v2(text, uuid, bigint, text, uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.get_intake_lifecycle_email_delivery_v2(uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.get_intake_lifecycle_capability_v2(text, uuid, bigint) from public, anon, authenticated, service_role;
revoke all on function public.claim_intake_lifecycle_email_job_v2(uuid) from public, anon, authenticated, service_role;
revoke all on function public.complete_intake_lifecycle_email_job_v2(uuid, uuid, boolean, boolean, text, text) from public, anon, authenticated, service_role;
grant execute on function public.list_intake_lifecycle_candidates_v2(text, timestamptz, integer) to service_role;
grant execute on function public.claim_intake_lifecycle_reminder_v2(text, uuid, bigint, text, timestamptz) to service_role;
grant execute on function public.prepare_intake_lifecycle_email_job_v2(text, uuid, bigint, text, uuid, timestamptz) to service_role;
grant execute on function public.get_intake_lifecycle_email_delivery_v2(uuid, timestamptz) to service_role;
grant execute on function public.get_intake_lifecycle_capability_v2(text, uuid, bigint) to service_role;
grant execute on function public.claim_intake_lifecycle_email_job_v2(uuid) to service_role;
grant execute on function public.complete_intake_lifecycle_email_job_v2(uuid, uuid, boolean, boolean, text, text) to service_role;
