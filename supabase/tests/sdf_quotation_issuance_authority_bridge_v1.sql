begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(31);

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
  'public','prepare_sdf_quotation_issuance_v1',
  array['uuid','uuid','integer','text','smallint','uuid'],
  'QF-3B SDF PREPARE bridge exists'
);
select has_function(
  'public','commit_sdf_quotation_issuance_v1',
  array['uuid','uuid','integer','text','uuid','uuid','text','text','text','text',
    'smallint','text','bigint','text','bigint'],
  'QF-3B SDF COMMIT bridge exists'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.prepare_sdf_quotation_issuance_v1(uuid,uuid,integer,text,smallint,uuid)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.prepare_sdf_quotation_issuance_v1(uuid,uuid,integer,text,smallint,uuid)',
    'execute'
  ) and not has_function_privilege(
    'service_role',
    'public.prepare_sdf_quotation_issuance_v1(uuid,uuid,integer,text,smallint,uuid)',
    'execute'
  ),
  'only authenticated human owner route can invoke QF-3B'
);

create function pg_temp.qf3b_uuid(p_value text)
returns uuid language sql immutable set search_path=pg_catalog as $$
  select (substr(md5(p_value),1,8)||'-'||substr(md5(p_value),9,4)||'-4'||
    substr(md5(p_value),14,3)||'-8'||substr(md5(p_value),18,3)||'-'||
    substr(md5(p_value),21,12))::uuid
$$;

create function pg_temp.qf3b_payload(p_package text)
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
          'documentCount',case p_package when 'start' then 499
            when 'groei' then 2499 else 7499 end,
          'period','monthly','averagePagesPerDocument',1
        ),
        jsonb_build_object(
          'documentType','invoice','documentCount',1,'period','monthly',
          'averagePagesPerDocument',1
        )
      ),
      'flowCount',case p_package when 'start' then 1 when 'groei' then 3 else 6 end,
      'userCount',case p_package when 'start' then 3 when 'groei' then 10 else 25 end
    )
  )
$$;

create function pg_temp.qf3b_schedule()
returns jsonb language sql immutable set search_path=pg_catalog as $$
  select jsonb_build_object('milestones',jsonb_build_array(jsonb_build_object(
    'sequence',1,'label','Synthetic implementation payment','percentage',100,
    'amount_minor',null,'trigger','invoice','due_terms_days',30,'recurring_cycle',null
  )))
$$;

create temporary table qf3b_fixtures(
  label text primary key,
  package text not null,
  quote_request_id uuid not null,
  intake_id uuid not null,
  uploaded_file_id uuid not null,
  preparation_authority_id uuid,
  decision_id uuid,
  business_draft_id uuid,
  generic_intake_id uuid,
  pricing_snapshot_id uuid,
  approval_id uuid,
  approval_sha256 text
);
insert into qf3b_fixtures(label,package,quote_request_id,intake_id,uploaded_file_id)
select label,package,
  pg_temp.qf3b_uuid('qf3b-'||label||'-request'),
  pg_temp.qf3b_uuid('qf3b-'||label||'-intake'),
  pg_temp.qf3b_uuid('qf3b-'||label||'-file')
from (values
  ('start','start'),('groei','groei'),('pro','pro'),('stale','start')
) as fixture(label,package);

insert into auth.users(id,email) values
  (pg_temp.qf3b_uuid('qf3b-owner-auth'),'qf3b-owner@example.test'),
  (pg_temp.qf3b_uuid('qf3b-admin-auth'),'qf3b-admin@example.test');
insert into public.commercial_operators(
  operator_id,auth_user_id,display_name,role,status
) values
  (pg_temp.qf3b_uuid('qf3b-owner-operator'),pg_temp.qf3b_uuid('qf3b-owner-auth'),
   'QF-3B Synthetic Owner','owner','ACTIVE'),
  (pg_temp.qf3b_uuid('qf3b-admin-operator'),pg_temp.qf3b_uuid('qf3b-admin-auth'),
   'QF-3B Synthetic Admin','admin','ACTIVE');

