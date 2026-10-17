begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public',
  'open_existing_website_project_preview_v1',
  array['uuid', 'text'],
  'preview reopen RPC exists'
);

select ok(
  (
    select p.prosecdef
      and pg_get_userbyid(p.proowner) = 'postgres'
      and p.proconfig = array['search_path=public, lws_internal, auth, pg_catalog']
    from pg_proc as p
    where p.oid =
      'public.open_existing_website_project_preview_v1(uuid,text)'::regprocedure
  ),
  'preview reopen RPC remains postgres-owned SECURITY DEFINER with safe search_path'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.open_existing_website_project_preview_v1(uuid,text)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.open_existing_website_project_preview_v1(uuid,text)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.open_existing_website_project_preview_v1(uuid,text)',
    'execute'
  ),
  'preview reopen execute remains authenticated-only'
);

select results_eq(
  $$
    select coalesce(role.rolname, 'PUBLIC')::text collate "C"
    from pg_proc as p
    cross join lateral aclexplode(
      coalesce(p.proacl, acldefault('f', p.proowner))
    ) as acl
    left join pg_roles as role on role.oid = acl.grantee
    where p.oid =
      'public.open_existing_website_project_preview_v1(uuid,text)'::regprocedure
      and acl.privilege_type = 'EXECUTE'
    order by 1
  $$,
  $$ values ('authenticated'::text collate "C"), ('postgres'::text collate "C") $$,
  'preview reopen effective EXECUTE ACL has only authenticated and postgres'
);

insert into auth.users(id, email) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'preview-reopen-current-commit@example.test');

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}',
  true
);

set local session_replication_role = replica;

insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status
) values (
  'eec31000-0000-4000-8000-000000000001',
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'Preview reopen current commit owner',
  'owner',
  'ACTIVE'
);

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind, sdf_package,
  created_at, updated_at, name, email, website_type, budget, timing,
  description, privacy_consent, status
) values (
  'eec31000-0000-4000-8000-000000000002',
  'LWS-AAN-2099-9902',
  'production',
  'website',
  null,
  '2026-10-15T00:00:00Z',
  '2026-10-15T00:00:00Z',
  'Synthetic preview reopen current commit test',
  'preview-reopen-current-commit@example.test',
  'business',
  'Meer dan EUR 6.000',
  'flexible',
  'Rollback-only preview reopen current commit fixture.',
  true,
  'approved'
);

insert into public.website_concepts(
  concept_id, quote_request_id, mode, briefing_status, concept_status,
  revision, created_by, created_at, updated_at
) values (
  'eec31000-0000-4000-8000-000000000003',
  'eec31000-0000-4000-8000-000000000002',
  'PRE_PROJECT',
  'LIMITED',
  'ACTIVE',
  1,
  'eec31000-0000-4000-8000-000000000001',
  '2026-10-15T00:01:00Z',
  '2026-10-15T00:01:00Z'
);

insert into public.website_work_contexts(
  website_work_context_id, quote_request_id, concept_id, project_id,
  phase, revision, created_at, updated_at
) values (
  'eec31000-0000-4000-8000-000000000004',
  'eec31000-0000-4000-8000-000000000002',
  'eec31000-0000-4000-8000-000000000003',
  null,
  'PRE_PROJECT',
  1,
  '2026-10-15T00:01:00Z',
  '2026-10-15T00:01:00Z'
);

insert into public.website_execution_workspaces(
  website_workspace_id, website_work_context_id, project_id, quote_request_id,
  workspace_state, repository_provider, repository_owner, repository_name,
  default_branch, last_commit_sha, binding_revision, created_by, provisioned_by,
  provisioned_at, repository_external_id, repository_node_id,
  repository_visibility, repository_state, starter_source, starter_version,
  starter_commit_sha, repository_marker_commit_sha, repository_bound_at,
  created_at, updated_at
) values (
  'eec31000-0000-4000-8000-000000000005',
  'eec31000-0000-4000-8000-000000000004',
  null,
  'eec31000-0000-4000-8000-000000000002',
  'REPOSITORY_READY',
  'GITHUB',
  'lws-repro-fixtures',
  'preview-reopen-current-commit',
  'main',
  repeat('a', 40),
  1,
  'eec31000-0000-4000-8000-000000000001',
  'eec31000-0000-4000-8000-000000000001',
  '2026-10-15T00:10:00Z',
  990003101,
  'R_preview_reopen_current_commit',
  'private',
  'BOUND',
  'lws-repro-fixtures/website-starter',
  '1.0.0',
  repeat('8', 40),
  repeat('9', 40),
  '2026-10-15T00:10:00Z',
  '2026-10-15T00:05:00Z',
  '2026-10-15T00:10:00Z'
);

