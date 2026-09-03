begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('public', 'workforce_leave_requests', 'leave request authority exists');
select has_table('public', 'workforce_leave_request_events', 'leave request audit authority exists');
select columns_are(
  'public',
  'workforce_leave_requests',
  array[
    'request_id', 'employee_id', 'leave_type', 'start_date', 'end_date', 'day_part',
    'request_status', 'revision', 'employee_note', 'submitted_at', 'decided_at',
    'decided_by_operator_id', 'management_note', 'created_at', 'updated_at'
  ],
  'leave request snapshot has the approved minimal fields plus revision'
);
select columns_are(
  'public',
  'workforce_leave_request_events',
  array[
    'event_id', 'request_id', 'event_type', 'previous_status', 'new_status',
    'actor_operator_id', 'management_note', 'occurred_at'
  ],
  'leave decisions have an append-only event ledger'
);
select has_function(
  'public', 'submit_workforce_leave_request_v1',
  array['uuid', 'uuid', 'date', 'date', 'text', 'text'],
  'self-bound leave submission authority exists'
);
select has_function(
  'public', 'list_workforce_leave_requests_v1', array['uuid', 'date', 'date'],
  'bounded owner leave queue authority exists'
);
select has_function(
  'public', 'decide_workforce_leave_request_v1',
  array['uuid', 'uuid', 'text', 'bigint', 'text', 'text'],
  'optimistic owner decision authority exists'
);
select has_function(
  'public', 'get_operator_leave_requests_v1', array['date', 'date'],
  'authenticated owner Calendar queue wrapper exists'
);
select has_function(
  'public', 'decide_operator_leave_request_v1',
  array['uuid', 'text', 'bigint', 'text', 'text'],
  'authenticated owner Calendar decision wrapper exists'
);
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.workforce_leave_requests'::regclass)
  and (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.workforce_leave_request_events'::regclass),
  'leave authority tables enable and force RLS'
);
select ok(
  not has_table_privilege('anon', 'public.workforce_leave_requests', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.workforce_leave_requests', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.workforce_leave_requests', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.workforce_leave_request_events', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.workforce_leave_request_events', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.workforce_leave_request_events', 'select,insert,update,delete'),
  'runtime roles have no direct leave table authority'
);
select ok(
  has_function_privilege('service_role', 'public.submit_workforce_leave_request_v1(uuid,uuid,date,date,text,text)', 'execute')
  and has_function_privilege('service_role', 'public.list_workforce_leave_requests_v1(uuid,date,date)', 'execute')
  and has_function_privilege('service_role', 'public.decide_workforce_leave_request_v1(uuid,uuid,text,bigint,text,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.submit_workforce_leave_request_v1(uuid,uuid,date,date,text,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.list_workforce_leave_requests_v1(uuid,date,date)', 'execute')
  and not has_function_privilege('authenticated', 'public.decide_workforce_leave_request_v1(uuid,uuid,text,bigint,text,text)', 'execute'),
  'leave RPCs are service-role only'
);
select ok(
  has_function_privilege('authenticated', 'public.get_operator_leave_requests_v1(date,date)', 'execute')
  and has_function_privilege('authenticated', 'public.decide_operator_leave_request_v1(uuid,text,bigint,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.get_operator_leave_requests_v1(date,date)', 'execute')
  and not has_function_privilege('anon', 'public.decide_operator_leave_request_v1(uuid,text,bigint,text,text)', 'execute'),
  'only authenticated callers can reach operator leave wrappers'
);

insert into auth.users(id, email) values
  ('ca100000-0000-4000-8000-000000000001', 'leave-owner@example.test'),
  ('ca100000-0000-4000-8000-000000000002', 'leave-admin@example.test'),
  ('ca100000-0000-4000-8000-000000000011', 'lana@example.test'),
  ('ca100000-0000-4000-8000-000000000012', 'milan@example.test'),
  ('ca100000-0000-4000-8000-000000000013', 'noor@example.test'),
  ('ca100000-0000-4000-8000-000000000014', 'inactive@example.test');

insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('ca200000-0000-4000-8000-000000000001', 'ca100000-0000-4000-8000-000000000001', 'Leave Owner', 'owner', 'ACTIVE'),
  ('ca200000-0000-4000-8000-000000000002', 'ca100000-0000-4000-8000-000000000002', 'Leave Admin', 'admin', 'ACTIVE'),
  ('ca200000-0000-4000-8000-000000000011', 'ca100000-0000-4000-8000-000000000011', 'Lana Account', 'operator', 'ACTIVE'),
  ('ca200000-0000-4000-8000-000000000012', 'ca100000-0000-4000-8000-000000000012', 'Milan Account', 'operator', 'ACTIVE'),
  ('ca200000-0000-4000-8000-000000000013', 'ca100000-0000-4000-8000-000000000013', 'Noor Account', 'operator', 'ACTIVE'),
  ('ca200000-0000-4000-8000-000000000014', 'ca100000-0000-4000-8000-000000000014', 'Inactive Account', 'operator', 'ACTIVE');

insert into public.workforce_employees(
  id, display_name, role_title, team_name, employment_status, start_date, commercial_operator_id
) values
  ('ca300000-0000-4000-8000-000000000011', 'Lana Jacobs', 'Planner', 'Operations', 'ACTIVE', '2026-01-01', 'ca200000-0000-4000-8000-000000000011'),
  ('ca300000-0000-4000-8000-000000000012', 'Milan Peeters', 'Consultant', 'Delivery', 'ACTIVE', '2026-01-01', 'ca200000-0000-4000-8000-000000000012'),
  ('ca300000-0000-4000-8000-000000000013', 'Noor Willems', 'Consultant', 'Delivery', 'ACTIVE', '2026-01-01', 'ca200000-0000-4000-8000-000000000013'),
  ('ca300000-0000-4000-8000-000000000014', 'Inactive Person', null, null, 'INACTIVE', '2026-01-01', 'ca200000-0000-4000-8000-000000000014');

insert into public.employee_identity_reservations(
  employee_identity_id, employee_number, display_name, identity_status, workforce_employee_id, activated_at
) values
  ('ca400000-0000-4000-8000-000000000011', 'LWS-90011', 'Lana Jacobs', 'ACTIVATED', 'ca300000-0000-4000-8000-000000000011', clock_timestamp()),
  ('ca400000-0000-4000-8000-000000000012', 'LWS-90012', 'Milan Peeters', 'ACTIVATED', 'ca300000-0000-4000-8000-000000000012', clock_timestamp()),
  ('ca400000-0000-4000-8000-000000000013', 'LWS-90013', 'Noor Willems', 'ACTIVATED', 'ca300000-0000-4000-8000-000000000013', clock_timestamp()),
  ('ca400000-0000-4000-8000-000000000099', 'LWS-90099', 'Pre Employment Person', 'PRE_EMPLOYMENT', null, null);

set local role service_role;
select lives_ok(
  $$select public.submit_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000011',
    'ca300000-0000-4000-8000-000000000011',
    '2026-09-18', '2026-09-18', 'FULL_DAY', 'Familiedag'
  )$$,
  'active employee can create a self-bound full-day request'
);
select throws_ok(
  $$select public.submit_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000011',
    'ca300000-0000-4000-8000-000000000099',
    '2026-09-18', '2026-09-18', 'FULL_DAY', null
  )$$,
  'P0002', 'LEAVE_EMPLOYEE_NOT_FOUND', 'missing workforce employee is blocked'
);
select throws_ok(
  $$select public.submit_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000011',
    'ca400000-0000-4000-8000-000000000099',
    '2026-09-18', '2026-09-18', 'FULL_DAY', null
  )$$,
  '42501', 'LEAVE_PRE_EMPLOYMENT_NOT_ELIGIBLE', 'pre-employment identity is blocked'
);
select throws_ok(
  $$select public.submit_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000011',
    'ca300000-0000-4000-8000-000000000011',
    '2026-09-19', '2026-09-18', 'FULL_DAY', null
  )$$,
  '22023', 'LEAVE_DATE_RANGE_REVERSED', 'reversed date range is blocked'
);
select throws_ok(
  $$select public.submit_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000011',
    'ca300000-0000-4000-8000-000000000011',
    '2026-09-18', '2026-09-19', 'AM', null
  )$$,
  '22023', 'LEAVE_PARTIAL_DAY_RANGE_INVALID', 'AM across multiple dates is blocked'
);
select throws_ok(
  $$select public.submit_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000011',
    'ca300000-0000-4000-8000-000000000012',
    '2026-09-18', '2026-09-18', 'FULL_DAY', null
  )$$,
  '42501', 'LEAVE_EMPLOYEE_SELF_REQUIRED', 'employee cannot submit for another employee'
);
select throws_ok(
  $$select public.submit_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000014',
    'ca300000-0000-4000-8000-000000000014',
    '2026-09-18', '2026-09-18', 'FULL_DAY', null
  )$$,
  '42501', 'LEAVE_EMPLOYEE_NOT_ACTIVE_FOR_PERIOD', 'inactive employee cannot submit leave'
);
reset role;

