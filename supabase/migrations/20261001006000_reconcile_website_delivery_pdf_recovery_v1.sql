alter table public.website_delivery_pdf_recovery_intents
  add column observed_provider_status text
    check (observed_provider_status is null or (
      nullif(btrim(observed_provider_status), '') is not null
      and length(observed_provider_status) <= 40
    )),
  add column observed_provider_conclusion text
    check (observed_provider_conclusion is null or (
      nullif(btrim(observed_provider_conclusion), '') is not null
      and length(observed_provider_conclusion) <= 80
    )),
  add column observed_checked_at timestamptz;

create or replace function public.get_website_delivery_pdf_dispatch_status_v1(p_task_id uuid)
returns jsonb
language plpgsql security definer set search_path=public,pg_catalog as $$
declare
  v_intent public.website_delivery_pdf_dispatch_intents%rowtype;
  v_recovery public.website_delivery_pdf_recovery_intents%rowtype;
begin
  if p_task_id is null then
    raise exception using errcode='22023',message='WEBSITE_DELIVERY_PDF_DISPATCH_INPUT_INVALID';
  end if;
  select * into v_intent
  from public.website_delivery_pdf_dispatch_intents where task_id=p_task_id;
  if not found then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_DISPATCH_NOT_FOUND';
  end if;
  select * into v_recovery
  from public.website_delivery_pdf_recovery_intents
  where task_id=p_task_id and dispatch_attempt_id=v_intent.dispatch_attempt_id;
  return jsonb_build_object(
    'task_id',v_intent.task_id,'artifact_id',v_intent.artifact_id,'status',v_intent.status,
    'dispatch_attempt',v_intent.dispatch_attempt,'dispatch_attempt_id',v_intent.dispatch_attempt_id,
    'result_code',v_intent.result_code,'provider_run_id',v_intent.provider_run_id,
    'provider_run_attempt',v_intent.provider_run_attempt,
    'provider_checked_at',v_intent.provider_checked_at,'created_at',v_intent.created_at,
    'dispatch_started_at',v_intent.dispatch_started_at,
    'dispatch_finished_at',v_intent.dispatch_finished_at,
    'running_at',v_intent.running_at,'completed_at',v_intent.completed_at,
    'updated_at',v_intent.updated_at,
    'recovery_id',case when found then v_recovery.recovery_id else null end,
    'recovery_status',case when found then v_recovery.status else null end,
    'recovery_result_code',case when found then v_recovery.result_code else null end,
    'approved_run_attempt',case when found then v_recovery.approved_run_attempt else null end,
    'observed_run_attempt',case when found then v_recovery.observed_run_attempt else null end,
    'observed_provider_status',case when found then v_recovery.observed_provider_status else null end,
    'observed_provider_conclusion',case when found then v_recovery.observed_provider_conclusion else null end,
    'observed_checked_at',case when found then v_recovery.observed_checked_at else null end
  );
end;
$$;

