begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(35);

select has_function('public','is_valid_quotation_generation_payload_v1',array['jsonb'],'strict generation validator exists');
select has_function('public','canonicalize_quotation_generation_payload_v1',array['jsonb'],'deterministic canonicalizer exists');
select has_function('public','quotation_generation_payload_sha256_v1',array['jsonb'],'generation hash function exists');
select ok(not has_function_privilege('service_role','public.is_valid_quotation_generation_payload_raw_v1(jsonb)','execute'),'service role cannot bypass the strict VAT generation validator');
select has_function('public','build_quotation_preview_payload_v1',array['uuid','jsonb','jsonb','text'],'trusted preview builder exists');
select has_function('public','build_quotation_issue_payload_v1',array['uuid','jsonb','jsonb','text'],'trusted issue builder exists');
select ok(not has_function_privilege('anon','public.build_quotation_preview_payload_v1(uuid,jsonb,jsonb,text)','execute'),'anon cannot build preview');
select ok(not has_function_privilege('authenticated','public.build_quotation_issue_payload_v1(uuid,jsonb,jsonb,text)','execute'),'authenticated cannot build issue payload');
select ok(has_function_privilege('service_role','public.build_quotation_issue_payload_v1(uuid,jsonb,jsonb,text)','execute'),'service role can build issue payload');

create temporary table d3e4_inputs as
select
  jsonb_build_object('template_id','quotation-candidate','template_version','0.1.0','template_sha256',repeat('a',64),'authority_status','CANDIDATE') as candidate_template,
  jsonb_build_object('template_id','quotation-approved','template_version','1.0.0','template_sha256',repeat('b',64),'authority_status','APPROVED') as approved_template,
  jsonb_build_object('legal_name','Test Seller','address_line_1','Teststraat 1','address_line_2',null,'postal_code','9000','city','Gent','country_code','BE','enterprise_number','0123456789','vat_number','BE0123456789','email','seller@example.test','website','https://example.test','contact_name',null) as seller;

select ok(public.is_valid_quotation_generation_seller_v1(seller),'trusted seller snapshot is strictly valid') from d3e4_inputs;
select ok(public.is_valid_quotation_generation_template_v1(candidate_template,false),'preview accepts candidate template') from d3e4_inputs;
select ok(not public.is_valid_quotation_generation_template_v1(candidate_template,true),'issue rejects candidate template') from d3e4_inputs;
select ok(public.is_valid_quotation_generation_template_v1(approved_template,true),'issue accepts explicitly approved template identity') from d3e4_inputs;

select throws_ok(
  $$select * from public.build_quotation_preview_payload_v1('00000000-0000-4000-8000-000000000001','{}','{}',repeat('f',64))$$,
  'P0001','APPROVAL_NOT_FOUND','preview builder fails closed without immutable approval'
);
select throws_ok(
  $$select * from public.build_quotation_issue_payload_v1('00000000-0000-4000-8000-000000000001','{}','{}',repeat('f',64))$$,
  'P0001','ISSUANCE_NOT_FOUND','issue builder fails closed without PREPARED issuance'
);

select ok((public.quotation_generation_data_minimization_v1()->'EXCLUDED') ? 'capability_tokens','capability tokens are explicitly excluded');
select ok((public.quotation_generation_data_minimization_v1()->'EXCLUDED') ? 'raw_intake','raw intake is explicitly excluded');
select ok((public.quotation_generation_data_minimization_v1()->'AUDIT_ONLY') ? 'integrity_metadata','integrity metadata is audit-only');

