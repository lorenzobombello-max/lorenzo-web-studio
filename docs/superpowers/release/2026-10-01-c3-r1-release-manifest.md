# C3-R1 release manifest - 2026-10-01

Status: **REVIEWABLE LOCALLY; EVERY EXTERNAL MUTATION REMAINS UNAUTHORIZED**.

This manifest is a control artifact. It is not part of the 77-file release payload. No commit, push, merge, remote migration, migration repair, deploy, App/configuration change, workflow run, fixture or trial was performed while preparing it.

## 1. Release identity and boundaries

- Repository: `lorenzobombello-max/lorenzo-web-studio` (repository ID `1320223175`).
- Supabase project: `xcsptvntvrizwhskaphr`.
- Release worktree: `C:\Users\info\Project-Worktrees\lorenzo-web-studio-c3-r1-release-20261001`.
- Worktree state: detached and uncommitted by design.
- Exact base and remote `main` at preparation time: `b3980407c7e90d66c432d4dc6284398aeaa213ca`.
- Payload: exactly 77 changed/untracked files relative to the base: 46 selected migrations and 31 runtime/workflow/config/assets files.
- Complete payload identity: SHA-256 `70df0e9d309ba197fb20529f6f90f71b1e20ad75aced8bd6589f40a48fec5264` over the 77 sorted lines `<prospective-git-blob><two spaces><relative-path><LF>`, using `git hash-object --path` so repository filters are applied.
- Review control artifact: this manifest, excluded from the 77-file payload count.
- Explicitly excluded migration: `20260927004000_fix_operator_application_detail_transaction_mode.sql`.
- Explicitly excluded deployable: `website-delivery-pdf-orphan-cleanup`; its SQL safeguards remain in the selected migration chain, but the Edge Function remains undeployed and unscheduled.
- Local Supabase link marker `supabase/.branches/_current_branch` and validation scratch data are excluded.

## 2. Historical migration recovery

`supabase/migrations/20260924100000_resolve_website_project_preview_storage_build_id_v1.sql` already exists in the pinned remote-main base and was restored into the dirty source worktree from that exact Git object. It was not reconstructed or retyped.

- Source commit: `b3980407c7e90d66c432d4dc6284398aeaa213ca`.
- Git blob: `bda9bf5e7d8eb62db613bab65b8ba394f8124a55`.
- Canonical LF SHA-256: `1f0efeffacd99e518a81d873380b44bdd5c2fe9a924e90b8cc3228ac77b90a4c`.
- Windows CRLF worktree SHA-256: `de0fc9c6f668cba45c788a656b51e71552e0a49f84f2b72a50c7baae9d75d1af`.
- Git canonical blob comparison: exact match.
- Remote ledger statement SHA-256 values, in stored order:
  - `877753226a1a872ad06cae8887ecf7927ad1a0f0e8d154f1ae0a6ccfae6a6102`
  - `9e09779ff5234b0bbc24b9f58cff6a4e8d9c2ca0a52a6099c2ace6ca00e77bdf`
  - `c09693945af494ccfaff25e0033410f65f309694f02b1f3cf36f766cb05f26a7`

The ledger stores a parsed statement array, not the original file bytes, so its serialization is not claimed to equal the Git file representation. Both identities are retained. The migration makes `resolve_website_project_preview_session_v1(text)` resolve `storageBuildId` through lease `authorized_build_id`, revokes public/anon/authenticated access and grants service-role execution.

## 3. Exact selected migration order

The release applies these 46 remote-absent migrations, in this order:

