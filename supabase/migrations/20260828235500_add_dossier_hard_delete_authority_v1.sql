create table lws_internal.dossier_identity_anchors (
  quote_request_id uuid primary key,
  application_reference text unique
    check (application_reference ~ '^LWS-AAN-[0-9]{4}-[0-9]{4}$'),
  original_created_at timestamptz not null,
  record_classification text not null
    check (record_classification in ('production', 'internal_e2e')),
  request_kind text not null,
  anchored_at timestamptz not null default clock_timestamp()
);

create table lws_internal.intake_identity_anchors (
  intake_id uuid primary key,
  quote_request_id uuid not null
    references lws_internal.dossier_identity_anchors(quote_request_id) on delete restrict,
  original_created_at timestamptz not null,
  anchored_at timestamptz not null default clock_timestamp(),
  unique (quote_request_id)
);

create table lws_internal.dossier_purge_tombstones (
  quote_request_id uuid primary key
    references lws_internal.dossier_identity_anchors(quote_request_id) on delete restrict,
  purged_at timestamptz not null,
  purged_by_operator_id uuid not null
    references public.commercial_operators(operator_id) on delete restrict,
  purge_reason text not null check (char_length(btrim(purge_reason)) between 1 and 500),
  original_request_status text not null,
  original_dossier_state text not null check (original_dossier_state = 'TRASHED'),
  original_state_before_trash text not null
    check (original_state_before_trash in ('ACTIVE', 'ARCHIVED')),
  record_classification text not null
    check (record_classification in ('production', 'internal_e2e')),
  request_kind text not null,
  contract_version smallint not null check (contract_version = 1),
  idempotency_key uuid not null unique,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$')
);

create table lws_internal.dossier_preofficial_quotation_tombstones (
  evidence_id bigint generated always as identity primary key,
  quote_request_id uuid not null
    references lws_internal.dossier_identity_anchors(quote_request_id) on delete restrict,
  record_kind text not null check (record_kind in (
    'APPROVAL_DRAFT', 'BUSINESS_DRAFT', 'APPROVAL', 'PROMOTION'
  )),
  source_record_id uuid not null,
  evidence_sha256 char(64) not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  original_created_at timestamptz not null,
  purged_at timestamptz not null,
  unique (record_kind, source_record_id)
);

insert into lws_internal.dossier_identity_anchors (
  quote_request_id, application_reference, original_created_at,
  record_classification, request_kind
)
select
  request.id, request.application_reference, request.created_at,
  request.record_classification, request.request_kind
from public.quote_requests as request;

insert into lws_internal.intake_identity_anchors (
  intake_id, quote_request_id, original_created_at
)
select intake.id, intake.quote_request_id, intake.created_at
from public.quote_request_intakes as intake;

create function lws_internal.anchor_dossier_identity_v1()
returns trigger
language plpgsql
security definer
set search_path = lws_internal, pg_catalog
as $$
begin
  insert into lws_internal.dossier_identity_anchors (
    quote_request_id, application_reference, original_created_at,
    record_classification, request_kind
  ) values (
    new.id, new.application_reference, new.created_at,
    new.record_classification, new.request_kind
  );
  return new;
end;
$$;

create trigger trg_quote_requests_anchor_identity
after insert on public.quote_requests
for each row execute function lws_internal.anchor_dossier_identity_v1();

create function lws_internal.sync_dossier_application_reference_v1()
returns trigger
language plpgsql
security definer
set search_path = lws_internal, pg_catalog
as $$
begin
  perform set_config('lws.dossier_anchor_reference_sync', 'on', true);
  update lws_internal.dossier_identity_anchors
  set application_reference = new.application_reference
  where quote_request_id = new.id
    and application_reference is null;
  perform set_config('lws.dossier_anchor_reference_sync', '', true);
  return new;
end;
$$;

