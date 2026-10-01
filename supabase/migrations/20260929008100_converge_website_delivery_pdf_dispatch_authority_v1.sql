do $$
declare
  v_legacy_oid oid := to_regprocedure(
    'public.reconcile_website_delivery_pdf_dispatch_unknown_v1(uuid,text,timestamptz,uuid,boolean,text)'
  );
  v_dependents text;
begin
  if v_legacy_oid is null then
    return;
  end if;

  select string_agg(
    pg_describe_object(dependency.classid, dependency.objid, dependency.objsubid),
    ', ' order by pg_describe_object(
      dependency.classid,
      dependency.objid,
      dependency.objsubid
    )
  )
  into v_dependents
  from pg_depend dependency
  where dependency.refclassid = 'pg_proc'::regclass
    and dependency.refobjid = v_legacy_oid;

  if v_dependents is not null then
    raise exception using
      errcode = '2BP01',
      message = 'WEBSITE_DELIVERY_PDF_DISPATCH_LEGACY_DEPENDENCY',
      detail = v_dependents;
  end if;
end;
$$;

drop function if exists public.reconcile_website_delivery_pdf_dispatch_unknown_v1(
  uuid,text,timestamptz,uuid,boolean,text
);

create or replace function public.reconcile_website_delivery_pdf_dispatch_unknown_v1(
  p_task_id uuid,
  p_provider_run_id text,
  p_provider_run_attempt integer,
  p_provider_checked_at timestamptz,
  p_reconciliation_id uuid,
  p_approved boolean,
  p_actor text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_intent public.website_delivery_pdf_dispatch_intents%rowtype;
begin
  if p_task_id is null or p_reconciliation_id is null
     or p_provider_checked_at is null
     or p_provider_checked_at > clock_timestamp() + interval '1 minute'
     or p_provider_checked_at < clock_timestamp() - interval '10 minutes'
     or (p_provider_run_id is not null and p_provider_run_id !~ '^[1-9][0-9]*$')
     or (p_provider_run_id is null) <> (p_provider_run_attempt is null)
     or (p_provider_run_attempt is not null and p_provider_run_attempt <= 0)
     or p_approved is null or nullif(btrim(p_actor), '') is null
     or length(p_actor) > 200 then
    raise exception using
      errcode = '22023',
      message = 'WEBSITE_DELIVERY_PDF_DISPATCH_RECONCILIATION_INVALID';
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
  if v_intent.reconciliation_id = p_reconciliation_id then
    if v_intent.provider_run_id is distinct from p_provider_run_id
       or v_intent.provider_run_attempt is distinct from p_provider_run_attempt then
      raise exception using
        errcode = 'P0001',
        message = 'WEBSITE_DELIVERY_PDF_DISPATCH_BINDING_INVALID';
    end if;
    return public.get_website_delivery_pdf_dispatch_status_v1(p_task_id);
  end if;
  if v_intent.status <> 'DISPATCH_UNKNOWN' then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_DELIVERY_PDF_DISPATCH_STATE_INVALID';
  end if;
  if p_provider_run_id is null and not p_approved then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_DELIVERY_PDF_DISPATCH_APPROVAL_REQUIRED';
  end if;
  if p_provider_run_id is null and v_intent.dispatch_attempt >= 2 then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_DELIVERY_PDF_DISPATCH_RECONCILIATION_EXHAUSTED';
  end if;

  update public.website_delivery_pdf_dispatch_intents
  set status = case
        when p_provider_run_id is null then 'RETRY_APPROVED'
        else 'DISPATCH_ACCEPTED'
      end,
      result_code = case
        when p_provider_run_id is null then 'DISPATCH_RETRY_APPROVED'
        else 'DISPATCH_RUN_FOUND'
      end,
      provider_run_id = p_provider_run_id,
      provider_run_attempt = p_provider_run_attempt,
      provider_checked_at = p_provider_checked_at,
      reconciliation_id = p_reconciliation_id,
      dispatch_finished_at = clock_timestamp(),
      updated_at = clock_timestamp(),
      actor = btrim(p_actor)
  where task_id = p_task_id;

  return public.get_website_delivery_pdf_dispatch_status_v1(p_task_id);
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
  set status = case
        when new.completed_at is null then 'RUNNING'
        else 'COMPLETED'
      end,
      result_code = case
        when new.completed_at is null then 'WORKFLOW_RUNNING'
        else 'WORKFLOW_COMPLETED'
      end,
      provider_run_id = new.workflow_run_id,
      provider_run_attempt = new.workflow_run_attempt,
      running_at = coalesce(running_at, new.claimed_at),
      completed_at = case
        when new.completed_at is null then completed_at
        else new.completed_at
      end,
      updated_at = clock_timestamp()
  where task_id = new.task_id;
  return new;
end;
$$;

drop trigger if exists sync_website_delivery_pdf_dispatch_execution_insert_v1
on public.website_delivery_pdf_conversion_executions;
create trigger sync_website_delivery_pdf_dispatch_execution_insert_v1
after insert on public.website_delivery_pdf_conversion_executions
for each row
execute function public.sync_website_delivery_pdf_dispatch_execution_v1();

drop trigger if exists sync_website_delivery_pdf_dispatch_execution_update_v1
on public.website_delivery_pdf_conversion_executions;
create trigger sync_website_delivery_pdf_dispatch_execution_update_v1
after update of execution_id, workflow_run_attempt, completed_at
on public.website_delivery_pdf_conversion_executions
for each row
execute function public.sync_website_delivery_pdf_dispatch_execution_v1();

revoke all on function public.reconcile_website_delivery_pdf_dispatch_unknown_v1(
  uuid,text,integer,timestamptz,uuid,boolean,text
) from public, anon, authenticated, service_role;
grant execute on function public.reconcile_website_delivery_pdf_dispatch_unknown_v1(
  uuid,text,integer,timestamptz,uuid,boolean,text
) to service_role;

revoke all on function public.sync_website_delivery_pdf_dispatch_execution_v1()
from public, anon, authenticated, service_role;

comment on function public.reconcile_website_delivery_pdf_dispatch_unknown_v1(
  uuid,text,integer,timestamptz,uuid,boolean,text
) is 'C2-H1 canonical UNKNOWN reconciliation with exact provider run ID and run attempt.';
comment on function public.sync_website_delivery_pdf_dispatch_execution_v1()
is 'C2-H1 canonical execution lifecycle projection for dispatch intent RUNNING and COMPLETED states.';