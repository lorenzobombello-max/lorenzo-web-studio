create or replace view lws_internal.operator_pending_intakes_v1 as
select
  request.id as quote_request_id,
  intake.id as intake_id,
  request.name,
  request.company as organization,
  request.email,
  request.phone,
  request.request_kind,
  request.website_type,
  intake.created_at as invitation_created_at,
  invitation.sent_at as invitation_sent_at,
  intake.status::text as intake_status,
  public.resolve_quote_request_intake_effective_access_v1(
    intake.access_state,
    intake.access_token_expires_at,
    statement_timestamp()
  ) as effective_access,
  intake.access_token_expires_at,
  intake.lifecycle_revision,
  coalesce(retention.retention_state, 'ACTIVE') as retention_state,
  retention.archived_at,
  retention.revision as retention_revision,
  delete_check.delete_block_reason is null as can_permanently_delete,
  delete_check.delete_block_reason,
  intake.started_at,
  cycle.access_cycle as current_reminder_cycle,
  reminder_1.sent_at as reminder_1_sent_at,
  reminder_2.sent_at as reminder_2_sent_at,
  request.support_reference
from public.quote_request_intakes as intake
join public.quote_requests as request
  on request.id = intake.quote_request_id
 and request.record_classification = 'production'
 and request.request_kind = 'website'
left join public.quote_request_email_jobs as invitation
  on invitation.quote_request_id = request.id
 and invitation.kind = 'intake_invitation'
left join lws_internal.operator_pending_intake_retention as retention
  on retention.intake_id = intake.id
cross join lateral (
  select lws_internal.pending_intake_delete_block_reason_v1(intake.id, request.id) as delete_block_reason
) as delete_check
cross join lateral lws_internal.resolve_intake_reminder_access_cycle_v1(intake.id) as cycle
left join lws_internal.intake_reminder_evidence as reminder_1
  on reminder_1.intake_id = intake.id
 and reminder_1.access_cycle = cycle.access_cycle
 and reminder_1.reminder_phase = 'REMINDER_1'
 and reminder_1.state = 'SENT'
left join lws_internal.intake_reminder_evidence as reminder_2
  on reminder_2.intake_id = intake.id
 and reminder_2.access_cycle = cycle.access_cycle
 and reminder_2.reminder_phase = 'REMINDER_2'
 and reminder_2.state = 'SENT'
where intake.status in ('invited', 'in_progress');

create or replace function public.list_operator_pending_intakes_v1(
  p_actor_auth_user_id uuid,
  p_retention_state text default 'ACTIVE'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_items jsonb;
begin
  perform lws_internal.assert_operator_application_actor_v2(p_actor_auth_user_id);
  if p_retention_state not in ('ACTIVE', 'ARCHIVED') then
    raise exception using errcode = '22023', message = 'INVALID_PENDING_INTAKE_RETENTION_STATE';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'quote_request_id', pending.quote_request_id,
    'intake_id', pending.intake_id,
    'name', pending.name,
    'organization', pending.organization,
    'support_reference', pending.support_reference,
    'email', pending.email,
    'phone', pending.phone,
    'request_kind', pending.request_kind,
    'website_type', pending.website_type,
    'invitation_created_at', pending.invitation_created_at,
    'invitation_sent_at', pending.invitation_sent_at,
    'intake_status', pending.intake_status,
    'effective_access', pending.effective_access,
    'access_token_expires_at', pending.access_token_expires_at,
    'lifecycle_revision', pending.lifecycle_revision,
    'retention_state', pending.retention_state,
    'archived_at', pending.archived_at,
    'retention_revision', coalesce(pending.retention_revision, 0),
    'can_permanently_delete', pending.can_permanently_delete,
    'delete_block_reason', pending.delete_block_reason,
    'started_at', pending.started_at,
    'current_reminder_cycle', pending.current_reminder_cycle,
    'reminder_1_sent_at', pending.reminder_1_sent_at,
    'reminder_2_sent_at', pending.reminder_2_sent_at
  ) order by pending.invitation_created_at desc, pending.quote_request_id desc), '[]'::jsonb)
  into v_items
  from lws_internal.operator_pending_intakes_v1 as pending
  where pending.retention_state = p_retention_state;

  return jsonb_build_object('items', v_items);
end;
$$;