create trigger trg_quote_requests_sync_anchor_reference
after update of application_reference on public.quote_requests
for each row
when (old.application_reference is null and new.application_reference is not null)
execute function lws_internal.sync_dossier_application_reference_v1();

create function lws_internal.anchor_intake_identity_v1()
returns trigger
language plpgsql
security definer
set search_path = lws_internal, pg_catalog
as $$
begin
  insert into lws_internal.intake_identity_anchors (
    intake_id, quote_request_id, original_created_at
  ) values (
    new.id, new.quote_request_id, new.created_at
  );
  return new;
end;
$$;

create trigger trg_quote_request_intakes_anchor_identity
after insert on public.quote_request_intakes
for each row execute function lws_internal.anchor_intake_identity_v1();

create function lws_internal.prevent_dossier_purge_authority_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op = 'UPDATE' and tg_table_name = 'dossier_identity_anchors' then
    if current_setting('lws.dossier_anchor_reference_sync', true) = 'on'
       and old.application_reference is null
       and new.application_reference is not null
       and (to_jsonb(new) - 'application_reference')
         = (to_jsonb(old) - 'application_reference') then
      return new;
    end if;
  end if;
  raise exception using errcode = '55000', message = 'DOSSIER_PURGE_AUTHORITY_IMMUTABLE';
end;
$$;

create trigger trg_dossier_identity_anchors_immutable
before update or delete on lws_internal.dossier_identity_anchors
for each row execute function lws_internal.prevent_dossier_purge_authority_mutation_v1();

create trigger trg_intake_identity_anchors_immutable
before update or delete on lws_internal.intake_identity_anchors
for each row execute function lws_internal.prevent_dossier_purge_authority_mutation_v1();

create trigger trg_dossier_purge_tombstones_immutable
before update or delete on lws_internal.dossier_purge_tombstones
for each row execute function lws_internal.prevent_dossier_purge_authority_mutation_v1();

create trigger trg_dossier_preofficial_quotation_tombstones_immutable
before update or delete on lws_internal.dossier_preofficial_quotation_tombstones
for each row execute function lws_internal.prevent_dossier_purge_authority_mutation_v1();

alter table lws_internal.dossier_identity_anchors enable row level security;
alter table lws_internal.dossier_identity_anchors force row level security;
alter table lws_internal.intake_identity_anchors enable row level security;
alter table lws_internal.intake_identity_anchors force row level security;
alter table lws_internal.dossier_purge_tombstones enable row level security;
alter table lws_internal.dossier_purge_tombstones force row level security;
alter table lws_internal.dossier_preofficial_quotation_tombstones enable row level security;
alter table lws_internal.dossier_preofficial_quotation_tombstones force row level security;

revoke all on table
  lws_internal.dossier_identity_anchors,
  lws_internal.intake_identity_anchors,
  lws_internal.dossier_purge_tombstones,
  lws_internal.dossier_preofficial_quotation_tombstones
from public, anon, authenticated, service_role;

revoke all on function lws_internal.anchor_dossier_identity_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.anchor_intake_identity_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.sync_dossier_application_reference_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.prevent_dossier_purge_authority_mutation_v1()
from public, anon, authenticated, service_role;

do $$
declare
  v_constraint record;
begin
  for v_constraint in
    select constraint_table.constraint_schema,
      constraint_table.table_name,
      constraint_table.constraint_name
    from information_schema.referential_constraints as reference_constraint
    join information_schema.table_constraints as constraint_table
      on constraint_table.constraint_catalog = reference_constraint.constraint_catalog
     and constraint_table.constraint_schema = reference_constraint.constraint_schema
     and constraint_table.constraint_name = reference_constraint.constraint_name
    where reference_constraint.unique_constraint_schema = 'public'
      and reference_constraint.unique_constraint_name = 'quote_requests_pkey'
      and (constraint_table.constraint_schema, constraint_table.table_name) in (
        ('lws_internal', 'operator_dossier_assignments'),
        ('lws_internal', 'operator_dossier_assignment_events'),
        ('lws_internal', 'operator_dossier_assignment_commands'),
        ('public', 'quotation_vat_transaction_classifications')
      )
  loop
    execute format(
      'alter table %I.%I drop constraint %I',
      v_constraint.constraint_schema,
      v_constraint.table_name,
      v_constraint.constraint_name
    );
  end loop;
