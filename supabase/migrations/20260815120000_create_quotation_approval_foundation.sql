create function public.jsonb_has_exact_keys(p_value jsonb, p_keys text[])
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_value) = 'object'
    and p_value ?& p_keys
    and (select count(*) from jsonb_object_keys(p_value)) = cardinality(p_keys)
$$;

create function public.is_jsonb_nonnegative_integer(p_value jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_value) = 'number'
    and p_value::text ~ '^\d+$'
$$;

create function public.is_jsonb_positive_number(p_value jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_value) = 'number'
    and (p_value::text)::numeric > 0
$$;

create function public.is_iso_utc_timestamp(p_value jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_value) = 'string'
    and p_value #>> '{}' ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$'
$$;

create function public.is_sha256_jsonb(p_value jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_value) = 'string'
    and p_value #>> '{}' ~ '^[0-9a-f]{64}$'
$$;

create function public.is_valid_quotation_lines_v1(p_lines jsonb)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  v_line jsonb;
  v_line_ids text[] := '{}';
  v_sequences bigint[] := '{}';
  v_quantity numeric;
  v_unit_price numeric;
  v_discount numeric;
  v_line_net numeric;
begin
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 1 then
    return false;
  end if;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    if not public.jsonb_has_exact_keys(v_line, array[
      'line_id', 'sequence', 'product_or_service_code', 'description',
      'quantity', 'unit', 'unit_price_minor', 'discount_minor',
      'vat_treatment', 'vat_rate', 'line_net_amount_minor', 'cost_type'
    ])
      or jsonb_typeof(v_line->'line_id') <> 'string'
      or nullif(btrim(v_line->>'line_id'), '') is null
      or jsonb_typeof(v_line->'product_or_service_code') <> 'string'
      or nullif(btrim(v_line->>'product_or_service_code'), '') is null
      or jsonb_typeof(v_line->'description') <> 'string'
      or nullif(btrim(v_line->>'description'), '') is null
      or jsonb_typeof(v_line->'unit') <> 'string'
      or nullif(btrim(v_line->>'unit'), '') is null
      or not public.is_jsonb_nonnegative_integer(v_line->'sequence')
      or (v_line->>'sequence')::bigint < 1
      or not public.is_jsonb_positive_number(v_line->'quantity')
      or not public.is_jsonb_nonnegative_integer(v_line->'unit_price_minor')
      or not public.is_jsonb_nonnegative_integer(v_line->'discount_minor')
      or not public.is_jsonb_nonnegative_integer(v_line->'line_net_amount_minor')
      or jsonb_typeof(v_line->'vat_treatment') <> 'string'
      or nullif(btrim(v_line->>'vat_treatment'), '') is null
      or not (
        jsonb_typeof(v_line->'vat_rate') = 'number'
        and (v_line->>'vat_rate')::numeric >= 0
      )
      or v_line->>'cost_type' not in ('ONE_TIME', 'RECURRING') then
      return false;
    end if;

    v_quantity := (v_line->>'quantity')::numeric;
    v_unit_price := (v_line->>'unit_price_minor')::numeric;
    v_discount := (v_line->>'discount_minor')::numeric;
    v_line_net := (v_line->>'line_net_amount_minor')::numeric;

    if v_discount > trunc(v_quantity * v_unit_price)
       or v_line_net <> trunc(v_quantity * v_unit_price) - v_discount
       or (v_line->>'line_id') = any(v_line_ids)
       or (v_line->>'sequence')::bigint = any(v_sequences) then
      return false;
    end if;

    v_line_ids := array_append(v_line_ids, v_line->>'line_id');
    v_sequences := array_append(v_sequences, (v_line->>'sequence')::bigint);
  end loop;

  return true;
exception
  when others then
    return false;
end;
$$;

