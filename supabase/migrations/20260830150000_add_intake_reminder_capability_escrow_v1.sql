create table lws_internal.intake_reminder_capability_escrow (
  intake_id uuid not null
    references public.quote_request_intakes(id) on delete cascade,
  access_cycle bigint not null check (access_cycle >= 0),
  encrypted_capability text not null
    check (encrypted_capability ~ '^v1\.[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{40,}$'),
  copied_from_cycle bigint,
  created_at timestamptz not null default clock_timestamp(),
  primary key (intake_id, access_cycle),
  constraint intake_reminder_capability_escrow_copy_valid check (
    copied_from_cycle is null
    or (copied_from_cycle >= 0 and copied_from_cycle < access_cycle)
  )
);

alter table lws_internal.intake_reminder_capability_escrow enable row level security;
alter table lws_internal.intake_reminder_capability_escrow force row level security;

revoke all on table lws_internal.intake_reminder_capability_escrow
from public, anon, authenticated, service_role;

create function lws_internal.copy_intake_reminder_capability_to_reactivated_cycle_v1()
returns trigger
language plpgsql
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_new_cycle bigint;
begin
  if new.event_type <> 'REACTIVATED' then return new; end if;

  select count(*)::bigint into v_new_cycle
  from public.quote_request_intake_lifecycle_events as event
  where event.intake_id = new.intake_id
    and event.event_type = 'REACTIVATED';

  insert into lws_internal.intake_reminder_capability_escrow (
    intake_id,
    access_cycle,
    encrypted_capability,
    copied_from_cycle
  )
  select
    previous.intake_id,
    v_new_cycle,
    previous.encrypted_capability,
    previous.access_cycle
  from lws_internal.intake_reminder_capability_escrow as previous
  where previous.intake_id = new.intake_id
    and previous.access_cycle < v_new_cycle
  order by previous.access_cycle desc
  limit 1
  on conflict (intake_id, access_cycle) do nothing;

  return new;
end;
$$;

create trigger trg_copy_intake_reminder_capability_to_reactivated_cycle
  after insert on public.quote_request_intake_lifecycle_events
  for each row
  when (new.event_type = 'REACTIVATED')
  execute function lws_internal.copy_intake_reminder_capability_to_reactivated_cycle_v1();

create function lws_internal.clear_terminal_intake_reminder_capability_v1()
returns trigger
language plpgsql
security definer
set search_path = lws_internal, public, pg_catalog
as $$
begin
  if new.status::text in ('submitted', 'reviewed')
     or new.access_state = 'CANCELLED' then
    delete from lws_internal.intake_reminder_capability_escrow as escrow
    where escrow.intake_id = new.id;
  end if;
  return new;
end;
$$;

create trigger trg_clear_terminal_intake_reminder_capability
  after update of status, access_state on public.quote_request_intakes
  for each row
  when (
    new.status is distinct from old.status
    or new.access_state is distinct from old.access_state
  )
  execute function lws_internal.clear_terminal_intake_reminder_capability_v1();

revoke all on function lws_internal.copy_intake_reminder_capability_to_reactivated_cycle_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.clear_terminal_intake_reminder_capability_v1()
from public, anon, authenticated, service_role;

create or replace function public.create_quote_request_intake_invitation(
  p_approval_token_hash text,
  p_access_token_hash text,
  p_encrypted_token text
)
returns table (
  outcome text,
  request_id uuid,
  request_name text,
  request_company text,
  request_email text,
  intake_id uuid,
  access_token_expires_at timestamptz,
  invitation_job_id uuid,
  invitation_job_status text
)
language plpgsql
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_request public.quote_requests%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_job public.quote_request_email_jobs%rowtype;
  v_created_at timestamptz;
begin
  if p_approval_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_APPROVAL_TOKEN_HASH';
  end if;
  if p_access_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_ACCESS_TOKEN_HASH';
  end if;
  if p_encrypted_token !~ '^v1\.[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{40,}$' then
    raise exception using errcode = '22023', message = 'INVALID_ENCRYPTED_TOKEN';
  end if;

  select request.* into v_request
  from public.quote_requests as request
  where request.approval_token_hash = p_approval_token_hash
  for update;

  if not found
     or v_request.status <> 'approved'
     or v_request.approval_token_expires_at is null
     or v_request.approval_token_expires_at <= clock_timestamp() then
    return query select
      'not_allowed'::text,
      null::uuid, null::text, null::text, null::text,
      null::uuid, null::timestamptz, null::uuid, null::text;
    return;
  end if;

  select intake.* into v_intake
  from public.quote_request_intakes as intake
  where intake.quote_request_id = v_request.id;

  if found then
    select job.* into v_job
    from public.quote_request_email_jobs as job
    where job.quote_request_id = v_request.id
      and job.kind = 'intake_invitation';

    if found and v_job.encrypted_payload is not null then
      insert into lws_internal.intake_reminder_capability_escrow (
        intake_id,
        access_cycle,
        encrypted_capability
      ) values (
        v_intake.id,
        0,
        v_job.encrypted_payload
      )
      on conflict on constraint intake_reminder_capability_escrow_pkey do nothing;
    end if;

    return query select
      case when v_job.id is not null then 'already_invited'::text else 'not_deliverable'::text end,
      v_request.id,
      v_request.name,
      v_request.company,
      v_request.email,
      v_intake.id,
      v_intake.access_token_expires_at,
      v_job.id,
      v_job.status::text;
    return;
  end if;

  v_created_at := clock_timestamp();

  insert into public.quote_request_intakes (
    quote_request_id,
    status,
    access_token_hash,
    access_token_expires_at,
    access_token_revoked_at,
    created_at,
    updated_at
  ) values (
    v_request.id,
    'invited',
    p_access_token_hash,
    public.quote_request_intake_default_expires_at_v1(v_created_at),
    null,
    v_created_at,
    v_created_at
  )
  returning * into v_intake;

  insert into public.quote_request_email_jobs (
    quote_request_id,
    kind,
    encrypted_payload
  ) values (
    v_request.id,
    'intake_invitation',
    p_encrypted_token
  )
  returning * into v_job;

  insert into lws_internal.intake_reminder_capability_escrow (
    intake_id,
    access_cycle,
    encrypted_capability
  ) values (
    v_intake.id,
    0,
    p_encrypted_token
  );

  return query select
    'invitation_created'::text,
    v_request.id,
    v_request.name,
    v_request.company,
    v_request.email,
    v_intake.id,
    v_intake.access_token_expires_at,
    v_job.id,
    v_job.status::text;
