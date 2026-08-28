create table public.quotation_seller_authorities (
  seller_authority_id uuid primary key default gen_random_uuid(),
  seller_id text not null,
  seller_version text not null,
  seller_identity jsonb not null,
  seller_identity_sha256 char(64) not null check (seller_identity_sha256 ~ '^[0-9a-f]{64}$'),
  status text not null check (status in ('APPROVED', 'RETIRED')),
  approved_by text not null,
  approved_at timestamptz not null,
  retired_by text,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default clock_timestamp(),
  constraint quotation_seller_authority_version_unique unique (seller_id, seller_version),
  constraint quotation_seller_authority_identity_valid check (
    public.is_valid_quotation_generation_seller_v1(seller_identity)
    and seller_identity_sha256 = encode(extensions.digest(convert_to(seller_identity::text, 'UTF8'), 'sha256'), 'hex')
  ),
  constraint quotation_seller_authority_state_valid check (
    (status = 'APPROVED' and retired_by is null and retired_at is null and retirement_reason is null)
    or (status = 'RETIRED' and nullif(btrim(retired_by), '') is not null
      and retired_at is not null and nullif(btrim(retirement_reason), '') is not null)
  )
);

create unique index quotation_seller_authority_one_approved
on public.quotation_seller_authorities (seller_id)
where status = 'APPROVED';

create table public.quotation_terms_authorities (
  terms_authority_id uuid primary key default gen_random_uuid(),
  terms_id text not null,
  terms_version text not null,
  terms_sha256 char(64) not null check (terms_sha256 ~ '^[0-9a-f]{64}$'),
  source_path text not null,
  status text not null check (status in ('APPROVED', 'RETIRED')),
  effective_from date not null,
  approved_by text not null,
  approved_at timestamptz not null,
  retired_by text,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default clock_timestamp(),
  constraint quotation_terms_authority_version_unique unique (terms_id, terms_version),
  constraint quotation_terms_authority_state_valid check (
    (status = 'APPROVED' and retired_by is null and retired_at is null and retirement_reason is null)
    or (status = 'RETIRED' and nullif(btrim(retired_by), '') is not null
      and retired_at is not null and nullif(btrim(retirement_reason), '') is not null)
  )
);

create unique index quotation_terms_authority_one_approved
on public.quotation_terms_authorities (terms_id)
where status = 'APPROVED';

create table public.quotation_vat_decision_authorities (
  vat_decision_authority_id uuid primary key default gen_random_uuid(),
  decision_code text not null,
  decision_version text not null,
  vat_treatment text not null,
  vat_rate numeric(7,4) not null check (vat_rate >= 0),
  authority_source_identifier text not null,
  status text not null check (status in ('APPROVED', 'RETIRED')),
  approved_by text not null,
  approved_at timestamptz not null,
  retired_by text,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default clock_timestamp(),
  constraint quotation_vat_decision_version_unique unique (decision_code, decision_version),
  constraint quotation_vat_decision_state_valid check (
    (status = 'APPROVED' and retired_by is null and retired_at is null and retirement_reason is null)
    or (status = 'RETIRED' and nullif(btrim(retired_by), '') is not null
      and retired_at is not null and nullif(btrim(retirement_reason), '') is not null)
  )
);

create unique index quotation_vat_decision_one_approved
on public.quotation_vat_decision_authorities (decision_code)
where status = 'APPROVED';

create table public.quotation_business_policy_authorities (
  policy_authority_id uuid primary key default gen_random_uuid(),
  policy_id text not null,
  policy_version text not null,
  exact_pricing_mode text not null check (exact_pricing_mode = 'FIXED'),
  default_validity_days integer not null check (default_validity_days = 30),
  status text not null check (status in ('APPROVED', 'RETIRED')),
  approved_by text not null,
  approved_at timestamptz not null,
  retired_by text,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default clock_timestamp(),
  constraint quotation_business_policy_version_unique unique (policy_id, policy_version),
  constraint quotation_business_policy_state_valid check (
    (status = 'APPROVED' and retired_by is null and retired_at is null and retirement_reason is null)
    or (status = 'RETIRED' and nullif(btrim(retired_by), '') is not null
      and retired_at is not null and nullif(btrim(retirement_reason), '') is not null)
  )
);

create unique index quotation_business_policy_one_approved
on public.quotation_business_policy_authorities (policy_id)
where status = 'APPROVED';

create table public.quote_request_quotation_business_drafts (
  business_draft_id uuid primary key default gen_random_uuid(),
  approval_draft_id uuid not null references public.quote_request_quotation_approval_drafts(id),
  quote_request_id uuid not null references public.quote_requests(id),
  intake_id uuid not null references public.quote_request_intakes(id),
  pricing_snapshot_id uuid not null references public.quote_request_pricing_snapshots(id),
  business_revision bigint not null check (business_revision > 0),
  operator_id uuid not null references public.commercial_operators(operator_id),
  seller_authority_id uuid not null references public.quotation_seller_authorities(seller_authority_id),
  terms_authority_id uuid not null references public.quotation_terms_authorities(terms_authority_id),
  vat_decision_authority_id uuid not null references public.quotation_vat_decision_authorities(vat_decision_authority_id),
  template_authority_id uuid not null references public.quotation_template_authorities(id),
  policy_authority_id uuid not null references public.quotation_business_policy_authorities(policy_authority_id),
  canonical_payload jsonb not null,
  canonical_payload_sha256 char(64) not null check (canonical_payload_sha256 ~ '^[0-9a-f]{64}$'),
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  idempotency_key uuid not null unique,
  result_payload jsonb not null,
  prepared_by_actor text not null,
  prepared_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint quotation_business_draft_revision_unique unique (intake_id, business_revision),
  constraint quotation_business_draft_payload_valid check (
    public.is_valid_quotation_approval_payload_v1(canonical_payload, false)
    and canonical_payload_sha256 = public.quotation_approval_payload_sha256_v1(canonical_payload)
  )
);

