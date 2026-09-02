begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(13);

select has_function('public', 'get_operator_dossier_substance_v1', array['uuid', 'uuid'], 'dossier substance projection exists');
select ok(
  has_function_privilege('service_role', 'public.get_operator_dossier_substance_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.get_operator_dossier_substance_v1(uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.get_operator_dossier_substance_v1(uuid,uuid)', 'execute'),
  'only service transport can execute dossier substance projection'
);

insert into auth.users(id, email) values
  ('ac100000-0000-4000-8000-000000000001', 'substance-owner@example.test'),
  ('ac100000-0000-4000-8000-000000000002', 'substance-operator@example.test'),
  ('ac100000-0000-4000-8000-000000000003', 'substance-disabled@example.test');
insert into public.commercial_operators(operator_id, auth_user_id, display_name, role, status) values
  ('ac110000-0000-4000-8000-000000000001', 'ac100000-0000-4000-8000-000000000001', 'Substance Owner', 'owner', 'ACTIVE'),
  ('ac110000-0000-4000-8000-000000000002', 'ac100000-0000-4000-8000-000000000002', 'Substance Operator', 'operator', 'ACTIVE'),
  ('ac110000-0000-4000-8000-000000000003', 'ac100000-0000-4000-8000-000000000003', 'Substance Disabled', 'admin', 'DISABLED');

insert into public.quote_requests(
  id, record_classification, request_kind, name, company, email, phone,
  website_type, budget, timing, description, privacy_consent, status
) values
  ('ac120001-0000-4000-8000-000000000001', 'production', 'website', 'Website customer', 'Website BV', 'website@example.test', null, 'Website op maat', 'EUR 3.000', 'flexible', '<script>exact request</script>', true, 'approved'),
  ('ac120002-0000-4000-8000-000000000002', 'production', 'slimme_documentenflow', 'SDF customer', null, 'sdf@example.test', null, null, null, null, 'Exact SDF request.', true, 'approved'),
  ('ac120003-0000-4000-8000-000000000003', 'production', 'website', 'Missing intake', null, 'missing@example.test', null, 'Website op maat', 'EUR 3.000', 'flexible', 'Missing linked intake.', true, 'approved');

insert into public.quote_request_intakes(
  id, quote_request_id, status, access_token_hash, access_token_expires_at, started_at,
  business_description, target_audience, requested_features, additional_notes
) values (
  'ac130000-0000-4000-8000-000000000001', 'ac120001-0000-4000-8000-000000000001',
  'in_progress', repeat('a', 64), '2099-01-01T00:00:00Z', now(),
  'Exact business context', 'Zakelijke klanten', array['contact_form'], 'Exact additional note'
);

insert into public.sdf_qualification_intakes(
  intake_id, quote_request_id, status, customer_capability_digest,
  customer_capability_encrypted, customer_capability_expires_at, draft_answers
) values (
  'ac140000-0000-4000-8000-000000000001', 'ac120002-0000-4000-8000-000000000002',
  'invited', repeat('b', 64), 'v1.ABCDEFGHIJKLMNOP.ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn',
  '2099-01-01T00:00:00Z',
  '{"businessRequirements":{"currentWorkflow":"Handmatig","desiredWorkflow":"Geautomatiseerd","rolesUsers":["Boekhouding"]},"workflowCapabilities":["receive","archive"],"commercialQualification":{"packageDirection":"groei"}}'::jsonb
);

select is(
  public.get_operator_dossier_substance_v1('ac100000-0000-4000-8000-000000000001', 'ac120001-0000-4000-8000-000000000001') #>> '{request,original_text}',
  '<script>exact request</script>',
  'original customer text remains exact'
);
select is(
  public.get_operator_dossier_substance_v1('ac100000-0000-4000-8000-000000000001', 'ac120001-0000-4000-8000-000000000001') #>> '{intake,structured_answers,business_description}',
  'Exact business context',
  'website structured intake is projected'
);
select is(
  public.get_operator_dossier_substance_v1('ac100000-0000-4000-8000-000000000001', 'ac120001-0000-4000-8000-000000000001') #>> '{intake,invitation_state}',
  'ACTIVATED',
  'in-progress website intake is activated'
);
select is(
  public.get_operator_dossier_substance_v1('ac100000-0000-4000-8000-000000000001', 'ac120002-0000-4000-8000-000000000002') #>> '{intake,structured_answers,businessRequirements,currentWorkflow}',
  'Handmatig',
  'SDF draft is projected through explicit keys'
);
insert into public.sdf_qualification_intake_submissions(
  submission_id, intake_id, submission_sequence, answers, taxonomy_version,
  payload_sha256, confirmation_version, confirmation_sha256
) values (
  'ac150000-0000-4000-8000-000000000001', 'ac140000-0000-4000-8000-000000000001', 1,
  '{"businessRequirements":{"currentWorkflow":"Ingediend exact"},"commercialQualification":{"documentVolumes":[{"documentType":"invoice","documentCount":12,"period":"monthly","averagePagesPerDocument":2,"unknown":"forbidden"}]},"unknown":"forbidden"}'::jsonb,
  'sdf_qualification_intake/1.0.0', repeat('c', 64),
  'SDF_QUALIFICATION_CONFIRMATION_NL_BE_v1', repeat('d', 64)
);
select is(
  public.get_operator_dossier_substance_v1('ac100000-0000-4000-8000-000000000001', 'ac120002-0000-4000-8000-000000000002') #>> '{intake,structured_answers,businessRequirements,currentWorkflow}',
  'Ingediend exact',
  'latest immutable SDF submission takes precedence over draft'
);
select is(
  public.get_operator_dossier_substance_v1('ac100000-0000-4000-8000-000000000001', 'ac120002-0000-4000-8000-000000000002') #>> '{intake,invitation_state}',
  'INVITED',
  'invited SDF intake remains distinct'
);
select is(
  (public.get_operator_dossier_substance_v1('ac100000-0000-4000-8000-000000000001', 'ac120001-0000-4000-8000-000000000001') #>> '{documents,customer_request_count}')::integer,
  0,
  'linked document domain returns counts only'
);
select ok(
  not (public.get_operator_dossier_substance_v1('ac100000-0000-4000-8000-000000000001', 'ac120002-0000-4000-8000-000000000002') #> '{intake,structured_answers}') ? 'unknown'
  and not (public.get_operator_dossier_substance_v1('ac100000-0000-4000-8000-000000000001', 'ac120002-0000-4000-8000-000000000002') #> '{intake,structured_answers,commercialQualification,documentVolumes,0}') ? 'unknown',
  'unknown root and nested SDF keys are not projected'
);
select throws_ok(
  $$select public.get_operator_dossier_substance_v1('ac100000-0000-4000-8000-000000000002', 'ac120001-0000-4000-8000-000000000001')$$,
  '42501', 'APPLICATION_SCOPE_DENIED', 'unauthorized operator is rejected'
);
select throws_ok(
  $$select public.get_operator_dossier_substance_v1('ac100000-0000-4000-8000-000000000003', 'ac120001-0000-4000-8000-000000000001')$$,
  '42501', 'OPERATOR_DISABLED', 'disabled operator is rejected'
);
select throws_ok(
  $$select public.get_operator_dossier_substance_v1('ac100000-0000-4000-8000-000000000001', 'ac120003-0000-4000-8000-000000000003')$$,
  'P0001', 'DOSSIER_INTAKE_NOT_FOUND', 'missing linked intake fails safely'
);

select * from finish();
rollback;