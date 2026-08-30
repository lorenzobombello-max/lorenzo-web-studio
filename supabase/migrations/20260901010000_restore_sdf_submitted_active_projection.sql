do $$
begin
  if exists (select 1 from public.sdf_owner_work_acceptance_authorities) then
    raise exception using
      errcode = '55000',
      message = 'SDF_WORK_ACCEPTANCE_AUTHORITY_NOT_EMPTY';
  end if;
end;
$$;

create or replace view lws_internal.operator_application_readmodel_v2 as
select request.id quote_request_id,request.application_reference,request.support_reference,request.name,request.company organization,request.request_kind,dossier_state.state zone,lws_internal.resolve_operator_operational_status_v2(request.request_kind,intake.status::text,public.resolve_quote_request_intake_effective_access_v1(intake.access_state,intake.access_token_expires_at,statement_timestamp()),project.current_state,acceptance.id is not null) operational_status,intake.submitted_at dossier_date
from public.quote_request_intakes intake join public.quote_requests request on request.id=intake.quote_request_id and request.record_classification='production' and request.request_kind='website' join lws_internal.operator_dossier_states dossier_state on dossier_state.quote_request_id=request.id
left join lateral(select accepted.id from public.quote_request_quotation_approvals approval join public.quote_request_quotation_issuances issuance on issuance.approval_id=approval.id join public.quote_request_quotation_acceptances accepted on accepted.issuance_id=issuance.id where approval.quote_request_id=request.id order by accepted.accepted_at desc limit 1) acceptance on true
left join public.commercial_projects project on project.acceptance_id=acceptance.id where intake.status in ('submitted','reviewed') and intake.submitted_at is not null
union all
select request.id,request.application_reference,request.support_reference,request.name,request.company,request.request_kind,dossier_state.state,lws_internal.resolve_operator_operational_status_v2(request.request_kind,intake.status::text,null,null,quotation_acceptance.quotation_id is not null),coalesce(intake.submitted_at,intake.updated_at)
from public.sdf_qualification_intakes intake join public.quote_requests request on request.id=intake.quote_request_id and request.record_classification='production' and request.request_kind='slimme_documentenflow' join lws_internal.operator_dossier_states dossier_state on dossier_state.quote_request_id=request.id left join public.sdf_quotations quotation on quotation.quote_request_id=request.id left join public.sdf_quotation_acceptances quotation_acceptance on quotation_acceptance.quotation_id=quotation.quotation_id where intake.status in ('submitted','under_review','changes_requested','qualification_complete');

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
  and intake.status in ('invited','in_progress');

drop function public.accept_sdf_for_active_work_v1(uuid, uuid);

drop trigger trg_sdf_owner_work_acceptance_authorities_immutable
on public.sdf_owner_work_acceptance_authorities;

drop table public.sdf_owner_work_acceptance_authorities;
