create function lws_internal.resolve_operator_operational_status_v2(
  p_request_kind text,
  p_intake_status text,
  p_effective_access text,
  p_project_state text,
  p_has_acceptance boolean
)
returns text
language plpgsql
stable
set search_path = pg_catalog
as $$
begin
  if p_request_kind not in ('website', 'slimme_documentenflow') then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_REQUEST_KIND';
  end if;
  if p_request_kind = 'website'
     and p_effective_access not in ('ACTIVE', 'INTERRUPTED', 'EXPIRED', 'CANCELLED') then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_EFFECTIVE_ACCESS';
  end if;
  if p_request_kind = 'slimme_documentenflow'
     and (p_intake_status is not null or p_effective_access is not null or p_project_state is not null) then
    raise exception using errcode = '22023', message = 'INVALID_SDF_OPERATIONAL_AUTHORITY';
  end if;
  if p_effective_access = 'CANCELLED' then
    return 'CANCELLED';
  end if;
  if p_project_state is not null then
    if p_project_state not in (
      'QUOTE_ACCEPTED', 'M1_PAYMENT_PENDING', 'M1_PAYMENT_RECEIVED',
      'PROJECT_RELEASED', 'PREVIEW_READY', 'M2_PAYMENT_RECEIVED',
      'FINAL_APPROVAL_RECORDED', 'FULL_PAYMENT_RECEIVED',
      'FINAL_TRANSFER_AUTHORIZED', 'DELIVERED', 'ARCHIVED'
    ) then
      raise exception using errcode = '22023', message = 'UNKNOWN_OPERATOR_PROJECT_STATE';
    end if;
    return p_project_state;
  end if;
  if p_has_acceptance then
    return 'QUOTE_ACCEPTED';
  end if;
  if p_intake_status = 'reviewed' then
    return 'REVIEWED';
  end if;
  if p_intake_status = 'submitted' or p_request_kind = 'slimme_documentenflow' then
    return 'SUBMITTED';
  end if;
  raise exception using errcode = '22023', message = 'INVALID_OPERATOR_OPERATIONAL_STATUS';
end;
$$;

create view lws_internal.operator_application_readmodel_v2 as
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
  order by accepted.accepted_at desc, accepted.id desc
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
  lws_internal.resolve_operator_operational_status_v2(
    request.request_kind,
    null,
    null,
    null,
    false
  ),
  request.created_at
from public.quote_requests as request
join lws_internal.operator_dossier_states as dossier_state
  on dossier_state.quote_request_id = request.id
where request.record_classification = 'production'
  and request.request_kind = 'slimme_documentenflow';

create function lws_internal.assert_operator_readmodel_integrity_v2()
returns void
language plpgsql
stable
security definer
set search_path = lws_internal, public, pg_catalog
as $$
begin
  if exists (
    select 1
    from public.quote_requests as request
    left join public.quote_request_intakes as intake
      on intake.quote_request_id = request.id
     and request.request_kind = 'website'
    left join lws_internal.operator_dossier_states as dossier_state
      on dossier_state.quote_request_id = request.id
    where request.record_classification = 'production'
      and (
        (request.request_kind = 'website' and intake.status in ('submitted', 'reviewed'))
        or request.request_kind = 'slimme_documentenflow'
      )
      and dossier_state.quote_request_id is null
  ) then
    raise exception using errcode = '23514', message = 'OPERATOR_DOSSIER_STATE_REQUIRED';
  end if;
end;
$$;

create function public.authorize_operator_application_reader_v2()
returns void
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
begin
  perform public.assert_internal_e2e_application_reader_v1();
end;
$$;

