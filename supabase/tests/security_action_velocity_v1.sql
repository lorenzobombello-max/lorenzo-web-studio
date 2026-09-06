begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set local search_path = public, extensions;
select no_plan();

create function pg_temp.set_velocity_claims_v1(p_subject uuid, p_role text default 'authenticated')
returns void
language sql
as $$
  select set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_subject, 'role', p_role, 'aal', 'aal2')::text,
    true
  )::text;
$$;

create function pg_temp.wait_for_velocity_lock_v1(p_backend_pid integer)
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

select has_table('lws_internal', 'security_action_velocity', 'private velocity ledger exists');
select is(
  (select max_per_hour from lws_internal.security_action_policy where action_code = 'purge_dossier_v1'),
  1,
  'existing PURGE hourly policy remains authoritative'
);
select is(
  (select max_per_day from lws_internal.security_action_policy where action_code = 'purge_dossier_v1'),
  3,
  'existing PURGE daily policy remains authoritative'
);
select is(
  (select row(max_per_hour, max_per_day)::text from lws_internal.security_action_policy where action_code = 'confirm_payment'),
  '(3,10)',
  'existing finance policy retains the audited 3/hour and 10/day limits'
);
select is(
  (select row(max_per_hour, max_per_day)::text from lws_internal.security_action_policy where action_code = 'create_dossier_document_access'),
  '(20,50)',
  'existing sensitive-export policy retains the audited 20/hour and 50/day limits'
);

insert into auth.users(id, email) values
  ('f5000000-0000-4000-8000-000000000001', 'velocity-actor-a@example.test'),
  ('f5000000-0000-4000-8000-000000000002', 'velocity-actor-b@example.test'),
  ('f5000000-0000-4000-8000-000000000003', 'velocity-non-operator@example.test'),
  ('f5000000-0000-4000-8000-000000000004', 'velocity-disabled@example.test'),
  ('f5000000-0000-4000-8000-000000000005', 'velocity-revoked@example.test');
set local session_replication_role = replica;
insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status, revoked_at) values
  ('f5010000-0000-4000-8000-000000000001', 'f5000000-0000-4000-8000-000000000001', 'Synthetic Velocity OP-01', 'owner', 'ACTIVE', null),
  ('f5010000-0000-4000-8000-000000000002', 'f5000000-0000-4000-8000-000000000002', 'Synthetic Velocity OP-02', 'operations_manager', 'ACTIVE', null),
  ('f5010000-0000-4000-8000-000000000004', 'f5000000-0000-4000-8000-000000000004', 'Synthetic Disabled Operator', 'operator', 'DISABLED', null),
  ('f5010000-0000-4000-8000-000000000005', 'f5000000-0000-4000-8000-000000000005', 'Synthetic Revoked Operator', 'operator', 'REVOKED', clock_timestamp());
set local session_replication_role = origin;

select ok(
  to_regprocedure('lws_internal.evaluate_security_action_velocity_v1(uuid,text,text)') is null
  and to_regprocedure('lws_internal.consume_security_action_velocity_v1(uuid,text,text,text,text)') is null
  and to_regprocedure('lws_internal.evaluate_security_action_velocity_v1(text,text)') is not null
  and to_regprocedure('lws_internal.consume_security_action_velocity_v1(text,text,text,text)') is not null,
  'velocity API exposes no caller-controlled actor UUID parameter'
);

select set_config('request.jwt.claims', jsonb_build_object('role', 'service_role', 'aal', 'aal2')::text, true);
select throws_ok(
  $$select * from lws_internal.consume_security_action_velocity_v1(
    'record_payment_evidence', 'FINANCE_FINALIZATION', repeat('0', 64), repeat('0', 64)
  )$$,
  '42501', 'HUMAN_JWT_REQUIRED',
  'service-role context without an end-user subject cannot choose an actor'
);
select pg_temp.set_velocity_claims_v1('f5000000-0000-4000-8000-000000000003');
select throws_ok(
  $$select * from lws_internal.evaluate_security_action_velocity_v1('record_payment_evidence', 'FINANCE_FINALIZATION')$$,
  '42501', 'SECURITY_VELOCITY_OPERATOR_REQUIRED',
  'authenticated non-operator identity is denied'
);
select pg_temp.set_velocity_claims_v1('f5000000-0000-4000-8000-000000000004');
select throws_ok(
  $$select * from lws_internal.consume_security_action_velocity_v1(
    'record_payment_evidence', 'FINANCE_FINALIZATION', repeat('0', 64), repeat('1', 64)
  )$$,
  '42501', 'OPERATOR_DISABLED', 'disabled operator is denied'
);
select pg_temp.set_velocity_claims_v1('f5000000-0000-4000-8000-000000000005');
select throws_ok(
  $$select * from lws_internal.consume_security_action_velocity_v1(
    'record_payment_evidence', 'FINANCE_FINALIZATION', repeat('0', 64), repeat('2', 64)
  )$$,
  '42501', 'OPERATOR_REVOKED', 'revoked operator is denied'
);