insert into public.website_repository_provisioning_operations(
  operation_id, website_workspace_id, website_work_context_id, actor_id,
  idempotency_key, request_fingerprint, repository_provider, repository_owner,
  repository_name, starter_source, starter_version, starter_commit_sha, state,
  attempt_count, first_attempt_at, retry_window_expires_at,
  repository_external_id, repository_node_id, claimed_at, updated_at,
  external_created_at, bound_at
) values (
  'eec31000-0000-4000-8000-000000000006',
  'eec31000-0000-4000-8000-000000000005',
  'eec31000-0000-4000-8000-000000000004',
  'eec31000-0000-4000-8000-000000000001',
  'eec31000-0000-4000-8000-000000000025',
  repeat('1', 64),
  'GITHUB',
  'lws-repro-fixtures',
  'preview-reopen-current-commit',
  'lws-repro-fixtures/website-starter',
  '1.0.0',
  repeat('8', 40),
  'BOUND',
  1,
  '2026-10-15T00:10:00Z',
  '2026-10-16T00:10:00Z',
  990003101,
  'R_preview_reopen_current_commit',
  '2026-10-15T00:10:00Z',
  '2026-10-15T00:10:00Z',
  '2026-10-15T00:10:00Z',
  '2026-10-15T00:10:00Z'
);

insert into lws_internal.website_project_files_write_leases(
  lease_id, actor_operator_id, actor_auth_user_id, quote_request_id,
  website_work_context_id, website_workspace_id, binding_revision,
  repository_provider, repository_owner, repository_name,
  repository_external_id, repository_node_id, default_branch, repository_ref,
  ref_label, marker_operation_id, write_path, expected_commit_sha,
  idempotency_key, acquired_at, expires_at, finalized_at, finalized_commit_sha,
  finalized_created, released_at
) values (
  'eec31000-0000-4000-8000-000000000007',
  'eec31000-0000-4000-8000-000000000001',
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'eec31000-0000-4000-8000-000000000002',
  'eec31000-0000-4000-8000-000000000004',
  'eec31000-0000-4000-8000-000000000005',
  1, 'GITHUB', 'lws-repro-fixtures', 'preview-reopen-current-commit',
  990003101, 'R_preview_reopen_current_commit', 'main', 'heads/main', 'main',
  'eec31000-0000-4000-8000-000000000006', 'src/index.html',
  repeat('a', 40), 'eec31000-0000-4000-8000-000000000026',
  '2026-10-15T00:20:00Z', '2026-10-15T00:20:30Z',
  '2026-10-15T00:20:10Z', repeat('a', 40), true,
  '2026-10-15T00:20:15Z'
);

insert into lws_internal.website_project_preview_build_leases(
  preview_lease_id, source_write_lease_id, actor_auth_user_id, quote_request_id,
  website_work_context_id, website_workspace_id, expected_commit_sha,
  acquired_at, expires_at, released_at, authorized_build_id
) values (
  'eec31000-0000-4000-8000-000000000008',
  'eec31000-0000-4000-8000-000000000007',
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'eec31000-0000-4000-8000-000000000002',
  'eec31000-0000-4000-8000-000000000004',
  'eec31000-0000-4000-8000-000000000005',
  repeat('a', 40),
  '2026-10-15T00:20:15Z',
  '2026-10-15T00:25:15Z',
  null,
  'eec31000-0000-4000-8000-000000000009'
);

