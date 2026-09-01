begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

create function pg_temp.sdf_v3_payload()
returns jsonb language sql immutable set search_path=pg_catalog as $$
  select '{
    "documentPurpose":{"categories":["invoice"]},
    "workflowCapabilities":["receive"],
    "businessRequirements":{"currentWorkflow":"Manual","desiredWorkflow":"Controlled","volumeBand":"10_to_49","frequency":"monthly","relevantDocumentTypes":["Invoice"],"rolesUsers":["Finance"]},
    "sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false},
    "commercialQualification":{"packageDirection":"start","customComplexity":"","documentVolumes":[{"documentType":"invoice","documentCount":100,"period":"monthly","averagePagesPerDocument":1}],"flowCount":1,"userCount":2}
  }'::jsonb
$$;

select has_function('lws_internal', 'evaluate_sdf_document_completeness_v1', array['uuid'], 'private dossier completeness evaluator exists');
select is((select provolatile::text from pg_proc where oid='lws_internal.evaluate_sdf_document_completeness_v1(uuid)'::regprocedure), 's', 'table-backed evaluator is stable');
select ok(not has_function_privilege('authenticated', 'lws_internal.evaluate_sdf_document_completeness_v1(uuid)', 'execute'), 'client cannot invoke private completeness authority');
select has_column('public', 'sdf_quotation_preparation_authorities', 'document_evidence_sha256', 'quotation authority has document evidence binding');

insert into auth.users(id,email) values('dc100000-0000-4000-8000-000000000001','dfq2b-owner@example.test');
insert into public.commercial_operators(operator_id,auth_user_id,display_name,role,status)
values('dc110000-0000-4000-8000-000000000001','dc100000-0000-4000-8000-000000000001','DFQ-2B Owner','owner','ACTIVE');

insert into public.quote_requests(
  id,application_reference,record_classification,request_kind,sdf_package,
  name,email,description,privacy_consent,status
) values
  ('dc200000-0000-4000-8000-000000000001','LWS-AAN-2099-9201','production','slimme_documentenflow','start','DFQ complete','complete@example.test','Synthetic complete fixture.',true,'approved'),
  ('dd200000-0000-4000-8000-000000000001','LWS-AAN-2099-9202','production','slimme_documentenflow','start','DFQ empty','empty@example.test','Synthetic zero-requirement fixture.',true,'approved'),
  ('de200000-0000-4000-8000-000000000001','LWS-AAN-2099-9203','production','slimme_documentenflow','start','DFQ legacy','legacy@example.test','Synthetic V2 fixture.',true,'approved'),
  ('df200000-0000-4000-8000-000000000001','LWS-AAN-2099-9204','production','slimme_documentenflow','start','DFQ other','other@example.test','Synthetic cross-dossier fixture.',true,'approved');

insert into public.sdf_projects(project_id,quote_request_id) values
  ('dc210000-0000-4000-8000-000000000001','dc200000-0000-4000-8000-000000000001'),
  ('df210000-0000-4000-8000-000000000001','df200000-0000-4000-8000-000000000001');

insert into public.sdf_qualification_intakes(
  intake_id,quote_request_id,status,taxonomy_version,customer_capability_digest,
  customer_capability_encrypted,customer_capability_expires_at,draft_answers,
  draft_revision,latest_submission_sequence
) values
  ('dc300000-0000-4000-8000-000000000001','dc200000-0000-4000-8000-000000000001','qualification_complete','sdf_qualification_intake/3.0.0',repeat('1',64),'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',clock_timestamp()+interval '1 day',pg_temp.sdf_v3_payload(),1,1),
  ('dd300000-0000-4000-8000-000000000001','dd200000-0000-4000-8000-000000000001','qualification_complete','sdf_qualification_intake/3.0.0',repeat('2',64),'v1.BBBBBBBBBBBBBBBB.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',clock_timestamp()+interval '1 day',pg_temp.sdf_v3_payload(),1,1),
  ('de300000-0000-4000-8000-000000000001','de200000-0000-4000-8000-000000000001','qualification_complete','sdf_qualification_intake/2.0.0',repeat('3',64),'v1.CCCCCCCCCCCCCCCC.CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',clock_timestamp()+interval '1 day',pg_temp.sdf_v3_payload()-'commercialQualification'||jsonb_build_object('commercialQualification',(pg_temp.sdf_v3_payload()->'commercialQualification')-'flowCount'-'userCount'),1,1);

