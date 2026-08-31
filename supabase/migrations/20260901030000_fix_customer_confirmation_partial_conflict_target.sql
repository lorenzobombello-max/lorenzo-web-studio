create or replace function public.transition_quote_request_review(
  p_token_hash text,
  p_action text
)
returns table (
  request_id uuid,
  request_name text,
  request_email text,
  review_status text,
  reviewed_at timestamptz,
  confirmation_job_id uuid,
  confirmation_job_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.quote_requests%rowtype;
  v_job public.quote_request_email_jobs%rowtype;
  v_reviewed_at timestamptz;
begin
  if p_action not in ('approved', 'rejected') then
    raise exception using errcode = 'P0001', message = 'INVALID_REVIEW_ACTION';
  end if;

  select *
    into v_request
    from public.quote_requests
    where approval_token_hash = p_token_hash
    for update;

  if not found then
    return;
  end if;

  if v_request.status = 'pending'
     and v_request.approval_token_expires_at <= now() then
    return;
  end if;

  if v_request.status = 'pending' then
    v_reviewed_at := now();

    update public.quote_requests
      set status = p_action::public.quote_request_status,
          reviewer_action = p_action,
          reviewed_at = v_reviewed_at
      where id = v_request.id
        and status = 'pending'
      returning * into v_request;
  end if;

  if v_request.status = 'approved' then
    insert into public.quote_request_email_jobs (quote_request_id, kind)
    values (v_request.id, 'customer_confirmation')
    on conflict (quote_request_id, kind)
      where reminder_access_cycle is null
    do nothing;

    select *
      into v_job
      from public.quote_request_email_jobs
      where quote_request_id = v_request.id
        and kind = 'customer_confirmation';
  end if;

  return query
  select
    v_request.id,
    v_request.name,
    v_request.email,
    v_request.status::text,
    v_request.reviewed_at,
    v_job.id,
    v_job.status::text;
end;
$$;