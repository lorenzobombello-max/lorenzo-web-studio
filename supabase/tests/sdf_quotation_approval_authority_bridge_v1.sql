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
  'public','promote_sdf_quotation_business_draft_to_approval_v1',
  array['uuid','bigint','uuid','uuid','jsonb'],
  'QF-3A SDF approval CREATE bridge exists'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.promote_sdf_quotation_business_draft_to_approval_v1(uuid,bigint,uuid,uuid,jsonb)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.promote_sdf_quotation_business_draft_to_approval_v1(uuid,bigint,uuid,uuid,jsonb)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.promote_sdf_quotation_business_draft_to_approval_v1(uuid,bigint,uuid,uuid,jsonb)',
    'execute'
  ),
  'only authenticated human owner route can invoke QF-3A'
);

create function pg_temp.qf3a_uuid(p_value text)
returns uuid language sql immutable set search_path=pg_catalog as $$
  select (substr(md5(p_value),1,8)||'-'||substr(md5(p_value),9,4)||'-4'||
    substr(md5(p_value),14,3)||'-8'||substr(md5(p_value),18,3)||'-'||
    substr(md5(p_value),21,12))::uuid
$$;

create function pg_temp.qf3a_payload(p_package text)
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

create function pg_temp.qf3a_schedule()
returns jsonb language sql immutable set search_path=pg_catalog as $$
  select jsonb_build_object('milestones',jsonb_build_array(jsonb_build_object(
    'sequence',1,'label','Synthetic implementation payment','percentage',100,
    'amount_minor',null,'trigger','invoice','due_terms_days',30,'recurring_cycle',null
  )))
$$;

create temporary table qf3a_fixtures(
  label text primary key,
  package text not null,
  quote_request_id uuid not null,
  intake_id uuid not null,
  uploaded_file_id uuid not null,
  preparation_authority_id uuid,
  decision_id uuid,
  business_draft_id uuid,
  generic_intake_id uuid,
  pricing_snapshot_id uuid
);
insert into qf3a_fixtures(label,package,quote_request_id,intake_id,uploaded_file_id)
select label,package,
  pg_temp.qf3a_uuid('qf3a-'||label||'-request'),
  pg_temp.qf3a_uuid('qf3a-'||label||'-intake'),
  pg_temp.qf3a_uuid('qf3a-'||label||'-file')
from (values
  ('start','start'),('groei','groei'),('pro','pro'),
  ('stale-price','start'),('stale-doc','start'),('stale-decision','start'),
  ('cross','start'),('cross-target','start')
) as fixture(label,package);

insert into auth.users(id,email) values
  (pg_temp.qf3a_uuid('qf3a-owner-auth'),'qf3a-owner@example.test'),
  (pg_temp.qf3a_uuid('qf3a-admin-auth'),'qf3a-admin@example.test');
insert into public.commercial_operators(
  operator_id,auth_user_id,display_name,role,status
) values
  (pg_temp.qf3a_uuid('qf3a-owner-operator'),pg_temp.qf3a_uuid('qf3a-owner-auth'),
   'QF-3A Synthetic Owner','owner','ACTIVE'),
  (pg_temp.qf3a_uuid('qf3a-admin-operator'),pg_temp.qf3a_uuid('qf3a-admin-auth'),
   'QF-3A Synthetic Admin','admin','ACTIVE');

insert into public.quote_requests(
  id,application_reference,record_classification,request_kind,sdf_package,
  name,company,email,description,privacy_consent,status,
  billing_address,billing_postal_code,billing_city,billing_country
)
select quote_request_id,
  'LWS-AAN-2099-'||(9800+row_number() over(order by label))::text,
  'production','slimme_documentenflow','start','QF-3A '||label,
  'Synthetic QF-3A BV','qf3a-'||label||'@example.test',
  'Synthetic QF-3A fixture.',true,'approved',
  'Teststraat 1','9000','Gent','BE'
from qf3a_fixtures;
insert into public.sdf_projects(project_id,quote_request_id)
select pg_temp.qf3a_uuid('qf3a-'||label||'-project'),quote_request_id
from qf3a_fixtures;
insert into public.sdf_qualification_intakes(
  intake_id,quote_request_id,status,taxonomy_version,customer_capability_digest,
  customer_capability_encrypted,customer_capability_expires_at,draft_answers,
  draft_revision,latest_submission_sequence
)
select intake_id,quote_request_id,'qualification_complete',
  'sdf_qualification_intake/3.0.0',
  encode(extensions.digest(convert_to('qf3a-'||label,'UTF8'),'sha256'),'hex'),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  clock_timestamp()+interval '1 day',pg_temp.qf3a_payload(package),1,1
