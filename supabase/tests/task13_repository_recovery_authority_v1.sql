begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

create function pg_temp.read_recovery_authority(
  p_operation_id uuid,
  p_website_work_context_id uuid,
  p_website_workspace_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  if to_regprocedure(
    'public.get_task13_repository_recovery_authority_v1(uuid,uuid,uuid)'
  ) is null then
    return jsonb_build_object('capability_missing', true);
  end if;
  execute 'select public.get_task13_repository_recovery_authority_v1($1,$2,$3)'
    into v_result
    using p_operation_id,p_website_work_context_id,p_website_workspace_id;
  return v_result;
end;
$$;

select has_function(
  'public','get_task13_repository_recovery_authority_v1',
  array['uuid','uuid','uuid'],
  'dedicated Task 13 recovery authority exists without an idempotency key'
);
select function_returns(
  'public','get_task13_repository_recovery_authority_v1',
  array['uuid','uuid','uuid'],'jsonb','recovery authority returns one closed JSON projection'
);
select volatility_is(
  'public','get_task13_repository_recovery_authority_v1',
  array['uuid','uuid','uuid'],'stable','recovery authority is read-only stable'
);
select is_definer(
  'public','get_task13_repository_recovery_authority_v1',
  array['uuid','uuid','uuid'],'recovery authority uses the guarded definer pattern'
);
select is(
  (select proconfig from pg_proc where oid=
    'public.get_task13_repository_recovery_authority_v1(uuid,uuid,uuid)'::regprocedure),
  array['search_path=public, lws_internal, auth, pg_catalog'],
  'recovery authority pins the reviewed hardened search path'
);
select ok(
  has_function_privilege('authenticated','public.get_task13_repository_recovery_authority_v1(uuid,uuid,uuid)','execute')
  and not has_function_privilege('public','public.get_task13_repository_recovery_authority_v1(uuid,uuid,uuid)','execute')
  and not has_function_privilege('anon','public.get_task13_repository_recovery_authority_v1(uuid,uuid,uuid)','execute')
  and not has_function_privilege('service_role','public.get_task13_repository_recovery_authority_v1(uuid,uuid,uuid)','execute'),
  'only authenticated callers can enter the recovery authority'
);
select ok(
  not has_table_privilege('authenticated','public.website_repository_provisioning_operations','select')
  and not has_table_privilege('authenticated','public.website_work_contexts','select')
  and not has_table_privilege('authenticated','public.website_execution_workspaces','select')
  and not has_table_privilege('authenticated','public.website_concepts','select')
  and not has_table_privilege('authenticated','public.quote_requests','select'),
  'recovery authority adds no direct protected-table SELECT grant'
);
select ok(
  lower(pg_get_functiondef(
    'public.get_task13_repository_recovery_authority_v1(uuid,uuid,uuid)'::regprocedure
  )) !~ '\m(insert|update|delete|truncate|merge)\M',
  'recovery authority contains no mutation statement'
);
select ok(
  lower(pg_get_functiondef(
    'public.get_task13_repository_recovery_authority_v1(uuid,uuid,uuid)'::regprocedure
  )) not like '%idempotency%',
  'recovery authority neither accepts nor reads an idempotency key'
);
select is(
  (select count(*)::integer from pg_proc
   where pronamespace='public'::regnamespace
     and proname='get_task13_repository_recovery_authority_v1'),
  1,'recovery authority has no overload ambiguity'
);

insert into auth.users(id,email) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','recovery-owner@example.test'),
  ('bd2ab636-0d42-4069-88a9-60bd97f2b335','recovery-admin@example.test')
on conflict (id) do update set email=excluded.email;
set local session_replication_role = replica;
insert into public.commercial_operators(
  operator_id,auth_user_id,display_name,role,status
) values
  ('fa100000-0000-4000-8000-000000000001','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','Recovery Owner','owner','ACTIVE'),
  ('fa100000-0000-4000-8000-000000000002','bd2ab636-0d42-4069-88a9-60bd97f2b335','Recovery Admin','admin','ACTIVE')
on conflict (auth_user_id) do update
set display_name=excluded.display_name,role=excluded.role,status=excluded.status;
set local session_replication_role = origin;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'role','authenticated','aal','aal2'
)::text,true);