create function public.guard_quotation_business_authority_mutation_v1()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'UPDATE'
     and current_setting('lws.quotation_business_authority_transition', true) = 'ACTIVATE_VERSION'
     and old.status = 'APPROVED' and new.status = 'RETIRED'
     and old.retired_by is null and old.retired_at is null and old.retirement_reason is null
     and nullif(btrim(new.retired_by), '') is not null
     and new.retired_at is not null
     and nullif(btrim(new.retirement_reason), '') is not null
     and (to_jsonb(new) - array['status', 'retired_by', 'retired_at', 'retirement_reason']::text[])
       = (to_jsonb(old) - array['status', 'retired_by', 'retired_at', 'retirement_reason']::text[]) then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'QUOTATION_BUSINESS_AUTHORITY_IMMUTABLE';
end;
$$;

create trigger trg_quotation_seller_authority_immutable
before update or delete on public.quotation_seller_authorities
for each row execute function public.guard_quotation_business_authority_mutation_v1();
create trigger trg_quotation_terms_authority_immutable
before update or delete on public.quotation_terms_authorities
for each row execute function public.guard_quotation_business_authority_mutation_v1();
create trigger trg_quotation_vat_authority_immutable
before update or delete on public.quotation_vat_decision_authorities
for each row execute function public.guard_quotation_business_authority_mutation_v1();
create trigger trg_quotation_business_policy_immutable
before update or delete on public.quotation_business_policy_authorities
for each row execute function public.guard_quotation_business_authority_mutation_v1();
create trigger trg_quotation_business_draft_immutable
before update or delete on public.quote_request_quotation_business_drafts
for each row execute function public.guard_quotation_business_authority_mutation_v1();

insert into public.quotation_seller_authorities (
  seller_authority_id, seller_id, seller_version, seller_identity,
  seller_identity_sha256, status, approved_by, approved_at
)
select
  'b1000000-0000-4000-8000-000000000001',
  'LORENZO_WEB_SOLUTIONS',
  '1.0.0',
  identity,
  encode(extensions.digest(convert_to(identity::text, 'UTF8'), 'sha256'), 'hex'),
  'APPROVED',
  'BUSINESS_DECISION:2026-08-28',
  '2026-08-28T00:00:00Z'::timestamptz
from (values (jsonb_build_object(
  'legal_name', 'Lorenzo Bombello',
  'address_line_1', 'Grote Baan 164 bus 1002',
  'address_line_2', null,
  'postal_code', '9920',
  'city', 'Lievegem',
  'country_code', 'BE',
  'enterprise_number', '0742.361.487',
  'vat_number', 'BE 0742.361.487',
  'email', 'info@lorenzowebsolution.be',
  'website', 'https://lorenzowebsolutions.be/',
  'contact_name', null
))) as seller(identity);

insert into public.quotation_terms_authorities (
  terms_authority_id, terms_id, terms_version, terms_sha256, source_path,
  status, effective_from, approved_by, approved_at
) values (
  'b1010000-0000-4000-8000-000000000001',
  'LWS_GENERAL_TERMS_NL_BE',
  '1.0',
  lower('E3898AA99103C52354537550FDA583A2DCA7302329622115ECB39080A5EB4A32'),
  'pages/algemene-voorwaarden.html',
  'APPROVED',
  '2026-08-09',
  'BUSINESS_DECISION:2026-08-28',
  '2026-08-28T00:00:00Z'
);

insert into public.quotation_business_policy_authorities (
  policy_authority_id, policy_id, policy_version, exact_pricing_mode,
  default_validity_days, status, approved_by, approved_at
) values (
  'b1020000-0000-4000-8000-000000000001',
  'QUOTATION_BUSINESS_V1',
  '1.0.0',
  'FIXED',
  30,
  'APPROVED',
  'BUSINESS_DECISION:2026-08-28',
  '2026-08-28T00:00:00Z'
);

create function public.resolve_quotation_seller_authority_v1()
returns public.quotation_seller_authorities
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_authority public.quotation_seller_authorities%rowtype;
begin
  select count(*) into v_count
  from public.quotation_seller_authorities
  where seller_id = 'LORENZO_WEB_SOLUTIONS' and status = 'APPROVED';
  if v_count <> 1 then
    raise exception using errcode = 'P0001', message = 'QUOTATION_SELLER_AUTHORITY_UNAVAILABLE';
  end if;
  select * into strict v_authority
  from public.quotation_seller_authorities
  where seller_id = 'LORENZO_WEB_SOLUTIONS' and status = 'APPROVED';
  return v_authority;
end;
$$;

create function lws_internal.assert_quotation_frozen_rule_coverage_v1(
  p_calculation jsonb,
  p_commercial_lines jsonb
)
returns bigint
language plpgsql
stable
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_line jsonb;
  v_rule jsonb;
  v_fixed_count integer := 0;
  v_fixed_total bigint := 0;
  v_known_minimum bigint;
