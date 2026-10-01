create or replace function public.reconcile_website_delivery_pdf_rerun_unknown_v1(
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
  v_provider_status text := btrim(p_provider_status);
  v_provider_conclusion text := case
    when p_provider_conclusion is null then null else btrim(p_provider_conclusion)
  end;
  v_stored_rank integer;
  v_observed_rank integer;
begin
  if p_task_id is null or p_recovery_id is null
     or p_provider_run_id !~ '^[1-9][0-9]*$'
     or p_provider_run_attempt is null or p_provider_run_attempt <= 0
     or nullif(v_provider_status, '') is null or length(p_provider_status) > 40
     or v_provider_status not in ('queued','in_progress','completed')
     or (p_provider_conclusion is not null and (
       nullif(v_provider_conclusion, '') is null or length(p_provider_conclusion) > 80
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
  if p_provider_run_attempt <= v_recovery.approved_run_attempt then
    return jsonb_build_object(
      'task_id',v_recovery.task_id,'recovery_id',v_recovery.recovery_id,
      'recovery_status',v_recovery.status,'result_code',v_recovery.result_code
    );
  end if;
  if v_recovery.status not in ('RERUN_UNKNOWN','RERUN_ACCEPTED','RUNNING') then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_RECOVERY_STATE_INVALID';
  end if;
  if v_recovery.observed_run_attempt is not null
     and v_recovery.observed_run_attempt <> p_provider_run_attempt then
    raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_RECOVERY_STALE';
  end if;
  if v_recovery.observed_provider_status is not null then
    if v_recovery.observed_provider_status = v_provider_status
       and v_recovery.observed_provider_conclusion is not distinct from v_provider_conclusion then
      return jsonb_build_object(
        'task_id',v_recovery.task_id,'recovery_id',v_recovery.recovery_id,
        'recovery_status',v_recovery.status,'result_code',v_recovery.result_code
      );
    end if;

    v_stored_rank := case v_recovery.observed_provider_status
      when 'queued' then 1 when 'in_progress' then 2 when 'completed' then 3 else null
    end;
    v_observed_rank := case v_provider_status
      when 'queued' then 1 when 'in_progress' then 2 when 'completed' then 3 else null
    end;
    if v_stored_rank is null or v_observed_rank <= v_stored_rank
       or (v_recovery.observed_checked_at is not null
         and p_provider_checked_at < v_recovery.observed_checked_at) then
      raise exception using errcode='P0001',message='WEBSITE_DELIVERY_PDF_RECOVERY_STALE';
    end if;
  end if;

  update public.website_delivery_pdf_recovery_intents
  set observed_run_attempt=coalesce(observed_run_attempt,p_provider_run_attempt),
      observed_provider_status=v_provider_status,
      observed_provider_conclusion=v_provider_conclusion,
      observed_checked_at=p_provider_checked_at,
      provider_checked_at=p_provider_checked_at,
      status=case when status='RERUN_UNKNOWN' then 'RERUN_ACCEPTED' else status end,
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