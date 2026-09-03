begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, storage, extensions;
select plan(41);

do $$
declare v_template_id uuid;
begin
  perform public.retire_quotation_template_v1(
    (select id from public.quotation_template_authorities
     where request_kind = 'slimme_documentenflow' and status = 'APPROVED'),
    'TEST_ONLY','Synthetic bridge fixture','SDF_BRIDGE_OFFICIAL_TEMPLATE_RETIRE'
  );
  v_template_id := public.register_quotation_template_candidate_for_product_v1(
    'slimme_documentenflow','SYNTHETIC_SDF_QUOTATION','test-v1','QUOTATION',
    'nl-BE','EUR',repeat('A',64),'synthetic/sdf-quotation.docx',1::smallint,
    'synthetic-sdf-renderer-v1',1::smallint,1::smallint,
    'TEST_ONLY','SDF_BRIDGE_TEMPLATE_REGISTER',null
  );
  perform public.approve_quotation_template_v1(
    v_template_id,'TEST_ONLY','SDF_BRIDGE_TEMPLATE_APPROVE'
  );
end;
$$;

select has_function(
  'public', 'prepare_sdf_issued_quotation_delivery_v1',
  array['uuid','uuid','integer','text','uuid','uuid','text','bigint','text','text',
    'timestamp with time zone'],
  'QF-5B owner-authorized SDF delivery preparation bridge exists'
);
select is(
  pg_get_function_arguments(
    'public.prepare_sdf_issued_quotation_delivery_v1(uuid,uuid,integer,text,uuid,uuid,text,bigint,text,text,timestamp with time zone)'::regprocedure
  ),
  'p_business_draft_id uuid, p_approval_id uuid, p_expected_approval_version integer, p_expected_approval_sha256 text, p_issuance_id uuid, p_artifact_id uuid, p_expected_artifact_sha256 text, p_expected_artifact_bytes bigint, p_token_digest text, p_encrypted_token text, p_requested_expires_at timestamp with time zone',
  'bridge signature has frozen authority and artifact inputs without admin token'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.prepare_sdf_issued_quotation_delivery_v1(uuid,uuid,integer,text,uuid,uuid,text,bigint,text,text,timestamp with time zone)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.prepare_sdf_issued_quotation_delivery_v1(uuid,uuid,integer,text,uuid,uuid,text,bigint,text,text,timestamp with time zone)',
    'execute'
  ),
  'authenticated is the only browser role allowed to invoke the bridge'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.prepare_sdf_issued_quotation_delivery_v1(uuid,uuid,integer,text,uuid,uuid,text,bigint,text,text,timestamp with time zone)',
    'execute'
  ),
  'service role cannot bypass the owner boundary'
);
select ok(
  pg_get_functiondef(
    'public.prepare_sdf_issued_quotation_delivery_v1(uuid,uuid,integer,text,uuid,uuid,text,bigint,text,text,timestamp with time zone)'::regprocedure
  ) like '%assert_sdf_approval_issuance_authority_v1%'
  and pg_get_functiondef(
    'public.prepare_sdf_issued_quotation_delivery_v1(uuid,uuid,integer,text,uuid,uuid,text,bigint,text,text,timestamp with time zone)'::regprocedure
  ) not like '%admin_access_token%'
  and pg_get_functiondef(
    'public.prepare_sdf_issued_quotation_delivery_v1(uuid,uuid,integer,text,uuid,uuid,text,bigint,text,text,timestamp with time zone)'::regprocedure
  ) not like '%claim_quote_request_email_job%'
  and pg_get_functiondef(
    'public.prepare_sdf_issued_quotation_delivery_v1(uuid,uuid,integer,text,uuid,uuid,text,bigint,text,text,timestamp with time zone)'::regprocedure
  ) not like '%http%'
  and pg_get_functiondef(
    'public.prepare_sdf_issued_quotation_delivery_v1(uuid,uuid,integer,text,uuid,uuid,text,bigint,text,text,timestamp with time zone)'::regprocedure
  ) not like '%execute %',
  'bridge reuses SDF authority and contains no admin token, transport, claim, or dynamic SQL'
);

create function pg_temp.qf5b_uuid(p_value text)
returns uuid language sql immutable set search_path=pg_catalog as $$
  select (substr(md5(p_value),1,8)||'-'||substr(md5(p_value),9,4)||'-4'||
    substr(md5(p_value),14,3)||'-8'||substr(md5(p_value),18,3)||'-'||
    substr(md5(p_value),21,12))::uuid
$$;

create function pg_temp.qf5b_payload()
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
        jsonb_build_object('documentType','quotation','documentCount',499,
          'period','monthly','averagePagesPerDocument',1),
        jsonb_build_object('documentType','invoice','documentCount',1,
          'period','monthly','averagePagesPerDocument',1)
      ),
      'flowCount',1,'userCount',3
    )
  )
$$;

create function pg_temp.qf5b_schedule()
returns jsonb language sql immutable set search_path=pg_catalog as $$
  select jsonb_build_object('milestones',jsonb_build_array(jsonb_build_object(
    'sequence',1,'label','Synthetic implementation payment','percentage',100,
    'amount_minor',null,'trigger','invoice','due_terms_days',30,
    'recurring_cycle',null
  )))
