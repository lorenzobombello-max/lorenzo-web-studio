begin;

create table public.website_quotation_pricing_decisions (
  decision_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null references public.quote_requests(id) on delete restrict,
  intake_id uuid not null unique references public.quote_request_intakes(id) on delete restrict,
  pricing_snapshot_id uuid not null unique references public.quote_request_pricing_snapshots(id) on delete restrict,
  pricing_snapshot_sha256 char(64) not null check (pricing_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  pricing_integrity_algorithm_version text not null check (pricing_integrity_algorithm_version = 'hmac-sha256-v1'),
  pricing_integrity_key_id text not null check (pricing_integrity_key_id ~ '^v[1-9][0-9]*$'),
  pricing_integrity_mac char(64) not null check (pricing_integrity_mac ~ '^[0-9a-f]{64}$'),
  resolved_rule_id text not null check (nullif(btrim(resolved_rule_id),'') is not null),
  currency char(3) not null check (currency = 'EUR'),
  known_minimum_minor bigint not null check (known_minimum_minor >= 0),
  owner_final_amount_minor bigint not null check (owner_final_amount_minor >= known_minimum_minor),
  decision_reason text check (
    decision_reason is null or (
      decision_reason = btrim(decision_reason)
      and length(decision_reason) between 1 and 1000
    )
  ),
  decided_by_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  decided_by_actor text not null check (decided_by_actor ~ '^OPERATOR:[0-9a-f-]{36}$'),
  decided_at timestamptz not null,
  idempotency_key uuid not null unique,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  decision_sha256 char(64) not null check (decision_sha256 ~ '^[0-9a-f]{64}$')
);

create table public.website_quotation_pricing_decision_events (
  event_id bigint generated always as identity primary key,
  decision_id uuid not null unique references public.website_quotation_pricing_decisions(decision_id) on delete restrict,
  quote_request_id uuid not null references public.quote_requests(id) on delete restrict,
  intake_id uuid not null unique references public.quote_request_intakes(id) on delete restrict,
  pricing_snapshot_id uuid not null unique references public.quote_request_pricing_snapshots(id) on delete restrict,
  event_type text not null check (event_type = 'WEBSITE_QUOTATION_PRICING_DECIDED'),
  actor_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  actor text not null check (actor ~ '^OPERATOR:[0-9a-f-]{36}$'),
  idempotency_key uuid not null unique,
  occurred_at timestamptz not null,
  metadata jsonb not null check (
    public.jsonb_has_exact_keys(metadata,array[
      'decision_id','quote_request_id','intake_id','pricing_snapshot_id',
      'pricing_snapshot_sha256','resolved_rule_id','currency',
      'known_minimum_minor','owner_final_amount_minor'
    ])
  )
);

create function public.guard_website_quotation_pricing_decision_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_table_name = 'website_quotation_pricing_decision_events' then
    raise exception using errcode='55000',message='WEBSITE_PRICING_DECISION_EVENT_IMMUTABLE';
  end if;
  raise exception using errcode='55000',message='WEBSITE_PRICING_DECISION_IMMUTABLE';
end;
$$;

create trigger trg_website_quotation_pricing_decisions_immutable
before update or delete on public.website_quotation_pricing_decisions
for each row execute function public.guard_website_quotation_pricing_decision_v1();
create trigger trg_website_quotation_pricing_decision_events_immutable
before update or delete on public.website_quotation_pricing_decision_events
for each row execute function public.guard_website_quotation_pricing_decision_v1();

create function public.website_pricing_snapshot_sha256_v1(p_snapshot_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_snapshot public.quote_request_pricing_snapshots%rowtype;
  v_integrity public.quote_request_pricing_snapshot_integrity%rowtype;
begin
  select * into v_snapshot from public.quote_request_pricing_snapshots where id=p_snapshot_id;
  select * into v_integrity from public.quote_request_pricing_snapshot_integrity where snapshot_id=p_snapshot_id;
  if v_snapshot.id is null or v_integrity.snapshot_id is null then
    raise exception using errcode='23514',message='WEBSITE_PRICING_SNAPSHOT_NOT_FOUND';
  end if;
  return encode(extensions.digest(convert_to(jsonb_build_object(
    'snapshotId',v_snapshot.id,
    'intakeId',v_snapshot.intake_id,
    'snapshotContractVersion',v_snapshot.snapshot_contract_version,
    'configVersion',v_snapshot.config_version,
    'configHash',v_snapshot.config_hash,
    'normalizedEvidence',v_snapshot.normalized_evidence,
    'calculation',v_snapshot.calculation,
    'packageAdvice',v_snapshot.package_advice,
    'budgetEvaluation',v_snapshot.budget_evaluation,
    'packageDefinition',v_snapshot.package_definition,
    'recurringServices',v_snapshot.recurring_services,
    'integrityAlgorithmVersion',v_integrity.algorithm_version,
    'integrityKeyId',v_integrity.key_id,
    'integrityMac',v_integrity.mac
  )::text,'UTF8'),'sha256'),'hex');
end;
$$;

create function public.get_operator_website_quotation_pricing_state_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid,
  p_intake_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_request public.quote_requests%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_snapshot public.quote_request_pricing_snapshots%rowtype;
  v_decision public.website_quotation_pricing_decisions%rowtype;
  v_from_count integer;
  v_has_draft boolean;
begin
  if auth.uid() is null then
    raise exception using errcode='42501',message='HUMAN_JWT_REQUIRED';
  end if;
  if auth.uid() <> p_actor_auth_user_id then
    raise exception using errcode='42501',message='OPERATOR_IDENTITY_MISMATCH';
  end if;
  perform lws_internal.assert_operator_application_actor_v2(p_actor_auth_user_id);
  select * into strict v_operator from public.commercial_operators where auth_user_id=p_actor_auth_user_id;
  select * into v_request from public.quote_requests
  where id=p_quote_request_id and request_kind='website'
    and record_classification in ('production','internal_e2e');
  select * into v_intake from public.quote_request_intakes
  where id=p_intake_id and quote_request_id=p_quote_request_id and status in ('submitted','reviewed');
  select * into v_snapshot from public.quote_request_pricing_snapshots where intake_id=p_intake_id;
  if v_request.id is null or v_intake.id is null or v_snapshot.id is null then
    raise exception using errcode='23514',message='WEBSITE_PRICING_INTAKE_NOT_READY';
  end if;
  select count(*)::integer into v_from_count
  from jsonb_array_elements(v_snapshot.calculation->'appliedRules') rule(value)
  where lower(rule.value->>'mode')='from';
  select * into v_decision from public.website_quotation_pricing_decisions where intake_id=p_intake_id;
  select exists(select 1 from public.quote_request_quotation_business_drafts where intake_id=p_intake_id)
  into v_has_draft;
  return jsonb_build_object(
    'quote_request_id',v_request.id,
    'intake_id',v_intake.id,
    'pricing_snapshot_id',v_snapshot.id,
    'pricing_snapshot_sha256',public.website_pricing_snapshot_sha256_v1(v_snapshot.id),
    'currency',v_snapshot.calculation->>'currency',
    'known_minimum_minor',(v_snapshot.calculation->>'knownMinimumMinor')::bigint,
    'contains_from_pricing',v_from_count>0,
    'decision_required',v_from_count=1 and v_decision.decision_id is null,
    'can_decide',v_operator.role='owner' and coalesce(auth.jwt()->>'aal','')='aal2'
      and auth.uid() in (
        'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'::uuid,
        'bd2ab636-0d42-4069-88a9-60bd97f2b335'::uuid
      ),
    'resolved',v_decision.decision_id is not null,
    'decision',case when v_decision.decision_id is null then null else jsonb_build_object(
      'decision_id',v_decision.decision_id,
      'resolved_rule_id',v_decision.resolved_rule_id,
      'currency',v_decision.currency,
      'known_minimum_minor',v_decision.known_minimum_minor,
      'owner_final_amount_minor',v_decision.owner_final_amount_minor,
      'decision_sha256',rtrim(v_decision.decision_sha256),
      'decided_at',v_decision.decided_at
    ) end,
    'quotation_draft_available',v_has_draft
  );
end;
$$;

create function public.authorize_website_quotation_pricing_decision_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid,
  p_intake_id uuid,
  p_expected_pricing_snapshot_id uuid,
  p_expected_pricing_snapshot_sha256 text,
  p_currency text,
  p_owner_final_amount_minor bigint,
  p_decision_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_request public.quote_requests%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_snapshot public.quote_request_pricing_snapshots%rowtype;
  v_integrity public.quote_request_pricing_snapshot_integrity%rowtype;
  v_existing public.website_quotation_pricing_decisions%rowtype;
  v_rule jsonb;
  v_from_count integer;
  v_manual_count integer;
  v_snapshot_sha text;
  v_currency text;
  v_minimum bigint;
  v_reason text;
  v_fingerprint text;
  v_decision_id uuid:=gen_random_uuid();
  v_decision_sha text;
  v_actor text;
  v_now timestamptz:=clock_timestamp();
begin
  if p_actor_auth_user_id is null or p_quote_request_id is null or p_intake_id is null
     or p_expected_pricing_snapshot_id is null or p_idempotency_key is null
     or p_expected_pricing_snapshot_sha256 !~ '^[0-9a-f]{64}$'
     or p_owner_final_amount_minor is null or p_owner_final_amount_minor<=0
     or p_currency is null then
    raise exception using errcode='22023',message='WEBSITE_PRICING_DECISION_INPUT_INVALID';
  end if;
  if auth.uid() is null then raise exception using errcode='42501',message='HUMAN_JWT_REQUIRED'; end if;
  if auth.uid()<>p_actor_auth_user_id then raise exception using errcode='42501',message='OPERATOR_IDENTITY_MISMATCH'; end if;
  perform lws_internal.assert_operator_aal2_v1();
  select * into v_operator from public.commercial_operators where auth_user_id=p_actor_auth_user_id;
  if not found or v_operator.status<>'ACTIVE' or v_operator.role<>'owner' then
    raise exception using errcode='42501',message='WEBSITE_PRICING_DECISION_FORBIDDEN';
  end if;
  v_reason:=nullif(btrim(p_decision_reason),'');
  if v_reason is not null and length(v_reason)>1000 then
    raise exception using errcode='22023',message='WEBSITE_PRICING_DECISION_INPUT_INVALID';
  end if;
  v_actor:='OPERATOR:'||v_operator.operator_id::text;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_intake_id::text,0));
  select * into v_request from public.quote_requests where id=p_quote_request_id for update;
  if not found then raise exception using errcode='23503',message='WEBSITE_PRICING_REQUEST_NOT_FOUND'; end if;
  if v_request.request_kind<>'website' or v_request.record_classification not in ('production','internal_e2e') then
    raise exception using errcode='23514',message='WEBSITE_PRICING_DOMAIN_MISMATCH';
  end if;
  select * into v_intake from public.quote_request_intakes
  where id=p_intake_id and quote_request_id=p_quote_request_id for update;
  if not found or v_intake.status not in ('submitted','reviewed') then
    raise exception using errcode='23514',message='WEBSITE_PRICING_INTAKE_NOT_READY';
  end if;
  select * into v_snapshot from public.quote_request_pricing_snapshots
  where id=p_expected_pricing_snapshot_id and intake_id=p_intake_id for update;
  if not found then raise exception using errcode='23514',message='WEBSITE_PRICING_SNAPSHOT_STALE'; end if;
  select * into v_integrity from public.quote_request_pricing_snapshot_integrity
  where snapshot_id=v_snapshot.id for update;
  if not found then raise exception using errcode='23514',message='WEBSITE_PRICING_SNAPSHOT_NOT_FOUND'; end if;
  v_snapshot_sha:=public.website_pricing_snapshot_sha256_v1(v_snapshot.id);
  if v_snapshot_sha<>p_expected_pricing_snapshot_sha256 then
    raise exception using errcode='23514',message='WEBSITE_PRICING_SNAPSHOT_STALE';
  end if;
  select count(*) filter(where lower(rule.value->>'mode')='from')::integer,
         count(*) filter(where lower(rule.value->>'mode')='manual')::integer,
         (min(rule.value::text) filter(where lower(rule.value->>'mode')='from'))::jsonb
  into v_from_count,v_manual_count,v_rule
  from jsonb_array_elements(v_snapshot.calculation->'appliedRules') rule(value);
  if v_from_count=0 then raise exception using errcode='23514',message='WEBSITE_PRICING_DECISION_NOT_REQUIRED'; end if;
  if v_from_count<>1 or v_manual_count<>0 or (v_rule->>'quantity')::numeric<>1 then
    raise exception using errcode='23514',message='WEBSITE_PRICING_DECISION_SCOPE_UNSUPPORTED';
  end if;
  v_currency:=v_snapshot.calculation->>'currency';
  v_minimum:=(v_snapshot.calculation->>'knownMinimumMinor')::bigint;
  if v_currency<>'EUR' or p_currency<>v_currency then
    raise exception using errcode='23514',message='WEBSITE_PRICING_CURRENCY_MISMATCH';
  end if;
  if p_owner_final_amount_minor<v_minimum then
    raise exception using errcode='23514',message='WEBSITE_PRICING_AMOUNT_BELOW_MINIMUM';
  end if;
  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'authorityVersion',1,'actorAuthUserId',p_actor_auth_user_id,
    'quoteRequestId',p_quote_request_id,'intakeId',p_intake_id,
    'expectedPricingSnapshotId',p_expected_pricing_snapshot_id,
    'expectedPricingSnapshotSha256',p_expected_pricing_snapshot_sha256,
    'serverPricingSnapshotId',v_snapshot.id,'serverPricingSnapshotSha256',v_snapshot_sha,
    'resolvedRuleId',v_rule->>'ruleId','currency',v_currency,
    'knownMinimumMinor',v_minimum,'ownerFinalAmountMinor',p_owner_final_amount_minor,
    'decisionReason',v_reason
  )::text,'UTF8'),'sha256'),'hex');
  select * into v_existing from public.website_quotation_pricing_decisions
  where idempotency_key=p_idempotency_key;
  if found then
    if rtrim(v_existing.request_fingerprint)<>v_fingerprint then
      raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'decision_id',v_existing.decision_id,'quote_request_id',v_existing.quote_request_id,
      'intake_id',v_existing.intake_id,'pricing_snapshot_id',v_existing.pricing_snapshot_id,
      'resolved_rule_id',v_existing.resolved_rule_id,'currency',v_existing.currency,
      'known_minimum_minor',v_existing.known_minimum_minor,
      'owner_final_amount_minor',v_existing.owner_final_amount_minor,
      'decision_sha256',rtrim(v_existing.decision_sha256),'decided_at',v_existing.decided_at,
      'status','WEBSITE_QUOTATION_PRICING_DECIDED','replayed',true
    );
  end if;
  if exists(select 1 from public.website_quotation_pricing_decisions where intake_id=p_intake_id) then
    raise exception using errcode='55000',message='WEBSITE_PRICING_DECISION_ALREADY_EXISTS';
  end if;
  v_decision_sha:=encode(extensions.digest(convert_to(jsonb_build_object(
    'authorityVersion',1,'decisionId',v_decision_id,'quoteRequestId',p_quote_request_id,
    'intakeId',p_intake_id,'pricingSnapshotId',v_snapshot.id,
    'pricingSnapshotSha256',v_snapshot_sha,'resolvedRuleId',v_rule->>'ruleId',
    'currency',v_currency,'knownMinimumMinor',v_minimum,
    'ownerFinalAmountMinor',p_owner_final_amount_minor,'decisionReason',v_reason,
    'decidedBy',v_actor,'decidedAt',v_now
  )::text,'UTF8'),'sha256'),'hex');
  insert into public.website_quotation_pricing_decisions(
    decision_id,quote_request_id,intake_id,pricing_snapshot_id,pricing_snapshot_sha256,
    pricing_integrity_algorithm_version,pricing_integrity_key_id,pricing_integrity_mac,
    resolved_rule_id,currency,known_minimum_minor,owner_final_amount_minor,decision_reason,
    decided_by_operator_id,decided_by_actor,decided_at,idempotency_key,request_fingerprint,decision_sha256
  ) values(
    v_decision_id,p_quote_request_id,p_intake_id,v_snapshot.id,v_snapshot_sha,
    v_integrity.algorithm_version,v_integrity.key_id,v_integrity.mac,
    v_rule->>'ruleId',v_currency,v_minimum,p_owner_final_amount_minor,v_reason,
    v_operator.operator_id,v_actor,v_now,p_idempotency_key,v_fingerprint,v_decision_sha
  ) returning * into v_existing;
  insert into public.website_quotation_pricing_decision_events(
    decision_id,quote_request_id,intake_id,pricing_snapshot_id,event_type,
    actor_operator_id,actor,idempotency_key,occurred_at,metadata
  ) values(
    v_decision_id,p_quote_request_id,p_intake_id,v_snapshot.id,'WEBSITE_QUOTATION_PRICING_DECIDED',
    v_operator.operator_id,v_actor,p_idempotency_key,v_now,jsonb_build_object(
      'decision_id',v_decision_id,'quote_request_id',p_quote_request_id,'intake_id',p_intake_id,
      'pricing_snapshot_id',v_snapshot.id,'pricing_snapshot_sha256',v_snapshot_sha,
      'resolved_rule_id',v_rule->>'ruleId','currency',v_currency,
      'known_minimum_minor',v_minimum,'owner_final_amount_minor',p_owner_final_amount_minor
    )
  );
  return jsonb_build_object(
    'decision_id',v_existing.decision_id,'quote_request_id',v_existing.quote_request_id,
    'intake_id',v_existing.intake_id,'pricing_snapshot_id',v_existing.pricing_snapshot_id,
    'resolved_rule_id',v_existing.resolved_rule_id,'currency',v_existing.currency,
    'known_minimum_minor',v_existing.known_minimum_minor,
    'owner_final_amount_minor',v_existing.owner_final_amount_minor,
    'decision_sha256',rtrim(v_existing.decision_sha256),'decided_at',v_existing.decided_at,
    'status','WEBSITE_QUOTATION_PRICING_DECIDED','replayed',false
  );
