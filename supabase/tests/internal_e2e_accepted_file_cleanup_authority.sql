begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, storage, extensions;
select no_plan();

select has_function(
  'public', 'authorize_internal_e2e_accepted_file_cleanup_v1',
  array['uuid','uuid','uuid','uuid','uuid'],
  'Owner cleanup authorization exists'
);
select has_function(
  'public', 'finalize_internal_e2e_accepted_file_cleanup_v1',
  array['uuid','uuid'],
  'Owner cleanup finalization exists'
);
select is(
  pg_get_function_arguments(to_regprocedure('public.authorize_internal_e2e_accepted_file_cleanup_v1(uuid,uuid,uuid,uuid,uuid)')),
  'p_run_id uuid, p_request_id uuid, p_upload_request_id uuid, p_uploaded_file_id uuid, p_idempotency_key uuid',
  'authorization accepts exact entity bindings and no caller bucket or path'
);
select is(
  pg_get_function_arguments(to_regprocedure('public.finalize_internal_e2e_accepted_file_cleanup_v1(uuid,uuid)')),
  'p_cleanup_authorization_id uuid, p_idempotency_key uuid',
  'finalization accepts only server-issued authorization and idempotency identity'
);
select ok(
  has_function_privilege('authenticated', to_regprocedure('public.authorize_internal_e2e_accepted_file_cleanup_v1(uuid,uuid,uuid,uuid,uuid)'), 'execute')
  and has_function_privilege('authenticated', to_regprocedure('public.finalize_internal_e2e_accepted_file_cleanup_v1(uuid,uuid)'), 'execute')
  and not has_function_privilege('anon', to_regprocedure('public.authorize_internal_e2e_accepted_file_cleanup_v1(uuid,uuid,uuid,uuid,uuid)'), 'execute')
  and not has_function_privilege('service_role', to_regprocedure('public.finalize_internal_e2e_accepted_file_cleanup_v1(uuid,uuid)'), 'execute'),
  'only authenticated humans can enter cleanup authority'
);

insert into auth.users(id, email) values
  ('e1000000-0000-4000-8000-000000000001', 'cleanup-owner@example.test'),
  ('e1000000-0000-4000-8000-000000000002', 'cleanup-admin@example.test');
insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('e1100000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001', 'Cleanup Owner', 'owner', 'ACTIVE'),
  ('e1100000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000002', 'Cleanup Admin', 'admin', 'ACTIVE');

select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000001', true);
create temporary table cleanup_fixture as
select public.create_customer_request_smoke_fixture_v1(
  'e1200000-0000-4000-8000-000000000001'
) as result;

set local session_replication_role = replica;
insert into public.customer_request_upload_requests(
  upload_request_id, customer_request_id, token_digest, status, expires_at,
  created_by_operator_id, completed_at
) select
  'e1300000-0000-4000-8000-000000000001', (result->>'request_id')::uuid,
  repeat('e', 64), 'ACTIVE', clock_timestamp() + interval '1 hour',
  'e1100000-0000-4000-8000-000000000001', null
from cleanup_fixture;
insert into public.customer_request_uploaded_files(
  uploaded_file_id, upload_request_id, customer_request_id, status,
  storage_object_path, original_file_name, file_extension,
  declared_content_type, declared_byte_count, observed_content_type,
  observed_byte_count, sha256, accepted_at
) select
  'e1400000-0000-4000-8000-000000000001',
  'e1300000-0000-4000-8000-000000000001', (result->>'request_id')::uuid,
  'ACCEPTED',
  'requests/' || (result->>'request_id') || '/uploads/e1300000-0000-4000-8000-000000000001/files/e1400000-0000-4000-8000-000000000001.png',
  'lws-smoke-b-synthetic.png', 'png', 'image/png', 68, 'image/png', 68,
  repeat('a', 64), clock_timestamp()
