-- C1 schema-free orphan cleanup. The existing execution row is the durable
-- interlock around the external Storage delete; no age-only deletion exists.

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
     and new.workflow_run_id = old.workflow_run_id
     and new.workflow_run_attempt = old.workflow_run_attempt
     and old.claimed_by not like 'PDF_ORPHAN_CLEANUP:CLAIM:%'
     and new.claimed_by like 'PDF_ORPHAN_CLEANUP:CLAIM:%'
     and new.claimed_at >= old.expires_at
     and new.expires_at > new.claimed_at
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
     and new.claimed_by like 'PDF_ORPHAN_CLEANUP:DONE:%'
     and new.claimed_at = old.claimed_at
     and new.expires_at > new.claimed_at
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
     and (
       new.workflow_run_id::numeric > old.workflow_run_id::numeric
       or (new.workflow_run_id = old.workflow_run_id and new.workflow_run_attempt > old.workflow_run_attempt)
     )
     and old.claimed_by not like 'PDF_ORPHAN_CLEANUP:CLAIM:%'
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

alter function public.claim_website_delivery_pdf_conversion_v2(uuid,text,text,text,text,text,integer,text)
  rename to claim_website_delivery_pdf_conversion_core_v2;
revoke all on function public.claim_website_delivery_pdf_conversion_core_v2(uuid,text,text,text,text,text,integer,text)
  from public, anon, authenticated, service_role;

create function public.claim_website_delivery_pdf_conversion_v2(
  p_task_id uuid, p_workflow_repository text, p_workflow_repository_id text,
  p_workflow_ref_name text, p_workflow_ref text, p_workflow_run_id text,
  p_workflow_run_attempt integer, p_actor text
) returns jsonb
language plpgsql security definer set search_path = public, pg_catalog as $$
declare v_claimed_by text;
begin
  if p_task_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(p_task_id::text, 0));
    select claimed_by into v_claimed_by
    from public.website_delivery_pdf_conversion_executions where task_id = p_task_id;
    if v_claimed_by like 'PDF_ORPHAN_CLEANUP:CLAIM:%' then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_CLAIM_CONFLICT';
    end if;
  end if;
  return public.claim_website_delivery_pdf_conversion_core_v2(
    p_task_id, p_workflow_repository, p_workflow_repository_id, p_workflow_ref_name,
    p_workflow_ref, p_workflow_run_id, p_workflow_run_attempt, p_actor
  );
end;
$$;

alter function public.complete_website_delivery_pdf_conversion_v2(uuid,text,integer,char,bigint,uuid,text)
  rename to complete_website_delivery_pdf_conversion_core_v2;
revoke all on function public.complete_website_delivery_pdf_conversion_core_v2(uuid,text,integer,char,bigint,uuid,text)
  from public, anon, authenticated, service_role;

create function public.complete_website_delivery_pdf_conversion_v2(
  p_execution_id uuid, p_workflow_run_id text, p_workflow_run_attempt integer,
  p_pdf_sha256 char(64), p_pdf_bytes bigint, p_idempotency_key uuid, p_actor text
) returns jsonb
language plpgsql security definer set search_path = public, pg_catalog as $$
declare v_task_id uuid; v_claimed_by text;
begin
  select task_id into v_task_id
  from public.website_delivery_pdf_conversion_executions where execution_id = p_execution_id;
  if v_task_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(v_task_id::text, 0));
    select claimed_by into v_claimed_by
    from public.website_delivery_pdf_conversion_executions where execution_id = p_execution_id;
    if v_claimed_by like 'PDF_ORPHAN_CLEANUP:%' then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_EXECUTION_BINDING_INVALID';
    end if;
  end if;
  return public.complete_website_delivery_pdf_conversion_core_v2(
    p_execution_id, p_workflow_run_id, p_workflow_run_attempt, p_pdf_sha256,
    p_pdf_bytes, p_idempotency_key, p_actor
  );
end;
$$;

create function public.list_website_delivery_pdf_orphans_v1(
  p_quarantine_seconds integer default 86400,
  p_limit integer default 100
) returns table(
  task_id uuid, artifact_id uuid, execution_id uuid,
  storage_bucket_id text, storage_object_path text,
  pdf_sha256 char(64), pdf_bytes bigint,
  object_created_at timestamptz, object_updated_at timestamptz,
  execution_expires_at timestamptz
)
language plpgsql security definer set search_path = public, storage, pg_catalog as $$
begin
  if p_quarantine_seconds < 86400 or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_PDF_ORPHAN_SELECTION_INVALID';
  end if;
  return query
  select t.task_id, t.artifact_id, e.execution_id,
    o.bucket_id, o.name,
    substring(o.name from '/([0-9a-f]{64})\.pdf$')::char(64),
    (o.metadata->>'size')::bigint,
    o.created_at, o.updated_at, e.expires_at
  from public.website_delivery_pdf_conversion_tasks t
  join public.website_delivery_document_artifacts a on a.artifact_id = t.artifact_id
  join public.website_delivery_pdf_conversion_executions e on e.task_id = t.task_id
  join storage.objects o
    on o.bucket_id = 'website-delivery-document-views'
   and o.name = 'projects/'||t.project_id||'/versions/'||t.document_version||'/views/'
     ||rtrim(t.source_docx_sha256)||'/'||substring(o.name from '/([0-9a-f]{64})\.pdf$')||'.pdf'
  where e.completed_at is null
    and e.claimed_by not like 'PDF_ORPHAN_CLEANUP:%'
    and e.expires_at <= clock_timestamp() - make_interval(secs => p_quarantine_seconds)
    and o.created_at <= clock_timestamp() - make_interval(secs => p_quarantine_seconds)
    and o.updated_at <= clock_timestamp() - make_interval(secs => p_quarantine_seconds)
    and coalesce(o.metadata->>'mimetype','') = 'application/pdf'
    and coalesce(o.metadata->>'size','') ~ '^[1-9][0-9]*$'
    and (o.metadata->>'size')::bigint <= 10485760
    and not exists (
      select 1 from public.website_delivery_document_view_derivatives v
      where v.artifact_id = t.artifact_id or v.storage_object_path = o.name
    )
  order by greatest(o.created_at, o.updated_at), t.task_id
  limit p_limit;
