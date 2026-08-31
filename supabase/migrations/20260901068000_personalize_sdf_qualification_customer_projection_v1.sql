create or replace function public.inspect_sdf_qualification_intake_v1(
  p_customer_capability_digest text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_quote_request_id uuid;
  v_status public.sdf_qualification_intake_status;
  v_taxonomy_version text;
  v_draft jsonb;
  v_draft_revision bigint;
  v_expires_at timestamptz;
  v_name text;
  v_company text;
  v_email text;
  v_phone text;
  v_support_reference text;
  v_request_created_at timestamptz;
begin
  select
    quote_request_id,
    status,
    taxonomy_version,
    draft_answers,
    draft_revision,
    customer_capability_expires_at
  into
    v_quote_request_id,
    v_status,
    v_taxonomy_version,
    v_draft,
    v_draft_revision,
    v_expires_at
  from public.sdf_qualification_intakes
  where customer_capability_digest = p_customer_capability_digest
    and customer_capability_revoked_at is null
    and customer_capability_expires_at > clock_timestamp();

  if not found then
    raise exception using errcode = '42501', message = 'SDF_INTAKE_ACCESS_DENIED';
  end if;

  select name, company, email, phone, support_reference, created_at
  into strict v_name, v_company, v_email, v_phone, v_support_reference, v_request_created_at
  from public.quote_requests
  where id = v_quote_request_id
    and request_kind = 'slimme_documentenflow';

  return jsonb_build_object(
    'customer', jsonb_strip_nulls(jsonb_build_object(
      'name', v_name,
      'company', nullif(btrim(v_company), ''),
      'email', v_email,
      'phone', nullif(btrim(v_phone), '')
    )),
    'support_reference', v_support_reference,
    'request_created_at', v_request_created_at,
    'status', v_status,
    'taxonomy_version', v_taxonomy_version,
    'draft', v_draft,
    'draft_revision', v_draft_revision,
    'expires_at', v_expires_at
  );
end;
$$;

revoke all on function public.inspect_sdf_qualification_intake_v1(text)
from public, anon, authenticated, service_role;

grant execute on function public.inspect_sdf_qualification_intake_v1(text)
to service_role;