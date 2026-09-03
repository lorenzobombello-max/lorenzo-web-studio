begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(34);

select has_function(
  'public', 'can_purge_dossier_v1', array['uuid'],
  'dossier purge eligibility RPC exists'
);
select has_function(
  'public', 'purge_dossier_v1', array['uuid','text','uuid'],
  'dossier purge RPC exists'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.purge_dossier_v1(uuid,text,uuid)', 'execute'
  ) and not has_function_privilege(
    'anon', 'public.purge_dossier_v1(uuid,text,uuid)', 'execute'
  ) and not has_function_privilege(
    'service_role', 'public.purge_dossier_v1(uuid,text,uuid)', 'execute'
  ),
  'only authenticated callers can enter dossier purge authority'
);
select ok(
  not has_table_privilege(
    'authenticated', 'lws_internal.dossier_identity_anchors',
    'select,insert,update,delete'
  ) and not has_table_privilege(
    'authenticated', 'lws_internal.intake_identity_anchors',
    'select,insert,update,delete'
  ) and not has_table_privilege(
    'authenticated', 'lws_internal.dossier_purge_tombstones',
    'select,insert,update,delete'
  ) and not has_table_privilege(
    'authenticated', 'lws_internal.dossier_preofficial_quotation_tombstones',
    'select,insert,update,delete'
  ),
  'authenticated callers have no direct purge authority table privileges'
);
select ok(
  (select count(*) = 4
   from pg_class as relation
   join pg_namespace as namespace on namespace.oid = relation.relnamespace
   where namespace.nspname = 'lws_internal'
     and relation.relname in (
       'dossier_identity_anchors', 'intake_identity_anchors',
       'dossier_purge_tombstones', 'dossier_preofficial_quotation_tombstones'
     )
     and relation.relrowsecurity
     and relation.relforcerowsecurity),
  'all purge authority tables enforce RLS'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.prepare_quotation_issuance_unlocked_v1(uuid,smallint,smallint,text,uuid,text,text)',
    'execute'
  ) and not has_function_privilege(
    'service_role',
    'public.prepare_quotation_issuance_unlocked_v2(uuid,smallint,smallint,text,uuid,text,text)',
    'execute'
  ),
  'callers cannot bypass shared dossier lock through unlocked issuance helpers'
);
select ok(
  pg_get_functiondef(
    'public.prepare_quotation_issuance_v1(uuid,smallint,smallint,text,uuid,text,text)'::regprocedure
  ) like '%pg_advisory_xact_lock%DOSSIER:%'
  and pg_get_functiondef(
    'public.prepare_quotation_issuance_v2(uuid,smallint,smallint,text,uuid,text,text)'::regprocedure
  ) like '%pg_advisory_xact_lock%DOSSIER:%',
  'both issuance entry points bind the shared dossier transaction lock'
);

insert into auth.users (id, email) values
  ('fa000000-0000-4000-8000-000000000001', 'purge-owner@example.test'),
  ('fa000000-0000-4000-8000-000000000002', 'purge-admin@example.test');

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status, revoked_at
) values
  ('fa010000-0000-4000-8000-000000000001', 'fa000000-0000-4000-8000-000000000001', 'Purge Owner', 'owner', 'ACTIVE', null),
  ('fa010000-0000-4000-8000-000000000002', 'fa000000-0000-4000-8000-000000000002', 'Purge Admin', 'admin', 'ACTIVE', null);

insert into public.quote_requests (
  id, request_kind, website_type, budget, timing, created_at,
  name, email, description, privacy_consent, status
) values (
  'd3752349-3489-4c19-bd03-f0cc076b5607', 'website', 'business',
  'EUR 3.200 t/m EUR 6.000', 'flexible',
  '2026-08-18T06:40:00.735922Z', 'Purge authority fixture',
  'purge-fixture@example.test', 'Local purge validation fixture.', true, 'approved'
);

