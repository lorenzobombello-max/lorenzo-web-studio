create table lws_internal.operator_pending_intake_retention (
  intake_id uuid primary key
    references lws_internal.intake_identity_anchors(intake_id) on delete restrict,
  retention_state text not null default 'ACTIVE'
    check (retention_state in ('ACTIVE', 'ARCHIVED')),
  archived_at timestamptz,
  archived_by_operator_id uuid
    references public.commercial_operators(operator_id) on delete restrict,
  revision bigint not null default 0 check (revision >= 0),
  updated_at timestamptz not null default clock_timestamp(),
  constraint operator_pending_intake_retention_archive_evidence check (
    (retention_state = 'ACTIVE' and archived_at is null and archived_by_operator_id is null)
    or
    (retention_state = 'ARCHIVED' and archived_at is not null and archived_by_operator_id is not null)
  )
);

create table lws_internal.operator_pending_intake_retention_events (
  event_id uuid primary key default gen_random_uuid(),
  intake_id uuid not null
    references lws_internal.intake_identity_anchors(intake_id) on delete restrict,
  event_type text not null check (event_type in ('ARCHIVED', 'RESTORED')),
  previous_state text not null check (previous_state in ('ACTIVE', 'ARCHIVED')),
  new_state text not null check (new_state in ('ACTIVE', 'ARCHIVED')),
  actor_operator_id uuid not null
    references public.commercial_operators(operator_id) on delete restrict,
  reason text not null check (char_length(btrim(reason)) between 1 and 500),
  idempotency_key uuid not null,
  occurred_at timestamptz not null default clock_timestamp(),
  constraint operator_pending_intake_retention_events_transition check (
    (event_type = 'ARCHIVED' and previous_state = 'ACTIVE' and new_state = 'ARCHIVED')
    or
    (event_type = 'RESTORED' and previous_state = 'ARCHIVED' and new_state = 'ACTIVE')
  ),
  unique (intake_id, idempotency_key)
);

create table lws_internal.pending_intake_purge_tombstones (
  intake_id uuid primary key
    references lws_internal.intake_identity_anchors(intake_id) on delete restrict,
  quote_request_id uuid not null
    references lws_internal.dossier_identity_anchors(quote_request_id) on delete restrict,
  purged_at timestamptz not null,
  purged_by_operator_id uuid not null
    references public.commercial_operators(operator_id) on delete restrict,
  purge_reason text not null check (char_length(btrim(purge_reason)) between 1 and 500),
  original_intake_status text not null check (original_intake_status in ('invited', 'in_progress')),
  original_retention_state text not null check (original_retention_state in ('ACTIVE', 'ARCHIVED')),
  idempotency_key uuid not null unique,
  request_fingerprint text not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  unique (quote_request_id)
);

create function lws_internal.prevent_pending_intake_workspace_audit_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'PENDING_INTAKE_WORKSPACE_AUDIT_IMMUTABLE';
end;
$$;

create trigger trg_operator_pending_intake_retention_events_immutable
before update or delete on lws_internal.operator_pending_intake_retention_events
for each row execute function lws_internal.prevent_pending_intake_workspace_audit_mutation_v1();

create trigger trg_pending_intake_purge_tombstones_immutable
before update or delete on lws_internal.pending_intake_purge_tombstones
for each row execute function lws_internal.prevent_pending_intake_workspace_audit_mutation_v1();

alter table lws_internal.operator_pending_intake_retention enable row level security;
alter table lws_internal.operator_pending_intake_retention force row level security;
alter table lws_internal.operator_pending_intake_retention_events enable row level security;
alter table lws_internal.operator_pending_intake_retention_events force row level security;
alter table lws_internal.pending_intake_purge_tombstones enable row level security;
alter table lws_internal.pending_intake_purge_tombstones force row level security;

revoke all on table
  lws_internal.operator_pending_intake_retention,
  lws_internal.operator_pending_intake_retention_events,
  lws_internal.pending_intake_purge_tombstones
from public, anon, authenticated, service_role;

