begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public','get_website_repository_operation_by_identity_v1',
  array['uuid','uuid','uuid'],
  'OWNER lookup resolves one repository operation by its complete identity'
);
select function_returns(
  'public','get_website_repository_operation_by_identity_v1',
  array['uuid','uuid','uuid'],'jsonb',
  'identity lookup returns one closed JSON projection'
);
select volatility_is(
  'public','get_website_repository_operation_by_identity_v1',
  array['uuid','uuid','uuid'],'stable',
  'identity lookup is declared read-only'
);
select is_definer(
  'public','get_website_repository_operation_by_identity_v1',
  array['uuid','uuid','uuid'],
  'identity lookup crosses forced RLS only through guarded definer authority'
);
select is(
  (
    select array_to_string(proconfig, ',')
    from pg_proc
    where oid='public.get_website_repository_operation_by_identity_v1(uuid,uuid,uuid)'::regprocedure
  ),
  'search_path=public, lws_internal, auth, pg_catalog',
  'identity lookup pins its search path'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_website_repository_operation_by_identity_v1(uuid,uuid,uuid)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.get_website_repository_operation_by_identity_v1(uuid,uuid,uuid)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.get_website_repository_operation_by_identity_v1(uuid,uuid,uuid)',
    'execute'
  ),
  'only authenticated callers can enter the identity lookup authority'
);

insert into auth.users(id,email) values
  ('f1000000-0000-4000-8000-000000000002','operation-lookup-other-owner@example.test'),
  ('f1000000-0000-4000-8000-000000000003','operation-lookup-admin@example.test');

set local session_replication_role = replica;
insert into public.commercial_operators(
  operator_id,auth_user_id,display_name,role,status
) values
  ('f1100000-0000-4000-8000-000000000002','f1000000-0000-4000-8000-000000000002','Operation lookup other owner','owner','ACTIVE'),
  ('f1100000-0000-4000-8000-000000000003','f1000000-0000-4000-8000-000000000003','Operation lookup admin','admin','ACTIVE');
insert into public.quote_requests(
  id,application_reference,record_classification,request_kind,name,email,
  website_type,budget,timing,description,privacy_consent,status
) values
  ('f1200000-0000-4000-8000-000000000001','LWS-AAN-2099-7201','internal_e2e','website','Lookup fixture A','lookup-a@example.test','business','EUR 4.000','flexible','Lookup fixture A.',true,'approved'),
  ('f2200000-0000-4000-8000-000000000002','LWS-AAN-2099-7202','internal_e2e','website','Lookup fixture B','lookup-b@example.test','business','EUR 4.000','flexible','Lookup fixture B.',true,'approved'),
  ('f3200000-0000-4000-8000-000000000003','LWS-AAN-2099-7203','internal_e2e','website','Lookup fixture C','lookup-c@example.test','business','EUR 4.000','flexible','Lookup fixture C.',true,'approved');
insert into public.website_concepts(
  concept_id,quote_request_id,briefing_status,created_by
) values
  ('f1300000-0000-4000-8000-000000000001','f1200000-0000-4000-8000-000000000001','LIMITED','f1100000-0000-4000-8000-000000000002'),
  ('f1300000-0000-4000-8000-000000000002','f2200000-0000-4000-8000-000000000002','LIMITED','f1100000-0000-4000-8000-000000000002'),
  ('f1300000-0000-4000-8000-000000000003','f3200000-0000-4000-8000-000000000003','LIMITED','f1100000-0000-4000-8000-000000000002');
insert into public.website_work_contexts(
  website_work_context_id,quote_request_id,concept_id,phase
) values
  ('f1400000-0000-4000-8000-000000000001','f1200000-0000-4000-8000-000000000001','f1300000-0000-4000-8000-000000000001','PRE_PROJECT'),
  ('f1400000-0000-4000-8000-000000000002','f2200000-0000-4000-8000-000000000002','f1300000-0000-4000-8000-000000000002','PRE_PROJECT'),
  ('f1400000-0000-4000-8000-000000000003','f3200000-0000-4000-8000-000000000003','f1300000-0000-4000-8000-000000000003','PRE_PROJECT');
insert into public.website_execution_workspaces(
  website_workspace_id,website_work_context_id,project_id,quote_request_id,
  workspace_state,repository_provider,default_branch,preview_branch,created_by,
  provisioned_by,provisioned_at
) values
  ('f1500000-0000-4000-8000-000000000001','f1400000-0000-4000-8000-000000000001',null,'f1200000-0000-4000-8000-000000000001','REPOSITORY_PROVISIONING','GITHUB','main',null,'f1100000-0000-4000-8000-000000000002','f1100000-0000-4000-8000-000000000002',clock_timestamp()),
  ('f1500000-0000-4000-8000-000000000002','f1400000-0000-4000-8000-000000000002',null,'f2200000-0000-4000-8000-000000000002','REPOSITORY_PROVISIONING','GITHUB','main',null,'f1100000-0000-4000-8000-000000000002','f1100000-0000-4000-8000-000000000002',clock_timestamp()),
  ('f1500000-0000-4000-8000-000000000003','f1400000-0000-4000-8000-000000000003',null,'f3200000-0000-4000-8000-000000000003','REPOSITORY_PROVISIONING','GITHUB','main',null,'f1100000-0000-4000-8000-000000000002','f1100000-0000-4000-8000-000000000002',clock_timestamp());
