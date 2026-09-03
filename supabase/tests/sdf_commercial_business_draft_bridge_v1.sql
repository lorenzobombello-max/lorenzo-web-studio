begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

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

select has_table('public','sdf_quotation_business_draft_adapters','QF-2 immutable adapter ledger exists');
select has_function(
  'public','create_sdf_quotation_business_draft_v2',array['uuid','uuid','uuid','integer'],
  'QF-2 owner-only bridge requires an integer indicative execution term'
);
select ok(
  not has_function_privilege('anon','public.create_sdf_quotation_business_draft_v1(uuid,uuid,uuid)','execute')
  and not has_function_privilege('service_role','public.create_sdf_quotation_business_draft_v1(uuid,uuid,uuid)','execute')
  and not has_function_privilege('authenticated','public.create_sdf_quotation_business_draft_v1(uuid,uuid,uuid)','execute')
  and not has_function_privilege('anon','public.create_sdf_quotation_business_draft_v2(uuid,uuid,uuid,integer)','execute')
  and not has_function_privilege('service_role','public.create_sdf_quotation_business_draft_v2(uuid,uuid,uuid,integer)','execute')
  and has_function_privilege('authenticated','public.create_sdf_quotation_business_draft_v2(uuid,uuid,uuid,integer)','execute'),
  'only authenticated owner path can invoke v2 and the nullable legacy path is closed'
);

create function pg_temp.fixture_uuid(p_value text)
returns uuid language sql immutable set search_path=pg_catalog as $$
  select (substr(md5(p_value),1,8)||'-'||substr(md5(p_value),9,4)||'-4'||substr(md5(p_value),14,3)||'-8'||substr(md5(p_value),18,3)||'-'||substr(md5(p_value),21,12))::uuid
$$;

create function pg_temp.sdf_v3_payload(p_package text)
returns jsonb language sql immutable set search_path=pg_catalog as $$
  select jsonb_build_object(
    'documentPurpose',jsonb_build_object('categories',jsonb_build_array('quotation','invoice')),
    'workflowCapabilities',jsonb_build_array('receive'),
    'businessRequirements',jsonb_build_object(
      'currentWorkflow','Synthetic current workflow','desiredWorkflow','Synthetic controlled workflow',
      'volumeBand','50_to_249','frequency','monthly',
      'relevantDocumentTypes',jsonb_build_array('Synthetic documents'),
      'rolesUsers',jsonb_build_array('Synthetic users')
    ),
    'sampleDocumentMetadata',jsonb_build_object(
      'available',false,'requestedByLws',false,'uploadRequiredLater',false
    ),
    'commercialQualification',jsonb_build_object(
      'packageDirection',case when p_package='maatwerk' then 'maatwerk' else 'start' end,
      'customComplexity',case when p_package='maatwerk' then 'Synthetic complexity' else '' end,
      'documentVolumes',jsonb_build_array(jsonb_build_object(
        'documentType','quotation',
        'documentCount',case p_package when 'start' then 499 when 'groei' then 2499
          when 'pro' then 7499 else 7500 end,
        'period','monthly','averagePagesPerDocument',1
      ),jsonb_build_object(
        'documentType','invoice','documentCount',1,'period','monthly','averagePagesPerDocument',1
      )),
      'flowCount',case p_package when 'start' then 1 when 'groei' then 3 when 'pro' then 6 else 7 end,
      'userCount',case p_package when 'start' then 3 when 'groei' then 10 else 25 end
    )
  )
$$;

create function pg_temp.schedule()
returns jsonb language sql immutable set search_path=pg_catalog as $$
  select jsonb_build_object('milestones',jsonb_build_array(jsonb_build_object(
    'sequence',1,'label','Synthetic implementation payment','percentage',100,
    'amount_minor',null,'trigger','invoice','due_terms_days',30,'recurring_cycle',null
  )))
$$;

create temporary table qf2_fixtures(
  label text primary key, package text not null, quote_request_id uuid not null,
  intake_id uuid not null, uploaded_file_id uuid not null,
  preparation_authority_id uuid, decision_id uuid
);
insert into qf2_fixtures(label,package,quote_request_id,intake_id,uploaded_file_id)
select label,package,pg_temp.fixture_uuid('qf2-'||label||'-request'),
  pg_temp.fixture_uuid('qf2-'||label||'-intake'),pg_temp.fixture_uuid('qf2-'||label||'-file')