insert into lws_internal.website_project_preview_builds(
  preview_build_id, lease_id, actor_auth_user_id, quote_request_id,
  website_work_context_id, website_workspace_id, commit_sha, artifact_path,
  artifact_sha256, artifact_bytes, build_status, built_at
) values (
  'eec31000-0000-4000-8000-000000000009',
  'eec31000-0000-4000-8000-000000000008',
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'eec31000-0000-4000-8000-000000000002',
  'eec31000-0000-4000-8000-000000000004',
  'eec31000-0000-4000-8000-000000000005',
  repeat('a', 40),
  'preview/current-pass.tar',
  repeat('a', 64),
  100,
  'PASS',
  '2026-10-15T00:21:00Z'
);

insert into lws_internal.website_project_preview_build_artifacts(
  artifact_id, preview_build_id, relative_path, content_type, sha256, bytes,
  created_at
) values (
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'eec31000-0000-4000-8000-000000000009',
  'index.html', 'text/html', repeat('a', 64), 100,
  '2026-10-15T00:21:00Z'
);

set local session_replication_role = origin;

select count(*)::integer as pass_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select public.open_existing_website_project_preview_v1(
  'eec31000-0000-4000-8000-000000000002',
  repeat('1', 64)
) as pass_response
\gset
reset role;
select count(*)::integer as pass_after
from lws_internal.website_project_preview_sessions
\gset

select is(:pass_before::integer, 0, 'current PASS starts without sessions');
select is(:pass_after::integer, 1, 'current PASS creates exactly one session');
select is(
  :'pass_response'::jsonb->>'previewBuildId',
  'eec31000-0000-4000-8000-000000000009',
  'current PASS returns the current build'
);
select ok(
  (:'pass_response'::jsonb->>'isCurrentCommit')::boolean
  and :'pass_response'::jsonb->>'builtCommitSha' = repeat('a', 40)
  and :'pass_response'::jsonb->>'currentCommitSha' = repeat('a', 40),
  'current PASS response preserves the Edge current-commit contract'
);

set local session_replication_role = replica;
insert into lws_internal.website_project_files_write_leases(
  lease_id, actor_operator_id, actor_auth_user_id, quote_request_id,
  website_work_context_id, website_workspace_id, binding_revision,
  repository_provider, repository_owner, repository_name,
  repository_external_id, repository_node_id, default_branch, repository_ref,
  ref_label, marker_operation_id, write_path, expected_commit_sha,
  idempotency_key, acquired_at, expires_at, finalized_at, finalized_commit_sha,
  finalized_created, released_at
) values (
  'eec31000-0000-4000-8000-000000000011',
  'eec31000-0000-4000-8000-000000000001',
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'eec31000-0000-4000-8000-000000000002',
  'eec31000-0000-4000-8000-000000000004',
  'eec31000-0000-4000-8000-000000000005',
  1, 'GITHUB', 'lws-repro-fixtures', 'preview-reopen-current-commit',
  990003101, 'R_preview_reopen_current_commit', 'main', 'heads/main', 'main',
  'eec31000-0000-4000-8000-000000000006', 'src/index.html',
  repeat('a', 40), 'eec31000-0000-4000-8000-000000000027',
  '2026-10-15T00:22:00Z', '2026-10-15T00:22:30Z',
  '2026-10-15T00:22:10Z', repeat('a', 40), true,
  '2026-10-15T00:22:15Z'
);
insert into lws_internal.website_project_preview_build_leases(
  preview_lease_id, source_write_lease_id, actor_auth_user_id, quote_request_id,
  website_work_context_id, website_workspace_id, expected_commit_sha,
  acquired_at, expires_at, released_at, authorized_build_id
) values (
  'eec31000-0000-4000-8000-000000000012',
  'eec31000-0000-4000-8000-000000000011',
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'eec31000-0000-4000-8000-000000000002',
  'eec31000-0000-4000-8000-000000000004',
  'eec31000-0000-4000-8000-000000000005',
  repeat('a', 40), '2026-10-15T00:22:15Z',
  '2026-10-15T00:27:15Z', null,
  'eec31000-0000-4000-8000-000000000013'
);
insert into lws_internal.website_project_preview_builds(
  preview_build_id, lease_id, actor_auth_user_id, quote_request_id,
  website_work_context_id, website_workspace_id, commit_sha, artifact_path,
  artifact_sha256, artifact_bytes, build_status, built_at
) values (
  'eec31000-0000-4000-8000-000000000013',
  'eec31000-0000-4000-8000-000000000012',
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'eec31000-0000-4000-8000-000000000002',
  'eec31000-0000-4000-8000-000000000004',
  'eec31000-0000-4000-8000-000000000005',
  repeat('a', 40), 'preview/current-warning.tar', repeat('b', 64), 101,
  'PASS_WITH_WARNINGS', '2026-10-15T00:23:00Z'
);
insert into lws_internal.website_project_preview_build_artifacts(
  artifact_id, preview_build_id, relative_path, content_type, sha256, bytes,
  created_at
) values (
  'eec31000-0000-4000-8000-000000000014',
  'eec31000-0000-4000-8000-000000000013',
  'index.html', 'text/html', repeat('b', 64), 101,
  '2026-10-15T00:23:00Z'
);
set local session_replication_role = origin;

