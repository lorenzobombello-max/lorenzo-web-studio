begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(29);

select has_function(
  'public','build_sdf_quotation_issue_payload_v1',
  array['uuid','uuid','integer','text','uuid'],
  'QF-4B SDF generation payload bridge exists'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.build_sdf_quotation_issue_payload_v1(uuid,uuid,integer,text,uuid)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.build_sdf_quotation_issue_payload_v1(uuid,uuid,integer,text,uuid)',
    'execute'
  ) and not has_function_privilege(
    'service_role',
    'public.build_sdf_quotation_issue_payload_v1(uuid,uuid,integer,text,uuid)',
    'execute'
  ),
  'only authenticated owner boundary can execute QF-4B'
);
select is(
  pg_get_function_arguments(
    'public.build_sdf_quotation_issue_payload_v1(uuid,uuid,integer,text,uuid)'::regprocedure
  ),
  'p_business_draft_id uuid, p_approval_id uuid, p_expected_approval_version integer, p_expected_approval_sha256 text, p_issuance_id uuid',
  'QF-4B has no admin token parameter'
);
select ok(
  pg_get_functiondef(
    'public.build_sdf_quotation_issue_payload_v1(uuid,uuid,integer,text,uuid)'::regprocedure
  ) like '%assert_sdf_approval_issuance_authority_v1%'
  and pg_get_functiondef(
    'public.build_sdf_quotation_issue_payload_v1(uuid,uuid,integer,text,uuid)'::regprocedure
  ) like '%project_quotation_generation_payload_v1%'
  and pg_get_functiondef(
    'public.build_sdf_quotation_issue_payload_v1(uuid,uuid,integer,text,uuid)'::regprocedure
  ) like '%quotation_generation_payload_sha256_v1%',
  'QF-4B reuses QF-3B authority plus existing projector and hash contract'
);

create function pg_temp.qf4b_uuid(p_value text)
returns uuid language sql immutable set search_path=pg_catalog as $$
  select (substr(md5(p_value),1,8)||'-'||substr(md5(p_value),9,4)||'-4'||
    substr(md5(p_value),14,3)||'-8'||substr(md5(p_value),18,3)||'-'||
    substr(md5(p_value),21,12))::uuid
$$;

create function pg_temp.qf4b_payload(p_package text)
returns jsonb language sql immutable set search_path=pg_catalog as $$
  select jsonb_build_object(
    'documentPurpose',jsonb_build_object('categories',jsonb_build_array('quotation','invoice')),
    'workflowCapabilities',jsonb_build_array('receive'),
    'businessRequirements',jsonb_build_object(
      'currentWorkflow','Synthetic current workflow',
      'desiredWorkflow','Synthetic controlled workflow',
      'volumeBand','50_to_249','frequency','monthly',
      'relevantDocumentTypes',jsonb_build_array('Synthetic documents'),
      'rolesUsers',jsonb_build_array('Synthetic users')
    ),
    'sampleDocumentMetadata',jsonb_build_object(
      'available',false,'requestedByLws',false,'uploadRequiredLater',false
    ),
    'commercialQualification',jsonb_build_object(
      'packageDirection','start','customComplexity','',
      'documentVolumes',jsonb_build_array(
        jsonb_build_object(
          'documentType','quotation',
          'documentCount',case p_package when 'start' then 499 else 2499 end,
          'period','monthly','averagePagesPerDocument',1
        ),
        jsonb_build_object(
          'documentType','invoice','documentCount',1,'period','monthly',
          'averagePagesPerDocument',1
        )
      ),
      'flowCount',case p_package when 'start' then 1 else 3 end,
      'userCount',case p_package when 'start' then 3 else 10 end
    )
  )
$$;

create function pg_temp.qf4b_schedule()
returns jsonb language sql immutable set search_path=pg_catalog as $$
  select jsonb_build_object('milestones',jsonb_build_array(jsonb_build_object(
    'sequence',1,'label','Synthetic implementation payment','percentage',100,
    'amount_minor',null,'trigger','invoice','due_terms_days',30,'recurring_cycle',null
  )))
$$;

