-- W2.4.1-PDF B2: secure execution transfer around the immutable B1 task.
-- This migration does not start a workflow or convert a document.

create table public.website_delivery_pdf_conversion_executions (
  execution_id uuid primary key default gen_random_uuid(),
  task_id uuid not null unique references public.website_delivery_pdf_conversion_tasks(task_id),
  workflow_repository text not null check (nullif(btrim(workflow_repository), '') is not null),
  workflow_repository_id text not null check (workflow_repository_id ~ '^[1-9][0-9]*$'),
  workflow_ref_name text not null check (nullif(btrim(workflow_ref_name), '') is not null),
  workflow_ref text not null check (nullif(btrim(workflow_ref), '') is not null),
  workflow_run_id text not null check (workflow_run_id ~ '^[1-9][0-9]*$'),
  claimed_by text not null check (nullif(btrim(claimed_by), '') is not null),
  claimed_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default (clock_timestamp() + interval '15 minutes'),
  completed_at timestamptz,
  view_derivative_id uuid unique references public.website_delivery_document_view_derivatives(view_derivative_id),
  pdf_sha256 char(64),
  pdf_bytes bigint,
  completion_idempotency_key uuid unique,
  completed_by text,
  constraint website_delivery_pdf_execution_completion_all_or_none check (
    (completed_at is null and view_derivative_id is null and pdf_sha256 is null and pdf_bytes is null
      and completion_idempotency_key is null and completed_by is null)
    or
    (completed_at is not null and view_derivative_id is not null
      and pdf_sha256 ~ '^[0-9a-f]{64}$' and pdf_bytes > 0 and pdf_bytes <= 10485760
      and completion_idempotency_key is not null and nullif(btrim(completed_by), '') is not null)
  ),
  check (expires_at > claimed_at)
);

create function public.guard_website_delivery_pdf_execution_mutation_v1()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_EXECUTION_IMMUTABLE';
  end if;
  if old.completed_at is not null
     or new.execution_id <> old.execution_id or new.task_id <> old.task_id
     or new.workflow_repository <> old.workflow_repository
     or new.workflow_repository_id <> old.workflow_repository_id
     or new.workflow_ref_name <> old.workflow_ref_name or new.workflow_ref <> old.workflow_ref
     or new.workflow_run_id <> old.workflow_run_id or new.claimed_by <> old.claimed_by
     or new.claimed_at <> old.claimed_at or new.expires_at <> old.expires_at
     or new.completed_at is null or new.view_derivative_id is null
     or new.pdf_sha256 is null or new.pdf_bytes is null
     or new.completion_idempotency_key is null or nullif(btrim(new.completed_by), '') is null then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_EXECUTION_IMMUTABLE';
  end if;
  return new;
end;
$$;

create trigger trg_website_delivery_pdf_conversion_executions_guard
before update or delete on public.website_delivery_pdf_conversion_executions
for each row execute function public.guard_website_delivery_pdf_execution_mutation_v1();

alter table public.website_delivery_pdf_conversion_executions enable row level security;
alter table public.website_delivery_pdf_conversion_executions force row level security;
revoke all on table public.website_delivery_pdf_conversion_executions from public, anon, authenticated, service_role;

create function public.claim_website_delivery_pdf_conversion_v1(
  p_task_id uuid,
  p_workflow_repository text,
  p_workflow_repository_id text,
  p_workflow_ref_name text,
  p_workflow_ref text,
  p_workflow_run_id text,
  p_actor text
) returns jsonb
language plpgsql security definer set search_path = public, storage, pg_catalog as $$
declare
  v_task public.website_delivery_pdf_conversion_tasks%rowtype;
  v_artifact public.website_delivery_document_artifacts%rowtype;
  v_candidate public.website_delivery_document_candidates%rowtype;
  v_execution public.website_delivery_pdf_conversion_executions%rowtype;
  v_metadata jsonb;
  v_state text;