insert into public.quote_requests(
  id,application_reference,record_classification,request_kind,sdf_package,
  name,company,email,description,privacy_consent,status,
  billing_address,billing_postal_code,billing_city,billing_country
)
select quote_request_id,
  'LWS-AAN-2099-'||(9900+row_number() over(order by label))::text,
  'production','slimme_documentenflow','start','QF-3B '||label,
  'Synthetic QF-3B BV','qf3b-'||label||'@example.test',
  'Synthetic QF-3B fixture.',true,'approved',
  'Teststraat 1','9000','Gent','BE'
from qf3b_fixtures;
insert into public.sdf_projects(project_id,quote_request_id)
select pg_temp.qf3b_uuid('qf3b-'||label||'-project'),quote_request_id
from qf3b_fixtures;
insert into public.sdf_qualification_intakes(
  intake_id,quote_request_id,status,taxonomy_version,customer_capability_digest,
  customer_capability_encrypted,customer_capability_expires_at,draft_answers,
  draft_revision,latest_submission_sequence
)
select intake_id,quote_request_id,'qualification_complete',
  'sdf_qualification_intake/3.0.0',
  encode(extensions.digest(convert_to('qf3b-'||label,'UTF8'),'sha256'),'hex'),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  clock_timestamp()+interval '1 day',pg_temp.qf3b_payload(package),1,1
from qf3b_fixtures;
insert into public.sdf_qualification_intake_submissions(
  submission_id,intake_id,submission_sequence,answers,taxonomy_version,
  payload_sha256,confirmation_version,confirmation_sha256
)
select pg_temp.qf3b_uuid('qf3b-'||fixture.label||'-submission'),
  intake.intake_id,1,intake.draft_answers,intake.taxonomy_version,
  encode(extensions.digest(convert_to(intake.draft_answers::text,'UTF8'),'sha256'),'hex'),
  'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1',repeat('a',64)
from qf3b_fixtures fixture
join public.sdf_qualification_intakes intake on intake.intake_id=fixture.intake_id;
insert into public.sdf_qualification_intake_events(
  event_id,intake_id,event_kind,from_status,to_status,actor_class,submission_sequence
)
select pg_temp.qf3b_uuid('qf3b-'||label||'-completion'),intake_id,
  'QUALIFICATION_COMPLETE','under_review','qualification_complete','system',1
from qf3b_fixtures;

insert into public.customer_requests(
  request_id,request_reference,quote_request_id,source,request_type,title,
  description,status,priority,submitted_at,submitter_type
)
select pg_temp.qf3b_uuid('qf3b-'||label||'-customer-request'),
  'LWS-VRZ-2099-'||(9900+row_number() over(order by label))::text,
  quote_request_id,'OPERATOR','FILE_DELIVERY','QF-3B synthetic evidence',
  'Synthetic evidence.','NEW','NORMAL',clock_timestamp(),'OPERATOR'
from qf3b_fixtures;
insert into public.customer_request_upload_requests(
  upload_request_id,customer_request_id,token_digest,status,expires_at,created_at,
  created_by_operator_id,completed_at
)
select pg_temp.qf3b_uuid('qf3b-'||label||'-upload'),
  pg_temp.qf3b_uuid('qf3b-'||label||'-customer-request'),
  encode(extensions.digest(convert_to('qf3b-token-'||label,'UTF8'),'sha256'),'hex'),
  'COMPLETED',clock_timestamp()+interval '1 day',clock_timestamp(),
  pg_temp.qf3b_uuid('qf3b-owner-operator'),clock_timestamp()
from qf3b_fixtures;
insert into public.customer_request_uploaded_files(
  uploaded_file_id,upload_request_id,customer_request_id,status,storage_object_path,
  original_file_name,file_extension,declared_content_type,declared_byte_count,
  observed_content_type,observed_byte_count,sha256,accepted_at
)
select uploaded_file_id,pg_temp.qf3b_uuid('qf3b-'||label||'-upload'),
  pg_temp.qf3b_uuid('qf3b-'||label||'-customer-request'),'ACCEPTED',
  'requests/'||pg_temp.qf3b_uuid('qf3b-'||label||'-customer-request')::text||
    '/uploads/'||pg_temp.qf3b_uuid('qf3b-'||label||'-upload')::text||
    '/files/'||uploaded_file_id::text||'.pdf',
  'qf3b-'||label||'.pdf','pdf','application/pdf',100,
  'application/pdf',100,
  encode(extensions.digest(convert_to('qf3b-file-'||label,'UTF8'),'sha256'),'hex'),
  clock_timestamp()
