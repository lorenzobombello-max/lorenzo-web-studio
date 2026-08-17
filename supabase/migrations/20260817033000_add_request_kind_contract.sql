-- Slimme Documentenflow request-kind contract.
-- Historical and legacy callers remain website requests; non-website requests fail closed.

alter table public.quote_requests
  add column request_kind text not null default 'website';

alter table public.quote_requests
  alter column website_type drop not null,
  alter column budget drop not null,
  alter column timing drop not null;

alter table public.quote_requests
  add constraint quote_requests_request_kind_check
    check (request_kind in ('website', 'slimme_documentenflow')) not valid,
  add constraint quote_requests_request_kind_shape_check
    check (
      (
        request_kind = 'website'
        and website_type is not null
        and budget is not null
        and timing is not null
      )
      or (
        request_kind = 'slimme_documentenflow'
        and website_type is null
        and budget is null
        and timing is null
      )
    ) not valid;

alter table public.quote_requests
  validate constraint quote_requests_request_kind_check,
  validate constraint quote_requests_request_kind_shape_check;

comment on column public.quote_requests.request_kind is
  'Durable commercial product discriminator. Omitted legacy submissions are website requests.';

create function public.create_quote_request_idempotent(
  p_idempotency_key uuid,
  p_request_fingerprint text,
  p_request_kind text,
  p_name text,
  p_customer_type text,
  p_company text,
  p_enterprise_number text,
  p_enterprise_validation_status text,
  p_vat_number text,
  p_vat_validation_status text,
  p_vat_validated_at timestamptz,
  p_billing_address text,
  p_billing_postal_code text,
  p_billing_city text,
  p_billing_country text,
  p_billing_email text,
  p_email text,
  p_phone text,
  p_website_type text,
  p_budget text,
  p_timing text,
  p_description text,
  p_privacy_consent boolean,
  p_approval_token_hash text,
  p_approval_token_expires_at timestamptz,
  p_client_ip_hash text,
  p_user_agent text
)
returns table (
  request_id uuid,
  request_created_at timestamptz,
  was_created boolean,
  admin_job_id uuid,
  admin_job_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.quote_requests%rowtype;
  v_job public.quote_request_email_jobs%rowtype;
  v_was_created boolean := false;
begin
  if p_request_kind is null or p_request_kind not in ('website', 'slimme_documentenflow') then
    raise exception using errcode = '22023', message = 'INVALID_REQUEST_KIND';
  end if;
  if p_request_kind = 'website'
     and (p_website_type is null or p_budget is null or p_timing is null) then
    raise exception using errcode = '22023', message = 'INVALID_WEBSITE_REQUEST_SHAPE';
  end if;
  if p_request_kind = 'slimme_documentenflow'
     and (p_website_type is not null or p_budget is not null or p_timing is not null) then
    raise exception using errcode = '22023', message = 'INVALID_DOCUMENTENFLOW_REQUEST_SHAPE';
  end if;

  insert into public.quote_requests (
    idempotency_key, request_fingerprint, request_kind, name, customer_type, company,
    enterprise_number, enterprise_validation_status, vat_number, vat_validation_status, vat_validated_at,
    billing_address, billing_postal_code, billing_city, billing_country, billing_email,
    email, phone, website_type, budget, timing, description, privacy_consent, status,
    approval_token_hash, approval_token_expires_at, client_ip_hash, user_agent
  ) values (
    p_idempotency_key, p_request_fingerprint, p_request_kind, p_name, p_customer_type, p_company,
    p_enterprise_number, p_enterprise_validation_status, p_vat_number, p_vat_validation_status, p_vat_validated_at,
    p_billing_address, p_billing_postal_code, p_billing_city, p_billing_country, p_billing_email,
    p_email, p_phone, p_website_type, p_budget, p_timing, p_description, p_privacy_consent, 'pending',
    p_approval_token_hash, p_approval_token_expires_at, p_client_ip_hash, p_user_agent
  )
  on conflict (idempotency_key) where idempotency_key is not null do nothing
  returning * into v_request;

  v_was_created := found;

  if not v_was_created then
    select * into v_request
      from public.quote_requests
      where idempotency_key = p_idempotency_key;

    if not found then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_LOOKUP_FAILED';
    end if;

    if v_request.request_fingerprint is distinct from p_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
  end if;

  insert into public.quote_request_email_jobs (quote_request_id, kind)
  values (v_request.id, 'admin_notification')
  on conflict (quote_request_id, kind) do nothing;

  select * into v_job
    from public.quote_request_email_jobs
    where quote_request_id = v_request.id
      and kind = 'admin_notification';

  return query
  select v_request.id, v_request.created_at, v_was_created, v_job.id, v_job.status::text;
end;
$$;

revoke all
on function public.create_quote_request_idempotent(
  uuid, text, text, text, text, text, text, text, text, text, timestamptz,
  text, text, text, text, text, text, text, text, text, text, text, boolean,
  text, timestamptz, text, text
)
from public, anon, authenticated;

grant execute
on function public.create_quote_request_idempotent(
  uuid, text, text, text, text, text, text, text, text, text, timestamptz,
  text, text, text, text, text, text, text, text, text, text, text, boolean,
  text, timestamptz, text, text
)
to service_role;

comment on function public.create_quote_request_idempotent(
  uuid, text, text, text, text, text, text, text, text, text, timestamptz,
  text, text, text, text, text, text, text, text, text, text, text, boolean,
  text, timestamptz, text, text
) is 'Request-kind-aware idempotent commercial request storage. Legacy overload remains website-only.';

create function public.guard_quote_request_kind_v1()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.request_kind is distinct from old.request_kind then
    raise exception using errcode = '55000', message = 'REQUEST_KIND_IMMUTABLE';
  end if;
  if old.request_kind = 'slimme_documentenflow'
     and new.status is distinct from old.status then
    raise exception using errcode = '42501', message = 'REQUEST_KIND_ACTION_NOT_ALLOWED';
  end if;
  return new;
end;
$$;

create trigger trg_quote_request_kind_guard
before update of request_kind, status on public.quote_requests
for each row execute function public.guard_quote_request_kind_v1();

create function public.guard_website_intake_kind_v1()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_request_kind text;
begin
  select request_kind into v_request_kind
    from public.quote_requests
    where id = new.quote_request_id;

  if v_request_kind = 'slimme_documentenflow' then
    raise exception using errcode = '42501', message = 'REQUEST_KIND_INTAKE_NOT_ALLOWED';
  end if;
  return new;
end;
$$;

create trigger trg_quote_request_intake_kind_guard
before insert or update of quote_request_id on public.quote_request_intakes
for each row execute function public.guard_website_intake_kind_v1();

revoke execute on function
  public.guard_quote_request_kind_v1(),
  public.guard_website_intake_kind_v1()
from public, anon, authenticated, service_role;

comment on function public.guard_quote_request_kind_v1() is
  'Prevents request-kind mutation and website review transitions for Documentenflow requests.';
comment on function public.guard_website_intake_kind_v1() is
  'Authoritative fail-closed boundary preventing non-website requests from entering website intake and Budget Guard.';