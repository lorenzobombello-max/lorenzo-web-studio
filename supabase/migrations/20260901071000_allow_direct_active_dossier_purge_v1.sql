alter table lws_internal.dossier_purge_tombstones
  drop constraint dossier_purge_tombstones_original_dossier_state_check;
alter table lws_internal.dossier_purge_tombstones
  add constraint dossier_purge_tombstones_original_dossier_state_check
  check (original_dossier_state in ('ACTIVE', 'TRASHED'));

create or replace function public.can_purge_dossier_v1(p_quote_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_request public.quote_requests%rowtype;
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

  select * into v_request
  from public.quote_requests
  where id = p_quote_request_id;
  if not found then
    return jsonb_build_object('can_purge', false, 'reason', 'DOSSIER_NOT_FOUND');
  end if;
  if v_request.request_kind <> 'website' then
    return jsonb_build_object('can_purge', false, 'reason', 'WRONG_PRODUCT_KIND');
  end if;

  select * into v_state
  from lws_internal.operator_dossier_states
  where quote_request_id = p_quote_request_id;
  if not found then
    return jsonb_build_object('can_purge', false, 'reason', 'DOSSIER_NOT_FOUND');
  end if;
  if v_state.state not in ('ACTIVE', 'TRASHED') then
    return jsonb_build_object('can_purge', false, 'reason', 'DOSSIER_STATE_NOT_PURGEABLE');
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

create or replace function public.purge_dossier_v1(
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
  if v_request.request_kind <> 'website' then
    raise exception using errcode = '55000', message = 'WRONG_PRODUCT_KIND';
  end if;

  select * into v_state
  from lws_internal.operator_dossier_states
  where quote_request_id = p_quote_request_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'DOSSIER_NOT_FOUND';
  end if;
  if v_state.state not in ('ACTIVE', 'TRASHED') then
    raise exception using errcode = '55000', message = 'DOSSIER_STATE_NOT_PURGEABLE';
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
    v_request.status::text, v_state.state, coalesce(v_state.state_before_trash, v_state.state),
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

create or replace function public.can_purge_sdf_dossier_v1(p_quote_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_request public.quote_requests%rowtype;
  v_state lws_internal.operator_dossier_states%rowtype;
  v_reason text;
begin
  perform lws_internal.assert_sdf_owner_v1();

  if exists (
    select 1 from lws_internal.dossier_purge_tombstones
    where quote_request_id = p_quote_request_id
  ) then
    return jsonb_build_object('can_purge', false, 'reason', 'ALREADY_PURGED');
  end if;

  select * into v_request
  from public.quote_requests
  where id = p_quote_request_id;
  if not found then
    return jsonb_build_object('can_purge', false, 'reason', 'DOSSIER_NOT_FOUND');
  end if;
  if v_request.request_kind <> 'slimme_documentenflow' then
    return jsonb_build_object('can_purge', false, 'reason', 'WRONG_PRODUCT_KIND');
  end if;

  select * into v_state
  from lws_internal.operator_dossier_states
  where quote_request_id = p_quote_request_id;
  if not found then
    return jsonb_build_object('can_purge', false, 'reason', 'DOSSIER_NOT_FOUND');
  end if;
  if v_state.state not in ('ACTIVE', 'TRASHED') then
    return jsonb_build_object('can_purge', false, 'reason', 'DOSSIER_STATE_NOT_PURGEABLE');
  end if;

  v_reason := lws_internal.sdf_dossier_purge_block_reason_v1(p_quote_request_id);
  return jsonb_build_object('can_purge', v_reason is null, 'reason', v_reason);
end;
$$;

create or replace function public.purge_sdf_dossier_v1(
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
  v_block_reason text;
  v_fingerprint char(64);
  v_purged_at timestamptz := clock_timestamp();
begin
  v_operator := lws_internal.assert_sdf_owner_v1();
  if p_quote_request_id is null or p_idempotency_key is null
     or char_length(v_reason) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'INVALID_SDF_DOSSIER_PURGE_REQUEST';
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
      'deleted', true,
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
  if v_request.request_kind <> 'slimme_documentenflow' then
    raise exception using errcode = '55000', message = 'WRONG_PRODUCT_KIND';
  end if;

  select * into v_state
  from lws_internal.operator_dossier_states
  where quote_request_id = p_quote_request_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'DOSSIER_NOT_FOUND';
  end if;
  if v_state.state not in ('ACTIVE', 'TRASHED') then
    raise exception using errcode = '55000', message = 'DOSSIER_STATE_NOT_PURGEABLE';
  end if;

  v_block_reason := lws_internal.sdf_dossier_purge_block_reason_v1(p_quote_request_id);
  if v_block_reason is not null then
    raise exception using errcode = '55000', message = v_block_reason;
  end if;

  insert into lws_internal.dossier_purge_tombstones (
    quote_request_id, purged_at, purged_by_operator_id, purge_reason,
    original_request_status, original_dossier_state, original_state_before_trash,
    record_classification, request_kind, contract_version,
    idempotency_key, request_fingerprint
  ) values (
    p_quote_request_id, v_purged_at, v_operator.operator_id, v_reason,
    v_request.status::text, v_state.state, coalesce(v_state.state_before_trash, v_state.state),
    v_request.record_classification, v_request.request_kind, 1,
    p_idempotency_key, v_fingerprint
  );

  perform set_config('lws.sdf_dossier_purge_authority', 'on', true);

  delete from public.sdf_quotation_preparation_authorities
  where quote_request_id = p_quote_request_id;
  delete from public.sdf_quotation_documents
  where quotation_id in (
    select quotation_id from public.sdf_quotations
    where quote_request_id = p_quote_request_id
  );
  delete from public.sdf_quotations
  where quote_request_id = p_quote_request_id;
  delete from public.sdf_projects
  where quote_request_id = p_quote_request_id;
  delete from lws_internal.sdf_initial_confirmation_recovery_events
  where quote_request_id = p_quote_request_id;
  delete from public.sdf_qualification_intake_email_jobs
  where intake_id in (
    select intake_id from public.sdf_qualification_intakes
    where quote_request_id = p_quote_request_id
  );
  delete from public.sdf_qualification_intake_events
  where intake_id in (
    select intake_id from public.sdf_qualification_intakes
    where quote_request_id = p_quote_request_id
  );
  delete from public.sdf_qualification_intake_submissions
  where intake_id in (
    select intake_id from public.sdf_qualification_intakes
    where quote_request_id = p_quote_request_id
  );
  delete from public.sdf_qualification_intakes
  where quote_request_id = p_quote_request_id;
  delete from public.sdf_initial_confirmation_email_jobs
  where quote_request_id = p_quote_request_id;
  delete from lws_internal.application_intake_automation_work
  where quote_request_id = p_quote_request_id;
  delete from public.quote_request_email_jobs
  where quote_request_id = p_quote_request_id;
  delete from lws_internal.operator_dossier_states
  where quote_request_id = p_quote_request_id;
  delete from public.quote_requests
  where id = p_quote_request_id;

  perform set_config('lws.sdf_dossier_purge_authority', '', true);

  return jsonb_build_object(
    'quote_request_id', p_quote_request_id,
    'purged_at', v_purged_at,
    'deleted', true,
    'replayed', false
  );
end;
$$;