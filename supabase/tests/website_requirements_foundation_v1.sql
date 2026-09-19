begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, lws_internal, extensions;

select no_plan();

select has_table('public', 'website_requirements_boards', 'Website requirements board root exists');
select has_table('public', 'website_requirements', 'Website requirement item root exists');
select has_table('public', 'website_requirement_sync_runs', 'Website requirement sync root exists');
select has_table('public', 'website_requirement_events', 'Website requirement event root exists');
select has_table('public', 'website_requirement_verifications', 'Website requirement verification root exists');

select col_is_pk('public', 'website_requirements_boards', 'requirements_board_id', 'board uses the exact primary key');
select col_is_pk('public', 'website_requirements', 'requirement_id', 'item uses the exact primary key');
select col_is_pk('public', 'website_requirement_sync_runs', 'sync_run_id', 'sync run uses the exact primary key');
select col_is_pk('public', 'website_requirement_events', 'event_id', 'event uses the exact primary key');
select col_is_pk('public', 'website_requirement_verifications', 'verification_id', 'verification uses the exact primary key');

select is(
  (select jsonb_object_agg(table_name, columns order by table_name)
   from (
     select table_name, jsonb_agg(column_name order by ordinal_position) as columns
     from information_schema.columns
     where table_schema = 'public'
       and table_name in (
         'website_requirements_boards', 'website_requirements',
         'website_requirement_sync_runs', 'website_requirement_events',
         'website_requirement_verifications'
       )
     group by table_name
   ) as actual),
  '{
    "website_requirement_events":["event_id","requirements_board_id","website_work_context_id","quote_request_id","requirement_id","event_type","actor_id","command_id","prior_revision","new_revision","reason","metadata","occurred_at"],
    "website_requirement_sync_runs":["sync_run_id","requirements_board_id","website_work_context_id","quote_request_id","intake_id","intake_revision","intake_snapshot_sha256","mapping_version","request_fingerprint","created_count","updated_count","retired_count","review_required_count","actor_id","command_id","result","created_at","proposed_changes"],
    "website_requirement_verifications":["verification_id","requirement_id","requirements_board_id","website_work_context_id","quote_request_id","website_workspace_id","binding_revision","canonical_commit_sha","requirement_revision","rule_key","rule_version","result","evidence_reference","evidence_sha256","verified_by","verified_at","expires_at"],
    "website_requirements":["requirement_id","requirements_board_id","website_work_context_id","quote_request_id","source_key","source_reference","source_value_sha256","item_number","sort_order","title","description","category","linked_page_or_module","status","completion_mode","completion_rule_key","completion_rule_version","source_review_state","required","started_at","completed_at","completed_by","evidence_summary","verification_result","blocked_reason","revision","created_at","updated_at"],
    "website_requirements_boards":["requirements_board_id","website_work_context_id","quote_request_id","sync_state","mapping_version","current_intake_id","current_intake_revision","current_intake_snapshot_sha256","revision","created_by","created_at","updated_at"]
  }'::jsonb,
  'Website requirements roots expose only the exact foundation columns'
);

select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'website_requirements_boards', 'website_requirements',
        'website_requirement_sync_runs', 'website_requirement_events',
        'website_requirement_verifications'
      )
      and (
        (column_name in (
          'requirements_board_id', 'requirement_id', 'sync_run_id', 'event_id',
          'verification_id', 'website_work_context_id', 'quote_request_id',
          'website_workspace_id', 'command_id', 'current_intake_id', 'intake_id'
        ) and udt_name <> 'uuid')
        or (column_name in (
          'requirements_board_id', 'sync_run_id', 'event_id', 'verification_id',
          'requirements_board_id', 'website_work_context_id', 'quote_request_id'
        ) and is_nullable <> 'NO')
        or (table_name = 'website_requirement_verifications'
          and column_name = 'requirement_id' and is_nullable <> 'NO')
        or (table_name = 'website_requirement_events'
          and column_name = 'requirement_id' and is_nullable <> 'YES')
      )
  ),
  'authority identities have exact UUID types and nullability'
);

