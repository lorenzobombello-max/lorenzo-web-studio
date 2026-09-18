begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public',
  'create_task13_synthetic_context_v1',
  array[]::text[],
  'parameterless Task 13 synthetic context authority exists'
);
select has_function(
  'public',
  'verify_task13_synthetic_context_authority_v1',
  array['uuid','uuid'],
  'guarded Task 13 synthetic context read authority exists'
);
select ok(
  (select prosecdef
       and provolatile = 's'
       and proconfig = array['search_path=public, lws_internal, auth, pg_catalog']
       and pg_get_userbyid(proowner) = 'postgres'
   from pg_proc
   where oid = 'public.verify_task13_synthetic_context_authority_v1(uuid,uuid)'::regprocedure),
  'guarded read authority is stable SECURITY DEFINER owned by postgres with a fixed search_path'
);
select is(
  (select count(*)::integer
   from pg_proc
   where pronamespace = 'public'::regnamespace
     and proname = 'verify_task13_synthetic_context_authority_v1'),
  1,
  'guarded read authority has no overload ambiguity'
);
select ok(
  not has_function_privilege(
    'public',
    'public.verify_task13_synthetic_context_authority_v1(uuid,uuid)',
    'execute'
  ),
  'PUBLIC cannot execute guarded read authority'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.create_task13_synthetic_context_v1()',
    'execute'
  ),
  'authenticated humans can enter the guarded authority'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.create_task13_synthetic_context_v1()',
    'execute'
  ),
  'anonymous callers cannot create a synthetic context'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.create_task13_synthetic_context_v1()',
    'execute'
  ),
  'service role cannot bypass human OWNER authority'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.verify_task13_synthetic_context_authority_v1(uuid,uuid)',
    'execute'
  ),
  'authenticated humans can enter the guarded read authority'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.verify_task13_synthetic_context_authority_v1(uuid,uuid)',
    'execute'
  ),
  'anonymous callers cannot enter the guarded read authority'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.verify_task13_synthetic_context_authority_v1(uuid,uuid)',
    'execute'
  ),
  'service role cannot bypass guarded read authority'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.website_work_contexts', 'select'
  ) and not has_table_privilege(
    'authenticated', 'public.website_execution_workspaces', 'select'
  ),
  'guarded RPC adds no direct protected-table SELECT authority'
);

insert into auth.users(id,email) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','task13-owner@example.test'),
  ('bd2ab636-0d42-4069-88a9-60bd97f2b335','task13-admin@example.test')
on conflict (id) do update set email = excluded.email;
set local session_replication_role = replica;
insert into public.commercial_operators(
  operator_id,auth_user_id,display_name,role,status
) values
  ('e2110000-0000-4000-8000-000000000001','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','Task 13 Owner','owner','ACTIVE'),
  ('e2110000-0000-4000-8000-000000000002','bd2ab636-0d42-4069-88a9-60bd97f2b335','Task 13 Admin','admin','ACTIVE')
on conflict (auth_user_id) do update
set display_name = excluded.display_name,
    role = excluded.role,
    status = excluded.status;
set local session_replication_role = origin;

select set_config('request.jwt.claims','{}',true);
select throws_ok(
  $$select public.create_task13_synthetic_context_v1()$$,
  '42501','HUMAN_JWT_REQUIRED',
  'unauthenticated caller is denied'
);
select throws_ok(
  $$select public.verify_task13_synthetic_context_authority_v1(
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222'
    )$$,
  '42501','HUMAN_JWT_REQUIRED',
  'unauthenticated caller cannot enter guarded read authority'
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'role','authenticated','aal','aal1'
  )::text,true
);
select throws_ok(
  $$select public.create_task13_synthetic_context_v1()$$,
  '42501','AAL2_REQUIRED',
  'OWNER at AAL1 is denied'
);
select throws_ok(
  $$select public.verify_task13_synthetic_context_authority_v1(
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222'
    )$$,
  '42501','AAL2_REQUIRED',
  'OWNER at AAL1 cannot enter guarded read authority'
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','bd2ab636-0d42-4069-88a9-60bd97f2b335',
    'role','authenticated','aal','aal2'
  )::text,true
);
select throws_ok(
  $$select public.create_task13_synthetic_context_v1()$$,
  '42501','WEBSITE_REPOSITORY_OWNER_REQUIRED',
  'non-OWNER at AAL2 is denied'
);
select throws_ok(
  $$select public.verify_task13_synthetic_context_authority_v1(
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222'
    )$$,
  '42501','WEBSITE_REPOSITORY_OWNER_REQUIRED',
  'non-OWNER at AAL2 cannot enter guarded read authority'
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'role','authenticated','aal','aal2'
  )::text,true
);