insert into public.sdf_qualification_intake_submissions(
  submission_id,intake_id,submission_sequence,answers,taxonomy_version,
  payload_sha256,confirmation_version,confirmation_sha256
)
select gen_random_uuid(),intake_id,1,draft_answers,taxonomy_version,
  encode(extensions.digest(convert_to(draft_answers::text,'UTF8'),'sha256'),'hex'),
  'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1',repeat('4',64)
from public.sdf_qualification_intakes;

insert into public.sdf_qualification_intake_events(
  event_id,intake_id,event_kind,from_status,to_status,actor_class,submission_sequence
) select gen_random_uuid(),intake_id,'QUALIFICATION_COMPLETE','under_review','qualification_complete','system',1
from public.sdf_qualification_intakes;

insert into public.customer_requests(
  request_id,request_reference,quote_request_id,customer_id,project_id,source,
  request_type,title,description,status,priority,submitted_at,submitter_type
) values
  ('dc400000-0000-4000-8000-000000000001','LWS-VRZ-2099-9201','dc200000-0000-4000-8000-000000000001',null,null,'OPERATOR','FILE_DELIVERY','DFQ complete files','Synthetic complete files.','NEW','NORMAL',clock_timestamp(),'OPERATOR'),
  ('df400000-0000-4000-8000-000000000001','LWS-VRZ-2099-9204','df200000-0000-4000-8000-000000000001',null,null,'OPERATOR','FILE_DELIVERY','DFQ other files','Synthetic cross-dossier files.','NEW','NORMAL',clock_timestamp(),'OPERATOR');

insert into public.customer_request_upload_requests(
  upload_request_id,customer_request_id,token_digest,status,expires_at,created_at,
  created_by_operator_id,completed_at
) values
  ('dc500000-0000-4000-8000-000000000001','dc400000-0000-4000-8000-000000000001',repeat('5',64),'COMPLETED',clock_timestamp()+interval '1 day',clock_timestamp(),'dc110000-0000-4000-8000-000000000001',clock_timestamp()),
  ('df500000-0000-4000-8000-000000000001','df400000-0000-4000-8000-000000000001',repeat('6',64),'COMPLETED',clock_timestamp()+interval '1 day',clock_timestamp(),'dc110000-0000-4000-8000-000000000001',clock_timestamp());

insert into public.customer_request_uploaded_files(
  uploaded_file_id,upload_request_id,customer_request_id,status,storage_object_path,
  original_file_name,file_extension,declared_content_type,declared_byte_count,
  observed_content_type,observed_byte_count,sha256,accepted_at
) values
  ('dc600000-0000-4000-8000-000000000001','dc500000-0000-4000-8000-000000000001','dc400000-0000-4000-8000-000000000001','ACCEPTED','requests/dc400000-0000-4000-8000-000000000001/uploads/dc500000-0000-4000-8000-000000000001/files/dc600000-0000-4000-8000-000000000001.pdf','one.pdf','pdf','application/pdf',101,'application/pdf',101,repeat('7',64),clock_timestamp()),
  ('dc600000-0000-4000-8000-000000000002','dc500000-0000-4000-8000-000000000001','dc400000-0000-4000-8000-000000000001','ACCEPTED','requests/dc400000-0000-4000-8000-000000000001/uploads/dc500000-0000-4000-8000-000000000001/files/dc600000-0000-4000-8000-000000000002.pdf','two.pdf','pdf','application/pdf',102,'application/pdf',102,repeat('8',64),clock_timestamp()),
  ('dc600000-0000-4000-8000-000000000003','dc500000-0000-4000-8000-000000000001','dc400000-0000-4000-8000-000000000001','ACCEPTED','requests/dc400000-0000-4000-8000-000000000001/uploads/dc500000-0000-4000-8000-000000000001/files/dc600000-0000-4000-8000-000000000003.pdf','three.pdf','pdf','application/pdf',103,'application/pdf',103,repeat('9',64),clock_timestamp()),
  ('df600000-0000-4000-8000-000000000001','df500000-0000-4000-8000-000000000001','df400000-0000-4000-8000-000000000001','ACCEPTED','requests/df400000-0000-4000-8000-000000000001/uploads/df500000-0000-4000-8000-000000000001/files/df600000-0000-4000-8000-000000000001.pdf','other.pdf','pdf','application/pdf',104,'application/pdf',104,repeat('a',64),clock_timestamp());

