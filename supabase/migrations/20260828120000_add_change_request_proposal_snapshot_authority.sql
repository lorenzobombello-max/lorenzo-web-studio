create schema if not exists lws_internal authorization postgres;
revoke all on schema lws_internal from public, anon, authenticated, service_role;

create table public.change_request_proposal_snapshots (
  proposal_id uuid primary key default gen_random_uuid(),
  change_order_id uuid not null references public.change_orders(change_order_id),
  project_id uuid not null references public.commercial_projects(project_id),
  original_quotation_issuance_id uuid not null references public.quote_request_quotation_issuances(id),
  feedback_id uuid not null references public.customer_feedback(feedback_id),
  customer_request_id uuid references public.customer_requests(request_id),
  proposal_revision integer not null check (proposal_revision > 0),
  expected_project_revision bigint not null check (expected_project_revision >= 0),
  expected_change_order_status text not null check (expected_change_order_status = 'CHANGE_ORDER_REQUIRED'),
  customer_visible_change_summary text not null check (
    length(customer_visible_change_summary) between 1 and 2000
    and customer_visible_change_summary = btrim(customer_visible_change_summary)
  ),
  reason text not null check (length(reason) between 1 and 2000 and reason = btrim(reason)),
  added_scope text[] not null,
  removed_scope text[] not null,
  affected_deliverables text[] not null check (cardinality(affected_deliverables) > 0),
  other_scope_impact text,
  schedule_impact text not null check (
    length(schedule_impact) between 1 and 2000 and schedule_impact = btrim(schedule_impact)
  ),
  additional_time_value integer not null check (additional_time_value >= 0),
  additional_time_unit text not null check (additional_time_unit in ('DAYS','WEEKS')),
  adjusted_delivery_target date not null,
  pricing_classification text not null check (
    pricing_classification in ('FIXED','UNIT','FROM','MANUAL','INCLUDED')
  ),
  catalog_item_reference text,
  catalog_version text not null,
  catalog_sha256 char(64) not null check (catalog_sha256 ~ '^[0-9A-F]{64}$'),
  quantity bigint check (quantity > 0),
  unit_price_minor bigint check (unit_price_minor >= 0),
  fixed_price_minor bigint check (fixed_price_minor >= 0),
  authority_floor_minor bigint check (authority_floor_minor >= 0),
  owner_final_amount_minor bigint check (owner_final_amount_minor >= 0),
  amount_ex_vat_minor bigint not null check (amount_ex_vat_minor >= 0),
  impact_direction text check (impact_direction in ('INCREASE','REDUCTION')),
  currency char(3) not null check (currency = 'EUR'),
  pricing_justification text,
  payment_milestone_impact text not null check (
    length(payment_milestone_impact) between 1 and 2000
    and payment_milestone_impact = btrim(payment_milestone_impact)
  ),
  separate_invoicing boolean not null,
  template_authority_id uuid not null references public.change_request_template_authorities(id),
  template_id text not null,
  template_version text not null,
  template_sha256 char(64) not null check (template_sha256 ~ '^[0-9A-F]{64}$'),
  approved_by_operator_id uuid not null references public.commercial_operators(operator_id),
  approved_by_actor text not null check (nullif(btrim(approved_by_actor), '') is not null),
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  constraint change_request_proposal_revision_unique
    unique (change_order_id, proposal_revision),
  constraint change_request_proposal_expected_revision_unique
    unique (change_order_id, expected_project_revision),
  constraint change_request_proposal_scope_shape_valid check (
    cardinality(added_scope) > 0
    or cardinality(removed_scope) > 0
    or nullif(btrim(other_scope_impact), '') is not null
  ),
  constraint change_request_proposal_pricing_shape_valid check (
    (
      pricing_classification = 'FIXED'
      and nullif(btrim(catalog_item_reference), '') is not null
      and fixed_price_minor is not null
      and amount_ex_vat_minor = fixed_price_minor
      and quantity is null and unit_price_minor is null
      and authority_floor_minor is null and owner_final_amount_minor is null
      and pricing_justification is null and impact_direction is not null
    ) or (
      pricing_classification = 'UNIT'
      and nullif(btrim(catalog_item_reference), '') is not null
      and quantity is not null and unit_price_minor is not null
      and amount_ex_vat_minor = quantity * unit_price_minor
      and fixed_price_minor is null and authority_floor_minor is null
      and owner_final_amount_minor is null and pricing_justification is null
      and impact_direction is not null
    ) or (
      pricing_classification = 'FROM'
      and nullif(btrim(catalog_item_reference), '') is not null
      and authority_floor_minor is not null
      and owner_final_amount_minor is not null
      and owner_final_amount_minor >= authority_floor_minor
      and amount_ex_vat_minor = owner_final_amount_minor
      and quantity is null and unit_price_minor is null and fixed_price_minor is null
      and pricing_justification is null and impact_direction is not null
    ) or (
      pricing_classification = 'MANUAL'
      and owner_final_amount_minor is not null
      and amount_ex_vat_minor = owner_final_amount_minor
      and nullif(btrim(pricing_justification), '') is not null
      and quantity is null and unit_price_minor is null and fixed_price_minor is null
      and authority_floor_minor is null and impact_direction is not null
    ) or (
      pricing_classification = 'INCLUDED'
      and amount_ex_vat_minor = 0 and impact_direction is null
      and quantity is null and unit_price_minor is null and fixed_price_minor is null
      and authority_floor_minor is null and owner_final_amount_minor is null
      and pricing_justification is null
    )
  )
);

