begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_column(
  'public', 'resend_sdf_inbound_receipts', 'record_classification',
  'receipt classification column exists'
);
select col_not_null(
  'public', 'resend_sdf_inbound_receipts', 'record_classification',
  'receipt classification is required'
);
select col_default_is(
  'public', 'resend_sdf_inbound_receipts', 'record_classification',
  'production', 'receipt classification defaults to production'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.resend_sdf_inbound_receipts'::regclass
      and conname = 'resend_sdf_inbound_receipts_record_classification_check'
      and pg_get_constraintdef(oid) = 'CHECK ((record_classification = ANY (ARRAY[''production''::text, ''internal_e2e''::text])))'
  ),
  'receipt classification permits exactly production and internal_e2e'
);
select ok(
  not exists (
    select 1
    from public.resend_sdf_inbound_receipts
    where record_classification <> 'production'
  ),
  'all pre-canary existing receipts remain production'
);
select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class where oid = 'public.resend_sdf_inbound_receipts'::regclass)
  and (select relrowsecurity and relforcerowsecurity
       from pg_class where oid = 'lws_internal.resend_sdf_inbound_receipt_deliveries'::regclass),
  'receipt and delivery tables retain forced RLS'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.register_resend_sdf_inbound_receipt_v1(text,text,text,text,text,timestamp with time zone,text)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.register_resend_sdf_inbound_receipt_v1(text,text,text,text,text,timestamp with time zone,text)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.register_resend_sdf_inbound_receipt_v1(text,text,text,text,text,timestamp with time zone,text)',
    'execute'
  ),
  'receipt registration grants remain service-role-only'
);
select ok(
  not has_table_privilege('anon', 'public.resend_sdf_inbound_receipts', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.resend_sdf_inbound_receipts', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.resend_sdf_inbound_receipts', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'lws_internal.resend_sdf_inbound_receipt_deliveries', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'lws_internal.resend_sdf_inbound_receipt_deliveries', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'lws_internal.resend_sdf_inbound_receipt_deliveries', 'select,insert,update,delete'),
  'receipt and delivery direct grants remain closed'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.get_sdf_inbound_signed_canary_evidence_v1()', 'execute'
  )
  and not has_function_privilege(
    'anon', 'public.get_sdf_inbound_signed_canary_evidence_v1()', 'execute'
  )
  and not has_function_privilege(
    'service_role', 'public.get_sdf_inbound_signed_canary_evidence_v1()', 'execute'
  ),
  'only authenticated callers can enter the owner AAL2 evidence authority'
);

create temporary table downstream_baseline as
select
  (select count(*) from public.quote_requests) as quote_requests,
  (select count(*) from public.customer_requests) as customer_requests,
  (select count(*) from public.sdf_projects) as sdf_projects,
  (select count(*) from public.quote_request_intakes) as intakes,
  (select count(*) from public.quote_request_email_jobs) as email_jobs,
  (select count(*) from public.document_inbox_items) as document_inbox_items,
  (select count(*) from storage.objects) as storage_objects,
  (select count(*) from auth.users) as auth_users;

create temporary table normal_receipt as
select * from public.register_resend_sdf_inbound_receipt_v1(
  'signed_canary_normal_email', 'signed_canary_normal_delivery',
  '<signed-canary-normal@example.test>', 'customer@example.test',
  'sdf@lorenzowebsolutions.be', '2030-01-01T10:00:00Z', repeat('a', 64)
);
select is(
  (select record_classification from public.resend_sdf_inbound_receipts
   where provider_email_id = 'signed_canary_normal_email'),
  'production',
  'normal registration remains production'
);

select throws_ok($$
  select * from public.register_resend_sdf_inbound_receipt_v1(
    'internal_e2e_sdf_inbound_canary_v1', 'partial_spoof_delivery',
    '<partial-spoof@invalid.local>', 'attacker@example.test',
    'sdf@lorenzowebsolutions.be', '2030-01-01T10:00:00Z', repeat('b', 64)
  )
$$, '22023', 'INVALID_RESEND_SDF_INBOUND_RECEIPT', 'partial canary tuple fails closed');

