begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public',
  'create_website_project_preview_session_v1',
  array['uuid', 'text'],
  'create-session RPC exists'
);

select ok(
  (
    select p.prosecdef
      and pg_get_userbyid(p.proowner) = 'postgres'
      and p.proconfig = array['search_path=public, lws_internal, auth, pg_catalog']
    from pg_proc as p
    where p.oid =
      'public.create_website_project_preview_session_v1(uuid,text)'::regprocedure
  ),
  'create-session RPC remains postgres-owned SECURITY DEFINER with safe search_path'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.create_website_project_preview_session_v1(uuid,text)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.create_website_project_preview_session_v1(uuid,text)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.create_website_project_preview_session_v1(uuid,text)',
    'execute'
  ),
  'create-session execute remains authenticated-only'
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
      'public.create_website_project_preview_session_v1(uuid,text)'::regprocedure
      and acl.privilege_type = 'EXECUTE'
    order by 1
  $$,
  $$ values ('authenticated'::text collate "C"), ('postgres'::text collate "C") $$,
  'create-session effective EXECUTE ACL has only authenticated and postgres'
);

insert into auth.users(id, email) values
  (
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'preview-create-session-owner@example.test'
  ),
  (
    'eec32000-0000-4000-8000-000000000041',
    'preview-create-session-other@example.test'
  );

set local session_replication_role = replica;

insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status, created_at, updated_at
) values
  (
    'eec32000-0000-4000-8000-000000000001',
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'Preview create-session owner',
    'owner',
    'ACTIVE',
    '2026-10-16T00:00:00Z',
    '2026-10-16T00:00:00Z'
  ),
  (
    'eec32000-0000-4000-8000-000000000024',
    'eec32000-0000-4000-8000-000000000041',
    'Preview create-session synthetic actor',
    'operator',
    'ACTIVE',
    '2026-10-16T00:00:00Z',
    '2026-10-16T00:00:00Z'
  );

set local session_replication_role = origin;

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind, sdf_package,
  created_at, updated_at, name, email, website_type, budget, timing,
  description, privacy_consent, status
) values
  (
    'eec32000-0000-4000-8000-000000000002',
    'LWS-AAN-2099-9903',
    'production',
    'website',
    null,
    '2026-10-16T00:00:00Z',
    '2026-10-16T00:00:00Z',
    'Synthetic preview create-session test',
    'preview-create-session-owner@example.test',
    'business',
    'Meer dan EUR 6.000',
    'flexible',
    'Rollback-only create-session current commit fixture.',
    true,
    'approved'
  ),
  (
    'eec32100-0000-4000-8000-000000000019',
    'LWS-AAN-2099-9904',
    'production',
    'website',
    null,
    '2026-10-16T00:00:00Z',
    '2026-10-16T00:00:00Z',
    'Synthetic preview cross-dossier test',
    'preview-create-session-other@example.test',
    'business',
    'Meer dan EUR 6.000',
    'flexible',
    'Rollback-only cross-dossier fixture.',
    true,
    'approved'
  );

set local lws.website_concept_command = 'on';

insert into public.website_concepts(
  concept_id, quote_request_id, mode, briefing_status, concept_status,
  revision, created_by, created_at, updated_at
) values
  (
    'eec32000-0000-4000-8000-000000000003',
    'eec32000-0000-4000-8000-000000000002',
    'PRE_PROJECT',
    'LIMITED',
    'ACTIVE',
    1,
    'eec32000-0000-4000-8000-000000000001',
    '2026-10-16T00:01:00Z',
    '2026-10-16T00:01:00Z'
  ),
  (
    'eec32000-0000-4000-8000-000000000020',
    'eec32100-0000-4000-8000-000000000019',
    'PRE_PROJECT',
    'LIMITED',
    'ACTIVE',
    1,
    'eec32000-0000-4000-8000-000000000001',
    '2026-10-16T00:01:00Z',
    '2026-10-16T00:01:00Z'
  );

