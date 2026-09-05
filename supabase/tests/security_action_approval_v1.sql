begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set local search_path = public, extensions;
select no_plan();

create function pg_temp.set_approval_claims_v1(p_subject uuid, p_aal text)
returns void
language sql
as $$
  select set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_subject, 'role', 'authenticated', 'aal', p_aal)::text,
    true
  )::text;
$$;

create function pg_temp.wait_for_approval_lock_v1(p_backend_pid integer)
returns boolean
language plpgsql
as $$
declare
  v_deadline timestamptz := clock_timestamp() + interval '5 seconds';
begin
  loop
    if exists (
      select 1 from pg_catalog.pg_locks
      where pid = p_backend_pid and not granted
    ) then
      return true;
    end if;
    if clock_timestamp() >= v_deadline then
      return false;
    end if;
  end loop;
end;
$$;

select has_table('lws_internal', 'security_action_approvals', 'private approval request model exists');
select is(
  (select count(*)::integer from lws_internal.security_action_policy
   where action_code = 'permanently_delete_pending_intake'),
  0,
  'legacy pending-intake delete action code is absent'
);
select is(
  (select count(*)::integer from lws_internal.security_action_policy
   where action_code = 'permanently_delete_pending_intake_v1'),
  1,
  'canonical pending-intake delete action code exists exactly once'
);
select is(
  (select requires_dual_control from lws_internal.security_action_policy
   where action_code = 'permanently_delete_pending_intake_v1'),
  true,
  'canonical pending-intake delete action requires dual control'
);
select is(
  (select count(*)::integer from lws_internal.security_action_policy
   where action_code = 'permanently_delete_pending_intake_v1'
     and requires_dual_control),
  1,
  'canonical pending-intake delete action occurs exactly once in dual-control policy registration'
);
select is(
  (select count(*)::integer from lws_internal.security_action_policy where requires_dual_control),
  9,
  'exactly nine actions require dual control'
);
select results_eq(
  $$select action_code from lws_internal.security_action_policy where requires_dual_control order by action_code$$,
  $$values
    ('appoint_operations_manager_v1'::text),
    ('authorize_final_transfer'::text),
    ('confirm_payment'::text),
    ('issue_and_deliver_approved_quotation'::text),
    ('permanently_delete_pending_intake_v1'::text),
    ('purge_dossier_v1'::text),
    ('purge_sdf_dossier_v1'::text),
    ('release_project'::text),
    ('set_commercial_operator_status_v1'::text)
  $$,
  'the exact nine audited action codes are registered'
);

insert into auth.users(id, email) values
  ('f4000000-0000-4000-8000-000000000001', 'approval-owner@example.test'),
  ('f4000000-0000-4000-8000-000000000002', 'approval-manager@example.test'),
  ('f4000000-0000-4000-8000-000000000003', 'approval-operator@example.test');
set local session_replication_role = replica;
insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('f4010000-0000-4000-8000-000000000001', 'f4000000-0000-4000-8000-000000000001', 'Synthetic Approval Owner', 'owner', 'ACTIVE'),
  ('f4010000-0000-4000-8000-000000000002', 'f4000000-0000-4000-8000-000000000002', 'Synthetic Approval Manager', 'operations_manager', 'ACTIVE'),
  ('f4010000-0000-4000-8000-000000000003', 'f4000000-0000-4000-8000-000000000003', 'Synthetic Approval Operator', 'operator', 'ACTIVE');
set local session_replication_role = origin;

select pg_temp.set_approval_claims_v1('f4000000-0000-4000-8000-000000000001', 'aal2');
select lives_ok(
  $$select public.request_security_action_approval_v1(
    'purge_dossier_v1', repeat('a', 64), 900,
    '{"source":"pgtap","correlation_id":"primary"}'::jsonb
  )$$,
  'authorized AAL2 actor can request approval for a registered dual-control action'
);

