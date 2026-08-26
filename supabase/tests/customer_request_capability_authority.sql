begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public', 'resolve_customer_request_authorization_v1', array['uuid', 'text'],
  'central request-scoped authorization resolver exists'
);
select has_function(
  'public', 'get_customer_request_v1', array['uuid'],
  'minimal Customer Request read boundary exists'
);
select has_function(
  'public', 'transition_customer_request_v1', array['uuid', 'text', 'bigint', 'uuid', 'jsonb'],
  'authenticated Customer Request transition boundary exists'
);
select ok(
  has_function_privilege('authenticated', 'public.get_customer_request_v1(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.transition_customer_request_v1(uuid,text,bigint,uuid,jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.resolve_customer_request_authorization_v1(uuid,text)', 'execute')
  and not has_function_privilege('anon', 'public.get_customer_request_v1(uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.get_customer_request_v1(uuid)', 'execute'),
  'only the two minimal authenticated entrypoints are exposed'
);
select ok(
  not has_function_privilege('authenticated', 'lws_internal.transition_customer_request_core_v1(uuid,text,bigint,uuid,jsonb)', 'execute')
  and not has_table_privilege('authenticated', 'public.customer_requests', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.customer_request_events', 'select,insert,update,delete'),
  'private core and Customer Request tables remain inaccessible to authenticated runtime'
);
select is(
  pg_get_function_arguments('public.get_customer_request_v1(uuid)'::regprocedure),
  'p_request_id uuid',
  'read boundary accepts no client identity or authority inputs'
);
select is(
  pg_get_function_arguments('public.transition_customer_request_v1(uuid,text,bigint,uuid,jsonb)'::regprocedure),
  'p_request_id uuid, p_command_type text, p_expected_revision bigint, p_idempotency_key uuid, p_payload jsonb DEFAULT ''{}''::jsonb',
  'transition boundary accepts no client identity or authority inputs'
);

insert into auth.users(id, email) values
  ('d9000000-0000-4000-8000-000000000001', 'capability-owner@example.test'),
  ('d9000000-0000-4000-8000-000000000002', 'capability-manager@example.test'),
  ('d9000000-0000-4000-8000-000000000003', 'capability-operator-a@example.test'),
  ('d9000000-0000-4000-8000-000000000004', 'capability-operator-b@example.test'),
  ('d9000000-0000-4000-8000-000000000005', 'capability-reviewer@example.test'),
  ('d9000000-0000-4000-8000-000000000006', 'capability-read-only@example.test'),
  ('d9000000-0000-4000-8000-000000000007', 'capability-admin@example.test'),
  ('d9000000-0000-4000-8000-000000000008', 'capability-disabled@example.test'),
  ('d9000000-0000-4000-8000-000000000009', 'capability-revoked@example.test'),
  ('d9000000-0000-4000-8000-000000000010', 'capability-unknown@example.test');

insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status, revoked_at
) values
  ('d9010000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000001', 'Capability Owner', 'owner', 'ACTIVE', null),
  ('d9010000-0000-4000-8000-000000000002', 'd9000000-0000-4000-8000-000000000002', 'Capability Manager', 'operations_manager', 'ACTIVE', null),
  ('d9010000-0000-4000-8000-000000000003', 'd9000000-0000-4000-8000-000000000003', 'Capability Operator A', 'operator', 'ACTIVE', null),
  ('d9010000-0000-4000-8000-000000000004', 'd9000000-0000-4000-8000-000000000004', 'Capability Operator B', 'operator', 'ACTIVE', null),
  ('d9010000-0000-4000-8000-000000000005', 'd9000000-0000-4000-8000-000000000005', 'Capability Reviewer', 'reviewer', 'ACTIVE', null),
  ('d9010000-0000-4000-8000-000000000006', 'd9000000-0000-4000-8000-000000000006', 'Capability Read Only', 'read_only', 'ACTIVE', null),
  ('d9010000-0000-4000-8000-000000000007', 'd9000000-0000-4000-8000-000000000007', 'Capability Admin', 'admin', 'ACTIVE', null),
  ('d9010000-0000-4000-8000-000000000008', 'd9000000-0000-4000-8000-000000000008', 'Capability Disabled', 'operator', 'DISABLED', null),
  ('d9010000-0000-4000-8000-000000000009', 'd9000000-0000-4000-8000-000000000009', 'Capability Revoked', 'operator', 'REVOKED', statement_timestamp());

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind,
  name, email, website_type, budget, timing, description, privacy_consent, status
) values
  ('d9100001-0000-4000-8000-000000000001', 'LWS-AAN-2099-0901', 'production', 'website', 'Capability A', 'a@example.test', 'business', 'x', 'x', 'Capability fixture A.', true, 'approved'),
  ('d9100002-0000-4000-8000-000000000002', 'LWS-AAN-2099-0902', 'production', 'website', 'Capability B', 'b@example.test', 'business', 'x', 'x', 'Capability fixture B.', true, 'approved'),
  ('d9100003-0000-4000-8000-000000000003', 'LWS-AAN-2099-0903', 'production', 'website', 'Capability C', 'c@example.test', 'business', 'x', 'x', 'Capability fixture C.', true, 'approved'),
  ('d9100004-0000-4000-8000-000000000004', 'LWS-AAN-2099-0904', 'production', 'website', 'Capability D', 'd@example.test', 'business', 'x', 'x', 'Capability fixture D.', true, 'approved'),
  ('d9100005-0000-4000-8000-000000000005', 'LWS-AAN-2099-0905', 'production', 'website', 'Capability E', 'e@example.test', 'business', 'x', 'x', 'Capability fixture E.', true, 'approved'),
  ('d9100006-0000-4000-8000-000000000006', 'LWS-AAN-2099-0906', 'production', 'website', 'Capability F', 'f@example.test', 'business', 'x', 'x', 'Capability fixture F.', true, 'approved');