end;
$$;

create function public.claim_website_delivery_pdf_orphan_cleanup_v1(
  p_task_id uuid, p_pdf_sha256 char(64), p_pdf_bytes bigint,
  p_quarantine_seconds integer, p_actor text
) returns jsonb
language plpgsql security definer set search_path = public, storage, pg_catalog as $$
declare
  v_task public.website_delivery_pdf_conversion_tasks%rowtype;
  v_execution public.website_delivery_pdf_conversion_executions%rowtype;
  v_object storage.objects%rowtype;
  v_path text;
  v_marker text;
begin
  if p_task_id is null or p_pdf_sha256 !~ '^[0-9a-f]{64}$'
     or p_pdf_bytes <= 0 or p_pdf_bytes > 10485760
     or p_quarantine_seconds < 86400 or nullif(btrim(p_actor),'') is null or length(p_actor) > 200 then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_PDF_ORPHAN_CLAIM_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_task_id::text, 0));
  select * into v_task from public.website_delivery_pdf_conversion_tasks where task_id = p_task_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_TASK_NOT_FOUND';
  end if;
  v_path := 'projects/'||v_task.project_id||'/versions/'||v_task.document_version||'/views/'
    ||rtrim(v_task.source_docx_sha256)||'/'||rtrim(p_pdf_sha256)||'.pdf';
  v_marker := 'PDF_ORPHAN_CLEANUP:CLAIM:'||rtrim(p_pdf_sha256)||':'||p_pdf_bytes||':'||btrim(p_actor);
  select * into v_execution from public.website_delivery_pdf_conversion_executions
  where task_id = p_task_id for update;
  if not found or v_execution.completed_at is not null then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_ORPHAN_NOT_ELIGIBLE';
  end if;
  if v_execution.claimed_by = v_marker then
    select * into v_object from storage.objects
    where bucket_id='website-delivery-document-views' and name=v_path;
    if not found then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_ORPHAN_OBJECT_MISSING';
    end if;
    return jsonb_build_object('task_id',p_task_id,'cleanup_execution_id',v_execution.execution_id,
      'storage_bucket_id','website-delivery-document-views','storage_object_path',v_path,
      'pdf_sha256',rtrim(p_pdf_sha256),'pdf_bytes',p_pdf_bytes,'was_claimed',false);
  end if;
  if v_execution.claimed_by like 'PDF_ORPHAN_CLEANUP:%'
     or v_execution.expires_at > clock_timestamp() - make_interval(secs => p_quarantine_seconds)
     or exists (select 1 from public.website_delivery_document_view_derivatives
       where artifact_id=v_task.artifact_id or storage_object_path=v_path) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_ORPHAN_NOT_ELIGIBLE';
  end if;
  select * into v_object from storage.objects
  where bucket_id='website-delivery-document-views' and name=v_path for update;
  if not found or v_object.created_at > clock_timestamp() - make_interval(secs => p_quarantine_seconds)
     or v_object.updated_at > clock_timestamp() - make_interval(secs => p_quarantine_seconds)
     or coalesce(v_object.metadata->>'mimetype','') <> 'application/pdf'
     or coalesce(v_object.metadata->>'size','') !~ '^[1-9][0-9]*$'
     or (v_object.metadata->>'size')::bigint <> p_pdf_bytes then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_ORPHAN_NOT_ELIGIBLE';
  end if;
  update public.website_delivery_pdf_conversion_executions
  set execution_id=gen_random_uuid(), claimed_by=v_marker,
      claimed_at=clock_timestamp(), expires_at=clock_timestamp()+interval '15 minutes'
  where task_id=p_task_id returning * into v_execution;
  return jsonb_build_object('task_id',p_task_id,'cleanup_execution_id',v_execution.execution_id,
    'storage_bucket_id','website-delivery-document-views','storage_object_path',v_path,
    'pdf_sha256',rtrim(p_pdf_sha256),'pdf_bytes',p_pdf_bytes,'was_claimed',true);
end;
$$;

