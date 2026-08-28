do $$
begin
  if exists (select 1 from public.quotation_vat_decision_authorities) then
    raise exception using
      errcode = 'P0001',
      message = 'LEGACY_VAT_AUTHORITY_REVIEW_REQUIRED';
  end if;
end;
$$;

create function public.is_valid_quotation_vat_authority_v1(p_authority jsonb)
returns boolean
language sql
immutable
set search_path = public, pg_catalog
as $$
  select public.jsonb_has_exact_keys(p_authority, array[
    'authority_family', 'decision_code', 'decision_version', 'effective_from',
    'jurisdiction', 'regime_code', 'vat_treatment', 'rate_semantics',
    'vat_rate', 'invoice_literal', 'applicability_code', 'unsupported_behavior',
    'threshold_year', 'applicable_threshold_minor'
  ])
  and p_authority->>'authority_family' = 'LWS_OUTGOING_VAT'
  and p_authority->>'decision_code' = 'BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION'
  and p_authority->>'decision_version' = '1.0.0'
  and p_authority->>'effective_from' = '2026-08-08'
  and p_authority->>'jurisdiction' = 'BE'
  and p_authority->>'regime_code' = 'SMALL_ENTERPRISE_EXEMPTION'
  and p_authority->>'vat_treatment' = 'EXEMPT'
  and p_authority->>'rate_semantics' = 'NOT_APPLICABLE'
  and p_authority->'vat_rate' = '0'::jsonb
  and p_authority->>'invoice_literal' = 'Bijzondere vrijstellingsregeling van belasting'
  and p_authority->>'applicability_code' = 'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION_V1'
  and p_authority->>'unsupported_behavior' = 'FAIL_CLOSED'
  and p_authority->'threshold_year' = '2026'::jsonb
  and p_authority->'applicable_threshold_minor' = '1000000'::jsonb;
$$;

create function public.quotation_vat_authority_sha256_v1(p_authority jsonb)
returns text
language sql
immutable
set search_path = public, extensions, pg_catalog
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'annual_threshold_minor', p_authority->'annual_threshold_minor',
    'applicability_code', p_authority->'applicability_code',
    'applicable_threshold_minor', p_authority->'applicable_threshold_minor',
    'approved_at', p_authority->'approved_at',
    'approved_by', p_authority->'approved_by',
    'authority_family', p_authority->'authority_family',
    'authority_source_identifier', p_authority->'authority_source_identifier',
    'business_start_date', p_authority->'business_start_date',
    'decision_code', p_authority->'decision_code',
    'decision_version', p_authority->'decision_version',
    'effective_from', p_authority->'effective_from',
    'effective_until', p_authority->'effective_until',
    'elapsed_calendar_days', p_authority->'elapsed_calendar_days',
    'invoice_literal', p_authority->'invoice_literal',
    'jurisdiction', p_authority->'jurisdiction',
    'legal_provenance', p_authority->'legal_provenance',
    'predecessor_authority_id', p_authority->'predecessor_authority_id',
    'rate_semantics', p_authority->'rate_semantics',
    'regime_code', p_authority->'regime_code',
    'registration_provenance', p_authority->'registration_provenance',
    'remaining_calendar_days', p_authority->'remaining_calendar_days',
    'threshold_year', p_authority->'threshold_year',
    'unsupported_behavior', p_authority->'unsupported_behavior',
    'vat_decision_authority_id', p_authority->'vat_decision_authority_id',
    'vat_rate', p_authority->'vat_rate',
    'vat_treatment', p_authority->'vat_treatment'
  )::text, 'UTF8'), 'sha256'), 'hex')
$$;

comment on function public.quotation_vat_authority_sha256_v1(jsonb) is
  'Canonical VAT governance fingerprint over authority identity, meaning, effectivity, provenance, and approval metadata. Creation and retirement bookkeeping are excluded because lifecycle rotation is governed separately.';

alter table public.quotation_vat_decision_authorities
  add column authority_family text not null,
  add column effective_from date not null,
  add column effective_until date,
  add column jurisdiction text not null,
  add column regime_code text not null,
  add column rate_semantics text not null,
  add column invoice_literal text not null,
  add column threshold_year integer not null,
  add column annual_threshold_minor bigint not null,
  add column applicable_threshold_minor bigint not null,
  add column business_start_date date not null,
  add column elapsed_calendar_days integer not null,
  add column remaining_calendar_days integer not null,
  add column applicability_code text not null,
  add column unsupported_behavior text not null,
  add column registration_provenance jsonb not null,
  add column legal_provenance jsonb not null,
  add column authority_sha256 char(64) not null,
  add column predecessor_authority_id uuid references public.quotation_vat_decision_authorities(vat_decision_authority_id);

