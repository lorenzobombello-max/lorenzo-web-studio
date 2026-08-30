create type public.sdf_qualification_intake_status as enum (
  'invited', 'in_progress', 'submitted', 'under_review',
  'changes_requested', 'qualification_complete', 'closed'
);

create table public.sdf_qualification_intakes (
  intake_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null unique references public.quote_requests(id) on delete restrict,
  status public.sdf_qualification_intake_status not null default 'invited',
  taxonomy_version text not null default 'sdf_qualification_intake/1.0.0'
    check (taxonomy_version = 'sdf_qualification_intake/1.0.0'),
  customer_capability_digest char(64) not null check (customer_capability_digest ~ '^[0-9a-f]{64}$'),
  customer_capability_encrypted text not null check (customer_capability_encrypted ~ '^v1\.[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{40,}$'),
  customer_capability_expires_at timestamptz not null,
  customer_capability_revoked_at timestamptz,
  invitation_generation integer not null default 1 check (invitation_generation > 0),
  internal_capability_digest char(64) check (internal_capability_digest ~ '^[0-9a-f]{64}$'),
  internal_capability_expires_at timestamptz,
  internal_capability_revoked_at timestamptz,
  draft_answers jsonb not null default '{}'::jsonb check (jsonb_typeof(draft_answers) = 'object'),
  draft_revision bigint not null default 0 check (draft_revision >= 0),
  latest_submission_sequence integer not null default 0 check (latest_submission_sequence >= 0),
  invited_at timestamptz not null default clock_timestamp(),
  submitted_at timestamptz,
  review_started_at timestamptz,
  qualification_completed_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint sdf_qualification_capability_window check (customer_capability_expires_at > created_at)
);

alter table public.quote_request_email_jobs
  add column template_key text,
  add column template_version text,
  add constraint quote_request_email_jobs_sdf_template_authority check (
    (template_key is null and template_version is null)
    or (template_key = 'SDF_REQUEST_RECEIVED_NL_BE_v1' and template_version = 'v1')
  );

create table public.sdf_qualification_intake_submissions (
  submission_id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references public.sdf_qualification_intakes(intake_id) on delete restrict,
  submission_sequence integer not null check (submission_sequence > 0),
  answers jsonb not null,
  taxonomy_version text not null check (taxonomy_version = 'sdf_qualification_intake/1.0.0'),
  payload_sha256 char(64) not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  confirmation_version text not null check (confirmation_version = 'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1'),
  confirmation_sha256 char(64) not null check (confirmation_sha256 ~ '^[0-9a-f]{64}$'),
  submitted_at timestamptz not null default clock_timestamp(),
  unique (intake_id, submission_sequence),
  unique (intake_id, payload_sha256)
);

create table public.sdf_qualification_intake_events (
  event_id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references public.sdf_qualification_intakes(intake_id) on delete restrict,
  event_kind text not null check (event_kind in (
    'INVITED', 'DRAFT_SAVED', 'SUBMITTED', 'REVIEW_STARTED',
    'CHANGES_REQUESTED', 'QUALIFICATION_COMPLETE', 'CLOSED', 'INVITATION_REISSUED'
  )),
  from_status public.sdf_qualification_intake_status,
  to_status public.sdf_qualification_intake_status not null,
  actor_class text not null check (actor_class in ('operator', 'customer', 'system')),
  actor_operator_id uuid references public.commercial_operators(operator_id) on delete restrict,
  submission_sequence integer,
  reason text check (reason is null or char_length(btrim(reason)) between 1 and 2000),
  idempotency_key uuid,
  request_fingerprint char(64) check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  result_snapshot jsonb,
  occurred_at timestamptz not null default clock_timestamp(),
  unique (intake_id, idempotency_key),
  constraint sdf_qualification_command_result_snapshot check (
    (event_kind in ('INVITED','INVITATION_REISSUED') and result_snapshot is not null and jsonb_typeof(result_snapshot)='object')
    or (event_kind not in ('INVITED','INVITATION_REISSUED') and result_snapshot is null)
  )
);

create unique index sdf_qualification_intake_events_idempotency_key
  on public.sdf_qualification_intake_events (idempotency_key)
  where idempotency_key is not null;

create table public.sdf_qualification_intake_email_jobs (
  job_id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references public.sdf_qualification_intakes(intake_id) on delete restrict,
  kind text not null check (kind in ('invitation', 'submitted', 'more_information')),
  template_version text not null check (template_version in (
    'SDF_QUALIFICATION_INTAKE_INVITATION_NL_BE_v1',
    'SDF_QUALIFICATION_SUBMITTED_INTERNAL_NL_BE_v1',
    'SDF_QUALIFICATION_MORE_INFORMATION_NL_BE_v1'
  )),
  invitation_generation integer,
  submission_sequence integer,
  status public.quote_request_email_status not null default 'pending',
  attempt_count integer not null default 0 check (attempt_count between 0 and 20),
  max_attempts integer not null default 5 check (max_attempts between 1 and 20),
  next_attempt_at timestamptz not null default clock_timestamp(),
  locked_at timestamptz,
  delivery_lease_token uuid,
  delivery_lease_expires_at timestamptz,
  sent_at timestamptz,
  provider_message_id text,
  last_error_code text,
  idempotency_key uuid not null,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  encrypted_capability text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (idempotency_key)
);

create unique index sdf_qualification_email_jobs_semantic_key
  on public.sdf_qualification_intake_email_jobs (
    intake_id,
    kind,
    coalesce(invitation_generation, 0),
    coalesce(submission_sequence, 0)
  );

create table lws_internal.sdf_qualification_rate_limits (
  pseudonymous_key char(64) not null check (pseudonymous_key ~ '^[0-9a-f]{64}$'),
  operation text not null check (operation in ('inspect_save', 'submit', 'invalid_capability')),
  window_started_at timestamptz not null,
  attempt_count integer not null check (attempt_count > 0),
  primary key (pseudonymous_key, operation, window_started_at)
);

create table public.sdf_quotation_preparation_authorities (
  authority_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null unique references public.quote_requests(id) on delete restrict,
  quotation_id uuid not null unique references public.sdf_quotations(quotation_id) on delete restrict,
  qualification_intake_id uuid not null unique references public.sdf_qualification_intakes(intake_id) on delete restrict,
  taxonomy_version text not null check (taxonomy_version = 'sdf_qualification_intake/1.0.0'),
  submission_sequence integer not null check (submission_sequence > 0),
  submission_sha256 char(64) not null check (submission_sha256 ~ '^[0-9a-f]{64}$'),
  completion_event_id uuid not null unique references public.sdf_qualification_intake_events(event_id) on delete restrict,
  sdf_package text not null check (sdf_package in ('start', 'groei', 'maatwerk')),
  pricing_authority_version integer not null check (pricing_authority_version > 0),
  pricing_authority_sha256 char(64) not null check (pricing_authority_sha256 ~ '^[0-9a-f]{64}$'),
  actor_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  actor_role text not null check (actor_role = 'owner'),
  decided_at timestamptz not null default clock_timestamp(),
  idempotency_key uuid not null unique,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$')
);

create function lws_internal.reject_sdf_qualification_history_mutation_v1()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  raise exception using errcode = '55000', message = 'SDF_QUALIFICATION_HISTORY_IMMUTABLE';
end;
$$;

create trigger trg_sdf_qualification_submissions_immutable before update or delete on public.sdf_qualification_intake_submissions for each row execute function lws_internal.reject_sdf_qualification_history_mutation_v1();
create trigger trg_sdf_qualification_events_immutable before update or delete on public.sdf_qualification_intake_events for each row execute function lws_internal.reject_sdf_qualification_history_mutation_v1();
create trigger trg_sdf_quotation_preparation_authorities_immutable before update or delete on public.sdf_quotation_preparation_authorities for each row execute function lws_internal.reject_sdf_qualification_history_mutation_v1();

alter table public.sdf_qualification_intakes enable row level security;
alter table public.sdf_qualification_intakes force row level security;
alter table public.sdf_qualification_intake_submissions enable row level security;
alter table public.sdf_qualification_intake_submissions force row level security;
alter table public.sdf_qualification_intake_events enable row level security;
alter table public.sdf_qualification_intake_events force row level security;
alter table public.sdf_qualification_intake_email_jobs enable row level security;
alter table public.sdf_qualification_intake_email_jobs force row level security;
alter table public.sdf_quotation_preparation_authorities enable row level security;
alter table public.sdf_quotation_preparation_authorities force row level security;
alter table lws_internal.sdf_qualification_rate_limits enable row level security;
alter table lws_internal.sdf_qualification_rate_limits force row level security;

