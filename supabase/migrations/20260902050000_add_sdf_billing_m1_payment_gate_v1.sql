alter table public.quote_requests
  drop constraint quote_requests_sdf_package_shape_check,
  add constraint quote_requests_sdf_package_shape_check
    check (
      (request_kind = 'website' and sdf_package is null)
      or (
        request_kind = 'slimme_documentenflow'
        and (sdf_package is null or sdf_package in ('start', 'groei', 'pro', 'maatwerk'))
      )
    );

alter table public.sdf_accepted_commercial_terms
  drop constraint sdf_accepted_commercial_terms_sdf_package_check,
  add constraint sdf_accepted_commercial_terms_sdf_package_check
    check (sdf_package in ('start', 'groei', 'pro', 'maatwerk'));

create or replace function public.get_sdf_package_pricing_authority_v1(p_sdf_package text)
returns jsonb
language plpgsql
immutable
strict
set search_path = public, pg_catalog
as $$
declare
  v_implementation_minor bigint;
  v_recurring_minor bigint;
  v_price_mode text;
begin
  case p_sdf_package
    when 'start' then
      v_implementation_minor := 285000;
      v_recurring_minor := 17500;
      v_price_mode := 'fixed';
    when 'groei' then
      v_implementation_minor := 570000;
      v_recurring_minor := 29900;
      v_price_mode := 'fixed';
    when 'pro' then
      v_implementation_minor := 750000;
      v_recurring_minor := 44900;
      v_price_mode := 'fixed';
    when 'maatwerk' then
      v_implementation_minor := 750000;
      v_recurring_minor := 44900;
      v_price_mode := 'starting_at';
    else
      raise exception using errcode = '22023', message = 'INVALID_SDF_PACKAGE';
  end case;

  return jsonb_build_object(
    'authority_version', 1,
    'package', p_sdf_package,
    'currency', 'EUR',
    'vat_basis', 'exclusive',
    'implementation', jsonb_build_object(
      'price_mode', v_price_mode,
      'amount_minor', v_implementation_minor
    ),
    'recurring', jsonb_build_object(
      'price_mode', v_price_mode,
      'amount_minor', v_recurring_minor,
      'billing_period', 'month',
      'commercial_package_price', true,
      'active_recurring_obligation', false
    )
  );
end;
$$;

comment on function public.get_sdf_package_pricing_authority_v1(text) is
  'Private immutable SDF package pricing authority. PRO is fixed at EUR 7,500 implementation; MAATWERK remains an explicit negotiated amount and never uses the starting-at amount as accepted-price fallback.';

create table public.sdf_invoice_master_bindings (
  singleton boolean primary key default true check (singleton),
  document_reference text not null,
  drive_file_id text not null unique,
  document_sha256 char(64) not null check (document_sha256 ~ '^[0-9a-f]{64}$'),
  bound_at timestamptz not null default clock_timestamp()
);

insert into public.sdf_invoice_master_bindings(
  document_reference, drive_file_id, document_sha256
) values (
  '03_Algemene_sjablonen/02_Factuursjabloon.docx',
  '1j3yiSWsWermVnPEkNBcKfAGp20E1NvEC',
  '52dc454bec5d0e09fc9f4b85a1f1877b65f7d3aea166ed195da598cb7b4536d6'
);

create table public.sdf_m1_payment_receipts (
  receipt_id uuid primary key default gen_random_uuid(),
  issuance_id uuid not null references public.sdf_m1_invoice_issuances(issuance_id),
  candidate_id uuid not null references public.sdf_m1_invoice_candidates(candidate_id),
  quote_request_id uuid not null references public.quote_requests(id),
  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null check (currency = 'EUR'),
  bank_transaction_reference text not null unique check (nullif(btrim(bank_transaction_reference), '') is not null),
  evidence_reference text not null check (nullif(btrim(evidence_reference), '') is not null),
  candidate_payload_sha256 char(64) not null check (candidate_payload_sha256 ~ '^[0-9a-f]{64}$'),
  issuance_payload_sha256 char(64) not null check (issuance_payload_sha256 ~ '^[0-9a-f]{64}$'),
  receipt_idempotency_key uuid not null unique,
  receipt_fingerprint char(64) not null check (receipt_fingerprint ~ '^[0-9a-f]{64}$'),
  received_by_operator_id uuid not null references public.commercial_operators(operator_id),
  received_at timestamptz not null default clock_timestamp()
);

