create index customer_requests_dossier_submitted_idx
  on public.customer_requests (quote_request_id, submitted_at desc, request_id desc);

create function public.get_customer_requests_for_dossier_v1(
  p_dossier_reference text,
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
  v_operator public.commercial_operators%rowtype;
  v_quote_request_id uuid;
  v_allowed boolean := false;
  v_cursor_payload jsonb;
  v_cursor_submitted_at timestamptz;
  v_cursor_request_id uuid;
  v_items jsonb;
  v_last jsonb;
  v_has_more boolean := false;
  v_next_cursor text;
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
  if v_operator.status = 'DISABLED' then
    raise exception using errcode = '42501', message = 'OPERATOR_DISABLED';
  end if;
  if v_operator.status = 'REVOKED' then
    raise exception using errcode = '42501', message = 'OPERATOR_REVOKED';
  end if;
  if v_operator.status <> 'ACTIVE' then
    raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST_LIST_LIMIT';
  end if;

  begin
    v_quote_request_id := lws_internal.resolve_operator_dossier_reference_v1(p_dossier_reference);
  exception
    when sqlstate 'P0001' then
      raise exception using errcode = '42501', message = 'CUSTOMER_REQUEST_ACCESS_DENIED';
  end;

  if v_operator.role in ('owner', 'operations_manager') then
    v_allowed := true;
  elsif v_operator.role = 'operator' then
    select true into v_allowed
    from lws_internal.operator_dossier_assignments as assignment
    where assignment.quote_request_id = v_quote_request_id
      and assignment.assignee_operator_id = v_operator.operator_id;
  elsif v_operator.role = 'reviewer' then
    select true into v_allowed
    from public.commercial_operator_project_grants as project_grant
    join public.customer_requests as request
      on request.project_id = project_grant.project_id
    where project_grant.operator_id = v_operator.operator_id
      and request.quote_request_id = v_quote_request_id
      and project_grant.access_level in ('operator', 'reviewer')
      and project_grant.revoked_at is null;
  elsif v_operator.role = 'read_only' then
    select true into v_allowed
    from public.commercial_operator_project_grants as project_grant
    join public.customer_requests as request
      on request.project_id = project_grant.project_id
    where project_grant.operator_id = v_operator.operator_id
      and request.quote_request_id = v_quote_request_id
      and project_grant.access_level in ('operator', 'reviewer', 'read_only')
      and project_grant.revoked_at is null;
  end if;

  if not coalesce(v_allowed, false) then
    raise exception using errcode = '42501', message = 'CUSTOMER_REQUEST_ACCESS_DENIED';
  end if;

  if p_cursor is not null then
    begin
      if p_cursor = ''
         or p_cursor !~ '^[0-9a-f]+$'
         or char_length(p_cursor) % 2 <> 0 then
        raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST_LIST_CURSOR';
      end if;

      v_cursor_payload := convert_from(decode(p_cursor, 'hex'), 'UTF8')::jsonb;
      if jsonb_typeof(v_cursor_payload) <> 'object'
         or not (v_cursor_payload ?& array['submitted_at', 'request_id'])
         or (select count(*) from jsonb_object_keys(v_cursor_payload)) <> 2
         or jsonb_typeof(v_cursor_payload->'submitted_at') <> 'string'
         or jsonb_typeof(v_cursor_payload->'request_id') <> 'string' then
        raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST_LIST_CURSOR';
      end if;

      v_cursor_submitted_at := (v_cursor_payload->>'submitted_at')::timestamptz;
      v_cursor_request_id := (v_cursor_payload->>'request_id')::uuid;
      if v_cursor_submitted_at is null or v_cursor_request_id is null then
        raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST_LIST_CURSOR';
      end if;
    exception
      when sqlstate '22023' then
        raise;
      when others then
        raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST_LIST_CURSOR';
    end;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'request_id', page.request_id,
    'request_reference', page.request_reference,
    'request_type', page.request_type,
    'title', page.title,
    'status', page.status,
    'priority', page.priority,
    'submitted_at', page.submitted_at,
    'updated_at', page.updated_at,
    'revision', page.revision
  ) order by page.submitted_at desc, page.request_id desc), '[]'::jsonb)
  into v_items
  from (
    select request.*
    from public.customer_requests as request
    where request.quote_request_id = v_quote_request_id
      and (
        v_operator.role not in ('reviewer', 'read_only')
        or exists (
          select 1
          from public.commercial_operator_project_grants as project_grant
          where project_grant.operator_id = v_operator.operator_id
            and project_grant.project_id = request.project_id
            and project_grant.revoked_at is null
            and (
              (v_operator.role = 'reviewer' and project_grant.access_level in ('operator', 'reviewer'))
              or (v_operator.role = 'read_only' and project_grant.access_level in ('operator', 'reviewer', 'read_only'))
            )
        )
      )
      and (
        p_cursor is null
        or (request.submitted_at, request.request_id)
             < (v_cursor_submitted_at, v_cursor_request_id)
      )
    order by request.submitted_at desc, request.request_id desc
    limit p_limit + 1
  ) as page;

  if jsonb_array_length(v_items) > p_limit then
    v_last := v_items->(p_limit - 1);
    v_has_more := true;
    v_next_cursor := encode(convert_to(jsonb_build_object(
      'submitted_at', v_last->>'submitted_at',
      'request_id', v_last->>'request_id'
    )::text, 'UTF8'), 'hex');
    v_items := v_items - p_limit;
  end if;

  return jsonb_build_object(
    'items', v_items,
    'has_more', v_has_more,
    'next_cursor', v_next_cursor
  );
end;
$$;

revoke all on function public.get_customer_requests_for_dossier_v1(text, text, integer)
from public, anon, authenticated, service_role;

grant execute on function public.get_customer_requests_for_dossier_v1(text, text, integer)
to authenticated;

comment on function public.get_customer_requests_for_dossier_v1(text, text, integer) is
  'Caller-scoped operational Customer Requests list for one canonically referenced dossier with keyset pagination.';