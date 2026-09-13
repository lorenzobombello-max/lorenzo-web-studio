create function public.vat_finance_projection_sha256_v1(p_projection jsonb)
returns text
language plpgsql
immutable
set search_path = public, extensions, pg_catalog
as $$
declare
  v_payload jsonb;
  v_sha256 text;
  v_supplied_sha256 text;
begin
  if p_projection is null or jsonb_typeof(p_projection) <> 'object' then
    raise exception using
      errcode = '22023',
      message = 'VAT_FINANCE_PROJECTION_INVALID';
  end if;

  v_supplied_sha256 := p_projection->>'source_sha256';
  v_payload := p_projection - 'source_sha256';
  if not public.jsonb_has_exact_keys(v_payload, array[
    'source_projection_id', 'projection_version', 'covered_from',
    'covered_through', 'currency', 'included_transaction_references',
    'excluded_transactions', 'pre_transaction_turnover_minor',
    'candidate_transaction_reference', 'candidate_transaction_minor',
    'governed_turnover_minor',
    'category_classification_authority_references',
    'ledger_source_watermark', 'generated_at'
  ]) or (p_projection ? 'source_sha256' and v_supplied_sha256 is null) then
    raise exception using
      errcode = '22023',
      message = 'VAT_FINANCE_PROJECTION_INVALID';
  end if;

  v_sha256 := encode(extensions.digest(convert_to(jsonb_build_object(
    'source_projection_id', v_payload->'source_projection_id',
    'projection_version', v_payload->'projection_version',
    'covered_from', v_payload->'covered_from',
    'covered_through', v_payload->'covered_through',
    'currency', v_payload->'currency',
    'included_transaction_references',
      v_payload->'included_transaction_references',
    'excluded_transactions', v_payload->'excluded_transactions',
    'pre_transaction_turnover_minor',
      v_payload->'pre_transaction_turnover_minor',
    'candidate_transaction_reference',
      v_payload->'candidate_transaction_reference',
    'candidate_transaction_minor', v_payload->'candidate_transaction_minor',
    'governed_turnover_minor', v_payload->'governed_turnover_minor',
    'category_classification_authority_references',
      v_payload->'category_classification_authority_references',
    'ledger_source_watermark', v_payload->'ledger_source_watermark',
    'generated_at', v_payload->'generated_at'
  )::text, 'UTF8'), 'sha256'), 'hex');

  if p_projection ? 'source_sha256'
     and (
       v_supplied_sha256 !~ '^[0-9a-f]{64}$'
       or v_supplied_sha256 <> v_sha256
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'VAT_FINANCE_PROJECTION_HASH_MISMATCH';
  end if;

  return v_sha256;
end;
$$;

create table public.vat_finance_projection_adapters (
  adapter_id uuid primary key,
  adapter_code text not null,
  adapter_version text not null,
  source_owner text not null,
  effective_from date not null,
  effective_until date,
  source_schema_sha256 char(64) not null,
  approval_reference text,
  approved_by text,
  approved_at timestamptz,
  predecessor_adapter_id uuid
    references public.vat_finance_projection_adapters(adapter_id)
    on delete restrict,
  status text not null check (status in ('DRAFT', 'APPROVED', 'RETIRED')),
  constraint vat_finance_projection_adapter_identity_valid check (
    nullif(btrim(adapter_code), '') is not null
    and nullif(btrim(adapter_version), '') is not null
    and nullif(btrim(source_owner), '') is not null
    and source_schema_sha256 ~ '^[0-9a-f]{64}$'
    and predecessor_adapter_id is distinct from adapter_id
  ),
  constraint vat_finance_projection_adapter_version_unique
    unique (adapter_code, adapter_version),
  constraint vat_finance_projection_adapter_effectivity_valid check (
    effective_until is null or effective_until >= effective_from
  ),
  constraint vat_finance_projection_adapter_approval_valid check (
    (
      status = 'DRAFT'
      and approval_reference is null
      and approved_by is null
      and approved_at is null
    ) or (
      status in ('APPROVED', 'RETIRED')
      and nullif(btrim(approval_reference), '') is not null
      and nullif(btrim(approved_by), '') is not null
      and approved_at is not null
    )
  )
);

create function lws_internal.prevent_vat_finance_projection_adapter_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'VAT_FINANCE_PROJECTION_ADAPTER_IMMUTABLE';
end;
$$;

create trigger trg_vat_finance_projection_adapter_immutable
before update or delete on public.vat_finance_projection_adapters
for each row execute function
  lws_internal.prevent_vat_finance_projection_adapter_mutation_v1();

create function public.get_finance_ledger_projection_v1(
  p_threshold_year integer,
  p_vat_decision_authority_id uuid,
  p_measurement_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_approved_adapter_count integer;
begin
  if p_threshold_year is null
     or p_vat_decision_authority_id is null
     or p_measurement_date is null
     or extract(year from p_measurement_date)::integer <> p_threshold_year then
    raise exception using
      errcode = '22023',
      message = 'VAT_FINANCE_PROJECTION_REQUEST_INVALID';
  end if;

  select count(*)::integer into v_approved_adapter_count
  from public.vat_finance_projection_adapters
  where status = 'APPROVED'
    and effective_from <= p_measurement_date
    and (effective_until is null or effective_until >= p_measurement_date);

  raise exception using
    errcode = 'P0001',
    message = 'VAT_FINANCE_SOURCE_UNAVAILABLE',
    detail = case
      when v_approved_adapter_count = 0 then 'NO_APPROVED_FINANCE_ADAPTER'
      when v_approved_adapter_count > 1 then 'AMBIGUOUS_FINANCE_ADAPTER'
      else 'APPROVED_FINANCE_ADAPTER_NOT_ACTIVATED'
    end;
end;
$$;

alter table public.vat_finance_projection_adapters enable row level security;
alter table public.vat_finance_projection_adapters force row level security;

revoke all privileges on table public.vat_finance_projection_adapters
from public, anon, authenticated, service_role;
revoke all on function public.vat_finance_projection_sha256_v1(jsonb)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.prevent_vat_finance_projection_adapter_mutation_v1()
from public, anon, authenticated, service_role;
revoke all on function public.get_finance_ledger_projection_v1(integer, uuid, date)
from public, anon, authenticated, service_role;

grant execute on function public.vat_finance_projection_sha256_v1(jsonb)
to service_role;
grant execute on function public.get_finance_ledger_projection_v1(integer, uuid, date)
to service_role;

comment on table public.vat_finance_projection_adapters is
  'Immutable Finance source adapter/version allowlist. No adapter is seeded until Finance and accounting governance decisions close.';
comment on function public.get_finance_ledger_projection_v1(integer, uuid, date) is
  'Service-only fail-closed Finance projection contract. It does not infer turnover from payment, invoice, obligation, or receipt tables.';