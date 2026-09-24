# GIT-001C Production Execution Runbook

Status: **GATES 1-4 EXECUTED; GATE 5 BLOCKED BEFORE MUTATION ON MISSING REMOTE WORKFLOW**. GIT-001C remains **OPEN** until live acceptance is proven.

## Fixed authority

- Reviewed baseline: `b4fc16e2e754a31b111408a8450376332e5f3a90`; every production phase uses the then-reviewed exact HEAD.
- Supabase project: `xcsptvntvrizwhskaphr`.
- Platform workflow repository: `lorenzobombello-max/lorenzo-web-studio`, immutable ID `1320223175`, branch/ref `main` / `refs/heads/main`.
- Customer source: repository ID `1378797607`, commit `1f19bf01c61c6da79fa4c7374333a91b70f9bf48`.
- Cloudflare account: `acbc1b86d8c3f0ce809dc4600783a48b`; existing project `lws-website-project-preview-host`, ID `56ba0651-2499-4b40-b3f7-ad2b690dfa3c`.
- Assigned Pages hostname: `lws-website-project-preview-host.pages.dev`; customer hostname: `preview.lorenzowebsolutions.be`.
- Never create another Pages project or customer repository. Preserve Worker `lorenzobombello-api-proxy`.

## Local preparation versus production

Local/review-only actions are the contract test, targeted security tests, `supabase db push --dry-run`, provider GET/list calls and command review. Production mutations are separately gated: migration push; Supabase secret/config writes; function deploys; GitHub variable writes/workflow publication; Pages secret/deploy/domain writes; OVH CNAME; and dispatch. Never combine two gates merely because the previous gate passed.

## Configuration contract

Supabase already contains `SUPABASE_URL`, its service-key binding, `LWS_GITHUB_APP_ID`, `LWS_GITHUB_APP_INSTALLATION_ID` and `LWS_GITHUB_APP_PRIVATE_KEY`. Add only these names when their phase is approved:

| Name | Exact non-secret value or source | Required by |
| --- | --- | --- |
| `LWS_PREVIEW_OIDC_AUDIENCE` | `lws-preview-artifact-receipt` | artifact + source-token functions; GitHub variable |
| `LWS_PREVIEW_WORKFLOW_REPOSITORY` | `lorenzobombello-max/lorenzo-web-studio` | artifact + source-token |
| `LWS_PREVIEW_WORKFLOW_REPOSITORY_ID` | `1320223175` | artifact + source-token |
| `LWS_PREVIEW_WORKFLOW_REF` | `lorenzobombello-max/lorenzo-web-studio/.github/workflows/build-website-project-preview.yml@refs/heads/main` | artifact + source-token |
| `LWS_PREVIEW_WORKFLOW_REF_NAME` | `refs/heads/main` | artifact + source-token |
| `LWS_PREVIEW_ORIGIN_TOKEN` | one execution-time random 32-byte value, identical in Supabase and encrypted Pages secret | origin + Pages |
| `LWS_PREVIEW_HOST_URL` | `https://preview.lorenzowebsolutions.be` | operator command, only after custom-domain/TLS acceptance |
| `LWS_PREVIEW_SOURCE_TOKEN_ENDPOINT` | `https://xcsptvntvrizwhskaphr.supabase.co/functions/v1/website-project-preview-source-token` | GitHub Actions variable |
| `LWS_PREVIEW_ARTIFACT_ENDPOINT` | `https://xcsptvntvrizwhskaphr.supabase.co/functions/v1/website-project-preview-artifact` | GitHub Actions variable |
| `LWS_PREVIEW_ORIGIN_URL` | `https://xcsptvntvrizwhskaphr.supabase.co/functions/v1/website-project-preview-host` | Pages plain variable in reviewed Wrangler config |

Secret values never enter this runbook, git, shell history or Wrangler `vars`. Prepare an ignored local env file under `.local-backups/git001c/` and delete it after provider writes.

## Ordered production gates

### Gate 1: recovery checkpoint and additive migrations

Outcome 2026-09-24: **ACCEPTED AND EXECUTED** from exact clean HEAD `aaad95da5969b15f7bba5e3f9aee2fb1435e40db`. With no newer providerbackup and PITR off, the physical baseline was supplemented by checksummed, ignored schema/data exports for `auth,storage,public,lws_internal` plus an explicit isolated-restore procedure. All eight existing previewleases were released, the previewbucket contained zero objects, and current auth state was exported without assigning a cause to the observed `auth.users` change. The guarded script applied all seven migrations in order; focused verification found all seven ledger entries and zero pending migrations. The command below is retained as historical procedure only: always resolve the then-current reviewed HEAD and provider recovery evidence instead of reusing these values.

Dependencies: reviewed exact HEAD; clean worktree; fresh completed backup recorded; PITR-off risk accepted; remote pending set exactly the seven contract migrations. Preflight is read-only:

```powershell
./scripts/invoke-git001c-preview-release.ps1 -Phase Preflight
```

