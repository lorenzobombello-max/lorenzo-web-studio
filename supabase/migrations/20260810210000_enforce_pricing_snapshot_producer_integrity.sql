create table public.quote_request_pricing_snapshot_integrity (
  snapshot_id uuid primary key
    references public.quote_request_pricing_snapshots (id)
    on delete cascade,
  algorithm_version text not null,
  key_id text not null,
  mac text not null,
  created_at timestamptz not null default clock_timestamp(),

  constraint quote_request_pricing_snapshot_integrity_algorithm_valid
    check (algorithm_version = 'hmac-sha256-v1'),
  constraint quote_request_pricing_snapshot_integrity_key_id_valid
    check (key_id ~ '^v[1-9][0-9]*$'),
  constraint quote_request_pricing_snapshot_integrity_mac_valid
    check (mac ~ '^[0-9a-f]{64}$')
);

comment on table public.quote_request_pricing_snapshot_integrity is
  'Immutable producer-authenticity proof attached atomically to a newly submitted pricing snapshot. The signing key remains exclusively in the Edge runtime.';

alter table public.quote_request_pricing_snapshot_integrity enable row level security;

revoke all privileges
on table public.quote_request_pricing_snapshot_integrity
from public, anon, authenticated, service_role;

create trigger trg_quote_request_pricing_snapshot_integrity_immutable
before update on public.quote_request_pricing_snapshot_integrity
for each row
execute function public.prevent_quote_request_pricing_snapshot_update();

create function public.has_canonical_pricing_snapshot_v2_evidence(
  p_normalized_scope jsonb
)
returns boolean
language plpgsql
stable
set search_path = public
as $$
declare
  v_module jsonb;
  v_module_id text;
begin
  if p_normalized_scope->'primaryLanguage' <> 'null'::jsonb
     and exists (
       select 1
       from jsonb_array_elements_text(p_normalized_scope->'additionalLanguages') as language(value)
       where language.value = p_normalized_scope->>'primaryLanguage'
     ) then
    return false;
  end if;

  for v_module in
    select value from jsonb_array_elements(p_normalized_scope->'modules')
  loop
    v_module_id := v_module->>'id';
    if jsonb_array_length(v_module->'evidence') = 0
       or jsonb_array_length(v_module->'evidence') <> (
         select count(distinct evidence.value)
         from jsonb_array_elements_text(v_module->'evidence') as evidence(value)
       )
       or exists (
         select 1
         from jsonb_array_elements_text(v_module->'evidence') as evidence(value)
         where not (
           (v_module_id = 'shop' and evidence.value in (
             'requested_pages.shop', 'requested_features.shop',
             'requested_features.online_payment', 'website_goals.sell_products',
             'shop_required', 'shop_details'
           ))
           or (v_module_id = 'booking' and evidence.value in (
             'requested_pages.reservations', 'requested_features.appointments',
             'website_goals.appointments', 'requested_features.reservations',
             'website_goals.reservations', 'booking_required', 'booking_details'
           ))
           or (v_module_id = 'forms' and evidence.value in (
             'requested_pages.quote_request', 'requested_features.quote_form',
             'website_goals.quote_requests', 'contact_form_intent'
           ))
           or (v_module_id = 'multilingual' and evidence.value in (
             'additional_languages', 'unknown_languages', 'multilingual_details'
           ))
           or (v_module_id = 'content_media' and evidence.value = 'content_media')
           or (v_module_id = 'hosting_maintenance' and evidence.value = 'hosting_maintenance')
           or (v_module_id = 'seo' and evidence.value = 'seo')
         )
       ) then
      return false;
    end if;

    if v_module_id = 'multilingual' and (
      not (v_module->'evidence' ? 'multilingual_details')
      or ((v_module->'evidence' ? 'additional_languages') is distinct from
        (jsonb_array_length(p_normalized_scope->'additionalLanguages') > 0))
      or ((v_module->'evidence' ? 'unknown_languages') is distinct from
        (jsonb_array_length(p_normalized_scope->'unknownLanguages') > 0))
      or (
        v_module->>'classification' = 'normal'
        and (
          jsonb_array_length(p_normalized_scope->'additionalLanguages') = 0
          or jsonb_array_length(p_normalized_scope->'unknownLanguages') > 0
        )
      )
    ) then
      return false;
    end if;
  end loop;

  if (
    jsonb_array_length(p_normalized_scope->'additionalLanguages') > 0
    or jsonb_array_length(p_normalized_scope->'unknownLanguages') > 0
  ) is distinct from exists (
    select 1
    from jsonb_array_elements(p_normalized_scope->'modules') as module(value)
    where module.value->>'id' = 'multilingual'
  ) then
    return false;
  end if;

  return true;