create temporary table qf4b_fixtures(
  label text primary key,
  package text not null,
  quote_request_id uuid not null,
  intake_id uuid not null,
  uploaded_file_id uuid not null,
  preparation_authority_id uuid,
  decision_id uuid,
  business_draft_id uuid,
  generic_intake_id uuid,
  approval_id uuid,
  approval_sha256 text,
  issuance_id uuid
);
insert into qf4b_fixtures(label,package,quote_request_id,intake_id,uploaded_file_id)
select label,package,
  pg_temp.qf4b_uuid('qf4b-'||label||'-request'),
  pg_temp.qf4b_uuid('qf4b-'||label||'-intake'),
  pg_temp.qf4b_uuid('qf4b-'||label||'-file')
from (values ('start','start'),('cross','groei')) fixture(label,package);

insert into auth.users(id,email) values
  (pg_temp.qf4b_uuid('qf4b-owner-auth'),'qf4b-owner@example.test'),
  (pg_temp.qf4b_uuid('qf4b-operator-auth'),'qf4b-operator@example.test');
insert into public.commercial_operators(
  operator_id,auth_user_id,display_name,role,status
) values
(
  pg_temp.qf4b_uuid('qf4b-owner-operator'),pg_temp.qf4b_uuid('qf4b-owner-auth'),
  'QF-4B Synthetic Owner','owner','ACTIVE'
),(
  pg_temp.qf4b_uuid('qf4b-operator'),pg_temp.qf4b_uuid('qf4b-operator-auth'),
  'QF-4B Synthetic Operator','operator','ACTIVE'
);
insert into public.quote_requests(
  id,application_reference,record_classification,request_kind,sdf_package,
  name,company,email,description,privacy_consent,status,
  billing_address,billing_postal_code,billing_city,billing_country
)
select quote_request_id,
  'LWS-AAN-2099-'||(9950+row_number() over(order by label))::text,
  'production','slimme_documentenflow','start','QF-4B '||label,
  'Synthetic QF-4B BV','qf4b-'||label||'@example.test',
  'Synthetic QF-4B fixture.',true,'approved',
  'Teststraat 1','9000','Gent','BE'
from qf4b_fixtures;
insert into public.sdf_projects(project_id,quote_request_id)
select pg_temp.qf4b_uuid('qf4b-'||label||'-project'),quote_request_id
from qf4b_fixtures;
insert into public.sdf_qualification_intakes(
  intake_id,quote_request_id,status,taxonomy_version,customer_capability_digest,
  customer_capability_encrypted,customer_capability_expires_at,draft_answers,
  draft_revision,latest_submission_sequence
)
select intake_id,quote_request_id,'qualification_complete',
  'sdf_qualification_intake/3.0.0',
  encode(extensions.digest(convert_to('qf4b-'||label,'UTF8'),'sha256'),'hex'),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  clock_timestamp()+interval '1 day',pg_temp.qf4b_payload(package),1,1
from qf4b_fixtures;
insert into public.sdf_qualification_intake_submissions(
  submission_id,intake_id,submission_sequence,answers,taxonomy_version,
  payload_sha256,confirmation_version,confirmation_sha256
)
select pg_temp.qf4b_uuid('qf4b-'||fixture.label||'-submission'),
  intake.intake_id,1,intake.draft_answers,intake.taxonomy_version,
  encode(extensions.digest(convert_to(intake.draft_answers::text,'UTF8'),'sha256'),'hex'),
  'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1',repeat('a',64)
from qf4b_fixtures fixture
join public.sdf_qualification_intakes intake on intake.intake_id=fixture.intake_id;
insert into public.sdf_qualification_intake_events(
  event_id,intake_id,event_kind,from_status,to_status,actor_class,submission_sequence
)
select pg_temp.qf4b_uuid('qf4b-'||label||'-completion'),intake_id,
  'QUALIFICATION_COMPLETE','under_review','qualification_complete','system',1
from qf4b_fixtures;

insert into public.customer_requests(
  request_id,request_reference,quote_request_id,source,request_type,title,
  description,status,priority,submitted_at,submitter_type
)
select pg_temp.qf4b_uuid('qf4b-'||label||'-customer-request'),
  'LWS-VRZ-2099-'||(9950+row_number() over(order by label))::text,
  quote_request_id,'OPERATOR','FILE_DELIVERY','QF-4B synthetic evidence',
  'Synthetic evidence.','NEW','NORMAL',clock_timestamp(),'OPERATOR'
