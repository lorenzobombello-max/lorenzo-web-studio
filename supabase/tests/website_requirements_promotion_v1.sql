begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, lws_internal, extensions;

select no_plan();

select has_table(
  'public', 'website_concept_promotion_commands',
  'promotion command ledger exists'
);
select has_table(
  'public', 'website_work_context_promotion_events',
  'promotion event authority exists'
);
select has_function(
  'public', 'promote_website_concept_v1',
  array['uuid', 'uuid', 'bigint', 'uuid'],
  'promotion RPC has the exact server-derived-project signature'
);

select columns_are(
  'public', 'website_concept_promotion_commands',
  array[
    'idempotency_key', 'request_fingerprint_sha256', 'actor_id',
    'quote_request_id', 'website_work_context_id',
    'expected_context_revision', 'status', 'response_payload',
    'promotion_event_id', 'created_at', 'completed_at'
  ],
  'promotion ledger exposes only the closed command authority'
);
select columns_are(
  'public', 'website_work_context_promotion_events',
  array[
    'promotion_event_id', 'event_type', 'quote_request_id',
    'website_work_context_id', 'concept_id', 'project_id', 'actor_id',
    'previous_phase', 'phase', 'previous_context_revision',
    'context_revision', 'created_at'
  ],
  'promotion events expose only the append-only audit authority'
);

select col_is_pk(
  'public', 'website_concept_promotion_commands', 'idempotency_key',
  'idempotency key is the promotion command identity'
);
select col_is_pk(
  'public', 'website_work_context_promotion_events', 'promotion_event_id',
  'promotion event identity is primary'
);
select col_type_is(
  'public', 'website_concept_promotion_commands',
  'request_fingerprint_sha256', 'text',
  'canonical promotion fingerprint is text SHA-256'
);
select col_type_is(
  'public', 'website_concept_promotion_commands',
  'expected_context_revision', 'bigint',
  'only context revision is browser concurrency authority'
);
select col_type_is(
  'public', 'website_concept_promotion_commands',
  'response_payload', 'jsonb',
  'completed logical response is persisted for exact replay'
);
select col_type_is(
  'public', 'website_work_context_promotion_events',
  'created_at', 'timestamp with time zone',
  'promotion event timestamp is authoritative'
);

select ok(
  (select relation.relrowsecurity and relation.relforcerowsecurity
   from pg_class as relation
   where relation.oid = to_regclass('public.website_concept_promotion_commands')),
  'promotion command ledger forces RLS'
);
select ok(
  (select relation.relrowsecurity and relation.relforcerowsecurity
   from pg_class as relation
   where relation.oid = to_regclass('public.website_work_context_promotion_events')),
  'promotion event authority forces RLS'
);
select ok(
  not exists (
    select 1
    from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in (
        'website_concept_promotion_commands',
        'website_work_context_promotion_events'
      )
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  'runtime roles have no direct promotion-table privileges'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = to_regclass('public.website_concept_promotion_commands')
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%PENDING%COMPLETED%'
  ),
  'promotion ledger status is closed to PENDING and COMPLETED'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = to_regclass('public.website_work_context_promotion_events')
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%WEBSITE_WORK_CONTEXT_PROMOTED%'
  ),
  'promotion event type is closed to WEBSITE_WORK_CONTEXT_PROMOTED'
);
select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = to_regclass('public.website_work_context_promotion_events')
      and not tgisinternal
      and tgname like '%guard%'
  ),
  'promotion event history has an append-only command guard'
);

