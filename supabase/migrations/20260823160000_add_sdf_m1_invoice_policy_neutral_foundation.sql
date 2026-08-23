create table public.sdf_invoice_number_counters (
  issue_year smallint primary key check (issue_year between 2000 and 9999),
  next_sequence integer not null default 1 check (next_sequence between 1 and 10000),
  updated_at timestamptz not null default clock_timestamp()
);

create table public.sdf_invoice_template_authorities (
  template_authority_id uuid primary key default gen_random_uuid(),
  document_type text not null check (document_type = 'INVOICE'),
  milestone_identity text not null check (milestone_identity = 'M1'),
  template_id text not null,
  template_version text not null,
  document_reference text not null,
  document_sha256 char(64) not null check (document_sha256 ~ '^[0-9a-f]{64}$'),
  registration_idempotency_key uuid not null unique,
  registration_fingerprint char(64) not null check (registration_fingerprint ~ '^[0-9a-f]{64}$'),
  created_by_operator_id uuid not null references public.commercial_operators(operator_id),
  created_at timestamptz not null default clock_timestamp(),
  constraint sdf_invoice_template_identity_unique unique (template_id, template_version),
  constraint sdf_invoice_template_document_reference_valid check (
    nullif(btrim(document_reference), '') is not null
    and document_reference !~ '^[A-Za-z][A-Za-z0-9+.-]*://'
    and position('?' in document_reference) = 0
    and position('#' in document_reference) = 0
  )
);

create table public.sdf_m1_invoice_candidates (
  candidate_id uuid primary key default gen_random_uuid(),
  obligation_id uuid not null unique references public.sdf_milestone_one_obligations(obligation_id),
  quotation_id uuid not null unique references public.sdf_quotation_acceptances(quotation_id),
  accepted_terms_id uuid not null unique references public.sdf_accepted_commercial_terms(accepted_terms_id),
  quote_request_id uuid not null unique references public.quote_requests(id),
  application_reference text not null unique check (application_reference ~ '^LWS-AAN-[0-9]{4}-[0-9]{4}$'),
  template_authority_id uuid not null references public.sdf_invoice_template_authorities(template_authority_id),
  candidate_state text not null check (candidate_state = 'PREPARED'),
  milestone_identity text not null check (milestone_identity = 'M1'),
  percentage_basis_points smallint not null check (percentage_basis_points = 4000),
  currency char(3) not null check (currency = 'EUR'),
  net_amount_minor bigint not null check (net_amount_minor >= 0),
  accepted_price_basis text not null check (accepted_price_basis = 'exclusive'),
  seller_snapshot jsonb not null,
  customer_snapshot jsonb not null,
  bank_snapshot jsonb not null,
  template_snapshot jsonb not null,
  candidate_payload_sha256 char(64) not null check (candidate_payload_sha256 ~ '^[0-9a-f]{64}$'),
  creation_idempotency_key uuid not null unique,
  creation_fingerprint char(64) not null check (creation_fingerprint ~ '^[0-9a-f]{64}$'),
  prepared_by_operator_id uuid not null references public.commercial_operators(operator_id),
  prepared_at timestamptz not null default clock_timestamp(),
  constraint sdf_m1_invoice_candidate_no_fiscal_fallback check (
    not (seller_snapshot ?| array['vat_treatment','vat_rate','vat_rate_basis_points','vat_amount_minor','gross_amount_minor'])
    and not (customer_snapshot ?| array['vat_treatment','vat_rate','vat_rate_basis_points','vat_amount_minor','gross_amount_minor'])
    and not (bank_snapshot ?| array['vat_treatment','vat_rate','vat_rate_basis_points','vat_amount_minor','gross_amount_minor'])
    and not (template_snapshot ?| array['vat_treatment','vat_rate','vat_rate_basis_points','vat_amount_minor','gross_amount_minor'])
  )
);

