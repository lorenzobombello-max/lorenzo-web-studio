begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

create function pg_temp.set_recovery_claims_v1(p_subject uuid, p_aal text default 'aal2')
returns void
language sql
as $$
  select set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_subject, 'role', 'authenticated', 'aal', p_aal)::text,
    true
  )::text;
$$;

select has_table('lws_internal', 'security_recovery_policy', 'private recovery policy exists');
select has_table('lws_internal', 'security_recovery_records', 'private recovery record ledger exists');
select has_table('lws_internal', 'security_restore_requests', 'private restore request ledger exists');
select has_table('lws_internal', 'security_compensating_events', 'private compensating event chain exists');

select results_eq(
  $$
    select action_code, recovery_class
    from lws_internal.security_recovery_policy
    order by action_code
  $$,
  $$
    select * from (values
      ('appoint_operations_manager_v1', 'COMPENSATABLE'),
      ('approve_document_inbox_item_v1', 'COMPENSATABLE'),
      ('archive_project', 'RESTORABLE'),
      ('authorize_final_transfer', 'IRREVERSIBLE'),
      ('cancel_intake', 'COMPENSATABLE'),
      ('confirm_payment', 'COMPENSATABLE'),
      ('create_dossier_document_access', 'IRREVERSIBLE'),
      ('create_recruitment_cv_access', 'IRREVERSIBLE'),
      ('decide_operator_leave_request_v1', 'COMPENSATABLE'),
      ('export_application_dossier_pdf', 'IRREVERSIBLE'),
      ('invite_recruitment_test_candidate', 'COMPENSATABLE'),
      ('issue_and_deliver_approved_quotation', 'IRREVERSIBLE'),
      ('permanently_delete_pending_intake_v1', 'IRREVERSIBLE'),
      ('process_document_inbox_item_v1', 'COMPENSATABLE'),
      ('purge_dossier_v1', 'IRREVERSIBLE'),
      ('purge_sdf_dossier_v1', 'IRREVERSIBLE'),
      ('reconcile_payment', 'COMPENSATABLE'),
      ('record_delivery', 'IRREVERSIBLE'),
      ('record_payment_evidence', 'COMPENSATABLE'),
      ('reject_document_inbox_item_v1', 'COMPENSATABLE'),
      ('reject_recruitment_open_application', 'COMPENSATABLE'),
      ('release_project', 'IRREVERSIBLE'),
      ('revoke_operations_manager_v1', 'COMPENSATABLE'),
      ('revoke_operator_workspace_v1', 'COMPENSATABLE'),
      ('set_commercial_operator_status_v1', 'COMPENSATABLE')
    ) as expected(action_code, recovery_class)
    order by action_code
  $$,
  'every P0-3A HIGH/CRITICAL action has one explicit recovery class'
);

select is(
  (select count(*)::integer
   from lws_internal.security_recovery_policy as recovery
   join lws_internal.security_action_policy as action using (action_code)
   where action.risk_level in ('HIGH', 'CRITICAL')),
  (select count(*)::integer
   from lws_internal.security_action_policy
   where risk_level in ('HIGH', 'CRITICAL')),
  'recovery classification exactly covers the central HIGH/CRITICAL policy registry'
);
select results_eq(
  $$
    select action_code, minimum_pre_execution_retention_seconds,
      requires_trash_first, requires_dual_control_before_execution, requires_backup_dependency
    from lws_internal.security_recovery_policy
    where action_code in (
      'purge_dossier_v1', 'purge_sdf_dossier_v1', 'permanently_delete_pending_intake_v1'
    )
    order by action_code
  $$,
  $$
    values
      ('permanently_delete_pending_intake_v1', 604800, true, true, true),
      ('purge_dossier_v1', 2592000, true, true, true),
      ('purge_sdf_dossier_v1', 2592000, true, true, true)
  $$,
  'physical purge policies require cooling-off, dual control, and backup dependency'
);
select is(
  (select count(*)::integer from lws_internal.security_recovery_policy
   where recovery_class = 'RESTORABLE'),
  1,
  'only the conservatively verified archive action is directly restorable'
);
select ok(
  (select bool_and(requires_dual_control_before_execution)
   from lws_internal.security_recovery_policy
   where recovery_class = 'IRREVERSIBLE'),
  'every irreversible action requires dual control before future execution wiring'
);

