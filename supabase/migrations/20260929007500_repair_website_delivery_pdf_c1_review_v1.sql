-- C1 review repair: recovery is same-run/higher-attempt only, and orphan
-- deletion uses a durable claim -> quarantine stage -> finalize sequence.

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
     and old.claimed_by not like 'PDF_ORPHAN_CLEANUP:%'
     and new.completed_at is not null and new.view_derivative_id is not null
     and new.pdf_sha256 is not null and new.pdf_bytes is not null
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
     and new.workflow_run_id = old.workflow_run_id
     and new.workflow_run_attempt = old.workflow_run_attempt
     and old.claimed_by not like 'PDF_ORPHAN_CLEANUP:CLAIM:%'
     and old.claimed_by not like 'PDF_ORPHAN_CLEANUP:STAGED:%'
     and new.claimed_by like 'PDF_ORPHAN_CLEANUP:CLAIM:%'
     and new.claimed_at >= old.expires_at and new.expires_at > new.claimed_at
     and new.completed_at is null and new.view_derivative_id is null
     and new.pdf_sha256 is null and new.pdf_bytes is null
     and new.completion_idempotency_key is null and new.completed_by is null then
    return new;
  end if;

  if new.execution_id = old.execution_id
     and new.task_id = old.task_id
     and new.workflow_repository = old.workflow_repository
     and new.workflow_repository_id = old.workflow_repository_id
     and new.workflow_ref_name = old.workflow_ref_name
     and new.workflow_ref = old.workflow_ref
     and new.workflow_run_id = old.workflow_run_id
     and new.workflow_run_attempt = old.workflow_run_attempt
     and old.claimed_by like 'PDF_ORPHAN_CLEANUP:CLAIM:%'
     and new.claimed_by like 'PDF_ORPHAN_CLEANUP:STAGED:%'
     and new.claimed_at = old.claimed_at and new.expires_at = old.expires_at
     and new.completed_at is null and new.view_derivative_id is null
     and new.pdf_sha256 is null and new.pdf_bytes is null
     and new.completion_idempotency_key is null and new.completed_by is null then
    return new;
  end if;

  if new.execution_id = old.execution_id
     and new.task_id = old.task_id
     and new.workflow_repository = old.workflow_repository
     and new.workflow_repository_id = old.workflow_repository_id
     and new.workflow_ref_name = old.workflow_ref_name
     and new.workflow_ref = old.workflow_ref
     and new.workflow_run_id = old.workflow_run_id
     and new.workflow_run_attempt = old.workflow_run_attempt
     and (old.claimed_by like 'PDF_ORPHAN_CLEANUP:CLAIM:%'
       or old.claimed_by like 'PDF_ORPHAN_CLEANUP:STAGED:%')
     and new.claimed_by like 'PDF_ORPHAN_CLEANUP:DONE:%'
     and new.claimed_at = old.claimed_at and new.expires_at > new.claimed_at
     and new.completed_at is null and new.view_derivative_id is null
     and new.pdf_sha256 is null and new.pdf_bytes is null
     and new.completion_idempotency_key is null and new.completed_by is null then
    return new;
  end if;

  if old.expires_at <= clock_timestamp()
     and new.execution_id <> old.execution_id
     and new.task_id = old.task_id
     and new.workflow_repository = old.workflow_repository
     and new.workflow_repository_id = old.workflow_repository_id
     and new.workflow_ref_name = old.workflow_ref_name
     and new.workflow_ref = old.workflow_ref
     and new.workflow_run_id = old.workflow_run_id
     and new.workflow_run_attempt > old.workflow_run_attempt
     and old.claimed_by not like 'PDF_ORPHAN_CLEANUP:CLAIM:%'
     and old.claimed_by not like 'PDF_ORPHAN_CLEANUP:STAGED:%'
     and new.claimed_by not like 'PDF_ORPHAN_CLEANUP:%'
     and nullif(btrim(new.claimed_by), '') is not null
     and new.claimed_at >= old.expires_at and new.expires_at > new.claimed_at
     and new.completed_at is null and new.view_derivative_id is null
     and new.pdf_sha256 is null and new.pdf_bytes is null
     and new.completion_idempotency_key is null and new.completed_by is null then
    return new;
  end if;

  raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_EXECUTION_IMMUTABLE';
