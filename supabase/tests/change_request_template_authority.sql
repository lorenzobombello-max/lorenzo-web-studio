begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(25);

select has_table('public','change_request_template_authorities','change request template authority exists');
select has_function('public','resolve_current_change_request_template_v1',array['text'],'server-side resolver exists');
select ok(not has_table_privilege('service_role','public.change_request_template_authorities','insert'),'service role cannot insert authority directly');
select ok(not has_table_privilege('service_role','public.change_request_template_authorities','update'),'service role cannot update authority directly');
select ok(not has_table_privilege('service_role','public.change_request_template_authorities','delete'),'service role cannot delete authority directly');
select ok(not has_function_privilege('anon','public.resolve_current_change_request_template_v1(text)','execute'),'anon cannot resolve authority');
select ok(not has_function_privilege('authenticated','public.resolve_current_change_request_template_v1(text)','execute'),'authenticated cannot resolve authority');
select ok(has_function_privilege('service_role','public.resolve_current_change_request_template_v1(text)','execute'),'service role can resolve authority');

select is((select count(*)::integer from public.change_request_template_authorities where status='CURRENT'),1,'exactly one current authority exists');
select is((select document_type from public.resolve_current_change_request_template_v1('CHANGE_REQUEST')),'CHANGE_REQUEST','canonical document type resolves');
select is((select array_to_string(product_families,',') from public.resolve_current_change_request_template_v1('CHANGE_REQUEST')),'WEBSITE,SLIMME_DOCUMENTENFLOW','authority binds both governed product families');
select is((select template_id from public.resolve_current_change_request_template_v1('CHANGE_REQUEST')),'LWS_CHANGE_REQUEST_NL_BE','canonical template id resolves');
select is((select template_version from public.resolve_current_change_request_template_v1('CHANGE_REQUEST')),'v2','canonical version resolves');
select is((select canonical_filename from public.resolve_current_change_request_template_v1('CHANGE_REQUEST')),'08_Wijzigingsverzoek_ChangeRequest_v2.docx','canonical filename resolves');
select is((select repository_asset_path from public.resolve_current_change_request_template_v1('CHANGE_REQUEST')),'assets/docs/change-request/08_Wijzigingsverzoek_ChangeRequest_v2.docx','governed repository asset resolves');
select is((select rtrim(template_sha256) from public.resolve_current_change_request_template_v1('CHANGE_REQUEST')),'671C2BD8512F7C222271464B2269C65826680CC822D8B4DCE8A0DEA9A6DC9271','canonical SHA-256 resolves');
select throws_ok($$select * from public.resolve_current_change_request_template_v1('QUOTATION')$$,'P0001','CHANGE_REQUEST_TEMPLATE_NOT_CURRENT','wrong type cannot fall back to quotation authority');
select throws_ok($$select * from public.resolve_current_change_request_template_v1('UNKNOWN')$$,'P0001','CHANGE_REQUEST_TEMPLATE_NOT_CURRENT','unknown type fails closed');

insert into public.change_request_template_authorities (
  template_id,template_version,document_type,product_families,canonical_filename,
  repository_asset_path,template_sha256,status,authority_reference,created_by
) values (
  'TEST_ONLY_SUPERSEDED_CHANGE_REQUEST','test-superseded','CHANGE_REQUEST',
  array['WEBSITE','SLIMME_DOCUMENTENFLOW']::text[],'test-only-superseded.docx',
  'assets/docs/change-request/test-only-superseded.docx',repeat('0',64),
  'SUPERSEDED','TEST_ONLY','test:change-request-template-authority'
);

select is((select template_version from public.resolve_current_change_request_template_v1('CHANGE_REQUEST')),'v2','superseded authority is ignored without fallback');
select throws_ok($$update public.change_request_template_authorities set status='SUPERSEDED' where status='CURRENT'$$,'55000','CHANGE_REQUEST_TEMPLATE_AUTHORITY_IMMUTABLE','current authority cannot be deactivated directly');
select throws_ok($$delete from public.change_request_template_authorities where status='CURRENT'$$,'55000','CHANGE_REQUEST_TEMPLATE_AUTHORITY_IMMUTABLE','current authority cannot be removed directly');

create temporary table change_request_template_side_effect_snapshot as
select
  (select count(*) from public.commercial_obligations where obligation_type='CHANGE_ORDER') as change_orders,
  (select count(*) from public.quote_request_pricing_snapshots) as pricing_snapshots,
  (select count(*) from public.quote_request_quotation_email_orchestrations) as mail_orchestrations;

select lives_ok($$select * from public.resolve_current_change_request_template_v1('CHANGE_REQUEST')$$,'resolver executes without business commands');
select is(
  (select row(change_orders,pricing_snapshots,mail_orchestrations)::text from change_request_template_side_effect_snapshot),
  (select row(
    (select count(*) from public.commercial_obligations where obligation_type='CHANGE_ORDER'),
    (select count(*) from public.quote_request_pricing_snapshots),
    (select count(*) from public.quote_request_quotation_email_orchestrations)
  )::text),
  'resolver creates no change order, pricing, or mail side effect'
);

set local role service_role;

select is(
  (select concat_ws('|',template_version,status,canonical_filename) from public.resolve_current_change_request_template_v1('CHANGE_REQUEST')),
  'v2|CURRENT|08_Wijzigingsverzoek_ChangeRequest_v2.docx',
  'service role resolves the canonical CURRENT Change Request v2 authority at runtime'
);
select throws_ok(
  $$select template_id from public.change_request_template_authorities limit 1$$,
  '42501',
  'permission denied for table change_request_template_authorities',
  'service role cannot read the authority table directly at runtime'
);

reset role;

select * from finish();
rollback;