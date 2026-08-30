begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, storage, extensions;
select no_plan();

select has_table('public', 'customer_request_upload_requests', 'upload request authority exists');
select has_table('public', 'customer_request_uploaded_files', 'uploaded file authority exists');
select has_table('public', 'document_inbox_customer_request_upload_sources', 'typed Customer Request upload Inbox provenance exists');
select has_table('lws_internal', 'customer_request_upload_operations', 'idempotency ledger exists');
select is((select public from storage.buckets where id = 'customer-request-quarantine'), false, 'quarantine bucket is private');
select is((select file_size_limit from storage.buckets where id = 'customer-request-quarantine'), 8388608::bigint, 'bucket enforces eight MiB per object');
select is((select allowed_mime_types from storage.buckets where id = 'customer-request-quarantine'), array['application/pdf','image/png','image/jpeg']::text[], 'bucket MIME allowlist is exact');
select is((select count(*)::integer from pg_policies where schemaname = 'storage' and tablename = 'objects' and (coalesce(qual, '') like '%customer-request-quarantine%' or coalesce(with_check, '') like '%customer-request-quarantine%')), 0, 'no browser Storage policy grants list, read, or write');
select ok((select relrowsecurity from pg_class where oid = 'public.customer_request_upload_requests'::regclass), 'upload requests have RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.customer_request_uploaded_files'::regclass), 'uploaded files have RLS');

select has_function('public', 'create_customer_request_upload_request_v1', array['uuid','text','timestamptz','uuid'], 'create operation exists');
select has_function('public', 'revoke_customer_request_upload_request_v1', array['uuid','text','uuid'], 'revoke operation exists');
select has_function('public', 'resolve_customer_request_upload_capability_v1', array['text'], 'resolve operation exists');
select has_function('public', 'prepare_customer_request_upload_v1', array['text','text','text','bigint','uuid'], 'prepare operation exists');
select has_function('public', 'finalize_customer_request_uploaded_file_v1', array['text','uuid','text','bigint','text','boolean','uuid'], 'finalize operation exists');
select has_function('public', 'list_customer_request_uploaded_files_v1', array['text'], 'list operation exists');
select has_function('public', 'complete_customer_request_upload_request_v1', array['text','uuid'], 'complete operation exists');
select has_function('public', 'cleanup_expired_customer_request_uploads_v1', array['integer','uuid'], 'cleanup operation exists');
select has_function('public', 'authorize_customer_request_upload_inbox_promotion_v1', array['uuid'], 'operator promotion authorization exists');
select has_function('public', 'finalize_customer_request_upload_inbox_promotion_v1', array['uuid'], 'operator promotion finalization exists');
select ok(has_function_privilege('authenticated', 'public.create_customer_request_upload_request_v1(uuid,text,timestamptz,uuid)', 'execute') and has_function_privilege('authenticated', 'public.revoke_customer_request_upload_request_v1(uuid,text,uuid)', 'execute'), 'operator create and revoke are authenticated entrypoints');
select ok(not has_function_privilege('authenticated', 'public.prepare_customer_request_upload_v1(text,text,text,bigint,uuid)', 'execute') and has_function_privilege('service_role', 'public.prepare_customer_request_upload_v1(text,text,text,bigint,uuid)', 'execute'), 'public capability mutations are service-role Edge only');
select ok(not has_table_privilege('anon', 'public.customer_request_upload_requests', 'select') and not has_table_privilege('authenticated', 'public.customer_request_uploaded_files', 'select') and not has_table_privilege('service_role', 'public.customer_request_uploaded_files', 'insert'), 'runtime roles cannot bypass RPC authority with direct table access');
select is(pg_get_function_arguments('public.prepare_customer_request_upload_v1(text,text,text,bigint,uuid)'::regprocedure), 'p_token_digest text, p_original_file_name text, p_content_type text, p_byte_count bigint, p_idempotency_key uuid', 'prepare accepts no browser customer, project, dossier, or object path authority');
select ok(
  has_function_privilege('authenticated', 'public.authorize_customer_request_upload_inbox_promotion_v1(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.finalize_customer_request_upload_inbox_promotion_v1(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.authorize_customer_request_upload_inbox_promotion_v1(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.finalize_customer_request_upload_inbox_promotion_v1(uuid)', 'execute'),
  'promotion RPCs are authenticated-only and unavailable to anon'
);