create temporary table leave_test_ids(label text primary key, request_id uuid not null);
grant select, insert on leave_test_ids to service_role;
insert into leave_test_ids values
  ('lana_18', (select request_id from public.workforce_leave_requests where employee_id = 'ca300000-0000-4000-8000-000000000011' and start_date = '2026-09-18'));

set local role service_role;
insert into leave_test_ids values
  ('milan_18', (public.submit_workforce_leave_request_v1('ca100000-0000-4000-8000-000000000012', 'ca300000-0000-4000-8000-000000000012', '2026-09-18', '2026-09-18', 'FULL_DAY', null)->>'request_id')::uuid),
  ('noor_18', (public.submit_workforce_leave_request_v1('ca100000-0000-4000-8000-000000000013', 'ca300000-0000-4000-8000-000000000013', '2026-09-18', '2026-09-18', 'AM', null)->>'request_id')::uuid),
  ('waiting_approved', (public.submit_workforce_leave_request_v1('ca100000-0000-4000-8000-000000000011', 'ca300000-0000-4000-8000-000000000011', '2026-09-19', '2026-09-19', 'FULL_DAY', null)->>'request_id')::uuid),
  ('waiting_rejected', (public.submit_workforce_leave_request_v1('ca100000-0000-4000-8000-000000000011', 'ca300000-0000-4000-8000-000000000011', '2026-09-20', '2026-09-20', 'FULL_DAY', null)->>'request_id')::uuid),
  ('direct_rejected', (public.submit_workforce_leave_request_v1('ca100000-0000-4000-8000-000000000011', 'ca300000-0000-4000-8000-000000000011', '2026-09-21', '2026-09-21', 'FULL_DAY', null)->>'request_id')::uuid),
  ('stale', (public.submit_workforce_leave_request_v1('ca100000-0000-4000-8000-000000000011', 'ca300000-0000-4000-8000-000000000011', '2026-09-22', '2026-09-22', 'FULL_DAY', null)->>'request_id')::uuid),
  ('terminal_approved', (public.submit_workforce_leave_request_v1('ca100000-0000-4000-8000-000000000011', 'ca300000-0000-4000-8000-000000000011', '2026-09-23', '2026-09-23', 'FULL_DAY', null)->>'request_id')::uuid),
  ('overlap', (public.submit_workforce_leave_request_v1('ca100000-0000-4000-8000-000000000011', 'ca300000-0000-4000-8000-000000000011', '2026-09-24', '2026-09-24', 'FULL_DAY', null)->>'request_id')::uuid),
  ('duplicate', (public.submit_workforce_leave_request_v1('ca100000-0000-4000-8000-000000000011', 'ca300000-0000-4000-8000-000000000011', '2026-09-25', '2026-09-25', 'FULL_DAY', null)->>'request_id')::uuid),
  ('rollback', (public.submit_workforce_leave_request_v1('ca100000-0000-4000-8000-000000000011', 'ca300000-0000-4000-8000-000000000011', '2026-09-26', '2026-09-26', 'FULL_DAY', null)->>'request_id')::uuid);