insert into lws_internal.operator_dossier_assignment_events (
  quote_request_id, event_type, previous_assignee_operator_id,
  new_assignee_operator_id, actor_operator_id, previous_revision,
  resulting_revision, idempotency_key, request_fingerprint
) values (
  'd3752349-3489-4c19-bd03-f0cc076b5607', 'ASSIGNED', null,
  'fa010000-0000-4000-8000-000000000001',
  'fa010000-0000-4000-8000-000000000001', 0, 1,
  'fa040000-0000-4000-8000-000000000001', repeat('1', 64)
);
insert into lws_internal.operator_dossier_assignment_commands (
  idempotency_key, quote_request_id, actor_operator_id,
  assignee_operator_id, expected_revision, request_fingerprint, result_payload
) values (
  'fa040000-0000-4000-8000-000000000002',
  'd3752349-3489-4c19-bd03-f0cc076b5607',
  'fa010000-0000-4000-8000-000000000001',
  'fa010000-0000-4000-8000-000000000001', 0, repeat('2', 64), '{}'::jsonb
);

select set_config('request.jwt.claim.sub', 'fa000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.purge_dossier_v1(
    'd3752349-3489-4c19-bd03-f0cc076b5607', 'Permanent cleanup',
    'fa020000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'OWNER_REQUIRED', 'non-owner operator cannot purge a dossier'
);

select set_config('request.jwt.claim.sub', 'fa000000-0000-4000-8000-000000000001', true);
select is(
  public.can_purge_dossier_v1('d3752349-3489-4c19-bd03-f0cc076b5607')->>'can_purge',
  'false', 'active Website dossier must enter Trash before purge eligibility'
);

create function pg_temp.trash_dossier(
  p_quote_request_id uuid,
  p_idempotency_key uuid
)
returns void
language plpgsql
as $$
declare
  v_capability uuid;
begin
  v_capability := public.issue_operator_dossier_lifecycle_edge_capability_v1(
    auth.uid(), p_quote_request_id, 'TRASHED', 0,
    p_idempotency_key, 'Trash before permanent cleanup'
  );
  perform public.execute_operator_dossier_lifecycle_command_v1(
    p_quote_request_id, 'TRASHED', 0,
    p_idempotency_key, 'Trash before permanent cleanup',
    v_capability
  );
end;
$$;

select pg_temp.trash_dossier(
  'd3752349-3489-4c19-bd03-f0cc076b5607',
  'fa030000-0000-4000-8000-000000000001'
);
select is(
  (select state from lws_internal.operator_dossier_states
   where quote_request_id = 'd3752349-3489-4c19-bd03-f0cc076b5607'),
  'TRASHED', 'clean Website dossier enters persistent Trash before purge'
);
select is(
  public.can_purge_dossier_v1('d3752349-3489-4c19-bd03-f0cc076b5607')->>'can_purge',
  'true', 'trashed clean Website dossier is purge eligible'
);

