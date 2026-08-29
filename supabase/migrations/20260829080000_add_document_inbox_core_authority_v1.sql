create table public.document_inbox_items (
  id uuid primary key default gen_random_uuid(),
  sha256 char(64) not null,
  storage_bucket_id text not null default 'supplier-documents',
  storage_object_path text not null,
  original_file_name text not null,
  mime_type text not null,
  byte_count bigint not null,
  source_type text not null,
  source_instance text,
  external_id text,
  received_at timestamptz not null default clock_timestamp(),
  lifecycle_status text not null default 'RECEIVED',
  revision bigint not null default 1,
  extraction_status text not null default 'NOT_RECORDED',
  extraction_provider text,
  extraction_version text,
  extracted_at timestamptz,
  extraction_error_code text,
  extraction_candidates jsonb not null default '{}'::jsonb,
  proposed_supplier_name text,
  proposed_document_type text,
  proposed_document_reference text,
  proposed_document_date date,
  proposed_amount_minor bigint,
  proposed_currency text,
  proposed_description text,
  proposed_category text,
  proposed_expense_date date,
  proposed_relation_type text,
  confirmed_supplier_name text,
  confirmed_document_type text,
  confirmed_document_reference text,
  confirmed_document_date date,
  confirmed_amount_minor bigint,
  confirmed_currency text,
  confirmed_description text,
  confirmed_category text,
  confirmed_expense_date date,
  confirmed_relation_type text,
  warnings jsonb not null default '[]'::jsonb,
  warnings_acknowledged boolean not null default false,
  processing_stage text,
  processing_error_code text,
  processing_attempts integer not null default 0,
  result_supplier_document_id uuid references public.supplier_documents(id) on delete restrict,
  result_business_expense_id uuid references public.business_expenses(id) on delete restrict,
  result_link_id uuid references public.business_expense_documents(id) on delete restrict,
  record_classification text not null default 'production',
  created_by_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  approved_by_operator_id uuid references public.commercial_operators(operator_id) on delete restrict,
  rejected_by_operator_id uuid references public.commercial_operators(operator_id) on delete restrict,
  approved_at timestamptz,
  processed_at timestamptz,
  rejected_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint document_inbox_items_sha256_valid check (sha256 ~ '^[0-9a-f]{64}$'),
  constraint document_inbox_items_binary_unique unique (sha256),
  constraint document_inbox_items_bucket_valid check (storage_bucket_id = 'supplier-documents'),
  constraint document_inbox_items_file_name_valid check (
    original_file_name = btrim(original_file_name)
    and length(original_file_name) between 1 and 200
    and original_file_name !~ '[\\/]'
  ),
  constraint document_inbox_items_mime_valid check (
    mime_type in ('application/pdf', 'image/png', 'image/jpeg')
  ),
  constraint document_inbox_items_byte_count_valid check (byte_count between 1 and 10485760),
  constraint document_inbox_items_storage_path_valid check (
    storage_object_path = 'documents/' || rtrim(sha256) || case mime_type
      when 'application/pdf' then '.pdf'
      when 'image/png' then '.png'
      when 'image/jpeg' then '.jpg'
    end
  ),
  constraint document_inbox_items_source_type_valid check (
    source_type = upper(btrim(source_type)) and source_type ~ '^[A-Z][A-Z0-9_]{0,63}$'
  ),
  constraint document_inbox_items_source_identity_valid check (
    (external_id is null and source_instance is null)
    or (
      external_id = btrim(external_id) and length(external_id) between 1 and 500
      and source_instance = btrim(source_instance) and length(source_instance) between 1 and 200
    )
  ),
  constraint document_inbox_items_lifecycle_valid check (
    lifecycle_status in ('RECEIVED', 'REVIEW_REQUIRED', 'APPROVED', 'PROCESSED', 'REJECTED')
  ),
  constraint document_inbox_items_revision_valid check (revision > 0),
  constraint document_inbox_items_extraction_status_valid check (
    extraction_status in ('NOT_RECORDED', 'SUCCEEDED', 'PARTIAL', 'ERROR')
  ),
  constraint document_inbox_items_extraction_metadata_valid check (
    jsonb_typeof(extraction_candidates) = 'object'
    and (extraction_provider is null or (extraction_provider = btrim(extraction_provider) and length(extraction_provider) between 1 and 100))
    and (extraction_version is null or (extraction_version = btrim(extraction_version) and length(extraction_version) between 1 and 100))
    and (extraction_error_code is null or (extraction_error_code = btrim(extraction_error_code) and length(extraction_error_code) between 1 and 100))
  ),
  constraint document_inbox_items_warnings_valid check (jsonb_typeof(warnings) = 'array'),
  constraint document_inbox_items_processing_metadata_valid check (
    processing_attempts >= 0
    and (processing_stage is null or processing_stage in ('EXPENSE', 'DOCUMENT', 'LINK'))
    and (processing_error_code is null or processing_error_code ~ '^[A-Z0-9_]{1,100}$')
  ),
  constraint document_inbox_items_classification_valid check (
    record_classification in ('production', 'internal_e2e')
  ),
  constraint document_inbox_items_proposed_type_valid check (
    proposed_document_type is null or proposed_document_type in ('INVOICE', 'CREDIT_NOTE', 'RECEIPT', 'CONTRACT', 'OTHER')
  ),
  constraint document_inbox_items_proposed_category_valid check (
    proposed_category is null or proposed_category in (
      'software', 'hosting', 'telecom', 'accounting', 'hardware',
      'marketing', 'insurance', 'education', 'office', 'transport', 'other'
    )
  ),
  constraint document_inbox_items_proposed_relation_valid check (
    proposed_relation_type is null or proposed_relation_type in ('INVOICE', 'CREDIT_NOTE', 'RECEIPT', 'CONTRACT', 'OTHER')
  ),
  constraint document_inbox_items_proposed_finance_valid check (
    (proposed_amount_minor is null or proposed_amount_minor > 0)
    and (proposed_currency is null or proposed_currency = 'EUR')
  ),
  constraint document_inbox_items_confirmed_type_valid check (
    confirmed_document_type is null or confirmed_document_type in ('INVOICE', 'CREDIT_NOTE', 'RECEIPT', 'CONTRACT', 'OTHER')
  ),
  constraint document_inbox_items_confirmed_category_valid check (
    confirmed_category is null or confirmed_category in (
      'software', 'hosting', 'telecom', 'accounting', 'hardware',
      'marketing', 'insurance', 'education', 'office', 'transport', 'other'
    )
  ),
  constraint document_inbox_items_confirmed_relation_valid check (
    confirmed_relation_type is null or confirmed_relation_type in ('INVOICE', 'CREDIT_NOTE', 'RECEIPT', 'CONTRACT', 'OTHER')
  ),
  constraint document_inbox_items_confirmed_finance_valid check (
    (confirmed_amount_minor is null or confirmed_amount_minor > 0)
    and (confirmed_currency is null or confirmed_currency = 'EUR')
  ),
  constraint document_inbox_items_result_state_valid check (
    (lifecycle_status = 'PROCESSED'
      and result_supplier_document_id is not null
      and result_business_expense_id is not null
      and result_link_id is not null
      and processed_at is not null)
    or (lifecycle_status <> 'PROCESSED'
      and result_supplier_document_id is null
      and result_business_expense_id is null
      and result_link_id is null
      and processed_at is null)
  ),
  constraint document_inbox_items_approval_state_valid check (
    (lifecycle_status in ('APPROVED', 'PROCESSED') and approved_at is not null and approved_by_operator_id is not null)
    or (lifecycle_status not in ('APPROVED', 'PROCESSED') and approved_at is null and approved_by_operator_id is null)
  ),
  constraint document_inbox_items_rejection_state_valid check (
    (lifecycle_status = 'REJECTED' and rejected_at is not null and rejected_by_operator_id is not null)
    or (lifecycle_status <> 'REJECTED' and rejected_at is null and rejected_by_operator_id is null)
  )
);

