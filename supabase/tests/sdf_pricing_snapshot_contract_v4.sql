begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_column('public', 'quote_request_pricing_snapshots', 'sdf_pricing', 'SDF pricing envelope column exists');
select has_function('public', 'is_valid_sdf_pricing_snapshot_v4', array['jsonb'], 'SDF v4 structural validator exists');
select has_function(
  'public', 'is_strict_pricing_snapshot_v4', array['uuid','smallint','text','text','jsonb'],
  'SDF v4 strict lineage validator exists'
);

create function pg_temp.fixture_uuid(p_value text)
returns uuid language sql immutable set search_path=pg_catalog as $$
  select (substr(md5(p_value),1,8)||'-'||substr(md5(p_value),9,4)||'-4'||substr(md5(p_value),14,3)||'-8'||substr(md5(p_value),18,3)||'-'||substr(md5(p_value),21,12))::uuid
$$;

create function pg_temp.sdf_snapshot(p_package text)
returns jsonb
language plpgsql
stable
set search_path = public, lws_internal, extensions, pg_catalog
as $$
declare
  v_authority jsonb := lws_internal.get_sdf_budget_guard_pricing_authority_v2(p_package);
begin
  return jsonb_build_object(
    'commercial_decision_id', pg_temp.fixture_uuid('qf2b-' || p_package || '-decision'),
    'product_kind', 'sdf',
    'package', p_package,
    'currency', 'EUR',
    'implementation', jsonb_build_object(
      'amount_minor', v_authority#>'{implementation,amount_minor}',
      'price_mode', v_authority#>>'{implementation,price_mode}'
    ),
    'recurring', jsonb_build_object(
      'amount_minor', v_authority#>'{recurring,amount_minor}',
      'interval', 'month',
      'price_mode', v_authority#>>'{recurring,price_mode}'
    ),
    'pricing_authority_sha256', encode(
      extensions.digest(convert_to(v_authority::text, 'UTF8'), 'sha256'), 'hex'
    ),
    'submission_sha256', repeat('a', 64),
    'document_evidence_sha256', repeat('b', 64)
  );
end;
$$;

select ok(public.is_valid_sdf_pricing_snapshot_v4(pg_temp.sdf_snapshot('start')), 'START snapshot is valid');
select ok(public.is_valid_sdf_pricing_snapshot_v4(pg_temp.sdf_snapshot('groei')), 'GROEI snapshot is valid');
select ok(public.is_valid_sdf_pricing_snapshot_v4(pg_temp.sdf_snapshot('pro')), 'PRO snapshot is valid');
select ok(public.is_valid_sdf_pricing_snapshot_v4(pg_temp.sdf_snapshot('maatwerk')), 'MAATWERK manual/null state is structurally valid');
select ok(
  not public.is_strict_pricing_snapshot_v4(
    pg_temp.fixture_uuid('qf2b-maatwerk-intake'), 4::smallint, '2026-09-01-v4',
    pg_temp.sdf_snapshot('maatwerk')->>'pricing_authority_sha256',
    pg_temp.sdf_snapshot('maatwerk')
  ),
  'MAATWERK cannot become strict without immutable fixed commercial authority'
);

select ok(not public.is_valid_sdf_pricing_snapshot_v4(
  pg_temp.sdf_snapshot('start') || jsonb_build_object('normalizedScope', '{}'::jsonb)
), 'website field is rejected');
select ok(not public.is_valid_sdf_pricing_snapshot_v4(
  pg_temp.sdf_snapshot('start') || jsonb_build_object('starter_floor', 180000)
), 'starter_floor is rejected');
select ok(not public.is_valid_sdf_pricing_snapshot_v4(
  jsonb_set(pg_temp.sdf_snapshot('start'), '{package}', '"starter_v1"')
), 'website package ID is rejected');
select ok(not public.is_valid_sdf_pricing_snapshot_v4(
  jsonb_set(pg_temp.sdf_snapshot('start'), '{implementation,amount_minor}', '285001')
), 'client setup price mismatch is rejected');
select ok(not public.is_valid_sdf_pricing_snapshot_v4(
  jsonb_set(pg_temp.sdf_snapshot('start'), '{recurring,interval}', '"year"')
), 'invalid recurring interval is rejected');
select ok(not public.is_valid_sdf_pricing_snapshot_v4(
  jsonb_set(pg_temp.sdf_snapshot('start'), '{implementation,amount_minor}', 'null')
), 'fixed package with null setup amount is rejected');
select ok(not public.is_valid_sdf_pricing_snapshot_v4(
  jsonb_set(
    jsonb_set(pg_temp.sdf_snapshot('maatwerk'), '{implementation,price_mode}', '"fixed"'),
    '{implementation,amount_minor}', '1'
  )
), 'manual package with fixed setup amount is rejected');
select ok(not public.is_valid_sdf_pricing_snapshot_v4(
  pg_temp.sdf_snapshot('start') || jsonb_build_object('unexpected', true)
), 'unknown SDF snapshot field is rejected');