insert into auth.users(id, email) values
  ('f6000000-0000-4000-8000-000000000001', 'recovery-owner@example.test'),
  ('f6000000-0000-4000-8000-000000000002', 'recovery-manager@example.test'),
  ('f6000000-0000-4000-8000-000000000003', 'recovery-operator@example.test'),
  ('f6000000-0000-4000-8000-000000000004', 'recovery-disabled@example.test');

set local session_replication_role = replica;
insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('f6010000-0000-4000-8000-000000000001', 'f6000000-0000-4000-8000-000000000001', 'Synthetic Recovery Owner', 'owner', 'ACTIVE'),
  ('f6010000-0000-4000-8000-000000000002', 'f6000000-0000-4000-8000-000000000002', 'Synthetic Recovery Manager', 'operations_manager', 'ACTIVE'),
  ('f6010000-0000-4000-8000-000000000003', 'f6000000-0000-4000-8000-000000000003', 'Synthetic Recovery Operator', 'operator', 'ACTIVE'),
  ('f6010000-0000-4000-8000-000000000004', 'f6000000-0000-4000-8000-000000000004', 'Synthetic Recovery Disabled', 'operator', 'DISABLED');
insert into public.commercial_projects(
  project_id, customer_id, quotation_issuance_id, acceptance_id,
  accepted_total_minor, currency, m1_minor, m2_minor, m3_minor,
  current_state, revision
) values (
  'f6100000-0000-4000-8000-000000000001',
  'f6110000-0000-4000-8000-000000000001',
  'f6120000-0000-4000-8000-000000000001',
  'f6130000-0000-4000-8000-000000000001',
  10000, 'EUR', 4000, 4000, 2000, 'ARCHIVED', 1
);
set local session_replication_role = origin;

create temporary table recovery_test_context(
  label text primary key,
  identifier uuid not null
);

select set_config('request.jwt.claims', jsonb_build_object('role', 'service_role', 'aal', 'aal2')::text, true);
select throws_ok(
  $$select lws_internal.record_security_recovery_v1(
    'archive_project', 'f6100000-0000-4000-8000-000000000001', repeat('0', 64), '{}'::jsonb
  )$$,
  '42501', 'HUMAN_JWT_REQUIRED',
  'service-role context without an end-user subject cannot choose a recovery actor'
);

select pg_temp.set_recovery_claims_v1('f6000000-0000-4000-8000-000000000001');
insert into recovery_test_context(label, identifier)
select 'restorable', lws_internal.record_security_recovery_v1(
  'archive_project',
  'f6100000-0000-4000-8000-000000000001',
  repeat('a', 64),
  jsonb_build_object('source', 'p0-3d-test')
);

select is(
  (select actor_auth_user_id::text from lws_internal.security_recovery_records
   where recovery_record_id = (select identifier from recovery_test_context where label = 'restorable')),
  'f6000000-0000-4000-8000-000000000001',
  'recovery record actor is derived from auth.uid()'
);
select is(
  (select reason_code from lws_internal.evaluate_security_recovery_v1(
    (select identifier from recovery_test_context where label = 'restorable'),
    'archive_project', repeat('a', 64)
  )),
  'SECURITY_RECOVERY_ELIGIBLE',
  'restorable action is eligible inside retention while primary data remains archived'
);
select is(
  (select reason_code from lws_internal.evaluate_security_recovery_v1(
    (select identifier from recovery_test_context where label = 'restorable'),
    'confirm_payment', repeat('a', 64)
  )),
  'SECURITY_RECOVERY_BINDING_MISMATCH',
  'wrong action binding is denied'
);
select is(
  (select reason_code from lws_internal.evaluate_security_recovery_v1(
    (select identifier from recovery_test_context where label = 'restorable'),
    'archive_project', repeat('b', 64)
  )),
  'SECURITY_RECOVERY_BINDING_MISMATCH',
  'wrong object fingerprint is denied'
);

