-- Forward repair for the C3 TEST_ONLY fixture site binding.
-- The existing guarded site command remains the sole authority for validation,
-- authorization, idempotency, actor evidence, and immutable site history.

do $migration$
declare
  v_definition text;
  v_repaired text;
  v_anchor text := '  insert into public.preview_versions(';
  v_site_command text := $site_command$  perform public.execute_operator_project_site_command_v1(
    v_project_id,
    'INITIAL_BIND',
    0,
    p_idempotency_key,
    'c3-test-only.invalid',
    'TEST_ONLY:C3:PDF_RECOVERY_ONLY'
  );

$site_command$;
begin
  select pg_get_functiondef(
    'public.create_website_delivery_pdf_c3_trial_fixture_v1(uuid,uuid)'::regprocedure
  ) into v_definition;
  if position('execute_operator_project_site_command_v1' in v_definition) > 0 then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_C3_TRIAL_SITE_BINDING_REPAIR_ALREADY_PRESENT';
  end if;
  v_repaired := replace(v_definition, v_anchor, v_site_command || v_anchor);
  if v_repaired = v_definition then
    raise exception using errcode = 'P0001', message = 'WEBSITE_DELIVERY_PDF_C3_TRIAL_SITE_BINDING_REPAIR_TARGET_MISSING';
  end if;
  execute v_repaired;
end;
$migration$;

comment on function public.create_website_delivery_pdf_c3_trial_fixture_v1(uuid, uuid) is
  'Creates one isolated synthetic M2+CURRENT-preview fixture with a guarded TEST_ONLY .invalid site binding for an active internal_e2e run, without payment, invoice, mail, access, or customer-approval evidence; quotation and issuance identities satisfy current validators.';