set local session_replication_role = replica;

insert into public.commercial_customers(customer_id, acceptance_id, identity_sha256) values
  ('d9300000-0000-4000-8000-000000000001', 'd9310001-0000-4000-8000-000000000001', repeat('1', 64)),
  ('d9300000-0000-4000-8000-000000000002', 'd9310002-0000-4000-8000-000000000002', repeat('2', 64)),
  ('d9300000-0000-4000-8000-000000000003', 'd9310003-0000-4000-8000-000000000003', repeat('3', 64)),
  ('d9300000-0000-4000-8000-000000000004', 'd9310004-0000-4000-8000-000000000004', repeat('4', 64)),
  ('d9300000-0000-4000-8000-000000000005', 'd9310005-0000-4000-8000-000000000005', repeat('5', 64)),
  ('d9300000-0000-4000-8000-000000000006', 'd9310006-0000-4000-8000-000000000006', repeat('6', 64));

insert into public.commercial_projects(
  project_id, customer_id, quotation_issuance_id, acceptance_id,
  accepted_total_minor, currency, m1_minor, m2_minor, m3_minor,
  current_state, revision
) values
  ('d9400000-0000-4000-8000-000000000001', 'd9300000-0000-4000-8000-000000000001', 'd9410001-0000-4000-8000-000000000001', 'd9310001-0000-4000-8000-000000000001', 0, 'EUR', 0, 0, 0, 'PROJECT_RELEASED', 0),
  ('d9400000-0000-4000-8000-000000000002', 'd9300000-0000-4000-8000-000000000002', 'd9410002-0000-4000-8000-000000000002', 'd9310002-0000-4000-8000-000000000002', 0, 'EUR', 0, 0, 0, 'PROJECT_RELEASED', 0),
  ('d9400000-0000-4000-8000-000000000003', 'd9300000-0000-4000-8000-000000000003', 'd9410003-0000-4000-8000-000000000003', 'd9310003-0000-4000-8000-000000000003', 0, 'EUR', 0, 0, 0, 'PROJECT_RELEASED', 0),
  ('d9400000-0000-4000-8000-000000000004', 'd9300000-0000-4000-8000-000000000004', 'd9410004-0000-4000-8000-000000000004', 'd9310004-0000-4000-8000-000000000004', 0, 'EUR', 0, 0, 0, 'PROJECT_RELEASED', 0),
  ('d9400000-0000-4000-8000-000000000005', 'd9300000-0000-4000-8000-000000000005', 'd9410005-0000-4000-8000-000000000005', 'd9310005-0000-4000-8000-000000000005', 0, 'EUR', 0, 0, 0, 'PROJECT_RELEASED', 0),
  ('d9400000-0000-4000-8000-000000000006', 'd9300000-0000-4000-8000-000000000006', 'd9410006-0000-4000-8000-000000000006', 'd9310006-0000-4000-8000-000000000006', 0, 'EUR', 0, 0, 0, 'PROJECT_RELEASED', 0);

