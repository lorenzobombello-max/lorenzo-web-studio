begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table(
  'public', 'quotation_vat_transaction_classifications',
  'server-owned VAT transaction classifications exist'
);
select has_table(
  'public', 'quotation_vat_turnover_snapshots',
  'append-only governed VAT turnover snapshots exist'
);
select has_function(
  'public', 'resolve_quotation_vat_authority_v1', array['uuid', 'date'],
  'canonical VAT authority resolver exists'
);
select has_function(
  'public', 'is_valid_quotation_vat_authority_v1', array['jsonb'],
  'strict VAT authority validator exists'
);
select has_function(
  'public', 'quotation_vat_authority_sha256_v1', array['jsonb'],
  'deterministic VAT governance fingerprint function exists'
);
select has_function(
  'public', 'record_quotation_vat_transaction_classification_v1',
  array['uuid', 'text', 'text', 'text'],
  'service-side transaction classification append API exists'
);
select has_function(
  'public', 'record_quotation_vat_turnover_snapshot_v1',
  array['date', 'bigint', 'text', 'text', 'uuid', 'text'],
  'service-side governed turnover append API exists'
);

select is(
  (select count(*)::integer
   from public.quotation_vat_decision_authorities
   where authority_family = 'LWS_OUTGOING_VAT' and status = 'APPROVED'),
  1,
  'exactly one canonical LWS outgoing VAT authority is approved'
);
select ok(
  (select decision_code = 'BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION'
      and decision_version = '1.0.0'
      and effective_from = '2026-08-08'::date
      and jurisdiction = 'BE'
      and regime_code = 'SMALL_ENTERPRISE_EXEMPTION'
      and vat_treatment = 'EXEMPT'
      and rate_semantics = 'NOT_APPLICABLE'
      and vat_rate = 0
      and invoice_literal = 'Bijzondere vrijstellingsregeling van belasting'
      and threshold_year = 2026
      and annual_threshold_minor = 2500000
      and applicable_threshold_minor = 1000000
      and business_start_date = '2026-08-08'::date
      and elapsed_calendar_days = 219
      and remaining_calendar_days = 146
      and applicability_code = 'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION_V1'
      and unsupported_behavior = 'FAIL_CLOSED'
      and predecessor_authority_id is null
      and authority_sha256 ~ '^[0-9a-f]{64}$'
   from public.quotation_vat_decision_authorities
   where authority_family = 'LWS_OUTGOING_VAT' and status = 'APPROVED'),
  'canonical authority freezes exact treatment, literal, dates, thresholds, and fingerprint'
);
select is(
  (select rtrim(authority_sha256)
   from public.quotation_vat_decision_authorities
   where authority_family = 'LWS_OUTGOING_VAT' and status = 'APPROVED'),
  (select public.quotation_vat_authority_sha256_v1(to_jsonb(authority))
   from public.quotation_vat_decision_authorities as authority
   where authority_family = 'LWS_OUTGOING_VAT' and status = 'APPROVED'),
  'canonical seed fingerprint is reproducible from all governed authority fields'
);
select isnt(
  public.quotation_vat_authority_sha256_v1(authority_document),
  public.quotation_vat_authority_sha256_v1(
    jsonb_set(authority_document, '{approved_at}', '"2026-08-28T00:00:01+00:00"')
  ),
  'approval metadata mutation changes the authority fingerprint'
)
from (
  select to_jsonb(authority) as authority_document
  from public.quotation_vat_decision_authorities as authority
  where authority_family = 'LWS_OUTGOING_VAT' and status = 'APPROVED'
) as governed;
select isnt(
  public.quotation_vat_authority_sha256_v1(authority_document),
  public.quotation_vat_authority_sha256_v1(
    jsonb_set(authority_document, '{effective_until}', '"2026-12-31"')
  ),
  'effectivity mutation changes the authority fingerprint'
)
from (
  select to_jsonb(authority) as authority_document
  from public.quotation_vat_decision_authorities as authority
  where authority_family = 'LWS_OUTGOING_VAT' and status = 'APPROVED'
) as governed;
select is(
  public.quotation_vat_authority_sha256_v1(authority_document),
  public.quotation_vat_authority_sha256_v1(
    jsonb_build_object('approved_at', authority_document->'approved_at')
      || (authority_document - 'approved_at')
  ),
  'authority fingerprint is independent of JSON property insertion order'
)
from (
  select to_jsonb(authority) as authority_document
  from public.quotation_vat_decision_authorities as authority
  where authority_family = 'LWS_OUTGOING_VAT' and status = 'APPROVED'
) as governed;
select ok(
  public.is_valid_quotation_vat_authority_v1(jsonb_build_object(
    'authority_family', 'LWS_OUTGOING_VAT',
    'decision_code', 'BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION',
    'decision_version', '1.0.0',
    'effective_from', '2026-08-08',
    'jurisdiction', 'BE',
    'regime_code', 'SMALL_ENTERPRISE_EXEMPTION',
    'vat_treatment', 'EXEMPT',
    'rate_semantics', 'NOT_APPLICABLE',
    'vat_rate', 0,
    'invoice_literal', 'Bijzondere vrijstellingsregeling van belasting',
    'applicability_code', 'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION_V1',
    'unsupported_behavior', 'FAIL_CLOSED',
    'threshold_year', 2026,
    'applicable_threshold_minor', 1000000
  )),
  'canonical exemption combination is valid'
);
select ok(
  not public.is_valid_quotation_vat_authority_v1(jsonb_build_object(
    'authority_family', 'LWS_OUTGOING_VAT',
    'decision_code', 'BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION',
    'decision_version', '1.0.0',
    'effective_from', '2026-08-08',
    'jurisdiction', 'BE',
    'regime_code', 'SMALL_ENTERPRISE_EXEMPTION',
    'vat_treatment', 'ZERO_RATE',
    'rate_semantics', 'NOT_APPLICABLE',
    'vat_rate', 0,
    'invoice_literal', 'Bijzondere vrijstellingsregeling van belasting',
    'applicability_code', 'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION_V1',
    'unsupported_behavior', 'FAIL_CLOSED',
    'threshold_year', 2026,
    'applicable_threshold_minor', 1000000
  )),
  'zero-rate treatment cannot impersonate the exemption'
);
select ok(
  not public.is_valid_quotation_vat_authority_v1(jsonb_build_object(
    'authority_family', 'LWS_OUTGOING_VAT',
    'decision_code', 'BELGIAN_SMALL_ENTERPRISE_VAT_EXEMPTION',
    'decision_version', '1.0.0',
    'effective_from', '2026-08-08',
    'jurisdiction', 'BE',
    'regime_code', 'SMALL_ENTERPRISE_EXEMPTION',
    'vat_treatment', 'EXEMPT',
    'vat_rate', 0,
    'invoice_literal', 'Bijzondere vrijstellingsregeling kleine ondernemingen',
    'applicability_code', 'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION_V1',
    'unsupported_behavior', 'FAIL_CLOSED',
    'threshold_year', 2026,
    'applicable_threshold_minor', 1000000
  )),
  'missing rate semantics and altered literal are rejected'
);

