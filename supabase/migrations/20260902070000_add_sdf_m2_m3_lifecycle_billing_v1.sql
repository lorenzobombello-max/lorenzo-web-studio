create table public.sdf_post_start_milestone_obligations (
  obligation_id uuid primary key default gen_random_uuid(),
  sdf_project_id uuid not null references public.sdf_projects(project_id) on delete restrict,
  quote_request_id uuid not null references public.quote_requests(id) on delete restrict,
  request_kind text not null check (request_kind='slimme_documentenflow'),
  sdf_package text not null check (sdf_package in ('start','groei','pro','maatwerk')),
  approved_implementation_amount_minor bigint not null check (approved_implementation_amount_minor>0),
  milestone_identity text not null check (milestone_identity in ('M2','M3')),
  percentage_basis_points smallint not null check (
    (milestone_identity='M2' and percentage_basis_points=4000)
    or (milestone_identity='M3' and percentage_basis_points=2000)
  ),
  amount_minor bigint not null check (amount_minor>0),
  currency char(3) not null check (currency='EUR'),
  vat_basis text not null check (vat_basis='exclusive'),
  accepted_terms_id uuid not null references public.sdf_accepted_commercial_terms(accepted_terms_id) on delete restrict,
  quotation_id uuid not null references public.sdf_accepted_commercial_terms(quotation_id) on delete restrict,
  commercial_snapshot_sha256 char(64) not null check (commercial_snapshot_sha256~'^[0-9a-f]{64}$'),
  lifecycle_event_id uuid not null unique references public.sdf_project_lifecycle_events(lifecycle_event_id) on delete restrict,
  lifecycle_event_state text not null check (lifecycle_event_state in ('PHASE_A_CONFIRMED','PHASE_B_CONFIRMED')),
  lifecycle_evidence_reference text not null,
  lifecycle_evidence_sha256 char(64) not null check (lifecycle_evidence_sha256~'^[0-9a-f]{64}$'),
  project_linkage_sha256 char(64) not null check (project_linkage_sha256~'^[0-9a-f]{64}$'),
  obligation_state text not null check (obligation_state='EXPECTED'),
  obligation_origin text not null check (obligation_origin='LIFECYCLE_EVENT'),
  creation_idempotency_key uuid not null unique,
  creation_fingerprint char(64) not null check (creation_fingerprint~'^[0-9a-f]{64}$'),
  created_by_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint sdf_post_start_obligation_business_key unique(sdf_project_id,milestone_identity),
  constraint sdf_post_start_obligation_event_coherent check (
    (milestone_identity='M2' and lifecycle_event_state='PHASE_A_CONFIRMED')
    or (milestone_identity='M3' and lifecycle_event_state='PHASE_B_CONFIRMED')
  )
);

create table public.sdf_post_start_invoice_candidates (
  candidate_id uuid primary key default gen_random_uuid(),
  obligation_id uuid not null unique references public.sdf_post_start_milestone_obligations(obligation_id) on delete restrict,
  sdf_project_id uuid not null references public.sdf_projects(project_id) on delete restrict,
  quote_request_id uuid not null references public.quote_requests(id) on delete restrict,
  request_kind text not null check (request_kind='slimme_documentenflow'),
  application_reference text not null check (application_reference~'^LWS-AAN-[0-9]{4}-[0-9]{4}$'),
  sdf_package text not null check (sdf_package in ('start','groei','pro','maatwerk')),
  approved_implementation_amount_minor bigint not null check (approved_implementation_amount_minor>0),
  milestone_identity text not null check (milestone_identity in ('M2','M3')),
  percentage_basis_points smallint not null check (percentage_basis_points in (4000,2000)),
  net_amount_minor bigint not null check (net_amount_minor>0),
  currency char(3) not null check (currency='EUR'),
  accepted_price_basis text not null check (accepted_price_basis='exclusive'),
  accepted_terms_id uuid not null references public.sdf_accepted_commercial_terms(accepted_terms_id) on delete restrict,
  quotation_id uuid not null references public.sdf_accepted_commercial_terms(quotation_id) on delete restrict,
  commercial_snapshot_sha256 char(64) not null check (commercial_snapshot_sha256~'^[0-9a-f]{64}$'),
  lifecycle_event_id uuid not null references public.sdf_project_lifecycle_events(lifecycle_event_id) on delete restrict,
  lifecycle_event_state text not null check (lifecycle_event_state in ('PHASE_A_CONFIRMED','PHASE_B_CONFIRMED')),
  lifecycle_evidence_reference text not null,
  lifecycle_evidence_sha256 char(64) not null check (lifecycle_evidence_sha256~'^[0-9a-f]{64}$'),
  project_linkage_sha256 char(64) not null check (project_linkage_sha256~'^[0-9a-f]{64}$'),
  invoice_master_reference text not null,
  invoice_master_drive_file_id text not null,
  invoice_master_sha256 char(64) not null check (invoice_master_sha256~'^[0-9a-f]{64}$'),
  seller_snapshot jsonb not null,
  customer_snapshot jsonb not null,
  bank_snapshot jsonb not null,
  candidate_state text not null check (candidate_state='PREPARED'),
  candidate_payload_sha256 char(64) not null check (candidate_payload_sha256~'^[0-9a-f]{64}$'),
  creation_idempotency_key uuid not null unique,
  creation_fingerprint char(64) not null check (creation_fingerprint~'^[0-9a-f]{64}$'),
  prepared_by_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  prepared_at timestamptz not null default clock_timestamp()
);

