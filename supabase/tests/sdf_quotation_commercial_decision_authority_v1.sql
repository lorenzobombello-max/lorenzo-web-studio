begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('public', 'sdf_quotation_commercial_decisions', 'QF-2A commercial decision authority exists');
select has_function(
  'public', 'authorize_sdf_quotation_commercial_decision_v1',
  array['uuid','uuid','uuid','uuid','jsonb','uuid'],
  'QF-2A owner command exists'
);
select has_function(
  'public', 'is_sdf_vat_context_binding_valid_v1', array['uuid','jsonb'],
  'QF-2A VAT resolver equality validator exists'
);
select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class where oid = 'public.sdf_quotation_commercial_decisions'::regclass),
  'commercial decisions have forced RLS'
);
select ok(
  not has_table_privilege('anon', 'public.sdf_quotation_commercial_decisions', 'select')
  and not has_table_privilege('authenticated', 'public.sdf_quotation_commercial_decisions', 'select')
  and not has_table_privilege('service_role', 'public.sdf_quotation_commercial_decisions', 'insert'),
  'runtime roles cannot bypass the decision command'
);

create function pg_temp.fixture_uuid(p_value text)
returns uuid language sql immutable set search_path=pg_catalog as $$
  select (substr(md5(p_value),1,8)||'-'||substr(md5(p_value),9,4)||'-4'||substr(md5(p_value),14,3)||'-8'||substr(md5(p_value),18,3)||'-'||substr(md5(p_value),21,12))::uuid
$$;

create function pg_temp.sdf_v3_payload(
  p_direction text,
  p_flows integer,
  p_document_types integer,
  p_pages_per_month integer,
  p_users integer
)
returns jsonb language sql immutable set search_path=pg_catalog as $$
  with document_types(value,position) as (
    select *
    from unnest(array[
      'quotation','invoice','order_confirmation','work_order','delivery_note',
      'contract','customer_document','supplier_document',
      'internal_administrative_document','multiple_document_types'
    ]) with ordinality
    limit p_document_types
  )
  select jsonb_build_object(
    'documentPurpose',jsonb_build_object(
      'categories',(select jsonb_agg(value order by position) from document_types)
    ),
    'workflowCapabilities',jsonb_build_array('receive'),
    'businessRequirements',jsonb_build_object(
      'currentWorkflow','Synthetic current workflow',
      'desiredWorkflow','Synthetic controlled workflow',
      'volumeBand','50_to_249',
      'frequency','monthly',
      'relevantDocumentTypes',jsonb_build_array('Synthetic documents'),
      'rolesUsers',jsonb_build_array('Synthetic users')
    ),
    'sampleDocumentMetadata',jsonb_build_object(
      'available',false,'requestedByLws',false,'uploadRequiredLater',false
    ),
    'commercialQualification',jsonb_build_object(
      'packageDirection',p_direction,
      'customComplexity',case when p_direction='maatwerk' then 'Synthetic complexity' else '' end,
      'documentVolumes',(
        select jsonb_agg(jsonb_build_object(
          'documentType',value,
          'documentCount',case when position=1 then p_pages_per_month-p_document_types+1 else 1 end,
          'period','monthly','averagePagesPerDocument',1
        ) order by position)
        from document_types
      ),
      'flowCount',p_flows,
      'userCount',p_users
    )
  )
$$;

create function pg_temp.schedule(p_percentage numeric default 100, p_amount_minor bigint default null)
returns jsonb language sql immutable set search_path=pg_catalog as $$
  select jsonb_build_object('milestones', jsonb_build_array(jsonb_build_object(
    'sequence',1,
    'label','Synthetic implementation payment',
    'percentage',case when p_amount_minor is null then p_percentage else null end,
    'amount_minor',p_amount_minor,
    'trigger','invoice',
    'due_terms_days',30,
    'recurring_cycle',null
  )))
$$;