revoke all on table public.sdf_qualification_intakes, public.sdf_qualification_intake_submissions,
  public.sdf_qualification_intake_events, public.sdf_qualification_intake_email_jobs,
  public.sdf_quotation_preparation_authorities, lws_internal.sdf_qualification_rate_limits
from public, anon, authenticated, service_role;

create function lws_internal.assert_sdf_owner_v1()
returns public.commercial_operators
language plpgsql stable security definer
set search_path = public, auth, pg_catalog as $$
declare v_operator public.commercial_operators%rowtype;
begin
  if auth.uid() is null then raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED'; end if;
  select * into v_operator from public.commercial_operators where auth_user_id = auth.uid();
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;
  if v_operator.role <> 'owner' then raise exception using errcode = '42501', message = 'OWNER_REQUIRED'; end if;
  return v_operator;
end;
$$;

create function lws_internal.sdf_payload_valid_v1(p_answers jsonb, p_require_complete boolean)
returns boolean language plpgsql immutable set search_path = pg_catalog as $$
declare
  v_keys text[];
  v_purpose_keys text[];
  v_business_keys text[];
  v_sample_keys text[];
  v_categories jsonb;
  v_capabilities jsonb;
  v_business jsonb;
  v_sample jsonb;
begin
  if jsonb_typeof(p_answers) <> 'object' then return false; end if;
  select coalesce(array_agg(key order by key), '{}') into v_keys from jsonb_object_keys(p_answers) key;
  if v_keys <> array['businessRequirements','documentPurpose','sampleDocumentMetadata','workflowCapabilities']::text[] then return false; end if;
  v_categories := p_answers#>'{documentPurpose,categories}';
  v_capabilities := p_answers->'workflowCapabilities';
  v_business := p_answers->'businessRequirements';
  v_sample := p_answers->'sampleDocumentMetadata';
  if jsonb_typeof(p_answers->'documentPurpose') <> 'object'
    or jsonb_typeof(v_categories) <> 'array'
    or jsonb_typeof(v_capabilities) <> 'array'
    or jsonb_typeof(v_business) <> 'object'
    or jsonb_typeof(v_sample) <> 'object' then return false; end if;
  select coalesce(array_agg(key order by key), '{}') into v_purpose_keys from jsonb_object_keys(p_answers->'documentPurpose') key;
  select coalesce(array_agg(key order by key), '{}') into v_business_keys from jsonb_object_keys(v_business) key;
  select coalesce(array_agg(key order by key), '{}') into v_sample_keys from jsonb_object_keys(v_sample) key;
  if v_purpose_keys not in (array['categories']::text[],array['categories','otherDescription']::text[])
    or v_business_keys <> array['currentWorkflow','desiredWorkflow','frequency','relevantDocumentTypes','rolesUsers','volumeBand']::text[]
    or v_sample_keys <> array['available','requestedByLws','uploadRequiredLater']::text[] then return false; end if;
  if jsonb_array_length(v_categories) > 12 or jsonb_array_length(v_capabilities) > 7
    or jsonb_typeof(v_business->'currentWorkflow') <> 'string'
    or jsonb_typeof(v_business->'desiredWorkflow') <> 'string'
    or jsonb_typeof(v_business->'volumeBand') <> 'string'
    or jsonb_typeof(v_business->'frequency') <> 'string'
    or jsonb_typeof(v_business->'relevantDocumentTypes') <> 'array'
    or jsonb_typeof(v_business->'rolesUsers') <> 'array'
    or jsonb_array_length(v_business->'relevantDocumentTypes') > 20
    or jsonb_array_length(v_business->'rolesUsers') > 20
    or jsonb_typeof(v_sample->'available') <> 'boolean'
    or jsonb_typeof(v_sample->'requestedByLws') <> 'boolean'
    or jsonb_typeof(v_sample->'uploadRequiredLater') <> 'boolean'
    or char_length(v_business->>'currentWorkflow') > 4000
    or char_length(v_business->>'desiredWorkflow') > 4000
    or (v_business->>'volumeBand'<>'' and v_business->>'volumeBand' not in ('1_to_9','10_to_49','50_to_249','250_plus','unknown'))
    or (v_business->>'frequency'<>'' and v_business->>'frequency' not in ('daily','weekly','monthly','ad_hoc','unknown')) then return false; end if;
  if p_require_complete and (
    jsonb_array_length(v_categories) not between 1 and 12
    or jsonb_array_length(v_capabilities) not between 1 and 7
    or nullif(btrim(v_business->>'currentWorkflow'), '') is null
    or nullif(btrim(v_business->>'desiredWorkflow'), '') is null
    or nullif(v_business->>'volumeBand','') is null
    or nullif(v_business->>'frequency','') is null
   or jsonb_array_length(v_business->'relevantDocumentTypes') < 1
   or jsonb_array_length(v_business->'rolesUsers') < 1
  ) then return false; end if;
  if exists (select 1 from jsonb_array_elements_text(coalesce(v_categories, '[]')) value where value not in ('quotation','invoice','order_confirmation','work_order','delivery_note','contract','customer_document','supplier_document','internal_administrative_document','multiple_document_types','other_custom','unknown_qualification_required')) then return false; end if;
  if exists (select 1 from jsonb_array_elements_text(coalesce(v_capabilities, '[]')) value where value not in ('receive','generate','review','approve','send','archive','retrieve')) then return false; end if;
  if (select count(*) from jsonb_array_elements_text(coalesce(v_categories, '[]'))) <> (select count(distinct value) from jsonb_array_elements_text(coalesce(v_categories, '[]')) value) then return false; end if;
  if (select count(*) from jsonb_array_elements_text(coalesce(v_capabilities, '[]'))) <> (select count(distinct value) from jsonb_array_elements_text(coalesce(v_capabilities, '[]')) value) then return false; end if;
  if exists (select 1 from jsonb_array_elements(v_business->'relevantDocumentTypes') value where jsonb_typeof(value)<>'string' or char_length(btrim(value#>>'{}')) not between 1 and 200) then return false; end if;
  if exists (select 1 from jsonb_array_elements(v_business->'rolesUsers') value where jsonb_typeof(value)<>'string' or char_length(btrim(value#>>'{}')) not between 1 and 200) then return false; end if;
  if (select count(*) from jsonb_array_elements_text(v_business->'relevantDocumentTypes')) <> (select count(distinct value) from jsonb_array_elements_text(v_business->'relevantDocumentTypes') value) then return false; end if;
  if (select count(*) from jsonb_array_elements_text(v_business->'rolesUsers')) <> (select count(distinct value) from jsonb_array_elements_text(v_business->'rolesUsers') value) then return false; end if;
  if coalesce(v_categories ? 'unknown_qualification_required', false) and jsonb_array_length(v_categories) <> 1 then return false; end if;
  if coalesce(v_categories ? 'other_custom', false) <> (nullif(btrim(p_answers#>>'{documentPurpose,otherDescription}'), '') is not null) then return false; end if;
  if p_answers#>'{documentPurpose,otherDescription}' is not null and (jsonb_typeof(p_answers#>'{documentPurpose,otherDescription}')<>'string' or char_length(p_answers#>>'{documentPurpose,otherDescription}')>500) then return false; end if;
  return true;
exception when others then return false;
end;
$$;

create function public.consume_sdf_qualification_rate_limit_v1(p_pseudonymous_key text,p_operation text)
returns boolean language plpgsql volatile security definer
set search_path=lws_internal,pg_catalog as $$
declare v_window_seconds integer; v_max_attempts integer; v_window timestamptz; v_attempt_count integer;
begin
  if p_pseudonymous_key !~ '^[0-9a-f]{64}$' or p_operation not in ('inspect_save','submit','invalid_capability') then
    raise exception using errcode='22023',message='INVALID_SDF_RATE_LIMIT_REQUEST';
  end if;
  if p_operation='inspect_save' then v_window_seconds:=60; v_max_attempts:=30;
  elsif p_operation='submit' then v_window_seconds:=900; v_max_attempts:=10;
  else v_window_seconds:=900; v_max_attempts:=20;
  end if;
  v_window:=to_timestamp(floor(extract(epoch from clock_timestamp())/v_window_seconds)*v_window_seconds);
  insert into lws_internal.sdf_qualification_rate_limits(pseudonymous_key,operation,window_started_at,attempt_count)
  values(p_pseudonymous_key,p_operation,v_window,1)
  on conflict(pseudonymous_key,operation,window_started_at) do update
  set attempt_count=lws_internal.sdf_qualification_rate_limits.attempt_count+1
  returning attempt_count into v_attempt_count;
  delete from lws_internal.sdf_qualification_rate_limits where window_started_at<clock_timestamp()-interval '2 days';
  return v_attempt_count<=v_max_attempts;
end;
$$;

create function public.allow_sdf_qualification_intake_v1(
  p_quote_request_id uuid, p_customer_capability_digest text, p_encrypted_capability text, p_idempotency_key uuid
) returns jsonb language plpgsql volatile security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog as $$
declare v_operator public.commercial_operators%rowtype; v_request public.quote_requests%rowtype; v_intake public.sdf_qualification_intakes%rowtype; v_event public.sdf_qualification_intake_events%rowtype; v_fingerprint char(64); v_due timestamptz; v_event_id uuid:=gen_random_uuid(); v_occurred_at timestamptz:=clock_timestamp(); v_result jsonb;
begin
  v_operator := lws_internal.assert_sdf_owner_v1();
  if p_quote_request_id is null or p_idempotency_key is null or p_customer_capability_digest !~ '^[0-9a-f]{64}$' or p_encrypted_capability !~ '^v1\.[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{40,}$' then raise exception using errcode='22023', message='INVALID_SDF_INTAKE_ALLOW_REQUEST'; end if;
  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object('v',1,'request',p_quote_request_id,'action','allow_sdf_qualification_intake')::text,'UTF8'),'sha256'),'hex');
  select * into v_event from public.sdf_qualification_intake_events where idempotency_key=p_idempotency_key;
  if found then
    if v_event.request_fingerprint <> v_fingerprint then raise exception using errcode='P0001', message='IDEMPOTENCY_CONFLICT'; end if;
    return v_event.result_snapshot;
  end if;
  select * into v_request from public.quote_requests where id=p_quote_request_id for update;
  if not found or v_request.request_kind <> 'slimme_documentenflow' then raise exception using errcode='23514', message='SDF_REQUEST_KIND_REQUIRED'; end if;
  if v_request.status = 'rejected' then raise exception using errcode='55000', message='SDF_REQUEST_CLOSED'; end if;
  if exists(select 1 from public.sdf_qualification_intakes where quote_request_id=p_quote_request_id) then raise exception using errcode='23505', message='SDF_INTAKE_ALREADY_EXISTS'; end if;
  v_due := coalesce(v_request.confirmation_sent_at + interval '120 seconds', 'infinity'::timestamptz);
  insert into public.sdf_qualification_intakes(quote_request_id,customer_capability_digest,customer_capability_encrypted,customer_capability_expires_at)
  values(p_quote_request_id,p_customer_capability_digest,p_encrypted_capability,clock_timestamp()+interval '14 days') returning * into v_intake;
  v_result:=jsonb_build_object('intake_id',v_intake.intake_id,'quote_request_id',p_quote_request_id,'status','invited','invitation_generation',v_intake.invitation_generation,'expires_at',v_intake.customer_capability_expires_at,'event_id',v_event_id,'occurred_at',v_occurred_at,'replayed',false);
  insert into public.sdf_qualification_intake_events(event_id,intake_id,event_kind,to_status,actor_class,actor_operator_id,idempotency_key,request_fingerprint,result_snapshot,occurred_at)
  values(v_event_id,v_intake.intake_id,'INVITED','invited','operator',v_operator.operator_id,p_idempotency_key,v_fingerprint,v_result,v_occurred_at);
  insert into public.sdf_qualification_intake_email_jobs(intake_id,kind,template_version,invitation_generation,status,next_attempt_at,idempotency_key,request_fingerprint,encrypted_capability)
  values(v_intake.intake_id,'invitation','SDF_QUALIFICATION_INTAKE_INVITATION_NL_BE_v1',1,'pending',v_due,p_idempotency_key,v_fingerprint,p_encrypted_capability);
  return v_result;
end;
$$;

create function public.inspect_sdf_qualification_intake_v1(p_customer_capability_digest text)
returns jsonb language plpgsql stable security definer set search_path=public,pg_catalog as $$
declare v_intake public.sdf_qualification_intakes%rowtype;
begin
  select * into v_intake from public.sdf_qualification_intakes where customer_capability_digest=p_customer_capability_digest and customer_capability_revoked_at is null and customer_capability_expires_at>clock_timestamp();
  if not found then raise exception using errcode='42501', message='SDF_INTAKE_ACCESS_DENIED'; end if;
  return jsonb_build_object('intake_id',v_intake.intake_id,'status',v_intake.status,'taxonomy_version',v_intake.taxonomy_version,'draft',v_intake.draft_answers,'draft_revision',v_intake.draft_revision,'expires_at',v_intake.customer_capability_expires_at);
end;
$$;

create function public.reissue_sdf_qualification_intake_v1(p_quote_request_id uuid,p_customer_capability_digest text,p_encrypted_capability text,p_idempotency_key uuid)
returns jsonb language plpgsql volatile security definer set search_path=public,lws_internal,extensions,pg_catalog as $$
declare v_operator public.commercial_operators%rowtype; v_intake public.sdf_qualification_intakes%rowtype; v_event public.sdf_qualification_intake_events%rowtype; v_fingerprint char(64); v_generation integer; v_event_id uuid:=gen_random_uuid(); v_occurred_at timestamptz:=clock_timestamp(); v_result jsonb; v_intake_id uuid;
begin
  v_operator:=lws_internal.assert_sdf_owner_v1();
  if p_quote_request_id is null or p_idempotency_key is null or p_customer_capability_digest !~ '^[0-9a-f]{64}$' or p_encrypted_capability !~ '^v1\.[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{40,}$' then raise exception using errcode='22023',message='INVALID_SDF_INTAKE_REISSUE_REQUEST'; end if;
  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object('v',1,'request',p_quote_request_id,'action','reissue_sdf_qualification_intake')::text,'UTF8'),'sha256'),'hex');
  select * into v_event from public.sdf_qualification_intake_events where idempotency_key=p_idempotency_key;
  if found then if v_event.request_fingerprint<>v_fingerprint then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT'; end if; return v_event.result_snapshot; end if;
  select intake_id into v_intake_id from public.sdf_qualification_intakes where quote_request_id=p_quote_request_id;
  if not found then raise exception using errcode='P0002',message='SDF_QUALIFICATION_INTAKE_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_intake_id::text,0));
  select * into strict v_intake from public.sdf_qualification_intakes where intake_id=v_intake_id for update;
  if v_intake.status not in ('invited','in_progress','changes_requested') then raise exception using errcode='55000',message='SDF_INTAKE_TRANSITION_NOT_ALLOWED'; end if;
  if exists(select 1 from public.sdf_qualification_intake_email_jobs where intake_id=v_intake.intake_id and kind='invitation' and invitation_generation=v_intake.invitation_generation and status='processing' and delivery_lease_expires_at>clock_timestamp()) then raise exception using errcode='55000',message='SDF_INVITATION_DELIVERY_IN_PROGRESS'; end if;
  v_generation:=v_intake.invitation_generation+1;
  update public.sdf_qualification_intakes set customer_capability_digest=p_customer_capability_digest,customer_capability_encrypted=p_encrypted_capability,customer_capability_expires_at=clock_timestamp()+interval '14 days',invitation_generation=v_generation,updated_at=clock_timestamp() where intake_id=v_intake.intake_id returning * into v_intake;
  update public.sdf_qualification_intake_email_jobs set status='failed',locked_at=null,delivery_lease_token=null,delivery_lease_expires_at=null,last_error_code='REISSUED',next_attempt_at=clock_timestamp(),updated_at=clock_timestamp() where intake_id=v_intake.intake_id and kind='invitation' and status in ('pending','retry_wait','processing');
  v_result:=jsonb_build_object('intake_id',v_intake.intake_id,'quote_request_id',p_quote_request_id,'status',v_intake.status,'invitation_generation',v_generation,'expires_at',v_intake.customer_capability_expires_at,'event_id',v_event_id,'occurred_at',v_occurred_at,'replayed',false);
  insert into public.sdf_qualification_intake_events(event_id,intake_id,event_kind,from_status,to_status,actor_class,actor_operator_id,idempotency_key,request_fingerprint,result_snapshot,occurred_at) values(v_event_id,v_intake.intake_id,'INVITATION_REISSUED',v_intake.status,v_intake.status,'operator',v_operator.operator_id,p_idempotency_key,v_fingerprint,v_result,v_occurred_at);
  insert into public.sdf_qualification_intake_email_jobs(intake_id,kind,template_version,invitation_generation,status,next_attempt_at,idempotency_key,request_fingerprint,encrypted_capability) values(v_intake.intake_id,'invitation','SDF_QUALIFICATION_INTAKE_INVITATION_NL_BE_v1',v_generation,'pending',clock_timestamp(),p_idempotency_key,v_fingerprint,p_encrypted_capability);
  return v_result;
end;
$$;

create function public.save_sdf_qualification_intake_draft_v1(p_customer_capability_digest text,p_expected_revision bigint,p_answers jsonb)
returns jsonb language plpgsql volatile security definer set search_path=public,pg_catalog as $$
declare v_intake public.sdf_qualification_intakes%rowtype; v_new_status public.sdf_qualification_intake_status;
begin
  select * into v_intake from public.sdf_qualification_intakes where customer_capability_digest=p_customer_capability_digest and customer_capability_revoked_at is null and customer_capability_expires_at>clock_timestamp() for update;
  if not found then raise exception using errcode='42501', message='SDF_INTAKE_ACCESS_DENIED'; end if;
  if v_intake.status not in ('invited','in_progress','changes_requested') then raise exception using errcode='55000', message='SDF_INTAKE_TRANSITION_NOT_ALLOWED'; end if;
  if p_expected_revision <> v_intake.draft_revision then raise exception using errcode='40001', message='SDF_INTAKE_REVISION_CONFLICT'; end if;
  if not lws_internal.sdf_payload_valid_v1(p_answers,false) then raise exception using errcode='22023', message='INVALID_SDF_QUALIFICATION_PAYLOAD'; end if;
  if p_answers=v_intake.draft_answers then return jsonb_build_object('intake_id',v_intake.intake_id,'status',v_intake.status,'draft_revision',v_intake.draft_revision,'replayed',true); end if;
  v_new_status := 'in_progress';
  update public.sdf_qualification_intakes set draft_answers=p_answers,draft_revision=draft_revision+1,status=v_new_status,updated_at=clock_timestamp() where intake_id=v_intake.intake_id returning * into v_intake;
  insert into public.sdf_qualification_intake_events(intake_id,event_kind,from_status,to_status,actor_class) values(v_intake.intake_id,'DRAFT_SAVED',v_intake.status,v_new_status,'customer');
  return jsonb_build_object('intake_id',v_intake.intake_id,'status',v_intake.status,'draft_revision',v_intake.draft_revision,'replayed',false);
end;
$$;

create function public.submit_sdf_qualification_intake_v1(p_customer_capability_digest text,p_expected_revision bigint,p_confirmation_accepted boolean,p_confirmation_version text,p_confirmation_sha256 text,p_idempotency_key uuid)
returns jsonb language plpgsql volatile security definer set search_path=public,extensions,pg_catalog as $$
declare v_intake public.sdf_qualification_intakes%rowtype; v_event public.sdf_qualification_intake_events%rowtype; v_sequence integer; v_hash char(64); v_fingerprint char(64);
begin
  select * into v_intake from public.sdf_qualification_intakes where customer_capability_digest=p_customer_capability_digest and customer_capability_revoked_at is null and customer_capability_expires_at>clock_timestamp() for update;
  if not found then raise exception using errcode='42501', message='SDF_INTAKE_ACCESS_DENIED'; end if;
  v_hash := encode(extensions.digest(convert_to(v_intake.draft_answers::text,'UTF8'),'sha256'),'hex');
  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object('v',1,'intake',v_intake.intake_id,'revision',p_expected_revision,'payload',v_hash,'confirmation',p_confirmation_sha256)::text,'UTF8'),'sha256'),'hex');
  select * into v_event from public.sdf_qualification_intake_events where intake_id=v_intake.intake_id and idempotency_key=p_idempotency_key;
  if found then if v_event.request_fingerprint<>v_fingerprint then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT'; end if; return jsonb_build_object('intake_id',v_intake.intake_id,'status',v_event.to_status,'submission_sequence',v_event.submission_sequence,'replayed',true); end if;
  if v_intake.status not in ('invited','in_progress','changes_requested') then raise exception using errcode='55000',message='SDF_INTAKE_TRANSITION_NOT_ALLOWED'; end if;
  if p_expected_revision<>v_intake.draft_revision then raise exception using errcode='40001',message='SDF_INTAKE_REVISION_CONFLICT'; end if;
    if p_confirmation_accepted is not true
      or p_confirmation_version<>'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1'
      or p_confirmation_sha256<>encode(extensions.digest(convert_to('Ik bevestig dat de ingevulde informatie naar best vermogen volledig en correct is. Ik begrijp dat deze kwalificatie geen offerte, prijsbevestiging of aanvaarding van een opdracht vormt.','UTF8'),'sha256'),'hex')
      or not lws_internal.sdf_payload_valid_v1(v_intake.draft_answers,true) then raise exception using errcode='22023',message='INVALID_SDF_QUALIFICATION_SUBMISSION'; end if;
  v_sequence:=v_intake.latest_submission_sequence+1;
  insert into public.sdf_qualification_intake_submissions(intake_id,submission_sequence,answers,taxonomy_version,payload_sha256,confirmation_version,confirmation_sha256) values(v_intake.intake_id,v_sequence,v_intake.draft_answers,v_intake.taxonomy_version,v_hash,p_confirmation_version,p_confirmation_sha256);
  update public.sdf_qualification_intakes set status='submitted',latest_submission_sequence=v_sequence,submitted_at=clock_timestamp(),internal_capability_expires_at=clock_timestamp()+interval '30 days',updated_at=clock_timestamp() where intake_id=v_intake.intake_id;
  insert into public.sdf_qualification_intake_events(intake_id,event_kind,from_status,to_status,actor_class,submission_sequence,idempotency_key,request_fingerprint) values(v_intake.intake_id,'SUBMITTED',v_intake.status,'submitted','customer',v_sequence,p_idempotency_key,v_fingerprint);
  insert into public.sdf_qualification_intake_email_jobs(intake_id,kind,template_version,submission_sequence,idempotency_key,request_fingerprint) values(v_intake.intake_id,'submitted','SDF_QUALIFICATION_SUBMITTED_INTERNAL_NL_BE_v1',v_sequence,p_idempotency_key,v_fingerprint);
  return jsonb_build_object('intake_id',v_intake.intake_id,'status','submitted','submission_sequence',v_sequence,'payload_sha256',v_hash,'replayed',false);
