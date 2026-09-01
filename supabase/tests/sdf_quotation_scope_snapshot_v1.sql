begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(19);

create function pg_temp.sdf_scope_answers(
  p_document_types integer,
  p_flow_count integer,
  p_users integer,
  p_documents_per_type integer
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'documentPurpose',jsonb_build_object(
      'categories',(
        select jsonb_agg(document_type order by ordinal)
        from unnest(array[
          'quotation','invoice','order_confirmation','work_order','delivery_note',
          'contract','customer_document','supplier_document',
          'internal_administrative_document','multiple_document_types',
          'other_custom','unknown_qualification_required'
        ]) with ordinality as category(document_type,ordinal)
        where ordinal<=p_document_types
      )
    ) || case when p_document_types>=11
      then jsonb_build_object('otherDescription','Synthetic custom document')
      else '{}'::jsonb end,
    'workflowCapabilities',jsonb_build_array('receive','review','approve'),
    'businessRequirements',jsonb_build_object(
      'currentWorkflow','Synthetic current workflow',
      'desiredWorkflow','Synthetic controlled workflow',
      'volumeBand','50_to_249','frequency','monthly',
      'relevantDocumentTypes',jsonb_build_array('Synthetic document'),
      'rolesUsers',jsonb_build_array('Synthetic operator')
    ),
    'sampleDocumentMetadata',jsonb_build_object(
      'available',false,'requestedByLws',false,'uploadRequiredLater',false
    ),
    'commercialQualification',jsonb_build_object(
      'packageDirection','start',
      'customComplexity','',
      'documentVolumes',(
        select jsonb_agg(jsonb_build_object(
          'documentType',document_type,
          'documentCount',p_documents_per_type,
          'period','monthly','averagePagesPerDocument',1
        ) order by ordinal)
        from unnest(array[
          'quotation','invoice','order_confirmation','work_order','delivery_note',
          'contract','customer_document','supplier_document',
          'internal_administrative_document','multiple_document_types',
          'other_custom','unknown_qualification_required'
        ]) with ordinality as category(document_type,ordinal)
        where ordinal<=p_document_types
      ),
      'flowCount',p_flow_count,
      'userCount',p_users
    )
  )
$$;

create function pg_temp.sdf_scope_schedule(p_implementation_minor bigint)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'milestones',jsonb_build_array(
      jsonb_build_object(
        'sequence',1,'label','Synthetic opdrachtbevestiging','percentage',40,
        'amount_minor',round(p_implementation_minor * 0.4)::bigint,
        'trigger','accepted','due_terms_days',30,'recurring_cycle',null
      ),
      jsonb_build_object(
        'sequence',2,'label','Synthetic functionele oplevering','percentage',40,
        'amount_minor',round(p_implementation_minor * 0.4)::bigint,
        'trigger','functional_delivery','due_terms_days',30,'recurring_cycle',null
      ),
      jsonb_build_object(
        'sequence',3,'label','Synthetic definitieve oplevering','percentage',20,
        'amount_minor',p_implementation_minor-
          2*round(p_implementation_minor * 0.4)::bigint,
        'trigger','final_delivery','due_terms_days',30,'recurring_cycle',null
      )
    )
  )
$$;

create temporary table sdf_scope_cases(
  package_key text primary key,
  answers jsonb not null,
  schedule jsonb not null
);
insert into sdf_scope_cases values
  ('start',pg_temp.sdf_scope_answers(1,1,3,500),pg_temp.sdf_scope_schedule(285000)),
  ('groei',pg_temp.sdf_scope_answers(3,3,10,600),pg_temp.sdf_scope_schedule(570000)),
  ('pro',pg_temp.sdf_scope_answers(6,6,25,500),pg_temp.sdf_scope_schedule(750000)),
  ('maatwerk',pg_temp.sdf_scope_answers(11,7,26,700),jsonb_build_object(
    'milestones',jsonb_build_array()
  ));

create temporary table sdf_scope_results as
select package_key,lws_internal.build_sdf_quotation_scope_snapshot_v1(
  answers,package_key,schedule
) scope
from sdf_scope_cases;