create temporary table qf2a_fixtures (
  label text primary key,
  quote_request_id uuid not null,
  intake_id uuid not null,
  uploaded_file_id uuid not null,
  direction text not null,
  flows integer not null,
  document_types integer not null,
  pages_per_month integer not null,
  users integer not null,
  preparation_authority_id uuid,
  expected_package text not null,
  expected_setup bigint,
  expected_recurring bigint
);

insert into qf2a_fixtures values
  ('start', pg_temp.fixture_uuid('qf2a-start-request'), pg_temp.fixture_uuid('qf2a-start-intake'), pg_temp.fixture_uuid('qf2a-start-file'), 'pro', 1, 2, 500, 3, null, 'start', 285000, 17500),
  ('groei', pg_temp.fixture_uuid('qf2a-groei-request'), pg_temp.fixture_uuid('qf2a-groei-intake'), pg_temp.fixture_uuid('qf2a-groei-file'), 'start', 3, 5, 2500, 10, null, 'groei', 570000, 29900),
  ('pro', pg_temp.fixture_uuid('qf2a-pro-request'), pg_temp.fixture_uuid('qf2a-pro-intake'), pg_temp.fixture_uuid('qf2a-pro-file'), 'start', 6, 10, 7500, 25, null, 'pro', 750000, 44900),
  ('maatwerk', pg_temp.fixture_uuid('qf2a-maatwerk-request'), pg_temp.fixture_uuid('qf2a-maatwerk-intake'), pg_temp.fixture_uuid('qf2a-maatwerk-file'), 'pro', 7, 10, 7500, 25, null, 'maatwerk', null, null),
  ('cross', pg_temp.fixture_uuid('qf2a-cross-request'), pg_temp.fixture_uuid('qf2a-cross-intake'), pg_temp.fixture_uuid('qf2a-cross-file'), 'start', 1, 2, 500, 3, null, 'start', 285000, 17500),
  ('missing-context', pg_temp.fixture_uuid('qf2a-missing-context-request'), pg_temp.fixture_uuid('qf2a-missing-context-intake'), pg_temp.fixture_uuid('qf2a-missing-context-file'), 'start', 1, 2, 500, 3, null, 'start', 285000, 17500);

insert into auth.users(id,email) values
  (pg_temp.fixture_uuid('qf2a-owner-auth'), 'qf2a-owner@example.test'),
  (pg_temp.fixture_uuid('qf2a-operator-auth'), 'qf2a-operator@example.test');
insert into public.commercial_operators(operator_id,auth_user_id,display_name,role,status) values
  (pg_temp.fixture_uuid('qf2a-owner-operator'),pg_temp.fixture_uuid('qf2a-owner-auth'),'QF-2A Synthetic Owner','owner','ACTIVE'),
  (pg_temp.fixture_uuid('qf2a-non-owner-operator'),pg_temp.fixture_uuid('qf2a-operator-auth'),'QF-2A Synthetic Operator','operator','ACTIVE');

insert into public.quote_requests(
  id,application_reference,record_classification,request_kind,sdf_package,
  name,email,description,privacy_consent,status,customer_type,billing_country
)
select quote_request_id,
  'LWS-AAN-2099-' || (9500 + row_number() over (order by label))::text,
  'production','slimme_documentenflow','start',
  'QF-2A ' || label,'qf2a-' || label || '@example.test','Synthetic QF-2A fixture.',true,'approved',null,'BE'
from qf2a_fixtures;

insert into public.sdf_projects(project_id,quote_request_id)
select pg_temp.fixture_uuid('qf2a-' || label || '-project'), quote_request_id
from qf2a_fixtures;

insert into public.sdf_qualification_intakes(
  intake_id,quote_request_id,status,taxonomy_version,customer_capability_digest,
  customer_capability_encrypted,customer_capability_expires_at,draft_answers,
  draft_revision,latest_submission_sequence
)
select intake_id,quote_request_id,'qualification_complete','sdf_qualification_intake/3.0.0',
  encode(extensions.digest(convert_to('qf2a-' || label,'UTF8'),'sha256'),'hex'),
  'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  clock_timestamp()+interval '1 day',
  pg_temp.sdf_v3_payload(direction,flows,document_types,pages_per_month,users),1,1
