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
    substr(md5(p_value), 1, 8) || '-' ||
    substr(md5(p_value), 9, 4) || '-4' ||
    substr(md5(p_value), 14, 3) || '-8' ||
    substr(md5(p_value), 18, 3) || '-' ||
    substr(md5(p_value), 21, 12)
  )::uuid
$$;

create function pg_temp.set_claims(p_subject uuid, p_aal text)
returns void
language sql
set search_path = pg_catalog
as $$
  select set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_subject, 'role', 'authenticated', 'aal', p_aal)::text,
    true
  )::text
$$;

create function pg_temp.jsonb_keys(p_value jsonb)
returns text[]
language sql
immutable
set search_path = pg_catalog
as $$
  select coalesce(array_agg(key order by key), array[]::text[])
  from jsonb_object_keys(p_value) as keys(key)
$$;

select has_table(
  'public', 'website_requirement_command_ledger',
  'Task 3 command ledger exists'
);
select has_function(
  'public', 'get_website_requirements_board_v1', array['uuid', 'uuid'],
  'Website requirements board projection has the exact signature'
);
select has_function(
  'public', 'start_website_requirement_v1',
  array['uuid', 'uuid', 'uuid', 'bigint', 'uuid'],
  'start RPC has the exact signature'
);
select has_function(
  'public', 'block_website_requirement_v1',
  array['uuid', 'uuid', 'uuid', 'bigint', 'text', 'uuid'],
  'block RPC has the exact signature'
);
select has_function(
  'public', 'complete_website_requirement_v1',
  array['uuid', 'uuid', 'uuid', 'bigint', 'jsonb', 'uuid'],
  'complete RPC has the exact signature'
);
select has_function(
  'public', 'reopen_website_requirement_v1',
  array['uuid', 'uuid', 'uuid', 'bigint', 'text', 'uuid'],
  'reopen RPC has the exact signature'
);
select has_function(
  'public', 'resolve_website_requirement_source_change_v1',
  array['uuid', 'uuid', 'uuid', 'bigint', 'text', 'text', 'uuid'],
  'source-resolution RPC has the exact signature'
);
select has_function(
  'lws_internal', 'transition_website_requirement_core_v1',
  array['text', 'uuid', 'uuid', 'uuid', 'bigint', 'text', 'jsonb', 'text', 'uuid'],
  'one private Task 3 transition core owns lifecycle and source resolution'
);
select has_function(
  'lws_internal', 'website_requirement_permitted_actions_v1',
  array['uuid', 'uuid', 'uuid'],
  'private action projector exists'
);
select has_function(
  'lws_internal', 'website_requirements_progress_v1', array['uuid'],
  'private progress projector exists'
);
select has_function(
  'lws_internal', 'website_requirements_readiness_v1', array['uuid'],
  'private readiness projector exists'
);
select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'website_requirements'
      and indexname = 'website_requirements_one_active_context_idx'
      and indexdef ~ $$WHERE \(status = 'ACTIVE'::text\)$$
      and indexdef !~ 'source_review_state'
  ),
  'database enforces one ACTIVE requirement per context regardless of source-review state'
);

select (
  to_regclass('public.website_requirement_command_ledger') is not null
  and to_regprocedure('public.get_website_requirements_board_v1(uuid,uuid)') is not null
  and to_regprocedure('public.start_website_requirement_v1(uuid,uuid,uuid,bigint,uuid)') is not null
  and to_regprocedure('public.block_website_requirement_v1(uuid,uuid,uuid,bigint,text,uuid)') is not null
  and to_regprocedure('public.complete_website_requirement_v1(uuid,uuid,uuid,bigint,jsonb,uuid)') is not null
  and to_regprocedure('public.reopen_website_requirement_v1(uuid,uuid,uuid,bigint,text,uuid)') is not null
  and to_regprocedure('public.resolve_website_requirement_source_change_v1(uuid,uuid,uuid,bigint,text,text,uuid)') is not null
) as task3_implemented \gset

\if :task3_implemented

select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class where oid = 'public.website_requirement_command_ledger'::regclass),
  'command ledger has forced RLS'
);
select ok(
  not has_table_privilege('public', 'public.website_requirement_command_ledger', 'select')
  and not has_table_privilege('anon', 'public.website_requirement_command_ledger', 'select')
  and not has_table_privilege('authenticated', 'public.website_requirement_command_ledger', 'select')
  and not has_table_privilege('service_role', 'public.website_requirement_command_ledger', 'select'),
  'no runtime role has direct ledger access'
);
select ok(
  has_function_privilege('authenticated', 'public.get_website_requirements_board_v1(uuid,uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.start_website_requirement_v1(uuid,uuid,uuid,bigint,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.get_website_requirements_board_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.start_website_requirement_v1(uuid,uuid,uuid,bigint,uuid)', 'execute'),
  'only authenticated humans can enter public Task 3 RPCs'
);

