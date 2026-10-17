begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(18);

insert into auth.users(id, email)
values ('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0', 'p2-owner@invalid.local');

select set_config(
  'request.jwt.claims',
  '{"sub":"c9bcd3ef-1e7e-4889-8a12-db827f1b97b0","role":"authenticated","aal":"aal2"}',
  true
);

insert into public.commercial_operators(
  operator_id, auth_user_id, display_name, role, status
) values (
  'a2020000-0000-4000-8000-000000000001',
  'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
  'P2 synthetic owner',
  'owner',
  'ACTIVE'
);

create function pg_temp.create_p2_fixture(
  p_quote_id uuid,
  p_intake_id uuid,
  p_run_id uuid,
  p_run_key uuid,
  p_fixture_key uuid,
  p_application_reference text
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  insert into public.quote_requests(
    id, application_reference, record_classification, request_kind, created_at,
    name, email, website_type, budget, timing, description, privacy_consent, status
  ) values (
    p_quote_id,
    p_application_reference,
    'internal_e2e',
    'website',
    clock_timestamp(),
    'P2 synthetic customer',
    'p2-customer@invalid.local',
    'business',
    'TEST_ONLY',
    'TEST_ONLY',
    'P2 legacy idempotency regression fixture',
    true,
    'approved'
  );

  insert into public.quote_request_intakes(
    id, quote_request_id, status, access_token_hash, access_token_expires_at,
    started_at, submitted_at, confirmation
  ) values (
    p_intake_id,
    p_quote_id,
    'submitted',
    encode(extensions.digest(convert_to(p_intake_id::text, 'UTF8'), 'sha256'), 'hex'),
    clock_timestamp() + interval '1 hour',
    clock_timestamp(),
    clock_timestamp(),
    true
  );

  insert into public.internal_e2e_runs(
    id, quote_request_id, idempotency_key, request_fingerprint, run_label,
    created_by_operator_id, created_at, expires_at
  ) values (
    p_run_id,
    p_quote_id,
    p_run_key,
    encode(extensions.digest(convert_to(p_run_id::text, 'UTF8'), 'sha256'), 'hex'),
    'P2 legacy idempotency regression',
    'a2020000-0000-4000-8000-000000000001',
    clock_timestamp(),
    clock_timestamp() + interval '1 hour'
  );

  v_result := public.create_website_delivery_pdf_c3_trial_fixture_v1(
    p_run_id,
    p_fixture_key
  );
  return v_result;
end;
$$;

create function pg_temp.capture_prepare(
  p_project_id uuid,
  p_delivery_date date,
  p_checklist jsonb,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  v_result := public.prepare_website_delivery_document_v1(
    p_project_id,
    p_delivery_date,
    p_checklist,
    'NONE_CONFIRMED',
    null,
    current_date,
    'TEST_ONLY',
    null,
    null,
    p_idempotency_key,
    'TEST_ONLY:P2'
  );
  return jsonb_build_object('ok', true, 'value', v_result);
exception
  when others then
    return jsonb_build_object(
      'ok', false,
      'sqlstate', sqlstate,
      'message', sqlerrm
    );
end;
$$;

create temporary table p2_fixtures(
  scenario text primary key,
  result jsonb not null
);

insert into p2_fixtures values
(
  'without_application_reference',
  pg_temp.create_p2_fixture(
    'a2030000-0000-4000-8000-000000000001',
    'a2040000-0000-4000-8000-000000000001',
    'a2050000-0000-4000-8000-000000000001',
    'a2050000-0000-4000-8000-000000000002',
    'a2060000-0000-4000-8000-000000000001',
    null
  )
),
(
  'with_application_reference',
  pg_temp.create_p2_fixture(
    'b2030000-0000-4000-8000-000000000001',
    'b2040000-0000-4000-8000-000000000001',
    'b2050000-0000-4000-8000-000000000001',
    'b2050000-0000-4000-8000-000000000002',
    'b2060000-0000-4000-8000-000000000001',
    'LWS-AAN-2099-9002'
  )
);

create temporary table p2_input as
select
  scenario,
  (result->>'project_id')::uuid as project_id,
  current_date as delivery_date,
  jsonb_build_object(
    'pages', 'COMPLETED',
    'desktop_browsers', 'COMPLETED',
    'mobile_tablet', 'COMPLETED',
    'forms', 'COMPLETED',
    'links', 'COMPLETED',
    'technical_seo', 'COMPLETED',
    'ssl', 'COMPLETED',
    'hosting', 'COMPLETED',
    'domain', 'COMPLETED',
    'access_transfer', 'COMPLETED',
    'backup', 'COMPLETED'
  ) as checklist
from p2_fixtures;

create temporary table p2_no_application_first as
select public.prepare_website_delivery_document_v1(
  project_id,
  delivery_date,
  checklist,
  'NONE_CONFIRMED',
  null,
  current_date,
  'TEST_ONLY',
  null,
  null,
  'a2070000-0000-4000-8000-000000000010',
  'TEST_ONLY:P2'
) as result
from p2_input
where scenario = 'without_application_reference';

create temporary table p2_application_first as
select public.prepare_website_delivery_document_v1(
  project_id,
  delivery_date,
  checklist,
  'NONE_CONFIRMED',
  null,
  current_date,
  'TEST_ONLY',
  null,
  null,
  'b2070000-0000-4000-8000-000000000010',
  'TEST_ONLY:P2'
) as result
from p2_input
where scenario = 'with_application_reference';

with source_candidate as (
  select candidate.*
  from public.website_delivery_document_candidates as candidate
  where candidate.preparation_idempotency_key =
    'a2070000-0000-4000-8000-000000000010'
),
legacy_payload as (
  select
    source_candidate.*,
    jsonb_set(
      source_candidate.generation_payload,
      '{project,reference}',
      'null'::jsonb,
      false
    ) as payload
  from source_candidate
)
insert into public.website_delivery_document_candidates(
  project_id,
  customer_id,
  preview_version_id,
  preview_version,
  preview_content_reference,
  preview_content_sha256,
  source_drive_file_id,
  source_sha256,
  statement_version,
  document_version,
  generation_payload,
  generation_payload_sha256,
  preparation_idempotency_key,
  created_by
)
select
  project_id,
  customer_id,
  preview_version_id,
  preview_version,
  preview_content_reference,
  preview_content_sha256,
  source_drive_file_id,
  source_sha256,
  statement_version,
  document_version + 1,
  payload,
  encode(extensions.digest(convert_to(payload::text, 'UTF8'), 'sha256'), 'hex'),
  'a2070000-0000-4000-8000-000000000011',
  'TEST_ONLY:P2:LEGACY'
from legacy_payload
;

create temporary table p2_legacy_candidate as
select *
from public.website_delivery_document_candidates
where preparation_idempotency_key =
  'a2070000-0000-4000-8000-000000000011';

create temporary table p2_sensitive_counts_before as
select 'artifacts'::text as relation_name, count(*)::bigint as row_count
from public.website_delivery_document_artifacts
union all
select 'view_derivatives', count(*) from public.website_delivery_document_view_derivatives
union all
select 'conversion_tasks', count(*) from public.website_delivery_pdf_conversion_tasks
union all
select 'conversion_executions', count(*) from public.website_delivery_pdf_conversion_executions
union all
select 'dispatch_intents', count(*) from public.website_delivery_pdf_dispatch_intents
union all
select 'recovery_intents', count(*) from public.website_delivery_pdf_recovery_intents
union all
select 'preview_sessions', count(*) from lws_internal.website_project_preview_sessions;

create temporary table p2_results as
select
  'legacy_retry'::text as scenario,
  pg_temp.capture_prepare(
    input.project_id,
    input.delivery_date,
    input.checklist,
    'a2070000-0000-4000-8000-000000000011'
  ) as result
from p2_input as input
where input.scenario = 'without_application_reference'
union all
select
  'changed_legacy_retry',
  pg_temp.capture_prepare(
    input.project_id,
    input.delivery_date + 1,
    input.checklist,
    'a2070000-0000-4000-8000-000000000011'
  )
from p2_input as input
where input.scenario = 'without_application_reference'
union all
select
  'support_reference_retry',
  pg_temp.capture_prepare(
    input.project_id,
    input.delivery_date,
    input.checklist,
    'a2070000-0000-4000-8000-000000000010'
  )
from p2_input as input
where input.scenario = 'without_application_reference'
union all
select
  'application_reference_retry',
  pg_temp.capture_prepare(
    input.project_id,
    input.delivery_date,
    input.checklist,
    'b2070000-0000-4000-8000-000000000010'
  )
from p2_input as input
where input.scenario = 'with_application_reference'
union all
select
  'cross_dossier_retry',
  pg_temp.capture_prepare(
    input.project_id,
    input.delivery_date,
    input.checklist,
    'a2070000-0000-4000-8000-000000000010'
  )
from p2_input as input
where input.scenario = 'with_application_reference';

select is(
  (select result->>'ok' from p2_results where scenario = 'legacy_retry'),
  'true',
  'pre-fallback candidate replays under its original idempotency key'
);
select is(
  (select result->'value'->>'candidate_id' from p2_results where scenario = 'legacy_retry'),
  (select candidate_id::text from p2_legacy_candidate),
  'legacy replay returns the original candidate identity'
);
select is(
  (select result->'value'->>'generation_payload_sha256' from p2_results where scenario = 'legacy_retry'),
  (select rtrim(generation_payload_sha256) from p2_legacy_candidate),
  'legacy replay returns the original stored payload hash'
);
select is(
  (select result->'value'->>'was_created' from p2_results where scenario = 'legacy_retry'),
  'false',
  'legacy replay creates no replacement candidate'
);
select is(
  (select result->>'ok' from p2_results where scenario = 'changed_legacy_retry'),
  'false',
  'same legacy key rejects genuinely changed content'
);
select is(
  (select result->>'message' from p2_results where scenario = 'changed_legacy_retry'),
  'WEBSITE_DELIVERY_IDEMPOTENCY_CONFLICT',
  'changed legacy retry returns the exact conflict'
);
select is(
  (select result->'generation_payload'->'project'->>'reference'
   from p2_no_application_first),
  '#A2030000',
  'missing application reference uses the support reference'
);
select ok(
  (select result->>'ok' = 'true'
     and result->'value'->>'candidate_id' =
       (select result->>'candidate_id' from p2_no_application_first)
     and result->'value'->>'was_created' = 'false'
   from p2_results
   where scenario = 'support_reference_retry'),
  'support-reference candidate replays without duplication'
);
select is(
  (select result->'generation_payload'->'project'->>'reference'
   from p2_application_first),
  'LWS-AAN-2099-9002',
  'valid application reference remains the primary document reference'
);
select ok(
  (select result->>'ok' = 'true'
     and result->'value'->>'candidate_id' =
       (select result->>'candidate_id' from p2_application_first)
     and result->'value'->>'was_created' = 'false'
   from p2_results
   where scenario = 'application_reference_retry'),
  'application-reference candidate replays without duplication'
);
select is(
  (select result->>'ok' from p2_results where scenario = 'cross_dossier_retry'),
  'false',
  'idempotency key cannot cross dossier boundaries'
);
select is(
  (select result->>'message' from p2_results where scenario = 'cross_dossier_retry'),
  'WEBSITE_DELIVERY_IDEMPOTENCY_CONFLICT',
  'cross-dossier key reuse returns the exact conflict'
);
select is(
  (
    select count(*)::integer
    from public.website_delivery_document_candidates
    where project_id in (select project_id from p2_input)
  ),
  3,
  'retries create no duplicate delivery-document candidates'
);
select isnt(
  (select customer_id::text from public.commercial_projects
   where project_id = (
     select project_id from p2_input where scenario = 'without_application_reference'
   )),
  (select customer_id::text from public.commercial_projects
   where project_id = (
     select project_id from p2_input where scenario = 'with_application_reference'
   )),
  'cross-dossier test uses distinct synthetic customer authorities'
);
select ok(
  exists (
    select 1
    from pg_proc as function
    join pg_roles as owner on owner.oid = function.proowner
    where function.oid =
      'public.prepare_website_delivery_document_v1(uuid,date,jsonb,text,text,date,text,date,text,uuid,text)'::regprocedure
      and owner.rolname = 'postgres'
      and function.prosecdef
      and function.proconfig =
        array['search_path=public, lws_internal, extensions, pg_catalog']
      and function.proacl =
        '{postgres=X/postgres,service_role=X/postgres}'::aclitem[]
      and function.prosrc like '%v_legacy_payload_sha256%'
  ),
  'corrected function preserves owner, ACL, SECURITY DEFINER, search_path and legacy guard'
);
select ok(
  exists (
    select 1
    from public.website_delivery_document_candidates as candidate
    join p2_legacy_candidate as legacy using (candidate_id)
    where candidate.generation_payload = legacy.generation_payload
      and candidate.generation_payload->'project'->'reference' = 'null'::jsonb
      and rtrim(candidate.generation_payload_sha256) =
        rtrim(legacy.generation_payload_sha256)
  ),
  'legacy document identity and stored hash remain unchanged'
);
select ok(
  not exists (
    select 1
    from p2_sensitive_counts_before as before
    join (
      select 'artifacts'::text as relation_name, count(*)::bigint as row_count
      from public.website_delivery_document_artifacts
      union all
      select 'view_derivatives', count(*) from public.website_delivery_document_view_derivatives
      union all
      select 'conversion_tasks', count(*) from public.website_delivery_pdf_conversion_tasks
      union all
      select 'conversion_executions', count(*) from public.website_delivery_pdf_conversion_executions
      union all
      select 'dispatch_intents', count(*) from public.website_delivery_pdf_dispatch_intents
      union all
      select 'recovery_intents', count(*) from public.website_delivery_pdf_recovery_intents
      union all
      select 'preview_sessions', count(*) from lws_internal.website_project_preview_sessions
    ) as after using (relation_name)
    where before.row_count <> after.row_count
  ),
  'retries create no provider, artifact, conversion or preview-session effects'
);
select is(
  (
    select count(*)::integer
    from lws_internal.website_project_preview_sessions as session
    join lws_internal.website_project_preview_builds as build
      on build.preview_build_id = session.preview_build_id
    where build.quote_request_id in (
      'a2030000-0000-4000-8000-000000000001',
      'b2030000-0000-4000-8000-000000000001'
    )
  ),
  0,
  'delivery-document retries create no preview sessions'
);

select * from finish();

rollback;
