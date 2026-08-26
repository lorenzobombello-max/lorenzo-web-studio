begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public', 'get_customer_requests_for_dossier_v1', array['text', 'text', 'integer'],
  'dossier-scoped Customer Requests list RPC exists'
);
select ok(
  exists (
    select 1 from pg_proc
    where oid = 'public.get_customer_requests_for_dossier_v1(text,text,integer)'::regprocedure
      and prosecdef
      and provolatile = 's'
      and proconfig = array['search_path=public, lws_internal, auth, pg_catalog']
  ),
  'list RPC is stable SECURITY DEFINER with a fixed search_path'
);
select is(
  pg_get_function_arguments('public.get_customer_requests_for_dossier_v1(text,text,integer)'::regprocedure),
  'p_dossier_reference text, p_cursor text DEFAULT NULL::text, p_limit integer DEFAULT 25',
  'list RPC accepts only dossier reference and bounded pagination'
);
select ok(
  has_function_privilege('authenticated', 'public.get_customer_requests_for_dossier_v1(text,text,integer)', 'execute')
  and not has_function_privilege('anon', 'public.get_customer_requests_for_dossier_v1(text,text,integer)', 'execute')
  and not has_function_privilege('service_role', 'public.get_customer_requests_for_dossier_v1(text,text,integer)', 'execute')
  and not has_function_privilege('public', 'public.get_customer_requests_for_dossier_v1(text,text,integer)', 'execute'),
  'only authenticated receives list RPC execution authority'
);
select is(
  (select count(*)::integer
   from information_schema.parameters
   where specific_schema = 'public'
     and specific_name like 'get_customer_requests_for_dossier_v1_%'
     and parameter_name in ('operator_id', 'role', 'access_level', 'customer_id', 'project_id', 'quote_request_id')),
  0,
  'list RPC accepts no client-supplied identity or authority'
);
select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'customer_requests'
      and indexname = 'customer_requests_dossier_submitted_idx'
      and indexdef like '%(quote_request_id, submitted_at DESC, request_id DESC)%'
  ),
  'dossier keyset pagination has an additive supporting index'
);

insert into auth.users(id, email) values
  ('e1000000-0000-4000-8000-000000000001', 'request-list-owner@example.test'),
  ('e1000000-0000-4000-8000-000000000002', 'request-list-manager@example.test'),
  ('e1000000-0000-4000-8000-000000000003', 'request-list-operator-a@example.test'),
  ('e1000000-0000-4000-8000-000000000004', 'request-list-operator-b@example.test'),
  ('e1000000-0000-4000-8000-000000000005', 'request-list-reviewer@example.test'),
  ('e1000000-0000-4000-8000-000000000006', 'request-list-read-only@example.test'),
  ('e1000000-0000-4000-8000-000000000007', 'request-list-admin@example.test'),
  ('e1000000-0000-4000-8000-000000000008', 'request-list-disabled@example.test'),
  ('e1000000-0000-4000-8000-000000000009', 'request-list-revoked@example.test'),
  ('e1000000-0000-4000-8000-000000000010', 'request-list-unknown@example.test');

insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status, revoked_at
) values
  ('e1010000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001', 'Request List Owner', 'owner', 'ACTIVE', null),
  ('e1010000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000002', 'Request List Manager', 'operations_manager', 'ACTIVE', null),
  ('e1010000-0000-4000-8000-000000000003', 'e1000000-0000-4000-8000-000000000003', 'Request List Operator A', 'operator', 'ACTIVE', null),
  ('e1010000-0000-4000-8000-000000000004', 'e1000000-0000-4000-8000-000000000004', 'Request List Operator B', 'operator', 'ACTIVE', null),
  ('e1010000-0000-4000-8000-000000000005', 'e1000000-0000-4000-8000-000000000005', 'Request List Reviewer', 'reviewer', 'ACTIVE', null),
  ('e1010000-0000-4000-8000-000000000006', 'e1000000-0000-4000-8000-000000000006', 'Request List Read Only', 'read_only', 'ACTIVE', null),
  ('e1010000-0000-4000-8000-000000000007', 'e1000000-0000-4000-8000-000000000007', 'Request List Admin', 'admin', 'ACTIVE', null),
  ('e1010000-0000-4000-8000-000000000008', 'e1000000-0000-4000-8000-000000000008', 'Request List Disabled', 'operator', 'DISABLED', null),
  ('e1010000-0000-4000-8000-000000000009', 'e1000000-0000-4000-8000-000000000009', 'Request List Revoked', 'operator', 'REVOKED', statement_timestamp());

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind,
  name, email, website_type, budget, timing, description, privacy_consent, status
) values
  ('e1100001-0000-4000-8000-000000000001', 'LWS-AAN-2099-1101', 'production', 'website', 'Request List A', 'list-a@example.test', 'business', 'x', 'x', 'Request list fixture A.', true, 'approved'),
  ('e1100002-0000-4000-8000-000000000002', 'LWS-AAN-2099-1102', 'production', 'website', 'Request List B', 'list-b@example.test', 'business', 'x', 'x', 'Request list fixture B.', true, 'approved'),
  ('e1100003-0000-4000-8000-000000000003', 'LWS-AAN-2099-1103', 'production', 'website', 'Request List C', 'list-c@example.test', 'business', 'x', 'x', 'Request list fixture C.', true, 'approved');

set local session_replication_role = replica;

insert into public.commercial_customers(customer_id, acceptance_id, identity_sha256) values
  ('e1300000-0000-4000-8000-000000000001', 'e1310001-0000-4000-8000-000000000001', repeat('1', 64)),
  ('e1300000-0000-4000-8000-000000000002', 'e1310002-0000-4000-8000-000000000002', repeat('2', 64)),
  ('e1300000-0000-4000-8000-000000000003', 'e1310003-0000-4000-8000-000000000003', repeat('3', 64));

insert into public.commercial_projects(
  project_id, customer_id, quotation_issuance_id, acceptance_id,
  accepted_total_minor, currency, m1_minor, m2_minor, m3_minor, current_state, revision
) values
  ('e1400000-0000-4000-8000-000000000001', 'e1300000-0000-4000-8000-000000000001', 'e1410001-0000-4000-8000-000000000001', 'e1310001-0000-4000-8000-000000000001', 0, 'EUR', 0, 0, 0, 'PROJECT_RELEASED', 0),
  ('e1400000-0000-4000-8000-000000000002', 'e1300000-0000-4000-8000-000000000002', 'e1410002-0000-4000-8000-000000000002', 'e1310002-0000-4000-8000-000000000002', 0, 'EUR', 0, 0, 0, 'PROJECT_RELEASED', 0),
  ('e1400000-0000-4000-8000-000000000003', 'e1300000-0000-4000-8000-000000000003', 'e1410003-0000-4000-8000-000000000003', 'e1310003-0000-4000-8000-000000000003', 0, 'EUR', 0, 0, 0, 'PROJECT_RELEASED', 0);

