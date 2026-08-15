create table public.quote_request_quotation_acceptance_capabilities (
  id uuid primary key default gen_random_uuid(),
  issuance_id uuid not null references public.quote_request_quotation_issuances(id),
  token_digest char(64) not null unique check (token_digest ~ '^[0-9a-f]{64}$'),
  capability_version smallint not null check (capability_version = 1),
  status text not null check (status in ('ACTIVE','CONSUMED','REVOKED')),
  expires_at timestamptz not null,
  acceptance_id uuid references public.quote_request_quotation_acceptances(id),
  consumed_request_fingerprint char(64) check (consumed_request_fingerprint is null or consumed_request_fingerprint ~ '^[0-9a-f]{64}$'),
  consumed_at timestamptz,
  revoked_at timestamptz,
  revoked_by text,
  revocation_reason text,
  created_at timestamptz not null default clock_timestamp(),
  created_by text not null check (nullif(btrim(created_by),'') is not null),
  constraint quotation_acceptance_capability_state_valid check (
    (status='ACTIVE' and acceptance_id is null and consumed_request_fingerprint is null and consumed_at is null and revoked_at is null and revoked_by is null and revocation_reason is null)
    or (status='CONSUMED' and acceptance_id is not null and consumed_request_fingerprint is not null and consumed_at is not null and revoked_at is null and revoked_by is null and revocation_reason is null)
    or (status='REVOKED' and acceptance_id is null and consumed_at is null and revoked_at is not null and nullif(btrim(revoked_by),'') is not null and nullif(btrim(revocation_reason),'') is not null)
  )
);
create unique index quotation_acceptance_one_active_capability
on public.quote_request_quotation_acceptance_capabilities(issuance_id)
where status='ACTIVE';

create table public.quote_request_quotation_acceptance_capability_operations (
  idempotency_key uuid primary key,
  operation_type text not null check (operation_type in ('CREATE','REVOKE')),
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  capability_id uuid not null references public.quote_request_quotation_acceptance_capabilities(id),
  created_at timestamptz not null default clock_timestamp()
);
create table public.quote_request_quotation_acceptance_capability_events (
  id bigint generated always as identity primary key,
  capability_id uuid not null references public.quote_request_quotation_acceptance_capabilities(id),
  issuance_id uuid not null references public.quote_request_quotation_issuances(id),
  event_type text not null check (event_type in ('CREATED','CONSUMED','REVOKED')),
  actor text not null,
  event_at timestamptz not null,
  evidence jsonb not null,
  constraint quotation_acceptance_capability_event_safe check (
    jsonb_typeof(evidence)='object' and not (evidence ?| array['token','token_digest','admin_access_token_hash','service_role_key'])
  )
);

create function public.guard_quotation_acceptance_capability_mutation()
returns trigger language plpgsql set search_path=public as $$
declare v_transition text:=current_setting('lws.acceptance_capability_transition',true);
begin
  if tg_op='DELETE' then raise exception using errcode='55000',message='ACCEPTANCE_CAPABILITY_IMMUTABLE';end if;
  if v_transition='CONSUME' and old.status='ACTIVE' and new.status='CONSUMED'
    and old.id=new.id and old.issuance_id=new.issuance_id and old.token_digest=new.token_digest
    and old.capability_version=new.capability_version and old.expires_at=new.expires_at
    and old.created_at=new.created_at and old.created_by=new.created_by then return new;end if;
  if v_transition='REVOKE' and old.status='ACTIVE' and new.status='REVOKED'
    and old.id=new.id and old.issuance_id=new.issuance_id and old.token_digest=new.token_digest
    and old.capability_version=new.capability_version and old.expires_at=new.expires_at
    and old.created_at=new.created_at and old.created_by=new.created_by then return new;end if;
  raise exception using errcode='55000',message='ACCEPTANCE_CAPABILITY_IMMUTABLE';
end$$;
create function public.prevent_quotation_acceptance_capability_history_mutation()
returns trigger language plpgsql set search_path=public as $$begin raise exception using errcode='55000',message='ACCEPTANCE_CAPABILITY_HISTORY_IMMUTABLE';end$$;
create trigger trg_acceptance_capability_guard before update or delete on public.quote_request_quotation_acceptance_capabilities for each row execute function public.guard_quotation_acceptance_capability_mutation();
create trigger trg_acceptance_capability_operations_immutable before update or delete on public.quote_request_quotation_acceptance_capability_operations for each row execute function public.prevent_quotation_acceptance_capability_history_mutation();
create trigger trg_acceptance_capability_events_immutable before update or delete on public.quote_request_quotation_acceptance_capability_events for each row execute function public.prevent_quotation_acceptance_capability_history_mutation();

