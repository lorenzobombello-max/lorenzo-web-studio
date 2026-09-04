begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(6);

select ok(
  has_function_privilege('authenticated', 'public.count_operator_active_pending_intakes_v1(uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.count_operator_active_pending_intakes_v1(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.count_operator_active_pending_intakes_v1(uuid)', 'execute'),
  'active pending-intake count is executable only through authenticated caller authority'
);

select ok(
  pg_get_functiondef('public.count_operator_active_pending_intakes_v1(uuid)'::regprocedure)
    like '%auth.uid() <> p_actor_auth_user_id%',
  'active pending-intake count binds the requested operator UUID to auth.uid()'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select lives_ok(
  $$select public.count_operator_active_pending_intakes_v1('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0')$$,
  'authorized OP-01 caller can read the active pending-intake count'
);
select throws_ok(
  $$select public.count_operator_active_pending_intakes_v1('bd2ab636-0d42-4069-88a9-60bd97f2b335')$$,
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
  $$select public.count_operator_active_pending_intakes_v1('bd2ab636-0d42-4069-88a9-60bd97f2b335')$$,
  '42501', 'APPLICATION_SCOPE_DENIED',
  'OP-02 keeps the existing application-scope denial'
);
reset role;

insert into auth.users (id, email)
values ('d0247fd9-60d5-40bc-a905-6b02024b6420', 'operator-three@example.test')
on conflict (id) do nothing;
insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values (
  'd0247fd9-60d5-40bc-a905-6b02024b6420',
  'd0247fd9-60d5-40bc-a905-6b02024b6420',
  'Operator Three', 'operator', 'ACTIVE'
)
on conflict (auth_user_id) do update
set role = excluded.role, status = excluded.status;

select set_config(
  'request.jwt.claims',
  '{"sub":"d0247fd9-60d5-40bc-a905-6b02024b6420","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.count_operator_active_pending_intakes_v1('d0247fd9-60d5-40bc-a905-6b02024b6420')$$,
  '42501', 'APPLICATION_SCOPE_DENIED',
  'OP-03 keeps the existing application-scope denial'
);
reset role;

select * from finish();
rollback;