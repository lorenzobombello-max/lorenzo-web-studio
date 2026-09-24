# GIT-001C Production Execution Runbook

Status: **GATES 1-4 EXECUTED; GATE 5 CONTROLLED RERUN FAILED IN BROWSER SERVING; LOCAL FIX ONLY, NO RETRY**. GIT-001C remains **OPEN** until live acceptance is proven.

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

Preflight outcome 2026-09-24: **HARD STOP BEFORE MUTATION**. The exact platform repository and remote `main` SHA `ededdd6043c3ad749a1faf9a3993221c24fc3971` are verified, but remote `main` does not contain the preview workflow introduced locally at `35fbb65730966430d16432f8dea8ded8f655f474`. At evidence HEAD `4290c36f44e72a16f72cd1702fa71f56e9dfd24d`, the branch is exactly 20 commits ahead and 0 behind. The three required preview Actions-variables are absent and there are zero remote runs for the preview workflow path. Customer repository ID `1378797607`, exact commit and dossier binding are unchanged; all Supabase authority bindings match by digest; production has zero active previewleases/builds/tokens/upload/viewer sessions. Because publication requires a push/merge excluded from this execution, no variables, AAL2 authority or dispatch were created. Resume only after separate publication authorization and repeat this preflight before the one allowed run.

First controlled-run outcome 2026-09-24: **FAILED IN ISOLATED BUILD; NO RETRY**. PR `#55` published the manual-only workflow. After exact variable and authority preflight, one owner-AAL2 acquire and one dispatch created run `35960635554`; fetch passed and the isolated build failed with `EACCES` on `/workspace/node_modules`. Upload was skipped, the lease was released and final active authority counts were zero. PR `#57` subsequently published the reviewed dynamic non-root UID/GID correction and moved `main` to `6e8a746385934a178a6453a43ea44b4861856e04`.

Controlled live-acceptance rerun outcome 2026-09-24: **WORKFLOW PASSED; BROWSER SERVING FAILED; NO RETRY**. Fresh preflight revalidated exact variables, no conflicting authority and unchanged dossier-0006 source. One owner-AAL2 acquire returned lease `4b6f635f-2b05-45fd-a7ed-cdab443f6bda` and authorized build ID `aa685956-91a6-4891-af75-e11c50560bc7`; exactly one dispatch returned HTTP 204 and created run `35965885425`, number 2/attempt 1. Fetch, isolated build and upload/finalize all completed success. Persisted preview build `b93a0deb-48f3-4148-b39b-a39fab94b6ea` is `PASS_WITH_WARNINGS` with six manifest artifacts and primary `index.html`. The handoff was consumed once, but authenticated root serving returned 404 `PREVIEW_ASSET_NOT_FOUND`. Database/Storage readback proves all six objects are under authorized-build prefix `aa685956-91a6-4891-af75-e11c50560bc7/`, while the host used empty preview-build prefix `b93a0deb-48f3-4148-b39b-a39fab94b6ea/`. Viewer session `ba609d11-c855-406d-b9b6-0f66a874612f` was revoked; final readback showed zero active preview leases, artifact tokens, open upload sessions and viewer sessions. Completed evidence remained intact and `NO_SECOND_CREATE` remained hard.

Local storage-prefix correction 2026-09-24: `authorized_build_id` is the canonical object prefix because acquire records it server-side before upload and database triggers bind artifact tokens/upload sessions to it. The separate `preview_build_id` remains the persistent preview/session identity. An additive migration extends the service-role-only session resolver to return `storageBuildId` through session -> preview build -> lease; all handoff-consumed, expiry and revocation checks remain unchanged and released leases remain resolvable. The host requires this value to be a UUID and uses it as its sole Storage prefix; missing/invalid values return `401 PREVIEW_SESSION_INVALID`, with no `previewBuildId` fallback. RED/GREEN evidence covers distinct IDs, `index.html`, nested `assets/app.css`, a released lease and denial of a caller-selected other build. No production action occurred and GIT-001C remains OPEN.

