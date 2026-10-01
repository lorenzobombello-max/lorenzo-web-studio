create table public.website_commercial_document_templates (
  document_kind text primary key check (document_kind in (
    'AGREEMENT', 'INVOICE_M1', 'INVOICE_M2', 'INVOICE_FINAL',
    'INVOICE_FINAL_CENT_REMAINDER_TEST'
  )),
  milestone smallint,
  source_drive_file_id text not null check (nullif(btrim(source_drive_file_id), '') is not null),
  source_sha256 char(64) not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  derivative_reference text,
  derivative_sha256 char(64),
  template_status text not null check (template_status = 'LOCAL_CONCEPT_ONLY'),
  test_only boolean not null,
  fiscal_fields_resolved boolean not null check (not fiscal_fields_resolved),
  issuance_status text not null check (
    issuance_status = 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
  ),
  created_at timestamptz not null default clock_timestamp(),
  constraint website_commercial_template_shape check (
    (document_kind = 'AGREEMENT' and milestone is null and not test_only
      and derivative_reference is not null and derivative_sha256 is not null)
    or (document_kind = 'INVOICE_M1' and milestone = 1 and not test_only
      and derivative_reference is not null and derivative_sha256 is not null)
    or (document_kind = 'INVOICE_M2' and milestone = 2 and not test_only
      and derivative_reference is not null and derivative_sha256 is not null)
    or (document_kind = 'INVOICE_FINAL' and milestone = 3 and not test_only
      and derivative_reference is not null and derivative_sha256 is not null)
    or (document_kind = 'INVOICE_FINAL_CENT_REMAINDER_TEST' and milestone = 3 and test_only
      and derivative_reference is null and derivative_sha256 is null)
  )
);

insert into public.website_commercial_document_templates (
  document_kind, milestone, source_drive_file_id, source_sha256,
  derivative_reference, derivative_sha256, template_status, test_only,
  fiscal_fields_resolved, issuance_status
) values
  (
    'AGREEMENT', null, '1Mc2AabV-J9cuDbnlFSS2_1XXSlsGJb_K',
    '548bf88021e9a6ae54e3cda97fb864f85574dc9abbbe47f777dc0a35b6e2fa89',
    'assets/docs/website-commercial/LWS_WEBSITE_AGREEMENT_NL_BE_CONCEPT_v1.docx',
    '10804398000fc16c1cedd95fa4391971a9c9133ba530c4eea07088c6bddd6ccd',
    'LOCAL_CONCEPT_ONLY', false, false, 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
  ),
  (
    'INVOICE_M1', 1, '1AXcub1kC6L6rLnqKlvY58GBK47to8Mtk',
    'ac61007478c15ff69bbe1033c05d1a0e8f07bad86cbdefbde1824c36850b4a41',
    'assets/docs/website-commercial/LWS_WEBSITE_INVOICE_M1_40_NONPRODUCTION_v1.docx',
    '53c8e7b8223a6c2d62b471ecabc8982663b7ce5a98a73b15b45b66b59ac12e9a',
    'LOCAL_CONCEPT_ONLY', false, false, 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
  ),
  (
    'INVOICE_M2', 2, '18tqoTLT0MB4c0rpf9uJJ3wTcwzVjxIOK',
    '929b6c5be4a340824b29bcb67dc793d575f69f7909dd3004b3cff874f5d135b6',
    'assets/docs/website-commercial/LWS_WEBSITE_INVOICE_M2_40_NONPRODUCTION_v1.docx',
    'b25615b7890789d08df0a4017ae149a47a2e655169a2497848c0817e8fffdf82',
    'LOCAL_CONCEPT_ONLY', false, false, 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
  ),
  (
    'INVOICE_FINAL', 3, '1-rQm3PXaGfbXejQroz2-rwRJJfutEDmT',
    '4321d43bdbb053169ee2a0b021ba0807740e3f6b229b3e76ee84615ef944ed9a',
    'assets/docs/website-commercial/LWS_WEBSITE_INVOICE_FINAL_REMAINDER_NONPRODUCTION_v1.docx',
    'fe567d0f02a998f59ca73189287d565d669ff2d4adb9a5d4167f548081ca0d94',
    'LOCAL_CONCEPT_ONLY', false, false, 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
  ),
  (
    'INVOICE_FINAL_CENT_REMAINDER_TEST', 3, '1gAntldNK5862IuYWtyYEljVsA26s21hK',
    '1207adbbe06f62cc9db7feaf40d2a69d3a07a21a7759684e4adef71aaa7fe093',
    null, null, 'LOCAL_CONCEPT_ONLY', true, false,
    'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
  );

