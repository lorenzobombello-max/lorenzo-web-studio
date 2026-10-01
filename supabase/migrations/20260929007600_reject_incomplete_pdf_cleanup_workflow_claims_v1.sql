create or replace function public.claim_website_delivery_pdf_conversion_v2(
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
    if v_claimed_by like 'PDF_ORPHAN_CLEANUP:CLAIM:%'
       or v_claimed_by like 'PDF_ORPHAN_CLEANUP:STAGED:%' then
      raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_CLAIM_CONFLICT';
    end if;
  end if;
  return public.claim_website_delivery_pdf_conversion_core_v2(
    p_task_id, p_workflow_repository, p_workflow_repository_id, p_workflow_ref_name,
    p_workflow_ref, p_workflow_run_id, p_workflow_run_attempt, p_actor
  );
end;
$$;

comment on function public.claim_website_delivery_pdf_conversion_v2(uuid,text,text,text,text,text,integer,text) is
  'Claims a PDF conversion only when no incomplete orphan-cleanup CLAIM or STAGED phase owns the task.';