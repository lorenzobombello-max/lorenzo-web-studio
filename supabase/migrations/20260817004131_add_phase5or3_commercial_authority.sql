-- Phase 5O-R3 durable migration: commercial command guards fail closed while preserving immutable-money error precedence.
-- R2 ACL and service_role schema-USAGE decisions remain unchanged; owner bootstrap is not invoked.

-- BEGIN PHASE5OR3 SOURCE: 001_commercial_schema.sql
-- Source: Phase 5K 002_core_project.sql
create table public.commercial_customers (
  customer_id uuid primary key default gen_random_uuid(),
  acceptance_id uuid not null unique references public.quote_request_quotation_acceptances(id),
  identity_sha256 char(64) not null check (identity_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp()
)
;

create table public.commercial_projects (
  project_id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.commercial_customers(customer_id),
  quotation_issuance_id uuid not null unique references public.quote_request_quotation_issuances(id),
  acceptance_id uuid not null unique references public.quote_request_quotation_acceptances(id),
  accepted_total_minor bigint not null check (accepted_total_minor >= 0),
  currency char(3) not null check (currency = 'EUR'),
  m1_minor bigint not null check (m1_minor >= 0),
  m2_minor bigint not null check (m2_minor >= 0),
  m3_minor bigint not null check (m3_minor >= 0),
  current_state text not null,
  revision bigint not null default 0 check (revision >= 0),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint commercial_project_money_coherent check (accepted_total_minor = m1_minor + m2_minor + m3_minor)
)
;

-- Source: Phase 5K 003_obligations_payment.sql
create table public.commercial_obligations (
  obligation_id uuid primary key default gen_random_uuid(), project_id uuid not null references public.commercial_projects(project_id),
  obligation_type text not null check (obligation_type in ('PROJECT_MILESTONE','CHANGE_ORDER','RECURRING','EXTERNAL_COST')),
  milestone smallint, amount_minor bigint not null check (amount_minor >= 0), expected_reference text not null,
  status text not null, created_at timestamptz not null default clock_timestamp(),
  constraint obligation_milestone_shape check ((obligation_type='PROJECT_MILESTONE' and milestone between 1 and 3) or (obligation_type<>'PROJECT_MILESTONE' and milestone is null)),
  unique(project_id,obligation_type,milestone), unique(project_id,expected_reference)
)
;

create table public.commercial_documents (
  commercial_document_id uuid primary key default gen_random_uuid(), project_id uuid not null references public.commercial_projects(project_id),
  obligation_id uuid references public.commercial_obligations(obligation_id), document_type text not null, workflow_state text not null,
  template_id text not null, template_version text not null, commercial_reference text not null unique,
  status text not null check (status='NON_PRODUCTION_WORKING'), created_at timestamptz not null default clock_timestamp()
)
;

create table public.payment_expectations (
  payment_expectation_id uuid primary key default gen_random_uuid(), project_id uuid not null references public.commercial_projects(project_id),
  obligation_id uuid not null unique references public.commercial_obligations(obligation_id), expected_amount_minor bigint not null check(expected_amount_minor>=0),
  expected_reference text not null unique, created_at timestamptz not null default clock_timestamp()
)
;

create table public.payment_evidence (
  payment_evidence_id uuid primary key default gen_random_uuid(), project_id uuid not null references public.commercial_projects(project_id),
  obligation_id uuid not null references public.commercial_obligations(obligation_id), received_amount_minor bigint not null check(received_amount_minor>=0),
  transaction_date date not null, transaction_reference text not null unique, evidence_reference text not null unique,
  bank_account_fingerprint char(64) not null check(bank_account_fingerprint ~ '^[0-9a-f]{64}$'), verified_by text not null,
  verified_at timestamptz not null, created_at timestamptz not null default clock_timestamp()
)
;

create table public.payment_reconciliations (
  payment_reconciliation_id uuid primary key default gen_random_uuid(), payment_evidence_id uuid not null unique references public.payment_evidence(payment_evidence_id),
  project_id uuid not null references public.commercial_projects(project_id), obligation_id uuid not null references public.commercial_obligations(obligation_id),
  match_status text not null check(match_status in('UNVERIFIED','MATCHED','PARTIAL','OVERPAYMENT','REFERENCE_MISMATCH','AMOUNT_MISMATCH','DUPLICATE_EVIDENCE','REJECTED')),
  decided_by text not null check(decided_by='SERVER_COMMAND_LAYER'), decided_at timestamptz not null default clock_timestamp()
)
;

-- Source: Phase 5K 004_events_audit.sql
create table public.workflow_events (
  workflow_event_id bigint generated always as identity primary key, project_id uuid not null references public.commercial_projects(project_id),
  previous_state text not null, new_state text not null, project_revision bigint not null check(project_revision>0), command_id uuid not null,
  occurred_at timestamptz not null default clock_timestamp(), unique(project_id,project_revision)
)
;

create table public.audit_events (
  audit_event_id bigint generated always as identity primary key, project_id uuid not null references public.commercial_projects(project_id),
  event_type text not null, actor text not null, command_id uuid, occurred_at timestamptz not null default clock_timestamp(),
  evidence_reference text, metadata jsonb not null default '{}'::jsonb,
  constraint audit_metadata_safe check(not(metadata ?| array['token','token_digest','session','credential','raw_bank','internal_note','customer_content','service_role_key']))
)
;

create table public.idempotency_ledger (
  operation_id uuid primary key default gen_random_uuid(), actor_id text not null, project_id uuid not null references public.commercial_projects(project_id),
  command_type text not null, idempotency_key uuid not null, request_fingerprint char(64) not null check(request_fingerprint ~ '^[0-9a-f]{64}$'),
  result_reference text not null, result_payload jsonb not null, created_at timestamptz not null default clock_timestamp(),
  unique(actor_id,project_id,command_type,idempotency_key)
)
;

-- Source: Phase 5K 005_preview_security.sql
create table public.preview_access (
  preview_access_id uuid primary key default gen_random_uuid(), project_id uuid not null references public.commercial_projects(project_id),
  preview_version_id uuid not null, token_digest char(64) not null unique check(token_digest ~ '^[0-9a-f]{64}$'),
  status text not null check(status in('ACTIVE','EXPIRED','REVOKED')), expires_at timestamptz not null, revision bigint not null default 1 check(revision>0),
  created_by text not null, created_at timestamptz not null default clock_timestamp(), revoked_at timestamptz,
  constraint preview_access_state_shape check((status='ACTIVE' and revoked_at is null) or (status in('EXPIRED','REVOKED')))
)
;

create unique index preview_one_active_per_version on public.preview_access(project_id,preview_version_id) where status='ACTIVE'
;

create table public.preview_sessions (
  preview_session_id uuid primary key default gen_random_uuid(), preview_access_id uuid not null references public.preview_access(preview_access_id),
  project_id uuid not null references public.commercial_projects(project_id), session_digest char(64) not null unique check(session_digest ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null, created_at timestamptz not null default clock_timestamp(), revoked_at timestamptz
)
;

-- Source: Phase 5K 006_feedback_revision_approval.sql
create table public.customer_feedback (
  feedback_id uuid primary key default gen_random_uuid(), project_id uuid not null references public.commercial_projects(project_id),
  preview_access_id uuid not null references public.preview_access(preview_access_id), feedback_type text not null check(feedback_type in('GENERAL','CONTENT','DESIGN','FUNCTIONALITY','MOBILE','OTHER')),
  subject text not null check(length(subject) between 1 and 120), customer_message text not null check(length(customer_message) between 1 and 4000),
  page_reference text, status text not null check(status in('NEW','REVIEWED','IN_PROGRESS','RESOLVED','REJECTED','POTENTIAL_SCOPE_CHANGE')),
  revision bigint not null default 1 check(revision>0), submitted_at timestamptz not null default clock_timestamp()
)
;

create table public.feedback_internal_notes (
  internal_note_id uuid primary key default gen_random_uuid(), feedback_id uuid not null references public.customer_feedback(feedback_id),
  project_id uuid not null references public.commercial_projects(project_id), note text not null check(length(note) between 1 and 2000),
  actor text not null, created_at timestamptz not null default clock_timestamp()
)
;

create table public.project_revisions (
  revision_id uuid primary key default gen_random_uuid(), project_id uuid not null references public.commercial_projects(project_id),
  feedback_id uuid not null unique references public.customer_feedback(feedback_id), revision_number integer not null check(revision_number>0),
  classification text not null check(classification in('INCLUDED_REVISION','CLARIFICATION_REQUIRED','POTENTIAL_SCOPE_CHANGE','NO_ACTION_REQUIRED')),
  status text not null check(status in('OPEN','IN_PROGRESS','READY_FOR_PREVIEW','COMPLETED','CANCELLED')),
  evidence_reference text not null, revision bigint not null default 1 check(revision>0), created_at timestamptz not null default clock_timestamp(), completed_at timestamptz,
  unique(project_id,revision_number)
)
;

create table public.preview_versions (
  preview_version_id uuid primary key default gen_random_uuid(), project_id uuid not null references public.commercial_projects(project_id),
  revision_id uuid references public.project_revisions(revision_id), version_number integer not null check(version_number>0),
  content_reference text not null, content_sha256 char(64) not null check(content_sha256 ~ '^[0-9a-f]{64}$'),
  status text not null check(status in('CURRENT','SUPERSEDED')), created_at timestamptz not null default clock_timestamp(), unique(project_id,version_number)
)
;

create unique index preview_one_current_version on public.preview_versions(project_id) where status='CURRENT'
;

create table public.customer_approvals (
  approval_id uuid primary key default gen_random_uuid(), project_id uuid not null references public.commercial_projects(project_id),
  preview_access_id uuid not null references public.preview_access(preview_access_id), preview_version_id uuid not null references public.preview_versions(preview_version_id),
  statement_version text not null, statement_sha256 char(64) not null check(statement_sha256 ~ '^[0-9a-f]{64}$'),
  status text not null check(status in('CURRENT','SUPERSEDED')), submitted_at timestamptz not null default clock_timestamp(),
  unique(project_id,preview_version_id)
)
;

create unique index approval_one_current_per_project on public.customer_approvals(project_id) where status='CURRENT'
;

-- Source: Phase 5K 007_separate_commercial_records.sql
create table public.change_orders (
  change_order_id uuid primary key default gen_random_uuid(), project_id uuid not null references public.commercial_projects(project_id),
  original_quotation_issuance_id uuid not null references public.quote_request_quotation_issuances(id), feedback_id uuid not null references public.customer_feedback(feedback_id),
  change_request_reference text not null unique, separate_amount_minor bigint check(separate_amount_minor>=0),
  status text not null check(status in('CHANGE_ORDER_REQUIRED','PROPOSED','ACCEPTED','REJECTED','CANCELLED')), created_at timestamptz not null default clock_timestamp()
)
;

create table public.recurring_services (
  recurring_service_id uuid primary key default gen_random_uuid(), project_id uuid not null references public.commercial_projects(project_id),
  service_type text not null check(service_type in('HOSTING','MAINTENANCE','SEO_CARE_GROWTH')),
  schedule text not null check(schedule in('YEARLY_IN_ADVANCE','MONTHLY_IN_ADVANCE')), status text not null, created_at timestamptz not null default clock_timestamp()
)
;

create table public.external_costs (
  external_cost_id uuid primary key default gen_random_uuid(), project_id uuid not null references public.commercial_projects(project_id),
  route text not null check(route in('DIRECT_CUSTOMER_PAYMENT','LWS_PURCHASE_AFTER_PREPAYMENT')), amount_minor bigint not null check(amount_minor>=0),
  prepayment_evidence_reference text, automatic_markup boolean not null default false check(automatic_markup=false), created_at timestamptz not null default clock_timestamp()
)
;

-- Source: Phase 5K 008_relational_constraints.sql
alter table public.preview_access add constraint preview_access_version_fk foreign key(preview_version_id) references public.preview_versions(preview_version_id)
;
do $$ begin if not exists(select 1 from pg_constraint where conname='commercial_project_money_coherent') then raise exception 'MONEY_CONSTRAINT_MISSING';end if;end $$;
-- END PHASE5OR3 SOURCE: 001_commercial_schema.sql

-- BEGIN PHASE5OR3 SOURCE: 002_operator_authority.sql
create table public.commercial_operators (
  operator_id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users(id),
  display_name text not null check (nullif(btrim(display_name),'') is not null),
  role text not null check (role in ('owner','admin','operator','reviewer','read_only')),
  status text not null check (status in ('ACTIVE','DISABLED','REVOKED')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  constraint commercial_operator_status_shape check (
    (status in ('ACTIVE','DISABLED') and revoked_at is null)
    or (status='REVOKED' and revoked_at is not null)
  )
);

create table public.commercial_operator_project_grants (
  operator_id uuid not null references public.commercial_operators(operator_id),
  project_id uuid not null references public.commercial_projects(project_id),
  access_level text not null check (access_level in ('operator','reviewer','read_only')),
  granted_at timestamptz not null default clock_timestamp(),
  granted_by uuid references public.commercial_operators(operator_id),
  revoked_at timestamptz,
  primary key(operator_id,project_id)
);

create index commercial_operator_project_grants_project_idx
  on public.commercial_operator_project_grants(project_id,operator_id)
  where revoked_at is null;

alter table public.commercial_operators enable row level security;
alter table public.commercial_operators force row level security;
alter table public.commercial_operator_project_grants enable row level security;
alter table public.commercial_operator_project_grants force row level security;

revoke all privileges on table public.commercial_operators from public,anon,authenticated,service_role;
revoke all privileges on table public.commercial_operator_project_grants from public,anon,authenticated,service_role;

comment on table public.commercial_operators is
  'Human commercial operator authority. Security identity is auth_user_id/JWT sub; display_name and email are never authorization inputs.';
comment on table public.commercial_operator_project_grants is
  'Explicit project scope for operator/reviewer/read_only roles. Owner/admin global scope is resolved server-side and is not represented by blanket rows.';
-- END PHASE5OR3 SOURCE: 002_operator_authority.sql

-- BEGIN PHASE5OR3 SOURCE: 003_authority_guards.sql
create function public.commercial_prevent_history_mutation() returns trigger
language plpgsql set search_path=public as $$
begin raise exception using errcode='55000',message='APPEND_ONLY_AUTHORITY'; end $$;

create function public.commercial_guard_project_mutation() returns trigger
language plpgsql set search_path=public as $$
begin
  if tg_op='DELETE' then raise exception using errcode='55000',message='COMMERCIAL_PROJECT_IMMUTABLE'; end if;
  if current_setting('lws.commercial_command',true) is distinct from 'on'
     and row(old.customer_id,old.quotation_issuance_id,old.acceptance_id,old.accepted_total_minor,old.currency,old.m1_minor,old.m2_minor,old.m3_minor)
         is not distinct from row(new.customer_id,new.quotation_issuance_id,new.acceptance_id,new.accepted_total_minor,new.currency,new.m1_minor,new.m2_minor,new.m3_minor) then
    raise exception using errcode='55000',message='DIRECT_STATE_WRITE_FORBIDDEN';
  end if;
  if row(old.customer_id,old.quotation_issuance_id,old.acceptance_id,old.accepted_total_minor,old.currency,old.m1_minor,old.m2_minor,old.m3_minor)
     is distinct from row(new.customer_id,new.quotation_issuance_id,new.acceptance_id,new.accepted_total_minor,new.currency,new.m1_minor,new.m2_minor,new.m3_minor) then
    raise exception using errcode='55000',message='ACCEPTED_MONEY_IMMUTABLE';
  end if;
  if new.revision<>old.revision+1 then raise exception using errcode='40001',message='CONCURRENT_MODIFICATION'; end if;
  return new;
end $$;

create function public.commercial_guard_controlled_status() returns trigger
language plpgsql set search_path=public as $$
begin
  if tg_op='DELETE' or current_setting('lws.commercial_command',true) is distinct from 'on' then
    raise exception using errcode='55000',message='DIRECT_AUTHORITY_WRITE_FORBIDDEN';
  end if;
  return new;
end $$;

revoke execute on function
  public.commercial_prevent_history_mutation(),
  public.commercial_guard_project_mutation(),
  public.commercial_guard_controlled_status()
from public,anon,authenticated,service_role;

create trigger trg_commercial_project_guard before update or delete on public.commercial_projects for each row execute function public.commercial_guard_project_mutation();

do $$ declare t text; begin
  foreach t in array array['commercial_customers','payment_evidence','payment_reconciliations','workflow_events','audit_events','feedback_internal_notes','idempotency_ledger'] loop
    execute format('create trigger trg_commercial_%I_immutable before update or delete on public.%I for each row execute function public.commercial_prevent_history_mutation()',t,t);
  end loop;
end $$;

create trigger trg_commercial_preview_access_guard before update or delete on public.preview_access for each row execute function public.commercial_guard_controlled_status();
create trigger trg_commercial_preview_session_guard before update or delete on public.preview_sessions for each row execute function public.commercial_guard_controlled_status();
create trigger trg_commercial_feedback_guard before update or delete on public.customer_feedback for each row execute function public.commercial_guard_controlled_status();
create trigger trg_commercial_revision_guard before update or delete on public.project_revisions for each row execute function public.commercial_guard_controlled_status();
create trigger trg_commercial_version_guard before update or delete on public.preview_versions for each row execute function public.commercial_guard_controlled_status();
create trigger trg_commercial_approval_guard before update or delete on public.customer_approvals for each row execute function public.commercial_guard_controlled_status();
-- END PHASE5OR3 SOURCE: 003_authority_guards.sql

-- BEGIN PHASE5OR3 SOURCE: 004_private_transaction_core.sql
create schema if not exists lws_internal authorization postgres;
revoke all on schema lws_internal from public,anon,authenticated,service_role;
create or replace function lws_internal.commercial_fingerprint_v1(p_value jsonb) returns text language sql immutable set search_path=public,extensions as $$
  select encode(extensions.digest(convert_to(p_value::text,'UTF8'),'sha256'),'hex')
$$;

create or replace function lws_internal.record_quotation_acceptance_core_v1(
  p_audit_actor text,p_project_id uuid,p_acceptance_id uuid,p_expected_total_minor bigint,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path=lws_internal,public,extensions,pg_catalog as $$
declare v_acceptance public.quote_request_quotation_acceptances%rowtype;v_issuance public.quote_request_quotation_issuances%rowtype;v_approval public.quote_request_quotation_approvals%rowtype;v_customer_id uuid;v_total bigint;v_fp text;v_old public.idempotency_ledger%rowtype;v_result jsonb;
begin
  if nullif(btrim(p_audit_actor),'') is null then raise exception using errcode='42501',message='UNAUTHORIZED';end if;
  v_fp:=lws_internal.commercial_fingerprint_v1(jsonb_build_object('actor',p_audit_actor,'project',p_project_id,'acceptance',p_acceptance_id,'total',p_expected_total_minor));
  select * into v_old from public.idempotency_ledger where actor_id=p_audit_actor and project_id=p_project_id and command_type='record_quotation_acceptance' and idempotency_key=p_idempotency_key;
  if found then if v_old.request_fingerprint<>v_fp then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';end if;return v_old.result_payload;end if;
  select * into v_acceptance from public.quote_request_quotation_acceptances where id=p_acceptance_id;if not found then raise exception using errcode='23503',message='ACCEPTANCE_NOT_FOUND';end if;
  select * into strict v_issuance from public.quote_request_quotation_issuances where id=v_acceptance.issuance_id;
  select * into strict v_approval from public.quote_request_quotation_approvals where id=v_issuance.approval_id;
  v_total:=(v_approval.approved_payload->'totals'->>'one_time_subtotal_minor')::bigint;
  if v_total<>p_expected_total_minor or v_total<0 then raise exception using errcode='23514',message='ACCEPTED_TOTAL_MISMATCH';end if;
  insert into public.commercial_customers(acceptance_id,identity_sha256) values(p_acceptance_id,v_acceptance.customer_identity_sha256) returning customer_id into v_customer_id;
  insert into public.commercial_projects(project_id,customer_id,quotation_issuance_id,acceptance_id,accepted_total_minor,currency,m1_minor,m2_minor,m3_minor,current_state,revision)
  values(p_project_id,v_customer_id,v_acceptance.issuance_id,p_acceptance_id,v_total,'EUR',floor(v_total*40/100),floor(v_total*40/100),v_total-floor(v_total*40/100)-floor(v_total*40/100),'QUOTE_ACCEPTED',1);
  insert into public.workflow_events(project_id,previous_state,new_state,project_revision,command_id) values(p_project_id,'QUOTE_SENT','QUOTE_ACCEPTED',1,p_idempotency_key);
  insert into public.audit_events(project_id,event_type,actor,command_id,metadata) values(p_project_id,'RECORD_QUOTATION_ACCEPTANCE',p_audit_actor,p_idempotency_key,jsonb_build_object('acceptance_id',p_acceptance_id));
  v_result:=jsonb_build_object('project_id',p_project_id,'resulting_state','QUOTE_ACCEPTED','revision',1,'accepted_total_minor',v_total);
  insert into public.idempotency_ledger(actor_id,project_id,command_type,idempotency_key,request_fingerprint,result_reference,result_payload) values(p_audit_actor,p_project_id,'record_quotation_acceptance',p_idempotency_key,v_fp,p_project_id::text,v_result);
  return v_result;
end $$;

create or replace function lws_internal.execute_commercial_command_core_v1(
  p_audit_actor text,p_project_id uuid,p_command_type text,p_expected_state text,p_expected_revision bigint,p_idempotency_key uuid,p_payload jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=lws_internal,public,extensions,pg_catalog as $$
declare v_project public.commercial_projects%rowtype;v_old public.idempotency_ledger%rowtype;v_fp text;v_state text;v_result jsonb;v_evidence public.payment_evidence%rowtype;v_expect public.payment_expectations%rowtype;v_match text;v_milestone int;v_access public.preview_access%rowtype;v_feedback public.customer_feedback%rowtype;v_revision public.project_revisions%rowtype;v_version public.preview_versions%rowtype;v_id uuid;v_changes_state boolean:=false;
begin
  if nullif(btrim(p_audit_actor),'') is null or p_payload ?| array['resulting_state','current_state','match_status','fiscal_production_enabled'] then raise exception using errcode='42501',message='DIRECT_STATE_WRITE_FORBIDDEN';end if;
  v_fp:=lws_internal.commercial_fingerprint_v1(jsonb_build_object('actor',p_audit_actor,'project',p_project_id,'command',p_command_type,'state',p_expected_state,'revision',p_expected_revision,'payload',p_payload));
  select * into v_old from public.idempotency_ledger where actor_id=p_audit_actor and project_id=p_project_id and command_type=p_command_type and idempotency_key=p_idempotency_key;
  if found then if v_old.request_fingerprint<>v_fp then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';end if;return v_old.result_payload;end if;
  select * into v_project from public.commercial_projects where project_id=p_project_id for update;if not found then raise exception using errcode='23503',message='PROJECT_NOT_FOUND';end if;
  if v_project.current_state<>p_expected_state or v_project.revision<>p_expected_revision then raise exception using errcode='40001',message='CONCURRENT_MODIFICATION';end if;
  v_state:=v_project.current_state;
  if p_command_type='prepare_milestone_1' then
    if v_state<>'QUOTE_ACCEPTED' then raise exception using errcode='P0001',message='INVALID_STATE';end if;
    insert into public.commercial_obligations(project_id,obligation_type,milestone,amount_minor,expected_reference,status) values
      (p_project_id,'PROJECT_MILESTONE',1,v_project.m1_minor,'LWS-MILESTONE-'||p_project_id::text||'-M1','OPEN'),
      (p_project_id,'PROJECT_MILESTONE',2,v_project.m2_minor,'LWS-MILESTONE-'||p_project_id::text||'-M2','OPEN'),
      (p_project_id,'PROJECT_MILESTONE',3,v_project.m3_minor,'LWS-MILESTONE-'||p_project_id::text||'-M3','OPEN');
    insert into public.payment_expectations(project_id,obligation_id,expected_amount_minor,expected_reference)
      select project_id,obligation_id,amount_minor,expected_reference from public.commercial_obligations where project_id=p_project_id;
    v_state:='M1_PAYMENT_PENDING';v_changes_state:=true;
  elsif p_command_type='record_payment_evidence' then
    if p_payload->>'bank_iban'='BE34 1500 3429 84' then raise exception using errcode='23514',message='FORBIDDEN_OLD_IBAN';end if;
    if p_payload->>'bank_iban'<>'BE42 7380 5510 8954' then raise exception using errcode='23514',message='UNAPPROVED_BANK';end if;
    select * into v_expect from public.payment_expectations where project_id=p_project_id and expected_reference=p_payload->>'expected_reference';if not found then raise exception using errcode='23503',message='EXPECTATION_NOT_FOUND';end if;
    insert into public.payment_evidence(project_id,obligation_id,received_amount_minor,transaction_date,transaction_reference,evidence_reference,bank_account_fingerprint,verified_by,verified_at)
    values(p_project_id,v_expect.obligation_id,(p_payload->>'received_amount_minor')::bigint,(p_payload->>'transaction_date')::date,p_payload->>'transaction_reference',p_payload->>'evidence_reference',lws_internal.commercial_fingerprint_v1(to_jsonb(p_payload->>'bank_iban')),p_audit_actor,clock_timestamp()) returning * into v_evidence;
  elsif p_command_type='reconcile_payment' then
    select * into v_evidence from public.payment_evidence where payment_evidence_id=(p_payload->>'payment_evidence_id')::uuid and project_id=p_project_id;if not found then raise exception using errcode='23503',message='PAYMENT_EVIDENCE_NOT_FOUND';end if;
    select * into strict v_expect from public.payment_expectations where obligation_id=v_evidence.obligation_id;
    if exists(select 1 from public.payment_reconciliations where payment_evidence_id=v_evidence.payment_evidence_id) then v_match:='DUPLICATE_EVIDENCE';
    elsif v_evidence.received_amount_minor<v_expect.expected_amount_minor then v_match:='PARTIAL';
    elsif v_evidence.received_amount_minor>v_expect.expected_amount_minor then v_match:='OVERPAYMENT';else v_match:='MATCHED';end if;
    insert into public.payment_reconciliations(payment_evidence_id,project_id,obligation_id,match_status,decided_by) values(v_evidence.payment_evidence_id,p_project_id,v_evidence.obligation_id,v_match,'SERVER_COMMAND_LAYER');
  elsif p_command_type='confirm_payment' then
    v_milestone:=(p_payload->>'milestone')::int;
    select pe.* into v_expect from public.payment_expectations pe join public.commercial_obligations co using(obligation_id) where pe.project_id=p_project_id and co.milestone=v_milestone;
    if not found or not exists(select 1 from public.payment_reconciliations where obligation_id=v_expect.obligation_id and match_status='MATCHED') then raise exception using errcode='P0001',message='PAYMENT_NOT_MATCHED';end if;
    if v_milestone=1 and v_state='M1_PAYMENT_PENDING' then v_state:='M1_PAYMENT_RECEIVED';elsif v_milestone=2 and v_state='PREVIEW_READY' then v_state:='M2_PAYMENT_RECEIVED';elsif v_milestone=3 and v_state='FINAL_APPROVAL_RECORDED' then v_state:='FULL_PAYMENT_RECEIVED';else raise exception using errcode='P0001',message='INVALID_STATE';end if;v_changes_state:=true;
  elsif p_command_type='release_project' then if v_state<>'M1_PAYMENT_RECEIVED' then raise exception using errcode='P0001',message='PAYMENT_NOT_MATCHED';end if;v_state:='PROJECT_RELEASED';v_changes_state:=true;
  elsif p_command_type='record_preview_ready' then if v_state<>'PROJECT_RELEASED' then raise exception using errcode='P0001',message='INVALID_STATE';end if;insert into public.preview_versions(project_id,version_number,content_reference,content_sha256,status) values(p_project_id,1,p_payload->>'content_reference',p_payload->>'content_sha256','CURRENT') returning * into v_version;v_state:='PREVIEW_READY';v_changes_state:=true;
  elsif p_command_type='activate_preview_access' then
    if (p_payload->>'token_digest') !~ '^[0-9a-f]{64}$' or (p_payload->>'expires_at')::timestamptz<=clock_timestamp() then raise exception using errcode='22023',message='INVALID_PREVIEW_CREDENTIAL';end if;
    select * into v_version from public.preview_versions where project_id=p_project_id and status='CURRENT';
    insert into public.preview_access(project_id,preview_version_id,token_digest,status,expires_at,created_by) values(p_project_id,v_version.preview_version_id,p_payload->>'token_digest','ACTIVE',(p_payload->>'expires_at')::timestamptz,p_audit_actor) returning * into v_access;
  elsif p_command_type='revoke_preview_access' then perform set_config('lws.commercial_command','on',true);update public.preview_access set status='REVOKED',revoked_at=clock_timestamp(),revision=revision+1 where preview_access_id=(p_payload->>'preview_access_id')::uuid and project_id=p_project_id and status='ACTIVE' returning * into v_access;if not found then raise exception using errcode='P0001',message='ACCESS_NOT_ACTIVE';end if;update public.preview_sessions set revoked_at=clock_timestamp() where preview_access_id=v_access.preview_access_id and revoked_at is null;perform set_config('lws.commercial_command','',true);
  elsif p_command_type='submit_customer_feedback' then
    select * into v_access from public.preview_access where preview_access_id=(p_payload->>'preview_access_id')::uuid and project_id=p_project_id and status='ACTIVE' and expires_at>clock_timestamp();if not found then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
    insert into public.customer_feedback(project_id,preview_access_id,feedback_type,subject,customer_message,page_reference,status) values(p_project_id,v_access.preview_access_id,p_payload->>'feedback_type',p_payload->>'subject',p_payload->>'message',p_payload->>'page_reference','NEW') returning * into v_feedback;
  elsif p_command_type='classify_feedback' then
    perform set_config('lws.commercial_command','on',true);update public.customer_feedback set status=p_payload->>'status',revision=revision+1 where feedback_id=(p_payload->>'feedback_id')::uuid and project_id=p_project_id returning * into v_feedback;perform set_config('lws.commercial_command','',true);if not found then raise exception using errcode='23503',message='FEEDBACK_NOT_FOUND';end if;
  elsif p_command_type='create_revision' then
    select * into v_feedback from public.customer_feedback where feedback_id=(p_payload->>'feedback_id')::uuid and project_id=p_project_id and status='REVIEWED';if not found then raise exception using errcode='P0001',message='INCLUDED_CLASSIFICATION_REQUIRED';end if;
    insert into public.project_revisions(project_id,feedback_id,revision_number,classification,status,evidence_reference) values(p_project_id,v_feedback.feedback_id,coalesce((select max(revision_number)+1 from public.project_revisions where project_id=p_project_id),1),'INCLUDED_REVISION','OPEN',p_payload->>'evidence_reference') returning * into v_revision;
  elsif p_command_type='mark_revision_ready' then
    perform set_config('lws.commercial_command','on',true);update public.project_revisions set status='READY_FOR_PREVIEW',revision=revision+1 where revision_id=(p_payload->>'revision_id')::uuid and project_id=p_project_id and status in('OPEN','IN_PROGRESS') returning * into v_revision;perform set_config('lws.commercial_command','',true);if not found then raise exception using errcode='P0001',message='INVALID_REVISION_STATE';end if;
  elsif p_command_type='create_preview_version' then
    select * into v_revision from public.project_revisions where revision_id=(p_payload->>'revision_id')::uuid and project_id=p_project_id and status='READY_FOR_PREVIEW';if not found then raise exception using errcode='P0001',message='REVISION_NOT_READY';end if;
    perform set_config('lws.commercial_command','on',true);update public.preview_versions set status='SUPERSEDED' where project_id=p_project_id and status='CURRENT';update public.customer_approvals set status='SUPERSEDED' where project_id=p_project_id and status='CURRENT';perform set_config('lws.commercial_command','',true);
    insert into public.preview_versions(project_id,revision_id,version_number,content_reference,content_sha256,status) values(p_project_id,v_revision.revision_id,coalesce((select max(version_number)+1 from public.preview_versions where project_id=p_project_id),1),p_payload->>'content_reference',p_payload->>'content_sha256','CURRENT') returning * into v_version;
  elsif p_command_type='submit_customer_approval' then
    select * into v_access from public.preview_access where preview_access_id=(p_payload->>'preview_access_id')::uuid and project_id=p_project_id and status='ACTIVE' and expires_at>clock_timestamp();if not found then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
    select * into v_version from public.preview_versions where preview_version_id=(p_payload->>'preview_version_id')::uuid and project_id=p_project_id and status='CURRENT';if not found or v_access.preview_version_id<>v_version.preview_version_id then raise exception using errcode='P0001',message='PREVIEW_VERSION_MISMATCH';end if;
    insert into public.customer_approvals(project_id,preview_access_id,preview_version_id,statement_version,statement_sha256,status) values(p_project_id,v_access.preview_access_id,v_version.preview_version_id,p_payload->>'statement_version',p_payload->>'statement_sha256','CURRENT');
    if v_state='M2_PAYMENT_RECEIVED' then v_state:='FINAL_APPROVAL_RECORDED';v_changes_state:=true;end if;
  elsif p_command_type='require_change_order' then
    select * into v_feedback from public.customer_feedback where feedback_id=(p_payload->>'feedback_id')::uuid and project_id=p_project_id;if not found then raise exception using errcode='23503',message='FEEDBACK_NOT_FOUND';end if;
    insert into public.change_orders(project_id,original_quotation_issuance_id,feedback_id,change_request_reference,separate_amount_minor,status) values(p_project_id,v_project.quotation_issuance_id,v_feedback.feedback_id,p_payload->>'change_request_reference',null,'CHANGE_ORDER_REQUIRED');
  elsif p_command_type='authorize_final_transfer' then if v_state<>'FULL_PAYMENT_RECEIVED' then raise exception using errcode='P0001',message='PAYMENT_NOT_MATCHED';end if;v_state:='FINAL_TRANSFER_AUTHORIZED';v_changes_state:=true;
  elsif p_command_type='record_delivery' then if v_state<>'FINAL_TRANSFER_AUTHORIZED' then raise exception using errcode='P0001',message='TRANSFER_NOT_AUTHORIZED';end if;v_state:='DELIVERED';v_changes_state:=true;
  elsif p_command_type='archive_project' then if v_state<>'DELIVERED' then raise exception using errcode='P0001',message='INVALID_STATE';end if;v_state:='ARCHIVED';v_changes_state:=true;
  elsif p_command_type in('invoice_production','vat_production','peppol_production','credit_note_production','fiscal_numbering_activation') then raise exception using errcode='42501',message='FISCAL_PRODUCTION_BLOCKED';
  else raise exception using errcode='22023',message='UNKNOWN_COMMAND';end if;
  if v_changes_state then perform set_config('lws.commercial_command','on',true);update public.commercial_projects set current_state=v_state,revision=revision+1,updated_at=clock_timestamp() where project_id=p_project_id returning * into v_project;perform set_config('lws.commercial_command','',true);insert into public.workflow_events(project_id,previous_state,new_state,project_revision,command_id) values(p_project_id,p_expected_state,v_state,v_project.revision,p_idempotency_key);end if;
  insert into public.audit_events(project_id,event_type,actor,command_id,metadata) values(p_project_id,upper(p_command_type),p_audit_actor,p_idempotency_key,jsonb_build_object('state',v_state));
  v_result:=jsonb_build_object('project_id',p_project_id,'resulting_state',v_state,'revision',(select revision from public.commercial_projects where project_id=p_project_id),'command_type',p_command_type,'match_status',v_match,'entity_id',coalesce(v_evidence.payment_evidence_id,v_access.preview_access_id,v_feedback.feedback_id,v_revision.revision_id,v_version.preview_version_id));
  insert into public.idempotency_ledger(actor_id,project_id,command_type,idempotency_key,request_fingerprint,result_reference,result_payload) values(p_audit_actor,p_project_id,p_command_type,p_idempotency_key,v_fp,p_idempotency_key::text,v_result);
  return v_result;
end $$;


revoke all on function lws_internal.commercial_fingerprint_v1(jsonb),lws_internal.record_quotation_acceptance_core_v1(text,uuid,uuid,bigint,uuid),lws_internal.execute_commercial_command_core_v1(text,uuid,text,text,bigint,uuid,jsonb) from public,anon,authenticated,service_role;
-- END PHASE5OR3 SOURCE: 004_private_transaction_core.sql

-- BEGIN PHASE5OR3 SOURCE: 005_authorized_entrypoints.sql
create or replace function public.resolve_commercial_operator_authorization_v1(
  p_project_id uuid,
  p_command_type text,
  p_require_mutation boolean default true
) returns table(operator_id uuid,operator_role text,audit_actor text)
language plpgsql stable security definer
set search_path=public,auth,pg_catalog
as $$
declare
  v_subject uuid:=auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_access text;
  v_allowed boolean:=false;
begin
  if v_subject is null then raise exception using errcode='42501',message='HUMAN_JWT_REQUIRED';end if;
  select * into v_operator from public.commercial_operators where auth_user_id=v_subject;
  if not found then raise exception using errcode='42501',message='UNKNOWN_OPERATOR';end if;
  if v_operator.status='DISABLED' then raise exception using errcode='42501',message='OPERATOR_DISABLED';end if;
  if v_operator.status='REVOKED' then raise exception using errcode='42501',message='OPERATOR_REVOKED';end if;
  if v_operator.status<>'ACTIVE' then raise exception using errcode='42501',message='OPERATOR_INACTIVE';end if;
  if not exists(select 1 from public.commercial_projects where project_id=p_project_id) then raise exception using errcode='23503',message='PROJECT_NOT_FOUND';end if;

  if v_operator.role in('owner','admin') then
    v_access:=v_operator.role;
  else
    select grants.access_level into v_access from public.commercial_operator_project_grants as grants
      where grants.operator_id=v_operator.operator_id and grants.project_id=p_project_id and grants.revoked_at is null;
    if not found then raise exception using errcode='42501',message='PROJECT_SCOPE_DENIED';end if;
  end if;

  if not p_require_mutation then v_allowed:=true;
  elsif v_operator.role in('owner','admin') then
    v_allowed:=p_command_type=any(array[
      'prepare_milestone_1','record_payment_evidence','reconcile_payment','confirm_payment','release_project',
      'record_preview_ready','activate_preview_access','revoke_preview_access','classify_feedback','create_revision',
      'mark_revision_ready','create_preview_version','require_change_order','authorize_final_transfer','record_delivery','archive_project'
    ]);
  elsif v_operator.role='operator' and v_access='operator' then
    v_allowed:=p_command_type=any(array[
      'prepare_milestone_1','record_payment_evidence','reconcile_payment','record_preview_ready',
      'activate_preview_access','revoke_preview_access','create_revision','mark_revision_ready','create_preview_version'
    ]);
  elsif v_operator.role='reviewer' and v_access in('reviewer','operator') then
    v_allowed:=p_command_type='classify_feedback';
  else
    v_allowed:=false;
  end if;
  if not v_allowed then raise exception using errcode='42501',message='COMMAND_PERMISSION_DENIED';end if;
  return query select v_operator.operator_id,v_operator.role,'OPERATOR:'||v_operator.operator_id::text;
end $$;

create or replace function public.execute_commercial_command_v2(
  p_project_id uuid,p_command_type text,p_expected_state text,p_expected_revision bigint,p_idempotency_key uuid,p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql volatile security definer
set search_path=lws_internal,public,auth,extensions,pg_catalog
as $$
declare v_auth record;
begin
  select * into strict v_auth from public.resolve_commercial_operator_authorization_v1(p_project_id,p_command_type,true);
  return lws_internal.execute_commercial_command_core_v1(v_auth.audit_actor,p_project_id,p_command_type,p_expected_state,p_expected_revision,p_idempotency_key,p_payload);
end $$;

create or replace function public.get_commercial_project_view_v2(p_project_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public,auth,pg_catalog as $$
declare v_auth record;v_project public.commercial_projects%rowtype;
begin
  select * into strict v_auth from public.resolve_commercial_operator_authorization_v1(p_project_id,'READ_PROJECT',false);
  select * into strict v_project from public.commercial_projects where project_id=p_project_id;
  return jsonb_build_object('project_id',v_project.project_id,'current_state',v_project.current_state,'revision',v_project.revision,'accepted_total_minor',v_project.accepted_total_minor,'m1_minor',v_project.m1_minor,'m2_minor',v_project.m2_minor,'m3_minor',v_project.m3_minor);
end $$;

create or replace function public.initialize_commercial_project_from_acceptance_v1(
  p_project_id uuid,p_acceptance_id uuid,p_expected_total_minor bigint,p_idempotency_key uuid
) returns jsonb
language sql volatile security definer set search_path=lws_internal,public,pg_catalog as $$
  select lws_internal.record_quotation_acceptance_core_v1('SYSTEM:QUOTATION_ACCEPTANCE',p_project_id,p_acceptance_id,p_expected_total_minor,p_idempotency_key)
$$;

create or replace function public.execute_customer_commercial_command_v1(
  p_session_digest char(64),p_project_id uuid,p_command_type text,p_expected_state text,p_expected_revision bigint,p_idempotency_key uuid,p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql volatile security definer set search_path=lws_internal,public,pg_catalog as $$
declare v_session public.preview_sessions%rowtype;v_access public.preview_access%rowtype;v_safe_payload jsonb;
begin
  if p_command_type not in('submit_customer_feedback','submit_customer_approval') then raise exception using errcode='42501',message='CUSTOMER_COMMAND_DENIED';end if;
  select * into v_session from public.preview_sessions where session_digest=p_session_digest and project_id=p_project_id and revoked_at is null and expires_at>clock_timestamp();
  if not found then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
  select * into v_access from public.preview_access where preview_access_id=v_session.preview_access_id and project_id=p_project_id and status='ACTIVE' and expires_at>clock_timestamp();
  if not found then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
  v_safe_payload:=coalesce(p_payload,'{}'::jsonb)||jsonb_build_object('preview_access_id',v_access.preview_access_id);
  return lws_internal.execute_commercial_command_core_v1('CUSTOMER:'||v_access.preview_access_id::text,p_project_id,p_command_type,p_expected_state,p_expected_revision,p_idempotency_key,v_safe_payload);
end $$;

create or replace function public.resolve_customer_preview_v2(p_session_digest char(64),p_requested_project_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public,pg_catalog as $$
declare v_session public.preview_sessions%rowtype;v_access public.preview_access%rowtype;
begin
  select * into v_session from public.preview_sessions where session_digest=p_session_digest and project_id=p_requested_project_id and revoked_at is null and expires_at>clock_timestamp();
  if not found then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
  select * into v_access from public.preview_access where preview_access_id=v_session.preview_access_id and project_id=p_requested_project_id and status='ACTIVE' and expires_at>clock_timestamp();
  if not found then raise exception using errcode='42501',message='ACCESS_DENIED';end if;
  return jsonb_build_object('project_id',p_requested_project_id,'preview_access_id',v_access.preview_access_id,'preview_version_id',v_access.preview_version_id,'expires_at',v_access.expires_at);
end $$;

create or replace function public.set_commercial_operator_status_v1(p_operator_id uuid,p_status text) returns void
language plpgsql volatile security definer set search_path=public,auth,pg_catalog as $$
declare v_subject uuid:=auth.uid();v_caller public.commercial_operators%rowtype;
begin
  select * into v_caller from public.commercial_operators where auth_user_id=v_subject and status='ACTIVE';
  if not found or v_caller.role<>'owner' then raise exception using errcode='42501',message='OWNER_REQUIRED';end if;
  if p_status not in('ACTIVE','DISABLED','REVOKED') then raise exception using errcode='22023',message='INVALID_OPERATOR_STATUS';end if;
  perform set_config('lws.operator_admin','on',true);
  update public.commercial_operators set status=p_status,updated_at=clock_timestamp(),revoked_at=case when p_status='REVOKED' then clock_timestamp() else null end where operator_id=p_operator_id;
  perform set_config('lws.operator_admin','',true);
  if not found then raise exception using errcode='23503',message='OPERATOR_NOT_FOUND';end if;
end $$;

create or replace function public.guard_commercial_operator_mutation() returns trigger language plpgsql set search_path=public as $$
begin
  if tg_op='DELETE' then raise exception using errcode='55000',message='OPERATOR_AUTHORITY_IMMUTABLE';end if;
  if current_setting('lws.operator_admin',true)<>'on' then raise exception using errcode='55000',message='DIRECT_OPERATOR_MUTATION_DENIED';end if;
  if row(old.operator_id,old.auth_user_id,old.created_at) is distinct from row(new.operator_id,new.auth_user_id,new.created_at) then raise exception using errcode='55000',message='OPERATOR_IDENTITY_IMMUTABLE';end if;
  return new;
end $$;
drop trigger if exists trg_commercial_operator_guard on public.commercial_operators;
create trigger trg_commercial_operator_guard before update or delete on public.commercial_operators for each row execute function public.guard_commercial_operator_mutation();
-- END PHASE5OR3 SOURCE: 005_authorized_entrypoints.sql

-- BEGIN PHASE5OR3 SOURCE: 006_object_specific_privileges.sql
revoke all privileges on table
  public.commercial_customers,public.commercial_projects,public.commercial_obligations,public.commercial_documents,
  public.payment_expectations,public.payment_evidence,public.payment_reconciliations,public.workflow_events,public.audit_events,
  public.preview_access,public.preview_sessions,public.customer_feedback,public.feedback_internal_notes,public.project_revisions,
  public.preview_versions,public.customer_approvals,public.change_orders,public.recurring_services,public.external_costs,
  public.idempotency_ledger,public.commercial_operators,public.commercial_operator_project_grants
from public,anon,authenticated,service_role;

revoke all privileges on sequence public.workflow_events_workflow_event_id_seq,public.audit_events_audit_event_id_seq
from public,anon,authenticated,service_role;

revoke all on function
  public.resolve_commercial_operator_authorization_v1(uuid,text,boolean),
  public.execute_commercial_command_v2(uuid,text,text,bigint,uuid,jsonb),
  public.get_commercial_project_view_v2(uuid),
  public.initialize_commercial_project_from_acceptance_v1(uuid,uuid,bigint,uuid),
  public.execute_customer_commercial_command_v1(char,uuid,text,text,bigint,uuid,jsonb),
  public.resolve_customer_preview_v2(char,uuid),
  public.set_commercial_operator_status_v1(uuid,text),
  public.guard_commercial_operator_mutation()
from public,anon,authenticated,service_role;

grant execute on function
  public.execute_commercial_command_v2(uuid,text,text,bigint,uuid,jsonb),
  public.get_commercial_project_view_v2(uuid),
  public.set_commercial_operator_status_v1(uuid,text)
to authenticated;

grant execute on function
  public.initialize_commercial_project_from_acceptance_v1(uuid,uuid,bigint,uuid),
  public.execute_customer_commercial_command_v1(char,uuid,text,text,bigint,uuid,jsonb),
  public.resolve_customer_preview_v2(char,uuid)
to service_role;

comment on function public.execute_commercial_command_v2(uuid,text,text,bigint,uuid,jsonb) is
  'Human operator command. Identity derives from auth.uid(); caller-supplied actor text is absent.';
comment on function public.initialize_commercial_project_from_acceptance_v1(uuid,uuid,bigint,uuid) is
  'SYSTEM-only project initialization. Audit actor is fixed and cannot impersonate a human.';
-- END PHASE5OR3 SOURCE: 006_object_specific_privileges.sql

-- BEGIN PHASE5OR3 SOURCE: 007_indexes.sql
create index commercial_projects_customer_idx on public.commercial_projects(customer_id)
;

create index commercial_projects_state_idx on public.commercial_projects(current_state)
;

create index commercial_obligations_project_status_idx on public.commercial_obligations(project_id,status)
;

create index payment_reconciliations_timeline_idx on public.payment_reconciliations(project_id,decided_at desc)
;

create index audit_events_timeline_idx on public.audit_events(project_id,audit_event_id)
;

create index customer_feedback_queue_idx on public.customer_feedback(project_id,status,submitted_at desc)
;

create index project_revisions_sequence_idx on public.project_revisions(project_id,revision_number)
;

create index customer_approvals_version_idx on public.customer_approvals(preview_version_id,status);
;
-- END PHASE5OR3 SOURCE: 007_indexes.sql

-- BEGIN PHASE5OR3 SOURCE: 008_operator_rate_limit.sql
create table lws_internal.commercial_operator_rate_limits(
  auth_user_id uuid not null references auth.users(id),
  project_id uuid not null references public.commercial_projects(project_id),
  window_started_at timestamptz not null,
  request_count integer not null check(request_count>0),
  updated_at timestamptz not null,
  primary key(auth_user_id,project_id)
);
revoke all privileges on table lws_internal.commercial_operator_rate_limits from public,anon,authenticated,service_role;

create function public.consume_commercial_operator_rate_limit_v1(p_project_id uuid,p_max_requests integer default 60,p_window_seconds integer default 60)
returns table(allowed boolean,remaining integer,retry_after_seconds integer)
language plpgsql volatile security definer set search_path=lws_internal,public,auth,pg_catalog as $$
declare v_subject uuid:=auth.uid();v_now timestamptz:=clock_timestamp();v_row lws_internal.commercial_operator_rate_limits%rowtype;
begin
  if v_subject is null then raise exception using errcode='42501',message='HUMAN_JWT_REQUIRED';end if;
  if p_max_requests not between 1 and 300 or p_window_seconds not between 10 and 3600 then raise exception using errcode='22023',message='INVALID_RATE_LIMIT';end if;
  perform 1 from public.resolve_commercial_operator_authorization_v1(p_project_id,'READ_PROJECT',false);
  insert into lws_internal.commercial_operator_rate_limits(auth_user_id,project_id,window_started_at,request_count,updated_at)
  values(v_subject,p_project_id,v_now,1,v_now)
  on conflict(auth_user_id,project_id) do update set
    window_started_at=case when commercial_operator_rate_limits.window_started_at<=v_now-make_interval(secs=>p_window_seconds) then v_now else commercial_operator_rate_limits.window_started_at end,
    request_count=case when commercial_operator_rate_limits.window_started_at<=v_now-make_interval(secs=>p_window_seconds) then 1 else commercial_operator_rate_limits.request_count+1 end,
    updated_at=v_now returning * into v_row;
  allowed:=v_row.request_count<=p_max_requests;
  remaining:=greatest(p_max_requests-v_row.request_count,0);
  retry_after_seconds:=case when allowed then 0 else greatest(ceil(extract(epoch from (v_row.window_started_at+make_interval(secs=>p_window_seconds)-v_now)))::integer,1) end;
  return next;
end $$;
revoke all on function public.consume_commercial_operator_rate_limit_v1(uuid,integer,integer) from public,anon,authenticated,service_role;
grant execute on function public.consume_commercial_operator_rate_limit_v1(uuid,integer,integer) to authenticated;
-- END PHASE5OR3 SOURCE: 008_operator_rate_limit.sql

-- BEGIN PHASE5OR3 SOURCE: 009_owner_bootstrap_authority.sql
create table public.commercial_operator_authority_events(
  event_id bigint generated always as identity primary key,
  operator_id uuid not null references public.commercial_operators(operator_id),
  auth_user_id uuid not null references auth.users(id),
  event_type text not null check(event_type in('OWNER_BOOTSTRAPPED')),
  authority_reference text not null,
  occurred_at timestamptz not null default clock_timestamp()
);
alter table public.commercial_operator_authority_events enable row level security;
alter table public.commercial_operator_authority_events force row level security;
revoke all privileges on table public.commercial_operator_authority_events from public,anon,authenticated,service_role;
revoke all privileges on sequence public.commercial_operator_authority_events_event_id_seq from public,anon,authenticated,service_role;

create function public.bootstrap_first_commercial_owner_v1(p_auth_user_id uuid,p_display_name text,p_authority_reference text)
returns uuid language plpgsql volatile security definer set search_path=public,auth,pg_catalog as $$
declare v_operator public.commercial_operators%rowtype;
begin
  if current_user not in('postgres','supabase_admin') then raise exception using errcode='42501',message='DATABASE_OWNER_REQUIRED';end if;
  if nullif(btrim(p_display_name),'') is null or nullif(btrim(p_authority_reference),'') is null then raise exception using errcode='22023',message='INVALID_BOOTSTRAP_INPUT';end if;
  if not exists(select 1 from auth.users where id=p_auth_user_id) then raise exception using errcode='23503',message='AUTH_USER_NOT_FOUND';end if;
  select * into v_operator from public.commercial_operators where auth_user_id=p_auth_user_id;
  if found then
    if v_operator.role='owner' and v_operator.status='ACTIVE' then return v_operator.operator_id;end if;
    raise exception using errcode='P0001',message='BOOTSTRAP_IDENTITY_CONFLICT';
  end if;
  if exists(select 1 from public.commercial_operators where role='owner') then raise exception using errcode='P0001',message='OWNER_ALREADY_EXISTS';end if;
  insert into public.commercial_operators(auth_user_id,display_name,role,status) values(p_auth_user_id,p_display_name,'owner','ACTIVE') returning * into v_operator;
  insert into public.commercial_operator_authority_events(operator_id,auth_user_id,event_type,authority_reference) values(v_operator.operator_id,p_auth_user_id,'OWNER_BOOTSTRAPPED',p_authority_reference);
  return v_operator.operator_id;
end $$;
revoke all on function public.bootstrap_first_commercial_owner_v1(uuid,text,text) from public,anon,authenticated,service_role;
-- END PHASE5OR3 SOURCE: 009_owner_bootstrap_authority.sql
