-- W2.4.1-PDF B1: persist the exact runtime-template identity used for new DOCX artifacts
-- and create immutable local PDF conversion-task bindings. This migration does not execute
-- conversion, publish a PDF view, or activate customer acceptance.

create table lws_internal.website_delivery_runtime_template_authorities (
  runtime_template_reference text not null,
  runtime_template_version text not null,
  runtime_template_sha256 char(64) not null check (runtime_template_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  primary key(runtime_template_reference, runtime_template_version, runtime_template_sha256)
);

insert into lws_internal.website_delivery_runtime_template_authorities(
  runtime_template_reference, runtime_template_version, runtime_template_sha256
) values (
  'LWS_WEBSITE_DELIVERY_DOCUMENT_OPL_W_01_v2.docx',
  'v2',
  '84f16839f584e6949c9fc6389d72894160e65fbf67746eb3bc0effb0d546706d'
);

create trigger trg_website_delivery_runtime_template_authorities_immutable
before update or delete on lws_internal.website_delivery_runtime_template_authorities
for each row execute function public.prevent_website_delivery_document_mutation_v1();

revoke all on table lws_internal.website_delivery_runtime_template_authorities
from public, anon, authenticated, service_role;

alter table public.website_delivery_document_artifacts
  add column runtime_template_reference text,
  add column runtime_template_version text,
  add column runtime_template_sha256 char(64),
  add constraint website_delivery_artifact_runtime_template_all_or_none check (
    (runtime_template_reference is null and runtime_template_version is null and runtime_template_sha256 is null)
    or
    (nullif(btrim(runtime_template_reference), '') is not null
      and nullif(btrim(runtime_template_version), '') is not null
      and runtime_template_sha256 ~ '^[0-9a-f]{64}$')
  ),
  add constraint website_delivery_artifact_runtime_template_authority foreign key(
    runtime_template_reference, runtime_template_version, runtime_template_sha256
  ) references lws_internal.website_delivery_runtime_template_authorities(
    runtime_template_reference, runtime_template_version, runtime_template_sha256
  ),
  add constraint website_delivery_artifact_task_binding_unique unique(
    artifact_id, candidate_id, project_id, preview_version_id, document_version,
    docx_sha256, runtime_template_reference, runtime_template_version, runtime_template_sha256
  );

alter table public.website_delivery_document_candidates
  add constraint website_delivery_candidate_task_binding_unique unique(
    candidate_id, project_id, preview_version_id, document_version,
    generation_payload_sha256, source_drive_file_id, source_sha256, statement_version
  );

create function public.register_website_delivery_document_artifact_v2(
  p_candidate_id uuid,
  p_docx_sha256 char(64),
  p_content_type text,
  p_docx_bytes bigint,
  p_runtime_template_reference text,
  p_runtime_template_version text,
  p_runtime_template_sha256 char(64),
  p_idempotency_key uuid,
  p_actor text
)
returns jsonb
language plpgsql
security definer
set search_path = public, storage, lws_internal, pg_catalog
as $$
declare
  v_candidate public.website_delivery_document_candidates%rowtype;
  v_existing public.website_delivery_document_artifacts%rowtype;
  v_artifact public.website_delivery_document_artifacts%rowtype;
  v_path text;
  v_metadata jsonb;
begin
  if p_candidate_id is null or p_idempotency_key is null
     or p_docx_sha256 !~ '^[0-9a-f]{64}$'
     or p_docx_bytes <= 0 or p_docx_bytes > 10485760
     or p_content_type <> 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
     or nullif(btrim(p_runtime_template_reference), '') is null
     or nullif(btrim(p_runtime_template_version), '') is null
     or p_runtime_template_sha256 !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_actor), '') is null then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_ARTIFACT_INPUT_INVALID';
  end if;
  if not exists (
    select 1 from lws_internal.website_delivery_runtime_template_authorities authority
    where authority.runtime_template_reference = btrim(p_runtime_template_reference)
      and authority.runtime_template_version = btrim(p_runtime_template_version)
      and authority.runtime_template_sha256 = p_runtime_template_sha256
  ) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_RUNTIME_TEMPLATE_INVALID';
  end if;

  select * into v_existing from public.website_delivery_document_artifacts
  where registration_idempotency_key = p_idempotency_key;
  if found then
    if v_existing.candidate_id <> p_candidate_id or v_existing.docx_sha256 <> p_docx_sha256
       or v_existing.docx_bytes <> p_docx_bytes or v_existing.content_type <> p_content_type
       or (v_existing.runtime_template_sha256 is not null and (
         v_existing.runtime_template_reference <> btrim(p_runtime_template_reference)
         or v_existing.runtime_template_version <> btrim(p_runtime_template_version)
         or v_existing.runtime_template_sha256 <> p_runtime_template_sha256
       )) then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'artifact_id', v_existing.artifact_id, 'storage_bucket_id', v_existing.storage_bucket_id,
      'storage_object_path', v_existing.storage_object_path, 'docx_sha256', rtrim(v_existing.docx_sha256),
      'docx_bytes', v_existing.docx_bytes, 'was_created', false
    );
  end if;

  select * into v_candidate from public.website_delivery_document_candidates
  where candidate_id = p_candidate_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_CANDIDATE_NOT_FOUND';
  end if;
  v_path := 'projects/' || v_candidate.project_id::text || '/versions/' ||
    v_candidate.document_version::text || '/' || p_docx_sha256 || '.docx';
  select metadata into v_metadata from storage.objects
  where bucket_id = 'website-delivery-documents' and name = v_path;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_OBJECT_NOT_FOUND';
  end if;
  if coalesce(v_metadata->>'mimetype', '') <> p_content_type
     or coalesce(v_metadata->>'size', '') !~ '^[0-9]+$'
     or (v_metadata->>'size')::bigint <> p_docx_bytes then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_OBJECT_METADATA_MISMATCH';
  end if;

  select * into v_existing from public.website_delivery_document_artifacts
  where candidate_id = p_candidate_id;
  if found then
    if v_existing.docx_sha256 <> p_docx_sha256 or v_existing.docx_bytes <> p_docx_bytes
       or v_existing.storage_object_path <> v_path
       or (v_existing.runtime_template_sha256 is not null and (
         v_existing.runtime_template_reference <> btrim(p_runtime_template_reference)
         or v_existing.runtime_template_version <> btrim(p_runtime_template_version)
         or v_existing.runtime_template_sha256 <> p_runtime_template_sha256
       )) then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_ARTIFACT_CONFLICT';
    end if;
    return jsonb_build_object(
      'artifact_id', v_existing.artifact_id, 'storage_bucket_id', v_existing.storage_bucket_id,
      'storage_object_path', v_existing.storage_object_path, 'docx_sha256', rtrim(v_existing.docx_sha256),
      'docx_bytes', v_existing.docx_bytes, 'was_created', false
    );
  end if;

  insert into public.website_delivery_document_artifacts(
    candidate_id, project_id, preview_version_id, document_version,
    storage_bucket_id, storage_object_path, content_type, docx_sha256, docx_bytes,
    runtime_template_reference, runtime_template_version, runtime_template_sha256,
    registration_idempotency_key, created_by
  ) values (
    v_candidate.candidate_id, v_candidate.project_id, v_candidate.preview_version_id,
    v_candidate.document_version, 'website-delivery-documents', v_path,
    p_content_type, p_docx_sha256, p_docx_bytes, btrim(p_runtime_template_reference),
    btrim(p_runtime_template_version), p_runtime_template_sha256, p_idempotency_key, btrim(p_actor)
  ) returning * into v_artifact;
  return jsonb_build_object(
    'artifact_id', v_artifact.artifact_id, 'storage_bucket_id', v_artifact.storage_bucket_id,
    'storage_object_path', v_artifact.storage_object_path, 'docx_sha256', rtrim(v_artifact.docx_sha256),
    'docx_bytes', v_artifact.docx_bytes, 'was_created', true
  );
