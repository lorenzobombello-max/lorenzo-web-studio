create or replace function public.build_quotation_issue_payload_v1_unchecked_d3e4(
  p_issuance_id uuid,
  p_template jsonb,
  p_seller jsonb,
  p_admin_access_token_hash text
)
returns table(payload jsonb, payload_sha256 text, contract_version smallint, mode text, approval_id uuid, issuance_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_issuance public.quote_request_quotation_issuances%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_payload jsonb;
  v_payload_sha256 text;
begin
  select * into v_issuance
  from public.quote_request_quotation_issuances
  where id = p_issuance_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_NOT_FOUND';
  end if;
  if not (
    (v_issuance.status = 'PREPARED' and v_issuance.generation_payload_sha256 is null)
    or
    (v_issuance.status = 'ISSUED'
      and v_issuance.generation_payload_sha256 is not null
      and v_issuance.template_id = p_template->>'template_id'
      and v_issuance.template_version = p_template->>'template_version'
      and rtrim(v_issuance.template_sha256) = lower(p_template->>'template_sha256'))
  ) then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_STATE_CONFLICT';
  end if;
  select * into strict v_approval
  from public.quote_request_quotation_approvals
  where id = v_issuance.approval_id;
  select * into strict v_intake
  from public.quote_request_intakes
  where id = v_approval.intake_id;
  if p_admin_access_token_hash !~ '^[0-9a-f]{64}$'
     or v_intake.admin_access_token_hash is distinct from p_admin_access_token_hash
     or v_intake.admin_access_token_expires_at <= clock_timestamp()
     or v_intake.admin_access_token_revoked_at is not null then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;
  if not public.is_valid_quotation_approval_for_issuance_v1(v_approval.id) then
    raise exception using errcode = 'P0001', message = 'APPROVAL_INTEGRITY_INVALID';
  end if;
  if not public.is_valid_quotation_generation_template_v1(p_template, true) then
    if public.is_valid_quotation_generation_template_v1(p_template, false) then
      raise exception using errcode = 'P0001', message = 'QUOTATION_TEMPLATE_NOT_APPROVED';
    end if;
    raise exception using errcode = '22023', message = 'TEMPLATE_IDENTITY_INVALID';
  end if;
  if not public.is_valid_quotation_generation_seller_v1(p_seller) then
    raise exception using errcode = '22023', message = 'SELLER_IDENTITY_INVALID';
  end if;
  v_payload := public.project_quotation_generation_payload_v1(
    'ISSUE', v_approval.id, v_approval.approved_payload, v_approval.payload_sha256,
    p_template, p_seller, v_issuance.id, v_issuance.quotation_number,
    v_issuance.quotation_version
  );
  if not public.is_valid_quotation_generation_payload_v1(v_payload) then
    raise exception using errcode = '22023', message = 'INVALID_QUOTATION_GENERATION_PAYLOAD_V1';
  end if;
  v_payload_sha256 := public.quotation_generation_payload_sha256_v1(v_payload);
  if v_issuance.status = 'ISSUED'
     and rtrim(v_issuance.generation_payload_sha256) <> v_payload_sha256 then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_STATE_CONFLICT';
  end if;
  return query select v_payload, v_payload_sha256, 1::smallint, 'ISSUE'::text,
    v_approval.id, v_issuance.id;
end;
$$;

revoke all on function public.build_quotation_issue_payload_v1_unchecked_d3e4(uuid, jsonb, jsonb, text)
from public, anon, authenticated, service_role;