end;
$$;

alter table lws_internal.operator_dossier_assignments
  add constraint operator_dossier_assignments_anchor_fkey
  foreign key (quote_request_id)
  references lws_internal.dossier_identity_anchors(quote_request_id) on delete restrict;

alter table lws_internal.operator_dossier_assignment_events
  add constraint operator_dossier_assignment_events_anchor_fkey
  foreign key (quote_request_id)
  references lws_internal.dossier_identity_anchors(quote_request_id) on delete restrict;

alter table lws_internal.operator_dossier_assignment_commands
  add constraint operator_dossier_assignment_commands_anchor_fkey
  foreign key (quote_request_id)
  references lws_internal.dossier_identity_anchors(quote_request_id) on delete restrict;

alter table public.quotation_vat_transaction_classifications
  add constraint quotation_vat_classifications_anchor_fkey
  foreign key (quote_request_id)
  references lws_internal.dossier_identity_anchors(quote_request_id) on delete restrict;

alter table public.quote_request_intake_lifecycle_events
  drop constraint quote_request_intake_lifecycle_events_intake_id_fkey;

alter table public.quote_request_intake_lifecycle_events
  add constraint intake_lifecycle_events_anchor_fkey
  foreign key (intake_id)
  references lws_internal.intake_identity_anchors(intake_id) on delete restrict;

create or replace function public.prevent_quotation_approval_mutation()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  if tg_op = 'DELETE'
     and current_setting('lws.dossier_purge_authority', true) = 'on' then
    return old;
  end if;
  raise exception using errcode = '55000', message = 'QUOTATION_APPROVAL_IMMUTABLE';
end;
$$;

create or replace function public.guard_quotation_business_authority_mutation_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  if tg_op = 'DELETE'
     and tg_table_name = 'quote_request_quotation_business_drafts'
     and current_setting('lws.dossier_purge_authority', true) = 'on' then
    return old;
  end if;
  if tg_op = 'UPDATE'
     and current_setting('lws.quotation_business_authority_transition', true) = 'ACTIVATE_VERSION'
     and old.status = 'APPROVED' and new.status = 'RETIRED'
     and old.retired_by is null and old.retired_at is null and old.retirement_reason is null
     and nullif(btrim(new.retired_by), '') is not null
     and new.retired_at is not null
     and nullif(btrim(new.retirement_reason), '') is not null
     and (to_jsonb(new) - array['status', 'retired_by', 'retired_at', 'retirement_reason']::text[])
       = (to_jsonb(old) - array['status', 'retired_by', 'retired_at', 'retirement_reason']::text[]) then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'QUOTATION_BUSINESS_AUTHORITY_IMMUTABLE';
end;
$$;

create or replace function public.prevent_quotation_business_approval_promotion_mutation_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  if tg_op = 'DELETE'
     and current_setting('lws.dossier_purge_authority', true) = 'on' then
    return old;
  end if;
  raise exception using errcode = '55000', message = 'QUOTATION_BUSINESS_APPROVAL_PROMOTION_IMMUTABLE';
end;
$$;

create or replace function public.prevent_quotation_vat_governance_mutation_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  if tg_op = 'DELETE'
     and tg_table_name = 'quotation_business_draft_vat_bindings'
     and current_setting('lws.dossier_purge_authority', true) = 'on' then
    return old;
  end if;
  raise exception using errcode = '55000', message = 'QUOTATION_VAT_GOVERNANCE_IMMUTABLE';
end;
$$;

