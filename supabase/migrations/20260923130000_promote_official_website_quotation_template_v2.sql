do $migration$
declare
  v_previous_template_id uuid;
  v_official_template_id uuid;
begin
  select id into strict v_previous_template_id
  from public.quotation_template_authorities
  where request_kind = 'website'
    and template_id = 'LWS_QUOTATION_NL_BE'
    and template_version = '1.0.0-technical'
    and status = 'APPROVED';

  if exists (
    select 1
    from public.quote_request_quotation_business_drafts as business
    where business.template_authority_id = v_previous_template_id
      and not exists (
        select 1
        from public.quote_request_quotation_business_approval_promotions as promotion
        join public.quote_request_quotation_issuances as issuance
          on issuance.approval_id = promotion.approval_id
        where promotion.business_draft_id = business.business_draft_id
          and issuance.status = 'ISSUED'
      )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_TEMPLATE_IN_FLIGHT_APPROVALS_REQUIRE_RESOLUTION';
  end if;

  v_official_template_id := public.register_quotation_template_candidate_for_product_v1(
    'website',
    'LWS_QUOTATION_NL_BE',
    '2.0.0-official',
    'QUOTATION',
    'nl-BE',
    'EUR',
    'B8B958AE9567FD8526195B4F614ECDCCAB7E1BB2ACAB21121BEE0342630DA059',
    'assets/docs/quotation/LWS_WEBSITE_QUOTATION_NL_BE_OFFICIAL_v1.docx',
    1::smallint,
    'website-official-ooxml-v1',
    1::smallint,
    1::smallint,
    'migration:20260923130000',
    'WEBSITE_OFFICIAL_QUOTATION_TEMPLATE_REGISTERED',
    v_previous_template_id
  );

  perform public.retire_quotation_template_v1(
    v_previous_template_id,
    'migration:20260923130000',
    'Superseded by the tagged derivative of the official Website quotation document.',
    'WEBSITE_TECHNICAL_QUOTATION_TEMPLATE_RETIRED'
  );

  perform public.approve_quotation_template_v1(
    v_official_template_id,
    'migration:20260923130000',
    'WEBSITE_OFFICIAL_QUOTATION_TEMPLATE_APPROVED'
  );
end;
$migration$;