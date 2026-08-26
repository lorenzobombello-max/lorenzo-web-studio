create schema if not exists lws_internal authorization postgres;
revoke all on schema lws_internal from public, anon, authenticated, service_role;

create table lws_internal.customer_request_reference_counters (
  reference_year smallint primary key,
  last_value integer not null,
  constraint customer_request_reference_counters_year_valid
    check (reference_year between 2026 and 9999),
  constraint customer_request_reference_counters_value_valid
    check (last_value between 1 and 9999)
);

create table public.customer_requests (
  request_id uuid primary key default gen_random_uuid(),
  request_reference text not null unique,
  quote_request_id uuid not null references public.quote_requests(id),
  customer_id uuid not null references public.commercial_customers(customer_id),
  project_id uuid not null references public.commercial_projects(project_id),
  source text not null check (source in ('CUSTOMER_PORTAL','CUSTOMER_FEEDBACK','OPERATOR')),
  request_type text not null check (request_type in (
    'CONTENT_CHANGE','DESIGN_CHANGE','TECHNICAL_CHANGE','NEW_FEATURE',
    'CORRECTION','FILE_DELIVERY','OTHER'
  )),
  title text not null check (length(title) between 1 and 160 and title = btrim(title)),
  description text not null check (length(description) between 1 and 4000 and description = btrim(description)),
  status text not null check (status in (
    'NEW','TRIAGED','IN_PROGRESS','WAITING_CUSTOMER',
    'WAITING_CHANGE_ORDER','RESOLVED','CANCELLED'
  )),
  priority text check (priority in ('LOW','NORMAL','HIGH','URGENT')),
  submitted_at timestamptz not null,
  submitter_type text not null check (submitter_type in ('CUSTOMER','OPERATOR','SYSTEM')),
  source_feedback_id uuid unique references public.customer_feedback(feedback_id),
  linked_change_order_id uuid unique references public.change_orders(change_order_id),
  resolution_summary text check (
    resolution_summary is null
    or (length(resolution_summary) between 1 and 2000 and resolution_summary = btrim(resolution_summary))
  ),
  resolved_at timestamptz,
  revision bigint not null default 0 check (revision >= 0),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint customer_requests_reference_format_valid
    check (request_reference ~ '^LWS-VRZ-[0-9]{4}-[0-9]{4}$'),
  constraint customer_requests_resolution_shape_valid check (
    (status = 'RESOLVED' and resolution_summary is not null and resolved_at is not null)
    or (status <> 'RESOLVED' and resolution_summary is null and resolved_at is null)
  )
);

create table public.customer_request_events (
  event_id bigint generated always as identity primary key,
  request_id uuid not null references public.customer_requests(request_id),
  event_type text not null check (event_type in (
    'CREATED','TRIAGED','STARTED','CUSTOMER_RESPONSE_REQUIRED',
    'CUSTOMER_WAIT_ENDED','SCOPE_IMPACT_SIGNALED',
    'CHANGE_ORDER_ACCEPTED','RESOLVED','CANCELLED'
  )),
  request_revision bigint not null check (request_revision >= 0),
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default clock_timestamp(),
  unique (request_id, request_revision)
);

create table lws_internal.customer_request_commands (
  idempotency_key uuid primary key,
  request_id uuid not null references public.customer_requests(request_id),
  command_type text not null,
  request_fingerprint char(64) not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  result_payload jsonb not null,
  created_at timestamptz not null default clock_timestamp()
);

create function lws_internal.customer_request_fingerprint_v1(p_value jsonb)
returns text
language sql
immutable
set search_path = public, extensions, pg_catalog
as $$
  select encode(extensions.digest(convert_to(p_value::text, 'UTF8'), 'sha256'), 'hex')
$$;

