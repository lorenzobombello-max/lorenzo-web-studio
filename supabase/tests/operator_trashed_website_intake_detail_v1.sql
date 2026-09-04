begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public',
  'get_operator_trashed_website_intake_detail_v1',
  array['uuid', 'text'],
  'dedicated Trash Website intake detail RPC exists'
);

select ok(
  has_function_privilege('service_role', 'public.get_operator_trashed_website_intake_detail_v1(uuid,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.get_operator_trashed_website_intake_detail_v1(uuid,text)', 'execute')
  and not has_function_privilege('anon', 'public.get_operator_trashed_website_intake_detail_v1(uuid,text)', 'execute'),
  'only the service-role Edge boundary can enter the Trash detail RPC'
);

select has_function(
  'public',
  'get_operator_trashed_website_intake_detail_caller_v1',
  array['text'],
  'authenticated Trash Website detail wrapper has no actor UUID parameter'
);

select ok(
  has_function_privilege('authenticated', 'public.get_operator_trashed_website_intake_detail_caller_v1(text)', 'execute')
  and not has_function_privilege('service_role', 'public.get_operator_trashed_website_intake_detail_caller_v1(text)', 'execute')
  and not has_function_privilege('anon', 'public.get_operator_trashed_website_intake_detail_caller_v1(text)', 'execute')
  and not has_function_privilege('public', 'public.get_operator_trashed_website_intake_detail_caller_v1(text)', 'execute'),
  'only authenticated callers can enter the auth.uid-bound wrapper'
);

select ok(
  to_regprocedure('public.get_operator_trashed_website_intake_detail_caller_v1(uuid,text)') is null,
  'caller wrapper exposes no actor UUID overload'
);

select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_caller_v1('#D8200001')$$,
  '42501', 'HUMAN_JWT_REQUIRED',
  'authenticated transport without auth.uid is rejected'
);
reset role;

insert into auth.users (id, email) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'step-2o-op01@example.test'),
  ('bd2ab636-0d42-4069-88a9-60bd97f2b335', 'step-2o-op02@example.test'),
  ('d0247fd9-60d5-40bc-a905-6b02024b6420', 'step-2o-op03@example.test'),
  ('d8100000-0000-4000-8000-000000000001', 'trash-detail-owner@example.test'),
  ('d8100000-0000-4000-8000-000000000002', 'trash-detail-operator@example.test'),
  ('d8100000-0000-4000-8000-000000000003', 'trash-detail-admin@example.test');

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values
  ('d8110010-0000-4000-8000-000000000010', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'Step 2O OP-01', 'owner', 'ACTIVE'),
  ('d8110020-0000-4000-8000-000000000020', 'bd2ab636-0d42-4069-88a9-60bd97f2b335', 'Step 2O OP-02', 'operations_manager', 'ACTIVE'),
  ('d8110000-0000-4000-8000-000000000001', 'd8100000-0000-4000-8000-000000000001', 'Trash detail owner', 'owner', 'ACTIVE'),
  ('d8110000-0000-4000-8000-000000000002', 'd8100000-0000-4000-8000-000000000002', 'Trash detail operator', 'operator', 'ACTIVE'),
  ('d8110000-0000-4000-8000-000000000003', 'd8100000-0000-4000-8000-000000000003', 'Trash detail admin', 'admin', 'ACTIVE');

