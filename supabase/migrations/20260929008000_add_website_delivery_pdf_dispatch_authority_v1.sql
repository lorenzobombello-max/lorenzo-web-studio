create table public.website_delivery_pdf_dispatch_intents (
  task_id uuid primary key references public.website_delivery_pdf_conversion_tasks(task_id),
  artifact_id uuid not null unique references public.website_delivery_document_artifacts(artifact_id),
  status text not null check (status in (
    'DISPATCH_UNKNOWN','DISPATCH_ACCEPTED','DISPATCH_FAILED','RETRY_APPROVED','RUNNING','COMPLETED'
  )),
  dispatch_attempt integer not null check (dispatch_attempt between 1 and 2),
  dispatch_attempt_id uuid not null unique,
  result_code text not null check (result_code ~ '^[A-Z][A-Z0-9_]{0,99}$'),
  provider_run_id text check (provider_run_id is null or provider_run_id ~ '^[1-9][0-9]*$'),
  provider_run_attempt integer check (provider_run_attempt is null or provider_run_attempt > 0),
  provider_checked_at timestamptz,
  reconciliation_id uuid unique,
  created_at timestamptz not null default clock_timestamp(),
  dispatch_started_at timestamptz not null default clock_timestamp(),
  dispatch_finished_at timestamptz,
  running_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  actor text not null check (nullif(btrim(actor),'') is not null),
  constraint website_delivery_pdf_dispatch_run_pair check (
    (provider_run_id is null and provider_run_attempt is null)
    or provider_run_id is not null
  )
);

alter table public.website_delivery_pdf_dispatch_intents enable row level security;
alter table public.website_delivery_pdf_dispatch_intents force row level security;
revoke all on table public.website_delivery_pdf_dispatch_intents
from public, anon, authenticated, service_role;

create function public.get_website_delivery_pdf_dispatch_status_v1(p_task_id uuid)
returns jsonb
language plpgsql security definer set search_path=public,pg_catalog as $$
declare v_intent public.website_delivery_pdf_dispatch_intents%rowtype;
begin
  if p_task_id is null then
    raise exception using errcode='22023',message='WEBSITE_DELIVERY_PDF_DISPATCH_INPUT_INVALID';
  end if;
  select * into v_intent from public.website_delivery_pdf_dispatch_intents where task_id=p_task_id;
  if not found then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_DISPATCH_NOT_FOUND';
  end if;
  return jsonb_build_object(
    'task_id',v_intent.task_id,'artifact_id',v_intent.artifact_id,'status',v_intent.status,
    'dispatch_attempt',v_intent.dispatch_attempt,'dispatch_attempt_id',v_intent.dispatch_attempt_id,
    'result_code',v_intent.result_code,'provider_run_id',v_intent.provider_run_id,
    'provider_run_attempt',v_intent.provider_run_attempt,
    'provider_checked_at',v_intent.provider_checked_at,'created_at',v_intent.created_at,
    'dispatch_started_at',v_intent.dispatch_started_at,
    'dispatch_finished_at',v_intent.dispatch_finished_at,
    'running_at',v_intent.running_at,'completed_at',v_intent.completed_at,
    'updated_at',v_intent.updated_at
  );
end;
$$;

create function public.claim_website_delivery_pdf_dispatch_v1(p_task_id uuid,p_actor text)
returns jsonb
language plpgsql security definer set search_path=public,pg_catalog as $$
declare
  v_task public.website_delivery_pdf_conversion_tasks%rowtype;
  v_intent public.website_delivery_pdf_dispatch_intents%rowtype;
  v_should_dispatch boolean:=false;
