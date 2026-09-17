begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public','finalize_recovered_website_repository_v1',array['uuid','jsonb','uuid','text'],
  'dedicated post-recovery repository finalizer exists'
);
select function_returns(
  'public','finalize_recovered_website_repository_v1',array['uuid','jsonb','uuid','text'],
  'jsonb','finalizer returns one closed operation projection'
);
select volatility_is(
  'public','finalize_recovered_website_repository_v1',array['uuid','jsonb','uuid','text'],
  'volatile','finalizer declares its durable write behavior'
);
select is_definer(
  'public','finalize_recovered_website_repository_v1',array['uuid','jsonb','uuid','text'],
  'finalizer uses the guarded definer pattern'
);
select is(
  (select proconfig from pg_proc where oid=
    'public.finalize_recovered_website_repository_v1(uuid,jsonb,uuid,text)'::regprocedure),
  array['search_path=public, lws_internal, auth, pg_catalog'],
  'finalizer pins the reviewed hardened search path'
);
select ok(
  has_function_privilege('service_role','public.finalize_recovered_website_repository_v1(uuid,jsonb,uuid,text)','execute')
  and not has_function_privilege('public','public.finalize_recovered_website_repository_v1(uuid,jsonb,uuid,text)','execute')
  and not has_function_privilege('anon','public.finalize_recovered_website_repository_v1(uuid,jsonb,uuid,text)','execute')
  and not has_function_privilege('authenticated','public.finalize_recovered_website_repository_v1(uuid,jsonb,uuid,text)','execute'),
  'only the trusted Edge service principal can enter the finalizer'
);
select ok(
  pg_get_functiondef('public.resume_website_repository_provisioning_v1(uuid,uuid)'::regprocedure)
    !~ 'TERMINAL_FAILED',
  'generic resume remains closed to terminal failures'
);

insert into auth.users(id,email) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','finalizer-owner@example.test'),
  ('bd2ab636-0d42-4069-88a9-60bd97f2b335','finalizer-admin@example.test')
on conflict (id) do update set email=excluded.email;
set local session_replication_role = replica;
insert into public.commercial_operators(
  operator_id,auth_user_id,display_name,role,status
) values
  ('fb100000-0000-4000-8000-000000000001','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','Finalizer Owner','owner','ACTIVE'),
  ('fb100000-0000-4000-8000-000000000002','bd2ab636-0d42-4069-88a9-60bd97f2b335','Finalizer Admin','admin','ACTIVE')
on conflict (auth_user_id) do update
set display_name=excluded.display_name,role=excluded.role,status=excluded.status;
set local session_replication_role = origin;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'role','authenticated','aal','aal2'
)::text,true);

create temporary table finalizer_fixture(value jsonb not null) on commit drop;
insert into finalizer_fixture values(public.create_task13_synthetic_context_v1());

set local session_replication_role = replica;
update public.website_execution_workspaces
set workspace_state='REPOSITORY_FAILED'
where website_workspace_id=(select (value->>'workspace_id')::uuid from finalizer_fixture);
set local session_replication_role = origin;

select set_config('lws.website_repository_command','on',true);
insert into public.website_repository_provisioning_operations(
  operation_id,website_workspace_id,website_work_context_id,actor_id,
  idempotency_key,request_fingerprint,repository_owner,repository_name,
  starter_source,starter_version,starter_commit_sha,state,attempt_count,
  failure_code,retry_action,repository_external_id,repository_node_id,
  claimed_at,updated_at,external_created_at
) values (
  'fb300000-0000-4000-8000-000000000001',
  (select (value->>'workspace_id')::uuid from finalizer_fixture),
  (select (value->>'website_work_context_id')::uuid from finalizer_fixture),
  (select operator_id from public.commercial_operators
   where auth_user_id='c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
  'fb400000-0000-4000-8000-000000000001',repeat('d',64),
  'lorenzo-web-solutions-lab',
  'lws-web-'||replace((select value->>'website_work_context_id' from finalizer_fixture),'-',''),
  'lorenzo-web-solutions/lws-website-starter','1.0.0',repeat('a',40),
  'TERMINAL_FAILED',1,'REPOSITORY_PROVIDER_FAILED',null,
  1371224564,'R_task13_existing_repository',
  statement_timestamp(),statement_timestamp(),statement_timestamp()
);
select set_config('lws.website_repository_command','',true);

create function pg_temp.verification(p_override jsonb default '{}'::jsonb)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'operation_id','fb300000-0000-4000-8000-000000000001',
    'website_workspace_id',value->>'workspace_id',
    'website_work_context_id',value->>'website_work_context_id',
    'repository_external_id','1371224564',
    'repository_node_id','R_task13_existing_repository',
    'repository_owner','lorenzo-web-solutions-lab',
    'repository_name','lws-web-'||replace(value->>'website_work_context_id','-',''),
    'repository_visibility','private','default_branch','main',
    'starter_source','lorenzo-web-solutions/lws-website-starter',
    'starter_version','1.0.0','starter_commit_sha',repeat('a',40),
    'repository_marker_commit_sha',repeat('b',40)
  ) || p_override from finalizer_fixture
$$;

