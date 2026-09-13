begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table(
  'public', 'website_repository_provisioning_operations',
  'durable repository provisioning operation authority exists'
);
select has_table(
  'public', 'website_repository_provisioning_events',
  'repository provisioning transitions have immutable events'
);

select columns_are(
  'public', 'website_repository_provisioning_operations',
  array[
    'operation_id','website_workspace_id','website_work_context_id','actor_id',
    'idempotency_key','request_fingerprint','repository_provider',
    'repository_owner','repository_name','starter_source','starter_version',
    'starter_commit_sha','state','attempt_count','failure_code','retry_at',
    'repository_external_id','repository_node_id','claimed_at','updated_at',
    'external_created_at','bound_at'
  ],
  'operation ledger contains only durable authority and redacted lifecycle metadata'
);
select columns_are(
  'public', 'website_repository_provisioning_events',
  array[
    'event_id','operation_id','website_workspace_id','website_work_context_id',
    'actor_id','request_fingerprint','event_type','previous_state','new_state',
    'repository_provider','repository_owner','repository_name',
    'repository_external_id','starter_source','starter_version',
    'starter_commit_sha','attempt_number','result_code','github_request_id',
    'occurred_at'
  ],
  'event ledger excludes credentials, source content, URLs and customer PII'
);

select has_column('public','website_execution_workspaces','repository_external_id','workspace stores immutable external repository ID');
select has_column('public','website_execution_workspaces','repository_node_id','workspace stores immutable GitHub node ID');
select has_column('public','website_execution_workspaces','repository_visibility','workspace stores verified visibility');
select has_column('public','website_execution_workspaces','repository_state','workspace stores repository-specific state');
select has_column('public','website_execution_workspaces','starter_source','workspace stores approved starter source');
select has_column('public','website_execution_workspaces','starter_version','workspace stores approved starter version');
select has_column('public','website_execution_workspaces','starter_commit_sha','workspace stores exact starter commit');
select has_column('public','website_execution_workspaces','repository_marker_commit_sha','workspace stores marker commit');
select has_column('public','website_execution_workspaces','repository_bound_at','workspace stores verified binding time');

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid='public.website_repository_provisioning_operations'::regclass
      and contype='f' and confrelid='public.website_execution_workspaces'::regclass
  ) and exists (
    select 1 from pg_constraint
    where conrelid='public.website_repository_provisioning_operations'::regclass
      and contype='f' and confrelid='public.website_work_contexts'::regclass
  ),
  'operation authority is foreign-key bound to workspace and work context'
);
select results_eq(
  $$
    select source.relname, source_column.attname,
      target.relname, target_column.attname
    from pg_constraint as constraint_record
    join pg_class as source on source.oid=constraint_record.conrelid
    join pg_class as target on target.oid=constraint_record.confrelid
    join pg_attribute as source_column
      on source_column.attrelid=source.oid
     and source_column.attnum=constraint_record.conkey[1]
    join pg_attribute as target_column
      on target_column.attrelid=target.oid
     and target_column.attnum=constraint_record.confkey[1]
    where constraint_record.contype='f'
      and source.relname in (
        'website_repository_provisioning_operations',
        'website_repository_provisioning_events'
      )
    order by source.relname, source_column.attname
  $$,
  $$values
    ('website_repository_provisioning_events'::name,'actor_id'::name,'commercial_operators'::name,'operator_id'::name),
    ('website_repository_provisioning_events'::name,'operation_id'::name,'website_repository_provisioning_operations'::name,'operation_id'::name),
    ('website_repository_provisioning_events'::name,'website_work_context_id'::name,'website_work_contexts'::name,'website_work_context_id'::name),
    ('website_repository_provisioning_events'::name,'website_workspace_id'::name,'website_execution_workspaces'::name,'website_workspace_id'::name),
    ('website_repository_provisioning_operations'::name,'actor_id'::name,'commercial_operators'::name,'operator_id'::name),
    ('website_repository_provisioning_operations'::name,'website_work_context_id'::name,'website_work_contexts'::name,'website_work_context_id'::name),
    ('website_repository_provisioning_operations'::name,'website_workspace_id'::name,'website_execution_workspaces'::name,'website_workspace_id'::name)
  $$,
  'every repository operation and event foreign key targets its exact authority root'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname='public'
      and indexname='website_repository_operation_active_workspace_unique'
      and indexdef ~ 'UNIQUE'
      and indexdef ~ 'WHERE'
  ) and exists (
    select 1 from pg_indexes
    where schemaname='public'
      and indexname='website_repository_operation_active_context_unique'
      and indexdef ~ 'UNIQUE'
      and indexdef ~ 'WHERE'
  ),
  'one active operation is enforced independently per workspace and context'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname='public'
      and indexname='website_execution_workspace_repository_external_id_unique'
      and indexdef ~ 'UNIQUE'
      and indexdef ~ 'WHERE'
  ),
  'one external repository ID can bind only once'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname='public'
      and indexname='website_repository_operation_bound_workspace_unique'
      and indexdef ~ 'UNIQUE'
  ) and exists (
    select 1 from pg_indexes
    where schemaname='public'
      and indexname='website_repository_operation_bound_context_unique'
      and indexdef ~ 'UNIQUE'
  ),
  'one terminal bound operation is enforced per workspace and context'
);