insert into public.website_work_contexts(
  website_work_context_id, quote_request_id, concept_id, project_id,
  phase, revision, created_at, updated_at
) values
  (
    'eec32000-0000-4000-8000-000000000004',
    'eec32000-0000-4000-8000-000000000002',
    'eec32000-0000-4000-8000-000000000003',
    null,
    'PRE_PROJECT',
    1,
    '2026-10-16T00:01:00Z',
    '2026-10-16T00:01:00Z'
  ),
  (
    'eec32000-0000-4000-8000-000000000021',
    'eec32100-0000-4000-8000-000000000019',
    'eec32000-0000-4000-8000-000000000020',
    null,
    'PRE_PROJECT',
    1,
    '2026-10-16T00:01:00Z',
    '2026-10-16T00:01:00Z'
  );

set constraints
  trg_website_concepts_binding,
  trg_website_work_contexts_binding
immediate;
set constraints
  trg_website_concepts_binding,
  trg_website_work_contexts_binding
deferred;

set local lws.website_concept_command = 'off';

insert into public.website_execution_workspaces(
  website_workspace_id, website_work_context_id, project_id, quote_request_id,
  workspace_state, repository_provider, repository_owner, repository_name,
  default_branch, last_commit_sha, last_commit_at, binding_revision, created_by,
  provisioned_by, provisioned_at, repository_external_id, repository_node_id,
  repository_visibility, repository_state, starter_source, starter_version,
  starter_commit_sha, repository_marker_commit_sha, repository_bound_at,
  created_at, updated_at
) values
  (
    'eec32000-0000-4000-8000-000000000005',
    'eec32000-0000-4000-8000-000000000004',
    null,
    'eec32000-0000-4000-8000-000000000002',
    'REPOSITORY_READY',
    'GITHUB',
    'lws-repro-fixtures',
    'preview-create-session-current',
    'main',
    repeat('a', 40),
    '2026-10-16T00:22:40Z',
    1,
    'eec32000-0000-4000-8000-000000000001',
    'eec32000-0000-4000-8000-000000000001',
    '2026-10-16T00:10:00Z',
    990003201,
    'R_preview_create_session_current',
    'private',
    'BOUND',
    'lws-repro-fixtures/website-starter',
    '1.0.0',
    repeat('8', 40),
    repeat('9', 40),
    '2026-10-16T00:10:00Z',
    '2026-10-16T00:05:00Z',
    '2026-10-16T00:22:40Z'
  ),
  (
    'eec32000-0000-4000-8000-000000000022',
    'eec32000-0000-4000-8000-000000000021',
    null,
    'eec32100-0000-4000-8000-000000000019',
    'REPOSITORY_READY',
    'GITHUB',
    'lws-repro-fixtures',
    'preview-create-session-other',
    'main',
    repeat('b', 40),
    '2026-10-16T00:10:00Z',
    1,
    'eec32000-0000-4000-8000-000000000024',
    'eec32000-0000-4000-8000-000000000024',
    '2026-10-16T00:10:00Z',
    990003202,
    'R_preview_create_session_other',
    'private',
    'BOUND',
    'lws-repro-fixtures/website-starter',
    '1.0.0',
    repeat('8', 40),
    repeat('9', 40),
    '2026-10-16T00:10:00Z',
    '2026-10-16T00:05:00Z',
    '2026-10-16T00:10:00Z'
  );

set local lws.website_repository_command = 'on';

