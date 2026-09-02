create table public.sdf_project_phase_acceptance_capabilities (
  capability_id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.sdf_projects(project_id) on delete restrict,
  quote_request_id uuid not null references public.quote_requests(id) on delete restrict,
  request_kind text not null check (request_kind = 'slimme_documentenflow'),
  target_state text not null check (target_state in ('PHASE_A_CONFIRMED','PHASE_B_CONFIRMED')),
  document_reference text not null check (
    nullif(btrim(document_reference),'') is not null
    and document_reference !~ '^[A-Za-z][A-Za-z0-9+.-]*://'
    and position('?' in document_reference) = 0
    and position('#' in document_reference) = 0
  ),
  document_sha256 char(64) not null check (document_sha256 ~ '^[0-9a-f]{64}$'),
  project_linkage_sha256 char(64) not null check (project_linkage_sha256 ~ '^[0-9a-f]{64}$'),
  token_digest char(64) not null unique check (token_digest ~ '^[0-9a-f]{64}$'),
  capability_version smallint not null check (capability_version = 1),
  status text not null check (status in ('ACTIVE','CONSUMED','REVOKED')),
  expires_at timestamptz not null,
  lifecycle_event_id uuid,
  consumed_request_fingerprint char(64) check (
    consumed_request_fingerprint is null or consumed_request_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  consumed_at timestamptz,
  revoked_at timestamptz,
  revoked_by_operator_id uuid references public.commercial_operators(operator_id) on delete restrict,
  revocation_reason text,
  created_by_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint sdf_project_phase_capability_identity unique (project_id,target_state,capability_id)
);

create unique index sdf_project_phase_one_active_capability
on public.sdf_project_phase_acceptance_capabilities(project_id,target_state)
where status = 'ACTIVE';

create table public.sdf_project_phase_acceptance_capability_operations (
  idempotency_key uuid primary key,
  operation_type text not null check (operation_type in ('CREATE','REVOKE')),
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  capability_id uuid not null references public.sdf_project_phase_acceptance_capabilities(capability_id) on delete restrict,
  actor_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

create table public.sdf_project_lifecycle_events (
  lifecycle_event_id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.sdf_projects(project_id) on delete restrict,
  quote_request_id uuid not null references public.quote_requests(id) on delete restrict,
  request_kind text not null check (request_kind = 'slimme_documentenflow'),
  accepted_terms_id uuid not null references public.sdf_accepted_commercial_terms(accepted_terms_id) on delete restrict,
  quotation_id uuid not null references public.sdf_quotation_acceptances(quotation_id) on delete restrict,
  project_linkage_sha256 char(64) not null check (project_linkage_sha256 ~ '^[0-9a-f]{64}$'),
  previous_state text not null check (previous_state in ('PROJECT_STARTED','PHASE_A_CONFIRMED','PHASE_B_CONFIRMED')),
  new_state text not null check (new_state in ('PHASE_A_CONFIRMED','PHASE_B_CONFIRMED','OPERATIONAL_ACTIVATED')),
  start_authority_id uuid not null references public.sdf_m1_project_start_authorities(start_authority_id) on delete restrict,
  predecessor_event_id uuid references public.sdf_project_lifecycle_events(lifecycle_event_id) on delete restrict,
  capability_id uuid references public.sdf_project_phase_acceptance_capabilities(capability_id) on delete restrict,
  actor_type text not null check (actor_type in ('CUSTOMER','OWNER')),
  actor_operator_id uuid references public.commercial_operators(operator_id) on delete restrict,
  actor_identity jsonb not null,
  occurred_at timestamptz not null,
  evidence_reference text not null check (
    nullif(btrim(evidence_reference),'') is not null
    and evidence_reference !~ '^[A-Za-z][A-Za-z0-9+.-]*://'
    and position('?' in evidence_reference) = 0
    and position('#' in evidence_reference) = 0
  ),
  evidence_sha256 char(64) not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  idempotency_key uuid not null unique,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  audit_metadata jsonb not null,
  created_at timestamptz not null,
  constraint sdf_project_lifecycle_canonical_state unique (project_id,new_state),
  constraint sdf_project_lifecycle_timestamp_coherent check (created_at = occurred_at),
  constraint sdf_project_lifecycle_transition_valid check (
    (previous_state='PROJECT_STARTED' and new_state='PHASE_A_CONFIRMED')
    or (previous_state='PHASE_A_CONFIRMED' and new_state='PHASE_B_CONFIRMED')
    or (previous_state='PHASE_B_CONFIRMED' and new_state='OPERATIONAL_ACTIVATED')
  ),
  constraint sdf_project_lifecycle_actor_valid check (
    (
      new_state in ('PHASE_A_CONFIRMED','PHASE_B_CONFIRMED')
      and actor_type='CUSTOMER' and actor_operator_id is null and capability_id is not null
    )
    or (
      new_state='OPERATIONAL_ACTIVATED'
      and actor_type='OWNER' and actor_operator_id is not null and capability_id is null
    )
  ),
  constraint sdf_project_lifecycle_audit_safe check (
    jsonb_typeof(actor_identity)='object'
    and jsonb_typeof(audit_metadata)='object'
    and not (actor_identity ?| array['token','token_digest','access_token','service_role_key'])
    and not (audit_metadata ?| array['token','token_digest','access_token','service_role_key'])
  )
);

alter table public.sdf_project_phase_acceptance_capabilities
  add constraint sdf_project_phase_capability_event_fk
    foreign key (lifecycle_event_id)
    references public.sdf_project_lifecycle_events(lifecycle_event_id) on delete restrict,
  add constraint sdf_project_phase_capability_state_valid check (
    (
      status='ACTIVE' and lifecycle_event_id is null
      and consumed_request_fingerprint is null and consumed_at is null
      and revoked_at is null and revoked_by_operator_id is null and revocation_reason is null
    )
    or (
      status='CONSUMED' and lifecycle_event_id is not null
      and consumed_request_fingerprint is not null and consumed_at is not null
      and revoked_at is null and revoked_by_operator_id is null and revocation_reason is null
    )
    or (
      status='REVOKED' and lifecycle_event_id is null
      and consumed_request_fingerprint is null and consumed_at is null
      and revoked_at is not null and revoked_by_operator_id is not null
      and nullif(btrim(revocation_reason),'') is not null
    )
  );

create function lws_internal.assert_sdf_lifecycle_owner_v1()
returns public.commercial_operators
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
begin
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = auth.uid();
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role <> 'owner' then
    raise exception using errcode = '42501', message = 'SDF_LIFECYCLE_AUTHORITY_DENIED';
  end if;
  return v_operator;
end;
$$;

create function lws_internal.assert_sdf_lifecycle_reader_v1()
returns public.commercial_operators
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
begin
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = auth.uid();
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner','admin') then
    raise exception using errcode = '42501', message = 'SDF_LIFECYCLE_AUTHORITY_DENIED';
  end if;
  return v_operator;
end;
$$;

create function lws_internal.resolve_sdf_project_lifecycle_context_v1(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_project public.sdf_projects%rowtype;
  v_request public.quote_requests%rowtype;
  v_start public.sdf_m1_project_start_authorities%rowtype;
  v_candidate public.sdf_m1_invoice_candidates%rowtype;
  v_issuance public.sdf_m1_invoice_issuances%rowtype;
  v_terms public.sdf_accepted_commercial_terms%rowtype;
  v_acceptance public.sdf_quotation_acceptances%rowtype;
  v_linkage_sha256 text;
begin
  select * into v_project from public.sdf_projects where project_id = p_project_id;
  if not found then
    raise exception using errcode = '23503', message = 'SDF_PROJECT_REQUIRED';
  end if;
  select * into strict v_request from public.quote_requests where id = v_project.quote_request_id;
  if v_request.request_kind <> 'slimme_documentenflow' then
    raise exception using errcode = '23514', message = 'SDF_REQUEST_KIND_REQUIRED';
  end if;

  select * into v_start
  from public.sdf_m1_project_start_authorities
  where project_id = p_project_id and authority_state = 'START_ALLOWED';
  if not found then
    return jsonb_build_object(
      'project_id',v_project.project_id,
      'quote_request_id',v_project.quote_request_id,
      'request_kind',v_request.request_kind,
      'current_state','NOT_STARTED'
    );
  end if;

  select * into strict v_candidate
  from public.sdf_m1_invoice_candidates where candidate_id = v_start.candidate_id;
  select * into strict v_issuance
  from public.sdf_m1_invoice_issuances where issuance_id = v_start.issuance_id;
  select * into strict v_terms
  from public.sdf_accepted_commercial_terms where accepted_terms_id = v_candidate.accepted_terms_id;
  select * into strict v_acceptance
  from public.sdf_quotation_acceptances where quotation_id = v_candidate.quotation_id;

  if v_start.quote_request_id <> v_project.quote_request_id
     or v_candidate.quote_request_id <> v_project.quote_request_id
     or v_candidate.accepted_terms_id <> v_terms.accepted_terms_id
     or v_candidate.quotation_id <> v_terms.quotation_id
     or v_issuance.candidate_id <> v_candidate.candidate_id
     or rtrim(v_start.candidate_payload_sha256) <> rtrim(v_candidate.candidate_payload_sha256)
     or rtrim(v_start.issuance_payload_sha256) <> rtrim(v_issuance.issuance_payload_sha256) then
    raise exception using errcode = '55000', message = 'SDF_PROJECT_LINKAGE_STALE';
  end if;

  v_linkage_sha256 := encode(extensions.digest(convert_to(jsonb_build_object(
    'acceptedTermsId',v_terms.accepted_terms_id,
    'candidateId',v_candidate.candidate_id,
    'candidatePayloadSha256',rtrim(v_candidate.candidate_payload_sha256),
    'issuanceId',v_issuance.issuance_id,
    'issuancePayloadSha256',rtrim(v_issuance.issuance_payload_sha256),
    'projectId',v_project.project_id,
    'quotationAcceptanceSha256',rtrim(v_acceptance.document_sha256),
    'quotationId',v_acceptance.quotation_id,
    'quoteRequestId',v_project.quote_request_id,
    'requestKind',v_request.request_kind,
    'startAuthorityId',v_start.start_authority_id
  )::text,'UTF8'),'sha256'),'hex');

  return jsonb_build_object(
    'project_id',v_project.project_id,
    'quote_request_id',v_project.quote_request_id,
    'request_kind',v_request.request_kind,
    'accepted_terms_id',v_terms.accepted_terms_id,
    'quotation_id',v_acceptance.quotation_id,
    'start_authority_id',v_start.start_authority_id,
    'project_linkage_sha256',v_linkage_sha256
  );
end;
$$;

create function lws_internal.sdf_project_lifecycle_state_v1(p_project_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_context jsonb;
begin
  v_context := lws_internal.resolve_sdf_project_lifecycle_context_v1(p_project_id);
  if v_context->>'current_state' = 'NOT_STARTED' then return 'NOT_STARTED'; end if;
  if exists(select 1 from public.sdf_project_lifecycle_events where project_id=p_project_id and new_state='OPERATIONAL_ACTIVATED') then
    return 'OPERATIONAL_ACTIVATED';
  end if;
  if exists(select 1 from public.sdf_project_lifecycle_events where project_id=p_project_id and new_state='PHASE_B_CONFIRMED') then
    return 'PHASE_B_CONFIRMED';
  end if;
  if exists(select 1 from public.sdf_project_lifecycle_events where project_id=p_project_id and new_state='PHASE_A_CONFIRMED') then
    return 'PHASE_A_CONFIRMED';
  end if;
  return 'PROJECT_STARTED';
end;
$$;

create function public.get_sdf_project_lifecycle_v1(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_context jsonb;
  v_state text;
  v_latest_event_id uuid;
begin
  perform lws_internal.assert_sdf_lifecycle_reader_v1();
  v_context := lws_internal.resolve_sdf_project_lifecycle_context_v1(p_project_id);
  v_state := lws_internal.sdf_project_lifecycle_state_v1(p_project_id);
  select lifecycle_event_id into v_latest_event_id
  from public.sdf_project_lifecycle_events
  where project_id=p_project_id
  order by case new_state
    when 'PHASE_A_CONFIRMED' then 1
    when 'PHASE_B_CONFIRMED' then 2
    when 'OPERATIONAL_ACTIVATED' then 3 end desc
  limit 1;
  return jsonb_build_object(
    'project_id',p_project_id,
    'quote_request_id',v_context->>'quote_request_id',
    'request_kind',v_context->>'request_kind',
    'current_state',v_state,
    'start_authority_id',v_context->>'start_authority_id',
    'latest_lifecycle_event_id',v_latest_event_id,
    'project_linkage_sha256',v_context->>'project_linkage_sha256'
  );
end;
$$;

create function public.guard_sdf_project_lifecycle_event_v1()
returns trigger
language plpgsql
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_context jsonb;
  v_state text;
  v_predecessor_id uuid;
begin
  v_context := lws_internal.resolve_sdf_project_lifecycle_context_v1(new.project_id);
  v_state := lws_internal.sdf_project_lifecycle_state_v1(new.project_id);
  if new.quote_request_id <> (v_context->>'quote_request_id')::uuid
     or new.request_kind <> v_context->>'request_kind'
     or new.accepted_terms_id <> (v_context->>'accepted_terms_id')::uuid
     or new.quotation_id <> (v_context->>'quotation_id')::uuid
     or new.start_authority_id <> (v_context->>'start_authority_id')::uuid
     or rtrim(new.project_linkage_sha256) <> v_context->>'project_linkage_sha256'
     or new.previous_state <> v_state then
    raise exception using errcode = '55000', message = 'SDF_PROJECT_LINKAGE_STALE';
  end if;

  if new.new_state='PHASE_A_CONFIRMED' and new.previous_state='PROJECT_STARTED' then
    if new.predecessor_event_id is not null then
      raise exception using errcode = '23514', message = 'SDF_LIFECYCLE_PREDECESSOR_INVALID';
    end if;
  elsif new.new_state='PHASE_B_CONFIRMED' and new.previous_state='PHASE_A_CONFIRMED' then
    select lifecycle_event_id into v_predecessor_id from public.sdf_project_lifecycle_events
    where project_id=new.project_id and new_state='PHASE_A_CONFIRMED';
    if new.predecessor_event_id is distinct from v_predecessor_id then
      raise exception using errcode = '23514', message = 'SDF_LIFECYCLE_PREDECESSOR_INVALID';
    end if;
  elsif new.new_state='OPERATIONAL_ACTIVATED' and new.previous_state='PHASE_B_CONFIRMED' then
    select lifecycle_event_id into v_predecessor_id from public.sdf_project_lifecycle_events
    where project_id=new.project_id and new_state='PHASE_B_CONFIRMED';
    if new.predecessor_event_id is distinct from v_predecessor_id then
      raise exception using errcode = '23514', message = 'SDF_LIFECYCLE_PREDECESSOR_INVALID';
    end if;
  else
    raise exception using errcode = '55000', message = 'SDF_LIFECYCLE_INVALID_TRANSITION';
  end if;
  return new;
end;
$$;

create function public.guard_sdf_project_phase_capability_mutation_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_transition text := current_setting('lws.sdf_phase_capability_transition',true);
begin
  if tg_op='DELETE' then
    raise exception using errcode = '55000', message = 'SDF_PROJECT_LIFECYCLE_IMMUTABLE';
  end if;
  if old.capability_id <> new.capability_id
     or old.project_id <> new.project_id
     or old.quote_request_id <> new.quote_request_id
     or old.request_kind <> new.request_kind
     or old.target_state <> new.target_state
     or old.document_reference <> new.document_reference
     or old.document_sha256 <> new.document_sha256
     or old.project_linkage_sha256 <> new.project_linkage_sha256
     or old.token_digest <> new.token_digest
     or old.capability_version <> new.capability_version
     or old.expires_at <> new.expires_at
     or old.created_by_operator_id <> new.created_by_operator_id
     or old.created_at <> new.created_at then
    raise exception using errcode = '55000', message = 'SDF_PROJECT_LIFECYCLE_IMMUTABLE';
  end if;
  if v_transition='CONSUME' and old.status='ACTIVE' and new.status='CONSUMED' then return new; end if;
  if v_transition='REVOKE' and old.status='ACTIVE' and new.status='REVOKED' then return new; end if;
  raise exception using errcode = '55000', message = 'SDF_PROJECT_LIFECYCLE_IMMUTABLE';
end;
$$;

create function public.prevent_sdf_project_lifecycle_mutation_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'SDF_PROJECT_LIFECYCLE_IMMUTABLE';
end;
$$;

create trigger trg_sdf_project_lifecycle_events_guard
before insert on public.sdf_project_lifecycle_events
for each row execute function public.guard_sdf_project_lifecycle_event_v1();
create trigger trg_sdf_project_lifecycle_events_immutable
before update or delete on public.sdf_project_lifecycle_events
for each row execute function public.prevent_sdf_project_lifecycle_mutation_v1();
create trigger trg_sdf_project_phase_capabilities_guard
before update or delete on public.sdf_project_phase_acceptance_capabilities
for each row execute function public.guard_sdf_project_phase_capability_mutation_v1();
create trigger trg_sdf_project_phase_capability_operations_immutable
before update or delete on public.sdf_project_phase_acceptance_capability_operations
for each row execute function public.prevent_sdf_project_lifecycle_mutation_v1();

create function public.prepare_sdf_project_phase_acceptance_v1(
  p_project_id uuid,
  p_target_state text,
  p_document_reference text,
  p_document_sha256 text,
  p_token_digest text,
  p_requested_expires_at timestamptz,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_context jsonb;
  v_state text;
  v_expected_state text;
  v_fingerprint text;
  v_operation public.sdf_project_phase_acceptance_capability_operations%rowtype;
  v_capability public.sdf_project_phase_acceptance_capabilities%rowtype;
begin
  v_operator := lws_internal.assert_sdf_lifecycle_owner_v1();
  if p_project_id is null or p_target_state not in ('PHASE_A_CONFIRMED','PHASE_B_CONFIRMED')
     or nullif(btrim(p_document_reference),'') is null
     or p_document_reference ~ '^[A-Za-z][A-Za-z0-9+.-]*://'
     or position('?' in p_document_reference)>0 or position('#' in p_document_reference)>0
     or p_document_sha256 !~ '^[0-9a-f]{64}$' or p_token_digest !~ '^[0-9a-f]{64}$'
     or p_requested_expires_at is null or p_requested_expires_at <= clock_timestamp()
     or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'SDF_PHASE_ACCEPTANCE_INPUT_INVALID';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_project_id::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  v_context := lws_internal.resolve_sdf_project_lifecycle_context_v1(p_project_id);
  v_state := lws_internal.sdf_project_lifecycle_state_v1(p_project_id);
  if v_state='NOT_STARTED' then
    raise exception using errcode = '55000', message = 'SDF_PROJECT_NOT_STARTED';
  end if;
  v_expected_state := case p_target_state
    when 'PHASE_A_CONFIRMED' then 'PROJECT_STARTED'
    when 'PHASE_B_CONFIRMED' then 'PHASE_A_CONFIRMED' end;
  if v_state <> v_expected_state then
    raise exception using errcode = '55000', message = 'SDF_LIFECYCLE_INVALID_TRANSITION';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'documentReference',btrim(p_document_reference),
    'documentSha256',p_document_sha256,
    'expiresAt',p_requested_expires_at,
    'projectId',p_project_id,
    'projectLinkageSha256',v_context->>'project_linkage_sha256',
    'targetState',p_target_state,
    'tokenDigest',p_token_digest
  )::text,'UTF8'),'sha256'),'hex');
  select * into v_operation from public.sdf_project_phase_acceptance_capability_operations
  where idempotency_key=p_idempotency_key;
  if found then
    if v_operation.operation_type<>'CREATE' or rtrim(v_operation.request_fingerprint)<>v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    select * into strict v_capability from public.sdf_project_phase_acceptance_capabilities
    where capability_id=v_operation.capability_id;
    return jsonb_build_object('capability_id',v_capability.capability_id,'was_created',false);
  end if;
  select * into v_capability from public.sdf_project_phase_acceptance_capabilities
  where project_id=p_project_id and target_state=p_target_state and status='ACTIVE';
  if found then
    if rtrim(v_capability.project_linkage_sha256)<>v_context->>'project_linkage_sha256'
       or rtrim(v_capability.token_digest)<>p_token_digest
       or v_capability.document_reference<>btrim(p_document_reference)
       or rtrim(v_capability.document_sha256)<>p_document_sha256
       or v_capability.expires_at<>p_requested_expires_at then
      raise exception using errcode = 'P0001', message = 'ACTIVE_CAPABILITY_EXISTS';
    end if;
    return jsonb_build_object('capability_id',v_capability.capability_id,'was_created',false);
  end if;

  insert into public.sdf_project_phase_acceptance_capabilities(
    project_id,quote_request_id,request_kind,target_state,document_reference,document_sha256,
    project_linkage_sha256,token_digest,capability_version,status,expires_at,created_by_operator_id
  ) values (
    p_project_id,(v_context->>'quote_request_id')::uuid,v_context->>'request_kind',p_target_state,
    btrim(p_document_reference),p_document_sha256,v_context->>'project_linkage_sha256',p_token_digest,
    1,'ACTIVE',p_requested_expires_at,v_operator.operator_id
  ) returning * into v_capability;
  insert into public.sdf_project_phase_acceptance_capability_operations(
    idempotency_key,operation_type,request_fingerprint,capability_id,actor_operator_id
  ) values (p_idempotency_key,'CREATE',v_fingerprint,v_capability.capability_id,v_operator.operator_id);
  return jsonb_build_object('capability_id',v_capability.capability_id,'was_created',true);
end;
$$;

create function public.resolve_sdf_project_phase_acceptance_v1(p_token_digest text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_capability public.sdf_project_phase_acceptance_capabilities%rowtype;
begin
  if p_token_digest !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('state','INVALID_OR_EXPIRED_LINK');
  end if;
  select * into v_capability from public.sdf_project_phase_acceptance_capabilities
  where token_digest=p_token_digest;
  if not found or v_capability.status='REVOKED'
     or (v_capability.status='ACTIVE' and clock_timestamp()>=v_capability.expires_at) then
    return jsonb_build_object('state','INVALID_OR_EXPIRED_LINK');
  end if;
  if v_capability.status='CONSUMED' then
    return jsonb_build_object('state','ACCEPTED','lifecycle_event_id',v_capability.lifecycle_event_id);
  end if;
  return jsonb_build_object(
    'state','ACTIVE','target_state',v_capability.target_state,
    'document_reference',v_capability.document_reference,
    'document_sha256',rtrim(v_capability.document_sha256),
    'expires_at',v_capability.expires_at
  );
end;
$$;

create function public.submit_sdf_project_phase_acceptance_v1(
  p_token_digest text,
  p_accepting_name text,
  p_accepting_email text,
  p_accepting_organization text,
  p_accepting_role text,
  p_authority_declaration boolean,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_capability public.sdf_project_phase_acceptance_capabilities%rowtype;
  v_project public.sdf_projects%rowtype;
  v_context jsonb;
  v_state text;
  v_expected_state text;
  v_predecessor_id uuid;
  v_fingerprint text;
  v_event public.sdf_project_lifecycle_events%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  if p_token_digest !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_accepting_name),'') is null
     or lower(btrim(p_accepting_email)) !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     or not coalesce(p_authority_declaration,false) or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'SDF_PHASE_ACCEPTANCE_SIGNATURE_INVALID';
  end if;
  select * into v_capability from public.sdf_project_phase_acceptance_capabilities
  where token_digest=p_token_digest for update;
  if not found or v_capability.status='REVOKED'
     or (v_capability.status='ACTIVE' and v_now>=v_capability.expires_at) then
    raise exception using errcode = '42501', message = 'SDF_PHASE_ACCEPTANCE_CAPABILITY_INVALID';
  end if;
  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'acceptingEmail',lower(btrim(p_accepting_email)),
    'acceptingName',btrim(p_accepting_name),
    'acceptingOrganization',nullif(btrim(p_accepting_organization),''),
    'acceptingRole',nullif(btrim(p_accepting_role),''),
    'authorityDeclaration',p_authority_declaration,
    'capabilityId',v_capability.capability_id,
    'documentSha256',rtrim(v_capability.document_sha256),
    'targetState',v_capability.target_state
  )::text,'UTF8'),'sha256'),'hex');
  if v_capability.status='CONSUMED' then
    if rtrim(v_capability.consumed_request_fingerprint)<>v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('lifecycle_event_id',v_capability.lifecycle_event_id,'was_created',false);
  end if;

  select * into strict v_project from public.sdf_projects where project_id=v_capability.project_id;
  if v_project.quote_request_id<>v_capability.quote_request_id then
    raise exception using errcode = '23514', message = 'SDF_PROJECT_LINKAGE_MISMATCH';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_capability.project_id::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  v_context := lws_internal.resolve_sdf_project_lifecycle_context_v1(v_capability.project_id);
  if v_context->>'project_linkage_sha256'<>rtrim(v_capability.project_linkage_sha256) then
    raise exception using errcode = '55000', message = 'SDF_PROJECT_LINKAGE_STALE';
  end if;
  v_state := lws_internal.sdf_project_lifecycle_state_v1(v_capability.project_id);
  v_expected_state := case v_capability.target_state
    when 'PHASE_A_CONFIRMED' then 'PROJECT_STARTED'
    when 'PHASE_B_CONFIRMED' then 'PHASE_A_CONFIRMED' end;
  if v_state<>v_expected_state then
    raise exception using errcode = '55000', message = 'SDF_LIFECYCLE_INVALID_TRANSITION';
  end if;
  if v_capability.target_state='PHASE_B_CONFIRMED' then
    select lifecycle_event_id into strict v_predecessor_id
    from public.sdf_project_lifecycle_events
    where project_id=v_capability.project_id and new_state='PHASE_A_CONFIRMED';
  end if;
  select * into v_event from public.sdf_project_lifecycle_events
  where idempotency_key=p_idempotency_key;
  if found then
    if rtrim(v_event.request_fingerprint)<>v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('lifecycle_event_id',v_event.lifecycle_event_id,'was_created',false);
  end if;

  insert into public.sdf_project_lifecycle_events(
    project_id,quote_request_id,request_kind,accepted_terms_id,quotation_id,project_linkage_sha256,
    previous_state,new_state,start_authority_id,predecessor_event_id,capability_id,actor_type,
    actor_identity,occurred_at,evidence_reference,evidence_sha256,idempotency_key,request_fingerprint,
    audit_metadata,created_at
  ) values (
    v_capability.project_id,v_capability.quote_request_id,v_capability.request_kind,
    (v_context->>'accepted_terms_id')::uuid,(v_context->>'quotation_id')::uuid,
    v_context->>'project_linkage_sha256',v_expected_state,v_capability.target_state,
    (v_context->>'start_authority_id')::uuid,v_predecessor_id,v_capability.capability_id,'CUSTOMER',
    jsonb_build_object(
      'name',btrim(p_accepting_name),'email',lower(btrim(p_accepting_email)),
      'organization',nullif(btrim(p_accepting_organization),''),
      'role',nullif(btrim(p_accepting_role),''),'authority_declaration',true
    ),v_now,v_capability.document_reference,v_capability.document_sha256,p_idempotency_key,v_fingerprint,
    jsonb_build_object('capabilityVersion',v_capability.capability_version,'acceptanceMode','ACTIVE_SIGNATURE'),v_now
  ) returning * into v_event;
  perform set_config('lws.sdf_phase_capability_transition','CONSUME',true);
  update public.sdf_project_phase_acceptance_capabilities
  set status='CONSUMED',lifecycle_event_id=v_event.lifecycle_event_id,
      consumed_request_fingerprint=v_fingerprint,consumed_at=v_now
  where capability_id=v_capability.capability_id;
  perform set_config('lws.sdf_phase_capability_transition','',true);
  return jsonb_build_object('lifecycle_event_id',v_event.lifecycle_event_id,'was_created',true);
