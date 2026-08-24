begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(49);

select has_table('lws_internal', 'operator_dossier_states', 'private dossier state authority exists');
select has_table('lws_internal', 'operator_dossier_state_events', 'private dossier event authority exists');
select has_function('lws_internal', 'operator_dossier_transition_allowed_v1', array['text','text','text'], 'canonical transition contract exists');
select col_is_pk('lws_internal', 'operator_dossier_states', 'quote_request_id', 'state authority is one-to-one by root UUID');
select fk_ok('lws_internal', 'operator_dossier_states', 'quote_request_id', 'public', 'quote_requests', 'id', 'state authority binds to the canonical dossier root');

select is(
  (select confdeltype::text from pg_constraint where conname = 'operator_dossier_states_quote_request_id_fkey'),
  'c',
  'state authority follows a future authorized root cleanup by cascade'
);
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'lws_internal.operator_dossier_states'::regclass),
  'state authority has RLS and FORCE RLS'
);
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'lws_internal.operator_dossier_state_events'::regclass),
  'event authority has RLS and FORCE RLS'
);
select ok(
  not has_table_privilege('anon', 'lws_internal.operator_dossier_states', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'lws_internal.operator_dossier_states', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'lws_internal.operator_dossier_states', 'select,insert,update,delete'),
  'runtime roles have no direct state table authority'
);
select ok(
  not has_table_privilege('anon', 'lws_internal.operator_dossier_state_events', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'lws_internal.operator_dossier_state_events', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'lws_internal.operator_dossier_state_events', 'select,insert,update,delete'),
  'runtime roles have no direct event table authority'
);

insert into auth.users(id,email) values
  ('d1000000-0000-4000-8000-000000000001','dossier-state-owner@example.test');
insert into public.commercial_operators(operator_id,auth_user_id,display_name,role,status) values
  ('d1010000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','Dossier State Owner','owner','ACTIVE');

insert into public.quote_requests(
  id,record_classification,request_kind,sdf_package,name,email,description,privacy_consent,status
) values
  ('d1100000-0000-4000-8000-000000000001','production','slimme_documentenflow','start','State fixture A','state-a@example.test','Production dossier state fixture A.',true,'approved'),
  ('d1110000-0000-4000-8000-000000000002','production','slimme_documentenflow','groei','State fixture B','state-b@example.test','Production dossier state fixture B.',true,'approved'),
  ('d1120000-0000-4000-8000-000000000003','internal_e2e','slimme_documentenflow','start','E2E fixture','state-e2e@invalid.local','Independent E2E state fixture.',true,'approved');

select is(
  (select count(*)::integer from lws_internal.operator_dossier_states where quote_request_id in ('d1100000-0000-4000-8000-000000000001','d1110000-0000-4000-8000-000000000002')),
  2,
  'every new production dossier receives exactly one state row'
);
select is(
  (select count(*)::integer from lws_internal.operator_dossier_states where quote_request_id = 'd1120000-0000-4000-8000-000000000003'),
  0,
  'internal E2E remains outside dossier state authority'
);
select is(
  (select count(*)::integer from lws_internal.operator_dossier_states where state = 'ACTIVE' and revision = 0),
  (select count(*)::integer from public.quote_requests where record_classification = 'production'),
  'existing and new production dossiers are initialized ACTIVE at revision zero'
);
select is(
  (select count(*)::integer from public.quote_requests request left join lws_internal.operator_dossier_states state on state.quote_request_id=request.id where request.record_classification='production' and state.quote_request_id is null),
  0,
  'production root cardinality has no missing state rows'
);
select throws_ok(
  $$insert into lws_internal.operator_dossier_states(quote_request_id) values('d1120000-0000-4000-8000-000000000003')$$,
  '23514','OPERATOR_DOSSIER_PRODUCTION_ROOT_REQUIRED','non-production root cannot receive dossier state authority'
);
select throws_ok(
  $$update lws_internal.operator_dossier_states set state='DELETED',revision=1,updated_at=clock_timestamp()+interval '1 second' where quote_request_id='d1100000-0000-4000-8000-000000000001'$$,
  '23514','INVALID_OPERATOR_DOSSIER_TRANSITION','DELETED is absent and rejected fail closed'
);
select throws_ok(
  $$update lws_internal.operator_dossier_states set state='ACTIVE',revision=1,updated_at=clock_timestamp()+interval '1 second' where quote_request_id='d1100000-0000-4000-8000-000000000001'$$,
  '23514','INVALID_OPERATOR_DOSSIER_TRANSITION','ACTIVE to ACTIVE is not a mutation'
);
select throws_ok(
  $$update lws_internal.operator_dossier_states set state='TRASHED',revision=1,state_before_trash=null,deletion_eligible_at=null,updated_at=clock_timestamp()+interval '1 second' where quote_request_id='d1100000-0000-4000-8000-000000000001'$$,
  '23514',null,'TRASHED without state_before_trash fails closed'
);
select throws_ok(
  $$update lws_internal.operator_dossier_states set state='ARCHIVED',revision=1,deletion_eligible_at=clock_timestamp(),updated_at=clock_timestamp()+interval '1 second' where quote_request_id='d1100000-0000-4000-8000-000000000001'$$,
  '23514',null,'ARCHIVED rejects deletion eligibility metadata'
);
select throws_ok(
  $$update lws_internal.operator_dossier_states set state='ARCHIVED',revision=1,state_before_trash='ACTIVE',updated_at=clock_timestamp()+interval '1 second' where quote_request_id='d1100000-0000-4000-8000-000000000001'$$,
  '23514',null,'ARCHIVED rejects state_before_trash metadata'
);

