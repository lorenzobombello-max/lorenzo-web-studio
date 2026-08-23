begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(63);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, budget_category_scheme, budget_category_code
) values
  ('f2300000-0000-4000-8000-000000000001', 'Active lifecycle', 'active@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Active fixture.', true, 'approved', 'budget_guard_v2', 'above_6000'),
  ('f2300000-0000-4000-8000-000000000002', 'Interrupted lifecycle', 'interrupted@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Interrupted fixture.', true, 'approved', 'budget_guard_v2', 'above_6000'),
  ('f2300000-0000-4000-8000-000000000003', 'Expired lifecycle', 'expired@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Expired fixture.', true, 'approved', 'budget_guard_v2', 'above_6000'),
  ('f2300000-0000-4000-8000-000000000004', 'Cancelled lifecycle', 'cancelled@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Cancelled fixture.', true, 'approved', 'budget_guard_v2', 'above_6000'),
  ('f2300000-0000-4000-8000-000000000005', 'Revoked lifecycle', 'revoked@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Revoked fixture.', true, 'approved', 'budget_guard_v2', 'above_6000'),
  ('f2300000-0000-4000-8000-000000000006', 'Submitted lifecycle', 'submitted@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Submitted fixture.', true, 'approved', 'budget_guard_v2', 'above_6000'),
  ('f2300000-0000-4000-8000-000000000007', 'Reviewed lifecycle', 'reviewed@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Reviewed fixture.', true, 'approved', 'budget_guard_v2', 'above_6000');

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  access_token_revoked_at, access_state, started_at, submitted_at, reviewed_at,
  created_at, confirmation, draft_revision
) values
  ('f2310000-0000-4000-8000-000000000001', 'f2300000-0000-4000-8000-000000000001', 'invited', repeat('a',64), clock_timestamp()+interval '1 day', null, 'ACTIVE', null, null, null, clock_timestamp()-interval '1 day', false, 0),
  ('f2310000-0000-4000-8000-000000000002', 'f2300000-0000-4000-8000-000000000002', 'in_progress', repeat('b',64), clock_timestamp()+interval '1 day', null, 'INTERRUPTED', clock_timestamp()-interval '1 hour', null, null, clock_timestamp()-interval '1 day', false, 2),
  ('f2310000-0000-4000-8000-000000000003', 'f2300000-0000-4000-8000-000000000003', 'in_progress', repeat('c',64), clock_timestamp()-interval '1 hour', null, 'ACTIVE', clock_timestamp()-interval '1 day', null, null, clock_timestamp()-interval '2 days', false, 3),
  ('f2310000-0000-4000-8000-000000000004', 'f2300000-0000-4000-8000-000000000004', 'in_progress', repeat('d',64), clock_timestamp()-interval '1 hour', null, 'CANCELLED', clock_timestamp()-interval '1 day', null, null, clock_timestamp()-interval '2 days', false, 4),
  ('f2310000-0000-4000-8000-000000000005', 'f2300000-0000-4000-8000-000000000005', 'in_progress', repeat('e',64), clock_timestamp()+interval '1 day', clock_timestamp()-interval '1 minute', 'CANCELLED', clock_timestamp()-interval '1 hour', null, null, clock_timestamp()-interval '1 day', false, 5),
  ('f2310000-0000-4000-8000-000000000006', 'f2300000-0000-4000-8000-000000000006', 'submitted', repeat('f',64), clock_timestamp()+interval '1 day', null, 'ACTIVE', clock_timestamp()-interval '2 hours', clock_timestamp()-interval '1 hour', null, clock_timestamp()-interval '1 day', true, 6),
  ('f2310000-0000-4000-8000-000000000007', 'f2300000-0000-4000-8000-000000000007', 'reviewed', repeat('1',64), clock_timestamp()+interval '1 day', null, 'ACTIVE', clock_timestamp()-interval '3 hours', clock_timestamp()-interval '2 hours', clock_timestamp()-interval '1 hour', clock_timestamp()-interval '1 day', true, 7);

