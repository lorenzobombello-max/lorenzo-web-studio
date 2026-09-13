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
select has_function(
  'lws_internal','website_repository_transition_allowed_v1',
  array['text','text'],
  'one pure predicate owns the complete repository transition matrix'
);
select results_eq(
  $$with states(state) as (
      select unnest(array[
        'CLAIMED','CREATING','EXTERNAL_CREATED','VERIFYING','BOUND',
        'RETRYABLE_FAILED','RETRY_SCHEDULED','BLOCKED','QUARANTINED','TERMINAL_FAILED'
      ]::text[])
    ), allowed(old_state,new_state) as (values
      ('CLAIMED','CREATING'),
      ('CREATING','EXTERNAL_CREATED'),('CREATING','RETRYABLE_FAILED'),
      ('CREATING','RETRY_SCHEDULED'),('CREATING','BLOCKED'),
      ('CREATING','QUARANTINED'),('CREATING','TERMINAL_FAILED'),
      ('EXTERNAL_CREATED','VERIFYING'),
      ('VERIFYING','BOUND'),('VERIFYING','RETRYABLE_FAILED'),
      ('VERIFYING','RETRY_SCHEDULED'),('VERIFYING','BLOCKED'),
      ('VERIFYING','QUARANTINED'),('VERIFYING','TERMINAL_FAILED'),
      ('RETRYABLE_FAILED','RETRY_SCHEDULED'),('RETRYABLE_FAILED','CREATING'),
      ('RETRYABLE_FAILED','VERIFYING'),
      ('RETRY_SCHEDULED','CREATING'),('RETRY_SCHEDULED','VERIFYING'),
      ('BLOCKED','CREATING'),('BLOCKED','VERIFYING'),
      ('QUARANTINED','VERIFYING'),('QUARANTINED','TERMINAL_FAILED')
    ), matrix as (
      select source.state as old_state,target.state as new_state,
        source.state=target.state or exists (
          select 1 from allowed
          where allowed.old_state=source.state and allowed.new_state=target.state
        ) as expected
      from states source cross join states target
    )
    select count(*)::integer,
      count(*) filter (where expected)::integer,
      bool_and(lws_internal.website_repository_transition_allowed_v1(old_state,new_state)=expected)
    from matrix$$,
  $$values (100,33,true)$$,
  'all 100 state pairs match the exact 33-transition allowlist including self-updates'
);
select has_function(
  'public','claim_website_repository_provisioning_v1',
  array['uuid','uuid','uuid','text','text','text'],
  'owner command can claim one durable repository operation'
);
select has_function(
  'public','record_website_repository_external_identity_v1',
  array['uuid','text','text'],
  'provider result can durably capture external repository identity'
);
select has_function(
  'public','bind_website_repository_v1',array['uuid','jsonb'],
  'verified provider result can bind one repository'
);
select has_function(
  'public','fail_website_repository_provisioning_v1',array['uuid','text','text'],
  'stable provider failure can advance operation authority'
);
select has_function(
  'public','fail_website_repository_provisioning_v1',
  array['uuid','text','text','text'],
  'provider failure can supply normalized retry timing'
);
select has_function(
  'public','resume_website_repository_provisioning_v1',array['uuid','uuid'],
  'owner command can explicitly resume retryable or blocked work'
);
select has_function(
  'public','resolve_website_repository_quarantine_v1',
  array['uuid','uuid','text','text'],
  'owner command can resolve matching immutable quarantine evidence'
);
select has_function(
  'public','mark_website_repository_quarantine_alerted_v1',
  array['uuid','text'],
  'owner command can durably mark a due quarantine alert'
);
select has_function(
  'public','get_website_repository_operation_v1',array['uuid'],
  'caller-authorized operation projection exists'
);

