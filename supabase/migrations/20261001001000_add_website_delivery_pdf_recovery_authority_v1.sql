create unique index website_delivery_pdf_dispatch_task_attempt_unique
on public.website_delivery_pdf_dispatch_intents(task_id, dispatch_attempt_id);

create table public.website_delivery_pdf_recovery_intents (
  recovery_id uuid primary key,
  task_id uuid not null,
  dispatch_attempt_id uuid not null,
  provider_run_id text not null check (provider_run_id ~ '^[1-9][0-9]*$'),
  approved_run_attempt integer not null check (approved_run_attempt > 0),
  observed_run_attempt integer check (observed_run_attempt is null or observed_run_attempt > approved_run_attempt),
  provider_status text not null check (provider_status = 'completed'),
  provider_conclusion text not null check (provider_conclusion in (
    'action_required','cancelled','failure','stale','startup_failure','timed_out'
  )),
  status text not null check (status in (
    'RERUN_UNKNOWN','RERUN_ACCEPTED','RERUN_FAILED','RUNNING','COMPLETED'
  )),
  result_code text not null check (result_code ~ '^[A-Z][A-Z0-9_]{0,99}$'),
  provider_checked_at timestamptz not null,
  approved_at timestamptz not null default clock_timestamp(),
  rerun_started_at timestamptz not null default clock_timestamp(),
  rerun_finished_at timestamptz,
  running_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  actor text not null check (nullif(btrim(actor), '') is not null),
  unique(task_id, dispatch_attempt_id),
  foreign key(task_id, dispatch_attempt_id)
    references public.website_delivery_pdf_dispatch_intents(task_id, dispatch_attempt_id)
);

alter table public.website_delivery_pdf_recovery_intents enable row level security;
alter table public.website_delivery_pdf_recovery_intents force row level security;
revoke all on table public.website_delivery_pdf_recovery_intents
from public, anon, authenticated, service_role;

create function public.claim_website_delivery_pdf_rerun_v1(
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
set search_path = public, pg_catalog
as $$
declare
  v_intent public.website_delivery_pdf_dispatch_intents%rowtype;
  v_recovery public.website_delivery_pdf_recovery_intents%rowtype;
begin
  if p_task_id is null or p_expected_dispatch_attempt_id is null
     or p_provider_run_id !~ '^[1-9][0-9]*$'
     or p_provider_run_attempt is null or p_provider_run_attempt <= 0
     or p_provider_status <> 'completed'
     or p_provider_conclusion not in (
       'action_required','cancelled','failure','stale','startup_failure','timed_out'
     )
     or p_approval_id is null or p_provider_checked_at is null
     or p_provider_checked_at > clock_timestamp() + interval '1 minute'
     or p_provider_checked_at < clock_timestamp() - interval '10 minutes'
     or nullif(btrim(p_actor), '') is null or length(p_actor) > 200 then
    raise exception using
      errcode = '22023',
      message = 'WEBSITE_DELIVERY_PDF_RECOVERY_INPUT_INVALID';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_task_id::text, 0));
  select * into v_intent
  from public.website_delivery_pdf_dispatch_intents
  where task_id = p_task_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_DELIVERY_PDF_DISPATCH_NOT_FOUND';
  end if;
  if v_intent.dispatch_attempt_id <> p_expected_dispatch_attempt_id
     or v_intent.status <> 'DISPATCH_ACCEPTED'
     or v_intent.provider_run_id is distinct from p_provider_run_id
     or v_intent.provider_run_attempt is distinct from p_provider_run_attempt then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_DELIVERY_PDF_RECOVERY_STALE';
  end if;

  select * into v_recovery
  from public.website_delivery_pdf_recovery_intents
  where task_id = p_task_id and dispatch_attempt_id = p_expected_dispatch_attempt_id
  for update;
  if found then
    if v_recovery.recovery_id <> p_approval_id then
      raise exception using
        errcode = 'P0001',
        message = 'WEBSITE_DELIVERY_PDF_RECOVERY_ALREADY_CLAIMED';
    end if;
    if v_recovery.provider_run_id <> p_provider_run_id
       or v_recovery.approved_run_attempt <> p_provider_run_attempt
       or v_recovery.provider_status <> p_provider_status
       or v_recovery.provider_conclusion <> p_provider_conclusion then
      raise exception using
        errcode = 'P0001',
        message = 'WEBSITE_DELIVERY_PDF_RECOVERY_STALE';
    end if;
    return jsonb_build_object(
      'task_id',v_recovery.task_id,
      'dispatch_attempt_id',v_recovery.dispatch_attempt_id,
      'recovery_id',v_recovery.recovery_id,
      'recovery_status',v_recovery.status,
      'result_code',v_recovery.result_code,
      'should_rerun',false
    );
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
    'task_id',v_recovery.task_id,
    'dispatch_attempt_id',v_recovery.dispatch_attempt_id,
    'recovery_id',v_recovery.recovery_id,
    'recovery_status',v_recovery.status,
    'result_code',v_recovery.result_code,
    'should_rerun',true
  );
