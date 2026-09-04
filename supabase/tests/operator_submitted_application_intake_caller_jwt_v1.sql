begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(14);

select ok(
  has_function_privilege('authenticated', 'public.get_operator_submitted_application_intake_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.get_operator_submitted_application_intake_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.get_operator_submitted_application_intake_v1(uuid,uuid)', 'execute'),
  'only authenticated callers can execute the intake projection'
);

select ok(
  not has_table_privilege('authenticated', 'public.quote_request_intakes', 'select')
  and not has_table_privilege('anon', 'public.quote_request_intakes', 'select'),
  'the intake table remains closed to authenticated and anonymous roles'
);

select ok(
  pg_get_functiondef('public.get_operator_submitted_application_intake_v1(uuid,uuid)'::regprocedure)
    like '%auth.uid() <> p_actor_auth_user_id%'
  and pg_get_functiondef('public.get_operator_submitted_application_intake_v1(uuid,uuid)'::regprocedure)
    like '%assert_operator_application_actor_v2(p_actor_auth_user_id)%',
  'intake projection binds auth.uid and preserves owner/admin authority'
);

insert into auth.users (id, email) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'step-2j-owner@example.test'),
  ('bd2ab636-0d42-4069-88a9-60bd97f2b335', 'step-2j-operator-two@example.test'),
  ('d0247fd9-60d5-40bc-a905-6b02024b6420', 'step-2j-operator-three@example.test')
on conflict (id) do nothing;

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values
  ('2d110000-0000-4000-8000-000000000001', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'Step 2J Owner', 'owner', 'ACTIVE'),
  ('2d110000-0000-4000-8000-000000000002', 'bd2ab636-0d42-4069-88a9-60bd97f2b335', 'Step 2J Operator Two', 'operator', 'ACTIVE')
on conflict (auth_user_id) do update
set role = excluded.role, status = excluded.status;

insert into public.quote_requests (
  id, record_classification, request_kind, website_type, budget, timing,
  name, company, email, phone, description, privacy_consent, status
) values (
  '2d120000-0000-4000-8000-000000000001', 'production', 'website', 'business',
  'EUR 3.200 t/m EUR 6.000', 'flexible', 'Step 2J Fixture', 'Step 2J Company',
  'step-2j-fixture@example.test', null, 'Intake projection fixture.', true, 'approved'
);

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  started_at, submitted_at, confirmation, business_description
) values (
  '2d130000-0000-4000-8000-000000000001',
  '2d120000-0000-4000-8000-000000000001',
  'submitted', repeat('d', 64), clock_timestamp() + interval '7 days',
  clock_timestamp(), clock_timestamp(), true, 'Step 2J evidence fixture.'
);

select set_config('request.jwt.claims', '{"role":"authenticated","aal":"aal1"}', true);
set local role authenticated;
select throws_ok(
  $$select public.get_operator_submitted_application_intake_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2d120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'HUMAN_JWT_REQUIRED',
  'authenticated transport without a human subject is rejected'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select is(
  (select array_agg(key order by key) from jsonb_object_keys(
    public.get_operator_submitted_application_intake_v1(
      'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
      '2d120000-0000-4000-8000-000000000001'
    )
  ) as key),
  array[
    'additional_languages','additional_notes','booking_details','booking_required','brand_colors',
    'brand_status','budget_notes','business_description','content_media_details','content_status',
    'deadline_date','deadline_details','deadline_reason','design_styles','disliked_styles','domain_name',
    'domain_status','download_details','elements_to_keep','existing_website_url','has_existing_website',
    'hosting_maintenance_details','hosting_status','hosting_support','id','image_status','image_support',
    'improvement_areas','inspiration_sites','integrations','languages','logo_status','maintenance_interest',
    'multilingual_details','newsletter_details','other_pages','page_scope_details','primary_conversion_goal',
    'primary_language','priorities','quote_form_details','quote_request_id','requested_features',
    'requested_pages','seo_details','seo_priority','shop_details','shop_required','social_channels','status',
    'submitted_at','target_audience','website_goals'
  ]::text[],
  'OP-01 receives exactly the 53 allowlisted intake fields'
);
select throws_ok(
  $$select public.get_operator_submitted_application_intake_v1(
    'bd2ab636-0d42-4069-88a9-60bd97f2b335',
    '2d120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'OPERATOR_IDENTITY_MISMATCH',
  'an authenticated owner cannot spoof another actor UUID'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"bd2ab636-0d42-4069-88a9-60bd97f2b335","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.get_operator_submitted_application_intake_v1(
    'bd2ab636-0d42-4069-88a9-60bd97f2b335',
    '2d120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'APPLICATION_SCOPE_DENIED',
  'OP-02 remains outside owner/admin application scope'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"d0247fd9-60d5-40bc-a905-6b02024b6420","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.get_operator_submitted_application_intake_v1(
    'd0247fd9-60d5-40bc-a905-6b02024b6420',
    '2d120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'UNKNOWN_OPERATOR',
  'OP-03 remains unknown to Operator authority'
);
reset role;

set local role service_role;
select throws_ok(
  $$select public.get_operator_submitted_application_intake_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2d120000-0000-4000-8000-000000000001'
  )$$,
  '42501',
  'permission denied for function get_operator_submitted_application_intake_v1',
  'service role cannot execute the intake projection'
);
reset role;

set local role anon;
select throws_ok(
  $$select public.get_operator_submitted_application_intake_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2d120000-0000-4000-8000-000000000001'
  )$$,
  '42501',
  'permission denied for function get_operator_submitted_application_intake_v1',
  'anonymous callers cannot execute the intake projection'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select is(
  public.get_operator_submitted_application_intake_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2d120000-0000-4000-8000-000000000099'
  ),
  null::jsonb,
  'a missing request returns null'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select ok(
  public.get_operator_submitted_application_intake_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2d120000-0000-4000-8000-000000000001'
  ) ->> 'business_description' = 'Step 2J evidence fixture.',
  'existing intake evidence semantics are preserved'
);
reset role;

select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'quote_request_intakes'
  ),
  'no intake RLS policy was introduced'
);

select ok(
  (select relrowsecurity and not relforcerowsecurity
   from pg_class where oid = 'public.quote_request_intakes'::regclass),
  'intake RLS remains enabled without FORCE RLS'
);

select * from finish();
rollback;