from qf3a_fixtures;
insert into public.sdf_qualification_intake_submissions(
  submission_id,intake_id,submission_sequence,answers,taxonomy_version,
  payload_sha256,confirmation_version,confirmation_sha256
)
select pg_temp.qf3a_uuid('qf3a-'||fixture.label||'-submission'),
  intake.intake_id,1,intake.draft_answers,intake.taxonomy_version,
  encode(extensions.digest(convert_to(intake.draft_answers::text,'UTF8'),'sha256'),'hex'),
  'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1',repeat('a',64)
from qf3a_fixtures fixture
join public.sdf_qualification_intakes intake on intake.intake_id=fixture.intake_id;
insert into public.sdf_qualification_intake_events(
  event_id,intake_id,event_kind,from_status,to_status,actor_class,submission_sequence
)
select pg_temp.qf3a_uuid('qf3a-'||label||'-completion'),intake_id,
  'QUALIFICATION_COMPLETE','under_review','qualification_complete','system',1
from qf3a_fixtures;

insert into public.customer_requests(
  request_id,request_reference,quote_request_id,source,request_type,title,
  description,status,priority,submitted_at,submitter_type
)
select pg_temp.qf3a_uuid('qf3a-'||label||'-customer-request'),
  'LWS-VRZ-2099-'||(9800+row_number() over(order by label))::text,
  quote_request_id,'OPERATOR','FILE_DELIVERY','QF-3A synthetic evidence',
  'Synthetic evidence.','NEW','NORMAL',clock_timestamp(),'OPERATOR'
from qf3a_fixtures;
insert into public.customer_request_upload_requests(
  upload_request_id,customer_request_id,token_digest,status,expires_at,created_at,
  created_by_operator_id,completed_at
)
select pg_temp.qf3a_uuid('qf3a-'||label||'-upload'),
  pg_temp.qf3a_uuid('qf3a-'||label||'-customer-request'),
  encode(extensions.digest(convert_to('qf3a-token-'||label,'UTF8'),'sha256'),'hex'),
  'COMPLETED',clock_timestamp()+interval '1 day',clock_timestamp(),
  pg_temp.qf3a_uuid('qf3a-owner-operator'),clock_timestamp()
from qf3a_fixtures;
insert into public.customer_request_uploaded_files(
  uploaded_file_id,upload_request_id,customer_request_id,status,storage_object_path,
  original_file_name,file_extension,declared_content_type,declared_byte_count,
  observed_content_type,observed_byte_count,sha256,accepted_at
)
select uploaded_file_id,pg_temp.qf3a_uuid('qf3a-'||label||'-upload'),
  pg_temp.qf3a_uuid('qf3a-'||label||'-customer-request'),'ACCEPTED',
  'requests/'||pg_temp.qf3a_uuid('qf3a-'||label||'-customer-request')::text||
    '/uploads/'||pg_temp.qf3a_uuid('qf3a-'||label||'-upload')::text||
    '/files/'||uploaded_file_id::text||'.pdf',
  'qf3a-'||label||'.pdf','pdf','application/pdf',100,
  'application/pdf',100,
  encode(extensions.digest(convert_to('qf3a-file-'||label,'UTF8'),'sha256'),'hex'),
  clock_timestamp()
from qf3a_fixtures;
insert into public.document_inbox_items(
  id,sha256,storage_object_path,original_file_name,mime_type,byte_count,
  source_type,source_instance,external_id,created_by_operator_id
)
select pg_temp.qf3a_uuid('qf3a-'||label||'-inbox'),
  encode(extensions.digest(convert_to('qf3a-file-'||label,'UTF8'),'sha256'),'hex'),
  'documents/'||encode(extensions.digest(
    convert_to('qf3a-file-'||label,'UTF8'),'sha256'
  ),'hex')||'.pdf',
  'qf3a-'||label||'.pdf','application/pdf',100,'CUSTOMER_REQUEST_UPLOAD',
  pg_temp.qf3a_uuid('qf3a-'||label||'-customer-request')::text,
  uploaded_file_id::text,pg_temp.qf3a_uuid('qf3a-owner-operator')
