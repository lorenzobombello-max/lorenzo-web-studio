begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(128);

select has_table('public','sdf_qualification_intakes','dedicated SDF qualification intake exists');
select has_table('public','sdf_qualification_intake_submissions','immutable SDF submissions exist');
select has_table('public','sdf_qualification_intake_events','immutable SDF lifecycle events exist');
select has_table('public','sdf_quotation_preparation_authorities','quotation preparation authority exists');
select has_function('public','authorize_sdf_quotation_preparation_v1',array['uuid','uuid'],'quotation bridge command exists');
select hasnt_table('public','sdf_owner_work_acceptance_authorities','withdrawn Owner work-acceptance authority is removed');
select hasnt_function('public','accept_sdf_for_active_work_v1',array['uuid','uuid'],'withdrawn Owner work-acceptance command is removed');
select ok(
  not exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'quote_request_email_jobs'
      and indexdef ilike '%sdf_initial_confirmation%'
  ),
  'Website indexes contain no SDF initial authority'
);
select ok(
  not (pg_get_functiondef(
    'public.transition_quote_request_review(text,text)'::regprocedure
  ) ilike '%sdf_initial_confirmation_email_jobs%'),
  'Website review contains no SDF authority dependency'
);

insert into auth.users(id,email) values
  ('bd100000-0000-4000-8000-000000000001','sdf-owner@example.test'),
  ('bd100000-0000-4000-8000-000000000002','sdf-admin@example.test'),
  ('bd100000-0000-4000-8000-000000000003','sdf-inactive-owner@example.test');
insert into public.commercial_operators(auth_user_id,display_name,role,status) values
  ('bd100000-0000-4000-8000-000000000001','SDF Owner','owner','ACTIVE'),
  ('bd100000-0000-4000-8000-000000000002','SDF Admin','admin','ACTIVE'),
  ('bd100000-0000-4000-8000-000000000003','SDF Inactive Owner','owner','DISABLED');

select ok(
  has_function_privilege('authenticated','public.allow_sdf_qualification_intake_v1(uuid,text,text,uuid)','execute')
  and has_function_privilege('authenticated','public.reissue_sdf_qualification_intake_v1(uuid,text,text,uuid)','execute')
  and has_function_privilege('authenticated','public.inspect_sdf_qualification_intake_for_operator_v1(uuid)','execute')
  and has_function_privilege('authenticated','public.transition_sdf_qualification_intake_v1(uuid,text,text,uuid,text)','execute'),
  'authenticated caller can enter exactly the four guarded SDF Owner RPCs'
);
select ok(
  not has_function_privilege('anon','public.allow_sdf_qualification_intake_v1(uuid,text,text,uuid)','execute')
  and not has_function_privilege('anon','public.reissue_sdf_qualification_intake_v1(uuid,text,text,uuid)','execute')
  and not has_function_privilege('anon','public.inspect_sdf_qualification_intake_for_operator_v1(uuid)','execute')
  and not has_function_privilege('anon','public.transition_sdf_qualification_intake_v1(uuid,text,text,uuid,text)','execute'),
  'anon and PUBLIC-derived privileges cannot enter the four SDF Owner RPCs'
);
select ok(
  has_function_privilege('service_role','public.allow_sdf_qualification_intake_v1(uuid,text,text,uuid)','execute')
  and has_function_privilege('service_role','public.reissue_sdf_qualification_intake_v1(uuid,text,text,uuid)','execute')
  and has_function_privilege('service_role','public.inspect_sdf_qualification_intake_for_operator_v1(uuid)','execute')
  and has_function_privilege('service_role','public.transition_sdf_qualification_intake_v1(uuid,text,text,uuid,text)','execute'),
  'existing service-role execution remains available for internal flows with human authority context'
);
select ok(
  has_function_privilege('service_role','public.list_operator_pending_sdf_intakes_v1(uuid)','execute'),
  'service role can execute the SDF pending projection for the server-side operator readmodel'
);
select ok(
  not has_function_privilege('anon','public.list_operator_pending_sdf_intakes_v1(uuid)','execute'),
  'anon cannot execute the SDF pending projection'
);
select ok(
  not has_function_privilege('public','public.list_operator_pending_sdf_intakes_v1(uuid)','execute'),
  'PUBLIC cannot execute the SDF pending projection'
);
select ok(
  not has_function_privilege('authenticated','public.list_operator_pending_sdf_intakes_v1(uuid)','execute'),
  'authenticated callers use the guarded operator command route instead of direct projection access'
);
select lives_ok(
  $$select public.activate_application_intake_automation_v1('SDF-IMPLEMENTATION-V1-TEST')$$,
  'existing automation can be activated locally'
);
update lws_internal.application_intake_automation_config
set cutover_at=fixture.cutover_at,
    activated_at=fixture.cutover_at