select pg_temp.set_velocity_claims_v1('f5000000-0000-4000-8000-000000000001');

update lws_internal.security_action_policy
set max_per_hour = 1, max_per_day = 3, cooldown_seconds = 0
where action_code = 'record_payment_evidence';

select is(
  (select row(current_hour_count, current_day_count)::text
   from lws_internal.evaluate_security_action_velocity_v1(
     'record_payment_evidence', 'FINANCE_FINALIZATION'
   )),
  '(0,0)',
  'initial evaluator counts are zero'
);
select ok(
  (select allowed from lws_internal.consume_security_action_velocity_v1(
    'record_payment_evidence', 'FINANCE_FINALIZATION',
    repeat('a', 64), repeat('1', 64)
  )),
  'first consume is allowed'
);
select is(
  (select count(*)::integer from lws_internal.security_action_velocity
   where actor_auth_user_id = 'f5000000-0000-4000-8000-000000000001'
     and action_code = 'record_payment_evidence'),
  1,
  'allowed consume increments the ledger exactly once'
);
select is(
  (select reason_code from lws_internal.consume_security_action_velocity_v1(
    'record_payment_evidence', 'FINANCE_FINALIZATION',
    repeat('b', 64), repeat('2', 64)
  )),
  'SECURITY_VELOCITY_HOUR_LIMIT_REACHED',
  'next consume is denied at the hourly limit'
);
select is(
  (select count(*)::integer from lws_internal.security_action_velocity
   where actor_auth_user_id = 'f5000000-0000-4000-8000-000000000001'
     and action_code = 'record_payment_evidence'),
  1,
  'denied consume does not increment the ledger'
);
select ok(
  pg_temp.set_velocity_claims_v1('f5000000-0000-4000-8000-000000000002') is null,
  'OP-02 caller context is selected independently'
);
select ok(
  (select allowed from lws_internal.consume_security_action_velocity_v1(
    'record_payment_evidence', 'FINANCE_FINALIZATION',
    repeat('c', 64), repeat('3', 64)
  )),
  'actor A consumption does not affect actor B'
);
select is(
  (select actor_auth_user_id::text from lws_internal.security_action_velocity
   where idempotency_fingerprint = repeat('3', 64)),
  'f5000000-0000-4000-8000-000000000002',
  'OP-02 consume is attributed only to server-derived OP-02 identity'
);
select pg_temp.set_velocity_claims_v1('f5000000-0000-4000-8000-000000000001');
select ok(
  (select allowed from lws_internal.consume_security_action_velocity_v1(
    'reconcile_payment', 'FINANCE_FINALIZATION',
    repeat('d', 64), repeat('4', 64)
  )),
  'action A consumption does not affect action B'
);
select is(
  (select reason_code from lws_internal.evaluate_security_action_velocity_v1(
    'record_payment_evidence', 'PURGE'
  )),
  'SECURITY_VELOCITY_DOMAIN_MISMATCH',
  'action is bound to its policy domain'
);

