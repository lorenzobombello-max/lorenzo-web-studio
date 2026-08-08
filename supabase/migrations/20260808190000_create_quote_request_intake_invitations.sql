alter type public.quote_request_email_kind
  add value if not exists 'intake_invitation';

alter table public.quote_request_email_jobs
  add column if not exists encrypted_payload text;

alter table public.quote_request_email_jobs
  drop constraint if exists quote_request_email_jobs_encrypted_payload_check;

alter table public.quote_request_email_jobs
  add constraint quote_request_email_jobs_encrypted_payload_check
  check (encrypted_payload is null or char_length(encrypted_payload) between 40 and 4096);

create or replace function public.clear_sent_intake_invitation_payload()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.kind = 'intake_invitation'
     and new.status = 'sent' then
    new.encrypted_payload := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_clear_sent_intake_invitation_payload
on public.quote_request_email_jobs;

create trigger trg_clear_sent_intake_invitation_payload
before insert or update on public.quote_request_email_jobs
for each row
execute function public.clear_sent_intake_invitation_payload();

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
set search_path = public
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

  select *
    into v_request
    from public.quote_requests
    where approval_token_hash = p_approval_token_hash
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

  select *
    into v_intake
    from public.quote_request_intakes
    where quote_request_id = v_request.id;

  if found then
    select *
      into v_job
      from public.quote_request_email_jobs
      where quote_request_id = v_request.id
        and kind = 'intake_invitation';

    return query select
      case when found then 'already_invited'::text else 'not_deliverable'::text end,
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
    v_created_at + interval '14 days',
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

create or replace function public.get_quote_request_intake_invitation(
  p_approval_token_hash text
)
returns table (
  outcome text,
  request_id uuid,
  request_name text,
  request_company text,
  request_email text,
  access_token_hash text,
  access_token_expires_at timestamptz,
  invitation_job_id uuid,
  invitation_job_status text,
  encrypted_token text
)
language sql
security definer
set search_path = public
as $$
  select
    case
      when request.status <> 'approved'
        or request.approval_token_expires_at is null
        or request.approval_token_expires_at <= clock_timestamp() then 'not_allowed'
      when job.status = 'sent' then 'already_invited'
      when intake.id is null or job.id is null or job.encrypted_payload is null then 'not_deliverable'
      else 'retryable'
    end,
    request.id,
    request.name,
    request.company,
    request.email,
    intake.access_token_hash,
    intake.access_token_expires_at,
    job.id,
    job.status::text,
    job.encrypted_payload
  from public.quote_requests as request
  left join public.quote_request_intakes as intake
    on intake.quote_request_id = request.id
  left join public.quote_request_email_jobs as job
    on job.quote_request_id = request.id
   and job.kind::text = 'intake_invitation'
  where request.approval_token_hash = p_approval_token_hash
  limit 1
$$;

revoke all
on function public.clear_sent_intake_invitation_payload()
from public, anon, authenticated;

revoke all
on function public.create_quote_request_intake_invitation(text, text, text)
from public, anon, authenticated;

revoke all
on function public.get_quote_request_intake_invitation(text)
from public, anon, authenticated;

grant execute
on function public.create_quote_request_intake_invitation(text, text, text)
to service_role;

grant execute
on function public.get_quote_request_intake_invitation(text)
to service_role;