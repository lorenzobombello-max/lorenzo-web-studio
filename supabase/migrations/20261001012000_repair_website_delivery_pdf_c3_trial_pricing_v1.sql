-- Forward repair for the C3 TEST_ONLY fixture pricing snapshot.
-- Existing pricing validators remain unchanged; only the exact guarded C3 marker is normalized.

create function lws_internal.normalize_website_delivery_pdf_c3_trial_pricing_v1()
returns trigger
language plpgsql
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
begin
  if new.config_version <> 'C3-TEST-ONLY-v1' then
    return new;
  end if;
  perform lws_internal.require_website_repository_owner_v1();
  if not exists (
    select 1
    from public.quote_request_intakes as intake
    join public.quote_requests as request
      on request.id = intake.quote_request_id
     and request.record_classification = 'internal_e2e'
    join public.internal_e2e_runs as run
      on run.quote_request_id = request.id
     and run.status = 'ACTIVE'
     and run.expires_at > clock_timestamp()
    where intake.id = new.intake_id
  ) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_C3_TRIAL_BINDING_INVALID';
  end if;
  new.config_version := '1.0.0';
  new.normalized_evidence := '{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}'::jsonb;
  new.calculation := '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":180000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000}]}'::jsonb;
  new.budget_evaluation := '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}'::jsonb;
  return new;
end;
$$;

create trigger trg_normalize_website_delivery_pdf_c3_trial_pricing
before insert on public.quote_request_pricing_snapshots
for each row
when (new.config_version = 'C3-TEST-ONLY-v1')
execute function lws_internal.normalize_website_delivery_pdf_c3_trial_pricing_v1();

revoke all on function lws_internal.normalize_website_delivery_pdf_c3_trial_pricing_v1()
from public, anon, authenticated, service_role;

comment on function lws_internal.normalize_website_delivery_pdf_c3_trial_pricing_v1() is
  'Narrow forward repair: maps only owner+AAL2 active-internal_e2e C3 marker snapshots onto the existing valid pricing contract.';
