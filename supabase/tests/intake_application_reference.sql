begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(22);

select has_column('public', 'quote_requests', 'application_reference', 'application reference is stored on the application record');
select has_table('public', 'application_reference_counters', 'yearly application reference counters exist');
select col_is_null('public', 'quote_requests', 'application_reference', 'historical application references remain nullable');
select has_trigger('public', 'quote_request_intakes', 'trg_quote_request_intakes_assign_application_reference', 'submission transition assigns the reference');
select has_trigger('public', 'quote_requests', 'trg_quote_requests_application_reference_immutable', 'assigned references are immutable');
select ok(not has_table_privilege('anon', 'public.application_reference_counters', 'select'), 'anonymous callers cannot inspect counters');
select ok(not has_table_privilege('authenticated', 'public.application_reference_counters', 'select'), 'authenticated callers cannot inspect counters');

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, budget_category_scheme, budget_category_code
) values
('19b20000-0000-4000-8000-000000000001','Legacy application','legacy@example.test','business','Meer dan EUR 6.000','flexible','Legacy reference fixture',true,'approved','budget_guard_v2','above_6000'),
('19b20000-0000-4000-8000-000000000002','New application one','one@example.test','business','Meer dan EUR 6.000','flexible','Reference fixture one',true,'approved','budget_guard_v2','above_6000'),
('19b20000-0000-4000-8000-000000000003','New application two','two@example.test','business','Meer dan EUR 6.000','flexible','Reference fixture two',true,'approved','budget_guard_v2','above_6000'),
('19b20000-0000-4000-8000-000000000004','Year boundary','year@example.test','business','Meer dan EUR 6.000','flexible','Year boundary fixture',true,'approved','budget_guard_v2','above_6000');

insert into public.quote_request_intakes (
  id, quote_request_id, access_token_hash, access_token_expires_at
) values
('19b21000-0000-4000-8000-000000000002','19b20000-0000-4000-8000-000000000002',repeat('1',64),clock_timestamp()+interval '1 day'),
('19b21000-0000-4000-8000-000000000003','19b20000-0000-4000-8000-000000000003',repeat('2',64),clock_timestamp()+interval '1 day'),
('19b21000-0000-4000-8000-000000000004','19b20000-0000-4000-8000-000000000004',repeat('3',64),clock_timestamp()+interval '10 years');

create function pg_temp.submit_application(p_access_hash text, p_admin_hash text)
returns text
language sql
as $$
  select outcome
  from public.update_quote_request_intake(
    p_access_hash,
    'submit',
    jsonb_build_object(
      'business_description','Complete application reference fixture',
      'target_audience','Local businesses',
      'primary_conversion_goal','Request quote',
      'website_goals',jsonb_build_array('generate_leads'),
      'requested_pages',jsonb_build_array('home'),
      'requested_features','[]'::jsonb,
      'design_styles',jsonb_build_array('modern'),
      'brand_status','complete',
      'logo_status','available',
      'content_status','complete',
      'image_status','sufficient',
      'domain_status','has_domain',
      'hosting_status','has_hosting',
      'maintenance_interest','no',
      'seo_priority','basic',
      'priorities',jsonb_build_array('usability'),
      'confirmation',true
    ),
    p_admin_hash,
    clock_timestamp()+interval '1 day'
  )
$$;

select is(
  (select application_reference from public.quote_requests where id='19b20000-0000-4000-8000-000000000001'),
  null,
  'historical records are not assigned fabricated references'
);

select is(pg_temp.submit_application(repeat('1',64), repeat('a',64)), 'submitted', 'first valid submission succeeds');

select matches(
  (select application_reference from public.quote_requests where id='19b20000-0000-4000-8000-000000000002'),
  '^LWS-AAN-[0-9]{4}-[0-9]{4}$',
  'first submission receives the required human-readable format'
);
select is(
  (select id::text from public.quote_requests where application_reference is not null),
  '19b20000-0000-4000-8000-000000000002',
  'the internal UUID remains the database identifier'
);

create temporary table first_reference as
select application_reference
from public.quote_requests
where id='19b20000-0000-4000-8000-000000000002';

select is(pg_temp.submit_application(repeat('1',64), repeat('a',64)), 'already_submitted', 'duplicate submit follows the idempotent path');

select is(
  (select application_reference from public.quote_requests where id='19b20000-0000-4000-8000-000000000002'),
  (select application_reference from first_reference),
  'idempotent retry preserves the same application reference'
);
select is(
  (select count(*)::integer from public.quote_request_email_jobs where quote_request_id='19b20000-0000-4000-8000-000000000002' and kind='intake_submitted_notification'),
  1,
  'idempotent retry preserves one notification job'
);

select is(pg_temp.submit_application(repeat('2',64), repeat('b',64)), 'submitted', 'second valid submission succeeds');

select is(
  right((select application_reference from public.quote_requests where id='19b20000-0000-4000-8000-000000000003'), 4)::integer,
  right((select application_reference from first_reference), 4)::integer + 1,
  'references increase monotonically within the year'
);
select is(
  left((select application_reference from public.quote_requests where id='19b20000-0000-4000-8000-000000000003'), 12),
  left((select application_reference from first_reference), 12),
  'consecutive references use the same current year prefix'
);
select is(
  (select count(distinct application_reference)::integer from public.quote_requests where id in ('19b20000-0000-4000-8000-000000000002','19b20000-0000-4000-8000-000000000003')),
  2,
  'separate applications have unique references'
);
select throws_matching(
  $$update public.quote_requests set application_reference='LWS-AAN-2099-9999' where id='19b20000-0000-4000-8000-000000000002'$$,
  'APPLICATION_REFERENCE_IMMUTABLE',
  'assigned application references cannot be changed'
);
select throws_matching(
  $$update public.quote_requests set application_reference=null where id='19b20000-0000-4000-8000-000000000002'$$,
  'APPLICATION_REFERENCE_IMMUTABLE',
  'assigned application references cannot be removed'
);
select is(
  (select count(*)::integer from public.application_reference_counters),
  1,
  'only the active year counter is created'
);

update public.quote_request_intakes
set business_description='Year boundary', target_audience='Local businesses',
  primary_conversion_goal='Request quote', website_goals=array['generate_leads'],
  requested_pages=array['home'], requested_features='{}', design_styles=array['modern'],
  brand_status='complete', logo_status='available', content_status='complete',
  image_status='sufficient', domain_status='has_domain', hosting_status='has_hosting',
  maintenance_interest='no', seo_priority='basic', priorities=array['usability'],
  confirmation=true, started_at='2030-12-31 22:59:00+00',
  submitted_at='2030-12-31 23:00:00+00', status='submitted',
  admin_access_token_hash=repeat('c',64),
  admin_access_token_expires_at='2031-01-02 00:00:00+00'
where id='19b21000-0000-4000-8000-000000000004';

select matches(
  (select application_reference from public.quote_requests where id='19b20000-0000-4000-8000-000000000004'),
  '^LWS-AAN-2031-0001$',
  'reference year follows submitted_at in Europe Brussels at the year boundary'
);

select * from finish();
rollback;