create table lws_internal.change_request_proposal_operations (
  operation_id uuid primary key default gen_random_uuid(),
  actor_id text not null,
  project_id uuid not null references public.commercial_projects(project_id),
  idempotency_key uuid not null,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  proposal_id uuid not null references public.change_request_proposal_snapshots(proposal_id),
  result_payload jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (actor_id, project_id, idempotency_key)
);

create function lws_internal.guard_change_request_proposal_immutable_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'CHANGE_REQUEST_PROPOSAL_IMMUTABLE';
end;
$$;

create trigger trg_change_request_proposal_snapshots_immutable
before update or delete on public.change_request_proposal_snapshots
for each row execute function lws_internal.guard_change_request_proposal_immutable_v1();

create trigger trg_change_request_proposal_operations_immutable
before update or delete on lws_internal.change_request_proposal_operations
for each row execute function lws_internal.guard_change_request_proposal_immutable_v1();

create function lws_internal.create_change_request_proposal_snapshot_core_v1(
  p_operator_id uuid,
  p_actor_id text,
  p_change_order_id uuid,
  p_project_id uuid,
  p_original_quotation_issuance_id uuid,
  p_feedback_id uuid,
  p_customer_request_id uuid,
  p_proposal_revision integer,
  p_expected_project_revision bigint,
  p_expected_change_order_status text,
  p_idempotency_key uuid,
  p_customer_visible_change_summary text,
  p_reason text,
  p_added_scope text[],
  p_removed_scope text[],
  p_affected_deliverables text[],
  p_other_scope_impact text,
  p_schedule_impact text,
  p_additional_time_value integer,
  p_additional_time_unit text,
  p_adjusted_delivery_target date,
  p_pricing_classification text,
  p_catalog_item_reference text,
  p_catalog_version text,
  p_catalog_sha256 text,
  p_quantity bigint,
  p_unit_price_minor bigint,
  p_fixed_price_minor bigint,
  p_authority_floor_minor bigint,
  p_owner_final_amount_minor bigint,
  p_amount_ex_vat_minor bigint,
  p_impact_direction text,
  p_currency text,
  p_pricing_justification text,
  p_payment_milestone_impact text,
  p_separate_invoicing boolean
)
returns table (proposal_id uuid, proposal_revision integer, replayed boolean)
language plpgsql
security definer
set search_path = lws_internal, public, extensions, pg_catalog
as $$
declare
  v_change_order public.change_orders%rowtype;
  v_project public.commercial_projects%rowtype;
  v_customer_request public.customer_requests%rowtype;
  v_template public.change_request_template_authorities%rowtype;
  v_request_kind text;
  v_fingerprint text;
  v_existing lws_internal.change_request_proposal_operations%rowtype;
  v_proposal_id uuid := gen_random_uuid();
  v_result jsonb;