insert into public.website_repository_provisioning_operations(
  operation_id, website_workspace_id, website_work_context_id, actor_id,
  idempotency_key, request_fingerprint, repository_provider, repository_owner,
  repository_name, starter_source, starter_version, starter_commit_sha, state,
  attempt_count, first_attempt_at, retry_window_expires_at,
  repository_external_id, repository_node_id, claimed_at, updated_at,
  external_created_at, bound_at
) values
  (
    'eec32000-0000-4000-8000-000000000006',
    'eec32000-0000-4000-8000-000000000005',
    'eec32000-0000-4000-8000-000000000004',
    'eec32000-0000-4000-8000-000000000001',
    'eec32000-0000-4000-8000-000000000025',
    repeat('1', 64),
    'GITHUB',
    'lws-repro-fixtures',
    'preview-create-session-current',
    'lws-repro-fixtures/website-starter',
    '1.0.0',
    repeat('8', 40),
    'BOUND',
    1,
    '2026-10-16T00:10:00Z',
    '2026-10-17T00:10:00Z',
    990003201,
    'R_preview_create_session_current',
    '2026-10-16T00:10:00Z',
    '2026-10-16T00:10:00Z',
    '2026-10-16T00:10:00Z',
    '2026-10-16T00:10:00Z'
  ),
  (
    'eec32000-0000-4000-8000-000000000023',
    'eec32000-0000-4000-8000-000000000022',
    'eec32000-0000-4000-8000-000000000021',
    'eec32000-0000-4000-8000-000000000024',
    'eec32000-0000-4000-8000-000000000026',
    repeat('2', 64),
    'GITHUB',
    'lws-repro-fixtures',
    'preview-create-session-other',
    'lws-repro-fixtures/website-starter',
    '1.0.0',
    repeat('8', 40),
    'BOUND',
    1,
    '2026-10-16T00:10:00Z',
    '2026-10-17T00:10:00Z',
    990003202,
    'R_preview_create_session_other',
    '2026-10-16T00:10:00Z',
    '2026-10-16T00:10:00Z',
    '2026-10-16T00:10:00Z',
    '2026-10-16T00:10:00Z'
  );

set local lws.website_repository_command = 'off';

insert into lws_internal.website_project_files_write_leases(
  lease_id, actor_operator_id, actor_auth_user_id, quote_request_id,
  website_work_context_id, website_workspace_id, binding_revision,
  repository_provider, repository_owner, repository_name,
  repository_external_id, repository_node_id, default_branch, repository_ref,
  ref_label, marker_operation_id, write_path, expected_commit_sha,
  idempotency_key, acquired_at, expires_at, finalized_at, finalized_commit_sha,
  finalized_created, released_at
) values
  (
    'eec32000-0000-4000-8000-000000000007',
    'eec32000-0000-4000-8000-000000000001',
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'eec32000-0000-4000-8000-000000000002',
    'eec32000-0000-4000-8000-000000000004',
    'eec32000-0000-4000-8000-000000000005',
    1,
    'GITHUB',
    'lws-repro-fixtures',
    'preview-create-session-current',
    990003201,
    'R_preview_create_session_current',
    'main',
    'heads/main',
    'main',
    'eec32000-0000-4000-8000-000000000006',
    'index.html',
    repeat('a', 40),
    'eec32000-0000-4000-8000-000000000027',
    '2026-10-16T00:20:00Z',
    '2026-10-16T00:20:30Z',
    '2026-10-16T00:20:10Z',
    repeat('a', 40),
    true,
    '2026-10-16T00:20:10Z'
  ),
  (
    'eec32000-0000-4000-8000-000000000011',
    'eec32000-0000-4000-8000-000000000001',
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'eec32000-0000-4000-8000-000000000002',
    'eec32000-0000-4000-8000-000000000004',
    'eec32000-0000-4000-8000-000000000005',
    1,
    'GITHUB',
    'lws-repro-fixtures',
    'preview-create-session-current',
    990003201,
    'R_preview_create_session_current',
    'main',
    'heads/main',
    'main',
    'eec32000-0000-4000-8000-000000000006',
    'index.html',
    repeat('a', 40),
    'eec32000-0000-4000-8000-000000000028',
    '2026-10-16T00:21:00Z',
    '2026-10-16T00:21:30Z',
    '2026-10-16T00:21:10Z',
    repeat('a', 40),
    true,
    '2026-10-16T00:21:10Z'
  ),
  (
    'eec32000-0000-4000-8000-000000000015',
    'eec32000-0000-4000-8000-000000000001',
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'eec32000-0000-4000-8000-000000000002',
    'eec32000-0000-4000-8000-000000000004',
    'eec32000-0000-4000-8000-000000000005',
    1,
    'GITHUB',
    'lws-repro-fixtures',
    'preview-create-session-current',
    990003201,
    'R_preview_create_session_current',
    'main',
    'heads/main',
    'main',
    'eec32000-0000-4000-8000-000000000006',
    'index.html',
    repeat('c', 40),
    'eec32000-0000-4000-8000-000000000029',
    '2026-10-16T00:22:00Z',
    '2026-10-16T00:22:30Z',
    '2026-10-16T00:22:10Z',
    repeat('c', 40),
    true,
    '2026-10-16T00:22:10Z'
  );

