begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select has_table('public', 'project_requirements_boards', 'requirements board root exists');
select has_table('public', 'project_requirements', 'requirements execution items exist');

select has_column('public', 'project_requirements_boards', 'requirements_board_id', 'board has requirements_board_id');
select has_column('public', 'project_requirements_boards', 'project_id', 'board has project_id');
select has_column('public', 'project_requirements_boards', 'quote_request_id', 'board has quote_request_id');
select has_column('public', 'project_requirements_boards', 'source_approval_id', 'board has source_approval_id');
select has_column('public', 'project_requirements_boards', 'source_payload_sha256', 'board has source_payload_sha256');
select has_column('public', 'project_requirements_boards', 'status', 'board has status');
select has_column('public', 'project_requirements_boards', 'revision', 'board has revision');
select has_column('public', 'project_requirements_boards', 'finalized_by', 'board has finalized_by');
select has_column('public', 'project_requirements_boards', 'finalized_at', 'board has finalized_at');
select has_column('public', 'project_requirements_boards', 'created_by', 'board has created_by');

select has_column('public', 'project_requirements', 'requirement_id', 'requirement has requirement_id');
select has_column('public', 'project_requirements', 'requirements_board_id', 'requirement has requirements_board_id');
select has_column('public', 'project_requirements', 'project_id', 'requirement has project_id');
select has_column('public', 'project_requirements', 'item_number', 'requirement has item_number');
select has_column('public', 'project_requirements', 'title', 'requirement has title');
select has_column('public', 'project_requirements', 'description', 'requirement has description');
select has_column('public', 'project_requirements', 'category', 'requirement has category');
select has_column('public', 'project_requirements', 'source_reference', 'requirement has source_reference');
select has_column('public', 'project_requirements', 'linked_page_or_module', 'requirement has linked_page_or_module');
select has_column('public', 'project_requirements', 'status', 'requirement has status');
select has_column('public', 'project_requirements', 'completion_mode', 'requirement has completion_mode');
select has_column('public', 'project_requirements', 'completion_rule_key', 'requirement has completion_rule_key');
select has_column('public', 'project_requirements', 'completion_rule_version', 'requirement has completion_rule_version');
select has_column('public', 'project_requirements', 'sort_order', 'requirement has sort_order');
select has_column('public', 'project_requirements', 'required', 'requirement has required');
select has_column('public', 'project_requirements', 'started_at', 'requirement has started_at');
select has_column('public', 'project_requirements', 'completed_at', 'requirement has completed_at');
select has_column('public', 'project_requirements', 'completed_by', 'requirement has completed_by');
select has_column('public', 'project_requirements', 'evidence_reference', 'requirement has evidence_reference');
select has_column('public', 'project_requirements', 'verification_result', 'requirement has verification_result');
select has_column('public', 'project_requirements', 'blocked_reason', 'requirement has blocked_reason');
select has_column('public', 'project_requirements', 'revision', 'requirement has revision');

select has_index('public', 'project_requirements_boards', 'project_requirements_boards_one_current_idx', 'board has one-current index');
select has_index('public', 'project_requirements', 'project_requirements_one_active_idx', 'requirements have one-active index');

select ok(
  coalesce((select relrowsecurity and relforcerowsecurity
    from pg_class where oid = to_regclass('public.project_requirements_boards')), false),
  'requirements boards force RLS'
);
select ok(
  coalesce((select relrowsecurity and relforcerowsecurity
    from pg_class where oid = to_regclass('public.project_requirements')), false),
  'requirements items force RLS'
);
select ok(
  not exists (
    select 1
    from information_schema.role_table_grants
    where grantee = 'authenticated'
      and table_schema = 'public'
      and table_name = 'project_requirements_boards'
      and privilege_type = 'SELECT'
  ),
  'authenticated callers cannot read boards directly'
);
select ok(
  not exists (
    select 1
    from information_schema.role_table_grants
    where grantee = 'authenticated'
      and table_schema = 'public'
      and table_name = 'project_requirements'
      and privilege_type = 'SELECT'
  ),
  'authenticated callers cannot read requirements directly'
);

select has_function('public', 'resolve_project_requirement_authorization_v1', array['uuid', 'uuid', 'text', 'boolean']);
select has_function('lws_internal', 'validate_project_requirement_source_v1', array['uuid', 'uuid', 'jsonb']);
select has_function('public', 'create_project_requirements_board_v1', array['uuid', 'uuid', 'uuid']);
select has_function('public', 'create_project_requirement_v1', array['uuid', 'uuid', 'uuid', 'bigint', 'jsonb', 'uuid']);
select has_function('public', 'finalize_project_requirements_board_v1', array['uuid', 'uuid', 'uuid', 'bigint', 'uuid']);
select has_function(
  'public', 'get_project_requirements_board_v1', array['uuid', 'uuid'],
  'requirements board read projection exists'
);
select has_function('public', 'start_project_requirement_v1', array['uuid', 'uuid', 'uuid', 'bigint', 'uuid']);
select has_function('public', 'block_project_requirement_v1', array['uuid', 'uuid', 'uuid', 'bigint', 'text', 'uuid']);
select has_function('public', 'complete_project_requirement_v1', array['uuid', 'uuid', 'uuid', 'bigint', 'jsonb', 'uuid']);
select has_function('public', 'reopen_project_requirement_v1', array['uuid', 'uuid', 'uuid', 'bigint', 'text', 'uuid']);
select has_function(
  'lws_internal', 'transition_project_requirement_core_v1',
  array['text', 'uuid', 'uuid', 'uuid', 'bigint', 'text', 'jsonb', 'uuid'],
  'one private requirement transition core exists'
);
select has_table('public', 'project_requirement_verifications', 'append-only requirement verification authority exists');
select has_function(
  'public', 'record_project_requirement_verification_v1',
  array['uuid', 'uuid', 'uuid', 'bigint', 'text', 'integer', 'text', 'jsonb', 'uuid'],
  'trusted requirement verification ingest exists'
);
select has_function(
  'lws_internal', 'evaluate_project_requirements_readiness_v1', array['uuid'],
  'shared server-side requirements readiness evaluator exists'
);
select has_function(
  'lws_internal', 'project_requirement_permitted_actions_v1',
  array['uuid', 'uuid', 'uuid', 'boolean'],
  'private server-authoritative requirement action projector exists'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'lws_internal.project_requirement_permitted_actions_v1(uuid,uuid,uuid,boolean)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'lws_internal.project_requirement_permitted_actions_v1(uuid,uuid,uuid,boolean)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'lws_internal.project_requirement_permitted_actions_v1(uuid,uuid,uuid,boolean)',
    'execute'
  ),
  'API roles cannot bypass the authorized board projection to invoke action logic'
);
select ok(
  case when to_regprocedure('public.get_project_requirements_board_v1(uuid,uuid)') is null then false
    else has_function_privilege(
      'authenticated', 'public.get_project_requirements_board_v1(uuid,uuid)', 'execute'
    )
      and not has_function_privilege(
        'anon', 'public.get_project_requirements_board_v1(uuid,uuid)', 'execute'
      )
      and not has_function_privilege(
        'service_role', 'public.get_project_requirements_board_v1(uuid,uuid)', 'execute'
      )
  end,
  'only authenticated humans can enter the requirements read projection'
);
select ok(
  case when to_regprocedure('public.start_project_requirement_v1(uuid,uuid,uuid,bigint,uuid)') is null then false
    else has_function_privilege(
      'authenticated', 'public.start_project_requirement_v1(uuid,uuid,uuid,bigint,uuid)', 'execute'
    )
      and has_function_privilege(
        'authenticated', 'public.block_project_requirement_v1(uuid,uuid,uuid,bigint,text,uuid)', 'execute'
      )
      and has_function_privilege(
        'authenticated', 'public.complete_project_requirement_v1(uuid,uuid,uuid,bigint,jsonb,uuid)', 'execute'
      )
      and has_function_privilege(
        'authenticated', 'public.reopen_project_requirement_v1(uuid,uuid,uuid,bigint,text,uuid)', 'execute'
      )
      and not has_function_privilege(
        'authenticated', 'lws_internal.transition_project_requirement_core_v1(text,uuid,uuid,uuid,bigint,text,jsonb,uuid)', 'execute'
      )
  end,
  'authenticated humans enter only the four narrow lifecycle wrappers'
);

select matches(
  coalesce(pg_get_functiondef(to_regprocedure('public.create_project_requirements_board_v1(uuid,uuid,uuid)')), ''),
  $$'CREATE_BOARD', false$$,
  'assigned operators may prepare a requirements board draft'
);
select matches(
  coalesce(pg_get_functiondef(to_regprocedure('public.create_project_requirement_v1(uuid,uuid,uuid,bigint,jsonb,uuid)')), ''),
  $$'CREATE_ITEM', false$$,
  'assigned operators may prepare requirement draft items'
);
select matches(
  coalesce(pg_get_functiondef(to_regprocedure('public.finalize_project_requirements_board_v1(uuid,uuid,uuid,bigint,uuid)')), ''),
  $$'FINALIZE_BOARD', true$$,
  'requirements board finalization remains management-only'
);

