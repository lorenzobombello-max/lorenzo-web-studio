create table public.resend_sdf_inbound_receipts (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'RESEND'
    check (provider = 'RESEND'),
  provider_email_id text not null
    check (provider_email_id ~ '^[A-Za-z0-9_-]{1,200}$'),
  webhook_delivery_id text not null
    check (webhook_delivery_id ~ '^[A-Za-z0-9_-]{1,200}$'),
  rfc_message_id text
    check (rfc_message_id is null or (
      char_length(rfc_message_id) between 3 and 998
      and rfc_message_id = btrim(rfc_message_id)
      and rfc_message_id !~ E'[\\r\\n]'
    )),
  sender_email text not null
    check (
      sender_email = lower(btrim(sender_email))
      and sender_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
      and char_length(sender_email) <= 254
    ),
  matched_recipient text not null
    check (
      matched_recipient = lower(btrim(matched_recipient))
      and matched_recipient ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
      and char_length(matched_recipient) <= 254
    ),
  received_at timestamptz not null,
  status text not null default 'RECEIVED' check (status = 'RECEIVED'),
  canonical_fingerprint char(64) not null
    check (canonical_fingerprint ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  constraint resend_sdf_inbound_receipts_provider_email_key
    unique (provider, provider_email_id),
  constraint resend_sdf_inbound_receipts_delivery_key
    unique (provider, webhook_delivery_id)
);

create table lws_internal.resend_sdf_inbound_receipt_deliveries (
  provider text not null check (provider = 'RESEND'),
  webhook_delivery_id text not null
    check (webhook_delivery_id ~ '^[A-Za-z0-9_-]{1,200}$'),
  receipt_id uuid not null
    references public.resend_sdf_inbound_receipts(id) on delete restrict,
  canonical_fingerprint char(64) not null
    check (canonical_fingerprint ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  primary key (provider, webhook_delivery_id)
);

create function lws_internal.prevent_resend_sdf_inbound_receipt_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'RESEND_SDF_INBOUND_RECEIPT_IMMUTABLE';
end;
$$;

create trigger trg_resend_sdf_inbound_receipts_immutable
before update or delete on public.resend_sdf_inbound_receipts
for each row execute function lws_internal.prevent_resend_sdf_inbound_receipt_mutation_v1();

create trigger trg_resend_sdf_inbound_deliveries_immutable
before update or delete on lws_internal.resend_sdf_inbound_receipt_deliveries
for each row execute function lws_internal.prevent_resend_sdf_inbound_receipt_mutation_v1();

alter table public.resend_sdf_inbound_receipts enable row level security;
alter table public.resend_sdf_inbound_receipts force row level security;
alter table lws_internal.resend_sdf_inbound_receipt_deliveries enable row level security;
alter table lws_internal.resend_sdf_inbound_receipt_deliveries force row level security;

revoke all on table public.resend_sdf_inbound_receipts
from public, anon, authenticated, service_role;
revoke all on table lws_internal.resend_sdf_inbound_receipt_deliveries
from public, anon, authenticated, service_role;
revoke all on function lws_internal.prevent_resend_sdf_inbound_receipt_mutation_v1()
from public, anon, authenticated, service_role;

create function public.register_resend_sdf_inbound_receipt_v1(
  p_provider_email_id text,
  p_webhook_delivery_id text,
  p_rfc_message_id text,
  p_sender_email text,
  p_matched_recipient text,
  p_received_at timestamptz,
  p_canonical_fingerprint text
)
returns table (
  receipt_id uuid,
  replayed boolean
)
language plpgsql
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_receipt public.resend_sdf_inbound_receipts%rowtype;
  v_delivery lws_internal.resend_sdf_inbound_receipt_deliveries%rowtype;
  v_delivery_lock bigint;
  v_email_lock bigint;
begin
  if p_provider_email_id is null
     or p_provider_email_id !~ '^[A-Za-z0-9_-]{1,200}$'
     or p_webhook_delivery_id is null
     or p_webhook_delivery_id !~ '^[A-Za-z0-9_-]{1,200}$'
     or p_sender_email is null
     or p_sender_email <> lower(btrim(p_sender_email))
     or p_sender_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     or char_length(p_sender_email) > 254
     or p_matched_recipient is null
     or p_matched_recipient <> lower(btrim(p_matched_recipient))
     or p_matched_recipient !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     or char_length(p_matched_recipient) > 254
     or p_received_at is null
     or p_canonical_fingerprint is null
     or p_canonical_fingerprint !~ '^[0-9a-f]{64}$'
     or (p_rfc_message_id is not null and (
       char_length(p_rfc_message_id) not between 3 and 998
       or p_rfc_message_id <> btrim(p_rfc_message_id)
       or p_rfc_message_id ~ E'[\\r\\n]'
     )) then
    raise exception using errcode = '22023', message = 'INVALID_RESEND_SDF_INBOUND_RECEIPT';
  end if;

  v_delivery_lock := hashtextextended('RESEND:delivery:' || p_webhook_delivery_id, 0);
  v_email_lock := hashtextextended('RESEND:email:' || p_provider_email_id, 0);
  perform pg_advisory_xact_lock(least(v_delivery_lock, v_email_lock));
  if v_delivery_lock <> v_email_lock then
    perform pg_advisory_xact_lock(greatest(v_delivery_lock, v_email_lock));
  end if;

  select delivery.* into v_delivery
  from lws_internal.resend_sdf_inbound_receipt_deliveries as delivery
  where delivery.provider = 'RESEND'
    and delivery.webhook_delivery_id = p_webhook_delivery_id;

  if found then
    select receipt.* into strict v_receipt
    from public.resend_sdf_inbound_receipts as receipt
    where receipt.id = v_delivery.receipt_id;
    if v_delivery.canonical_fingerprint <> p_canonical_fingerprint
       or v_receipt.provider_email_id <> p_provider_email_id
       or v_receipt.canonical_fingerprint <> p_canonical_fingerprint then
      raise exception using errcode = 'P0001', message = 'INBOUND_RECEIPT_CONFLICT';
    end if;
    return query select v_receipt.id, true;
    return;
  end if;

  select receipt.* into v_receipt
  from public.resend_sdf_inbound_receipts as receipt
  where receipt.provider = 'RESEND'
    and receipt.provider_email_id = p_provider_email_id;

  if found then
    if v_receipt.canonical_fingerprint <> p_canonical_fingerprint
       or v_receipt.rfc_message_id is distinct from p_rfc_message_id
       or v_receipt.sender_email <> p_sender_email
       or v_receipt.matched_recipient <> p_matched_recipient
       or v_receipt.received_at <> p_received_at then
      raise exception using errcode = 'P0001', message = 'INBOUND_RECEIPT_CONFLICT';
    end if;
    insert into lws_internal.resend_sdf_inbound_receipt_deliveries (
      provider, webhook_delivery_id, receipt_id, canonical_fingerprint
    ) values (
      'RESEND', p_webhook_delivery_id, v_receipt.id, p_canonical_fingerprint
    );
    return query select v_receipt.id, true;
    return;
  end if;

  insert into public.resend_sdf_inbound_receipts (
    provider, provider_email_id, webhook_delivery_id, rfc_message_id,
    sender_email, matched_recipient, received_at, canonical_fingerprint
  ) values (
    'RESEND', p_provider_email_id, p_webhook_delivery_id, p_rfc_message_id,
    p_sender_email, p_matched_recipient, p_received_at, p_canonical_fingerprint
  ) returning * into v_receipt;

  insert into lws_internal.resend_sdf_inbound_receipt_deliveries (
    provider, webhook_delivery_id, receipt_id, canonical_fingerprint
  ) values (
    'RESEND', p_webhook_delivery_id, v_receipt.id, p_canonical_fingerprint
  );

  return query select v_receipt.id, false;
end;
$$;

revoke all on function public.register_resend_sdf_inbound_receipt_v1(
  text, text, text, text, text, timestamptz, text
) from public, anon, authenticated;
grant execute on function public.register_resend_sdf_inbound_receipt_v1(
  text, text, text, text, text, timestamptz, text
) to service_role;

comment on table public.resend_sdf_inbound_receipts is
  'Immutable metadata-only receipts for authenticated Resend email.received events routed by the configured SDF recipient. Creates no downstream business records.';
comment on function public.register_resend_sdf_inbound_receipt_v1(
  text, text, text, text, text, timestamptz, text
) is 'Service-role-only atomic receipt registration with delivery and provider-email replay conflict protection.';