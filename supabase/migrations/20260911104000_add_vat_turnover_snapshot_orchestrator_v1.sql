create function lws_internal.validate_vat_finance_projection_v1(
  p_projection jsonb
)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public
as $$
declare
  v_covered_from date;
  v_covered_through date;
  v_generated_at timestamptz;
  v_pre_transaction numeric;
  v_candidate numeric;
  v_governed numeric;
  v_included_sum numeric := 0;
  v_item jsonb;
  v_candidate_reference text;
  v_included_count integer;
  v_distinct_included_count integer;
  v_excluded_count integer;
  v_distinct_excluded_count integer;
  v_category_count integer;
  v_distinct_category_count integer;
  v_recomputed_sha256 text;
begin
  if p_projection is null
     or jsonb_typeof(p_projection) <> 'object'
     or not public.jsonb_has_exact_keys(p_projection, array[
       'source_projection_id', 'projection_version', 'covered_from',
       'covered_through', 'currency', 'included_transaction_references',
       'excluded_transactions', 'pre_transaction_turnover_minor',
       'candidate_transaction_reference', 'candidate_transaction_minor',
       'governed_turnover_minor',
       'category_classification_authority_references',
       'ledger_source_watermark', 'generated_at', 'source_sha256'
     ])
     or nullif(btrim(p_projection->>'source_projection_id'), '') is null
     or nullif(btrim(p_projection->>'projection_version'), '') is null
     or p_projection->>'currency' <> 'EUR'
     or jsonb_typeof(p_projection->'included_transaction_references') <> 'array'
     or jsonb_typeof(p_projection->'excluded_transactions') <> 'array'
     or jsonb_typeof(
       p_projection->'category_classification_authority_references'
     ) <> 'array'
     or coalesce(p_projection->>'covered_from', '') !~ '^\d{4}-\d{2}-\d{2}$'
     or coalesce(p_projection->>'covered_through', '') !~ '^\d{4}-\d{2}-\d{2}$'
     or coalesce(p_projection->>'ledger_source_watermark', '')
       !~ '^\d{4}-\d{2}-\d{2}$'
     or coalesce(p_projection->>'generated_at', '') = ''
     or coalesce(p_projection->>'pre_transaction_turnover_minor', '')
       !~ '^(0|[1-9][0-9]*)$'
     or coalesce(p_projection->>'governed_turnover_minor', '')
       !~ '^(0|[1-9][0-9]*)$' then
    raise exception using
      errcode = 'P0001', message = 'VAT_FINANCE_PROJECTION_INVALID';
  end if;

  v_covered_from := (p_projection->>'covered_from')::date;
  v_covered_through := (p_projection->>'covered_through')::date;
  v_generated_at := (p_projection->>'generated_at')::timestamptz;
  v_pre_transaction := (p_projection->>'pre_transaction_turnover_minor')::numeric;
  v_governed := (p_projection->>'governed_turnover_minor')::numeric;
  v_candidate_reference := nullif(
    btrim(p_projection->>'candidate_transaction_reference'), ''
  );

  if (p_projection->'candidate_transaction_reference' = 'null'::jsonb)
     is distinct from (p_projection->'candidate_transaction_minor' = 'null'::jsonb)
     or (
       p_projection->'candidate_transaction_minor' <> 'null'::jsonb
       and coalesce(p_projection->>'candidate_transaction_minor', '')
         !~ '^(0|[1-9][0-9]*)$'
     ) then
    raise exception using
      errcode = 'P0001', message = 'VAT_FINANCE_PROJECTION_INVALID';
  end if;
  if p_projection->'candidate_transaction_minor' = 'null'::jsonb then
    v_candidate := 0;
    if v_candidate_reference is not null then
      raise exception using
        errcode = 'P0001', message = 'VAT_FINANCE_PROJECTION_INVALID';
    end if;
  else
    v_candidate := (p_projection->>'candidate_transaction_minor')::numeric;
    if v_candidate_reference is null then
      raise exception using
        errcode = 'P0001', message = 'VAT_FINANCE_PROJECTION_INVALID';
    end if;
  end if;

  if v_covered_from <> make_date(extract(year from v_covered_through)::integer, 1, 1)
     or p_projection->>'ledger_source_watermark' <> p_projection->>'covered_through'
     or v_generated_at > transaction_timestamp()
     or v_pre_transaction > 9223372036854775807
     or v_candidate > 9223372036854775807
     or v_governed > 9223372036854775807
     or v_pre_transaction + v_candidate <> v_governed then
    raise exception using
      errcode = 'P0001', message = 'VAT_FINANCE_PROJECTION_INVALID';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(p_projection->'included_transaction_references')
  loop
    if jsonb_typeof(v_item) <> 'object'
       or not public.jsonb_has_exact_keys(v_item, array[
         'transaction_reference', 'category_code', 'governed_minor'
       ])
       or nullif(btrim(v_item->>'transaction_reference'), '') is null
       or nullif(btrim(v_item->>'category_code'), '') is null
       or coalesce(v_item->>'governed_minor', '') !~ '^(0|[1-9][0-9]*)$'
       or (v_item->>'governed_minor')::numeric > 9223372036854775807 then
      raise exception using
        errcode = 'P0001', message = 'VAT_FINANCE_PROJECTION_INVALID';
    end if;
    v_included_sum := v_included_sum + (v_item->>'governed_minor')::numeric;
  end loop;

  select count(*), count(distinct value->>'transaction_reference')
  into v_included_count, v_distinct_included_count
  from jsonb_array_elements(p_projection->'included_transaction_references');
  if v_included_count <> v_distinct_included_count
     or v_included_sum <> v_governed then
    raise exception using
      errcode = 'P0001', message = 'VAT_FINANCE_PROJECTION_INVALID';
  end if;

  if v_candidate_reference is not null and not exists (
    select 1
    from jsonb_array_elements(
      p_projection->'included_transaction_references'
    ) as included(value)
    where included.value->>'transaction_reference' = v_candidate_reference
      and (included.value->>'governed_minor')::numeric = v_candidate
  ) then
    raise exception using
      errcode = 'P0001', message = 'VAT_FINANCE_PROJECTION_INVALID';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(p_projection->'excluded_transactions')
  loop
    if jsonb_typeof(v_item) <> 'object'
       or not public.jsonb_has_exact_keys(v_item, array[
         'transaction_reference', 'category_code', 'reason_code'
       ])
       or nullif(btrim(v_item->>'transaction_reference'), '') is null
       or nullif(btrim(v_item->>'category_code'), '') is null
       or nullif(btrim(v_item->>'reason_code'), '') is null then
      raise exception using
        errcode = 'P0001', message = 'VAT_FINANCE_PROJECTION_INVALID';
    end if;
  end loop;

  select count(*), count(distinct value->>'transaction_reference')
  into v_excluded_count, v_distinct_excluded_count
  from jsonb_array_elements(p_projection->'excluded_transactions');
  if v_excluded_count <> v_distinct_excluded_count
     or exists (
       select 1
       from jsonb_array_elements(
         p_projection->'included_transaction_references'
       ) as included(value)
       join jsonb_array_elements(
         p_projection->'excluded_transactions'
       ) as excluded(value)
         on excluded.value->>'transaction_reference'
          = included.value->>'transaction_reference'
     ) then
    raise exception using
      errcode = 'P0001', message = 'VAT_FINANCE_PROJECTION_INVALID';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(
      p_projection->'category_classification_authority_references'
    )
  loop
    if jsonb_typeof(v_item) <> 'object'
       or not public.jsonb_has_exact_keys(v_item, array[
         'category_code', 'authority_reference', 'authority_sha256', 'status'
       ])
       or nullif(btrim(v_item->>'category_code'), '') is null
       or nullif(btrim(v_item->>'authority_reference'), '') is null
       or coalesce(v_item->>'authority_sha256', '') !~ '^[0-9a-f]{64}$'
       or v_item->>'status' <> 'APPROVED' then
      raise exception using
        errcode = 'P0001', message = 'VAT_FINANCE_CATEGORY_AUTHORITY_REQUIRED';
    end if;
  end loop;

  select count(*), count(distinct value->>'category_code')
  into v_category_count, v_distinct_category_count
  from jsonb_array_elements(
    p_projection->'category_classification_authority_references'
  );
  if v_category_count <> v_distinct_category_count
     or exists (
       select 1
       from jsonb_array_elements(
         p_projection->'included_transaction_references'
       ) as included(value)
       where not exists (
         select 1
         from jsonb_array_elements(
           p_projection->'category_classification_authority_references'
         ) as authority(value)
         where authority.value->>'category_code'
           = included.value->>'category_code'
           and authority.value->>'status' = 'APPROVED'
       )
     ) then
    raise exception using
      errcode = 'P0001', message = 'VAT_FINANCE_CATEGORY_AUTHORITY_REQUIRED';
  end if;

  v_recomputed_sha256 := public.vat_finance_projection_sha256_v1(p_projection);
  if v_recomputed_sha256 <> p_projection->>'source_sha256' then
    raise exception using
      errcode = 'P0001', message = 'VAT_FINANCE_PROJECTION_HASH_MISMATCH';
  end if;

  return p_projection;