begin
  if p_task_id is null or nullif(btrim(p_actor),'') is null or length(p_actor)>200 then
    raise exception using errcode='22023',message='WEBSITE_DELIVERY_PDF_DISPATCH_INPUT_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_task_id::text,0));
  select * into v_task from public.website_delivery_pdf_conversion_tasks where task_id=p_task_id;
  if not found then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_TASK_NOT_FOUND';
  end if;
  select * into v_intent from public.website_delivery_pdf_dispatch_intents
  where task_id=p_task_id for update;
  if not found then
    insert into public.website_delivery_pdf_dispatch_intents(
      task_id,artifact_id,status,dispatch_attempt,dispatch_attempt_id,result_code,actor
    ) values (
      v_task.task_id,v_task.artifact_id,'DISPATCH_UNKNOWN',1,gen_random_uuid(),
      'DISPATCH_OUTCOME_UNKNOWN',btrim(p_actor)
    ) returning * into v_intent;
    v_should_dispatch:=true;
  elsif v_intent.status='RETRY_APPROVED' then
    if v_intent.dispatch_attempt<>1 then
      raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_DISPATCH_RECONCILIATION_EXHAUSTED';
    end if;
    update public.website_delivery_pdf_dispatch_intents
    set status='DISPATCH_UNKNOWN',dispatch_attempt=2,dispatch_attempt_id=gen_random_uuid(),
        result_code='DISPATCH_OUTCOME_UNKNOWN',dispatch_started_at=clock_timestamp(),
        dispatch_finished_at=null,provider_run_id=null,provider_run_attempt=null,
        updated_at=clock_timestamp(),actor=btrim(p_actor)
    where task_id=p_task_id returning * into v_intent;
    v_should_dispatch:=true;
  end if;
  return public.get_website_delivery_pdf_dispatch_status_v1(p_task_id)
    ||jsonb_build_object('should_dispatch',v_should_dispatch);
end;
$$;

create function public.record_website_delivery_pdf_dispatch_result_v1(
  p_task_id uuid,p_dispatch_attempt_id uuid,p_status text,p_result_code text,p_actor text
) returns jsonb
language plpgsql security definer set search_path=public,pg_catalog as $$
declare v_intent public.website_delivery_pdf_dispatch_intents%rowtype;
begin
  if p_task_id is null or p_dispatch_attempt_id is null
     or p_status not in ('DISPATCH_ACCEPTED','DISPATCH_FAILED','DISPATCH_UNKNOWN')
     or p_result_code !~ '^[A-Z][A-Z0-9_]{0,99}$'
     or nullif(btrim(p_actor),'') is null or length(p_actor)>200 then
    raise exception using errcode='22023',message='WEBSITE_DELIVERY_PDF_DISPATCH_RESULT_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_task_id::text,0));
  select * into v_intent from public.website_delivery_pdf_dispatch_intents
  where task_id=p_task_id for update;
  if not found or v_intent.dispatch_attempt_id<>p_dispatch_attempt_id then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_DISPATCH_BINDING_INVALID';
  end if;
  if v_intent.status in ('RUNNING','COMPLETED') then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_DISPATCH_STATE_INVALID';
  end if;
  if v_intent.status=p_status and v_intent.result_code=p_result_code then
    return public.get_website_delivery_pdf_dispatch_status_v1(p_task_id);
  end if;
  if v_intent.status<>'DISPATCH_UNKNOWN' then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_DISPATCH_STATE_INVALID';
  end if;
  update public.website_delivery_pdf_dispatch_intents
  set status=p_status,result_code=p_result_code,dispatch_finished_at=clock_timestamp(),
      updated_at=clock_timestamp(),actor=btrim(p_actor)
  where task_id=p_task_id;
  return public.get_website_delivery_pdf_dispatch_status_v1(p_task_id);
end;
$$;