create temporary table task13_context_results(
  sequence integer primary key,
  result jsonb not null
) on commit drop;
insert into task13_context_results values
  (1,public.create_task13_synthetic_context_v1()),
  (2,public.create_task13_synthetic_context_v1());

create temporary table task13_negative_results(
  predicate text primary key,
  result jsonb not null
) on commit drop;
insert into task13_negative_results values
  ('classification',public.create_task13_synthetic_context_v1()),
  ('kind',public.create_task13_synthetic_context_v1()),
  ('reference',public.create_task13_synthetic_context_v1());

set local session_replication_role = replica;
update public.quote_requests as request
set record_classification = 'production'
from public.website_work_contexts as context,
     task13_negative_results as negative
where negative.predicate = 'classification'
  and context.website_work_context_id =
      (negative.result->>'website_work_context_id')::uuid
  and request.id = context.quote_request_id;
update public.quote_requests as request
set request_kind = 'slimme_documentenflow',
    website_type = null,
    budget = null,
    timing = null
from public.website_work_contexts as context,
     task13_negative_results as negative
where negative.predicate = 'kind'
  and context.website_work_context_id =
      (negative.result->>'website_work_context_id')::uuid
  and request.id = context.quote_request_id;
update public.quote_requests as request
set application_reference = 'LWS-AAN-2099-0001'
from public.website_work_contexts as context,
     task13_negative_results as negative
where negative.predicate = 'reference'
  and context.website_work_context_id =
      (negative.result->>'website_work_context_id')::uuid
  and request.id = context.quote_request_id;
set local session_replication_role = origin;

create temporary table task13_authority_snapshot(
  snapshot jsonb not null
) on commit drop;
insert into task13_authority_snapshot
select jsonb_build_object(
  'requests',(
    select coalesce(jsonb_agg(to_jsonb(request) order by request.id),'[]'::jsonb)
    from public.quote_requests as request
    where request.id in (
      select context.quote_request_id
      from public.website_work_contexts as context
      where context.website_work_context_id in (
        select (result->>'website_work_context_id')::uuid from task13_context_results
        union all
        select (result->>'website_work_context_id')::uuid from task13_negative_results
      )
    )
  ),
  'contexts',(
    select coalesce(jsonb_agg(to_jsonb(context) order by context.website_work_context_id),'[]'::jsonb)
    from public.website_work_contexts as context
    where context.website_work_context_id in (
      select (result->>'website_work_context_id')::uuid from task13_context_results
      union all
      select (result->>'website_work_context_id')::uuid from task13_negative_results
    )
  ),
  'workspaces',(
    select coalesce(jsonb_agg(to_jsonb(workspace) order by workspace.website_workspace_id),'[]'::jsonb)
    from public.website_execution_workspaces as workspace
    where workspace.website_work_context_id in (
      select (result->>'website_work_context_id')::uuid from task13_context_results
      union all
      select (result->>'website_work_context_id')::uuid from task13_negative_results
    )
  ),
  'operations',(
    select coalesce(jsonb_agg(to_jsonb(operation) order by operation.operation_id),'[]'::jsonb)
    from public.website_repository_provisioning_operations as operation
    where operation.website_work_context_id in (
      select (result->>'website_work_context_id')::uuid from task13_context_results
      union all
      select (result->>'website_work_context_id')::uuid from task13_negative_results
    )
  ),
  'events',(
    select coalesce(jsonb_agg(to_jsonb(event) order by event.event_id),'[]'::jsonb)
    from public.website_concept_events as event
    where event.website_work_context_id in (
      select (result->>'website_work_context_id')::uuid from task13_context_results
      union all
      select (result->>'website_work_context_id')::uuid from task13_negative_results
    )
  )
);

