alter type public.quote_request_email_kind add value if not exists 'quotation_delivery';
alter type public.quote_request_email_kind add value if not exists 'quotation_acceptance_customer';
alter type public.quote_request_email_kind add value if not exists 'quotation_acceptance_internal';

alter table public.quote_request_email_jobs
  alter column quote_request_id drop not null;

alter table public.quote_request_email_jobs
  add constraint quote_request_email_jobs_authority_binding check (
    (kind in ('quotation_delivery','quotation_acceptance_customer','quotation_acceptance_internal') and quote_request_id is null)
    or (kind not in ('quotation_delivery','quotation_acceptance_customer','quotation_acceptance_internal') and quote_request_id is not null)
  );

create table public.quote_request_quotation_email_orchestrations (
  id uuid primary key default gen_random_uuid(),
  email_job_id uuid not null unique references public.quote_request_email_jobs(id),
  email_type text not null check (email_type in ('QUOTATION_DELIVERY','ACCEPTANCE_CONFIRMATION_CUSTOMER','ACCEPTANCE_CONFIRMATION_INTERNAL')),
  issuance_id uuid not null references public.quote_request_quotation_issuances(id),
  acceptance_id uuid references public.quote_request_quotation_acceptances(id),
  capability_id uuid references public.quote_request_quotation_acceptance_capabilities(id),
  recipient_email text not null check (recipient_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  content_version text not null,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  idempotency_key uuid not null unique,
  created_at timestamptz not null default clock_timestamp(),
  created_by text not null,
  constraint quotation_email_authority_shape check (
    (email_type='QUOTATION_DELIVERY' and acceptance_id is null and capability_id is not null)
    or (email_type in ('ACCEPTANCE_CONFIRMATION_CUSTOMER','ACCEPTANCE_CONFIRMATION_INTERNAL') and acceptance_id is not null and capability_id is null)
  ),
    constraint quotation_email_acceptance_binding check (acceptance_id is null or email_type<>'QUOTATION_DELIVERY')
);

  create unique index quotation_delivery_email_once_per_version
    on public.quote_request_quotation_email_orchestrations(issuance_id,content_version)
    where email_type='QUOTATION_DELIVERY';

  create unique index quotation_acceptance_email_once_per_version
    on public.quote_request_quotation_email_orchestrations(email_type,acceptance_id,content_version)
    where email_type in ('ACCEPTANCE_CONFIRMATION_CUSTOMER','ACCEPTANCE_CONFIRMATION_INTERNAL');

create function public.prevent_quotation_email_orchestration_mutation()
returns trigger language plpgsql set search_path=public as $$begin raise exception using errcode='55000',message='QUOTATION_EMAIL_ORCHESTRATION_IMMUTABLE';end$$;
create trigger trg_quotation_email_orchestration_immutable before update or delete on public.quote_request_quotation_email_orchestrations for each row execute function public.prevent_quotation_email_orchestration_mutation();

create function public.prepare_issued_quotation_delivery_v1(p_issuance_id uuid,p_capability_id uuid,p_content_version text,p_idempotency_key uuid,p_admin_access_token_hash text,p_created_by text)
returns table(orchestration_id uuid,email_job_id uuid,recipient_email text,client_name text,quotation_number text,quotation_version integer,project_title text,valid_until date,job_status text,was_created boolean)
language plpgsql security definer set search_path=public as $$
declare v_i public.quote_request_quotation_issuances%rowtype;v_a public.quote_request_quotation_approvals%rowtype;v_intake public.quote_request_intakes%rowtype;v_c public.quote_request_quotation_acceptance_capabilities%rowtype;v_job public.quote_request_email_jobs%rowtype;v_o public.quote_request_quotation_email_orchestrations%rowtype;v_email text;v_fp text;
begin
 if p_content_version<>'QUOTATION_DELIVERY_NL_BE_v1' or p_admin_access_token_hash!~'^[0-9a-f]{64}$' or nullif(btrim(p_created_by),'') is null then raise exception using errcode='42501',message='UNAUTHORIZED';end if;
 select * into v_i from public.quote_request_quotation_issuances where id=p_issuance_id for update;if not found or v_i.status<>'ISSUED' then raise exception using errcode='P0001',message='DELIVERY_NOT_AVAILABLE';end if;
 if not public.is_quotation_within_validity_v1(v_i.id) or exists(select 1 from public.quote_request_quotation_acceptances where issuance_id=v_i.id) then raise exception using errcode='P0001',message='DELIVERY_NOT_AVAILABLE';end if;
 select * into strict v_a from public.quote_request_quotation_approvals where id=v_i.approval_id;select * into strict v_intake from public.quote_request_intakes where id=v_a.intake_id;
 if v_intake.admin_access_token_hash is distinct from p_admin_access_token_hash then raise exception using errcode='42501',message='UNAUTHORIZED';end if;
 select * into v_c from public.quote_request_quotation_acceptance_capabilities where id=p_capability_id and issuance_id=v_i.id and status='ACTIVE' and expires_at>clock_timestamp() for share;if not found then raise exception using errcode='P0001',message='CAPABILITY_NOT_AVAILABLE';end if;
 v_email:=v_a.approved_payload->'customer_identity'->>'email';if v_email!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception using errcode='P0001',message='RECIPIENT_INVALID';end if;
 v_fp:=encode(extensions.digest(convert_to(jsonb_build_object('issuanceId',v_i.id,'capabilityId',v_c.id,'recipient',lower(v_email),'contentVersion',p_content_version)::text,'UTF8'),'sha256'),'hex');
 select * into v_o from public.quote_request_quotation_email_orchestrations where idempotency_key=p_idempotency_key;if found then if v_o.request_fingerprint<>v_fp then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';end if;select * into strict v_job from public.quote_request_email_jobs where id=v_o.email_job_id;return query select v_o.id,v_job.id,v_o.recipient_email,v_a.approved_payload->'customer_identity'->>'legal_name',v_i.quotation_number,v_i.quotation_version,v_a.approved_payload->'project_scope'->>'project_title',(v_a.approved_payload->'validity'->>'valid_until')::date,v_job.status::text,false;return;end if;
 insert into public.quote_request_email_jobs(quote_request_id,kind) values(null,'quotation_delivery') returning * into v_job;
 insert into public.quote_request_quotation_email_orchestrations(email_job_id,email_type,issuance_id,capability_id,recipient_email,content_version,request_fingerprint,idempotency_key,created_by) values(v_job.id,'QUOTATION_DELIVERY',v_i.id,v_c.id,lower(v_email),p_content_version,v_fp,p_idempotency_key,p_created_by) returning * into v_o;
 return query select v_o.id,v_job.id,v_o.recipient_email,v_a.approved_payload->'customer_identity'->>'legal_name',v_i.quotation_number,v_i.quotation_version,v_a.approved_payload->'project_scope'->>'project_title',(v_a.approved_payload->'validity'->>'valid_until')::date,v_job.status::text,true;
end$$;

create function public.prepare_issued_quotation_delivery_with_capability_v1(p_issuance_id uuid,p_token_digest text,p_encrypted_token text,p_requested_expires_at timestamptz,p_capability_idempotency_key uuid,p_delivery_idempotency_key uuid,p_admin_access_token_hash text,p_created_by text)
returns table(orchestration_id uuid,email_job_id uuid,recipient_email text,client_name text,quotation_number text,quotation_version integer,project_title text,valid_until date,capability_id uuid,capability_expires_at timestamptz,stored_token_digest text,encrypted_token text,job_status text)
language plpgsql security definer set search_path=public as $$
declare v_c record;v_d record;v_o public.quote_request_quotation_email_orchestrations%rowtype;v_cap public.quote_request_quotation_acceptance_capabilities%rowtype;v_i public.quote_request_quotation_issuances%rowtype;v_a public.quote_request_quotation_approvals%rowtype;v_intake public.quote_request_intakes%rowtype;v_job public.quote_request_email_jobs%rowtype;v_op public.quote_request_quotation_acceptance_capability_operations%rowtype;
begin
 if p_encrypted_token!~'^v1\.[A-Za-z0-9_-]{16}\.[A-Za-z0-9_-]{40,}$' then raise exception using errcode='22023',message='INVALID_ENCRYPTED_TOKEN';end if;
 select * into v_o from public.quote_request_quotation_email_orchestrations where idempotency_key=p_delivery_idempotency_key;
 if found then
  if v_o.email_type<>'QUOTATION_DELIVERY' or v_o.issuance_id<>p_issuance_id then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';end if;
  select * into strict v_cap from public.quote_request_quotation_acceptance_capabilities where id=v_o.capability_id;
  select * into v_op from public.quote_request_quotation_acceptance_capability_operations where idempotency_key=p_capability_idempotency_key;
  if not found or v_op.operation_type<>'CREATE' or v_op.capability_id<>v_cap.id then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';end if;
  select * into strict v_i from public.quote_request_quotation_issuances where id=v_o.issuance_id;select * into strict v_a from public.quote_request_quotation_approvals where id=v_i.approval_id;select * into strict v_intake from public.quote_request_intakes where id=v_a.intake_id;select * into strict v_job from public.quote_request_email_jobs where id=v_o.email_job_id;
  if v_intake.admin_access_token_hash is distinct from p_admin_access_token_hash or v_intake.admin_access_token_expires_at<=clock_timestamp() or v_intake.admin_access_token_revoked_at is not null then raise exception using errcode='42501',message='UNAUTHORIZED';end if;
  if v_job.status<>'sent' and v_job.encrypted_payload is null then raise exception using errcode='P0001',message='DELIVERY_PAYLOAD_UNAVAILABLE';end if;
  return query select v_o.id,v_job.id,v_o.recipient_email,v_a.approved_payload->'customer_identity'->>'legal_name',v_i.quotation_number,v_i.quotation_version,v_a.approved_payload->'project_scope'->>'project_title',(v_a.approved_payload->'validity'->>'valid_until')::date,v_cap.id,v_cap.expires_at,v_cap.token_digest::text,v_job.encrypted_payload,v_job.status::text;return;
 end if;
 select * into v_c from public.create_quotation_acceptance_capability_v1(p_issuance_id,p_token_digest,p_requested_expires_at,p_capability_idempotency_key,p_admin_access_token_hash,p_created_by);
 select * into strict v_d from public.prepare_issued_quotation_delivery_v1(p_issuance_id,v_c.capability_id,'QUOTATION_DELIVERY_NL_BE_v1',p_delivery_idempotency_key,p_admin_access_token_hash,p_created_by);
 update public.quote_request_email_jobs set encrypted_payload=p_encrypted_token where id=v_d.email_job_id and status<>'sent' and encrypted_payload is null;
 return query select v_d.orchestration_id,v_d.email_job_id,v_d.recipient_email,v_d.client_name,v_d.quotation_number,v_d.quotation_version,v_d.project_title,v_d.valid_until,v_c.capability_id,v_c.expires_at,p_token_digest,(select encrypted_payload from public.quote_request_email_jobs where id=v_d.email_job_id),v_d.job_status;
end$$;

create or replace function public.clear_sent_intake_invitation_payload()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status='sent' and new.kind in ('intake_invitation','quotation_delivery') then new.encrypted_payload:=null;end if;
 return new;
end$$;

create function public.prepare_quotation_acceptance_confirmation_v1(p_acceptance_id uuid,p_email_type text,p_content_version text,p_idempotency_key uuid,p_created_by text,p_internal_recipient text default null)
returns table(orchestration_id uuid,email_job_id uuid,recipient_email text,client_name text,quotation_number text,quotation_version integer,project_title text,accepted_at timestamptz,accepting_name text,job_status text,was_created boolean)
language plpgsql security definer set search_path=public as $$
declare v_ac public.quote_request_quotation_acceptances%rowtype;v_i public.quote_request_quotation_issuances%rowtype;v_a public.quote_request_quotation_approvals%rowtype;v_intake public.quote_request_intakes%rowtype;v_c public.quote_request_quotation_acceptance_capabilities%rowtype;v_job public.quote_request_email_jobs%rowtype;v_o public.quote_request_quotation_email_orchestrations%rowtype;v_kind public.quote_request_email_kind;v_recipient text;v_fp text;
begin
 if p_email_type not in('ACCEPTANCE_CONFIRMATION_CUSTOMER','ACCEPTANCE_CONFIRMATION_INTERNAL') or nullif(btrim(p_created_by),'') is null then raise exception using errcode='42501',message='UNAUTHORIZED';end if;
 if (p_email_type='ACCEPTANCE_CONFIRMATION_CUSTOMER' and p_content_version<>'ACCEPTANCE_CONFIRMATION_CUSTOMER_NL_BE_v1') or (p_email_type='ACCEPTANCE_CONFIRMATION_INTERNAL' and p_content_version<>'ACCEPTANCE_CONFIRMATION_INTERNAL_NL_BE_v1') then raise exception using errcode='22023',message='CONTENT_VERSION_INVALID';end if;
 select * into v_ac from public.quote_request_quotation_acceptances where id=p_acceptance_id;if not found then raise exception using errcode='P0001',message='ACCEPTANCE_NOT_FOUND';end if;select * into strict v_i from public.quote_request_quotation_issuances where id=v_ac.issuance_id;select * into strict v_a from public.quote_request_quotation_approvals where id=v_i.approval_id;select * into strict v_intake from public.quote_request_intakes where id=v_a.intake_id;
 select * into v_c from public.quote_request_quotation_acceptance_capabilities where acceptance_id=v_ac.id and issuance_id=v_i.id and status='CONSUMED';if not found then raise exception using errcode='P0001',message='CAPABILITY_BINDING_INVALID';end if;
 if p_email_type='ACCEPTANCE_CONFIRMATION_CUSTOMER' then v_recipient:=v_a.approved_payload->'customer_identity'->>'email';v_kind:='quotation_acceptance_customer';else v_recipient:=p_internal_recipient;v_kind:='quotation_acceptance_internal';end if;if v_recipient!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception using errcode='P0001',message='RECIPIENT_INVALID';end if;
 v_fp:=encode(extensions.digest(convert_to(jsonb_build_object('acceptanceId',v_ac.id,'emailType',p_email_type,'recipient',lower(v_recipient),'contentVersion',p_content_version)::text,'UTF8'),'sha256'),'hex');select * into v_o from public.quote_request_quotation_email_orchestrations where idempotency_key=p_idempotency_key;if found then if v_o.request_fingerprint<>v_fp then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';end if;select * into strict v_job from public.quote_request_email_jobs where id=v_o.email_job_id;return query select v_o.id,v_job.id,v_o.recipient_email,v_a.approved_payload->'customer_identity'->>'legal_name',v_ac.quotation_number,v_ac.quotation_version,v_a.approved_payload->'project_scope'->>'project_title',v_ac.accepted_at,v_ac.accepting_name,v_job.status::text,false;return;end if;
 insert into public.quote_request_email_jobs(quote_request_id,kind) values(null,v_kind) returning * into v_job;insert into public.quote_request_quotation_email_orchestrations(email_job_id,email_type,issuance_id,acceptance_id,recipient_email,content_version,request_fingerprint,idempotency_key,created_by) values(v_job.id,p_email_type,v_i.id,v_ac.id,lower(v_recipient),p_content_version,v_fp,p_idempotency_key,p_created_by) returning * into v_o;return query select v_o.id,v_job.id,v_o.recipient_email,v_a.approved_payload->'customer_identity'->>'legal_name',v_ac.quotation_number,v_ac.quotation_version,v_a.approved_payload->'project_scope'->>'project_title',v_ac.accepted_at,v_ac.accepting_name,v_job.status::text,true;
end$$;

alter table public.quote_request_quotation_email_orchestrations enable row level security;revoke all privileges on table public.quote_request_quotation_email_orchestrations from public,anon,authenticated,service_role;revoke all on function public.prevent_quotation_email_orchestration_mutation() from public,anon,authenticated,service_role;revoke all on function public.prepare_issued_quotation_delivery_v1(uuid,uuid,text,uuid,text,text),public.prepare_issued_quotation_delivery_with_capability_v1(uuid,text,text,timestamptz,uuid,uuid,text,text),public.prepare_quotation_acceptance_confirmation_v1(uuid,text,text,uuid,text,text) from public,anon,authenticated;grant execute on function public.prepare_issued_quotation_delivery_v1(uuid,uuid,text,uuid,text,text),public.prepare_issued_quotation_delivery_with_capability_v1(uuid,text,text,timestamptz,uuid,uuid,text,text),public.prepare_quotation_acceptance_confirmation_v1(uuid,text,text,uuid,text,text) to service_role;
