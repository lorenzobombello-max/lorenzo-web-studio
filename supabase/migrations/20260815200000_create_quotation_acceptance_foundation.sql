create table public.quotation_acceptance_terms_authorities (
  terms_id text not null,
  terms_version text not null,
  status text not null check (status in ('APPROVED', 'RETIRED')),
  content_reference text not null check (nullif(btrim(content_reference), '') is not null),
  content_sha256 char(64) not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  approved_at timestamptz not null,
  approved_by text not null check (nullif(btrim(approved_by), '') is not null),
  approval_reference text not null check (nullif(btrim(approval_reference), '') is not null),
  created_at timestamptz not null default clock_timestamp(),
  primary key (terms_id, terms_version)
);

create unique index quotation_acceptance_terms_one_approved
on public.quotation_acceptance_terms_authorities (terms_id)
where status = 'APPROVED';

insert into public.quotation_acceptance_terms_authorities (
  terms_id, terms_version, status, content_reference, content_sha256,
  approved_at, approved_by, approval_reference
) values (
  'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT', '1.0.0-technical', 'APPROVED',
  'Technical acknowledgement: accepts the exact issued quotation and confirms authority to accept for the identified customer.',
  encode(extensions.digest(convert_to(
    'Technical acknowledgement: accepts the exact issued quotation and confirms authority to accept for the identified customer.',
    'UTF8'
  ), 'sha256'), 'hex'),
  clock_timestamp(), 'checkpoint:D3E8', 'LWS_D3E8_TECHNICAL_TERMS_APPROVAL'
);

