begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public', 'claim_production_website_repository_provisioning_v1',
  array['uuid','uuid','uuid','uuid','text','text','text'],
  'production PRE_PROJECT repository claim authority exists'
);
select has_function(
  'public', 'bind_production_website_repository_v1',
  array['uuid','uuid','jsonb'],
  'production repository bind authority exists'
);
select has_function(
  'public', 'get_production_website_repository_recovery_authority_v1',
  array['uuid','uuid','uuid'],
  'production existing-repository recovery authority exists'
);
select has_function(
  'public', 'finalize_production_website_repository_recovery_v1',
  array['uuid','uuid','jsonb','uuid','text'],
  'production existing-repository recovery finalizer exists'
);
select has_function(
  'public', 'get_website_execution_workspace_v5', array['uuid'],
  'workspace retry and recovery projection exists'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.claim_production_website_repository_provisioning_v1(uuid,uuid,uuid,uuid,text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.claim_production_website_repository_provisioning_v1(uuid,uuid,uuid,uuid,text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.claim_production_website_repository_provisioning_v1(uuid,uuid,uuid,uuid,text,text,text)',
    'EXECUTE'
  ),
  'only authenticated callers can enter the production claim authority'
);

create function pg_temp.commercial_snapshot()
returns jsonb
language sql
stable
set search_path = public, pg_catalog
as $$
  select jsonb_build_object(
    'commercial_projects', (select count(*) from public.commercial_projects),
    'project_requirements_boards', (select count(*) from public.project_requirements_boards),
    'project_requirements', (select count(*) from public.project_requirements),
    'payment_evidence', (select count(*) from public.payment_evidence),
    'payment_expectations', (select count(*) from public.payment_expectations),
    'payment_reconciliations', (select count(*) from public.payment_reconciliations),
    'm1_invoice_candidates', (select count(*) from public.sdf_m1_invoice_candidates),
    'm1_invoice_issuances', (select count(*) from public.sdf_m1_invoice_issuances),
    'email_jobs', (select count(*) from public.quote_request_email_jobs),
    'email_orchestrations', (select count(*) from public.quote_request_quotation_email_orchestrations),
    'promotion_events', (select count(*) from public.website_work_context_promotion_events)
  )
$$;

set local session_replication_role = replica;
insert into public.quote_requests(
  id, application_reference, record_classification, request_kind, name, email,
  website_type, budget, timing, description, privacy_consent, status
) values (
  'e1100000-0000-4000-8000-000000000001', 'LWS-AAN-2099-7101',
  'production', 'website', 'Production PRE_PROJECT fixture',
  'production-pre-project@example.test', 'business', 'Onbekend', 'flexible',
  'Technical-only PRE_PROJECT repository fixture.', true, 'approved'
);
insert into public.website_concepts(
  concept_id, quote_request_id, mode, briefing_status, commercially_released,
  concept_status, revision, created_by
) values (
  'e1200000-0000-4000-8000-000000000001',
  'e1100000-0000-4000-8000-000000000001', 'PRE_PROJECT', 'LIMITED', false,
  'ACTIVE', 1,
  (select operator_id from public.commercial_operators
   where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0')
);
insert into public.website_work_contexts(
  website_work_context_id, quote_request_id, concept_id, project_id, phase, revision
) values (
  'e1300000-0000-4000-8000-000000000001',
  'e1100000-0000-4000-8000-000000000001',
  'e1200000-0000-4000-8000-000000000001', null, 'PRE_PROJECT', 1
);
insert into public.website_execution_workspaces(
  website_workspace_id, website_work_context_id, project_id, quote_request_id,
  workspace_state, repository_provider, default_branch, preview_branch,
  created_by, provisioned_by, provisioned_at
) values (
  'e1400000-0000-4000-8000-000000000001',
  'e1300000-0000-4000-8000-000000000001', null,
  'e1100000-0000-4000-8000-000000000001', 'PENDING_REPOSITORY',
  'GITHUB', 'main', null,
  (select operator_id from public.commercial_operators
   where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
  (select operator_id from public.commercial_operators
   where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
  clock_timestamp()
);
set local session_replication_role = origin;

create temporary table commercial_before as
select pg_temp.commercial_snapshot() as value;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'role','authenticated','aal','aal2'
  )::text, true
);

create temporary table production_claim as
select public.claim_production_website_repository_provisioning_v1(
  'e1100000-0000-4000-8000-000000000001',
  'e1400000-0000-4000-8000-000000000001',
  'e1300000-0000-4000-8000-000000000001',
  'e1500000-0000-4000-8000-000000000001',
  'lorenzo-web-solutions/lws-website-starter', '1.0.0', repeat('1', 40)
) as result;

select is((select result->>'result' from production_claim), 'CLAIMED',
  'production PRE_PROJECT without quotation, payment, or project can claim');
select is((select result->>'repository_owner' from production_claim),
  'lorenzo-web-solutions', 'production claim derives the production owner');
select is((select result->>'repository_name' from production_claim),
  'lws-web-e1300000000040008000000000000001',
  'repository name is derived only from the work context');
select is(
  pg_temp.commercial_snapshot(),
  (select value from commercial_before),
  'claim creates no quotation, payment, invoice, mail, project, promotion, or publish authority'
);
select ok(
  (select phase = 'PRE_PROJECT' and project_id is null
   from public.website_work_contexts
   where website_work_context_id = 'e1300000-0000-4000-8000-000000000001')
  and (select commercially_released = false
   from public.website_concepts
   where concept_id = 'e1200000-0000-4000-8000-000000000001'),
  'claim leaves the context PRE_PROJECT and commercially unreleased'
);

select throws_ok(
  $$select public.claim_production_website_repository_provisioning_v1(
    'e1100000-0000-4000-8000-000000000099',
    'e1400000-0000-4000-8000-000000000001',
    'e1300000-0000-4000-8000-000000000001',
    'e1500000-0000-4000-8000-000000000099',
    'lorenzo-web-solutions/lws-website-starter', '1.0.0', repeat('1', 40)
  )$$,
  '42501', 'PRODUCTION_REPOSITORY_CONTEXT_DENIED',
  'cross-dossier production claim is denied before provider work'
);

select public.record_website_repository_external_identity_v1(
  (select (result->>'operation_id')::uuid from production_claim),
  '1369007101', 'R_production_pre_project_fixture'
);
select public.bind_production_website_repository_v1(
  'e1100000-0000-4000-8000-000000000001',
  (select (result->>'operation_id')::uuid from production_claim),
  jsonb_build_object(
    'operation_id', (select result->>'operation_id' from production_claim),
    'website_workspace_id', 'e1400000-0000-4000-8000-000000000001',
    'website_work_context_id', 'e1300000-0000-4000-8000-000000000001',
    'repository_external_id', '1369007101',
    'repository_node_id', 'R_production_pre_project_fixture',
    'repository_owner', 'lorenzo-web-solutions',
    'repository_name', 'lws-web-e1300000000040008000000000000001',
    'repository_visibility', 'private',
    'default_branch', 'main',
    'starter_source', 'lorenzo-web-solutions/lws-website-starter',
    'starter_version', '1.0.0',
    'starter_commit_sha', repeat('1', 40),
    'repository_marker_commit_sha', repeat('2', 40)
  )
);
select ok(
  (select workspace_state = 'REPOSITORY_READY'
      and repository_owner = 'lorenzo-web-solutions'
      and repository_name = 'lws-web-e1300000000040008000000000000001'
      and last_commit_sha = repeat('2', 40)
      and project_id is null
   from public.website_execution_workspaces
   where website_workspace_id = 'e1400000-0000-4000-8000-000000000001'),
  'verified bind makes Project Files ready with an initial commit and no project'
);
select is(
  pg_temp.commercial_snapshot(),
  (select value from commercial_before),
  'bind creates no commercial or publication side effect'
);
select is(
  public.claim_production_website_repository_provisioning_v1(
    'e1100000-0000-4000-8000-000000000001',
    'e1400000-0000-4000-8000-000000000001',
    'e1300000-0000-4000-8000-000000000001',
    'e1500000-0000-4000-8000-000000000001',
    'lorenzo-web-solutions/lws-website-starter', '1.0.0', repeat('1', 40)
  )->>'result',
  'REPLAY', 'duplicate production command replays without a second repository claim'
);

set local session_replication_role = replica;
insert into public.quote_requests(
  id, application_reference, record_classification, request_kind, name, email,
  website_type, budget, timing, description, privacy_consent, status
) values (
  'e1110000-0000-4000-8000-000000000002', 'LWS-AAN-2099-7102',
  'production', 'website', 'Production recovery guard fixture',
  'production-recovery-guard@example.test', 'business', 'Onbekend', 'flexible',
  'No-second-create production fixture.', true, 'approved'
);
insert into public.website_concepts(
  concept_id, quote_request_id, mode, briefing_status, commercially_released,
  concept_status, revision, created_by
) values (
  'e1200000-0000-4000-8000-000000000002',
  'e1110000-0000-4000-8000-000000000002', 'PRE_PROJECT', 'LIMITED', false,
  'ACTIVE', 1,
  (select operator_id from public.commercial_operators
   where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0')
);
insert into public.website_work_contexts(
  website_work_context_id, quote_request_id, concept_id, project_id, phase, revision
) values (
  'e1300000-0000-4000-8000-000000000002',
  'e1110000-0000-4000-8000-000000000002',
  'e1200000-0000-4000-8000-000000000002', null, 'PRE_PROJECT', 1
);
insert into public.website_execution_workspaces(
  website_workspace_id, website_work_context_id, project_id, quote_request_id,
  workspace_state, repository_provider, default_branch, preview_branch,
  created_by, provisioned_by, provisioned_at
) values (
  'e1400000-0000-4000-8000-000000000002',
  'e1300000-0000-4000-8000-000000000002', null,
  'e1110000-0000-4000-8000-000000000002', 'PENDING_REPOSITORY',
  'GITHUB', 'main', null,
  (select operator_id from public.commercial_operators
   where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
  (select operator_id from public.commercial_operators
   where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
  clock_timestamp()
);
set local session_replication_role = origin;

create temporary table production_recovery_guard_claim as
select public.claim_production_website_repository_provisioning_v1(
  'e1110000-0000-4000-8000-000000000002',
  'e1400000-0000-4000-8000-000000000002',
  'e1300000-0000-4000-8000-000000000002',
  'e1500000-0000-4000-8000-000000000002',
  'lorenzo-web-solutions/lws-website-starter', '1.0.0', repeat('1', 40)
) as result;
select public.record_website_repository_external_identity_v1(
  (select (result->>'operation_id')::uuid from production_recovery_guard_claim),
  '1369007102', 'R_production_recovery_guard'
);
select public.fail_website_repository_provisioning_v1(
  (select (result->>'operation_id')::uuid from production_recovery_guard_claim),
  'REPOSITORY_PROVIDER_FAILED', null
);

select throws_ok(
  $$select public.claim_production_website_repository_provisioning_v1(
    'e1110000-0000-4000-8000-000000000002',
    'e1400000-0000-4000-8000-000000000002',
    'e1300000-0000-4000-8000-000000000002',
    'e1500000-0000-4000-8000-000000000099',
    'lorenzo-web-solutions/lws-website-starter', '1.0.0', repeat('1', 40)
  )$$,
  'P0001', 'PRODUCTION_REPOSITORY_RECOVERY_REQUIRED',
  'fresh production claim is denied after durable external identity'
);
select results_eq(
  $$select count(*)::integer,
      count(*) filter (where state='TERMINAL_FAILED')::integer,
      count(*) filter (where repository_external_id=1369007102)::integer
    from public.website_repository_provisioning_operations
    where website_workspace_id='e1400000-0000-4000-8000-000000000002'$$,
  $$values (1,1,1)$$,
  'recovery-required denial creates no second operation and preserves identity'
);
select is(
  public.claim_production_website_repository_provisioning_v1(
    'e1110000-0000-4000-8000-000000000002',
    'e1400000-0000-4000-8000-000000000002',
    'e1300000-0000-4000-8000-000000000002',
    'e1500000-0000-4000-8000-000000000002',
    'lorenzo-web-solutions/lws-website-starter', '1.0.0', repeat('1', 40)
  )->>'result',
  'REPLAY', 'the original command remains an idempotent terminal replay'
);

create temporary table production_recovery_authority as
select public.get_production_website_repository_recovery_authority_v1(
  'e1110000-0000-4000-8000-000000000002',
  'e1300000-0000-4000-8000-000000000002',
  'e1400000-0000-4000-8000-000000000002'
) as result;
select results_eq(
  $$select result->>'operation_id', result->>'repository_external_id',
      result->>'repository_node_id', result->>'repository_owner'
    from production_recovery_authority$$,
  $$select result->>'operation_id', '1369007102',
      'R_production_recovery_guard', 'lorenzo-web-solutions'
    from production_recovery_guard_claim$$,
  'recovery authority derives the exact durable operation and repository identity'
);
select ok(
  (public.get_website_execution_workspace_v5(
    'e1110000-0000-4000-8000-000000000002'
  ) #>> '{workspace,capabilities,repository_recovery_required}')::boolean
  and not (public.get_website_execution_workspace_v5(
    'e1110000-0000-4000-8000-000000000002'
  ) #>> '{workspace,capabilities,repository_retry_allowed}')::boolean
  and public.get_website_execution_workspace_v5(
    'e1110000-0000-4000-8000-000000000002'
  ) #>> '{workspace,repository_recovery_operation_id}' =
    (select result->>'operation_id' from production_recovery_guard_claim),
  'workspace projection suppresses retry and selects recovery server-side'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object('role','service_role')::text, true
);
select public.finalize_production_website_repository_recovery_v1(
  'e1110000-0000-4000-8000-000000000002',
  (select (result->>'operation_id')::uuid from production_recovery_guard_claim),
  jsonb_build_object(
    'operation_id', (select result->>'operation_id' from production_recovery_guard_claim),
    'website_workspace_id', 'e1400000-0000-4000-8000-000000000002',
    'website_work_context_id', 'e1300000-0000-4000-8000-000000000002',
    'repository_external_id', '1369007102',
    'repository_node_id', 'R_production_recovery_guard',
    'repository_owner', 'lorenzo-web-solutions',
    'repository_name', 'lws-web-e1300000000040008000000000000002',
    'repository_visibility', 'private',
    'default_branch', 'main',
    'starter_source', 'lorenzo-web-solutions/lws-website-starter',
    'starter_version', '1.0.0',
    'starter_commit_sha', repeat('1', 40),
    'repository_marker_commit_sha', repeat('3', 40)
  ),
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'aal2'
);
select ok(
  (select state = 'BOUND' and failure_code is null
   from public.website_repository_provisioning_operations
   where operation_id =
     (select (result->>'operation_id')::uuid from production_recovery_guard_claim))
  and (select workspace_state = 'REPOSITORY_READY'
      and repository_external_id = 1369007102
      and repository_node_id = 'R_production_recovery_guard'
      and repository_marker_commit_sha = repeat('3', 40)
      and last_commit_sha = repeat('3', 40)
      and project_id is null
    from public.website_execution_workspaces
    where website_workspace_id = 'e1400000-0000-4000-8000-000000000002'),
  'service-only recovery finalization binds the existing repository and initial commit atomically'
);
select is(
  pg_temp.commercial_snapshot(),
  (select value from commercial_before),
  'production recovery creates no commercial or publication side effect'
);

select * from finish();
rollback;
