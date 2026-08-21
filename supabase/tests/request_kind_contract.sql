begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(31);

select has_column('public', 'quote_requests', 'request_kind', 'request_kind column exists');
select has_column('public', 'quote_requests', 'sdf_package', 'SDF package identity column exists');
select col_default_is('public', 'quote_requests', 'request_kind', 'website', 'legacy rows and inserts default to website');
select col_not_null('public', 'quote_requests', 'request_kind', 'request_kind is never null');
select ok(
  exists(select 1 from pg_constraint where conname='quote_requests_request_kind_check' and conrelid='public.quote_requests'::regclass),
  'request_kind has a closed value constraint'
);
select ok(
  exists(select 1 from pg_constraint where conname='quote_requests_request_kind_shape_check' and conrelid='public.quote_requests'::regclass),
  'request kind controls website-only fields'
);
select ok(
  exists(select 1 from pg_constraint where conname='quote_requests_sdf_package_shape_check' and conrelid='public.quote_requests'::regclass),
  'request kind controls SDF package identity'
);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description, privacy_consent, status
) values (
  '44000000-0000-4000-8000-000000000001', 'Legacy website request', 'legacy@example.test',
  'Bedrijfswebsite', 'EUR 1.500 - EUR 3.000', 'Binnen 2 tot 3 maanden',
  'Legacy website request fixture.', true, 'approved'
);

select is(
  (select request_kind from public.quote_requests where id = '44000000-0000-4000-8000-000000000001'),
  'website',
  'omitted request_kind preserves website semantics'
);

insert into public.quote_requests (
  id, request_kind, name, email, website_type, budget, timing, description, privacy_consent, status
) values (
  '44000000-0000-4000-8000-000000000002', 'slimme_documentenflow',
  'Documentenflow request', 'flow@example.test', null, null, null,
  'Documentenflow request fixture.', true, 'approved'
);

select is(
  (select request_kind from public.quote_requests where id = '44000000-0000-4000-8000-000000000002'),
  'slimme_documentenflow',
  'Documentenflow request persists distinctly'
);

select throws_ok(
  $$insert into public.quote_requests (request_kind,name,email,description,privacy_consent,status) values ('unknown','Unknown','unknown@example.test','Unknown kind fixture.',true,'approved')$$,
  '23514', null, 'unknown request_kind is rejected by the database'
);

select throws_ok(
  $$insert into public.quote_requests (request_kind,sdf_package,name,email,description,privacy_consent,status) values ('slimme_documentenflow','onbekend','Unknown package','unknown-package@example.test','Unknown package fixture.',true,'approved')$$,
  '23514', null, 'unknown SDF package is rejected by the database'
);

select throws_ok(
  $$insert into public.quote_requests (request_kind,sdf_package,name,email,website_type,budget,timing,description,privacy_consent,status) values ('website','start','Website package','website-package@example.test','Andere','Meer dan EUR 6.000','Flexibel / nog te bepalen','Website package fixture.',true,'approved')$$,
  '23514', null, 'Website request cannot carry an SDF package'
);

select throws_ok(
  $$insert into public.quote_requests (request_kind,name,email,website_type,budget,timing,description,privacy_consent,status) values ('slimme_documentenflow','Fabricated','fabricated@example.test','Andere','Meer dan EUR 6.000','flexible','Fabricated website fields.',true,'approved')$$,
  '23514', null, 'Documentenflow cannot carry fabricated website fields'
);

select throws_ok(
  $$insert into public.quote_requests (request_kind,name,email,description,privacy_consent,status) values ('website','Incomplete','incomplete@example.test','Incomplete website fixture.',true,'approved')$$,
  '23514', null, 'website requests still require website fields'
);

select throws_ok(
  $$update public.quote_requests set request_kind='slimme_documentenflow' where id='44000000-0000-4000-8000-000000000001'$$,
  '55000', 'REQUEST_KIND_IMMUTABLE', 'website request cannot silently become Documentenflow'
);