from qf2a_fixtures;

insert into public.sdf_qualification_intake_submissions(
  submission_id,intake_id,submission_sequence,answers,taxonomy_version,
  payload_sha256,confirmation_version,confirmation_sha256
)
select pg_temp.fixture_uuid('qf2a-' || fixture.label || '-submission'),intake.intake_id,1,
  intake.draft_answers,intake.taxonomy_version,
  encode(extensions.digest(convert_to(intake.draft_answers::text,'UTF8'),'sha256'),'hex'),
  'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1',repeat('a',64)
from qf2a_fixtures fixture
join public.sdf_qualification_intakes intake on intake.intake_id=fixture.intake_id;

insert into public.sdf_qualification_intake_events(
  event_id,intake_id,event_kind,from_status,to_status,actor_class,submission_sequence
)
select pg_temp.fixture_uuid('qf2a-' || label || '-completion'),intake_id,
  'QUALIFICATION_COMPLETE','under_review','qualification_complete','system',1
from qf2a_fixtures;

insert into public.customer_requests(
  request_id,request_reference,quote_request_id,customer_id,project_id,source,
  request_type,title,description,status,priority,submitted_at,submitter_type
)
select pg_temp.fixture_uuid('qf2a-' || label || '-customer-request'),
  'LWS-VRZ-2099-' || (9500 + row_number() over (order by label))::text,
  quote_request_id,null,null,'OPERATOR','FILE_DELIVERY','QF-2A synthetic evidence',
  'Synthetic evidence fixture.','NEW','NORMAL',clock_timestamp(),'OPERATOR'
from qf2a_fixtures;

insert into public.customer_request_upload_requests(
  upload_request_id,customer_request_id,token_digest,status,expires_at,created_at,
  created_by_operator_id,completed_at
)
select pg_temp.fixture_uuid('qf2a-' || label || '-upload'),
  pg_temp.fixture_uuid('qf2a-' || label || '-customer-request'),
  encode(extensions.digest(convert_to('qf2a-token-' || label,'UTF8'),'sha256'),'hex'),
  'COMPLETED',clock_timestamp()+interval '1 day',clock_timestamp(),
  pg_temp.fixture_uuid('qf2a-owner-operator'),clock_timestamp()
from qf2a_fixtures;

insert into public.customer_request_uploaded_files(
  uploaded_file_id,upload_request_id,customer_request_id,status,storage_object_path,
  original_file_name,file_extension,declared_content_type,declared_byte_count,
  observed_content_type,observed_byte_count,sha256,accepted_at
)
select uploaded_file_id,pg_temp.fixture_uuid('qf2a-' || label || '-upload'),
  pg_temp.fixture_uuid('qf2a-' || label || '-customer-request'),'ACCEPTED',
  'requests/' || pg_temp.fixture_uuid('qf2a-' || label || '-customer-request')::text
    || '/uploads/' || pg_temp.fixture_uuid('qf2a-' || label || '-upload')::text
    || '/files/' || uploaded_file_id::text || '.pdf',
  'qf2a-' || label || '.pdf','pdf','application/pdf',100,
  'application/pdf',100,
  encode(extensions.digest(convert_to('qf2a-file-' || label,'UTF8'),'sha256'),'hex'),
  clock_timestamp()
from qf2a_fixtures;

insert into public.document_inbox_items(
  id,sha256,storage_object_path,original_file_name,mime_type,byte_count,
  source_type,source_instance,external_id,created_by_operator_id
)
select pg_temp.fixture_uuid('qf2a-' || label || '-inbox'),
  encode(extensions.digest(convert_to('qf2a-file-' || label,'UTF8'),'sha256'),'hex'),
  'documents/' || encode(extensions.digest(convert_to('qf2a-file-' || label,'UTF8'),'sha256'),'hex') || '.pdf',
  'qf2a-' || label || '.pdf',
  'application/pdf',100,'CUSTOMER_REQUEST_UPLOAD',
  pg_temp.fixture_uuid('qf2a-' || label || '-customer-request')::text,
  uploaded_file_id::text,pg_temp.fixture_uuid('qf2a-owner-operator')