begin
  if jsonb_typeof(p_calculation) <> 'object'
     or not public.is_jsonb_nonnegative_integer(p_calculation->'knownMinimumMinor')
     or jsonb_typeof(p_calculation->'appliedRules') <> 'array'
     or jsonb_typeof(p_commercial_lines) <> 'array' then
    raise exception using errcode = '22023', message = 'QUOTATION_PRICING_COVERAGE_INPUT_INVALID';
  end if;

  for v_line in select value from jsonb_array_elements(p_commercial_lines)
  loop
    if not public.jsonb_has_exact_keys(v_line, array[
      'rule_id', 'quantity', 'description_context'
    ]) or nullif(btrim(v_line->>'rule_id'), '') is null
       or not public.is_jsonb_positive_number(v_line->'quantity')
       or nullif(btrim(v_line->>'description_context'), '') is null then
      raise exception using errcode = '22023', message = 'COMMERCIAL_LINE_INPUT_INVALID';
    end if;
    if (
      select count(*) from jsonb_array_elements(p_commercial_lines) as duplicate(value)
      where duplicate.value->>'rule_id' = v_line->>'rule_id'
    ) <> 1 then
      raise exception using errcode = '22023', message = 'COMMERCIAL_LINE_DUPLICATE';
    end if;
  end loop;

  if exists (
    select 1 from jsonb_array_elements(p_calculation->'appliedRules') as rule(value)
    where lower(rule.value->>'mode') = 'from'
  ) then
    raise exception using errcode = 'P0001', message = 'QUOTATION_PRICING_FROM_UNRESOLVED';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_calculation->'appliedRules') as rule(value)
    where lower(rule.value->>'mode') = 'manual'
  ) then
    raise exception using errcode = 'P0001', message = 'QUOTATION_PRICING_MANUAL_UNRESOLVED';
  end if;

  for v_rule in select value from jsonb_array_elements(p_calculation->'appliedRules')
  loop
    if lower(v_rule->>'mode') = 'fixed' then
      v_fixed_count := v_fixed_count + 1;
      if not public.is_jsonb_nonnegative_integer(v_rule->'amountMinor')
         or not public.is_jsonb_positive_number(v_rule->'quantity')
         or not public.is_jsonb_nonnegative_integer(v_rule->'knownMinimumContributionMinor')
         or (v_rule->>'knownMinimumContributionMinor')::numeric
              <> trunc((v_rule->>'amountMinor')::numeric * (v_rule->>'quantity')::numeric)
         or (
           select count(*) from jsonb_array_elements(p_commercial_lines) as line(value)
           where line.value->>'rule_id' = v_rule->>'ruleId'
             and (line.value->>'quantity')::numeric = (v_rule->>'quantity')::numeric
         ) <> 1 then
        raise exception using errcode = 'P0001', message = 'QUOTATION_FIXED_RULE_COVERAGE_INCOMPLETE';
      end if;
      v_fixed_total := v_fixed_total + (v_rule->>'knownMinimumContributionMinor')::bigint;
    elsif lower(v_rule->>'mode') = 'included' then
      if (v_rule->>'knownMinimumContributionMinor')::bigint <> 0 then
        raise exception using errcode = 'P0001', message = 'QUOTATION_INCLUDED_RULE_PRICE_INVALID';
      end if;
    else
      raise exception using errcode = 'P0001', message = 'QUOTATION_PRICING_MODE_UNSUPPORTED';
    end if;
  end loop;

  if jsonb_array_length(p_commercial_lines) <> v_fixed_count then
    raise exception using errcode = 'P0001', message = 'QUOTATION_FIXED_RULE_COVERAGE_INCOMPLETE';
  end if;
  v_known_minimum := (p_calculation->>'knownMinimumMinor')::bigint;
  if v_fixed_total <> v_known_minimum then
    raise exception using errcode = 'P0001', message = 'QUOTATION_KNOWN_MINIMUM_MISMATCH';
  end if;
  return v_fixed_total;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode = '22023', message = 'QUOTATION_PRICING_COVERAGE_INPUT_INVALID';
end;
$$;