exception
  when invalid_text_representation
    or datetime_field_overflow
    or numeric_value_out_of_range then
    raise exception using
      errcode = 'P0001', message = 'VAT_FINANCE_PROJECTION_INVALID';
end;
$$;

create table public.quotation_vat_turnover_refresh_operations (
  operation_id uuid primary key default gen_random_uuid(),
  vat_decision_authority_id uuid not null
    references public.quotation_vat_decision_authorities(vat_decision_authority_id)
    on delete restrict,
  threshold_year integer not null,
  measurement_date date not null,
  adapter_id uuid not null
    references public.vat_finance_projection_adapters(adapter_id)
    on delete restrict,
  adapter_version text not null,
  source_projection_id text not null,
  source_sha256 char(64) not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  idempotency_key uuid not null unique,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  outcome text not null check (outcome in ('READY', 'REVIEW_REQUIRED')),
  turnover_snapshot_id uuid
    references public.quotation_vat_turnover_snapshots(turnover_snapshot_id)
    on delete restrict,
  result_payload jsonb not null check (jsonb_typeof(result_payload) = 'object'),
  process_identity text not null check (
    process_identity = 'VAT_TURNOVER_SNAPSHOT_ORCHESTRATOR'
  ),
  process_version text not null check (process_version = '1.0.0'),
  created_at timestamptz not null,
  constraint quotation_vat_turnover_refresh_outcome_valid check (
    (outcome = 'READY' and turnover_snapshot_id is not null)
    or (outcome = 'REVIEW_REQUIRED' and turnover_snapshot_id is null)
  )
);