from qf4b_fixtures;
insert into public.customer_request_upload_requests(
  upload_request_id,customer_request_id,token_digest,status,expires_at,created_at,
  created_by_operator_id,completed_at
)
select pg_temp.qf4b_uuid('qf4b-'||label||'-upload'),
  pg_temp.qf4b_uuid('qf4b-'||label||'-customer-request'),
  encode(extensions.digest(convert_to('qf4b-token-'||label,'UTF8'),'sha256'),'hex'),
  'COMPLETED',clock_timestamp()+interval '1 day',clock_timestamp(),
  pg_temp.qf4b_uuid('qf4b-owner-operator'),clock_timestamp()
from qf4b_fixtures;
insert into public.customer_request_uploaded_files(
  uploaded_file_id,upload_request_id,customer_request_id,status,storage_object_path,
  original_file_name,file_extension,declared_content_type,declared_byte_count,
  observed_content_type,observed_byte_count,sha256,accepted_at
)
select uploaded_file_id,pg_temp.qf4b_uuid('qf4b-'||label||'-upload'),
  pg_temp.qf4b_uuid('qf4b-'||label||'-customer-request'),'ACCEPTED',
  'requests/'||pg_temp.qf4b_uuid('qf4b-'||label||'-customer-request')::text||
    '/uploads/'||pg_temp.qf4b_uuid('qf4b-'||label||'-upload')::text||
    '/files/'||uploaded_file_id::text||'.pdf',
  'qf4b-'||label||'.pdf','pdf','application/pdf',100,
  'application/pdf',100,
  encode(extensions.digest(convert_to('qf4b-file-'||label,'UTF8'),'sha256'),'hex'),
  clock_timestamp()
from qf4b_fixtures;
insert into public.document_inbox_items(
  id,sha256,storage_object_path,original_file_name,mime_type,byte_count,
  source_type,source_instance,external_id,created_by_operator_id
)
select pg_temp.qf4b_uuid('qf4b-'||label||'-inbox'),
  encode(extensions.digest(convert_to('qf4b-file-'||label,'UTF8'),'sha256'),'hex'),
  'documents/'||encode(extensions.digest(
    convert_to('qf4b-file-'||label,'UTF8'),'sha256'
  ),'hex')||'.pdf',
  'qf4b-'||label||'.pdf','application/pdf',100,'CUSTOMER_REQUEST_UPLOAD',
  pg_temp.qf4b_uuid('qf4b-'||label||'-customer-request')::text,
  uploaded_file_id::text,pg_temp.qf4b_uuid('qf4b-owner-operator')
from qf4b_fixtures;
insert into public.document_inbox_customer_request_upload_sources(
  uploaded_file_id,customer_request_id,quote_request_id,document_inbox_item_id,
  promoted_by_operator_id
)
select uploaded_file_id,pg_temp.qf4b_uuid('qf4b-'||label||'-customer-request'),
  quote_request_id,pg_temp.qf4b_uuid('qf4b-'||label||'-inbox'),
  pg_temp.qf4b_uuid('qf4b-owner-operator')
from qf4b_fixtures;

select set_config(
  'request.jwt.claim.sub',pg_temp.qf4b_uuid('qf4b-owner-auth')::text,true
);
create temporary table qf4b_requirements as
select label,uploaded_file_id,
  (public.create_sdf_document_requirement_v1(
    quote_request_id,'invoice',1
  )->>'requirement_id')::uuid requirement_id
from qf4b_fixtures;
select public.bind_sdf_document_requirement_evidence_v1(
  requirement_id,uploaded_file_id
) from qf4b_requirements;
update qf4b_fixtures fixture set preparation_authority_id=(
  public.authorize_sdf_quotation_preparation_v1(
    fixture.quote_request_id,
    pg_temp.qf4b_uuid('qf4b-'||fixture.label||'-preparation-key')
  )->>'authority_id'
)::uuid;

