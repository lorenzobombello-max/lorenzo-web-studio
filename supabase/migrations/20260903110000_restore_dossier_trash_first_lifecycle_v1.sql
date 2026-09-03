create or replace function lws_internal.enforce_dossier_trash_before_purge_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if (current_setting('lws.dossier_purge_authority', true) = 'on'
      or current_setting('lws.sdf_dossier_purge_authority', true) = 'on')
     and old.state <> 'TRASHED' then
    raise exception using errcode = '55000', message = 'DOSSIER_NOT_TRASHED';
  end if;
  return old;
end;
$$;

revoke all on function lws_internal.enforce_dossier_trash_before_purge_v1()
from public, anon, authenticated, service_role;

drop trigger if exists trg_enforce_dossier_trash_before_purge_v1
on lws_internal.operator_dossier_states;
create trigger trg_enforce_dossier_trash_before_purge_v1
before delete on lws_internal.operator_dossier_states
for each row execute function lws_internal.enforce_dossier_trash_before_purge_v1();

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
  if v_state.state <> 'TRASHED' then
    return jsonb_build_object('can_purge', false, 'reason', 'DOSSIER_NOT_TRASHED');
  end if;

  v_reason := lws_internal.sdf_dossier_purge_block_reason_v1(p_quote_request_id);
  return jsonb_build_object('can_purge', v_reason is null, 'reason', v_reason);
end;
$$;

create or replace view lws_internal.operator_application_readmodel_v2 as
select
  request.id as quote_request_id,
  request.application_reference,
  request.support_reference,
  request.name,
  request.company as organization,
  request.request_kind,
  dossier_state.state as zone,
  lws_internal.resolve_operator_operational_status_v2(
    request.request_kind,
    intake.status::text,
    public.resolve_quote_request_intake_effective_access_v1(
      intake.access_state,
      intake.access_token_expires_at,
      statement_timestamp()
    ),
    project.current_state,
    acceptance.id is not null
  ) as operational_status,
  intake.submitted_at as dossier_date
from public.quote_request_intakes as intake
join public.quote_requests as request
  on request.id = intake.quote_request_id
 and request.record_classification = 'production'
 and request.request_kind = 'website'
join lws_internal.operator_dossier_states as dossier_state
  on dossier_state.quote_request_id = request.id
left join lateral (
  select accepted.id
  from public.quote_request_quotation_approvals as approval
  join public.quote_request_quotation_issuances as issuance
    on issuance.approval_id = approval.id
  join public.quote_request_quotation_acceptances as accepted
    on accepted.issuance_id = issuance.id
  where approval.quote_request_id = request.id
  order by accepted.accepted_at desc
  limit 1
) as acceptance on true
left join public.commercial_projects as project
  on project.acceptance_id = acceptance.id
where intake.status in ('submitted', 'reviewed')
  and intake.submitted_at is not null
union all
select
  request.id,
  request.application_reference,
  request.support_reference,
  request.name,
  request.company,
  request.request_kind,
  dossier_state.state,
  upper(intake.status::text),
  coalesce(intake.started_at, intake.created_at)
from public.quote_request_intakes as intake
join public.quote_requests as request
  on request.id = intake.quote_request_id
 and request.record_classification = 'production'
 and request.request_kind = 'website'
join lws_internal.operator_dossier_states as dossier_state
  on dossier_state.quote_request_id = request.id
where intake.status in ('invited', 'in_progress')
  and dossier_state.state = 'TRASHED'
union all
select
  request.id,
  request.application_reference,
  request.support_reference,
  request.name,
  request.company,
  request.request_kind,
  dossier_state.state,
  lws_internal.resolve_operator_operational_status_v2(
    request.request_kind,
    intake.status::text,
    null,
    null,
    quotation_acceptance.quotation_id is not null
  ),
  coalesce(intake.submitted_at, intake.updated_at)
from public.sdf_qualification_intakes as intake
join public.quote_requests as request
  on request.id = intake.quote_request_id
 and request.record_classification = 'production'
 and request.request_kind = 'slimme_documentenflow'
