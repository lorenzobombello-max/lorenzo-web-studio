create table public.sdf_accepted_commercial_terms (
  accepted_terms_id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null unique references public.sdf_quotation_acceptances(quotation_id),
  quote_request_id uuid not null unique references public.quote_requests(id),
  sdf_package text not null check (sdf_package in ('start','groei','maatwerk')),
  accepted_implementation_amount_minor bigint not null check (accepted_implementation_amount_minor >= 0),
  currency char(3) not null check (currency = 'EUR'),
  vat_basis text not null check (vat_basis = 'exclusive'),
  pricing_authority_version smallint not null check (pricing_authority_version = 1),
  creation_idempotency_key uuid not null unique,
  creation_fingerprint char(64) not null check (creation_fingerprint ~ '^[0-9a-f]{64}$'),
  created_by_operator_id uuid not null references public.commercial_operators(operator_id),
  created_at timestamptz not null default clock_timestamp()
);

create table public.sdf_milestone_one_obligations (
  obligation_id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null references public.sdf_accepted_commercial_terms(quotation_id),
  accepted_terms_id uuid not null unique references public.sdf_accepted_commercial_terms(accepted_terms_id),
  milestone_identity text not null check (milestone_identity = 'M1'),
  percentage_basis_points smallint not null check (percentage_basis_points = 4000),
  amount_minor bigint not null check (amount_minor >= 0),
  currency char(3) not null check (currency = 'EUR'),
  vat_basis text not null check (vat_basis = 'exclusive'),
  obligation_state text not null check (obligation_state = 'EXPECTED'),
  obligation_origin text not null check (obligation_origin = 'QUOTATION_ACCEPTANCE'),
  created_at timestamptz not null default clock_timestamp(),
  constraint sdf_milestone_one_business_key unique (quotation_id,milestone_identity)
);

comment on table public.sdf_accepted_commercial_terms is
  'Private append-once snapshot of the exact implementation terms bound to one accepted SDF quotation. Package identity is copied as evidence and is not a live pricing lookup.';
comment on table public.sdf_milestone_one_obligations is
  'Private append-once EXPECTED/factureerbaar M1 obligation. This is not invoice, payment, receipt, reconciliation, project, activation, or recurring evidence.';

create function public.guard_sdf_accepted_commercial_terms_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_quote_request_id uuid;
  v_request_kind text;
  v_sdf_package text;
  v_pricing jsonb;
  v_canonical_amount bigint;
begin
  if tg_op in ('UPDATE','DELETE') then
    raise exception using errcode = '55000', message = 'SDF_ACCEPTED_TERMS_IMMUTABLE';
  end if;

  select quotation.quote_request_id, request.request_kind, request.sdf_package
  into v_quote_request_id, v_request_kind, v_sdf_package
  from public.sdf_quotation_acceptances as acceptance
  join public.sdf_quotations as quotation on quotation.quotation_id = acceptance.quotation_id
  join public.quote_requests as request on request.id = quotation.quote_request_id
  where acceptance.quotation_id = new.quotation_id;

  if not found then
    raise exception using errcode = '23503', message = 'SDF_QUOTATION_ACCEPTANCE_REQUIRED';
  end if;
  if v_request_kind <> 'slimme_documentenflow' then
    raise exception using errcode = '23514', message = 'SDF_FINANCIAL_AUTHORITY_REQUIRES_SDF';
  end if;
  if v_sdf_package is null then
    raise exception using errcode = '23514', message = 'SDF_ACCEPTED_PACKAGE_REQUIRED';
  end if;
  if new.quote_request_id <> v_quote_request_id or new.sdf_package <> v_sdf_package then
    raise exception using errcode = '23514', message = 'SDF_ACCEPTED_TERMS_LINKAGE_MISMATCH';
  end if;

  v_pricing := public.get_sdf_package_pricing_authority_v1(v_sdf_package);
  v_canonical_amount := (v_pricing->'implementation'->>'amount_minor')::bigint;
  if new.currency <> v_pricing->>'currency'
     or new.vat_basis <> v_pricing->>'vat_basis'
     or new.pricing_authority_version <> (v_pricing->>'authority_version')::smallint then
    raise exception using errcode = '23514', message = 'SDF_PRICING_PROVENANCE_MISMATCH';
  end if;
  if v_sdf_package in ('start','groei')
     and new.accepted_implementation_amount_minor <> v_canonical_amount then
    raise exception using errcode = '23514', message = 'SDF_ACCEPTED_AMOUNT_MISMATCH';
  end if;
  if v_sdf_package = 'maatwerk'
     and new.accepted_implementation_amount_minor < v_canonical_amount then
    raise exception using errcode = '23514', message = 'SDF_ACCEPTED_AMOUNT_BELOW_AUTHORITY_MINIMUM';
  end if;
  if mod(new.accepted_implementation_amount_minor,5) <> 0 then
    raise exception using errcode = '23514', message = 'SDF_MILESTONE_ONE_MINOR_UNIT_INEXACT';
  end if;
  return new;