create function public.can_purge_dossier_v1(p_quote_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_state lws_internal.operator_dossier_states%rowtype;
begin
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = auth.uid();
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role <> 'owner' then
    raise exception using errcode = '42501', message = 'OWNER_REQUIRED';
  end if;

  if exists (
    select 1 from lws_internal.dossier_purge_tombstones
    where quote_request_id = p_quote_request_id
  ) then
    return jsonb_build_object('can_purge', false, 'reason', 'ALREADY_PURGED');
  end if;

  select * into v_state
  from lws_internal.operator_dossier_states
  where quote_request_id = p_quote_request_id;
  if not found then
    return jsonb_build_object('can_purge', false, 'reason', 'DOSSIER_NOT_FOUND');
  end if;
  if v_state.state <> 'TRASHED' then
    return jsonb_build_object('can_purge', false, 'reason', 'DOSSIER_NOT_TRASHED');
  end if;

  if exists (
    select 1
    from public.quote_request_quotation_issuances as issuance
    join public.quote_request_quotation_approvals as approval
      on approval.id = issuance.approval_id
    where approval.quote_request_id = p_quote_request_id
  ) then
    return jsonb_build_object('can_purge', false, 'reason', 'OFFICIAL_QUOTATION_EXISTS');
  end if;

  if exists (select 1 from public.sdf_projects where quote_request_id = p_quote_request_id)
     or exists (select 1 from public.sdf_quotations where quote_request_id = p_quote_request_id)
     or exists (select 1 from public.customer_requests where quote_request_id = p_quote_request_id) then
    return jsonb_build_object('can_purge', false, 'reason', 'PROTECTED_DOSSIER_DEPENDENCY_EXISTS');
  end if;

  return jsonb_build_object('can_purge', true, 'reason', null);
end;
$$;

create function public.purge_dossier_v1(
  p_quote_request_id uuid,
  p_reason text,
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
  v_request public.quote_requests%rowtype;
  v_state lws_internal.operator_dossier_states%rowtype;
  v_existing lws_internal.dossier_purge_tombstones%rowtype;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_fingerprint char(64);
  v_purged_at timestamptz := clock_timestamp();
begin
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = auth.uid();
  if not found or v_operator.status <> 'ACTIVE' or v_operator.role <> 'owner' then
    raise exception using errcode = '42501', message = 'OWNER_REQUIRED';
  end if;
  if p_quote_request_id is null or p_idempotency_key is null
     or char_length(v_reason) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'INVALID_DOSSIER_PURGE_REQUEST';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'contract_version', 1,
    'idempotency_key', p_idempotency_key,
    'operator_id', v_operator.operator_id,
    'quote_request_id', p_quote_request_id,
    'reason', v_reason
  )::text, 'UTF8'), 'sha256'), 'hex');

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('DOSSIER:' || p_quote_request_id::text, 0)
  );

  select * into v_existing
  from lws_internal.dossier_purge_tombstones
  where quote_request_id = p_quote_request_id;
  if found then
    if v_existing.idempotency_key <> p_idempotency_key
       or v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'DOSSIER_ALREADY_PURGED';
    end if;
    return jsonb_build_object(
      'quote_request_id', v_existing.quote_request_id,
      'purged_at', v_existing.purged_at,
      'replayed', true
    );
  end if;

  select * into v_request
  from public.quote_requests
  where id = p_quote_request_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'DOSSIER_NOT_FOUND';
  end if;

  select * into v_state
  from lws_internal.operator_dossier_states
  where quote_request_id = p_quote_request_id
  for update;
  if not found or v_state.state <> 'TRASHED' then
    raise exception using errcode = 'P0001', message = 'DOSSIER_NOT_TRASHED';
  end if;

  if exists (
    select 1
    from public.quote_request_quotation_issuances as issuance
    join public.quote_request_quotation_approvals as approval
      on approval.id = issuance.approval_id
    where approval.quote_request_id = p_quote_request_id
  ) then
    raise exception using
      errcode = '55000',
      message = 'OFFICIAL_QUOTATION_EXISTS',
      detail = 'Definitief verwijderen niet toegestaan - voor dit dossier bestaat reeds een officiele offerte.';
  end if;

  if exists (select 1 from public.sdf_projects where quote_request_id = p_quote_request_id)
     or exists (select 1 from public.sdf_quotations where quote_request_id = p_quote_request_id)
     or exists (select 1 from public.customer_requests where quote_request_id = p_quote_request_id) then
    raise exception using errcode = '55000', message = 'PROTECTED_DOSSIER_DEPENDENCY_EXISTS';
  end if;

  insert into lws_internal.dossier_preofficial_quotation_tombstones (
    quote_request_id, record_kind, source_record_id,
    evidence_sha256, original_created_at, purged_at
  )
  select draft.quote_request_id, 'APPROVAL_DRAFT', draft.id,
    draft.payload_fingerprint, draft.created_at, v_purged_at
  from public.quote_request_quotation_approval_drafts as draft
  where draft.quote_request_id = p_quote_request_id
  union all
  select business.quote_request_id, 'BUSINESS_DRAFT', business.business_draft_id,
    rtrim(business.canonical_payload_sha256), business.created_at, v_purged_at
  from public.quote_request_quotation_business_drafts as business
  where business.quote_request_id = p_quote_request_id
  union all
  select approval.quote_request_id, 'APPROVAL', approval.id,
    approval.payload_sha256, approval.approved_at, v_purged_at
  from public.quote_request_quotation_approvals as approval
  where approval.quote_request_id = p_quote_request_id
  union all
  select business.quote_request_id, 'PROMOTION', promotion.business_draft_id,
    encode(extensions.digest(convert_to(jsonb_build_object(
      'approval_id', promotion.approval_id,
      'business_draft_id', promotion.business_draft_id
    )::text, 'UTF8'), 'sha256'), 'hex'), business.created_at, v_purged_at
  from public.quote_request_quotation_business_approval_promotions as promotion
  join public.quote_request_quotation_business_drafts as business
    on business.business_draft_id = promotion.business_draft_id
  where business.quote_request_id = p_quote_request_id;

  insert into lws_internal.dossier_purge_tombstones (
    quote_request_id, purged_at, purged_by_operator_id, purge_reason,
    original_request_status, original_dossier_state, original_state_before_trash,
    record_classification, request_kind, contract_version,
    idempotency_key, request_fingerprint
  ) values (
    p_quote_request_id, v_purged_at, v_operator.operator_id, v_reason,
    v_request.status::text, v_state.state, v_state.state_before_trash,
    v_request.record_classification, v_request.request_kind, 1,
    p_idempotency_key, v_fingerprint
  );

  perform set_config('lws.dossier_purge_authority', 'on', true);

  delete from public.quote_request_quotation_business_approval_promotion_operations
  where business_draft_id in (
    select business_draft_id
    from public.quote_request_quotation_business_drafts
    where quote_request_id = p_quote_request_id
  );
  delete from public.quote_request_quotation_business_approval_promotions
  where business_draft_id in (
    select business_draft_id
    from public.quote_request_quotation_business_drafts
    where quote_request_id = p_quote_request_id
  );
  delete from public.quotation_business_draft_vat_bindings
  where business_draft_id in (
    select business_draft_id
    from public.quote_request_quotation_business_drafts
    where quote_request_id = p_quote_request_id
  );
  delete from public.quote_request_quotation_business_drafts
  where quote_request_id = p_quote_request_id;
  delete from public.quote_request_quotation_approval_operations
  where draft_id in (
      select id from public.quote_request_quotation_approval_drafts
      where quote_request_id = p_quote_request_id
    )
    or approval_id in (
      select id from public.quote_request_quotation_approvals
      where quote_request_id = p_quote_request_id
    );
  delete from public.quote_request_quotation_approval_integrity
  where approval_id in (
    select id from public.quote_request_quotation_approvals
    where quote_request_id = p_quote_request_id
  );
  delete from public.quote_request_quotation_approvals
  where quote_request_id = p_quote_request_id;
  delete from public.quote_request_quotation_approval_drafts
  where quote_request_id = p_quote_request_id;

  perform set_config('lws.dossier_purge_authority', '', true);

  delete from public.quote_request_email_jobs
  where quote_request_id = p_quote_request_id;
  delete from lws_internal.application_intake_automation_work
  where quote_request_id = p_quote_request_id;
  delete from public.quote_request_pricing_snapshot_integrity
  where snapshot_id in (
    select snapshot.id
    from public.quote_request_pricing_snapshots as snapshot
    join public.quote_request_intakes as intake on intake.id = snapshot.intake_id
    where intake.quote_request_id = p_quote_request_id
  );
  delete from public.quote_request_pricing_snapshots
  where intake_id in (
    select id from public.quote_request_intakes
    where quote_request_id = p_quote_request_id
  );
  delete from public.quote_request_intakes
  where quote_request_id = p_quote_request_id;
  delete from lws_internal.operator_dossier_states
  where quote_request_id = p_quote_request_id;
  delete from public.quote_requests
  where id = p_quote_request_id;

  return jsonb_build_object(
    'quote_request_id', p_quote_request_id,
    'purged_at', v_purged_at,
    'replayed', false
  );