create table public.sdf_m1_project_start_authorities (
  start_authority_id uuid primary key default gen_random_uuid(),
  project_id uuid not null unique references public.sdf_projects(project_id),
  quote_request_id uuid not null unique references public.quote_requests(id),
  issuance_id uuid not null unique references public.sdf_m1_invoice_issuances(issuance_id),
  candidate_id uuid not null unique references public.sdf_m1_invoice_candidates(candidate_id),
  authority_state text not null check (authority_state = 'START_ALLOWED'),
  required_amount_minor bigint not null check (required_amount_minor > 0),
  received_amount_minor bigint not null check (received_amount_minor = required_amount_minor),
  currency char(3) not null check (currency = 'EUR'),
  candidate_payload_sha256 char(64) not null check (candidate_payload_sha256 ~ '^[0-9a-f]{64}$'),
  issuance_payload_sha256 char(64) not null check (issuance_payload_sha256 ~ '^[0-9a-f]{64}$'),
  creation_idempotency_key uuid not null unique,
  creation_fingerprint char(64) not null check (creation_fingerprint ~ '^[0-9a-f]{64}$'),
  authorized_by_operator_id uuid not null references public.commercial_operators(operator_id),
  authorized_at timestamptz not null default clock_timestamp()
);

create trigger trg_sdf_invoice_master_bindings_immutable
before update or delete on public.sdf_invoice_master_bindings
for each row execute function public.prevent_sdf_invoice_foundation_mutation_v1();
create trigger trg_sdf_m1_payment_receipts_immutable
before update or delete on public.sdf_m1_payment_receipts
for each row execute function public.prevent_sdf_invoice_foundation_mutation_v1();
create trigger trg_sdf_m1_project_start_authorities_immutable
before update or delete on public.sdf_m1_project_start_authorities
for each row execute function public.prevent_sdf_invoice_foundation_mutation_v1();

create function public.calculate_sdf_m1_candidate_payload_sha256_v1(
  p_candidate public.sdf_m1_invoice_candidates
)
returns text
language sql
immutable
strict
set search_path = public, extensions, pg_catalog
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'acceptedPriceBasis',p_candidate.accepted_price_basis,
    'acceptedTermsId',p_candidate.accepted_terms_id,
    'applicationReference',p_candidate.application_reference,
    'bank',p_candidate.bank_snapshot,
    'currency',p_candidate.currency,
    'customer',p_candidate.customer_snapshot,
    'milestoneIdentity',p_candidate.milestone_identity,
    'netAmountMinor',p_candidate.net_amount_minor,
    'obligationId',p_candidate.obligation_id,
    'percentageBasisPoints',p_candidate.percentage_basis_points,
    'quotationId',p_candidate.quotation_id,
    'seller',p_candidate.seller_snapshot,
    'template',p_candidate.template_snapshot
  )::text,'UTF8'),'sha256'),'hex')
$$;