set local session_replication_role = origin;

select set_config('lws.website_repository_command','on',true);
insert into public.website_repository_provisioning_operations(
  operation_id,website_workspace_id,website_work_context_id,actor_id,
  idempotency_key,request_fingerprint,repository_owner,repository_name,
  starter_source,starter_version,starter_commit_sha,state,attempt_count,
  failure_code,retry_action
) values
  ('f1600000-0000-4000-8000-000000000001','f1500000-0000-4000-8000-000000000001','f1400000-0000-4000-8000-000000000001',(select operator_id from public.commercial_operators where auth_user_id='c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),'f1700000-0000-4000-8000-000000000001',repeat('a',64),'lorenzo-web-solutions-lab','lws-web-f1400000000040008000000000000001','lorenzo-web-solutions/lws-website-starter','1.0.0',repeat('b',40),'CREATING',1,null,'RECONCILE'),
  ('f1600000-0000-4000-8000-000000000002','f1500000-0000-4000-8000-000000000002','f1400000-0000-4000-8000-000000000002',(select operator_id from public.commercial_operators where auth_user_id='c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),'f1700000-0000-4000-8000-000000000002',repeat('c',64),'lorenzo-web-solutions-lab','lws-web-f1400000000040008000000000000002','lorenzo-web-solutions/lws-website-starter','1.0.0',repeat('d',40),'CREATING',1,null,'RECONCILE'),
  ('f1600000-0000-4000-8000-000000000003','f1500000-0000-4000-8000-000000000003','f1400000-0000-4000-8000-000000000003',(select operator_id from public.commercial_operators where auth_user_id='c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),'f1700000-0000-4000-8000-000000000003',repeat('e',64),'lorenzo-web-solutions-lab','lws-web-f1400000000040008000000000000003','lorenzo-web-solutions/lws-website-starter','1.0.0',repeat('f',40),'TERMINAL_FAILED',1,'FIXTURE_FAILED',null),
  ('f1600000-0000-4000-8000-000000000004','f1500000-0000-4000-8000-000000000003','f1400000-0000-4000-8000-000000000003','f1100000-0000-4000-8000-000000000002','f1700000-0000-4000-8000-000000000003',repeat('1',64),'lorenzo-web-solutions-lab','lws-web-f1400000000040008000000000000003','lorenzo-web-solutions/lws-website-starter','1.0.0',repeat('2',40),'CLAIMED',1,null,null);
select set_config('lws.website_repository_command','',true);

select set_config('request.jwt.claims','{}',true);
select throws_ok(
  $$select public.get_website_repository_operation_by_identity_v1(
    'f1500000-0000-4000-8000-000000000001','f1400000-0000-4000-8000-000000000001','f1700000-0000-4000-8000-000000000001')$$,
  '42501','HUMAN_JWT_REQUIRED','anonymous lookup is denied'
);
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','role','authenticated','aal','aal1'
)::text,true);
select throws_ok(
  $$select public.get_website_repository_operation_by_identity_v1(
    'f1500000-0000-4000-8000-000000000001','f1400000-0000-4000-8000-000000000001','f1700000-0000-4000-8000-000000000001')$$,
  '42501','AAL2_REQUIRED','AAL1 lookup is denied'
);
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','f1000000-0000-4000-8000-000000000003','role','authenticated','aal','aal2'
)::text,true);
select throws_ok(
  $$select public.get_website_repository_operation_by_identity_v1(
    'f1500000-0000-4000-8000-000000000001','f1400000-0000-4000-8000-000000000001','f1700000-0000-4000-8000-000000000001')$$,
  '42501','WEBSITE_REPOSITORY_OWNER_REQUIRED','non-owner lookup is denied'
);
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','role','authenticated','aal','aal2'
)::text,true);