select ok(
  coalesce((
    select prosecdef
    from pg_proc
    where oid = to_regprocedure(
      'public.promote_website_concept_v1(uuid,uuid,bigint,uuid)'
    )
  ), false),
  'promotion RPC is SECURITY DEFINER'
);
select ok(
  coalesce((
    select prosrc like '%assert_operator_aal2_v1%'
      and prosrc like '%role <> ''owner''%'
      and prosrc like '%WEBSITE_PROMOTION_PROJECT_NOT_FOUND%'
      and prosrc like '%WEBSITE_PROMOTION_PROJECT_AMBIGUOUS%'
      and prosrc like '%WEBSITE_CONCEPT_PROMOTION_IDEMPOTENCY_CONFLICT%'
      and prosrc like '%WEBSITE_CONCEPT_ALREADY_PROMOTED%'
    from pg_proc
    where oid = to_regprocedure(
      'public.promote_website_concept_v1(uuid,uuid,bigint,uuid)'
    )
  ), false),
  'promotion RPC closes owner AAL2, project cardinality, replay conflict, and completed-state rejection'
);
select ok(
  coalesce((
    select prosrc like '%website_work_contexts%FOR UPDATE%'
      and prosrc like '%website_concepts%FOR UPDATE%'
      and prosrc like '%commercial_projects%FOR UPDATE%'
      and prosrc like '%website_execution_workspaces%FOR UPDATE%'
      and prosrc like '%website_requirements_boards%FOR UPDATE%'
      and prosrc like '%WEBSITE_WORK_CONTEXT_PROMOTED%'
    from pg_proc
    where oid = to_regprocedure(
      'public.promote_website_concept_v1(uuid,uuid,bigint,uuid)'
    )
  ), false),
  'promotion RPC locks every continuity root and appends the exact audit event'
);
select ok(
  coalesce((
    select prosrc not like '%p_project_id%'
      and prosrc like '%expected_context_revision%'
      and prosrc like '%context_revision%'
      and prosrc like '%requirements_board_revision%'
      and prosrc like '%workspace_binding_revision%'
      and prosrc like '%replayed%'
    from pg_proc
    where oid = to_regprocedure(
      'public.promote_website_concept_v1(uuid,uuid,bigint,uuid)'
    )
  ), false),
  'promotion RPC derives project authority and returns the closed continuity result'
);
select ok(
  not exists (
    select 1
    from pg_proc as procedure
    cross join lateral aclexplode(
      coalesce(procedure.proacl, acldefault('f', procedure.proowner))
    ) as privilege
    join pg_roles as grantee on grantee.oid = privilege.grantee
    where procedure.oid = to_regprocedure(
      'public.promote_website_concept_v1(uuid,uuid,bigint,uuid)'
    )
      and grantee.rolname = 'anon'
      and privilege.privilege_type = 'EXECUTE'
  ),
  'anonymous callers cannot execute promotion'
);
select ok(
  exists (
    select 1
    from pg_proc as procedure
    cross join lateral aclexplode(
      coalesce(procedure.proacl, acldefault('f', procedure.proowner))
    ) as privilege
    join pg_roles as grantee on grantee.oid = privilege.grantee
    where procedure.oid = to_regprocedure(
      'public.promote_website_concept_v1(uuid,uuid,bigint,uuid)'
    )
      and grantee.rolname = 'authenticated'
      and privilege.privilege_type = 'EXECUTE'
  ),
  'authenticated caller JWT may reach the server authority'
);
select ok(
  not exists (
    select 1
    from pg_proc as procedure
    cross join lateral aclexplode(
      coalesce(procedure.proacl, acldefault('f', procedure.proowner))
    ) as privilege
    join pg_roles as grantee on grantee.oid = privilege.grantee
    where procedure.oid = to_regprocedure(
      'public.promote_website_concept_v1(uuid,uuid,bigint,uuid)'
    )
      and grantee.rolname = 'service_role'
      and privilege.privilege_type = 'EXECUTE'
  ),
  'service role has no promotion execution grant'
);

create function pg_temp.set_promotion_claims_v1(p_subject uuid, p_aal text)
returns void
language sql
as $$
  select set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_subject, 'role', 'authenticated', 'aal', p_aal
    )::text,
    true
  )::text;
$$;

insert into public.quote_requests(
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, request_kind, record_classification
) values
  ('d8100000-0000-4000-8000-000000000001', 'Promotion fixture',
   'promotion@example.test', 'business', 'Meer dan EUR 6.000', 'flexible',
   'Runtime promotion continuity fixture.', true, 'approved', 'website', 'production'),
  ('d8100002-0000-4000-8000-000000000002', 'Cross dossier fixture',
   'promotion-cross@example.test', 'business', 'Meer dan EUR 6.000', 'flexible',
   'Runtime cross dossier rollback fixture.', true, 'approved', 'website', 'production');