create temporary table d3e4_payload as
select jsonb_build_object(
  'contract_version',1,'mode','PREVIEW','template',candidate_template,
  'quotation',jsonb_build_object('approval_id','d3ea5000-0000-4000-8000-000000000001','issuance_id',null,'quotation_number',null,'quotation_version',null,'quotation_status','NON_AUTHORITATIVE','visible_marker','CONCEPT — NIET GELDIG ALS OFFERTE'),
  'seller',seller,
  'customer',jsonb_build_object('customer_id',null,'legal_name','Customer','contact_name',null,'email','customer@example.test','address_line_1','Klantstraat 1','address_line_2',null,'postal_code','9000','city','Gent','country_code','BE','enterprise_number',null,'vat_number',null),
  'project',jsonb_build_object('project_id',null,'project_title','Website','project_type','website','scope_summary','Scope','requested_languages',jsonb_build_array('nl'),'included_page_count',1,'features','[]'::jsonb,'copywriting',null,'seo',null,'hosting',null,'maintenance',null,'exclusions','[]'::jsonb,'assumptions','[]'::jsonb,'indicative_timing',null),
  'lines',jsonb_build_array(jsonb_build_object('line_id','line-1','sequence',1,'product_or_service_code','WEB','description','Website','quantity',1,'unit','project','unit_price_minor',10000,'discount_minor',0,'vat_treatment','STANDARD','vat_rate',21,'line_net_amount_minor',10000,'cost_type','ONE_TIME')),
  'totals',jsonb_build_object('subtotal_net_minor',10000,'one_time_subtotal_minor',10000,'recurring_subtotal_minor',0,'discount_total_minor',0,'vat_base_minor',10000,'vat_amount_minor',2100,'total_gross_minor',12100),
  'vat',jsonb_build_object('vat_treatment','STANDARD','rate_semantics','PERCENT','vat_rate',21,'invoice_literal',null,'vat_decision_source','accountant'),
  'payment_schedule',jsonb_build_object('schedule_id','schedule-1','milestones',jsonb_build_array(jsonb_build_object('sequence',1,'label','Volledig','percentage',100,'amount_minor',null,'trigger','invoice','due_terms_days',30,'recurring_cycle',null))),
  'validity',jsonb_build_object('valid_from','2026-08-15','valid_until','2026-09-14','validity_days',30),
  'legal_references',jsonb_build_object('terms_reference','terms-v1','terms_version','1.0.0','agreement_reference',null,'agreement_version',null),
  'acceptance_instruction','Bevestig uw akkoord.','pricing_references',jsonb_build_object('approval_payload_sha256',repeat('c',64),'pricing_snapshot_id','d3ea2000-0000-4000-8000-000000000001','pricing_snapshot_contract_version',2),
  'locale',jsonb_build_object('document_language','nl','document_locale','nl-BE','currency','EUR')
) as payload from d3e4_inputs;

