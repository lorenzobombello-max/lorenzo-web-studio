create table public.quotation_vat_classification_operations (
  operation_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null references public.quote_requests(id),
  resolution_date date not null,
  approved_review_decision_id uuid,
  context_sha256 char(64) not null check (context_sha256 ~ '^[0-9a-f]{64}$'),
  classification_policy_id uuid
    references public.quotation_vat_classification_policies(classification_policy_id),
  classification_policy_version text,
  classification_policy_sha256 char(64),
  idempotency_key uuid not null unique,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  result_payload jsonb not null,
  process_identity text not null check (
    process_identity = 'VAT_CLASSIFICATION_ORCHESTRATOR_V1'
  ),
  created_at timestamptz not null default clock_timestamp(),
  constraint quotation_vat_classification_operation_policy_binding_valid check (
    (
      classification_policy_id is null
      and classification_policy_version is null
      and classification_policy_sha256 is null
    ) or (
      classification_policy_id is not null
      and nullif(btrim(classification_policy_version), '') is not null
      and classification_policy_sha256 ~ '^[0-9a-f]{64}$'
    )
  )
);

create trigger trg_quotation_vat_classification_operation_immutable
before update or delete on public.quotation_vat_classification_operations
for each row execute function public.prevent_quotation_vat_governance_mutation_v1();