select set_config('lws_test.original_timezone', current_setting('TimeZone'), true);
select set_config(
  'TimeZone',
  (select (case when hours >= 0 then '+' else '-' end) || lpad(abs(hours)::text, 2, '0') || ':00'
   from (select 12 - extract(hour from clock_timestamp() at time zone 'UTC')::integer as hours) as offset_value),
  true
);
update lws_internal.security_action_policy
set max_per_hour = 1, max_per_day = 1, cooldown_seconds = 0
where action_code = 'archive_project';
insert into lws_internal.security_action_velocity (
  actor_auth_user_id, action_code, domain,
  object_reference_fingerprint, idempotency_fingerprint, consumed_at
) values (
  'f5000000-0000-4000-8000-000000000001', 'archive_project', 'FINANCE_FINALIZATION',
  repeat('e', 64), repeat('5', 64), date_trunc('hour', clock_timestamp()) - interval '1 second'
);
select ok(
  (select consumed_at >= date_trunc('day', clock_timestamp())
     and consumed_at < date_trunc('hour', clock_timestamp())
   from lws_internal.security_action_velocity
   where actor_auth_user_id = 'f5000000-0000-4000-8000-000000000001'
     and action_code = 'archive_project'),
  'daily-limit fixture is inside the current day and outside the current hour'
);
select is(
  (select reason_code from lws_internal.consume_security_action_velocity_v1(
    'archive_project', 'FINANCE_FINALIZATION',
    repeat('f', 64), repeat('6', 64)
  )),
  'SECURITY_VELOCITY_DAY_LIMIT_REACHED',
  'daily limit denies the next consume'
);
select is(
  (select count(*)::integer from lws_internal.security_action_velocity
   where actor_auth_user_id = 'f5000000-0000-4000-8000-000000000001'
     and action_code = 'archive_project'),
  1,
  'daily-limit denial does not increment the ledger'
);

update lws_internal.security_action_policy
set max_per_hour = 10, max_per_day = 30, cooldown_seconds = 60
where action_code = 'cancel_intake';
insert into lws_internal.security_action_velocity (
  actor_auth_user_id, action_code, domain,
  object_reference_fingerprint, idempotency_fingerprint, consumed_at
) values (
  'f5000000-0000-4000-8000-000000000001', 'cancel_intake', 'DOCUMENT_DISPOSITION',
  repeat('1', 64), repeat('7', 64), clock_timestamp() - interval '30 seconds'
);
select is(
  (select reason_code from lws_internal.consume_security_action_velocity_v1(
    'cancel_intake', 'DOCUMENT_DISPOSITION',
    repeat('2', 64), repeat('8', 64)
  )),
  'SECURITY_VELOCITY_COOLDOWN_ACTIVE',
  'active cooldown denies consume'
);
update lws_internal.security_action_velocity
set consumed_at = clock_timestamp() - interval '61 seconds'
where actor_auth_user_id = 'f5000000-0000-4000-8000-000000000001'
  and action_code = 'cancel_intake';
select ok(
  (select allowed from lws_internal.consume_security_action_velocity_v1(
    'cancel_intake', 'DOCUMENT_DISPOSITION',
    repeat('3', 64), repeat('9', 64)
  )),
  'consume is allowed after cooldown expires'
);

select ok(
  (select allowed from lws_internal.consume_security_action_velocity_v1(
    'approve_document_inbox_item_v1', 'DOCUMENT_DISPOSITION',
    repeat('4', 64), repeat('a', 64)
  )),
  'idempotent action is consumed initially'
);
select is(
  (select reason_code from lws_internal.consume_security_action_velocity_v1(
    'approve_document_inbox_item_v1', 'DOCUMENT_DISPOSITION',
    repeat('4', 64), repeat('a', 64)
  )),
  'SECURITY_VELOCITY_REPLAY_DENIED',
  'same idempotency fingerprint cannot consume twice'
);
select is(
  (select count(*)::integer from lws_internal.security_action_velocity
   where actor_auth_user_id = 'f5000000-0000-4000-8000-000000000001'
     and action_code = 'approve_document_inbox_item_v1'),
  1,
  'replay denial preserves a single ledger entry'
);

