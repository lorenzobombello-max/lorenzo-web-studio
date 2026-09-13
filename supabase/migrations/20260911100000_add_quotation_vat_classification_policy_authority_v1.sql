create function public.quotation_vat_classification_policy_sha256_v1(p_policy jsonb)
returns text
language plpgsql
immutable
set search_path = public, extensions, pg_catalog
as $$
begin
  if not public.jsonb_has_exact_keys(p_policy, array[
    'applicability_predicate', 'approved_at', 'approved_by',
    'classification_code', 'classification_policy_id', 'customer_type',
    'effective_from', 'effective_until', 'jurisdiction', 'policy_family',
    'policy_version', 'predecessor_policy_id', 'required_evidence_schema',
    'source_allowlist', 'source_reference', 'source_sha256', 'status',
    'unsupported_outcomes', 'vat_decision_authority_id'
  ]) then
    raise exception using
      errcode = '22023',
      message = 'QUOTATION_VAT_CLASSIFICATION_POLICY_INVALID';
  end if;

  return encode(extensions.digest(convert_to(jsonb_build_object(
    'applicability_predicate', p_policy->'applicability_predicate',
    'approved_at', p_policy->'approved_at',
    'approved_by', p_policy->'approved_by',
    'classification_code', p_policy->'classification_code',
    'classification_policy_id', p_policy->'classification_policy_id',
    'customer_type', p_policy->'customer_type',
    'effective_from', p_policy->'effective_from',
    'effective_until', p_policy->'effective_until',
    'jurisdiction', p_policy->'jurisdiction',
    'policy_family', p_policy->'policy_family',
    'policy_version', p_policy->'policy_version',
    'predecessor_policy_id', p_policy->'predecessor_policy_id',
    'required_evidence_schema', p_policy->'required_evidence_schema',
    'source_allowlist', p_policy->'source_allowlist',
    'source_reference', p_policy->'source_reference',
    'source_sha256', p_policy->'source_sha256',
    'status', p_policy->'status',
    'unsupported_outcomes', p_policy->'unsupported_outcomes',
    'vat_decision_authority_id', p_policy->'vat_decision_authority_id'
  )::text, 'UTF8'), 'sha256'), 'hex');
end;
$$;

create table public.quotation_vat_classification_policies (
  classification_policy_id uuid primary key,
  policy_family text not null,
  policy_version text not null,
  jurisdiction text not null,
  customer_type text not null,
  classification_code text not null,
  applicability_predicate jsonb not null,
  required_evidence_schema jsonb not null,
  source_allowlist jsonb not null,
  unsupported_outcomes jsonb not null,
  effective_from date not null,
  effective_until date,
  vat_decision_authority_id uuid not null
    references public.quotation_vat_decision_authorities(vat_decision_authority_id),
  source_reference text not null,
  source_sha256 char(64) not null,
  approved_by text not null,
  approved_at timestamptz not null,
  policy_sha256 char(64) not null,
  predecessor_policy_id uuid
    references public.quotation_vat_classification_policies(classification_policy_id),
  status text not null check (status in ('DRAFT', 'APPROVED', 'RETIRED')),
  constraint quotation_vat_classification_policy_identity_valid check (
    nullif(btrim(policy_family), '') is not null
    and nullif(btrim(policy_version), '') is not null
    and nullif(btrim(jurisdiction), '') is not null
    and customer_type in ('business', 'individual')
    and nullif(btrim(classification_code), '') is not null
  ),
  constraint quotation_vat_classification_policy_effectivity_valid check (
    effective_until is null or effective_until >= effective_from
  ),
  constraint quotation_vat_classification_policy_source_valid check (
    nullif(btrim(source_reference), '') is not null
    and source_sha256 ~ '^[0-9a-f]{64}$'
    and nullif(btrim(approved_by), '') is not null
  ),
  constraint quotation_vat_classification_policy_documents_valid check (
    jsonb_typeof(applicability_predicate) = 'object'
    and jsonb_typeof(required_evidence_schema) = 'object'
    and jsonb_typeof(source_allowlist) = 'object'
    and jsonb_typeof(unsupported_outcomes) = 'object'
  ),
  constraint quotation_vat_classification_policy_sha256_valid check (
    policy_sha256 ~ '^[0-9a-f]{64}$'
    and policy_sha256 = public.quotation_vat_classification_policy_sha256_v1(
      to_jsonb(quotation_vat_classification_policies) - 'policy_sha256'
    )
  )
);

create unique index quotation_vat_classification_one_approved
on public.quotation_vat_classification_policies (
  policy_family, jurisdiction, customer_type
)
where status = 'APPROVED';

create function public.prevent_quotation_vat_classification_policy_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'QUOTATION_VAT_CLASSIFICATION_POLICY_IMMUTABLE';
end;
$$;

create trigger trg_quotation_vat_classification_policy_immutable
before update or delete on public.quotation_vat_classification_policies
for each row execute function public.prevent_quotation_vat_classification_policy_mutation_v1();

