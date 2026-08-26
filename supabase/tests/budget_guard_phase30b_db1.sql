begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(26);

insert into public.quote_requests (
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status
) values
  ('30000000-0000-0000-0000-000000000001', 'Historical evidence', 'historical@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'Historical quote form fixture.', true, 'approved'),
  ('30000001-0000-0000-0000-000000000002', 'Basic structure', 'basic@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'Basic structure fixture.', true, 'approved'),
  ('30000002-0000-0000-0000-000000000003', 'Extended structure', 'extended@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'Extended structure fixture.', true, 'approved'),
  ('30000003-0000-0000-0000-000000000004', 'Unsure structure', 'unsure@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'Unsure structure fixture.', true, 'approved'),
  ('30000004-0000-0000-0000-000000000005', 'Orchestrated structure', 'orchestrated@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'Orchestrated structure fixture.', true, 'approved'),
  ('30000005-0000-0000-0000-000000000006', 'Rollback structure', 'rollback@example.test', 'business', 'EUR 3.000 - EUR 6.000', 'flexible', 'Rollback structure fixture.', true, 'approved');

insert into public.quote_request_intakes (
  quote_request_id, access_token_hash, access_token_expires_at,
  status, confirmation, quote_form_details, created_at
) values
  ('30000000-0000-0000-0000-000000000001', repeat('a', 64), clock_timestamp() + interval '1 day', 'invited', false, '{"classification":"extended","form_count":1}'::jsonb, clock_timestamp()),
  ('30000001-0000-0000-0000-000000000002', repeat('b', 64), clock_timestamp() + interval '1 day', 'invited', false, null, clock_timestamp()),
  ('30000002-0000-0000-0000-000000000003', repeat('c', 64), clock_timestamp() + interval '1 day', 'invited', false, null, clock_timestamp()),
  ('30000003-0000-0000-0000-000000000004', repeat('d', 64), clock_timestamp() + interval '1 day', 'invited', false, null, clock_timestamp()),
  ('30000004-0000-0000-0000-000000000005', repeat('e', 64), clock_timestamp() + interval '1 day', 'invited', false, null, clock_timestamp()),
  ('30000005-0000-0000-0000-000000000006', repeat('f', 64), clock_timestamp() + interval '1 day', 'invited', false, null, clock_timestamp());

select lives_ok(
  $$
    select *
    from public.update_quote_request_intake_evidence(
      repeat('a', 64),
      '{"quote_form_details":{"classification":"extended","form_count":1}}'::jsonb
    )
  $$,
  'historical payload without structure_scope remains valid'
);
select lives_ok(
  $$select * from public.update_quote_request_intake_evidence(repeat('b', 64), '{"quote_form_details":{"structure_scope":"basic_single_section"}}'::jsonb)$$,
  'basic_single_section is accepted'
);
select lives_ok(
  $$select * from public.update_quote_request_intake_evidence(repeat('c', 64), '{"quote_form_details":{"structure_scope":"extended_standard_structure"}}'::jsonb)$$,
  'extended_standard_structure is accepted'
);
select lives_ok(
  $$select * from public.update_quote_request_intake_evidence(repeat('d', 64), '{"quote_form_details":{"structure_scope":"unsure_or_other"}}'::jsonb)$$,
  'unsure_or_other is accepted'
);

select throws_matching(
  $$select * from public.update_quote_request_intake_evidence(repeat('b', 64), '{"quote_form_details":{"structure_scope":"unknown"}}'::jsonb)$$,
  'INVALID_QUOTE_FORM_DETAILS',
  'unknown structure_scope string is rejected'
);
select throws_matching(
  $$select * from public.update_quote_request_intake_evidence(repeat('b', 64), '{"quote_form_details":{"structure_scope":1}}'::jsonb)$$,
  'INVALID_QUOTE_FORM_DETAILS',
  'numeric structure_scope is rejected'
);
select throws_matching(
  $$select * from public.update_quote_request_intake_evidence(repeat('b', 64), '{"quote_form_details":{"structure_scope":true}}'::jsonb)$$,
  'INVALID_QUOTE_FORM_DETAILS',
  'boolean structure_scope is rejected'
);
select throws_matching(
  $$select * from public.update_quote_request_intake_evidence(repeat('b', 64), '{"quote_form_details":{"structure_scope":[]}}'::jsonb)$$,
  'INVALID_QUOTE_FORM_DETAILS',
  'array structure_scope is rejected'
);
select throws_matching(
  $$select * from public.update_quote_request_intake_evidence(repeat('b', 64), '{"quote_form_details":{"structure_scope":{}}}'::jsonb)$$,
  'INVALID_QUOTE_FORM_DETAILS',
  'object structure_scope is rejected'
);
select throws_matching(
  $$select * from public.update_quote_request_intake_evidence(repeat('b', 64), '{"quote_form_details":{"structure_scope":"basic_single_section","unexpected":true}}'::jsonb)$$,
  'INVALID_QUOTE_FORM_DETAILS',
  'unknown extra quote_form_details key remains rejected'
);

select is(
  (select quote_form_details->>'classification' from public.quote_request_intakes where access_token_hash = repeat('a', 64)),
  'extended',
  'legacy classification remains backwards-compatible'
);
select is(
  (select quote_form_details->>'structure_scope' from public.quote_request_intakes where access_token_hash = repeat('c', 64)),
  'extended_standard_structure',
  'bridge stores structure_scope exactly'
);
select is(
  (
    select intake_data->'quote_form_details'->>'structure_scope'
    from public.inspect_quote_request_intake_details_v2(repeat('c', 64))
  ),
  'extended_standard_structure',
  'inspect v2 returns structure_scope exactly'
);
select ok(
  not (
    select intake_data->'quote_form_details' ? 'structure_scope'
    from public.inspect_quote_request_intake_details_v2(repeat('a', 64))
  ),
  'historical record remains without a synthesized structure_scope'
);

select is(
  (
    select outcome
    from public.update_quote_request_intake_with_evidence(
      repeat('e', 64),
      'save_draft',
      '{"business_description":"Atomic DB1 draft"}'::jsonb,
      '{"quote_form_details":{"structure_scope":"extended_standard_structure"}}'::jsonb
    )
  ),
  'saved',
  'orchestrator draft-save accepts the expanded evidence contract'
);
select is(
  (select quote_form_details->>'structure_scope' from public.quote_request_intakes where access_token_hash = repeat('e', 64)),
  'extended_standard_structure',
  'orchestrator draft-save stores structure_scope transactionally'
);
select throws_matching(
  $$
    select *
    from public.update_quote_request_intake_with_evidence(
      repeat('f', 64),
      'submit',
      '{"business_description":"Incomplete submit"}'::jsonb,
      '{"quote_form_details":{"structure_scope":"basic_single_section"}}'::jsonb,
      repeat('9', 64),
      clock_timestamp() + interval '1 day'
    )
  $$,
  'INCOMPLETE_INTAKE_SUBMISSION',
  'forced legacy failure aborts the orchestrated operation'
);
select is(
  (select quote_form_details from public.quote_request_intakes where access_token_hash = repeat('f', 64)),
  null::jsonb,
  'forced failure fully rolls back structure_scope evidence'
);

select ok(
  not has_function_privilege('anon', 'public.update_quote_request_intake_evidence(text,jsonb)', 'execute'),
  'anon cannot execute the bridge'
);
select ok(
  not has_function_privilege('authenticated', 'public.update_quote_request_intake_evidence(text,jsonb)', 'execute'),
  'authenticated cannot execute the bridge'
);
select ok(
  not has_function_privilege('anon', 'public.update_quote_request_intake_with_evidence(text,text,jsonb,jsonb,text,timestamp with time zone)', 'execute'),
  'anon cannot execute the orchestrator'
);
select ok(
  not has_function_privilege('authenticated', 'public.update_quote_request_intake_with_evidence(text,text,jsonb,jsonb,text,timestamp with time zone)', 'execute'),
  'authenticated cannot execute the orchestrator'
);
select ok(
  has_function_privilege('service_role', 'public.update_quote_request_intake_evidence(text,jsonb)', 'execute'),
  'service role retains bridge execute privilege'
);
select ok(
  has_function_privilege('service_role', 'public.update_quote_request_intake_with_evidence(text,text,jsonb,jsonb,text,timestamp with time zone)', 'execute'),
  'service role retains orchestrator execute privilege'
);

set local role service_role;
select is(
  (
    select outcome
    from public.update_quote_request_intake_evidence(
      repeat('d', 64),
      '{"quote_form_details":{"structure_scope":"unsure_or_other"}}'::jsonb
    )
  ),
  'saved',
  'service-role bridge path remains functional'
);
select is(
  (
    select outcome
    from public.update_quote_request_intake_with_evidence(
      repeat('e', 64),
      'save_draft',
      '{"business_description":"Service-role DB1 draft"}'::jsonb,
      '{"quote_form_details":{"structure_scope":"extended_standard_structure"}}'::jsonb
    )
  ),
  'saved',
  'service-role orchestrator path remains functional'
);
reset role;

select * from finish();
rollback;