create function public.create_quotation_acceptance_capability_v1(
  p_issuance_id uuid,p_token_digest text,p_requested_expires_at timestamptz,
  p_idempotency_key uuid,p_admin_access_token_hash text,p_created_by text
) returns table(capability_id uuid,expires_at timestamptz,was_created boolean)
language plpgsql security definer set search_path=public as $$
declare v_i public.quote_request_quotation_issuances%rowtype;v_a public.quote_request_quotation_approvals%rowtype;v_intake public.quote_request_intakes%rowtype;v_c public.quote_request_quotation_acceptance_capabilities%rowtype;v_op public.quote_request_quotation_acceptance_capability_operations%rowtype;v_deadline timestamptz;v_exp timestamptz;v_fp text;
begin
 if p_token_digest!~'^[0-9a-f]{64}$' or p_admin_access_token_hash!~'^[0-9a-f]{64}$' or nullif(btrim(p_created_by),'') is null then raise exception using errcode='42501',message='UNAUTHORIZED';end if;
 select * into v_i from public.quote_request_quotation_issuances where id=p_issuance_id for update;
 if not found or v_i.status<>'ISSUED' then raise exception using errcode='P0001',message='CAPABILITY_NOT_AVAILABLE';end if;
 if exists(select 1 from public.quote_request_quotation_acceptances where issuance_id=p_issuance_id) then raise exception using errcode='P0001',message='ALREADY_ACCEPTED';end if;
 select * into strict v_a from public.quote_request_quotation_approvals where id=v_i.approval_id;
 select * into strict v_intake from public.quote_request_intakes where id=v_a.intake_id for update;
 if v_intake.admin_access_token_hash is distinct from p_admin_access_token_hash or v_intake.admin_access_token_expires_at<=clock_timestamp() or v_intake.admin_access_token_revoked_at is not null then raise exception using errcode='42501',message='UNAUTHORIZED';end if;
 select acceptance_deadline_at into v_deadline from public.quotation_issuance_acceptance_deadline_v1(p_issuance_id);
 if clock_timestamp()>=v_deadline then raise exception using errcode='P0001',message='CAPABILITY_NOT_AVAILABLE';end if;
 v_exp:=least(coalesce(p_requested_expires_at,v_deadline),v_deadline);
 if v_exp<=clock_timestamp() then raise exception using errcode='22023',message='CAPABILITY_EXPIRY_INVALID';end if;
 v_fp:=encode(extensions.digest(convert_to(jsonb_build_object('issuanceId',p_issuance_id,'tokenDigest',p_token_digest,'expiresAt',v_exp)::text,'UTF8'),'sha256'),'hex');
 select * into v_op from public.quote_request_quotation_acceptance_capability_operations where idempotency_key=p_idempotency_key;
 if found then if v_op.operation_type<>'CREATE' or v_op.request_fingerprint<>v_fp then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';end if;select * into strict v_c from public.quote_request_quotation_acceptance_capabilities where id=v_op.capability_id;return query select v_c.id,v_c.expires_at,false;return;end if;
 if exists(select 1 from public.quote_request_quotation_acceptance_capabilities where issuance_id=p_issuance_id and status='ACTIVE') then raise exception using errcode='P0001',message='ACTIVE_CAPABILITY_EXISTS';end if;
 begin insert into public.quote_request_quotation_acceptance_capabilities(issuance_id,token_digest,capability_version,status,expires_at,created_by) values(p_issuance_id,p_token_digest,1,'ACTIVE',v_exp,p_created_by) returning * into v_c;exception when unique_violation then raise exception using errcode='P0001',message='CAPABILITY_CONFLICT';end;
 insert into public.quote_request_quotation_acceptance_capability_operations values(p_idempotency_key,'CREATE',v_fp,v_c.id,clock_timestamp());
 insert into public.quote_request_quotation_acceptance_capability_events(capability_id,issuance_id,event_type,actor,event_at,evidence) values(v_c.id,p_issuance_id,'CREATED',p_created_by,clock_timestamp(),jsonb_build_object('expiresAt',v_exp,'capabilityVersion',1));
 return query select v_c.id,v_c.expires_at,true;
