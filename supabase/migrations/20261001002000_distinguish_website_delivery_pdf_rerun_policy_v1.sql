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
     or p_provider_conclusion is null
     or p_approval_id is null or p_provider_checked_at is null
     or p_provider_checked_at > clock_timestamp() + interval '1 minute'
     or p_provider_checked_at < clock_timestamp() - interval '10 minutes'
     or nullif(btrim(p_actor), '') is null or length(p_actor) > 200 then
    raise exception using
      errcode = '22023',
      message = 'WEBSITE_DELIVERY_PDF_RECOVERY_INPUT_INVALID';
  end if;
  if p_provider_conclusion not in (
    'action_required','cancelled','failure','stale','startup_failure','timed_out'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_DELIVERY_PDF_RECOVERY_NOT_ALLOWED';
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

revoke all on function public.claim_website_delivery_pdf_rerun_v1(
  uuid,uuid,text,integer,text,text,uuid,timestamptz,text
) from public, anon, authenticated, service_role;
grant execute on function public.claim_website_delivery_pdf_rerun_v1(
  uuid,uuid,text,integer,text,text,uuid,timestamptz,text
) to service_role;