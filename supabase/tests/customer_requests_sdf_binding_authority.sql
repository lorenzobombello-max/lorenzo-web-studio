begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public', 'create_sdf_customer_request_v1',
  array['uuid','uuid','text','text','text','text'],
  'authenticated SDF Customer Request creation authority exists'
);
select ok(
  has_function_privilege('authenticated', 'public.create_sdf_customer_request_v1(uuid,uuid,text,text,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.create_sdf_customer_request_v1(uuid,uuid,text,text,text,text)', 'execute')
  and not has_function_privilege('service_role', 'public.create_sdf_customer_request_v1(uuid,uuid,text,text,text,text)', 'execute'),
  'only authenticated humans can invoke the SDF creation boundary'
);
select is(
  pg_get_function_arguments('public.create_sdf_customer_request_v1(uuid,uuid,text,text,text,text)'::regprocedure),
  'p_quote_request_id uuid, p_idempotency_key uuid, p_request_type text, p_title text, p_description text, p_priority text DEFAULT NULL::text',
  'creation accepts no request kind or fabricated Website identities'
);
select ok(
  not has_function_privilege('authenticated', 'lws_internal.assert_customer_request_binding_v1(uuid,uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'lws_internal.create_customer_request_core_v1(uuid,uuid,uuid,uuid,uuid,uuid,jsonb)', 'execute'),
  'binding and create cores remain private'
);

insert into auth.users(id, email) values
  ('cb000000-0000-4000-8000-000000000001', 'sdf-request-owner@example.test'),
  ('cb000000-0000-4000-8000-000000000002', 'sdf-request-reviewer@example.test');
insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('cb010000-0000-4000-8000-000000000001', 'cb000000-0000-4000-8000-000000000001', 'SDF Request Owner', 'owner', 'ACTIVE'),
  ('cb010000-0000-4000-8000-000000000002', 'cb000000-0000-4000-8000-000000000002', 'SDF Request Reviewer', 'reviewer', 'ACTIVE');

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind, sdf_package,
  name, email, website_type, budget, timing, description, privacy_consent, status
) values
  ('cb020000-0000-4000-8000-000000000001', 'LWS-AAN-2099-8201', 'production', 'slimme_documentenflow', 'start', 'SDF request fixture', 'sdf-request@example.test', null, null, null, 'Canonical SDF request fixture.', true, 'approved'),
  ('cb020002-0000-4000-8000-000000000002', 'LWS-AAN-2099-8202', 'production', 'website', null, 'Website request fixture', 'website-request@example.test', 'business', 'Meer dan EUR 6.000', 'flexible', 'Website isolation fixture.', true, 'approved');
insert into public.sdf_projects(project_id, quote_request_id, created_at) values
  ('cb030000-0000-4000-8000-000000000001', 'cb020000-0000-4000-8000-000000000001', '2099-08-29T10:00:00Z');

select set_config('request.jwt.claim.sub', 'cb000000-0000-4000-8000-000000000001', true);
create temporary table sdf_create_result as
select public.create_sdf_customer_request_v1(
  'cb020000-0000-4000-8000-000000000001',
  'cb040000-0000-4000-8000-000000000001',
  'FILE_DELIVERY',
  'Bronbestanden aanleveren',
  'Lever de bronbestanden voor de documentenflow aan.',
  'NORMAL'
) as payload;

select is(
  (select request.quote_request_id
   from public.customer_requests as request
   where request.request_id = (select (payload->>'request_id')::uuid from sdf_create_result)),
  'cb020000-0000-4000-8000-000000000001'::uuid,
  'SDF Customer Request binds to the canonical quote request'
);
select ok(
  (select request.customer_id is null and request.project_id is null
   from public.customer_requests as request
   where request.request_id = (select (payload->>'request_id')::uuid from sdf_create_result)),
  'SDF Customer Request has no fabricated Website customer or project identity'
);
select is(
  public.create_sdf_customer_request_v1(
    'cb020000-0000-4000-8000-000000000001',
    'cb040000-0000-4000-8000-000000000001',
    'FILE_DELIVERY',
    'Bronbestanden aanleveren',
    'Lever de bronbestanden voor de documentenflow aan.',
    'NORMAL'
  )->>'replayed',
  'true',
  'identical retry replays the original creation result'
);
select throws_ok($$
  select public.create_sdf_customer_request_v1(
    'cb020000-0000-4000-8000-000000000001',
    'cb040000-0000-4000-8000-000000000001',
    'OTHER',
    'Andere inhoud',
    'Een gewijzigde payload mag dezelfde key niet hergebruiken.',
    null
  )
$$, 'P0001', 'IDEMPOTENCY_CONFLICT', 'changed retry is rejected as an idempotency conflict');

select lives_ok($$
  select public.create_customer_request_upload_request_v1(
    (select (payload->>'request_id')::uuid from sdf_create_result),
    repeat('c', 64),
    clock_timestamp() + interval '1 day',
    'cb050000-0000-4000-8000-000000000001'
  )
$$, 'existing upload authority accepts the canonical SDF Customer Request');

select lives_ok($$
  select * from public.get_operator_dossier_document_manifest_v1(
    'cb000000-0000-4000-8000-000000000001',
    'cb020000-0000-4000-8000-000000000001'
  )
$$, 'existing dossier document manifest accepts the SDF request binding');

select throws_ok($$
  select public.create_sdf_customer_request_v1(
    'cb020002-0000-4000-8000-000000000002',
    'cb040000-0000-4000-8000-000000000002',
    'OTHER', 'Website afwijzen', 'Website dossiers mogen deze authority niet gebruiken.', null
  )
$$, '42501', 'SDF_CUSTOMER_REQUEST_ACCESS_DENIED', 'server-derived request kind rejects a Website dossier');

select set_config('request.jwt.claim.sub', 'cb000000-0000-4000-8000-000000000002', true);
select throws_ok($$
  select public.create_sdf_customer_request_v1(
    'cb020000-0000-4000-8000-000000000001',
    'cb040000-0000-4000-8000-000000000003',
    'OTHER', 'Geen authority', 'Reviewers kunnen geen operationele request aanmaken.', null
  )
$$, '42501', 'SDF_CUSTOMER_REQUEST_ACCESS_DENIED', 'reviewer without operational authority is denied');

select set_config('request.jwt.claim.sub', '', true);
select throws_ok($$
  select public.create_sdf_customer_request_v1(
    'cb020000-0000-4000-8000-000000000001',
    'cb040000-0000-4000-8000-000000000004',
    'OTHER', 'Geen JWT', 'Een human JWT blijft verplicht.', null
  )
$$, '42501', 'HUMAN_JWT_REQUIRED', 'missing human JWT is denied');

select * from finish();
rollback;