1. `20260923130000_promote_official_website_quotation_template_v2.sql`
2. `20260926120000_add_website_commercial_document_concepts_v1.sql`
3. `20260927003000_add_website_agreement_registration_status_v1.sql`
4. `20260927005000_add_website_quotation_payment_term_release_gate_v1.sql`
5. `20260927006000_add_website_document_flow_operator_routes_v1.sql`
6. `20260927007000_add_website_preview_ready_from_build_v1.sql`
7. `20260928000000_add_commercial_customer_preview_session_v1.sql`
8. `20260928001000_add_commercial_customer_approval_gateway_v1.sql`
9. `20260928002000_harden_commercial_customer_approval_replay_v1.sql`
10. `20260928003000_add_website_delivery_document_package_1_v1.sql`
11. `20260928004000_require_website_delivery_legal_form_v1.sql`
12. `20260928005000_add_quotation_identity_legal_form_v1.sql`
13. `20260928006000_preserve_quotation_identity_v1_compatibility.sql`
14. `20260928007000_add_website_delivery_document_viewing_package_2_v1.sql`
15. `20260928008000_add_customer_delivery_document_view_resolution_v1.sql`
16. `20260928009000_add_operator_delivery_document_view_resolution_v1.sql`
17. `20260928010000_revalidate_current_delivery_document_receipts_v1.sql`
18. `20260928011000_bind_customer_acceptance_to_viewed_delivery_document_v1.sql`
19. `20260928012000_prepare_delivery_document_before_customer_acceptance_v1.sql`
20. `20260928013000_serialize_customer_acceptance_replay_v1.sql`
21. `20260928014000_freeze_delivery_document_registration_after_acceptance_v1.sql`
22. `20260929001000_add_website_delivery_pdf_conversion_tasks_v1.sql`
23. `20260929002000_add_website_delivery_pdf_conversion_execution_v1.sql`
24. `20260929003000_fix_website_delivery_pdf_claim_replay_result_v1.sql`
25. `20260929004000_add_website_delivery_pdf_conversion_recovery_v2.sql`
26. `20260929005000_serialize_website_delivery_pdf_completion_takeover_v2.sql`
27. `20260929006000_harden_website_delivery_pdf_completion_v3.sql`
28. `20260929007000_add_website_delivery_pdf_orphan_cleanup_v1.sql`
29. `20260929007500_repair_website_delivery_pdf_c1_review_v1.sql`
30. `20260929007600_reject_incomplete_pdf_cleanup_workflow_claims_v1.sql`
31. `20260929008000_add_website_delivery_pdf_dispatch_authority_v1.sql`
32. `20260929008100_converge_website_delivery_pdf_dispatch_authority_v1.sql`
33. `20261001001000_add_website_delivery_pdf_recovery_authority_v1.sql`
34. `20261001002000_distinguish_website_delivery_pdf_rerun_policy_v1.sql`
35. `20261001003000_remove_negative_readback_redispatch_authority_v1.sql`
36. `20261001004000_bind_accepted_website_delivery_pdf_run_v1.sql`
37. `20261001005000_stabilize_website_delivery_pdf_run_inspection_v1.sql`
38. `20261001006000_reconcile_website_delivery_pdf_recovery_v1.sql`
39. `20261001007000_close_website_delivery_pdf_recovery_visibility_v1.sql`
40. `20261001008000_serialize_website_delivery_pdf_recovery_cleanup_v1.sql`
41. `20261001009000_advance_website_delivery_pdf_recovery_provider_status_v1.sql`
42. `20261001010000_reject_incomplete_website_delivery_pdf_provider_completion_v1.sql`
43. `20261001011000_add_website_delivery_pdf_c3_trial_authority_v1.sql`
44. `20261001012000_repair_website_delivery_pdf_c3_trial_pricing_v1.sql`
45. `20261001013000_repair_website_delivery_pdf_c3_trial_identity_v1.sql`
46. `20261001014000_repair_website_delivery_pdf_c3_trial_issuance_v1.sql`

## 4. Exact non-migration payload

The other 31 payload files are:

