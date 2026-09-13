alter table public.quotation_business_draft_vat_bindings
  add column classification_policy_id uuid,
  add column classification_policy_version text,
  add column classification_policy_sha256 char(64),
  add column turnover_adapter_id uuid,
  add column turnover_adapter_version text,
  add column turnover_source_projection_id text,
  add column turnover_projection_version text,
  add column turnover_source_sha256 char(64),
  add column turnover_category_authority_manifest_sha256 char(64);

do $$
begin
  if exists (select 1 from public.quotation_business_draft_vat_bindings) then
    raise exception using
      errcode = 'P0001',
      message = 'LEGACY_QUOTATION_VAT_EVIDENCE_BINDING_REQUIRED';
  end if;
end;
$$;

alter table public.quotation_business_draft_vat_bindings
  alter column classification_policy_id set not null,
  alter column classification_policy_version set not null,
  alter column classification_policy_sha256 set not null,
  alter column turnover_adapter_id set not null,
  alter column turnover_adapter_version set not null,
  alter column turnover_source_projection_id set not null,
  alter column turnover_projection_version set not null,
  alter column turnover_source_sha256 set not null,
  alter column turnover_category_authority_manifest_sha256 set not null,
  add constraint quotation_business_draft_vat_binding_policy_fk
    foreign key (classification_policy_id)
    references public.quotation_vat_classification_policies(classification_policy_id)
    on delete restrict,
  add constraint quotation_business_draft_vat_binding_adapter_fk
    foreign key (turnover_adapter_id)
    references public.vat_finance_projection_adapters(adapter_id)
    on delete restrict,
  add constraint quotation_business_draft_vat_binding_projection_fk
    foreign key (turnover_snapshot_id)
    references public.quotation_vat_turnover_snapshot_projection_bindings(turnover_snapshot_id)
    on delete restrict,
  add constraint quotation_business_draft_vat_policy_metadata_valid check (
    nullif(btrim(classification_policy_version), '') is not null
    and classification_policy_sha256 ~ '^[0-9a-f]{64}$'
  ),
  add constraint quotation_business_draft_vat_projection_metadata_valid check (
    nullif(btrim(turnover_adapter_version), '') is not null
    and nullif(btrim(turnover_source_projection_id), '') is not null
    and nullif(btrim(turnover_projection_version), '') is not null
    and turnover_source_sha256 ~ '^[0-9a-f]{64}$'
    and turnover_category_authority_manifest_sha256 ~ '^[0-9a-f]{64}$'
  );