from (values
  ('start','start'),('groei','groei'),('pro','pro'),('maatwerk','maatwerk'),
  ('invalid','start'),('stale-price','start'),('stale-doc','start'),
  ('stale-decision','start'),('cross-a','start'),('cross-b','groei')
) as fixture(label,package);

insert into auth.users(id,email) values
  (pg_temp.fixture_uuid('qf2-owner-auth'),'qf2-owner@example.test');
insert into public.commercial_operators(operator_id,auth_user_id,display_name,role,status) values
  (pg_temp.fixture_uuid('qf2-owner-operator'),pg_temp.fixture_uuid('qf2-owner-auth'),'QF-2 Synthetic Owner','owner','ACTIVE');

insert into public.quote_requests(
  id,application_reference,record_classification,request_kind,sdf_package,
  name,company,email,description,privacy_consent,status,
  billing_address,billing_postal_code,billing_city,billing_country
)
select quote_request_id,'LWS-AAN-2099-'||(9700+row_number() over(order by label))::text,
  'production','slimme_documentenflow','start','QF-2 '||label,'Synthetic QF-2 BV',
  'qf2-'||label||'@example.test','Synthetic QF-2 fixture.',true,'approved',
  'Teststraat 1','9000','Gent','BE'
from qf2_fixtures;
insert into public.sdf_projects(project_id,quote_request_id)
select pg_temp.fixture_uuid('qf2-'||label||'-project'),quote_request_id from qf2_fixtures;
insert into public.sdf_qualification_intakes(
  intake_id,quote_request_id,status,taxonomy_version,customer_capability_digest,
  customer_capability_encrypted,customer_capability_expires_at,draft_answers,
  draft_revision,latest_submission_sequence
)
select intake_id,quote_request_id,'qualification_complete','sdf_qualification_intake/3.0.0',
  encode(extensions.digest(convert_to('qf2-'||label,'UTF8'),'sha256'),'hex'),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  clock_timestamp()+interval '1 day',pg_temp.sdf_v3_payload(package),1,1
from qf2_fixtures;
insert into public.sdf_qualification_intake_submissions(
  submission_id,intake_id,submission_sequence,answers,taxonomy_version,
  payload_sha256,confirmation_version,confirmation_sha256
)
select pg_temp.fixture_uuid('qf2-'||fixture.label||'-submission'),intake.intake_id,1,
  intake.draft_answers,intake.taxonomy_version,
  encode(extensions.digest(convert_to(intake.draft_answers::text,'UTF8'),'sha256'),'hex'),
  'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1',repeat('a',64)
from qf2_fixtures fixture join public.sdf_qualification_intakes intake
  on intake.intake_id=fixture.intake_id;
insert into public.sdf_qualification_intake_events(
  event_id,intake_id,event_kind,from_status,to_status,actor_class,submission_sequence
)
select pg_temp.fixture_uuid('qf2-'||label||'-completion'),intake_id,
  'QUALIFICATION_COMPLETE','under_review','qualification_complete','system',1
from qf2_fixtures;

insert into public.customer_requests(
  request_id,request_reference,quote_request_id,source,request_type,title,
  description,status,priority,submitted_at,submitter_type
)
select pg_temp.fixture_uuid('qf2-'||label||'-customer-request'),
  'LWS-VRZ-2099-'||(9700+row_number() over(order by label))::text,quote_request_id,
  'OPERATOR','FILE_DELIVERY','QF-2 synthetic evidence','Synthetic evidence.',
  'NEW','NORMAL',clock_timestamp(),'OPERATOR'
from qf2_fixtures;
insert into public.customer_request_upload_requests(
  upload_request_id,customer_request_id,token_digest,status,expires_at,created_at,
  created_by_operator_id,completed_at
)
select pg_temp.fixture_uuid('qf2-'||label||'-upload'),
  pg_temp.fixture_uuid('qf2-'||label||'-customer-request'),
  encode(extensions.digest(convert_to('qf2-token-'||label,'UTF8'),'sha256'),'hex'),
  'COMPLETED',clock_timestamp()+interval '1 day',clock_timestamp(),
  pg_temp.fixture_uuid('qf2-owner-operator'),clock_timestamp()
