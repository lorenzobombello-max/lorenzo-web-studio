begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, storage, extensions;
select no_plan();

select has_table('public', 'recruitment_applications', 'private application authority exists');
select columns_are(
  'public', 'recruitment_applications',
  array[
    'id', 'vacancy_id', 'first_name', 'last_name', 'email', 'phone',
    'motivation', 'cv_storage_path', 'cv_mime_type', 'cv_byte_count',
    'cv_sha256', 'status', 'submitted_at', 'created_at', 'updated_at'
  ],
  'application authority contains only approved candidate and CV integrity fields'
);
select has_function(
  'public', 'finalize_recruitment_application_v1',
  array['uuid','uuid','text','text','text','text','text','text','text','bigint','text'],
  'service-only application finalizer exists'
);
select has_function('public', 'list_owner_recruitment_applications_v1', array[]::text[], 'owner list authority exists');
select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class where oid = 'public.recruitment_applications'::regclass),
  'application table enables and forces RLS'
);
select ok(
  not has_table_privilege('anon', 'public.recruitment_applications', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.recruitment_applications', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.recruitment_applications', 'select,insert,update,delete'),
  'runtime roles have no direct application table authority'
);
select ok(
  has_function_privilege('service_role', 'public.finalize_recruitment_application_v1(uuid,uuid,text,text,text,text,text,text,text,bigint,text)', 'execute')
  and not has_function_privilege('anon', 'public.finalize_recruitment_application_v1(uuid,uuid,text,text,text,text,text,text,text,bigint,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.finalize_recruitment_application_v1(uuid,uuid,text,text,text,text,text,text,text,bigint,text)', 'execute'),
  'only service role can execute application finalization'
);
select ok(
  has_function_privilege('authenticated', 'public.list_owner_recruitment_applications_v1()', 'execute')
  and not has_function_privilege('anon', 'public.list_owner_recruitment_applications_v1()', 'execute'),
  'owner list has authenticated caller-JWT surface only'
);

select is((select public from storage.buckets where id = 'recruitment-cvs'), false, 'CV bucket is private');
select is((select file_size_limit from storage.buckets where id = 'recruitment-cvs'), 10485760::bigint, 'CV bucket enforces ten MiB maximum');
select is(
  (select allowed_mime_types from storage.buckets where id = 'recruitment-cvs'),
  array[
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ]::text[],
  'CV bucket allows only PDF DOC and DOCX'
);
select is(
  (select count(*)::integer from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and (coalesce(qual, '') like '%recruitment-cvs%'
       or coalesce(with_check, '') like '%recruitment-cvs%')),
  0,
  'CV bucket has no browser Storage policy'
);

insert into auth.users(id, email) values
  ('fa200000-0000-4000-8000-000000000001', 'application-owner@example.test'),
  ('fa200000-0000-4000-8000-000000000002', 'application-non-owner@example.test');
insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('fa210000-0000-4000-8000-000000000001', 'fa200000-0000-4000-8000-000000000001', 'Application Owner', 'owner', 'ACTIVE'),
  ('fa210000-0000-4000-8000-000000000002', 'fa200000-0000-4000-8000-000000000002', 'Application Operator', 'operator', 'ACTIVE');

insert into public.recruitment_vacancies(
  id, title, slug, department, location, employment_type,
  summary, description, requirements, status, published_at, closed_at
) values
  ('fa300000-0000-4000-8000-000000000001', 'Published role', 'published-role', 'Development', 'Lievegem', 'Full-time', 'Summary', 'Description', 'Requirements', 'PUBLISHED', clock_timestamp(), null),
  ('fa300000-0000-4000-8000-000000000002', 'Draft role', 'draft-role', 'Development', 'Lievegem', 'Full-time', 'Summary', 'Description', 'Requirements', 'DRAFT', null, null),
  ('fa300000-0000-4000-8000-000000000003', 'Closed role', 'closed-role', 'Development', 'Lievegem', 'Full-time', 'Summary', 'Description', 'Requirements', 'CLOSED', clock_timestamp() - interval '1 day', clock_timestamp());