insert into public.document_inbox_items(
  id,sha256,storage_object_path,original_file_name,mime_type,byte_count,
  source_type,source_instance,external_id,created_by_operator_id
) values
  ('dc700000-0000-4000-8000-000000000001',repeat('7',64),'documents/'||repeat('7',64)||'.pdf','one.pdf','application/pdf',101,'CUSTOMER_REQUEST_UPLOAD','dc400000-0000-4000-8000-000000000001','dc600000-0000-4000-8000-000000000001','dc110000-0000-4000-8000-000000000001'),
  ('dc700000-0000-4000-8000-000000000002',repeat('8',64),'documents/'||repeat('8',64)||'.pdf','two.pdf','application/pdf',102,'CUSTOMER_REQUEST_UPLOAD','dc400000-0000-4000-8000-000000000001','dc600000-0000-4000-8000-000000000002','dc110000-0000-4000-8000-000000000001'),
  ('dc700000-0000-4000-8000-000000000003',repeat('9',64),'documents/'||repeat('9',64)||'.pdf','three.pdf','application/pdf',103,'CUSTOMER_REQUEST_UPLOAD','dc400000-0000-4000-8000-000000000001','dc600000-0000-4000-8000-000000000003','dc110000-0000-4000-8000-000000000001'),
  ('df700000-0000-4000-8000-000000000001',repeat('a',64),'documents/'||repeat('a',64)||'.pdf','other.pdf','application/pdf',104,'CUSTOMER_REQUEST_UPLOAD','df400000-0000-4000-8000-000000000001','df600000-0000-4000-8000-000000000001','dc110000-0000-4000-8000-000000000001');

insert into public.document_inbox_customer_request_upload_sources(
  uploaded_file_id,customer_request_id,quote_request_id,document_inbox_item_id,promoted_by_operator_id
) values
  ('dc600000-0000-4000-8000-000000000001','dc400000-0000-4000-8000-000000000001','dc200000-0000-4000-8000-000000000001','dc700000-0000-4000-8000-000000000001','dc110000-0000-4000-8000-000000000001'),
  ('dc600000-0000-4000-8000-000000000002','dc400000-0000-4000-8000-000000000001','dc200000-0000-4000-8000-000000000001','dc700000-0000-4000-8000-000000000002','dc110000-0000-4000-8000-000000000001'),
  ('dc600000-0000-4000-8000-000000000003','dc400000-0000-4000-8000-000000000001','dc200000-0000-4000-8000-000000000001','dc700000-0000-4000-8000-000000000003','dc110000-0000-4000-8000-000000000001'),
  ('df600000-0000-4000-8000-000000000001','df400000-0000-4000-8000-000000000001','df200000-0000-4000-8000-000000000001','df700000-0000-4000-8000-000000000001','dc110000-0000-4000-8000-000000000001');

select set_config('request.jwt.claim.sub','dc100000-0000-4000-8000-000000000001',true);

