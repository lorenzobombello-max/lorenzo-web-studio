alter type public.quote_request_email_kind
  add value if not exists 'intake_reminder_1';

alter type public.quote_request_email_kind
  add value if not exists 'intake_reminder_2';

alter table public.quote_request_email_jobs
  add column reminder_intake_id uuid
    references lws_internal.intake_identity_anchors(intake_id) on delete restrict,
  add column reminder_access_cycle bigint,
  add column reminder_phase text,
  add column reminder_claim_token uuid;

alter table public.quote_request_email_jobs
  drop constraint quote_request_email_jobs_request_kind_key;

create unique index quote_request_email_jobs_request_kind_non_reminder_key
  on public.quote_request_email_jobs (quote_request_id, kind)
  where reminder_access_cycle is null;

create unique index quote_request_email_jobs_reminder_cycle_key
  on public.quote_request_email_jobs (quote_request_id, kind, reminder_access_cycle)
  where reminder_access_cycle is not null;

alter table public.quote_request_email_jobs
  add constraint quote_request_email_jobs_reminder_binding check (
    (
      reminder_intake_id is null
      and reminder_access_cycle is null
      and reminder_phase is null
      and reminder_claim_token is null
      and kind::text not in ('intake_reminder_1', 'intake_reminder_2')
    )
    or
    (
      reminder_intake_id is not null
      and reminder_access_cycle >= 0
      and reminder_claim_token is not null
      and (
        (reminder_phase = 'REMINDER_1' and kind::text = 'intake_reminder_1')
        or (reminder_phase = 'REMINDER_2' and kind::text = 'intake_reminder_2')
      )
    )
  );

create function lws_internal.intake_reminder_phase_is_due_v1(
  p_reminder_phase text,
  p_server_now timestamptz,
  p_expires_at timestamptz
)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select case p_reminder_phase
    when 'REMINDER_1' then
      p_server_now >= p_expires_at - interval '4 days'
      and p_server_now < p_expires_at - interval '1 day'
      and p_server_now < p_expires_at
    when 'REMINDER_2' then
      p_server_now >= p_expires_at - interval '1 day'
      and p_server_now < p_expires_at
    else false
  end;
$$;

revoke all on function lws_internal.intake_reminder_phase_is_due_v1(text, timestamptz, timestamptz)
from public, anon, authenticated, service_role;

create or replace function public.list_intake_reminder_candidates_v1(
  p_reminder_phase text,
  p_server_now timestamptz default clock_timestamp(),
  p_limit integer default 100
)
returns table (
  quote_request_id uuid,
  intake_id uuid,
  access_cycle bigint,
  reminder_phase text,
  progress_status text,
  intake_created_at timestamptz,
  invitation_sent_at timestamptz,
  started_at timestamptz,
  expires_at timestamptz,
  cycle_started_at timestamptz
)
language plpgsql
stable
security definer
set search_path = lws_internal, public, pg_catalog
as $$
begin
  if p_reminder_phase not in ('REMINDER_1', 'REMINDER_2')
     or p_server_now is null
     or p_limit is null
     or p_limit < 1
     or p_limit > 500 then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_REMINDER_CANDIDATE_REQUEST';
  end if;

  return query
  select
    anchor.quote_request_id,
    intake.id,
    cycle.access_cycle,
    p_reminder_phase,
    intake.status::text,
    intake.created_at,
    invitation.sent_at,
    intake.started_at,
    intake.access_token_expires_at,
    cycle.cycle_started_at
  from public.quote_request_intakes as intake
  join lws_internal.intake_identity_anchors as anchor
    on anchor.intake_id = intake.id
  join public.quote_requests as request
    on request.id = anchor.quote_request_id
   and request.record_classification = 'production'
   and request.request_kind = 'website'
  cross join lateral lws_internal.resolve_intake_reminder_access_cycle_v1(intake.id) as cycle
  left join public.quote_request_email_jobs as invitation
    on invitation.quote_request_id = anchor.quote_request_id
   and invitation.kind = 'intake_invitation'
  left join lws_internal.intake_reminder_evidence as evidence
    on evidence.intake_id = intake.id
   and evidence.access_cycle = cycle.access_cycle
   and evidence.reminder_phase = p_reminder_phase
  where intake.status in ('invited', 'in_progress')
    and p_server_now >= cycle.cycle_started_at
    and public.resolve_quote_request_intake_effective_access_v1(
      intake.access_state,
      intake.access_token_expires_at,
      p_server_now
    ) = 'ACTIVE'
    and lws_internal.intake_reminder_phase_is_due_v1(
      p_reminder_phase,
      p_server_now,
      intake.access_token_expires_at
    )
    and (
      evidence.intake_id is null
      or (evidence.state = 'CLAIMED' and evidence.claim_expires_at <= p_server_now)
    )
  order by intake.access_token_expires_at, intake.id
  limit p_limit;
