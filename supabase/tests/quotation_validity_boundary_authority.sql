begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(30);

select has_table('public','quotation_validity_boundary_authorities','validity boundary authority exists');
select has_function('public','quotation_acceptance_deadline_v1',array['date'],'deadline helper exists');
select has_function('public','is_quotation_within_validity_at_v1',array['date','timestamp with time zone'],'deterministic boundary helper exists');
select has_function('public','quotation_issuance_acceptance_deadline_v1',array['uuid'],'ISSUED authority resolver exists');
select is((select validity_timezone from public.quotation_validity_boundary_authorities where authority_version=1),'Europe/Brussels','timezone authority is Europe/Brussels');
select is((select valid_until_semantics from public.quotation_validity_boundary_authorities where authority_version=1),'INCLUSIVE_CALENDAR_DATE','calendar date is inclusive');
select is((select acceptance_deadline_rule from public.quotation_validity_boundary_authorities where authority_version=1),'NEXT_LOCAL_DAY_00_00_EXCLUSIVE','deadline is exclusive next local midnight');
select ok(not has_table_privilege('service_role','public.quotation_validity_boundary_authorities','update'),'service role cannot mutate validity authority');
select ok(not has_function_privilege('anon','public.is_quotation_within_validity_v1(uuid)','execute'),'anon cannot query business eligibility');
select ok(has_function_privilege('service_role','public.is_quotation_within_validity_v1(uuid)','execute'),'service role can query business eligibility');
select ok(not has_function_privilege('service_role','public.is_quotation_within_validity_at_v1(date,timestamp with time zone)','execute'),'service role cannot inject an authoritative clock');
select ok(not has_function_privilege('authenticated','public.quotation_acceptance_deadline_v1(date)','execute'),'authenticated cannot call deadline authority directly');
select ok(not has_function_privilege('anon','public.quotation_issuance_acceptance_deadline_v1(uuid)','execute'),'anon cannot resolve issuance deadlines');
select throws_ok($$update public.quotation_validity_boundary_authorities set validity_timezone='UTC'$$,'55000','QUOTATION_VALIDITY_AUTHORITY_IMMUTABLE','caller cannot override timezone');
select throws_ok($$delete from public.quotation_validity_boundary_authorities$$,'55000','QUOTATION_VALIDITY_AUTHORITY_IMMUTABLE','validity authority cannot be deleted');

select is(public.quotation_acceptance_deadline_v1('2026-01-15'::date),'2026-01-15 23:00:00+00'::timestamptz,'winter deadline observes UTC+1');
select is(public.quotation_acceptance_deadline_v1('2026-07-15'::date),'2026-07-15 22:00:00+00'::timestamptz,'summer deadline observes UTC+2');
select is(public.quotation_acceptance_deadline_v1('2026-03-28'::date),'2026-03-28 23:00:00+00'::timestamptz,'spring transition deadline uses local midnight before DST jump');
select is(public.quotation_acceptance_deadline_v1('2026-03-29'::date),'2026-03-29 22:00:00+00'::timestamptz,'spring post-transition deadline uses summer offset');
select is(public.quotation_acceptance_deadline_v1('2026-10-25'::date),'2026-10-25 23:00:00+00'::timestamptz,'autumn transition deadline uses winter offset');

select ok(public.is_quotation_within_validity_at_v1('2026-09-15','2026-09-15 21:59:59.999999+00'),'last instant before deadline is valid');
select ok(not public.is_quotation_within_validity_at_v1('2026-09-15','2026-09-15 22:00:00+00'),'exact deadline is expired');
select ok(not public.is_quotation_within_validity_at_v1('2026-09-15','2026-09-15 22:00:00.000001+00'),'after deadline is expired');
select ok(public.is_quotation_within_validity_at_v1('2026-09-15','2026-09-14 22:00:00+00'),'start of valid-until local day is valid');
select ok(public.is_quotation_within_validity_at_v1('2026-09-15','2026-09-15 12:00:00+00'),'middle of valid-until local day is valid');
select is(public.quotation_acceptance_deadline_v1('2026-09-14'::text::date),public.quotation_acceptance_deadline_v1('2026-09-14'::date),'historical v1 ISO date text has deterministic interpretation');
select throws_ok($$select public.quotation_acceptance_deadline_v1(null)$$,'22023','VALID_UNTIL_INVALID','missing commercial date is rejected');
select throws_ok($$select public.is_quotation_within_validity_at_v1('2026-09-15',null)$$,'22023','SERVER_TIME_INVALID','missing test clock is rejected');
select throws_ok($$select * from public.quotation_issuance_acceptance_deadline_v1('00000000-0000-4000-8000-000000000001')$$,'P0001','ISSUANCE_NOT_ELIGIBLE','nonexistent or non-ISSUED quotation fails closed');
select is((select count(*)::integer from public.quote_request_quotation_issuances),0,'validity authority creates no issuance side effects');

select * from finish();
rollback;