create temporary table zero_state as
select lws_internal.evaluate_sdf_document_completeness_v1('dd200000-0000-4000-8000-000000000001') result;
select is((select result->>'required_count' from zero_state),'0','zero requirements reports zero required items');
select is((select result->>'is_complete' from zero_state),'false','zero requirements fails closed');
select is((select result->>'classification_reason' from zero_state),'NO_REQUIREMENTS','zero requirements has explicit classification');
select throws_ok(
  $$select public.authorize_sdf_quotation_preparation_v1('dd200000-0000-4000-8000-000000000001','dd800000-0000-4000-8000-000000000001')$$,
  '55000','SDF_DOCUMENT_COMPLETENESS_REQUIRED','V3 quotation rejects zero requirements'
);
select is((select count(*)::integer from public.sdf_quotations where quote_request_id='dd200000-0000-4000-8000-000000000001'),0,'incomplete gate creates no quotation identity');

create temporary table invoice_requirement as
select public.create_sdf_document_requirement_v1('dc200000-0000-4000-8000-000000000001','invoice',2) result;
create temporary table no_evidence_state as
select lws_internal.evaluate_sdf_document_completeness_v1('dc200000-0000-4000-8000-000000000001') result;
select is((select result->>'required_count' from no_evidence_state),'1','one requirement is counted once regardless of required_count');
select is((select result->>'satisfied_count' from no_evidence_state),'0','requirement without evidence is unsatisfied');
select is((select result->>'missing_count' from no_evidence_state),'1','one unsatisfied requirement is missing');
select throws_ok(
  $$select public.authorize_sdf_quotation_preparation_v1('dc200000-0000-4000-8000-000000000001','dc800000-0000-4000-8000-000000000001')$$,
  '55000','SDF_DOCUMENT_COMPLETENESS_REQUIRED','qualification and Budget Guard cannot bypass incomplete documents'
);

select public.bind_sdf_document_requirement_evidence_v1(
  (select (result->>'requirement_id')::uuid from invoice_requirement),
  'dc600000-0000-4000-8000-000000000001'
);
create temporary table one_file_state as
select lws_internal.evaluate_sdf_document_completeness_v1('dc200000-0000-4000-8000-000000000001') result;
select is((select result->>'satisfied_count' from one_file_state),'0','required_count two remains unsatisfied with one evidence');
select isnt((select result->>'evidence_sha256' from one_file_state),(select result->>'evidence_sha256' from no_evidence_state),'added relevant evidence changes hash');

create temporary table contract_requirement as
select public.create_sdf_document_requirement_v1('dc200000-0000-4000-8000-000000000001','contract',1) result;
select public.bind_sdf_document_requirement_evidence_v1(
  (select (result->>'requirement_id')::uuid from invoice_requirement),
  'dc600000-0000-4000-8000-000000000002'
);
create temporary table partial_state as
select lws_internal.evaluate_sdf_document_completeness_v1('dc200000-0000-4000-8000-000000000001') result;
select is((select result->>'required_count' from partial_state),'2','two requirement items aggregate dossier-wide');
select is((select result->>'satisfied_count' from partial_state),'1','two invoice files satisfy only the invoice requirement');
select is((select result->>'missing_count' from partial_state),'1','unsatisfied contract remains missing');
select is((select result->>'is_complete' from partial_state),'false','partial dossier remains incomplete');
select throws_ok(
  $$select public.authorize_sdf_quotation_preparation_v1('dc200000-0000-4000-8000-000000000001','dc800000-0000-4000-8000-000000000003')$$,
  '55000','SDF_DOCUMENT_COMPLETENESS_REQUIRED','two-required one-satisfied dossier is rejected'
);