end;
$$;

create function public.record_website_delivery_pdf_rerun_result_v1(
  p_task_id uuid,
  p_approval_id uuid,
  p_status text,
  p_result_code text,
  p_actor text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_recovery public.website_delivery_pdf_recovery_intents%rowtype;
begin
  if p_task_id is null or p_approval_id is null
     or p_status not in ('RERUN_ACCEPTED','RERUN_FAILED','RERUN_UNKNOWN')
     or p_result_code !~ '^[A-Z][A-Z0-9_]{0,99}$'
     or nullif(btrim(p_actor), '') is null or length(p_actor) > 200 then
    raise exception using
      errcode = '22023',
      message = 'WEBSITE_DELIVERY_PDF_RECOVERY_RESULT_INVALID';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_task_id::text, 0));
  select * into v_recovery
  from public.website_delivery_pdf_recovery_intents
  where task_id = p_task_id and recovery_id = p_approval_id
  for update;
  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_DELIVERY_PDF_RECOVERY_BINDING_INVALID';
  end if;
  if v_recovery.status = p_status and v_recovery.result_code = p_result_code then
    return jsonb_build_object(
      'task_id',v_recovery.task_id,'recovery_id',v_recovery.recovery_id,
      'recovery_status',v_recovery.status,'result_code',v_recovery.result_code
    );
  end if;
  if v_recovery.status <> 'RERUN_UNKNOWN' then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_DELIVERY_PDF_RECOVERY_STATE_INVALID';
  end if;

  update public.website_delivery_pdf_recovery_intents
  set status = p_status,
      result_code = p_result_code,
      rerun_finished_at = clock_timestamp(),
      updated_at = clock_timestamp(),
      actor = btrim(p_actor)
  where task_id = p_task_id and recovery_id = p_approval_id
  returning * into v_recovery;

  return jsonb_build_object(
    'task_id',v_recovery.task_id,'recovery_id',v_recovery.recovery_id,
    'recovery_status',v_recovery.status,'result_code',v_recovery.result_code
  );
end;
$$;