insert into storage.objects(bucket_id, name, metadata) values
  ('recruitment-cvs', 'applications/fa400000-0000-4000-8000-000000000001/cv.pdf', jsonb_build_object('size', 101, 'mimetype', 'application/pdf', 'sha256', repeat('a', 64))),
  ('recruitment-cvs', 'applications/fa400000-0000-4000-8000-000000000002/cv.pdf', jsonb_build_object('size', 102, 'mimetype', 'application/pdf', 'sha256', repeat('b', 64))),
  ('recruitment-cvs', 'applications/fa400000-0000-4000-8000-000000000003/cv.doc', jsonb_build_object('size', 103, 'mimetype', 'application/msword', 'sha256', repeat('c', 64))),
  ('recruitment-cvs', 'applications/fa400000-0000-4000-8000-000000000004/cv.docx', jsonb_build_object('size', 104, 'mimetype', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'sha256', repeat('d', 64))),
  ('recruitment-cvs', 'applications/fa400000-0000-4000-8000-000000000005/cv.pdf', jsonb_build_object('size', 105, 'mimetype', 'application/pdf', 'sha256', repeat('e', 64))),
  ('recruitment-cvs', 'applications/fa400000-0000-4000-8000-000000000006/cv.pdf', jsonb_build_object('size', 106, 'mimetype', 'application/pdf', 'sha256', repeat('f', 64)));

set local role anon;
select throws_ok(
  $$select * from public.recruitment_applications$$,
  '42501', 'permission denied for table recruitment_applications',
  'anon direct application SELECT is denied'
);
select throws_ok(
  $$insert into public.recruitment_applications(id,vacancy_id,first_name,last_name,email,motivation,cv_storage_path,cv_mime_type,cv_byte_count,cv_sha256) values('fa4f0000-0000-4000-8000-000000000001','fa300000-0000-4000-8000-000000000001','Anon','Candidate','anon@example.test','Motivation','applications/fa4f0000-0000-4000-8000-000000000001/cv.pdf','application/pdf',1,repeat('a',64))$$,
  '42501', 'permission denied for table recruitment_applications',
  'anon direct application INSERT is denied'
);
select is(
  (select count(*)::integer from storage.objects where bucket_id = 'recruitment-cvs'),
  0,
  'anon cannot list or read private CV objects'
);
select throws_matching(
  $$insert into storage.objects(bucket_id,name,metadata) values('recruitment-cvs','attacker/cv.pdf','{}')$$,
  '.*row-level security.*|.*permission denied.*',
  'anon arbitrary CV upload is denied'
);
reset role;

select set_config('request.jwt.claim.sub', 'fa200000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select throws_ok(
  $$select * from public.recruitment_applications$$,
  '42501', 'permission denied for table recruitment_applications',
  'authenticated non-owner direct application SELECT is denied'
);
select is(
  (select count(*)::integer from storage.objects where bucket_id = 'recruitment-cvs'),
  0,
  'authenticated non-owner cannot list private CV objects'
);
select throws_ok(
  $$select public.list_owner_recruitment_applications_v1()$$,
  '42501', 'RECRUITMENT_OWNER_REQUIRED',
  'non-owner owner-list call is denied'
);
reset role;

select set_config('request.jwt.claim.role', 'service_role', true);
select is(
  public.finalize_recruitment_application_v1(
    'fa400000-0000-4000-8000-000000000001', 'fa300000-0000-4000-8000-000000000001',
    ' Ada ', ' Lovelace ', ' ADA@EXAMPLE.TEST ', '', ' Secure software matters. ',
    'applications/fa400000-0000-4000-8000-000000000001/cv.pdf',
    'application/pdf', 101, repeat('a', 64)
  )->>'status',
  'SUBMITTED',
  'PUBLISHED vacancy accepts a valid application as SUBMITTED'
);
select is((select email from public.recruitment_applications where id = 'fa400000-0000-4000-8000-000000000001'), 'ada@example.test', 'email is normalized server-side');
select is((select phone from public.recruitment_applications where id = 'fa400000-0000-4000-8000-000000000001'), null, 'blank optional phone is stored as null');

