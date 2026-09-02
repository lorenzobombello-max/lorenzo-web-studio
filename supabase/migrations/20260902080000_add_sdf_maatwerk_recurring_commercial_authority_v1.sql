alter table public.sdf_quotation_commercial_decisions
  drop constraint sdf_quotation_commercial_decisions_sdf_package_check;
alter table public.sdf_quotation_commercial_decisions
  add constraint sdf_quotation_commercial_decisions_sdf_package_check
  check (sdf_package in ('start','groei','pro','maatwerk'));

alter table public.sdf_accepted_commercial_terms
  add column accepted_recurring_amount_minor bigint
    check (accepted_recurring_amount_minor > 0),
  add column pricing_mode text
    check (pricing_mode in ('fixed','manual')),
  add column commercial_decision_id uuid unique
    references public.sdf_quotation_commercial_decisions(decision_id) on delete restrict,
  add column commercial_decision_sha256 char(64)
    check (commercial_decision_sha256 ~ '^[0-9a-f]{64}$');

create or replace function public.guard_sdf_accepted_commercial_terms_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_quote_request_id uuid;
  v_request_kind text;
  v_sdf_package text;
  v_pricing jsonb;
  v_canonical_amount bigint;
  v_decision public.sdf_quotation_commercial_decisions%rowtype;
begin
  if tg_op in ('UPDATE','DELETE') then
    raise exception using errcode = '55000', message = 'SDF_ACCEPTED_TERMS_IMMUTABLE';
  end if;

  select quotation.quote_request_id, request.request_kind, request.sdf_package
  into v_quote_request_id, v_request_kind, v_sdf_package
  from public.sdf_quotation_acceptances as acceptance
  join public.sdf_quotations as quotation on quotation.quotation_id = acceptance.quotation_id
  join public.quote_requests as request on request.id = quotation.quote_request_id
  where acceptance.quotation_id = new.quotation_id;

  if not found then
    raise exception using errcode = '23503', message = 'SDF_QUOTATION_ACCEPTANCE_REQUIRED';
  end if;
  if v_request_kind <> 'slimme_documentenflow' then
    raise exception using errcode = '23514', message = 'SDF_FINANCIAL_AUTHORITY_REQUIRES_SDF';
  end if;
  if v_sdf_package is null then
    raise exception using errcode = '23514', message = 'SDF_ACCEPTED_PACKAGE_REQUIRED';
  end if;
  if new.quote_request_id <> v_quote_request_id or new.sdf_package <> v_sdf_package then
    raise exception using errcode = '23514', message = 'SDF_ACCEPTED_TERMS_LINKAGE_MISMATCH';
  end if;

  v_pricing := public.get_sdf_package_pricing_authority_v1(v_sdf_package);
  v_canonical_amount := (v_pricing->'implementation'->>'amount_minor')::bigint;
  if new.currency <> v_pricing->>'currency'
     or new.vat_basis <> v_pricing->>'vat_basis'
     or new.pricing_authority_version <> (v_pricing->>'authority_version')::smallint then
    raise exception using errcode = '23514', message = 'SDF_PRICING_PROVENANCE_MISMATCH';
  end if;
  if v_sdf_package in ('start','groei','pro')
     and new.accepted_implementation_amount_minor <> v_canonical_amount then
    raise exception using errcode = '23514', message = 'SDF_ACCEPTED_AMOUNT_MISMATCH';
  end if;
  if v_sdf_package = 'maatwerk'
     and new.accepted_implementation_amount_minor < v_canonical_amount then
    raise exception using errcode = '23514', message = 'SDF_ACCEPTED_AMOUNT_BELOW_AUTHORITY_MINIMUM';
  end if;
  if mod(new.accepted_implementation_amount_minor,5) <> 0 then
    raise exception using errcode = '23514', message = 'SDF_MILESTONE_ONE_MINOR_UNIT_INEXACT';
  end if;

  if v_sdf_package = 'maatwerk' then
    if new.accepted_recurring_amount_minor is null
       or new.pricing_mode <> 'manual'
       or new.commercial_decision_id is null
       or new.commercial_decision_sha256 is null then
      raise exception using errcode = '23514', message = 'SDF_MAATWERK_COMMERCIAL_PROVENANCE_REQUIRED';
    end if;
    select * into v_decision
    from public.sdf_quotation_commercial_decisions
    where decision_id = new.commercial_decision_id;
    if not found
       or v_decision.quote_request_id <> new.quote_request_id
       or v_decision.quotation_id <> new.quotation_id
       or v_decision.sdf_package <> new.sdf_package
       or (v_decision.canonical_payload->>'implementation_amount_minor')::bigint
          <> new.accepted_implementation_amount_minor
       or (v_decision.canonical_payload->>'recurring_amount_minor')::bigint
          <> new.accepted_recurring_amount_minor
       or v_decision.canonical_payload->>'currency' <> new.currency
       or rtrim(v_decision.decision_sha256) <> rtrim(new.commercial_decision_sha256)
       or rtrim(v_decision.decision_sha256) <>
          encode(extensions.digest(convert_to(v_decision.canonical_payload::text,'UTF8'),'sha256'),'hex') then
      raise exception using errcode = '23514', message = 'SDF_MAATWERK_COMMERCIAL_PROVENANCE_MISMATCH';
    end if;
  end if;
  return new;