insert into public.customer_requests(
  request_id, request_reference, quote_request_id, customer_id, project_id,
  source, request_type, title, description, status, priority,
  submitted_at, submitter_type, revision
) values
  ('d9200000-0000-4000-8000-000000000001', 'LWS-VRZ-2099-0901', 'd9100001-0000-4000-8000-000000000001', 'd9300000-0000-4000-8000-000000000001', 'd9400000-0000-4000-8000-000000000001', 'OPERATOR', 'OTHER', 'Assigned request', 'Assigned request detail.', 'NEW', 'NORMAL', statement_timestamp(), 'OPERATOR', 0),
  ('d9200000-0000-4000-8000-000000000002', 'LWS-VRZ-2099-0902', 'd9100002-0000-4000-8000-000000000002', 'd9300000-0000-4000-8000-000000000002', 'd9400000-0000-4000-8000-000000000002', 'OPERATOR', 'OTHER', 'Other dossier', 'Other customer detail.', 'NEW', 'HIGH', statement_timestamp(), 'OPERATOR', 0),
  ('d9200000-0000-4000-8000-000000000003', 'LWS-VRZ-2099-0903', 'd9100003-0000-4000-8000-000000000003', 'd9300000-0000-4000-8000-000000000003', 'd9400000-0000-4000-8000-000000000003', 'OPERATOR', 'TECHNICAL_CHANGE', 'Work request', 'Work transition detail.', 'TRIAGED', 'NORMAL', statement_timestamp(), 'OPERATOR', 0),
  ('d9200000-0000-4000-8000-000000000004', 'LWS-VRZ-2099-0904', 'd9100004-0000-4000-8000-000000000004', 'd9300000-0000-4000-8000-000000000004', 'd9400000-0000-4000-8000-000000000004', 'OPERATOR', 'OTHER', 'Owner terminal request', 'Owner terminal detail.', 'NEW', null, statement_timestamp(), 'OPERATOR', 0),
  ('d9200000-0000-4000-8000-000000000005', 'LWS-VRZ-2099-0905', 'd9100005-0000-4000-8000-000000000005', 'd9300000-0000-4000-8000-000000000005', 'd9400000-0000-4000-8000-000000000005', 'OPERATOR', 'OTHER', 'Manager terminal request', 'Manager terminal detail.', 'NEW', null, statement_timestamp(), 'OPERATOR', 0),
  ('d9200000-0000-4000-8000-000000000006', 'LWS-VRZ-2099-0906', 'd9100006-0000-4000-8000-000000000006', 'd9300000-0000-4000-8000-000000000006', 'd9400000-0000-4000-8000-000000000006', 'OPERATOR', 'OTHER', 'Manager triage request', 'Manager triage detail.', 'NEW', null, statement_timestamp(), 'OPERATOR', 0);

update lws_internal.operator_dossier_assignments
set assignee_operator_id = 'd9010000-0000-4000-8000-000000000003',
    assigned_at = statement_timestamp(),
    updated_at = statement_timestamp(),
    revision = 1
where quote_request_id in (
  'd9100001-0000-4000-8000-000000000001',
  'd9100003-0000-4000-8000-000000000003'
);

insert into public.commercial_operator_project_grants(
  operator_id, project_id, access_level, granted_by, revoked_at
) values
  ('d9010000-0000-4000-8000-000000000005', 'd9400000-0000-4000-8000-000000000001', 'reviewer', 'd9010000-0000-4000-8000-000000000001', null),
  ('d9010000-0000-4000-8000-000000000006', 'd9400000-0000-4000-8000-000000000001', 'read_only', 'd9010000-0000-4000-8000-000000000001', null);

set local session_replication_role = origin;

select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.get_customer_request_v1('d9200000-0000-4000-8000-000000000001')$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'read requires auth.uid derived human identity'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000010', true);
select throws_ok(
  $$select public.get_customer_request_v1('d9200000-0000-4000-8000-000000000001')$$,
  '42501', 'UNKNOWN_OPERATOR', 'unknown authenticated identity cannot supply operator authority'
);