select throws_ok($$
  select * from public.register_resend_sdf_inbound_receipt_v1(
    'internal_e2e_sdf_inbound_canary_v1', 'partial_spoof_null_message',
    null, 'attacker@example.test', 'sdf@lorenzowebsolutions.be',
    '2030-01-01T10:00:00Z', repeat('b', 64)
  )
$$, '22023', 'INVALID_RESEND_SDF_INBOUND_RECEIPT', 'partial canary tuple with null message id fails closed');

create temporary table first_canary as
select * from public.register_resend_sdf_inbound_receipt_v1(
  'internal_e2e_sdf_inbound_canary_v1',
  'internal_e2e_sdf_inbound_delivery_v1',
  '<internal-e2e-sdf-inbound-canary-v1@invalid.local>',
  'sdf-inbound-canary@invalid.local',
  'sdf-inbound-canary@invalid.local',
  '2000-01-01T00:00:00.000Z',
  '2962999d3c2a4f05a820c57319af788b77da8bcb53ab209bb8d519f643401d5d'
);
select is((select replayed from first_canary), false, 'first canary registration is received');
select is(
  (select record_classification from public.resend_sdf_inbound_receipts
   where provider_email_id = 'internal_e2e_sdf_inbound_canary_v1'),
  'internal_e2e',
  'exact marker-bound canary tuple is internal_e2e'
);
select is(
  (select count(*)::integer from public.resend_sdf_inbound_receipts
   where provider_email_id = 'internal_e2e_sdf_inbound_canary_v1'),
  1, 'first canary creates exactly one receipt'
);
select is(
  (select count(*)::integer
   from lws_internal.resend_sdf_inbound_receipt_deliveries
   where webhook_delivery_id = 'internal_e2e_sdf_inbound_delivery_v1'),
  1, 'first canary creates exactly one delivery'
);

create temporary table replayed_canary as
select * from public.register_resend_sdf_inbound_receipt_v1(
  'internal_e2e_sdf_inbound_canary_v1',
  'internal_e2e_sdf_inbound_delivery_v1',
  '<internal-e2e-sdf-inbound-canary-v1@invalid.local>',
  'sdf-inbound-canary@invalid.local',
  'sdf-inbound-canary@invalid.local',
  '2000-01-01T00:00:00.000Z',
  '2962999d3c2a4f05a820c57319af788b77da8bcb53ab209bb8d519f643401d5d'
);
select ok(
  (select replayed from replayed_canary)
  and (select receipt_id from replayed_canary) = (select receipt_id from first_canary),
  'second canary call replays the same receipt'
);
select is(
  (select count(*)::integer from public.resend_sdf_inbound_receipts
   where provider_email_id = 'internal_e2e_sdf_inbound_canary_v1'),
  1, 'canary replay creates no extra receipt'
);
select is(
  (select count(*)::integer
   from lws_internal.resend_sdf_inbound_receipt_deliveries
   where webhook_delivery_id = 'internal_e2e_sdf_inbound_delivery_v1'),
  1, 'canary replay creates no extra delivery'
);

select throws_ok($$
  select * from public.register_resend_sdf_inbound_receipt_v1(
    'signed_canary_conflict_email', 'signed_canary_normal_delivery',
    '<signed-canary-conflict@example.test>', 'attacker@example.test',
    'sdf@lorenzowebsolutions.be', '2030-01-01T10:00:00Z', repeat('c', 64)
  )
$$, 'P0001', 'INBOUND_RECEIPT_CONFLICT', 'conflicting normal fingerprint retains conflict semantics');

select is((select count(*) from public.quote_requests), (select quote_requests from downstream_baseline), 'creates zero quote requests');
select is((select count(*) from public.customer_requests), (select customer_requests from downstream_baseline), 'creates zero customer requests');
select is((select count(*) from public.sdf_projects), (select sdf_projects from downstream_baseline), 'creates zero SDF projects');
select is((select count(*) from public.quote_request_intakes), (select intakes from downstream_baseline), 'creates zero intakes');
select is((select count(*) from public.quote_request_email_jobs), (select email_jobs from downstream_baseline), 'creates zero outbound email jobs');
select is((select count(*) from public.document_inbox_items), (select document_inbox_items from downstream_baseline), 'creates zero Document Inbox items');
select is((select count(*) from storage.objects), (select storage_objects from downstream_baseline), 'creates zero Storage objects');
select is((select count(*) from auth.users), (select auth_users from downstream_baseline), 'creates zero Auth users');

select * from finish();
rollback;
