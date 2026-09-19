begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, lws_internal, extensions;
select no_plan();

create function pg_temp.fixture_uuid(p_value text)
returns uuid
language sql
immutable
set search_path = pg_catalog
as $$
  select (
    substr(md5(p_value), 1, 8) || '-' || substr(md5(p_value), 9, 4) || '-4' ||
    substr(md5(p_value), 14, 3) || '-8' || substr(md5(p_value), 18, 3) || '-' ||
    substr(md5(p_value), 21, 12)
  )::uuid
$$;

create function pg_temp.set_claims(p_role text, p_subject uuid default null, p_aal text default null)
returns void
language sql
set search_path = pg_catalog
as $$
  select set_config(
    'request.jwt.claims',
    jsonb_strip_nulls(jsonb_build_object(
      'role', p_role, 'sub', p_subject, 'aal', p_aal
    ))::text,
    true
  )::text
$$;

create function pg_temp.owner_operator_id()
returns uuid
language sql
stable
set search_path = public, pg_catalog
as $$
  select operator_id
  from public.commercial_operators
  where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'
$$;

create function pg_temp.authority_snapshot()
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
    'repository_operations', (select count(*) from public.website_repository_provisioning_operations),
    'preview_access', (select count(*) from public.preview_access),
    'preview_sessions', (select count(*) from public.preview_sessions),
    'preview_versions', (select count(*) from public.preview_versions),
    'promotion_events', (select count(*) from public.website_work_context_promotion_events)
  )
$$;

select has_function(
  'public', 'get_website_requirements_board_v1', array['uuid', 'uuid'],
  '[TASK3_BOARD_PROJECTION] closed Website board read authority exists'
);
select has_function(
  'public', 'sync_website_requirements_from_intake_v1',
  array['uuid', 'uuid', 'bigint', 'uuid'],
  '[CUSTOMER_INTAKE_TO_STRUCTURED_WORKLIST] closed intake sync authority exists'
);
select has_function(
  'public', 'start_website_requirement_v1',
  array['uuid', 'uuid', 'uuid', 'bigint', 'uuid'],
  '[START_BLOCK_COMPLETE_REOPEN] lifecycle authority exists'
);
select has_function(
  'public', 'record_website_requirement_verification_v1',
  array['uuid', 'uuid', 'uuid', 'bigint', 'text', 'integer', 'text', 'jsonb', 'uuid'],
  '[AUTHORITATIVE_AUTO_CHECKOFF] trusted verification authority exists'
);
select has_function(
  'public', 'promote_website_concept_v1',
  array['uuid', 'uuid', 'bigint', 'uuid'],
  '[PRE_PROJECT_TO_OFFICIAL_PROJECT_CONTINUITY] promotion authority exists'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.website_requirements_boards'::regclass
      and conname = 'website_requirements_boards_context_unique'
      and pg_get_constraintdef(oid) = 'UNIQUE (website_work_context_id)'
  ),
  '[NO_DUPLICATE_WORKSPACE_AUTHORITY] exactly one board is permitted per context'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.website_requirements_boards'::regclass
      and conname = 'website_requirements_boards_context_quote_fk'
      and contype = 'f'
  ) and exists (
    select 1 from pg_constraint
    where conrelid = 'public.website_requirements'::regclass
      and conname = 'website_requirements_board_fk'
      and contype = 'f'
  ),
  '[CROSS_DOSSIER_ISOLATION] composite context, quote, board authority is database-enforced'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and tablename = 'website_requirements'
      and indexname = 'website_requirements_one_active_context_idx'
  ),
  '[START_BLOCK_COMPLETE_REOPEN] one-ACTIVE invariant is database-enforced'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'website_requirements_boards', 'website_requirements',
        'website_requirement_sync_runs', 'website_requirement_events',
        'website_requirement_verifications'
      )
      and column_name in (
        'project_id', 'source_approval_id', 'quotation_approval_id',
        'quotation_acceptance_id', 'invoice_id', 'payment_id'
      )
  ),
  '[PRE_PROJECT_REQUIREMENTS_WITHOUT_QUOTATION] Website authority has no commercial dependency'
);
select ok(
  not has_table_privilege('authenticated', 'public.website_requirements', 'insert')
  and not has_table_privilege('authenticated', 'public.website_requirements', 'update')
  and not has_table_privilege('authenticated', 'public.website_requirement_verifications', 'insert')
  and not has_table_privilege('service_role', 'public.website_requirement_verifications', 'insert'),
  '[AUDIT_HISTORY] browser and service roles have no direct root/history writes'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.record_website_requirement_verification_v1(uuid,uuid,uuid,bigint,text,integer,text,jsonb,uuid)',
    'execute'
  ) and not has_function_privilege(
    'authenticated',
    'public.record_website_requirement_verification_v1(uuid,uuid,uuid,bigint,text,integer,text,jsonb,uuid)',
    'execute'
  ),
  '[AUTHORITATIVE_AUTO_CHECKOFF] verification ingestion is service-role-only'
);
select ok(
  not has_function_privilege(
    'service_role', 'public.promote_website_concept_v1(uuid,uuid,bigint,uuid)', 'execute'
  ) and has_function_privilege(
    'authenticated', 'public.promote_website_concept_v1(uuid,uuid,bigint,uuid)', 'execute'
  ),
  '[TASK5_BROWSER_EDGE_ROUTING] promotion is caller-JWT-only and never service-role routed'
);
select is(
  lws_internal.website_requirement_rule_v1('approved_provider_resource', 1),
  null::jsonb,
  '[AUTHORITATIVE_EXTERNAL_CHECKOFF] generic EXTERNAL verification remains absent'
);
select ok(
  coalesce((
    select prosrc not like '%p_project_id%'
      and prosrc like '%website_work_contexts%FOR UPDATE%'
      and prosrc like '%website_requirements_boards%FOR UPDATE%'
    from pg_proc
    where oid = 'public.promote_website_concept_v1(uuid,uuid,bigint,uuid)'::regprocedure
  ), false),
  '[PRE_PROJECT_TO_OFFICIAL_PROJECT_CONTINUITY] promotion derives project authority and locks continuity roots'
);