select throws_ok(
  $$update public.quote_requests set status='rejected' where id='44000000-0000-4000-8000-000000000002'$$,
  '42501', 'REQUEST_KIND_ACTION_NOT_ALLOWED', 'Documentenflow cannot enter website review transitions'
);

select throws_ok(
  $$insert into public.quote_request_intakes (quote_request_id,access_token_hash,access_token_expires_at) values ('44000000-0000-4000-8000-000000000002',repeat('d',64),clock_timestamp()+interval '1 day')$$,
  '42501', 'REQUEST_KIND_INTAKE_NOT_ALLOWED', 'Documentenflow cannot enter website intake'
);

insert into public.quote_request_intakes (
  quote_request_id, access_token_hash, access_token_expires_at
) values (
  '44000000-0000-4000-8000-000000000001', repeat('w',64), clock_timestamp()+interval '1 day'
);

select is(
  (select count(*)::integer from public.quote_request_intakes where quote_request_id='44000000-0000-4000-8000-000000000001'),
  1,
  'website intake eligibility remains unchanged'
);

select throws_ok(
  $$select * from public.create_quote_request_idempotent(
    p_idempotency_key=>'44000000-0000-4000-8000-000000000010',
    p_request_fingerprint=>repeat('a',64),p_request_kind=>null,p_sdf_package=>null,p_name=>'Null kind',p_customer_type=>'individual',
    p_company=>null,p_enterprise_number=>null,p_enterprise_validation_status=>'not_checked',p_vat_number=>null,
    p_vat_validation_status=>'not_checked',p_vat_validated_at=>null,p_billing_address=>null,p_billing_postal_code=>null,
    p_billing_city=>null,p_billing_country=>null,p_billing_email=>null,p_email=>'null@example.test',p_phone=>null,
    p_website_type=>null,p_budget=>null,p_timing=>null,p_description=>'Null request kind fixture.',p_privacy_consent=>true,
    p_approval_token_hash=>repeat('a',64),p_approval_token_expires_at=>clock_timestamp()+interval '1 day',
    p_client_ip_hash=>repeat('b',64),p_user_agent=>'pgtap')$$,
  '22023', 'INVALID_REQUEST_KIND', 'null request_kind fails closed at the RPC boundary'
);

create temporary table stored_documentenflow as
select * from public.create_quote_request_idempotent(
  p_idempotency_key=>'44000000-0000-4000-8000-000000000011',
  p_request_fingerprint=>repeat('c',64),p_request_kind=>'slimme_documentenflow',p_sdf_package=>'start',p_name=>'Stored flow',p_customer_type=>'individual',
  p_company=>null,p_enterprise_number=>null,p_enterprise_validation_status=>'not_checked',p_vat_number=>null,
  p_vat_validation_status=>'not_checked',p_vat_validated_at=>null,p_billing_address=>null,p_billing_postal_code=>null,
  p_billing_city=>null,p_billing_country=>null,p_billing_email=>null,p_email=>'stored-flow@example.test',p_phone=>null,
  p_website_type=>null,p_budget=>null,p_timing=>null,p_description=>'Stored Documentenflow request.',p_privacy_consent=>true,
  p_approval_token_hash=>repeat('c',64),p_approval_token_expires_at=>clock_timestamp()+interval '1 day',
  p_client_ip_hash=>repeat('d',64),p_user_agent=>'pgtap'
);

select is((select was_created from stored_documentenflow), true, 'request-kind-aware RPC creates Documentenflow request');
select is(
  (select request_kind from public.quote_requests where id=(select request_id from stored_documentenflow)),
  'slimme_documentenflow',
  'request-kind-aware RPC persists Documentenflow kind'
);
select is(
  (select website_type from public.quote_requests where id=(select request_id from stored_documentenflow)),
  null::text,
  'request-kind-aware RPC persists no fabricated website type'
);
select is(
  (select sdf_package from public.quote_requests where id=(select request_id from stored_documentenflow)),
  'start',
  'request-kind-aware RPC persists START package identity'
);

