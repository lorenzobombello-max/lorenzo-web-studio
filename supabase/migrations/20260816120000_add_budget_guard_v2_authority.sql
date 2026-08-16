alter table public.quote_requests
  drop constraint quote_requests_budget_category_v2_coherent;

alter table public.quote_requests
  add constraint quote_requests_budget_category_v2_coherent
  check (
    (budget_category_scheme is null and budget_category_code is null)
    or (
      budget_category_scheme = 'budget_guard_v1'
      and (
        (budget_category_code = 'below_1800' and budget = 'Minder dan EUR 1.800')
        or (budget_category_code = '1800_to_below_3200' and budget = 'EUR 1.800 tot minder dan EUR 3.200')
        or (budget_category_code = '3200_to_6000_inclusive' and budget = 'EUR 3.200 t/m EUR 6.000')
        or (budget_category_code = 'above_6000' and budget = 'Meer dan EUR 6.000')
      )
    )
    or (
      budget_category_scheme = 'budget_guard_v2'
      and (
        (budget_category_code = 'below_1800' and budget = 'Minder dan EUR 1.800')
        or (budget_category_code = '1800_to_below_3500' and budget = 'EUR 1.800 tot minder dan EUR 3.500')
        or (budget_category_code = '3500_to_6000_inclusive' and budget = 'EUR 3.500 t/m EUR 6.000')
        or (budget_category_code = 'above_6000' and budget = 'Meer dan EUR 6.000')
      )
    )
  );

alter table public.quote_request_intakes
  drop constraint quote_request_intakes_budget_category_v2_coherent,
  drop constraint quote_request_intakes_budget_update_category_valid;

alter table public.quote_request_intakes
  add constraint quote_request_intakes_budget_category_v2_coherent
  check (
    (budget_update_category_scheme is null and budget_update_category_code is null)
    or (
      budget_update_category_scheme = 'budget_guard_v1'
      and (
        (budget_update_category_code = 'below_1800' and budget_update_category = 'Minder dan EUR 1.800')
        or (budget_update_category_code = '1800_to_below_3200' and budget_update_category = 'EUR 1.800 tot minder dan EUR 3.200')
        or (budget_update_category_code = '3200_to_6000_inclusive' and budget_update_category = 'EUR 3.200 t/m EUR 6.000')
        or (budget_update_category_code = 'above_6000' and budget_update_category = 'Meer dan EUR 6.000')
      )
    )
    or (
      budget_update_category_scheme = 'budget_guard_v2'
      and (
        (budget_update_category_code = 'below_1800' and budget_update_category = 'Minder dan EUR 1.800')
        or (budget_update_category_code = '1800_to_below_3500' and budget_update_category = 'EUR 1.800 tot minder dan EUR 3.500')
        or (budget_update_category_code = '3500_to_6000_inclusive' and budget_update_category = 'EUR 3.500 t/m EUR 6.000')
        or (budget_update_category_code = 'above_6000' and budget_update_category = 'Meer dan EUR 6.000')
      )
    )
  ),
  add constraint quote_request_intakes_budget_update_category_valid
  check (
    budget_update_category is null
    or budget_update_category in (
      'Tot EUR 1.500', 'EUR 1.500 - EUR 3.000', 'EUR 3.000 - EUR 6.000',
      'Meer dan EUR 6.000', 'Minder dan EUR 1.800',
      'EUR 1.800 tot minder dan EUR 3.200', 'EUR 3.200 t/m EUR 6.000',
      'EUR 1.800 tot minder dan EUR 3.500', 'EUR 3.500 t/m EUR 6.000'
    )
  );

