begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

create function pg_temp.lineage_commercial_snapshot()
returns jsonb
language sql
stable
set search_path = public, pg_catalog
as $$
  select jsonb_build_object(
    'commercial_projects', (select count(*) from public.commercial_projects),
    'payment_evidence', (select count(*) from public.payment_evidence),
    'payment_expectations', (select count(*) from public.payment_expectations),
    'm1_invoice_issuances', (select count(*) from public.sdf_m1_invoice_issuances),
    'promotion_events', (select count(*) from public.website_work_context_promotion_events)
  )
$$;

create temporary table lineage_commercial_before as
select pg_temp.lineage_commercial_snapshot() as value;

set local session_replication_role = replica;

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind, name, email,
  website_type, budget, timing, description, privacy_consent, status
) values
  ('f1100000-0000-4000-8000-000000000001', 'LWS-AAN-2099-7201',
   'production', 'website', 'Three-operation lineage fixture',
   'lineage@example.test', 'business', 'Onbekend', 'flexible',
   'Canonical durable repository lineage.', true, 'approved'),
  ('f1110000-0000-4000-8000-000000000002', 'LWS-AAN-2099-7202',
   'production', 'website', 'Ambiguous lineage fixture',
   'lineage-ambiguous@example.test', 'business', 'Onbekend', 'flexible',
   'Conflicting durable repository lineage.', true, 'approved');

