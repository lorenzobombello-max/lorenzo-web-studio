# Website Execution Project Files Phase A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add repository-backed, bounded, read-only Projectbestanden to the existing Website Execution Workspace without giving the browser repository authority or exposing any repository mutation path.

**Architecture:** Keep `dossiers:website-<quote_request_id>` as the only managed Website child and mount one internal Projectbestanden controller in that child. Route exact browser intent through `commercial-operator-command`; resolve owner+AAL2, work context, workspace, repository binding, immutable commit, limits, and provider reads on the server before returning normalized inert DTOs. Preserve the deployed v118 workspace-provisioning source before any backend edit and stop if the separately reviewed repository binding/provider prerequisites are not available on the selected implementation baseline.

**Tech Stack:** PostgreSQL/Supabase forward-only migrations, forced RLS, pgTAP, Deno Edge Functions and tests, Supabase JS caller-JWT clients, GitHub App installation tokens and Git Data REST reads, static JavaScript ES modules, Node test runner, Playwright, HTML/CSS.

**Spec:** `docs/superpowers/specs/2026-09-17-website-execution-build-workspace-design.md`

## Global Constraints

- Implement only Phase A: repository-backed, read-only Projectbestanden inside the existing Website Execution Workspace.
- Keep exactly one managed Website child and slot: `dossiers:website-<quote_request_id>` / `website-<quote_request_id>`. Add no build, files, or editor module registration.
- Exclude Phase B local launcher, Phase C preview/build, Phase D popup/window handoff, Task14, repository creation/provisioning, browser editor, browser write/delete/rename, commits, pushes, publication, and production release.
- Treat the browser as untrusted intent. List requests contain only `action`, `quote_request_id`, `path`, and `cursor`; read requests contain only `action`, `quote_request_id`, and `path`.
- Never accept browser-supplied work-context/workspace/project IDs, repository coordinates/external ID/installation, provider, branch/ref/commit, credentials, provider host, or local path.
- Resolve caller JWT -> authenticated active human -> OWNER -> AAL2 -> quote request -> website work context -> execution workspace -> `REPOSITORY_READY` -> canonical binding/revision/external ID/ref -> immutable commit -> provider read on every operation.
- `project_id` remains nullable and is never required for PRE_PROJECT. Authority is `website_work_context_id` plus the execution workspace.
- Directory traversal is lazy. A page contains at most 500 entries and 512 KiB serialized data; cursors expire after five minutes and bind caller, context, repository, binding revision, commit, directory, and offset.
- A direct file read resolves the current canonical ref again. The UI never combines a tree snapshot and file content snapshot after their commit SHAs diverge.
- File content is strict UTF-8 only, at most 1 MiB after provider transport decoding and before UTF-8 interpretation. No truncation, binary bytes, data/object URL, provider temporary URL, or download endpoint is allowed.
- Secret paths/content, symlinks, submodules, Git links, redirects, malformed provider data, unavailable classifier, stale binding, and cross-context substitution fail closed before content return.
- Use server-projected allowlisted navigation for GitHub. Do not extend Phase A with VS Code, Build, or Preview controls.
- Repository content is rendered only through `textContent`/text nodes and is never persisted in localStorage, sessionStorage, IndexedDB, service-worker caches, URLs, or fragments.
- Use synthetic IDs only. Do not use any production dossier reference, quote UUID, work-context UUID, workspace UUID, repository name, or external repository ID in tests.
- Do not edit existing committed migrations. Add forward-only migration(s).
- Do not clean unrelated formatter, MFA, lockfile, auth-bootstrap, or baseline debt. Compare release results to the recorded baseline where a repository-wide gate has pre-existing failures.
- Every implementation task is local-only and ends at its stated commit boundary. Push, deploy, remote migration, repository creation, provider write, and business mutation remain separately prohibited.

## Reviewed Baseline and Mandatory Stop Gates

Planning inspection on 2026-09-17 established:

```text
ORIGINAL_PLAN_SPEC_HEAD=c23479676a3a48a19cfe70fcf2a13ddf94080c82
PREVIOUS_PLAN_COMMIT=270e60f904503af96bbb1a78ffb72c1ce010a132
AMENDED_SPEC_HEAD=325fadf50d3c17ffa89b9d77bbd71cb6ae227727
REMOTE_MAIN_HEAD=f94888318c74e79bf5e148d81d3eb892907798b8
DEPLOYED_V118_SOURCE=7c7672980d31a92fea124727b41ca5eef6eec005
DEPLOYED_V118_PARENT=f94888318c74e79bf5e148d81d3eb892907798b8
```

The reviewed baseline does not contain the v118 gateway delta. It also does not contain the later Task13 GitHub App/token/HTTP/repository-binding stack. The exact prerequisite provenance is:

| Commit | Required pre-existing responsibility | Files Phase A may consume |
|---|---|---|
| `8bd8f04c13d8fae856ee5088f7f6570e9ce20576` | Versioned repository contract | `supabase/functions/_shared/repository-provisioning.ts` types only; no command invocation |
| `392e56379c73385a0137a960d615ca7d54056727` | GitHub App configuration | `supabase/functions/_shared/github-app-config.ts` |
| `96ced670d823ae7f1dd0cc8dcb7af7f9b97a80ba` | Repository-ID-scoped App token broker | `supabase/functions/_shared/github-app-token.ts` |
| `879e1a41840106368b3a4be4757ee07ac47ac29a` | Bounded GitHub HTTP transport | `supabase/functions/_shared/github-http.ts` |
| `c3619f0d6185b98cfb92c0af390ce0ecf5bb729f` | Repository lifecycle schema | `supabase/migrations/20260914090000_add_website_repository_provisioning_v1.sql` read model |
| `2f4c193a5427b599f7b7b580ca513e2c9c451618` | Canonical claim/binding RPCs | `supabase/migrations/20260914090000_add_website_repository_provisioning_v1.sql` binding fields and constraints |
| `ffd65a6b6cfab2595d67f3724b5c4c913db6799a` | Reconciliation/quarantine authority | `supabase/migrations/20260914090000_add_website_repository_provisioning_v1.sql` normalized lifecycle state |
| `4dd420b4510df55642a8b1e2e1b91dfc4a61155e` | Hardened private-key/token/ref/provider tests | `supabase/functions/_shared/github-app-private-key.ts`, `supabase/functions/_shared/github-installation-token.ts`, `supabase/functions/_shared/github-ref-read-diagnostic.ts`, and tests for the read primitives |

These commits also contain repository-provisioning and test-island behavior outside Phase A. This plan never integrates that range itself.

```text
EXECUTABLE_PREREQUISITE_MODE=EXACT_ANCESTRY_ONLY
NO_SECOND_CREATE=HARD
```

Execution has two mandatory stop gates:

1. Re-prove and preserve v118 before editing either commercial gateway file.
2. Obtain a controller-approved implementation baseline on which every exact commit in the prerequisite table is an ancestor. It must supply canonical `repository_external_id`, node/marker identity, `REPOSITORY_READY`, binding revision, and the audited read-only GitHub App primitives. If any ancestry proof fails, Phase A stops after v118 reconciliation.

This Phase A plan does not forward-port, cherry-pick subsets, copy source, or accept inferred, squashed, patch-ID, or patch-equivalent prerequisites. None of those mechanisms satisfies the ancestry gate. If exact ancestry cannot be obtained, a separate controller-approved prerequisite integration plan must produce a new reviewed baseline SHA; this Phase A plan must then be revalidated against that exact baseline before execution. No second binding/create authority may be reconstructed. `CREATE_REPOSITORY`, `CREATE_BLOB`, `CREATE_TREE`, `CREATE_COMMIT`, `CREATE_REF`, `UPDATE_REF`, `WRITE_PROJECT_MARKER`, and every provisioning service/store/router remain unreachable and absent from the Phase A dependency graph.

## Current Source Map

### A. Website Execution child UI

- `assets/js/operator-website-execution-child.mjs`
  - `childMarkup()` owns current Website Execution DOM and the existing `data-website-action="files"` button.
  - `renderChild(workspace, state)` writes context/reference fields with `textContent` and controls links.
  - `initializeOperatorWebsiteExecution(root, client, identity, options)` owns caller gateway, refresh generation, current snapshot, authorization failure, click routing, disposal, and auto-refresh.
  - The current files click only scrolls/focuses `[data-website-development]`; it performs no file request.

### B. Website Execution state/view projection

- `assets/js/operator-website-execution.mjs`
  - `websiteExecutionRequest(detail)` emits only `get_website_execution_workspace` plus `quote_request_id`.
  - `validateWebsiteExecutionWorkspace(value, expected)` exact-validates context/workspace binding and currently recognizes `PENDING_REPOSITORY`, legacy `READY`, and `REPOSITORY_READY`.
  - `websiteExecutionView(value)` maps empty, pending, and ready references.
  - `safeWebsiteExecutionLinks(owner, name)` currently constructs GitHub and VS Code Web links client-side; Phase A must replace GitHub navigation with a server-projected allowlisted URL and remove the VS Code Web control from the Phase A UI.

### C/D/H. Commercial command validator, handler, router, and errors

- `supabase/functions/commercial-operator-command/handler.ts`
  - `APPLICATION_ACTIONS`, `UnvalidatedInput`, `validateApplicationAction(value)`, `CommercialOperatorDependencies`, `handleCommercialOperator(request, deps)`, `mapDatabaseError(error)`, and `response(status, code, extra)` own exact request validation, caller verification, dependency dispatch, normalized errors, and no-store responses.
  - `requireOperatorAal2(claims, subject)` is currently used selectively and has a fixed eligible-subject set. Project Files must additionally rely on database active-owner+AAL2 authority; no browser role claim is authoritative.
- `supabase/functions/commercial-operator-command/index.ts`
  - `clientFor(jwt)` creates the non-persistent caller-JWT Supabase client.
  - The `executeApplicationAction` dispatcher currently calls `get_website_execution_workspace_v2` for Website Execution.
  - Runtime composition belongs here; provider tokens and raw GitHub responses must never enter handler DTOs.
- `supabase/functions/commercial-operator-command/handler.test.ts`
  - Existing dependency harness and request fixtures test exact-key validation, caller-JWT RPC transport, CORS/no-store behavior, and database-error mapping.

### E/L. GitHub/provider read infrastructure

- The reviewed `origin/main`/`c234796` tree has no GitHub provider modules.
- The separate reviewed Task13 history proves useful patterns but becomes an implementation dependency only when every required commit is an exact ancestor of the selected baseline:
  - `supabase/functions/_shared/github-app-config.ts`: strict environment/config parsing and non-enumerable private key.
  - `supabase/functions/_shared/github-app-token.ts`: repository-ID-scoped installation token and `contents: read` permission.
  - `supabase/functions/_shared/github-http.ts`: injected abort-signal support, bounded responses, redirect denial, normalized HTTP errors, and validated metadata/ref/tree/blob results; Phase A owns one 10-second operation deadline outside this transport.
  - `supabase/functions/_shared/github-repository-runtime.ts`: server-selected ref/tree/blob reads, but it is coupled to provisioning and must not be imported directly by Phase A.
- Phase A adds a focused provider service over approved read-only primitives. It must not depend on `RepositoryProvisioningServiceV2`, provisioning stores, test-island handlers, or any write operation.

### F/K. Repository binding/read models and lifecycle