select ok(
  public.verify_task13_synthetic_context_authority_v1(
    (select (result->>'website_work_context_id')::uuid
     from task13_context_results where sequence=1),
    (select (result->>'workspace_id')::uuid
     from task13_context_results where sequence=1)
  ),
  'guarded read authority accepts one exact generated synthetic relation'
);
select ok(
  not public.verify_task13_synthetic_context_authority_v1(
    (select (result->>'website_work_context_id')::uuid
     from task13_context_results where sequence=1),
    (select (result->>'workspace_id')::uuid
     from task13_context_results where sequence=2)
  ),
  'guarded read authority rejects a cross-context workspace relation'
);
select ok(
  not public.verify_task13_synthetic_context_authority_v1(
    (select (result->>'website_work_context_id')::uuid
     from task13_context_results where sequence=2),
    (select (result->>'workspace_id')::uuid
     from task13_context_results where sequence=1)
  ),
  'guarded read authority rejects the opposite cross-context relation'
);
select ok(
  not public.verify_task13_synthetic_context_authority_v1(
    '11111111-1111-4111-8111-111111111111',
    (select (result->>'workspace_id')::uuid
     from task13_context_results where sequence=1)
  ),
  'guarded read authority rejects a wrong context with a valid workspace'
);
select ok(
  not public.verify_task13_synthetic_context_authority_v1(
    (select (result->>'website_work_context_id')::uuid
     from task13_context_results where sequence=1),
    '22222222-2222-4222-8222-222222222222'
  ),
  'guarded read authority rejects a valid context with a wrong workspace'
);
select ok(
  not public.verify_task13_synthetic_context_authority_v1(
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222'
  ),
  'guarded read authority rejects two unknown IDs'
);
select ok(
  not public.verify_task13_synthetic_context_authority_v1(
    (select (result->>'website_work_context_id')::uuid
     from task13_negative_results where predicate='classification'),
    (select (result->>'workspace_id')::uuid
     from task13_negative_results where predicate='classification')
  ),
  'guarded read authority rejects a production customer context'
);
select ok(
  not public.verify_task13_synthetic_context_authority_v1(
    (select (result->>'website_work_context_id')::uuid
     from task13_negative_results where predicate='kind'),
    (select (result->>'workspace_id')::uuid
     from task13_negative_results where predicate='kind')
  ),
  'guarded read authority rejects a non-website context'
);
select ok(
  not public.verify_task13_synthetic_context_authority_v1(
    (select (result->>'website_work_context_id')::uuid
     from task13_negative_results where predicate='reference'),
    (select (result->>'workspace_id')::uuid
     from task13_negative_results where predicate='reference')
  ),
  'guarded read authority rejects a dossier-bound context'
);
select ok(
  lower(pg_get_functiondef(
    'public.verify_task13_synthetic_context_authority_v1(uuid,uuid)'::regprocedure
  )) like '%context.project_id is null%'
  and lower(pg_get_functiondef(
    'public.verify_task13_synthetic_context_authority_v1(uuid,uuid)'::regprocedure
  )) like '%workspace.project_id is null%',
  'guarded read authority requires both project bindings to remain absent'
);
select is(
  (select jsonb_build_object(
    'requests',(
      select coalesce(jsonb_agg(to_jsonb(request) order by request.id),'[]'::jsonb)
      from public.quote_requests as request
      where request.id in (
        select context.quote_request_id
        from public.website_work_contexts as context
        where context.website_work_context_id in (
          select (result->>'website_work_context_id')::uuid from task13_context_results
          union all
          select (result->>'website_work_context_id')::uuid from task13_negative_results
        )
      )
    ),
    'contexts',(
      select coalesce(jsonb_agg(to_jsonb(context) order by context.website_work_context_id),'[]'::jsonb)
      from public.website_work_contexts as context
      where context.website_work_context_id in (
        select (result->>'website_work_context_id')::uuid from task13_context_results
        union all
        select (result->>'website_work_context_id')::uuid from task13_negative_results
      )
    ),
    'workspaces',(
      select coalesce(jsonb_agg(to_jsonb(workspace) order by workspace.website_workspace_id),'[]'::jsonb)
      from public.website_execution_workspaces as workspace
      where workspace.website_work_context_id in (
        select (result->>'website_work_context_id')::uuid from task13_context_results
        union all
        select (result->>'website_work_context_id')::uuid from task13_negative_results
      )
    ),
    'operations',(
      select coalesce(jsonb_agg(to_jsonb(operation) order by operation.operation_id),'[]'::jsonb)
      from public.website_repository_provisioning_operations as operation
      where operation.website_work_context_id in (
        select (result->>'website_work_context_id')::uuid from task13_context_results
        union all
        select (result->>'website_work_context_id')::uuid from task13_negative_results
      )
    ),
    'events',(
      select coalesce(jsonb_agg(to_jsonb(event) order by event.event_id),'[]'::jsonb)
      from public.website_concept_events as event
      where event.website_work_context_id in (
        select (result->>'website_work_context_id')::uuid from task13_context_results
        union all
        select (result->>'website_work_context_id')::uuid from task13_negative_results
      )
    )
  )),
  (select snapshot from task13_authority_snapshot),
  'guarded read authority changes no context, workspace, request, operation, binding, or event data'
);

