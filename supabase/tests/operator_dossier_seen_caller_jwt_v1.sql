begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(14);

select ok(
  has_function_privilege('authenticated', 'public.mark_operator_dossier_seen_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.mark_operator_dossier_seen_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.mark_operator_dossier_seen_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'lws_internal.mark_operator_dossier_seen_v1_core(uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'lws_internal.mark_operator_dossier_seen_v1_core(uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'lws_internal.mark_operator_dossier_seen_v1_core(uuid,uuid)', 'execute'),
  'only authenticated callers can execute the public seen wrapper and the core remains private'
);

select ok(
  pg_get_functiondef('public.mark_operator_dossier_seen_v1(uuid,uuid)'::regprocedure)
    like '%auth.uid() <> p_actor_auth_user_id%',
  'seen mutation binds the requested operator UUID to auth.uid()'
);

insert into auth.users (id, email) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'step-2h-owner@example.test'),
  ('bd2ab636-0d42-4069-88a9-60bd97f2b335', 'step-2h-operator-two@example.test'),
  ('d0247fd9-60d5-40bc-a905-6b02024b6420', 'step-2h-operator-three@example.test')
on conflict (id) do nothing;

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values
  ('2b110000-0000-4000-8000-000000000001', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'Step 2H Owner', 'owner', 'ACTIVE'),
  ('2b110000-0000-4000-8000-000000000002', 'bd2ab636-0d42-4069-88a9-60bd97f2b335', 'Step 2H Operator Two', 'operator', 'ACTIVE')
on conflict (auth_user_id) do update
set role = excluded.role, status = excluded.status;

insert into public.quote_requests (
  id, record_classification, request_kind, website_type, budget, timing,
  name, company, email, description, privacy_consent, status
) values (
  '2b120000-0000-4000-8000-000000000001', 'production', 'website', 'business',
  'EUR 3.200 t/m EUR 6.000', 'flexible', 'Step 2H Fixture', 'Step 2H Company',
  'step-2h-fixture@example.test', 'Dossiers seen caller-JWT fixture.', true, 'approved'
);

create temporary table step_2h_business_snapshot as
select
  to_jsonb(request) as request_row,
  (select to_jsonb(state) from lws_internal.operator_dossier_states as state
   where state.quote_request_id = request.id) as dossier_state_row
from public.quote_requests as request
where request.id = '2b120000-0000-4000-8000-000000000001';

select set_config('request.jwt.claims', '{"role":"authenticated","aal":"aal1"}', true);
set local role authenticated;
select throws_ok(
  $$select public.mark_operator_dossier_seen_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2b120000-0000-4000-8000-000000000001'
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
  $$select public.mark_operator_dossier_seen_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2b120000-0000-4000-8000-000000000001'
  )$$,
  'authorized OP-01 caller can mark the dossier seen'
);
select throws_ok(
  $$select public.mark_operator_dossier_seen_v1(
    'bd2ab636-0d42-4069-88a9-60bd97f2b335',
    '2b120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'OPERATOR_IDENTITY_MISMATCH',
  'OP-01 cannot substitute the OP-02 UUID'
);
reset role;

select is(
  (select count(*)::integer from lws_internal.operator_dossier_seen_states
   where quote_request_id = '2b120000-0000-4000-8000-000000000001'),
  1, 'authorized write creates only the intended per-operator seen row'
);
select is(
  (select to_jsonb(request) from public.quote_requests as request
   where request.id = '2b120000-0000-4000-8000-000000000001'),
  (select request_row from step_2h_business_snapshot),
  'seen mutation does not alter dossier content or request lifecycle fields'
);
select is(
  (select to_jsonb(state) from lws_internal.operator_dossier_states as state
   where state.quote_request_id = '2b120000-0000-4000-8000-000000000001'),
  (select dossier_state_row from step_2h_business_snapshot),
  'seen mutation does not alter dossier state or revision data'
);

create temporary table step_2h_seen_snapshot as
select first_seen_at, seen_at
from lws_internal.operator_dossier_seen_states
where quote_request_id = '2b120000-0000-4000-8000-000000000001';

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select lives_ok(
  $$select public.mark_operator_dossier_seen_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2b120000-0000-4000-8000-000000000001'
  )$$,
  'repeat open remains idempotent'
);
reset role;

select ok(
  (select current.first_seen_at = snapshot.first_seen_at
     and current.seen_at >= snapshot.seen_at
     and (select count(*) from lws_internal.operator_dossier_seen_states
          where quote_request_id = '2b120000-0000-4000-8000-000000000001') = 1
   from lws_internal.operator_dossier_seen_states as current
   cross join step_2h_seen_snapshot as snapshot
   where current.quote_request_id = '2b120000-0000-4000-8000-000000000001'),
  'repeat open preserves first-seen, refreshes latest-seen, and creates no duplicate'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"bd2ab636-0d42-4069-88a9-60bd97f2b335","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.mark_operator_dossier_seen_v1(
    'bd2ab636-0d42-4069-88a9-60bd97f2b335',
    '2b120000-0000-4000-8000-000000000001'
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
  $$select public.mark_operator_dossier_seen_v1(
    'd0247fd9-60d5-40bc-a905-6b02024b6420',
    '2b120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'UNKNOWN_OPERATOR',
  'OP-03 keeps the existing unknown-operator denial'
);
reset role;

set local role service_role;
select throws_ok(
  $$select public.mark_operator_dossier_seen_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2b120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'permission denied for function mark_operator_dossier_seen_v1',
  'service-role transport cannot execute the seen mutation'
);
reset role;

set local role anon;
select throws_ok(
  $$select public.mark_operator_dossier_seen_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2b120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'permission denied for function mark_operator_dossier_seen_v1',
  'anonymous transport cannot execute the seen mutation'
);
reset role;

select * from finish();
rollback;