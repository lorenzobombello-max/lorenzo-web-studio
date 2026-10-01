create table public.website_quotation_payment_term_release_authorities (
  authority_id uuid primary key default gen_random_uuid(),
  authority_version text not null unique,
  payment_term_days integer not null check (payment_term_days = 14),
  external_confirmation_reference text not null
    check (nullif(btrim(external_confirmation_reference), '') is not null),
  external_confirmation_sha256 char(64) not null
    check (external_confirmation_sha256 ~ '^[0-9a-f]{64}$'),
  status text not null check (status in ('APPROVED', 'RETIRED')),
  approved_by text not null check (nullif(btrim(approved_by), '') is not null),
  approved_at timestamptz not null,
  retired_by text,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default clock_timestamp(),
  constraint website_quotation_payment_term_approved_at_valid check (
    approved_at <= created_at
  ),
  constraint website_quotation_payment_term_release_authority_state_valid check (
    (status = 'APPROVED'
      and retired_by is null and retired_at is null and retirement_reason is null)
    or (status = 'RETIRED'
      and nullif(btrim(retired_by), '') is not null
      and retired_at is not null
      and retired_at >= approved_at
      and nullif(btrim(retirement_reason), '') is not null)
  )
);

create unique index website_quotation_payment_term_one_approved_release
on public.website_quotation_payment_term_release_authorities (payment_term_days)
where status = 'APPROVED';

create function public.validate_website_quotation_payment_term_release_insert_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  new.created_at := clock_timestamp();
  if new.approved_at > new.created_at then
    raise exception using
      errcode = '23514',
      message = 'WEBSITE_QUOTATION_PAYMENT_TERM_RELEASE_FUTURE_DATED';
  end if;
  return new;
end;
$$;

create trigger trg_website_quotation_payment_term_release_insert_valid
before insert on public.website_quotation_payment_term_release_authorities
for each row execute function public.validate_website_quotation_payment_term_release_insert_v1();

create function public.prevent_website_quotation_payment_term_release_mutation_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  if tg_op = 'UPDATE'
     and current_setting(
       'lws.website_quotation_payment_term_release_transition',
       true
     ) = 'RETIRE'
     and old.status = 'APPROVED'
     and new.status = 'RETIRED'
     and new.authority_id is not distinct from old.authority_id
     and new.authority_version is not distinct from old.authority_version
     and new.payment_term_days is not distinct from old.payment_term_days
     and new.external_confirmation_reference is not distinct from old.external_confirmation_reference
     and new.external_confirmation_sha256 is not distinct from old.external_confirmation_sha256
     and new.approved_by is not distinct from old.approved_by
     and new.approved_at is not distinct from old.approved_at
     and new.created_at is not distinct from old.created_at
     and nullif(btrim(new.retired_by), '') is not null
     and new.retired_at is not null
     and new.retired_at >= old.approved_at
     and nullif(btrim(new.retirement_reason), '') is not null then
    return new;
  end if;
  raise exception using
    errcode = '55000',
    message = 'WEBSITE_QUOTATION_PAYMENT_TERM_RELEASE_IMMUTABLE';
end;
$$;

create trigger trg_website_quotation_payment_term_release_immutable
before update or delete on public.website_quotation_payment_term_release_authorities
for each row execute function public.prevent_website_quotation_payment_term_release_mutation_v1();