create function public.get_sdf_m1_payment_state_v1(p_issuance_id uuid)
returns table (
  payment_state text,
  cumulative_received_minor bigint,
  required_amount_minor bigint,
  reconciliation_state text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_required bigint;
  v_received bigint;
begin
  select * into v_operator from public.commercial_operators where auth_user_id = v_subject;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner','admin') then
    raise exception using errcode = '42501', message = 'SDF_PAYMENT_AUTHORITY_DENIED';
  end if;
  select gross_amount_minor into v_required
  from public.sdf_m1_invoice_issuances
  where issuance_id = p_issuance_id and issuance_state = 'ISSUED';
  if not found then
    raise exception using errcode = '23503', message = 'SDF_M1_ISSUANCE_REQUIRED';
  end if;

  select coalesce(sum(amount_minor),0) into v_received
  from public.sdf_m1_payment_receipts
  where issuance_id = p_issuance_id;

  return query select
    case when v_received = 0 then 'NOT_RECEIVED'
         when v_received = v_required then 'RECEIVED'
         else 'PARTIAL' end,
    v_received,
    v_required,
    'NOT_RECONCILED'::text;
end;
$$;

create function public.record_sdf_m1_payment_receipt_v1(
  p_issuance_id uuid,
  p_amount_minor bigint,
  p_bank_transaction_reference text,
  p_evidence_reference text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, extensions, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_issuance public.sdf_m1_invoice_issuances%rowtype;
  v_candidate public.sdf_m1_invoice_candidates%rowtype;
  v_master public.sdf_invoice_master_bindings%rowtype;
  v_existing public.sdf_m1_payment_receipts%rowtype;
  v_receipt public.sdf_m1_payment_receipts%rowtype;
  v_current bigint;
  v_candidate_hash text;
  v_fingerprint text;
begin
  select * into v_operator from public.commercial_operators where auth_user_id = v_subject;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner','admin') then
    raise exception using errcode = '42501', message = 'SDF_PAYMENT_AUTHORITY_DENIED';
  end if;
  if p_issuance_id is null or p_amount_minor <= 0 or p_idempotency_key is null
     or nullif(btrim(p_bank_transaction_reference),'') is null
     or nullif(btrim(p_evidence_reference),'') is null then
    raise exception using errcode = '22023', message = 'SDF_M1_PAYMENT_INPUT_INVALID';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_issuance_id::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  select * into v_issuance from public.sdf_m1_invoice_issuances
  where issuance_id = p_issuance_id and issuance_state = 'ISSUED';
  if not found then raise exception using errcode = '23503', message = 'SDF_M1_ISSUANCE_REQUIRED'; end if;
  select * into strict v_candidate from public.sdf_m1_invoice_candidates
  where candidate_id = v_issuance.candidate_id;
  select * into strict v_master from public.sdf_invoice_master_bindings where singleton;

  v_candidate_hash := public.calculate_sdf_m1_candidate_payload_sha256_v1(v_candidate);
  if v_candidate_hash <> rtrim(v_candidate.candidate_payload_sha256)
     or v_issuance.net_amount_minor <> v_candidate.net_amount_minor
     or v_issuance.gross_amount_minor <> v_candidate.net_amount_minor
     or v_candidate.template_snapshot->>'document_reference' <> v_master.document_reference
     or v_candidate.template_snapshot->>'document_sha256' <> rtrim(v_master.document_sha256) then
    raise exception using errcode = '55000', message = 'SDF_M1_COMMERCIAL_SNAPSHOT_STALE';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'amountMinor',p_amount_minor,
    'bankTransactionReference',btrim(p_bank_transaction_reference),
    'evidenceReference',btrim(p_evidence_reference),
    'issuanceId',p_issuance_id
  )::text,'UTF8'),'sha256'),'hex');
  select * into v_existing from public.sdf_m1_payment_receipts
  where receipt_idempotency_key = p_idempotency_key;
  if found then
    if rtrim(v_existing.receipt_fingerprint) <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('receipt_id',v_existing.receipt_id,'was_created',false);
  end if;
  select * into v_existing from public.sdf_m1_payment_receipts
  where bank_transaction_reference = btrim(p_bank_transaction_reference);
  if found then
    raise exception using errcode = 'P0001', message = 'SDF_M1_PAYMENT_TRANSACTION_CONFLICT';
  end if;

  select coalesce(sum(amount_minor),0) into v_current
  from public.sdf_m1_payment_receipts where issuance_id = p_issuance_id;
  if v_current + p_amount_minor > v_issuance.gross_amount_minor then
    raise exception using errcode = '23514', message = 'SDF_M1_PAYMENT_EXCEEDS_REQUIRED';
  end if;

  insert into public.sdf_m1_payment_receipts(
    issuance_id,candidate_id,quote_request_id,amount_minor,currency,
    bank_transaction_reference,evidence_reference,candidate_payload_sha256,
    issuance_payload_sha256,receipt_idempotency_key,receipt_fingerprint,received_by_operator_id
  ) values (
    v_issuance.issuance_id,v_candidate.candidate_id,v_candidate.quote_request_id,p_amount_minor,'EUR',
    btrim(p_bank_transaction_reference),btrim(p_evidence_reference),v_candidate.candidate_payload_sha256,
    v_issuance.issuance_payload_sha256,p_idempotency_key,v_fingerprint,v_operator.operator_id
  ) returning * into v_receipt;
  return jsonb_build_object('receipt_id',v_receipt.receipt_id,'was_created',true);
end;
$$;

