do $$
begin
  create type public.quote_request_email_kind as enum ('admin_notification', 'customer_confirmation');
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.quote_request_email_status as enum ('pending', 'processing', 'sent', 'retry_wait', 'failed');
exception
  when duplicate_object then null;
end
$$;

alter table public.quote_requests
  add column if not exists idempotency_key uuid,
  add column if not exists request_fingerprint text;

create unique index if not exists idx_quote_requests_idempotency_key
  on public.quote_requests (idempotency_key)
  where idempotency_key is not null;

create unique index if not exists idx_quote_requests_approval_token_hash_all
  on public.quote_requests (approval_token_hash)
  where approval_token_hash is not null;

create table if not exists public.quote_request_email_jobs (
  id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null references public.quote_requests (id) on delete cascade,
  kind public.quote_request_email_kind not null,
  status public.quote_request_email_status not null default 'pending',
  attempt_count integer not null default 0 check (attempt_count >= 0),
  max_attempts integer not null default 5 check (max_attempts between 1 and 20),
  stale_recovery_count integer not null default 0 check (stale_recovery_count >= 0),
  max_stale_recoveries integer not null default 2 check (max_stale_recoveries between 0 and 5),
  next_attempt_at timestamptz not null default now(),
  locked_at timestamptz,
  last_attempt_at timestamptz,
  sent_at timestamptz,
  provider_message_id text,
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quote_request_email_jobs_request_kind_key unique (quote_request_id, kind)
);

create index if not exists idx_quote_request_email_jobs_retry
  on public.quote_request_email_jobs (status, next_attempt_at, locked_at)
  where status in ('pending', 'processing', 'retry_wait');

create index if not exists idx_quote_request_email_jobs_request
  on public.quote_request_email_jobs (quote_request_id, created_at desc);

drop trigger if exists trg_quote_request_email_jobs_set_updated_at on public.quote_request_email_jobs;
create trigger trg_quote_request_email_jobs_set_updated_at
before update on public.quote_request_email_jobs
for each row
execute function public.set_quote_requests_updated_at();

alter table public.quote_request_email_jobs enable row level security;

grant select, insert, update on table public.quote_request_email_jobs to service_role;