begin
  if p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'CHANGE_REQUEST_PROPOSAL_IDEMPOTENCY_KEY_REQUIRED';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'change_order_id', p_change_order_id,
    'project_id', p_project_id,
    'original_quotation_issuance_id', p_original_quotation_issuance_id,
    'feedback_id', p_feedback_id,
    'customer_request_id', p_customer_request_id,
    'proposal_revision', p_proposal_revision,
    'expected_project_revision', p_expected_project_revision,
    'expected_change_order_status', p_expected_change_order_status,
    'customer_visible_change_summary', p_customer_visible_change_summary,
    'reason', p_reason,
    'added_scope', p_added_scope,
    'removed_scope', p_removed_scope,
    'affected_deliverables', p_affected_deliverables,
    'other_scope_impact', p_other_scope_impact,
    'schedule_impact', p_schedule_impact,
    'additional_time_value', p_additional_time_value,
    'additional_time_unit', p_additional_time_unit,
    'adjusted_delivery_target', p_adjusted_delivery_target,
    'pricing_classification', p_pricing_classification,
    'catalog_item_reference', p_catalog_item_reference,
    'catalog_version', p_catalog_version,
    'catalog_sha256', p_catalog_sha256,
    'quantity', p_quantity,
    'unit_price_minor', p_unit_price_minor,
    'fixed_price_minor', p_fixed_price_minor,
    'authority_floor_minor', p_authority_floor_minor,
    'owner_final_amount_minor', p_owner_final_amount_minor,
    'amount_ex_vat_minor', p_amount_ex_vat_minor,
    'impact_direction', p_impact_direction,
    'currency', p_currency,
    'pricing_justification', p_pricing_justification,
    'payment_milestone_impact', p_payment_milestone_impact,
    'separate_invoicing', p_separate_invoicing
  )::text, 'UTF8'), 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended(
    p_actor_id || ':' || p_project_id::text || ':' || p_idempotency_key::text, 0
  ));

  select * into v_existing
  from lws_internal.change_request_proposal_operations
  where actor_id = p_actor_id
    and project_id = p_project_id
    and idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return query select
      (v_existing.result_payload->>'proposal_id')::uuid,
      (v_existing.result_payload->>'proposal_revision')::integer,
      true;
    return;
  end if;

  select * into v_change_order
  from public.change_orders
  where change_order_id = p_change_order_id
  for share;
  if not found then
    raise exception using errcode = '23503', message = 'CHANGE_REQUEST_PROPOSAL_CHANGE_ORDER_NOT_FOUND';
  end if;
  if v_change_order.project_id <> p_project_id then
    raise exception using errcode = '23514', message = 'CHANGE_REQUEST_PROPOSAL_PROJECT_MISMATCH';
  end if;
  if v_change_order.original_quotation_issuance_id <> p_original_quotation_issuance_id then
    raise exception using errcode = '23514', message = 'CHANGE_REQUEST_PROPOSAL_QUOTATION_MISMATCH';
  end if;
  if v_change_order.feedback_id <> p_feedback_id then
    raise exception using errcode = '23514', message = 'CHANGE_REQUEST_PROPOSAL_FEEDBACK_MISMATCH';
  end if;
  if p_expected_change_order_status is distinct from 'CHANGE_ORDER_REQUIRED'
     or v_change_order.status is distinct from p_expected_change_order_status then
    raise exception using errcode = '40001', message = 'CHANGE_REQUEST_PROPOSAL_CHANGE_ORDER_STATE_CONFLICT';
  end if;

  select * into v_project
  from public.commercial_projects
  where project_id = p_project_id
  for share;
  if not found then
    raise exception using errcode = '23503', message = 'CHANGE_REQUEST_PROPOSAL_PROJECT_NOT_FOUND';
  end if;
  if v_project.quotation_issuance_id <> p_original_quotation_issuance_id then
    raise exception using errcode = '23514', message = 'CHANGE_REQUEST_PROPOSAL_QUOTATION_MISMATCH';
  end if;
  if v_project.revision <> p_expected_project_revision then
    raise exception using errcode = '40001', message = 'CHANGE_REQUEST_PROPOSAL_STALE_REVISION';
  end if;

  if not exists (
    select 1 from public.customer_feedback
    where feedback_id = p_feedback_id and project_id = p_project_id
  ) then
    raise exception using errcode = '23514', message = 'CHANGE_REQUEST_PROPOSAL_FEEDBACK_MISMATCH';
  end if;

  if p_customer_request_id is not null then
    select * into v_customer_request
    from public.customer_requests
    where request_id = p_customer_request_id;
    if not found
       or v_customer_request.project_id <> p_project_id
       or v_customer_request.linked_change_order_id is distinct from p_change_order_id
       or v_customer_request.source_feedback_id is distinct from p_feedback_id then
      raise exception using errcode = '23514', message = 'CHANGE_REQUEST_PROPOSAL_CUSTOMER_REQUEST_MISMATCH';
    end if;
  end if;

  select request_row.request_kind into v_request_kind
  from public.quote_request_quotation_issuances as issuance
  join public.quote_request_quotation_approvals as approval on approval.id = issuance.approval_id
  join public.quote_requests as request_row on request_row.id = approval.quote_request_id
  where issuance.id = p_original_quotation_issuance_id
    and issuance.status in ('ISSUED','SUPERSEDED');
  if v_request_kind is distinct from 'website' then
    raise exception using errcode = '23514', message = 'CHANGE_REQUEST_PROPOSAL_WEBSITE_REQUIRED';
  end if;

  if nullif(btrim(p_customer_visible_change_summary), '') is null
     or nullif(btrim(p_reason), '') is null
     or p_added_scope is null or p_removed_scope is null
     or p_affected_deliverables is null or cardinality(p_affected_deliverables) = 0
     or (
       cardinality(p_added_scope) = 0 and cardinality(p_removed_scope) = 0
       and nullif(btrim(p_other_scope_impact), '') is null
     )
     or nullif(btrim(p_schedule_impact), '') is null
     or p_additional_time_value is null or p_additional_time_value < 0
     or p_additional_time_unit not in ('DAYS','WEEKS')
     or p_adjusted_delivery_target is null
     or nullif(btrim(p_payment_milestone_impact), '') is null
     or p_separate_invoicing is null then
    raise exception using errcode = '23514', message = 'CHANGE_REQUEST_PROPOSAL_SCOPE_REQUIRED';
  end if;

  if p_pricing_classification not in ('FIXED','UNIT','FROM','MANUAL','INCLUDED') then
    raise exception using errcode = '23514', message = 'CHANGE_REQUEST_PROPOSAL_PRICING_CLASSIFICATION_INVALID';
  end if;
  if p_currency is distinct from 'EUR' then
    raise exception using errcode = '23514', message = 'CHANGE_REQUEST_PROPOSAL_CURRENCY_INVALID';
  end if;
  if p_catalog_version is distinct from 'LWS_Master_Product_Price_Catalog_v2_2026-08-13'
     or p_catalog_sha256 is distinct from '52FA3B9664EFF84640EAB914B72768E8059B1B49708815A0095D346C8F27BACE' then
    raise exception using errcode = '23514', message = 'CHANGE_REQUEST_PROPOSAL_CATALOG_AUTHORITY_INVALID';
  end if;
    if p_amount_ex_vat_minor is null or p_amount_ex_vat_minor < 0
      or not coalesce((
       (p_pricing_classification = 'FIXED'
        and nullif(btrim(p_catalog_item_reference), '') is not null
        and p_fixed_price_minor is not null and p_fixed_price_minor >= 0
        and p_amount_ex_vat_minor = p_fixed_price_minor
        and p_quantity is null and p_unit_price_minor is null
        and p_authority_floor_minor is null and p_owner_final_amount_minor is null
        and p_pricing_justification is null and p_impact_direction in ('INCREASE','REDUCTION'))
       or (p_pricing_classification = 'UNIT'
        and nullif(btrim(p_catalog_item_reference), '') is not null
        and p_quantity > 0 and p_unit_price_minor >= 0
        and p_amount_ex_vat_minor = p_quantity * p_unit_price_minor
        and p_fixed_price_minor is null and p_authority_floor_minor is null
        and p_owner_final_amount_minor is null and p_pricing_justification is null
        and p_impact_direction in ('INCREASE','REDUCTION'))
       or (p_pricing_classification = 'FROM'
        and nullif(btrim(p_catalog_item_reference), '') is not null
        and p_authority_floor_minor >= 0
        and p_owner_final_amount_minor >= p_authority_floor_minor
        and p_amount_ex_vat_minor = p_owner_final_amount_minor
        and p_quantity is null and p_unit_price_minor is null and p_fixed_price_minor is null
        and p_pricing_justification is null and p_impact_direction in ('INCREASE','REDUCTION'))
       or (p_pricing_classification = 'MANUAL'
        and p_owner_final_amount_minor >= 0
        and p_amount_ex_vat_minor = p_owner_final_amount_minor
        and nullif(btrim(p_pricing_justification), '') is not null
        and p_quantity is null and p_unit_price_minor is null and p_fixed_price_minor is null
        and p_authority_floor_minor is null and p_impact_direction in ('INCREASE','REDUCTION'))
       or (p_pricing_classification = 'INCLUDED'
        and p_amount_ex_vat_minor = 0 and p_impact_direction is null
        and p_quantity is null and p_unit_price_minor is null and p_fixed_price_minor is null
        and p_authority_floor_minor is null and p_owner_final_amount_minor is null
        and p_pricing_justification is null)
    ), false) then
    raise exception using errcode = '23514', message = 'CHANGE_REQUEST_PROPOSAL_PRICING_SHAPE_INVALID';
  end if;

  if exists (
    select 1 from public.change_request_proposal_snapshots as proposal
    where proposal.change_order_id = p_change_order_id
      and proposal.proposal_revision = p_proposal_revision
  ) then
    raise exception using errcode = '23505', message = 'CHANGE_REQUEST_PROPOSAL_REVISION_CONFLICT';
  end if;
  if exists (
    select 1 from public.change_request_proposal_snapshots as proposal
    where proposal.change_order_id = p_change_order_id
      and proposal.expected_project_revision = p_expected_project_revision
  ) then
    raise exception using errcode = '23505', message = 'CHANGE_REQUEST_PROPOSAL_EXPECTED_REVISION_CONFLICT';
  end if;

  select * into strict v_template
  from public.resolve_current_change_request_template_v1('CHANGE_REQUEST');

  insert into public.change_request_proposal_snapshots (
    proposal_id, change_order_id, project_id, original_quotation_issuance_id,
    feedback_id, customer_request_id, proposal_revision,
    expected_project_revision, expected_change_order_status,
    customer_visible_change_summary, reason, added_scope, removed_scope,
    affected_deliverables, other_scope_impact, schedule_impact,
    additional_time_value, additional_time_unit, adjusted_delivery_target,
    pricing_classification, catalog_item_reference, catalog_version,
    catalog_sha256, quantity, unit_price_minor, fixed_price_minor,
    authority_floor_minor, owner_final_amount_minor, amount_ex_vat_minor,
    impact_direction, currency, pricing_justification,
    payment_milestone_impact, separate_invoicing,
    template_authority_id, template_id, template_version, template_sha256,
    approved_by_operator_id, approved_by_actor, request_fingerprint
  ) values (
    v_proposal_id, p_change_order_id, p_project_id,
    p_original_quotation_issuance_id, p_feedback_id, p_customer_request_id,
    p_proposal_revision, p_expected_project_revision,
    p_expected_change_order_status, btrim(p_customer_visible_change_summary),
    btrim(p_reason), p_added_scope, p_removed_scope, p_affected_deliverables,
    nullif(btrim(p_other_scope_impact), ''), btrim(p_schedule_impact),
    p_additional_time_value, p_additional_time_unit,
    p_adjusted_delivery_target, p_pricing_classification,
    nullif(btrim(p_catalog_item_reference), ''), p_catalog_version,
    p_catalog_sha256, p_quantity, p_unit_price_minor, p_fixed_price_minor,
    p_authority_floor_minor, p_owner_final_amount_minor,
    p_amount_ex_vat_minor, p_impact_direction, p_currency,
    nullif(btrim(p_pricing_justification), ''),
    btrim(p_payment_milestone_impact), p_separate_invoicing,
    v_template.id, v_template.template_id, v_template.template_version,
    v_template.template_sha256, p_operator_id, p_actor_id, v_fingerprint
  );

  v_result := jsonb_build_object(
    'proposal_id', v_proposal_id,
    'proposal_revision', p_proposal_revision
  );
  insert into lws_internal.change_request_proposal_operations (
    actor_id, project_id, idempotency_key, request_fingerprint,
    proposal_id, result_payload
  ) values (
    p_actor_id, p_project_id, p_idempotency_key, v_fingerprint,
    v_proposal_id, v_result
  );

  return query select v_proposal_id, p_proposal_revision, false;
