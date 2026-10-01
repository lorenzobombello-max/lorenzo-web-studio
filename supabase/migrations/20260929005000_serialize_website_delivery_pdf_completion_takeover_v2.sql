-- W2.4.1-PDF completion/takeover repair: claim and completion now acquire the same
-- task advisory lock before their execution/project row locks. This prevents the
-- inverse execution -> project versus project -> execution deadlock without changing
-- immutable task/document bindings, lease rules, replay rules or table schemas.

create or replace function public.complete_website_delivery_pdf_conversion_v2(
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
  v_task_id uuid;
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

  select task_id into v_task_id
  from public.website_delivery_pdf_conversion_executions
  where execution_id = p_execution_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_EXECUTION_BINDING_INVALID';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_task_id::text, 0));
  select * into v_execution
  from public.website_delivery_pdf_conversion_executions
  where execution_id = p_execution_id for update;
  if not found or v_execution.task_id <> v_task_id
     or v_execution.workflow_run_id <> p_workflow_run_id
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

revoke all on function public.complete_website_delivery_pdf_conversion_v2(uuid,text,integer,char,bigint,uuid,text)
from public, anon, authenticated, service_role;
grant execute on function public.complete_website_delivery_pdf_conversion_v2(uuid,text,integer,char,bigint,uuid,text)
to service_role;

comment on function public.complete_website_delivery_pdf_conversion_v2(uuid,text,integer,char,bigint,uuid,text) is
  'Completes only the current execution/run/run_attempt; serialized with claim/takeover by the task advisory lock before execution, project, view-registration and acceptance interlocks.';