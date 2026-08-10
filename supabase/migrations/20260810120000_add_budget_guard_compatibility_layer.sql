alter table public.quote_requests
  add column budget_category_scheme text,
  add column budget_category_code text;

alter table public.quote_requests
  add constraint quote_requests_budget_category_v2_coherent
    check (
      (budget_category_scheme is null and budget_category_code is null)
      or (
        budget_category_scheme = 'budget_guard_v1'
        and budget_category_code in (
          'below_1800',
          '1800_to_below_3200',
          '3200_to_6000_inclusive',
          'above_6000'
        )
        and (
          (budget_category_code = 'below_1800' and budget = 'Minder dan EUR 1.800')
          or (budget_category_code = '1800_to_below_3200' and budget = 'EUR 1.800 tot minder dan EUR 3.200')
          or (budget_category_code = '3200_to_6000_inclusive' and budget = 'EUR 3.200 t/m EUR 6.000')
          or (budget_category_code = 'above_6000' and budget = 'Meer dan EUR 6.000')
        )
      )
    );

alter table public.quote_request_intakes
  add column primary_language text,
  add column additional_languages text[],
  add column page_scope_details jsonb,
  add column quote_form_details jsonb,
  add column multilingual_details jsonb,
  add column download_details jsonb,
  add column content_media_details jsonb,
  add column newsletter_details jsonb,
  add column hosting_maintenance_details jsonb,
  add column deadline_details jsonb,
  add column seo_details jsonb,
  add column budget_update_category_scheme text,
  add column budget_update_category_code text;

alter table public.quote_request_intakes
  add constraint quote_request_intakes_primary_language_not_blank
    check (primary_language is null or char_length(btrim(primary_language)) between 2 and 35),
  add constraint quote_request_intakes_page_scope_details_object
    check (page_scope_details is null or jsonb_typeof(page_scope_details) = 'object'),
  add constraint quote_request_intakes_quote_form_details_object
    check (quote_form_details is null or jsonb_typeof(quote_form_details) = 'object'),
  add constraint quote_request_intakes_multilingual_details_object
    check (multilingual_details is null or jsonb_typeof(multilingual_details) = 'object'),
  add constraint quote_request_intakes_download_details_object
    check (download_details is null or jsonb_typeof(download_details) = 'object'),
  add constraint quote_request_intakes_content_media_details_object
    check (content_media_details is null or jsonb_typeof(content_media_details) = 'object'),
  add constraint quote_request_intakes_newsletter_details_object
    check (newsletter_details is null or jsonb_typeof(newsletter_details) = 'object'),
  add constraint quote_request_intakes_hosting_maintenance_details_object
    check (hosting_maintenance_details is null or jsonb_typeof(hosting_maintenance_details) = 'object'),
  add constraint quote_request_intakes_deadline_details_object
    check (deadline_details is null or jsonb_typeof(deadline_details) = 'object'),
  add constraint quote_request_intakes_seo_details_object
    check (seo_details is null or jsonb_typeof(seo_details) = 'object'),
  add constraint quote_request_intakes_budget_category_v2_coherent
    check (
      (budget_update_category_scheme is null and budget_update_category_code is null)
      or (
        budget_update_category_scheme = 'budget_guard_v1'
        and budget_update_category_code in (
          'below_1800',
          '1800_to_below_3200',
          '3200_to_6000_inclusive',
          'above_6000'
        )
        and (
          (budget_update_category_code = 'below_1800' and budget_update_category = 'Minder dan EUR 1.800')
          or (budget_update_category_code = '1800_to_below_3200' and budget_update_category = 'EUR 1.800 tot minder dan EUR 3.200')
          or (budget_update_category_code = '3200_to_6000_inclusive' and budget_update_category = 'EUR 3.200 t/m EUR 6.000')
          or (budget_update_category_code = 'above_6000' and budget_update_category = 'Meer dan EUR 6.000')
        )
      )
    );

alter table public.quote_request_intakes
  drop constraint quote_request_intakes_budget_update_category_valid;