end;
$$;

create function public.create_change_request_proposal_snapshot_v1(
  p_change_order_id uuid,
  p_project_id uuid,
  p_original_quotation_issuance_id uuid,
  p_feedback_id uuid,
  p_customer_request_id uuid,
  p_proposal_revision integer,
  p_expected_project_revision bigint,
  p_expected_change_order_status text,
  p_idempotency_key uuid,
  p_customer_visible_change_summary text,
  p_reason text,
  p_added_scope text[],
  p_removed_scope text[],
  p_affected_deliverables text[],
  p_other_scope_impact text,
  p_schedule_impact text,
  p_additional_time_value integer,
  p_additional_time_unit text,
  p_adjusted_delivery_target date,
  p_pricing_classification text,
  p_catalog_item_reference text,
  p_catalog_version text,
  p_catalog_sha256 text,
  p_quantity bigint,
  p_unit_price_minor bigint,
  p_fixed_price_minor bigint,
  p_authority_floor_minor bigint,
  p_owner_final_amount_minor bigint,
  p_amount_ex_vat_minor bigint,
  p_impact_direction text,
  p_currency text,
  p_pricing_justification text,
  p_payment_milestone_impact text,
  p_separate_invoicing boolean
)
returns table (proposal_id uuid, proposal_revision integer, replayed boolean)
language plpgsql
security definer
set search_path = lws_internal, public, auth, extensions, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;
  if not found then
    raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR';
  end if;
  if v_operator.status is distinct from 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;
  if v_operator.role not in ('owner','admin') then
    raise exception using errcode = '42501', message = 'CHANGE_REQUEST_PROPOSAL_OWNER_REQUIRED';
  end if;

  return query
  select * from lws_internal.create_change_request_proposal_snapshot_core_v1(
    v_operator.operator_id, 'OPERATOR:' || v_operator.operator_id::text,
    p_change_order_id, p_project_id, p_original_quotation_issuance_id,
    p_feedback_id, p_customer_request_id, p_proposal_revision,
    p_expected_project_revision, p_expected_change_order_status,
    p_idempotency_key, p_customer_visible_change_summary, p_reason,
    p_added_scope, p_removed_scope, p_affected_deliverables,
    p_other_scope_impact, p_schedule_impact, p_additional_time_value,
    p_additional_time_unit, p_adjusted_delivery_target,
    p_pricing_classification, p_catalog_item_reference, p_catalog_version,
    p_catalog_sha256, p_quantity, p_unit_price_minor, p_fixed_price_minor,
    p_authority_floor_minor, p_owner_final_amount_minor,
    p_amount_ex_vat_minor, p_impact_direction, p_currency,
    p_pricing_justification, p_payment_milestone_impact,
    p_separate_invoicing
  );