create function lws_internal.assert_operator_application_actor_v2(p_actor_auth_user_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
begin
  if p_actor_auth_user_id is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = p_actor_auth_user_id;
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status = 'DISABLED' then raise exception using errcode = '42501', message = 'OPERATOR_DISABLED'; end if;
  if v_operator.status = 'REVOKED' then raise exception using errcode = '42501', message = 'OPERATOR_REVOKED'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;
  if v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'APPLICATION_SCOPE_DENIED';
  end if;
end;
$$;

create function lws_internal.list_operator_applications_v2_core(
  p_actor_auth_user_id uuid,
  p_zone text default 'ACTIVE',
  p_operational_status text default null,
  p_year integer default null,
  p_quarter text default null,
  p_request_kind text default null,
  p_search text default null,
  p_cursor_date timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = lws_internal, public, auth, pg_catalog
as $$
declare
  v_search text := nullif(btrim(p_search), '');
  v_search_normalized text;
  v_search_pattern text;
  v_search_upper text;
  v_identifier_kind text;
  v_identifier_uuid uuid;
  v_from timestamptz;
  v_to timestamptz;
  v_start_month integer;
  v_items jsonb;
  v_last jsonb;
  v_has_more boolean := false;
  v_next_position jsonb;
begin
  perform lws_internal.assert_operator_application_actor_v2(p_actor_auth_user_id);
  perform lws_internal.assert_operator_readmodel_integrity_v2();

  if p_zone is null or p_zone not in ('ACTIVE', 'ARCHIVED', 'TRASHED', 'ACTIVE_ARCHIVED') then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_ZONE';
  end if;
  if p_operational_status is not null and p_operational_status not in (
    'CANCELLED', 'SUBMITTED', 'REVIEWED', 'QUOTE_ACCEPTED',
    'M1_PAYMENT_PENDING', 'M1_PAYMENT_RECEIVED', 'PROJECT_RELEASED',
    'PREVIEW_READY', 'M2_PAYMENT_RECEIVED', 'FINAL_APPROVAL_RECORDED',
    'FULL_PAYMENT_RECEIVED', 'FINAL_TRANSFER_AUTHORIZED', 'DELIVERED', 'ARCHIVED'
  ) then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_OPERATIONAL_STATUS_FILTER';
  end if;
  if p_year is not null and (p_year < 1 or p_year > 9999) then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_YEAR';
  end if;
  if p_quarter is not null and (p_quarter not in ('Q1', 'Q2', 'Q3', 'Q4') or p_year is null) then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_QUARTER';
  end if;
  if p_request_kind is not null and p_request_kind not in ('website', 'slimme_documentenflow') then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_REQUEST_KIND_FILTER';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_PAGE_LIMIT';
  end if;
  if (p_cursor_date is null) <> (p_cursor_id is null) then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_CURSOR_POSITION';
  end if;
  if v_search is not null and char_length(v_search) > 140 then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_SEARCH';
  end if;

  v_search_normalized := lower(v_search);
  v_search_upper := upper(v_search);
  v_search_pattern := replace(replace(replace(v_search_normalized, '\', '\\'), '%', '\%'), '_', '\_') || '%';

  if v_search is not null and v_search ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    v_identifier_kind := 'UUID';
    v_identifier_uuid := v_search::uuid;
  elsif v_search_upper ~ '^LWS-AAN-[0-9]{4}-[0-9]{4}$' then
    v_identifier_kind := 'APPLICATION_REFERENCE';
  elsif v_search_upper ~ '^#?[0-9A-F]{8}$' then
    v_identifier_kind := 'SUPPORT_REFERENCE';
  end if;

  if v_identifier_kind is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'quote_request_id', readmodel.quote_request_id,
      'application_reference', readmodel.application_reference,
      'support_reference', readmodel.support_reference,
      'name', readmodel.name,
      'organization', readmodel.organization,
      'request_kind', readmodel.request_kind,
      'zone', readmodel.zone,
      'operational_status', readmodel.operational_status,
      'dossier_date', readmodel.dossier_date
    )), '[]'::jsonb)
    into v_items
    from lws_internal.operator_application_readmodel_v2 as readmodel
    where (
      (p_zone = 'TRASHED' and readmodel.zone = 'TRASHED')
      or (p_zone <> 'TRASHED' and readmodel.zone in ('ACTIVE', 'ARCHIVED'))
    )
      and (
        (v_identifier_kind = 'UUID' and readmodel.quote_request_id = v_identifier_uuid)
        or (v_identifier_kind = 'APPLICATION_REFERENCE' and readmodel.application_reference = v_search_upper)
        or (v_identifier_kind = 'SUPPORT_REFERENCE'
            and readmodel.support_reference = '#' || ltrim(v_search_upper, '#'))
      );
    return jsonb_build_object('items', v_items, 'has_more', false, 'next_position', null);
  end if;

  if p_year is not null then
    v_start_month := case p_quarter when 'Q1' then 1 when 'Q2' then 4 when 'Q3' then 7 when 'Q4' then 10 else 1 end;
    v_from := make_timestamptz(p_year, v_start_month, 1, 0, 0, 0, 'UTC');
    v_to := case
      when p_quarter is null then make_timestamptz(p_year + 1, 1, 1, 0, 0, 0, 'UTC')
      when p_quarter = 'Q4' then make_timestamptz(p_year + 1, 1, 1, 0, 0, 0, 'UTC')
      else make_timestamptz(p_year, v_start_month + 3, 1, 0, 0, 0, 'UTC')
    end;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'quote_request_id', page.quote_request_id,
    'application_reference', page.application_reference,
    'support_reference', page.support_reference,
    'name', page.name,
    'organization', page.organization,
    'request_kind', page.request_kind,
    'zone', page.zone,
    'operational_status', page.operational_status,
    'dossier_date', page.dossier_date
  ) order by page.dossier_date desc, page.quote_request_id desc), '[]'::jsonb)
  into v_items
  from (
    select readmodel.*
    from lws_internal.operator_application_readmodel_v2 as readmodel
    where (
      (p_zone = 'ACTIVE_ARCHIVED' and readmodel.zone in ('ACTIVE', 'ARCHIVED'))
      or (p_zone <> 'ACTIVE_ARCHIVED' and readmodel.zone = p_zone)
    )
      and (p_operational_status is null or readmodel.operational_status = p_operational_status)
      and (p_request_kind is null or readmodel.request_kind = p_request_kind)
      and (v_from is null or (readmodel.dossier_date >= v_from and readmodel.dossier_date < v_to))
      and (
        v_search is null
        or lower(btrim(readmodel.application_reference)) like v_search_pattern escape '\'
        or lower(btrim(readmodel.name)) like v_search_pattern escape '\'
        or lower(btrim(readmodel.organization)) like v_search_pattern escape '\'
      )
      and (p_cursor_date is null or (readmodel.dossier_date, readmodel.quote_request_id) < (p_cursor_date, p_cursor_id))
    order by readmodel.dossier_date desc, readmodel.quote_request_id desc
    limit p_limit + 1
  ) as page;

  if jsonb_array_length(v_items) > p_limit then
    v_last := v_items->(p_limit - 1);
    v_has_more := true;
    v_next_position := jsonb_build_object(
      'dossier_date', v_last->>'dossier_date',
      'quote_request_id', v_last->>'quote_request_id'
    );
    v_items := v_items - p_limit;
  end if;

  return jsonb_build_object('items', v_items, 'has_more', v_has_more, 'next_position', v_next_position);