end$$;

create function public.revoke_quotation_acceptance_capability_v1(p_capability_id uuid,p_reason text,p_actor text,p_idempotency_key uuid,p_admin_access_token_hash text)
returns table(capability_id uuid,status text,revoked_at timestamptz,was_revoked boolean)
language plpgsql security definer set search_path=public as $$
declare v_c public.quote_request_quotation_acceptance_capabilities%rowtype;v_i public.quote_request_quotation_issuances%rowtype;v_a public.quote_request_quotation_approvals%rowtype;v_intake public.quote_request_intakes%rowtype;v_op public.quote_request_quotation_acceptance_capability_operations%rowtype;v_fp text;
begin
 if nullif(btrim(p_reason),'') is null or nullif(btrim(p_actor),'') is null or p_admin_access_token_hash!~'^[0-9a-f]{64}$' then raise exception using errcode='42501',message='UNAUTHORIZED';end if;
 select * into v_c from public.quote_request_quotation_acceptance_capabilities where id=p_capability_id for update;if not found then raise exception using errcode='P0001',message='CAPABILITY_NOT_FOUND';end if;
 select * into strict v_i from public.quote_request_quotation_issuances where id=v_c.issuance_id;select * into strict v_a from public.quote_request_quotation_approvals where id=v_i.approval_id;select * into strict v_intake from public.quote_request_intakes where id=v_a.intake_id;
 if v_intake.admin_access_token_hash is distinct from p_admin_access_token_hash then raise exception using errcode='42501',message='UNAUTHORIZED';end if;
 v_fp:=encode(extensions.digest(convert_to(jsonb_build_object('capabilityId',p_capability_id,'reason',p_reason,'actor',p_actor)::text,'UTF8'),'sha256'),'hex');select * into v_op from public.quote_request_quotation_acceptance_capability_operations where idempotency_key=p_idempotency_key;if found then if v_op.operation_type<>'REVOKE' or v_op.request_fingerprint<>v_fp then raise exception using errcode='P0001',message='IDEMPOTENCY_CONFLICT';end if;return query select v_c.id,v_c.status,v_c.revoked_at,false;return;end if;
 if v_c.status='CONSUMED' then raise exception using errcode='P0001',message='CAPABILITY_ALREADY_CONSUMED';end if;if v_c.status='REVOKED' then raise exception using errcode='P0001',message='CAPABILITY_ALREADY_REVOKED';end if;
 perform set_config('lws.acceptance_capability_transition','REVOKE',true);update public.quote_request_quotation_acceptance_capabilities set status='REVOKED',revoked_at=clock_timestamp(),revoked_by=p_actor,revocation_reason=p_reason where id=v_c.id returning * into v_c;perform set_config('lws.acceptance_capability_transition','',true);
 insert into public.quote_request_quotation_acceptance_capability_operations values(p_idempotency_key,'REVOKE',v_fp,v_c.id,clock_timestamp());insert into public.quote_request_quotation_acceptance_capability_events(capability_id,issuance_id,event_type,actor,event_at,evidence) values(v_c.id,v_c.issuance_id,'REVOKED',p_actor,v_c.revoked_at,jsonb_build_object('reason',p_reason));return query select v_c.id,v_c.status,v_c.revoked_at,true;
end$$;

