begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(10);

select ok(
  has_function_privilege('authenticated', 'public.get_operator_dossier_substance_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.get_operator_dossier_substance_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.get_operator_dossier_substance_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'lws_internal.get_operator_dossier_substance_v1_core(uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'lws_internal.get_operator_dossier_substance_v1_core(uuid,uuid)', 'execute'),
  'only authenticated callers can execute the public substance wrapper and the core remains private'
);

select ok(
  pg_get_functiondef('public.get_operator_dossier_substance_v1(uuid,uuid)'::regprocedure)
    like '%auth.uid() <> p_actor_auth_user_id%',
  'dossier substance binds the requested operator UUID to auth.uid()'
);

insert into auth.users (id, email) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'step-2g-owner@example.test'),
  ('bd2ab636-0d42-4069-88a9-60bd97f2b335', 'step-2g-operator-two@example.test'),
  ('d0247fd9-60d5-40bc-a905-6b02024b6420', 'step-2g-operator-three@example.test')
on conflict (id) do nothing;

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values
  ('2a110000-0000-4000-8000-000000000001', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'Step 2G Owner', 'owner', 'ACTIVE'),
  ('2a110000-0000-4000-8000-000000000002', 'bd2ab636-0d42-4069-88a9-60bd97f2b335', 'Step 2G Operator Two', 'operator', 'ACTIVE')
on conflict (auth_user_id) do update
set role = excluded.role, status = excluded.status;

insert into public.quote_requests (
  id, record_classification, request_kind, name, company, email, phone,
  website_type, budget, timing, description, privacy_consent, status
) values (
  '2a120000-0000-4000-8000-000000000001', 'production', 'website',
  'Step 2G Customer', null, 'step-2g-customer@example.test', null,
  'Website op maat', 'EUR 3.000', 'flexible', 'Sensitive request fixture', true, 'approved'
);

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  business_description
) values (
  '2a130000-0000-4000-8000-000000000001',
  '2a120000-0000-4000-8000-000000000001',
  'invited', repeat('a', 64), '2099-01-01T00:00:00Z', 'Sensitive intake fixture'
);

select set_config('request.jwt.claims', '{"role":"authenticated","aal":"aal1"}', true);
set local role authenticated;
select throws_ok(
  $$select public.get_operator_dossier_substance_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2a120000-0000-4000-8000-000000000001'
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
select lives_ok(
  $$select public.get_operator_dossier_substance_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2a120000-0000-4000-8000-000000000001'
  )$$,
  'authorized OP-01 caller can read dossier substance'
);
select ok(
  (select array_agg(key order by key) from jsonb_object_keys(public.get_operator_dossier_substance_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2a120000-0000-4000-8000-000000000001'
  )) as key) = array['customer', 'documents', 'intake', 'quote_request_id', 'request', 'request_kind']::text[]
  and (select array_agg(key order by key) from jsonb_object_keys(public.get_operator_dossier_substance_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2a120000-0000-4000-8000-000000000001'
  ) -> 'customer') as key) = array['company', 'email', 'name', 'phone']::text[]
  and (select array_agg(key order by key) from jsonb_object_keys(public.get_operator_dossier_substance_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2a120000-0000-4000-8000-000000000001'
  ) -> 'documents') as key) = array['customer_request_count', 'uploaded_document_count']::text[],
  'authenticated response preserves the exact closed root, customer, and document-count projection'
);
select throws_ok(
  $$select public.get_operator_dossier_substance_v1(
    'bd2ab636-0d42-4069-88a9-60bd97f2b335',
    '2a120000-0000-4000-8000-000000000001'
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
  $$select public.get_operator_dossier_substance_v1(
    'bd2ab636-0d42-4069-88a9-60bd97f2b335',
    '2a120000-0000-4000-8000-000000000001'
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
  $$select public.get_operator_dossier_substance_v1(
    'd0247fd9-60d5-40bc-a905-6b02024b6420',
    '2a120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'UNKNOWN_OPERATOR',
  'OP-03 keeps the existing unknown-operator denial'
);
reset role;

set local role service_role;
select throws_ok(
  $$select public.get_operator_dossier_substance_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2a120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'permission denied for function get_operator_dossier_substance_v1',
  'service-role transport cannot execute dossier substance'
);
reset role;

set local role anon;
select throws_ok(
  $$select public.get_operator_dossier_substance_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2a120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'permission denied for function get_operator_dossier_substance_v1',
  'anonymous transport cannot execute dossier substance'
);
reset role;

select * from finish();
rollback;