select pg_temp.set_recovery_claims_v1('f6000000-0000-4000-8000-000000000001', 'aal1');
select throws_ok(
  format(
    'select * from lws_internal.evaluate_security_recovery_v1(%L, %L, %L)',
    (select identifier from recovery_test_context where label = 'restorable'),
    'archive_project', repeat('a', 64)
  ),
  '42501', 'AAL2_REQUIRED',
  'AAL1 is denied for restore evaluation'
);
select pg_temp.set_recovery_claims_v1('f6000000-0000-4000-8000-000000000003');
select throws_ok(
  format(
    'select * from lws_internal.evaluate_security_recovery_v1(%L, %L, %L)',
    (select identifier from recovery_test_context where label = 'restorable'),
    'archive_project', repeat('a', 64)
  ),
  '42501', 'SECURITY_RECOVERY_AUTHORITY_REQUIRED',
  'ordinary operator lacks restore authority'
);
select pg_temp.set_recovery_claims_v1('f6000000-0000-4000-8000-000000000004');
select throws_ok(
  $$select * from lws_internal.record_security_recovery_v1(
    'archive_project', 'f6100000-0000-4000-8000-000000000001', repeat('b', 64), '{}'::jsonb
  )$$,
  '42501', 'OPERATOR_DISABLED',
  'disabled operator fails closed before recording recovery metadata'
);

select pg_temp.set_recovery_claims_v1('f6000000-0000-4000-8000-000000000001');
select throws_ok(
  $$select lws_internal.record_security_recovery_v1(
    'archive_project', 'f6100000-0000-4000-8000-000000000099', repeat('b', 64), '{}'::jsonb
  )$$,
  '55000', 'SECURITY_RECOVERY_RETAINED_SOURCE_REQUIRED',
  'restorable record requires genuine retained primary data'
);

create temporary table expired_recovery_record as
with inserted as (
  insert into lws_internal.security_recovery_records (
    action_code, recovery_class, object_reference, object_reference_fingerprint,
    actor_auth_user_id, recovery_state, created_at, expires_at
  ) values (
    'archive_project', 'RESTORABLE', 'f6100000-0000-4000-8000-000000000001', repeat('c', 64),
    'f6000000-0000-4000-8000-000000000001', 'AVAILABLE',
    clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour'
  )
  returning recovery_record_id
)
select recovery_record_id from inserted;

select is(
  (select reason_code from lws_internal.evaluate_security_recovery_v1(
    (select recovery_record_id from expired_recovery_record),
    'archive_project', repeat('c', 64)
  )),
  'SECURITY_RECOVERY_RETENTION_EXPIRED',
  'expired recovery record is denied outside retention'
);

insert into recovery_test_context(label, identifier)
select 'irreversible', lws_internal.record_security_recovery_v1(
  'purge_dossier_v1', 'f6200000-0000-4000-8000-000000000001', repeat('d', 64), '{}'::jsonb
);
select is(
  (select reason_code from lws_internal.evaluate_security_recovery_v1(
    (select identifier from recovery_test_context where label = 'irreversible'),
    'purge_dossier_v1', repeat('d', 64)
  )),
  'SECURITY_RECOVERY_IRREVERSIBLE',
  'irreversible purge never offers direct restore'
);

set local session_replication_role = replica;
insert into lws_internal.dossier_identity_anchors(
  quote_request_id, application_reference, original_created_at,
  record_classification, request_kind
) values (
  'f6200000-0000-4000-8000-000000000001', 'LWS-AAN-2099-9001',
  clock_timestamp() - interval '31 days', 'internal_e2e', 'website'
);
insert into lws_internal.dossier_purge_tombstones(
  quote_request_id, purged_at, purged_by_operator_id, purge_reason,
  original_request_status, original_dossier_state, original_state_before_trash,
  record_classification, request_kind, contract_version,
  idempotency_key, request_fingerprint
) values (
  'f6200000-0000-4000-8000-000000000001', clock_timestamp(),
  'f6010000-0000-4000-8000-000000000001', 'Synthetic tombstone-only proof',
  'submitted', 'TRASHED', 'ACTIVE', 'internal_e2e', 'website', 1,
  'f6210000-0000-4000-8000-000000000001', repeat('e', 64)
);
set local session_replication_role = origin;
select ok(
  not lws_internal.security_retained_source_available_v1(
    'purge_dossier_v1', 'f6200000-0000-4000-8000-000000000001'
  ),
  'a purge tombstone alone is never treated as a restore source'
);