insert into lws_internal.website_project_preview_build_leases(
  preview_lease_id, source_write_lease_id, actor_auth_user_id, quote_request_id,
  website_work_context_id, website_workspace_id, expected_commit_sha,
  acquired_at, expires_at, released_at, authorized_build_id
) values
  (
    'eec32000-0000-4000-8000-000000000008',
    'eec32000-0000-4000-8000-000000000007',
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'eec32000-0000-4000-8000-000000000002',
    'eec32000-0000-4000-8000-000000000004',
    'eec32000-0000-4000-8000-000000000005',
    repeat('a', 40),
    '2026-10-16T00:20:15Z',
    '2026-10-16T00:40:15Z',
    '2026-10-16T00:20:31Z',
    'eec32000-0000-4000-8000-000000000030'
  ),
  (
    'eec32000-0000-4000-8000-000000000012',
    'eec32000-0000-4000-8000-000000000011',
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'eec32000-0000-4000-8000-000000000002',
    'eec32000-0000-4000-8000-000000000004',
    'eec32000-0000-4000-8000-000000000005',
    repeat('a', 40),
    '2026-10-16T00:21:15Z',
    '2026-10-16T00:41:15Z',
    '2026-10-16T00:21:31Z',
    'eec32000-0000-4000-8000-000000000031'
  ),
  (
    'eec32000-0000-4000-8000-000000000016',
    'eec32000-0000-4000-8000-000000000015',
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'eec32000-0000-4000-8000-000000000002',
    'eec32000-0000-4000-8000-000000000004',
    'eec32000-0000-4000-8000-000000000005',
    repeat('c', 40),
    '2026-10-16T00:22:15Z',
    '2026-10-16T00:42:15Z',
    '2026-10-16T00:22:31Z',
    'eec32000-0000-4000-8000-000000000032'
  );

insert into lws_internal.website_project_preview_builds(
  preview_build_id, lease_id, actor_auth_user_id, quote_request_id,
  website_work_context_id, website_workspace_id, commit_sha, artifact_path,
  artifact_sha256, artifact_bytes, build_status, built_at
) values
  (
    'eec32000-0000-4000-8000-000000000009',
    'eec32000-0000-4000-8000-000000000008',
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'eec32000-0000-4000-8000-000000000002',
    'eec32000-0000-4000-8000-000000000004',
    'eec32000-0000-4000-8000-000000000005',
    repeat('a', 40),
    'index.html',
    repeat('a', 64),
    100,
    'PASS',
    '2026-10-16T00:20:30Z'
  ),
  (
    'eec32000-0000-4000-8000-000000000013',
    'eec32000-0000-4000-8000-000000000012',
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'eec32000-0000-4000-8000-000000000002',
    'eec32000-0000-4000-8000-000000000004',
    'eec32000-0000-4000-8000-000000000005',
    repeat('a', 40),
    'index.html',
    repeat('b', 64),
    101,
    'PASS_WITH_WARNINGS',
    '2026-10-16T00:21:30Z'
  ),
  (
    'eec32000-0000-4000-8000-000000000017',
    'eec32000-0000-4000-8000-000000000016',
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'eec32000-0000-4000-8000-000000000002',
    'eec32000-0000-4000-8000-000000000004',
    'eec32000-0000-4000-8000-000000000005',
    repeat('c', 40),
    'index.html',
    repeat('c', 64),
    102,
    'PASS',
    '2026-10-16T00:22:30Z'
  );