- `supabase/migrations/20260912132000_reanchor_website_execution_workspace_v1.sql` establishes stable `website_work_context_id`, including `project_id = null` for PRE_PROJECT.
- Deployed commit `7c76729` adds `workspace_state`, provisioning actor/time, `PENDING_REPOSITORY`, legacy `READY`, and `get_website_execution_workspace_v2`.
- The separately reviewed Task13 migration `supabase/migrations/20260914090000_add_website_repository_provisioning_v1.sql` establishes `repository_external_id`, node identity, `REPOSITORY_PROVISIONING`, `REPOSITORY_READY`, `REPOSITORY_FAILED`, and operation states including `BLOCKED` and `QUARANTINED`. Phase A may consume it only from a selected baseline satisfying exact ancestry and must not invoke its create/provision/retry/finalize commands.

### G. Caller JWT / OWNER / AAL2 authority

- `supabase/functions/commercial-operator-command/handler.ts` rejects missing/expired/service-role JWTs and calls `verifyUser(jwt)`.
- `supabase/functions/commercial-operator-command/index.ts` propagates the human JWT through `clientFor(jwt)`.
- Existing SQL authorities resolve `auth.uid()` to `commercial_operators`, status, role, and `lws_internal.assert_operator_aal2_v1()`.
- New Project Files acquisition must be an authenticated caller-JWT RPC requiring ACTIVE owner and AAL2. A service-role client cannot acquire file authority.

### I. Frontend gateway/request helpers

- `createOperatorDossierAuthority(client, options).gateway(request)` in `assets/js/operator-dossiers.mjs` invokes `commercial-operator-command`, unwraps `result`, and triggers the established authorization-failure callback.
- `initializeOperatorWebsiteExecution` already owns this authority and will pass only the gateway function into the internal Project Files controller.

### J. Existing tests

- `scripts/operator-website-execution.test.mjs` covers exact Website context/workspace validation, PRE_PROJECT null project, safe rendering/link behavior, managed child lifecycle, CSS contracts, and caller-scoped gateway routing.
- `supabase/functions/commercial-operator-command/handler.test.ts` is the exact Edge handler regression surface.
- `supabase/tests/website_concept_pre_project_v1.sql`, `supabase/tests/website_execution_workspace_v1.sql`, and `supabase/tests/operator_mfa_aal2_authority_v1.sql` are adjacent database authorities.
- Established commands are `node --test ...`, `deno test --allow-env --allow-read ...`, `deno check ...`, and `npx supabase test db <file>`.

### M. Historical project-file design

- The amended authoritative spec is commit `325fadf50d3c17ffa89b9d77bbd71cb6ae227727` at `docs/superpowers/specs/2026-09-17-website-execution-build-workspace-design.md`.
- Historical Website Execution Tasks 16-18 proposed a local launcher, server file reads, and internal file view but were never implemented. Phase A reuses only the internal read-only intent; launcher and build concepts remain excluded.

## File Structure / Responsibility Map

### Prerequisite baseline files (verified or supplied before Phase A; not broadened here)

FILE=`scripts/operator-website-execution.test.mjs`, `supabase/functions/commercial-operator-command/handler.test.ts`, `supabase/functions/commercial-operator-command/handler.ts`, `supabase/functions/commercial-operator-command/index.ts`, `supabase/migrations/20260913100000_add_pre_project_technical_workspace_provisioning_v1.sql`, `supabase/tests/website_concept_pre_project_v1.sql`
RESPONSIBILITY=Preserve deployed v118 PRE_PROJECT workspace provisioning and `get_website_execution_workspace_v2`.
WHY_EXISTING_FILE_OR_NEW_FILE=Exact six-file scope from audited commit `7c76729`; integrate the commit unchanged under Case A.
PUBLIC_INTERFACE=`provision_website_execution_workspace_v1(uuid,uuid)`, `get_website_execution_workspace_v2(uuid)`.

FILE=`supabase/functions/_shared/github-app-config.ts`, `supabase/functions/_shared/github-app-private-key.ts`, `supabase/functions/_shared/github-installation-token.ts`, `supabase/functions/_shared/github-app-token.ts`, `supabase/functions/_shared/github-http.ts`
RESPONSIBILITY=Approved GitHub App config, signing/token exchange, redirect/timeout/size bounds, and read-only metadata/ref/commit/tree/blob operations.
WHY_EXISTING_FILE_OR_NEW_FILE=Existing only on an approved selected baseline where every prerequisite commit is an exact ancestor; this plan does not forward-port or reconstruct these files.
PUBLIC_INTERFACE=`loadGitHubAppConfig`, `createGitHubAppTokenBroker`, `createGitHubHttpClient`, read-only `GitHubHttpOperation` variants.

### Phase A files

FILE=`supabase/migrations/20260917100000_add_website_project_files_read_authority_v1.sql`
RESPONSIBILITY=Add caller-JWT owner+AAL2 authority projection, exact 60-second rolling rate accounting with five-minute record retention, 15-second concurrency leases, safe repository-operation status projection, new forward-only `get_website_execution_workspace_v3(uuid)`, and release RPC without granting direct table access while preserving v2 unchanged.
WHY_EXISTING_FILE_OR_NEW_FILE=New forward-only authority; existing committed migrations remain immutable.
PUBLIC_INTERFACE=`acquire_website_project_files_read_v1(uuid,text)`, `release_website_project_files_read_v1(uuid)`, `get_website_execution_workspace_v3(uuid)`; existing `get_website_execution_workspace_v2(uuid)` remains unchanged.

FILE=`supabase/tests/website_project_files_phase_a_v1.sql`
RESPONSIBILITY=pgTAP contract for caller authority, PRE_PROJECT, lifecycle gates, binding identity, rate/concurrency bounds, cross-context denial, forced RLS, and zero repository-operation creation.
WHY_EXISTING_FILE_OR_NEW_FILE=New focused executable SQL specification.
PUBLIC_INTERFACE=Test-only synthetic `CONTEXT_A`/`CONTEXT_B` fixtures and assertions.

FILE=`supabase/functions/_shared/website-project-files-policy.ts`
RESPONSIBILITY=Normalize paths, project metadata-only directory readability, map known unsupported entries inertly, reject unknown/malformed objects, classify blocked names/content, enforce post-read UTF-8/binary/size rules, and construct safe text results.
WHY_EXISTING_FILE_OR_NEW_FILE=New focused pure module keeps policy out of `supabase/functions/commercial-operator-command/handler.ts` and provider transport.
PUBLIC_INTERFACE=`normalizeWebsiteProjectPath`, `classifyWebsiteProjectPath`, `classifyWebsiteProjectDirectoryEntry`, `inspectWebsiteProjectFile`, `WebsiteProjectFilesPolicyError`.

FILE=`supabase/functions/_shared/website-project-files-policy.test.ts`
RESPONSIBILITY=Unit-test every path, sensitive-file, encoding, binary, and size boundary.
WHY_EXISTING_FILE_OR_NEW_FILE=New pure-policy TDD surface.
PUBLIC_INTERFACE=None; imports the policy exports.

FILE=`supabase/functions/_shared/website-project-files-cursor.ts`
RESPONSIBILITY=Sign and verify canonical five-minute HMAC cursors bound to actor/context/repository/binding/commit/directory/tree/offset.
WHY_EXISTING_FILE_OR_NEW_FILE=Existing `supabase/functions/_shared/operator-cursor.ts` is dossier-filter-specific and has a 15-minute payload; reuse its cryptographic pattern, not its incompatible DTO.
PUBLIC_INTERFACE=`signWebsiteProjectFilesCursor`, `verifyWebsiteProjectFilesCursor`, `WebsiteProjectFilesCursorError`.

FILE=`supabase/functions/_shared/website-project-files-cursor.test.ts`
RESPONSIBILITY=Cursor canonicalization, expiry, tampering, and cross-context/snapshot replay tests.
WHY_EXISTING_FILE_OR_NEW_FILE=New focused cursor TDD surface.
PUBLIC_INTERFACE=None.

FILE=`supabase/functions/_shared/website-project-files-provider.ts`
RESPONSIBILITY=Use server-selected repository authority to verify metadata/marker, resolve immutable commit, traverse trees, read blobs, normalize provider failures, and expose no write method.
WHY_EXISTING_FILE_OR_NEW_FILE=New Phase-A orchestration over prerequisite read-only GitHub primitives; provisioning runtime is intentionally not reused because it exposes write paths.
PUBLIC_INTERFACE=`WebsiteProjectFilesAuthority`, `WebsiteProjectFilesProvider`, `createWebsiteProjectFilesProvider`, `WebsiteProjectFilesProviderError`.

FILE=`supabase/functions/_shared/website-project-files-provider.test.ts`
RESPONSIBILITY=Provider metadata/ref/tree/blob/marker validation, timeout/throttle/malformed/path/type/snapshot errors, and mutation-unreachability tests.
WHY_EXISTING_FILE_OR_NEW_FILE=New mocked-provider TDD surface.
PUBLIC_INTERFACE=None.

FILE=`supabase/functions/_shared/website-project-files-service.ts`
RESPONSIBILITY=Coordinate policy, immutable snapshot, sorting/pagination/512-KiB bound, safe file result, and cursor while the runtime composition root owns authority lease acquisition/release.
WHY_EXISTING_FILE_OR_NEW_FILE=New application service prevents handler/index monolith growth.
PUBLIC_INTERFACE=`WebsiteProjectFilesListInput`, `WebsiteProjectFileReadInput`, `WebsiteProjectFilesResult`, `createWebsiteProjectFilesService`.

FILE=`supabase/functions/_shared/website-project-files-service.test.ts`
RESPONSIBILITY=End-to-end service tests for snapshot consistency, response bounds, limits, and normalized errors; runtime tests own lease release.
WHY_EXISTING_FILE_OR_NEW_FILE=New dependency-injected TDD surface.
PUBLIC_INTERFACE=None.

FILE=`supabase/functions/commercial-operator-command/handler.ts`
RESPONSIBILITY=Recognize exact actions/DTOs, require human owner-eligible AAL2 intent, dispatch service dependency, and map stable errors.
WHY_EXISTING_FILE_OR_NEW_FILE=Existing single commercial operator HTTP contract; no parallel Edge Function.
PUBLIC_INTERFACE=`WebsiteProjectDirectoryListActionInput`, `WebsiteProjectFileReadActionInput`, extended `CommercialOperatorDependencies`.

FILE=`supabase/functions/commercial-operator-command/index.ts`
RESPONSIBILITY=Compose caller-JWT authority RPC, approved GitHub read-only runtime, cursor secret, service, and action dispatch.
WHY_EXISTING_FILE_OR_NEW_FILE=Existing runtime/router composition root.
PUBLIC_INTERFACE=No new exported browser API beyond the two actions; testable `executeCallerJwtWebsiteProjectFilesAction` helper.

FILE=`supabase/functions/commercial-operator-command/handler.test.ts`
RESPONSIBILITY=Exact request keys, JWT/AAL2/OWNER dispatch, response headers/codes, raw-provider redaction, and no mutation-route tests.
WHY_EXISTING_FILE_OR_NEW_FILE=Existing gateway regression harness.
PUBLIC_INTERFACE=None.

FILE=`assets/js/operator-website-project-files.mjs`
RESPONSIBILITY=Build exact requests, validate list/read DTOs, own in-memory tree/file/snapshot state, render inert DOM, and clear state on authority/context/lifecycle changes.
WHY_EXISTING_FILE_OR_NEW_FILE=New focused frontend controller prevents `assets/js/operator-website-execution-child.mjs` from becoming a files monolith.
PUBLIC_INTERFACE=`websiteProjectDirectoryRequest`, `websiteProjectFileRequest`, `validateWebsiteProjectDirectory`, `validateWebsiteProjectFile`, `createWebsiteProjectFilesController`.