select throws_ok(
  $$select public.finalize_recovered_website_repository_v1(
    'fb300000-0000-4000-8000-000000000001',pg_temp.verification(),
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','aal2')$$,
  '42501','TASK13_FINALIZATION_SERVICE_REQUIRED',
  'authenticated OWNER cannot bypass the Edge proof path'
);
select set_config('request.jwt.claims',jsonb_build_object(
  'role','service_role'
)::text,true);
select throws_ok(
  $$select public.finalize_recovered_website_repository_v1(
    'fb300000-0000-4000-8000-000000000001',pg_temp.verification(),
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','aal1')$$,
  '42501','AAL2_REQUIRED','AAL1 is denied'
);
select throws_ok(
  $$select public.finalize_recovered_website_repository_v1(
    'fb300000-0000-4000-8000-000000000001',pg_temp.verification(),
    'bd2ab636-0d42-4069-88a9-60bd97f2b335','aal2')$$,
  '42501','WEBSITE_REPOSITORY_OWNER_REQUIRED','non-OWNER is denied'
);

select throws_ok(
  $$select public.finalize_recovered_website_repository_v1(
    'fb300000-0000-4000-8000-000000000001',
    pg_temp.verification('{"repository_owner":null}'),
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','aal2')$$,
  '22023','INVALID_RECOVERED_WEBSITE_REPOSITORY_BINDING',
  'JSON null cannot bypass exact binding comparisons'
);

select throws_ok(
  $$select public.finalize_recovered_website_repository_v1(
    'fb300000-0000-4000-8000-000000000001',
    pg_temp.verification('{"repository_external_id":"1371224565"}'),
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','aal2')$$,
  'P0001','RECOVERED_WEBSITE_REPOSITORY_BINDING_MISMATCH',
  'substituted repository identity is denied'
);
select throws_ok(
  $$select public.finalize_recovered_website_repository_v1(
    'fb300000-0000-4000-8000-000000000001',
    pg_temp.verification('{"website_work_context_id":"11111111-1111-4111-8111-111111111111"}'),
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','aal2')$$,
  'P0001','RECOVERED_WEBSITE_REPOSITORY_BINDING_MISMATCH',
  'substituted work context is denied'
);

create function pg_temp.reject_finalizer_ready_v1()
returns trigger language plpgsql as $$
begin
  if new.workspace_state='REPOSITORY_READY' then
    raise exception using errcode='P0001',message='FORCED_FINALIZER_ROLLBACK';
  end if;
  return new;
end;
$$;
create trigger trg_reject_finalizer_ready_v1
before update on public.website_execution_workspaces
for each row execute function pg_temp.reject_finalizer_ready_v1();
select throws_ok(
  $$select public.finalize_recovered_website_repository_v1(
    'fb300000-0000-4000-8000-000000000001',pg_temp.verification(),
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','aal2')$$,
  'P0001','FORCED_FINALIZER_ROLLBACK',
  'workspace write failure aborts finalization'
);
drop trigger trg_reject_finalizer_ready_v1 on public.website_execution_workspaces;
select results_eq(
  $$select operation.state,workspace.workspace_state,
      count(event.event_id)::integer
    from public.website_repository_provisioning_operations operation
    join public.website_execution_workspaces workspace using (website_workspace_id)
    left join public.website_repository_provisioning_events event
      on event.operation_id=operation.operation_id
      and event.event_type='REPOSITORY_BOUND'
    where operation.operation_id='fb300000-0000-4000-8000-000000000001'
    group by operation.state,workspace.workspace_state$$,
  $$values ('TERMINAL_FAILED'::text,'REPOSITORY_FAILED'::text,0::integer)$$,
  'failed finalization leaves operation workspace and event ledger unchanged'
);

create temporary table finalizer_results(name text primary key,payload jsonb not null)
on commit drop;
insert into finalizer_results values(
  'bound',public.finalize_recovered_website_repository_v1(
    'fb300000-0000-4000-8000-000000000001',pg_temp.verification(),
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','aal2'
  )
);
select is(
  (select payload->>'result' from finalizer_results where name='bound'),
  'BOUND','eligible post-recovery state binds atomically'
);
select results_eq(
  $$select operation.state,operation.failure_code,operation.bound_at is not null,
      workspace.workspace_state,workspace.repository_state,
      workspace.repository_external_id,workspace.repository_node_id,
      workspace.repository_marker_commit_sha,
      count(event.event_id)::integer
    from public.website_repository_provisioning_operations operation
    join public.website_execution_workspaces workspace using (website_workspace_id)
    left join public.website_repository_provisioning_events event
      on event.operation_id=operation.operation_id
      and event.event_type='REPOSITORY_BOUND'
    where operation.operation_id='fb300000-0000-4000-8000-000000000001'
    group by operation.state,operation.failure_code,operation.bound_at,
      workspace.workspace_state,workspace.repository_state,
      workspace.repository_external_id,workspace.repository_node_id,
      workspace.repository_marker_commit_sha$$,
  $$values ('BOUND'::text,null::text,true,'REPOSITORY_READY'::text,'BOUND'::text,
    1371224564::bigint,'R_task13_existing_repository'::text,
    repeat('b',40)::text,1::integer)$$,
  'success records the exact binding and one terminal event'
);

insert into finalizer_results values(
  'replay',public.finalize_recovered_website_repository_v1(
    'fb300000-0000-4000-8000-000000000001',pg_temp.verification(),
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','aal2'
  )
);
select is(
  (select payload->>'result' from finalizer_results where name='replay'),
  'REPLAY','exact BOUND replay is idempotent'
);
select is(
  (select count(*)::integer from public.website_repository_provisioning_events
   where operation_id='fb300000-0000-4000-8000-000000000001'
     and event_type='REPOSITORY_BOUND'),
  1,'exact replay never duplicates the bound event'
);
select throws_ok(
  $$select public.finalize_recovered_website_repository_v1(
    'fb300000-0000-4000-8000-000000000001',
    pg_temp.verification('{"repository_marker_commit_sha":"cccccccccccccccccccccccccccccccccccccccc"}'),
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','aal2')$$,
  'P0001','RECOVERED_WEBSITE_REPOSITORY_BINDING_MISMATCH',
  'conflicting BOUND replay is denied'
);

select * from finish();
rollback;