select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'website_requirements_boards', 'website_requirements',
        'website_requirement_sync_runs', 'website_requirement_events',
        'website_requirement_verifications'
      )
      and column_name in (
        'project_id', 'source_approval_id', 'quotation_approval_id',
        'quotation_acceptance_id', 'invoice_id', 'payment_id',
        'token', 'credential', 'password', 'secret', 'service_role_key',
        'repository_url', 'temporary_url'
      )
  ),
  'Website requirements roots contain no commercial authority or secret-bearing columns'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.website_work_contexts'::regclass
      and conname = 'website_work_contexts_context_quote_unique'
      and contype = 'u'
      and pg_get_constraintdef(oid) = 'UNIQUE (website_work_context_id, quote_request_id)'
  ),
  'work context exposes the exact context and quote authority target'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = to_regclass('public.website_requirements_boards')
      and conname = 'website_requirements_boards_context_unique'
      and contype = 'u'
      and pg_get_constraintdef(oid) = 'UNIQUE (website_work_context_id)'
  ),
  'one board is allowed per Website work context'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = to_regclass('public.website_requirements_boards')
      and conname = 'website_requirements_boards_context_quote_fk'
      and contype = 'f'
      and confrelid = 'public.website_work_contexts'::regclass
      and pg_get_constraintdef(oid) like 'FOREIGN KEY (website_work_context_id, quote_request_id) REFERENCES website_work_contexts(website_work_context_id, quote_request_id)%'
  ),
  'board has the exact context and quote composite foreign key'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = to_regclass('public.website_requirements_boards')
      and conname = 'website_requirements_boards_authority_unique'
      and contype = 'u'
      and pg_get_constraintdef(oid) = 'UNIQUE (requirements_board_id, website_work_context_id, quote_request_id)'
  ),
  'board exposes the exact child authority target'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = to_regclass('public.website_requirements')
      and conname = 'website_requirements_board_fk'
      and contype = 'f'
      and pg_get_constraintdef(oid) like 'FOREIGN KEY (requirements_board_id, website_work_context_id, quote_request_id) REFERENCES website_requirements_boards(requirements_board_id, website_work_context_id, quote_request_id)%'
  ),
  'items have the exact board authority foreign key'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = to_regclass('public.website_requirements')
      and conname = 'website_requirements_authority_unique'
      and contype = 'u'
      and pg_get_constraintdef(oid) = 'UNIQUE (requirement_id, requirements_board_id, website_work_context_id, quote_request_id)'
  ),
  'items expose the exact requirement authority target'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = to_regclass('public.website_requirement_sync_runs')
      and conname = 'website_requirement_sync_runs_board_fk'
      and contype = 'f'
      and pg_get_constraintdef(oid) like 'FOREIGN KEY (requirements_board_id, website_work_context_id, quote_request_id) REFERENCES website_requirements_boards(requirements_board_id, website_work_context_id, quote_request_id)%'
  ),
  'sync runs have the exact board authority foreign key'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = to_regclass('public.website_requirement_events')
      and conname = 'website_requirement_events_board_fk'
      and contype = 'f'
  ) and exists (
    select 1 from pg_constraint
    where conrelid = to_regclass('public.website_requirement_events')
      and conname = 'website_requirement_events_requirement_fk'
      and contype = 'f'
      and confmatchtype = 's'
  ),
  'events have board and MATCH SIMPLE requirement authority foreign keys'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = to_regclass('public.website_requirement_verifications')
      and conname = 'website_requirement_verifications_requirement_fk'
      and contype = 'f'
      and pg_get_constraintdef(oid) like 'FOREIGN KEY (requirement_id, requirements_board_id, website_work_context_id, quote_request_id) REFERENCES website_requirements(requirement_id, requirements_board_id, website_work_context_id, quote_request_id)%'
  ),
  'verifications have the exact requirement authority foreign key'
);

select ok(
  not exists (
    select 1
    from (values
      ('website_requirements_boards'), ('website_requirements'),
      ('website_requirement_sync_runs'), ('website_requirement_events'),
      ('website_requirement_verifications')
    ) as expected(table_name)
    left join pg_class as relation
      on relation.oid = to_regclass('public.' || expected.table_name)
    where relation.oid is null
       or not relation.relrowsecurity
       or not relation.relforcerowsecurity
  ),
  'all five Website requirements roots force RLS'
);

select ok(
  not exists (
    select 1
    from information_schema.role_table_grants
    where grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
      and table_schema = 'public'
      and table_name in (
        'website_requirements_boards', 'website_requirements',
        'website_requirement_sync_runs', 'website_requirement_events',
        'website_requirement_verifications'
      )
  ),
  'runtime roles have no direct Website requirements table privileges'
);

