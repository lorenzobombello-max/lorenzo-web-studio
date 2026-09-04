begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(21);

select ok(
  has_function_privilege('authenticated', 'public.get_operator_submitted_application_pricing_snapshot_v1(uuid,uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.get_operator_submitted_application_pricing_snapshot_v1(uuid,uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.get_operator_submitted_application_pricing_snapshot_v1(uuid,uuid,uuid)', 'execute'),
  'only authenticated callers can execute the pricing snapshot projection'
);

select ok(
  not has_table_privilege('authenticated', 'public.quote_request_pricing_snapshots', 'select')
  and not has_table_privilege('anon', 'public.quote_request_pricing_snapshots', 'select'),
  'the pricing snapshot table remains closed to authenticated and anonymous roles'
);

select ok(
  (select prosecdef and provolatile = 's'
   from pg_proc
   where oid = 'public.get_operator_submitted_application_pricing_snapshot_v1(uuid,uuid,uuid)'::regprocedure)
  and (select proconfig @> array['search_path=public, lws_internal, auth, pg_catalog']
       from pg_proc
       where oid = 'public.get_operator_submitted_application_pricing_snapshot_v1(uuid,uuid,uuid)'::regprocedure),
  'snapshot projection is stable SECURITY DEFINER with a pinned search path'
);

select ok(
  pg_get_functiondef('public.get_operator_submitted_application_pricing_snapshot_v1(uuid,uuid,uuid)'::regprocedure)
    like '%auth.uid() <> p_actor_auth_user_id%'
  and pg_get_functiondef('public.get_operator_submitted_application_pricing_snapshot_v1(uuid,uuid,uuid)'::regprocedure)
    like '%assert_operator_application_actor_v2(p_actor_auth_user_id)%'
  and pg_get_functiondef('public.get_operator_submitted_application_pricing_snapshot_v1(uuid,uuid,uuid)'::regprocedure)
    like '%snapshot.intake_id = p_intake_id%'
  and pg_get_functiondef('public.get_operator_submitted_application_pricing_snapshot_v1(uuid,uuid,uuid)'::regprocedure)
    like '%intake.quote_request_id = p_quote_request_id%'
  and pg_get_functiondef('public.get_operator_submitted_application_pricing_snapshot_v1(uuid,uuid,uuid)'::regprocedure)
    like '%request.request_kind = ''website''%'
  and pg_get_functiondef('public.get_operator_submitted_application_pricing_snapshot_v1(uuid,uuid,uuid)'::regprocedure)
    like '%request.record_classification in (''production'', ''internal_e2e'')%',
  'snapshot projection binds actor, snapshot intake, request, product, and classification'
);

insert into auth.users (id, email) values
  ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'step-2k-owner@example.test'),
  ('bd2ab636-0d42-4069-88a9-60bd97f2b335', 'step-2k-operator-two@example.test'),
  ('d0247fd9-60d5-40bc-a905-6b02024b6420', 'step-2k-operator-three@example.test')
on conflict (id) do nothing;

insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values
  ('2e110000-0000-4000-8000-000000000001', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'Step 2K Owner', 'owner', 'ACTIVE'),
  ('2e110000-0000-4000-8000-000000000002', 'bd2ab636-0d42-4069-88a9-60bd97f2b335', 'Step 2K Operator Two', 'operator', 'ACTIVE')
on conflict (auth_user_id) do update
set role = excluded.role, status = excluded.status;

insert into public.quote_requests (
  id, record_classification, request_kind, website_type, budget, timing,
  name, company, email, phone, description, privacy_consent, status
) values (
  '2e120000-0000-4000-8000-000000000001', 'production', 'website', 'business',
  'EUR 3.200 t/m EUR 6.000', 'flexible', 'Step 2K Fixture', 'Step 2K Company',
  'step-2k-fixture@example.test', null, 'Pricing snapshot projection fixture.', true, 'approved'
);

insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at,
  started_at, submitted_at, confirmation
) values (
  '2e130000-0000-4000-8000-000000000001',
  '2e120000-0000-4000-8000-000000000001',
  'submitted', repeat('e', 64), clock_timestamp() + interval '7 days',
  clock_timestamp(), clock_timestamp(), true
);

insert into public.quote_request_pricing_snapshots (
  id, intake_id, snapshot_contract_version, config_version, config_hash,
  normalized_evidence, calculation, package_advice, budget_evaluation
) values (
  '2e140000-0000-4000-8000-000000000001',
  '2e130000-0000-4000-8000-000000000001',
  2, '1.0.0', repeat('e', 64),
  '{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}',
  '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":180000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000}]}',
  '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}',
  '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}'
);

insert into public.quote_request_pricing_snapshot_integrity (
  snapshot_id, algorithm_version, key_id, mac
) values (
  '2e140000-0000-4000-8000-000000000001',
  'hmac-sha256-v1', 'v1', repeat('e', 64)
);

