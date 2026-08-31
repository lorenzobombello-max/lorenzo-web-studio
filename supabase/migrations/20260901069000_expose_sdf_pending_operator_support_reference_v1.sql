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
  greatest(intake.updated_at,coalesce(invitation.updated_at,intake.updated_at)) as last_activity_at,
  request.support_reference
from public.sdf_qualification_intakes intake
join public.quote_requests request on request.id=intake.quote_request_id
left join public.sdf_qualification_intake_email_jobs invitation
  on invitation.intake_id=intake.intake_id and invitation.kind='invitation' and invitation.invitation_generation=intake.invitation_generation
where request.record_classification='production'
  and request.request_kind='slimme_documentenflow'
  and intake.status in ('invited','in_progress');