create table public.sdf_m1_invoice_issuances (
  issuance_id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null unique references public.sdf_m1_invoice_candidates(candidate_id),
  invoice_number text not null unique check (invoice_number ~ '^LWS-[0-9]{4}-[0-9]{4}$'),
  issue_year smallint not null check (issue_year between 2000 and 9999),
  sequence integer not null check (sequence between 1 and 9999),
  issuance_state text not null check (issuance_state = 'ISSUED'),
  vat_authority_version text not null check (nullif(btrim(vat_authority_version), '') is not null),
  vat_treatment text not null check (nullif(btrim(vat_treatment), '') is not null),
  vat_rate_basis_points integer not null check (vat_rate_basis_points >= 0),
  net_amount_minor bigint not null check (net_amount_minor >= 0),
  vat_amount_minor bigint not null check (vat_amount_minor >= 0),
  gross_amount_minor bigint not null check (gross_amount_minor = net_amount_minor + vat_amount_minor),
  issuance_payload_sha256 char(64) not null check (issuance_payload_sha256 ~ '^[0-9a-f]{64}$'),
  docx_sha256 char(64) not null check (docx_sha256 ~ '^[0-9a-f]{64}$'),
  docx_bytes bigint not null check (docx_bytes > 0),
  pdf_sha256 char(64) check (pdf_sha256 is null or pdf_sha256 ~ '^[0-9a-f]{64}$'),
  pdf_bytes bigint check (pdf_bytes is null or pdf_bytes > 0),
  issuance_idempotency_key uuid not null unique,
  issuance_fingerprint char(64) not null check (issuance_fingerprint ~ '^[0-9a-f]{64}$'),
  issued_by_operator_id uuid not null references public.commercial_operators(operator_id),
  issued_at timestamptz not null default clock_timestamp(),
  constraint sdf_m1_invoice_number_components_coherent check (
    invoice_number = 'LWS-' || issue_year::text || '-' || lpad(sequence::text, 4, '0')
  ),
  constraint sdf_m1_invoice_issuance_year_sequence_unique unique (issue_year, sequence)
);

comment on table public.sdf_invoice_number_counters is
  'Private SDF invoice sequence authority. Candidate preparation never consumes a sequence; allocation is reserved for a future atomic issuance transaction.';
comment on table public.sdf_invoice_template_authorities is
  'Immutable identity binding for an existing externally governed Drive invoice document. This table does not create or redesign a template.';
comment on table public.sdf_m1_invoice_candidates is
  'Immutable policy-neutral PREPARED M1 invoice candidate. Snapshots the separate human application reference while preserving quote_request, quotation, terms, obligation, and candidate UUID identities. Contains no invoice number, invoice date, due date, VAT rate, VAT amount, gross amount, payment, reconciliation, or project-start evidence.';
comment on table public.sdf_m1_invoice_issuances is
  'Dormant immutable issuance-evidence schema. Invoice number remains separate from candidate, obligation, and dossier identities and resolves through candidate_id. This is not receipt or reconciliation evidence. No successful production issuance route exists until explicit fiscal authority is activated by a future forward migration.';

create function public.prevent_sdf_invoice_foundation_mutation_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'SDF_INVOICE_FOUNDATION_IMMUTABLE';
end;
$$;

create trigger trg_sdf_invoice_template_authorities_immutable
before update or delete on public.sdf_invoice_template_authorities
for each row execute function public.prevent_sdf_invoice_foundation_mutation_v1();
create trigger trg_sdf_m1_invoice_candidates_immutable
before update or delete on public.sdf_m1_invoice_candidates
for each row execute function public.prevent_sdf_invoice_foundation_mutation_v1();
create trigger trg_sdf_m1_invoice_issuances_immutable
before update or delete on public.sdf_m1_invoice_issuances
for each row execute function public.prevent_sdf_invoice_foundation_mutation_v1();

create function public.guard_sdf_m1_invoice_candidate_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_obligation public.sdf_milestone_one_obligations%rowtype;
  v_terms public.sdf_accepted_commercial_terms%rowtype;
  v_application_reference text;