create table public.website_commercial_document_candidates (
  candidate_id uuid primary key default gen_random_uuid(),
  document_kind text not null references public.website_commercial_document_templates(document_kind),
  quote_request_id uuid not null references public.quote_requests(id),
  quotation_issuance_id uuid not null references public.quote_request_quotation_issuances(id),
  acceptance_id uuid not null references public.quote_request_quotation_acceptances(id),
  customer_id uuid not null references public.commercial_customers(customer_id),
  project_id uuid not null references public.commercial_projects(project_id),
  obligation_id uuid references public.commercial_obligations(obligation_id),
  milestone smallint,
  agreement_status text,
  candidate_status text not null check (candidate_status = 'PREPARED_LOCAL_CONCEPT'),
  issuance_status text not null check (
    issuance_status = 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
  ),
  generation_payload jsonb not null,
  generation_payload_sha256 char(64) not null check (generation_payload_sha256 ~ '^[0-9a-f]{64}$'),
  creation_idempotency_key uuid not null unique,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  unique (project_id, document_kind),
  constraint website_commercial_candidate_shape check (
    (document_kind = 'AGREEMENT' and milestone is null and obligation_id is null
      and agreement_status = 'UNSIGNED_CONCEPT')
    or (document_kind = 'INVOICE_M1' and milestone = 1 and obligation_id is not null
      and agreement_status is null)
    or (document_kind = 'INVOICE_M2' and milestone = 2 and obligation_id is not null
      and agreement_status is null)
    or (document_kind = 'INVOICE_FINAL' and milestone = 3 and obligation_id is not null
      and agreement_status is null)
  ),
  constraint website_commercial_candidate_payload_hash_matches check (
    generation_payload_sha256 = encode(extensions.digest(
      convert_to(generation_payload::text, 'UTF8'), 'sha256'
    ), 'hex')
  )
);

create table public.website_commercial_document_render_artifacts (
  artifact_id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null unique references public.website_commercial_document_candidates(candidate_id),
  document_kind text not null references public.website_commercial_document_templates(document_kind),
  template_sha256 char(64) not null check (template_sha256 ~ '^[0-9a-f]{64}$'),
  generation_payload_sha256 char(64) not null check (generation_payload_sha256 ~ '^[0-9a-f]{64}$'),
  docx_sha256 char(64) not null check (docx_sha256 ~ '^[0-9a-f]{64}$'),
  docx_bytes bigint not null check (docx_bytes > 0),
  render_status text not null check (render_status = 'LOCAL_RENDER_ONLY'),
  issuance_status text not null check (
    issuance_status = 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED'
  ),
  registration_idempotency_key uuid not null unique,
  created_at timestamptz not null default clock_timestamp()
);

create function public.prevent_website_commercial_document_mutation_v1()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception using errcode = '55000', message = 'WEBSITE_COMMERCIAL_DOCUMENT_IMMUTABLE';
end;
$$;

create trigger trg_website_commercial_templates_immutable
before update or delete on public.website_commercial_document_templates
for each row execute function public.prevent_website_commercial_document_mutation_v1();
create trigger trg_website_commercial_candidates_immutable
before update or delete on public.website_commercial_document_candidates
for each row execute function public.prevent_website_commercial_document_mutation_v1();
create trigger trg_website_commercial_render_artifacts_immutable
before update or delete on public.website_commercial_document_render_artifacts
for each row execute function public.prevent_website_commercial_document_mutation_v1();