select is((select effective_access from public.inspect_quote_request_intake_customer_access_v1(repeat('a',64))), 'ACTIVE', 'preflight resolves active');
select is((select effective_access from public.inspect_quote_request_intake_customer_access_v1(repeat('b',64))), 'INTERRUPTED', 'preflight resolves interrupted');
select is((select effective_access from public.inspect_quote_request_intake_customer_access_v1(repeat('c',64))), 'EXPIRED', 'preflight resolves expired');
select is((select effective_access from public.inspect_quote_request_intake_customer_access_v1(repeat('d',64))), 'CANCELLED', 'preflight resolves cancelled');
select is((select count(*)::integer from public.inspect_quote_request_intake_customer_access_v1(repeat('e',64))), 0, 'preflight hides revoked capability');
select is((select count(*)::integer from public.inspect_quote_request_intake_customer_access_v1(repeat('9',64))), 0, 'preflight hides unknown capability');

select is((select intake_status from public.inspect_quote_request_intake_details_v5(repeat('a',64))), 'invited', 'active invited inspect remains allowed');
select throws_ok($$select * from public.inspect_quote_request_intake_details_v5(repeat('b',64))$$, 'P0001', 'INTAKE_ACCESS_INTERRUPTED', 'inspect blocks interrupted');
select throws_ok($$select * from public.inspect_quote_request_intake_details_v5(repeat('c',64))$$, 'P0001', 'INTAKE_ACCESS_EXPIRED', 'inspect blocks expired');
select throws_ok($$select * from public.inspect_quote_request_intake_details_v5(repeat('d',64))$$, 'P0001', 'INTAKE_ACCESS_CANCELLED', 'inspect blocks cancelled');
select is((select count(*)::integer from public.inspect_quote_request_intake_details_v5(repeat('e',64))), 0, 'inspect preserves revoked denial');
select is((select intake_status from public.inspect_quote_request_intake_details_v5(repeat('f',64))), 'submitted', 'active submitted inspect remains allowed');
select is((select intake_status from public.inspect_quote_request_intake_details_v5(repeat('1',64))), 'reviewed', 'active reviewed inspect remains allowed');

select is((select intake_status from public.inspect_quote_request_intake(repeat('a',64))), 'invited', 'active legacy inspect remains allowed');
select throws_ok($$select * from public.inspect_quote_request_intake(repeat('b',64))$$, 'P0001', 'INTAKE_ACCESS_INTERRUPTED', 'legacy inspect blocks interrupted');
select throws_ok($$select * from public.inspect_quote_request_intake(repeat('c',64))$$, 'P0001', 'INTAKE_ACCESS_EXPIRED', 'legacy inspect blocks expired');
select throws_ok($$select * from public.inspect_quote_request_intake(repeat('d',64))$$, 'P0001', 'INTAKE_ACCESS_CANCELLED', 'legacy inspect blocks cancelled');
select is((select count(*)::integer from public.inspect_quote_request_intake(repeat('e',64))), 0, 'legacy inspect preserves revoked denial');
select is((select count(*)::integer from public.inspect_quote_request_intake(repeat('9',64))), 0, 'legacy inspect preserves unknown denial');

select is((select outcome from public.save_quote_request_intake_draft_v2(repeat('a',64),0,'{}','{}')), 'saved', 'active revision-aware save remains allowed');
select throws_ok($$select * from public.save_quote_request_intake_draft_v2(repeat('b',64),2,'{}','{}')$$, 'P0001', 'INTAKE_ACCESS_INTERRUPTED', 'revision-aware save blocks interrupted');
select throws_ok($$select * from public.save_quote_request_intake_draft_v2(repeat('c',64),3,'{}','{}')$$, 'P0001', 'INTAKE_ACCESS_EXPIRED', 'revision-aware save blocks expired');
select throws_ok($$select * from public.save_quote_request_intake_draft_v2(repeat('d',64),4,'{}','{}')$$, 'P0001', 'INTAKE_ACCESS_CANCELLED', 'revision-aware save blocks cancelled');
select is((select outcome from public.save_quote_request_intake_draft_v2(repeat('e',64),5,'{}','{}')), 'invalid_token', 'revision-aware save preserves revoked denial');