$$;

create temporary table qf5b_fixture(
  quote_request_id uuid not null,
  qualification_intake_id uuid not null,
  uploaded_file_id uuid not null,
  preparation_authority_id uuid,
  decision_id uuid,
  business_draft_id uuid,
  generic_intake_id uuid,
  pricing_snapshot_id uuid,
  approval_id uuid,
  approval_sha256 text,
  issuance_id uuid,
  artifact_id uuid
);
insert into qf5b_fixture(quote_request_id,qualification_intake_id,uploaded_file_id)
values (
  pg_temp.qf5b_uuid('qf5b-request'),
  pg_temp.qf5b_uuid('qf5b-intake'),
  pg_temp.qf5b_uuid('qf5b-file')
);

insert into auth.users(id,email) values
  (pg_temp.qf5b_uuid('qf5b-owner-auth'),'qf5b-owner@example.test'),
  (pg_temp.qf5b_uuid('qf5b-operator-auth'),'qf5b-operator@example.test');
insert into public.commercial_operators(
  operator_id,auth_user_id,display_name,role,status
) values
  (pg_temp.qf5b_uuid('qf5b-owner-operator'),pg_temp.qf5b_uuid('qf5b-owner-auth'),
   'QF-5B Synthetic Owner','owner','ACTIVE'),
  (pg_temp.qf5b_uuid('qf5b-operator'),pg_temp.qf5b_uuid('qf5b-operator-auth'),
   'QF-5B Synthetic Operator','operator','ACTIVE');

insert into public.quote_requests(
  id,application_reference,record_classification,request_kind,sdf_package,
  name,company,email,description,privacy_consent,status,
  billing_address,billing_postal_code,billing_city,billing_country
)
select quote_request_id,'LWS-AAN-2099-9981','production','slimme_documentenflow',
  'start','QF-5B Synthetic','Synthetic QF-5B BV','qf5b@example.test',
  'Synthetic QF-5B fixture.',true,'approved','Teststraat 1','9000','Gent','BE'
from qf5b_fixture;
insert into public.sdf_projects(project_id,quote_request_id)
select pg_temp.qf5b_uuid('qf5b-project'),quote_request_id from qf5b_fixture;
insert into public.sdf_qualification_intakes(
  intake_id,quote_request_id,status,taxonomy_version,customer_capability_digest,
  customer_capability_encrypted,customer_capability_expires_at,draft_answers,
  draft_revision,latest_submission_sequence
)
select qualification_intake_id,quote_request_id,'qualification_complete',
  'sdf_qualification_intake/3.0.0',repeat('1',64),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  clock_timestamp()+interval '1 day',pg_temp.qf5b_payload(),1,1
from qf5b_fixture;
insert into public.sdf_qualification_intake_submissions(
  submission_id,intake_id,submission_sequence,answers,taxonomy_version,
  payload_sha256,confirmation_version,confirmation_sha256
)
select pg_temp.qf5b_uuid('qf5b-submission'),qualification_intake_id,1,
  pg_temp.qf5b_payload(),'sdf_qualification_intake/3.0.0',
  encode(extensions.digest(convert_to(pg_temp.qf5b_payload()::text,'UTF8'),'sha256'),'hex'),
  'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1',repeat('2',64)
from qf5b_fixture;
insert into public.sdf_qualification_intake_events(
  event_id,intake_id,event_kind,from_status,to_status,actor_class,
  submission_sequence
)
select pg_temp.qf5b_uuid('qf5b-completion'),qualification_intake_id,
  'QUALIFICATION_COMPLETE','under_review','qualification_complete','system',1
from qf5b_fixture;

insert into public.customer_requests(
  request_id,request_reference,quote_request_id,source,request_type,title,
  description,status,priority,submitted_at,submitter_type
)
select pg_temp.qf5b_uuid('qf5b-customer-request'),'LWS-VRZ-2099-9981',
  quote_request_id,'OPERATOR','FILE_DELIVERY','QF-5B synthetic evidence',
  'Synthetic evidence.','NEW','NORMAL',clock_timestamp(),'OPERATOR'
from qf5b_fixture;
insert into public.customer_request_upload_requests(
  upload_request_id,customer_request_id,token_digest,status,expires_at,created_at,
  created_by_operator_id,completed_at
)
select pg_temp.qf5b_uuid('qf5b-upload'),pg_temp.qf5b_uuid('qf5b-customer-request'),
  repeat('3',64),'COMPLETED',clock_timestamp()+interval '1 day',clock_timestamp(),
  pg_temp.qf5b_uuid('qf5b-owner-operator'),clock_timestamp()