select ok(public.is_valid_quotation_generation_payload_v1(payload),'valid strict PREVIEW payload passes') from d3e4_payload;
select ok(not public.is_valid_quotation_generation_payload_v1(payload #- '{vat,rate_semantics}'),'generation VAT schema requires rate semantics') from d3e4_payload;
create temporary table d3e4_exempt_payload as
select jsonb_set(
  jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(payload, '{lines,0,vat_treatment}', '"EXEMPT"'),
        '{lines,0,vat_rate}', '0'
      ),
      '{totals,vat_amount_minor}', '0'
    ),
    '{totals,total_gross_minor}', '10000'
  ),
  '{vat}', '{"vat_treatment":"EXEMPT","rate_semantics":"NOT_APPLICABLE","vat_rate":0,"invoice_literal":"Bijzondere vrijstellingsregeling van belasting","vat_decision_source":"FOD_FINANCIEN:0cb8f71e-6522-47c2-9134-8c15300d3507:PAGE_15"}'
) as payload
from d3e4_payload;
select ok(
  public.is_valid_quotation_generation_payload_v1(payload),
  'EXEMPT plus NOT_APPLICABLE and the official literal is valid'
) from d3e4_exempt_payload;
select ok(
  not public.is_valid_quotation_generation_payload_v1(
    jsonb_set(payload, '{vat,rate_semantics}', '"PERCENT"')
  ),
  'wrong exemption rate semantics is rejected'
) from d3e4_exempt_payload;
select ok(
  not public.is_valid_quotation_generation_payload_v1(
    jsonb_set(payload, '{vat,invoice_literal}', '"0% BTW"')
  ),
  'wrong exemption literal is rejected'
) from d3e4_exempt_payload;
select ok(
  not public.is_valid_quotation_generation_payload_v1(
    jsonb_set(
      jsonb_set(payload, '{lines,0,vat_treatment}', '"ZERO_RATE"'),
      '{vat,vat_treatment}', '"ZERO_RATE"'
    )
  ),
  'ZERO_RATE cannot impersonate the EXEMPT generation semantics'
) from d3e4_exempt_payload;
select throws_ok(
  $$select public.project_quotation_generation_payload_v1(
    'PREVIEW', 'd3ea5000-0000-4000-8000-000000000001',
    '{"line_items":[],"vat_approval":{"vat_treatment":"EXEMPT","vat_rate":0,"vat_decision_source":"FOD_FINANCIEN:0cb8f71e-6522-47c2-9134-8c15300d3507:PAGE_15"}}',
    repeat('c',64), '{}'::jsonb, '{}'::jsonb
  )$$,
  'P0001', 'QUOTATION_VAT_BINDING_REQUIRED',
  'legacy EXEMPT approval without a frozen VAT binding fails closed'
);
select throws_ok(
  $$select public.project_quotation_generation_payload_v1(
    'PREVIEW', 'd3ea5000-0000-4000-8000-000000000001',
    '{"line_items":[],"vat_approval":{"vat_treatment":"EXEMPT","vat_rate":0,"vat_decision_source":"FOD_FINANCIEN:0cb8f71e-6522-47c2-9134-8c15300d3507:PAGE_15"}}',
    repeat('c',64), '{}'::jsonb, '{}'::jsonb
  )$$,
  'P0001', 'QUOTATION_VAT_BINDING_REQUIRED',
  'generation does not synthesize the official literal for an unbound approval'
);
select is(public.quotation_generation_payload_sha256_v1(payload),public.quotation_generation_payload_sha256_v1(payload::text::jsonb),'same payload has deterministic hash') from d3e4_payload;
select isnt(public.quotation_generation_payload_sha256_v1(payload),public.quotation_generation_payload_sha256_v1(jsonb_set(payload,'{customer,legal_name}','"Changed"')),'document-visible change changes hash') from d3e4_payload;
select ok(not public.is_valid_quotation_generation_payload_v1(jsonb_set(payload,'{quotation,quotation_number}','"LWS-OFF-2030-0001"')),'PREVIEW production number is rejected') from d3e4_payload;
select ok(not public.is_valid_quotation_generation_payload_v1(jsonb_set(payload,'{quotation,issuance_id}','"d3ea6000-0000-4000-8000-000000000001"')),'PREVIEW issuance identity is rejected') from d3e4_payload;
select ok(not public.is_valid_quotation_generation_payload_v1(jsonb_set(payload,'{locale,document_locale}','"fr-BE"')),'unsupported locale is rejected') from d3e4_payload;
select ok(not public.is_valid_quotation_generation_payload_v1(jsonb_set(payload,'{totals,total_gross_minor}','12099')),'totals mismatch is rejected') from d3e4_payload;
select ok(not public.is_valid_quotation_generation_payload_v1(jsonb_set(payload,'{payment_schedule,milestones,0,amount_minor}','10000')),'payment percentage and amount cannot coexist') from d3e4_payload;
select ok(not public.is_valid_quotation_generation_payload_v1(jsonb_set(payload,'{vat,vat_rate}','6')),'top-level VAT must match every approved line') from d3e4_payload;
select ok(not public.is_valid_quotation_generation_payload_v1(payload||'{"unknown":true}'::jsonb),'unknown top-level field is rejected') from d3e4_payload;

select * from finish();
rollback;
