begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(28);

create temporary table sdf_v2_fixture(payload jsonb not null);
insert into sdf_v2_fixture(payload) values (
  '{"documentPurpose":{"categories":["invoice"]},"workflowCapabilities":["receive","review"],"businessRequirements":{"currentWorkflow":"Handmatige ontvangst","desiredWorkflow":"Gecontroleerde digitale flow","volumeBand":"50_to_249","frequency":"monthly","relevantDocumentTypes":["Factuur"],"rolesUsers":["Boekhouding"]},"sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false},"commercialQualification":{"packageDirection":"start","customComplexity":"","documentVolumes":[{"documentType":"invoice","documentCount":120,"period":"monthly","averagePagesPerDocument":2}]}}'::jsonb
);

select has_function('lws_internal','sdf_payload_valid_v2',array['jsonb','boolean'],'V2 exact-schema validator exists');
select has_function('lws_internal','canonicalize_sdf_payload_v2',array['jsonb'],'V2 canonicalizer exists');
select has_function('lws_internal','sdf_payload_taxonomy_version_v2',array['jsonb','boolean'],'version dispatcher exists');

select is(
  lws_internal.sdf_payload_taxonomy_version_v2(
    '{"documentPurpose":{"categories":["invoice"]},"workflowCapabilities":["receive"],"businessRequirements":{"currentWorkflow":"A","desiredWorkflow":"B","volumeBand":"1_to_9","frequency":"weekly","relevantDocumentTypes":["Factuur"],"rolesUsers":["Boekhouding"]},"sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false}}'::jsonb,
    true
  ),
  'sdf_qualification_intake/1.0.0',
  'legacy complete C4A remains V1'
);
select ok(lws_internal.sdf_payload_valid_v1(
  '{"documentPurpose":{"categories":["invoice"]},"workflowCapabilities":["receive"],"businessRequirements":{"currentWorkflow":"A","desiredWorkflow":"B","volumeBand":"1_to_9","frequency":"weekly","relevantDocumentTypes":["Factuur"],"rolesUsers":["Boekhouding"]},"sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false}}'::jsonb,
  true
),'legacy C4A validator remains valid');

select ok(lws_internal.sdf_payload_valid_v2(payload,true),'START direction with one bounded volume is valid') from sdf_v2_fixture;
select ok(lws_internal.sdf_payload_valid_v2(jsonb_set(payload,'{commercialQualification,packageDirection}','"groei"'),true),'GROEI direction is valid') from sdf_v2_fixture;
select ok(lws_internal.sdf_payload_valid_v2(jsonb_set(payload,'{commercialQualification,packageDirection}','"pro"'),true),'PRO direction is valid') from sdf_v2_fixture;
select ok(lws_internal.sdf_payload_valid_v2(
  jsonb_set(jsonb_set(payload,'{commercialQualification,packageDirection}','"maatwerk"'),'{commercialQualification,customComplexity}','"Meerdere systemen en complexe goedkeuringen"'),true
),'MAATWERK direction requires and accepts bounded context') from sdf_v2_fixture;
select ok(lws_internal.sdf_payload_valid_v2(jsonb_set(payload,'{commercialQualification,packageDirection}','"advice_requested"'),true),'advice-requested direction is valid') from sdf_v2_fixture;
select isnt(lws_internal.sdf_payload_valid_v2(jsonb_set(payload,'{commercialQualification,packageDirection}','"enterprise"'),true),true,'unknown package direction is rejected') from sdf_v2_fixture;

select ok(lws_internal.sdf_payload_valid_v2(
  '{"documentPurpose":{"categories":["invoice","quotation"]},"workflowCapabilities":["receive","review"],"businessRequirements":{"currentWorkflow":"A","desiredWorkflow":"B","volumeBand":"50_to_249","frequency":"monthly","relevantDocumentTypes":["Factuur","Offerte"],"rolesUsers":["Boekhouding"]},"sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false},"commercialQualification":{"packageDirection":"groei","customComplexity":"","documentVolumes":[{"documentType":"invoice","documentCount":100,"period":"monthly","averagePagesPerDocument":2},{"documentType":"quotation","documentCount":30,"period":"quarterly","averagePagesPerDocument":5}]}}'::jsonb,
  true
),'multiple document types retain separate counts and periods');

select ok(lws_internal.sdf_payload_valid_v2(
  '{"documentPurpose":{"categories":["other_custom"] ,"otherDescription":"Douanedocument"},"workflowCapabilities":["receive"],"businessRequirements":{"currentWorkflow":"A","desiredWorkflow":"B","volumeBand":"10_to_49","frequency":"monthly","relevantDocumentTypes":["Douanedocument"],"rolesUsers":["Administratie"]},"sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false},"commercialQualification":{"packageDirection":"maatwerk","customComplexity":"Externe koppeling","documentVolumes":[{"documentType":"other_custom","documentCount":20,"period":"monthly","averagePagesPerDocument":3}]}}'::jsonb,
  true
),'custom document type keeps its description and volume');

