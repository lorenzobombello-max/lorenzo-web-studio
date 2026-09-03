begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('public', 'employee_identity_reservations', 'pre-employment identity reservation authority exists');
select has_table('public', 'employee_number_allocation_ledger', 'employee number allocation ledger exists');
select has_table('public', 'employee_identity_activation_events', 'employee activation event ledger exists');
select has_function(
  'public', 'reserve_employee_identity_v1', array['text', 'text'],
  'server-side employee identity allocator exists'
);
select has_function(
  'public', 'activate_workforce_employee_identity_v1', array['uuid', 'date', 'text', 'text', 'text', 'date'],
  'transactional workforce activation function exists'
);
select ok(
  exists (
    select 1
    from pg_class
    where oid = 'public.employee_identity_number_seq'::regclass
      and relkind = 'S'
  ),
  'employee number sequence exists'
);
select ok(
  (select attnotnull
   from pg_attribute
   where attrelid = 'public.workforce_employees'::regclass
     and attname = 'start_date'
     and not attisdropped),
  'workforce start_date remains NOT NULL'
);
select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class
   where oid = 'public.employee_identity_reservations'::regclass)
  and (select relrowsecurity and relforcerowsecurity
       from pg_class
       where oid = 'public.employee_number_allocation_ledger'::regclass)
  and (select relrowsecurity and relforcerowsecurity
       from pg_class
       where oid = 'public.employee_identity_activation_events'::regclass),
  'identity tables enable and force RLS'
);
select ok(
  not has_table_privilege('anon', 'public.employee_identity_reservations', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.employee_identity_reservations', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.employee_identity_reservations', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.employee_number_allocation_ledger', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.employee_number_allocation_ledger', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.employee_number_allocation_ledger', 'select,insert,update,delete'),
  'runtime roles have no direct identity or ledger authority'
);
select ok(
  not has_function_privilege('anon', 'public.reserve_employee_identity_v1(text,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.reserve_employee_identity_v1(text,text)', 'execute')
  and not has_function_privilege('service_role', 'public.reserve_employee_identity_v1(text,text)', 'execute')
  and not has_function_privilege('anon', 'public.activate_workforce_employee_identity_v1(uuid,date,text,text,text,date)', 'execute')
  and not has_function_privilege('authenticated', 'public.activate_workforce_employee_identity_v1(uuid,date,text,text,text,date)', 'execute')
  and not has_function_privilege('service_role', 'public.activate_workforce_employee_identity_v1(uuid,date,text,text,text,date)', 'execute'),
  'C3A exposes no runtime reservation or activation route'
);

select is(
  (select count(*) from public.employee_identity_reservations),
  3::bigint,
  'exactly three owner-approved identities are reserved'
);
select results_eq(
  $$
    select employee_number, display_name, identity_status, workforce_employee_id
    from public.employee_identity_reservations
    order by employee_number
  $$,
  $$values
    ('LWS-00001'::text, 'Lorenzo Bombello'::text, 'PRE_EMPLOYMENT'::text, null::uuid),
    ('LWS-00002'::text, 'Herlinde Verlodt'::text, 'PRE_EMPLOYMENT'::text, null::uuid),
    ('LWS-00003'::text, 'Daisy Defraine'::text, 'PRE_EMPLOYMENT'::text, null::uuid)
  $$,
  'reserved identities have exact numbers, names, status, and no Workforce binding'
);
select is(
  (select count(*) from public.employee_number_allocation_ledger),
  3::bigint,
  'ledger contains exactly three initial allocations'
);
select results_eq(
  $$
    select employee_number
    from public.employee_number_allocation_ledger
    order by employee_number
  $$,
  $$values ('LWS-00001'::text), ('LWS-00002'::text), ('LWS-00003'::text)$$,
  'ledger permanently records the first three numbers'
);
select is(
  (select count(*)
   from public.workforce_employees
   where display_name in ('Lorenzo Bombello', 'Herlinde Verlodt', 'Daisy Defraine')),
  0::bigint,
  'pre-employment reservations do not create Workforce employees'
);
select is(
  (select last_value from public.employee_identity_number_seq),
  4::bigint,
  'sequence is initialized at numeric value four'
);
select is(
  (select is_called from public.employee_identity_number_seq),
  false,
  'sequence value four has not yet been allocated'
);

select throws_ok(
  $$insert into public.employee_identity_reservations(employee_number, display_name) values ('LWS-00001', 'C3A Duplicate Test')$$,
  '23505', null,
  'duplicate employee number is rejected'
);
select throws_ok(
  $$insert into public.employee_identity_reservations(employee_number, display_name) values ('LWS-1', 'C3A Format Test')$$,
  '23514', null,
  'free-form employee number is rejected'
);
select throws_ok(
  $$update public.employee_identity_reservations set employee_number = 'LWS-00012' where employee_number = 'LWS-00002'$$,
  '55000', 'EMPLOYEE_IDENTITY_RESERVATION_IMMUTABLE',
  'employee number cannot be changed'
);
select throws_ok(
  $$delete from public.employee_identity_reservations where employee_number = 'LWS-00002'$$,
  '55000', 'EMPLOYEE_IDENTITY_RESERVATION_IMMUTABLE',
  'reservation cannot be deleted or recycled'
);
select throws_ok(
  $$update public.employee_number_allocation_ledger set allocation_reason = 'changed' where employee_number = 'LWS-00001'$$,
  '55000', 'EMPLOYEE_NUMBER_ALLOCATION_IMMUTABLE',
  'allocation ledger update is rejected'
);
select throws_ok(
  $$delete from public.employee_number_allocation_ledger where employee_number = 'LWS-00001'$$,
  '55000', 'EMPLOYEE_NUMBER_ALLOCATION_IMMUTABLE',
  'allocation ledger delete is rejected'
);
insert into public.employee_identity_reservations(employee_number, display_name)
values ('LWS-09998', 'C3A Ledger Consistency Test');
select throws_ok(
  $$
    insert into public.employee_number_allocation_ledger(
      employee_identity_id,
      employee_number,
      allocation_reason
    )
    select employee_identity_id, 'LWS-09997', 'C3A_TEST'
    from public.employee_identity_reservations
    where employee_number = 'LWS-09998'
  $$,
  '23503', null,
  'ledger number must match its reservation number'
);

create temporary table c3a_allocations(payload jsonb);
insert into c3a_allocations(payload)
values (public.reserve_employee_identity_v1('C3A Allocation Test 04', 'C3A_TEST'));
insert into c3a_allocations(payload)
values (public.reserve_employee_identity_v1('C3A Allocation Test 05', 'C3A_TEST'));
select results_eq(
  $$select payload->>'employee_number' from c3a_allocations order by payload->>'employee_number'$$,
  $$values ('LWS-00004'::text), ('LWS-00005'::text)$$,
  'first two server allocations are LWS-00004 and LWS-00005'
);
select throws_ok(
  $$delete from public.employee_identity_reservations where employee_number = 'LWS-00004'$$,
  '55000', 'EMPLOYEE_IDENTITY_RESERVATION_IMMUTABLE',
  'allocated number remains reserved before activation'
);

create function public.c3a_test_reject_ledger_insert()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.allocation_reason = 'C3A_TEST_FORCE_FAILURE' then
    raise exception using errcode = '55000', message = 'C3A_FORCED_LEDGER_FAILURE';
  end if;
  return new;
end;
$$;
create trigger trg_c3a_test_reject_ledger_insert
before insert on public.employee_number_allocation_ledger
for each row execute function public.c3a_test_reject_ledger_insert();
select throws_ok(
  $$select public.reserve_employee_identity_v1('C3A Allocation Rollback Test', 'C3A_TEST_FORCE_FAILURE')$$,
  '55000', 'C3A_FORCED_LEDGER_FAILURE',
  'ledger failure aborts identity reservation'
);
select is(
  (select count(*) from public.employee_identity_reservations where display_name = 'C3A Allocation Rollback Test'),
  0::bigint,
  'failed ledger insert leaves no partial identity row'
);
drop trigger trg_c3a_test_reject_ledger_insert on public.employee_number_allocation_ledger;
drop function public.c3a_test_reject_ledger_insert();

create temporary table c3a_activation_identity as
select public.reserve_employee_identity_v1('C3A Workforce Activation Test', 'C3A_TEST') as payload;
select throws_ok(
  $$
    select public.activate_workforce_employee_identity_v1(
      (select (payload->>'employee_identity_id')::uuid from c3a_activation_identity),
      null,
      'ACTIVE'
    )
  $$,
  '23502', 'WORKFORCE_START_DATE_REQUIRED',
  'workforce activation without a start date is blocked'
);
select is(
  (select count(*) from public.workforce_employees where display_name = 'C3A Workforce Activation Test'),
  0::bigint,
  'rejected activation creates no Workforce employee'
);

create function public.c3a_test_reject_activation_event()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  if exists (
    select 1
    from public.employee_identity_reservations
    where employee_identity_id = new.employee_identity_id
      and display_name = 'C3A Workforce Activation Test'
  ) then
    raise exception using errcode = '55000', message = 'C3A_FORCED_ACTIVATION_EVENT_FAILURE';
  end if;
  return new;
end;
$$;
create trigger trg_c3a_test_reject_activation_event
before insert on public.employee_identity_activation_events
for each row execute function public.c3a_test_reject_activation_event();
select throws_ok(
  $$
    select public.activate_workforce_employee_identity_v1(
      (select (payload->>'employee_identity_id')::uuid from c3a_activation_identity),
      '2026-10-01',
      'ACTIVE'
    )
  $$,
  '55000', 'C3A_FORCED_ACTIVATION_EVENT_FAILURE',
  'activation event failure aborts the complete activation'
);
select is(
  (select count(*) from public.workforce_employees where display_name = 'C3A Workforce Activation Test'),
  0::bigint,
  'failed activation event leaves no partial Workforce employee'
);
select is(
  (select identity_status
   from public.employee_identity_reservations
   where employee_identity_id = (select (payload->>'employee_identity_id')::uuid from c3a_activation_identity)),
  'PRE_EMPLOYMENT'::text,
  'failed activation leaves reservation in PRE_EMPLOYMENT'
);
drop trigger trg_c3a_test_reject_activation_event on public.employee_identity_activation_events;
drop function public.c3a_test_reject_activation_event();

create temporary table c3a_activation_result as
select public.activate_workforce_employee_identity_v1(
  (select (payload->>'employee_identity_id')::uuid from c3a_activation_identity),
  '2026-10-01',
  'ACTIVE'
) as payload;
select is(
  (select payload->>'identity_status' from c3a_activation_result),
  'ACTIVATED'::text,
  'activation with a real test start date succeeds'
);
select is(
  (select payload->>'employee_number' from c3a_activation_result),
  (select payload->>'employee_number' from c3a_activation_identity),
  'activation preserves the reserved employee number'
);
select ok(
  exists (
    select 1
    from public.workforce_employees employee
    join public.employee_identity_reservations identity
      on identity.workforce_employee_id = employee.id
    where identity.employee_identity_id = (select (payload->>'employee_identity_id')::uuid from c3a_activation_identity)
      and employee.start_date = '2026-10-01'
      and employee.employment_status = 'ACTIVE'
      and employee.commercial_operator_id is null
  ),
  'activation creates one minimally valid unbound Workforce employee'
);
select is(
  (select count(*)
   from public.employee_identity_activation_events
   where employee_identity_id = (select (payload->>'employee_identity_id')::uuid from c3a_activation_identity)),
  1::bigint,
  'activation writes one immutable binding event'
);
select throws_ok(
  $$
    select public.activate_workforce_employee_identity_v1(
      (select (payload->>'employee_identity_id')::uuid from c3a_activation_identity),
      '2026-10-02',
      'ACTIVE'
    )
  $$,
  '55000', 'EMPLOYEE_IDENTITY_ALREADY_ACTIVATED',
  'second Workforce binding is blocked'
);
select throws_ok(
  $$
    update public.employee_identity_reservations
    set workforce_employee_id = gen_random_uuid()
    where employee_identity_id = (select (payload->>'employee_identity_id')::uuid from c3a_activation_identity)
  $$,
  '55000', 'EMPLOYEE_IDENTITY_BINDING_IMMUTABLE',
  'activated Workforce UUID cannot be replaced'
);
select throws_ok(
  $$update public.employee_identity_activation_events set activated_at = clock_timestamp()$$,
  '55000', 'EMPLOYEE_IDENTITY_ACTIVATION_EVENT_IMMUTABLE',
  'activation event update is rejected'
);
select throws_ok(
  $$delete from public.employee_identity_activation_events$$,
  '55000', 'EMPLOYEE_IDENTITY_ACTIVATION_EVENT_IMMUTABLE',
  'activation event delete is rejected'
);

insert into auth.users(id, email)
values ('c3a00000-0000-4000-8000-000000000001', 'c3a-workforce-owner@example.test');
insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status)
values (
  'c3a10000-0000-4000-8000-000000000001',
  'c3a00000-0000-4000-8000-000000000001',
  'C3A Workforce Owner',
  'owner',
  'ACTIVE'
);
select ok(
  not (public.list_workforce_calendar_v1(
    'c3a00000-0000-4000-8000-000000000001',
    '2026-10-01',
    '2026-10-01'
  )::text ~ 'Lorenzo Bombello|Herlinde Verlodt|Daisy Defraine'),
  'pre-employment identities do not appear in Calendar'
);
select ok(
  public.list_workforce_calendar_v1(
    'c3a00000-0000-4000-8000-000000000001',
    '2026-10-01',
    '2026-10-01'
  )::text ~ (select payload->>'workforce_employee_id' from c3a_activation_result),
  'Calendar projects an activated test employee by Workforce UUID'
);
select set_config('request.jwt.claim.sub', 'c3a00000-0000-4000-8000-000000000001', true);
set local role authenticated;
select ok(
  public.list_operator_workforce_v1()::text ~ 'C3A Workforce Activation Test',
  'Workforce read RPC projects an activated test employee'
);
select ok(
  not (public.list_operator_workforce_v1()::text ~ 'Lorenzo Bombello|Herlinde Verlodt|Daisy Defraine'),
  'Workforce read RPC excludes pre-employment identities'
);
reset role;

select setval('public.employee_identity_number_seq', 4, false);
select * from finish();
rollback;