create or replace function public.resolve_quotation_vat_authority_v1(
  p_quote_request_id uuid,
  p_resolution_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, lws_internal, extensions
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
    raise exception using
      errcode = 'P0001', message = 'QUOTATION_VAT_DECISION_NOT_APPROVED';
  end if;

  select count(*)::integer into v_count
  from public.quotation_vat_decision_authorities
  where authority_family = 'LWS_OUTGOING_VAT'
    and status = 'APPROVED'
    and effective_from <= p_resolution_date
    and (effective_until is null or effective_until >= p_resolution_date);
  if v_count <> 1 then
    raise exception using
      errcode = 'P0001', message = 'QUOTATION_VAT_DECISION_NOT_APPROVED';
  end if;
  select * into strict v_authority
  from public.quotation_vat_decision_authorities
  where authority_family = 'LWS_OUTGOING_VAT'
    and status = 'APPROVED'
    and effective_from <= p_resolution_date
    and (effective_until is null or effective_until >= p_resolution_date);

  select * into v_request
  from public.quote_requests
  where id = p_quote_request_id;
  if not found then
    raise exception using
      errcode = 'P0001', message = 'QUOTATION_VAT_CONTEXT_REQUIRED';
  end if;
  if upper(coalesce(v_request.billing_country, '')) <> v_authority.jurisdiction then
    raise exception using
      errcode = 'P0001', message = 'QUOTATION_VAT_CONTEXT_UNSUPPORTED';
  end if;

  v_context_sha256 := public.quotation_vat_context_sha256_v1(p_quote_request_id);
  select count(*)::integer into v_count
  from public.quotation_vat_transaction_classifications classification
  join public.quotation_vat_classification_policies policy
    on policy.classification_policy_id = classification.classification_policy_id
   and policy.policy_version = classification.classification_policy_version
   and rtrim(policy.policy_sha256) = rtrim(classification.classification_policy_sha256)
   and policy.classification_code = classification.classification_code
   and policy.vat_decision_authority_id = v_authority.vat_decision_authority_id
   and rtrim(policy.source_sha256) = rtrim(v_authority.authority_sha256)
  where classification.quote_request_id = p_quote_request_id
    and classification.context_sha256 = v_context_sha256
    and classification.classification_code =
      'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION'
    and policy.status = 'APPROVED'
    and policy.policy_family = 'LWS_OUTGOING_VAT_CLASSIFICATION'
    and policy.customer_type = v_request.customer_type
    and policy.jurisdiction = v_authority.jurisdiction
    and policy.effective_from <= p_resolution_date
    and (policy.effective_until is null or policy.effective_until >= p_resolution_date)
    and lws_internal.quotation_vat_classification_policy_complete_v1(policy);
  if v_count <> 1 then
    raise exception using
      errcode = 'P0001', message = 'QUOTATION_VAT_CONTEXT_REQUIRED';
  end if;
  select classification.* into strict v_classification
  from public.quotation_vat_transaction_classifications classification
  join public.quotation_vat_classification_policies policy
    on policy.classification_policy_id = classification.classification_policy_id
   and policy.policy_version = classification.classification_policy_version
   and rtrim(policy.policy_sha256) = rtrim(classification.classification_policy_sha256)
   and policy.classification_code = classification.classification_code
   and policy.vat_decision_authority_id = v_authority.vat_decision_authority_id
   and rtrim(policy.source_sha256) = rtrim(v_authority.authority_sha256)
  where classification.quote_request_id = p_quote_request_id
    and classification.context_sha256 = v_context_sha256
    and classification.classification_code =
      'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION'
    and policy.status = 'APPROVED'
    and policy.policy_family = 'LWS_OUTGOING_VAT_CLASSIFICATION'
    and policy.customer_type = v_request.customer_type
    and policy.jurisdiction = v_authority.jurisdiction
    and policy.effective_from <= p_resolution_date
    and (policy.effective_until is null or policy.effective_until >= p_resolution_date)
    and lws_internal.quotation_vat_classification_policy_complete_v1(policy);

  select count(*)::integer into v_count
  from public.quotation_vat_turnover_snapshots snapshot
  join public.quotation_vat_turnover_snapshot_projection_bindings binding
    on binding.turnover_snapshot_id = snapshot.turnover_snapshot_id
   and binding.source_projection_id = snapshot.source_reference
   and rtrim(binding.source_sha256) = rtrim(snapshot.source_sha256)
   and binding.projection_version = binding.adapter_version
   and rtrim(binding.category_authority_manifest_sha256) = encode(
     extensions.digest(convert_to(binding.category_authority_manifest::text, 'UTF8'), 'sha256'), 'hex'
   )
  join public.vat_finance_projection_adapters adapter
    on adapter.adapter_id = binding.adapter_id
   and adapter.adapter_version = binding.adapter_version
   and rtrim(adapter.source_schema_sha256) = rtrim(binding.source_schema_sha256)
   and adapter.status = 'APPROVED'
   and adapter.effective_from <= snapshot.measurement_watermark
   and (adapter.effective_until is null or adapter.effective_until >= snapshot.measurement_watermark)
  where snapshot.vat_decision_authority_id = v_authority.vat_decision_authority_id
    and snapshot.threshold_year = v_authority.threshold_year
    and snapshot.measurement_watermark = p_resolution_date;
  if v_count <> 1 then
    raise exception using
      errcode = 'P0001',
      message = 'QUOTATION_VAT_THRESHOLD_AUTHORITY_REVIEW_REQUIRED';
  end if;
  select snapshot.* into strict v_turnover
  from public.quotation_vat_turnover_snapshots snapshot
  join public.quotation_vat_turnover_snapshot_projection_bindings binding
    on binding.turnover_snapshot_id = snapshot.turnover_snapshot_id
   and binding.source_projection_id = snapshot.source_reference
   and rtrim(binding.source_sha256) = rtrim(snapshot.source_sha256)
   and binding.projection_version = binding.adapter_version
   and rtrim(binding.category_authority_manifest_sha256) = encode(
     extensions.digest(convert_to(binding.category_authority_manifest::text, 'UTF8'), 'sha256'), 'hex'
   )
  join public.vat_finance_projection_adapters adapter
    on adapter.adapter_id = binding.adapter_id
   and adapter.adapter_version = binding.adapter_version
   and rtrim(adapter.source_schema_sha256) = rtrim(binding.source_schema_sha256)
   and adapter.status = 'APPROVED'
   and adapter.effective_from <= snapshot.measurement_watermark
   and (adapter.effective_until is null or adapter.effective_until >= snapshot.measurement_watermark)
  where snapshot.vat_decision_authority_id = v_authority.vat_decision_authority_id
    and snapshot.threshold_year = v_authority.threshold_year
    and snapshot.measurement_watermark = p_resolution_date;
  if v_turnover.state <> 'BELOW_OR_AT_THRESHOLD'
     or v_turnover.governed_turnover_minor > v_authority.applicable_threshold_minor then
    raise exception using
      errcode = 'P0001', message = 'AUTHORITY_REVIEW_REQUIRED';
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

create or replace function public.validate_quotation_business_draft_vat_binding_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_classification public.quotation_vat_transaction_classifications%rowtype;
  v_projection public.quotation_vat_turnover_snapshot_projection_bindings%rowtype;
begin
  select * into strict v_classification
  from public.quotation_vat_transaction_classifications
  where classification_id = new.classification_id;
  select * into strict v_projection
  from public.quotation_vat_turnover_snapshot_projection_bindings
  where turnover_snapshot_id = new.turnover_snapshot_id;

  new.classification_policy_id := coalesce(
    new.classification_policy_id, v_classification.classification_policy_id
  );
  new.classification_policy_version := coalesce(
    new.classification_policy_version,
    v_classification.classification_policy_version
  );
  new.classification_policy_sha256 := coalesce(
    new.classification_policy_sha256,
    v_classification.classification_policy_sha256
  );
  new.turnover_adapter_id := coalesce(
    new.turnover_adapter_id, v_projection.adapter_id
  );
  new.turnover_adapter_version := coalesce(
    new.turnover_adapter_version, v_projection.adapter_version
  );
  new.turnover_source_projection_id := coalesce(
    new.turnover_source_projection_id, v_projection.source_projection_id
  );
  new.turnover_projection_version := coalesce(
    new.turnover_projection_version, v_projection.projection_version
  );
  new.turnover_source_sha256 := coalesce(
    new.turnover_source_sha256, v_projection.source_sha256
  );
  new.turnover_category_authority_manifest_sha256 := coalesce(
    new.turnover_category_authority_manifest_sha256,
    v_projection.category_authority_manifest_sha256
  );

  if not exists (
    select 1
    from public.quotation_vat_decision_authorities authority
    join public.quotation_vat_transaction_classifications classification
      on classification.classification_id = new.classification_id
    join public.quotation_vat_classification_policies policy
      on policy.classification_policy_id = classification.classification_policy_id
    join public.quotation_vat_turnover_snapshots snapshot
      on snapshot.turnover_snapshot_id = new.turnover_snapshot_id
     and snapshot.vat_decision_authority_id = authority.vat_decision_authority_id
    join public.quotation_vat_turnover_snapshot_projection_bindings projection
      on projection.turnover_snapshot_id = snapshot.turnover_snapshot_id
    join public.vat_finance_projection_adapters adapter
      on adapter.adapter_id = projection.adapter_id
    where authority.vat_decision_authority_id = new.vat_decision_authority_id
      and new.authority_family = authority.authority_family
      and new.decision_code = authority.decision_code
      and new.decision_version = authority.decision_version
      and rtrim(new.authority_sha256) = rtrim(authority.authority_sha256)
      and new.vat_treatment = authority.vat_treatment
      and new.rate_semantics = authority.rate_semantics
      and new.invoice_literal = authority.invoice_literal
      and new.context_sha256 = classification.context_sha256
      and new.classification_policy_id = policy.classification_policy_id
      and new.classification_policy_version = policy.policy_version
      and rtrim(new.classification_policy_sha256) = rtrim(policy.policy_sha256)
      and classification.classification_policy_version = policy.policy_version
      and rtrim(classification.classification_policy_sha256) = rtrim(policy.policy_sha256)
      and new.turnover_adapter_id = adapter.adapter_id
      and new.turnover_adapter_version = adapter.adapter_version
      and projection.adapter_version = adapter.adapter_version
      and new.turnover_source_projection_id = projection.source_projection_id
      and new.turnover_projection_version = projection.projection_version
      and rtrim(new.turnover_source_sha256) = rtrim(projection.source_sha256)
      and rtrim(new.turnover_category_authority_manifest_sha256)
        = rtrim(projection.category_authority_manifest_sha256)
  ) then
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  end if;
  return new;
end;
$$;

create or replace function public.assert_quotation_business_draft_vat_binding_v1(
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
  v_classification public.quotation_vat_transaction_classifications%rowtype;
  v_projection public.quotation_vat_turnover_snapshot_projection_bindings%rowtype;
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
    select * into strict v_classification
    from public.quotation_vat_transaction_classifications
    where classification_id = (v_resolved->>'classification_id')::uuid;
    select * into strict v_projection
    from public.quotation_vat_turnover_snapshot_projection_bindings
    where turnover_snapshot_id = (v_resolved->>'turnover_snapshot_id')::uuid;
    if v_authority.status <> 'APPROVED'
       or v_binding.vat_decision_authority_id is distinct from (v_resolved->>'vat_decision_authority_id')::uuid
       or v_binding.authority_family is distinct from v_resolved->>'authority_family'
       or v_binding.decision_code is distinct from v_resolved->>'decision_code'
       or v_binding.decision_version is distinct from v_resolved->>'decision_version'
       or rtrim(v_binding.authority_sha256) is distinct from v_resolved->>'authority_sha256'
       or rtrim(v_binding.context_sha256) is distinct from v_resolved->>'context_sha256'
       or v_binding.classification_id is distinct from v_classification.classification_id
       or v_binding.turnover_snapshot_id is distinct from v_projection.turnover_snapshot_id
       or v_binding.classification_policy_id is distinct from v_classification.classification_policy_id
       or v_binding.classification_policy_version is distinct from v_classification.classification_policy_version
       or rtrim(v_binding.classification_policy_sha256) is distinct from rtrim(v_classification.classification_policy_sha256)
       or v_binding.turnover_adapter_id is distinct from v_projection.adapter_id
       or v_binding.turnover_adapter_version is distinct from v_projection.adapter_version
       or v_binding.turnover_source_projection_id is distinct from v_projection.source_projection_id
       or v_binding.turnover_projection_version is distinct from v_projection.projection_version
       or rtrim(v_binding.turnover_source_sha256) is distinct from rtrim(v_projection.source_sha256)
       or rtrim(v_binding.turnover_category_authority_manifest_sha256)
          is distinct from rtrim(v_projection.category_authority_manifest_sha256) then
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
  v_classification public.quotation_vat_transaction_classifications%rowtype;
  v_projection public.quotation_vat_turnover_snapshot_projection_bindings%rowtype;
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
  select * into strict v_classification
  from public.quotation_vat_transaction_classifications
  where classification_id = (v_vat->>'classification_id')::uuid;
  select * into strict v_projection
  from public.quotation_vat_turnover_snapshot_projection_bindings
  where turnover_snapshot_id = (v_vat->>'turnover_snapshot_id')::uuid;

  v_result := public.upsert_quotation_business_draft_v1(
    p_actor_auth_user_id, p_intake_id, p_expected_revision,
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
    decision_code, decision_version, authority_sha256, vat_treatment,
    rate_semantics, invoice_literal, context_sha256, classification_id,
    turnover_snapshot_id, classification_policy_id,
    classification_policy_version, classification_policy_sha256,
    turnover_adapter_id, turnover_adapter_version,
    turnover_source_projection_id, turnover_projection_version,
    turnover_source_sha256, turnover_category_authority_manifest_sha256
  ) values (
    v_business.business_draft_id,
    (v_vat->>'vat_decision_authority_id')::uuid,
    v_vat->>'authority_family', v_vat->>'decision_code',
    v_vat->>'decision_version', v_vat->>'authority_sha256',
    v_vat->>'vat_treatment', v_vat->>'rate_semantics', v_vat->>'invoice_literal',
    v_vat->>'context_sha256', v_classification.classification_id,
    v_projection.turnover_snapshot_id, v_classification.classification_policy_id,
    v_classification.classification_policy_version,
    v_classification.classification_policy_sha256, v_projection.adapter_id,
    v_projection.adapter_version, v_projection.source_projection_id,
    v_projection.projection_version, v_projection.source_sha256,
    v_projection.category_authority_manifest_sha256
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
     or rtrim(v_binding.context_sha256) is distinct from v_vat->>'context_sha256'
     or v_binding.classification_id is distinct from v_classification.classification_id
     or v_binding.turnover_snapshot_id is distinct from v_projection.turnover_snapshot_id
     or v_binding.classification_policy_id is distinct from v_classification.classification_policy_id
     or v_binding.classification_policy_version is distinct from v_classification.classification_policy_version
     or rtrim(v_binding.classification_policy_sha256) is distinct from rtrim(v_classification.classification_policy_sha256)
     or v_binding.turnover_adapter_id is distinct from v_projection.adapter_id
     or v_binding.turnover_adapter_version is distinct from v_projection.adapter_version
     or v_binding.turnover_source_projection_id is distinct from v_projection.source_projection_id
     or v_binding.turnover_projection_version is distinct from v_projection.projection_version
     or rtrim(v_binding.turnover_source_sha256) is distinct from rtrim(v_projection.source_sha256)
     or rtrim(v_binding.turnover_category_authority_manifest_sha256)
       is distinct from rtrim(v_projection.category_authority_manifest_sha256) then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
  end if;
  return v_result || jsonb_build_object(
    'vat_authority_binding', to_jsonb(v_binding) - array[
      'classification_policy_id', 'classification_policy_version',
      'classification_policy_sha256', 'turnover_adapter_id',
      'turnover_adapter_version', 'turnover_source_projection_id',
      'turnover_projection_version', 'turnover_source_sha256',
      'turnover_category_authority_manifest_sha256'
    ]
  );
end;
$$;

revoke all on function public.resolve_quotation_vat_authority_v1(uuid, date)
from public, anon, authenticated, service_role;
grant execute on function public.resolve_quotation_vat_authority_v1(uuid, date)
to service_role;
revoke all on function public.upsert_quotation_business_draft_v2(uuid, uuid, bigint, uuid, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.upsert_quotation_business_draft_v2(uuid, uuid, bigint, uuid, jsonb)
to service_role;
revoke all on function public.create_sdf_quotation_business_draft_v1(uuid, uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.create_sdf_quotation_business_draft_v2(uuid, uuid, uuid, integer)
from public, anon, authenticated, service_role;
grant execute on function public.create_sdf_quotation_business_draft_v2(uuid, uuid, uuid, integer)
to authenticated;
