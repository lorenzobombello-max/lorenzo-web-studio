do $$
begin
  if exists (select 1 from public.sdf_m1_invoice_issuances) then
    raise exception using
      errcode = 'P0001',
      message = 'LEGACY_SDF_INVOICE_VAT_BINDING_REVIEW_REQUIRED';
  end if;
end;
$$;

alter table public.sdf_m1_invoice_issuances
  add column vat_decision_authority_id uuid not null
    references public.quotation_vat_decision_authorities(vat_decision_authority_id),
  add column vat_authority_sha256 char(64) not null
    check (vat_authority_sha256 ~ '^[0-9a-f]{64}$'),
  add column rate_semantics text not null,
  add column invoice_literal text not null;

alter table public.sdf_m1_invoice_issuances
  add constraint sdf_m1_invoice_exemption_authority_valid check (
    vat_treatment = 'EXEMPT'
    and rate_semantics = 'NOT_APPLICABLE'
    and vat_rate_basis_points = 0
    and invoice_literal = 'Bijzondere vrijstellingsregeling van belasting'
    and vat_amount_minor = 0
    and gross_amount_minor = net_amount_minor
  );

create table public.sdf_quotation_vat_authority_bindings (
  quotation_id uuid primary key references public.sdf_quotation_acceptances(quotation_id),
  quote_request_id uuid not null references public.quote_requests(id),
  vat_decision_authority_id uuid not null references public.quotation_vat_decision_authorities(vat_decision_authority_id),
  vat_authority_version text not null,
  vat_authority_sha256 char(64) not null check (vat_authority_sha256 ~ '^[0-9a-f]{64}$'),
  vat_treatment text not null check (vat_treatment = 'EXEMPT'),
  rate_semantics text not null check (rate_semantics = 'NOT_APPLICABLE'),
  invoice_literal text not null check (invoice_literal = 'Bijzondere vrijstellingsregeling van belasting'),
  context_sha256 char(64) not null check (context_sha256 ~ '^[0-9a-f]{64}$'),
  classification_id uuid not null references public.quotation_vat_transaction_classifications(classification_id),
  turnover_snapshot_id uuid not null references public.quotation_vat_turnover_snapshots(turnover_snapshot_id),
  bound_by_operator_id uuid not null references public.commercial_operators(operator_id),
  bound_at timestamptz not null default clock_timestamp()
);

create trigger trg_sdf_quotation_vat_authority_binding_immutable
before update or delete on public.sdf_quotation_vat_authority_bindings
for each row execute function public.prevent_sdf_invoice_foundation_mutation_v1();