from qf2a_fixtures;

insert into public.document_inbox_customer_request_upload_sources(
  uploaded_file_id,customer_request_id,quote_request_id,document_inbox_item_id,
  promoted_by_operator_id
)
select uploaded_file_id,pg_temp.fixture_uuid('qf2a-' || label || '-customer-request'),
  quote_request_id,pg_temp.fixture_uuid('qf2a-' || label || '-inbox'),
  pg_temp.fixture_uuid('qf2a-owner-operator')
from qf2a_fixtures;

select set_config('request.jwt.claim.sub',pg_temp.fixture_uuid('qf2a-owner-auth')::text,true);

create temporary table qf2a_requirements as
select fixture.label, fixture.uploaded_file_id,
  (public.create_sdf_document_requirement_v1(fixture.quote_request_id,'invoice',1)->>'requirement_id')::uuid requirement_id
from qf2a_fixtures fixture;

select public.bind_sdf_document_requirement_evidence_v1(requirement_id,uploaded_file_id)
from qf2a_requirements;

update qf2a_fixtures fixture
set preparation_authority_id = (
  public.authorize_sdf_quotation_preparation_v1(
    fixture.quote_request_id,
    pg_temp.fixture_uuid('qf2a-' || fixture.label || '-preparation-key')
  )->>'authority_id'
)::uuid;

create temporary table qf2a_vat_fixture as
select vat_decision_authority_id approved_id
from public.quotation_vat_decision_authorities
where authority_family = 'LWS_OUTGOING_VAT' and status = 'APPROVED';
select is((select count(*)::integer from qf2a_vat_fixture),1,'fixture resolves the single approved LWS outgoing VAT authority');

insert into public.quotation_vat_transaction_classifications(
  classification_id,quote_request_id,context_sha256,classification_code,
  source_reference,source_sha256,classified_by,classified_at
)
select pg_temp.fixture_uuid('qf2a-' || label || '-vat-classification'),quote_request_id,
  public.quotation_vat_context_sha256_v1(quote_request_id),
  'SUPPORTED_BELGIAN_DOMESTIC_EXEMPT_TRANSACTION','TEST_ONLY:QF2A',repeat('e',64),
  'QF2A_TEST',clock_timestamp()
from qf2a_fixtures
where label <> 'missing-context';

insert into public.quotation_vat_turnover_snapshots(
  turnover_snapshot_id,vat_decision_authority_id,threshold_year,
  measurement_watermark,governed_turnover_minor,currency,state,
  source_reference,source_sha256,predecessor_snapshot_id,recorded_by,recorded_at
) values (
  pg_temp.fixture_uuid('qf2a-vat-turnover'),
  (select approved_id from qf2a_vat_fixture),2026,current_date,0,'EUR',
  'BELOW_OR_AT_THRESHOLD','TEST_ONLY:QF2A',repeat('f',64),null,'QF2A_TEST',clock_timestamp()
);

insert into public.quotation_terms_authorities(
  terms_authority_id,terms_id,terms_version,terms_sha256,source_path,status,
  effective_from,approved_by,approved_at,retired_by,retired_at,retirement_reason
) values
  (pg_temp.fixture_uuid('qf2a-terms-approved'),'QF2A_TERMS','1.0.0',repeat('b',64),'synthetic/qf2a-terms','APPROVED',current_date,'QF2A_TEST',clock_timestamp(),null,null,null),
  (pg_temp.fixture_uuid('qf2a-terms-approved-2'),'QF2A_TERMS_ALT','1.0.0',repeat('d',64),'synthetic/qf2a-terms-alt','APPROVED',current_date,'QF2A_TEST',clock_timestamp(),null,null,null),
  (pg_temp.fixture_uuid('qf2a-terms-retired'),'QF2A_RETIRED_TERMS','1.0.0',repeat('c',64),'synthetic/qf2a-retired-terms','RETIRED',current_date,'QF2A_TEST',clock_timestamp(),'QF2A_TEST',clock_timestamp(),'Synthetic retirement');

