update public.website_delivery_pdf_dispatch_intents
set status = 'DISPATCH_UNKNOWN',
    result_code = 'DISPATCH_RUN_NOT_OBSERVED',
    updated_at = clock_timestamp()
where status = 'RETRY_APPROVED';

create or replace function public.claim_website_delivery_pdf_dispatch_v1(
  p_task_id uuid,
  p_actor text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_task public.website_delivery_pdf_conversion_tasks%rowtype;
  v_intent public.website_delivery_pdf_dispatch_intents%rowtype;
  v_should_dispatch boolean := false;
begin
  if p_task_id is null or nullif(btrim(p_actor), '') is null or length(p_actor) > 200 then
    raise exception using
      errcode = '22023',
      message = 'WEBSITE_DELIVERY_PDF_DISPATCH_INPUT_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_task_id::text, 0));
  select * into v_task
  from public.website_delivery_pdf_conversion_tasks
  where task_id = p_task_id;
  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_DELIVERY_PDF_TASK_NOT_FOUND';
  end if;
  select * into v_intent
  from public.website_delivery_pdf_dispatch_intents
  where task_id = p_task_id
  for update;
  if not found then
    insert into public.website_delivery_pdf_dispatch_intents(
      task_id,artifact_id,status,dispatch_attempt,dispatch_attempt_id,result_code,actor
    ) values (
      v_task.task_id,v_task.artifact_id,'DISPATCH_UNKNOWN',1,gen_random_uuid(),
      'DISPATCH_OUTCOME_UNKNOWN',btrim(p_actor)
    ) returning * into v_intent;
    v_should_dispatch := true;
  end if;
  return public.get_website_delivery_pdf_dispatch_status_v1(p_task_id)
    || jsonb_build_object('should_dispatch',v_should_dispatch);
end;
$$;

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

  update public.website_delivery_pdf_dispatch_intents
  set status = case
        when p_provider_run_id is null then 'DISPATCH_UNKNOWN'
        else 'DISPATCH_ACCEPTED'
      end,
      result_code = case
        when p_provider_run_id is null then 'DISPATCH_RUN_NOT_OBSERVED'
        else 'DISPATCH_RUN_FOUND'
      end,
      provider_run_id = p_provider_run_id,
      provider_run_attempt = p_provider_run_attempt,
      provider_checked_at = p_provider_checked_at,
      reconciliation_id = p_reconciliation_id,
      dispatch_finished_at = case
        when p_provider_run_id is null then dispatch_finished_at
        else clock_timestamp()
      end,
      updated_at = clock_timestamp(),
      actor = btrim(p_actor)
  where task_id = p_task_id;

  return public.get_website_delivery_pdf_dispatch_status_v1(p_task_id);
end;
$$;

revoke all on function public.claim_website_delivery_pdf_dispatch_v1(uuid,text)
from public, anon, authenticated, service_role;
grant execute on function public.claim_website_delivery_pdf_dispatch_v1(uuid,text)
to service_role;

revoke all on function public.reconcile_website_delivery_pdf_dispatch_unknown_v1(
  uuid,text,integer,timestamptz,uuid,boolean,text
) from public, anon, authenticated, service_role;
grant execute on function public.reconcile_website_delivery_pdf_dispatch_unknown_v1(
  uuid,text,integer,timestamptz,uuid,boolean,text
) to service_role;