create function public.reconcile_website_delivery_pdf_dispatch_unknown_v1(
  p_task_id uuid,p_provider_run_id text,p_provider_run_attempt integer,p_provider_checked_at timestamptz,
  p_reconciliation_id uuid,p_approved boolean,p_actor text
) returns jsonb
language plpgsql security definer set search_path=public,pg_catalog as $$
declare v_intent public.website_delivery_pdf_dispatch_intents%rowtype;
begin
  if p_task_id is null or p_reconciliation_id is null or p_provider_checked_at is null
     or p_provider_checked_at>clock_timestamp()+interval '1 minute'
     or p_provider_checked_at<clock_timestamp()-interval '10 minutes'
     or (p_provider_run_id is not null and p_provider_run_id!~'^[1-9][0-9]*$')
    or (p_provider_run_id is null)<>(p_provider_run_attempt is null)
    or (p_provider_run_attempt is not null and p_provider_run_attempt<=0)
     or p_approved is null or nullif(btrim(p_actor),'') is null or length(p_actor)>200 then
    raise exception using errcode='22023',message='WEBSITE_DELIVERY_PDF_DISPATCH_RECONCILIATION_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_task_id::text,0));
  select * into v_intent from public.website_delivery_pdf_dispatch_intents
  where task_id=p_task_id for update;
  if not found then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_DISPATCH_NOT_FOUND';
  end if;
  if v_intent.reconciliation_id=p_reconciliation_id then
     if v_intent.provider_run_id is distinct from p_provider_run_id
       or v_intent.provider_run_attempt is distinct from p_provider_run_attempt then
      raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_DISPATCH_BINDING_INVALID';
    end if;
    return public.get_website_delivery_pdf_dispatch_status_v1(p_task_id);
  end if;
  if v_intent.status<>'DISPATCH_UNKNOWN' then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_DISPATCH_STATE_INVALID';
  end if;
  if p_provider_run_id is null and not p_approved then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_DISPATCH_APPROVAL_REQUIRED';
  end if;
  if p_provider_run_id is null and v_intent.dispatch_attempt>=2 then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_DISPATCH_RECONCILIATION_EXHAUSTED';
  end if;
  update public.website_delivery_pdf_dispatch_intents
  set status=case when p_provider_run_id is null then 'RETRY_APPROVED' else 'DISPATCH_ACCEPTED' end,
      result_code=case when p_provider_run_id is null then 'DISPATCH_RETRY_APPROVED' else 'DISPATCH_RUN_FOUND' end,
      provider_run_id=p_provider_run_id,provider_run_attempt=p_provider_run_attempt,
      provider_checked_at=p_provider_checked_at,
      reconciliation_id=p_reconciliation_id,dispatch_finished_at=clock_timestamp(),
      updated_at=clock_timestamp(),actor=btrim(p_actor)
  where task_id=p_task_id;
  return public.get_website_delivery_pdf_dispatch_status_v1(p_task_id);
end;
$$;

create function public.sync_website_delivery_pdf_dispatch_execution_v1()
returns trigger
language plpgsql security definer set search_path=public,pg_catalog as $$
begin
  update public.website_delivery_pdf_dispatch_intents
  set status=case when new.completed_at is null then 'RUNNING' else 'COMPLETED' end,
      result_code=case when new.completed_at is null
        then 'WORKFLOW_RUNNING' else 'WORKFLOW_COMPLETED' end,
      provider_run_id=new.workflow_run_id,
      provider_run_attempt=new.workflow_run_attempt,
      running_at=coalesce(running_at,new.claimed_at),
      completed_at=case when new.completed_at is null then completed_at else new.completed_at end,
      updated_at=clock_timestamp()
  where task_id=new.task_id;
  return new;
end;
$$;

create trigger sync_website_delivery_pdf_dispatch_execution_insert_v1
after insert on public.website_delivery_pdf_conversion_executions
for each row execute function public.sync_website_delivery_pdf_dispatch_execution_v1();
create trigger sync_website_delivery_pdf_dispatch_execution_update_v1
after update of execution_id,workflow_run_attempt,completed_at
on public.website_delivery_pdf_conversion_executions
for each row execute function public.sync_website_delivery_pdf_dispatch_execution_v1();

revoke all on function public.sync_website_delivery_pdf_dispatch_execution_v1()
from public,anon,authenticated,service_role;

revoke all on function public.claim_website_delivery_pdf_dispatch_v1(uuid,text)
from public,anon,authenticated,service_role;
grant execute on function public.claim_website_delivery_pdf_dispatch_v1(uuid,text) to service_role;
revoke all on function public.record_website_delivery_pdf_dispatch_result_v1(uuid,uuid,text,text,text)
from public,anon,authenticated,service_role;
grant execute on function public.record_website_delivery_pdf_dispatch_result_v1(uuid,uuid,text,text,text) to service_role;
revoke all on function public.reconcile_website_delivery_pdf_dispatch_unknown_v1(uuid,text,integer,timestamptz,uuid,boolean,text)
from public,anon,authenticated,service_role;
grant execute on function public.reconcile_website_delivery_pdf_dispatch_unknown_v1(uuid,text,integer,timestamptz,uuid,boolean,text) to service_role;
revoke all on function public.get_website_delivery_pdf_dispatch_status_v1(uuid)
from public,anon,authenticated,service_role;
grant execute on function public.get_website_delivery_pdf_dispatch_status_v1(uuid) to service_role;

comment on table public.website_delivery_pdf_dispatch_intents is
  'C2 durable fail-closed authority for one automatic GitHub workflow dispatch per immutable PDF task.';