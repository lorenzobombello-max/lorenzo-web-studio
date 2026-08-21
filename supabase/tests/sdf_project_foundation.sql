begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(11);

select has_table('public','sdf_projects','private SDF project foundation exists');
select columns_are('public','sdf_projects',array['project_id','quote_request_id','created_at'],'SDF project foundation contains identity, application linkage, and creation time only');
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.sdf_projects'::regclass),
  'SDF project foundation has forced RLS'
);
select ok(
  not has_table_privilege('anon','public.sdf_projects','select')
  and not has_table_privilege('authenticated','public.sdf_projects','select')
  and not has_table_privilege('service_role','public.sdf_projects','select'),
  'SDF project foundation has no direct runtime read privileges'
);

insert into public.quote_requests (id,request_kind,sdf_package,name,email,website_type,budget,timing,description,privacy_consent,status) values
  ('b5100000-0000-4000-8000-000000000001','slimme_documentenflow','groei','SDF project fixture','sdf-project@example.test',null,null,null,'SDF project foundation fixture.',true,'approved'),
  ('b5100000-0000-4000-8000-000000000002','website',null,'Website project fixture','website-project@example.test','business','Meer dan EUR 6.000','flexible','Website project isolation fixture.',true,'approved');

select lives_ok(
  $$insert into public.sdf_projects(project_id,quote_request_id,created_at) values ('b5200000-0000-4000-8000-000000000001','b5100000-0000-4000-8000-000000000001','2099-01-02T10:00:00Z')$$,
  'an SDF project identity can be durably linked to an SDF application'
);
select is(
  (select quote_request_id::text || '|' || created_at::text from public.sdf_projects where project_id='b5200000-0000-4000-8000-000000000001'),
  'b5100000-0000-4000-8000-000000000001|2099-01-02 10:00:00+00',
  'SDF project authority preserves exact application linkage and creation time'
);
select throws_ok(
  $$insert into public.sdf_projects(project_id,quote_request_id) values ('b5200000-0000-4000-8000-000000000002','b5100000-0000-4000-8000-000000000001')$$,
  '23505', null, 'one SDF application cannot acquire multiple project identities'
);
select throws_ok(
  $$insert into public.sdf_projects(project_id,quote_request_id) values ('b5200000-0000-4000-8000-000000000003','b5100000-0000-4000-8000-000000000002')$$,
  '23514', 'SDF_PROJECT_REQUIRES_SDF_APPLICATION', 'Website applications cannot enter the SDF project authority'
);
select throws_ok(
  $$update public.sdf_projects set created_at=clock_timestamp() where project_id='b5200000-0000-4000-8000-000000000001'$$,
  '55000', 'SDF_PROJECT_IMMUTABLE', 'SDF project identity cannot be rewritten'
);
select throws_ok(
  $$delete from public.sdf_projects where project_id='b5200000-0000-4000-8000-000000000001'$$,
  '55000', 'SDF_PROJECT_IMMUTABLE', 'SDF project identity cannot be deleted'
);
select ok(
  not exists(
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='sdf_projects'
      and column_name in ('project_status','accepted_total_minor','recurring_service_id')
  ),
  'SDF project identity fabricates no status, pricing, or recurring lifecycle'
);

select * from finish();
rollback;