from (select clock_timestamp()-interval '10 minutes' as cutover_at) fixture
where singleton;

insert into public.quote_requests(
  id,request_kind,sdf_package,created_at,name,company,email,description,
  privacy_consent,status,record_classification,approval_token_hash,approval_token_expires_at
) values (
  'bd200000-0000-4000-8000-000000000001','slimme_documentenflow','groei',
  clock_timestamp()-interval '3 minutes','SDF Klant','SDF Test BV','sdf@example.test',
  'SDF qualification fixture',true,'pending','production',repeat('9',64),clock_timestamp()+interval '1 day'
);

select set_config('request.jwt.claim.sub','bd100000-0000-4000-8000-000000000002',true);
select throws_ok($$select public.allow_sdf_qualification_intake_v1('bd200000-0000-4000-8000-000000000001',repeat('a',64),'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA','bd400000-0000-4000-8000-000000000020')$$,'42501','OWNER_REQUIRED','non-owner cannot allow SDF qualification');
select throws_ok($$select public.reissue_sdf_qualification_intake_v1('bd200000-0000-4000-8000-000000000001',repeat('a',64),'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA','bd400000-0000-4000-8000-000000000021')$$,'42501','OWNER_REQUIRED','non-owner cannot reissue SDF qualification');
select throws_ok($$select public.inspect_sdf_qualification_intake_for_operator_v1('bd200000-0000-4000-8000-000000000001')$$,'42501','OWNER_REQUIRED','non-owner cannot inspect SDF qualification');
select throws_ok($$select public.transition_sdf_qualification_intake_v1('bd200000-0000-4000-8000-000000000001','begin_review',null,'bd400000-0000-4000-8000-000000000022')$$,'42501','OWNER_REQUIRED','non-owner cannot transition SDF qualification');

select set_config('request.jwt.claim.sub','bd100000-0000-4000-8000-000000000003',true);
select throws_ok($$select public.allow_sdf_qualification_intake_v1('bd200000-0000-4000-8000-000000000001',repeat('a',64),'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA','bd400000-0000-4000-8000-000000000023')$$,'42501','OPERATOR_INACTIVE','inactive Owner cannot allow SDF qualification');
select throws_ok($$select public.reissue_sdf_qualification_intake_v1('bd200000-0000-4000-8000-000000000001',repeat('a',64),'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA','bd400000-0000-4000-8000-000000000024')$$,'42501','OPERATOR_INACTIVE','inactive Owner cannot reissue SDF qualification');
select throws_ok($$select public.inspect_sdf_qualification_intake_for_operator_v1('bd200000-0000-4000-8000-000000000001')$$,'42501','OPERATOR_INACTIVE','inactive Owner cannot inspect SDF qualification');
select throws_ok($$select public.transition_sdf_qualification_intake_v1('bd200000-0000-4000-8000-000000000001','begin_review',null,'bd400000-0000-4000-8000-000000000025')$$,'42501','OPERATOR_INACTIVE','inactive Owner cannot transition SDF qualification');

select is(
  (select count(*)::integer from lws_internal.application_intake_automation_work where quote_request_id='bd200000-0000-4000-8000-000000000001'),
  1,
  'SDF request enrolls exactly one persistent automation row'
);
select is(
  (select phase from lws_internal.application_intake_automation_work where quote_request_id='bd200000-0000-4000-8000-000000000001'),
  'SDF_CONFIRMATION',
  'SDF starts in confirmation phase'
);
select is(
  (select work.approval_due_at-request.created_at
   from lws_internal.application_intake_automation_work work
   join public.quote_requests request on request.id=work.quote_request_id
   where work.quote_request_id='bd200000-0000-4000-8000-000000000001'),
  interval '120 seconds',
  'confirmation due is persisted at request creation plus 120 seconds'
);

create temporary table sdf_claim as
select * from public.claim_application_intake_automation_work_v1('bd300000-0000-4000-8000-000000000001',5);
select is((select count(*)::integer from sdf_claim),1,'due SDF confirmation is claimed once');

