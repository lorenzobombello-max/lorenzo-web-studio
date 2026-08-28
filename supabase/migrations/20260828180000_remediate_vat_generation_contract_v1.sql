alter function public.is_valid_quotation_generation_payload_v1(jsonb)
rename to is_valid_quotation_generation_payload_raw_v1;

create function public.is_valid_quotation_generation_payload_v1(p_payload jsonb)
returns boolean
language sql
immutable
security definer
set search_path = public, pg_catalog
as $$
  select public.is_valid_quotation_generation_payload_raw_v1(
    (p_payload #- '{vat,rate_semantics}') #- '{vat,invoice_literal}'
  )
  and public.jsonb_has_exact_keys(p_payload->'vat', array[
    'vat_treatment', 'rate_semantics', 'vat_rate', 'invoice_literal',
    'vat_decision_source'
  ])
  and jsonb_typeof(p_payload->'vat'->'rate_semantics') = 'string'
  and (
    (
      p_payload->'vat'->>'vat_treatment' = 'EXEMPT'
      and p_payload->'vat'->>'rate_semantics' = 'NOT_APPLICABLE'
      and p_payload->'vat'->'vat_rate' = '0'::jsonb
      and p_payload->'vat'->>'invoice_literal'
        = 'Bijzondere vrijstellingsregeling van belasting'
    )
    or (
      p_payload->'vat'->>'vat_treatment' <> 'EXEMPT'
      and p_payload->'vat'->>'rate_semantics' = 'PERCENT'
      and p_payload->'vat'->'invoice_literal' = 'null'::jsonb
    )
  )
$$;

alter function public.project_quotation_generation_payload_v1(
  text, uuid, jsonb, text, jsonb, jsonb, uuid, text, integer
)
rename to project_quotation_generation_payload_raw_v1;

create function public.project_quotation_generation_payload_v1(
  p_mode text,
  p_approval_id uuid,
  p_approved_payload jsonb,
  p_payload_sha256 text,
  p_template jsonb,
  p_seller jsonb,
  p_issuance_id uuid default null,
  p_quotation_number text default null,
  p_quotation_version integer default null
)
returns jsonb
language sql
immutable
set search_path = public, pg_catalog
as $$
  select jsonb_set(
    public.project_quotation_generation_payload_raw_v1(
      p_mode,
      p_approval_id,
      p_approved_payload,
      p_payload_sha256,
      p_template,
      p_seller,
      p_issuance_id,
      p_quotation_number,
      p_quotation_version
    ),
    '{vat}',
    public.project_quotation_generation_payload_raw_v1(
      p_mode,
      p_approval_id,
      p_approved_payload,
      p_payload_sha256,
      p_template,
      p_seller,
      p_issuance_id,
      p_quotation_number,
      p_quotation_version
    )->'vat' || jsonb_build_object(
      'rate_semantics', case
        when p_approved_payload->'vat_approval'->>'vat_treatment' = 'EXEMPT'
          then 'NOT_APPLICABLE'
        else 'PERCENT'
      end,
      'invoice_literal', case
        when p_approved_payload->'vat_approval'->>'vat_treatment' = 'EXEMPT'
          then 'Bijzondere vrijstellingsregeling van belasting'
        else null
      end
    )
  )
$$;

revoke all on function public.is_valid_quotation_generation_payload_raw_v1(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.is_valid_quotation_generation_payload_v1(jsonb)
  from public, anon, authenticated;
revoke all on function public.project_quotation_generation_payload_raw_v1(
  text, uuid, jsonb, text, jsonb, jsonb, uuid, text, integer
) from public, anon, authenticated, service_role;
revoke all on function public.project_quotation_generation_payload_v1(
  text, uuid, jsonb, text, jsonb, jsonb, uuid, text, integer
) from public, anon, authenticated;

grant execute on function public.is_valid_quotation_generation_payload_v1(jsonb)
  to service_role;

comment on function public.is_valid_quotation_generation_payload_v1(jsonb) is
  'Schema-strict generation validator requiring explicit rate semantics and invoice literal; EXEMPT is valid only as NOT_APPLICABLE with compatibility rate zero and the canonical literal.';
comment on function public.project_quotation_generation_payload_v1(
  text, uuid, jsonb, text, jsonb, jsonb, uuid, text, integer
) is
  'Preserves the generation v1 projection and adds explicit VAT rate semantics and the canonical exemption invoice literal without changing document layout.';