create function public.activate_quotation_business_authority_version_v1(
  p_actor_auth_user_id uuid,
  p_authority_type text,
  p_authority jsonb,
  p_retirement_reason text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_actor text;
  v_now timestamptz := clock_timestamp();
  v_authority_id uuid;
  v_family_key text;
  v_identity jsonb;
begin
  select * into v_operator from public.commercial_operators
  where auth_user_id = p_actor_auth_user_id;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'QUOTATION_BUSINESS_AUTHORITY_SCOPE_DENIED';
  end if;
  if p_authority_type not in ('SELLER', 'TERMS', 'VAT', 'POLICY')
     or jsonb_typeof(p_authority) <> 'object'
     or nullif(btrim(p_retirement_reason), '') is null then
    raise exception using errcode = '22023', message = 'QUOTATION_BUSINESS_AUTHORITY_INPUT_INVALID';
  end if;
  v_actor := 'OPERATOR:' || v_operator.operator_id::text;

  if p_authority_type = 'SELLER' then
    if not public.jsonb_has_exact_keys(p_authority, array[
      'seller_id', 'seller_version', 'seller_identity'
    ]) or nullif(btrim(p_authority->>'seller_id'), '') is null
       or nullif(btrim(p_authority->>'seller_version'), '') is null
       or not public.is_valid_quotation_generation_seller_v1(p_authority->'seller_identity') then
      raise exception using errcode = '22023', message = 'QUOTATION_BUSINESS_AUTHORITY_INPUT_INVALID';
    end if;
    v_family_key := p_authority->>'seller_id';
  elsif p_authority_type = 'TERMS' then
    if not public.jsonb_has_exact_keys(p_authority, array[
      'terms_id', 'terms_version', 'terms_sha256', 'source_path', 'effective_from'
    ]) or nullif(btrim(p_authority->>'terms_id'), '') is null
       or nullif(btrim(p_authority->>'terms_version'), '') is null
       or (p_authority->>'terms_sha256') !~ '^[0-9a-f]{64}$'
       or nullif(btrim(p_authority->>'source_path'), '') is null then
      raise exception using errcode = '22023', message = 'QUOTATION_BUSINESS_AUTHORITY_INPUT_INVALID';
    end if;
    perform (p_authority->>'effective_from')::date;
    v_family_key := p_authority->>'terms_id';
  elsif p_authority_type = 'VAT' then
    if not public.jsonb_has_exact_keys(p_authority, array[
      'decision_code', 'decision_version', 'vat_treatment', 'vat_rate',
      'authority_source_identifier'
    ]) or nullif(btrim(p_authority->>'decision_code'), '') is null
       or nullif(btrim(p_authority->>'decision_version'), '') is null
       or nullif(btrim(p_authority->>'vat_treatment'), '') is null
       or jsonb_typeof(p_authority->'vat_rate') <> 'number'
       or (p_authority->>'vat_rate')::numeric < 0
       or nullif(btrim(p_authority->>'authority_source_identifier'), '') is null then
      raise exception using errcode = '22023', message = 'QUOTATION_BUSINESS_AUTHORITY_INPUT_INVALID';
    end if;
    v_family_key := p_authority->>'decision_code';
  else
    if not public.jsonb_has_exact_keys(p_authority, array[
      'policy_id', 'policy_version', 'exact_pricing_mode', 'default_validity_days'
    ]) or nullif(btrim(p_authority->>'policy_id'), '') is null
       or nullif(btrim(p_authority->>'policy_version'), '') is null
       or p_authority->>'exact_pricing_mode' <> 'FIXED'
       or p_authority->'default_validity_days' <> '30'::jsonb then
      raise exception using errcode = '22023', message = 'QUOTATION_BUSINESS_AUTHORITY_INPUT_INVALID';
    end if;
    v_family_key := p_authority->>'policy_id';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_authority_type || ':' || v_family_key, 0)
  );
  perform set_config('lws.quotation_business_authority_transition', 'ACTIVATE_VERSION', true);

  if p_authority_type = 'SELLER' then
    update public.quotation_seller_authorities
    set status = 'RETIRED', retired_by = v_actor, retired_at = v_now,
        retirement_reason = p_retirement_reason
    where seller_id = v_family_key and status = 'APPROVED';
    v_identity := p_authority->'seller_identity';
    insert into public.quotation_seller_authorities (
      seller_id, seller_version, seller_identity, seller_identity_sha256,
      status, approved_by, approved_at
    ) values (
      v_family_key, p_authority->>'seller_version', v_identity,
      encode(extensions.digest(convert_to(v_identity::text, 'UTF8'), 'sha256'), 'hex'),
      'APPROVED', v_actor, v_now
    ) returning seller_authority_id into v_authority_id;
  elsif p_authority_type = 'TERMS' then
    update public.quotation_terms_authorities
    set status = 'RETIRED', retired_by = v_actor, retired_at = v_now,
        retirement_reason = p_retirement_reason
    where terms_id = v_family_key and status = 'APPROVED';
    insert into public.quotation_terms_authorities (
      terms_id, terms_version, terms_sha256, source_path, status,
      effective_from, approved_by, approved_at
    ) values (
      v_family_key, p_authority->>'terms_version', p_authority->>'terms_sha256',
      p_authority->>'source_path', 'APPROVED', (p_authority->>'effective_from')::date,
      v_actor, v_now
    ) returning terms_authority_id into v_authority_id;
  elsif p_authority_type = 'VAT' then
    update public.quotation_vat_decision_authorities
    set status = 'RETIRED', retired_by = v_actor, retired_at = v_now,
        retirement_reason = p_retirement_reason
    where decision_code = v_family_key and status = 'APPROVED';
    insert into public.quotation_vat_decision_authorities (
      decision_code, decision_version, vat_treatment, vat_rate,
      authority_source_identifier, status, approved_by, approved_at
    ) values (
      v_family_key, p_authority->>'decision_version', p_authority->>'vat_treatment',
      (p_authority->>'vat_rate')::numeric, p_authority->>'authority_source_identifier',
      'APPROVED', v_actor, v_now
    ) returning vat_decision_authority_id into v_authority_id;
  else
    update public.quotation_business_policy_authorities
    set status = 'RETIRED', retired_by = v_actor, retired_at = v_now,
        retirement_reason = p_retirement_reason
    where policy_id = v_family_key and status = 'APPROVED';
    insert into public.quotation_business_policy_authorities (
      policy_id, policy_version, exact_pricing_mode, default_validity_days,
      status, approved_by, approved_at
    ) values (
      v_family_key, p_authority->>'policy_version', 'FIXED', 30,
      'APPROVED', v_actor, v_now
    ) returning policy_authority_id into v_authority_id;
  end if;
  perform set_config('lws.quotation_business_authority_transition', '', true);
  return jsonb_build_object(
    'authority_id', v_authority_id,
    'authority_type', p_authority_type,
    'family_key', v_family_key,
    'activated_by', v_actor,
    'activated_at', v_now
  );