create temporary table sdf_confirmation as
select * from public.prepare_sdf_initial_confirmation_v2(
  (select work_id from sdf_claim),(select claim_token from sdf_claim)
);
select is((select request_kind from sdf_confirmation),'slimme_documentenflow','confirmation authority is request-kind aware');
select is(
  (select status::text from public.sdf_initial_confirmation_email_jobs where job_id=(select job_id from sdf_confirmation)),
  'pending',
  'confirmation execution creates one pending isolated SDF mail job'
);
select is((select template_version from public.sdf_initial_confirmation_email_jobs where job_id=(select job_id from sdf_confirmation)),'SDF_REQUEST_RECEIVED_NL_BE_v1','confirmation job persists exact template authority');
update public.sdf_initial_confirmation_email_jobs set status='retry_wait' where job_id=(select job_id from sdf_confirmation);
select is((select template_version from public.sdf_initial_confirmation_email_jobs where job_id=(select job_id from sdf_confirmation)),'SDF_REQUEST_RECEIVED_NL_BE_v1','confirmation retry preserves exact template authority');
select is(
  (select count(*)::integer from public.quote_request_email_jobs where quote_request_id='bd200000-0000-4000-8000-000000000001'),
  0,
  'isolated SDF confirmation creates no Website mail-authority row'
);
select is(
  (select phase from lws_internal.application_intake_automation_work where quote_request_id='bd200000-0000-4000-8000-000000000001'),
  'SDF_CONFIRMATION',
  'mail job creation does not advance the phase'
);

select set_config('request.jwt.claim.sub','bd100000-0000-4000-8000-000000000001',true);
create temporary table allow_result as
select public.allow_sdf_qualification_intake_v1(
    'bd200000-0000-4000-8000-000000000001',repeat('a',64),
    'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'bd400000-0000-4000-8000-000000000001'
  ) as result;
select is((select result->>'replayed' from allow_result),'false','Owner can explicitly allow SDF qualification intake');
select is((select count(*)::integer from public.sdf_qualification_intakes),1,'Owner allow creates exactly one intake');
select is((select count(*)::integer from public.sdf_qualification_intake_email_jobs where kind='invitation'),1,'Owner allow creates exactly one invitation job');
select ok(
  has_function_privilege('service_role','public.resolve_sdf_support_reference_v1(uuid,uuid)','execute')
  and not has_function_privilege('anon','public.resolve_sdf_support_reference_v1(uuid,uuid)','execute')
  and not has_function_privilege('authenticated','public.resolve_sdf_support_reference_v1(uuid,uuid)','execute'),
  'only service role can resolve an SDF support reference for mail delivery'
);
select is(
  public.resolve_sdf_support_reference_v1('bd200000-0000-4000-8000-000000000001',null),
  (select support_reference from public.quote_requests where id='bd200000-0000-4000-8000-000000000001'),
  'mail authority resolves the canonical support reference by quote request'
);
select is(
  public.resolve_sdf_support_reference_v1(null,(select intake_id from public.sdf_qualification_intakes where quote_request_id='bd200000-0000-4000-8000-000000000001')),
  (select support_reference from public.quote_requests where id='bd200000-0000-4000-8000-000000000001'),
  'mail authority resolves the canonical support reference by intake'
);
select is(
  public.inspect_sdf_qualification_intake_v1(repeat('a',64))->>'support_reference',
  (select support_reference from public.quote_requests where id='bd200000-0000-4000-8000-000000000001'),
  'customer capability inspection exposes the canonical support reference'
);
select throws_ok(
  $$select public.resolve_sdf_support_reference_v1(null,null)$$,
  '22023','EXACTLY_ONE_SDF_IDENTIFIER_REQUIRED','mail authority requires exactly one identifier'
);
select is((select count(*)::integer from lws_internal.operator_pending_sdf_intakes_v1),1,'invited SDF intake is visible in pending projection');
select is((select count(*)::integer from lws_internal.operator_application_readmodel_v2 where request_kind='slimme_documentenflow'),0,'invited SDF intake is not active');
select is(
  public.list_operator_pending_sdf_intakes_v1('bd100000-0000-4000-8000-000000000001')->'items'->0->>'request_kind',
  'slimme_documentenflow',
  'service-side projection returns the canonical SDF pending DTO for an active Owner actor'
);
select is(
  public.list_operator_pending_sdf_intakes_v1('bd100000-0000-4000-8000-000000000001')->'items'->0->>'support_reference',
  (select support_reference from public.quote_requests where id='bd200000-0000-4000-8000-000000000001'),
  'SDF pending operator projection exposes the canonical public dossier reference'
);
select throws_ok(
  $$select public.list_operator_pending_sdf_intakes_v1('bd100000-0000-4000-8000-000000000099')$$,
  '42501','UNKNOWN_OPERATOR','non-operator cannot read the SDF pending projection'
);
select throws_ok(
  $$select public.list_operator_pending_sdf_intakes_v1('bd100000-0000-4000-8000-000000000003')$$,
  '42501','OPERATOR_DISABLED','disabled Owner cannot read the SDF pending projection'
);
select lives_ok(
  $$select public.inspect_sdf_qualification_intake_for_operator_v1('bd200000-0000-4000-8000-000000000001')$$,
  'authenticated Owner can inspect the SDF qualification intake'
);
select is(
  public.allow_sdf_qualification_intake_v1(
    'bd200000-0000-4000-8000-000000000001',repeat('c',64),
    'v1.CCCCCCCCCCCCCCCC.CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
    'bd400000-0000-4000-8000-000000000001'
  ),
  (select result from allow_result),
  'allow replay returns the immutable original result despite new capability material'
);
select is((select result_snapshot from public.sdf_qualification_intake_events where idempotency_key='bd400000-0000-4000-8000-000000000001'),(select result from allow_result),'allow result snapshot is persisted in immutable event authority');
insert into public.quote_requests(id,request_kind,sdf_package,created_at,name,email,description,privacy_consent,status,record_classification,approval_token_hash,approval_token_expires_at)
values('ce200000-0000-4000-8000-000000000002','slimme_documentenflow','start',clock_timestamp(),'Conflict fixture','conflict@example.test','Conflict fixture',true,'pending','production',repeat('8',64),clock_timestamp()+interval '1 day');
select throws_ok(
  $$select public.allow_sdf_qualification_intake_v1('ce200000-0000-4000-8000-000000000002',repeat('e',64),'v1.EEEEEEEEEEEEEEEE.EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE','bd400000-0000-4000-8000-000000000001')$$,
  'P0001','IDEMPOTENCY_CONFLICT','same allow key with a different canonical fingerprint fails closed'
);
select ok(public.consume_sdf_qualification_rate_limit_v1(repeat('f',64),'submit'),'first capability submit attempt concerned by rate limiting is allowed');
select throws_ok(
  $$select public.consume_sdf_qualification_rate_limit_v1('raw-secret','submit')$$,
  '22023','INVALID_SDF_RATE_LIMIT_REQUEST','raw capability material is rejected from durable rate-limit storage'
);
select is(
  (select count(*)::integer from public.claim_application_intake_automation_work_v1('bd300000-0000-4000-8000-000000000002',5)),
  0,
  'unsent confirmation blocks intake invitation claims'
);