insert into public.quote_requests (
  id, request_kind, name, company, email, customer_type, enterprise_number,
  enterprise_validation_status, vat_number, vat_validation_status, vat_validated_at,
  billing_address, billing_postal_code, billing_city, billing_country, billing_email,
  website_type, budget, timing, description, privacy_consent, status
) values (
  'bd100000-0000-4000-8000-000000000001', 'website', 'VAT Contact', 'VAT Customer BV',
  'vat-customer@example.test', 'business', '0123456789',
  'format_valid_not_externally_verified', 'BE0123456789', 'valid', '2026-08-28T08:00:00Z',
  'Klantstraat 1', '9000', 'Gent', 'BE', 'billing@example.test',
  'business', 'EUR 3.000', 'flexible', 'Canonical VAT resolver fixture.', true, 'approved'
), (
  'bd100001-0000-4000-8000-000000000002', 'website', 'Foreign Contact', 'Foreign Customer BV',
  'foreign-customer@example.test', 'business', '0123456789',
  'format_valid_not_externally_verified', 'NL012345678B01', 'valid', '2026-08-28T08:00:00Z',
  'Klantstraat 2', '1000', 'Amsterdam', 'NL', 'foreign-billing@example.test',
  'business', 'EUR 3.000', 'flexible', 'Unsupported foreign VAT resolver fixture.', true, 'approved'
);
insert into auth.users (id, email) values (
  'bd110000-0000-4000-8000-000000000001', 'vat-authority-owner@example.test'
);
insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values (
  'bd120000-0000-4000-8000-000000000001',
  'bd110000-0000-4000-8000-000000000001',
  'VAT Authority Owner', 'owner', 'ACTIVE'
);
insert into public.quote_request_intakes (
  id, quote_request_id, status, access_token_hash, access_token_expires_at
) values (
  'bd130000-0000-4000-8000-000000000001',
  'bd100000-0000-4000-8000-000000000001',
  'invited', repeat('7',64), clock_timestamp() + interval '1 day'
);