update lws_internal.security_action_policy
set max_per_hour = 1, max_per_day = 1, cooldown_seconds = 0
where action_code = 'confirm_payment';
insert into lws_internal.security_action_velocity (
  actor_auth_user_id, action_code, domain,
  object_reference_fingerprint, idempotency_fingerprint, consumed_at
) values (
  'f5000000-0000-4000-8000-000000000001', 'confirm_payment', 'FINANCE_FINALIZATION',
  repeat('5', 64), repeat('b', 64), date_trunc('hour', clock_timestamp()) - interval '1 second'
);
select is(
  (select reason_code from lws_internal.consume_security_action_velocity_v1(
    'confirm_payment', 'FINANCE_FINALIZATION',
    repeat('6', 64), repeat('c', 64)
  )),
  'SECURITY_VELOCITY_DAY_LIMIT_REACHED',
  'critical daily overflow is denied'
);
select ok(
  (select is_active from lws_internal.security_kill_switch where scope = 'FINANCE_FINALIZATION'),
  'critical daily overflow activates the existing domain circuit breaker'
);
select is(
  (select activated_by::text from lws_internal.security_kill_switch where scope = 'FINANCE_FINALIZATION'),
  'f5000000-0000-4000-8000-000000000001',
  'circuit breaker attribution uses the server-derived caller UUID'
);
select ok(
  not (select is_active from lws_internal.security_kill_switch where scope = 'GLOBAL'),
  'ordinary velocity overflow never activates GLOBAL'
);
select ok(
  (select allowed from lws_internal.evaluate_security_action_velocity_v1(
    'purge_sdf_dossier_v1', 'PURGE'
  )),
  'domain circuit breaker does not block another domain'
);
select ok(
  exists (
    select 1 from lws_internal.security_control_events
    where event_type = 'VELOCITY_BLOCKED'
      and action_code = 'confirm_payment'
      and metadata ->> 'reason_code' = 'SECURITY_VELOCITY_DAY_LIMIT_REACHED'
  ) and exists (
    select 1 from lws_internal.security_control_events
    where event_type = 'SWITCH_ACTIVATED'
      and domain = 'FINANCE_FINALIZATION'
      and metadata ->> 'source' = 'consume_security_action_velocity_v1'
  ),
  'threshold denial and automatic breaker activation emit safe audit events'
);
select set_config('TimeZone', current_setting('lws_test.original_timezone'), true);
select throws_ok(
  $$update lws_internal.security_control_events set metadata = '{}'::jsonb where event_type in ('VELOCITY_BLOCKED', 'VELOCITY_CONSUMED')$$,
  '55000', 'SECURITY_CONTROL_EVENT_APPEND_ONLY', 'velocity audit events remain append-only'
);

select ok(
  not has_function_privilege('service_role', 'lws_internal.evaluate_security_action_velocity_v1(text,text)', 'execute')
  and not has_function_privilege('service_role', 'lws_internal.consume_security_action_velocity_v1(text,text,text,text)', 'execute')
  and not has_function_privilege('authenticated', 'lws_internal.evaluate_security_action_velocity_v1(text,text)', 'execute')
  and not has_function_privilege('authenticated', 'lws_internal.consume_security_action_velocity_v1(text,text,text,text)', 'execute')
  and not has_function_privilege('anon', 'lws_internal.consume_security_action_velocity_v1(text,text,text,text)', 'execute'),
  'velocity evaluator and consume have no direct role grants'
);
select ok(
  not exists (
    select 1
    from pg_proc as procedure
    cross join lateral aclexplode(procedure.proacl) as privilege
    where procedure.oid in (
      'lws_internal.evaluate_security_action_velocity_v1(text,text)'::regprocedure,
      'lws_internal.consume_security_action_velocity_v1(text,text,text,text)'::regprocedure
    )
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC has no execute privilege on velocity functions'
);
select ok(
  not exists (
    select 1 from pg_proc
    where oid in (
      'lws_internal.evaluate_security_action_velocity_v1(text,text)'::regprocedure,
      'lws_internal.consume_security_action_velocity_v1(text,text,text,text)'::regprocedure,
      'lws_internal.resolve_security_velocity_actor_v1()'::regprocedure
    )
      and not (proconfig @> array['search_path=lws_internal, auth, pg_catalog']
        or proconfig @> array['search_path=lws_internal, pg_catalog'])
  ),
  'velocity SECURITY DEFINER functions have fixed search paths'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'lws_internal'
      and table_name = 'security_action_velocity'
      and column_name like '%display_name%'
  ),
  'velocity authority and state contain no display-name authority'
);