update public.sdf_initial_confirmation_email_jobs
set next_attempt_at=now()-interval '1 second'
where job_id=(select job_id from sdf_confirmation);
create temporary table claimed_sdf_confirmation as
select * from public.claim_sdf_initial_confirmation_email_job_v1((select job_id from sdf_confirmation));
select public.complete_sdf_initial_confirmation_email_job_v1(
  (select job_id from claimed_sdf_confirmation),
  (select delivery_lease_token from claimed_sdf_confirmation),
  true,false,null,'test-message'
);
select is(
  (select status::text from public.sdf_initial_confirmation_email_jobs where job_id=(select job_id from sdf_confirmation)),
  'sent',
  'confirmation job is durably sent'
);
select isnt(
  (select confirmation_sent_at from public.quote_requests where id='bd200000-0000-4000-8000-000000000001'),
  null::timestamptz,
  'sent confirmation is projected onto the SDF request'
);
select is(
  (select count(*)::integer from lws_internal.application_intake_automation_work where quote_request_id='bd200000-0000-4000-8000-000000000001' and phase='SDF_INTAKE'),
  1,
  'durably sent confirmation opens exactly one SDF intake phase'
);
select is(
  (select intake_due_at-approved_at from lws_internal.application_intake_automation_work where quote_request_id='bd200000-0000-4000-8000-000000000001'),
  interval '120 seconds',
  'invitation due is confirmation sent time plus 120 seconds'
);
select isnt((select next_attempt_at from public.sdf_qualification_intake_email_jobs where kind='invitation'),'infinity'::timestamptz,'early Owner allow becomes finite after durable confirmation delivery');
select is(
  (select invitation.next_attempt_at-confirmation.sent_at from public.sdf_qualification_intake_email_jobs invitation cross join public.sdf_initial_confirmation_email_jobs confirmation where invitation.kind='invitation' and confirmation.job_id=(select job_id from sdf_confirmation)),
  interval '120 seconds',
  'early invitation uses canonical confirmation sent plus 120 seconds due'
);
update public.sdf_initial_confirmation_email_jobs set status='sent',sent_at=sent_at where job_id=(select job_id from sdf_confirmation);
select is((select count(*)::integer from public.sdf_qualification_intake_email_jobs where kind='invitation'),1,'duplicate confirmation trigger remains single-invitation safe');

