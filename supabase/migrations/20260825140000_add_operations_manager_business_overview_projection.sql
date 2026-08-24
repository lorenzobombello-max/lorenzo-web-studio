create function public.get_operations_manager_business_overview_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_actor_role text;
  v_actor_status text;
  v_as_of timestamptz := statement_timestamp();
  v_result jsonb;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select role, status
  into v_actor_role, v_actor_status
  from public.commercial_operators
  where auth_user_id = v_subject;

  if not found then
    raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR';
  end if;
  if v_actor_status = 'DISABLED' then
    raise exception using errcode = '42501', message = 'OPERATOR_DISABLED';
  end if;
  if v_actor_status = 'REVOKED' then
    raise exception using errcode = '42501', message = 'OPERATOR_REVOKED';
  end if;
  if v_actor_status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;
  if v_actor_role not in ('owner', 'operations_manager') then
    raise exception using errcode = '42501', message = 'OPERATIONS_MANAGER_BUSINESS_OVERVIEW_READER_REQUIRED';
  end if;

  perform lws_internal.assert_operator_readmodel_integrity_v2();

  with classified as (
    select
      readmodel.request_kind as source,
      readmodel.operational_status,
      readmodel.dossier_date as relevant_at,
      readmodel.operational_status not in ('CANCELLED', 'ARCHIVED') as is_open
    from lws_internal.operator_application_readmodel_v2 as readmodel
  ), included as (
    select source, operational_status, relevant_at, is_open
    from classified
    where is_open or relevant_at >= v_as_of - interval '90 days'
  )
  select jsonb_build_object(
    'as_of', v_as_of,
    'total_count', count(*),
    'open_count', count(*) filter (where is_open),
    'counts_by_source', jsonb_build_object(
      'website', count(*) filter (where source = 'website'),
      'slimme_documentenflow', count(*) filter (where source = 'slimme_documentenflow')
    ),
    'counts_by_status', jsonb_build_object(
      'CANCELLED', count(*) filter (where operational_status = 'CANCELLED'),
      'SUBMITTED', count(*) filter (where operational_status = 'SUBMITTED'),
      'REVIEWED', count(*) filter (where operational_status = 'REVIEWED'),
      'QUOTE_ACCEPTED', count(*) filter (where operational_status = 'QUOTE_ACCEPTED'),
      'M1_PAYMENT_PENDING', count(*) filter (where operational_status = 'M1_PAYMENT_PENDING'),
      'M1_PAYMENT_RECEIVED', count(*) filter (where operational_status = 'M1_PAYMENT_RECEIVED'),
      'PROJECT_RELEASED', count(*) filter (where operational_status = 'PROJECT_RELEASED'),
      'PREVIEW_READY', count(*) filter (where operational_status = 'PREVIEW_READY'),
      'M2_PAYMENT_RECEIVED', count(*) filter (where operational_status = 'M2_PAYMENT_RECEIVED'),
      'FINAL_APPROVAL_RECORDED', count(*) filter (where operational_status = 'FINAL_APPROVAL_RECORDED'),
      'FULL_PAYMENT_RECEIVED', count(*) filter (where operational_status = 'FULL_PAYMENT_RECEIVED'),
      'FINAL_TRANSFER_AUTHORIZED', count(*) filter (where operational_status = 'FINAL_TRANSFER_AUTHORIZED'),
      'DELIVERED', count(*) filter (where operational_status = 'DELIVERED'),
      'ARCHIVED', count(*) filter (where operational_status = 'ARCHIVED')
    ),
    'counts_by_waiting_bucket', jsonb_build_object(
      'lt_24h', count(*) filter (where is_open and v_as_of - relevant_at < interval '24 hours'),
      'd1_3', count(*) filter (
        where is_open
          and v_as_of - relevant_at >= interval '24 hours'
          and v_as_of - relevant_at < interval '4 days'
      ),
      'd4_7', count(*) filter (
        where is_open
          and v_as_of - relevant_at >= interval '4 days'
          and v_as_of - relevant_at < interval '8 days'
      ),
      'gt_7d', count(*) filter (where is_open and v_as_of - relevant_at >= interval '8 days')
    )
  )
  into v_result
  from included;

  return v_result;
end;
$$;

revoke all on function public.get_operations_manager_business_overview_v1()
from public, anon, authenticated, service_role;

grant execute on function public.get_operations_manager_business_overview_v1()
to authenticated;

comment on function public.get_operations_manager_business_overview_v1() is
  'Read-only global production business aggregates for active owners and Operations Managers; exposes no record identity or PII.';