select ok(
  (select count(*) from pg_trigger
   where tgrelid in (
     to_regclass('public.website_requirements_boards'),
     to_regclass('public.website_requirements')
   ) and not tgisinternal and tgname like '%command_guard%') = 2,
  'board and item writes are internally command guarded'
);

select ok(
  (select count(*) from pg_trigger
   where tgrelid in (
     to_regclass('public.website_requirement_sync_runs'),
     to_regclass('public.website_requirement_events'),
     to_regclass('public.website_requirement_verifications')
   ) and not tgisinternal and tgname like '%guard%') = 3,
  'sync, event, and verification roots have insert-command and immutability guards'
);

select ok(
  not exists (
    select expected.index_name
    from (values
      ('website_requirements_source_key_current_idx'),
      ('website_requirements_item_number_current_idx'),
      ('website_requirements_sort_order_current_idx'),
      ('website_requirements_one_active_context_idx'),
      ('website_requirements_context_status_idx'),
      ('website_requirement_sync_runs_context_created_idx'),
      ('website_requirement_events_context_occurred_idx'),
      ('website_requirement_events_requirement_occurred_idx'),
      ('website_requirement_verifications_current_idx')
    ) as expected(index_name)
    where to_regclass('public.' || expected.index_name) is null
  ),
  'current-item, active-item, history, and verification indexes exist'
);

create function pg_temp.website_requirements_foundation_fixture_v1()
returns jsonb
language plpgsql
as $$
declare
  context_a constant uuid := 'f1900000-0000-4000-8000-000000000001';
  context_b constant uuid := 'f1900000-0000-4000-8000-000000000002';
  quote_a constant uuid := 'f1910000-0000-4000-8000-000000000001';
  quote_b constant uuid := 'f1910001-0000-4000-8000-000000000002';
  board_a constant uuid := 'f1920000-0000-4000-8000-000000000001';
  board_b constant uuid := 'f1920000-0000-4000-8000-000000000002';
  requirement_a constant uuid := 'f1930000-0000-4000-8000-000000000001';
  requirement_b constant uuid := 'f1930000-0000-4000-8000-000000000002';
  result jsonb := '{}'::jsonb;
  rejected boolean;
