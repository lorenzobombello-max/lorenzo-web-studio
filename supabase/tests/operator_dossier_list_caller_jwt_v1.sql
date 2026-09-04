begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(6);

select ok(
  has_function_privilege('authenticated', 'public.list_operator_applications_v2(uuid,text,text,integer,text,text,text,timestamp with time zone,uuid,integer)', 'execute')
  and not has_function_privilege('service_role', 'public.list_operator_applications_v2(uuid,text,text,integer,text,text,text,timestamp with time zone,uuid,integer)', 'execute')
  and not has_function_privilege('anon', 'public.list_operator_applications_v2(uuid,text,text,integer,text,text,text,timestamp with time zone,uuid,integer)', 'execute'),
  'v2 dossier list is executable only through authenticated caller authority'
);

select ok(
  pg_get_functiondef('public.list_operator_applications_v2(uuid,text,text,integer,text,text,text,timestamptz,uuid,integer)'::regprocedure)
    like '%auth.uid() <> p_actor_auth_user_id%',
  'v2 dossier list binds the requested operator UUID to auth.uid()'
);

insert into auth.users (id, email) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'step-2f-owner@example.test'),
  ('bd2ab636-0d42-4069-88a9-60bd97f2b335', 'step-2f-operator-two@example.test'),
  ('d0247fd9-60d5-40bc-a905-6b02024b6420', 'step-2f-operator-three@example.test')
on conflict (id) do nothing;

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'Step 2F Owner', 'owner', 'ACTIVE'),
  ('bd2ab636-0d42-4069-88a9-60bd97f2b335', 'bd2ab636-0d42-4069-88a9-60bd97f2b335', 'Step 2F Operator Two', 'operator', 'ACTIVE'),
  ('d0247fd9-60d5-40bc-a905-6b02024b6420', 'd0247fd9-60d5-40bc-a905-6b02024b6420', 'Step 2F Operator Three', 'operator', 'ACTIVE')
on conflict (auth_user_id) do update
set role = excluded.role, status = excluded.status;

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select lives_ok(
  $$select public.list_operator_applications_v2('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0')$$,
  'authorized OP-01 caller can read the v2 dossier list'
);
select throws_ok(
  $$select public.list_operator_applications_v2('bd2ab636-0d42-4069-88a9-60bd97f2b335')$$,
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
  $$select public.list_operator_applications_v2('bd2ab636-0d42-4069-88a9-60bd97f2b335')$$,
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
  $$select public.list_operator_applications_v2('d0247fd9-60d5-40bc-a905-6b02024b6420')$$,
  '42501', 'APPLICATION_SCOPE_DENIED',
  'OP-03 keeps the existing application-scope denial'
);
reset role;

select * from finish();
rollback;