end;
$$;

create function public.inspect_sdf_qualification_intake_for_operator_v1(p_quote_request_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,lws_internal,pg_catalog as $$
declare v_operator public.commercial_operators%rowtype; v_result jsonb;
begin
  v_operator:=lws_internal.assert_sdf_owner_v1();
  select jsonb_build_object('quote_request_id',r.id,'name',r.name,'company',r.company,'email',r.email,'sdf_package',r.sdf_package,'intake_id',i.intake_id,'status',i.status,'taxonomy_version',i.taxonomy_version,'draft_revision',i.draft_revision,'latest_submission_sequence',i.latest_submission_sequence,'latest_submission',s.answers,'latest_submission_sha256',s.payload_sha256) into v_result from public.quote_requests r join public.sdf_qualification_intakes i on i.quote_request_id=r.id left join public.sdf_qualification_intake_submissions s on s.intake_id=i.intake_id and s.submission_sequence=i.latest_submission_sequence where r.id=p_quote_request_id and r.request_kind='slimme_documentenflow';
  if v_result is null then raise exception using errcode='P0002',message='SDF_QUALIFICATION_INTAKE_NOT_FOUND'; end if;
  return v_result;
end;
$$;

create function public.transition_sdf_qualification_intake_v1(p_quote_request_id uuid,p_action text,p_reason text,p_idempotency_key uuid,p_encrypted_capability text default null)
returns jsonb language plpgsql volatile security definer set search_path=public,lws_internal,extensions,pg_catalog as $$
declare v_operator public.commercial_operators%rowtype; v_intake public.sdf_qualification_intakes%rowtype; v_event public.sdf_qualification_intake_events%rowtype; v_to public.sdf_qualification_intake_status; v_kind text; v_reason text:=nullif(btrim(p_reason),''); v_fingerprint char(64); v_event_id uuid; v_encrypted_capability text:=p_encrypted_capability;
begin
  v_operator:=lws_internal.assert_sdf_owner_v1();
  select i.* into v_intake from public.sdf_qualification_intakes i join public.quote_requests r on r.id=i.quote_request_id where i.quote_request_id=p_quote_request_id and r.request_kind='slimme_documentenflow' for update;
  if not found then raise exception using errcode='P0002',message='SDF_QUALIFICATION_INTAKE_NOT_FOUND'; end if;
  if p_action='begin_review' and v_intake.status='submitted' then v_to:='under_review'; v_kind:='REVIEW_STARTED';
  elsif p_action='request_more_information' and v_intake.status='under_review' then v_to:='changes_requested'; v_kind:='CHANGES_REQUESTED';
  elsif p_action='mark_qualification_complete' and v_intake.status='under_review' then v_to:='qualification_complete'; v_kind:='QUALIFICATION_COMPLETE';
  elsif p_action='close_qualification' and v_intake.status='under_review' then v_to:='closed'; v_kind:='CLOSED';
  else raise exception using errcode='55000',message='SDF_INTAKE_TRANSITION_NOT_ALLOWED'; end if;
  if p_action in ('request_more_information','close_qualification') and (v_reason is null or char_length(v_reason) not between 1 and 2000) then raise exception using errcode='22023',message='SDF_INTAKE_REASON_REQUIRED'; end if;
  if p_action='request_more_information' and v_encrypted_capability is null then
    v_encrypted_capability:=v_intake.customer_capability_encrypted;
    if v_encrypted_capability is null then raise exception using errcode='22023',message='SDF_INTAKE_CAPABILITY_REQUIRED'; end if;
  end if;
  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object('v',1,'intake',v_intake.intake_id,'action',p_action,'reason',v_reason,'submission',v_intake.latest_submission_sequence)::text,'UTF8'),'sha256'),'hex');
  select * into v_event from public.sdf_qualification_intake_events where intake_id=v_intake.intake_id and idempotency_key=p_idempotency_key;
  if found then if v_event.request_fingerprint<>v_fingerprint then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT'; end if; return jsonb_build_object('intake_id',v_intake.intake_id,'status',v_event.to_status,'event_id',v_event.event_id,'replayed',true); end if;
  update public.sdf_qualification_intakes set status=v_to,review_started_at=case when v_to='under_review' then clock_timestamp() else review_started_at end,qualification_completed_at=case when v_to='qualification_complete' then clock_timestamp() else qualification_completed_at end,closed_at=case when v_to='closed' then clock_timestamp() else closed_at end,updated_at=clock_timestamp() where intake_id=v_intake.intake_id;
  insert into public.sdf_qualification_intake_events(intake_id,event_kind,from_status,to_status,actor_class,actor_operator_id,submission_sequence,reason,idempotency_key,request_fingerprint) values(v_intake.intake_id,v_kind,v_intake.status,v_to,'operator',v_operator.operator_id,v_intake.latest_submission_sequence,v_reason,p_idempotency_key,v_fingerprint) returning event_id into v_event_id;
  if v_to='changes_requested' then insert into public.sdf_qualification_intake_email_jobs(intake_id,kind,template_version,submission_sequence,idempotency_key,request_fingerprint,encrypted_capability) values(v_intake.intake_id,'more_information','SDF_QUALIFICATION_MORE_INFORMATION_NL_BE_v1',v_intake.latest_submission_sequence,p_idempotency_key,v_fingerprint,v_encrypted_capability); end if;
  return jsonb_build_object('intake_id',v_intake.intake_id,'status',v_to,'event_id',v_event_id,'replayed',false);