select matches(
  coalesce(pg_get_functiondef(to_regprocedure('public.resolve_project_requirement_authorization_v1(uuid,uuid,text,boolean)')), ''),
  'operator_dossier_assignments',
  'authorization composes dossier assignment authority'
);
select matches(
  coalesce(pg_get_functiondef(to_regprocedure('public.resolve_project_requirement_authorization_v1(uuid,uuid,text,boolean)')), ''),
  'commercial_operator_project_grants',
  'authorization composes project grant authority'
);
select matches(
  coalesce(pg_get_functiondef(to_regprocedure('lws_internal.validate_project_requirement_source_v1(uuid,uuid,jsonb)')), ''),
  'quote_request_quotation_approvals',
  'source validation resolves accepted quotation approval'
);
select matches(
  coalesce(pg_get_functiondef(to_regprocedure('public.create_project_requirement_v1(uuid,uuid,uuid,bigint,jsonb,uuid)')), ''),
  'idempotency_ledger',
  'requirement creation uses the existing idempotency ledger'
);
select matches(
  coalesce(pg_get_functiondef(to_regprocedure('public.create_project_requirement_v1(uuid,uuid,uuid,bigint,jsonb,uuid)')), ''),
  'audit_events',
  'requirement creation uses the existing audit authority'
);

select ok(
  has_function_privilege('authenticated', 'public.create_project_requirements_board_v1(uuid,uuid,uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.create_project_requirement_v1(uuid,uuid,uuid,bigint,jsonb,uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.finalize_project_requirements_board_v1(uuid,uuid,uuid,bigint,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.create_project_requirements_board_v1(uuid,uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.create_project_requirements_board_v1(uuid,uuid,uuid)', 'execute'),
  'only authenticated humans can enter the Task 1 command RPCs'
);
select has_trigger(
  'public', 'project_requirements_boards', 'trg_project_requirements_boards_command_guard',
  'board writes are command-guarded'
);
select has_trigger(
  'public', 'project_requirements', 'trg_project_requirements_command_guard',
  'requirement writes are command-guarded'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.project_requirements'::regclass
      and contype = 'f'
      and confrelid = 'public.project_requirements_boards'::regclass
      and array_length(conkey, 1) = 2
  ),
  'requirements use the composite board and project foreign key'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.project_requirements'::regclass
      and contype = 'u'
      and pg_get_constraintdef(oid) like 'UNIQUE (requirements_board_id, item_number)%'
  )
  and exists (
    select 1 from pg_constraint
    where conrelid = 'public.project_requirements'::regclass
      and contype = 'u'
      and pg_get_constraintdef(oid) like 'UNIQUE (requirements_board_id, sort_order)%'
  ),
  'requirement item number and sort order are unique within a board'
);

create function pg_temp.set_requirement_claims_v1(p_subject uuid)
returns void
language sql
as $$
  select set_config(
    'request.jwt.claims',
    case when p_subject is null then '{}'::jsonb
      else jsonb_build_object('sub', p_subject, 'role', 'authenticated', 'aal', 'aal1') end::text,
    true
  )::text;
$$;