select ok(lws_internal.sdf_payload_valid_v1(
  '{"documentPurpose":{"categories":["invoice"]},"workflowCapabilities":["receive","review"],"businessRequirements":{"currentWorkflow":"Handmatige ontvangst","desiredWorkflow":"Gecontroleerde digitale flow","volumeBand":"10_to_49","frequency":"weekly","relevantDocumentTypes":["Factuur"],"rolesUsers":["Boekhouding"]},"sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false}}'::jsonb,true
),'canonical frozen C4A payload is valid');
select isnt(lws_internal.sdf_payload_valid_v1(
  '{"documentPurpose":{"categories":["invoice"]},"workflowCapabilities":["receive"],"businessRequirements":{"currentWorkflow":"A","desiredWorkflow":"B","volumeBand":"10_to_49","frequency":"weekly","relevantDocumentTypes":["Factuur"]},"sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false}}'::jsonb,true
),true,'missing required nested key is rejected');
select isnt(lws_internal.sdf_payload_valid_v1(
  '{"documentPurpose":{"categories":["invoice"]},"workflowCapabilities":["receive"],"businessRequirements":{"currentWorkflow":"A","desiredWorkflow":"B","volumeBand":"10_to_49","frequency":"weekly","relevantDocumentTypes":["Factuur"],"rolesUsers":["Boekhouding"]},"sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false},"extra":true}'::jsonb,true
),true,'unknown top-level key is rejected');
select isnt(lws_internal.sdf_payload_valid_v1(
  '{"documentPurpose":{"categories":["invoice"],"unexpected":true},"workflowCapabilities":["receive"],"businessRequirements":{"currentWorkflow":"A","desiredWorkflow":"B","volumeBand":"10_to_49","frequency":"weekly","relevantDocumentTypes":["Factuur"],"rolesUsers":["Boekhouding"]},"sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false}}'::jsonb,true
),true,'unknown nested key is rejected');
select isnt(lws_internal.sdf_payload_valid_v1(
  jsonb_build_object('documentPurpose',jsonb_build_object('categories',jsonb_build_array('invoice')),'workflowCapabilities',jsonb_build_array('receive'),'businessRequirements',jsonb_build_object('currentWorkflow',repeat('x',4001),'desiredWorkflow','B','volumeBand','10_to_49','frequency','weekly','relevantDocumentTypes',jsonb_build_array('Factuur'),'rolesUsers',jsonb_build_array('Boekhouding')),'sampleDocumentMetadata',jsonb_build_object('available',false,'requestedByLws',false,'uploadRequiredLater',false)),true
),true,'oversized nested string is rejected');
select isnt(lws_internal.sdf_payload_valid_v1(
  jsonb_build_object('documentPurpose',jsonb_build_object('categories',jsonb_build_array('invoice')),'workflowCapabilities',jsonb_build_array('receive'),'businessRequirements',jsonb_build_object('currentWorkflow','A','desiredWorkflow','B','volumeBand','10_to_49','frequency','weekly','relevantDocumentTypes',to_jsonb(array_fill('Factuur'::text,array[21])),'rolesUsers',jsonb_build_array('Boekhouding')),'sampleDocumentMetadata',jsonb_build_object('available',false,'requestedByLws',false,'uploadRequiredLater',false)),true
),true,'oversized nested array is rejected');
select isnt(lws_internal.sdf_payload_valid_v1(
  '{"documentPurpose":{"categories":["invoice"]},"workflowCapabilities":["receive"],"businessRequirements":{"currentWorkflow":"A","desiredWorkflow":"B","volumeBand":"invalid","frequency":"weekly","relevantDocumentTypes":["Factuur"],"rolesUsers":["Boekhouding"]},"sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false}}'::jsonb,true
),true,'invalid nested enum is rejected');

