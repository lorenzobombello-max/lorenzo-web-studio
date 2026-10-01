-- W2.4.1-PDF B1-B3 review repair: recover an incomplete expired conversion execution.
-- No document, task, artifact, view or hash binding is replaced by this lease takeover.

alter table public.website_delivery_pdf_conversion_executions
  add column workflow_run_attempt integer not null default 1
  check (workflow_run_attempt > 0);

create or replace function public.guard_website_delivery_pdf_execution_mutation_v1()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  if tg_op = 'DELETE' or old.completed_at is not null then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_EXECUTION_IMMUTABLE';
  end if;

  if new.execution_id = old.execution_id
     and new.task_id = old.task_id
     and new.workflow_repository = old.workflow_repository
     and new.workflow_repository_id = old.workflow_repository_id
     and new.workflow_ref_name = old.workflow_ref_name
     and new.workflow_ref = old.workflow_ref
     and new.workflow_run_id = old.workflow_run_id
     and new.workflow_run_attempt = old.workflow_run_attempt
     and new.claimed_by = old.claimed_by
     and new.claimed_at = old.claimed_at
     and new.expires_at = old.expires_at
     and new.completed_at is not null
     and new.view_derivative_id is not null
     and new.pdf_sha256 is not null
     and new.pdf_bytes is not null
     and new.completion_idempotency_key is not null
     and nullif(btrim(new.completed_by), '') is not null then
    return new;
  end if;

  if old.expires_at <= clock_timestamp()
     and new.execution_id <> old.execution_id
     and new.task_id = old.task_id
     and new.workflow_repository = old.workflow_repository
     and new.workflow_repository_id = old.workflow_repository_id
     and new.workflow_ref_name = old.workflow_ref_name
     and new.workflow_ref = old.workflow_ref
     and (
       new.workflow_run_id::numeric > old.workflow_run_id::numeric
       or (
         new.workflow_run_id = old.workflow_run_id
         and new.workflow_run_attempt > old.workflow_run_attempt
       )
     )
     and nullif(btrim(new.claimed_by), '') is not null
     and new.claimed_at >= old.expires_at
     and new.expires_at > new.claimed_at
     and new.completed_at is null
     and new.view_derivative_id is null
     and new.pdf_sha256 is null
     and new.pdf_bytes is null
     and new.completion_idempotency_key is null
     and new.completed_by is null then
    return new;
  end if;

  raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_EXECUTION_IMMUTABLE';
end;
$$;