from qf3b_fixtures;
insert into public.document_inbox_items(
  id,sha256,storage_object_path,original_file_name,mime_type,byte_count,
  source_type,source_instance,external_id,created_by_operator_id
)
select pg_temp.qf3b_uuid('qf3b-'||label||'-inbox'),
  encode(extensions.digest(convert_to('qf3b-file-'||label,'UTF8'),'sha256'),'hex'),
  'documents/'||encode(extensions.digest(
    convert_to('qf3b-file-'||label,'UTF8'),'sha256'
  ),'hex')||'.pdf',
  'qf3b-'||label||'.pdf','application/pdf',100,'CUSTOMER_REQUEST_UPLOAD',
  pg_temp.qf3b_uuid('qf3b-'||label||'-customer-request')::text,
  uploaded_file_id::text,pg_temp.qf3b_uuid('qf3b-owner-operator')
from qf3b_fixtures;
insert into public.document_inbox_customer_request_upload_sources(
  uploaded_file_id,customer_request_id,quote_request_id,document_inbox_item_id,
  promoted_by_operator_id
)
select uploaded_file_id,pg_temp.qf3b_uuid('qf3b-'||label||'-customer-request'),
  quote_request_id,pg_temp.qf3b_uuid('qf3b-'||label||'-inbox'),
  pg_temp.qf3b_uuid('qf3b-owner-operator')
from qf3b_fixtures;

select set_config(
  'request.jwt.claim.sub',pg_temp.qf3b_uuid('qf3b-owner-auth')::text,true
);
create temporary table qf3b_requirements as
select label,uploaded_file_id,
  (public.create_sdf_document_requirement_v1(
    quote_request_id,'invoice',1
  )->>'requirement_id')::uuid requirement_id
from qf3b_fixtures;
select public.bind_sdf_document_requirement_evidence_v1(
  requirement_id,uploaded_file_id
) from qf3b_requirements;
update qf3b_fixtures fixture set preparation_authority_id=(
  public.authorize_sdf_quotation_preparation_v1(
    fixture.quote_request_id,
    pg_temp.qf3b_uuid('qf3b-'||fixture.label||'-preparation-key')
  )->>'authority_id'
)::uuid;

create temporary table qf3b_vat as
select vat_decision_authority_id approved_id
from public.quotation_vat_decision_authorities
where authority_family='LWS_OUTGOING_VAT' and status='APPROVED';
insert into public.quotation_vat_transaction_classifications(
  classification_id,quote_request_id,context_sha256,classification_code,
  source_reference,source_sha256,classified_by,classified_at
)
select pg_temp.qf3b_uuid('qf3b-'||label||'-vat-classification'),quote_request_id,
  public.quotation_vat_context_sha256_v1(quote_request_id),
  'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION','TEST_ONLY:QF3B',
  repeat('b',64),'QF3B_TEST',clock_timestamp()
from qf3b_fixtures;
insert into public.quotation_vat_turnover_snapshots(
  turnover_snapshot_id,vat_decision_authority_id,threshold_year,
  measurement_watermark,governed_turnover_minor,currency,state,
  source_reference,source_sha256,predecessor_snapshot_id,recorded_by,recorded_at
) values (
  pg_temp.qf3b_uuid('qf3b-vat-turnover'),(select approved_id from qf3b_vat),
  2026,current_date,0,'EUR','BELOW_OR_AT_THRESHOLD','TEST_ONLY:QF3B',
  repeat('c',64),null,'QF3B_TEST',clock_timestamp()
);
insert into public.quotation_terms_authorities(
  terms_authority_id,terms_id,terms_version,terms_sha256,source_path,status,
  effective_from,approved_by,approved_at
) values (
  pg_temp.qf3b_uuid('qf3b-terms'),'QF3B_TERMS','1.0.0',repeat('d',64),
  'synthetic/qf3b-terms','APPROVED',current_date,'QF3B_TEST',clock_timestamp()
);
update qf3b_fixtures fixture set decision_id=(
  public.authorize_sdf_quotation_commercial_decision_v1(
    fixture.quote_request_id,fixture.preparation_authority_id,
    (select approved_id from qf3b_vat),pg_temp.qf3b_uuid('qf3b-terms'),
    pg_temp.qf3b_schedule(),
    pg_temp.qf3b_uuid('qf3b-'||fixture.label||'-decision-key')
  )->>'decision_id'
)::uuid;