create unique index document_inbox_items_source_identity_unique
on public.document_inbox_items(source_type, source_instance, external_id)
where external_id is not null;

create index document_inbox_items_queue_idx
on public.document_inbox_items(record_classification, lifecycle_status, received_at desc, id desc);

create table public.document_inbox_events (
  id uuid primary key default gen_random_uuid(),
  inbox_item_id uuid not null references public.document_inbox_items(id) on delete restrict,
  event_type text not null,
  occurred_at timestamptz not null default clock_timestamp(),
  actor_user_id uuid,
  stage text,
  metadata jsonb not null default '{}'::jsonb,
  constraint document_inbox_events_type_valid check (
    event_type in (
      'RECEIVED', 'EXTRACTION_RECORDED', 'PROPOSAL_UPDATED', 'CONFIRMED',
      'APPROVED', 'REJECTED', 'PROCESSING_STARTED', 'PROCESSED', 'PROCESSING_ERROR'
    )
  ),
  constraint document_inbox_events_stage_valid check (
    stage is null or stage in ('RECEIVE', 'EXTRACTION', 'REVIEW', 'APPROVAL', 'EXPENSE', 'DOCUMENT', 'LINK')
  ),
  constraint document_inbox_events_metadata_valid check (jsonb_typeof(metadata) = 'object')
);

create index document_inbox_events_item_time_idx
on public.document_inbox_events(inbox_item_id, occurred_at, id);

alter table public.document_inbox_items enable row level security;
alter table public.document_inbox_events enable row level security;

create function public.prevent_document_inbox_event_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'DOCUMENT_INBOX_EVENT_IMMUTABLE';
end;
$$;

create trigger trg_document_inbox_events_immutable
before update or delete on public.document_inbox_events
for each row execute function public.prevent_document_inbox_event_mutation_v1();