create function public.website_commercial_payment_term_days_v1(p_milestones jsonb)
returns integer
language plpgsql
immutable
set search_path = public, pg_catalog
as $$
declare
  v_milestone_count integer;
  v_value_count integer;
  v_distinct_count integer;
  v_days integer;
begin
  if jsonb_typeof(p_milestones) <> 'array' then
    raise exception using errcode = '22023', message = 'WEBSITE_COMMERCIAL_PAYMENT_TERM_AMBIGUOUS';
  end if;
  select count(*)::integer,
    count(milestone->>'due_terms_days')::integer,
    count(distinct (milestone->>'due_terms_days')::integer)::integer,
    min((milestone->>'due_terms_days')::integer)
  into v_milestone_count, v_value_count, v_distinct_count, v_days
  from jsonb_array_elements(p_milestones) milestone;
  if v_milestone_count < 1 or v_value_count <> v_milestone_count
     or v_distinct_count <> 1 or v_days < 1 then
    raise exception using errcode = '22023', message = 'WEBSITE_COMMERCIAL_PAYMENT_TERM_AMBIGUOUS';
  end if;
  return v_days;
exception
  when sqlstate '22023' then raise;
  when others then
    raise exception using errcode = '22023', message = 'WEBSITE_COMMERCIAL_PAYMENT_TERM_AMBIGUOUS';
end;
$$;