select count(*)::integer as warning_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select public.open_existing_website_project_preview_v1(
  'eec31000-0000-4000-8000-000000000002',
  repeat('2', 64)
) as warning_response
\gset
reset role;
select count(*)::integer as warning_after
from lws_internal.website_project_preview_sessions
\gset

select is(:warning_before::integer, 1, 'current warning starts after one session');
select is(:warning_after::integer, 2, 'current PASS_WITH_WARNINGS creates one session');
select ok(
  :'warning_response'::jsonb->>'previewBuildId' =
    'eec31000-0000-4000-8000-000000000013'
  and :'warning_response'::jsonb->>'buildStatus' = 'PASS_WITH_WARNINGS'
  and (:'warning_response'::jsonb->>'isCurrentCommit')::boolean,
  'current PASS_WITH_WARNINGS returns the current warning build'
);

set local session_replication_role = replica;
insert into lws_internal.website_project_files_write_leases(
  lease_id, actor_operator_id, actor_auth_user_id, quote_request_id,
  website_work_context_id, website_workspace_id, binding_revision,
  repository_provider, repository_owner, repository_name,
  repository_external_id, repository_node_id, default_branch, repository_ref,
  ref_label, marker_operation_id, write_path, expected_commit_sha,
  idempotency_key, acquired_at, expires_at, finalized_at, finalized_commit_sha,
  finalized_created, released_at
) values (
  'eec31000-0000-4000-8000-000000000015',
  'eec31000-0000-4000-8000-000000000001',
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'eec31000-0000-4000-8000-000000000002',
  'eec31000-0000-4000-8000-000000000004',
  'eec31000-0000-4000-8000-000000000005',
  1, 'GITHUB', 'lws-repro-fixtures', 'preview-reopen-current-commit',
  990003101, 'R_preview_reopen_current_commit', 'main', 'heads/main', 'main',
  'eec31000-0000-4000-8000-000000000006', 'src/index.html',
  repeat('c', 40), 'eec31000-0000-4000-8000-000000000028',
  '2026-10-15T00:24:00Z', '2026-10-15T00:24:30Z',
  '2026-10-15T00:24:10Z', repeat('c', 40), true,
  '2026-10-15T00:24:15Z'
);
insert into lws_internal.website_project_preview_build_leases(
  preview_lease_id, source_write_lease_id, actor_auth_user_id, quote_request_id,
  website_work_context_id, website_workspace_id, expected_commit_sha,
  acquired_at, expires_at, released_at, authorized_build_id
) values (
  'eec31000-0000-4000-8000-000000000016',
  'eec31000-0000-4000-8000-000000000015',
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'eec31000-0000-4000-8000-000000000002',
  'eec31000-0000-4000-8000-000000000004',
  'eec31000-0000-4000-8000-000000000005',
  repeat('c', 40), '2026-10-15T00:24:15Z',
  '2026-10-15T00:29:15Z', null,
  'eec31000-0000-4000-8000-000000000017'
);
insert into lws_internal.website_project_preview_builds(
  preview_build_id, lease_id, actor_auth_user_id, quote_request_id,
  website_work_context_id, website_workspace_id, commit_sha, artifact_path,
  artifact_sha256, artifact_bytes, build_status, built_at
) values (
  'eec31000-0000-4000-8000-000000000017',
  'eec31000-0000-4000-8000-000000000016',
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'eec31000-0000-4000-8000-000000000002',
  'eec31000-0000-4000-8000-000000000004',
  'eec31000-0000-4000-8000-000000000005',
  repeat('c', 40), 'preview/newer-stale.tar', repeat('c', 64), 102,
  'PASS', '2026-10-15T00:25:00Z'
);
insert into lws_internal.website_project_preview_build_artifacts(
  artifact_id, preview_build_id, relative_path, content_type, sha256, bytes,
  created_at
) values (
  'eec31000-0000-4000-8000-000000000018',
  'eec31000-0000-4000-8000-000000000017',
  'index.html', 'text/html', repeat('c', 64), 102,
  '2026-10-15T00:25:00Z'
);
set local session_replication_role = origin;