select columns_are(
  'public', 'website_repository_provisioning_operations',
  array[
    'operation_id','website_workspace_id','website_work_context_id','actor_id',
    'idempotency_key','request_fingerprint','repository_provider',
    'repository_owner','repository_name','starter_source','starter_version',
    'starter_commit_sha','state','attempt_count','failure_code','retry_at',
    'first_attempt_at','retry_window_expires_at','provider_retry_after_at',
    'retry_action','quarantine_evidence','quarantine_evidence_sha256',
    'quarantined_at','quarantine_reason','quarantine_alert_due_at',
    'quarantine_alerted_at','quarantine_resolution','quarantine_resolved_at',
    'quarantine_resolved_by_operator_id',
    'quarantine_resolution_evidence_sha256',
    'quarantine_resolution_idempotency_key','resume_idempotency_key',
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
    ('website_repository_provisioning_operations'::name,'quarantine_resolved_by_operator_id'::name,'commercial_operators'::name,'operator_id'::name),
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
insert into public.commercial_operators(
  operator_id,auth_user_id,display_name,role,status
) values (
  'c1e35692-c152-4d0d-a3df-c4a4b78e143e',
  'c1e35692-c152-4d0d-a3df-c4a4b78e143e',
  'Repository schema fixture','owner','ACTIVE'
);
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
select set_config('lws.website_repository_command','on',true);

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
select set_config('lws.website_repository_command','',true);

select is(
  (
    select count(*)::integer
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid=procedure.pronamespace
    cross join lateral aclexplode(procedure.proacl) as privilege
    join pg_roles as role on role.oid=privilege.grantee
    where namespace.nspname='public'
      and procedure.proname in (
        'claim_website_repository_provisioning_v1',
        'record_website_repository_external_identity_v1',
        'bind_website_repository_v1',
        'fail_website_repository_provisioning_v1',
        'get_website_repository_operation_v1',
        'resume_website_repository_provisioning_v1',
        'resolve_website_repository_quarantine_v1',
        'mark_website_repository_quarantine_alerted_v1'
      )
      and privilege.privilege_type='EXECUTE'
      and role.rolname='authenticated'
  ),
  9,
  'all repository command RPCs grant execute to authenticated callers'
);
select is(
  (
    select count(*)::integer
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid=procedure.pronamespace
    cross join lateral aclexplode(procedure.proacl) as privilege
    left join pg_roles as role on role.oid=privilege.grantee
    where namespace.nspname='public'
      and procedure.proname in (
        'claim_website_repository_provisioning_v1',
        'record_website_repository_external_identity_v1',
        'bind_website_repository_v1',
        'fail_website_repository_provisioning_v1',
        'get_website_repository_operation_v1',
        'resume_website_repository_provisioning_v1',
        'resolve_website_repository_quarantine_v1',
        'mark_website_repository_quarantine_alerted_v1'
      )
      and privilege.privilege_type='EXECUTE'
      and coalesce(role.rolname,'public') in ('public','anon','service_role')
  ),
  0,
  'repository command RPCs grant no execute authority to public, anon or service_role'
);

set local session_replication_role = replica;
insert into public.commercial_operators(
  operator_id,auth_user_id,display_name,role,status
) values (
  'd9000000-0000-4000-8000-000000000001',
  'd9000000-0000-4000-8000-000000000002',
  'Disabled repository owner','owner','DISABLED'
);
insert into public.quote_requests(
  id,application_reference,record_classification,request_kind,name,email,
  website_type,budget,timing,description,privacy_consent,status
) values
  ('b1100000-0000-4000-8000-000000000001','LWS-AAN-2099-6101',
   'internal_e2e','website','Repository RPC fixture A','repository-rpc-a@example.test',
   'business','EUR 4.000','flexible','Repository RPC authority fixture A.',true,'approved'),
  ('b2100000-0000-4000-8000-000000000002','LWS-AAN-2099-6102',
   'internal_e2e','website','Repository RPC fixture B','repository-rpc-b@example.test',
   'business','EUR 4.000','flexible','Repository RPC authority fixture B.',true,'approved'),
  ('b3100000-0000-4000-8000-000000000003','LWS-AAN-2099-6103',
   'internal_e2e','website','Repository RPC fixture C','repository-rpc-c@example.test',
    'business','EUR 4.000','flexible','Repository RPC authority fixture C.',true,'approved'),
    ('b4100000-0000-4000-8000-000000000004','LWS-AAN-2099-6104',
    'internal_e2e','website','Repository RPC fixture D','repository-rpc-d@example.test',
      'business','EUR 4.000','flexible','Repository RPC authority fixture D.',true,'approved'),
    ('c1100000-0000-4000-8000-000000000005','LWS-AAN-2099-6105',
      'production','website','Repository RPC fixture E','repository-rpc-e@example.test',
      'business','EUR 4.000','flexible','Repository RPC authority fixture E.',true,'approved');
insert into public.website_concepts(
  concept_id,quote_request_id,briefing_status,created_by
) values
  ('b1200000-0000-4000-8000-000000000001','b1100000-0000-4000-8000-000000000001','LIMITED','c1e35692-c152-4d0d-a3df-c4a4b78e143e'),
  ('b1200000-0000-4000-8000-000000000002','b2100000-0000-4000-8000-000000000002','LIMITED','c1e35692-c152-4d0d-a3df-c4a4b78e143e'),
  ('b1200000-0000-4000-8000-000000000003','b3100000-0000-4000-8000-000000000003','LIMITED','c1e35692-c152-4d0d-a3df-c4a4b78e143e'),
  ('b1200000-0000-4000-8000-000000000004','b4100000-0000-4000-8000-000000000004','LIMITED','c1e35692-c152-4d0d-a3df-c4a4b78e143e'),
  ('c1200000-0000-4000-8000-000000000005','c1100000-0000-4000-8000-000000000005','LIMITED','c1e35692-c152-4d0d-a3df-c4a4b78e143e');
insert into public.website_work_contexts(
  website_work_context_id,quote_request_id,concept_id,phase
) values
  ('b1300000-0000-4000-8000-000000000001','b1100000-0000-4000-8000-000000000001','b1200000-0000-4000-8000-000000000001','PRE_PROJECT'),
  ('b1300000-0000-4000-8000-000000000002','b2100000-0000-4000-8000-000000000002','b1200000-0000-4000-8000-000000000002','PRE_PROJECT'),
  ('b1300000-0000-4000-8000-000000000003','b3100000-0000-4000-8000-000000000003','b1200000-0000-4000-8000-000000000003','PRE_PROJECT'),
  ('b1300000-0000-4000-8000-000000000004','b4100000-0000-4000-8000-000000000004','b1200000-0000-4000-8000-000000000004','PRE_PROJECT'),
  ('c1300000-0000-4000-8000-000000000005','c1100000-0000-4000-8000-000000000005','c1200000-0000-4000-8000-000000000005','PRE_PROJECT');
insert into public.website_execution_workspaces(
  website_workspace_id,website_work_context_id,project_id,quote_request_id,
  workspace_state,repository_provider,default_branch,preview_branch,created_by,
  provisioned_by,provisioned_at
) values
  ('b1400000-0000-4000-8000-000000000001','b1300000-0000-4000-8000-000000000001',null,'b1100000-0000-4000-8000-000000000001','PENDING_REPOSITORY','GITHUB','main',null,'c1e35692-c152-4d0d-a3df-c4a4b78e143e','c1e35692-c152-4d0d-a3df-c4a4b78e143e',clock_timestamp()),
  ('b1400000-0000-4000-8000-000000000002','b1300000-0000-4000-8000-000000000002',null,'b2100000-0000-4000-8000-000000000002','PENDING_REPOSITORY','GITHUB','main',null,'c1e35692-c152-4d0d-a3df-c4a4b78e143e','c1e35692-c152-4d0d-a3df-c4a4b78e143e',clock_timestamp()),
  ('b1400000-0000-4000-8000-000000000003','b1300000-0000-4000-8000-000000000003',null,'b3100000-0000-4000-8000-000000000003','PENDING_REPOSITORY','GITHUB','main',null,'c1e35692-c152-4d0d-a3df-c4a4b78e143e','c1e35692-c152-4d0d-a3df-c4a4b78e143e',clock_timestamp()),
  ('b1400000-0000-4000-8000-000000000004','b1300000-0000-4000-8000-000000000004',null,'b4100000-0000-4000-8000-000000000004','PENDING_REPOSITORY','GITHUB','main',null,'c1e35692-c152-4d0d-a3df-c4a4b78e143e','c1e35692-c152-4d0d-a3df-c4a4b78e143e',clock_timestamp()),
  ('c1400000-0000-4000-8000-000000000005','c1300000-0000-4000-8000-000000000005',null,'c1100000-0000-4000-8000-000000000005','PENDING_REPOSITORY','GITHUB','main',null,'c1e35692-c152-4d0d-a3df-c4a4b78e143e','c1e35692-c152-4d0d-a3df-c4a4b78e143e',clock_timestamp());
set local session_replication_role = origin;

select set_config('request.jwt.claims','{}',true);
select throws_ok(
  $$select public.claim_website_repository_provisioning_v1(
    'b1400000-0000-4000-8000-000000000001',
    'b1300000-0000-4000-8000-000000000001',
    'b1500000-0000-4000-8000-000000000001',
    'lorenzo-web-solutions-lab/website-starter','1.0.0',repeat('1',40)
  )$$,
  '42501','HUMAN_JWT_REQUIRED',
  'repository claim requires a caller JWT'
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'role','authenticated','aal','aal1'
  )::text,true
);
select throws_ok(
  $$select public.claim_website_repository_provisioning_v1(
    'b1400000-0000-4000-8000-000000000001',
    'b1300000-0000-4000-8000-000000000001',
    'b1500000-0000-4000-8000-000000000001',
    'lorenzo-web-solutions-lab/website-starter','1.0.0',repeat('1',40)
  )$$,
  '42501','AAL2_REQUIRED',
  'repository claim rejects an owner at aal1'
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','bd2ab636-0d42-4069-88a9-60bd97f2b335',
    'role','authenticated','aal','aal2'
  )::text,true
);
select throws_ok(
  $$select public.claim_website_repository_provisioning_v1(
    'b1400000-0000-4000-8000-000000000001',
    'b1300000-0000-4000-8000-000000000001',
    'b1500000-0000-4000-8000-000000000001',
    'lorenzo-web-solutions-lab/website-starter','1.0.0',repeat('1',40)
  )$$,
  '42501','WEBSITE_REPOSITORY_OWNER_REQUIRED',
  'repository claim rejects a non-owner at aal2'
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','d9000000-0000-4000-8000-000000000002',
    'role','authenticated','aal','aal2'
  )::text,true
);
select throws_ok(
  $$select public.claim_website_repository_provisioning_v1(
    'b1400000-0000-4000-8000-000000000001',
    'b1300000-0000-4000-8000-000000000001',
    'b1500000-0000-4000-8000-000000000001',
    'lorenzo-web-solutions-lab/website-starter','1.0.0',repeat('1',40)
  )$$,
  '42501','WEBSITE_REPOSITORY_OWNER_REQUIRED',
  'repository claim rejects a disabled owner at aal2'
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'role','authenticated','aal','aal2'
  )::text,true
);

