create extension if not exists pgcrypto;

create type public.quote_request_status as enum ('pending', 'approved', 'rejected');

create table if not exists public.quote_requests (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  name text not null check (char_length(name) between 2 and 120),
  company text null check (char_length(company) <= 140),
  email text not null check (char_length(email) <= 254),
  phone text null check (char_length(phone) <= 40),
  website_type text not null check (char_length(website_type) <= 80),
  budget text not null check (char_length(budget) <= 80),
  timing text not null check (char_length(timing) <= 80),
  description text not null check (char_length(description) between 10 and 3000),
  privacy_consent boolean not null check (privacy_consent = true),
  status public.quote_request_status not null default 'pending',
  approval_token_hash text,
  approval_token_expires_at timestamptz,
  reviewed_at timestamptz,
  reviewer_action text check (reviewer_action in ('approved', 'rejected') or reviewer_action is null),
  client_ip_hash text,
  user_agent text,
  notification_sent_at timestamptz,
  confirmation_sent_at timestamptz,
  constraint quote_requests_token_required_when_pending
    check (
      (status = 'pending' and approval_token_hash is not null and approval_token_expires_at is not null)
      or status <> 'pending'
    )
);

create unique index if not exists idx_quote_requests_pending_token_hash
  on public.quote_requests (approval_token_hash)
  where status = 'pending';

create index if not exists idx_quote_requests_status on public.quote_requests (status);
create index if not exists idx_quote_requests_created_at_desc on public.quote_requests (created_at desc);
create index if not exists idx_quote_requests_client_ip_hash_created_at on public.quote_requests (client_ip_hash, created_at desc);

create or replace function public.set_quote_requests_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_quote_requests_set_updated_at on public.quote_requests;
create trigger trg_quote_requests_set_updated_at
before update on public.quote_requests
for each row
execute function public.set_quote_requests_updated_at();

alter table public.quote_requests enable row level security;

-- All access is intentionally handled by Edge Functions using service role.
-- Do not add public read/write policies here.