FILE=`assets/js/operator-website-execution.mjs`
RESPONSIBILITY=Validate Website Execution contract v3 lifecycle/operation status and project the server-provided GitHub navigation URL plus files availability.
WHY_EXISTING_FILE_OR_NEW_FILE=Existing Website workspace contract/view owner.
PUBLIC_INTERFACE=Extended `validateWebsiteExecutionWorkspace` and `websiteExecutionView`; `safeWebsiteExecutionLinks` no longer creates VS Code Web authority.

FILE=`assets/js/operator-website-execution-child.mjs`
RESPONSIBILITY=Mount one internal Projectbestanden host/controller, pass gateway/context/owner+AAL2 capability, notify it on refreshed snapshots, and dispose it.
WHY_EXISTING_FILE_OR_NEW_FILE=Existing managed Website child lifecycle owner.
PUBLIC_INTERFACE=Unchanged `initializeOperatorWebsiteExecution`.

FILE=`assets/css/operator-dashboard.css`
RESPONSIBILITY=Responsive, bounded tree/content layout and explicit state presentation inside Website Execution.
WHY_EXISTING_FILE_OR_NEW_FILE=Existing Operator/Website visual contract; no new stylesheet load path.
PUBLIC_INTERFACE=New `.website-project-files*` selectors only.

FILE=`scripts/operator-website-project-files.test.mjs`
RESPONSIBILITY=Node/Playwright tests for exact frontend DTOs, lifecycle states, safe rendering, snapshot mismatch, state clearing, and persistence prohibition.
WHY_EXISTING_FILE_OR_NEW_FILE=New focused frontend behavior/security test.
PUBLIC_INTERFACE=None.

FILE=`scripts/operator-website-execution.test.mjs`
RESPONSIBILITY=Assert the existing child/slot contract, Phase B/C absence, lifecycle integration, PRE_PROJECT, and no new managed module.
WHY_EXISTING_FILE_OR_NEW_FILE=Existing Website Execution regression suite.
PUBLIC_INTERFACE=None.

FILE=`docs/superpowers/checkpoints/2026-09-17-website-execution-project-files-phase-a-verification.md`
RESPONSIBILITY=Record implementation SHAs, exact commands/results, baseline debt, no-write proof, and release authorization state.
WHY_EXISTING_FILE_OR_NEW_FILE=New final local evidence document; it authorizes no deploy/push.
PUBLIC_INTERFACE=Human-readable verification checkpoint.

## Exact Phase A Contracts

### Browser requests

```ts
export type WebsiteProjectDirectoryListActionInput = Readonly<{
  action: "list_website_project_directory";
  quote_request_id: string;
  path: string;
  cursor: string | null;
}>;

export type WebsiteProjectFileReadActionInput = Readonly<{
  action: "read_website_project_file";
  quote_request_id: string;
  path: string;
}>;
```

Root uses `path: ""`. Omitted `path`, omitted `cursor`, extra keys, and all authority fields are invalid; frontend builders always send the exact shapes above.

### Server authority and lease

```ts
export type WebsiteProjectFilesAuthority = Readonly<{
  leaseId: string;
  actorAuthUserId: string;
  quoteRequestId: string;
  websiteWorkContextId: string;
  websiteWorkspaceId: string;
  bindingRevision: number;
  repositoryProvider: "GITHUB";
  repositoryOwner: string;
  repositoryName: string;
  repositoryExternalId: string;
  repositoryNodeId: string;
  defaultBranch: string;
  repositoryRef: string;
  refLabel: string;
  markerOperationId: string;
  expiresAt: string;
}>;
```

`repositoryRef` is the database-authorized full ref such as `heads/main`; provider metadata is validation evidence and cannot select or replace it. `refLabel` is its safe browser label. `acquire_website_project_files_read_v1(quote_request_id, read_kind)` returns this only to the Edge caller-JWT transport after active OWNER+AAL2 and all bindings are proven. `read_kind` is exactly `DIRECTORY` or `FILE`; the database counts timestamps in the half-open 60-second interval `(clock_timestamp() - interval '60 seconds', clock_timestamp()]`, enforces 30 DIRECTORY and 10 FILE acquisitions per actor/context, retains accounting rows for five minutes only for cleanup/audit, and permits at most four unexpired leases per actor. `release_website_project_files_read_v1(lease_id)` accepts only the same caller, is idempotent for an already released/expired same-caller lease, and returns no authority. The `supabase/functions/commercial-operator-command/index.ts` runtime composition root is the single lease owner: acquire once before calling the service and release once in `finally`; the service never acquires or releases a lease.

### Website Execution contract v3

The existing `get_website_execution_workspace_v2(uuid)` RPC and its response remain unchanged for backward compatibility. Phase A adds the forward-only `get_website_execution_workspace_v3(uuid)` RPC in the new migration; v3 alone owns `WebsiteExecutionWorkspaceV3`. During Phase A implementation, the commercial operator Website Execution read route switches to v3. The existing root keys remain closed and v3 returns `contract_version: 3`. The exact workspace object is:

```ts
type WebsiteExecutionWorkspaceV3 = Readonly<{
  website_workspace_id: string;
  website_work_context_id: string;
  project_id: string | null;
  quote_request_id: string;
  workspace_state: "PENDING_REPOSITORY" | "REPOSITORY_PROVISIONING" | "REPOSITORY_READY" | "REPOSITORY_FAILED" | "READY";
  repository_operation_state: "CLAIMED" | "CREATING" | "EXTERNAL_CREATED" | "VERIFYING" | "COMPLETE" | "RETRYABLE_FAILED" | "RETRY_SCHEDULED" | "BLOCKED" | "QUARANTINED" | "TERMINAL_FAILED" | null;
  repository_failure_category: "RETRYABLE" | "BLOCKED" | "QUARANTINED" | "TERMINAL" | null;
  repository_recovery_guidance: "WAIT" | "REFRESH_LATER" | "CONTACT_OWNER" | "RECONCILIATION_REQUIRED" | null;
  repository_provider: "GITHUB";
  repository_owner: string | null;
  repository_name: string | null;
  repository_navigation_url: string | null;
  default_branch: string;
  preview_branch: string | null;
  preview_url: string | null;
  last_commit_sha: string | null;
  last_commit_at: string | null;
  last_build_result: "PASS" | "FAIL" | "UNKNOWN" | null;
  last_build_at: string | null;
  binding_revision: number;
  provisioned_by: string;
  provisioned_at: string;
  created_at: string;
  updated_at: string;
  capabilities: Readonly<{ project_files_read: boolean }>;
}>;
```

The root remains exactly `contract_version`, `mode`, `quote_request_id`, `concept_id`, `project_id`, `website_work_context_id`, `context_revision`, `briefing_status`, `commercially_released`, `project`, `start_gate`, `workspace`, and `requirements`. `repository_navigation_url` is null unless it is an allowlisted `https://github.com/<owner>/<repository>` projection. `project_files_read` is true only for `REPOSITORY_READY`, operation `COMPLETE`, verified binding, and a caller eligible to attempt the separately AAL2-guarded action.

Before constructing this exact DTO, SQL normalizes any unrecognized persisted repository operation value to null and records no raw value in the response. Failure category is an independent server projection evaluated with this total precedence:

| Priority | Repository operation | Failure category |
|---|---|---|
| 1 | `QUARANTINED` | `QUARANTINED` |
| 2 | `BLOCKED` | `BLOCKED` |
| 3 | `TERMINAL_FAILED` | `TERMINAL` |
| 4 | `RETRYABLE_FAILED` or `RETRY_SCHEDULED` | `RETRYABLE` |
| 5 | `CLAIMED`, `CREATING`, `EXTERNAL_CREATED`, `VERIFYING`, or `COMPLETE` | null |
| 6 | null, including an unknown operation normalized to null | null |

For `REPOSITORY_FAILED` without a recognized failure operation, the category is null. For contradictory workspace/operation combinations, a recognized failure operation wins according to the table; otherwise the category is null. A null category does not mean success and never enables `project_files_read`.

Recovery guidance is a separate server projection evaluated top to bottom:

| Priority | Workspace/operation condition | Guidance | Files |
|---|---|---|---|
| 1 | operation `QUARANTINED` | `RECONCILIATION_REQUIRED` | false |
| 2 | operation `BLOCKED` or `TERMINAL_FAILED` | `CONTACT_OWNER` | false |
| 3 | operation `RETRYABLE_FAILED` or `RETRY_SCHEDULED` | `REFRESH_LATER` | false |
| 4 | workspace `READY` (legacy), regardless of remaining operation | `RECONCILIATION_REQUIRED` | false |
| 5 | workspace `REPOSITORY_FAILED` without priority 1-3 | `CONTACT_OWNER` | false |
| 6 | workspace `PENDING_REPOSITORY` or `REPOSITORY_PROVISIONING`, or operation `CLAIMED`, `CREATING`, `EXTERNAL_CREATED`, or `VERIFYING` | `WAIT` | false |
| 7 | workspace `REPOSITORY_READY` + operation `COMPLETE` + verified binding | null | true for owner-eligible caller only |
| 8 | every null, unknown, or contradictory combination | `RECONCILIATION_REQUIRED` | false |

Task 3 pgTAP and Task 7 frontend fixtures enumerate the Cartesian product of every declared workspace state with every declared operation state plus null and one unknown value, then assert both precedence tables. `repository_failure_category` and `repository_recovery_guidance` are independent server projections. No browser branch infers failure category or invents recovery guidance.

### Cursor

```ts
export type WebsiteProjectFilesCursorPayload = Readonly<{
  domain: "lws-website-project-files";
  version: 1;
  keyId: "V1";
  actorAuthUserId: string;
  websiteWorkContextId: string;
  repositoryExternalId: string;
  bindingRevision: number;
  commitSha: string;
  rootTreeSha: string;
  directory: string;
  directoryTreeSha: string;
  offset: number;
  issuedAt: number;
  expiresAt: number;
}>;
```

Use `LWS_WEBSITE_PROJECT_FILES_CURSOR_SIGNING_KEY_V1`, exactly 32 random bytes encoded base64url, HMAC-SHA-256, canonical JSON, `expiresAt - issuedAt = 300000`, and constant-time Web Crypto verification.

### Provider boundary

```ts
export type WebsiteProjectFilesProvider = Readonly<{
  resolveSnapshot(authority: WebsiteProjectFilesAuthority): Promise<Readonly<{
    commitSha: string;
    rootTreeSha: string;
    repositoryDisplayName: string;
  }>>;
  listDirectory(input: Readonly<{
    authority: WebsiteProjectFilesAuthority;
    commitSha: string;
    rootTreeSha: string;
    directoryTreeSha: string | null;
    path: string;
  }>): Promise<Readonly<{ directoryTreeSha: string; entries: readonly ProviderTreeEntry[] }>>;
  readFile(input: Readonly<{
    authority: WebsiteProjectFilesAuthority;
    commitSha: string;
    rootTreeSha: string;
    path: string;
  }>): Promise<Readonly<{ canonicalPath: string; objectType: "blob"; blobSha: string; declaredSize: number; bytes: Uint8Array }>>;
}>;
```