update lws_internal.operator_dossier_states
set state='ARCHIVED',revision=1,updated_at=clock_timestamp()+interval '1 second'
where quote_request_id='d1100000-0000-4000-8000-000000000001';
select is((select state from lws_internal.operator_dossier_states where quote_request_id='d1100000-0000-4000-8000-000000000001'),'ARCHIVED','ACTIVE transitions to ARCHIVED');
select throws_ok(
  $$update lws_internal.operator_dossier_states set state='ACTIVE',revision=2,deletion_eligible_at=clock_timestamp(),updated_at=clock_timestamp()+interval '2 seconds' where quote_request_id='d1100000-0000-4000-8000-000000000001'$$,
  '23514',null,'ACTIVE rejects deletion eligibility metadata'
);
select throws_ok(
  $$update lws_internal.operator_dossier_states set state='ACTIVE',revision=2,state_before_trash='ARCHIVED',updated_at=clock_timestamp()+interval '2 seconds' where quote_request_id='d1100000-0000-4000-8000-000000000001'$$,
  '23514',null,'ACTIVE rejects state_before_trash metadata'
);
select throws_ok(
  $$update lws_internal.operator_dossier_states set state='ACTIVE',revision=1,updated_at=clock_timestamp()+interval '2 seconds' where quote_request_id='d1100000-0000-4000-8000-000000000001'$$,
  '40001','OPERATOR_DOSSIER_REVISION_MISMATCH','stale revision fails closed'
);
update lws_internal.operator_dossier_states
set state='ACTIVE',revision=2,updated_at=clock_timestamp()+interval '2 seconds'
where quote_request_id='d1100000-0000-4000-8000-000000000001';
select is((select state from lws_internal.operator_dossier_states where quote_request_id='d1100000-0000-4000-8000-000000000001'),'ACTIVE','ARCHIVED transitions to ACTIVE');

update lws_internal.operator_dossier_states
set state='TRASHED',revision=3,state_before_trash='ACTIVE',
    deletion_eligible_at=null,updated_at=clock_timestamp()+interval '3 seconds'
where quote_request_id='d1100000-0000-4000-8000-000000000001';
select ok(
  (select state='TRASHED' and state_before_trash='ACTIVE' and deletion_eligible_at is null and revision=3
   from lws_internal.operator_dossier_states where quote_request_id='d1100000-0000-4000-8000-000000000001'),
  'ACTIVE transitions to TRASHED with explicit no-purge authority'
);
select throws_ok(
  $$update lws_internal.operator_dossier_states set state='ARCHIVED',revision=4,state_before_trash=null,deletion_eligible_at=null,updated_at=clock_timestamp()+interval '4 seconds' where quote_request_id='d1100000-0000-4000-8000-000000000001'$$,
  '23514','INVALID_OPERATOR_DOSSIER_TRANSITION','TRASHED cannot restore to a state other than state_before_trash'
);
update lws_internal.operator_dossier_states
set state='ACTIVE',revision=4,state_before_trash=null,deletion_eligible_at=null,
    updated_at=clock_timestamp()+interval '4 seconds'