Provider API or DNS-over-HTTPS unavailability fails this gate closed. Retry the unchanged preflight after the transient failure; never bypass, infer or manually override Pages/DNS state.

After separate approval, apply only from the reviewed HEAD:

```powershell
$reviewedHead = git rev-parse HEAD
./scripts/invoke-git001c-preview-release.ps1 -Phase ApplyMigrations `
  -ExpectedHead $reviewedHead `
  -ResponsibleOperator $env:USERNAME `
  -BackupId "1759100262" `
  -BackupCompletedAtUtc "2026-09-23T05:25:23.466Z" `
  -PitrState OFF `
  -Execute
```

Acceptance: the script first verifies that backup ID, completion time, freshness (maximum 24 hours) and PITR state still match the provider; all seven timestamps are then remote in order; tables, constraints, RPC definitions and grants match source; existing operator RPC/AAL2 tests remain valid. The script writes a value-free recovery checkpoint before `db push`. If the named backup is no longer the latest fresh completed backup, rerun read-only `Preflight`, review the newly reported ID/timestamp and update only those two command arguments.

Rollback: stop before function deployment. Do not mark migrations manually. Because the migrations are additive and later migrations depend on earlier objects, revert only after an explicit database decision and in reverse dependency order; otherwise leave schema in place and keep every new endpoint undeployed.

### Gate 2: Supabase bindings and three functions, workflow still absent

Outcome 2026-09-24: **ACCEPTED AND EXECUTED** from clean evidence HEAD `305b1a28329d0a29f994482538892325876fc0eb`. Exactly the five workflow/OIDC bindings below plus `LWS_PREVIEW_ORIGIN_TOKEN` were set; `LWS_PREVIEW_HOST_URL` remains absent until Gate 4. The three contracted functions are active at version 1 with provider bundle digests recorded in the checkpoint. Live unauthenticated probes returned the required 403/401/403 fail-closed responses. No valid token issue/upload/session/browser flow was attempted, so this is not functional liveacceptance. Workflow, Pages and DNS remained untouched.

Dependencies: Gate 1 accepted. Create the local ignored env file with the five workflow/OIDC bindings plus `LWS_PREVIEW_ORIGIN_TOKEN`; retain existing App secret values without reading or rewriting them.

```powershell
npx supabase secrets set --project-ref xcsptvntvrizwhskaphr --env-file .local-backups/git001c/preview-supabase.env
npx supabase functions deploy website-project-preview-artifact --project-ref xcsptvntvrizwhskaphr --no-verify-jwt
npx supabase functions deploy website-project-preview-source-token --project-ref xcsptvntvrizwhskaphr --no-verify-jwt
npx supabase functions deploy website-project-preview-host --project-ref xcsptvntvrizwhskaphr --no-verify-jwt
```

Acceptance: function list contains exactly these three new slugs; direct origin request without purpose token returns `403 PREVIEW_ORIGIN_FORBIDDEN` before RPC/Storage; unauthenticated artifact/source-token requests return their fail-closed auth response; workflow remains absent and undispatched.

Rollback: remove or disable only the three new functions/bindings. Do not alter the GitHub App installation, existing functions, bucket data or customer repository.

### Gate 3: Pages secret and deployment without DNS

Outcome 2026-09-24: **ACCEPTED AND EXECUTED**. Preflight found the exact existing empty project, no domains/secrets, DNS NXDOMAIN and the preserved Worker. The DPAPI-protected Gate 2 token was written in memory as the sole Pages secret. Wrangler `4.137.0` rejected the unsupported config `secrets` field before the first write; tested commit `b8df38f73617e47aba60ab2bbcec3c14455c17f8` removed it. Deployment `dff59da2-f14c-4f4a-8186-0cdeedff8467` then revealed that the live 308 lacked `cache-control` and was rejected. Tested replacement commit `c79a72a26c6a4d958f43bdbca56d3c4bdc869ac1` added `private, no-store`; latest production deployment `84b61c2c-9672-4ffc-adb7-15581a095eae` is successful from that clean SHA. Primary and immutable pages.dev URLs now redirect path/query before origin contact with the required cache policy; direct origin remains fail-closed. Domains remain empty and DNS remains NXDOMAIN.

Dependencies: Gate 2 accepted; Pages project GET still returns ID `56ba0651-2499-4b40-b3f7-ad2b690dfa3c`, zero unexpected deployments/domains and account Worker `lorenzobombello-api-proxy` unchanged. Use the existing-project deploy route confirmed by Wrangler 4.137.0; never run project-create.

```powershell
Push-Location cloudflare/website-project-preview-host
try {
  npx wrangler pages secret put LWS_PREVIEW_ORIGIN_TOKEN --project-name lws-website-project-preview-host
  $reviewedHead = git rev-parse HEAD
  npx wrangler pages deploy ./public --project-name lws-website-project-preview-host --branch main --commit-hash $reviewedHead --commit-message "GIT-001C reviewed preview host" --commit-dirty=false
} finally {
  Pop-Location
}
```