select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class where oid='public.website_repository_provisioning_operations'::regclass)
  and (select relrowsecurity and relforcerowsecurity
       from pg_class where oid='public.website_repository_provisioning_events'::regclass),
  'repository operation and event ledgers force RLS'
);
select ok(
  not has_table_privilege('anon','public.website_repository_provisioning_operations','select,insert,update,delete')
  and not has_table_privilege('authenticated','public.website_repository_provisioning_operations','select,insert,update,delete')
  and not has_table_privilege('service_role','public.website_repository_provisioning_operations','select,insert,update,delete')
  and not has_table_privilege('anon','public.website_repository_provisioning_events','select,insert,update,delete')
  and not has_table_privilege('authenticated','public.website_repository_provisioning_events','select,insert,update,delete')
  and not has_table_privilege('service_role','public.website_repository_provisioning_events','select,insert,update,delete'),
  'runtime roles have no direct repository authority table privileges'
);

select matches(
  pg_get_constraintdef(oid),
  'CLAIMED.*CREATING.*EXTERNAL_CREATED.*VERIFYING.*BOUND.*RETRYABLE_FAILED.*BLOCKED.*QUARANTINED.*TERMINAL_FAILED',
  'operation state constraint contains the exact durable lifecycle'
)
from pg_constraint
where conrelid='public.website_repository_provisioning_operations'::regclass
  and conname='website_repository_operation_state_valid';
select matches(
  pg_get_constraintdef(oid),
  'PENDING_REPOSITORY.*REPOSITORY_PROVISIONING.*REPOSITORY_READY.*REPOSITORY_FAILED.*READY',
  'workspace state constraint preserves READY and adds repository lifecycle states'
)
from pg_constraint
where conrelid='public.website_execution_workspaces'::regclass
  and conname='website_execution_workspace_state_valid';
select matches(
  pg_get_constraintdef(oid),
  'REPOSITORY_READY.*repository_external_id.*repository_node_id.*repository_visibility.*starter_source.*starter_version.*starter_commit_sha.*repository_marker_commit_sha.*repository_bound_at',
  'workspace ready shape requires complete verified repository metadata'
)
from pg_constraint
where conrelid='public.website_execution_workspaces'::regclass
  and conname='website_execution_workspace_repository_binding_shape';