select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000001', true);
select is(
  public.get_customer_request_v1('d9200000-0000-4000-8000-000000000002')->>'request_reference',
  'LWS-VRZ-2099-0902', 'owner has global VIEW authority'
);
select is(
  (select count(*)::integer from jsonb_object_keys(public.get_customer_request_v1('d9200000-0000-4000-8000-000000000002'))),
  11, 'read projection exposes exactly eleven operational fields'
);
select ok(
  not (public.get_customer_request_v1('d9200000-0000-4000-8000-000000000002') ?| array['customer_id','project_id','quote_request_id','linked_change_order_id']),
  'read projection exposes no customer, project, dossier, or change-order identifiers'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$select public.get_customer_request_v1('d9200000-0000-4000-8000-000000000002')$$,
  'Operations Manager has global VIEW authority'
);

select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000003', true);
select lives_ok(
  $$select public.get_customer_request_v1('d9200000-0000-4000-8000-000000000001')$$,
  'assigned ACTIVE operator views own request'
);
select throws_ok(
  $$select public.get_customer_request_v1('d9200000-0000-4000-8000-000000000002')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'operator receives cross-dossier and cross-customer denial'
);
select throws_ok(
  $$select public.get_customer_request_v1('d9299999-0000-4000-8000-000000000099')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'guessed request identity reveals no existence information'
);

select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000005', true);
select lives_ok(
  $$select public.get_customer_request_v1('d9200000-0000-4000-8000-000000000001')$$,
  'reviewer VIEW follows an active project grant'
);
select throws_ok(
  $$select public.get_customer_request_v1('d9200000-0000-4000-8000-000000000002')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'reviewer without matching project grant is denied'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000006', true);
select lives_ok(
  $$select public.get_customer_request_v1('d9200000-0000-4000-8000-000000000001')$$,
  'read-only VIEW follows an active project grant'
);

set local session_replication_role = replica;
update public.commercial_operator_project_grants
set revoked_at = statement_timestamp()
where project_id = 'd9400000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select throws_ok(
  $$select public.get_customer_request_v1('d9200000-0000-4000-8000-000000000001')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'revoked read-only grant removes VIEW authority'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select public.get_customer_request_v1('d9200000-0000-4000-8000-000000000001')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'revoked reviewer grant removes VIEW authority'
);