create temporary table qf3b_business_results(label text primary key,value jsonb);
insert into qf3b_business_results
select label,public.create_sdf_quotation_business_draft_v2(
  preparation_authority_id,decision_id,
  pg_temp.qf3b_uuid('qf3b-'||label||'-business-key'),
  case label when 'start' then 3 else 6 end
) from qf3b_fixtures;
update qf3b_fixtures fixture set
  business_draft_id=(result.value->>'business_draft_id')::uuid,
  generic_intake_id=(result.value->>'generic_intake_id')::uuid,
  pricing_snapshot_id=(result.value->>'pricing_snapshot_id')::uuid
from qf3b_business_results result
where result.label=fixture.label;

create function pg_temp.qf3b_proof(p_label text)
returns jsonb language sql stable set search_path=public,extensions,pg_catalog as $$
  select jsonb_build_object(
    'algorithmVersion','hmac-sha256-v1','keyId','v1',
    'mac',encode(extensions.digest(convert_to(
      'qf3b-approval-proof:'||p_label,'UTF8'
    ),'sha256'),'hex'),
    'root',public.quotation_approval_integrity_root_v1(
      pg_temp.qf3b_uuid('qf3b-'||p_label||'-approval'),
      rtrim(business.canonical_payload_sha256),1::smallint,
      business.quote_request_id,business.intake_id,business.pricing_snapshot_id
    )
  )
  from public.quote_request_quotation_business_drafts business
  join qf3b_fixtures fixture on fixture.business_draft_id=business.business_draft_id
  where fixture.label=p_label
$$;

create temporary table qf3b_approval_results(label text primary key,result jsonb);
insert into qf3b_approval_results
select label,public.promote_sdf_quotation_business_draft_to_approval_v1(
  business_draft_id,1,
  pg_temp.qf3b_uuid('qf3b-'||label||'-approval-key'),
  pg_temp.qf3b_uuid('qf3b-'||label||'-approval'),
  pg_temp.qf3b_proof(label)
) from qf3b_fixtures;
update qf3b_fixtures fixture set
  approval_id=(result.result->>'approval_id')::uuid,
  approval_sha256=approval.payload_sha256
from qf3b_approval_results result
join public.quote_request_quotation_approvals approval
  on approval.id=(result.result->>'approval_id')::uuid
where result.label=fixture.label;

create temporary table qf3b_baseline as
select
  (select count(*) from public.quote_request_quotation_acceptance_capabilities) delivery_count,
  (select count(*) from public.quote_request_quotation_email_orchestrations) mail_count;

select ok(not exists(
  select 1 from qf3b_fixtures fixture
  join public.quote_request_intakes intake on intake.id=fixture.generic_intake_id
  where intake.admin_access_token_hash is not null
),'SDF issuance authority has no fabricated admin capability');
select throws_ok(format(
  $sql$select * from public.prepare_quotation_issuance_v2(%L,2030::smallint,1::smallint,%L,%L,null,'legacy')$sql$,
  (select approval_id from qf3b_fixtures where label='start'),
  (select approval_sha256 from qf3b_fixtures where label='start'),
  pg_temp.qf3b_uuid('qf3b-legacy-prepare')
),'42501','UNAUTHORIZED','legacy website PREPARE still requires admin capability');

