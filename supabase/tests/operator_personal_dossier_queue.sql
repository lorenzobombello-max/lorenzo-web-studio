begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public', 'get_operator_personal_dossier_queue_v1', array['text', 'integer'],
  'personal dossier queue RPC exists'
);
select ok(
  exists (
    select 1 from pg_proc
    where oid = 'public.get_operator_personal_dossier_queue_v1(text,integer)'::regprocedure
      and prosecdef
      and provolatile = 's'
      and proconfig = array['search_path=public, lws_internal, auth, pg_catalog']
  ),
  'personal queue is stable SECURITY DEFINER with a fixed search_path'
);
select is(
  pg_get_function_arguments('public.get_operator_personal_dossier_queue_v1(text,integer)'::regprocedure),
  'p_cursor text DEFAULT NULL::text, p_limit integer DEFAULT 25',
  'cursor and limit have the bounded v1 defaults'
);
select ok(
  has_function_privilege('authenticated', 'public.get_operator_personal_dossier_queue_v1(text,integer)', 'execute')
  and not has_function_privilege('anon', 'public.get_operator_personal_dossier_queue_v1(text,integer)', 'execute')
  and not has_function_privilege('service_role', 'public.get_operator_personal_dossier_queue_v1(text,integer)', 'execute')
  and not has_function_privilege('public', 'public.get_operator_personal_dossier_queue_v1(text,integer)', 'execute'),
  'only authenticated receives execute privilege'
);
select is(
  (select count(*)::integer
   from information_schema.parameters
   where specific_schema = 'public'
     and specific_name like 'get_operator_personal_dossier_queue_v1_%'
     and parameter_name in ('operator_id', 'assignee_operator_id', 'auth_user_id', 'role', 'status')),
  0,
  'RPC exposes no caller-supplied identity or authority parameter'
);
select ok(
  (select prosrc !~* '\m(insert|update|delete|merge|truncate|upsert)\M'
   from pg_proc where oid = 'public.get_operator_personal_dossier_queue_v1(text,integer)'::regprocedure),
  'personal queue runtime is read-only'
);
select ok(
  (select prosrc !~* 'operator_dossier_assignment_events|operator_dossier_assignment_commands|commercial_operator_project_grants|get_operations_manager_business_queue'
   from pg_proc where oid = 'public.get_operator_personal_dossier_queue_v1(text,integer)'::regprocedure),
  'history, command, project-grant, and manager-queue authority are absent'
);
select ok(
  (select strpos(prosrc, 'where auth_user_id = v_subject') < strpos(prosrc, 'where assignment.assignee_operator_id = v_operator_id')
   from pg_proc where oid = 'public.get_operator_personal_dossier_queue_v1(text,integer)'::regprocedure),
  'auth.uid identity resolution precedes own-assignment filtering'
);

insert into auth.users(id, email) values
  ('c1000000-0000-4000-8000-000000000001', 'personal-owner@example.test'),
  ('c1000000-0000-4000-8000-000000000002', 'personal-manager@example.test'),
  ('c1000000-0000-4000-8000-000000000003', 'personal-operator-a@example.test'),
  ('c1000000-0000-4000-8000-000000000004', 'personal-operator-b@example.test'),
  ('c1000000-0000-4000-8000-000000000005', 'personal-disabled@example.test'),
  ('c1000000-0000-4000-8000-000000000006', 'personal-revoked@example.test'),
  ('c1000000-0000-4000-8000-000000000007', 'personal-unknown@example.test'),
  ('c1000000-0000-4000-8000-000000000008', 'personal-reviewer@example.test');

insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status, revoked_at
) values
  ('c1010000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000001', 'Personal Owner', 'owner', 'ACTIVE', null),
  ('c1010000-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000002', 'Personal Manager', 'operations_manager', 'ACTIVE', null),
  ('c1010000-0000-4000-8000-000000000003', 'c1000000-0000-4000-8000-000000000003', 'Personal Operator A', 'operator', 'ACTIVE', null),
  ('c1010000-0000-4000-8000-000000000004', 'c1000000-0000-4000-8000-000000000004', 'Personal Operator B', 'operator', 'ACTIVE', null),
  ('c1010000-0000-4000-8000-000000000005', 'c1000000-0000-4000-8000-000000000005', 'Personal Disabled', 'operator', 'DISABLED', null),
  ('c1010000-0000-4000-8000-000000000006', 'c1000000-0000-4000-8000-000000000006', 'Personal Revoked', 'operator', 'REVOKED', statement_timestamp()),
  ('c1010000-0000-4000-8000-000000000008', 'c1000000-0000-4000-8000-000000000008', 'Personal Reviewer', 'reviewer', 'ACTIVE', null);

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind, sdf_package,
  created_at, name, email, description, privacy_consent, status
)
select
  ('c2' || lpad(series::text, 6, '0') || '-0000-4000-8000-' || lpad(series::text, 12, '0'))::uuid,
  'LWS-AAN-2099-' || lpad((7000 + series)::text, 4, '0'),
  'production', 'slimme_documentenflow', 'start',
  '2099-01-01T00:00:00Z'::timestamptz + make_interval(mins => series),
  'Personal fixture ' || series, 'personal-' || series || '@example.test',
  'Personal queue fixture.', true, 'approved'