select is((select outcome from public.update_quote_request_intake(repeat('a',64),'save_draft','{}')), 'saved', 'active legacy save remains allowed');
select throws_ok($$select * from public.update_quote_request_intake(repeat('b',64),'save_draft','{}')$$, 'P0001', 'INTAKE_ACCESS_INTERRUPTED', 'legacy save blocks interrupted');
select throws_ok($$select * from public.update_quote_request_intake(repeat('c',64),'save_draft','{}')$$, 'P0001', 'INTAKE_ACCESS_EXPIRED', 'legacy save blocks expired');
select throws_ok($$select * from public.update_quote_request_intake(repeat('d',64),'save_draft','{}')$$, 'P0001', 'INTAKE_ACCESS_CANCELLED', 'legacy save blocks cancelled');
select is((select outcome from public.update_quote_request_intake(repeat('e',64),'save_draft','{}')), 'invalid_token', 'legacy save preserves revoked denial');

select is((select outcome from public.reset_quote_request_intake_draft_v1(repeat('a',64),1)), 'reset', 'active reset remains allowed');
select throws_ok($$select * from public.reset_quote_request_intake_draft_v1(repeat('b',64),2)$$, 'P0001', 'INTAKE_ACCESS_INTERRUPTED', 'reset blocks interrupted');
select throws_ok($$select * from public.reset_quote_request_intake_draft_v1(repeat('c',64),3)$$, 'P0001', 'INTAKE_ACCESS_EXPIRED', 'reset blocks expired');
select throws_ok($$select * from public.reset_quote_request_intake_draft_v1(repeat('d',64),4)$$, 'P0001', 'INTAKE_ACCESS_CANCELLED', 'reset blocks cancelled');
select is((select outcome from public.reset_quote_request_intake_draft_v1(repeat('e',64),5)), 'invalid_token', 'reset preserves revoked denial');
select is((select outcome from public.reset_quote_request_intake_draft_v1(repeat('f',64),6)), 'not_editable', 'submitted reset remains not editable');
select is((select outcome from public.reset_quote_request_intake_draft_v1(repeat('1',64),7)), 'not_editable', 'reviewed reset remains not editable');

select is((select outcome from public.update_quote_request_intake(repeat('f',64),'submit','{}')), 'already_submitted', 'active submitted remains idempotent');
select throws_ok($$select * from public.update_quote_request_intake(repeat('b',64),'submit','{}')$$, 'P0001', 'INTAKE_ACCESS_INTERRUPTED', 'submit blocks interrupted');
select throws_ok($$select * from public.update_quote_request_intake(repeat('c',64),'submit','{}')$$, 'P0001', 'INTAKE_ACCESS_EXPIRED', 'submit blocks expired');
select throws_ok($$select * from public.update_quote_request_intake(repeat('d',64),'submit','{}')$$, 'P0001', 'INTAKE_ACCESS_CANCELLED', 'submit blocks cancelled');
select is((select outcome from public.update_quote_request_intake(repeat('e',64),'submit','{}')), 'invalid_token', 'submit preserves revoked denial');
select ok(position('update_quote_request_intake(' in pg_get_functiondef('public.update_quote_request_intake_v5(text,text,jsonb,text,timestamp with time zone,jsonb,jsonb)'::regprocedure)) > 0, 'submit v5 delegates to lifecycle-enforced base mutation');

select is((select intake_status from public.inspect_preview_budget_guard_context_v1(repeat('a',64))), 'in_progress', 'active preview remains allowed');
select throws_ok($$select * from public.inspect_preview_budget_guard_context_v1(repeat('b',64))$$, 'P0001', 'INTAKE_ACCESS_INTERRUPTED', 'preview blocks interrupted');
select throws_ok($$select * from public.inspect_preview_budget_guard_context_v1(repeat('c',64))$$, 'P0001', 'INTAKE_ACCESS_EXPIRED', 'preview blocks expired');
select throws_ok($$select * from public.inspect_preview_budget_guard_context_v1(repeat('d',64))$$, 'P0001', 'INTAKE_ACCESS_CANCELLED', 'preview blocks cancelled');
select is((select count(*)::integer from public.inspect_preview_budget_guard_context_v1(repeat('e',64))), 0, 'preview preserves revoked denial');