set local session_replication_role = replica;
insert into lws_internal.operator_dossier_states(
  quote_request_id, state, revision, state_before_trash,
  deletion_eligible_at, created_at, updated_at
) values
  ('f6400000-0000-4000-8000-000000000002', 'ACTIVE', 0, null, null,
    clock_timestamp() - interval '40 days', clock_timestamp() - interval '40 days'),
  ('f6400000-0000-4000-8000-000000000003', 'TRASHED', 1, 'ACTIVE', null,
    clock_timestamp() - interval '40 days', clock_timestamp() - interval '29 days'),
  ('f6400000-0000-4000-8000-000000000004', 'TRASHED', 1, 'ACTIVE', null,
    clock_timestamp() - interval '40 days', clock_timestamp() - interval '29 days'),
  ('f6400000-0000-4000-8000-000000000005', 'TRASHED', 1, 'ARCHIVED', null,
    clock_timestamp() - interval '40 days', clock_timestamp() - interval '31 days'),
  ('f6400000-0000-4000-8000-000000000006', 'TRASHED', 1, 'ACTIVE', null,
    clock_timestamp() - interval '40 days', clock_timestamp() - interval '31 days');
insert into lws_internal.operator_dossier_state_events(
  quote_request_id, event_type, previous_state, new_state, state_before_trash,
  previous_revision, new_revision, deletion_eligible_at, actor_operator_id,
  reason, occurred_at, idempotency_key, request_fingerprint
) values
  ('f6400000-0000-4000-8000-000000000003', 'TRASHED', 'ACTIVE', 'TRASHED', 'ACTIVE',
    0, 1, null, 'f6010000-0000-4000-8000-000000000001',
    'Synthetic young website trash', clock_timestamp() - interval '29 days',
    'f6410000-0000-4000-8000-000000000003', repeat('3', 64)),
  ('f6400000-0000-4000-8000-000000000004', 'TRASHED', 'ACTIVE', 'TRASHED', 'ACTIVE',
    0, 1, null, 'f6010000-0000-4000-8000-000000000001',
    'Synthetic young SDF trash', clock_timestamp() - interval '29 days',
    'f6410000-0000-4000-8000-000000000004', repeat('4', 64)),
  ('f6400000-0000-4000-8000-000000000005', 'TRASHED', 'ARCHIVED', 'TRASHED', 'ARCHIVED',
    0, 1, null, 'f6010000-0000-4000-8000-000000000001',
    'Synthetic elapsed website trash', clock_timestamp() - interval '31 days',
    'f6410000-0000-4000-8000-000000000005', repeat('5', 64));
insert into lws_internal.operator_pending_intake_retention(
  intake_id, retention_state, archived_at, archived_by_operator_id, revision, updated_at
) values (
  'f6400000-0000-4000-8000-000000000007', 'ARCHIVED',
  clock_timestamp() - interval '6 days', 'f6010000-0000-4000-8000-000000000001',
  1, clock_timestamp() - interval '6 days'
);
set local session_replication_role = origin;

insert into recovery_test_context(label, identifier)
select fixture.label, lws_internal.record_security_recovery_v1(
  fixture.action_code, fixture.object_reference, fixture.object_fingerprint, '{}'::jsonb
)
from (values
  ('wrong_state', 'purge_dossier_v1', 'f6400000-0000-4000-8000-000000000002'::uuid, repeat('6', 64)),
  ('website_young', 'purge_dossier_v1', 'f6400000-0000-4000-8000-000000000003'::uuid, repeat('7', 64)),
  ('sdf_young', 'purge_sdf_dossier_v1', 'f6400000-0000-4000-8000-000000000004'::uuid, repeat('8', 64)),
  ('website_elapsed', 'purge_dossier_v1', 'f6400000-0000-4000-8000-000000000005'::uuid, repeat('9', 64)),
  ('missing_timestamp', 'purge_dossier_v1', 'f6400000-0000-4000-8000-000000000006'::uuid, repeat('b', 64)),
  ('pending_young', 'permanently_delete_pending_intake_v1', 'f6400000-0000-4000-8000-000000000007'::uuid, repeat('c', 64))
) as fixture(label, action_code, object_reference, object_fingerprint);

