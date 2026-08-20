begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, storage, extensions;

select plan(56);

select is((select count(*)::integer from storage.buckets where id='quotation-artifacts'),1,'private quotation artifact bucket exists');
select is((select public from storage.buckets where id='quotation-artifacts'),false,'quotation artifact bucket is private');
select is((select file_size_limit from storage.buckets where id='quotation-artifacts'),10485760::bigint,'bucket enforces the ten MiB limit');
select is((select allowed_mime_types from storage.buckets where id='quotation-artifacts'),array['application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/pdf']::text[],'bucket allows only DOCX and PDF');
select is((select count(*)::integer from pg_policies where schemaname='storage' and tablename='objects' and (coalesce(qual,'') like '%quotation-artifacts%' or coalesce(with_check,'') like '%quotation-artifacts%')),0,'bucket has no browser Storage policy');
select has_table('public','quote_request_quotation_artifacts','artifact metadata table exists');
select has_table('public','quote_request_quotation_artifact_events','artifact event table exists');
select ok((select relrowsecurity from pg_class where oid='public.quote_request_quotation_artifacts'::regclass),'artifact table has RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.quote_request_quotation_artifact_events'::regclass),'artifact event table has RLS enabled');
select has_function('public','register_quotation_artifact_v1',array['uuid','text','text','bigint','text','uuid','text'],'registration RPC exists');
select has_function('public','get_quotation_artifact_metadata_v1',array['uuid'],'metadata-only RPC exists');
select has_function('public','record_quotation_artifact_archive_failure_v1',array['uuid','text','text','uuid','text'],'failure evidence RPC exists');
select has_function('public','reconcile_quotation_artifact_v1',array['uuid','text','text','bigint','text','uuid','text'],'reconciliation RPC exists');
select ok(not has_function_privilege('anon','public.register_quotation_artifact_v1(uuid,text,text,bigint,text,uuid,text)','execute'),'anon cannot execute registration');
select ok(not has_function_privilege('authenticated','public.register_quotation_artifact_v1(uuid,text,text,bigint,text,uuid,text)','execute'),'authenticated cannot execute registration');
select ok(has_function_privilege('service_role','public.register_quotation_artifact_v1(uuid,text,text,bigint,text,uuid,text)','execute'),'service role can execute registration');
select ok(not has_table_privilege('anon','public.quote_request_quotation_artifacts','select'),'anon has no artifact table read grant');
select ok(not has_table_privilege('authenticated','public.quote_request_quotation_artifacts','insert'),'authenticated has no artifact table write grant');
select ok(not has_table_privilege('service_role','public.quote_request_quotation_artifacts','insert'),'service role cannot bypass the registration RPC with a direct table insert');
select ok(exists(select 1 from pg_indexes where schemaname='storage' and tablename='objects' and indexname='bucketid_objname' and indexdef like 'CREATE UNIQUE INDEX%'),'Storage enforces unique bucket and object paths');

create temporary table c1_authorities (
  scenario text primary key,
  quote_id uuid not null default gen_random_uuid(),
  intake_id uuid not null default gen_random_uuid(),
  pricing_id uuid not null default gen_random_uuid(),
  draft_id uuid not null default gen_random_uuid(),
  approval_id uuid not null default gen_random_uuid(),
  issuance_id uuid not null default gen_random_uuid()
);
insert into c1_authorities(scenario) values
  ('issued'),('prepared'),('void'),('successor'),('superseded'),('missing');

insert into public.quote_requests(id,name,email,website_type,budget,timing,description,privacy_consent,status)
select quote_id,'C1 '||scenario,scenario||'@example.test','business','EUR 3.200 t/m EUR 6.000','flexible','C1 archive fixture',true,'approved'
from c1_authorities;
insert into public.quote_request_intakes(
  id,quote_request_id,access_token_hash,access_token_expires_at,status,
  started_at,submitted_at,confirmation,admin_access_token_hash,admin_access_token_expires_at
)
select intake_id,quote_id,
  encode(extensions.digest(convert_to('c1-access-'||scenario,'UTF8'),'sha256'),'hex'),
  clock_timestamp()+interval '1 day','submitted',clock_timestamp(),clock_timestamp(),true,
  encode(extensions.digest(convert_to('c1-admin-'||scenario,'UTF8'),'sha256'),'hex'),
  clock_timestamp()+interval '1 day'