set local session_replication_role = replica;
insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status, revoked_at
) values
  (pg_temp.fixture_uuid('wrl-owner-op'), pg_temp.fixture_uuid('wrl-owner-user'), 'WRL Owner', 'owner', 'ACTIVE', null),
  (pg_temp.fixture_uuid('wrl-admin-op'), pg_temp.fixture_uuid('wrl-admin-user'), 'WRL Admin', 'admin', 'ACTIVE', null),
  (pg_temp.fixture_uuid('wrl-manager-op'), pg_temp.fixture_uuid('wrl-manager-user'), 'WRL Manager', 'operations_manager', 'ACTIVE', null),
  (pg_temp.fixture_uuid('wrl-assigned-op'), pg_temp.fixture_uuid('wrl-assigned-user'), 'WRL Assigned', 'operator', 'ACTIVE', null),
  (pg_temp.fixture_uuid('wrl-unassigned-op'), pg_temp.fixture_uuid('wrl-unassigned-user'), 'WRL Unassigned', 'operator', 'ACTIVE', null),
  (pg_temp.fixture_uuid('wrl-reviewer-op'), pg_temp.fixture_uuid('wrl-reviewer-user'), 'WRL Reviewer', 'reviewer', 'ACTIVE', null),
  (pg_temp.fixture_uuid('wrl-readonly-op'), pg_temp.fixture_uuid('wrl-readonly-user'), 'WRL Read Only', 'read_only', 'ACTIVE', null),
  (pg_temp.fixture_uuid('wrl-inactive-op'), pg_temp.fixture_uuid('wrl-inactive-user'), 'WRL Inactive', 'owner', 'DISABLED', null),
  (pg_temp.fixture_uuid('wrl-revoked-op'), pg_temp.fixture_uuid('wrl-revoked-user'), 'WRL Revoked', 'owner', 'REVOKED', clock_timestamp());

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind,
  name, company, email, website_type, budget, timing, description,
  privacy_consent, status
) values
  (pg_temp.fixture_uuid('wrl-quote-a'), 'LWS-AAN-2099-9301', 'production', 'website',
   'WRL Customer A', 'WRL Company A', 'wrl-a@example.test', 'business',
   'Meer dan EUR 6.000', 'flexible', 'Synthetic Task 3 context A.', true, 'approved'),
  (pg_temp.fixture_uuid('wrl-quote-b'), 'LWS-AAN-2099-9302', 'production', 'website',
   'WRL Customer B', 'WRL Company B', 'wrl-b@example.test', 'business',
   'Meer dan EUR 6.000', 'flexible', 'Synthetic Task 3 context B.', true, 'approved');

insert into public.quote_request_intakes(
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  started_at, submitted_at, confirmation, draft_revision
) values
  (pg_temp.fixture_uuid('wrl-intake-a'), pg_temp.fixture_uuid('wrl-quote-a'), 'submitted',
   repeat('1', 64), '2099-12-31T00:00:00Z', '2099-01-01T00:00:00Z',
   '2099-01-01T01:00:00Z', true, 7),
  (pg_temp.fixture_uuid('wrl-intake-b'), pg_temp.fixture_uuid('wrl-quote-b'), 'submitted',
   repeat('2', 64), '2099-12-31T00:00:00Z', '2099-01-01T00:00:00Z',
   '2099-01-01T01:00:00Z', true, 3);

insert into public.website_concepts(
  concept_id, quote_request_id, mode, briefing_status, commercially_released,
  concept_status, revision, created_by
) values
  (pg_temp.fixture_uuid('wrl-concept-a'), pg_temp.fixture_uuid('wrl-quote-a'),
   'PRE_PROJECT', 'COMPLETE', false, 'ACTIVE', 1, pg_temp.fixture_uuid('wrl-owner-op')),
  (pg_temp.fixture_uuid('wrl-concept-b'), pg_temp.fixture_uuid('wrl-quote-b'),
   'PRE_PROJECT', 'COMPLETE', false, 'ACTIVE', 1, pg_temp.fixture_uuid('wrl-owner-op'));

