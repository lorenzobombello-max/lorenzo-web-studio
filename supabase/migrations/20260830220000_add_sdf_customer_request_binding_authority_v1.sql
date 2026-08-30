alter table public.customer_requests
  alter column customer_id drop not null,
  alter column project_id drop not null;

alter table public.customer_requests
  add constraint customer_requests_binding_shape_valid check (
    (customer_id is not null and project_id is not null)
    or (customer_id is null and project_id is null)
  );

alter table public.customer_requests
  drop constraint customer_requests_authority_binding_valid,
  add constraint customer_requests_authority_binding_valid check (
    (
      internal_e2e_run_id is null
      and (
        (customer_id is not null and project_id is not null)
        or (customer_id is null and project_id is null)
      )
    )
    or
    (
      internal_e2e_run_id is not null
      and customer_id is null
      and project_id is null
      and source_feedback_id is null
      and linked_change_order_id is null
      and source = 'OPERATOR'
      and submitter_type = 'OPERATOR'
      and request_type = 'FILE_DELIVERY'
      and priority = 'LOW'
      and title = 'LWS-SMOKE-TEST-UPLOAD-LINK-20260827'
      and description = 'Synthetic internal Customer Request Upload Link capability lifecycle smoke fixture. No customer data and no file upload.'
    )
  );