create temporary table qf3b_prepare_results as
select fixture.label,result.*
from qf3b_fixtures fixture
cross join lateral public.prepare_sdf_quotation_issuance_v1(
  fixture.business_draft_id,fixture.approval_id,1,fixture.approval_sha256,
  1::smallint,pg_temp.qf3b_uuid('qf3b-'||fixture.label||'-prepare-key')
) result
where fixture.label in ('start','groei','pro');

select is((select count(*)::integer from qf3b_prepare_results),3,
  'START, GROEI, and PRO prepare through the SDF bridge');
select ok(not exists(
  select 1 from qf3b_prepare_results
  where status<>'PREPARED' or was_created<>true
),'all SDF preparations use existing PREPARED semantics');
select ok(not exists(
  select 1 from qf3b_prepare_results
  where quotation_number !~ '^LWS-OFF-[0-9]{4}-[0-9]{4}$'
),'quotation numbering retains LWS-OFF-YYYY-SSSS');
select ok(not exists(
  select 1 from qf3b_prepare_results where quotation_version<>1
),'first SDF issuance version is 1');
select is((select count(distinct quotation_number)::integer from qf3b_prepare_results),3,
  'atomic counter allocates unique quotation numbers');
select ok(not exists(
  select 1 from qf3b_prepare_results result
  join qf3b_fixtures fixture on fixture.label=result.label
  where result.issuance_input_sha256<>fixture.approval_sha256
),'prepare derives issuance input hash from approval authority');
select is((select was_created from public.prepare_sdf_quotation_issuance_v1(
  (select business_draft_id from qf3b_fixtures where label='start'),
  (select approval_id from qf3b_fixtures where label='start'),1,
  (select approval_sha256 from qf3b_fixtures where label='start'),1::smallint,
  pg_temp.qf3b_uuid('qf3b-start-prepare-key')
)),false,'exact PREPARE replay is idempotent');
select is((select count(*)::integer from public.quote_request_quotation_issuances),3,
  'PREPARE replay allocates no duplicate issuance or number');
select throws_ok(format(
  $sql$select * from public.prepare_sdf_quotation_issuance_v1(%L,%L,1,%L,1::smallint,%L)$sql$,
  (select business_draft_id from qf3b_fixtures where label='groei'),
  (select approval_id from qf3b_fixtures where label='groei'),
  (select approval_sha256 from qf3b_fixtures where label='groei'),
  pg_temp.qf3b_uuid('qf3b-start-prepare-key')
),'P0001','IDEMPOTENCY_CONFLICT','same PREPARE key with changed authority conflicts');

select set_config(
  'request.jwt.claim.sub',pg_temp.qf3b_uuid('qf3b-admin-auth')::text,true
);
select throws_ok(format(
  $sql$select * from public.prepare_sdf_quotation_issuance_v1(%L,%L,1,%L,1::smallint,%L)$sql$,
  (select business_draft_id from qf3b_fixtures where label='stale'),
  (select approval_id from qf3b_fixtures where label='stale'),
  (select approval_sha256 from qf3b_fixtures where label='stale'),
  pg_temp.qf3b_uuid('qf3b-non-owner-prepare-key')
),'42501','OWNER_REQUIRED','non-owner cannot prepare SDF issuance');
select set_config(
  'request.jwt.claim.sub',pg_temp.qf3b_uuid('qf3b-owner-auth')::text,true
);
select throws_ok(format(
  $sql$select * from public.prepare_sdf_quotation_issuance_v1(%L,%L,1,%L,1::smallint,%L)$sql$,
  (select business_draft_id from qf3b_fixtures where label='start'),
  (select approval_id from qf3b_fixtures where label='groei'),
  (select approval_sha256 from qf3b_fixtures where label='groei'),
  pg_temp.qf3b_uuid('qf3b-cross-prepare-key')
),'42501','SDF_ISSUANCE_CROSS_DOSSIER','cross-dossier approval is rejected');
select throws_ok(format(
  $sql$select * from public.prepare_sdf_quotation_issuance_v1(%L,%L,2,%L,1::smallint,%L)$sql$,
  (select business_draft_id from qf3b_fixtures where label='stale'),
  (select approval_id from qf3b_fixtures where label='stale'),
  (select approval_sha256 from qf3b_fixtures where label='stale'),
  pg_temp.qf3b_uuid('qf3b-stale-version-key')
),'P0001','SDF_APPROVAL_STALE','stale approval version is rejected');
select throws_ok(format(
  $sql$select * from public.prepare_sdf_quotation_issuance_v1(%L,%L,1,%L,1::smallint,%L)$sql$,
  (select business_draft_id from qf3b_fixtures where label='stale'),
  (select approval_id from qf3b_fixtures where label='stale'),repeat('9',64),
  pg_temp.qf3b_uuid('qf3b-stale-hash-key')
),'P0001','SDF_APPROVAL_STALE','changed approval hash is rejected');

