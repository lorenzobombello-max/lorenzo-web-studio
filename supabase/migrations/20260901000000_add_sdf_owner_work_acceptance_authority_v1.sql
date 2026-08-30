create table public.sdf_owner_work_acceptance_authorities (
  authority_id uuid primary key default gen_random_uuid(),
  quote_request_id uuid not null unique references public.quote_requests(id) on delete restrict,
  qualification_intake_id uuid not null unique references public.sdf_qualification_intakes(intake_id) on delete restrict,
  taxonomy_version text not null check (taxonomy_version = 'sdf_qualification_intake/1.0.0'),
  submission_sequence integer not null check (submission_sequence > 0),
  submission_sha256 char(64) not null check (submission_sha256 ~ '^[0-9a-f]{64}$'),
  accepted_intake_status public.sdf_qualification_intake_status not null check (
    accepted_intake_status in ('submitted', 'under_review', 'changes_requested', 'qualification_complete')
  ),
  actor_operator_id uuid not null references public.commercial_operators(operator_id) on delete restrict,
  actor_role text not null check (actor_role = 'owner'),
  accepted_at timestamptz not null default clock_timestamp(),
  idempotency_key uuid not null unique,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$')
);

comment on table public.sdf_owner_work_acceptance_authorities is
  'Private immutable Owner authority accepting one submitted SDF qualification into active work. It does not mutate qualification, quotation, project, invoice, or payment state.';

create trigger trg_sdf_owner_work_acceptance_authorities_immutable
before update or delete on public.sdf_owner_work_acceptance_authorities
for each row execute function lws_internal.reject_sdf_qualification_history_mutation_v1();

alter table public.sdf_owner_work_acceptance_authorities enable row level security;
alter table public.sdf_owner_work_acceptance_authorities force row level security;

revoke all privileges on table public.sdf_owner_work_acceptance_authorities
from public, anon, authenticated, service_role;

create function public.accept_sdf_for_active_work_v1(
  p_quote_request_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql volatile security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_request public.quote_requests%rowtype;
  v_intake public.sdf_qualification_intakes%rowtype;
  v_submission public.sdf_qualification_intake_submissions%rowtype;
  v_existing public.sdf_owner_work_acceptance_authorities%rowtype;
  v_fingerprint char(64);
begin
  v_operator := lws_internal.assert_sdf_owner_v1();
  if p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text, 0));
  select * into v_request
  from public.quote_requests
  where id = p_quote_request_id
  for update;

  if not found or v_request.request_kind <> 'slimme_documentenflow' then
    raise exception using errcode = '23514', message = 'SDF_REQUEST_KIND_REQUIRED';
  end if;
  if v_request.status = 'rejected'
     or exists (
       select 1
       from lws_internal.operator_dossier_states
       where quote_request_id = p_quote_request_id and state = 'TRASHED'
     ) then
    raise exception using errcode = '55000', message = 'SDF_WORK_ACCEPTANCE_NOT_ELIGIBLE';
  end if;

  select * into v_intake
  from public.sdf_qualification_intakes
  where quote_request_id = p_quote_request_id
  for update;

  if not found or v_intake.status not in ('submitted', 'under_review', 'changes_requested', 'qualification_complete') then
    raise exception using errcode = '55000', message = 'SDF_WORK_ACCEPTANCE_NOT_ELIGIBLE';
  end if;

  select * into strict v_submission
  from public.sdf_qualification_intake_submissions
  where intake_id = v_intake.intake_id
    and submission_sequence = v_intake.latest_submission_sequence;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'v', 1,
    'request', p_quote_request_id,
    'intake', v_intake.intake_id,
    'taxonomy', v_intake.taxonomy_version,
    'submission_sequence', v_submission.submission_sequence,
    'submission_sha256', v_submission.payload_sha256
  )::text, 'UTF8'), 'sha256'), 'hex');

  select * into v_existing
  from public.sdf_owner_work_acceptance_authorities
  where idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'authority_id', v_existing.authority_id,
      'quote_request_id', v_existing.quote_request_id,
      'status', 'ACCEPTED_FOR_ACTIVE_WORK',
      'replayed', true
    );
  end if;

  if exists (
    select 1 from public.sdf_owner_work_acceptance_authorities
    where quote_request_id = p_quote_request_id
  ) then
    raise exception using errcode = '55000', message = 'SDF_WORK_ALREADY_ACCEPTED';
  end if;

  insert into public.sdf_owner_work_acceptance_authorities (
    quote_request_id,
    qualification_intake_id,
    taxonomy_version,
    submission_sequence,
    submission_sha256,
    accepted_intake_status,
    actor_operator_id,
    actor_role,
    idempotency_key,
    request_fingerprint
  ) values (
    p_quote_request_id,
    v_intake.intake_id,
    v_intake.taxonomy_version,
    v_submission.submission_sequence,
    v_submission.payload_sha256,
    v_intake.status,
    v_operator.operator_id,
    'owner',
    p_idempotency_key,
    v_fingerprint
  ) returning * into v_existing;

  return jsonb_build_object(
    'authority_id', v_existing.authority_id,
    'quote_request_id', v_existing.quote_request_id,
    'status', 'ACCEPTED_FOR_ACTIVE_WORK',
    'replayed', false
  );