end;
$$;

create or replace function public.claim_website_delivery_pdf_conversion_core_v2(
  p_task_id uuid, p_workflow_repository text, p_workflow_repository_id text,
  p_workflow_ref_name text, p_workflow_ref text, p_workflow_run_id text,
  p_workflow_run_attempt integer, p_actor text
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
  if not exists (select 1 from public.preview_versions
    where preview_version_id = v_task.preview_version_id and project_id = v_task.project_id and status = 'CURRENT') then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_SOURCE_STALE';
  end if;
  if exists (select 1 from public.website_delivery_document_view_derivatives where artifact_id = v_task.artifact_id) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_VIEW_ALREADY_REGISTERED';
  end if;

  select metadata into v_metadata from storage.objects
  where bucket_id = v_artifact.storage_bucket_id and name = v_artifact.storage_object_path;
  if not found or coalesce(v_metadata->>'mimetype', '') <> v_artifact.content_type
     or coalesce(v_metadata->>'size', '') !~ '^[0-9]+$'
     or (v_metadata->>'size')::bigint <> v_artifact.docx_bytes then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_SOURCE_OBJECT_INVALID';
  end if;

  select * into v_execution from public.website_delivery_pdf_conversion_executions where task_id = p_task_id;
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
      if p_workflow_run_id <> v_execution.workflow_run_id
         or p_workflow_run_attempt <= v_execution.workflow_run_attempt then
        raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_CLAIM_STALE';
      end if;
      update public.website_delivery_pdf_conversion_executions
      set execution_id = gen_random_uuid(), workflow_run_attempt = p_workflow_run_attempt,
          claimed_by = btrim(p_actor), claimed_at = clock_timestamp(),
          expires_at = clock_timestamp() + interval '15 minutes'
      where task_id = p_task_id returning * into v_execution;
      v_was_created := true;
      v_was_recovered := true;
    end if;
  end if;

  return jsonb_build_object(
    'execution_id', v_execution.execution_id, 'task_id', v_task.task_id,
    'artifact_id', v_task.artifact_id, 'project_id', v_task.project_id,
    'preview_version_id', v_task.preview_version_id, 'document_version', v_task.document_version,
    'source_bucket_id', v_artifact.storage_bucket_id, 'source_object_path', v_artifact.storage_object_path,
    'source_docx_sha256', rtrim(v_task.source_docx_sha256), 'source_docx_bytes', v_artifact.docx_bytes,
    'generation_payload_sha256', rtrim(v_task.generation_payload_sha256),
    'generation_payload', v_candidate.generation_payload,
    'workflow_run_id', v_execution.workflow_run_id,
    'workflow_run_attempt', v_execution.workflow_run_attempt,
    'expires_at', v_execution.expires_at,
    'was_created', v_was_created, 'was_recovered', v_was_recovered
  );
end;
$$;

create or replace function public.claim_website_delivery_pdf_orphan_cleanup_v1(
  p_task_id uuid, p_pdf_sha256 char(64), p_pdf_bytes bigint,
  p_quarantine_seconds integer, p_actor text
) returns jsonb
language plpgsql security definer set search_path = public, storage, pg_catalog as $$
declare
  v_task public.website_delivery_pdf_conversion_tasks%rowtype;
  v_execution public.website_delivery_pdf_conversion_executions%rowtype;
  v_object storage.objects%rowtype;
  v_path text;
  v_cleanup_path text;
  v_phase text;
  v_object_id uuid;
  v_marker text;
begin
  if p_task_id is null or p_pdf_sha256 !~ '^[0-9a-f]{64}$'
     or p_pdf_bytes <= 0 or p_pdf_bytes > 10485760
     or p_quarantine_seconds < 86400 or nullif(btrim(p_actor),'') is null or length(p_actor)>200 then
    raise exception using errcode='22023', message='WEBSITE_DELIVERY_PDF_ORPHAN_CLAIM_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_task_id::text,0));
  select * into v_task from public.website_delivery_pdf_conversion_tasks where task_id=p_task_id;
  if not found then
    raise exception using errcode='P0001', message='WEBSITE_DELIVERY_PDF_TASK_NOT_FOUND';
  end if;
  v_path := 'projects/'||v_task.project_id||'/versions/'||v_task.document_version||'/views/'
    ||rtrim(v_task.source_docx_sha256)||'/'||rtrim(p_pdf_sha256)||'.pdf';
  select * into v_execution from public.website_delivery_pdf_conversion_executions
  where task_id=p_task_id for update;
  if not found or v_execution.completed_at is not null then
    raise exception using errcode='P0001', message='WEBSITE_DELIVERY_PDF_ORPHAN_NOT_ELIGIBLE';
  end if;

  v_phase := split_part(v_execution.claimed_by,':',2);
  if split_part(v_execution.claimed_by,':',1)='PDF_ORPHAN_CLEANUP'
     and v_phase in ('CLAIM','STAGED','DONE')
     and split_part(v_execution.claimed_by,':',3)=rtrim(p_pdf_sha256)
     and split_part(v_execution.claimed_by,':',4)=p_pdf_bytes::text then
    if split_part(v_execution.claimed_by,':',5) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      v_object_id := split_part(v_execution.claimed_by,':',5)::uuid;
    end if;
    v_cleanup_path := 'cleanup/'||p_task_id||'/'||v_execution.execution_id||'/'||rtrim(p_pdf_sha256)||'.pdf';
    return jsonb_build_object(
      'task_id',p_task_id,'cleanup_execution_id',v_execution.execution_id,
      'storage_bucket_id','website-delivery-document-views','storage_object_path',v_path,
      'cleanup_storage_object_path',v_cleanup_path,'storage_object_id',v_object_id,
      'cleanup_phase',v_phase,'pdf_sha256',rtrim(p_pdf_sha256),
      'pdf_bytes',p_pdf_bytes,'was_claimed',false
    );
  end if;
  if v_execution.claimed_by like 'PDF_ORPHAN_CLEANUP:%'
     or v_execution.expires_at > clock_timestamp()-make_interval(secs=>p_quarantine_seconds)
     or exists (select 1 from public.website_delivery_document_view_derivatives
       where artifact_id=v_task.artifact_id or storage_object_path=v_path) then
    raise exception using errcode='P0001', message='WEBSITE_DELIVERY_PDF_ORPHAN_NOT_ELIGIBLE';
  end if;
  select * into v_object from storage.objects
  where bucket_id='website-delivery-document-views' and name=v_path for update;
  if not found or v_object.created_at > clock_timestamp()-make_interval(secs=>p_quarantine_seconds)
     or v_object.updated_at > clock_timestamp()-make_interval(secs=>p_quarantine_seconds)
     or coalesce(v_object.metadata->>'mimetype','')<>'application/pdf'
     or coalesce(v_object.metadata->>'size','') !~ '^[1-9][0-9]*$'
     or (v_object.metadata->>'size')::bigint<>p_pdf_bytes then
    raise exception using errcode='P0001', message='WEBSITE_DELIVERY_PDF_ORPHAN_NOT_ELIGIBLE';
  end if;
  v_marker := 'PDF_ORPHAN_CLEANUP:CLAIM:'||rtrim(p_pdf_sha256)||':'||p_pdf_bytes||':'||v_object.id||':'||btrim(p_actor);
  update public.website_delivery_pdf_conversion_executions
  set execution_id=gen_random_uuid(), claimed_by=v_marker,
      claimed_at=clock_timestamp(), expires_at=clock_timestamp()+interval '15 minutes'
  where task_id=p_task_id returning * into v_execution;
  v_cleanup_path := 'cleanup/'||p_task_id||'/'||v_execution.execution_id||'/'||rtrim(p_pdf_sha256)||'.pdf';
  return jsonb_build_object(
    'task_id',p_task_id,'cleanup_execution_id',v_execution.execution_id,
    'storage_bucket_id','website-delivery-document-views','storage_object_path',v_path,
    'cleanup_storage_object_path',v_cleanup_path,'storage_object_id',v_object.id,
    'cleanup_phase','CLAIM','pdf_sha256',rtrim(p_pdf_sha256),
    'pdf_bytes',p_pdf_bytes,'was_claimed',true
  );
end;
$$;

create function public.stage_website_delivery_pdf_orphan_cleanup_v1(
  p_task_id uuid, p_cleanup_execution_id uuid, p_pdf_sha256 char(64), p_actor text
) returns jsonb
language plpgsql security definer set search_path = public, storage, pg_catalog as $$
declare
  v_task public.website_delivery_pdf_conversion_tasks%rowtype;
  v_execution public.website_delivery_pdf_conversion_executions%rowtype;
  v_path text;
  v_cleanup_path text;
  v_object_id uuid;
  v_phase text;
begin
  if p_task_id is null or p_cleanup_execution_id is null or p_pdf_sha256 !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_actor),'') is null or length(p_actor)>200 then
    raise exception using errcode='22023', message='WEBSITE_DELIVERY_PDF_ORPHAN_STAGE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_task_id::text,0));
  select * into v_task from public.website_delivery_pdf_conversion_tasks where task_id=p_task_id;
  select * into v_execution from public.website_delivery_pdf_conversion_executions
  where task_id=p_task_id and execution_id=p_cleanup_execution_id for update;
  v_phase := split_part(v_execution.claimed_by,':',2);
  if not found or v_task.task_id is null
     or split_part(v_execution.claimed_by,':',1)<>'PDF_ORPHAN_CLEANUP'
     or v_phase not in ('CLAIM','STAGED')
     or split_part(v_execution.claimed_by,':',3)<>rtrim(p_pdf_sha256) then
    raise exception using errcode='P0001', message='WEBSITE_DELIVERY_PDF_ORPHAN_CLAIM_INVALID';
  end if;
  v_path := 'projects/'||v_task.project_id||'/versions/'||v_task.document_version||'/views/'
    ||rtrim(v_task.source_docx_sha256)||'/'||rtrim(p_pdf_sha256)||'.pdf';
  v_cleanup_path := 'cleanup/'||p_task_id||'/'||p_cleanup_execution_id||'/'||rtrim(p_pdf_sha256)||'.pdf';
  if exists (select 1 from public.website_delivery_document_view_derivatives
    where artifact_id=v_task.artifact_id or storage_object_path in (v_path,v_cleanup_path)) then
    raise exception using errcode='P0001', message='WEBSITE_DELIVERY_PDF_ORPHAN_REGISTRATION_CONFLICT';
  end if;
  if v_phase='CLAIM' then
    if split_part(v_execution.claimed_by,':',5) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      v_object_id := split_part(v_execution.claimed_by,':',5)::uuid;
    end if;
    if exists (select 1 from storage.objects where bucket_id='website-delivery-document-views'
        and name=v_cleanup_path and (v_object_id is null or id=v_object_id))
       or not exists (select 1 from storage.objects where bucket_id='website-delivery-document-views'
        and name in (v_path,v_cleanup_path)) then
      update public.website_delivery_pdf_conversion_executions
      set claimed_by=replace(v_execution.claimed_by,'PDF_ORPHAN_CLEANUP:CLAIM:','PDF_ORPHAN_CLEANUP:STAGED:')
      where execution_id=p_cleanup_execution_id returning * into v_execution;
    else
      raise exception using errcode='P0001', message='WEBSITE_DELIVERY_PDF_ORPHAN_STAGE_CONFLICT';
    end if;
  end if;
  return jsonb_build_object(
    'task_id',p_task_id,'cleanup_execution_id',p_cleanup_execution_id,
    'storage_bucket_id','website-delivery-document-views','storage_object_path',v_path,
    'cleanup_storage_object_path',v_cleanup_path,'storage_object_id',v_object_id,
    'cleanup_phase','STAGED','pdf_sha256',rtrim(p_pdf_sha256)
  );