create function pg_temp.get_requirement_projection_v1(
  p_quote_request_id uuid,
  p_project_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  execute 'select public.get_project_requirements_board_v1($1, $2)'
  into v_result
  using p_quote_request_id, p_project_id;
  return v_result;
exception
  when undefined_function then
    return '{"missing_projection":true}'::jsonb;
end;
$$;

create function pg_temp.get_requirement_permitted_actions_v1(
  p_subject uuid,
  p_quote_request_id uuid,
  p_project_id uuid,
  p_item_number integer
)
returns jsonb
language plpgsql
as $$
declare
  v_projection jsonb;
  v_actions jsonb;
  v_previous_claims text := current_setting('request.jwt.claims', true);
begin
  perform pg_temp.set_requirement_claims_v1(p_subject);
  v_projection := public.get_project_requirements_board_v1(
    p_quote_request_id, p_project_id
  );
  select item->'permitted_actions' into v_actions
  from jsonb_array_elements(v_projection->'items') as item
  where (item->>'item_number')::integer = p_item_number;
  perform set_config('request.jwt.claims', coalesce(v_previous_claims, '{}'), true);
  return coalesce(v_actions, '[]'::jsonb);
exception when insufficient_privilege then
  perform set_config('request.jwt.claims', coalesce(v_previous_claims, '{}'), true);
  return '[]'::jsonb;
end;
$$;

create function pg_temp.requirement_start_replayed_v1()
returns boolean
language plpgsql
as $$
declare
  v_replayed boolean;
begin
  execute $command$
    select (public.start_project_requirement_v1(
      'e8100000-0000-4000-8000-000000000001',
      'e8180000-0000-4000-8000-000000000001',
      (select requirement_id from public.project_requirements
        where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 2),
      5, 'e8300000-0000-4000-8000-000000000004'
    )->>'replayed')::boolean
  $command$ into v_replayed;
  return v_replayed;
exception
  when undefined_function then
    return false;
end;
$$;

create function pg_temp.get_requirement_readiness_v1(p_project_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  execute 'select lws_internal.evaluate_project_requirements_readiness_v1($1)'
  into v_result
  using p_project_id;
  return v_result;
exception
  when undefined_function then
    return '{"missing_evaluator":true}'::jsonb;
end;
$$;

create function pg_temp.preview_ready_attempt_v1(p_idempotency_key uuid)
returns text
language plpgsql
as $$
declare
  v_message text;
begin
  begin
    perform public.execute_commercial_command_v2(
      'e8180000-0000-4000-8000-000000000001',
      'record_preview_ready', 'PROJECT_RELEASED', 2, p_idempotency_key,
      jsonb_build_object(
        'content_reference', 'requirements-preview-' || p_idempotency_key::text,
        'content_sha256', repeat('c', 64)
      )
    );
    raise exception using errcode = 'P0001', message = 'COMMAND_SUCCEEDED';
  exception when others then
    get stacked diagnostics v_message = message_text;
    return v_message;
  end;
end;
$$;

insert into auth.users(id, email) values
  ('e8000000-0000-4000-8000-000000000001', 'requirements-owner@example.test'),
  ('e8000000-0000-4000-8000-000000000002', 'requirements-manager@example.test'),
  ('e8000000-0000-4000-8000-000000000003', 'requirements-assigned@example.test'),
  ('e8000000-0000-4000-8000-000000000004', 'requirements-unassigned@example.test'),
  ('e8000000-0000-4000-8000-000000000005', 'requirements-reviewer@example.test');
set local session_replication_role = replica;
insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status
) values
  ('e8010000-0000-4000-8000-000000000001', 'e8000000-0000-4000-8000-000000000001', 'Requirements Owner', 'owner', 'ACTIVE'),
  ('e8010000-0000-4000-8000-000000000002', 'e8000000-0000-4000-8000-000000000002', 'Requirements Manager', 'operations_manager', 'ACTIVE'),
  ('e8010000-0000-4000-8000-000000000003', 'e8000000-0000-4000-8000-000000000003', 'Requirements Assigned', 'operator', 'ACTIVE'),
  ('e8010000-0000-4000-8000-000000000004', 'e8000000-0000-4000-8000-000000000004', 'Requirements Unassigned', 'operator', 'ACTIVE'),
  ('e8010000-0000-4000-8000-000000000005', 'e8000000-0000-4000-8000-000000000005', 'Requirements Reviewer', 'reviewer', 'ACTIVE');
set local session_replication_role = origin;

create function pg_temp.create_requirement_project_fixture_v1()
returns table(quote_request_id uuid, project_id uuid, approval_id uuid, approval_sha256 text)
language plpgsql
as $$
declare
  v_quote_request_id uuid := 'e8100000-0000-4000-8000-000000000001';
  v_intake_id uuid := 'e8110000-0000-4000-8000-000000000001';
  v_snapshot_id uuid := 'e8120000-0000-4000-8000-000000000001';
  v_draft_id uuid := 'e8130000-0000-4000-8000-000000000001';
  v_approval_id uuid := 'e8140000-0000-4000-8000-000000000001';
  v_issuance_id uuid := 'e8150000-0000-4000-8000-000000000001';
  v_acceptance_id uuid := 'e8160000-0000-4000-8000-000000000001';
  v_customer_id uuid := 'e8170000-0000-4000-8000-000000000001';
  v_project_id uuid := 'e8180000-0000-4000-8000-000000000001';
  v_approval_payload jsonb;
  v_acceptance_payload jsonb;
begin
  insert into public.quote_requests(
    id, request_kind, created_at, name, email, website_type, budget, timing,
    description, privacy_consent, status
  ) values (
    v_quote_request_id, 'website', '2099-01-01T00:00:00Z', 'Requirements fixture',
    'requirements-fixture@example.test', 'business', 'Budget', 'Timing',
    'Requirements Board authority fixture.', true, 'approved'
  );
  insert into public.quote_request_intakes(
    id, quote_request_id, status, access_token_hash, access_token_expires_at,
    started_at, submitted_at, confirmation
  ) values (
    v_intake_id, v_quote_request_id, 'submitted', repeat('1', 64),
    '2099-01-03T00:00:00Z', '2099-01-01T01:00:00Z', '2099-01-01T02:00:00Z', true
  );
  insert into public.quote_request_pricing_snapshots(
    id, intake_id, snapshot_contract_version, config_version, config_hash,
    normalized_evidence, calculation, package_advice, budget_evaluation
  ) values (
    v_snapshot_id, v_intake_id, 2, '1.0.0', repeat('1', 64),
    '{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}',
    '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":10000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":10000,"quantity":1,"knownMinimumContributionMinor":10000}]}',
    '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}',
    '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}'
  );
  insert into public.quote_request_pricing_snapshot_integrity(snapshot_id, algorithm_version, key_id, mac)
  values (v_snapshot_id, 'hmac-sha256-v1', 'v1', repeat('a', 64));

  v_approval_payload := jsonb_build_object(
    'contract_version', 1, 'source_quote_request_id', v_quote_request_id::text,
    'source_intake_id', v_intake_id::text,
    'pricing_snapshot', jsonb_build_object('snapshot_id',v_snapshot_id::text,'snapshot_contract_version',2,'integrity_algorithm_version','hmac-sha256-v1','integrity_key_id','v1','integrity_mac',repeat('a',64)),
    'currency', 'EUR',
    'line_items', jsonb_build_array(jsonb_build_object('line_id','website','sequence',1,'product_or_service_code','WEBSITE','description','Websiteontwikkeling','quantity',1,'unit','project','unit_price_minor',10000,'discount_minor',0,'vat_treatment','STANDARD','vat_rate',21,'line_net_amount_minor',10000,'cost_type','ONE_TIME')),
    'totals', jsonb_build_object('one_time_subtotal_minor',10000,'recurring_subtotal_minor',0,'discount_total_minor',0,'vat_base_minor',10000,'vat_amount_minor',2100,'total_gross_minor',12100),
    'discount', jsonb_build_object('discount_type',null,'discount_value_minor',0,'discount_reason',null,'approved_by',null,'approved_at',null),
    'customer_identity', jsonb_build_object('source_quote_request_id',v_quote_request_id::text,'source_intake_id',v_intake_id::text,'customer_id',null,'legal_name','Requirements Fixture','contact_name','Requirements Fixture','email','requirements-fixture@example.test','address_line_1','Teststraat 1','address_line_2',null,'postal_code','9000','city','Gent','country_code','BE','enterprise_number',null,'vat_number',null,'source_fields',jsonb_build_object('legal_name','fixture'),'snapshot_sha256',repeat('b',64)),
    'project_scope', jsonb_build_object('project_id',null,'project_title','Requirements fixture','project_type','website','scope_summary','Accepted requirements scope','requested_languages',jsonb_build_array('nl'),'included_page_count',1,'features',jsonb_build_array('contact_form'),'copywriting',null,'seo',null,'hosting',null,'maintenance',null,'exclusions','[]'::jsonb,'assumptions','[]'::jsonb,'indicative_timing',null,'source_intake_id',v_intake_id::text,'source_pricing_snapshot_id',v_snapshot_id::text,'snapshot_sha256',repeat('c',64)),
    'vat_approval', jsonb_build_object('vat_treatment','STANDARD','vat_rate',21,'vat_decision_source','accountant','vat_approved_by','accountant:test','vat_approved_at','2026-08-15T12:00:00Z'),
    'payment_schedule', jsonb_build_object('schedule_id','schedule-1','milestones',jsonb_build_array(jsonb_build_object('sequence',1,'label','Volledige betaling','percentage',100,'amount_minor',null,'trigger','invoice','due_terms_days',30,'recurring_cycle',null)),'approved_by','commercial:test','approved_at','2026-08-15T12:00:00Z'),
    'validity', jsonb_build_object('valid_from','2026-08-15','valid_until','2026-09-14','validity_days',30,'approved_by','commercial:test','approved_at','2026-08-15T12:00:00Z'),
    'legal_references', jsonb_build_object('terms_reference','terms-v1','terms_version','1.0.0','terms_sha256',repeat('d',64),'terms_status','APPROVED','agreement_template_reference',null,'agreement_template_version',null,'agreement_template_sha256',null)
  );
  insert into public.quote_request_quotation_approval_drafts(
    id, quote_request_id, intake_id, pricing_snapshot_id, contract_version,
    approval_payload, payload_fingerprint, idempotency_key, created_by
  ) values (
    v_draft_id, v_quote_request_id, v_intake_id, v_snapshot_id, 1,
    v_approval_payload, public.quotation_approval_payload_sha256_v1(v_approval_payload),
    'e8130000-0000-4000-8000-000000000002', 'test:requirements'
  );
  insert into public.quote_request_quotation_approvals(
    id, draft_id, quote_request_id, intake_id, pricing_snapshot_id, contract_version,
    approval_version, approved_payload, payload_sha256, approved_by, approved_at
  ) values (
    v_approval_id, v_draft_id, v_quote_request_id, v_intake_id, v_snapshot_id, 1,
    1, v_approval_payload, public.quotation_approval_payload_sha256_v1(v_approval_payload),
    'test:requirements', clock_timestamp()
  );
  insert into public.quote_request_quotation_approval_integrity(approval_id, algorithm_version, key_id, mac)
  values (v_approval_id, 'hmac-sha256-v1', 'v1', repeat('e', 64));
  insert into public.quote_request_quotation_issuances(
    id, quotation_number, quotation_version, status, approval_id, issued_at, issued_by,
    template_id, template_version, template_sha256, generation_contract_version,
    issuance_input_sha256, generation_payload_sha256, docx_sha256, docx_bytes,
    prepare_idempotency_key, prepare_fingerprint, commit_idempotency_key, commit_fingerprint
  ) values (
    v_issuance_id, 'LWS-OFF-2099-8201', 1, 'ISSUED', v_approval_id, clock_timestamp(),
    'test:requirements', 'LWS_QUOTATION_NL_BE', '1.0.0-technical', repeat('3',64), 1,
    repeat('4',64), repeat('5',64), repeat('6',64), 12345,
    'e8150000-0000-4000-8000-000000000002', repeat('7',64),
    'e8150000-0000-4000-8000-000000000003', repeat('8',64)
  );
  v_acceptance_payload := jsonb_build_object(
    'acceptance_contract_version',1,'issuance_id',v_issuance_id::text,
    'quotation_number','LWS-OFF-2099-8201','quotation_version',1,
    'customer_identity_sha256',repeat('b',64),'generation_payload_sha256',repeat('5',64),
    'template',jsonb_build_object('template_id','LWS_QUOTATION_NL_BE','template_version','1.0.0-technical','template_sha256',repeat('3',64)),
    'docx',jsonb_build_object('sha256',repeat('6',64),'bytes',12345),
    'acceptance_terms',jsonb_build_object('terms_id','LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','terms_version','1.0.0-technical','terms_sha256',repeat('9',64)),
    'actor',jsonb_build_object('name','Requirements Acceptant','email','requirements-fixture@example.test','organization','Requirements Fixture','role','Bestuurder'),
    'authority_declaration',true,'accepted_at','2026-08-20T12:00:00.000000Z'
  );
  insert into public.quote_request_quotation_acceptances(
    id, issuance_id, quotation_number, quotation_version, customer_identity_sha256,
    customer_legal_name, generation_payload_sha256, template_id, template_version,
    template_sha256, docx_sha256, docx_bytes, acceptance_contract_version,
    acceptance_terms_id, acceptance_terms_version, acceptance_terms_sha256,
    accepting_name, accepting_email, accepting_organization, accepting_role,
    authority_declaration, acceptance_payload, acceptance_payload_sha256,
    semantic_request_fingerprint, accepted_at, created_at
  ) values (
    v_acceptance_id, v_issuance_id, 'LWS-OFF-2099-8201', 1, repeat('b',64),
    'Requirements Fixture', repeat('5',64), 'LWS_QUOTATION_NL_BE', '1.0.0-technical',
    repeat('3',64), repeat('6',64), 12345, 1,
    'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT', '1.0.0-technical', repeat('9',64),
    'Requirements Acceptant', 'requirements-fixture@example.test', 'Requirements Fixture',
    'Bestuurder', true, v_acceptance_payload,
    public.quotation_acceptance_payload_sha256_v1(v_acceptance_payload), repeat('f',64),
    '2026-08-20T12:00:00Z', '2026-08-20T12:00:00Z'
  );
  insert into public.commercial_customers(customer_id, acceptance_id, identity_sha256)
  values (v_customer_id, v_acceptance_id, repeat('a',64));
  insert into public.commercial_projects(
    project_id, customer_id, quotation_issuance_id, acceptance_id,
    accepted_total_minor, currency, m1_minor, m2_minor, m3_minor, current_state, revision
  ) values (
    v_project_id, v_customer_id, v_issuance_id, v_acceptance_id,
    10000, 'EUR', 4000, 4000, 2000, 'QUOTE_ACCEPTED', 1
  );
  return query select v_quote_request_id, v_project_id, v_approval_id,
    public.quotation_approval_payload_sha256_v1(v_approval_payload);
end;
$$;

create temporary table requirement_project_fixture as
select * from pg_temp.create_requirement_project_fixture_v1();

insert into public.website_execution_workspaces(
  website_workspace_id, project_id, quote_request_id,
  repository_owner, repository_name, last_commit_sha, last_commit_at,
  last_build_result, last_build_at, created_by
) values (
  'e8190000-0000-4000-8000-000000000001',
  'e8180000-0000-4000-8000-000000000001',
  'e8100000-0000-4000-8000-000000000001',
  'lorenzo-test', 'requirements-fixture', repeat('a', 40), clock_timestamp(),
  'PASS', clock_timestamp(), 'e8010000-0000-4000-8000-000000000001'
);
insert into public.audit_events(project_id, event_type, actor, command_id, metadata)
values (
  'e8180000-0000-4000-8000-000000000001', 'PROJECT_WORK_STARTED',
  'OPERATOR:e8010000-0000-4000-8000-000000000001',
  'e81a0000-0000-4000-8000-000000000001',
  '{"quote_request_id":"e8100000-0000-4000-8000-000000000001"}'::jsonb
);

select set_config('lws.operator_dossier_assignment_command', 'on', true);
update lws_internal.operator_dossier_assignments as assignment
set assignee_operator_id = 'e8010000-0000-4000-8000-000000000003',
    revision = assignment.revision + 1,
    assigned_at = command_time.occurred_at,
    updated_at = command_time.occurred_at
from requirement_project_fixture as fixture
cross join lateral (select clock_timestamp() as occurred_at) as command_time
where assignment.quote_request_id = fixture.quote_request_id;
select set_config('lws.operator_dossier_assignment_command', '', true);
insert into public.commercial_operator_project_grants(
  operator_id, project_id, access_level, granted_by
) select
  'e8010000-0000-4000-8000-000000000003', project_id, 'operator',
  'e8010000-0000-4000-8000-000000000001'
from requirement_project_fixture;

select pg_temp.set_requirement_claims_v1(null);
select throws_ok(
  $$select public.resolve_project_requirement_authorization_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 'READ_BOARD', false
  )$$,
  '42501', 'HUMAN_JWT_REQUIRED',
  'requirements authority rejects a request without a human subject'
);
select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000002');
select lives_ok(
  $$select public.resolve_project_requirement_authorization_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 'FINALIZE_BOARD', true
  )$$,
  'active operations management has requirements management authority without a project grant'
);
select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000003');
select is(
  pg_temp.get_requirement_projection_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001'
  )->>'empty_state',
  'NO_BOARD',
  'authorized project without a board returns the explicit empty state'
);
select is(
  pg_temp.get_requirement_projection_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001'
  )->'readiness',
  '{"required_total":0,"required_completed":0,"required_open":0,"required_blocked":0,"active_requirement_id":null,"active_item_number":null,"ready_for_preview":false,"readiness":"UNKNOWN","reason":"REQUIREMENTS_BOARD_MISSING"}'::jsonb,
  'missing board readiness fails closed without fake completion'
);
select lives_ok(
  $$select public.resolve_project_requirement_authorization_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 'CREATE_ITEM', false
  )$$,
  'assigned operator with active operator grant may prepare requirement drafts'
);
select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000004');
select throws_ok(
  $$select public.resolve_project_requirement_authorization_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 'READ_BOARD', false
  )$$,
  '42501', 'PROJECT_REQUIREMENT_ASSIGNMENT_DENIED',
  'unassigned operator receives no requirements metadata'
);
select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000005');
select throws_ok(
  $$select public.resolve_project_requirement_authorization_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 'READ_BOARD', false
  )$$,
  '42501', 'PROJECT_REQUIREMENT_ROLE_DENIED',
  'reviewer receives no v1 requirements access'
);
select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000001');
select throws_ok(
  $$select public.resolve_project_requirement_authorization_v1(
    'e8100000-0000-4000-8000-000000000099',
    'e8180000-0000-4000-8000-000000000001', 'READ_BOARD', false
  )$$,
  '42501', 'PROJECT_REQUIREMENT_BINDING_DENIED',
  'management cannot combine a project with the wrong quote request'
);