create temporary table qf4b_vat as
select vat_decision_authority_id approved_id
from public.quotation_vat_decision_authorities
where authority_family='LWS_OUTGOING_VAT' and status='APPROVED';
insert into public.quotation_vat_transaction_classifications(
  classification_id,quote_request_id,context_sha256,classification_code,
  source_reference,source_sha256,classified_by,classified_at
)
select pg_temp.qf4b_uuid('qf4b-'||label||'-vat-classification'),quote_request_id,
  public.quotation_vat_context_sha256_v1(quote_request_id),
  'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION','TEST_ONLY:QF4B',
  repeat('b',64),'QF4B_TEST',clock_timestamp()
from qf4b_fixtures;
insert into public.quotation_vat_turnover_snapshots(
  turnover_snapshot_id,vat_decision_authority_id,threshold_year,
  measurement_watermark,governed_turnover_minor,currency,state,
  source_reference,source_sha256,predecessor_snapshot_id,recorded_by,recorded_at
) values (
  pg_temp.qf4b_uuid('qf4b-vat-turnover'),(select approved_id from qf4b_vat),
  2026,current_date,0,'EUR','BELOW_OR_AT_THRESHOLD','TEST_ONLY:QF4B',
  repeat('c',64),null,'QF4B_TEST',clock_timestamp()
);
insert into public.quotation_vat_turnover_snapshots(
  turnover_snapshot_id,vat_decision_authority_id,threshold_year,
  measurement_watermark,governed_turnover_minor,currency,state,
  source_reference,source_sha256,predecessor_snapshot_id,recorded_by,recorded_at
) values (
  pg_temp.qf4b_uuid('qf4b-vat-turnover-d-plus-1'),
  (select approved_id from qf4b_vat),2026,current_date+1,0,'EUR',
  'BELOW_OR_AT_THRESHOLD','TEST_ONLY:QF4B:D_PLUS_1',repeat('e',64),
  pg_temp.qf4b_uuid('qf4b-vat-turnover'),'QF4B_TEST',clock_timestamp()
);
insert into public.quotation_terms_authorities(
  terms_authority_id,terms_id,terms_version,terms_sha256,source_path,status,
  effective_from,approved_by,approved_at
) values (
  pg_temp.qf4b_uuid('qf4b-terms'),'QF4B_TERMS','1.0.0',repeat('d',64),
  'synthetic/qf4b-terms','APPROVED',current_date,'QF4B_TEST',clock_timestamp()
);
update qf4b_fixtures fixture set decision_id=(
  public.authorize_sdf_quotation_commercial_decision_v1(
    fixture.quote_request_id,fixture.preparation_authority_id,
    (select approved_id from qf4b_vat),pg_temp.qf4b_uuid('qf4b-terms'),
    pg_temp.qf4b_schedule(),
    pg_temp.qf4b_uuid('qf4b-'||fixture.label||'-decision-key')
  )->>'decision_id'
)::uuid;

create temporary table qf4b_business_results(label text primary key,value jsonb);
insert into qf4b_business_results
select label,public.create_sdf_quotation_business_draft_v1(
  preparation_authority_id,decision_id,
  pg_temp.qf4b_uuid('qf4b-'||label||'-business-key')
) from qf4b_fixtures;
update qf4b_fixtures fixture set
  business_draft_id=(result.value->>'business_draft_id')::uuid,
  generic_intake_id=(result.value->>'generic_intake_id')::uuid
from qf4b_business_results result
where result.label=fixture.label;

create function pg_temp.qf4b_proof(p_label text)
returns jsonb language sql stable set search_path=public,extensions,pg_catalog as $$
  select jsonb_build_object(
    'algorithmVersion','hmac-sha256-v1','keyId','v1',
    'mac',encode(extensions.digest(convert_to(
      'qf4b-approval-proof:'||p_label,'UTF8'
    ),'sha256'),'hex'),
    'root',public.quotation_approval_integrity_root_v1(
      pg_temp.qf4b_uuid('qf4b-'||p_label||'-approval'),
      rtrim(business.canonical_payload_sha256),1::smallint,
      business.quote_request_id,business.intake_id,business.pricing_snapshot_id
    )
  )
  from public.quote_request_quotation_business_drafts business
  join qf4b_fixtures fixture on fixture.business_draft_id=business.business_draft_id
  where fixture.label=p_label
$$;

