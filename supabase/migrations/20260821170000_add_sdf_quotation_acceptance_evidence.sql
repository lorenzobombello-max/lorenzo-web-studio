create table public.sdf_quotation_documents (
  quotation_id uuid primary key references public.sdf_quotations(quotation_id),
  quotation_date date not null,
  valid_until date not null,
  prepared_at timestamptz not null,
  document_reference text not null,
  document_sha256 char(64) not null,
  constraint sdf_quotation_document_validity_valid
    check (valid_until >= quotation_date),
  constraint sdf_quotation_document_reference_valid
    check (
      nullif(btrim(document_reference), '') is not null
      and document_reference !~ '^[A-Za-z][A-Za-z0-9+.-]*://'
      and position('?' in document_reference) = 0
      and position('#' in document_reference) = 0
    ),
  constraint sdf_quotation_document_sha256_valid
    check (document_sha256 ~ '^[0-9a-f]{64}$')
);

create table public.sdf_quotation_acceptances (
  quotation_id uuid primary key references public.sdf_quotation_documents(quotation_id),
  accepted_at timestamptz not null,
  document_reference text not null,
  document_sha256 char(64) not null,
  constraint sdf_quotation_acceptance_reference_valid
    check (
      nullif(btrim(document_reference), '') is not null
      and document_reference !~ '^[A-Za-z][A-Za-z0-9+.-]*://'
      and position('?' in document_reference) = 0
      and position('#' in document_reference) = 0
    ),
  constraint sdf_quotation_acceptance_sha256_valid
    check (document_sha256 ~ '^[0-9a-f]{64}$')
);

comment on table public.sdf_quotation_documents is
  'Private immutable evidence for one prepared SDF quotation document. Stores dates, stable internal reference, and lowercase SHA-256 only; no status, pricing, delivery, activation, or recurring semantics.';

comment on table public.sdf_quotation_acceptances is
  'Private immutable evidence of one active SDF quotation acceptance. Requires existing SDF quotation document evidence and creates no downstream obligation or workflow.';

create function public.guard_sdf_quotation_document_evidence_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_request_kind text;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    raise exception using errcode = '55000', message = 'SDF_QUOTATION_EVIDENCE_IMMUTABLE';
  end if;

  select qr.request_kind into v_request_kind
  from public.sdf_quotations as quotation
  join public.quote_requests as qr on qr.id = quotation.quote_request_id
  where quotation.quotation_id = new.quotation_id;

  if not found then
    raise exception using errcode = '23503', message = 'SDF_QUOTATION_NOT_FOUND';
  end if;
  if v_request_kind <> 'slimme_documentenflow' then
    raise exception using errcode = '23514', message = 'SDF_QUOTATION_EVIDENCE_REQUIRES_SDF_APPLICATION';
  end if;
  return new;
end;
$$;

create function public.guard_sdf_quotation_acceptance_evidence_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_request_kind text;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    raise exception using errcode = '55000', message = 'SDF_QUOTATION_ACCEPTANCE_IMMUTABLE';
  end if;

  select qr.request_kind into v_request_kind
  from public.sdf_quotation_documents as document
  join public.sdf_quotations as quotation on quotation.quotation_id = document.quotation_id
  join public.quote_requests as qr on qr.id = quotation.quote_request_id
  where document.quotation_id = new.quotation_id;

  if not found then
    raise exception using errcode = '23503', message = 'SDF_QUOTATION_DOCUMENT_EVIDENCE_NOT_FOUND';
  end if;
  if v_request_kind <> 'slimme_documentenflow' then
    raise exception using errcode = '23514', message = 'SDF_QUOTATION_ACCEPTANCE_REQUIRES_SDF_APPLICATION';
  end if;
  return new;
end;
$$;

create trigger trg_sdf_quotation_documents_guard
before insert or update or delete on public.sdf_quotation_documents
for each row execute function public.guard_sdf_quotation_document_evidence_v1();

create trigger trg_sdf_quotation_acceptances_guard
before insert or update or delete on public.sdf_quotation_acceptances
for each row execute function public.guard_sdf_quotation_acceptance_evidence_v1();

alter table public.sdf_quotation_documents enable row level security;
alter table public.sdf_quotation_documents force row level security;
alter table public.sdf_quotation_acceptances enable row level security;
alter table public.sdf_quotation_acceptances force row level security;

revoke all privileges on table public.sdf_quotation_documents
from public, anon, authenticated, service_role;
revoke all privileges on table public.sdf_quotation_acceptances
from public, anon, authenticated, service_role;
revoke all on function public.guard_sdf_quotation_document_evidence_v1()
from public, anon, authenticated, service_role;
revoke all on function public.guard_sdf_quotation_acceptance_evidence_v1()
from public, anon, authenticated, service_role;

alter function public.get_operator_application_v1(uuid, text)
rename to get_operator_application_before_sdf_evidence_v1;

revoke all on function public.get_operator_application_before_sdf_evidence_v1(uuid, text)
from public, anon, authenticated, service_role;

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
  v_evidence jsonb;
begin
  v_result := public.get_operator_application_before_sdf_evidence_v1(
    p_quote_request_id,
    p_application_reference
  );

  if v_result->>'request_kind' <> 'slimme_documentenflow'
     or v_result->'sdf_quotation' = 'null'::jsonb then
    return v_result;
  end if;

  select jsonb_build_object(
    'document', case when document.quotation_id is null then null else jsonb_build_object(
      'quotation_date', document.quotation_date,
      'valid_until', document.valid_until,
      'prepared_at', document.prepared_at,
      'document_reference_present', nullif(btrim(document.document_reference), '') is not null,
      'document_sha256_present', document.document_sha256 is not null
    ) end,
    'acceptance', case when acceptance.quotation_id is null then null else jsonb_build_object(
      'accepted_at', acceptance.accepted_at,
      'accepted_document_reference_present', nullif(btrim(acceptance.document_reference), '') is not null,
      'accepted_document_sha256_present', acceptance.document_sha256 is not null
    ) end
  ) into v_evidence
  from public.sdf_quotations as quotation
  left join public.sdf_quotation_documents as document
    on document.quotation_id = quotation.quotation_id
  left join public.sdf_quotation_acceptances as acceptance
    on acceptance.quotation_id = document.quotation_id
  where quotation.quotation_id = (v_result->'sdf_quotation'->>'quotation_id')::uuid;

  return jsonb_set(
    v_result,
    '{sdf_quotation}',
    v_result->'sdf_quotation' || coalesce(v_evidence, '{"document":null,"acceptance":null}'::jsonb)
  );
end;
$$;

comment on function public.get_operator_application_v1(uuid, text) is
  'Owner/admin-only product-aware dossier. SDF quotation evidence exposes dates and presence flags only; hashes, storage references, generic status, pricing duplication, and lifecycle automation remain private or unavailable.';

revoke all on function public.get_operator_application_v1(uuid, text)
from public, anon, authenticated, service_role;
grant execute on function public.get_operator_application_v1(uuid, text)
to authenticated;