insert into public.website_concepts(
  concept_id, quote_request_id, mode, briefing_status, commercially_released,
  concept_status, revision, created_by
) values
  ('f1200000-0000-4000-8000-000000000001',
   'f1100000-0000-4000-8000-000000000001', 'PRE_PROJECT', 'LIMITED', false,
   'ACTIVE', 1, (select operator_id from public.commercial_operators
     where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0')),
  ('f1200000-0000-4000-8000-000000000002',
  'f1110000-0000-4000-8000-000000000002', 'PRE_PROJECT', 'LIMITED', false,
   'ACTIVE', 1, (select operator_id from public.commercial_operators
     where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'));

insert into public.website_work_contexts(
  website_work_context_id, quote_request_id, concept_id, project_id, phase, revision
) values
  ('f1300000-0000-4000-8000-000000000001',
   'f1100000-0000-4000-8000-000000000001',
   'f1200000-0000-4000-8000-000000000001', null, 'PRE_PROJECT', 1),
  ('f1300000-0000-4000-8000-000000000002',
  'f1110000-0000-4000-8000-000000000002',
   'f1200000-0000-4000-8000-000000000002', null, 'PRE_PROJECT', 1);

insert into public.website_execution_workspaces(
  website_workspace_id, website_work_context_id, project_id, quote_request_id,
  workspace_state, repository_provider, default_branch, preview_branch,
  created_by, provisioned_by, provisioned_at
) values
  ('f1400000-0000-4000-8000-000000000001',
   'f1300000-0000-4000-8000-000000000001', null,
   'f1100000-0000-4000-8000-000000000001', 'REPOSITORY_FAILED',
   'GITHUB', 'main', null,
   (select operator_id from public.commercial_operators
     where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
   (select operator_id from public.commercial_operators
     where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'), clock_timestamp()),
  ('f1400000-0000-4000-8000-000000000002',
   'f1300000-0000-4000-8000-000000000002', null,
  'f1110000-0000-4000-8000-000000000002', 'REPOSITORY_FAILED',
   'GITHUB', 'main', null,
   (select operator_id from public.commercial_operators
     where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
   (select operator_id from public.commercial_operators
     where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'), clock_timestamp());

insert into public.website_repository_provisioning_operations(
  operation_id, website_workspace_id, website_work_context_id, actor_id,
  idempotency_key, request_fingerprint, repository_provider,
  repository_owner, repository_name, starter_source, starter_version,
  starter_commit_sha, state, attempt_count, failure_code, first_attempt_at,
  retry_window_expires_at, claimed_at, updated_at, repository_external_id,
  repository_node_id, external_created_at
) values
  ('f1500000-0000-4000-8000-000000000001',
   'f1400000-0000-4000-8000-000000000001',
   'f1300000-0000-4000-8000-000000000001',
   (select operator_id from public.commercial_operators
     where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
   'f1600000-0000-4000-8000-000000000001', repeat('1',64), 'GITHUB',
   'lorenzo-web-solutions', 'lws-web-f1300000000040008000000000000001',
   'lorenzo-web-solutions/lws-website-starter', '1.0.0', repeat('1',40),
   'TERMINAL_FAILED', 1, 'REPOSITORY_PROVIDER_FAILED',
  '2026-01-01 10:00:00+00', '2026-01-02 10:00:00+00',
  '2026-01-01 10:00:00+00', '2026-01-01 10:05:00+00', null, null, null),
  ('f1500000-0000-4000-8000-000000000002',
   'f1400000-0000-4000-8000-000000000001',
   'f1300000-0000-4000-8000-000000000001',
   (select operator_id from public.commercial_operators
     where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
   'f1600000-0000-4000-8000-000000000002',
   encode(extensions.digest(convert_to(jsonb_build_object(
     'authority_version', 'website_repository_provisioning_v1',
     'website_workspace_id', 'f1400000-0000-4000-8000-000000000001'::uuid,
     'website_work_context_id', 'f1300000-0000-4000-8000-000000000001'::uuid,
     'repository_name', 'lws-web-f1300000000040008000000000000001',
     'starter_source', 'lorenzo-web-solutions/lws-website-starter',
     'starter_version', '1.0.0',
     'starter_commit_sha', repeat('1',40)
   )::text, 'UTF8'), 'sha256'), 'hex')::character(64), 'GITHUB',
   'lorenzo-web-solutions', 'lws-web-f1300000000040008000000000000001',
   'lorenzo-web-solutions/lws-website-starter', '1.0.0', repeat('1',40),
   'TERMINAL_FAILED', 1, 'REPOSITORY_PROVIDER_FAILED',
  '2026-01-01 11:00:00+00', '2026-01-02 11:00:00+00',
  '2026-01-01 11:00:00+00', '2026-01-01 11:05:00+00',
  1378797607, 'R_kgDOUi7IJw', '2026-01-01 11:03:00+00'),
  ('f1500000-0000-4000-8000-000000000003',
   'f1400000-0000-4000-8000-000000000001',
   'f1300000-0000-4000-8000-000000000001',
   (select operator_id from public.commercial_operators
     where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
   'f1600000-0000-4000-8000-000000000003', repeat('3',64), 'GITHUB',
   'lorenzo-web-solutions', 'lws-web-f1300000000040008000000000000001',
   'lorenzo-web-solutions/lws-website-starter', '1.0.0', repeat('1',40),
   'TERMINAL_FAILED', 1, 'REPOSITORY_PROVIDER_FAILED',
  '2026-01-01 12:00:00+00', '2026-01-02 12:00:00+00',
  '2026-01-01 12:00:00+00', '2026-01-01 12:05:00+00', null, null, null),
  ('f1500000-0000-4000-8000-000000000011',
   'f1400000-0000-4000-8000-000000000002',
   'f1300000-0000-4000-8000-000000000002',
   (select operator_id from public.commercial_operators
     where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
   'f1600000-0000-4000-8000-000000000011', repeat('a',64), 'GITHUB',
   'lorenzo-web-solutions', 'lws-web-conflict-a',
   'lorenzo-web-solutions/lws-website-starter', '1.0.0', repeat('1',40),
   'TERMINAL_FAILED', 1, 'REPOSITORY_PROVIDER_FAILED',
  '2026-01-01 10:00:00+00', '2026-01-02 10:00:00+00',
  '2026-01-01 10:00:00+00', '2026-01-01 10:05:00+00',
  1378797611, 'R_conflict_a', '2026-01-01 10:03:00+00'),
  ('f1500000-0000-4000-8000-000000000012',
   'f1400000-0000-4000-8000-000000000002',
   'f1300000-0000-4000-8000-000000000002',
   (select operator_id from public.commercial_operators
     where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
   'f1600000-0000-4000-8000-000000000012', repeat('b',64), 'GITHUB',
   'lorenzo-web-solutions', 'lws-web-conflict-b',
   'lorenzo-web-solutions/lws-website-starter', '1.0.0', repeat('1',40),
   'TERMINAL_FAILED', 1, 'REPOSITORY_PROVIDER_FAILED',
  '2026-01-01 11:00:00+00', '2026-01-02 11:00:00+00',
  '2026-01-01 11:00:00+00', '2026-01-01 11:05:00+00',
  1378797612, 'R_conflict_b', '2026-01-01 11:03:00+00');

set local session_replication_role = origin;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'role','authenticated','aal','aal2'
)::text, true);

select throws_ok(
  $$select public.claim_production_website_repository_provisioning_v1(
    'f1100000-0000-4000-8000-000000000001',
    'f1400000-0000-4000-8000-000000000001',
    'f1300000-0000-4000-8000-000000000001',
    'f1600000-0000-4000-8000-000000000099',
    'lorenzo-web-solutions/lws-website-starter','1.0.0',repeat('1',40)
  )$$,
  'P0001', 'PRODUCTION_REPOSITORY_RECOVERY_REQUIRED',
  'fresh claim is denied when an older lineage operation owns durable identity'
);
select is(
  (select count(*)::integer from public.website_repository_provisioning_operations
   where website_workspace_id='f1400000-0000-4000-8000-000000000001'),
  3, 'fresh denial creates no fourth operation'
);

-- Regression: exact idempotent replay. Replaying the exact same actor +
-- idempotency_key that already produced durable operation B must remain
-- possible and must not create a new operation or reach CREATE_REPOSITORY.
select lives_ok(
  $$select public.claim_production_website_repository_provisioning_v1(
    'f1100000-0000-4000-8000-000000000001',
    'f1400000-0000-4000-8000-000000000001',
    'f1300000-0000-4000-8000-000000000001',
    'f1600000-0000-4000-8000-000000000002',
    'lorenzo-web-solutions/lws-website-starter','1.0.0',repeat('1',40)
  )$$,
  'exact idempotent replay of an existing durable-identity operation remains possible'
);
select is(
  (select count(*)::integer from public.website_repository_provisioning_operations
   where website_workspace_id='f1400000-0000-4000-8000-000000000001'),
  3, 'exact idempotent replay creates no new operation'
);
select is(
  (select state from public.website_repository_provisioning_operations
   where operation_id='f1500000-0000-4000-8000-000000000002'),
  'TERMINAL_FAILED',
  'exact idempotent replay has no CREATE_REPOSITORY side effect on operation B'
);

create temporary table canonical_recovery as
select public.get_production_website_repository_recovery_authority_v1(
  'f1100000-0000-4000-8000-000000000001',
  'f1300000-0000-4000-8000-000000000001',
  'f1400000-0000-4000-8000-000000000001'
) as result;

select is((select result->>'operation_id' from canonical_recovery),
  'f1500000-0000-4000-8000-000000000002',
  'recovery authority selects the canonical durable operation B');
select is((select result->>'repository_external_id' from canonical_recovery),
  '1378797607', 'canonical external repository identity is preserved');
select ok(
  (public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #>> '{workspace,capabilities,repository_recovery_required}')::boolean
  and not (public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #>> '{workspace,capabilities,repository_retry_allowed}')::boolean
  and public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #>> '{workspace,repository_recovery_operation_id}' =
    'f1500000-0000-4000-8000-000000000002',
  'three-operation workspace is recovery-required against operation B'
);
select results_eq(
  $$select value from (values
      (public.get_website_execution_workspace_v5(
        'f1100000-0000-4000-8000-000000000001'
      ) #>> '{workspace,repository_operation_state}'),
      (public.get_website_execution_workspace_v5(
        'f1100000-0000-4000-8000-000000000001'
      ) #>> '{workspace,repository_failure_category}'),
      (public.get_website_execution_workspace_v5(
        'f1100000-0000-4000-8000-000000000001'
      ) #>> '{workspace,repository_recovery_guidance}')
    ) as expected(value)$$,
  $$values ('TERMINAL_FAILED'),('TERMINAL'),('CONTACT_OWNER')$$,
  'pre-recovery v3/v4/v5 projection uses canonical durable failure semantics'
);

select throws_ok(
  $$select public.get_production_website_repository_recovery_authority_v1(
    'f1110000-0000-4000-8000-000000000002',
    'f1300000-0000-4000-8000-000000000002',
    'f1400000-0000-4000-8000-000000000002'
  )$$,
  'P0001', 'PRODUCTION_REPOSITORY_RECOVERY_RECONCILIATION_REQUIRED',
  'conflicting durable repository identities fail recovery closed'
);
select throws_ok(
  $$select public.get_website_execution_workspace_v5(
    'f1110000-0000-4000-8000-000000000002'
  )$$,
  'P0001', 'PRODUCTION_REPOSITORY_RECOVERY_RECONCILIATION_REQUIRED',
  'conflicting durable repository identities fail projection closed'
);
select is(
  (select count(*)::integer from public.website_repository_provisioning_operations
   where website_workspace_id='f1400000-0000-4000-8000-000000000002'),
  2, 'ambiguity checks perform no write'
);

-- Regression: a fresh production provisioning claim against a lineage
-- already holding two conflicting durable repository identities must be
-- rejected fail-closed, must not create a third operation, must not
-- create a repository, and must not mutate the workspace.
select throws_ok(
  $$select public.claim_production_website_repository_provisioning_v1(
    'f1110000-0000-4000-8000-000000000002',
    'f1400000-0000-4000-8000-000000000002',
    'f1300000-0000-4000-8000-000000000002',
    'f1600000-0000-4000-8000-000000000098',
    'lorenzo-web-solutions/lws-website-starter','1.0.0',repeat('1',40)
  )$$,
  'P0001', 'PRODUCTION_REPOSITORY_RECOVERY_REQUIRED',
  'fresh claim against conflicting durable identities is rejected fail-closed'
);
select is(
  (select count(*)::integer from public.website_repository_provisioning_operations
   where website_workspace_id='f1400000-0000-4000-8000-000000000002'),
  2, 'rejected conflicting-identity claim creates no additional operation'
);
select is(
  (select workspace_state from public.website_execution_workspaces
   where website_workspace_id='f1400000-0000-4000-8000-000000000002'),
  'REPOSITORY_FAILED',
  'rejected conflicting-identity claim performs no workspace mutation'
);

select set_config('request.jwt.claims', jsonb_build_object(
  'role','service_role'
)::text, true);
select throws_ok(
  $$select public.finalize_production_website_repository_recovery_v1(
    'f1110000-0000-4000-8000-000000000002',
    'f1500000-0000-4000-8000-000000000011',
    '{}'::jsonb,
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','aal2'
  )$$,
  'P0001', 'PRODUCTION_REPOSITORY_RECOVERY_RECONCILIATION_REQUIRED',
  'conflicting durable identities block finalization before any write'
);
select results_eq(
  $$select operation_id::text,state,failure_code
    from public.website_repository_provisioning_operations
    where website_workspace_id='f1400000-0000-4000-8000-000000000002'
    order by operation_id$$,
  $$values
    ('f1500000-0000-4000-8000-000000000011','TERMINAL_FAILED','REPOSITORY_PROVIDER_FAILED'),
    ('f1500000-0000-4000-8000-000000000012','TERMINAL_FAILED','REPOSITORY_PROVIDER_FAILED')$$,
  'ambiguity-blocked finalization preserves both operations unchanged'
);

-- Regression: finalizing using a non-canonical operation_id (operation A,
-- an older identity-free TERMINAL_FAILED operation in the same lineage as
-- canonical durable operation B) must fail closed, must not mutate the
-- canonical operation, and must not mutate the workspace.
select throws_ok(
  $$select public.finalize_production_website_repository_recovery_v1(
    'f1100000-0000-4000-8000-000000000001',
    'f1500000-0000-4000-8000-000000000001',
    '{}'::jsonb,
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','aal2'
  )$$,
  '42501', 'PRODUCTION_REPOSITORY_RECOVERY_OPERATION_DENIED',
  'finalizing a non-canonical operation id fails closed'
);
select results_eq(
  $$select operation_id::text,state,failure_code
    from public.website_repository_provisioning_operations
    where website_workspace_id='f1400000-0000-4000-8000-000000000001'
    order by operation_id$$,
  $$values
    ('f1500000-0000-4000-8000-000000000001','TERMINAL_FAILED','REPOSITORY_PROVIDER_FAILED'),
    ('f1500000-0000-4000-8000-000000000002','TERMINAL_FAILED','REPOSITORY_PROVIDER_FAILED'),
    ('f1500000-0000-4000-8000-000000000003','TERMINAL_FAILED','REPOSITORY_PROVIDER_FAILED')$$,
  'non-canonical finalize attempt leaves all three lineage operations unchanged'
);
select is(
  (select workspace_state from public.website_execution_workspaces
   where website_workspace_id='f1400000-0000-4000-8000-000000000001'),
  'REPOSITORY_FAILED',
  'non-canonical finalize attempt performs no workspace mutation'
);

select lives_ok(
  $$select public.finalize_production_website_repository_recovery_v1(
    'f1100000-0000-4000-8000-000000000001',
    'f1500000-0000-4000-8000-000000000002',
    jsonb_build_object(
      'operation_id','f1500000-0000-4000-8000-000000000002',
      'website_workspace_id','f1400000-0000-4000-8000-000000000001',
      'website_work_context_id','f1300000-0000-4000-8000-000000000001',
      'repository_external_id','1378797607',
      'repository_node_id','R_kgDOUi7IJw',
      'repository_owner','lorenzo-web-solutions',
      'repository_name','lws-web-f1300000000040008000000000000001',
      'repository_visibility','private','default_branch','main',
      'starter_source','lorenzo-web-solutions/lws-website-starter',
      'starter_version','1.0.0','starter_commit_sha',repeat('1',40),
      'repository_marker_commit_sha',repeat('9',40)
    ),
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0','aal2'
  )$$,
  'canonical durable operation B can be finalized'
);

select results_eq(
  $$select operation_id::text,state,failure_code
    from public.website_repository_provisioning_operations
    where operation_id in (
      'f1500000-0000-4000-8000-000000000002',
      'f1500000-0000-4000-8000-000000000003'
    ) order by operation_id$$,
  $$values
    ('f1500000-0000-4000-8000-000000000002','BOUND',null::text),
    ('f1500000-0000-4000-8000-000000000003','TERMINAL_FAILED','REPOSITORY_PROVIDER_FAILED')$$,
  'finalization binds B while preserving later historical operation C unchanged'
);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub','c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'role','authenticated','aal','aal2'
)::text, true);

select ok(
  public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #>> '{workspace,repository_operation_state}' = 'COMPLETE'
  and public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #> '{workspace,repository_failure_category}' = 'null'::jsonb
  and public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #> '{workspace,repository_recovery_guidance}' = 'null'::jsonb,
  'post-bind v3/v4/v5 projection reports complete without failure guidance'
);
select ok(
  (public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #>> '{workspace,capabilities,project_files_read}')::boolean
  and (public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #>> '{workspace,capabilities,project_files_write}')::boolean,
  'Project Files read and write capabilities are eligible after canonical bind'
);
create temporary table canonical_read_lease as
select public.acquire_website_project_files_read_v1(
  'f1100000-0000-4000-8000-000000000001', 'FILE'
) as result;
create temporary table canonical_write_lease as
select public.acquire_website_project_files_write_v1(
  'f1100000-0000-4000-8000-000000000001',
  'pages/index.html', repeat('9',40),
  'f1600000-0000-4000-8000-000000000020'
) as result;
select is(
  (select result->>'markerOperationId' from canonical_read_lease),
  'f1500000-0000-4000-8000-000000000002',
  'Project Files read acquisition binds its lease to canonical operation B'
);
select is(
  (select result->>'markerOperationId' from canonical_write_lease),
  'f1500000-0000-4000-8000-000000000002',
  'Project Files write acquisition binds its lease to canonical operation B'
);
select ok(
  not (public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #>> '{workspace,capabilities,repository_retry_allowed}')::boolean
  and not (public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #>> '{workspace,capabilities,repository_recovery_required}')::boolean
  and public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #> '{workspace,repository_recovery_operation_id}' = 'null'::jsonb,
  'post-bind projection exposes neither retry nor recovery action'
);

-- Regression: adversarial updated_at shadowing. After canonical operation
-- B is bound, force a later historical identity-free operation C's
-- updated_at strictly after B's updated_at (simulating any out-of-band
-- touch to C's row). Canonical resolution must remain durable-identity
-- based, not timestamp based, so B must continue to be resolved by every
-- consumer and CREATE_REPOSITORY must remain unreachable.
select set_config('lws.website_repository_command', 'on', true);
update public.website_repository_provisioning_operations
set updated_at = (
  select updated_at from public.website_repository_provisioning_operations
  where operation_id = 'f1500000-0000-4000-8000-000000000002'
) + interval '1 hour'
where operation_id = 'f1500000-0000-4000-8000-000000000003';
select set_config('lws.website_repository_command', '', true);
select ok(
  (select updated_at from public.website_repository_provisioning_operations
   where operation_id = 'f1500000-0000-4000-8000-000000000003')
  > (select updated_at from public.website_repository_provisioning_operations
     where operation_id = 'f1500000-0000-4000-8000-000000000002'),
  'adversarial fixture: C.updated_at now strictly newer than B.updated_at'
);
select is(
  (select workspace_state from public.website_execution_workspaces
   where website_workspace_id = 'f1400000-0000-4000-8000-000000000001'),
  'REPOSITORY_READY',
  'timestamp-shadowed lineage leaves workspace_state REPOSITORY_READY'
);
select is(
  (select repository_state from public.website_execution_workspaces
   where website_workspace_id = 'f1400000-0000-4000-8000-000000000001'),
  'BOUND',
  'timestamp-shadowed lineage leaves repository_state BOUND'
);
select ok(
  public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #>> '{workspace,workspace_state}' = 'REPOSITORY_READY'
  and public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #>> '{workspace,repository_operation_state}' = 'COMPLETE'
  and public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #> '{workspace,repository_failure_category}' = 'null'::jsonb
  and public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #> '{workspace,repository_recovery_guidance}' = 'null'::jsonb
  and not (public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #>> '{workspace,capabilities,repository_retry_allowed}')::boolean
  and not (public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #>> '{workspace,capabilities,repository_recovery_required}')::boolean
  and public.get_website_execution_workspace_v5(
    'f1100000-0000-4000-8000-000000000001'
  ) #> '{workspace,repository_recovery_operation_id}' = 'null'::jsonb,
  'timestamp-shadowed lineage still projects canonical B as complete and bound'
);
select throws_ok(
  $$select public.claim_production_website_repository_provisioning_v1(
    'f1100000-0000-4000-8000-000000000001',
    'f1400000-0000-4000-8000-000000000001',
    'f1300000-0000-4000-8000-000000000001',
    'f1600000-0000-4000-8000-000000000097',
    'lorenzo-web-solutions/lws-website-starter','1.0.0',repeat('1',40)
  )$$,
  'P0001', 'PRODUCTION_REPOSITORY_RECOVERY_REQUIRED',
  'CREATE_REPOSITORY remains unreachable once a durable identity is bound, even under timestamp shadowing'
);
create temporary table shadowed_read_lease as
select public.acquire_website_project_files_read_v1(
  'f1100000-0000-4000-8000-000000000001', 'FILE'
) as result;
create temporary table shadowed_write_lease as
select public.acquire_website_project_files_write_v1(
  'f1100000-0000-4000-8000-000000000001',
  'pages/about.html', repeat('9',40),
  'f1600000-0000-4000-8000-000000000021'
) as result;
select is(
  (select result->>'markerOperationId' from shadowed_read_lease),
  'f1500000-0000-4000-8000-000000000002',
  'Project Files read continues to bind to canonical operation B despite C.updated_at shadowing'
);
select is(
  (select result->>'markerOperationId' from shadowed_write_lease),
  'f1500000-0000-4000-8000-000000000002',
  'Project Files write continues to bind to canonical operation B despite C.updated_at shadowing'
);
select is(
  (select state from public.website_repository_provisioning_operations
   where operation_id = 'f1500000-0000-4000-8000-000000000003'),
  'TERMINAL_FAILED',
  'shadowing operation C remains unbound historical evidence'
);

select is(
  pg_temp.lineage_commercial_snapshot(),
  (select value from lineage_commercial_before),
  'lineage recovery creates no commercial side effects'
);

select * from finish();
rollback;