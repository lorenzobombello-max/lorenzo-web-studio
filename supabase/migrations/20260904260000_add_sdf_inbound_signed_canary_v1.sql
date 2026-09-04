alter table public.resend_sdf_inbound_receipts
  add column record_classification text not null default 'production'
  constraint resend_sdf_inbound_receipts_record_classification_check
    check (record_classification in ('production','internal_e2e'));

create or replace function public.register_resend_sdf_inbound_receipt_v1(
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
  v_record_classification text := 'production';
  v_canary_match_count integer;
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

  v_canary_match_count :=
    (p_provider_email_id = 'internal_e2e_sdf_inbound_canary_v1')::integer
    + (p_webhook_delivery_id = 'internal_e2e_sdf_inbound_delivery_v1')::integer
    + coalesce((p_rfc_message_id = '<internal-e2e-sdf-inbound-canary-v1@invalid.local>')::integer, 0)
    + (p_sender_email = 'sdf-inbound-canary@invalid.local')::integer
    + (p_matched_recipient = 'sdf-inbound-canary@invalid.local')::integer
    + (p_received_at = '2000-01-01T00:00:00.000Z'::timestamptz)::integer
    + (p_canonical_fingerprint = '2962999d3c2a4f05a820c57319af788b77da8bcb53ab209bb8d519f643401d5d')::integer;

  if v_canary_match_count > 0 and v_canary_match_count < 7 then
    raise exception using errcode = '22023', message = 'INVALID_RESEND_SDF_INBOUND_RECEIPT';
  end if;
  if v_canary_match_count = 7 then
    v_record_classification := 'internal_e2e';
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
       or v_receipt.canonical_fingerprint <> p_canonical_fingerprint
       or v_receipt.record_classification <> v_record_classification then
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
       or v_receipt.received_at <> p_received_at
       or v_receipt.record_classification <> v_record_classification then
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
    sender_email, matched_recipient, received_at, canonical_fingerprint,
    record_classification
  ) values (
    'RESEND', p_provider_email_id, p_webhook_delivery_id, p_rfc_message_id,
    p_sender_email, p_matched_recipient, p_received_at, p_canonical_fingerprint,
    v_record_classification
  ) returning * into v_receipt;

  insert into lws_internal.resend_sdf_inbound_receipt_deliveries (
    provider, webhook_delivery_id, receipt_id, canonical_fingerprint
  ) values (
    'RESEND', p_webhook_delivery_id, v_receipt.id, p_canonical_fingerprint
  );

  return query select v_receipt.id, false;
end;
$$;

create function public.get_sdf_inbound_signed_canary_evidence_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_receipt_count bigint;
  v_delivery_count bigint;
  v_classification text;
begin
  perform lws_internal.assert_operator_aal2_v1();
  perform lws_internal.assert_sdf_owner_v1();

  select count(*), min(receipt.record_classification)
  into v_receipt_count, v_classification
  from public.resend_sdf_inbound_receipts as receipt
  where receipt.provider = 'RESEND'
    and receipt.provider_email_id = 'internal_e2e_sdf_inbound_canary_v1'
    and receipt.webhook_delivery_id = 'internal_e2e_sdf_inbound_delivery_v1';

  select count(*)
  into v_delivery_count
  from lws_internal.resend_sdf_inbound_receipt_deliveries as delivery
  join public.resend_sdf_inbound_receipts as receipt
    on receipt.id = delivery.receipt_id
  where delivery.provider = 'RESEND'
    and delivery.webhook_delivery_id = 'internal_e2e_sdf_inbound_delivery_v1'
    and receipt.provider_email_id = 'internal_e2e_sdf_inbound_canary_v1';

  return jsonb_build_object(
    'authorized', true,
    'receipt_count', v_receipt_count,
    'delivery_count', v_delivery_count,
    'classification', v_classification
  );
end;
$$;

revoke all on function public.get_sdf_inbound_signed_canary_evidence_v1()
from public, anon, service_role;
grant execute on function public.get_sdf_inbound_signed_canary_evidence_v1()
to authenticated;

comment on function public.get_sdf_inbound_signed_canary_evidence_v1() is
  'OP-01 AAL2-only read of fixed signed SDF inbound canary evidence; returns no record identifiers.';