create table public.quote_request_quotation_acceptances (
  id uuid primary key default gen_random_uuid(),
  issuance_id uuid not null unique references public.quote_request_quotation_issuances(id),
  quotation_number text not null check (quotation_number ~ '^LWS-OFF-[0-9]{4}-[0-9]{4}$'),
  quotation_version integer not null check (quotation_version >= 1),
  customer_identity_sha256 char(64) not null check (customer_identity_sha256 ~ '^[0-9a-f]{64}$'),
  customer_id text,
  customer_legal_name text not null check (nullif(btrim(customer_legal_name), '') is not null),
  generation_payload_sha256 char(64) not null check (generation_payload_sha256 ~ '^[0-9a-f]{64}$'),
  template_id text not null,
  template_version text not null,
  template_sha256 char(64) not null check (template_sha256 ~ '^[0-9a-f]{64}$'),
  docx_sha256 char(64) not null check (docx_sha256 ~ '^[0-9a-f]{64}$'),
  docx_bytes bigint not null check (docx_bytes > 0),
  acceptance_contract_version smallint not null check (acceptance_contract_version = 1),
  acceptance_terms_id text not null,
  acceptance_terms_version text not null,
  acceptance_terms_sha256 char(64) not null check (acceptance_terms_sha256 ~ '^[0-9a-f]{64}$'),
  accepting_name text not null check (nullif(btrim(accepting_name), '') is not null),
  accepting_email text not null check (accepting_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  accepting_organization text,
  accepting_role text,
  authority_declaration boolean not null check (authority_declaration),
  acceptance_payload jsonb not null,
  acceptance_payload_sha256 char(64) not null check (acceptance_payload_sha256 ~ '^[0-9a-f]{64}$'),
  semantic_request_fingerprint char(64) not null check (semantic_request_fingerprint ~ '^[0-9a-f]{64}$'),
  accepted_at timestamptz not null,
  created_at timestamptz not null,
  constraint quotation_acceptance_terms_fk foreign key (acceptance_terms_id, acceptance_terms_version)
    references public.quotation_acceptance_terms_authorities(terms_id, terms_version),
  constraint quotation_acceptance_identity_unique unique (quotation_number, quotation_version),
  constraint quotation_acceptance_created_matches check (created_at = accepted_at)
);

create table public.quote_request_quotation_acceptance_operations (
  idempotency_key uuid primary key,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  acceptance_id uuid not null references public.quote_request_quotation_acceptances(id),
  created_at timestamptz not null default clock_timestamp()
);

create table public.quote_request_quotation_acceptance_events (
  id bigint generated always as identity primary key,
  acceptance_id uuid not null references public.quote_request_quotation_acceptances(id),
  issuance_id uuid not null references public.quote_request_quotation_issuances(id),
  event_type text not null check (event_type = 'ACCEPTED'),
  actor_reference jsonb not null,
  acceptance_terms_id text not null,
  acceptance_terms_version text not null,
  acceptance_payload_sha256 char(64) not null check (acceptance_payload_sha256 ~ '^[0-9a-f]{64}$'),
  event_at timestamptz not null,
  constraint quotation_acceptance_event_actor_minimized check (
    public.jsonb_has_exact_keys(actor_reference, array['name', 'email', 'organization', 'role'])
    and not (actor_reference ?| array['ip', 'user_agent', 'device_fingerprint', 'geolocation', 'capability_token'])
  )
);

create function public.canonicalize_quotation_acceptance_payload_v1(p_payload jsonb)
returns text
language plpgsql
immutable
set search_path = public
as $$
begin
  if not public.jsonb_has_exact_keys(p_payload, array[
    'acceptance_contract_version', 'issuance_id', 'quotation_number',
    'quotation_version', 'customer_identity_sha256', 'generation_payload_sha256',
    'template', 'docx', 'acceptance_terms', 'actor', 'authority_declaration',
    'accepted_at'
  ])
    or p_payload->'acceptance_contract_version' <> '1'::jsonb
    or (p_payload->>'issuance_id') !~ '^[0-9a-f-]{36}$'
    or p_payload->>'quotation_number' !~ '^LWS-OFF-[0-9]{4}-[0-9]{4}$'
    or not public.is_jsonb_nonnegative_integer(p_payload->'quotation_version')
    or not public.is_sha256_jsonb(p_payload->'customer_identity_sha256')
    or not public.is_sha256_jsonb(p_payload->'generation_payload_sha256')
    or not public.jsonb_has_exact_keys(p_payload->'template', array['template_id','template_version','template_sha256'])
    or not public.is_sha256_jsonb(p_payload->'template'->'template_sha256')
    or not public.jsonb_has_exact_keys(p_payload->'docx', array['sha256','bytes'])
    or not public.is_sha256_jsonb(p_payload->'docx'->'sha256')
    or not public.is_jsonb_nonnegative_integer(p_payload->'docx'->'bytes')
    or not public.jsonb_has_exact_keys(p_payload->'acceptance_terms', array['terms_id','terms_version','terms_sha256'])
    or not public.is_sha256_jsonb(p_payload->'acceptance_terms'->'terms_sha256')
    or not public.jsonb_has_exact_keys(p_payload->'actor', array['name','email','organization','role'])
    or nullif(btrim(p_payload->'actor'->>'name'), '') is null
    or p_payload->'actor'->>'email' !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    or p_payload->'authority_declaration' <> 'true'::jsonb
    or not public.is_iso_utc_timestamp(p_payload->'accepted_at') then
    raise exception using errcode = '22023', message = 'INVALID_QUOTATION_ACCEPTANCE_PAYLOAD_V1';
  end if;
  return p_payload::text;
end;
$$;

create function public.quotation_acceptance_payload_sha256_v1(p_payload jsonb)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select encode(extensions.digest(convert_to(
    public.canonicalize_quotation_acceptance_payload_v1(p_payload), 'UTF8'
  ), 'sha256'), 'hex')
$$;

alter table public.quote_request_quotation_acceptances
  add constraint quotation_acceptance_payload_hash_matches check (
    acceptance_payload_sha256 = public.quotation_acceptance_payload_sha256_v1(acceptance_payload)
  );

create function public.prevent_quotation_acceptance_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception using errcode = '55000', message = 'QUOTATION_ACCEPTANCE_IMMUTABLE';
end;
$$;

create trigger trg_quotation_acceptances_immutable
before update or delete on public.quote_request_quotation_acceptances
for each row execute function public.prevent_quotation_acceptance_mutation();
create trigger trg_quotation_acceptance_operations_immutable
before update or delete on public.quote_request_quotation_acceptance_operations
for each row execute function public.prevent_quotation_acceptance_mutation();
create trigger trg_quotation_acceptance_events_immutable
before update or delete on public.quote_request_quotation_acceptance_events
for each row execute function public.prevent_quotation_acceptance_mutation();
create trigger trg_quotation_acceptance_terms_immutable
before update or delete on public.quotation_acceptance_terms_authorities
for each row execute function public.prevent_quotation_acceptance_mutation();

create function public.accept_quotation_v1(
  p_issuance_id uuid,
  p_expected_quotation_version integer,
  p_expected_customer_identity_sha256 text,
  p_acceptance_terms_id text,
  p_acceptance_terms_version text,
  p_accepting_name text,
  p_accepting_email text,
  p_accepting_organization text,
  p_accepting_role text,
  p_authority_declaration boolean,
  p_idempotency_key uuid,
  p_admin_access_token_hash text
)
returns table (
  acceptance_id uuid,
  issuance_id uuid,
  quotation_number text,
  quotation_version integer,
  acceptance_payload_sha256 text,
  accepted_at timestamptz,
  was_created boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_issuance public.quote_request_quotation_issuances%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_terms public.quotation_acceptance_terms_authorities%rowtype;
  v_acceptance public.quote_request_quotation_acceptances%rowtype;
  v_operation public.quote_request_quotation_acceptance_operations%rowtype;
  v_customer jsonb;
  v_customer_hash text;
  v_request_fingerprint text;
  v_payload jsonb;
  v_accepted_at timestamptz;
begin
  if p_admin_access_token_hash is null or p_admin_access_token_hash !~ '^[0-9a-f]{64}$'
     or p_expected_quotation_version is null or p_expected_quotation_version < 1
     or p_expected_customer_identity_sha256 is null or p_expected_customer_identity_sha256 !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_accepting_name), '') is null
     or p_accepting_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     or p_authority_declaration is not true then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;

  select * into v_issuance from public.quote_request_quotation_issuances
  where id = p_issuance_id for update;
  if not found then raise exception using errcode = 'P0001', message = 'ISSUANCE_NOT_FOUND'; end if;
  if v_issuance.status <> 'ISSUED' then raise exception using errcode = 'P0001', message = 'ISSUANCE_NOT_ELIGIBLE'; end if;
  if v_issuance.quotation_version <> p_expected_quotation_version then
    raise exception using errcode = 'P0001', message = 'QUOTATION_VERSION_MISMATCH';
  end if;
  if v_issuance.generation_payload_sha256 is null or v_issuance.template_id is null
     or v_issuance.template_version is null or v_issuance.template_sha256 is null
     or v_issuance.docx_sha256 is null or v_issuance.docx_bytes is null then
    raise exception using errcode = 'P0001', message = 'ISSUANCE_ARTIFACT_EVIDENCE_INVALID';
  end if;
  select * into strict v_approval from public.quote_request_quotation_approvals
  where id = v_issuance.approval_id;
  select * into strict v_intake from public.quote_request_intakes
  where id = v_approval.intake_id for update;
  if v_intake.admin_access_token_hash is distinct from p_admin_access_token_hash
     or v_intake.admin_access_token_expires_at <= clock_timestamp()
     or v_intake.admin_access_token_revoked_at is not null then
    raise exception using errcode = '42501', message = 'UNAUTHORIZED';
  end if;

  v_customer := v_approval.approved_payload->'customer_identity';
  v_customer_hash := v_customer->>'snapshot_sha256';
  if v_customer_hash is distinct from p_expected_customer_identity_sha256 then
    raise exception using errcode = 'P0001', message = 'CUSTOMER_IDENTITY_MISMATCH';
  end if;

  select * into v_terms from public.quotation_acceptance_terms_authorities
  where terms_id = p_acceptance_terms_id and terms_version = p_acceptance_terms_version
    and status = 'APPROVED' for share;
  if not found then raise exception using errcode = 'P0001', message = 'ACCEPTANCE_TERMS_NOT_APPROVED'; end if;

  v_request_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'issuanceId', p_issuance_id, 'quotationVersion', p_expected_quotation_version,
    'customerIdentitySha256', p_expected_customer_identity_sha256,
    'termsId', p_acceptance_terms_id, 'termsVersion', p_acceptance_terms_version,
    'acceptingName', btrim(p_accepting_name), 'acceptingEmail', lower(btrim(p_accepting_email)),
    'acceptingOrganization', nullif(btrim(p_accepting_organization), ''),
    'acceptingRole', nullif(btrim(p_accepting_role), ''),
    'authorityDeclaration', p_authority_declaration
  )::text, 'UTF8'), 'sha256'), 'hex');

  select * into v_operation from public.quote_request_quotation_acceptance_operations
  where idempotency_key = p_idempotency_key;
  if found then
    if v_operation.request_fingerprint <> v_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    select * into strict v_acceptance from public.quote_request_quotation_acceptances
    where id = v_operation.acceptance_id;
    return query select v_acceptance.id, v_acceptance.issuance_id,
      v_acceptance.quotation_number, v_acceptance.quotation_version,
      rtrim(v_acceptance.acceptance_payload_sha256), v_acceptance.accepted_at, false;
    return;
  end if;

  select * into v_acceptance
  from public.quote_request_quotation_acceptances as acceptance
  where acceptance.issuance_id = p_issuance_id;
  if found then
    if v_acceptance.semantic_request_fingerprint <> v_request_fingerprint then
      raise exception using errcode = 'P0001', message = 'ACCEPTANCE_CONFLICT';
    end if;
    insert into public.quote_request_quotation_acceptance_operations (
      idempotency_key, request_fingerprint, acceptance_id
    ) values (p_idempotency_key, v_request_fingerprint, v_acceptance.id);
    return query select v_acceptance.id, v_acceptance.issuance_id,
      v_acceptance.quotation_number, v_acceptance.quotation_version,
      rtrim(v_acceptance.acceptance_payload_sha256), v_acceptance.accepted_at, false;
    return;
  end if;

  v_accepted_at := clock_timestamp();
  if v_accepted_at >= (
    select deadline.acceptance_deadline_at
    from public.quotation_issuance_acceptance_deadline_v1(p_issuance_id) as deadline
  ) then
    raise exception using errcode = 'P0001', message = 'QUOTATION_EXPIRED';
  end if;
  v_payload := jsonb_build_object(
    'acceptance_contract_version', 1,
    'issuance_id', v_issuance.id,
    'quotation_number', v_issuance.quotation_number,
    'quotation_version', v_issuance.quotation_version,
    'customer_identity_sha256', v_customer_hash,
    'generation_payload_sha256', rtrim(v_issuance.generation_payload_sha256),
    'template', jsonb_build_object('template_id', v_issuance.template_id,
      'template_version', v_issuance.template_version,
      'template_sha256', rtrim(v_issuance.template_sha256)),
    'docx', jsonb_build_object('sha256', rtrim(v_issuance.docx_sha256), 'bytes', v_issuance.docx_bytes),
    'acceptance_terms', jsonb_build_object('terms_id', v_terms.terms_id,
      'terms_version', v_terms.terms_version, 'terms_sha256', rtrim(v_terms.content_sha256)),
    'actor', jsonb_build_object('name', btrim(p_accepting_name),
      'email', lower(btrim(p_accepting_email)),
      'organization', nullif(btrim(p_accepting_organization), ''),
      'role', nullif(btrim(p_accepting_role), '')),
    'authority_declaration', true,
    'accepted_at', to_char(v_accepted_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  );

  insert into public.quote_request_quotation_acceptances (
    issuance_id, quotation_number, quotation_version, customer_identity_sha256,
    customer_id, customer_legal_name, generation_payload_sha256,
    template_id, template_version, template_sha256, docx_sha256, docx_bytes,
    acceptance_contract_version, acceptance_terms_id, acceptance_terms_version,
    acceptance_terms_sha256, accepting_name, accepting_email,
    accepting_organization, accepting_role, authority_declaration,
    acceptance_payload, acceptance_payload_sha256, semantic_request_fingerprint,
    accepted_at, created_at
  ) values (
    v_issuance.id, v_issuance.quotation_number, v_issuance.quotation_version,
    v_customer_hash, v_customer->>'customer_id', v_customer->>'legal_name',
    rtrim(v_issuance.generation_payload_sha256), v_issuance.template_id,
    v_issuance.template_version, rtrim(v_issuance.template_sha256),
    rtrim(v_issuance.docx_sha256), v_issuance.docx_bytes, 1,
    v_terms.terms_id, v_terms.terms_version, rtrim(v_terms.content_sha256),
    btrim(p_accepting_name), lower(btrim(p_accepting_email)),
    nullif(btrim(p_accepting_organization), ''), nullif(btrim(p_accepting_role), ''),
    true, v_payload, public.quotation_acceptance_payload_sha256_v1(v_payload),
    v_request_fingerprint, v_accepted_at, v_accepted_at
  ) returning * into v_acceptance;

  insert into public.quote_request_quotation_acceptance_operations (
    idempotency_key, request_fingerprint, acceptance_id
  ) values (p_idempotency_key, v_request_fingerprint, v_acceptance.id);
  insert into public.quote_request_quotation_acceptance_events (
    acceptance_id, issuance_id, event_type, actor_reference,
    acceptance_terms_id, acceptance_terms_version,
    acceptance_payload_sha256, event_at
  ) values (
    v_acceptance.id, v_issuance.id, 'ACCEPTED', v_payload->'actor',
    v_terms.terms_id, v_terms.terms_version,
    v_acceptance.acceptance_payload_sha256, v_accepted_at
  );

  return query select v_acceptance.id, v_acceptance.issuance_id,
    v_acceptance.quotation_number, v_acceptance.quotation_version,
    rtrim(v_acceptance.acceptance_payload_sha256), v_acceptance.accepted_at, true;
end;
$$;

alter table public.quotation_acceptance_terms_authorities enable row level security;
alter table public.quote_request_quotation_acceptances enable row level security;
alter table public.quote_request_quotation_acceptance_operations enable row level security;
alter table public.quote_request_quotation_acceptance_events enable row level security;

revoke all privileges on table public.quotation_acceptance_terms_authorities from public,anon,authenticated,service_role;
revoke all privileges on table public.quote_request_quotation_acceptances from public,anon,authenticated,service_role;
revoke all privileges on table public.quote_request_quotation_acceptance_operations from public,anon,authenticated,service_role;
revoke all privileges on table public.quote_request_quotation_acceptance_events from public,anon,authenticated,service_role;
revoke all on function public.canonicalize_quotation_acceptance_payload_v1(jsonb) from public,anon,authenticated;
revoke all on function public.quotation_acceptance_payload_sha256_v1(jsonb) from public,anon,authenticated;
revoke all on function public.prevent_quotation_acceptance_mutation() from public,anon,authenticated,service_role;
revoke all on function public.accept_quotation_v1(uuid,integer,text,text,text,text,text,text,text,boolean,uuid,text) from public,anon,authenticated;
grant execute on function public.accept_quotation_v1(uuid,integer,text,text,text,text,text,text,text,boolean,uuid,text) to service_role;

comment on table public.quote_request_quotation_acceptances is
  'Immutable customer acceptance authority. IS_ACCEPTED means exactly one valid immutable row exists for the exact issuance/version; issuance remains ISSUED.';
comment on function public.accept_quotation_v1(uuid,integer,text,text,text,text,text,text,text,boolean,uuid,text) is
  'Trusted backend-only customer acceptance. Uses D3E8A server-time eligibility and immutable issued/customer/artifact evidence. No public token, client timestamp, invoice, email, payment, or project side effect.';
