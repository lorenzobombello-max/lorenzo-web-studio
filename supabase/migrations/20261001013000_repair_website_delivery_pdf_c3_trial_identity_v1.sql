-- Forward repair for the C3 TEST_ONLY quotation identity.
-- The current validator requires source_fields.legal_form whenever legal_form is explicit.

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
    '''source_fields'',jsonb_build_object(''classification'',''internal_e2e'')',
    '''source_fields'',jsonb_build_object(''legal_name'',''TEST_ONLY'',''legal_form'',''TEST_ONLY'')'
  );
  if v_repaired = v_definition then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_C3_TRIAL_IDENTITY_REPAIR_TARGET_MISSING';
  end if;
  execute v_repaired;
end;
$migration$;

comment on function public.create_website_delivery_pdf_c3_trial_fixture_v1(uuid, uuid) is
  'Creates one isolated synthetic M2+CURRENT-preview fixture for an active internal_e2e run without payment, invoice, mail, access, or customer-approval evidence; identity fields satisfy the current quotation validator.';