from cleanup_fixture;
insert into storage.objects(bucket_id, name, metadata)
values (
  'customer-request-quarantine',
  'requests/' || (select result->>'request_id' from cleanup_fixture) || '/uploads/e1300000-0000-4000-8000-000000000001/files/e1400000-0000-4000-8000-000000000001.png',
  '{"size":68,"mimetype":"image/png"}'::jsonb
);

insert into public.customer_requests(
  request_id, request_reference, quote_request_id, customer_id, project_id,
  source, request_type, title, description, status, priority, submitted_at,
  submitter_type
) values (
  'e1500000-0000-4000-8000-000000000001', 'LWS-VRZ-2099-0901',
  'e1510000-0000-4000-8000-000000000001',
  'e1520000-0000-4000-8000-000000000001',
  'e1530000-0000-4000-8000-000000000001',
  'OPERATOR', 'FILE_DELIVERY', 'Real request', 'Non-synthetic fixture.',
  'WAITING_CUSTOMER', 'NORMAL', clock_timestamp(), 'OPERATOR'
);
insert into public.customer_request_upload_requests(
  upload_request_id, customer_request_id, token_digest, status, expires_at,
  created_by_operator_id, completed_at
) values (
  'e1300000-0000-4000-8000-000000000002',
  'e1500000-0000-4000-8000-000000000001', repeat('f', 64), 'COMPLETED',
  clock_timestamp() + interval '1 hour',
  'e1100000-0000-4000-8000-000000000001', clock_timestamp()
);
insert into public.customer_request_uploaded_files(
  uploaded_file_id, upload_request_id, customer_request_id, status,
  storage_object_path, original_file_name, file_extension,
  declared_content_type, declared_byte_count, observed_content_type,
  observed_byte_count, sha256, accepted_at
) values (
  'e1400000-0000-4000-8000-000000000002',
  'e1300000-0000-4000-8000-000000000002',
  'e1500000-0000-4000-8000-000000000001', 'ACCEPTED',
  'requests/e1500000-0000-4000-8000-000000000001/uploads/e1300000-0000-4000-8000-000000000002/files/e1400000-0000-4000-8000-000000000002.png',
  'real.png', 'png', 'image/png', 68, 'image/png', 68, repeat('b', 64),
  clock_timestamp()
);
set local session_replication_role = origin;

create temporary table cleanup_authorization(result jsonb);
create function pg_temp.capture_cleanup_authorization(
  p_run_id uuid,
  p_request_id uuid,
  p_upload_request_id uuid,
  p_uploaded_file_id uuid,
  p_idempotency_key uuid
) returns void language plpgsql as $$
begin
  execute 'insert into cleanup_authorization(result) select public.authorize_internal_e2e_accepted_file_cleanup_v1($1,$2,$3,$4,$5)'
  using p_run_id, p_request_id, p_upload_request_id, p_uploaded_file_id, p_idempotency_key;
end;
$$;

select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000002', true);
select throws_ok(
  format(
    'select public.authorize_internal_e2e_accepted_file_cleanup_v1(%L,%L,%L,%L,%L)',
    (select result->>'run_id' from cleanup_fixture),
    (select result->>'request_id' from cleanup_fixture),
    'e1300000-0000-4000-8000-000000000001',
    'e1400000-0000-4000-8000-000000000001',
    'e1600000-0000-4000-8000-000000000001'
  ),
  '42501', 'INTERNAL_E2E_OWNER_REQUIRED', 'non-owner cannot authorize cleanup'
);

