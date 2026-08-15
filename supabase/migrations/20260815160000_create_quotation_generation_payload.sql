create function public.is_valid_quotation_generation_seller_v1(p_seller jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select public.jsonb_has_exact_keys(p_seller, array[
    'legal_name', 'address_line_1', 'address_line_2', 'postal_code', 'city',
    'country_code', 'enterprise_number', 'vat_number', 'email', 'website',
    'contact_name'
  ])
    and jsonb_typeof(p_seller->'legal_name') = 'string'
    and nullif(btrim(p_seller->>'legal_name'), '') is not null
    and jsonb_typeof(p_seller->'address_line_1') = 'string'
    and nullif(btrim(p_seller->>'address_line_1'), '') is not null
    and jsonb_typeof(p_seller->'postal_code') = 'string'
    and nullif(btrim(p_seller->>'postal_code'), '') is not null
    and jsonb_typeof(p_seller->'city') = 'string'
    and nullif(btrim(p_seller->>'city'), '') is not null
    and p_seller->>'country_code' ~ '^[A-Z]{2}$'
    and jsonb_typeof(p_seller->'enterprise_number') = 'string'
    and nullif(btrim(p_seller->>'enterprise_number'), '') is not null
    and jsonb_typeof(p_seller->'vat_number') = 'string'
    and nullif(btrim(p_seller->>'vat_number'), '') is not null
    and jsonb_typeof(p_seller->'email') = 'string'
    and p_seller->>'email' ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    and jsonb_typeof(p_seller->'website') = 'string'
    and nullif(btrim(p_seller->>'website'), '') is not null
    and (p_seller->'address_line_2' = 'null'::jsonb
      or jsonb_typeof(p_seller->'address_line_2') = 'string')
    and (p_seller->'contact_name' = 'null'::jsonb
      or jsonb_typeof(p_seller->'contact_name') = 'string')
$$;

create function public.is_valid_quotation_generation_template_v1(
  p_template jsonb,
  p_require_approved boolean
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select public.jsonb_has_exact_keys(p_template, array[
    'template_id', 'template_version', 'template_sha256', 'authority_status'
  ])
    and jsonb_typeof(p_template->'template_id') = 'string'
    and nullif(btrim(p_template->>'template_id'), '') is not null
    and jsonb_typeof(p_template->'template_version') = 'string'
    and nullif(btrim(p_template->>'template_version'), '') is not null
    and public.is_sha256_jsonb(p_template->'template_sha256')
    and p_template->>'authority_status' in ('CANDIDATE', 'APPROVED')
    and (not p_require_approved or p_template->>'authority_status' = 'APPROVED')
$$;

create function public.is_valid_quotation_generation_payload_v1(p_payload jsonb)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  v_line jsonb;
  v_milestone jsonb;
  v_previous_sequence bigint := 0;
  v_one_time bigint := 0;
  v_recurring bigint := 0;
  v_discount bigint := 0;
  v_quotation jsonb;
  v_totals jsonb;
begin
  if not public.jsonb_has_exact_keys(p_payload, array[
    'contract_version', 'mode', 'template', 'quotation', 'seller', 'customer',
    'project', 'lines', 'totals', 'vat', 'payment_schedule', 'validity',
    'legal_references', 'acceptance_instruction', 'pricing_references', 'locale'
  ])
    or p_payload->'contract_version' <> '1'::jsonb
    or p_payload->>'mode' not in ('PREVIEW', 'ISSUE')
    or not public.is_valid_quotation_generation_seller_v1(p_payload->'seller')
    or not public.is_valid_quotation_generation_template_v1(
      p_payload->'template', p_payload->>'mode' = 'ISSUE'
    )
    or not public.jsonb_has_exact_keys(p_payload->'locale', array[
      'document_language', 'document_locale', 'currency'
    ])
    or p_payload->'locale'->>'document_language' <> 'nl'
    or p_payload->'locale'->>'document_locale' <> 'nl-BE'
    or p_payload->'locale'->>'currency' <> 'EUR'
    or not public.jsonb_has_exact_keys(p_payload->'quotation', array[
      'approval_id', 'issuance_id', 'quotation_number', 'quotation_version',
      'quotation_status', 'visible_marker'
    ])
    or not public.jsonb_has_exact_keys(p_payload->'customer', array[
      'customer_id', 'legal_name', 'contact_name', 'email', 'address_line_1',
      'address_line_2', 'postal_code', 'city', 'country_code',
      'enterprise_number', 'vat_number'
    ])
    or jsonb_typeof(p_payload->'customer'->'legal_name') <> 'string'
    or nullif(btrim(p_payload->'customer'->>'legal_name'), '') is null
    or jsonb_typeof(p_payload->'customer'->'email') <> 'string'
    or not public.jsonb_has_exact_keys(p_payload->'project', array[
      'project_id', 'project_title', 'project_type', 'scope_summary',
      'requested_languages', 'included_page_count', 'features', 'copywriting',
      'seo', 'hosting', 'maintenance', 'exclusions', 'assumptions',
      'indicative_timing'
    ])
    or jsonb_typeof(p_payload->'project'->'project_title') <> 'string'
    or nullif(btrim(p_payload->'project'->>'project_title'), '') is null
    or jsonb_typeof(p_payload->'project'->'requested_languages') <> 'array'
    or jsonb_typeof(p_payload->'project'->'features') <> 'array'
    or not public.is_jsonb_nonnegative_integer(p_payload->'project'->'included_page_count')
    or not public.is_valid_quotation_lines_v1(p_payload->'lines')
    or not public.jsonb_has_exact_keys(p_payload->'totals', array[
      'subtotal_net_minor', 'one_time_subtotal_minor', 'recurring_subtotal_minor',
      'discount_total_minor', 'vat_base_minor', 'vat_amount_minor',
      'total_gross_minor'
    ])
    or not public.jsonb_has_exact_keys(p_payload->'vat', array[
      'vat_treatment', 'vat_rate', 'vat_decision_source'
    ])
    or jsonb_typeof(p_payload->'vat'->'vat_treatment') <> 'string'
    or jsonb_typeof(p_payload->'vat'->'vat_rate') <> 'number'
    or not public.jsonb_has_exact_keys(p_payload->'payment_schedule', array[
      'schedule_id', 'milestones'
    ])
    or jsonb_typeof(p_payload->'payment_schedule'->'milestones') <> 'array'
    or jsonb_array_length(p_payload->'payment_schedule'->'milestones') < 1
    or not public.jsonb_has_exact_keys(p_payload->'validity', array[
      'valid_from', 'valid_until', 'validity_days'
    ])
    or not public.jsonb_has_exact_keys(p_payload->'legal_references', array[
      'terms_reference', 'terms_version', 'agreement_reference',
      'agreement_version'
    ])
    or not public.jsonb_has_exact_keys(p_payload->'pricing_references', array[
      'approval_payload_sha256', 'pricing_snapshot_id',
      'pricing_snapshot_contract_version'
    ])
    or not public.is_sha256_jsonb(
      p_payload->'pricing_references'->'approval_payload_sha256'
    )
    or (p_payload->'pricing_references'->>'pricing_snapshot_id')
      !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or not public.is_jsonb_nonnegative_integer(
      p_payload->'pricing_references'->'pricing_snapshot_contract_version'
    )
    or jsonb_typeof(p_payload->'acceptance_instruction') <> 'string'
    or nullif(btrim(p_payload->>'acceptance_instruction'), '') is null then
    return false;
  end if;

  v_quotation := p_payload->'quotation';
  if (v_quotation->>'approval_id')
       !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or (p_payload->>'mode' = 'PREVIEW' and not (
       v_quotation->'issuance_id' = 'null'::jsonb
       and v_quotation->'quotation_number' = 'null'::jsonb
       and v_quotation->'quotation_version' = 'null'::jsonb
       and v_quotation->>'quotation_status' = 'NON_AUTHORITATIVE'
       and v_quotation->>'visible_marker' = 'CONCEPT — NIET GELDIG ALS OFFERTE'
     ))
     or (p_payload->>'mode' = 'ISSUE' and not (
       (v_quotation->>'issuance_id')
         ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       and v_quotation->>'quotation_number' ~ '^LWS-OFF-[0-9]{4}-[0-9]{4}$'
       and public.is_jsonb_nonnegative_integer(v_quotation->'quotation_version')
       and (v_quotation->>'quotation_version')::integer >= 1
       and v_quotation->>'quotation_status' = 'PREPARED'
       and v_quotation->'visible_marker' = 'null'::jsonb
     )) then
    return false;
  end if;

  for v_line in select value from jsonb_array_elements(p_payload->'lines')
  loop
    if (v_line->>'sequence')::bigint <= v_previous_sequence then return false; end if;
    v_previous_sequence := (v_line->>'sequence')::bigint;
    if v_line->>'cost_type' = 'ONE_TIME' then
      v_one_time := v_one_time + (v_line->>'line_net_amount_minor')::bigint;
    else
      v_recurring := v_recurring + (v_line->>'line_net_amount_minor')::bigint;
    end if;
    v_discount := v_discount + (v_line->>'discount_minor')::bigint;
  end loop;
  v_totals := p_payload->'totals';
  if not (
    public.is_jsonb_nonnegative_integer(v_totals->'subtotal_net_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'one_time_subtotal_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'recurring_subtotal_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'discount_total_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'vat_base_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'vat_amount_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'total_gross_minor')
    and (v_totals->>'one_time_subtotal_minor')::bigint = v_one_time
    and (v_totals->>'recurring_subtotal_minor')::bigint = v_recurring
    and (v_totals->>'subtotal_net_minor')::bigint = v_one_time + v_recurring
    and (v_totals->>'discount_total_minor')::bigint = v_discount
    and (v_totals->>'total_gross_minor')::bigint
      = (v_totals->>'vat_base_minor')::bigint
      + (v_totals->>'vat_amount_minor')::bigint
  ) then return false; end if;

  if exists (
    select 1
    from jsonb_array_elements(p_payload->'lines') as line
    where line->>'vat_treatment' is distinct from p_payload->'vat'->>'vat_treatment'
       or (line->>'vat_rate')::numeric
          is distinct from (p_payload->'vat'->>'vat_rate')::numeric
  ) then return false; end if;

  v_previous_sequence := 0;
  for v_milestone in select value from jsonb_array_elements(
    p_payload->'payment_schedule'->'milestones'
  )
  loop
    if not public.jsonb_has_exact_keys(v_milestone, array[
      'sequence', 'label', 'percentage', 'amount_minor', 'trigger',
      'due_terms_days', 'recurring_cycle'
    ])
      or not public.is_jsonb_nonnegative_integer(v_milestone->'sequence')
      or (v_milestone->>'sequence')::bigint <= v_previous_sequence then
      return false;
    end if;
    v_previous_sequence := (v_milestone->>'sequence')::bigint;
  end loop;

  return public.is_valid_quotation_payment_schedule_v1(
    (p_payload->'payment_schedule') || jsonb_build_object(
      'approved_by', 'generation-contract',
      'approved_at', '2000-01-01T00:00:00Z'
    ),
    (v_totals->>'one_time_subtotal_minor')::bigint,
    true
  ) and public.is_valid_quotation_validity_v1(
    (p_payload->'validity') || jsonb_build_object(
      'approved_by', 'generation-contract',
      'approved_at', '2000-01-01T00:00:00Z'
    ), true
  );
exception when others then return false;
end;
$$;

create function public.canonicalize_quotation_generation_payload_v1(p_payload jsonb)
returns text
language plpgsql
immutable
set search_path = public
as $$
begin
  if not public.is_valid_quotation_generation_payload_v1(p_payload) then
    raise exception using errcode = '22023', message = 'INVALID_QUOTATION_GENERATION_PAYLOAD_V1';
  end if;
  return p_payload::text;
end;
$$;

create function public.quotation_generation_payload_sha256_v1(p_payload jsonb)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select encode(extensions.digest(convert_to(
    public.canonicalize_quotation_generation_payload_v1(p_payload), 'UTF8'
  ), 'sha256'), 'hex')
$$;

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
set search_path = public
as $$
  select jsonb_build_object(
    'contract_version', 1,
    'mode', p_mode,
    'template', p_template,
    'quotation', jsonb_build_object(
      'approval_id', p_approval_id,
      'issuance_id', p_issuance_id,
      'quotation_number', p_quotation_number,
      'quotation_version', p_quotation_version,
      'quotation_status', case when p_mode = 'ISSUE' then 'PREPARED' else 'NON_AUTHORITATIVE' end,
      'visible_marker', case when p_mode = 'PREVIEW' then 'CONCEPT — NIET GELDIG ALS OFFERTE' else null end
    ),
    'seller', p_seller,
    'customer', jsonb_build_object(
      'customer_id', p_approved_payload->'customer_identity'->'customer_id',
      'legal_name', p_approved_payload->'customer_identity'->'legal_name',
      'contact_name', p_approved_payload->'customer_identity'->'contact_name',
      'email', p_approved_payload->'customer_identity'->'email',
      'address_line_1', p_approved_payload->'customer_identity'->'address_line_1',
      'address_line_2', p_approved_payload->'customer_identity'->'address_line_2',
      'postal_code', p_approved_payload->'customer_identity'->'postal_code',
      'city', p_approved_payload->'customer_identity'->'city',
      'country_code', p_approved_payload->'customer_identity'->'country_code',
      'enterprise_number', p_approved_payload->'customer_identity'->'enterprise_number',
      'vat_number', p_approved_payload->'customer_identity'->'vat_number'
    ),
    'project', (p_approved_payload->'project_scope') - array[
      'source_intake_id', 'source_pricing_snapshot_id', 'snapshot_sha256'
    ],
    'lines', (select jsonb_agg(value order by (value->>'sequence')::integer)
      from jsonb_array_elements(p_approved_payload->'line_items')),
    'totals', jsonb_build_object(
      'subtotal_net_minor', (p_approved_payload->'totals'->>'one_time_subtotal_minor')::bigint
        + (p_approved_payload->'totals'->>'recurring_subtotal_minor')::bigint,
      'one_time_subtotal_minor', p_approved_payload->'totals'->'one_time_subtotal_minor',
      'recurring_subtotal_minor', p_approved_payload->'totals'->'recurring_subtotal_minor',
      'discount_total_minor', p_approved_payload->'totals'->'discount_total_minor',
      'vat_base_minor', p_approved_payload->'totals'->'vat_base_minor',
      'vat_amount_minor', p_approved_payload->'totals'->'vat_amount_minor',
      'total_gross_minor', p_approved_payload->'totals'->'total_gross_minor'
    ),
    'vat', jsonb_build_object(
      'vat_treatment', p_approved_payload->'vat_approval'->'vat_treatment',
      'vat_rate', p_approved_payload->'vat_approval'->'vat_rate',
      'vat_decision_source', p_approved_payload->'vat_approval'->'vat_decision_source'
    ),
    'payment_schedule', jsonb_build_object(
      'schedule_id', p_approved_payload->'payment_schedule'->'schedule_id',
      'milestones', p_approved_payload->'payment_schedule'->'milestones'
    ),
    'validity', (p_approved_payload->'validity') - array['approved_by', 'approved_at'],
    'legal_references', jsonb_build_object(
      'terms_reference', p_approved_payload->'legal_references'->'terms_reference',
      'terms_version', p_approved_payload->'legal_references'->'terms_version',
      'agreement_reference', p_approved_payload->'legal_references'->'agreement_template_reference',
      'agreement_version', p_approved_payload->'legal_references'->'agreement_template_version'
    ),
    'acceptance_instruction', 'Bevestig uw akkoord volgens de instructies bij deze offerte.',
    'pricing_references', jsonb_build_object(
      'approval_payload_sha256', p_payload_sha256,
      'pricing_snapshot_id', p_approved_payload->'pricing_snapshot'->'snapshot_id',
      'pricing_snapshot_contract_version', p_approved_payload->'pricing_snapshot'->'snapshot_contract_version'
    ),
    'locale', jsonb_build_object(
      'document_language', 'nl', 'document_locale', 'nl-BE', 'currency', 'EUR'
    )
  )
$$;

create function public.build_quotation_preview_payload_v1(
  p_approval_id uuid,
  p_template jsonb,
  p_seller jsonb,
  p_admin_access_token_hash text
)
returns table(payload jsonb, payload_sha256 text, contract_version smallint, mode text, approval_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_payload jsonb;
begin
  select * into v_approval from public.quote_request_quotation_approvals where id = p_approval_id;
  if not found then raise exception using errcode='P0001', message='APPROVAL_NOT_FOUND'; end if;
  select * into strict v_intake from public.quote_request_intakes where id=v_approval.intake_id;
  if p_admin_access_token_hash !~ '^[0-9a-f]{64}$'
     or v_intake.admin_access_token_hash is distinct from p_admin_access_token_hash
     or v_intake.admin_access_token_expires_at <= clock_timestamp()
     or v_intake.admin_access_token_revoked_at is not null then
    raise exception using errcode='42501', message='UNAUTHORIZED';
  end if;
  if not public.is_valid_quotation_approval_for_issuance_v1(p_approval_id) then
    raise exception using errcode='P0001', message='APPROVAL_INTEGRITY_INVALID';
  end if;
  if not public.is_valid_quotation_generation_template_v1(p_template,false) then
    raise exception using errcode='22023', message='TEMPLATE_IDENTITY_INVALID';
  end if;
  if not public.is_valid_quotation_generation_seller_v1(p_seller) then
    raise exception using errcode='22023', message='SELLER_IDENTITY_INVALID';
  end if;
  v_payload:=public.project_quotation_generation_payload_v1('PREVIEW',v_approval.id,v_approval.approved_payload,v_approval.payload_sha256,p_template,p_seller);
  if not public.is_valid_quotation_generation_payload_v1(v_payload) then
    raise exception using errcode='22023', message='INVALID_QUOTATION_GENERATION_PAYLOAD_V1';
  end if;
  return query select v_payload,public.quotation_generation_payload_sha256_v1(v_payload),1::smallint,'PREVIEW'::text,v_approval.id;
end;
$$;

create function public.build_quotation_issue_payload_v1(
  p_issuance_id uuid,
  p_template jsonb,
  p_seller jsonb,
  p_admin_access_token_hash text
)
returns table(payload jsonb, payload_sha256 text, contract_version smallint, mode text, approval_id uuid, issuance_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_issuance public.quote_request_quotation_issuances%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_payload jsonb;
begin
  select * into v_issuance from public.quote_request_quotation_issuances where id=p_issuance_id;
  if not found then raise exception using errcode='P0001', message='ISSUANCE_NOT_FOUND'; end if;
  if v_issuance.status <> 'PREPARED' or v_issuance.generation_payload_sha256 is not null then
    raise exception using errcode='P0001', message='ISSUANCE_STATE_CONFLICT';
  end if;
  select * into strict v_approval from public.quote_request_quotation_approvals where id=v_issuance.approval_id;
  select * into strict v_intake from public.quote_request_intakes where id=v_approval.intake_id;
  if p_admin_access_token_hash !~ '^[0-9a-f]{64}$'
     or v_intake.admin_access_token_hash is distinct from p_admin_access_token_hash
     or v_intake.admin_access_token_expires_at <= clock_timestamp()
     or v_intake.admin_access_token_revoked_at is not null then
    raise exception using errcode='42501', message='UNAUTHORIZED';
  end if;
  if not public.is_valid_quotation_approval_for_issuance_v1(v_approval.id) then
    raise exception using errcode='P0001', message='APPROVAL_INTEGRITY_INVALID';
  end if;
  if not public.is_valid_quotation_generation_template_v1(p_template,true) then
    if public.is_valid_quotation_generation_template_v1(p_template,false) then
      raise exception using errcode='P0001', message='QUOTATION_TEMPLATE_NOT_APPROVED';
    end if;
    raise exception using errcode='22023', message='TEMPLATE_IDENTITY_INVALID';
  end if;
  if not public.is_valid_quotation_generation_seller_v1(p_seller) then
    raise exception using errcode='22023', message='SELLER_IDENTITY_INVALID';
  end if;
  v_payload:=public.project_quotation_generation_payload_v1('ISSUE',v_approval.id,v_approval.approved_payload,v_approval.payload_sha256,p_template,p_seller,v_issuance.id,v_issuance.quotation_number,v_issuance.quotation_version);
  if not public.is_valid_quotation_generation_payload_v1(v_payload) then
    raise exception using errcode='22023', message='INVALID_QUOTATION_GENERATION_PAYLOAD_V1';
  end if;
  return query select v_payload,public.quotation_generation_payload_sha256_v1(v_payload),1::smallint,'ISSUE'::text,v_approval.id,v_issuance.id;
end;
$$;

create function public.quotation_generation_data_minimization_v1()
returns jsonb
language sql
immutable
set search_path=public
as $$
select jsonb_build_object(
  'DOCUMENT_VISIBLE',jsonb_build_array('seller','customer','project','lines','totals','vat','payment_schedule','validity','legal_references','acceptance_instruction','locale'),
  'GENERATOR_REQUIRED_ONLY',jsonb_build_array('template','quotation','pricing_references'),
  'AUDIT_ONLY',jsonb_build_array('approver_identity','approval_timestamps','integrity_metadata','source_snapshot_hashes'),
  'EXCLUDED',jsonb_build_array('capability_tokens','hmac_mac','hmac_key_id','raw_intake','raw_pricing_snapshot','raw_approval_record')
)
$$;

revoke all on function public.build_quotation_preview_payload_v1(uuid,jsonb,jsonb,text) from public,anon,authenticated;
revoke all on function public.build_quotation_issue_payload_v1(uuid,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.build_quotation_preview_payload_v1(uuid,jsonb,jsonb,text) to service_role;
grant execute on function public.build_quotation_issue_payload_v1(uuid,jsonb,jsonb,text) to service_role;

revoke all on function public.is_valid_quotation_generation_seller_v1(jsonb) from public,anon,authenticated;
revoke all on function public.is_valid_quotation_generation_template_v1(jsonb,boolean) from public,anon,authenticated;
revoke all on function public.is_valid_quotation_generation_payload_v1(jsonb) from public,anon,authenticated;
revoke all on function public.canonicalize_quotation_generation_payload_v1(jsonb) from public,anon,authenticated;
revoke all on function public.quotation_generation_payload_sha256_v1(jsonb) from public,anon,authenticated;
revoke all on function public.project_quotation_generation_payload_v1(text,uuid,jsonb,text,jsonb,jsonb,uuid,text,integer) from public,anon,authenticated;
revoke all on function public.quotation_generation_data_minimization_v1() from public,anon,authenticated;

grant execute on function public.is_valid_quotation_generation_seller_v1(jsonb) to service_role;
grant execute on function public.is_valid_quotation_generation_template_v1(jsonb,boolean) to service_role;
grant execute on function public.is_valid_quotation_generation_payload_v1(jsonb) to service_role;
grant execute on function public.canonicalize_quotation_generation_payload_v1(jsonb) to service_role;
grant execute on function public.quotation_generation_payload_sha256_v1(jsonb) to service_role;
grant execute on function public.quotation_generation_data_minimization_v1() to service_role;

comment on function public.build_quotation_preview_payload_v1(uuid,jsonb,jsonb,text) is
  'Read-only trusted projection from an immutable approval. Seller identity is validated trusted input until a machine-readable seller authority exists.';
comment on function public.build_quotation_issue_payload_v1(uuid,jsonb,jsonb,text) is
  'Read-only projection from PREPARED v2 issuance and immutable approval. APPROVED template identity is required but no template authority is created here.';