select throws_ok(
  $$select public.claim_website_repository_provisioning_v1(
    'c1400000-0000-4000-8000-000000000005','c1300000-0000-4000-8000-000000000005',
    'c1500000-0000-4000-8000-000000000005','lorenzo-web-solutions-lab/website-starter','1.0.0',repeat('1',40))$$,
  '22023','WEBSITE_REPOSITORY_STARTER_OWNER_INVALID',
  'a production context cannot substitute the isolated test organization'
);
select is(
  public.claim_website_repository_provisioning_v1(
    'c1400000-0000-4000-8000-000000000005','c1300000-0000-4000-8000-000000000005',
    'c1500000-0000-4000-8000-000000000005','lorenzo-web-solutions/website-starter','1.0.0',repeat('1',40)
  )->>'repository_owner',
  'lorenzo-web-solutions','production derives only the production organization'
);

create temporary table repository_rpc_results(
  result_name text primary key,
  payload jsonb not null
) on commit drop;
insert into repository_rpc_results values (
  'claim',
  public.claim_website_repository_provisioning_v1(
    'b1400000-0000-4000-8000-000000000001',
    'b1300000-0000-4000-8000-000000000001',
    'b1500000-0000-4000-8000-000000000001',
    'lorenzo-web-solutions-lab/website-starter','1.0.0',repeat('1',40)
  )
);
select is(
  (select payload->>'result' from repository_rpc_results where result_name='claim'),
  'CLAIMED','first exact request claims a durable repository operation'
);
select results_eq(
  $$select repository_owner,repository_name,starter_source,starter_version,
      starter_commit_sha,state
    from public.website_repository_provisioning_operations
    where website_work_context_id='b1300000-0000-4000-8000-000000000001'$$,
  $$values (
    'lorenzo-web-solutions-lab'::text,
    'lws-web-b1300000000040008000000000000001'::text,
    'lorenzo-web-solutions-lab/website-starter'::text,
    '1.0.0'::text,repeat('1',40)::text,'CREATING'::text
  )$$,
  'claim derives the test owner and UUID repository name and binds starter provenance'
);
insert into repository_rpc_results values (
  'claim_replay',
  public.claim_website_repository_provisioning_v1(
    'b1400000-0000-4000-8000-000000000001',
    'b1300000-0000-4000-8000-000000000001',
    'b1500000-0000-4000-8000-000000000001',
    'lorenzo-web-solutions-lab/website-starter','1.0.0',repeat('1',40)
  )
);
select is(
  (select payload->>'result' from repository_rpc_results where result_name='claim_replay'),
  'REPLAY','an exact idempotency fingerprint replays the existing operation'
);
insert into repository_rpc_results values (
  'claim_in_progress',
  public.claim_website_repository_provisioning_v1(
    'b1400000-0000-4000-8000-000000000001',
    'b1300000-0000-4000-8000-000000000001',
    'b1500000-0000-4000-8000-000000000002',
    'lorenzo-web-solutions-lab/website-starter','1.0.0',repeat('1',40)
  )
);
select is(
  (select payload->>'result' from repository_rpc_results where result_name='claim_in_progress'),
  'IN_PROGRESS','a second key cannot create another active context operation'
);
select throws_ok(
  $$select public.claim_website_repository_provisioning_v1(
    'b1400000-0000-4000-8000-000000000001',
    'b1300000-0000-4000-8000-000000000001',
    'b1500000-0000-4000-8000-000000000001',
    'lorenzo-web-solutions-lab/website-starter','1.0.1',repeat('1',40)
  )$$,
  'P0001','IDEMPOTENCY_CONFLICT',
  'an idempotency key cannot be reused with a different fingerprint'
);
select throws_ok(
  $$select public.bind_website_repository_v1(
    (select operation_id from public.website_repository_provisioning_operations
      where website_work_context_id='b1300000-0000-4000-8000-000000000001'),
    '{}'::jsonb
  )$$,
  '22023','INVALID_WEBSITE_REPOSITORY_BINDING',
  'binding rejects incomplete verification before external capture'
);
insert into repository_rpc_results values (
  'external_capture',
  public.record_website_repository_external_identity_v1(
    (select operation_id from public.website_repository_provisioning_operations
      where website_work_context_id='b1300000-0000-4000-8000-000000000001'),
    '610001','R_kgDORepository610001'
  )
);
select results_eq(
  $$select state,repository_external_id,repository_node_id,
      external_created_at is not null
    from public.website_repository_provisioning_operations
    where website_work_context_id='b1300000-0000-4000-8000-000000000001'$$,
  $$values ('VERIFYING'::text,610001::bigint,
    'R_kgDORepository610001'::text,true)$$,
  'external repository identity is durable before verification and binding'
);
select throws_ok(
  $$select public.record_website_repository_external_identity_v1(
    (select operation_id from public.website_repository_provisioning_operations
      where website_work_context_id='b1300000-0000-4000-8000-000000000001'),
    '610002','R_kgDORepository610002'
  )$$,
  'P0001','WEBSITE_REPOSITORY_IDENTITY_MISMATCH',
  'captured external identity cannot be substituted'
);
select throws_ok(
  $$select public.bind_website_repository_v1(
    (select operation_id from public.website_repository_provisioning_operations
      where website_work_context_id='b1300000-0000-4000-8000-000000000001'),
    jsonb_build_object(
      'operation_id',(select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000001'),
      'website_workspace_id','b1400000-0000-4000-8000-000000000001',
      'website_work_context_id','b1300000-0000-4000-8000-000000000002',
      'repository_external_id','610001','repository_node_id','R_kgDORepository610001',
      'repository_owner','lorenzo-web-solutions-lab',
      'repository_name','lws-web-b1300000000040008000000000000001',
      'repository_visibility','private','default_branch','main',
      'starter_source','lorenzo-web-solutions-lab/website-starter',
      'starter_version','1.0.0','starter_commit_sha',repeat('1',40),
      'repository_marker_commit_sha',repeat('2',40)
    )
  )$$,
  'P0001','WEBSITE_REPOSITORY_BINDING_MISMATCH',
  'binding rejects a substituted work context'
);
select throws_ok(
  $$select public.bind_website_repository_v1(
    (select operation_id from public.website_repository_provisioning_operations
      where website_work_context_id='b1300000-0000-4000-8000-000000000001'),
    jsonb_build_object(
      'operation_id',(select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000001'),
      'website_workspace_id','b1400000-0000-4000-8000-000000000001',
      'website_work_context_id','b1300000-0000-4000-8000-000000000001',
      'repository_external_id','610002','repository_node_id','R_kgDORepository610001',
      'repository_owner','lorenzo-web-solutions-lab',
      'repository_name','lws-web-b1300000000040008000000000000001',
      'repository_visibility','private','default_branch','main',
      'starter_source','lorenzo-web-solutions-lab/website-starter',
      'starter_version','1.0.0','starter_commit_sha',repeat('1',40),
      'repository_marker_commit_sha',repeat('2',40)
    )
  )$$,
  'P0001','WEBSITE_REPOSITORY_BINDING_MISMATCH',
  'binding rejects a substituted external repository ID'
);
create function pg_temp.reject_repository_ready_v1()
returns trigger language plpgsql as $$
begin
  if new.workspace_state='REPOSITORY_READY' then
    raise exception using errcode='P0001',message='FORCED_BINDING_ROLLBACK';
  end if;
  return new;
end;
$$;
create trigger trg_reject_repository_ready_v1
before update on public.website_execution_workspaces
for each row execute function pg_temp.reject_repository_ready_v1();
create temporary table binding_rollback_before as
select operation.updated_at,
  (select count(*)::integer from public.website_repository_provisioning_events event
   where event.operation_id=operation.operation_id) as event_count
from public.website_repository_provisioning_operations operation
where operation.website_work_context_id='b1300000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.bind_website_repository_v1(
    (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000001'),
    jsonb_build_object(
      'operation_id',(select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000001'),
      'website_workspace_id','b1400000-0000-4000-8000-000000000001',
      'website_work_context_id','b1300000-0000-4000-8000-000000000001',
      'repository_external_id','610001','repository_node_id','R_kgDORepository610001',
      'repository_owner','lorenzo-web-solutions-lab',
      'repository_name','lws-web-b1300000000040008000000000000001',
      'repository_visibility','private','default_branch','main',
      'starter_source','lorenzo-web-solutions-lab/website-starter',
      'starter_version','1.0.0','starter_commit_sha',repeat('1',40),
      'repository_marker_commit_sha',repeat('2',40)
    ))$$,
  'P0001','FORCED_BINDING_ROLLBACK',
  'binding failure after its first write aborts the whole transaction'
);
drop trigger trg_reject_repository_ready_v1 on public.website_execution_workspaces;
select results_eq(
  $$select operation.state,workspace.workspace_state,
      operation.updated_at=(select updated_at from binding_rollback_before),
      (select count(*)::integer from public.website_repository_provisioning_events event
       where event.operation_id=operation.operation_id)=(select event_count from binding_rollback_before)
    from public.website_repository_provisioning_operations operation
    join public.website_execution_workspaces workspace using (website_workspace_id)
    where operation.website_work_context_id='b1300000-0000-4000-8000-000000000001'$$,
  $$values ('VERIFYING'::text,'REPOSITORY_PROVISIONING'::text,true,true)$$,
  'failed binding rolls back operation, workspace, and event changes atomically'
);
insert into repository_rpc_results values (
  'bound',
  public.bind_website_repository_v1(
    (select operation_id from public.website_repository_provisioning_operations
      where website_work_context_id='b1300000-0000-4000-8000-000000000001'),
    jsonb_build_object(
      'operation_id',(select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000001'),
      'website_workspace_id','b1400000-0000-4000-8000-000000000001',
      'website_work_context_id','b1300000-0000-4000-8000-000000000001',
      'repository_external_id','610001','repository_node_id','R_kgDORepository610001',
      'repository_owner','lorenzo-web-solutions-lab',
      'repository_name','lws-web-b1300000000040008000000000000001',
      'repository_visibility','private','default_branch','main',
      'starter_source','lorenzo-web-solutions-lab/website-starter',
      'starter_version','1.0.0','starter_commit_sha',repeat('1',40),
      'repository_marker_commit_sha',repeat('2',40)
    )
  )
);
select is(
  (select payload->>'result' from repository_rpc_results where result_name='bound'),
  'BOUND','an exact verified repository result binds the workspace'
);
select results_eq(
  $$select workspace_state,repository_state,repository_external_id,
      repository_node_id,repository_marker_commit_sha,repository_bound_at is not null
    from public.website_execution_workspaces
    where website_workspace_id='b1400000-0000-4000-8000-000000000001'$$,
  $$values ('REPOSITORY_READY'::text,'BOUND'::text,610001::bigint,
    'R_kgDORepository610001'::text,repeat('2',40)::text,true)$$,
  'binding persists the exact verified repository identity and marker'
);
select throws_ok(
  $$select public.bind_website_repository_v1(
    (select operation_id from public.website_repository_provisioning_operations
      where website_work_context_id='b1300000-0000-4000-8000-000000000001'),
    jsonb_build_object(
      'operation_id',(select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000001'),
      'website_workspace_id','b1400000-0000-4000-8000-000000000001',
      'website_work_context_id','b1300000-0000-4000-8000-000000000002',
      'repository_external_id','610001','repository_node_id','R_kgDORepository610001',
      'repository_owner','lorenzo-web-solutions-lab',
      'repository_name','lws-web-b1300000000040008000000000000001',
      'repository_visibility','private','default_branch','main',
      'starter_source','lorenzo-web-solutions-lab/website-starter',
      'starter_version','1.0.0','starter_commit_sha',repeat('1',40),
      'repository_marker_commit_sha',repeat('2',40)
    )
  )$$,
  'P0001','WEBSITE_REPOSITORY_BINDING_MISMATCH',
  'bound replay still rejects a substituted context'
);
insert into repository_rpc_results values (
  'read',
  public.get_website_repository_operation_v1(
    (select operation_id from public.website_repository_provisioning_operations
      where website_work_context_id='b1300000-0000-4000-8000-000000000001')
  )
);
select results_eq(
  $$select array_agg(key order by key)
    from jsonb_object_keys((select payload from repository_rpc_results where result_name='read')) as key$$,
  $$values (array[
    'attempt_count','bound_at','claimed_at','external_created_at','failure_code',
    'first_attempt_at','operation_id','provider_retry_after_at','quarantine_alert_due_at',
    'quarantine_alerted_at','quarantine_evidence_sha256','quarantine_reason',
    'quarantine_resolution','quarantine_resolved_at','quarantined_at',
    'repository_external_id','repository_name','repository_node_id',
    'repository_owner','repository_provider','result','retry_action','retry_at',
    'retry_window_expires_at','starter_commit_sha',
    'starter_source','starter_version','state','updated_at','website_work_context_id',
    'website_workspace_id'
  ]::text[])$$,
  'operation read returns the exact redacted projection'
);

insert into repository_rpc_results values (
  'failure_claim',
  public.claim_website_repository_provisioning_v1(
    'b1400000-0000-4000-8000-000000000002',
    'b1300000-0000-4000-8000-000000000002',
    'b1500000-0000-4000-8000-000000000003',
    'lorenzo-web-solutions-lab/website-starter','1.0.0',repeat('1',40)
  )
);
insert into repository_rpc_results values (
  'retryable_failure',
  public.fail_website_repository_provisioning_v1(
    (select operation_id from public.website_repository_provisioning_operations
      where website_work_context_id='b1300000-0000-4000-8000-000000000002'),
    'PROVIDER_UNAVAILABLE','github-request-610002','not-a-provider-time'
  )
);
select results_eq(
  $$select state,failure_code,retry_at is not null
    from public.website_repository_provisioning_operations
    where website_work_context_id='b1300000-0000-4000-8000-000000000002'$$,
  $$values ('RETRY_SCHEDULED'::text,'PROVIDER_UNAVAILABLE'::text,true)$$,
  'retryable provider failure records a stable code and retry boundary'
);
insert into repository_rpc_results values (
  'quarantine_claim',
  public.claim_website_repository_provisioning_v1(
    'b1400000-0000-4000-8000-000000000003',
    'b1300000-0000-4000-8000-000000000003',
    'b1500000-0000-4000-8000-000000000004',
    'lorenzo-web-solutions-lab/website-starter','1.0.0',repeat('1',40)
  )
);
insert into repository_rpc_results values (
  'quarantine_external_capture',
  public.record_website_repository_external_identity_v1(
    (select operation_id from public.website_repository_provisioning_operations
      where website_work_context_id='b1300000-0000-4000-8000-000000000003'),
    '610003','R_kgDORepository610003'
  )
);
insert into repository_rpc_results values (
  'quarantined_failure',
  public.fail_website_repository_provisioning_v1(
    (select operation_id from public.website_repository_provisioning_operations
      where website_work_context_id='b1300000-0000-4000-8000-000000000003'),
    'MARKER_MISMATCH','github-request-610003'
  )
);
select results_eq(
  $$select state,failure_code,retry_at is null
    from public.website_repository_provisioning_operations
    where website_work_context_id='b1300000-0000-4000-8000-000000000003'$$,
  $$values ('QUARANTINED'::text,'MARKER_MISMATCH'::text,true)$$,
  'permanent verification mismatch is quarantined without automatic retry'
);
select is(
  (
    select count(*)::integer
    from public.website_repository_provisioning_events
    where operation_id in (
      select operation_id
      from public.website_repository_provisioning_operations
      where website_work_context_id in (
        'b1300000-0000-4000-8000-000000000001',
        'b1300000-0000-4000-8000-000000000002',
        'b1300000-0000-4000-8000-000000000003'
      )
    )
  ),
  13,
  'claims, external capture, binding and failures emit immutable redacted events'
);

select results_eq(
  $$select retry_window_expires_at=first_attempt_at+interval '24 hours',
      attempt_count,retry_action,
      extract(epoch from retry_at-updated_at) between 23 and 37
    from public.website_repository_provisioning_operations
    where website_work_context_id='b1300000-0000-4000-8000-000000000002'$$,
  $$values (true,1,'CREATE'::text,true)$$,
  'first retry uses one fixed 24-hour window and a deterministic 30-second plus-or-minus-20-percent delay'
);
set local session_replication_role = replica;
update public.website_repository_provisioning_operations as operation
set first_attempt_at=clock.now_at-interval '24 hours',
    retry_window_expires_at=clock.now_at,retry_at=clock.now_at
from (select clock_timestamp() as now_at) as clock
where website_work_context_id='b1300000-0000-4000-8000-000000000002';
set local session_replication_role = origin;
select throws_ok(
  $$select public.resume_website_repository_provisioning_v1(
    (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000002'),
    'b1600000-0000-4000-8000-000000000001')$$,
  'P0001','WEBSITE_REPOSITORY_RETRY_WINDOW_EXPIRED',
  'fixed retry window never resets and denies automatic work after 24 hours'
);

insert into repository_rpc_results values (
  'provider_claim',public.claim_website_repository_provisioning_v1(
    'b1400000-0000-4000-8000-000000000004','b1300000-0000-4000-8000-000000000004',
    'b1500000-0000-4000-8000-000000000005','lorenzo-web-solutions-lab/website-starter','1.0.0',repeat('1',40)
  )
);
select public.fail_website_repository_provisioning_v1(
  (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000004'),
  'RATE_LIMITED','github-request-610004',(clock_timestamp()+interval '48 hours')::text
);
select ok(
  (select provider_retry_after_at=retry_at and retry_at=retry_window_expires_at
   from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000004'),
  'valid normalized provider timing takes precedence and is clamped to fixed-window expiry'
);
select set_config('lws.website_repository_command','on',true);
update public.website_repository_provisioning_operations set retry_at=claimed_at
where website_work_context_id='b1300000-0000-4000-8000-000000000004';
select set_config('lws.website_repository_command','',true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','role','authenticated','aal','aal1')::text,true
);
select throws_ok(
  $$select public.resume_website_repository_provisioning_v1(
    (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000004'),
    'b1600000-0000-4000-8000-000000000002')$$,
  '42501','AAL2_REQUIRED','explicit retry resume requires owner AAL2'
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','role','authenticated','aal','aal2')::text,true
);
select is(
  public.resume_website_repository_provisioning_v1(
    (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000004'),
    'b1600000-0000-4000-8000-000000000002')->>'state',
  'CREATING','explicit due retry resumes CREATE without resetting its window'
);
select public.fail_website_repository_provisioning_v1(
  (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000004'),
  'PROVIDER_FORBIDDEN','github-request-610004'
);
select is(
  public.claim_website_repository_provisioning_v1(
    'b1400000-0000-4000-8000-000000000004','b1300000-0000-4000-8000-000000000004',
    'b1500000-0000-4000-8000-000000000006','lorenzo-web-solutions-lab/website-starter','1.0.0',repeat('1',40)
  )->>'result','IN_PROGRESS',
  'BLOCKED cannot auto-resume through a new claim'
);
select is(
  public.resume_website_repository_provisioning_v1(
    (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000004'),
    'b1600000-0000-4000-8000-000000000003'
  )->>'state','CREATING',
  'BLOCKED resumes only through a new explicit owner AAL2 command'
);
select public.fail_website_repository_provisioning_v1(
  (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000004'),
  'EXTERNAL_OUTCOME_UNKNOWN','github-request-610004','malformed'
);
select results_eq(
  $$select state,retry_action,attempt_count,
      extract(epoch from retry_at-updated_at) between 95 and 145
    from public.website_repository_provisioning_operations
    where website_work_context_id='b1300000-0000-4000-8000-000000000004'$$,
  $$values ('RETRY_SCHEDULED'::text,'RECONCILE'::text,3,true)$$,
  'unknown external outcome schedules reconciliation only with deterministic exponential jitter'
);
select set_config('lws.website_repository_command','on',true);
update public.website_repository_provisioning_operations set retry_at=claimed_at
where website_work_context_id='b1300000-0000-4000-8000-000000000004';
select set_config('lws.website_repository_command','',true);
select results_eq(
  $$select result->>'state',result->>'retry_action'
    from (select public.resume_website_repository_provisioning_v1(
      (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000004'),
      'b1600000-0000-4000-8000-000000000004'
    ) as result) resumed$$,
  $$values ('CREATING'::text,'RECONCILE'::text)$$,
  'unknown external outcome resumes reconciliation-only without authorizing another create'
);
select public.fail_website_repository_provisioning_v1(
  (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000004'),
  'PROVIDER_UNAVAILABLE','github-request-610004'
);
select ok(
  (select attempt_count=4 and extract(epoch from retry_at-updated_at) between 190 and 290
   from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000004'),
  'attempt five is scheduled from the 240-second base with deterministic jitter'
);
select set_config('lws.website_repository_command','on',true);
update public.website_repository_provisioning_operations set retry_at=claimed_at
where website_work_context_id='b1300000-0000-4000-8000-000000000004';
select set_config('lws.website_repository_command','',true);
select public.resume_website_repository_provisioning_v1(
  (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000004'),
  'b1600000-0000-4000-8000-000000000005'
);
select public.fail_website_repository_provisioning_v1(
  (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000004'),
  'EXTERNAL_OUTCOME_UNKNOWN','github-request-610004'
);
select results_eq(
  $$select state,attempt_count,retry_at is null,quarantine_evidence is not null
    from public.website_repository_provisioning_operations
    where website_work_context_id='b1300000-0000-4000-8000-000000000004'$$,
  $$values ('QUARANTINED'::text,5,true,true)$$,
  'fifth unknown-outcome attempt exhausts automatic retries into quarantine'
);
select is(
  public.resolve_website_repository_quarantine_v1(
    (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000004'),
    'b1700000-0000-4000-8000-000000000004','MARK_TERMINAL_FAILED',
    (select quarantine_evidence_sha256::text from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000004')
  )->>'state','TERMINAL_FAILED',
  'MARK_TERMINAL_FAILED is the only non-binding quarantine resolution'
);

select results_eq(
  $$select (select count(*)::integer from jsonb_object_keys(quarantine_evidence)),
      quarantine_evidence_sha256=encode(extensions.digest(convert_to(quarantine_evidence::text,'UTF8'),'sha256'),'hex'),
      quarantine_alert_due_at=quarantined_at+interval '24 hours',quarantine_alerted_at is null
    from public.website_repository_provisioning_operations
    where website_work_context_id='b1300000-0000-4000-8000-000000000003'$$,
  $$values (22,true,true,true)$$,
  'quarantine stores the complete canonical evidence hash and non-expiring 24-hour alert representation'
);
select throws_ok(
  $$select public.mark_website_repository_quarantine_alerted_v1(
    (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000003'),
    (select quarantine_evidence_sha256::text from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000003'))$$,
  'P0001','WEBSITE_REPOSITORY_QUARANTINE_ALERT_NOT_DUE',
  'quarantine alert cannot be marked before its durable due time'
);
set local session_replication_role = replica;
update public.website_repository_provisioning_operations
set quarantined_at=quarantined_at-interval '24 hours',
    quarantine_alert_due_at=quarantine_alert_due_at-interval '24 hours'
where website_work_context_id='b1300000-0000-4000-8000-000000000003';
set local session_replication_role = origin;
insert into repository_rpc_results values (
  'quarantine_alerted',
  public.mark_website_repository_quarantine_alerted_v1(
    (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000003'),
    (select quarantine_evidence_sha256::text from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000003')
  )
);
select results_eq(
  $$select (select payload->>'state' from repository_rpc_results where result_name='quarantine_alerted'),
      state,quarantine_alerted_at is not null,
      quarantine_evidence_sha256=encode(extensions.digest(convert_to(quarantine_evidence::text,'UTF8'),'sha256'),'hex')
    from public.website_repository_provisioning_operations
    where website_work_context_id='b1300000-0000-4000-8000-000000000003'$$,
  $$values ('QUARANTINED'::text,'QUARANTINED'::text,true,true)$$,
  'marking a due alert records delivery without mutating state or evidence'
);
select is(
  (select count(*)::integer from public.website_repository_provisioning_events event
   join public.website_repository_provisioning_operations operation using (operation_id)
   where operation.website_work_context_id='b1300000-0000-4000-8000-000000000003'
     and event.event_type='REPOSITORY_QUARANTINE_ALERTED'),
  1,'quarantine alert marking emits one immutable audit event'
);
select set_config('lws.website_repository_command','on',true);
select throws_ok(
  $$update public.website_repository_provisioning_operations
    set quarantine_evidence=quarantine_evidence||'{"marker_status":"SUBSTITUTED"}'::jsonb,
        quarantine_evidence_sha256=repeat('e',64)
    where website_work_context_id='b1300000-0000-4000-8000-000000000003'$$,
  '55000','WEBSITE_REPOSITORY_QUARANTINE_EVIDENCE_IMMUTABLE',
  'captured quarantine evidence and its hash are immutable even inside command scope'
);
select set_config('lws.website_repository_command','',true);
select throws_ok(
  $$select public.resolve_website_repository_quarantine_v1(
    (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000003'),
    'b1700000-0000-4000-8000-000000000001','ADOPT',repeat('f',64))$$,
  '22023','INVALID_WEBSITE_REPOSITORY_QUARANTINE_RESOLUTION',
  'quarantine resolution rejects every non-approved decision literal'
);
select throws_ok(
  $$select public.resolve_website_repository_quarantine_v1(
    (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000003'),
    'b1700000-0000-4000-8000-000000000001','VERIFY_AND_BIND',
    (select quarantine_evidence_sha256::text from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000004'))$$,
  '42501','STALE_QUARANTINE_EVIDENCE',
  'quarantine resolution rejects stale or cross-context evidence hashes'
);
select is(
  public.resolve_website_repository_quarantine_v1(
    (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000003'),
    'b1700000-0000-4000-8000-000000000001','VERIFY_AND_BIND',
    (select quarantine_evidence_sha256::text from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000003')
  )->>'state','VERIFYING',
  'matching owner AAL2 evidence permits only VERIFY_AND_BIND into verification'
);
select is(
  public.fail_website_repository_provisioning_v1(
    (select operation_id from public.website_repository_provisioning_operations where website_work_context_id='b1300000-0000-4000-8000-000000000003'),
    'MARKER_MISMATCH','github-request-610003'
  )->>'state','TERMINAL_FAILED',
  'a second permanent mismatch after quarantine resolution fails closed without rewriting evidence'
);
select is(
  (select count(*)::integer from public.website_repository_provisioning_events event
   join public.website_repository_provisioning_operations operation using (operation_id)
   where operation.website_work_context_id in (
     'b1300000-0000-4000-8000-000000000003','b1300000-0000-4000-8000-000000000004'
   ) and event.event_type='REPOSITORY_QUARANTINE_RESOLVED'),
  2,'both approved quarantine decisions emit immutable resolution events'
);
select throws_ok(
  $test$do $body$ begin
      perform set_config('lws.website_repository_command','on',true);
      update public.website_repository_provisioning_operations
      set state='QUARANTINED'
      where website_work_context_id='b1300000-0000-4000-8000-000000000004';
      raise exception using errcode='P0001',message='TRANSITION_GUARD_MISSING';
    end $body$;$test$,
  'P0001','WEBSITE_REPOSITORY_TRANSITION_INVALID',
  'terminal states reject structurally valid backward transitions'
);

select * from finish();
rollback;
