create function public.start_website_concept_v1(
  p_quote_request_id uuid,
  p_expected_website_work_revision bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_subject uuid := auth.uid();
  v_operator public.commercial_operators%rowtype;
  v_request public.quote_requests%rowtype;
  v_existing public.website_concept_idempotency_ledger%rowtype;
  v_website_work jsonb;
  v_briefing_status text;
  v_fingerprint character(64);
  v_concept_id uuid := extensions.gen_random_uuid();
  v_website_work_context_id uuid := extensions.gen_random_uuid();
begin
  if p_quote_request_id is null
     or p_expected_website_work_revision is null
     or p_expected_website_work_revision < 1
     or p_idempotency_key is null then
    raise exception using
      errcode = '22023',
      message = 'INVALID_WEBSITE_CONCEPT_START_COMMAND';
  end if;

  if v_subject is null then
    raise exception using errcode = '42501', message = 'HUMAN_JWT_REQUIRED';
  end if;

  select operator.*
  into v_operator
  from public.commercial_operators as operator
  where operator.auth_user_id = v_subject;

  if not found
     or v_operator.status <> 'ACTIVE'
     or v_operator.role <> 'owner' then
    raise exception using
      errcode = '42501',
      message = 'WEBSITE_CONCEPT_OWNER_REQUIRED';
  end if;

  perform lws_internal.assert_operator_aal2_v1();

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'authority_version', 'website_concept_start_v1',
    'actor_id', v_operator.operator_id,
    'command_type', 'START_WEBSITE_CONCEPT',
    'quote_request_id', p_quote_request_id,
    'expected_website_work_revision', p_expected_website_work_revision
  )::text, 'UTF8'), 'sha256'), 'hex')::character(64);

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'WEBSITE_CONCEPT_START:' || v_operator.operator_id::text
      || ':' || p_idempotency_key::text,
    0
  ));

  select ledger.*
  into v_existing
  from public.website_concept_idempotency_ledger as ledger
  where ledger.actor_id = v_operator.operator_id
    and ledger.command_type = 'START_WEBSITE_CONCEPT'
    and ledger.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_fingerprint <> v_fingerprint then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return v_existing.result_payload || jsonb_build_object('replayed', true);
  end if;

  select request.*
  into v_request
  from public.quote_requests as request
  where request.id = p_quote_request_id
  for update;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'WEBSITE_CONCEPT_DOSSIER_NOT_FOUND';
  end if;

  if exists (
    select 1
    from public.website_concepts as concept
    where concept.quote_request_id = p_quote_request_id
  ) or exists (
    select 1
    from public.website_work_contexts as context
    where context.quote_request_id = p_quote_request_id
  ) or exists (
    select 1
    from public.commercial_projects as project
    join public.quote_request_quotation_acceptances as acceptance
      on acceptance.id = project.acceptance_id
     and acceptance.issuance_id = project.quotation_issuance_id
    join public.quote_request_quotation_issuances as issuance
      on issuance.id = project.quotation_issuance_id
     and issuance.status = 'ISSUED'
    join public.quote_request_quotation_approvals as approval
      on approval.id = issuance.approval_id
    where approval.quote_request_id = p_quote_request_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_CONCEPT_ALREADY_EXISTS';
  end if;

  v_website_work := public.get_operator_website_work_v1(p_quote_request_id);

  if v_website_work->>'state' <> 'NONE'
     or not (v_website_work->'permitted_actions' ? 'CAN_START_WEBSITE_CONCEPT') then
    raise exception using
      errcode = 'P0001',
      message = 'WEBSITE_CONCEPT_NOT_ELIGIBLE';
  end if;

  if (v_website_work->>'revision')::bigint
       <> p_expected_website_work_revision then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;

  v_briefing_status :=
    lws_internal.website_briefing_status_v1(p_quote_request_id);

  set constraints
    trg_website_concepts_binding,
    trg_website_work_contexts_binding
  deferred;
  perform set_config('lws.website_concept_command', 'on', true);

  insert into public.website_concepts(
    concept_id,
    quote_request_id,
    mode,
    briefing_status,
    commercially_released,
    concept_status,
    revision,
    created_by
  ) values (
    v_concept_id,
    p_quote_request_id,
    'PRE_PROJECT',
    v_briefing_status,
    false,
    'ACTIVE',
    1,
    v_operator.operator_id
  );

  insert into public.website_work_contexts(
    website_work_context_id,
    quote_request_id,
    concept_id,
    project_id,
    phase,
    revision
  ) values (
    v_website_work_context_id,
    p_quote_request_id,
    v_concept_id,
    null,
    'PRE_PROJECT',
    1
  );

  insert into public.website_concept_events(
    concept_id,
    website_work_context_id,
    quote_request_id,
    event_type,
    actor_id,
    actor_role,
    command_id,
    metadata
  ) values (
    v_concept_id,
    v_website_work_context_id,
    p_quote_request_id,
    'WEBSITE_CONCEPT_STARTED',
    v_operator.operator_id,
    'owner',
    p_idempotency_key,
    jsonb_build_object(
      'authority_version', 'website_concept_start_v1',
      'briefing_status', v_briefing_status,
      'expected_website_work_revision', p_expected_website_work_revision
    )
  );

  v_website_work := public.get_operator_website_work_v1(p_quote_request_id);

  insert into public.website_concept_idempotency_ledger(
    actor_id,
    quote_request_id,
    command_type,
    idempotency_key,
    request_fingerprint,
    result_reference,
    result_payload
  ) values (
    v_operator.operator_id,
    p_quote_request_id,
    'START_WEBSITE_CONCEPT',
    p_idempotency_key,
    v_fingerprint,
    v_concept_id::text,
    v_website_work
  );

  set constraints
    trg_website_concepts_binding,
    trg_website_work_contexts_binding
  immediate;
  perform set_config('lws.website_concept_command', '', true);

  return v_website_work || jsonb_build_object('replayed', false);
exception
  when others then
    perform set_config('lws.website_concept_command', '', true);
    raise;
end;
$$;

revoke all on function public.start_website_concept_v1(uuid, bigint, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.start_website_concept_v1(uuid, bigint, uuid)
to authenticated;

comment on function public.start_website_concept_v1(uuid, bigint, uuid) is
  'Owner-only AAL2 command that atomically starts one non-commercial Website concept and stable work context.';