from qf5b_fixture;
insert into public.customer_request_uploaded_files(
  uploaded_file_id,upload_request_id,customer_request_id,status,storage_object_path,
  original_file_name,file_extension,declared_content_type,declared_byte_count,
  observed_content_type,observed_byte_count,sha256,accepted_at
)
select uploaded_file_id,pg_temp.qf5b_uuid('qf5b-upload'),
  pg_temp.qf5b_uuid('qf5b-customer-request'),'ACCEPTED',
  'requests/'||pg_temp.qf5b_uuid('qf5b-customer-request')::text||
    '/uploads/'||pg_temp.qf5b_uuid('qf5b-upload')::text||
    '/files/'||uploaded_file_id::text||'.pdf',
  'qf5b.pdf','pdf','application/pdf',100,
  'application/pdf',100,repeat('4',64),clock_timestamp()
from qf5b_fixture;
insert into public.document_inbox_items(
  id,sha256,storage_object_path,original_file_name,mime_type,byte_count,
  source_type,source_instance,external_id,created_by_operator_id
)
select pg_temp.qf5b_uuid('qf5b-inbox'),repeat('4',64),
  'documents/'||repeat('4',64)||'.pdf','qf5b.pdf','application/pdf',100,
  'CUSTOMER_REQUEST_UPLOAD',pg_temp.qf5b_uuid('qf5b-customer-request')::text,
  uploaded_file_id::text,pg_temp.qf5b_uuid('qf5b-owner-operator')
from qf5b_fixture;
insert into public.document_inbox_customer_request_upload_sources(
  uploaded_file_id,customer_request_id,quote_request_id,document_inbox_item_id,
  promoted_by_operator_id
)
select uploaded_file_id,pg_temp.qf5b_uuid('qf5b-customer-request'),quote_request_id,
  pg_temp.qf5b_uuid('qf5b-inbox'),pg_temp.qf5b_uuid('qf5b-owner-operator')
from qf5b_fixture;

select set_config('request.jwt.claim.sub',pg_temp.qf5b_uuid('qf5b-owner-auth')::text,true);
select public.confirm_sdf_scope_classification_v1(
  quote_request_id,
  (select submission.submission_id
   from public.sdf_qualification_intakes intake
   join public.sdf_qualification_intake_submissions submission using (intake_id)
   where intake.quote_request_id=qf5b_fixture.quote_request_id),
  'standard',false,'start',pg_temp.qf5b_uuid('qf5b-classification-key')
)
from qf5b_fixture;
create temporary table qf5b_requirement as
select uploaded_file_id,(public.create_sdf_document_requirement_v1(
  quote_request_id,'invoice',1
)->>'requirement_id')::uuid requirement_id
from qf5b_fixture;
select public.bind_sdf_document_requirement_evidence_v1(
  requirement_id,uploaded_file_id
) from qf5b_requirement;
update qf5b_fixture set preparation_authority_id=(
  public.authorize_sdf_quotation_preparation_v1(
    quote_request_id,pg_temp.qf5b_uuid('qf5b-preparation-key')
  )->>'authority_id'
)::uuid;

create temporary table qf5b_vat as
select vat_decision_authority_id approved_id
from public.quotation_vat_decision_authorities
where authority_family='LWS_OUTGOING_VAT' and status='APPROVED';
insert into public.quotation_vat_transaction_classifications(
  classification_id,quote_request_id,context_sha256,classification_code,
  source_reference,source_sha256,classified_by,classified_at
)
select pg_temp.qf5b_uuid('qf5b-vat-classification'),quote_request_id,
  public.quotation_vat_context_sha256_v1(quote_request_id),
  'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION','TEST_ONLY:QF5B',
  repeat('5',64),'QF5B_TEST',clock_timestamp()
from qf5b_fixture;
insert into public.quotation_vat_turnover_snapshots(
  turnover_snapshot_id,vat_decision_authority_id,threshold_year,
  measurement_watermark,governed_turnover_minor,currency,state,
  source_reference,source_sha256,predecessor_snapshot_id,recorded_by,recorded_at
) values (
  pg_temp.qf5b_uuid('qf5b-vat-turnover'),(select approved_id from qf5b_vat),
  2026,current_date,0,'EUR','BELOW_OR_AT_THRESHOLD','TEST_ONLY:QF5B',
  repeat('6',64),null,'QF5B_TEST',clock_timestamp()
);
insert into public.quotation_terms_authorities(
  terms_authority_id,terms_id,terms_version,terms_sha256,source_path,status,
  effective_from,approved_by,approved_at
) values (
  pg_temp.qf5b_uuid('qf5b-terms'),'QF5B_TERMS','1.0.0',repeat('7',64),
  'synthetic/qf5b-terms','APPROVED',current_date,'QF5B_TEST',clock_timestamp()
);
update qf5b_fixture set decision_id=(
  public.authorize_sdf_quotation_commercial_decision_v1(
    quote_request_id,preparation_authority_id,(select approved_id from qf5b_vat),
    pg_temp.qf5b_uuid('qf5b-terms'),pg_temp.qf5b_schedule(),
    pg_temp.qf5b_uuid('qf5b-decision-key')
  )->>'decision_id'
)::uuid;

create temporary table qf5b_business_result as
select public.create_sdf_quotation_business_draft_v2(
  preparation_authority_id,decision_id,pg_temp.qf5b_uuid('qf5b-business-key'),6
) result from qf5b_fixture;
update qf5b_fixture set
  business_draft_id=(result->>'business_draft_id')::uuid,
  generic_intake_id=(result->>'generic_intake_id')::uuid,
  pricing_snapshot_id=(result->>'pricing_snapshot_id')::uuid