from c1_authorities;
insert into public.quote_request_pricing_snapshots(
  id,intake_id,snapshot_contract_version,config_version,config_hash,
  normalized_evidence,calculation,package_advice,budget_evaluation
)
select pricing_id,intake_id,2,'1.0.0',repeat('1',64),
  '{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}',
  '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":180000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000}]}',
  '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}',
  '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}'
from c1_authorities;
insert into public.quote_request_pricing_snapshot_integrity(snapshot_id,algorithm_version,key_id,mac)
select pricing_id,'hmac-sha256-v1','v1',repeat('a',64) from c1_authorities;

create temporary table c1_payloads as
select authority.*,
  jsonb_build_object(
    'contract_version',1,
    'source_quote_request_id',quote_id,
    'source_intake_id',intake_id,
    'pricing_snapshot',jsonb_build_object('snapshot_id',pricing_id,'snapshot_contract_version',2,'integrity_algorithm_version','hmac-sha256-v1','integrity_key_id','v1','integrity_mac',repeat('a',64)),
    'currency','EUR',
    'line_items',jsonb_build_array(jsonb_build_object('line_id','website','sequence',1,'product_or_service_code','WEBSITE','description','Websiteontwikkeling','quantity',1,'unit','project','unit_price_minor',100000,'discount_minor',0,'vat_treatment','STANDARD','vat_rate',21,'line_net_amount_minor',100000,'cost_type','ONE_TIME')),
    'totals',jsonb_build_object('one_time_subtotal_minor',100000,'recurring_subtotal_minor',0,'discount_total_minor',0,'vat_base_minor',100000,'vat_amount_minor',21000,'total_gross_minor',121000),
    'discount',jsonb_build_object('discount_type',null,'discount_value_minor',0,'discount_reason',null,'approved_by',null,'approved_at',null),
    'customer_identity',jsonb_build_object('source_quote_request_id',quote_id,'source_intake_id',intake_id,'customer_id',null,'legal_name','C1 Customer','contact_name',null,'email',scenario||'@example.test','address_line_1','Teststraat 1','address_line_2',null,'postal_code','9000','city','Gent','country_code','BE','enterprise_number',null,'vat_number',null,'source_fields',jsonb_build_object('legal_name','fixture'),'snapshot_sha256',repeat('b',64)),
    'project_scope',jsonb_build_object('project_id',null,'project_title','C1 website','project_type','website','scope_summary','Fictieve scope','requested_languages',jsonb_build_array('nl'),'included_page_count',5,'features',jsonb_build_array('contact_form'),'copywriting',null,'seo',null,'hosting',null,'maintenance',null,'exclusions','[]'::jsonb,'assumptions','[]'::jsonb,'indicative_timing',null,'source_intake_id',intake_id,'source_pricing_snapshot_id',pricing_id,'snapshot_sha256',repeat('c',64)),
    'vat_approval',jsonb_build_object('vat_treatment','STANDARD','vat_rate',21,'vat_decision_source','accountant','vat_approved_by','accountant:test','vat_approved_at','2026-08-20T12:00:00Z'),
    'payment_schedule',jsonb_build_object('schedule_id','schedule-1','milestones',jsonb_build_array(jsonb_build_object('sequence',1,'label','Volledige betaling','percentage',100,'amount_minor',null,'trigger','invoice','due_terms_days',30,'recurring_cycle',null)),'approved_by','commercial:test','approved_at','2026-08-20T12:00:00Z'),
    'validity',jsonb_build_object('valid_from','2026-08-20','valid_until','2026-09-19','validity_days',30,'approved_by','commercial:test','approved_at','2026-08-20T12:00:00Z'),
    'legal_references',jsonb_build_object('terms_reference','terms-v1','terms_version','1.0.0','terms_sha256',repeat('d',64),'terms_status','APPROVED','agreement_template_reference',null,'agreement_template_version',null,'agreement_template_sha256',null)
  ) as payload
