insert into auth.users(id, email) values
  ('fa000000-0000-4000-8000-000000000099', 'inbox-readonly-owner@example.test')
on conflict (id) do nothing;
insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('fa010000-0000-4000-8000-000000000099', 'fa000000-0000-4000-8000-000000000099', 'Inbox Readonly Owner', 'owner', 'ACTIVE')
on conflict (operator_id) do nothing;

begin transaction read only;
select set_config('request.jwt.claim.sub', 'fa000000-0000-4000-8000-000000000099', true);
select public.get_document_inbox_v1(null, 'production');
rollback;

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, storage, extensions;

select no_plan();

select has_table('public', 'document_inbox_items', 'document inbox item authority exists');
select has_table('public', 'document_inbox_events', 'document inbox immutable event ledger exists');
select has_table('public', 'document_inbox_customer_request_upload_sources', 'Customer Request upload provenance reuses the existing Inbox');
select has_function('public', 'receive_document_inbox_item_v1', array['text','text','text','bigint','text','text','text','text'], 'receive RPC exists');
select has_function('public', 'record_document_inbox_extraction_v1', array['uuid','bigint','text','text','text','jsonb','text'], 'extraction placeholder RPC exists');
select has_function('public', 'update_document_inbox_proposal_v1', array['uuid','bigint','text','text','text','date','bigint','text','text','text','date','text','jsonb'], 'proposal RPC exists');
select has_function('public', 'confirm_document_inbox_values_v1', array['uuid','bigint','text','text','text','date','bigint','text','text','text','date','text'], 'confirmed values RPC exists');
select has_function('public', 'approve_document_inbox_item_v1', array['uuid','bigint','boolean'], 'approval RPC exists');
select has_function('public', 'reject_document_inbox_item_v1', array['uuid','bigint','text'], 'rejection RPC exists');
select has_function('public', 'process_document_inbox_item_v1', array['uuid','bigint'], 'transactional processing RPC exists');
select has_function('public', 'get_document_inbox_v1', array['text','text'], 'owner list/read RPC exists');
select has_function('public', 'authorize_customer_request_upload_inbox_promotion_v1', array['uuid'], 'Customer Request upload promotion authorization exists');
select has_function('public', 'finalize_customer_request_upload_inbox_promotion_v1', array['uuid'], 'Customer Request upload promotion finalization exists');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.document_inbox_items'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.document_inbox_events'::regclass),
  'both inbox tables have RLS enabled'
);
select ok(
  not has_table_privilege('authenticated', 'public.document_inbox_items', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.document_inbox_items', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.document_inbox_items', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.document_inbox_events', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.document_inbox_events', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'public.document_inbox_events', 'select,insert,update,delete'),
  'browser and service roles have no direct inbox table authority'
);
select ok(
  has_function_privilege('authenticated', 'public.receive_document_inbox_item_v1(text,text,text,bigint,text,text,text,text)', 'execute')
  and has_function_privilege('authenticated', 'public.process_document_inbox_item_v1(uuid,bigint)', 'execute')
  and not has_function_privilege('anon', 'public.receive_document_inbox_item_v1(text,text,text,bigint,text,text,text,text)', 'execute')
  and not has_function_privilege('service_role', 'public.process_document_inbox_item_v1(uuid,bigint)', 'execute'),
  'only authenticated receives guarded inbox command execution'
);
select ok(
  not has_table_privilege('authenticated', 'public.document_inbox_customer_request_upload_sources', 'select,insert,update,delete')
  and not has_table_privilege('anon', 'public.document_inbox_customer_request_upload_sources', 'select,insert,update,delete')
  and not has_function_privilege('anon', 'public.authorize_customer_request_upload_inbox_promotion_v1(uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.finalize_customer_request_upload_inbox_promotion_v1(uuid)', 'execute'),
  'provenance has no direct browser writes and promotion requires caller-JWT authority'
);
select ok(
  exists (select 1 from pg_trigger where tgrelid = 'public.document_inbox_events'::regclass and tgname = 'trg_document_inbox_events_immutable' and tgenabled <> 'D'),
  'audit event immutability trigger is enabled'
);
select matches(
  (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.document_inbox_items'::regclass and conname = 'document_inbox_items_lifecycle_valid'),
  'RECEIVED.*REVIEW_REQUIRED.*APPROVED.*PROCESSED.*REJECTED',
  'lifecycle contains exactly the bounded states'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'document_inbox_items'
      and column_name in ('supplier_id','payment_state','vat_amount_minor','bank_transaction_id','gmail_message_id','drive_file_id')
  ),
  'inbox adds no supplier master payment VAT banking Gmail or Drive authority'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.document_inbox_items'::regclass
      and conname = 'document_inbox_items_binary_unique' and contype = 'u'
  ),
  'one inbox item per binary is enforced by SHA-256 uniqueness'
);
select ok(
  not exists (
    select 1 from pg_constraint
    where conrelid = 'public.document_inbox_items'::regclass and contype = 'u'
      and pg_get_constraintdef(oid) ~* '(supplier|reference|amount|date)'
  ),
  'business fingerprint is not a hard uniqueness authority'
);
select ok(
  position('create_business_expense_v1' in pg_get_functiondef('public.process_document_inbox_item_v1(uuid,bigint)'::regprocedure)) > 0
  and position('create_supplier_document_v1' in pg_get_functiondef('public.process_document_inbox_item_v1(uuid,bigint)'::regprocedure)) > 0
  and position('link_business_expense_document_v1' in pg_get_functiondef('public.process_document_inbox_item_v1(uuid,bigint)'::regprocedure)) > 0
  and position('for update' in lower(pg_get_functiondef('public.process_document_inbox_item_v1(uuid,bigint)'::regprocedure))) > 0,
  'processing row-locks the item and reuses all three existing authorities'
);
select ok(
  position('for share' in lower(pg_get_functiondef('public.require_document_inbox_owner_v1()'::regprocedure))) = 0
  and position('for update' in lower(pg_get_functiondef('public.require_document_inbox_owner_v1()'::regprocedure))) = 0
  and position('for share' in lower(pg_get_functiondef('public.get_document_inbox_v1(text,text)'::regprocedure))) = 0
  and position('for update' in lower(pg_get_functiondef('public.get_document_inbox_v1(text,text)'::regprocedure))) = 0,
  'owner authorization and inbox read path require no row lock'
);
select ok(
  position('for update' in lower(pg_get_functiondef('public.approve_document_inbox_item_v1(uuid,bigint,boolean)'::regprocedure))) > 0
  and position('for update' in lower(pg_get_functiondef('public.reject_document_inbox_item_v1(uuid,bigint,text)'::regprocedure))) > 0
  and position('for update' in lower(pg_get_functiondef('public.process_document_inbox_item_v1(uuid,bigint)'::regprocedure))) > 0,
  'approve reject and process retain mutation row locking'
);

