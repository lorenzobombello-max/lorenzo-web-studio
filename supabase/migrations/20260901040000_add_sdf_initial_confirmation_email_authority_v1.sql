create table public.sdf_initial_confirmation_email_jobs (
  job_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null unique
    references public.quote_requests(id) on delete restrict,
  template_version text not null default 'SDF_REQUEST_RECEIVED_NL_BE_v1',
  status text not null default 'pending',
  attempt_count integer not null default 0,
  max_attempts integer not null default 5,
  next_attempt_at timestamptz not null default clock_timestamp(),
  locked_at timestamptz,
  delivery_lease_token uuid,
  delivery_lease_expires_at timestamptz,
  sent_at timestamptz,
  provider_message_id text,
  last_error_code text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint sdf_initial_confirmation_email_jobs_template_version_check
    check (template_version = 'SDF_REQUEST_RECEIVED_NL_BE_v1'),
  constraint sdf_initial_confirmation_email_jobs_status_check
    check (status in ('pending', 'processing', 'retry_wait', 'sent', 'failed')),
  constraint sdf_initial_confirmation_email_jobs_attempt_count_check
    check (attempt_count between 0 and 5),
  constraint sdf_initial_confirmation_email_jobs_max_attempts_check
    check (max_attempts = 5),
  constraint sdf_initial_confirmation_email_jobs_lease_shape_check
    check (
      (
        status = 'processing'
        and locked_at is not null
        and delivery_lease_token is not null
        and delivery_lease_expires_at is not null
      )
      or (
        status <> 'processing'
        and locked_at is null
        and delivery_lease_token is null
        and delivery_lease_expires_at is null
      )
    ),
  constraint sdf_initial_confirmation_email_jobs_sent_at_shape_check
    check (
      (status = 'sent' and sent_at is not null)
      or (status <> 'sent' and sent_at is null)
    ),
  constraint sdf_initial_confirmation_email_jobs_attempts_within_max_check
    check (attempt_count <= max_attempts),
  constraint sdf_initial_confirmation_email_jobs_last_error_code_check
    check (last_error_code is null or char_length(last_error_code) <= 120)
);

create index sdf_initial_confirmation_email_jobs_due_idx
  on public.sdf_initial_confirmation_email_jobs (
    status,
    next_attempt_at,
    created_at
  )
  where status in ('pending', 'retry_wait');

create function lws_internal.guard_sdf_initial_confirmation_request_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  if not exists (
    select 1
    from public.quote_requests as request
    where request.id = new.quote_request_id
      and request.request_kind = 'slimme_documentenflow'
      and request.record_classification = 'production'
  ) then
    raise exception using
      errcode = '23514',
      message = 'SDF_INITIAL_CONFIRMATION_REQUEST_REQUIRED';
  end if;

  return new;
end;
$$;

create trigger sdf_initial_confirmation_email_jobs_request_guard
before insert or update of quote_request_id
on public.sdf_initial_confirmation_email_jobs
for each row
execute function lws_internal.guard_sdf_initial_confirmation_request_v1();

alter table public.sdf_initial_confirmation_email_jobs enable row level security;
alter table public.sdf_initial_confirmation_email_jobs force row level security;

revoke all on table public.sdf_initial_confirmation_email_jobs
from public, anon, authenticated, service_role;

revoke execute on function lws_internal.guard_sdf_initial_confirmation_request_v1()
from public, anon, authenticated, service_role;