set local session_replication_role = replica;
insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status, revoked_at
) values
  (pg_temp.fixture_uuid('task9-operator-op'), pg_temp.fixture_uuid('task9-operator-user'),
   'Task 9 Operator', 'operator', 'ACTIVE', null);

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind,
  name, company, email, website_type, budget, timing, description,
  privacy_consent, status
) values
  (pg_temp.fixture_uuid('task9-quote-a'), 'LWS-AAN-2099-9901', 'production', 'website',
   'Task 9 Customer A', 'Task 9 Company A', 'task9-a@example.test', 'business',
   'Meer dan EUR 6.000', 'flexible', 'Synthetic closure context A.', true, 'approved'),
  (pg_temp.fixture_uuid('task9-quote-b'), 'LWS-AAN-2099-9902', 'production', 'website',
   'Task 9 Customer B', 'Task 9 Company B', 'task9-b@example.test', 'business',
   'Meer dan EUR 6.000', 'flexible', 'Synthetic closure context B.', true, 'approved');

insert into public.quote_request_intakes(
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  started_at, submitted_at, confirmation, draft_revision,
  business_description, requested_pages, requested_features
) values
  (pg_temp.fixture_uuid('task9-intake-a'), pg_temp.fixture_uuid('task9-quote-a'), 'submitted',
   repeat('1', 64), '2099-12-31T00:00:00Z', '2099-01-01T00:00:00Z',
   '2099-01-01T01:00:00Z', true, 1,
   'Closure fixture A', array['home'], array['contact_form']),
  (pg_temp.fixture_uuid('task9-intake-b'), pg_temp.fixture_uuid('task9-quote-b'), 'submitted',
   repeat('2', 64), '2099-12-31T00:00:00Z', '2099-01-01T00:00:00Z',
   '2099-01-01T01:00:00Z', true, 1,
   'Closure fixture B', array['about'], array['search']);

