create function public.inspect_customer_pricing_read_v1(p_access_token_hash text)
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
  outside_budget_wishes boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    intake.status::text,
    snapshot.id is not null,
    snapshot.snapshot_contract_version,
    snapshot.calculation->>'basis',
    snapshot.calculation->>'currency',
    snapshot.calculation->>'vatBasis',
    case
      when jsonb_typeof(snapshot.calculation->'knownMinimumMinor') = 'number'
        and (snapshot.calculation->>'knownMinimumMinor') ~ '^\d+$'
      then (snapshot.calculation->>'knownMinimumMinor')::bigint
      else null
    end,
    case
      when jsonb_typeof(snapshot.calculation->'containsFromPricing') = 'boolean'
      then (snapshot.calculation->>'containsFromPricing')::boolean
      else null
    end,
    case
      when jsonb_typeof(snapshot.calculation->'manualReviewRequired') = 'boolean'
      then (snapshot.calculation->>'manualReviewRequired')::boolean
      else null
    end,
    case
      when jsonb_typeof(snapshot.calculation->'manualReasons') = 'array'
      then jsonb_array_length(snapshot.calculation->'manualReasons')
      else null
    end,
    case
      when jsonb_typeof(snapshot.budget_evaluation->'contractVersion') = 'number'
        and (snapshot.budget_evaluation->>'contractVersion') ~ '^\d+$'
      then (snapshot.budget_evaluation->>'contractVersion')::smallint
      else null
    end,
    snapshot.budget_evaluation->>'evidenceProvenance',
    snapshot.budget_evaluation->>'status',
    case
      when jsonb_typeof(snapshot.budget_evaluation->'outsideBudgetWishes') = 'boolean'
      then (snapshot.budget_evaluation->>'outsideBudgetWishes')::boolean
      else null
    end
  from public.quote_request_intakes as intake
  left join public.quote_request_pricing_snapshots as snapshot
    on snapshot.intake_id = intake.id
  where p_access_token_hash ~ '^[0-9a-f]{64}$'
    and intake.access_token_hash = p_access_token_hash
    and intake.access_token_expires_at > clock_timestamp()
    and intake.access_token_revoked_at is null
    and intake.status in ('submitted', 'reviewed')
    and intake.submitted_at is not null
  limit 1
$$;

comment on function public.inspect_customer_pricing_read_v1(text) is
  'Service-role-only capability projection for customer pricing DTO mapping. It returns no snapshot JSON, config metadata, evidence, rules, reasons, package advice, IDs or privileged metadata.';

revoke all
on function public.inspect_customer_pricing_read_v1(text)
from public, anon, authenticated;

grant execute
on function public.inspect_customer_pricing_read_v1(text)
to service_role;

create function public.inspect_admin_pricing_read_v1(p_admin_access_token_hash text)
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
  budget_evaluation jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    intake.status::text,
    snapshot.id is not null,
    snapshot.snapshot_contract_version,
    snapshot.created_at,
    snapshot.config_version,
    snapshot.config_hash,
    snapshot.normalized_evidence,
    snapshot.calculation,
    snapshot.package_advice,
    snapshot.budget_evaluation
  from public.quote_request_intakes as intake
  left join public.quote_request_pricing_snapshots as snapshot
    on snapshot.intake_id = intake.id
  where p_admin_access_token_hash ~ '^[0-9a-f]{64}$'
    and intake.admin_access_token_hash = p_admin_access_token_hash
    and intake.admin_access_token_expires_at > clock_timestamp()
    and intake.admin_access_token_revoked_at is null
    and intake.status = 'submitted'
    and intake.submitted_at is not null
  limit 1
$$;

comment on function public.inspect_admin_pricing_read_v1(text) is
  'Service-role-only capability projection for explicit AdminPricingDTO mapping. It returns selected historical sections without IDs, capabilities, secrets or a complete snapshot wrapper.';

revoke all
on function public.inspect_admin_pricing_read_v1(text)
from public, anon, authenticated;

grant execute
on function public.inspect_admin_pricing_read_v1(text)
to service_role;