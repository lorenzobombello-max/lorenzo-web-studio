begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('public', 'recruitment_vacancies', 'vacancy authority exists');
select columns_are(
  'public', 'recruitment_vacancies',
  array[
    'id', 'title', 'slug', 'department', 'location', 'employment_type',
    'summary', 'description', 'requirements', 'status', 'published_at',
    'closed_at', 'created_at', 'updated_at'
  ],
  'vacancy authority contains only approved fields'
);
select has_function('public', 'create_recruitment_vacancy_v1', array['text', 'text', 'text', 'text', 'text', 'text', 'text', 'text']);
select has_function('public', 'update_recruitment_vacancy_v1', array['uuid', 'text', 'text', 'text', 'text', 'text', 'text', 'text']);
select has_function('public', 'set_recruitment_vacancy_status_v1', array['uuid', 'text']);
select has_function('public', 'list_public_recruitment_vacancies_v1', array[]::text[]);
select hasnt_table('public', 'recruitment_applications', 'applicant authority is not created');
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.recruitment_vacancies'::regclass),
  'vacancy authority enables and forces RLS'
);
select ok(
  not has_table_privilege('anon', 'public.recruitment_vacancies', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.recruitment_vacancies', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.recruitment_vacancies', 'select,insert,update,delete'),
  'runtime roles have no direct vacancy table authority'
);
select ok(
  has_function_privilege('anon', 'public.list_public_recruitment_vacancies_v1()', 'execute')
  and has_function_privilege('authenticated', 'public.list_public_recruitment_vacancies_v1()', 'execute')
  and not has_function_privilege('anon', 'public.create_recruitment_vacancy_v1(text,text,text,text,text,text,text,text)', 'execute')
  and has_function_privilege('authenticated', 'public.create_recruitment_vacancy_v1(text,text,text,text,text,text,text,text)', 'execute'),
  'public read and authenticated write function grants are exact'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.recruitment_vacancies'::regclass
      and conname = 'recruitment_vacancies_slug_key'
      and contype = 'u'
  ),
  'vacancy slug is unique'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.recruitment_vacancies'::regclass
      and conname = 'recruitment_vacancies_status_check'
      and pg_get_constraintdef(oid) ~ 'DRAFT.*PUBLISHED.*CLOSED'
  ),
  'status contract is exactly draft published closed'
);

set local role anon;
select throws_ok(
  $$select * from public.recruitment_vacancies$$,
  '42501', 'permission denied for table recruitment_vacancies',
  'anon direct vacancy read is denied'
);
select is(public.list_public_recruitment_vacancies_v1(), '[]'::jsonb, 'public list starts empty');
select throws_ok(
  $$select public.create_recruitment_vacancy_v1('Anon', 'anon', 'Ops', 'Remote', 'Full-time', 'Summary', 'Description', 'Requirements')$$,
  '42501', 'permission denied for function create_recruitment_vacancy_v1',
  'anon cannot create a vacancy'
);
reset role;

set local role authenticated;
select throws_ok(
  $$select * from public.recruitment_vacancies$$,
  '42501', 'permission denied for table recruitment_vacancies',
  'authenticated direct vacancy read is denied'
);
reset role;

insert into auth.users(id, email) values
  ('fd000000-0000-4000-8000-000000000001', 'recruitment-owner@example.test'),
  ('fd000000-0000-4000-8000-000000000002', 'recruitment-admin@example.test'),
  ('fd000000-0000-4000-8000-000000000003', 'recruitment-manager@example.test'),
  ('fd000000-0000-4000-8000-000000000004', 'recruitment-operator@example.test'),
  ('fd000000-0000-4000-8000-000000000005', 'recruitment-disabled@example.test'),
  ('fd000000-0000-4000-8000-000000000006', 'recruitment-unassigned@example.test');

insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('fd100000-0000-4000-8000-000000000001', 'fd000000-0000-4000-8000-000000000001', 'Recruitment Owner', 'owner', 'ACTIVE'),
  ('fd100000-0000-4000-8000-000000000002', 'fd000000-0000-4000-8000-000000000002', 'Recruitment Admin', 'admin', 'ACTIVE'),
  ('fd100000-0000-4000-8000-000000000003', 'fd000000-0000-4000-8000-000000000003', 'Recruitment Manager', 'operations_manager', 'ACTIVE'),
  ('fd100000-0000-4000-8000-000000000004', 'fd000000-0000-4000-8000-000000000004', 'Recruitment Operator', 'operator', 'ACTIVE'),
  ('fd100000-0000-4000-8000-000000000005', 'fd000000-0000-4000-8000-000000000005', 'Recruitment Disabled Owner', 'owner', 'DISABLED');

select set_config('test.workforce_employee_count', (select count(*)::text from public.workforce_employees), true);
select set_config('request.jwt.claim.sub', 'fd000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select set_config('test.vacancy_id', (public.create_recruitment_vacancy_v1(
    'Webdesigner', 'webdesigner', 'Design', 'Antwerpen', 'Full-time',
    'Bouw heldere digitale ervaringen.', 'Werk aan websites en klantprojecten.', 'Ervaring met toegankelijk webdesign.'
  )->>'id'), true)$$,
  'active owner can create a draft vacancy'
);
select is(
  public.update_recruitment_vacancy_v1(
    current_setting('test.vacancy_id')::uuid,
    'Senior Webdesigner', 'Design', 'Antwerpen', 'Full-time',
    'Bouw sterke digitale ervaringen.', 'Werk aan websites en klantprojecten.', 'Ervaring met toegankelijk webdesign.'
  )->>'slug',
  'webdesigner',
  'owner can update content while the stable slug is retained'
);
select is(public.list_public_recruitment_vacancies_v1(), '[]'::jsonb, 'draft vacancy is not public');
select isnt(
  public.set_recruitment_vacancy_status_v1(current_setting('test.vacancy_id')::uuid, 'PUBLISHED')->>'published_at',
  null,
  'owner publication sets published_at'
);
reset role;

set local role anon;
select is(jsonb_array_length(public.list_public_recruitment_vacancies_v1()), 1, 'published vacancy is public');
select is(
  (select array_agg(key order by key) from jsonb_object_keys(public.list_public_recruitment_vacancies_v1()->0) as key),
  array['department', 'description', 'employment_type', 'location', 'published_at', 'requirements', 'slug', 'summary', 'title'],
  'public projection exposes only approved website fields'
);
select ok(
  not (public.list_public_recruitment_vacancies_v1()::text ~* 'id|operator|auth|created_at|updated_at|closed_at|internal|note'),
  'public projection contains no internal identifiers or metadata'
);
reset role;

select set_config('request.jwt.claim.sub', 'fd000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select isnt(
  public.set_recruitment_vacancy_status_v1(current_setting('test.vacancy_id')::uuid, 'CLOSED')->>'closed_at',
  null,
  'owner can close a published vacancy and closed_at is set'
);
select is(public.list_public_recruitment_vacancies_v1(), '[]'::jsonb, 'closed vacancy is not public');
select throws_ok(
  $$select public.set_recruitment_vacancy_status_v1(current_setting('test.vacancy_id')::uuid, 'ARCHIVED')$$,
  '22023', 'INVALID_RECRUITMENT_VACANCY_STATUS',
  'invalid vacancy status is rejected'
);
select throws_ok(
  $$select public.create_recruitment_vacancy_v1('Duplicate', 'webdesigner', 'Design', 'Gent', 'Part-time', 'Summary', 'Description', 'Requirements')$$,
  '23505', null,
  'duplicate slug is rejected'
);
select throws_matching(
  $$select public.create_recruitment_vacancy_v1('Invalid slug', 'Invalid Slug', 'Design', 'Gent', 'Part-time', 'Summary', 'Description', 'Requirements')$$,
  '.*recruitment_vacancies_slug_format.*',
  'non-URL-safe slug is rejected'
);
reset role;

