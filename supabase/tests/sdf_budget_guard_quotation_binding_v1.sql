begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(20);

create function pg_temp.sdf_v3_payload(p_direction text,p_flows integer,p_document_types integer,p_pages_per_month integer,p_users integer)
returns jsonb language sql immutable set search_path=pg_catalog as $$
  with document_types(value,position) as (
    select * from unnest(array['quotation','invoice','order_confirmation','work_order','delivery_note','contract','customer_document','supplier_document','internal_administrative_document','multiple_document_types']) with ordinality limit p_document_types
  )
  select jsonb_build_object(
    'documentPurpose',jsonb_build_object('categories',(select jsonb_agg(value order by position) from document_types)),
    'workflowCapabilities',jsonb_build_array('receive'),
    'businessRequirements',jsonb_build_object('currentWorkflow','A','desiredWorkflow','B','volumeBand','50_to_249','frequency','monthly','relevantDocumentTypes',jsonb_build_array('Documenten'),'rolesUsers',jsonb_build_array('Gebruikers')),
    'sampleDocumentMetadata',jsonb_build_object('available',false,'requestedByLws',false,'uploadRequiredLater',false),
    'commercialQualification',jsonb_build_object(
      'packageDirection',p_direction,
      'customComplexity',case when p_direction='maatwerk' then 'Complex' else '' end,
      'documentVolumes',(select jsonb_agg(jsonb_build_object('documentType',value,'documentCount',case when position=1 then p_pages_per_month-p_document_types+1 else 1 end,'period','monthly','averagePagesPerDocument',1) order by position) from document_types),
      'flowCount',p_flows,
      'userCount',p_users
    )
  )
$$;

select has_function('lws_internal','get_sdf_budget_guard_pricing_authority_v2',array['text'],'BG-3 pricing authority exists');
select has_function('lws_internal','get_sdf_budget_guard_quotation_binding_v1',array['jsonb'],'BG-3 qualification binding exists');
select is((select provolatile::text from pg_proc where oid='lws_internal.get_sdf_budget_guard_quotation_binding_v1(jsonb)'::regprocedure),'i','qualification binding is immutable');
select ok(not has_function_privilege('anon','lws_internal.get_sdf_budget_guard_quotation_binding_v1(jsonb)','execute') and not has_function_privilege('authenticated','lws_internal.get_sdf_budget_guard_quotation_binding_v1(jsonb)','execute') and not has_function_privilege('service_role','lws_internal.get_sdf_budget_guard_quotation_binding_v1(jsonb)','execute'),'qualification binding is private');