create function public.authorize_sdf_project_start_v1(
  p_project_id uuid,
  p_issuance_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, extensions, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_project public.sdf_projects%rowtype;
  v_issuance public.sdf_m1_invoice_issuances%rowtype;
  v_candidate public.sdf_m1_invoice_candidates%rowtype;
  v_payment record;
  v_existing public.sdf_m1_project_start_authorities%rowtype;
  v_authority public.sdf_m1_project_start_authorities%rowtype;
  v_fingerprint text;
begin
  select * into v_operator from public.commercial_operators where auth_user_id = v_subject;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner','admin') then
    raise exception using errcode = '42501', message = 'SDF_PROJECT_START_AUTHORITY_DENIED';
  end if;
  if p_project_id is null or p_issuance_id is null or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'SDF_PROJECT_START_INPUT_INVALID';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_project_id::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  select * into v_project from public.sdf_projects where project_id = p_project_id;
  if not found then raise exception using errcode = '23503', message = 'SDF_PROJECT_REQUIRED'; end if;
  select * into v_issuance from public.sdf_m1_invoice_issuances
  where issuance_id = p_issuance_id and issuance_state = 'ISSUED';
  if not found then raise exception using errcode = '23503', message = 'SDF_M1_ISSUANCE_REQUIRED'; end if;
  select * into strict v_candidate from public.sdf_m1_invoice_candidates
  where candidate_id = v_issuance.candidate_id;
  if v_project.quote_request_id <> v_candidate.quote_request_id then
    raise exception using errcode = '23514', message = 'SDF_PROJECT_LINKAGE_MISMATCH';
  end if;
  if public.calculate_sdf_m1_candidate_payload_sha256_v1(v_candidate) <> rtrim(v_candidate.candidate_payload_sha256) then
    raise exception using errcode = '55000', message = 'SDF_M1_COMMERCIAL_SNAPSHOT_STALE';
  end if;

  select * into strict v_payment from public.get_sdf_m1_payment_state_v1(p_issuance_id);
  if v_payment.payment_state <> 'RECEIVED'
     or v_payment.cumulative_received_minor <> v_payment.required_amount_minor then
    raise exception using errcode = 'P0001', message = 'SDF_M1_FULL_PAYMENT_REQUIRED';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'candidatePayloadSha256',rtrim(v_candidate.candidate_payload_sha256),
    'issuanceId',p_issuance_id,
    'issuancePayloadSha256',rtrim(v_issuance.issuance_payload_sha256),
    'projectId',p_project_id,
    'receivedAmountMinor',v_payment.cumulative_received_minor
  )::text,'UTF8'),'sha256'),'hex');
  select * into v_existing from public.sdf_m1_project_start_authorities
  where creation_idempotency_key = p_idempotency_key;
  if found then
    if rtrim(v_existing.creation_fingerprint) <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('start_authority_id',v_existing.start_authority_id,'was_created',false);
  end if;
  select * into v_existing from public.sdf_m1_project_start_authorities
  where project_id = p_project_id;
  if found then
    if rtrim(v_existing.creation_fingerprint) <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'SDF_PROJECT_START_AUTHORITY_CONFLICT';
    end if;
    return jsonb_build_object('start_authority_id',v_existing.start_authority_id,'was_created',false);
  end if;

  insert into public.sdf_m1_project_start_authorities(
    project_id,quote_request_id,issuance_id,candidate_id,authority_state,
    required_amount_minor,received_amount_minor,currency,candidate_payload_sha256,
    issuance_payload_sha256,creation_idempotency_key,creation_fingerprint,authorized_by_operator_id
  ) values (
    v_project.project_id,v_project.quote_request_id,v_issuance.issuance_id,v_candidate.candidate_id,'START_ALLOWED',
    v_payment.required_amount_minor,v_payment.cumulative_received_minor,'EUR',v_candidate.candidate_payload_sha256,
    v_issuance.issuance_payload_sha256,p_idempotency_key,v_fingerprint,v_operator.operator_id
  ) returning * into v_authority;
  return jsonb_build_object('start_authority_id',v_authority.start_authority_id,'was_created',true);
end;
$$;

alter table public.sdf_invoice_master_bindings enable row level security;
alter table public.sdf_invoice_master_bindings force row level security;
alter table public.sdf_m1_payment_receipts enable row level security;
alter table public.sdf_m1_payment_receipts force row level security;
alter table public.sdf_m1_project_start_authorities enable row level security;
alter table public.sdf_m1_project_start_authorities force row level security;

revoke all privileges on table public.sdf_invoice_master_bindings from public, anon, authenticated, service_role;
revoke all privileges on table public.sdf_m1_payment_receipts from public, anon, authenticated, service_role;
revoke all privileges on table public.sdf_m1_project_start_authorities from public, anon, authenticated, service_role;
revoke all on function public.calculate_sdf_m1_candidate_payload_sha256_v1(public.sdf_m1_invoice_candidates) from public, anon, authenticated, service_role;
revoke all on function public.get_sdf_m1_payment_state_v1(uuid) from public, anon, authenticated, service_role;
revoke all on function public.record_sdf_m1_payment_receipt_v1(uuid,bigint,text,text,uuid) from public, anon, authenticated, service_role;
revoke all on function public.authorize_sdf_project_start_v1(uuid,uuid,uuid) from public, anon, authenticated, service_role;
grant execute on function public.get_sdf_m1_payment_state_v1(uuid) to authenticated;
grant execute on function public.record_sdf_m1_payment_receipt_v1(uuid,bigint,text,text,uuid) to authenticated;
grant execute on function public.authorize_sdf_project_start_v1(uuid,uuid,uuid) to authenticated;

comment on table public.sdf_invoice_master_bindings is
  'Exact proven singleton Drive invoice master identity: canonical path, Drive file ID, and byte SHA-256.';
comment on table public.sdf_m1_payment_receipts is
  'Append-only bank receipt evidence for an ISSUED SDF M1 invoice. Receipt never implies reconciliation.';
comment on table public.sdf_m1_project_start_authorities is
  'Immutable server-side SDF project-start authority created only after exact cumulative M1 receipt.';