select is(
  (select reason_code from lws_internal.evaluate_security_destructive_execution_v1(
    (select identifier from recovery_test_context where label = 'irreversible'),
    'purge_dossier_v1', 'f6200000-0000-4000-8000-000000000001', repeat('d', 64)
  )),
  'SECURITY_DESTRUCTIVE_TRASH_FIRST_REQUIRED',
  'purge without current trash state is denied even when a tombstone exists'
);
select is(
  (select reason_code from lws_internal.evaluate_security_destructive_execution_v1(
    (select identifier from recovery_test_context where label = 'wrong_state'),
    'purge_dossier_v1', 'f6400000-0000-4000-8000-000000000002', repeat('6', 64)
  )),
  'SECURITY_DESTRUCTIVE_TRASH_FIRST_REQUIRED',
  'purge with ACTIVE lifecycle state is denied'
);
select is(
  (select reason_code from lws_internal.evaluate_security_destructive_execution_v1(
    (select identifier from recovery_test_context where label = 'website_young'),
    'purge_dossier_v1', 'f6400000-0000-4000-8000-000000000003', repeat('7', 64)
  )),
  'SECURITY_DESTRUCTIVE_RETENTION_ACTIVE',
  'website purge before 30 days is denied'
);
select is(
  (select reason_code from lws_internal.evaluate_security_destructive_execution_v1(
    (select identifier from recovery_test_context where label = 'sdf_young'),
    'purge_sdf_dossier_v1', 'f6400000-0000-4000-8000-000000000004', repeat('8', 64)
  )),
  'SECURITY_DESTRUCTIVE_RETENTION_ACTIVE',
  'SDF purge before 30 days is denied'
);
select is(
  (select reason_code from lws_internal.evaluate_security_destructive_execution_v1(
    (select identifier from recovery_test_context where label = 'pending_young'),
    'permanently_delete_pending_intake_v1', 'f6400000-0000-4000-8000-000000000007', repeat('c', 64)
  )),
  'SECURITY_DESTRUCTIVE_RETENTION_ACTIVE',
  'pending-intake delete before 7 days is denied'
);
select is(
  (select reason_code from lws_internal.evaluate_security_destructive_execution_v1(
    (select identifier from recovery_test_context where label = 'missing_timestamp'),
    'purge_dossier_v1', 'f6400000-0000-4000-8000-000000000006', repeat('b', 64)
  )),
  'SECURITY_DESTRUCTIVE_TRASH_TIMESTAMP_REQUIRED',
  'TRASHED state without matching server lifecycle timestamp is denied'
);
select ok(
  (select retention_satisfied and trash_first_satisfied and not backup_dependency_satisfied
   from lws_internal.evaluate_security_destructive_execution_v1(
    (select identifier from recovery_test_context where label = 'website_elapsed'),
    'purge_dossier_v1', 'f6400000-0000-4000-8000-000000000005', repeat('9', 64)
  )),
  'elapsed 30-day lifecycle satisfies trash and retention but not backup dependency'
);
select is(
  (select reason_code from lws_internal.evaluate_security_destructive_execution_v1(
    (select identifier from recovery_test_context where label = 'website_elapsed'),
    'purge_dossier_v1', 'f6400000-0000-4000-8000-000000000005', repeat('9', 64)
  )),
  'SECURITY_DESTRUCTIVE_DUAL_CONTROL_REQUIRED',
  'elapsed retention cannot bypass P0-3B dual control'
);