insert into public.quote_requests (
  id, application_reference, record_classification, request_kind, sdf_package,
  name, email, website_type, budget, timing, description, privacy_consent, status
) values
  ('d8200001-0000-4000-8000-000000000001', null, 'production', 'website', null, 'Trash invited', 'trash-invited@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Trash invited detail fixture.', true, 'approved'),
  ('d8200002-0000-4000-8000-000000000002', null, 'production', 'website', null, 'Trash progress', 'trash-progress@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Trash progress detail fixture.', true, 'approved'),
  ('d8200003-0000-4000-8000-000000000003', 'LWS-AAN-2099-8203', 'production', 'website', null, 'Trash submitted', 'trash-submitted@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Trash submitted detail fixture.', true, 'approved'),
  ('d8200004-0000-4000-8000-000000000004', 'LWS-AAN-2099-8204', 'production', 'website', null, 'Trash reviewed', 'trash-reviewed@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Trash reviewed detail fixture.', true, 'approved'),
  ('d8200005-0000-4000-8000-000000000005', null, 'production', 'website', null, 'Active invited', 'active-invited@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Active invited detail fixture.', true, 'approved'),
  ('d8200006-0000-4000-8000-000000000006', null, 'production', 'website', null, 'Active progress', 'active-progress@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Active progress detail fixture.', true, 'approved'),
  ('d8200007-0000-4000-8000-000000000007', null, 'production', 'website', null, 'Missing intake', 'missing-intake@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Missing intake detail fixture.', true, 'approved'),
  ('d8200008-0000-4000-8000-000000000008', 'LWS-AAN-2099-8208', 'production', 'slimme_documentenflow', 'start', 'SDF unchanged', 'sdf-unchanged@example.test', null, null, null, 'SDF unchanged detail fixture.', true, 'approved'),
  ('d8200009-0000-4000-8000-000000000009', null, 'production', 'website', null, 'Archived invited', 'archived-invited@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Archived invited detail fixture.', true, 'approved'),
  ('d8200010-0000-4000-8000-000000000010', null, 'internal_e2e', 'website', null, 'Internal invited', 'internal-invited@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Internal invited detail fixture.', true, 'approved'),
  ('d8200011-0000-4000-8000-000000000011', null, 'production', 'slimme_documentenflow', 'start', 'Trash SDF invited', 'trash-sdf-invited@example.test', null, null, null, 'Trash SDF invited detail fixture.', true, 'approved');

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_state, lifecycle_revision, confirmation, created_at, started_at, submitted_at, reviewed_at
) values
  ('d8300001-0000-4000-8000-000000000001', 'd8200001-0000-4000-8000-000000000001', 'invited', repeat('1', 64), '2099-09-03T12:00:00Z', 'ACTIVE', 0, false, clock_timestamp(), null, null, null),
  ('d8300002-0000-4000-8000-000000000002', 'd8200002-0000-4000-8000-000000000002', 'in_progress', repeat('2', 64), '2099-09-03T12:00:00Z', 'ACTIVE', 0, false, clock_timestamp(), clock_timestamp(), null, null),
  ('d8300003-0000-4000-8000-000000000003', 'd8200003-0000-4000-8000-000000000003', 'submitted', repeat('3', 64), '2099-09-03T12:00:00Z', 'ACTIVE', 0, true, clock_timestamp(), clock_timestamp(), clock_timestamp(), null),
  ('d8300004-0000-4000-8000-000000000004', 'd8200004-0000-4000-8000-000000000004', 'reviewed', repeat('4', 64), '2099-09-03T12:00:00Z', 'ACTIVE', 0, true, clock_timestamp(), clock_timestamp(), clock_timestamp(), clock_timestamp()),
  ('d8300005-0000-4000-8000-000000000005', 'd8200005-0000-4000-8000-000000000005', 'invited', repeat('5', 64), '2099-09-03T12:00:00Z', 'ACTIVE', 0, false, clock_timestamp(), null, null, null),
  ('d8300006-0000-4000-8000-000000000006', 'd8200006-0000-4000-8000-000000000006', 'in_progress', repeat('6', 64), '2099-09-03T12:00:00Z', 'ACTIVE', 0, false, clock_timestamp(), clock_timestamp(), null, null),
  ('d8300009-0000-4000-8000-000000000009', 'd8200009-0000-4000-8000-000000000009', 'invited', repeat('9', 64), '2099-09-03T12:00:00Z', 'ACTIVE', 0, false, clock_timestamp(), null, null, null),
  ('d8300010-0000-4000-8000-000000000010', 'd8200010-0000-4000-8000-000000000010', 'invited', repeat('a', 64), '2099-09-03T12:00:00Z', 'ACTIVE', 0, false, clock_timestamp(), null, null, null);