end;
$$;

create function public.list_operator_applications_v2(
  p_actor_auth_user_id uuid,
  p_zone text default 'ACTIVE',
  p_operational_status text default null,
  p_year integer default null,
  p_quarter text default null,
  p_request_kind text default null,
  p_search text default null,
  p_cursor_date timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns jsonb
language sql
stable
security definer
set search_path = lws_internal, pg_catalog
as $$
  select lws_internal.list_operator_applications_v2_core(
    p_actor_auth_user_id, p_zone, p_operational_status, p_year, p_quarter,
    p_request_kind, p_search, p_cursor_date, p_cursor_id, p_limit
  );
$$;

create function lws_internal.get_operator_dossier_facets_v2_core(
  p_actor_auth_user_id uuid,
  p_zone text default 'ACTIVE',
  p_operational_status text default null,
  p_request_kind text default null,
  p_search text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = lws_internal, public, auth, pg_catalog
as $$
declare
  v_search text := nullif(btrim(p_search), '');
  v_search_normalized text;
  v_search_pattern text;
  v_search_upper text;
  v_identifier_kind text;
  v_identifier_uuid uuid;
  v_result jsonb;
begin
  perform lws_internal.assert_operator_application_actor_v2(p_actor_auth_user_id);
  perform lws_internal.assert_operator_readmodel_integrity_v2();

  if p_zone is null or p_zone not in ('ACTIVE', 'ARCHIVED', 'TRASHED', 'ACTIVE_ARCHIVED') then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_ZONE';
  end if;
  if p_operational_status is not null and p_operational_status not in (
    'CANCELLED', 'SUBMITTED', 'REVIEWED', 'QUOTE_ACCEPTED',
    'M1_PAYMENT_PENDING', 'M1_PAYMENT_RECEIVED', 'PROJECT_RELEASED',
    'PREVIEW_READY', 'M2_PAYMENT_RECEIVED', 'FINAL_APPROVAL_RECORDED',
    'FULL_PAYMENT_RECEIVED', 'FINAL_TRANSFER_AUTHORIZED', 'DELIVERED', 'ARCHIVED'
  ) then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_OPERATIONAL_STATUS_FILTER';
  end if;
  if p_request_kind is not null and p_request_kind not in ('website', 'slimme_documentenflow') then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_REQUEST_KIND_FILTER';
  end if;
  if v_search is not null and char_length(v_search) > 140 then
    raise exception using errcode = '22023', message = 'INVALID_OPERATOR_SEARCH';
  end if;

  v_search_normalized := lower(v_search);
  v_search_upper := upper(v_search);
  v_search_pattern := replace(replace(replace(v_search_normalized, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  if v_search is not null and v_search ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    v_identifier_kind := 'UUID';
    v_identifier_uuid := v_search::uuid;
  elsif v_search_upper ~ '^LWS-AAN-[0-9]{4}-[0-9]{4}$' then
    v_identifier_kind := 'APPLICATION_REFERENCE';
  elsif v_search_upper ~ '^#?[0-9A-F]{8}$' then
    v_identifier_kind := 'SUPPORT_REFERENCE';
  end if;

  with filtered as (
    select readmodel.*
    from lws_internal.operator_application_readmodel_v2 as readmodel
    where case
      when v_identifier_kind is not null then
        (
          (p_zone = 'TRASHED' and readmodel.zone = 'TRASHED')
          or (p_zone <> 'TRASHED' and readmodel.zone in ('ACTIVE', 'ARCHIVED'))
        )
        and (
          (v_identifier_kind = 'UUID' and readmodel.quote_request_id = v_identifier_uuid)
          or (v_identifier_kind = 'APPLICATION_REFERENCE' and readmodel.application_reference = v_search_upper)
          or (v_identifier_kind = 'SUPPORT_REFERENCE' and readmodel.support_reference = '#' || ltrim(v_search_upper, '#'))
        )
      else
        (
          (p_zone = 'ACTIVE_ARCHIVED' and readmodel.zone in ('ACTIVE', 'ARCHIVED'))
          or (p_zone <> 'ACTIVE_ARCHIVED' and readmodel.zone = p_zone)
        )
        and (p_operational_status is null or readmodel.operational_status = p_operational_status)
        and (p_request_kind is null or readmodel.request_kind = p_request_kind)
        and (
          v_search is null
          or lower(btrim(readmodel.application_reference)) like v_search_pattern escape '\'
          or lower(btrim(readmodel.name)) like v_search_pattern escape '\'
          or lower(btrim(readmodel.organization)) like v_search_pattern escape '\'
        )
    end
  ), grouped as (
    select
      extract(year from dossier_date at time zone 'UTC')::integer as dossier_year,
      count(*)::bigint as total_count,
      count(*) filter (where extract(quarter from dossier_date at time zone 'UTC') = 1)::bigint as q1_count,
      count(*) filter (where extract(quarter from dossier_date at time zone 'UTC') = 2)::bigint as q2_count,
      count(*) filter (where extract(quarter from dossier_date at time zone 'UTC') = 3)::bigint as q3_count,
      count(*) filter (where extract(quarter from dossier_date at time zone 'UTC') = 4)::bigint as q4_count
    from filtered
    group by extract(year from dossier_date at time zone 'UTC')
  )
  select jsonb_build_object('years', coalesce(jsonb_agg(jsonb_build_object(
    'year', dossier_year,
    'count', total_count,
    'quarters', jsonb_build_array(
      jsonb_build_object('quarter', 'Q1', 'count', q1_count),
      jsonb_build_object('quarter', 'Q2', 'count', q2_count),
      jsonb_build_object('quarter', 'Q3', 'count', q3_count),
      jsonb_build_object('quarter', 'Q4', 'count', q4_count)
    )
  ) order by dossier_year desc), '[]'::jsonb))
  into v_result
  from grouped;

  return v_result;
end;
$$;

create function public.get_operator_dossier_facets_v2(
  p_actor_auth_user_id uuid,
  p_zone text default 'ACTIVE',
  p_operational_status text default null,
  p_request_kind text default null,
  p_search text default null
)
returns jsonb
language sql
stable
security definer
set search_path = lws_internal, pg_catalog
as $$
  select lws_internal.get_operator_dossier_facets_v2_core(
    p_actor_auth_user_id, p_zone, p_operational_status, p_request_kind, p_search
  );
$$;

create index operator_dossier_states_zone_root_idx
  on lws_internal.operator_dossier_states (state, quote_request_id);

create index quote_request_intakes_dossier_date_root_idx
  on public.quote_request_intakes (submitted_at desc, quote_request_id desc)
  where status in ('submitted', 'reviewed') and submitted_at is not null;

create index quote_requests_sdf_dossier_date_root_idx
  on public.quote_requests (created_at desc, id desc)
  where record_classification = 'production' and request_kind = 'slimme_documentenflow';

create index quote_request_intakes_access_dossier_date_root_idx
  on public.quote_request_intakes (access_state, submitted_at desc, quote_request_id desc)
  where status in ('submitted', 'reviewed') and submitted_at is not null;

create index quote_requests_operator_name_prefix_idx
  on public.quote_requests (lower(btrim(name)) text_pattern_ops)
  where record_classification = 'production';

create index quote_requests_operator_company_prefix_idx
  on public.quote_requests (lower(btrim(company)) text_pattern_ops)
  where record_classification = 'production' and company is not null;

revoke all on function lws_internal.resolve_operator_operational_status_v2(text, text, text, text, boolean)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.assert_operator_readmodel_integrity_v2()
from public, anon, authenticated, service_role;
revoke all on function lws_internal.assert_operator_application_actor_v2(uuid)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.list_operator_applications_v2_core(uuid, text, text, integer, text, text, text, timestamptz, uuid, integer)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.get_operator_dossier_facets_v2_core(uuid, text, text, text, text)
from public, anon, authenticated, service_role;
revoke all on table lws_internal.operator_application_readmodel_v2
from public, anon, authenticated, service_role;
revoke all on function public.authorize_operator_application_reader_v2()
from public, anon, authenticated, service_role;
revoke all on function public.list_operator_applications_v2(uuid, text, text, integer, text, text, text, timestamptz, uuid, integer)
from public, anon, authenticated, service_role;
revoke all on function public.get_operator_dossier_facets_v2(uuid, text, text, text, text)
from public, anon, authenticated, service_role;

grant execute on function public.authorize_operator_application_reader_v2()
to authenticated;
grant execute on function public.list_operator_applications_v2(uuid, text, text, integer, text, text, text, timestamptz, uuid, integer)
to service_role;
grant execute on function public.get_operator_dossier_facets_v2(uuid, text, text, text, text)
to service_role;

comment on view lws_internal.operator_application_readmodel_v2 is
  'Private Phase-2 dossier readmodel. Zone and operational status remain separate authoritative projections.';
comment on function public.authorize_operator_application_reader_v2() is
  'Authenticated authority-only preflight. It returns no dossier data and performs no cursor processing.';
comment on function public.list_operator_applications_v2(uuid, text, text, integer, text, text, text, timestamptz, uuid, integer) is
  'Service-role-only Phase-2 transport. The private core revalidates the supplied human actor and returns a raw keyset position.';
comment on function public.get_operator_dossier_facets_v2(uuid, text, text, text, text) is
  'Service-role-only Phase-2 facets transport with private human-actor revalidation.';