end;
$$;

create function public.authorize_sdf_quotation_preparation_v1(p_quote_request_id uuid,p_idempotency_key uuid)
returns jsonb language plpgsql volatile security definer set search_path=public,lws_internal,auth,extensions,pg_catalog as $$
declare v_operator public.commercial_operators%rowtype; v_request public.quote_requests%rowtype; v_intake public.sdf_qualification_intakes%rowtype; v_submission public.sdf_qualification_intake_submissions%rowtype; v_completion public.sdf_qualification_intake_events%rowtype; v_existing public.sdf_quotation_preparation_authorities%rowtype; v_quotation_id uuid; v_pricing jsonb; v_pricing_hash char(64); v_fingerprint char(64);
begin
  v_operator:=lws_internal.assert_sdf_owner_v1();
  select * into v_request from public.quote_requests where id=p_quote_request_id for update;
  if not found or v_request.request_kind<>'slimme_documentenflow' then raise exception using errcode='23514',message='SDF_REQUEST_KIND_REQUIRED'; end if;
  if v_request.status='rejected' or v_request.sdf_package is null then raise exception using errcode='55000',message='SDF_QUOTATION_PREPARATION_NOT_ELIGIBLE'; end if;
  if exists(select 1 from lws_internal.operator_dossier_states where quote_request_id=p_quote_request_id and state='TRASHED') then raise exception using errcode='55000',message='SDF_QUOTATION_PREPARATION_NOT_ELIGIBLE'; end if;
  select * into v_intake from public.sdf_qualification_intakes where quote_request_id=p_quote_request_id for update;
  if not found or v_intake.status<>'qualification_complete' then raise exception using errcode='55000',message='SDF_QUALIFICATION_COMPLETE_REQUIRED'; end if;
  select * into strict v_submission from public.sdf_qualification_intake_submissions where intake_id=v_intake.intake_id and submission_sequence=v_intake.latest_submission_sequence;
  select * into strict v_completion from public.sdf_qualification_intake_events where intake_id=v_intake.intake_id and event_kind='QUALIFICATION_COMPLETE' order by occurred_at desc limit 1;
  v_pricing:=public.get_sdf_package_pricing_authority_v1(v_request.sdf_package);
  v_pricing_hash:=encode(extensions.digest(convert_to(v_pricing::text,'UTF8'),'sha256'),'hex');
  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object('v',1,'request',p_quote_request_id,'intake',v_intake.intake_id,'submission',v_submission.payload_sha256,'completion',v_completion.event_id,'package',v_request.sdf_package,'pricing',v_pricing_hash)::text,'UTF8'),'sha256'),'hex');
  select * into v_existing from public.sdf_quotation_preparation_authorities where idempotency_key=p_idempotency_key;
  if found then if v_existing.request_fingerprint<>v_fingerprint then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT'; end if; return jsonb_build_object('authority_id',v_existing.authority_id,'quotation_id',v_existing.quotation_id,'status','QUOTATION_PREPARATION_ELIGIBLE','replayed',true); end if;
  if exists(select 1 from public.sdf_quotations where quote_request_id=p_quote_request_id) or exists(select 1 from public.sdf_quotation_preparation_authorities where quote_request_id=p_quote_request_id) then raise exception using errcode='55000',message='SDF_QUOTATION_PREPARATION_CONFLICT'; end if;
  insert into public.sdf_quotations(quote_request_id) values(p_quote_request_id) returning quotation_id into v_quotation_id;
  insert into public.sdf_quotation_preparation_authorities(quote_request_id,quotation_id,qualification_intake_id,taxonomy_version,submission_sequence,submission_sha256,completion_event_id,sdf_package,pricing_authority_version,pricing_authority_sha256,actor_operator_id,actor_role,idempotency_key,request_fingerprint) values(p_quote_request_id,v_quotation_id,v_intake.intake_id,v_intake.taxonomy_version,v_submission.submission_sequence,v_submission.payload_sha256,v_completion.event_id,v_request.sdf_package,(v_pricing->>'authority_version')::integer,v_pricing_hash,v_operator.operator_id,'owner',p_idempotency_key,v_fingerprint) returning * into v_existing;
  return jsonb_build_object('authority_id',v_existing.authority_id,'quotation_id',v_existing.quotation_id,'status','QUOTATION_PREPARATION_ELIGIBLE','replayed',false);