end;
$$;

create table public.website_delivery_pdf_conversion_tasks (
  task_id uuid primary key default gen_random_uuid(),
  artifact_id uuid not null unique,
  candidate_id uuid not null,
  project_id uuid not null,
  preview_version_id uuid not null,
  document_version integer not null check (document_version > 0),
  source_docx_sha256 char(64) not null check (source_docx_sha256 ~ '^[0-9a-f]{64}$'),
  generation_payload_sha256 char(64) not null check (generation_payload_sha256 ~ '^[0-9a-f]{64}$'),
  source_drive_file_id text not null,
  source_sha256 char(64) not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  statement_version text not null,
  runtime_template_reference text not null,
  runtime_template_version text not null,
  runtime_template_sha256 char(64) not null check (runtime_template_sha256 ~ '^[0-9a-f]{64}$'),
  task_idempotency_key uuid not null unique,
  actor text not null check (nullif(btrim(actor), '') is not null),
  created_at timestamptz not null default clock_timestamp(),
  constraint website_delivery_pdf_task_artifact_binding foreign key(
    artifact_id, candidate_id, project_id, preview_version_id, document_version,
    source_docx_sha256, runtime_template_reference, runtime_template_version, runtime_template_sha256
  ) references public.website_delivery_document_artifacts(
    artifact_id, candidate_id, project_id, preview_version_id, document_version,
    docx_sha256, runtime_template_reference, runtime_template_version, runtime_template_sha256
  ),
  constraint website_delivery_pdf_task_candidate_binding foreign key(
    candidate_id, project_id, preview_version_id, document_version,
    generation_payload_sha256, source_drive_file_id, source_sha256, statement_version
  ) references public.website_delivery_document_candidates(
    candidate_id, project_id, preview_version_id, document_version,
    generation_payload_sha256, source_drive_file_id, source_sha256, statement_version
  )
);

