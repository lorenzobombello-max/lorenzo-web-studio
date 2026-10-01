-- W2.4.1-PDF C3 preparation: isolated TEST_ONLY dossier and deterministic post-claim hold.
-- This authority creates synthetic commercial state only. It does not prove or execute quotation,
-- invoicing, payment, delivery, customer-access, or customer-approval workflows.

create sequence public.website_delivery_pdf_c3_trial_number_seq
  as integer minvalue 1 maxvalue 9999 start 1 no cycle;
revoke all on sequence public.website_delivery_pdf_c3_trial_number_seq
from public, anon, authenticated, service_role;

create table public.website_delivery_pdf_c3_trial_fixtures (
  fixture_id uuid primary key default gen_random_uuid(),
  internal_e2e_run_id uuid not null unique references public.internal_e2e_runs(id),
  quote_request_id uuid not null unique references public.quote_requests(id),
  project_id uuid not null unique references public.commercial_projects(project_id),
  preview_version_id uuid not null unique references public.preview_versions(preview_version_id),
  idempotency_key uuid not null unique,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'CLOSED')),
  revision integer not null default 0 check (revision >= 0),
  created_by_operator_id uuid not null references public.commercial_operators(operator_id),
  created_at timestamptz not null default clock_timestamp(),
  closed_at timestamptz,
  close_idempotency_key uuid unique,
  constraint website_delivery_pdf_c3_trial_terminal_shape check (
    (status = 'ACTIVE' and closed_at is null and close_idempotency_key is null)
    or (status = 'CLOSED' and closed_at is not null and close_idempotency_key is not null)
  )
);

create table public.website_delivery_pdf_c3_trial_fixture_events (
  event_id bigint generated always as identity primary key,
  fixture_id uuid not null references public.website_delivery_pdf_c3_trial_fixtures(fixture_id),
  event_type text not null check (event_type in ('CREATED', 'CLOSED')),
  resulting_status text not null check (resulting_status in ('ACTIVE', 'CLOSED')),
  resulting_revision integer not null check (resulting_revision >= 0),
  actor_operator_id uuid not null references public.commercial_operators(operator_id),
  idempotency_key uuid not null,
  occurred_at timestamptz not null default clock_timestamp(),
  unique (fixture_id, idempotency_key)
);

create function public.guard_website_delivery_pdf_c3_trial_fixture_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'WEBSITE_DELIVERY_PDF_C3_TRIAL_FIXTURE_IMMUTABLE';
  end if;
  if current_setting('lws.website_delivery_pdf_c3_trial_command', true) = 'close'
     and old.status = 'ACTIVE' and new.status = 'CLOSED'
     and new.fixture_id = old.fixture_id
     and new.internal_e2e_run_id = old.internal_e2e_run_id
     and new.quote_request_id = old.quote_request_id
     and new.project_id = old.project_id
     and new.preview_version_id = old.preview_version_id
     and new.idempotency_key = old.idempotency_key
     and new.created_by_operator_id = old.created_by_operator_id
     and new.created_at = old.created_at
     and new.revision = old.revision + 1
     and new.closed_at is not null
     and new.close_idempotency_key is not null then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'WEBSITE_DELIVERY_PDF_C3_TRIAL_FIXTURE_IMMUTABLE';
end;
$$;

create function public.prevent_website_delivery_pdf_c3_trial_event_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception using errcode = '55000', message = 'WEBSITE_DELIVERY_PDF_C3_TRIAL_EVENT_IMMUTABLE';
end;
$$;

create trigger trg_website_delivery_pdf_c3_trial_fixtures_guard
before update or delete on public.website_delivery_pdf_c3_trial_fixtures
for each row execute function public.guard_website_delivery_pdf_c3_trial_fixture_v1();

create trigger trg_website_delivery_pdf_c3_trial_fixture_events_immutable
before update or delete on public.website_delivery_pdf_c3_trial_fixture_events
for each row execute function public.prevent_website_delivery_pdf_c3_trial_event_mutation_v1();