select throws_ok(
  $$select * from public.create_quote_request_idempotent(
    p_idempotency_key=>'44000000-0000-4000-8000-000000000012',p_request_fingerprint=>repeat('d',64),
    p_request_kind=>'slimme_documentenflow',p_sdf_package=>null,p_name=>'Missing package',p_customer_type=>'individual',
    p_company=>null,p_enterprise_number=>null,p_enterprise_validation_status=>'not_checked',p_vat_number=>null,
    p_vat_validation_status=>'not_checked',p_vat_validated_at=>null,p_billing_address=>null,p_billing_postal_code=>null,
    p_billing_city=>null,p_billing_country=>null,p_billing_email=>null,p_email=>'missing-package@example.test',p_phone=>null,
    p_website_type=>null,p_budget=>null,p_timing=>null,p_description=>'Missing package request.',p_privacy_consent=>true,
    p_approval_token_hash=>repeat('d',64),p_approval_token_expires_at=>clock_timestamp()+interval '1 day',
    p_client_ip_hash=>repeat('e',64),p_user_agent=>'pgtap')$$,
  '22023', 'INVALID_DOCUMENTENFLOW_REQUEST_SHAPE', 'new SDF request without package fails closed at RPC boundary'
);

select throws_ok(
  $$select * from public.create_quote_request_idempotent(
    p_idempotency_key=>'44000000-0000-4000-8000-000000000013',p_request_fingerprint=>repeat('e',64),
    p_request_kind=>'slimme_documentenflow',p_sdf_package=>'onbekend',p_name=>'Invalid package',p_customer_type=>'individual',
    p_company=>null,p_enterprise_number=>null,p_enterprise_validation_status=>'not_checked',p_vat_number=>null,
    p_vat_validation_status=>'not_checked',p_vat_validated_at=>null,p_billing_address=>null,p_billing_postal_code=>null,
    p_billing_city=>null,p_billing_country=>null,p_billing_email=>null,p_email=>'invalid-package@example.test',p_phone=>null,
    p_website_type=>null,p_budget=>null,p_timing=>null,p_description=>'Invalid package request.',p_privacy_consent=>true,
    p_approval_token_hash=>repeat('e',64),p_approval_token_expires_at=>clock_timestamp()+interval '1 day',
    p_client_ip_hash=>repeat('f',64),p_user_agent=>'pgtap')$$,
  '22023', 'INVALID_DOCUMENTENFLOW_REQUEST_SHAPE', 'unknown SDF package fails closed at RPC boundary'
);

select throws_ok(
  $$select * from public.create_quote_request_idempotent(
    p_idempotency_key=>'44000000-0000-4000-8000-000000000014',p_request_fingerprint=>repeat('f',64),
    p_request_kind=>'website',p_sdf_package=>'start',p_name=>'Website package',p_customer_type=>'individual',
    p_company=>null,p_enterprise_number=>null,p_enterprise_validation_status=>'not_checked',p_vat_number=>null,
    p_vat_validation_status=>'not_checked',p_vat_validated_at=>null,p_billing_address=>null,p_billing_postal_code=>null,
    p_billing_city=>null,p_billing_country=>null,p_billing_email=>null,p_email=>'website-package-rpc@example.test',p_phone=>null,
    p_website_type=>'Andere',p_budget=>'Meer dan EUR 6.000',p_timing=>'Flexibel / nog te bepalen',p_description=>'Website package request.',p_privacy_consent=>true,
    p_approval_token_hash=>repeat('f',64),p_approval_token_expires_at=>clock_timestamp()+interval '1 day',
    p_client_ip_hash=>repeat('1',64),p_user_agent=>'pgtap')$$,
  '22023', 'INVALID_WEBSITE_REQUEST_SHAPE', 'Website package identity fails closed at RPC boundary'
);

