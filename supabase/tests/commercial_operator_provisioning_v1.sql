begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public',
  'provision_commercial_operator_v1',
  array['uuid', 'text', 'text', 'text'],
  'owner-AAL2 commercial operator provisioning RPC exists'
);
select has_table(
  'lws_internal',
  'commercial_operator_provisioning_events',
  'dedicated provisioning audit authority exists'
);
select has_trigger(
  'public',
  'commercial_operators',
  'trg_commercial_operator_auth_uuid_binding_aal2',
  'existing Auth UUID AAL2 binding trigger remains present'
);
select is(
  (select tgenabled::text
   from pg_trigger
   where tgrelid = 'public.commercial_operators'::regclass
     and tgname = 'trg_commercial_operator_auth_uuid_binding_aal2'
     and not tgisinternal),
  'O',
  'existing Auth UUID AAL2 binding trigger remains enabled'
);
select has_trigger(
  'lws_internal',
  'commercial_operator_provisioning_events',
  'trg_commercial_operator_provisioning_events_append_only',
  'provisioning audit events are append-only'
);

select ok(
  not has_table_privilege('authenticated', 'public.commercial_operators', 'insert')
  and not has_table_privilege('anon', 'public.commercial_operators', 'insert')
  and not has_table_privilege('service_role', 'public.commercial_operators', 'insert'),
  'no API role receives direct commercial operator INSERT authority'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.provision_commercial_operator_v1(uuid,text,text,text)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.provision_commercial_operator_v1(uuid,text,text,text)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.provision_commercial_operator_v1(uuid,text,text,text)',
    'execute'
  ),
  'only authenticated callers can enter the provisioning RPC'
);
select ok(
  (select prosecdef
   from pg_proc
   where oid = 'public.provision_commercial_operator_v1(uuid,text,text,text)'::regprocedure)
  and
  (select proconfig @> array['search_path=public, lws_internal, auth, pg_catalog']
   from pg_proc
   where oid = 'public.provision_commercial_operator_v1(uuid,text,text,text)'::regprocedure),
  'provisioning RPC is SECURITY DEFINER with a fixed search path'
);
select ok(
  coalesce((select relrowsecurity and relforcerowsecurity
    from pg_class
    where oid = 'lws_internal.commercial_operator_provisioning_events'::regclass), false),
  'provisioning audit authority forces RLS'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'lws_internal.commercial_operator_provisioning_events',
    'select,insert,update,delete'
  )
  and not has_table_privilege(
    'service_role',
    'lws_internal.commercial_operator_provisioning_events',
    'select,insert,update,delete'
  ),
  'runtime roles cannot access provisioning audit storage directly'
);

insert into auth.users (id, email, email_confirmed_at) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'provision-owner@example.test', clock_timestamp()),
  ('bd2ab636-0d42-4069-88a9-60bd97f2b335', 'provision-admin@example.test', clock_timestamp()),
  ('ab120000-0000-4000-8000-000000000003', 'provision-read-only@example.test', clock_timestamp()),
  ('ab120000-0000-4000-8000-000000000005', 'provision-target@example.test', clock_timestamp()),
  ('ab120000-0000-4000-8000-000000000006', 'provision-unconfirmed@example.test', null),
  ('ab120000-0000-4000-8000-000000000007', 'provision-conflict@example.test', clock_timestamp())
on conflict (id) do update
set email = excluded.email,
    email_confirmed_at = excluded.email_confirmed_at;

set local session_replication_role = replica;
insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values
  ('ab121000-0000-4000-8000-000000000001', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'Provision Owner', 'owner', 'ACTIVE'),
  ('ab121000-0000-4000-8000-000000000002', 'bd2ab636-0d42-4069-88a9-60bd97f2b335', 'Provision Admin', 'admin', 'ACTIVE'),
  ('ab121000-0000-4000-8000-000000000003', 'ab120000-0000-4000-8000-000000000003', 'Provision Read Only', 'read_only', 'ACTIVE'),
  ('ab121000-0000-4000-8000-000000000007', 'ab120000-0000-4000-8000-000000000007', 'Existing Binding', 'operator', 'ACTIVE')
on conflict (auth_user_id) do update
set display_name = excluded.display_name,
    role = excluded.role,
    status = excluded.status;
set local session_replication_role = origin;

set local role authenticated;
select throws_ok(
  $$select public.provision_commercial_operator_v1(
    'ab120000-0000-4000-8000-000000000005', 'Target Admin', 'admin', 'ACTIVE'
  )$$,
  '42501', 'HUMAN_JWT_REQUIRED',
  'unauthenticated caller is denied'
);
reset role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'role', 'authenticated',
    'aal', 'aal1'
  )::text,
  true
);
set local role authenticated;
select throws_ok(
  $$select public.provision_commercial_operator_v1(
    'ab120000-0000-4000-8000-000000000005', 'Target Admin', 'admin', 'ACTIVE'
  )$$,
  '42501', 'AAL2_REQUIRED',
  'ACTIVE owner at AAL1 is denied'
);
reset role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'bd2ab636-0d42-4069-88a9-60bd97f2b335',
    'role', 'authenticated',
    'aal', 'aal2'
  )::text,
  true
);
set local role authenticated;
select throws_ok(
  $$select public.provision_commercial_operator_v1(
    'ab120000-0000-4000-8000-000000000005', 'Target Admin', 'admin', 'ACTIVE'
  )$$,
  '42501', 'PROVISIONING_OWNER_REQUIRED',
  'ACTIVE admin at AAL2 is denied'
);
reset role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'ab120000-0000-4000-8000-000000000003',
    'role', 'authenticated',
    'aal', 'aal2'
  )::text,
  true
);
set local role authenticated;
select throws_ok(
  $$select public.provision_commercial_operator_v1(
    'ab120000-0000-4000-8000-000000000005', 'Target Admin', 'admin', 'ACTIVE'
  )$$,
  '42501', 'MFA_OPERATOR_NOT_ELIGIBLE',
  'ACTIVE read-only operator at AAL2 is denied'
);
reset role;