select set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000001', true);
select throws_ok(
  format(
    'select public.authorize_internal_e2e_accepted_file_cleanup_v1(%L,%L,%L,%L,%L)',
    (select result->>'run_id' from cleanup_fixture),
    'e1500000-0000-4000-8000-000000000001',
    'e1300000-0000-4000-8000-000000000002',
    'e1400000-0000-4000-8000-000000000002',
    'e1600000-0000-4000-8000-000000000002'
  ),
  '42501', 'INTERNAL_E2E_CLEANUP_BINDING_REQUIRED', 'real accepted file is denied'
);
select throws_ok(
  format(
    'select public.authorize_internal_e2e_accepted_file_cleanup_v1(%L,%L,%L,%L,%L)',
    (select result->>'run_id' from cleanup_fixture),
    (select result->>'request_id' from cleanup_fixture),
    'e1300000-0000-4000-8000-000000000002',
    'e1400000-0000-4000-8000-000000000001',
    'e1600000-0000-4000-8000-000000000003'
  ),
  '42501', 'INTERNAL_E2E_CLEANUP_BINDING_REQUIRED', 'cross-bound upload request is denied'
);
select throws_ok(
  format(
    'select public.authorize_internal_e2e_accepted_file_cleanup_v1(%L,%L,%L,%L,%L)',
    (select result->>'run_id' from cleanup_fixture),
    (select result->>'request_id' from cleanup_fixture),
    'e1300000-0000-4000-8000-000000000001',
    'e1400000-0000-4000-8000-000000000001',
    'e1600000-0000-4000-8000-000000000007'
  ),
  'P0001', 'INTERNAL_E2E_UPLOAD_REQUEST_TERMINAL_REQUIRED',
  'ACTIVE upload request is denied to close concurrent prepare authority before cleanup'
);
set local session_replication_role = replica;
update public.customer_request_upload_requests
set status = 'REVOKED', revoked_at = clock_timestamp(),
    revoked_by_operator_id = 'e1100000-0000-4000-8000-000000000001',
    revocation_reason = 'Synthetic partial-state cleanup'
where upload_request_id = 'e1300000-0000-4000-8000-000000000001';
set local session_replication_role = origin;

set local session_replication_role = replica;
update public.customer_request_uploaded_files
set status = 'PREPARED', accepted_at = null, observed_content_type = null,
    observed_byte_count = null, sha256 = null
where uploaded_file_id = 'e1400000-0000-4000-8000-000000000001';
set local session_replication_role = origin;
select throws_ok(
  format(
    'select public.authorize_internal_e2e_accepted_file_cleanup_v1(%L,%L,%L,%L,%L)',
    (select result->>'run_id' from cleanup_fixture),
    (select result->>'request_id' from cleanup_fixture),
    'e1300000-0000-4000-8000-000000000001',
    'e1400000-0000-4000-8000-000000000001',
    'e1600000-0000-4000-8000-000000000004'
  ),
  'P0001', 'ACCEPTED_INTERNAL_E2E_FILE_REQUIRED', 'PREPARED file is denied'
);
set local session_replication_role = replica;
update public.customer_request_uploaded_files
set status = 'ACCEPTED', accepted_at = clock_timestamp(),
    observed_content_type = 'image/png', observed_byte_count = 68,
    sha256 = repeat('a', 64)
where uploaded_file_id = 'e1400000-0000-4000-8000-000000000001';
set local session_replication_role = origin;

select lives_ok(
  format(
    'select pg_temp.capture_cleanup_authorization(%L,%L,%L,%L,%L)',
    (select result->>'run_id' from cleanup_fixture),
    (select result->>'request_id' from cleanup_fixture),
    'e1300000-0000-4000-8000-000000000001',
    'e1400000-0000-4000-8000-000000000001',
    'e1600000-0000-4000-8000-000000000005'
  ),
  'synthetic ACCEPTED file can be authorized after its upload request is REVOKED'
);
select is((select result->>'state' from cleanup_authorization), 'AUTHORIZED', 'authorization state is explicit');
select is((select result->>'storage_bucket_id' from cleanup_authorization), 'customer-request-quarantine', 'bucket is server-derived');
select is(
  (select result->>'storage_object_path' from cleanup_authorization),
  (select storage_object_path from public.customer_request_uploaded_files where uploaded_file_id = 'e1400000-0000-4000-8000-000000000001'),
  'object path is server-derived from the exact file binding'
);