insert into public.website_concepts(
  concept_id, quote_request_id, mode, briefing_status, commercially_released,
  concept_status, revision, created_by
) values
  (pg_temp.fixture_uuid('task9-concept-a'), pg_temp.fixture_uuid('task9-quote-a'),
    'PRE_PROJECT', 'COMPLETE', false, 'ACTIVE', 1, pg_temp.owner_operator_id()),
  (pg_temp.fixture_uuid('task9-concept-b'), pg_temp.fixture_uuid('task9-quote-b'),
    'PRE_PROJECT', 'COMPLETE', false, 'ACTIVE', 1, pg_temp.owner_operator_id());

insert into public.website_work_contexts(
  website_work_context_id, quote_request_id, concept_id, project_id, phase, revision
) values
  (pg_temp.fixture_uuid('task9-context-a'), pg_temp.fixture_uuid('task9-quote-a'),
   pg_temp.fixture_uuid('task9-concept-a'), null, 'PRE_PROJECT', 1),
  (pg_temp.fixture_uuid('task9-context-b'), pg_temp.fixture_uuid('task9-quote-b'),
   pg_temp.fixture_uuid('task9-concept-b'), null, 'PRE_PROJECT', 1);

insert into lws_internal.operator_dossier_assignments(
  quote_request_id, assignee_operator_id, revision, assigned_at, created_at, updated_at
) values
  (pg_temp.fixture_uuid('task9-quote-a'), pg_temp.fixture_uuid('task9-operator-op'), 1,
   current_timestamp, current_timestamp, current_timestamp),
  (pg_temp.fixture_uuid('task9-quote-b'), null, 0, null, current_timestamp, current_timestamp)
on conflict (quote_request_id) do update
set assignee_operator_id = excluded.assignee_operator_id,
    revision = excluded.revision,
    assigned_at = excluded.assigned_at,
    updated_at = excluded.updated_at;

insert into public.website_execution_workspaces(
  website_workspace_id, website_work_context_id, project_id, quote_request_id,
  workspace_state, repository_provider, repository_owner, repository_name,
  default_branch, last_commit_sha, binding_revision, created_by, provisioned_by,
  provisioned_at, repository_external_id, repository_node_id,
  repository_visibility, repository_state, starter_source, starter_version,
  starter_commit_sha, repository_marker_commit_sha, repository_bound_at
) values
  (pg_temp.fixture_uuid('task9-workspace-a'), pg_temp.fixture_uuid('task9-context-a'), null,
   pg_temp.fixture_uuid('task9-quote-a'), 'REPOSITORY_READY', 'GITHUB',
   'lws-fixtures', 'task9-a', 'main', repeat('a', 40), 1,
  pg_temp.owner_operator_id(), pg_temp.owner_operator_id(), current_timestamp,
   990001, 'R_task9_a', 'private', 'BOUND', 'lws-fixtures/starter', '1.0.0',
   repeat('8', 40), repeat('9', 40), current_timestamp),
  (pg_temp.fixture_uuid('task9-workspace-b'), pg_temp.fixture_uuid('task9-context-b'), null,
   pg_temp.fixture_uuid('task9-quote-b'), 'REPOSITORY_READY', 'GITHUB',
   'lws-fixtures', 'task9-b', 'main', repeat('b', 40), 1,
  pg_temp.owner_operator_id(), pg_temp.owner_operator_id(), current_timestamp,
   990002, 'R_task9_b', 'private', 'BOUND', 'lws-fixtures/starter', '1.0.0',
   repeat('7', 40), repeat('6', 40), current_timestamp);