create temporary table stored_groei as
select * from public.create_quote_request_idempotent(
  p_idempotency_key=>'44000000-0000-4000-8000-000000000015',p_request_fingerprint=>repeat('1',64),
  p_request_kind=>'slimme_documentenflow',p_sdf_package=>'groei',p_name=>'Stored groei',p_customer_type=>'individual',
  p_company=>null,p_enterprise_number=>null,p_enterprise_validation_status=>'not_checked',p_vat_number=>null,
  p_vat_validation_status=>'not_checked',p_vat_validated_at=>null,p_billing_address=>null,p_billing_postal_code=>null,
  p_billing_city=>null,p_billing_country=>null,p_billing_email=>null,p_email=>'stored-groei@example.test',p_phone=>null,
  p_website_type=>null,p_budget=>null,p_timing=>null,p_description=>'Stored GROEI package request.',p_privacy_consent=>true,
  p_approval_token_hash=>repeat('1',64),p_approval_token_expires_at=>clock_timestamp()+interval '1 day',
  p_client_ip_hash=>repeat('2',64),p_user_agent=>'pgtap'
);
select is((select sdf_package from public.quote_requests where id=(select request_id from stored_groei)),'groei','request-kind-aware RPC persists GROEI package identity');

create temporary table stored_maatwerk as
select * from public.create_quote_request_idempotent(
  p_idempotency_key=>'44000000-0000-4000-8000-000000000016',p_request_fingerprint=>repeat('2',64),
  p_request_kind=>'slimme_documentenflow',p_sdf_package=>'maatwerk',p_name=>'Stored maatwerk',p_customer_type=>'individual',
  p_company=>null,p_enterprise_number=>null,p_enterprise_validation_status=>'not_checked',p_vat_number=>null,
  p_vat_validation_status=>'not_checked',p_vat_validated_at=>null,p_billing_address=>null,p_billing_postal_code=>null,
  p_billing_city=>null,p_billing_country=>null,p_billing_email=>null,p_email=>'stored-maatwerk@example.test',p_phone=>null,
  p_website_type=>null,p_budget=>null,p_timing=>null,p_description=>'Stored MAATWERK package request.',p_privacy_consent=>true,
  p_approval_token_hash=>repeat('2',64),p_approval_token_expires_at=>clock_timestamp()+interval '1 day',
  p_client_ip_hash=>repeat('3',64),p_user_agent=>'pgtap'
);
select is((select sdf_package from public.quote_requests where id=(select request_id from stored_maatwerk)),'maatwerk','request-kind-aware RPC persists MAATWERK package identity');

create temporary table replayed_documentenflow as
select * from public.create_quote_request_idempotent(
  p_idempotency_key=>'44000000-0000-4000-8000-000000000011',
  p_request_fingerprint=>repeat('c',64),p_request_kind=>'slimme_documentenflow',p_sdf_package=>'start',p_name=>'Stored flow',p_customer_type=>'individual',
  p_company=>null,p_enterprise_number=>null,p_enterprise_validation_status=>'not_checked',p_vat_number=>null,
  p_vat_validation_status=>'not_checked',p_vat_validated_at=>null,p_billing_address=>null,p_billing_postal_code=>null,
  p_billing_city=>null,p_billing_country=>null,p_billing_email=>null,p_email=>'stored-flow@example.test',p_phone=>null,
  p_website_type=>null,p_budget=>null,p_timing=>null,p_description=>'Stored Documentenflow request.',p_privacy_consent=>true,
  p_approval_token_hash=>repeat('c',64),p_approval_token_expires_at=>clock_timestamp()+interval '1 day',
  p_client_ip_hash=>repeat('d',64),p_user_agent=>'pgtap'
);
select is((select was_created from replayed_documentenflow),false,'same SDF package replay remains idempotent');
select is((select count(*)::integer from public.quote_requests where idempotency_key='44000000-0000-4000-8000-000000000011'),1,'same SDF package replay creates no duplicate request');
select ok(
  not has_function_privilege('service_role','public.guard_quote_request_kind_v1()','execute')
  and not has_function_privilege('service_role','public.guard_website_intake_kind_v1()','execute'),
  'trigger implementation functions are not executable by service_role'
);

select * from finish();
rollback;