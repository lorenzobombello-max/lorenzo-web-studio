begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(6);

select ok(
  has_function_privilege('authenticated', 'public.get_operator_dossier_facets_v2(uuid,text,text,text,text)', 'execute')
  and not has_function_privilege('service_role', 'public.get_operator_dossier_facets_v2(uuid,text,text,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.get_operator_dossier_facets_v2(uuid,text,text,text,text)', 'execute'),
  'dossier facets are executable only through authenticated caller authority'
);

select ok(
  pg_get_functiondef('public.get_operator_dossier_facets_v2(uuid,text,text,text,text)'::regprocedure)
    like '%auth.uid() <> p_actor_auth_user_id%',
  'dossier facets bind the requested operator UUID to auth.uid()'
);

insert into auth.users (id, email) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'step-2e-owner@example.test'),
  ('bd2ab636-0d42-4069-88a9-60bd97f2b335', 'step-2e-operator-two@example.test'),
  ('d0247fd9-60d5-40bc-a905-6b02024b6420', 'step-2e-operator-three@example.test')
on conflict (id) do nothing;

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'Step 2E Owner', 'owner', 'ACTIVE'),
  ('bd2ab636-0d42-4069-88a9-60bd97f2b335', 'bd2ab636-0d42-4069-88a9-60bd97f2b335', 'Step 2E Operator Two', 'operator', 'ACTIVE'),
  ('d0247fd9-60d5-40bc-a905-6b02024b6420', 'd0247fd9-60d5-40bc-a905-6b02024b6420', 'Step 2E Operator Three', 'operator', 'ACTIVE')
on conflict (auth_user_id) do update
set role = excluded.role, status = excluded.status;

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select lives_ok(
  $$select public.get_operator_dossier_facets_v2('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'ACTIVE', null, null, null)$$,
  'authorized OP-01 caller can read dossier facets'
);
select throws_ok(
  $$select public.get_operator_dossier_facets_v2('bd2ab636-0d42-4069-88a9-60bd97f2b335', 'ACTIVE', null, null, null)$$,
  '42501', 'OPERATOR_IDENTITY_MISMATCH',
  'authenticated caller cannot substitute another operator UUID'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"bd2ab636-0d42-4069-88a9-60bd97f2b335","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.get_operator_dossier_facets_v2('bd2ab636-0d42-4069-88a9-60bd97f2b335', 'ACTIVE', null, null, null)$$,
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
  $$select public.get_operator_dossier_facets_v2('d0247fd9-60d5-40bc-a905-6b02024b6420', 'ACTIVE', null, null, null)$$,
  '42501', 'APPLICATION_SCOPE_DENIED',
  'OP-03 keeps the existing application-scope denial'
);
reset role;

select * from finish();
rollback;