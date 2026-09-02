create table public.sdf_recurring_activation_obligations (
  obligation_id uuid primary key default gen_random_uuid(),
  sdf_project_id uuid not null references public.sdf_projects(project_id) on delete restrict,
  quote_request_id uuid not null references public.quote_requests(id) on delete restrict,
  request_kind text not null check (request_kind='slimme_documentenflow'),
  sdf_package text not null check (sdf_package in ('start','groei','pro','maatwerk')),
  pricing_mode text not null check (pricing_mode in ('fixed','manual')),
  amount_minor bigint not null check (amount_minor>0),
  currency char(3) not null check (currency='EUR'),
  vat_basis text not null check (vat_basis='exclusive'),
  recurring_cadence text not null check (recurring_cadence='MONTHLY'),
  period_authority text not null check (period_authority='ACTIVATION_ANCHOR'),
  activation_anchor_at timestamptz not null,
  accepted_terms_id uuid not null references public.sdf_accepted_commercial_terms(accepted_terms_id) on delete restrict,
  commercial_decision_id uuid not null references public.sdf_quotation_commercial_decisions(decision_id) on delete restrict,
  commercial_decision_sha256 char(64) not null check (commercial_decision_sha256~'^[0-9a-f]{64}$'),
  lifecycle_event_id uuid not null unique references public.sdf_project_lifecycle_events(lifecycle_event_id) on delete restrict,
  lifecycle_event_sha256 char(64) not null check (lifecycle_event_sha256~'^[0-9a-f]{64}$'),
  project_linkage_sha256 char(64) not null check (project_linkage_sha256~'^[0-9a-f]{64}$'),
  invoice_master_reference text not null,
  invoice_master_drive_file_id text not null,
  invoice_master_sha256 char(64) not null check (invoice_master_sha256~'^[0-9a-f]{64}$'),
  vat_decision_authority_id uuid not null references public.quotation_vat_decision_authorities(vat_decision_authority_id) on delete restrict,
  vat_authority_sha256 char(64) not null check (vat_authority_sha256~'^[0-9a-f]{64}$'),
  obligation_state text not null check (obligation_state='EXPECTED'),
  creation_idempotency_key uuid not null unique,
  creation_fingerprint char(64) not null check (creation_fingerprint~'^[0-9a-f]{64}$'),
  created_by_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint sdf_recurring_activation_business_key unique(sdf_project_id,period_authority)
);

create table public.sdf_recurring_invoice_candidates (
  candidate_id uuid primary key default gen_random_uuid(),
  obligation_id uuid not null unique references public.sdf_recurring_activation_obligations(obligation_id) on delete restrict,
  sdf_project_id uuid not null references public.sdf_projects(project_id) on delete restrict,
  quote_request_id uuid not null references public.quote_requests(id) on delete restrict,
  request_kind text not null check (request_kind='slimme_documentenflow'),
  sdf_package text not null check (sdf_package in ('start','groei','pro','maatwerk')),
  pricing_mode text not null check (pricing_mode in ('fixed','manual')),
  net_amount_minor bigint not null check (net_amount_minor>0),
  currency char(3) not null check (currency='EUR'),
  activation_anchor_at timestamptz not null,
  invoice_description text not null,
  accepted_terms_id uuid not null references public.sdf_accepted_commercial_terms(accepted_terms_id) on delete restrict,
  commercial_decision_id uuid not null references public.sdf_quotation_commercial_decisions(decision_id) on delete restrict,
  commercial_decision_sha256 char(64) not null check (commercial_decision_sha256~'^[0-9a-f]{64}$'),
  lifecycle_event_id uuid not null references public.sdf_project_lifecycle_events(lifecycle_event_id) on delete restrict,
  lifecycle_event_sha256 char(64) not null check (lifecycle_event_sha256~'^[0-9a-f]{64}$'),
  invoice_master_reference text not null,
  invoice_master_drive_file_id text not null,
  invoice_master_sha256 char(64) not null check (invoice_master_sha256~'^[0-9a-f]{64}$'),
  vat_decision_authority_id uuid not null references public.quotation_vat_decision_authorities(vat_decision_authority_id) on delete restrict,
  vat_authority_sha256 char(64) not null check (vat_authority_sha256~'^[0-9a-f]{64}$'),
  candidate_state text not null check (candidate_state='PREPARED'),
  candidate_payload_sha256 char(64) not null check (candidate_payload_sha256~'^[0-9a-f]{64}$'),
  creation_idempotency_key uuid not null unique,
  creation_fingerprint char(64) not null check (creation_fingerprint~'^[0-9a-f]{64}$'),
  prepared_by_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  prepared_at timestamptz not null default clock_timestamp()
);

