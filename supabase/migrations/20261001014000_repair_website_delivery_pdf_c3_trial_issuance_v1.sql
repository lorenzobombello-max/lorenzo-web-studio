-- Forward repair for the C3 TEST_ONLY issuance after issuance_input_sha256 became mandatory.

do $migration$
declare
  v_definition text;
  v_repaired text;
begin
  select pg_get_functiondef(
    'public.create_website_delivery_pdf_c3_trial_fixture_v1(uuid,uuid)'::regprocedure
  ) into v_definition;
  v_repaired := replace(
    v_definition,
    'template_id, template_version, template_sha256, generation_contract_version,
    generation_payload_sha256, docx_sha256, docx_bytes,',
    'template_id, template_version, template_sha256, generation_contract_version,
    issuance_input_sha256, generation_payload_sha256, docx_sha256, docx_bytes,'
  );
  if v_repaired = v_definition then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_C3_TRIAL_ISSUANCE_COLUMNS_REPAIR_TARGET_MISSING';
  end if;
  v_definition := v_repaired;
  v_repaired := replace(
    v_definition,
    '''LWS_C3_TEST_ONLY'', ''1'', repeat(''3'',64), 1, repeat(''4'',64), repeat(''5'',64), 1,',
    '''LWS_C3_TEST_ONLY'', ''1'', repeat(''3'',64), 1, repeat(''e'',64), repeat(''4'',64), repeat(''5'',64), 1,'
  );
  if v_repaired = v_definition then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_C3_TRIAL_ISSUANCE_VALUES_REPAIR_TARGET_MISSING';
  end if;
  execute v_repaired;
end;
$migration$;

comment on function public.create_website_delivery_pdf_c3_trial_fixture_v1(uuid, uuid) is
  'Creates one isolated synthetic M2+CURRENT-preview fixture for an active internal_e2e run without payment, invoice, mail, access, or customer-approval evidence; quotation and issuance identities satisfy current validators.';