update public.sdf_qualification_intake_email_jobs set next_attempt_at=clock_timestamp()-interval '1 second' where kind='invitation';
create temporary table claimed_old_invitation as select * from public.claim_next_sdf_qualification_email_job_v1();
select is((select count(*)::integer from claimed_old_invitation),1,'old invitation generation can be leased before reissue');
select throws_ok(
  $$select public.reissue_sdf_qualification_intake_v1(
    'bd200000-0000-4000-8000-000000000001',repeat('b',64),
    'v1.BBBBBBBBBBBBBBBB.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
    'bd400000-0000-4000-8000-000000000011'
  )$$,
  '55000','SDF_INVITATION_DELIVERY_IN_PROGRESS','reissue fails closed while the current invitation has an active processing lease'
);
select is((select status::text from public.sdf_qualification_intake_email_jobs where job_id=(select job_id from claimed_old_invitation)),'processing','failed reissue preserves the active delivery lease');
select is(public.validate_sdf_qualification_email_delivery_v1((select job_id from claimed_old_invitation),'ffffffff-ffff-4fff-bfff-ffffffffffff'),false,'spoofed lease owner cannot obtain delivery authority');
select is(public.complete_sdf_qualification_email_job_v1((select job_id from claimed_old_invitation),'ffffffff-ffff-4fff-bfff-ffffffffffff',true,false,null,'spoofed-provider-id'),null::jsonb,'spoofed lease owner cannot complete delivery');
select is(public.validate_sdf_qualification_email_delivery_v1((select job_id from claimed_old_invitation),(select delivery_lease_token from claimed_old_invitation)),true,'current worker retains delivery authority after conflicting reissue rolls back');
select is((select invitation_generation from public.sdf_qualification_intakes),1,'conflicting reissue cannot activate a new generation');
select is(public.complete_sdf_qualification_email_job_v1((select job_id from claimed_old_invitation),(select delivery_lease_token from claimed_old_invitation),true,false,null,'authorized-provider-id')->>'status','sent','authorized worker can complete the old generation');
create temporary table reissue_result as
select public.reissue_sdf_qualification_intake_v1(
  'bd200000-0000-4000-8000-000000000001',repeat('b',64),
  'v1.BBBBBBBBBBBBBBBB.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
  'bd400000-0000-4000-8000-000000000011'
) as result;
select is((select result->>'replayed' from reissue_result),'false','Owner can reissue after the prior delivery lease completes');
select is(public.validate_sdf_qualification_email_delivery_v1((select job_id from claimed_old_invitation),(select delivery_lease_token from claimed_old_invitation)),false,'completed old generation has no current delivery authority after reissue');
select is((select count(*)::integer from lws_internal.operator_pending_sdf_intakes_v1),1,'reissued intake projects exactly one pending row');
select is((select invitation_generation from public.sdf_qualification_intakes),2,'new invitation generation is canonical');
select is(
  public.reissue_sdf_qualification_intake_v1(
    'bd200000-0000-4000-8000-000000000001',repeat('d',64),
    'v1.DDDDDDDDDDDDDDDD.DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD',
    'bd400000-0000-4000-8000-000000000011'
  ),
  (select result from reissue_result),
  'reissue replay returns the immutable original result despite new capability material'
);
select is((select result_snapshot from public.sdf_qualification_intake_events where idempotency_key='bd400000-0000-4000-8000-000000000011'),(select result from reissue_result),'reissue result snapshot is persisted in immutable event authority');
select is(public.allow_sdf_qualification_intake_v1('bd200000-0000-4000-8000-000000000001',repeat('a',64),'v1.AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA','bd400000-0000-4000-8000-000000000001'),(select result from allow_result),'allow replay remains unchanged after later reissue mutates generation and expiry');