end;
$$;

alter table lws_internal.application_intake_automation_work drop constraint application_intake_automation_work_phase_valid;
alter table lws_internal.application_intake_automation_work add constraint application_intake_automation_work_phase_valid check (phase in ('APPROVAL','INTAKE','SDF_CONFIRMATION','SDF_INTAKE','COMPLETED','STOPPED','MANUAL_REVIEW'));

create or replace function lws_internal.enroll_application_intake_automation_v1()
returns trigger language plpgsql security definer set search_path=lws_internal,public,pg_catalog as $$
declare v_cutover_at timestamptz; v_phase text;
begin
  perform pg_catalog.pg_advisory_xact_lock(17003,1);
  select cutover_at into v_cutover_at from lws_internal.application_intake_automation_config where singleton and active;
  if v_cutover_at is null or new.created_at<v_cutover_at or new.record_classification<>'production' or new.request_kind not in ('website','slimme_documentenflow') or new.status<>'pending' then return new; end if;
  v_phase:=case when new.request_kind='website' then 'APPROVAL' else 'SDF_CONFIRMATION' end;
  insert into lws_internal.application_intake_automation_work(quote_request_id,phase,approval_due_at,next_attempt_at) values(new.id,v_phase,new.created_at+interval '120 seconds',new.created_at+interval '120 seconds') on conflict(quote_request_id) do nothing;
  return new;