select ok(
  lws_internal.validate_project_requirement_source_v1(
    'e8180000-0000-4000-8000-000000000001',
    'e8100000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'authority_type','ACCEPTED_PROJECT_SCOPE',
      'authority_id','e8140000-0000-4000-8000-000000000001',
      'json_path','project_scope.scope_summary',
      'source_sha256',(select approval_sha256 from requirement_project_fixture)
    )
  ),
  'source validator resolves a real node in the exact accepted project scope'
);
select ok(
  not lws_internal.validate_project_requirement_source_v1(
    'e8180000-0000-4000-8000-000000000001',
    'e8100000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'authority_type','ACCEPTED_PROJECT_SCOPE',
      'authority_id','e8140000-0000-4000-8000-000000000001',
      'json_path','project_scope.nonexistent',
      'source_sha256',(select approval_sha256 from requirement_project_fixture)
    )
  ),
  'source validator rejects a nonexistent accepted payload path'
);
select ok(
  not lws_internal.validate_project_requirement_source_v1(
    'e8180000-0000-4000-8000-000000000001',
    'e8100000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'authority_type','ACCEPTED_PROJECT_SCOPE',
      'authority_id','e8140000-0000-4000-8000-000000000001',
      'json_path','customer_identity.email',
      'source_sha256',(select approval_sha256 from requirement_project_fixture)
    )
  ),
  'source validator rejects arbitrary accepted payload branches'
);

select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000003');
select lives_ok(
  $$select public.create_project_requirements_board_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    'e8200000-0000-4000-8000-000000000001'
  )$$,
  'assigned operator can create the project requirements draft'
);
select is(
  public.create_project_requirements_board_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    'e8200000-0000-4000-8000-000000000001'
  )->>'replayed',
  'true',
  'same requirements board command replays its original idempotent result'
);
select throws_ok(
  $$select public.create_project_requirements_board_v1(
    'e8100000-0000-4000-8000-000000000099',
    'e8180000-0000-4000-8000-000000000001',
    'e8200000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'PROJECT_REQUIREMENT_BINDING_DENIED',
  'changed board command cannot reuse authority from an idempotent request'
);
select throws_ok(
  $$update public.project_requirements_boards set revision = revision + 1
    where project_id = 'e8180000-0000-4000-8000-000000000001'$$,
  '55000', 'DIRECT_REQUIREMENT_WRITE_FORBIDDEN',
  'direct requirements board mutation is denied'
);
select is(
  pg_temp.get_requirement_projection_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001'
  )->'actions',
  '{"can_create_board":false,"can_create_item":true,"can_finalize":false}'::jsonb,
  'assigned operator receives draft preparation but no finalization action'
);
select is(
  pg_temp.get_requirement_projection_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001'
  )->'board'->>'status',
  'DRAFT',
  'draft board state is projected explicitly'
);

select lives_ok(
  $$select public.create_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirements_board_id from public.project_requirements_boards
      where project_id = 'e8180000-0000-4000-8000-000000000001'),
    1,
    jsonb_build_object(
      'item_number',1,'title','Homepage','description','Bouw de geaccepteerde homepage.',
      'category','PAGE',
      'source_reference',jsonb_build_object(
        'authority_type','ACCEPTED_PROJECT_SCOPE',
        'authority_id','e8140000-0000-4000-8000-000000000001',
        'json_path','project_scope.scope_summary',
        'source_sha256',(select approval_sha256 from requirement_project_fixture)
      ),
      'linked_page_or_module','/', 'completion_mode','OPERATOR',
      'completion_rule_key',null,'completion_rule_version',null,
      'sort_order',1,'required',true
    ),
    'e8210000-0000-4000-8000-000000000001'
  )$$,
  'assigned operator can add an accepted-source requirement to the draft'
);
select is(
  public.create_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirements_board_id from public.project_requirements_boards
      where project_id = 'e8180000-0000-4000-8000-000000000001'),
    1,
    jsonb_build_object(
      'item_number',1,'title','Homepage','description','Bouw de geaccepteerde homepage.',
      'category','PAGE',
      'source_reference',jsonb_build_object(
        'authority_type','ACCEPTED_PROJECT_SCOPE',
        'authority_id','e8140000-0000-4000-8000-000000000001',
        'json_path','project_scope.scope_summary',
        'source_sha256',(select approval_sha256 from requirement_project_fixture)
      ),
      'linked_page_or_module','/', 'completion_mode','OPERATOR',
      'completion_rule_key',null,'completion_rule_version',null,
      'sort_order',1,'required',true
    ),
    'e8210000-0000-4000-8000-000000000001'
  )->>'replayed',
  'true',
  'same requirement create command replays the original result'
);
select throws_ok(
  $$select public.create_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirements_board_id from public.project_requirements_boards
      where project_id = 'e8180000-0000-4000-8000-000000000001'),
    1,
    jsonb_build_object(
      'item_number',1,'title','Changed title','description','Bouw de geaccepteerde homepage.',
      'category','PAGE',
      'source_reference',jsonb_build_object(
        'authority_type','ACCEPTED_PROJECT_SCOPE',
        'authority_id','e8140000-0000-4000-8000-000000000001',
        'json_path','project_scope.scope_summary',
        'source_sha256',(select approval_sha256 from requirement_project_fixture)
      ),
      'linked_page_or_module','/', 'completion_mode','OPERATOR',
      'completion_rule_key',null,'completion_rule_version',null,
      'sort_order',1,'required',true
    ),
    'e8210000-0000-4000-8000-000000000001'
  )$$,
  'P0001', 'IDEMPOTENCY_CONFLICT',
  'changed requirement payload cannot reuse an idempotency key'
);
select is(
  (select count(*)::integer from public.audit_events
   where project_id = 'e8180000-0000-4000-8000-000000000001'
     and event_type = 'REQUIREMENT_CREATED'
     and actor = 'OPERATOR:e8010000-0000-4000-8000-000000000003'),
  1,
  'requirement creation appends one minimized canonical-actor audit event'
);
select ok(
  not exists (
    select 1 from public.audit_events
    where project_id = 'e8180000-0000-4000-8000-000000000001'
      and metadata ?| array[
        'token', 'token_digest', 'session', 'credential', 'raw_bank',
        'internal_note', 'customer_content', 'service_role_key'
      ]
  ),
  'requirements audit metadata contains no forbidden sensitive keys'
);
do $$
declare
  v_item_number integer;