create function public.finalize_website_delivery_pdf_orphan_cleanup_v1(
  p_task_id uuid, p_cleanup_execution_id uuid, p_pdf_sha256 char(64), p_actor text
) returns jsonb
language plpgsql security definer set search_path = public, storage, pg_catalog as $$
declare
  v_task public.website_delivery_pdf_conversion_tasks%rowtype;
  v_execution public.website_delivery_pdf_conversion_executions%rowtype;
  v_path text;
  v_claim_prefix text;
  v_done_prefix text;
begin
  if p_task_id is null or p_cleanup_execution_id is null or p_pdf_sha256 !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_actor),'') is null or length(p_actor)>200 then
    raise exception using errcode='22023', message='WEBSITE_DELIVERY_PDF_ORPHAN_FINALIZE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_task_id::text,0));
  select * into v_task from public.website_delivery_pdf_conversion_tasks where task_id=p_task_id;
  select * into v_execution from public.website_delivery_pdf_conversion_executions
  where task_id=p_task_id and execution_id=p_cleanup_execution_id for update;
  v_claim_prefix := 'PDF_ORPHAN_CLEANUP:CLAIM:'||rtrim(p_pdf_sha256)||':';
  v_done_prefix := 'PDF_ORPHAN_CLEANUP:DONE:'||rtrim(p_pdf_sha256)||':';
  if not found or v_task.task_id is null
     or (v_execution.claimed_by not like v_claim_prefix||'%' and v_execution.claimed_by not like v_done_prefix||'%') then
    raise exception using errcode='P0001', message='WEBSITE_DELIVERY_PDF_ORPHAN_CLAIM_INVALID';
  end if;
  if v_execution.claimed_by like v_done_prefix||'%' then
    return jsonb_build_object('task_id',p_task_id,'cleanup_execution_id',p_cleanup_execution_id,
      'pdf_sha256',rtrim(p_pdf_sha256),'was_finalized',false);
  end if;
  v_path := 'projects/'||v_task.project_id||'/versions/'||v_task.document_version||'/views/'
    ||rtrim(v_task.source_docx_sha256)||'/'||rtrim(p_pdf_sha256)||'.pdf';
  if exists (select 1 from public.website_delivery_document_view_derivatives
      where artifact_id=v_task.artifact_id or storage_object_path=v_path) then
    raise exception using errcode='P0001', message='WEBSITE_DELIVERY_PDF_ORPHAN_REGISTRATION_CONFLICT';
  end if;
  if exists (select 1 from storage.objects where bucket_id='website-delivery-document-views' and name=v_path) then
    raise exception using errcode='P0001', message='WEBSITE_DELIVERY_PDF_ORPHAN_OBJECT_STILL_PRESENT';
  end if;
  update public.website_delivery_pdf_conversion_executions
  set claimed_by=replace(v_execution.claimed_by,'PDF_ORPHAN_CLEANUP:CLAIM:','PDF_ORPHAN_CLEANUP:DONE:'),
      expires_at=greatest(clock_timestamp(),claimed_at+interval '1 microsecond')
  where execution_id=p_cleanup_execution_id;
  return jsonb_build_object('task_id',p_task_id,'cleanup_execution_id',p_cleanup_execution_id,
    'pdf_sha256',rtrim(p_pdf_sha256),'was_finalized',true);
end;
$$;

revoke all on function public.claim_website_delivery_pdf_conversion_v2(uuid,text,text,text,text,text,integer,text)
  from public, anon, authenticated, service_role;
revoke all on function public.complete_website_delivery_pdf_conversion_v2(uuid,text,integer,char,bigint,uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function public.list_website_delivery_pdf_orphans_v1(integer,integer)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_website_delivery_pdf_orphan_cleanup_v1(uuid,char,bigint,integer,text)
  from public, anon, authenticated, service_role;
revoke all on function public.finalize_website_delivery_pdf_orphan_cleanup_v1(uuid,uuid,char,text)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_website_delivery_pdf_conversion_v2(uuid,text,text,text,text,text,integer,text) to service_role;
grant execute on function public.complete_website_delivery_pdf_conversion_v2(uuid,text,integer,char,bigint,uuid,text) to service_role;
grant execute on function public.list_website_delivery_pdf_orphans_v1(integer,integer) to service_role;
grant execute on function public.claim_website_delivery_pdf_orphan_cleanup_v1(uuid,char,bigint,integer,text) to service_role;
grant execute on function public.finalize_website_delivery_pdf_orphan_cleanup_v1(uuid,uuid,char,text) to service_role;

comment on function public.list_website_delivery_pdf_orphans_v1(integer,integer) is
  'Dry-run only selection; requires exact stale task, execution and private Storage lineage with a minimum 24-hour quarantine.';
comment on function public.claim_website_delivery_pdf_orphan_cleanup_v1(uuid,char,bigint,integer,text) is
  'Claims one exact orphan under the task advisory lock by rotating the existing execution identity.';
comment on function public.finalize_website_delivery_pdf_orphan_cleanup_v1(uuid,uuid,char,text) is
  'Finalizes an exact cleanup claim only after the private Storage object is absent and no derivative was registered.';