create function public.get_website_delivery_pdf_operator_status_v1(
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
  v_allowed_action text;
begin
  if p_project_id is null then
    raise exception using
      errcode = '22023',
      message = 'WEBSITE_DELIVERY_PDF_STATUS_INPUT_INVALID';
  end if;

  select * into v_task
  from public.website_delivery_pdf_conversion_tasks
  where project_id = p_project_id
  order by document_version desc, created_at desc
  limit 1;
  if not found then
    return jsonb_build_object(
      'project_id',p_project_id,'task_id',null,'document_version',null,
      'status','NOT_CREATED','result_code','PDF_TASK_NOT_CREATED',
      'dispatch_attempt',null,'dispatch_attempt_id',null,
      'provider_run_id',null,'provider_run_attempt',null,
      'created_at',null,'dispatch_started_at',null,'dispatch_finished_at',null,
      'provider_checked_at',null,'running_at',null,'completed_at',null,
      'recovery_id',null,'recovery_status',null,'recovery_result_code',null,
      'recovery_approved_at',null,'rerun_started_at',null,
      'rerun_finished_at',null,'allowed_action','NONE'
    );
  end if;

  select * into v_intent
  from public.website_delivery_pdf_dispatch_intents
  where task_id = v_task.task_id;
  if not found then
    return jsonb_build_object(
      'project_id',p_project_id,'task_id',v_task.task_id,
      'document_version',v_task.document_version,'status','NOT_STARTED',
      'result_code','PDF_DISPATCH_NOT_STARTED','dispatch_attempt',null,
      'dispatch_attempt_id',null,'provider_run_id',null,
      'provider_run_attempt',null,'created_at',v_task.created_at,
      'dispatch_started_at',null,'dispatch_finished_at',null,
      'provider_checked_at',null,'running_at',null,'completed_at',null,
      'recovery_id',null,'recovery_status',null,'recovery_result_code',null,
      'recovery_approved_at',null,'rerun_started_at',null,
      'rerun_finished_at',null,'allowed_action','NONE'
    );
  end if;

  select * into v_recovery
  from public.website_delivery_pdf_recovery_intents
  where task_id = v_task.task_id and dispatch_attempt_id = v_intent.dispatch_attempt_id;
  v_allowed_action := case
    when found and v_recovery.status in ('RERUN_UNKNOWN','RERUN_ACCEPTED') then 'WAIT_FOR_RERUN'
    when v_intent.status in ('DISPATCH_UNKNOWN','DISPATCH_ACCEPTED') then 'INSPECT_PROVIDER'
    else 'NONE'
  end;

  return jsonb_build_object(
    'project_id',p_project_id,'task_id',v_task.task_id,
    'document_version',v_task.document_version,'status',v_intent.status,
    'result_code',v_intent.result_code,
    'dispatch_attempt',v_intent.dispatch_attempt,
    'dispatch_attempt_id',v_intent.dispatch_attempt_id,
    'provider_run_id',v_intent.provider_run_id,
    'provider_run_attempt',v_intent.provider_run_attempt,
    'created_at',v_intent.created_at,
    'dispatch_started_at',v_intent.dispatch_started_at,
    'dispatch_finished_at',v_intent.dispatch_finished_at,
    'provider_checked_at',v_intent.provider_checked_at,
    'running_at',v_intent.running_at,'completed_at',v_intent.completed_at,
    'recovery_id',case when found then v_recovery.recovery_id else null end,
    'recovery_status',case when found then v_recovery.status else null end,
    'recovery_result_code',case when found then v_recovery.result_code else null end,
    'recovery_approved_at',case when found then v_recovery.approved_at else null end,
    'rerun_started_at',case when found then v_recovery.rerun_started_at else null end,
    'rerun_finished_at',case when found then v_recovery.rerun_finished_at else null end,
    'allowed_action',v_allowed_action
  );
end;
$$;

create or replace function public.sync_website_delivery_pdf_dispatch_execution_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  update public.website_delivery_pdf_dispatch_intents
  set status = case when new.completed_at is null then 'RUNNING' else 'COMPLETED' end,
      result_code = case when new.completed_at is null
        then 'WORKFLOW_RUNNING' else 'WORKFLOW_COMPLETED' end,
      provider_run_id = new.workflow_run_id,
      provider_run_attempt = new.workflow_run_attempt,
      running_at = coalesce(running_at, new.claimed_at),
      completed_at = case when new.completed_at is null then completed_at else new.completed_at end,
      updated_at = clock_timestamp()
  where task_id = new.task_id;

  update public.website_delivery_pdf_recovery_intents
  set status = case when new.completed_at is null then 'RUNNING' else 'COMPLETED' end,
      result_code = case when new.completed_at is null
        then 'WORKFLOW_RERUN_RUNNING' else 'WORKFLOW_RERUN_COMPLETED' end,
      observed_run_attempt = new.workflow_run_attempt,
      running_at = coalesce(running_at, new.claimed_at),
      completed_at = case when new.completed_at is null then completed_at else new.completed_at end,
      updated_at = clock_timestamp()
  where task_id = new.task_id
    and provider_run_id = new.workflow_run_id
    and new.workflow_run_attempt > approved_run_attempt;
  return new;
end;
$$;

revoke all on function public.claim_website_delivery_pdf_rerun_v1(
  uuid,uuid,text,integer,text,text,uuid,timestamptz,text
) from public, anon, authenticated, service_role;
grant execute on function public.claim_website_delivery_pdf_rerun_v1(
  uuid,uuid,text,integer,text,text,uuid,timestamptz,text
) to service_role;

revoke all on function public.record_website_delivery_pdf_rerun_result_v1(
  uuid,uuid,text,text,text
) from public, anon, authenticated, service_role;
grant execute on function public.record_website_delivery_pdf_rerun_result_v1(
  uuid,uuid,text,text,text
) to service_role;

revoke all on function public.get_website_delivery_pdf_operator_status_v1(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_website_delivery_pdf_operator_status_v1(uuid)
to service_role;

revoke all on function public.sync_website_delivery_pdf_dispatch_execution_v1()
from public, anon, authenticated, service_role;

comment on table public.website_delivery_pdf_recovery_intents is
  'C2-H2 durable authority for at most one explicitly approved rerun of the exact current GitHub workflow run.';