create function public.is_valid_quotation_discount_v1(
  p_discount jsonb,
  p_require_approval boolean
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select public.jsonb_has_exact_keys(p_discount, array[
    'discount_type', 'discount_value_minor', 'discount_reason',
    'approved_by', 'approved_at'
  ])
    and public.is_jsonb_nonnegative_integer(p_discount->'discount_value_minor')
    and (
      (p_discount->>'discount_value_minor')::numeric = 0
      or (
        jsonb_typeof(p_discount->'discount_type') = 'string'
        and nullif(btrim(p_discount->>'discount_type'), '') is not null
        and jsonb_typeof(p_discount->'discount_reason') = 'string'
        and nullif(btrim(p_discount->>'discount_reason'), '') is not null
        and jsonb_typeof(p_discount->'approved_by') = 'string'
        and nullif(btrim(p_discount->>'approved_by'), '') is not null
        and public.is_iso_utc_timestamp(p_discount->'approved_at')
      )
    )
    and (
      not p_require_approval
      or (p_discount->>'discount_value_minor')::numeric = 0
      or public.is_iso_utc_timestamp(p_discount->'approved_at')
    )
$$;

create function public.is_valid_quotation_vat_approval_v1(
  p_vat jsonb,
  p_require_approval boolean
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select public.jsonb_has_exact_keys(p_vat, array[
    'vat_treatment', 'vat_rate', 'vat_decision_source',
    'vat_approved_by', 'vat_approved_at'
  ])
    and (
      not p_require_approval
      and p_vat->'vat_treatment' = 'null'::jsonb
      and p_vat->'vat_rate' = 'null'::jsonb
      and p_vat->'vat_decision_source' = 'null'::jsonb
      and p_vat->'vat_approved_by' = 'null'::jsonb
      and p_vat->'vat_approved_at' = 'null'::jsonb
      or (
        jsonb_typeof(p_vat->'vat_treatment') = 'string'
        and nullif(btrim(p_vat->>'vat_treatment'), '') is not null
        and jsonb_typeof(p_vat->'vat_rate') = 'number'
        and (p_vat->>'vat_rate')::numeric >= 0
        and jsonb_typeof(p_vat->'vat_decision_source') = 'string'
        and nullif(btrim(p_vat->>'vat_decision_source'), '') is not null
        and jsonb_typeof(p_vat->'vat_approved_by') = 'string'
        and nullif(btrim(p_vat->>'vat_approved_by'), '') is not null
        and public.is_iso_utc_timestamp(p_vat->'vat_approved_at')
      )
    )
$$;

create function public.is_valid_quotation_payment_schedule_v1(
  p_schedule jsonb,
  p_one_time_total_minor bigint,
  p_require_approval boolean
)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  v_milestone jsonb;
  v_sequences bigint[] := '{}';
  v_percentage_total numeric := 0;
  v_amount_total numeric := 0;
  v_percentage_count integer := 0;
  v_amount_count integer := 0;
begin
  if not public.jsonb_has_exact_keys(p_schedule, array[
    'schedule_id', 'milestones', 'approved_by', 'approved_at'
  ])
    or jsonb_typeof(p_schedule->'schedule_id') <> 'string'
    or nullif(btrim(p_schedule->>'schedule_id'), '') is null
    or jsonb_typeof(p_schedule->'milestones') <> 'array'
    or jsonb_array_length(p_schedule->'milestones') < 1
    or (
      p_require_approval
      and (
        jsonb_typeof(p_schedule->'approved_by') <> 'string'
        or nullif(btrim(p_schedule->>'approved_by'), '') is null
        or not public.is_iso_utc_timestamp(p_schedule->'approved_at')
      )
    ) then
    return false;
  end if;

  for v_milestone in select value from jsonb_array_elements(p_schedule->'milestones')
  loop
    if not public.jsonb_has_exact_keys(v_milestone, array[
      'sequence', 'label', 'percentage', 'amount_minor', 'trigger',
      'due_terms_days', 'recurring_cycle'
    ])
      or not public.is_jsonb_nonnegative_integer(v_milestone->'sequence')
      or (v_milestone->>'sequence')::bigint < 1
      or (v_milestone->>'sequence')::bigint = any(v_sequences)
      or jsonb_typeof(v_milestone->'label') <> 'string'
      or nullif(btrim(v_milestone->>'label'), '') is null
      or jsonb_typeof(v_milestone->'trigger') <> 'string'
      or nullif(btrim(v_milestone->>'trigger'), '') is null
      or not public.is_jsonb_nonnegative_integer(v_milestone->'due_terms_days')
      or not (
        v_milestone->'recurring_cycle' = 'null'::jsonb
        or jsonb_typeof(v_milestone->'recurring_cycle') = 'string'
      )
      or not (
        (jsonb_typeof(v_milestone->'percentage') = 'number'
          and (v_milestone->>'percentage')::numeric >= 0
          and v_milestone->'amount_minor' = 'null'::jsonb)
        or (v_milestone->'percentage' = 'null'::jsonb
          and public.is_jsonb_nonnegative_integer(v_milestone->'amount_minor'))
      ) then
      return false;
    end if;

    if v_milestone->'percentage' <> 'null'::jsonb then
      v_percentage_count := v_percentage_count + 1;
      v_percentage_total := v_percentage_total + (v_milestone->>'percentage')::numeric;
    else
      v_amount_count := v_amount_count + 1;
      v_amount_total := v_amount_total + (v_milestone->>'amount_minor')::numeric;
    end if;

    v_sequences := array_append(v_sequences, (v_milestone->>'sequence')::bigint);
  end loop;

  return (
    v_percentage_count = jsonb_array_length(p_schedule->'milestones')
    and v_percentage_total = 100
  ) or (
    v_amount_count = jsonb_array_length(p_schedule->'milestones')
    and v_amount_total = p_one_time_total_minor
  );
exception
  when others then
    return false;
end;
$$;

create function public.is_valid_quotation_validity_v1(
  p_validity jsonb,
  p_require_approval boolean
)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  v_from date;
  v_until date;
  v_days integer;
begin
  if not public.jsonb_has_exact_keys(p_validity, array[
    'valid_from', 'valid_until', 'validity_days', 'approved_by', 'approved_at'
  ])
    or jsonb_typeof(p_validity->'valid_from') <> 'string'
    or jsonb_typeof(p_validity->'valid_until') <> 'string'
    or not public.is_jsonb_nonnegative_integer(p_validity->'validity_days')
    or (p_validity->>'validity_days')::integer < 1
    or (
      p_require_approval
      and (
        jsonb_typeof(p_validity->'approved_by') <> 'string'
        or nullif(btrim(p_validity->>'approved_by'), '') is null
        or not public.is_iso_utc_timestamp(p_validity->'approved_at')
      )
    ) then
    return false;
  end if;

  v_from := (p_validity->>'valid_from')::date;
  v_until := (p_validity->>'valid_until')::date;
  v_days := (p_validity->>'validity_days')::integer;
  return v_until > v_from and v_until - v_from = v_days;
exception
  when others then
    return false;
end;
$$;

create function public.is_valid_quotation_identity_v1(p_identity jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select public.jsonb_has_exact_keys(p_identity, array[
    'source_quote_request_id', 'source_intake_id', 'customer_id',
    'legal_name', 'contact_name', 'email', 'address_line_1', 'address_line_2',
    'postal_code', 'city', 'country_code', 'enterprise_number', 'vat_number',
    'source_fields', 'snapshot_sha256'
  ])
    and jsonb_typeof(p_identity->'source_quote_request_id') = 'string'
    and jsonb_typeof(p_identity->'source_intake_id') = 'string'
    and (p_identity->>'source_quote_request_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and (p_identity->>'source_intake_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and (
      p_identity->'customer_id' = 'null'::jsonb
      or (
        jsonb_typeof(p_identity->'customer_id') = 'string'
        and nullif(btrim(p_identity->>'customer_id'), '') is not null
      )
    )
    and jsonb_typeof(p_identity->'legal_name') = 'string'
    and nullif(btrim(p_identity->>'legal_name'), '') is not null
    and jsonb_typeof(p_identity->'email') = 'string'
    and p_identity->>'email' ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    and jsonb_typeof(p_identity->'address_line_1') = 'string'
    and nullif(btrim(p_identity->>'address_line_1'), '') is not null
    and jsonb_typeof(p_identity->'city') = 'string'
    and nullif(btrim(p_identity->>'city'), '') is not null
    and jsonb_typeof(p_identity->'country_code') = 'string'
    and p_identity->>'country_code' ~ '^[A-Z]{2}$'
    and (
      p_identity->'postal_code' = 'null'::jsonb
      or jsonb_typeof(p_identity->'postal_code') = 'string'
    )
    and jsonb_typeof(p_identity->'source_fields') = 'object'
    and (select count(*) from jsonb_object_keys(p_identity->'source_fields')) > 0
    and public.is_sha256_jsonb(p_identity->'snapshot_sha256')
$$;

create function public.is_valid_quotation_scope_v1(p_scope jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select public.jsonb_has_exact_keys(p_scope, array[
    'project_id', 'project_title', 'project_type', 'scope_summary',
    'requested_languages', 'included_page_count', 'features', 'copywriting',
    'seo', 'hosting', 'maintenance', 'exclusions', 'assumptions',
    'indicative_timing', 'source_intake_id', 'source_pricing_snapshot_id',
    'snapshot_sha256'
  ])
    and (
      p_scope->'project_id' = 'null'::jsonb
      or (
        jsonb_typeof(p_scope->'project_id') = 'string'
        and nullif(btrim(p_scope->>'project_id'), '') is not null
      )
    )
    and jsonb_typeof(p_scope->'project_title') = 'string'
    and nullif(btrim(p_scope->>'project_title'), '') is not null
    and jsonb_typeof(p_scope->'project_type') = 'string'
    and nullif(btrim(p_scope->>'project_type'), '') is not null
    and jsonb_typeof(p_scope->'scope_summary') = 'string'
    and nullif(btrim(p_scope->>'scope_summary'), '') is not null
    and jsonb_typeof(p_scope->'requested_languages') = 'array'
    and jsonb_array_length(p_scope->'requested_languages') > 0
    and jsonb_typeof(p_scope->'features') = 'array'
    and public.is_jsonb_nonnegative_integer(p_scope->'included_page_count')
    and jsonb_typeof(p_scope->'exclusions') = 'array'
    and jsonb_typeof(p_scope->'assumptions') = 'array'
    and (p_scope->>'source_intake_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and (p_scope->>'source_pricing_snapshot_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and public.is_sha256_jsonb(p_scope->'snapshot_sha256')
$$;

create function public.is_valid_quotation_legal_references_v1(
  p_legal jsonb,
  p_require_approval boolean
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select public.jsonb_has_exact_keys(p_legal, array[
    'terms_reference', 'terms_version', 'terms_sha256', 'terms_status',
    'agreement_template_reference', 'agreement_template_version',
    'agreement_template_sha256'
  ])
    and p_legal->>'terms_status' in ('UNAPPROVED', 'APPROVED')
    and (
      not p_require_approval
      or p_legal->>'terms_status' = 'APPROVED'
    )
    and (
      p_legal->>'terms_status' <> 'APPROVED'
      or (
        jsonb_typeof(p_legal->'terms_reference') = 'string'
        and nullif(btrim(p_legal->>'terms_reference'), '') is not null
        and jsonb_typeof(p_legal->'terms_version') = 'string'
        and nullif(btrim(p_legal->>'terms_version'), '') is not null
        and public.is_sha256_jsonb(p_legal->'terms_sha256')
      )
    )
    and (
      p_legal->'agreement_template_reference' = 'null'::jsonb
      or (
        jsonb_typeof(p_legal->'agreement_template_reference') = 'string'
        and jsonb_typeof(p_legal->'agreement_template_version') = 'string'
        and public.is_sha256_jsonb(p_legal->'agreement_template_sha256')
      )
    )
$$;

create function public.is_valid_quotation_approval_payload_v1(
  p_payload jsonb,
  p_require_approval boolean default true
)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  v_line jsonb;
  v_one_time_subtotal bigint := 0;
  v_recurring_subtotal bigint := 0;
  v_discount_total bigint := 0;
  v_totals jsonb;
begin
  if not public.jsonb_has_exact_keys(p_payload, array[
    'contract_version', 'source_quote_request_id', 'source_intake_id',
    'pricing_snapshot', 'currency', 'line_items', 'totals', 'discount',
    'customer_identity', 'project_scope', 'vat_approval', 'payment_schedule',
    'validity', 'legal_references'
  ])
    or p_payload->'contract_version' <> '1'::jsonb
    or (p_payload->>'source_quote_request_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or (p_payload->>'source_intake_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or not public.jsonb_has_exact_keys(p_payload->'pricing_snapshot', array[
      'snapshot_id', 'snapshot_contract_version', 'integrity_algorithm_version',
      'integrity_key_id', 'integrity_mac'
    ])
    or (p_payload->'pricing_snapshot'->>'snapshot_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or not public.is_jsonb_nonnegative_integer(p_payload->'pricing_snapshot'->'snapshot_contract_version')
    or (p_payload->'pricing_snapshot'->>'snapshot_contract_version')::integer not in (2, 3)
    or p_payload->'pricing_snapshot'->>'integrity_algorithm_version' <> 'hmac-sha256-v1'
    or (p_payload->'pricing_snapshot'->>'integrity_key_id') !~ '^v[1-9][0-9]*$'
    or not public.is_sha256_jsonb(p_payload->'pricing_snapshot'->'integrity_mac')
    or p_payload->>'currency' <> 'EUR'
    or not public.is_valid_quotation_lines_v1(p_payload->'line_items')
    or not public.jsonb_has_exact_keys(p_payload->'totals', array[
      'one_time_subtotal_minor', 'recurring_subtotal_minor', 'discount_total_minor',
      'vat_base_minor', 'vat_amount_minor', 'total_gross_minor'
    ])
    or not public.is_valid_quotation_discount_v1(p_payload->'discount', p_require_approval)
    or not public.is_valid_quotation_identity_v1(p_payload->'customer_identity')
    or not public.is_valid_quotation_scope_v1(p_payload->'project_scope')
    or not public.is_valid_quotation_vat_approval_v1(p_payload->'vat_approval', p_require_approval)
    or not public.is_valid_quotation_legal_references_v1(p_payload->'legal_references', p_require_approval)
    or not public.is_valid_quotation_validity_v1(p_payload->'validity', p_require_approval) then
    return false;
  end if;

  if p_payload->'customer_identity'->>'source_quote_request_id'
       is distinct from p_payload->>'source_quote_request_id'
     or p_payload->'customer_identity'->>'source_intake_id'
       is distinct from p_payload->>'source_intake_id'
     or p_payload->'project_scope'->>'source_intake_id'
       is distinct from p_payload->>'source_intake_id'
     or p_payload->'project_scope'->>'source_pricing_snapshot_id'
       is distinct from p_payload->'pricing_snapshot'->>'snapshot_id' then
    return false;
  end if;

  v_totals := p_payload->'totals';
  if not (
    public.is_jsonb_nonnegative_integer(v_totals->'one_time_subtotal_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'recurring_subtotal_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'discount_total_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'vat_base_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'vat_amount_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'total_gross_minor')
  ) then
    return false;
  end if;

  for v_line in select value from jsonb_array_elements(p_payload->'line_items')
  loop
    if v_line->>'cost_type' = 'ONE_TIME' then
      v_one_time_subtotal := v_one_time_subtotal + (v_line->>'line_net_amount_minor')::bigint;
    else
      v_recurring_subtotal := v_recurring_subtotal + (v_line->>'line_net_amount_minor')::bigint;
    end if;
    v_discount_total := v_discount_total + (v_line->>'discount_minor')::bigint;
  end loop;

  if (v_totals->>'one_time_subtotal_minor')::bigint <> v_one_time_subtotal
     or (v_totals->>'recurring_subtotal_minor')::bigint <> v_recurring_subtotal
     or (v_totals->>'discount_total_minor')::bigint <> v_discount_total
     or (p_payload->'discount'->>'discount_value_minor')::bigint <> v_discount_total
     or (v_totals->>'vat_base_minor')::bigint <> v_one_time_subtotal
    or (v_totals->>'total_gross_minor')::bigint
      <> (v_totals->>'vat_base_minor')::bigint
      + (v_totals->>'vat_amount_minor')::bigint then
    return false;
  end if;

  return public.is_valid_quotation_payment_schedule_v1(
    p_payload->'payment_schedule', v_one_time_subtotal, p_require_approval
  );
exception
  when others then
    return false;
end;
$$;

create function public.canonicalize_quotation_approval_payload_v1(p_payload jsonb)
returns text
language plpgsql
immutable
set search_path = public
as $$
begin
  if not public.is_valid_quotation_approval_payload_v1(p_payload, false) then
    raise exception using errcode = '22023', message = 'INVALID_QUOTATION_APPROVAL_PAYLOAD_V1';
  end if;
  return p_payload::text;
end;
$$;

create function public.quotation_approval_payload_sha256_v1(p_payload jsonb)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select encode(extensions.digest(
    convert_to(public.canonicalize_quotation_approval_payload_v1(p_payload), 'UTF8'),
    'sha256'
  ), 'hex')
$$;

create table public.quote_request_quotation_approval_drafts (
  id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null references public.quote_requests(id),
  intake_id uuid not null references public.quote_request_intakes(id),
  pricing_snapshot_id uuid not null references public.quote_request_pricing_snapshots(id),
  contract_version smallint not null default 1 check (contract_version = 1),
  approval_payload jsonb not null,
  payload_fingerprint text not null check (payload_fingerprint ~ '^[0-9a-f]{64}$'),
  idempotency_key uuid not null unique,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  created_by text not null check (nullif(btrim(created_by), '') is not null),

  constraint quote_request_quotation_approval_drafts_intake_unique unique (intake_id),
  constraint quote_request_quotation_approval_drafts_payload_valid
    check (public.is_valid_quotation_approval_payload_v1(approval_payload, false)),
  constraint quote_request_quotation_approval_drafts_payload_sources_match
    check (
      approval_payload->>'source_quote_request_id' = quote_request_id::text
      and approval_payload->>'source_intake_id' = intake_id::text
      and approval_payload->'pricing_snapshot'->>'snapshot_id' = pricing_snapshot_id::text
    ),
  constraint quote_request_quotation_approval_drafts_fingerprint_matches
    check (payload_fingerprint = public.quotation_approval_payload_sha256_v1(approval_payload))
);

create table public.quote_request_quotation_approvals (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null references public.quote_request_quotation_approval_drafts(id),
  quote_request_id uuid not null references public.quote_requests(id),
  intake_id uuid not null references public.quote_request_intakes(id),
  pricing_snapshot_id uuid not null references public.quote_request_pricing_snapshots(id),
  contract_version smallint not null check (contract_version = 1),
  approval_version integer not null check (approval_version > 0),
  approved_payload jsonb not null,
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  approved_by text not null check (nullif(btrim(approved_by), '') is not null),
  approved_at timestamptz not null,

  constraint quote_request_quotation_approvals_version_unique
    unique (intake_id, approval_version),
  constraint quote_request_quotation_approvals_payload_valid
    check (public.is_valid_quotation_approval_payload_v1(approved_payload, true)),
  constraint quote_request_quotation_approvals_payload_sources_match
    check (
      approved_payload->>'source_quote_request_id' = quote_request_id::text
      and approved_payload->>'source_intake_id' = intake_id::text
      and approved_payload->'pricing_snapshot'->>'snapshot_id' = pricing_snapshot_id::text
    ),
  constraint quote_request_quotation_approvals_hash_matches
    check (payload_sha256 = public.quotation_approval_payload_sha256_v1(approved_payload))
);

create table public.quote_request_quotation_approval_integrity (
  approval_id uuid primary key references public.quote_request_quotation_approvals(id),
  algorithm_version text not null check (algorithm_version = 'hmac-sha256-v1'),
  key_id text not null check (key_id ~ '^v[1-9][0-9]*$'),
  mac text not null check (mac ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp()
);

create function public.set_quotation_approval_draft_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger trg_quotation_approval_drafts_updated_at
before update on public.quote_request_quotation_approval_drafts
for each row execute function public.set_quotation_approval_draft_updated_at();

create function public.prevent_quotation_approval_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception using errcode = '55000', message = 'QUOTATION_APPROVAL_IMMUTABLE';
end;
$$;

create trigger trg_quotation_approvals_immutable
before update or delete on public.quote_request_quotation_approvals
for each row execute function public.prevent_quotation_approval_mutation();

create trigger trg_quotation_approval_integrity_immutable
before update or delete on public.quote_request_quotation_approval_integrity
for each row execute function public.prevent_quotation_approval_mutation();

alter table public.quote_request_quotation_approval_drafts enable row level security;
alter table public.quote_request_quotation_approvals enable row level security;
alter table public.quote_request_quotation_approval_integrity enable row level security;

revoke all privileges on table public.quote_request_quotation_approval_drafts
from public, anon, authenticated, service_role;
revoke all privileges on table public.quote_request_quotation_approvals
from public, anon, authenticated, service_role;
revoke all privileges on table public.quote_request_quotation_approval_integrity
from public, anon, authenticated, service_role;

revoke all on function public.prevent_quotation_approval_mutation()
from public, anon, authenticated, service_role;
revoke all on function public.set_quotation_approval_draft_updated_at()
from public, anon, authenticated, service_role;

revoke all on function public.jsonb_has_exact_keys(jsonb, text[])
from public, anon, authenticated;
revoke all on function public.is_jsonb_nonnegative_integer(jsonb)
from public, anon, authenticated;
revoke all on function public.is_jsonb_positive_number(jsonb)
from public, anon, authenticated;
revoke all on function public.is_iso_utc_timestamp(jsonb)
from public, anon, authenticated;
revoke all on function public.is_sha256_jsonb(jsonb)
from public, anon, authenticated;
revoke all on function public.is_valid_quotation_lines_v1(jsonb)
from public, anon, authenticated;
revoke all on function public.is_valid_quotation_discount_v1(jsonb, boolean)
from public, anon, authenticated;
revoke all on function public.is_valid_quotation_vat_approval_v1(jsonb, boolean)
from public, anon, authenticated;
revoke all on function public.is_valid_quotation_payment_schedule_v1(jsonb, bigint, boolean)
from public, anon, authenticated;
revoke all on function public.is_valid_quotation_validity_v1(jsonb, boolean)
from public, anon, authenticated;
revoke all on function public.is_valid_quotation_identity_v1(jsonb)
from public, anon, authenticated;
revoke all on function public.is_valid_quotation_scope_v1(jsonb)
from public, anon, authenticated;
revoke all on function public.is_valid_quotation_legal_references_v1(jsonb, boolean)
from public, anon, authenticated;
revoke all on function public.is_valid_quotation_approval_payload_v1(jsonb, boolean)
from public, anon, authenticated;
revoke all on function public.canonicalize_quotation_approval_payload_v1(jsonb)
from public, anon, authenticated;
revoke all on function public.quotation_approval_payload_sha256_v1(jsonb)
from public, anon, authenticated;

grant execute on function public.jsonb_has_exact_keys(jsonb, text[])
to service_role;
grant execute on function public.is_jsonb_nonnegative_integer(jsonb)
to service_role;
grant execute on function public.is_jsonb_positive_number(jsonb)
to service_role;
grant execute on function public.is_iso_utc_timestamp(jsonb)
to service_role;
grant execute on function public.is_sha256_jsonb(jsonb)
to service_role;
grant execute on function public.is_valid_quotation_lines_v1(jsonb)
to service_role;
grant execute on function public.is_valid_quotation_discount_v1(jsonb, boolean)
to service_role;
grant execute on function public.is_valid_quotation_vat_approval_v1(jsonb, boolean)
to service_role;
grant execute on function public.is_valid_quotation_payment_schedule_v1(jsonb, bigint, boolean)
to service_role;
grant execute on function public.is_valid_quotation_validity_v1(jsonb, boolean)
to service_role;
grant execute on function public.is_valid_quotation_identity_v1(jsonb)
to service_role;
grant execute on function public.is_valid_quotation_scope_v1(jsonb)
to service_role;
grant execute on function public.is_valid_quotation_legal_references_v1(jsonb, boolean)
to service_role;
grant execute on function public.is_valid_quotation_approval_payload_v1(jsonb, boolean)
to service_role;
grant execute on function public.canonicalize_quotation_approval_payload_v1(jsonb)
to service_role;
grant execute on function public.quotation_approval_payload_sha256_v1(jsonb)
to service_role;