update public.commercial_operators
set role = 'owner', status = 'DISABLED'
where auth_user_id = 'bd2ab636-0d42-4069-88a9-60bd97f2b335';
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'bd2ab636-0d42-4069-88a9-60bd97f2b335',
    'role', 'authenticated',
    'aal', 'aal2'
  )::text,
  true
);
set local role authenticated;
select throws_ok(
  $$select public.provision_commercial_operator_v1(
    'ab120000-0000-4000-8000-000000000005', 'Target Admin', 'admin', 'ACTIVE'
  )$$,
  '42501', 'OPERATOR_INACTIVE',
  'inactive owner is denied before provisioning'
);
reset role;
update public.commercial_operators
set role = 'admin', status = 'ACTIVE'
where auth_user_id = 'bd2ab636-0d42-4069-88a9-60bd97f2b335';

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'role', 'authenticated',
    'aal', 'aal2'
  )::text,
  true
);
set local role authenticated;

select throws_ok(
  $$select public.provision_commercial_operator_v1(
    'ab120000-0000-4000-8000-000000000099', 'Missing Target', 'admin', 'ACTIVE'
  )$$,
  '23503', 'TARGET_AUTH_USER_NOT_FOUND',
  'missing target Auth user is denied'
);
select throws_ok(
  $$select public.provision_commercial_operator_v1(
    'ab120000-0000-4000-8000-000000000006', 'Unconfirmed Target', 'admin', 'ACTIVE'
  )$$,
  '42501', 'TARGET_AUTH_EMAIL_NOT_CONFIRMED',
  'unconfirmed target Auth user is denied'
);
select throws_ok(
  $$select public.provision_commercial_operator_v1(
    'ab120000-0000-4000-8000-000000000007', 'Conflicting Binding', 'admin', 'ACTIVE'
  )$$,
  '23505', 'OPERATOR_BINDING_CONFLICT',
  'conflicting target binding is denied'
);
select throws_ok(
  $$select public.provision_commercial_operator_v1(
    'ab120000-0000-4000-8000-000000000005', 'Forbidden Owner', 'owner', 'ACTIVE'
  )$$,
  '22023', 'INVALID_OPERATOR_PROVISIONING_REQUEST',
  'provisioning cannot create another owner'
);
select throws_ok(
  $$select public.provision_commercial_operator_v1(
    'ab120000-0000-4000-8000-000000000005', 'Forbidden Manager', 'operations_manager', 'ACTIVE'
  )$$,
  '22023', 'INVALID_OPERATOR_PROVISIONING_REQUEST',
  'provisioning cannot bypass operations-manager appointment authority'
);
select throws_ok(
  $$insert into public.commercial_operators (
      auth_user_id, display_name, role, status
    ) values (
      'ab120000-0000-4000-8000-000000000005', 'Direct Insert', 'admin', 'ACTIVE'
    )$$,
  '42501', 'permission denied for table commercial_operators',
  'authenticated callers still cannot INSERT commercial operators directly'
);

select is(
  public.provision_commercial_operator_v1(
    'ab120000-0000-4000-8000-000000000005', 'Target Admin', 'admin', 'ACTIVE'
  )->>'replayed',
  'false',
  'ACTIVE owner at AAL2 provisions a confirmed target'
);
select is(
  public.provision_commercial_operator_v1(
    'ab120000-0000-4000-8000-000000000005', 'Target Admin', 'admin', 'ACTIVE'
  )->>'replayed',
  'true',
  'exact provisioning replay is idempotent'
);

reset role;

select ok(
  exists (
    select 1
    from public.commercial_operators
    where auth_user_id = 'ab120000-0000-4000-8000-000000000005'
      and display_name = 'Target Admin'
      and role = 'admin'
      and status = 'ACTIVE'
  ),
  'valid provisioning creates the exact requested authority'
);
select is(
  (select count(*)::integer
   from lws_internal.commercial_operator_provisioning_events
   where target_auth_user_id = 'ab120000-0000-4000-8000-000000000005'),
  1,
  'idempotent replay creates one immutable audit event'
);
select ok(
  exists (
    select 1
    from lws_internal.commercial_operator_provisioning_events
    where target_auth_user_id = 'ab120000-0000-4000-8000-000000000005'
      and actor_auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'
      and target_role = 'admin'
      and target_status = 'ACTIVE'
      and metadata = jsonb_build_object(
        'contract_version', 1,
        'display_name', 'Target Admin'
      )
  ),
  'audit event binds the owner and target authority without credentials'
);
select throws_ok(
  $$update lws_internal.commercial_operator_provisioning_events
    set metadata = metadata$$,
  '55000', 'COMMERCIAL_OPERATOR_PROVISIONING_EVENT_APPEND_ONLY',
  'provisioning audit events cannot be updated'
);
select throws_ok(
  $$delete from lws_internal.commercial_operator_provisioning_events$$,
  '55000', 'COMMERCIAL_OPERATOR_PROVISIONING_EVENT_APPEND_ONLY',
  'provisioning audit events cannot be deleted'
);
select ok(
  exists (
    select 1
    from public.commercial_operators
    where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'
      and role = 'owner'
      and status = 'ACTIVE'
  )
  and exists (
    select 1
    from public.commercial_operators
    where auth_user_id = 'bd2ab636-0d42-4069-88a9-60bd97f2b335'
      and role = 'admin'
      and status = 'ACTIVE'
  ),
  'provisioning leaves existing operator authorities unchanged'
);

select * from finish();
rollback;