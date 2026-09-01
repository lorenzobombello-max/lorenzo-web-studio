create table public.sdf_quotation_commercial_decisions (
  decision_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null unique references public.quote_requests(id) on delete restrict,
  preparation_authority_id uuid not null unique references public.sdf_quotation_preparation_authorities(authority_id) on delete restrict,
  quotation_id uuid not null unique references public.sdf_quotations(quotation_id) on delete restrict,
  vat_decision_authority_id uuid not null references public.quotation_vat_decision_authorities(vat_decision_authority_id) on delete restrict,
  vat_resolution_date date not null,
  vat_context_sha256 char(64) not null check (vat_context_sha256 ~ '^[0-9a-f]{64}$'),
  vat_classification_id uuid not null references public.quotation_vat_transaction_classifications(classification_id) on delete restrict,
  vat_turnover_snapshot_id uuid not null references public.quotation_vat_turnover_snapshots(turnover_snapshot_id) on delete restrict,
  terms_authority_id uuid not null references public.quotation_terms_authorities(terms_authority_id) on delete restrict,
  sdf_package text not null check (sdf_package in ('start', 'groei', 'pro')),
  pricing_authority_version integer not null check (pricing_authority_version > 0),
  pricing_authority_sha256 char(64) not null check (pricing_authority_sha256 ~ '^[0-9a-f]{64}$'),
  submission_sha256 char(64) not null check (submission_sha256 ~ '^[0-9a-f]{64}$'),
  document_evidence_sha256 char(64) not null check (document_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  payment_schedule jsonb not null,
  canonical_payload jsonb not null,
  decision_sha256 char(64) not null check (decision_sha256 ~ '^[0-9a-f]{64}$'),
  actor_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  actor_role text not null check (actor_role = 'owner'),
  decided_at timestamptz not null,
  idempotency_key uuid not null unique,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint sdf_quotation_commercial_decision_schedule_valid
    check (public.is_valid_quotation_payment_schedule_v1(payment_schedule, (canonical_payload->>'implementation_amount_minor')::bigint, true)),
  constraint sdf_quotation_commercial_decision_payload_valid check (
    public.jsonb_has_exact_keys(canonical_payload, array[
      'authority_version', 'quote_request_id', 'preparation_authority_id', 'quotation_id',
      'submission_sha256', 'pricing_authority_version', 'pricing_authority_sha256',
      'document_evidence_sha256', 'sdf_package', 'implementation_amount_minor',
      'recurring_amount_minor', 'currency', 'vat_decision_authority_id',
      'vat_resolution_date', 'vat_context_sha256', 'vat_classification_id',
      'vat_turnover_snapshot_id',
      'terms_authority_id', 'payment_schedule'
    ])
    and canonical_payload->>'authority_version' = '1'
    and canonical_payload->>'quote_request_id' = quote_request_id::text
    and canonical_payload->>'preparation_authority_id' = preparation_authority_id::text
    and canonical_payload->>'quotation_id' = quotation_id::text
    and canonical_payload->>'submission_sha256' = rtrim(submission_sha256)
    and (canonical_payload->>'pricing_authority_version')::integer = pricing_authority_version
    and canonical_payload->>'pricing_authority_sha256' = rtrim(pricing_authority_sha256)
    and canonical_payload->>'document_evidence_sha256' = rtrim(document_evidence_sha256)
    and canonical_payload->>'sdf_package' = sdf_package
    and canonical_payload->>'currency' = 'EUR'
    and canonical_payload->>'vat_decision_authority_id' = vat_decision_authority_id::text
    and (canonical_payload->>'vat_resolution_date')::date = vat_resolution_date
    and canonical_payload->>'vat_context_sha256' = rtrim(vat_context_sha256)
    and canonical_payload->>'vat_classification_id' = vat_classification_id::text
    and canonical_payload->>'vat_turnover_snapshot_id' = vat_turnover_snapshot_id::text
    and canonical_payload->>'terms_authority_id' = terms_authority_id::text
    and canonical_payload->'payment_schedule' = payment_schedule
    and decision_sha256 = encode(extensions.digest(convert_to(canonical_payload::text, 'UTF8'), 'sha256'), 'hex')
  )
);

create function public.guard_sdf_quotation_commercial_decision_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'SDF_COMMERCIAL_DECISION_IMMUTABLE';
end;
$$;

create trigger trg_sdf_quotation_commercial_decisions_immutable
before update or delete on public.sdf_quotation_commercial_decisions
for each row execute function public.guard_sdf_quotation_commercial_decision_v1();

create function public.is_sdf_vat_context_binding_valid_v1(
  p_vat_decision_authority_id uuid,
  p_resolved_context jsonb
)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_vat_decision_authority_id is not null
    and public.jsonb_has_exact_keys(p_resolved_context, array[
      'vat_decision_authority_id', 'authority_family', 'decision_code',
      'decision_version', 'authority_sha256', 'vat_treatment', 'rate_semantics',
      'vat_rate', 'invoice_literal', 'context_sha256', 'classification_id',
      'turnover_snapshot_id', 'applicable_threshold_minor', 'governed_turnover_minor'
    ])
    and (p_resolved_context->>'vat_decision_authority_id')::uuid
      = p_vat_decision_authority_id
    and p_resolved_context->>'context_sha256' ~ '^[0-9a-f]{64}$'
    and (p_resolved_context->>'classification_id') ~
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and (p_resolved_context->>'turnover_snapshot_id') ~
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
$$;

create function public.authorize_sdf_quotation_commercial_decision_v1(
  p_quote_request_id uuid,
  p_preparation_authority_id uuid,
  p_vat_decision_authority_id uuid,
  p_terms_authority_id uuid,
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
  v_implementation_minor bigint;
  v_recurring_minor bigint;
  v_now timestamptz := clock_timestamp();
  v_vat_resolution_date date;
  v_actor text;
begin
  if p_quote_request_id is null or p_preparation_authority_id is null
     or p_vat_decision_authority_id is null or p_terms_authority_id is null
     or p_idempotency_key is null or not public.jsonb_has_exact_keys(p_payment_schedule, array['milestones']) then
    raise exception using errcode = '22023', message = 'SDF_COMMERCIAL_DECISION_INPUT_INVALID';
  end if;

  v_operator := lws_internal.assert_sdf_owner_v1();
  v_actor := 'OPERATOR:' || v_operator.operator_id::text;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text, 0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_preparation_authority_id::text, 0));

  select * into v_preparation
  from public.sdf_quotation_preparation_authorities
  where authority_id = p_preparation_authority_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'SDF_QUOTATION_PREPARATION_NOT_FOUND';
  end if;
  if v_preparation.quote_request_id is distinct from p_quote_request_id then
    raise exception using errcode = '42501', message = 'SDF_COMMERCIAL_DECISION_CROSS_DOSSIER';
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

  v_submission_hash := encode(extensions.digest(convert_to(v_submission.answers::text, 'UTF8'), 'sha256'), 'hex');
  if v_submission_hash <> rtrim(v_submission.payload_sha256)
     or v_submission_hash <> rtrim(v_preparation.submission_sha256)
     or v_submission.taxonomy_version <> v_preparation.taxonomy_version
     or v_intake.latest_submission_sequence <> v_submission.submission_sequence then
    raise exception using errcode = '55000', message = 'SDF_QUALIFICATION_INTEGRITY_MISMATCH';
  end if;

  v_binding := lws_internal.get_sdf_budget_guard_quotation_binding_v1(v_submission.answers);
  v_package := v_binding->>'package';
  v_pricing := v_binding->'pricing';
  v_pricing_hash := encode(extensions.digest(convert_to(v_pricing::text, 'UTF8'), 'sha256'), 'hex');
  if v_package <> v_preparation.sdf_package
     or (v_pricing->>'authority_version')::integer <> v_preparation.pricing_authority_version
     or v_pricing_hash <> rtrim(v_preparation.pricing_authority_sha256) then
    raise exception using errcode = '55000', message = 'SDF_PRICING_AUTHORITY_MISMATCH';
  end if;
  if v_package = 'maatwerk' then
    raise exception using errcode = '55000', message = 'SDF_MANUAL_PRICING_REQUIRED';
  end if;

  v_implementation_minor := (v_pricing#>>'{implementation,amount_minor}')::bigint;
  v_recurring_minor := (v_pricing#>>'{recurring,amount_minor}')::bigint;

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
  v_vat_context := public.resolve_quotation_vat_authority_v1(
    p_quote_request_id, v_vat_resolution_date
  );
  if not public.is_sdf_vat_context_binding_valid_v1(
    p_vat_decision_authority_id, v_vat_context
  ) then
    raise exception using errcode = '55000', message = 'SDF_VAT_AUTHORITY_CONTEXT_MISMATCH';
  end if;
  select * into v_terms
  from public.quotation_terms_authorities
  where terms_authority_id = p_terms_authority_id and status = 'APPROVED';
  if not found then
    raise exception using errcode = 'P0001', message = 'QUOTATION_TERMS_NOT_APPROVED';
  end if;

  v_request_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'authorityVersion', 1,
    'quoteRequestId', p_quote_request_id,
    'preparationAuthorityId', p_preparation_authority_id,
    'preparationFingerprint', rtrim(v_preparation.request_fingerprint),
    'submissionSha256', v_submission_hash,
    'pricingAuthoritySha256', v_pricing_hash,
    'documentEvidenceSha256', v_document_hash,
    'vatDecisionAuthorityId', p_vat_decision_authority_id,
    'vatResolutionDate', v_vat_resolution_date,
    'vatContextSha256', v_vat_context->>'context_sha256',
    'vatClassificationId', v_vat_context->>'classification_id',
    'vatTurnoverSnapshotId', v_vat_context->>'turnover_snapshot_id',
    'termsAuthorityId', p_terms_authority_id,
    'paymentMilestones', p_payment_schedule->'milestones'
  )::text, 'UTF8'), 'sha256'), 'hex');

  select * into v_existing
  from public.sdf_quotation_commercial_decisions
  where idempotency_key = p_idempotency_key;
  if found then
    if rtrim(v_existing.request_fingerprint) <> v_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'decision_id', v_existing.decision_id,
      'quote_request_id', v_existing.quote_request_id,
      'preparation_authority_id', v_existing.preparation_authority_id,
      'decision_sha256', rtrim(v_existing.decision_sha256),
      'status', 'SDF_COMMERCIAL_DECISION_AUTHORIZED',
      'replayed', true
    );
  end if;
  if exists (
    select 1 from public.sdf_quotation_commercial_decisions
    where preparation_authority_id = p_preparation_authority_id
  ) then
    raise exception using errcode = '55000', message = 'SDF_COMMERCIAL_DECISION_ALREADY_EXISTS';
  end if;

  v_schedule := jsonb_build_object(
    'schedule_id', 'sdf-commercial-decision:' || p_preparation_authority_id::text,
    'milestones', p_payment_schedule->'milestones',
    'approved_by', v_actor,
    'approved_at', to_char(v_now at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  );
  if not public.is_valid_quotation_payment_schedule_v1(v_schedule, v_implementation_minor, true) then
    raise exception using errcode = '22023', message = 'PAYMENT_SCHEDULE_INVALID';
  end if;

  v_canonical := jsonb_build_object(
    'authority_version', 1,
    'quote_request_id', p_quote_request_id,
    'preparation_authority_id', p_preparation_authority_id,
    'quotation_id', v_preparation.quotation_id,
    'submission_sha256', v_submission_hash,
    'pricing_authority_version', v_preparation.pricing_authority_version,
    'pricing_authority_sha256', v_pricing_hash,
    'document_evidence_sha256', v_document_hash,
    'sdf_package', v_package,
    'implementation_amount_minor', v_implementation_minor,
    'recurring_amount_minor', v_recurring_minor,
    'currency', 'EUR',
    'vat_decision_authority_id', p_vat_decision_authority_id,
    'vat_resolution_date', v_vat_resolution_date,
    'vat_context_sha256', v_vat_context->>'context_sha256',
    'vat_classification_id', v_vat_context->>'classification_id',
    'vat_turnover_snapshot_id', v_vat_context->>'turnover_snapshot_id',
    'terms_authority_id', p_terms_authority_id,
    'payment_schedule', v_schedule
  );
  v_decision_hash := encode(extensions.digest(convert_to(v_canonical::text, 'UTF8'), 'sha256'), 'hex');

  insert into public.sdf_quotation_commercial_decisions (
    quote_request_id, preparation_authority_id, quotation_id,
    vat_decision_authority_id, vat_resolution_date, vat_context_sha256,
    vat_classification_id, vat_turnover_snapshot_id, terms_authority_id, sdf_package,
    pricing_authority_version, pricing_authority_sha256, submission_sha256,
    document_evidence_sha256, payment_schedule, canonical_payload,
    decision_sha256, actor_operator_id, actor_role, decided_at,
    idempotency_key, request_fingerprint
  ) values (
    p_quote_request_id, p_preparation_authority_id, v_preparation.quotation_id,
    p_vat_decision_authority_id, v_vat_resolution_date,
    v_vat_context->>'context_sha256', (v_vat_context->>'classification_id')::uuid,
    (v_vat_context->>'turnover_snapshot_id')::uuid, p_terms_authority_id, v_package,
    v_preparation.pricing_authority_version, v_pricing_hash, v_submission_hash,
    v_document_hash, v_schedule, v_canonical,
    v_decision_hash, v_operator.operator_id, 'owner', v_now,
    p_idempotency_key, v_request_fingerprint
  ) returning * into v_existing;

  return jsonb_build_object(
    'decision_id', v_existing.decision_id,
    'quote_request_id', v_existing.quote_request_id,
    'preparation_authority_id', v_existing.preparation_authority_id,
    'decision_sha256', rtrim(v_existing.decision_sha256),
    'status', 'SDF_COMMERCIAL_DECISION_AUTHORIZED',
    'replayed', false
  );
exception
  when no_data_found then
    raise exception using errcode = '55000', message = 'SDF_QUOTATION_PREPARATION_STALE';
end;
$$;

alter table public.sdf_quotation_commercial_decisions enable row level security;
alter table public.sdf_quotation_commercial_decisions force row level security;

revoke all privileges on table public.sdf_quotation_commercial_decisions
from public, anon, authenticated, service_role;
revoke all on function public.guard_sdf_quotation_commercial_decision_v1()
from public, anon, authenticated, service_role;
revoke all on function public.is_sdf_vat_context_binding_valid_v1(uuid, jsonb)
from public, anon, authenticated, service_role;
revoke all on function public.authorize_sdf_quotation_commercial_decision_v1(uuid, uuid, uuid, uuid, jsonb, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.authorize_sdf_quotation_commercial_decision_v1(uuid, uuid, uuid, uuid, jsonb, uuid)
to authenticated;

comment on table public.sdf_quotation_commercial_decisions is
  'Private immutable QF-2A owner authority binding one V3 SDF quotation preparation to resolved VAT context, approved terms, and an exact setup payment schedule. Creates no business draft, approval, issuance, delivery, or acceptance.';
comment on function public.authorize_sdf_quotation_commercial_decision_v1(uuid, uuid, uuid, uuid, jsonb, uuid) is
  'Owner-only QF-2A command. Revalidates immutable V3 SDF preparation lineage and fixed server pricing before binding approved VAT, terms, and an exact payment schedule. MAATWERK fails closed.';