begin
  for v_item_number in 2..12 loop
    perform public.create_project_requirement_v1(
      'e8100000-0000-4000-8000-000000000001',
      'e8180000-0000-4000-8000-000000000001',
      (select requirements_board_id from public.project_requirements_boards
        where project_id = 'e8180000-0000-4000-8000-000000000001'),
      v_item_number,
      jsonb_build_object(
        'item_number',v_item_number,
        'title','Requirement ' || lpad(v_item_number::text, 2, '0'),
        'description','Accepted execution requirement ' || v_item_number::text || '.',
        'category',case
          when v_item_number in (4, 6) then 'TECHNICAL'
          when v_item_number = 5 then 'FORM'
          when v_item_number % 2 = 0 then 'CONTENT'
          else 'TECHNICAL'
        end,
        'source_reference',jsonb_build_object(
          'authority_type','ACCEPTED_LINE_ITEM',
          'authority_id','e8140000-0000-4000-8000-000000000001',
          'json_path','line_items.0.description',
          'source_sha256',(select approval_sha256 from requirement_project_fixture)
        ),
        'linked_page_or_module',null,
        'completion_mode',case v_item_number
          when 4 then 'AUTO'
          when 5 then 'HYBRID'
          when 6 then 'EXTERNAL'
          else 'OPERATOR'
        end,
        'completion_rule_key',case
          when v_item_number in (4, 5) then 'website_test_run'
          when v_item_number = 6 then 'project_work_started'
          else null
        end,
        'completion_rule_version',case when v_item_number in (4, 5, 6) then 1 else null end,
        'sort_order',v_item_number,
        'required',v_item_number <= 10
      ),
      ('e8210000-0000-4000-8000-' || lpad(v_item_number::text, 12, '0'))::uuid
    );
  end loop;