create table public.quotation_vat_turnover_snapshot_projection_bindings (
  turnover_snapshot_id uuid primary key
    references public.quotation_vat_turnover_snapshots(turnover_snapshot_id)
    on delete restrict,
  adapter_id uuid not null
    references public.vat_finance_projection_adapters(adapter_id)
    on delete restrict,
  adapter_version text not null,
  source_projection_id text not null,
  projection_version text not null,
  source_sha256 char(64) not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  source_schema_sha256 char(64) not null
    check (source_schema_sha256 ~ '^[0-9a-f]{64}$'),
  category_authority_manifest jsonb not null
    check (jsonb_typeof(category_authority_manifest) = 'array'),
  category_authority_manifest_sha256 char(64) not null
    check (category_authority_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  bound_at timestamptz not null,
  unique (adapter_id, source_projection_id, source_sha256)
);

create function lws_internal.prevent_vat_turnover_refresh_operation_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using
    errcode = '55000', message = 'VAT_TURNOVER_REFRESH_OPERATION_IMMUTABLE';
end;
$$;

create function lws_internal.prevent_vat_turnover_projection_binding_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using
    errcode = '55000', message = 'VAT_TURNOVER_PROJECTION_BINDING_IMMUTABLE';
end;
$$;

create trigger trg_vat_turnover_refresh_operation_immutable
before update or delete on public.quotation_vat_turnover_refresh_operations
for each row execute function
  lws_internal.prevent_vat_turnover_refresh_operation_mutation_v1();

create trigger trg_vat_turnover_projection_binding_immutable
before update or delete
on public.quotation_vat_turnover_snapshot_projection_bindings
for each row execute function
  lws_internal.prevent_vat_turnover_projection_binding_mutation_v1();

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
      errcode = 'P0001', message = 'QUOTATION_VAT_TURNOVER_SNAPSHOT_CONFLICT';
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
      errcode = 'P0001', message = 'QUOTATION_VAT_TURNOVER_SNAPSHOT_CONFLICT';
end;
$$;

create function public.refresh_quotation_vat_turnover_snapshot_v1(
  p_measurement_date date,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, lws_internal, extensions
as $$
declare
  v_existing public.quotation_vat_turnover_refresh_operations%rowtype;
  v_authority public.quotation_vat_decision_authorities%rowtype;
  v_adapter public.vat_finance_projection_adapters%rowtype;
  v_authority_count integer;
  v_adapter_count integer;
  v_request_fingerprint text;
  v_projection jsonb;
  v_validated_projection jsonb;
  v_source_projection_id text;
  v_source_sha256 text;
  v_predecessor_snapshot_id uuid;
  v_turnover_snapshot_id uuid;
  v_recorded_at timestamptz;
  v_result jsonb;
  v_now timestamptz := clock_timestamp();
  v_category_manifest jsonb;
  v_category_manifest_sha256 text;
begin
  if p_measurement_date is null or p_idempotency_key is null then
    raise exception using
      errcode = '22023', message = 'VAT_TURNOVER_REFRESH_REQUEST_INVALID';
  end if;

  v_request_fingerprint := encode(extensions.digest(convert_to(
    jsonb_build_object(
      'measurement_date', p_measurement_date,
      'process_identity', 'VAT_TURNOVER_SNAPSHOT_ORCHESTRATOR',
      'process_version', '1.0.0'
    )::text, 'UTF8'
  ), 'sha256'), 'hex');
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key::text, 0)
  );
  select * into v_existing
  from public.quotation_vat_turnover_refresh_operations
  where idempotency_key = p_idempotency_key;
  if found then
    if rtrim(v_existing.request_fingerprint) <> v_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed', true);
  end if;

  select count(*)::integer into v_authority_count
  from public.quotation_vat_decision_authorities
  where authority_family = 'LWS_OUTGOING_VAT'
    and status = 'APPROVED'
    and effective_from <= p_measurement_date
    and (effective_until is null or effective_until >= p_measurement_date);
  if v_authority_count <> 1 then
    raise exception using
      errcode = 'P0001', message = 'QUOTATION_VAT_DECISION_NOT_APPROVED';
  end if;
  select * into strict v_authority
  from public.quotation_vat_decision_authorities
  where authority_family = 'LWS_OUTGOING_VAT'
    and status = 'APPROVED'
    and effective_from <= p_measurement_date
    and (effective_until is null or effective_until >= p_measurement_date);
  if extract(year from p_measurement_date)::integer <> v_authority.threshold_year then
    raise exception using
      errcode = 'P0001', message = 'VAT_FINANCE_THRESHOLD_YEAR_INVALID';
  end if;

  select count(*)::integer into v_adapter_count
  from public.vat_finance_projection_adapters
  where status = 'APPROVED'
    and effective_from <= p_measurement_date
    and (effective_until is null or effective_until >= p_measurement_date);
  if v_adapter_count <> 1 then
    raise exception using
      errcode = 'P0001', message = 'VAT_FINANCE_SOURCE_UNAVAILABLE';
  end if;
  select * into strict v_adapter
  from public.vat_finance_projection_adapters
  where status = 'APPROVED'
    and effective_from <= p_measurement_date
    and (effective_until is null or effective_until >= p_measurement_date);

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    v_authority.vat_decision_authority_id::text || ':' || p_measurement_date::text,
    0
  ));
  v_projection := public.get_finance_ledger_projection_v1(
    v_authority.threshold_year,
    v_authority.vat_decision_authority_id,
    p_measurement_date
  );
  v_source_projection_id := v_projection->>'source_projection_id';
  v_source_sha256 := v_projection->>'source_sha256';

  if exists (
    select 1
    from public.quotation_vat_turnover_snapshots as snapshot
    where snapshot.vat_decision_authority_id
        = v_authority.vat_decision_authority_id
      and snapshot.threshold_year = v_authority.threshold_year
      and snapshot.measurement_watermark < p_measurement_date
      and not exists (
        select 1
        from public.quotation_vat_turnover_snapshot_projection_bindings as binding
        where binding.turnover_snapshot_id = snapshot.turnover_snapshot_id
      )
  ) then
    raise exception using
      errcode = 'P0001', message = 'VAT_TURNOVER_PREDECESSOR_CHAIN_INVALID';
  end if;

  select snapshot.turnover_snapshot_id
  into v_predecessor_snapshot_id
  from public.quotation_vat_turnover_snapshots as snapshot
  join public.quotation_vat_turnover_snapshot_projection_bindings as binding
    on binding.turnover_snapshot_id = snapshot.turnover_snapshot_id
  where snapshot.vat_decision_authority_id = v_authority.vat_decision_authority_id
    and snapshot.threshold_year = v_authority.threshold_year
    and snapshot.measurement_watermark < p_measurement_date
  order by snapshot.measurement_watermark desc, snapshot.recorded_at desc,
    snapshot.turnover_snapshot_id desc
  limit 1;

  begin
    v_validated_projection :=
      lws_internal.validate_vat_finance_projection_v1(v_projection);
  exception
    when raise_exception then
      if sqlerrm <> 'VAT_FINANCE_CATEGORY_AUTHORITY_REQUIRED' then
        raise;
      end if;
      perform public.vat_finance_projection_sha256_v1(v_projection);
      v_result := jsonb_build_object(
        'measurement_date', p_measurement_date,
        'threshold_year', v_authority.threshold_year,
        'turnover_status', 'REVIEW_REQUIRED',
        'turnover_snapshot_id', null,
        'state', 'AUTHORITY_REVIEW_REQUIRED',
        'source_projection_id', v_source_projection_id,
        'source_sha256', v_source_sha256,
        'predecessor_snapshot_id', v_predecessor_snapshot_id,
        'blocking_reason', 'VAT_FINANCE_CATEGORY_AUTHORITY_REQUIRED',
        'recorded_at', null,
        'replayed', false
      );
      insert into public.quotation_vat_turnover_refresh_operations (
        vat_decision_authority_id, threshold_year, measurement_date,
        adapter_id, adapter_version, source_projection_id, source_sha256,
        idempotency_key, request_fingerprint, outcome, turnover_snapshot_id,
        result_payload, process_identity, process_version, created_at
      ) values (
        v_authority.vat_decision_authority_id, v_authority.threshold_year,
        p_measurement_date, v_adapter.adapter_id, v_adapter.adapter_version,
        v_source_projection_id, v_source_sha256, p_idempotency_key,
        v_request_fingerprint, 'REVIEW_REQUIRED', null, v_result,
        'VAT_TURNOVER_SNAPSHOT_ORCHESTRATOR', '1.0.0', v_now
      );
      return v_result;
  end;

  if v_validated_projection->>'projection_version' <> v_adapter.adapter_version then
    raise exception using
      errcode = 'P0001', message = 'VAT_FINANCE_PROJECTION_VERSION_INVALID';
  end if;
  if (v_validated_projection->>'covered_through')::date <> p_measurement_date
     or (v_validated_projection->>'ledger_source_watermark')::date
       <> p_measurement_date then
    raise exception using
      errcode = 'P0001', message = 'VAT_FINANCE_PROJECTION_STALE';
  end if;

  if (v_validated_projection->>'governed_turnover_minor')::numeric
       > v_authority.applicable_threshold_minor then
    v_result := jsonb_build_object(
      'measurement_date', p_measurement_date,
      'threshold_year', v_authority.threshold_year,
      'turnover_status', 'REVIEW_REQUIRED',
      'turnover_snapshot_id', null,
      'state', 'AUTHORITY_REVIEW_REQUIRED',
      'source_projection_id', v_source_projection_id,
      'source_sha256', v_source_sha256,
      'predecessor_snapshot_id', v_predecessor_snapshot_id,
      'blocking_reason', 'VAT_THRESHOLD_TRANSITION_AUTHORITY_REQUIRED',
      'recorded_at', null,
      'replayed', false
    );
    insert into public.quotation_vat_turnover_refresh_operations (
      vat_decision_authority_id, threshold_year, measurement_date,
      adapter_id, adapter_version, source_projection_id, source_sha256,
      idempotency_key, request_fingerprint, outcome, turnover_snapshot_id,
      result_payload, process_identity, process_version, created_at
    ) values (
      v_authority.vat_decision_authority_id, v_authority.threshold_year,
      p_measurement_date, v_adapter.adapter_id, v_adapter.adapter_version,
      v_source_projection_id, v_source_sha256, p_idempotency_key,
      v_request_fingerprint, 'REVIEW_REQUIRED', null, v_result,
      'VAT_TURNOVER_SNAPSHOT_ORCHESTRATOR', '1.0.0', v_now
    );
    return v_result;
  end if;

  v_turnover_snapshot_id := public.record_quotation_vat_turnover_snapshot_v1(
    p_measurement_date,
    (v_validated_projection->>'governed_turnover_minor')::bigint,
    v_source_projection_id,
    v_source_sha256,
    v_predecessor_snapshot_id,
    'VAT_TURNOVER_SNAPSHOT_ORCHESTRATOR_V1'
  );
  select recorded_at into strict v_recorded_at
  from public.quotation_vat_turnover_snapshots
  where turnover_snapshot_id = v_turnover_snapshot_id;

  v_category_manifest :=
    v_validated_projection->'category_classification_authority_references';
  v_category_manifest_sha256 := encode(extensions.digest(convert_to(
    v_category_manifest::text, 'UTF8'
  ), 'sha256'), 'hex');
  insert into public.quotation_vat_turnover_snapshot_projection_bindings (
    turnover_snapshot_id, adapter_id, adapter_version, source_projection_id,
    projection_version, source_sha256, source_schema_sha256,
    category_authority_manifest, category_authority_manifest_sha256, bound_at
  ) values (
    v_turnover_snapshot_id, v_adapter.adapter_id, v_adapter.adapter_version,
    v_source_projection_id, v_validated_projection->>'projection_version',
    v_source_sha256, v_adapter.source_schema_sha256, v_category_manifest,
    v_category_manifest_sha256, v_recorded_at
  );

  v_result := jsonb_build_object(
    'measurement_date', p_measurement_date,
    'threshold_year', v_authority.threshold_year,
    'turnover_status', 'READY',
    'turnover_snapshot_id', v_turnover_snapshot_id,
    'state', 'BELOW_OR_AT_THRESHOLD',
    'source_projection_id', v_source_projection_id,
    'source_sha256', v_source_sha256,
    'predecessor_snapshot_id', v_predecessor_snapshot_id,
    'blocking_reason', null,
    'recorded_at', v_recorded_at,
    'replayed', false
  );
  insert into public.quotation_vat_turnover_refresh_operations (
    vat_decision_authority_id, threshold_year, measurement_date,
    adapter_id, adapter_version, source_projection_id, source_sha256,
    idempotency_key, request_fingerprint, outcome, turnover_snapshot_id,
    result_payload, process_identity, process_version, created_at
  ) values (
    v_authority.vat_decision_authority_id, v_authority.threshold_year,
    p_measurement_date, v_adapter.adapter_id, v_adapter.adapter_version,
    v_source_projection_id, v_source_sha256, p_idempotency_key,
    v_request_fingerprint, 'READY', v_turnover_snapshot_id, v_result,
    'VAT_TURNOVER_SNAPSHOT_ORCHESTRATOR', '1.0.0', v_now
  );

  return v_result;