from qf3a_fixtures;
insert into public.document_inbox_customer_request_upload_sources(
  uploaded_file_id,customer_request_id,quote_request_id,document_inbox_item_id,
  promoted_by_operator_id
)
select uploaded_file_id,pg_temp.qf3a_uuid('qf3a-'||label||'-customer-request'),
  quote_request_id,pg_temp.qf3a_uuid('qf3a-'||label||'-inbox'),
  pg_temp.qf3a_uuid('qf3a-owner-operator')
from qf3a_fixtures;

select set_config(
  'request.jwt.claim.sub',pg_temp.qf3a_uuid('qf3a-owner-auth')::text,true
);
select public.confirm_sdf_scope_classification_v1(
  fixture.quote_request_id,
  pg_temp.qf3a_uuid('qf3a-'||fixture.label||'-submission'),
  'standard',false,fixture.package,
  pg_temp.qf3a_uuid('qf3a-'||fixture.label||'-classification-key')
)
from qf3a_fixtures fixture;
create temporary table qf3a_requirements as
select label,uploaded_file_id,
  (public.create_sdf_document_requirement_v1(
    quote_request_id,'invoice',1
  )->>'requirement_id')::uuid requirement_id
from qf3a_fixtures;
select public.bind_sdf_document_requirement_evidence_v1(
  requirement_id,uploaded_file_id
) from qf3a_requirements;
update qf3a_fixtures fixture set preparation_authority_id=(
  public.authorize_sdf_quotation_preparation_v1(
    fixture.quote_request_id,
    pg_temp.qf3a_uuid('qf3a-'||fixture.label||'-preparation-key')
  )->>'authority_id'
)::uuid;

create temporary table qf3a_vat as
select vat_decision_authority_id approved_id
from public.quotation_vat_decision_authorities
where authority_family='LWS_OUTGOING_VAT' and status='APPROVED';
insert into public.quotation_vat_transaction_classifications(
  classification_id,quote_request_id,context_sha256,classification_code,
  source_reference,source_sha256,classified_by,classified_at
)
select pg_temp.qf3a_uuid('qf3a-'||label||'-vat-classification'),quote_request_id,
  public.quotation_vat_context_sha256_v1(quote_request_id),
  'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION','TEST_ONLY:QF3A',
  repeat('b',64),'QF3A_TEST',clock_timestamp()
from qf3a_fixtures;
insert into public.quotation_vat_turnover_snapshots(
  turnover_snapshot_id,vat_decision_authority_id,threshold_year,
  measurement_watermark,governed_turnover_minor,currency,state,
  source_reference,source_sha256,predecessor_snapshot_id,recorded_by,recorded_at
) values (
  pg_temp.qf3a_uuid('qf3a-vat-turnover'),(select approved_id from qf3a_vat),
  2026,current_date,0,'EUR','BELOW_OR_AT_THRESHOLD','TEST_ONLY:QF3A',
  repeat('c',64),null,'QF3A_TEST',clock_timestamp()
);
insert into public.quotation_terms_authorities(
  terms_authority_id,terms_id,terms_version,terms_sha256,source_path,status,
  effective_from,approved_by,approved_at
) values (
  pg_temp.qf3a_uuid('qf3a-terms'),'QF3A_TERMS','1.0.0',repeat('d',64),
  'synthetic/qf3a-terms','APPROVED',current_date,'QF3A_TEST',clock_timestamp()
);
update qf3a_fixtures fixture set decision_id=(
  public.authorize_sdf_quotation_commercial_decision_v1(
    fixture.quote_request_id,fixture.preparation_authority_id,
    (select approved_id from qf3a_vat),pg_temp.qf3a_uuid('qf3a-terms'),
    pg_temp.qf3a_schedule(),
    pg_temp.qf3a_uuid('qf3a-'||fixture.label||'-decision-key')
  )->>'decision_id'
)::uuid;

create temporary table qf3a_business_results(label text primary key,value jsonb);
insert into qf3a_business_results
select label,public.create_sdf_quotation_business_draft_v2(
  preparation_authority_id,decision_id,
  pg_temp.qf3a_uuid('qf3a-'||label||'-business-key'),
  case label when 'start' then 3 when 'cross-source' then 11 else 6 end
) from qf3a_fixtures where label<>'cross-target';
update qf3a_fixtures fixture set
  business_draft_id=(result.value->>'business_draft_id')::uuid,
  generic_intake_id=(result.value->>'generic_intake_id')::uuid,
  pricing_snapshot_id=(result.value->>'pricing_snapshot_id')::uuid