select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid='public.website_repository_provisioning_operations'::regclass
      and tgname='trg_website_repository_operation_identity_guard'
      and not tgisinternal
  ),
  'operation identity has a mutation guard'
);
select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid='public.website_repository_provisioning_events'::regclass
      and tgname='trg_website_repository_event_immutable'
      and not tgisinternal
  ),
  'repository events are append-only'
);
select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid='public.website_execution_workspaces'::regclass
      and tgname='trg_website_repository_binding_guard'
      and not tgisinternal
  ),
  'bound workspace repository identity has a mutation guard'
);

select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name in (
        'website_execution_workspaces',
        'website_repository_provisioning_operations',
        'website_repository_provisioning_events'
      )
      and column_name ~* '(token|secret|credential|password|private_key|source_content|repository_url|html_url)'
  ),
  'repository authority stores no credential, source-content or independent URL columns'
);

set local session_replication_role = replica;
insert into public.quote_requests(
  id,application_reference,record_classification,request_kind,name,email,
  website_type,budget,timing,description,privacy_consent,status
) values (
  'a5100000-0000-4000-8000-000000000001','LWS-AAN-2099-5101',
  'internal_e2e','website','Repository schema fixture','repository-schema@example.test',
  'business','EUR 4.000','flexible','Repository schema authority fixture.',true,'approved'
);
insert into public.website_concepts(
  concept_id,quote_request_id,briefing_status,created_by
) values (
  'a5200000-0000-4000-8000-000000000001',
  'a5100000-0000-4000-8000-000000000001','LIMITED',
  'c1e35692-c152-4d0d-a3df-c4a4b78e143e'
);
insert into public.website_work_contexts(
  website_work_context_id,quote_request_id,concept_id,phase
) values (
  'a5300000-0000-4000-8000-000000000001',
  'a5100000-0000-4000-8000-000000000001',
  'a5200000-0000-4000-8000-000000000001','PRE_PROJECT'
);
insert into public.website_execution_workspaces(
  website_workspace_id,website_work_context_id,project_id,quote_request_id,
  workspace_state,repository_provider,repository_owner,repository_name,
  default_branch,preview_branch,created_by,provisioned_by,provisioned_at
) values (
  'a5400000-0000-4000-8000-000000000001',
  'a5300000-0000-4000-8000-000000000001',null,
  'a5100000-0000-4000-8000-000000000001','PENDING_REPOSITORY',
  'GITHUB',null,null,'main',null,
  'c1e35692-c152-4d0d-a3df-c4a4b78e143e',
  'c1e35692-c152-4d0d-a3df-c4a4b78e143e',clock_timestamp()
);
set local session_replication_role = origin;

insert into public.website_repository_provisioning_operations(
  operation_id,website_workspace_id,website_work_context_id,actor_id,
  idempotency_key,request_fingerprint,repository_owner,repository_name,
  starter_source,starter_version,starter_commit_sha
) values (
  'a5500000-0000-4000-8000-000000000001',
  'a5400000-0000-4000-8000-000000000001',
  'a5300000-0000-4000-8000-000000000001',
  'c1e35692-c152-4d0d-a3df-c4a4b78e143e',
  'a5600000-0000-4000-8000-000000000001',repeat('a',64),
  'lorenzo-web-solutions-lab','website-a5300000-0000-4000-8000-000000000001',
  'lorenzo-web-solutions/website-starter','1.0.0',repeat('b',40)
);