create table public.sdf_post_start_invoice_issuances (
  issuance_id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null unique references public.sdf_post_start_invoice_candidates(candidate_id) on delete restrict,
  obligation_id uuid not null unique references public.sdf_post_start_milestone_obligations(obligation_id) on delete restrict,
  sdf_project_id uuid not null references public.sdf_projects(project_id) on delete restrict,
  quote_request_id uuid not null references public.quote_requests(id) on delete restrict,
  request_kind text not null check (request_kind='slimme_documentenflow'),
  sdf_package text not null check (sdf_package in ('start','groei','pro','maatwerk')),
  approved_implementation_amount_minor bigint not null check (approved_implementation_amount_minor>0),
  milestone_identity text not null check (milestone_identity in ('M2','M3')),
  percentage_basis_points smallint not null check (percentage_basis_points in (4000,2000)),
  net_amount_minor bigint not null check (net_amount_minor>0),
  currency char(3) not null check (currency='EUR'),
  accepted_terms_id uuid not null references public.sdf_accepted_commercial_terms(accepted_terms_id) on delete restrict,
  quotation_id uuid not null references public.sdf_accepted_commercial_terms(quotation_id) on delete restrict,
  commercial_snapshot_sha256 char(64) not null check (commercial_snapshot_sha256~'^[0-9a-f]{64}$'),
  lifecycle_event_id uuid not null references public.sdf_project_lifecycle_events(lifecycle_event_id) on delete restrict,
  lifecycle_event_state text not null check (lifecycle_event_state in ('PHASE_A_CONFIRMED','PHASE_B_CONFIRMED')),
  lifecycle_evidence_reference text not null,
  lifecycle_evidence_sha256 char(64) not null check (lifecycle_evidence_sha256~'^[0-9a-f]{64}$'),
  project_linkage_sha256 char(64) not null check (project_linkage_sha256~'^[0-9a-f]{64}$'),
  invoice_master_reference text not null,
  invoice_master_drive_file_id text not null,
  invoice_master_sha256 char(64) not null check (invoice_master_sha256~'^[0-9a-f]{64}$'),
  invoice_number text not null unique check (invoice_number~'^LWS-[0-9]{4}-[0-9]{4}$'),
  issue_year smallint not null check (issue_year between 2000 and 9999),
  sequence integer not null check (sequence between 1 and 9999),
  issuance_state text not null check (issuance_state='ISSUED'),
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
  constraint sdf_post_start_invoice_number_coherent check (
    invoice_number='LWS-'||issue_year::text||'-'||lpad(sequence::text,4,'0')
  ),
  constraint sdf_post_start_invoice_year_sequence_unique unique(issue_year,sequence)
);