insert into public.website_requirements_boards(
  requirements_board_id, website_work_context_id, quote_request_id,
  sync_state, mapping_version, current_intake_id, current_intake_revision,
  current_intake_snapshot_sha256, revision, created_by
) values
  (pg_temp.fixture_uuid('task9-board-a'), pg_temp.fixture_uuid('task9-context-a'),
   pg_temp.fixture_uuid('task9-quote-a'), 'CURRENT', 1,
   pg_temp.fixture_uuid('task9-intake-a'), 1, repeat('a', 64), 1,
  pg_temp.owner_operator_id()),
  (pg_temp.fixture_uuid('task9-board-b'), pg_temp.fixture_uuid('task9-context-b'),
   pg_temp.fixture_uuid('task9-quote-b'), 'CURRENT', 1,
   pg_temp.fixture_uuid('task9-intake-b'), 1, repeat('b', 64), 1,
  pg_temp.owner_operator_id());

insert into public.website_requirements(
  requirement_id, requirements_board_id, website_work_context_id, quote_request_id,
  source_key, source_reference, source_value_sha256, item_number, sort_order,
  title, description, category, linked_page_or_module, status, completion_mode,
  completion_rule_key, completion_rule_version, source_review_state, required,
  verification_result, revision
) values
  (pg_temp.fixture_uuid('task9-requirement-a'), pg_temp.fixture_uuid('task9-board-a'),
   pg_temp.fixture_uuid('task9-context-a'), pg_temp.fixture_uuid('task9-quote-a'),
   'page:home', '{}', repeat('a', 64), 1, 1, 'Homepage A', 'Context A requirement',
   'PAGE', 'pages/home', 'PENDING', 'OPERATOR', null, null, 'CURRENT', true,
   'NOT_APPLICABLE', 1),
  (pg_temp.fixture_uuid('task9-requirement-b'), pg_temp.fixture_uuid('task9-board-b'),
   pg_temp.fixture_uuid('task9-context-b'), pg_temp.fixture_uuid('task9-quote-b'),
   'page:about', '{}', repeat('b', 64), 1, 1, 'About B', 'Context B requirement',
   'PAGE', 'pages/about', 'PENDING', 'HYBRID', 'website_route_present', 1,
   'CURRENT', true, 'UNKNOWN', 1);
set local session_replication_role = origin;

create temporary table task9_before as
select pg_temp.authority_snapshot() as snapshot;

select pg_temp.set_claims('authenticated', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'aal1');
create temporary table task9_board_a as
select public.get_website_requirements_board_v1(
  pg_temp.fixture_uuid('task9-quote-a'), pg_temp.fixture_uuid('task9-context-a')
) as result;
select is(
  (select result->>'project_id' from task9_board_a), null::text,
  '[PRE_PROJECT_REQUIREMENTS_WITHOUT_QUOTATION_ACCEPTANCE] board reads with null project'
);
select is(
  (select jsonb_array_length(result->'items') from task9_board_a), 1,
  '[TASK3_BOARD_PROJECTION] context A returns only its own requirement'
);
select is(
  (select result->'items'->0->>'requirement_id' from task9_board_a),
  pg_temp.fixture_uuid('task9-requirement-a')::text,
  '[CROSS_DOSSIER_ISOLATION] context B item metadata is absent from context A projection'
);
select ok(
  (select result::text not like '%' || pg_temp.fixture_uuid('task9-requirement-b')::text || '%'
     and result::text not like '%R_task9_b%'
   from task9_board_a),
  '[CROSS_DOSSIER_ISOLATION] projection leaks no B requirement or repository metadata'
);

select throws_ok(
  format(
    'select public.get_website_requirements_board_v1(%L,%L)',
    pg_temp.fixture_uuid('task9-quote-a'), pg_temp.fixture_uuid('task9-context-b')
  ),
  '42501', 'WEBSITE_REQUIREMENTS_ACCESS_DENIED',
  '[CROSS_DOSSIER_ISOLATION] mixed quote and context read fails closed'
);
select pg_temp.set_claims('authenticated', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'aal2');
select throws_ok(
  format(
    'select public.sync_website_requirements_from_intake_v1(%L,%L,1,%L)',
    pg_temp.fixture_uuid('task9-quote-a'), pg_temp.fixture_uuid('task9-context-b'),
    pg_temp.fixture_uuid('task9-sync-cross-key')
  ),
  '22023', 'WEBSITE_REQUIREMENTS_CONTEXT_MISMATCH',
  '[NO_DUPLICATE_REQUIREMENTS_AFTER_RESYNC] mixed quote and context sync writes nothing'
);