insert into auth.users(id, email) values
  ('ca000000-0000-4000-8000-000000000001', 'upload-owner@example.test'),
  ('ca000000-0000-4000-8000-000000000002', 'upload-read-only@example.test'),
  ('ca000000-0000-4000-8000-000000000003', 'upload-operations@example.test'),
  ('ca000000-0000-4000-8000-000000000004', 'upload-assigned@example.test'),
  ('ca000000-0000-4000-8000-000000000005', 'upload-other-dossier@example.test');
insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('ca010000-0000-4000-8000-000000000001', 'ca000000-0000-4000-8000-000000000001', 'Upload Owner', 'owner', 'ACTIVE'),
  ('ca010000-0000-4000-8000-000000000002', 'ca000000-0000-4000-8000-000000000002', 'Upload Read Only', 'read_only', 'ACTIVE'),
  ('ca010000-0000-4000-8000-000000000003', 'ca000000-0000-4000-8000-000000000003', 'Upload Operations', 'operations_manager', 'ACTIVE'),
  ('ca010000-0000-4000-8000-000000000004', 'ca000000-0000-4000-8000-000000000004', 'Upload Assigned', 'operator', 'ACTIVE'),
  ('ca010000-0000-4000-8000-000000000005', 'ca000000-0000-4000-8000-000000000005', 'Upload Other Dossier', 'operator', 'ACTIVE');

insert into public.quote_requests(
  id, name, email, website_type, budget, timing, description,
  privacy_consent, status, record_classification
) values
  ('ca030001-0000-4000-8000-000000000001', 'Upload A', 'upload-a@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Upload authority fixture A.', true, 'approved', 'production'),
  ('ca030002-0000-4000-8000-000000000002', 'Upload B', 'upload-b@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Upload authority fixture B.', true, 'approved', 'production'),
  ('ca030003-0000-4000-8000-000000000003', 'Upload C', 'upload-c@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Upload authority fixture C.', true, 'approved', 'production'),
  ('ca030004-0000-4000-8000-000000000004', 'Upload D', 'upload-d@example.test', 'business', 'EUR 3.200 t/m EUR 6.000', 'flexible', 'Upload authority fixture D.', true, 'approved', 'production');

set local session_replication_role = replica;
update lws_internal.operator_dossier_assignments
set assignee_operator_id = 'ca010000-0000-4000-8000-000000000004',
    revision = 1,
    assigned_at = statement_timestamp(),
    updated_at = statement_timestamp()
where quote_request_id = 'ca030002-0000-4000-8000-000000000002';
update lws_internal.operator_dossier_assignments
set assignee_operator_id = 'ca010000-0000-4000-8000-000000000005',
    revision = 1,
    assigned_at = statement_timestamp(),
    updated_at = statement_timestamp()
where quote_request_id = 'ca030001-0000-4000-8000-000000000001';
set local session_replication_role = origin;

set local session_replication_role = replica;
insert into public.customer_requests(
  request_id, request_reference, quote_request_id, customer_id, project_id, source,
  request_type, title, description, status, priority, submitted_at, submitter_type
) values
  ('ca020000-0000-4000-8000-000000000001', 'LWS-VRZ-2099-0801', 'ca030001-0000-4000-8000-000000000001', 'ca040000-0000-4000-8000-000000000001', 'ca050000-0000-4000-8000-000000000001', 'OPERATOR', 'FILE_DELIVERY', 'Upload A', 'Upload authority fixture A.', 'WAITING_CUSTOMER', 'NORMAL', statement_timestamp(), 'OPERATOR'),
  ('ca020000-0000-4000-8000-000000000002', 'LWS-VRZ-2099-0802', 'ca030002-0000-4000-8000-000000000002', 'ca040000-0000-4000-8000-000000000002', 'ca050000-0000-4000-8000-000000000002', 'OPERATOR', 'FILE_DELIVERY', 'Upload B', 'Upload authority fixture B.', 'WAITING_CUSTOMER', 'NORMAL', statement_timestamp(), 'OPERATOR'),
  ('ca020000-0000-4000-8000-000000000003', 'LWS-VRZ-2099-0803', 'ca030003-0000-4000-8000-000000000003', 'ca040000-0000-4000-8000-000000000003', 'ca050000-0000-4000-8000-000000000003', 'OPERATOR', 'FILE_DELIVERY', 'Upload C', 'Upload authority fixture C.', 'WAITING_CUSTOMER', 'NORMAL', statement_timestamp(), 'OPERATOR'),
  ('ca020000-0000-4000-8000-000000000004', 'LWS-VRZ-2099-0804', 'ca030004-0000-4000-8000-000000000004', 'ca040000-0000-4000-8000-000000000004', 'ca050000-0000-4000-8000-000000000004', 'OPERATOR', 'FILE_DELIVERY', 'Upload D', 'Upload authority fixture D.', 'WAITING_CUSTOMER', 'NORMAL', statement_timestamp(), 'OPERATOR');