end;
$$;

create function public.guard_sdf_milestone_one_obligation_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_terms public.sdf_accepted_commercial_terms%rowtype;
  v_expected_amount bigint;
begin
  if tg_op in ('UPDATE','DELETE') then
    raise exception using errcode = '55000', message = 'SDF_MILESTONE_ONE_IMMUTABLE';
  end if;

  select * into v_terms
  from public.sdf_accepted_commercial_terms
  where accepted_terms_id = new.accepted_terms_id;
  if not found then
    raise exception using errcode = '23503', message = 'SDF_ACCEPTED_TERMS_REQUIRED';
  end if;

  v_expected_amount := ((v_terms.accepted_implementation_amount_minor::numeric * 4000) / 10000)::bigint;
  if new.quotation_id <> v_terms.quotation_id
     or new.amount_minor <> v_expected_amount
     or new.currency <> v_terms.currency
     or new.vat_basis <> v_terms.vat_basis then
    raise exception using errcode = '23514', message = 'SDF_MILESTONE_ONE_COHERENCE_FAILED';
  end if;
  return new;
end;
$$;

create function public.guard_sdf_accepted_package_input_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  if new.sdf_package is distinct from old.sdf_package
     and exists(
       select 1
       from public.sdf_accepted_commercial_terms as terms
       where terms.quote_request_id = old.id
     ) then
    raise exception using errcode = '55000', message = 'SDF_ACCEPTED_PACKAGE_IMMUTABLE';
  end if;
  return new;
end;
$$;

create trigger trg_sdf_accepted_commercial_terms_guard
before insert or update or delete on public.sdf_accepted_commercial_terms
for each row execute function public.guard_sdf_accepted_commercial_terms_v1();
create trigger trg_sdf_milestone_one_obligations_guard
before insert or update or delete on public.sdf_milestone_one_obligations
for each row execute function public.guard_sdf_milestone_one_obligation_v1();
create trigger trg_sdf_accepted_package_input_guard
before update of sdf_package on public.quote_requests
for each row execute function public.guard_sdf_accepted_package_input_v1();

alter table public.sdf_accepted_commercial_terms enable row level security;
alter table public.sdf_accepted_commercial_terms force row level security;
alter table public.sdf_milestone_one_obligations enable row level security;
alter table public.sdf_milestone_one_obligations force row level security;

revoke all privileges on table public.sdf_accepted_commercial_terms
from public, anon, authenticated, service_role;
revoke all privileges on table public.sdf_milestone_one_obligations
from public, anon, authenticated, service_role;
revoke all on function public.guard_sdf_accepted_commercial_terms_v1()
from public, anon, authenticated, service_role;
revoke all on function public.guard_sdf_milestone_one_obligation_v1()
from public, anon, authenticated, service_role;
revoke all on function public.guard_sdf_accepted_package_input_v1()
from public, anon, authenticated, service_role;