end;
$$;

create function lws_internal.resolve_website_quotation_calculation_v1(
  p_quote_request_id uuid,
  p_intake_id uuid,
  p_snapshot_id uuid,
  p_calculation jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_decision public.website_quotation_pricing_decisions%rowtype;
  v_snapshot public.quote_request_pricing_snapshots%rowtype;
  v_integrity public.quote_request_pricing_snapshot_integrity%rowtype;
  v_result jsonb:=p_calculation;
  v_rule jsonb;
  v_rules jsonb:='[]'::jsonb;
  v_from_count integer:=0;
  v_manual_count integer:=0;
  v_total bigint:=0;
begin
  if p_calculation is null or jsonb_typeof(p_calculation->'appliedRules')<>'array' then
    raise exception using errcode='23514',message='WEBSITE_PRICING_DECISION_STALE';
  end if;
  select count(*) filter(where lower(rule.value->>'mode')='from')::integer,
         count(*) filter(where lower(rule.value->>'mode')='manual')::integer
  into v_from_count,v_manual_count
  from jsonb_array_elements(p_calculation->'appliedRules') rule(value);
  if v_manual_count>0 then raise exception using errcode='P0001',message='QUOTATION_PRICING_MANUAL_UNRESOLVED'; end if;
  if v_from_count=0 then return p_calculation; end if;
  select * into v_decision from public.website_quotation_pricing_decisions where intake_id=p_intake_id;
  if not found then raise exception using errcode='P0001',message='QUOTATION_PRICING_FROM_UNRESOLVED'; end if;
  select snapshot.* into v_snapshot
  from public.quote_request_pricing_snapshots snapshot
  join public.quote_request_intakes intake on intake.id=snapshot.intake_id
  where snapshot.id=p_snapshot_id and snapshot.intake_id=p_intake_id
    and intake.quote_request_id=p_quote_request_id and intake.status in ('submitted','reviewed');
  select * into v_integrity from public.quote_request_pricing_snapshot_integrity where snapshot_id=p_snapshot_id;
  if v_snapshot.id is null or v_integrity.snapshot_id is null
     or v_decision.quote_request_id<>p_quote_request_id
     or v_decision.pricing_snapshot_id<>p_snapshot_id
     or rtrim(v_decision.pricing_snapshot_sha256)<>public.website_pricing_snapshot_sha256_v1(p_snapshot_id)
     or v_decision.pricing_integrity_algorithm_version<>v_integrity.algorithm_version
     or v_decision.pricing_integrity_key_id<>v_integrity.key_id
     or rtrim(v_decision.pricing_integrity_mac)<>v_integrity.mac
     or v_decision.currency<>p_calculation->>'currency'
     or v_decision.known_minimum_minor<>(p_calculation->>'knownMinimumMinor')::bigint then
    raise exception using errcode='23514',message='WEBSITE_PRICING_DECISION_STALE';
  end if;
  for v_rule in select value from jsonb_array_elements(p_calculation->'appliedRules') loop
    if lower(v_rule->>'mode')='from' then
      if v_from_count<>1 or (v_rule->>'quantity')::numeric<>1
         or v_rule->>'ruleId'<>v_decision.resolved_rule_id then
        raise exception using errcode='23514',message='WEBSITE_PRICING_DECISION_STALE';
      end if;
      v_rule:=jsonb_set(jsonb_set(jsonb_set(v_rule,'{mode}','"fixed"'::jsonb),
        '{amountMinor}',to_jsonb(v_decision.owner_final_amount_minor)),
        '{knownMinimumContributionMinor}',to_jsonb(v_decision.owner_final_amount_minor));
    end if;
    v_total:=v_total+coalesce((v_rule->>'knownMinimumContributionMinor')::bigint,0);
    v_rules:=v_rules||jsonb_build_array(v_rule);
  end loop;
  v_result:=jsonb_set(v_result,'{appliedRules}',v_rules);
  v_result:=jsonb_set(v_result,'{knownMinimumMinor}',to_jsonb(v_total));
  v_result:=jsonb_set(v_result,'{containsFromPricing}','false'::jsonb);
  return v_result;
end;
$$;

create or replace function public.is_valid_quotation_approval_payload_v1(
  p_payload jsonb,
  p_require_approval boolean default true
)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  v_line jsonb;
  v_one_time_subtotal bigint := 0;
  v_recurring_subtotal bigint := 0;
  v_discount_total bigint := 0;
  v_totals jsonb;
begin
  if not public.jsonb_has_exact_keys(p_payload, array[
    'contract_version', 'source_quote_request_id', 'source_intake_id',
    'pricing_snapshot', 'currency', 'line_items', 'totals', 'discount',
    'customer_identity', 'project_scope', 'vat_approval', 'payment_schedule',
    'validity', 'legal_references'
  ])
    or p_payload->'contract_version' <> '1'::jsonb
    or (p_payload->>'source_quote_request_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or (p_payload->>'source_intake_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or not (
      public.jsonb_has_exact_keys(p_payload->'pricing_snapshot', array[
        'snapshot_id', 'snapshot_contract_version', 'integrity_algorithm_version',
        'integrity_key_id', 'integrity_mac'
      ])
      or (
        public.jsonb_has_exact_keys(p_payload->'pricing_snapshot', array[
          'snapshot_id', 'snapshot_contract_version', 'integrity_algorithm_version',
          'integrity_key_id', 'integrity_mac', 'website_pricing_decision_id',
          'website_pricing_decision_sha256'
        ])
        and (p_payload->'pricing_snapshot'->>'website_pricing_decision_id')
          ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        and public.is_sha256_jsonb(
          p_payload->'pricing_snapshot'->'website_pricing_decision_sha256'
        )
      )
    )
    or (p_payload->'pricing_snapshot'->>'snapshot_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or not public.is_jsonb_nonnegative_integer(p_payload->'pricing_snapshot'->'snapshot_contract_version')
    or (p_payload->'pricing_snapshot'->>'snapshot_contract_version')::integer not in (2, 3, 4)
    or p_payload->'pricing_snapshot'->>'integrity_algorithm_version' <> 'hmac-sha256-v1'
    or (p_payload->'pricing_snapshot'->>'integrity_key_id') !~ '^v[1-9][0-9]*$'
    or not public.is_sha256_jsonb(p_payload->'pricing_snapshot'->'integrity_mac')
    or p_payload->>'currency' <> 'EUR'
    or not public.is_valid_quotation_lines_v1(p_payload->'line_items')
    or not public.jsonb_has_exact_keys(p_payload->'totals', array[
      'one_time_subtotal_minor', 'recurring_subtotal_minor', 'discount_total_minor',
      'vat_base_minor', 'vat_amount_minor', 'total_gross_minor'
    ])
    or not public.is_valid_quotation_discount_v1(p_payload->'discount', p_require_approval)
    or not public.is_valid_quotation_identity_v1(p_payload->'customer_identity')
    or not public.is_valid_quotation_scope_v1(p_payload->'project_scope')
    or not public.is_valid_quotation_vat_approval_v1(p_payload->'vat_approval', p_require_approval)
    or not public.is_valid_quotation_legal_references_v1(p_payload->'legal_references', p_require_approval)
    or not public.is_valid_quotation_validity_v1(p_payload->'validity', p_require_approval) then
    return false;
  end if;

  if p_payload->'customer_identity'->>'source_quote_request_id'
       is distinct from p_payload->>'source_quote_request_id'
     or p_payload->'customer_identity'->>'source_intake_id'
       is distinct from p_payload->>'source_intake_id'
     or p_payload->'project_scope'->>'source_intake_id'
       is distinct from p_payload->>'source_intake_id'
     or p_payload->'project_scope'->>'source_pricing_snapshot_id'
       is distinct from p_payload->'pricing_snapshot'->>'snapshot_id' then
    return false;
  end if;

  v_totals := p_payload->'totals';
  if not (
    public.is_jsonb_nonnegative_integer(v_totals->'one_time_subtotal_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'recurring_subtotal_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'discount_total_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'vat_base_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'vat_amount_minor')
    and public.is_jsonb_nonnegative_integer(v_totals->'total_gross_minor')
  ) then
    return false;
  end if;

  for v_line in select value from jsonb_array_elements(p_payload->'line_items') loop
    if v_line->>'cost_type' = 'ONE_TIME' then
      v_one_time_subtotal := v_one_time_subtotal + (v_line->>'line_net_amount_minor')::bigint;
    else
      v_recurring_subtotal := v_recurring_subtotal + (v_line->>'line_net_amount_minor')::bigint;
    end if;
    v_discount_total := v_discount_total + (v_line->>'discount_minor')::bigint;
  end loop;

  if (v_totals->>'one_time_subtotal_minor')::bigint <> v_one_time_subtotal
     or (v_totals->>'recurring_subtotal_minor')::bigint <> v_recurring_subtotal
     or (v_totals->>'discount_total_minor')::bigint <> v_discount_total
     or (p_payload->'discount'->>'discount_value_minor')::bigint <> v_discount_total
     or (v_totals->>'vat_base_minor')::bigint <> v_one_time_subtotal
     or (v_totals->>'total_gross_minor')::bigint
       <> (v_totals->>'vat_base_minor')::bigint
       + (v_totals->>'vat_amount_minor')::bigint then
    return false;
  end if;

  return public.is_valid_quotation_payment_schedule_v1(
    p_payload->'payment_schedule', v_one_time_subtotal, p_require_approval
  );
exception
  when others then
    return false;
end;
$$;

create or replace function public.upsert_quotation_business_draft_v1(
  p_actor_auth_user_id uuid,
  p_intake_id uuid,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_input jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_request public.quote_requests%rowtype;
  v_snapshot public.quote_request_pricing_snapshots%rowtype;
  v_integrity public.quote_request_pricing_snapshot_integrity%rowtype;
  v_website_pricing_decision public.website_quotation_pricing_decisions%rowtype;
  v_seller public.quotation_seller_authorities%rowtype;
  v_terms public.quotation_terms_authorities%rowtype;
  v_vat public.quotation_vat_decision_authorities%rowtype;
  v_template public.quotation_template_authorities%rowtype;
  v_policy public.quotation_business_policy_authorities%rowtype;
  v_previous public.quote_request_quotation_business_drafts%rowtype;
  v_existing public.quote_request_quotation_business_drafts%rowtype;
  v_approval_draft record;
  v_line_input jsonb;
  v_rule jsonb;
  v_lines jsonb := '[]'::jsonb;
  v_customer jsonb;
  v_scope jsonb;
  v_payload jsonb;
  v_result jsonb;
  v_request_fingerprint text;
  v_payload_sha256 text;
  v_actor text;
  v_now timestamptz := clock_timestamp();
  v_revision bigint;
  v_sequence integer := 0;
  v_rule_count integer;
  v_quantity numeric;
  v_unit_minor bigint;
  v_gross_minor bigint;
  v_line_discount bigint;
  v_discount_remaining bigint;
  v_discount_minor bigint;
  v_one_time_minor bigint := 0;
  v_vat_minor bigint;
  v_validity_days integer;
  v_pricing_reference jsonb;
  v_schedule jsonb;
  v_identity_base jsonb;
  v_scope_base jsonb;
begin
  if p_actor_auth_user_id is null or p_intake_id is null or p_idempotency_key is null
     or p_expected_revision is null or p_expected_revision < 0
     or not public.jsonb_has_exact_keys(p_input, array[
       'commercial_lines', 'discount', 'scope', 'vat_decision_authority_id',
       'payment_schedule', 'validity_days', 'terms_authority_id'
     ]) then
    raise exception using errcode = '22023', message = 'QUOTATION_BUSINESS_INPUT_INVALID';
  end if;

  select * into v_operator from public.commercial_operators
  where auth_user_id = p_actor_auth_user_id;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'QUOTATION_BUSINESS_SCOPE_DENIED';
  end if;
  v_actor := 'OPERATOR:' || v_operator.operator_id::text;

  v_request_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'actorAuthUserId', p_actor_auth_user_id,
    'expectedRevision', p_expected_revision,
    'input', p_input,
    'intakeId', p_intake_id
  )::text, 'UTF8'), 'sha256'), 'hex');
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key::text, 0)
  );
  select * into v_existing from public.quote_request_quotation_business_drafts
  where idempotency_key = p_idempotency_key;
  if found then
    if rtrim(v_existing.request_fingerprint) <> v_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed', true);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_intake_id::text, 0));
  select * into v_intake from public.quote_request_intakes where id = p_intake_id for update;
  if not found or v_intake.status not in ('submitted', 'reviewed')
     or v_intake.admin_access_token_hash is null
     or v_intake.admin_access_token_expires_at <= v_now
     or v_intake.admin_access_token_revoked_at is not null then
    raise exception using errcode = '42501', message = 'QUOTATION_INTAKE_NOT_AVAILABLE';
  end if;
  select * into strict v_request from public.quote_requests where id = v_intake.quote_request_id;
  select * into strict v_snapshot from public.quote_request_pricing_snapshots
  where intake_id = p_intake_id;
  select * into strict v_integrity from public.quote_request_pricing_snapshot_integrity
  where snapshot_id = v_snapshot.id;

  v_pricing_reference := jsonb_build_object(
    'snapshot_id', v_snapshot.id,
    'snapshot_contract_version', v_snapshot.snapshot_contract_version,
    'integrity_algorithm_version', v_integrity.algorithm_version,
    'integrity_key_id', v_integrity.key_id,
    'integrity_mac', v_integrity.mac
  );
  if not public.is_current_pricing_snapshot_integrity_valid(
    p_intake_id, v_snapshot.id, v_pricing_reference
  ) then
    raise exception using errcode = 'P0001', message = 'PRICING_INTEGRITY_INVALID';
  end if;
  v_snapshot.calculation := lws_internal.resolve_website_quotation_calculation_v1(
    v_request.id, v_intake.id, v_snapshot.id, v_snapshot.calculation
  );
  select * into v_website_pricing_decision
  from public.website_quotation_pricing_decisions
  where intake_id = v_intake.id;
  if found then
    v_pricing_reference := v_pricing_reference || jsonb_build_object(
      'website_pricing_decision_id', v_website_pricing_decision.decision_id,
      'website_pricing_decision_sha256', rtrim(v_website_pricing_decision.decision_sha256)
    );
  end if;

  select * into v_seller from public.resolve_quotation_seller_authority_v1();
  select * into v_terms from public.quotation_terms_authorities
  where terms_authority_id = (p_input->>'terms_authority_id')::uuid and status = 'APPROVED';
  if not found then raise exception using errcode = 'P0001', message = 'QUOTATION_TERMS_NOT_APPROVED'; end if;
  select * into v_vat from public.quotation_vat_decision_authorities
  where vat_decision_authority_id = (p_input->>'vat_decision_authority_id')::uuid and status = 'APPROVED';
  if not found then raise exception using errcode = 'P0001', message = 'QUOTATION_VAT_DECISION_NOT_APPROVED'; end if;
  select * into strict v_template from public.resolve_approved_quotation_template_v1(
    'QUOTATION', 'nl-BE', 'EUR', 1::smallint, 1::smallint, 1::smallint
  );
  select * into strict v_policy from public.quotation_business_policy_authorities
  where policy_id = 'QUOTATION_BUSINESS_V1' and status = 'APPROVED';

  select * into v_previous from public.quote_request_quotation_business_drafts
  where intake_id = p_intake_id order by business_revision desc limit 1;
  v_revision := coalesce(v_previous.business_revision, 0) + 1;
  if p_expected_revision <> v_revision - 1 then
    raise exception using errcode = 'P0001', message = 'STALE_BUSINESS_REVISION';
  end if;

  if jsonb_typeof(p_input->'commercial_lines') <> 'array'
     or jsonb_array_length(p_input->'commercial_lines') < 1 then
    raise exception using errcode = '22023', message = 'COMMERCIAL_LINES_REQUIRED';
  end if;
  if not public.jsonb_has_exact_keys(p_input->'discount', array[
    'discount_type', 'discount_value_minor', 'discount_reason'
  ]) or not public.is_jsonb_nonnegative_integer(p_input->'discount'->'discount_value_minor') then
    raise exception using errcode = '22023', message = 'DISCOUNT_INVALID';
  end if;
  v_discount_minor := (p_input->'discount'->>'discount_value_minor')::bigint;
  if v_discount_minor > 0 and (
    nullif(btrim(p_input->'discount'->>'discount_type'), '') is null
    or nullif(btrim(p_input->'discount'->>'discount_reason'), '') is null
  ) then
    raise exception using errcode = '22023', message = 'DISCOUNT_REASON_REQUIRED';
  end if;
  v_discount_remaining := v_discount_minor;

  for v_line_input in select value from jsonb_array_elements(p_input->'commercial_lines')
  loop
    if not public.jsonb_has_exact_keys(v_line_input, array[
      'rule_id', 'quantity', 'description_context'
    ]) or nullif(btrim(v_line_input->>'rule_id'), '') is null
       or not public.is_jsonb_positive_number(v_line_input->'quantity')
       or nullif(btrim(v_line_input->>'description_context'), '') is null then
      raise exception using errcode = '22023', message = 'COMMERCIAL_LINE_INPUT_INVALID';
    end if;
    select count(*), min(rule.value::text)::jsonb into v_rule_count, v_rule
    from jsonb_array_elements(v_snapshot.calculation->'appliedRules') as rule(value)
    where rule.value->>'ruleId' = v_line_input->>'rule_id';
    if v_rule_count <> 1 then
      raise exception using errcode = 'P0001', message = 'PRICING_RULE_NOT_FOUND';
    end if;
    if upper(v_rule->>'mode') <> v_policy.exact_pricing_mode then
      raise exception using errcode = 'P0001', message = 'PRICING_RULE_NOT_EXACT';
    end if;
    if not public.is_jsonb_nonnegative_integer(v_rule->'amountMinor')
       or not public.is_jsonb_positive_number(v_rule->'quantity')
       or (v_rule->>'quantity')::numeric <> (v_line_input->>'quantity')::numeric then
      raise exception using errcode = 'P0001', message = 'PRICING_RULE_QUANTITY_MISMATCH';
    end if;
    if exists (
      select 1 from jsonb_array_elements(v_lines) as existing(value)
      where existing.value->>'product_or_service_code' = v_line_input->>'rule_id'
    ) then
      raise exception using errcode = '22023', message = 'COMMERCIAL_LINE_DUPLICATE';
    end if;
    v_sequence := v_sequence + 1;
    v_quantity := (v_line_input->>'quantity')::numeric;
    v_unit_minor := (v_rule->>'amountMinor')::bigint;
    v_gross_minor := trunc(v_quantity * v_unit_minor)::bigint;
    if (v_rule->>'knownMinimumContributionMinor')::bigint <> v_gross_minor then
      raise exception using errcode = 'P0001', message = 'PRICING_RULE_AMOUNT_MISMATCH';
    end if;
    v_line_discount := least(v_discount_remaining, v_gross_minor);
    v_discount_remaining := v_discount_remaining - v_line_discount;
    v_one_time_minor := v_one_time_minor + v_gross_minor - v_line_discount;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'line_id', 'pricing-rule:' || (v_line_input->>'rule_id'),
      'sequence', v_sequence,
      'product_or_service_code', v_line_input->>'rule_id',
      'description', v_line_input->>'description_context',
      'quantity', v_quantity,
      'unit', 'item',
      'unit_price_minor', v_unit_minor,
      'discount_minor', v_line_discount,
      'vat_treatment', v_vat.vat_treatment,
      'vat_rate', v_vat.vat_rate,
      'line_net_amount_minor', v_gross_minor - v_line_discount,
      'cost_type', 'ONE_TIME'
    ));
  end loop;
  if v_discount_remaining <> 0 then
    raise exception using errcode = '22023', message = 'DISCOUNT_EXCEEDS_TOTAL';
  end if;

  v_identity_base := jsonb_build_object(
    'source_quote_request_id', v_request.id,
    'source_intake_id', v_intake.id,
    'customer_id', null,
    'legal_name', coalesce(nullif(btrim(v_request.company), ''), v_request.name),
    'contact_name', v_request.name,
    'email', v_request.email,
    'address_line_1', v_request.billing_address,
    'address_line_2', null,
    'postal_code', v_request.billing_postal_code,
    'city', v_request.billing_city,
    'country_code', upper(v_request.billing_country),
    'enterprise_number', v_request.enterprise_number,
    'vat_number', v_request.vat_number,
    'source_fields', jsonb_build_object(
      'legal_name', case when nullif(btrim(v_request.company), '') is null then 'quote_requests.name' else 'quote_requests.company' end,
      'address', 'quote_requests.billing_address'
    )
  );
  v_customer := v_identity_base || jsonb_build_object(
    'snapshot_sha256', encode(extensions.digest(convert_to(v_identity_base::text, 'UTF8'), 'sha256'), 'hex')
  );

  if not public.jsonb_has_exact_keys(p_input->'scope', array[
    'project_title', 'project_type', 'scope_summary', 'requested_languages',
    'included_page_count', 'features', 'copywriting', 'seo', 'hosting',
    'maintenance', 'exclusions', 'assumptions', 'indicative_timing'
  ]) then
    raise exception using errcode = '22023', message = 'PROJECT_SCOPE_INVALID';
  end if;
  v_scope_base := jsonb_build_object(
    'project_id', null,
    'project_title', p_input->'scope'->'project_title',
    'project_type', p_input->'scope'->'project_type',
    'scope_summary', p_input->'scope'->'scope_summary',
    'requested_languages', p_input->'scope'->'requested_languages',
    'included_page_count', p_input->'scope'->'included_page_count',
    'features', p_input->'scope'->'features',
    'copywriting', p_input->'scope'->'copywriting',
    'seo', p_input->'scope'->'seo',
    'hosting', p_input->'scope'->'hosting',
    'maintenance', p_input->'scope'->'maintenance',
    'exclusions', p_input->'scope'->'exclusions',
    'assumptions', p_input->'scope'->'assumptions',
    'indicative_timing', p_input->'scope'->'indicative_timing',
    'source_intake_id', v_intake.id,
    'source_pricing_snapshot_id', v_snapshot.id
  );
  v_scope := v_scope_base || jsonb_build_object(
    'snapshot_sha256', encode(extensions.digest(convert_to(v_scope_base::text, 'UTF8'), 'sha256'), 'hex')
  );

  if p_input->'validity_days' = 'null'::jsonb then
    v_validity_days := v_policy.default_validity_days;
  elsif public.is_jsonb_nonnegative_integer(p_input->'validity_days')
      and (p_input->>'validity_days')::integer > 0 then
    v_validity_days := (p_input->>'validity_days')::integer;
  else
    raise exception using errcode = '22023', message = 'VALIDITY_DAYS_INVALID';
  end if;
  if v_validity_days > 365 then
    raise exception using errcode = '22023', message = 'VALIDITY_DAYS_INVALID';
  end if;

  if not public.jsonb_has_exact_keys(p_input->'payment_schedule', array['milestones']) then
    raise exception using errcode = '22023', message = 'PAYMENT_SCHEDULE_INVALID';
  end if;
  v_schedule := jsonb_build_object(
    'schedule_id', 'quotation-payment-v1-' || substr(v_request_fingerprint, 1, 16),
    'milestones', p_input->'payment_schedule'->'milestones',
    'approved_by', v_actor,
    'approved_at', to_char(v_now at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  );
  if not public.is_valid_quotation_payment_schedule_v1(v_schedule, v_one_time_minor, true) then
    raise exception using errcode = '22023', message = 'PAYMENT_SCHEDULE_INVALID';
  end if;

  v_vat_minor := round(v_one_time_minor::numeric * v_vat.vat_rate / 100)::bigint;
  v_payload := jsonb_build_object(
    'contract_version', 1,
    'source_quote_request_id', v_request.id,
    'source_intake_id', v_intake.id,
    'pricing_snapshot', v_pricing_reference,
    'currency', 'EUR',
    'line_items', v_lines,
    'totals', jsonb_build_object(
      'one_time_subtotal_minor', v_one_time_minor,
      'recurring_subtotal_minor', 0,
      'discount_total_minor', v_discount_minor,
      'vat_base_minor', v_one_time_minor,
      'vat_amount_minor', v_vat_minor,
      'total_gross_minor', v_one_time_minor + v_vat_minor
    ),
    'discount', jsonb_build_object(
      'discount_type', case when v_discount_minor = 0 then null else p_input->'discount'->'discount_type' end,
      'discount_value_minor', v_discount_minor,
      'discount_reason', case when v_discount_minor = 0 then null else p_input->'discount'->'discount_reason' end,
      'approved_by', case when v_discount_minor = 0 then null else to_jsonb(v_actor) end,
      'approved_at', case when v_discount_minor = 0 then null else to_jsonb(to_char(v_now at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')) end
    ),
    'customer_identity', v_customer,
    'project_scope', v_scope,
    'vat_approval', jsonb_build_object(
      'vat_treatment', v_vat.vat_treatment,
      'vat_rate', v_vat.vat_rate,
      'vat_decision_source', v_vat.authority_source_identifier,
      'vat_approved_by', v_actor,
      'vat_approved_at', to_char(v_now at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    ),
    'payment_schedule', v_schedule,
    'validity', jsonb_build_object(
      'valid_from', (v_now at time zone 'Europe/Brussels')::date,
      'valid_until', (v_now at time zone 'Europe/Brussels')::date + v_validity_days,
      'validity_days', v_validity_days,
      'approved_by', v_actor,
      'approved_at', to_char(v_now at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    ),
    'legal_references', jsonb_build_object(
      'terms_reference', v_terms.terms_id,
      'terms_version', v_terms.terms_version,
      'terms_sha256', rtrim(v_terms.terms_sha256),
      'terms_status', 'APPROVED',
      'agreement_template_reference', null,
      'agreement_template_version', null,
      'agreement_template_sha256', null
    )
  );
  if not public.is_valid_quotation_approval_payload_v1(v_payload, true) then
    raise exception using errcode = '22023', message = 'QUOTATION_BUSINESS_PAYLOAD_INVALID';
  end if;
  perform lws_internal.assert_quotation_frozen_rule_coverage_v1(
    v_snapshot.calculation,
    p_input->'commercial_lines'
  );
  v_payload_sha256 := public.quotation_approval_payload_sha256_v1(v_payload);

  select * into strict v_approval_draft from public.upsert_quotation_approval_draft_v1(
    v_request.id, v_intake.id, v_snapshot.id, v_payload,
    p_idempotency_key, v_intake.admin_access_token_hash, v_actor
  );
  v_result := jsonb_build_object(
    'approval_draft_id', v_approval_draft.draft_id,
    'business_revision', v_revision,
    'canonical_payload', v_payload,
    'canonical_payload_sha256', v_payload_sha256,
    'bindings', jsonb_build_object(
      'policy_authority_id', v_policy.policy_authority_id,
      'pricing_snapshot_id', v_snapshot.id,
      'seller_authority_id', v_seller.seller_authority_id,
      'seller_identity', v_seller.seller_identity,
      'template_authority_id', v_template.id,
      'template_id', v_template.template_id,
      'template_version', v_template.template_version,
      'template_sha256', lower(rtrim(v_template.template_sha256)),
      'terms_authority_id', v_terms.terms_authority_id,
      'vat_decision_authority_id', v_vat.vat_decision_authority_id
    ),
    'prepared_by_actor', v_actor,
    'prepared_at', v_now,
    'replayed', false
  );
  insert into public.quote_request_quotation_business_drafts (
    approval_draft_id, quote_request_id, intake_id, pricing_snapshot_id,
    business_revision, operator_id, seller_authority_id, terms_authority_id,
    vat_decision_authority_id, template_authority_id, policy_authority_id,
    canonical_payload, canonical_payload_sha256, request_fingerprint,
    idempotency_key, result_payload, prepared_by_actor, prepared_at
  ) values (
    v_approval_draft.draft_id, v_request.id, v_intake.id, v_snapshot.id,
    v_revision, v_operator.operator_id, v_seller.seller_authority_id,
    v_terms.terms_authority_id, v_vat.vat_decision_authority_id,
    v_template.id, v_policy.policy_authority_id, v_payload, v_payload_sha256,
    v_request_fingerprint, p_idempotency_key, v_result, v_actor, v_now
  );
  return v_result;
exception
  when invalid_text_representation then
    raise exception using errcode = '22023', message = 'QUOTATION_BUSINESS_INPUT_INVALID';
end;
$$;

alter table public.website_quotation_pricing_decisions enable row level security;
alter table public.website_quotation_pricing_decisions force row level security;
alter table public.website_quotation_pricing_decision_events enable row level security;
alter table public.website_quotation_pricing_decision_events force row level security;

revoke all privileges on public.website_quotation_pricing_decisions from public,anon,authenticated,service_role;
revoke all privileges on public.website_quotation_pricing_decision_events from public,anon,authenticated,service_role;
revoke all on function public.guard_website_quotation_pricing_decision_v1() from public,anon,authenticated,service_role;
revoke all on function public.website_pricing_snapshot_sha256_v1(uuid) from public,anon,service_role;
grant execute on function public.website_pricing_snapshot_sha256_v1(uuid) to authenticated;
revoke all on function public.get_operator_website_quotation_pricing_state_v1(uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.get_operator_website_quotation_pricing_state_v1(uuid,uuid,uuid) to authenticated;
revoke all on function public.authorize_website_quotation_pricing_decision_v1(uuid,uuid,uuid,uuid,text,text,bigint,text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.authorize_website_quotation_pricing_decision_v1(uuid,uuid,uuid,uuid,text,text,bigint,text,uuid) to authenticated;
revoke all on function lws_internal.resolve_website_quotation_calculation_v1(uuid,uuid,uuid,jsonb) from public,anon,authenticated,service_role;

comment on table public.website_quotation_pricing_decisions is
  'Immutable owner-approved exact Website quotation amount bound to one submitted pricing snapshot; never rewrites intake pricing evidence.';
comment on table public.website_quotation_pricing_decision_events is
  'Immutable pre-project audit event for a Website quotation pricing decision.';
comment on function public.authorize_website_quotation_pricing_decision_v1(uuid,uuid,uuid,uuid,text,text,bigint,text,uuid) is
  'AAL2 owner-only command that resolves one Website FROM/package-floor rule to an exact amount at or above its immutable floor.';

commit;