- `.github/workflows/convert-website-delivery-pdf.yml`
- `deno.lock`
- `scripts/website-delivery-pdf/conversion-task-http-runner.ts`
- `scripts/website-delivery-pdf/conversion-task-runner.ts`
- `scripts/website-delivery-pdf/libreoffice-pdf-exporter.ts`
- `scripts/website-delivery-pdf/libreoffice/Dockerfile`
- `scripts/website-delivery-pdf/run-conversion-task.ts`
- `supabase/config.toml`
- `supabase/functions/_shared/github-app-config.ts`
- `supabase/functions/_shared/github-app-token.ts`
- `supabase/functions/_shared/website-delivery-pdf-oidc.ts`
- `supabase/functions/_shared/website-delivery-pdf-session.ts`
- `supabase/functions/_shared/website-delivery-pdf-transfer.ts`
- `supabase/functions/_shared/website-delivery-pdf-validation.ts`
- `supabase/functions/_shared/website-delivery-pdf-workflow-dispatch.ts`
- `supabase/functions/_shared/website-delivery-pdf-workflow-starter.ts`
- `supabase/functions/commercial-operator-command/handler.ts`
- `supabase/functions/commercial-operator-command/index.ts`
- `supabase/functions/commercial-operator-command/quotation-runtime.ts`
- `supabase/functions/commercial-operator-command/website-commercial-renderer-edge.ts`
- `supabase/functions/commercial-operator-command/website-delivery-renderer-edge.ts`
- `supabase/functions/commercial-operator-command/website-quotation-renderer-edge.ts`
- `supabase/functions/commercial-operator-command/assets/LWS_WEBSITE_AGREEMENT_NL_BE_CONCEPT_v1.docx`
- `supabase/functions/commercial-operator-command/assets/LWS_WEBSITE_DELIVERY_DOCUMENT_OPL_W_01_v1.docx`
- `supabase/functions/commercial-operator-command/assets/LWS_WEBSITE_DELIVERY_DOCUMENT_OPL_W_01_v2.docx`
- `supabase/functions/commercial-operator-command/assets/LWS_WEBSITE_INVOICE_FINAL_REMAINDER_NONPRODUCTION_v1.docx`
- `supabase/functions/commercial-operator-command/assets/LWS_WEBSITE_INVOICE_M1_40_NONPRODUCTION_v1.docx`
- `supabase/functions/commercial-operator-command/assets/LWS_WEBSITE_INVOICE_M2_40_NONPRODUCTION_v1.docx`
- `supabase/functions/commercial-operator-command/assets/LWS_WEBSITE_QUOTATION_NL_BE_OFFICIAL_v1.docx`
- `supabase/functions/website-delivery-pdf-conversion/handler.ts`
- `supabase/functions/website-delivery-pdf-conversion/index.ts`

`supabase/config.toml` differs from the pinned base only by the `website-delivery-pdf-conversion` function entry with `verify_jwt = false`. No orphan-cleanup entry is included.

## 5. Pinned hashes

- Workflow: `3d0daa3fdaf8cd801a0e391a654cf1b59490373c120757b03f9ed77aca78c569`.
- `deno.lock`: `73d483523d1e6f887dd1414d7974d850ecdd0c3d9b1a592db12c1298ac9bfca9`.
- `supabase/config.toml`: `d1f85c932a293ac43cc2324e97a6f29978a9d4cac368562a489fe833096d85b8`.
- Conversion entrypoint: `ac1dcba038edd853a2761f1fb680a18e27bfc704cbd700301b297ce9e68b577d`.
- Operator entrypoint: `b15f755c97da948c288b45f7c6dea10da64a666e80ddcc7bde99c5e95db52730`.
- Workflow runner entrypoint: `2e3cc8f729a84c6d64e3088ab38fe089686fcbb985a16c5b0f8f9321c8f5ca12`.
- Final selected migration `20261001014000`: `9ce6347d3fbc54eacd16978f7749e5127c8884ad638b09fd9bd783a4d2fff68c`.

The lock gained the 31 entrypoint-specific dependency records required for frozen resolution, including the existing `docxtemplater`, `pizzip` and `pdf-parse` dependency graph. It was then verified with `--frozen`.

## 6. Applicability evidence

### Isolated database

A temporary DB-only Supabase stack on isolated ports replayed the exact remote-main migration baseline through `20260924100000`, then applied the 46 selected migrations in order. The recovered resolver still selected lease `authorized_build_id`. The focused C3 pgTAP transaction returned 36/36 `ok` and was rolled back. The temporary stack was stopped and deleted with no backup.

One historical data-state dependency is not reproducible from an empty database: `20260903190000_bind_operator_profiles_to_auth_users_v1.sql` requires three fixed, confirmed Auth identities already present in production. The isolated baseline therefore inserted only those three prerequisite Auth rows, using the identities referenced by the historical migration, before replay continued. No production data was copied. This proves the selected set against the reproduced remote schema and explicit prerequisites; it does not claim that the full historical baseline can replay from a data-empty database.

### Remote linked dry run

From this selected release worktree:

```powershell
npx supabase db push --linked --include-all --dry-run --workdir C:\Users\info\Project-Worktrees\lorenzo-web-studio-c3-r1-release-20261001
```

The linked project reported exactly the 46 filenames in section 3, in the same order, with `seeds: []`, `roles: []` and `dryRun: true`. It proposed no unrelated migration and performed no mutation.

### Runtime checks

All exact release entrypoints passed frozen Deno resolution:

```powershell
deno check --node-modules-dir=auto --frozen supabase/functions/website-delivery-pdf-conversion/index.ts
deno check --node-modules-dir=auto --frozen supabase/functions/commercial-operator-command/index.ts
deno check --node-modules-dir=auto --frozen scripts/website-delivery-pdf/run-conversion-task.ts
```