end;
$$;

create function public.authorize_sdf_quotation_commercial_decision_v1(
  p_quote_request_id uuid,
  p_preparation_authority_id uuid,
  p_vat_decision_authority_id uuid,
  p_terms_authority_id uuid,
  p_implementation_amount_minor bigint,
  p_recurring_amount_minor bigint,
  p_payment_schedule jsonb,
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
  v_preparation public.sdf_quotation_preparation_authorities%rowtype;
  v_intake public.sdf_qualification_intakes%rowtype;
  v_submission public.sdf_qualification_intake_submissions%rowtype;
  v_completion public.sdf_qualification_intake_events%rowtype;
  v_vat public.quotation_vat_decision_authorities%rowtype;
  v_terms public.quotation_terms_authorities%rowtype;
  v_existing public.sdf_quotation_commercial_decisions%rowtype;
  v_binding jsonb;
  v_pricing jsonb;
  v_completeness jsonb;
  v_vat_context jsonb;
  v_schedule jsonb;
  v_canonical jsonb;
  v_package text;
  v_submission_hash text;
  v_pricing_hash text;
  v_document_hash text;
  v_decision_hash text;
  v_request_fingerprint text;
  v_now timestamptz := clock_timestamp();
  v_vat_resolution_date date;
  v_actor text;
begin
  if p_quote_request_id is null or p_preparation_authority_id is null
     or p_vat_decision_authority_id is null or p_terms_authority_id is null
     or p_idempotency_key is null
     or not public.jsonb_has_exact_keys(p_payment_schedule,array['milestones']) then
    raise exception using errcode = '22023', message = 'SDF_COMMERCIAL_DECISION_INPUT_INVALID';
  end if;
  if p_implementation_amount_minor is null then
    raise exception using errcode = '22004', message = 'SDF_MAATWERK_IMPLEMENTATION_AMOUNT_REQUIRED';
  end if;
  if p_recurring_amount_minor is null then
    raise exception using errcode = '22004', message = 'SDF_MAATWERK_RECURRING_AMOUNT_REQUIRED';
  end if;
  if p_implementation_amount_minor <= 0 then
    raise exception using errcode = '22023', message = 'SDF_MAATWERK_IMPLEMENTATION_AMOUNT_INVALID';
  end if;
  if p_recurring_amount_minor <= 0 then
    raise exception using errcode = '22023', message = 'SDF_MAATWERK_RECURRING_AMOUNT_INVALID';
  end if;

  v_operator := lws_internal.assert_sdf_owner_v1();
  v_actor := 'OPERATOR:' || v_operator.operator_id::text;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_preparation_authority_id::text,0));

  select * into v_preparation
  from public.sdf_quotation_preparation_authorities
  where authority_id = p_preparation_authority_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'SDF_QUOTATION_PREPARATION_NOT_FOUND';
  end if;
  if v_preparation.quote_request_id is distinct from p_quote_request_id then
    raise exception using errcode = '42501', message = 'SDF_COMMERCIAL_DECISION_CROSS_DOSSIER';
  end if;
  if v_preparation.sdf_package <> 'maatwerk' then
    raise exception using errcode = '23514', message = 'SDF_FIXED_PRICING_OVERRIDE_DENIED';
  end if;
  if v_preparation.taxonomy_version <> 'sdf_qualification_intake/3.0.0'
     or v_preparation.document_evidence_sha256 is null then
    raise exception using errcode = '55000', message = 'SDF_V3_QUOTATION_PREPARATION_REQUIRED';
  end if;

  select * into strict v_intake
  from public.sdf_qualification_intakes
  where intake_id = v_preparation.qualification_intake_id
    and quote_request_id = p_quote_request_id
    and status = 'qualification_complete';
  select * into strict v_submission
  from public.sdf_qualification_intake_submissions
  where intake_id = v_intake.intake_id
    and submission_sequence = v_preparation.submission_sequence;
  select * into strict v_completion
  from public.sdf_qualification_intake_events
  where event_id = v_preparation.completion_event_id
    and intake_id = v_intake.intake_id
    and event_kind = 'QUALIFICATION_COMPLETE'
    and submission_sequence = v_submission.submission_sequence;

  v_submission_hash := encode(extensions.digest(convert_to(v_submission.answers::text,'UTF8'),'sha256'),'hex');
  if v_submission_hash <> rtrim(v_submission.payload_sha256)
     or v_submission_hash <> rtrim(v_preparation.submission_sha256)
     or v_submission.taxonomy_version <> v_preparation.taxonomy_version
     or v_intake.latest_submission_sequence <> v_submission.submission_sequence then
    raise exception using errcode = '55000', message = 'SDF_QUALIFICATION_INTEGRITY_MISMATCH';
  end if;

  v_binding := lws_internal.get_sdf_budget_guard_quotation_binding_v1(v_submission.answers);
  v_package := v_binding->>'package';
  v_pricing := v_binding->'pricing';
  v_pricing_hash := encode(extensions.digest(convert_to(v_pricing::text,'UTF8'),'sha256'),'hex');
  if v_package <> 'maatwerk'
     or v_package <> v_preparation.sdf_package
     or (v_pricing->>'authority_version')::integer <> v_preparation.pricing_authority_version
     or v_pricing_hash <> rtrim(v_preparation.pricing_authority_sha256) then
    raise exception using errcode = '55000', message = 'SDF_PRICING_AUTHORITY_MISMATCH';
  end if;

  v_completeness := lws_internal.evaluate_sdf_document_completeness_v1(p_quote_request_id);
  v_document_hash := v_completeness->>'evidence_sha256';
  if (v_completeness->>'is_complete')::boolean is distinct from true
     or v_document_hash <> rtrim(v_preparation.document_evidence_sha256) then
    raise exception using errcode = '55000', message = 'SDF_DOCUMENT_EVIDENCE_MISMATCH';
  end if;

  select * into v_vat
  from public.quotation_vat_decision_authorities
  where vat_decision_authority_id = p_vat_decision_authority_id and status = 'APPROVED';
  if not found then
    raise exception using errcode = 'P0001', message = 'QUOTATION_VAT_DECISION_NOT_APPROVED';
  end if;
  v_vat_resolution_date := (v_now at time zone 'UTC')::date;
  v_vat_context := public.resolve_quotation_vat_authority_v1(p_quote_request_id,v_vat_resolution_date);
  if not public.is_sdf_vat_context_binding_valid_v1(p_vat_decision_authority_id,v_vat_context) then
    raise exception using errcode = '55000', message = 'SDF_VAT_AUTHORITY_CONTEXT_MISMATCH';
  end if;
  select * into v_terms
  from public.quotation_terms_authorities
  where terms_authority_id = p_terms_authority_id and status = 'APPROVED';
  if not found then
    raise exception using errcode = 'P0001', message = 'QUOTATION_TERMS_NOT_APPROVED';
  end if;

  v_request_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'authorityVersion',1,
    'quoteRequestId',p_quote_request_id,
    'preparationAuthorityId',p_preparation_authority_id,
    'preparationFingerprint',rtrim(v_preparation.request_fingerprint),
    'submissionSha256',v_submission_hash,
    'pricingAuthoritySha256',v_pricing_hash,
    'documentEvidenceSha256',v_document_hash,
    'implementationAmountMinor',p_implementation_amount_minor,
    'recurringAmountMinor',p_recurring_amount_minor,
    'currency','EUR',
    'vatDecisionAuthorityId',p_vat_decision_authority_id,
    'vatResolutionDate',v_vat_resolution_date,
    'vatContextSha256',v_vat_context->>'context_sha256',
    'vatClassificationId',v_vat_context->>'classification_id',
    'vatTurnoverSnapshotId',v_vat_context->>'turnover_snapshot_id',
    'termsAuthorityId',p_terms_authority_id,
    'paymentMilestones',p_payment_schedule->'milestones'
  )::text,'UTF8'),'sha256'),'hex');

  select * into v_existing
  from public.sdf_quotation_commercial_decisions
  where idempotency_key = p_idempotency_key;
  if found then
    if rtrim(v_existing.request_fingerprint) <> v_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'decision_id',v_existing.decision_id,
      'quote_request_id',v_existing.quote_request_id,
      'preparation_authority_id',v_existing.preparation_authority_id,
      'decision_sha256',rtrim(v_existing.decision_sha256),
      'status','SDF_COMMERCIAL_DECISION_AUTHORIZED',
      'replayed',true
    );
  end if;
  if exists (
    select 1 from public.sdf_quotation_commercial_decisions
    where preparation_authority_id = p_preparation_authority_id
  ) then
    raise exception using errcode = '55000', message = 'SDF_COMMERCIAL_DECISION_ALREADY_EXISTS';
  end if;

  v_schedule := jsonb_build_object(
    'schedule_id','sdf-commercial-decision:' || p_preparation_authority_id::text,
    'milestones',p_payment_schedule->'milestones',
    'approved_by',v_actor,
    'approved_at',to_char(v_now at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  );
  if not public.is_valid_quotation_payment_schedule_v1(v_schedule,p_implementation_amount_minor,true) then
    raise exception using errcode = '22023', message = 'PAYMENT_SCHEDULE_INVALID';
  end if;

  v_canonical := jsonb_build_object(
    'authority_version',1,
    'quote_request_id',p_quote_request_id,
    'preparation_authority_id',p_preparation_authority_id,
    'quotation_id',v_preparation.quotation_id,
    'submission_sha256',v_submission_hash,
    'pricing_authority_version',v_preparation.pricing_authority_version,
    'pricing_authority_sha256',v_pricing_hash,
    'document_evidence_sha256',v_document_hash,
    'sdf_package','maatwerk',
    'implementation_amount_minor',p_implementation_amount_minor,
    'recurring_amount_minor',p_recurring_amount_minor,
    'currency','EUR',
    'vat_decision_authority_id',p_vat_decision_authority_id,
    'vat_resolution_date',v_vat_resolution_date,
    'vat_context_sha256',v_vat_context->>'context_sha256',
    'vat_classification_id',v_vat_context->>'classification_id',
    'vat_turnover_snapshot_id',v_vat_context->>'turnover_snapshot_id',
    'terms_authority_id',p_terms_authority_id,
    'payment_schedule',v_schedule
  );
  v_decision_hash := encode(extensions.digest(convert_to(v_canonical::text,'UTF8'),'sha256'),'hex');

  insert into public.sdf_quotation_commercial_decisions(
    quote_request_id,preparation_authority_id,quotation_id,
    vat_decision_authority_id,vat_resolution_date,vat_context_sha256,
    vat_classification_id,vat_turnover_snapshot_id,terms_authority_id,sdf_package,
    pricing_authority_version,pricing_authority_sha256,submission_sha256,
    document_evidence_sha256,payment_schedule,canonical_payload,
    decision_sha256,actor_operator_id,actor_role,decided_at,
    idempotency_key,request_fingerprint
  ) values (
    p_quote_request_id,p_preparation_authority_id,v_preparation.quotation_id,
    p_vat_decision_authority_id,v_vat_resolution_date,v_vat_context->>'context_sha256',
    (v_vat_context->>'classification_id')::uuid,(v_vat_context->>'turnover_snapshot_id')::uuid,
    p_terms_authority_id,'maatwerk',v_preparation.pricing_authority_version,
    v_pricing_hash,v_submission_hash,v_document_hash,v_schedule,v_canonical,
    v_decision_hash,v_operator.operator_id,'owner',v_now,p_idempotency_key,v_request_fingerprint
  ) returning * into v_existing;

  return jsonb_build_object(
    'decision_id',v_existing.decision_id,
    'quote_request_id',v_existing.quote_request_id,
    'preparation_authority_id',v_existing.preparation_authority_id,
    'decision_sha256',rtrim(v_existing.decision_sha256),
    'status','SDF_COMMERCIAL_DECISION_AUTHORIZED',
    'replayed',false
  );
exception
  when no_data_found then
    raise exception using errcode = '55000', message = 'SDF_QUOTATION_PREPARATION_STALE';
end;
$$;

create function public.create_sdf_milestone_one_foundation_v2(
  p_quotation_id uuid,
  p_commercial_decision_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, extensions, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_decision public.sdf_quotation_commercial_decisions%rowtype;
  v_existing public.sdf_accepted_commercial_terms%rowtype;
  v_terms public.sdf_accepted_commercial_terms%rowtype;
  v_obligation public.sdf_milestone_one_obligations%rowtype;
  v_implementation_amount_minor bigint;
  v_recurring_amount_minor bigint;
  v_fingerprint text;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner','admin') then
    raise exception using errcode = '42501', message = 'SDF_FINANCIAL_AUTHORITY_DENIED';
  end if;
  if p_quotation_id is null or p_commercial_decision_id is null or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'SDF_ACCEPTED_COMMERCIAL_AUTHORITY_INPUT_INVALID';
  end if;

  select * into v_decision
  from public.sdf_quotation_commercial_decisions
  where decision_id = p_commercial_decision_id;
  if not found then
    raise exception using errcode = '23503', message = 'SDF_COMMERCIAL_DECISION_REQUIRED';
  end if;
  if v_decision.quotation_id <> p_quotation_id or v_decision.sdf_package <> 'maatwerk' then
    raise exception using errcode = '23514', message = 'SDF_COMMERCIAL_DECISION_LINKAGE_MISMATCH';
  end if;
  if rtrim(v_decision.decision_sha256) <>
     encode(extensions.digest(convert_to(v_decision.canonical_payload::text,'UTF8'),'sha256'),'hex') then
    raise exception using errcode = '55000', message = 'SDF_COMMERCIAL_DECISION_INTEGRITY_MISMATCH';
  end if;
  v_implementation_amount_minor := (v_decision.canonical_payload->>'implementation_amount_minor')::bigint;
  v_recurring_amount_minor := (v_decision.canonical_payload->>'recurring_amount_minor')::bigint;
  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'commercialDecisionId',v_decision.decision_id,
    'commercialDecisionSha256',rtrim(v_decision.decision_sha256),
    'implementationAmountMinor',v_implementation_amount_minor,
    'recurringAmountMinor',v_recurring_amount_minor,
    'currency',v_decision.canonical_payload->>'currency',
    'quotationId',p_quotation_id
  )::text,'UTF8'),'sha256'),'hex');

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  select * into v_existing
  from public.sdf_accepted_commercial_terms
  where creation_idempotency_key = p_idempotency_key;
  if found then
    if rtrim(v_existing.creation_fingerprint) <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    select * into strict v_obligation
    from public.sdf_milestone_one_obligations
    where accepted_terms_id = v_existing.accepted_terms_id;
    return jsonb_build_object(
      'accepted_terms_id',v_existing.accepted_terms_id,
      'obligation_id',v_obligation.obligation_id,
      'quotation_id',v_existing.quotation_id,
      'was_created',false
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_quotation_id::text,0));
  select * into v_existing
  from public.sdf_accepted_commercial_terms
  where quotation_id = p_quotation_id;
  if found then
    if rtrim(v_existing.creation_fingerprint) <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'SDF_ACCEPTED_TERMS_CONFLICT';
    end if;
    select * into strict v_obligation
    from public.sdf_milestone_one_obligations
    where accepted_terms_id = v_existing.accepted_terms_id;
    return jsonb_build_object(
      'accepted_terms_id',v_existing.accepted_terms_id,
      'obligation_id',v_obligation.obligation_id,
      'quotation_id',v_existing.quotation_id,
      'was_created',false
    );
  end if;

  if not exists (
    select 1 from public.sdf_quotation_acceptances
    where quotation_id = p_quotation_id
  ) then
    raise exception using errcode = '23503', message = 'SDF_QUOTATION_ACCEPTANCE_REQUIRED';
  end if;

  update public.quote_requests
  set sdf_package = v_decision.sdf_package
  where id = v_decision.quote_request_id
    and sdf_package is distinct from v_decision.sdf_package;

  insert into public.sdf_accepted_commercial_terms(
    quotation_id,quote_request_id,sdf_package,
    accepted_implementation_amount_minor,accepted_recurring_amount_minor,
    currency,vat_basis,pricing_authority_version,pricing_mode,
    commercial_decision_id,commercial_decision_sha256,
    creation_idempotency_key,creation_fingerprint,created_by_operator_id
  ) values (
    p_quotation_id,v_decision.quote_request_id,'maatwerk',
    v_implementation_amount_minor,v_recurring_amount_minor,
    v_decision.canonical_payload->>'currency','exclusive',1,'manual',
    v_decision.decision_id,rtrim(v_decision.decision_sha256),
    p_idempotency_key,v_fingerprint,v_operator.operator_id
  ) returning * into v_terms;

  insert into public.sdf_milestone_one_obligations(
    quotation_id,accepted_terms_id,milestone_identity,percentage_basis_points,
    amount_minor,currency,vat_basis,obligation_state,obligation_origin
  ) values (
    v_terms.quotation_id,v_terms.accepted_terms_id,'M1',4000,
    ((v_terms.accepted_implementation_amount_minor::numeric*4000)/10000)::bigint,
    v_terms.currency,v_terms.vat_basis,'EXPECTED','QUOTATION_ACCEPTANCE'
  ) returning * into v_obligation;

  return jsonb_build_object(
    'accepted_terms_id',v_terms.accepted_terms_id,
    'obligation_id',v_obligation.obligation_id,
    'quotation_id',v_terms.quotation_id,
    'was_created',true
  );