select is(
  (select jsonb_agg(scope->>'package_key' order by package_key)
   from sdf_scope_results),
  '["groei","maatwerk","pro","start"]'::jsonb,
  'START GROEI PRO and MAATWERK have explicit canonical package keys'
);
select is(
  (select jsonb_agg(scope->>'required_package_key' order by package_key)
   from sdf_scope_results),
  '["groei","maatwerk","pro","start"]'::jsonb,
  'required package key is explicit and server evaluated'
);
select is(
  (select scope#>>'{budget_guard_result,classification_reason}'
   from sdf_scope_results where package_key='start'),
  'WITHIN_START_LIMITS','START Budget Guard result is explicit'
);
select is(
  (select scope#>>'{budget_guard_result,classification_reason}'
   from sdf_scope_results where package_key='groei'),
  'WITHIN_GROEI_LIMITS','GROEI Budget Guard result is explicit'
);
select is(
  (select scope#>>'{budget_guard_result,classification_reason}'
   from sdf_scope_results where package_key='pro'),
  'WITHIN_PRO_LIMITS','PRO Budget Guard result is explicit'
);
select is(
  (select scope#>>'{budget_guard_result,classification_reason}'
   from sdf_scope_results where package_key='maatwerk'),
  'ABOVE_PRO_LIMITS','MAATWERK Budget Guard result is explicit'
);
select is(
  (select scope->>'implementation_amount_minor' from sdf_scope_results
   where package_key='start'),'285000','fixed implementation amount is authoritative'
);
select is(
  (select scope->>'recurring_amount_minor' from sdf_scope_results
   where package_key='start'),'17500','recurring amount remains separate'
);
select ok(
  (select scope->'implementation_amount_minor'='null'::jsonb
     and scope->'recurring_amount_minor'='null'::jsonb
   from sdf_scope_results where package_key='maatwerk'),
  'MAATWERK invents no fixed implementation or recurring price'
);
select is(
  (select scope->'payment_milestones' from sdf_scope_results where package_key='pro'),
  (select schedule->'milestones' from sdf_scope_cases where package_key='pro'),
  'approved 40 40 20 milestone snapshot is preserved exactly'
);
select is(
  (select scope->'selected_document_types' from sdf_scope_results
   where package_key='groei'),
  '["invoice","order_confirmation","quotation"]'::jsonb,
  'selected document types come from canonical submission'
);
select is(
  (select scope->>'document_flow_count' from sdf_scope_results where package_key='pro'),
  '6','document flow count is explicit'
);
select is(
  (select scope->>'document_type_count' from sdf_scope_results where package_key='pro'),
  '6','document type count is explicit'
);
select is(
  (select scope->>'normalized_monthly_pages' from sdf_scope_results where package_key='pro'),
  '3000','normalized monthly pages are explicit'
);
select is(
  (select scope->>'user_count' from sdf_scope_results where package_key='pro'),
  '25','user count is explicit'
);
select is(
  (select scope#>'{workflow_complexity,workflow_capabilities}'
   from sdf_scope_results where package_key='pro'),
  '["approve","receive","review"]'::jsonb,
  'workflow complexity is copied from canonical submission'
);
select ok(
  (select bool_and(public.is_valid_sdf_quotation_scope_snapshot_v1(scope))
   from sdf_scope_results),
  'all canonical scope snapshots validate'
);
select throws_ok(
  $$select lws_internal.build_sdf_quotation_scope_snapshot_v1(
    pg_temp.sdf_scope_answers(6,6,25,500),'start',
    pg_temp.sdf_scope_schedule(285000)
  )$$,
  '55000','SDF_SCOPE_PACKAGE_MISMATCH',
  'package is not derived from free text or frontend package direction'
);
select throws_ok(
  $$select lws_internal.build_sdf_quotation_scope_snapshot_v1(
    jsonb_build_object('commercialQualification',jsonb_build_object()),
    'start',pg_temp.sdf_scope_schedule(285000)
  )$$,
  '22023','SDF_SCOPE_SNAPSHOT_INPUT_INVALID',
  'missing canonical scope fails closed'
);

select * from finish();
rollback;