create function lws_internal.assert_customer_request_binding_v1(
  p_quote_request_id uuid,
  p_customer_id uuid,
  p_project_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_request_kind text;
begin
  select request_kind into v_request_kind
  from public.quote_requests
  where id = p_quote_request_id
    and record_classification = 'production';

  if not found then
    raise exception using errcode = '23514', message = 'PRODUCTION_QUOTE_REQUEST_REQUIRED';
  end if;

  if v_request_kind = 'website' then
    if p_customer_id is null or p_project_id is null or not exists (
      select 1
      from public.commercial_projects as project
      join public.commercial_customers as customer
        on customer.customer_id = project.customer_id
       and customer.acceptance_id = project.acceptance_id
      join public.quote_request_quotation_acceptances as acceptance
        on acceptance.id = project.acceptance_id
       and acceptance.issuance_id = project.quotation_issuance_id
      join public.quote_request_quotation_issuances as issuance
        on issuance.id = project.quotation_issuance_id
      join public.quote_request_quotation_approvals as approval
        on approval.id = issuance.approval_id
      join public.quote_request_intakes as intake
        on intake.id = approval.intake_id
       and intake.quote_request_id = approval.quote_request_id
      where project.project_id = p_project_id
        and project.customer_id = p_customer_id
        and approval.quote_request_id = p_quote_request_id
        and intake.quote_request_id = p_quote_request_id
    ) then
      raise exception using errcode = '23514', message = 'CUSTOMER_REQUEST_BINDING_MISMATCH';
    end if;
  elsif v_request_kind = 'slimme_documentenflow' then
    if p_customer_id is not null or p_project_id is not null or not exists (
      select 1
      from public.sdf_projects
      where quote_request_id = p_quote_request_id
    ) then
      raise exception using errcode = '23514', message = 'SDF_CUSTOMER_REQUEST_BINDING_MISMATCH';
    end if;
  else
    raise exception using errcode = '23514', message = 'CUSTOMER_REQUEST_KIND_UNSUPPORTED';
  end if;
end;
$$;

create function lws_internal.guard_customer_request_binding_v1()
returns trigger
language plpgsql
set search_path = lws_internal, pg_catalog
as $$
begin
  if new.internal_e2e_run_id is not null then
    return new;
  end if;

  perform lws_internal.assert_customer_request_binding_v1(
    new.quote_request_id,
    new.customer_id,
    new.project_id
  );
  return new;
end;
$$;

create trigger trg_customer_requests_binding_guard
before insert or update of quote_request_id, customer_id, project_id
on public.customer_requests
for each row execute function lws_internal.guard_customer_request_binding_v1();

create or replace function lws_internal.create_customer_request_core_v1(
  p_quote_request_id uuid,
  p_customer_id uuid,
  p_project_id uuid,
  p_source_feedback_id uuid,
  p_linked_change_order_id uuid,
  p_idempotency_key uuid,
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = lws_internal, public, extensions, pg_catalog
as $$
declare
  v_allowed_keys constant text[] := array[
    'source','request_type','title','description','priority',
    'submitted_at','submitter_type'
  ];
  v_fingerprint text;
  v_old lws_internal.customer_request_commands%rowtype;
  v_source text := p_input->>'source';
  v_request_type text := p_input->>'request_type';
  v_title text := btrim(p_input->>'title');
  v_description text := btrim(p_input->>'description');
  v_priority text := nullif(p_input->>'priority', '');
  v_submitted_at timestamptz;
  v_server_submitted_at boolean := not (p_input ? 'submitted_at');
  v_submitter_type text := p_input->>'submitter_type';
  v_year smallint;
  v_sequence integer;
  v_request_id uuid := gen_random_uuid();
  v_reference text;
  v_result jsonb;
begin
  if p_idempotency_key is null or jsonb_typeof(p_input) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST';
  end if;
  if p_input ? 'request_reference' then
    raise exception using errcode = '22023', message = 'CLIENT_REQUEST_REFERENCE_FORBIDDEN';
  end if;
  if exists (select 1 from jsonb_object_keys(p_input) as input_key(key) where not input_key.key = any(v_allowed_keys)) then
    raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST';
  end if;

  if v_server_submitted_at then
    if p_customer_id is not null then
      raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST';
    end if;
    v_submitted_at := clock_timestamp();
  else
    begin
      v_submitted_at := (p_input->>'submitted_at')::timestamptz;
    exception when others then
      raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST';
    end;
  end if;

  if v_source not in ('CUSTOMER_PORTAL','CUSTOMER_FEEDBACK','OPERATOR')
     or v_request_type not in (
       'CONTENT_CHANGE','DESIGN_CHANGE','TECHNICAL_CHANGE','NEW_FEATURE',
       'CORRECTION','FILE_DELIVERY','OTHER'
     )
     or v_submitter_type not in ('CUSTOMER','OPERATOR','SYSTEM')
     or length(v_title) not between 1 and 160
     or length(v_description) not between 1 and 4000
     or (v_priority is not null and v_priority not in ('LOW','NORMAL','HIGH','URGENT'))
     or v_submitted_at is null then
    raise exception using errcode = '23514', message = 'INVALID_CUSTOMER_REQUEST';
  end if;

  v_fingerprint := lws_internal.customer_request_fingerprint_v1(jsonb_build_object(
    'quote_request_id', p_quote_request_id,
    'customer_id', p_customer_id,
    'project_id', p_project_id,
    'source_feedback_id', p_source_feedback_id,
    'linked_change_order_id', p_linked_change_order_id,
    'source', v_source,
    'request_type', v_request_type,
    'title', v_title,
    'description', v_description,
    'priority', v_priority,
    'submitted_at', case when v_server_submitted_at then 'SERVER' else v_submitted_at::text end,
    'submitter_type', v_submitter_type
  ));

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_old
  from lws_internal.customer_request_commands
  where idempotency_key = p_idempotency_key;
  if found then
    if v_old.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_old.result_payload || jsonb_build_object('replayed', true);
  end if;

  perform lws_internal.assert_customer_request_binding_v1(
    p_quote_request_id,
    p_customer_id,
    p_project_id
  );

  if p_customer_id is null then
    if p_source_feedback_id is not null or p_linked_change_order_id is not null then
      raise exception using errcode = '23514', message = 'SDF_CUSTOMER_REQUEST_RELATION_FORBIDDEN';
    end if;
  else
    if p_source_feedback_id is not null and not exists (
      select 1 from public.customer_feedback
      where feedback_id = p_source_feedback_id and project_id = p_project_id
    ) then
      raise exception using errcode = '23514', message = 'CUSTOMER_REQUEST_FEEDBACK_MISMATCH';
    end if;

    if p_linked_change_order_id is not null and not exists (
      select 1
      from public.change_orders as change_order
      join public.commercial_projects as project
        on project.project_id = change_order.project_id
       and project.quotation_issuance_id = change_order.original_quotation_issuance_id
      where change_order.change_order_id = p_linked_change_order_id
        and change_order.project_id = p_project_id
    ) then
      raise exception using errcode = '23514', message = 'CUSTOMER_REQUEST_CHANGE_ORDER_MISMATCH';
    end if;
  end if;

  v_year := extract(year from v_submitted_at at time zone 'Europe/Brussels')::smallint;
  insert into lws_internal.customer_request_reference_counters as counter(reference_year, last_value)
  values (v_year, 1)
  on conflict (reference_year) do update
    set last_value = counter.last_value + 1
  returning last_value into v_sequence;
  if v_sequence > 9999 then
    raise exception using errcode = '22003', message = 'CUSTOMER_REQUEST_REFERENCE_SEQUENCE_EXHAUSTED';
  end if;
  v_reference := format('LWS-VRZ-%s-%s', v_year, lpad(v_sequence::text, 4, '0'));

  insert into public.customer_requests(
    request_id, request_reference, quote_request_id, customer_id, project_id,
    source, request_type, title, description, status, priority,
    submitted_at, submitter_type, source_feedback_id, linked_change_order_id
  ) values (
    v_request_id, v_reference, p_quote_request_id, p_customer_id, p_project_id,
    v_source, v_request_type, v_title, v_description, 'NEW', v_priority,
    v_submitted_at, v_submitter_type, p_source_feedback_id, p_linked_change_order_id
  );

  insert into public.customer_request_events(request_id, event_type, request_revision, payload)
  values (
    v_request_id, 'CREATED', 0,
    jsonb_strip_nulls(jsonb_build_object(
      'source', v_source,
      'request_type', v_request_type,
      'submitter_type', v_submitter_type,
      'source_feedback_id', p_source_feedback_id,
      'linked_change_order_id', p_linked_change_order_id
    ))
  );

  v_result := jsonb_build_object(
    'request_id', v_request_id,
    'request_reference', v_reference,
    'status', 'NEW',
    'revision', 0,
    'replayed', false
  );
  insert into lws_internal.customer_request_commands(
    idempotency_key, request_id, command_type, request_fingerprint, result_payload
  ) values (
    p_idempotency_key, v_request_id, 'CREATE', v_fingerprint, v_result
  );
  return v_result;
end;
$$;

create function public.create_sdf_customer_request_v1(
  p_quote_request_id uuid,
  p_idempotency_key uuid,
  p_request_type text,
  p_title text,
  p_description text,
  p_priority text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_request public.quote_requests%rowtype;
  v_allowed boolean := false;
begin
  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select * into v_operator
  from public.commercial_operators
  where auth_user_id = v_subject
  for share;

  if not found then raise exception using errcode = '42501', message = 'UNKNOWN_OPERATOR'; end if;
  if v_operator.status = 'DISABLED' then raise exception using errcode = '42501', message = 'OPERATOR_DISABLED'; end if;
  if v_operator.status = 'REVOKED' then raise exception using errcode = '42501', message = 'OPERATOR_REVOKED'; end if;
  if v_operator.status <> 'ACTIVE' then raise exception using errcode = '42501', message = 'OPERATOR_INACTIVE'; end if;

  select * into v_request
  from public.quote_requests
  where id = p_quote_request_id
    and record_classification = 'production'
  for share;

  if not found or v_request.request_kind <> 'slimme_documentenflow' then
    raise exception using errcode = '42501', message = 'SDF_CUSTOMER_REQUEST_ACCESS_DENIED';
  end if;

  if v_operator.role in ('owner', 'operations_manager') then
    v_allowed := true;
  elsif v_operator.role = 'operator' then
    select true into v_allowed
    from lws_internal.operator_dossier_assignments as assignment
    where assignment.quote_request_id = p_quote_request_id
      and assignment.assignee_operator_id = v_operator.operator_id
    for share;
  end if;

  if not coalesce(v_allowed, false) then
    raise exception using errcode = '42501', message = 'SDF_CUSTOMER_REQUEST_ACCESS_DENIED';
  end if;

  return lws_internal.create_customer_request_core_v1(
    p_quote_request_id,
    null,
    null,
    null,
    null,
    p_idempotency_key,
    jsonb_build_object(
      'source', 'OPERATOR',
      'request_type', p_request_type,
      'title', p_title,
      'description', p_description,
      'priority', p_priority,
      'submitter_type', 'OPERATOR'
    )
  );
end;
$$;

revoke all on function lws_internal.assert_customer_request_binding_v1(uuid, uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_customer_request_binding_v1()
from public, anon, authenticated, service_role;
revoke all on function public.create_sdf_customer_request_v1(uuid, uuid, text, text, text, text)
from public, anon, authenticated, service_role;
grant execute on function public.create_sdf_customer_request_v1(uuid, uuid, text, text, text, text)
to authenticated;

comment on function lws_internal.assert_customer_request_binding_v1(uuid, uuid, uuid) is
  'Canonical cross-product binding guard: Website requests require their existing commercial customer/project chain; SDF requests require a matching SDF project and no Website customer/project identities.';
comment on function public.create_sdf_customer_request_v1(uuid, uuid, text, text, text, text) is
  'Authenticated operator authority for creating one idempotent operational Customer Request under a canonical SDF quote request. Request kind is derived server-side.';