create function lws_internal.pending_intake_delete_block_reason_v1(
  p_intake_id uuid,
  p_quote_request_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_status text;
  v_application_reference text;
begin
  select intake.status::text, request.application_reference
  into v_status, v_application_reference
  from public.quote_request_intakes as intake
  join public.quote_requests as request on request.id = intake.quote_request_id
  where intake.id = p_intake_id
    and intake.quote_request_id = p_quote_request_id;

  if not found then return 'NOT_FOUND'; end if;
  if v_status not in ('invited', 'in_progress') then return 'INTAKE_SUBMITTED'; end if;
  if v_application_reference is not null then return 'COMMERCIAL_FOLLOW_UP_EXISTS'; end if;
    if exists (select 1 from public.quote_request_quotation_approval_drafts where quote_request_id = p_quote_request_id)
      or exists (select 1 from public.quote_request_quotation_business_drafts where quote_request_id = p_quote_request_id)
      or exists (select 1 from public.quote_request_quotation_approvals where quote_request_id = p_quote_request_id) then return 'QUOTATION_EXISTS'; end if;
  if exists (select 1 from public.sdf_projects where quote_request_id = p_quote_request_id)
     or exists (select 1 from public.sdf_quotations where quote_request_id = p_quote_request_id) then return 'PROJECT_EXISTS'; end if;
  if exists (select 1 from public.sdf_m1_invoice_candidates where quote_request_id = p_quote_request_id) then return 'INVOICE_EXISTS'; end if;
  if exists (select 1 from public.customer_requests where quote_request_id = p_quote_request_id) then return 'CUSTOMER_REQUEST_EXISTS'; end if;
  if exists (select 1 from public.quotation_vat_transaction_classifications where quote_request_id = p_quote_request_id) then return 'FINANCIAL_DEPENDENCY_EXISTS'; end if;
  return null;
end;
$$;

create function public.can_permanently_delete_pending_intake_v1(
  p_actor_auth_user_id uuid,
  p_intake_id uuid,
  p_quote_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_reason text;
begin
  perform lws_internal.assert_operator_application_actor_v2(p_actor_auth_user_id);
  if p_intake_id is null or p_quote_request_id is null then
    raise exception using errcode = '22023', message = 'INVALID_PENDING_INTAKE_DELETE_REQUEST';
  end if;
  v_reason := lws_internal.pending_intake_delete_block_reason_v1(p_intake_id, p_quote_request_id);
  return jsonb_build_object(
    'can_permanently_delete', v_reason is null,
    'delete_block_reason', v_reason
  );
end;
$$;

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
  delete_check.delete_block_reason
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
    'delete_block_reason', pending.delete_block_reason
  ) order by pending.invitation_created_at desc, pending.quote_request_id desc), '[]'::jsonb)
  into v_items
  from lws_internal.operator_pending_intakes_v1 as pending
  where pending.retention_state = p_retention_state;

  return jsonb_build_object('items', v_items);
end;
$$;