select results_eq(
  $$select array_agg(key order by key)
    from jsonb_object_keys(
      (select result from task13_context_results where sequence=1)
    ) as key$$,
  $$values (array[
    'environment','record_classification',
    'website_work_context_id','workspace_id'
  ]::text[])$$,
  'response exposes only the closed synthetic island projection'
);
select is(
  (select result->>'record_classification' from task13_context_results where sequence=1),
  'internal_e2e',
  'classification is server-authored as internal_e2e'
);
select is(
  (select result->>'environment' from task13_context_results where sequence=1),
  'TEST',
  'environment is server-authored as TEST'
);
select isnt(
  (select result->>'website_work_context_id' from task13_context_results where sequence=1),
  (select result->>'website_work_context_id' from task13_context_results where sequence=2),
  'two requests receive distinct server-generated work context IDs'
);
select isnt(
  (select result->>'workspace_id' from task13_context_results where sequence=1),
  (select result->>'workspace_id' from task13_context_results where sequence=2),
  'two requests receive distinct server-generated workspace IDs'
);
select is(
  (select count(*)::integer
   from public.quote_requests as request
   join public.website_work_contexts as context
     on context.quote_request_id=request.id
   where context.website_work_context_id in (
     select (result->>'website_work_context_id')::uuid
     from task13_context_results
   )
     and request.record_classification='internal_e2e'
     and request.request_kind='website'
     and request.application_reference is null),
  2,
  'each context owns a new non-production synthetic root without a dossier reference'
);
select is(
  (select count(*)::integer
   from public.website_concepts as concept
   join public.website_work_contexts as context
     on context.concept_id=concept.concept_id
    and context.quote_request_id=concept.quote_request_id
   where context.website_work_context_id in (
     select (result->>'website_work_context_id')::uuid
     from task13_context_results
   )
     and concept.mode='PRE_PROJECT'
     and concept.commercially_released=false
     and concept.promoted_project_id is null
     and context.phase='PRE_PROJECT'
     and context.project_id is null),
  2,
  'each context remains an unreleased PRE_PROJECT island without customer project binding'
);
select is(
  (select count(*)::integer
   from public.website_execution_workspaces as workspace
   join task13_context_results as created
     on workspace.website_workspace_id=(created.result->>'workspace_id')::uuid
    and workspace.website_work_context_id=(created.result->>'website_work_context_id')::uuid
   join public.quote_requests as request
     on request.id=workspace.quote_request_id
   where workspace.project_id is null
     and workspace.workspace_state='PENDING_REPOSITORY'
     and workspace.repository_provider='GITHUB'
     and workspace.repository_owner is null
     and workspace.repository_name is null
     and workspace.preview_branch is null
     and request.record_classification='internal_e2e'),
  2,
  'each workspace is isolated and has no repository or production binding'
);
select is(
  (select count(distinct workspace.quote_request_id)::integer
   from public.website_execution_workspaces as workspace
   join task13_context_results as created
     on workspace.website_workspace_id=(created.result->>'workspace_id')::uuid),
  2,
  'synthetic workspaces never reuse a dossier root across contexts'
);
select is(
  (select count(*)::integer
   from public.quote_requests as request
   join public.website_work_contexts as context
     on context.quote_request_id=request.id
   where context.website_work_context_id in (
     select (result->>'website_work_context_id')::uuid
     from task13_context_results
   )
     and request.record_classification='production'),
  0,
  'synthetic authority creates no production customer row'
);
select is(
  (select count(*)::integer
   from public.website_concept_events as event
   where event.website_work_context_id in (
     select (result->>'website_work_context_id')::uuid
     from task13_context_results
   )
     and event.event_type='WEBSITE_CONCEPT_STARTED'),
  2,
  'each synthetic island has exactly one append-only creation event'
);

select * from finish();
rollback;