create function lws_internal.assert_sdf_post_start_invoice_operator_v1()
returns public.commercial_operators
language plpgsql
stable
security definer
set search_path=public,auth,pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
begin
  select * into v_operator from public.commercial_operators where auth_user_id=auth.uid();
  if not found or v_operator.status<>'ACTIVE' or v_operator.role not in ('owner','admin') then
    raise exception using errcode='42501',message='SDF_INVOICE_AUTHORITY_DENIED';
  end if;
  return v_operator;
end;
$$;

create function lws_internal.calculate_sdf_post_start_commercial_snapshot_v1(
  p_terms public.sdf_accepted_commercial_terms,
  p_event public.sdf_project_lifecycle_events,
  p_milestone_identity text,
  p_percentage_basis_points smallint,
  p_amount_minor bigint
)
returns text
language sql
immutable
strict
set search_path=public,extensions,pg_catalog
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'acceptedImplementationAmountMinor',p_terms.accepted_implementation_amount_minor,
    'acceptedTermsId',p_terms.accepted_terms_id,
    'currency',p_terms.currency,
    'lifecycleEventId',p_event.lifecycle_event_id,
    'lifecycleEventState',p_event.new_state,
    'lifecycleEvidenceReference',p_event.evidence_reference,
    'lifecycleEvidenceSha256',rtrim(p_event.evidence_sha256),
    'milestoneAmountMinor',p_amount_minor,
    'milestoneIdentity',p_milestone_identity,
    'package',p_terms.sdf_package,
    'percentageBasisPoints',p_percentage_basis_points,
    'pricingAuthorityVersion',p_terms.pricing_authority_version,
    'projectId',p_event.project_id,
    'projectLinkageSha256',rtrim(p_event.project_linkage_sha256),
    'quotationId',p_terms.quotation_id,
    'quoteRequestId',p_terms.quote_request_id,
    'vatBasis',p_terms.vat_basis
  )::text,'UTF8'),'sha256'),'hex')
$$;