create function lws_internal.customer_request_event_payload_safe_v1(p_payload jsonb)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  with recursive nodes(value) as (
    select p_payload
    union all
    select child.value
    from nodes
    cross join lateral (
      select object_value as value
      from jsonb_each(case jsonb_typeof(nodes.value) when 'object' then nodes.value else '{}'::jsonb end)
        as object_child(key, object_value)
      union all
      select array_value
      from jsonb_array_elements(case jsonb_typeof(nodes.value) when 'array' then nodes.value else '[]'::jsonb end)
        as array_child(array_value)
    ) as child
  )
  select jsonb_typeof(p_payload) = 'object'
    and octet_length(p_payload::text) <= 2048
    and not exists (
      select 1
      from nodes
      cross join lateral jsonb_object_keys(
        case jsonb_typeof(nodes.value) when 'object' then nodes.value else '{}'::jsonb end
      ) as object_key(key)
      where lower(object_key.key) in (
        'token','tokens','credential','credentials','secret','secrets',
        'customer_email','customer_contact','contact_data','customer_content',
        'internal_note','internal_notes','price','prices','amount','amount_minor',
        'storage_path','storage_paths','path'
      )
    )
$$;

alter table public.customer_request_events
  add constraint customer_request_events_payload_safe
  check (lws_internal.customer_request_event_payload_safe_v1(payload));

create function lws_internal.guard_customer_request_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'DIRECT_CUSTOMER_REQUEST_WRITE_FORBIDDEN';
  end if;
  if new.request_reference is distinct from old.request_reference then
    raise exception using errcode = '23514', message = 'CUSTOMER_REQUEST_REFERENCE_IMMUTABLE';
  end if;
  if current_setting('lws.customer_request_command', true) is distinct from 'on' then
    raise exception using errcode = '55000', message = 'DIRECT_CUSTOMER_REQUEST_WRITE_FORBIDDEN';
  end if;
  return new;
end;
$$;

create function lws_internal.guard_customer_request_events_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'CUSTOMER_REQUEST_EVENTS_APPEND_ONLY';
end;
$$;

create function lws_internal.guard_customer_request_event_payload_v1()
returns trigger
language plpgsql
set search_path = lws_internal, pg_catalog
as $$
begin
  if not lws_internal.customer_request_event_payload_safe_v1(new.payload) then
    raise exception using errcode = '23514', message = 'CUSTOMER_REQUEST_EVENT_PAYLOAD_UNSAFE';
  end if;
  return new;
end;
$$;

create function lws_internal.guard_customer_request_commands_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'CUSTOMER_REQUEST_COMMANDS_APPEND_ONLY';
end;
$$;

create trigger trg_customer_requests_guard
before update or delete on public.customer_requests
for each row execute function lws_internal.guard_customer_request_mutation_v1();

create trigger trg_customer_request_events_append_only
before update or delete on public.customer_request_events
for each row execute function lws_internal.guard_customer_request_events_v1();

create trigger trg_customer_request_event_payload_safe
before insert or update of payload on public.customer_request_events
for each row execute function lws_internal.guard_customer_request_event_payload_v1();

create trigger trg_customer_request_commands_append_only
before update or delete on lws_internal.customer_request_commands
for each row execute function lws_internal.guard_customer_request_commands_v1();