create function public.guard_document_inbox_item_update_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if old.lifecycle_status in ('PROCESSED', 'REJECTED') then
    raise exception using errcode = '55000', message = 'DOCUMENT_INBOX_ITEM_TERMINAL';
  end if;
  if new.sha256 <> old.sha256
     or new.storage_bucket_id <> old.storage_bucket_id
     or new.storage_object_path <> old.storage_object_path
     or new.original_file_name <> old.original_file_name
     or new.mime_type <> old.mime_type
     or new.byte_count <> old.byte_count
     or new.source_type <> old.source_type
     or new.source_instance is distinct from old.source_instance
     or new.external_id is distinct from old.external_id
     or new.received_at <> old.received_at
     or new.record_classification <> old.record_classification
     or new.created_by_operator_id <> old.created_by_operator_id
     or new.created_at <> old.created_at then
    raise exception using errcode = '55000', message = 'DOCUMENT_INBOX_BINARY_IDENTITY_IMMUTABLE';
  end if;
  if new.revision <> old.revision + 1 then
    raise exception using errcode = '40001', message = 'DOCUMENT_INBOX_REVISION_REQUIRED';
  end if;
  if new.lifecycle_status <> old.lifecycle_status and not (
    (old.lifecycle_status = 'RECEIVED' and new.lifecycle_status in ('REVIEW_REQUIRED', 'REJECTED'))
    or (old.lifecycle_status = 'REVIEW_REQUIRED' and new.lifecycle_status in ('APPROVED', 'REJECTED'))
    or (old.lifecycle_status = 'APPROVED' and new.lifecycle_status = 'PROCESSED')
  ) then
    raise exception using errcode = '23514', message = 'INVALID_DOCUMENT_INBOX_TRANSITION';
  end if;
  return new;
end;
$$;

create trigger trg_document_inbox_items_guard
before update on public.document_inbox_items
for each row execute function public.guard_document_inbox_item_update_v1();

create function public.require_document_inbox_owner_v1()
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator from public.commercial_operators where auth_user_id = v_subject for share;
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status = 'DISABLED' then raise exception using errcode = '42501', message = 'OPERATOR_DISABLED'; end if;
  if v_operator.status = 'REVOKED' then raise exception using errcode = '42501', message = 'OPERATOR_REVOKED'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;
  if v_operator.role <> 'owner' then raise exception using errcode = '42501', message = 'DOCUMENT_INBOX_OWNER_REQUIRED'; end if;
  return v_operator.operator_id;
end;
$$;

create function public.receive_document_inbox_item_v1(
  p_sha256 text,
  p_original_file_name text,
  p_mime_type text,
  p_byte_count bigint,
  p_source_type text default 'MANUAL_UPLOAD',
  p_source_instance text default null,
  p_external_id text default null,
  p_record_classification text default 'production'
)
returns jsonb
language plpgsql
security definer
set search_path = public, storage, auth, pg_catalog
as $$
declare
  v_operator_id uuid := public.require_document_inbox_owner_v1();
  v_subject uuid := auth.uid();
  v_sha256 text := btrim(p_sha256);
  v_file_name text := btrim(p_original_file_name);
  v_mime_type text := lower(btrim(p_mime_type));
  v_source_type text := upper(btrim(p_source_type));
  v_source_instance text := nullif(btrim(p_source_instance), '');
  v_external_id text := nullif(btrim(p_external_id), '');
  v_path text;
  v_metadata jsonb;
  v_item public.document_inbox_items%rowtype;