update lws_internal.operator_dossier_states
set state = 'TRASHED', revision = 1, state_before_trash = 'ACTIVE', updated_at = clock_timestamp()
where quote_request_id in (
  'd8200001-0000-4000-8000-000000000001',
  'd8200002-0000-4000-8000-000000000002',
  'd8200003-0000-4000-8000-000000000003',
  'd8200004-0000-4000-8000-000000000004',
  'd8200007-0000-4000-8000-000000000007',
  'd8200011-0000-4000-8000-000000000011'
);

update lws_internal.operator_dossier_states
set state = 'ARCHIVED', revision = 1, updated_at = clock_timestamp()
where quote_request_id = 'd8200009-0000-4000-8000-000000000009';

select set_config('request.jwt.claim.sub', 'd8100000-0000-4000-8000-000000000001', true);

create temporary table expected_trash_detail (value jsonb not null) on commit drop;
insert into expected_trash_detail
select public.get_operator_trashed_website_intake_detail_v1(
  'd8100000-0000-4000-8000-000000000001',
  '#D8200001'
);
grant select on expected_trash_detail to authenticated;

set local role authenticated;
select is(
  public.get_operator_trashed_website_intake_detail_caller_v1('#D8200001'),
  (select value from expected_trash_detail),
  'caller wrapper returns the exact inner RPC DTO'
);
reset role;

select set_config('request.jwt.claim.sub', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', true);
set local role authenticated;
select lives_ok(
  $$select public.get_operator_trashed_website_intake_detail_caller_v1('#D8200001')$$,
  'OP-01 can read a TRASHED Website intake through caller JWT'
);
reset role;

select set_config('request.jwt.claim.sub', 'd8100000-0000-4000-8000-000000000003', true);
set local role authenticated;
select lives_ok(
  $$select public.get_operator_trashed_website_intake_detail_caller_v1('#D8200002')$$,
  'active admin can read a TRASHED Website intake through caller JWT'
);
reset role;

select set_config('request.jwt.claim.sub', 'bd2ab636-0d42-4069-88a9-60bd97f2b335', true);
set local role authenticated;
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_caller_v1('#D8200001')$$,
  '42501', 'APPLICATION_SCOPE_DENIED',
  'OP-02 keeps the existing application-scope denial'
);
reset role;

select set_config('request.jwt.claim.sub', 'd0247fd9-60d5-40bc-a905-6b02024b6420', true);
set local role authenticated;
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_caller_v1('#D8200001')$$,
  '42501', 'UNKNOWN_OPERATOR',
  'OP-03 keeps the existing unknown-operator denial'
);
reset role;

set local role anon;
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_caller_v1('#D8200001')$$,
  '42501', 'permission denied for function get_operator_trashed_website_intake_detail_caller_v1',
  'anon cannot execute the caller wrapper'
);
reset role;

set local role service_role;
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_caller_v1('#D8200001')$$,
  '42501', 'permission denied for function get_operator_trashed_website_intake_detail_caller_v1',
  'service role cannot execute the caller wrapper'
);
reset role;