Publication order for this correction: (1) independently review and publish the exact main-based patch; (2) under separate migration authorization, apply only `20260924100000_resolve_website_project_preview_storage_build_id_v1.sql` and verify function body/grants plus the existing released build mapping; (3) under separate deployment authorization, deploy only `website-project-preview-host` and verify direct-origin/no-session fail-closed responses; (4) do not acquire authority or dispatch until a later explicit live-acceptance approval. Migration-first is backward-compatible because the current host ignores the added JSON field; host-first would intentionally fail closed but temporarily block valid previews. Never move existing Storage objects or add an ID fallback.

Dependencies: Gates 1-4 accepted. Add exactly the three repository variables from the table, publish the reviewed workflow on `main`, confirm `workflow_dispatch` is its only trigger, then acquire one AAL2 lease/build authority. Dispatch once with the exact server-returned lease/build IDs, customer repository ID `1378797607` and commit `1f19bf01c61c6da79fa4c7374333a91b70f9bf48`.

Acceptance: effective installation token is limited to repository ID `1378797607` and `contents:read`; checkout SHA is exact; build has no OIDC/token/service key and direct network is denied; upload/finalize succeeds; private session-bound preview reaches `PASS` or `PASS_WITH_WARNINGS`.

Rollback: disable dispatch and source-token issuance, revoke sessions, abort incomplete uploads and retry private-object cleanup. Never delete the customer repository, commit or completed build data.

#### Gate 5 publication proposal (local only, 2026-09-24)

**Compared range.** Fresh fetch confirms `origin/main=ededdd6043c3ad749a1faf9a3993221c24fc3971`, merge-base equals that SHA, and reviewed evidence HEAD is `4290c36f44e72a16f72cd1702fa71f56e9dfd24d` (20 commits ahead, 0 behind). The range changes exactly 80 files: `.github` 1, `.release` 1, `.superpowers` 1, `assets` 3, `cloudflare` 6, `docs` 3, repository root 2, `scripts` 20 and `supabase` 43. `git diff --check origin/main..4290c36f44e72a16f72cd1702fa71f56e9dfd24d` is clean. The complete path-level inventory is already recorded in the local verification checkpoint under the recovery-commit file list; later commits only amend those paths and add the release contract/runbook/release script.

**Publication unit.** Publish the complete branch range, not the workflow YAML by itself. Its runtime dependency closure is:

- workflow and isolated build/upload client: `.github/workflows/build-website-project-preview.yml`, `scripts/website-project-preview-upload.ts`, `scripts/preview-build-proxy/filter.allow`, `scripts/preview-build-proxy/tinyproxy.conf`;
- manifest and upload authority: `supabase/functions/_shared/website-project-preview-artifact-manifest.ts`, `website-project-preview-sanitizer.ts`, `website-project-preview-artifact-receipt.ts`, `website-project-preview-single-use-token.ts`, `website-project-preview-oidc-broker.ts`, plus `supabase/functions/website-project-preview-artifact/{handler.ts,index.ts}`;
- exact-source token authority: `supabase/functions/website-project-preview-source-token/{handler.ts,index.ts,service.ts}` and the already-existing shared GitHub App/key-binding modules they import;
- private preview serving: `supabase/functions/_shared/website-project-preview-{hosting-gateway,local-hosting-gateway}.ts`, `supabase/functions/website-project-preview-host/{handler.ts,index.ts}`, and `cloudflare/website-project-preview-host/{functions/[[path]].ts,public/_routes.json,wrangler.jsonc}`;
- operator acquisition/status/session wiring: `assets/js/operator-website-execution-child.mjs`, `assets/js/operator-website-preview-build.mjs`, and `supabase/functions/commercial-operator-command/{handler.ts,index.ts}`;
- database contract: all seven ordered migrations named in `.release/git001c-preview-release.json`;
- reproducibility and review evidence: the related tests, fixture, `deno.lock`, `supabase/config.toml`, value-free examples, release contract, guarded release script, plans and checkpoints in the same 20-commit range.

Selective YAML publication is rejected: the fetch job needs both proxy files; upload needs the CLI and manifest/sanitizer modules; OIDC issuance and artifact upload need the deployed source-token/artifact code and database authority; preview opening needs the operator, origin and Pages code. Gates 1-4 deployed those provider components from this range, so publishing the full range also makes `main` the source of truth for the already-live state. It does not repeat those gates.