from qf5b_business_result;

create function pg_temp.qf5b_proof()
returns jsonb language sql stable set search_path=public,extensions,pg_catalog as $$
  select jsonb_build_object(
    'algorithmVersion','hmac-sha256-v1','keyId','v1','mac',repeat('8',64),
    'root',public.quotation_approval_integrity_root_v1(
      pg_temp.qf5b_uuid('qf5b-approval'),
      rtrim(business.canonical_payload_sha256),1::smallint,
      business.quote_request_id,business.intake_id,business.pricing_snapshot_id
    )
  )
  from public.quote_request_quotation_business_drafts business
  join qf5b_fixture fixture
    on fixture.business_draft_id=business.business_draft_id
$$;
create temporary table qf5b_approval_result as
select public.promote_sdf_quotation_business_draft_to_approval_v1(
  business_draft_id,1,pg_temp.qf5b_uuid('qf5b-approval-key'),
  pg_temp.qf5b_uuid('qf5b-approval'),pg_temp.qf5b_proof()
) result from qf5b_fixture;
update qf5b_fixture fixture set
  approval_id=(result.result->>'approval_id')::uuid,
  approval_sha256=approval.payload_sha256
from qf5b_approval_result result
join public.quote_request_quotation_approvals approval
  on approval.id=(result.result->>'approval_id')::uuid;

create temporary table qf5b_prepare as
select result.* from qf5b_fixture fixture
cross join lateral public.prepare_sdf_quotation_issuance_v1(
  fixture.business_draft_id,fixture.approval_id,1,fixture.approval_sha256,
  1::smallint,pg_temp.qf5b_uuid('qf5b-prepare-key')
) result;
update qf5b_fixture set issuance_id=(select issuance_id from qf5b_prepare);

select set_config('request.jwt.claim.sub',pg_temp.qf5b_uuid('qf5b-operator-auth')::text,true);
select throws_ok(format(
  $sql$select * from public.prepare_sdf_issued_quotation_delivery_v1(%L,%L,1,%L,%L,%L,%L,100,%L,%L,null)$sql$,
  (select business_draft_id from qf5b_fixture),(select approval_id from qf5b_fixture),
  (select approval_sha256 from qf5b_fixture),(select issuance_id from qf5b_fixture),
  pg_temp.qf5b_uuid('missing-artifact'),repeat('9',64),repeat('a',64),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
),'42501','OWNER_REQUIRED','authenticated non-owner is rejected');
select set_config('request.jwt.claim.sub',pg_temp.qf5b_uuid('qf5b-owner-auth')::text,true);
select throws_ok(format(
  $sql$select * from public.prepare_sdf_issued_quotation_delivery_v1(%L,%L,1,%L,%L,%L,%L,100,%L,%L,null)$sql$,
  pg_temp.qf5b_uuid('wrong-business'),(select approval_id from qf5b_fixture),
  (select approval_sha256 from qf5b_fixture),(select issuance_id from qf5b_fixture),
  pg_temp.qf5b_uuid('missing-artifact'),repeat('9',64),repeat('a',64),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
),'P0001','SDF_BUSINESS_DRAFT_NOT_FOUND','wrong business draft is rejected');

create temporary table qf5b_cross_fixture as select
  pg_temp.qf5b_uuid('qf5b-cross-request') quote_request_id,
  pg_temp.qf5b_uuid('qf5b-cross-intake') intake_id,
  pg_temp.qf5b_uuid('qf5b-cross-pricing') pricing_snapshot_id,
  pg_temp.qf5b_uuid('qf5b-cross-draft') draft_id,
  pg_temp.qf5b_uuid('qf5b-cross-approval') approval_id;
insert into public.quote_requests(
  id,application_reference,record_classification,request_kind,sdf_package,
  name,company,email,description,privacy_consent,status,
  billing_address,billing_postal_code,billing_city,billing_country
)
select quote_request_id,'LWS-AAN-2099-9982','production','slimme_documentenflow',
  'start','QF-5B Cross','Synthetic QF-5B Cross BV','qf5b-cross@example.test',
  'Separate synthetic cross-dossier fixture.',true,'approved',
  'Teststraat 2','9000','Gent','BE'
from qf5b_cross_fixture;
select set_config('lws.sdf_generic_intake_adapter','CREATE',true);
insert into public.quote_request_intakes(
  id,quote_request_id,status,access_token_hash,access_token_expires_at,
  started_at,submitted_at,confirmation
)
select intake_id,quote_request_id,'submitted',repeat('f',64),
  clock_timestamp()+interval '1 day',clock_timestamp(),clock_timestamp(),true