insert into public.customer_requests(
  request_id, request_reference, quote_request_id, customer_id, project_id,
  source, request_type, title, description, status, priority,
  submitted_at, submitter_type, revision, updated_at
) values
  ('e1200001-0000-4000-8000-000000000001', 'LWS-VRZ-2099-1101', 'e1100001-0000-4000-8000-000000000001', 'e1300000-0000-4000-8000-000000000001', 'e1400000-0000-4000-8000-000000000001', 'OPERATOR', 'OTHER', 'First request', 'First request detail.', 'NEW', 'NORMAL', '2099-03-01T10:00:00Z', 'OPERATOR', 0, '2099-03-01T10:00:00Z'),
  ('e1200001-0000-4000-8000-000000000002', 'LWS-VRZ-2099-1102', 'e1100001-0000-4000-8000-000000000001', 'e1300000-0000-4000-8000-000000000001', 'e1400000-0000-4000-8000-000000000001', 'OPERATOR', 'TECHNICAL_CHANGE', 'Second request', 'Second request detail.', 'TRIAGED', 'HIGH', '2099-03-02T10:00:00Z', 'OPERATOR', 1, '2099-03-02T10:00:00Z'),
  ('e1200002-0000-4000-8000-000000000001', 'LWS-VRZ-2099-1103', 'e1100002-0000-4000-8000-000000000002', 'e1300000-0000-4000-8000-000000000002', 'e1400000-0000-4000-8000-000000000002', 'OPERATOR', 'OTHER', 'Other dossier request', 'Other dossier detail.', 'NEW', 'LOW', '2099-03-03T10:00:00Z', 'OPERATOR', 0, '2099-03-03T10:00:00Z'),
  ('e1200003-0000-4000-8000-000000000001', 'LWS-VRZ-2099-1104', 'e1100003-0000-4000-8000-000000000003', 'e1300000-0000-4000-8000-000000000003', 'e1400000-0000-4000-8000-000000000003', 'OPERATOR', 'OTHER', 'Granted request', 'Granted request detail.', 'NEW', null, '2099-03-04T10:00:00Z', 'OPERATOR', 0, '2099-03-04T10:00:00Z');

update lws_internal.operator_dossier_assignments
set assignee_operator_id = case
      when quote_request_id = 'e1100001-0000-4000-8000-000000000001' then 'e1010000-0000-4000-8000-000000000003'::uuid
      else 'e1010000-0000-4000-8000-000000000004'::uuid
    end,
    assigned_at = statement_timestamp(),
    updated_at = statement_timestamp(),
    revision = revision + 1
where quote_request_id in (
  'e1100001-0000-4000-8000-000000000001',
  'e1100002-0000-4000-8000-000000000002'
);

insert into public.commercial_operator_project_grants(
  operator_id, project_id, access_level, granted_by, revoked_at
) values
  ('e1010000-0000-4000-8000-000000000005', 'e1400000-0000-4000-8000-000000000003', 'reviewer', 'e1010000-0000-4000-8000-000000000001', null),
  ('e1010000-0000-4000-8000-000000000006', 'e1400000-0000-4000-8000-000000000003', 'read_only', 'e1010000-0000-4000-8000-000000000001', null);

set local session_replication_role = origin;

select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1101')$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'list requires auth.uid derived identity'
);
select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000010', true);
select throws_ok(
  $$select public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1101')$$,
  '42501', 'UNKNOWN_OPERATOR', 'unknown operator is denied'
);
select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000008', true);
select throws_ok(
  $$select public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1101')$$,
  '42501', 'OPERATOR_DISABLED', 'DISABLED operator is denied'
);
select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000009', true);
select throws_ok(
  $$select public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1101')$$,
  '42501', 'OPERATOR_REVOKED', 'REVOKED operator is denied'
);