insert into auth.users(id, email) values
  ('fa000000-0000-4000-8000-000000000001', 'inbox-owner@example.test'),
  ('fa000000-0000-4000-8000-000000000002', 'inbox-admin@example.test'),
  ('fa000000-0000-4000-8000-000000000003', 'inbox-disabled@example.test'),
  ('fa000000-0000-4000-8000-000000000004', 'inbox-revoked@example.test');

insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status, revoked_at) values
  ('fa010000-0000-4000-8000-000000000001', 'fa000000-0000-4000-8000-000000000001', 'Inbox Owner', 'owner', 'ACTIVE', null),
  ('fa010000-0000-4000-8000-000000000002', 'fa000000-0000-4000-8000-000000000002', 'Inbox Admin', 'admin', 'ACTIVE', null),
  ('fa010000-0000-4000-8000-000000000003', 'fa000000-0000-4000-8000-000000000003', 'Inbox Disabled', 'owner', 'DISABLED', null),
  ('fa010000-0000-4000-8000-000000000004', 'fa000000-0000-4000-8000-000000000004', 'Inbox Revoked', 'owner', 'REVOKED', clock_timestamp());

insert into storage.objects(bucket_id, name, metadata) values
  ('supplier-documents', 'documents/' || repeat('a',64) || '.pdf', jsonb_build_object('size',101,'mimetype','application/pdf','sha256',repeat('a',64))),
  ('supplier-documents', 'documents/' || repeat('b',64) || '.png', jsonb_build_object('size',102,'mimetype','image/png','sha256',repeat('b',64))),
  ('supplier-documents', 'documents/' || repeat('c',64) || '.jpg', jsonb_build_object('size',103,'mimetype','image/jpeg','sha256',repeat('c',64))),
  ('supplier-documents', 'documents/' || repeat('d',64) || '.pdf', jsonb_build_object('size',104,'mimetype','application/pdf','sha256',repeat('d',64))),
  ('supplier-documents', 'documents/' || repeat('e',64) || '.pdf', jsonb_build_object('size',105,'mimetype','application/pdf','sha256',repeat('e',64))),
  ('supplier-documents', 'documents/' || repeat('f',64) || '.pdf', jsonb_build_object('size',999,'mimetype','application/pdf','sha256',repeat('f',64))),
  ('supplier-documents', 'documents/' || repeat('1',64) || '.pdf', jsonb_build_object('size',106,'mimetype','application/pdf','sha256',repeat('1',64)));