from c1_authorities as authority;

insert into public.quote_request_quotation_approval_drafts(
  id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,
  approval_payload,payload_fingerprint,idempotency_key,created_by
)
select draft_id,quote_id,intake_id,pricing_id,1,payload,public.quotation_approval_payload_sha256_v1(payload),gen_random_uuid(),'admin:c1'
from c1_payloads;
insert into public.quote_request_quotation_approvals(
  id,draft_id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,
  approval_version,approved_payload,payload_sha256,approved_by,approved_at
)
select approval_id,draft_id,quote_id,intake_id,pricing_id,1,1,payload,public.quotation_approval_payload_sha256_v1(payload),'admin:c1',clock_timestamp()
from c1_payloads;
insert into public.quote_request_quotation_approval_integrity(approval_id,algorithm_version,key_id,mac)
select approval_id,'hmac-sha256-v1','v1',repeat('e',64) from c1_payloads;

insert into public.quote_request_quotation_issuances(
  id,quotation_number,quotation_version,status,approval_id,issued_at,issued_by,
  template_id,template_version,template_sha256,generation_contract_version,
  generation_payload_sha256,docx_sha256,docx_bytes,pdf_sha256,pdf_bytes,
  prepare_idempotency_key,prepare_fingerprint,commit_idempotency_key,
  commit_fingerprint,issuance_input_sha256
)
select issuance_id,'LWS-OFF-2098-0001',1,'ISSUED',approval_id,clock_timestamp(),'admin:c1',
  'LWS_QUOTATION_NL_BE','1.0.0-technical',repeat('3',64),1,repeat('4',64),
  repeat('5',64),120,repeat('6',64),80,gen_random_uuid(),repeat('7',64),gen_random_uuid(),repeat('8',64),repeat('9',64)
from c1_authorities where scenario='issued';
insert into public.quote_request_quotation_issuances(
  id,quotation_number,quotation_version,status,approval_id,generation_contract_version,
  prepare_idempotency_key,prepare_fingerprint,issuance_input_sha256
)
select issuance_id,'LWS-OFF-2098-0002',1,'PREPARED',approval_id,1,gen_random_uuid(),repeat('1',64),repeat('2',64)
from c1_authorities where scenario='prepared';
insert into public.quote_request_quotation_issuances(
  id,quotation_number,quotation_version,status,approval_id,generation_contract_version,
  prepare_idempotency_key,prepare_fingerprint,void_idempotency_key,void_fingerprint,
  voided_at,voided_by,void_reason,issuance_input_sha256
)
select issuance_id,'LWS-OFF-2098-0003',1,'VOID',approval_id,1,gen_random_uuid(),repeat('1',64),gen_random_uuid(),repeat('2',64),clock_timestamp(),'admin:c1','fixture void',repeat('3',64)
from c1_authorities where scenario='void';
insert into public.quote_request_quotation_issuances(
  id,quotation_number,quotation_version,status,approval_id,issued_at,issued_by,
  template_id,template_version,template_sha256,generation_contract_version,
  generation_payload_sha256,docx_sha256,docx_bytes,prepare_idempotency_key,
  prepare_fingerprint,commit_idempotency_key,commit_fingerprint,issuance_input_sha256
)
select issuance_id,'LWS-OFF-2098-0005',2,'ISSUED',approval_id,clock_timestamp(),'admin:c1',
  'LWS_QUOTATION_NL_BE','1.0.0-technical',repeat('3',64),1,repeat('4',64),repeat('a',64),140,
  gen_random_uuid(),repeat('5',64),gen_random_uuid(),repeat('6',64),repeat('7',64)
