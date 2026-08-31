begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(14);

insert into public.quote_requests (
  id, request_kind, sdf_package, created_at, name, company, email, phone,
  description, privacy_consent, status, record_classification
) values
  (
    '68000000-0000-4000-8000-000000000001', 'slimme_documentenflow', 'groei',
    '2026-09-01 08:00:00+00', 'Ada Lovelace', 'Analytical Engines BV',
    'ada@example.test', '+32 470 00 00 01', 'Customer projection fixture A.',
    true, 'approved', 'production'
  ),
  (
    '68100000-0000-4000-8000-000000000002', 'slimme_documentenflow', 'start',
    '2026-09-01 09:00:00+00', 'Grace Hopper', null,
    'grace@example.test', null, 'Customer projection fixture B.',
    true, 'approved', 'production'
  );

insert into public.sdf_qualification_intakes (
  quote_request_id, customer_capability_digest, customer_capability_encrypted,
  customer_capability_expires_at
) values
  (
    '68000000-0000-4000-8000-000000000001', repeat('a', 64),
    'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    clock_timestamp() + interval '1 day'
  ),
  (
    '68100000-0000-4000-8000-000000000002', repeat('b', 64),
    'v1.BBBBBBBBBBBBBBBB.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
    clock_timestamp() + interval '1 day'
  );

select is(
  public.inspect_sdf_qualification_intake_v1(repeat('a', 64))->'customer'->>'name',
  'Ada Lovelace',
  'customer capability exposes its request name'
);
select is(public.inspect_sdf_qualification_intake_v1(repeat('a', 64))->'customer'->>'company', 'Analytical Engines BV', 'company is projected when present');
select is(public.inspect_sdf_qualification_intake_v1(repeat('a', 64))->'customer'->>'email', 'ada@example.test', 'email is projected from the same request');
select is(public.inspect_sdf_qualification_intake_v1(repeat('a', 64))->'customer'->>'phone', '+32 470 00 00 01', 'phone is projected from the same request');
select is(public.inspect_sdf_qualification_intake_v1(repeat('a', 64))->>'support_reference', (select support_reference from public.quote_requests where id = '68000000-0000-4000-8000-000000000001'), 'public support reference remains canonical');
select is((public.inspect_sdf_qualification_intake_v1(repeat('a', 64))->>'request_created_at')::timestamptz, '2026-09-01 08:00:00+00'::timestamptz, 'request creation date is projected');
select is(public.inspect_sdf_qualification_intake_v1(repeat('b', 64))->'customer'->>'name', 'Grace Hopper', 'second capability resolves only its own request');
select ok(not (public.inspect_sdf_qualification_intake_v1(repeat('b', 64))->'customer' ? 'company'), 'missing optional company is omitted');
select ok(not (public.inspect_sdf_qualification_intake_v1(repeat('b', 64))->'customer' ? 'phone'), 'missing optional phone is omitted');
select ok(not (public.inspect_sdf_qualification_intake_v1(repeat('a', 64)) ? 'intake_id'), 'customer projection omits internal intake UUID');
select ok(not (public.inspect_sdf_qualification_intake_v1(repeat('a', 64)) ? 'quote_request_id'), 'customer projection omits raw request UUID');
select ok(not (public.inspect_sdf_qualification_intake_v1(repeat('a', 64)) ? 'application_reference'), 'customer projection omits internal application reference');
select is((select array_agg(key order by key) from jsonb_object_keys(public.inspect_sdf_qualification_intake_v1(repeat('a', 64))) key), array['customer','draft','draft_revision','expires_at','request_created_at','status','support_reference','taxonomy_version']::text[], 'customer projection has an exact top-level allowlist');
select throws_ok($$select public.inspect_sdf_qualification_intake_v1(repeat('c', 64))$$, '42501', 'SDF_INTAKE_ACCESS_DENIED', 'unknown capability cannot inspect any customer dossier');

select * from finish();
rollback;