create function public.create_sdf_post_start_milestone_obligation_v1(
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
  v_predecessor public.sdf_project_lifecycle_events%rowtype;
  v_terms public.sdf_accepted_commercial_terms%rowtype;
  v_request public.quote_requests%rowtype;
  v_project public.sdf_projects%rowtype;
  v_existing public.sdf_post_start_milestone_obligations%rowtype;
  v_obligation public.sdf_post_start_milestone_obligations%rowtype;
  v_pricing jsonb;
  v_milestone text;
  v_percentage smallint;
  v_amount bigint;
  v_snapshot text;
  v_fingerprint text;
begin
  v_operator:=lws_internal.assert_sdf_post_start_invoice_operator_v1();
  if p_lifecycle_event_id is null or p_idempotency_key is null then
    raise exception using errcode='22023',message='SDF_POST_START_OBLIGATION_INPUT_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_lifecycle_event_id::text,0));

  select * into v_event from public.sdf_project_lifecycle_events where lifecycle_event_id=p_lifecycle_event_id;
  if not found or v_event.new_state not in ('PHASE_A_CONFIRMED','PHASE_B_CONFIRMED') then
    raise exception using errcode='23503',message='SDF_LIFECYCLE_EVENT_REQUIRED';
  end if;
  select * into v_terms from public.sdf_accepted_commercial_terms where accepted_terms_id=v_event.accepted_terms_id;
  if not found then raise exception using errcode='23503',message='SDF_ACCEPTED_TERMS_REQUIRED'; end if;
  select * into v_request from public.quote_requests where id=v_terms.quote_request_id;
  if not found or v_request.request_kind<>'slimme_documentenflow' then
    raise exception using errcode='23514',message='SDF_FINANCIAL_AUTHORITY_REQUIRES_SDF';
  end if;
  select * into v_project from public.sdf_projects where quote_request_id=v_terms.quote_request_id;
  if not found or v_event.project_id<>v_project.project_id or v_event.quote_request_id<>v_terms.quote_request_id
     or v_event.quotation_id<>v_terms.quotation_id or v_event.request_kind<>'slimme_documentenflow' then
    raise exception using errcode='23514',message='SDF_LIFECYCLE_PROJECT_LINKAGE_MISMATCH';
  end if;
  if v_event.new_state='PHASE_B_CONFIRMED' then
    select * into v_predecessor from public.sdf_project_lifecycle_events
    where lifecycle_event_id=v_event.predecessor_event_id and project_id=v_event.project_id
      and new_state='PHASE_A_CONFIRMED';
    if not found then raise exception using errcode='55000',message='SDF_LIFECYCLE_ORDER_INVALID'; end if;
  end if;

  v_pricing:=public.get_sdf_package_pricing_authority_v1(v_terms.sdf_package);
  if v_terms.sdf_package in ('start','groei','pro')
     and v_terms.accepted_implementation_amount_minor<>(v_pricing->'implementation'->>'amount_minor')::bigint then
    raise exception using errcode='55000',message='SDF_POST_START_COMMERCIAL_SNAPSHOT_STALE';
  end if;
  if v_terms.sdf_package='maatwerk' and (v_terms.accepted_implementation_amount_minor is null or v_terms.accepted_implementation_amount_minor<=0) then
    raise exception using errcode='23514',message='SDF_MAATWERK_AMOUNT_REQUIRED';
  end if;
  v_milestone:=case v_event.new_state when 'PHASE_A_CONFIRMED' then 'M2' else 'M3' end;
  v_percentage:=case v_milestone when 'M2' then 4000 else 2000 end;
  if mod(v_terms.accepted_implementation_amount_minor*v_percentage,10000)<>0 then
    raise exception using errcode='23514',message='SDF_POST_START_MILESTONE_MINOR_UNIT_INEXACT';
  end if;
  v_amount:=(v_terms.accepted_implementation_amount_minor*v_percentage)/10000;
  v_snapshot:=lws_internal.calculate_sdf_post_start_commercial_snapshot_v1(v_terms,v_event,v_milestone,v_percentage,v_amount);
  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'commercialSnapshotSha256',v_snapshot,'lifecycleEventId',v_event.lifecycle_event_id,
    'milestoneIdentity',v_milestone
  )::text,'UTF8'),'sha256'),'hex');

  select * into v_existing from public.sdf_post_start_milestone_obligations where creation_idempotency_key=p_idempotency_key;
  if found then
    if rtrim(v_existing.creation_fingerprint)<>v_fingerprint then
      raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('obligation_id',v_existing.obligation_id,'obligation_state','EXPECTED','was_created',false);
  end if;
  select * into v_existing from public.sdf_post_start_milestone_obligations
  where sdf_project_id=v_project.project_id and milestone_identity=v_milestone;
  if found then
    if rtrim(v_existing.creation_fingerprint)<>v_fingerprint then
      raise exception using errcode='P0001',message='SDF_POST_START_OBLIGATION_CONFLICT';
    end if;
    return jsonb_build_object('obligation_id',v_existing.obligation_id,'obligation_state','EXPECTED','was_created',false);
  end if;

  insert into public.sdf_post_start_milestone_obligations(
    sdf_project_id,quote_request_id,request_kind,sdf_package,approved_implementation_amount_minor,
    milestone_identity,percentage_basis_points,amount_minor,currency,vat_basis,accepted_terms_id,
    quotation_id,commercial_snapshot_sha256,lifecycle_event_id,lifecycle_event_state,
    lifecycle_evidence_reference,lifecycle_evidence_sha256,project_linkage_sha256,
    obligation_state,obligation_origin,creation_idempotency_key,creation_fingerprint,created_by_operator_id
  ) values (
    v_project.project_id,v_terms.quote_request_id,'slimme_documentenflow',v_terms.sdf_package,
    v_terms.accepted_implementation_amount_minor,v_milestone,v_percentage,v_amount,v_terms.currency,
    v_terms.vat_basis,v_terms.accepted_terms_id,v_terms.quotation_id,v_snapshot,v_event.lifecycle_event_id,
    v_event.new_state,v_event.evidence_reference,rtrim(v_event.evidence_sha256),
    rtrim(v_event.project_linkage_sha256),'EXPECTED','LIFECYCLE_EVENT',p_idempotency_key,v_fingerprint,
    v_operator.operator_id
  ) returning * into v_obligation;
  return jsonb_build_object('obligation_id',v_obligation.obligation_id,'obligation_state','EXPECTED','was_created',true);
end;
$$;