begin
  if v_sha256 is null or v_sha256 !~ '^[0-9a-f]{64}$' then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_SHA256'; end if;
  if v_file_name is null or length(v_file_name) not between 1 and 200 or v_file_name ~ '[\\/]' then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_FILE_NAME'; end if;
  if v_mime_type not in ('application/pdf', 'image/png', 'image/jpeg') then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_MIME_TYPE'; end if;
  if p_byte_count is null or p_byte_count not between 1 and 10485760 then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_BYTE_COUNT'; end if;
  if v_source_type <> 'MANUAL_UPLOAD' then raise exception using errcode = '22023', message = 'DOCUMENT_INBOX_SOURCE_NOT_ENABLED'; end if;
  if (v_external_id is null) <> (v_source_instance is null) then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_SOURCE_IDENTITY'; end if;
  if v_source_instance is not null and length(v_source_instance) > 200 then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_SOURCE_IDENTITY'; end if;
  if v_external_id is not null and length(v_external_id) > 500 then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_SOURCE_IDENTITY'; end if;
  if p_record_classification not in ('production', 'internal_e2e') then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_CLASSIFICATION'; end if;

  v_path := 'documents/' || v_sha256 || case v_mime_type when 'application/pdf' then '.pdf' when 'image/png' then '.png' when 'image/jpeg' then '.jpg' end;
  select metadata into v_metadata from storage.objects where bucket_id = 'supplier-documents' and name = v_path;
  if not found then raise exception using errcode = 'P0001', message = 'DOCUMENT_INBOX_OBJECT_NOT_FOUND'; end if;
  if coalesce(v_metadata->>'mimetype', '') <> v_mime_type
     or coalesce(v_metadata->>'size', '') !~ '^[0-9]+$'
     or (v_metadata->>'size')::bigint <> p_byte_count
     or coalesce(v_metadata->>'sha256', '') <> v_sha256 then
    raise exception using errcode = 'P0001', message = 'DOCUMENT_INBOX_OBJECT_METADATA_MISMATCH';
  end if;

  select * into v_item from public.document_inbox_items where rtrim(sha256) = v_sha256 for update;
  if found then
    if v_item.storage_object_path <> v_path or v_item.mime_type <> v_mime_type
       or v_item.byte_count <> p_byte_count or v_item.record_classification <> p_record_classification then
      raise exception using errcode = 'P0001', message = 'DOCUMENT_INBOX_BINARY_IDENTITY_MISMATCH';
    end if;
    return jsonb_build_object('id', v_item.id, 'status', v_item.lifecycle_status, 'revision', v_item.revision, 'replayed', true);
  end if;

  if v_external_id is not null and exists (
    select 1 from public.document_inbox_items
    where source_type = v_source_type and source_instance = v_source_instance and external_id = v_external_id
  ) then raise exception using errcode = '23505', message = 'DOCUMENT_INBOX_SOURCE_REPLAY_CONFLICT'; end if;

  begin
    insert into public.document_inbox_items(
      sha256, storage_object_path, original_file_name, mime_type, byte_count,
      source_type, source_instance, external_id, record_classification, created_by_operator_id
    ) values (
      v_sha256, v_path, v_file_name, v_mime_type, p_byte_count,
      v_source_type, v_source_instance, v_external_id, p_record_classification, v_operator_id
    ) returning * into v_item;
  exception when unique_violation then
    select * into v_item from public.document_inbox_items where rtrim(sha256) = v_sha256;
    if not found then raise exception using errcode = '23505', message = 'DOCUMENT_INBOX_SOURCE_REPLAY_CONFLICT'; end if;
  end;
  insert into public.document_inbox_events(inbox_item_id, event_type, actor_user_id, stage, metadata)
  values (v_item.id, 'RECEIVED', v_subject, 'RECEIVE', jsonb_build_object('source_type', v_source_type));
  return jsonb_build_object('id', v_item.id, 'status', v_item.lifecycle_status, 'revision', v_item.revision, 'replayed', false);
end;
$$;