insert into public.website_work_contexts(
  website_work_context_id, quote_request_id, concept_id, project_id, phase, revision
) values
  (pg_temp.fixture_uuid('wrl-context-a'), pg_temp.fixture_uuid('wrl-quote-a'),
   pg_temp.fixture_uuid('wrl-concept-a'), null, 'PRE_PROJECT', 4),
  (pg_temp.fixture_uuid('wrl-context-b'), pg_temp.fixture_uuid('wrl-quote-b'),
   pg_temp.fixture_uuid('wrl-concept-b'), null, 'PRE_PROJECT', 2);

insert into lws_internal.operator_dossier_assignments(
  quote_request_id, assignee_operator_id, revision, assigned_at, created_at, updated_at
) values
  (pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-assigned-op'), 1,
   '2099-01-01T00:00:00Z', '2099-01-01T00:00:00Z', '2099-01-01T00:00:00Z'),
  (pg_temp.fixture_uuid('wrl-quote-b'), null, 0, null,
   '2099-01-01T00:00:00Z', '2099-01-01T00:00:00Z')
on conflict (quote_request_id) do update
set assignee_operator_id = excluded.assignee_operator_id,
    revision = excluded.revision,
    assigned_at = excluded.assigned_at,
    updated_at = excluded.updated_at;
set local session_replication_role = origin;

select set_config('lws.website_requirement_command', 'on', true);
insert into public.website_requirements_boards(
  requirements_board_id, website_work_context_id, quote_request_id,
  sync_state, mapping_version, current_intake_id, current_intake_revision,
  current_intake_snapshot_sha256, revision, created_by
) values
  (pg_temp.fixture_uuid('wrl-board-a'), pg_temp.fixture_uuid('wrl-context-a'),
   pg_temp.fixture_uuid('wrl-quote-a'), 'REVIEW_REQUIRED', 1,
   pg_temp.fixture_uuid('wrl-intake-a'), 7, repeat('a', 64), 10,
   pg_temp.fixture_uuid('wrl-owner-op')),
  (pg_temp.fixture_uuid('wrl-board-b'), pg_temp.fixture_uuid('wrl-context-b'),
   pg_temp.fixture_uuid('wrl-quote-b'), 'CURRENT', 1,
   pg_temp.fixture_uuid('wrl-intake-b'), 3, repeat('b', 64), 1,
   pg_temp.fixture_uuid('wrl-owner-op'));

