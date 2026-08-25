create function public.get_operator_personal_dossier_queue_v1(
  p_cursor text default null,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator_id uuid;
  v_operator_role text;
  v_operator_status text;
  v_cursor_payload jsonb;
  v_cursor_assigned_at timestamptz;
  v_cursor_quote_request_id uuid;
  v_items jsonb;
  v_last jsonb;
  v_has_more boolean := false;
  v_next_cursor text;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select operator_id, role, status
  into v_operator_id, v_operator_role, v_operator_status
  from public.commercial_operators
  where auth_user_id = v_subject;

  if not found then
    raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR';
  end if;
  if v_operator_status = 'DISABLED' then
    raise exception using errcode = '42501', message = 'OPERATOR_DISABLED';
  end if;
  if v_operator_status = 'REVOKED' then
    raise exception using errcode = '42501', message = 'OPERATOR_REVOKED';
  end if;
  if v_operator_status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;
  if v_operator_role <> 'operator' then
    raise exception using errcode = '42501', message = 'OPERATOR_PERSONAL_QUEUE_READER_REQUIRED';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_PERSONAL_QUEUE_LIMIT';
  end if;

  if p_cursor is not null then
    begin
      if p_cursor = ''
         or p_cursor !~ '^[0-9a-f]+$'
         or char_length(p_cursor) % 2 <> 0 then
        raise exception using errcode = '22023', message = 'INVALID_OPERATOR_PERSONAL_QUEUE_CURSOR';
      end if;

      v_cursor_payload := convert_from(decode(p_cursor, 'hex'), 'UTF8')::jsonb;
      if jsonb_typeof(v_cursor_payload) <> 'object'
         or not (v_cursor_payload ?& array['assigned_at', 'quote_request_id'])
         or (select count(*) from jsonb_object_keys(v_cursor_payload)) <> 2
         or jsonb_typeof(v_cursor_payload->'assigned_at') <> 'string'
         or jsonb_typeof(v_cursor_payload->'quote_request_id') <> 'string' then
        raise exception using errcode = '22023', message = 'INVALID_OPERATOR_PERSONAL_QUEUE_CURSOR';
      end if;

      v_cursor_assigned_at := (v_cursor_payload->>'assigned_at')::timestamptz;
      v_cursor_quote_request_id := (v_cursor_payload->>'quote_request_id')::uuid;
      if v_cursor_assigned_at is null or v_cursor_quote_request_id is null then
        raise exception using errcode = '22023', message = 'INVALID_OPERATOR_PERSONAL_QUEUE_CURSOR';
      end if;
    exception
      when sqlstate '22023' then
        raise;
      when others then
        raise exception using errcode = '22023', message = 'INVALID_OPERATOR_PERSONAL_QUEUE_CURSOR';
    end;
  end if;

  if exists (
    select 1
    from lws_internal.operator_dossier_assignments as assignment
    left join lws_internal.operator_application_readmodel_v2 as readmodel
      on readmodel.quote_request_id = assignment.quote_request_id
    where assignment.assignee_operator_id = v_operator_id
      and (
        assignment.assigned_at is null
        or readmodel.quote_request_id is null
        or coalesce(readmodel.application_reference, readmodel.support_reference) is null
        or coalesce(readmodel.application_reference, readmodel.support_reference)
             !~ '^(LWS-AAN-[0-9]{4}-[0-9]{4}|#[0-9A-F]{8})$'
        or readmodel.request_kind not in ('website', 'slimme_documentenflow')
        or readmodel.zone not in ('ACTIVE', 'ARCHIVED', 'TRASHED')
        or readmodel.operational_status is null
      )
  ) then
    raise exception using errcode = '23514', message = 'OPERATOR_PERSONAL_QUEUE_CONTRACT_INVALID';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'reference', page.reference,
    'source', page.source,
    'zone', page.zone,
    'status', page.status,
    'assigned_at', page.assigned_at,
    'assignment_revision', page.assignment_revision,
    '_quote_request_id', page.quote_request_id
  ) order by page.assigned_at desc, page.quote_request_id desc), '[]'::jsonb)
  into v_items
  from (
    select
      assignment.quote_request_id,
      coalesce(readmodel.application_reference, readmodel.support_reference) as reference,
      readmodel.request_kind as source,
      readmodel.zone,
      readmodel.operational_status as status,
      assignment.assigned_at,
      assignment.revision as assignment_revision
    from lws_internal.operator_dossier_assignments as assignment
    join lws_internal.operator_application_readmodel_v2 as readmodel
      on readmodel.quote_request_id = assignment.quote_request_id
    where assignment.assignee_operator_id = v_operator_id
      and (
        p_cursor is null
        or (assignment.assigned_at, assignment.quote_request_id)
             < (v_cursor_assigned_at, v_cursor_quote_request_id)
      )
    order by assignment.assigned_at desc, assignment.quote_request_id desc
    limit p_limit + 1
  ) as page;

  if jsonb_array_length(v_items) > p_limit then
    v_last := v_items->(p_limit - 1);
    v_has_more := true;
    v_next_cursor := encode(convert_to(jsonb_build_object(
      'assigned_at', v_last->>'assigned_at',
      'quote_request_id', v_last->>'_quote_request_id'
    )::text, 'UTF8'), 'hex');
    v_items := v_items - p_limit;
  end if;

  select coalesce(jsonb_agg(item - '_quote_request_id'), '[]'::jsonb)
  into v_items
  from jsonb_array_elements(v_items) as item;

  return jsonb_build_object(
    'items', v_items,
    'has_more', v_has_more,
    'next_cursor', v_next_cursor
  );
end;
$$;

revoke all on function public.get_operator_personal_dossier_queue_v1(text, integer)
from public, anon, authenticated, service_role;

grant execute on function public.get_operator_personal_dossier_queue_v1(text, integer)
to authenticated;

comment on function public.get_operator_personal_dossier_queue_v1(text, integer) is
  'Read-only current dossier assignments for the authenticated ACTIVE operator; caller identity derives exclusively from auth.uid().';