create function public.require_website_quotation_payment_term_release_v1(
  p_request_kind text,
  p_milestones jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_payment_term_days integer;
  v_release public.website_quotation_payment_term_release_authorities%rowtype;
begin
  if p_request_kind is distinct from 'website' then
    return null;
  end if;
    if p_milestones is null
      or jsonb_typeof(p_milestones) <> 'array'
      or jsonb_array_length(p_milestones) = 0
     or exists (
       select 1
       from jsonb_array_elements(p_milestones) as milestone
       where not (milestone ? 'due_terms_days')
          or milestone->'due_terms_days' = 'null'::jsonb
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_QUOTATION_PAYMENT_TERM_MISSING';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_milestones) as milestone
    where not public.is_jsonb_nonnegative_integer(milestone->'due_terms_days')
       or (milestone->>'due_terms_days')::integer < 1
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_QUOTATION_PAYMENT_TERM_DEVIATES_FROM_SELECTION';
  end if;
  if (
    select count(distinct (milestone->>'due_terms_days')::integer)
    from jsonb_array_elements(p_milestones) as milestone
  ) <> 1 then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_QUOTATION_PAYMENT_TERM_AMBIGUOUS';
  end if;

  select (milestone->>'due_terms_days')::integer
  into strict v_payment_term_days
  from jsonb_array_elements(p_milestones) as milestone
  limit 1;
  if v_payment_term_days <> 14 then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_QUOTATION_PAYMENT_TERM_DEVIATES_FROM_SELECTION';
  end if;

  select * into v_release
  from public.website_quotation_payment_term_release_authorities
  where payment_term_days = v_payment_term_days
    and status = 'APPROVED'
    and approved_at <= clock_timestamp();
  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_QUOTATION_PAYMENT_TERM_RELEASE_REQUIRED';
  end if;

  return jsonb_build_object(
    'authority_id', v_release.authority_id,
    'authority_version', v_release.authority_version,
    'payment_term_days', v_release.payment_term_days,
    'external_confirmation_reference', v_release.external_confirmation_reference,
    'external_confirmation_sha256', rtrim(v_release.external_confirmation_sha256),
    'approved_by', v_release.approved_by,
    'approved_at', v_release.approved_at
  );
end;
$$;

create or replace function public.resolve_first_customer_quotation_orchestration_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_request public.quote_requests%rowtype;
  v_business public.quote_request_quotation_business_drafts%rowtype;
  v_promotion public.quote_request_quotation_business_approval_promotions%rowtype;
  v_approval public.quote_request_quotation_approvals%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_seller public.quotation_seller_authorities%rowtype;
  v_template public.quotation_template_authorities%rowtype;
  v_payment_term_release jsonb;
  v_issuance_authority jsonb;
  v_issuance_input_sha256 text;
begin
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = p_actor_auth_user_id;
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'QUOTATION_ORCHESTRATION_SCOPE_DENIED';
  end if;

  select business.* into v_business
  from public.quote_request_quotation_business_drafts as business
  join public.quote_request_quotation_business_approval_promotions as promotion
    on promotion.business_draft_id = business.business_draft_id
  where business.quote_request_id = p_quote_request_id
  order by business.business_revision desc
  limit 1;
  if not found then
    raise exception using errcode = 'P0001', message = 'APPROVAL_NOT_FOUND';
  end if;

  select * into strict v_promotion
  from public.quote_request_quotation_business_approval_promotions
  where business_draft_id = v_business.business_draft_id;
  select * into strict v_approval
  from public.quote_request_quotation_approvals
  where id = v_promotion.approval_id;
  select * into strict v_request
  from public.quote_requests
  where id = v_business.quote_request_id;
  select * into strict v_intake
  from public.quote_request_intakes
  where id = v_business.intake_id;
  select * into strict v_seller
  from public.quotation_seller_authorities
  where seller_authority_id = v_business.seller_authority_id;
  select * into strict v_template
  from public.quotation_template_authorities
  where id = v_business.template_authority_id;

  if v_approval.quote_request_id is distinct from v_business.quote_request_id
     or v_approval.intake_id is distinct from v_business.intake_id
     or v_approval.pricing_snapshot_id is distinct from v_business.pricing_snapshot_id
     or v_approval.draft_id is distinct from v_business.approval_draft_id
     or v_approval.approved_payload is distinct from v_business.canonical_payload
     or rtrim(v_approval.payload_sha256) is distinct from rtrim(v_business.canonical_payload_sha256)
     or v_request.id is distinct from p_quote_request_id
     or v_intake.quote_request_id is distinct from p_quote_request_id then
    raise exception using errcode = 'P0001', message = 'APPROVAL_INTEGRITY_INVALID';
  end if;
  if not public.is_valid_quotation_approval_for_issuance_v1(v_approval.id) then
    raise exception using errcode = 'P0001', message = 'APPROVAL_INTEGRITY_INVALID';
  end if;
  if v_intake.status not in ('submitted', 'reviewed')
     or v_intake.admin_access_token_hash is null
     or v_intake.admin_access_token_hash !~ '^[0-9a-f]{64}$'
     or v_intake.admin_access_token_expires_at <= clock_timestamp()
     or v_intake.admin_access_token_revoked_at is not null then
    raise exception using errcode = '42501', message = 'QUOTATION_ADMIN_CAPABILITY_UNAVAILABLE';
  end if;
  if v_template.status <> 'APPROVED' then
    raise exception using errcode = 'P0001', message = 'QUOTATION_TEMPLATE_NOT_APPROVED';
  end if;
  if not public.is_valid_quotation_generation_seller_v1(v_seller.seller_identity) then
    raise exception using errcode = 'P0001', message = 'SELLER_IDENTITY_INVALID';
  end if;

  v_payment_term_release := public.require_website_quotation_payment_term_release_v1(
    v_request.request_kind,
    v_approval.approved_payload->'payment_schedule'->'milestones'
  );
  v_issuance_authority := jsonb_build_object(
    'approvalId', v_approval.id,
    'approvalPayloadSha256', rtrim(v_approval.payload_sha256),
    'generationContractVersion', v_template.generation_contract_version,
    'sellerAuthorityId', v_seller.seller_authority_id,
    'sellerIdentitySha256', rtrim(v_seller.seller_identity_sha256),
    'templateAuthorityId', v_template.id,
    'templateSha256', lower(rtrim(v_template.template_sha256))
  );
  if v_payment_term_release is not null then
    v_issuance_authority := v_issuance_authority || jsonb_build_object(
      'websitePaymentTermReleaseAuthority', v_payment_term_release
    );
  end if;
  v_issuance_input_sha256 := encode(extensions.digest(
    convert_to(v_issuance_authority::text, 'UTF8'),
    'sha256'
  ), 'hex');

  return jsonb_build_object(
    'approval_id', v_approval.id,
    'admin_access_token_hash', v_intake.admin_access_token_hash,
    'issue_year', extract(year from clock_timestamp() at time zone 'Europe/Brussels')::integer,
    'issuance_input_sha256', v_issuance_input_sha256,
    'template', jsonb_build_object(
      'template_id', v_template.template_id,
      'template_version', v_template.template_version,
      'template_sha256', lower(rtrim(v_template.template_sha256)),
      'authority_status', v_template.status,
      'technical_master_filename', v_template.technical_master_filename,
      'renderer_version', v_template.renderer_version
    ),
    'seller', v_seller.seller_identity
  ) || case
    when v_payment_term_release is null then '{}'::jsonb
    else jsonb_build_object(
      'website_payment_term_release_authority', v_payment_term_release
    )
  end;
end;
$$;

create or replace function public.prepare_quotation_issuance_v2(
  p_approval_id uuid,
  p_issue_year smallint,
  p_generation_contract_version smallint,
  p_issuance_input_sha256 text,
  p_idempotency_key uuid,
  p_admin_access_token_hash text,
  p_prepared_by text
)
returns table (
  issuance_id uuid, quotation_number text, quotation_version integer,
  status text, generation_contract_version smallint,
  issuance_input_sha256 text, generation_payload_sha256 text,
  was_created boolean
)
language plpgsql
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_quote_request_id uuid;
  v_request_kind text;
  v_milestones jsonb;
  v_business public.quote_request_quotation_business_drafts%rowtype;
  v_seller public.quotation_seller_authorities%rowtype;
  v_template public.quotation_template_authorities%rowtype;
  v_payment_term_release jsonb;
  v_issuance_authority jsonb;
  v_expected_issuance_input_sha256 text;
begin
  select quote_request_id, approved_payload->'payment_schedule'->'milestones'
  into v_quote_request_id, v_milestones
  from public.quote_request_quotation_approvals
  where id = p_approval_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'APPROVAL_NOT_FOUND';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('DOSSIER:' || v_quote_request_id::text, 0)
  );
  if exists (
    select 1 from lws_internal.dossier_purge_tombstones
    where quote_request_id = v_quote_request_id
  ) or not exists (
    select 1 from public.quote_requests where id = v_quote_request_id
  ) then
    raise exception using errcode = '55000', message = 'DOSSIER_PURGED';
  end if;

  select request_kind into strict v_request_kind
  from public.quote_requests
  where id = v_quote_request_id;
  v_payment_term_release := public.require_website_quotation_payment_term_release_v1(
    v_request_kind,
    v_milestones
  );
  if v_payment_term_release is not null then
    perform 1
    from public.website_quotation_payment_term_release_authorities as authority
    where authority.authority_id = (v_payment_term_release->>'authority_id')::uuid
      and authority.status = 'APPROVED'
      and authority.approved_at <= clock_timestamp()
    FOR UPDATE;
    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'WEBSITE_QUOTATION_PAYMENT_TERM_RELEASE_REQUIRED';
    end if;

    select business.* into strict v_business
    from public.quote_request_quotation_business_drafts as business
    join public.quote_request_quotation_business_approval_promotions as promotion
      on promotion.business_draft_id = business.business_draft_id
    where promotion.approval_id = p_approval_id;
    select * into strict v_seller
    from public.quotation_seller_authorities
    where seller_authority_id = v_business.seller_authority_id;
    select * into strict v_template
    from public.quotation_template_authorities
    where id = v_business.template_authority_id;

    v_issuance_authority := jsonb_build_object(
      'approvalId', p_approval_id,
      'approvalPayloadSha256', rtrim(v_business.canonical_payload_sha256),
      'generationContractVersion', v_template.generation_contract_version,
      'sellerAuthorityId', v_seller.seller_authority_id,
      'sellerIdentitySha256', rtrim(v_seller.seller_identity_sha256),
      'templateAuthorityId', v_template.id,
      'templateSha256', lower(rtrim(v_template.template_sha256)),
      'websitePaymentTermReleaseAuthority', v_payment_term_release
    );
    v_expected_issuance_input_sha256 := encode(extensions.digest(
      convert_to(v_issuance_authority::text, 'UTF8'),
      'sha256'
    ), 'hex');
    if v_expected_issuance_input_sha256 is distinct from p_issuance_input_sha256 then
      raise exception using
        errcode = 'P0001',
        message = 'QUOTATION_ISSUANCE_INPUT_MISMATCH';
    end if;
  end if;

  return query select * from public.prepare_quotation_issuance_unlocked_v2(
    p_approval_id, p_issue_year, p_generation_contract_version,
    p_issuance_input_sha256, p_idempotency_key,
    p_admin_access_token_hash, p_prepared_by
  );
end;
$$;

alter table public.website_quotation_payment_term_release_authorities enable row level security;
alter table public.website_quotation_payment_term_release_authorities force row level security;

revoke all privileges on table public.website_quotation_payment_term_release_authorities
from public, anon, authenticated, service_role;
revoke all on function public.validate_website_quotation_payment_term_release_insert_v1()
from public, anon, authenticated, service_role;
revoke all on function public.prevent_website_quotation_payment_term_release_mutation_v1()
from public, anon, authenticated, service_role;
revoke all on function public.require_website_quotation_payment_term_release_v1(text, jsonb)
from public, anon, authenticated, service_role;
revoke all on function public.resolve_first_customer_quotation_orchestration_v1(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.resolve_first_customer_quotation_orchestration_v1(uuid, uuid)
to service_role;

comment on table public.website_quotation_payment_term_release_authorities is
  'External release authority for the selected 14-day Website quotation payment term. Intentionally empty until separate evidence is approved; identity and evidence are immutable, with database-owner-only retirement for replacement.';
comment on function public.require_website_quotation_payment_term_release_v1(text, jsonb) is
  'Fail-closed Website-only payment-term gate. Non-Website quotations remain outside this authority.';
comment on function public.resolve_first_customer_quotation_orchestration_v1(uuid, uuid) is
  'Service-only owner/admin resolver that requires Website payment-term release before quotation number preparation.';