insert into public.website_requirements(
  requirement_id, requirements_board_id, website_work_context_id, quote_request_id,
  source_key, source_reference, source_value_sha256, item_number, sort_order,
  title, description, category, linked_page_or_module, status, completion_mode,
  completion_rule_key, completion_rule_version, source_review_state, required,
  started_at, completed_at, completed_by, evidence_summary,
  verification_result, blocked_reason, revision
) values
  (pg_temp.fixture_uuid('wrl-r-lifecycle'), pg_temp.fixture_uuid('wrl-board-a'), pg_temp.fixture_uuid('wrl-context-a'), pg_temp.fixture_uuid('wrl-quote-a'),
   'page:home', '{"authority_type":"WEBSITE_INTAKE","intake_id":"00000000-0000-4000-8000-000000000001","intake_revision":7,"submitted_at":"2099-01-01T01:00:00Z","source_path":"mapping_v1/page:home","source_key":"page:home","source_value_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","mapping_version":1}', repeat('a',64), 1, 1,
   'Bouw homepage', 'Lifecycle fixture', 'PAGE', 'home', 'PENDING', 'OPERATOR', null, null, 'CURRENT', true,
   null, null, null, null, 'NOT_APPLICABLE', null, 1),
  (pg_temp.fixture_uuid('wrl-r-change'), pg_temp.fixture_uuid('wrl-board-a'), pg_temp.fixture_uuid('wrl-context-a'), pg_temp.fixture_uuid('wrl-quote-a'),
   'module:forms', '{"authority_type":"WEBSITE_INTAKE","intake_id":"00000000-0000-4000-8000-000000000001","intake_revision":6,"submitted_at":"2099-01-01T01:00:00Z","source_path":"mapping_v1/module:forms","source_key":"module:forms","source_value_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","mapping_version":1}', repeat('b',64), 2, 2,
   'Oud formulier', 'Oude definitie', 'FORM', 'module:forms', 'BLOCKED', 'OPERATOR', null, null, 'CHANGE_PENDING', true,
   '2099-01-01T02:00:00Z', null, null, '{"attestation":"old"}', 'NOT_APPLICABLE', 'Wacht op klant', 3),
  (pg_temp.fixture_uuid('wrl-r-keep'), pg_temp.fixture_uuid('wrl-board-a'), pg_temp.fixture_uuid('wrl-context-a'), pg_temp.fixture_uuid('wrl-quote-a'),
   'technical:domain', '{"authority_type":"WEBSITE_INTAKE","intake_id":"00000000-0000-4000-8000-000000000001","intake_revision":6,"submitted_at":"2099-01-01T01:00:00Z","source_path":"mapping_v1/technical:domain","source_key":"technical:domain","source_value_sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","mapping_version":1}', repeat('c',64), 3, 3,
   'Behoud domein', 'Bestaande definitie', 'TECHNICAL', 'technical:domain', 'COMPLETED', 'OPERATOR', null, null, 'REMOVAL_PENDING', true,
   '2099-01-01T02:00:00Z', '2099-01-01T03:00:00Z', 'OPERATOR:' || pg_temp.fixture_uuid('wrl-assigned-op')::text,
   '{"attestation":"done"}', 'NOT_APPLICABLE', null, 4),
  (pg_temp.fixture_uuid('wrl-r-retire'), pg_temp.fixture_uuid('wrl-board-a'), pg_temp.fixture_uuid('wrl-context-a'), pg_temp.fixture_uuid('wrl-quote-a'),
   'technical:hosting', '{"authority_type":"WEBSITE_INTAKE","intake_id":"00000000-0000-4000-8000-000000000001","intake_revision":6,"submitted_at":"2099-01-01T01:00:00Z","source_path":"mapping_v1/technical:hosting","source_key":"technical:hosting","source_value_sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","mapping_version":1}', repeat('d',64), 4, 4,
   'Oude hosting', 'Te verwijderen definitie', 'TECHNICAL', 'technical:hosting', 'BLOCKED', 'HYBRID', 'website_test_suite_passed', 1, 'REMOVAL_PENDING', true,
   '2099-01-01T02:00:00Z', null, null, '{"reference":"old-pass"}', 'PASS', 'Niet meer nodig', 5),
  (pg_temp.fixture_uuid('wrl-r-cross'), pg_temp.fixture_uuid('wrl-board-b'), pg_temp.fixture_uuid('wrl-context-b'), pg_temp.fixture_uuid('wrl-quote-b'),
   'page:about', '{"authority_type":"WEBSITE_INTAKE","intake_id":"00000000-0000-4000-8000-000000000002","intake_revision":3,"submitted_at":"2099-01-01T01:00:00Z","source_path":"mapping_v1/page:about","source_key":"page:about","source_value_sha256":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","mapping_version":1}', repeat('e',64), 1, 1,
   'Bouw over ons', 'Context B fixture', 'PAGE', 'about', 'PENDING', 'OPERATOR', null, null, 'CURRENT', true,
   null, null, null, null, 'NOT_APPLICABLE', null, 1);
select set_config('lws.website_requirement_command', '', true);

select set_config('lws.website_requirement_history_command', 'on', true);
insert into public.website_requirement_sync_runs(
  sync_run_id, requirements_board_id, website_work_context_id, quote_request_id,
  intake_id, intake_revision, intake_snapshot_sha256, mapping_version,
  request_fingerprint, created_count, updated_count, retired_count,
  review_required_count, actor_id, command_id, result, proposed_changes
) values (
  pg_temp.fixture_uuid('wrl-sync-a'), pg_temp.fixture_uuid('wrl-board-a'),
  pg_temp.fixture_uuid('wrl-context-a'), pg_temp.fixture_uuid('wrl-quote-a'),
  pg_temp.fixture_uuid('wrl-intake-a'), 7, repeat('a',64), 1, repeat('f',64),
  0, 0, 0, 3, 'OPERATOR:' || pg_temp.fixture_uuid('wrl-owner-op')::text,
  pg_temp.fixture_uuid('wrl-sync-command-a'), '{}',
  jsonb_build_array(
    jsonb_build_object(
      'source_key','module:forms','action','CHANGE_PENDING',
      'requirement_id',pg_temp.fixture_uuid('wrl-r-change'),
      'previous_source_value_sha256',repeat('b',64),
      'proposed_source_value_sha256',repeat('1',64),
      'proposed_definition',jsonb_build_object(
        'title','Nieuw formulier','description','Nieuwe definitie','category','FORM',
        'linked_page_or_module','module:forms','required',true,
        'completion_mode','OPERATOR','completion_rule_key',null,
        'completion_rule_version',null,
        'source_reference',jsonb_build_object(
          'authority_type','WEBSITE_INTAKE','intake_id',pg_temp.fixture_uuid('wrl-intake-a'),
          'intake_revision',7,'submitted_at','2099-01-01T01:00:00Z',
          'source_path','mapping_v1/module:forms','source_key','module:forms',
          'source_value_sha256',repeat('1',64),'mapping_version',1
        )
      )
    ),
    jsonb_build_object(
      'source_key','technical:domain','action','REMOVAL_PENDING',
      'requirement_id',pg_temp.fixture_uuid('wrl-r-keep'),
      'previous_source_value_sha256',repeat('c',64),
      'proposed_source_value_sha256',null,'proposed_definition',null
    ),
    jsonb_build_object(
      'source_key','technical:hosting','action','REMOVAL_PENDING',
      'requirement_id',pg_temp.fixture_uuid('wrl-r-retire'),
      'previous_source_value_sha256',repeat('d',64),
      'proposed_source_value_sha256',null,'proposed_definition',null
    )
  )
);
select set_config('lws.website_requirement_history_command', '', true);

