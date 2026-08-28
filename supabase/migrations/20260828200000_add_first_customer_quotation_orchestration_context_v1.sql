create function public.resolve_first_customer_quotation_orchestration_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_business public.quote_request_quotation_business_drafts%rowtype;
  v_promotion public.quote_request_quotation_business_approval_promotions%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_seller public.quotation_seller_authorities%rowtype;
  v_template public.quotation_template_authorities%rowtype;
  v_issuance_input_sha256 text;
begin
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = p_actor_auth_user_id;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'QUOTATION_ORCHESTRATION_SCOPE_DENIED';
  end if;

  select business.* into v_business
  from public.quote_request_quotation_business_drafts as business
  join public.quote_request_quotation_business_approval_promotions as promotion
    on promotion.business_draft_id = business.business_draft_id
  where business.quote_request_id = p_quote_request_id
  order by business.business_revision desc
  limit 1;
  if not found then
    raise exception using errcode = 'P0001', message = 'APPROVAL_NOT_FOUND';
  end if;

  select * into strict v_promotion
  from public.quote_request_quotation_business_approval_promotions
  where business_draft_id = v_business.business_draft_id;
  select * into strict v_approval
  from public.quote_request_quotation_approvals
  where id = v_promotion.approval_id;
  select * into strict v_intake
  from public.quote_request_intakes
  where id = v_business.intake_id;
  select * into strict v_seller
  from public.quotation_seller_authorities
  where seller_authority_id = v_business.seller_authority_id;
  select * into strict v_template
  from public.quotation_template_authorities
  where id = v_business.template_authority_id;

  if v_approval.quote_request_id is distinct from v_business.quote_request_id
     or v_approval.intake_id is distinct from v_business.intake_id
     or v_approval.pricing_snapshot_id is distinct from v_business.pricing_snapshot_id
     or v_approval.draft_id is distinct from v_business.approval_draft_id
     or v_approval.approved_payload is distinct from v_business.canonical_payload
     or rtrim(v_approval.payload_sha256) is distinct from rtrim(v_business.canonical_payload_sha256)
     or v_intake.quote_request_id is distinct from p_quote_request_id then
    raise exception using errcode = 'P0001', message = 'APPROVAL_INTEGRITY_INVALID';
  end if;
  if not public.is_valid_quotation_approval_for_issuance_v1(v_approval.id) then
    raise exception using errcode = 'P0001', message = 'APPROVAL_INTEGRITY_INVALID';
  end if;
  if v_intake.status not in ('submitted', 'reviewed')
     or v_intake.admin_access_token_hash is null
     or v_intake.admin_access_token_hash !~ '^[0-9a-f]{64}$'
     or v_intake.admin_access_token_expires_at <= clock_timestamp()
     or v_intake.admin_access_token_revoked_at is not null then
    raise exception using errcode = '42501', message = 'QUOTATION_ADMIN_CAPABILITY_UNAVAILABLE';
  end if;
  if v_template.status <> 'APPROVED' then
    raise exception using errcode = 'P0001', message = 'QUOTATION_TEMPLATE_NOT_APPROVED';
  end if;
  if not public.is_valid_quotation_generation_seller_v1(v_seller.seller_identity) then
    raise exception using errcode = 'P0001', message = 'SELLER_IDENTITY_INVALID';
  end if;

  v_issuance_input_sha256 := encode(extensions.digest(convert_to(jsonb_build_object(
    'approvalId', v_approval.id,
    'approvalPayloadSha256', rtrim(v_approval.payload_sha256),
    'generationContractVersion', v_template.generation_contract_version,
    'sellerAuthorityId', v_seller.seller_authority_id,
    'sellerIdentitySha256', rtrim(v_seller.seller_identity_sha256),
    'templateAuthorityId', v_template.id,
    'templateSha256', lower(rtrim(v_template.template_sha256))
  )::text, 'UTF8'), 'sha256'), 'hex');

  return jsonb_build_object(
    'approval_id', v_approval.id,
    'admin_access_token_hash', v_intake.admin_access_token_hash,
    'issue_year', extract(year from clock_timestamp() at time zone 'Europe/Brussels')::integer,
    'issuance_input_sha256', v_issuance_input_sha256,
    'template', jsonb_build_object(
      'template_id', v_template.template_id,
      'template_version', v_template.template_version,
      'template_sha256', lower(rtrim(v_template.template_sha256)),
      'authority_status', v_template.status,
      'technical_master_filename', v_template.technical_master_filename,
      'renderer_version', v_template.renderer_version
    ),
    'seller', v_seller.seller_identity
  );
end;
$$;

revoke all on function public.resolve_first_customer_quotation_orchestration_v1(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.resolve_first_customer_quotation_orchestration_v1(uuid, uuid)
to service_role;

comment on function public.resolve_first_customer_quotation_orchestration_v1(uuid, uuid) is
  'Service-only owner/admin resolver for one promoted quotation approval and its frozen issuance, seller, template, and intake capability context.';