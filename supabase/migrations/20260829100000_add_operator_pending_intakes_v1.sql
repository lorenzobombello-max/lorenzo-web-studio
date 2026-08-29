create view lws_internal.operator_pending_intakes_v1 as
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
  intake.lifecycle_revision
from public.quote_request_intakes as intake
join public.quote_requests as request
  on request.id = intake.quote_request_id
 and request.record_classification = 'production'
 and request.request_kind = 'website'
left join public.quote_request_email_jobs as invitation
  on invitation.quote_request_id = request.id
 and invitation.kind = 'intake_invitation'
where intake.status in ('invited', 'in_progress');

create function public.list_operator_pending_intakes_v1(
  p_actor_auth_user_id uuid
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

  select coalesce(jsonb_agg(jsonb_build_object(
    'quote_request_id', pending.quote_request_id,
    'intake_id', pending.intake_id,
    'name', pending.name,
    'organization', pending.organization,
    'email', pending.email,
    'phone', pending.phone,
    'request_kind', pending.request_kind,
    'website_type', pending.website_type,
    'invitation_created_at', pending.invitation_created_at,
    'invitation_sent_at', pending.invitation_sent_at,
    'intake_status', pending.intake_status,
    'effective_access', pending.effective_access,
    'access_token_expires_at', pending.access_token_expires_at,
    'lifecycle_revision', pending.lifecycle_revision
  ) order by pending.invitation_created_at desc, pending.quote_request_id desc), '[]'::jsonb)
  into v_items
  from lws_internal.operator_pending_intakes_v1 as pending;

  return jsonb_build_object('items', v_items);
end;
$$;

create index quote_request_intakes_pending_created_root_idx
  on public.quote_request_intakes (created_at desc, quote_request_id desc)
  where status in ('invited', 'in_progress');

revoke all on table lws_internal.operator_pending_intakes_v1
from public, anon, authenticated, service_role;

revoke all on function public.list_operator_pending_intakes_v1(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.list_operator_pending_intakes_v1(uuid)
to service_role;

comment on view lws_internal.operator_pending_intakes_v1 is
  'Private pre-submission intake readmodel. It contains invited and in-progress production Website intakes only and exposes no capability material.';

comment on function public.list_operator_pending_intakes_v1(uuid) is
  'Service-role-only pending-intake transport that revalidates the supplied ACTIVE owner/admin identity.';