insert into lws_internal.website_project_preview_build_artifacts(
  artifact_id, preview_build_id, relative_path, content_type, sha256, bytes,
  created_at
) values
  (
    'eec32000-0000-4000-8000-000000000010',
    'eec32000-0000-4000-8000-000000000009',
    'index.html',
    'text/html',
    repeat('a', 64),
    100,
    '2026-10-16T00:20:30Z'
  ),
  (
    'eec32000-0000-4000-8000-000000000014',
    'eec32000-0000-4000-8000-000000000013',
    'index.html',
    'text/html',
    repeat('b', 64),
    101,
    '2026-10-16T00:21:30Z'
  ),
  (
    'eec32000-0000-4000-8000-000000000018',
    'eec32000-0000-4000-8000-000000000017',
    'index.html',
    'text/html',
    repeat('c', 64),
    102,
    '2026-10-16T00:22:30Z'
  );

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}',
  true
);

select count(*)::integer as pass_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select public.create_website_project_preview_session_v1(
  'eec32000-0000-4000-8000-000000000009',
  md5('create-session-pass') || md5('create-session-pass')
) as pass_response
\gset
reset role;
select count(*)::integer as pass_after
from lws_internal.website_project_preview_sessions
\gset

select is(:pass_after::integer, :pass_before::integer + 1, 'current PASS creates one session');
select is(
  (
    select session.preview_build_id::text
    from lws_internal.website_project_preview_sessions as session
    where session.session_token_hash =
      md5('create-session-pass') || md5('create-session-pass')
  ),
  'eec32000-0000-4000-8000-000000000009',
  'current PASS session is bound to the exact requested build'
);
select is(
  (
    select session.actor_auth_user_id::text
    from lws_internal.website_project_preview_sessions as session
    where session.session_token_hash =
      md5('create-session-pass') || md5('create-session-pass')
  ),
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'current PASS session preserves caller authority'
);
select is(
  (
    select array_agg(key order by key)
    from jsonb_object_keys(:'pass_response'::jsonb) as key
  ),
  array['expiresAt', 'previewSessionId']::text[],
  'success response keeps the exact existing key contract'
);
select ok(
  (:'pass_response'::jsonb->>'previewSessionId')::uuid is not null
  and (:'pass_response'::jsonb->>'expiresAt')::timestamptz >
    clock_timestamp() + interval '29 minutes'
  and (:'pass_response'::jsonb->>'expiresAt')::timestamptz <
    clock_timestamp() + interval '31 minutes',
  'success response keeps the UUID and thirty-minute expiry contract'
);

select count(*)::integer as warning_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select public.create_website_project_preview_session_v1(
  'eec32000-0000-4000-8000-000000000013',
  md5('create-session-warning') || md5('create-session-warning')
) as warning_response
\gset
reset role;
select count(*)::integer as warning_after
from lws_internal.website_project_preview_sessions
\gset
select is(
  :warning_after::integer,
  :warning_before::integer + 1,
  'current PASS_WITH_WARNINGS creates one session'
);
select is(
  (
    select session.preview_build_id::text
    from lws_internal.website_project_preview_sessions as session
    where session.session_token_hash =
      md5('create-session-warning') || md5('create-session-warning')
  ),
  'eec32000-0000-4000-8000-000000000013',
  'current PASS_WITH_WARNINGS session uses the exact requested build'
);