create temporary table promotion_approval_payload as
select jsonb_build_object(
  'contract_version', 1,
  'source_quote_request_id', 'd8100000-0000-4000-8000-000000000001',
  'source_intake_id', 'd8110000-0000-4000-8000-000000000001',
  'pricing_snapshot', jsonb_build_object(
    'snapshot_id', 'd8120000-0000-4000-8000-000000000001',
    'snapshot_contract_version', 2, 'integrity_algorithm_version', 'hmac-sha256-v1',
    'integrity_key_id', 'v1', 'integrity_mac', repeat('a', 64)
  ),
  'currency', 'EUR',
  'line_items', jsonb_build_array(jsonb_build_object(
    'line_id', 'website', 'sequence', 1, 'product_or_service_code', 'WEBSITE',
    'description', 'Websiteontwikkeling', 'quantity', 1, 'unit', 'project',
    'unit_price_minor', 10000, 'discount_minor', 0, 'vat_treatment', 'STANDARD',
    'vat_rate', 21, 'line_net_amount_minor', 10000, 'cost_type', 'ONE_TIME'
  )),
  'totals', jsonb_build_object(
    'one_time_subtotal_minor', 10000, 'recurring_subtotal_minor', 0,
    'discount_total_minor', 0, 'vat_base_minor', 10000,
    'vat_amount_minor', 2100, 'total_gross_minor', 12100
  ),
  'discount', jsonb_build_object(
    'discount_type', null, 'discount_value_minor', 0,
    'discount_reason', null, 'approved_by', null, 'approved_at', null
  ),
  'customer_identity', jsonb_build_object(
    'source_quote_request_id', 'd8100000-0000-4000-8000-000000000001',
    'source_intake_id', 'd8110000-0000-4000-8000-000000000001',
    'customer_id', null, 'legal_name', 'Promotion Fixture BV',
    'contact_name', 'Promotion fixture', 'email', 'promotion@example.test',
    'address_line_1', 'Teststraat 1', 'address_line_2', null,
    'postal_code', '9000', 'city', 'Gent', 'country_code', 'BE',
    'enterprise_number', null, 'vat_number', null,
    'source_fields', jsonb_build_object('legal_name', 'fixture'),
    'snapshot_sha256', repeat('b', 64)
  ),
  'project_scope', jsonb_build_object(
    'project_id', null, 'project_title', 'Promotion fixture',
    'project_type', 'website', 'scope_summary', 'Accepted promotion scope',
    'requested_languages', jsonb_build_array('nl'), 'included_page_count', 1,
    'features', jsonb_build_array('contact_form'), 'copywriting', null,
    'seo', null, 'hosting', null, 'maintenance', null,
    'exclusions', '[]'::jsonb, 'assumptions', '[]'::jsonb, 'indicative_timing', null,
    'source_intake_id', 'd8110000-0000-4000-8000-000000000001',
    'source_pricing_snapshot_id', 'd8120000-0000-4000-8000-000000000001',
    'snapshot_sha256', repeat('c', 64)
  ),
  'vat_approval', jsonb_build_object(
    'vat_treatment', 'STANDARD', 'vat_rate', 21,
    'vat_decision_source', 'accountant', 'vat_approved_by', 'accountant:test',
    'vat_approved_at', '2026-09-19T08:00:00Z'
  ),
  'payment_schedule', jsonb_build_object(
    'schedule_id', 'promotion-fixture',
    'milestones', jsonb_build_array(jsonb_build_object(
      'sequence', 1, 'label', 'Volledige betaling', 'percentage', 100,
      'amount_minor', null, 'trigger', 'invoice', 'due_terms_days', 30,
      'recurring_cycle', null
    )),
    'approved_by', 'commercial:test', 'approved_at', '2026-09-19T08:00:00Z'
  ),
  'validity', jsonb_build_object(
    'valid_from', '2026-09-19', 'valid_until', '2026-10-19',
    'validity_days', 30, 'approved_by', 'commercial:test',
    'approved_at', '2026-09-19T08:00:00Z'
  ),
  'legal_references', jsonb_build_object(
    'terms_reference', 'terms-v1', 'terms_version', '1.0.0',
    'terms_sha256', repeat('d', 64), 'terms_status', 'APPROVED',
    'agreement_template_reference', null, 'agreement_template_version', null,
    'agreement_template_sha256', null
  )
) as payload;