from qf3a_business_results result
where result.label=fixture.label;

create function pg_temp.qf3a_proof(p_label text)
returns jsonb language sql stable set search_path=public,extensions,pg_catalog as $$
  select jsonb_build_object(
    'algorithmVersion','hmac-sha256-v1','keyId','v1',
    'mac',encode(extensions.digest(convert_to(
      'qf3a-approval-proof:'||p_label,'UTF8'
    ),'sha256'),'hex'),
    'root',public.quotation_approval_integrity_root_v1(
      pg_temp.qf3a_uuid('qf3a-'||p_label||'-approval'),
      rtrim(business.canonical_payload_sha256),1::smallint,
      business.quote_request_id,business.intake_id,business.pricing_snapshot_id
    )
  )
  from public.quote_request_quotation_business_drafts business
  join qf3a_fixtures fixture on fixture.business_draft_id=business.business_draft_id
  where fixture.label=p_label
$$;

create temporary table qf3a_baseline as
select
  (select count(*) from public.quote_request_quotation_issuances) issuance_count,
  (select count(*) from public.quote_request_quotation_email_orchestrations) mail_count;

select ok(not exists(
  select 1 from qf3a_fixtures fixture
  join public.quote_request_intakes intake on intake.id=fixture.generic_intake_id
  where fixture.label in ('start','groei','pro')
    and intake.admin_access_token_hash is not null
),'SDF adapters have no fabricated admin capability');
select throws_ok(format(
  $sql$select public.promote_quotation_business_draft_to_approval_v1(%L,%L,1,%L,%L,%L::jsonb)$sql$,
  pg_temp.qf3a_uuid('qf3a-owner-auth'),
  (select generic_intake_id from qf3a_fixtures where label='pro'),
  pg_temp.qf3a_uuid('qf3a-pro-legacy-key'),
  pg_temp.qf3a_uuid('qf3a-pro-approval'),
  pg_temp.qf3a_proof('pro')::text
),'42501','UNAUTHORIZED','legacy generic approval still requires admin capability');

create temporary table qf3a_results(label text primary key,result jsonb);
insert into qf3a_results
select label,public.promote_sdf_quotation_business_draft_to_approval_v1(
  business_draft_id,1,
  pg_temp.qf3a_uuid('qf3a-'||label||'-approval-key'),
  pg_temp.qf3a_uuid('qf3a-'||label||'-approval'),
  pg_temp.qf3a_proof(label)
) from qf3a_fixtures where label in ('start','groei','pro');

select is((select count(*)::integer from qf3a_results),3,
  'START, GROEI, and PRO approvals are created');
select ok(not exists(
  select 1 from qf3a_results where result->>'status'<>'APPROVED'
    or result->>'was_created'<>'true'
),'all successful SDF promotions return APPROVED CREATE semantics');
select is((select count(*)::integer from public.quote_request_quotation_approvals),3,
  'existing generic immutable approval authority stores the results');
