begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('public', 'resend_sdf_inbound_receipts', 'canonical receipt table exists');
select has_table('lws_internal', 'resend_sdf_inbound_receipt_deliveries', 'private delivery evidence exists');
select has_function(
  'public', 'register_resend_sdf_inbound_receipt_v1',
  array['text','text','text','text','text','timestamp with time zone','text'],
  'atomic receipt registration authority exists'
);
select ok(
  has_function_privilege('service_role', 'public.register_resend_sdf_inbound_receipt_v1(text,text,text,text,text,timestamp with time zone,text)', 'execute')
  and not has_function_privilege('anon', 'public.register_resend_sdf_inbound_receipt_v1(text,text,text,text,text,timestamp with time zone,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.register_resend_sdf_inbound_receipt_v1(text,text,text,text,text,timestamp with time zone,text)', 'execute'),
  'only service_role can execute receipt registration'
);
select ok(
  not has_table_privilege('anon', 'public.resend_sdf_inbound_receipts', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.resend_sdf_inbound_receipts', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.resend_sdf_inbound_receipts', 'select,insert,update,delete'),
  'receipt table has no direct client or service-role mutation surface'
);
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.resend_sdf_inbound_receipts'::regclass),
  'receipt table forces RLS'
);
select ok(
  exists(select 1 from pg_constraint where conname = 'resend_sdf_inbound_receipts_provider_email_key')
  and exists(select 1 from pg_constraint where conname = 'resend_sdf_inbound_receipts_delivery_key'),
  'provider email and initial delivery identities are unique'
);
select ok(
  pg_get_functiondef('public.register_resend_sdf_inbound_receipt_v1(text,text,text,text,text,timestamp with time zone,text)'::regprocedure)
    ~ 'pg_advisory_xact_lock',
  'registration serializes concurrent delivery and email identities'
);

create temporary table downstream_baseline as
select
  (select count(*) from public.quote_requests) as quote_requests,
  (select count(*) from public.customer_requests) as customer_requests,
  (select count(*) from public.sdf_projects) as sdf_projects,
  (select count(*) from public.quote_request_intakes) as intakes,
  (select count(*) from public.quote_request_email_jobs) as email_jobs,
  (select count(*) from public.document_inbox_items) as document_inbox_items;

create temporary table first_receipt as
select * from public.register_resend_sdf_inbound_receipt_v1(
  'email_2b_1', 'msg_delivery_1', '<message-1@example.test>',
  'customer@example.test', 'sdf@lorenzowebsolutions.be',
  '2030-01-01T10:00:00Z', repeat('a', 64)
);

select is((select replayed from first_receipt), false, 'first event creates one receipt');
select is((select count(*)::integer from public.resend_sdf_inbound_receipts), 1, 'exactly one receipt exists');
select is((select count(*)::integer from lws_internal.resend_sdf_inbound_receipt_deliveries), 1, 'first delivery evidence exists');

create temporary table same_delivery_replay as
select * from public.register_resend_sdf_inbound_receipt_v1(
  'email_2b_1', 'msg_delivery_1', '<message-1@example.test>',
  'customer@example.test', 'sdf@lorenzowebsolutions.be',
  '2030-01-01T10:00:00Z', repeat('a', 64)
);
select ok(
  (select replayed from same_delivery_replay)
  and (select receipt_id from same_delivery_replay) = (select receipt_id from first_receipt),
  'same delivery replays the canonical receipt'
);

create temporary table same_email_replay as
select * from public.register_resend_sdf_inbound_receipt_v1(
  'email_2b_1', 'msg_delivery_2', '<message-1@example.test>',
  'customer@example.test', 'sdf@lorenzowebsolutions.be',
  '2030-01-01T10:00:00Z', repeat('a', 64)
);
select ok(
  (select replayed from same_email_replay)
  and (select receipt_id from same_email_replay) = (select receipt_id from first_receipt),
  'same provider email through another delivery replays one receipt'
);
select is((select count(*)::integer from public.resend_sdf_inbound_receipts), 1, 'provider email replay creates no second receipt');
select is((select count(*)::integer from lws_internal.resend_sdf_inbound_receipt_deliveries), 2, 'each authenticated delivery identity remains protected');

select throws_ok($$
  select * from public.register_resend_sdf_inbound_receipt_v1(
    'email_conflict', 'msg_delivery_1', '<changed@example.test>',
    'attacker@example.test', 'sdf@lorenzowebsolutions.be',
    '2030-01-01T10:00:00Z', repeat('b', 64)
  )
$$, 'P0001', 'INBOUND_RECEIPT_CONFLICT', 'conflicting delivery replay is denied');

select throws_ok($$
  select * from public.register_resend_sdf_inbound_receipt_v1(
    'email_2b_1', 'msg_delivery_3', '<changed@example.test>',
    'attacker@example.test', 'sdf@lorenzowebsolutions.be',
    '2030-01-01T10:00:00Z', repeat('b', 64)
  )
$$, 'P0001', 'INBOUND_RECEIPT_CONFLICT', 'conflicting provider email replay is denied');

set local role authenticated;
select throws_ok($$
  insert into public.resend_sdf_inbound_receipts(
    provider_email_id, webhook_delivery_id, sender_email, matched_recipient,
    received_at, canonical_fingerprint
  ) values (
    'direct_client', 'msg_direct', 'client@example.test',
    'sdf@lorenzowebsolutions.be', clock_timestamp(), repeat('c', 64)
  )
$$, '42501', null, 'direct client insert is denied');
reset role;

select is((select count(*) from public.quote_requests), (select quote_requests from downstream_baseline), 'creates zero quote requests');
select is((select count(*) from public.customer_requests), (select customer_requests from downstream_baseline), 'creates zero customer requests');
select is((select count(*) from public.sdf_projects), (select sdf_projects from downstream_baseline), 'creates zero SDF projects');
select is((select count(*) from public.quote_request_intakes), (select intakes from downstream_baseline), 'creates zero intakes');
select is((select count(*) from public.quote_request_email_jobs), (select email_jobs from downstream_baseline), 'creates zero outbound email jobs');
select is((select count(*) from public.document_inbox_items), (select document_inbox_items from downstream_baseline), 'creates zero Document Inbox items');

select * from finish();
rollback;