where quote_request_id='d1100000-0000-4000-8000-000000000001';
select is((select state from lws_internal.operator_dossier_states where quote_request_id='d1100000-0000-4000-8000-000000000001'),'ACTIVE','TRASHED restores to prior ACTIVE');

update lws_internal.operator_dossier_states
set state='ARCHIVED',revision=1,updated_at=clock_timestamp()+interval '1 second'
where quote_request_id='d1110000-0000-4000-8000-000000000002';
update lws_internal.operator_dossier_states
set state='TRASHED',revision=2,state_before_trash='ARCHIVED',
    deletion_eligible_at=null,updated_at=clock_timestamp()+interval '2 seconds'
where quote_request_id='d1110000-0000-4000-8000-000000000002';
select ok(
  (select state_before_trash='ARCHIVED' and deletion_eligible_at is null
   from lws_internal.operator_dossier_states where quote_request_id='d1110000-0000-4000-8000-000000000002'),
  'ARCHIVED transitions to TRASHED with prior state and no purge authority'
);
update lws_internal.operator_dossier_states
set state='ARCHIVED',revision=3,state_before_trash=null,deletion_eligible_at=null,
    updated_at=clock_timestamp()+interval '3 seconds'
where quote_request_id='d1110000-0000-4000-8000-000000000002';
select is((select state from lws_internal.operator_dossier_states where quote_request_id='d1110000-0000-4000-8000-000000000002'),'ARCHIVED','TRASHED restores to prior ARCHIVED');

select is(
  (select count(*)::integer
   from (values
     ('ACTIVE','ARCHIVED',null),('ARCHIVED','ACTIVE',null),
     ('ACTIVE','TRASHED','ACTIVE'),('ARCHIVED','TRASHED','ARCHIVED'),
     ('TRASHED','ACTIVE','ACTIVE'),('TRASHED','ARCHIVED','ARCHIVED')
   ) transition(previous_state,new_state,state_before_trash)
   where lws_internal.operator_dossier_transition_allowed_v1(previous_state,new_state,state_before_trash)),
  6,
  'all six context-valid transition paths are allowed'
);
select ok(
  not lws_internal.operator_dossier_transition_allowed_v1('TRASHED','ACTIVE','ARCHIVED')
  and not lws_internal.operator_dossier_transition_allowed_v1('ACTIVE','ACTIVE',null)
  and not lws_internal.operator_dossier_transition_allowed_v1('ARCHIVED','ARCHIVED',null)
  and not lws_internal.operator_dossier_transition_allowed_v1('TRASHED','TRASHED','ACTIVE'),
  'undefined and mismatched restore transitions fail closed'
);