select set_config('request.jwt.claim.sub', 'fd000000-0000-4000-8000-000000000002', true);
set local role authenticated;
select throws_ok(
  $$select public.create_recruitment_vacancy_v1('Admin', 'admin-vacancy', 'Ops', 'Remote', 'Full-time', 'Summary', 'Description', 'Requirements')$$,
  '42501', 'RECRUITMENT_OWNER_REQUIRED', 'admin create is denied'
);
select throws_ok(
  $$select public.update_recruitment_vacancy_v1(current_setting('test.vacancy_id')::uuid, 'Admin edit', 'Ops', 'Remote', 'Full-time', 'Summary', 'Description', 'Requirements')$$,
  '42501', 'RECRUITMENT_OWNER_REQUIRED', 'admin update is denied'
);
select throws_ok(
  $$select public.set_recruitment_vacancy_status_v1(current_setting('test.vacancy_id')::uuid, 'PUBLISHED')$$,
  '42501', 'RECRUITMENT_OWNER_REQUIRED', 'admin publish is denied'
);
reset role;

select set_config('request.jwt.claim.sub', 'fd000000-0000-4000-8000-000000000003', true);
set local role authenticated;
select throws_ok(
  $$select public.create_recruitment_vacancy_v1('Manager', 'manager-vacancy', 'Ops', 'Remote', 'Full-time', 'Summary', 'Description', 'Requirements')$$,
  '42501', 'RECRUITMENT_OWNER_REQUIRED', 'operations manager create is denied'
);
select throws_ok(
  $$select public.update_recruitment_vacancy_v1(current_setting('test.vacancy_id')::uuid, 'Manager edit', 'Ops', 'Remote', 'Full-time', 'Summary', 'Description', 'Requirements')$$,
  '42501', 'RECRUITMENT_OWNER_REQUIRED', 'operations manager update is denied'
);
select throws_ok(
  $$select public.set_recruitment_vacancy_status_v1(current_setting('test.vacancy_id')::uuid, 'PUBLISHED')$$,
  '42501', 'RECRUITMENT_OWNER_REQUIRED', 'operations manager publish is denied'
);
reset role;

select set_config('request.jwt.claim.sub', 'fd000000-0000-4000-8000-000000000004', true);
set local role authenticated;
select throws_ok(
  $$select public.create_recruitment_vacancy_v1('Operator', 'operator-vacancy', 'Ops', 'Remote', 'Full-time', 'Summary', 'Description', 'Requirements')$$,
  '42501', 'RECRUITMENT_OWNER_REQUIRED', 'ordinary operator create is denied'
);
select throws_ok(
  $$select public.update_recruitment_vacancy_v1(current_setting('test.vacancy_id')::uuid, 'Operator edit', 'Ops', 'Remote', 'Full-time', 'Summary', 'Description', 'Requirements')$$,
  '42501', 'RECRUITMENT_OWNER_REQUIRED', 'ordinary operator update is denied'
);
select throws_ok(
  $$select public.set_recruitment_vacancy_status_v1(current_setting('test.vacancy_id')::uuid, 'PUBLISHED')$$,
  '42501', 'RECRUITMENT_OWNER_REQUIRED', 'ordinary operator publish is denied'
);
reset role;

select set_config('request.jwt.claim.sub', 'fd000000-0000-4000-8000-000000000005', true);
set local role authenticated;
select throws_ok(
  $$select public.create_recruitment_vacancy_v1('Disabled', 'disabled-vacancy', 'Ops', 'Remote', 'Full-time', 'Summary', 'Description', 'Requirements')$$,
  '42501', 'RECRUITMENT_OWNER_REQUIRED', 'disabled owner create is denied'
);
reset role;

select set_config('request.jwt.claim.sub', 'fd000000-0000-4000-8000-000000000006', true);
set local role authenticated;
select throws_ok(
  $$select public.create_recruitment_vacancy_v1('Unassigned', 'unassigned-vacancy', 'Ops', 'Remote', 'Full-time', 'Summary', 'Description', 'Requirements')$$,
  '42501', 'RECRUITMENT_OWNER_REQUIRED', 'authenticated user without operator authority is denied'
);
reset role;

select is(
  (select count(*)::text from public.workforce_employees),
  current_setting('test.workforce_employee_count'),
  'vacancy authority does not modify workforce employees'
);
select hasnt_table('public', 'recruitment_candidates', 'candidate authority is not created');
select hasnt_table('public', 'recruitment_onboarding', 'onboarding authority is not created');

select * from finish();
rollback;