create function pg_temp.approval_payload(p_snapshot_version integer)
returns jsonb language sql immutable set search_path=pg_catalog as $$
  select jsonb_build_object(
    'contract_version',1,
    'source_quote_request_id','4f2b0000-0000-4000-8000-000000000001',
    'source_intake_id','4f2b1000-0000-4000-8000-000000000001',
    'pricing_snapshot',jsonb_build_object(
      'snapshot_id','4f2b2000-0000-4000-8000-000000000001',
      'snapshot_contract_version',p_snapshot_version,
      'integrity_algorithm_version','hmac-sha256-v1','integrity_key_id','v1',
      'integrity_mac',repeat('c',64)
    ),
    'currency','EUR',
    'line_items',jsonb_build_array(
      jsonb_build_object(
        'line_id','sdf-setup','sequence',1,'product_or_service_code','SDF_SETUP',
        'description','Synthetic SDF implementation','quantity',1,'unit','project',
        'unit_price_minor',285000,'discount_minor',0,'vat_treatment','EXEMPT',
        'vat_rate',0,'line_net_amount_minor',285000,'cost_type','ONE_TIME'
      ),
      jsonb_build_object(
        'line_id','sdf-monthly','sequence',2,'product_or_service_code','SDF_MONTHLY',
        'description','Synthetic SDF monthly service','quantity',1,'unit','month',
        'unit_price_minor',17500,'discount_minor',0,'vat_treatment','EXEMPT',
        'vat_rate',0,'line_net_amount_minor',17500,'cost_type','RECURRING'
      )
    ),
    'totals',jsonb_build_object(
      'one_time_subtotal_minor',285000,'recurring_subtotal_minor',17500,
      'discount_total_minor',0,'vat_base_minor',285000,'vat_amount_minor',0,
      'total_gross_minor',285000
    ),
    'discount',jsonb_build_object(
      'discount_type',null,'discount_value_minor',0,'discount_reason',null,
      'approved_by',null,'approved_at',null
    ),
    'customer_identity',jsonb_build_object(
      'source_quote_request_id','4f2b0000-0000-4000-8000-000000000001',
      'source_intake_id','4f2b1000-0000-4000-8000-000000000001',
      'customer_id',null,'legal_name','Synthetic SDF Customer','contact_name',null,
      'email','qf2b@example.test','address_line_1','Teststraat 1','address_line_2',null,
      'postal_code','9000','city','Gent','country_code','BE','enterprise_number',null,
      'vat_number',null,'source_fields',jsonb_build_object('legal_name','synthetic'),
      'snapshot_sha256',repeat('d',64)
    ),
    'project_scope',jsonb_build_object(
      'project_id',null,'project_title','Synthetic SDF','project_type','sdf',
      'scope_summary','Synthetic controlled document flow','requested_languages',jsonb_build_array('nl'),
      'included_page_count',0,'features',jsonb_build_array('document_flow'),
      'copywriting',null,'seo',null,'hosting',null,'maintenance',null,
      'exclusions','[]'::jsonb,'assumptions','[]'::jsonb,'indicative_timing',null,
      'source_intake_id','4f2b1000-0000-4000-8000-000000000001',
      'source_pricing_snapshot_id','4f2b2000-0000-4000-8000-000000000001',
      'snapshot_sha256',repeat('e',64)
    ),
    'vat_approval',jsonb_build_object(
      'vat_treatment','EXEMPT','vat_rate',0,'vat_decision_source','LWS_OUTGOING_VAT',
      'vat_approved_by','authority:test','vat_approved_at','2026-09-01T00:00:00Z'
    ),
    'payment_schedule',jsonb_build_object(
      'schedule_id','qf2b-schedule','milestones',jsonb_build_array(jsonb_build_object(
        'sequence',1,'label','Implementation','percentage',100,'amount_minor',null,
        'trigger','invoice','due_terms_days',30,'recurring_cycle',null
      )),'approved_by','owner:test','approved_at','2026-09-01T00:00:00Z'
    ),
    'validity',jsonb_build_object(
      'valid_from','2026-09-01','valid_until','2026-10-01','validity_days',30,
      'approved_by','owner:test','approved_at','2026-09-01T00:00:00Z'
    ),
    'legal_references',jsonb_build_object(
      'terms_reference','synthetic-terms','terms_version','1.0.0','terms_sha256',repeat('f',64),
      'terms_status','APPROVED','agreement_template_reference',null,
      'agreement_template_version',null,'agreement_template_sha256',null
    )
  )
$$;

select ok(
  public.is_valid_quotation_approval_payload_v1(pg_temp.approval_payload(4), false),
  'valid synthetic SDF approval payload is recognized at contract v4 without executing approval'
);
select ok(
  not public.is_valid_quotation_approval_payload_v1(pg_temp.approval_payload(5), false),
  'unknown pricing snapshot contract version is rejected by approval validator'
);

select * from finish();
rollback;