create temporary table qf2a_decision_results(label text primary key,result jsonb);
insert into qf2a_decision_results
select fixture.label,public.authorize_sdf_quotation_commercial_decision_v1(
  fixture.quote_request_id,fixture.preparation_authority_id,
  (select approved_id from qf2a_vat_fixture),pg_temp.fixture_uuid('qf2a-terms-approved'),
  pg_temp.schedule(),pg_temp.fixture_uuid('qf2a-' || fixture.label || '-decision-key')
)
from qf2a_fixtures fixture
where fixture.label in ('start','groei','pro');

select is((select count(*)::integer from qf2a_decision_results),3,'START, GROEI, and PRO decisions are created');
select is((select result->>'replayed' from qf2a_decision_results where label='start'),'false','START decision is newly created');
select is((select canonical_payload->>'implementation_amount_minor' from public.sdf_quotation_commercial_decisions where sdf_package='start'),'285000','START setup amount is server-derived');
select is((select canonical_payload->>'recurring_amount_minor' from public.sdf_quotation_commercial_decisions where sdf_package='start'),'17500','START recurring amount is server-derived');
select is((select jsonb_build_array(canonical_payload->>'implementation_amount_minor',canonical_payload->>'recurring_amount_minor') from public.sdf_quotation_commercial_decisions where sdf_package='groei'),'["570000", "29900"]'::jsonb,'GROEI amounts are server-derived');
select is((select jsonb_build_array(canonical_payload->>'implementation_amount_minor',canonical_payload->>'recurring_amount_minor') from public.sdf_quotation_commercial_decisions where sdf_package='pro'),'["750000", "44900"]'::jsonb,'PRO amounts are server-derived');
select is(
  (select vat_context_sha256::text from public.sdf_quotation_commercial_decisions where sdf_package='start'),
  public.quotation_vat_context_sha256_v1((select quote_request_id from qf2a_fixtures where label='start')),
  'commercial decision binds the current server VAT context hash'
);
select is(
  (select vat_classification_id from public.sdf_quotation_commercial_decisions where sdf_package='start'),
  pg_temp.fixture_uuid('qf2a-start-vat-classification'),
  'commercial decision binds the resolved transaction classification'
);
select is(
  (select vat_turnover_snapshot_id from public.sdf_quotation_commercial_decisions where sdf_package='start'),
  pg_temp.fixture_uuid('qf2a-vat-turnover'),
  'commercial decision binds the resolved turnover snapshot'
);
select ok(
  not public.is_sdf_vat_context_binding_valid_v1(
    pg_temp.fixture_uuid('qf2a-vat-mismatch'),
    public.resolve_quotation_vat_authority_v1(
      (select quote_request_id from qf2a_fixtures where label='start'), current_date
    )
  ),
  'resolver VAT authority mismatch is rejected'
);

alter table public.quote_request_intakes disable trigger trg_quote_request_intake_kind_guard;
insert into public.quote_request_intakes(
  id,quote_request_id,access_token_hash,access_token_expires_at,status,
  started_at,submitted_at,confirmation
)
select pg_temp.fixture_uuid('qf2b-' || fixture.label || '-generic-intake'),
  fixture.quote_request_id,
  encode(extensions.digest(convert_to('qf2b-' || fixture.label || '-token','UTF8'),'sha256'),'hex'),
  clock_timestamp()+interval '1 day','submitted',clock_timestamp(),clock_timestamp(),true
from qf2a_fixtures fixture
where fixture.label in ('start','groei','pro');
alter table public.quote_request_intakes enable trigger trg_quote_request_intake_kind_guard;