create function public.count_operator_active_pending_intakes_v1(
  p_actor_auth_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = lws_internal, public, pg_catalog
as $$
declare
  v_count bigint;
begin
  perform lws_internal.assert_operator_application_actor_v2(p_actor_auth_user_id);
  select count(*) into v_count
  from lws_internal.operator_pending_intakes_v1
  where retention_state = 'ACTIVE';
  return jsonb_build_object('active_count', v_count);
end;
$$;

create function public.execute_operator_pending_intake_retention_v1(
  p_actor_auth_user_id uuid,
  p_intake_id uuid,
  p_event_type text,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, lws_internal, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_retention lws_internal.operator_pending_intake_retention%rowtype;
  v_existing lws_internal.operator_pending_intake_retention_events%rowtype;
  v_previous_state text;
  v_new_state text;
  v_now timestamptz := clock_timestamp();
begin
  perform lws_internal.assert_operator_application_actor_v2(p_actor_auth_user_id);
  select * into strict v_operator from public.commercial_operators where auth_user_id = p_actor_auth_user_id;
  if p_event_type not in ('ARCHIVED', 'RESTORED') or p_intake_id is null or p_idempotency_key is null
     or p_expected_revision is null or p_expected_revision < 0
     or p_reason is null or char_length(btrim(p_reason)) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'INVALID_PENDING_INTAKE_RETENTION_REQUEST';
  end if;

  select * into v_existing
  from lws_internal.operator_pending_intake_retention_events
  where intake_id = p_intake_id and idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('intake_id', p_intake_id, 'retention_state', v_existing.new_state, 'revision', p_expected_revision + 1);
  end if;

  select * into v_intake from public.quote_request_intakes where id = p_intake_id for update;
  if not found then raise exception using errcode = 'P0001', message = 'PENDING_INTAKE_NOT_FOUND'; end if;
  if v_intake.status::text not in ('invited', 'in_progress') then raise exception using errcode = '55000', message = 'PENDING_INTAKE_REQUIRED'; end if;

  insert into lws_internal.operator_pending_intake_retention (intake_id)
  values (p_intake_id)
  on conflict (intake_id) do nothing;
  select * into strict v_retention
  from lws_internal.operator_pending_intake_retention
  where intake_id = p_intake_id for update;

  if v_retention.revision <> p_expected_revision then raise exception using errcode = '40001', message = 'STALE_PENDING_INTAKE_RETENTION_REVISION'; end if;
  v_previous_state := v_retention.retention_state;
  v_new_state := case p_event_type when 'ARCHIVED' then 'ARCHIVED' else 'ACTIVE' end;
  if (v_previous_state, v_new_state) not in (('ACTIVE', 'ARCHIVED'), ('ARCHIVED', 'ACTIVE')) then
    raise exception using errcode = '55000', message = 'INVALID_PENDING_INTAKE_RETENTION_TRANSITION';
  end if;

  update lws_internal.operator_pending_intake_retention
  set retention_state = v_new_state,
      archived_at = case when v_new_state = 'ARCHIVED' then v_now else null end,
      archived_by_operator_id = case when v_new_state = 'ARCHIVED' then v_operator.operator_id else null end,
      revision = revision + 1,
      updated_at = v_now
  where intake_id = p_intake_id
  returning * into v_retention;

  insert into lws_internal.operator_pending_intake_retention_events (
    intake_id, event_type, previous_state, new_state, actor_operator_id,
    reason, idempotency_key, occurred_at
  ) values (
    p_intake_id, p_event_type, v_previous_state, v_new_state, v_operator.operator_id,
    btrim(p_reason), p_idempotency_key, v_now
  );

  return jsonb_build_object('intake_id', p_intake_id, 'retention_state', v_new_state, 'revision', v_retention.revision);
end;
$$;

create function public.permanently_delete_pending_intake_v1(
  p_actor_auth_user_id uuid,
  p_intake_id uuid,
  p_quote_request_id uuid,
  p_idempotency_key uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_intake public.quote_request_intakes%rowtype;
  v_request public.quote_requests%rowtype;
  v_retention_state text;
  v_block_reason text;
  v_now timestamptz := clock_timestamp();
  v_fingerprint text;
begin
  perform lws_internal.assert_operator_application_actor_v2(p_actor_auth_user_id);
  select * into strict v_operator from public.commercial_operators where auth_user_id = p_actor_auth_user_id;
  if p_intake_id is null or p_quote_request_id is null or p_idempotency_key is null
     or p_reason is null or char_length(btrim(p_reason)) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'INVALID_PENDING_INTAKE_DELETE_REQUEST';
  end if;
  if exists (select 1 from lws_internal.pending_intake_purge_tombstones where idempotency_key = p_idempotency_key) then
    return jsonb_build_object('outcome', 'already_deleted', 'intake_id', p_intake_id, 'quote_request_id', p_quote_request_id);
  end if;

  select * into v_request from public.quote_requests where id = p_quote_request_id for update;
  if not found then raise exception using errcode = 'P0001', message = 'PENDING_INTAKE_NOT_FOUND'; end if;
  select * into v_intake from public.quote_request_intakes
  where id = p_intake_id and quote_request_id = p_quote_request_id for update;
  if not found then raise exception using errcode = 'P0001', message = 'PENDING_INTAKE_NOT_FOUND'; end if;

  perform pg_advisory_xact_lock(hashtextextended('DOSSIER:' || p_quote_request_id::text, 0));
  v_block_reason := lws_internal.pending_intake_delete_block_reason_v1(p_intake_id, p_quote_request_id);
  if v_block_reason is not null then
    raise exception using errcode = '55000', message = 'PENDING_INTAKE_DELETE_BLOCKED', detail = v_block_reason;
  end if;

  select coalesce(retention_state, 'ACTIVE') into v_retention_state
  from lws_internal.operator_pending_intake_retention where intake_id = p_intake_id;
  v_retention_state := coalesce(v_retention_state, 'ACTIVE');
  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'actor', p_actor_auth_user_id,
    'intake_id', p_intake_id,
    'quote_request_id', p_quote_request_id,
    'reason', btrim(p_reason)
  )::text, 'UTF8'), 'sha256'), 'hex');

  insert into lws_internal.pending_intake_purge_tombstones (
    intake_id, quote_request_id, purged_at, purged_by_operator_id, purge_reason,
    original_intake_status, original_retention_state, idempotency_key, request_fingerprint
  ) values (
    p_intake_id, p_quote_request_id, v_now, v_operator.operator_id, btrim(p_reason),
    v_intake.status::text, v_retention_state, p_idempotency_key, v_fingerprint
  );

  delete from lws_internal.operator_pending_intake_retention where intake_id = p_intake_id;
  delete from public.quote_request_email_jobs where quote_request_id = p_quote_request_id;
  delete from lws_internal.application_intake_automation_work where quote_request_id = p_quote_request_id;
  delete from public.quote_request_pricing_snapshot_integrity where snapshot_id in (
    select id from public.quote_request_pricing_snapshots where intake_id = p_intake_id
  );
  delete from public.quote_request_pricing_snapshots where intake_id = p_intake_id;
  delete from public.quote_request_intakes where id = p_intake_id;
  delete from public.quote_requests where id = p_quote_request_id;

  return jsonb_build_object('outcome', 'deleted', 'intake_id', p_intake_id, 'quote_request_id', p_quote_request_id);