create function public.prepare_sdf_post_start_invoice_candidate_v1(
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
  v_obligation public.sdf_post_start_milestone_obligations%rowtype;
  v_terms public.sdf_accepted_commercial_terms%rowtype;
  v_event public.sdf_project_lifecycle_events%rowtype;
  v_request public.quote_requests%rowtype;
  v_master public.sdf_invoice_master_bindings%rowtype;
  v_existing public.sdf_post_start_invoice_candidates%rowtype;
  v_candidate public.sdf_post_start_invoice_candidates%rowtype;
  v_snapshot text;
  v_seller jsonb;
  v_customer jsonb;
  v_bank jsonb;
  v_payload_hash text;
  v_fingerprint text;
begin
  v_operator:=lws_internal.assert_sdf_post_start_invoice_operator_v1();
  if p_obligation_id is null or p_idempotency_key is null then
    raise exception using errcode='22023',message='SDF_POST_START_CANDIDATE_INPUT_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_obligation_id::text,0));
  select * into v_obligation from public.sdf_post_start_milestone_obligations where obligation_id=p_obligation_id;
  if not found then raise exception using errcode='23503',message='SDF_POST_START_OBLIGATION_REQUIRED'; end if;
  select * into strict v_terms from public.sdf_accepted_commercial_terms where accepted_terms_id=v_obligation.accepted_terms_id;
  select * into strict v_event from public.sdf_project_lifecycle_events where lifecycle_event_id=v_obligation.lifecycle_event_id;
  select * into strict v_request from public.quote_requests where id=v_obligation.quote_request_id;
  select * into strict v_master from public.sdf_invoice_master_bindings where singleton;
  v_snapshot:=lws_internal.calculate_sdf_post_start_commercial_snapshot_v1(
    v_terms,v_event,v_obligation.milestone_identity,v_obligation.percentage_basis_points,v_obligation.amount_minor
  );
  if v_snapshot<>rtrim(v_obligation.commercial_snapshot_sha256)
     or v_terms.accepted_implementation_amount_minor<>v_obligation.approved_implementation_amount_minor
     or v_event.project_id<>v_obligation.sdf_project_id then
    raise exception using errcode='55000',message='SDF_POST_START_COMMERCIAL_SNAPSHOT_STALE';
  end if;
  v_seller:=jsonb_build_object(
    'legal_name','Lorenzo Bombello','trade_name','Lorenzo Web Solutions',
    'address_line_1','Grote Baan 164 bus 1002','postal_code','9920','city','Lievegem','country_code','BE',
    'enterprise_number','0742.361.487','vat_identification_number','BE 0742.361.487'
  );
  v_customer:=jsonb_build_object(
    'customer_type',v_request.customer_type,'legal_name',coalesce(nullif(btrim(v_request.company),''),v_request.name),
    'contact_name',v_request.name,'email',v_request.email,'billing_email',v_request.billing_email,
    'enterprise_number',v_request.enterprise_number,'vat_identification_number',v_request.vat_number,
    'address_line_1',v_request.billing_address,'postal_code',v_request.billing_postal_code,
    'city',v_request.billing_city,'country_code',v_request.billing_country
  );
  v_bank:=jsonb_build_object('bank','KBC','iban','BE42 7380 5510 8954','bic','KREDBEBB');
  v_payload_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'bank',v_bank,'commercialSnapshotSha256',v_snapshot,'customer',v_customer,
    'invoiceMaster',jsonb_build_object('documentReference',v_master.document_reference,'driveFileId',v_master.drive_file_id,'sha256',rtrim(v_master.document_sha256)),
    'milestoneAmountMinor',v_obligation.amount_minor,'milestoneIdentity',v_obligation.milestone_identity,
    'obligationId',v_obligation.obligation_id,'seller',v_seller
  )::text,'UTF8'),'sha256'),'hex');
  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'candidatePayloadSha256',v_payload_hash,'obligationId',v_obligation.obligation_id
  )::text,'UTF8'),'sha256'),'hex');
  select * into v_existing from public.sdf_post_start_invoice_candidates where creation_idempotency_key=p_idempotency_key;
  if found then
    if rtrim(v_existing.creation_fingerprint)<>v_fingerprint then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT'; end if;
    return jsonb_build_object('candidate_id',v_existing.candidate_id,'candidate_state','PREPARED','invoice_number',null,'was_created',false);
  end if;
  select * into v_existing from public.sdf_post_start_invoice_candidates where obligation_id=p_obligation_id;
  if found then
    if rtrim(v_existing.creation_fingerprint)<>v_fingerprint then raise exception using errcode='P0001',message='SDF_POST_START_CANDIDATE_CONFLICT'; end if;
    return jsonb_build_object('candidate_id',v_existing.candidate_id,'candidate_state','PREPARED','invoice_number',null,'was_created',false);
  end if;
  insert into public.sdf_post_start_invoice_candidates(
    obligation_id,sdf_project_id,quote_request_id,request_kind,application_reference,sdf_package,
    approved_implementation_amount_minor,milestone_identity,percentage_basis_points,net_amount_minor,
    currency,accepted_price_basis,accepted_terms_id,quotation_id,commercial_snapshot_sha256,
    lifecycle_event_id,lifecycle_event_state,lifecycle_evidence_reference,lifecycle_evidence_sha256,
    project_linkage_sha256,invoice_master_reference,invoice_master_drive_file_id,invoice_master_sha256,
    seller_snapshot,customer_snapshot,bank_snapshot,candidate_state,candidate_payload_sha256,
    creation_idempotency_key,creation_fingerprint,prepared_by_operator_id
  ) values (
    v_obligation.obligation_id,v_obligation.sdf_project_id,v_obligation.quote_request_id,'slimme_documentenflow',
    v_request.application_reference,v_obligation.sdf_package,v_obligation.approved_implementation_amount_minor,
    v_obligation.milestone_identity,v_obligation.percentage_basis_points,v_obligation.amount_minor,
    v_obligation.currency,v_obligation.vat_basis,v_obligation.accepted_terms_id,v_obligation.quotation_id,
    v_snapshot,v_obligation.lifecycle_event_id,v_obligation.lifecycle_event_state,
    v_obligation.lifecycle_evidence_reference,rtrim(v_obligation.lifecycle_evidence_sha256),
    rtrim(v_obligation.project_linkage_sha256),v_master.document_reference,v_master.drive_file_id,
    rtrim(v_master.document_sha256),v_seller,v_customer,v_bank,'PREPARED',v_payload_hash,
    p_idempotency_key,v_fingerprint,v_operator.operator_id
  ) returning * into v_candidate;
  return jsonb_build_object('candidate_id',v_candidate.candidate_id,'candidate_state','PREPARED','invoice_number',null,'was_created',true);