from qf5b_cross_fixture;
select set_config('lws.sdf_generic_intake_adapter','',true);
insert into public.quote_request_pricing_snapshots(
  id,intake_id,config_version,config_hash,normalized_evidence,calculation,
  package_advice,budget_evaluation,snapshot_contract_version,
  package_definition,recurring_services,sdf_pricing
)
select pricing_snapshot_id,intake_id,'1.0.0',repeat('1',64),
  '{"standardPages":["home"],"standardPageCount":1,"primaryLanguage":"nl","additionalLanguages":[],"unknownLanguages":[],"modules":[],"manualComponents":[]}'::jsonb,
  '{"basis":"starter_floor","currency":"EUR","vatBasis":"exclusive","knownMinimumMinor":180000,"containsFromPricing":true,"manualReviewRequired":false,"manualReasons":[],"appliedRules":[{"ruleId":"starter_floor","mode":"from","amountMinor":180000,"quantity":1,"knownMinimumContributionMinor":180000}]}'::jsonb,
  '{"status":"none","reasons":[],"advisoryOnly":true,"selectedPackage":null}'::jsonb,
  '{"contractVersion":2,"evidenceProvenance":"budget_guard_v1","categoryScheme":"budget_guard_v1","categoryCode":"3200_to_6000_inclusive","originalLabel":"EUR 3.200 t/m EUR 6.000","status":"possibly_compatible_with_category","outsideBudgetWishes":false}'::jsonb,
  2,null,null,null
from qf5b_cross_fixture;
insert into public.quote_request_pricing_snapshot_integrity(
  snapshot_id,algorithm_version,key_id,mac
)
select pricing_snapshot_id,'hmac-sha256-v1','v1',repeat('2',64)
from qf5b_cross_fixture;

create temporary table qf5b_cross_payload as
with source as (
  select approval.approved_payload payload,cross_fixture.*
  from qf5b_fixture fixture
  join public.quote_request_quotation_approvals approval
    on approval.id=fixture.approval_id
  cross join qf5b_cross_fixture cross_fixture
), rewritten as (
  select source.*,
    ((payload->'customer_identity')::jsonb - 'snapshot_sha256'::text) || jsonb_build_object(
      'source_quote_request_id',quote_request_id,
      'source_intake_id',intake_id
    ) identity_base,
    ((payload->'project_scope')::jsonb - 'snapshot_sha256'::text) || jsonb_build_object(
      'source_intake_id',intake_id,
      'source_pricing_snapshot_id',pricing_snapshot_id
    ) scope_base
  from source
)
select rewritten.*,
  payload || jsonb_build_object(
    'source_quote_request_id',quote_request_id,
    'source_intake_id',intake_id,
    'pricing_snapshot',jsonb_build_object(
      'snapshot_id',pricing_snapshot_id,'snapshot_contract_version',2,
      'integrity_algorithm_version','hmac-sha256-v1',
      'integrity_key_id','v1','integrity_mac',repeat('2',64)
    ),
    'customer_identity',identity_base || jsonb_build_object(
      'snapshot_sha256',encode(extensions.digest(
        convert_to(identity_base::text,'UTF8'),'sha256'
      ),'hex')
    ),
    'project_scope',scope_base || jsonb_build_object(
      'snapshot_sha256',encode(extensions.digest(
        convert_to(scope_base::text,'UTF8'),'sha256'
      ),'hex')
    )
  ) approval_payload
from rewritten;

insert into public.quote_request_quotation_approval_drafts(
  id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,
  approval_payload,payload_fingerprint,idempotency_key,created_by
)
select draft_id,quote_request_id,intake_id,pricing_snapshot_id,1,
  approval_payload,public.quotation_approval_payload_sha256_v1(approval_payload),
  pg_temp.qf5b_uuid('qf5b-cross-draft-key'),'QF5B_TEST'
from qf5b_cross_payload;
insert into public.quote_request_quotation_approvals(
  id,draft_id,quote_request_id,intake_id,pricing_snapshot_id,contract_version,
  approval_version,approved_payload,payload_sha256,approved_by,approved_at
)
select approval_id,draft_id,quote_request_id,intake_id,pricing_snapshot_id,1,1,
  approval_payload,public.quotation_approval_payload_sha256_v1(approval_payload),
  'QF5B_TEST',clock_timestamp()
from qf5b_cross_payload;
insert into public.quote_request_quotation_approval_integrity(
  approval_id,algorithm_version,key_id,mac
) values (pg_temp.qf5b_uuid('qf5b-cross-approval'),'hmac-sha256-v1','v1',repeat('b',64));