end;
$$;

create function public.revoke_sdf_project_phase_acceptance_v1(
  p_capability_id uuid,
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_capability public.sdf_project_phase_acceptance_capabilities%rowtype;
  v_operation public.sdf_project_phase_acceptance_capability_operations%rowtype;
  v_fingerprint text;
  v_now timestamptz := clock_timestamp();
begin
  v_operator := lws_internal.assert_sdf_lifecycle_owner_v1();
  if p_capability_id is null or nullif(btrim(p_reason),'') is null or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'SDF_PHASE_ACCEPTANCE_REVOCATION_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  select * into v_capability from public.sdf_project_phase_acceptance_capabilities
  where capability_id=p_capability_id for update;
  if not found then raise exception using errcode = '23503', message = 'SDF_PHASE_CAPABILITY_REQUIRED'; end if;
  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'capabilityId',p_capability_id,'reason',btrim(p_reason)
  )::text,'UTF8'),'sha256'),'hex');
  select * into v_operation from public.sdf_project_phase_acceptance_capability_operations
  where idempotency_key=p_idempotency_key;
  if found then
    if v_operation.operation_type<>'REVOKE' or rtrim(v_operation.request_fingerprint)<>v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('capability_id',p_capability_id,'was_revoked',false);
  end if;
  if v_capability.status<>'ACTIVE' then
    raise exception using errcode = '55000', message = 'SDF_PHASE_CAPABILITY_NOT_ACTIVE';
  end if;
  perform set_config('lws.sdf_phase_capability_transition','REVOKE',true);
  update public.sdf_project_phase_acceptance_capabilities
  set status='REVOKED',revoked_at=v_now,revoked_by_operator_id=v_operator.operator_id,
      revocation_reason=btrim(p_reason)
  where capability_id=p_capability_id;
  perform set_config('lws.sdf_phase_capability_transition','',true);
  insert into public.sdf_project_phase_acceptance_capability_operations(
    idempotency_key,operation_type,request_fingerprint,capability_id,actor_operator_id
  ) values (p_idempotency_key,'REVOKE',v_fingerprint,p_capability_id,v_operator.operator_id);
  return jsonb_build_object('capability_id',p_capability_id,'was_revoked',true);
