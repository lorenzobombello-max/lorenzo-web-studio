begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public', 'list_operator_message_recipients_v1', array[]::text[],
  'Operator-owned PERSONAL recipient roster authority exists'
);
select ok(
  to_regprocedure('public.list_operator_message_recipients_v1(uuid)') is null,
  'roster accepts no client-supplied operator identity'
);
select ok(
  has_function_privilege('authenticated', 'public.list_operator_message_recipients_v1()', 'execute')
  and not has_function_privilege('anon', 'public.list_operator_message_recipients_v1()', 'execute'),
  'only authenticated callers can enter the roster authority'
);

insert into auth.users(id, email) values
  ('f2100000-0000-4000-8000-000000000001', 'roster-owner@example.test'),
  ('f2100000-0000-4000-8000-000000000002', 'roster-alpha@example.test'),
  ('f2100000-0000-4000-8000-000000000003', 'roster-zulu@example.test'),
  ('f2100000-0000-4000-8000-000000000004', 'roster-disabled@example.test'),
  ('f2100000-0000-4000-8000-000000000005', 'roster-nonoperator@example.test'),
  ('f2100000-0000-4000-8000-000000000006', 'roster-nonowner@example.test'),
  ('f2100000-0000-4000-8000-000000000007', 'roster-disabled-owner@example.test');

insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('f2110000-0000-4000-8000-000000000001', 'f2100000-0000-4000-8000-000000000001', 'Test Owner', 'owner', 'ACTIVE'),
  ('f2110000-0000-4000-8000-000000000002', 'f2100000-0000-4000-8000-000000000002', 'Alpha Test Operator', 'operator', 'ACTIVE'),
  ('f2110000-0000-4000-8000-000000000003', 'f2100000-0000-4000-8000-000000000003', 'Zulu Test Operator', 'reviewer', 'ACTIVE'),
  ('f2110000-0000-4000-8000-000000000004', 'f2100000-0000-4000-8000-000000000004', 'Disabled Test Operator', 'operator', 'DISABLED'),
  ('f2110000-0000-4000-8000-000000000006', 'f2100000-0000-4000-8000-000000000006', 'Management Test Operator', 'operations_manager', 'ACTIVE'),
  ('f2110000-0000-4000-8000-000000000007', 'f2100000-0000-4000-8000-000000000007', 'Disabled Test Owner', 'owner', 'DISABLED');

select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.list_operator_message_recipients_v1()$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'unauthenticated caller cannot enumerate operators'
);

select set_config('request.jwt.claim.sub', 'f2100000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select public.list_operator_message_recipients_v1()$$,
  '42501', 'UNKNOWN_OPERATOR', 'authenticated non-Operator cannot enumerate operators'
);

select set_config('request.jwt.claim.sub', 'f2100000-0000-4000-8000-000000000006', true);
select throws_ok(
  $$select public.list_operator_message_recipients_v1()$$,
  '42501', 'OWNER_MESSAGE_SENDER_REQUIRED', 'active non-owner cannot enumerate the owner-only composer roster'
);

select set_config('request.jwt.claim.sub', 'f2100000-0000-4000-8000-000000000007', true);
select throws_ok(
  $$select public.list_operator_message_recipients_v1()$$,
  '42501', 'OPERATOR_NOT_ACTIVE', 'disabled owner cannot enumerate operators'
);

select set_config('request.jwt.claim.sub', 'f2100000-0000-4000-8000-000000000001', true);
create temporary table roster_fixture(payload jsonb);
insert into roster_fixture values(public.list_operator_message_recipients_v1());

select is(
  jsonb_array_length((select payload from roster_fixture)),
  (select count(*)::integer from public.commercial_operators where status = 'ACTIVE' and operator_id <> 'f2110000-0000-4000-8000-000000000001'),
  'authorized owner receives every other active Operator'
);
select ok(
  not (select payload from roster_fixture) @> '[{"operator_id":"f2110000-0000-4000-8000-000000000001"}]'::jsonb,
  'current sender is excluded server-side'
);
select ok(
  (select payload from roster_fixture) @> '[{"operator_id":"f2110000-0000-4000-8000-000000000002","display_name":"Alpha Test Operator"}]'::jsonb,
  'active eligible Operator appears in roster'
);
select ok(
  not (select payload from roster_fixture) @> '[{"operator_id":"f2110000-0000-4000-8000-000000000004"}]'::jsonb,
  'disabled Operator is excluded'
);
select ok(
  not (select payload from roster_fixture) @> '[{"operator_id":"f2100000-0000-4000-8000-000000000005"}]'::jsonb,
  'non-Operator auth user is excluded'
);
select is(
  (select count(*)::integer
   from roster_fixture, jsonb_array_elements(payload) as recipient
   where (select array_agg(key order by key) from jsonb_object_keys(recipient) as key)
     = array['display_name','operator_id']),
  jsonb_array_length((select payload from roster_fixture)),
  'every roster item exposes only operator_id and display_name'
);
select is((select payload->0->>'display_name' from roster_fixture), 'Alpha Test Operator', 'roster ordering starts deterministically by display name');
select is(
  (select array_agg(recipient->>'display_name' order by position)
   from roster_fixture, jsonb_array_elements(payload) with ordinality as listed(recipient, position)),
  (select array_agg(display_name order by lower(display_name), operator_id)
   from public.commercial_operators
   where status = 'ACTIVE' and operator_id <> 'f2110000-0000-4000-8000-000000000001'),
  'roster ordering is deterministic across all eligible Operators'
);
select ok(
  pg_get_functiondef('public.list_operator_message_recipients_v1()'::regprocedure) !~* '(online|heartbeat|last_seen|presence)',
  'offline eligibility has no online or presence dependency'
);

select * from finish();
rollback;