select throws_ok(
  $$select public.receive_document_inbox_item_v1(repeat('a',64),'invoice.pdf','application/pdf',101)$$,
  '42501', 'HUMAN_JWT_REQUIRED', 'anonymous receive is denied'
);
select set_config('request.jwt.claim.sub', 'fa000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$select public.receive_document_inbox_item_v1(repeat('a',64),'invoice.pdf','application/pdf',101)$$,
  '42501', 'DOCUMENT_INBOX_OWNER_REQUIRED', 'active non-owner receive is denied'
);
select throws_ok(
  $$select public.get_document_inbox_v1(null,'production')$$,
  '42501', 'DOCUMENT_INBOX_OWNER_REQUIRED', 'active non-owner inbox read is denied'
);
select set_config('request.jwt.claim.sub', 'fa000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$select public.receive_document_inbox_item_v1(repeat('a',64),'invoice.pdf','application/pdf',101)$$,
  '42501', 'OPERATOR_DISABLED', 'disabled owner receive is denied'
);
select set_config('request.jwt.claim.sub', 'fa000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$select public.receive_document_inbox_item_v1(repeat('a',64),'invoice.pdf','application/pdf',101)$$,
  '42501', 'OPERATOR_REVOKED', 'revoked owner receive is denied'
);
select set_config('request.jwt.claim.sub', 'fa000000-0000-4000-8000-000000000001', true);

select throws_ok(
  $$select public.receive_document_inbox_item_v1(repeat('9',64),'missing.pdf','application/pdf',109)$$,
  'P0001', 'DOCUMENT_INBOX_OBJECT_NOT_FOUND', 'receive requires an existing canonical object'
);
select throws_ok(
  $$select public.receive_document_inbox_item_v1(repeat('f',64),'mismatch.pdf','application/pdf',106)$$,
  'P0001', 'DOCUMENT_INBOX_OBJECT_METADATA_MISMATCH', 'receive requires finalized matching storage metadata'
);
select throws_ok(
  $$select public.receive_document_inbox_item_v1(repeat('a',64),'invoice.pdf','application/pdf',101,'GMAIL')$$,
  '22023', 'DOCUMENT_INBOX_SOURCE_NOT_ENABLED', 'future sources remain disabled in the first authority version'
);

create temporary table received as
select public.receive_document_inbox_item_v1(
  repeat('a',64), 'invoice-a.pdf', 'application/pdf', 101,
  'MANUAL_UPLOAD', 'owner-console', 'manual-001', 'production'
) as result;
select ok(((select result from received)->>'id')::uuid is not null, 'active owner receives a validated canonical object');
select is((select result->>'status' from received), 'RECEIVED', 'new inbox item starts RECEIVED');
select is((select (result->>'revision')::bigint from received), 1::bigint, 'new inbox item starts at revision one');
select is((select count(*)::integer from public.document_inbox_events where event_type = 'RECEIVED'), 1, 'first receive writes one audit event');

