begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(24);

select has_function('public','is_valid_quotation_preview_package_v1',array['jsonb'],'strict preview package validator exists');
select has_function('public','canonicalize_quotation_preview_package_v1',array['jsonb'],'preview package canonicalizer exists');
select has_function('public','quotation_preview_package_sha256_v1',array['jsonb'],'preview package hash exists');
select has_function('public','quotation_preview_id_v1',array['text'],'deterministic preview identity exists');
select has_function('public','build_quotation_preview_package_v1',array['uuid','jsonb','jsonb','text','text','text'],'trusted preview orchestrator exists');
select ok(not has_function_privilege('anon','public.build_quotation_preview_package_v1(uuid,jsonb,jsonb,text,text,text)','execute'),'anon cannot orchestrate preview');
select ok(not has_function_privilege('authenticated','public.build_quotation_preview_package_v1(uuid,jsonb,jsonb,text,text,text)','execute'),'authenticated cannot orchestrate preview');
select ok(has_function_privilege('service_role','public.build_quotation_preview_package_v1(uuid,jsonb,jsonb,text,text,text)','execute'),'service role can orchestrate preview');

select is(public.quotation_preview_id_v1(repeat('a',64)),public.quotation_preview_id_v1(repeat('a',64)),'same generation hash yields same preview identity');
select isnt(public.quotation_preview_id_v1(repeat('a',64)),public.quotation_preview_id_v1(repeat('b',64)),'changed generation hash changes preview identity');
select throws_ok($$select public.quotation_preview_id_v1('bad')$$,'22023','PREVIEW_FINGERPRINT_INVALID','malformed preview fingerprint is rejected');
select throws_ok($$select * from public.build_quotation_preview_package_v1('00000000-0000-4000-8000-000000000001','{}','{}','fr-BE','DOCX',repeat('f',64))$$,'22023','UNSUPPORTED_PREVIEW_LOCALE','unsupported locale is rejected');
select throws_ok($$select * from public.build_quotation_preview_package_v1('00000000-0000-4000-8000-000000000001','{}','{}','nl-BE','PDF',repeat('f',64))$$,'22023','UNSUPPORTED_PREVIEW_OUTPUT','unsupported output is rejected');
select throws_ok($$select * from public.build_quotation_preview_package_v1('00000000-0000-4000-8000-000000000001',jsonb_build_object('template_id','approved','template_version','1.0.0','template_sha256',repeat('a',64),'authority_status','APPROVED'),'{}','nl-BE','DOCX',repeat('f',64))$$,'P0001','PREVIEW_TEMPLATE_NOT_CANDIDATE','APPROVED template is rejected by candidate-only path');
select throws_ok($$select * from public.build_quotation_preview_package_v1('00000000-0000-4000-8000-000000000001',jsonb_build_object('template_id','candidate','template_version','0.1.0','template_sha256','bad','authority_status','CANDIDATE'),'{}','nl-BE','DOCX',repeat('f',64))$$,'22023','TEMPLATE_IDENTITY_INVALID','missing valid candidate hash is rejected');

