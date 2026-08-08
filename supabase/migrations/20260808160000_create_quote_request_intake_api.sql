create or replace function public.create_quote_request_intake(
  p_approval_token_hash text,
  p_access_token_hash text
)
returns table (
  outcome text,
  intake_id uuid,
  access_token_expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.quote_requests%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_created_at timestamptz;
begin
  if p_approval_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_APPROVAL_TOKEN_HASH';
  end if;

  if p_access_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_ACCESS_TOKEN_HASH';
  end if;

  select *
    into v_request
    from public.quote_requests
    where approval_token_hash = p_approval_token_hash
    for update;

  if not found
     or v_request.status <> 'approved'
     or v_request.approval_token_expires_at is null
     or v_request.approval_token_expires_at <= now() then
    return query select 'not_allowed'::text, null::uuid, null::timestamptz;
    return;
  end if;

  select *
    into v_intake
    from public.quote_request_intakes
    where quote_request_id = v_request.id;

  if found then
    return query select 'already_exists'::text, v_intake.id, v_intake.access_token_expires_at;
    return;
  end if;

  v_created_at := clock_timestamp();

  insert into public.quote_request_intakes (
    quote_request_id,
    status,
    access_token_hash,
    access_token_expires_at,
    access_token_revoked_at,
    created_at,
    updated_at
  ) values (
    v_request.id,
    'invited',
    p_access_token_hash,
    v_created_at + interval '14 days',
    null,
    v_created_at,
    v_created_at
  )
  returning * into v_intake;

  return query select 'created'::text, v_intake.id, v_intake.access_token_expires_at;
exception
  when unique_violation then
    select *
      into v_intake
      from public.quote_request_intakes
      where quote_request_id = v_request.id;

    if not found then
      raise;
    end if;

    return query select 'already_exists'::text, v_intake.id, v_intake.access_token_expires_at;
end;
$$;

create or replace function public.inspect_quote_request_intake(p_access_token_hash text)
returns table (
  intake_id uuid,
  intake_status text,
  quote_request_created_at timestamptz,
  name text,
  company text,
  email text,
  phone text,
  website_type text,
  budget text,
  timing text,
  description text,
  started_at timestamptz,
  submitted_at timestamptz,
  reviewed_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    intake.id,
    intake.status::text,
    request.created_at,
    request.name,
    request.company,
    request.email,
    request.phone,
    request.website_type,
    request.budget,
    request.timing,
    request.description,
    intake.started_at,
    intake.submitted_at,
    intake.reviewed_at
  from public.quote_request_intakes as intake
  inner join public.quote_requests as request
    on request.id = intake.quote_request_id
  where intake.access_token_hash = p_access_token_hash
    and intake.access_token_expires_at > now()
    and intake.access_token_revoked_at is null
  limit 1
$$;

revoke all
on function public.create_quote_request_intake(text, text)
from public, anon, authenticated;

revoke all
on function public.inspect_quote_request_intake(text)
from public, anon, authenticated;

grant execute
on function public.create_quote_request_intake(text, text)
to service_role;

grant execute
on function public.inspect_quote_request_intake(text)
to service_role;