select count(*)::integer as stale_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.create_website_project_preview_session_v1(
    'eec32000-0000-4000-8000-000000000017',
    md5('create-session-stale') || md5('create-session-stale')
  )$$,
  '42501',
  'PROJECT_PREVIEW_BUILD_NOT_READY',
  'stale requested build is rejected instead of falling back to a current build'
);
reset role;
select count(*)::integer as stale_after
from lws_internal.website_project_preview_sessions
\gset
select is(:stale_after::integer, :stale_before::integer, 'stale build creates no session');

update lws_internal.website_project_files_write_leases
set binding_revision = 2
where lease_id = 'eec32000-0000-4000-8000-000000000007';
select count(*)::integer as binding_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.create_website_project_preview_session_v1(
    'eec32000-0000-4000-8000-000000000009',
    md5('create-session-binding') || md5('create-session-binding')
  )$$,
  '42501',
  'PROJECT_PREVIEW_BUILD_NOT_READY',
  'stale binding revision is rejected'
);
reset role;
select count(*)::integer as binding_after
from lws_internal.website_project_preview_sessions
\gset
select is(
  :binding_after::integer,
  :binding_before::integer,
  'binding revision rejection creates no session'
);
update lws_internal.website_project_files_write_leases
set binding_revision = 1
where lease_id = 'eec32000-0000-4000-8000-000000000007';

update lws_internal.website_project_files_write_leases
set repository_name = 'wrong-repository'
where lease_id = 'eec32000-0000-4000-8000-000000000007';
select count(*)::integer as repository_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.create_website_project_preview_session_v1(
    'eec32000-0000-4000-8000-000000000009',
    md5('create-session-repository') || md5('create-session-repository')
  )$$,
  '42501',
  'PROJECT_PREVIEW_BUILD_NOT_READY',
  'repository binding mismatch is rejected'
);
reset role;
select count(*)::integer as repository_after
from lws_internal.website_project_preview_sessions
\gset
select is(
  :repository_after::integer,
  :repository_before::integer,
  'repository binding rejection creates no session'
);
update lws_internal.website_project_files_write_leases
set repository_name = 'preview-create-session-current'
where lease_id = 'eec32000-0000-4000-8000-000000000007';

update lws_internal.website_project_files_write_leases
set marker_operation_id = 'eec32000-0000-4000-8000-000000000023'
where lease_id = 'eec32000-0000-4000-8000-000000000007';
select count(*)::integer as operation_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.create_website_project_preview_session_v1(
    'eec32000-0000-4000-8000-000000000009',
    md5('create-session-operation') || md5('create-session-operation')
  )$$,
  '42501',
  'PROJECT_PREVIEW_BUILD_NOT_READY',
  'non-canonical repository operation is rejected'
);
reset role;
select count(*)::integer as operation_after
from lws_internal.website_project_preview_sessions
\gset
select is(
  :operation_after::integer,
  :operation_before::integer,
  'canonical operation rejection creates no session'
);
update lws_internal.website_project_files_write_leases
set marker_operation_id = 'eec32000-0000-4000-8000-000000000006'
where lease_id = 'eec32000-0000-4000-8000-000000000007';