select lives_ok(
  $$select public.save_sdf_qualification_intake_draft_v1(
    repeat('b',64),0,
    '{"documentPurpose":{"categories":["invoice"]},"workflowCapabilities":["receive","review"],"businessRequirements":{"currentWorkflow":"Handmatige ontvangst","desiredWorkflow":"Gecontroleerde digitale flow","volumeBand":"10_to_49","frequency":"weekly","relevantDocumentTypes":["Factuur"],"rolesUsers":["Boekhouding"]},"sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false}}'::jsonb
  )$$,
  'customer can save a valid C4A draft'
);
select is((select count(*)::integer from lws_internal.operator_pending_sdf_intakes_v1),1,'in-progress SDF intake remains pending');
select is((select count(*)::integer from lws_internal.operator_application_readmodel_v2 where request_kind='slimme_documentenflow'),0,'in-progress SDF intake is not active');
select is(jsonb_array_length(public.list_operator_pending_sdf_intakes_v1('bd100000-0000-4000-8000-000000000001')->'items'),1,'pending transport accepts an in-progress SDF item');
select lives_ok(
  $$select public.submit_sdf_qualification_intake_v1(repeat('b',64),1,true,'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1',encode(extensions.digest(convert_to('Ik bevestig dat de ingevulde informatie naar best vermogen volledig en correct is. Ik begrijp dat deze kwalificatie geen offerte, prijsbevestiging of aanvaarding van een opdracht vormt.','UTF8'),'sha256'),'hex'),'bd400000-0000-4000-8000-000000000002')$$,
  'customer can submit a complete C4A payload'
);
select is((select status::text from public.sdf_qualification_intakes),'submitted','submit enters active review projection boundary');
select is((select count(*)::integer from lws_internal.operator_pending_sdf_intakes_v1),0,'submitted SDF intake leaves pending');
select is((select count(*)::integer from lws_internal.operator_application_readmodel_v2 where request_kind='slimme_documentenflow'),1,'submitted SDF intake enters active work automatically');
select is(jsonb_array_length(public.list_operator_pending_sdf_intakes_v1('bd100000-0000-4000-8000-000000000001')->'items'),0,'pending transport excludes a submitted SDF item');

select lives_ok(
  $$select public.transition_sdf_qualification_intake_v1('bd200000-0000-4000-8000-000000000001','begin_review',null,'bd400000-0000-4000-8000-000000000003')$$,
  'Owner begins review'
);
select is((select count(*)::integer from lws_internal.operator_pending_sdf_intakes_v1),0,'under-review SDF intake remains outside pending');
select is((select count(*)::integer from lws_internal.operator_application_readmodel_v2 where request_kind='slimme_documentenflow'),1,'under-review SDF intake remains active');
select throws_ok(
  $$select public.authorize_sdf_quotation_preparation_v1('bd200000-0000-4000-8000-000000000001','bd400000-0000-4000-8000-000000000004')$$,
  '55000','SDF_QUALIFICATION_COMPLETE_REQUIRED','quotation preparation is blocked before completion'
);
select lives_ok(
  $$select public.transition_sdf_qualification_intake_v1(
    'bd200000-0000-4000-8000-000000000001','request_more_information','Beschrijf de uitzonderingsroute.',
    'bd400000-0000-4000-8000-000000000005',null
  )$$,
  'Owner can request more information from the existing capability escrow'
);
select is((select status::text from public.sdf_qualification_intakes),'changes_requested','more-info blocks quotation eligibility');
select is((select count(*)::integer from lws_internal.operator_pending_sdf_intakes_v1),0,'changes-requested SDF intake remains outside pending');
select is((select count(*)::integer from lws_internal.operator_application_readmodel_v2 where request_kind='slimme_documentenflow'),1,'changes-requested SDF intake retains active review semantics');
select is((select count(*)::integer from public.sdf_qualification_intake_email_jobs where kind='more_information'),1,'more-info mail job is idempotently recorded');
select is(
  (select encrypted_capability from public.sdf_qualification_intake_email_jobs where kind='more_information'),
  (select customer_capability_encrypted from public.sdf_qualification_intakes),
  'more-info delivery reuses exactly the intake capability escrow'
);
update public.sdf_qualification_intake_email_jobs set status='sent',sent_at=clock_timestamp() where kind='invitation';
create temporary table claimed_more_information as select * from public.claim_next_sdf_qualification_email_job_v1();
select is((select kind from claimed_more_information),'more_information','next-email lease claims the due more-info job independently of automation work');

select lives_ok(
  $$select public.save_sdf_qualification_intake_draft_v1(
    repeat('b',64),1,
    '{"documentPurpose":{"categories":["invoice"]},"workflowCapabilities":["receive","review","approve"],"businessRequirements":{"currentWorkflow":"Handmatige ontvangst","desiredWorkflow":"Gecontroleerde digitale goedkeuring","volumeBand":"10_to_49","frequency":"weekly","relevantDocumentTypes":["Factuur"],"rolesUsers":["Boekhouding"]},"sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false}}'::jsonb
  )$$,
  'customer can revise after changes requested'
);
select lives_ok(
  $$select public.submit_sdf_qualification_intake_v1(repeat('b',64),2,true,'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1',encode(extensions.digest(convert_to('Ik bevestig dat de ingevulde informatie naar best vermogen volledig en correct is. Ik begrijp dat deze kwalificatie geen offerte, prijsbevestiging of aanvaarding van een opdracht vormt.','UTF8'),'sha256'),'hex'),'bd400000-0000-4000-8000-000000000006')$$,
  'customer can resubmit'
);
select is((select count(*)::integer from lws_internal.operator_pending_sdf_intakes_v1),0,'resubmitted SDF intake remains outside pending');
select is((select count(*)::integer from lws_internal.operator_application_readmodel_v2 where request_kind='slimme_documentenflow'),1,'resubmitted SDF intake remains active');
select lives_ok(
  $$select public.transition_sdf_qualification_intake_v1('bd200000-0000-4000-8000-000000000001','begin_review',null,'bd400000-0000-4000-8000-000000000007')$$,
  'Owner reviews the resubmission'
);