```ts
export type ProviderTreeEntry = Readonly<{
  name: string;
  canonicalPath: string;
  mode: string;
  objectType: "blob" | "tree" | "commit";
  objectSha: string;
  size: number | null;
}>;

export type SensitiveContentClassifier = Readonly<{
  classify(input: Readonly<{ path: string; bytes: Uint8Array; text: string }> ):
    "SAFE" | "SENSITIVE" | "UNAVAILABLE";
}>;

export type WebsiteProjectFilesResult =
  | WebsiteProjectDirectoryResult
  | WebsiteProjectFileResult;

export type WebsiteProjectFilesService = Readonly<{
  list(input: WebsiteProjectFilesListInput): Promise<WebsiteProjectDirectoryResult>;
  read(input: WebsiteProjectFileReadInput): Promise<WebsiteProjectFileResult>;
}>;
```

`WebsiteProjectFilesListInput` is exactly `{ authority, path, cursor }`; `WebsiteProjectFileReadInput` is exactly `{ authority, path }`. `service.list()` resolves a snapshot exactly once for a new listing and passes `directoryTreeSha: null`; cursor continuation verifies and passes its signed `commitSha`, `rootTreeSha`, and non-null `directoryTreeSha` to direct tree listing without resolving the mutable ref or retraversing a changed path. `service.read()` resolves a snapshot exactly once and passes that immutable `commitSha`/`rootTreeSha` to `provider.readFile()`; `provider.readFile()` never resolves a branch.

The `supabase/functions/commercial-operator-command/index.ts` lease wrapper creates one `AbortSignal.timeout(10000)` for the entire acquisition-to-result operation and injects it through service/provider/HTTP calls. Every nested call consumes the remaining single deadline; no call starts or retries after abort. This operation-wide 10-second deadline is strictly below the 15-second lease lifetime, so an active request cannot outlive its concurrency lease.

`resolveSnapshot` obtains a repository-ID-scoped installation token with metadata/content read only, verifies metadata identity/private repository, validates that `authority.repositoryRef` is the authorized binding ref and that its branch label agrees with metadata without deriving authority from metadata, resolves only `authority.repositoryRef`, validates the commit, reads `.lws/project.json` internally at that same commit, and compares context/external ID/marker operation. Directory traversal reads one non-recursive tree per normalized segment. Known structurally valid symlink modes and `commit` entries (submodules/Git links) become inert non-selectable `UNSUPPORTED` directory entries and are never followed. Unknown object types, invalid mode/type combinations, malformed metadata, redirects, wrong canonical paths, root escapes, and tree truncation fail the entire current request closed; no partial unsafe listing is returned.

### Success DTOs

Directory `result` is exact:

```ts
type WebsiteProjectDirectoryEntry =
  | Readonly<{
      entry_type: "ENTRY";
      name: string;
      path: string;
      kind: "DIRECTORY" | "FILE" | "UNSUPPORTED";
      size_bytes: number | null;
      readability: "DIRECTORY" | "READABLE_CANDIDATE" | "TOO_LARGE" | "SENSITIVE_BLOCKED" | "UNSUPPORTED";
      selectable: boolean;
    }>
  | Readonly<{
      entry_type: "BLOCKED_CREDENTIAL";
      name: "Geblokkeerd bestand";
      kind: "UNSUPPORTED";
      readability: "SENSITIVE_BLOCKED";
      selectable: false;
    }>;

type WebsiteProjectDirectoryResult = Readonly<{
  contract_version: 1;
  quote_request_id: string;
  website_work_context_id: string;
  workspace_state: "REPOSITORY_READY";
  repository: Readonly<{ display_name: string; binding_revision: number }>;
  snapshot: Readonly<{ commit_sha: string; ref_label: string }>;
  directory: string;
  entries: readonly WebsiteProjectDirectoryEntry[];
  next_cursor: string | null;
}>;
```

Directory listings contain metadata only and use this total projection:

| Provider/tree fact | Exact directory result |
|---|---|
| Tree/directory | `kind=DIRECTORY`, `readability=DIRECTORY`, `selectable=true` |
| Regular safe-path blob with declared size at most 1 MiB | `kind=FILE`, `readability=READABLE_CANDIDATE`, `selectable=true` |
| Regular safe-path blob with null/unknown provider size | `kind=FILE`, `readability=READABLE_CANDIDATE`, `selectable=true`; enforce 1 MiB authoritatively during read |
| Regular safe-path blob with declared size greater than 1 MiB | `kind=FILE`, `readability=TOO_LARGE`, `selectable=false` |
| Blocked credential pathname | Exact redacted `BLOCKED_CREDENTIAL`; no path, original filename, size, object SHA/ID, cursor target, or selectable action |
| Known structurally valid symlink | `kind=UNSUPPORTED`, `readability=UNSUPPORTED`, `selectable=false` |
| Known structurally valid submodule/Git-link/commit entry | `kind=UNSUPPORTED`, `readability=UNSUPPORTED`, `selectable=false` |
| Unknown object/mode, invalid mode/type, malformed metadata, canonical-path mismatch, redirect, or root escape | Fail the entire current request closed; return no partial unsafe entry |

`TEXT` is a post-read success fact only after actual bytes pass size, strict UTF-8, binary, and sensitive-content checks. `BINARY_UNSUPPORTED`, `UNSUPPORTED_ENCODING`, `SENSITIVE_FILE_BLOCKED`, and `FILE_TOO_LARGE` are authoritative file-read outcomes/errors, not guesses from ordinary tree metadata. Only a provider-declared oversize blob yields pre-read `TOO_LARGE`; a blocked pathname yields the redacted blocked variant.

File `result` is exact:

```ts
type WebsiteProjectFileResult = Readonly<{
  contract_version: 1;
  quote_request_id: string;
  website_work_context_id: string;
  workspace_state: "REPOSITORY_READY";
  repository: Readonly<{ display_name: string; binding_revision: number }>;
  snapshot: Readonly<{ commit_sha: string; ref_label: string }>;
  file: Readonly<{
    path: string;
    size_bytes: number;
    media_type: "text/plain";
    encoding: "utf-8";
    content: string;
  }>;
}>;
```

The gateway wraps either as `{ ok: true, code: "APPLICATION_ACTION_ACCEPTED", result }`, with `Content-Type: application/json`, `Cache-Control: no-store`, `Referrer-Policy: no-referrer`, and `X-Content-Type-Options: nosniff`. The 512-KiB ceiling applies to the complete UTF-8 encoded HTTP response body including this envelope; service pagination reserves and tests the exact envelope overhead before returning its result.

### Deterministic sensitive classifier

`classifyWebsiteProjectPath` compares normalized path segments and compares the normalized basename case-insensitively. It blocks the exact names/directories in the approved spec. Provider-token basenames use the semantic rule: optional leading `.`, provider `github|gitlab|npm|provider`, optional separator `-|_|.`, literal `token`, and an optional suffix beginning with `-`, `_`, or `.` and otherwise containing only ASCII letters, digits, `.`, `_`, or `-`. The equivalent implementation regex may be `^\.?(?:github|gitlab|npm|provider)(?:[-_.]?token)(?:[-_.][a-z0-9][a-z0-9._-]*)?$` with case-insensitive matching; semantic examples are authoritative.

Provider-token tests must block every amended-spec example: `.github-token`, `.gitlab-token`, `.npm-token`, `.provider-token`, `github-token`, `gitlab-token`, `npm-token`, `provider-token`, `github_token`, `github.token`, `githubtoken`, `.github-token.local`, `github-token.backup`, `gitlab_token_prod`, `npm.token.dev`, `PROVIDER-TOKEN`, and `.GITHUB-TOKEN`. They must allow every amended-spec example: `github-actions.yml`, `provider-config.json`, `npm-package.json`, `tokenizer.ts`, `github-tokenizer.txt`, `gitlab-ci.yml`, `package.json`, and `build-token-view.mjs`. Add separator, suffix, first-suffix-character, case, and tokenizer near-miss boundaries. Exact independently blocked `.npmrc` and `.git-credentials` remain blocked.

Listings replace every blocked credential/sensitive pathname with the exact `BLOCKED_CREDENTIAL` union variant above; that variant has no original filename, path, size, object ID/SHA, cursor target, or selectable action.

The deterministic V1 local classifier first scans decoded text without logging it. `SENSITIVE` means a PEM private-key header; an HTTPS/SSH remote containing user-info or a token; a token matching `ghp_[A-Za-z0-9]{36}`, `github_pat_[A-Za-z0-9_]{82}`, `glpat-[A-Za-z0-9_-]{20,}`, or `npm_[A-Za-z0-9]{36}`; or an assignment whose normalized key matches `password|passwd|secret|token|api_key|apikey|private_key|client_secret` and whose value is neither empty nor one of `example`, `sample`, `dummy`, `changeme`, `replace-me`, or `${...}`. Tests cover each exact minimum, minimum-minus-one, and boundary characters. Null bytes, forbidden control-byte density above 1%, or strict UTF-8 failure are binary/encoding failures before this classifier. Any classifier exception maps to `UNAVAILABLE`; no partial content or matched fragment leaves the service.

### Stable error mapping

```text
400 INVALID_REQUEST | INVALID_PROJECT_PATH | PROJECT_FILES_CURSOR_INVALID
403 OPERATOR_NOT_AUTHORIZED | SENSITIVE_FILE_BLOCKED
404 PROJECT_DIRECTORY_NOT_FOUND | PROJECT_FILE_NOT_FOUND
409 REPOSITORY_NOT_READY | REPOSITORY_BINDING_MISSING | REPOSITORY_BINDING_STALE | REPOSITORY_REF_MISMATCH | PROJECT_FILES_SNAPSHOT_UNAVAILABLE | PROJECT_PATH_KIND_MISMATCH
413 FILE_TOO_LARGE
415 BINARY_UNSUPPORTED | UNSUPPORTED_ENCODING
429 PROJECT_FILES_RATE_LIMITED | PROJECT_FILES_CONCURRENCY_LIMITED
503 PROJECT_FILES_PROVIDER_UNAVAILABLE | PROJECT_FILES_PROVIDER_TIMEOUT | PROJECT_FILES_PROVIDER_THROTTLED | PROJECT_FILES_PROVIDER_RESPONSE_INVALID | SENSITIVE_CLASSIFICATION_UNAVAILABLE
```

No raw provider message, request ID, token, URL, retry body, or response fragment reaches the browser. A safe integer `retry_after_seconds` may accompany 429 only.

## Task 1: Reconcile the implementation baseline and preserve live v118

**Files:**
- Create: none
- Modify: the exact six files already contained by `7c7672980d31a92fea124727b41ca5eef6eec005` under Case A only
- Test: `scripts/operator-website-execution.test.mjs`, `supabase/functions/commercial-operator-command/handler.test.ts`, `supabase/tests/website_concept_pre_project_v1.sql`

**Interfaces:**
- Consumes: current `origin/main`, approved design commit, deployed v118 commit
- Produces: a baseline that contains v118 unchanged and a recorded prerequisite decision for canonical repository binding/provider reads

- [ ] Fetch and record `git rev-parse origin/main`, `git rev-parse HEAD`, `git status --short`, `git rev-parse 7c767298^`, `git show --format=fuller --stat 7c767298`, and `git diff --check 7c767298^ 7c767298`.
- [ ] CASE A requires `origin/main = 7c767298^ = f94888318c74e79bf5e148d81d3eb892907798b8`, clean worktree, and unchanged six-file commit scope. Cherry-pick the exact `7c767298...` commit; do not manually reconstruct it.
- [ ] CASE B applies if `origin/main` moved or the parent/scope differs. Stop before backend editing. Create a separate controller-reviewed three-way reconciliation of OLD BASE `f948883...`, CURRENT MAIN, and DEPLOYED SOURCE `7c76729`; do not checkout `supabase/functions/commercial-operator-command/handler.ts` or `supabase/functions/commercial-operator-command/index.ts` from either side wholesale.
- [ ] Under Case A, require this exact v118 file list before cherry-pick:

  ```text
  scripts/operator-website-execution.test.mjs
  supabase/functions/commercial-operator-command/handler.test.ts
  supabase/functions/commercial-operator-command/handler.ts
  supabase/functions/commercial-operator-command/index.ts
  supabase/migrations/20260913100000_add_pre_project_technical_workspace_provisioning_v1.sql
  supabase/tests/website_concept_pre_project_v1.sql
  ```
