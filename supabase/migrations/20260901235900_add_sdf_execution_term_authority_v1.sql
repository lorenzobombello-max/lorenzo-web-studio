do $$
declare
  v_definition text;
  v_rewritten text;
begin
  v_definition := pg_get_functiondef(
    'public.create_sdf_quotation_business_draft_v1(uuid,uuid,uuid)'::regprocedure
  );
  v_rewritten := replace(
    v_definition,
    'create_sdf_quotation_business_draft_v1',
    'create_sdf_quotation_business_draft_v2'
  );
  v_rewritten := regexp_replace(
    v_rewritten,
    'p_idempotency_key uuid\s*\)',
    E'p_idempotency_key uuid,\n    p_indicative_timing integer\n)',
    ''
  );
  v_rewritten := replace(
    v_rewritten,
    'or p_idempotency_key is null then',
    E'or p_idempotency_key is null\n     or p_indicative_timing is null or p_indicative_timing <= 0 then'
  );
  v_rewritten := replace(
    v_rewritten,
    '''decision_sha256'', v_current_decision_sha256',
    '''decision_sha256'', v_current_decision_sha256,
    ''indicative_timing'', p_indicative_timing'
  );
  v_rewritten := replace(
    v_rewritten,
    '''indicative_timing'', null',
    '''indicative_timing'', to_jsonb(p_indicative_timing)'
  );
  if v_rewritten = v_definition
     or strpos(v_rewritten, 'p_indicative_timing integer') = 0
     or strpos(v_rewritten, '''indicative_timing'', p_indicative_timing') = 0
     or strpos(v_rewritten, '''indicative_timing'', to_jsonb(p_indicative_timing)') = 0 then
    raise exception using errcode = '55000', message = 'SDF_EXECUTION_TERM_DRAFT_CALLSITE_DRIFT';
  end if;
  execute v_rewritten;
end;
$$;

create or replace function public.is_valid_sdf_quotation_generation_payload_v1(p_payload jsonb)
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
    and public.is_jsonb_nonnegative_integer(p_payload->'project'->'indicative_timing')
    and (p_payload#>>'{project,indicative_timing}')::bigint > 0
    and public.is_valid_sdf_quotation_scope_snapshot_v1(p_payload->'sdf_scope')
    and p_payload->'sdf_scope'->'implementation_amount_minor'
      = p_payload->'totals'->'one_time_subtotal_minor'
    and p_payload->'sdf_scope'->'recurring_amount_minor'
      = p_payload->'totals'->'recurring_subtotal_minor'
    and p_payload->'sdf_scope'->'payment_milestones'
      = p_payload->'payment_schedule'->'milestones'
$$;

revoke all on function public.create_sdf_quotation_business_draft_v1(uuid, uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.create_sdf_quotation_business_draft_v2(uuid, uuid, uuid, integer)
from public, anon, authenticated, service_role;
grant execute on function public.create_sdf_quotation_business_draft_v2(uuid, uuid, uuid, integer)
to authenticated;

comment on function public.create_sdf_quotation_business_draft_v2(uuid, uuid, uuid, integer) is
  'Owner-only SDF business-draft bridge. Requires a project-specific positive whole-week indicative execution term and binds it into the immutable approval payload and request fingerprint; no package default or frontend authority is used.';