from qf2_fixtures;
insert into public.customer_request_uploaded_files(
  uploaded_file_id,upload_request_id,customer_request_id,status,storage_object_path,
  original_file_name,file_extension,declared_content_type,declared_byte_count,
  observed_content_type,observed_byte_count,sha256,accepted_at
)
select uploaded_file_id,pg_temp.fixture_uuid('qf2-'||label||'-upload'),
  pg_temp.fixture_uuid('qf2-'||label||'-customer-request'),'ACCEPTED',
  'requests/'||pg_temp.fixture_uuid('qf2-'||label||'-customer-request')::text||
    '/uploads/'||pg_temp.fixture_uuid('qf2-'||label||'-upload')::text||
    '/files/'||uploaded_file_id::text||'.pdf',
  'qf2-'||label||'.pdf','pdf','application/pdf',100,'application/pdf',100,
  encode(extensions.digest(convert_to('qf2-file-'||label,'UTF8'),'sha256'),'hex'),clock_timestamp()
from qf2_fixtures;
insert into public.document_inbox_items(
  id,sha256,storage_object_path,original_file_name,mime_type,byte_count,
  source_type,source_instance,external_id,created_by_operator_id
)
select pg_temp.fixture_uuid('qf2-'||label||'-inbox'),
  encode(extensions.digest(convert_to('qf2-file-'||label,'UTF8'),'sha256'),'hex'),
  'documents/'||encode(extensions.digest(convert_to('qf2-file-'||label,'UTF8'),'sha256'),'hex')||'.pdf',
  'qf2-'||label||'.pdf','application/pdf',100,
  'CUSTOMER_REQUEST_UPLOAD',pg_temp.fixture_uuid('qf2-'||label||'-customer-request')::text,
  uploaded_file_id::text,pg_temp.fixture_uuid('qf2-owner-operator')
from qf2_fixtures;
insert into public.document_inbox_customer_request_upload_sources(
  uploaded_file_id,customer_request_id,quote_request_id,document_inbox_item_id,
  promoted_by_operator_id
)
select uploaded_file_id,pg_temp.fixture_uuid('qf2-'||label||'-customer-request'),
  quote_request_id,pg_temp.fixture_uuid('qf2-'||label||'-inbox'),
  pg_temp.fixture_uuid('qf2-owner-operator') from qf2_fixtures;

select set_config('request.jwt.claim.sub',pg_temp.fixture_uuid('qf2-owner-auth')::text,true);
select public.confirm_sdf_scope_classification_v1(
  fixture.quote_request_id,
  (select submission_id from public.sdf_qualification_intake_submissions where intake_id=fixture.intake_id),
  'standard',false,fixture.package,pg_temp.fixture_uuid('qf2-'||fixture.label||'-classification-key')
)
from qf2_fixtures fixture;
create temporary table qf2_requirements as
select label,uploaded_file_id,
  (public.create_sdf_document_requirement_v1(quote_request_id,'invoice',1)->>'requirement_id')::uuid requirement_id
from qf2_fixtures;
select public.bind_sdf_document_requirement_evidence_v1(requirement_id,uploaded_file_id)
from qf2_requirements;
update qf2_fixtures fixture set preparation_authority_id=(
  public.authorize_sdf_quotation_preparation_v1(
    fixture.quote_request_id,pg_temp.fixture_uuid('qf2-'||fixture.label||'-preparation-key')
  )->>'authority_id'
)::uuid;

create temporary table qf2_vat as
select vat_decision_authority_id approved_id
from public.quotation_vat_decision_authorities
where authority_family='LWS_OUTGOING_VAT' and status='APPROVED';
insert into public.quotation_vat_transaction_classifications(
  classification_id,quote_request_id,context_sha256,classification_code,
  source_reference,source_sha256,classified_by,classified_at
)
select pg_temp.fixture_uuid('qf2-'||label||'-vat-classification'),quote_request_id,
  public.quotation_vat_context_sha256_v1(quote_request_id),
  'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION','TEST_ONLY:QF2',repeat('b',64),
  'QF2_TEST',clock_timestamp() from qf2_fixtures;