create temporary table primary_approval as
select id, action_code, object_reference_fingerprint::text, request_fingerprint::text
from lws_internal.security_action_approvals
where requested_by = 'f4000000-0000-4000-8000-000000000001'
  and object_reference_fingerprint = repeat('a', 64)
order by requested_at desc
limit 1;

select throws_ok(
  format(
    'select public.approve_security_action_v1(%L, %L, %L, %L)',
    id, action_code, object_reference_fingerprint, request_fingerprint
  ),
  '42501',
  'SECURITY_APPROVAL_SELF_APPROVAL_FORBIDDEN',
  'request actor cannot approve its own request'
)
from primary_approval;

select pg_temp.set_approval_claims_v1('f4000000-0000-4000-8000-000000000002', 'aal1');
select throws_ok(
  format(
    'select public.approve_security_action_v1(%L, %L, %L, %L)',
    id, action_code, object_reference_fingerprint, request_fingerprint
  ),
  '42501', 'AAL2_REQUIRED', 'AAL1 approver is denied'
)
from primary_approval;

select pg_temp.set_approval_claims_v1('f4000000-0000-4000-8000-000000000003', 'aal2');
select throws_ok(
  format(
    'select public.approve_security_action_v1(%L, %L, %L, %L)',
    id, action_code, object_reference_fingerprint, request_fingerprint
  ),
  '42501', 'SECURITY_APPROVAL_AUTHORITY_REQUIRED', 'ordinary authenticated operator is denied'
)
from primary_approval;

select pg_temp.set_approval_claims_v1('f4000000-0000-4000-8000-000000000002', 'aal2');
select lives_ok(
  format(
    'select public.approve_security_action_v1(%L, %L, %L, %L)',
    id, action_code, object_reference_fingerprint, request_fingerprint
  ),
  'different authorized AAL2 actor can approve'
)
from primary_approval;
select is(
  (select approved_by::text from lws_internal.security_action_approvals where id = (select id from primary_approval)),
  'f4000000-0000-4000-8000-000000000002',
  'approval authority is stored by UUID rather than display name'
);
select throws_ok(
  format(
    'select public.approve_security_action_v1(%L, %L, %L, %L)',
    id, action_code, object_reference_fingerprint, request_fingerprint
  ),
  '55000', 'SECURITY_APPROVAL_NOT_PENDING', 'duplicate approval is denied'
)
from primary_approval;

select is(
  (select reason_code from lws_internal.evaluate_security_action_approval_v1(
    id, 'purge_sdf_dossier_v1', object_reference_fingerprint, request_fingerprint
  )),
  'SECURITY_APPROVAL_ACTION_MISMATCH',
  'approval cannot be replayed for another action'
)
from primary_approval;
select is(
  (select reason_code from lws_internal.evaluate_security_action_approval_v1(
    id, action_code, repeat('b', 64), request_fingerprint
  )),
  'SECURITY_APPROVAL_OBJECT_MISMATCH',
  'approval cannot be replayed for another object'
)
from primary_approval;
select is(
  (select reason_code from lws_internal.evaluate_security_action_approval_v1(
    id, action_code, object_reference_fingerprint, repeat('c', 64)
  )),
  'SECURITY_APPROVAL_FINGERPRINT_MISMATCH',
  'request fingerprint must match exactly'
)
from primary_approval;
select ok(
  (select allowed from lws_internal.evaluate_security_action_approval_v1(
    id, action_code, object_reference_fingerprint, request_fingerprint
  )),
  'approved request evaluates as allowed before execution'
)
from primary_approval;

select ok(
  (select allowed from lws_internal.claim_security_action_execution_v1(
    id, action_code, object_reference_fingerprint, request_fingerprint
  )),
  'approved request can be claimed exactly once'
)
from primary_approval;
select is(
  (select reason_code from lws_internal.claim_security_action_execution_v1(
    id, action_code, object_reference_fingerprint, request_fingerprint
  )),
  'SECURITY_APPROVAL_ALREADY_EXECUTED',
  'duplicate execution claim is denied'
)
from primary_approval;
select is(
  (select reason_code from lws_internal.evaluate_security_action_approval_v1(
    id, action_code, object_reference_fingerprint, request_fingerprint
  )),
  'SECURITY_APPROVAL_EXECUTED',
  'executed approval is terminal and no longer usable'
)
from primary_approval;