delete from lws_internal.website_project_preview_build_artifacts
where preview_build_id = 'eec32000-0000-4000-8000-000000000009';
select count(*)::integer as artifact_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.create_website_project_preview_session_v1(
    'eec32000-0000-4000-8000-000000000009',
    md5('create-session-artifact') || md5('create-session-artifact')
  )$$,
  '42501',
  'PROJECT_PREVIEW_BUILD_NOT_READY',
  'build without an artifact is rejected'
);
reset role;
select count(*)::integer as artifact_after
from lws_internal.website_project_preview_sessions
\gset
select is(
  :artifact_after::integer,
  :artifact_before::integer,
  'missing artifact rejection creates no session'
);
insert into lws_internal.website_project_preview_build_artifacts(
  artifact_id, preview_build_id, relative_path, content_type, sha256, bytes,
  created_at
) values (
  'eec32000-0000-4000-8000-000000000010',
  'eec32000-0000-4000-8000-000000000009',
  'index.html',
  'text/html',
  repeat('a', 64),
  100,
  '2026-10-16T00:20:30Z'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}',
  true
);
update lws_internal.website_project_preview_builds
set actor_auth_user_id = 'eec32000-0000-4000-8000-000000000041'
where preview_build_id = 'eec32000-0000-4000-8000-000000000009';
select count(*)::integer as actor_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.create_website_project_preview_session_v1(
    'eec32000-0000-4000-8000-000000000009',
    md5('create-session-actor') || md5('create-session-actor')
  )$$,
  '42501',
  'PROJECT_PREVIEW_BUILD_NOT_READY',
  'different active owner cannot issue a session for another actor build'
);
reset role;
select count(*)::integer as actor_after
from lws_internal.website_project_preview_sessions
\gset
select is(:actor_after::integer, :actor_before::integer, 'wrong actor creates no session');
update lws_internal.website_project_preview_builds
set actor_auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'
where preview_build_id = 'eec32000-0000-4000-8000-000000000009';

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}',
  true
);
set local session_replication_role = replica;
update public.commercial_operators
set role = 'operator'
where operator_id = 'eec32000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select count(*)::integer as non_owner_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.create_website_project_preview_session_v1(
    'eec32000-0000-4000-8000-000000000009',
    md5('create-session-non-owner') || md5('create-session-non-owner')
  )$$,
  '42501',
  'WEBSITE_REPOSITORY_OWNER_REQUIRED',
  'non-owner is rejected'
);
reset role;
select count(*)::integer as non_owner_after
from lws_internal.website_project_preview_sessions
\gset
select is(
  :non_owner_after::integer,
  :non_owner_before::integer,
  'non-owner rejection creates no session'
);
set local session_replication_role = replica;
update public.commercial_operators
set role = 'owner'
where operator_id = 'eec32000-0000-4000-8000-000000000001';
set local session_replication_role = origin;

set local session_replication_role = replica;
update public.commercial_operators
set status = 'DISABLED'
where operator_id = 'eec32000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select count(*)::integer as inactive_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.create_website_project_preview_session_v1(
    'eec32000-0000-4000-8000-000000000009',
    md5('create-session-inactive') || md5('create-session-inactive')
  )$$,
  '42501',
  'WEBSITE_REPOSITORY_OWNER_REQUIRED',
  'inactive owner is rejected'
);
reset role;
select count(*)::integer as inactive_after
from lws_internal.website_project_preview_sessions
\gset
select is(
  :inactive_after::integer,
  :inactive_before::integer,
  'inactive owner rejection creates no session'
);
set local session_replication_role = replica;
update public.commercial_operators
set status = 'ACTIVE'
where operator_id = 'eec32000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal1"}',
  true
);
select count(*)::integer as aal1_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.create_website_project_preview_session_v1(
    'eec32000-0000-4000-8000-000000000009',
    md5('create-session-aal1') || md5('create-session-aal1')
  )$$,
  '42501',
  'AAL2_REQUIRED',
  'AAL1 is rejected'
);
reset role;
select count(*)::integer as aal1_after
from lws_internal.website_project_preview_sessions
\gset
select is(:aal1_after::integer, :aal1_before::integer, 'AAL1 rejection creates no session');

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"service_role","aal":"aal2"}',
  true
);
select count(*)::integer as service_role_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.create_website_project_preview_session_v1(
    'eec32000-0000-4000-8000-000000000009',
    md5('create-session-service-role') || md5('create-session-service-role')
  )$$,
  '42501',
  'HUMAN_JWT_REQUIRED',
  'service-role JWT is rejected'
);
reset role;
select count(*)::integer as service_role_after
from lws_internal.website_project_preview_sessions
\gset
select is(
  :service_role_after::integer,
  :service_role_before::integer,
  'service-role rejection creates no session'
);