set local session_replication_role = origin;

select set_config('request.jwt.claim.sub', 'ca000000-0000-4000-8000-000000000001', true);
select lives_ok($$
  select public.create_customer_request_upload_request_v1(
    'ca020000-0000-4000-8000-000000000001', repeat('a', 64), clock_timestamp() + interval '1 day', 'ca100000-0000-4000-8000-000000000001'
  )
$$, 'owner with WORK authority creates upload request');
select is(public.resolve_customer_request_upload_capability_v1(repeat('a', 64))->>'state', 'ACTIVE', 'valid capability resolves exactly one active request');
select is(public.resolve_customer_request_upload_capability_v1(repeat('f', 64))->>'state', 'INVALID_OR_EXPIRED_LINK', 'invalid capability is denied generically');
select is((select customer_request_id from public.customer_request_upload_requests where token_digest = repeat('a', 64)), 'ca020000-0000-4000-8000-000000000001'::uuid, 'digest binds to the server-selected Customer Request');
select is(public.get_customer_request_v1('ca020000-0000-4000-8000-000000000001')->'upload_request'->>'status', 'ACTIVE', 'operator detail exposes only safe active upload request metadata');

select set_config('request.jwt.claim.sub', 'ca000000-0000-4000-8000-000000000002', true);
select throws_ok($$
  select public.create_customer_request_upload_request_v1(
    'ca020000-0000-4000-8000-000000000002', repeat('b', 64), clock_timestamp() + interval '1 day', 'ca100000-0000-4000-8000-000000000002'
  )
$$, '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'create requires existing WORK authority and denies cross-customer access');
select set_config('request.jwt.claim.sub', 'ca000000-0000-4000-8000-000000000001', true);

select is(public.prepare_customer_request_upload_v1(repeat('a', 64), 'bewijs.exe', 'application/octet-stream', 1, 'ca110000-0000-4000-8000-000000000001')->>'state', 'VALIDATION_FAILED', 'unsupported MIME and extension are denied');
select is(public.prepare_customer_request_upload_v1(repeat('a', 64), 'bewijs.pdf', 'application/pdf', 8388609, 'ca110000-0000-4000-8000-000000000002')->>'state', 'VALIDATION_FAILED', 'file over eight MiB is denied');
select is(public.prepare_customer_request_upload_v1(repeat('a', 64), 'bewijs.pdf', 'application/pdf', 42, 'ca110000-0000-4000-8000-000000000003')->>'state', 'PREPARED', 'valid file reservation succeeds');
select ok((select storage_object_path like 'requests/ca020000-0000-4000-8000-000000000001/uploads/%/files/%.pdf' from public.customer_request_uploaded_files where original_file_name = 'bewijs.pdf'), 'object path is generated from authoritative bindings');
select is(public.prepare_customer_request_upload_v1(repeat('a', 64), 'twee.png', 'image/png', 1, 'ca110000-0000-4000-8000-000000000004')->>'state', 'PREPARED', 'second reservation succeeds');
select is(public.prepare_customer_request_upload_v1(repeat('a', 64), 'drie.jpg', 'image/jpeg', 1, 'ca110000-0000-4000-8000-000000000005')->>'state', 'PREPARED', 'third reservation succeeds');
select is(public.prepare_customer_request_upload_v1(repeat('a', 64), 'vier.jpeg', 'image/jpeg', 1, 'ca110000-0000-4000-8000-000000000006')->>'state', 'PREPARED', 'fourth reservation succeeds');
select is(public.prepare_customer_request_upload_v1(repeat('a', 64), 'vijf.pdf', 'application/pdf', 1, 'ca110000-0000-4000-8000-000000000007')->>'state', 'PREPARED', 'fifth reservation succeeds');
select is(public.prepare_customer_request_upload_v1(repeat('a', 64), 'zes.pdf', 'application/pdf', 1, 'ca110000-0000-4000-8000-000000000008')->>'state', 'LIMIT_EXCEEDED', 'PREPARED reservations count toward the five-file maximum');

set local session_replication_role = replica;
insert into public.customer_request_upload_requests(upload_request_id, customer_request_id, token_digest, status, expires_at, created_by_operator_id)
values ('ca060000-0000-4000-8000-000000000002', 'ca020000-0000-4000-8000-000000000002', repeat('b', 64), 'ACTIVE', clock_timestamp() + interval '1 day', 'ca010000-0000-4000-8000-000000000001');
set local session_replication_role = origin;
select is(public.prepare_customer_request_upload_v1(repeat('b', 64), 'a.pdf', 'application/pdf', 8388608, 'ca120000-0000-4000-8000-000000000001')->>'state', 'PREPARED', 'aggregate reservation one succeeds');
select is(public.prepare_customer_request_upload_v1(repeat('b', 64), 'b.pdf', 'application/pdf', 8388608, 'ca120000-0000-4000-8000-000000000002')->>'state', 'PREPARED', 'aggregate reservation two succeeds');
select is(public.prepare_customer_request_upload_v1(repeat('b', 64), 'c.pdf', 'application/pdf', 8388608, 'ca120000-0000-4000-8000-000000000003')->>'state', 'PREPARED', 'aggregate reservation three reaches 24 MiB');
select is(public.prepare_customer_request_upload_v1(repeat('b', 64), 'd.pdf', 'application/pdf', 2097153, 'ca120000-0000-4000-8000-000000000004')->>'state', 'LIMIT_EXCEEDED', 'PREPARED bytes enforce the 25 MiB aggregate maximum');

create temporary table upload_finalize_fixture as
select uploaded_file_id, storage_object_path from public.customer_request_uploaded_files
where upload_request_id = (select upload_request_id from public.customer_request_upload_requests where token_digest = repeat('a', 64))
  and original_file_name = 'bewijs.pdf';
insert into storage.objects(bucket_id, name, metadata)
select 'customer-request-quarantine', storage_object_path, '{"size":42,"mimetype":"application/pdf"}'::jsonb from upload_finalize_fixture;
select is(public.finalize_customer_request_uploaded_file_v1(repeat('a', 64), (select uploaded_file_id from upload_finalize_fixture), 'application/pdf', 42, repeat('1', 64), false, 'ca130000-0000-4000-8000-000000000001')->>'state', 'REJECTED', 'magic-byte mismatch rejects the quarantine object');

select is(public.prepare_customer_request_upload_v1(repeat('b', 64), 'small.png', 'image/png', 10, 'ca120000-0000-4000-8000-000000000005')->>'state', 'PREPARED', 'finalize fixture reservation succeeds');
create temporary table upload_accept_fixture as
select uploaded_file_id, storage_object_path from public.customer_request_uploaded_files where original_file_name = 'small.png';
insert into storage.objects(bucket_id, name, metadata)
select 'customer-request-quarantine', storage_object_path, '{"size":10,"mimetype":"image/png"}'::jsonb from upload_accept_fixture;
select is(public.finalize_customer_request_uploaded_file_v1(repeat('b', 64), (select uploaded_file_id from upload_accept_fixture), 'image/png', 10, repeat('2', 64), true, 'ca130000-0000-4000-8000-000000000002')->>'state', 'ACTIVE', 'matching observed size, MIME, signature, and SHA accepts object');
select is(public.finalize_customer_request_uploaded_file_v1(repeat('b', 64), (select uploaded_file_id from upload_accept_fixture), 'image/png', 10, repeat('2', 64), true, 'ca130000-0000-4000-8000-000000000002')->>'state', 'ACTIVE', 'finalize replay returns the idempotent result');
select is(public.finalize_customer_request_uploaded_file_v1(repeat('b', 64), gen_random_uuid(), 'image/png', 10, repeat('2', 64), true, 'ca130000-0000-4000-8000-000000000003')->>'state', 'VALIDATION_FAILED', 'wrong object reservation is denied');
select is(
  public.authorize_customer_request_upload_inbox_promotion_v1((select uploaded_file_id from upload_accept_fixture))->>'state',
  'AUTHORIZED',
  'accepted upload receives a server-derived private promotion contract'
);
insert into storage.objects(bucket_id, name, metadata)
values ('supplier-documents', 'documents/' || repeat('2', 64) || '.png', jsonb_build_object('size', 10, 'mimetype', 'image/png', 'sha256', repeat('2', 64)));
create temporary table upload_promotion_fixture as
select public.finalize_customer_request_upload_inbox_promotion_v1((select uploaded_file_id from upload_accept_fixture)) as result;
select is((select result->>'status' from upload_promotion_fixture), 'RECEIVED', 'accepted upload enters the existing pre-extraction Inbox state');
select is((select result->>'replayed' from upload_promotion_fixture), 'false', 'first accepted upload promotion is not a replay');
select is(
  public.finalize_customer_request_upload_inbox_promotion_v1((select uploaded_file_id from upload_accept_fixture))->>'document_inbox_item_id',
  (select result->>'document_inbox_item_id' from upload_promotion_fixture),
  'promotion replay returns the same canonical Inbox item'
);
select is((select count(*)::integer from public.document_inbox_customer_request_upload_sources where uploaded_file_id = (select uploaded_file_id from upload_accept_fixture)), 1, 'one uploaded_file_id has exactly one typed provenance row');
select is((select source_type from public.document_inbox_customer_request_upload_sources where uploaded_file_id = (select uploaded_file_id from upload_accept_fixture)), 'CUSTOMER_REQUEST_UPLOAD', 'typed provenance source is server-derived and fixed');
select is((select count(*)::integer from public.document_inbox_items where rtrim(sha256) = repeat('2', 64)), 1, 'promotion replay creates no duplicate Inbox item');
select is((select source_type from public.document_inbox_items where id = ((select result->>'document_inbox_item_id' from upload_promotion_fixture)::uuid)), 'CUSTOMER_REQUEST_UPLOAD', 'promotion source type is server-derived');
select is((select customer_request_id from public.document_inbox_customer_request_upload_sources where uploaded_file_id = (select uploaded_file_id from upload_accept_fixture)), 'ca020000-0000-4000-8000-000000000002'::uuid, 'provenance binds canonical customer_request_id');
select is((select quote_request_id from public.document_inbox_customer_request_upload_sources where uploaded_file_id = (select uploaded_file_id from upload_accept_fixture)), 'ca030002-0000-4000-8000-000000000002'::uuid, 'provenance binds canonical quote_request_id');

select set_config('request.jwt.claim.sub', 'ca000000-0000-4000-8000-000000000003', true);
select is(
  public.authorize_customer_request_upload_inbox_promotion_v1((select uploaded_file_id from upload_accept_fixture))->>'state',
  'PROMOTED',
  'operations manager retains existing WORK authority for promotion'
);
select set_config('request.jwt.claim.sub', 'ca000000-0000-4000-8000-000000000004', true);
select is(
  public.authorize_customer_request_upload_inbox_promotion_v1((select uploaded_file_id from upload_accept_fixture))->>'state',
  'PROMOTED',
  'assigned operator retains existing WORK authority for promotion'
);
select set_config('request.jwt.claim.sub', 'ca000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$select public.authorize_customer_request_upload_inbox_promotion_v1((select uploaded_file_id from upload_accept_fixture))$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'operator assigned to another dossier cannot promote this upload'
);
select set_config('request.jwt.claim.sub', 'ca000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.authorize_customer_request_upload_inbox_promotion_v1((select uploaded_file_id from upload_accept_fixture))$$,
  '42501', 'CUSTOMER_REQUEST_ACCESS_DENIED', 'unauthorized operator cannot promote across dossier authority'
);
select set_config('request.jwt.claim.sub', 'ca000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$select public.authorize_customer_request_upload_inbox_promotion_v1((select uploaded_file_id from public.customer_request_uploaded_files where original_file_name = 'a.pdf'))$$,
  '55000', 'CUSTOMER_REQUEST_UPLOAD_NOT_ACCEPTED', 'non-ACCEPTED upload cannot be promoted'
);

select is(public.prepare_customer_request_upload_v1(repeat('b', 64), 'mismatch.jpg', 'image/jpeg', 11, 'ca120000-0000-4000-8000-000000000006')->>'state', 'PREPARED', 'size mismatch fixture reservation succeeds');
create temporary table upload_mismatch_fixture as
select uploaded_file_id, storage_object_path from public.customer_request_uploaded_files where original_file_name = 'mismatch.jpg';
insert into storage.objects(bucket_id, name, metadata)
select 'customer-request-quarantine', storage_object_path, '{"size":10,"mimetype":"image/jpeg"}'::jsonb from upload_mismatch_fixture;
select is(public.finalize_customer_request_uploaded_file_v1(repeat('b', 64), (select uploaded_file_id from upload_mismatch_fixture), 'image/jpeg', 10, repeat('3', 64), true, 'ca130000-0000-4000-8000-000000000004')->>'state', 'REJECTED', 'actual size mismatch is denied');

select lives_ok($$
  select public.revoke_customer_request_upload_request_v1(
    (select upload_request_id from public.customer_request_upload_requests where token_digest = repeat('a', 64)),
    'Klant vroeg intrekking', 'ca140000-0000-4000-8000-000000000001'
  )
$$, 'WORK-authorized operator revokes upload request');
select is(public.resolve_customer_request_upload_capability_v1(repeat('a', 64))->>'state', 'INVALID_OR_EXPIRED_LINK', 'revoked capability is denied generically');
select is(public.cleanup_expired_customer_request_uploads_v1(100, 'ca150000-0000-4000-8000-000000000002')->>'expired_file_count', '4', 'cleanup claims abandoned PREPARED files after revocation');
select is((select count(*)::integer from public.customer_request_uploaded_files where upload_request_id = (select upload_request_id from public.customer_request_upload_requests where token_digest = repeat('a', 64)) and status = 'EXPIRED'), 4, 'revoked upload reservations become expired');

set local session_replication_role = replica;
insert into public.customer_request_upload_requests(upload_request_id, customer_request_id, token_digest, status, expires_at, created_at, created_by_operator_id)
values ('ca060000-0000-4000-8000-000000000003', 'ca020000-0000-4000-8000-000000000003', repeat('c', 64), 'ACTIVE', clock_timestamp() - interval '1 minute', clock_timestamp() - interval '1 day', 'ca010000-0000-4000-8000-000000000001');
insert into public.customer_request_uploaded_files(uploaded_file_id, upload_request_id, customer_request_id, storage_object_path, original_file_name, file_extension, declared_content_type, declared_byte_count)
values ('ca070000-0000-4000-8000-000000000003', 'ca060000-0000-4000-8000-000000000003', 'ca020000-0000-4000-8000-000000000003', 'requests/ca020000-0000-4000-8000-000000000003/uploads/ca060000-0000-4000-8000-000000000003/files/ca070000-0000-4000-8000-000000000003.pdf', 'expired.pdf', 'pdf', 'application/pdf', 20);
set local session_replication_role = origin;
select is(public.resolve_customer_request_upload_capability_v1(repeat('c', 64))->>'state', 'INVALID_OR_EXPIRED_LINK', 'expired capability is denied generically');
select is(public.cleanup_expired_customer_request_uploads_v1(100, 'ca150000-0000-4000-8000-000000000001')->>'state', 'CLEANED', 'cleanup expires abandoned requests and reservations');
select is(public.cleanup_expired_customer_request_uploads_v1(100, 'ca150000-0000-4000-8000-000000000001')->>'state', 'CLEANED', 'cleanup replay is idempotent');
select is((select status from public.customer_request_upload_requests where token_digest = repeat('c', 64)), 'EXPIRED', 'cleanup marks request expired');
select is((select status from public.customer_request_uploaded_files where uploaded_file_id = 'ca070000-0000-4000-8000-000000000003'), 'EXPIRED', 'cleanup marks abandoned reservation expired');

select * from finish();
rollback;