insert into lws_internal.operator_dossier_state_events(
  quote_request_id,event_type,previous_state,new_state,state_before_trash,
  previous_revision,new_revision,deletion_eligible_at,actor_operator_id,reason,
  idempotency_key,request_fingerprint,evidence
) values(
  'd1100000-0000-4000-8000-000000000001','TRASHED','ACTIVE','TRASHED','ACTIVE',
  0,1,null,'d1010000-0000-4000-8000-000000000001','Archive contract evidence.',
  'd1200000-0000-4000-8000-000000000001',repeat('a',64),'{"contract_version":1}'
);
select is((select count(*)::integer from lws_internal.operator_dossier_state_events where event_type='TRASHED' and deletion_eligible_at is null),1,'TRASHED event records explicit no-purge authority');
select throws_ok(
  $$insert into lws_internal.operator_dossier_state_events(quote_request_id,event_type,previous_state,new_state,state_before_trash,previous_revision,new_revision,deletion_eligible_at,actor_operator_id,reason,idempotency_key,request_fingerprint) values('d1110000-0000-4000-8000-000000000002','TRASHED','ACTIVE','TRASHED',null,0,1,null,'d1010000-0000-4000-8000-000000000001','Missing prior state.','d1200000-0000-4000-8000-000000000004',repeat('e',64))$$,
  '23514',null,'TRASHED event without state_before_trash fails closed'
);
select throws_ok(
  $$update lws_internal.operator_dossier_state_events set reason='Changed'$$,
  '55000','OPERATOR_DOSSIER_STATE_EVENT_APPEND_ONLY','event update is denied'
);
select throws_ok(
  $$delete from lws_internal.operator_dossier_state_events$$,
  '55000','OPERATOR_DOSSIER_STATE_EVENT_APPEND_ONLY','event delete is denied'
);
select throws_ok(
  $$insert into lws_internal.operator_dossier_state_events(quote_request_id,event_type,previous_state,new_state,previous_revision,new_revision,actor_operator_id,reason,idempotency_key,request_fingerprint) values('d1100000-0000-4000-8000-000000000001','ARCHIVED','ACTIVE','ARCHIVED',1,2,'d1010000-0000-4000-8000-000000000001','Duplicate command.','d1200000-0000-4000-8000-000000000001',repeat('b',64))$$,
  '23505',null,'duplicate dossier idempotency key is denied'
);
select throws_ok(
  $$insert into lws_internal.operator_dossier_state_events(quote_request_id,event_type,previous_state,new_state,state_before_trash,previous_revision,new_revision,actor_operator_id,reason,idempotency_key,request_fingerprint) values('d1100000-0000-4000-8000-000000000001','RESTORED','TRASHED','ACTIVE','ARCHIVED',3,4,'d1010000-0000-4000-8000-000000000001','Invalid restore evidence.','d1200000-0000-4000-8000-000000000002',repeat('c',64))$$,
  '23514',null,'invalid restore evidence fails closed'
);
select throws_ok(
  $$insert into lws_internal.operator_dossier_state_events(quote_request_id,event_type,previous_state,new_state,previous_revision,new_revision,actor_operator_id,reason,idempotency_key,request_fingerprint,evidence) values('d1100000-0000-4000-8000-000000000001','ARCHIVED','ACTIVE','ARCHIVED',4,5,'d1010000-0000-4000-8000-000000000001','Unsafe evidence.','d1200000-0000-4000-8000-000000000003',repeat('d',64),'{"access_token_hash":"forbidden"}')$$,
  '23514',null,'sensitive event evidence is denied'
);

set local role authenticated;
select throws_ok(
  $$update lws_internal.operator_dossier_states set revision=revision+1$$,
  '42501',null,'authenticated direct state mutation is denied'
);
reset role;

select is((select enum_range(null::public.quote_request_intake_status)::text),'{invited,in_progress,submitted,reviewed}','intake progress authority is unchanged');
select has_function('public','resolve_quote_request_intake_effective_access_v1',array['text','timestamptz','timestamptz'],'CANCELLED remains separate intake lifecycle authority');
select has_table('lws_internal','legacy_test_cleanup_authorities','exact legacy cleanup authority remains present');
select is((select count(*)::integer from lws_internal.legacy_test_cleanup_authorities),11,'legacy cleanup allowlist remains exactly eleven');
select ok(
  exists(select 1 from pg_constraint where conrelid='public.commercial_projects'::regclass and conname='commercial_project_money_coherent' and contype='c'),
  '40/40/rest amount authority remains constrained'
);
select ok(
  not has_function_privilege('authenticated','lws_internal.operator_dossier_transition_allowed_v1(text,text,text)','execute')
  and not has_function_privilege('service_role','lws_internal.operator_dossier_transition_allowed_v1(text,text,text)','execute'),
  'transition internals expose no runtime execution authority'
);
select is(
  (select count(*)::integer from information_schema.columns where table_schema='lws_internal' and table_name='operator_dossier_states' and column_name='state'),
  1,
  'one canonical state column exists without parallel status authority'
);
select is(
  (select count(*)::integer from pg_constraint where conrelid='lws_internal.operator_dossier_states'::regclass and pg_get_constraintdef(oid) ilike '%DELETED%'),
  0,
  'catalog contains no DELETED dossier state'
);
select ok(
  (select updated_at >= created_at from lws_internal.operator_dossier_states where quote_request_id='d1100000-0000-4000-8000-000000000001'),
  'state authority timestamps remain ordered'
);

select * from finish();
rollback;