create temporary table operation_lookup_before as
select row_to_json(operation)::jsonb as snapshot
from public.website_repository_provisioning_operations as operation
where operation.operation_id='f1600000-0000-4000-8000-000000000001';
create temporary table workspace_lookup_before as
select row_to_json(workspace)::jsonb as snapshot
from public.website_execution_workspaces as workspace
where workspace.website_workspace_id='f1500000-0000-4000-8000-000000000001';
create temporary table event_count_before as
select count(*)::bigint as count
from public.website_repository_provisioning_events;
create temporary table operation_lookup_results(
  result_name text primary key,
  payload jsonb not null
) on commit drop;
insert into operation_lookup_results values (
  'exact',public.get_website_repository_operation_by_identity_v1(
    'f1500000-0000-4000-8000-000000000001',
    'f1400000-0000-4000-8000-000000000001',
    'f1700000-0000-4000-8000-000000000001'
  )
);
select is(
  (select payload->>'operation_id' from operation_lookup_results where result_name='exact'),
  'f1600000-0000-4000-8000-000000000001',
  'OWNER AAL2 resolves the exact existing non-BOUND operation ID'
);
select results_eq(
  $$select array_agg(key order by key)
    from jsonb_object_keys(
      (select payload from operation_lookup_results where result_name='exact')
    ) as key$$,
  $$values (array[
    'bound_at','claimed_at','external_created_at','failure_code',
    'first_attempt_at','operation_id','quarantine_alert_due_at',
    'quarantine_alerted_at','quarantine_evidence_sha256','quarantine_reason',
    'quarantine_resolution','quarantine_resolved_at','quarantined_at',
    'repository_external_id','repository_name','repository_owner',
    'repository_visibility','retry_at','state','website_work_context_id',
    'website_workspace_id'
  ]::text[])$$,
  'lookup exposes only the closed safe operation projection'
);
select is(
  (select payload->>'state' from operation_lookup_results where result_name='exact'),
  'CREATING','current in-progress state remains visible without mutation'
);

select throws_ok(
  $$select public.get_website_repository_operation_by_identity_v1(
    'f1500000-0000-4000-8000-000000000002','f1400000-0000-4000-8000-000000000001','f1700000-0000-4000-8000-000000000001')$$,
  '42501','AUTHORITY_MISMATCH','wrong workspace fails closed'
);
select throws_ok(
  $$select public.get_website_repository_operation_by_identity_v1(
    'f1500000-0000-4000-8000-000000000001','f1400000-0000-4000-8000-000000000002','f1700000-0000-4000-8000-000000000001')$$,
  '42501','AUTHORITY_MISMATCH','wrong context fails closed'
);
select throws_ok(
  $$select public.get_website_repository_operation_by_identity_v1(
    'f1500000-0000-4000-8000-000000000001','f1400000-0000-4000-8000-000000000001','f1700000-0000-4000-8000-000000000099')$$,
  'P0002','WEBSITE_REPOSITORY_OPERATION_NOT_FOUND','wrong idempotency key returns no data'
);
select throws_ok(
  $$select public.get_website_repository_operation_by_identity_v1(
    'f1500000-0000-4000-8000-000000000001','f1400000-0000-4000-8000-000000000001','f1700000-0000-4000-8000-000000000002')$$,
  '42501','AUTHORITY_MISMATCH','cross-context operation identity is denied'
);
select throws_ok(
  $$select public.get_website_repository_operation_by_identity_v1(
    'f1500000-0000-4000-8000-000000000002','f1400000-0000-4000-8000-000000000002','f1700000-0000-4000-8000-000000000001')$$,
  '42501','AUTHORITY_MISMATCH','cross-workspace operation identity is denied'
);
select throws_ok(
  $$select public.get_website_repository_operation_by_identity_v1(
    'f1500000-0000-4000-8000-000000000003','f1400000-0000-4000-8000-000000000003','f1700000-0000-4000-8000-000000000003')$$,
  'P0003','AMBIGUOUS_OPERATION','multiple exact operations fail closed'
);

select lives_ok(
  $$select public.get_website_repository_operation_by_identity_v1(
    'f1500000-0000-4000-8000-000000000001','f1400000-0000-4000-8000-000000000001','f1700000-0000-4000-8000-000000000001')$$,
  'read-only lookup can be repeated safely'
);
select results_eq(
  $$select row_to_json(operation)::jsonb
    from public.website_repository_provisioning_operations as operation
    where operation.operation_id='f1600000-0000-4000-8000-000000000001'$$,
  $$select snapshot from operation_lookup_before$$,
  'lookup does not mutate operation state or metadata'
);
select results_eq(
  $$select row_to_json(workspace)::jsonb
    from public.website_execution_workspaces as workspace
    where workspace.website_workspace_id='f1500000-0000-4000-8000-000000000001'$$,
  $$select snapshot from workspace_lookup_before$$,
  'lookup does not mutate workspace state or metadata'
);
select results_eq(
  $$select count(*)::bigint from public.website_repository_provisioning_events$$,
  $$select count from event_count_before$$,
  'lookup emits no repository operation event'
);
select ok(
  lower(pg_get_functiondef(
    'public.get_website_repository_operation_by_identity_v1(uuid,uuid,uuid)'::regprocedure
  )) !~ '(github|http|net\\.|\\m(insert|update|delete)\\M)',
  'lookup contains no provider, GitHub, network or mutation path'
);
select is(
  (
    select count(*)::integer
    from jsonb_object_keys(
      (select payload from operation_lookup_results where result_name='exact')
    ) as key
    where key ~* '(token|secret|credential|password|private_key|request_fingerprint|quarantine_evidence|repository_node_id|starter_)'
      and key <> 'quarantine_evidence_sha256'
  ),0,
  'lookup projects no secrets, credentials, raw evidence or internal fingerprints'
);

select * from finish();
rollback;