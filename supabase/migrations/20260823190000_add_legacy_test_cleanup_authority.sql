create function lws_internal.legacy_test_cleanup_identity_sha256_v1(
  p_quote_request_id uuid,
  p_support_reference text,
  p_application_reference text,
  p_request_kind text,
  p_dossier_created_at timestamptz,
  p_authoritative_browse_at timestamptz,
  p_authority_reason text,
  p_source_checkpoint text,
  p_source_migration text
)
returns char(64)
language sql
immutable
set search_path = pg_catalog, extensions
as $$
  select encode(extensions.digest(convert_to(concat_ws('|',
    p_quote_request_id::text,
    p_support_reference,
    coalesce(p_application_reference, '<null>'),
    p_request_kind,
    extract(epoch from p_dossier_created_at)::numeric::text,
    extract(epoch from p_authoritative_browse_at)::numeric::text,
    p_authority_reason,
    p_source_checkpoint,
    p_source_migration
  ), 'UTF8'), 'sha256'), 'hex')::char(64)
$$;

create table lws_internal.legacy_test_cleanup_authorities (
  quote_request_id uuid primary key,
  support_reference text not null check (support_reference ~ '^#[0-9A-F]{8}$'),
  application_reference text check (
    application_reference is null
    or application_reference ~ '^LWS-AAN-[0-9]{4}-[0-9]{4}$'
  ),
  request_kind text not null check (request_kind in ('website', 'slimme_documentenflow')),
  dossier_created_at timestamptz not null,
  authoritative_browse_at timestamptz not null,
  authority_reason text not null check (
    authority_reason = 'LEGACY_OPERATOR_TEST_DEVELOPMENT_DOSSIER_CLEANUP_ONLY'
  ),
  source_checkpoint text not null check (
    source_checkpoint = 'FINAL-PRODUCTION-CHECKPOINT-20260814.md:legacy-authority-inventory-2026-08-23'
  ),
  source_migration text not null check (
    source_migration = '20260823190000_add_legacy_test_cleanup_authority'
  ),
  identity_evidence_sha256 char(64) generated always as (
    lws_internal.legacy_test_cleanup_identity_sha256_v1(
      quote_request_id,
      support_reference,
      application_reference,
      request_kind,
      dossier_created_at,
      authoritative_browse_at,
      authority_reason,
      source_checkpoint,
      source_migration
    )
  ) stored
);