alter table public.quote_request_intakes
  add constraint quote_request_intakes_budget_update_category_valid
    check (
      budget_update_category is null
      or budget_update_category in (
        'Tot EUR 1.500',
        'EUR 1.500 - EUR 3.000',
        'EUR 3.000 - EUR 6.000',
        'Meer dan EUR 6.000',
        'Minder dan EUR 1.800',
        'EUR 1.800 tot minder dan EUR 3.200',
        'EUR 3.200 t/m EUR 6.000'
      )
    );

create table public.quote_request_pricing_snapshots (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid not null unique
    references public.quote_request_intakes (id)
    on delete cascade,
  config_version text not null,
  config_hash text not null,
  normalized_evidence jsonb not null,
  calculation jsonb not null,
  package_advice jsonb not null,
  budget_evaluation jsonb not null,
  created_at timestamptz not null default clock_timestamp(),

  constraint quote_request_pricing_snapshots_config_version_valid
    check (config_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  constraint quote_request_pricing_snapshots_config_hash_valid
    check (config_hash ~ '^[0-9a-f]{64}$'),
  constraint quote_request_pricing_snapshots_normalized_evidence_valid
    check (
      jsonb_typeof(normalized_evidence) = 'object'
      and jsonb_typeof(normalized_evidence->'standardPages') = 'array'
      and jsonb_typeof(normalized_evidence->'standardPageCount') = 'number'
      and (normalized_evidence->>'standardPageCount') ~ '^\d+$'
      and jsonb_typeof(normalized_evidence->'additionalLanguages') = 'array'
      and jsonb_typeof(normalized_evidence->'unknownLanguages') = 'array'
      and jsonb_typeof(normalized_evidence->'modules') = 'array'
      and jsonb_typeof(normalized_evidence->'manualComponents') = 'array'
    ),
  constraint quote_request_pricing_snapshots_calculation_valid
    check (
      jsonb_typeof(calculation) = 'object'
      and calculation->>'basis' = 'starter_floor'
      and calculation->>'currency' = 'EUR'
      and calculation->>'vatBasis' = 'exclusive'
      and jsonb_typeof(calculation->'knownMinimumMinor') = 'number'
      and (calculation->>'knownMinimumMinor') ~ '^\d+$'
      and jsonb_typeof(calculation->'containsFromPricing') = 'boolean'
      and jsonb_typeof(calculation->'manualReviewRequired') = 'boolean'
      and jsonb_typeof(calculation->'manualReasons') = 'array'
      and jsonb_typeof(calculation->'appliedRules') = 'array'
      and (
        (calculation->>'manualReviewRequired')::boolean
        or jsonb_array_length(calculation->'manualReasons') = 0
      )
      and (
        not (calculation->>'manualReviewRequired')::boolean
        or jsonb_array_length(calculation->'manualReasons') > 0
      )
    ),
  constraint quote_request_pricing_snapshots_package_advice_valid
    check (
      jsonb_typeof(package_advice) = 'object'
      and package_advice->>'status' in ('none', 'consider_professional', 'manual_scope_review')
      and jsonb_typeof(package_advice->'reasons') = 'array'
      and package_advice->'advisoryOnly' = 'true'::jsonb
      and package_advice ? 'selectedPackage'
      and package_advice->'selectedPackage' = 'null'::jsonb
    ),
  constraint quote_request_pricing_snapshots_budget_evaluation_valid
    check (
      jsonb_typeof(budget_evaluation) = 'object'
      and budget_evaluation->>'categoryCode' in (
        'below_1800',
        '1800_to_below_3200',
        '3200_to_6000_inclusive',
        'above_6000'
      )
      and budget_evaluation->>'status' in (
        'below_starter_starting_price',
        'known_minimum_exceeds_category_upper_bound',
        'possibly_compatible_with_category',
        'unbounded_category_indeterminate',
        'legacy_category_not_safely_comparable',
        'manual_review_required'
      )
      and (
        not (budget_evaluation ? 'outsideBudgetWishes')
        or jsonb_typeof(budget_evaluation->'outsideBudgetWishes') = 'array'
      )
    )
);

  comment on table public.quote_request_pricing_snapshots is
    'Submitted pricing snapshots cannot be mutated during the intake lifetime. Controlled deletion of the parent intake may remove its snapshot through ON DELETE CASCADE for privacy and data-retention lifecycle operations.';

alter table public.quote_request_pricing_snapshots enable row level security;

revoke all privileges
on table public.quote_request_pricing_snapshots
from public, anon, authenticated, service_role;

grant select
on table public.quote_request_pricing_snapshots
to service_role;

create function public.prevent_quote_request_pricing_snapshot_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception using errcode = '55000', message = 'PRICING_SNAPSHOT_IMMUTABLE';
end;
$$;

create trigger trg_quote_request_pricing_snapshots_immutable
before update on public.quote_request_pricing_snapshots
for each row
execute function public.prevent_quote_request_pricing_snapshot_update();

revoke all
on function public.prevent_quote_request_pricing_snapshot_update()
from public, anon, authenticated, service_role;

create function public.update_quote_request_intake_v2(
  p_access_token_hash text,
  p_action text,
  p_data jsonb,
  p_admin_access_token_hash text default null,
  p_admin_access_token_expires_at timestamptz default null,
  p_budget_guard_snapshot jsonb default null
)
returns table (
  outcome text,
  intake_status text,
  started_at timestamptz,
  submitted_at timestamptz,
  updated_at timestamptz,
  notification_job_id uuid,
  notification_job_status text,
  pricing_snapshot jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result record;
  v_intake public.quote_request_intakes%rowtype;
  v_snapshot public.quote_request_pricing_snapshots%rowtype;
  v_legacy_data jsonb;
  v_v2_keys constant text[] := array[
    'primary_language', 'additional_languages', 'page_scope_details',
    'quote_form_details', 'multilingual_details', 'download_details',
    'content_media_details', 'newsletter_details', 'hosting_maintenance_details',
    'deadline_details', 'seo_details', 'budget_update_category_scheme',
    'budget_update_category_code'
  ];
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' then
    raise exception using errcode = '22023', message = 'INVALID_INTAKE_DATA';
  end if;

  if p_action = 'save_draft' and p_budget_guard_snapshot is not null then
    raise exception using errcode = '22023', message = 'PRICING_SNAPSHOT_NOT_ALLOWED_FOR_DRAFT';
  end if;

  if p_action = 'submit'
     and (p_budget_guard_snapshot is null or jsonb_typeof(p_budget_guard_snapshot) <> 'object') then
    raise exception using errcode = '22023', message = 'PRICING_SNAPSHOT_REQUIRED_FOR_SUBMIT';
  end if;

  v_legacy_data := p_data - v_v2_keys;

  select *
    into v_result
    from public.update_quote_request_intake(
      p_access_token_hash,
      p_action,
      v_legacy_data,
      p_admin_access_token_hash,
      p_admin_access_token_expires_at
    );

  if v_result.outcome not in ('saved', 'submitted') then
    select snapshot.*
      into v_snapshot
      from public.quote_request_pricing_snapshots as snapshot
      inner join public.quote_request_intakes as intake
        on intake.id = snapshot.intake_id
      where intake.access_token_hash = p_access_token_hash;

    return query select
      v_result.outcome,
      v_result.intake_status,
      v_result.started_at,
      v_result.submitted_at,
      v_result.updated_at,
      v_result.notification_job_id,
      v_result.notification_job_status,
      case when v_snapshot.id is null then null else jsonb_build_object(
        'pricingConfigVersion', v_snapshot.config_version,
        'pricingConfigHash', v_snapshot.config_hash,
        'normalizedScope', v_snapshot.normalized_evidence,
        'calculation', v_snapshot.calculation,
        'packageAdvice', v_snapshot.package_advice,
        'budgetEvaluation', v_snapshot.budget_evaluation,
        'createdAt', v_snapshot.created_at
      ) end;
    return;
  end if;

  select *
    into v_intake
    from public.quote_request_intakes
    where access_token_hash = p_access_token_hash
    for update;

  update public.quote_request_intakes
  set
    primary_language = case when p_data ? 'primary_language' then nullif(btrim(p_data->>'primary_language'), '') else v_intake.primary_language end,
    additional_languages = case
      when not (p_data ? 'additional_languages') then v_intake.additional_languages
      when p_data->'additional_languages' = 'null'::jsonb then null
      else array(select jsonb_array_elements_text(p_data->'additional_languages'))
    end,
    page_scope_details = case when p_data ? 'page_scope_details' then nullif(p_data->'page_scope_details', 'null'::jsonb) else v_intake.page_scope_details end,
    quote_form_details = case when p_data ? 'quote_form_details' then nullif(p_data->'quote_form_details', 'null'::jsonb) else v_intake.quote_form_details end,
    multilingual_details = case when p_data ? 'multilingual_details' then nullif(p_data->'multilingual_details', 'null'::jsonb) else v_intake.multilingual_details end,
    download_details = case when p_data ? 'download_details' then nullif(p_data->'download_details', 'null'::jsonb) else v_intake.download_details end,
    content_media_details = case when p_data ? 'content_media_details' then nullif(p_data->'content_media_details', 'null'::jsonb) else v_intake.content_media_details end,
    newsletter_details = case when p_data ? 'newsletter_details' then nullif(p_data->'newsletter_details', 'null'::jsonb) else v_intake.newsletter_details end,
    hosting_maintenance_details = case when p_data ? 'hosting_maintenance_details' then nullif(p_data->'hosting_maintenance_details', 'null'::jsonb) else v_intake.hosting_maintenance_details end,
    deadline_details = case when p_data ? 'deadline_details' then nullif(p_data->'deadline_details', 'null'::jsonb) else v_intake.deadline_details end,
    seo_details = case when p_data ? 'seo_details' then nullif(p_data->'seo_details', 'null'::jsonb) else v_intake.seo_details end,
    budget_update_category_scheme = case when p_data ? 'budget_update_category_scheme' then nullif(p_data->>'budget_update_category_scheme', '') else v_intake.budget_update_category_scheme end,
    budget_update_category_code = case when p_data ? 'budget_update_category_code' then nullif(p_data->>'budget_update_category_code', '') else v_intake.budget_update_category_code end
  where id = v_intake.id
  returning * into v_intake;

  if v_result.outcome = 'submitted' then
     if jsonb_typeof(p_budget_guard_snapshot->'budgetEvaluation') is distinct from 'object'
       or v_intake.budget_update_category_scheme <> 'budget_guard_v1'
       or v_intake.budget_update_category_code is null
       or p_budget_guard_snapshot->'budgetEvaluation'->>'categoryCode'
         is distinct from v_intake.budget_update_category_code then
      raise exception using errcode = '22023', message = 'PRICING_SNAPSHOT_BUDGET_MISMATCH';
    end if;

    insert into public.quote_request_pricing_snapshots (
      intake_id,
      config_version,
      config_hash,
      normalized_evidence,
      calculation,
      package_advice,
      budget_evaluation
    ) values (
      v_intake.id,
      p_budget_guard_snapshot->>'pricingConfigVersion',
      p_budget_guard_snapshot->>'pricingConfigHash',
      p_budget_guard_snapshot->'normalizedScope',
      p_budget_guard_snapshot->'calculation',
      p_budget_guard_snapshot->'packageAdvice',
      p_budget_guard_snapshot->'budgetEvaluation'
    )
    returning * into v_snapshot;
  end if;

  return query select
    v_result.outcome,
    v_result.intake_status,
    v_intake.started_at,
    v_intake.submitted_at,
    v_intake.updated_at,
    v_result.notification_job_id,
    v_result.notification_job_status,
    case when v_snapshot.id is null then null else jsonb_build_object(
      'pricingConfigVersion', v_snapshot.config_version,
      'pricingConfigHash', v_snapshot.config_hash,
      'normalizedScope', v_snapshot.normalized_evidence,
      'calculation', v_snapshot.calculation,
      'packageAdvice', v_snapshot.package_advice,
      'budgetEvaluation', v_snapshot.budget_evaluation,
      'createdAt', v_snapshot.created_at
    ) end;
end;
$$;

comment on function public.update_quote_request_intake_v2(text, text, jsonb, text, timestamptz, jsonb) is
  'Trusted server-side mutation boundary. p_budget_guard_snapshot is authoritative only when supplied by service-role backend code; browsers and frontend clients must never construct or persist authoritative pricing snapshots directly.';

revoke all
on function public.update_quote_request_intake_v2(text, text, jsonb, text, timestamptz, jsonb)
from public, anon, authenticated;

grant execute
on function public.update_quote_request_intake_v2(text, text, jsonb, text, timestamptz, jsonb)
to service_role;

create function public.create_quote_request_idempotent_v2(
  p_idempotency_key uuid,
  p_request_fingerprint text,
  p_name text,
  p_customer_type text,
  p_company text,
  p_enterprise_number text,
  p_enterprise_validation_status text,
  p_vat_number text,
  p_vat_validation_status text,
  p_vat_validated_at timestamptz,
  p_billing_address text,
  p_billing_postal_code text,
  p_billing_city text,
  p_billing_country text,
  p_billing_email text,
  p_email text,
  p_phone text,
  p_website_type text,
  p_budget text,
  p_timing text,
  p_description text,
  p_privacy_consent boolean,
  p_approval_token_hash text,
  p_approval_token_expires_at timestamptz,
  p_client_ip_hash text,
  p_user_agent text,
  p_budget_category_scheme text,
  p_budget_category_code text
)
returns table (
  request_id uuid,
  request_created_at timestamptz,
  was_created boolean,
  admin_job_id uuid,
  admin_job_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result record;
  v_request public.quote_requests%rowtype;
begin
  if p_budget_category_scheme is distinct from 'budget_guard_v1'
     or p_budget_category_code is null
     or p_budget_category_code not in (
       'below_1800',
       '1800_to_below_3200',
       '3200_to_6000_inclusive',
       'above_6000'
     )
     or not (
       (p_budget_category_code = 'below_1800' and p_budget = 'Minder dan EUR 1.800')
       or (p_budget_category_code = '1800_to_below_3200' and p_budget = 'EUR 1.800 tot minder dan EUR 3.200')
       or (p_budget_category_code = '3200_to_6000_inclusive' and p_budget = 'EUR 3.200 t/m EUR 6.000')
       or (p_budget_category_code = 'above_6000' and p_budget = 'Meer dan EUR 6.000')
     ) then
    raise exception using errcode = '22023', message = 'INVALID_BUDGET_CATEGORY_V2';
  end if;

  select *
    into v_result
    from public.create_quote_request_idempotent(
      p_idempotency_key,
      p_request_fingerprint,
      p_name,
      p_customer_type,
      p_company,
      p_enterprise_number,
      p_enterprise_validation_status,
      p_vat_number,
      p_vat_validation_status,
      p_vat_validated_at,
      p_billing_address,
      p_billing_postal_code,
      p_billing_city,
      p_billing_country,
      p_billing_email,
      p_email,
      p_phone,
      p_website_type,
      p_budget,
      p_timing,
      p_description,
      p_privacy_consent,
      p_approval_token_hash,
      p_approval_token_expires_at,
      p_client_ip_hash,
      p_user_agent
    );

  select *
    into v_request
    from public.quote_requests
    where id = v_result.request_id
    for update;

  if v_result.was_created then
    update public.quote_requests
    set
      budget_category_scheme = p_budget_category_scheme,
      budget_category_code = p_budget_category_code
    where id = v_request.id;
  elsif v_request.budget_category_scheme is distinct from p_budget_category_scheme
        or v_request.budget_category_code is distinct from p_budget_category_code then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
  end if;

  return query select
    v_result.request_id,
    v_result.request_created_at,
    v_result.was_created,
    v_result.admin_job_id,
    v_result.admin_job_status;
end;
$$;

revoke all
on function public.create_quote_request_idempotent_v2(uuid, text, text, text, text, text, text, text, text, timestamptz, text, text, text, text, text, text, text, text, text, text, text, boolean, text, timestamptz, text, text, text, text)
from public, anon, authenticated;

grant execute
on function public.create_quote_request_idempotent_v2(uuid, text, text, text, text, text, text, text, text, timestamptz, text, text, text, text, text, text, text, text, text, text, text, boolean, text, timestamptz, text, text, text, text)
to service_role;

create function public.inspect_quote_request_intake_details_v2(p_access_token_hash text)
returns table (
  intake_id uuid,
  intake_status text,
  quote_request_created_at timestamptz,
  name text,
  company text,
  email text,
  phone text,
  website_type text,
  budget text,
  timing text,
  description text,
  started_at timestamptz,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  intake_data jsonb,
  pricing_snapshot jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    legacy.intake_id,
    legacy.intake_status,
    legacy.quote_request_created_at,
    legacy.name,
    legacy.company,
    legacy.email,
    legacy.phone,
    legacy.website_type,
    legacy.budget,
    legacy.timing,
    legacy.description,
    legacy.started_at,
    legacy.submitted_at,
    legacy.reviewed_at,
    legacy.intake_data || jsonb_build_object(
      'primary_language', intake.primary_language,
      'additional_languages', intake.additional_languages,
      'page_scope_details', intake.page_scope_details,
      'quote_form_details', intake.quote_form_details,
      'multilingual_details', intake.multilingual_details,
      'download_details', intake.download_details,
      'content_media_details', intake.content_media_details,
      'newsletter_details', intake.newsletter_details,
      'hosting_maintenance_details', intake.hosting_maintenance_details,
      'deadline_details', intake.deadline_details,
      'seo_details', intake.seo_details,
      'budget_update_category_scheme', intake.budget_update_category_scheme,
      'budget_update_category_code', intake.budget_update_category_code
    ),
    case when snapshot.id is null then null else jsonb_build_object(
      'pricingConfigVersion', snapshot.config_version,
      'pricingConfigHash', snapshot.config_hash,
      'normalizedScope', snapshot.normalized_evidence,
      'calculation', snapshot.calculation,
      'packageAdvice', snapshot.package_advice,
      'budgetEvaluation', snapshot.budget_evaluation,
      'createdAt', snapshot.created_at
    ) end
  from public.inspect_quote_request_intake_details(p_access_token_hash) as legacy
  inner join public.quote_request_intakes as intake
    on intake.id = legacy.intake_id
  left join public.quote_request_pricing_snapshots as snapshot
    on snapshot.intake_id = intake.id
$$;

revoke all
on function public.inspect_quote_request_intake_details_v2(text)
from public, anon, authenticated;

grant execute
on function public.inspect_quote_request_intake_details_v2(text)
to service_role;

create function public.inspect_submitted_intake_for_admin_v2(p_admin_access_token_hash text)
returns table (
  intake_id uuid,
  intake_status text,
  quote_request_id uuid,
  quote_request_created_at timestamptz,
  name text,
  company text,
  email text,
  phone text,
  website_type text,
  budget text,
  timing text,
  description text,
  started_at timestamptz,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  intake_data jsonb,
  pricing_snapshot jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    legacy.intake_id,
    legacy.intake_status,
    legacy.quote_request_id,
    legacy.quote_request_created_at,
    legacy.name,
    legacy.company,
    legacy.email,
    legacy.phone,
    legacy.website_type,
    legacy.budget,
    legacy.timing,
    legacy.description,
    legacy.started_at,
    legacy.submitted_at,
    legacy.reviewed_at,
    legacy.intake_data || jsonb_build_object(
      'primary_language', intake.primary_language,
      'additional_languages', intake.additional_languages,
      'page_scope_details', intake.page_scope_details,
      'quote_form_details', intake.quote_form_details,
      'multilingual_details', intake.multilingual_details,
      'download_details', intake.download_details,
      'content_media_details', intake.content_media_details,
      'newsletter_details', intake.newsletter_details,
      'hosting_maintenance_details', intake.hosting_maintenance_details,
      'deadline_details', intake.deadline_details,
      'seo_details', intake.seo_details,
      'budget_update_category_scheme', intake.budget_update_category_scheme,
      'budget_update_category_code', intake.budget_update_category_code
    ),
    case when snapshot.id is null then null else jsonb_build_object(
      'pricingConfigVersion', snapshot.config_version,
      'pricingConfigHash', snapshot.config_hash,
      'normalizedScope', snapshot.normalized_evidence,
      'calculation', snapshot.calculation,
      'packageAdvice', snapshot.package_advice,
      'budgetEvaluation', snapshot.budget_evaluation,
      'createdAt', snapshot.created_at
    ) end
  from public.inspect_submitted_intake_for_admin(p_admin_access_token_hash) as legacy
  inner join public.quote_request_intakes as intake
    on intake.id = legacy.intake_id
  left join public.quote_request_pricing_snapshots as snapshot
    on snapshot.intake_id = intake.id
$$;

revoke all
on function public.inspect_submitted_intake_for_admin_v2(text)
from public, anon, authenticated;

grant execute
on function public.inspect_submitted_intake_for_admin_v2(text)
to service_role;