end;
$$;

alter table public.change_request_proposal_snapshots enable row level security;
alter table public.change_request_proposal_snapshots force row level security;
alter table lws_internal.change_request_proposal_operations enable row level security;
alter table lws_internal.change_request_proposal_operations force row level security;

revoke all privileges on table public.change_request_proposal_snapshots
from public, anon, authenticated, service_role;
revoke all privileges on table lws_internal.change_request_proposal_operations
from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_change_request_proposal_immutable_v1()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.create_change_request_proposal_snapshot_core_v1(
  uuid,text,uuid,uuid,uuid,uuid,uuid,integer,bigint,text,uuid,
  text,text,text[],text[],text[],text,text,integer,text,date,
  text,text,text,text,bigint,bigint,bigint,bigint,bigint,bigint,
  text,text,text,text,boolean
) from public, anon, authenticated, service_role;
revoke all on function public.create_change_request_proposal_snapshot_v1(
  uuid,uuid,uuid,uuid,uuid,integer,bigint,text,uuid,
  text,text,text[],text[],text[],text,text,integer,text,date,
  text,text,text,text,bigint,bigint,bigint,bigint,bigint,bigint,
  text,text,text,text,boolean
) from public, anon, authenticated, service_role;

grant execute on function public.create_change_request_proposal_snapshot_v1(
  uuid,uuid,uuid,uuid,uuid,integer,bigint,text,uuid,
  text,text,text[],text[],text[],text,text,integer,text,date,
  text,text,text,text,bigint,bigint,bigint,bigint,bigint,bigint,
  text,text,text,text,boolean
) to authenticated;

comment on table public.change_request_proposal_snapshots is
  'Immutable Owner-approved Website Change Request proposal snapshots; no document, lifecycle, pricing, mail, invoice, payment, capability, SDF, or RDR side effects.';
comment on function public.create_change_request_proposal_snapshot_v1(
  uuid,uuid,uuid,uuid,uuid,integer,bigint,text,uuid,
  text,text,text[],text[],text[],text,text,integer,text,date,
  text,text,text,text,bigint,bigint,bigint,bigint,bigint,bigint,
  text,text,text,text,boolean
) is 'Creates or idempotently replays a structured Website-only proposal snapshot after Owner/admin and provenance validation.';