select lives_ok(
  format(
    'select public.authorize_internal_e2e_accepted_file_cleanup_v1(%L,%L,%L,%L,%L)',
    (select result->>'run_id' from cleanup_fixture),
    (select result->>'request_id' from cleanup_fixture),
    'e1300000-0000-4000-8000-000000000001',
    'e1400000-0000-4000-8000-000000000001',
    'e1600000-0000-4000-8000-000000000005'
  ),
  'authorization replay is idempotent'
);
select throws_ok(
  format(
    'select public.finalize_internal_e2e_accepted_file_cleanup_v1(%L,%L)',
    (select result->>'cleanup_authorization_id' from cleanup_authorization),
    'e1700000-0000-4000-8000-000000000001'
  ),
  'P0001', 'INTERNAL_E2E_STORAGE_OBJECT_STILL_EXISTS',
  'database finalization refuses to claim deletion while Storage object exists'
);

set local session_replication_role = replica;
update public.customer_requests set status = 'CANCELLED'
where request_id = (select (result->>'request_id')::uuid from cleanup_fixture);
set local session_replication_role = origin;
select throws_ok(
  format(
    'select public.finalize_internal_e2e_run_v1(%L,%L,%s,%L)',
    (select result->>'run_id' from cleanup_fixture), 'PASSED', 0,
    'e1800000-0000-4000-8000-000000000001'
  ),
  'P0001', 'INTERNAL_E2E_CUSTOMER_REQUEST_CLEANUP_REQUIRED',
  'fixture run remains blocked while the accepted file is not deleted'
);

set local session_replication_role = replica;
delete from storage.objects
where bucket_id = 'customer-request-quarantine'
  and name = (select result->>'storage_object_path' from cleanup_authorization);
set local session_replication_role = origin;
create temporary table cleanup_finalization(result jsonb);
create function pg_temp.capture_cleanup_finalization(
  p_cleanup_authorization_id uuid,
  p_idempotency_key uuid
) returns void language plpgsql as $$
begin
  execute 'insert into cleanup_finalization(result) select public.finalize_internal_e2e_accepted_file_cleanup_v1($1,$2)'
  using p_cleanup_authorization_id, p_idempotency_key;
end;
$$;
select lives_ok(
  format(
    'select pg_temp.capture_cleanup_finalization(%L,%L)',
    (select result->>'cleanup_authorization_id' from cleanup_authorization),
    'e1700000-0000-4000-8000-000000000002'
  ),
  'finalization succeeds only after exact object absence'
);
select is((select result->>'state' from cleanup_finalization), 'DELETED', 'finalization reports DELETED');
select is(
  (select row(status, deleted_at is not null)::text from public.customer_request_uploaded_files where uploaded_file_id = 'e1400000-0000-4000-8000-000000000001'),
  row('DELETED', true)::text,
  'accepted row is retained and transitions to DELETED with deletion time'
);
select lives_ok(
  format(
    'select public.finalize_internal_e2e_accepted_file_cleanup_v1(%L,%L)',
    (select result->>'cleanup_authorization_id' from cleanup_authorization),
    'e1700000-0000-4000-8000-000000000002'
  ),
  'finalization replay is idempotent'
);
select throws_ok(
  format(
    'select public.authorize_internal_e2e_accepted_file_cleanup_v1(%L,%L,%L,%L,%L)',
    (select result->>'run_id' from cleanup_fixture),
    (select result->>'request_id' from cleanup_fixture),
    'e1300000-0000-4000-8000-000000000001',
    'e1400000-0000-4000-8000-000000000001',
    'e1600000-0000-4000-8000-000000000006'
  ),
  'P0001', 'INTERNAL_E2E_FILE_ALREADY_DELETED',
  'new authorization key cannot reopen terminal cleanup'
);
create temporary table cleanup_run_finalization(result jsonb);
select lives_ok(
  format(
    'insert into cleanup_run_finalization(result) select public.finalize_internal_e2e_run_v1(%L,%L,%s,%L)',
    (select result->>'run_id' from cleanup_fixture), 'PASSED', 0,
    'e1800000-0000-4000-8000-000000000002'
  ),
  'fixture run can finalize after retained file reaches DELETED'
);
select is((select result->>'status' from cleanup_run_finalization), 'PASSED', 'post-cleanup run status is PASSED');

select * from finish();
rollback;