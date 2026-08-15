begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(26);

select has_table('public','quotation_acceptance_terms_authorities','acceptance terms authority exists');
select has_table('public','quote_request_quotation_acceptances','immutable acceptance authority exists');
select has_table('public','quote_request_quotation_acceptance_operations','acceptance operation ledger exists');
select has_table('public','quote_request_quotation_acceptance_events','acceptance audit events exist');
select has_function('public','accept_quotation_v1',array['uuid','integer','text','text','text','text','text','text','text','boolean','uuid','text'],'trusted acceptance RPC exists');
select has_function('public','quotation_acceptance_payload_sha256_v1',array['jsonb'],'acceptance payload hash exists');
select ok(not has_function_privilege('anon','public.accept_quotation_v1(uuid,integer,text,text,text,text,text,text,text,boolean,uuid,text)','execute'),'anon cannot accept quotation');
select ok(not has_function_privilege('authenticated','public.accept_quotation_v1(uuid,integer,text,text,text,text,text,text,text,boolean,uuid,text)','execute'),'authenticated cannot accept quotation');
select ok(has_function_privilege('service_role','public.accept_quotation_v1(uuid,integer,text,text,text,text,text,text,text,boolean,uuid,text)','execute'),'service role can call trusted acceptance RPC');
select ok(not has_table_privilege('service_role','public.quote_request_quotation_acceptances','insert'),'service role cannot insert acceptance directly');
select ok(not has_table_privilege('service_role','public.quote_request_quotation_acceptances','update'),'service role cannot update acceptance directly');
select ok(not has_table_privilege('service_role','public.quote_request_quotation_acceptances','delete'),'service role cannot delete acceptance directly');
select is((select status from public.quotation_acceptance_terms_authorities where terms_id='LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT'),'APPROVED','technical acceptance terms are approved');
select is((select count(*)::integer from public.quotation_acceptance_terms_authorities),1,'exactly one terms version is seeded');
select is((select count(*)::integer from public.quote_request_quotation_acceptances),0,'migration creates no acceptance records');

create temporary table acceptance_payload_fixture as
select jsonb_build_object(
  'acceptance_contract_version',1,
  'issuance_id','d3e86000-0000-4000-8000-000000000001',
  'quotation_number','LWS-OFF-2099-0001',
  'quotation_version',1,
  'customer_identity_sha256',repeat('a',64),
  'generation_payload_sha256',repeat('b',64),
  'template',jsonb_build_object('template_id','LWS_QUOTATION_NL_BE','template_version','1.0.0-technical','template_sha256',repeat('c',64)),
  'docx',jsonb_build_object('sha256',repeat('d',64),'bytes',12345),
  'acceptance_terms',jsonb_build_object('terms_id','LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','terms_version','1.0.0-technical','terms_sha256',repeat('e',64)),
  'actor',jsonb_build_object('name','Test Acceptant','email','acceptant@example.test','organization','Test Customer','role','Bestuurder'),
  'authority_declaration',true,
  'accepted_at','2026-08-15T12:00:00.000000Z'
) as payload;

select is(length(public.quotation_acceptance_payload_sha256_v1(payload)),64,'acceptance hash is SHA-256') from acceptance_payload_fixture;
select is(public.quotation_acceptance_payload_sha256_v1(payload),public.quotation_acceptance_payload_sha256_v1(payload::text::jsonb),'acceptance hash is canonical and deterministic') from acceptance_payload_fixture;
select isnt(public.quotation_acceptance_payload_sha256_v1(payload),public.quotation_acceptance_payload_sha256_v1(jsonb_set(payload,'{actor,name}','"Other Actor"')),'actor change changes acceptance hash') from acceptance_payload_fixture;
select isnt(public.quotation_acceptance_payload_sha256_v1(payload),public.quotation_acceptance_payload_sha256_v1(jsonb_set(payload,'{quotation_version}','2')),'quotation version change changes acceptance hash') from acceptance_payload_fixture;
select throws_ok($$select public.quotation_acceptance_payload_sha256_v1(jsonb_set((select payload from acceptance_payload_fixture),'{accepted_at}','null'))$$,'22023','INVALID_QUOTATION_ACCEPTANCE_PAYLOAD_V1','missing trusted timestamp is rejected');
select throws_ok($$select * from public.accept_quotation_v1('00000000-0000-4000-8000-000000000001',1,repeat('a',64),'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical','Test Acceptant','acceptant@example.test',null,null,true,'d3e88000-0000-4000-8000-000000000001',repeat('f',64))$$,'P0001','ISSUANCE_NOT_FOUND','nonexistent issuance is rejected');
select throws_ok($$select * from public.accept_quotation_v1('00000000-0000-4000-8000-000000000001',1,repeat('a',64),'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical','', 'acceptant@example.test',null,null,true,'d3e88000-0000-4000-8000-000000000002',repeat('f',64))$$,'42501','UNAUTHORIZED','missing actor name is rejected');
select throws_ok($$select * from public.accept_quotation_v1('00000000-0000-4000-8000-000000000001',1,repeat('a',64),'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical','Test','bad-email',null,null,true,'d3e88000-0000-4000-8000-000000000003',repeat('f',64))$$,'42501','UNAUTHORIZED','malformed actor email is rejected');
select throws_ok($$select * from public.accept_quotation_v1('00000000-0000-4000-8000-000000000001',1,repeat('a',64),'LWS_QUOTATION_ACCEPTANCE_ACKNOWLEDGEMENT','1.0.0-technical','Test','acceptant@example.test',null,null,false,'d3e88000-0000-4000-8000-000000000004',repeat('f',64))$$,'42501','UNAUTHORIZED','missing authority declaration is rejected');
select hasnt_function('public','accept_quotation_v1',array['uuid','integer','text','text','text','text','text','text','text','boolean','uuid','text','timestamp with time zone'],'caller cannot supply authoritative accepted_at');
select is((select count(*)::integer from information_schema.tables where table_schema='public' and table_name like '%invoice%' and table_name like '%accept%'),0,'acceptance creates no invoice coupling');

select * from finish();
rollback;