select isnt(lws_internal.sdf_payload_valid_v2(jsonb_set(payload,'{commercialQualification,documentVolumes,0,documentCount}','0'),true),true,'zero count is rejected') from sdf_v2_fixture;
select isnt(lws_internal.sdf_payload_valid_v2(jsonb_set(payload,'{commercialQualification,documentVolumes,0,documentCount}','-1'),true),true,'negative count is rejected') from sdf_v2_fixture;
select isnt(lws_internal.sdf_payload_valid_v2(jsonb_set(payload,'{commercialQualification,documentVolumes,0,period}','"daily"'),true),true,'invalid period is rejected') from sdf_v2_fixture;
select isnt(lws_internal.sdf_payload_valid_v2(jsonb_set(payload,'{commercialQualification,documentVolumes,0,documentCount}','1000001'),true),true,'excessive count is rejected') from sdf_v2_fixture;
select isnt(lws_internal.sdf_payload_valid_v2(jsonb_set(payload,'{commercialQualification,documentVolumes}','[]'),true),true,'missing selected-type volume is rejected') from sdf_v2_fixture;
select isnt(lws_internal.sdf_payload_valid_v2(jsonb_set(payload,'{commercialQualification,documentVolumes,0,documentType}','"quotation"'),true),true,'volume for an unselected type is rejected') from sdf_v2_fixture;
select isnt(lws_internal.sdf_payload_valid_v2(jsonb_set(payload,'{commercialQualification,documentVolumes,0,averagePagesPerDocument}','1001'),true),true,'excessive average pages is rejected') from sdf_v2_fixture;
select isnt(lws_internal.sdf_payload_valid_v2(jsonb_set(payload,'{commercialQualification,priceMinor}','1000'),true),true,'pricing authority field is rejected') from sdf_v2_fixture;
select isnt(lws_internal.sdf_payload_valid_v2(jsonb_set(payload,'{commercialQualification,documentVolumes,0,estimatedPagesPerPeriod}','240'),true),true,'client-derived volume field is rejected from authority') from sdf_v2_fixture;

select ok(lws_internal.sdf_payload_valid_v2(
  jsonb_set(jsonb_set(jsonb_set(payload,'{commercialQualification,packageDirection}','""'),'{commercialQualification,documentVolumes,0,documentCount}','null'),'{commercialQualification,documentVolumes,0,averagePagesPerDocument}','null'),
  false
),'partial V2 draft permits null numeric inputs') from sdf_v2_fixture;
select isnt(lws_internal.sdf_payload_valid_v2(
  jsonb_set(jsonb_set(jsonb_set(payload,'{commercialQualification,packageDirection}','""'),'{commercialQualification,documentVolumes,0,documentCount}','null'),'{commercialQualification,documentVolumes,0,averagePagesPerDocument}','null'),
  true
),true,'partial V2 draft cannot be submitted') from sdf_v2_fixture;

select is(
  lws_internal.sdf_payload_taxonomy_version_v2(payload,true),
  'sdf_qualification_intake/2.0.0',
  'complete commercial qualification dispatches to V2'
) from sdf_v2_fixture;

select is(
  lws_internal.canonicalize_sdf_payload_v2(jsonb_set(payload,'{commercialQualification,packageDirection}','"pro"'))#>>'{commercialQualification,packageDirection}',
  'pro',
  'PRO survives canonical roundtrip as its distinct key'
) from sdf_v2_fixture;

select is(
  encode(digest(convert_to(lws_internal.canonicalize_sdf_payload_v2(jsonb_set(payload,'{commercialQualification,packageDirection}','"pro"'))::text,'UTF8'),'sha256'),'hex'),
  encode(digest(convert_to(lws_internal.canonicalize_sdf_payload_v2(jsonb_set(payload,'{commercialQualification,packageDirection}','"pro"'))::text,'UTF8'),'sha256'),'hex'),
  'PRO V2 canonical payload hash is deterministic'
) from sdf_v2_fixture;

select is(
  lws_internal.canonicalize_sdf_payload_v2(
    '{"documentPurpose":{"categories":["quotation","invoice"]},"workflowCapabilities":["review","receive"],"businessRequirements":{"currentWorkflow":"A","desiredWorkflow":"B","volumeBand":"50_to_249","frequency":"monthly","relevantDocumentTypes":["Offerte","Factuur"],"rolesUsers":["Verkoop","Boekhouding"]},"sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false},"commercialQualification":{"packageDirection":"groei","customComplexity":"","documentVolumes":[{"documentType":"quotation","documentCount":30,"period":"quarterly","averagePagesPerDocument":5},{"documentType":"invoice","documentCount":100,"period":"monthly","averagePagesPerDocument":2}]}}'::jsonb
  ),
  lws_internal.canonicalize_sdf_payload_v2(
    '{"documentPurpose":{"categories":["invoice","quotation"]},"workflowCapabilities":["receive","review"],"businessRequirements":{"currentWorkflow":"A","desiredWorkflow":"B","volumeBand":"50_to_249","frequency":"monthly","relevantDocumentTypes":["Factuur","Offerte"],"rolesUsers":["Boekhouding","Verkoop"]},"sampleDocumentMetadata":{"available":false,"requestedByLws":false,"uploadRequiredLater":false},"commercialQualification":{"packageDirection":"groei","customComplexity":"","documentVolumes":[{"documentType":"invoice","documentCount":100,"period":"monthly","averagePagesPerDocument":2},{"documentType":"quotation","documentCount":30,"period":"quarterly","averagePagesPerDocument":5}]}}'::jsonb
  ),
  'canonical payload is stable across set and volume ordering'
);

select * from finish();
rollback;