create function public.reconcile_website_delivery_pdf_rerun_unknown_v1(
  p_task_id uuid,
  p_recovery_id uuid,
  p_provider_run_id text,
  p_provider_run_attempt integer,
  p_provider_status text,
  p_provider_conclusion text,
  p_provider_checked_at timestamptz,
  p_actor text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_recovery public.website_delivery_pdf_recovery_intents%rowtype;
begin
  if p_task_id is null or p_recovery_id is null
     or p_provider_run_id !~ '^[1-9][0-9]*$'
     or p_provider_run_attempt is null or p_provider_run_attempt <= 0
     or nullif(btrim(p_provider_status), '') is null or length(p_provider_status) > 40
     or (p_provider_conclusion is not null and (
       nullif(btrim(p_provider_conclusion), '') is null or length(p_provider_conclusion) > 80
     ))
     or p_provider_checked_at is null
     or p_provider_checked_at > clock_timestamp() + interval '1 minute'
     or p_provider_checked_at < clock_timestamp() - interval '10 minutes'
     or nullif(btrim(p_actor), '') is null or length(p_actor) > 200 then
    raise exception using errcode='22023',message='WEBSITE_DELIVERY_PDF_RECOVERY_INPUT_INVALID';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_task_id::text, 0));
  select * into v_recovery
  from public.website_delivery_pdf_recovery_intents
  where task_id=p_task_id and recovery_id=p_recovery_id
  for update;
  if not found then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_RECOVERY_STALE';
  end if;
  if v_recovery.provider_run_id <> p_provider_run_id then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_RECOVERY_STALE';
  end if;
  if v_recovery.observed_run_attempt is not null then
    if v_recovery.observed_run_attempt <> p_provider_run_attempt
       or v_recovery.observed_provider_status <> btrim(p_provider_status)
       or v_recovery.observed_provider_conclusion is distinct from
             (case when p_provider_conclusion is null then null else btrim(p_provider_conclusion) end) then
      raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_RECOVERY_STALE';
    end if;
    return jsonb_build_object(
      'task_id',v_recovery.task_id,'recovery_id',v_recovery.recovery_id,
      'recovery_status',v_recovery.status,'result_code',v_recovery.result_code
    );
  end if;
  if p_provider_run_attempt <= v_recovery.approved_run_attempt then
    return jsonb_build_object(
      'task_id',v_recovery.task_id,'recovery_id',v_recovery.recovery_id,
      'recovery_status',v_recovery.status,'result_code',v_recovery.result_code
    );
  end if;
  if v_recovery.status <> 'RERUN_UNKNOWN' then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_RECOVERY_STATE_INVALID';
  end if;

  update public.website_delivery_pdf_recovery_intents
  set observed_run_attempt=p_provider_run_attempt,
      observed_provider_status=btrim(p_provider_status),
      observed_provider_conclusion=case
        when p_provider_conclusion is null then null else btrim(p_provider_conclusion)
      end,
      observed_checked_at=p_provider_checked_at,
      provider_checked_at=p_provider_checked_at,
      status='RERUN_ACCEPTED',
      result_code='RERUN_HIGHER_ATTEMPT_OBSERVED',
      rerun_finished_at=coalesce(rerun_finished_at,clock_timestamp()),
      updated_at=clock_timestamp(),
      actor=btrim(p_actor)
  where task_id=p_task_id and recovery_id=p_recovery_id
  returning * into v_recovery;

  return jsonb_build_object(
    'task_id',v_recovery.task_id,'recovery_id',v_recovery.recovery_id,
    'recovery_status',v_recovery.status,'result_code',v_recovery.result_code
  );
end;
$$;

create or replace function public.claim_website_delivery_pdf_rerun_v1(
  p_task_id uuid,
  p_expected_dispatch_attempt_id uuid,
  p_provider_run_id text,
  p_provider_run_attempt integer,
  p_provider_status text,
  p_provider_conclusion text,
  p_approval_id uuid,
  p_provider_checked_at timestamptz,
  p_actor text
) returns jsonb
language plpgsql
security definer
set search_path = public, storage, pg_catalog
as $$
declare
  v_intent public.website_delivery_pdf_dispatch_intents%rowtype;
  v_recovery public.website_delivery_pdf_recovery_intents%rowtype;
  v_execution public.website_delivery_pdf_conversion_executions%rowtype;
  v_task public.website_delivery_pdf_conversion_tasks%rowtype;
  v_artifact public.website_delivery_document_artifacts%rowtype;
  v_metadata jsonb;
  v_state text;