The previously established focused implementation evidence remains 36/36 pgTAP, 9/9 hold/runtime checks and 2/2 operator handler/transport checks. Untouched broad suites were deliberately not repeated for this packaging pass.

## 7. Rollback artifact

The currently deployed operator was read-only downloaded before any future replacement:

- Remote function: `commercial-operator-command`.
- Current remote deployment ID: `e4a8f354-530a-4b08-be8b-feeb722ce876`.
- Current remote version: `138`.
- Current remote digest: `8b3c20f71c0cf501ce78cf8ceed84df2886747fe32d7332448ede862d8afcae2`.
- Local source artifact: `C:\Users\info\Project-Worktrees\lorenzo-web-studio-c3-r1-rollback-v138-20261001`.
- Source files/assets: 46; generated Supabase link metadata excluded.
- Deterministic aggregate SHA-256 over sorted lines `<file-sha256><two spaces><relative-path><LF>`: `1a0d70c3ed3ac43dfa43802b2dff88cf956cfb14608d2d948a0dbceea48d943a`.
- Secret scan: no `.env`, PEM/key file or token/private-key value was present. Three pattern hits were PEM header/footer literals in `github-app-private-key.ts`, not key material.

The CLI can redeploy this exact downloaded source but cannot select existing deployment version 138 by ID. A redeploy creates a new function version and may produce a different provider digest after rebundling. If byte-identical provider-version rollback is a release requirement, authenticated Supabase version-rollback capability must be proven before operator deployment; otherwise the accepted recovery unit is the pinned 46-file source artifact.

## 8. Authenticated GitHub readback - 2026-10-01

The repository identity was re-read as `lorenzobombello-max/lorenzo-web-studio`. A direct read-only remote-ref query returned `refs/heads/main` at `b3980407c7e90d66c432d4dc6284398aeaa213ca`, exactly the pinned release base. There is no head drift and the 77-file payload and SHA-256 `70df0e9d309ba197fb20529f6f90f71b1e20ad75aced8bd6589f40a48fec5264` remain unchanged.

Authenticated repository Admin readback completed through the shared browser without any write. The repository GitHub Apps page lists only `ChatGPT Codex Connector` (installation `132899593`) and `Linear Code` (installation `133131987`). Neither is the dedicated website-delivery-PDF dispatch App. Therefore the required dedicated App identity/installation, selected-repository grant to `lorenzobombello-max/lorenzo-web-studio`, and exact `metadata:read` plus `actions:write` installation permissions are **ABSENT**, not `UNKNOWN`. No existing App was opened, reconfigured or reused.

Repository Actions settings are:

- all actions and reusable workflows allowed;
- full-length action-SHA pinning not required;
- default `GITHUB_TOKEN` permissions limited to read repository contents and packages;
- GitHub Actions may not create or approve pull requests;
- the conversion workflow remains absent from `main`, so it has no prior enabled/run state.

This repository policy is compatible with the candidate workflow's explicit `contents:read` and `id-token:write`, but it does not supply the separate GitHub App `actions:write` permission needed for workflow dispatch.

Only configuration names and scopes were recorded; no secret value was opened or stored. Existing Actions configuration is:

- environment variable in `production-continuity`: `LWS_SUPABASE_PUBLISHABLE_KEY`;
- repository variables: `LWS_PREVIEW_ARTIFACT_ENDPOINT`, `LWS_PREVIEW_OIDC_AUDIENCE`, `LWS_PREVIEW_SOURCE_TOKEN_ENDPOINT`, `LWS_SUPABASE_PROJECT_REF`, `LWS_SUPABASE_PUBLISHABLE_KEY`;
- environment secrets in `production-continuity`: `LWS_RELEASE_SMOKE_EMAIL`, `LWS_RELEASE_SMOKE_PASSWORD`;
- repository secret: `SUPABASE_ACCESS_TOKEN`.

Required repository variable `LWS_DELIVERY_PDF_CONVERSION_ENDPOINT` is **ABSENT**. The conversion workflow requires no Actions secret, and no `LWS_DELIVERY_PDF_*` Actions secret exists. This closes the authenticated readback; it does not authorize creating the missing App, installation, permission grant or variable.

The workflow reads one GitHub Actions variable, `LWS_DELIVERY_PDF_CONVERSION_ENDPOINT`, and no Actions secret. The Supabase runtime contract uses nine production names before normal dispatch:

- `LWS_DELIVERY_PDF_DISPATCH_APP_ID`
- `LWS_DELIVERY_PDF_DISPATCH_INSTALLATION_ID`
- `LWS_DELIVERY_PDF_DISPATCH_PRIVATE_KEY`
- `LWS_DELIVERY_PDF_OIDC_AUDIENCE`
- `LWS_DELIVERY_PDF_WORKFLOW_REPOSITORY`
- `LWS_DELIVERY_PDF_WORKFLOW_REPOSITORY_ID`
- `LWS_DELIVERY_PDF_WORKFLOW_REF`
- `LWS_DELIVERY_PDF_WORKFLOW_REF_NAME`
- `LWS_DELIVERY_PDF_SESSION_SECRET`

The three `LWS_DELIVERY_PDF_C3_TEST_HOLD_*` names stay absent until a separately approved TEST_ONLY trial. `LWS_DELIVERY_PDF_ORPHAN_CLEANUP_TOKEN` stays absent because cleanup is not released.

### Publication trigger preflight

The exact repository workflow set was inspected before branch creation and push:

- `build-website-project-preview.yml`: `workflow_dispatch` only;
- candidate `convert-website-delivery-pdf.yml`: `workflow_dispatch` only, with no schedule;
- `deploy-commercial-operator-command.yml`: push only to `main` and only for its bounded path list, plus `workflow_dispatch`;
- `deploy-pages.yml`: push only to `main`, plus `workflow_dispatch`.

No repository workflow has a `pull_request`, `pull_request_target`, release-branch push, `workflow_run` or schedule trigger. A push to `release/c3-r1-20261001` and opening a draft PR against `main` therefore start no repository workflow, deployment, PDF conversion or production action. The GitHub-generated `pages-build-deployment` can follow a Pages deployment but has no independent release-branch/PR trigger; this step does not start its parent Pages workflow. This conclusion applies only while the remote workflow set and trigger definitions remain unchanged. Drift before push is a hard stop. No workflow, repository protection or Actions setting was changed for this preflight.

## 9. One proposed external change sequence

This is one proposal, not an authorization:

1. Review the 77-file payload plus this control manifest, create one release branch/commit from the pinned base and open a PR. Do not merge yet.
2. Re-read remote `main`, Supabase ledger, latest completed backup and function identities. Re-run the selected linked dry run. Stop on any drift or filename/order difference.
3. Obtain a separate migration approval and apply exactly the 46 forward migrations. Read back the exact ledger and critical schema/functions. Never use migration repair, reset, down migration or compensating DML.
4. Merge only the reviewed release commit. This publishes a `workflow_dispatch`-only workflow; do not run it.
5. Under a separate App/configuration approval, create one dedicated dispatch App, install it only for repository `lorenzobombello-max/lorenzo-web-studio`, grant exactly `metadata:read` and `actions:write`, and read back App ID, installation ID, selected repository and exact permissions. Do not reuse or alter the two existing unrelated Apps.
6. Set only the nine approved Supabase runtime names without echoing values. Keep all three hold names and the cleanup name absent; read back names only.
7. Deploy `website-delivery-pdf-conversion`; read back ID/version/digest and `verify_jwt=false`. Then create only `LWS_DELIVERY_PDF_CONVERSION_ENDPOINT` as a repository Actions variable and read back its name. Do not add an Actions secret.
8. Deploy `commercial-operator-command` last; read back ID/version/digest and `verify_jwt=false`.
9. Stop. Fixture creation, initial automatic dispatch, normal cancellation and same-run rerun each retain their separate trial approvals.

Hard stops: base/head drift, dirty or extra payload, hash mismatch, extra dry-run migration, backup failure, migration/readback error, App repository or permission mismatch, ambiguous configuration, failed function readback, workflow run, unexpected dispatch or any unauthorized mutation.

## 10. Commands for a separately approved release

### Review and publication

Recompute the payload identity before staging; the result must be the pinned 77-file SHA-256 from section 1:

```powershell
$release = 'C:\Users\info\Project-Worktrees\lorenzo-web-studio-c3-r1-release-20261001'
$control = 'docs/superpowers/release/2026-10-01-c3-r1-release-manifest.md'
$paths = @(git -C $release status --porcelain=v1 --untracked-files=all | ForEach-Object { $_.Substring(3) } | Where-Object { $_ -notmatch 'node_modules|\.c3-r1-validation' -and $_ -ne $control } | Sort-Object)
$lines = @($paths | ForEach-Object { $blob = git -C $release hash-object --path=$_ -- $_; "$blob  $_" })
[Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n"))).ToLowerInvariant()
```