select set_config('request.jwt.claim.sub','bd100000-0000-4000-8000-000000000002',true);
select throws_ok(
  $$select public.transition_sdf_qualification_intake_v1('bd200000-0000-4000-8000-000000000001','mark_qualification_complete',null,'bd400000-0000-4000-8000-000000000008')$$,
  '42501','OWNER_REQUIRED','admin cannot mark qualification complete'
);
select set_config('request.jwt.claim.sub','bd100000-0000-4000-8000-000000000001',true);
select lives_ok(
  $$select public.transition_sdf_qualification_intake_v1('bd200000-0000-4000-8000-000000000001','mark_qualification_complete',null,'bd400000-0000-4000-8000-000000000008')$$,
  'Owner marks qualification complete'
);
select is((select count(*)::integer from lws_internal.operator_pending_sdf_intakes_v1),0,'qualification-complete SDF remains outside pending');
select is((select count(*)::integer from lws_internal.operator_application_readmodel_v2 where request_kind='slimme_documentenflow'),1,'qualification-complete SDF remains active');
select is(
  (public.inspect_sdf_qualification_intake_for_operator_v1('bd200000-0000-4000-8000-000000000001')->>'quotation_preparation_authorized')::boolean,
  false,
  'qualification inspect reports quotation preparation as not authorized before authority exists'
);
select is(
  jsonb_typeof(public.inspect_sdf_qualification_intake_for_operator_v1('bd200000-0000-4000-8000-000000000001')->'quotation_preparation_authorized'),
  'boolean',
  'quotation preparation authorization is an explicit JSON boolean'
);
select is(
  public.inspect_sdf_qualification_intake_for_operator_v1('bd200000-0000-4000-8000-000000000001')->>'status',
  'qualification_complete',
  'qualification inspect payload retains its canonical status'
);
select is(
  (select count(*)::integer from public.sdf_quotation_preparation_authorities),
  0,
  'qualification inspect performs no quotation preparation mutation'
);
select lives_ok(
  $$select public.authorize_sdf_quotation_preparation_v1('bd200000-0000-4000-8000-000000000001','bd400000-0000-4000-8000-000000000009')$$,
  'Owner authorizes quotation preparation'
);
select is((select count(*)::integer from public.sdf_quotations),1,'bridge atomically creates one quotation identity');
select is((select count(*)::integer from public.sdf_quotation_preparation_authorities),1,'bridge atomically creates one preparation authority');
select is(
  (public.inspect_sdf_qualification_intake_for_operator_v1('bd200000-0000-4000-8000-000000000001')->>'quotation_preparation_authorized')::boolean,
  true,
  'qualification inspect reports quotation preparation as authorized after authority exists'
);
select is(
  (public.authorize_sdf_quotation_preparation_v1('bd200000-0000-4000-8000-000000000001','bd400000-0000-4000-8000-000000000009')->>'replayed')::boolean,
  true,
  'exact quotation bridge replay is idempotent'
);
select throws_ok(
  $$select public.authorize_sdf_quotation_preparation_v1('bd200000-0000-4000-8000-000000000001','bd400000-0000-4000-8000-000000000010')$$,
  '55000','SDF_QUOTATION_PREPARATION_CONFLICT','second quotation command fails closed'
);
select is((select count(*)::integer from public.sdf_quotation_documents),0,'bridge creates no quotation document or send side effect');
select is((select count(*)::integer from public.sdf_projects),0,'bridge creates no project side effect');

select is((select count(*)::integer from lws_internal.operator_pending_sdf_intakes_v1),0,'quotation preparation does not change pending lifecycle membership');
select is((select count(*)::integer from lws_internal.operator_application_readmodel_v2 where request_kind='slimme_documentenflow'),1,'quotation preparation does not change active lifecycle membership');

select * from finish();
rollback;