insert into lws_internal.security_action_approvals (
  id, action_code, domain, object_reference_fingerprint,
  requested_by, requested_at, request_fingerprint, expires_at,
  status, approved_by, approved_at
) values (
  'f6500000-0000-4000-8000-000000000001',
  'purge_dossier_v1', 'PURGE', repeat('9', 64),
  'f6000000-0000-4000-8000-000000000001', clock_timestamp(), repeat('a', 64),
  clock_timestamp() + interval '15 minutes', 'APPROVED',
  'f6000000-0000-4000-8000-000000000002', clock_timestamp()
);
select is(
  (select reason_code from lws_internal.evaluate_security_destructive_execution_v1(
    (select identifier from recovery_test_context where label = 'website_elapsed'),
    'purge_dossier_v1', 'f6400000-0000-4000-8000-000000000005', repeat('9', 64)
  )),
  'BACKUP_EVIDENCE_UNAVAILABLE',
  'eligible lifecycle and approval still fail closed without authoritative backup evidence'
);
select ok(
  not (select allowed from lws_internal.evaluate_security_destructive_execution_v1(
    (select identifier from recovery_test_context where label = 'website_elapsed'),
    'purge_dossier_v1', 'f6400000-0000-4000-8000-000000000005', repeat('9', 64)
  ))
  and (select dual_control_satisfied from lws_internal.evaluate_security_destructive_execution_v1(
    (select identifier from recovery_test_context where label = 'website_elapsed'),
    'purge_dossier_v1', 'f6400000-0000-4000-8000-000000000005', repeat('9', 64)
  ))
  and not (select backup_dependency_satisfied from lws_internal.evaluate_security_destructive_execution_v1(
    (select identifier from recovery_test_context where label = 'website_elapsed'),
    'purge_dossier_v1', 'f6400000-0000-4000-8000-000000000005', repeat('9', 64)
  )),
  'backup dependency is mandatory and cannot become eligible without authoritative evidence'
);
select ok(
  pg_get_function_arguments('lws_internal.evaluate_security_destructive_execution_v1(uuid,text,uuid,text)'::regprocedure)
    !~ '(timestamp|retention|trash|backup|actor|approved_by)',
  'caller cannot supply lifecycle timestamps, retention status, backup status, actor, or approver'
);

select pg_temp.set_recovery_claims_v1('f6000000-0000-4000-8000-000000000003');
select throws_ok(
  format(
    'select * from lws_internal.evaluate_security_destructive_execution_v1(%L, %L, %L, %L)',
    (select identifier from recovery_test_context where label = 'website_elapsed'),
    'purge_dossier_v1', 'f6400000-0000-4000-8000-000000000005', repeat('9', 64)
  ),
  '42501', 'SECURITY_DESTRUCTIVE_EXECUTION_OWNER_REQUIRED',
  'non-owner cannot evaluate destructive execution eligibility'
);
select pg_temp.set_recovery_claims_v1('f6000000-0000-4000-8000-000000000001', 'aal1');
select throws_ok(
  format(
    'select * from lws_internal.evaluate_security_destructive_execution_v1(%L, %L, %L, %L)',
    (select identifier from recovery_test_context where label = 'website_elapsed'),
    'purge_dossier_v1', 'f6400000-0000-4000-8000-000000000005', repeat('9', 64)
  ),
  '42501', 'AAL2_REQUIRED',
  'AAL1 owner cannot evaluate destructive execution eligibility'
);
select pg_temp.set_recovery_claims_v1('f6000000-0000-4000-8000-000000000001');
select ok(
  exists (select 1 from lws_internal.operator_dossier_states where quote_request_id = 'f6400000-0000-4000-8000-000000000005')
  and exists (select 1 from lws_internal.operator_pending_intake_retention where intake_id = 'f6400000-0000-4000-8000-000000000007'),
  'destructive evaluator performs no business delete'
);

insert into recovery_test_context(label, identifier)
select 'compensatable', lws_internal.record_security_recovery_v1(
  'confirm_payment', 'f6300000-0000-4000-8000-000000000001', repeat('f', 64), '{}'::jsonb
);
select is(
  (select reason_code from lws_internal.evaluate_security_recovery_v1(
    (select identifier from recovery_test_context where label = 'compensatable'),
    'confirm_payment', repeat('f', 64)
  )),
  'SECURITY_RECOVERY_COMPENSATION_REQUIRED',
  'compensatable action denies direct restore'
);

insert into lws_internal.security_action_approvals (
  id, action_code, domain, object_reference_fingerprint,
  requested_by, requested_at, request_fingerprint, expires_at,
  status, approved_by, approved_at
) values (
  'f6310000-0000-4000-8000-000000000001',
  'confirm_payment', 'FINANCE_FINALIZATION', repeat('f', 64),
  'f6000000-0000-4000-8000-000000000001', clock_timestamp(), repeat('1', 64),
  clock_timestamp() + interval '15 minutes', 'APPROVED',
  'f6000000-0000-4000-8000-000000000002', clock_timestamp()
);
create temporary table original_recovery_snapshot as
select recovery_record_id, recovery_state, actor_auth_user_id, created_at
from lws_internal.security_recovery_records
where recovery_record_id = (select identifier from recovery_test_context where label = 'compensatable');