from c1_authorities where scenario='successor';
insert into public.quote_request_quotation_issuances(
  id,quotation_number,quotation_version,status,approval_id,issued_at,issued_by,
  template_id,template_version,template_sha256,generation_contract_version,
  generation_payload_sha256,docx_sha256,docx_bytes,prepare_idempotency_key,
  prepare_fingerprint,commit_idempotency_key,commit_fingerprint,
  superseded_by_issuance_id,revision_reason,issuance_input_sha256
)
select old.issuance_id,'LWS-OFF-2098-0004',1,'SUPERSEDED',old.approval_id,clock_timestamp(),'admin:c1',
  'LWS_QUOTATION_NL_BE','1.0.0-technical',repeat('3',64),1,repeat('4',64),repeat('b',64),130,
  gen_random_uuid(),repeat('5',64),gen_random_uuid(),repeat('6',64),new.issuance_id,'corrected scope',repeat('7',64)
from c1_authorities old cross join c1_authorities new
where old.scenario='superseded' and new.scenario='successor';

insert into public.quote_request_quotation_issuances(
  id,quotation_number,quotation_version,status,approval_id,issued_at,issued_by,
  template_id,template_version,template_sha256,generation_contract_version,
  generation_payload_sha256,docx_sha256,docx_bytes,prepare_idempotency_key,
  prepare_fingerprint,commit_idempotency_key,commit_fingerprint,issuance_input_sha256
)
select issuance_id,'LWS-OFF-2098-0006',1,'ISSUED',approval_id,clock_timestamp(),'admin:c1',
  'LWS_QUOTATION_NL_BE','1.0.0-technical',repeat('3',64),1,repeat('4',64),repeat('c',64),150,
  gen_random_uuid(),repeat('5',64),gen_random_uuid(),repeat('6',64),repeat('7',64)
from c1_authorities where scenario='missing';

insert into storage.objects(bucket_id,name,metadata)
select 'quotation-artifacts','issuances/'||issuance_id||'/docx/'||repeat('5',64)||'.docx',jsonb_build_object('size',120,'mimetype','application/vnd.openxmlformats-officedocument.wordprocessingml.document')
from c1_authorities where scenario='issued';
insert into storage.objects(bucket_id,name,metadata)
select 'quotation-artifacts','issuances/'||issuance_id||'/pdf/'||repeat('6',64)||'.pdf',jsonb_build_object('size',80,'mimetype','application/pdf')
from c1_authorities where scenario='issued';
insert into storage.objects(bucket_id,name,metadata)
select 'quotation-artifacts','issuances/'||issuance_id||'/docx/'||repeat('a',64)||'.docx',jsonb_build_object('size',141,'mimetype','application/vnd.openxmlformats-officedocument.wordprocessingml.document')
from c1_authorities where scenario='successor';
insert into storage.objects(bucket_id,name,metadata)
select 'quotation-artifacts','issuances/'||issuance_id||'/docx/'||repeat('b',64)||'.docx',jsonb_build_object('size',130,'mimetype','application/vnd.openxmlformats-officedocument.wordprocessingml.document')
from c1_authorities where scenario='superseded';