create temporary table qf3b_stale_prepare as
select * from public.prepare_sdf_quotation_issuance_v1(
  (select business_draft_id from qf3b_fixtures where label='stale'),
  (select approval_id from qf3b_fixtures where label='stale'),1,
  (select approval_sha256 from qf3b_fixtures where label='stale'),1::smallint,
  pg_temp.qf3b_uuid('qf3b-stale-prepare-key')
);

alter table public.sdf_quotation_business_draft_adapters disable trigger user;
update public.sdf_quotation_business_draft_adapters
set pricing_authority_sha256=repeat('8',64)
where business_draft_id=(select business_draft_id from qf3b_fixtures where label='stale');
alter table public.sdf_quotation_business_draft_adapters enable trigger user;
select throws_ok(format(
  $sql$select * from public.prepare_sdf_quotation_issuance_v1(%L,%L,1,%L,1::smallint,%L)$sql$,
  (select business_draft_id from qf3b_fixtures where label='stale'),
  (select approval_id from qf3b_fixtures where label='stale'),
  (select approval_sha256 from qf3b_fixtures where label='stale'),
  pg_temp.qf3b_uuid('qf3b-stale-lineage-key')
),'55000','SDF_PRICING_AUTHORITY_MISMATCH','stale SDF pricing lineage is rejected');
select throws_ok(format(
  $sql$select * from public.commit_sdf_quotation_issuance_v1(%L,%L,1,%L,%L,%L,%L,'LWS_QUOTATION_NL_BE','1.0.0-technical',%L,1::smallint,%L,100,null,null)$sql$,
  (select business_draft_id from qf3b_fixtures where label='stale'),
  (select approval_id from qf3b_fixtures where label='stale'),
  (select approval_sha256 from qf3b_fixtures where label='stale'),
  (select issuance_id from qf3b_stale_prepare),
  pg_temp.qf3b_uuid('qf3b-stale-commit-key'),repeat('6',64),
  lower('3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE'),
  repeat('4',64)
),'55000','SDF_PRICING_AUTHORITY_MISMATCH','COMMIT revalidates stale SDF lineage');

create temporary table qf3b_generation as
select public.project_quotation_generation_payload_v1(
  'ISSUE',approval.id,approval.approved_payload,approval.payload_sha256,
  jsonb_build_object(
    'template_id','LWS_QUOTATION_NL_BE','template_version','1.0.0-technical',
    'template_sha256',lower('3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE'),
    'authority_status','APPROVED'
  ),
  jsonb_build_object(
    'legal_name','Lorenzo Web Solutions','address_line_1','Teststraat 1',
    'address_line_2',null,'postal_code','9000','city','Gent','country_code','BE',
    'enterprise_number','BE0123456789','vat_number','BE0123456789',
    'email','info@example.test','website','https://example.test','contact_name',null
  ),issuance.id,issuance.quotation_number,issuance.quotation_version
) payload
from public.quote_request_quotation_approvals approval
join qf3b_fixtures fixture on fixture.approval_id=approval.id and fixture.label='start'
join public.quote_request_quotation_issuances issuance on issuance.approval_id=approval.id;

select ok(public.is_valid_quotation_generation_payload_v1(payload),
  'existing generic generation projector produces valid ISSUE payload')