insert into public.quotation_vat_turnover_snapshots(
  turnover_snapshot_id,vat_decision_authority_id,threshold_year,measurement_watermark,
  governed_turnover_minor,currency,state,source_reference,source_sha256,
  predecessor_snapshot_id,recorded_by,recorded_at
) values (
  pg_temp.fixture_uuid('qf2-vat-turnover'),(select approved_id from qf2_vat),2026,
  current_date,0,'EUR','BELOW_OR_AT_THRESHOLD','TEST_ONLY:QF2',repeat('c',64),
  null,'QF2_TEST',clock_timestamp()
);
insert into public.quotation_terms_authorities(
  terms_authority_id,terms_id,terms_version,terms_sha256,source_path,status,
  effective_from,approved_by,approved_at
) values (
  pg_temp.fixture_uuid('qf2-terms'),'QF2_TERMS','1.0.0',repeat('d',64),
  'synthetic/qf2-terms','APPROVED',current_date,'QF2_TEST',clock_timestamp()
);
update qf2_fixtures fixture set decision_id=(
  public.authorize_sdf_quotation_commercial_decision_v1(
    fixture.quote_request_id,fixture.preparation_authority_id,
    (select approved_id from qf2_vat),pg_temp.fixture_uuid('qf2-terms'),
    pg_temp.schedule(),pg_temp.fixture_uuid('qf2-'||fixture.label||'-decision-key')
  )->>'decision_id'
)::uuid where package<>'maatwerk';

create temporary table qf2_results(label text primary key,result jsonb);
insert into qf2_results
select label,public.create_sdf_quotation_business_draft_v2(
  preparation_authority_id,decision_id,pg_temp.fixture_uuid('qf2-'||label||'-bridge-key'),
  case label when 'start' then 3 when 'groei' then 6 when 'pro' then 9 else 11 end
) from qf2_fixtures where label in ('start','groei','pro','invalid');