drop index public.quotation_vat_decision_one_approved;
create unique index quotation_vat_decision_one_approved
on public.quotation_vat_decision_authorities (authority_family)
where status = 'APPROVED';

alter table public.quotation_vat_decision_authorities
  add constraint quotation_vat_authority_effectivity_valid check (
    effective_until is null or effective_until >= effective_from
  ),
  add constraint quotation_vat_authority_threshold_valid check (
    threshold_year = 2026
    and annual_threshold_minor = 2500000
    and applicable_threshold_minor = 1000000
    and business_start_date = '2026-08-08'::date
    and elapsed_calendar_days = 219
    and remaining_calendar_days = 146
  ),
  add constraint quotation_vat_authority_provenance_valid check (
    public.jsonb_has_exact_keys(registration_provenance, array[
      'document_name', 'dossier_number', 'enterprise_number', 'trade_name',
      'vat_regime', 'effective_from', 'sha256'
    ])
    and registration_provenance->>'document_name' = 'Liantis_Dossieroverzicht_Creatiedossier_2026-08-07.pdf'
    and registration_provenance->>'dossier_number' = '001804353-56'
    and registration_provenance->>'enterprise_number' = '0742.361.487'
    and registration_provenance->>'trade_name' = 'Lorenzo Web Solutions'
    and registration_provenance->>'vat_regime' = 'Vrijstelling'
    and registration_provenance->>'effective_from' = '2026-08-08'
    and registration_provenance->>'sha256' = lower('5DF9C764938FD007315273B016CF445B944BC227B5583A212AB8738A2B9FAC7F')
    and public.jsonb_has_exact_keys(legal_provenance, array[
      'title', 'document_id', 'document_date', 'last_modified',
      'fisconetplus_date', 'status', 'api_path', 'page', 'literal', 'sha256'
    ])
    and legal_provenance->>'document_id' = '0cb8f71e-6522-47c2-9134-8c15300d3507'
    and legal_provenance->>'document_date' = '2026-04-01'
    and legal_provenance->>'last_modified' = '2026-04-20'
    and legal_provenance->>'fisconetplus_date' = '2026-03-17'
    and legal_provenance->>'status' = 'Published'
    and legal_provenance->>'api_path' = '/myminfin-rest/fisconetPlus/public/document/0cb8f71e-6522-47c2-9134-8c15300d3507'
    and legal_provenance->'page' = '15'::jsonb
    and legal_provenance->>'literal' = invoice_literal
    and legal_provenance->>'sha256' = lower('B325F900CC163339EEBC3C71EBD8AD280C29C858D070B7AC0474B7CF0AB114FB')
  ),
  add constraint quotation_vat_authority_semantics_valid check (
    public.is_valid_quotation_vat_authority_v1(jsonb_build_object(
      'authority_family', authority_family,
      'decision_code', decision_code,
      'decision_version', decision_version,
      'effective_from', effective_from,
      'jurisdiction', jurisdiction,
      'regime_code', regime_code,
      'vat_treatment', vat_treatment,
      'rate_semantics', rate_semantics,
      'vat_rate', vat_rate,
      'invoice_literal', invoice_literal,
      'applicability_code', applicability_code,
      'unsupported_behavior', unsupported_behavior,
      'threshold_year', threshold_year,
      'applicable_threshold_minor', applicable_threshold_minor
    ))
  ),
  add constraint quotation_vat_authority_sha256_valid check (
    authority_sha256 ~ '^[0-9a-f]{64}$'
    and authority_sha256 = public.quotation_vat_authority_sha256_v1(
      to_jsonb(quotation_vat_decision_authorities) - 'authority_sha256'
    )
  );