select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000007', true);
select throws_ok(
  $$select public.get_customer_request_v1('d9200000-0000-4000-8000-000000000001')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'admin is denied by default'
);
select throws_ok(
  $$select * from public.resolve_customer_request_authorization_v1('d9200000-0000-4000-8000-000000000001','INVALID')$$,
  '22023', 'INVALID_CUSTOMER_REQUEST_ACTION', 'resolver accepts only the fixed action family'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000008', true);
select throws_ok(
  $$select public.get_customer_request_v1('d9200000-0000-4000-8000-000000000001')$$,
  '42501', 'OPERATOR_DISABLED', 'DISABLED operator is denied before request authority'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000009', true);
select throws_ok(
  $$select public.get_customer_request_v1('d9200000-0000-4000-8000-000000000001')$$,
  '42501', 'OPERATOR_REVOKED', 'REVOKED operator is denied before request authority'
);

select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.transition_customer_request_v1('d9200000-0000-4000-8000-000000000001','TRIAGE',0,'d9500000-0000-4000-8000-000000000001','{}'::jsonb)$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'operator cannot TRIAGE'
);
select ok(
  (select status = 'NEW' and revision = 0 from public.customer_requests where request_id = 'd9200000-0000-4000-8000-000000000001')
  and not exists (select 1 from public.customer_request_events where request_id = 'd9200000-0000-4000-8000-000000000001'),
  'authorization denial happens before core mutation'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select public.transition_customer_request_v1('d9200000-0000-4000-8000-000000000001','TRIAGE',0,'d9500000-0000-4000-8000-000000000011','{}'::jsonb)$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'reviewer never receives TRIAGE authority'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000006', true);
select throws_ok(
  $$select public.transition_customer_request_v1('d9200000-0000-4000-8000-000000000001','TRIAGE',0,'d9500000-0000-4000-8000-000000000012','{}'::jsonb)$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'read-only never receives TRIAGE authority'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000007', true);
select throws_ok(
  $$select public.transition_customer_request_v1('d9200000-0000-4000-8000-000000000001','TRIAGE',0,'d9500000-0000-4000-8000-000000000013','{}'::jsonb)$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'admin never receives TRIAGE authority'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000001', true);
select is(
  public.transition_customer_request_v1(
    'd9200000-0000-4000-8000-000000000001', 'TRIAGE', 0,
    'd9500000-0000-4000-8000-000000000002', '{"priority":"URGENT"}'::jsonb
  )->>'status',
  'TRIAGED', 'owner can TRIAGE'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000002', true);
select is(
  public.transition_customer_request_v1(
    'd9200000-0000-4000-8000-000000000006', 'TRIAGE', 0,
    'd9500000-0000-4000-8000-000000000003', '{}'::jsonb
  )->>'status',
  'TRIAGED', 'Operations Manager can TRIAGE'
);

select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.transition_customer_request_v1('d9200000-0000-4000-8000-000000000002','START',0,'d9500000-0000-4000-8000-000000000014','{}'::jsonb)$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'unassigned operator has no WORK authority'
);
select is(
  public.transition_customer_request_v1(
    'd9200000-0000-4000-8000-000000000003', 'START', 0,
    'd9500000-0000-4000-8000-000000000004', '{}'::jsonb
  )->>'status',
  'IN_PROGRESS', 'assigned ACTIVE operator can execute a work transition'
);
select throws_ok(
  $$select public.transition_customer_request_v1('d9200000-0000-4000-8000-000000000003','REQUIRE_CUSTOMER_RESPONSE',0,'d9500000-0000-4000-8000-000000000005','{}'::jsonb)$$,
  '40001', 'CONCURRENT_MODIFICATION', 'work boundary preserves stale expected_revision failure'
);
select throws_ok(
  $$select public.transition_customer_request_v1('d9200000-0000-4000-8000-000000000003','RESOLVE',1,'d9500000-0000-4000-8000-000000000006','{"resolution_summary":"Operator bypass"}'::jsonb)$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'operator cannot execute terminal transition'
);

select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$select * from public.resolve_customer_request_authorization_v1('d9200000-0000-4000-8000-000000000002','WORK')$$,
  'owner has global WORK authority'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$select * from public.resolve_customer_request_authorization_v1('d9200000-0000-4000-8000-000000000002','WORK')$$,
  'Operations Manager has global WORK authority'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select * from public.resolve_customer_request_authorization_v1('d9200000-0000-4000-8000-000000000001','WORK')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'reviewer never receives WORK authority'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000006', true);
select throws_ok(
  $$select * from public.resolve_customer_request_authorization_v1('d9200000-0000-4000-8000-000000000001','WORK')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'read-only never receives WORK authority'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000007', true);
select throws_ok(
  $$select * from public.resolve_customer_request_authorization_v1('d9200000-0000-4000-8000-000000000001','WORK')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'admin never receives WORK authority'
);

select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000001', true);
select is(
  public.transition_customer_request_v1(
    'd9200000-0000-4000-8000-000000000004', 'CANCEL', 0,
    'd9500000-0000-4000-8000-000000000007', '{}'::jsonb
  )->>'status',
  'CANCELLED', 'owner can execute a terminal transition'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000002', true);
select is(
  public.transition_customer_request_v1(
    'd9200000-0000-4000-8000-000000000005', 'CANCEL', 0,
    'd9500000-0000-4000-8000-000000000008', '{}'::jsonb
  )->>'status',
  'CANCELLED', 'Operations Manager can execute a terminal transition'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select * from public.resolve_customer_request_authorization_v1('d9200000-0000-4000-8000-000000000001','TRANSITION')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'reviewer never receives management transition authority'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000006', true);
select throws_ok(
  $$select * from public.resolve_customer_request_authorization_v1('d9200000-0000-4000-8000-000000000001','TRANSITION')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'read-only never receives management transition authority'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000007', true);
select throws_ok(
  $$select * from public.resolve_customer_request_authorization_v1('d9200000-0000-4000-8000-000000000001','TRANSITION')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'admin never receives management transition authority'
);

set local session_replication_role = replica;
update lws_internal.operator_dossier_assignments
set assignee_operator_id = 'd9010000-0000-4000-8000-000000000004',
    assigned_at = statement_timestamp(),
    updated_at = statement_timestamp(),
    revision = revision + 1
where quote_request_id = 'd9100001-0000-4000-8000-000000000001';
set local session_replication_role = origin;

select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.get_customer_request_v1('d9200000-0000-4000-8000-000000000001')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'former operator loses authority immediately after reassignment'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000004', true);
select lives_ok(
  $$select public.get_customer_request_v1('d9200000-0000-4000-8000-000000000001')$$,
  'new ACTIVE assigned operator gains authority immediately after reassignment'
);

select * from finish();
rollback;