set local role authenticated;
select public.open_existing_website_project_preview_v1(
  'eec31000-0000-4000-8000-000000000002',
  repeat('3', 64)
) as current_over_stale_response
\gset
reset role;
select is(
  :'current_over_stale_response'::jsonb->>'previewBuildId',
  'eec31000-0000-4000-8000-000000000013',
  'newer stale build does not outrank the older current build'
);

set local session_replication_role = replica;
update public.website_execution_workspaces
set last_commit_sha = repeat('d', 40),
    last_commit_at = '2026-10-15T00:26:00Z'
where website_workspace_id = 'eec31000-0000-4000-8000-000000000005';
set local session_replication_role = origin;

select count(*)::integer as stale_pass_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.open_existing_website_project_preview_v1(
    'eec31000-0000-4000-8000-000000000002',
    repeat('4', 64)
  )$$,
  'P0001',
  'PROJECT_PREVIEW_BUILD_NOT_FOUND',
  'only stale PASS build is rejected before session creation'
);
reset role;
select count(*)::integer as stale_pass_after
from lws_internal.website_project_preview_sessions
\gset
select is(
  :stale_pass_after::integer,
  :stale_pass_before::integer,
  'stale PASS rejection creates no session'
);

set local session_replication_role = replica;
update lws_internal.website_project_preview_builds
set build_status = 'PASS_WITH_WARNINGS'
where preview_build_id = 'eec31000-0000-4000-8000-000000000017';
set local session_replication_role = origin;

select count(*)::integer as stale_warning_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.open_existing_website_project_preview_v1(
    'eec31000-0000-4000-8000-000000000002',
    repeat('5', 64)
  )$$,
  'P0001',
  'PROJECT_PREVIEW_BUILD_NOT_FOUND',
  'only stale PASS_WITH_WARNINGS build is rejected before session creation'
);
reset role;
select count(*)::integer as stale_warning_after
from lws_internal.website_project_preview_sessions
\gset
select is(
  :stale_warning_after::integer,
  :stale_warning_before::integer,
  'stale PASS_WITH_WARNINGS rejection creates no session'
);

set local role authenticated;
select throws_ok(
  $$select public.open_existing_website_project_preview_v1(
    'eec31000-0000-4000-8000-000000000002',
    'invalid-token-hash'
  )$$,
  '22023',
  'PROJECT_PREVIEW_OPEN_INPUT_INVALID',
  'invalid token hash is rejected'
);
reset role;

select set_config('request.jwt.claims', '{}', true);
set local role authenticated;
select throws_ok(
  $$select public.open_existing_website_project_preview_v1(
    'eec31000-0000-4000-8000-000000000002',
    repeat('6', 64)
  )$$,
  '42501',
  'HUMAN_JWT_REQUIRED',
  'missing human JWT is rejected'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.open_existing_website_project_preview_v1(
    'eec31000-0000-4000-8000-000000000002',
    repeat('7', 64)
  )$$,
  '42501',
  'AAL2_REQUIRED',
  'AAL1 is rejected'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}',
  true
);
set local session_replication_role = replica;
update public.commercial_operators
set role = 'operator'
where operator_id = 'eec31000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
set local role authenticated;
select throws_ok(
  $$select public.open_existing_website_project_preview_v1(
    'eec31000-0000-4000-8000-000000000002',
    repeat('8', 64)
  )$$,
  '42501',
  'WEBSITE_REPOSITORY_OWNER_REQUIRED',
  'non-owner is rejected'
);
reset role;

