begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(38);

select has_table('public','quotation_template_authorities','quotation template authority exists');
select has_table('public','quotation_template_authority_events','immutable authority event log exists');
select has_function('public','register_quotation_template_candidate_v1',array['text','text','text','text','text','text','text','smallint','text','smallint','smallint','text','text','uuid'],'candidate registration RPC exists');
select has_function('public','approve_quotation_template_v1',array['uuid','text','text'],'approval RPC exists');
select has_function('public','retire_quotation_template_v1',array['uuid','text','text','text'],'retirement RPC exists');
select has_function('public','resolve_approved_quotation_template_v1',array['text','text','text','smallint','smallint','smallint'],'deterministic resolver exists');
select ok(not has_function_privilege('anon','public.approve_quotation_template_v1(uuid,text,text)','execute'),'anon cannot approve templates');
select ok(not has_function_privilege('authenticated','public.retire_quotation_template_v1(uuid,text,text,text)','execute'),'authenticated cannot retire templates');
select ok(has_function_privilege('service_role','public.approve_quotation_template_v1(uuid,text,text)','execute'),'service role can approve templates');
select ok(not has_table_privilege('service_role','public.quotation_template_authorities','insert'),'service role cannot insert authority directly');
select ok(not has_table_privilege('service_role','public.quotation_template_authorities','update'),'service role cannot update authority directly');
select ok(not has_table_privilege('service_role','public.quotation_template_authorities','delete'),'service role cannot delete authority directly');
select ok(not has_function_privilege('service_role','public.build_quotation_issue_payload_v1_unchecked_d3e4(uuid,jsonb,jsonb,text)','execute'),'service role cannot call unchecked ISSUE builder');
select ok(not has_function_privilege('service_role','public.commit_quotation_issuance_v2_unchecked_d3e3a(uuid,uuid,text,text,text,text,text,smallint,text,bigint,text,bigint,text,text)','execute'),'service role cannot call unchecked commit');

select is((select status from public.quotation_template_authorities where template_id='LWS_QUOTATION_NL_BE'),'APPROVED','verified technical master is approved');
select is((select rtrim(template_sha256) from public.quotation_template_authorities where template_id='LWS_QUOTATION_NL_BE'),'3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE','authority binds exact full master hash');
select is((select technical_master_filename from public.quotation_template_authorities where template_id='LWS_QUOTATION_NL_BE'),'assets/docs/quotation/LWS_QUOTATION_NL_BE_TECHNICAL_v1.docx','authority binds repository candidate filename');
select is((select template_id from public.resolve_approved_quotation_template_v1('QUOTATION','nl-BE','EUR',1::smallint,1::smallint,1::smallint)),'LWS_QUOTATION_NL_BE','resolver returns the single governed template');
select ok(public.is_approved_quotation_template_identity_v1(jsonb_build_object('template_id','LWS_QUOTATION_NL_BE','template_version','1.0.0-technical','template_sha256',lower('3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE'),'authority_status','APPROVED')),'exact approved identity validates');
select ok(not public.is_approved_quotation_template_identity_v1(jsonb_build_object('template_id','LWS_QUOTATION_NL_BE','template_version','1.0.0-technical','template_sha256',repeat('0',64),'authority_status','APPROVED')),'wrong template hash is rejected');
select ok(not public.is_approved_quotation_template_identity_v1(jsonb_build_object('template_id','LWS_QUOTATION_NL_BE','template_version','9.9.9','template_sha256',lower('3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE'),'authority_status','APPROVED')),'unknown template version is rejected');
select throws_ok($$select * from public.resolve_approved_quotation_template_v1('INVOICE','nl-BE','EUR',1::smallint,1::smallint,1::smallint)$$,'P0001','QUOTATION_TEMPLATE_NOT_APPROVED','wrong document type fails closed');
select throws_ok($$select * from public.resolve_approved_quotation_template_v1('QUOTATION','fr-BE','EUR',1::smallint,1::smallint,1::smallint)$$,'P0001','QUOTATION_TEMPLATE_NOT_APPROVED','wrong locale fails closed');
select throws_ok($$select * from public.resolve_approved_quotation_template_v1('QUOTATION','nl-BE','EUR',1::smallint,2::smallint,1::smallint)$$,'P0001','QUOTATION_TEMPLATE_NOT_APPROVED','unsupported generation contract fails closed');
select throws_ok($$update public.quotation_template_authorities set template_sha256=repeat('0',64)$$,'55000','QUOTATION_TEMPLATE_AUTHORITY_IMMUTABLE','approved hash cannot be mutated');
select throws_ok($$delete from public.quotation_template_authorities$$,'55000','QUOTATION_TEMPLATE_AUTHORITY_IMMUTABLE','authority cannot be deleted');
select throws_ok($$update public.quotation_template_authority_events set event_reference='changed'$$,'55000','QUOTATION_TEMPLATE_AUTHORITY_EVENT_IMMUTABLE','event history cannot be changed');
select is((
	select count(*)::integer
	from public.quotation_template_authority_events event
	join public.quotation_template_authorities authority
		on authority.id = event.template_authority_id
	where authority.request_kind = 'website'
),2,'Website registration and approval events are retained');
select is((select count(*)::integer from public.quotation_template_authority_events where evidence ?| array['capability_token','service_role_key','hmac_secret']),0,'event evidence contains no secrets');