select is((select count(*)::integer from qf2_results),4,'business drafts require explicit quotation-specific execution terms');
select is(
  (select canonical_payload#>>'{project_scope,indicative_timing}'
   from public.quote_request_quotation_business_drafts business
   join qf2_fixtures fixture on fixture.quote_request_id=business.quote_request_id
   where fixture.label='start'),
  '3','START preserves the exact approved candidate in its immutable payload'
);
select is(
  (select canonical_payload#>>'{project_scope,indicative_timing}'
   from public.quote_request_quotation_business_drafts business
   join qf2_fixtures fixture on fixture.quote_request_id=business.quote_request_id
   where fixture.label='invalid'),
  '11','a second START quotation may carry a different execution term'
);
select isnt(
  (select canonical_payload_sha256::text
   from public.quote_request_quotation_business_drafts business
   join qf2_fixtures fixture on fixture.quote_request_id=business.quote_request_id
   where fixture.label='start'),
  (select public.quotation_approval_payload_sha256_v1(
     jsonb_set(canonical_payload,'{project_scope,indicative_timing}','11'::jsonb)
   )
   from public.quote_request_quotation_business_drafts business
   join qf2_fixtures fixture on fixture.quote_request_id=business.quote_request_id
   where fixture.label='start'),
  'the execution term participates in the immutable approval payload hash'
);
select throws_ok(format(
  $sql$select public.create_sdf_quotation_business_draft_v2(%L,%L,%L,null)$sql$,
  (select preparation_authority_id from qf2_fixtures where label='cross-a'),
  (select decision_id from qf2_fixtures where label='cross-a'),
  pg_temp.fixture_uuid('qf2-null-term-key')
),'22023','SDF_BUSINESS_DRAFT_INPUT_INVALID','missing execution term fails closed');
select throws_ok(format(
  $sql$select public.create_sdf_quotation_business_draft_v2(%L,%L,%L,0)$sql$,
  (select preparation_authority_id from qf2_fixtures where label='cross-a'),
  (select decision_id from qf2_fixtures where label='cross-a'),
  pg_temp.fixture_uuid('qf2-zero-term-key')
),'22023','SDF_BUSINESS_DRAFT_INPUT_INVALID','zero execution term fails closed');
select throws_ok(format(
  $sql$select public.create_sdf_quotation_business_draft_v2(%L,%L,%L,-1)$sql$,
  (select preparation_authority_id from qf2_fixtures where label='cross-a'),
  (select decision_id from qf2_fixtures where label='cross-a'),
  pg_temp.fixture_uuid('qf2-negative-term-key')
),'22023','SDF_BUSINESS_DRAFT_INPUT_INVALID','negative execution term fails closed');
select is(
  (select jsonb_build_array(
    canonical_payload#>'{line_items,0,unit_price_minor}',
    canonical_payload#>'{line_items,1,unit_price_minor}'
  ) from public.quote_request_quotation_business_drafts business
   join qf2_fixtures fixture on fixture.quote_request_id=business.quote_request_id
   where fixture.label='start'),'[285000,17500]'::jsonb,'START preserves setup and recurring prices'
);
select is(
  (select jsonb_build_array(
    canonical_payload#>'{line_items,0,unit_price_minor}',
    canonical_payload#>'{line_items,1,unit_price_minor}'
  ) from public.quote_request_quotation_business_drafts business
   join qf2_fixtures fixture on fixture.quote_request_id=business.quote_request_id
   where fixture.label='groei'),'[570000,29900]'::jsonb,'GROEI preserves setup and recurring prices'
);
select is(
  (select jsonb_build_array(
    canonical_payload#>'{line_items,0,unit_price_minor}',
    canonical_payload#>'{line_items,1,unit_price_minor}'
  ) from public.quote_request_quotation_business_drafts business
   join qf2_fixtures fixture on fixture.quote_request_id=business.quote_request_id
   where fixture.label='pro'),'[750000,44900]'::jsonb,'PRO preserves setup and recurring prices'
);
select is((select min(snapshot_contract_version)::integer from public.quote_request_pricing_snapshots),4,'all bridge snapshots use contract 4');
select ok(not exists(
  select 1 from public.quote_request_pricing_snapshots
  where normalized_evidence<>'{}'::jsonb or calculation<>'{}'::jsonb
     or package_advice<>'{}'::jsonb or package_definition is not null
),'bridge snapshots contain no website semantics');
select ok(not exists(
  select 1 from public.quote_request_quotation_business_drafts
  where canonical_payload#>>'{line_items,1,cost_type}'<>'RECURRING'
     or (canonical_payload#>>'{totals,recurring_subtotal_minor}')::bigint<=0
),'monthly service is stored as a recurring commercial line');
select ok(not exists(
  select 1 from public.quote_request_intakes intake
  join public.sdf_quotation_business_draft_adapters adapter on adapter.generic_intake_id=intake.id
  where intake.access_token_revoked_at is null or cardinality(intake.languages)<>0
     or cardinality(intake.requested_pages)<>0 or cardinality(intake.requested_features)<>0
     or intake.selected_package_definition_id is not null
),'generic adapters are revoked and contain no website intake semantics');
select ok(not exists(
  select 1 from public.sdf_quotation_business_draft_adapters adapter
  join public.sdf_quotation_commercial_decisions decision on decision.decision_id=adapter.commercial_decision_id
  join public.quote_request_quotation_business_drafts business on business.business_draft_id=adapter.business_draft_id
  where business.vat_decision_authority_id<>decision.vat_decision_authority_id
     or business.terms_authority_id<>decision.terms_authority_id
     or business.canonical_payload->'payment_schedule'<>decision.payment_schedule
),'business drafts preserve exact QF-2A VAT, terms, and payment authorities');
select lives_ok(
  $$select public.assert_quotation_business_draft_vat_binding_v1(business_draft_id,true)
    from public.quote_request_quotation_business_drafts$$,
  'all business VAT bindings remain current and approval-compatible'
);
select ok(not exists(
  select 1 from public.quote_request_quotation_business_drafts
  where not public.is_valid_quotation_approval_payload_v1(canonical_payload,true)
),'all resulting business drafts pass the approval payload validator');

select throws_ok(format(
  $sql$select public.create_sdf_quotation_business_draft_v1(%L,%L,%L)$sql$,
  (select preparation_authority_id from qf2_fixtures where label='maatwerk'),
  pg_temp.fixture_uuid('qf2-missing-manual-decision'),pg_temp.fixture_uuid('qf2-maatwerk-bridge-key')
),'55000','SDF_MANUAL_PRICING_REQUIRED','MAATWERK creates no business draft');
select throws_ok(format(
  $sql$select public.create_sdf_quotation_business_draft_v1(%L,%L,%L)$sql$,
  pg_temp.fixture_uuid('qf2-missing-preparation'),
  (select decision_id from qf2_fixtures where label='invalid'),pg_temp.fixture_uuid('qf2-invalid-preparation-key')
),'P0001','SDF_QUOTATION_PREPARATION_NOT_FOUND','invalid preparation is rejected');
select throws_ok(format(
  $sql$select public.create_sdf_quotation_business_draft_v1(%L,%L,%L)$sql$,
  (select preparation_authority_id from qf2_fixtures where label='invalid'),
  pg_temp.fixture_uuid('qf2-missing-decision'),pg_temp.fixture_uuid('qf2-invalid-decision-key')
),'P0001','SDF_COMMERCIAL_DECISION_NOT_FOUND','invalid commercial decision is rejected');
select throws_ok(format(
  $sql$select public.create_sdf_quotation_business_draft_v1(%L,%L,%L)$sql$,
  (select preparation_authority_id from qf2_fixtures where label='cross-a'),
  (select decision_id from qf2_fixtures where label='cross-b'),pg_temp.fixture_uuid('qf2-cross-key')
),'42501','SDF_BUSINESS_DRAFT_CROSS_DOSSIER','cross-dossier authorities are rejected');

alter table public.sdf_quotation_preparation_authorities disable trigger user;
update public.sdf_quotation_preparation_authorities set pricing_authority_sha256=repeat('1',64)
where authority_id=(select preparation_authority_id from qf2_fixtures where label='stale-price');
update public.sdf_quotation_preparation_authorities set document_evidence_sha256=repeat('2',64)
where authority_id=(select preparation_authority_id from qf2_fixtures where label='stale-doc');
alter table public.sdf_quotation_preparation_authorities enable trigger user;
alter table public.sdf_quotation_commercial_decisions disable trigger user;
alter table public.sdf_quotation_commercial_decisions
  drop constraint sdf_quotation_commercial_decision_payload_valid;
update public.sdf_quotation_commercial_decisions set decision_sha256=repeat('3',64)
where decision_id=(select decision_id from qf2_fixtures where label='stale-decision');
alter table public.sdf_quotation_commercial_decisions enable trigger user;
select throws_ok(format(
  $sql$select public.create_sdf_quotation_business_draft_v1(%L,%L,%L)$sql$,
  (select preparation_authority_id from qf2_fixtures where label='stale-price'),
  (select decision_id from qf2_fixtures where label='stale-price'),pg_temp.fixture_uuid('qf2-stale-price-key')
),'55000','SDF_PRICING_AUTHORITY_MISMATCH','stale pricing hash is rejected');
select throws_ok(format(
  $sql$select public.create_sdf_quotation_business_draft_v1(%L,%L,%L)$sql$,
  (select preparation_authority_id from qf2_fixtures where label='stale-doc'),
  (select decision_id from qf2_fixtures where label='stale-doc'),pg_temp.fixture_uuid('qf2-stale-doc-key')
),'55000','SDF_DOCUMENT_EVIDENCE_MISMATCH','stale document evidence hash is rejected');
select throws_ok(format(
  $sql$select public.create_sdf_quotation_business_draft_v1(%L,%L,%L)$sql$,
  (select preparation_authority_id from qf2_fixtures where label='stale-decision'),
  (select decision_id from qf2_fixtures where label='stale-decision'),pg_temp.fixture_uuid('qf2-stale-decision-key')
),'55000','SDF_COMMERCIAL_DECISION_INTEGRITY_MISMATCH','stale decision hash is rejected');

select is(
  public.create_sdf_quotation_business_draft_v2(
    (select preparation_authority_id from qf2_fixtures where label='start'),
    (select decision_id from qf2_fixtures where label='start'),
    pg_temp.fixture_uuid('qf2-start-bridge-key'),3
  )->>'replayed','true','exact bridge replay returns the existing business draft'
);
select is((select count(*)::integer from public.quote_request_quotation_business_drafts),4,'replay creates no duplicate business draft');
select throws_ok(format(
  $sql$select public.create_sdf_quotation_business_draft_v1(%L,%L,%L)$sql$,
  (select preparation_authority_id from qf2_fixtures where label='cross-a'),
  (select decision_id from qf2_fixtures where label='cross-a'),pg_temp.fixture_uuid('qf2-start-bridge-key')
),'P0001','IDEMPOTENCY_CONFLICT','same key with changed lineage conflicts');
select is((select count(*)::integer from public.quote_request_quotation_approvals),0,'no approval is executed');
select is((select count(*)::integer from public.quote_request_quotation_issuances),0,'no issuance is created');
select is((select count(*)::integer from public.quote_request_quotation_approval_drafts),4,'only pre-approval draft prerequisites are created');

select * from finish();
rollback;