create temporary table replay as
select public.receive_document_inbox_item_v1(
  repeat('a',64), 'invoice-a.pdf', 'application/pdf', 101,
  'MANUAL_UPLOAD', 'owner-console', 'manual-001', 'production'
) as result;
select is((select result->>'id' from replay), (select result->>'id' from received), 'same binary receive returns the same inbox item');
select is((select result->>'replayed' from replay), 'true', 'same binary receive is explicitly marked replayed');
select is((select count(*)::integer from public.document_inbox_items where rtrim(sha256) = repeat('a',64)), 1, 'same binary creates no duplicate inbox item');
select is((select count(*)::integer from public.document_inbox_events where event_type = 'RECEIVED'), 1, 'binary replay creates no duplicate receive event');

select public.receive_document_inbox_item_v1(repeat('b',64),'receipt.png','image/png',102,'MANUAL_UPLOAD','owner-console','manual-002','production');
select throws_ok(
  $$select public.receive_document_inbox_item_v1(repeat('c',64),'receipt.jpg','image/jpeg',103,'MANUAL_UPLOAD','owner-console','manual-002','production')$$,
  '23505', 'DOCUMENT_INBOX_SOURCE_REPLAY_CONFLICT', 'same external source identity cannot bind another binary'
);

create temporary table proposal as
select public.update_document_inbox_proposal_v1(
  ((select result->>'id' from received)::uuid), 1,
  '  Proposed Supplier  ', 'invoice', ' INV-A ', '2026-08-28',
  12345, 'eur', ' Proposed hosting ', 'hosting', '2026-08-29', 'invoice',
  '[{"code":"LOW_CONFIDENCE"}]'::jsonb
) as result;
select is((select result->>'status' from proposal), 'REVIEW_REQUIRED', 'proposal moves RECEIVED to REVIEW_REQUIRED');
select is((select proposed_supplier_name from public.document_inbox_items where id = ((select result->>'id' from received)::uuid)), 'Proposed Supplier', 'proposal values are normalized and stored');
select is((select confirmed_supplier_name from public.document_inbox_items where id = ((select result->>'id' from received)::uuid)), null, 'proposal never silently populates confirmed values');
select throws_ok(
  $$select public.update_document_inbox_proposal_v1(((select result->>'id' from received)::uuid),2,'Supplier','PAYMENT_EVIDENCE',null,null,100,'EUR','Purpose','hosting','2026-08-29','INVOICE','[]')$$,
  '22023', 'INVALID_DOCUMENT_INBOX_DOCUMENT_TYPE', 'PAYMENT_EVIDENCE proposal is denied'
);
select throws_ok(
  $$select public.update_document_inbox_proposal_v1(((select result->>'id' from received)::uuid),2,'Supplier','INVOICE',null,null,100,'EUR','Purpose','travel','2026-08-29','INVOICE','[]')$$,
  '22023', 'INVALID_DOCUMENT_INBOX_CATEGORY', 'unknown expense category is denied'
);
select throws_ok(
  $$select public.update_document_inbox_proposal_v1(((select result->>'id' from received)::uuid),2,'Supplier','INVOICE',null,null,100,'USD','Purpose','hosting','2026-08-29','INVOICE','[]')$$,
  '22023', 'INVALID_DOCUMENT_INBOX_CURRENCY', 'non-EUR proposal is denied'
);

select public.confirm_document_inbox_values_v1(
  ((select result->>'id' from received)::uuid), 2,
  'Confirmed Supplier', 'INVOICE', 'INV-A', '2026-08-28',
  12345, 'EUR', 'Confirmed hosting expense', 'hosting', '2026-08-29', 'INVOICE'
);
select is((select proposed_supplier_name from public.document_inbox_items where id = ((select result->>'id' from received)::uuid)), 'Proposed Supplier', 'confirmed update preserves proposed evidence');
select is((select confirmed_supplier_name from public.document_inbox_items where id = ((select result->>'id' from received)::uuid)), 'Confirmed Supplier', 'owner confirmed values are stored separately');
select throws_ok(
  $$select public.approve_document_inbox_item_v1(((select result->>'id' from received)::uuid),3,false)$$,
  '22023', 'DOCUMENT_INBOX_WARNINGS_ACKNOWLEDGEMENT_REQUIRED', 'warnings require explicit owner acknowledgement'
);
select public.approve_document_inbox_item_v1(((select result->>'id' from received)::uuid),3,true);
select is((select lifecycle_status from public.document_inbox_items where id = ((select result->>'id' from received)::uuid)), 'APPROVED', 'confirmed review becomes APPROVED');
select throws_ok(
  $$select public.approve_document_inbox_item_v1(((select result->>'id' from received)::uuid),4,true)$$,
  '23514', 'DOCUMENT_INBOX_NOT_APPROVABLE', 'approval is not double executable'
);