select throws_ok($$select * from public.register_quotation_artifact_v1('00000000-0000-4000-8000-000000000099','DOCX',repeat('5',64),120,'application/vnd.openxmlformats-officedocument.wordprocessingml.document',gen_random_uuid(),'operator:c1')$$,'P0001','ISSUANCE_NOT_FOUND','unknown issuance is rejected');
select throws_ok(format('select * from public.register_quotation_artifact_v1(%L,%L,%L,120,%L,gen_random_uuid(),%L)',(select issuance_id from c1_authorities where scenario='prepared'),'DOCX',repeat('5',64),'application/vnd.openxmlformats-officedocument.wordprocessingml.document','operator:c1'),'P0001','ARTIFACT_ARCHIVE_NOT_AVAILABLE','PREPARED issuance is rejected');
select throws_ok(format('select * from public.register_quotation_artifact_v1(%L,%L,%L,120,%L,gen_random_uuid(),%L)',(select issuance_id from c1_authorities where scenario='void'),'DOCX',repeat('5',64),'application/vnd.openxmlformats-officedocument.wordprocessingml.document','operator:c1'),'P0001','ARTIFACT_ARCHIVE_NOT_AVAILABLE','VOID issuance is rejected');
select throws_ok(format('select * from public.register_quotation_artifact_v1(%L,%L,%L,120,%L,gen_random_uuid(),%L)',(select issuance_id from c1_authorities where scenario='issued'),'ZIP',repeat('5',64),'application/zip','operator:c1'),'22023','ARTIFACT_TYPE_INVALID','unknown artifact type is rejected');
select throws_ok(format('select * from public.register_quotation_artifact_v1(%L,%L,%L,120,%L,gen_random_uuid(),%L)',(select issuance_id from c1_authorities where scenario='issued'),'DOCX',repeat('f',64),'application/vnd.openxmlformats-officedocument.wordprocessingml.document','operator:c1'),'P0001','ARTIFACT_HASH_MISMATCH','issuance hash mismatch is rejected');
select throws_ok(format('select * from public.register_quotation_artifact_v1(%L,%L,%L,121,%L,gen_random_uuid(),%L)',(select issuance_id from c1_authorities where scenario='issued'),'DOCX',repeat('5',64),'application/vnd.openxmlformats-officedocument.wordprocessingml.document','operator:c1'),'P0001','ARTIFACT_BYTE_COUNT_MISMATCH','issuance byte mismatch is rejected');
select throws_ok(format('select * from public.register_quotation_artifact_v1(%L,%L,%L,120,%L,gen_random_uuid(),%L)',(select issuance_id from c1_authorities where scenario='issued'),'DOCX',repeat('5',64),'application/pdf','operator:c1'),'P0001','ARTIFACT_CONTENT_TYPE_MISMATCH','MIME mismatch is rejected');
select throws_ok(format('select * from public.register_quotation_artifact_v1(%L,%L,%L,140,%L,gen_random_uuid(),%L)',(select issuance_id from c1_authorities where scenario='successor'),'DOCX',repeat('a',64),'application/vnd.openxmlformats-officedocument.wordprocessingml.document','operator:c1'),'P0001','ARTIFACT_OBJECT_METADATA_MISMATCH','Storage metadata mismatch is rejected');
select throws_ok(format('select * from public.register_quotation_artifact_v1(%L,%L,%L,150,%L,gen_random_uuid(),%L)',(select issuance_id from c1_authorities where scenario='missing'),'DOCX',repeat('c',64),'application/vnd.openxmlformats-officedocument.wordprocessingml.document','operator:c1'),'P0001','ARTIFACT_OBJECT_NOT_FOUND','missing expected Storage object is rejected');