end;
$$;

create function lws_internal.intake_reminder_email_job_is_eligible_v1(
  p_job_id uuid,
  p_server_now timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = lws_internal, public, pg_catalog
as $$
  select exists (
    select 1
    from public.quote_request_email_jobs as job
    join public.quote_request_intakes as intake
      on intake.id = job.reminder_intake_id
    join lws_internal.intake_identity_anchors as anchor
      on anchor.intake_id = intake.id
     and anchor.quote_request_id = job.quote_request_id
    join public.quote_requests as request
      on request.id = anchor.quote_request_id
     and request.record_classification = 'production'
     and request.request_kind = 'website'
    cross join lateral lws_internal.resolve_intake_reminder_access_cycle_v1(intake.id) as cycle
    join lws_internal.intake_reminder_evidence as evidence
      on evidence.intake_id = intake.id
     and evidence.access_cycle = cycle.access_cycle
     and evidence.reminder_phase = job.reminder_phase
     and evidence.claim_token = job.reminder_claim_token
     and evidence.state = 'CLAIMED'
    where job.id = p_job_id
      and job.reminder_access_cycle = cycle.access_cycle
      and p_server_now >= cycle.cycle_started_at
      and intake.status in ('invited', 'in_progress')
      and public.resolve_quote_request_intake_effective_access_v1(
        intake.access_state,
        intake.access_token_expires_at,
        p_server_now
      ) = 'ACTIVE'
      and lws_internal.intake_reminder_phase_is_due_v1(
        job.reminder_phase,
        p_server_now,
        intake.access_token_expires_at
      )
  );
$$;

revoke all on function lws_internal.intake_reminder_email_job_is_eligible_v1(uuid, timestamptz)
from public, anon, authenticated, service_role;

create function public.prepare_intake_reminder_email_job_v1(
  p_intake_id uuid,
  p_access_cycle bigint,
  p_reminder_phase text,
  p_claim_token uuid,
  p_encrypted_token text,
  p_server_now timestamptz default clock_timestamp()
)
returns table (
  outcome text,
  email_job_id uuid,
  email_job_status text,
  quote_request_id uuid,
  recipient_email text,
  client_name text,
  company text,
  progress_status text,
  expires_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_intake public.quote_request_intakes%rowtype;
  v_request public.quote_requests%rowtype;
  v_cycle record;
  v_evidence lws_internal.intake_reminder_evidence%rowtype;
  v_job public.quote_request_email_jobs%rowtype;
  v_kind public.quote_request_email_kind;
begin
  if p_intake_id is null
     or p_access_cycle is null
     or p_access_cycle < 0
     or p_reminder_phase not in ('REMINDER_1', 'REMINDER_2')
     or p_claim_token is null
     or p_encrypted_token is null
     or p_encrypted_token !~ '^v1\.[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{40,}$'
     or p_server_now is null then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_REMINDER_EMAIL_PREPARATION';
  end if;

  select intake.* into v_intake
  from public.quote_request_intakes as intake
  where intake.id = p_intake_id
  for update;

  if not found then return; end if;

  select request.* into v_request
  from lws_internal.intake_identity_anchors as anchor
  join public.quote_requests as request
    on request.id = anchor.quote_request_id
   and request.record_classification = 'production'
   and request.request_kind = 'website'
  where anchor.intake_id = p_intake_id;

  if not found then return; end if;

  select * into v_cycle
  from lws_internal.resolve_intake_reminder_access_cycle_v1(p_intake_id);

  select evidence.* into v_evidence
  from lws_internal.intake_reminder_evidence as evidence
  where evidence.intake_id = p_intake_id
    and evidence.access_cycle = p_access_cycle
    and evidence.reminder_phase = p_reminder_phase
  for update;

  if not found
     or v_cycle.access_cycle <> p_access_cycle
     or v_evidence.state <> 'CLAIMED'
     or v_evidence.claim_token <> p_claim_token
     or v_intake.status not in ('invited', 'in_progress')
     or p_server_now < v_cycle.cycle_started_at
     or public.resolve_quote_request_intake_effective_access_v1(
       v_intake.access_state,
       v_intake.access_token_expires_at,
       p_server_now
     ) <> 'ACTIVE'
     or not lws_internal.intake_reminder_phase_is_due_v1(
       p_reminder_phase,
       p_server_now,
       v_intake.access_token_expires_at
     ) then
    return;
  end if;

  v_kind := case p_reminder_phase
    when 'REMINDER_1' then 'intake_reminder_1'::public.quote_request_email_kind
    else 'intake_reminder_2'::public.quote_request_email_kind
  end;

  select job.* into v_job
  from public.quote_request_email_jobs as job
  where job.quote_request_id = v_request.id
    and job.kind = v_kind
    and job.reminder_access_cycle = p_access_cycle
  for update;

  if found then
    update public.quote_request_email_jobs as job
    set encrypted_payload = p_encrypted_token,
        reminder_claim_token = p_claim_token,
        status = case when job.status = 'sent' then job.status else 'pending'::public.quote_request_email_status end,
        attempt_count = case when job.status = 'sent' then job.attempt_count else 0 end,
        stale_recovery_count = case when job.status = 'sent' then job.stale_recovery_count else 0 end,
        next_attempt_at = case when job.status = 'sent' then job.next_attempt_at else now() end,
        locked_at = case when job.status = 'sent' then job.locked_at else null end,
        last_error_code = case when job.status = 'sent' then job.last_error_code else null end
    where job.id = v_job.id
    returning job.* into v_job;
  else
    insert into public.quote_request_email_jobs (
      quote_request_id,
      kind,
      encrypted_payload,
      reminder_intake_id,
      reminder_access_cycle,
      reminder_phase,
      reminder_claim_token
    ) values (
      v_request.id,
      v_kind,
      p_encrypted_token,
      p_intake_id,
      p_access_cycle,
      p_reminder_phase,
      p_claim_token
    )
    returning * into v_job;
  end if;

  return query select
    case when v_job.status = 'sent' then 'already_sent'::text else 'prepared'::text end,
    v_job.id,
    v_job.status::text,
    v_request.id,
    v_request.email,
    v_request.name,
    v_request.company,
    v_intake.status::text,
    v_intake.access_token_expires_at;
end;
$$;

create function public.get_intake_reminder_email_delivery_v1(
  p_job_id uuid,
  p_server_now timestamptz default clock_timestamp()
)
returns table (
  email_job_id uuid,
  reminder_phase text,
  access_cycle bigint,
  recipient_email text,
  client_name text,
  company text,
  progress_status text,
  expires_at timestamptz,
  encrypted_token text
)
language sql
stable
security definer
set search_path = lws_internal, public, pg_catalog
as $$
  select
    job.id,
    job.reminder_phase,
    job.reminder_access_cycle,
    request.email,
    request.name,
    request.company,
    intake.status::text,
    intake.access_token_expires_at,
    job.encrypted_payload
  from public.quote_request_email_jobs as job
  join public.quote_request_intakes as intake
    on intake.id = job.reminder_intake_id
  join public.quote_requests as request
    on request.id = job.quote_request_id
  where job.id = p_job_id
    and job.status in ('pending', 'retry_wait', 'processing')
    and job.encrypted_payload is not null
    and lws_internal.intake_reminder_email_job_is_eligible_v1(job.id, p_server_now);
$$;

create or replace function public.claim_quote_request_email_job(p_job_id uuid)
returns table (
  job_id uuid,
  quote_request_id uuid,
  kind text,
  attempt_count integer,
  max_attempts integer,
  stale_recovery_count integer,
  max_stale_recoveries integer
)
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.quote_request_email_jobs as jobs
    set status = 'failed',
        locked_at = null,
        next_attempt_at = now(),
        last_error_code = 'REMINDER_NOT_ELIGIBLE',
        encrypted_payload = null
    where jobs.id = p_job_id
      and jobs.reminder_intake_id is not null
      and jobs.status in ('pending', 'processing', 'retry_wait')
      and not lws_internal.intake_reminder_email_job_is_eligible_v1(jobs.id, now());

  update public.quote_request_email_jobs as jobs
    set status = 'failed',
        locked_at = null,
        next_attempt_at = now(),
        last_error_code = 'STALE_RECOVERY_EXHAUSTED'
    where jobs.id = p_job_id
      and jobs.status = 'processing'
      and jobs.locked_at < now() - interval '5 minutes'
      and jobs.stale_recovery_count >= jobs.max_stale_recoveries;

  return query
  update public.quote_request_email_jobs as jobs
    set status = 'processing',
        attempt_count = case
          when jobs.status = 'processing' then jobs.attempt_count
          else jobs.attempt_count + 1
        end,
        stale_recovery_count = case
          when jobs.status = 'processing' then jobs.stale_recovery_count + 1
          else 0
        end,
        locked_at = now(),
        last_attempt_at = now(),
        last_error_code = null
    where jobs.id = p_job_id
      and (
        (jobs.status in ('pending', 'retry_wait') and jobs.next_attempt_at <= now())
        or (
          jobs.status = 'processing'
          and jobs.locked_at < now() - interval '5 minutes'
          and jobs.stale_recovery_count < jobs.max_stale_recoveries
        )
      )
      and (
        jobs.status = 'processing'
        or jobs.attempt_count < jobs.max_attempts
      )
    returning
      jobs.id,
      jobs.quote_request_id,
      jobs.kind::text,
      jobs.attempt_count,
      jobs.max_attempts,
      jobs.stale_recovery_count,
      jobs.max_stale_recoveries;
end;
$$;

create or replace function public.clear_sent_intake_invitation_payload()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.kind::text in ('intake_invitation', 'intake_reminder_1', 'intake_reminder_2')
     and new.status = 'sent' then
    new.encrypted_payload := null;
  end if;
  return new;
end;
$$;

create function lws_internal.finalize_sent_intake_reminder_email_job_v1()
returns trigger
language plpgsql
security definer
set search_path = lws_internal, public, pg_catalog
as $$
begin
  if new.reminder_intake_id is null or new.status <> 'sent' or old.status = 'sent' then
    return new;
  end if;

  perform set_config('lws.intake_reminder_evidence_transition', 'SENT', true);
  update lws_internal.intake_reminder_evidence as evidence
  set state = 'SENT',
      sent_at = clock_timestamp(),
      email_job_id = new.id
  where evidence.intake_id = new.reminder_intake_id
    and evidence.access_cycle = new.reminder_access_cycle
    and evidence.reminder_phase = new.reminder_phase
    and evidence.claim_token = new.reminder_claim_token
    and evidence.state = 'CLAIMED';
  perform set_config('lws.intake_reminder_evidence_transition', '', true);

  if not found then
    raise exception using errcode = '55000', message = 'INTAKE_REMINDER_EVIDENCE_FINALIZATION_FAILED';
  end if;
  return new;
end;
$$;

create trigger trg_finalize_sent_intake_reminder_email_job
  after update of status on public.quote_request_email_jobs
  for each row
  when (new.status = 'sent' and new.reminder_intake_id is not null)
  execute function lws_internal.finalize_sent_intake_reminder_email_job_v1();

revoke all on function lws_internal.finalize_sent_intake_reminder_email_job_v1()
from public, anon, authenticated, service_role;

revoke all on function public.prepare_intake_reminder_email_job_v1(uuid, bigint, text, uuid, text, timestamptz)
from public, anon, authenticated, service_role;
revoke all on function public.get_intake_reminder_email_delivery_v1(uuid, timestamptz)
from public, anon, authenticated, service_role;

grant execute on function public.prepare_intake_reminder_email_job_v1(uuid, bigint, text, uuid, text, timestamptz)
to service_role;
grant execute on function public.get_intake_reminder_email_delivery_v1(uuid, timestamptz)
to service_role;

comment on function lws_internal.intake_reminder_phase_is_due_v1(text, timestamptz, timestamptz) is
  'Expiry-relative reminder policy: REMINDER_1 is due from four days until one day before expiry; REMINDER_2 is due during the final day before expiry.';
comment on function public.prepare_intake_reminder_email_job_v1(uuid, bigint, text, uuid, text, timestamptz) is
  'Creates one encrypted, cycle-bound reminder email job after validating the current reminder claim and expiry-relative policy. It performs no delivery.';
comment on function public.get_intake_reminder_email_delivery_v1(uuid, timestamptz) is
  'Service-only reminder email context projection with a final current-cycle eligibility recheck. It performs no delivery.';

create or replace function public.claim_intake_reminder_v1(
  p_intake_id uuid,
  p_reminder_phase text,
  p_server_now timestamptz default clock_timestamp()
)
returns table (
  intake_id uuid,
  access_cycle bigint,
  reminder_phase text,
  claim_token uuid,
  claim_expires_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_intake public.quote_request_intakes%rowtype;
  v_cycle record;
  v_existing lws_internal.intake_reminder_evidence%rowtype;
  v_claim_token uuid := gen_random_uuid();
begin
  if p_intake_id is null
     or p_reminder_phase not in ('REMINDER_1', 'REMINDER_2')
     or p_server_now is null then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_REMINDER_CLAIM';
  end if;

  select intake.* into v_intake
  from public.quote_request_intakes as intake
  join lws_internal.intake_identity_anchors as anchor on anchor.intake_id = intake.id
  join public.quote_requests as request
    on request.id = anchor.quote_request_id
   and request.record_classification = 'production'
   and request.request_kind = 'website'
  where intake.id = p_intake_id
  for update of intake;

  if not found then return; end if;

  select * into v_cycle
  from lws_internal.resolve_intake_reminder_access_cycle_v1(p_intake_id);

  if not found
     or v_intake.status not in ('invited', 'in_progress')
     or p_server_now < v_cycle.cycle_started_at
     or public.resolve_quote_request_intake_effective_access_v1(
       v_intake.access_state,
       v_intake.access_token_expires_at,
       p_server_now
     ) <> 'ACTIVE'
     or not lws_internal.intake_reminder_phase_is_due_v1(
       p_reminder_phase,
       p_server_now,
       v_intake.access_token_expires_at
     ) then
    return;
  end if;

  select * into v_existing
  from lws_internal.intake_reminder_evidence as evidence
  where evidence.intake_id = p_intake_id
    and evidence.access_cycle = v_cycle.access_cycle
    and evidence.reminder_phase = p_reminder_phase
  for update;

  if found then
    if v_existing.state = 'SENT' or v_existing.claim_expires_at > p_server_now then
      return;
    end if;

    perform set_config('lws.intake_reminder_evidence_transition', 'RECLAIM', true);
    update lws_internal.intake_reminder_evidence as evidence
    set claim_token = v_claim_token,
        claimed_at = p_server_now,
        claim_expires_at = p_server_now + interval '5 minutes'
    where evidence.intake_id = p_intake_id
      and evidence.access_cycle = v_cycle.access_cycle
      and evidence.reminder_phase = p_reminder_phase;
    perform set_config('lws.intake_reminder_evidence_transition', '', true);

    return query select
      p_intake_id,
      v_cycle.access_cycle,
      p_reminder_phase,
      v_claim_token,
      p_server_now + interval '5 minutes';
    return;
  end if;

  insert into lws_internal.intake_reminder_evidence (
    intake_id,
    access_cycle,
    reminder_phase,
    cycle_started_at,
    state,
    claim_token,
    claimed_at,
    claim_expires_at
  ) values (
    p_intake_id,
    v_cycle.access_cycle,
    p_reminder_phase,
    v_cycle.cycle_started_at,
    'CLAIMED',
    v_claim_token,
    p_server_now,
    p_server_now + interval '5 minutes'
  )
  on conflict on constraint intake_reminder_evidence_pkey do nothing;

  if not found then return; end if;

  return query select
    p_intake_id,
    v_cycle.access_cycle,
    p_reminder_phase,
    v_claim_token,
    p_server_now + interval '5 minutes';
end;
$$;

create or replace view lws_internal.operator_pending_intakes_v1 as
select
  request.id as quote_request_id,
  intake.id as intake_id,
  request.name,
  request.company as organization,
  request.email,
  request.phone,
  request.request_kind,
  request.website_type,
  intake.created_at as invitation_created_at,
  invitation.sent_at as invitation_sent_at,
  intake.status::text as intake_status,
  public.resolve_quote_request_intake_effective_access_v1(
    intake.access_state,
    intake.access_token_expires_at,
    statement_timestamp()
  ) as effective_access,
  intake.access_token_expires_at,
  intake.lifecycle_revision,
  coalesce(retention.retention_state, 'ACTIVE') as retention_state,
  retention.archived_at,
  retention.revision as retention_revision,
  delete_check.delete_block_reason is null as can_permanently_delete,
  delete_check.delete_block_reason,
  intake.started_at,
  cycle.access_cycle as current_reminder_cycle,
  reminder_1.sent_at as reminder_1_sent_at,
  reminder_2.sent_at as reminder_2_sent_at
from public.quote_request_intakes as intake
join public.quote_requests as request
  on request.id = intake.quote_request_id
 and request.record_classification = 'production'
 and request.request_kind = 'website'
left join public.quote_request_email_jobs as invitation
  on invitation.quote_request_id = request.id
 and invitation.kind = 'intake_invitation'
left join lws_internal.operator_pending_intake_retention as retention
  on retention.intake_id = intake.id
cross join lateral (
  select lws_internal.pending_intake_delete_block_reason_v1(intake.id, request.id) as delete_block_reason
) as delete_check
cross join lateral lws_internal.resolve_intake_reminder_access_cycle_v1(intake.id) as cycle
left join lws_internal.intake_reminder_evidence as reminder_1
  on reminder_1.intake_id = intake.id
 and reminder_1.access_cycle = cycle.access_cycle
 and reminder_1.reminder_phase = 'REMINDER_1'
 and reminder_1.state = 'SENT'
left join lws_internal.intake_reminder_evidence as reminder_2
  on reminder_2.intake_id = intake.id
 and reminder_2.access_cycle = cycle.access_cycle
 and reminder_2.reminder_phase = 'REMINDER_2'
 and reminder_2.state = 'SENT'
where intake.status in ('invited', 'in_progress');

create or replace function public.list_operator_pending_intakes_v1(
  p_actor_auth_user_id uuid,
  p_retention_state text default 'ACTIVE'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_items jsonb;
begin
  perform lws_internal.assert_operator_application_actor_v2(p_actor_auth_user_id);
  if p_retention_state not in ('ACTIVE', 'ARCHIVED') then
    raise exception using errcode = '22023', message = 'INVALID_PENDING_INTAKE_RETENTION_STATE';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'quote_request_id', pending.quote_request_id,
    'intake_id', pending.intake_id,
    'name', pending.name,
    'organization', pending.organization,
    'email', pending.email,
    'phone', pending.phone,
    'request_kind', pending.request_kind,
    'website_type', pending.website_type,
    'invitation_created_at', pending.invitation_created_at,
    'invitation_sent_at', pending.invitation_sent_at,
    'intake_status', pending.intake_status,
    'effective_access', pending.effective_access,
    'access_token_expires_at', pending.access_token_expires_at,
    'lifecycle_revision', pending.lifecycle_revision,
    'retention_state', pending.retention_state,
    'archived_at', pending.archived_at,
    'retention_revision', coalesce(pending.retention_revision, 0),
    'can_permanently_delete', pending.can_permanently_delete,
    'delete_block_reason', pending.delete_block_reason,
    'started_at', pending.started_at,
    'current_reminder_cycle', pending.current_reminder_cycle,
    'reminder_1_sent_at', pending.reminder_1_sent_at,
    'reminder_2_sent_at', pending.reminder_2_sent_at
  ) order by pending.invitation_created_at desc, pending.quote_request_id desc), '[]'::jsonb)
  into v_items
  from lws_internal.operator_pending_intakes_v1 as pending
  where pending.retention_state = p_retention_state;

  return jsonb_build_object('items', v_items);
end;
$$;