begin
  if p_task_id is null or nullif(btrim(p_workflow_repository), '') is null
     or p_workflow_repository_id !~ '^[1-9][0-9]*$'
     or nullif(btrim(p_workflow_ref_name), '') is null or nullif(btrim(p_workflow_ref), '') is null
     or p_workflow_run_id !~ '^[1-9][0-9]*$' or nullif(btrim(p_actor), '') is null then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_PDF_CLAIM_INPUT_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_task_id::text, 0));
  select * into v_task from public.website_delivery_pdf_conversion_tasks where task_id = p_task_id;
  if not found then raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_TASK_NOT_FOUND'; end if;
  select * into v_artifact from public.website_delivery_document_artifacts where artifact_id = v_task.artifact_id;
  select * into v_candidate from public.website_delivery_document_candidates where candidate_id = v_task.candidate_id;
  if v_artifact.artifact_id is null or v_candidate.candidate_id is null
     or v_artifact.docx_sha256 <> v_task.source_docx_sha256
     or v_candidate.generation_payload_sha256 <> v_task.generation_payload_sha256 then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_SOURCE_STALE';
  end if;
  select current_state into v_state from public.commercial_projects where project_id = v_task.project_id for update;
  if v_state <> 'M2_PAYMENT_RECEIVED' then raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_STATE_INVALID'; end if;
  if exists (select 1 from public.website_delivery_document_acceptances where project_id = v_task.project_id) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_ALREADY_ACCEPTED';
  end if;
  if not exists (select 1 from public.preview_versions where preview_version_id = v_task.preview_version_id and project_id = v_task.project_id and status = 'CURRENT') then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_SOURCE_STALE';
  end if;
  if exists (select 1 from public.website_delivery_document_view_derivatives where artifact_id = v_task.artifact_id) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_VIEW_ALREADY_REGISTERED';
  end if;
  select metadata into v_metadata from storage.objects where bucket_id = v_artifact.storage_bucket_id and name = v_artifact.storage_object_path;
  if not found or coalesce(v_metadata->>'mimetype','') <> v_artifact.content_type
     or coalesce(v_metadata->>'size','') !~ '^[0-9]+$' or (v_metadata->>'size')::bigint <> v_artifact.docx_bytes then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_SOURCE_OBJECT_INVALID';
  end if;
  select * into v_execution from public.website_delivery_pdf_conversion_executions where task_id = p_task_id;
  if found then
    if v_execution.workflow_repository <> btrim(p_workflow_repository)
       or v_execution.workflow_repository_id <> p_workflow_repository_id
       or v_execution.workflow_ref_name <> btrim(p_workflow_ref_name)
       or v_execution.workflow_ref <> btrim(p_workflow_ref)
       or v_execution.workflow_run_id <> p_workflow_run_id then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_CLAIM_CONFLICT';
    end if;
  else
    insert into public.website_delivery_pdf_conversion_executions(task_id,workflow_repository,workflow_repository_id,workflow_ref_name,workflow_ref,workflow_run_id,claimed_by)
    values (p_task_id,btrim(p_workflow_repository),p_workflow_repository_id,btrim(p_workflow_ref_name),btrim(p_workflow_ref),p_workflow_run_id,btrim(p_actor)) returning * into v_execution;
  end if;
  return jsonb_build_object(
    'execution_id',v_execution.execution_id,'task_id',v_task.task_id,'artifact_id',v_task.artifact_id,
    'project_id',v_task.project_id,'preview_version_id',v_task.preview_version_id,'document_version',v_task.document_version,
    'source_bucket_id',v_artifact.storage_bucket_id,'source_object_path',v_artifact.storage_object_path,
    'source_docx_sha256',rtrim(v_task.source_docx_sha256),'source_docx_bytes',v_artifact.docx_bytes,
    'generation_payload_sha256',rtrim(v_task.generation_payload_sha256),'generation_payload',v_candidate.generation_payload,
    'expires_at',v_execution.expires_at,'was_created',v_execution.claimed_at = v_execution.claimed_at
  );
end;
$$;

create function public.complete_website_delivery_pdf_conversion_v1(
  p_execution_id uuid,
  p_workflow_run_id text,
  p_pdf_sha256 char(64),
  p_pdf_bytes bigint,
  p_idempotency_key uuid,
  p_actor text
) returns jsonb
language plpgsql security definer set search_path = public, pg_catalog as $$
declare
  v_execution public.website_delivery_pdf_conversion_executions%rowtype;
  v_task public.website_delivery_pdf_conversion_tasks%rowtype;
  v_view jsonb;
  v_state text;