select lives_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000001', %L, 'REQUESTED', 1, 'APPROVED', 'Goedgekeurd'
  )$call$, (select request_id from leave_test_ids where label = 'milan_18')),
  'REQUESTED to APPROVED succeeds'
);
select lives_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000001', %L, 'REQUESTED', 1, 'WAITING', 'Bezetting controleren'
  )$call$, (select request_id from leave_test_ids where label = 'noor_18')),
  'REQUESTED to WAITING succeeds'
);
select lives_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000001', %L, 'REQUESTED', 1, 'REJECTED', 'Niet mogelijk'
  )$call$, (select request_id from leave_test_ids where label = 'direct_rejected')),
  'REQUESTED to REJECTED succeeds'
);
select lives_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000001', %L, 'REQUESTED', 1, 'WAITING', null
  )$call$, (select request_id from leave_test_ids where label = 'waiting_approved')),
  'request can first move to WAITING'
);
select lives_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000001', %L, 'WAITING', 2, 'APPROVED', 'Controle afgerond'
  )$call$, (select request_id from leave_test_ids where label = 'waiting_approved')),
  'WAITING to APPROVED succeeds'
);
select lives_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000001', %L, 'REQUESTED', 1, 'WAITING', null
  )$call$, (select request_id from leave_test_ids where label = 'waiting_rejected')),
  'second request can move to WAITING'
);
select lives_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000001', %L, 'WAITING', 2, 'REJECTED', 'Na controle geweigerd'
  )$call$, (select request_id from leave_test_ids where label = 'waiting_rejected')),
  'WAITING to REJECTED succeeds'
);
select throws_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000002', %L, 'REQUESTED', 1, 'APPROVED', null
  )$call$, (select request_id from leave_test_ids where label = 'lana_18')),
  '42501', 'LEAVE_MANAGEMENT_OWNER_REQUIRED', 'non-owner decision is blocked'
);
select lives_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000001', %L, 'REQUESTED', 1, 'WAITING', null
  )$call$, (select request_id from leave_test_ids where label = 'stale')),
  'stale fixture first moves to WAITING'
);
select throws_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000001', %L, 'REQUESTED', 1, 'REJECTED', null
  )$call$, (select request_id from leave_test_ids where label = 'stale')),
  '40001', 'LEAVE_REQUEST_STALE_DECISION', 'stale decision cannot overwrite newer state'
);
select lives_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000001', %L, 'REQUESTED', 1, 'APPROVED', null
  )$call$, (select request_id from leave_test_ids where label = 'terminal_approved')),
  'terminal approval fixture is approved'
);
select throws_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000001', %L, 'APPROVED', 2, 'REJECTED', null
  )$call$, (select request_id from leave_test_ids where label = 'terminal_approved')),
  '55000', 'LEAVE_REQUEST_INVALID_TRANSITION', 'APPROVED to REJECTED is blocked'
);
select throws_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000001', %L, 'REJECTED', 2, 'APPROVED', null
  )$call$, (select request_id from leave_test_ids where label = 'direct_rejected')),
  '55000', 'LEAVE_REQUEST_INVALID_TRANSITION', 'REJECTED to APPROVED is blocked'
);
reset role;

