begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'role', 'authenticated',
    'aal', 'aal1'
  )::text,
  true
);

select throws_ok(
  $$select public.appoint_operations_manager_v1(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MFA contract probe'
  )$$,
  '42501',
  'AAL2_REQUIRED',
  'OP-01 cannot start a critical authority mutation at aal1'
);

select lives_ok(
  $$select public.get_current_operator_identity_v1()$$,
  'OP-01 read-only identity remains available at aal1'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'bd2ab636-0d42-4069-88a9-60bd97f2b335',
    'role', 'authenticated',
    'aal', 'aal1'
  )::text,
  true
);

select throws_ok(
  $$select public.purge_dossier_v1(
    '00000000-0000-4000-8000-000000000002'::uuid,
    'MFA contract probe',
    '00000000-0000-4000-8000-000000000003'::uuid
  )$$,
  '42501',
  'AAL2_REQUIRED',
  'OP-02 cannot start a critical dossier mutation at aal1'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'bd2ab636-0d42-4069-88a9-60bd97f2b335',
    'role', 'authenticated',
    'aal', 'aal2'
  )::text,
  true
);

select throws_ok(
  $$select public.appoint_operations_manager_v1(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MFA contract probe'
  )$$,
  '42501',
  'OWNER_REQUIRED',
  'OP-02 aal2 still cannot bypass the existing owner authority'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'c9bcd3ef-1e7e-4889-8a12-db827f1b97b0',
    'role', 'authenticated',
    'aal', 'aal2'
  )::text,
  true
);

select throws_ok(
  $$select public.appoint_operations_manager_v1(
    '00000000-0000-4000-8000-000000000001'::uuid,
    'MFA contract probe'
  )$$,
  '23503',
  'TARGET_OPERATOR_NOT_FOUND',
  'OP-01 aal2 reaches the existing owner-authority validation without mutating data'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'd0247fd9-60d5-40bc-a905-6b02024b6420',
    'role', 'authenticated',
    'aal', 'aal2'
  )::text,
  true
);

select throws_ok(
  $$select public.purge_dossier_v1(
    '00000000-0000-4000-8000-000000000002'::uuid,
    'MFA contract probe',
    '00000000-0000-4000-8000-000000000003'::uuid
  )$$,
  '42501',
  'MFA_OPERATOR_NOT_ELIGIBLE',
  'OP-03 remains excluded even with an aal2 claim'
);

select ok(
  has_function_privilege('authenticated', 'public.purge_dossier_v1(uuid,text,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.purge_dossier_pre_mfa_impl_v1(uuid,text,uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.revoke_operations_manager_v1(uuid,text,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.revoke_operations_manager_pre_mfa_impl_v1(uuid,text,text)', 'execute'),
  'authenticated callers can execute only the AAL2 wrappers, never their implementations'
);

select * from finish();
rollback;