begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, storage, extensions;
select no_plan();

select has_table('public', 'recruitment_publication_settings', 'publication singleton authority exists');
select columns_are(
  'public', 'recruitment_publication_settings',
  array['singleton', 'enabled', 'updated_at'],
  'publication authority contains only the required fields'
);
select has_function('public', 'get_public_recruitment_publication_state_v1', array[]::text[], 'minimal public read exists');
select has_function('public', 'set_recruitment_publication_enabled_v1', array['boolean'], 'owner write exists');
select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class where oid = 'public.recruitment_publication_settings'::regclass),
  'publication authority enables and forces RLS'
);
select ok(
  not has_table_privilege('anon', 'public.recruitment_publication_settings', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.recruitment_publication_settings', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.recruitment_publication_settings', 'select,insert,update,delete'),
  'runtime roles have no direct settings table authority'
);
select ok(
  has_function_privilege('anon', 'public.get_public_recruitment_publication_state_v1()', 'execute')
  and has_function_privilege('authenticated', 'public.get_public_recruitment_publication_state_v1()', 'execute')
  and not has_function_privilege('anon', 'public.set_recruitment_publication_enabled_v1(boolean)', 'execute')
  and has_function_privilege('authenticated', 'public.set_recruitment_publication_enabled_v1(boolean)', 'execute'),
  'public read and authenticated write grants are exact'
);
select is(public.get_public_recruitment_publication_state_v1(), '{"enabled": true}'::jsonb, 'initial state is enabled');
select is(
  (select array_agg(key order by key) from jsonb_object_keys(public.get_public_recruitment_publication_state_v1()) as key),
  array['enabled'],
  'public read exposes only enabled'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.recruitment_publication_settings'::regclass
      and conname = 'recruitment_publication_settings_singleton'
  ),
  'singleton constraint exists'
);

insert into public.recruitment_vacancies (
  id, title, slug, department, location, employment_type,
  summary, description, requirements, status, published_at
) values (
  'fc200000-0000-4000-8000-000000000001', 'Publication fixture', 'publication-fixture',
  'Engineering', 'Lievegem', 'Voltijds', 'Publieke fixture.',
  'Alleen zichtbaar wanneer publicatie actief is.', 'Testvereisten.',
  'PUBLISHED', clock_timestamp()
);

select set_config('test.recruitment_vacancy_count', (select count(*)::text from public.recruitment_vacancies), true);
select set_config('test.recruitment_application_count', (select count(*)::text from public.recruitment_applications), true);
select set_config('test.recruitment_cv_count', (select count(*)::text from storage.objects where bucket_id = 'recruitment-cvs'), true);

set local role anon;
select throws_ok(
  $$select * from public.recruitment_publication_settings$$,
  '42501', 'permission denied for table recruitment_publication_settings',
  'anon direct settings read is denied'
);
select throws_ok(
  $$select public.set_recruitment_publication_enabled_v1(false)$$,
  '42501', 'permission denied for function set_recruitment_publication_enabled_v1',
  'anon write is denied'
);
select is(public.get_public_recruitment_publication_state_v1(), '{"enabled": true}'::jsonb, 'anon reads minimal enabled state');
select is(jsonb_array_length(public.list_public_recruitment_vacancies_v1()), 1, 'enabled publication exposes published vacancies');
reset role;

insert into auth.users(id, email) values
  ('fc000000-0000-4000-8000-000000000001', 'publication-owner@example.test'),
  ('fc000000-0000-4000-8000-000000000002', 'publication-operator@example.test');

insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('fc100000-0000-4000-8000-000000000001', 'fc000000-0000-4000-8000-000000000001', 'Publication Owner', 'owner', 'ACTIVE'),
  ('fc100000-0000-4000-8000-000000000002', 'fc000000-0000-4000-8000-000000000002', 'Publication Operator', 'operator', 'ACTIVE');

select set_config('request.jwt.claim.sub', 'fc000000-0000-4000-8000-000000000002', true);
set local role authenticated;
select throws_ok(
  $$select public.set_recruitment_publication_enabled_v1(false)$$,
  '42501', 'RECRUITMENT_OWNER_REQUIRED',
  'authenticated non-owner write is denied'
);
reset role;

select set_config('request.jwt.claim.sub', 'fc000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select is(
  public.set_recruitment_publication_enabled_v1(false),
  '{"enabled": false}'::jsonb,
  'owner can disable public recruitment'
);
select is(public.get_public_recruitment_publication_state_v1(), '{"enabled": false}'::jsonb, 'public read returns disabled state');
select is(public.list_public_recruitment_vacancies_v1(), '[]'::jsonb, 'disabled publication exposes no vacancies');
select is(
  public.set_recruitment_publication_enabled_v1(true),
  '{"enabled": true}'::jsonb,
  'owner can enable public recruitment'
);
select is(jsonb_array_length(public.list_public_recruitment_vacancies_v1()), 1, 're-enabled publication restores published vacancy visibility');
select throws_ok(
  $$select public.set_recruitment_publication_enabled_v1(null)$$,
  '22023', 'INVALID_RECRUITMENT_PUBLICATION_STATE',
  'null publication state is rejected'
);
reset role;

select is(
  (select status from public.recruitment_vacancies where id = 'fc200000-0000-4000-8000-000000000001'),
  'PUBLISHED',
  'publication toggles preserve vacancy status'
);

select is(
  (select count(*)::text from public.recruitment_vacancies),
  current_setting('test.recruitment_vacancy_count'),
  'toggle does not mutate vacancies'
);
select is(
  (select count(*)::text from public.recruitment_applications),
  current_setting('test.recruitment_application_count'),
  'toggle does not mutate applications'
);
select is(
  (select count(*)::text from storage.objects where bucket_id = 'recruitment-cvs'),
  current_setting('test.recruitment_cv_count'),
  'toggle does not mutate CV storage'
);
select ok(
  not (pg_get_functiondef('public.set_recruitment_publication_enabled_v1(boolean)'::regprocedure)
    ~* '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}'),
  'owner authority contains no hardcoded email identity'
);

select * from finish();
rollback;