create function public.record_document_inbox_extraction_v1(
  p_inbox_item_id uuid,
  p_expected_revision bigint,
  p_extraction_status text,
  p_provider text,
  p_version text,
  p_candidates jsonb,
  p_error_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_operator_id uuid := public.require_document_inbox_owner_v1();
  v_subject uuid := auth.uid();
  v_item public.document_inbox_items%rowtype;
  v_status text := upper(btrim(p_extraction_status));
  v_provider text := nullif(btrim(p_provider), '');
  v_version text := nullif(btrim(p_version), '');
  v_error text := nullif(upper(btrim(p_error_code)), '');
begin
  select * into v_item from public.document_inbox_items where id = p_inbox_item_id for update;
  if not found then raise exception using errcode = 'P0001', message = 'DOCUMENT_INBOX_ITEM_NOT_FOUND'; end if;
  if v_item.lifecycle_status not in ('RECEIVED', 'REVIEW_REQUIRED') then raise exception using errcode = '23514', message = 'DOCUMENT_INBOX_NOT_REVIEWABLE'; end if;
  if v_item.revision <> p_expected_revision then raise exception using errcode = '40001', message = 'DOCUMENT_INBOX_REVISION_CONFLICT'; end if;
  if v_status not in ('SUCCEEDED', 'PARTIAL', 'ERROR') then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_EXTRACTION_STATUS'; end if;
  if p_candidates is null or jsonb_typeof(p_candidates) <> 'object' then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_EXTRACTION_CANDIDATES'; end if;
  if v_status in ('SUCCEEDED', 'PARTIAL') and (v_provider is null or v_version is null) then raise exception using errcode = '22023', message = 'DOCUMENT_INBOX_EXTRACTION_IDENTITY_REQUIRED'; end if;
  if v_status = 'ERROR' and v_error is null then raise exception using errcode = '22023', message = 'DOCUMENT_INBOX_EXTRACTION_ERROR_REQUIRED'; end if;
  update public.document_inbox_items set
    lifecycle_status = 'REVIEW_REQUIRED', revision = revision + 1,
    extraction_status = v_status, extraction_provider = v_provider, extraction_version = v_version,
    extracted_at = clock_timestamp(), extraction_error_code = v_error,
    extraction_candidates = p_candidates, updated_at = clock_timestamp()
  where id = v_item.id returning * into v_item;
  insert into public.document_inbox_events(inbox_item_id, event_type, actor_user_id, stage, metadata)
  values (v_item.id, 'EXTRACTION_RECORDED', v_subject, 'EXTRACTION', jsonb_build_object('status', v_status, 'provider', v_provider, 'version', v_version, 'error_code', v_error));
  return jsonb_build_object('id', v_item.id, 'status', v_item.lifecycle_status, 'revision', v_item.revision);
end;
$$;

create function public.update_document_inbox_proposal_v1(
  p_inbox_item_id uuid, p_expected_revision bigint,
  p_supplier_name text, p_document_type text, p_document_reference text, p_document_date date,
  p_amount_minor bigint, p_currency text, p_description text, p_category text,
  p_expense_date date, p_relation_type text, p_warnings jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_operator_id uuid := public.require_document_inbox_owner_v1();
  v_subject uuid := auth.uid();
  v_item public.document_inbox_items%rowtype;
  v_supplier text := nullif(btrim(p_supplier_name), '');
  v_type text := nullif(upper(btrim(p_document_type)), '');
  v_reference text := nullif(btrim(p_document_reference), '');
  v_currency text := nullif(upper(btrim(p_currency)), '');
  v_description text := nullif(btrim(p_description), '');
  v_category text := nullif(lower(btrim(p_category)), '');
  v_relation text := nullif(upper(btrim(p_relation_type)), '');
begin
  select * into v_item from public.document_inbox_items where id = p_inbox_item_id for update;
  if not found then raise exception using errcode = 'P0001', message = 'DOCUMENT_INBOX_ITEM_NOT_FOUND'; end if;
  if v_item.lifecycle_status not in ('RECEIVED', 'REVIEW_REQUIRED') then raise exception using errcode = '23514', message = 'DOCUMENT_INBOX_NOT_REVIEWABLE'; end if;
  if v_item.revision <> p_expected_revision then raise exception using errcode = '40001', message = 'DOCUMENT_INBOX_REVISION_CONFLICT'; end if;
  if v_supplier is not null and length(v_supplier) > 200 then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_SUPPLIER'; end if;
  if v_type is not null and v_type not in ('INVOICE','CREDIT_NOTE','RECEIPT','CONTRACT','OTHER') then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_DOCUMENT_TYPE'; end if;
  if v_reference is not null and length(v_reference) > 200 then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_REFERENCE'; end if;
  if p_amount_minor is not null and p_amount_minor <= 0 then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_AMOUNT'; end if;
  if v_currency is not null and v_currency <> 'EUR' then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_CURRENCY'; end if;
  if v_description is not null and length(v_description) > 1000 then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_DESCRIPTION'; end if;
  if v_category is not null and v_category not in ('software','hosting','telecom','accounting','hardware','marketing','insurance','education','office','transport','other') then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_CATEGORY'; end if;
  if v_relation is not null and v_relation not in ('INVOICE','CREDIT_NOTE','RECEIPT','CONTRACT','OTHER') then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_RELATION_TYPE'; end if;
  if p_warnings is null or jsonb_typeof(p_warnings) <> 'array' then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_WARNINGS'; end if;
  update public.document_inbox_items set
    lifecycle_status = 'REVIEW_REQUIRED', revision = revision + 1,
    proposed_supplier_name = v_supplier, proposed_document_type = v_type,
    proposed_document_reference = v_reference, proposed_document_date = p_document_date,
    proposed_amount_minor = p_amount_minor, proposed_currency = v_currency,
    proposed_description = v_description, proposed_category = v_category,
    proposed_expense_date = p_expense_date, proposed_relation_type = v_relation,
    warnings = p_warnings, warnings_acknowledged = false, updated_at = clock_timestamp()
  where id = v_item.id returning * into v_item;
  insert into public.document_inbox_events(inbox_item_id, event_type, actor_user_id, stage, metadata)
  values (v_item.id, 'PROPOSAL_UPDATED', v_subject, 'REVIEW', jsonb_build_object('warning_count', jsonb_array_length(p_warnings)));
  return jsonb_build_object('id', v_item.id, 'status', v_item.lifecycle_status, 'revision', v_item.revision);
end;
$$;

create function public.confirm_document_inbox_values_v1(
  p_inbox_item_id uuid, p_expected_revision bigint,
  p_supplier_name text, p_document_type text, p_document_reference text, p_document_date date,
  p_amount_minor bigint, p_currency text, p_description text, p_category text,
  p_expense_date date, p_relation_type text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_operator_id uuid := public.require_document_inbox_owner_v1();
  v_subject uuid := auth.uid();
  v_item public.document_inbox_items%rowtype;
  v_supplier text := btrim(p_supplier_name);
  v_type text := upper(btrim(p_document_type));
  v_reference text := nullif(btrim(p_document_reference), '');
  v_currency text := upper(btrim(p_currency));
  v_description text := btrim(p_description);
  v_category text := lower(btrim(p_category));
  v_relation text := upper(btrim(p_relation_type));
begin
  select * into v_item from public.document_inbox_items where id = p_inbox_item_id for update;
  if not found then raise exception using errcode = 'P0001', message = 'DOCUMENT_INBOX_ITEM_NOT_FOUND'; end if;
  if v_item.lifecycle_status <> 'REVIEW_REQUIRED' then raise exception using errcode = '23514', message = 'DOCUMENT_INBOX_NOT_CONFIRMABLE'; end if;
  if v_item.revision <> p_expected_revision then raise exception using errcode = '40001', message = 'DOCUMENT_INBOX_REVISION_CONFLICT'; end if;
  if v_supplier is null or length(v_supplier) not between 1 and 200 then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_SUPPLIER'; end if;
  if v_type is null or v_type not in ('INVOICE','CREDIT_NOTE','RECEIPT','CONTRACT','OTHER') then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_DOCUMENT_TYPE'; end if;
  if v_reference is not null and length(v_reference) > 200 then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_REFERENCE'; end if;
  if p_amount_minor is null or p_amount_minor <= 0 then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_AMOUNT'; end if;
  if v_currency is distinct from 'EUR' then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_CURRENCY'; end if;
  if v_description is null or length(v_description) not between 1 and 1000 then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_DESCRIPTION'; end if;
  if v_category is null or v_category not in ('software','hosting','telecom','accounting','hardware','marketing','insurance','education','office','transport','other') then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_CATEGORY'; end if;
  if p_expense_date is null then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_EXPENSE_DATE'; end if;
  if v_relation is null or v_relation not in ('INVOICE','CREDIT_NOTE','RECEIPT','CONTRACT','OTHER') then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_RELATION_TYPE'; end if;
  update public.document_inbox_items set
    revision = revision + 1,
    confirmed_supplier_name = v_supplier, confirmed_document_type = v_type,
    confirmed_document_reference = v_reference, confirmed_document_date = p_document_date,
    confirmed_amount_minor = p_amount_minor, confirmed_currency = v_currency,
    confirmed_description = v_description, confirmed_category = v_category,
    confirmed_expense_date = p_expense_date, confirmed_relation_type = v_relation,
    updated_at = clock_timestamp()
  where id = v_item.id returning * into v_item;
  insert into public.document_inbox_events(inbox_item_id, event_type, actor_user_id, stage, metadata)
  values (v_item.id, 'CONFIRMED', v_subject, 'REVIEW', '{}'::jsonb);
  return jsonb_build_object('id', v_item.id, 'status', v_item.lifecycle_status, 'revision', v_item.revision);
end;
$$;

create function public.approve_document_inbox_item_v1(
  p_inbox_item_id uuid, p_expected_revision bigint, p_acknowledge_warnings boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_operator_id uuid := public.require_document_inbox_owner_v1();
  v_subject uuid := auth.uid();
  v_item public.document_inbox_items%rowtype;
begin
  select * into v_item from public.document_inbox_items where id = p_inbox_item_id for update;
  if not found then raise exception using errcode = 'P0001', message = 'DOCUMENT_INBOX_ITEM_NOT_FOUND'; end if;
  if v_item.lifecycle_status <> 'REVIEW_REQUIRED' then raise exception using errcode = '23514', message = 'DOCUMENT_INBOX_NOT_APPROVABLE'; end if;
  if v_item.revision <> p_expected_revision then raise exception using errcode = '40001', message = 'DOCUMENT_INBOX_REVISION_CONFLICT'; end if;
  if v_item.confirmed_supplier_name is null or v_item.confirmed_document_type is null
     or v_item.confirmed_amount_minor is null or v_item.confirmed_currency is null
     or v_item.confirmed_description is null or v_item.confirmed_category is null
     or v_item.confirmed_expense_date is null or v_item.confirmed_relation_type is null then
    raise exception using errcode = '22023', message = 'DOCUMENT_INBOX_CONFIRMED_VALUES_REQUIRED';
  end if;
  if jsonb_array_length(v_item.warnings) > 0 and p_acknowledge_warnings is not true then
    raise exception using errcode = '22023', message = 'DOCUMENT_INBOX_WARNINGS_ACKNOWLEDGEMENT_REQUIRED';
  end if;
  update public.document_inbox_items set
    lifecycle_status = 'APPROVED', revision = revision + 1,
    warnings_acknowledged = p_acknowledge_warnings or jsonb_array_length(warnings) = 0,
    approved_by_operator_id = v_operator_id, approved_at = clock_timestamp(), updated_at = clock_timestamp()
  where id = v_item.id returning * into v_item;
  insert into public.document_inbox_events(inbox_item_id, event_type, actor_user_id, stage, metadata)
  values (v_item.id, 'APPROVED', v_subject, 'APPROVAL', jsonb_build_object('warnings_acknowledged', v_item.warnings_acknowledged));
  return jsonb_build_object('id', v_item.id, 'status', v_item.lifecycle_status, 'revision', v_item.revision);
end;
$$;

create function public.reject_document_inbox_item_v1(
  p_inbox_item_id uuid, p_expected_revision bigint, p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_operator_id uuid := public.require_document_inbox_owner_v1();
  v_subject uuid := auth.uid();
  v_item public.document_inbox_items%rowtype;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if v_reason is not null and length(v_reason) > 500 then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_REJECTION_REASON'; end if;
  select * into v_item from public.document_inbox_items where id = p_inbox_item_id for update;
  if not found then raise exception using errcode = 'P0001', message = 'DOCUMENT_INBOX_ITEM_NOT_FOUND'; end if;
  if v_item.lifecycle_status not in ('RECEIVED', 'REVIEW_REQUIRED') then raise exception using errcode = '23514', message = 'DOCUMENT_INBOX_NOT_REJECTABLE'; end if;
  if v_item.revision <> p_expected_revision then raise exception using errcode = '40001', message = 'DOCUMENT_INBOX_REVISION_CONFLICT'; end if;
  update public.document_inbox_items set lifecycle_status = 'REJECTED', revision = revision + 1,
    rejected_by_operator_id = v_operator_id, rejected_at = clock_timestamp(), updated_at = clock_timestamp()
  where id = v_item.id returning * into v_item;
  insert into public.document_inbox_events(inbox_item_id, event_type, actor_user_id, stage, metadata)
  values (v_item.id, 'REJECTED', v_subject, 'REVIEW', jsonb_build_object('reason', v_reason));
  return jsonb_build_object('id', v_item.id, 'status', v_item.lifecycle_status, 'revision', v_item.revision);
end;
$$;

create function public.process_document_inbox_item_v1(p_inbox_item_id uuid, p_expected_revision bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_operator_id uuid := public.require_document_inbox_owner_v1();
  v_subject uuid := auth.uid();
  v_item public.document_inbox_items%rowtype;
  v_expense_id uuid;
  v_document_id uuid;
  v_link_id uuid;
  v_stage text := 'EXPENSE';
  v_sqlstate text;
begin
  select * into v_item from public.document_inbox_items where id = p_inbox_item_id for update;
  if not found then raise exception using errcode = 'P0001', message = 'DOCUMENT_INBOX_ITEM_NOT_FOUND'; end if;
  if v_item.lifecycle_status = 'PROCESSED' then
    return jsonb_build_object('ok', true, 'id', v_item.id, 'status', v_item.lifecycle_status, 'revision', v_item.revision,
      'supplier_document_id', v_item.result_supplier_document_id, 'business_expense_id', v_item.result_business_expense_id,
      'link_id', v_item.result_link_id, 'replayed', true);
  end if;
  if v_item.lifecycle_status <> 'APPROVED' then raise exception using errcode = '23514', message = 'DOCUMENT_INBOX_NOT_PROCESSABLE'; end if;
  if v_item.revision <> p_expected_revision then raise exception using errcode = '40001', message = 'DOCUMENT_INBOX_REVISION_CONFLICT'; end if;

  insert into public.document_inbox_events(inbox_item_id, event_type, actor_user_id, stage, metadata)
  values (v_item.id, 'PROCESSING_STARTED', v_subject, 'APPROVAL', jsonb_build_object('attempt', v_item.processing_attempts + 1));

  begin
    v_stage := 'EXPENSE';
    v_expense_id := public.create_business_expense_v1(
      v_item.confirmed_supplier_name, v_item.confirmed_description, v_item.confirmed_category,
      v_item.confirmed_amount_minor, v_item.confirmed_currency, v_item.confirmed_expense_date,
      v_item.record_classification, 'DOCUMENT-INBOX:' || v_item.id::text
    );

    v_stage := 'DOCUMENT';
    select id into v_document_id from public.supplier_documents where rtrim(sha256) = rtrim(v_item.sha256) for share;
    if found then
      if (select record_classification from public.supplier_documents where id = v_document_id) <> v_item.record_classification then
        raise exception using errcode = 'P0001', message = 'DOCUMENT_INBOX_DOCUMENT_CLASSIFICATION_MISMATCH';
      end if;
    else
      begin
        v_document_id := public.create_supplier_document_v1(
          v_item.confirmed_document_type, v_item.confirmed_supplier_name,
          v_item.confirmed_document_reference, v_item.confirmed_document_date,
          v_item.original_file_name, v_item.mime_type, v_item.byte_count,
          rtrim(v_item.sha256), v_item.record_classification
        );
      exception when unique_violation then
        select id into v_document_id from public.supplier_documents
        where rtrim(sha256) = rtrim(v_item.sha256) and record_classification = v_item.record_classification for share;
        if not found then raise; end if;
      end;
    end if;

    v_stage := 'LINK';
    v_link_id := public.link_business_expense_document_v1(v_expense_id, v_document_id, v_item.confirmed_relation_type);

    update public.document_inbox_items set
      lifecycle_status = 'PROCESSED', revision = revision + 1,
      processing_stage = null, processing_error_code = null, processing_attempts = processing_attempts + 1,
      result_supplier_document_id = v_document_id, result_business_expense_id = v_expense_id,
      result_link_id = v_link_id, processed_at = clock_timestamp(), updated_at = clock_timestamp()
    where id = v_item.id returning * into v_item;
    insert into public.document_inbox_events(inbox_item_id, event_type, actor_user_id, stage, metadata)
    values (v_item.id, 'PROCESSED', v_subject, 'LINK', jsonb_build_object(
      'supplier_document_id', v_document_id, 'business_expense_id', v_expense_id, 'link_id', v_link_id
    ));
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate;
    update public.document_inbox_items set revision = revision + 1,
      processing_stage = v_stage, processing_error_code = 'PROCESSING_' || v_sqlstate,
      processing_attempts = processing_attempts + 1, updated_at = clock_timestamp()
    where id = v_item.id returning * into v_item;
    insert into public.document_inbox_events(inbox_item_id, event_type, actor_user_id, stage, metadata)
    values (v_item.id, 'PROCESSING_ERROR', v_subject, v_stage, jsonb_build_object('sqlstate', v_sqlstate));
    return jsonb_build_object('ok', false, 'id', v_item.id, 'status', v_item.lifecycle_status,
      'revision', v_item.revision, 'error_code', v_item.processing_error_code, 'stage', v_stage);
  end;

  return jsonb_build_object('ok', true, 'id', v_item.id, 'status', v_item.lifecycle_status, 'revision', v_item.revision,
    'supplier_document_id', v_document_id, 'business_expense_id', v_expense_id, 'link_id', v_link_id, 'replayed', false);
end;
$$;

create function public.get_document_inbox_v1(
  p_lifecycle_status text default null, p_record_classification text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_operator_id uuid := public.require_document_inbox_owner_v1();
  v_status text := nullif(upper(btrim(p_lifecycle_status)), '');
  v_result jsonb;
begin
  if v_status is not null and v_status not in ('RECEIVED','REVIEW_REQUIRED','APPROVED','PROCESSED','REJECTED') then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_STATUS'; end if;
  if p_record_classification not in ('production','internal_e2e') then raise exception using errcode = '22023', message = 'INVALID_DOCUMENT_INBOX_CLASSIFICATION'; end if;
  select jsonb_build_object('scope', 'document_inbox', 'items', coalesce(jsonb_agg(to_jsonb(item) - 'created_by_operator_id' - 'approved_by_operator_id' - 'rejected_by_operator_id' order by item.received_at desc, item.id desc), '[]'::jsonb))
  into v_result from public.document_inbox_items item
  where item.record_classification = p_record_classification and (v_status is null or item.lifecycle_status = v_status);
  return v_result;
end;
$$;

revoke all on table public.document_inbox_items from public, anon, authenticated, service_role;
revoke all on table public.document_inbox_events from public, anon, authenticated, service_role;
revoke all on function public.prevent_document_inbox_event_mutation_v1() from public, anon, authenticated, service_role;
revoke all on function public.guard_document_inbox_item_update_v1() from public, anon, authenticated, service_role;
revoke all on function public.require_document_inbox_owner_v1() from public, anon, authenticated, service_role;

revoke all on function public.receive_document_inbox_item_v1(text,text,text,bigint,text,text,text,text) from public, anon, authenticated, service_role;
revoke all on function public.record_document_inbox_extraction_v1(uuid,bigint,text,text,text,jsonb,text) from public, anon, authenticated, service_role;
revoke all on function public.update_document_inbox_proposal_v1(uuid,bigint,text,text,text,date,bigint,text,text,text,date,text,jsonb) from public, anon, authenticated, service_role;
revoke all on function public.confirm_document_inbox_values_v1(uuid,bigint,text,text,text,date,bigint,text,text,text,date,text) from public, anon, authenticated, service_role;
revoke all on function public.approve_document_inbox_item_v1(uuid,bigint,boolean) from public, anon, authenticated, service_role;
revoke all on function public.reject_document_inbox_item_v1(uuid,bigint,text) from public, anon, authenticated, service_role;
revoke all on function public.process_document_inbox_item_v1(uuid,bigint) from public, anon, authenticated, service_role;
revoke all on function public.get_document_inbox_v1(text,text) from public, anon, authenticated, service_role;

grant execute on function public.receive_document_inbox_item_v1(text,text,text,bigint,text,text,text,text) to authenticated;
grant execute on function public.record_document_inbox_extraction_v1(uuid,bigint,text,text,text,jsonb,text) to authenticated;
grant execute on function public.update_document_inbox_proposal_v1(uuid,bigint,text,text,text,date,bigint,text,text,text,date,text,jsonb) to authenticated;
grant execute on function public.confirm_document_inbox_values_v1(uuid,bigint,text,text,text,date,bigint,text,text,text,date,text) to authenticated;
grant execute on function public.approve_document_inbox_item_v1(uuid,bigint,boolean) to authenticated;
grant execute on function public.reject_document_inbox_item_v1(uuid,bigint,text) to authenticated;
grant execute on function public.process_document_inbox_item_v1(uuid,bigint) to authenticated;
grant execute on function public.get_document_inbox_v1(text,text) to authenticated;

comment on table public.document_inbox_items is
  'Owner-only pre-authority processing dossiers for validated canonical supplier-document objects; never expense or supplier-document authority.';
comment on table public.document_inbox_events is
  'Immutable audit ledger for Document Inbox receipt, review, approval, processing and retry outcomes.';
comment on function public.process_document_inbox_item_v1(uuid,bigint) is
  'Owner-only row-locked transaction coordinator that reuses existing expense, supplier-document and immutable link authorities.';