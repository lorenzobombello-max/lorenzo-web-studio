alter function public.is_valid_phase_d_intake_evidence(
  public.quote_request_intakes
) rename to is_valid_phase_d_intake_evidence_v1;

create function public.is_valid_phase_d_intake_evidence(
  p_intake public.quote_request_intakes
)
returns boolean
language plpgsql
stable
set search_path = public
as $$
declare
  v_intake public.quote_request_intakes%rowtype;
  v_page_scope jsonb;
  v_shop_details jsonb;
begin
  v_intake := p_intake;
  v_page_scope := p_intake.page_scope_details;
  if v_page_scope is not null then
    if jsonb_typeof(v_page_scope) <> 'object'
       or (
         v_page_scope ? 'jobs'
         and (
           jsonb_typeof(v_page_scope->'jobs') <> 'string'
           or v_page_scope->>'jobs' not in ('normal', 'complex', 'unknown', 'dynamic')
         )
       )
       or (
         v_page_scope ? 'jobs_application'
         and (
           not (v_page_scope ? 'jobs')
           or jsonb_typeof(v_page_scope->'jobs_application') <> 'string'
           or v_page_scope->>'jobs_application' not in (
             'none', 'basic', 'upload', 'complex', 'ats'
           )
         )
       ) then
      return false;
    end if;
    v_page_scope := v_page_scope - 'jobs_application';
    if v_page_scope->>'jobs' = 'dynamic' then
      v_page_scope := jsonb_set(v_page_scope, '{jobs}', '"complex"'::jsonb);
    end if;
    v_intake.page_scope_details := v_page_scope;
  end if;

  v_shop_details := p_intake.shop_details;
  if v_shop_details is not null then
    if jsonb_typeof(v_shop_details) <> 'object'
       or (
         v_shop_details ? 'pickup_scope'
         and (
           jsonb_typeof(v_shop_details->'pickup_scope') <> 'string'
           or v_shop_details->>'pickup_scope' not in (
             'none', 'simple', 'scheduled', 'complex'
           )
           or not (v_shop_details ? 'pickup')
           or (v_shop_details->>'pickup')::boolean is distinct from
             (v_shop_details->>'pickup_scope' <> 'none')
         )
       ) then
      return false;
    end if;
    v_intake.shop_details := v_shop_details - 'pickup_scope';
  end if;

  return public.is_valid_phase_d_intake_evidence_v1(v_intake);
exception when others then
  return false;
end;
$$;

revoke all
on function public.is_valid_phase_d_intake_evidence(public.quote_request_intakes)
from public, anon, authenticated;

grant execute
on function public.is_valid_phase_d_intake_evidence(public.quote_request_intakes)
to service_role;

comment on function public.is_valid_phase_d_intake_evidence(
  public.quote_request_intakes
) is
  'Validates Phase-D intake evidence with pickup and vacancy scope extensions while preserving the prior closed contract.';

do $$
declare
  v_signature constant text :=
    'public.is_strict_pricing_snapshot_v3(smallint,text,text,jsonb,jsonb,jsonb,jsonb,jsonb)';
  v_definition text;
  v_updated text;
begin
  select pg_get_functiondef(v_signature::regprocedure)
  into v_definition;

  v_updated := replace(
    v_definition,
    'p_config_version not in (''2.0.0'', ''2026-08-12-v1'')',
    'p_config_version not in (''2.0.0'', ''2026-08-12-v1'', ''2026-08-13-v2'')'
  );
  if v_updated = v_definition then
    raise exception 'STRICT_V3_VERSION_ALLOWLIST_FRAGMENT_NOT_FOUND';
  end if;
  v_definition := v_updated;

  v_updated := replace(
    v_definition,
    'p_config_version <> ''2026-08-12-v1''',
    'p_config_version not in (''2026-08-12-v1'', ''2026-08-13-v2'')'
  );
  if v_updated = v_definition then
    raise exception 'STRICT_V3_PROFESSIONAL_VERSION_FRAGMENT_NOT_FOUND';
  end if;
  v_definition := v_updated;

  v_updated := replace(
    v_definition,
    'p_config_version = ''2026-08-12-v1''',
    'p_config_version in (''2026-08-12-v1'', ''2026-08-13-v2'')'
  );
  if v_updated = v_definition then
    raise exception 'STRICT_V3_EXTRA_PAGE_VERSION_FRAGMENT_NOT_FOUND';
  end if;

  execute v_updated;
end;
$$;