create table public.sdf_recurring_invoice_issuances (
  issuance_id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null unique references public.sdf_recurring_invoice_candidates(candidate_id) on delete restrict,
  obligation_id uuid not null unique references public.sdf_recurring_activation_obligations(obligation_id) on delete restrict,
  sdf_project_id uuid not null references public.sdf_projects(project_id) on delete restrict,
  quote_request_id uuid not null references public.quote_requests(id) on delete restrict,
  request_kind text not null check (request_kind='slimme_documentenflow'),
  net_amount_minor bigint not null check (net_amount_minor>0),
  currency char(3) not null check (currency='EUR'),
  invoice_description text not null,
  invoice_master_reference text not null,
  invoice_master_drive_file_id text not null,
  invoice_master_sha256 char(64) not null check (invoice_master_sha256~'^[0-9a-f]{64}$'),
  invoice_number text not null unique check (invoice_number~'^LWS-[0-9]{4}-[0-9]{4}$'),
  issue_year smallint not null check (issue_year between 2000 and 9999),
  sequence integer not null check (sequence between 1 and 9999),
  issuance_state text not null check (issuance_state='INVOICED'),
  vat_decision_authority_id uuid not null references public.quotation_vat_decision_authorities(vat_decision_authority_id) on delete restrict,
  vat_authority_version text not null,
  vat_authority_sha256 char(64) not null check (vat_authority_sha256~'^[0-9a-f]{64}$'),
  vat_treatment text not null check (vat_treatment='EXEMPT'),
  rate_semantics text not null check (rate_semantics='NOT_APPLICABLE'),
  vat_rate_basis_points integer not null check (vat_rate_basis_points=0),
  invoice_literal text not null check (invoice_literal='Bijzondere vrijstellingsregeling van belasting'),
  vat_amount_minor bigint not null check (vat_amount_minor=0),
  gross_amount_minor bigint not null check (gross_amount_minor=net_amount_minor),
  issuance_payload_sha256 char(64) not null check (issuance_payload_sha256~'^[0-9a-f]{64}$'),
  docx_sha256 char(64) not null check (docx_sha256~'^[0-9a-f]{64}$'),
  docx_bytes bigint not null check (docx_bytes>0),
  pdf_sha256 char(64) check (pdf_sha256 is null or pdf_sha256~'^[0-9a-f]{64}$'),
  pdf_bytes bigint check (pdf_bytes is null or pdf_bytes>0),
  issuance_idempotency_key uuid not null unique,
  issuance_fingerprint char(64) not null check (issuance_fingerprint~'^[0-9a-f]{64}$'),
  issued_by_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  issued_at timestamptz not null default clock_timestamp(),
  constraint sdf_recurring_invoice_year_sequence_unique unique(issue_year,sequence)
);

create trigger trg_sdf_recurring_activation_obligations_immutable
before update or delete on public.sdf_recurring_activation_obligations
for each row execute function public.prevent_sdf_invoice_foundation_mutation_v1();
create trigger trg_sdf_recurring_invoice_candidates_immutable
before update or delete on public.sdf_recurring_invoice_candidates
for each row execute function public.prevent_sdf_invoice_foundation_mutation_v1();
create trigger trg_sdf_recurring_invoice_issuances_immutable
before update or delete on public.sdf_recurring_invoice_issuances
for each row execute function public.prevent_sdf_invoice_foundation_mutation_v1();

alter table public.sdf_recurring_activation_obligations enable row level security;
alter table public.sdf_recurring_activation_obligations force row level security;
alter table public.sdf_recurring_invoice_candidates enable row level security;
alter table public.sdf_recurring_invoice_candidates force row level security;
alter table public.sdf_recurring_invoice_issuances enable row level security;
alter table public.sdf_recurring_invoice_issuances force row level security;
revoke all privileges on table public.sdf_recurring_activation_obligations,
  public.sdf_recurring_invoice_candidates,public.sdf_recurring_invoice_issuances
from public,anon,authenticated,service_role;