create temporary table c1_docx as
select * from public.register_quotation_artifact_v1(
  (select issuance_id from c1_authorities where scenario='issued'),'DOCX',repeat('5',64),120,
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'c1000000-0000-4000-8000-000000000001','operator:c1'
);
select is((select was_created from c1_docx),true,'valid ISSUED DOCX registration succeeds');
select is((select storage_object_path from c1_docx),'issuances/'||(select issuance_id from c1_authorities where scenario='issued')||'/docx/'||repeat('5',64)||'.docx','DOCX path is deterministic');
select is((select was_created from public.register_quotation_artifact_v1((select issuance_id from c1_authorities where scenario='issued'),'DOCX',repeat('5',64),120,'application/vnd.openxmlformats-officedocument.wordprocessingml.document','c1000000-0000-4000-8000-000000000001','operator:c1')),false,'exact registration retry returns canonical metadata');
select is((select artifact_id from public.register_quotation_artifact_v1((select issuance_id from c1_authorities where scenario='issued'),'DOCX',repeat('5',64),120,'application/vnd.openxmlformats-officedocument.wordprocessingml.document','c1000000-0000-4000-8000-000000000002','operator:c1')),(select artifact_id from c1_docx),'same issuance type and hash under a new key returns canonical artifact');
select throws_ok(format('select * from public.register_quotation_artifact_v1(%L,%L,%L,120,%L,%L,%L)',(select issuance_id from c1_authorities where scenario='issued'),'DOCX',repeat('f',64),'application/vnd.openxmlformats-officedocument.wordprocessingml.document','c1000000-0000-4000-8000-000000000001','operator:c1'),'P0001','IDEMPOTENCY_CONFLICT','same key with a different fingerprint is rejected');
select throws_ok(format('select * from public.register_quotation_artifact_v1(%L,%L,%L,120,%L,%L,%L)',(select issuance_id from c1_authorities where scenario='issued'),'DOCX',repeat('f',64),'application/vnd.openxmlformats-officedocument.wordprocessingml.document','c1000000-0000-4000-8000-000000000003','operator:c1'),'P0001','ARTIFACT_CONFLICT','same issuance and type with a different hash is rejected as artifact conflict');

create temporary table c1_pdf as
select * from public.register_quotation_artifact_v1(
  (select issuance_id from c1_authorities where scenario='issued'),'PDF',repeat('6',64),80,
  'application/pdf','c1000000-0000-4000-8000-000000000004','operator:c1'
);
select is((select was_created from c1_pdf),true,'valid optional PDF registration succeeds');
select is((select storage_object_path from c1_pdf),'issuances/'||(select issuance_id from c1_authorities where scenario='issued')||'/pdf/'||repeat('6',64)||'.pdf','PDF path is deterministic');
select is((select count(*)::integer from public.get_quotation_artifact_metadata_v1((select issuance_id from c1_authorities where scenario='issued'))),2,'metadata RPC returns both artifacts without binary content');
select is((select count(*)::integer from public.quote_request_quotation_artifact_events where event_type='ARTIFACT_ARCHIVED'),2,'registration atomically creates archive events');
select throws_ok($$update public.quote_request_quotation_artifacts set created_by='changed'$$,'55000','QUOTATION_ARTIFACT_HISTORY_IMMUTABLE','artifact metadata update is blocked');
select throws_ok($$delete from public.quote_request_quotation_artifacts$$,'55000','QUOTATION_ARTIFACT_HISTORY_IMMUTABLE','artifact metadata delete is blocked');
select throws_ok($$update public.quote_request_quotation_artifact_events set actor='changed'$$,'55000','QUOTATION_ARTIFACT_HISTORY_IMMUTABLE','artifact event update is blocked');
select throws_ok($$delete from public.quote_request_quotation_artifact_events$$,'55000','QUOTATION_ARTIFACT_HISTORY_IMMUTABLE','artifact event delete is blocked');

select is((select was_created from public.record_quotation_artifact_archive_failure_v1((select issuance_id from c1_authorities where scenario='issued'),'DOCX','UPLOAD_FAILED','c1000000-0000-4000-8000-000000000005','operator:c1')),true,'failure evidence is appended');
select is((select was_created from public.record_quotation_artifact_archive_failure_v1((select issuance_id from c1_authorities where scenario='issued'),'DOCX','UPLOAD_FAILED','c1000000-0000-4000-8000-000000000005','operator:c1')),false,'failure evidence retry is idempotent');
select throws_ok(format('select * from public.record_quotation_artifact_archive_failure_v1(%L,%L,%L,%L,%L)',(select issuance_id from c1_authorities where scenario='issued'),'DOCX','HASH_MISMATCH','c1000000-0000-4000-8000-000000000005','operator:c1'),'P0001','IDEMPOTENCY_CONFLICT','failure operation key cannot be reused for different evidence');
select throws_ok(format('insert into public.quote_request_quotation_artifact_events(issuance_id,artifact_type,event_type,operation_id,actor,evidence) values(%L,%L,%L,gen_random_uuid(),%L,%L::jsonb)',(select issuance_id from c1_authorities where scenario='issued'),'DOCX','ARTIFACT_ARCHIVE_FAILED','operator:c1','{"failure_code":"UPLOAD_FAILED","outcome":"FAILED","token":"secret"}'),'23514',null,'sensitive event evidence is rejected');

