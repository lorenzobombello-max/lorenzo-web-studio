begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(10);

select is(
  (
    select count(*)::integer
    from public.quotation_template_authorities
    where request_kind = 'slimme_documentenflow'
      and template_id = 'LWS_SDF_QUOTATION_NL_BE'
      and template_version = '1.0.0-official'
      and status = 'APPROVED'
  ),
  1,
  'exactly one official SDF template authority is approved'
);
select is(
  (
    select template_sha256
    from public.quotation_template_authorities
    where template_id = 'LWS_SDF_QUOTATION_NL_BE'
  ),
  '33DA6DBBEEF02876D0624D28FB17A16787CB1E7D0BDE8EE74026664BA7739C1D',
  'official authority stores the verified source SHA-256'
);
select is(
  (
    select technical_master_filename
    from public.quotation_template_authorities
    where template_id = 'LWS_SDF_QUOTATION_NL_BE'
  ),
  'assets/docs/quotation/LWS_SDF_QUOTATION_NL_BE_OFFICIAL_v1.docx',
  'official authority binds the dedicated repository asset'
);
select is(
  (
    select renderer_version
    from public.quotation_template_authorities
    where template_id = 'LWS_SDF_QUOTATION_NL_BE'
  ),
  'not-implemented',
  'Phase 3 authority explicitly does not claim a renderer implementation'
);
select is(
  (
    select template_id
    from public.resolve_approved_quotation_template_for_product_v1(
      'slimme_documentenflow','QUOTATION','nl-BE','EUR',
      1::smallint,1::smallint,1::smallint
    )
  ),
  'LWS_SDF_QUOTATION_NL_BE',
  'SDF resolves its official template'
);
select is(
  (
    select template_id
    from public.resolve_approved_quotation_template_for_product_v1(
      'website','QUOTATION','nl-BE','EUR',
      1::smallint,1::smallint,1::smallint
    )
  ),
  'LWS_QUOTATION_NL_BE',
  'Website continues to resolve its unchanged template'
);
select ok(
  public.is_approved_quotation_template_identity_for_product_v1(
    'slimme_documentenflow',jsonb_build_object(
      'template_id','LWS_SDF_QUOTATION_NL_BE',
      'template_version','1.0.0-official',
      'template_sha256','33da6dbbeef02876d0624d28fb17a16787cb1e7d0bde8ee74026664ba7739c1d',
      'authority_status','APPROVED'
    )
  ),
  'official SDF identity is accepted'
);
select ok(
  not public.is_approved_quotation_template_identity_for_product_v1(
    'slimme_documentenflow',jsonb_build_object(
      'template_id','LWS_SDF_QUOTATION_NL_BE',
      'template_version','1.0.0-official',
      'template_sha256',repeat('0',64),
      'authority_status','APPROVED'
    )
  ),
  'wrong official SDF hash is rejected'
);

select public.register_quotation_template_candidate_for_product_v1(
  'slimme_documentenflow','SYNTHETIC_UNAPPROVED_SDF_QUOTATION','test-v1',
  'QUOTATION','nl-BE','EUR',repeat('A',64),'synthetic/unapproved-sdf.docx',
  1::smallint,'not-implemented',1::smallint,1::smallint,
  'TEST_ONLY','OFFICIAL_SDF_UNAPPROVED_TEST',null
);
select ok(
  not public.is_approved_quotation_template_identity_for_product_v1(
    'slimme_documentenflow',jsonb_build_object(
      'template_id','SYNTHETIC_UNAPPROVED_SDF_QUOTATION',
      'template_version','test-v1','template_sha256',lower(repeat('A',64)),
      'authority_status','CANDIDATE'
    )
  ),
  'unapproved SDF candidate identity is rejected'
);
select throws_ok(
  $$select public.approve_quotation_template_v1(
    (select id from public.quotation_template_authorities
     where template_id = 'SYNTHETIC_UNAPPROVED_SDF_QUOTATION'),
    'TEST_ONLY','OFFICIAL_SDF_DUPLICATE_APPROVAL_TEST'
  )$$,
  'P0001','TEMPLATE_AUTHORITY_AMBIGUOUS',
  'a second approved SDF authority for the same contract is rejected'
);

select * from finish();
rollback;