insert into public.workforce_calendar_entries(employee_id, calendar_date, status)
values ('ca300000-0000-4000-8000-000000000011', '2026-09-24', 'WORKED_FULL_DAY');

set local role service_role;
select throws_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000001', %L, 'REQUESTED', 1, 'APPROVED', null
  )$call$, (select request_id from leave_test_ids where label = 'overlap')),
  '23P01', 'LEAVE_REQUEST_CALENDAR_CONFLICT', 'existing definitive attendance blocks approval'
);
select lives_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000001', %L, 'REQUESTED', 1, 'APPROVED', null
  )$call$, (select request_id from leave_test_ids where label = 'duplicate')),
  'duplicate fixture is approved once'
);
select throws_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000001', %L, 'REQUESTED', 1, 'APPROVED', null
  )$call$, (select request_id from leave_test_ids where label = 'duplicate')),
  '40001', 'LEAVE_REQUEST_STALE_DECISION', 'approval replay is stale and cannot duplicate Calendar leave'
);
reset role;

create function pg_temp.fail_leave_decision_event_v1()
returns trigger
language plpgsql
as $$
begin
  if new.event_type = 'DECISION' and new.management_note = 'FORCE_EVENT_FAILURE' then
    raise exception using errcode = 'P0001', message = 'TEST_EVENT_FAILURE';
  end if;
  return new;
end;
$$;

create trigger test_fail_leave_decision_event
before insert on public.workforce_leave_request_events
for each row execute function pg_temp.fail_leave_decision_event_v1();

set local role service_role;
select throws_ok(
  format($call$select public.decide_workforce_leave_request_v1(
    'ca100000-0000-4000-8000-000000000001', %L, 'REQUESTED', 1, 'APPROVED', 'FORCE_EVENT_FAILURE'
  )$call$, (select request_id from leave_test_ids where label = 'rollback')),
  'P0001', 'TEST_EVENT_FAILURE', 'partial decision failure rolls back atomically'
);
reset role;

select is(
  (select request_status from public.workforce_leave_requests where request_id = (select request_id from leave_test_ids where label = 'rollback')),
  'REQUESTED', 'failed decision rolls request status back'
);
select is(
  (select count(*)::integer from public.workforce_calendar_entries where employee_id = 'ca300000-0000-4000-8000-000000000011' and calendar_date = '2026-09-26'),
  0, 'failed decision rolls Calendar leave back'
);
select is(
  (select count(*)::integer from public.workforce_leave_request_events where request_id = (select request_id from leave_test_ids where label = 'rollback')),
  1, 'failed decision records no partial audit event'
);

drop trigger test_fail_leave_decision_event on public.workforce_leave_request_events;