create temporary table processed as
select public.process_document_inbox_item_v1(((select result->>'id' from received)::uuid),4) as result;
select is((select result->>'ok' from processed), 'true', 'approved item processes successfully');
select is((select result->>'status' from processed), 'PROCESSED', 'successful coordinator reaches PROCESSED');
select ok(
  (select result->>'business_expense_id' is not null and result->>'supplier_document_id' is not null and result->>'link_id' is not null from processed),
  'processing returns all definitive result identities'
);
select is((select count(*)::integer from public.business_expenses where internal_reference = 'DOCUMENT-INBOX:' || ((select result->>'id' from received))), 1, 'processing creates exactly one existing-authority expense');
select is((select count(*)::integer from public.supplier_documents where rtrim(sha256) = repeat('a',64)), 1, 'processing creates exactly one existing-authority supplier document');
select is((select count(*)::integer from public.business_expense_documents where id = ((select result->>'link_id' from processed)::uuid)), 1, 'processing creates exactly one existing-authority link');

create temporary table process_replay as
select public.process_document_inbox_item_v1(((select result->>'id' from received)::uuid),4) as result;
select is((select result->>'replayed' from process_replay), 'true', 'lost process response retry returns a replay');
select is((select result->>'business_expense_id' from process_replay), (select result->>'business_expense_id' from processed), 'process retry returns the existing expense id');
select is((select count(*)::integer from public.business_expenses where internal_reference = 'DOCUMENT-INBOX:' || ((select result->>'id' from received))), 1, 'processed replay creates no second expense');
select is((select count(*)::integer from public.document_inbox_events where inbox_item_id = ((select result->>'id' from received)::uuid) and event_type = 'PROCESSED'), 1, 'processed replay creates no second completion event');

create temporary table rejected as
select public.receive_document_inbox_item_v1(repeat('c',64),'reject.jpg','image/jpeg',103) as received;
select public.reject_document_inbox_item_v1(((select received->>'id' from rejected)::uuid),1,'Not a business document');
select is((select lifecycle_status from public.document_inbox_items where id = ((select received->>'id' from rejected)::uuid)), 'REJECTED', 'RECEIVED may transition to terminal REJECTED');
select is((select count(*)::integer from public.business_expenses where internal_reference = 'DOCUMENT-INBOX:' || ((select received->>'id' from rejected))), 0, 'rejection creates no expense');
select throws_ok(
  $$update public.document_inbox_items set lifecycle_status='REVIEW_REQUIRED',revision=revision+1 where id=((select received->>'id' from rejected)::uuid)$$,
  '55000', 'DOCUMENT_INBOX_ITEM_TERMINAL', 'rejected item cannot transition again'
);

create temporary table extracted as
select public.receive_document_inbox_item_v1(repeat('d',64),'extract.pdf','application/pdf',104) as received;
select public.record_document_inbox_extraction_v1(
  ((select received->>'id' from extracted)::uuid),1,'PARTIAL','synthetic-provider','contract-v1',
  '{"supplier_name":{"value":"Candidate","confidence":0.7,"evidence":"page:1"}}'::jsonb,null
);
select is((select extraction_status from public.document_inbox_items where id=((select received->>'id' from extracted)::uuid)), 'PARTIAL', 'synthetic extraction evidence is recorded without OCR');
select is((select proposed_supplier_name from public.document_inbox_items where id=((select received->>'id' from extracted)::uuid)), null, 'extraction candidates do not silently become proposals');
select is((select lifecycle_status from public.document_inbox_items where id=((select received->>'id' from extracted)::uuid)), 'REVIEW_REQUIRED', 'extraction result moves item to human review');

