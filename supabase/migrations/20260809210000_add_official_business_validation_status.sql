alter table public.quote_requests
  add column if not exists enterprise_validation_status text not null default 'not_checked',
  add column if not exists vat_validation_status text not null default 'not_checked',
  add column if not exists vat_validated_at timestamptz;

alter table public.quote_requests
  add constraint quote_requests_enterprise_validation_status_check
    check (enterprise_validation_status in ('format_valid_not_externally_verified', 'not_checked')) not valid,
  add constraint quote_requests_enterprise_validation_consistency_check
    check (
      enterprise_validation_status = 'not_checked'
      or (
        customer_type = 'business'
        and enterprise_number ~ '^\d{10}$'
      )
    ) not valid,
  add constraint quote_requests_vat_validation_status_check
    check (vat_validation_status in ('valid', 'invalid', 'unavailable', 'not_checked')) not valid,
  add constraint quote_requests_vat_validation_consistency_check
    check (
      (vat_validation_status = 'not_checked' and vat_validated_at is null)
      or (vat_validation_status = 'unavailable' and vat_number is not null and vat_validated_at is not null)
      or (vat_validation_status in ('valid', 'invalid') and vat_number is not null and vat_validated_at is not null)
    ) not valid;

alter table public.quote_requests
  validate constraint quote_requests_enterprise_validation_status_check,
  validate constraint quote_requests_enterprise_validation_consistency_check,
  validate constraint quote_requests_vat_validation_status_check,
  validate constraint quote_requests_vat_validation_consistency_check;

create function public.create_quote_request_idempotent(
  p_idempotency_key uuid,
  p_request_fingerprint text,
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
  insert into public.quote_requests (
    idempotency_key, request_fingerprint, name, customer_type, company,
    enterprise_number, enterprise_validation_status, vat_number, vat_validation_status, vat_validated_at,
    billing_address, billing_postal_code, billing_city, billing_country, billing_email,
    email, phone, website_type, budget, timing, description, privacy_consent, status,
    approval_token_hash, approval_token_expires_at, client_ip_hash, user_agent
  ) values (
    p_idempotency_key, p_request_fingerprint, p_name, p_customer_type, p_company,
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
on function public.create_quote_request_idempotent(uuid, text, text, text, text, text, text, text, text, timestamptz, text, text, text, text, text, text, text, text, text, text, text, boolean, text, timestamptz, text, text)
from public, anon, authenticated;

grant execute
on function public.create_quote_request_idempotent(uuid, text, text, text, text, text, text, text, text, timestamptz, text, text, text, text, text, text, text, text, text, text, text, boolean, text, timestamptz, text, text)
to service_role;