end;
$$;

create function lws_internal.advance_sdf_automation_after_confirmation_v1()
returns trigger language plpgsql security definer set search_path=lws_internal,public,pg_catalog as $$
begin
  if new.request_kind='slimme_documentenflow' and new.confirmation_sent_at is not null and old.confirmation_sent_at is null then
    update lws_internal.application_intake_automation_work set phase='SDF_INTAKE',approved_at=new.confirmation_sent_at,intake_due_at=new.confirmation_sent_at+interval '120 seconds',next_attempt_at=new.confirmation_sent_at+interval '120 seconds',attempt_count=0,claim_token=null,claimed_by=null,claimed_at=null,claim_expires_at=null,last_error_code=null where quote_request_id=new.id and phase='SDF_CONFIRMATION';
    update public.sdf_qualification_intake_email_jobs job
    set next_attempt_at=new.confirmation_sent_at+interval '120 seconds',updated_at=clock_timestamp()
    from public.sdf_qualification_intakes intake
    where intake.quote_request_id=new.id and job.intake_id=intake.intake_id and job.kind='invitation'
      and job.invitation_generation=intake.invitation_generation and job.status in ('pending','retry_wait')
      and job.next_attempt_at='infinity'::timestamptz;
  end if;
  return new;
end;
$$;
create trigger trg_quote_requests_advance_sdf_automation after update of confirmation_sent_at on public.quote_requests for each row execute function lws_internal.advance_sdf_automation_after_confirmation_v1();

create function lws_internal.advance_sdf_automation_from_confirmation_job_v1()
returns trigger language plpgsql security definer set search_path=lws_internal,public,pg_catalog as $$
declare v_kind text;
begin
  select request.request_kind into v_kind
  from public.quote_requests request
  where request.id=new.quote_request_id;
  if v_kind='slimme_documentenflow'
     and new.kind='customer_confirmation'
     and new.status='sent'
     and new.sent_at is not null
     and (old.status is distinct from new.status or old.sent_at is distinct from new.sent_at) then
    update public.quote_requests
    set confirmation_sent_at=coalesce(confirmation_sent_at,new.sent_at)
    where id=new.quote_request_id;
    update lws_internal.application_intake_automation_work
    set phase='SDF_INTAKE',approved_at=new.sent_at,intake_due_at=new.sent_at+interval '120 seconds',
        next_attempt_at=new.sent_at+interval '120 seconds',attempt_count=0,
        claim_token=null,claimed_by=null,claimed_at=null,claim_expires_at=null,last_error_code=null
    where quote_request_id=new.quote_request_id and phase='SDF_CONFIRMATION';
    update public.sdf_qualification_intake_email_jobs job
    set next_attempt_at=new.sent_at+interval '120 seconds',updated_at=clock_timestamp()
    from public.sdf_qualification_intakes intake
    where intake.quote_request_id=new.quote_request_id and job.intake_id=intake.intake_id and job.kind='invitation'
      and job.invitation_generation=intake.invitation_generation and job.status in ('pending','retry_wait')
      and job.next_attempt_at='infinity'::timestamptz;
  end if;
  return new;
end;
$$;
create trigger trg_sdf_confirmation_job_advances_automation
after update of status,sent_at on public.quote_request_email_jobs
for each row execute function lws_internal.advance_sdf_automation_from_confirmation_job_v1();

create or replace function public.claim_application_intake_automation_work_v1(p_worker_id uuid,p_limit integer default 5)
returns table(work_id bigint,quote_request_id uuid,phase text,claim_token uuid,claim_expires_at timestamptz)
language plpgsql volatile security definer set search_path=lws_internal,public,pg_catalog as $$
declare v_now timestamptz:=clock_timestamp(); v_limit integer:=least(greatest(coalesce(p_limit,5),1),5);
begin
  if p_worker_id is null then raise exception using errcode='22023',message='INVALID_AUTOMATION_WORKER_ID'; end if;
  return query with candidates as materialized (
    select w.work_id from lws_internal.application_intake_automation_work w join public.quote_requests r on r.id=w.quote_request_id join lws_internal.application_intake_automation_config c on c.singleton
    where c.active and r.created_at>=c.cutover_at and r.record_classification='production' and w.phase in ('APPROVAL','INTAKE','SDF_CONFIRMATION','SDF_INTAKE') and w.attempt_count<5 and w.next_attempt_at<=v_now and (w.claim_token is null or w.claim_expires_at<=v_now)
    and ((r.request_kind='website' and w.phase in ('APPROVAL','INTAKE'))
      or (r.request_kind='slimme_documentenflow' and w.phase='SDF_CONFIRMATION' and r.confirmation_sent_at is null)
      or (r.request_kind='slimme_documentenflow' and w.phase='SDF_INTAKE' and r.confirmation_sent_at is not null and w.intake_due_at<=v_now and exists(select 1 from public.sdf_qualification_intakes i join public.sdf_qualification_intake_email_jobs j on j.intake_id=i.intake_id where i.quote_request_id=r.id and i.status='invited' and j.kind='invitation' and j.status in ('pending','retry_wait') and j.next_attempt_at<=v_now)))
    order by w.next_attempt_at,w.work_id for update of w skip locked limit v_limit
  ), claimed as (
    update lws_internal.application_intake_automation_work w set claim_token=gen_random_uuid(),claimed_by=p_worker_id,claimed_at=v_now,claim_expires_at=v_now+interval '90 seconds',attempt_count=w.attempt_count+1,last_error_code=null from candidates where w.work_id=candidates.work_id returning w.*
  ) select claimed.work_id,claimed.quote_request_id,claimed.phase,claimed.claim_token,claimed.claim_expires_at from claimed order by claimed.work_id;
end;
$$;

create function public.execute_application_intake_automation_sdf_confirmation_v1(p_work_id bigint,p_claim_token uuid)
returns table(outcome text,confirmation_job_id uuid,request_name text,request_email text,application_reference text,created_at timestamptz,request_kind text,template_key text,template_version text)
language plpgsql volatile security definer set search_path=lws_internal,public,pg_catalog as $$
declare v_work lws_internal.application_intake_automation_work%rowtype; v_request public.quote_requests%rowtype; v_job public.quote_request_email_jobs%rowtype;
begin
  select * into v_work from lws_internal.application_intake_automation_work where work_id=p_work_id and claim_token=p_claim_token and claim_expires_at>clock_timestamp() for update;
  if not found or v_work.phase<>'SDF_CONFIRMATION' then return; end if;
  select request.* into v_request
  from public.quote_requests as request
  where request.id=v_work.quote_request_id
    and request.request_kind='slimme_documentenflow'
    and request.record_classification='production'
  for update;
  if not found or v_request.confirmation_sent_at is not null then return; end if;
  insert into public.quote_request_email_jobs(quote_request_id,kind,next_attempt_at,template_key,template_version)
  select v_request.id,'customer_confirmation',clock_timestamp(),'SDF_REQUEST_RECEIVED_NL_BE_v1','v1'
  where not exists (
    select 1 from public.quote_request_email_jobs
    where quote_request_id=v_request.id and kind='customer_confirmation'
  )
  on conflict do nothing;
  select job.* into strict v_job from public.quote_request_email_jobs job where job.quote_request_id=v_request.id and job.kind='customer_confirmation' and job.template_key='SDF_REQUEST_RECEIVED_NL_BE_v1' and job.template_version='v1';
  return query select 'confirmation_pending'::text,v_job.id,v_request.name,v_request.email,v_request.application_reference,v_request.created_at,v_request.request_kind,v_job.template_key,v_job.template_version;
end;
$$;

create function public.claim_sdf_qualification_email_job_v1(p_job_id uuid)
returns table(job_id uuid,intake_id uuid,kind text,template_version text,attempt_count integer,encrypted_capability text,customer_capability_digest text,delivery_lease_token uuid,delivery_lease_expires_at timestamptz)
language plpgsql volatile security definer set search_path=public,pg_catalog as $$
declare v_intake_id uuid; v_now timestamptz:=clock_timestamp(); v_lease_token uuid:=gen_random_uuid();
begin
 select j.intake_id into v_intake_id from public.sdf_qualification_intake_email_jobs j where j.job_id=p_job_id;
 if v_intake_id is null then return; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_intake_id::text,0));
 return query update public.sdf_qualification_intake_email_jobs j set status='processing',attempt_count=j.attempt_count+1,locked_at=v_now,delivery_lease_token=v_lease_token,delivery_lease_expires_at=v_now+interval '10 minutes',updated_at=v_now from public.sdf_qualification_intakes i,public.quote_requests r where j.job_id=p_job_id and i.intake_id=j.intake_id and r.id=i.quote_request_id and r.confirmation_sent_at is not null and j.status in ('pending','retry_wait') and j.next_attempt_at<=v_now and j.attempt_count<j.max_attempts and (j.kind<>'invitation' or j.invitation_generation=i.invitation_generation) returning j.job_id,j.intake_id,j.kind,j.template_version,j.attempt_count,j.encrypted_capability,i.customer_capability_digest::text,v_lease_token,v_now+interval '10 minutes';