begin
  insert into public.quote_requests(
    id, request_kind, created_at, name, email, website_type, budget, timing,
    description, privacy_consent, status
  ) values
    (quote_a, 'website', '2099-01-01T00:00:00Z', 'Requirements A', 'requirements-a@example.test',
     'business', 'Budget', 'Timing', 'PRE_PROJECT requirements fixture A.', true, 'approved'),
    (quote_b, 'website', '2099-01-01T00:00:00Z', 'Requirements B', 'requirements-b@example.test',
     'business', 'Budget', 'Timing', 'PRE_PROJECT requirements fixture B.', true, 'approved');

  insert into public.quote_request_intakes(
    id, quote_request_id, status, access_token_hash, access_token_expires_at,
    started_at, submitted_at, confirmation
  ) values
    ('f1970000-0000-4000-8000-000000000001', quote_b, 'submitted', repeat('1', 64),
     '2099-01-03T00:00:00Z', '2099-01-01T01:00:00Z', '2099-01-01T02:00:00Z', true),
    ('f1970000-0000-4000-8000-000000000002', quote_a, 'submitted', repeat('2', 64),
     '2099-01-03T00:00:00Z', '2099-01-01T01:00:00Z', '2099-01-01T02:00:00Z', true);

  insert into auth.users(id, email)
  values ('f1940000-0000-4000-8000-000000000002', 'requirements-foundation@example.test');

  set local session_replication_role = replica;
  insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status)
  values (
    'f1940000-0000-4000-8000-000000000001',
    'f1940000-0000-4000-8000-000000000002',
    'Requirements Foundation', 'owner', 'ACTIVE'
  );
  insert into public.website_concepts(
    concept_id, quote_request_id, mode, briefing_status, commercially_released,
    concept_status, revision, created_by
  ) values
    ('f1950000-0000-4000-8000-000000000001', quote_a, 'PRE_PROJECT', 'COMPLETE', false,
     'ACTIVE', 1, 'f1940000-0000-4000-8000-000000000001'),
    ('f1950000-0000-4000-8000-000000000002', quote_b, 'PRE_PROJECT', 'COMPLETE', false,
     'ACTIVE', 1, 'f1940000-0000-4000-8000-000000000001');
  insert into public.website_work_contexts(
    website_work_context_id, quote_request_id, concept_id, project_id, phase, revision
  ) values
    (context_a, quote_a, 'f1950000-0000-4000-8000-000000000001', null, 'PRE_PROJECT', 1),
    (context_b, quote_b, 'f1950000-0000-4000-8000-000000000002', null, 'PRE_PROJECT', 1);
  set local session_replication_role = origin;

  perform set_config('lws.website_requirement_command', 'on', true);
  insert into public.website_requirements_boards(
    requirements_board_id, website_work_context_id, quote_request_id,
    sync_state, mapping_version, revision, created_by
  ) values
    (board_a, context_a, quote_a, 'CURRENT', 1, 1, 'f1940000-0000-4000-8000-000000000001'),
    (board_b, context_b, quote_b, 'CURRENT', 1, 1, 'f1940000-0000-4000-8000-000000000001');
  insert into public.website_requirements(
    requirement_id, requirements_board_id, website_work_context_id, quote_request_id,
    source_key, source_reference, source_value_sha256, item_number, sort_order,
    title, description, category, status, completion_mode, source_review_state,
    required, verification_result, revision
  ) values
    (requirement_a, board_a, context_a, quote_a, 'page:home', '{"source_path":"requested_pages"}', repeat('a', 64),
     1, 1, 'Homepage', 'Build the requested homepage.', 'PAGE', 'PENDING', 'OPERATOR', 'CURRENT', true, 'UNKNOWN', 1),
    (requirement_b, board_b, context_b, quote_b, 'page:contact', '{"source_path":"requested_pages"}', repeat('b', 64),
     1, 1, 'Contact', 'Build the requested contact page.', 'PAGE', 'PENDING', 'OPERATOR', 'CURRENT', true, 'UNKNOWN', 1);
  perform set_config('lws.website_requirement_command', '', true);

  result := result || jsonb_build_object(
    'pre_project', exists (
      select 1 from public.website_requirements_boards as board
      join public.website_work_contexts as context using (website_work_context_id, quote_request_id)
      join public.website_concepts as concept using (concept_id, quote_request_id)
      where board.requirements_board_id = board_a
        and context.phase = 'PRE_PROJECT' and context.project_id is null
        and concept.commercially_released = false
    )
  );

  rejected := false;
  begin
    perform set_config('lws.website_requirement_command', 'on', true);
    insert into public.website_requirements_boards(
      requirements_board_id, website_work_context_id, quote_request_id,
      sync_state, mapping_version, revision, created_by
    ) values (
      'f1920000-0000-4000-8000-000000000003', context_a, quote_b,
      'CURRENT', 1, 1, 'f1940000-0000-4000-8000-000000000001'
    );
  exception when foreign_key_violation or unique_violation then rejected := true;
  end;
  result := result || jsonb_build_object('context_quote', rejected);

  rejected := false;
  begin
    perform set_config('lws.website_requirement_command', 'on', true);
    insert into public.website_requirements(
      requirements_board_id, website_work_context_id, quote_request_id,
      source_key, source_reference, source_value_sha256, item_number, sort_order,
      title, description, category, status, completion_mode, source_review_state,
      required, verification_result, revision
    ) values (
      board_a, context_b, quote_b, 'other:wrong-board', '{"source_path":"other"}', repeat('c', 64),
      2, 2, 'Wrong board', 'Must fail.', 'OTHER', 'PENDING', 'OPERATOR', 'CURRENT', true, 'UNKNOWN', 1
    );
  exception when foreign_key_violation then rejected := true;
  end;
  result := result || jsonb_build_object('board_context', rejected);

  rejected := false;
  begin
    perform set_config('lws.website_requirement_history_command', 'on', true);
    insert into public.website_requirement_sync_runs(
      sync_run_id, requirements_board_id, website_work_context_id, quote_request_id,
      intake_id, intake_revision, intake_snapshot_sha256, mapping_version,
      request_fingerprint, created_count, updated_count, retired_count,
      review_required_count, actor_id, command_id, result
    ) values (
      'f1960000-0000-4000-8000-000000000001', board_a, context_b, quote_b,
      'f1970000-0000-4000-8000-000000000001', 1, repeat('d', 64), 1,
      repeat('e', 64), 0, 0, 0, 0, 'OPERATOR:f1940000-0000-4000-8000-000000000001',
      'f1980000-0000-4000-8000-000000000001', '{}'
    );
  exception when foreign_key_violation then rejected := true;
  end;
  result := result || jsonb_build_object('sync_board', rejected);

  rejected := false;
  begin
    perform set_config('lws.website_requirement_history_command', 'on', true);
    insert into public.website_requirement_events(
      event_id, requirements_board_id, website_work_context_id, quote_request_id,
      requirement_id, event_type, actor_id, command_id, prior_revision,
      new_revision, reason, metadata
    ) values (
      'f1990000-0000-4000-8000-000000000001', board_a, context_b, quote_b,
      null, 'BOARD_CREATED', 'SYSTEM:requirements_sync',
      'f1980000-0000-4000-8000-000000000002', null, 1, null, '{}'
    );
  exception when foreign_key_violation then rejected := true;
  end;
  result := result || jsonb_build_object('event_board', rejected);

  rejected := false;
  begin
    perform set_config('lws.website_requirement_history_command', 'on', true);
    insert into public.website_requirement_events(
      requirements_board_id, website_work_context_id, quote_request_id,
      requirement_id, event_type, actor_id, command_id, prior_revision,
      new_revision, reason, metadata
    ) values (
      board_b, context_b, quote_b, requirement_a, 'REQUIREMENT_CREATED',
      'SYSTEM:requirements_sync', 'f1980000-0000-4000-8000-000000000003',
      null, 1, null, '{}'
    );
  exception when foreign_key_violation then rejected := true;
  end;
  result := result || jsonb_build_object('requirement_board', rejected);

  rejected := false;
  begin
    perform set_config('lws.website_requirement_history_command', 'on', true);
    insert into public.website_requirement_verifications(
      verification_id, requirement_id, requirements_board_id,
      website_work_context_id, quote_request_id, website_workspace_id,
      binding_revision, canonical_commit_sha, requirement_revision,
      rule_key, rule_version, result, evidence_reference,
      evidence_sha256, verified_by
    ) values (
      'f19a0000-0000-4000-8000-000000000001', requirement_b, board_a,
      context_a, quote_a, 'f19b0000-0000-4000-8000-000000000001',
      1, repeat('a', 40), 1, 'website_route_present', 1, 'PASS', '{}',
      repeat('f', 64), 'SYSTEM:requirements_verifier'
    );
  exception when foreign_key_violation then rejected := true;
  end;
  result := result || jsonb_build_object('verification_requirement', rejected);

  perform set_config('lws.website_requirement_history_command', 'on', true);
  insert into public.website_requirement_sync_runs(
    sync_run_id, requirements_board_id, website_work_context_id, quote_request_id,
    intake_id, intake_revision, intake_snapshot_sha256, mapping_version,
    request_fingerprint, created_count, updated_count, retired_count,
    review_required_count, actor_id, command_id, result
  ) values (
    'f1960000-0000-4000-8000-000000000002', board_a, context_a, quote_a,
    'f1970000-0000-4000-8000-000000000002', 1, repeat('1', 64), 1,
    repeat('2', 64), 2, 0, 0, 0, 'SYSTEM:requirements_sync',
    'f1980000-0000-4000-8000-000000000004', '{}'
  );
  insert into public.website_requirement_events(
    event_id, requirements_board_id, website_work_context_id, quote_request_id,
    requirement_id, event_type, actor_id, command_id, prior_revision,
    new_revision, reason, metadata
  ) values (
    'f1990000-0000-4000-8000-000000000002', board_a, context_a, quote_a,
    requirement_a, 'REQUIREMENT_CREATED', 'SYSTEM:requirements_sync',
    'f1980000-0000-4000-8000-000000000005', null, 1, null, '{}'
  );
  insert into public.website_requirement_verifications(
    verification_id, requirement_id, requirements_board_id,
    website_work_context_id, quote_request_id, website_workspace_id,
    binding_revision, canonical_commit_sha, requirement_revision,
    rule_key, rule_version, result, evidence_reference,
    evidence_sha256, verified_by
  ) values (
    'f19a0000-0000-4000-8000-000000000002', requirement_a, board_a,
    context_a, quote_a, 'f19b0000-0000-4000-8000-000000000002',
    1, repeat('b', 40), 1, 'website_route_present', 1, 'UNKNOWN', '{}',
    repeat('3', 64), 'SYSTEM:requirements_verifier'
  );
  perform set_config('lws.website_requirement_history_command', '', true);

  return result;