end;
$$;

create or replace function public.finalize_website_delivery_pdf_orphan_cleanup_v1(
  p_task_id uuid, p_cleanup_execution_id uuid, p_pdf_sha256 char(64), p_actor text
) returns jsonb
language plpgsql security definer set search_path = public, storage, pg_catalog as $$
declare
  v_task public.website_delivery_pdf_conversion_tasks%rowtype;
  v_execution public.website_delivery_pdf_conversion_executions%rowtype;
  v_path text;
  v_cleanup_path text;
  v_phase text;
begin
  if p_task_id is null or p_cleanup_execution_id is null or p_pdf_sha256 !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_actor),'') is null or length(p_actor)>200 then
    raise exception using errcode='22023', message='WEBSITE_DELIVERY_PDF_ORPHAN_FINALIZE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_task_id::text,0));
  select * into v_task from public.website_delivery_pdf_conversion_tasks where task_id=p_task_id;
  select * into v_execution from public.website_delivery_pdf_conversion_executions
  where task_id=p_task_id and execution_id=p_cleanup_execution_id for update;
  v_phase := split_part(v_execution.claimed_by,':',2);
  if not found or v_task.task_id is null
     or split_part(v_execution.claimed_by,':',1)<>'PDF_ORPHAN_CLEANUP'
     or v_phase not in ('CLAIM','STAGED','DONE')
     or split_part(v_execution.claimed_by,':',3)<>rtrim(p_pdf_sha256) then
    raise exception using errcode='P0001', message='WEBSITE_DELIVERY_PDF_ORPHAN_CLAIM_INVALID';
  end if;
  if v_phase='DONE' then
    return jsonb_build_object('task_id',p_task_id,'cleanup_execution_id',p_cleanup_execution_id,
      'pdf_sha256',rtrim(p_pdf_sha256),'was_finalized',false);
  end if;
  v_path := 'projects/'||v_task.project_id||'/versions/'||v_task.document_version||'/views/'
    ||rtrim(v_task.source_docx_sha256)||'/'||rtrim(p_pdf_sha256)||'.pdf';
  v_cleanup_path := 'cleanup/'||p_task_id||'/'||p_cleanup_execution_id||'/'||rtrim(p_pdf_sha256)||'.pdf';
  if exists (select 1 from public.website_delivery_document_view_derivatives
      where artifact_id=v_task.artifact_id or storage_object_path in (v_path,v_cleanup_path)) then
    raise exception using errcode='P0001', message='WEBSITE_DELIVERY_PDF_ORPHAN_REGISTRATION_CONFLICT';
  end if;
  if exists (select 1 from storage.objects where bucket_id='website-delivery-document-views'
      and name in (v_path,v_cleanup_path)) then
    raise exception using errcode='P0001', message='WEBSITE_DELIVERY_PDF_ORPHAN_OBJECT_STILL_PRESENT';
  end if;
  update public.website_delivery_pdf_conversion_executions
  set claimed_by=regexp_replace(v_execution.claimed_by,
        '^PDF_ORPHAN_CLEANUP:(CLAIM|STAGED):','PDF_ORPHAN_CLEANUP:DONE:'),
      expires_at=greatest(clock_timestamp(),claimed_at+interval '1 microsecond')
  where execution_id=p_cleanup_execution_id;
  return jsonb_build_object('task_id',p_task_id,'cleanup_execution_id',p_cleanup_execution_id,
    'pdf_sha256',rtrim(p_pdf_sha256),'was_finalized',true);
end;
$$;

revoke all on function public.stage_website_delivery_pdf_orphan_cleanup_v1(uuid,uuid,char,text)
  from public, anon, authenticated, service_role;
grant execute on function public.stage_website_delivery_pdf_orphan_cleanup_v1(uuid,uuid,char,text)
  to service_role;

comment on function public.claim_website_delivery_pdf_conversion_core_v2(uuid,text,text,text,text,text,integer,text) is
  'Core claim authority; an expired execution can rotate only for the same workflow run with a strictly higher run_attempt.';
comment on function public.stage_website_delivery_pdf_orphan_cleanup_v1(uuid,uuid,char,text) is
  'Durably records that the claimed object was moved to its cleanup-execution quarantine path, or was already absent.';