select throws_ok(format(
  $sql$select * from public.prepare_sdf_issued_quotation_delivery_v1(%L,%L,1,%L,%L,%L,%L,100,%L,%L,null)$sql$,
  (select business_draft_id from qf5b_fixture),pg_temp.qf5b_uuid('qf5b-cross-approval'),
  (select public.quotation_approval_payload_sha256_v1(approval_payload)
    from qf5b_cross_payload),(select issuance_id from qf5b_fixture),
  pg_temp.qf5b_uuid('missing-artifact'),repeat('9',64),repeat('a',64),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
),'42501','SDF_ISSUANCE_CROSS_DOSSIER','cross-dossier approval is rejected');
select throws_ok(format(
  $sql$select * from public.prepare_sdf_issued_quotation_delivery_v1(%L,%L,2,%L,%L,%L,%L,100,%L,%L,null)$sql$,
  (select business_draft_id from qf5b_fixture),(select approval_id from qf5b_fixture),
  (select approval_sha256 from qf5b_fixture),(select issuance_id from qf5b_fixture),
  pg_temp.qf5b_uuid('missing-artifact'),repeat('9',64),repeat('a',64),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
),'P0001','SDF_APPROVAL_STALE','stale approval version is rejected');
select throws_ok(format(
  $sql$select * from public.prepare_sdf_issued_quotation_delivery_v1(%L,%L,1,%L,%L,%L,%L,100,%L,%L,null)$sql$,
  (select business_draft_id from qf5b_fixture),(select approval_id from qf5b_fixture),
  repeat('c',64),(select issuance_id from qf5b_fixture),
  pg_temp.qf5b_uuid('missing-artifact'),repeat('9',64),repeat('a',64),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
),'P0001','SDF_APPROVAL_STALE','stale approval SHA is rejected');
select throws_ok(format(
  $sql$select * from public.prepare_sdf_issued_quotation_delivery_v1(%L,%L,1,%L,%L,%L,%L,100,%L,%L,null)$sql$,
  (select business_draft_id from qf5b_fixture),(select approval_id from qf5b_fixture),
  (select approval_sha256 from qf5b_fixture),(select issuance_id from qf5b_fixture),
  pg_temp.qf5b_uuid('missing-artifact'),repeat('9',64),repeat('a',64),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
),'P0001','SDF_DELIVERY_NOT_AVAILABLE','PREPARED issuance is rejected');

select public.commit_sdf_quotation_issuance_v1(
  business_draft_id,approval_id,1,approval_sha256,issuance_id,
  pg_temp.qf5b_uuid('qf5b-commit-key'),repeat('d',64),
  'LWS_QUOTATION_NL_BE','1.0.0-technical',repeat('e',64),1::smallint,
  repeat('9',64),100,null,null
) from qf5b_fixture;

insert into public.quote_request_quotation_issuances(
  id,quotation_number,quotation_version,status,approval_id,issued_at,issued_by,
  template_id,template_version,template_sha256,generation_contract_version,
  generation_payload_sha256,docx_sha256,docx_bytes,prepare_idempotency_key,
  prepare_fingerprint,commit_idempotency_key,commit_fingerprint,
  issuance_input_sha256
) values (
  pg_temp.qf5b_uuid('qf5b-cross-issuance'),'LWS-OFF-2099-9982',2,'ISSUED',
  pg_temp.qf5b_uuid('qf5b-cross-approval'),clock_timestamp(),'QF5B_TEST',
  'LWS_QUOTATION_NL_BE','1.0.0-technical',repeat('e',64),1,repeat('d',64),
  repeat('f',64),110,pg_temp.qf5b_uuid('qf5b-cross-prepare-key'),repeat('1',64),
  pg_temp.qf5b_uuid('qf5b-cross-commit-key'),repeat('2',64),repeat('3',64)
);
select throws_ok(format(
  $sql$select * from public.prepare_sdf_issued_quotation_delivery_v1(%L,%L,1,%L,%L,%L,%L,100,%L,%L,null)$sql$,
  (select business_draft_id from qf5b_fixture),(select approval_id from qf5b_fixture),
  (select approval_sha256 from qf5b_fixture),pg_temp.qf5b_uuid('qf5b-cross-issuance'),
  pg_temp.qf5b_uuid('missing-artifact'),repeat('9',64),repeat('a',64),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
),'42501','SDF_DELIVERY_CROSS_DOSSIER','cross-dossier issuance is rejected');
select throws_ok(format(
  $sql$select * from public.prepare_sdf_issued_quotation_delivery_v1(%L,%L,1,%L,%L,%L,%L,100,%L,%L,null)$sql$,
  (select business_draft_id from qf5b_fixture),(select approval_id from qf5b_fixture),
  (select approval_sha256 from qf5b_fixture),(select issuance_id from qf5b_fixture),
  pg_temp.qf5b_uuid('missing-artifact'),repeat('9',64),repeat('a',64),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
),'P0001','SDF_DELIVERY_ARTIFACT_NOT_FOUND','missing artifact is rejected');

