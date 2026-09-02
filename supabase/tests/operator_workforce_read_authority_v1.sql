begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function('public', 'list_operator_workforce_v1', array[]::text[], 'narrow caller-authorized Personnel list exists');
select ok(
  has_function_privilege('authenticated', 'public.list_operator_workforce_v1()', 'execute')
  and not has_function_privilege('anon', 'public.list_operator_workforce_v1()', 'execute'),
  'only authenticated humans can invoke the Personnel list'
);
select ok(
  not has_table_privilege('authenticated', 'public.workforce_employees', 'select,insert,update,delete'),
  'Personnel list grants no direct workforce table authority'
);

insert into auth.users(id, email) values
  ('f7000000-0000-4000-8000-000000000001', 'workforce-owner@example.test'),
  ('f7000000-0000-4000-8000-000000000002', 'workforce-admin@example.test'),
  ('f7000000-0000-4000-8000-000000000003', 'workforce-manager@example.test'),
  ('f7000000-0000-4000-8000-000000000004', 'workforce-operator@example.test'),
  ('f7000000-0000-4000-8000-000000000005', 'workforce-disabled@example.test');

insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('f7010000-0000-4000-8000-000000000001', 'f7000000-0000-4000-8000-000000000001', 'Workforce Owner', 'owner', 'ACTIVE'),
  ('f7010000-0000-4000-8000-000000000002', 'f7000000-0000-4000-8000-000000000002', 'Workforce Admin', 'admin', 'ACTIVE'),
  ('f7010000-0000-4000-8000-000000000003', 'f7000000-0000-4000-8000-000000000003', 'Workforce Manager', 'operations_manager', 'ACTIVE'),
  ('f7010000-0000-4000-8000-000000000004', 'f7000000-0000-4000-8000-000000000004', 'Workforce Operator', 'operator', 'ACTIVE'),
  ('f7010000-0000-4000-8000-000000000005', 'f7000000-0000-4000-8000-000000000005', 'Workforce Disabled', 'owner', 'DISABLED');

insert into public.workforce_employees(id, display_name, role_title, team_name, employment_status, start_date, commercial_operator_id) values
  ('f7020000-0000-4000-8000-000000000001', 'Alex Personeel', 'Projectcoordinator', 'Operations', 'ACTIVE', '2026-01-15', null),
  ('f7020000-0000-4000-8000-000000000002', 'Zoë Personeel', null, null, 'INACTIVE', '2025-06-01', 'f7010000-0000-4000-8000-000000000003');

select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.list_operator_workforce_v1()$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'unauthenticated Personnel read is denied'
);

select set_config('request.jwt.claim.sub', 'f7000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select public.list_operator_workforce_v1()$$,
  '42501', 'OPERATOR_NOT_ACTIVE', 'DISABLED Operator cannot read Personnel'
);

select set_config('request.jwt.claim.sub', 'f7000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$select public.list_operator_workforce_v1()$$,
  '42501', 'WORKFORCE_MANAGEMENT_READER_REQUIRED', 'ordinary Operator cannot read Personnel'
);

select set_config('request.jwt.claim.sub', 'f7000000-0000-4000-8000-000000000001', true);
select is(jsonb_array_length(public.list_operator_workforce_v1()->'employees'), 2, 'owner reads the Personnel list');
select is(
  (public.list_operator_workforce_v1()->'employees'->0->>'display_name'),
  'Alex Personeel',
  'Personnel list is deterministically ordered'
);
select is(
  (select array_agg(key order by key) from jsonb_object_keys(public.list_operator_workforce_v1()->'employees'->0) key),
  array['display_name','employee_id','employment_status','role_title','start_date','team_name'],
  'Personnel exposes only the approved minimum fields'
);
select ok(
  not (public.list_operator_workforce_v1()::text like '%Workforce Owner%'),
  'Operator access identities do not implicitly become Personnel records'
);

select set_config('request.jwt.claim.sub', 'f7000000-0000-4000-8000-000000000002', true);
select is(jsonb_array_length(public.list_operator_workforce_v1()->'employees'), 2, 'admin reads the Personnel list');

select set_config('request.jwt.claim.sub', 'f7000000-0000-4000-8000-000000000003', true);
select is(jsonb_array_length(public.list_operator_workforce_v1()->'employees'), 2, 'operations manager reads the Personnel list');

select * from finish();
rollback;