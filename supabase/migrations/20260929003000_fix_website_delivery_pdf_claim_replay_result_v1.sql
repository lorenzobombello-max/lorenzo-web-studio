-- W2.4.1-PDF B2: report claim creation versus replay under the same task lock.

alter function public.claim_website_delivery_pdf_conversion_v1(uuid,text,text,text,text,text,text)
rename to claim_website_delivery_pdf_conversion_internal_v1;

revoke all on function public.claim_website_delivery_pdf_conversion_internal_v1(uuid,text,text,text,text,text,text)
from public, anon, authenticated, service_role;

create function public.claim_website_delivery_pdf_conversion_v1(
  p_task_id uuid,
  p_workflow_repository text,
  p_workflow_repository_id text,
  p_workflow_ref_name text,
  p_workflow_ref text,
  p_workflow_run_id text,
  p_actor text
) returns jsonb
language plpgsql security definer set search_path = public, pg_catalog as $$
declare
  v_existed boolean;
  v_result jsonb;
begin
  if p_task_id is null then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_PDF_CLAIM_INPUT_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_task_id::text, 0));
  select exists(
    select 1 from public.website_delivery_pdf_conversion_executions where task_id = p_task_id
  ) into v_existed;
  v_result := public.claim_website_delivery_pdf_conversion_internal_v1(
    p_task_id, p_workflow_repository, p_workflow_repository_id, p_workflow_ref_name,
    p_workflow_ref, p_workflow_run_id, p_actor
  );
  return jsonb_set(v_result, '{was_created}', to_jsonb(not v_existed), true);
end;
$$;

revoke all on function public.claim_website_delivery_pdf_conversion_v1(uuid,text,text,text,text,text,text)
from public, anon, authenticated, service_role;
grant execute on function public.claim_website_delivery_pdf_conversion_v1(uuid,text,text,text,text,text,text)
to service_role;

comment on function public.claim_website_delivery_pdf_conversion_v1(uuid,text,text,text,text,text,text) is
  'Claims one exact B1 task for one verified workflow run, resolves source and generation data server-side, and distinguishes creation from replay.';