end;
$$;

revoke all on function public.authorize_sdf_quotation_commercial_decision_v1(
  uuid,uuid,uuid,uuid,bigint,bigint,jsonb,uuid
) from public,anon,authenticated,service_role;
grant execute on function public.authorize_sdf_quotation_commercial_decision_v1(
  uuid,uuid,uuid,uuid,bigint,bigint,jsonb,uuid
) to authenticated;
revoke all on function public.create_sdf_milestone_one_foundation_v2(uuid,uuid,uuid)
from public,anon,authenticated,service_role;
grant execute on function public.create_sdf_milestone_one_foundation_v2(uuid,uuid,uuid)
to authenticated;

comment on function public.authorize_sdf_quotation_commercial_decision_v1(
  uuid,uuid,uuid,uuid,bigint,bigint,jsonb,uuid
) is 'Owner-only MAATWERK overload binding explicit positive implementation and monthly recurring amounts into the existing immutable commercial decision ledger. Creates no obligation, invoice, period, due date, or scheduler evidence.';
comment on function public.create_sdf_milestone_one_foundation_v2(uuid,uuid,uuid) is
  'Owner/admin accepted-terms binding for an accepted MAATWERK quotation. Copies exact amounts and immutable decision provenance; creates M1 only and no recurring billing obligation.';