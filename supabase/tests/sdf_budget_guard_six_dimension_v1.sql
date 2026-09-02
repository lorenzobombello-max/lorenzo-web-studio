begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(53);

select has_function('lws_internal','evaluate_sdf_budget_guard_v2',array['bigint','bigint','bigint','bigint','text','boolean','text'],'canonical six-dimension evaluator exists');
select is((select provolatile::text from pg_proc where oid='lws_internal.evaluate_sdf_budget_guard_v2(bigint,bigint,bigint,bigint,text,boolean,text)'::regprocedure),'i','canonical evaluator is immutable');
select ok(not has_function_privilege('anon','lws_internal.evaluate_sdf_budget_guard_v2(bigint,bigint,bigint,bigint,text,boolean,text)','execute') and not has_function_privilege('authenticated','lws_internal.evaluate_sdf_budget_guard_v2(bigint,bigint,bigint,bigint,text,boolean,text)','execute') and not has_function_privilege('service_role','lws_internal.evaluate_sdf_budget_guard_v2(bigint,bigint,bigint,bigint,text,boolean,text)','execute'),'canonical evaluator remains private');

select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',false,'start')->>'minimum_package','start','START exact boundary selects START');
select is(lws_internal.evaluate_sdf_budget_guard_v2(2,2,500,3,'standard',false,'groei')->>'minimum_package','groei','two flows cross START to GROEI');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,3,500,3,'standard',false,'groei')->>'minimum_package','groei','three document types cross START to GROEI');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,501,3,'standard',false,'groei')->>'minimum_package','groei','501 pages cross START to GROEI');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,4,'standard',false,'groei')->>'minimum_package','groei','four users cross START to GROEI');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'expanded',false,'groei')->>'minimum_package','groei','expanded complexity crosses START to GROEI');

select is(lws_internal.evaluate_sdf_budget_guard_v2(3,5,2500,10,'expanded',false,'groei')->>'minimum_package','groei','GROEI exact boundary selects GROEI');
select is(lws_internal.evaluate_sdf_budget_guard_v2(4,5,2500,10,'expanded',false,'pro')->>'minimum_package','pro','four flows cross GROEI to PRO');
select is(lws_internal.evaluate_sdf_budget_guard_v2(3,6,2500,10,'expanded',false,'pro')->>'minimum_package','pro','six document types cross GROEI to PRO');
select is(lws_internal.evaluate_sdf_budget_guard_v2(3,5,2501,10,'expanded',false,'pro')->>'minimum_package','pro','2501 pages cross GROEI to PRO');
select is(lws_internal.evaluate_sdf_budget_guard_v2(3,5,2500,11,'expanded',false,'pro')->>'minimum_package','pro','eleven users cross GROEI to PRO');
select is(lws_internal.evaluate_sdf_budget_guard_v2(3,5,2500,10,'advanced',false,'pro')->>'minimum_package','pro','advanced complexity crosses GROEI to PRO');

select is(lws_internal.evaluate_sdf_budget_guard_v2(6,10,7500,25,'advanced',false,'pro')->>'minimum_package','pro','PRO exact boundary selects PRO');
select is(lws_internal.evaluate_sdf_budget_guard_v2(7,10,7500,25,'advanced',false,'maatwerk')->>'minimum_package','maatwerk','seven flows require MAATWERK');
select is(lws_internal.evaluate_sdf_budget_guard_v2(6,11,7500,25,'advanced',false,'maatwerk')->>'minimum_package','maatwerk','eleven document types require MAATWERK');
select is(lws_internal.evaluate_sdf_budget_guard_v2(6,10,7501,25,'advanced',false,'maatwerk')->>'minimum_package','maatwerk','7501 pages require MAATWERK');
select is(lws_internal.evaluate_sdf_budget_guard_v2(6,10,7500,26,'advanced',false,'maatwerk')->>'minimum_package','maatwerk','26 users require MAATWERK');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',true,'maatwerk')->>'minimum_package','maatwerk','exceptional scope requires MAATWERK');

select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,501,3,'standard',false,'groei')->>'minimum_package','groei','highest wins when only pages require GROEI');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,11,'standard',false,'pro')->>'minimum_package','pro','highest wins when only users require PRO');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'advanced',false,'pro')->>'minimum_package','pro','complexity advanced raises numeric START to PRO');
select is(lws_internal.evaluate_sdf_budget_guard_v2(6,10,7500,25,'standard',false,'pro')->>'minimum_package','pro','numeric PRO remains PRO with standard complexity');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',true,'maatwerk')->>'minimum_package','maatwerk','numeric START plus exceptional scope requires MAATWERK');
select is(lws_internal.evaluate_sdf_budget_guard_v2(6,10,7500,25,'standard',true,'maatwerk')->>'minimum_package','maatwerk','numeric PRO plus exceptional scope requires MAATWERK');
select is(lws_internal.evaluate_sdf_budget_guard_v2(7,2,500,3,'standard',false,'maatwerk')->>'minimum_package','maatwerk','one numeric dimension above PRO requires MAATWERK');
select is(lws_internal.evaluate_sdf_budget_guard_v2(3,6,500,10,'expanded',false,'pro')->>'minimum_package','pro','multiple differing dimensions resolve to the highest requirement');