set local session_replication_role = replica;
insert into public.quote_request_quotation_approvals(
  id, draft_id, quote_request_id, intake_id, pricing_snapshot_id,
  contract_version, approval_version, approved_payload, payload_sha256,
  approved_by, approved_at
)
select 'd8130000-0000-4000-8000-000000000001',
  'd8140000-0000-4000-8000-000000000001',
  'd8100000-0000-4000-8000-000000000001',
  'd8110000-0000-4000-8000-000000000001',
  'd8120000-0000-4000-8000-000000000001', 1, 1, payload,
  public.quotation_approval_payload_sha256_v1(payload),
  'test:promotion', clock_timestamp()
from promotion_approval_payload;
insert into public.quote_request_quotation_approvals(
  id, draft_id, quote_request_id, intake_id, pricing_snapshot_id,
  contract_version, approval_version, approved_payload, payload_sha256,
  approved_by, approved_at
)
select 'd8130000-0000-4000-8000-000000000002',
  'd8140000-0000-4000-8000-000000000002',
  'd8100000-0000-4000-8000-000000000001',
  'd8110000-0000-4000-8000-000000000001',
  'd8120000-0000-4000-8000-000000000001', 1, 2, payload,
  public.quotation_approval_payload_sha256_v1(payload),
  'test:promotion', clock_timestamp()
from promotion_approval_payload;

insert into public.quote_request_quotation_issuances(
  id, quotation_number, quotation_version, status, approval_id,
  issued_at, issued_by, template_id, template_version, template_sha256,
  generation_contract_version, issuance_input_sha256, generation_payload_sha256,
  docx_sha256, docx_bytes, prepare_idempotency_key, prepare_fingerprint,
  commit_idempotency_key, commit_fingerprint
) values
  ('d8150000-0000-4000-8000-000000000001', 'LWS-OFF-2099-9201', 1, 'ISSUED',
   'd8130000-0000-4000-8000-000000000001', clock_timestamp(), 'test:promotion',
   'LWS_QUOTATION_NL_BE', '1.0.0', repeat('1', 64), 1, repeat('2', 64),
   repeat('3', 64), repeat('4', 64), 100, 'd8160000-0000-4000-8000-000000000001',
   repeat('5', 64), 'd8170000-0000-4000-8000-000000000001', repeat('6', 64)),
  ('d8150000-0000-4000-8000-000000000002', 'LWS-OFF-2099-9202', 2, 'ISSUED',
    'd8130000-0000-4000-8000-000000000002', clock_timestamp(), 'test:promotion',
   'LWS_QUOTATION_NL_BE', '1.0.0', repeat('1', 64), 1, repeat('7', 64),
   repeat('8', 64), repeat('9', 64), 100, 'd8160000-0000-4000-8000-000000000002',
   repeat('a', 64), 'd8170000-0000-4000-8000-000000000002', repeat('b', 64));

create temporary table promotion_acceptance_payloads as
select fixture.*,
  jsonb_build_object(
    'acceptance_contract_version', 1,
    'issuance_id', fixture.issuance_id,
    'quotation_number', fixture.quotation_number,
    'quotation_version', fixture.quotation_version,
    'customer_identity_sha256', repeat('b', 64),
    'generation_payload_sha256', fixture.generation_sha,
    'template', jsonb_build_object(
      'template_id', 'LWS_QUOTATION_NL_BE', 'template_version', '1.0.0',
      'template_sha256', repeat('1', 64)
    ),
    'docx', jsonb_build_object('sha256', fixture.docx_sha, 'bytes', 100),
    'acceptance_terms', jsonb_build_object(
      'terms_id', 'terms-v1', 'terms_version', '1.0.0',
      'terms_sha256', repeat('d', 64)
    ),
    'actor', jsonb_build_object(
      'name', 'Promotion Owner', 'email', 'promotion@example.test',
      'organization', 'Promotion Fixture BV', 'role', 'Bestuurder'
    ),
    'authority_declaration', true,
    'accepted_at', '2026-09-19T09:00:00.000000Z'
  ) as payload
from (values
  ('d8180000-0000-4000-8000-000000000001'::uuid,
   'd8150000-0000-4000-8000-000000000001'::uuid,
   'LWS-OFF-2099-9201'::text, 1, repeat('3', 64), repeat('4', 64)),
  ('d8180000-0000-4000-8000-000000000002'::uuid,
   'd8150000-0000-4000-8000-000000000002'::uuid,
   'LWS-OFF-2099-9202'::text, 2, repeat('8', 64), repeat('9', 64))
) as fixture(acceptance_id, issuance_id, quotation_number, quotation_version, generation_sha, docx_sha);