end;
$$;

create function public.issue_sdf_post_start_invoice_v1(
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
  v_candidate public.sdf_post_start_invoice_candidates%rowtype;
  v_binding public.sdf_quotation_vat_authority_bindings%rowtype;
  v_master public.sdf_invoice_master_bindings%rowtype;
  v_existing public.sdf_post_start_invoice_issuances%rowtype;
  v_issuance public.sdf_post_start_invoice_issuances%rowtype;
  v_number record;
  v_resolution_year smallint:=(extract(year from clock_timestamp() at time zone 'Europe/Brussels'))::smallint;
  v_fingerprint text;
  v_payload_hash text;
begin
  v_operator:=lws_internal.assert_sdf_post_start_invoice_operator_v1();
  if p_candidate_id is null or p_idempotency_key is null or p_issue_year<>v_resolution_year
     or p_docx_sha256!~'^[0-9a-f]{64}$' or p_docx_bytes<=0
     or (p_pdf_sha256 is null)<>(p_pdf_bytes is null)
     or (p_pdf_sha256 is not null and (p_pdf_sha256!~'^[0-9a-f]{64}$' or p_pdf_bytes<=0)) then
    raise exception using errcode='22023',message='SDF_INVOICE_ISSUANCE_INPUT_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_candidate_id::text,0));
  select * into v_candidate from public.sdf_post_start_invoice_candidates where candidate_id=p_candidate_id;
  if not found then raise exception using errcode='23503',message='SDF_POST_START_CANDIDATE_REQUIRED'; end if;
  select * into v_master from public.sdf_invoice_master_bindings where singleton;
  if not found or v_candidate.invoice_master_reference<>v_master.document_reference
     or v_candidate.invoice_master_drive_file_id<>v_master.drive_file_id
     or rtrim(v_candidate.invoice_master_sha256)<>rtrim(v_master.document_sha256) then
    raise exception using errcode='55000',message='SDF_INVOICE_MASTER_STALE';
  end if;
  select * into v_binding from public.sdf_quotation_vat_authority_bindings where quotation_id=v_candidate.quotation_id;
  if not found then raise exception using errcode='P0001',message='QUOTATION_VAT_CONTEXT_REQUIRED'; end if;
  if v_binding.quote_request_id<>v_candidate.quote_request_id or v_binding.vat_treatment<>'EXEMPT'
     or v_binding.rate_semantics<>'NOT_APPLICABLE' or v_binding.invoice_literal<>'Bijzondere vrijstellingsregeling van belasting' then
    raise exception using errcode='P0001',message='SDF_VAT_AUTHORITY_MISMATCH';
  end if;
  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'candidateId',p_candidate_id,'candidatePayloadSha256',rtrim(v_candidate.candidate_payload_sha256),
    'docxBytes',p_docx_bytes,'docxSha256',p_docx_sha256,'issueYear',p_issue_year,
    'pdfBytes',p_pdf_bytes,'pdfSha256',p_pdf_sha256,'vatAuthoritySha256',rtrim(v_binding.vat_authority_sha256)
  )::text,'UTF8'),'sha256'),'hex');
  select * into v_existing from public.sdf_post_start_invoice_issuances where issuance_idempotency_key=p_idempotency_key;
  if found then
    if rtrim(v_existing.issuance_fingerprint)<>v_fingerprint then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT'; end if;
    return jsonb_build_object('issuance_id',v_existing.issuance_id,'invoice_number',v_existing.invoice_number,'was_created',false);
  end if;
  select * into v_existing from public.sdf_post_start_invoice_issuances where candidate_id=p_candidate_id;
  if found then
    if rtrim(v_existing.issuance_fingerprint)<>v_fingerprint then raise exception using errcode='P0001',message='SDF_POST_START_ISSUANCE_CONFLICT'; end if;
    return jsonb_build_object('issuance_id',v_existing.issuance_id,'invoice_number',v_existing.invoice_number,'was_created',false);
  end if;
  select * into strict v_number from public.allocate_sdf_invoice_number_v1(p_issue_year);
  v_payload_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'candidatePayloadSha256',rtrim(v_candidate.candidate_payload_sha256),'grossAmountMinor',v_candidate.net_amount_minor,
    'invoiceLiteral',v_binding.invoice_literal,'invoiceNumber',v_number.invoice_number,
    'netAmountMinor',v_candidate.net_amount_minor,'vatAmountMinor',0,'vatTreatment',v_binding.vat_treatment
  )::text,'UTF8'),'sha256'),'hex');
  insert into public.sdf_post_start_invoice_issuances(
    candidate_id,obligation_id,sdf_project_id,quote_request_id,request_kind,sdf_package,
    approved_implementation_amount_minor,milestone_identity,percentage_basis_points,net_amount_minor,
    currency,accepted_terms_id,quotation_id,commercial_snapshot_sha256,lifecycle_event_id,
    lifecycle_event_state,lifecycle_evidence_reference,lifecycle_evidence_sha256,project_linkage_sha256,
    invoice_master_reference,invoice_master_drive_file_id,invoice_master_sha256,invoice_number,issue_year,
    sequence,issuance_state,vat_decision_authority_id,vat_authority_version,vat_authority_sha256,
    vat_treatment,rate_semantics,vat_rate_basis_points,invoice_literal,vat_amount_minor,gross_amount_minor,
    issuance_payload_sha256,docx_sha256,docx_bytes,pdf_sha256,pdf_bytes,issuance_idempotency_key,
    issuance_fingerprint,issued_by_operator_id
  ) values (
    v_candidate.candidate_id,v_candidate.obligation_id,v_candidate.sdf_project_id,v_candidate.quote_request_id,
    'slimme_documentenflow',v_candidate.sdf_package,v_candidate.approved_implementation_amount_minor,
    v_candidate.milestone_identity,v_candidate.percentage_basis_points,v_candidate.net_amount_minor,
    v_candidate.currency,v_candidate.accepted_terms_id,v_candidate.quotation_id,
    rtrim(v_candidate.commercial_snapshot_sha256),v_candidate.lifecycle_event_id,v_candidate.lifecycle_event_state,
    v_candidate.lifecycle_evidence_reference,rtrim(v_candidate.lifecycle_evidence_sha256),
    rtrim(v_candidate.project_linkage_sha256),v_candidate.invoice_master_reference,
    v_candidate.invoice_master_drive_file_id,rtrim(v_candidate.invoice_master_sha256),v_number.invoice_number,
    p_issue_year,v_number.sequence,'ISSUED',v_binding.vat_decision_authority_id,v_binding.vat_authority_version,
    rtrim(v_binding.vat_authority_sha256),v_binding.vat_treatment,v_binding.rate_semantics,0,
    v_binding.invoice_literal,0,v_candidate.net_amount_minor,v_payload_hash,p_docx_sha256,p_docx_bytes,
    p_pdf_sha256,p_pdf_bytes,p_idempotency_key,v_fingerprint,v_operator.operator_id
  ) returning * into v_issuance;
  return jsonb_build_object('issuance_id',v_issuance.issuance_id,'invoice_number',v_issuance.invoice_number,'was_created',true);