create function public.create_sdf_recurring_activation_obligation_v1(
  p_lifecycle_event_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path=public,extensions,pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_event public.sdf_project_lifecycle_events%rowtype;
  v_terms public.sdf_accepted_commercial_terms%rowtype;
  v_decision public.sdf_quotation_commercial_decisions%rowtype;
  v_project public.sdf_projects%rowtype;
  v_request public.quote_requests%rowtype;
  v_master public.sdf_invoice_master_bindings%rowtype;
  v_vat public.sdf_quotation_vat_authority_bindings%rowtype;
  v_existing public.sdf_recurring_activation_obligations%rowtype;
  v_obligation public.sdf_recurring_activation_obligations%rowtype;
  v_pricing jsonb;
  v_amount bigint;
  v_pricing_mode text;
  v_event_hash text;
  v_fingerprint text;
begin
  v_operator:=lws_internal.assert_sdf_post_start_invoice_operator_v1();
  if p_lifecycle_event_id is null or p_idempotency_key is null then
    raise exception using errcode='22023',message='SDF_RECURRING_OBLIGATION_INPUT_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_lifecycle_event_id::text,0));

  select * into v_event from public.sdf_project_lifecycle_events
  where lifecycle_event_id=p_lifecycle_event_id;
  if not found or v_event.new_state<>'OPERATIONAL_ACTIVATED' then
    raise exception using errcode='23503',message='SDF_OPERATIONAL_ACTIVATION_REQUIRED';
  end if;
  select * into v_terms from public.sdf_accepted_commercial_terms
  where accepted_terms_id=v_event.accepted_terms_id;
  if not found then raise exception using errcode='23503',message='SDF_ACCEPTED_TERMS_REQUIRED'; end if;
  select * into v_request from public.quote_requests where id=v_terms.quote_request_id;
  if not found or v_request.request_kind<>'slimme_documentenflow' then
    raise exception using errcode='23514',message='SDF_FINANCIAL_AUTHORITY_REQUIRES_SDF';
  end if;
  select * into v_project from public.sdf_projects where project_id=v_event.project_id;
  if not found or v_project.quote_request_id<>v_terms.quote_request_id
     or v_event.quote_request_id<>v_terms.quote_request_id
     or v_event.quotation_id<>v_terms.quotation_id
     or v_event.request_kind<>'slimme_documentenflow' then
    raise exception using errcode='23514',message='SDF_RECURRING_PROJECT_LINKAGE_MISMATCH';
  end if;
  select * into v_decision from public.sdf_quotation_commercial_decisions
  where quotation_id=v_terms.quotation_id
    and (
      decision_id=v_terms.commercial_decision_id
      or (
        v_terms.sdf_package in ('start','groei','pro')
        and v_terms.commercial_decision_id is null
      )
    );
  if not found or v_decision.quote_request_id<>v_terms.quote_request_id
     or v_decision.quotation_id<>v_terms.quotation_id
     or v_decision.sdf_package<>v_terms.sdf_package
     or (
       v_terms.commercial_decision_sha256 is not null
       and rtrim(v_decision.decision_sha256)<>rtrim(v_terms.commercial_decision_sha256)
     )
     or rtrim(v_decision.decision_sha256)<>
        encode(extensions.digest(convert_to(v_decision.canonical_payload::text,'UTF8'),'sha256'),'hex') then
    raise exception using errcode='55000',message='SDF_RECURRING_COMMERCIAL_SNAPSHOT_STALE';
  end if;

  v_pricing:=public.get_sdf_package_pricing_authority_v1(v_terms.sdf_package);
  if v_terms.sdf_package='maatwerk' then
    if v_terms.accepted_recurring_amount_minor is null or v_terms.accepted_recurring_amount_minor<=0 then
      raise exception using errcode='23514',message='SDF_MAATWERK_RECURRING_AMOUNT_REQUIRED';
    end if;
    v_amount:=v_terms.accepted_recurring_amount_minor;
    v_pricing_mode:='manual';
    if (v_decision.canonical_payload->>'recurring_amount_minor')::bigint<>v_amount
       or v_terms.pricing_mode<>'manual' then
      raise exception using errcode='55000',message='SDF_RECURRING_COMMERCIAL_SNAPSHOT_STALE';
    end if;
  else
    v_amount:=(v_pricing#>>'{recurring,amount_minor}')::bigint;
    v_pricing_mode:='fixed';
    if (v_decision.canonical_payload->>'recurring_amount_minor')::bigint<>v_amount
       or (v_terms.accepted_recurring_amount_minor is not null and v_terms.accepted_recurring_amount_minor<>v_amount)
       or (v_terms.pricing_mode is not null and v_terms.pricing_mode<>'fixed') then
      raise exception using errcode='55000',message='SDF_RECURRING_COMMERCIAL_SNAPSHOT_STALE';
    end if;
  end if;

  select * into strict v_master from public.sdf_invoice_master_bindings where singleton;
  select * into v_vat from public.sdf_quotation_vat_authority_bindings
  where quotation_id=v_terms.quotation_id;
  if not found then raise exception using errcode='P0001',message='QUOTATION_VAT_CONTEXT_REQUIRED'; end if;
  v_event_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'activationAnchorAt',v_event.occurred_at,'evidenceReference',v_event.evidence_reference,
    'evidenceSha256',rtrim(v_event.evidence_sha256),'lifecycleEventId',v_event.lifecycle_event_id,
    'projectId',v_event.project_id,'projectLinkageSha256',rtrim(v_event.project_linkage_sha256),
    'requestFingerprint',rtrim(v_event.request_fingerprint),'state',v_event.new_state
  )::text,'UTF8'),'sha256'),'hex');
  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'acceptedTermsId',v_terms.accepted_terms_id,'amountMinor',v_amount,
    'commercialDecisionId',v_decision.decision_id,'commercialDecisionSha256',rtrim(v_decision.decision_sha256),
    'currency',v_terms.currency,'lifecycleEventId',v_event.lifecycle_event_id,
    'lifecycleEventSha256',v_event_hash,'periodAuthority','ACTIVATION_ANCHOR',
    'projectId',v_project.project_id
  )::text,'UTF8'),'sha256'),'hex');

  select * into v_existing from public.sdf_recurring_activation_obligations
  where creation_idempotency_key=p_idempotency_key;
  if found then
    if rtrim(v_existing.creation_fingerprint)<>v_fingerprint then
      raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('obligation_id',v_existing.obligation_id,'obligation_state','EXPECTED','was_created',false);
  end if;
  select * into v_existing from public.sdf_recurring_activation_obligations
  where sdf_project_id=v_project.project_id and period_authority='ACTIVATION_ANCHOR';
  if found then
    if rtrim(v_existing.creation_fingerprint)<>v_fingerprint then
      raise exception using errcode='P0001',message='SDF_RECURRING_OBLIGATION_CONFLICT';
    end if;
    return jsonb_build_object('obligation_id',v_existing.obligation_id,'obligation_state','EXPECTED','was_created',false);
  end if;

  insert into public.sdf_recurring_activation_obligations(
    sdf_project_id,quote_request_id,request_kind,sdf_package,pricing_mode,amount_minor,
    currency,vat_basis,recurring_cadence,period_authority,activation_anchor_at,
    accepted_terms_id,commercial_decision_id,commercial_decision_sha256,lifecycle_event_id,
    lifecycle_event_sha256,project_linkage_sha256,invoice_master_reference,
    invoice_master_drive_file_id,invoice_master_sha256,vat_decision_authority_id,
    vat_authority_sha256,obligation_state,creation_idempotency_key,creation_fingerprint,
    created_by_operator_id
  ) values (
    v_project.project_id,v_terms.quote_request_id,'slimme_documentenflow',v_terms.sdf_package,
    v_pricing_mode,v_amount,v_terms.currency,v_terms.vat_basis,'MONTHLY','ACTIVATION_ANCHOR',
    v_event.occurred_at,v_terms.accepted_terms_id,v_decision.decision_id,rtrim(v_decision.decision_sha256),
    v_event.lifecycle_event_id,v_event_hash,rtrim(v_event.project_linkage_sha256),
    v_master.document_reference,v_master.drive_file_id,rtrim(v_master.document_sha256),
    v_vat.vat_decision_authority_id,rtrim(v_vat.vat_authority_sha256),'EXPECTED',
    p_idempotency_key,v_fingerprint,v_operator.operator_id
  ) returning * into v_obligation;
  return jsonb_build_object('obligation_id',v_obligation.obligation_id,'obligation_state','EXPECTED','was_created',true);
