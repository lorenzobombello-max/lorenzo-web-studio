begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(14);

select has_function(
  'public', 'get_current_operator_identity_v1', array[]::text[],
  'current operator identity projection exists'
);
select ok(
  has_function_privilege('authenticated', 'public.get_current_operator_identity_v1()', 'execute')
  and not has_function_privilege('anon', 'public.get_current_operator_identity_v1()', 'execute')
  and not has_function_privilege('service_role', 'public.get_current_operator_identity_v1()', 'execute'),
  'only authenticated callers can execute the identity projection'
);
select ok(
  not has_table_privilege('authenticated', 'public.commercial_operators', 'select,insert,update,delete'),
  'identity projection grants no direct commercial operator table privileges'
);

insert into auth.users(id, email) values
  ('a9000000-0000-4000-8000-000000000001', 'identity-owner@example.test'),
  ('a9000000-0000-4000-8000-000000000002', 'identity-manager@example.test'),
  ('a9000000-0000-4000-8000-000000000003', 'identity-operator@example.test'),
  ('a9000000-0000-4000-8000-000000000004', 'identity-reviewer@example.test'),
  ('a9000000-0000-4000-8000-000000000005', 'identity-read-only@example.test'),
  ('a9000000-0000-4000-8000-000000000006', 'identity-admin@example.test'),
  ('a9000000-0000-4000-8000-000000000007', 'identity-disabled@example.test'),
  ('a9000000-0000-4000-8000-000000000008', 'identity-revoked@example.test'),
  ('a9000000-0000-4000-8000-000000000010', 'identity-unknown@example.test');

insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status, revoked_at
) values
  ('a9010000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000001', 'Identity Owner', 'owner', 'ACTIVE', null),
  ('a9010000-0000-4000-8000-000000000002', 'a9000000-0000-4000-8000-000000000002', 'Identity Manager', 'operations_manager', 'ACTIVE', null),
  ('a9010000-0000-4000-8000-000000000003', 'a9000000-0000-4000-8000-000000000003', 'Identity Operator', 'operator', 'ACTIVE', null),
  ('a9010000-0000-4000-8000-000000000004', 'a9000000-0000-4000-8000-000000000004', 'Identity Reviewer', 'reviewer', 'ACTIVE', null),
  ('a9010000-0000-4000-8000-000000000005', 'a9000000-0000-4000-8000-000000000005', 'Identity Read Only', 'read_only', 'ACTIVE', null),
  ('a9010000-0000-4000-8000-000000000006', 'a9000000-0000-4000-8000-000000000006', 'Identity Admin', 'admin', 'ACTIVE', null),
  ('a9010000-0000-4000-8000-000000000007', 'a9000000-0000-4000-8000-000000000007', 'Identity Disabled', 'operator', 'DISABLED', null),
  ('a9010000-0000-4000-8000-000000000008', 'a9000000-0000-4000-8000-000000000008', 'Identity Revoked', 'operator', 'REVOKED', clock_timestamp());

create function pg_temp.identity_for(p_subject uuid)
returns jsonb
language plpgsql
as $$
declare
  v_identity jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_subject::text, true);
  select public.get_current_operator_identity_v1() into v_identity;
  return v_identity;
end;
$$;

select is(pg_temp.identity_for('a9000000-0000-4000-8000-000000000001')->>'role', 'owner', 'owner identity is caller-bound');
select is(pg_temp.identity_for('a9000000-0000-4000-8000-000000000002')->>'role', 'operations_manager', 'operations manager identity is caller-bound');
select is(pg_temp.identity_for('a9000000-0000-4000-8000-000000000003')->>'role', 'operator', 'operator identity is caller-bound');
select is(pg_temp.identity_for('a9000000-0000-4000-8000-000000000004')->>'role', 'reviewer', 'reviewer identity is caller-bound');
select is(pg_temp.identity_for('a9000000-0000-4000-8000-000000000005')->>'role', 'read_only', 'read only identity is caller-bound');
select is(pg_temp.identity_for('a9000000-0000-4000-8000-000000000006')->>'role', 'admin', 'admin identity is caller-bound');
select is(
  pg_temp.identity_for('a9000000-0000-4000-8000-000000000003'),
  jsonb_build_object('display_name', 'Identity Operator', 'role', 'operator', 'status', 'ACTIVE'),
  'identity projection exposes only presentation fields'
);

select throws_ok(
  $$select pg_temp.identity_for('a9000000-0000-4000-8000-000000000007')$$,
  '42501', 'OPERATOR_DISABLED', 'disabled operator is denied'
);
select throws_ok(
  $$select pg_temp.identity_for('a9000000-0000-4000-8000-000000000008')$$,
  '42501', 'OPERATOR_REVOKED', 'revoked operator is denied'
);
select throws_ok(
  $$select pg_temp.identity_for('a9000000-0000-4000-8000-000000000010')$$,
  '42501', 'UNKNOWN_OPERATOR', 'unknown authenticated user is denied'
);
select throws_ok(
  $$select set_config('request.jwt.claim.sub', '', true); select public.get_current_operator_identity_v1()$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'anonymous caller is denied'
);

select * from finish();
rollback;