end;
$$;

alter function public.prepare_quotation_issuance_v1(
  uuid, smallint, smallint, text, uuid, text, text
) rename to prepare_quotation_issuance_unlocked_v1;

create function public.prepare_quotation_issuance_v1(
  p_approval_id uuid,
  p_issue_year smallint,
  p_generation_contract_version smallint,
  p_generation_payload_sha256 text,
  p_idempotency_key uuid,
  p_admin_access_token_hash text,
  p_prepared_by text
)
returns table (
  issuance_id uuid, quotation_number text, quotation_version integer,
  status text, generation_contract_version smallint,
  generation_payload_sha256 text, was_created boolean
)
language plpgsql
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_quote_request_id uuid;
begin
  select quote_request_id into v_quote_request_id
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
  return query select * from public.prepare_quotation_issuance_unlocked_v1(
    p_approval_id, p_issue_year, p_generation_contract_version,
    p_generation_payload_sha256, p_idempotency_key,
    p_admin_access_token_hash, p_prepared_by
  );
end;
$$;

alter function public.prepare_quotation_issuance_v2(
  uuid, smallint, smallint, text, uuid, text, text
) rename to prepare_quotation_issuance_unlocked_v2;

create function public.prepare_quotation_issuance_v2(
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
begin
  select quote_request_id into v_quote_request_id
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
  return query select * from public.prepare_quotation_issuance_unlocked_v2(
    p_approval_id, p_issue_year, p_generation_contract_version,
    p_issuance_input_sha256, p_idempotency_key,
    p_admin_access_token_hash, p_prepared_by
  );
end;
$$;

revoke all on function public.can_purge_dossier_v1(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.can_purge_dossier_v1(uuid) to authenticated;

revoke all on function public.purge_dossier_v1(uuid, text, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.purge_dossier_v1(uuid, text, uuid) to authenticated;

revoke all on function public.prepare_quotation_issuance_unlocked_v1(
  uuid, smallint, smallint, text, uuid, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.prepare_quotation_issuance_unlocked_v2(
  uuid, smallint, smallint, text, uuid, text, text
) from public, anon, authenticated, service_role;

revoke all on function public.prepare_quotation_issuance_v1(
  uuid, smallint, smallint, text, uuid, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.prepare_quotation_issuance_v1(
  uuid, smallint, smallint, text, uuid, text, text
) to service_role;

revoke all on function public.prepare_quotation_issuance_v2(
  uuid, smallint, smallint, text, uuid, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.prepare_quotation_issuance_v2(
  uuid, smallint, smallint, text, uuid, text, text
) to service_role;