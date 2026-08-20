create function public.list_operator_applications_v1(
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
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
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status = 'DISABLED' then raise exception using errcode = '42501', message = 'OPERATOR_DISABLED'; end if;
  if v_operator.status = 'REVOKED' then raise exception using errcode = '42501', message = 'OPERATOR_REVOKED'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;
  if v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'APPLICATION_SCOPE_DENIED';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 200 or p_offset is null or p_offset < 0 then
    raise exception using errcode = '22023', message = 'INVALID_PAGINATION';
  end if;

  return coalesce((
    select jsonb_agg(to_jsonb(application_row) order by application_row.submitted_at desc)
    from (
      select
        qr.id as quote_request_id,
        qr.application_reference,
        qr.name,
        qr.company,
        qr.email,
        qr.website_type,
        qr.budget,
        qr.timing,
        intake.status::text as intake_status,
        intake.submitted_at,
        acceptance.id as acceptance_id,
        acceptance.quotation_number,
        acceptance.accepted_at,
        project.project_id,
        project.current_state as project_state,
        project.revision as project_revision
      from public.quote_requests as qr
      join public.quote_request_intakes as intake on intake.quote_request_id = qr.id
      left join lateral (
        select accepted.id, accepted.quotation_number, accepted.accepted_at
        from public.quote_request_quotation_approvals as approval
        join public.quote_request_quotation_issuances as issuance on issuance.approval_id = approval.id
        join public.quote_request_quotation_acceptances as accepted on accepted.issuance_id = issuance.id
        where approval.quote_request_id = qr.id
        order by accepted.accepted_at desc
        limit 1
      ) as acceptance on true
      left join public.commercial_projects as project on project.acceptance_id = acceptance.id
      where intake.status in ('submitted', 'reviewed')
      order by intake.submitted_at desc
      limit p_limit offset p_offset
    ) as application_row
  ), '[]'::jsonb);
end;
$$;

create function public.get_operator_application_v1(
  p_quote_request_id uuid default null,
  p_application_reference text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_result jsonb;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status = 'DISABLED' then raise exception using errcode = '42501', message = 'OPERATOR_DISABLED'; end if;
  if v_operator.status = 'REVOKED' then raise exception using errcode = '42501', message = 'OPERATOR_REVOKED'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;
  if v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'APPLICATION_SCOPE_DENIED';
  end if;
  if (p_quote_request_id is null) = (p_application_reference is null) then
    raise exception using errcode = '22023', message = 'EXACTLY_ONE_APPLICATION_LOCATOR_REQUIRED';
  end if;
  if p_application_reference is not null
     and p_application_reference !~ '^LWS-AAN-[0-9]{4}-[0-9]{4}$' then
    raise exception using errcode = '22023', message = 'INVALID_APPLICATION_REFERENCE';
  end if;

  select jsonb_build_object(
    'quote_request_id', qr.id,
    'application_reference', qr.application_reference,
    'name', qr.name,
    'company', qr.company,
    'email', qr.email,
    'phone', qr.phone,
    'website_type', qr.website_type,
    'budget', qr.budget,
    'timing', qr.timing,
    'description', qr.description,
    'intake_status', intake.status,
    'submitted_at', intake.submitted_at,
    'acceptance', case when acceptance.id is null then null else jsonb_build_object(
      'acceptance_id', acceptance.id,
      'quotation_number', acceptance.quotation_number,
      'quotation_version', acceptance.quotation_version,
      'customer_legal_name', acceptance.customer_legal_name,
      'accepted_at', acceptance.accepted_at
    ) end,
    'project', case when project.project_id is null then null else jsonb_build_object(
      'project_id', project.project_id,
      'current_state', project.current_state,
      'revision', project.revision,
      'accepted_total_minor', project.accepted_total_minor,
      'm1_minor', project.m1_minor,
      'm2_minor', project.m2_minor,
      'm3_minor', project.m3_minor
    ) end
  ) into v_result
  from public.quote_requests as qr
  join public.quote_request_intakes as intake on intake.quote_request_id = qr.id
  left join lateral (
    select accepted.*
    from public.quote_request_quotation_approvals as approval
    join public.quote_request_quotation_issuances as issuance on issuance.approval_id = approval.id
    join public.quote_request_quotation_acceptances as accepted on accepted.issuance_id = issuance.id
    where approval.quote_request_id = qr.id
    order by accepted.accepted_at desc
    limit 1
  ) as acceptance on true
  left join public.commercial_projects as project on project.acceptance_id = acceptance.id
  where intake.status in ('submitted', 'reviewed')
    and (p_quote_request_id is null or qr.id = p_quote_request_id)
    and (p_application_reference is null or qr.application_reference = p_application_reference);

  if v_result is null then
    raise exception using errcode = 'P0001', message = 'APPLICATION_NOT_FOUND';
  end if;
  return v_result;
end;
$$;

create function public.promote_operator_application_v1(
  p_idempotency_key uuid,
  p_quote_request_id uuid default null,
  p_application_reference text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_acceptance_id uuid;
  v_total_minor bigint;
  v_project public.commercial_projects%rowtype;
  v_result jsonb;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;
  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject;
  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status = 'DISABLED' then raise exception using errcode = '42501', message = 'OPERATOR_DISABLED'; end if;
  if v_operator.status = 'REVOKED' then raise exception using errcode = '42501', message = 'OPERATOR_REVOKED'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;
  if v_operator.role not in ('owner', 'admin') then
    raise exception using errcode = '42501', message = 'APPLICATION_SCOPE_DENIED';
  end if;
  if p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if (p_quote_request_id is null) = (p_application_reference is null) then
    raise exception using errcode = '22023', message = 'EXACTLY_ONE_APPLICATION_LOCATOR_REQUIRED';
  end if;
  if p_application_reference is not null
     and p_application_reference !~ '^LWS-AAN-[0-9]{4}-[0-9]{4}$' then
    raise exception using errcode = '22023', message = 'INVALID_APPLICATION_REFERENCE';
  end if;

  select accepted.id,
    (approval.approved_payload->'totals'->>'one_time_subtotal_minor')::bigint
  into v_acceptance_id, v_total_minor
  from public.quote_requests as qr
  join public.quote_request_intakes as intake on intake.quote_request_id = qr.id
  join public.quote_request_quotation_approvals as approval on approval.quote_request_id = qr.id
  join public.quote_request_quotation_issuances as issuance on issuance.approval_id = approval.id
  join public.quote_request_quotation_acceptances as accepted on accepted.issuance_id = issuance.id
  where intake.status in ('submitted', 'reviewed')
    and (p_quote_request_id is null or qr.id = p_quote_request_id)
    and (p_application_reference is null or qr.application_reference = p_application_reference)
  order by accepted.accepted_at desc
  limit 1;

  if v_acceptance_id is null then
    raise exception using errcode = 'P0001', message = 'APPLICATION_NOT_ACCEPTED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_acceptance_id::text, 0));

  select * into v_project
  from public.commercial_projects
  where acceptance_id = v_acceptance_id;
  if found then
    return jsonb_build_object(
      'project_id', v_project.project_id,
      'resulting_state', v_project.current_state,
      'revision', v_project.revision,
      'accepted_total_minor', v_project.accepted_total_minor,
      'was_created', false
    );
  end if;

  v_result := public.initialize_commercial_project_from_acceptance_v1(
    gen_random_uuid(),
    v_acceptance_id,
    v_total_minor,
    p_idempotency_key
  );
  return v_result || jsonb_build_object('was_created', true);
end;
$$;

revoke all on function public.list_operator_applications_v1(integer, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.get_operator_application_v1(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.promote_operator_application_v1(uuid, uuid, text)
  from public, anon, authenticated, service_role;

grant execute on function public.list_operator_applications_v1(integer, integer) to authenticated;
grant execute on function public.get_operator_application_v1(uuid, text) to authenticated;
grant execute on function public.promote_operator_application_v1(uuid, uuid, text) to authenticated;

comment on function public.list_operator_applications_v1(integer, integer) is
  'Owner/admin-only submitted application list. Caller identity is derived from auth.uid(); application_reference is a locator only.';
comment on function public.get_operator_application_v1(uuid, text) is
  'Owner/admin-only submitted application detail by exactly one internal or human-readable locator.';
comment on function public.promote_operator_application_v1(uuid, uuid, text) is
  'Owner/admin-only accepted-application promotion. Serializes by acceptance and delegates project creation to initialize_commercial_project_from_acceptance_v1.';