with canonical as (
  select
    jsonb_build_object(
      'document_name', 'Liantis_Dossieroverzicht_Creatiedossier_2026-08-07.pdf',
      'dossier_number', '001804353-56',
      'enterprise_number', '0742.361.487',
      'trade_name', 'Lorenzo Web Solutions',
      'vat_regime', 'Vrijstelling',
      'effective_from', '2026-08-08',
      'sha256', lower('5DF9C764938FD007315273B016CF445B944BC227B5583A212AB8738A2B9FAC7F')
    ) as registration_provenance,
    jsonb_build_object(
      'title', 'Brochure - 9 vragen omtrent de vrijstellingsregeling van belasting voor kleine ondernemingen. Editie 2026',
      'document_id', '0cb8f71e-6522-47c2-9134-8c15300d3507',
      'document_date', '2026-04-01',
      'last_modified', '2026-04-20',
      'fisconetplus_date', '2026-03-17',
      'status', 'Published',
      'api_path', '/myminfin-rest/fisconetPlus/public/document/0cb8f71e-6522-47c2-9134-8c15300d3507',
      'page', 15,
      'literal', 'Bijzondere vrijstellingsregeling van belasting',
      'sha256', lower('B325F900CC163339EEBC3C71EBD8AD280C29C858D070B7AC0474B7CF0AB114FB')
    ) as legal_provenance
), authority as (
  select *, jsonb_build_object(
    'annual_threshold_minor', 2500000,
    'applicability_code', 'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION_V1',
    'applicable_threshold_minor', 1000000,
    'approved_at', '2026-08-28T00:00:00Z'::timestamptz,
    'approved_by', 'VAT_AUTHORITY_REMEDIATION:2026-08-28',
    'authority_family', 'LWS_OUTGOING_VAT',
    'authority_source_identifier', 'FOD_FINANCIEN:0cb8f71e-6522-47c2-9134-8c15300d3507:PAGE_15',
    'business_start_date', '2026-08-08'::date,
    'decision_code', 'BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION',
    'decision_version', '1.0.0',
    'effective_from', '2026-08-08'::date,
    'effective_until', null,
    'elapsed_calendar_days', 219,
    'invoice_literal', 'Bijzondere vrijstellingsregeling van belasting',
    'jurisdiction', 'BE',
    'legal_provenance', legal_provenance,
    'predecessor_authority_id', null,
    'rate_semantics', 'NOT_APPLICABLE',
    'regime_code', 'SMALL_ENTERPRISE_EXEMPTION',
    'registration_provenance', registration_provenance,
    'remaining_calendar_days', 146,
    'threshold_year', 2026,
    'unsupported_behavior', 'FAIL_CLOSED',
    'vat_decision_authority_id', 'b1030000-0000-4000-8000-000000000001'::uuid,
    'vat_rate', 0::numeric(7,4),
    'vat_treatment', 'EXEMPT'
  ) as authority_document
  from canonical
)
insert into public.quotation_vat_decision_authorities (
  vat_decision_authority_id, authority_family, decision_code, decision_version,
  effective_from, jurisdiction, regime_code, vat_treatment, rate_semantics,
  vat_rate, invoice_literal, authority_source_identifier, threshold_year,
  annual_threshold_minor, applicable_threshold_minor, business_start_date,
  elapsed_calendar_days, remaining_calendar_days, applicability_code,
  unsupported_behavior, registration_provenance, legal_provenance,
  authority_sha256, status, approved_by, approved_at
)
select
  'b1030000-0000-4000-8000-000000000001',
  'LWS_OUTGOING_VAT', 'BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION', '1.0.0',
  '2026-08-08', 'BE', 'SMALL_ENTERPRISE_EXEMPTION', 'EXEMPT',
  'NOT_APPLICABLE', 0, 'Bijzondere vrijstellingsregeling van belasting',
  'FOD_FINANCIEN:0cb8f71e-6522-47c2-9134-8c15300d3507:PAGE_15',
  2026, 2500000, 1000000, '2026-08-08', 219, 146,
  'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION_V1', 'FAIL_CLOSED',
  registration_provenance, legal_provenance,
  encode(extensions.digest(convert_to(authority_document::text, 'UTF8'), 'sha256'), 'hex'),
  'APPROVED', 'VAT_AUTHORITY_REMEDIATION:2026-08-28', '2026-08-28T00:00:00Z'
from authority;

create function public.prevent_quotation_vat_governance_mutation_v1()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception using errcode = '55000', message = 'QUOTATION_VAT_GOVERNANCE_IMMUTABLE';
end;
$$;

