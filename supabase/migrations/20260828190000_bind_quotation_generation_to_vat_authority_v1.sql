create function public.resolve_quotation_generation_vat_binding_v1(
  p_approval_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_binding public.quotation_business_draft_vat_bindings%rowtype;
  v_authority public.quotation_vat_decision_authorities%rowtype;
  v_business public.quote_request_quotation_business_drafts%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_business_draft_id uuid;
begin
  select promotion.business_draft_id
  into v_business_draft_id
  from public.quote_request_quotation_business_approval_promotions as promotion
  where promotion.approval_id = p_approval_id;

  if v_business_draft_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'QUOTATION_VAT_BINDING_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.quotation_business_draft_vat_bindings
    where business_draft_id = v_business_draft_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'QUOTATION_VAT_BINDING_REQUIRED';
  end if;

  perform public.assert_quotation_business_draft_vat_binding_v1(
    v_business_draft_id,
    false
  );

  select * into strict v_business
  from public.quote_request_quotation_business_drafts
  where business_draft_id = v_business_draft_id;

  select * into strict v_approval
  from public.quote_request_quotation_approvals
  where id = p_approval_id;

  select * into strict v_binding
  from public.quotation_business_draft_vat_bindings
  where business_draft_id = v_business_draft_id;

  select * into strict v_authority
  from public.quotation_vat_decision_authorities
  where vat_decision_authority_id = v_binding.vat_decision_authority_id;

  if v_approval.draft_id is distinct from v_business.approval_draft_id
     or v_approval.intake_id is distinct from v_business.intake_id
     or v_approval.quote_request_id is distinct from v_business.quote_request_id
     or v_approval.pricing_snapshot_id is distinct from v_business.pricing_snapshot_id
     or v_approval.contract_version <> 1
     or v_approval.approved_payload is distinct from v_business.canonical_payload
     or rtrim(v_approval.payload_sha256) is distinct from rtrim(v_business.canonical_payload_sha256)
     or public.quotation_approval_payload_sha256_v1(v_approval.approved_payload)
        is distinct from rtrim(v_approval.payload_sha256) then
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
  end if;

  return jsonb_build_object(
    'vat_decision_authority_id', v_binding.vat_decision_authority_id,
    'authority_family', v_binding.authority_family,
    'decision_code', v_binding.decision_code,
    'decision_version', v_binding.decision_version,
    'authority_sha256', rtrim(v_binding.authority_sha256),
    'vat_treatment', v_binding.vat_treatment,
    'rate_semantics', v_binding.rate_semantics,
    'vat_rate', v_authority.vat_rate,
    'invoice_literal', v_binding.invoice_literal,
    'vat_decision_source', v_authority.authority_source_identifier
  );
exception
  when no_data_found or too_many_rows then
    raise exception using errcode = 'P0001', message = 'APPROVAL_CONFLICT';
end;
$$;

alter function public.project_quotation_generation_payload_v1(
  text, uuid, jsonb, text, jsonb, jsonb, uuid, text, integer
)
rename to project_quotation_generation_payload_unbound_v1;

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
stable
security definer
set search_path = public, pg_catalog
as $$
  with binding as (
    select public.resolve_quotation_generation_vat_binding_v1(p_approval_id) as value
  ), base as (
    select public.project_quotation_generation_payload_raw_v1(
      p_mode,
      p_approval_id,
      p_approved_payload,
      p_payload_sha256,
      p_template,
      p_seller,
      p_issuance_id,
      p_quotation_number,
      p_quotation_version
    ) as value
  )
  select jsonb_set(
    base.value,
    '{vat}',
    jsonb_build_object(
      'vat_treatment', binding.value->>'vat_treatment',
      'rate_semantics', binding.value->>'rate_semantics',
      'vat_rate', binding.value->'vat_rate',
      'invoice_literal', binding.value->>'invoice_literal',
      'vat_decision_source', binding.value->>'vat_decision_source'
    )
  )
  from base cross join binding
$$;

revoke all on function public.resolve_quotation_generation_vat_binding_v1(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.project_quotation_generation_payload_unbound_v1(
  text, uuid, jsonb, text, jsonb, jsonb, uuid, text, integer
) from public, anon, authenticated, service_role;
revoke all on function public.project_quotation_generation_payload_v1(
  text, uuid, jsonb, text, jsonb, jsonb, uuid, text, integer
) from public, anon, authenticated, service_role;

comment on function public.resolve_quotation_generation_vat_binding_v1(uuid) is
  'Resolves quotation generation VAT fields only through the immutable approval promotion and exact frozen business-draft VAT authority binding; missing legacy bindings fail closed without backfill.';
comment on function public.project_quotation_generation_payload_v1(
  text, uuid, jsonb, text, jsonb, jsonb, uuid, text, integer
) is
  'Projects VAT treatment, compatibility rate, rate semantics, literal, and source exclusively from the validated frozen authority binding associated with the approval.';