select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-owner-user'), 'aal1');
select lives_ok(
  format('select public.get_website_requirements_board_v1(%L,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a')),
  'ACTIVE owner reads without AAL2'
);
select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-admin-user'), 'aal1');
select lives_ok(
  format('select public.get_website_requirements_board_v1(%L,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a')),
  'ACTIVE admin reads without AAL2'
);
select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-manager-user'), 'aal1');
select lives_ok(
  format('select public.get_website_requirements_board_v1(%L,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a')),
  'ACTIVE operations manager reads without AAL2'
);
select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-assigned-user'), 'aal1');
select lives_ok(
  format('select public.get_website_requirements_board_v1(%L,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a')),
  'exact assigned ACTIVE operator reads without AAL2'
);
select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-unassigned-user'), 'aal2');
select throws_ok(
  format('select public.get_website_requirements_board_v1(%L,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a')),
  '42501', 'WEBSITE_REQUIREMENT_ASSIGNMENT_DENIED',
  'unassigned operator read is denied without metadata'
);
select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-reviewer-user'), 'aal2');
select throws_ok(
  format('select public.get_website_requirements_board_v1(%L,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a')),
  '42501', 'WEBSITE_REQUIREMENT_ROLE_DENIED', 'reviewer read is denied'
);
select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-readonly-user'), 'aal2');
select throws_ok(
  format('select public.get_website_requirements_board_v1(%L,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a')),
  '42501', 'WEBSITE_REQUIREMENT_ROLE_DENIED', 'read-only role is denied'
);
select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-inactive-user'), 'aal2');
select throws_ok(
  format('select public.get_website_requirements_board_v1(%L,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a')),
  '42501', 'WEBSITE_REQUIREMENTS_ACCESS_DENIED', 'disabled operator is denied without metadata'
);
select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-revoked-user'), 'aal2');
select throws_ok(
  format('select public.get_website_requirements_board_v1(%L,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a')),
  '42501', 'WEBSITE_REQUIREMENTS_ACCESS_DENIED', 'revoked operator is denied without metadata'
);

select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-owner-user'), 'aal1');
select throws_ok(
  format('select public.start_website_requirement_v1(%L,%L,%L,1,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'), pg_temp.fixture_uuid('wrl-r-lifecycle'), pg_temp.fixture_uuid('wrl-key-aal1')),
  '42501', 'AAL2_REQUIRED', 'all mutations require AAL2'
);
select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-admin-user'), 'aal2');
select throws_ok(
  format('select public.start_website_requirement_v1(%L,%L,%L,1,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'), pg_temp.fixture_uuid('wrl-r-lifecycle'), pg_temp.fixture_uuid('wrl-key-admin')),
  '42501', 'WEBSITE_REQUIREMENT_ROLE_DENIED', 'admin mutation is denied'
);
select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-unassigned-user'), 'aal2');
select throws_ok(
  format('select public.start_website_requirement_v1(%L,%L,%L,1,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'), pg_temp.fixture_uuid('wrl-r-lifecycle'), pg_temp.fixture_uuid('wrl-key-unassigned')),
  '42501', 'WEBSITE_REQUIREMENT_ASSIGNMENT_DENIED', 'unassigned operator mutation is denied'
);