create function lws_internal.create_customer_request_core_v1(
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

  begin
    v_submitted_at := (p_input->>'submitted_at')::timestamptz;
  exception when others then
    raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST';
  end;

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
    'submitted_at', v_submitted_at,
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

  if not exists (
    select 1 from public.quote_requests
    where id = p_quote_request_id and record_classification = 'production'
  ) then
    raise exception using errcode = '23514', message = 'PRODUCTION_QUOTE_REQUEST_REQUIRED';
  end if;

  if not exists (
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

create function lws_internal.transition_customer_request_core_v1(
  p_request_id uuid,
  p_command_type text,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = lws_internal, public, extensions, pg_catalog
as $$
declare
  v_request public.customer_requests%rowtype;
  v_old lws_internal.customer_request_commands%rowtype;
  v_fingerprint text;
  v_new_status text;
  v_event_type text;
  v_priority text;
  v_resolution_summary text;
  v_change_order_id uuid;
  v_result jsonb;
begin
  if p_request_id is null or p_idempotency_key is null
     or p_expected_revision < 0 or jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST_COMMAND';
  end if;

  v_fingerprint := lws_internal.customer_request_fingerprint_v1(jsonb_build_object(
    'request_id', p_request_id,
    'command_type', p_command_type,
    'expected_revision', p_expected_revision,
    'payload', p_payload
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

  select * into v_request
  from public.customer_requests
  where request_id = p_request_id
  for update;
  if not found then
    raise exception using errcode = '23503', message = 'CUSTOMER_REQUEST_NOT_FOUND';
  end if;
  if v_request.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;
  if v_request.status in ('RESOLVED','CANCELLED') then
    raise exception using errcode = 'P0001', message = 'CUSTOMER_REQUEST_TERMINAL';
  end if;

  v_new_status := v_request.status;
  v_priority := v_request.priority;
  if p_command_type = 'TRIAGE' then
    if v_request.status <> 'NEW'
       or exists (select 1 from jsonb_object_keys(p_payload) as key where key not in ('priority')) then
      raise exception using errcode = 'P0001', message = 'INVALID_CUSTOMER_REQUEST_TRANSITION';
    end if;
    v_priority := coalesce(nullif(p_payload->>'priority', ''), v_priority);
    if v_priority is not null and v_priority not in ('LOW','NORMAL','HIGH','URGENT') then
      raise exception using errcode = '23514', message = 'INVALID_CUSTOMER_REQUEST';
    end if;
    v_new_status := 'TRIAGED';
    v_event_type := 'TRIAGED';
  elsif p_command_type = 'START' then
    if v_request.status <> 'TRIAGED' or p_payload <> '{}'::jsonb then
      raise exception using errcode = 'P0001', message = 'INVALID_CUSTOMER_REQUEST_TRANSITION';
    end if;
    v_new_status := 'IN_PROGRESS';
    v_event_type := 'STARTED';
  elsif p_command_type = 'REQUIRE_CUSTOMER_RESPONSE' then
    if v_request.status <> 'IN_PROGRESS' or p_payload <> '{}'::jsonb then
      raise exception using errcode = 'P0001', message = 'INVALID_CUSTOMER_REQUEST_TRANSITION';
    end if;
    v_new_status := 'WAITING_CUSTOMER';
    v_event_type := 'CUSTOMER_RESPONSE_REQUIRED';
  elsif p_command_type = 'RESUME' then
    if v_request.status <> 'WAITING_CUSTOMER' or p_payload <> '{}'::jsonb then
      raise exception using errcode = 'P0001', message = 'INVALID_CUSTOMER_REQUEST_TRANSITION';
    end if;
    v_new_status := 'IN_PROGRESS';
    v_event_type := 'CUSTOMER_WAIT_ENDED';
  elsif p_command_type = 'SIGNAL_SCOPE_IMPACT' then
    if v_request.status not in ('TRIAGED','IN_PROGRESS')
       or p_payload - 'linked_change_order_id' <> '{}'::jsonb
       or nullif(p_payload->>'linked_change_order_id', '') is null then
      raise exception using errcode = 'P0001', message = 'INVALID_CUSTOMER_REQUEST_TRANSITION';
    end if;
    begin
      v_change_order_id := (p_payload->>'linked_change_order_id')::uuid;
    exception when others then
      raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST_COMMAND';
    end;
    if not exists (
      select 1
      from public.change_orders as change_order
      join public.commercial_projects as project
        on project.project_id = change_order.project_id
       and project.quotation_issuance_id = change_order.original_quotation_issuance_id
      where change_order.change_order_id = v_change_order_id
        and change_order.project_id = v_request.project_id
    ) then
      raise exception using errcode = '23514', message = 'CUSTOMER_REQUEST_CHANGE_ORDER_MISMATCH';
    end if;
    v_new_status := 'WAITING_CHANGE_ORDER';
    v_event_type := 'SCOPE_IMPACT_SIGNALED';
  elsif p_command_type = 'ACCEPT_CHANGE_ORDER' then
    if v_request.status <> 'WAITING_CHANGE_ORDER' or p_payload <> '{}'::jsonb
       or not exists (
         select 1
         from public.change_orders as change_order
         join public.commercial_projects as project
           on project.project_id = change_order.project_id
          and project.quotation_issuance_id = change_order.original_quotation_issuance_id
         where change_order.change_order_id = v_request.linked_change_order_id
           and change_order.project_id = v_request.project_id
           and change_order.status = 'ACCEPTED'
       ) then
      raise exception using errcode = 'P0001', message = 'INVALID_CUSTOMER_REQUEST_TRANSITION';
    end if;
    v_new_status := 'IN_PROGRESS';
    v_event_type := 'CHANGE_ORDER_ACCEPTED';
  elsif p_command_type = 'RESOLVE' then
    v_resolution_summary := btrim(p_payload->>'resolution_summary');
    if v_request.status <> 'IN_PROGRESS'
       or p_payload - 'resolution_summary' <> '{}'::jsonb
       or length(v_resolution_summary) not between 1 and 2000 then
      raise exception using errcode = 'P0001', message = 'INVALID_CUSTOMER_REQUEST_TRANSITION';
    end if;
    v_new_status := 'RESOLVED';
    v_event_type := 'RESOLVED';
  elsif p_command_type = 'CANCEL' then
    if p_payload <> '{}'::jsonb then
      raise exception using errcode = 'P0001', message = 'INVALID_CUSTOMER_REQUEST_TRANSITION';
    end if;
    v_new_status := 'CANCELLED';
    v_event_type := 'CANCELLED';
  else
    raise exception using errcode = '22023', message = 'INVALID_CUSTOMER_REQUEST_COMMAND';
  end if;

  perform set_config('lws.customer_request_command', 'on', true);
  update public.customer_requests
  set status = v_new_status,
      priority = v_priority,
      linked_change_order_id = coalesce(v_change_order_id, linked_change_order_id),
      resolution_summary = case when v_new_status = 'RESOLVED' then v_resolution_summary else resolution_summary end,
      resolved_at = case when v_new_status = 'RESOLVED' then clock_timestamp() else resolved_at end,
      revision = revision + 1,
      updated_at = clock_timestamp()
  where request_id = p_request_id;
  perform set_config('lws.customer_request_command', '', true);

  insert into public.customer_request_events(request_id, event_type, request_revision, payload)
  values (
    p_request_id,
    v_event_type,
    p_expected_revision + 1,
    jsonb_strip_nulls(jsonb_build_object(
      'previous_status', v_request.status,
      'new_status', v_new_status,
      'priority', case when v_priority is distinct from v_request.priority then v_priority end,
      'linked_change_order_id', v_change_order_id,
      'resolution_recorded', case when v_new_status = 'RESOLVED' then true end
    ))
  );

  v_result := jsonb_build_object(
    'request_id', p_request_id,
    'request_reference', v_request.request_reference,
    'status', v_new_status,
    'revision', p_expected_revision + 1,
    'replayed', false
  );
  insert into lws_internal.customer_request_commands(
    idempotency_key, request_id, command_type, request_fingerprint, result_payload
  ) values (
    p_idempotency_key, p_request_id, p_command_type, v_fingerprint, v_result
  );
  return v_result;
end;
$$;

alter table public.customer_requests enable row level security;
alter table public.customer_requests force row level security;
alter table public.customer_request_events enable row level security;
alter table public.customer_request_events force row level security;
alter table lws_internal.customer_request_reference_counters enable row level security;
alter table lws_internal.customer_request_reference_counters force row level security;
alter table lws_internal.customer_request_commands enable row level security;
alter table lws_internal.customer_request_commands force row level security;

revoke all privileges on table public.customer_requests from public, anon, authenticated, service_role;
revoke all privileges on table public.customer_request_events from public, anon, authenticated, service_role;
revoke all privileges on table lws_internal.customer_request_reference_counters from public, anon, authenticated, service_role;
revoke all privileges on table lws_internal.customer_request_commands from public, anon, authenticated, service_role;
revoke all privileges on sequence public.customer_request_events_event_id_seq from public, anon, authenticated, service_role;

revoke all on function lws_internal.customer_request_fingerprint_v1(jsonb) from public, anon, authenticated, service_role;
revoke all on function lws_internal.customer_request_event_payload_safe_v1(jsonb) from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_customer_request_mutation_v1() from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_customer_request_events_v1() from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_customer_request_event_payload_v1() from public, anon, authenticated, service_role;
revoke all on function lws_internal.guard_customer_request_commands_v1() from public, anon, authenticated, service_role;
revoke all on function lws_internal.create_customer_request_core_v1(uuid,uuid,uuid,uuid,uuid,uuid,jsonb) from public, anon, authenticated, service_role;
revoke all on function lws_internal.transition_customer_request_core_v1(uuid,text,bigint,uuid,jsonb) from public, anon, authenticated, service_role;