insert into public.quote_request_quotation_acceptances(
  id, issuance_id, quotation_number, quotation_version,
  customer_identity_sha256, customer_legal_name, generation_payload_sha256,
  template_id, template_version, template_sha256, docx_sha256, docx_bytes,
  acceptance_contract_version, acceptance_terms_id, acceptance_terms_version,
  acceptance_terms_sha256, accepting_name, accepting_email,
  accepting_organization, accepting_role,
  authority_declaration, acceptance_payload, acceptance_payload_sha256,
  semantic_request_fingerprint, accepted_at, created_at
)
select acceptance_id, issuance_id, quotation_number, quotation_version,
  repeat('b', 64), 'Promotion Fixture BV', generation_sha,
  'LWS_QUOTATION_NL_BE', '1.0.0', repeat('1', 64), docx_sha, 100, 1,
  'terms-v1', '1.0.0', repeat('d', 64), 'Promotion Owner',
  'promotion@example.test', 'Promotion Fixture BV', 'Bestuurder', true,
  payload, public.quotation_acceptance_payload_sha256_v1(payload),
  repeat('f', 64), '2026-09-19T09:00:00Z', '2026-09-19T09:00:00Z'
from promotion_acceptance_payloads;

insert into public.commercial_customers(customer_id, acceptance_id, identity_sha256) values
  ('d8190000-0000-4000-8000-000000000001', 'd8180000-0000-4000-8000-000000000001', repeat('b', 64)),
  ('d8190000-0000-4000-8000-000000000002', 'd8180000-0000-4000-8000-000000000002', repeat('b', 64));
insert into public.commercial_projects(
  project_id, customer_id, quotation_issuance_id, acceptance_id,
  accepted_total_minor, currency, m1_minor, m2_minor, m3_minor,
  current_state, revision
) values
  ('d81a0000-0000-4000-8000-000000000001', 'd8190000-0000-4000-8000-000000000001',
   'd8150000-0000-4000-8000-000000000001', 'd8180000-0000-4000-8000-000000000001',
   10000, 'EUR', 4000, 4000, 2000, 'QUOTE_ACCEPTED', 1),
  ('d81a0000-0000-4000-8000-000000000002', 'd8190000-0000-4000-8000-000000000002',
   'd8150000-0000-4000-8000-000000000002', 'd8180000-0000-4000-8000-000000000002',
   10000, 'EUR', 4000, 4000, 2000, 'QUOTE_ACCEPTED', 1);