select is(
  (select status from public.workforce_calendar_entries where employee_id = 'ca300000-0000-4000-8000-000000000012' and calendar_date = '2026-09-18'),
  'LEAVE', 'approved request creates canonical Calendar leave'
);
select is(
  (select count(*)::integer from public.workforce_calendar_entries where employee_id = 'ca300000-0000-4000-8000-000000000013' and calendar_date = '2026-09-18'),
  0, 'waiting request creates no Calendar leave'
);
select is(
  (select count(*)::integer from public.workforce_calendar_entries where employee_id = 'ca300000-0000-4000-8000-000000000011' and calendar_date in ('2026-09-20', '2026-09-21')),
  0, 'rejected requests create no Calendar leave'
);
select is(
  (select count(*)::integer from public.workforce_calendar_entries where employee_id = 'ca300000-0000-4000-8000-000000000011' and calendar_date = '2026-09-25'),
  1, 'approval replay cannot duplicate canonical leave'
);
select is(
  (select count(*)::integer from public.workforce_leave_request_events where request_id = (select request_id from leave_test_ids where label = 'waiting_approved')),
  3, 'REQUESTED to WAITING to APPROVED retains the complete history'
);
select is(
  (select string_agg(new_status, '>' order by occurred_at, event_id) from public.workforce_leave_request_events where request_id = (select request_id from leave_test_ids where label = 'waiting_approved')),
  'REQUESTED>WAITING>APPROVED', 'decision history order is immutable and complete'
);
select throws_ok(
  $$update public.workforce_leave_request_events set management_note = 'rewrite' where true$$,
  '55000', 'LEAVE_REQUEST_EVENT_IMMUTABLE', 'decision history cannot be rewritten'
);
select throws_ok(
  $$delete from public.workforce_leave_requests where true$$,
  '55000', 'LEAVE_REQUEST_DELETE_DENIED', 'leave requests remain available for audit'
);

set local role service_role;
select is(
  public.list_workforce_leave_requests_v1(
    'ca100000-0000-4000-8000-000000000001', '2026-09-18', '2026-09-18'
  )->'counters'->>'requested',
  '1', 'same-day queue reports the requested count'
);
select is(
  public.list_workforce_leave_requests_v1(
    'ca100000-0000-4000-8000-000000000001', '2026-09-18', '2026-09-18'
  )->'counters'->>'waiting',
  '1', 'same-day queue reports the waiting count'
);
select is(
  public.list_workforce_leave_requests_v1(
    'ca100000-0000-4000-8000-000000000001', '2026-09-18', '2026-09-18'
  )->'counters'->>'approved',
  '1', 'same-day queue reports the approved count'
);
select is(
  (
    select item->>'employee_number'
    from jsonb_array_elements(public.list_workforce_leave_requests_v1(
      'ca100000-0000-4000-8000-000000000001', '2026-09-18', '2026-09-18'
    )->'requests') as item
    where item->>'display_name' = 'Lana Jacobs'
  ),
  'LWS-90011', 'queue safely projects the activated employee number'
);
select is(
  (
    select context->>'approved_leave_count'
    from jsonb_array_elements(public.list_workforce_leave_requests_v1(
      'ca100000-0000-4000-8000-000000000001', '2026-09-18', '2026-09-18'
    )->'requests') as item
    cross join lateral jsonb_array_elements(item->'capacity_context') as context
    where item->>'display_name' = 'Lana Jacobs'
  ),
  '1', 'same-day context reports approved leave without a fake capacity maximum'
);
select is(
  (
    select context->>'waiting_count'
    from jsonb_array_elements(public.list_workforce_leave_requests_v1(
      'ca100000-0000-4000-8000-000000000001', '2026-09-18', '2026-09-18'
    )->'requests') as item
    cross join lateral jsonb_array_elements(item->'capacity_context') as context
    where item->>'display_name' = 'Lana Jacobs'
  ),
  '1', 'same-day context reports waiting requests'
);
select throws_ok(
  $$select public.list_workforce_leave_requests_v1(
    'ca100000-0000-4000-8000-000000000002', '2026-09-18', '2026-09-18'
  )$$,
  '42501', 'LEAVE_MANAGEMENT_OWNER_REQUIRED', 'non-owner cannot read management queue'
);
reset role;

set local role authenticated;
set local request.jwt.claim.sub = 'ca100000-0000-4000-8000-000000000001';
select is(
  public.get_operator_leave_requests_v1('2026-09-18', '2026-09-18')->'counters'->>'approved',
  '1', 'authenticated owner wrapper returns the bounded management queue'
);
set local request.jwt.claim.sub = 'ca100000-0000-4000-8000-000000000002';
select throws_ok(
  $$select public.get_operator_leave_requests_v1('2026-09-18', '2026-09-18')$$,
  '42501', 'LEAVE_MANAGEMENT_OWNER_REQUIRED', 'authenticated non-owner wrapper remains blocked'
);
reset role;

select * from finish();
rollback;