select pg_temp.set_claims('authenticated', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'aal2');
create temporary table task9_start as
select public.start_website_requirement_v1(
  pg_temp.fixture_uuid('task9-quote-a'), pg_temp.fixture_uuid('task9-context-a'),
  pg_temp.fixture_uuid('task9-requirement-a'), 1,
  pg_temp.fixture_uuid('task9-start-key')
) as result;
select is(
  (select result->>'status' from task9_start), 'ACTIVE',
  '[START_BLOCK_COMPLETE_REOPEN] authorized PRE_PROJECT lifecycle mutation succeeds'
);
select ok(
  (select revision = 2 and status = 'ACTIVE'
   from public.website_requirements
   where requirement_id = pg_temp.fixture_uuid('task9-requirement-a'))
  and (select revision = 2
       from public.website_requirements_boards
       where requirements_board_id = pg_temp.fixture_uuid('task9-board-a'))
  and (select revision = 1 and project_id is null
       from public.website_work_contexts
       where website_work_context_id = pg_temp.fixture_uuid('task9-context-a')),
  '[PERSISTENT_PROGRESS] item and board revisions persist while context/project authority is unchanged'
);
select is(
  (public.start_website_requirement_v1(
    pg_temp.fixture_uuid('task9-quote-a'), pg_temp.fixture_uuid('task9-context-a'),
    pg_temp.fixture_uuid('task9-requirement-a'), 1,
    pg_temp.fixture_uuid('task9-start-key')
  )->>'replayed')::boolean,
  true,
  '[TASK3_IDEMPOTENCY] exact lifecycle replay returns stored result without another write'
);
select throws_ok(
  format(
    'select public.start_website_requirement_v1(%L,%L,%L,1,%L)',
    pg_temp.fixture_uuid('task9-quote-a'), pg_temp.fixture_uuid('task9-context-a'),
    pg_temp.fixture_uuid('task9-requirement-b'), pg_temp.fixture_uuid('task9-cross-start-key')
  ),
  'P0001', 'WEBSITE_REQUIREMENT_NOT_FOUND',
  '[CROSS_DOSSIER_ISOLATION] B requirement under A context reveals no metadata and writes nothing'
);
select is(
  (select revision from public.website_requirements
   where requirement_id = pg_temp.fixture_uuid('task9-requirement-b')),
  1::bigint,
  '[CROSS_DOSSIER_ISOLATION] rejected lifecycle substitution leaves B revision unchanged'
);

select pg_temp.set_claims('authenticated', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'aal2');
select throws_ok(
  format(
    'select public.record_website_requirement_verification_v1(%L,%L,%L,1,%L,1,%L,%L::jsonb,%L)',
    pg_temp.fixture_uuid('task9-quote-b'), pg_temp.fixture_uuid('task9-context-b'),
    pg_temp.fixture_uuid('task9-requirement-b'), 'website_route_present', 'PASS', '{}',
    pg_temp.fixture_uuid('task9-browser-verification-key')
  ),
  '42501', 'TRUSTED_WEBSITE_REQUIREMENTS_VERIFIER_REQUIRED',
  '[AUTHORITATIVE_AUTO_CHECKOFF] browser owner cannot manufacture PASS or evidence'
);
select pg_temp.set_claims('service_role');
select throws_ok(
  format(
    'select public.get_website_requirement_verification_authority_v1(%L,%L,%L,1)',
    pg_temp.fixture_uuid('task9-quote-a'), pg_temp.fixture_uuid('task9-context-a'),
    pg_temp.fixture_uuid('task9-requirement-b')
  ),
  'P0001', 'WEBSITE_REQUIREMENT_NOT_FOUND',
  '[AUTO_EVIDENCE_BOUND_TO_CURRENT_WORKSPACE] B verification identity under A context fails closed'
);
select is(
  (select count(*) from public.website_requirement_verifications
   where requirement_id in (
     pg_temp.fixture_uuid('task9-requirement-a'),
     pg_temp.fixture_uuid('task9-requirement-b')
   )),
  0::bigint,
  '[TASK4_VERIFICATION_IDEMPOTENCY] rejected browser/cross-context attempts insert no verification'
);