end;
$$;
select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000003');
select throws_ok(
  $$select public.finalize_project_requirements_board_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirements_board_id from public.project_requirements_boards
      where project_id = 'e8180000-0000-4000-8000-000000000001'),
    13, 'e8220000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'PROJECT_REQUIREMENT_ROLE_DENIED',
  'assigned operator cannot finalize board coverage'
);
select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000002');
select lives_ok(
  $$select public.finalize_project_requirements_board_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirements_board_id from public.project_requirements_boards
      where project_id = 'e8180000-0000-4000-8000-000000000001'),
    13, 'e8220000-0000-4000-8000-000000000002'
  )$$,
  'operations management can finalize reviewed board coverage'
);
select is(
  (select count(*)::integer from public.audit_events
   where project_id = 'e8180000-0000-4000-8000-000000000001'
     and event_type = 'REQUIREMENTS_BOARD_FINALIZED'
     and actor = 'OPERATOR:e8010000-0000-4000-8000-000000000002'),
  1,
  'board finalization appends one minimized management audit event'
);
select is(
  (select array_agg(key order by key)
   from jsonb_object_keys(pg_temp.get_requirement_projection_v1(
     'e8100000-0000-4000-8000-000000000001',
     'e8180000-0000-4000-8000-000000000001'
   )) as key),
  array['actions','board','context','contract_version','empty_state','items','project_id','quote_request_id','readiness']::text[],
  'requirements projection exposes the exact bounded root shape'
);
select is(
  pg_temp.get_requirement_projection_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001'
  )->'context',
  jsonb_build_object(
    'customer','Requirements Fixture',
    'dossier_reference',null,
    'project_reference','e8180000-0000-4000-8000-000000000001',
    'assigned_operator',jsonb_build_object(
      'operator_id','e8010000-0000-4000-8000-000000000003',
      'display_name','Requirements Assigned'
    )
  ),
  'projection resolves customer, dossier, project and current assignment context server-side'
);
select is(
  jsonb_array_length(pg_temp.get_requirement_projection_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001'
  )->'items'),
  12,
  'finalized board projects all 12 reviewed requirements'
);
select is(
  (select string_agg(item->>'item_number', ',' order by ordinal)
   from jsonb_array_elements(pg_temp.get_requirement_projection_v1(
     'e8100000-0000-4000-8000-000000000001',
     'e8180000-0000-4000-8000-000000000001'
   )->'items') with ordinality as projected(item, ordinal)),
  '1,2,3,4,5,6,7,8,9,10,11,12',
  'requirements projection preserves stable server sort order'
);
select is(
  pg_temp.get_requirement_projection_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001'
  )->'readiness',
  '{"required_total":10,"required_completed":0,"required_open":10,"required_blocked":0,"active_requirement_id":null,"active_item_number":null,"ready_for_preview":false,"readiness":"BLOCKED","reason":"REQUIRED_REQUIREMENTS_OPEN"}'::jsonb,
  'shared readiness reports open required requirements as blocked'
);
select is(
  pg_temp.get_requirement_projection_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001'
  )->'actions',
  '{"can_create_board":false,"can_create_item":false,"can_finalize":false}'::jsonb,
  'finalized board exposes no draft mutation actions'
);
select is(
  pg_temp.get_requirement_permitted_actions_v1(
    null,
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 1
  ),
  '[]'::jsonb,
  'unauthenticated actor receives no permitted requirement actions'
);
select is(
  pg_temp.get_requirement_permitted_actions_v1(
    'e8000000-0000-4000-8000-000000000004',
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 1
  ),
  '[]'::jsonb,
  'operator without the assignment and project grant receives no permitted actions'
);
select is(
  pg_temp.get_requirement_permitted_actions_v1(
    'e8000000-0000-4000-8000-000000000005',
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 1
  ),
  '[]'::jsonb,
  'reviewer receives no permitted requirement actions'
);
select is(
  pg_temp.get_requirement_permitted_actions_v1(
    'e8000000-0000-4000-8000-000000000002',
    'e8100000-0000-4000-8000-000000000099',
    'e8180000-0000-4000-8000-000000000001', 1
  ),
  '[]'::jsonb,
  'wrong quote and project binding yields no permitted actions'
);
select is(
  pg_temp.get_requirement_permitted_actions_v1(
    'e8000000-0000-4000-8000-000000000003',
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 1
  ),
  '["start_project_requirement"]'::jsonb,
  'authorized assigned operator may start a PENDING requirement'
);
select is(
  pg_temp.get_requirement_permitted_actions_v1(
    'e8000000-0000-4000-8000-000000000002',
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 1
  ),
  '["start_project_requirement"]'::jsonb,
  'management receives the legal PENDING action without an assignment'
);
select ok(
  not exists (
    select 1
    from jsonb_array_elements(pg_temp.get_requirement_projection_v1(
      'e8100000-0000-4000-8000-000000000001',
      'e8180000-0000-4000-8000-000000000001'
    )->'items') as item
    cross join lateral jsonb_array_elements_text(item->'permitted_actions') as action(value)
    where action.value not in (
      'start_project_requirement', 'block_project_requirement',
      'complete_project_requirement', 'reopen_project_requirement'
    )
  ),
  'projection returns no unknown requirement action names'
);
select volatility_is(
  'public', 'get_project_requirements_board_v1', array['uuid', 'uuid'], 'stable',
  'requirements action projection remains read-only'
);
select ok(
  not (pg_temp.get_requirement_projection_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001'
  )::text ~ '(approved_payload|source_sha256|json_path|token|credential|service_role_key)'),
  'projection leaks no accepted payload, source hash/path or credential material'
);
select throws_ok(
  $$select public.get_project_requirements_board_v1(
    'e8100000-0000-4000-8000-000000000099',
    'e8180000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'PROJECT_REQUIREMENT_BINDING_DENIED',
  'read projection rejects mismatched project and quote identities'
);

select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000003');
select lives_ok(
  $$select public.start_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 1),
    1, 'e8300000-0000-4000-8000-000000000001'
  )$$,
  'assigned operator can transition PENDING to ACTIVE'
);
select is(
  (select jsonb_build_array(status, revision, started_at is not null)
   from public.project_requirements
   where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 1),
  '["ACTIVE",2,true]'::jsonb,
  'start transition sets ACTIVE, increments revision and records server start time'
);
select is(
  pg_temp.get_requirement_permitted_actions_v1(
    'e8000000-0000-4000-8000-000000000003',
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 1
  ),
  '["block_project_requirement","complete_project_requirement"]'::jsonb,
  'ACTIVE OPERATOR requirement permits block and operator completion'
);
select is(
  pg_temp.get_requirement_permitted_actions_v1(
    'e8000000-0000-4000-8000-000000000003',
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 4
  ),
  '[]'::jsonb,
  'PENDING requirement exposes no impossible start while another requirement is ACTIVE'
);
select throws_ok(
  $$select public.start_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 2),
    1, 'e8300000-0000-4000-8000-000000000002'
  )$$,
  'P0001', 'ACTIVE_REQUIREMENT_CONFLICT',
  'a second ACTIVE requirement is rejected explicitly'
);
select throws_ok(
  $$select public.block_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 2),
    1, '   ', 'e8310000-0000-4000-8000-000000000001'
  )$$,
  '22023', 'BLOCKED_REASON_REQUIRED',
  'blocking requires a bounded nonempty reason'
);
select lives_ok(
  $$select public.block_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 2),
    1, 'Wacht op klantinput.', 'e8310000-0000-4000-8000-000000000002'
  )$$,
  'assigned operator can transition PENDING to BLOCKED'
);
select lives_ok(
  $$select public.block_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 1),
    2, 'Technische afhankelijkheid.', 'e8310000-0000-4000-8000-000000000003'
  )$$,
  'assigned operator can transition ACTIVE to BLOCKED'
);
select is(
  pg_temp.get_requirement_permitted_actions_v1(
    'e8000000-0000-4000-8000-000000000003',
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 2
  ),
  '["start_project_requirement"]'::jsonb,
  'BLOCKED requirement resumes through the existing start command'
);
select lives_ok(
  $$select public.start_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 2),
    2, 'e8300000-0000-4000-8000-000000000003'
  )$$,
  'assigned operator can transition BLOCKED to ACTIVE'
);
select throws_ok(
  $$select public.block_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 2),
    2, 'Stale command.', 'e8310000-0000-4000-8000-000000000004'
  )$$,
  '40001', 'CONCURRENT_MODIFICATION',
  'lifecycle rejects stale requirement revision'
);
select throws_ok(
  $$select public.complete_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 3),
    1, '{"attestation":"Inhoudelijk gecontroleerd."}',
    'e8320000-0000-4000-8000-000000000001'
  )$$,
  '55000', 'INVALID_REQUIREMENT_TRANSITION',
  'OPERATOR requirement cannot skip directly from PENDING to COMPLETED'
);
select lives_ok(
  $$select public.complete_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 2),
    3, '{"attestation":"Inhoudelijk gecontroleerd en akkoord."}',
    'e8320000-0000-4000-8000-000000000002'
  )$$,
  'assigned operator can transition ACTIVE to COMPLETED with attestation'
);
select is(
  (select jsonb_build_array(status, revision, completed_at is not null, completed_by)
   from public.project_requirements
   where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 2),
  '["COMPLETED",4,true,"OPERATOR:e8010000-0000-4000-8000-000000000003"]'::jsonb,
  'completion records state, revision, server time and canonical actor'
);
select is(
  pg_temp.get_requirement_permitted_actions_v1(
    'e8000000-0000-4000-8000-000000000003',
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 2
  ),
  '[]'::jsonb,
  'assigned operator cannot reopen a COMPLETED requirement'
);
select is(
  pg_temp.get_requirement_permitted_actions_v1(
    'e8000000-0000-4000-8000-000000000002',
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 2
  ),
  '["reopen_project_requirement"]'::jsonb,
  'management may reopen a COMPLETED requirement'
);
select throws_ok(
  $$select public.reopen_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 2),
    4, 'Hercontrole nodig.', 'e8330000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'PROJECT_REQUIREMENT_ROLE_DENIED',
  'assigned operator cannot reopen a completed requirement'
);
select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000002');
select throws_ok(
  $$select public.reopen_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 2),
    4, '', 'e8330000-0000-4000-8000-000000000002'
  )$$,
  '22023', 'REOPEN_REASON_REQUIRED',
  'management reopen requires a bounded nonempty reason'
);
select lives_ok(
  $$select public.reopen_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 2),
    4, 'Hercontrole nodig.', 'e8330000-0000-4000-8000-000000000003'
  )$$,
  'operations management can transition COMPLETED to PENDING'
);
select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000003');
select lives_ok(
  $$select public.start_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 2),
    5, 'e8300000-0000-4000-8000-000000000004'
  )$$,
  'reopened requirement can return to ACTIVE'
);
select ok(
  pg_temp.requirement_start_replayed_v1(),
  'same lifecycle command replays the original result'
);
select throws_ok(
  $$select public.start_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 2),
    4, 'e8300000-0000-4000-8000-000000000004'
  )$$,
  'P0001', 'IDEMPOTENCY_CONFLICT',
  'changed lifecycle command cannot reuse an idempotency key'
);
select is(
  (select count(*)::integer from public.audit_events
   where project_id = 'e8180000-0000-4000-8000-000000000001'
     and event_type in (
       'REQUIREMENT_STARTED', 'REQUIREMENT_BLOCKED',
       'REQUIREMENT_COMPLETED', 'REQUIREMENT_REOPENED'
     )),
  7,
  'every successful lifecycle transition appends one existing audit event'
);
select set_config('lws.operator_dossier_assignment_command', 'on', true);
update lws_internal.operator_dossier_assignments
set assignee_operator_id = 'e8010000-0000-4000-8000-000000000004',
    revision = revision + 1,
    assigned_at = command_time.occurred_at,
    updated_at = command_time.occurred_at
from (select clock_timestamp() as occurred_at) as command_time
where quote_request_id = 'e8100000-0000-4000-8000-000000000001';
select set_config('lws.operator_dossier_assignment_command', '', true);
select is(
  (select jsonb_build_array(status, revision)
   from public.project_requirements
   where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 2),
  '["ACTIVE",6]'::jsonb,
  'requirement state and revision persist across dossier reassignment'
);