insert into public.quote_request_pricing_snapshots(
  id,intake_id,snapshot_contract_version,config_version,config_hash,
  normalized_evidence,calculation,package_advice,budget_evaluation,sdf_pricing
)
select pg_temp.fixture_uuid('qf2b-' || fixture.label || '-snapshot'),
  pg_temp.fixture_uuid('qf2b-' || fixture.label || '-generic-intake'),
  4,'2026-09-01-v4',rtrim(decision.pricing_authority_sha256),
  '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
  jsonb_build_object(
    'commercial_decision_id',decision.decision_id,
    'product_kind','sdf','package',decision.sdf_package,'currency','EUR',
    'implementation',jsonb_build_object(
      'amount_minor',decision.canonical_payload->'implementation_amount_minor',
      'price_mode','fixed'
    ),
    'recurring',jsonb_build_object(
      'amount_minor',decision.canonical_payload->'recurring_amount_minor',
      'interval','month','price_mode','fixed'
    ),
    'pricing_authority_sha256',rtrim(decision.pricing_authority_sha256),
    'submission_sha256',rtrim(decision.submission_sha256),
    'document_evidence_sha256',rtrim(decision.document_evidence_sha256)
  )
from qf2a_fixtures fixture
join public.sdf_quotation_commercial_decisions decision
  on decision.quote_request_id=fixture.quote_request_id
where fixture.label in ('start','groei','pro');

insert into public.quote_request_pricing_snapshot_integrity(
  snapshot_id,algorithm_version,key_id,mac
)
select pg_temp.fixture_uuid('qf2b-' || label || '-snapshot'),
  'hmac-sha256-v1','v1',repeat('9',64)
from qf2a_fixtures where label in ('start','groei','pro');

select is(
  (select count(*)::integer from public.quote_request_pricing_snapshots
   where snapshot_contract_version=4),3,
  'START, GROEI, and PRO create strict decision-bound v4 snapshot fixtures'
);
select ok(
  public.is_current_pricing_snapshot_integrity_valid(
    pg_temp.fixture_uuid('qf2b-start-generic-intake'),
    pg_temp.fixture_uuid('qf2b-start-snapshot'),
    jsonb_build_object(
      'snapshot_id',pg_temp.fixture_uuid('qf2b-start-snapshot'),
      'snapshot_contract_version',4,'integrity_algorithm_version','hmac-sha256-v1',
      'integrity_key_id','v1','integrity_mac',repeat('9',64)
    )
  ),
  'existing integrity boundary accepts a valid strict SDF v4 snapshot'
);
select ok(
  not public.is_strict_pricing_snapshot_v4(
    pg_temp.fixture_uuid('qf2b-groei-generic-intake'),4::smallint,
    '2026-09-01-v4',
    (select config_hash from public.quote_request_pricing_snapshots
     where id=pg_temp.fixture_uuid('qf2b-start-snapshot')),
    (select sdf_pricing from public.quote_request_pricing_snapshots
     where id=pg_temp.fixture_uuid('qf2b-start-snapshot'))
  ),
  'strict SDF snapshot rejects cross-dossier intake lineage'
);
select ok(
  not public.is_current_pricing_snapshot_integrity_valid(
    pg_temp.fixture_uuid('qf2b-start-generic-intake'),
    pg_temp.fixture_uuid('qf2b-start-snapshot'),
    jsonb_build_object(
      'snapshot_id',pg_temp.fixture_uuid('qf2b-start-snapshot'),
      'snapshot_contract_version',4,'integrity_algorithm_version','hmac-sha256-v1',
      'integrity_key_id','v1','integrity_mac',repeat('8',64)
    )
  ),
  'integrity boundary rejects a manipulated SDF v4 MAC'
);

select throws_ok(
  format($sql$select public.authorize_sdf_quotation_commercial_decision_v1(%L,%L,%L,%L,pg_temp.schedule(),%L)$sql$,
    (select quote_request_id from qf2a_fixtures where label='maatwerk'),
    (select preparation_authority_id from qf2a_fixtures where label='maatwerk'),
    (select approved_id from qf2a_vat_fixture),pg_temp.fixture_uuid('qf2a-terms-approved'),
    pg_temp.fixture_uuid('qf2a-maatwerk-decision-key')),
  '55000','SDF_MANUAL_PRICING_REQUIRED','MAATWERK fails closed before schedule creation'
);
select is((select count(*)::integer from public.sdf_quotation_commercial_decisions where quote_request_id=(select quote_request_id from qf2a_fixtures where label='maatwerk')),0,'MAATWERK creates no decision');

