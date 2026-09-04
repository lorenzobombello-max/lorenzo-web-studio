begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(26);

select has_table('lws_internal', 'operator_dossier_seen_states', 'private per-operator dossier seen state exists');
select has_function('public', 'mark_operator_dossier_seen_v1', array['uuid','uuid'], 'seen write RPC exists');
select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class where oid = 'lws_internal.operator_dossier_seen_states'::regclass),
  'seen state enforces RLS'
);
select ok(
  has_function_privilege('service_role', 'public.mark_operator_dossier_seen_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.mark_operator_dossier_seen_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.mark_operator_dossier_seen_v1(uuid,uuid)', 'execute')
  and not has_table_privilege('service_role', 'lws_internal.operator_dossier_seen_states', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'lws_internal.operator_dossier_seen_states', 'select,insert,update,delete'),
  'only the service transport enters seen authority and runtime roles cannot access its table'
);
select is(
  (select confdeltype::text from pg_constraint
   where conrelid = 'lws_internal.operator_dossier_seen_states'::regclass
     and confrelid = 'public.quote_requests'::regclass),
  'c', 'permanent dossier deletion cascades mutable seen state'
);
select ok(
  pg_get_functiondef('public.mark_operator_dossier_seen_v1(uuid,uuid)'::regprocedure)
    like '%assert_operator_application_actor_v2(p_actor_auth_user_id)%',
  'seen write revalidates the server-derived human actor'
);
select ok(
  pg_get_functiondef('public.list_operator_applications_v2(uuid,text,text,integer,text,text,text,timestamptz,uuid,integer)'::regprocedure)
    like '%project_operator_dossier_seen_v1%',
  'submitted Dossiers workqueue projects per-operator seen state'
);
select ok(
  pg_get_functiondef('public.list_operator_pending_intakes_v1(uuid,text)'::regprocedure)
    like '%project_operator_dossier_seen_v1%',
  'Website pending workqueue projects per-operator seen state'
);
select ok(
  pg_get_functiondef('public.list_operator_pending_sdf_intakes_v1(uuid)'::regprocedure)
    like '%project_operator_dossier_seen_v1%',
  'SDF pending workqueue projects per-operator seen state'
);

insert into auth.users (id, email) values
  ('db100000-0000-4000-8000-000000000001', 'seen-owner-one@example.test'),
  ('db100000-0000-4000-8000-000000000002', 'seen-owner-two@example.test'),
  ('db100000-0000-4000-8000-000000000003', 'seen-operator@example.test');
insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values
  ('db110000-0000-4000-8000-000000000001', 'db100000-0000-4000-8000-000000000001', 'Seen Owner One', 'owner', 'ACTIVE'),
  ('db110000-0000-4000-8000-000000000002', 'db100000-0000-4000-8000-000000000002', 'Seen Owner Two', 'owner', 'ACTIVE'),
  ('db110000-0000-4000-8000-000000000003', 'db100000-0000-4000-8000-000000000003', 'Seen Operator', 'operator', 'ACTIVE');

insert into public.quote_requests (
  id, record_classification, request_kind, website_type, budget, timing,
  name, company, email, description, privacy_consent, status
) values (
  'db120000-0000-4000-8000-000000000001', 'production', 'website', 'business',
  'EUR 3.200 t/m EUR 6.000', 'flexible', 'Seen Fixture', 'Seen Company',
  'seen-fixture@example.test', 'Dossiers seen-state fixture.', true, 'approved'
);

select set_config('request.jwt.claim.sub', 'db100000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select public.list_operator_applications_v2('db100000-0000-4000-8000-000000000001')$$,
  'submitted Dossiers list is read-only through caller JWT'
);
reset role;

select set_config('request.jwt.claim.sub', 'db100000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select public.list_operator_pending_intakes_v1('db100000-0000-4000-8000-000000000001', 'ACTIVE')$$,
  'Website pending list is read-only through caller JWT'
);
select lives_ok(
  $$select public.list_operator_pending_sdf_intakes_v1('db100000-0000-4000-8000-000000000001')$$,
  'SDF pending list is read-only through caller JWT'
);
reset role;