select ok(
  case when to_regclass('public.project_requirement_verifications') is null then false
    else (select relrowsecurity and relforcerowsecurity
      from pg_class where oid = to_regclass('public.project_requirement_verifications'))
      and not has_table_privilege('authenticated', 'public.project_requirement_verifications', 'select')
      and not has_table_privilege('service_role', 'public.project_requirement_verifications', 'insert')
  end,
  'verification storage is forced-RLS and writable only through trusted ingest'
);
select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000002');
select throws_ok(
  $$select public.record_project_requirement_verification_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 4),
    1, 'website_test_run', 1, 'PASS',
    jsonb_build_object(
      'evidence_type','TEST_RUN','website_workspace_id','e8190000-0000-4000-8000-000000000001',
      'binding_revision',1,'branch','develop','commit_sha',repeat('a',40),
      'suite_id','requirements-contract','contract_version',1,'observed_at',clock_timestamp()
    ), 'e8400000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'TRUSTED_VERIFIER_REQUIRED',
  'browser-authenticated actors cannot write trusted verification results'
);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select throws_ok(
  $$select public.record_project_requirement_verification_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 4),
    1, 'unknown_rule', 1, 'PASS', '{}'::jsonb,
    'e8400000-0000-4000-8000-000000000002'
  )$$,
  '22023', 'UNKNOWN_REQUIREMENT_RULE',
  'unknown verification rule can never produce completion'
);
select throws_ok(
  $$select public.record_project_requirement_verification_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 4),
    1, 'website_test_run', 2, 'PASS', '{}'::jsonb,
    'e8400000-0000-4000-8000-000000000003'
  )$$,
  '22023', 'UNKNOWN_REQUIREMENT_RULE',
  'unknown verification rule version can never produce completion'
);
select throws_ok(
  $$select public.record_project_requirement_verification_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 4),
    1, 'website_test_run', 1, 'PASS',
    '{"evidence_type":"FILE_EXISTS","path":"index.html"}'::jsonb,
    'e8400000-0000-4000-8000-000000000004'
  )$$,
  '22023', 'INVALID_VERIFICATION_EVIDENCE',
  'file, element and AI-style strings are not accepted evidence types'
);
select throws_ok(
  $$select public.record_project_requirement_verification_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 4),
    1, 'website_test_run', 1, 'PASS',
    jsonb_build_object(
      'evidence_type','TEST_RUN','website_workspace_id','e8190000-0000-4000-8000-000000000001',
      'binding_revision',1,'branch','develop','commit_sha',repeat('b',40),
      'suite_id','requirements-contract','contract_version',1,'observed_at',clock_timestamp()
    ), 'e8400000-0000-4000-8000-000000000005'
  )$$,
  '23514', 'VERIFICATION_WORKSPACE_MISMATCH',
  'verification for a different repository commit is rejected'
);
select throws_ok(
  $$select public.record_project_requirement_verification_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 4),
    1, 'website_test_run', 1, 'PASS',
    jsonb_build_object(
      'evidence_type','TEST_RUN','website_workspace_id','e8190000-0000-4000-8000-000000000001',
      'binding_revision',1,'branch','develop','commit_sha',repeat('a',40),
      'suite_id','requirements-contract','contract_version',1,
      'observed_at',clock_timestamp() - interval '25 hours'
    ), 'e8400000-0000-4000-8000-000000000006'
  )$$,
  '22023', 'VERIFICATION_STALE',
  'expired technical verification cannot produce completion'
);
select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000002');
select lives_ok(
  $$select public.block_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 2),
    6, 'Vrijgemaakt voor modeverificatie.', 'e8410000-0000-4000-8000-000000000001'
  )$$,
  'management can release the current ACTIVE slot for verification tests'
);
select lives_ok(
  $$select public.start_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 4),
    1, 'e8410000-0000-4000-8000-000000000002'
  )$$,
  'AUTO requirement can enter ACTIVE before trusted verification'
);
select ok(
  (select lws_internal.validate_project_requirement_source_v1(
    project_id,
    'e8100000-0000-4000-8000-000000000001',
    source_reference
  ) from public.project_requirements
  where project_id = 'e8180000-0000-4000-8000-000000000001'
    and item_number = 4),
  'ACTIVE AUTO requirement retains a valid accepted source'
);
select is(
  (select count(*)::integer from public.project_requirements
   where project_id = 'e8180000-0000-4000-8000-000000000001'
     and status = 'ACTIVE'),
  1,
  'completion-mode projection fixture has exactly one ACTIVE requirement'
);
select is(
  pg_temp.get_requirement_permitted_actions_v1(
    'e8000000-0000-4000-8000-000000000002',
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 4
  ),
  '["block_project_requirement"]'::jsonb,
  'ACTIVE AUTO requirement never exposes browser completion without trusted PASS'
);
select throws_ok(
  $$select public.complete_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 4),
    2, '{"attestation":"klaar"}'::jsonb,
    'e8410000-0000-4000-8000-000000000003'
  )$$,
  '55000', 'REQUIREMENT_VERIFICATION_REQUIRED',
  'operator or AI completion text cannot replace trusted AUTO evidence'
);
select set_config('lws.requirement_command', 'on', true);
update public.project_requirements
set status = 'ACTIVE', completed_at = null, completed_by = null,
    evidence_reference = null, revision = 2
where project_id = 'e8180000-0000-4000-8000-000000000001'
  and item_number = 4 and status = 'COMPLETED';
select set_config('lws.requirement_command', '', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select lives_ok(
  $$select public.record_project_requirement_verification_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 4),
    2, 'website_test_run', 1, 'PASS',
    jsonb_build_object(
      'evidence_type','TEST_RUN','website_workspace_id','e8190000-0000-4000-8000-000000000001',
      'binding_revision',1,'branch','develop','commit_sha',repeat('a',40),
      'suite_id','requirements-contract','contract_version',1,'observed_at',clock_timestamp()
    ), 'e8420000-0000-4000-8000-000000000001'
  )$$,
  'trusted current PASS automatically completes an AUTO requirement'
);
select is(
  (select jsonb_build_array(status, verification_result, completed_by)
   from public.project_requirements
   where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 4),
  '["COMPLETED","PASS","SYSTEM:requirements_verifier"]'::jsonb,
  'AUTO completion stores trusted system provenance, not a browser claim'
);
select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000002');
select lives_ok(
  $$select public.start_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 5),
    1, 'e8430000-0000-4000-8000-000000000001'
  )$$,
  'HYBRID requirement enters ACTIVE for operator work'
);
select is(
  pg_temp.get_requirement_permitted_actions_v1(
    'e8000000-0000-4000-8000-000000000002',
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 5
  ),
  '["block_project_requirement"]'::jsonb,
  'ACTIVE HYBRID requirement without current trusted PASS cannot be completed'
);
select throws_ok(
  $$select public.complete_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 5),
    2, '{"attestation":"Inhoudelijk akkoord."}'::jsonb,
    'e8430000-0000-4000-8000-000000000002'
  )$$,
  '55000', 'REQUIREMENT_VERIFICATION_REQUIRED',
  'HYBRID cannot complete before trusted technical PASS'
);
select set_config('lws.requirement_command', 'on', true);
update public.project_requirements
set status = 'ACTIVE', completed_at = null, completed_by = null,
    evidence_reference = null, revision = 2
where project_id = 'e8180000-0000-4000-8000-000000000001'
  and item_number = 5 and status = 'COMPLETED';
select set_config('lws.requirement_command', '', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select lives_ok(
  $$select public.record_project_requirement_verification_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 5),
    2, 'website_test_run', 1, 'PASS',
    jsonb_build_object(
      'evidence_type','TEST_RUN','website_workspace_id','e8190000-0000-4000-8000-000000000001',
      'binding_revision',1,'branch','develop','commit_sha',repeat('a',40),
      'suite_id','requirements-contract','contract_version',1,'observed_at',clock_timestamp()
    ), 'e8440000-0000-4000-8000-000000000001'
  )$$,
  'trusted PASS records HYBRID technical verification without auto-completion'
);
select is(
  (select jsonb_build_array(status, verification_result, revision)
   from public.project_requirements
   where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 5),
  '["ACTIVE","PASS",3]'::jsonb,
  'HYBRID remains ACTIVE after PASS and advances its revision'
);
select is(
  pg_temp.get_requirement_permitted_actions_v1(
    'e8000000-0000-4000-8000-000000000002',
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 5
  ),
  '["block_project_requirement","complete_project_requirement"]'::jsonb,
  'ACTIVE HYBRID requirement exposes completion only after current trusted PASS'
);
update public.website_execution_workspaces
set binding_revision = binding_revision + 1
where project_id = 'e8180000-0000-4000-8000-000000000001';
select is(
  pg_temp.get_requirement_permitted_actions_v1(
    'e8000000-0000-4000-8000-000000000002',
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 5
  ),
  '["block_project_requirement"]'::jsonb,
  'stale HYBRID verification removes browser completion authority'
);
update public.website_execution_workspaces
set binding_revision = binding_revision - 1
where project_id = 'e8180000-0000-4000-8000-000000000001';
select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000002');
select lives_ok(
  $$select public.complete_project_requirement_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 5),
    3, '{"attestation":"Technische PASS inhoudelijk beoordeeld."}'::jsonb,
    'e8450000-0000-4000-8000-000000000001'
  )$$,
  'HYBRID completes only after current PASS plus operator attestation'
);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select lives_ok(
  $$select public.record_project_requirement_verification_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001',
    (select requirement_id from public.project_requirements
      where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 6),
    1, 'project_work_started', 1, 'PASS',
    jsonb_build_object(
      'evidence_type','COMMERCIAL_EVENT',
      'event_id',(select audit_event_id from public.audit_events
        where project_id = 'e8180000-0000-4000-8000-000000000001'
          and event_type = 'PROJECT_WORK_STARTED' order by audit_event_id limit 1),
      'event_type','PROJECT_WORK_STARTED'
    ), 'e8460000-0000-4000-8000-000000000001'
  )$$,
  'exact immutable project event automatically completes EXTERNAL requirement'
);
select ok(
  not pg_temp.get_requirement_permitted_actions_v1(
    'e8000000-0000-4000-8000-000000000002',
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 6
  ) ? 'complete_project_requirement',
  'EXTERNAL requirement never exposes operator completion'
);
select is(
  pg_temp.get_requirement_readiness_v1('e8180000-0000-4000-8000-000000000001')->>'required_completed',
  '3',
  'shared readiness counts coherent completed required requirements'
);
select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000002');
select is(
  pg_temp.get_requirement_projection_v1(
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001'
  )->'readiness',
  pg_temp.get_requirement_readiness_v1('e8180000-0000-4000-8000-000000000001'),
  'board projection consumes the same shared readiness evaluator'
);
select set_config('lws.requirement_command', 'on', true);
update public.project_requirements_boards
set source_payload_sha256 = repeat('f', 64)
where project_id = 'e8180000-0000-4000-8000-000000000001';
select set_config('lws.requirement_command', '', true);
select is(
  pg_temp.get_requirement_permitted_actions_v1(
    'e8000000-0000-4000-8000-000000000002',
    'e8100000-0000-4000-8000-000000000001',
    'e8180000-0000-4000-8000-000000000001', 3
  ),
  '[]'::jsonb,
  'board source authority drift removes every projected item action'
);
select is(
  pg_temp.get_requirement_readiness_v1(
    'e8180000-0000-4000-8000-000000000001'
  )->>'reason',
  'REQUIREMENTS_SOURCE_AUTHORITY_MISMATCH',
  'readiness fails closed when finalized board source authority drifts'
);
select set_config('lws.requirement_command', 'on', true);
update public.project_requirements_boards as board
set source_payload_sha256 = approval.payload_sha256
from public.quote_request_quotation_approvals as approval
where board.project_id = 'e8180000-0000-4000-8000-000000000001'
  and approval.id = board.source_approval_id;