create temporary table recovery_contexts(
  sequence integer primary key,
  value jsonb not null
) on commit drop;
insert into recovery_contexts values
  (1,public.create_task13_synthetic_context_v1()),
  (2,public.create_task13_synthetic_context_v1()),
  (3,public.create_task13_synthetic_context_v1()),
  (4,public.create_task13_synthetic_context_v1()),
  (5,public.create_task13_synthetic_context_v1());

set local session_replication_role = replica;
update public.website_concepts as concept
set concept_status='PROMOTED',
    promoted_project_id='fa200000-0000-4000-8000-000000000002',
    promoted_at=clock_timestamp()
from public.website_work_contexts as context
where context.website_work_context_id=(
    select (value->>'website_work_context_id')::uuid
    from recovery_contexts where sequence=2
  )
  and concept.concept_id=context.concept_id;
update public.quote_requests as request
set application_reference='LWS-AAN-2099-9903'
from public.website_work_contexts as context
where context.website_work_context_id=(
    select (value->>'website_work_context_id')::uuid
    from recovery_contexts where sequence=3
  )
  and request.id=context.quote_request_id;
update public.website_execution_workspaces as workspace
set workspace_state='REPOSITORY_READY',
    repository_owner='lorenzo-web-solutions-lab',
    repository_name='lws-web-recovery-binding-fixture',
    repository_external_id=1371224564,
    repository_node_id='R_recovery_binding_fixture',
    repository_visibility='private',
    repository_state='BOUND',
    starter_source='lorenzo-web-solutions/lws-website-starter',
    starter_version='1.0.0',
    starter_commit_sha=repeat('a',40),
    repository_marker_commit_sha=repeat('b',40),
    repository_bound_at=clock_timestamp()
where workspace.website_workspace_id=(
  select (value->>'workspace_id')::uuid
  from recovery_contexts where sequence=4
);
set local session_replication_role = origin;