begin
  select * into v_obligation
  from public.sdf_milestone_one_obligations
  where obligation_id = new.obligation_id;
  if not found then
    raise exception using errcode = '23503', message = 'SDF_M1_OBLIGATION_REQUIRED';
  end if;

  select * into strict v_terms
  from public.sdf_accepted_commercial_terms
  where accepted_terms_id = v_obligation.accepted_terms_id;
    select application_reference into strict v_application_reference
    from public.quote_requests
    where id = v_terms.quote_request_id;

  if new.quotation_id <> v_obligation.quotation_id
     or new.accepted_terms_id <> v_obligation.accepted_terms_id
     or new.quote_request_id <> v_terms.quote_request_id
      or new.application_reference <> v_application_reference
     or new.milestone_identity <> v_obligation.milestone_identity
     or new.percentage_basis_points <> v_obligation.percentage_basis_points
     or new.currency <> v_obligation.currency
     or new.net_amount_minor <> v_obligation.amount_minor
     or new.accepted_price_basis <> v_obligation.vat_basis
     or v_obligation.obligation_state <> 'EXPECTED' then
    raise exception using errcode = '23514', message = 'SDF_M1_INVOICE_CANDIDATE_LINKAGE_MISMATCH';
  end if;
  return new;
end;
$$;

create trigger trg_sdf_m1_invoice_candidates_guard
before insert on public.sdf_m1_invoice_candidates
for each row execute function public.guard_sdf_m1_invoice_candidate_v1();

create function public.allocate_sdf_invoice_number_v1(p_issue_year smallint)
returns table (invoice_number text, sequence integer)
language plpgsql
volatile
set search_path = public, pg_catalog
as $$
declare
  v_sequence integer;
begin
  if p_issue_year not between 2000 and 9999 then
    raise exception using errcode = '22023', message = 'SDF_INVOICE_YEAR_INVALID';
  end if;

  insert into public.sdf_invoice_number_counters as counter(issue_year, next_sequence)
  values (p_issue_year, 2)
  on conflict (issue_year) do update
    set next_sequence = counter.next_sequence + 1,
        updated_at = clock_timestamp()
    where counter.next_sequence <= 9999
  returning next_sequence - 1 into v_sequence;

  if v_sequence is null then
    raise exception using errcode = '22003', message = 'SDF_INVOICE_SEQUENCE_EXHAUSTED';
  end if;

  return query select
    'LWS-' || p_issue_year::text || '-' || lpad(v_sequence::text, 4, '0'),
    v_sequence;
end;
$$;

create function public.register_sdf_invoice_template_authority_v1(
  p_template_id text,
  p_template_version text,
  p_document_reference text,
  p_document_sha256 text,
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
  v_fingerprint text;
  v_existing public.sdf_invoice_template_authorities%rowtype;
  v_template public.sdf_invoice_template_authorities%rowtype;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator from public.commercial_operators where auth_user_id = v_subject;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner','admin') then
    raise exception using errcode = '42501', message = 'SDF_INVOICE_AUTHORITY_DENIED';
  end if;
  if nullif(btrim(p_template_id), '') is null
     or nullif(btrim(p_template_version), '') is null
     or nullif(btrim(p_document_reference), '') is null
     or p_document_reference ~ '^[A-Za-z][A-Za-z0-9+.-]*://'
     or position('?' in p_document_reference) > 0
     or position('#' in p_document_reference) > 0
     or p_document_sha256 !~ '^[0-9a-f]{64}$'
     or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'SDF_INVOICE_TEMPLATE_IDENTITY_INVALID';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'documentReference',p_document_reference,
    'documentSha256',p_document_sha256,
    'documentType','INVOICE',
    'milestoneIdentity','M1',
    'templateId',p_template_id,
    'templateVersion',p_template_version
  )::text,'UTF8'),'sha256'),'hex');

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  select * into v_existing from public.sdf_invoice_template_authorities
  where registration_idempotency_key = p_idempotency_key;
  if found then
    if rtrim(v_existing.registration_fingerprint) <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('template_authority_id',v_existing.template_authority_id,'was_created',false);
  end if;

  select * into v_existing from public.sdf_invoice_template_authorities
  where template_id = p_template_id and template_version = p_template_version;
  if found then
    if rtrim(v_existing.registration_fingerprint) <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'SDF_INVOICE_TEMPLATE_IDENTITY_CONFLICT';
    end if;
    return jsonb_build_object('template_authority_id',v_existing.template_authority_id,'was_created',false);
  end if;

  insert into public.sdf_invoice_template_authorities(
    document_type,milestone_identity,template_id,template_version,document_reference,
    document_sha256,registration_idempotency_key,registration_fingerprint,created_by_operator_id
  ) values (
    'INVOICE','M1',p_template_id,p_template_version,p_document_reference,
    p_document_sha256,p_idempotency_key,v_fingerprint,v_operator.operator_id
  ) returning * into v_template;

  return jsonb_build_object('template_authority_id',v_template.template_authority_id,'was_created',true);