end;
$$;

create function public.prepare_sdf_recurring_invoice_candidate_v1(
  p_obligation_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path=public,extensions,pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_obligation public.sdf_recurring_activation_obligations%rowtype;
  v_master public.sdf_invoice_master_bindings%rowtype;
  v_vat public.sdf_quotation_vat_authority_bindings%rowtype;
  v_existing public.sdf_recurring_invoice_candidates%rowtype;
  v_candidate public.sdf_recurring_invoice_candidates%rowtype;
  v_description text;
  v_payload text;
  v_fingerprint text;
begin
  v_operator:=lws_internal.assert_sdf_post_start_invoice_operator_v1();
  if p_obligation_id is null or p_idempotency_key is null then
    raise exception using errcode='22023',message='SDF_RECURRING_CANDIDATE_INPUT_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obligation_id::text,0));
  select * into v_obligation from public.sdf_recurring_activation_obligations where obligation_id=p_obligation_id;
  if not found then raise exception using errcode='23503',message='SDF_RECURRING_OBLIGATION_REQUIRED'; end if;
  select * into strict v_master from public.sdf_invoice_master_bindings where singleton;
  if v_obligation.invoice_master_reference<>v_master.document_reference
     or v_obligation.invoice_master_drive_file_id<>v_master.drive_file_id
     or rtrim(v_obligation.invoice_master_sha256)<>rtrim(v_master.document_sha256) then
    raise exception using errcode='55000',message='SDF_INVOICE_MASTER_STALE';
  end if;
  select * into v_vat from public.sdf_quotation_vat_authority_bindings
  where quote_request_id=v_obligation.quote_request_id;
  if not found or v_vat.vat_decision_authority_id<>v_obligation.vat_decision_authority_id
     or rtrim(v_vat.vat_authority_sha256)<>rtrim(v_obligation.vat_authority_sha256) then
    raise exception using errcode='55000',message='SDF_VAT_AUTHORITY_MISMATCH';
  end if;
  v_description:='Slimme Documentenflow — recurrente dienstverlening activation anchor '
    ||to_char(v_obligation.activation_anchor_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')
    ||' — pakket '||upper(v_obligation.sdf_package);
  v_payload:=encode(extensions.digest(convert_to(jsonb_build_object(
    'activationAnchorAt',v_obligation.activation_anchor_at,'amountMinor',v_obligation.amount_minor,
    'commercialDecisionSha256',rtrim(v_obligation.commercial_decision_sha256),
    'description',v_description,'invoiceMasterSha256',rtrim(v_master.document_sha256),
    'lifecycleEventSha256',rtrim(v_obligation.lifecycle_event_sha256),
    'obligationId',v_obligation.obligation_id,'vatAuthoritySha256',rtrim(v_vat.vat_authority_sha256)
  )::text,'UTF8'),'sha256'),'hex');
  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'candidatePayloadSha256',v_payload,'obligationId',v_obligation.obligation_id
  )::text,'UTF8'),'sha256'),'hex');
  select * into v_existing from public.sdf_recurring_invoice_candidates where creation_idempotency_key=p_idempotency_key;
  if found then
    if rtrim(v_existing.creation_fingerprint)<>v_fingerprint then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT'; end if;
    return jsonb_build_object('candidate_id',v_existing.candidate_id,'candidate_state','PREPARED','invoice_number',null,'was_created',false);
  end if;
  select * into v_existing from public.sdf_recurring_invoice_candidates where obligation_id=p_obligation_id;
  if found then
    if rtrim(v_existing.creation_fingerprint)<>v_fingerprint then raise exception using errcode='P0001',message='SDF_RECURRING_CANDIDATE_CONFLICT'; end if;
    return jsonb_build_object('candidate_id',v_existing.candidate_id,'candidate_state','PREPARED','invoice_number',null,'was_created',false);
  end if;
  insert into public.sdf_recurring_invoice_candidates(
    obligation_id,sdf_project_id,quote_request_id,request_kind,sdf_package,pricing_mode,
    net_amount_minor,currency,activation_anchor_at,invoice_description,accepted_terms_id,
    commercial_decision_id,commercial_decision_sha256,lifecycle_event_id,lifecycle_event_sha256,
    invoice_master_reference,invoice_master_drive_file_id,invoice_master_sha256,
    vat_decision_authority_id,vat_authority_sha256,candidate_state,candidate_payload_sha256,
    creation_idempotency_key,creation_fingerprint,prepared_by_operator_id
  ) values (
    v_obligation.obligation_id,v_obligation.sdf_project_id,v_obligation.quote_request_id,
    'slimme_documentenflow',v_obligation.sdf_package,v_obligation.pricing_mode,
    v_obligation.amount_minor,v_obligation.currency,v_obligation.activation_anchor_at,v_description,
    v_obligation.accepted_terms_id,v_obligation.commercial_decision_id,
    rtrim(v_obligation.commercial_decision_sha256),v_obligation.lifecycle_event_id,
    rtrim(v_obligation.lifecycle_event_sha256),v_master.document_reference,v_master.drive_file_id,
    rtrim(v_master.document_sha256),v_vat.vat_decision_authority_id,rtrim(v_vat.vat_authority_sha256),
    'PREPARED',v_payload,p_idempotency_key,v_fingerprint,v_operator.operator_id
  ) returning * into v_candidate;
  return jsonb_build_object('candidate_id',v_candidate.candidate_id,'candidate_state','PREPARED','invoice_number',null,'was_created',true);