select ok(not exists(
  select 1 from public.quote_request_quotation_approvals approval
  join qf3a_fixtures fixture on fixture.generic_intake_id=approval.intake_id
  where fixture.label in ('start','groei','pro')
    and (approval.approval_version<>1
      or approval.approved_by<>'OPERATOR:'||pg_temp.qf3a_uuid('qf3a-owner-operator')::text
      or approval.payload_sha256<>public.quotation_approval_payload_sha256_v1(approval.approved_payload))
),'approval version, owner actor, and canonical payload hash are preserved');
select ok(not exists(
  select 1 from public.quote_request_quotation_approvals approval
  where (approval.approved_payload->'pricing_snapshot'->>'snapshot_contract_version')::integer<>4
),'all approvals preserve pricing snapshot contract v4');
select is(
  (select jsonb_agg(jsonb_build_array(
    approval.approved_payload#>'{line_items,0,unit_price_minor}',
    approval.approved_payload#>'{line_items,1,unit_price_minor}'
  ) order by fixture.label)
   from public.quote_request_quotation_approvals approval
   join qf3a_fixtures fixture on fixture.generic_intake_id=approval.intake_id),
  '[[570000, 29900], [750000, 44900], [285000, 17500]]'::jsonb,
  'GROEI, PRO, and START setup plus recurring prices remain exact'
);
select ok(not exists(
  select 1 from public.quote_request_quotation_approvals approval,
    lateral jsonb_array_elements(approval.approved_payload->'line_items') line
  where line->>'cost_type' not in ('ONE_TIME','RECURRING')
),'ONE_TIME and RECURRING line semantics are preserved');
select lives_ok(
  $$select public.assert_quotation_business_draft_vat_binding_v1(
      promotion.business_draft_id,true
    )
    from public.quote_request_quotation_business_approval_promotions promotion$$,
  'every promoted SDF approval retains a current VAT context binding'
);
select ok(not exists(
  select 1 from public.quote_request_quotation_approvals approval
  join qf3a_fixtures fixture on fixture.generic_intake_id=approval.intake_id
  join public.sdf_quotation_commercial_decisions decision
    on decision.decision_id=fixture.decision_id
  where approval.approved_payload->'payment_schedule'<>decision.payment_schedule
),'approved payment schedules remain exact commercial-decision authorities');
select ok(not exists(
  select 1 from public.quote_request_quotation_approvals approval
  join qf3a_fixtures fixture on fixture.generic_intake_id=approval.intake_id
  join public.sdf_quotation_commercial_decisions decision
    on decision.decision_id=fixture.decision_id
  join public.quotation_terms_authorities terms
    on terms.terms_authority_id=decision.terms_authority_id
  where approval.approved_payload#>>'{legal_references,terms_sha256}'<>rtrim(terms.terms_sha256)
),'approved legal references retain the approved terms authority');
select ok(not exists(
  select 1 from public.quote_request_quotation_approvals approval
  where not public.is_current_pricing_snapshot_integrity_valid(
    approval.intake_id,approval.pricing_snapshot_id,
    approval.approved_payload->'pricing_snapshot'
  ) or not public.is_valid_quotation_approval_payload_v1(approval.approved_payload,true)
),'all resulting approvals pass existing payload and pricing validators');
select is((select count(*)::integer from public.quote_request_quotation_approval_operations),3,
  'existing approval operation ledger records every SDF CREATE');
select is((select count(*)::integer from public.quote_request_quotation_business_approval_promotions),3,
  'existing promotion authority binds every business draft once');

select set_config(
  'request.jwt.claim.sub',pg_temp.qf3a_uuid('qf3a-admin-auth')::text,true
);
select throws_ok(format(
  $sql$select public.promote_sdf_quotation_business_draft_to_approval_v1(%L,1,%L,%L,%L::jsonb)$sql$,
  (select business_draft_id from qf3a_fixtures where label='cross'),
  pg_temp.qf3a_uuid('qf3a-non-owner-key'),
  pg_temp.qf3a_uuid('qf3a-cross-approval'),
  pg_temp.qf3a_proof('cross')::text
),'42501','OWNER_REQUIRED','non-owner operator is rejected');
select set_config(
  'request.jwt.claim.sub',pg_temp.qf3a_uuid('qf3a-owner-auth')::text,true
);
select throws_ok(format(
  $sql$select public.promote_sdf_quotation_business_draft_to_approval_v1(%L,1,%L,%L,'{}'::jsonb)$sql$,
  pg_temp.qf3a_uuid('qf3a-missing-business'),
  pg_temp.qf3a_uuid('qf3a-missing-key'),
  pg_temp.qf3a_uuid('qf3a-missing-approval')
),'P0001','SDF_BUSINESS_DRAFT_NOT_FOUND','unknown business draft is rejected');
select throws_ok(format(
  $sql$select public.promote_sdf_quotation_business_draft_to_approval_v1(%L,2,%L,%L,%L::jsonb)$sql$,
  (select business_draft_id from qf3a_fixtures where label='cross'),
  pg_temp.qf3a_uuid('qf3a-stale-revision-key'),
  pg_temp.qf3a_uuid('qf3a-cross-approval'),
  pg_temp.qf3a_proof('cross')::text
),'P0001','STALE_BUSINESS_REVISION','stale business revision is rejected');

alter table public.sdf_quotation_business_draft_adapters disable trigger user;
update public.sdf_quotation_business_draft_adapters set pricing_authority_sha256=repeat('1',64)
where business_draft_id=(select business_draft_id from qf3a_fixtures where label='stale-price');
update public.sdf_quotation_business_draft_adapters set document_evidence_sha256=repeat('2',64)
where business_draft_id=(select business_draft_id from qf3a_fixtures where label='stale-doc');
update public.sdf_quotation_business_draft_adapters set decision_sha256=repeat('3',64)
where business_draft_id=(select business_draft_id from qf3a_fixtures where label='stale-decision');
update public.sdf_quotation_business_draft_adapters set quote_request_id=(
  select quote_request_id from qf3a_fixtures where label='cross-target'
) where business_draft_id=(select business_draft_id from qf3a_fixtures where label='cross');
alter table public.sdf_quotation_business_draft_adapters enable trigger user;