from generate_series(1, 30) as series;

select set_config('lws.operator_dossier_assignment_command', 'on', true);
update lws_internal.operator_dossier_assignments
set assignee_operator_id = case
      when quote_request_id = 'c2000030-0000-4000-8000-000000000030' then 'c1010000-0000-4000-8000-000000000004'::uuid
      else 'c1010000-0000-4000-8000-000000000003'::uuid
    end,
    revision = revision + 1,
    assigned_at = '2099-02-01T00:00:00Z'::timestamptz + make_interval(mins => case when quote_request_id in ('c2000027-0000-4000-8000-000000000027','c2000028-0000-4000-8000-000000000028') then 28 else substring(quote_request_id::text, 3, 6)::integer end),
    updated_at = '2099-02-01T00:00:00Z'::timestamptz + make_interval(mins => case when quote_request_id in ('c2000027-0000-4000-8000-000000000027','c2000028-0000-4000-8000-000000000028') then 28 else substring(quote_request_id::text, 3, 6)::integer end)
where quote_request_id::text like 'c2%'
  and quote_request_id <> 'c2000029-0000-4000-8000-000000000029';
select set_config('lws.operator_dossier_assignment_command', '', true);

select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.get_operator_personal_dossier_queue_v1()$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'unauthenticated caller is denied'
);
select set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000007', true);
select throws_ok(
  $$select public.get_operator_personal_dossier_queue_v1()$$,
  '42501', 'UNKNOWN_OPERATOR', 'unknown human is denied'
);
select set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$select public.get_operator_personal_dossier_queue_v1()$$,
  '42501', 'OPERATOR_PERSONAL_QUEUE_READER_REQUIRED', 'owner is denied'
);
select set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.get_operator_personal_dossier_queue_v1()$$,
  '42501', 'OPERATOR_PERSONAL_QUEUE_READER_REQUIRED', 'Operations Manager is denied'
);
select set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000008', true);
select throws_ok(
  $$select public.get_operator_personal_dossier_queue_v1()$$,
  '42501', 'OPERATOR_PERSONAL_QUEUE_READER_REQUIRED', 'other active role is denied'
);
select set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select public.get_operator_personal_dossier_queue_v1()$$,
  '42501', 'OPERATOR_DISABLED', 'DISABLED operator is denied'
);
select set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000006', true);
select throws_ok(
  $$select public.get_operator_personal_dossier_queue_v1()$$,
  '42501', 'OPERATOR_REVOKED', 'REVOKED operator is denied'
);

select set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000003', true);
create temporary table personal_a as
select public.get_operator_personal_dossier_queue_v1() as value;

select is(jsonb_array_length(value->'items'), 25, 'omitted limit returns the default 25 rows') from personal_a;
select is((value->>'has_more')::boolean, true, 'default page reports remaining own rows') from personal_a;
select is(
  (select array_agg(key order by key) from jsonb_object_keys(value) as key),
  array['has_more','items','next_cursor']::text[],
  'top-level response has only pagination fields'
) from personal_a;
select ok(
  not exists (
    select 1 from personal_a, jsonb_array_elements(value->'items') as item
    where (select array_agg(key order by key) from jsonb_object_keys(item) as key)
       <> array['assigned_at','assignment_revision','reference','source','status','zone']::text[]
  ),
  'items expose exactly the safe personal queue projection'
);
select ok(
  not exists (
    select 1 from personal_a, jsonb_array_elements(value->'items') as item
    where item ?| array['quote_request_id','operator_id','assignee_operator_id','auth_user_id','name','organization','email','history','events','commands']
  ),
  'items expose no identity, customer, or assignment-history fields'
);
select ok(
  not exists (
    select 1 from personal_a, jsonb_array_elements(value->'items') as item
    where item->>'reference' in ('LWS-AAN-2099-7029', 'LWS-AAN-2099-7030')
  ),
  'operator A sees neither unassigned nor operator B dossiers'
);
select is((value->'items'->0)->>'reference', 'LWS-AAN-2099-7028', 'newest assignment is first') from personal_a;
select is((value->'items'->1)->>'reference', 'LWS-AAN-2099-7027', 'equal assigned_at uses quote_request_id DESC') from personal_a;