begin
  if p_task_id is null or p_expected_dispatch_attempt_id is null
     or p_provider_run_id !~ '^[1-9][0-9]*$'
     or p_provider_run_attempt is null or p_provider_run_attempt <= 0
     or p_provider_status <> 'completed' or p_provider_conclusion is null
     or p_approval_id is null or p_provider_checked_at is null
     or p_provider_checked_at > clock_timestamp() + interval '1 minute'
     or p_provider_checked_at < clock_timestamp() - interval '10 minutes'
     or nullif(btrim(p_actor), '') is null or length(p_actor) > 200 then
    raise exception using errcode='22023',message='WEBSITE_DELIVERY_PDF_RECOVERY_INPUT_INVALID';
  end if;
  if p_provider_conclusion not in (
    'action_required','cancelled','failure','stale','startup_failure','timed_out'
  ) then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_RECOVERY_NOT_ALLOWED';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_task_id::text, 0));
  select * into v_intent
  from public.website_delivery_pdf_dispatch_intents
  where task_id=p_task_id for update;
  if not found then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_DISPATCH_NOT_FOUND';
  end if;
  if v_intent.dispatch_attempt_id <> p_expected_dispatch_attempt_id then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_RECOVERY_STALE';
  end if;

  select * into v_recovery
  from public.website_delivery_pdf_recovery_intents
  where task_id=p_task_id and dispatch_attempt_id=p_expected_dispatch_attempt_id
  for update;
  if found then
    if v_recovery.recovery_id <> p_approval_id then
      raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_RECOVERY_ALREADY_CLAIMED';
    end if;
    if v_recovery.provider_run_id <> p_provider_run_id
       or v_recovery.approved_run_attempt <> p_provider_run_attempt
       or v_recovery.provider_status <> p_provider_status
       or v_recovery.provider_conclusion <> p_provider_conclusion then
      raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_RECOVERY_STALE';
    end if;
    return jsonb_build_object(
      'task_id',v_recovery.task_id,'dispatch_attempt_id',v_recovery.dispatch_attempt_id,
      'recovery_id',v_recovery.recovery_id,'recovery_status',v_recovery.status,
      'result_code',v_recovery.result_code,'should_rerun',false
    );
  end if;

  if v_intent.status not in ('DISPATCH_ACCEPTED','RUNNING')
     or v_intent.provider_run_id is distinct from p_provider_run_id
     or v_intent.provider_run_attempt is distinct from p_provider_run_attempt then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_RECOVERY_STALE';
  end if;

  if v_intent.status='RUNNING' then
    select * into v_execution
    from public.website_delivery_pdf_conversion_executions
    where task_id=p_task_id for update;
    if not found or v_execution.workflow_run_id <> p_provider_run_id
       or v_execution.workflow_run_attempt <> p_provider_run_attempt
       or v_execution.completed_at is not null or v_execution.view_derivative_id is not null then
      raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_RECOVERY_STALE';
    end if;
    if v_execution.expires_at > clock_timestamp() then
      raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_RECOVERY_LEASE_ACTIVE';
    end if;
    if v_execution.claimed_by like 'PDF_ORPHAN_CLEANUP:CLAIM:%'
       or v_execution.claimed_by like 'PDF_ORPHAN_CLEANUP:STAGED:%' then
      raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_RECOVERY_NOT_ALLOWED';
    end if;

    select * into v_task from public.website_delivery_pdf_conversion_tasks where task_id=p_task_id;
    select * into v_artifact from public.website_delivery_document_artifacts
    where artifact_id=v_task.artifact_id;
    if v_task.task_id is null or v_artifact.artifact_id is null
       or v_artifact.docx_sha256 <> v_task.source_docx_sha256 then
      raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_SOURCE_STALE';
    end if;
    select current_state into v_state
    from public.commercial_projects where project_id=v_task.project_id for update;
    if v_state <> 'M2_PAYMENT_RECEIVED' then
      raise exception using errcode='P0001',message='WEBSITE_DELIVERY_STATE_INVALID';
    end if;
    if exists (select 1 from public.website_delivery_document_acceptances
      where project_id=v_task.project_id) then
      raise exception using errcode='P0001',message='WEBSITE_DELIVERY_ALREADY_ACCEPTED';
    end if;
    if not exists (select 1 from public.preview_versions
      where preview_version_id=v_task.preview_version_id
        and project_id=v_task.project_id and status='CURRENT') then
      raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_SOURCE_STALE';
    end if;
    if exists (select 1 from public.website_delivery_document_view_derivatives
      where artifact_id=v_task.artifact_id) then
      raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_VIEW_ALREADY_REGISTERED';
    end if;
    select metadata into v_metadata from storage.objects
    where bucket_id=v_artifact.storage_bucket_id and name=v_artifact.storage_object_path;
    if not found or coalesce(v_metadata->>'mimetype','') <> v_artifact.content_type
       or coalesce(v_metadata->>'size','') !~ '^[0-9]+$'
       or (v_metadata->>'size')::bigint <> v_artifact.docx_bytes then
      raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_SOURCE_OBJECT_INVALID';
    end if;
  end if;

  insert into public.website_delivery_pdf_recovery_intents(
    recovery_id,task_id,dispatch_attempt_id,provider_run_id,
    approved_run_attempt,provider_status,provider_conclusion,status,
    result_code,provider_checked_at,actor
  ) values (
    p_approval_id,p_task_id,p_expected_dispatch_attempt_id,p_provider_run_id,
    p_provider_run_attempt,p_provider_status,p_provider_conclusion,'RERUN_UNKNOWN',
    'RERUN_OUTCOME_UNKNOWN',p_provider_checked_at,btrim(p_actor)
  ) returning * into v_recovery;

  return jsonb_build_object(
    'task_id',v_recovery.task_id,'dispatch_attempt_id',v_recovery.dispatch_attempt_id,
    'recovery_id',v_recovery.recovery_id,'recovery_status',v_recovery.status,
    'result_code',v_recovery.result_code,'should_rerun',true
  );
