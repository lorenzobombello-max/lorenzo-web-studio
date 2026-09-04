begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(11);

select ok(
  has_function_privilege('authenticated', 'public.get_operator_submitted_application_request_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.get_operator_submitted_application_request_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.get_operator_submitted_application_request_v1(uuid,uuid)', 'execute'),
  'only authenticated callers can execute the request projection'
);

select ok(
  not has_table_privilege('authenticated', 'public.quote_requests', 'select')
  and not has_table_privilege('anon', 'public.quote_requests', 'select'),
  'the request table remains closed to authenticated and anonymous roles'
);

select ok(
  pg_get_functiondef('public.get_operator_submitted_application_request_v1(uuid,uuid)'::regprocedure)
    like '%auth.uid() <> p_actor_auth_user_id%'
  and pg_get_functiondef('public.get_operator_submitted_application_request_v1(uuid,uuid)'::regprocedure)
    like '%assert_operator_application_actor_v2(p_actor_auth_user_id)%',
  'request projection binds auth.uid and preserves owner/admin authority'
);

insert into auth.users (id, email) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'step-2i-owner@example.test'),
  ('bd2ab636-0d42-4069-88a9-60bd97f2b335', 'step-2i-operator-two@example.test'),
  ('d0247fd9-60d5-40bc-a905-6b02024b6420', 'step-2i-operator-three@example.test')
on conflict (id) do nothing;

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values
  ('2c110000-0000-4000-8000-000000000001', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'Step 2I Owner', 'owner', 'ACTIVE'),
  ('2c110000-0000-4000-8000-000000000002', 'bd2ab636-0d42-4069-88a9-60bd97f2b335', 'Step 2I Operator Two', 'operator', 'ACTIVE')
on conflict (auth_user_id) do update
set role = excluded.role, status = excluded.status;

insert into public.quote_requests (
  id, record_classification, request_kind, website_type, budget, timing,
  name, company, email, phone, description, privacy_consent, status
) values (
  '2c120000-0000-4000-8000-000000000001', 'production', 'website', 'business',
  'EUR 3.200 t/m EUR 6.000', 'flexible', 'Step 2I Fixture', 'Step 2I Company',
  'step-2i-fixture@example.test', null, 'Request projection fixture.', true, 'approved'
);

select set_config('request.jwt.claims', '{"role":"authenticated","aal":"aal1"}', true);
set local role authenticated;
select throws_ok(
  $$select public.get_operator_submitted_application_request_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2c120000-0000-4000-8000-000000000001'
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
    public.get_operator_submitted_application_request_v1(
      'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
      '2c120000-0000-4000-8000-000000000001'
    )
  ) as key),
  array['application_reference','budget','company','email','id','name','phone','record_classification','timing','website_type']::text[],
  'OP-01 receives exactly the ten allowlisted request fields'
);
select throws_ok(
  $$select public.get_operator_submitted_application_request_v1(
    'bd2ab636-0d42-4069-88a9-60bd97f2b335',
    '2c120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'OPERATOR_IDENTITY_MISMATCH',
  'OP-01 cannot substitute the OP-02 UUID'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"bd2ab636-0d42-4069-88a9-60bd97f2b335","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.get_operator_submitted_application_request_v1(
    'bd2ab636-0d42-4069-88a9-60bd97f2b335',
    '2c120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'APPLICATION_SCOPE_DENIED',
  'OP-02 keeps the existing application-scope denial'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"d0247fd9-60d5-40bc-a905-6b02024b6420","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.get_operator_submitted_application_request_v1(
    'd0247fd9-60d5-40bc-a905-6b02024b6420',
    '2c120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'UNKNOWN_OPERATOR',
  'OP-03 keeps the existing unknown-operator denial'
);
reset role;

set local role service_role;
select throws_ok(
  $$select public.get_operator_submitted_application_request_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2c120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'permission denied for function get_operator_submitted_application_request_v1',
  'service-role transport cannot execute the request projection'
);
reset role;

set local role anon;
select throws_ok(
  $$select public.get_operator_submitted_application_request_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2c120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'permission denied for function get_operator_submitted_application_request_v1',
  'anonymous transport cannot execute the request projection'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select is(
  public.get_operator_submitted_application_request_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2c120000-0000-4000-8000-000000000099'
  ),
  null,
  'missing request preserves the existing null read behavior'
);
reset role;

select * from finish();
rollback;