select is(lws_internal.get_sdf_budget_guard_quotation_binding_v1(pg_temp.sdf_v3_payload('pro',1,2,500,3))#>>'{package}','start','client PRO direction cannot override START capacities');
select is(lws_internal.get_sdf_budget_guard_quotation_binding_v1(pg_temp.sdf_v3_payload('start',3,5,2500,10))#>>'{package}','groei','GROEI exact capacities select GROEI');
select is(lws_internal.get_sdf_budget_guard_quotation_binding_v1(pg_temp.sdf_v3_payload('start',6,10,7500,25))#>>'{package}','pro','client START direction cannot override PRO capacities');
select is(lws_internal.get_sdf_budget_guard_quotation_binding_v1(pg_temp.sdf_v3_payload('pro',7,10,7500,25))#>>'{package}','maatwerk','above-PRO capacities select MAATWERK');
select is(lws_internal.get_sdf_budget_guard_quotation_binding_v1(pg_temp.sdf_v3_payload('pro',1,2,500,3))#>'{pricing,implementation}','{"price_mode":"fixed","amount_minor":285000}'::jsonb,'START pricing is fixed 2850');
select is(lws_internal.get_sdf_budget_guard_quotation_binding_v1(pg_temp.sdf_v3_payload('start',3,5,2500,10))#>'{pricing,recurring}','{"price_mode":"fixed","amount_minor":29900,"billing_period":"month","commercial_package_price":true,"active_recurring_obligation":false}'::jsonb,'GROEI pricing is fixed 299 monthly');
select is(jsonb_build_array(lws_internal.get_sdf_budget_guard_quotation_binding_v1(pg_temp.sdf_v3_payload('start',6,10,7500,25))#>>'{pricing,implementation,amount_minor}',lws_internal.get_sdf_budget_guard_quotation_binding_v1(pg_temp.sdf_v3_payload('start',6,10,7500,25))#>>'{pricing,recurring,amount_minor}'),'["750000","44900"]'::jsonb,'PRO pricing is fixed 7500 and 449');
select is(lws_internal.get_sdf_budget_guard_quotation_binding_v1(pg_temp.sdf_v3_payload('pro',7,10,7500,25))#>'{pricing,implementation}','{"price_mode":"manual","amount_minor":null}'::jsonb,'MAATWERK has manual pricing and no fixed PRO amount');
select isnt(lws_internal.sdf_payload_valid_v3(jsonb_set(pg_temp.sdf_v3_payload('start',1,2,500,3),'{commercialQualification,priceMinor}','1'),true),true,'client price manipulation remains rejected');
select throws_ok($$select lws_internal.get_sdf_budget_guard_quotation_binding_v1(pg_temp.sdf_v3_payload('start',1,2,500,3) #- '{commercialQualification,flowCount}')$$,'22023','INVALID_SDF_BUDGET_GUARD_CAPACITY_INPUT','missing capacity fails closed without package fallback');
select is(lws_internal.get_sdf_budget_guard_quotation_binding_v1(pg_temp.sdf_v3_payload('start',6,10,7500,25)),lws_internal.get_sdf_budget_guard_quotation_binding_v1(pg_temp.sdf_v3_payload('start',6,10,7500,25)),'same canonical qualification yields deterministic package and pricing');

insert into auth.users(id,email) values('bf100000-0000-4000-8000-000000000001','bg3-owner@example.test');
insert into public.commercial_operators(auth_user_id,display_name,role,status) values('bf100000-0000-4000-8000-000000000001','BG-3 Owner','owner','ACTIVE');
insert into public.quote_requests(id,request_kind,sdf_package,created_at,name,email,description,privacy_consent,status,record_classification,approval_token_hash,approval_token_expires_at)
values('bf200000-0000-4000-8000-000000000001','slimme_documentenflow','start',clock_timestamp(),'BG-3 Klant','bg3@example.test','BG-3 fixture',true,'pending','production',repeat('7',64),clock_timestamp()+interval '1 day');
insert into public.sdf_qualification_intakes(intake_id,quote_request_id,status,taxonomy_version,customer_capability_digest,customer_capability_encrypted,customer_capability_expires_at,draft_answers,draft_revision,latest_submission_sequence)
values('bf300000-0000-4000-8000-000000000001','bf200000-0000-4000-8000-000000000001','qualification_complete','sdf_qualification_intake/3.0.0',repeat('6',64),'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',clock_timestamp()+interval '1 day',pg_temp.sdf_v3_payload('start',6,10,7500,25),1,1);
insert into public.sdf_qualification_intake_submissions(submission_id,intake_id,submission_sequence,answers,taxonomy_version,payload_sha256,confirmation_version,confirmation_sha256)
select 'bf400000-0000-4000-8000-000000000001','bf300000-0000-4000-8000-000000000001',1,draft_answers,'sdf_qualification_intake/3.0.0',encode(extensions.digest(convert_to(draft_answers::text,'UTF8'),'sha256'),'hex'),'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1',repeat('5',64) from public.sdf_qualification_intakes where intake_id='bf300000-0000-4000-8000-000000000001';
insert into public.sdf_qualification_intake_events(event_id,intake_id,event_kind,from_status,to_status,actor_class,submission_sequence)
values('bf500000-0000-4000-8000-000000000001','bf300000-0000-4000-8000-000000000001','QUALIFICATION_COMPLETE','under_review','qualification_complete','system',1);
select set_config('request.jwt.claim.sub','bf100000-0000-4000-8000-000000000001',true);

insert into public.sdf_projects(project_id,quote_request_id)
values('bfe00000-0000-4000-8000-000000000001','bf200000-0000-4000-8000-000000000001');
insert into public.customer_requests(
  request_id,request_reference,quote_request_id,source,request_type,title,
  description,status,priority,submitted_at,submitter_type
) values (
  'bfa00000-0000-4000-8000-000000000001','LWS-VRZ-2099-9801',
  'bf200000-0000-4000-8000-000000000001','OPERATOR','FILE_DELIVERY',
  'BG-3 synthetic evidence','Synthetic invoice evidence.','NEW','NORMAL',
  clock_timestamp(),'OPERATOR'
);
insert into public.customer_request_upload_requests(
  upload_request_id,customer_request_id,token_digest,status,expires_at,created_at,
  created_by_operator_id,completed_at
)
select 'bfb00000-0000-4000-8000-000000000001','bfa00000-0000-4000-8000-000000000001',
  repeat('a',64),'COMPLETED',clock_timestamp()+interval '1 day',clock_timestamp(),
  operator_id,clock_timestamp()
from public.commercial_operators where auth_user_id='bf100000-0000-4000-8000-000000000001';
insert into public.customer_request_uploaded_files(
  uploaded_file_id,upload_request_id,customer_request_id,status,storage_object_path,
  original_file_name,file_extension,declared_content_type,declared_byte_count,
  observed_content_type,observed_byte_count,sha256,accepted_at
) values (
  'bfc00000-0000-4000-8000-000000000001','bfb00000-0000-4000-8000-000000000001',
  'bfa00000-0000-4000-8000-000000000001','ACCEPTED',
  'requests/bfa00000-0000-4000-8000-000000000001/uploads/bfb00000-0000-4000-8000-000000000001/files/bfc00000-0000-4000-8000-000000000001.pdf',
  'bg3-invoice.pdf','pdf','application/pdf',100,'application/pdf',100,repeat('b',64),clock_timestamp()
);
insert into public.document_inbox_items(
  id,sha256,storage_object_path,original_file_name,mime_type,byte_count,
  source_type,source_instance,external_id,created_by_operator_id
)
select 'bfd00000-0000-4000-8000-000000000001',repeat('b',64),
  'documents/'||repeat('b',64)||'.pdf','bg3-invoice.pdf','application/pdf',100,
  'CUSTOMER_REQUEST_UPLOAD','bfa00000-0000-4000-8000-000000000001',
  'bfc00000-0000-4000-8000-000000000001',operator_id
from public.commercial_operators where auth_user_id='bf100000-0000-4000-8000-000000000001';
insert into public.document_inbox_customer_request_upload_sources(
  uploaded_file_id,customer_request_id,quote_request_id,document_inbox_item_id,
  promoted_by_operator_id
)
select 'bfc00000-0000-4000-8000-000000000001','bfa00000-0000-4000-8000-000000000001',
  'bf200000-0000-4000-8000-000000000001','bfd00000-0000-4000-8000-000000000001',operator_id
from public.commercial_operators where auth_user_id='bf100000-0000-4000-8000-000000000001';
create temporary table bg3_requirement as
select (public.create_sdf_document_requirement_v1(
  'bf200000-0000-4000-8000-000000000001','invoice',1
)->>'requirement_id')::uuid requirement_id;
select public.bind_sdf_document_requirement_evidence_v1(
  (select requirement_id from bg3_requirement),'bfc00000-0000-4000-8000-000000000001'
);
select public.confirm_sdf_scope_classification_v1(
  'bf200000-0000-4000-8000-000000000001',
  'bf400000-0000-4000-8000-000000000001',
  'standard',false,'pro','bf700000-0000-4000-8000-000000000001'
);

select is(public.authorize_sdf_quotation_preparation_v1('bf200000-0000-4000-8000-000000000001','bf600000-0000-4000-8000-000000000001')->>'sdf_package','pro','quotation preparation returns evaluator package, not request package');
select is((select sdf_package from public.sdf_quotation_preparation_authorities where quote_request_id='bf200000-0000-4000-8000-000000000001'),'pro','quotation authority persists evaluator package');
select is((select pricing_authority_version from public.sdf_quotation_preparation_authorities where quote_request_id='bf200000-0000-4000-8000-000000000001'),2,'V3 quotation authority binds pricing version 2');
select is((select rtrim(pricing_authority_sha256) from public.sdf_quotation_preparation_authorities where quote_request_id='bf200000-0000-4000-8000-000000000001'),encode(extensions.digest(convert_to(lws_internal.get_sdf_budget_guard_pricing_authority_v2('pro')::text,'UTF8'),'sha256'),'hex'),'quotation authority binds exact server pricing hash');
select ok((select submission_sha256=(select payload_sha256 from public.sdf_qualification_intake_submissions where intake_id=qualification_intake_id and submission_sequence=sdf_quotation_preparation_authorities.submission_sequence) from public.sdf_quotation_preparation_authorities where quote_request_id='bf200000-0000-4000-8000-000000000001'),'quotation authority binds the immutable qualification hash');

select * from finish();
rollback;