select throws_ok(
  format($sql$select public.authorize_sdf_quotation_commercial_decision_v1(%L,%L,%L,%L,pg_temp.schedule(),%L)$sql$,
    (select quote_request_id from qf2a_fixtures where label='cross'),
    (select preparation_authority_id from qf2a_fixtures where label='maatwerk'),
    (select approved_id from qf2a_vat_fixture),pg_temp.fixture_uuid('qf2a-terms-approved'),
    pg_temp.fixture_uuid('qf2a-cross-decision-key')),
  '42501','SDF_COMMERCIAL_DECISION_CROSS_DOSSIER','cross-dossier preparation binding is rejected'
);

select throws_ok(
  format($sql$select public.authorize_sdf_quotation_commercial_decision_v1(%L,%L,%L,%L,pg_temp.schedule(),%L)$sql$,
    (select quote_request_id from qf2a_fixtures where label='missing-context'),
    (select preparation_authority_id from qf2a_fixtures where label='missing-context'),
    (select approved_id from qf2a_vat_fixture),pg_temp.fixture_uuid('qf2a-terms-approved'),
    pg_temp.fixture_uuid('qf2a-missing-context-decision-key')),
  'P0001','QUOTATION_VAT_CONTEXT_REQUIRED','missing VAT transaction context is rejected'
);

select throws_ok(
  format($sql$select public.authorize_sdf_quotation_commercial_decision_v1(%L,%L,%L,%L,pg_temp.schedule(),%L)$sql$,
    (select quote_request_id from qf2a_fixtures where label='cross'),
    (select preparation_authority_id from qf2a_fixtures where label='cross'),
    pg_temp.fixture_uuid('qf2a-vat-missing'),pg_temp.fixture_uuid('qf2a-terms-approved'),
    pg_temp.fixture_uuid('qf2a-invalid-vat-key')),
  'P0001','QUOTATION_VAT_DECISION_NOT_APPROVED','unknown VAT authority is rejected'
);
select throws_ok(
  format($sql$select public.authorize_sdf_quotation_commercial_decision_v1(%L,%L,%L,%L,pg_temp.schedule(),%L)$sql$,
    (select quote_request_id from qf2a_fixtures where label='cross'),
    (select preparation_authority_id from qf2a_fixtures where label='cross'),
    (select approved_id from qf2a_vat_fixture),pg_temp.fixture_uuid('qf2a-terms-retired'),
    pg_temp.fixture_uuid('qf2a-retired-terms-key')),
  'P0001','QUOTATION_TERMS_NOT_APPROVED','retired terms authority is rejected'
);
select throws_ok(
  format($sql$select public.authorize_sdf_quotation_commercial_decision_v1(%L,%L,%L,%L,pg_temp.schedule(99),%L)$sql$,
    (select quote_request_id from qf2a_fixtures where label='cross'),
    (select preparation_authority_id from qf2a_fixtures where label='cross'),
    (select approved_id from qf2a_vat_fixture),pg_temp.fixture_uuid('qf2a-terms-approved'),
    pg_temp.fixture_uuid('qf2a-incomplete-schedule-key')),
  '22023','PAYMENT_SCHEDULE_INVALID','incomplete percentage schedule is rejected'
);
select throws_ok(
  format($sql$select public.authorize_sdf_quotation_commercial_decision_v1(%L,%L,%L,%L,pg_temp.schedule(null,1),%L)$sql$,
    (select quote_request_id from qf2a_fixtures where label='cross'),
    (select preparation_authority_id from qf2a_fixtures where label='cross'),
    (select approved_id from qf2a_vat_fixture),pg_temp.fixture_uuid('qf2a-terms-approved'),
    pg_temp.fixture_uuid('qf2a-mismatch-schedule-key')),
  '22023','PAYMENT_SCHEDULE_INVALID','amount schedule must equal authoritative setup amount'
);