end;
$$;

create trigger trg_sdf_post_start_milestone_obligations_immutable
before update or delete on public.sdf_post_start_milestone_obligations
for each row execute function public.prevent_sdf_invoice_foundation_mutation_v1();
create trigger trg_sdf_post_start_invoice_candidates_immutable
before update or delete on public.sdf_post_start_invoice_candidates
for each row execute function public.prevent_sdf_invoice_foundation_mutation_v1();
create trigger trg_sdf_post_start_invoice_issuances_immutable
before update or delete on public.sdf_post_start_invoice_issuances
for each row execute function public.prevent_sdf_invoice_foundation_mutation_v1();

alter table public.sdf_post_start_milestone_obligations enable row level security;
alter table public.sdf_post_start_milestone_obligations force row level security;
alter table public.sdf_post_start_invoice_candidates enable row level security;
alter table public.sdf_post_start_invoice_candidates force row level security;
alter table public.sdf_post_start_invoice_issuances enable row level security;
alter table public.sdf_post_start_invoice_issuances force row level security;

revoke all privileges on table public.sdf_post_start_milestone_obligations,
  public.sdf_post_start_invoice_candidates,public.sdf_post_start_invoice_issuances
  from public,anon,authenticated,service_role;
revoke all on function lws_internal.assert_sdf_post_start_invoice_operator_v1() from public,anon,authenticated,service_role;
revoke all on function lws_internal.calculate_sdf_post_start_commercial_snapshot_v1(
  public.sdf_accepted_commercial_terms,public.sdf_project_lifecycle_events,text,smallint,bigint
) from public,anon,authenticated,service_role;
revoke all on function public.create_sdf_post_start_milestone_obligation_v1(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.prepare_sdf_post_start_invoice_candidate_v1(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.issue_sdf_post_start_invoice_v1(uuid,smallint,uuid,text,bigint,text,bigint) from public,anon,authenticated,service_role;
grant execute on function public.create_sdf_post_start_milestone_obligation_v1(uuid,uuid) to authenticated;
grant execute on function public.prepare_sdf_post_start_invoice_candidate_v1(uuid,uuid) to authenticated;
grant execute on function public.issue_sdf_post_start_invoice_v1(uuid,smallint,uuid,text,bigint,text,bigint) to authenticated;

comment on table public.sdf_post_start_milestone_obligations is
  'Immutable EXPECTED M2/M3 authority created only from canonical PHASE_A_CONFIRMED or PHASE_B_CONFIRMED lifecycle evidence. It is not invoice, receipt, reconciliation, recurring billing, or operational activation evidence.';
comment on table public.sdf_post_start_invoice_issuances is
  'Immutable M2/M3 ISSUED evidence reusing the M1 invoice number, master, VAT, authorization, and audit authorities. ISSUED never implies RECEIVED or RECONCILED.';