exception
  when unique_violation then
    raise exception using errcode = 'P0001', message = 'QUOTATION_BUSINESS_AUTHORITY_VERSION_CONFLICT';
  when invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception using errcode = '22023', message = 'QUOTATION_BUSINESS_AUTHORITY_INPUT_INVALID';
end;
$$;

create function public.upsert_quotation_business_draft_v1(
  p_actor_auth_user_id uuid,
  p_intake_id uuid,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_input jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_request public.quote_requests%rowtype;
  v_snapshot public.quote_request_pricing_snapshots%rowtype;
  v_integrity public.quote_request_pricing_snapshot_integrity%rowtype;
  v_seller public.quotation_seller_authorities%rowtype;
  v_terms public.quotation_terms_authorities%rowtype;
  v_vat public.quotation_vat_decision_authorities%rowtype;
  v_template public.quotation_template_authorities%rowtype;
  v_policy public.quotation_business_policy_authorities%rowtype;
  v_previous public.quote_request_quotation_business_drafts%rowtype;
  v_existing public.quote_request_quotation_business_drafts%rowtype;
  v_approval_draft record;
  v_line_input jsonb;
  v_rule jsonb;
  v_lines jsonb := '[]'::jsonb;
  v_customer jsonb;
  v_scope jsonb;
  v_payload jsonb;
  v_result jsonb;
  v_request_fingerprint text;
  v_payload_sha256 text;
  v_actor text;
  v_now timestamptz := clock_timestamp();
  v_revision bigint;
  v_sequence integer := 0;
  v_rule_count integer;
  v_quantity numeric;
  v_unit_minor bigint;
  v_gross_minor bigint;
  v_line_discount bigint;
  v_discount_remaining bigint;
  v_discount_minor bigint;
  v_one_time_minor bigint := 0;
  v_vat_minor bigint;
  v_validity_days integer;
  v_pricing_reference jsonb;
  v_schedule jsonb;
  v_identity_base jsonb;
  v_scope_base jsonb;
begin
  if p_actor_auth_user_id is null or p_intake_id is null or p_idempotency_key is null
     or p_expected_revision is null or p_expected_revision < 0
     or not public.jsonb_has_exact_keys(p_input, array[
       'commercial_lines', 'discount', 'scope', 'vat_decision_authority_id',
       'payment_schedule', 'validity_days', 'terms_authority_id'
     ]) then
    raise exception using errcode = '22023', message = 'QUOTATION_BUSINESS_INPUT_INVALID';
  end if;

  select * into v_operator from public.commercial_operators
  where auth_user_id = p_actor_auth_user_id;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'QUOTATION_BUSINESS_SCOPE_DENIED';
  end if;
  v_actor := 'OPERATOR:' || v_operator.operator_id::text;

  v_request_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'actorAuthUserId', p_actor_auth_user_id,
    'expectedRevision', p_expected_revision,
    'input', p_input,
    'intakeId', p_intake_id
  )::text, 'UTF8'), 'sha256'), 'hex');
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key::text, 0)
  );
  select * into v_existing from public.quote_request_quotation_business_drafts
  where idempotency_key = p_idempotency_key;
  if found then
    if rtrim(v_existing.request_fingerprint) <> v_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed', true);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_intake_id::text, 0));
  select * into v_intake from public.quote_request_intakes where id = p_intake_id for update;
  if not found or v_intake.status not in ('submitted', 'reviewed')
     or v_intake.admin_access_token_hash is null
     or v_intake.admin_access_token_expires_at <= v_now
     or v_intake.admin_access_token_revoked_at is not null then
    raise exception using errcode = '42501', message = 'QUOTATION_INTAKE_NOT_AVAILABLE';
  end if;
  select * into strict v_request from public.quote_requests where id = v_intake.quote_request_id;
  select * into strict v_snapshot from public.quote_request_pricing_snapshots
  where intake_id = p_intake_id;
  select * into strict v_integrity from public.quote_request_pricing_snapshot_integrity
  where snapshot_id = v_snapshot.id;

  v_pricing_reference := jsonb_build_object(
    'snapshot_id', v_snapshot.id,
    'snapshot_contract_version', v_snapshot.snapshot_contract_version,
    'integrity_algorithm_version', v_integrity.algorithm_version,
    'integrity_key_id', v_integrity.key_id,
    'integrity_mac', v_integrity.mac
  );
  if not public.is_current_pricing_snapshot_integrity_valid(
    p_intake_id, v_snapshot.id, v_pricing_reference
  ) then
    raise exception using errcode = 'P0001', message = 'PRICING_INTEGRITY_INVALID';
  end if;

  select * into v_seller from public.resolve_quotation_seller_authority_v1();
  select * into v_terms from public.quotation_terms_authorities
  where terms_authority_id = (p_input->>'terms_authority_id')::uuid and status = 'APPROVED';
  if not found then raise exception using errcode = 'P0001', message = 'QUOTATION_TERMS_NOT_APPROVED'; end if;
  select * into v_vat from public.quotation_vat_decision_authorities
  where vat_decision_authority_id = (p_input->>'vat_decision_authority_id')::uuid and status = 'APPROVED';
  if not found then raise exception using errcode = 'P0001', message = 'QUOTATION_VAT_DECISION_NOT_APPROVED'; end if;
  select * into strict v_template from public.resolve_approved_quotation_template_v1(
    'QUOTATION', 'nl-BE', 'EUR', 1::smallint, 1::smallint, 1::smallint
  );
  select * into strict v_policy from public.quotation_business_policy_authorities
  where policy_id = 'QUOTATION_BUSINESS_V1' and status = 'APPROVED';

  select * into v_previous from public.quote_request_quotation_business_drafts
  where intake_id = p_intake_id order by business_revision desc limit 1;
  v_revision := coalesce(v_previous.business_revision, 0) + 1;
  if p_expected_revision <> v_revision - 1 then
    raise exception using errcode = 'P0001', message = 'STALE_BUSINESS_REVISION';
  end if;

  if jsonb_typeof(p_input->'commercial_lines') <> 'array'
     or jsonb_array_length(p_input->'commercial_lines') < 1 then
    raise exception using errcode = '22023', message = 'COMMERCIAL_LINES_REQUIRED';
  end if;
  if not public.jsonb_has_exact_keys(p_input->'discount', array[
    'discount_type', 'discount_value_minor', 'discount_reason'
  ]) or not public.is_jsonb_nonnegative_integer(p_input->'discount'->'discount_value_minor') then
    raise exception using errcode = '22023', message = 'DISCOUNT_INVALID';
  end if;
  v_discount_minor := (p_input->'discount'->>'discount_value_minor')::bigint;
  if v_discount_minor > 0 and (
    nullif(btrim(p_input->'discount'->>'discount_type'), '') is null
    or nullif(btrim(p_input->'discount'->>'discount_reason'), '') is null
  ) then
    raise exception using errcode = '22023', message = 'DISCOUNT_REASON_REQUIRED';
  end if;
  v_discount_remaining := v_discount_minor;

  for v_line_input in select value from jsonb_array_elements(p_input->'commercial_lines')
  loop
    if not public.jsonb_has_exact_keys(v_line_input, array[
      'rule_id', 'quantity', 'description_context'
    ]) or nullif(btrim(v_line_input->>'rule_id'), '') is null
       or not public.is_jsonb_positive_number(v_line_input->'quantity')
       or nullif(btrim(v_line_input->>'description_context'), '') is null then
      raise exception using errcode = '22023', message = 'COMMERCIAL_LINE_INPUT_INVALID';
    end if;
    select count(*), min(rule.value::text)::jsonb into v_rule_count, v_rule
    from jsonb_array_elements(v_snapshot.calculation->'appliedRules') as rule(value)
    where rule.value->>'ruleId' = v_line_input->>'rule_id';
    if v_rule_count <> 1 then
      raise exception using errcode = 'P0001', message = 'PRICING_RULE_NOT_FOUND';
    end if;
    if upper(v_rule->>'mode') <> v_policy.exact_pricing_mode then
      raise exception using errcode = 'P0001', message = 'PRICING_RULE_NOT_EXACT';
    end if;
    if not public.is_jsonb_nonnegative_integer(v_rule->'amountMinor')
       or not public.is_jsonb_positive_number(v_rule->'quantity')
       or (v_rule->>'quantity')::numeric <> (v_line_input->>'quantity')::numeric then
      raise exception using errcode = 'P0001', message = 'PRICING_RULE_QUANTITY_MISMATCH';
    end if;
    if exists (
      select 1 from jsonb_array_elements(v_lines) as existing(value)
      where existing.value->>'product_or_service_code' = v_line_input->>'rule_id'
    ) then
      raise exception using errcode = '22023', message = 'COMMERCIAL_LINE_DUPLICATE';
    end if;
    v_sequence := v_sequence + 1;
    v_quantity := (v_line_input->>'quantity')::numeric;
    v_unit_minor := (v_rule->>'amountMinor')::bigint;
    v_gross_minor := trunc(v_quantity * v_unit_minor)::bigint;
    if (v_rule->>'knownMinimumContributionMinor')::bigint <> v_gross_minor then
      raise exception using errcode = 'P0001', message = 'PRICING_RULE_AMOUNT_MISMATCH';
    end if;
    v_line_discount := least(v_discount_remaining, v_gross_minor);
    v_discount_remaining := v_discount_remaining - v_line_discount;
    v_one_time_minor := v_one_time_minor + v_gross_minor - v_line_discount;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'line_id', 'pricing-rule:' || (v_line_input->>'rule_id'),
      'sequence', v_sequence,
      'product_or_service_code', v_line_input->>'rule_id',
      'description', v_line_input->>'description_context',
      'quantity', v_quantity,
      'unit', 'item',
      'unit_price_minor', v_unit_minor,
      'discount_minor', v_line_discount,
      'vat_treatment', v_vat.vat_treatment,
      'vat_rate', v_vat.vat_rate,
      'line_net_amount_minor', v_gross_minor - v_line_discount,
      'cost_type', 'ONE_TIME'
    ));
  end loop;
  if v_discount_remaining <> 0 then
    raise exception using errcode = '22023', message = 'DISCOUNT_EXCEEDS_TOTAL';
  end if;

  v_identity_base := jsonb_build_object(
    'source_quote_request_id', v_request.id,
    'source_intake_id', v_intake.id,
    'customer_id', null,
    'legal_name', coalesce(nullif(btrim(v_request.company), ''), v_request.name),
    'contact_name', v_request.name,
    'email', v_request.email,
    'address_line_1', v_request.billing_address,
    'address_line_2', null,
    'postal_code', v_request.billing_postal_code,
    'city', v_request.billing_city,
    'country_code', upper(v_request.billing_country),
    'enterprise_number', v_request.enterprise_number,
    'vat_number', v_request.vat_number,
    'source_fields', jsonb_build_object(
      'legal_name', case when nullif(btrim(v_request.company), '') is null then 'quote_requests.name' else 'quote_requests.company' end,
      'address', 'quote_requests.billing_address'
    )
  );
  v_customer := v_identity_base || jsonb_build_object(
    'snapshot_sha256', encode(extensions.digest(convert_to(v_identity_base::text, 'UTF8'), 'sha256'), 'hex')
  );

  if not public.jsonb_has_exact_keys(p_input->'scope', array[
    'project_title', 'project_type', 'scope_summary', 'requested_languages',
    'included_page_count', 'features', 'copywriting', 'seo', 'hosting',
    'maintenance', 'exclusions', 'assumptions', 'indicative_timing'
  ]) then
    raise exception using errcode = '22023', message = 'PROJECT_SCOPE_INVALID';
  end if;
  v_scope_base := jsonb_build_object(
    'project_id', null,
    'project_title', p_input->'scope'->'project_title',
    'project_type', p_input->'scope'->'project_type',
    'scope_summary', p_input->'scope'->'scope_summary',
    'requested_languages', p_input->'scope'->'requested_languages',
    'included_page_count', p_input->'scope'->'included_page_count',
    'features', p_input->'scope'->'features',
    'copywriting', p_input->'scope'->'copywriting',
    'seo', p_input->'scope'->'seo',
    'hosting', p_input->'scope'->'hosting',
    'maintenance', p_input->'scope'->'maintenance',
    'exclusions', p_input->'scope'->'exclusions',
    'assumptions', p_input->'scope'->'assumptions',
    'indicative_timing', p_input->'scope'->'indicative_timing',
    'source_intake_id', v_intake.id,
    'source_pricing_snapshot_id', v_snapshot.id
  );
  v_scope := v_scope_base || jsonb_build_object(
    'snapshot_sha256', encode(extensions.digest(convert_to(v_scope_base::text, 'UTF8'), 'sha256'), 'hex')
  );

  if p_input->'validity_days' = 'null'::jsonb then
    v_validity_days := v_policy.default_validity_days;
  elsif public.is_jsonb_nonnegative_integer(p_input->'validity_days')
      and (p_input->>'validity_days')::integer > 0 then
    v_validity_days := (p_input->>'validity_days')::integer;
  else
    raise exception using errcode = '22023', message = 'VALIDITY_DAYS_INVALID';
  end if;
  if v_validity_days > 365 then
    raise exception using errcode = '22023', message = 'VALIDITY_DAYS_INVALID';
  end if;

  if not public.jsonb_has_exact_keys(p_input->'payment_schedule', array['milestones']) then
    raise exception using errcode = '22023', message = 'PAYMENT_SCHEDULE_INVALID';
  end if;
  v_schedule := jsonb_build_object(
    'schedule_id', 'quotation-payment-v1-' || substr(v_request_fingerprint, 1, 16),
    'milestones', p_input->'payment_schedule'->'milestones',
    'approved_by', v_actor,
    'approved_at', to_char(v_now at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  );
  if not public.is_valid_quotation_payment_schedule_v1(v_schedule, v_one_time_minor, true) then
    raise exception using errcode = '22023', message = 'PAYMENT_SCHEDULE_INVALID';
  end if;

  v_vat_minor := round(v_one_time_minor::numeric * v_vat.vat_rate / 100)::bigint;
  v_payload := jsonb_build_object(
    'contract_version', 1,
    'source_quote_request_id', v_request.id,
    'source_intake_id', v_intake.id,
    'pricing_snapshot', v_pricing_reference,
    'currency', 'EUR',
    'line_items', v_lines,
    'totals', jsonb_build_object(
      'one_time_subtotal_minor', v_one_time_minor,
      'recurring_subtotal_minor', 0,
      'discount_total_minor', v_discount_minor,
      'vat_base_minor', v_one_time_minor,
      'vat_amount_minor', v_vat_minor,
      'total_gross_minor', v_one_time_minor + v_vat_minor
    ),
    'discount', jsonb_build_object(
      'discount_type', case when v_discount_minor = 0 then null else p_input->'discount'->'discount_type' end,
      'discount_value_minor', v_discount_minor,
      'discount_reason', case when v_discount_minor = 0 then null else p_input->'discount'->'discount_reason' end,
      'approved_by', case when v_discount_minor = 0 then null else to_jsonb(v_actor) end,
      'approved_at', case when v_discount_minor = 0 then null else to_jsonb(to_char(v_now at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')) end
    ),
    'customer_identity', v_customer,
    'project_scope', v_scope,
    'vat_approval', jsonb_build_object(
      'vat_treatment', v_vat.vat_treatment,
      'vat_rate', v_vat.vat_rate,
      'vat_decision_source', v_vat.authority_source_identifier,
      'vat_approved_by', v_actor,
      'vat_approved_at', to_char(v_now at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    ),
    'payment_schedule', v_schedule,
    'validity', jsonb_build_object(
      'valid_from', (v_now at time zone 'Europe/Brussels')::date,
      'valid_until', (v_now at time zone 'Europe/Brussels')::date + v_validity_days,
      'validity_days', v_validity_days,
      'approved_by', v_actor,
      'approved_at', to_char(v_now at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    ),
    'legal_references', jsonb_build_object(
      'terms_reference', v_terms.terms_id,
      'terms_version', v_terms.terms_version,
      'terms_sha256', rtrim(v_terms.terms_sha256),
      'terms_status', 'APPROVED',
      'agreement_template_reference', null,
      'agreement_template_version', null,
      'agreement_template_sha256', null
    )
  );
  if not public.is_valid_quotation_approval_payload_v1(v_payload, true) then
    raise exception using errcode = '22023', message = 'QUOTATION_BUSINESS_PAYLOAD_INVALID';
  end if;
  perform lws_internal.assert_quotation_frozen_rule_coverage_v1(
    v_snapshot.calculation,
    p_input->'commercial_lines'
  );
  v_payload_sha256 := public.quotation_approval_payload_sha256_v1(v_payload);

  select * into strict v_approval_draft from public.upsert_quotation_approval_draft_v1(
    v_request.id, v_intake.id, v_snapshot.id, v_payload,
    p_idempotency_key, v_intake.admin_access_token_hash, v_actor
  );
  v_result := jsonb_build_object(
    'approval_draft_id', v_approval_draft.draft_id,
    'business_revision', v_revision,
    'canonical_payload', v_payload,
    'canonical_payload_sha256', v_payload_sha256,
    'bindings', jsonb_build_object(
      'policy_authority_id', v_policy.policy_authority_id,
      'pricing_snapshot_id', v_snapshot.id,
      'seller_authority_id', v_seller.seller_authority_id,
      'seller_identity', v_seller.seller_identity,
      'template_authority_id', v_template.id,
      'template_id', v_template.template_id,
      'template_version', v_template.template_version,
      'template_sha256', lower(rtrim(v_template.template_sha256)),
      'terms_authority_id', v_terms.terms_authority_id,
      'vat_decision_authority_id', v_vat.vat_decision_authority_id
    ),
    'prepared_by_actor', v_actor,
    'prepared_at', v_now,
    'replayed', false
  );
  insert into public.quote_request_quotation_business_drafts (
    approval_draft_id, quote_request_id, intake_id, pricing_snapshot_id,
    business_revision, operator_id, seller_authority_id, terms_authority_id,
    vat_decision_authority_id, template_authority_id, policy_authority_id,
    canonical_payload, canonical_payload_sha256, request_fingerprint,
    idempotency_key, result_payload, prepared_by_actor, prepared_at
  ) values (
    v_approval_draft.draft_id, v_request.id, v_intake.id, v_snapshot.id,
    v_revision, v_operator.operator_id, v_seller.seller_authority_id,
    v_terms.terms_authority_id, v_vat.vat_decision_authority_id,
    v_template.id, v_policy.policy_authority_id, v_payload, v_payload_sha256,
    v_request_fingerprint, p_idempotency_key, v_result, v_actor, v_now
  );
  return v_result;
exception
  when invalid_text_representation then
    raise exception using errcode = '22023', message = 'QUOTATION_BUSINESS_INPUT_INVALID';
end;
$$;

alter table public.quotation_seller_authorities enable row level security;
alter table public.quotation_seller_authorities force row level security;
alter table public.quotation_terms_authorities enable row level security;
alter table public.quotation_terms_authorities force row level security;
alter table public.quotation_vat_decision_authorities enable row level security;
alter table public.quotation_vat_decision_authorities force row level security;
alter table public.quotation_business_policy_authorities enable row level security;
alter table public.quotation_business_policy_authorities force row level security;
alter table public.quote_request_quotation_business_drafts enable row level security;
alter table public.quote_request_quotation_business_drafts force row level security;

revoke all privileges on table public.quotation_seller_authorities from public, anon, authenticated, service_role;
revoke all privileges on table public.quotation_terms_authorities from public, anon, authenticated, service_role;
revoke all privileges on table public.quotation_vat_decision_authorities from public, anon, authenticated, service_role;
revoke all privileges on table public.quotation_business_policy_authorities from public, anon, authenticated, service_role;
revoke all privileges on table public.quote_request_quotation_business_drafts from public, anon, authenticated, service_role;
revoke all on function public.guard_quotation_business_authority_mutation_v1() from public, anon, authenticated, service_role;
revoke all on function lws_internal.assert_quotation_frozen_rule_coverage_v1(jsonb, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.resolve_quotation_seller_authority_v1() from public, anon, authenticated, service_role;
revoke all on function public.activate_quotation_business_authority_version_v1(uuid, text, jsonb, text) from public, anon, authenticated, service_role;
revoke all on function public.upsert_quotation_business_draft_v1(uuid, uuid, bigint, uuid, jsonb) from public, anon, authenticated, service_role;
grant execute on function public.resolve_quotation_seller_authority_v1() to service_role;
grant execute on function public.activate_quotation_business_authority_version_v1(uuid, text, jsonb, text) to service_role;
grant execute on function public.upsert_quotation_business_draft_v1(uuid, uuid, bigint, uuid, jsonb) to service_role;

comment on function public.upsert_quotation_business_draft_v1(uuid, uuid, bigint, uuid, jsonb) is
  'Service-side owner/admin quotation business authority. Resolves immutable seller, approved template and terms, governed VAT, frozen FIXED pricing, canonical payload, revision audit, and existing approval draft without exposing capability or pricing authority to the browser.';