create or replace function public.is_valid_pricing_budget_evaluation_v2(p_value jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_value) = 'object'
    and p_value ?& array[
      'contractVersion', 'evidenceProvenance', 'categoryScheme', 'categoryCode',
      'originalLabel', 'status', 'outsideBudgetWishes'
    ]
    and (select count(*) = 7 from jsonb_object_keys(p_value))
    and p_value->'contractVersion' = '2'::jsonb
    and p_value->>'evidenceProvenance' in (
      'budget_guard_v1', 'budget_guard_v2', 'legacy_label', 'missing', 'ambiguous'
    )
    and p_value->>'status' in (
      'below_starter_starting_price',
      'known_minimum_exceeds_category_upper_bound',
      'possibly_compatible_with_category',
      'unbounded_category_indeterminate',
      'legacy_category_not_safely_comparable',
      'manual_review_required'
    )
    and jsonb_typeof(p_value->'outsideBudgetWishes') in ('boolean', 'null')
    and (
      (
        p_value->>'evidenceProvenance' = 'budget_guard_v1'
        and p_value->>'categoryScheme' = 'budget_guard_v1'
        and (
          (p_value->>'categoryCode' = 'below_1800' and p_value->>'originalLabel' = 'Minder dan EUR 1.800')
          or (p_value->>'categoryCode' = '1800_to_below_3200' and p_value->>'originalLabel' = 'EUR 1.800 tot minder dan EUR 3.200')
          or (p_value->>'categoryCode' = '3200_to_6000_inclusive' and p_value->>'originalLabel' = 'EUR 3.200 t/m EUR 6.000')
          or (p_value->>'categoryCode' = 'above_6000' and p_value->>'originalLabel' = 'Meer dan EUR 6.000')
        )
      )
      or (
        p_value->>'evidenceProvenance' = 'budget_guard_v2'
        and p_value->>'categoryScheme' = 'budget_guard_v2'
        and (
          (p_value->>'categoryCode' = 'below_1800' and p_value->>'originalLabel' = 'Minder dan EUR 1.800')
          or (p_value->>'categoryCode' = '1800_to_below_3500' and p_value->>'originalLabel' = 'EUR 1.800 tot minder dan EUR 3.500')
          or (p_value->>'categoryCode' = '3500_to_6000_inclusive' and p_value->>'originalLabel' = 'EUR 3.500 t/m EUR 6.000')
          or (p_value->>'categoryCode' = 'above_6000' and p_value->>'originalLabel' = 'Meer dan EUR 6.000')
        )
      )
      or (
        p_value->>'evidenceProvenance' in ('legacy_label', 'ambiguous')
        and p_value->'categoryScheme' = 'null'::jsonb
        and p_value->'categoryCode' = 'null'::jsonb
        and jsonb_typeof(p_value->'originalLabel') = 'string'
        and p_value->>'status' in ('legacy_category_not_safely_comparable', 'manual_review_required')
        and p_value->'outsideBudgetWishes' = 'null'::jsonb
      )
      or (
        p_value->>'evidenceProvenance' = 'missing'
        and p_value->'categoryScheme' = 'null'::jsonb
        and p_value->'categoryCode' = 'null'::jsonb
        and p_value->'originalLabel' = 'null'::jsonb
        and p_value->>'status' = 'manual_review_required'
        and p_value->'outsideBudgetWishes' = 'null'::jsonb
      )
    )
$$;

create function public.guard_pricing_snapshot_budget_evidence()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_label text;
  v_scheme text;
  v_code text;
begin
  if new.budget_evaluation->>'evidenceProvenance' is distinct from 'budget_guard_v2' then
    return new;
  end if;

  select coalesce(intake.budget_update_category, request.budget),
         case when intake.budget_update_category is null then request.budget_category_scheme else intake.budget_update_category_scheme end,
         case when intake.budget_update_category is null then request.budget_category_code else intake.budget_update_category_code end
  into v_label, v_scheme, v_code
  from public.quote_request_intakes as intake
  join public.quote_requests as request on request.id = intake.quote_request_id
  where intake.id = new.intake_id;

  if new.budget_evaluation->>'originalLabel' is distinct from v_label then
    raise exception using errcode = '22023', message = 'PRICING_SNAPSHOT_BUDGET_MISMATCH';
  end if;

  if new.budget_evaluation->>'categoryScheme' is distinct from v_scheme
     or new.budget_evaluation->>'categoryCode' is distinct from v_code then
    raise exception using errcode = '22023', message = 'PRICING_SNAPSHOT_BUDGET_MISMATCH';
  end if;

  return new;
end;
$$;

create trigger trg_pricing_snapshot_budget_evidence
before insert on public.quote_request_pricing_snapshots
for each row execute function public.guard_pricing_snapshot_budget_evidence();

revoke all on function public.guard_pricing_snapshot_budget_evidence() from public, anon, authenticated, service_role;
