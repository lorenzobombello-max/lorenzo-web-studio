begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(11);

select is(
  (select request_kind from public.quotation_template_authorities
   where template_id = 'LWS_QUOTATION_NL_BE'),
  'website',
  'existing approved quotation template is deterministically Website'
);
select is(
  (select template_id from public.resolve_approved_quotation_template_v1(
    'QUOTATION','nl-BE','EUR',1::smallint,1::smallint,1::smallint
  )),
  'LWS_QUOTATION_NL_BE',
  'legacy resolver preserves Website semantics'
);
select public.retire_quotation_template_v1(
  (select id from public.quotation_template_authorities
   where request_kind = 'slimme_documentenflow' and status = 'APPROVED'),
  'TEST_ONLY','Explicit missing-SDF authority scenario',
  'PRODUCT_AUTHORITY_MISSING_SDF_SCENARIO'
);
select throws_ok(
  $$select * from public.resolve_approved_quotation_template_for_product_v1(
    'slimme_documentenflow','QUOTATION','nl-BE','EUR',
    1::smallint,1::smallint,1::smallint
  )$$,
  'P0001','QUOTATION_TEMPLATE_NOT_APPROVED',
  'SDF never falls back to the Website template'
);

select public.register_quotation_template_candidate_for_product_v1(
  'slimme_documentenflow','SYNTHETIC_SDF_QUOTATION','test-v1','QUOTATION',
  'nl-BE','EUR',repeat('A',64),'synthetic/sdf-quotation.docx',
  1::smallint,'synthetic-sdf-renderer-v1',1::smallint,1::smallint,
  'TEST_ONLY','PRODUCT_AUTHORITY_TEST',null
);
select lives_ok(
  $$select public.approve_quotation_template_v1(
    (select id from public.quotation_template_authorities
     where template_id='SYNTHETIC_SDF_QUOTATION'),
    'TEST_ONLY','PRODUCT_AUTHORITY_TEST_APPROVE'
  )$$,
  'SDF may approve its own template alongside Website'
);
select is(
  (select template_id from public.resolve_approved_quotation_template_for_product_v1(
    'website','QUOTATION','nl-BE','EUR',1::smallint,1::smallint,1::smallint
  )),
  'LWS_QUOTATION_NL_BE',
  'Website resolves only the Website template'
);
select is(
  (select template_id from public.resolve_approved_quotation_template_for_product_v1(
    'slimme_documentenflow','QUOTATION','nl-BE','EUR',
    1::smallint,1::smallint,1::smallint
  )),
  'SYNTHETIC_SDF_QUOTATION',
  'SDF resolves only the SDF template'
);
select ok(
  not public.is_approved_quotation_template_identity_for_product_v1(
    'website',jsonb_build_object(
      'template_id','SYNTHETIC_SDF_QUOTATION','template_version','test-v1',
      'template_sha256',lower(repeat('A',64)),'authority_status','APPROVED'
    )
  ),
  'Website rejects an SDF template identity'
);
select ok(
  not public.is_approved_quotation_template_identity_for_product_v1(
    'slimme_documentenflow',jsonb_build_object(
      'template_id','LWS_QUOTATION_NL_BE','template_version','1.0.0-technical',
      'template_sha256',lower('3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE'),
      'authority_status','APPROVED'
    )
  ),
  'SDF rejects the Website template identity'
);
select public.register_quotation_template_candidate_for_product_v1(
  'slimme_documentenflow','SYNTHETIC_SDF_QUOTATION_2','test-v1','QUOTATION',
  'nl-BE','EUR',repeat('B',64),'synthetic/sdf-quotation-2.docx',
  1::smallint,'synthetic-sdf-renderer-v1',1::smallint,1::smallint,
  'TEST_ONLY','PRODUCT_AUTHORITY_DUPLICATE_TEST',null
);
select throws_ok(
  $$select public.approve_quotation_template_v1(
    (select id from public.quotation_template_authorities
     where template_id='SYNTHETIC_SDF_QUOTATION_2'),
    'TEST_ONLY','PRODUCT_AUTHORITY_DUPLICATE_APPROVE'
  )$$,
  'P0001','TEMPLATE_AUTHORITY_AMBIGUOUS',
  'duplicate approved template in one product contract is rejected'
);
select is(
  (select count(*)::integer from public.quotation_template_authorities
   where status='APPROVED' and document_type='QUOTATION' and locale='nl-BE'
     and currency='EUR' and renderer_contract_version=1
     and generation_contract_version=1 and semantic_contract_version=1),
  2,
  'different product families retain one approved template each'
);
select throws_ok(
  $$select public.register_quotation_template_candidate_for_product_v1(
    'sdf','INVALID_PRODUCT','test-v1','QUOTATION','nl-BE','EUR',repeat('C',64),
    'synthetic/invalid.docx',1::smallint,'synthetic',1::smallint,1::smallint,
    'TEST_ONLY','INVALID_PRODUCT_TEST',null
  )$$,
  '22023','TEMPLATE_AUTHORITY_INPUT_INVALID',
  'unproven product vocabulary fails closed'
);

select * from finish();
rollback;