create function public.quotation_vat_context_sha256_v1(p_quote_request_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_request public.quote_requests%rowtype;
begin
  select * into v_request from public.quote_requests where id = p_quote_request_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'QUOTATION_VAT_CONTEXT_REQUIRED';
  end if;
  return encode(extensions.digest(convert_to(jsonb_build_object(
    'billing_country', upper(coalesce(v_request.billing_country, '')),
    'customer_type', v_request.customer_type,
    'enterprise_number', v_request.enterprise_number,
    'enterprise_validation_status', v_request.enterprise_validation_status,
    'quote_request_id', v_request.id,
    'vat_number', v_request.vat_number,
    'vat_validated_at', v_request.vat_validated_at,
    'vat_validation_status', v_request.vat_validation_status
  )::text, 'UTF8'), 'sha256'), 'hex');
end;
$$;

create table public.quotation_vat_transaction_classifications (
  classification_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null references public.quote_requests(id),
  context_sha256 char(64) not null check (context_sha256 ~ '^[0-9a-f]{64}$'),
  classification_code text not null check (
    classification_code = 'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION'
  ),
  source_reference text not null check (nullif(btrim(source_reference), '') is not null),
  source_sha256 char(64) not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  classified_by text not null check (nullif(btrim(classified_by), '') is not null),
  classified_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint quotation_vat_transaction_classification_unique
    unique (quote_request_id, context_sha256, classification_code)
);

create trigger trg_quotation_vat_transaction_classification_immutable
before update or delete on public.quotation_vat_transaction_classifications
for each row execute function public.prevent_quotation_vat_governance_mutation_v1();

create table public.quotation_vat_turnover_snapshots (
  turnover_snapshot_id uuid primary key default gen_random_uuid(),
  vat_decision_authority_id uuid not null references public.quotation_vat_decision_authorities(vat_decision_authority_id),
  threshold_year integer not null check (threshold_year = 2026),
  measurement_watermark date not null,
  governed_turnover_minor bigint not null check (governed_turnover_minor >= 0),
  currency text not null check (currency = 'EUR'),
  state text not null check (
    (state = 'BELOW_OR_AT_THRESHOLD' and governed_turnover_minor <= 1000000)
    or (state = 'AUTHORITY_REVIEW_REQUIRED' and governed_turnover_minor > 1000000)
  ),
  source_reference text not null check (nullif(btrim(source_reference), '') is not null),
  source_sha256 char(64) not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  predecessor_snapshot_id uuid unique references public.quotation_vat_turnover_snapshots(turnover_snapshot_id),
  recorded_by text not null check (nullif(btrim(recorded_by), '') is not null),
  recorded_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp()
);

create trigger trg_quotation_vat_turnover_snapshot_immutable
before update or delete on public.quotation_vat_turnover_snapshots
for each row execute function public.prevent_quotation_vat_governance_mutation_v1();

create function public.record_quotation_vat_transaction_classification_v1(
  p_quote_request_id uuid,
  p_source_reference text,
  p_source_sha256 text,
  p_classified_by text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public, pg_catalog
as $$
declare
  v_id uuid;
begin
  if p_quote_request_id is null
     or nullif(btrim(p_source_reference), '') is null
     or p_source_sha256 !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_classified_by), '') is null then
    raise exception using errcode = '22023', message = 'QUOTATION_VAT_CLASSIFICATION_INVALID';
  end if;
  insert into public.quotation_vat_transaction_classifications (
    quote_request_id, context_sha256, classification_code,
    source_reference, source_sha256, classified_by, classified_at
  ) values (
    p_quote_request_id,
    public.quotation_vat_context_sha256_v1(p_quote_request_id),
    'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION',
    p_source_reference, p_source_sha256, p_classified_by, clock_timestamp()
  ) returning classification_id into v_id;
  return v_id;
exception
  when unique_violation then
    raise exception using errcode = 'P0001', message = 'QUOTATION_VAT_CLASSIFICATION_CONFLICT';
end;
$$;

create function public.record_quotation_vat_turnover_snapshot_v1(
  p_measurement_watermark date,
  p_governed_turnover_minor bigint,
  p_source_reference text,
  p_source_sha256 text,
  p_predecessor_snapshot_id uuid,
  p_recorded_by text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public, pg_catalog
as $$
declare
  v_authority_id uuid;
  v_id uuid;
begin
  if p_measurement_watermark is null
     or extract(year from p_measurement_watermark)::integer <> 2026
     or p_governed_turnover_minor is null or p_governed_turnover_minor < 0
     or nullif(btrim(p_source_reference), '') is null
     or p_source_sha256 !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_recorded_by), '') is null then
    raise exception using errcode = '22023', message = 'QUOTATION_VAT_TURNOVER_SNAPSHOT_INVALID';
  end if;
  select vat_decision_authority_id into strict v_authority_id
  from public.quotation_vat_decision_authorities
  where authority_family = 'LWS_OUTGOING_VAT' and status = 'APPROVED';
  if exists (
    select 1 from public.quotation_vat_turnover_snapshots
    where vat_decision_authority_id = v_authority_id
      and threshold_year = 2026
      and measurement_watermark = p_measurement_watermark
  ) then
    raise exception using errcode = 'P0001', message = 'QUOTATION_VAT_TURNOVER_SNAPSHOT_CONFLICT';
  end if;
  insert into public.quotation_vat_turnover_snapshots (
    vat_decision_authority_id, threshold_year, measurement_watermark,
    governed_turnover_minor, currency, state, source_reference, source_sha256,
    predecessor_snapshot_id, recorded_by, recorded_at
  ) values (
    v_authority_id, 2026, p_measurement_watermark, p_governed_turnover_minor,
    'EUR', case when p_governed_turnover_minor <= 1000000
      then 'BELOW_OR_AT_THRESHOLD' else 'AUTHORITY_REVIEW_REQUIRED' end,
    p_source_reference, p_source_sha256, p_predecessor_snapshot_id,
    p_recorded_by, clock_timestamp()
  ) returning turnover_snapshot_id into v_id;
  return v_id;
