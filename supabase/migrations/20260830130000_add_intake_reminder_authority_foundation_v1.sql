create table lws_internal.intake_reminder_evidence (
  intake_id uuid not null
    references lws_internal.intake_identity_anchors(intake_id) on delete restrict,
  access_cycle bigint not null check (access_cycle >= 0),
  reminder_phase text not null check (reminder_phase in ('REMINDER_1', 'REMINDER_2')),
  cycle_started_at timestamptz not null,
  state text not null check (state in ('CLAIMED', 'SENT')),
  claim_token uuid not null,
  claimed_at timestamptz not null,
  claim_expires_at timestamptz not null,
  sent_at timestamptz,
  email_job_id uuid references public.quote_request_email_jobs(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  primary key (intake_id, access_cycle, reminder_phase),
  constraint intake_reminder_evidence_claim_window_valid
    check (claim_expires_at > claimed_at),
  constraint intake_reminder_evidence_state_valid check (
    (state = 'CLAIMED' and sent_at is null and email_job_id is null)
    or
    (state = 'SENT' and sent_at is not null and sent_at >= claimed_at)
  )
);

create index intake_reminder_evidence_state_idx
  on lws_internal.intake_reminder_evidence (state, claim_expires_at);

create function lws_internal.resolve_intake_reminder_access_cycle_v1(
  p_intake_id uuid
)
returns table (
  access_cycle bigint,
  cycle_started_at timestamptz
)
language sql
stable
security definer
set search_path = lws_internal, public, pg_catalog
as $$
  select
    count(event.id) filter (where event.event_type = 'REACTIVATED')::bigint,
    coalesce(
      max(event.occurred_at) filter (where event.event_type = 'REACTIVATED'),
      anchor.original_created_at
    )
  from lws_internal.intake_identity_anchors as anchor
  left join public.quote_request_intake_lifecycle_events as event
    on event.intake_id = anchor.intake_id
  where anchor.intake_id = p_intake_id
  group by anchor.intake_id, anchor.original_created_at
$$;

create function lws_internal.prevent_intake_reminder_evidence_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
declare
  v_transition text := current_setting('lws.intake_reminder_evidence_transition', true);
begin
  if tg_op = 'UPDATE'
     and v_transition = 'RECLAIM'
     and old.state = 'CLAIMED'
     and new.state = 'CLAIMED'
     and row(
       new.intake_id, new.access_cycle, new.reminder_phase,
       new.cycle_started_at, new.sent_at, new.email_job_id, new.created_at
     ) is not distinct from row(
       old.intake_id, old.access_cycle, old.reminder_phase,
       old.cycle_started_at, old.sent_at, old.email_job_id, old.created_at
     )
     and new.claimed_at >= old.claimed_at
     and new.claim_expires_at > new.claimed_at then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and v_transition = 'SENT'
     and old.state = 'CLAIMED'
     and new.state = 'SENT'
     and row(
       new.intake_id, new.access_cycle, new.reminder_phase,
       new.cycle_started_at, new.claim_token, new.claimed_at,
       new.claim_expires_at, new.created_at
     ) is not distinct from row(
       old.intake_id, old.access_cycle, old.reminder_phase,
       old.cycle_started_at, old.claim_token, old.claimed_at,
       old.claim_expires_at, old.created_at
     )
     and new.sent_at is not null
     and new.sent_at >= old.claimed_at then
    return new;
  end if;

  raise exception using
    errcode = '55000',
    message = 'INTAKE_REMINDER_EVIDENCE_IMMUTABLE';
end;
$$;

create trigger trg_intake_reminder_evidence_immutable
before update or delete on lws_internal.intake_reminder_evidence
for each row execute function lws_internal.prevent_intake_reminder_evidence_mutation_v1();

alter table lws_internal.intake_reminder_evidence enable row level security;
alter table lws_internal.intake_reminder_evidence force row level security;

revoke all on table lws_internal.intake_reminder_evidence
from public, anon, authenticated, service_role;

revoke all on function lws_internal.resolve_intake_reminder_access_cycle_v1(uuid)
from public, anon, authenticated, service_role;

revoke all on function lws_internal.prevent_intake_reminder_evidence_mutation_v1()
from public, anon, authenticated, service_role;

create function public.list_intake_reminder_candidates_v1(
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
    and public.resolve_quote_request_intake_effective_access_v1(
      intake.access_state,
      intake.access_token_expires_at,
      p_server_now
    ) = 'ACTIVE'
    and intake.access_token_expires_at > p_server_now
    and (
      evidence.intake_id is null
      or (evidence.state = 'CLAIMED' and evidence.claim_expires_at <= p_server_now)
    )
  order by intake.access_token_expires_at, intake.id
  limit p_limit;
end;
$$;

create function public.claim_intake_reminder_v1(
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

  if not found
     or v_intake.status not in ('invited', 'in_progress')
     or v_intake.access_token_expires_at <= p_server_now
     or public.resolve_quote_request_intake_effective_access_v1(
       v_intake.access_state,
       v_intake.access_token_expires_at,
       p_server_now
     ) <> 'ACTIVE' then
    return;
  end if;

  select * into v_cycle
  from lws_internal.resolve_intake_reminder_access_cycle_v1(p_intake_id);

  if not found then return; end if;

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

create function public.mark_intake_reminder_sent_v1(
  p_intake_id uuid,
  p_access_cycle bigint,
  p_reminder_phase text,
  p_claim_token uuid,
  p_email_job_id uuid default null
)
returns boolean
language plpgsql
volatile
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_evidence lws_internal.intake_reminder_evidence%rowtype;
  v_quote_request_id uuid;
  v_sent_at timestamptz := clock_timestamp();
begin
  if p_intake_id is null
     or p_access_cycle is null
     or p_access_cycle < 0
     or p_reminder_phase not in ('REMINDER_1', 'REMINDER_2')
     or p_claim_token is null then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_REMINDER_COMPLETION';
  end if;

  select evidence.* into v_evidence
  from lws_internal.intake_reminder_evidence as evidence
  where evidence.intake_id = p_intake_id
    and evidence.access_cycle = p_access_cycle
    and evidence.reminder_phase = p_reminder_phase
  for update;

  if not found or v_evidence.claim_token <> p_claim_token then return false; end if;
  if v_evidence.state = 'SENT' then return true; end if;

  if p_email_job_id is not null then
    select anchor.quote_request_id into v_quote_request_id
    from lws_internal.intake_identity_anchors as anchor
    where anchor.intake_id = p_intake_id;

    if not exists (
      select 1
      from public.quote_request_email_jobs as job
      where job.id = p_email_job_id
        and job.quote_request_id = v_quote_request_id
        and job.status = 'sent'
    ) then
      raise exception using errcode = '23503', message = 'INTAKE_REMINDER_EMAIL_JOB_NOT_SENT';
    end if;
  end if;

  perform set_config('lws.intake_reminder_evidence_transition', 'SENT', true);
  update lws_internal.intake_reminder_evidence as evidence
  set state = 'SENT',
      sent_at = v_sent_at,
      email_job_id = p_email_job_id
  where evidence.intake_id = p_intake_id
    and evidence.access_cycle = p_access_cycle
    and evidence.reminder_phase = p_reminder_phase
    and evidence.state = 'CLAIMED'
    and evidence.claim_token = p_claim_token;
  perform set_config('lws.intake_reminder_evidence_transition', '', true);

  return found;
end;
$$;

revoke all on function public.list_intake_reminder_candidates_v1(text, timestamptz, integer)
from public, anon, authenticated, service_role;
revoke all on function public.claim_intake_reminder_v1(uuid, text, timestamptz)
from public, anon, authenticated, service_role;
revoke all on function public.mark_intake_reminder_sent_v1(uuid, bigint, text, uuid, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.list_intake_reminder_candidates_v1(text, timestamptz, integer)
to service_role;
grant execute on function public.claim_intake_reminder_v1(uuid, text, timestamptz)
to service_role;
grant execute on function public.mark_intake_reminder_sent_v1(uuid, bigint, text, uuid, uuid)
to service_role;

comment on table lws_internal.intake_reminder_evidence is
  'Private per-intake, per-reactivation-cycle, per-phase reminder claim and final sent evidence. It stores no customer capability material.';
comment on function lws_internal.resolve_intake_reminder_access_cycle_v1(uuid) is
  'Cycle zero is the initial intake; each immutable REACTIVATED lifecycle event starts the next cycle. RESUMED does not change the cycle.';
comment on function public.list_intake_reminder_candidates_v1(text, timestamptz, integer) is
  'Service-role-only status eligibility projection. Timing policy is intentionally outside this foundation.';
comment on function public.claim_intake_reminder_v1(uuid, text, timestamptz) is
  'Atomically claims at most one reminder phase per current intake access cycle without sending email.';
comment on function public.mark_intake_reminder_sent_v1(uuid, bigint, text, uuid, uuid) is
  'Finalizes one claimed reminder evidence row. Email delivery remains owned by quote_request_email_jobs.';