select throws_ok(
  $$insert into public.website_repository_provisioning_operations(
      operation_id,website_workspace_id,website_work_context_id,actor_id,
      idempotency_key,request_fingerprint,repository_owner,repository_name,
      starter_source,starter_version,starter_commit_sha
    ) values (
      'a5500000-0000-4000-8000-000000000002',
      'a5400000-0000-4000-8000-000000000001',
      'a5300000-0000-4000-8000-000000000001',
      'c1e35692-c152-4d0d-a3df-c4a4b78e143e',
      'a5600000-0000-4000-8000-000000000002',repeat('c',64),
      'lorenzo-web-solutions-lab','website-a5300000-0000-4000-8000-000000000001',
      'lorenzo-web-solutions/website-starter','1.0.0',repeat('b',40)
    )$$,
  '23505',
  'duplicate key value violates unique constraint "website_repository_operation_active_workspace_unique"',
  'a second active operation for the same workspace and context is rejected'
);
select throws_ok(
  $$update public.website_repository_provisioning_operations
    set repository_name='substituted-repository'
    where operation_id='a5500000-0000-4000-8000-000000000001'$$,
  '55000','WEBSITE_REPOSITORY_OPERATION_IDENTITY_IMMUTABLE',
  'operation target identity cannot be substituted'
);
select throws_ok(
  $$delete from public.website_repository_provisioning_operations
    where operation_id='a5500000-0000-4000-8000-000000000001'$$,
  '55000','WEBSITE_REPOSITORY_OPERATION_IMMUTABLE',
  'durable operations cannot be deleted'
);
select throws_ok(
  $$update public.website_execution_workspaces
    set workspace_state='REPOSITORY_READY'
    where website_workspace_id='a5400000-0000-4000-8000-000000000001'$$,
  '23514','new row for relation "website_execution_workspaces" violates check constraint "website_execution_workspace_repository_binding_shape"',
  'repository-ready state rejects incomplete verified metadata'
);

update public.website_execution_workspaces
set workspace_state='REPOSITORY_READY',
    repository_owner='lorenzo-web-solutions-lab',
    repository_name='website-a5300000-0000-4000-8000-000000000001',
    repository_external_id=424242,
    repository_node_id='R_kgDORepositoryFixture',
    repository_visibility='private',
    repository_state='BOUND',
    starter_source='lorenzo-web-solutions/website-starter',
    starter_version='1.0.0',
    starter_commit_sha=repeat('b',40),
    repository_marker_commit_sha=repeat('c',40),
    repository_bound_at=clock_timestamp()
where website_workspace_id='a5400000-0000-4000-8000-000000000001';

select throws_ok(
  $$update public.website_execution_workspaces
    set repository_node_id='R_kgDOSubstituted'
    where website_workspace_id='a5400000-0000-4000-8000-000000000001'$$,
  '55000','WEBSITE_REPOSITORY_BINDING_IMMUTABLE',
  'verified workspace repository identity cannot be substituted'
);

insert into public.website_repository_provisioning_events(
  event_id,operation_id,website_workspace_id,website_work_context_id,actor_id,
  request_fingerprint,event_type,previous_state,new_state,
  repository_provider,repository_owner,repository_name,starter_source,
  starter_version,starter_commit_sha,attempt_number,result_code
) values (
  'a5700000-0000-4000-8000-000000000001',
  'a5500000-0000-4000-8000-000000000001',
  'a5400000-0000-4000-8000-000000000001',
  'a5300000-0000-4000-8000-000000000001',
  'c1e35692-c152-4d0d-a3df-c4a4b78e143e',repeat('a',64),
  'REPOSITORY_PROVISIONING_CLAIMED',null,'CLAIMED','GITHUB',
  'lorenzo-web-solutions-lab','website-a5300000-0000-4000-8000-000000000001',
  'lorenzo-web-solutions/website-starter','1.0.0',repeat('b',40),0,'CLAIMED'
);
select throws_ok(
  $$update public.website_repository_provisioning_events
    set result_code='SUBSTITUTED'
    where event_id='a5700000-0000-4000-8000-000000000001'$$,
  '55000','WEBSITE_REPOSITORY_EVENT_IMMUTABLE',
  'repository lifecycle events cannot be changed'
);
select throws_ok(
  $$delete from public.website_repository_provisioning_events
    where event_id='a5700000-0000-4000-8000-000000000001'$$,
  '55000','WEBSITE_REPOSITORY_EVENT_IMMUTABLE',
  'repository lifecycle events cannot be deleted'
);

select * from finish();
rollback;
