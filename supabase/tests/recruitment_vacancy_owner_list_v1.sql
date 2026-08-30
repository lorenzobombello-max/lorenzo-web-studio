begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public', 'list_owner_recruitment_vacancies_v1', array[]::text[],
  'owner vacancy list RPC exists'
);
select ok(
  has_function_privilege('authenticated', 'public.list_owner_recruitment_vacancies_v1()', 'execute')
  and not has_function_privilege('anon', 'public.list_owner_recruitment_vacancies_v1()', 'execute')
  and not has_function_privilege('service_role', 'public.list_owner_recruitment_vacancies_v1()', 'execute'),
  'only authenticated callers receive owner-list execute authority'
);

insert into auth.users(id, email) values
  ('fc000000-0000-4000-8000-000000000001', 'vacancy-list-owner@example.test'),
  ('fc000000-0000-4000-8000-000000000002', 'vacancy-list-admin@example.test'),
  ('fc000000-0000-4000-8000-000000000003', 'vacancy-list-manager@example.test'),
  ('fc000000-0000-4000-8000-000000000004', 'vacancy-list-operator@example.test'),
  ('fc000000-0000-4000-8000-000000000005', 'vacancy-list-disabled@example.test'),
  ('fc000000-0000-4000-8000-000000000006', 'vacancy-list-unassigned@example.test');

insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('fc100000-0000-4000-8000-000000000001', 'fc000000-0000-4000-8000-000000000001', 'Vacancy List Owner', 'owner', 'ACTIVE'),
  ('fc100000-0000-4000-8000-000000000002', 'fc000000-0000-4000-8000-000000000002', 'Vacancy List Admin', 'admin', 'ACTIVE'),
  ('fc100000-0000-4000-8000-000000000003', 'fc000000-0000-4000-8000-000000000003', 'Vacancy List Manager', 'operations_manager', 'ACTIVE'),
  ('fc100000-0000-4000-8000-000000000004', 'fc000000-0000-4000-8000-000000000004', 'Vacancy List Operator', 'operator', 'ACTIVE'),
  ('fc100000-0000-4000-8000-000000000005', 'fc000000-0000-4000-8000-000000000005', 'Vacancy List Disabled Owner', 'owner', 'DISABLED');

insert into public.recruitment_vacancies(
  id, title, slug, department, location, employment_type,
  summary, description, requirements, status, published_at, closed_at
) values
  ('fc200000-0000-4000-8000-000000000001', 'Draft role', 'draft-role', 'Design', 'Antwerpen', 'Full-time', 'Draft summary', 'Draft description', 'Draft requirements', 'DRAFT', null, null),
  ('fc200000-0000-4000-8000-000000000002', 'Published role', 'published-role', 'Operations', 'Gent', 'Part-time', 'Published summary', 'Published description', 'Published requirements', 'PUBLISHED', '2026-08-29T10:00:00Z', null),
  ('fc200000-0000-4000-8000-000000000003', 'Closed role', 'closed-role', 'Support', 'Remote', 'Full-time', 'Closed summary', 'Closed description', 'Closed requirements', 'CLOSED', '2026-08-20T10:00:00Z', '2026-08-28T10:00:00Z');

set local role anon;
select throws_ok(
  $$select public.list_owner_recruitment_vacancies_v1()$$,
  '42501', 'permission denied for function list_owner_recruitment_vacancies_v1',
  'anonymous callers cannot execute the owner list'
);
reset role;

select set_config('request.jwt.claim.sub', 'fc000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select is(
  jsonb_array_length(public.list_owner_recruitment_vacancies_v1()),
  3,
  'active owner receives all vacancy lifecycle states'
);
select is(
  (select array_agg(value->>'status' order by value->>'status') from jsonb_array_elements(public.list_owner_recruitment_vacancies_v1()) as value),
  array['CLOSED', 'DRAFT', 'PUBLISHED'],
  'owner list includes draft published and closed vacancies'
);
select is(
  (select array_agg(key order by key) from jsonb_object_keys(public.list_owner_recruitment_vacancies_v1()->0) as key),
  array['closed_at', 'created_at', 'department', 'description', 'employment_type', 'id', 'location', 'published_at', 'requirements', 'slug', 'status', 'summary', 'title', 'updated_at'],
  'owner projection exposes exactly the vacancy management fields'
);
select ok(
  not (public.list_owner_recruitment_vacancies_v1()::text ~* 'operator|auth_user|email|applicant|candidate'),
  'owner projection contains no operator auth or applicant metadata'
);
reset role;

select set_config('request.jwt.claim.sub', 'fc000000-0000-4000-8000-000000000002', true);
set local role authenticated;
select throws_ok($$select public.list_owner_recruitment_vacancies_v1()$$, '42501', 'RECRUITMENT_OWNER_REQUIRED', 'admin list is denied');
reset role;

select set_config('request.jwt.claim.sub', 'fc000000-0000-4000-8000-000000000003', true);
set local role authenticated;
select throws_ok($$select public.list_owner_recruitment_vacancies_v1()$$, '42501', 'RECRUITMENT_OWNER_REQUIRED', 'operations manager list is denied');
reset role;

select set_config('request.jwt.claim.sub', 'fc000000-0000-4000-8000-000000000004', true);
set local role authenticated;
select throws_ok($$select public.list_owner_recruitment_vacancies_v1()$$, '42501', 'RECRUITMENT_OWNER_REQUIRED', 'operator list is denied');
reset role;

select set_config('request.jwt.claim.sub', 'fc000000-0000-4000-8000-000000000005', true);
set local role authenticated;
select throws_ok($$select public.list_owner_recruitment_vacancies_v1()$$, '42501', 'RECRUITMENT_OWNER_REQUIRED', 'disabled owner list is denied');
reset role;

select set_config('request.jwt.claim.sub', 'fc000000-0000-4000-8000-000000000006', true);
set local role authenticated;
select throws_ok($$select public.list_owner_recruitment_vacancies_v1()$$, '42501', 'RECRUITMENT_OWNER_REQUIRED', 'unassigned authenticated user list is denied');
reset role;

select * from finish();
rollback;