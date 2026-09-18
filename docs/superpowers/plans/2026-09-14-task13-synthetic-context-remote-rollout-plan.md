# Task 13 synthetic context remote rollout plan

Status: PREPARED, NOT EXECUTED

Project ref: `xcsptvntvrizwhskaphr`

This rollout creates database and Edge authority only. It must not enable the GitHub provider, invoke the GitHub test island, create a repository, change a secret, or push Git.

## Immutable inputs

- Provider flag remains `LWS_GITHUB_PROVIDER_ENABLED=false`.
- Production installation: `161436785`.
- LAB installation: `161461160`.
- Production organization: `lorenzo-web-solutions`.
- LAB organization: `lorenzo-web-solutions-lab`.
- Starter: `lorenzo-web-solutions/lws-website-starter` (`1368684860`).
- Release: `v1.0.0`.
- Commit: `47e7d7aad37afaa0b3e921fac349a87d2dd2816a`.
- Tree SHA-256: `6b4a76bf8a64ad91dc18fabe410f032670f03578d2d4c2123dba7cc0e98b5957`.
- Release provenance is compiled into the Task 13 runtime. Do not add provenance secrets.

## 1. Preflight stop gate

From the repository root, authenticate the Supabase CLI and link only the stated project. Run:

```powershell
.\node_modules\.bin\supabase.cmd migration list --linked
```

Proceed only if remote history is consistent and the only Task 13 migrations awaiting application are:

- `20260914100000_harden_task13_two_principal_repository_claim_v1.sql`
- `20260914110000_add_task13_synthetic_context_authority_v1.sql`

Also confirm in the Supabase dashboard that `LWS_GITHUB_PROVIDER_ENABLED` is exactly `false`. Do not inspect or print secret values.

## 2. Apply migrations

```powershell
.\node_modules\.bin\supabase.cmd db push --linked
```

Do not deploy functions if this command is not fully successful.

## 3. Read back database authority

```powershell
.\node_modules\.bin\supabase.cmd migration list --linked
```

Verify both migration versions are present remotely. In the Supabase SQL editor, run this read-only check:

```sql
select
  p.oid::regprocedure::text as function_name,
  has_function_privilege('authenticated', p.oid, 'execute') as authenticated_execute,
  has_function_privilege('anon', p.oid, 'execute') as anon_execute,
  has_function_privilege('service_role', p.oid, 'execute') as service_role_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'create_task13_synthetic_context_v1',
    'claim_website_repository_provisioning_v1',
    'record_website_repository_external_identity_v1',
    'bind_website_repository_v1',
    'fail_website_repository_provisioning_v1',
    'resume_website_repository_provisioning_v1',
    'resolve_website_repository_quarantine_v1',
    'mark_website_repository_quarantine_alerted_v1',
    'get_website_repository_operation_v1'
  )
order by p.proname;
```

For `create_task13_synthetic_context_v1()`, require `true, false, false` for authenticated, anon, and service role respectively. Stop on any missing function or privilege mismatch.

## 4. Deploy the synthetic authority

```powershell
.\node_modules\.bin\supabase.cmd functions deploy github-task13-synthetic-context --project-ref xcsptvntvrizwhskaphr --no-verify-jwt
```

The function disables gateway JWT verification intentionally because its closed handler verifies the human JWT, expiry, AAL2, verified subject, and OWNER role before calling the parameterless RPC.

## 5. Deploy the GitHub test island without invoking it

```powershell
.\node_modules\.bin\supabase.cmd functions deploy github-task13-test-island --project-ref xcsptvntvrizwhskaphr --no-verify-jwt
```

Deployment is preparation only. Do not call this function in this rollout.

## 6. Boundary checks

Endpoint:

```text
https://xcsptvntvrizwhskaphr.supabase.co/functions/v1/github-task13-synthetic-context
```

Body:

```json
{"action":"create_task13_synthetic_context","environment":"TEST"}
```

Run, in order:

1. No Authorization header: require `401` and no row creation.
2. Valid AAL1 human JWT: require `403` and no row creation.
3. Valid AAL2 non-OWNER human JWT: require `403` and no row creation.
4. A body containing any ID, classification, customer, dossier, GitHub organization, repository, installation, or starter field: require `400` and no row creation.

Never place JWTs in command history, logs, files, or this runbook. Inject each token through the operator's approved ephemeral secret mechanism.

## 7. OWNER+AAL2 synthetic context check

With one valid OWNER+AAL2 human JWT, send exactly the closed body once. Require `201` and exactly these response keys:

- `website_work_context_id`
- `workspace_id`
- `record_classification`
- `environment`

Require `record_classification=internal_e2e` and `environment=TEST`. Read back the created rows and verify one new internal E2E website root, one unreleased `PRE_PROJECT` context, and one `PENDING_REPOSITORY` workspace with null project and repository identity.

## 8. Mandatory stop

Stop after database readback. Do not invoke `github-task13-test-island`. Confirm:

- `LWS_GITHUB_PROVIDER_ENABLED=false`.
- LAB repository count remains `0`.
- No GitHub API call occurred.
- No repository was created.
- No secret was changed.
- No Git commit or push occurred.

A later, separately authorized rollout may execute the GitHub bootstrap only after these facts are recorded and all Task 13 hard gates pass.