select set_config('request.jwt.claim.sub', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', true);
set local role authenticated;
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_caller_v1('#D8200005')$$,
  'P0001', 'APPLICATION_NOT_FOUND', 'ACTIVE Website invited remains unavailable through the wrapper'
);
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_caller_v1('#D8200009')$$,
  'P0001', 'APPLICATION_NOT_FOUND', 'ARCHIVED Website invited remains unavailable through the wrapper'
);
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_caller_v1('#D8200011')$$,
  'P0001', 'APPLICATION_NOT_FOUND', 'TRASHED SDF invited remains unavailable through the wrapper'
);
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_caller_v1('#D8200010')$$,
  'P0001', 'APPLICATION_NOT_FOUND', 'non-production Website invited remains unavailable through the wrapper'
);
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_caller_v1('#D8200003')$$,
  'P0001', 'APPLICATION_NOT_FOUND', 'submitted Trash intake remains outside the fallback'
);
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_caller_v1('#D8200004')$$,
  'P0001', 'APPLICATION_NOT_FOUND', 'reviewed Trash intake remains outside the fallback'
);
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_caller_v1('#D8200007')$$,
  'P0001', 'APPLICATION_NOT_FOUND', 'missing intake fails closed through the wrapper'
);
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_caller_v1('#D8299999')$$,
  'P0001', 'APPLICATION_NOT_FOUND', 'unknown support reference fails closed through the wrapper'
);
select is(
  public.get_operator_trashed_website_intake_detail_caller_v1('#D8200002')->>'quote_request_id',
  'd8200002-0000-4000-8000-000000000002',
  'wrapper binds the support reference to the canonical quote request'
);
select is(
  public.get_operator_trashed_website_intake_detail_caller_v1('#D8200002')->>'intake_status',
  'in_progress',
  'wrapper preserves the canonical one-to-one intake binding'
);
select is(
  public.get_operator_trashed_website_intake_detail_caller_v1('#D8200002')->'dossier_lifecycle',
  jsonb_build_object('state', 'TRASHED', 'revision', 1),
  'wrapper preserves the canonical Trash lifecycle binding'
);
reset role;

select is(
  public.get_operator_trashed_website_intake_detail_v1('d8100000-0000-4000-8000-000000000001', '#D8200001')->>'operational_status',
  'INVITED',
  'TRASHED Website invited detail is readable'
);
select is(
  public.get_operator_trashed_website_intake_detail_v1('d8100000-0000-4000-8000-000000000001', '#D8200002')->>'operational_status',
  'IN_PROGRESS',
  'TRASHED Website in-progress detail is readable'
);
select is(
  public.get_operator_application_by_support_reference_v1('#D8200003'),
  public.get_operator_application_v1('d8200003-0000-4000-8000-000000000003', null),
  'TRASHED Website submitted preserves the historical detail flow'
);
select is(
  public.get_operator_application_by_support_reference_v1('#D8200004'),
  public.get_operator_application_v1('d8200004-0000-4000-8000-000000000004', null),
  'TRASHED Website reviewed preserves the historical detail flow'
);

select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_v1('d8100000-0000-4000-8000-000000000001', '#D8200005')$$,
  'P0001', 'APPLICATION_NOT_FOUND', 'non-TRASHED Website invited remains unavailable as application detail'
);
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_v1('d8100000-0000-4000-8000-000000000001', '#D8200006')$$,
  'P0001', 'APPLICATION_NOT_FOUND', 'non-TRASHED Website in-progress remains unavailable as application detail'
);
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_v1('d8100000-0000-4000-8000-000000000002', '#D8200001')$$,
  '42501', 'APPLICATION_SCOPE_DENIED', 'unauthorized operator is rejected'
);
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_v1('d8100000-0000-4000-8000-000000000001', '#D8200007')$$,
  'P0001', 'APPLICATION_NOT_FOUND', 'canonical record without a matching intake fails closed'
);
select throws_ok(
  $$select public.get_operator_trashed_website_intake_detail_v1('d8100000-0000-4000-8000-000000000001', '#D8299999')$$,
  'P0001', 'APPLICATION_NOT_FOUND', 'missing dossier fails closed'
);
select is(
  public.get_operator_application_by_support_reference_v1('#D8200008'),
  public.get_operator_application_v1('d8200008-0000-4000-8000-000000000008', null),
  'SDF support-reference detail remains unchanged'
);
select is(
  public.get_operator_trashed_website_intake_detail_v1('d8100000-0000-4000-8000-000000000001', '#D8200001')->'dossier_lifecycle',
  jsonb_build_object('state', 'TRASHED', 'revision', 1),
  'Trash detail binds canonical lifecycle state and revision'
);
select is(
  public.get_operator_trashed_website_intake_detail_v1('d8100000-0000-4000-8000-000000000001', '#D8200001')->>'quote_request_id',
  'd8200001-0000-4000-8000-000000000001',
  'Trash detail identity is bound to the canonical support reference'
);

select * from finish();
rollback;