create function public.claim_website_delivery_pdf_conversion_v2(
  p_task_id uuid,
  p_workflow_repository text,
  p_workflow_repository_id text,
  p_workflow_ref_name text,
  p_workflow_ref text,
  p_workflow_run_id text,
  p_workflow_run_attempt integer,
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
  v_was_created boolean := false;
  v_was_recovered boolean := false;
begin
  if p_task_id is null or nullif(btrim(p_workflow_repository), '') is null
     or p_workflow_repository_id !~ '^[1-9][0-9]*$'
     or nullif(btrim(p_workflow_ref_name), '') is null or nullif(btrim(p_workflow_ref), '') is null
     or p_workflow_run_id !~ '^[1-9][0-9]*$'
     or p_workflow_run_attempt is null or p_workflow_run_attempt <= 0
     or nullif(btrim(p_actor), '') is null then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_PDF_CLAIM_INPUT_INVALID';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_task_id::text, 0));
  select * into v_task from public.website_delivery_pdf_conversion_tasks where task_id = p_task_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_TASK_NOT_FOUND';
  end if;
  select * into v_artifact from public.website_delivery_document_artifacts where artifact_id = v_task.artifact_id;
  select * into v_candidate from public.website_delivery_document_candidates where candidate_id = v_task.candidate_id;
  if v_artifact.artifact_id is null or v_candidate.candidate_id is null
     or v_artifact.docx_sha256 <> v_task.source_docx_sha256
     or v_candidate.generation_payload_sha256 <> v_task.generation_payload_sha256 then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_SOURCE_STALE';
  end if;

  select current_state into v_state
  from public.commercial_projects where project_id = v_task.project_id for update;
  if v_state <> 'M2_PAYMENT_RECEIVED' then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_STATE_INVALID';
  end if;
  if exists (select 1 from public.website_delivery_document_acceptances where project_id = v_task.project_id) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_ALREADY_ACCEPTED';
  end if;
  if not exists (
    select 1 from public.preview_versions
    where preview_version_id = v_task.preview_version_id
      and project_id = v_task.project_id and status = 'CURRENT'
  ) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_SOURCE_STALE';
  end if;
  if exists (
    select 1 from public.website_delivery_document_view_derivatives where artifact_id = v_task.artifact_id
  ) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_VIEW_ALREADY_REGISTERED';
  end if;

  select metadata into v_metadata
  from storage.objects
  where bucket_id = v_artifact.storage_bucket_id and name = v_artifact.storage_object_path;
  if not found or coalesce(v_metadata->>'mimetype', '') <> v_artifact.content_type
     or coalesce(v_metadata->>'size', '') !~ '^[0-9]+$'
     or (v_metadata->>'size')::bigint <> v_artifact.docx_bytes then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_SOURCE_OBJECT_INVALID';
  end if;

  select * into v_execution
  from public.website_delivery_pdf_conversion_executions
  where task_id = p_task_id;
  if not found then
    insert into public.website_delivery_pdf_conversion_executions(
      task_id, workflow_repository, workflow_repository_id, workflow_ref_name,
      workflow_ref, workflow_run_id, workflow_run_attempt, claimed_by
    ) values (
      p_task_id, btrim(p_workflow_repository), p_workflow_repository_id, btrim(p_workflow_ref_name),
      btrim(p_workflow_ref), p_workflow_run_id, p_workflow_run_attempt, btrim(p_actor)
    ) returning * into v_execution;
    v_was_created := true;
  else
    if v_execution.workflow_repository <> btrim(p_workflow_repository)
       or v_execution.workflow_repository_id <> p_workflow_repository_id
       or v_execution.workflow_ref_name <> btrim(p_workflow_ref_name)
       or v_execution.workflow_ref <> btrim(p_workflow_ref) then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_CLAIM_CONFLICT';
    end if;

    if v_execution.workflow_run_id = p_workflow_run_id
       and v_execution.workflow_run_attempt = p_workflow_run_attempt then
      if v_execution.expires_at <= clock_timestamp() then
        raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_EXECUTION_EXPIRED';
      end if;
    else
      if v_execution.expires_at > clock_timestamp() then
        raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_CLAIM_CONFLICT';
      end if;
      if p_workflow_run_id::numeric < v_execution.workflow_run_id::numeric
         or (
           p_workflow_run_id = v_execution.workflow_run_id
           and p_workflow_run_attempt <= v_execution.workflow_run_attempt
         ) then
        raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_CLAIM_STALE';
      end if;
      update public.website_delivery_pdf_conversion_executions
      set execution_id = gen_random_uuid(),
          workflow_run_id = p_workflow_run_id,
          workflow_run_attempt = p_workflow_run_attempt,
          claimed_by = btrim(p_actor),
          claimed_at = clock_timestamp(),
          expires_at = clock_timestamp() + interval '15 minutes'
      where task_id = p_task_id
      returning * into v_execution;
      v_was_created := true;
      v_was_recovered := true;
    end if;
  end if;

  return jsonb_build_object(
    'execution_id', v_execution.execution_id,
    'task_id', v_task.task_id,
    'artifact_id', v_task.artifact_id,
    'project_id', v_task.project_id,
    'preview_version_id', v_task.preview_version_id,
    'document_version', v_task.document_version,
    'source_bucket_id', v_artifact.storage_bucket_id,
    'source_object_path', v_artifact.storage_object_path,
    'source_docx_sha256', rtrim(v_task.source_docx_sha256),
    'source_docx_bytes', v_artifact.docx_bytes,
    'generation_payload_sha256', rtrim(v_task.generation_payload_sha256),
    'generation_payload', v_candidate.generation_payload,
    'workflow_run_id', v_execution.workflow_run_id,
    'workflow_run_attempt', v_execution.workflow_run_attempt,
    'expires_at', v_execution.expires_at,
    'was_created', v_was_created,
    'was_recovered', v_was_recovered
  );
end;
$$;

create function public.complete_website_delivery_pdf_conversion_v2(
  p_execution_id uuid,
  p_workflow_run_id text,
  p_workflow_run_attempt integer,
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
     or p_workflow_run_attempt is null or p_workflow_run_attempt <= 0
     or p_pdf_sha256 !~ '^[0-9a-f]{64}$' or p_pdf_bytes <= 0 or p_pdf_bytes > 10485760
     or p_idempotency_key is null or nullif(btrim(p_actor), '') is null then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_PDF_COMPLETE_INPUT_INVALID';
  end if;

  select * into v_execution
  from public.website_delivery_pdf_conversion_executions
  where execution_id = p_execution_id for update;
  if not found or v_execution.workflow_run_id <> p_workflow_run_id
     or v_execution.workflow_run_attempt <> p_workflow_run_attempt then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_EXECUTION_BINDING_INVALID';
  end if;

  select * into v_task from public.website_delivery_pdf_conversion_tasks where task_id = v_execution.task_id;
  select current_state into v_state
  from public.commercial_projects where project_id = v_task.project_id for update;
  if v_state <> 'M2_PAYMENT_RECEIVED' then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_STATE_INVALID';
  end if;
  if exists (select 1 from public.website_delivery_document_acceptances where project_id = v_task.project_id) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_ALREADY_ACCEPTED';
  end if;
  if not exists (
    select 1 from public.preview_versions
    where preview_version_id = v_task.preview_version_id
      and project_id = v_task.project_id and status = 'CURRENT'
  ) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_SOURCE_STALE';
  end if;

  if v_execution.completed_at is not null then
    if v_execution.pdf_sha256 <> p_pdf_sha256 or v_execution.pdf_bytes <> p_pdf_bytes
       or v_execution.completion_idempotency_key <> p_idempotency_key then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_COMPLETION_CONFLICT';
    end if;
    select jsonb_build_object(
      'execution_id', v_execution.execution_id,
      'workflow_run_id', v_execution.workflow_run_id,
      'workflow_run_attempt', v_execution.workflow_run_attempt,
      'view_derivative_id', view_derivative_id,
      'pdf_sha256', rtrim(pdf_sha256),
      'pdf_bytes', pdf_bytes,
      'was_created', false
    ) into v_view
    from public.website_delivery_document_view_derivatives
    where view_derivative_id = v_execution.view_derivative_id;
    return v_view;
  end if;

  if v_execution.expires_at <= clock_timestamp() then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_EXECUTION_EXPIRED';
  end if;
  v_view := public.register_website_delivery_document_view_v1(
    v_task.artifact_id, rtrim(p_pdf_sha256), p_pdf_bytes,
    'application/pdf', p_idempotency_key, btrim(p_actor)
  );
  update public.website_delivery_pdf_conversion_executions
  set completed_at = clock_timestamp(),
      view_derivative_id = (v_view->>'view_derivative_id')::uuid,
      pdf_sha256 = p_pdf_sha256,
      pdf_bytes = p_pdf_bytes,
      completion_idempotency_key = p_idempotency_key,
      completed_by = btrim(p_actor)
  where execution_id = p_execution_id
  returning * into v_execution;
  return jsonb_build_object(
    'execution_id', v_execution.execution_id,
    'workflow_run_id', v_execution.workflow_run_id,
    'workflow_run_attempt', v_execution.workflow_run_attempt,
    'view_derivative_id', v_execution.view_derivative_id,
    'pdf_sha256', rtrim(v_execution.pdf_sha256),
    'pdf_bytes', v_execution.pdf_bytes,
    'was_created', true
  );
end;
$$;

revoke all on function public.claim_website_delivery_pdf_conversion_v2(uuid,text,text,text,text,text,integer,text)
from public, anon, authenticated, service_role;
grant execute on function public.claim_website_delivery_pdf_conversion_v2(uuid,text,text,text,text,text,integer,text)
to service_role;
revoke all on function public.complete_website_delivery_pdf_conversion_v2(uuid,text,integer,char,bigint,uuid,text)
from public, anon, authenticated, service_role;
grant execute on function public.complete_website_delivery_pdf_conversion_v2(uuid,text,integer,char,bigint,uuid,text)
to service_role;

revoke execute on function public.claim_website_delivery_pdf_conversion_v1(uuid,text,text,text,text,text,text)
from service_role;
revoke execute on function public.complete_website_delivery_pdf_conversion_v1(uuid,text,char,bigint,uuid,text)
from service_role;

comment on column public.website_delivery_pdf_conversion_executions.workflow_run_attempt is
  'GitHub workflow run_attempt bound to the current execution lease; takeover requires a newer run tuple after expiry.';
comment on function public.claim_website_delivery_pdf_conversion_v2(uuid,text,text,text,text,text,integer,text) is
  'Claims or atomically recovers one exact immutable conversion task; only an expired incomplete lease and a newer run tuple can rotate execution identity.';
comment on function public.complete_website_delivery_pdf_conversion_v2(uuid,text,integer,char,bigint,uuid,text) is
  'Completes only the current execution/run/run_attempt and returns exact idempotent replay after durable registration.';