select throws_ok(
  $$select public.finalize_recruitment_application_v1('fa400000-0000-4000-8000-000000000002','fa300000-0000-4000-8000-000000000002','Draft','Candidate','draft@example.test',null,'Motivation','applications/fa400000-0000-4000-8000-000000000002/cv.pdf','application/pdf',102,repeat('b',64))$$,
  '22023', 'RECRUITMENT_VACANCY_NOT_OPEN', 'DRAFT vacancy is denied'
);
select throws_ok(
  $$select public.finalize_recruitment_application_v1('fa400000-0000-4000-8000-000000000003','fa300000-0000-4000-8000-000000000003','Closed','Candidate','closed@example.test',null,'Motivation','applications/fa400000-0000-4000-8000-000000000003/cv.doc','application/msword',103,repeat('c',64))$$,
  '22023', 'RECRUITMENT_VACANCY_NOT_OPEN', 'CLOSED vacancy is denied'
);
select throws_ok(
  $$select public.finalize_recruitment_application_v1('fa400000-0000-4000-8000-000000000004','fa300000-0000-4000-8000-000000000099','Unknown','Candidate','unknown@example.test',null,'Motivation','applications/fa400000-0000-4000-8000-000000000004/cv.docx','application/vnd.openxmlformats-officedocument.wordprocessingml.document',104,repeat('d',64))$$,
  'P0002', 'RECRUITMENT_VACANCY_NOT_FOUND', 'unknown vacancy is denied'
);
select throws_ok(
  $$select public.finalize_recruitment_application_v1('fa400000-0000-4000-8000-000000000005','fa300000-0000-4000-8000-000000000001','', 'Candidate','empty@example.test',null,'Motivation','applications/fa400000-0000-4000-8000-000000000005/cv.pdf','application/pdf',105,repeat('e',64))$$,
  '22023', 'INVALID_RECRUITMENT_FIRST_NAME', 'empty required name is denied'
);
select throws_ok(
  $$select public.finalize_recruitment_application_v1('fa400000-0000-4000-8000-000000000006','fa300000-0000-4000-8000-000000000001','Long','Candidate','long@example.test',null,repeat('x',5001),'applications/fa400000-0000-4000-8000-000000000006/cv.pdf','application/pdf',106,repeat('f',64))$$,
  '22023', 'INVALID_RECRUITMENT_MOTIVATION', 'overlong motivation is denied'
);
select throws_ok(
  $$select public.finalize_recruitment_application_v1('fa400000-0000-4000-8000-000000000005','fa300000-0000-4000-8000-000000000001','Path','Candidate','path@example.test',null,'Motivation','attacker/cv.pdf','application/pdf',105,repeat('e',64))$$,
  '22023', 'INVALID_RECRUITMENT_CV_STORAGE_PATH', 'arbitrary CV storage path is denied'
);
select is((select count(*)::integer from public.recruitment_applications), 1, 'failed submissions create no application rows');
select is((select status from public.recruitment_applications), 'SUBMITTED', 'public input cannot determine application status');

select set_config('request.jwt.claim.sub', 'fa200000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select is(jsonb_array_length(public.list_owner_recruitment_applications_v1()), 1, 'active owner can list private applications');
reset role;

select ok(
  (select prosrc !~* 'lorenzo|@[a-z0-9]|auth_user_id[[:space:]]*=[[:space:]]*''[0-9a-f-]+'''
   from pg_proc where oid = 'public.list_owner_recruitment_applications_v1()'::regprocedure),
  'owner authority contains no hardcoded identity'
);
select ok(
  not exists (
    select 1 from pg_constraint
    where conrelid = 'public.recruitment_applications'::regclass
      and contype = 'u'
      and pg_get_constraintdef(oid) ~* 'vacancy_id.*email|email.*vacancy_id'
  ),
  'email and vacancy are not hard-unique without a duplicate product decision'
);
select ok(
  (select prosrc !~* 'createSignedUrl|publicUrl|signed_url'
   from pg_proc where oid = 'public.list_owner_recruitment_applications_v1()'::regprocedure),
  'owner list creates no public or signed CV URL'
);

select * from finish();
rollback;