select is(
  public.authorize_sdf_quotation_commercial_decision_v1(
    (select quote_request_id from qf2a_fixtures where label='start'),
    (select preparation_authority_id from qf2a_fixtures where label='start'),
    (select approved_id from qf2a_vat_fixture),pg_temp.fixture_uuid('qf2a-terms-approved'),
    pg_temp.schedule(),pg_temp.fixture_uuid('qf2a-start-decision-key')
  )->>'replayed','true','exact decision replay is idempotent'
);
select is((select count(*)::integer from public.sdf_quotation_commercial_decisions where sdf_package='start'),1,'exact replay creates no duplicate');
select throws_ok(
  format($sql$select public.authorize_sdf_quotation_commercial_decision_v1(%L,%L,%L,%L,pg_temp.schedule(),%L)$sql$,
    (select quote_request_id from qf2a_fixtures where label='start'),
    (select preparation_authority_id from qf2a_fixtures where label='start'),
    (select approved_id from qf2a_vat_fixture),pg_temp.fixture_uuid('qf2a-terms-approved-2'),
    pg_temp.fixture_uuid('qf2a-start-decision-key')),
  'P0001','IDEMPOTENCY_CONFLICT','same key with changed VAT decision conflicts'
);
select is(
  (select rtrim(decision_sha256) from public.sdf_quotation_commercial_decisions where sdf_package='start'),
  (select encode(extensions.digest(convert_to(canonical_payload::text,'UTF8'),'sha256'),'hex') from public.sdf_quotation_commercial_decisions where sdf_package='start'),
  'decision hash deterministically binds canonical payload'
);

alter table public.quotation_vat_decision_authorities disable trigger user;
update public.quotation_vat_decision_authorities
set status='RETIRED', retired_by='QF2A_TEST', retired_at=clock_timestamp(),
  retirement_reason='Synthetic rollback-only retirement'
where vat_decision_authority_id=(select approved_id from qf2a_vat_fixture);
alter table public.quotation_vat_decision_authorities enable trigger user;
select throws_ok(
  format($sql$select public.authorize_sdf_quotation_commercial_decision_v1(%L,%L,%L,%L,pg_temp.schedule(),%L)$sql$,
    (select quote_request_id from qf2a_fixtures where label='cross'),
    (select preparation_authority_id from qf2a_fixtures where label='cross'),
    (select approved_id from qf2a_vat_fixture),pg_temp.fixture_uuid('qf2a-terms-approved'),
    pg_temp.fixture_uuid('qf2a-retired-vat-key')),
  'P0001','QUOTATION_VAT_DECISION_NOT_APPROVED','retired VAT authority is rejected'
);

select set_config('request.jwt.claim.sub',pg_temp.fixture_uuid('qf2a-operator-auth')::text,true);
select throws_ok(
  format($sql$select public.authorize_sdf_quotation_commercial_decision_v1(%L,%L,%L,%L,pg_temp.schedule(),%L)$sql$,
    (select quote_request_id from qf2a_fixtures where label='cross'),
    (select preparation_authority_id from qf2a_fixtures where label='cross'),
    (select approved_id from qf2a_vat_fixture),pg_temp.fixture_uuid('qf2a-terms-approved'),
    pg_temp.fixture_uuid('qf2a-non-owner-key')),
  '42501','OWNER_REQUIRED','non-owner operator cannot authorize commercial decision'
);
select is((select count(*)::integer from public.sdf_quotation_commercial_decisions),3,'rejected attempts create no extra decisions');
select throws_ok(
  $$update public.sdf_quotation_commercial_decisions set decided_at=clock_timestamp()$$,
  '55000','SDF_COMMERCIAL_DECISION_IMMUTABLE','decision history cannot be rewritten'
);
select is((select count(*)::integer from public.quote_request_quotation_business_drafts),0,'QF-2A creates no business draft');
select is((select count(*)::integer from public.quote_request_quotation_approvals),0,'QF-2A creates no approval');
select is((select count(*)::integer from public.quote_request_quotation_issuances),0,'QF-2A creates no issuance');

select * from finish();
rollback;
