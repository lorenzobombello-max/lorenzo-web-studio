create table public.sdf_quotation_business_draft_adapters (
  adapter_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null unique references public.quote_requests(id) on delete restrict,
  preparation_authority_id uuid not null unique references public.sdf_quotation_preparation_authorities(authority_id) on delete restrict,
  commercial_decision_id uuid not null unique references public.sdf_quotation_commercial_decisions(decision_id) on delete restrict,
  generic_intake_id uuid not null unique references public.quote_request_intakes(id) on delete restrict,
  pricing_snapshot_id uuid not null unique references public.quote_request_pricing_snapshots(id) on delete restrict,
  approval_draft_id uuid not null unique references public.quote_request_quotation_approval_drafts(id) on delete restrict,
  business_draft_id uuid not null unique references public.quote_request_quotation_business_drafts(business_draft_id) on delete restrict,
  submission_sha256 char(64) not null check (submission_sha256 ~ '^[0-9a-f]{64}$'),
  pricing_authority_sha256 char(64) not null check (pricing_authority_sha256 ~ '^[0-9a-f]{64}$'),
  document_evidence_sha256 char(64) not null check (document_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  decision_sha256 char(64) not null check (decision_sha256 ~ '^[0-9a-f]{64}$'),
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  idempotency_key uuid not null unique,
  result_payload jsonb not null,
  created_by_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

create function public.guard_sdf_quotation_business_draft_adapter_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'SDF_BUSINESS_DRAFT_ADAPTER_IMMUTABLE';
end;
$$;

create trigger trg_sdf_quotation_business_draft_adapters_immutable
before update or delete on public.sdf_quotation_business_draft_adapters
for each row execute function public.guard_sdf_quotation_business_draft_adapter_v1();

create or replace function public.guard_website_intake_kind_v1()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_request_kind text;
begin
  select request_kind into v_request_kind
  from public.quote_requests
  where id = new.quote_request_id;

  if v_request_kind = 'slimme_documentenflow'
     and current_setting('lws.sdf_generic_intake_adapter', true) <> 'CREATE' then
    raise exception using errcode = '42501', message = 'REQUEST_KIND_INTAKE_NOT_ALLOWED';
  end if;
  return new;
end;
$$;

create function public.create_sdf_quotation_business_draft_v1(
  p_preparation_authority_id uuid,
  p_commercial_decision_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_preparation public.sdf_quotation_preparation_authorities%rowtype;
  v_decision public.sdf_quotation_commercial_decisions%rowtype;
  v_submission public.sdf_qualification_intake_submissions%rowtype;
  v_request public.quote_requests%rowtype;
  v_terms public.quotation_terms_authorities%rowtype;
  v_vat public.quotation_vat_decision_authorities%rowtype;
  v_seller public.quotation_seller_authorities%rowtype;
  v_template public.quotation_template_authorities%rowtype;
  v_policy public.quotation_business_policy_authorities%rowtype;
  v_existing public.sdf_quotation_business_draft_adapters%rowtype;
  v_business public.quote_request_quotation_business_drafts%rowtype;
  v_vat_context jsonb;
  v_pricing jsonb;
  v_sdf_pricing jsonb;
  v_pricing_reference jsonb;
  v_identity_base jsonb;
  v_customer jsonb;
  v_scope_base jsonb;
  v_scope jsonb;
  v_lines jsonb;
  v_payload jsonb;
  v_result jsonb;
  v_request_fingerprint text;
  v_payload_sha256 text;
  v_integrity_mac text;
  v_current_submission_sha256 text;
  v_current_pricing_sha256 text;
  v_current_document_sha256 text;
  v_current_decision_sha256 text;
  v_implementation_minor bigint;
  v_recurring_minor bigint;
  v_vat_minor bigint;
  v_has_existing boolean := false;
  v_intake_id uuid := gen_random_uuid();
  v_snapshot_id uuid := gen_random_uuid();
  v_approval_draft_id uuid := gen_random_uuid();
  v_business_draft_id uuid := gen_random_uuid();
  v_now timestamptz := clock_timestamp();
  v_resolution_date date := (clock_timestamp() at time zone 'Europe/Brussels')::date;
  v_actor text;
begin
  if p_preparation_authority_id is null or p_commercial_decision_id is null
     or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'SDF_BUSINESS_DRAFT_INPUT_INVALID';
  end if;

  v_operator := lws_internal.assert_sdf_owner_v1();
  v_actor := 'OPERATOR:' || v_operator.operator_id::text;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_preparation_authority_id::text, 0)
  );

  select * into v_existing
  from public.sdf_quotation_business_draft_adapters
  where idempotency_key = p_idempotency_key;
  v_has_existing := found;
  if v_has_existing and (
    v_existing.preparation_authority_id is distinct from p_preparation_authority_id
    or v_existing.commercial_decision_id is distinct from p_commercial_decision_id
  ) then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
  end if;

  select * into v_preparation
  from public.sdf_quotation_preparation_authorities
  where authority_id = p_preparation_authority_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'SDF_QUOTATION_PREPARATION_NOT_FOUND';
  end if;
  if v_preparation.sdf_package = 'maatwerk' then
    raise exception using errcode = '55000', message = 'SDF_MANUAL_PRICING_REQUIRED';
  end if;
  select * into v_decision
  from public.sdf_quotation_commercial_decisions
  where decision_id = p_commercial_decision_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'SDF_COMMERCIAL_DECISION_NOT_FOUND';
  end if;
  if v_decision.preparation_authority_id is distinct from v_preparation.authority_id
     or v_decision.quote_request_id is distinct from v_preparation.quote_request_id
     or v_decision.quotation_id is distinct from v_preparation.quotation_id then
    raise exception using errcode = '42501', message = 'SDF_BUSINESS_DRAFT_CROSS_DOSSIER';
  end if;
  if v_decision.sdf_package = 'maatwerk' then
    raise exception using errcode = '55000', message = 'SDF_MANUAL_PRICING_REQUIRED';
  end if;

  select * into strict v_submission
  from public.sdf_qualification_intake_submissions
  where intake_id = v_preparation.qualification_intake_id
    and submission_sequence = v_preparation.submission_sequence;
  select * into strict v_request
  from public.quote_requests
  where id = v_preparation.quote_request_id;

  v_current_submission_sha256 := encode(
    extensions.digest(convert_to(v_submission.answers::text, 'UTF8'), 'sha256'), 'hex'
  );
  v_pricing := lws_internal.get_sdf_budget_guard_pricing_authority_v2(v_decision.sdf_package);
  v_current_pricing_sha256 := encode(
    extensions.digest(convert_to(v_pricing::text, 'UTF8'), 'sha256'), 'hex'
  );
  v_current_document_sha256 := (
    lws_internal.evaluate_sdf_document_completeness_v1(v_request.id)->>'evidence_sha256'
  );
  v_current_decision_sha256 := encode(
    extensions.digest(convert_to(v_decision.canonical_payload::text, 'UTF8'), 'sha256'), 'hex'
  );

  if v_current_submission_sha256 is distinct from rtrim(v_preparation.submission_sha256)
     or v_current_submission_sha256 is distinct from rtrim(v_decision.submission_sha256) then
    raise exception using errcode = '55000', message = 'SDF_QUALIFICATION_INTEGRITY_MISMATCH';
  end if;
  if v_current_pricing_sha256 is distinct from rtrim(v_preparation.pricing_authority_sha256)
     or v_current_pricing_sha256 is distinct from rtrim(v_decision.pricing_authority_sha256) then
    raise exception using errcode = '55000', message = 'SDF_PRICING_AUTHORITY_MISMATCH';
  end if;
  if v_current_document_sha256 is distinct from rtrim(v_preparation.document_evidence_sha256)
     or v_current_document_sha256 is distinct from rtrim(v_decision.document_evidence_sha256) then
    raise exception using errcode = '55000', message = 'SDF_DOCUMENT_EVIDENCE_MISMATCH';
  end if;
  if v_current_decision_sha256 is distinct from rtrim(v_decision.decision_sha256) then
    raise exception using errcode = '55000', message = 'SDF_COMMERCIAL_DECISION_INTEGRITY_MISMATCH';
  end if;

  v_request_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'bridge_version', 1,
    'preparation_authority_id', v_preparation.authority_id,
    'commercial_decision_id', v_decision.decision_id,
    'quote_request_id', v_request.id,
    'submission_sha256', v_current_submission_sha256,
    'pricing_authority_sha256', v_current_pricing_sha256,
    'document_evidence_sha256', v_current_document_sha256,
    'decision_sha256', v_current_decision_sha256
  )::text, 'UTF8'), 'sha256'), 'hex');

  if v_has_existing then
    if rtrim(v_existing.request_fingerprint) <> v_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed', true);
  end if;
  if exists (
    select 1 from public.sdf_quotation_business_draft_adapters
    where preparation_authority_id = p_preparation_authority_id
       or commercial_decision_id = p_commercial_decision_id
  ) then
    raise exception using errcode = '55000', message = 'SDF_BUSINESS_DRAFT_ALREADY_EXISTS';
  end if;

  v_implementation_minor := (v_pricing#>>'{implementation,amount_minor}')::bigint;
  v_recurring_minor := (v_pricing#>>'{recurring,amount_minor}')::bigint;

  v_vat_context := public.resolve_quotation_vat_authority_v1(v_request.id, v_resolution_date);
  if not public.is_sdf_vat_context_binding_valid_v1(
       v_decision.vat_decision_authority_id, v_vat_context
     )
     or v_decision.vat_context_sha256 is distinct from v_vat_context->>'context_sha256'
     or v_decision.vat_classification_id is distinct from (v_vat_context->>'classification_id')::uuid
     or v_decision.vat_turnover_snapshot_id is distinct from (v_vat_context->>'turnover_snapshot_id')::uuid then
    raise exception using errcode = '55000', message = 'SDF_VAT_AUTHORITY_CONTEXT_MISMATCH';
  end if;
  select * into strict v_vat
  from public.quotation_vat_decision_authorities
  where vat_decision_authority_id = v_decision.vat_decision_authority_id
    and status = 'APPROVED';
  select * into v_terms
  from public.quotation_terms_authorities
  where terms_authority_id = v_decision.terms_authority_id and status = 'APPROVED';
  if not found then
    raise exception using errcode = 'P0001', message = 'QUOTATION_TERMS_NOT_APPROVED';
  end if;
  select * into v_seller from public.resolve_quotation_seller_authority_v1();
  select * into strict v_template from public.resolve_approved_quotation_template_v1(
    'QUOTATION', 'nl-BE', 'EUR', 1::smallint, 1::smallint, 1::smallint
  );
  select * into strict v_policy
  from public.quotation_business_policy_authorities
  where policy_id = 'QUOTATION_BUSINESS_V1' and status = 'APPROVED';

  if nullif(btrim(v_request.name), '') is null
     or v_request.email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     or nullif(btrim(v_request.billing_address), '') is null
     or nullif(btrim(v_request.billing_city), '') is null
     or upper(coalesce(v_request.billing_country, '')) !~ '^[A-Z]{2}$' then
    raise exception using errcode = '55000', message = 'QUOTATION_CUSTOMER_IDENTITY_INCOMPLETE';
  end if;

  perform set_config('lws.sdf_generic_intake_adapter', 'CREATE', true);
  insert into public.quote_request_intakes (
    id, quote_request_id, status, access_token_hash, access_token_expires_at,
    access_token_revoked_at, started_at, submitted_at, confirmation,
    languages, created_at, updated_at
  ) values (
    v_intake_id, v_request.id, 'submitted',
    encode(extensions.digest(convert_to(
      'SDF_GENERIC_INTAKE:' || v_decision.decision_id::text || ':' || p_idempotency_key::text,
      'UTF8'
    ), 'sha256'), 'hex'),
    v_now + interval '1 day', v_now, v_now, v_now, true, '{}'::text[], v_now, v_now
  );
  perform set_config('lws.sdf_generic_intake_adapter', '', true);

  v_sdf_pricing := jsonb_build_object(
    'commercial_decision_id', v_decision.decision_id,
    'product_kind', 'sdf', 'package', v_decision.sdf_package, 'currency', 'EUR',
    'implementation', jsonb_build_object(
      'amount_minor', v_implementation_minor, 'price_mode', 'fixed'
    ),
    'recurring', jsonb_build_object(
      'amount_minor', v_recurring_minor, 'interval', 'month', 'price_mode', 'fixed'
    ),
    'pricing_authority_sha256', v_current_pricing_sha256,
    'submission_sha256', v_current_submission_sha256,
    'document_evidence_sha256', v_current_document_sha256
  );
  insert into public.quote_request_pricing_snapshots (
    id, intake_id, snapshot_contract_version, config_version, config_hash,
    normalized_evidence, calculation, package_advice, budget_evaluation,
    package_definition, recurring_services, sdf_pricing
  ) values (
    v_snapshot_id, v_intake_id, 4, '2026-09-01-v4', v_current_pricing_sha256,
    '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, null, null, v_sdf_pricing
  );
  v_integrity_mac := encode(extensions.hmac(
    convert_to(v_sdf_pricing::text, 'UTF8'),
    convert_to(rtrim(v_decision.decision_sha256), 'UTF8'), 'sha256'
  ), 'hex');
  insert into public.quote_request_pricing_snapshot_integrity (
    snapshot_id, algorithm_version, key_id, mac
  ) values (v_snapshot_id, 'hmac-sha256-v1', 'v4', v_integrity_mac);
  v_pricing_reference := jsonb_build_object(
    'snapshot_id', v_snapshot_id, 'snapshot_contract_version', 4,
    'integrity_algorithm_version', 'hmac-sha256-v1',
    'integrity_key_id', 'v4', 'integrity_mac', v_integrity_mac
  );

  v_lines := jsonb_build_array(
    jsonb_build_object(
      'line_id', 'sdf-implementation', 'sequence', 1,
      'product_or_service_code', 'SDF_IMPLEMENTATION',
      'description', 'Slimme Documentenflow implementatie',
      'quantity', 1, 'unit', 'project', 'unit_price_minor', v_implementation_minor,
      'discount_minor', 0, 'vat_treatment', v_vat.vat_treatment,
      'vat_rate', v_vat.vat_rate, 'line_net_amount_minor', v_implementation_minor,
      'cost_type', 'ONE_TIME'
    ),
    jsonb_build_object(
      'line_id', 'sdf-recurring-monthly', 'sequence', 2,
      'product_or_service_code', 'SDF_RECURRING_MONTHLY',
      'description', 'Slimme Documentenflow maandelijkse dienstverlening',
      'quantity', 1, 'unit', 'month', 'unit_price_minor', v_recurring_minor,
      'discount_minor', 0, 'vat_treatment', v_vat.vat_treatment,
      'vat_rate', v_vat.vat_rate, 'line_net_amount_minor', v_recurring_minor,
      'cost_type', 'RECURRING'
    )
  );
  v_identity_base := jsonb_build_object(
    'source_quote_request_id', v_request.id, 'source_intake_id', v_intake_id,
    'customer_id', null,
    'legal_name', coalesce(nullif(btrim(v_request.company), ''), v_request.name),
    'contact_name', v_request.name, 'email', v_request.email,
    'address_line_1', v_request.billing_address, 'address_line_2', null,
    'postal_code', v_request.billing_postal_code, 'city', v_request.billing_city,
    'country_code', upper(v_request.billing_country),
    'enterprise_number', v_request.enterprise_number, 'vat_number', v_request.vat_number,
    'source_fields', jsonb_build_object(
      'identity', 'quote_requests', 'origin', 'sdf_quotation_commercial_decision'
    )
  );
  v_customer := v_identity_base || jsonb_build_object(
    'snapshot_sha256', encode(
      extensions.digest(convert_to(v_identity_base::text, 'UTF8'), 'sha256'), 'hex'
    )
  );
  v_scope_base := jsonb_build_object(
    'project_id', null,
    'project_title', 'Slimme Documentenflow ' || upper(v_decision.sdf_package),
    'project_type', 'slimme_documentenflow',
    'scope_summary', 'Server-authoritative SDF qualification and commercial decision',
    'requested_languages', jsonb_build_array('nl'), 'included_page_count', 0,
    'features', coalesce(v_submission.answers->'workflowCapabilities', '[]'::jsonb),
    'copywriting', null, 'seo', null, 'hosting', null, 'maintenance', null,
    'exclusions', '[]'::jsonb, 'assumptions', '[]'::jsonb, 'indicative_timing', null,
    'source_intake_id', v_intake_id, 'source_pricing_snapshot_id', v_snapshot_id
  );
  v_scope := v_scope_base || jsonb_build_object(
    'snapshot_sha256', encode(
      extensions.digest(convert_to(v_scope_base::text, 'UTF8'), 'sha256'), 'hex'
    )
  );
  v_vat_minor := round(v_implementation_minor::numeric * v_vat.vat_rate / 100)::bigint;
  v_payload := jsonb_build_object(
    'contract_version', 1,
    'source_quote_request_id', v_request.id, 'source_intake_id', v_intake_id,
    'pricing_snapshot', v_pricing_reference, 'currency', 'EUR', 'line_items', v_lines,
    'totals', jsonb_build_object(
      'one_time_subtotal_minor', v_implementation_minor,
      'recurring_subtotal_minor', v_recurring_minor,
      'discount_total_minor', 0, 'vat_base_minor', v_implementation_minor,
      'vat_amount_minor', v_vat_minor,
      'total_gross_minor', v_implementation_minor + v_vat_minor
    ),
    'discount', jsonb_build_object(
      'discount_type', null, 'discount_value_minor', 0, 'discount_reason', null,
      'approved_by', null, 'approved_at', null
    ),
    'customer_identity', v_customer, 'project_scope', v_scope,
    'vat_approval', jsonb_build_object(
      'vat_treatment', v_vat.vat_treatment, 'vat_rate', v_vat.vat_rate,
      'vat_decision_source', v_vat.authority_source_identifier,
      'vat_approved_by', 'SDF_COMMERCIAL_DECISION:' || v_decision.decision_id::text,
      'vat_approved_at', to_char(v_decision.decided_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    ),
    'payment_schedule', v_decision.payment_schedule,
    'validity', jsonb_build_object(
      'valid_from', v_resolution_date,
      'valid_until', v_resolution_date + v_policy.default_validity_days,
      'validity_days', v_policy.default_validity_days,
      'approved_by', v_actor,
      'approved_at', to_char(v_now at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    ),
    'legal_references', jsonb_build_object(
      'terms_reference', v_terms.terms_id, 'terms_version', v_terms.terms_version,
      'terms_sha256', rtrim(v_terms.terms_sha256), 'terms_status', 'APPROVED',
      'agreement_template_reference', null, 'agreement_template_version', null,
      'agreement_template_sha256', null
    )
  );
  if not public.is_valid_quotation_approval_payload_v1(v_payload, true)
     or not public.is_current_pricing_snapshot_integrity_valid(
       v_intake_id, v_snapshot_id, v_pricing_reference
     ) then
    raise exception using errcode = '22023', message = 'SDF_BUSINESS_DRAFT_PAYLOAD_INVALID';
  end if;
  v_payload_sha256 := public.quotation_approval_payload_sha256_v1(v_payload);
  v_result := jsonb_build_object(
    'business_draft_id', v_business_draft_id,
    'approval_draft_id', v_approval_draft_id,
    'generic_intake_id', v_intake_id,
    'pricing_snapshot_id', v_snapshot_id,
    'snapshot_contract_version', 4,
    'commercial_decision_id', v_decision.decision_id,
    'preparation_authority_id', v_preparation.authority_id,
    'canonical_payload_sha256', v_payload_sha256,
    'status', 'SDF_COMMERCIAL_BUSINESS_DRAFT_CREATED',
    'replayed', false
  );

  insert into public.quote_request_quotation_approval_drafts (
    id, quote_request_id, intake_id, pricing_snapshot_id, approval_payload,
    payload_fingerprint, idempotency_key, created_by
  ) values (
    v_approval_draft_id, v_request.id, v_intake_id, v_snapshot_id, v_payload,
    v_payload_sha256, p_idempotency_key, v_actor
  );
  insert into public.quote_request_quotation_business_drafts (
    business_draft_id, approval_draft_id, quote_request_id, intake_id,
    pricing_snapshot_id, business_revision, operator_id, seller_authority_id,
    terms_authority_id, vat_decision_authority_id, template_authority_id,
    policy_authority_id, canonical_payload, canonical_payload_sha256,
    request_fingerprint, idempotency_key, result_payload, prepared_by_actor, prepared_at
  ) values (
    v_business_draft_id, v_approval_draft_id, v_request.id, v_intake_id,
    v_snapshot_id, 1, v_operator.operator_id, v_seller.seller_authority_id,
    v_terms.terms_authority_id, v_vat.vat_decision_authority_id, v_template.id,
    v_policy.policy_authority_id, v_payload, v_payload_sha256,
    v_request_fingerprint, p_idempotency_key, v_result, v_actor, v_now
  ) returning * into v_business;
  insert into public.quotation_business_draft_vat_bindings (
    business_draft_id, vat_decision_authority_id, authority_family,
    decision_code, decision_version, authority_sha256, vat_treatment,
    rate_semantics, invoice_literal, context_sha256, classification_id,
    turnover_snapshot_id
  ) values (
    v_business.business_draft_id, v_vat.vat_decision_authority_id,
    v_vat.authority_family, v_vat.decision_code, v_vat.decision_version,
    rtrim(v_vat.authority_sha256), v_vat.vat_treatment, v_vat.rate_semantics,
    v_vat.invoice_literal, v_vat_context->>'context_sha256',
    (v_vat_context->>'classification_id')::uuid,
    (v_vat_context->>'turnover_snapshot_id')::uuid
  );
  perform public.assert_quotation_business_draft_vat_binding_v1(
    v_business.business_draft_id, true
  );

  insert into public.sdf_quotation_business_draft_adapters (
    quote_request_id, preparation_authority_id, commercial_decision_id,
    generic_intake_id, pricing_snapshot_id, approval_draft_id, business_draft_id,
    submission_sha256, pricing_authority_sha256, document_evidence_sha256,
    decision_sha256, request_fingerprint, idempotency_key, result_payload,
    created_by_operator_id
  ) values (
    v_request.id, v_preparation.authority_id, v_decision.decision_id,
    v_intake_id, v_snapshot_id, v_approval_draft_id, v_business.business_draft_id,
    v_current_submission_sha256, v_current_pricing_sha256,
    v_current_document_sha256, v_current_decision_sha256,
    v_request_fingerprint, p_idempotency_key, v_result, v_operator.operator_id
  );
  return v_result;
exception
  when no_data_found then
    raise exception using errcode = '55000', message = 'SDF_BUSINESS_DRAFT_LINEAGE_STALE';
end;
$$;

alter table public.sdf_quotation_business_draft_adapters enable row level security;
alter table public.sdf_quotation_business_draft_adapters force row level security;

revoke all privileges on table public.sdf_quotation_business_draft_adapters
from public, anon, authenticated, service_role;
revoke all on function public.guard_sdf_quotation_business_draft_adapter_v1()
from public, anon, authenticated, service_role;
revoke all on function public.create_sdf_quotation_business_draft_v1(uuid, uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.create_sdf_quotation_business_draft_v1(uuid, uuid, uuid)
to authenticated;

comment on table public.sdf_quotation_business_draft_adapters is
  'Immutable SDF-to-generic quotation adapter lineage. References the existing generic intake, v4 snapshot, approval draft prerequisite, and commercial business draft without creating approval or issuance.';
comment on function public.create_sdf_quotation_business_draft_v1(uuid, uuid, uuid) is
  'Owner-only QF-2 bridge. Materializes a revoked generic SDF adapter intake, strict snapshot v4, pre-approval draft, VAT binding, and existing generic commercial business draft from server authorities only.';