- [ ] After Case A cherry-pick, run:

  ```powershell
  deno test --allow-env --allow-read supabase/functions/commercial-operator-command/handler.test.ts
  node --test scripts/operator-website-execution.test.mjs
  npx supabase test db supabase/tests/website_concept_pre_project_v1.sql
  ```

  Expected: all pass with the v118 provisioning action retained.
- [ ] Run this exact ancestry gate. Require exit 0 for every SHA; otherwise stop and obtain a new controller-approved baseline before continuing to Task 2. This plan accepts no inferred/squashed patch equivalence.

  ```powershell
  @('8bd8f04c13d8fae856ee5088f7f6570e9ce20576','392e56379c73385a0137a960d615ca7d54056727','96ced670d823ae7f1dd0cc8dcb7af7f9b97a80ba','879e1a41840106368b3a4be4757ee07ac47ac29a','c3619f0d6185b98cfb92c0af390ce0ecf5bb729f','2f4c193a5427b599f7b7b580ca513e2c9c451618','ffd65a6b6cfab2595d67f3724b5c4c913db6799a','4dd420b4510df55642a8b1e2e1b91dfc4a61155e') | ForEach-Object { git merge-base --is-ancestor $_ HEAD; if ($LASTEXITCODE -ne 0) { throw "Missing prerequisite commit $_" } }
  ```
- [ ] If any exact ancestry check fails, stop Phase A. Do not forward-port, cherry-pick subsets, copy files, or accept patch-ID/patch equivalence under this plan. A separate controller-approved prerequisite integration plan must produce a reviewed baseline SHA, after which this complete Phase A plan is revalidated before execution resumes.
- [ ] Require and typecheck the exact prerequisite manifest, then run every test file present for those primitives:

  ```powershell
  git ls-files --error-unmatch supabase/functions/_shared/repository-provisioning.ts supabase/functions/_shared/github-app-config.ts supabase/functions/_shared/github-app-config.test.ts supabase/functions/_shared/github-app-private-key.ts supabase/functions/_shared/github-installation-token.ts supabase/functions/_shared/github-app-token.ts supabase/functions/_shared/github-app-token.test.ts supabase/functions/_shared/github-http.ts supabase/functions/_shared/github-http.test.ts supabase/functions/_shared/github-ref-read-diagnostic.ts supabase/migrations/20260914090000_add_website_repository_provisioning_v1.sql
  deno check supabase/functions/_shared/github-app-config.ts supabase/functions/_shared/github-app-private-key.ts supabase/functions/_shared/github-installation-token.ts supabase/functions/_shared/github-app-token.ts supabase/functions/_shared/github-http.ts supabase/functions/_shared/github-ref-read-diagnostic.ts
  deno test --allow-env --allow-read supabase/functions/_shared/github-app-config.test.ts supabase/functions/_shared/github-app-token.test.ts supabase/functions/_shared/github-http.test.ts
  ```

  Expected: `git ls-files` prints all 11 paths, typecheck passes all six source modules, and all three audited test files pass. The audited commit contains no separate private-key, installation-token, or ref-read-diagnostic test file; their compilation is explicit and their behavior is exercised through the token/HTTP suites.
- [ ] The static test `Phase A provider dependency graph exposes read operations only` in Task 4 must read `supabase/functions/_shared/website-project-files-provider.ts`, `supabase/functions/_shared/website-project-files-service.ts`, and `supabase/functions/commercial-operator-command/index.ts` and assert no `CREATE_REPOSITORY|CREATE_BLOB|CREATE_TREE|CREATE_COMMIT|CREATE_REF|UPDATE_REF|WRITE_PROJECT_MARKER|RepositoryProvisioningServiceV2` reference. At this gate, verify only that the prerequisite modules exist; Task 4 supplies the RED/GREEN proof after the focused provider exists.
- [ ] Commit boundary: the Case A cherry-pick preserves commit message `fix(operator): enable workspace provisioning command`; any Case B/prerequisite reconciliation uses a separately approved commit and is not authored under this plan.

## Task 2: Add path, object, encoding, and sensitive-file policy primitives

**Files:**
- Create: `supabase/functions/_shared/website-project-files-policy.ts`, `supabase/functions/_shared/website-project-files-policy.test.ts`
- Modify: none
- Test: `supabase/functions/_shared/website-project-files-policy.test.ts`

**Interfaces:**
- Consumes: raw JSON path string, provider object metadata, declared size, decoded bytes, sensitive classifier
- Produces: normalized path, exact metadata-only directory projection, or exact `WebsiteProjectFilesPolicyError`; accepted UTF-8 text only after separate file-content inspection

- [ ] Write failing tests named `path policy accepts root only for directory lists`, `path policy rejects absolute drive UNC URL and backslash forms`, `path policy rejects empty dot dotdot null control and invalid Unicode segments`, `path policy rejects percent encoded separator dot and null tricks`, `path policy rejects non-NFC and NFKC separator ambiguity`, and `provider canonical path mismatch and root escape fail closed`.
- [ ] Test maximum 1024 UTF-8 bytes, 64 non-empty segments, and 255 UTF-8 bytes per segment at exact boundary and boundary+1.
- [ ] Test metadata mapping separately from content inspection: tree becomes `DIRECTORY`; regular safe-path blob at or below 1 MiB and null/unknown-size blob become selectable `READABLE_CANDIDATE`; declared oversize becomes non-selectable `TOO_LARGE`; blocked pathname becomes the redacted non-selectable `BLOCKED_CREDENTIAL`; known symlink mode `120000` and known submodule/Git-link `commit` become inert non-selectable `UNSUPPORTED`.
- [ ] Test unknown object type, invalid mode/type combination, malformed metadata, provider canonical-path mismatch, redirect, and root escape fail the whole current directory request closed with no partial item. A direct file read of a symlink or commit entry also fails closed and never follows the target.
- [ ] Test blocked names exactly: `.env`, `.env.local`, `.env.production`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `id_rsa`, `id_ed25519`, `.git-credentials`, `.netrc`, `.npmrc`, `.pypirc`, `credentials.json`, `service-account.json`, `.git/**`, and `.lws/project.json`.
- [ ] Test all authoritative provider-token block/allow examples listed under Deterministic sensitive classifier, case-insensitive matching, and separator/suffix/tokenizer near-miss boundaries.
- [ ] Test `.env.example`, `.env.sample`, and `.env.template` pass the name gate but still enter content scanning.
- [ ] Test innocent filenames containing private-key headers, authenticated remotes/token-like content, and non-dummy credential assignments return `SENSITIVE_FILE_BLOCKED` with no partial text. Classifier exception/unavailability returns `SENSITIVE_CLASSIFICATION_UNAVAILABLE` with no bytes/text.
- [ ] In the separate post-read path, test 1,048,576 decoded bytes becomes `TEXT` only when strict UTF-8, binary checks, and sensitive-content classification all pass; 1,048,577 returns `FILE_TOO_LARGE`. Provider-declared oversize produces listing `TOO_LARGE` and blocks blob fetch. Test UTF-8 BOM removal, malformed UTF-8, UTF-16, legacy bytes, null/control binary heuristics, and no truncation. `BINARY_UNSUPPORTED`, `UNSUPPORTED_ENCODING`, `SENSITIVE_FILE_BLOCKED`, `FILE_TOO_LARGE`, and `SENSITIVE_CLASSIFICATION_UNAVAILABLE` are read outcomes/errors and never ordinary tree-metadata guesses.
- [ ] Run RED:

  ```powershell
  deno test --allow-env supabase/functions/_shared/website-project-files-policy.test.ts
  ```

  Expected: import/missing exports fail.
- [ ] Implement `normalizeWebsiteProjectPath(raw, { allowRoot })`, `classifyWebsiteProjectPath(path)`, `classifyWebsiteProjectDirectoryEntry(input)`, `inspectWebsiteProjectFile(input)`, and `WebsiteProjectFilesPolicyError` with the exact codes and metadata/read boundary above. Decode JSON once; do not URL-decode paths.
- [ ] Run GREEN and adjacent security regression:

  ```powershell
  deno test --allow-env supabase/functions/_shared/website-project-files-policy.test.ts
  deno test --allow-env supabase/functions/_shared/validation.test.ts supabase/functions/_shared/security.test.ts
  ```

  Expected: all pass.
- [ ] Commit:

  ```powershell
  git add supabase/functions/_shared/website-project-files-policy.ts supabase/functions/_shared/website-project-files-policy.test.ts
  git commit -m "feat(website): add project file read policy"
  ```

## Task 3: Add caller-JWT repository-read authority and resource leases

**Files:**
- Create: `supabase/migrations/20260917100000_add_website_project_files_read_authority_v1.sql`, `supabase/tests/website_project_files_phase_a_v1.sql`
- Modify: none
- Test: `supabase/tests/website_project_files_phase_a_v1.sql`, `supabase/tests/website_concept_pre_project_v1.sql`, `supabase/tests/operator_mfa_aal2_authority_v1.sql`

**Interfaces:**
- Consumes: authenticated caller, `quote_request_id`, `DIRECTORY|FILE`
- Produces: exact `WebsiteProjectFilesAuthority`, rate/concurrency lease, safe Website Execution lifecycle projection; no repository mutation

- [ ] Create synthetic `CONTEXT_A` and `CONTEXT_B` fixtures with distinct quote request, work context, workspace, repository owner/name/external ID/node ID, binding revision, marker operation, and `project_id = null`.
- [ ] First write failing pgTAP assertions for new tables/functions, forced RLS, revoked direct access, authenticated-only execute, no anon/service-role execute, ACTIVE owner, AAL2, PRE_PROJECT null project, and exact authority keys.
- [ ] Test no workspace, `PENDING_REPOSITORY`, `REPOSITORY_PROVISIONING`, `REPOSITORY_FAILED`, legacy `READY`, missing external ID/node/marker, stale operation, `BLOCKED`, and `QUARANTINED` all deny acquisition with normalized state-specific codes; only fully verified `REPOSITORY_READY` succeeds.
- [ ] Test AAL1 owner, active non-owner, inactive/revoked owner, anonymous, and service-role contexts fail before authority projection.
- [ ] Test 30 DIRECTORY acquisitions per actor/context/minute pass and the 31st returns `PROJECT_FILES_RATE_LIMITED`; 10 FILE acquisitions pass and the 11th fails. Test context B has an independent budget.
- [ ] Test four unexpired leases pass and the fifth returns `PROJECT_FILES_CONCURRENCY_LIMITED`; release and expiry permit a later lease. Bind release to the acquiring caller.
- [ ] Test A quote with B workspace/external ID/marker/binding revision cannot produce authority. Direct table updates and client-selected repository fields remain impossible.
- [ ] Snapshot `website_repository_provisioning_operations/events` and all repository/workspace mutation ledgers before acquisitions; assert counts and content remain unchanged. Only rate bucket/read lease tables may change.
- [ ] Add the forward-only `get_website_execution_workspace_v3(uuid)` contract tests and prove `V2_BACKWARD_COMPATIBILITY=PASS` for unchanged `get_website_execution_workspace_v2(uuid)` plus `V3_EXACT_CONTRACT=PASS` for the exact closed v3 DTO. Never redefine v2 to emit v3 semantics.
- [ ] Enumerate the complete workspace-state x operation-state matrix, including null and one normalized unknown operation. Assert the exact failure-category table and the separate recovery-guidance table above, recognized failure-operation precedence for contradictory combinations, null category for `REPOSITORY_FAILED` without a recognized failure operation, zero browser inference, and false `project_files_read` outside the exact ready/complete/verified condition.
- [ ] Run RED:

  ```powershell
  npx supabase test db supabase/tests/website_project_files_phase_a_v1.sql
  ```

  Expected: missing migration functions/tables fail.
