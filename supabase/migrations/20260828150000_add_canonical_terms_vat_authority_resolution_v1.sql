create function public.resolve_quotation_terms_authority_v1(
  p_resolution_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_terms public.quotation_terms_authorities%rowtype;
  v_candidate_count integer;
begin
  if p_resolution_date is null then
    raise exception using errcode = '22023', message = 'QUOTATION_TERMS_NOT_APPROVED';
  end if;

  select count(*)::integer into v_candidate_count
  from public.quotation_terms_authorities
  where terms_id = 'LWS_GENERAL_TERMS_NL_BE'
    and status = 'APPROVED'
    and effective_from <= p_resolution_date;

  if v_candidate_count <> 1 then
    raise exception using errcode = 'P0001', message = 'QUOTATION_TERMS_NOT_APPROVED';
  end if;

  select * into strict v_terms
  from public.quotation_terms_authorities
  where terms_id = 'LWS_GENERAL_TERMS_NL_BE'
    and status = 'APPROVED'
    and effective_from <= p_resolution_date;

  return jsonb_build_object(
    'terms_authority_id', v_terms.terms_authority_id,
    'terms_id', v_terms.terms_id,
    'terms_version', v_terms.terms_version,
    'terms_sha256', rtrim(v_terms.terms_sha256),
    'source_path', v_terms.source_path,
    'effective_from', v_terms.effective_from
  );
end;
$$;

create function public.upsert_quotation_business_draft_v2(
  p_actor_auth_user_id uuid,
  p_intake_id uuid,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_input jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_terms jsonb;
begin
  if p_actor_auth_user_id is null or p_intake_id is null or p_idempotency_key is null
     or p_expected_revision is null or p_expected_revision < 0
     or not public.jsonb_has_exact_keys(p_input, array[
       'commercial_lines', 'discount', 'scope', 'payment_schedule', 'validity_days'
     ]) then
    raise exception using errcode = '22023', message = 'QUOTATION_BUSINESS_INPUT_INVALID';
  end if;

  select * into v_operator
  from public.commercial_operators
  where auth_user_id = p_actor_auth_user_id;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'QUOTATION_BUSINESS_SCOPE_DENIED';
  end if;

  v_terms := public.resolve_quotation_terms_authority_v1(
    (clock_timestamp() at time zone 'Europe/Brussels')::date
  );
  if v_terms is null then
    raise exception using errcode = 'P0001', message = 'QUOTATION_TERMS_NOT_APPROVED';
  end if;

  raise exception using
    errcode = 'P0001',
    message = 'QUOTATION_VAT_CONTEXT_REQUIRED';
end;
$$;

revoke all on function public.resolve_quotation_terms_authority_v1(date)
from public, anon, authenticated, service_role;
revoke all on function public.upsert_quotation_business_draft_v2(uuid, uuid, bigint, uuid, jsonb)
from public, anon, authenticated, service_role;

grant execute on function public.resolve_quotation_terms_authority_v1(date)
to service_role;
grant execute on function public.upsert_quotation_business_draft_v2(uuid, uuid, bigint, uuid, jsonb)
to service_role;

comment on function public.resolve_quotation_terms_authority_v1(date) is
  'Resolves exactly one effective approved LWS_GENERAL_TERMS_NL_BE authority without caller selection.';
comment on function public.upsert_quotation_business_draft_v2(uuid, uuid, bigint, uuid, jsonb) is
  'Authority-minimal business draft boundary; creation remains fail-closed until governed VAT context resolution exists.';