select set_config('lws.requirement_command', '', true);
select throws_ok(
  $$update public.project_requirement_verifications set result = 'FAIL'$$,
  '55000', 'REQUIREMENT_VERIFICATION_IMMUTABLE',
  'verification records are append-only'
);
select pg_temp.set_requirement_claims_v1('e8000000-0000-4000-8000-000000000001');
select set_config('lws.commercial_command', 'on', true);
update public.commercial_projects
set current_state = 'PROJECT_RELEASED', revision = 2, updated_at = clock_timestamp()
where project_id = 'e8180000-0000-4000-8000-000000000001';
select set_config('lws.commercial_command', '', true);

create temporary table preview_guard_baseline as
select
  (select count(*) from public.preview_versions
    where project_id = 'e8180000-0000-4000-8000-000000000001') as previews,
  (select count(*) from public.workflow_events
    where project_id = 'e8180000-0000-4000-8000-000000000001') as workflows,
  (select count(*) from public.audit_events
    where project_id = 'e8180000-0000-4000-8000-000000000001') as audits,
  (select count(*) from public.idempotency_ledger
    where project_id = 'e8180000-0000-4000-8000-000000000001') as commands;
create temporary table requirements_board_guard_snapshot as
select finalized_by, finalized_at
from public.project_requirements_boards
where project_id = 'e8180000-0000-4000-8000-000000000001';

select is(
  pg_temp.preview_ready_attempt_v1('e8500000-0000-4000-8000-000000000001'),
  'PROJECT_REQUIREMENTS_NOT_READY',
  'preview command rejects pending and blocked required requirements'
);
select is(
  (select jsonb_build_array(
    project.current_state, project.revision,
    (select count(*) from public.preview_versions
      where project_id = project.project_id) - baseline.previews,
    (select count(*) from public.workflow_events
      where project_id = project.project_id) - baseline.workflows,
    (select count(*) from public.audit_events
      where project_id = project.project_id) - baseline.audits,
    (select count(*) from public.idempotency_ledger
      where project_id = project.project_id) - baseline.commands
  )
  from public.commercial_projects as project
  cross join preview_guard_baseline as baseline
  where project.project_id = 'e8180000-0000-4000-8000-000000000001'),
  '["PROJECT_RELEASED",2,0,0,0,0]'::jsonb,
  'blocked preview writes no version, workflow, audit, idempotency or project revision'
);

select set_config('lws.requirement_command', 'on', true);
update public.project_requirements
set status = 'ACTIVE', started_at = clock_timestamp(), revision = revision + 1
where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 3;
select set_config('lws.requirement_command', '', true);
select is(
  pg_temp.preview_ready_attempt_v1('e8500000-0000-4000-8000-000000000002'),
  'PROJECT_REQUIREMENTS_NOT_READY',
  'preview command rejects an ACTIVE required requirement'
);
select set_config('lws.requirement_command', 'on', true);
update public.project_requirements
set status = 'PENDING', started_at = null, revision = revision - 1
where project_id = 'e8180000-0000-4000-8000-000000000001' and item_number = 3;
select set_config('lws.requirement_command', '', true);

update public.website_execution_workspaces
set binding_revision = binding_revision + 1
where project_id = 'e8180000-0000-4000-8000-000000000001';
select is(
  pg_temp.preview_ready_attempt_v1('e8500000-0000-4000-8000-000000000003'),
  'PROJECT_REQUIREMENTS_NOT_READY',
  'preview command rejects stale AUTO and HYBRID verification'
);
update public.website_execution_workspaces
set binding_revision = binding_revision - 1
where project_id = 'e8180000-0000-4000-8000-000000000001';

select set_config('lws.requirement_command', 'on', true);
update public.project_requirements_boards
set source_payload_sha256 = repeat('f', 64)
where project_id = 'e8180000-0000-4000-8000-000000000001';
select set_config('lws.requirement_command', '', true);
select is(
  pg_temp.preview_ready_attempt_v1('e8500000-0000-4000-8000-000000000004'),
  'PROJECT_REQUIREMENTS_NOT_READY',
  'preview command rejects a wrong accepted-source binding'
);
select set_config('lws.requirement_command', 'on', true);
update public.project_requirements_boards as board
set source_payload_sha256 = approval.payload_sha256
from public.quote_request_quotation_approvals as approval
where board.project_id = 'e8180000-0000-4000-8000-000000000001'
  and approval.id = board.source_approval_id;

update public.project_requirements_boards
set status = 'SUPERSEDED'
where project_id = 'e8180000-0000-4000-8000-000000000001';
select set_config('lws.requirement_command', '', true);
select is(
  pg_temp.preview_ready_attempt_v1('e8500000-0000-4000-8000-000000000005'),
  'PROJECT_REQUIREMENTS_NOT_READY',
  'preview command rejects an absent current requirements board'
);
select set_config('lws.requirement_command', 'on', true);
update public.project_requirements_boards
set status = 'FINALIZED'
where project_id = 'e8180000-0000-4000-8000-000000000001';

update public.project_requirements_boards
set status = 'DRAFT', finalized_by = null, finalized_at = null
where project_id = 'e8180000-0000-4000-8000-000000000001';
select set_config('lws.requirement_command', '', true);
select is(
  pg_temp.preview_ready_attempt_v1('e8500000-0000-4000-8000-000000000006'),
  'PROJECT_REQUIREMENTS_NOT_READY',
  'preview command rejects a draft requirements board'
);
select set_config('lws.requirement_command', 'on', true);
update public.project_requirements_boards as board
set status = 'FINALIZED', finalized_by = snapshot.finalized_by,
    finalized_at = snapshot.finalized_at
from requirements_board_guard_snapshot as snapshot
where board.project_id = 'e8180000-0000-4000-8000-000000000001';
select set_config('lws.requirement_command', '', true);

set local session_replication_role = replica;
update public.project_requirements
set required = false
where project_id = 'e8180000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select is(
  pg_temp.preview_ready_attempt_v1('e8500000-0000-4000-8000-000000000007'),
  'PROJECT_REQUIREMENTS_NOT_READY',
  'preview command rejects a finalized board with zero required items'
);
set local session_replication_role = replica;
update public.project_requirements
set required = item_number <= 10
where project_id = 'e8180000-0000-4000-8000-000000000001';
set local session_replication_role = origin;

select set_config('lws.requirement_command', 'on', true);
update public.project_requirements
set status = 'COMPLETED',
    started_at = coalesce(started_at, clock_timestamp()),
    completed_at = clock_timestamp(),
    completed_by = 'OPERATOR:e8010000-0000-4000-8000-000000000001',
    evidence_reference = '{"attestation":"Owner-reviewed preview requirement."}'::jsonb,
    verification_result = 'NOT_APPLICABLE', blocked_reason = null,
    revision = revision + 1, updated_at = clock_timestamp()
where project_id = 'e8180000-0000-4000-8000-000000000001'
  and required and completion_mode = 'OPERATOR';
select set_config('lws.requirement_command', '', true);
select is(
  pg_temp.get_requirement_readiness_v1(
    'e8180000-0000-4000-8000-000000000001'
  )->>'readiness',
  'READY',
  'all required items are coherently complete while optional items remain open'
);
select is(
  (select count(*)::integer from public.project_requirements
   where project_id = 'e8180000-0000-4000-8000-000000000001'
     and not required and status <> 'COMPLETED'),
  2,
  'two optional open requirements do not block preview readiness'
);
select lives_ok(
  $$select public.execute_commercial_command_v2(
    'e8180000-0000-4000-8000-000000000001',
    'record_preview_ready', 'PROJECT_RELEASED', 2,
    'e8500000-0000-4000-8000-000000000008',
    '{"content_reference":"requirements-ready-preview","content_sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}'::jsonb
  )$$,
  'preview command succeeds through the existing authority when requirements are READY'
);
select is(
  (select jsonb_build_array(current_state, revision)
   from public.commercial_projects
   where project_id = 'e8180000-0000-4000-8000-000000000001'),
  '["PREVIEW_READY",3]'::jsonb,
  'successful guarded command preserves the existing PREVIEW_READY transition'
);
select set_config('lws.requirement_command', 'on', true);
select throws_ok(
  $$update public.project_requirements
    set title = 'Mutated accepted definition'
    where project_id = 'e8180000-0000-4000-8000-000000000001'$$,
  '55000', 'FINALIZED_REQUIREMENT_DEFINITION_IMMUTABLE',
  'finalized requirement definitions remain immutable through the internal command channel'
);
select set_config('lws.requirement_command', '', true);

select * from finish();
rollback;