create function public.bind_sdf_quotation_vat_authority_v1(
  p_quotation_id uuid,
  p_resolution_date date
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_quote_request_id uuid;
  v_vat jsonb;
  v_binding public.sdf_quotation_vat_authority_bindings%rowtype;
begin
  select * into v_operator from public.commercial_operators where auth_user_id = v_subject;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'SDF_INVOICE_AUTHORITY_DENIED';
  end if;
  select quotation.quote_request_id into v_quote_request_id
  from public.sdf_quotations as quotation
  join public.sdf_quotation_acceptances as acceptance
    on acceptance.quotation_id = quotation.quotation_id
  where quotation.quotation_id = p_quotation_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'SDF_ACCEPTED_QUOTATION_REQUIRED';
  end if;
  v_vat := public.resolve_quotation_vat_authority_v1(v_quote_request_id, p_resolution_date);
  insert into public.sdf_quotation_vat_authority_bindings (
    quotation_id, quote_request_id, vat_decision_authority_id,
    vat_authority_version, vat_authority_sha256, vat_treatment,
    rate_semantics, invoice_literal, context_sha256, classification_id,
    turnover_snapshot_id, bound_by_operator_id
  ) values (
    p_quotation_id, v_quote_request_id,
    (v_vat->>'vat_decision_authority_id')::uuid,
    v_vat->>'decision_version', v_vat->>'authority_sha256',
    v_vat->>'vat_treatment', v_vat->>'rate_semantics', v_vat->>'invoice_literal',
    v_vat->>'context_sha256', (v_vat->>'classification_id')::uuid,
    (v_vat->>'turnover_snapshot_id')::uuid, v_operator.operator_id
  ) returning * into v_binding;
  return to_jsonb(v_binding);
exception
  when unique_violation then
    raise exception using errcode = 'P0001', message = 'SDF_VAT_AUTHORITY_BINDING_CONFLICT';
end;
$$;

create function public.resolve_sdf_m1_invoice_vat_authority_v1(
  p_candidate_id uuid,
  p_resolution_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_candidate public.sdf_m1_invoice_candidates%rowtype;
  v_binding public.sdf_quotation_vat_authority_bindings%rowtype;
  v_vat jsonb;
begin
  select * into v_candidate from public.sdf_m1_invoice_candidates
  where candidate_id = p_candidate_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'SDF_M1_INVOICE_CANDIDATE_REQUIRED';
  end if;
  v_vat := public.resolve_quotation_vat_authority_v1(
    v_candidate.quote_request_id, p_resolution_date
  );
  select * into v_binding from public.sdf_quotation_vat_authority_bindings
  where quotation_id = v_candidate.quotation_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'QUOTATION_VAT_CONTEXT_REQUIRED';
  end if;
  if v_binding.quote_request_id is distinct from v_candidate.quote_request_id
     or v_binding.vat_decision_authority_id is distinct from (v_vat->>'vat_decision_authority_id')::uuid
     or v_binding.vat_authority_version is distinct from v_vat->>'decision_version'
     or rtrim(v_binding.vat_authority_sha256) is distinct from v_vat->>'authority_sha256'
     or v_binding.vat_treatment is distinct from v_vat->>'vat_treatment'
     or v_binding.rate_semantics is distinct from v_vat->>'rate_semantics'
     or v_binding.invoice_literal is distinct from v_vat->>'invoice_literal'
     or rtrim(v_binding.context_sha256) is distinct from v_vat->>'context_sha256'
     or v_binding.classification_id is distinct from (v_vat->>'classification_id')::uuid
     or v_binding.turnover_snapshot_id is distinct from (v_vat->>'turnover_snapshot_id')::uuid then
    raise exception using errcode = 'P0001', message = 'SDF_VAT_AUTHORITY_MISMATCH';
  end if;
  return v_vat || jsonb_build_object(
    'quotation_id', v_candidate.quotation_id,
    'quote_request_id', v_candidate.quote_request_id
  );
end;
$$;

create or replace function public.issue_sdf_m1_invoice_v1(
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
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_resolution_date date := (clock_timestamp() at time zone 'Europe/Brussels')::date;
begin
  select * into v_operator from public.commercial_operators where auth_user_id = v_subject;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'SDF_INVOICE_AUTHORITY_DENIED';
  end if;
  perform public.resolve_sdf_m1_invoice_vat_authority_v1(p_candidate_id, v_resolution_date);
  raise exception using errcode = 'P0001', message = 'SDF_INVOICE_ARTIFACT_EVIDENCE_REQUIRED';
end;
$$;

create function public.issue_sdf_m1_invoice_v2(
  p_candidate_id uuid,
  p_issue_year smallint,
  p_idempotency_key uuid,
  p_docx_sha256 text,
  p_docx_bytes bigint,
  p_pdf_sha256 text,
  p_pdf_bytes bigint
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
  v_candidate public.sdf_m1_invoice_candidates%rowtype;
  v_existing public.sdf_m1_invoice_issuances%rowtype;
  v_issuance public.sdf_m1_invoice_issuances%rowtype;
  v_vat jsonb;
  v_resolution_date date := (clock_timestamp() at time zone 'Europe/Brussels')::date;
  v_number record;
  v_fingerprint text;
  v_payload_sha256 text;
begin
  select * into v_operator from public.commercial_operators where auth_user_id = v_subject;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'SDF_INVOICE_AUTHORITY_DENIED';
  end if;
  if p_candidate_id is null or p_idempotency_key is null
     or p_issue_year <> extract(year from v_resolution_date)::smallint
     or p_docx_sha256 !~ '^[0-9a-f]{64}$' or p_docx_bytes <= 0
     or (p_pdf_sha256 is null) <> (p_pdf_bytes is null)
     or (p_pdf_sha256 is not null and (p_pdf_sha256 !~ '^[0-9a-f]{64}$' or p_pdf_bytes <= 0)) then
    raise exception using errcode = '22023', message = 'SDF_INVOICE_ISSUANCE_INPUT_INVALID';
  end if;

  v_vat := public.resolve_sdf_m1_invoice_vat_authority_v1(p_candidate_id, v_resolution_date);
  select * into strict v_candidate from public.sdf_m1_invoice_candidates
  where candidate_id = p_candidate_id;
  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'authoritySha256', v_vat->>'authority_sha256',
    'candidateId', p_candidate_id,
    'candidatePayloadSha256', rtrim(v_candidate.candidate_payload_sha256),
    'docxBytes', p_docx_bytes,
    'docxSha256', p_docx_sha256,
    'issueYear', p_issue_year,
    'pdfBytes', p_pdf_bytes,
    'pdfSha256', p_pdf_sha256
  )::text, 'UTF8'), 'sha256'), 'hex');

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text, 0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_candidate_id::text, 0));
  v_vat := public.resolve_sdf_m1_invoice_vat_authority_v1(p_candidate_id, v_resolution_date);

  select * into v_existing from public.sdf_m1_invoice_issuances
  where issuance_idempotency_key = p_idempotency_key;
  if found then
    if rtrim(v_existing.issuance_fingerprint) <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'issuance_id', v_existing.issuance_id,
      'invoice_number', v_existing.invoice_number,
      'was_created', false
    );
  end if;
  select * into v_existing from public.sdf_m1_invoice_issuances
  where candidate_id = p_candidate_id;
  if found then
    if rtrim(v_existing.issuance_fingerprint) <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'SDF_M1_INVOICE_ISSUANCE_CONFLICT';
    end if;
    return jsonb_build_object(
      'issuance_id', v_existing.issuance_id,
      'invoice_number', v_existing.invoice_number,
      'was_created', false
    );
  end if;

  select * into strict v_number from public.allocate_sdf_invoice_number_v1(p_issue_year);
  v_payload_sha256 := encode(extensions.digest(convert_to(jsonb_build_object(
    'authoritySha256', v_vat->>'authority_sha256',
    'candidatePayloadSha256', rtrim(v_candidate.candidate_payload_sha256),
    'grossAmountMinor', v_candidate.net_amount_minor,
    'invoiceLiteral', v_vat->>'invoice_literal',
    'invoiceNumber', v_number.invoice_number,
    'netAmountMinor', v_candidate.net_amount_minor,
    'rateSemantics', v_vat->>'rate_semantics',
    'vatAmountMinor', 0,
    'vatTreatment', v_vat->>'vat_treatment'
  )::text, 'UTF8'), 'sha256'), 'hex');
  insert into public.sdf_m1_invoice_issuances (
    candidate_id, invoice_number, issue_year, sequence, issuance_state,
    vat_decision_authority_id, vat_authority_version, vat_authority_sha256,
    vat_treatment, rate_semantics, vat_rate_basis_points, invoice_literal,
    net_amount_minor, vat_amount_minor, gross_amount_minor,
    issuance_payload_sha256, docx_sha256, docx_bytes, pdf_sha256, pdf_bytes,
    issuance_idempotency_key, issuance_fingerprint, issued_by_operator_id
  ) values (
    p_candidate_id, v_number.invoice_number, p_issue_year, v_number.sequence, 'ISSUED',
    (v_vat->>'vat_decision_authority_id')::uuid,
    v_vat->>'decision_version', v_vat->>'authority_sha256',
    v_vat->>'vat_treatment', v_vat->>'rate_semantics', 0, v_vat->>'invoice_literal',
    v_candidate.net_amount_minor, 0, v_candidate.net_amount_minor,
    v_payload_sha256, p_docx_sha256, p_docx_bytes, p_pdf_sha256, p_pdf_bytes,
    p_idempotency_key, v_fingerprint, v_operator.operator_id
  ) returning * into v_issuance;
  return jsonb_build_object(
    'issuance_id', v_issuance.issuance_id,
    'invoice_number', v_issuance.invoice_number,
    'was_created', true
  );