select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000001', true);
select is(
  jsonb_array_length(public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1102')->'items'),
  1, 'owner has global list authority'
);
select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000002', true);
select is(
  jsonb_array_length(public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1102')->'items'),
  1, 'Operations Manager has global list authority'
);

select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000003', true);
create temporary table request_list_a as
select public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1101') as value;
select is(jsonb_array_length(value->'items'), 2, 'assigned ACTIVE operator lists own dossier requests') from request_list_a;
select is(
  (select array_agg(key order by key) from request_list_a, jsonb_object_keys(value) as key),
  array['has_more','items','next_cursor']::text[],
  'top-level response exposes only list pagination fields'
);
select ok(
  not exists (
    select 1 from request_list_a, jsonb_array_elements(value->'items') as item
    where (select array_agg(key order by key) from jsonb_object_keys(item) as key)
       <> array['priority','request_id','request_reference','request_type','revision','status','submitted_at','title','updated_at']::text[]
  ),
  'list items expose the exact operational whitelist'
);
select ok(
  not exists (
    select 1 from request_list_a, jsonb_array_elements(value->'items') as item
    where item ?| array['customer_id','project_id','quote_request_id','linked_change_order_id','price','amount','invoice','quotation','margin']
  ),
  'list exposes no dossier, customer, change-order, commercial, or financial identifiers'
);
select throws_ok(
  $$select public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1102')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'operator is denied for another dossier and customer'
);
select throws_ok(
  $$select public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-9999')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'guessed canonical dossier fails closed'
);
select throws_ok(
  $$select public.get_customer_requests_for_dossier_v1('not-a-dossier')$$,
  '22023', 'INVALID_DOSSIER_REFERENCE', 'invalid dossier reference fails closed'
);
select throws_ok(
  $$select public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1101', 'not-a-cursor', 1)$$,
  '22023', 'INVALID_CUSTOMER_REQUEST_LIST_CURSOR', 'malformed cursor fails closed'
);
select throws_ok(
  $$select public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1101', null, 101)$$,
  '22023', 'INVALID_CUSTOMER_REQUEST_LIST_LIMIT', 'limit above maximum fails closed'
);

create temporary table request_list_page_one as
select public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1101', null, 1) as value;
create temporary table request_list_page_two as
select public.get_customer_requests_for_dossier_v1(
  'LWS-AAN-2099-1101',
  (select value->>'next_cursor' from request_list_page_one),
  1
) as value;
select is((select (value->'items'->0)->>'request_id' from request_list_page_one), 'e1200001-0000-4000-8000-000000000002', 'first page returns newest request');
select is((select (value->'items'->0)->>'request_id' from request_list_page_two), 'e1200001-0000-4000-8000-000000000001', 'second page advances without omission');
select isnt(
  (select (value->'items'->0)->>'request_id' from request_list_page_one),
  (select (value->'items'->0)->>'request_id' from request_list_page_two),
  'adjacent pages contain no duplicate'
);
select is(
  (select array_agg(key order by key)
   from request_list_page_one,
   jsonb_object_keys(convert_from(decode(value->>'next_cursor', 'hex'), 'UTF8')::jsonb) as key),
  array['request_id','submitted_at']::text[],
  'cursor contains only the stable keyset position'
);

select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000005', true);
select is(
  jsonb_array_length(public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1103')->'items'),
  1, 'reviewer VIEW follows an active project grant'
);
select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000006', true);
select is(
  jsonb_array_length(public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1103')->'items'),
  1, 'read-only VIEW follows an active project grant'
);

set local session_replication_role = replica;
update public.commercial_operator_project_grants
set revoked_at = statement_timestamp()
where project_id = 'e1400000-0000-4000-8000-000000000003';
set local session_replication_role = origin;
select throws_ok(
  $$select public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1103')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'revoked read-only grant removes list authority'
);
select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1103')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'revoked reviewer grant removes list authority'
);

select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000007', true);
select throws_ok(
  $$select public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1101')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'admin is denied by default'
);

set local session_replication_role = replica;
update lws_internal.operator_dossier_assignments
set assignee_operator_id = 'e1010000-0000-4000-8000-000000000004',
    assigned_at = statement_timestamp(),
    updated_at = statement_timestamp(),
    revision = revision + 1
where quote_request_id = 'e1100001-0000-4000-8000-000000000001';
set local session_replication_role = origin;

select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1101')$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'former operator loses list authority immediately after reassignment'
);
select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000004', true);
select is(
  jsonb_array_length(public.get_customer_requests_for_dossier_v1('LWS-AAN-2099-1101')->'items'),
  2, 'new assigned ACTIVE operator gains list authority immediately'
);

select ok(
  not has_function_privilege('authenticated', 'lws_internal.resolve_operator_dossier_reference_v1(text)', 'execute')
  and not has_function_privilege('authenticated', 'lws_internal.transition_customer_request_core_v1(uuid,text,bigint,uuid,jsonb)', 'execute')
  and not has_function_privilege('anon', 'lws_internal.resolve_operator_dossier_reference_v1(text)', 'execute')
  and not has_function_privilege('service_role', 'lws_internal.transition_customer_request_core_v1(uuid,text,bigint,uuid,jsonb)', 'execute'),
  'private dossier resolver and Customer Request core remain unexposed'
);

select * from finish();
rollback;