alter table public.website_delivery_pdf_c3_trial_fixtures enable row level security;
alter table public.website_delivery_pdf_c3_trial_fixtures force row level security;
alter table public.website_delivery_pdf_c3_trial_fixture_events enable row level security;
alter table public.website_delivery_pdf_c3_trial_fixture_events force row level security;
revoke all on table public.website_delivery_pdf_c3_trial_fixtures,
  public.website_delivery_pdf_c3_trial_fixture_events
from public, anon, authenticated, service_role;

create or replace function public.prevent_internal_e2e_quotation_write()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  if exists (
    select 1 from public.quote_requests
    where id = new.quote_request_id and record_classification = 'internal_e2e'
  ) and current_setting('lws.website_delivery_pdf_c3_trial_command', true) <> 'create' then
    raise exception using errcode = 'P0001', message = 'INTERNAL_E2E_QUOTATION_DENIED';
  end if;
  return new;
end;
$$;

create function public.create_website_delivery_pdf_c3_trial_fixture_v1(
  p_internal_e2e_run_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, extensions, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_run public.internal_e2e_runs%rowtype;
  v_fixture public.website_delivery_pdf_c3_trial_fixtures%rowtype;
  v_request public.quote_requests%rowtype;
  v_intake_id uuid;
  v_snapshot_id uuid := gen_random_uuid();
  v_draft_id uuid := gen_random_uuid();
  v_approval_id uuid := gen_random_uuid();
  v_issuance_id uuid := gen_random_uuid();
  v_acceptance_id uuid := gen_random_uuid();
  v_customer_id uuid := gen_random_uuid();
  v_project_id uuid := gen_random_uuid();
  v_preview_version_id uuid := gen_random_uuid();
  v_quotation_number text;
  v_approval_payload jsonb;
  v_acceptance_payload jsonb;
  v_terms_sha256 text;
  v_accepted_at timestamptz := clock_timestamp();
  v_accepted_at_text text;
begin
  if p_internal_e2e_run_id is null or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_PDF_C3_TRIAL_INPUT_INVALID';
  end if;
  v_operator := lws_internal.require_website_repository_owner_v1();

  select * into v_fixture
  from public.website_delivery_pdf_c3_trial_fixtures
  where idempotency_key = p_idempotency_key;
  if found then
    if v_fixture.internal_e2e_run_id <> p_internal_e2e_run_id then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'fixture_id', v_fixture.fixture_id,
      'internal_e2e_run_id', v_fixture.internal_e2e_run_id,
      'quote_request_id', v_fixture.quote_request_id,
      'project_id', v_fixture.project_id,
      'preview_version_id', v_fixture.preview_version_id,
      'status', v_fixture.status,
      'revision', v_fixture.revision,
      'was_created', false,
      'synthetic_scope', 'PDF_RECOVERY_ONLY'
    );
  end if;

  select * into v_run from public.internal_e2e_runs
  where id = p_internal_e2e_run_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'INTERNAL_E2E_RUN_NOT_FOUND';
  end if;
  if v_run.status <> 'ACTIVE' or v_run.expires_at <= clock_timestamp() then
    raise exception using errcode = 'P0001', message = 'INTERNAL_E2E_RUN_NOT_ACTIVE';
  end if;
  select * into v_request from public.quote_requests
  where id = v_run.quote_request_id for update;
  if not found or v_request.record_classification <> 'internal_e2e' then
    raise exception using errcode = 'P0001', message = 'INTERNAL_E2E_CLASSIFICATION_REQUIRED';
  end if;
  if exists (
    select 1 from public.website_delivery_pdf_c3_trial_fixtures
    where internal_e2e_run_id = v_run.id
  ) then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_C3_TRIAL_FIXTURE_EXISTS';
  end if;
  select id into strict v_intake_id from public.quote_request_intakes
  where quote_request_id = v_run.quote_request_id;

  v_quotation_number := 'LWS-OFF-2099-' ||
    lpad(nextval('public.website_delivery_pdf_c3_trial_number_seq')::text, 4, '0');
  v_accepted_at_text := to_char(v_accepted_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
  select rtrim(content_sha256) into strict v_terms_sha256
  from public.quotation_acceptance_terms_authorities
  where terms_id = 'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT'
    and terms_version = '1.0.0-technical' and status = 'APPROVED';

  insert into public.quote_request_pricing_snapshots(
    id, intake_id, snapshot_contract_version, config_version, config_hash,
    normalized_evidence, calculation, package_advice, budget_evaluation
  ) values (
    v_snapshot_id, v_intake_id, 2, 'C3-TEST-ONLY-v1', repeat('1', 64),
    '{"standardPages":["test-only"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}'::jsonb,
    '{"basis":"c3_test_only","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":10000,"containsFromPricing":false,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[]}'::jsonb,
    '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}'::jsonb,
    '{"contractVersion":2,"evidenceProvenance":"internal_e2e","categoryScheme":"internal_e2e","categoryCode":"test_only","originalLabel":"TEST_ONLY","status":"test_only","outsideBudgetWishes":false}'::jsonb
  );

  v_approval_payload := jsonb_build_object(
    'contract_version', 1,
    'source_quote_request_id', v_run.quote_request_id,
    'source_intake_id', v_intake_id,
    'pricing_snapshot', jsonb_build_object('snapshot_id',v_snapshot_id,'snapshot_contract_version',2,'integrity_algorithm_version','hmac-sha256-v1','integrity_key_id','v1','integrity_mac',repeat('a',64)),
    'currency', 'EUR',
    'line_items', jsonb_build_array(jsonb_build_object('line_id','c3-test-only','sequence',1,'product_or_service_code','WEBSITE','description','C3 TEST_ONLY PDF recovery fixture','quantity',1,'unit','project','unit_price_minor',10000,'discount_minor',0,'vat_treatment','EXEMPT','vat_rate',0,'line_net_amount_minor',10000,'cost_type','ONE_TIME')),
    'totals', jsonb_build_object('one_time_subtotal_minor',10000,'recurring_subtotal_minor',0,'discount_total_minor',0,'vat_base_minor',10000,'vat_amount_minor',0,'total_gross_minor',10000),
    'discount', jsonb_build_object('discount_type',null,'discount_value_minor',0,'discount_reason',null,'approved_by',null,'approved_at',null),
    'customer_identity', jsonb_build_object('source_quote_request_id',v_run.quote_request_id,'source_intake_id',v_intake_id,'customer_id',null,'legal_name','C3 TEST_ONLY fixture','legal_form','TEST_ONLY','contact_name','C3 TEST_ONLY','email','c3-test-only@invalid.local','address_line_1','TEST_ONLY','address_line_2',null,'postal_code','0000','city','TEST_ONLY','country_code','BE','enterprise_number',null,'vat_number',null,'source_fields',jsonb_build_object('classification','internal_e2e'),'snapshot_sha256',repeat('b',64)),
    'project_scope', jsonb_build_object('project_id',null,'project_title','C3 TEST_ONLY PDF recovery','project_type','website','scope_summary','Synthetic state for PDF and recovery only','requested_languages',jsonb_build_array('nl'),'included_page_count',1,'features','[]'::jsonb,'copywriting',null,'seo',null,'hosting',null,'maintenance',null,'exclusions','[]'::jsonb,'assumptions','[]'::jsonb,'indicative_timing',1,'source_intake_id',v_intake_id,'source_pricing_snapshot_id',v_snapshot_id,'snapshot_sha256',repeat('c',64)),
    'vat_approval', jsonb_build_object('vat_treatment','EXEMPT','vat_rate',0,'vat_decision_source','TEST_ONLY','vat_approved_by','TEST_ONLY','vat_approved_at','2099-01-01T00:00:00Z'),
    'payment_schedule', jsonb_build_object('schedule_id','website-40-40-rest','milestones',jsonb_build_array(
      jsonb_build_object('sequence',1,'label','M1','percentage',40,'amount_minor',null,'trigger','agreement','due_terms_days',14,'recurring_cycle',null),
      jsonb_build_object('sequence',2,'label','M2','percentage',40,'amount_minor',null,'trigger','preview','due_terms_days',14,'recurring_cycle',null),
      jsonb_build_object('sequence',3,'label','Final','percentage',20,'amount_minor',null,'trigger','final','due_terms_days',14,'recurring_cycle',null)
    ),'approved_by','TEST_ONLY','approved_at','2099-01-01T00:00:00Z'),
    'validity', jsonb_build_object('valid_from','2099-01-01','valid_until','2099-01-31','validity_days',30,'approved_by','TEST_ONLY','approved_at','2099-01-01T00:00:00Z'),
    'legal_references', jsonb_build_object('terms_reference','TEST_ONLY','terms_version','1','terms_sha256',repeat('d',64),'terms_status','APPROVED','agreement_template_reference',null,'agreement_template_version',null,'agreement_template_sha256',null)
  );

  perform set_config('lws.website_delivery_pdf_c3_trial_command', 'create', true);
  insert into public.quote_request_quotation_approval_drafts(
    id, quote_request_id, intake_id, pricing_snapshot_id, contract_version,
    approval_payload, payload_fingerprint, idempotency_key, created_by
  ) values (
    v_draft_id, v_run.quote_request_id, v_intake_id, v_snapshot_id, 1,
    v_approval_payload, public.quotation_approval_payload_sha256_v1(v_approval_payload),
    gen_random_uuid(), 'TEST_ONLY:C3'
  );
  insert into public.quote_request_quotation_approvals(
    id, draft_id, quote_request_id, intake_id, pricing_snapshot_id, contract_version,
    approval_version, approved_payload, payload_sha256, approved_by, approved_at
  ) values (
    v_approval_id, v_draft_id, v_run.quote_request_id, v_intake_id, v_snapshot_id, 1,
    1, v_approval_payload, public.quotation_approval_payload_sha256_v1(v_approval_payload),
    'TEST_ONLY:C3', v_accepted_at
  );
  perform set_config('lws.website_delivery_pdf_c3_trial_command', '', true);

  insert into public.quote_request_quotation_issuances(
    id, quotation_number, quotation_version, status, approval_id, issued_at, issued_by,
    template_id, template_version, template_sha256, generation_contract_version,
    generation_payload_sha256, docx_sha256, docx_bytes,
    prepare_idempotency_key, prepare_fingerprint, commit_idempotency_key, commit_fingerprint
  ) values (
    v_issuance_id, v_quotation_number, 1, 'ISSUED', v_approval_id, v_accepted_at, 'TEST_ONLY:C3',
    'LWS_C3_TEST_ONLY', '1', repeat('3',64), 1, repeat('4',64), repeat('5',64), 1,
    gen_random_uuid(), repeat('6',64), gen_random_uuid(), repeat('7',64)
  );

  v_acceptance_payload := jsonb_build_object(
    'acceptance_contract_version',1,'issuance_id',v_issuance_id,
    'quotation_number',v_quotation_number,'quotation_version',1,
    'customer_identity_sha256',repeat('b',64),'generation_payload_sha256',repeat('4',64),
    'template',jsonb_build_object('template_id','LWS_C3_TEST_ONLY','template_version','1','template_sha256',repeat('3',64)),
    'docx',jsonb_build_object('sha256',repeat('5',64),'bytes',1),
    'acceptance_terms',jsonb_build_object('terms_id','LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','terms_version','1.0.0-technical','terms_sha256',v_terms_sha256),
    'actor',jsonb_build_object('name','C3 TEST_ONLY','email','c3-test-only@invalid.local','organization','C3 TEST_ONLY','role','TEST_ONLY'),
    'authority_declaration',true,'accepted_at',v_accepted_at_text
  );
  insert into public.quote_request_quotation_acceptances(
    id, issuance_id, quotation_number, quotation_version, customer_identity_sha256,
    customer_legal_name, generation_payload_sha256, template_id, template_version,
    template_sha256, docx_sha256, docx_bytes, acceptance_contract_version,
    acceptance_terms_id, acceptance_terms_version, acceptance_terms_sha256,
    accepting_name, accepting_email, accepting_organization, accepting_role,
    authority_declaration, acceptance_payload, acceptance_payload_sha256,
    semantic_request_fingerprint, accepted_at, created_at
  ) values (
    v_acceptance_id, v_issuance_id, v_quotation_number, 1, repeat('b',64),
    'C3 TEST_ONLY fixture', repeat('4',64), 'LWS_C3_TEST_ONLY', '1', repeat('3',64),
    repeat('5',64), 1, 1, 'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT',
    '1.0.0-technical', v_terms_sha256, 'C3 TEST_ONLY', 'c3-test-only@invalid.local',
    'C3 TEST_ONLY', 'TEST_ONLY', true, v_acceptance_payload,
    public.quotation_acceptance_payload_sha256_v1(v_acceptance_payload), repeat('8',64),
    v_accepted_at, v_accepted_at
  );

  insert into public.commercial_customers(customer_id, acceptance_id, identity_sha256)
  values (v_customer_id, v_acceptance_id, repeat('b',64));
  insert into public.commercial_projects(
    project_id, customer_id, quotation_issuance_id, acceptance_id, accepted_total_minor,
    currency, m1_minor, m2_minor, m3_minor, current_state, revision
  ) values (
    v_project_id, v_customer_id, v_issuance_id, v_acceptance_id, 10000,
    'EUR', 4000, 4000, 2000, 'M2_PAYMENT_RECEIVED', 1
  );
  insert into public.preview_versions(
    preview_version_id, project_id, version_number, content_reference, content_sha256, status
  ) values (
    v_preview_version_id, v_project_id, 1,
    'TEST_ONLY:C3:PDF_RECOVERY_ONLY', repeat('9',64), 'CURRENT'
  );

  insert into public.website_delivery_pdf_c3_trial_fixtures(
    internal_e2e_run_id, quote_request_id, project_id, preview_version_id,
    idempotency_key, created_by_operator_id
  ) values (
    v_run.id, v_run.quote_request_id, v_project_id, v_preview_version_id,
    p_idempotency_key, v_operator.operator_id
  ) returning * into v_fixture;
  insert into public.website_delivery_pdf_c3_trial_fixture_events(
    fixture_id, event_type, resulting_status, resulting_revision,
    actor_operator_id, idempotency_key
  ) values (
    v_fixture.fixture_id, 'CREATED', v_fixture.status, v_fixture.revision,
    v_operator.operator_id, p_idempotency_key
  );

  return jsonb_build_object(
    'fixture_id', v_fixture.fixture_id,
    'internal_e2e_run_id', v_fixture.internal_e2e_run_id,
    'quote_request_id', v_fixture.quote_request_id,
    'project_id', v_fixture.project_id,
    'preview_version_id', v_fixture.preview_version_id,
    'status', v_fixture.status,
    'revision', v_fixture.revision,
    'was_created', true,
    'synthetic_scope', 'PDF_RECOVERY_ONLY'
  );
exception when others then
  perform set_config('lws.website_delivery_pdf_c3_trial_command', '', true);
  raise;
end;
$$;

create function public.close_website_delivery_pdf_c3_trial_fixture_v1(
  p_fixture_id uuid,
  p_expected_revision integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, lws_internal, auth, pg_catalog
as $$
declare
  v_operator public.commercial_operators%rowtype;
  v_fixture public.website_delivery_pdf_c3_trial_fixtures%rowtype;
begin
  if p_fixture_id is null or p_expected_revision is null or p_expected_revision < 0
     or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'WEBSITE_DELIVERY_PDF_C3_TRIAL_INPUT_INVALID';
  end if;
  v_operator := lws_internal.require_website_repository_owner_v1();
  select * into v_fixture from public.website_delivery_pdf_c3_trial_fixtures
  where fixture_id = p_fixture_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_C3_TRIAL_FIXTURE_NOT_FOUND';
  end if;
  if v_fixture.status = 'CLOSED' then
    if v_fixture.close_idempotency_key <> p_idempotency_key then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object('fixture_id',v_fixture.fixture_id,'status',v_fixture.status,
      'revision',v_fixture.revision,'was_closed',false);
  end if;
  if v_fixture.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'CONCURRENT_MODIFICATION';
  end if;
  perform set_config('lws.website_delivery_pdf_c3_trial_command', 'close', true);
  update public.website_delivery_pdf_c3_trial_fixtures
  set status = 'CLOSED', revision = revision + 1, closed_at = clock_timestamp(),
      close_idempotency_key = p_idempotency_key
  where fixture_id = p_fixture_id returning * into v_fixture;
  perform set_config('lws.website_delivery_pdf_c3_trial_command', '', true);
  insert into public.website_delivery_pdf_c3_trial_fixture_events(
    fixture_id, event_type, resulting_status, resulting_revision,
    actor_operator_id, idempotency_key
  ) values (
    v_fixture.fixture_id, 'CLOSED', v_fixture.status, v_fixture.revision,
    v_operator.operator_id, p_idempotency_key
  );
  return jsonb_build_object('fixture_id',v_fixture.fixture_id,'status',v_fixture.status,
    'revision',v_fixture.revision,'was_closed',true);
exception when others then
  perform set_config('lws.website_delivery_pdf_c3_trial_command', '', true);
  raise;
end;
$$;

create function public.resolve_website_delivery_pdf_c3_test_hold_v1(
  p_configured_project_id uuid,
  p_configured_internal_e2e_run_id uuid,
  p_task_id uuid,
  p_workflow_run_attempt integer
)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_hold_until timestamptz;
begin
  if p_configured_project_id is null or p_configured_internal_e2e_run_id is null
     or p_task_id is null or p_workflow_run_attempt <> 1 then
    return null;
  end if;
  select execution.claimed_at + interval '2 minutes'
  into v_hold_until
  from public.website_delivery_pdf_c3_trial_fixtures as fixture
  join public.internal_e2e_runs as run
    on run.id = fixture.internal_e2e_run_id
   and run.quote_request_id = fixture.quote_request_id
   and run.status = 'ACTIVE' and run.expires_at > clock_timestamp()
  join public.quote_requests as request
    on request.id = fixture.quote_request_id
   and request.record_classification = 'internal_e2e'
  join public.website_delivery_pdf_conversion_tasks as task
    on task.project_id = fixture.project_id
   and task.preview_version_id = fixture.preview_version_id
   and task.task_id = p_task_id
  join public.website_delivery_pdf_conversion_executions as execution
    on execution.task_id = task.task_id
   and execution.workflow_run_attempt = 1
  where fixture.status = 'ACTIVE'
    and fixture.project_id = p_configured_project_id
    and fixture.internal_e2e_run_id = p_configured_internal_e2e_run_id;
  return v_hold_until;
end;
$$;

revoke all on function public.guard_website_delivery_pdf_c3_trial_fixture_v1()
from public, anon, authenticated, service_role;
revoke all on function public.prevent_website_delivery_pdf_c3_trial_event_mutation_v1()
from public, anon, authenticated, service_role;
revoke all on function public.create_website_delivery_pdf_c3_trial_fixture_v1(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.close_website_delivery_pdf_c3_trial_fixture_v1(uuid, integer, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.resolve_website_delivery_pdf_c3_test_hold_v1(uuid, uuid, uuid, integer)
from public, anon, authenticated, service_role;
grant execute on function public.create_website_delivery_pdf_c3_trial_fixture_v1(uuid, uuid)
to authenticated;
grant execute on function public.close_website_delivery_pdf_c3_trial_fixture_v1(uuid, integer, uuid)
to authenticated;
grant execute on function public.resolve_website_delivery_pdf_c3_test_hold_v1(uuid, uuid, uuid, integer)
to service_role;

comment on table public.website_delivery_pdf_c3_trial_fixtures is
  'Owner+AAL2-created internal_e2e marker for the C3 PDF/recovery trial only; upstream commercial workflows are explicitly not proven.';
comment on function public.create_website_delivery_pdf_c3_trial_fixture_v1(uuid, uuid) is
  'Creates one isolated synthetic M2+CURRENT-preview fixture for an active internal_e2e run without payment, invoice, mail, access, or customer-approval evidence.';
comment on function public.close_website_delivery_pdf_c3_trial_fixture_v1(uuid, integer, uuid) is
  'Logically closes one C3 fixture without disabling triggers or deleting retained test evidence.';
comment on function public.resolve_website_delivery_pdf_c3_test_hold_v1(uuid, uuid, uuid, integer) is
  'Service-only exact project+run+task resolver; attempt 1 deadline is immutable claimed_at plus two minutes.';