create function public.resolve_quotation_acceptance_capability_v1(p_token_digest text)
returns jsonb language plpgsql volatile security definer set search_path=public as $$
declare v_c public.quote_request_quotation_acceptance_capabilities%rowtype;v_i public.quote_request_quotation_issuances%rowtype;v_a public.quote_request_quotation_approvals%rowtype;v_t public.quotation_acceptance_terms_authorities%rowtype;v_state text;
begin
 if p_token_digest!~'^[0-9a-f]{64}$' then return jsonb_build_object('state','INVALID_OR_EXPIRED_LINK');end if;select * into v_c from public.quote_request_quotation_acceptance_capabilities where token_digest=p_token_digest;if not found then return jsonb_build_object('state','INVALID_OR_EXPIRED_LINK');end if;
 if v_c.status='CONSUMED' then return jsonb_build_object('state','ACCEPTED','quotation_number',(select quotation_number from public.quote_request_quotation_acceptances where id=v_c.acceptance_id));end if;
 if v_c.status<>'ACTIVE' or clock_timestamp()>=v_c.expires_at then return jsonb_build_object('state','INVALID_OR_EXPIRED_LINK');end if;
 select * into v_i from public.quote_request_quotation_issuances where id=v_c.issuance_id and status='ISSUED';if not found or not public.is_quotation_within_validity_v1(v_c.issuance_id) then return jsonb_build_object('state','ACCEPTANCE_NOT_AVAILABLE');end if;select * into strict v_a from public.quote_request_quotation_approvals where id=v_i.approval_id;select * into strict v_t from public.quotation_acceptance_terms_authorities where status='APPROVED';
 return jsonb_build_object('state','ACTIVE','quotation',jsonb_build_object('number',v_i.quotation_number,'version',v_i.quotation_version,'seller',jsonb_build_object('legal_name','Lorenzo Web Solutions'),'customer',jsonb_build_object('legal_name',v_a.approved_payload->'customer_identity'->>'legal_name','email',v_a.approved_payload->'customer_identity'->>'email'),'project',jsonb_build_object('title',v_a.approved_payload->'project_scope'->>'project_title','scope_summary',v_a.approved_payload->'project_scope'->>'scope_summary'),'lines',v_a.approved_payload->'line_items','totals',v_a.approved_payload->'totals','vat',(v_a.approved_payload->'vat_approval') - array['vat_approved_by','vat_approved_at'],'payment_schedule',(v_a.approved_payload->'payment_schedule') - array['approved_by','approved_at'],'validity',(v_a.approved_payload->'validity') - array['approved_by','approved_at']),'acceptance_terms',jsonb_build_object('terms_id',v_t.terms_id,'terms_version',v_t.terms_version,'content_reference',v_t.content_reference));
end$$;

create function public.submit_quotation_acceptance_capability_v1(p_token_digest text,p_expected_terms_id text,p_expected_terms_version text,p_accepting_name text,p_accepting_email text,p_accepting_organization text,p_accepting_role text,p_authority_declaration boolean,p_idempotency_key uuid)
returns jsonb language plpgsql volatile security definer set search_path=public as $$
declare v_c public.quote_request_quotation_acceptance_capabilities%rowtype;v_i public.quote_request_quotation_issuances%rowtype;v_a public.quote_request_quotation_approvals%rowtype;v_intake public.quote_request_intakes%rowtype;v_result record;v_fp text;
begin
 if p_token_digest!~'^[0-9a-f]{64}$' then return jsonb_build_object('state','INVALID_OR_EXPIRED_LINK');end if;v_fp:=encode(extensions.digest(convert_to(jsonb_build_object('termsId',p_expected_terms_id,'termsVersion',p_expected_terms_version,'name',btrim(p_accepting_name),'email',lower(btrim(p_accepting_email)),'organization',nullif(btrim(p_accepting_organization),''),'role',nullif(btrim(p_accepting_role),''),'declaration',p_authority_declaration)::text,'UTF8'),'sha256'),'hex');select * into v_c from public.quote_request_quotation_acceptance_capabilities where token_digest=p_token_digest for update;if not found then return jsonb_build_object('state','INVALID_OR_EXPIRED_LINK');end if;
 if v_c.status='CONSUMED' then if v_c.consumed_request_fingerprint<>v_fp then return jsonb_build_object('state','VALIDATION_FAILED');end if;return jsonb_build_object('state','ACCEPTED','acceptance_id',v_c.acceptance_id);end if;if v_c.status<>'ACTIVE' or clock_timestamp()>=v_c.expires_at then return jsonb_build_object('state','INVALID_OR_EXPIRED_LINK');end if;
 select * into strict v_i from public.quote_request_quotation_issuances where id=v_c.issuance_id for update;select * into strict v_a from public.quote_request_quotation_approvals where id=v_i.approval_id;select * into strict v_intake from public.quote_request_intakes where id=v_a.intake_id;
 select * into v_result from public.accept_quotation_v1(v_i.id,v_i.quotation_version,v_a.approved_payload->'customer_identity'->>'snapshot_sha256',p_expected_terms_id,p_expected_terms_version,p_accepting_name,p_accepting_email,p_accepting_organization,p_accepting_role,p_authority_declaration,p_idempotency_key,v_intake.admin_access_token_hash);
 perform set_config('lws.acceptance_capability_transition','CONSUME',true);update public.quote_request_quotation_acceptance_capabilities set status='CONSUMED',acceptance_id=v_result.acceptance_id,consumed_request_fingerprint=v_fp,consumed_at=clock_timestamp() where id=v_c.id returning * into v_c;perform set_config('lws.acceptance_capability_transition','',true);insert into public.quote_request_quotation_acceptance_capability_events(capability_id,issuance_id,event_type,actor,event_at,evidence) values(v_c.id,v_c.issuance_id,'CONSUMED','public-orchestration',v_c.consumed_at,jsonb_build_object('acceptanceId',v_result.acceptance_id));return jsonb_build_object('state','ACCEPTED','acceptance_id',v_result.acceptance_id,'quotation_number',v_result.quotation_number,'was_created',v_result.was_created);