create temporary table qf4b_approval_results(label text primary key,result jsonb);
insert into qf4b_approval_results
select label,public.promote_sdf_quotation_business_draft_to_approval_v1(
  business_draft_id,1,
  pg_temp.qf4b_uuid('qf4b-'||label||'-approval-key'),
  pg_temp.qf4b_uuid('qf4b-'||label||'-approval'),
  pg_temp.qf4b_proof(label)
) from qf4b_fixtures;
update qf4b_fixtures fixture set
  approval_id=(result.result->>'approval_id')::uuid,
  approval_sha256=approval.payload_sha256
from qf4b_approval_results result
join public.quote_request_quotation_approvals approval
  on approval.id=(result.result->>'approval_id')::uuid
where result.label=fixture.label;

create temporary table qf4b_prepare_results as
select fixture.label,result.*
from qf4b_fixtures fixture
cross join lateral public.prepare_sdf_quotation_issuance_v1(
  fixture.business_draft_id,fixture.approval_id,1,fixture.approval_sha256,
  1::smallint,pg_temp.qf4b_uuid('qf4b-'||fixture.label||'-prepare-key')
) result;
update qf4b_fixtures fixture set issuance_id=result.issuance_id
from qf4b_prepare_results result where result.label=fixture.label;

create temporary table qf4b_baseline as
select
  (select count(*) from public.quotation_vat_decision_authorities) vat_authority_count,
  (select count(*) from public.quotation_vat_turnover_snapshots) vat_turnover_count,
  (select count(*) from public.quote_request_pricing_snapshots) pricing_snapshot_count,
  (select count(*) from public.quotation_number_counters) counter_count,
  (select sum(next_sequence) from public.quotation_number_counters) counter_sum,
  (select count(*) from public.quote_request_quotation_issuances) issuance_count,
  (select coalesce(jsonb_agg(to_jsonb(operation) order by operation.idempotency_key),'[]'::jsonb)
   from public.quote_request_quotation_issuance_operations operation
   where operation.issuance_id=(
     select issuance_id from qf4b_fixtures where label='start'
   )) issuance_operations,
  (select coalesce(jsonb_agg(to_jsonb(artifact) order by artifact.artifact_id),'[]'::jsonb)
   from public.quote_request_quotation_artifacts artifact
   where artifact.issuance_id=(
     select issuance_id from qf4b_fixtures where label='start'
   )) quotation_artifacts,
  (select coalesce(jsonb_agg(to_jsonb(event) order by event.event_id),'[]'::jsonb)
   from public.quote_request_quotation_artifact_events event
   where event.issuance_id=(
     select issuance_id from qf4b_fixtures where label='start'
   )) quotation_artifact_events,
  (select count(*) from public.quote_request_quotation_email_orchestrations) orchestration_count,
  (select count(*) from public.quote_request_quotation_acceptance_capabilities) capability_count,
  (select count(*) from public.quote_request_email_jobs) mail_count;

select ok(not exists(
  select 1 from qf4b_fixtures fixture
  join public.quote_request_intakes intake on intake.id=fixture.generic_intake_id
  where intake.admin_access_token_hash is not null
),'authenticated owner generation needs no fabricated admin capability');

grant select on qf4b_fixtures to authenticated;
select set_config(
  'request.jwt.claim.sub',pg_temp.qf4b_uuid('qf4b-operator-auth')::text,true
);
set local role authenticated;
select throws_ok(format(
  $sql$select * from public.build_sdf_quotation_issue_payload_v1(%L,%L,1,%L,%L)$sql$,
  (select business_draft_id from qf4b_fixtures where label='start'),
  (select approval_id from qf4b_fixtures where label='start'),
  (select approval_sha256 from qf4b_fixtures where label='start'),
  (select issuance_id from qf4b_fixtures where label='start')
),'42501','OWNER_REQUIRED','authenticated active non-owner fails at owner authority');
reset role;
select set_config(
  'request.jwt.claim.sub',pg_temp.qf4b_uuid('qf4b-owner-auth')::text,true
);

create temporary table qf4b_result as
select * from public.build_sdf_quotation_issue_payload_v1(
  (select business_draft_id from qf4b_fixtures where label='start'),
  (select approval_id from qf4b_fixtures where label='start'),1,
  (select approval_sha256 from qf4b_fixtures where label='start'),
  (select issuance_id from qf4b_fixtures where label='start')
);
select ok(public.is_valid_quotation_generation_payload_v1(payload),
  'QF-4B produces a valid existing generation payload') from qf4b_result;
