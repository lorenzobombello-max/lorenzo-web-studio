insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) values (
  'supplier-documents',
  'supplier-documents',
  false,
  10485760,
  array['application/pdf', 'image/png', 'image/jpeg']::text[]
);

create table public.supplier_documents (
  id uuid primary key default gen_random_uuid(),
  document_type text not null,
  supplier_name text not null,
  document_reference text,
  document_date date,
  original_file_name text not null,
  mime_type text not null,
  byte_count bigint not null,
  storage_bucket_id text not null default 'supplier-documents',
  storage_object_path text not null,
  sha256 char(64) not null,
  record_classification text not null default 'production',
  created_by_operator_id uuid not null references public.commercial_operators(operator_id),
  created_at timestamptz not null default clock_timestamp(),
  constraint supplier_documents_type_valid check (
    document_type in ('INVOICE', 'CREDIT_NOTE', 'RECEIPT', 'CONTRACT', 'OTHER')
  ),
  constraint supplier_documents_supplier_name_valid check (
    supplier_name = btrim(supplier_name)
    and length(supplier_name) between 1 and 200
  ),
  constraint supplier_documents_reference_valid check (
    document_reference is null
    or (
      document_reference = btrim(document_reference)
      and length(document_reference) between 1 and 200
    )
  ),
  constraint supplier_documents_file_name_valid check (
    original_file_name = btrim(original_file_name)
    and length(original_file_name) between 1 and 200
    and original_file_name !~ '[\\/]'
  ),
  constraint supplier_documents_mime_type_valid check (
    mime_type in ('application/pdf', 'image/png', 'image/jpeg')
  ),
  constraint supplier_documents_byte_count_valid check (
    byte_count between 1 and 10485760
  ),
  constraint supplier_documents_storage_bucket_valid check (
    storage_bucket_id = 'supplier-documents'
  ),
  constraint supplier_documents_sha256_valid check (
    sha256 ~ '^[0-9a-f]{64}$'
  ),
  constraint supplier_documents_storage_path_valid check (
    storage_object_path = 'documents/' || rtrim(sha256) || case mime_type
      when 'application/pdf' then '.pdf'
      when 'image/png' then '.png'
      when 'image/jpeg' then '.jpg'
    end
  ),
  constraint supplier_documents_record_classification_valid check (
    record_classification in ('production', 'internal_e2e')
  ),
  constraint supplier_documents_binary_unique unique (sha256),
  constraint supplier_documents_storage_object_unique unique (
    storage_bucket_id, storage_object_path
  )
);

create function public.prevent_supplier_document_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'SUPPLIER_DOCUMENT_IMMUTABLE';
end;
$$;

create trigger trg_supplier_documents_immutable
before update or delete on public.supplier_documents
for each row execute function public.prevent_supplier_document_mutation_v1();

alter table public.supplier_documents enable row level security;