create trigger trg_website_delivery_pdf_conversion_tasks_immutable
before update or delete on public.website_delivery_pdf_conversion_tasks
for each row execute function public.prevent_website_delivery_document_mutation_v1();

alter table public.website_delivery_pdf_conversion_tasks enable row level security;
alter table public.website_delivery_pdf_conversion_tasks force row level security;
revoke all on table public.website_delivery_pdf_conversion_tasks
from public, anon, authenticated, service_role;

create function public.create_website_delivery_pdf_conversion_task_v1(
  p_artifact_id uuid,
  p_expected_project_id uuid,
  p_expected_preview_version_id uuid,
  p_expected_document_version integer,
  p_expected_source_docx_sha256 char(64),
  p_expected_generation_payload_sha256 char(64),
  p_expected_runtime_template_sha256 char(64),
  p_idempotency_key uuid,
  p_actor text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_artifact public.website_delivery_document_artifacts%rowtype;
  v_candidate public.website_delivery_document_candidates%rowtype;
  v_existing public.website_delivery_pdf_conversion_tasks%rowtype;
  v_task public.website_delivery_pdf_conversion_tasks%rowtype;
  v_state text;
begin
  if p_artifact_id is null or p_expected_project_id is null
     or p_expected_preview_version_id is null or p_expected_document_version <= 0
     or p_expected_source_docx_sha256 !~ '^[0-9a-f]{64}$'
     or p_expected_generation_payload_sha256 !~ '^[0-9a-f]{64}$'
     or p_expected_runtime_template_sha256 !~ '^[0-9a-f]{64}$'
     or p_idempotency_key is null or nullif(btrim(p_actor), '') is null then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_PDF_TASK_INPUT_INVALID';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.website_delivery_pdf_conversion_tasks
  where task_idempotency_key = p_idempotency_key;
  if found then
    if v_existing.artifact_id <> p_artifact_id
       or v_existing.project_id <> p_expected_project_id
       or v_existing.preview_version_id <> p_expected_preview_version_id
       or v_existing.document_version <> p_expected_document_version
       or v_existing.source_docx_sha256 <> p_expected_source_docx_sha256
       or v_existing.generation_payload_sha256 <> p_expected_generation_payload_sha256
       or v_existing.runtime_template_sha256 <> p_expected_runtime_template_sha256 then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_TASK_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'task_id', v_existing.task_id, 'artifact_id', v_existing.artifact_id,
      'project_id', v_existing.project_id, 'preview_version_id', v_existing.preview_version_id,
      'document_version', v_existing.document_version,
      'source_docx_sha256', rtrim(v_existing.source_docx_sha256),
      'generation_payload_sha256', rtrim(v_existing.generation_payload_sha256),
      'runtime_template_sha256', rtrim(v_existing.runtime_template_sha256), 'was_created', false
    );
  end if;

  select * into v_artifact from public.website_delivery_document_artifacts
  where artifact_id = p_artifact_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_TASK_BINDING_INVALID';
  end if;
  select * into v_candidate from public.website_delivery_document_candidates
  where candidate_id = v_artifact.candidate_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_TASK_BINDING_INVALID';
  end if;
  if v_artifact.runtime_template_sha256 is null then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_RUNTIME_TEMPLATE_IDENTITY_MISSING';
  end if;
  if v_artifact.project_id <> p_expected_project_id
     or v_artifact.preview_version_id <> p_expected_preview_version_id
     or v_artifact.document_version <> p_expected_document_version
     or v_artifact.docx_sha256 <> p_expected_source_docx_sha256
     or v_candidate.generation_payload_sha256 <> p_expected_generation_payload_sha256
     or v_artifact.runtime_template_sha256 <> p_expected_runtime_template_sha256 then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_TASK_BINDING_INVALID';
  end if;

  select current_state into v_state from public.commercial_projects
  where project_id = v_artifact.project_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_TASK_BINDING_INVALID';
  end if;
  if exists (
    select 1 from public.website_delivery_document_acceptances acceptance
    where acceptance.project_id = v_artifact.project_id
  ) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_ALREADY_ACCEPTED';
  end if;
  if v_state <> 'M2_PAYMENT_RECEIVED' then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_STATE_INVALID';
  end if;
  if not exists (
    select 1 from public.preview_versions preview
    where preview.preview_version_id = v_artifact.preview_version_id
      and preview.project_id = v_artifact.project_id and preview.status = 'CURRENT'
  ) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_TASK_BINDING_INVALID';
  end if;
  select * into v_existing from public.website_delivery_pdf_conversion_tasks
  where artifact_id = p_artifact_id;
  if found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_TASK_IDEMPOTENCY_CONFLICT';
  end if;

  insert into public.website_delivery_pdf_conversion_tasks(
    artifact_id, candidate_id, project_id, preview_version_id, document_version,
    source_docx_sha256, generation_payload_sha256, source_drive_file_id, source_sha256,
    statement_version, runtime_template_reference, runtime_template_version,
    runtime_template_sha256, task_idempotency_key, actor
  ) values (
    v_artifact.artifact_id, v_artifact.candidate_id, v_artifact.project_id,
    v_artifact.preview_version_id, v_artifact.document_version, v_artifact.docx_sha256,
    v_candidate.generation_payload_sha256, v_candidate.source_drive_file_id,
    v_candidate.source_sha256, v_candidate.statement_version,
    v_artifact.runtime_template_reference, v_artifact.runtime_template_version,
    v_artifact.runtime_template_sha256, p_idempotency_key, btrim(p_actor)
  ) returning * into v_task;
  return jsonb_build_object(
    'task_id', v_task.task_id, 'artifact_id', v_task.artifact_id,
    'project_id', v_task.project_id, 'preview_version_id', v_task.preview_version_id,
    'document_version', v_task.document_version,
    'source_docx_sha256', rtrim(v_task.source_docx_sha256),
    'generation_payload_sha256', rtrim(v_task.generation_payload_sha256),
    'runtime_template_sha256', rtrim(v_task.runtime_template_sha256), 'was_created', true
  );