create function public.prepare_website_commercial_document_concept_v1(
  p_project_id uuid,
  p_document_kind text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_project public.commercial_projects%rowtype;
  v_customer public.commercial_customers%rowtype;
  v_acceptance public.quote_request_quotation_acceptances%rowtype;
  v_issuance public.quote_request_quotation_issuances%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_request public.quote_requests%rowtype;
  v_vat_authority public.quotation_vat_decision_authorities%rowtype;
  v_template public.website_commercial_document_templates%rowtype;
  v_obligation public.commercial_obligations%rowtype;
  v_existing public.website_commercial_document_candidates%rowtype;
  v_candidate public.website_commercial_document_candidates%rowtype;
  v_customer_payload jsonb;
  v_project_payload jsonb;
  v_payload jsonb;
  v_payload_sha256 text;
  v_fingerprint text;
  v_milestone smallint;
  v_payment_term_days integer;
  v_vat_authority_count integer;
begin
  if p_project_id is null or p_idempotency_key is null
     or p_document_kind not in ('AGREEMENT', 'INVOICE_M1', 'INVOICE_M2', 'INVOICE_FINAL') then
    raise exception using errcode = '22023', message = 'WEBSITE_COMMERCIAL_CONCEPT_INPUT_INVALID';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'project_id', p_project_id,
    'document_kind', p_document_kind
  )::text, 'UTF8'), 'sha256'), 'hex');
  select * into v_existing
  from public.website_commercial_document_candidates
  where creation_idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'WEBSITE_COMMERCIAL_CONCEPT_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'candidate_id', v_existing.candidate_id,
      'generation_payload', v_existing.generation_payload,
      'generation_payload_sha256', rtrim(v_existing.generation_payload_sha256),
      'issuance_status', v_existing.issuance_status,
      'was_created', false
    );
  end if;

  select * into v_project from public.commercial_projects where project_id = p_project_id;
  if not found then raise exception using errcode = 'P0001', message = 'WEBSITE_COMMERCIAL_PROJECT_NOT_FOUND'; end if;
  if v_project.m3_minor <> v_project.accepted_total_minor - v_project.m1_minor - v_project.m2_minor then
    raise exception using errcode = '23514', message = 'WEBSITE_COMMERCIAL_M3_MISMATCH';
  end if;
  select * into strict v_customer from public.commercial_customers
  where customer_id = v_project.customer_id and acceptance_id = v_project.acceptance_id;
  select * into strict v_acceptance from public.quote_request_quotation_acceptances
  where id = v_project.acceptance_id and issuance_id = v_project.quotation_issuance_id;
  select * into strict v_issuance from public.quote_request_quotation_issuances
  where id = v_project.quotation_issuance_id;
  select * into strict v_approval from public.quote_request_quotation_approvals
  where id = v_issuance.approval_id;
  select * into strict v_request from public.quote_requests
  where id = v_approval.quote_request_id;
  if v_request.request_kind <> 'website' then
    raise exception using errcode = '23514', message = 'WEBSITE_COMMERCIAL_PRODUCT_FAMILY_INVALID';
  end if;
  if v_acceptance.customer_identity_sha256 <> v_customer.identity_sha256 then
    raise exception using errcode = '23514', message = 'WEBSITE_COMMERCIAL_CUSTOMER_LINKAGE_MISMATCH';
  end if;
  select * into strict v_template from public.website_commercial_document_templates
  where document_kind = p_document_kind and not test_only
    and template_status = 'LOCAL_CONCEPT_ONLY'
    and not fiscal_fields_resolved
    and issuance_status = 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED';

  if p_document_kind = 'AGREEMENT' then
    v_milestone := null;
  else
    v_milestone := case p_document_kind
      when 'INVOICE_M1' then 1 when 'INVOICE_M2' then 2 when 'INVOICE_FINAL' then 3
    end;
    select * into v_obligation from public.commercial_obligations
    where project_id = p_project_id and obligation_type = 'PROJECT_MILESTONE'
      and milestone = v_milestone;
    if not found then
      raise exception using errcode = 'P0001', message = 'WEBSITE_COMMERCIAL_OBLIGATION_NOT_FOUND';
    end if;
    if v_obligation.amount_minor <> (case v_milestone
      when 1 then v_project.m1_minor when 2 then v_project.m2_minor else v_project.m3_minor end) then
      raise exception using errcode = '23514', message = 'WEBSITE_COMMERCIAL_OBLIGATION_AMOUNT_MISMATCH';
    end if;
    if v_milestone >= 1 and not exists (
      select 1 from public.website_commercial_document_candidates
      where project_id = p_project_id and document_kind = 'AGREEMENT'
    ) then raise exception using errcode = 'P0001', message = 'WEBSITE_COMMERCIAL_AGREEMENT_CONCEPT_REQUIRED'; end if;
    if v_milestone >= 2 and not exists (
      select 1 from public.website_commercial_document_candidates
      where project_id = p_project_id and document_kind = 'INVOICE_M1'
    ) then raise exception using errcode = 'P0001', message = 'WEBSITE_COMMERCIAL_M1_CONCEPT_REQUIRED'; end if;
    if v_milestone >= 3 and not exists (
      select 1 from public.website_commercial_document_candidates
      where project_id = p_project_id and document_kind = 'INVOICE_M2'
    ) then raise exception using errcode = 'P0001', message = 'WEBSITE_COMMERCIAL_M2_CONCEPT_REQUIRED'; end if;
  end if;

  v_customer_payload := v_approval.approved_payload->'customer_identity';
  v_project_payload := v_approval.approved_payload->'project_scope';
  v_payment_term_days := public.website_commercial_payment_term_days_v1(
    v_approval.approved_payload->'payment_schedule'->'milestones'
  );
  select count(*)::integer into v_vat_authority_count
  from public.quotation_vat_decision_authorities authority
  where authority.authority_family = 'LWS_OUTGOING_VAT'
    and authority.decision_code = 'BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION'
    and authority.vat_treatment = 'EXEMPT'
    and authority.rate_semantics = 'NOT_APPLICABLE'
    and authority.vat_rate = 0
    and authority.invoice_literal = 'Bijzondere vrijstellingsregeling van belasting'
    and authority.vat_treatment = v_approval.approved_payload->'vat_approval'->>'vat_treatment'
    and authority.vat_rate = (v_approval.approved_payload->'vat_approval'->>'vat_rate')::numeric
    and authority.authority_source_identifier =
      v_approval.approved_payload->'vat_approval'->>'vat_decision_source'
    and authority.effective_from <= (v_acceptance.accepted_at at time zone 'Europe/Brussels')::date
    and (authority.effective_until is null
      or authority.effective_until >= (v_acceptance.accepted_at at time zone 'Europe/Brussels')::date);
  if v_vat_authority_count <> 1 then
    raise exception using errcode = 'P0001', message = 'WEBSITE_COMMERCIAL_VAT_AUTHORITY_REQUIRED';
  end if;
  select * into strict v_vat_authority
  from public.quotation_vat_decision_authorities authority
  where authority.authority_family = 'LWS_OUTGOING_VAT'
    and authority.decision_code = 'BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION'
    and authority.vat_treatment = v_approval.approved_payload->'vat_approval'->>'vat_treatment'
    and authority.vat_rate = (v_approval.approved_payload->'vat_approval'->>'vat_rate')::numeric
    and authority.authority_source_identifier =
      v_approval.approved_payload->'vat_approval'->>'vat_decision_source'
    and authority.effective_from <= (v_acceptance.accepted_at at time zone 'Europe/Brussels')::date
    and (authority.effective_until is null
      or authority.effective_until >= (v_acceptance.accepted_at at time zone 'Europe/Brussels')::date);
  if (v_approval.approved_payload->'totals'->>'one_time_subtotal_minor')::bigint
        <> v_project.accepted_total_minor
     or (v_approval.approved_payload->'totals'->>'vat_base_minor')::bigint
        <> v_project.accepted_total_minor
     or (v_approval.approved_payload->'totals'->>'vat_amount_minor')::bigint <> 0
     or (v_approval.approved_payload->'totals'->>'total_gross_minor')::bigint
        <> v_project.accepted_total_minor
     or exists (
       select 1
       from jsonb_array_elements(v_approval.approved_payload->'line_items') line(value)
       where line.value->>'vat_treatment' <> v_vat_authority.vat_treatment
          or (line.value->>'vat_rate')::numeric <> v_vat_authority.vat_rate
     ) then
    raise exception using errcode = '23514', message = 'WEBSITE_COMMERCIAL_VAT_AMOUNT_MISMATCH';
  end if;

  v_payload := jsonb_build_object(
    'test_only', true,
    'product_family', 'WEBSITE',
    'document_kind', p_document_kind,
    'lineage', jsonb_build_object(
      'quote_request_id', v_request.id,
      'quotation_issuance_id', v_issuance.id,
      'acceptance_id', v_acceptance.id,
      'customer_id', v_customer.customer_id,
      'project_id', v_project.project_id,
      'obligation_id', v_obligation.obligation_id,
      'quotation_number', v_acceptance.quotation_number
    ),
    'agreement', jsonb_build_object('status', 'UNSIGNED_CONCEPT'),
    'customer', jsonb_build_object(
      'legal_name', v_customer_payload->>'legal_name',
      'legal_form', coalesce(v_customer_payload->>'legal_form', ''),
      'enterprise_number', v_customer_payload->>'enterprise_number',
      'vat_number', v_customer_payload->>'vat_number',
      'address_line_1', v_customer_payload->>'address_line_1',
      'address_line_2', v_customer_payload->>'address_line_2',
      'postal_code', v_customer_payload->>'postal_code',
      'city', v_customer_payload->>'city',
      'country_code', v_customer_payload->>'country_code',
      'representative_name', v_acceptance.accepting_name,
      'representative_role', v_acceptance.accepting_role,
      'email', v_customer_payload->>'email'
    ),
    'project', jsonb_build_object(
      'title', v_project_payload->>'project_title',
      'timing_weeks', v_project_payload->'indicative_timing',
      'project_price_excl_vat_minor', v_project.accepted_total_minor,
      'accepted_total_minor', v_project.accepted_total_minor,
      'm1_minor', v_project.m1_minor,
      'm2_minor', v_project.m2_minor,
      'm3_minor', v_project.m3_minor,
      'currency', rtrim(v_project.currency),
      'payment_term_days', v_payment_term_days
    ),
    'vat', jsonb_build_object(
      'vat_decision_authority_id', v_vat_authority.vat_decision_authority_id,
      'authority_family', v_vat_authority.authority_family,
      'decision_code', v_vat_authority.decision_code,
      'decision_version', v_vat_authority.decision_version,
      'authority_sha256', rtrim(v_vat_authority.authority_sha256),
      'vat_treatment', v_vat_authority.vat_treatment,
      'rate_semantics', v_vat_authority.rate_semantics,
      'vat_rate', v_vat_authority.vat_rate,
      'invoice_literal', v_vat_authority.invoice_literal,
      'vat_base_minor', v_project.accepted_total_minor,
      'vat_amount_minor', 0,
      'customer_total_minor', v_project.accepted_total_minor
    ),
    'invoice_fiscal', case when v_milestone is null then null else jsonb_build_object(
      'obligation_id', v_obligation.obligation_id,
      'milestone', v_obligation.milestone,
      'vat_base_minor', v_obligation.amount_minor,
      'vat_amount_minor', 0,
      'customer_total_minor', v_obligation.amount_minor
    ) end,
    'template', jsonb_build_object(
      'document_kind', v_template.document_kind,
      'derivative_reference', v_template.derivative_reference,
      'derivative_sha256', rtrim(v_template.derivative_sha256)
    )
  );
  v_payload_sha256 := encode(extensions.digest(convert_to(v_payload::text, 'UTF8'), 'sha256'), 'hex');

  begin
    insert into public.website_commercial_document_candidates (
      document_kind, quote_request_id, quotation_issuance_id, acceptance_id,
      customer_id, project_id, obligation_id, milestone, agreement_status,
      candidate_status, issuance_status, generation_payload,
      generation_payload_sha256, creation_idempotency_key, request_fingerprint
    ) values (
      p_document_kind, v_request.id, v_issuance.id, v_acceptance.id,
      v_customer.customer_id, v_project.project_id,
      case when p_document_kind = 'AGREEMENT' then null else v_obligation.obligation_id end,
      v_milestone, case when p_document_kind = 'AGREEMENT' then 'UNSIGNED_CONCEPT' end,
      'PREPARED_LOCAL_CONCEPT', 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED',
      v_payload, v_payload_sha256, p_idempotency_key, v_fingerprint
    ) returning * into v_candidate;
  exception when unique_violation then
    raise exception using errcode = 'P0001', message = 'WEBSITE_COMMERCIAL_CONCEPT_ALREADY_EXISTS';
  end;

  return jsonb_build_object(
    'candidate_id', v_candidate.candidate_id,
    'generation_payload', v_candidate.generation_payload,
    'generation_payload_sha256', rtrim(v_candidate.generation_payload_sha256),
    'issuance_status', v_candidate.issuance_status,
    'was_created', true
  );