select set_config('request.jwt.claims', '{"role":"authenticated","aal":"aal1"}', true);
set local role authenticated;
select throws_ok(
  $$select public.get_operator_submitted_application_pricing_snapshot_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2e120000-0000-4000-8000-000000000001',
    '2e130000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'HUMAN_JWT_REQUIRED',
  'authenticated transport without a human subject is rejected'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select is(
  (select array_agg(key order by key) from jsonb_object_keys(
    public.get_operator_submitted_application_pricing_snapshot_v1(
      'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
      '2e120000-0000-4000-8000-000000000001',
      '2e130000-0000-4000-8000-000000000001'
    )
  ) as key),
  array[
    'budget_evaluation','calculation','config_hash','config_version','id','intake_id',
    'normalized_evidence','package_advice','package_definition','recurring_services',
    'snapshot_contract_version'
  ]::text[],
  'OP-01 receives exactly the eleven allowlisted snapshot fields'
);
select ok(
  public.get_operator_submitted_application_pricing_snapshot_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2e120000-0000-4000-8000-000000000001',
    '2e130000-0000-4000-8000-000000000001'
  ) -> 'calculation' =
    '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":180000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000}]}'::jsonb,
  'pricing values retain their exact persisted JSON semantics'
);
select throws_ok(
  $$select public.get_operator_submitted_application_pricing_snapshot_v1(
    'bd2ab636-0d42-4069-88a9-60bd97f2b335',
    '2e120000-0000-4000-8000-000000000001',
    '2e130000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'OPERATOR_IDENTITY_MISMATCH',
  'an authenticated owner cannot spoof another actor UUID'
);
select is(
  public.get_operator_submitted_application_pricing_snapshot_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2e120000-0000-4000-8000-000000000099',
    '2e130000-0000-4000-8000-000000000001'
  ),
  null::jsonb,
  'snapshot cannot cross its bound request context'
);
select is(
  public.get_operator_submitted_application_pricing_snapshot_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2e120000-0000-4000-8000-000000000001',
    '2e130000-0000-4000-8000-000000000099'
  ),
  null::jsonb,
  'request cannot substitute a different intake context'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"bd2ab636-0d42-4069-88a9-60bd97f2b335","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.get_operator_submitted_application_pricing_snapshot_v1(
    'bd2ab636-0d42-4069-88a9-60bd97f2b335',
    '2e120000-0000-4000-8000-000000000001',
    '2e130000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'APPLICATION_SCOPE_DENIED',
  'OP-02 remains outside owner/admin application scope'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"d0247fd9-60d5-40bc-a905-6b02024b6420","role":"authenticated","aal":"aal1"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.get_operator_submitted_application_pricing_snapshot_v1(
    'd0247fd9-60d5-40bc-a905-6b02024b6420',
    '2e120000-0000-4000-8000-000000000001',
    '2e130000-0000-4000-8000-000000000001'
  )$$,
  '42501', 'UNKNOWN_OPERATOR',
  'OP-03 remains unknown to Operator authority'
);
reset role;

set local role service_role;
select throws_ok(
  $$select public.get_operator_submitted_application_pricing_snapshot_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2e120000-0000-4000-8000-000000000001',
    '2e130000-0000-4000-8000-000000000001'
  )$$,
  '42501',
  'permission denied for function get_operator_submitted_application_pricing_snapshot_v1',
  'service role cannot execute the snapshot projection'
);
select is(
  (select row_to_json(result)::jsonb
   from public.get_pricing_snapshot_integrity_for_operator_v1(
     '2e140000-0000-4000-8000-000000000001'
   ) as result),
  jsonb_build_object(
    'algorithm_version', 'hmac-sha256-v1',
    'key_id', 'v1',
    'mac', repeat('e', 64)
  ),
  'existing service-only integrity RPC output remains exact'
);
reset role;

set local role anon;
select throws_ok(
  $$select public.get_operator_submitted_application_pricing_snapshot_v1(
    'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    '2e120000-0000-4000-8000-000000000001',
    '2e130000-0000-4000-8000-000000000001'
  )$$,
  '42501',
  'permission denied for function get_operator_submitted_application_pricing_snapshot_v1',
  'anonymous callers cannot execute the snapshot projection'
);
reset role;

select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'quote_request_pricing_snapshots'
  ),
  'no pricing snapshot RLS policy was introduced'
);

select ok(
  (select relrowsecurity and not relforcerowsecurity
   from pg_class where oid = 'public.quote_request_pricing_snapshots'::regclass),
  'pricing snapshot RLS remains enabled without FORCE RLS'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.quote_request_pricing_snapshots'::regclass
      and tgname = 'trg_quote_request_pricing_snapshots_immutable'
      and not tgisinternal
  ),
  'pricing snapshot immutability trigger remains active'
);

select ok(
  not has_function_privilege(
    'authenticated', 'public.get_pricing_snapshot_integrity_for_operator_v1(uuid)', 'execute'
  )
  and has_function_privilege(
    'service_role', 'public.get_pricing_snapshot_integrity_for_operator_v1(uuid)', 'execute'
  ),
  'integrity RPC authority remains service-only'
);

select is(
  pg_get_function_result(
    'public.get_pricing_snapshot_integrity_for_operator_v1(uuid)'::regprocedure
  ),
  'TABLE(algorithm_version text, key_id text, mac text)',
  'integrity RPC contract remains unchanged'
);

select ok(
  (select calculation from public.quote_request_pricing_snapshots
   where id = '2e140000-0000-4000-8000-000000000001')
    ->> 'knownMinimumMinor' = '180000',
  'pricing snapshot persisted value remains unchanged'
);

select * from finish();
rollback;