select lives_ok($$select public.retire_quotation_template_v1((select id from public.quotation_template_authorities where template_id='LWS_QUOTATION_NL_BE'),'admin:test','Superseded in local test','D3E7_RETIRE_TEST')$$,'approved template can be retired through trusted RPC');
select throws_ok($$select * from public.resolve_approved_quotation_template_v1('QUOTATION','nl-BE','EUR',1::smallint,1::smallint,1::smallint)$$,'P0001','QUOTATION_TEMPLATE_NOT_APPROVED','retired template cannot resolve for new issue');
select is((select rtrim(template_sha256) from public.quotation_template_authorities where status='RETIRED'),'3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE','retirement preserves historical hash evidence');
select ok(not public.is_approved_quotation_template_identity_v1(jsonb_build_object('template_id','LWS_QUOTATION_NL_BE','template_version','1.0.0-technical','template_sha256',lower('3AD2FAAAA6A0A06E566F462E1C65C631006019C0D2D462333B8C693EB11154DE'),'authority_status','APPROVED')),'retired identity cannot be used for new issue');

select is(public.register_quotation_template_candidate_v1('LWS_QUOTATION_NL_BE','1.0.1-technical','QUOTATION','nl-BE','EUR',repeat('B',64),'assets/docs/quotation/test-only-v101.docx',1::smallint,'quotation-docx-v1',1::smallint,1::smallint,'admin:test','D3E7_REGISTER_V101',(select id from public.quotation_template_authorities where template_version='1.0.0-technical')) is not null,true,'new bytes require a new candidate version');
select is((select status from public.quotation_template_authorities where template_version='1.0.1-technical'),'CANDIDATE','new version starts as candidate');
select lives_ok($$select public.approve_quotation_template_v1((select id from public.quotation_template_authorities where template_version='1.0.1-technical'),'admin:test','D3E7_APPROVE_V101')$$,'new version may be approved after retirement');
select is((select template_version from public.resolve_approved_quotation_template_v1('QUOTATION','nl-BE','EUR',1::smallint,1::smallint,1::smallint)),'1.0.1-technical','resolver deterministically returns replacement approval');
select throws_ok($$select public.register_quotation_template_candidate_v1('LWS_QUOTATION_NL_BE','1.0.1-technical','QUOTATION','nl-BE','EUR',repeat('C',64),'assets/docs/quotation/conflict.docx',1::smallint,'quotation-docx-v1',1::smallint,1::smallint,'admin:test','D3E7_DUPLICATE',null)$$,'P0001','TEMPLATE_VERSION_CONFLICT','same version cannot be reused with different bytes');

select * from finish();
rollback;
