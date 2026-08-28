begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(11);

insert into public.quotation_terms_authorities (
  terms_authority_id, terms_id, terms_version, terms_sha256, source_path,
  status, effective_from, approved_by, approved_at
) values (
  'bc100000-0000-4000-8000-000000000001', 'NON_CANONICAL_TERMS', '1.0',
  repeat('a', 64), 'TEST_ONLY', 'APPROVED', '2026-08-28', 'TEST', clock_timestamp()
);

insert into auth.users (id, email) values
  ('bc300000-0000-4000-8000-000000000001', 'authority-selection-owner@example.test');
insert into public.commercial_operators (
  operator_id, auth_user_id, display_name, role, status
) values (
  'bc310000-0000-4000-8000-000000000001',
  'bc300000-0000-4000-8000-000000000001',
  'Authority Selection Owner', 'owner', 'ACTIVE'
);

create temporary table authority_selection_initial_count as
select count(*)::integer as value
from public.quote_request_quotation_business_drafts;

select has_function(
  'public', 'resolve_quotation_terms_authority_v1', array['date'],
  'canonical terms resolver exists'
);
select has_function(
  'public', 'upsert_quotation_business_draft_v2',
  array['uuid', 'uuid', 'bigint', 'uuid', 'jsonb'],
  'authority-minimal business draft entrypoint exists'
);
select has_function(
  'public', 'resolve_quotation_vat_authority_v1', array['uuid', 'date'],
  'canonical VAT resolver exists without a caller-selected authority ID'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.upsert_quotation_business_draft_v2(uuid,uuid,bigint,uuid,jsonb)',
    'execute'
  ),
  'service role can invoke the authority-minimal entrypoint'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.upsert_quotation_business_draft_v2(uuid,uuid,bigint,uuid,jsonb)',
    'execute'
  ),
  'browser operators cannot invoke the authority-minimal entrypoint directly'
);
select is(
  public.resolve_quotation_terms_authority_v1('2026-08-28'::date)->>'terms_id',
  'LWS_GENERAL_TERMS_NL_BE',
  'terms resolver ignores another approved family'
);
select is(
  public.resolve_quotation_terms_authority_v1('2026-08-28'::date)->>'terms_authority_id',
  'b1010000-0000-4000-8000-000000000001',
  'terms resolver returns the immutable canonical authority ID'
);

select throws_ok(
  $$select public.upsert_quotation_business_draft_v2(
    'bc300000-0000-4000-8000-000000000001',
    'bc400000-0000-4000-8000-000000000001', 0,
    'bc500000-0000-4000-8000-000000000001',
    '{"commercial_lines":[],"discount":{},"scope":{},"payment_schedule":{},"validity_days":null,"terms_authority_id":"bc100000-0000-4000-8000-000000000001"}'
  )$$,
  '22023', 'QUOTATION_BUSINESS_INPUT_INVALID',
  'caller-selected terms authority fails before writer execution'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v2(
    'bc300000-0000-4000-8000-000000000001',
    'bc400000-0000-4000-8000-000000000001', 0,
    'bc500000-0000-4000-8000-000000000002',
    '{"commercial_lines":[],"discount":{},"scope":{},"payment_schedule":{},"validity_days":null,"vat_decision_authority_id":"bc200000-0000-4000-8000-000000000001"}'
  )$$,
  '22023', 'QUOTATION_BUSINESS_INPUT_INVALID',
  'caller-selected VAT authority fails before writer execution'
);
select throws_ok(
  $$select public.upsert_quotation_business_draft_v2(
    'bc300000-0000-4000-8000-000000000001',
    'bc400000-0000-4000-8000-000000000001', 0,
    'bc500000-0000-4000-8000-000000000003',
    '{"commercial_lines":[],"discount":{},"scope":{},"payment_schedule":{},"validity_days":null}'
  )$$,
  'P0001', 'QUOTATION_VAT_CONTEXT_REQUIRED',
  'missing governed VAT authority and transaction classification fail closed'
);
select is(
  (select count(*)::integer from public.quote_request_quotation_business_drafts),
  (select value from authority_selection_initial_count),
  'rejected authority selection writes no business draft'
);

select * from finish();
rollback;