end;
$$;

create function public.activate_sdf_project_operationally_v1(
  p_project_id uuid,
  p_evidence_reference text,
  p_evidence_sha256 text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_context jsonb;
  v_state text;
  v_predecessor public.sdf_project_lifecycle_events%rowtype;
  v_event public.sdf_project_lifecycle_events%rowtype;
  v_fingerprint text;
  v_now timestamptz := clock_timestamp();
begin
  v_operator := lws_internal.assert_sdf_lifecycle_owner_v1();
  if p_project_id is null or nullif(btrim(p_evidence_reference),'') is null
     or p_evidence_reference ~ '^[A-Za-z][A-Za-z0-9+.-]*://'
     or position('?' in p_evidence_reference)>0 or position('#' in p_evidence_reference)>0
     or p_evidence_sha256 !~ '^[0-9a-f]{64}$' or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'SDF_OPERATIONAL_ACTIVATION_INPUT_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_project_id::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,0));
  v_context := lws_internal.resolve_sdf_project_lifecycle_context_v1(p_project_id);
  v_state := lws_internal.sdf_project_lifecycle_state_v1(p_project_id);
  select * into v_predecessor from public.sdf_project_lifecycle_events
  where project_id=p_project_id and new_state='PHASE_B_CONFIRMED';

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'evidenceReference',btrim(p_evidence_reference),
    'evidenceSha256',p_evidence_sha256,
    'phaseBEvidenceSha256',case when v_predecessor.lifecycle_event_id is null then null else rtrim(v_predecessor.evidence_sha256) end,
    'projectId',p_project_id,
    'projectLinkageSha256',v_context->>'project_linkage_sha256'
  )::text,'UTF8'),'sha256'),'hex');
  select * into v_event from public.sdf_project_lifecycle_events where idempotency_key=p_idempotency_key;
  if found then
    if rtrim(v_event.request_fingerprint)<>v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('lifecycle_event_id',v_event.lifecycle_event_id,'was_created',false);
  end if;
  select * into v_event from public.sdf_project_lifecycle_events
  where project_id=p_project_id and new_state='OPERATIONAL_ACTIVATED';
  if found then
    if rtrim(v_event.request_fingerprint)<>v_fingerprint then
      raise exception using errcode = 'P0001', message = 'SDF_OPERATIONAL_ACTIVATION_CONFLICT';
    end if;
    return jsonb_build_object('lifecycle_event_id',v_event.lifecycle_event_id,'was_created',false);
  end if;
  if v_state<>'PHASE_B_CONFIRMED' or v_predecessor.lifecycle_event_id is null then
    raise exception using errcode = '55000', message = 'SDF_LIFECYCLE_INVALID_TRANSITION';
  end if;

  insert into public.sdf_project_lifecycle_events(
    project_id,quote_request_id,request_kind,accepted_terms_id,quotation_id,project_linkage_sha256,
    previous_state,new_state,start_authority_id,predecessor_event_id,actor_type,actor_operator_id,
    actor_identity,occurred_at,evidence_reference,evidence_sha256,idempotency_key,request_fingerprint,
    audit_metadata,created_at
  ) values (
    p_project_id,(v_context->>'quote_request_id')::uuid,v_context->>'request_kind',
    (v_context->>'accepted_terms_id')::uuid,(v_context->>'quotation_id')::uuid,
    v_context->>'project_linkage_sha256','PHASE_B_CONFIRMED','OPERATIONAL_ACTIVATED',
    (v_context->>'start_authority_id')::uuid,v_predecessor.lifecycle_event_id,'OWNER',v_operator.operator_id,
    jsonb_build_object('operator_id',v_operator.operator_id,'role','owner'),v_now,
    btrim(p_evidence_reference),p_evidence_sha256,p_idempotency_key,v_fingerprint,
    jsonb_build_object(
      'phaseBEventId',v_predecessor.lifecycle_event_id,
      'phaseBEvidenceSha256',rtrim(v_predecessor.evidence_sha256),
      'activationMode','OWNER_CONFIRMED'
    ),v_now
  ) returning * into v_event;
  return jsonb_build_object('lifecycle_event_id',v_event.lifecycle_event_id,'was_created',true);
