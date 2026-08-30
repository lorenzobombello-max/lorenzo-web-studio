begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('public', 'workforce_employees', 'workforce employee authority exists');
select has_table('public', 'workforce_calendar_entries', 'workforce calendar authority exists');
select columns_are(
  'public', 'workforce_employees',
  array['id', 'display_name', 'role_title', 'team_name', 'employment_status', 'start_date', 'end_date', 'commercial_operator_id', 'created_at', 'updated_at'],
  'employee authority contains only the approved foundation fields'
);
select columns_are(
  'public', 'workforce_calendar_entries',
  array['id', 'employee_id', 'calendar_date', 'status', 'created_at', 'updated_at'],
  'calendar authority contains only the approved presentation fields'
);
select has_function(
  'public', 'list_workforce_calendar_v1', array['uuid', 'date', 'date'],
  'bounded workforce calendar read RPC exists'
);
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.workforce_employees'::regclass)
  and (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.workforce_calendar_entries'::regclass),
  'workforce tables enable and force RLS'
);
select ok(
  not has_table_privilege('anon', 'public.workforce_employees', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.workforce_employees', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.workforce_employees', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.workforce_calendar_entries', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.workforce_calendar_entries', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.workforce_calendar_entries', 'select,insert,update,delete'),
  'runtime roles have no direct workforce table authority'
);
select ok(
  has_function_privilege('service_role', 'public.list_workforce_calendar_v1(uuid,date,date)', 'execute')
  and not has_function_privilege('anon', 'public.list_workforce_calendar_v1(uuid,date,date)', 'execute')
  and not has_function_privilege('authenticated', 'public.list_workforce_calendar_v1(uuid,date,date)', 'execute'),
  'only service role can execute the workforce read RPC'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.workforce_calendar_entries'::regclass
      and conname = 'workforce_calendar_entries_employee_date_key'
      and contype = 'u'
  ),
  'one calendar entry per employee and date is enforced'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.workforce_calendar_entries'::regclass
      and confrelid = 'public.workforce_employees'::regclass
      and confdeltype = 'r'
  ),
  'calendar history restricts employee deletion'
);

set local role anon;
select throws_ok(
  $$select * from public.workforce_employees$$,
  '42501', 'permission denied for table workforce_employees',
  'anon direct employee read is denied'
);
reset role;
set local role authenticated;
select throws_ok(
  $$select * from public.workforce_calendar_entries$$,
  '42501', 'permission denied for table workforce_calendar_entries',
  'authenticated direct calendar read is denied'
);
reset role;

insert into auth.users(id, email) values
  ('f2000000-0000-4000-8000-000000000001', 'workforce-owner@example.test'),
  ('f2000000-0000-4000-8000-000000000002', 'workforce-admin@example.test'),
  ('f2000000-0000-4000-8000-000000000003', 'workforce-manager@example.test'),
  ('f2000000-0000-4000-8000-000000000004', 'workforce-operator@example.test'),
  ('f2000000-0000-4000-8000-000000000005', 'workforce-disabled@example.test');

insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('f2010000-0000-4000-8000-000000000001', 'f2000000-0000-4000-8000-000000000001', 'Workforce Owner', 'owner', 'ACTIVE'),
  ('f2010000-0000-4000-8000-000000000002', 'f2000000-0000-4000-8000-000000000002', 'Workforce Admin', 'admin', 'ACTIVE'),
  ('f2010000-0000-4000-8000-000000000003', 'f2000000-0000-4000-8000-000000000003', 'Workforce Manager', 'operations_manager', 'ACTIVE'),
  ('f2010000-0000-4000-8000-000000000004', 'f2000000-0000-4000-8000-000000000004', 'Workforce Operator', 'operator', 'ACTIVE'),
  ('f2010000-0000-4000-8000-000000000005', 'f2000000-0000-4000-8000-000000000005', 'Workforce Disabled', 'admin', 'DISABLED');

select is(
  public.list_workforce_calendar_v1(
    'f2000000-0000-4000-8000-000000000001', '2026-01-01', '2026-12-31'
  )->'employees',
  '[]'::jsonb,
  'empty workforce returns an empty employee array'
);
select throws_ok(
  $$select public.list_workforce_calendar_v1(null, '2026-01-01', '2026-01-01')$$,
  '42501', 'WORKFORCE_ACTOR_REQUIRED', 'actor is required'
);
select throws_ok(
  $$select public.list_workforce_calendar_v1('f2000000-0000-4000-8000-000000000001', '2026-01-02', '2026-01-01')$$,
  '22023', 'WORKFORCE_DATE_RANGE_REVERSED', 'reversed date range is rejected'
);
select throws_ok(
  $$select public.list_workforce_calendar_v1('f2000000-0000-4000-8000-000000000001', '2026-01-01', '2027-01-02')$$,
  '22023', 'WORKFORCE_DATE_RANGE_TOO_LARGE', 'more than 366 inclusive days is rejected'
);
select lives_ok(
  $$select public.list_workforce_calendar_v1('f2000000-0000-4000-8000-000000000001', '2027-01-01', '2028-01-01')$$,
  'exactly 366 inclusive days is accepted'
);
select throws_ok(
  $$select public.list_workforce_calendar_v1('f2000000-0000-4000-8000-000000000004', '2026-01-01', '2026-01-01')$$,
  '42501', 'WORKFORCE_MANAGEMENT_READER_REQUIRED', 'non-management operator is rejected'
);
select throws_ok(
  $$select public.list_workforce_calendar_v1('f2000000-0000-4000-8000-000000000005', '2026-01-01', '2026-01-01')$$,
  '42501', 'OPERATOR_NOT_ACTIVE', 'disabled management actor is rejected'
);
select throws_ok(
  $$select public.list_workforce_calendar_v1('f2000000-0000-4000-8000-000000000099', '2026-01-01', '2026-01-01')$$,
  '42501', 'UNKNOWN_OPERATOR', 'unknown actor is rejected'
);

