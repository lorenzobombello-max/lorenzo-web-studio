create or replace function lws_internal.sdf_dossier_purge_block_reason_v1(
  p_quote_request_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
begin
  if exists (
    select 1
    from public.sdf_quotation_acceptances as acceptance
    join public.sdf_quotations as quotation
      on quotation.quotation_id = acceptance.quotation_id
    where quotation.quote_request_id = p_quote_request_id
  ) then
    return 'QUOTATION_ACCEPTANCE_EXISTS';
  end if;

  if exists (
    select 1 from public.sdf_accepted_commercial_terms
    where quote_request_id = p_quote_request_id
  ) then
    return 'ACCEPTED_COMMERCIAL_TERMS_EXIST';
  end if;

  if exists (
    select 1
    from public.sdf_milestone_one_obligations as obligation
    join public.sdf_accepted_commercial_terms as terms
      on terms.accepted_terms_id = obligation.accepted_terms_id
    where terms.quote_request_id = p_quote_request_id
  ) then
    return 'COMMERCIAL_OBLIGATION_EXISTS';
  end if;

  if exists (
    select 1
    from public.sdf_m1_invoice_issuances as issuance
    join public.sdf_m1_invoice_candidates as candidate
      on candidate.candidate_id = issuance.candidate_id
    where candidate.quote_request_id = p_quote_request_id
  ) then
    return 'INVOICE_EXISTS';
  end if;

  if exists (
    select 1 from public.quotation_vat_transaction_classifications
    where quote_request_id = p_quote_request_id
  ) or exists (
    select 1 from public.sdf_quotation_vat_authority_bindings
    where quote_request_id = p_quote_request_id
  ) then
    return 'VAT_COMMERCIAL_BINDING_EXISTS';
  end if;

  if exists (
    select 1
    from public.commercial_projects as project
    join public.quote_request_quotation_issuances as issuance
      on issuance.id = project.quotation_issuance_id
    join public.quote_request_quotation_approvals as approval
      on approval.id = issuance.approval_id
    where approval.quote_request_id = p_quote_request_id
  ) then
    return 'PROJECT_EXISTS';
  end if;

  if exists (
    select 1
    from public.payment_expectations as expectation
    join public.commercial_projects as project
      on project.project_id = expectation.project_id
    join public.quote_request_quotation_issuances as issuance
      on issuance.id = project.quotation_issuance_id
    join public.quote_request_quotation_approvals as approval
      on approval.id = issuance.approval_id
    where approval.quote_request_id = p_quote_request_id
  ) or exists (
    select 1
    from public.payment_evidence as evidence
    join public.commercial_projects as project
      on project.project_id = evidence.project_id
    join public.quote_request_quotation_issuances as issuance
      on issuance.id = project.quotation_issuance_id
    join public.quote_request_quotation_approvals as approval
      on approval.id = issuance.approval_id
    where approval.quote_request_id = p_quote_request_id
  ) or exists (
    select 1
    from public.payment_reconciliations as reconciliation
    join public.commercial_projects as project
      on project.project_id = reconciliation.project_id
    join public.quote_request_quotation_issuances as issuance
      on issuance.id = project.quotation_issuance_id
    join public.quote_request_quotation_approvals as approval
      on approval.id = issuance.approval_id
    where approval.quote_request_id = p_quote_request_id
  ) then
    return 'PAYMENT_EXISTS';
  end if;

  if exists (
    select 1 from public.customer_requests
    where quote_request_id = p_quote_request_id
  ) or exists (
    select 1 from public.document_inbox_customer_request_upload_sources
    where quote_request_id = p_quote_request_id
  ) then
    return 'CUSTOMER_REQUEST_EXISTS';
  end if;

  if exists (
    select 1
    from public.quote_request_quotation_issuances as issuance
    join public.quote_request_quotation_approvals as approval
      on approval.id = issuance.approval_id
    where approval.quote_request_id = p_quote_request_id
  ) then
    return 'OTHER_PROTECTED_DEPENDENCY';
  end if;

  return null;
end;
$$;

create or replace function public.guard_sdf_quotation_identity_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_request_kind text;
begin
  if tg_op = 'DELETE'
     and current_setting('lws.sdf_dossier_purge_authority', true) = 'on' then
    return old;
  end if;
  if tg_op in ('UPDATE', 'DELETE') then
    raise exception using errcode = '55000', message = 'SDF_QUOTATION_IDENTITY_IMMUTABLE';
  end if;

  select request_kind into v_request_kind
  from public.quote_requests
  where id = new.quote_request_id;

  if not found then
    raise exception using errcode = '23503', message = 'SDF_QUOTATION_APPLICATION_NOT_FOUND';
  end if;
  if v_request_kind <> 'slimme_documentenflow' then
    raise exception using errcode = '23514', message = 'SDF_QUOTATION_REQUIRES_SDF_APPLICATION';
  end if;
  return new;
end;
$$;

create or replace function public.guard_sdf_quotation_document_evidence_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_request_kind text;
begin
  if tg_op = 'DELETE'
     and current_setting('lws.sdf_dossier_purge_authority', true) = 'on' then
    return old;
  end if;
  if tg_op in ('UPDATE', 'DELETE') then
    raise exception using errcode = '55000', message = 'SDF_QUOTATION_EVIDENCE_IMMUTABLE';
  end if;

  select qr.request_kind into v_request_kind
  from public.sdf_quotations as quotation
  join public.quote_requests as qr on qr.id = quotation.quote_request_id
  where quotation.quotation_id = new.quotation_id;

  if not found then
    raise exception using errcode = '23503', message = 'SDF_QUOTATION_NOT_FOUND';
  end if;
  if v_request_kind <> 'slimme_documentenflow' then
    raise exception using errcode = '23514', message = 'SDF_QUOTATION_EVIDENCE_REQUIRES_SDF_APPLICATION';
  end if;
  return new;
end;
$$;

create or replace function public.guard_sdf_project_foundation_v1()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_request_kind text;
begin
  if tg_op = 'DELETE'
     and current_setting('lws.sdf_dossier_purge_authority', true) = 'on' then
    return old;
  end if;
  if tg_op in ('UPDATE', 'DELETE') then
    raise exception using errcode = '55000', message = 'SDF_PROJECT_IMMUTABLE';
  end if;

  select request_kind into v_request_kind
  from public.quote_requests
  where id = new.quote_request_id;

  if not found then
    raise exception using errcode = '23503', message = 'SDF_PROJECT_APPLICATION_NOT_FOUND';
  end if;
  if v_request_kind <> 'slimme_documentenflow' then
    raise exception using errcode = '23514', message = 'SDF_PROJECT_REQUIRES_SDF_APPLICATION';
  end if;
  return new;
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
  if not found or v_state.state <> 'TRASHED' then
    raise exception using errcode = '55000', message = 'DOSSIER_NOT_TRASHED';
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
    v_request.status::text, v_state.state, v_state.state_before_trash,
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

revoke all on function lws_internal.sdf_dossier_purge_block_reason_v1(uuid)
from public, anon, authenticated, service_role;

revoke all on function public.guard_sdf_quotation_identity_v1()
from public, anon, authenticated, service_role;
revoke all on function public.guard_sdf_quotation_document_evidence_v1()
from public, anon, authenticated, service_role;
revoke all on function public.guard_sdf_project_foundation_v1()
from public, anon, authenticated, service_role;

revoke all on function public.purge_sdf_dossier_v1(uuid, text, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.purge_sdf_dossier_v1(uuid, text, uuid)
to authenticated;