**v1/v2 review result: not a blocker.** `supabase/functions/commercial-operator-command/index.ts` deliberately calls `finalize_website_project_preview_build_v1` for the pre-existing synchronous, one-HTML-file `service.build()` path. Migration `20260923060000_add_website_project_preview_build_finalize_and_session_v1.sql` explicitly preserves that function and caller while adding v2 for the separate in-process multi-file async orchestrator in `_shared/website-project-preview-async-build.ts`. The GitHub workflow does not use either caller: its upload CLI calls the artifact endpoint, which opens and finalizes `finalize_website_project_preview_upload_session_v1` from migration `20260923100000`. That RPC validates complete per-file receipt and persists the manifest rows. Changing the legacy caller to v2 would instead break its current argument/result contract. No v1-to-v2 code change is proposed.

**Trigger impact.** Opening a PR or pushing this feature branch triggers no repository workflow: the two deployment workflows listen only to pushes on `main`, and the preview workflow is `workflow_dispatch` only. Merging/pushing the range to `main` has these exact automatic effects:

1. `deploy-pages.yml` runs for every main push. After `production-continuity` preapproval it rebuilds the existing allowlisted GitHub Pages site and deploys it, then runs the postdeploy continuity gate. This is a separate existing production site, not the Cloudflare preview Pages project.
2. `deploy-commercial-operator-command.yml` runs because this range changes `supabase/functions/commercial-operator-command/**` and `supabase/functions/_shared/**`. After preapproval it redeploys only `commercial-operator-command`, then runs the postdeploy continuity gate.
3. `build-website-project-preview.yml` becomes visible on `main` but does not run automatically.
4. No workflow reapplies Supabase migrations, redeploys the three preview functions, writes Actions/Supabase/Cloudflare variables or secrets, deploys the Cloudflare Pages project, changes its domain, edits OVH DNS, creates a repository/project, acquires authority or dispatches a preview build.

The two automatic production jobs are therefore real merge consequences and require their normal `production-continuity` approvals. They do not repeat Gates 1-4. `NO_SECOND_CREATE` remains hard, the existing Cloudflare project ID and dossier-0006 binding remain unchanged, and GIT-001C remains open.

**Repository-level GitHub Actions variables still required.** These are plain repository Actions variables in `lorenzobombello-max/lorenzo-web-studio`, not environments and not secrets:

| Name | Exact value |
| --- | --- |
| `LWS_PREVIEW_SOURCE_TOKEN_ENDPOINT` | `https://xcsptvntvrizwhskaphr.supabase.co/functions/v1/website-project-preview-source-token` |
| `LWS_PREVIEW_ARTIFACT_ENDPOINT` | `https://xcsptvntvrizwhskaphr.supabase.co/functions/v1/website-project-preview-artifact` |
| `LWS_PREVIEW_OIDC_AUDIENCE` | `lws-preview-artifact-receipt` |

Writing these variables is a separate remote mutation. No secret value belongs in the PR, workflow or variable set.

**Fresh local validation.** Release/workflow contracts pass 4/4; operator preview/controller tests pass 89/89; Deno checks pass for the upload CLI, three preview function entry points and Cloudflare front door; editor diagnostics report no errors in those entry points or this runbook; `git diff --check` passes. The combined Windows Deno security/unit run passes 59/62; its only three failures are Windows `os error 1314` while creating the symlink fixtures, before their assertions execute. Those exact tests were then run without skips or assertion changes on the available Docker Linux engine using the workflow-pinned `denoland/deno:2.9.5` image and the current worktree mounted read-only: the complete manifest suite passes 10/10, including all three symlink cases. `git hash-object` equals `HEAD` for the manifest test (`e1d13d00e638a63617d5c196df686cb08fa8f90f`), manifest implementation (`7cc56ace5e583bdb6f4ab7e0ca1cc9454cda6b61`), sanitizer (`05f392b85b27e4ff688345404bab9e80df1786ba`) and `deno.lock` (`8c0ff4771876c0323a8173f1c933c1e9a7b14c64`). The test therefore covers the exact relevant files at reviewed HEAD `4290c36f44e72a16f72cd1702fa71f56e9dfd24d`; no older Linux result is needed for acceptance. The installed `docker-desktop` WSL2 distribution itself has no directly callable Deno binary or `/mnt/c` worktree mount, so Docker was the available Linux execution boundary.

