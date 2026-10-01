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
  if exists (
       select 1 from public.website_delivery_pdf_recovery_intents
       where task_id=p_task_id
         and (
           status='RERUN_UNKNOWN'
           or (status in ('RERUN_ACCEPTED','RUNNING')
             and observed_provider_status is distinct from 'completed')
         )
     )
     or v_execution.claimed_by like 'PDF_ORPHAN_CLEANUP:%'
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