select throws_ok(format(
  $sql$select public.promote_sdf_quotation_business_draft_to_approval_v1(%L,1,%L,%L,%L::jsonb)$sql$,
  (select business_draft_id from qf3a_fixtures where label='stale-price'),
  pg_temp.qf3a_uuid('qf3a-stale-price-approval-key'),
  pg_temp.qf3a_uuid('qf3a-stale-price-approval'),
  pg_temp.qf3a_proof('stale-price')::text
),'55000','SDF_PRICING_AUTHORITY_MISMATCH','stale pricing lineage is rejected');
select throws_ok(format(
  $sql$select public.promote_sdf_quotation_business_draft_to_approval_v1(%L,1,%L,%L,%L::jsonb)$sql$,
  (select business_draft_id from qf3a_fixtures where label='stale-doc'),
  pg_temp.qf3a_uuid('qf3a-stale-doc-approval-key'),
  pg_temp.qf3a_uuid('qf3a-stale-doc-approval'),
  pg_temp.qf3a_proof('stale-doc')::text
),'55000','SDF_DOCUMENT_EVIDENCE_MISMATCH','stale document evidence is rejected');
select throws_ok(format(
  $sql$select public.promote_sdf_quotation_business_draft_to_approval_v1(%L,1,%L,%L,%L::jsonb)$sql$,
  (select business_draft_id from qf3a_fixtures where label='stale-decision'),
  pg_temp.qf3a_uuid('qf3a-stale-decision-approval-key'),
  pg_temp.qf3a_uuid('qf3a-stale-decision-approval'),
  pg_temp.qf3a_proof('stale-decision')::text
),'55000','SDF_COMMERCIAL_DECISION_INTEGRITY_MISMATCH','stale decision lineage is rejected');
select throws_ok(format(
  $sql$select public.promote_sdf_quotation_business_draft_to_approval_v1(%L,1,%L,%L,%L::jsonb)$sql$,
  (select business_draft_id from qf3a_fixtures where label='cross'),
  pg_temp.qf3a_uuid('qf3a-cross-approval-key'),
  pg_temp.qf3a_uuid('qf3a-cross-approval'),
  pg_temp.qf3a_proof('cross')::text
),'42501','SDF_APPROVAL_CROSS_DOSSIER','cross-dossier adapter lineage is rejected');

select is(
  public.promote_sdf_quotation_business_draft_to_approval_v1(
    (select business_draft_id from qf3a_fixtures where label='start'),1,
    pg_temp.qf3a_uuid('qf3a-start-approval-key'),
    pg_temp.qf3a_uuid('qf3a-start-approval'),pg_temp.qf3a_proof('start')
  )->>'was_created','false','exact retry replays the existing SDF approval'
);
select is((select count(*)::integer from public.quote_request_quotation_approvals),3,
  'exact replay creates no duplicate approval');
select throws_ok(format(
  $sql$select public.promote_sdf_quotation_business_draft_to_approval_v1(%L,1,%L,%L,%L::jsonb)$sql$,
  (select business_draft_id from qf3a_fixtures where label='groei'),
  pg_temp.qf3a_uuid('qf3a-start-approval-key'),
  pg_temp.qf3a_uuid('qf3a-groei-approval'),
  pg_temp.qf3a_proof('groei')::text
),'P0001','IDEMPOTENCY_CONFLICT','same key with changed SDF lineage conflicts');
select is(
  (select count(*) from public.quote_request_quotation_issuances),
  (select issuance_count from qf3a_baseline),
  'QF-3A creates no issuance'
);
select is(
  (select count(*) from public.quote_request_quotation_email_orchestrations),
  (select mail_count from qf3a_baseline),
  'QF-3A creates no delivery or mail orchestration'
);
select is((select count(*)::integer from public.quote_request_quotation_approval_integrity),3,
  'existing immutable approval integrity authority stores every proof');
select throws_ok(
  $$update public.quote_request_quotation_approvals set approved_by='tampered'$$,
  '55000','QUOTATION_APPROVAL_IMMUTABLE',
  'resulting SDF approvals remain immutable'
);

select * from finish();
rollback;