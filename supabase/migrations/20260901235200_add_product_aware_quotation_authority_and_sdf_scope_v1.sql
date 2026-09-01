alter table public.quotation_template_authorities
  add column request_kind text not null default 'website'
  constraint quotation_template_authorities_request_kind_check
    check (request_kind in ('website', 'slimme_documentenflow'));

comment on column public.quotation_template_authorities.request_kind is
  'Canonical product discriminator. Existing authorities are deterministically Website authorities; SDF never falls back to Website.';

drop index public.quotation_template_authority_one_approved_per_contract;
create unique index quotation_template_authority_one_approved_per_product_contract
on public.quotation_template_authorities (
  request_kind, document_type, locale, currency, renderer_contract_version,
  generation_contract_version, semantic_contract_version
)
where status = 'APPROVED';

create or replace function public.guard_quotation_template_authority_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_transition text := current_setting('lws.quotation_template_transition', true);
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'QUOTATION_TEMPLATE_AUTHORITY_IMMUTABLE';
  end if;
  if v_transition = 'APPROVE'
     and old.status = 'CANDIDATE' and new.status = 'APPROVED'
     and old.id = new.id and old.template_id = new.template_id
     and old.template_version = new.template_version
     and old.request_kind = new.request_kind
     and old.document_type = new.document_type and old.locale = new.locale
     and old.currency = new.currency and old.template_sha256 = new.template_sha256
     and old.technical_master_filename = new.technical_master_filename
     and old.renderer_contract_version = new.renderer_contract_version
     and old.renderer_version = new.renderer_version
     and old.generation_contract_version = new.generation_contract_version
     and old.semantic_contract_version = new.semantic_contract_version
     and old.supersedes_template_id is not distinct from new.supersedes_template_id
     and old.created_at = new.created_at and old.created_by = new.created_by then
    return new;
  end if;
  if v_transition = 'RETIRE'
     and old.status = 'APPROVED' and new.status = 'RETIRED'
     and old.id = new.id and old.template_id = new.template_id
     and old.template_version = new.template_version
     and old.request_kind = new.request_kind
     and old.document_type = new.document_type and old.locale = new.locale
     and old.currency = new.currency and old.template_sha256 = new.template_sha256
     and old.technical_master_filename = new.technical_master_filename
     and old.renderer_contract_version = new.renderer_contract_version
     and old.renderer_version = new.renderer_version
     and old.generation_contract_version = new.generation_contract_version
     and old.semantic_contract_version = new.semantic_contract_version
     and old.approved_at = new.approved_at and old.approved_by = new.approved_by
     and old.approval_reference = new.approval_reference
     and old.supersedes_template_id is not distinct from new.supersedes_template_id
     and old.created_at = new.created_at and old.created_by = new.created_by then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'QUOTATION_TEMPLATE_AUTHORITY_IMMUTABLE';
end;
$$;