select set_config('request.jwt.claims', '{}', true);
select count(*)::integer as missing_jwt_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.create_website_project_preview_session_v1(
    'eec32000-0000-4000-8000-000000000009',
    md5('create-session-missing-jwt') || md5('create-session-missing-jwt')
  )$$,
  '42501',
  'HUMAN_JWT_REQUIRED',
  'missing human JWT is rejected'
);
reset role;
select count(*)::integer as missing_jwt_after
from lws_internal.website_project_preview_sessions
\gset
select is(
  :missing_jwt_after::integer,
  :missing_jwt_before::integer,
  'missing JWT rejection creates no session'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}',
  true
);
select count(*)::integer as invalid_token_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.create_website_project_preview_session_v1(
    'eec32000-0000-4000-8000-000000000009',
    'invalid-token-hash'
  )$$,
  '22023',
  'PROJECT_PREVIEW_SESSION_TOKEN_INVALID',
  'invalid token hash is rejected'
);
reset role;
select count(*)::integer as invalid_token_after
from lws_internal.website_project_preview_sessions
\gset
select is(
  :invalid_token_after::integer,
  :invalid_token_before::integer,
  'invalid token rejection creates no session'
);

update lws_internal.website_project_preview_builds
set website_work_context_id = 'eec32000-0000-4000-8000-000000000021'
where preview_build_id = 'eec32000-0000-4000-8000-000000000009';
select count(*)::integer as context_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.create_website_project_preview_session_v1(
    'eec32000-0000-4000-8000-000000000009',
    md5('create-session-context') || md5('create-session-context')
  )$$,
  '42501',
  'PROJECT_PREVIEW_BUILD_NOT_READY',
  'cross-context build is rejected'
);
reset role;
select count(*)::integer as context_after
from lws_internal.website_project_preview_sessions
\gset
select is(
  :context_after::integer,
  :context_before::integer,
  'cross-context rejection creates no session'
);
update lws_internal.website_project_preview_builds
set website_work_context_id = 'eec32000-0000-4000-8000-000000000004'
where preview_build_id = 'eec32000-0000-4000-8000-000000000009';

update lws_internal.website_project_preview_builds
set website_workspace_id = 'eec32000-0000-4000-8000-000000000022'
where preview_build_id = 'eec32000-0000-4000-8000-000000000009';
select count(*)::integer as workspace_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.create_website_project_preview_session_v1(
    'eec32000-0000-4000-8000-000000000009',
    md5('create-session-workspace') || md5('create-session-workspace')
  )$$,
  '42501',
  'PROJECT_PREVIEW_BUILD_NOT_READY',
  'cross-workspace build is rejected'
);
reset role;
select count(*)::integer as workspace_after
from lws_internal.website_project_preview_sessions
\gset
select is(
  :workspace_after::integer,
  :workspace_before::integer,
  'cross-workspace rejection creates no session'
);
update lws_internal.website_project_preview_builds
set website_workspace_id = 'eec32000-0000-4000-8000-000000000005'
where preview_build_id = 'eec32000-0000-4000-8000-000000000009';

update lws_internal.website_project_preview_builds
set quote_request_id = 'eec32100-0000-4000-8000-000000000019'
where preview_build_id = 'eec32000-0000-4000-8000-000000000009';
select count(*)::integer as dossier_before
from lws_internal.website_project_preview_sessions
\gset
set local role authenticated;
select throws_ok(
  $$select public.create_website_project_preview_session_v1(
    'eec32000-0000-4000-8000-000000000009',
    md5('create-session-dossier') || md5('create-session-dossier')
  )$$,
  '42501',
  'PROJECT_PREVIEW_BUILD_NOT_READY',
  'cross-dossier build is rejected'
);
reset role;
select count(*)::integer as dossier_after
from lws_internal.website_project_preview_sessions
\gset
select is(
  :dossier_after::integer,
  :dossier_before::integer,
  'cross-dossier rejection creates no session'
);

select * from finish();
rollback;