create function lws_internal.assert_quotation_vat_context_current_v1(
  p_quote_request_id uuid,
  p_expected_context_sha256 text
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_current_context_sha256 text;
begin
  if p_quote_request_id is null
     or p_expected_context_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'VAT_CONTEXT_INVALID';
  end if;

  v_current_context_sha256 := public.quotation_vat_context_sha256_v1(
    p_quote_request_id
  );
  if v_current_context_sha256 is distinct from p_expected_context_sha256 then
    raise exception using errcode = 'P0001', message = 'VAT_CONTEXT_STALE';
  end if;
end;
$$;

create function lws_internal.quotation_vat_classification_policy_complete_v1(
  p_policy public.quotation_vat_classification_policies
)
returns boolean
language sql
stable
set search_path = pg_catalog, public
as $$
  select
    p_policy.status = 'APPROVED'
    and p_policy.applicability_predicate->>'transaction_characteristics_status' = 'SUPPORTED'
    and p_policy.applicability_predicate->>'exclusions_status' = 'CLEAR'
    and p_policy.required_evidence_schema->>'status' = 'COMPLETE'
    and p_policy.required_evidence_schema->'required' = '[]'::jsonb
    and p_policy.source_allowlist->>'status' = 'APPROVED'
    and jsonb_typeof(p_policy.source_allowlist->'sources') = 'array'
    and jsonb_array_length(p_policy.source_allowlist->'sources') = 1;
$$;

create function lws_internal.validate_quotation_vat_classification_policy_binding_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  v_policy public.quotation_vat_classification_policies%rowtype;
begin
  if new.classification_policy_id is null then
    return new;
  end if;

  select * into v_policy
  from public.quotation_vat_classification_policies
  where classification_policy_id = new.classification_policy_id;
  if not found
     or new.classification_policy_version is distinct from v_policy.policy_version
     or rtrim(new.classification_policy_sha256) is distinct from rtrim(v_policy.policy_sha256)
     or new.classification_code is distinct from v_policy.classification_code then
    raise exception using
      errcode = 'P0001',
      message = 'VAT_CLASSIFICATION_POLICY_BINDING_INVALID';
  end if;

  return new;
end;
$$;

create trigger trg_quotation_vat_classification_policy_binding_valid
before insert on public.quotation_vat_transaction_classifications
for each row execute function
  lws_internal.validate_quotation_vat_classification_policy_binding_v1();

create or replace function public.record_quotation_vat_transaction_classification_v1(
  p_quote_request_id uuid,
  p_source_reference text,
  p_source_sha256 text,
  p_classified_by text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $$
declare
  v_request public.quote_requests%rowtype;
  v_policy public.quotation_vat_classification_policies%rowtype;
  v_context_sha256 text;
  v_country text;
  v_policy_count integer;
  v_id uuid;
begin
  if p_quote_request_id is null
     or nullif(btrim(p_source_reference), '') is null
     or p_source_sha256 !~ '^[0-9a-f]{64}$'
     or p_classified_by <> 'VAT_CLASSIFICATION_ORCHESTRATOR_V1' then
    raise exception using
      errcode = 'P0001',
      message = 'VAT_CLASSIFICATION_REVIEW_REQUIRED';
  end if;

  select * into v_request
  from public.quote_requests
  where id = p_quote_request_id;
  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'VAT_CLASSIFICATION_REVIEW_REQUIRED';
  end if;

  v_country := lower(btrim(coalesce(v_request.billing_country, '')));
  if v_request.customer_type <> 'business'
     or v_country not in ('be', 'belgie', 'belgië', 'belgium')
     or nullif(btrim(v_request.enterprise_number), '') is null
     or v_request.enterprise_validation_status <> 'format_valid_not_externally_verified'
     or nullif(btrim(v_request.vat_number), '') is null
     or v_request.vat_validation_status <> 'valid'
     or v_request.vat_validated_at is null
     or nullif(btrim(v_request.billing_address), '') is null
     or nullif(btrim(v_request.billing_postal_code), '') is null
     or nullif(btrim(v_request.billing_city), '') is null then
    raise exception using
      errcode = 'P0001',
      message = 'VAT_CLASSIFICATION_REVIEW_REQUIRED';
  end if;

  select count(*)::integer into v_policy_count
  from public.quotation_vat_classification_policies as policy
  join public.quotation_vat_decision_authorities as authority
    on authority.vat_decision_authority_id = policy.vat_decision_authority_id
  where policy.status = 'APPROVED'
    and policy.customer_type = v_request.customer_type
    and policy.jurisdiction = 'BE'
    and policy.effective_from <= (clock_timestamp() at time zone 'Europe/Brussels')::date
    and (policy.effective_until is null
      or policy.effective_until >= (clock_timestamp() at time zone 'Europe/Brussels')::date)
    and authority.status = 'APPROVED'
    and authority.authority_family = 'LWS_OUTGOING_VAT'
    and authority.applicability_code = 'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION_V1'
    and rtrim(authority.authority_sha256) = rtrim(policy.source_sha256);
  if v_policy_count <> 1 then
    raise exception using
      errcode = 'P0001',
      message = 'VAT_CLASSIFICATION_REVIEW_REQUIRED';
  end if;

  select policy.* into strict v_policy
  from public.quotation_vat_classification_policies as policy
  join public.quotation_vat_decision_authorities as authority
    on authority.vat_decision_authority_id = policy.vat_decision_authority_id
  where policy.status = 'APPROVED'
    and policy.customer_type = v_request.customer_type
    and policy.jurisdiction = 'BE'
    and policy.effective_from <= (clock_timestamp() at time zone 'Europe/Brussels')::date
    and (policy.effective_until is null
      or policy.effective_until >= (clock_timestamp() at time zone 'Europe/Brussels')::date)
    and authority.status = 'APPROVED'
    and authority.authority_family = 'LWS_OUTGOING_VAT'
    and authority.applicability_code = 'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION_V1'
    and rtrim(authority.authority_sha256) = rtrim(policy.source_sha256);

  if not lws_internal.quotation_vat_classification_policy_complete_v1(v_policy)
     or v_policy.classification_code <> 'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION'
     or v_policy.applicability_predicate->>'customer_type' <> v_request.customer_type
     or not exists (
       select 1
       from jsonb_array_elements_text(
         v_policy.applicability_predicate->'billing_country_values'
       ) as country(value)
       where lower(country.value) = v_country
     )
     or not exists (
       select 1
       from jsonb_array_elements(v_policy.source_allowlist->'sources') as source(value)
       where source.value->>'reference' = p_source_reference
         and source.value->>'sha256' = p_source_sha256
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'VAT_CLASSIFICATION_REVIEW_REQUIRED';
  end if;

  v_context_sha256 := public.quotation_vat_context_sha256_v1(p_quote_request_id);
  perform lws_internal.assert_quotation_vat_context_current_v1(
    p_quote_request_id,
    v_context_sha256
  );

  insert into public.quotation_vat_transaction_classifications (
    quote_request_id, context_sha256, classification_code,
    source_reference, source_sha256, classified_by, classified_at,
    classification_policy_id, classification_policy_version,
    classification_policy_sha256
  ) values (
    p_quote_request_id, v_context_sha256, v_policy.classification_code,
    p_source_reference, p_source_sha256, p_classified_by, clock_timestamp(),
    v_policy.classification_policy_id, v_policy.policy_version,
    v_policy.policy_sha256
  )
  returning classification_id into v_id;

  return v_id;
exception
  when unique_violation then
    raise exception using
      errcode = 'P0001',
      message = 'QUOTATION_VAT_CLASSIFICATION_CONFLICT';
end;
$$;

create function public.ensure_quotation_vat_transaction_classification_v1(
  p_quote_request_id uuid,
  p_resolution_date date,
  p_idempotency_key uuid,
  p_approved_review_decision_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_request public.quote_requests%rowtype;
  v_existing public.quotation_vat_classification_operations%rowtype;
  v_policy public.quotation_vat_classification_policies%rowtype;
  v_policy_count integer;
  v_context_sha256 text;
  v_country text;
  v_request_fingerprint text;
  v_source_reference text;
  v_source_sha256 text;
  v_classification_id uuid;
  v_classified_at timestamptz;
  v_result jsonb;
begin
  if p_quote_request_id is null
     or p_resolution_date is null
     or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'VAT_CLASSIFICATION_REQUEST_INVALID';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_quote_request_id::text, 0)
  );

  v_request_fingerprint := encode(extensions.digest(convert_to(
    jsonb_build_object(
      'approved_review_decision_id', p_approved_review_decision_id,
      'quote_request_id', p_quote_request_id,
      'resolution_date', p_resolution_date
    )::text,
    'UTF8'
  ), 'sha256'), 'hex');

  select * into v_existing
  from public.quotation_vat_classification_operations
  where idempotency_key = p_idempotency_key;
  if found then
    if rtrim(v_existing.request_fingerprint) <> v_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed', true);
  end if;

  select * into v_request
  from public.quote_requests
  where id = p_quote_request_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'QUOTATION_VAT_CONTEXT_REQUIRED';
  end if;

  v_context_sha256 := public.quotation_vat_context_sha256_v1(p_quote_request_id);
  v_country := lower(btrim(coalesce(v_request.billing_country, '')));

  if p_approved_review_decision_id is not null then
    return jsonb_build_object(
      'quote_request_id', p_quote_request_id,
      'context_sha256', v_context_sha256,
      'classification_status', 'REVIEW_REQUIRED',
      'classification_id', null,
      'classification_policy_id', null,
      'policy_version', null,
      'blocking_reason', 'VAT_CLASSIFICATION_REVIEW_REQUIRED',
      'classified_at', null,
      'replayed', false
    );
  end if;

  if v_request.customer_type = 'individual' then
    return jsonb_build_object(
      'quote_request_id', p_quote_request_id,
      'context_sha256', v_context_sha256,
      'classification_status', 'REVIEW_REQUIRED',
      'classification_id', null,
      'classification_policy_id', null,
      'policy_version', null,
      'blocking_reason', 'VAT_INDIVIDUAL_POLICY_REVIEW_REQUIRED',
      'classified_at', null,
      'replayed', false
    );
  end if;

  if v_request.customer_type is null or v_country = '' then
    return jsonb_build_object(
      'quote_request_id', p_quote_request_id,
      'context_sha256', v_context_sha256,
      'classification_status', 'REVIEW_REQUIRED',
      'classification_id', null,
      'classification_policy_id', null,
      'policy_version', null,
      'blocking_reason', 'VAT_CLASSIFICATION_REVIEW_REQUIRED',
      'classified_at', null,
      'replayed', false
    );
  end if;

  if v_country not in ('be', 'belgie', 'belgië', 'belgium') then
    return jsonb_build_object(
      'quote_request_id', p_quote_request_id,
      'context_sha256', v_context_sha256,
      'classification_status', 'UNSUPPORTED',
      'classification_id', null,
      'classification_policy_id', null,
      'policy_version', null,
      'blocking_reason', 'VAT_POLICY_UNSUPPORTED',
      'classified_at', null,
      'replayed', false
    );
  end if;

  select count(*)::integer into v_policy_count
  from public.quotation_vat_classification_policies
  where status = 'APPROVED'
    and customer_type = v_request.customer_type
    and jurisdiction = 'BE'
    and effective_from <= p_resolution_date
    and (effective_until is null or effective_until >= p_resolution_date);
  if v_policy_count <> 1 then
    return jsonb_build_object(
      'quote_request_id', p_quote_request_id,
      'context_sha256', v_context_sha256,
      'classification_status', 'REVIEW_REQUIRED',
      'classification_id', null,
      'classification_policy_id', null,
      'policy_version', null,
      'blocking_reason', 'VAT_CLASSIFICATION_REVIEW_REQUIRED',
      'classified_at', null,
      'replayed', false
    );
  end if;

  select * into strict v_policy
  from public.quotation_vat_classification_policies
  where status = 'APPROVED'
    and customer_type = v_request.customer_type
    and jurisdiction = 'BE'
    and effective_from <= p_resolution_date
    and (effective_until is null or effective_until >= p_resolution_date);

  if not lws_internal.quotation_vat_classification_policy_complete_v1(v_policy) then
    v_result := jsonb_build_object(
      'quote_request_id', p_quote_request_id,
      'context_sha256', v_context_sha256,
      'classification_status', 'REVIEW_REQUIRED',
      'classification_id', null,
      'classification_policy_id', v_policy.classification_policy_id,
      'policy_version', v_policy.policy_version,
      'blocking_reason', 'VAT_CLASSIFICATION_REVIEW_REQUIRED',
      'classified_at', null,
      'replayed', false
    );
  else
    select
      source.value->>'reference',
      source.value->>'sha256'
    into strict v_source_reference, v_source_sha256
    from jsonb_array_elements(v_policy.source_allowlist->'sources') as source(value);

    perform lws_internal.assert_quotation_vat_context_current_v1(
      p_quote_request_id,
      v_context_sha256
    );
    v_classification_id := public.record_quotation_vat_transaction_classification_v1(
      p_quote_request_id,
      v_source_reference,
      v_source_sha256,
      'VAT_CLASSIFICATION_ORCHESTRATOR_V1'
    );
    select classified_at into strict v_classified_at
    from public.quotation_vat_transaction_classifications
    where classification_id = v_classification_id;
    v_result := jsonb_build_object(
      'quote_request_id', p_quote_request_id,
      'context_sha256', v_context_sha256,
      'classification_status', 'AUTO_CLASSIFIED',
      'classification_id', v_classification_id,
      'classification_policy_id', v_policy.classification_policy_id,
      'policy_version', v_policy.policy_version,
      'blocking_reason', null,
      'classified_at', v_classified_at,
      'replayed', false
    );
  end if;

  perform lws_internal.assert_quotation_vat_context_current_v1(
    p_quote_request_id,
    v_context_sha256
  );

  insert into public.quotation_vat_classification_operations (
    quote_request_id, resolution_date, approved_review_decision_id,
    context_sha256, classification_policy_id, classification_policy_version,
    classification_policy_sha256, idempotency_key, request_fingerprint,
    result_payload, process_identity
  ) values (
    p_quote_request_id, p_resolution_date, p_approved_review_decision_id,
    v_context_sha256, v_policy.classification_policy_id, v_policy.policy_version,
    v_policy.policy_sha256, p_idempotency_key, v_request_fingerprint,
    v_result, 'VAT_CLASSIFICATION_ORCHESTRATOR_V1'
  );

  return v_result;
end;
$$;

alter table public.quotation_vat_classification_operations enable row level security;
alter table public.quotation_vat_classification_operations force row level security;

revoke all privileges on table public.quotation_vat_classification_operations
from public, anon, authenticated, service_role;
grant select on table public.quotation_vat_classification_operations to service_role;

revoke all on function lws_internal.assert_quotation_vat_context_current_v1(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.quotation_vat_classification_policy_complete_v1(
  public.quotation_vat_classification_policies
) from public, anon, authenticated, service_role;
revoke all on function lws_internal.validate_quotation_vat_classification_policy_binding_v1()
from public, anon, authenticated, service_role;
revoke all on function public.record_quotation_vat_transaction_classification_v1(
  uuid, text, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.ensure_quotation_vat_transaction_classification_v1(
  uuid, date, uuid, uuid
) from public, anon, authenticated, service_role;

grant execute on function public.record_quotation_vat_transaction_classification_v1(
  uuid, text, text, text
) to service_role;
grant execute on function public.ensure_quotation_vat_transaction_classification_v1(
  uuid, date, uuid, uuid
) to service_role;

comment on function public.record_quotation_vat_transaction_classification_v1(
  uuid, text, text, text
) is
  'Appends policy-bound VAT classification evidence only after independently validating current request context, authority, complete policy evidence, source allowlist, and fixed process identity.';

comment on function public.ensure_quotation_vat_transaction_classification_v1(
  uuid, date, uuid, uuid
) is
  'Service-only idempotent VAT classification orchestrator. Unsupported or incomplete policy contexts remain fail closed without accepting a caller-supplied tax result.';