set local session_replication_role = replica;
update public.commercial_operators
set role = 'owner'
where operator_id = 'eec31000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
update public.website_execution_workspaces
set last_commit_sha = null,
    last_commit_at = null
where website_workspace_id = 'eec31000-0000-4000-8000-000000000005';
set local role authenticated;
select throws_ok(
  $$select public.open_existing_website_project_preview_v1(
    'eec31000-0000-4000-8000-000000000002',
    repeat('9', 64)
  )$$,
  'P0001',
  'PROJECT_PREVIEW_REPOSITORY_NOT_READY',
  'workspace without a current commit is rejected'
);
reset role;

update public.website_execution_workspaces
set last_commit_sha = repeat('a', 40),
    last_commit_at = '2026-10-15T00:26:00Z'
where website_workspace_id = 'eec31000-0000-4000-8000-000000000005';
set local session_replication_role = replica;
update lws_internal.website_project_files_write_leases
set binding_revision = 2
where lease_id in (
  'eec31000-0000-4000-8000-000000000007',
  'eec31000-0000-4000-8000-000000000011'
);
set local session_replication_role = origin;
set local role authenticated;
select throws_ok(
  $$select public.open_existing_website_project_preview_v1(
    'eec31000-0000-4000-8000-000000000002',
    repeat('a', 64)
  )$$,
  'P0001',
  'PROJECT_PREVIEW_BUILD_NOT_FOUND',
  'binding revision mismatch is rejected'
);
reset role;

set local session_replication_role = replica;
update lws_internal.website_project_files_write_leases
set binding_revision = 1
where lease_id in (
  'eec31000-0000-4000-8000-000000000007',
  'eec31000-0000-4000-8000-000000000011'
);
update public.website_repository_provisioning_operations
set repository_name = 'wrong-repository'
where operation_id = 'eec31000-0000-4000-8000-000000000006';
set local session_replication_role = origin;
set local role authenticated;
select throws_ok(
  $$select public.open_existing_website_project_preview_v1(
    'eec31000-0000-4000-8000-000000000002',
    repeat('b', 64)
  )$$,
  'P0001',
  'PROJECT_PREVIEW_REPOSITORY_NOT_READY',
  'repository operation binding mismatch is rejected'
);
reset role;

set local session_replication_role = replica;
update public.website_repository_provisioning_operations
set repository_name = 'preview-reopen-current-commit'
where operation_id = 'eec31000-0000-4000-8000-000000000006';
delete from lws_internal.website_project_preview_build_artifacts
where preview_build_id in (
  'eec31000-0000-4000-8000-000000000009',
  'eec31000-0000-4000-8000-000000000013'
);
set local session_replication_role = origin;
set local role authenticated;
select throws_ok(
  $$select public.open_existing_website_project_preview_v1(
    'eec31000-0000-4000-8000-000000000002',
    repeat('c', 64)
  )$$,
  'P0001',
  'PROJECT_PREVIEW_BUILD_NOT_FOUND',
  'build without artifact is rejected'
);
reset role;

set local session_replication_role = replica;
update lws_internal.website_project_preview_builds
set build_status = 'FAILED'
where preview_build_id in (
  'eec31000-0000-4000-8000-000000000009',
  'eec31000-0000-4000-8000-000000000013',
  'eec31000-0000-4000-8000-000000000017'
);
set local session_replication_role = origin;
set local role authenticated;
select throws_ok(
  $$select public.open_existing_website_project_preview_v1(
    'eec31000-0000-4000-8000-000000000002',
    repeat('d', 64)
  )$$,
  'P0001',
  'PROJECT_PREVIEW_BUILD_NOT_FOUND',
  'invalid build status is rejected'
);
reset role;

select todo_start(
  'real two-session workspace-commit race requires a committed migrated '
  || 'ephemeral database; current authorization forbids that visibility boundary'
);
select fail(
  'workspace commit change between selection and insert remains locally NOT TESTED'
);
select todo_end();

select * from finish();
rollback;