create temporary table before_cross_state as
select lws_internal.evaluate_sdf_document_completeness_v1('dc200000-0000-4000-8000-000000000001') result;
select throws_ok(
  $$select public.bind_sdf_document_requirement_evidence_v1(
    (select (result->>'requirement_id')::uuid from contract_requirement),
    'df600000-0000-4000-8000-000000000001'
  )$$,
  '23514','SDF_DOCUMENT_EVIDENCE_DOSSIER_MISMATCH','cross-dossier evidence cannot satisfy requirement'
);
select is(
  lws_internal.evaluate_sdf_document_completeness_v1('dc200000-0000-4000-8000-000000000001')->>'evidence_sha256',
  (select result->>'evidence_sha256' from before_cross_state),
  'rejected cross-dossier evidence has no hash influence'
);

select public.bind_sdf_document_requirement_evidence_v1(
  (select (result->>'requirement_id')::uuid from contract_requirement),
  'dc600000-0000-4000-8000-000000000003'
);
create temporary table complete_state as
select lws_internal.evaluate_sdf_document_completeness_v1('dc200000-0000-4000-8000-000000000001') result;
select is((select result->>'required_count' from complete_state),'2','complete dossier retains two requirements');
select is((select result->>'satisfied_count' from complete_state),'2','all requirement items are satisfied');
select is((select result->>'missing_count' from complete_state),'0','complete dossier has no missing requirements');
select is((select result->>'is_complete' from complete_state),'true','all requirements make dossier complete');
select is(
  lws_internal.evaluate_sdf_document_completeness_v1('dc200000-0000-4000-8000-000000000001')->>'evidence_sha256',
  (select result->>'evidence_sha256' from complete_state),
  'unchanged authoritative state yields identical hash'
);

create temporary table authorization_result as
select public.authorize_sdf_quotation_preparation_v1(
  'dc200000-0000-4000-8000-000000000001','dc800000-0000-4000-8000-000000000002'
) result;
select is((select result->>'replayed' from authorization_result),'false','complete V3 dossier creates quotation authority');
select is((select result->>'sdf_package' from authorization_result),'start','complete V3 dossier retains server-derived Budget Guard package');
select is(
  (select rtrim(document_evidence_sha256) from public.sdf_quotation_preparation_authorities where quote_request_id='dc200000-0000-4000-8000-000000000001'),
  (select result->>'evidence_sha256' from complete_state),
  'quotation authority binds exact document evidence hash'
);
select is(
  public.authorize_sdf_quotation_preparation_v1('dc200000-0000-4000-8000-000000000001','dc800000-0000-4000-8000-000000000002')->>'replayed',
  'true',
  'unchanged V3 evidence replays idempotently'
);

select public.reject_document_inbox_item_v1('dc700000-0000-4000-8000-000000000003',1,'Synthetic stale-evidence transition');
create temporary table rejected_state as
select lws_internal.evaluate_sdf_document_completeness_v1('dc200000-0000-4000-8000-000000000001') result;
select is((select result->>'is_complete' from rejected_state),'false','rejected relevant Inbox evidence makes dossier incomplete');
select isnt((select result->>'evidence_sha256' from rejected_state),(select result->>'evidence_sha256' from complete_state),'rejected evidence changes canonical hash');
select throws_ok(
  $$select public.authorize_sdf_quotation_preparation_v1('dc200000-0000-4000-8000-000000000001','dc800000-0000-4000-8000-000000000002')$$,
  'P0001','IDEMPOTENCY_CONFLICT','changed evidence rejects stale V3 replay'
);

create temporary table legacy_result as
select public.authorize_sdf_quotation_preparation_v1(
  'de200000-0000-4000-8000-000000000001','de800000-0000-4000-8000-000000000001'
) result;
select is((select result->>'replayed' from legacy_result),'false','V2 quotation behavior remains unblocked by document requirements');
select is((select document_evidence_sha256 from public.sdf_quotation_preparation_authorities where quote_request_id='de200000-0000-4000-8000-000000000001'),null,'V2 authority keeps document evidence binding null');

select * from finish();
rollback;