- [ ] Implement forward-only private rate/lease tables keyed by actor+context, a precise rolling 60-second count, five-minute accounting-row retention, 15-second leases, immutable authority snapshot fields, forced RLS, no direct grants, and guarded acquisition/release functions.
- [ ] Have acquisition call existing caller/work-context authority, `lws_internal.assert_operator_aal2_v1()`, lock authoritative rows, require role `owner` and status `ACTIVE`, and resolve latest verified binding/marker server-side. Do not accept repository coordinates in RPC parameters.
- [ ] Create `get_website_execution_workspace_v3(uuid)` in the new forward-only migration with the exact contract version 3 shape above, including normalized operation state, independently projected failure category and recovery guidance, project-files capability, and server-projected allowlisted GitHub HTTPS URL. Preserve `get_website_execution_workspace_v2(uuid)` unchanged. Return no external ID, node ID, installation ID, marker, or credential to browser workspace DTOs.
- [ ] Run GREEN and adjacent regressions:

  ```powershell
  npx supabase test db supabase/tests/website_project_files_phase_a_v1.sql
  npx supabase test db supabase/tests/website_concept_pre_project_v1.sql
  npx supabase test db supabase/tests/operator_mfa_aal2_authority_v1.sql
  npx supabase test db supabase/tests/website_execution_workspace_v1.sql
  ```

  Expected: all pass; PRE_PROJECT succeeds with null project; mutation-ledger snapshots remain unchanged.
- [ ] Commit:

  ```powershell
  git add supabase/migrations/20260917100000_add_website_project_files_read_authority_v1.sql supabase/tests/website_project_files_phase_a_v1.sql
  git commit -m "feat(website): add project file read authority"
  ```

## Task 4: Implement immutable directory snapshots and opaque cursors

**Files:**
- Create: `supabase/functions/_shared/website-project-files-cursor.ts`, `supabase/functions/_shared/website-project-files-cursor.test.ts`, `supabase/functions/_shared/website-project-files-provider.ts`, `supabase/functions/_shared/website-project-files-provider.test.ts`, `supabase/functions/_shared/website-project-files-service.ts`, `supabase/functions/_shared/website-project-files-service.test.ts`
- Modify: `supabase/functions/_shared/github-app-token.ts`, `supabase/functions/_shared/github-app-token.test.ts`, `supabase/functions/_shared/github-http.ts`, `supabase/functions/_shared/github-http.test.ts` only if the `WEBSITE_PROJECT_FILES_READ` operation is not yet exposed
- Test: `supabase/functions/_shared/website-project-files-cursor.test.ts`, `supabase/functions/_shared/website-project-files-provider.test.ts`, `supabase/functions/_shared/website-project-files-service.test.ts`, `supabase/functions/_shared/github-app-config.test.ts`, `supabase/functions/_shared/github-app-token.test.ts`, `supabase/functions/_shared/github-http.test.ts`

**Interfaces:**
- Consumes: server authority, normalized directory, optional opaque cursor
- Produces: immutable snapshot directory DTO, deterministic entries, optional five-minute cursor

- [ ] Write cursor RED tests for canonical payload/signature, five-minute exact TTL, tamper, wrong key, expired/future issue time, actor/context/repository/binding/commit/root-tree/directory/directory-tree mismatch, changed offset, and configuration failure.
- [ ] Implement the cursor interface exactly as defined above using a dedicated secret; never reuse browser data as key material.
- [ ] Write provider RED tests named `directory listing resolves ref to immutable commit`, `directory traversal uses commit tree only`, `marker and external repository identity are mandatory`, `tree entries reject canonical path and object type mismatch`, `provider timeout throttle malformed and snapshot unavailable normalize`, and `provider exposes no write method`.
- [ ] Mock `CONTEXT_A` and `CONTEXT_B`; substitute B metadata/tree/marker at every provider boundary and assert failure before any result.
- [ ] Write service RED tests for root path, nested path, directories-first then Unicode-code-point sort, 500-entry page, 501-entry continuation, 512-KiB response ceiling, lazy non-recursive traversal, empty directory, invalid cursor, and snapshot unavailable. Assert the service has no acquisition/release dependency.
- [ ] Add exact directory projection tests: safe blob -> selectable `READABLE_CANDIDATE`; null/unknown-size safe blob -> selectable `READABLE_CANDIDATE`; declared oversize -> non-selectable `TOO_LARGE`; blocked path -> redacted non-selectable `BLOCKED_CREDENTIAL`; known symlink -> inert non-selectable `UNSUPPORTED`; known submodule/Git-link/commit -> inert non-selectable `UNSUPPORTED`.
- [ ] Add provider/service tests proving unknown object type, invalid mode/type, malformed metadata, canonical-path mismatch, redirect, root escape, and tree truncation fail the entire current request closed with zero partial entries. Assert no symlink target or submodule repository is fetched.
- [ ] Assert cursor continuation reuses its bound commit and directory tree SHA even after the branch mock moves. Assert a caller cannot include or construct a historical commit/ref in request input.
- [ ] Run RED:

  ```powershell
  deno test --allow-env supabase/functions/_shared/website-project-files-cursor.test.ts supabase/functions/_shared/website-project-files-provider.test.ts supabase/functions/_shared/website-project-files-service.test.ts
  ```

  Expected: missing exports/behavior fail.
- [ ] Implement `signWebsiteProjectFilesCursor`/`verifyWebsiteProjectFilesCursor`, `createWebsiteProjectFilesProvider`, and `createWebsiteProjectFilesService`. Resolve `authority.repositoryRef` once per new list request, verify provider metadata default branch cannot override it, traverse trees by SHA, validate every returned path/type/SHA, map known unsupported entries inertly, fail unknown/malformed structures as a whole request, and paginate only normalized entries.
- [ ] Build the serialized result incrementally with `TextEncoder`; reserve the measured fixed gateway-envelope bytes and stop before 500 entries or 524,288 bytes for the complete response. Add an assertion that `new TextEncoder().encode(JSON.stringify(envelope)).byteLength <= 524288`. If provider data cannot be represented safely, fail rather than truncate an entry.
- [ ] For timeout, throttle, network failure, malformed response, and snapshot-unavailable tests, spy on the read-only HTTP client and assert exactly one provider attempt and zero automatic retries.
- [ ] Pass the single operation-wide abort signal into every approved GitHub HTTP call without resetting its deadline, and use a repository-ID-scoped installation token with `{ metadata: "read", contents: "read" }`; never log or return token/raw body.
- [ ] Run GREEN and adjacent provider regressions:

  ```powershell
  deno test --allow-env supabase/functions/_shared/website-project-files-cursor.test.ts supabase/functions/_shared/website-project-files-provider.test.ts supabase/functions/_shared/website-project-files-service.test.ts
  deno test --allow-env --allow-read supabase/functions/_shared/github-app-config.test.ts supabase/functions/_shared/github-app-token.test.ts supabase/functions/_shared/github-http.test.ts
  ```

  Expected: all pass; write-operation static assertion remains zero.
- [ ] Commit:

  ```powershell
  git add supabase/functions/_shared/website-project-files-cursor.ts supabase/functions/_shared/website-project-files-cursor.test.ts supabase/functions/_shared/website-project-files-provider.ts supabase/functions/_shared/website-project-files-provider.test.ts supabase/functions/_shared/website-project-files-service.ts supabase/functions/_shared/website-project-files-service.test.ts supabase/functions/_shared/github-app-token.ts supabase/functions/_shared/github-app-token.test.ts supabase/functions/_shared/github-http.ts supabase/functions/_shared/github-http.test.ts
  git commit -m "feat(website): add bounded project directory reads"
  ```

  Stage only prerequisite files that actually required the bounded read operation; omit unchanged paths from `git add`.

## Task 5: Implement safe file reads on a newly resolved snapshot

**Files:**
- Modify: `supabase/functions/_shared/website-project-files-provider.ts`, `supabase/functions/_shared/website-project-files-provider.test.ts`, `supabase/functions/_shared/website-project-files-service.ts`, `supabase/functions/_shared/website-project-files-service.test.ts`
- Create: none
- Test: `supabase/functions/_shared/website-project-files-provider.test.ts`, `supabase/functions/_shared/website-project-files-service.test.ts`, `supabase/functions/_shared/website-project-files-policy.test.ts`

**Interfaces:**
- Consumes: server authority and normalized file path only
- Produces: exact safe file DTO at the current canonical commit or stable failure

- [ ] Add failing tests `direct read re-resolves current canonical commit`, `direct read cannot select historical commit`, `parent tree traversal validates exact blob path`, and `changed branch yields new snapshot SHA`.
- [ ] Add failing tests for preflight declared oversize, streamed/decoded oversize, strict UTF-8, BOM removal, malformed/legacy encoding, binary, sensitive path/content, classifier unavailable, symlink/submodule/Git link, no partial content, no provider URL, and no data/object/download URL.
- [ ] Assert `TEXT` is produced only after fetched bytes pass decoded-size, strict UTF-8, binary, and sensitive-content checks. Assert `FILE_TOO_LARGE`, `BINARY_UNSUPPORTED`, `UNSUPPORTED_ENCODING`, `SENSITIVE_FILE_BLOCKED`, and `SENSITIVE_CLASSIFICATION_UNAVAILABLE` remain authoritative read outcomes/errors; listing metadata cannot pre-decide them except declared oversize and blocked pathname.
- [ ] Add provider failure cases: timeout, throttling, malformed JSON/result, wrong repository ID, wrong canonical path, wrong object type, missing commit/tree/blob, and unavailable snapshot. Assert browser-facing errors contain only stable code/status.
- [ ] Run RED:

  ```powershell
  deno test --allow-env supabase/functions/_shared/website-project-files-provider.test.ts supabase/functions/_shared/website-project-files-service.test.ts supabase/functions/_shared/website-project-files-policy.test.ts
  ```

  Expected: new read tests fail.
- [ ] Implement `service.read()` by resolving `authority.repositoryRef` exactly once, then call `provider.readFile()` with that immutable commit/root tree. `provider.readFile()` traverses parent trees without resolving a ref, validates exact blob SHA/path/type, enforces provider size before fetch and decoded size after base64, then passes bytes through policy. Never accept cursor/commit/ref on direct browser reads.
- [ ] For every failed provider operation, assert exactly one attempted metadata/ref/commit/tree/blob call at the failing boundary and no retry after dispatch.
- [ ] Return `media_type: "text/plain"`, `encoding: "utf-8"`, normalized path, exact decoded byte count, and inert text only.
- [ ] Run GREEN and full shared service regression with the same command; expect all pass.
- [ ] Commit:

  ```powershell
  git add supabase/functions/_shared/website-project-files-provider.ts supabase/functions/_shared/website-project-files-provider.test.ts supabase/functions/_shared/website-project-files-service.ts supabase/functions/_shared/website-project-files-service.test.ts
  git commit -m "feat(website): add safe project file reads"
  ```

