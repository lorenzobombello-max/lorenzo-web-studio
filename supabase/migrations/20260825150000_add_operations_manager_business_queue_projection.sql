create function public.get_operations_manager_business_queue_v1(
  p_cursor text default null,
  p_limit integer default 25
)
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
  v_cursor_payload jsonb;
  v_cursor_received_at timestamptz;
  v_cursor_reference text;
  v_items jsonb;
  v_last jsonb;
  v_has_more boolean := false;
  v_next_cursor text;
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
    raise exception using errcode = '42501', message = 'OPERATIONS_MANAGER_BUSINESS_QUEUE_READER_REQUIRED';
  end if;

  perform lws_internal.assert_operator_readmodel_integrity_v2();

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'INVALID_OPERATIONS_MANAGER_BUSINESS_QUEUE_LIMIT';
  end if;

  if p_cursor is not null then
    begin
      if p_cursor = ''
         or p_cursor !~ '^[0-9a-f]+$'
         or char_length(p_cursor) % 2 <> 0 then
        raise exception using errcode = '22023', message = 'INVALID_OPERATIONS_MANAGER_BUSINESS_QUEUE_CURSOR';
      end if;

      v_cursor_payload := convert_from(decode(p_cursor, 'hex'), 'UTF8')::jsonb;

      if jsonb_typeof(v_cursor_payload) <> 'object'
         or not (v_cursor_payload ?& array['received_at', 'reference'])
         or (select count(*) from jsonb_object_keys(v_cursor_payload)) <> 2
         or jsonb_typeof(v_cursor_payload->'received_at') <> 'string'
         or jsonb_typeof(v_cursor_payload->'reference') <> 'string' then
        raise exception using errcode = '22023', message = 'INVALID_OPERATIONS_MANAGER_BUSINESS_QUEUE_CURSOR';
      end if;

      v_cursor_reference := v_cursor_payload->>'reference';
      if v_cursor_reference !~ '^(LWS-AAN-[0-9]{4}-[0-9]{4}|#[0-9A-F]{8})$' then
        raise exception using errcode = '22023', message = 'INVALID_OPERATIONS_MANAGER_BUSINESS_QUEUE_CURSOR';
      end if;

      v_cursor_received_at := (v_cursor_payload->>'received_at')::timestamptz;
      if v_cursor_received_at is null then
        raise exception using errcode = '22023', message = 'INVALID_OPERATIONS_MANAGER_BUSINESS_QUEUE_CURSOR';
      end if;
    exception
      when sqlstate '22023' then
        raise;
      when others then
        raise exception using errcode = '22023', message = 'INVALID_OPERATIONS_MANAGER_BUSINESS_QUEUE_CURSOR';
    end;
  end if;

  if exists (
    select 1
    from lws_internal.operator_application_readmodel_v2 as readmodel
    where readmodel.operational_status is null
       or readmodel.operational_status not in (
         'CANCELLED', 'SUBMITTED', 'REVIEWED', 'QUOTE_ACCEPTED',
         'M1_PAYMENT_PENDING', 'M1_PAYMENT_RECEIVED', 'PROJECT_RELEASED',
         'PREVIEW_READY', 'M2_PAYMENT_RECEIVED', 'FINAL_APPROVAL_RECORDED',
         'FULL_PAYMENT_RECEIVED', 'FINAL_TRANSFER_AUTHORIZED', 'DELIVERED', 'ARCHIVED'
       )
       or (
         readmodel.operational_status not in ('CANCELLED', 'ARCHIVED')
         and (
           coalesce(readmodel.application_reference, readmodel.support_reference) is null
           or coalesce(readmodel.application_reference, readmodel.support_reference)
                !~ '^(LWS-AAN-[0-9]{4}-[0-9]{4}|#[0-9A-F]{8})$'
           or readmodel.request_kind is null
           or readmodel.request_kind not in ('website', 'slimme_documentenflow')
           or readmodel.dossier_date is null
         )
       )
  ) then
    raise exception using errcode = '23514', message = 'OPERATIONS_MANAGER_BUSINESS_QUEUE_CONTRACT_INVALID';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'reference', page.reference,
    'source', page.source,
    'status', page.status,
    'received_at', page.received_at
  ) order by page.received_at asc, page.reference asc), '[]'::jsonb)
  into v_items
  from (
    select
      coalesce(readmodel.application_reference, readmodel.support_reference) as reference,
      readmodel.request_kind as source,
      readmodel.operational_status as status,
      readmodel.dossier_date as received_at
    from lws_internal.operator_application_readmodel_v2 as readmodel
    where readmodel.operational_status not in ('CANCELLED', 'ARCHIVED')
      and (
        p_cursor is null
        or (readmodel.dossier_date, coalesce(readmodel.application_reference, readmodel.support_reference))
             > (v_cursor_received_at, v_cursor_reference)
      )
    order by
      readmodel.dossier_date asc,
      coalesce(readmodel.application_reference, readmodel.support_reference) asc
    limit p_limit + 1
  ) as page;

  if jsonb_array_length(v_items) > p_limit then
    v_last := v_items->(p_limit - 1);
    v_has_more := true;
    v_next_cursor := encode(convert_to(jsonb_build_object(
      'received_at', v_last->>'received_at',
      'reference', v_last->>'reference'
    )::text, 'UTF8'), 'hex');
    v_items := v_items - p_limit;
  end if;

  return jsonb_build_object(
    'as_of', v_as_of,
    'items', v_items,
    'has_more', v_has_more,
    'next_cursor', v_next_cursor
  );
end;
$$;

revoke all on function public.get_operations_manager_business_queue_v1(text, integer)
from public, anon, authenticated, service_role;

grant execute on function public.get_operations_manager_business_queue_v1(text, integer)
to authenticated;

comment on function public.get_operations_manager_business_queue_v1(text, integer) is
  'Read-only open production business queue for active owners and Operations Managers; exposes only reference, source, canonical status, and received timestamp.';