insert into recovery_test_context(label, identifier)
select 'compensation', lws_internal.record_security_compensating_event_v1(
  (select identifier from recovery_test_context where label = 'compensatable'),
  'reverse_payment_confirmation',
  'f6310000-0000-4000-8000-000000000001', repeat('2', 64), null,
  jsonb_build_object('source', 'p0-3d-test')
);
select is(
  (select actor_auth_user_id::text || ':' || approved_by_auth_user_id::text
   from lws_internal.security_compensating_events
   where compensating_event_id = (select identifier from recovery_test_context where label = 'compensation')),
  'f6000000-0000-4000-8000-000000000001:f6000000-0000-4000-8000-000000000002',
  'compensating event derives actor and approver from authenticated and approved records'
);
select ok(
  (select row(recovery_state, actor_auth_user_id, created_at)::text
   from lws_internal.security_recovery_records
   where recovery_record_id = (select identifier from recovery_test_context where label = 'compensatable'))
  =
  (select row(recovery_state, actor_auth_user_id, created_at)::text
   from original_recovery_snapshot),
  'compensating event does not mutate the original recovery record'
);
select throws_ok(
  $$update lws_internal.security_compensating_events
    set safe_metadata = '{}'::jsonb
    where compensating_event_id = (select identifier from recovery_test_context where label = 'compensation')$$,
  '55000', 'SECURITY_CONTROL_EVENT_APPEND_ONLY',
  'compensating event chain is append-only'
);

insert into recovery_test_context(label, identifier)
select 'restore_request', lws_internal.request_security_restore_v1(
  (select identifier from recovery_test_context where label = 'restorable'),
  'archive_project', repeat('a', 64), repeat('3', 64),
  jsonb_build_object('source', 'p0-3d-test')
);
select is(
  (select requested_by::text from lws_internal.security_restore_requests
   where restore_request_id = (select identifier from recovery_test_context where label = 'restore_request')),
  'f6000000-0000-4000-8000-000000000001',
  'restore request actor is derived from auth.uid()'
);
select throws_ok(
  format(
    'select lws_internal.request_security_restore_v1(%L, %L, %L, %L, %L::jsonb)',
    (select identifier from recovery_test_context where label = 'restorable'),
    'archive_project', repeat('a', 64), repeat('4', 64), '{}'
  ),
  '55000', 'SECURITY_RESTORE_REQUEST_DUPLICATE',
  'duplicate restore request fails closed'
);
select throws_ok(
  format(
    'select lws_internal.approve_security_restore_v1(%L, %L, %L)',
    (select identifier from recovery_test_context where label = 'restore_request'),
    'archive_project', repeat('a', 64)
  ),
  '42501', 'SECURITY_RESTORE_SELF_APPROVAL_FORBIDDEN',
  'restore requester cannot self-approve'
);

select pg_temp.set_recovery_claims_v1('f6000000-0000-4000-8000-000000000002');
select ok(
  lws_internal.approve_security_restore_v1(
    (select identifier from recovery_test_context where label = 'restore_request'),
    'archive_project', repeat('a', 64)
  ),
  'independent AAL2 Operations Manager can approve a bound restore request'
);
select is(
  (select approved_by::text from lws_internal.security_restore_requests
   where restore_request_id = (select identifier from recovery_test_context where label = 'restore_request')),
  'f6000000-0000-4000-8000-000000000002',
  'restore approval attribution is server-bound'
);
select throws_ok(
  $$update lws_internal.security_control_events
    set metadata = '{}'::jsonb
    where event_type = 'RESTORE_APPROVED'$$,
  '55000', 'SECURITY_CONTROL_EVENT_APPEND_ONLY',
  'restore audit event is append-only'
);