```powershell
git -C $release switch -c release/c3-r1-20261001
git -C $release add -- .github/workflows/convert-website-delivery-pdf.yml deno.lock scripts/website-delivery-pdf supabase/config.toml supabase/functions/_shared supabase/functions/commercial-operator-command supabase/functions/website-delivery-pdf-conversion supabase/migrations docs/superpowers/release/2026-10-01-c3-r1-release-manifest.md
git -C $release diff --cached --check
git -C $release commit -m "release: prepare website delivery PDF C3-R1"
git -C $release push --set-upstream origin release/c3-r1-20261001
```

The staged-file review must still prove that only the 77 payload files plus this one control artifact are present before commit. PR creation and merge require separate authorization.

### Migration and deploy

```powershell
npx supabase link --project-ref xcsptvntvrizwhskaphr --workdir $release --yes
npx supabase db push --linked --include-all --dry-run --workdir $release
npx supabase db push --linked --include-all --workdir $release --yes
npx supabase functions deploy website-delivery-pdf-conversion --project-ref xcsptvntvrizwhskaphr --no-verify-jwt --use-api --workdir $release
npx supabase functions deploy commercial-operator-command --project-ref xcsptvntvrizwhskaphr --no-verify-jwt --use-api --workdir $release
npx supabase functions list --project-ref xcsptvntvrizwhskaphr --output json
```

Before the function commands, set only the approved names from a protected operator-local env file; do not commit that file or print its contents:

```powershell
npx supabase secrets set --env-file <approved-c3-r1-runtime-env-file> --project-ref xcsptvntvrizwhskaphr
npx supabase secrets list --project-ref xcsptvntvrizwhskaphr --output json
```

After authenticated GitHub readback, install `gh` or use an equivalent authenticated connector. If the endpoint variable was proven absent and its write is separately approved:

```powershell
gh variable set LWS_DELIVERY_PDF_CONVERSION_ENDPOINT --repo lorenzobombello-max/lorenzo-web-studio --body "<approved-conversion-endpoint>"
gh variable list --repo lorenzobombello-max/lorenzo-web-studio
```

Do not deploy `website-delivery-pdf-orphan-cleanup`. Do not set any hold binding in this release phase.

### Recovery

Delete a newly introduced conversion function if its deploy/readback fails:

```powershell
npx supabase functions delete website-delivery-pdf-conversion --project-ref xcsptvntvrizwhskaphr
```

Restore the pinned operator source if the new operator deployment fails and source-level redeploy recovery has been accepted:

```powershell
$rollback = 'C:\Users\info\Project-Worktrees\lorenzo-web-studio-c3-r1-rollback-v138-20261001'
npx supabase functions deploy commercial-operator-command --project-ref xcsptvntvrizwhskaphr --no-verify-jwt --use-api --workdir $rollback
npx supabase functions list --project-ref xcsptvntvrizwhskaphr --output json
```

Remove only names proven absent before this package and newly added by it:

```powershell
npx supabase secrets unset LWS_DELIVERY_PDF_DISPATCH_APP_ID LWS_DELIVERY_PDF_DISPATCH_INSTALLATION_ID LWS_DELIVERY_PDF_DISPATCH_PRIVATE_KEY LWS_DELIVERY_PDF_OIDC_AUDIENCE LWS_DELIVERY_PDF_WORKFLOW_REPOSITORY LWS_DELIVERY_PDF_WORKFLOW_REPOSITORY_ID LWS_DELIVERY_PDF_WORKFLOW_REF LWS_DELIVERY_PDF_WORKFLOW_REF_NAME LWS_DELIVERY_PDF_SESSION_SECRET --project-ref xcsptvntvrizwhskaphr
```

Restore workflow absence with a reviewed revert of the release merge and preserve Actions logs/evidence:

```powershell
git revert <release-merge-sha>
git push origin main
```

Delete `LWS_DELIVERY_PDF_CONVERSION_ENDPOINT` only if authenticated preflight proved it absent before release and this package created it:

```powershell
gh variable delete LWS_DELIVERY_PDF_CONVERSION_ENDPOINT --repo lorenzobombello-max/lorenzo-web-studio
```

Restore/remove a GitHub App installation only from the authenticated baseline recorded before mutation. Additive database changes and immutable evidence remain in place; there is no database rollback command.