with authority as (
  select
    vat_decision_authority_id,
    authority_source_identifier,
    authority_sha256,
    approved_by,
    approved_at
  from public.quotation_vat_decision_authorities
  where vat_decision_authority_id = 'b1030000-0000-4000-8000-000000000001'
    and authority_family = 'LWS_OUTGOING_VAT'
    and applicability_code = 'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION_V1'
    and status = 'APPROVED'
), policy as (
  select
    'be110000-0000-4000-8000-000000000001'::uuid as classification_policy_id,
    'LWS_OUTGOING_VAT_CLASSIFICATION'::text as policy_family,
    '1.0.0'::text as policy_version,
    'BE'::text as jurisdiction,
    'business'::text as customer_type,
    'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION'::text as classification_code,
    jsonb_build_object(
      'billing_country_values', jsonb_build_array('BE', 'Belgie', 'België', 'Belgium'),
      'customer_type', 'business',
      'exclusions_status', 'REQUIRES_SECTION_20_PREREQUISITE_08',
      'transaction_characteristics_status', 'REQUIRES_SECTION_20_PREREQUISITE_08'
    ) as applicability_predicate,
    jsonb_build_object(
      'required', jsonb_build_array(
        'server_owned_transaction_characteristics',
        'server_owned_exclusion_evidence'
      ),
      'status', 'INCOMPLETE_REQUIRES_SECTION_20_PREREQUISITE_08'
    ) as required_evidence_schema,
    jsonb_build_object(
      'sources', '[]'::jsonb,
      'status', 'REQUIRES_SECTION_20_PREREQUISITE_08'
    ) as source_allowlist,
    jsonb_build_object(
      'conflicting_evidence', 'VAT_POLICY_UNSUPPORTED',
      'incomplete_transaction_evidence', 'VAT_CLASSIFICATION_REVIEW_REQUIRED',
      'individual', 'VAT_INDIVIDUAL_POLICY_REVIEW_REQUIRED',
      'non_be', 'VAT_POLICY_UNSUPPORTED'
    ) as unsupported_outcomes,
    '2026-08-08'::date as effective_from,
    null::date as effective_until,
    vat_decision_authority_id,
    authority_source_identifier as source_reference,
    rtrim(authority_sha256) as source_sha256,
    approved_by,
    approved_at,
    null::uuid as predecessor_policy_id,
    'APPROVED'::text as status
  from authority
)
insert into public.quotation_vat_classification_policies (
  classification_policy_id, policy_family, policy_version, jurisdiction,
  customer_type, classification_code, applicability_predicate,
  required_evidence_schema, source_allowlist, unsupported_outcomes,
  effective_from, effective_until, vat_decision_authority_id,
  source_reference, source_sha256, approved_by, approved_at, policy_sha256,
  predecessor_policy_id, status
)
select
  classification_policy_id, policy_family, policy_version, jurisdiction,
  customer_type, classification_code, applicability_predicate,
  required_evidence_schema, source_allowlist, unsupported_outcomes,
  effective_from, effective_until, vat_decision_authority_id,
  source_reference, source_sha256, approved_by, approved_at,
  public.quotation_vat_classification_policy_sha256_v1(to_jsonb(policy)),
  predecessor_policy_id, status
from policy;

do $$
begin
  if not exists (
    select 1
    from public.quotation_vat_classification_policies
    where classification_policy_id = 'be110000-0000-4000-8000-000000000001'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'QUOTATION_VAT_CLASSIFICATION_POLICY_AUTHORITY_REQUIRED';
  end if;
end;
$$;

alter table public.quotation_vat_transaction_classifications
  add column classification_policy_id uuid
    references public.quotation_vat_classification_policies(classification_policy_id),
  add column classification_policy_version text,
  add column classification_policy_sha256 char(64);

do $$
begin
  if exists (select 1 from public.quotation_vat_transaction_classifications) then
    raise exception using
      errcode = 'P0001',
      message = 'LEGACY_VAT_CLASSIFICATION_POLICY_BINDING_REQUIRED';
  end if;
end;
$$;

alter table public.quotation_vat_transaction_classifications
  add constraint quotation_vat_transaction_classification_policy_binding_valid check (
    (
      classification_policy_id is null
      and classification_policy_version is null
      and classification_policy_sha256 is null
    ) or (
      classification_policy_id is not null
      and nullif(btrim(classification_policy_version), '') is not null
      and classification_policy_sha256 ~ '^[0-9a-f]{64}$'
    )
  );

alter table public.quotation_vat_classification_policies enable row level security;
alter table public.quotation_vat_classification_policies force row level security;

revoke all privileges on table public.quotation_vat_classification_policies
from public, anon, authenticated, service_role;
grant select on table public.quotation_vat_classification_policies to service_role;

revoke all on function public.quotation_vat_classification_policy_sha256_v1(jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.quotation_vat_classification_policy_sha256_v1(jsonb)
to service_role;

revoke all on function public.prevent_quotation_vat_classification_policy_mutation_v1()
from public, anon, authenticated, service_role;

comment on table public.quotation_vat_classification_policies is
  'Immutable VAT classification-policy envelopes. The v1 business envelope remains non-auto-classifying until its required transaction evidence and source allowlist are approved.';

comment on constraint quotation_vat_transaction_classification_policy_binding_valid
on public.quotation_vat_transaction_classifications is
  'Transitional all-or-none policy binding. Task 2 hardens the recorder and resolver before bound evidence becomes authoritative.';