select is((select intake_status from public.inspect_customer_pricing_read_v3(repeat('f',64))), 'submitted', 'active submitted customer pricing remains allowed');
select is((select intake_status from public.inspect_customer_pricing_read_v2(repeat('f',64))), 'submitted', 'active submitted legacy customer pricing remains allowed');
update public.quote_request_intakes set access_state='INTERRUPTED' where access_token_hash=repeat('f',64);
select throws_ok($$select * from public.inspect_customer_pricing_read_v3(repeat('f',64))$$, 'P0001', 'INTAKE_ACCESS_INTERRUPTED', 'customer pricing blocks interrupted');
select throws_ok($$select * from public.inspect_customer_pricing_read_v2(repeat('f',64))$$, 'P0001', 'INTAKE_ACCESS_INTERRUPTED', 'legacy customer pricing blocks interrupted');
update public.quote_request_intakes set access_state='ACTIVE', access_token_expires_at=clock_timestamp()-interval '1 minute' where access_token_hash=repeat('f',64);
select throws_ok($$select * from public.inspect_customer_pricing_read_v3(repeat('f',64))$$, 'P0001', 'INTAKE_ACCESS_EXPIRED', 'customer pricing blocks expired');
select throws_ok($$select * from public.inspect_customer_pricing_read_v2(repeat('f',64))$$, 'P0001', 'INTAKE_ACCESS_EXPIRED', 'legacy customer pricing blocks expired');
update public.quote_request_intakes set access_state='CANCELLED', access_token_expires_at=clock_timestamp()+interval '1 day' where access_token_hash=repeat('f',64);
select throws_ok($$select * from public.inspect_customer_pricing_read_v3(repeat('f',64))$$, 'P0001', 'INTAKE_ACCESS_CANCELLED', 'customer pricing blocks cancelled');
select throws_ok($$select * from public.inspect_customer_pricing_read_v2(repeat('f',64))$$, 'P0001', 'INTAKE_ACCESS_CANCELLED', 'legacy customer pricing blocks cancelled');
select is((select count(*)::integer from public.inspect_customer_pricing_read_v3(repeat('e',64))), 0, 'customer pricing preserves revoked denial');
select is((select count(*)::integer from public.inspect_customer_pricing_read_v2(repeat('e',64))), 0, 'legacy customer pricing preserves revoked denial');
select is((select intake_status from public.inspect_customer_pricing_read_v3(repeat('1',64))), 'reviewed', 'active reviewed customer pricing remains allowed');

select ok(not has_function_privilege('service_role','public.inspect_quote_request_intake_details_phase2b_predecessor(text)','execute'), 'service role cannot bypass inspect wrapper');
select ok(not has_function_privilege('service_role','public.update_quote_request_intake_phase2b_predecessor(text,text,jsonb,text,timestamp with time zone)','execute'), 'service role cannot bypass mutation wrapper');
select ok(
  not has_function_privilege('service_role','public.save_quote_request_intake_draft_v2_phase2b_predecessor(text,bigint,jsonb,jsonb)','execute')
  and not has_function_privilege('service_role','public.reset_quote_request_intake_draft_v1_phase2b_predecessor(text,bigint)','execute')
  and not has_function_privilege('service_role','public.inspect_preview_budget_guard_context_v1_phase2b_predecessor(text)','execute')
  and not has_function_privilege('service_role','public.inspect_customer_pricing_read_v3_phase2b_predecessor(text)','execute'),
  'service role cannot bypass draft, reset, preview, or pricing wrappers'
);
select ok(
  not has_function_privilege('service_role','public.inspect_quote_request_intake_phase2b_predecessor(text)','execute')
  and not has_function_privilege('service_role','public.inspect_customer_pricing_read_v2_phase2b_predecessor(text)','execute'),
  'service role cannot bypass legacy customer read wrappers'
);
select ok(not has_function_privilege('anon','public.inspect_quote_request_intake_customer_access_v1(text)','execute') and not has_function_privilege('authenticated','public.inspect_quote_request_intake_customer_access_v1(text)','execute'), 'public roles cannot execute lifecycle preflight');

select * from finish();
rollback;