insert into lws_internal.security_action_approvals (
  id, action_code, domain, object_reference_fingerprint, requested_by,
  requested_at, request_fingerprint, expires_at, status,
  rejected_by, rejected_at, rejection_reason
) values
  ('f4100000-0000-4000-8000-000000000001', 'confirm_payment', 'FINANCE_FINALIZATION', repeat('d', 64),
   'f4000000-0000-4000-8000-000000000001', clock_timestamp() - interval '2 hours', repeat('e', 64),
   clock_timestamp() - interval '1 hour', 'PENDING', null, null, null),
  ('f4100000-0000-4000-8000-000000000002', 'release_project', 'FINANCE_FINALIZATION', repeat('f', 64),
   'f4000000-0000-4000-8000-000000000001', clock_timestamp(), repeat('1', 64),
   clock_timestamp() + interval '1 hour', 'REJECTED', 'f4000000-0000-4000-8000-000000000002', clock_timestamp(), 'Synthetic rejection'),
  ('f4100000-0000-4000-8000-000000000003', 'authorize_final_transfer', 'FINANCE_FINALIZATION', repeat('2', 64),
   'f4000000-0000-4000-8000-000000000001', clock_timestamp(), repeat('3', 64),
   clock_timestamp() + interval '1 hour', 'CANCELLED', null, null, null);

select is(
  (select reason_code from lws_internal.evaluate_security_action_approval_v1(
    'f4100000-0000-4000-8000-000000000001', 'confirm_payment', repeat('d', 64), repeat('e', 64)
  )),
  'SECURITY_APPROVAL_EXPIRED',
  'expired request is denied'
);
select is(
  (select reason_code from lws_internal.claim_security_action_execution_v1(
    'f4100000-0000-4000-8000-000000000002', 'release_project', repeat('f', 64), repeat('1', 64)
  )),
  'SECURITY_APPROVAL_REJECTED',
  'rejected request cannot execute'
);
select is(
  (select reason_code from lws_internal.claim_security_action_execution_v1(
    'f4100000-0000-4000-8000-000000000003', 'authorize_final_transfer', repeat('2', 64), repeat('3', 64)
  )),
  'SECURITY_APPROVAL_CANCELLED',
  'cancelled request cannot execute'
);

select pg_temp.set_approval_claims_v1('f4000000-0000-4000-8000-000000000001', 'aal2');
select lives_ok(
  $$select public.request_security_action_approval_v1('release_project', repeat('4', 64), 900, '{"source":"pgtap"}'::jsonb)$$,
  'second approval request is created for rejection coverage'
);
select pg_temp.set_approval_claims_v1('f4000000-0000-4000-8000-000000000002', 'aal2');
select lives_ok(
  format(
    'select public.reject_security_action_v1(%L, %L, %L, %L, %L)',
    id, action_code, object_reference_fingerprint, request_fingerprint, 'Independent reviewer rejects'
  ),
  'authorized second actor can reject with a reason'
)
from lws_internal.security_action_approvals
where object_reference_fingerprint = repeat('4', 64);
select ok(
  exists (
    select 1 from lws_internal.security_control_events
    where event_type = 'APPROVAL_REJECTED'
      and actor_auth_user_id = 'f4000000-0000-4000-8000-000000000002'
  ),
  'rejection emits an append-only UUID-authority audit event'
);
select throws_ok(
  $$update lws_internal.security_control_events set metadata = '{}'::jsonb where event_type like 'APPROVAL_%'$$,
  '55000', 'SECURITY_CONTROL_EVENT_APPEND_ONLY', 'approval audit events remain append-only'
);