create function public.register_quotation_template_candidate_for_product_v1(
  p_request_kind text,
  p_template_id text,
  p_template_version text,
  p_document_type text,
  p_locale text,
  p_currency text,
  p_template_sha256 text,
  p_technical_master_filename text,
  p_renderer_contract_version smallint,
  p_renderer_version text,
  p_generation_contract_version smallint,
  p_semantic_contract_version smallint,
  p_created_by text,
  p_event_reference text,
  p_supersedes_template_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_request_kind not in ('website', 'slimme_documentenflow')
     or p_document_type <> 'QUOTATION' or p_locale !~ '^[a-z]{2}(-[A-Z]{2})?$'
     or p_currency !~ '^[A-Z]{3}$' or p_template_sha256 !~ '^[0-9A-F]{64}$'
     or p_renderer_contract_version <> 1 or p_generation_contract_version <> 1
     or p_semantic_contract_version <> 1
     or nullif(btrim(p_template_id), '') is null
     or nullif(btrim(p_template_version), '') is null
     or nullif(btrim(p_technical_master_filename), '') is null
     or nullif(btrim(p_renderer_version), '') is null
     or nullif(btrim(p_created_by), '') is null
     or nullif(btrim(p_event_reference), '') is null then
    raise exception using errcode = '22023', message = 'TEMPLATE_AUTHORITY_INPUT_INVALID';
  end if;
  if p_supersedes_template_id is not null and not exists (
    select 1 from public.quotation_template_authorities
    where id = p_supersedes_template_id and request_kind = p_request_kind
  ) then
    raise exception using errcode = '22023', message = 'TEMPLATE_SUPERSESSION_PRODUCT_MISMATCH';
  end if;
  begin
    insert into public.quotation_template_authorities (
      request_kind, template_id, template_version, document_type, locale, currency,
      template_sha256, technical_master_filename, renderer_contract_version,
      renderer_version, generation_contract_version, semantic_contract_version,
      status, supersedes_template_id, created_by
    ) values (
      p_request_kind, p_template_id, p_template_version, p_document_type, p_locale,
      p_currency, p_template_sha256, p_technical_master_filename,
      p_renderer_contract_version, p_renderer_version,
      p_generation_contract_version, p_semantic_contract_version,
      'CANDIDATE', p_supersedes_template_id, p_created_by
    ) returning id into v_id;
  exception when unique_violation then
    raise exception using errcode = 'P0001', message = 'TEMPLATE_VERSION_CONFLICT';
  end;
  insert into public.quotation_template_authority_events (
    template_authority_id, event_type, actor, event_reference, evidence
  ) values (
    v_id, 'REGISTERED', p_created_by, p_event_reference,
    jsonb_build_object(
      'templateSha256', p_template_sha256, 'status', 'CANDIDATE',
      'requestKind', p_request_kind
    )
  );
  return v_id;
end;
$$;

create or replace function public.register_quotation_template_candidate_v1(
  p_template_id text,
  p_template_version text,
  p_document_type text,
  p_locale text,
  p_currency text,
  p_template_sha256 text,
  p_technical_master_filename text,
  p_renderer_contract_version smallint,
  p_renderer_version text,
  p_generation_contract_version smallint,
  p_semantic_contract_version smallint,
  p_created_by text,
  p_event_reference text,
  p_supersedes_template_id uuid default null
)
returns uuid
language sql
security definer
set search_path = public
as $$
  select public.register_quotation_template_candidate_for_product_v1(
    'website', p_template_id, p_template_version, p_document_type, p_locale,
    p_currency, p_template_sha256, p_technical_master_filename,
    p_renderer_contract_version, p_renderer_version,
    p_generation_contract_version, p_semantic_contract_version,
    p_created_by, p_event_reference, p_supersedes_template_id
  )
$$;

create function public.resolve_approved_quotation_template_for_product_v1(
  p_request_kind text,
  p_document_type text,
  p_locale text,
  p_currency text,
  p_renderer_contract_version smallint,
  p_generation_contract_version smallint,
  p_semantic_contract_version smallint
)
returns public.quotation_template_authorities
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_template public.quotation_template_authorities%rowtype;
begin
  if p_request_kind not in ('website', 'slimme_documentenflow') then
    raise exception using errcode = '22023', message = 'TEMPLATE_PRODUCT_INVALID';
  end if;
  select count(*) into v_count
  from public.quotation_template_authorities
  where request_kind = p_request_kind
    and document_type = p_document_type and locale = p_locale and currency = p_currency
    and renderer_contract_version = p_renderer_contract_version
    and generation_contract_version = p_generation_contract_version
    and semantic_contract_version = p_semantic_contract_version
    and status = 'APPROVED';
  if v_count = 0 then
    raise exception using errcode = 'P0001', message = 'QUOTATION_TEMPLATE_NOT_APPROVED';
  end if;
  if v_count <> 1 then
    raise exception using errcode = 'P0001', message = 'TEMPLATE_AUTHORITY_AMBIGUOUS';
  end if;
  select * into strict v_template
  from public.quotation_template_authorities
  where request_kind = p_request_kind
    and document_type = p_document_type and locale = p_locale and currency = p_currency
    and renderer_contract_version = p_renderer_contract_version
    and generation_contract_version = p_generation_contract_version
    and semantic_contract_version = p_semantic_contract_version
    and status = 'APPROVED';
  return v_template;
end;
$$;

create or replace function public.resolve_approved_quotation_template_v1(
  p_document_type text,
  p_locale text,
  p_currency text,
  p_renderer_contract_version smallint,
  p_generation_contract_version smallint,
  p_semantic_contract_version smallint
)
returns public.quotation_template_authorities
language sql
stable
security definer
set search_path = public
as $$
  select public.resolve_approved_quotation_template_for_product_v1(
    'website', p_document_type, p_locale, p_currency,
    p_renderer_contract_version, p_generation_contract_version,
    p_semantic_contract_version
  )
$$;

create function public.is_approved_quotation_template_identity_for_product_v1(
  p_request_kind text,
  p_template jsonb
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_request_kind in ('website', 'slimme_documentenflow')
    and public.is_valid_quotation_generation_template_v1(p_template, true)
    and exists (
      select 1 from public.quotation_template_authorities
      where request_kind = p_request_kind
        and template_id = p_template->>'template_id'
        and template_version = p_template->>'template_version'
        and rtrim(template_sha256) = upper(p_template->>'template_sha256')
        and document_type = 'QUOTATION' and locale = 'nl-BE' and currency = 'EUR'
        and renderer_contract_version = 1 and generation_contract_version = 1
        and semantic_contract_version = 1 and status = 'APPROVED'
    )
$$;

create or replace function public.is_approved_quotation_template_identity_v1(p_template jsonb)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_approved_quotation_template_identity_for_product_v1('website', p_template)
$$;

create function lws_internal.build_sdf_quotation_scope_snapshot_v1(
  p_answers jsonb,
  p_package_key text,
  p_payment_schedule jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_answers jsonb;
  v_capacities jsonb;
  v_evaluation jsonb;
  v_pricing jsonb;
  v_document_types jsonb;
  v_workflow_capabilities jsonb;
  v_milestones jsonb;
begin
  if p_package_key not in ('start', 'groei', 'pro', 'maatwerk')
     or not lws_internal.sdf_payload_valid_v3(p_answers, true)
    or not (p_payment_schedule ? 'milestones')
    or jsonb_typeof(p_payment_schedule->'milestones') <> 'array' then
    raise exception using errcode = '22023', message = 'SDF_SCOPE_SNAPSHOT_INPUT_INVALID';
  end if;
  v_answers := lws_internal.canonicalize_sdf_payload_v3(p_answers);
  v_capacities := lws_internal.get_sdf_budget_guard_capacity_input_v1(v_answers);
  v_evaluation := lws_internal.evaluate_sdf_budget_guard_v1(
    (v_capacities->>'flow_count')::bigint,
    (v_capacities->>'document_type_count')::bigint,
    (v_capacities->>'pages_per_month')::bigint,
    (v_capacities->>'user_count')::bigint
  );
  if v_evaluation->>'package' <> p_package_key then
    raise exception using errcode = '55000', message = 'SDF_SCOPE_PACKAGE_MISMATCH';
  end if;
  v_pricing := lws_internal.get_sdf_budget_guard_pricing_authority_v2(p_package_key);
  select jsonb_agg(volume->>'documentType' order by ordinal)
  into v_document_types
  from jsonb_array_elements(v_answers#>'{commercialQualification,documentVolumes}')
    with ordinality as item(volume, ordinal);
  v_workflow_capabilities := v_answers->'workflowCapabilities';
  v_milestones := p_payment_schedule->'milestones';
  return jsonb_build_object(
    'snapshot_contract_version', 1,
    'source_taxonomy_version', 'sdf_qualification_intake/3.0.0',
    'budget_guard_authority_version', 1,
    'pricing_authority_version', v_pricing->'authority_version',
    'package_key', p_package_key,
    'required_package_key', v_evaluation->'package',
    'implementation_amount_minor', v_pricing#>'{implementation,amount_minor}',
    'recurring_amount_minor', v_pricing#>'{recurring,amount_minor}',
    'payment_milestones', v_milestones,
    'selected_document_types', coalesce(v_document_types, '[]'::jsonb),
    'document_flow_count', v_capacities->'flow_count',
    'document_type_count', v_capacities->'document_type_count',
    'normalized_monthly_pages', v_capacities->'pages_per_month',
    'user_count', v_capacities->'user_count',
    'workflow_complexity', jsonb_build_object(
      'custom_complexity', v_answers#>'{commercialQualification,customComplexity}',
      'workflow_capabilities', v_workflow_capabilities
    ),
    'budget_guard_result', v_evaluation,
    'extra_work_line_items', '[]'::jsonb
  );
end;
$$;

create function public.is_valid_sdf_quotation_scope_snapshot_v1(p_scope jsonb)
returns boolean
language plpgsql
immutable
set search_path = public, pg_catalog
as $$
begin
  return public.jsonb_has_exact_keys(p_scope, array[
      'snapshot_contract_version', 'source_taxonomy_version',
      'budget_guard_authority_version', 'pricing_authority_version',
      'package_key', 'required_package_key', 'implementation_amount_minor',
      'recurring_amount_minor', 'payment_milestones', 'selected_document_types',
      'document_flow_count', 'document_type_count', 'normalized_monthly_pages',
      'user_count', 'workflow_complexity', 'budget_guard_result',
      'extra_work_line_items'
    ])
    and p_scope->>'snapshot_contract_version' = '1'
    and p_scope->>'source_taxonomy_version' = 'sdf_qualification_intake/3.0.0'
    and p_scope->>'budget_guard_authority_version' = '1'
    and p_scope->>'pricing_authority_version' = '2'
    and p_scope->>'package_key' in ('start', 'groei', 'pro', 'maatwerk')
    and p_scope->>'required_package_key' = p_scope->>'package_key'
    and jsonb_typeof(p_scope->'selected_document_types') = 'array'
    and jsonb_array_length(p_scope->'selected_document_types') =
      (p_scope->>'document_type_count')::integer
    and jsonb_typeof(p_scope->'payment_milestones') = 'array'
    and jsonb_typeof(p_scope->'workflow_complexity') = 'object'
    and jsonb_typeof(p_scope->'budget_guard_result') = 'object'
    and p_scope#>>'{budget_guard_result,package}' = p_scope->>'package_key'
    and jsonb_typeof(p_scope->'extra_work_line_items') = 'array'
    and public.is_jsonb_nonnegative_integer(p_scope->'document_flow_count')
    and public.is_jsonb_nonnegative_integer(p_scope->'document_type_count')
    and public.is_jsonb_nonnegative_integer(p_scope->'normalized_monthly_pages')
    and public.is_jsonb_nonnegative_integer(p_scope->'user_count')
    and (
      (p_scope->>'package_key' = 'maatwerk'
        and p_scope->'implementation_amount_minor' = 'null'::jsonb
        and p_scope->'recurring_amount_minor' = 'null'::jsonb)
      or
      (p_scope->>'package_key' <> 'maatwerk'
        and public.is_jsonb_nonnegative_integer(p_scope->'implementation_amount_minor')
        and public.is_jsonb_nonnegative_integer(p_scope->'recurring_amount_minor'))
    );
exception when others then
  return false;
end;
$$;

create or replace function public.is_valid_quotation_generation_payload_v1(p_payload jsonb)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  v_base_payload jsonb;
  v_line jsonb;
  v_milestone jsonb;
  v_previous_sequence bigint := 0;
  v_one_time bigint := 0;
  v_recurring bigint := 0;
  v_discount bigint := 0;
  v_quotation jsonb;
  v_totals jsonb;
begin
  if p_payload ? 'product_family' or p_payload ? 'sdf_scope' then
    if not (p_payload ?& array['product_family','sdf_scope'])
       or p_payload->>'product_family' <> 'slimme_documentenflow'
       or not public.is_valid_sdf_quotation_scope_snapshot_v1(p_payload->'sdf_scope') then
      return false;
    end if;
    v_base_payload := p_payload - 'product_family' - 'sdf_scope';
  else
    v_base_payload := p_payload;
  end if;
  if not public.jsonb_has_exact_keys(v_base_payload, array[
    'contract_version', 'mode', 'template', 'quotation', 'seller', 'customer',
    'project', 'lines', 'totals', 'vat', 'payment_schedule', 'validity',
    'legal_references', 'acceptance_instruction', 'pricing_references', 'locale'
  ])
    or v_base_payload->'contract_version' <> '1'::jsonb
    or v_base_payload->>'mode' not in ('PREVIEW', 'ISSUE')
    or not public.is_valid_quotation_generation_seller_v1(v_base_payload->'seller')
    or not public.is_valid_quotation_generation_template_v1(
      v_base_payload->'template', v_base_payload->>'mode' = 'ISSUE'
    )
    or not public.jsonb_has_exact_keys(v_base_payload->'locale', array[
      'document_language', 'document_locale', 'currency'
    ])
    or v_base_payload->'locale'->>'document_language' <> 'nl'
    or v_base_payload->'locale'->>'document_locale' <> 'nl-BE'
    or v_base_payload->'locale'->>'currency' <> 'EUR'
    or not public.jsonb_has_exact_keys(v_base_payload->'quotation', array[
      'approval_id', 'issuance_id', 'quotation_number', 'quotation_version',
      'quotation_status', 'visible_marker'
    ])
    or not public.jsonb_has_exact_keys(v_base_payload->'customer', array[
      'customer_id', 'legal_name', 'contact_name', 'email', 'address_line_1',
      'address_line_2', 'postal_code', 'city', 'country_code',
      'enterprise_number', 'vat_number'
    ])
    or jsonb_typeof(v_base_payload->'customer'->'legal_name') <> 'string'
    or nullif(btrim(v_base_payload->'customer'->>'legal_name'), '') is null
    or jsonb_typeof(v_base_payload->'customer'->'email') <> 'string'
    or not public.jsonb_has_exact_keys(v_base_payload->'project', array[
      'project_id', 'project_title', 'project_type', 'scope_summary',
      'requested_languages', 'included_page_count', 'features', 'copywriting',
      'seo', 'hosting', 'maintenance', 'exclusions', 'assumptions',
      'indicative_timing'
    ])
    or jsonb_typeof(v_base_payload->'project'->'project_title') <> 'string'
    or nullif(btrim(v_base_payload->'project'->>'project_title'), '') is null
    or jsonb_typeof(v_base_payload->'project'->'requested_languages') <> 'array'
    or jsonb_typeof(v_base_payload->'project'->'features') <> 'array'
    or not public.is_jsonb_nonnegative_integer(v_base_payload->'project'->'included_page_count')
    or not public.is_valid_quotation_lines_v1(v_base_payload->'lines')
    or not public.jsonb_has_exact_keys(v_base_payload->'totals', array[
      'subtotal_net_minor', 'one_time_subtotal_minor', 'recurring_subtotal_minor',
      'discount_total_minor', 'vat_base_minor', 'vat_amount_minor',
      'total_gross_minor'
    ])
    or not public.jsonb_has_exact_keys(v_base_payload->'vat', array[
      'vat_treatment', 'vat_rate', 'vat_decision_source'
    ])
    or jsonb_typeof(v_base_payload->'vat'->'vat_treatment') <> 'string'
    or jsonb_typeof(v_base_payload->'vat'->'vat_rate') <> 'number'
    or not public.jsonb_has_exact_keys(v_base_payload->'payment_schedule', array[
      'schedule_id', 'milestones'
    ])
    or jsonb_typeof(v_base_payload->'payment_schedule'->'milestones') <> 'array'
    or jsonb_array_length(v_base_payload->'payment_schedule'->'milestones') < 1
    or not public.jsonb_has_exact_keys(v_base_payload->'validity', array[
      'valid_from', 'valid_until', 'validity_days'
    ])
    or not public.jsonb_has_exact_keys(v_base_payload->'legal_references', array[
      'terms_reference', 'terms_version', 'agreement_reference',
      'agreement_version'
    ])
    or not public.jsonb_has_exact_keys(v_base_payload->'pricing_references', array[
      'approval_payload_sha256', 'pricing_snapshot_id',
      'pricing_snapshot_contract_version'
    ])
    or not public.is_sha256_jsonb(
      v_base_payload->'pricing_references'->'approval_payload_sha256'
    )
    or (v_base_payload->'pricing_references'->>'pricing_snapshot_id')
      !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or not public.is_jsonb_nonnegative_integer(
      v_base_payload->'pricing_references'->'pricing_snapshot_contract_version'
    )
    or jsonb_typeof(v_base_payload->'acceptance_instruction') <> 'string'
    or nullif(btrim(v_base_payload->>'acceptance_instruction'), '') is null then
    return false;
  end if;
  v_quotation := v_base_payload->'quotation';
  if (v_quotation->>'approval_id')
       !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or (v_base_payload->>'mode' = 'PREVIEW' and not (
       v_quotation->'issuance_id' = 'null'::jsonb
       and v_quotation->'quotation_number' = 'null'::jsonb
       and v_quotation->'quotation_version' = 'null'::jsonb
       and v_quotation->>'quotation_status' = 'NON_AUTHORITATIVE'
       and v_quotation->>'visible_marker' = 'CONCEPT — NIET GELDIG ALS OFFERTE'
     ))
     or (v_base_payload->>'mode' = 'ISSUE' and not (
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
  for v_line in select value from jsonb_array_elements(v_base_payload->'lines') loop
    if (v_line->>'sequence')::bigint <= v_previous_sequence then return false; end if;
    v_previous_sequence := (v_line->>'sequence')::bigint;
    if v_line->>'cost_type' = 'ONE_TIME' then
      v_one_time := v_one_time + (v_line->>'line_net_amount_minor')::bigint;
    else
      v_recurring := v_recurring + (v_line->>'line_net_amount_minor')::bigint;
    end if;
    v_discount := v_discount + (v_line->>'discount_minor')::bigint;
  end loop;
  v_totals := v_base_payload->'totals';
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
      = (v_totals->>'vat_base_minor')::bigint + (v_totals->>'vat_amount_minor')::bigint
  ) then return false; end if;
  if exists (
    select 1 from jsonb_array_elements(v_base_payload->'lines') as line
    where line->>'vat_treatment' is distinct from v_base_payload->'vat'->>'vat_treatment'
       or (line->>'vat_rate')::numeric
          is distinct from (v_base_payload->'vat'->>'vat_rate')::numeric
  ) then return false; end if;
  v_previous_sequence := 0;
  for v_milestone in select value from jsonb_array_elements(
    v_base_payload->'payment_schedule'->'milestones'
  ) loop
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
    (v_base_payload->'payment_schedule') || jsonb_build_object(
      'approved_by', 'generation-contract',
      'approved_at', '2000-01-01T00:00:00Z'
    ),
    (v_totals->>'one_time_subtotal_minor')::bigint,
    true
  ) and public.is_valid_quotation_validity_v1(
    (v_base_payload->'validity') || jsonb_build_object(
      'approved_by', 'generation-contract',
      'approved_at', '2000-01-01T00:00:00Z'
    ), true
  ) and (
    not (p_payload ? 'sdf_scope')
    or (
      p_payload->'sdf_scope'->'implementation_amount_minor'
        = v_totals->'one_time_subtotal_minor'
      and p_payload->'sdf_scope'->'recurring_amount_minor'
        = v_totals->'recurring_subtotal_minor'
      and p_payload->'sdf_scope'->'payment_milestones'
        = v_base_payload->'payment_schedule'->'milestones'
    )
  );
exception when others then return false;
end;
$$;

create or replace function public.is_valid_quotation_generation_payload_v1(p_payload jsonb)
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

create function public.is_valid_sdf_quotation_generation_payload_v1(p_payload jsonb)
returns boolean
language sql
immutable
security definer
set search_path = public, pg_catalog
as $$
  select public.jsonb_has_exact_keys(p_payload, array[
      'contract_version', 'mode', 'template', 'quotation', 'seller', 'customer',
      'project', 'lines', 'totals', 'vat', 'payment_schedule', 'validity',
      'legal_references', 'acceptance_instruction', 'pricing_references',
      'locale', 'product_family', 'sdf_scope'
    ])
    and p_payload->>'product_family' = 'slimme_documentenflow'
    and public.is_valid_quotation_generation_payload_v1(
      p_payload - 'product_family' - 'sdf_scope'
    )
    and public.is_valid_sdf_quotation_scope_snapshot_v1(p_payload->'sdf_scope')
    and p_payload->'sdf_scope'->'implementation_amount_minor'
      = p_payload->'totals'->'one_time_subtotal_minor'
    and p_payload->'sdf_scope'->'recurring_amount_minor'
      = p_payload->'totals'->'recurring_subtotal_minor'
    and p_payload->'sdf_scope'->'payment_milestones'
      = p_payload->'payment_schedule'->'milestones'
$$;

create function public.sdf_quotation_generation_payload_sha256_v1(p_payload jsonb)
returns text
language plpgsql
immutable
security definer
set search_path = public, extensions, pg_catalog
as $$
begin
  if not public.is_valid_sdf_quotation_generation_payload_v1(p_payload) then
    raise exception using errcode = '22023', message = 'INVALID_SDF_QUOTATION_GENERATION_PAYLOAD_V1';
  end if;
  return encode(extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256'), 'hex');
end;
$$;

create function lws_internal.is_approved_sdf_quotation_template_identity_v1(
  p_template jsonb
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select public.is_approved_quotation_template_identity_for_product_v1(
    'slimme_documentenflow', p_template
  )
$$;

create function lws_internal.project_sdf_quotation_generation_payload_v1(
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
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_answers jsonb;
  v_package_key text;
  v_scope jsonb;
  v_payload jsonb;
begin
  select submission.answers, decision.sdf_package
  into strict v_answers, v_package_key
  from public.quote_request_quotation_approvals approval
  join public.sdf_quotation_business_draft_adapters adapter
    on adapter.approval_draft_id = approval.draft_id
  join public.sdf_quotation_preparation_authorities preparation
    on preparation.authority_id = adapter.preparation_authority_id
  join public.sdf_quotation_commercial_decisions decision
    on decision.decision_id = adapter.commercial_decision_id
  join public.sdf_qualification_intake_submissions submission
    on submission.intake_id = preparation.qualification_intake_id
   and submission.submission_sequence = preparation.submission_sequence
  where approval.id = p_approval_id
    and approval.approved_payload = p_approved_payload
    and rtrim(approval.payload_sha256) = p_payload_sha256
    and decision.sdf_package = preparation.sdf_package
    and rtrim(submission.payload_sha256) = rtrim(preparation.submission_sha256);

  v_scope := lws_internal.build_sdf_quotation_scope_snapshot_v1(
    v_answers,
    v_package_key,
    p_approved_payload->'payment_schedule'
  );
  v_payload := public.project_quotation_generation_payload_v1(
    p_mode, p_approval_id, p_approved_payload, p_payload_sha256,
    p_template, p_seller, p_issuance_id, p_quotation_number,
    p_quotation_version
  ) || jsonb_build_object(
    'product_family', 'slimme_documentenflow',
    'sdf_scope', v_scope
  );
  return v_payload;
exception
  when no_data_found or too_many_rows then
    raise exception using errcode = '55000', message = 'SDF_SCOPE_AUTHORITY_STALE';
end;
$$;

do $$
declare
  v_definition text;
  v_rewritten text;
begin
  v_definition := pg_get_functiondef(
    'public.create_sdf_quotation_business_draft_v1(uuid,uuid,uuid)'::regprocedure
  );
  if strpos(
    v_definition,
    'public.resolve_approved_quotation_template_v1('
  ) = 0 then
    raise exception using errcode = '55000', message = 'SDF_TEMPLATE_RESOLVER_CALLSITE_DRIFT';
  end if;
  v_rewritten := replace(
    v_definition,
    'public.resolve_approved_quotation_template_v1(',
    'public.resolve_approved_quotation_template_for_product_v1(''slimme_documentenflow'', '
  );
  if v_rewritten = v_definition then
    raise exception using errcode = '55000', message = 'SDF_TEMPLATE_RESOLVER_CALLSITE_DRIFT';
  end if;
  execute v_rewritten;

  v_definition := pg_get_functiondef(
    'public.build_sdf_quotation_issue_payload_v1(uuid,uuid,integer,text,uuid)'::regprocedure
  );
    if strpos(v_definition, 'public.project_quotation_generation_payload_v1(') = 0
      or strpos(v_definition, 'public.is_approved_quotation_template_identity_v1(') = 0
        or strpos(v_definition, 'public.is_valid_quotation_generation_payload_v1(') = 0
        or strpos(v_definition, 'public.quotation_generation_payload_sha256_v1(') = 0 then
    raise exception using errcode = '55000', message = 'SDF_GENERATION_CALLSITE_DRIFT';
  end if;
  v_rewritten := replace(replace(replace(
    replace(
      v_definition,
      'public.project_quotation_generation_payload_v1(',
      'lws_internal.project_sdf_quotation_generation_payload_v1('
    ),
    'public.is_approved_quotation_template_identity_v1(',
    'lws_internal.is_approved_sdf_quotation_template_identity_v1('
  ),
    'public.is_valid_quotation_generation_payload_v1(',
    'public.is_valid_sdf_quotation_generation_payload_v1('
  ),
    'public.quotation_generation_payload_sha256_v1(',
    'public.sdf_quotation_generation_payload_sha256_v1('
  );
  if v_rewritten = v_definition then
    raise exception using errcode = '55000', message = 'SDF_GENERATION_CALLSITE_DRIFT';
  end if;
  execute v_rewritten;
end;
$$;

revoke all on function public.register_quotation_template_candidate_for_product_v1(
  text,text,text,text,text,text,text,text,smallint,text,smallint,smallint,text,text,uuid
) from public, anon, authenticated;
grant execute on function public.register_quotation_template_candidate_for_product_v1(
  text,text,text,text,text,text,text,text,smallint,text,smallint,smallint,text,text,uuid
) to service_role;
revoke all on function public.resolve_approved_quotation_template_for_product_v1(
  text,text,text,text,smallint,smallint,smallint
) from public, anon, authenticated;
grant execute on function public.resolve_approved_quotation_template_for_product_v1(
  text,text,text,text,smallint,smallint,smallint
) to service_role;
revoke all on function public.is_approved_quotation_template_identity_for_product_v1(text,jsonb)
from public, anon, authenticated;
grant execute on function public.is_approved_quotation_template_identity_for_product_v1(text,jsonb)
to service_role;
revoke all on function public.is_valid_sdf_quotation_scope_snapshot_v1(jsonb)
from public, anon, authenticated, service_role;
revoke all on function public.is_valid_sdf_quotation_generation_payload_v1(jsonb)
from public, anon, authenticated, service_role;
revoke all on function public.sdf_quotation_generation_payload_sha256_v1(jsonb)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.build_sdf_quotation_scope_snapshot_v1(jsonb,text,jsonb)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.is_approved_sdf_quotation_template_identity_v1(jsonb)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.project_sdf_quotation_generation_payload_v1(
  text,uuid,jsonb,text,jsonb,jsonb,uuid,text,integer
) from public, anon, authenticated, service_role;