select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',false,'start')->>'selected_package','start','minimum START allows START');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',false,'groei')->>'selected_package','groei','minimum START allows GROEI upgrade');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',false,'pro')->>'selected_package','pro','minimum START allows PRO upgrade');
select throws_ok($$select lws_internal.evaluate_sdf_budget_guard_v2(2,2,500,3,'standard',false,'start')$$,'23514','SDF_PACKAGE_DOWNGRADE_DENIED','minimum GROEI rejects START');
select is(lws_internal.evaluate_sdf_budget_guard_v2(2,2,500,3,'standard',false,'groei')->>'selected_package','groei','minimum GROEI allows GROEI');
select is(lws_internal.evaluate_sdf_budget_guard_v2(2,2,500,3,'standard',false,'pro')->>'selected_package','pro','minimum GROEI allows PRO upgrade');
select throws_ok($$select lws_internal.evaluate_sdf_budget_guard_v2(4,2,500,3,'standard',false,'groei')$$,'23514','SDF_PACKAGE_DOWNGRADE_DENIED','minimum PRO rejects GROEI');
select is(lws_internal.evaluate_sdf_budget_guard_v2(4,2,500,3,'standard',false,'pro')->>'selected_package','pro','minimum PRO allows PRO');
select throws_ok($$select lws_internal.evaluate_sdf_budget_guard_v2(7,2,500,3,'standard',false,'pro')$$,'23514','SDF_PACKAGE_DOWNGRADE_DENIED','MAATWERK requirement rejects PRO');
select is(lws_internal.evaluate_sdf_budget_guard_v2(7,2,500,3,'standard',false,'maatwerk')->>'selected_package','maatwerk','MAATWERK requirement allows MAATWERK only');

select throws_ok($$select lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,null,false,'start')$$,'22004','SDF_COMPLEXITY_LEVEL_REQUIRED','missing complexity fails closed');
select throws_ok($$select lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',null,'start')$$,'22004','SDF_EXCEPTIONAL_SCOPE_REQUIRED','missing exceptional scope fails closed');
select throws_ok($$select lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'inferred',false,'start')$$,'22023','INVALID_SDF_COMPLEXITY_LEVEL','non-canonical complexity fails closed');

select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',false,'start'),lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',false,'start'),'same authoritative facts produce the same canonical result');
select ok((lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',false,'start')->>'decision_fingerprint') ~ '^[0-9a-f]{64}$','canonical result has a SHA-256 decision fingerprint');
select isnt(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',false,'start')->>'decision_fingerprint',lws_internal.evaluate_sdf_budget_guard_v2(2,2,500,3,'standard',false,'groei')->>'decision_fingerprint','material numeric change changes decision fingerprint');
select isnt(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',false,'pro')->>'decision_fingerprint',lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'advanced',false,'pro')->>'decision_fingerprint','complexity change changes decision fingerprint');
select isnt(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',false,'maatwerk')->>'decision_fingerprint',lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',true,'maatwerk')->>'decision_fingerprint','exceptional-scope change changes decision fingerprint');

select is(jsonb_array_length(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',false,'start')->'reasons'),6,'canonical result has six deterministic dimension reasons');
select is(lws_internal.evaluate_sdf_budget_guard_v2(2,2,500,3,'standard',false,'groei')#>>'{dimensions,flows,reason}','FLOW_REQUIRES_GROEI','flow provenance identifies its required class');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,501,3,'standard',false,'groei')#>>'{dimensions,monthly_pages,applicable_threshold,max}', '2500','page provenance binds the applicable GROEI threshold');
select is(lws_internal.evaluate_sdf_budget_guard_v2(7,2,500,3,'standard',false,'maatwerk')#>>'{pricing,implementation,amount_minor}',null,'Budget Guard generates no MAATWERK implementation price');
select is(lws_internal.evaluate_sdf_budget_guard_v2(7,2,500,3,'standard',false,'maatwerk')#>>'{pricing,recurring,amount_minor}',null,'Budget Guard generates no MAATWERK recurring price');
select is(lws_internal.evaluate_sdf_budget_guard_v2(1,2,500,3,'standard',false,'start')->'scope_facts','{"flow_count":1,"document_type_count":2,"normalized_monthly_pages":500,"user_count":3,"complexity_level":"standard","exceptional_scope":false}'::jsonb,'canonical scope facts contain all six authoritative dimensions');

select * from finish();
rollback;