end;
$$;

create function public.claim_next_sdf_qualification_email_job_v1()
returns table(job_id uuid,intake_id uuid,kind text,template_version text,attempt_count integer,encrypted_capability text,customer_capability_digest text,request_name text,request_email text,reason text,delivery_lease_token uuid,delivery_lease_expires_at timestamptz)
language plpgsql volatile security definer set search_path=public,pg_catalog as $$
declare v_job_id uuid; v_intake_id uuid; v_now timestamptz:=clock_timestamp(); v_lease_token uuid:=gen_random_uuid();
begin
  update public.sdf_qualification_intake_email_jobs as stale_job
  set status='retry_wait',locked_at=null,delivery_lease_token=null,delivery_lease_expires_at=null,next_attempt_at=v_now,last_error_code='STALE_PROCESSING_LEASE',updated_at=v_now
  where stale_job.status='processing' and stale_job.delivery_lease_expires_at<=v_now and stale_job.attempt_count<stale_job.max_attempts;
  select j.job_id,j.intake_id into v_job_id,v_intake_id from public.sdf_qualification_intake_email_jobs j
  join public.sdf_qualification_intakes i on i.intake_id=j.intake_id
  join public.quote_requests r on r.id=i.quote_request_id
  where j.kind in ('invitation','more_information') and j.status in ('pending','retry_wait') and j.next_attempt_at<=v_now and j.attempt_count<j.max_attempts and r.confirmation_sent_at is not null and (j.kind<>'invitation' or j.invitation_generation=i.invitation_generation)
  order by j.next_attempt_at,j.created_at limit 1;
  if v_job_id is null then return; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_intake_id::text,0));
  return query
  update public.sdf_qualification_intake_email_jobs j set status='processing',attempt_count=j.attempt_count+1,locked_at=v_now,delivery_lease_token=v_lease_token,delivery_lease_expires_at=v_now+interval '10 minutes',updated_at=v_now
  from public.sdf_qualification_intakes i,public.quote_requests r
  where j.job_id=v_job_id and i.intake_id=j.intake_id and r.id=i.quote_request_id and r.confirmation_sent_at is not null and j.status in ('pending','retry_wait') and j.next_attempt_at<=v_now and j.attempt_count<j.max_attempts and (j.kind<>'invitation' or j.invitation_generation=i.invitation_generation)
  returning j.job_id,j.intake_id,j.kind,j.template_version,j.attempt_count,coalesce(j.encrypted_capability,i.customer_capability_encrypted),i.customer_capability_digest::text,r.name,r.email,
    (select event.reason from public.sdf_qualification_intake_events event where event.intake_id=i.intake_id and event.idempotency_key=j.idempotency_key),v_lease_token,v_now+interval '10 minutes';
end;
$$;

create function public.validate_sdf_qualification_email_delivery_v1(p_job_id uuid,p_delivery_lease_token uuid)
returns boolean language sql stable security definer set search_path=public,pg_catalog as $$
  select coalesce((
    select job.status='processing' and job.delivery_lease_token=p_delivery_lease_token and job.delivery_lease_expires_at>clock_timestamp() and (job.kind<>'invitation' or job.invitation_generation=intake.invitation_generation)
    from public.sdf_qualification_intake_email_jobs job
    join public.sdf_qualification_intakes intake on intake.intake_id=job.intake_id
    where job.job_id=p_job_id
  ),false);
$$;

create function public.complete_sdf_qualification_email_job_v1(p_job_id uuid,p_delivery_lease_token uuid,p_succeeded boolean,p_retryable boolean,p_error_code text default null,p_provider_message_id text default null)
returns jsonb language plpgsql volatile security definer set search_path=public,lws_internal,pg_catalog as $$
declare v_job public.sdf_qualification_intake_email_jobs%rowtype; v_status public.quote_request_email_status;
begin
 select * into v_job from public.sdf_qualification_intake_email_jobs where job_id=p_job_id and delivery_lease_token=p_delivery_lease_token and delivery_lease_expires_at>clock_timestamp() for update;
 if not found or v_job.status<>'processing' then return null; end if;
 if v_job.kind='invitation' and v_job.invitation_generation<>(select invitation_generation from public.sdf_qualification_intakes where intake_id=v_job.intake_id) then
   update public.sdf_qualification_intake_email_jobs set status='failed',locked_at=null,last_error_code='OBSOLETE_INVITATION_GENERATION',updated_at=clock_timestamp() where job_id=p_job_id;
   return jsonb_build_object('status','failed','attempt_count',v_job.attempt_count);
 end if;
 v_status:=case when p_succeeded then 'sent'::public.quote_request_email_status when p_retryable and v_job.attempt_count<v_job.max_attempts then 'retry_wait'::public.quote_request_email_status else 'failed'::public.quote_request_email_status end;
 update public.sdf_qualification_intake_email_jobs set status=v_status,next_attempt_at=case when v_status='retry_wait' then clock_timestamp()+make_interval(secs=>least(3600,30*power(2,greatest(v_job.attempt_count-1,0))::integer)) else clock_timestamp() end,locked_at=null,delivery_lease_token=null,delivery_lease_expires_at=null,sent_at=case when p_succeeded then clock_timestamp() else sent_at end,provider_message_id=case when p_succeeded then p_provider_message_id else provider_message_id end,last_error_code=case when p_succeeded then null else left(coalesce(p_error_code,'UNKNOWN_ERROR'),120) end,encrypted_capability=case when p_succeeded then null else encrypted_capability end,updated_at=clock_timestamp() where job_id=p_job_id;
 if p_succeeded and v_job.kind='invitation' then update lws_internal.application_intake_automation_work w set phase='COMPLETED',claim_token=null,claimed_by=null,claimed_at=null,claim_expires_at=null,last_error_code=null where w.quote_request_id=(select quote_request_id from public.sdf_qualification_intakes where intake_id=v_job.intake_id) and w.phase='SDF_INTAKE'; end if;
 return jsonb_build_object('status',v_status,'attempt_count',v_job.attempt_count);
end;
$$;

create function public.execute_application_intake_automation_sdf_intake_v1(p_work_id bigint,p_claim_token uuid)
returns jsonb language plpgsql volatile security definer set search_path=lws_internal,public,pg_catalog as $$
declare v_work lws_internal.application_intake_automation_work%rowtype; v_result jsonb;
begin
 select * into v_work from lws_internal.application_intake_automation_work where work_id=p_work_id and phase='SDF_INTAKE' and claim_token=p_claim_token and claim_expires_at>clock_timestamp() and intake_due_at<=clock_timestamp() for update;
 if not found then return null; end if;
 select jsonb_build_object('outcome','invitation_pending','job_id',j.job_id,'intake_id',i.intake_id,'request_id',r.id,'request_name',r.name,'request_email',r.email,'template_version',j.template_version,'encrypted_capability',j.encrypted_capability,'customer_capability_digest',i.customer_capability_digest,'expires_at',i.customer_capability_expires_at) into v_result from public.sdf_qualification_intakes i join public.quote_requests r on r.id=i.quote_request_id join public.sdf_qualification_intake_email_jobs j on j.intake_id=i.intake_id and j.kind='invitation' and j.invitation_generation=i.invitation_generation where i.quote_request_id=v_work.quote_request_id and i.status='invited' and r.confirmation_sent_at is not null and j.status in ('pending','retry_wait') and j.next_attempt_at<=clock_timestamp() limit 1;
 return v_result;
end;
$$;