create temporary table preview_contract_fixture as
select jsonb_build_object(
  'contract_version',1,'mode','PREVIEW',
  'template',jsonb_build_object('template_id','candidate','template_version','0.1.0','template_sha256',repeat('a',64),'authority_status','CANDIDATE'),
  'quotation',jsonb_build_object('approval_id','d3ea5000-0000-4000-8000-000000000001','issuance_id',null,'quotation_number',null,'quotation_version',null,'quotation_status','NON_AUTHORITATIVE','visible_marker','CONCEPT — NIET GELDIG ALS OFFERTE'),
  'seller',jsonb_build_object('legal_name','Test Seller','address_line_1','Teststraat 1','address_line_2',null,'postal_code','9000','city','Gent','country_code','BE','enterprise_number','0123456789','vat_number','BE0123456789','email','seller@example.test','website','https://example.test','contact_name',null),
  'customer',jsonb_build_object('customer_id',null,'legal_name','Customer','contact_name',null,'email','customer@example.test','address_line_1','Klantstraat 1','address_line_2',null,'postal_code','9000','city','Gent','country_code','BE','enterprise_number',null,'vat_number',null),
  'project',jsonb_build_object('project_id',null,'project_title','Website','project_type','website','scope_summary','Scope','requested_languages',jsonb_build_array('nl'),'included_page_count',1,'features','[]'::jsonb,'copywriting',null,'seo',null,'hosting',null,'maintenance',null,'exclusions','[]'::jsonb,'assumptions','[]'::jsonb,'indicative_timing',null),
  'lines',jsonb_build_array(jsonb_build_object('line_id','line-1','sequence',1,'product_or_service_code','WEB','description','Website','quantity',1,'unit','project','unit_price_minor',10000,'discount_minor',0,'vat_treatment','STANDARD','vat_rate',21,'line_net_amount_minor',10000,'cost_type','ONE_TIME')),
  'totals',jsonb_build_object('subtotal_net_minor',10000,'one_time_subtotal_minor',10000,'recurring_subtotal_minor',0,'discount_total_minor',0,'vat_base_minor',10000,'vat_amount_minor',2100,'total_gross_minor',12100),
  'vat',jsonb_build_object('vat_treatment','STANDARD','vat_rate',21,'vat_decision_source','accountant'),
  'payment_schedule',jsonb_build_object('schedule_id','schedule-1','milestones',jsonb_build_array(jsonb_build_object('sequence',1,'label','Volledig','percentage',100,'amount_minor',null,'trigger','invoice','due_terms_days',30,'recurring_cycle',null))),
  'validity',jsonb_build_object('valid_from','2026-08-15','valid_until','2026-09-14','validity_days',30),
  'legal_references',jsonb_build_object('terms_reference','terms-v1','terms_version','1.0.0','agreement_reference',null,'agreement_version',null),
  'acceptance_instruction','Bevestig uw akkoord.',
  'pricing_references',jsonb_build_object('approval_payload_sha256',repeat('c',64),'pricing_snapshot_id','d3ea2000-0000-4000-8000-000000000001','pricing_snapshot_contract_version',2),
  'locale',jsonb_build_object('document_language','nl','document_locale','nl-BE','currency','EUR')
) as payload;

create temporary table preview_package_fixture as
select jsonb_build_object(
  'preview_contract_version',1,
  'preview_id',public.quotation_preview_id_v1(public.quotation_generation_payload_sha256_v1(payload)),
  'created_at','2026-08-15T12:00:00.000000Z','mode','PREVIEW','is_authoritative',false,
  'source_identity',jsonb_build_object('source_type','IMMUTABLE_APPROVAL','approval_id','d3ea5000-0000-4000-8000-000000000001'),
  'template',payload->'template','generation_payload',payload,
  'generation_payload_sha256',public.quotation_generation_payload_sha256_v1(payload),
  'display_markers',jsonb_build_object('primary','CONCEPT — NIET GELDIG ALS OFFERTE','secondary','Geen officieel offertenummer toegekend.'),
  'locale',payload->'locale','requested_output','DOCX',
  'renderer_handoff',jsonb_build_object('package_kind','PREVIEW_PACKAGE','companion_required','TECHNICAL_QUOTATION_TEMPLATE','target','DOCX_RENDERER')
) as package from preview_contract_fixture;

select ok(public.is_valid_quotation_preview_package_v1(package),'valid deterministic preview package passes') from preview_package_fixture;
select is(public.quotation_preview_package_sha256_v1(package),public.quotation_preview_package_sha256_v1(package::text::jsonb),'preview package hash is deterministic') from preview_package_fixture;
select ok(not public.is_valid_quotation_preview_package_v1(jsonb_set(package,'{is_authoritative}','true')),'authoritative preview injection is rejected') from preview_package_fixture;
select ok(not public.is_valid_quotation_preview_package_v1(jsonb_set(package,'{generation_payload,quotation,quotation_number}','"LWS-OFF-2030-0001"')),'production number injection is rejected') from preview_package_fixture;
select ok(not public.is_valid_quotation_preview_package_v1(jsonb_set(package,'{generation_payload,quotation,issuance_id}','"d3ea6000-0000-4000-8000-000000000001"')),'issuance identity injection is rejected') from preview_package_fixture;
select ok(not public.is_valid_quotation_preview_package_v1(jsonb_set(package,'{display_markers,primary}','"Offerte"')),'invalid visible marker is rejected') from preview_package_fixture;
select ok(not public.is_valid_quotation_preview_package_v1(jsonb_set(package,'{generation_payload_sha256}',to_jsonb(repeat('0',64)))),'mismatched generation hash is rejected') from preview_package_fixture;
select ok(not public.is_valid_quotation_preview_package_v1(package||'{"capability_token":"secret"}'::jsonb),'unknown sensitive package field is rejected') from preview_package_fixture;
select is((select count(*)::integer from public.quotation_number_counters),0,'contract validation consumes no quotation number');

select * from finish();
rollback;