**Remaining blockers.** Remote `main` still lacks the workflow; all three repository Actions variables are still absent; the local documentation amendment is committed but not pushed; merge-triggered Pages and operator deployments still require their normal production approvals. After publication/configuration, Gate 5 still requires a fresh preflight and separate authority-acquire/one-dispatch permission. These are publication/governance blockers, not a v1/v2 code blocker.

**Proposed publication sequence requiring explicit permission.** First authorize one push of the reviewed feature branch, including the local publication-preparation commit, and creation of a PR; this has no repository workflow trigger. Review the exact remote head and required checks. Separately authorize merge to `main`, accepting the two production workflows above. Separately authorize the three repository-variable writes. Only after remote workflow/ref/variables are re-read and match the contract may a later Gate-5 approval acquire one AAL2 authority and dispatch dossier-0006 once. Merge, variable write, authority acquisition and dispatch must not be bundled into the publication approval.

**Prepared PR title:** `feat: publish controlled GIT-001C preview build pipeline`

**Prepared PR body:**

```markdown
## Scope

Publishes the complete GIT-001C async preview-build implementation and evidence from `ededdd6043c3ad749a1faf9a3993221c24fc3971` through reviewed evidence SHA `4290c36f44e72a16f72cd1702fa71f56e9dfd24d`. This intentionally includes the workflow, upload/proxy scripts, operator wiring, Supabase functions/shared modules, seven additive migrations, Cloudflare preview host, tests, fixtures and release documentation. Publishing only the workflow YAML is not supported.

## Production state

Gates 1-4 were already executed and are not repeated by this PR. The existing Cloudflare Pages project and `preview.lorenzowebsolutions.be` binding remain unchanged; `NO_SECOND_CREATE` is hard. Dossier-0006 remains bound to repository ID `1378797607` and commit `1f19bf01c61c6da79fa4c7374333a91b70f9bf48`. GIT-001C remains open.

## Merge effects

- PR creation and feature-branch push trigger no workflows.
- Merge to `main` triggers the existing GitHub Pages deployment for every main push.
- Merge to `main` also triggers the existing `commercial-operator-command` deployment because shared/function paths changed.
- Both production workflows retain their `production-continuity` gates.
- The new preview workflow is manual-only and will not dispatch on merge.
- No migration, preview-function deployment, Cloudflare/OVH mutation, project creation, authority acquisition or preview dispatch is performed by this PR.

## Review note: v1/v2 finalization

The v1 call in `commercial-operator-command/index.ts` is the intentionally preserved synchronous single-file path. The published workflow finalizes through the artifact upload-session RPC; the separate in-process async orchestrator calls v2. No v1/v2 correction is needed.

## Required post-merge configuration

Three repository-level Actions variables remain a separately approved write: `LWS_PREVIEW_SOURCE_TOKEN_ENDPOINT`, `LWS_PREVIEW_ARTIFACT_ENDPOINT`, and `LWS_PREVIEW_OIDC_AUDIENCE`. They contain endpoint/audience values only; no secret is added.

## Validation

- release/workflow contract tests: 4/4 pass
- operator preview/controller tests: 89/89 pass
- preview security/unit tests: 59/62 pass on Windows; only the three symlink-fixture cases are blocked by Windows privilege error 1314; the exact current manifest suite passes 10/10 on Linux with no skips
- Deno type checks pass for the workflow upload client, three deployed function entry points and Cloudflare front door
- editor diagnostics and `git diff --check` are clean

## Rollback

Before dispatch, remove/disable the workflow or its three repository variables. If the merge-triggered existing deployments regress, use their established continuity-gated rollback; do not roll back additive Gate-1 migrations or recreate/delete provider resources. No customer repository, dossier binding, DNS record or Cloudflare project is changed by this PR.
```

## Focused local evidence

Run only when preparation files change:

```powershell
node --test scripts/git001c-release-preparation.test.mjs scripts/website-project-preview-workflow.test.mjs
deno test cloudflare/website-project-preview-host/functions/preview-host.test.ts supabase/functions/website-project-preview-host/handler.test.ts
```

Existing heavy exact-source, concurrency, upload-session, Linux manifest and operator evidence remains authoritative unless its controlling code changes.