Acceptance: the deployment belongs to the existing project; custom domains remain empty; a request to `https://lws-website-project-preview-host.pages.dev/` returns `308` to `https://preview.lorenzowebsolutions.be/` before origin contact; direct origin without token remains `403 PREVIEW_ORIGIN_FORBIDDEN`. Before DNS exists, the redirect target is unavailable, so pages.dev cannot serve preview content. After DNS exists, the custom host without handoff/session returns `401 PREVIEW_SESSION_REQUIRED`. Responses are `private, no-store`.

Rollback: delete only the failed Pages deployment and its project secret if necessary. Keep the empty existing project, Worker and Supabase schema/functions intact for diagnosis. No DNS rollback is needed at this gate.

### Gate 4: custom domain, one OVH CNAME and host URL

Outcome 2026-09-24: **ACCEPTED AND EXECUTED**. Public preflight found no conflicting `preview` record and no apex CAA restriction while nameservers, apex, `www`, MX and TXT remained unchanged. The existing Pages association is `active/active`; Lorenzo added exactly `preview CNAME lws-website-project-preview-host.pages.dev.` in OVH. Both authoritative OVH servers and Cloudflare/Google public resolvers return that target with TTL 3600. TLS 1.3 has a valid chain and matching hostname through `2026-12-23T04:44:20Z`. The custom host returns unauthenticated `401 PREVIEW_SESSION_REQUIRED` with `private, no-store`, proving Pages-to-origin coupling; production and immutable pages.dev still redirect and direct origin remains 403. Only afterward was the exact host URL binding set and digest-verified. The existing operator runtime auto-refreshed to active version 137 with unchanged bundle digest. Positive handoff/replay, cookie and asset navigation remain required in integral Gate-5 acceptance. Gate 5 remains untouched.

Dependencies: Gate 3 accepted; public `preview.lorenzowebsolutions.be` still NXDOMAIN; apex CAA is absent or permits Cloudflare issuance. Associate the custom domain in Pages first. Only after Cloudflare reports the expected validation target, add OVH CNAME `preview` to `lws-website-project-preview-host.pages.dev`.

Acceptance: managed TLS is active; pages.dev redirects; custom host without a session is `401`; one-time handoff gives one `302` and replay is denied; HTML/CSS/image paths work; cookie is host-only `HttpOnly; Secure; SameSite=Lax; Path=/`; Storage is private; all responses are `private, no-store`. Only then set `LWS_PREVIEW_HOST_URL=https://preview.lorenzowebsolutions.be` and redeploy the existing operator command if its environment snapshot requires it.

Rollback: remove only the OVH `preview` CNAME and Pages custom-domain association, revoke preview sessions and keep apex, `www`, MX/TXT, nameservers, Supabase Auth and unrelated redirect/domain behavior unchanged.

### Gate 5: publish workflow bindings and one controlled dispatch

Preflight outcome 2026-09-24: **HARD STOP BEFORE MUTATION**. The exact platform repository and remote `main` SHA `ededdd6043c3ad749a1faf9a3993221c24fc3971` are verified, but remote `main` does not contain the preview workflow introduced locally at `35fbb65730966430d16432f8dea8ded8f655f474`. The branch is 19 commits ahead. The three required preview Actions-variables are absent and there are zero remote runs for the preview workflow path. Customer repository ID `1378797607`, exact commit and dossier binding are unchanged; all Supabase authority bindings match by digest; production has zero active previewleases/builds/tokens/upload/viewer sessions. Because publication requires a push/merge excluded from this execution, no variables, AAL2 authority or dispatch were created. Resume only after separate publication authorization and repeat this preflight before the one allowed run.

Dependencies: Gates 1-4 accepted. Add exactly the three repository variables from the table, publish the reviewed workflow on `main`, confirm `workflow_dispatch` is its only trigger, then acquire one AAL2 lease/build authority. Dispatch once with the exact server-returned lease/build IDs, customer repository ID `1378797607` and commit `1f19bf01c61c6da79fa4c7374333a91b70f9bf48`.

Acceptance: effective installation token is limited to repository ID `1378797607` and `contents:read`; checkout SHA is exact; build has no OIDC/token/service key and direct network is denied; upload/finalize succeeds; private session-bound preview reaches `PASS` or `PASS_WITH_WARNINGS`.

Rollback: disable dispatch and source-token issuance, revoke sessions, abort incomplete uploads and retry private-object cleanup. Never delete the customer repository, commit or completed build data.

## Focused local evidence

Run only when preparation files change:

```powershell
node --test scripts/git001c-release-preparation.test.mjs scripts/website-project-preview-workflow.test.mjs
deno test cloudflare/website-project-preview-host/functions/preview-host.test.ts supabase/functions/website-project-preview-host/handler.test.ts
```

Existing heavy exact-source, concurrency, upload-session, Linux manifest and operator evidence remains authoritative unless its controlling code changes.