select throws_ok(
  $$select public.resolve_quotation_vat_authority_v1(
    'bd100000-0000-4000-8000-000000000001', '2026-08-07'
  )$$,
  'P0001', 'QUOTATION_VAT_DECISION_NOT_APPROVED',
  'authority is unavailable before its effective date'
);
select throws_ok(
  $$select public.resolve_quotation_vat_authority_v1(
    'bd100001-0000-4000-8000-000000000002', '2026-08-28'
  )$$,
  'P0001', 'QUOTATION_VAT_CONTEXT_UNSUPPORTED',
  'foreign context fails closed'
);
select throws_ok(
  $$select public.resolve_quotation_vat_authority_v1(
    'bd100000-0000-4000-8000-000000000001', '2026-08-28'
  )$$,
  'P0001', 'QUOTATION_VAT_CONTEXT_REQUIRED',
  'missing server-owned transaction classification fails closed'
);

insert into public.quotation_vat_transaction_classifications (
  classification_id, quote_request_id, context_sha256, classification_code,
  source_reference, source_sha256, classified_by, classified_at
) values (
  'bd200000-0000-4000-8000-000000000001',
  'bd100000-0000-4000-8000-000000000001',
  public.quotation_vat_context_sha256_v1('bd100000-0000-4000-8000-000000000001'),
  'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION',
  'TEST_ONLY:SERVER_CLASSIFICATION', repeat('c', 64), 'TEST', '2026-08-28T08:00:00Z'
);

select throws_ok(
  $$select public.resolve_quotation_vat_authority_v1(
    'bd100000-0000-4000-8000-000000000001', '2026-08-28'
  )$$,
  'P0001', 'QUOTATION_VAT_THRESHOLD_AUTHORITY_REVIEW_REQUIRED',
  'missing turnover state fails closed'
);

insert into public.quotation_vat_turnover_snapshots (
  turnover_snapshot_id, vat_decision_authority_id, threshold_year,
  measurement_watermark, governed_turnover_minor, currency, state,
  source_reference, source_sha256, predecessor_snapshot_id,
  recorded_by, recorded_at
) values (
  'bd300000-0000-4000-8000-000000000001',
  (select vat_decision_authority_id from public.quotation_vat_decision_authorities
   where authority_family = 'LWS_OUTGOING_VAT' and status = 'APPROVED'),
  2026, '2026-08-27', 900000, 'EUR', 'BELOW_OR_AT_THRESHOLD',
  'TEST_ONLY:TURNOVER:STALE', repeat('d', 64), null, 'TEST', '2026-08-27T23:59:59Z'
);
select throws_ok(
  $$select public.resolve_quotation_vat_authority_v1(
    'bd100000-0000-4000-8000-000000000001', '2026-08-28'
  )$$,
  'P0001', 'QUOTATION_VAT_THRESHOLD_AUTHORITY_REVIEW_REQUIRED',
  'stale turnover state fails closed'
);