end;
$$;

create function public.issue_sdf_recurring_invoice_v1(
  p_candidate_id uuid,
  p_issue_year smallint,
  p_idempotency_key uuid,
  p_docx_sha256 text,
  p_docx_bytes bigint,
  p_pdf_sha256 text,
  p_pdf_bytes bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path=public,extensions,pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_candidate public.sdf_recurring_invoice_candidates%rowtype;
  v_master public.sdf_invoice_master_bindings%rowtype;
  v_vat public.sdf_quotation_vat_authority_bindings%rowtype;
  v_existing public.sdf_recurring_invoice_issuances%rowtype;
  v_issuance public.sdf_recurring_invoice_issuances%rowtype;
  v_number record;
  v_year smallint:=(extract(year from clock_timestamp() at time zone 'Europe/Brussels'))::smallint;
  v_fingerprint text;
  v_payload text;
begin
  v_operator:=lws_internal.assert_sdf_post_start_invoice_operator_v1();
  if p_candidate_id is null or p_idempotency_key is null or p_issue_year<>v_year
     or p_docx_sha256!~'^[0-9a-f]{64}$' or p_docx_bytes<=0
     or (p_pdf_sha256 is null)<>(p_pdf_bytes is null)
     or (p_pdf_sha256 is not null and (p_pdf_sha256!~'^[0-9a-f]{64}$' or p_pdf_bytes<=0)) then
    raise exception using errcode='22023',message='SDF_RECURRING_ISSUANCE_INPUT_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_candidate_id::text,0));
  select * into v_candidate from public.sdf_recurring_invoice_candidates where candidate_id=p_candidate_id;
  if not found then raise exception using errcode='23503',message='SDF_RECURRING_CANDIDATE_REQUIRED'; end if;
  select * into strict v_master from public.sdf_invoice_master_bindings where singleton;
  if v_candidate.invoice_master_reference<>v_master.document_reference
     or v_candidate.invoice_master_drive_file_id<>v_master.drive_file_id
     or rtrim(v_candidate.invoice_master_sha256)<>rtrim(v_master.document_sha256) then
    raise exception using errcode='55000',message='SDF_INVOICE_MASTER_STALE';
  end if;
  select * into v_vat from public.sdf_quotation_vat_authority_bindings
  where quote_request_id=v_candidate.quote_request_id;
  if not found or v_vat.vat_decision_authority_id<>v_candidate.vat_decision_authority_id
     or rtrim(v_vat.vat_authority_sha256)<>rtrim(v_candidate.vat_authority_sha256)
     or v_vat.vat_treatment<>'EXEMPT' or v_vat.rate_semantics<>'NOT_APPLICABLE' then
    raise exception using errcode='55000',message='SDF_VAT_AUTHORITY_MISMATCH';
  end if;
  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'candidateId',v_candidate.candidate_id,'candidatePayloadSha256',rtrim(v_candidate.candidate_payload_sha256),
    'docxBytes',p_docx_bytes,'docxSha256',p_docx_sha256,'issueYear',p_issue_year,
    'pdfBytes',p_pdf_bytes,'pdfSha256',p_pdf_sha256,'vatAuthoritySha256',rtrim(v_vat.vat_authority_sha256)
  )::text,'UTF8'),'sha256'),'hex');
  select * into v_existing from public.sdf_recurring_invoice_issuances where issuance_idempotency_key=p_idempotency_key;
  if found then
    if rtrim(v_existing.issuance_fingerprint)<>v_fingerprint then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT'; end if;
    return jsonb_build_object('issuance_id',v_existing.issuance_id,'invoice_number',v_existing.invoice_number,'was_created',false);
  end if;
  select * into v_existing from public.sdf_recurring_invoice_issuances where candidate_id=p_candidate_id;
  if found then
    if rtrim(v_existing.issuance_fingerprint)<>v_fingerprint then raise exception using errcode='P0001',message='SDF_RECURRING_ISSUANCE_CONFLICT'; end if;
    return jsonb_build_object('issuance_id',v_existing.issuance_id,'invoice_number',v_existing.invoice_number,'was_created',false);
  end if;
  select * into strict v_number from public.allocate_sdf_invoice_number_v1(p_issue_year);
  v_payload:=encode(extensions.digest(convert_to(jsonb_build_object(
    'candidatePayloadSha256',rtrim(v_candidate.candidate_payload_sha256),
    'grossAmountMinor',v_candidate.net_amount_minor,'invoiceLiteral',v_vat.invoice_literal,
    'invoiceNumber',v_number.invoice_number,'netAmountMinor',v_candidate.net_amount_minor,
    'vatAmountMinor',0,'vatTreatment',v_vat.vat_treatment
  )::text,'UTF8'),'sha256'),'hex');
  insert into public.sdf_recurring_invoice_issuances(
    candidate_id,obligation_id,sdf_project_id,quote_request_id,request_kind,net_amount_minor,
    currency,invoice_description,invoice_master_reference,invoice_master_drive_file_id,
    invoice_master_sha256,invoice_number,issue_year,sequence,issuance_state,
    vat_decision_authority_id,vat_authority_version,vat_authority_sha256,vat_treatment,
    rate_semantics,vat_rate_basis_points,invoice_literal,vat_amount_minor,gross_amount_minor,
    issuance_payload_sha256,docx_sha256,docx_bytes,pdf_sha256,pdf_bytes,
    issuance_idempotency_key,issuance_fingerprint,issued_by_operator_id
  ) values (
    v_candidate.candidate_id,v_candidate.obligation_id,v_candidate.sdf_project_id,
    v_candidate.quote_request_id,'slimme_documentenflow',v_candidate.net_amount_minor,
    v_candidate.currency,v_candidate.invoice_description,v_master.document_reference,v_master.drive_file_id,
    rtrim(v_master.document_sha256),v_number.invoice_number,p_issue_year,v_number.sequence,'INVOICED',
    v_vat.vat_decision_authority_id,v_vat.vat_authority_version,rtrim(v_vat.vat_authority_sha256),
    v_vat.vat_treatment,v_vat.rate_semantics,0,v_vat.invoice_literal,0,v_candidate.net_amount_minor,
    v_payload,p_docx_sha256,p_docx_bytes,p_pdf_sha256,p_pdf_bytes,p_idempotency_key,v_fingerprint,
    v_operator.operator_id
  ) returning * into v_issuance;
  return jsonb_build_object('issuance_id',v_issuance.issuance_id,'invoice_number',v_issuance.invoice_number,'was_created',true);