exception
  when no_data_found then
    raise exception using errcode = 'P0001', message = 'QUOTATION_VAT_DECISION_NOT_APPROVED';
  when unique_violation then
    raise exception using errcode = 'P0001', message = 'QUOTATION_VAT_TURNOVER_SNAPSHOT_CONFLICT';
end;
$$;

create function public.resolve_quotation_vat_authority_v1(
  p_quote_request_id uuid,
  p_resolution_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_request public.quote_requests%rowtype;
  v_authority public.quotation_vat_decision_authorities%rowtype;
  v_classification public.quotation_vat_transaction_classifications%rowtype;
  v_turnover public.quotation_vat_turnover_snapshots%rowtype;
  v_count integer;
  v_context_sha256 text;
begin
  if p_resolution_date is null then
    raise exception using errcode = 'P0001', message = 'QUOTATION_VAT_DECISION_NOT_APPROVED';
  end if;

  select count(*)::integer into v_count
  from public.quotation_vat_decision_authorities
  where authority_family = 'LWS_OUTGOING_VAT'
    and status = 'APPROVED'
    and effective_from <= p_resolution_date
    and (effective_until is null or effective_until >= p_resolution_date);
  if v_count <> 1 then
    raise exception using errcode = 'P0001', message = 'QUOTATION_VAT_DECISION_NOT_APPROVED';
  end if;
  select * into strict v_authority
  from public.quotation_vat_decision_authorities
  where authority_family = 'LWS_OUTGOING_VAT'
    and status = 'APPROVED'
    and effective_from <= p_resolution_date
    and (effective_until is null or effective_until >= p_resolution_date);

  select * into v_request from public.quote_requests where id = p_quote_request_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'QUOTATION_VAT_CONTEXT_REQUIRED';
  end if;
  if upper(coalesce(v_request.billing_country, '')) <> v_authority.jurisdiction then
    raise exception using errcode = 'P0001', message = 'QUOTATION_VAT_CONTEXT_UNSUPPORTED';
  end if;

  v_context_sha256 := public.quotation_vat_context_sha256_v1(p_quote_request_id);
  select count(*)::integer into v_count
  from public.quotation_vat_transaction_classifications
  where quote_request_id = p_quote_request_id
    and context_sha256 = v_context_sha256
    and classification_code = 'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION';
  if v_count <> 1 then
    raise exception using errcode = 'P0001', message = 'QUOTATION_VAT_CONTEXT_REQUIRED';
  end if;
  select * into strict v_classification
  from public.quotation_vat_transaction_classifications
  where quote_request_id = p_quote_request_id
    and context_sha256 = v_context_sha256
    and classification_code = 'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION';

  select count(*)::integer into v_count
  from public.quotation_vat_turnover_snapshots
  where vat_decision_authority_id = v_authority.vat_decision_authority_id
    and threshold_year = v_authority.threshold_year
    and measurement_watermark = p_resolution_date;
  if v_count <> 1 then
    raise exception using
      errcode = 'P0001',
      message = 'QUOTATION_VAT_THRESHOLD_AUTHORITY_REVIEW_REQUIRED';
  end if;
  select * into strict v_turnover
  from public.quotation_vat_turnover_snapshots
  where vat_decision_authority_id = v_authority.vat_decision_authority_id
    and threshold_year = v_authority.threshold_year
    and measurement_watermark = p_resolution_date;
  if v_turnover.state <> 'BELOW_OR_AT_THRESHOLD'
     or v_turnover.governed_turnover_minor > v_authority.applicable_threshold_minor then
    raise exception using errcode = 'P0001', message = 'AUTHORITY_REVIEW_REQUIRED';
  end if;

  return jsonb_build_object(
    'vat_decision_authority_id', v_authority.vat_decision_authority_id,
    'authority_family', v_authority.authority_family,
    'decision_code', v_authority.decision_code,
    'decision_version', v_authority.decision_version,
    'authority_sha256', rtrim(v_authority.authority_sha256),
    'vat_treatment', v_authority.vat_treatment,
    'rate_semantics', v_authority.rate_semantics,
    'vat_rate', v_authority.vat_rate,
    'invoice_literal', v_authority.invoice_literal,
    'context_sha256', v_context_sha256,
    'classification_id', v_classification.classification_id,
    'turnover_snapshot_id', v_turnover.turnover_snapshot_id,
    'applicable_threshold_minor', v_authority.applicable_threshold_minor,
    'governed_turnover_minor', v_turnover.governed_turnover_minor
  );
end;
$$;

create table public.quotation_business_draft_vat_bindings (
  business_draft_id uuid primary key references public.quote_request_quotation_business_drafts(business_draft_id),
  vat_decision_authority_id uuid not null references public.quotation_vat_decision_authorities(vat_decision_authority_id),
  authority_family text not null,
  decision_code text not null,
  decision_version text not null,
  authority_sha256 char(64) not null check (authority_sha256 ~ '^[0-9a-f]{64}$'),
  vat_treatment text not null check (vat_treatment = 'EXEMPT'),
  rate_semantics text not null check (rate_semantics = 'NOT_APPLICABLE'),
  invoice_literal text not null check (invoice_literal = 'Bijzondere vrijstellingsregeling van belasting'),
  context_sha256 char(64) not null check (context_sha256 ~ '^[0-9a-f]{64}$'),
  classification_id uuid not null references public.quotation_vat_transaction_classifications(classification_id),
  turnover_snapshot_id uuid not null references public.quotation_vat_turnover_snapshots(turnover_snapshot_id),
  created_at timestamptz not null default clock_timestamp()
);

create function public.validate_quotation_business_draft_vat_binding_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_authority public.quotation_vat_decision_authorities%rowtype;
begin
  select * into v_authority
  from public.quotation_vat_decision_authorities
  where vat_decision_authority_id = new.vat_decision_authority_id;
  if v_authority.vat_decision_authority_id is null
     or new.authority_family is distinct from v_authority.authority_family
     or new.decision_code is distinct from v_authority.decision_code
     or new.decision_version is distinct from v_authority.decision_version
     or rtrim(new.authority_sha256) is distinct from rtrim(v_authority.authority_sha256)
     or new.vat_treatment is distinct from v_authority.vat_treatment
     or new.rate_semantics is distinct from v_authority.rate_semantics
     or new.invoice_literal is distinct from v_authority.invoice_literal then
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  end if;
  return new;
end;
$$;

create trigger trg_quotation_business_draft_vat_binding_validate
before insert on public.quotation_business_draft_vat_bindings
for each row execute function public.validate_quotation_business_draft_vat_binding_v1();

create trigger trg_quotation_business_draft_vat_binding_immutable
before update or delete on public.quotation_business_draft_vat_bindings
for each row execute function public.prevent_quotation_vat_governance_mutation_v1();

create or replace function public.upsert_quotation_business_draft_v2(
  p_actor_auth_user_id uuid,
  p_intake_id uuid,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_input jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_quote_request_id uuid;
  v_terms jsonb;
  v_vat jsonb;
  v_result jsonb;
  v_business public.quote_request_quotation_business_drafts%rowtype;
  v_binding public.quotation_business_draft_vat_bindings%rowtype;
  v_resolution_date date := (clock_timestamp() at time zone 'Europe/Brussels')::date;
begin
  if p_actor_auth_user_id is null or p_intake_id is null or p_idempotency_key is null
     or p_expected_revision is null or p_expected_revision < 0
     or not public.jsonb_has_exact_keys(p_input, array[
       'commercial_lines', 'discount', 'scope', 'payment_schedule', 'validity_days'
     ]) then
    raise exception using errcode = '22023', message = 'QUOTATION_BUSINESS_INPUT_INVALID';
  end if;

  select * into v_operator
  from public.commercial_operators
  where auth_user_id = p_actor_auth_user_id;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'QUOTATION_BUSINESS_SCOPE_DENIED';
  end if;

  select quote_request_id into v_quote_request_id
  from public.quote_request_intakes
  where id = p_intake_id;
  v_terms := public.resolve_quotation_terms_authority_v1(v_resolution_date);
  v_vat := public.resolve_quotation_vat_authority_v1(v_quote_request_id, v_resolution_date);

  v_result := public.upsert_quotation_business_draft_v1(
    p_actor_auth_user_id,
    p_intake_id,
    p_expected_revision,
    p_idempotency_key,
    p_input || jsonb_build_object(
      'terms_authority_id', v_terms->>'terms_authority_id',
      'vat_decision_authority_id', v_vat->>'vat_decision_authority_id'
    )
  );

  select * into strict v_business
  from public.quote_request_quotation_business_drafts
  where idempotency_key = p_idempotency_key;
  insert into public.quotation_business_draft_vat_bindings (
    business_draft_id, vat_decision_authority_id, authority_family,
    decision_code, decision_version,
    authority_sha256, vat_treatment, rate_semantics, invoice_literal,
    context_sha256, classification_id, turnover_snapshot_id
  ) values (
    v_business.business_draft_id,
    (v_vat->>'vat_decision_authority_id')::uuid,
    v_vat->>'authority_family', v_vat->>'decision_code',
    v_vat->>'decision_version', v_vat->>'authority_sha256',
    v_vat->>'vat_treatment', v_vat->>'rate_semantics', v_vat->>'invoice_literal',
    v_vat->>'context_sha256', (v_vat->>'classification_id')::uuid,
    (v_vat->>'turnover_snapshot_id')::uuid
  ) on conflict (business_draft_id) do nothing;

  select * into strict v_binding
  from public.quotation_business_draft_vat_bindings
  where business_draft_id = v_business.business_draft_id;
  if v_binding.vat_decision_authority_id is distinct from (v_vat->>'vat_decision_authority_id')::uuid
      or v_binding.authority_family is distinct from v_vat->>'authority_family'
      or v_binding.decision_code is distinct from v_vat->>'decision_code'
     or v_binding.decision_version is distinct from v_vat->>'decision_version'
     or rtrim(v_binding.authority_sha256) is distinct from v_vat->>'authority_sha256'
      or v_binding.vat_treatment is distinct from v_vat->>'vat_treatment'
      or v_binding.rate_semantics is distinct from v_vat->>'rate_semantics'
      or v_binding.invoice_literal is distinct from v_vat->>'invoice_literal'
     or v_binding.context_sha256 is distinct from v_vat->>'context_sha256' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
  end if;
  return v_result || jsonb_build_object('vat_authority_binding', to_jsonb(v_binding));
end;
$$;

create function public.assert_quotation_business_draft_vat_binding_v1(
  p_business_draft_id uuid,
  p_require_current boolean
)
returns void
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_business public.quote_request_quotation_business_drafts%rowtype;
  v_binding public.quotation_business_draft_vat_bindings%rowtype;
  v_authority public.quotation_vat_decision_authorities%rowtype;
  v_resolved jsonb;
begin
  select * into v_business from public.quote_request_quotation_business_drafts
  where business_draft_id = p_business_draft_id;
  select * into v_binding from public.quotation_business_draft_vat_bindings
  where business_draft_id = p_business_draft_id;
  select * into v_authority from public.quotation_vat_decision_authorities
  where vat_decision_authority_id = v_binding.vat_decision_authority_id;
  if v_business.business_draft_id is null or v_binding.business_draft_id is null
     or v_authority.vat_decision_authority_id is null
     or v_business.vat_decision_authority_id is distinct from v_binding.vat_decision_authority_id
    or v_authority.authority_family is distinct from v_binding.authority_family
    or v_authority.decision_code is distinct from v_binding.decision_code
     or v_authority.decision_version is distinct from v_binding.decision_version
     or rtrim(v_authority.authority_sha256) is distinct from rtrim(v_binding.authority_sha256)
     or v_authority.vat_treatment is distinct from v_binding.vat_treatment
     or v_authority.rate_semantics is distinct from v_binding.rate_semantics
     or v_authority.invoice_literal is distinct from v_binding.invoice_literal
     or v_business.canonical_payload->'vat_approval'->>'vat_treatment' is distinct from v_binding.vat_treatment
     or (v_business.canonical_payload->'vat_approval'->>'vat_rate')::numeric is distinct from v_authority.vat_rate
     or v_business.canonical_payload->'vat_approval'->>'vat_decision_source' is distinct from v_authority.authority_source_identifier
     or (v_business.canonical_payload->'totals'->>'vat_amount_minor')::bigint <> 0
     or (v_business.canonical_payload->'totals'->>'total_gross_minor')::bigint
        <> (v_business.canonical_payload->'totals'->>'vat_base_minor')::bigint
     or exists (
       select 1
       from jsonb_array_elements(v_business.canonical_payload->'line_items') as line(value)
       where line.value->>'vat_treatment' is distinct from v_binding.vat_treatment
          or (line.value->>'vat_rate')::numeric is distinct from v_authority.vat_rate
     ) then
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  end if;

  if p_require_current then
    v_resolved := public.resolve_quotation_vat_authority_v1(
      v_business.quote_request_id,
      (clock_timestamp() at time zone 'Europe/Brussels')::date
    );
    if v_authority.status <> 'APPROVED'
       or v_binding.vat_decision_authority_id is distinct from (v_resolved->>'vat_decision_authority_id')::uuid
       or v_binding.authority_family is distinct from v_resolved->>'authority_family'
       or v_binding.decision_code is distinct from v_resolved->>'decision_code'
       or v_binding.decision_version is distinct from v_resolved->>'decision_version'
       or rtrim(v_binding.authority_sha256) is distinct from v_resolved->>'authority_sha256'
       or rtrim(v_binding.context_sha256) is distinct from v_resolved->>'context_sha256'
       or v_binding.classification_id is distinct from (v_resolved->>'classification_id')::uuid
       or v_binding.turnover_snapshot_id is distinct from (v_resolved->>'turnover_snapshot_id')::uuid then
      raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
    end if;
  end if;
exception
  when others then
    if sqlerrm = 'APPROVAL_CONFLICT' then
      raise;
    end if;
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
end;
$$;

create function public.assert_quotation_business_draft_vat_binding_v1(
  p_business_draft_id uuid
)
returns void
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select public.assert_quotation_business_draft_vat_binding_v1(
    p_business_draft_id,
    true
  )
$$;

alter function public.resolve_quotation_business_approval_promotion_context_v1(uuid, uuid, bigint)
rename to resolve_quotation_business_approval_promotion_context_raw_v1;

create function public.resolve_quotation_business_approval_promotion_context_v1(
  p_actor_auth_user_id uuid,
  p_intake_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_context jsonb;
begin
  v_context := public.resolve_quotation_business_approval_promotion_context_raw_v1(
    p_actor_auth_user_id, p_intake_id, p_expected_revision
  );
  perform public.assert_quotation_business_draft_vat_binding_v1(
    (v_context->>'business_draft_id')::uuid,
    v_context->>'mode' = 'CREATE'
  );
  return v_context;
end;
$$;

alter table public.quotation_vat_transaction_classifications enable row level security;
alter table public.quotation_vat_transaction_classifications force row level security;
alter table public.quotation_vat_turnover_snapshots enable row level security;
alter table public.quotation_vat_turnover_snapshots force row level security;
alter table public.quotation_business_draft_vat_bindings enable row level security;
alter table public.quotation_business_draft_vat_bindings force row level security;

revoke all privileges on table public.quotation_vat_transaction_classifications from public, anon, authenticated, service_role;
revoke all privileges on table public.quotation_vat_turnover_snapshots from public, anon, authenticated, service_role;
revoke all privileges on table public.quotation_business_draft_vat_bindings from public, anon, authenticated, service_role;
revoke all on function public.is_valid_quotation_vat_authority_v1(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.quotation_vat_authority_sha256_v1(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.prevent_quotation_vat_governance_mutation_v1() from public, anon, authenticated, service_role;
revoke all on function public.validate_quotation_business_draft_vat_binding_v1() from public, anon, authenticated, service_role;
revoke all on function public.quotation_vat_context_sha256_v1(uuid) from public, anon, authenticated, service_role;
revoke all on function public.record_quotation_vat_transaction_classification_v1(uuid, text, text, text) from public, anon, authenticated, service_role;
revoke all on function public.record_quotation_vat_turnover_snapshot_v1(date, bigint, text, text, uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.resolve_quotation_vat_authority_v1(uuid, date) from public, anon, authenticated, service_role;
revoke all on function public.assert_quotation_business_draft_vat_binding_v1(uuid) from public, anon, authenticated, service_role;
revoke all on function public.assert_quotation_business_draft_vat_binding_v1(uuid, boolean) from public, anon, authenticated, service_role;
revoke all on function public.resolve_quotation_business_approval_promotion_context_raw_v1(uuid, uuid, bigint) from public, anon, authenticated, service_role;
revoke all on function public.resolve_quotation_business_approval_promotion_context_v1(uuid, uuid, bigint) from public, anon, authenticated, service_role;

grant execute on function public.is_valid_quotation_vat_authority_v1(jsonb) to service_role;
grant execute on function public.quotation_vat_context_sha256_v1(uuid) to service_role;
grant execute on function public.record_quotation_vat_transaction_classification_v1(uuid, text, text, text) to service_role;
grant execute on function public.record_quotation_vat_turnover_snapshot_v1(date, bigint, text, text, uuid, text) to service_role;
grant execute on function public.resolve_quotation_vat_authority_v1(uuid, date) to service_role;
grant execute on function public.resolve_quotation_business_approval_promotion_context_v1(uuid, uuid, bigint) to service_role;

comment on function public.resolve_quotation_vat_authority_v1(uuid, date) is
  'Resolves exactly one canonical Belgian small-enterprise exemption authority from server-owned transaction classification and current governed turnover state; all unknown states fail closed.';
comment on function public.upsert_quotation_business_draft_v2(uuid, uuid, bigint, uuid, jsonb) is
  'Resolves canonical terms and VAT authorities server-side, delegates unchanged pricing and payload construction to v1, and freezes the VAT authority binding separately.';