insert into public.supplier_documents(
  id, document_type, supplier_name, original_file_name, mime_type, byte_count,
  storage_object_path, sha256, record_classification, created_by_operator_id
) values (
  'fa020000-0000-4000-8000-000000000001','INVOICE','Existing Production','existing.pdf','application/pdf',105,
  'documents/' || repeat('e',64) || '.pdf',repeat('e',64),'production','fa010000-0000-4000-8000-000000000001'
);
create temporary table failing as
select public.receive_document_inbox_item_v1(repeat('e',64),'internal.pdf','application/pdf',105,'MANUAL_UPLOAD',null,null,'internal_e2e') as received;
select public.update_document_inbox_proposal_v1(((select received->>'id' from failing)::uuid),1,'Internal','INVOICE',null,null,100,'EUR','Internal test','other','2026-08-29','INVOICE','[]');
select public.confirm_document_inbox_values_v1(((select received->>'id' from failing)::uuid),2,'Internal','INVOICE',null,null,100,'EUR','Internal test','other','2026-08-29','INVOICE');
select public.approve_document_inbox_item_v1(((select received->>'id' from failing)::uuid),3,false);
create temporary table failed_process as
select public.process_document_inbox_item_v1(((select received->>'id' from failing)::uuid),4) as result;
select is((select result->>'ok' from failed_process), 'false', 'forced downstream classification failure is contained');
select is((select lifecycle_status from public.document_inbox_items where id=((select received->>'id' from failing)::uuid)), 'APPROVED', 'failed processing remains retryable APPROVED');
select is((select count(*)::integer from public.business_expenses where internal_reference='DOCUMENT-INBOX:' || ((select received->>'id' from failing))), 0, 'failed document step rolls back the earlier expense create');
select is((select count(*)::integer from public.business_expense_documents where business_expense_id in (select result_business_expense_id from public.document_inbox_items where id=((select received->>'id' from failing)::uuid))), 0, 'failed processing leaves no link');
select is((select count(*)::integer from public.document_inbox_events where inbox_item_id=((select received->>'id' from failing)::uuid) and event_type='PROCESSING_ERROR'), 1, 'failed processing records one compact audit error');
select is((select processing_attempts from public.document_inbox_items where id=((select received->>'id' from failing)::uuid)), 1, 'failed attempt increments retry metadata');

select throws_ok(
  $$update public.document_inbox_events set metadata='{}' where event_type='RECEIVED'$$,
  '55000', 'DOCUMENT_INBOX_EVENT_IMMUTABLE', 'audit events cannot be updated'
);
select throws_ok(
  $$delete from public.document_inbox_events where event_type='RECEIVED'$$,
  '55000', 'DOCUMENT_INBOX_EVENT_IMMUTABLE', 'audit events cannot be deleted'
);
select throws_ok(
  $$update public.document_inbox_items set lifecycle_status='PROCESSED',revision=revision+1 where id=((select received->>'id' from extracted)::uuid)$$,
  '23514', 'INVALID_DOCUMENT_INBOX_TRANSITION', 'invalid lifecycle transition is denied'
);

select public.receive_document_inbox_item_v1(repeat('1',64),'internal-separate.pdf','application/pdf',106,'MANUAL_UPLOAD',null,null,'internal_e2e');
select is(jsonb_array_length(public.get_document_inbox_v1(null,'production')->'items'), 4, 'production inbox read excludes internal E2E items');
select is(jsonb_array_length(public.get_document_inbox_v1(null,'internal_e2e')->'items'), 2, 'internal E2E inbox records remain separately readable');
select is(public.get_document_inbox_v1(null,'production')->>'scope', 'document_inbox', 'inbox read preserves its scope contract');
select ok(jsonb_typeof(public.get_document_inbox_v1(null,'production')->'items') = 'array', 'inbox read preserves its items array contract');

select * from finish();
rollback;