end;
$$;

revoke all on function public.register_website_delivery_document_artifact_v2(
  uuid,char,text,bigint,text,text,char,uuid,text
) from public, anon, authenticated, service_role;
grant execute on function public.register_website_delivery_document_artifact_v2(
  uuid,char,text,bigint,text,text,char,uuid,text
) to service_role;
revoke all on function public.create_website_delivery_pdf_conversion_task_v1(
  uuid,uuid,uuid,integer,char,char,char,uuid,text
) from public, anon, authenticated, service_role;
grant execute on function public.create_website_delivery_pdf_conversion_task_v1(
  uuid,uuid,uuid,integer,char,char,char,uuid,text
) to service_role;

comment on table public.website_delivery_pdf_conversion_tasks is
  'Immutable local B1 authority binding one registered DOCX artifact to one future PDF conversion. Contains no execution status.';
comment on function public.register_website_delivery_document_artifact_v2(
  uuid,char,text,bigint,text,text,char,uuid,text
) is 'Registers new DOCX evidence with the exact authorized runtime-template bytes attested by the renderer. Historical v1 artifacts remain NULL.';
comment on function public.create_website_delivery_pdf_conversion_task_v1(
  uuid,uuid,uuid,integer,char,char,char,uuid,text
) is 'Creates or resolves one immutable local conversion-task binding. Does not execute conversion or register a PDF view.';