create function public.create_sdf_milestone_one_foundation_v1(
  p_quotation_id uuid,
  p_accepted_implementation_amount_minor bigint,
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
  v_quote_request_id uuid;
  v_request_kind text;
  v_sdf_package text;
  v_pricing jsonb;
  v_fingerprint text;
  v_existing public.sdf_accepted_commercial_terms%rowtype;
  v_terms public.sdf_accepted_commercial_terms%rowtype;
  v_obligation public.sdf_milestone_one_obligations%rowtype;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner','admin') then
    raise exception using errcode = '42501', message = 'SDF_FINANCIAL_AUTHORITY_DENIED';
  end if;
  if p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if p_accepted_implementation_amount_minor is null then
    raise exception using errcode = '22004', message = 'SDF_EXACT_ACCEPTED_AMOUNT_REQUIRED';
  end if;
  if p_accepted_implementation_amount_minor < 0 then
    raise exception using errcode = '22023', message = 'SDF_ACCEPTED_AMOUNT_INVALID';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'acceptedImplementationAmountMinor',p_accepted_implementation_amount_minor,
    'quotationId',p_quotation_id
  )::text,'UTF8'),'sha256'),'hex');

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  select * into v_existing
  from public.sdf_accepted_commercial_terms
  where creation_idempotency_key = p_idempotency_key;
  if found then
    if rtrim(v_existing.creation_fingerprint) <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    select * into strict v_obligation
    from public.sdf_milestone_one_obligations
    where accepted_terms_id = v_existing.accepted_terms_id;
    return jsonb_build_object(
      'accepted_terms_id',v_existing.accepted_terms_id,
      'obligation_id',v_obligation.obligation_id,
      'quotation_id',v_existing.quotation_id,
      'was_created',false
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_quotation_id::text,0));
  select * into v_existing
  from public.sdf_accepted_commercial_terms
  where quotation_id = p_quotation_id;
  if found then
    if rtrim(v_existing.creation_fingerprint) <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'SDF_ACCEPTED_TERMS_CONFLICT';
    end if;
    select * into strict v_obligation
    from public.sdf_milestone_one_obligations
    where accepted_terms_id = v_existing.accepted_terms_id;
    return jsonb_build_object(
      'accepted_terms_id',v_existing.accepted_terms_id,
      'obligation_id',v_obligation.obligation_id,
      'quotation_id',v_existing.quotation_id,
      'was_created',false
    );
  end if;

  select quotation.quote_request_id, request.request_kind, request.sdf_package
  into v_quote_request_id, v_request_kind, v_sdf_package
  from public.sdf_quotation_acceptances as acceptance
  join public.sdf_quotations as quotation on quotation.quotation_id = acceptance.quotation_id
  join public.quote_requests as request on request.id = quotation.quote_request_id
  where acceptance.quotation_id = p_quotation_id;
  if not found then
    raise exception using errcode = '23503', message = 'SDF_QUOTATION_ACCEPTANCE_REQUIRED';
  end if;
  if v_request_kind <> 'slimme_documentenflow' then
    raise exception using errcode = '23514', message = 'SDF_FINANCIAL_AUTHORITY_REQUIRES_SDF';
  end if;

  v_pricing := public.get_sdf_package_pricing_authority_v1(v_sdf_package);
  insert into public.sdf_accepted_commercial_terms(
    quotation_id,quote_request_id,sdf_package,accepted_implementation_amount_minor,
    currency,vat_basis,pricing_authority_version,creation_idempotency_key,
    creation_fingerprint,created_by_operator_id
  ) values (
    p_quotation_id,v_quote_request_id,v_sdf_package,p_accepted_implementation_amount_minor,
    v_pricing->>'currency',v_pricing->>'vat_basis',(v_pricing->>'authority_version')::smallint,
    p_idempotency_key,v_fingerprint,v_operator.operator_id
  ) returning * into v_terms;

  insert into public.sdf_milestone_one_obligations(
    quotation_id,accepted_terms_id,milestone_identity,percentage_basis_points,
    amount_minor,currency,vat_basis,obligation_state,obligation_origin
  ) values (
    v_terms.quotation_id,v_terms.accepted_terms_id,'M1',4000,
    ((v_terms.accepted_implementation_amount_minor::numeric * 4000) / 10000)::bigint,
    v_terms.currency,v_terms.vat_basis,'EXPECTED','QUOTATION_ACCEPTANCE'
  ) returning * into v_obligation;

  return jsonb_build_object(
    'accepted_terms_id',v_terms.accepted_terms_id,
    'obligation_id',v_obligation.obligation_id,
    'quotation_id',v_terms.quotation_id,
    'was_created',true
  );
end;
$$;

comment on function public.create_sdf_milestone_one_foundation_v1(uuid,bigint,uuid) is
  'Owner/admin-only atomic binding of exact accepted SDF implementation terms to one EXPECTED M1 obligation. Creates no invoice, payment, project, activation, or recurring evidence.';

revoke all on function public.create_sdf_milestone_one_foundation_v1(uuid,bigint,uuid)
from public, anon, authenticated, service_role;
grant execute on function public.create_sdf_milestone_one_foundation_v1(uuid,bigint,uuid)
to authenticated;