select is(
  (select count(*)::integer from lws_internal.operator_dossier_seen_states),
  0, 'list and refresh calls never create seen state'
);
set local role service_role;
select throws_ok(
  $$select public.mark_operator_dossier_seen_v1(
    'db100000-0000-4000-8000-000000000003', 'db120000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'APPLICATION_SCOPE_DENIED', 'unauthorized operator cannot write seen state'
);
select throws_ok(
  $$select public.mark_operator_dossier_seen_v1(
    'db100000-0000-4000-8000-000000000001', 'db120000-0000-4000-8000-000000000099'
  )$$,
  'P0001', 'DOSSIER_NOT_FOUND', 'missing dossier fails closed'
);
select lives_ok(
  $$select public.mark_operator_dossier_seen_v1(
    'db100000-0000-4000-8000-000000000001', 'db120000-0000-4000-8000-000000000001'
  )$$,
  'first owner marks an authoritative dossier seen'
);
reset role;

select is(
  (select count(*)::integer from lws_internal.operator_dossier_seen_states
   where operator_id = 'db110000-0000-4000-8000-000000000001'),
  1, 'first owner seen state persists'
);
select ok(
  (lws_internal.project_operator_dossier_seen_v1(
    jsonb_build_object('items', jsonb_build_array(jsonb_build_object(
      'quote_request_id', 'db120000-0000-4000-8000-000000000001'
    ))),
    'db100000-0000-4000-8000-000000000001'
  )->'items'->0->>'seen_at') is not null,
  'first owner sees the dossier as seen'
);
select is(
  lws_internal.project_operator_dossier_seen_v1(
    jsonb_build_object('items', jsonb_build_array(jsonb_build_object(
      'quote_request_id', 'db120000-0000-4000-8000-000000000001'
    ))),
    'db100000-0000-4000-8000-000000000002'
  )->'items'->0->>'seen_at',
  null, 'second owner still sees the same dossier as new'
);

set local role service_role;
select lives_ok(
  $$select public.mark_operator_dossier_seen_v1(
    'db100000-0000-4000-8000-000000000002', 'db120000-0000-4000-8000-000000000001'
  )$$,
  'second owner independently marks the same dossier seen'
);
reset role;

select is(
  (select count(distinct operator_id)::integer from lws_internal.operator_dossier_seen_states
   where quote_request_id = 'db120000-0000-4000-8000-000000000001'),
  2, 'seen state is keyed by operator identity'
);

create temporary table seen_snapshot as
select first_seen_at, seen_at
from lws_internal.operator_dossier_seen_states
where quote_request_id = 'db120000-0000-4000-8000-000000000001'
  and operator_id = 'db110000-0000-4000-8000-000000000001';

set local role service_role;
select lives_ok(
  $$select public.mark_operator_dossier_seen_v1(
    'db100000-0000-4000-8000-000000000001', 'db120000-0000-4000-8000-000000000001'
  )$$,
  'a later intentional open refreshes seen state idempotently'
);
reset role;

select is(
  (select current.first_seen_at
   from lws_internal.operator_dossier_seen_states current
   where current.quote_request_id = 'db120000-0000-4000-8000-000000000001'
     and current.operator_id = 'db110000-0000-4000-8000-000000000001'),
  (select first_seen_at from seen_snapshot),
  'later opens preserve first-seen time'
);
select ok(
  (select current.seen_at >= snapshot.seen_at
   from lws_internal.operator_dossier_seen_states current
   cross join seen_snapshot snapshot
   where current.quote_request_id = 'db120000-0000-4000-8000-000000000001'
     and current.operator_id = 'db110000-0000-4000-8000-000000000001'),
  'latest-seen time remains monotonic'
);
select is(
  (select count(*)::integer from lws_internal.operator_dossier_seen_states
   where quote_request_id = 'db120000-0000-4000-8000-000000000001'),
  2, 'repeat opens do not duplicate per-operator state'
);

select set_config('request.jwt.claim.sub', 'db100000-0000-4000-8000-000000000001', true);
set local role authenticated;
select is(
  public.can_purge_dossier_v1('db120000-0000-4000-8000-000000000001')->>'reason',
  'DOSSIER_NOT_TRASHED', 'current-main Trash-first delete authority remains intact'
);
reset role;

select * from finish();
rollback;