end;
$$;

create function public.prepare_sdf_m1_invoice_candidate_v1(
  p_obligation_id uuid,
  p_template_authority_id uuid,
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
  v_obligation public.sdf_milestone_one_obligations%rowtype;
  v_terms public.sdf_accepted_commercial_terms%rowtype;
  v_request public.quote_requests%rowtype;
  v_template public.sdf_invoice_template_authorities%rowtype;
  v_existing public.sdf_m1_invoice_candidates%rowtype;
  v_candidate public.sdf_m1_invoice_candidates%rowtype;
  v_seller jsonb;
  v_customer jsonb;
  v_bank jsonb;
  v_template_snapshot jsonb;
  v_payload jsonb;
  v_payload_sha256 text;
  v_fingerprint text;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator from public.commercial_operators where auth_user_id = v_subject;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner','admin') then
    raise exception using errcode = '42501', message = 'SDF_INVOICE_AUTHORITY_DENIED';
  end if;
  if p_obligation_id is null or p_template_authority_id is null or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'SDF_INVOICE_CANDIDATE_INPUT_INVALID';
  end if;

  select * into v_obligation from public.sdf_milestone_one_obligations
  where obligation_id = p_obligation_id;
  if not found then raise exception using errcode = '23503', message = 'SDF_M1_OBLIGATION_REQUIRED'; end if;
  select * into strict v_terms from public.sdf_accepted_commercial_terms
  where accepted_terms_id = v_obligation.accepted_terms_id;
  select * into strict v_request from public.quote_requests where id = v_terms.quote_request_id;
  if v_request.application_reference is null then
    raise exception using errcode = '23514', message = 'SDF_APPLICATION_REFERENCE_REQUIRED';
  end if;
  select * into v_template from public.sdf_invoice_template_authorities
  where template_authority_id = p_template_authority_id;
  if not found then raise exception using errcode = '23503', message = 'SDF_INVOICE_TEMPLATE_AUTHORITY_REQUIRED'; end if;

  v_seller := jsonb_build_object(
    'legal_name','Lorenzo Bombello',
    'trade_name','Lorenzo Web Solutions',
    'address_line_1','Grote Baan 164 bus 1002',
    'postal_code','9920',
    'city','Lievegem',
    'country_code','BE',
    'enterprise_number','0742.361.487',
    'vat_identification_number','BE 0742.361.487'
  );
  v_customer := jsonb_build_object(
    'customer_type',v_request.customer_type,
    'legal_name',coalesce(nullif(btrim(v_request.company),''),v_request.name),
    'contact_name',v_request.name,
    'email',v_request.email,
    'billing_email',v_request.billing_email,
    'enterprise_number',v_request.enterprise_number,
    'vat_identification_number',v_request.vat_number,
    'address_line_1',v_request.billing_address,
    'postal_code',v_request.billing_postal_code,
    'city',v_request.billing_city,
    'country_code',v_request.billing_country
  );
  v_bank := jsonb_build_object('bank','KBC','iban','BE42 7380 5510 8954','bic','KREDBEBB');
  v_template_snapshot := jsonb_build_object(
    'template_authority_id',v_template.template_authority_id,
    'template_id',v_template.template_id,
    'template_version',v_template.template_version,
    'document_reference',v_template.document_reference,
    'document_sha256',rtrim(v_template.document_sha256)
  );
  v_payload := jsonb_build_object(
    'acceptedPriceBasis',v_obligation.vat_basis,
    'acceptedTermsId',v_obligation.accepted_terms_id,
    'applicationReference',v_request.application_reference,
    'bank',v_bank,
    'currency',v_obligation.currency,
    'customer',v_customer,
    'milestoneIdentity',v_obligation.milestone_identity,
    'netAmountMinor',v_obligation.amount_minor,
    'obligationId',v_obligation.obligation_id,
    'percentageBasisPoints',v_obligation.percentage_basis_points,
    'quotationId',v_obligation.quotation_id,
    'seller',v_seller,
    'template',v_template_snapshot
  );
  v_payload_sha256 := encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'candidatePayloadSha256',v_payload_sha256,
    'obligationId',p_obligation_id,
    'templateAuthorityId',p_template_authority_id
  )::text,'UTF8'),'sha256'),'hex');

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  select * into v_existing from public.sdf_m1_invoice_candidates
  where creation_idempotency_key = p_idempotency_key;
  if found then
    if rtrim(v_existing.creation_fingerprint) <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'candidate_id',v_existing.candidate_id,
      'candidate_state',v_existing.candidate_state,
      'invoice_number',null,
      'was_created',false
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obligation_id::text,0));
  select * into v_existing from public.sdf_m1_invoice_candidates
  where obligation_id = p_obligation_id;
  if found then
    if rtrim(v_existing.creation_fingerprint) <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'SDF_M1_INVOICE_CANDIDATE_CONFLICT';
    end if;
    return jsonb_build_object(
      'candidate_id',v_existing.candidate_id,
      'candidate_state',v_existing.candidate_state,
      'invoice_number',null,
      'was_created',false
    );
  end if;

  insert into public.sdf_m1_invoice_candidates(
    obligation_id,quotation_id,accepted_terms_id,quote_request_id,application_reference,template_authority_id,
    candidate_state,milestone_identity,percentage_basis_points,currency,net_amount_minor,
    accepted_price_basis,seller_snapshot,customer_snapshot,bank_snapshot,template_snapshot,
    candidate_payload_sha256,creation_idempotency_key,creation_fingerprint,prepared_by_operator_id
  ) values (
    v_obligation.obligation_id,v_obligation.quotation_id,v_obligation.accepted_terms_id,v_terms.quote_request_id,
    v_request.application_reference,
    v_template.template_authority_id,'PREPARED',v_obligation.milestone_identity,
    v_obligation.percentage_basis_points,v_obligation.currency,v_obligation.amount_minor,
    v_obligation.vat_basis,v_seller,v_customer,v_bank,v_template_snapshot,
    v_payload_sha256,p_idempotency_key,v_fingerprint,v_operator.operator_id
  ) returning * into v_candidate;

  return jsonb_build_object(
    'candidate_id',v_candidate.candidate_id,
    'candidate_state',v_candidate.candidate_state,
    'invoice_number',null,
    'was_created',true
  );