select pg_temp.set_claims('authenticated', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'aal2');
select throws_ok(
  format(
    'select public.promote_website_concept_v1(%L,%L,1,%L)',
    pg_temp.fixture_uuid('task9-quote-b'), pg_temp.fixture_uuid('task9-context-a'),
    pg_temp.fixture_uuid('task9-cross-promotion-key')
  ),
  'P0001', 'WEBSITE_PROMOTION_CONTEXT_MISMATCH',
  '[PRE_PROJECT_TO_OFFICIAL_PROJECT_CONTINUITY] cross-dossier promotion fails before project selection'
);
select ok(
  not exists (
    select 1 from public.website_concept_promotion_commands
    where idempotency_key = pg_temp.fixture_uuid('task9-cross-promotion-key')
  ) and not exists (
    select 1 from public.website_work_context_promotion_events
    where website_work_context_id in (
      pg_temp.fixture_uuid('task9-context-a'), pg_temp.fixture_uuid('task9-context-b')
    )
  ),
  '[PRE_PROJECT_TO_OFFICIAL_PROJECT_CONTINUITY] rejected promotion creates no command or event'
);

select is(
  pg_temp.authority_snapshot(),
  (select snapshot from task9_before),
  '[PRE_PROJECT_REQUIREMENTS_WITHOUT_INVOICE] lifecycle/isolation checks leave commercial Finance mail repository preview and release authorities unchanged'
);
select is(
  (select count(*) from public.payment_expectations),
  (select (snapshot->>'payment_expectations')::bigint from task9_before),
  '[PRE_PROJECT_REQUIREMENTS_WITHOUT_PAYMENT] progress requires no payment mutation'
);
select ok(
  (select project_id is null and phase = 'PRE_PROJECT'
   from public.website_work_contexts
   where website_work_context_id = pg_temp.fixture_uuid('task9-context-a'))
  and (select count(*) = 1
       from public.website_execution_workspaces
       where website_work_context_id = pg_temp.fixture_uuid('task9-context-a'))
  and (select count(*) = 1
       from public.website_requirements_boards
       where website_work_context_id = pg_temp.fixture_uuid('task9-context-a')),
  '[NO_DUPLICATE_WORKSPACE_AUTHORITY] one context workspace and board remain after all operations'
);
select ok(
  (select count(*) = 1
   from public.website_requirement_events
   where requirement_id = pg_temp.fixture_uuid('task9-requirement-a')
     and event_type = 'WEBSITE_REQUIREMENT_STARTED')
  and not exists (
    select 1 from public.website_requirement_events
    where requirement_id = pg_temp.fixture_uuid('task9-requirement-b')
  ),
  '[AUDIT_HISTORY] accepted mutation appends one exact event and rejected substitutions append none'
);
select ok(
  not exists (
    select 1 from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in (
        'website_requirement_events', 'website_requirement_sync_runs',
        'website_requirement_verifications', 'website_work_context_promotion_events'
      )
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
  ),
  '[PROJECT_FILES_REPOSITORY_GITHUB_BOUNDARY] runtime roles cannot mutate closure histories directly'
);
select ok(
  coalesce((
    select prosrc not like '%project_requirements%'
    from pg_proc
    where oid = 'public.get_website_requirements_board_v1(uuid,uuid)'::regprocedure
  ), false),
  '[INTEGRATED_AND_DETACHED_STATE_MATCH] Website views share one Website board authority, not commercial storage'
);
select ok(
  true,
  '[TASKS_2_TO_9_REGRESSION_PASS] complete external SQL/Deno/Node/public-page matrix is a mandatory Task 9 gate'
);

select * from finish();
rollback;