end;
$$;

create or replace function public.get_website_delivery_pdf_operator_status_v1(
  p_project_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_task public.website_delivery_pdf_conversion_tasks%rowtype;
  v_intent public.website_delivery_pdf_dispatch_intents%rowtype;
  v_recovery public.website_delivery_pdf_recovery_intents%rowtype;
  v_execution public.website_delivery_pdf_conversion_executions%rowtype;
  v_allowed_action text;
begin
  if p_project_id is null then
    raise exception using errcode='22023',message='WEBSITE_DELIVERY_PDF_STATUS_INPUT_INVALID';
  end if;
  select * into v_task from public.website_delivery_pdf_conversion_tasks
  where project_id=p_project_id order by document_version desc,created_at desc limit 1;
  if not found then
    return jsonb_build_object(
      'project_id',p_project_id,'task_id',null,'document_version',null,
      'status','NOT_CREATED','result_code','PDF_TASK_NOT_CREATED',
      'dispatch_attempt',null,'dispatch_attempt_id',null,'provider_run_id',null,
      'provider_run_attempt',null,'created_at',null,'dispatch_started_at',null,
      'dispatch_finished_at',null,'provider_checked_at',null,'running_at',null,
      'completed_at',null,'recovery_id',null,'recovery_status',null,
      'recovery_result_code',null,'recovery_approved_at',null,
      'rerun_started_at',null,'rerun_finished_at',null,'allowed_action','NONE'
    );
  end if;
  select * into v_intent from public.website_delivery_pdf_dispatch_intents
  where task_id=v_task.task_id;
  if not found then
    return jsonb_build_object(
      'project_id',p_project_id,'task_id',v_task.task_id,
      'document_version',v_task.document_version,'status','NOT_STARTED',
      'result_code','PDF_DISPATCH_NOT_STARTED','dispatch_attempt',null,
      'dispatch_attempt_id',null,'provider_run_id',null,'provider_run_attempt',null,
      'created_at',v_task.created_at,'dispatch_started_at',null,
      'dispatch_finished_at',null,'provider_checked_at',null,'running_at',null,
      'completed_at',null,'recovery_id',null,'recovery_status',null,
      'recovery_result_code',null,'recovery_approved_at',null,
      'rerun_started_at',null,'rerun_finished_at',null,'allowed_action','NONE'
    );
  end if;
  select * into v_recovery from public.website_delivery_pdf_recovery_intents
  where task_id=v_task.task_id and dispatch_attempt_id=v_intent.dispatch_attempt_id;
  select * into v_execution from public.website_delivery_pdf_conversion_executions
  where task_id=v_task.task_id;
  v_allowed_action := case
    when v_recovery.recovery_id is not null and v_recovery.status='RERUN_UNKNOWN'
      then 'INSPECT_PROVIDER'
    when v_recovery.recovery_id is not null
      and v_recovery.status in ('RERUN_ACCEPTED','RUNNING') then 'WAIT_FOR_RERUN'
    when v_intent.status='RUNNING' and v_execution.execution_id is not null
      and v_execution.completed_at is null and v_execution.view_derivative_id is null
      and v_execution.expires_at <= clock_timestamp()
      and v_execution.claimed_by not like 'PDF_ORPHAN_CLEANUP:CLAIM:%'
      and v_execution.claimed_by not like 'PDF_ORPHAN_CLEANUP:STAGED:%'
      then 'INSPECT_PROVIDER'
    when v_intent.status in ('DISPATCH_UNKNOWN','DISPATCH_ACCEPTED')
      then 'INSPECT_PROVIDER'
    else 'NONE'
  end;
  return jsonb_build_object(
    'project_id',p_project_id,'task_id',v_task.task_id,
    'document_version',v_task.document_version,'status',v_intent.status,
    'result_code',v_intent.result_code,'dispatch_attempt',v_intent.dispatch_attempt,
    'dispatch_attempt_id',v_intent.dispatch_attempt_id,
    'provider_run_id',v_intent.provider_run_id,
    'provider_run_attempt',v_intent.provider_run_attempt,
    'created_at',v_intent.created_at,'dispatch_started_at',v_intent.dispatch_started_at,
    'dispatch_finished_at',v_intent.dispatch_finished_at,
    'provider_checked_at',v_intent.provider_checked_at,
    'running_at',v_intent.running_at,'completed_at',v_intent.completed_at,
    'recovery_id',case when v_recovery.recovery_id is not null then v_recovery.recovery_id else null end,
    'recovery_status',case when v_recovery.recovery_id is not null then v_recovery.status else null end,
    'recovery_result_code',case when v_recovery.recovery_id is not null then v_recovery.result_code else null end,
    'recovery_approved_at',case when v_recovery.recovery_id is not null then v_recovery.approved_at else null end,
    'rerun_started_at',case when v_recovery.recovery_id is not null then v_recovery.rerun_started_at else null end,
    'rerun_finished_at',case when v_recovery.recovery_id is not null then v_recovery.rerun_finished_at else null end,
    'allowed_action',v_allowed_action
  );
end;
$$;

revoke all on function public.reconcile_website_delivery_pdf_rerun_unknown_v1(
  uuid,uuid,text,integer,text,text,timestamptz,text
) from public,anon,authenticated,service_role;
grant execute on function public.reconcile_website_delivery_pdf_rerun_unknown_v1(
  uuid,uuid,text,integer,text,text,timestamptz,text
) to service_role;

revoke all on function public.claim_website_delivery_pdf_rerun_v1(
  uuid,uuid,text,integer,text,text,uuid,timestamptz,text
) from public,anon,authenticated,service_role;
grant execute on function public.claim_website_delivery_pdf_rerun_v1(
  uuid,uuid,text,integer,text,text,uuid,timestamptz,text
) to service_role;

revoke all on function public.get_website_delivery_pdf_dispatch_status_v1(uuid)
from public,anon,authenticated,service_role;
grant execute on function public.get_website_delivery_pdf_dispatch_status_v1(uuid)
to service_role;

revoke all on function public.get_website_delivery_pdf_operator_status_v1(uuid)
from public,anon,authenticated,service_role;
grant execute on function public.get_website_delivery_pdf_operator_status_v1(uuid)
to service_role;