## Task 6: Route exact list/read actions through commercial-operator-command

**Files:**
- Modify: `supabase/functions/commercial-operator-command/handler.ts`, `supabase/functions/commercial-operator-command/index.ts`, `supabase/functions/commercial-operator-command/handler.test.ts`
- Create: none
- Test: `supabase/functions/commercial-operator-command/handler.test.ts`

**Interfaces:**
- Consumes: exact browser DTOs
- Produces: `service.list`/`service.read` results in existing no-store envelope

- [ ] Add failing handler tests with exact names `project directory accepts only bounded browser intent`, `project file read accepts only bounded browser intent`, `project files require owner AAL2 before service dispatch`, `project files preserve caller JWT authority`, `project file errors map without provider leakage`, and `project read actions cannot dispatch mutation dependencies`.
- [ ] For both actions reject every forbidden field listed in Global Constraints, unknown keys, omitted cursor/path, non-UUID quote IDs, non-string paths/cursors, and non-null/non-string cursor values.
- [ ] Add response assertions for all stable statuses/codes, `Cache-Control: no-store`, `Referrer-Policy: no-referrer`, `X-Content-Type-Options: nosniff`, exact success result, and no token/provider/raw error fields.
- [ ] Add index composition tests proving the caller JWT client invokes only acquisition/release RPCs and the service; no service-role client, provisioning RPC, repository operation, provider write, build, preview, publication, or GitHub mutation is referenced by either action branch.
- [ ] Add an index routing test proving the Website Execution read path switches from unchanged `get_website_execution_workspace_v2(uuid)` to `get_website_execution_workspace_v3(uuid)` only as part of Phase A; project-file actions remain separate exact routes.
- [ ] Add index runtime tests proving exactly one acquisition and one same-caller release in success, policy failure, provider failure, timeout, and thrown-error paths. Test the release RPC itself is idempotent for an already released or expired same-caller lease and rejects another caller.
- [ ] Use a fake clock to prove sequential provider calls share one deadline: cumulative 9,999 ms may complete, cumulative 10,000 ms aborts before a later call/retry, and the 15-second lease remains unexpired until `finally` releases it. Assert four active requests deny the fifth for their full operation lifetime.
- [ ] Run RED:

  ```powershell
  deno test --allow-env --allow-read supabase/functions/commercial-operator-command/handler.test.ts
  ```

  Expected: new actions are invalid/missing.
- [ ] Add the two typed inputs, `APPLICATION_ACTIONS`, exact-key branches, path/cursor primitive validation, dependency methods `executeWebsiteProjectDirectoryList` and `executeWebsiteProjectFileRead`, explicit AAL2 requirement, and normalized error mapping.
- [ ] In `supabase/functions/commercial-operator-command/index.ts`, compose the approved config/token/HTTP/provider/service once per request boundary without exposing secrets; acquire using `clientFor(jwt)`, execute provider read, and perform the single idempotent release in `finally`.
- [ ] Run GREEN, typecheck, and v118 regression:

  ```powershell
  deno test --allow-env --allow-read supabase/functions/commercial-operator-command/handler.test.ts
  deno check supabase/functions/commercial-operator-command/index.ts
  node --test scripts/operator-website-execution.test.mjs
  ```

  Expected: all pass and provisioning route remains present.
- [ ] Commit:

  ```powershell
  git add supabase/functions/commercial-operator-command/handler.ts supabase/functions/commercial-operator-command/index.ts supabase/functions/commercial-operator-command/handler.test.ts
  git commit -m "feat(website): route project file reads"
  ```

## Task 7: Add frontend requests, exact DTO validation, and in-memory state

**Files:**
- Create: `assets/js/operator-website-project-files.mjs`, `scripts/operator-website-project-files.test.mjs`
- Modify: `assets/js/operator-website-execution.mjs`, `scripts/operator-website-execution.test.mjs`
- Test: both Node test files

**Interfaces:**
- Consumes: quote/context/workspace snapshot, gateway, owner+AAL2 capability, list/read DTOs
- Produces: exact requests, validated frozen projections, in-memory reducer/controller state

- [ ] Write RED unit tests for exact request builders, root path/cursor shape, extra authority-field rejection, exact response keys/types, safe HTTPS navigation, and rejection of external ID/token/provider URL/local path fields.
- [ ] Validate listing readability exactly as `DIRECTORY | READABLE_CANDIDATE | TOO_LARGE | SENSITIVE_BLOCKED | UNSUPPORTED`; reject stale listing `TEXT` and `BINARY_UNSUPPORTED` values. Validate the redacted `BLOCKED_CREDENTIAL` variant has no path, original filename, size, object SHA/ID, or action target.
- [ ] Add exact-key `contract_version: 3` fixtures from the v3 route and lifecycle view tests for no workspace, `PENDING_REPOSITORY`, `REPOSITORY_PROVISIONING`, `REPOSITORY_READY`, `REPOSITORY_FAILED`, operation `BLOCKED`, operation `QUARANTINED`, and legacy `READY` denied until verified. Enumerate the complete workspace-state x operation-state matrix, including null and one normalized unknown operation, and assert exact independently projected failure category, recovery guidance, and `capabilities.project_files_read` for each fixture. No frontend branch may derive failure category.
- [ ] Add reducer tests for loading, empty directory, denied, unavailable, not found, sensitive, binary, unsupported encoding, oversized, stale binding, generic failure, expanded directories, selected path, and cursor append.
- [ ] Add reducer tests proving `DIRECTORY` is expandable, `READABLE_CANDIDATE` is a selectable file candidate, and `TOO_LARGE`, `UNSUPPORTED`, and `SENSITIVE_BLOCKED`/`BLOCKED_CREDENTIAL` are inert and non-selectable. Do not show a text/binary/content classification before a read result.
- [ ] Add snapshot tests named `tree and file same commit may display`, `new file snapshot blocks stale tree presentation`, and `changed snapshot refreshes root before content display`. Assert content remains hidden until the refreshed tree commit equals the file commit.
- [ ] Run RED:

  ```powershell
  node --test scripts/operator-website-project-files.test.mjs scripts/operator-website-execution.test.mjs
  ```

  Expected: missing module/contract v3 tests fail.
- [ ] Implement the exact request/result/service/provider types above, exact contract-v3 validation, frozen state transitions, and an explicit `ownerEligible: identity.role === "owner"` input passed by the child. `options.requireAal2` remains the existing child option and is called immediately before the first gateway list/read in a user gesture. Store no repository content outside module memory.
- [ ] Update Website Execution validation/view for contract v3 and normalized lifecycle. Use only server-projected GitHub navigation. Remove client-generated VS Code Web capability from the ready view.
- [ ] Run GREEN with the same command; expect all pass.
- [ ] Commit:

  ```powershell
  git add assets/js/operator-website-project-files.mjs assets/js/operator-website-execution.mjs scripts/operator-website-project-files.test.mjs scripts/operator-website-execution.test.mjs
  git commit -m "feat(website): model project files state"
  ```

## Task 8: Build the internal Projectbestanden tree UI

**Files:**
- Modify: `assets/js/operator-website-project-files.mjs`, `assets/js/operator-website-execution-child.mjs`, `assets/css/operator-dashboard.css`, `scripts/operator-website-project-files.test.mjs`, `scripts/operator-website-execution.test.mjs`
- Create: none
- Test: both Node/Playwright test files

**Interfaces:**
- Consumes: validated Website snapshot and list gateway
- Produces: internal lazy tree and lifecycle/status surface; no new slot

- [ ] Add Playwright RED tests for all required lifecycle states and for `Projectbestanden` selecting/focusing an internal section without `window.open`, reservation, registry entry, or new module slot.
- [ ] Test owner+AAL2 gating: non-owner/status-authorized callers see a disabled access state and make zero file requests; owner calls the existing child option `options.requireAal2()` before first list.
- [ ] Test root list, nested lazy expansion, directories-first display, empty directory, 500-entry page, `next_cursor` continuation, refresh, keyboard focus, stable dimensions, mobile overflow, and loading lockout.
- [ ] Test the exact listing UI mapping: `DIRECTORY` expands, `READABLE_CANDIDATE` can request a file read, `TOO_LARGE` and `UNSUPPORTED` are inert, and the redacted `SENSITIVE_BLOCKED`/`BLOCKED_CREDENTIAL` row exposes no original filename or target. No listing row claims `TEXT` or `BINARY_UNSUPPORTED` before read.
- [ ] Run RED:

  ```powershell
  node --test scripts/operator-website-project-files.test.mjs scripts/operator-website-execution.test.mjs
  ```

  Expected: host/controller/tree assertions fail.
- [ ] Replace the current files-button scroll-only behavior with a Project Files host mounted by `createWebsiteProjectFilesController`. Pass only gateway, `requireAal2`, owner capability, and current safe context; do not pass repository coordinates.
- [ ] Render entries through `createElement` and `textContent`; buttons carry only normalized paths in closure/state, not HTML attributes assembled from provider text.
- [ ] Keep GitHub navigation only when server-authorized. Remove Preview and VS Code controls throughout this Phase A plan; restoring either belongs to a separately approved Phase B/C plan. Render no fake disabled future controls.
- [ ] Add responsive CSS with bounded tree/content tracks, `min-width: 0`, scroll containers, visible focus, and no nested decorative cards.
- [ ] Run GREEN and managed-child regression:

  ```powershell
  node --test scripts/operator-website-project-files.test.mjs scripts/operator-website-execution.test.mjs scripts/operator-workspace.test.mjs
  ```

  Expected: all pass; module registry contains no files/build/editor slot.
- [ ] Commit:

  ```powershell
  git add assets/js/operator-website-project-files.mjs assets/js/operator-website-execution-child.mjs assets/css/operator-dashboard.css scripts/operator-website-project-files.test.mjs scripts/operator-website-execution.test.mjs
  git commit -m "feat(website): render project files tree"
  ```

## Task 9: Add inert file content and snapshot-safe refresh/retention

**Files:**
- Modify: `assets/js/operator-website-project-files.mjs`, `assets/js/operator-website-execution-child.mjs`, `assets/css/operator-dashboard.css`, `scripts/operator-website-project-files.test.mjs`
- Create: none
- Test: `scripts/operator-website-project-files.test.mjs`

**Interfaces:**
- Consumes: selected safe file path and validated read result
- Produces: inert selectable text only after tree/read snapshots align

- [ ] Add RED malicious fixtures containing HTML, SVG, script, Markdown, template code, hostile filename text, event-handler strings, and closing tags. Assert zero script/event execution and no repository-derived `innerHTML`, trusted markup, object URL, or data URL.
- [ ] Add RED tests for file metadata/path/size/encoding/commit display and every stable state: access denied, provider unavailable, file not found, sensitive, binary, unsupported encoding, oversized, stale binding, and generic fail-closed.
- [ ] Assert the content pane presents `TEXT` only from a successful file result after all server read checks. Present `FILE_TOO_LARGE`, `BINARY_UNSUPPORTED`, `UNSUPPORTED_ENCODING`, `SENSITIVE_FILE_BLOCKED`, and `SENSITIVE_CLASSIFICATION_UNAVAILABLE` only as read outcomes/errors, never as guessed listing classifications.
- [ ] Add RED clearing tests for logout/authorization failure, revoke callback, controller/module disposal, work-context change, workspace change, binding revision change, repository state downgrade, and owner/AAL2 loss.
- [ ] Add a background-refresh failure test: mark the current tree/content stale, disable all further list/read controls, retain no content as current authority, and require a successful workspace revalidation before another file request.
- [ ] Spy on localStorage, sessionStorage, IndexedDB, Cache API/service worker, history/location/hash, and URL creation; assert zero repository-content writes.
- [ ] Test changed snapshot behavior exactly: read result at commit B while tree is commit A remains hidden, clears pagination, and triggers a normal root request that resolves the then-current canonical ref. Display the pending B content only if that root response is also commit B; if it is commit C or fails, permanently discard B content and present only the C tree or unavailable state. The browser never requests B explicitly.
- [ ] Run RED:

  ```powershell
  node --test scripts/operator-website-project-files.test.mjs
  ```

  Expected: content/snapshot/clear tests fail.