end;
$$;

alter table public.sdf_project_phase_acceptance_capabilities enable row level security;
alter table public.sdf_project_phase_acceptance_capabilities force row level security;
alter table public.sdf_project_phase_acceptance_capability_operations enable row level security;
alter table public.sdf_project_phase_acceptance_capability_operations force row level security;
alter table public.sdf_project_lifecycle_events enable row level security;
alter table public.sdf_project_lifecycle_events force row level security;

revoke all privileges on table public.sdf_project_phase_acceptance_capabilities from public,anon,authenticated,service_role;
revoke all privileges on table public.sdf_project_phase_acceptance_capability_operations from public,anon,authenticated,service_role;
revoke all privileges on table public.sdf_project_lifecycle_events from public,anon,authenticated,service_role;
revoke all on function lws_internal.assert_sdf_lifecycle_owner_v1() from public,anon,authenticated,service_role;
revoke all on function lws_internal.assert_sdf_lifecycle_reader_v1() from public,anon,authenticated,service_role;
revoke all on function lws_internal.resolve_sdf_project_lifecycle_context_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function lws_internal.sdf_project_lifecycle_state_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function public.guard_sdf_project_lifecycle_event_v1() from public,anon,authenticated,service_role;
revoke all on function public.guard_sdf_project_phase_capability_mutation_v1() from public,anon,authenticated,service_role;
revoke all on function public.prevent_sdf_project_lifecycle_mutation_v1() from public,anon,authenticated,service_role;
revoke all on function public.prepare_sdf_project_phase_acceptance_v1(uuid,text,text,text,text,timestamptz,uuid) from public,anon,authenticated,service_role;
revoke all on function public.resolve_sdf_project_phase_acceptance_v1(text) from public,anon,authenticated,service_role;
revoke all on function public.submit_sdf_project_phase_acceptance_v1(text,text,text,text,text,boolean,uuid) from public,anon,authenticated,service_role;
revoke all on function public.revoke_sdf_project_phase_acceptance_v1(uuid,text,uuid) from public,anon,authenticated,service_role;
revoke all on function public.activate_sdf_project_operationally_v1(uuid,text,text,uuid) from public,anon,authenticated,service_role;
revoke all on function public.get_sdf_project_lifecycle_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.prepare_sdf_project_phase_acceptance_v1(uuid,text,text,text,text,timestamptz,uuid) to authenticated;
grant execute on function public.revoke_sdf_project_phase_acceptance_v1(uuid,text,uuid) to authenticated;
grant execute on function public.activate_sdf_project_operationally_v1(uuid,text,text,uuid) to authenticated;
grant execute on function public.get_sdf_project_lifecycle_v1(uuid) to authenticated;
grant execute on function public.resolve_sdf_project_phase_acceptance_v1(text) to service_role;
grant execute on function public.submit_sdf_project_phase_acceptance_v1(text,text,text,text,text,boolean,uuid) to service_role;

comment on table public.sdf_project_lifecycle_events is
  'Immutable SDF-only lifecycle authority after M1 START_ALLOWED. Contains customer-confirmed Phase A/B and owner-confirmed operational activation, never billing or recurring state.';
comment on table public.sdf_project_phase_acceptance_capabilities is
  'Scoped bearer capabilities binding one SDF project phase to an exact delivery/acceptance document reference and SHA-256.';
comment on function public.get_sdf_project_lifecycle_v1(uuid) is
  'Owner/admin canonical projection. PROJECT_STARTED is derived only from the existing M1 START_ALLOWED authority; no duplicate start event exists.';