create table lws_internal.legacy_test_cleanup_consumptions (
  authority_quote_request_id uuid primary key
    references lws_internal.legacy_test_cleanup_authorities(quote_request_id),
  cleanup_operation_id uuid not null unique,
  consumed_at timestamptz not null,
  authorized_operator_id uuid not null references public.commercial_operators(operator_id),
  result text not null check (result = 'COMPLETED'),
  previous_identity_evidence_sha256 char(64) not null
    check (previous_identity_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  result_evidence_sha256 char(64) not null
    check (result_evidence_sha256 ~ '^[0-9a-f]{64}$')
);

create function lws_internal.prevent_legacy_test_cleanup_authority_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'LEGACY_TEST_CLEANUP_AUTHORITY_IMMUTABLE';
end;
$$;

create function lws_internal.prevent_legacy_test_cleanup_consumption_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'LEGACY_TEST_CLEANUP_CONSUMPTION_APPEND_ONLY';
end;
$$;

create function lws_internal.guard_legacy_test_cleanup_consumption_insert_v1()
returns trigger
language plpgsql
set search_path = lws_internal, pg_catalog
as $$
declare
  v_identity_evidence_sha256 char(64);
begin
  select identity_evidence_sha256
  into strict v_identity_evidence_sha256
  from lws_internal.legacy_test_cleanup_authorities
  where quote_request_id = new.authority_quote_request_id;

  if new.previous_identity_evidence_sha256 is distinct from v_identity_evidence_sha256 then
    raise exception using errcode = '23514', message = 'LEGACY_TEST_CLEANUP_IDENTITY_EVIDENCE_MISMATCH';
  end if;
  return new;
end;
$$;

create trigger trg_legacy_test_cleanup_authorities_immutable
before update or delete on lws_internal.legacy_test_cleanup_authorities
for each row execute function lws_internal.prevent_legacy_test_cleanup_authority_mutation_v1();

create trigger trg_legacy_test_cleanup_consumptions_append_only
before update or delete on lws_internal.legacy_test_cleanup_consumptions
for each row execute function lws_internal.prevent_legacy_test_cleanup_consumption_mutation_v1();

create trigger trg_legacy_test_cleanup_consumptions_identity_guard
before insert on lws_internal.legacy_test_cleanup_consumptions
for each row execute function lws_internal.guard_legacy_test_cleanup_consumption_insert_v1();

alter table lws_internal.legacy_test_cleanup_authorities enable row level security;
alter table lws_internal.legacy_test_cleanup_authorities force row level security;
alter table lws_internal.legacy_test_cleanup_consumptions enable row level security;
alter table lws_internal.legacy_test_cleanup_consumptions force row level security;

revoke all on table lws_internal.legacy_test_cleanup_authorities
from public, anon, authenticated, service_role;
revoke all on table lws_internal.legacy_test_cleanup_consumptions
from public, anon, authenticated, service_role;
revoke all on function lws_internal.legacy_test_cleanup_identity_sha256_v1(uuid, text, text, text, timestamptz, timestamptz, text, text, text)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.prevent_legacy_test_cleanup_authority_mutation_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.prevent_legacy_test_cleanup_consumption_mutation_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_legacy_test_cleanup_consumption_insert_v1()
from public, anon, authenticated, service_role;

insert into lws_internal.legacy_test_cleanup_authorities (
  quote_request_id,
  support_reference,
  application_reference,
  request_kind,
  dossier_created_at,
  authoritative_browse_at,
  authority_reason,
  source_checkpoint,
  source_migration
)
values
  ('a3e6cfbc-a575-4c8a-a9ca-1f091aba5414', '#A3E6CFBC', 'LWS-AAN-2026-0002', 'website', '2026-08-23T04:11:32.587019Z', '2026-08-23T07:39:10.676440Z', 'LEGACY_OPERATOR_TEST_DEVELOPMENT_DOSSIER_CLEANUP_ONLY', 'FINAL-PRODUCTION-CHECKPOINT-20260814.md:legacy-authority-inventory-2026-08-23', '20260823190000_add_legacy_test_cleanup_authority'),
  ('f98b2f08-e816-4ca5-85eb-5f05fa5045c6', '#F98B2F08', 'LWS-AAN-2026-0001', 'website', '2026-08-23T04:46:03.906006Z', '2026-08-23T06:38:13.263818Z', 'LEGACY_OPERATOR_TEST_DEVELOPMENT_DOSSIER_CLEANUP_ONLY', 'FINAL-PRODUCTION-CHECKPOINT-20260814.md:legacy-authority-inventory-2026-08-23', '20260823190000_add_legacy_test_cleanup_authority'),
  ('388e8887-8b20-4300-b1e8-183718fe6b57', '#388E8887', null, 'website', '2026-08-18T04:38:02.741551Z', '2026-08-18T09:21:18.906106Z', 'LEGACY_OPERATOR_TEST_DEVELOPMENT_DOSSIER_CLEANUP_ONLY', 'FINAL-PRODUCTION-CHECKPOINT-20260814.md:legacy-authority-inventory-2026-08-23', '20260823190000_add_legacy_test_cleanup_authority'),
  ('620b3fa5-2e6b-4439-9d22-741b8541fbdf', '#620B3FA5', null, 'website', '2026-08-18T06:41:37.328379Z', '2026-08-18T06:51:23.983507Z', 'LEGACY_OPERATOR_TEST_DEVELOPMENT_DOSSIER_CLEANUP_ONLY', 'FINAL-PRODUCTION-CHECKPOINT-20260814.md:legacy-authority-inventory-2026-08-23', '20260823190000_add_legacy_test_cleanup_authority'),
  ('d3752349-3489-4c19-bd03-f0cc076b5607', '#D3752349', null, 'slimme_documentenflow', '2026-08-18T06:40:00.735922Z', '2026-08-18T06:40:00.735922Z', 'LEGACY_OPERATOR_TEST_DEVELOPMENT_DOSSIER_CLEANUP_ONLY', 'FINAL-PRODUCTION-CHECKPOINT-20260814.md:legacy-authority-inventory-2026-08-23', '20260823190000_add_legacy_test_cleanup_authority'),
  ('741de441-04f7-41e9-88fe-da92d699e37c', '#741DE441', null, 'website', '2026-08-18T00:20:01.917620Z', '2026-08-18T02:57:54.766587Z', 'LEGACY_OPERATOR_TEST_DEVELOPMENT_DOSSIER_CLEANUP_ONLY', 'FINAL-PRODUCTION-CHECKPOINT-20260814.md:legacy-authority-inventory-2026-08-23', '20260823190000_add_legacy_test_cleanup_authority'),
  ('0696171e-a315-4c03-b402-ba0b689abfbc', '#0696171E', null, 'slimme_documentenflow', '2026-08-17T23:52:15.685429Z', '2026-08-17T23:52:15.685429Z', 'LEGACY_OPERATOR_TEST_DEVELOPMENT_DOSSIER_CLEANUP_ONLY', 'FINAL-PRODUCTION-CHECKPOINT-20260814.md:legacy-authority-inventory-2026-08-23', '20260823190000_add_legacy_test_cleanup_authority'),
  ('5c9a89e7-9af1-4ed0-990d-6ebe268fa871', '#5C9A89E7', null, 'website', '2026-08-09T21:55:51.188608Z', '2026-08-09T22:09:30.213079Z', 'LEGACY_OPERATOR_TEST_DEVELOPMENT_DOSSIER_CLEANUP_ONLY', 'FINAL-PRODUCTION-CHECKPOINT-20260814.md:legacy-authority-inventory-2026-08-23', '20260823190000_add_legacy_test_cleanup_authority'),
  ('a4e6cbb0-583e-4d0b-86dc-d0c7a5de9d8f', '#A4E6CBB0', null, 'website', '2026-08-09T01:12:16.064983Z', '2026-08-09T11:42:36.394692Z', 'LEGACY_OPERATOR_TEST_DEVELOPMENT_DOSSIER_CLEANUP_ONLY', 'FINAL-PRODUCTION-CHECKPOINT-20260814.md:legacy-authority-inventory-2026-08-23', '20260823190000_add_legacy_test_cleanup_authority'),
  ('8c7ed4d4-7ff4-4e9c-9f6e-7fd314c1c2b4', '#8C7ED4D4', null, 'website', '2026-08-08T19:40:16.615872Z', '2026-08-08T19:59:40.566391Z', 'LEGACY_OPERATOR_TEST_DEVELOPMENT_DOSSIER_CLEANUP_ONLY', 'FINAL-PRODUCTION-CHECKPOINT-20260814.md:legacy-authority-inventory-2026-08-23', '20260823190000_add_legacy_test_cleanup_authority'),
  ('19877689-7c72-4ad4-9a7c-7b9459b22ea1', '#19877689', null, 'website', '2026-08-08T14:54:51.783217Z', '2026-08-08T15:55:13.497810Z', 'LEGACY_OPERATOR_TEST_DEVELOPMENT_DOSSIER_CLEANUP_ONLY', 'FINAL-PRODUCTION-CHECKPOINT-20260814.md:legacy-authority-inventory-2026-08-23', '20260823190000_add_legacy_test_cleanup_authority');

create function lws_internal.assert_legacy_test_cleanup_candidate_v1(p_quote_request_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_authority lws_internal.legacy_test_cleanup_authorities%rowtype;
  v_request public.quote_requests%rowtype;
  v_browse_at timestamptz;
begin
  select * into v_authority
  from lws_internal.legacy_test_cleanup_authorities
  where quote_request_id = p_quote_request_id;
  if not found then
    raise exception using errcode = '42501', message = 'LEGACY_TEST_CLEANUP_AUTHORITY_REQUIRED';
  end if;

  if exists (
    select 1 from lws_internal.legacy_test_cleanup_consumptions
    where authority_quote_request_id = p_quote_request_id
  ) then
    raise exception using errcode = '55000', message = 'LEGACY_TEST_CLEANUP_AUTHORITY_CONSUMED';
  end if;

  select * into v_request from public.quote_requests where id = p_quote_request_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'LEGACY_TEST_CLEANUP_DOSSIER_NOT_FOUND';
  end if;

  if v_request.request_kind = 'website' then
    select submitted_at into v_browse_at
    from public.quote_request_intakes
    where quote_request_id = p_quote_request_id;
  else
    v_browse_at := v_request.created_at;
  end if;

  if v_request.record_classification is distinct from 'production'
     or v_request.support_reference is distinct from v_authority.support_reference
     or v_request.application_reference is distinct from v_authority.application_reference
     or v_request.request_kind is distinct from v_authority.request_kind
     or v_request.created_at is distinct from v_authority.dossier_created_at
     or v_browse_at is distinct from v_authority.authoritative_browse_at then
    raise exception using errcode = '23514', message = 'LEGACY_TEST_CLEANUP_IDENTITY_MISMATCH';
  end if;

  if exists (select 1 from public.quote_request_quotation_approval_drafts where quote_request_id = p_quote_request_id)
     or exists (select 1 from public.quote_request_quotation_approvals where quote_request_id = p_quote_request_id)
     or exists (
       select 1
       from public.quote_request_quotation_issuances issuance
       join public.quote_request_quotation_approvals approval on approval.id = issuance.approval_id
       where approval.quote_request_id = p_quote_request_id
     )
     or exists (
       select 1
       from public.quote_request_quotation_acceptances acceptance
       join public.quote_request_quotation_issuances issuance on issuance.id = acceptance.issuance_id
       join public.quote_request_quotation_approvals approval on approval.id = issuance.approval_id
       where approval.quote_request_id = p_quote_request_id
     ) then
    raise exception using errcode = '55000', message = 'LEGACY_TEST_CLEANUP_QUOTATION_BLOCKER_PRESENT';
  end if;

  if exists (
       select 1
       from public.commercial_customers customer
       join public.quote_request_quotation_acceptances acceptance on acceptance.id = customer.acceptance_id
       join public.quote_request_quotation_issuances issuance on issuance.id = acceptance.issuance_id
       join public.quote_request_quotation_approvals approval on approval.id = issuance.approval_id
       where approval.quote_request_id = p_quote_request_id
     )
     or exists (
       select 1
       from public.commercial_projects project
       join public.quote_request_quotation_acceptances acceptance on acceptance.id = project.acceptance_id
       join public.quote_request_quotation_issuances issuance on issuance.id = acceptance.issuance_id
       join public.quote_request_quotation_approvals approval on approval.id = issuance.approval_id
       where approval.quote_request_id = p_quote_request_id
     ) then
    raise exception using errcode = '55000', message = 'LEGACY_TEST_CLEANUP_COMMERCIAL_BLOCKER_PRESENT';
  end if;

  if exists (
       select 1
       from public.payment_expectations expectation
       join public.commercial_projects project on project.project_id = expectation.project_id
       join public.quote_request_quotation_acceptances acceptance on acceptance.id = project.acceptance_id
       join public.quote_request_quotation_issuances issuance on issuance.id = acceptance.issuance_id
       join public.quote_request_quotation_approvals approval on approval.id = issuance.approval_id
       where approval.quote_request_id = p_quote_request_id
     )
     or exists (
       select 1
       from public.payment_evidence evidence
       join public.commercial_projects project on project.project_id = evidence.project_id
       join public.quote_request_quotation_acceptances acceptance on acceptance.id = project.acceptance_id
       join public.quote_request_quotation_issuances issuance on issuance.id = acceptance.issuance_id
       join public.quote_request_quotation_approvals approval on approval.id = issuance.approval_id
       where approval.quote_request_id = p_quote_request_id
     )
     or exists (
       select 1
       from public.payment_reconciliations reconciliation
       join public.commercial_projects project on project.project_id = reconciliation.project_id
       join public.quote_request_quotation_acceptances acceptance on acceptance.id = project.acceptance_id
       join public.quote_request_quotation_issuances issuance on issuance.id = acceptance.issuance_id
       join public.quote_request_quotation_approvals approval on approval.id = issuance.approval_id
       where approval.quote_request_id = p_quote_request_id
     ) then
    raise exception using errcode = '55000', message = 'LEGACY_TEST_CLEANUP_PAYMENT_BLOCKER_PRESENT';
  end if;

  if exists (
       select 1
       from public.commercial_documents document
       join public.commercial_projects project on project.project_id = document.project_id
       join public.quote_request_quotation_acceptances acceptance on acceptance.id = project.acceptance_id
       join public.quote_request_quotation_issuances issuance on issuance.id = acceptance.issuance_id
       join public.quote_request_quotation_approvals approval on approval.id = issuance.approval_id
       where approval.quote_request_id = p_quote_request_id
     )
     or exists (
       select 1
       from public.quote_request_quotation_artifacts artifact
       join public.quote_request_quotation_issuances issuance on issuance.id = artifact.issuance_id
       join public.quote_request_quotation_approvals approval on approval.id = issuance.approval_id
       where approval.quote_request_id = p_quote_request_id
     ) then
    raise exception using errcode = '55000', message = 'LEGACY_TEST_CLEANUP_DOCUMENT_BLOCKER_PRESENT';
  end if;

  if exists (select 1 from public.sdf_projects where quote_request_id = p_quote_request_id)
     or exists (select 1 from public.sdf_quotations where quote_request_id = p_quote_request_id)
     or exists (select 1 from public.sdf_accepted_commercial_terms where quote_request_id = p_quote_request_id)
     or exists (
       select 1
       from public.sdf_quotation_documents document
       join public.sdf_quotations quotation on quotation.quotation_id = document.quotation_id
       where quotation.quote_request_id = p_quote_request_id
     )
     or exists (
       select 1
       from public.sdf_quotation_acceptances acceptance
       join public.sdf_quotations quotation on quotation.quotation_id = acceptance.quotation_id
       where quotation.quote_request_id = p_quote_request_id
     )
     or exists (select 1 from public.sdf_m1_invoice_candidates where quote_request_id = p_quote_request_id)
     or exists (
       select 1
       from public.sdf_m1_invoice_issuances issuance
       join public.sdf_m1_invoice_candidates candidate on candidate.candidate_id = issuance.candidate_id
       where candidate.quote_request_id = p_quote_request_id
     ) then
    raise exception using errcode = '55000', message = 'LEGACY_TEST_CLEANUP_SDF_BLOCKER_PRESENT';
  end if;
end;
$$;

revoke all on function lws_internal.assert_legacy_test_cleanup_candidate_v1(uuid)
from public, anon, authenticated, service_role;

do $$
declare
  v_quote_request_id uuid;
begin
  if (select count(*) from lws_internal.legacy_test_cleanup_authorities) <> 11 then
    raise exception using errcode = '23514', message = 'LEGACY_TEST_CLEANUP_AUTHORITY_SEED_COUNT_INVALID';
  end if;

  -- Fresh local resets have no business rows at migration time. Any populated database must match all 11 exactly.
  if exists (select 1 from public.quote_requests) then
    for v_quote_request_id in
      select quote_request_id from lws_internal.legacy_test_cleanup_authorities order by quote_request_id
    loop
      perform lws_internal.assert_legacy_test_cleanup_candidate_v1(v_quote_request_id);
    end loop;
  end if;
end;
$$;

comment on table lws_internal.legacy_test_cleanup_authorities is
  'Migration-owned immutable allowlist for exactly eleven historical test/development dossiers. It is not a production classification and has no FK to the deletable dossier root.';
comment on table lws_internal.legacy_test_cleanup_consumptions is
  'Append-only completion evidence reserved for a future owner-authorized cleanup command. This migration records no consumption.';