select is((select payload->>'mode' from qf4b_result),'ISSUE','payload mode is ISSUE');
select is((select payload->>'contract_version' from qf4b_result),'1',
  'generation contract remains version 1');
select is((select payload#>>'{quotation,issuance_id}' from qf4b_result),
  (select issuance_id::text from qf4b_fixtures where label='start'),
  'payload binds the prepared issuance identity');
select ok((select payload_sha256 ~ '^[0-9a-f]{64}$' from qf4b_result),
  'payload SHA-256 has the existing canonical shape');
select is((select payload_sha256 from qf4b_result),
  (select public.quotation_generation_payload_sha256_v1(payload) from qf4b_result),
  'payload SHA-256 is calculated by the existing hash contract');
select is((select payload#>>'{template,authority_status}' from qf4b_result),'APPROVED',
  'payload uses the frozen approved template authority');
select is((select payload#>>'{seller,legal_name}' from qf4b_result),
  (select seller.seller_identity->>'legal_name'
   from qf4b_fixtures fixture
   join public.quote_request_quotation_business_drafts business
     on business.business_draft_id=fixture.business_draft_id
   join public.quotation_seller_authorities seller
     on seller.seller_authority_id=business.seller_authority_id
   where fixture.label='start'),
  'payload uses the frozen seller authority');

create temporary table qf4b_d_plus_1_vat_context as
select public.resolve_quotation_vat_authority_v1(
  (select quote_request_id from qf4b_fixtures where label='start'),
  current_date+1
) value;
select isnt(
  (select value->>'turnover_snapshot_id' from qf4b_d_plus_1_vat_context),
  (select binding.turnover_snapshot_id::text
   from qf4b_fixtures fixture
   join public.quotation_business_draft_vat_bindings binding
     on binding.business_draft_id=fixture.business_draft_id
   where fixture.label='start'),
  'D+1 current VAT context differs from the frozen issuance VAT context'
);

create temporary table qf4b_replay as
select * from public.build_sdf_quotation_issue_payload_v1(
  (select business_draft_id from qf4b_fixtures where label='start'),
  (select approval_id from qf4b_fixtures where label='start'),1,
  (select approval_sha256 from qf4b_fixtures where label='start'),
  (select issuance_id from qf4b_fixtures where label='start')
);
select is((select payload from qf4b_replay),(select payload from qf4b_result),
  'exact replay returns the same canonical payload');
select is((select payload_sha256 from qf4b_replay),(select payload_sha256 from qf4b_result),
  'exact replay returns the same payload hash');

select throws_ok(format(
  $sql$select * from public.build_sdf_quotation_issue_payload_v1(%L,%L,1,%L,%L)$sql$,
  pg_temp.qf4b_uuid('qf4b-missing-business'),
  (select approval_id from qf4b_fixtures where label='start'),
  (select approval_sha256 from qf4b_fixtures where label='start'),
  (select issuance_id from qf4b_fixtures where label='start')
),'P0001','SDF_BUSINESS_DRAFT_NOT_FOUND','wrong business draft fails closed');
select throws_ok(format(
  $sql$select * from public.build_sdf_quotation_issue_payload_v1(%L,%L,1,%L,%L)$sql$,
  (select business_draft_id from qf4b_fixtures where label='start'),
  (select approval_id from qf4b_fixtures where label='start'),
  (select approval_sha256 from qf4b_fixtures where label='start'),
  (select issuance_id from qf4b_fixtures where label='cross')
),'42501','SDF_GENERATION_CROSS_DOSSIER','cross-dossier issuance fails closed');
select throws_ok(format(
  $sql$select * from public.build_sdf_quotation_issue_payload_v1(%L,%L,2,%L,%L)$sql$,
  (select business_draft_id from qf4b_fixtures where label='start'),
  (select approval_id from qf4b_fixtures where label='start'),
  (select approval_sha256 from qf4b_fixtures where label='start'),
  (select issuance_id from qf4b_fixtures where label='start')
),'P0001','SDF_APPROVAL_STALE','stale approval version fails closed');
select throws_ok(format(
  $sql$select * from public.build_sdf_quotation_issue_payload_v1(%L,%L,1,%L,%L)$sql$,
  (select business_draft_id from qf4b_fixtures where label='start'),
  (select approval_id from qf4b_fixtures where label='start'),repeat('9',64),
  (select issuance_id from qf4b_fixtures where label='start')
),'P0001','SDF_APPROVAL_STALE','stale approval hash fails closed');
select throws_ok(format(
  $sql$select * from public.build_sdf_quotation_issue_payload_v1(%L,%L,1,%L,%L)$sql$,
  (select business_draft_id from qf4b_fixtures where label='start'),
  (select approval_id from qf4b_fixtures where label='start'),
  (select approval_sha256 from qf4b_fixtures where label='start'),
  pg_temp.qf4b_uuid('qf4b-missing-issuance')
),'P0001','ISSUANCE_NOT_FOUND','wrong issuance fails closed');

alter table public.quotation_template_authorities disable trigger user;
update public.quotation_template_authorities set
  status='RETIRED',retired_at=clock_timestamp(),retired_by='QF4B_TEST',
  retirement_reason='Synthetic stale authority proof'
where id=(
  select business.template_authority_id
  from qf4b_fixtures fixture
  join public.quote_request_quotation_business_drafts business
    on business.business_draft_id=fixture.business_draft_id
  where fixture.label='start'
);
select throws_ok(format(
  $sql$select * from public.build_sdf_quotation_issue_payload_v1(%L,%L,1,%L,%L)$sql$,
  (select business_draft_id from qf4b_fixtures where label='start'),
  (select approval_id from qf4b_fixtures where label='start'),
  (select approval_sha256 from qf4b_fixtures where label='start'),
  (select issuance_id from qf4b_fixtures where label='start')
),'P0001','QUOTATION_TEMPLATE_NOT_APPROVED','stale template authority fails closed');
alter table public.quotation_template_authorities enable trigger user;

select ok(
  (select count(*) from public.quotation_vat_decision_authorities)=
    (select vat_authority_count from qf4b_baseline)
  and (select count(*) from public.quotation_vat_turnover_snapshots)=
    (select vat_turnover_count from qf4b_baseline)
  and (select count(*) from public.quote_request_pricing_snapshots)=
    (select pricing_snapshot_count from qf4b_baseline)
  and (select count(*) from public.quotation_number_counters)=
    (select counter_count from qf4b_baseline)
  and (select sum(next_sequence) from public.quotation_number_counters)=
    (select counter_sum from qf4b_baseline)
  and (select count(*) from public.quote_request_quotation_issuances)=
    (select issuance_count from qf4b_baseline),
  'generation creates no VAT authority, turnover, pricing, number, or issuance state'
);
select is(
  (select coalesce(jsonb_agg(to_jsonb(operation) order by operation.idempotency_key),'[]'::jsonb)
   from public.quote_request_quotation_issuance_operations operation
   where operation.issuance_id=(
     select issuance_id from qf4b_fixtures where label='start'
   )),
  (select issuance_operations from qf4b_baseline),
  'generation leaves the fixture issuance operation ledger unchanged'
);
select ok(
  (select coalesce(jsonb_agg(to_jsonb(artifact) order by artifact.artifact_id),'[]'::jsonb)
   from public.quote_request_quotation_artifacts artifact
   where artifact.issuance_id=(
     select issuance_id from qf4b_fixtures where label='start'
   ))=(select quotation_artifacts from qf4b_baseline)
  and
  (select coalesce(jsonb_agg(to_jsonb(event) order by event.event_id),'[]'::jsonb)
   from public.quote_request_quotation_artifact_events event
   where event.issuance_id=(
     select issuance_id from qf4b_fixtures where label='start'
   ))=(select quotation_artifact_events from qf4b_baseline),
  'generation leaves fixture artifact rows and archive events unchanged'
);
select is((select count(*) from public.quote_request_quotation_email_orchestrations),
  (select orchestration_count from qf4b_baseline),'generation creates no delivery record');
select is((select count(*) from public.quote_request_quotation_acceptance_capabilities),
  (select capability_count from qf4b_baseline),'generation creates no acceptance capability');
select is((select count(*) from public.quote_request_email_jobs),
  (select mail_count from qf4b_baseline),'generation creates no mail job');

select * from finish();
rollback;