end;
$$;

revoke all on function lws_internal.prevent_pending_intake_workspace_audit_mutation_v1() from public, anon, authenticated, service_role;
revoke all on function lws_internal.pending_intake_delete_block_reason_v1(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.can_permanently_delete_pending_intake_v1(uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.list_operator_pending_intakes_v1(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.count_operator_active_pending_intakes_v1(uuid) from public, anon, authenticated, service_role;
revoke all on function public.execute_operator_pending_intake_retention_v1(uuid, uuid, text, bigint, uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.permanently_delete_pending_intake_v1(uuid, uuid, uuid, uuid, text) from public, anon, authenticated, service_role;

grant execute on function public.can_permanently_delete_pending_intake_v1(uuid, uuid, uuid) to service_role;
grant execute on function public.list_operator_pending_intakes_v1(uuid, text) to service_role;
grant execute on function public.count_operator_active_pending_intakes_v1(uuid) to service_role;
grant execute on function public.execute_operator_pending_intake_retention_v1(uuid, uuid, text, bigint, uuid, text) to service_role;
grant execute on function public.permanently_delete_pending_intake_v1(uuid, uuid, uuid, uuid, text) to service_role;

comment on table lws_internal.operator_pending_intake_retention is
  'Operator workspace retention, independent from intake business lifecycle.';
comment on function public.permanently_delete_pending_intake_v1(uuid, uuid, uuid, uuid, text) is
  'Owner/admin pending-intake cleanup authority. Locks and rechecks all repository-backed protected dependencies before deleting one pre-submission chain.';