select lives_ok($$select public.get_operator_personal_dossier_queue_v1(null, 1)$$, 'limit 1 is accepted');
select lives_ok($$select public.get_operator_personal_dossier_queue_v1(null, 100)$$, 'maximum limit 100 is accepted');
select throws_ok($$select public.get_operator_personal_dossier_queue_v1(null, 0)$$, '22023', 'INVALID_OPERATOR_PERSONAL_QUEUE_LIMIT', 'zero limit fails closed');
select throws_ok($$select public.get_operator_personal_dossier_queue_v1(null, -1)$$, '22023', 'INVALID_OPERATOR_PERSONAL_QUEUE_LIMIT', 'negative limit fails closed');
select throws_ok($$select public.get_operator_personal_dossier_queue_v1(null, 101)$$, '22023', 'INVALID_OPERATOR_PERSONAL_QUEUE_LIMIT', 'limit above 100 fails closed');
select throws_ok($$select public.get_operator_personal_dossier_queue_v1(null, null)$$, '22023', 'INVALID_OPERATOR_PERSONAL_QUEUE_LIMIT', 'explicit null limit fails closed');
select throws_ok($$select public.get_operator_personal_dossier_queue_v1('not-a-cursor', 1)$$, '22023', 'INVALID_OPERATOR_PERSONAL_QUEUE_CURSOR', 'malformed cursor fails closed');

create temporary table personal_page_one as
select public.get_operator_personal_dossier_queue_v1(null, 1) as value;
create temporary table personal_page_two as
select public.get_operator_personal_dossier_queue_v1(
  (select value->>'next_cursor' from personal_page_one), 1
) as value;
select is((select (value->'items'->0)->>'reference' from personal_page_one), 'LWS-AAN-2099-7028', 'first page returns the first keyset row');
select is((select (value->'items'->0)->>'reference' from personal_page_two), 'LWS-AAN-2099-7027', 'second page advances without omission');
select isnt(
  (select (value->'items'->0)->>'reference' from personal_page_one),
  (select (value->'items'->0)->>'reference' from personal_page_two),
  'adjacent pages contain no duplicate'
);
select is(
  (select array_agg(key order by key)
   from personal_page_one,
   jsonb_object_keys(convert_from(decode(value->>'next_cursor', 'hex'), 'UTF8')::jsonb) as key),
  array['assigned_at','quote_request_id']::text[],
  'cursor contains only the stable keyset position'
);

select set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000004', true);
select is(
  (public.get_operator_personal_dossier_queue_v1()->'items'->0)->>'reference',
  'LWS-AAN-2099-7030',
  'operator B sees its own assignment'
);
select is(
  jsonb_array_length(public.get_operator_personal_dossier_queue_v1(
    (select value->>'next_cursor' from personal_page_one), 25
  )->'items'),
  0,
  'operator A cursor cannot reveal operator A rows to operator B'
);

select set_config('lws.operator_dossier_assignment_command', 'on', true);
update lws_internal.operator_dossier_assignments
set assignee_operator_id = 'c1010000-0000-4000-8000-000000000004',
    revision = revision + 1,
    assigned_at = '2099-03-01T00:00:00Z',
    updated_at = '2099-03-01T00:00:00Z'
where quote_request_id = 'c2000028-0000-4000-8000-000000000028';
select set_config('lws.operator_dossier_assignment_command', '', true);

select is(
  (public.get_operator_personal_dossier_queue_v1()->'items'->0)->>'reference',
  'LWS-AAN-2099-7028',
  'reassignment appears in the new operator current queue'
);
select set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000003', true);
select ok(
  not exists (
    select 1 from jsonb_array_elements(public.get_operator_personal_dossier_queue_v1(null, 100)->'items') as item
    where item->>'reference' = 'LWS-AAN-2099-7028'
  ),
  'reassignment removes the dossier from the previous operator current queue'
);

update lws_internal.operator_dossier_states
set state = 'TRASHED',
    revision = revision + 1,
    state_before_trash = 'ACTIVE',
    deletion_eligible_at = null,
    updated_at = clock_timestamp() + interval '1 second'
where quote_request_id = 'c2000027-0000-4000-8000-000000000027';

select is(
  (select zone from lws_internal.operator_application_readmodel_v2 where quote_request_id = 'c2000027-0000-4000-8000-000000000027'),
  'TRASHED',
  'trashed assignment remains visible to the explicit trash readmodel'
);
select ok(
  not exists (
    select 1 from jsonb_array_elements(public.get_operator_personal_dossier_queue_v1(null, 100)->'items') as item
    where item->>'reference' = 'LWS-AAN-2099-7027'
  ),
  'trashed assignment stays out of the personal current queue after refresh'
);
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000003', true);
select ok(
  not exists (
    select 1 from jsonb_array_elements(public.get_operator_personal_dossier_queue_v1(null, 100)->'items') as item
    where item->>'reference' = 'LWS-AAN-2099-7027'
  ),
  'trashed assignment stays out of a fresh authenticated operator session'
);

select * from finish();
rollback;