select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-assigned-user'), 'aal2');
create temporary table lifecycle_results(command text primary key, result jsonb);
insert into lifecycle_results values (
  'start', public.start_website_requirement_v1(
    pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'),
    pg_temp.fixture_uuid('wrl-r-lifecycle'), 1, pg_temp.fixture_uuid('wrl-key-start')
  )
);
select is((select result->>'status' from lifecycle_results where command='start'), 'ACTIVE', 'PENDING starts to ACTIVE');
select ok((select started_at is not null and blocked_reason is null from public.website_requirements where requirement_id=pg_temp.fixture_uuid('wrl-r-lifecycle')), 'start sets started_at and clears blocked reason');
select is((select revision from public.website_requirements where requirement_id=pg_temp.fixture_uuid('wrl-r-lifecycle')), 2::bigint, 'start increments requirement revision');
select is((select revision from public.website_requirements_boards where requirements_board_id=pg_temp.fixture_uuid('wrl-board-a')), 11::bigint, 'start increments board revision');
select is((select revision from public.website_work_contexts where website_work_context_id=pg_temp.fixture_uuid('wrl-context-a')), 4::bigint, 'start leaves context revision unchanged');
select throws_ok(
  format('select public.start_website_requirement_v1(%L,%L,%L,1,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'), pg_temp.fixture_uuid('wrl-r-lifecycle'), pg_temp.fixture_uuid('wrl-key-stale')),
  '40001', 'CONCURRENT_MODIFICATION', 'stale requirement revision is rejected'
);
insert into lifecycle_results values (
  'block', public.block_website_requirement_v1(
    pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'),
    pg_temp.fixture_uuid('wrl-r-lifecycle'), 2, '  Wacht op content  ', pg_temp.fixture_uuid('wrl-key-block')
  )
);
select is((select blocked_reason from public.website_requirements where requirement_id=pg_temp.fixture_uuid('wrl-r-lifecycle')), 'Wacht op content', 'block normalizes reason');
select throws_ok(
  format('select public.block_website_requirement_v1(%L,%L,%L,3,%L,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'), pg_temp.fixture_uuid('wrl-r-lifecycle'), '', pg_temp.fixture_uuid('wrl-key-block-empty')),
  '22023', 'WEBSITE_REQUIREMENT_BLOCK_REASON_REQUIRED', 'empty block reason is rejected'
);
insert into lifecycle_results values (
  'restart', public.start_website_requirement_v1(
    pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'),
    pg_temp.fixture_uuid('wrl-r-lifecycle'), 3, pg_temp.fixture_uuid('wrl-key-restart')
  )
);
insert into lifecycle_results values (
  'complete', public.complete_website_requirement_v1(
    pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'),
    pg_temp.fixture_uuid('wrl-r-lifecycle'), 4, '{"attestation":"  Handmatig gecontroleerd  "}', pg_temp.fixture_uuid('wrl-key-complete')
  )
);
select ok(
  (select status='COMPLETED' and completed_by='OPERATOR:' || pg_temp.fixture_uuid('wrl-assigned-op')::text
     and verification_result='NOT_APPLICABLE'
     and evidence_summary='{"attestation":"Handmatig gecontroleerd"}'::jsonb
   from public.website_requirements where requirement_id=pg_temp.fixture_uuid('wrl-r-lifecycle')),
  'OPERATOR completion stores exact normalized attestation and actor'
);
select throws_ok(
  format('select public.complete_website_requirement_v1(%L,%L,%L,5,%L::jsonb,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'), pg_temp.fixture_uuid('wrl-r-lifecycle'), '{"attestation":"x","extra":true}', pg_temp.fixture_uuid('wrl-key-attestation-extra')),
  '22023', 'WEBSITE_REQUIREMENT_ATTESTATION_REQUIRED', 'surplus attestation keys are rejected'
);
select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-assigned-user'), 'aal2');
select throws_ok(
  format('select public.reopen_website_requirement_v1(%L,%L,%L,5,%L,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'), pg_temp.fixture_uuid('wrl-r-lifecycle'), 'Operator may not reopen', pg_temp.fixture_uuid('wrl-key-reopen-operator')),
  '42501', 'WEBSITE_REQUIREMENT_ROLE_DENIED', 'operator cannot reopen'
);
select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-owner-user'), 'aal2');
insert into lifecycle_results values (
  'reopen', public.reopen_website_requirement_v1(
    pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'),
    pg_temp.fixture_uuid('wrl-r-lifecycle'), 5, '  Correctie nodig  ', pg_temp.fixture_uuid('wrl-key-reopen')
  )
);
select ok(
  (select status='PENDING' and started_at is null and blocked_reason is null
     and completed_at is null and completed_by is null and evidence_summary is null
     and verification_result='NOT_APPLICABLE'
   from public.website_requirements where requirement_id=pg_temp.fixture_uuid('wrl-r-lifecycle')),
  'management reopen resets current completion without changing identity'
);
select is(
  (select count(*)::integer from public.website_requirement_events where requirement_id=pg_temp.fixture_uuid('wrl-r-lifecycle') and event_type='WEBSITE_REQUIREMENT_EVIDENCE_INVALIDATED'),
  1, 'reopen appends evidence invalidation without deleting history'
);
select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-assigned-user'), 'aal2');
select is(
  public.start_website_requirement_v1(
    pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'),
    pg_temp.fixture_uuid('wrl-r-lifecycle'), 1, pg_temp.fixture_uuid('wrl-key-start')
  )->>'replayed',
  'true', 'same idempotency identity and fingerprint replays'
);
select is((select revision from public.website_requirements where requirement_id=pg_temp.fixture_uuid('wrl-r-lifecycle')), 6::bigint, 'replay does not increment revision');
select throws_ok(
  format('select public.start_website_requirement_v1(%L,%L,%L,2,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'), pg_temp.fixture_uuid('wrl-r-lifecycle'), pg_temp.fixture_uuid('wrl-key-start')),
  'P0001', 'WEBSITE_REQUIREMENT_IDEMPOTENCY_CONFLICT', 'same idempotency identity with changed fingerprint conflicts'
);