exception when others then if sqlstate in ('22023','42501','P0001') then return jsonb_build_object('state','VALIDATION_FAILED');end if;raise;end$$;

create table lws_internal.acceptance_capability_rate_limits(token_digest char(64) primary key,window_started_at timestamptz not null,request_count integer not null,updated_at timestamptz not null);
revoke all on table lws_internal.acceptance_capability_rate_limits from public,anon,authenticated,service_role;
create function public.consume_acceptance_capability_rate_limit_v1(p_token_digest text,p_max_requests integer default 30)
returns boolean language plpgsql volatile security definer set search_path=lws_internal,pg_catalog as $$declare v_now timestamptz:=clock_timestamp();v_count integer;begin if p_token_digest!~'^[0-9a-f]{64}$' or p_max_requests not between 1 and 100 then return false;end if;insert into lws_internal.acceptance_capability_rate_limits values(p_token_digest,date_trunc('minute',v_now),1,v_now) on conflict(token_digest) do update set window_started_at=case when acceptance_capability_rate_limits.window_started_at<=v_now-interval '1 minute' then date_trunc('minute',v_now) else acceptance_capability_rate_limits.window_started_at end,request_count=case when acceptance_capability_rate_limits.window_started_at<=v_now-interval '1 minute' then 1 else acceptance_capability_rate_limits.request_count+1 end,updated_at=v_now returning request_count into v_count;return v_count<=p_max_requests;end$$;

alter table public.quote_request_quotation_acceptance_capabilities enable row level security;alter table public.quote_request_quotation_acceptance_capability_operations enable row level security;alter table public.quote_request_quotation_acceptance_capability_events enable row level security;
revoke all privileges on table public.quote_request_quotation_acceptance_capabilities,public.quote_request_quotation_acceptance_capability_operations,public.quote_request_quotation_acceptance_capability_events from public,anon,authenticated,service_role;
revoke all on function public.guard_quotation_acceptance_capability_mutation(),public.prevent_quotation_acceptance_capability_history_mutation() from public,anon,authenticated,service_role;
revoke all on function public.create_quotation_acceptance_capability_v1(uuid,text,timestamptz,uuid,text,text),public.revoke_quotation_acceptance_capability_v1(uuid,text,text,uuid,text),public.resolve_quotation_acceptance_capability_v1(text),public.submit_quotation_acceptance_capability_v1(text,text,text,text,text,text,text,boolean,uuid),public.consume_acceptance_capability_rate_limit_v1(text,integer) from public,anon,authenticated;
grant execute on function public.create_quotation_acceptance_capability_v1(uuid,text,timestamptz,uuid,text,text),public.revoke_quotation_acceptance_capability_v1(uuid,text,text,uuid,text),public.resolve_quotation_acceptance_capability_v1(text),public.submit_quotation_acceptance_capability_v1(text,text,text,text,text,text,text,boolean,uuid),public.consume_acceptance_capability_rate_limit_v1(text,integer) to service_role;

comment on function public.submit_quotation_acceptance_capability_v1(text,text,text,text,text,text,text,boolean,uuid) is
  'Service-role orchestration. Capability lock, D3E8 acceptance, CONSUMED transition and event append execute in one PostgreSQL transaction; any later failure rolls back the nested acceptance.';
comment on function public.resolve_quotation_acceptance_capability_v1(text) is
  'Read-only customer-safe projection. ACTIVE returns display data; CONSUMED returns minimal accepted state; unknown, expired and revoked tokens share INVALID_OR_EXPIRED_LINK.';
comment on function public.consume_acceptance_capability_rate_limit_v1(text,integer) is
  'Shared per-capability abuse bucket: every requester presenting the same bearer token consumes the same fixed-minute allowance. It is abuse control, not identity proof.';
