select public.register_quotation_template_candidate_for_product_v1(
  'slimme_documentenflow',
  'LWS_SDF_QUOTATION_NL_BE',
  '1.0.0-official',
  'QUOTATION',
  'nl-BE',
  'EUR',
  '33DA6DBBEEF02876D0624D28FB17A16787CB1E7D0BDE8EE74026664BA7739C1D',
  'assets/docs/quotation/LWS_SDF_QUOTATION_NL_BE_OFFICIAL_v1.docx',
  1::smallint,
  'not-implemented',
  1::smallint,
  1::smallint,
  'checkpoint:F6HI',
  'F6HI_OFFICIAL_SDF_QUOTATION_TEMPLATE_REGISTRATION',
  null
);

select public.approve_quotation_template_v1(
  (
    select id
    from public.quotation_template_authorities
    where request_kind = 'slimme_documentenflow'
      and template_id = 'LWS_SDF_QUOTATION_NL_BE'
      and template_version = '1.0.0-official'
  ),
  'checkpoint:F6HI',
  'F6HI_OFFICIAL_SDF_QUOTATION_TEMPLATE_APPROVAL'
);