select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-owner-user'), 'aal2');
select throws_ok(
  format('select public.start_website_requirement_v1(%L,%L,%L,1,%L)', pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'), pg_temp.fixture_uuid('wrl-r-cross'), pg_temp.fixture_uuid('wrl-key-cross')),
  'P0001', 'WEBSITE_REQUIREMENT_NOT_FOUND', 'cross-context requirement substitution reveals no metadata'
);
select throws_ok(
  format('select public.get_website_requirements_board_v1(%L,%L)', pg_temp.fixture_uuid('wrl-quote-b'), pg_temp.fixture_uuid('wrl-context-a')),
  '42501', 'WEBSITE_REQUIREMENTS_ACCESS_DENIED', 'cross-dossier board substitution fails closed'
);

create temporary table source_results(command text primary key, result jsonb);
insert into source_results values (
  'accept', public.resolve_website_requirement_source_change_v1(
    pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'),
    pg_temp.fixture_uuid('wrl-r-change'), 3, 'ACCEPT_CHANGE', '  Nieuwe intake volgen  ',
    pg_temp.fixture_uuid('wrl-key-accept')
  )
);
select ok(
  (select title='Nieuw formulier' and description='Nieuwe definitie'
     and source_value_sha256=repeat('1',64) and source_review_state='CURRENT'
     and status='PENDING' and blocked_reason is null and started_at is null
   from public.website_requirements where requirement_id=pg_temp.fixture_uuid('wrl-r-change')),
  'ACCEPT_CHANGE applies only the immutable current proposal and resets execution state'
);
select is(
  (select count(*)::integer from public.website_requirement_events where requirement_id=pg_temp.fixture_uuid('wrl-r-change') and event_type='WEBSITE_REQUIREMENT_EVIDENCE_INVALIDATED'),
  1, 'ACCEPT_CHANGE invalidates prior execution evidence'
);
insert into source_results values (
  'keep', public.resolve_website_requirement_source_change_v1(
    pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'),
    pg_temp.fixture_uuid('wrl-r-keep'), 4, 'KEEP_EXISTING', 'Bestaande uitvoering behouden',
    pg_temp.fixture_uuid('wrl-key-keep')
  )
);
select ok(
  (select source_review_state='CURRENT' and status='COMPLETED'
     and title='Behoud domein' and source_value_sha256=repeat('c',64)
     and completed_at='2099-01-01T03:00:00Z'::timestamptz
     and evidence_summary='{"attestation":"done"}'::jsonb
   from public.website_requirements where requirement_id=pg_temp.fixture_uuid('wrl-r-keep')),
  'KEEP_EXISTING changes only source-review state plus revisions/events'
);
select is((select sync_state from public.website_requirements_boards where requirements_board_id=pg_temp.fixture_uuid('wrl-board-a')), 'REVIEW_REQUIRED', 'one unresolved source item keeps board REVIEW_REQUIRED');
insert into source_results values (
  'retire', public.resolve_website_requirement_source_change_v1(
    pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a'),
    pg_temp.fixture_uuid('wrl-r-retire'), 5, 'RETIRE', 'Hosting vervalt uit scope',
    pg_temp.fixture_uuid('wrl-key-retire')
  )
);
select ok(
  (select source_review_state='RETIRED' and required=false and status='PENDING'
     and started_at is null and blocked_reason is null and evidence_summary is null
     and verification_result='UNKNOWN'
   from public.website_requirements where requirement_id=pg_temp.fixture_uuid('wrl-r-retire')),
  'RETIRE resets ACTIVE/BLOCKED execution and never deletes the item'
);
select is((select sync_state from public.website_requirements_boards where requirements_board_id=pg_temp.fixture_uuid('wrl-board-a')), 'CURRENT', 'last source resolution clears board review state');

select pg_temp.set_claims(pg_temp.fixture_uuid('wrl-owner-user'), 'aal1');
create temporary table board_projection as
select public.get_website_requirements_board_v1(
  pg_temp.fixture_uuid('wrl-quote-a'), pg_temp.fixture_uuid('wrl-context-a')
) as result;
select is(
  pg_temp.jsonb_keys((select result from board_projection)),
  array['board','context','contract_version','empty_state','items','phase','progress','project_id','quote_request_id','readiness','website_work_context_id']::text[],
  'board projection has exact root keys'
);
select is(
  pg_temp.jsonb_keys((select result->'items'->0 from board_projection)),
  array['blocked_reason','category','completed_at','completion_mode','description','item_number','linked_page_or_module','permitted_actions','required','requirement_id','revision','sort_order','source','source_review_state','started_at','status','title','verification_result']::text[],
  'item projection has exact keys'
);
select is(
  pg_temp.jsonb_keys((select result->'items'->0->'source' from board_projection)),
  array['authority_type','intake_id','intake_revision','mapping_version','source_key','submitted_at']::text[],
  'safe source projection has exact allowlisted keys'
);
select is(
  pg_temp.jsonb_keys((select result->'progress' from board_projection)),
  array['required_blocked','required_completed','required_open','required_total','review_pending']::text[],
  'progress has exact keys'
);
select is(
  pg_temp.jsonb_keys((select result->'readiness' from board_projection)),
  array['readiness','ready_for_preview','reason']::text[],
  'readiness has exact keys'
);
select is((select result->>'project_id' from board_projection), null, 'PRE_PROJECT board projects null informational project_id');
select is((select result->>'phase' from board_projection), 'PRE_PROJECT', 'lifecycle works in PRE_PROJECT');
select is((select (result->'progress'->>'review_pending')::integer from board_projection), 0, 'resolved and retired sources are excluded from review_pending');
select is((select result->'readiness'->>'reason' from board_projection), 'REQUIRED_REQUIREMENTS_OPEN', 'readiness applies exact priority after review clears');
select ok(
  not ((select result from board_projection)::text ~* 'source_value_sha256|source_path|proposed_definition|token|credential'),
  'board projection exposes no source hash, proposal, token, or credential'
);

select is(
  pg_temp.jsonb_keys((select result from lifecycle_results where command='start')),
  array['board_revision','command','contract_version','previous_source_review_state','previous_status','quote_request_id','replayed','requirement_id','requirement_revision','requirements_board_id','resolution','source_review_state','status','website_work_context_id']::text[],
  'mutation result has exact root keys'
);
select is(
  (select count(*)::integer from public.website_requirement_events
   where event_type not in (
     'WEBSITE_REQUIREMENT_STARTED','WEBSITE_REQUIREMENT_BLOCKED',
     'WEBSITE_REQUIREMENT_COMPLETED','WEBSITE_REQUIREMENT_REOPENED',
     'WEBSITE_REQUIREMENT_SOURCE_CHANGE_ACCEPTED','WEBSITE_REQUIREMENT_SOURCE_KEPT',
     'WEBSITE_REQUIREMENT_RETIRED','WEBSITE_REQUIREMENT_EVIDENCE_INVALIDATED'
   )),
  0, 'Task 3 emits only the exact event vocabulary'
);
select ok(
  not exists (
    select 1 from public.website_requirement_events
    where pg_temp.jsonb_keys(metadata) is distinct from
      array['board_revision','new_revision','new_source_review_state','new_status',
             'previous_revision','previous_source_review_state','previous_status',
             'reason','requirement_id','requirements_board_id','resolution',
             'source_key','sync_run_id']::text[]
      or metadata::text ~* 'proposed_definition|attestation|token|credential'
  ),
  'every Task 3 event uses the exact safe metadata shape'
);
select throws_ok(
  $$delete from public.website_requirement_command_ledger$$,
  '55000', 'WEBSITE_REQUIREMENT_COMMAND_LEDGER_IMMUTABLE',
  'command ledger rows cannot be deleted'
);
select throws_ok(
  $$delete from public.website_requirement_events$$,
  '55000', 'WEBSITE_REQUIREMENT_HISTORY_IMMUTABLE',
  'Task 3 events remain immutable'
);
select is((select count(*)::integer from public.commercial_projects), 0, 'Task 3 creates no commercial project');
select is((select count(*)::integer from public.quote_request_quotation_acceptances), 0, 'Task 3 requires no quotation acceptance');

\endif

select * from finish();
rollback;