exception
  when undefined_table or undefined_column then
    return jsonb_build_object('missing_foundation', true);
end;
$$;

create temporary table website_requirements_foundation_result as
select pg_temp.website_requirements_foundation_fixture_v1() as result;

select is(
  (select result->>'pre_project' from website_requirements_foundation_result),
  'true',
  'PRE_PROJECT requirements work without project or commercial release'
);
select is(
  (select result->>'context_quote' from website_requirements_foundation_result),
  'true',
  'CONTEXT_A plus QUOTE_B is rejected by the database'
);
select is(
  (select result->>'board_context' from website_requirements_foundation_result),
  'true',
  'BOARD_A plus CONTEXT_B is rejected by the database'
);
select is(
  (select result->>'sync_board' from website_requirements_foundation_result),
  'true',
  'SYNC_A plus BOARD_B authority is rejected by the database'
);
select is(
  (select result->>'event_board' from website_requirements_foundation_result),
  'true',
  'EVENT_A plus BOARD_B authority is rejected by the database'
);
select is(
  (select result->>'requirement_board' from website_requirements_foundation_result),
  'true',
  'REQUIREMENT_A plus BOARD_B is rejected by the database'
);
select is(
  (select result->>'verification_requirement' from website_requirements_foundation_result),
  'true',
  'VERIFICATION_A plus REQUIREMENT_B is rejected by the database'
);

