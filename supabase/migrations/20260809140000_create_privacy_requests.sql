create type public.privacy_request_status as enum ('received', 'in_progress', 'closed');

create table public.privacy_requests (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  name text not null check (char_length(name) between 2 and 120),
  email text check (email is null or char_length(email) between 5 and 254),
  phone text check (phone is null or char_length(phone) between 6 and 40),
  message text not null check (char_length(message) between 10 and 3000),
  status public.privacy_request_status not null default 'received',
  client_ip_hash text not null check (client_ip_hash ~ '^[0-9a-f]{64}$'),
  user_agent text check (user_agent is null or char_length(user_agent) <= 500),
  idempotency_key uuid not null unique,
  request_fingerprint text not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  notification_status text not null default 'pending'
    check (notification_status in ('pending', 'sent', 'failed')),
  notification_attempted_at timestamptz,
  notification_error_code text,
  provider_message_id text,
  constraint privacy_requests_contact_required
    check (email is not null or phone is not null)
);

create index idx_privacy_requests_created_at_desc
  on public.privacy_requests (created_at desc);

create index idx_privacy_requests_client_ip_hash_created_at
  on public.privacy_requests (client_ip_hash, created_at desc);

create function public.set_privacy_requests_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_privacy_requests_set_updated_at
before update on public.privacy_requests
for each row
execute function public.set_privacy_requests_updated_at();

alter table public.privacy_requests enable row level security;

revoke all on table public.privacy_requests from public, anon, authenticated;
grant select, insert, update on table public.privacy_requests to service_role;

create function public.create_privacy_request_idempotent(
  p_idempotency_key uuid,
  p_request_fingerprint text,
  p_name text,
  p_email text,
  p_phone text,
  p_message text,
  p_client_ip_hash text,
  p_user_agent text
)
returns table (
  request_id uuid,
  request_created_at timestamptz,
  was_created boolean,
  request_notification_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.privacy_requests%rowtype;
  v_was_created boolean := false;
begin
  insert into public.privacy_requests (
    idempotency_key,
    request_fingerprint,
    name,
    email,
    phone,
    message,
    client_ip_hash,
    user_agent
  ) values (
    p_idempotency_key,
    p_request_fingerprint,
    p_name,
    nullif(p_email, ''),
    nullif(p_phone, ''),
    p_message,
    p_client_ip_hash,
    nullif(p_user_agent, '')
  )
  on conflict (idempotency_key) do nothing
  returning * into v_request;

  v_was_created := found;

  if not v_was_created then
    select *
      into v_request
      from public.privacy_requests
      where idempotency_key = p_idempotency_key;

    if not found then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_LOOKUP_FAILED';
    end if;

    if v_request.request_fingerprint is distinct from p_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
  end if;

  return query
  select
    v_request.id,
    v_request.created_at,
    v_was_created,
    v_request.notification_status;
end;
$$;

revoke all on function public.create_privacy_request_idempotent(uuid, text, text, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.create_privacy_request_idempotent(uuid, text, text, text, text, text, text, text)
  to service_role;