end;
$$;

create function public.register_website_commercial_document_render_v1(
  p_candidate_id uuid,
  p_expected_generation_payload_sha256 text,
  p_template_sha256 text,
  p_docx_sha256 text,
  p_docx_bytes bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_candidate public.website_commercial_document_candidates%rowtype;
  v_template public.website_commercial_document_templates%rowtype;
  v_existing public.website_commercial_document_render_artifacts%rowtype;
  v_artifact public.website_commercial_document_render_artifacts%rowtype;
begin
  if p_candidate_id is null or p_idempotency_key is null
     or p_expected_generation_payload_sha256 !~ '^[0-9a-f]{64}$'
     or p_template_sha256 !~ '^[0-9a-f]{64}$'
     or p_docx_sha256 !~ '^[0-9a-f]{64}$'
     or p_docx_bytes <= 0 then
    raise exception using errcode = '22023', message = 'WEBSITE_COMMERCIAL_RENDER_INPUT_INVALID';
  end if;
  select * into v_existing from public.website_commercial_document_render_artifacts
  where registration_idempotency_key = p_idempotency_key;
  if found then
    if v_existing.candidate_id <> p_candidate_id
       or v_existing.generation_payload_sha256 <> p_expected_generation_payload_sha256
       or v_existing.template_sha256 <> p_template_sha256
       or v_existing.docx_sha256 <> p_docx_sha256
       or v_existing.docx_bytes <> p_docx_bytes then
      raise exception using errcode = 'P0001', message = 'WEBSITE_COMMERCIAL_RENDER_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('artifact_id', v_existing.artifact_id, 'was_created', false,
      'issuance_status', v_existing.issuance_status);
  end if;
  select * into v_candidate from public.website_commercial_document_candidates
  where candidate_id = p_candidate_id;
  if not found then raise exception using errcode = 'P0001', message = 'WEBSITE_COMMERCIAL_CANDIDATE_NOT_FOUND'; end if;
  select * into strict v_template from public.website_commercial_document_templates
  where document_kind = v_candidate.document_kind;
  if v_candidate.generation_payload_sha256 <> p_expected_generation_payload_sha256
     or v_template.derivative_sha256 <> p_template_sha256
     or v_template.test_only
     or v_template.fiscal_fields_resolved
     or v_template.issuance_status <> 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED' then
    raise exception using errcode = '23514', message = 'WEBSITE_COMMERCIAL_RENDER_AUTHORITY_MISMATCH';
  end if;
  insert into public.website_commercial_document_render_artifacts (
    candidate_id, document_kind, template_sha256, generation_payload_sha256,
    docx_sha256, docx_bytes, render_status, issuance_status,
    registration_idempotency_key
  ) values (
    v_candidate.candidate_id, v_candidate.document_kind, p_template_sha256,
    p_expected_generation_payload_sha256, p_docx_sha256, p_docx_bytes,
    'LOCAL_RENDER_ONLY', 'BLOCKED_NONPRODUCTION_FISCAL_UNRESOLVED', p_idempotency_key
  ) returning * into v_artifact;
  return jsonb_build_object('artifact_id', v_artifact.artifact_id, 'was_created', true,
    'issuance_status', v_artifact.issuance_status);