select throws_ok(
  $$update lws_internal.security_action_approvals set action_code = 'purge_sdf_dossier_v1' where id = (select id from primary_approval)$$,
  '55000', 'SECURITY_ACTION_APPROVAL_BINDING_IMMUTABLE', 'approval action and object binding is immutable'
);
select throws_ok(
  $$delete from lws_internal.security_action_approvals where id = (select id from primary_approval)$$,
  '55000', 'SECURITY_ACTION_APPROVAL_DELETE_FORBIDDEN', 'approval records cannot be deleted'
);
select throws_ok(
  $$insert into lws_internal.security_action_approvals(
      action_code, domain, object_reference_fingerprint, requested_by,
      request_fingerprint, expires_at, safe_metadata
    ) values (
      'purge_dossier_v1', 'PURGE', repeat('5', 64),
      'f4000000-0000-4000-8000-000000000001', repeat('6', 64),
      clock_timestamp() + interval '15 minutes', '{"payload":"forbidden"}'::jsonb
    )$$,
  '23514', null, 'approval storage rejects unapproved metadata keys'
);

select ok(
  has_function_privilege('authenticated', 'public.request_security_action_approval_v1(text,text,integer,jsonb)', 'execute')
  and has_function_privilege('authenticated', 'public.approve_security_action_v1(uuid,text,text,text)', 'execute')
  and has_function_privilege('authenticated', 'public.reject_security_action_v1(uuid,text,text,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.request_security_action_approval_v1(text,text,integer,jsonb)', 'execute')
  and not has_function_privilege('service_role', 'public.approve_security_action_v1(uuid,text,text,text)', 'execute')
  and has_function_privilege('service_role', 'lws_internal.evaluate_security_action_approval_v1(uuid,text,text,text)', 'execute')
  and has_function_privilege('service_role', 'lws_internal.claim_security_action_execution_v1(uuid,text,text,text)', 'execute')
  and not has_function_privilege('authenticated', 'lws_internal.claim_security_action_execution_v1(uuid,text,text,text)', 'execute'),
  'privileged writes and server-only evaluation expose only intended roles'
);
select ok(
  not exists (
    select 1
    from pg_proc as procedure
    cross join lateral aclexplode(procedure.proacl) as privilege
    where procedure.oid in (
      'public.request_security_action_approval_v1(text,text,integer,jsonb)'::regprocedure,
      'public.approve_security_action_v1(uuid,text,text,text)'::regprocedure,
      'public.reject_security_action_v1(uuid,text,text,text,text)'::regprocedure,
      'lws_internal.evaluate_security_action_approval_v1(uuid,text,text,text)'::regprocedure,
      'lws_internal.claim_security_action_execution_v1(uuid,text,text,text)'::regprocedure
    )
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC has no execute privilege on approval functions'
);
select ok(
  not exists (
    select 1
    from pg_proc
    where oid in (
      'public.request_security_action_approval_v1(text,text,integer,jsonb)'::regprocedure,
      'public.approve_security_action_v1(uuid,text,text,text)'::regprocedure,
      'public.reject_security_action_v1(uuid,text,text,text,text)'::regprocedure,
      'lws_internal.evaluate_security_action_approval_v1(uuid,text,text,text)'::regprocedure,
      'lws_internal.claim_security_action_execution_v1(uuid,text,text,text)'::regprocedure
    )
      and not (
        proconfig @> array['search_path=public, lws_internal, auth, extensions, pg_catalog']
        or proconfig @> array['search_path=public, lws_internal, auth, pg_catalog']
        or proconfig @> array['search_path=lws_internal, pg_catalog']
      )
  ),
  'all SECURITY DEFINER approval functions have fixed search paths'
);

select is(
  extensions.dblink_connect(
    'approval_concurrency_setup',
    'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=approval_concurrency_setup'
  ),
  'OK',
  'concurrency setup connection opens'
);
select lives_ok(
  $test$select extensions.dblink_exec(
    'approval_concurrency_setup',
    $setup$
      insert into auth.users(id, email) values
        ('f4200000-0000-4000-8000-000000000001', 'approval-concurrency-requester@example.test'),
        ('f4200000-0000-4000-8000-000000000002', 'approval-concurrency-approver@example.test');
      insert into lws_internal.security_action_approvals(
        id, action_code, domain, object_reference_fingerprint, requested_by,
        request_fingerprint, expires_at, status, approved_by, approved_at
      ) values (
        'f4210000-0000-4000-8000-000000000001', 'confirm_payment', 'FINANCE_FINALIZATION', repeat('7', 64),
        'f4200000-0000-4000-8000-000000000001', repeat('8', 64), clock_timestamp() + interval '1 hour',
        'APPROVED', 'f4200000-0000-4000-8000-000000000002', clock_timestamp()
      );
    $setup$
  )$test$,
  'committed approved fixture is created outside the pgTAP transaction'
);
select is(extensions.dblink_connect('approval_claim_a', 'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=approval_claim_a'), 'OK', 'first claim connection opens');
select is(extensions.dblink_connect('approval_claim_b', 'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=approval_claim_b'), 'OK', 'second claim connection opens');
create temporary table approval_claim_pids(connection_name text primary key, backend_pid integer not null);
insert into approval_claim_pids
select 'approval_claim_b', backend_pid
from extensions.dblink('approval_claim_b', 'select pg_backend_pid()') as connection(backend_pid integer);
select is(extensions.dblink_exec('approval_claim_a', 'begin'), 'BEGIN', 'first execution claim transaction starts');
select ok(
  (select allowed from extensions.dblink(
    'approval_claim_a',
    $$select * from lws_internal.claim_security_action_execution_v1(
      'f4210000-0000-4000-8000-000000000001', 'confirm_payment', repeat('7', 64), repeat('8', 64)
    )$$
  ) as claim(allowed boolean, approval_status text, reason_code text, approval_id uuid, request_fingerprint text)),
  'first concurrent execution claim succeeds while holding its transaction lock'
);
select ok(
  extensions.dblink_send_query(
    'approval_claim_b',
    $$select * from lws_internal.claim_security_action_execution_v1(
      'f4210000-0000-4000-8000-000000000001', 'confirm_payment', repeat('7', 64), repeat('8', 64)
    )$$
  ) = 1,
  'second concurrent execution claim starts'
);
select ok(
  pg_temp.wait_for_approval_lock_v1((select backend_pid from approval_claim_pids where connection_name = 'approval_claim_b')),
  'second concurrent claim waits on the approval row lock'
);
select is(extensions.dblink_exec('approval_claim_a', 'commit'), 'COMMIT', 'first execution claim commits');
select is(
  (select reason_code from extensions.dblink_get_result('approval_claim_b')
    as claim(allowed boolean, approval_status text, reason_code text, approval_id uuid, request_fingerprint text)),
  'SECURITY_APPROVAL_ALREADY_EXECUTED',
  'second concurrent claim fails closed after the first commit'
);
select extensions.dblink_disconnect('approval_claim_a');
select extensions.dblink_disconnect('approval_claim_b');
select lives_ok(
  $test$select extensions.dblink_exec(
    'approval_concurrency_setup',
    $cleanup$
      set session_replication_role = replica;
      delete from lws_internal.security_control_events
      where metadata ->> 'approval_id' = 'f4210000-0000-4000-8000-000000000001';
      delete from lws_internal.security_action_approvals
      where id = 'f4210000-0000-4000-8000-000000000001';
      delete from auth.users
      where id in ('f4200000-0000-4000-8000-000000000001', 'f4200000-0000-4000-8000-000000000002');
      set session_replication_role = origin;
    $cleanup$
  )$test$,
  'committed concurrency fixtures are removed'
);
select extensions.dblink_disconnect('approval_concurrency_setup');

select * from finish();
rollback;