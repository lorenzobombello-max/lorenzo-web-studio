begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('public', 'sdf_document_requirements', 'required-document authority exists');
select has_table('public', 'sdf_document_requirement_evidence', 'requirement evidence authority exists');
select has_function('public', 'create_sdf_document_requirement_v1', array['uuid','text','integer'], 'owner requirement creation RPC exists');
select has_function('public', 'bind_sdf_document_requirement_evidence_v1', array['uuid','uuid'], 'owner evidence binding RPC exists');
select has_function('lws_internal', 'get_sdf_document_requirements_v1', array['uuid'], 'private deterministic requirement state exists');
select ok(
  not has_table_privilege('authenticated', 'public.sdf_document_requirements', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.sdf_document_requirement_evidence', 'select,insert,update,delete')
  and not has_function_privilege('authenticated', 'lws_internal.get_sdf_document_requirements_v1(uuid)', 'execute'),
  'authenticated clients have no direct table or private evaluator authority'
);
select ok(
  has_function_privilege('authenticated', 'public.create_sdf_document_requirement_v1(uuid,text,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.bind_sdf_document_requirement_evidence_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.create_sdf_document_requirement_v1(uuid,text,integer)', 'execute'),
  'only authenticated callers reach owner-checked commands'
);

insert into auth.users(id, email) values
  ('da100000-0000-4000-8000-000000000001', 'dfq2a-owner@example.test'),
  ('da100000-0000-4000-8000-000000000002', 'dfq2a-reviewer@example.test');
insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('da110000-0000-4000-8000-000000000001', 'da100000-0000-4000-8000-000000000001', 'DFQ-2A Owner', 'owner', 'ACTIVE'),
  ('da110000-0000-4000-8000-000000000002', 'da100000-0000-4000-8000-000000000002', 'DFQ-2A Reviewer', 'reviewer', 'ACTIVE');

insert into public.quote_requests(
  id, application_reference, record_classification, request_kind, sdf_package,
  name, email, description, privacy_consent, status
) values
  ('da200000-0000-4000-8000-000000000001', 'LWS-AAN-2099-9101', 'production', 'slimme_documentenflow', 'start', 'DFQ dossier A', 'dfq-a@example.test', 'Synthetic DFQ-2A dossier A.', true, 'approved'),
  ('db200000-0000-4000-8000-000000000002', 'LWS-AAN-2099-9102', 'production', 'slimme_documentenflow', 'start', 'DFQ dossier B', 'dfq-b@example.test', 'Synthetic DFQ-2A dossier B.', true, 'approved');
insert into public.sdf_projects(project_id, quote_request_id) values
  ('da210000-0000-4000-8000-000000000001', 'da200000-0000-4000-8000-000000000001'),
  ('da210000-0000-4000-8000-000000000002', 'db200000-0000-4000-8000-000000000002');

insert into public.customer_requests(
  request_id, request_reference, quote_request_id, customer_id, project_id,
  source, request_type, title, description, status, priority, submitted_at, submitter_type
) values
  ('da300000-0000-4000-8000-000000000001', 'LWS-VRZ-2099-9101', 'da200000-0000-4000-8000-000000000001', null, null, 'OPERATOR', 'FILE_DELIVERY', 'DFQ dossier A files', 'Synthetic files for dossier A.', 'NEW', 'NORMAL', clock_timestamp(), 'OPERATOR'),
  ('da300000-0000-4000-8000-000000000002', 'LWS-VRZ-2099-9102', 'db200000-0000-4000-8000-000000000002', null, null, 'OPERATOR', 'FILE_DELIVERY', 'DFQ dossier B files', 'Synthetic files for dossier B.', 'NEW', 'NORMAL', clock_timestamp(), 'OPERATOR');

insert into public.customer_request_upload_requests(
  upload_request_id, customer_request_id, token_digest, status, expires_at,
  created_at, created_by_operator_id, completed_at
) values
  ('da400000-0000-4000-8000-000000000001', 'da300000-0000-4000-8000-000000000001', repeat('a', 64), 'COMPLETED', clock_timestamp() + interval '1 day', clock_timestamp(), 'da110000-0000-4000-8000-000000000001', clock_timestamp()),
  ('da400000-0000-4000-8000-000000000002', 'da300000-0000-4000-8000-000000000002', repeat('b', 64), 'COMPLETED', clock_timestamp() + interval '1 day', clock_timestamp(), 'da110000-0000-4000-8000-000000000001', clock_timestamp());

insert into public.customer_request_uploaded_files(
  uploaded_file_id, upload_request_id, customer_request_id, status,
  storage_object_path, original_file_name, file_extension, declared_content_type,
  declared_byte_count, observed_content_type, observed_byte_count, sha256, accepted_at
) values
  ('da500000-0000-4000-8000-000000000001', 'da400000-0000-4000-8000-000000000001', 'da300000-0000-4000-8000-000000000001', 'ACCEPTED', 'requests/da300000-0000-4000-8000-000000000001/uploads/da400000-0000-4000-8000-000000000001/files/da500000-0000-4000-8000-000000000001.pdf', 'a-1.pdf', 'pdf', 'application/pdf', 101, 'application/pdf', 101, repeat('1', 64), clock_timestamp()),
  ('da500000-0000-4000-8000-000000000002', 'da400000-0000-4000-8000-000000000001', 'da300000-0000-4000-8000-000000000001', 'ACCEPTED', 'requests/da300000-0000-4000-8000-000000000001/uploads/da400000-0000-4000-8000-000000000001/files/da500000-0000-4000-8000-000000000002.pdf', 'a-2.pdf', 'pdf', 'application/pdf', 102, 'application/pdf', 102, repeat('2', 64), clock_timestamp()),
  ('da500000-0000-4000-8000-000000000003', 'da400000-0000-4000-8000-000000000001', 'da300000-0000-4000-8000-000000000001', 'ACCEPTED', 'requests/da300000-0000-4000-8000-000000000001/uploads/da400000-0000-4000-8000-000000000001/files/da500000-0000-4000-8000-000000000003.pdf', 'a-3.pdf', 'pdf', 'application/pdf', 103, 'application/pdf', 103, repeat('3', 64), clock_timestamp()),
  ('da500000-0000-4000-8000-000000000004', 'da400000-0000-4000-8000-000000000002', 'da300000-0000-4000-8000-000000000002', 'ACCEPTED', 'requests/da300000-0000-4000-8000-000000000002/uploads/da400000-0000-4000-8000-000000000002/files/da500000-0000-4000-8000-000000000004.pdf', 'b-1.pdf', 'pdf', 'application/pdf', 104, 'application/pdf', 104, repeat('4', 64), clock_timestamp());

insert into public.document_inbox_items(
  id, sha256, storage_object_path, original_file_name, mime_type, byte_count,
  source_type, source_instance, external_id, created_by_operator_id
) values
  ('da600000-0000-4000-8000-000000000001', repeat('1', 64), 'documents/' || repeat('1', 64) || '.pdf', 'a-1.pdf', 'application/pdf', 101, 'CUSTOMER_REQUEST_UPLOAD', 'da300000-0000-4000-8000-000000000001', 'da500000-0000-4000-8000-000000000001', 'da110000-0000-4000-8000-000000000001'),
  ('da600000-0000-4000-8000-000000000002', repeat('2', 64), 'documents/' || repeat('2', 64) || '.pdf', 'a-2.pdf', 'application/pdf', 102, 'CUSTOMER_REQUEST_UPLOAD', 'da300000-0000-4000-8000-000000000001', 'da500000-0000-4000-8000-000000000002', 'da110000-0000-4000-8000-000000000001'),
  ('da600000-0000-4000-8000-000000000003', repeat('3', 64), 'documents/' || repeat('3', 64) || '.pdf', 'a-3.pdf', 'application/pdf', 103, 'CUSTOMER_REQUEST_UPLOAD', 'da300000-0000-4000-8000-000000000001', 'da500000-0000-4000-8000-000000000003', 'da110000-0000-4000-8000-000000000001'),
  ('da600000-0000-4000-8000-000000000004', repeat('4', 64), 'documents/' || repeat('4', 64) || '.pdf', 'b-1.pdf', 'application/pdf', 104, 'CUSTOMER_REQUEST_UPLOAD', 'da300000-0000-4000-8000-000000000002', 'da500000-0000-4000-8000-000000000004', 'da110000-0000-4000-8000-000000000001');

insert into public.document_inbox_customer_request_upload_sources(
  uploaded_file_id, customer_request_id, quote_request_id,
  document_inbox_item_id, promoted_by_operator_id
) values
  ('da500000-0000-4000-8000-000000000001', 'da300000-0000-4000-8000-000000000001', 'da200000-0000-4000-8000-000000000001', 'da600000-0000-4000-8000-000000000001', 'da110000-0000-4000-8000-000000000001'),
  ('da500000-0000-4000-8000-000000000002', 'da300000-0000-4000-8000-000000000001', 'da200000-0000-4000-8000-000000000001', 'da600000-0000-4000-8000-000000000002', 'da110000-0000-4000-8000-000000000001'),
  ('da500000-0000-4000-8000-000000000003', 'da300000-0000-4000-8000-000000000001', 'da200000-0000-4000-8000-000000000001', 'da600000-0000-4000-8000-000000000003', 'da110000-0000-4000-8000-000000000001'),
  ('da500000-0000-4000-8000-000000000004', 'da300000-0000-4000-8000-000000000002', 'db200000-0000-4000-8000-000000000002', 'da600000-0000-4000-8000-000000000004', 'da110000-0000-4000-8000-000000000001');

select set_config('request.jwt.claim.sub', 'da100000-0000-4000-8000-000000000001', true);
create temporary table requirement_fixture as
select public.create_sdf_document_requirement_v1(
  'da200000-0000-4000-8000-000000000001', 'invoice', 2
) as result;

select is((select result->>'quote_request_id' from requirement_fixture), 'da200000-0000-4000-8000-000000000001', 'requirement binds canonical dossier identity');
select is((select result->>'required_count' from requirement_fixture), '2', 'positive integer required_count is authoritative');
select is((select result->>'status' from requirement_fixture), 'REQUIRED', 'new requirement starts REQUIRED');
select throws_ok(
  $$select public.create_sdf_document_requirement_v1('da200000-0000-4000-8000-000000000001', 'contract', 0)$$,
  '22023', 'INVALID_SDF_DOCUMENT_REQUIREMENT', 'zero required_count is rejected'
);
select throws_ok(
  $$select public.create_sdf_document_requirement_v1('da200000-0000-4000-8000-000000000001', 'contract', -1)$$,
  '22023', 'INVALID_SDF_DOCUMENT_REQUIREMENT', 'negative required_count is rejected'
);
select throws_ok(
  $$select public.create_sdf_document_requirement_v1('da200000-0000-4000-8000-000000000001', 'invoice', 2)$$,
  '23505', 'SDF_DOCUMENT_REQUIREMENT_EXISTS', 'duplicate dossier document type is rejected'
);

create temporary table first_binding as
select public.bind_sdf_document_requirement_evidence_v1(
  (select (result->>'requirement_id')::uuid from requirement_fixture),
  'da500000-0000-4000-8000-000000000001'
) as result;
select is((select result->>'status' from first_binding), 'REQUIRED', 'one valid file does not satisfy required_count two');
select is((select result->>'valid_evidence_count' from first_binding), '1', 'first unique valid evidence counts once');

select throws_ok(
  $$select public.bind_sdf_document_requirement_evidence_v1(
    (select (result->>'requirement_id')::uuid from requirement_fixture),
    'da500000-0000-4000-8000-000000000004'
  )$$,
  '23514', 'SDF_DOCUMENT_EVIDENCE_DOSSIER_MISMATCH', 'cross-dossier evidence is rejected'
);

create temporary table second_binding as
select public.bind_sdf_document_requirement_evidence_v1(
  (select (result->>'requirement_id')::uuid from requirement_fixture),
  'da500000-0000-4000-8000-000000000002'
) as result;
select is((select result->>'status' from second_binding), 'SATISFIED', 'two valid files satisfy required_count two');
select is((select result->>'valid_evidence_count' from second_binding), '2', 'two unique valid files count exactly twice');
select is(
  public.bind_sdf_document_requirement_evidence_v1(
    (select (result->>'requirement_id')::uuid from requirement_fixture),
    'da500000-0000-4000-8000-000000000002'
  )->>'replayed',
  'true',
  'duplicate binding replays without duplicate counting'
);
select is((select count(*)::integer from public.sdf_document_requirement_evidence), 2, 'duplicate evidence creates no second binding');

create temporary table stable_state as
select lws_internal.get_sdf_document_requirements_v1('da200000-0000-4000-8000-000000000001') as result;
select is(
  lws_internal.get_sdf_document_requirements_v1('da200000-0000-4000-8000-000000000001'),
  (select result from stable_state),
  'requirement state is deterministically readable'
);

select set_config('request.jwt.claim.sub', 'da100000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.create_sdf_document_requirement_v1('da200000-0000-4000-8000-000000000001', 'contract', 1)$$,
  '42501', 'OWNER_REQUIRED', 'reviewer cannot create requirements'
);
select throws_ok(
  $$select public.bind_sdf_document_requirement_evidence_v1(
    (select (result->>'requirement_id')::uuid from requirement_fixture),
    'da500000-0000-4000-8000-000000000003'
  )$$,
  '42501', 'OWNER_REQUIRED', 'reviewer cannot force requirement satisfaction'
);

select set_config('request.jwt.claim.sub', 'da100000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$update public.sdf_document_requirements set required_count = 1$$,
  '55000', 'SDF_DOCUMENT_REQUIREMENT_HISTORY_IMMUTABLE', 'required_count cannot be lowered by rewrite'
);
select throws_ok(
  $$delete from public.sdf_document_requirement_evidence$$,
  '55000', 'SDF_DOCUMENT_REQUIREMENT_HISTORY_IMMUTABLE', 'evidence cannot be removed to rewrite history'
);

select * from finish();
rollback;