end;
$$;

revoke all on function public.accept_sdf_for_active_work_v1(uuid, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.accept_sdf_for_active_work_v1(uuid, uuid) to authenticated;

create or replace view lws_internal.operator_application_readmodel_v2 as
select request.id quote_request_id,request.application_reference,request.support_reference,request.name,request.company organization,request.request_kind,dossier_state.state zone,lws_internal.resolve_operator_operational_status_v2(request.request_kind,intake.status::text,public.resolve_quote_request_intake_effective_access_v1(intake.access_state,intake.access_token_expires_at,statement_timestamp()),project.current_state,acceptance.id is not null) operational_status,intake.submitted_at dossier_date
from public.quote_request_intakes intake join public.quote_requests request on request.id=intake.quote_request_id and request.record_classification='production' and request.request_kind='website' join lws_internal.operator_dossier_states dossier_state on dossier_state.quote_request_id=request.id
left join lateral(select accepted.id from public.quote_request_quotation_approvals approval join public.quote_request_quotation_issuances issuance on issuance.approval_id=approval.id join public.quote_request_quotation_acceptances accepted on accepted.issuance_id=issuance.id where approval.quote_request_id=request.id order by accepted.accepted_at desc limit 1) acceptance on true
left join public.commercial_projects project on project.acceptance_id=acceptance.id where intake.status in ('submitted','reviewed') and intake.submitted_at is not null
union all
select request.id,request.application_reference,request.support_reference,request.name,request.company,request.request_kind,dossier_state.state,lws_internal.resolve_operator_operational_status_v2(request.request_kind,intake.status::text,null,null,quotation_acceptance.quotation_id is not null),coalesce(intake.submitted_at,intake.updated_at)
from public.sdf_owner_work_acceptance_authorities work_acceptance join public.sdf_qualification_intakes intake on intake.intake_id=work_acceptance.qualification_intake_id join public.quote_requests request on request.id=work_acceptance.quote_request_id and request.record_classification='production' and request.request_kind='slimme_documentenflow' join lws_internal.operator_dossier_states dossier_state on dossier_state.quote_request_id=request.id left join public.sdf_quotations quotation on quotation.quote_request_id=request.id left join public.sdf_quotation_acceptances quotation_acceptance on quotation_acceptance.quotation_id=quotation.quotation_id;

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
  and intake.status in ('invited','in_progress','submitted','under_review','changes_requested','qualification_complete')
  and not exists (
    select 1
    from public.sdf_owner_work_acceptance_authorities work_acceptance
    where work_acceptance.quote_request_id=request.id
  );

comment on function public.accept_sdf_for_active_work_v1(uuid, uuid) is
  'Owner-only idempotent command that records canonical SDF active-work acceptance without changing qualification or commercial state.';