begin
  if p_execution_id is null or p_workflow_run_id !~ '^[1-9][0-9]*$'
     or p_pdf_sha256 !~ '^[0-9a-f]{64}$' or p_pdf_bytes <= 0 or p_pdf_bytes > 10485760
     or p_idempotency_key is null or nullif(btrim(p_actor), '') is null then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_PDF_COMPLETE_INPUT_INVALID';
  end if;
  select * into v_execution from public.website_delivery_pdf_conversion_executions where execution_id = p_execution_id for update;
  if not found or v_execution.workflow_run_id <> p_workflow_run_id then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_EXECUTION_BINDING_INVALID';
  end if;
  select * into v_task from public.website_delivery_pdf_conversion_tasks where task_id = v_execution.task_id;
  select current_state into v_state from public.commercial_projects where project_id = v_task.project_id for update;
  if v_state <> 'M2_PAYMENT_RECEIVED' then raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_STATE_INVALID'; end if;
  if exists (select 1 from public.website_delivery_document_acceptances where project_id = v_task.project_id) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_ALREADY_ACCEPTED';
  end if;
  if not exists (select 1 from public.preview_versions where preview_version_id = v_task.preview_version_id and project_id = v_task.project_id and status = 'CURRENT') then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_SOURCE_STALE';
  end if;
  if v_execution.completed_at is not null then
    if v_execution.pdf_sha256 <> p_pdf_sha256 or v_execution.pdf_bytes <> p_pdf_bytes
       or v_execution.completion_idempotency_key <> p_idempotency_key then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_COMPLETION_CONFLICT';
    end if;
    select jsonb_build_object('execution_id',v_execution.execution_id,'view_derivative_id',view_derivative_id,'pdf_sha256',rtrim(pdf_sha256),'pdf_bytes',pdf_bytes,'was_created',false)
    into v_view from public.website_delivery_document_view_derivatives where view_derivative_id = v_execution.view_derivative_id;
    return v_view;
  end if;
  if v_execution.expires_at <= clock_timestamp() then raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_EXECUTION_EXPIRED'; end if;
  v_view := public.register_website_delivery_document_view_v1(v_task.artifact_id,rtrim(p_pdf_sha256),p_pdf_bytes,'application/pdf',p_idempotency_key,btrim(p_actor));
  update public.website_delivery_pdf_conversion_executions set completed_at=clock_timestamp(),view_derivative_id=(v_view->>'view_derivative_id')::uuid,pdf_sha256=p_pdf_sha256,pdf_bytes=p_pdf_bytes,completion_idempotency_key=p_idempotency_key,completed_by=btrim(p_actor)
  where execution_id=p_execution_id returning * into v_execution;
  return jsonb_build_object('execution_id',v_execution.execution_id,'view_derivative_id',v_execution.view_derivative_id,'pdf_sha256',rtrim(v_execution.pdf_sha256),'pdf_bytes',v_execution.pdf_bytes,'was_created',true);
end;
$$;

revoke all on function public.guard_website_delivery_pdf_execution_mutation_v1() from public, anon, authenticated, service_role;
revoke all on function public.claim_website_delivery_pdf_conversion_v1(uuid,text,text,text,text,text,text) from public, anon, authenticated, service_role;
grant execute on function public.claim_website_delivery_pdf_conversion_v1(uuid,text,text,text,text,text,text) to service_role;
revoke all on function public.complete_website_delivery_pdf_conversion_v1(uuid,text,char,bigint,uuid,text) from public, anon, authenticated, service_role;
grant execute on function public.complete_website_delivery_pdf_conversion_v1(uuid,text,char,bigint,uuid,text) to service_role;

comment on table public.website_delivery_pdf_conversion_executions is 'B2 run-bound execution state separate from immutable B1 conversion-task authority.';
comment on function public.claim_website_delivery_pdf_conversion_v1(uuid,text,text,text,text,text,text) is 'Claims one exact B1 task for one verified workflow run and resolves source and generation data server-side.';
comment on function public.complete_website_delivery_pdf_conversion_v1(uuid,text,char,bigint,uuid,text) is 'Atomically records a storage-readback-verified PDF as the single registered view for the claimed artifact.';