select is((select outcome from public.reconcile_quotation_artifact_v1((select issuance_id from c1_authorities where scenario='issued'),'DOCX',repeat('5',64),120,'application/vnd.openxmlformats-officedocument.wordprocessingml.document','c1000000-0000-4000-8000-000000000006','operator:c1')),'CONSISTENT','reconciliation confirms coherent object and immutable metadata');
select throws_ok(format('select * from public.reconcile_quotation_artifact_v1(%L,%L,%L,121,%L,%L,%L)',(select issuance_id from c1_authorities where scenario='issued'),'DOCX',repeat('5',64),'application/vnd.openxmlformats-officedocument.wordprocessingml.document','c1000000-0000-4000-8000-000000000006','operator:c1'),'P0001','IDEMPOTENCY_CONFLICT','reconciliation key cannot be reused with different observations');
insert into public.quote_request_quotation_artifacts(
  issuance_id,artifact_type,storage_bucket_id,storage_object_path,content_type,
  sha256,byte_count,registration_idempotency_key,registration_fingerprint,created_by
)
select issuance_id,'DOCX','quotation-artifacts',
  'issuances/'||issuance_id||'/docx/'||repeat('c',64)||'.docx',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  repeat('c',64),150,gen_random_uuid(),repeat('d',64),'service:c1-fixture'
from c1_authorities where scenario='missing';
select is((select outcome from public.reconcile_quotation_artifact_v1((select issuance_id from c1_authorities where scenario='missing'),'DOCX',null,null,null,'c1000000-0000-4000-8000-000000000007','operator:c1')),'MISSING_OBJECT','reconciliation records missing object without mutating artifact');
select is((select count(*)::integer from public.quote_request_quotation_artifacts where issuance_id=(select issuance_id from c1_authorities where scenario='missing')),1,'missing object reconciliation preserves immutable artifact metadata');
select is((select outcome from public.reconcile_quotation_artifact_v1((select issuance_id from c1_authorities where scenario='successor'),'DOCX',repeat('a',64),140,'application/vnd.openxmlformats-officedocument.wordprocessingml.document','c1000000-0000-4000-8000-000000000008','operator:c1')),'ORPHAN_OBJECT','reconciliation identifies an object without artifact metadata');
select is((select was_created from public.reconcile_quotation_artifact_v1((select issuance_id from c1_authorities where scenario='successor'),'DOCX',repeat('a',64),140,'application/vnd.openxmlformats-officedocument.wordprocessingml.document','c1000000-0000-4000-8000-000000000008','operator:c1')),false,'reconciliation retry is idempotent');

select is((select was_created from public.register_quotation_artifact_v1((select issuance_id from c1_authorities where scenario='superseded'),'DOCX',repeat('b',64),130,'application/vnd.openxmlformats-officedocument.wordprocessingml.document','c1000000-0000-4000-8000-000000000009','operator:c1')),true,'historical SUPERSEDED artifact can be archived');
select is((select count(*)::integer from public.quote_request_quotation_artifacts artifact join public.quote_request_quotation_issuances issuance on issuance.id=artifact.issuance_id where issuance.status='SUPERSEDED'),1,'SUPERSEDED issuance and artifact history remain preserved');
select throws_ok(format('insert into storage.objects(bucket_id,name,metadata) values(%L,%L,%L::jsonb)','quotation-artifacts',(select storage_object_path from c1_docx),'{"size":120,"mimetype":"application/vnd.openxmlformats-officedocument.wordprocessingml.document"}'),'23505',null,'duplicate Storage path cannot overwrite the archived object');

select * from finish();
rollback;