end;
$$;

alter table public.website_commercial_document_templates enable row level security;
alter table public.website_commercial_document_templates force row level security;
alter table public.website_commercial_document_candidates enable row level security;
alter table public.website_commercial_document_candidates force row level security;
alter table public.website_commercial_document_render_artifacts enable row level security;
alter table public.website_commercial_document_render_artifacts force row level security;

revoke all on table public.website_commercial_document_templates from public, anon, authenticated, service_role;
revoke all on table public.website_commercial_document_candidates from public, anon, authenticated, service_role;
revoke all on table public.website_commercial_document_render_artifacts from public, anon, authenticated, service_role;
revoke all on function public.prevent_website_commercial_document_mutation_v1() from public, anon, authenticated, service_role;
revoke all on function public.website_commercial_payment_term_days_v1(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.prepare_website_commercial_document_concept_v1(uuid, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.register_website_commercial_document_render_v1(uuid, text, text, text, bigint, uuid) from public, anon, authenticated, service_role;
grant execute on function public.prepare_website_commercial_document_concept_v1(uuid, text, uuid) to service_role;
grant execute on function public.register_website_commercial_document_render_v1(uuid, text, text, text, bigint, uuid) to service_role;

comment on table public.website_commercial_document_candidates is
  'Website-only local concept authority. A quotation acceptance does not sign an agreement and no row authorizes document issuance.';
comment on table public.website_commercial_document_render_artifacts is
  'Hash evidence for a local concept render only; this is neither archive evidence nor issuance evidence.';