end;
$$;

revoke all on function public.create_sdf_recurring_activation_obligation_v1(uuid,uuid)
from public,anon,authenticated,service_role;
revoke all on function public.prepare_sdf_recurring_invoice_candidate_v1(uuid,uuid)
from public,anon,authenticated,service_role;
revoke all on function public.issue_sdf_recurring_invoice_v1(uuid,smallint,uuid,text,bigint,text,bigint)
from public,anon,authenticated,service_role;
grant execute on function public.create_sdf_recurring_activation_obligation_v1(uuid,uuid) to authenticated;
grant execute on function public.prepare_sdf_recurring_invoice_candidate_v1(uuid,uuid) to authenticated;
grant execute on function public.issue_sdf_recurring_invoice_v1(uuid,smallint,uuid,text,bigint,text,bigint) to authenticated;

comment on table public.sdf_recurring_activation_obligations is
  'Immutable first MONTHLY recurring EXPECTED obligation anchored only to canonical OPERATIONAL_ACTIVATED. Defines no billing day, calendar period, next cycle, proration, receipt, reconciliation, or scheduler.';
comment on table public.sdf_recurring_invoice_issuances is
  'Immutable recurring INVOICED authority reusing the generic SDF invoice master, VAT binding, and invoice number allocator. INVOICED never implies RECEIVED or RECONCILED.';