insert into storage.objects(bucket_id,name,metadata)
select 'quotation-artifacts','issuances/'||issuance_id||'/docx/'||repeat('9',64)||'.docx',
  jsonb_build_object('size',100,'mimetype',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
from qf5b_fixture;
create temporary table qf5b_docx as
select result.* from qf5b_fixture fixture
cross join lateral public.register_quotation_artifact_v1(
  fixture.issuance_id,'DOCX',repeat('9',64),100,
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  pg_temp.qf5b_uuid('qf5b-artifact-key'),'QF5B_TEST'
) result;
update qf5b_fixture set artifact_id=(select artifact_id from qf5b_docx);

insert into storage.objects(bucket_id,name,metadata) values (
  'quotation-artifacts',
  'issuances/'||pg_temp.qf5b_uuid('qf5b-cross-issuance')||'/docx/'||repeat('f',64)||'.docx',
  jsonb_build_object('size',110,'mimetype',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
);
insert into public.quote_request_quotation_artifacts(
  artifact_id,issuance_id,artifact_type,storage_bucket_id,storage_object_path,
  content_type,sha256,byte_count,registration_idempotency_key,
  registration_fingerprint,created_by
) values (
  pg_temp.qf5b_uuid('qf5b-cross-artifact'),pg_temp.qf5b_uuid('qf5b-cross-issuance'),
  'DOCX','quotation-artifacts',
  'issuances/'||pg_temp.qf5b_uuid('qf5b-cross-issuance')||'/docx/'||repeat('f',64)||'.docx',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  repeat('f',64),110,pg_temp.qf5b_uuid('qf5b-cross-artifact-key'),repeat('4',64),
  'QF5B_TEST'
);
insert into storage.objects(bucket_id,name,metadata)
select 'quotation-artifacts','issuances/'||issuance_id||'/pdf/'||repeat('5',64)||'.pdf',
  jsonb_build_object('size',90,'mimetype','application/pdf')
from qf5b_fixture;
insert into public.quote_request_quotation_artifacts(
  artifact_id,issuance_id,artifact_type,storage_bucket_id,storage_object_path,
  content_type,sha256,byte_count,registration_idempotency_key,
  registration_fingerprint,created_by
)
select pg_temp.qf5b_uuid('qf5b-pdf-artifact'),issuance_id,'PDF',
  'quotation-artifacts','issuances/'||issuance_id||'/pdf/'||repeat('5',64)||'.pdf',
  'application/pdf',repeat('5',64),90,pg_temp.qf5b_uuid('qf5b-pdf-key'),
  repeat('6',64),'QF5B_TEST'
from qf5b_fixture;

select throws_ok(format(
  $sql$select * from public.prepare_sdf_issued_quotation_delivery_v1(%L,%L,1,%L,%L,%L,%L,100,%L,%L,null)$sql$,
  (select business_draft_id from qf5b_fixture),(select approval_id from qf5b_fixture),
  (select approval_sha256 from qf5b_fixture),(select issuance_id from qf5b_fixture),
  pg_temp.qf5b_uuid('qf5b-cross-artifact'),repeat('9',64),repeat('a',64),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
),'42501','SDF_DELIVERY_ARTIFACT_CROSS_ISSUANCE','artifact from another issuance is rejected');
select throws_ok(format(
  $sql$select * from public.prepare_sdf_issued_quotation_delivery_v1(%L,%L,1,%L,%L,%L,%L,90,%L,%L,null)$sql$,
  (select business_draft_id from qf5b_fixture),(select approval_id from qf5b_fixture),
  (select approval_sha256 from qf5b_fixture),(select issuance_id from qf5b_fixture),
  pg_temp.qf5b_uuid('qf5b-pdf-artifact'),repeat('5',64),repeat('a',64),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
),'P0001','SDF_DELIVERY_ARTIFACT_TYPE_INVALID','wrong artifact type is rejected');
select throws_ok(format(
  $sql$select * from public.prepare_sdf_issued_quotation_delivery_v1(%L,%L,1,%L,%L,%L,%L,100,%L,%L,null)$sql$,
  (select business_draft_id from qf5b_fixture),(select approval_id from qf5b_fixture),
  (select approval_sha256 from qf5b_fixture),(select issuance_id from qf5b_fixture),
  (select artifact_id from qf5b_fixture),repeat('7',64),repeat('a',64),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
),'P0001','SDF_DELIVERY_ARTIFACT_HASH_MISMATCH','artifact hash mismatch is rejected');
select throws_ok(format(
  $sql$select * from public.prepare_sdf_issued_quotation_delivery_v1(%L,%L,1,%L,%L,%L,%L,101,%L,%L,null)$sql$,
  (select business_draft_id from qf5b_fixture),(select approval_id from qf5b_fixture),
  (select approval_sha256 from qf5b_fixture),(select issuance_id from qf5b_fixture),
  (select artifact_id from qf5b_fixture),repeat('9',64),repeat('a',64),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
),'P0001','SDF_DELIVERY_ARTIFACT_BYTES_MISMATCH','artifact byte-count mismatch is rejected');

update storage.objects set metadata=jsonb_build_object(
  'size',101,'mimetype','application/vnd.openxmlformats-officedocument.wordprocessingml.document'
) where bucket_id='quotation-artifacts'
  and name=(select storage_object_path from qf5b_docx);
select throws_ok(format(
  $sql$select * from public.prepare_sdf_issued_quotation_delivery_v1(%L,%L,1,%L,%L,%L,%L,100,%L,%L,null)$sql$,
  (select business_draft_id from qf5b_fixture),(select approval_id from qf5b_fixture),
  (select approval_sha256 from qf5b_fixture),(select issuance_id from qf5b_fixture),
  (select artifact_id from qf5b_fixture),repeat('9',64),repeat('a',64),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
),'P0001','SDF_DELIVERY_ARTIFACT_METADATA_MISMATCH','wrong Storage metadata is rejected');
update storage.objects set metadata=jsonb_build_object(
  'size',100,'mimetype','application/vnd.openxmlformats-officedocument.wordprocessingml.document'
) where bucket_id='quotation-artifacts'
  and name=(select storage_object_path from qf5b_docx);

create temporary table qf5b_baseline as select
  (select count(*) from public.quote_request_quotation_issuances) issuance_count,
  (select count(*) from public.quote_request_quotation_artifacts) artifact_count,
  (select quotation_number from public.quote_request_quotation_issuances
    where id=(select issuance_id from qf5b_fixture)) quotation_number;
create temporary table qf5b_delivery as
select result.* from qf5b_fixture fixture
cross join lateral public.prepare_sdf_issued_quotation_delivery_v1(
  fixture.business_draft_id,fixture.approval_id,1,fixture.approval_sha256,
  fixture.issuance_id,fixture.artifact_id,repeat('9',64),100,repeat('a',64),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  clock_timestamp()+interval '90 days'
) result;

select is((select job_status from qf5b_delivery),'pending','owner prepares only a pending job');
select is((select capability_was_created from qf5b_delivery),true,'owner creates capability');
select is((select delivery_was_created from qf5b_delivery),true,'owner creates delivery orchestration');
select is((select artifact_id from qf5b_delivery),(select artifact_id from qf5b_fixture),
  'successful result is bound to exact archived DOCX');
select is((select count(*)::integer from public.quote_request_quotation_acceptance_capabilities
  where issuance_id=(select issuance_id from qf5b_fixture)),1,
  'exactly one ACTIVE capability is prepared');
select is((select count(*)::integer from public.quote_request_quotation_acceptance_capability_operations
  where capability_id=(select capability_id from qf5b_delivery)),1,
  'existing capability operation ledger records CREATE');
select is((select count(*)::integer from public.quote_request_quotation_acceptance_capability_events
  where capability_id=(select capability_id from qf5b_delivery) and event_type='CREATED'),1,
  'existing capability event ledger records CREATED');
select is((select count(*)::integer from public.quote_request_quotation_email_orchestrations
  where id=(select orchestration_id from qf5b_delivery)),1,
  'existing immutable delivery orchestration is reused');
select is((select count(*)::integer from public.quote_request_email_jobs
  where id=(select email_job_id from qf5b_delivery) and kind='quotation_delivery'),1,
  'existing quotation delivery job model is reused');

create temporary table qf5b_replay as
select result.* from qf5b_fixture fixture
cross join lateral public.prepare_sdf_issued_quotation_delivery_v1(
  fixture.business_draft_id,fixture.approval_id,1,fixture.approval_sha256,
  fixture.issuance_id,fixture.artifact_id,repeat('9',64),100,repeat('b',64),
  'v1.BBBBBBBBBBBBBBBB.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
  clock_timestamp()+interval '1 day'
) result;
select is((select capability_id from qf5b_replay),(select capability_id from qf5b_delivery),
  'exact replay returns the same capability');
select is((select email_job_id from qf5b_replay),(select email_job_id from qf5b_delivery),
  'exact replay returns the same delivery job');
select is((select orchestration_id from qf5b_replay),(select orchestration_id from qf5b_delivery),
  'exact replay returns the same orchestration');
select is((select stored_token_digest from qf5b_replay),repeat('a',64),
  'replay retains original capability digest and ignores replacement token material');
select ok((select not capability_was_created and not delivery_was_created from qf5b_replay),
  'replay reports no new preparation writes');
select is((select quotation_number from public.quote_request_quotation_issuances
  where id=(select issuance_id from qf5b_fixture)),
  (select quotation_number from qf5b_baseline),'delivery preparation changes no quotation number');
select is((select count(*) from public.quote_request_quotation_issuances),
  (select issuance_count from qf5b_baseline),'delivery preparation creates no issuance');
select is((select count(*) from public.quote_request_quotation_artifacts),
  (select artifact_count from qf5b_baseline),'delivery preparation creates or changes no artifact');
select is((select count(*)::integer from public.quote_request_quotation_acceptances
  where issuance_id=(select issuance_id from qf5b_fixture)),0,
  'delivery preparation performs no acceptance consumption');
select is((select attempt_count from public.quote_request_email_jobs
  where id=(select email_job_id from qf5b_delivery)),0,
  'delivery job is never claimed');
select is((select status::text from public.quote_request_email_jobs
  where id=(select email_job_id from qf5b_delivery)),'pending',
  'delivery job is never marked sent');
select is((select provider_message_id from public.quote_request_email_jobs
  where id=(select email_job_id from qf5b_delivery)),null,
  'no provider or Resend side effect exists');
select is((select encrypted_payload from public.quote_request_email_jobs
  where id=(select email_job_id from qf5b_delivery)),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  'encrypted retry token is retained in the existing job');
select ok((select capability_expires_at <= deadline.acceptance_deadline_at
  from qf5b_delivery
  cross join lateral public.quotation_issuance_acceptance_deadline_v1(
    (select issuance_id from qf5b_fixture)
  ) deadline),'requested expiry is capped by existing acceptance deadline');

select * from finish();
rollback;