create or replace function lws_internal.resolve_operator_operational_status_v2(p_request_kind text,p_intake_status text,p_effective_access text,p_project_state text,p_has_acceptance boolean)
returns text language plpgsql stable set search_path=pg_catalog as $$
begin
 if p_request_kind not in ('website','slimme_documentenflow') then raise exception using errcode='22023',message='INVALID_OPERATOR_REQUEST_KIND'; end if;
 if p_request_kind='slimme_documentenflow' then
   if p_project_state is not null then return p_project_state; end if;
   if p_has_acceptance then return 'QUOTE_ACCEPTED'; end if;
   if p_intake_status in ('under_review','changes_requested','qualification_complete') then return 'REVIEWED'; end if;
   if p_intake_status='submitted' then return 'SUBMITTED'; end if;
   raise exception using errcode='22023',message='INVALID_SDF_OPERATIONAL_AUTHORITY';
 end if;
 if p_effective_access not in ('ACTIVE','INTERRUPTED','EXPIRED','CANCELLED') then raise exception using errcode='22023',message='INVALID_OPERATOR_EFFECTIVE_ACCESS'; end if;
 if p_effective_access='CANCELLED' then return 'CANCELLED'; end if;
 if p_project_state is not null then return p_project_state; end if;
 if p_has_acceptance then return 'QUOTE_ACCEPTED'; end if;
 if p_intake_status='reviewed' then return 'REVIEWED'; end if;
 if p_intake_status='submitted' then return 'SUBMITTED'; end if;
 raise exception using errcode='22023',message='INVALID_OPERATOR_OPERATIONAL_STATUS';
end;
$$;

create or replace view lws_internal.operator_application_readmodel_v2 as
select request.id quote_request_id,request.application_reference,request.support_reference,request.name,request.company organization,request.request_kind,dossier_state.state zone,lws_internal.resolve_operator_operational_status_v2(request.request_kind,intake.status::text,public.resolve_quote_request_intake_effective_access_v1(intake.access_state,intake.access_token_expires_at,statement_timestamp()),project.current_state,acceptance.id is not null) operational_status,intake.submitted_at dossier_date
from public.quote_request_intakes intake join public.quote_requests request on request.id=intake.quote_request_id and request.record_classification='production' and request.request_kind='website' join lws_internal.operator_dossier_states dossier_state on dossier_state.quote_request_id=request.id
left join lateral(select accepted.id from public.quote_request_quotation_approvals approval join public.quote_request_quotation_issuances issuance on issuance.approval_id=approval.id join public.quote_request_quotation_acceptances accepted on accepted.issuance_id=issuance.id where approval.quote_request_id=request.id order by accepted.accepted_at desc limit 1) acceptance on true
left join public.commercial_projects project on project.acceptance_id=acceptance.id where intake.status in ('submitted','reviewed') and intake.submitted_at is not null
union all
select request.id,request.application_reference,request.support_reference,request.name,request.company,request.request_kind,dossier_state.state,lws_internal.resolve_operator_operational_status_v2(request.request_kind,intake.status::text,null,null,quotation_acceptance.quotation_id is not null),coalesce(intake.submitted_at,intake.updated_at)
from public.sdf_qualification_intakes intake join public.quote_requests request on request.id=intake.quote_request_id and request.record_classification='production' and request.request_kind='slimme_documentenflow' join lws_internal.operator_dossier_states dossier_state on dossier_state.quote_request_id=request.id left join public.sdf_quotations quotation on quotation.quote_request_id=request.id left join public.sdf_quotation_acceptances quotation_acceptance on quotation_acceptance.quotation_id=quotation.quotation_id where intake.status in ('submitted','under_review','changes_requested','qualification_complete');

create or replace view lws_internal.operator_pending_sdf_intakes_v1 as
select
  request.id as quote_request_id,
  intake.intake_id,
  request.name,
  request.company as organization,
  request.email,
  request.phone,
  request.request_kind,
  request.sdf_package,
  'Slimme documentenflow - '||request.sdf_package as website_type,
  intake.invited_at as invitation_created_at,
  invitation.sent_at as invitation_sent_at,
  invitation.status::text as invitation_delivery_status,
  intake.status::text as intake_status,
  case when intake.customer_capability_expires_at<=clock_timestamp() then 'EXPIRED' else 'ACTIVE' end as effective_access,
  intake.customer_capability_expires_at as access_token_expires_at,
  intake.draft_revision as lifecycle_revision,
  'ACTIVE'::text as retention_state,
  null::timestamptz as archived_at,
  0::bigint as retention_revision,
  false as can_permanently_delete,
  null::text as delete_block_reason,
  case when intake.status='in_progress' then intake.updated_at else null end as started_at,
  0 as current_reminder_cycle,
  null::timestamptz as reminder_1_sent_at,
  null::timestamptz as reminder_2_sent_at,
  greatest(intake.updated_at,coalesce(invitation.updated_at,intake.updated_at)) as last_activity_at
from public.sdf_qualification_intakes intake
join public.quote_requests request on request.id=intake.quote_request_id
left join public.sdf_qualification_intake_email_jobs invitation
  on invitation.intake_id=intake.intake_id and invitation.kind='invitation' and invitation.invitation_generation=intake.invitation_generation
where request.record_classification='production'
  and request.request_kind='slimme_documentenflow'
  and intake.status in ('invited','in_progress');

create function public.list_operator_pending_sdf_intakes_v1(p_actor_auth_user_id uuid)
returns jsonb language plpgsql stable security definer
set search_path=lws_internal,public,pg_catalog as $$
declare v_items jsonb;
begin
  perform lws_internal.assert_operator_application_actor_v2(p_actor_auth_user_id);
  select coalesce(jsonb_agg(to_jsonb(pending) order by pending.last_activity_at desc,pending.quote_request_id desc),'[]'::jsonb)
  into v_items from lws_internal.operator_pending_sdf_intakes_v1 pending;
  return jsonb_build_object('items',v_items);
end;
$$;

revoke all on function lws_internal.assert_sdf_owner_v1(),lws_internal.sdf_payload_valid_v1(jsonb,boolean),lws_internal.reject_sdf_qualification_history_mutation_v1(),lws_internal.advance_sdf_automation_after_confirmation_v1(),lws_internal.advance_sdf_automation_from_confirmation_job_v1() from public,anon,authenticated,service_role;
revoke all on function public.consume_sdf_qualification_rate_limit_v1(text,text),public.allow_sdf_qualification_intake_v1(uuid,text,text,uuid),public.reissue_sdf_qualification_intake_v1(uuid,text,text,uuid),public.inspect_sdf_qualification_intake_v1(text),public.save_sdf_qualification_intake_draft_v1(text,bigint,jsonb),public.submit_sdf_qualification_intake_v1(text,bigint,boolean,text,text,uuid),public.inspect_sdf_qualification_intake_for_operator_v1(uuid),public.transition_sdf_qualification_intake_v1(uuid,text,text,uuid,text),public.execute_application_intake_automation_sdf_confirmation_v1(bigint,uuid),public.execute_application_intake_automation_sdf_intake_v1(bigint,uuid),public.claim_sdf_qualification_email_job_v1(uuid),public.claim_next_sdf_qualification_email_job_v1(),public.validate_sdf_qualification_email_delivery_v1(uuid,uuid),public.complete_sdf_qualification_email_job_v1(uuid,uuid,boolean,boolean,text,text) from public,anon,authenticated,service_role;
revoke all on function public.authorize_sdf_quotation_preparation_v1(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.list_operator_pending_sdf_intakes_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.consume_sdf_qualification_rate_limit_v1(text,text),public.allow_sdf_qualification_intake_v1(uuid,text,text,uuid),public.reissue_sdf_qualification_intake_v1(uuid,text,text,uuid),public.inspect_sdf_qualification_intake_v1(text),public.save_sdf_qualification_intake_draft_v1(text,bigint,jsonb),public.submit_sdf_qualification_intake_v1(text,bigint,boolean,text,text,uuid),public.inspect_sdf_qualification_intake_for_operator_v1(uuid),public.transition_sdf_qualification_intake_v1(uuid,text,text,uuid,text),public.execute_application_intake_automation_sdf_confirmation_v1(bigint,uuid),public.execute_application_intake_automation_sdf_intake_v1(bigint,uuid),public.claim_sdf_qualification_email_job_v1(uuid),public.claim_next_sdf_qualification_email_job_v1(),public.validate_sdf_qualification_email_delivery_v1(uuid,uuid),public.complete_sdf_qualification_email_job_v1(uuid,uuid,boolean,boolean,text,text) to service_role;
grant execute on function public.allow_sdf_qualification_intake_v1(uuid,text,text,uuid),public.reissue_sdf_qualification_intake_v1(uuid,text,text,uuid),public.inspect_sdf_qualification_intake_for_operator_v1(uuid),public.transition_sdf_qualification_intake_v1(uuid,text,text,uuid,text) to authenticated;
grant execute on function public.authorize_sdf_quotation_preparation_v1(uuid,uuid) to authenticated;
grant execute on function public.list_operator_pending_sdf_intakes_v1(uuid) to authenticated;
