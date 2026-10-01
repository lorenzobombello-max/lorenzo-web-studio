create or replace function public.is_valid_quotation_identity_v1(p_identity jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select public.jsonb_has_exact_keys(p_identity, array[
    'source_quote_request_id', 'source_intake_id', 'customer_id',
    'legal_name', 'legal_form', 'contact_name', 'email', 'address_line_1', 'address_line_2',
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
    and jsonb_typeof(p_identity->'legal_form') = 'string'
    and nullif(btrim(p_identity->>'legal_form'), '') is not null
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
    and (p_identity->'source_fields' ? 'legal_form')
    and jsonb_typeof(p_identity->'source_fields'->'legal_form') = 'string'
    and nullif(btrim(p_identity->'source_fields'->>'legal_form'), '') is not null
    and (select count(*) from jsonb_object_keys(p_identity->'source_fields')) > 0
    and public.is_sha256_jsonb(p_identity->'snapshot_sha256')
$$;

comment on function public.is_valid_quotation_identity_v1(jsonb) is
  'Validates quotation customer identity v1, including an explicit legal form and its recorded source field.';