insert into public.quotation_vat_turnover_snapshots (
  turnover_snapshot_id, vat_decision_authority_id, threshold_year,
  measurement_watermark, governed_turnover_minor, currency, state,
  source_reference, source_sha256, predecessor_snapshot_id,
  recorded_by, recorded_at
) values (
  'bd300000-0000-4000-8000-000000000002',
  (select vat_decision_authority_id from public.quotation_vat_decision_authorities
   where authority_family = 'LWS_OUTGOING_VAT' and status = 'APPROVED'),
  2026, '2026-08-28', 1000000, 'EUR', 'BELOW_OR_AT_THRESHOLD',
  'TEST_ONLY:TURNOVER:CURRENT', repeat('e', 64),
  'bd300000-0000-4000-8000-000000000001', 'TEST', '2026-08-28T08:30:00Z'
);
select is(
  public.resolve_quotation_vat_authority_v1(
    'bd100000-0000-4000-8000-000000000001', '2026-08-28'
  )->>'invoice_literal',
  'Bijzondere vrijstellingsregeling van belasting',
  'supported context at the exact threshold resolves the canonical literal'
);
insert into public.quotation_vat_turnover_snapshots (
  turnover_snapshot_id, vat_decision_authority_id, threshold_year,
  measurement_watermark, governed_turnover_minor, currency, state,
  source_reference, source_sha256, predecessor_snapshot_id,
  recorded_by, recorded_at
)
select
  'bd390000-0000-4000-8000-000000000009', vat_decision_authority_id,
  extract(year from current_date)::integer, current_date, 1000000, 'EUR',
  'BELOW_OR_AT_THRESHOLD', 'TEST_ONLY:TURNOVER:RPC_CURRENT_DATE', repeat('f', 64),
  null, 'TEST', clock_timestamp()
from public.quotation_vat_decision_authorities
where authority_family = 'LWS_OUTGOING_VAT' and status = 'APPROVED';
select throws_ok(
  $$select public.upsert_quotation_business_draft_v2(
    'bd110000-0000-4000-8000-000000000001',
    'bd130000-0000-4000-8000-000000000001', 0,
    'bd140000-0000-4000-8000-000000000001',
    '{"commercial_lines":[],"discount":{},"scope":{},"payment_schedule":{},"validity_days":null}'
  )$$,
  '42501', 'QUOTATION_INTAKE_NOT_AVAILABLE',
  'v2 resolves server-owned terms and VAT before entering the unchanged v1 intake guard'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v2(
    'bd110000-0000-4000-8000-000000000001',
    'bd130000-0000-4000-8000-000000000001', 0,
    'bd140000-0000-4000-8000-000000000002',
    '{"commercial_lines":[],"discount":{},"scope":{},"payment_schedule":{},"validity_days":null,"authority_family":"CALLER_SELECTED"}'
  )$$,
  '22023', 'QUOTATION_BUSINESS_INPUT_INVALID',
  'caller cannot select the VAT authority family'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v2(
    'bd110000-0000-4000-8000-000000000001',
    'bd130000-0000-4000-8000-000000000001', 0,
    'bd140000-0000-4000-8000-000000000003',
    '{"commercial_lines":[],"discount":{},"scope":{},"payment_schedule":{},"validity_days":null,"decision_code":"CALLER_SELECTED"}'
  )$$,
  '22023', 'QUOTATION_BUSINESS_INPUT_INVALID',
  'caller cannot select the VAT decision code'
);

insert into public.quotation_vat_turnover_snapshots (
  turnover_snapshot_id, vat_decision_authority_id, threshold_year,
  measurement_watermark, governed_turnover_minor, currency, state,
  source_reference, source_sha256, predecessor_snapshot_id,
  recorded_by, recorded_at
) values (
  'bd300000-0000-4000-8000-000000000003',
  (select vat_decision_authority_id from public.quotation_vat_decision_authorities
   where authority_family = 'LWS_OUTGOING_VAT' and status = 'APPROVED'),
  2026, '2026-08-29', 1000001, 'EUR', 'AUTHORITY_REVIEW_REQUIRED',
  'TEST_ONLY:TURNOVER:REVIEW', repeat('f', 64),
  'bd300000-0000-4000-8000-000000000002', 'TEST', '2026-08-29T08:30:00Z'
);
select throws_ok(
  $$select public.resolve_quotation_vat_authority_v1(
    'bd100000-0000-4000-8000-000000000001', '2026-08-29'
  )$$,
  'P0001', 'AUTHORITY_REVIEW_REQUIRED',
  'turnover above EUR 10,000 requires authority review without a grace threshold'
);

select * from finish();
rollback;