insert into public.workforce_employees(
  id, display_name, role_title, team_name, employment_status, start_date
)
select
  ('f1000000-0000-4000-8000-' || lpad(sequence::text, 12, '0'))::uuid,
  'Workforce Employee ' || lpad(sequence::text, 2, '0'),
  case when sequence % 2 = 0 then 'Consultant' else 'Operator' end,
  case when sequence % 2 = 0 then 'Delivery' else 'Operations' end,
  case when sequence = 20 then 'INACTIVE' else 'ACTIVE' end,
  '2026-01-01'::date
from generate_series(1, 20) as sequence;

select is(
  (select count(*)::integer from public.workforce_employees where commercial_operator_id is null),
  20,
  'workforce people are not automatically linked to operator accounts'
);
select throws_matching(
  $$insert into public.workforce_employees(display_name, employment_status, start_date) values ('Invalid status', 'ONBOARDING', '2026-01-01')$$,
  '.*workforce_employees_employment_status_check.*',
  'unknown employment status is rejected'
);

insert into public.workforce_calendar_entries(employee_id, calendar_date, status) values
  ('f1000000-0000-4000-8000-000000000001', '2026-08-24', 'WORKED_FULL_DAY'),
  ('f1000000-0000-4000-8000-000000000002', '2026-08-24', 'WORKED_HALF_DAY_AM'),
  ('f1000000-0000-4000-8000-000000000003', '2026-08-24', 'WORKED_HALF_DAY_PM'),
  ('f1000000-0000-4000-8000-000000000004', '2026-08-24', 'LEAVE'),
  ('f1000000-0000-4000-8000-000000000005', '2026-08-24', 'SICK'),
  ('f1000000-0000-4000-8000-000000000006', '2026-08-24', 'OTHER_ABSENCE'),
  ('f1000000-0000-4000-8000-000000000001', '2026-08-25', 'LEAVE');

select throws_ok(
  $$insert into public.workforce_calendar_entries(employee_id, calendar_date, status) values ('f1000000-0000-4000-8000-000000000001', '2026-08-24', 'SICK')$$,
  '23505', null, 'duplicate employee/date is rejected'
);
select throws_matching(
  $$insert into public.workforce_calendar_entries(employee_id, calendar_date, status) values ('f1000000-0000-4000-8000-000000000007', '2026-08-24', 'MEDICAL_DETAIL')$$,
  '.*workforce_calendar_entries_status_check.*',
  'unknown calendar status is rejected'
);
select throws_ok(
  $$delete from public.workforce_employees where id = 'f1000000-0000-4000-8000-000000000001'$$,
  '23503', null, 'employee deletion cannot silently destroy calendar history'
);

set local role service_role;
select is(
  jsonb_array_length(public.list_workforce_calendar_v1(
    'f2000000-0000-4000-8000-000000000001', '2026-08-24', '2026-08-30'
  )->'employees'),
  20,
  'service read returns all 20 deterministic workforce employees'
);
select is(
  (public.list_workforce_calendar_v1(
    'f2000000-0000-4000-8000-000000000001', '2026-08-24', '2026-08-30'
  )->'employees'->0->'entries'->0->>'status'),
  'WORKED_FULL_DAY',
  'full day status is projected'
);
select is(
  (public.list_workforce_calendar_v1(
    'f2000000-0000-4000-8000-000000000002', '2026-08-24', '2026-08-24'
  )->'employees'->1->'entries'->0->>'status'),
  'WORKED_HALF_DAY_AM',
  'admin actor reads half-day AM status'
);
select is(
  (public.list_workforce_calendar_v1(
    'f2000000-0000-4000-8000-000000000003', '2026-08-24', '2026-08-24'
  )->'employees'->2->'entries'->0->>'status'),
  'WORKED_HALF_DAY_PM',
  'operations manager actor reads half-day PM status'
);
select is(
  (public.list_workforce_calendar_v1(
    'f2000000-0000-4000-8000-000000000001', '2026-08-24', '2026-08-24'
  )->'employees'->3->'entries'->0->>'status'),
  'LEAVE',
  'leave presentation status is projected'
);
select is(
  (public.list_workforce_calendar_v1(
    'f2000000-0000-4000-8000-000000000001', '2026-08-24', '2026-08-24'
  )->'employees'->4->'entries'->0->>'status'),
  'SICK',
  'sickness projection contains status only'
);
select is(
  (public.list_workforce_calendar_v1(
    'f2000000-0000-4000-8000-000000000001', '2026-08-24', '2026-08-24'
  )->'employees'->5->'entries'->0->>'status'),
  'OTHER_ABSENCE',
  'other absence presentation status is projected'
);
select is(
  jsonb_array_length(public.list_workforce_calendar_v1(
    'f2000000-0000-4000-8000-000000000001', '2026-08-25', '2026-08-25'
  )->'employees'->0->'entries'),
  1,
  'calendar entries are bounded to the requested date range'
);
select ok(
  not (public.list_workforce_calendar_v1(
    'f2000000-0000-4000-8000-000000000001', '2026-08-24', '2026-08-24'
  )::text ~* 'iban|bank|identity|medical|diagnos|document|token|auth_user|commercial_operator'),
  'readmodel projects no account, bank, identity, medical, document, or token data'
);
reset role;

select * from finish();
rollback;