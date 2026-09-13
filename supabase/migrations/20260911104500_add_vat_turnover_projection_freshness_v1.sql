create or replace function public.record_quotation_vat_turnover_snapshot_v1(
  p_measurement_watermark date,
  p_governed_turnover_minor bigint,
  p_source_reference text,
  p_source_sha256 text,
  p_predecessor_snapshot_id uuid,
  p_recorded_by text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $$
declare
  v_authority public.quotation_vat_decision_authorities%rowtype;
  v_authority_count integer;
  v_expected_predecessor_id uuid;
  v_id uuid;
begin
  if p_measurement_watermark is null
     or p_governed_turnover_minor is null
     or p_governed_turnover_minor < 0
     or nullif(btrim(p_source_reference), '') is null
     or p_source_sha256 !~ '^[0-9a-f]{64}$'
     or p_recorded_by <> 'VAT_TURNOVER_SNAPSHOT_ORCHESTRATOR_V1' then
    raise exception using
      errcode = '22023', message = 'QUOTATION_VAT_TURNOVER_SNAPSHOT_INVALID';
  end if;

  select count(*)::integer into v_authority_count
  from public.quotation_vat_decision_authorities
  where authority_family = 'LWS_OUTGOING_VAT'
    and status = 'APPROVED'
    and effective_from <= p_measurement_watermark
    and (effective_until is null or effective_until >= p_measurement_watermark);
  if v_authority_count <> 1 then
    raise exception using
      errcode = 'P0001', message = 'QUOTATION_VAT_DECISION_NOT_APPROVED';
  end if;

  select * into strict v_authority
  from public.quotation_vat_decision_authorities
  where authority_family = 'LWS_OUTGOING_VAT'
    and status = 'APPROVED'
    and effective_from <= p_measurement_watermark
    and (effective_until is null or effective_until >= p_measurement_watermark);
  if extract(year from p_measurement_watermark)::integer
       <> v_authority.threshold_year
     or p_governed_turnover_minor > v_authority.applicable_threshold_minor then
    raise exception using
      errcode = 'P0001', message = 'VAT_FINANCE_THRESHOLD_YEAR_INVALID';
  end if;

  select snapshot.turnover_snapshot_id
  into v_expected_predecessor_id
  from public.quotation_vat_turnover_snapshots as snapshot
  join public.quotation_vat_turnover_snapshot_projection_bindings as binding
    on binding.turnover_snapshot_id = snapshot.turnover_snapshot_id
  where snapshot.vat_decision_authority_id = v_authority.vat_decision_authority_id
    and snapshot.threshold_year = v_authority.threshold_year
    and snapshot.measurement_watermark < p_measurement_watermark
  order by snapshot.measurement_watermark desc, snapshot.recorded_at desc,
    snapshot.turnover_snapshot_id desc
  limit 1;
  if p_predecessor_snapshot_id is distinct from v_expected_predecessor_id then
    raise exception using
      errcode = 'P0001', message = 'VAT_TURNOVER_PREDECESSOR_INVALID';
  end if;

  if exists (
    select 1
    from public.quotation_vat_turnover_snapshots
    where vat_decision_authority_id = v_authority.vat_decision_authority_id
      and threshold_year = v_authority.threshold_year
      and measurement_watermark = p_measurement_watermark
  ) then
    raise exception using
      errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
  end if;

  insert into public.quotation_vat_turnover_snapshots (
    vat_decision_authority_id, threshold_year, measurement_watermark,
    governed_turnover_minor, currency, state, source_reference, source_sha256,
    predecessor_snapshot_id, recorded_by, recorded_at
  ) values (
    v_authority.vat_decision_authority_id, v_authority.threshold_year,
    p_measurement_watermark, p_governed_turnover_minor, 'EUR',
    'BELOW_OR_AT_THRESHOLD', p_source_reference, p_source_sha256,
    p_predecessor_snapshot_id, p_recorded_by, clock_timestamp()
  ) returning turnover_snapshot_id into v_id;

  return v_id;
exception
  when unique_violation then
    raise exception using
      errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
end;
$$;

create function public.evaluate_quotation_vat_turnover_freshness_v1(
  p_vat_decision_authority_id uuid,
  p_resolution_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_authority public.quotation_vat_decision_authorities%rowtype;
  v_snapshot public.quotation_vat_turnover_snapshots%rowtype;
  v_exact_raw_count integer;
  v_exact_accepted_count integer;
  v_result jsonb;
  v_evaluated_at timestamptz := clock_timestamp();
begin
  if p_vat_decision_authority_id is null or p_resolution_date is null then
    raise exception using
      errcode = '22023', message = 'VAT_TURNOVER_FRESHNESS_REQUEST_INVALID';
  end if;

  select * into v_authority
  from public.quotation_vat_decision_authorities
  where vat_decision_authority_id = p_vat_decision_authority_id
    and authority_family = 'LWS_OUTGOING_VAT'
    and status = 'APPROVED'
    and effective_from <= p_resolution_date
    and (effective_until is null or effective_until >= p_resolution_date);
  if not found
     or extract(year from p_resolution_date)::integer
       <> v_authority.threshold_year then
    raise exception using
      errcode = 'P0001', message = 'VAT_TURNOVER_AUTHORITY_INVALID';
  end if;

  select count(*)::integer into v_exact_raw_count
  from public.quotation_vat_turnover_snapshots
  where vat_decision_authority_id = p_vat_decision_authority_id
    and threshold_year = v_authority.threshold_year
    and measurement_watermark = p_resolution_date;

  select count(*)::integer into v_exact_accepted_count
  from public.quotation_vat_turnover_snapshots snapshot
  join public.quotation_vat_turnover_snapshot_projection_bindings binding
    on binding.turnover_snapshot_id = snapshot.turnover_snapshot_id
   and rtrim(binding.source_sha256) = rtrim(snapshot.source_sha256)
   and binding.category_authority_manifest_sha256 = encode(
     extensions.digest(convert_to(
       binding.category_authority_manifest::text, 'UTF8'
     ), 'sha256'), 'hex'
   )
  join public.vat_finance_projection_adapters adapter
    on adapter.adapter_id = binding.adapter_id
   and adapter.adapter_version = binding.adapter_version
   and binding.projection_version = adapter.adapter_version
   and rtrim(binding.source_schema_sha256)
     = rtrim(adapter.source_schema_sha256)
   and adapter.status = 'APPROVED'
   and adapter.effective_from <= snapshot.measurement_watermark
   and (adapter.effective_until is null
     or adapter.effective_until >= snapshot.measurement_watermark)
  where snapshot.vat_decision_authority_id = p_vat_decision_authority_id
    and snapshot.threshold_year = v_authority.threshold_year
    and snapshot.measurement_watermark = p_resolution_date
    and snapshot.currency = 'EUR'
    and snapshot.state = 'BELOW_OR_AT_THRESHOLD'
    and snapshot.governed_turnover_minor <= v_authority.applicable_threshold_minor;

  if v_exact_accepted_count = 1 and v_exact_raw_count = 1 then
    select snapshot.* into strict v_snapshot
    from public.quotation_vat_turnover_snapshots snapshot
    join public.quotation_vat_turnover_snapshot_projection_bindings binding
      on binding.turnover_snapshot_id = snapshot.turnover_snapshot_id
     and rtrim(binding.source_sha256) = rtrim(snapshot.source_sha256)
     and binding.category_authority_manifest_sha256 = encode(
       extensions.digest(convert_to(
         binding.category_authority_manifest::text, 'UTF8'
       ), 'sha256'), 'hex'
     )
    join public.vat_finance_projection_adapters adapter
      on adapter.adapter_id = binding.adapter_id
     and adapter.adapter_version = binding.adapter_version
     and binding.projection_version = adapter.adapter_version
     and rtrim(binding.source_schema_sha256)
       = rtrim(adapter.source_schema_sha256)
     and adapter.status = 'APPROVED'
     and adapter.effective_from <= snapshot.measurement_watermark
     and (adapter.effective_until is null
       or adapter.effective_until >= snapshot.measurement_watermark)
    where snapshot.vat_decision_authority_id = p_vat_decision_authority_id
      and snapshot.threshold_year = v_authority.threshold_year
      and snapshot.measurement_watermark = p_resolution_date
      and snapshot.currency = 'EUR'
      and snapshot.state = 'BELOW_OR_AT_THRESHOLD'
      and snapshot.governed_turnover_minor
        <= v_authority.applicable_threshold_minor;
    v_result := jsonb_build_object(
      'turnover_status', 'READY',
      'turnover_snapshot_id', v_snapshot.turnover_snapshot_id,
      'measurement_date', v_snapshot.measurement_watermark,
      'source_watermark', v_snapshot.measurement_watermark,
      'blocking_reason', null,
      'evaluated_at', v_evaluated_at
    );
    return v_result;
  end if;

  if v_exact_raw_count > 0 then
    return jsonb_build_object(
      'turnover_status', 'MISSING',
      'turnover_snapshot_id', null,
      'measurement_date', p_resolution_date,
      'source_watermark', null,
      'blocking_reason', 'VAT_TURNOVER_SOURCE_INVALID',
      'evaluated_at', v_evaluated_at
    );
  end if;

  select snapshot.* into v_snapshot
  from public.quotation_vat_turnover_snapshots snapshot
  join public.quotation_vat_turnover_snapshot_projection_bindings binding
    on binding.turnover_snapshot_id = snapshot.turnover_snapshot_id
   and rtrim(binding.source_sha256) = rtrim(snapshot.source_sha256)
   and binding.category_authority_manifest_sha256 = encode(
     extensions.digest(convert_to(
       binding.category_authority_manifest::text, 'UTF8'
     ), 'sha256'), 'hex'
   )
  join public.vat_finance_projection_adapters adapter
    on adapter.adapter_id = binding.adapter_id
   and adapter.adapter_version = binding.adapter_version
   and binding.projection_version = adapter.adapter_version
   and rtrim(binding.source_schema_sha256)
     = rtrim(adapter.source_schema_sha256)
   and adapter.status = 'APPROVED'
   and adapter.effective_from <= snapshot.measurement_watermark
   and (adapter.effective_until is null
     or adapter.effective_until >= snapshot.measurement_watermark)
  where snapshot.vat_decision_authority_id = p_vat_decision_authority_id
    and snapshot.threshold_year = v_authority.threshold_year
    and snapshot.measurement_watermark < p_resolution_date
    and snapshot.currency = 'EUR'
    and snapshot.state = 'BELOW_OR_AT_THRESHOLD'
    and snapshot.governed_turnover_minor <= v_authority.applicable_threshold_minor
  order by snapshot.measurement_watermark desc, snapshot.recorded_at desc,
    snapshot.turnover_snapshot_id desc
  limit 1;

  if found then
    return jsonb_build_object(
      'turnover_status', 'STALE',
      'turnover_snapshot_id', v_snapshot.turnover_snapshot_id,
      'measurement_date', v_snapshot.measurement_watermark,
      'source_watermark', v_snapshot.measurement_watermark,
      'blocking_reason', 'VAT_TURNOVER_STALE',
      'evaluated_at', v_evaluated_at
    );
  end if;

  return jsonb_build_object(
    'turnover_status', 'MISSING',
    'turnover_snapshot_id', null,
    'measurement_date', p_resolution_date,
    'source_watermark', null,
    'blocking_reason', 'VAT_TURNOVER_EVIDENCE_REQUIRED',
    'evaluated_at', v_evaluated_at
  );
end;
$$;

revoke all on function public.record_quotation_vat_turnover_snapshot_v1(
  date, bigint, text, text, uuid, text
) from public, anon, authenticated, service_role;
revoke all on function public.evaluate_quotation_vat_turnover_freshness_v1(uuid, date)
from public, anon, authenticated, service_role;
grant execute on function public.evaluate_quotation_vat_turnover_freshness_v1(uuid, date)
to authenticated, service_role;

comment on function public.evaluate_quotation_vat_turnover_freshness_v1(uuid, date) is
  'Read-only browser-safe exact-date VAT turnover freshness projection. It never creates, corrects, or supersedes evidence.';
