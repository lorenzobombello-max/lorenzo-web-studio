begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('lws_internal', 'security_action_policy', 'central action policy exists');
select has_table('lws_internal', 'security_kill_switch', 'central kill switches exist');
select has_table('lws_internal', 'security_control_events', 'security control audit exists');

select is(
  (select count(*)::integer from lws_internal.security_kill_switch),
  7,
  'all required kill-switch scopes are bootstrapped'
);
select is(
  (select count(*)::integer from lws_internal.security_kill_switch where is_active),
  0,
  'kill switches are inactive by default'
);
select is(
  (select count(*)::integer from lws_internal.security_action_policy where risk_level in ('HIGH', 'CRITICAL')),
  25,
  'audited HIGH and CRITICAL policies are bootstrapped without wiring'
);

insert into auth.users(id, email)
values
  ('f3000000-0000-4000-8000-000000000001', 'security-owner@example.test'),
  ('f3000000-0000-4000-8000-000000000002', 'security-operator@example.test');

set local session_replication_role = replica;
insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status)
values
  ('f3010000-0000-4000-8000-000000000001', 'f3000000-0000-4000-8000-000000000001', 'Synthetic Security Owner', 'owner', 'ACTIVE'),
  ('f3010000-0000-4000-8000-000000000002', 'f3000000-0000-4000-8000-000000000002', 'Synthetic Security Operator', 'operator', 'ACTIVE');
set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub', 'f3000000-0000-4000-8000-000000000002', 'role', 'authenticated', 'aal', 'aal2')::text,
  true
);
select throws_ok(
  $$select public.set_security_kill_switch_v1('GLOBAL', true, 'Unauthorized test')$$,
  '42501',
  'SECURITY_CONTROL_OWNER_REQUIRED',
  'non-owner cannot activate a kill switch'
);
select throws_ok(
  $$select public.upsert_security_action_policy_v1('synthetic_action', 'PURGE', 'HIGH', true, true, false, 1, 1, 0)$$,
  '42501',
  'SECURITY_CONTROL_OWNER_REQUIRED',
  'non-owner cannot mutate policy'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub', 'f3000000-0000-4000-8000-000000000001', 'role', 'authenticated', 'aal', 'aal1')::text,
  true
);
select throws_ok(
  $$select public.set_security_kill_switch_v1('GLOBAL', true, 'AAL1 test')$$,
  '42501',
  'AAL2_REQUIRED',
  'owner at AAL1 cannot write security controls'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub', 'f3000000-0000-4000-8000-000000000001', 'role', 'authenticated', 'aal', 'aal2')::text,
  true
);
select lives_ok(
  $$select public.upsert_security_action_policy_v1('synthetic_read_only', 'PURGE', 'READ_ONLY', true, false, false, null, null, null)$$,
  'AAL2 owner can write a transaction-local policy fixture'
);
select lives_ok(
  $$select public.set_security_kill_switch_v1('GLOBAL', true, 'Transaction-local global test')$$,
  'AAL2 owner can activate a kill switch in the transaction'
);
select is(
  (select reason_code from lws_internal.evaluate_security_action_v1('purge_dossier_v1')),
  'GLOBAL_KILL_SWITCH_ACTIVE',
  'GLOBAL active blocks a registered destructive mutation'
);
select ok(
  (select allowed from lws_internal.evaluate_security_action_v1('synthetic_read_only')),
  'read-only classification remains allowed while GLOBAL is active'
);
select lives_ok(
  $$select public.set_security_kill_switch_v1('GLOBAL', false, 'Release transaction-local global test')$$,
  'AAL2 owner can release the global switch'
);
select lives_ok(
  $$select public.set_security_kill_switch_v1('PURGE', true, 'Transaction-local purge test')$$,
  'AAL2 owner can activate the PURGE switch'
);
select is(
  (select reason_code from lws_internal.evaluate_security_action_v1('purge_sdf_dossier_v1')),
  'DOMAIN_KILL_SWITCH_ACTIVE',
  'PURGE active blocks a purge-domain action'
);
select ok(
  (select allowed from lws_internal.evaluate_security_action_v1('confirm_payment')),
  'PURGE active does not block a finance-domain action'
);
select is(
  (select reason_code from lws_internal.evaluate_security_action_v1('unknown_destructive_action')),
  'SECURITY_ACTION_NOT_REGISTERED',
  'unknown action evaluation fails closed'
);

select throws_ok(
  $$update lws_internal.security_control_events set metadata = '{}'::jsonb$$,
  '55000',
  'SECURITY_CONTROL_EVENT_APPEND_ONLY',
  'security control events cannot be updated'
);
select throws_ok(
  $$delete from lws_internal.security_control_events$$,
  '55000',
  'SECURITY_CONTROL_EVENT_APPEND_ONLY',
  'security control events cannot be deleted'
);
select ok(
  exists (
    select 1
    from lws_internal.security_control_events
    where actor_auth_user_id = 'f3000000-0000-4000-8000-000000000001'
      and event_type = 'SWITCH_ACTIVATED'
  )
  and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'lws_internal'
      and table_name = 'security_control_events'
      and column_name like '%display_name%'
  ),
  'events bind authority to actor UUID and contain no display-name authority'
);

select ok(
  (select proconfig @> array['search_path=public, lws_internal, auth, pg_catalog']
   from pg_proc where oid = 'public.set_security_kill_switch_v1(text,boolean,text)'::regprocedure)
  and
  (select proconfig @> array['search_path=lws_internal, pg_catalog']
   from pg_proc where oid = 'lws_internal.evaluate_security_action_v1(text)'::regprocedure),
  'SECURITY DEFINER functions have fixed search paths'
);
select ok(
  not has_function_privilege('anon', 'public.set_security_kill_switch_v1(text,boolean,text)', 'execute')
  and not has_function_privilege('service_role', 'public.set_security_kill_switch_v1(text,boolean,text)', 'execute')
  and has_function_privilege('authenticated', 'public.set_security_kill_switch_v1(text,boolean,text)', 'execute')
  and not has_function_privilege('anon', 'lws_internal.evaluate_security_action_v1(text)', 'execute')
  and not has_function_privilege('authenticated', 'lws_internal.evaluate_security_action_v1(text)', 'execute')
  and has_function_privilege('service_role', 'lws_internal.evaluate_security_action_v1(text)', 'execute'),
  'privileged control RPCs and private evaluation expose only their intended roles'
);
select ok(
  not exists (
    select 1
    from pg_proc as procedure
    cross join lateral aclexplode(procedure.proacl) as privilege
    where procedure.oid = 'public.set_security_kill_switch_v1(text,boolean,text)'::regprocedure
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC has no execute privilege on privileged control RPCs'
);

select * from finish();
rollback;