select is(
  extensions.dblink_connect(
    'velocity_concurrency_setup',
    'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=velocity_concurrency_setup'
  ),
  'OK',
  'concurrency setup connection opens'
);
select lives_ok(
  $test$select extensions.dblink_exec(
    'velocity_concurrency_setup',
    $setup$
      insert into auth.users(id, email) values
        ('f5200000-0000-4000-8000-000000000001', 'velocity-concurrency@example.test');
      set session_replication_role = replica;
      insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status)
      values ('f5210000-0000-4000-8000-000000000001', 'f5200000-0000-4000-8000-000000000001', 'Synthetic Concurrent Operator', 'operator', 'ACTIVE');
      set session_replication_role = origin;
    $setup$
  )$test$,
  'committed concurrency actor is created outside the pgTAP transaction'
);
select is(extensions.dblink_connect('velocity_claim_a', 'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=velocity_claim_a'), 'OK', 'first consume connection opens');
select is(extensions.dblink_connect('velocity_claim_b', 'host=host.docker.internal port=54322 dbname=' || current_database() || ' user=postgres password=postgres application_name=velocity_claim_b'), 'OK', 'second consume connection opens');
create temporary table velocity_claim_pids(connection_name text primary key, backend_pid integer not null);
insert into velocity_claim_pids
select 'velocity_claim_b', backend_pid
from extensions.dblink('velocity_claim_b', 'select pg_backend_pid()') as connection(backend_pid integer);
select is(extensions.dblink_exec('velocity_claim_a', 'begin; set request.jwt.claims = ''{"sub":"f5200000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}'''), 'SET', 'first concurrent consume transaction starts with caller identity');
select is(extensions.dblink_exec('velocity_claim_b', 'set request.jwt.claims = ''{"sub":"f5200000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}'''), 'SET', 'second concurrent consume receives the same caller identity');
select ok(
  (select allowed from extensions.dblink(
    'velocity_claim_a',
    $$select * from lws_internal.consume_security_action_velocity_v1(
      'purge_dossier_v1', 'PURGE', repeat('7', 64), repeat('d', 64)
    )$$
  ) as consume(allowed boolean, reason_code text, current_hour_count integer, current_day_count integer, cooldown_remaining_seconds integer, circuit_breaker_active boolean)),
  'first concurrent consume succeeds while holding the actor-action lock'
);
select ok(
  extensions.dblink_send_query(
    'velocity_claim_b',
    $$select * from lws_internal.consume_security_action_velocity_v1(
      'purge_dossier_v1', 'PURGE', repeat('8', 64), repeat('e', 64)
    )$$
  ) = 1,
  'second concurrent consume starts'
);
select ok(
  pg_temp.wait_for_velocity_lock_v1((select backend_pid from velocity_claim_pids where connection_name = 'velocity_claim_b')),
  'second concurrent consume waits on the actor-action advisory lock'
);
select is(extensions.dblink_exec('velocity_claim_a', 'commit'), 'COMMIT', 'first concurrent consume commits');
select ok(
  not (select allowed from extensions.dblink_get_result('velocity_claim_b')
    as consume(allowed boolean, reason_code text, current_hour_count integer, current_day_count integer, cooldown_remaining_seconds integer, circuit_breaker_active boolean)),
  'second concurrent consume fails closed after the first commit'
);
select is(
  (select consumed_count from extensions.dblink(
    'velocity_concurrency_setup',
    $$select count(*)::integer as consumed_count
      from lws_internal.security_action_velocity
      where actor_auth_user_id = 'f5200000-0000-4000-8000-000000000001'
        and action_code = 'purge_dossier_v1'$$
  ) as result(consumed_count integer)),
  1,
  'concurrent consumes cannot exceed the hourly policy limit'
);
select extensions.dblink_disconnect('velocity_claim_a');
select extensions.dblink_disconnect('velocity_claim_b');
select lives_ok(
  $test$select extensions.dblink_exec(
    'velocity_concurrency_setup',
    $cleanup$
      set session_replication_role = replica;
      delete from lws_internal.security_control_events
      where actor_auth_user_id = 'f5200000-0000-4000-8000-000000000001';
      delete from lws_internal.security_action_velocity
      where actor_auth_user_id = 'f5200000-0000-4000-8000-000000000001';
      delete from public.commercial_operators
      where auth_user_id = 'f5200000-0000-4000-8000-000000000001';
      delete from auth.users
      where id = 'f5200000-0000-4000-8000-000000000001';
      set session_replication_role = origin;
    $cleanup$
  )$test$,
  'committed concurrency fixtures are removed'
);
select extensions.dblink_disconnect('velocity_concurrency_setup');

select * from finish();
rollback;