create function public.create_supplier_document_v1(
  p_document_type text,
  p_supplier_name text,
  p_document_reference text,
  p_document_date date,
  p_original_file_name text,
  p_mime_type text,
  p_byte_count bigint,
  p_sha256 text,
  p_record_classification text default 'production'
)
returns uuid
language plpgsql
security definer
set search_path = public, storage, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_document_type text := upper(btrim(p_document_type));
  v_supplier_name text := btrim(p_supplier_name);
  v_document_reference text := nullif(btrim(p_document_reference), '');
  v_original_file_name text := btrim(p_original_file_name);
  v_mime_type text := lower(btrim(p_mime_type));
  v_sha256 text := btrim(p_sha256);
  v_extension text;
  v_storage_object_path text;
  v_storage_metadata jsonb;
  v_document_id uuid;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select *
  into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;

  if not found then
    raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR';
  end if;
  if v_operator.status = 'DISABLED' then
    raise exception using errcode = '42501', message = 'OPERATOR_DISABLED';
  end if;
  if v_operator.status = 'REVOKED' then
    raise exception using errcode = '42501', message = 'OPERATOR_REVOKED';
  end if;
  if v_operator.status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;
  if v_operator.role <> 'owner' then
    raise exception using errcode = '42501', message = 'SUPPLIER_DOCUMENT_OWNER_REQUIRED';
  end if;

  if v_document_type is null or v_document_type not in (
    'INVOICE', 'CREDIT_NOTE', 'RECEIPT', 'CONTRACT', 'OTHER'
  ) then
    raise exception using errcode = '22023', message = 'INVALID_SUPPLIER_DOCUMENT_TYPE';
  end if;
  if v_supplier_name is null or length(v_supplier_name) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'INVALID_SUPPLIER_DOCUMENT_SUPPLIER';
  end if;
  if v_document_reference is not null and length(v_document_reference) > 200 then
    raise exception using errcode = '22023', message = 'INVALID_SUPPLIER_DOCUMENT_REFERENCE';
  end if;
  if v_original_file_name is null
     or length(v_original_file_name) not between 1 and 200
     or v_original_file_name ~ '[\\/]' then
    raise exception using errcode = '22023', message = 'INVALID_SUPPLIER_DOCUMENT_FILE_NAME';
  end if;
  if v_mime_type is null
     or v_mime_type not in ('application/pdf', 'image/png', 'image/jpeg') then
    raise exception using errcode = '22023', message = 'INVALID_SUPPLIER_DOCUMENT_MIME_TYPE';
  end if;
  if p_byte_count is null or p_byte_count not between 1 and 10485760 then
    raise exception using errcode = '22023', message = 'INVALID_SUPPLIER_DOCUMENT_BYTE_COUNT';
  end if;
  if v_sha256 is null or v_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_SUPPLIER_DOCUMENT_SHA256';
  end if;
  if p_record_classification is null
     or p_record_classification not in ('production', 'internal_e2e') then
    raise exception using errcode = '22023', message = 'INVALID_SUPPLIER_DOCUMENT_CLASSIFICATION';
  end if;

  v_extension := case v_mime_type
    when 'application/pdf' then 'pdf'
    when 'image/png' then 'png'
    when 'image/jpeg' then 'jpg'
  end;
  v_storage_object_path := 'documents/' || v_sha256 || '.' || v_extension;

  select objects.metadata
  into v_storage_metadata
  from storage.objects as objects
  where objects.bucket_id = 'supplier-documents'
    and objects.name = v_storage_object_path;

  if not found then
    raise exception using errcode = 'P0001', message = 'SUPPLIER_DOCUMENT_OBJECT_NOT_FOUND';
  end if;
  if coalesce(v_storage_metadata->>'mimetype', '') <> v_mime_type
     or coalesce(v_storage_metadata->>'size', '') !~ '^[0-9]+$'
     or (v_storage_metadata->>'size')::bigint <> p_byte_count
     or coalesce(v_storage_metadata->>'sha256', '') <> v_sha256 then
    raise exception using errcode = 'P0001', message = 'SUPPLIER_DOCUMENT_OBJECT_METADATA_MISMATCH';
  end if;
  if exists (
    select 1 from public.supplier_documents as document
    where rtrim(document.sha256) = v_sha256
  ) then
    raise exception using errcode = '23505', message = 'SUPPLIER_DOCUMENT_BINARY_DUPLICATE';
  end if;

  begin
    insert into public.supplier_documents (
      document_type, supplier_name, document_reference, document_date,
      original_file_name, mime_type, byte_count, storage_bucket_id,
      storage_object_path, sha256, record_classification,
      created_by_operator_id
    ) values (
      v_document_type, v_supplier_name, v_document_reference, p_document_date,
      v_original_file_name, v_mime_type, p_byte_count, 'supplier-documents',
      v_storage_object_path, v_sha256, p_record_classification,
      v_operator.operator_id
    )
    returning id into v_document_id;
  exception when unique_violation then
    raise exception using errcode = '23505', message = 'SUPPLIER_DOCUMENT_BINARY_DUPLICATE';
  end;

  return v_document_id;
end;
$$;

revoke all privileges on table public.supplier_documents
from public, anon, authenticated, service_role;

revoke all on function public.prevent_supplier_document_mutation_v1()
from public, anon, authenticated, service_role;

revoke all on function public.create_supplier_document_v1(
  text, text, text, date, text, text, bigint, text, text
)
from public, anon, authenticated, service_role;

grant execute on function public.create_supplier_document_v1(
  text, text, text, date, text, text, bigint, text, text
)
to authenticated;

comment on table public.supplier_documents is
  'Immutable standalone supplier-document evidence bound to one private content-addressed Storage object. It is not expense, payment, VAT, recurring-cost or banking authority.';

comment on column public.supplier_documents.document_reference is
  'Optional supplier-provided document reference; not globally unique and not financial authority.';

comment on column public.supplier_documents.document_date is
  'Optional date stated by or associated with the supplier document; not an expense, due or payment date.';

comment on column public.supplier_documents.created_at is
  'Authoritative metadata registration time after the private Storage object and trusted integrity observations exist.';

comment on column public.supplier_documents.sha256 is
  'Trusted lowercase SHA-256 identity for the archived binary. One exact binary has one canonical supplier-document record.';

comment on function public.create_supplier_document_v1(
  text, text, text, date, text, text, bigint, text, text
) is
  'Owner-only registration boundary for existing private supplier-document objects with trusted MIME, byte-count and SHA-256 Storage metadata.';