select set_config('lws.website_repository_command','on',true);
insert into public.website_repository_provisioning_operations(
  operation_id,website_workspace_id,website_work_context_id,actor_id,
  idempotency_key,request_fingerprint,repository_owner,repository_name,
  starter_source,starter_version,starter_commit_sha,state,attempt_count,
  failure_code,retry_action,repository_external_id,repository_node_id,
  claimed_at,updated_at,external_created_at
)
select
  ('fa300000-0000-4000-8000-'||lpad(sequence::text,12,'0'))::uuid,
  (value->>'workspace_id')::uuid,
  (value->>'website_work_context_id')::uuid,
  (select operator_id from public.commercial_operators
   where auth_user_id='c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
  ('fa400000-0000-4000-8000-'||lpad(sequence::text,12,'0'))::uuid,
  repeat(sequence::text,64),
  'lorenzo-web-solutions-lab',
  'lws-web-recovery-authority-fixture-'||sequence,
  'lorenzo-web-solutions/lws-website-starter','1.0.0',repeat('c',40),
  'TERMINAL_FAILED',1,'REPOSITORY_PROVIDER_FAILED',null,
  1371224500+sequence,'R_recovery_authority_fixture_'||sequence,
  statement_timestamp(),statement_timestamp(),statement_timestamp()
from recovery_contexts;
select set_config('lws.website_repository_command','',true);

create temporary table recovery_before as
select jsonb_build_object(
  'requests',(select jsonb_agg(to_jsonb(request) order by request.id)
    from public.quote_requests request
    where request.id in (
      select context.quote_request_id from public.website_work_contexts context
      where context.website_work_context_id in (
        select (value->>'website_work_context_id')::uuid from recovery_contexts
      )
    )),
  'contexts',(select jsonb_agg(to_jsonb(context) order by context.website_work_context_id)
    from public.website_work_contexts context
    where context.website_work_context_id in (
      select (value->>'website_work_context_id')::uuid from recovery_contexts
    )),
  'workspaces',(select jsonb_agg(to_jsonb(workspace) order by workspace.website_workspace_id)
    from public.website_execution_workspaces workspace
    where workspace.website_workspace_id in (
      select (value->>'workspace_id')::uuid from recovery_contexts
    )),
  'operations',(select jsonb_agg(to_jsonb(operation) order by operation.operation_id)
    from public.website_repository_provisioning_operations operation
    where operation.operation_id::text like 'fa300000-0000-4000-8000-%')
) snapshot;

create temporary table recovery_results(
  sequence integer primary key,
  payload jsonb not null
) on commit drop;
insert into recovery_results
select sequence,pg_temp.read_recovery_authority(
  ('fa300000-0000-4000-8000-'||lpad(sequence::text,12,'0'))::uuid,
  (value->>'website_work_context_id')::uuid,
  (value->>'workspace_id')::uuid
)
from recovery_contexts;

select is(
  (select payload from recovery_results where sequence=1),
  jsonb_build_object(
    'operation_found',true,
    'operation_id','fa300000-0000-4000-8000-000000000001',
    'website_work_context_id',(select value->>'website_work_context_id' from recovery_contexts where sequence=1),
    'website_workspace_id',(select value->>'workspace_id' from recovery_contexts where sequence=1),
    'operation_state','TERMINAL_FAILED',
    'failure_code','REPOSITORY_PROVIDER_FAILED',
    'external_created_at_present',true,
    'repository_external_id','1371224501',
    'target_owner','lorenzo-web-solutions-lab',
    'target_repository_name','lws-web-recovery-authority-fixture-1',
    'bound_at_present',false,
    'quarantine_present',false,
    'customer_binding_present',false,
    'dossier_binding_present',false,
    'repository_binding_present',false
  ),
  'exact OWNER AAL2 authority projects one closed unbound operation result'
);
select is(
  (select (payload->>'customer_binding_present')::boolean from recovery_results where sequence=2),
  true,'promoted customer/project binding projects presence only'
);
select is(
  (select (payload->>'dossier_binding_present')::boolean from recovery_results where sequence=3),
  true,'dossier reference binding projects presence only'
);
select is(
  (select (payload->>'repository_binding_present')::boolean from recovery_results where sequence=4),
  true,'workspace repository binding projects presence only'
);

select throws_ok(
  $$select pg_temp.read_recovery_authority(
    'fa300000-0000-4000-8000-000000000099',
    (select (value->>'website_work_context_id')::uuid from recovery_contexts where sequence=1),
    (select (value->>'workspace_id')::uuid from recovery_contexts where sequence=1))$$,
  'P0002','TASK13_RECOVERY_OPERATION_NOT_FOUND','wrong operation fails closed'
);
select throws_ok(
  $$select pg_temp.read_recovery_authority(
    'fa300000-0000-4000-8000-000000000001',
    (select (value->>'website_work_context_id')::uuid from recovery_contexts where sequence=2),
    (select (value->>'workspace_id')::uuid from recovery_contexts where sequence=1))$$,
  '42501','TASK13_RECOVERY_AUTHORITY_MISMATCH','operation/context mismatch fails closed'
);
select throws_ok(
  $$select pg_temp.read_recovery_authority(
    'fa300000-0000-4000-8000-000000000001',
    (select (value->>'website_work_context_id')::uuid from recovery_contexts where sequence=1),
    (select (value->>'workspace_id')::uuid from recovery_contexts where sequence=2))$$,
  '42501','TASK13_RECOVERY_AUTHORITY_MISMATCH','operation/workspace mismatch fails closed'
);

select set_config('request.jwt.claims',jsonb_build_object(
  'sub','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','role','authenticated','aal','aal1'
)::text,true);
select throws_ok(
  $$select pg_temp.read_recovery_authority(
    'fa300000-0000-4000-8000-000000000001',
    (select (value->>'website_work_context_id')::uuid from recovery_contexts where sequence=1),
    (select (value->>'workspace_id')::uuid from recovery_contexts where sequence=1))$$,
  '42501','AAL2_REQUIRED','AAL1 is denied'
);
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','bd2ab636-0d42-4069-88a9-60bd97f2b335','role','authenticated','aal','aal2'
)::text,true);
select throws_ok(
  $$select pg_temp.read_recovery_authority(
    'fa300000-0000-4000-8000-000000000001',
    (select (value->>'website_work_context_id')::uuid from recovery_contexts where sequence=1),
    (select (value->>'workspace_id')::uuid from recovery_contexts where sequence=1))$$,
  '42501','WEBSITE_REPOSITORY_OWNER_REQUIRED','authenticated non-OWNER is denied'
);
select set_config('request.jwt.claims','{}',true);
select throws_ok(
  $$select pg_temp.read_recovery_authority(
    'fa300000-0000-4000-8000-000000000001',
    (select (value->>'website_work_context_id')::uuid from recovery_contexts where sequence=1),
    (select (value->>'workspace_id')::uuid from recovery_contexts where sequence=1))$$,
  '42501','HUMAN_JWT_REQUIRED','unauthenticated caller is denied'
);
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','role','authenticated','aal','aal2'
)::text,true);