select is(
  public.purge_dossier_v1(
    'd3752349-3489-4c19-bd03-f0cc076b5607', '  Permanent cleanup  ',
    'fa020000-0000-4000-8000-000000000001'
  )->>'replayed',
  'false', 'owner purges eligible dossier once'
);
select is(
  (select count(*)::integer from public.quote_requests
   where id = 'd3752349-3489-4c19-bd03-f0cc076b5607'),
  0, 'purge physically deletes the dossier root'
);
select is(
  (select count(*)::integer from lws_internal.operator_dossier_states
   where quote_request_id = 'd3752349-3489-4c19-bd03-f0cc076b5607'),
  0, 'purge physically deletes mutable dossier state'
);
select is(
  (select count(*)::integer
   from lws_internal.dossier_identity_anchors
   where quote_request_id = 'd3752349-3489-4c19-bd03-f0cc076b5607'),
  1, 'purge retains permanent dossier identity anchor'
);
select ok(
  (select count(*) = 1 from lws_internal.operator_dossier_assignments
   where quote_request_id = 'd3752349-3489-4c19-bd03-f0cc076b5607')
  and
  (select count(*) = 1 from lws_internal.operator_dossier_assignment_events
   where quote_request_id = 'd3752349-3489-4c19-bd03-f0cc076b5607')
  and
  (select count(*) = 1 from lws_internal.operator_dossier_assignment_commands
   where quote_request_id = 'd3752349-3489-4c19-bd03-f0cc076b5607'),
  'purge retains assignment state and append-only ledgers through dossier anchor'
);
select ok(
  (select purge_reason = 'Permanent cleanup'
      and original_dossier_state = 'TRASHED'
      and original_state_before_trash = 'ACTIVE'
   from lws_internal.dossier_purge_tombstones
   where quote_request_id = 'd3752349-3489-4c19-bd03-f0cc076b5607'),
  'trash-first purge retains normalized non-PII tombstone evidence'
);
select throws_ok(
  $$update lws_internal.dossier_purge_tombstones
    set purge_reason = 'Tampered'
    where quote_request_id = 'd3752349-3489-4c19-bd03-f0cc076b5607'$$,
  '55000', 'DOSSIER_PURGE_AUTHORITY_IMMUTABLE',
  'purge tombstone is immutable'
);
select is(
  public.purge_dossier_v1(
    'd3752349-3489-4c19-bd03-f0cc076b5607', 'Permanent cleanup',
    'fa020000-0000-4000-8000-000000000001'
  )->>'replayed',
  'true', 'exact purge replay is idempotent after root deletion'
);
select throws_ok(
  $$select public.purge_dossier_v1(
    'd3752349-3489-4c19-bd03-f0cc076b5607', 'Changed reason',
    'fa020000-0000-4000-8000-000000000001'
  )$$,
  'P0001', 'DOSSIER_ALREADY_PURGED', 'changed replay is rejected'
);

insert into public.quote_requests (
  id, request_kind, website_type, budget, timing, created_at,
  name, email, description, privacy_consent, status
) values (
  '19877689-7c72-4ad4-9a7c-7b9459b22ea1', 'website', 'business',
  'Meer dan EUR 6.000', 'flexible', '2026-08-08T14:54:51.783217Z',
  'Purge intake fixture', 'purge-intake@example.test',
  'Local intake purge validation fixture.', true, 'approved'
);
insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_state, lifecycle_revision, started_at, submitted_at, confirmation,
  created_at
) values (
  'fa050000-0000-4000-8000-000000000001',
  '19877689-7c72-4ad4-9a7c-7b9459b22ea1', 'submitted', repeat('3', 64),
  clock_timestamp() + interval '1 day', 'CANCELLED', 1,
  clock_timestamp(), '2026-08-08T15:55:13.497810Z', true,
  '2026-08-08T14:55:00Z'
);
insert into public.quote_request_intake_lifecycle_events (
  intake_id, event_type, previous_access_state, new_access_state,
  previous_expires_at, new_expires_at, actor_operator_id, reason,
  idempotency_key, request_fingerprint, evidence
) values (
  'fa050000-0000-4000-8000-000000000001', 'CANCELLED', 'ACTIVE', 'CANCELLED',
  '2099-08-30T12:00:00Z', '2099-08-30T12:00:00Z',
  'fa010000-0000-4000-8000-000000000001', 'Customer cancelled intake',
  'fa060000-0000-4000-8000-000000000001', repeat('4', 64), '{}'::jsonb
);

select throws_ok(
  $$select public.purge_dossier_v1(
    '19877689-7c72-4ad4-9a7c-7b9459b22ea1', '   ',
    'fa020000-0000-4000-8000-000000000002'
  )$$,
  '22023', 'INVALID_DOSSIER_PURGE_REQUEST', 'purge requires a meaningful reason'
);
select lives_ok(
  $$select pg_temp.trash_dossier(
    '19877689-7c72-4ad4-9a7c-7b9459b22ea1',
    'fa030000-0000-4000-8000-000000000002'
  )$$,
  'dossier with terminal intake can enter persistent trash'
);
select is(
  public.purge_dossier_v1(
    '19877689-7c72-4ad4-9a7c-7b9459b22ea1', 'Remove intake dossier',
    'fa020000-0000-4000-8000-000000000002'
  )->>'replayed',
  'false', 'owner purges dossier with intake'
);
select is(
  (select count(*)::integer from public.quote_request_intakes
   where id = 'fa050000-0000-4000-8000-000000000001'),
  0, 'purge physically deletes intake data'
);
select is(
  (select count(*)::integer from lws_internal.intake_identity_anchors
   where intake_id = 'fa050000-0000-4000-8000-000000000001'),
  1, 'purge retains permanent intake identity anchor'
);
select is(
  (select count(*)::integer from public.quote_request_intake_lifecycle_events
   where intake_id = 'fa050000-0000-4000-8000-000000000001'),
  1, 'purge retains immutable intake lifecycle event through intake anchor'
);