end;
$$;

alter table public.sdf_quotation_vat_authority_bindings enable row level security;
alter table public.sdf_quotation_vat_authority_bindings force row level security;
revoke all privileges on table public.sdf_quotation_vat_authority_bindings from public, anon, authenticated, service_role;
revoke all on function public.bind_sdf_quotation_vat_authority_v1(uuid, date) from public, anon, authenticated, service_role;
revoke all on function public.resolve_sdf_m1_invoice_vat_authority_v1(uuid, date) from public, anon, authenticated, service_role;
revoke all on function public.issue_sdf_m1_invoice_v2(uuid, smallint, uuid, text, bigint, text, bigint) from public, anon, authenticated, service_role;
grant execute on function public.bind_sdf_quotation_vat_authority_v1(uuid, date) to authenticated;
grant execute on function public.issue_sdf_m1_invoice_v2(uuid, smallint, uuid, text, bigint, text, bigint) to authenticated;

comment on function public.resolve_sdf_m1_invoice_vat_authority_v1(uuid, date) is
  'Preflight requiring exact active canonical authority, current classification and turnover, and immutable accepted-quotation authority equality before invoice number allocation.';
comment on function public.issue_sdf_m1_invoice_v2(uuid, smallint, uuid, text, bigint, text, bigint) is
  'Artifact-aware M1 invoice issuance. Revalidates all VAT gates after locks and only then allocates a number and freezes strict exemption evidence.';