- [ ] Implement content pane with `textContent`, selected metadata, stale guard, authoritative canonical-root refresh, conditional same-commit promotion of pending content, and one `clearAuthorityState()` path used by every listed lifecycle event.
- [ ] Integrate Website child refresh so context/workspace/binding/state changes reach the controller before any prior content remains visible; authorization failure clears immediately even when background refresh would otherwise retain the previous snapshot.
- [ ] Run GREEN and adjacent Website regression:

  ```powershell
  node --test scripts/operator-website-project-files.test.mjs scripts/operator-website-execution.test.mjs
  ```

  Expected: all pass.
- [ ] Commit:

  ```powershell
  git add assets/js/operator-website-project-files.mjs assets/js/operator-website-execution-child.mjs assets/css/operator-dashboard.css scripts/operator-website-project-files.test.mjs
  git commit -m "feat(website): render safe project file content"
  ```

## Task 10: Verify cross-context, resource, and mutation isolation end to end

**Files:**
- Modify: none; if a command fails, return to the owning Task 2-9 test/code files, make a separate focused RED/GREEN repair commit there, then restart Task 10
- Create: none
- Test: all Phase A test surfaces

**Interfaces:**
- Consumes: `CONTEXT_A`/`CONTEXT_B` adversarial substitutions and mutation spies
- Produces: executable isolation/no-write evidence

- [ ] Verify the tests authored in Tasks 2-9 contain the explicit substitution matrix: A request with B path assumptions, A cursor under B, B provider metadata/tree/blob/marker under A, external repository ID mismatch, marker context/operation mismatch, binding revision mismatch, stale workspace, and changed repository node ID.
- [ ] Verify the directory-object regression matrix: known structurally valid symlink/submodule/Git-link/commit entries are inert `UNSUPPORTED`; unknown object/mode, invalid mode/type, malformed metadata, canonical mismatch, redirect, and root escape fail the entire current request with no partial listing.
- [ ] Run the matrix and require every case to return a stable fail-closed code, no provider content, no stale UI content, no cursor reuse, and lease release.
- [ ] Run the exact resource tests for 60-second 30/10 budgets, four concurrent reads, 10-second timeout, 500 entries, complete-envelope 512 KiB, 1 MiB file, cursor expiry, provider oversized body, and classifier outage.
- [ ] Run the exact static test `Phase A provider dependency graph exposes read operations only` and runtime mutation spies authored in Tasks 3-9. Require zero repository create/provision operation, GitHub POST/PATCH/PUT/DELETE, commit/push, build/preview, publication, production release, or Task14 calls.
- [ ] Run the pgTAP snapshots of repository operation/event counts and workspace binding fields before/after list/read; only read budget/lease lifecycle may change.
- [ ] Run verification:

  ```powershell
  npx supabase test db supabase/tests/website_project_files_phase_a_v1.sql
  deno test --allow-env supabase/functions/_shared/website-project-files-policy.test.ts supabase/functions/_shared/website-project-files-cursor.test.ts supabase/functions/_shared/website-project-files-provider.test.ts supabase/functions/_shared/website-project-files-service.test.ts
  deno test --allow-env --allow-read supabase/functions/commercial-operator-command/handler.test.ts
  node --test scripts/operator-website-project-files.test.mjs scripts/operator-website-execution.test.mjs scripts/operator-workspace.test.mjs
  ```

  Expected: all pass with two synthetic contexts, one provider attempt at each injected failure, and zero mutation-spy calls.
- [ ] Run `git status --short` and require clean status. Task 10 is verification-only and creates no commit. Any repair must return to its owning task and its explicit file/commit boundary.

## Task 11: Run the complete local Phase A release gate

**Files:**
- Create: `docs/superpowers/checkpoints/2026-09-17-website-execution-project-files-phase-a-verification.md`
- Modify: none unless a focused failing Phase A test identifies a local defect, which must be fixed in its owning prior-task file and committed separately before this checkpoint
- Test: complete command list below

**Interfaces:**
- Consumes: final local Phase A candidate and baseline evidence
- Produces: local verification checkpoint; no deployment authorization

- [ ] Re-fetch and record current `origin/main`, candidate HEAD, merge-base, full commit list, and the preserved v118 source relationship. Stop on unexplained baseline movement.
- [ ] Re-run every Task 1 prerequisite `git merge-base --is-ancestor` check against the final candidate and record each exact ancestor result. Any failure stops release verification and requires a separate controller-approved prerequisite integration plan plus complete Phase A plan revalidation; do not integrate prerequisite code in this task.
- [ ] Run database gates:

  ```powershell
  npx supabase db reset
  npx supabase test db supabase/tests/website_project_files_phase_a_v1.sql
  npx supabase test db supabase/tests/website_concept_pre_project_v1.sql
  npx supabase test db supabase/tests/website_execution_workspace_v1.sql
  npx supabase test db supabase/tests/operator_mfa_aal2_authority_v1.sql
  ```

  Expected: all pass; record exact assertion counts.
- [ ] Run Deno unit/integration gates:

  ```powershell
  deno test --allow-env supabase/functions/_shared/website-project-files-policy.test.ts supabase/functions/_shared/website-project-files-cursor.test.ts supabase/functions/_shared/website-project-files-provider.test.ts supabase/functions/_shared/website-project-files-service.test.ts
  deno test --allow-env --allow-read supabase/functions/commercial-operator-command/handler.test.ts
  deno check supabase/functions/commercial-operator-command/index.ts
  ```

  Expected: all pass with no additional permissions beyond those shown.
- [ ] Run frontend/managed-workspace gates:

  ```powershell
  node --test scripts/operator-website-project-files.test.mjs scripts/operator-website-execution.test.mjs scripts/operator-workspace.test.mjs
  ```

  Expected: all pass, no new slot, no future control, no unsafe rendering/persistence.
- [ ] Run `deno test --allow-env supabase/functions/_shared/website-project-files-provider.test.ts --filter "Phase A provider dependency graph exposes read operations only"` and record zero reachable repository/provision/build/preview/publication mutation calls.
- [ ] Run the two existing repository-wide public-page regression scripts and compare any failure exactly to the pre-implementation baseline. Do not fix unrelated debt.

  ```powershell
  npm run test:page-end
  npm run test:visual-contract
  ```
- [ ] Write the checkpoint with commit SHAs, exact command outputs/counts, synthetic fixture statement, no-write counters, baseline debt, and `DEPLOY_AUTHORIZED=NEE`, `PUSH_AUTHORIZED=NEE`.
- [ ] Verify scope:

  ```powershell
  git status --short
  git diff --check
  git log --oneline --decorate --max-count=20
  ```

  Expected: only the uncommitted checkpoint exists before its commit; no generated build output or lockfile drift.
- [ ] Commit:

  ```powershell
  git add docs/superpowers/checkpoints/2026-09-17-website-execution-project-files-phase-a-verification.md
  git commit -m "docs(website): verify project files phase a"
  ```

- [ ] Final local status must be clean. Stop for controller implementation review; do not push, deploy, migrate remotely, provision, or create repositories.

## Requirement Coverage Matrix

| Approved requirement | Planned proof |
|---|---|
| One managed Website child; no final build module | Tasks 7-9 managed-child/static registry tests |
| Phase A only; B/C/D/Task14 excluded | Global Constraints, Tasks 8 and 10 absence/mutation tests |
| Exact list/read actions via commercial gateway | Task 6 DTO/route tests |
| Browser has no repository authority | Tasks 3, 6, 7 exact-key and server-resolution tests |
| Owner+AAL2 caller-JWT chain | Tasks 3 and 6 SQL/handler tests |
| PRE_PROJECT with null project | Task 3 synthetic fixtures and pgTAP |
| Repository-ready gating and failure states | Tasks 3, 7, 8 lifecycle tests |
| Immutable list snapshot and pinned cursor | Task 4 provider/cursor/service tests |
| Direct read re-resolves current commit | Tasks 5 and 7 snapshot tests |
| Stale tree/new file never presented coherently | Tasks 7 and 9 UI refresh tests |
| 500 entries / complete-envelope 512 KiB / lazy traversal / 5-minute cursor | Task 4 boundaries |
| 1 MiB / strict UTF-8 / BOM / binary / no truncation/download | Tasks 2 and 5 |
| Path normalization and unsafe object rejection | Task 2 exhaustive policy tests |
| Sensitive filenames/content and classifier outage | Tasks 2 and 5 |
| Two-context adversarial isolation | Tasks 3, 4, and 10 |
| Provider timeout/throttle/malformed/not-found/snapshot errors | Tasks 4 and 5 |
| 60-second 30/10 rates, four concurrent, 10-second timeout | Tasks 3, 4, and 10 |
| Inert rendering and hostile fixtures | Task 9 Playwright tests |
| Clear state on logout/revoke/dispose/context/binding/state/auth change | Task 9 retention tests |
| No local/session/IndexedDB/cache/URL persistence | Task 9 spies |
| No dead VS Code/Build/Preview controls | Tasks 7 and 8 |
| Repository creation/provision/write/build/preview/publication unreachable | Tasks 3, 6, 10 static/runtime proof |
| Backend v118/main divergence preserved | Task 1 Case A/B gate and Task 11 evidence |
| Exact-ancestry-only prerequisite model | Task 1 ancestry stop gate and Task 11 repeated ancestry evidence |
| Metadata-only pre-read directory semantics | Exact DTO plus Tasks 2, 4, 7, and 8 mapping tests |
| `TEXT` only after successful file read | Exact DTO boundary plus Tasks 2, 5, 7, and 9 tests |
| Known unsupported entries are inert and non-selectable | Tasks 2, 4, 7, 8, and 10 tests |
| Unknown or malformed provider objects fail the whole request closed | Tasks 2, 4, and 10 provider/service tests |
| Total server failure-category projection with zero browser inference | Exact v3 contract plus Tasks 3 and 7 Cartesian tests |
| V2 preserved and forward-only v3 introduced | Tasks 3, 6, and 7 contract/routing tests |
| Deterministic provider-token basename policy | Exact classifier contract plus Task 2 block/allow and boundary fixtures |

```text
SPEC_REQUIREMENTS_COVERED=31
SPEC_REQUIREMENTS_MISSING=0
PLACEHOLDERS=0
```

## Plan-Gate Validation

Before committing this plan, run:

```powershell
git status --short
git diff --check
git diff --name-status
git diff --stat
```

Require exactly one path:

```text
docs/superpowers/plans/2026-09-17-website-execution-project-files-phase-a-implementation-plan.md
```

Create exactly one local docs-only commit:

```powershell
git add docs/superpowers/plans/2026-09-17-website-execution-project-files-phase-a-implementation-plan.md
git commit -m "docs(website): harden project files phase a plan"
```

Then require:

```powershell
git status --short
git show --stat --oneline HEAD
git diff HEAD^ HEAD --name-status
```

Expected: clean worktree and one added plan file. No push.