select throws_ok(
  $$select pg_temp.read_recovery_authority(
    'fa300000-0000-4000-8000-000000000005',
    (select (value->>'website_work_context_id')::uuid from recovery_contexts where sequence=1),
    (select (value->>'workspace_id')::uuid from recovery_contexts where sequence=5))$$,
  '42501','TASK13_RECOVERY_AUTHORITY_MISMATCH','cross-context authority is denied'
);
select throws_ok(
  $$select pg_temp.read_recovery_authority(
    'fa300000-0000-4000-8000-000000000005',
    (select (value->>'website_work_context_id')::uuid from recovery_contexts where sequence=5),
    (select (value->>'workspace_id')::uuid from recovery_contexts where sequence=1))$$,
  '42501','TASK13_RECOVERY_AUTHORITY_MISMATCH','cross-workspace authority is denied'
);
select is(
  (select count(*)::integer from pg_constraint
   where conrelid='public.website_repository_provisioning_operations'::regclass
     and contype='p' and conkey=array[
       (select attnum from pg_attribute
        where attrelid='public.website_repository_provisioning_operations'::regclass
          and attname='operation_id')
     ]::smallint[]),
  1,'operation identity is structurally unambiguous'
);

select is(
  jsonb_build_object(
    'requests',(select jsonb_agg(to_jsonb(request) order by request.id)
      from public.quote_requests request
      where request.id in (
        select context.quote_request_id from public.website_work_contexts context
        where context.website_work_context_id in (
          select (value->>'website_work_context_id')::uuid from recovery_contexts
        )
      )),
    'contexts',(select jsonb_agg(to_jsonb(context) order by context.website_work_context_id)
      from public.website_work_contexts context
      where context.website_work_context_id in (
        select (value->>'website_work_context_id')::uuid from recovery_contexts
      )),
    'workspaces',(select jsonb_agg(to_jsonb(workspace) order by workspace.website_workspace_id)
      from public.website_execution_workspaces workspace
      where workspace.website_workspace_id in (
        select (value->>'workspace_id')::uuid from recovery_contexts
      )),
    'operations',(select jsonb_agg(to_jsonb(operation) order by operation.operation_id)
      from public.website_repository_provisioning_operations operation
      where operation.operation_id::text like 'fa300000-0000-4000-8000-%')
  ),
  (select snapshot from recovery_before),
  'all recovery authority reads leave operation context workspace and binding rows unchanged'
);

select * from finish();
rollback;