create function pg_temp.create_preofficial_quotation_fixture(
  p_quote_request_id uuid,
  p_created_at timestamptz,
  p_submitted_at timestamptz
)
returns uuid
language plpgsql
as $$
declare
  v_intake_id uuid := gen_random_uuid();
  v_snapshot_id uuid := gen_random_uuid();
  v_draft_id uuid := gen_random_uuid();
  v_approval_id uuid := gen_random_uuid();
  v_payload jsonb;
begin
  insert into public.quote_requests (
    id, request_kind, created_at, name, email, website_type, budget,
    timing, description, privacy_consent, status
  ) values (
    p_quote_request_id, 'website', p_created_at, 'Pre-official fixture',
    'preofficial@example.test', 'business', 'EUR 3.200 t/m EUR 6.000',
    'flexible', 'Local pre-official purge fixture.', true, 'approved'
  );
  insert into public.quote_request_intakes (
    id, quote_request_id, status, access_token_hash, access_token_expires_at,
    started_at, submitted_at, confirmation, admin_access_token_hash,
    admin_access_token_expires_at
  ) values (
    v_intake_id, p_quote_request_id, 'submitted', repeat('1', 64),
    clock_timestamp() + interval '1 day', p_created_at, p_submitted_at, true,
    repeat('f', 64), clock_timestamp() + interval '1 day'
  );
  insert into public.quote_request_pricing_snapshots (
    id, intake_id, snapshot_contract_version, config_version, config_hash,
    normalized_evidence, calculation, package_advice, budget_evaluation
  ) values (
    v_snapshot_id, v_intake_id, 2, '1.0.0', repeat('1', 64),
    '{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}',
    '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":10000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":10000,"quantity":1,"knownMinimumContributionMinor":10000}]}',
    '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}',
    '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}'
  );
  insert into public.quote_request_pricing_snapshot_integrity (
    snapshot_id, algorithm_version, key_id, mac
  ) values (v_snapshot_id, 'hmac-sha256-v1', 'v1', repeat('a', 64));

  v_payload := jsonb_build_object(
    'contract_version', 1,
    'source_quote_request_id', p_quote_request_id::text,
    'source_intake_id', v_intake_id::text,
    'pricing_snapshot', jsonb_build_object(
      'snapshot_id', v_snapshot_id::text,
      'snapshot_contract_version', 2,
      'integrity_algorithm_version', 'hmac-sha256-v1',
      'integrity_key_id', 'v1', 'integrity_mac', repeat('a', 64)
    ),
    'currency', 'EUR',
    'line_items', jsonb_build_array(jsonb_build_object(
      'line_id', 'website', 'sequence', 1,
      'product_or_service_code', 'WEBSITE', 'description', 'Websiteontwikkeling',
      'quantity', 1, 'unit', 'project', 'unit_price_minor', 10000,
      'discount_minor', 0, 'vat_treatment', 'STANDARD', 'vat_rate', 21,
      'line_net_amount_minor', 10000, 'cost_type', 'ONE_TIME'
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
      'source_quote_request_id', p_quote_request_id::text,
      'source_intake_id', v_intake_id::text, 'customer_id', null,
      'legal_name', 'Pre-official Fixture', 'contact_name', null,
      'email', 'preofficial@example.test', 'address_line_1', 'Teststraat 1',
      'address_line_2', null, 'postal_code', '9000', 'city', 'Gent',
      'country_code', 'BE', 'enterprise_number', null, 'vat_number', null,
      'source_fields', jsonb_build_object('legal_name', 'fixture'),
      'snapshot_sha256', repeat('b', 64)
    ),
    'project_scope', jsonb_build_object(
      'project_id', null, 'project_title', 'Pre-official website',
      'project_type', 'website', 'scope_summary', 'Local fixture',
      'requested_languages', jsonb_build_array('nl'), 'included_page_count', 1,
      'features', '[]'::jsonb, 'copywriting', null, 'seo', null,
      'hosting', null, 'maintenance', null, 'exclusions', '[]'::jsonb,
      'assumptions', '[]'::jsonb, 'indicative_timing', null,
      'source_intake_id', v_intake_id::text,
      'source_pricing_snapshot_id', v_snapshot_id::text,
      'snapshot_sha256', repeat('c', 64)
    ),
    'vat_approval', jsonb_build_object(
      'vat_treatment', 'STANDARD', 'vat_rate', 21,
      'vat_decision_source', 'accountant', 'vat_approved_by', 'accountant:test',
      'vat_approved_at', '2026-08-15T12:00:00Z'
    ),
    'payment_schedule', jsonb_build_object(
      'schedule_id', 'schedule-1', 'milestones', jsonb_build_array(jsonb_build_object(
        'sequence', 1, 'label', 'Volledige betaling', 'percentage', 100,
        'amount_minor', null, 'trigger', 'invoice', 'due_terms_days', 30,
        'recurring_cycle', null
      )), 'approved_by', 'commercial:test',
      'approved_at', '2026-08-15T12:00:00Z'
    ),
    'validity', jsonb_build_object(
      'valid_from', '2026-08-15', 'valid_until', '2026-09-14',
      'validity_days', 30, 'approved_by', 'commercial:test',
      'approved_at', '2026-08-15T12:00:00Z'
    ),
    'legal_references', jsonb_build_object(
      'terms_reference', 'terms-v1', 'terms_version', '1.0.0',
      'terms_sha256', repeat('d', 64), 'terms_status', 'APPROVED',
      'agreement_template_reference', null, 'agreement_template_version', null,
      'agreement_template_sha256', null
    )
  );
  insert into public.quote_request_quotation_approval_drafts (
    id, quote_request_id, intake_id, pricing_snapshot_id, contract_version,
    approval_payload, payload_fingerprint, idempotency_key, created_by
  ) values (
    v_draft_id, p_quote_request_id, v_intake_id, v_snapshot_id, 1,
    v_payload, public.quotation_approval_payload_sha256_v1(v_payload),
    gen_random_uuid(), 'test:purge-authority'
  );
  insert into public.quote_request_quotation_approvals (
    id, draft_id, quote_request_id, intake_id, pricing_snapshot_id,
    contract_version, approval_version, approved_payload, payload_sha256,
    approved_by, approved_at
  ) values (
    v_approval_id, v_draft_id, p_quote_request_id, v_intake_id, v_snapshot_id,
    1, 1, v_payload, public.quotation_approval_payload_sha256_v1(v_payload),
    'test:purge-authority', clock_timestamp()
  );
  insert into public.quote_request_quotation_approval_integrity (
    approval_id, algorithm_version, key_id, mac
  ) values (v_approval_id, 'hmac-sha256-v1', 'v1', repeat('e', 64));
  return v_approval_id;
end;
$$;

create temp table preofficial_approvals (
  fixture text primary key,
  quote_request_id uuid not null,
  approval_id uuid not null
) on commit drop;

insert into preofficial_approvals
select 'PURGE', '388e8887-8b20-4300-b1e8-183718fe6b57',
  pg_temp.create_preofficial_quotation_fixture(
    '388e8887-8b20-4300-b1e8-183718fe6b57',
    '2026-08-18T04:38:02.741551Z', '2026-08-18T09:21:18.906106Z'
  );
update lws_internal.operator_dossier_states
set state = 'TRASHED', revision = revision + 1,
    state_before_trash = 'ACTIVE', deletion_eligible_at = null,
    updated_at = clock_timestamp()
where quote_request_id = '388e8887-8b20-4300-b1e8-183718fe6b57';

select is(
  public.can_purge_dossier_v1('388e8887-8b20-4300-b1e8-183718fe6b57')->>'can_purge',
  'true', 'pre-official approval chain remains purge eligible'
);
select is(
  public.purge_dossier_v1(
    '388e8887-8b20-4300-b1e8-183718fe6b57', 'Remove pre-official quotation',
    'fa070000-0000-4000-8000-000000000001'
  )->>'replayed',
  'false', 'owner purges pre-official approval chain'
);
select ok(
  (select count(*) = 2
   from lws_internal.dossier_preofficial_quotation_tombstones
   where quote_request_id = '388e8887-8b20-4300-b1e8-183718fe6b57')
  and not exists (
    select 1 from public.quote_request_quotation_approval_drafts
    where quote_request_id = '388e8887-8b20-4300-b1e8-183718fe6b57'
  ) and not exists (
    select 1 from public.quote_request_quotation_approvals
    where quote_request_id = '388e8887-8b20-4300-b1e8-183718fe6b57'
  ) and not exists (
    select 1 from public.quote_requests
    where id = '388e8887-8b20-4300-b1e8-183718fe6b57'
  ),
  'purge replaces pre-official PII quotation records with hash evidence'
);

insert into preofficial_approvals
select 'ISSUED', '620b3fa5-2e6b-4439-9d22-741b8541fbdf',
  pg_temp.create_preofficial_quotation_fixture(
    '620b3fa5-2e6b-4439-9d22-741b8541fbdf',
    '2026-08-18T06:41:37.328379Z', '2026-08-18T06:51:23.983507Z'
  );
select * from public.prepare_quotation_issuance_v2(
  (select approval_id from preofficial_approvals where fixture = 'ISSUED'),
  2099::smallint, 1::smallint, repeat('5', 64),
  'fa080000-0000-4000-8000-000000000001', repeat('f', 64),
  'test:purge-authority'
);
select pg_temp.trash_dossier(
  '620b3fa5-2e6b-4439-9d22-741b8541fbdf',
  'fa030000-0000-4000-8000-000000000003'
);
select is(
  public.can_purge_dossier_v1('620b3fa5-2e6b-4439-9d22-741b8541fbdf')->>'reason',
  'OFFICIAL_QUOTATION_EXISTS', 'numbered PREPARED quotation blocks trashed purge eligibility'
);
select throws_ok(
  $$select public.purge_dossier_v1(
    '620b3fa5-2e6b-4439-9d22-741b8541fbdf', 'Must remain protected',
    'fa070000-0000-4000-8000-000000000002'
  )$$,
  '55000', 'OFFICIAL_QUOTATION_EXISTS', 'purge rejects numbered quotation'
);
select ok(
  exists (
    select 1 from public.quote_requests
    where id = '620b3fa5-2e6b-4439-9d22-741b8541fbdf'
  ) and exists (
    select 1
    from public.quote_request_quotation_issuances as issuance
    join preofficial_approvals as fixture on fixture.approval_id = issuance.approval_id
    where fixture.fixture = 'ISSUED' and issuance.status = 'PREPARED'
  ) and not exists (
    select 1 from lws_internal.dossier_purge_tombstones
    where quote_request_id = '620b3fa5-2e6b-4439-9d22-741b8541fbdf'
  ),
  'blocked purge leaves official quotation dossier wholly intact'
);

insert into public.quote_requests (
  id, request_kind, sdf_package, created_at, name, email, description,
  privacy_consent, status
) values (
  'fa090000-0000-4000-8000-000000000001', 'slimme_documentenflow', 'start',
  clock_timestamp(), 'SDF isolation fixture', 'sdf-isolation@example.test',
  'Website authority isolation fixture.', true, 'approved'
);
select is(
  public.can_purge_dossier_v1('fa090000-0000-4000-8000-000000000001')->>'reason',
  'WRONG_PRODUCT_KIND', 'Website eligibility rejects an active SDF dossier'
);
select throws_ok(
  $$select public.purge_dossier_v1(
    'fa090000-0000-4000-8000-000000000001', 'Must remain isolated',
    'fa090000-0000-4000-8000-000000000002'
  )$$,
  '55000', 'WRONG_PRODUCT_KIND', 'Website executor rejects an active SDF dossier'
);

select * from finish();
rollback;