join lws_internal.operator_dossier_states as dossier_state
  on dossier_state.quote_request_id = request.id
left join public.sdf_quotations as quotation
  on quotation.quote_request_id = request.id
left join public.sdf_quotation_acceptances as quotation_acceptance
  on quotation_acceptance.quotation_id = quotation.quotation_id
where intake.status in ('submitted', 'under_review', 'changes_requested', 'qualification_complete')
union all
select
  request.id,
  request.application_reference,
  request.support_reference,
  request.name,
  request.company,
  request.request_kind,
  dossier_state.state,
  upper(intake.status::text),
  coalesce(intake.invited_at, intake.created_at)
from public.sdf_qualification_intakes as intake
join public.quote_requests as request
  on request.id = intake.quote_request_id
 and request.record_classification = 'production'
 and request.request_kind = 'slimme_documentenflow'
join lws_internal.operator_dossier_states as dossier_state
  on dossier_state.quote_request_id = request.id
where intake.status in ('invited', 'in_progress')
  and dossier_state.state = 'TRASHED';

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
  request.support_reference,
  dossier_state.state as dossier_state,
  dossier_state.revision as dossier_revision
from public.quote_request_intakes as intake
join public.quote_requests as request
  on request.id = intake.quote_request_id
 and request.record_classification = 'production'
 and request.request_kind = 'website'
join lws_internal.operator_dossier_states as dossier_state
  on dossier_state.quote_request_id = request.id
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
where intake.status in ('invited', 'in_progress')
  and dossier_state.state <> 'TRASHED';

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
    'reminder_2_sent_at', pending.reminder_2_sent_at,
    'dossier_state', pending.dossier_state,
    'dossier_revision', pending.dossier_revision
  ) order by pending.invitation_created_at desc, pending.quote_request_id desc), '[]'::jsonb)
  into v_items
  from lws_internal.operator_pending_intakes_v1 as pending
  where pending.retention_state = p_retention_state;

  return jsonb_build_object('items', v_items);
end;
$$;

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
  'Slimme documentenflow - ' || request.sdf_package as website_type,
  intake.invited_at as invitation_created_at,
  invitation.sent_at as invitation_sent_at,
  invitation.status::text as invitation_delivery_status,
  intake.status::text as intake_status,
  case when intake.customer_capability_expires_at <= clock_timestamp() then 'EXPIRED' else 'ACTIVE' end as effective_access,
  intake.customer_capability_expires_at as access_token_expires_at,
  intake.draft_revision as lifecycle_revision,
  'ACTIVE'::text as retention_state,
  null::timestamptz as archived_at,
  0::bigint as retention_revision,
  false as can_permanently_delete,
  null::text as delete_block_reason,
  case when intake.status = 'in_progress' then intake.updated_at else null end as started_at,
  0 as current_reminder_cycle,
  null::timestamptz as reminder_1_sent_at,
  null::timestamptz as reminder_2_sent_at,
  greatest(intake.updated_at, coalesce(invitation.updated_at, intake.updated_at)) as last_activity_at,
  request.support_reference,
  dossier_state.state as dossier_state,
  dossier_state.revision as dossier_revision
from public.sdf_qualification_intakes as intake
join public.quote_requests as request
  on request.id = intake.quote_request_id
join lws_internal.operator_dossier_states as dossier_state
  on dossier_state.quote_request_id = request.id
left join public.sdf_qualification_intake_email_jobs as invitation
  on invitation.intake_id = intake.intake_id
 and invitation.kind = 'invitation'
 and invitation.invitation_generation = intake.invitation_generation
where request.record_classification = 'production'
  and request.request_kind = 'slimme_documentenflow'
  and intake.status in ('invited', 'in_progress')
  and dossier_state.state <> 'TRASHED';

comment on function lws_internal.enforce_dossier_trash_before_purge_v1() is
  'Fail-closed hard-delete guard: dossier roots can be purged only after the canonical state entered TRASHED.';
comment on view lws_internal.operator_application_readmodel_v2 is
  'Operator dossier zones including pending Website and SDF applications only when their canonical dossier state is TRASHED.';