select ok(
  not has_table_privilege('anon', 'lws_internal.security_recovery_records', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'lws_internal.security_recovery_records', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'lws_internal.security_recovery_records', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'lws_internal.security_compensating_events', 'select,insert,update,delete'),
  'recovery and compensation tables expose no runtime-role data privileges'
);
select ok(
  not has_function_privilege('public', 'lws_internal.evaluate_security_recovery_v1(uuid,text,text)', 'execute')
  and not has_function_privilege('anon', 'lws_internal.evaluate_security_recovery_v1(uuid,text,text)', 'execute')
  and not has_function_privilege('public', 'lws_internal.evaluate_security_destructive_execution_v1(uuid,text,uuid,text)', 'execute')
  and not has_function_privilege('anon', 'lws_internal.evaluate_security_destructive_execution_v1(uuid,text,uuid,text)', 'execute')
  and not has_function_privilege('authenticated', 'lws_internal.evaluate_security_destructive_execution_v1(uuid,text,uuid,text)', 'execute')
  and not has_function_privilege('service_role', 'lws_internal.evaluate_security_destructive_execution_v1(uuid,text,uuid,text)', 'execute')
  and not has_function_privilege('authenticated', 'lws_internal.request_security_restore_v1(uuid,text,text,text,jsonb)', 'execute')
  and not has_function_privilege('service_role', 'lws_internal.record_security_compensating_event_v1(uuid,text,uuid,text,uuid,jsonb)', 'execute'),
  'recovery functions expose no PUBLIC, anon, frontend, or service-role execution'
);
select ok(
  not exists (
    select 1
    from pg_proc
    where oid in (
      'lws_internal.record_security_recovery_v1(text,uuid,text,jsonb)'::regprocedure,
      'lws_internal.evaluate_security_recovery_v1(uuid,text,text)'::regprocedure,
      'lws_internal.request_security_restore_v1(uuid,text,text,text,jsonb)'::regprocedure,
      'lws_internal.approve_security_restore_v1(uuid,text,text)'::regprocedure,
      'lws_internal.record_security_compensating_event_v1(uuid,text,uuid,text,uuid,jsonb)'::regprocedure
    )
      and pg_get_function_arguments(oid) ~ 'p_(actor|approved_by)_auth_user_id'
  ),
  'privileged recovery contracts expose no caller-controlled actor or approver UUID'
);
select ok(
  not exists (
    select 1 from pg_proc
    where oid in (
      'lws_internal.assert_security_recovery_aal2_v1()'::regprocedure,
      'lws_internal.security_retained_source_available_v1(text,uuid)'::regprocedure,
      'lws_internal.evaluate_security_destructive_execution_v1(uuid,text,uuid,text)'::regprocedure,
      'lws_internal.record_security_recovery_v1(text,uuid,text,jsonb)'::regprocedure,
      'lws_internal.evaluate_security_recovery_v1(uuid,text,text)'::regprocedure,
      'lws_internal.request_security_restore_v1(uuid,text,text,text,jsonb)'::regprocedure,
      'lws_internal.approve_security_restore_v1(uuid,text,text)'::regprocedure,
      'lws_internal.record_security_compensating_event_v1(uuid,text,uuid,text,uuid,jsonb)'::regprocedure
    )
      and not (
        proconfig @> array['search_path=lws_internal, public, auth, pg_catalog']
        or proconfig @> array['search_path=public, pg_catalog']
        or proconfig @> array['search_path=auth, pg_catalog']
      )
  ),
  'all recovery SECURITY DEFINER functions have fixed search paths'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'lws_internal'
      and table_name in (
        'security_recovery_policy', 'security_recovery_records',
        'security_restore_requests', 'security_compensating_events'
      )
      and column_name in ('display_name', 'email', 'payload', 'document', 'token', 'secret')
  ),
  'recovery foundation stores no display-name authority, payloads, documents, tokens, or secrets'
);
select ok(
  not exists (
    select 1 from lws_internal.security_recovery_policy as recovery
    join lws_internal.security_action_policy as action using (action_code)
    where recovery.recovery_class = 'RESTORABLE'
      and (
        not recovery.requires_restore_approval
        or not recovery.restore_requires_aal2
        or not recovery.requires_retained_source
        or (action.requires_aal2 and not recovery.restore_requires_aal2)
      )
  ),
  'restore authority is equal to or stronger than the original action policy'
);

select * from finish();
rollback;