end;
$$;

create function public.get_intake_reminder_capability_v1(
  p_intake_id uuid,
  p_access_cycle bigint
)
returns table (
  outcome text,
  encrypted_capability text,
  access_token_hash text
)
language plpgsql
stable
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_current_cycle bigint;
  v_intake public.quote_request_intakes%rowtype;
  v_encrypted_capability text;
begin
  if p_intake_id is null or p_access_cycle is null or p_access_cycle < 0 then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_REMINDER_CAPABILITY_REQUEST';
  end if;

  select cycle.access_cycle into v_current_cycle
  from lws_internal.resolve_intake_reminder_access_cycle_v1(p_intake_id) as cycle;

  if not found or v_current_cycle <> p_access_cycle then
    return query select 'CAPABILITY_UNAVAILABLE'::text, null::text, null::text;
    return;
  end if;

  select intake.* into v_intake
  from public.quote_request_intakes as intake
  where intake.id = p_intake_id;

  if not found
     or v_intake.status not in ('invited', 'in_progress')
     or public.resolve_quote_request_intake_effective_access_v1(
       v_intake.access_state,
       v_intake.access_token_expires_at,
       clock_timestamp()
     ) <> 'ACTIVE' then
    return query select 'CAPABILITY_UNAVAILABLE'::text, null::text, null::text;
    return;
  end if;

  select escrow.encrypted_capability into v_encrypted_capability
  from lws_internal.intake_reminder_capability_escrow as escrow
  where escrow.intake_id = p_intake_id
    and escrow.access_cycle = p_access_cycle;

  if not found then
    return query select 'CAPABILITY_UNAVAILABLE'::text, null::text, null::text;
    return;
  end if;

  return query select
    'CAPABILITY_AVAILABLE'::text,
    v_encrypted_capability,
    v_intake.access_token_hash;
end;
$$;

revoke all on function public.get_intake_reminder_capability_v1(uuid, bigint)
from public, anon, authenticated, service_role;
grant execute on function public.get_intake_reminder_capability_v1(uuid, bigint)
to service_role;

drop function public.prepare_intake_reminder_email_job_v1(uuid, bigint, text, uuid, text, timestamptz);

create function public.prepare_intake_reminder_email_job_v1(
  p_intake_id uuid,
  p_access_cycle bigint,
  p_reminder_phase text,
  p_claim_token uuid,
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
  v_encrypted_capability text;
begin
  if p_intake_id is null
     or p_access_cycle is null
     or p_access_cycle < 0
     or p_reminder_phase not in ('REMINDER_1', 'REMINDER_2')
     or p_claim_token is null
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

  select escrow.encrypted_capability into v_encrypted_capability
  from lws_internal.intake_reminder_capability_escrow as escrow
  where escrow.intake_id = p_intake_id
    and escrow.access_cycle = p_access_cycle;

  if not found then
    return query select
      'CAPABILITY_UNAVAILABLE'::text,
      null::uuid, null::text, null::uuid, null::text,
      null::text, null::text, null::text, null::timestamptz;
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
    set encrypted_payload = v_encrypted_capability,
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
      v_encrypted_capability,
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

revoke all on function public.prepare_intake_reminder_email_job_v1(uuid, bigint, text, uuid, timestamptz)
from public, anon, authenticated, service_role;
grant execute on function public.prepare_intake_reminder_email_job_v1(uuid, bigint, text, uuid, timestamptz)
to service_role;

comment on table lws_internal.intake_reminder_capability_escrow is
  'Private ciphertext-only escrow for the current intake access capability. It preserves no plaintext and is copied across reactivation only because the access-token hash remains unchanged.';
comment on function public.get_intake_reminder_capability_v1(uuid, bigint) is
  'Service-only current-cycle ciphertext and hash-binding retrieval. Legacy intakes without escrow return CAPABILITY_UNAVAILABLE.';
comment on function public.prepare_intake_reminder_email_job_v1(uuid, bigint, text, uuid, timestamptz) is
  'Prepares a cycle-bound reminder email job from private capability escrow. Missing escrow returns CAPABILITY_UNAVAILABLE and creates no job.';