insert into public.website_concepts(
  concept_id, quote_request_id, mode, briefing_status, concept_status, revision, created_by
) values
(
  'd81b0000-0000-4000-8000-000000000001', 'd8100000-0000-4000-8000-000000000001',
  'PRE_PROJECT', 'COMPLETE', 'ACTIVE', 4,
  (select operator_id from public.commercial_operators
   where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0')
),
(
  'd81b0000-0000-4000-8000-000000000002', 'd8100002-0000-4000-8000-000000000002',
  'PRE_PROJECT', 'COMPLETE', 'ACTIVE', 1,
  (select operator_id from public.commercial_operators
   where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0')
);
insert into public.website_work_contexts(
  website_work_context_id, quote_request_id, concept_id, project_id, phase, revision
) values
(
  'd81c0000-0000-4000-8000-000000000001', 'd8100000-0000-4000-8000-000000000001',
  'd81b0000-0000-4000-8000-000000000001', null, 'PRE_PROJECT', 7
),
(
  'd81c0000-0000-4000-8000-000000000002', 'd8100002-0000-4000-8000-000000000002',
  'd81b0000-0000-4000-8000-000000000002', null, 'PRE_PROJECT', 1
);
insert into public.website_execution_workspaces(
  website_workspace_id, website_work_context_id, project_id, quote_request_id,
  repository_owner, repository_name, binding_revision, created_by,
  workspace_state, provisioned_by, provisioned_at, repository_provider,
  repository_external_id, repository_node_id, repository_visibility,
  repository_state, starter_source, starter_version, starter_commit_sha,
  repository_marker_commit_sha, last_commit_sha, repository_bound_at
) values (
  'd81d0000-0000-4000-8000-000000000001', 'd81c0000-0000-4000-8000-000000000001',
  null, 'd8100000-0000-4000-8000-000000000001', 'fixture-owner', 'fixture-repository',
  3, (select operator_id from public.commercial_operators
      where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'), 'REPOSITORY_READY',
  (select operator_id from public.commercial_operators
     where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'), clock_timestamp(),
    'GITHUB', 1369000001, 'R_promotion_continuity', 'private', 'BOUND',
    'lorenzo-web-solutions/lws-website-starter', '1.0.0', repeat('9', 40),
    repeat('8', 40), repeat('a', 40), clock_timestamp()
);
insert into public.website_requirements_boards(
  requirements_board_id, website_work_context_id, quote_request_id,
  sync_state, mapping_version, revision, created_by
) values (
  'd81e0000-0000-4000-8000-000000000001', 'd81c0000-0000-4000-8000-000000000001',
  'd8100000-0000-4000-8000-000000000001', 'CURRENT', 1, 5,
  (select operator_id from public.commercial_operators
   where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0')
);
insert into public.website_requirements(
  requirement_id, requirements_board_id, website_work_context_id, quote_request_id,
  source_key, source_reference, source_value_sha256, item_number, sort_order,
  title, description, category, status, completion_mode, required,
  verification_result, revision
) values (
  'd81f0000-0000-4000-8000-000000000001', 'd81e0000-0000-4000-8000-000000000001',
  'd81c0000-0000-4000-8000-000000000001', 'd8100000-0000-4000-8000-000000000001',
  'fixture.home', '{"source":"fixture"}', repeat('1', 64), 1, 1,
  'Homepage', 'Behoud de bestaande homepagevereiste.', 'PAGE', 'PENDING',
  'OPERATOR', true, 'UNKNOWN', 2
);
insert into public.website_requirement_events(
  event_id, requirements_board_id, website_work_context_id, quote_request_id,
  requirement_id, event_type, actor_id, command_id, prior_revision,
  new_revision, metadata
) values (
  'd8200000-0000-4000-8000-000000000001', 'd81e0000-0000-4000-8000-000000000001',
  'd81c0000-0000-4000-8000-000000000001', 'd8100000-0000-4000-8000-000000000001',
  'd81f0000-0000-4000-8000-000000000001', 'WEBSITE_REQUIREMENT_CREATED',
  'OPERATOR:' || (select operator_id::text from public.commercial_operators
                  where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
  'd8210000-0000-4000-8000-000000000001', null, 2, '{}'
);
insert into public.website_requirement_verifications(
  verification_id, requirement_id, requirements_board_id, website_work_context_id,
  quote_request_id, website_workspace_id, binding_revision, canonical_commit_sha,
  requirement_revision, rule_key, rule_version, result, evidence_reference,
  evidence_sha256, verified_by
) values (
  'd8220000-0000-4000-8000-000000000001', 'd81f0000-0000-4000-8000-000000000001',
  'd81e0000-0000-4000-8000-000000000001', 'd81c0000-0000-4000-8000-000000000001',
  'd8100000-0000-4000-8000-000000000001', 'd81d0000-0000-4000-8000-000000000001',
  3, repeat('a', 40), 2, 'fixture_rule', 1, 'PASS', '{"fixture":true}',
  repeat('2', 64), 'SYSTEM:website_requirements_verifier'
);
set local session_replication_role = origin;

select pg_temp.set_promotion_claims_v1('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'aal1');
select throws_ok(
  $$select public.promote_website_concept_v1(
    'd8100000-0000-4000-8000-000000000001',
    'd81c0000-0000-4000-8000-000000000001', 7,
    'd8230000-0000-4000-8000-000000000001')$$,
  '42501', 'AAL2_REQUIRED', 'owner AAL1 cannot promote'
);
select pg_temp.set_promotion_claims_v1('bd2ab636-0d42-4069-88a9-60bd97f2b335', 'aal2');
select throws_ok(
  $$select public.promote_website_concept_v1(
    'd8100000-0000-4000-8000-000000000001',
    'd81c0000-0000-4000-8000-000000000001', 7,
    'd8230000-0000-4000-8000-000000000002')$$,
  '42501', 'WEBSITE_CONCEPT_PROMOTION_ROLE_DENIED',
  'non-owner AAL2 cannot promote'
);
select pg_temp.set_promotion_claims_v1('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'aal2');
select throws_ok(
  $$select public.promote_website_concept_v1(
    'd8100002-0000-4000-8000-000000000002',
    'd81c0000-0000-4000-8000-000000000002', 1,
    'd8230000-0000-4000-8000-000000000007')$$,
  'P0001', 'WEBSITE_PROMOTION_PROJECT_NOT_FOUND',
  'zero eligible projects reject without creating promotion authority'
);
select throws_ok(
  $$select public.promote_website_concept_v1(
    'd8100000-0000-4000-8000-000000000001',
    'd81c0000-0000-4000-8000-000000000001', 7,
    'd8230000-0000-4000-8000-000000000003')$$,
  'P0001', 'WEBSITE_PROMOTION_PROJECT_AMBIGUOUS',
  'multiple eligible projects reject without arbitrary selection'
);
select is(
  (select count(*) from public.website_concept_promotion_commands
   where idempotency_key = 'd8230000-0000-4000-8000-000000000003'),
  0::bigint, 'ambiguous promotion rolls back its pending command'
);

set local session_replication_role = replica;
delete from public.commercial_projects where project_id = 'd81a0000-0000-4000-8000-000000000002';
delete from public.commercial_customers where customer_id = 'd8190000-0000-4000-8000-000000000002';
delete from public.quote_request_quotation_acceptances where id = 'd8180000-0000-4000-8000-000000000002';
delete from public.quote_request_quotation_issuances where id = 'd8150000-0000-4000-8000-000000000002';
delete from public.quote_request_quotation_approvals where id = 'd8130000-0000-4000-8000-000000000002';
set local session_replication_role = origin;

select throws_ok(
  $$select public.promote_website_concept_v1(
    'd8100000-0000-4000-8000-000000000001',
    'd81c0000-0000-4000-8000-000000000001', 6,
    'd8230000-0000-4000-8000-000000000008')$$,
  '40001', 'CONCURRENT_MODIFICATION',
  'stale expected context revision rejects atomically'
);

set local session_replication_role = replica;
insert into public.website_work_context_promotion_events(
  promotion_event_id, event_type, quote_request_id, website_work_context_id,
  concept_id, project_id, actor_id, previous_phase, phase,
  previous_context_revision, context_revision
) values (
  'd8240000-0000-4000-8000-000000000001', 'WEBSITE_WORK_CONTEXT_PROMOTED',
  'd8100000-0000-4000-8000-000000000001', 'd81c0000-0000-4000-8000-000000000001',
  'd81b0000-0000-4000-8000-000000000001', 'd81a0000-0000-4000-8000-000000000001',
  (select operator_id from public.commercial_operators
   where auth_user_id = 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'),
  'PRE_PROJECT', 'OFFICIAL_PROJECT', 7, 8
);
set local session_replication_role = origin;
select throws_ok(
  $$select public.promote_website_concept_v1(
    'd8100000-0000-4000-8000-000000000001',
    'd81c0000-0000-4000-8000-000000000001', 7,
    'd8230000-0000-4000-8000-000000000009')$$,
  '23505', null,
  'an injected post-update audit failure aborts promotion'
);
select ok(
  (select phase = 'PRE_PROJECT' and project_id is null and revision = 7
   from public.website_work_contexts
   where website_work_context_id = 'd81c0000-0000-4000-8000-000000000001')
  and (select concept_status = 'ACTIVE' and promoted_project_id is null and revision = 4
   from public.website_concepts
   where concept_id = 'd81b0000-0000-4000-8000-000000000001')
  and (select project_id is null and binding_revision = 3
   from public.website_execution_workspaces
   where website_workspace_id = 'd81d0000-0000-4000-8000-000000000001')
  and not exists (
    select 1 from public.website_concept_promotion_commands
    where idempotency_key = 'd8230000-0000-4000-8000-000000000009'
  ),
  'injected post-update failure rolls back context, concept, workspace, and command'
);
set local session_replication_role = replica;
delete from public.website_work_context_promotion_events
where promotion_event_id = 'd8240000-0000-4000-8000-000000000001';
set local session_replication_role = origin;

create temporary table promotion_runtime_result as
select public.promote_website_concept_v1(
  'd8100000-0000-4000-8000-000000000001',
  'd81c0000-0000-4000-8000-000000000001', 7,
  'd8230000-0000-4000-8000-000000000004'
) as result;
select is((select result->>'outcome' from promotion_runtime_result), 'PROMOTED',
  'owner AAL2 promotes the Website context');
select is((select result->>'project_id' from promotion_runtime_result),
  'd81a0000-0000-4000-8000-000000000001',
  'promotion resolves the accepted-quotation project server-side');
select ok(
  (select phase = 'OFFICIAL_PROJECT' and revision = 8
     and project_id = 'd81a0000-0000-4000-8000-000000000001'
   from public.website_work_contexts
   where website_work_context_id = 'd81c0000-0000-4000-8000-000000000001')
  and (select concept_status = 'PROMOTED'
     and promoted_project_id = 'd81a0000-0000-4000-8000-000000000001'
   from public.website_concepts
   where concept_id = 'd81b0000-0000-4000-8000-000000000001'),
  'context and concept transition together exactly once'
);
select ok(
  (select project_id = 'd81a0000-0000-4000-8000-000000000001'
     and binding_revision = 3
      and repository_provider = 'GITHUB'
      and repository_owner = 'fixture-owner'
      and repository_name = 'fixture-repository'
      and repository_external_id = 1369000001
      and repository_node_id = 'R_promotion_continuity'
      and repository_visibility = 'private'
      and repository_state = 'BOUND'
      and starter_source = 'lorenzo-web-solutions/lws-website-starter'
      and starter_version = '1.0.0'
      and starter_commit_sha = repeat('9', 40)
      and repository_marker_commit_sha = repeat('8', 40)
      and last_commit_sha = repeat('a', 40)
   from public.website_execution_workspaces
   where website_workspace_id = 'd81d0000-0000-4000-8000-000000000001')
  and exists (select 1 from public.website_requirements_boards where requirements_board_id = 'd81e0000-0000-4000-8000-000000000001' and revision = 5)
  and exists (select 1 from public.website_requirements where requirement_id = 'd81f0000-0000-4000-8000-000000000001' and revision = 2)
  and exists (select 1 from public.website_requirement_events where event_id = 'd8200000-0000-4000-8000-000000000001')
  and exists (select 1 from public.website_requirement_verifications where verification_id = 'd8220000-0000-4000-8000-000000000001' and binding_revision = 3),
  'repository identity, commits, Project Files authority, board, evidence, and history survive promotion'
);
select is(
  (select count(*) from public.website_work_context_promotion_events
   where website_work_context_id = 'd81c0000-0000-4000-8000-000000000001'),
  1::bigint, 'successful promotion emits one audit event'
);
select is(
  (public.promote_website_concept_v1(
    'd8100000-0000-4000-8000-000000000001',
    'd81c0000-0000-4000-8000-000000000001', 7,
    'd8230000-0000-4000-8000-000000000004')->>'replayed')::boolean,
  true, 'same key and fingerprint replays the stored result'
);
select throws_ok(
  $$select public.promote_website_concept_v1(
    'd8100000-0000-4000-8000-000000000001',
    'd81c0000-0000-4000-8000-000000000001', 8,
    'd8230000-0000-4000-8000-000000000004')$$,
  'P0001', 'WEBSITE_CONCEPT_PROMOTION_IDEMPOTENCY_CONFLICT',
  'same key with a different fingerprint conflicts'
);
select throws_ok(
  $$select public.promote_website_concept_v1(
    'd8100000-0000-4000-8000-000000000001',
    'd81c0000-0000-4000-8000-000000000001', 8,
    'd8230000-0000-4000-8000-000000000005')$$,
  'P0001', 'WEBSITE_CONCEPT_ALREADY_PROMOTED',
  'a new key cannot promote an already promoted context'
);
select throws_ok(
  $$select public.promote_website_concept_v1(
    'd8100002-0000-4000-8000-000000000002',
    'd81c0000-0000-4000-8000-000000000001', 8,
    'd8230000-0000-4000-8000-000000000006')$$,
  'P0001', 'WEBSITE_PROMOTION_CONTEXT_MISMATCH',
  'cross-dossier promotion is rejected before project selection'
);
select is(
  (select count(*) from public.website_concept_promotion_commands
   where idempotency_key in (
     'd8230000-0000-4000-8000-000000000005',
     'd8230000-0000-4000-8000-000000000006'
   )),
  0::bigint, 'definitive promotion failures roll back command and event writes'
);

select * from finish();
rollback;