select throws_ok(
  $$update public.website_requirement_sync_runs set result = result$$,
  '55000', 'WEBSITE_REQUIREMENT_HISTORY_IMMUTABLE',
  'sync history cannot be updated'
);
select throws_ok(
  $$delete from public.website_requirement_events$$,
  '55000', 'WEBSITE_REQUIREMENT_HISTORY_IMMUTABLE',
  'event history cannot be deleted'
);
select throws_ok(
  $$update public.website_requirement_verifications set result = result$$,
  '55000', 'WEBSITE_REQUIREMENT_HISTORY_IMMUTABLE',
  'verification history cannot be updated'
);

select throws_ok(
  $$insert into public.website_requirements_boards(
      website_work_context_id, quote_request_id, sync_state,
      mapping_version, revision, created_by
    ) values (
      'f1900000-0000-4000-8000-000000000001',
      'f1910000-0000-4000-8000-000000000001',
      'CURRENT', 1, 1, 'f1940000-0000-4000-8000-000000000001'
    )$$,
  '55000', 'DIRECT_WEBSITE_REQUIREMENT_WRITE_FORBIDDEN',
  'direct board writes are denied outside an internal command'
);
select throws_ok(
  $$insert into public.website_requirement_events(
      requirements_board_id, website_work_context_id, quote_request_id,
      event_type, actor_id, command_id, new_revision
    ) values (
      'f1920000-0000-4000-8000-000000000001',
      'f1900000-0000-4000-8000-000000000001',
      'f1910000-0000-4000-8000-000000000001',
      'DIRECT_WRITE', 'SYSTEM:requirements_sync',
      'f1980000-0000-4000-8000-000000000006', 1
    )$$,
  '55000', 'DIRECT_WEBSITE_REQUIREMENT_HISTORY_WRITE_FORBIDDEN',
  'direct history inserts are denied outside an internal command'
);

select ok(
  exists (select 1 from pg_constraint where conrelid = 'public.project_requirements_boards'::regclass and conname = 'project_requirements_boards_identity_unique')
  and exists (select 1 from pg_constraint where conrelid = 'public.project_requirements'::regclass and conname = 'project_requirements_board_fk')
  and exists (select 1 from pg_constraint where conrelid = 'public.project_requirement_verifications'::regclass and conname = 'project_requirement_verifications_requirement_fk'),
  'commercial Requirements authority constraints remain present and unchanged'
);

select * from finish();
rollback;