create or replace function public.create_quote_request_idempotent(
  p_idempotency_key uuid,
  p_request_fingerprint text,
  p_name text,
  p_company text,
  p_email text,
  p_phone text,
  p_website_type text,
  p_budget text,
  p_timing text,
  p_description text,
  p_privacy_consent boolean,
  p_approval_token_hash text,
  p_approval_token_expires_at timestamptz,
  p_client_ip_hash text,
  p_user_agent text
)
returns table (
  request_id uuid,
  request_created_at timestamptz,
  was_created boolean,
  admin_job_id uuid,
  admin_job_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.quote_requests%rowtype;
  v_job public.quote_request_email_jobs%rowtype;
  v_was_created boolean := false;
begin
  insert into public.quote_requests (
    idempotency_key,
    request_fingerprint,
    name,
    company,
    email,
    phone,
    website_type,
    budget,
    timing,
    description,
    privacy_consent,
    status,
    approval_token_hash,
    approval_token_expires_at,
    client_ip_hash,
    user_agent
  ) values (
    p_idempotency_key,
    p_request_fingerprint,
    p_name,
    p_company,
    p_email,
    p_phone,
    p_website_type,
    p_budget,
    p_timing,
    p_description,
    p_privacy_consent,
    'pending',
    p_approval_token_hash,
    p_approval_token_expires_at,
    p_client_ip_hash,
    p_user_agent
  )
  on conflict (idempotency_key) where idempotency_key is not null do nothing
  returning * into v_request;

  v_was_created := found;

  if not v_was_created then
    select *
      into v_request
      from public.quote_requests
      where idempotency_key = p_idempotency_key;

    if not found then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_LOOKUP_FAILED';
    end if;

    if v_request.request_fingerprint is distinct from p_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
  end if;

  insert into public.quote_request_email_jobs (quote_request_id, kind)
  values (v_request.id, 'admin_notification')
  on conflict (quote_request_id, kind) do nothing;

  select *
    into v_job
    from public.quote_request_email_jobs
    where quote_request_id = v_request.id
      and kind = 'admin_notification';

  return query
  select
    v_request.id,
    v_request.created_at,
    v_was_created,
    v_job.id,
    v_job.status::text;
end;
$$;

create or replace function public.transition_quote_request_review(
  p_token_hash text,
  p_action text
)
returns table (
  request_id uuid,
  request_name text,
  request_email text,
  review_status text,
  reviewed_at timestamptz,
  confirmation_job_id uuid,
  confirmation_job_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.quote_requests%rowtype;
  v_job public.quote_request_email_jobs%rowtype;
  v_reviewed_at timestamptz;
begin
  if p_action not in ('approved', 'rejected') then
    raise exception using errcode = 'P0001', message = 'INVALID_REVIEW_ACTION';
  end if;

  select *
    into v_request
    from public.quote_requests
    where approval_token_hash = p_token_hash
    for update;

  if not found then
    return;
  end if;

  if v_request.status = 'pending'
     and v_request.approval_token_expires_at <= now() then
    return;
  end if;

  if v_request.status = 'pending' then
    v_reviewed_at := now();

    update public.quote_requests
      set status = p_action::public.quote_request_status,
          reviewer_action = p_action,
          reviewed_at = v_reviewed_at
      where id = v_request.id
        and status = 'pending'
      returning * into v_request;
  end if;

  if v_request.status = 'approved' then
    insert into public.quote_request_email_jobs (quote_request_id, kind)
    values (v_request.id, 'customer_confirmation')
    on conflict (quote_request_id, kind) do nothing;

    select *
      into v_job
      from public.quote_request_email_jobs
      where quote_request_id = v_request.id
        and kind = 'customer_confirmation';
  end if;

  return query
  select
    v_request.id,
    v_request.name,
    v_request.email,
    v_request.status::text,
    v_request.reviewed_at,
    v_job.id,
    v_job.status::text;
end;
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

create or replace function public.requeue_quote_request_email_job(
  p_job_id uuid,
  p_expected_kind public.quote_request_email_kind
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated integer;
begin
  update public.quote_request_email_jobs
    set status = 'retry_wait',
        max_attempts = greatest(max_attempts, attempt_count + 1),
        next_attempt_at = now(),
        locked_at = null,
        last_error_code = null
    where id = p_job_id
      and kind = p_expected_kind
      and status in ('retry_wait', 'failed');

  get diagnostics v_updated = row_count;
  return v_updated = 1;
end;
$$;

create or replace function public.complete_quote_request_email_job(
  p_job_id uuid,
  p_succeeded boolean,
  p_retryable boolean,
  p_error_code text default null,
  p_provider_message_id text default null
)
returns table (
  job_status text,
  attempt_count integer,
  next_attempt_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.quote_request_email_jobs%rowtype;
  v_next_status public.quote_request_email_status;
  v_next_attempt_at timestamptz;
begin
  select *
    into v_job
    from public.quote_request_email_jobs
    where id = p_job_id
    for update;

  if not found or v_job.status <> 'processing' then
    return;
  end if;

  if p_succeeded then
    v_next_status := 'sent';
    v_next_attempt_at := now();
  elsif p_retryable and v_job.attempt_count < v_job.max_attempts then
    v_next_status := 'retry_wait';
    v_next_attempt_at := now() + make_interval(
      secs => least(3600, (30 * power(2, greatest(v_job.attempt_count - 1, 0)))::integer)
    );
  else
    v_next_status := 'failed';
    v_next_attempt_at := now();
  end if;

  update public.quote_request_email_jobs
    set status = v_next_status,
        next_attempt_at = v_next_attempt_at,
        locked_at = null,
        sent_at = case when p_succeeded then now() else sent_at end,
        provider_message_id = case when p_succeeded then p_provider_message_id else provider_message_id end,
        last_error_code = case when p_succeeded then null else left(coalesce(p_error_code, 'UNKNOWN_ERROR'), 120) end
    where id = p_job_id;

  if p_succeeded and v_job.kind = 'admin_notification' then
    update public.quote_requests
      set notification_sent_at = coalesce(notification_sent_at, now())
      where id = v_job.quote_request_id;
  elsif p_succeeded and v_job.kind = 'customer_confirmation' then
    update public.quote_requests
      set confirmation_sent_at = coalesce(confirmation_sent_at, now())
      where id = v_job.quote_request_id;
  end if;

  return query
  select v_next_status::text, v_job.attempt_count, v_next_attempt_at;
end;
$$;

revoke all on function public.create_quote_request_idempotent(uuid, text, text, text, text, text, text, text, text, text, boolean, text, timestamptz, text, text) from public, anon, authenticated;
revoke all on function public.transition_quote_request_review(text, text) from public, anon, authenticated;
revoke all on function public.claim_quote_request_email_job(uuid) from public, anon, authenticated;
revoke all on function public.requeue_quote_request_email_job(uuid, public.quote_request_email_kind) from public, anon, authenticated;
revoke all on function public.complete_quote_request_email_job(uuid, boolean, boolean, text, text) from public, anon, authenticated;

grant execute on function public.create_quote_request_idempotent(uuid, text, text, text, text, text, text, text, text, text, boolean, text, timestamptz, text, text) to service_role;
grant execute on function public.transition_quote_request_review(text, text) to service_role;
grant execute on function public.claim_quote_request_email_job(uuid) to service_role;
grant execute on function public.requeue_quote_request_email_job(uuid, public.quote_request_email_kind) to service_role;
grant execute on function public.complete_quote_request_email_job(uuid, boolean, boolean, text, text) to service_role;