end;
$$;

create function public.issue_sdf_m1_invoice_v1(
  p_candidate_id uuid,
  p_issue_year smallint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
begin
  raise exception using errcode = 'P0001', message = 'SDF_VAT_AUTHORITY_NOT_ACTIVE';
end;
$$;

alter table public.sdf_invoice_number_counters enable row level security;
alter table public.sdf_invoice_number_counters force row level security;
alter table public.sdf_invoice_template_authorities enable row level security;
alter table public.sdf_invoice_template_authorities force row level security;
alter table public.sdf_m1_invoice_candidates enable row level security;
alter table public.sdf_m1_invoice_candidates force row level security;
alter table public.sdf_m1_invoice_issuances enable row level security;
alter table public.sdf_m1_invoice_issuances force row level security;

revoke all privileges on table public.sdf_invoice_number_counters,
  public.sdf_invoice_template_authorities,
  public.sdf_m1_invoice_candidates,
  public.sdf_m1_invoice_issuances
from public, anon, authenticated, service_role;
revoke all on function public.prevent_sdf_invoice_foundation_mutation_v1()
from public, anon, authenticated, service_role;
revoke all on function public.guard_sdf_m1_invoice_candidate_v1()
from public, anon, authenticated, service_role;
revoke all on function public.allocate_sdf_invoice_number_v1(smallint)
from public, anon, authenticated, service_role;
revoke all on function public.register_sdf_invoice_template_authority_v1(text,text,text,text,uuid)
from public, anon, authenticated, service_role;
revoke all on function public.prepare_sdf_m1_invoice_candidate_v1(uuid,uuid,uuid)
from public, anon, authenticated, service_role;
revoke all on function public.issue_sdf_m1_invoice_v1(uuid,smallint,uuid)
from public, anon, authenticated, service_role;

grant execute on function public.register_sdf_invoice_template_authority_v1(text,text,text,text,uuid)
to authenticated;
grant execute on function public.prepare_sdf_m1_invoice_candidate_v1(uuid,uuid,uuid)
to authenticated;
grant execute on function public.issue_sdf_m1_invoice_v1(uuid,smallint,uuid)
to authenticated;

comment on function public.allocate_sdf_invoice_number_v1(smallint) is
  'Internal concurrency-safe LWS-YYYY-NNNN allocator for a future atomic issuance transaction. Candidate preparation never calls this function.';
comment on function public.issue_sdf_m1_invoice_v1(uuid,smallint,uuid) is
  'Deliberately fail-closed policy-neutral boundary. Always rejects before number allocation until explicit SDF VAT production authority is activated.';

alter function public.get_operator_application_v1(uuid, text)
  rename to get_operator_application_v1_pre_sdf_m1_invoice;

create function public.get_operator_application_v1(
  p_quote_request_id uuid default null,
  p_application_reference text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_result jsonb;
  v_candidate public.sdf_m1_invoice_candidates%rowtype;
begin
  v_result := public.get_operator_application_v1_pre_sdf_m1_invoice(
    p_quote_request_id,
    p_application_reference
  );

  select candidate.* into v_candidate
  from public.sdf_m1_invoice_candidates as candidate
  where candidate.quote_request_id = (v_result->>'quote_request_id')::uuid;

  if not found then
    return v_result || jsonb_build_object('sdf_m1_invoice_candidate',null);
  end if;

  return v_result || jsonb_build_object(
    'sdf_m1_invoice_candidate',jsonb_build_object(
      'candidate_id',v_candidate.candidate_id,
      'candidate_state',v_candidate.candidate_state,
      'application_reference',v_candidate.application_reference,
      'milestone_identity',v_candidate.milestone_identity,
      'percentage_basis_points',v_candidate.percentage_basis_points,
      'currency',v_candidate.currency,
      'net_amount_minor',v_candidate.net_amount_minor,
      'template_binding_present',v_candidate.template_authority_id is not null,
      'invoice_number',null,
      'fiscal_authority_state','NOT_ACTIVE',
      'production_issuance_available',false,
      'prepared_at',v_candidate.prepared_at
    )
  );
end;
$$;

revoke all on function public.get_operator_application_v1_pre_sdf_m1_invoice(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.get_operator_application_v1(uuid, text)
from public, anon, authenticated, service_role;
grant execute on function public.get_operator_application_v1(uuid, text)
to authenticated;