exception
  when others then
    return false;
end;
$$;

create or replace function public.is_strict_pricing_snapshot_v2(
  p_snapshot_contract_version smallint,
  p_config_version text,
  p_config_hash text,
  p_normalized_scope jsonb,
  p_calculation jsonb,
  p_package_advice jsonb,
  p_budget_evaluation jsonb
)
returns boolean
language plpgsql
stable
set search_path = public
as $$
begin
  if not coalesce(public.is_structurally_valid_pricing_snapshot_v2(
    p_snapshot_contract_version,
    p_config_version,
    p_config_hash,
    p_normalized_scope,
    p_calculation,
    p_package_advice,
    p_budget_evaluation
  ), false) then
    return false;
  end if;

  return public.has_canonical_pricing_snapshot_v2_semantics(
    p_normalized_scope,
    p_calculation,
    p_package_advice
  ) and public.has_canonical_pricing_snapshot_v2_evidence(p_normalized_scope);
exception
  when others then
    return false;
end;
$$;

create function public.update_quote_request_intake_v4(
  p_access_token_hash text,
  p_action text,
  p_data jsonb,
  p_admin_access_token_hash text default null,
  p_admin_access_token_expires_at timestamptz default null,
  p_budget_guard_snapshot jsonb default null,
  p_pricing_snapshot_integrity jsonb default null
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
  v_snapshot_id uuid;
  v_integrity_keys constant text[] := array['algorithmVersion', 'keyId', 'mac'];
begin
  if p_action <> 'submit'
     or p_pricing_snapshot_integrity is null
     or jsonb_typeof(p_pricing_snapshot_integrity) <> 'object'
     or not (p_pricing_snapshot_integrity ?& v_integrity_keys)
     or exists (
       select 1
       from jsonb_object_keys(p_pricing_snapshot_integrity) as supplied(key)
       where not (supplied.key = any(v_integrity_keys))
     )
     or p_pricing_snapshot_integrity->>'algorithmVersion' <> 'hmac-sha256-v1'
     or p_pricing_snapshot_integrity->>'keyId' !~ '^v[1-9][0-9]*$'
     or p_pricing_snapshot_integrity->>'mac' !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'INVALID_PRICING_SNAPSHOT_INTEGRITY';
  end if;

  select * into v_result
  from public.update_quote_request_intake_v3(
    p_access_token_hash,
    p_action,
    p_data,
    p_admin_access_token_hash,
    p_admin_access_token_expires_at,
    p_budget_guard_snapshot
  );

  if v_result.outcome = 'submitted' then
    select snapshot.id into strict v_snapshot_id
    from public.quote_request_pricing_snapshots as snapshot
    inner join public.quote_request_intakes as intake on intake.id = snapshot.intake_id
    where intake.access_token_hash = p_access_token_hash;

    insert into public.quote_request_pricing_snapshot_integrity (
      snapshot_id, algorithm_version, key_id, mac
    ) values (
      v_snapshot_id,
      p_pricing_snapshot_integrity->>'algorithmVersion',
      p_pricing_snapshot_integrity->>'keyId',
      p_pricing_snapshot_integrity->>'mac'
    );
  end if;

  return query select
    v_result.outcome,
    v_result.intake_status,
    v_result.started_at,
    v_result.submitted_at,
    v_result.updated_at,
    v_result.notification_job_id,
    v_result.notification_job_status,
    v_result.pricing_snapshot;
end;
$$;

revoke all
on function public.has_canonical_pricing_snapshot_v2_evidence(jsonb)
from public, anon, authenticated;

revoke all
on function public.update_quote_request_intake_v3(text, text, jsonb, text, timestamptz, jsonb)
from public, anon, authenticated, service_role;

revoke all
on function public.inspect_customer_pricing_read_v1(text)
from public, anon, authenticated, service_role;

revoke all
on function public.inspect_admin_pricing_read_v1(text)
from public, anon, authenticated, service_role;

revoke all
on function public.update_quote_request_intake_v4(text, text, jsonb, text, timestamptz, jsonb, jsonb)
from public, anon, authenticated;

grant execute
on function public.has_canonical_pricing_snapshot_v2_evidence(jsonb)
to service_role;

grant execute
on function public.update_quote_request_intake_v4(text, text, jsonb, text, timestamptz, jsonb, jsonb)
to service_role;

create function public.inspect_customer_pricing_read_v2(p_access_token_hash text)
returns table (
  intake_status text,
  snapshot_present boolean,
  snapshot_contract_version smallint,
  calculation_basis text,
  currency text,
  vat_basis text,
  known_minimum_minor bigint,
  contains_from_pricing boolean,
  manual_review_required boolean,
  manual_reason_count integer,
  budget_contract_version smallint,
  evidence_provenance text,
  budget_status text,
  outside_budget_wishes boolean,
  integrity_snapshot jsonb,
  integrity_context text,
  integrity_metadata jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    intake.status::text,
    snapshot.id is not null and validity.is_disclosable,
    case when validity.is_disclosable then snapshot.snapshot_contract_version end,
    case when validity.is_disclosable then snapshot.calculation->>'basis' end,
    case when validity.is_disclosable then snapshot.calculation->>'currency' end,
    case when validity.is_disclosable then snapshot.calculation->>'vatBasis' end,
    case when validity.is_disclosable then (snapshot.calculation->>'knownMinimumMinor')::bigint end,
    case when validity.is_disclosable then (snapshot.calculation->>'containsFromPricing')::boolean end,
    case when validity.is_disclosable then (snapshot.calculation->>'manualReviewRequired')::boolean end,
    case when validity.is_disclosable then jsonb_array_length(snapshot.calculation->'manualReasons') end,
    case when validity.is_disclosable then (snapshot.budget_evaluation->>'contractVersion')::smallint end,
    case when validity.is_disclosable then snapshot.budget_evaluation->>'evidenceProvenance' end,
    case when validity.is_disclosable then snapshot.budget_evaluation->>'status' end,
    case when validity.is_disclosable and jsonb_typeof(snapshot.budget_evaluation->'outsideBudgetWishes') = 'boolean'
      then (snapshot.budget_evaluation->>'outsideBudgetWishes')::boolean end,
    case when validity.is_disclosable then jsonb_build_object(
      'snapshotContractVersion', snapshot.snapshot_contract_version,
      'pricingConfigVersion', snapshot.config_version,
      'pricingConfigHash', snapshot.config_hash,
      'normalizedScope', snapshot.normalized_evidence,
      'calculation', snapshot.calculation,
      'packageAdvice', snapshot.package_advice,
      'budgetEvaluation', snapshot.budget_evaluation
    ) end,
    case when validity.is_disclosable then snapshot.intake_id::text end,
    case when validity.is_disclosable then jsonb_build_object(
      'algorithmVersion', integrity.algorithm_version,
      'keyId', integrity.key_id,
      'mac', integrity.mac
    ) end
  from public.quote_request_intakes as intake
  left join public.quote_request_pricing_snapshots as snapshot on snapshot.intake_id = intake.id
  left join public.quote_request_pricing_snapshot_integrity as integrity on integrity.snapshot_id = snapshot.id
  cross join lateral (
    select coalesce(public.is_strict_pricing_snapshot_v2(
      snapshot.snapshot_contract_version, snapshot.config_version, snapshot.config_hash,
      snapshot.normalized_evidence, snapshot.calculation, snapshot.package_advice,
      snapshot.budget_evaluation
    ), false) and integrity.snapshot_id is not null as is_disclosable
  ) as validity
  where p_access_token_hash ~ '^[0-9a-f]{64}$'
    and intake.access_token_hash = p_access_token_hash
    and intake.access_token_expires_at > clock_timestamp()
    and intake.access_token_revoked_at is null
    and intake.status in ('submitted', 'reviewed')
    and intake.submitted_at is not null
  limit 1
$$;

create function public.inspect_admin_pricing_read_v2(p_admin_access_token_hash text)
returns table (
  intake_status text,
  snapshot_present boolean,
  snapshot_contract_version smallint,
  snapshot_created_at timestamptz,
  config_version text,
  config_hash text,
  normalized_scope jsonb,
  calculation jsonb,
  package_advice jsonb,
  budget_evaluation jsonb,
  integrity_snapshot jsonb,
  integrity_context text,
  integrity_metadata jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    intake.status::text,
    snapshot.id is not null and validity.is_disclosable,
    case when validity.is_disclosable then snapshot.snapshot_contract_version end,
    case when validity.is_disclosable then snapshot.created_at end,
    case when validity.is_disclosable then snapshot.config_version end,
    case when validity.is_disclosable then snapshot.config_hash end,
    case when validity.is_disclosable then snapshot.normalized_evidence end,
    case when validity.is_disclosable then snapshot.calculation end,
    case when validity.is_disclosable then snapshot.package_advice end,
    case when validity.is_disclosable and validity.is_strict_v2 then snapshot.budget_evaluation end,
    case when validity.is_strict_v2 and integrity.snapshot_id is not null then jsonb_build_object(
      'snapshotContractVersion', snapshot.snapshot_contract_version,
      'pricingConfigVersion', snapshot.config_version,
      'pricingConfigHash', snapshot.config_hash,
      'normalizedScope', snapshot.normalized_evidence,
      'calculation', snapshot.calculation,
      'packageAdvice', snapshot.package_advice,
      'budgetEvaluation', snapshot.budget_evaluation
    ) end,
    case when validity.is_strict_v2 and integrity.snapshot_id is not null then snapshot.intake_id::text end,
    case when validity.is_strict_v2 and integrity.snapshot_id is not null then jsonb_build_object(
      'algorithmVersion', integrity.algorithm_version,
      'keyId', integrity.key_id,
      'mac', integrity.mac
    ) end
  from public.quote_request_intakes as intake
  left join public.quote_request_pricing_snapshots as snapshot on snapshot.intake_id = intake.id
  left join public.quote_request_pricing_snapshot_integrity as integrity on integrity.snapshot_id = snapshot.id
  cross join lateral (
    select
      coalesce(public.is_strict_pricing_snapshot_v2(
        snapshot.snapshot_contract_version, snapshot.config_version, snapshot.config_hash,
        snapshot.normalized_evidence, snapshot.calculation, snapshot.package_advice,
        snapshot.budget_evaluation
      ), false) as is_strict_v2,
      snapshot.snapshot_contract_version is null as is_historical_v1
  ) as contract
  cross join lateral (
    select
      contract.is_strict_v2,
      contract.is_historical_v1 or (contract.is_strict_v2 and integrity.snapshot_id is not null)
        as is_disclosable
  ) as validity
  where p_admin_access_token_hash ~ '^[0-9a-f]{64}$'
    and intake.admin_access_token_hash = p_admin_access_token_hash
    and intake.admin_access_token_expires_at > clock_timestamp()
    and intake.admin_access_token_revoked_at is null
    and intake.status = 'submitted'
    and intake.submitted_at is not null
  limit 1
$$;

revoke all
on function public.inspect_customer_pricing_read_v2(text)
from public, anon, authenticated;

revoke all
on function public.inspect_admin_pricing_read_v2(text)
from public, anon, authenticated;

grant execute
on function public.inspect_customer_pricing_read_v2(text)
to service_role;

grant execute
on function public.inspect_admin_pricing_read_v2(text)
to service_role;