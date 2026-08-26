begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(13);

select has_table('public','sdf_quotations','private SDF quotation identity foundation exists');
select columns_are('public','sdf_quotations',array['quotation_id','quote_request_id','created_at'],'SDF quotation foundation contains identity, application linkage, and creation time only');
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.sdf_quotations'::regclass),
  'SDF quotation identity has forced RLS'
);
select ok(
  not has_table_privilege('anon','public.sdf_quotations','select')
  and not has_table_privilege('authenticated','public.sdf_quotations','select')
  and not has_table_privilege('service_role','public.sdf_quotations','select')
  and not has_table_privilege('service_role','public.sdf_quotations','insert')
  and not has_table_privilege('service_role','public.sdf_quotations','update')
  and not has_table_privilege('service_role','public.sdf_quotations','delete'),
  'SDF quotation identity has no direct runtime privileges'
);
select ok(
  not exists(
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='sdf_quotations'
      and column_name in (
        'status','status_recorded_at','sdf_package','implementation_amount_minor',
        'recurring_amount_minor','currency','vat_amount_minor','total_minor',
        'pricing_snapshot_id','approval_id','quotation_number','quotation_version',
        'valid_until','issued_at','sent_at','acceptance_id'
      )
  ),
  'SDF quotation identity contains no status, pricing, or Website quotation columns'
);

insert into public.quote_requests (id,request_kind,sdf_package,name,email,website_type,budget,timing,description,privacy_consent,status) values
  ('c5100000-0000-4000-8000-000000000001','slimme_documentenflow','groei','SDF quotation fixture','sdf-quotation@example.test',null,null,null,'SDF quotation identity fixture.',true,'approved'),
  ('c5100001-0000-4000-8000-000000000002','website',null,'Website quotation fixture','website-quotation@example.test','business','Meer dan EUR 6.000','flexible','Website quotation isolation fixture.',true,'approved');

select is((select count(*)::integer from public.sdf_quotations),0,'SDF application creation does not automatically create quotation identity');

insert into public.sdf_projects(project_id,quote_request_id,created_at) values
  ('c5200000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','2099-01-02T09:00:00Z');

select is((select count(*)::integer from public.sdf_quotations),0,'SDF project identity creation does not automatically create quotation identity');
select lives_ok(
  $$insert into public.sdf_quotations(quotation_id,quote_request_id,created_at) values ('c5300000-0000-4000-8000-000000000001','c5100000-0000-4000-8000-000000000001','2099-01-03T10:00:00Z')$$,
  'an SDF quotation identity can be durably linked to an SDF application'
);
select is(
  (select quote_request_id::text || '|' || created_at::text from public.sdf_quotations where quotation_id='c5300000-0000-4000-8000-000000000001'),
  'c5100000-0000-4000-8000-000000000001|2099-01-03 10:00:00+00',
  'SDF quotation identity preserves exact application linkage and creation time'
);
select throws_ok(
  $$insert into public.sdf_quotations(quotation_id,quote_request_id) values ('c5300000-0000-4000-8000-000000000002','c5100000-0000-4000-8000-000000000001')$$,
  '23505', null, 'one SDF application cannot acquire multiple quotation identities'
);
select throws_ok(
  $$insert into public.sdf_quotations(quotation_id,quote_request_id) values ('c5300000-0000-4000-8000-000000000003','c5100001-0000-4000-8000-000000000002')$$,
  '23514', 'SDF_QUOTATION_REQUIRES_SDF_APPLICATION', 'Website applications cannot enter the SDF quotation identity authority'
);
select throws_ok(
  $$update public.sdf_quotations set created_at=clock_timestamp() where quotation_id='c5300000-0000-4000-8000-000000000001'$$,
  '55000', 'SDF_QUOTATION_IDENTITY_IMMUTABLE', 'SDF quotation identity and linkage cannot be rewritten'
);
select throws_ok(
  $$delete from public.sdf_quotations where quotation_id='c5300000-0000-4000-8000-000000000001'$$,
  '55000', 'SDF_QUOTATION_IDENTITY_IMMUTABLE', 'SDF quotation identity cannot be deleted'
);

select * from finish();
rollback;