end;
$$;

create or replace function public.resolve_quotation_vat_authority_v1(
  p_quote_request_id uuid,
  p_resolution_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_request public.quote_requests%rowtype;
  v_authority public.quotation_vat_decision_authorities%rowtype;
  v_classification public.quotation_vat_transaction_classifications%rowtype;
  v_turnover public.quotation_vat_turnover_snapshots%rowtype;
  v_count integer;
  v_context_sha256 text;
begin
  if p_resolution_date is null then
    raise exception using
      errcode = 'P0001', message = 'QUOTATION_VAT_DECISION_NOT_APPROVED';
  end if;

  select count(*)::integer into v_count
  from public.quotation_vat_decision_authorities
  where authority_family = 'LWS_OUTGOING_VAT'
    and status = 'APPROVED'
    and effective_from <= p_resolution_date
    and (effective_until is null or effective_until >= p_resolution_date);
  if v_count <> 1 then
    raise exception using
      errcode = 'P0001', message = 'QUOTATION_VAT_DECISION_NOT_APPROVED';
  end if;
  select * into strict v_authority
  from public.quotation_vat_decision_authorities
  where authority_family = 'LWS_OUTGOING_VAT'
    and status = 'APPROVED'
    and effective_from <= p_resolution_date
    and (effective_until is null or effective_until >= p_resolution_date);

  select * into v_request
  from public.quote_requests
  where id = p_quote_request_id;
  if not found then
    raise exception using
      errcode = 'P0001', message = 'QUOTATION_VAT_CONTEXT_REQUIRED';
  end if;
  if upper(coalesce(v_request.billing_country, '')) <> v_authority.jurisdiction then
    raise exception using
      errcode = 'P0001', message = 'QUOTATION_VAT_CONTEXT_UNSUPPORTED';
  end if;

  v_context_sha256 := public.quotation_vat_context_sha256_v1(p_quote_request_id);
  select count(*)::integer into v_count
  from public.quotation_vat_transaction_classifications
  where quote_request_id = p_quote_request_id
    and context_sha256 = v_context_sha256
    and classification_code = 'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION';
  if v_count <> 1 then
    raise exception using
      errcode = 'P0001', message = 'QUOTATION_VAT_CONTEXT_REQUIRED';
  end if;
  select * into strict v_classification
  from public.quotation_vat_transaction_classifications
  where quote_request_id = p_quote_request_id
    and context_sha256 = v_context_sha256
    and classification_code = 'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION';

  select count(*)::integer into v_count
  from public.quotation_vat_turnover_snapshots as snapshot
  join public.quotation_vat_turnover_snapshot_projection_bindings as binding
    on binding.turnover_snapshot_id = snapshot.turnover_snapshot_id
   and rtrim(binding.source_sha256) = rtrim(snapshot.source_sha256)
  join public.vat_finance_projection_adapters as adapter
    on adapter.adapter_id = binding.adapter_id
   and adapter.adapter_version = binding.adapter_version
   and rtrim(adapter.source_schema_sha256)
     = rtrim(binding.source_schema_sha256)
   and adapter.status = 'APPROVED'
   and adapter.effective_from <= p_resolution_date
   and (adapter.effective_until is null
     or adapter.effective_until >= p_resolution_date)
  where snapshot.vat_decision_authority_id = v_authority.vat_decision_authority_id
    and snapshot.threshold_year = v_authority.threshold_year
    and snapshot.measurement_watermark = p_resolution_date;
  if v_count <> 1 then
    raise exception using
      errcode = 'P0001',
      message = 'QUOTATION_VAT_THRESHOLD_AUTHORITY_REVIEW_REQUIRED';
  end if;
  select snapshot.* into strict v_turnover
  from public.quotation_vat_turnover_snapshots as snapshot
  join public.quotation_vat_turnover_snapshot_projection_bindings as binding
    on binding.turnover_snapshot_id = snapshot.turnover_snapshot_id
   and rtrim(binding.source_sha256) = rtrim(snapshot.source_sha256)
  join public.vat_finance_projection_adapters as adapter
    on adapter.adapter_id = binding.adapter_id
   and adapter.adapter_version = binding.adapter_version
   and rtrim(adapter.source_schema_sha256)
     = rtrim(binding.source_schema_sha256)
   and adapter.status = 'APPROVED'
   and adapter.effective_from <= p_resolution_date
   and (adapter.effective_until is null
     or adapter.effective_until >= p_resolution_date)
  where snapshot.vat_decision_authority_id = v_authority.vat_decision_authority_id
    and snapshot.threshold_year = v_authority.threshold_year
    and snapshot.measurement_watermark = p_resolution_date;
  if v_turnover.state <> 'BELOW_OR_AT_THRESHOLD'
     or v_turnover.governed_turnover_minor
       > v_authority.applicable_threshold_minor then
    raise exception using
      errcode = 'P0001', message = 'AUTHORITY_REVIEW_REQUIRED';
  end if;

  return jsonb_build_object(
    'vat_decision_authority_id', v_authority.vat_decision_authority_id,
    'authority_family', v_authority.authority_family,
    'decision_code', v_authority.decision_code,
    'decision_version', v_authority.decision_version,
    'authority_sha256', rtrim(v_authority.authority_sha256),
    'vat_treatment', v_authority.vat_treatment,
    'rate_semantics', v_authority.rate_semantics,
    'vat_rate', v_authority.vat_rate,
    'invoice_literal', v_authority.invoice_literal,
    'context_sha256', v_context_sha256,
    'classification_id', v_classification.classification_id,
    'turnover_snapshot_id', v_turnover.turnover_snapshot_id,
    'applicable_threshold_minor', v_authority.applicable_threshold_minor,
    'governed_turnover_minor', v_turnover.governed_turnover_minor
  );
end;
$$;

alter table public.quotation_vat_turnover_refresh_operations
  enable row level security;
alter table public.quotation_vat_turnover_refresh_operations
  force row level security;
alter table public.quotation_vat_turnover_snapshot_projection_bindings
  enable row level security;
alter table public.quotation_vat_turnover_snapshot_projection_bindings
  force row level security;

revoke all privileges on table public.quotation_vat_turnover_refresh_operations
from public, anon, authenticated, service_role;
revoke all privileges on table
  public.quotation_vat_turnover_snapshot_projection_bindings
from public, anon, authenticated, service_role;

revoke all on function lws_internal.validate_vat_finance_projection_v1(jsonb)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.prevent_vat_turnover_refresh_operation_mutation_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.prevent_vat_turnover_projection_binding_mutation_v1()
from public, anon, authenticated, service_role;
revoke all on function public.record_quotation_vat_turnover_snapshot_v1(
  date, bigint, text, text, uuid, text
) from public, anon, authenticated, service_role;
revoke all on function public.refresh_quotation_vat_turnover_snapshot_v1(date, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.refresh_quotation_vat_turnover_snapshot_v1(date, uuid)
to service_role;

comment on function public.refresh_quotation_vat_turnover_snapshot_v1(date, uuid) is
  'Service-only VAT turnover snapshot orchestrator. It accepts no turnover amount or source assertion and persists only a validated governed Finance projection.';