from qf3b_generation;
select ok(exists(
  select 1 from qf3b_generation,
    lateral jsonb_array_elements(payload->'lines') line
  where line->>'cost_type'='ONE_TIME'
),'generation preserves ONE_TIME line');
select ok(exists(
  select 1 from qf3b_generation,
    lateral jsonb_array_elements(payload->'lines') line
  where line->>'cost_type'='RECURRING'
),'generation preserves RECURRING line');
select is((select payload#>>'{pricing_references,pricing_snapshot_contract_version}'
  from qf3b_generation),'4','generation preserves pricing snapshot v4');

select throws_ok(format(
  $sql$select * from public.commit_quotation_issuance_v2(%L,%L,%L,%L,'LWS_QUOTATION_NL_BE','1.0.0-technical',%L,1::smallint,%L,100,null,null,'legacy',null)$sql$,
  (select issuance_id from qf3b_prepare_results where label='start'),
  pg_temp.qf3b_uuid('qf3b-legacy-commit-key'),
  (select approval_sha256 from qf3b_fixtures where label='start'),
  (select public.quotation_generation_payload_sha256_v1(payload) from qf3b_generation),
  lower('3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE'),
  repeat('4',64)
),'42501','UNAUTHORIZED','legacy website COMMIT still requires admin capability');

create temporary table qf3b_commit_result as
select * from public.commit_sdf_quotation_issuance_v1(
  (select business_draft_id from qf3b_fixtures where label='start'),
  (select approval_id from qf3b_fixtures where label='start'),1,
  (select approval_sha256 from qf3b_fixtures where label='start'),
  (select issuance_id from qf3b_prepare_results where label='start'),
  pg_temp.qf3b_uuid('qf3b-start-commit-key'),
  (select public.quotation_generation_payload_sha256_v1(payload) from qf3b_generation),
  'LWS_QUOTATION_NL_BE','1.0.0-technical',
  lower('3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE'),
  1::smallint,repeat('4',64),100,null,null
);
select is((select status from qf3b_commit_result),'ISSUED',
  'valid SDF COMMIT reaches existing ISSUED state');
select is((select issued_by from public.quote_request_quotation_issuances
  where id=(select issuance_id from qf3b_commit_result)),
  'OPERATOR:'||pg_temp.qf3b_uuid('qf3b-owner-operator')::text,
  'COMMIT records the server-derived owner actor');
select is((select was_committed from public.commit_sdf_quotation_issuance_v1(
  (select business_draft_id from qf3b_fixtures where label='start'),
  (select approval_id from qf3b_fixtures where label='start'),1,
  (select approval_sha256 from qf3b_fixtures where label='start'),
  (select issuance_id from qf3b_prepare_results where label='start'),
  pg_temp.qf3b_uuid('qf3b-start-commit-key'),
  (select public.quotation_generation_payload_sha256_v1(payload) from qf3b_generation),
  'LWS_QUOTATION_NL_BE','1.0.0-technical',
  lower('3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE'),
  1::smallint,repeat('4',64),100,null,null
)),false,'exact COMMIT replay is idempotent');
select throws_ok(format(
  $sql$select * from public.commit_sdf_quotation_issuance_v1(%L,%L,1,%L,%L,%L,%L,'LWS_QUOTATION_NL_BE','1.0.0-technical',%L,1::smallint,%L,100,null,null)$sql$,
  (select business_draft_id from qf3b_fixtures where label='start'),
  (select approval_id from qf3b_fixtures where label='start'),
  (select approval_sha256 from qf3b_fixtures where label='start'),
  (select issuance_id from qf3b_prepare_results where label='start'),
  pg_temp.qf3b_uuid('qf3b-start-commit-key'),repeat('7',64),
  lower('3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE'),
  repeat('4',64)
),'P0001','IDEMPOTENCY_CONFLICT','same COMMIT key with changed generation hash conflicts');
select is((select count(*) from public.quote_request_quotation_acceptance_capabilities),
  (select delivery_count from qf3b_baseline),'QF-3B creates no delivery capability');
select is((select count(*) from public.quote_request_quotation_email_orchestrations),
  (select mail_count from qf3b_baseline),'QF-3B creates no mail orchestration');

select * from finish();
rollback;