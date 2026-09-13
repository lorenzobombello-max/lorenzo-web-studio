# GitHub Repository Provider and Website Starter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the isolated LWS GitHub App repository provisioning, canonical website starter, per-dossier customer repository lifecycle, and development-workspace integration without mixing customer islands or LWS core code.

**Architecture:** Use a server-side GitHub App as the control plane. Every `website_work_context_id` remains a separate customer island with exactly one private repository, technical workspace, preview/cache/artifact namespace, and project-file context. The canonical starter is an independent LWS-controlled source and never a shared mutable customer workspace.

**Tech Stack:** Deno/TypeScript Edge Functions, Supabase/PostgreSQL, GitHub App API, Astro static output starter, existing Operator/Multi-Screen architecture.

**Spec:** docs/superpowers/specs/2026-09-13-github-repository-provider-and-website-starter-design.md

## Execution Rules

- This plan does not itself authorize implementation, migration execution, GitHub configuration, external API calls, deployment, push, or production/customer mutation. Start only after the OWNER approves the execution method.
- Execute tasks in order. Stop at every OWNER gate. Approval of one gate does not approve a later gate.
- Use test-first development: add the smallest failing test, observe the named failure, implement only enough to pass, run focused and adjacent regressions, inspect scope, then commit.
- Keep commits independently reviewable. Never combine a database authority change, provider side effect, UI change, and release activation in one commit.
- Preserve the existing untracked `supabase/functions/_shared/repository-provisioning.ts`, `supabase/functions/_shared/repository-provisioning.test.ts`, and `docs/superpowers/specs/2026-09-13-pre-project-repository-provider-v2-design.md` until Task 1 deliberately adopts the two provider files. Do not alter the earlier V2 design.
- Never reinterpret the inert `bootstrap: "NONE"` contract. Introduce a reviewed V2 request before template generation.
- Derive repository owner, name, visibility, starter, branch, host, repository URL, token scope, local root, preview namespace, cache key and artifact prefix server-side.
- Keep every token in memory for no more than one hour. Never return, persist or log App JWTs, installation tokens, PEM material, authorization headers, authenticated Git remotes or temporary download URLs.
- Do not add PAT, OAuth-user-token, installation-wide-token, service-role fallback, delete, transfer, archive, visibility-change, force-push, workflow-write, arbitrary-content, webhook or production-publish behavior.
- Keep customer source out of this repository. The canonical starter is a separate private GitHub Template Repository; every generated customer repository is private and dedicated to one `website_work_context_id`.
- Keep Website and SDF data planes separate. Security remains a control plane and cannot become a shared mutable customer data plane.
- Use forward-only migrations. Do not edit committed migrations. Local `supabase db reset` is allowed only in an implementation worktree; production migration execution remains separately gated.
- Commands use caller JWT, active owner, AAL2, exact keys, deterministic identifiers, durable idempotency and immutable audit. Prefixes and names are addressing, never authorization.
- No automatic orphan deletion or same-name adoption. Uncertain outcomes enter reconciliation or quarantine.
- PRE_PROJECT can never publish to production. Promotion preserves the same context, workspace, repository, Git history and provenance.
- Before every commit run `git diff --check`, inspect `git status --short`, and stage only files listed by that task.

## Fixed Contracts

Repository name:

```text
lws-web-<lowercase website_work_context_id without hyphens>
```

Versioned internal provider request:

```ts
export type RepositoryProvisioningRequestV2 = Readonly<{
  contractVersion: 2;
  operationId: string;
  websiteWorkContextId: string;
  repositoryName: string;
  visibility: "PRIVATE";
  defaultBranch: "main";
  bootstrap: "GITHUB_TEMPLATE";
  starter: Readonly<{
    source: string;
    version: string;
    commitSha: string;
    templateRepositoryId: string;
  }>;
}>;
```

Browser provisioning intent:

```ts
export type ProvisionWebsiteRepositoryAction = Readonly<{
  action: "provision_website_repository";
  website_workspace_id: string;
  website_work_context_id: string;
  idempotency_key: string;
}>;
```

Project-file read intent:

```ts
export type WebsiteProjectFileRef =
  | Readonly<{ kind: "DEFAULT_BRANCH"; value: "main" }>
  | Readonly<{ kind: "BOUND_BRANCH"; value: string }>
  | Readonly<{ kind: "BOUND_COMMIT"; value: string }>;

export type ReadWebsiteProjectFileAction = Readonly<{
  action: "read_website_project_file";
  website_work_context_id: string;
  path: string;
  ref: WebsiteProjectFileRef;
}>;
```

Provider result and marker:

```ts
export type VerifiedRepositoryBindingV2 = Readonly<{
  provider: "GITHUB";
  providerRepositoryId: string;
  providerNodeId: string;
  owner: string;
  name: string;
  visibility: "PRIVATE";
  defaultBranch: "main";
  starterSource: string;
  starterVersion: string;
  starterCommitSha: string;
  repositoryMarkerCommitSha: string;
}>;

export type LwsProjectMarkerV1 = Readonly<{
  schema_version: 1;
  website_work_context_id: string;
  repository_provisioning_operation_id: string;
  starter_source: string;
  starter_version: string;
  starter_commit_sha: string;
}>;
```

## File Map

### Current repository: create

- `supabase/functions/_shared/github-app-config.ts`
- `supabase/functions/_shared/github-app-config.test.ts`
- `supabase/functions/_shared/github-app-token.ts`
- `supabase/functions/_shared/github-app-token.test.ts`
- `supabase/functions/_shared/github-http.ts`
- `supabase/functions/_shared/github-http.test.ts`
- `supabase/functions/_shared/github-repository-provider.ts`
- `supabase/functions/_shared/github-repository-provider.test.ts`
- `supabase/functions/_shared/repository-provisioning-store.ts`
- `supabase/functions/_shared/repository-provisioning-store.test.ts`
- `supabase/functions/_shared/website-project-files.ts`
- `supabase/functions/_shared/website-project-files.test.ts`
- `supabase/functions/_shared/website-preview-build-contract.ts`
- `supabase/functions/_shared/website-preview-build-contract.test.ts`
- `supabase/migrations/20260914090000_add_website_repository_provisioning_v1.sql`
- `supabase/tests/website_repository_provisioning_v1.sql`
- `scripts/website-workspace-launcher.mjs`
- `scripts/website-workspace-launcher.test.mjs`
- `scripts/website-repository-isolation.test.mjs`
- `scripts/website-preview-isolation.test.mjs`
- `scripts/github-repository-provider-test-island.mjs`
- `scripts/github-repository-provider-test-island.test.mjs`
- `scripts/website-repository-release-gate.mjs`
- `scripts/website-repository-release-gate.test.mjs`
- `assets/js/operator-project-files.mjs`
- `operator/test/project-files.html`
- `scripts/operator-project-files.test.mjs`

### Current repository: modify

- `supabase/functions/_shared/repository-provisioning.ts`
- `supabase/functions/_shared/repository-provisioning.test.ts`
- `supabase/functions/commercial-operator-command/handler.ts`
- `supabase/functions/commercial-operator-command/index.ts`
- `supabase/functions/commercial-operator-command/handler.test.ts`
- `supabase/functions/commercial-operator-command/caller-jwt-read-path.test.ts`
- `assets/js/operator-website-execution.mjs`
- `assets/js/operator-website-execution-child.mjs`
- `assets/js/operator-module-registry.mjs`
- `scripts/operator-website-execution.test.mjs`
- `scripts/operator-project-requirements.test.mjs`
- `scripts/operator-workspace.test.mjs`
- `scripts/dossier-continuity-regression-gate.mjs`
- `scripts/dossier-continuity-regression-gate.test.mjs`
- `scripts/dossier-continuity-release-integration.test.mjs`
- `.github/workflows/deploy-commercial-operator-command.yml`

### Separate canonical starter repository: create

- `src/components/Seo.astro`
- `src/layouts/BaseLayout.astro`
- `src/pages/index.astro`
- `src/pages/404.astro`
- `src/styles/global.css`
- `public/robots.txt`
- `scripts/validate-starter.mjs`
- `tests/starter-contract.test.mjs`
- `tests/starter-browser.spec.mjs`
- `astro.config.mjs`
- `package.json`
- `package-lock.json`
- `tsconfig.json`
- `.editorconfig`
- `.gitignore`
- `README.md`

## PHASE A — GitHub App provider foundation

### Task 1: Version the inert provisioning contract

**Files:**
- Modify: `supabase/functions/_shared/repository-provisioning.ts`
- Modify: `supabase/functions/_shared/repository-provisioning.test.ts`
- Test: `supabase/functions/_shared/repository-provisioning.test.ts`

**Interfaces:**
- Consumes: the existing V1 `bootstrap: "NONE"` service and fake provider/store
- Produces: `RepositoryProvisioningRequestV2`, `VerifiedRepositoryBindingV2`, V2 claim/bind/fail interfaces, deterministic `repositoryNameForContext(uuid)`

- [ ] Step 1: Add tests for the exact V2 shapes, UUID-derived repository name, starter provenance, node ID and marker commit SHA; retain V1 tests as characterization.
- [ ] Step 2: Run `deno test supabase/functions/_shared/repository-provisioning.test.ts`; expect missing V2 exports and name derivation while all eight V1 tests remain passing.
- [ ] Step 3: Add the V2 types and service path without changing V1 semantics; reject caller owner/name/template/URL/credentials and malformed or extra fields.
- [ ] Step 4: Re-run the focused Deno test and require all V1 and V2 cases to pass.
- [ ] Step 5: Run `deno test --allow-env --allow-read supabase/functions/_shared/*.test.ts`.
- [ ] Step 6: Review the diff for `bootstrap: "NONE"` preservation, no provider activation and no secret-bearing fields.
- [ ] Step 7: Commit with `git commit -m "feat(repository): version provisioning contract"`.

### Task 2: Validate deny-by-default GitHub App configuration

**Files:**
- Create: `supabase/functions/_shared/github-app-config.ts`
- Create: `supabase/functions/_shared/github-app-config.test.ts`
- Test: `supabase/functions/_shared/github-app-config.test.ts`

**Interfaces:**
- Consumes: `LWS_GITHUB_PROVIDER_ENABLED`, App ID, installation ID, organization login, template owner/name/ID, starter version/SHA and private-key secret value
- Produces: frozen `GitHubAppConfig` only when feature flag, environment allowlist and all exact values validate

- [ ] Step 1: Write tests for disabled-by-default behavior, missing values, malformed IDs/SHA/version/PEM, production/test organization separation and rejection of PAT/OAuth-like configuration.
- [ ] Step 2: Run `deno test --allow-env supabase/functions/_shared/github-app-config.test.ts`; expect missing module/config loader.
- [ ] Step 3: Implement exact environment parsing with stable `GITHUB_PROVIDER_DISABLED` and `GITHUB_CONFIGURATION_INVALID` errors; do not log values.
- [ ] Step 4: Re-run the focused test and require pass.
- [ ] Step 5: Run `deno test --allow-env supabase/functions/_shared/supabase-key-bindings.test.ts supabase/functions/_shared/security.test.ts`.
- [ ] Step 6: Inspect the diff and search changed files for PEM bodies, tokens, PAT prefixes and real organization secrets; require zero matches.
- [ ] Step 7: Commit with `git commit -m "feat(repository): validate GitHub App configuration"`.

### OWNER GATE 1: GitHub Organization confirmation/configuration

- [ ] OWNER confirms the LWS-controlled production organization, separate test organization, human team/access policy, offboarding, audit review and break-glass ownership. Record identifiers only in the approved secret/configuration system, never in this plan or source.
- [ ] STOP until written approval is recorded. This gate permits configuration preparation only, not GitHub App registration or API calls.

### Task 3: Mint narrow in-memory App and installation tokens

**Files:**
- Create: `supabase/functions/_shared/github-app-token.ts`
- Create: `supabase/functions/_shared/github-app-token.test.ts`
- Test: `supabase/functions/_shared/github-app-token.test.ts`

**Interfaces:**
- Consumes: validated `GitHubAppConfig`, clock, crypto signer and fake HTTP exchange
- Produces: App JWT and installation-token lease scoped to explicit repository IDs and operation permissions, with expiry no later than one hour

- [ ] Step 1: Add deterministic clock/signer tests for JWT claims, short expiry, explicit `repository_ids`, exact permissions and refusal of an empty repository selection.
- [ ] Step 2: Run `deno test --allow-env supabase/functions/_shared/github-app-token.test.ts`; expect missing broker.
- [ ] Step 3: Implement dependency-injected signing/exchange; expose only `{ token, expiresAt }` internally and clear references after each provider operation.
- [ ] Step 4: Re-run the focused test and require pass.
- [ ] Step 5: Add redaction assertions proving thrown exchange errors, object inspection and logs never contain JWT, token or PEM fragments; rerun the test.
- [ ] Step 6: Verify no installation-wide fallback and no token persistence API exists.
- [ ] Step 7: Commit with `git commit -m "feat(repository): add scoped GitHub App token broker"`.

### Task 4: Restrict GitHub HTTP endpoints and responses

**Files:**
- Create: `supabase/functions/_shared/github-http.ts`
- Create: `supabase/functions/_shared/github-http.test.ts`
- Test: `supabase/functions/_shared/github-http.test.ts`

**Interfaces:**
- Consumes: fixed operation descriptors and injected `fetch`
- Produces: schema-validated GitHub responses, redacted stable errors and retry metadata

- [ ] Step 1: Test the exact allowed endpoints for token exchange, template metadata/tree, repository generation, repository metadata, marker contents and marker commit; deny arbitrary URL/method/path.
- [ ] Step 2: Run `deno test supabase/functions/_shared/github-http.test.ts`; expect missing client.
- [ ] Step 3: Implement HTTPS-only `api.github.com`/`github.com` routing, restricted redirects, request IDs, response ceilings, schema validation and redaction.
- [ ] Step 4: Re-run and require pass for 2xx, 401/403, 404, 409/422, 429/rate reset, 5xx, timeout and invalid JSON cases.
- [ ] Step 5: Add contract tests proving delete, transfer, archive, visibility mutation, workflow path mutation and arbitrary content methods are unreachable.
- [ ] Step 6: Inspect all error strings for raw body, header or URL leakage.
- [ ] Step 7: Commit with `git commit -m "feat(repository): constrain GitHub HTTP operations"`.

## PHASE B — repository database lifecycle / binding

### Task 5: Add repository lifecycle schema and immutable operation authority

**Files:**
- Create: `supabase/migrations/20260914090000_add_website_repository_provisioning_v1.sql`
- Create: `supabase/tests/website_repository_provisioning_v1.sql`
- Test: `supabase/tests/website_repository_provisioning_v1.sql`

**Interfaces:**
- Consumes: `website_execution_workspaces`, `website_work_contexts`, `commercial_operators`
- Produces: repository metadata columns, `website_repository_provisioning_operations`, immutable events and explicit workspace/operation state constraints

- [ ] Step 1: Write pgTAP assertions for every column, FK, unique external ID, one active operation per workspace/context, state shape, immutability, forced RLS and revoked direct privileges.
- [ ] Step 2: Run `npx supabase test db supabase/tests/website_repository_provisioning_v1.sql`; expect missing columns/table/functions.
- [ ] Step 3: Add the forward-only migration preserving existing `PENDING_REPOSITORY`/`READY` rows and adding `REPOSITORY_PROVISIONING`, `REPOSITORY_READY`, `REPOSITORY_FAILED` plus operation states from the spec.
- [ ] Step 4: Run `npx supabase db reset` and the focused pgTAP suite; require pass.
- [ ] Step 5: Run `npx supabase test db supabase/tests/website_execution_workspace_v1.sql` and `npx supabase test db supabase/tests/website_concept_pre_project_v1.sql`.
- [ ] Step 6: Confirm there are no secret, token, source-content or independent repository-URL columns and no edit to earlier migrations.
- [ ] Step 7: Commit with `git commit -m "feat(repository): add provisioning lifecycle authority"`.

### Task 6: Implement claim, external capture, bind and failure RPCs

**Files:**
- Modify: `supabase/migrations/20260914090000_add_website_repository_provisioning_v1.sql`
- Modify: `supabase/tests/website_repository_provisioning_v1.sql`
- Test: `supabase/tests/website_repository_provisioning_v1.sql`

**Interfaces:**
- Produces: `claim_website_repository_provisioning_v1(uuid,uuid,uuid,text,text,text)`, `record_website_repository_external_identity_v1(uuid,text,text)`, `bind_website_repository_v1(uuid,jsonb)`, `fail_website_repository_provisioning_v1(uuid,text,text)`, `get_website_repository_operation_v1(uuid)`

- [ ] Step 1: Add failing role/AAL2/caller-JWT, fingerprint replay/conflict, row-lock, transition and exact-result tests for all RPCs.
- [ ] Step 2: Run the focused pgTAP suite; expect missing-function failures.
- [ ] Step 3: Implement SECURITY DEFINER functions with fixed search paths, server-derived name/provenance, immutable fingerprints and command-local write guards.
- [ ] Step 4: Re-run focused pgTAP and require exact `CLAIMED`, `REPLAY`, `IN_PROGRESS`, `BOUND`, failure and quarantine results.
- [ ] Step 5: Run `npx supabase test db supabase/tests/operator_mfa_aal2_authority_v1.sql supabase/tests/operator_workspace_authority_v1.sql`.
- [ ] Step 6: Verify external identity is durably captured before verification/binding and cross-context/external-ID substitutions fail closed.
- [ ] Step 7: Commit with `git commit -m "feat(repository): add claim and binding RPCs"`.

### Task 7: Add reconciliation, quarantine and immutable audit

**Files:**
- Modify: `supabase/migrations/20260914090000_add_website_repository_provisioning_v1.sql`
- Modify: `supabase/tests/website_repository_provisioning_v1.sql`
- Test: `supabase/tests/website_repository_provisioning_v1.sql`

**Interfaces:**
- Produces: retry scheduling, quarantine evidence hash, owner+AAL2 resolution RPC and append-only redacted repository events

- [ ] Step 1: Add failing tests for all legal/illegal operation transitions, five attempts in 24 hours, `Retry-After`, 401/403 `BLOCKED`, permanent mismatch quarantine and 24-hour alert state.
- [ ] Step 2: Run the focused pgTAP suite; expect missing transition/audit behavior.
- [ ] Step 3: Implement bounded retries, no auto-expiry/delete, immutable evidence and separate `resolve_website_repository_quarantine_v1(operation_id,idempotency_key,decision,evidence_sha256)` authority.
- [ ] Step 4: Re-run focused pgTAP and require pass.
- [ ] Step 5: Add transaction rollback and two-session concurrency cases using the repository's established pgTAP/dblink pattern; rerun.
- [ ] Step 6: Inspect audit payload assertions: IDs, states, stable codes and request ID allowed; credentials, content, PII and raw errors forbidden.
- [ ] Step 7: Commit with `git commit -m "feat(repository): add reconciliation and quarantine authority"`.

## PHASE C — repository provisioning Edge command

### Task 8: Connect the database store to the V2 orchestrator

**Files:**
- Create: `supabase/functions/_shared/repository-provisioning-store.ts`
- Create: `supabase/functions/_shared/repository-provisioning-store.test.ts`
- Modify: `supabase/functions/_shared/repository-provisioning.ts`
- Modify: `supabase/functions/_shared/repository-provisioning.test.ts`
- Test: both repository provisioning test files

**Interfaces:**
- Consumes: caller-JWT Supabase client and Task 6 RPCs
- Produces: `RepositoryProvisioningStoreV2` and orchestration state machine with early external-ID capture

- [ ] Step 1: Test exact RPC names/arguments, claim replay/in-progress, external capture before verify, bind, stable failure mapping and quarantine on ambiguous outcome.
- [ ] Step 2: Run `deno test supabase/functions/_shared/repository-provisioning*.test.ts`; expect missing store adapter/V2 state transitions.
- [ ] Step 3: Implement the caller-JWT store and minimal V2 orchestrator; never use a service-role client as an authorization substitute.
- [ ] Step 4: Re-run focused tests and require pass.
- [ ] Step 5: Run all `_shared` tests with `deno test --allow-env --allow-read supabase/functions/_shared/*.test.ts`.
- [ ] Step 6: Verify every external call occurs only after a committed `CLAIMED` result and every uncertain timeout remains reconcilable.
- [ ] Step 7: Commit with `git commit -m "feat(repository): connect durable provisioning store"`.

### Task 9: Implement the GitHub repository provider with fake HTTP

**Files:**
- Create: `supabase/functions/_shared/github-repository-provider.ts`
- Create: `supabase/functions/_shared/github-repository-provider.test.ts`
- Test: `supabase/functions/_shared/github-repository-provider.test.ts`

**Interfaces:**
- Consumes: V2 provider request, token broker and restricted GitHub HTTP client
- Produces: verified generated repository, exact source-tree comparison, serialized marker and verified binding

- [ ] Step 1: Add fake-HTTP tests for template SHA lock, `include_all_branches=false`, private repository, organization/name/main, recursively sorted exact tree and serial marker commit/readback.
- [ ] Step 2: Run the focused Deno test; expect missing provider.
- [ ] Step 3: Implement the provider sequence without any real network permission; request template-only token first and new-repository-only tokens after creation.
- [ ] Step 4: Re-run and require pass for success, malformed metadata, source race, marker mismatch, same-name foreign repository, timeout-after-create and inaccessible repository.
- [ ] Step 5: Run token, HTTP and provisioning tests together.
- [ ] Step 6: Confirm no same-name adoption, no destructive method and no path substitution across starter files.
- [ ] Step 7: Commit with `git commit -m "feat(repository): implement verified GitHub provider"`.

### Task 10: Route provision and reconcile commands through caller-JWT Edge authority

**Files:**
- Modify: `supabase/functions/commercial-operator-command/handler.ts`
- Modify: `supabase/functions/commercial-operator-command/index.ts`
- Modify: `supabase/functions/commercial-operator-command/handler.test.ts`
- Test: `supabase/functions/commercial-operator-command/handler.test.ts`

**Interfaces:**
- Adds actions: `provision_website_repository`, `reconcile_website_repository_operation`, `resolve_website_repository_quarantine`
- Consumes: exact bounded browser intent and validated runtime configuration
- Produces: redacted stable Edge responses; provider remains disabled unless flag and environment allowlist pass

- [ ] Step 1: Add exact-key tests rejecting owner/name/URL/template/branch/credentials/actor/role and route tests proving caller JWT reaches claim/bind RPCs.
- [ ] Step 2: Run `deno test --allow-env supabase/functions/commercial-operator-command/handler.test.ts`; expect unsupported actions.
- [ ] Step 3: Add validators, transports and dependency-injected provider construction; preserve CORS/no-store and map auth, conflict, blocked, unavailable, unknown and quarantined outcomes.
- [ ] Step 4: Re-run the focused Edge suite and require pass.
- [ ] Step 5: Run `deno test --allow-env supabase/functions/commercial-operator-command/caller-jwt-read-path.test.ts supabase/functions/commercial-operator-command/handler.test.ts`.
- [ ] Step 6: Prove disabled mode performs zero token, GitHub and binding calls; inspect response snapshots for secrets/raw provider bodies.
- [ ] Step 7: Commit with `git commit -m "feat(repository): route owner provisioning command"`.

### OWNER GATES 3–5A: GitHub App authority and offline credential readiness

- [ ] **OWNER GATE 3 — GitHub App registration:** register the LWS-owned App only after Tasks 1-10 pass locally; record App identity and incident owner outside source control. STOP before registration until approved.
- [ ] **OWNER GATE 4 — permissions and installation scope:** approve Metadata read, Administration write and Contents write only; explicitly reject Workflows, Actions, Pages, Deployments, Webhooks, Issues, Pull Requests, Members and Secrets. Install with **Only select repositories**, initially selecting only the canonical template. STOP on any permission drift.
- [x] **OWNER GATE 5A — Secret Placement and Offline Credential Readiness:** generate the GitHub App private key, place it only in the approved Supabase Edge Function Secrets store and delete the downloaded local PEM. Store only the exact contract names `LWS_GITHUB_APP_PRIVATE_KEY`, `LWS_GITHUB_APP_ID`, `LWS_GITHUB_APP_INSTALLATION_ID`, `LWS_GITHUB_PRODUCTION_ORGANIZATION`, `LWS_GITHUB_TEST_ORGANIZATION`, `LWS_GITHUB_TEMPLATE_OWNER`, `LWS_GITHUB_TEMPLATE_NAME` and `LWS_GITHUB_PROVIDER_ENABLED`; the App ID and installation ID must be recorded there. Keep `LWS_GITHUB_PROVIDER_ENABLED=false`; prove no secret material exists in source, database, browser, logs, local environment or evidence; require offline configuration validation and fail-closed tests to pass. No real GitHub API call is required or authorized by Gate 5A. **Status: COMPLETE by OWNER-approved evidence.**
- [ ] **OWNER GATE 5B — Live Rotation / Revocation Evidence:** complete only after OWNER Gate 6 authorizes the first real GitHub API call and the initial `GET /app` plus repository-scoped installation-token test succeeds. Generate a second App private key, replace the active Supabase secret with the new key before revoking the previous key, verify new-key authentication and narrowly scoped token issuance, revoke the previous key, prove old-key authentication is denied and prove the new key remains valid. Record no key, JWT or token material; keep the provider disabled unless separately authorized. STOP until the rotation/revocation evidence is approved.

### OWNER-approved credential gate sequence

The legal sequence after completed Task 11 is:

1. Complete OWNER Gate 5A.
2. Complete Task 12.
3. Complete Task 13 Steps 1–5 without network access.
4. Obtain OWNER Gate 8A approval.
5. Deploy only the minimal server-side test harness required to use the existing Supabase-managed secrets.
6. Obtain OWNER Gate 6 approval.
7. Perform only the approved first real `GET /app` authentication and narrowly repository-scoped installation-token test.
8. Complete OWNER Gate 5B rotation/revocation rehearsal.
9. Complete the remaining Task 13 steps and commit its harness/tests/evidence schema.
10. Complete Tasks 14–21.
11. Obtain OWNER Gate 7 approval.
12. Obtain OWNER Gate 8B production activation approval.

Gate 5A, not Gate 5B, is the prerequisite for Task 12 and Task 13 Steps 1–5. Gate 8A is the narrow deployment authority required to make Gate 6 technically reachable without exporting Supabase secrets. Gate 6 remains the hard stop before the first real GitHub API call. Gate 5B remains mandatory before Task 13 may perform its approved external template-generation execution. Gate 8B remains the separate final authority for production migration execution, production Edge activation and feature-flag enablement.

The reconciliation changes no security boundary: `LWS_GITHUB_PROVIDER_ENABLED=false` remains mandatory; secrets remain server-side in Supabase Edge Function Secrets and may not be exported; browser DTOs contain no credentials; installation tokens must name exactly the approved repository and may never fall back to installation-wide scope; no customer repository or production provisioning is authorized; every dossier retains its own `website_work_context_id` repository island; and TEST remains fail-closed and separate from PRODUCTION.

## PHASE D — canonical starter repository contract

### OWNER GATE 2: Canonical starter repository creation

- [ ] OWNER approves creation of one separate private LWS-controlled GitHub Template Repository with protected `main`, immutable semantic tags, no customer source and no deployment credential. This gate can be prepared earlier but must complete before Task 11 external repository work.
- [ ] STOP until the repository owner/name, branch rules, release lock and reviewer policy are recorded.

### Task 11: Build the minimal Astro static starter in its separate repository

**Files:**
- Create: all files listed under “Separate canonical starter repository: create”
- Modify: none in the LWS core repository
- Test: `tests/starter-contract.test.mjs`, `tests/starter-browser.spec.mjs`

**Interfaces:**
- Produces: locked Astro static output, semantic layout/page/style conventions, SEO/sitemap/robots/404 and deterministic `dist/`
- Excludes: `.lws/project.json`, customer data, analytics secrets, production domains and deployment credentials

- [ ] Step 1: In the separate repository, write contract tests first for required paths, pinned engines, committed lockfile, static output, no secret/customer/deployment material and absence of `.lws/project.json`.
- [ ] Step 2: Run `node --test tests/starter-contract.test.mjs`; expect missing starter files/scripts.
- [ ] Step 3: Create the minimal Astro project and scripts `lint`, `typecheck`, `test`, `build`; use semantic accessible markup and opt-in client JavaScript only.
- [ ] Step 4: Run `npm ci`, `npm run lint`, `npm run typecheck`, `npm test`, and `npm run build`; require clean install and deterministic static output.
- [ ] Step 5: Run `npx playwright test tests/starter-browser.spec.mjs` for desktop/mobile, reduced motion, metadata, sitemap, robots, 404 and asset paths.
- [ ] Step 6: Review the entire separate-repository tree for customer/core source, active workflow/deploy configuration and secret-like values; require none.
- [ ] Step 7: Commit in the separate repository with `git commit -m "feat(starter): add canonical Astro static baseline"`.

### Task 12: Publish and lock an immutable starter release

**Files:**
- Modify: `README.md` in the separate canonical starter repository
- Test: `scripts/validate-starter.mjs` in the separate canonical starter repository

**Interfaces:**
- Produces: semantic version, exact `main` commit SHA, repository external ID and recursively hashed tree manifest for provider configuration

- [ ] Step 1: Add failing validation for unclean tree, unlocked dependencies, mismatched tag/SHA, branch-rule gaps and changed tree manifest.
- [ ] Step 2: Run `node scripts/validate-starter.mjs`; expect release metadata/ruleset evidence missing.
- [ ] Step 3: Document and implement the release lock procedure; protect `main` and semantic tags against force-push/deletion with audited break-glass only.
- [ ] Step 4: Re-run starter validation and all Task 11 checks; require pass.
- [ ] Step 5: Record the approved semantic version, commit SHA, external repository ID and tree digest in the approved deployment configuration, not customer source.
- [ ] Step 6: Verify generation is serialized while the release lock is held and existing customer repositories receive no automatic update.
- [ ] Step 7: Commit in the starter repository with `git commit -m "docs(starter): define immutable release procedure"`; creation of the release tag requires separate OWNER confirmation.

## PHASE E — starter bootstrap / provenance

### Task 13: Prove template bootstrap in the isolated test organization

**Files:**
- Create: `scripts/github-repository-provider-test-island.mjs`
- Create: `scripts/github-repository-provider-test-island.test.mjs`
- Test: both files plus provider unit tests

**Interfaces:**
- Consumes: dedicated test App, test organization, approved starter release and one synthetic test context
- Produces: redacted evidence for scoped template generation, tree equality, marker commit/readback and captured external identity

- [ ] Step 1: Unit-test the harness with fake API responses, explicit `--execute` opt-in, test-organization allowlist and refusal when production-like credentials/resources are supplied.
- [ ] Step 2: Run `node --test scripts/github-repository-provider-test-island.test.mjs`; expect missing harness.
- [ ] Step 3: Implement dry-run by default and exact redacted evidence output; cleanup remains disabled unless a separately approved marker+context+external-ID test cleanup path exists.
- [ ] Step 4: Re-run the unit harness test and provider Deno tests without network access; require pass.
- [ ] Step 5: Stop before any `--execute` invocation and request OWNER Gate 8A. Gate 6 is unreachable until the minimal secret-resident server-side harness is deployed under Gate 8A.

### OWNER GATE 8A: Test-harness Edge deployment

- [ ] OWNER authorizes deployment of only the minimal server-side GitHub App authentication/test harness required for Gate 6. It may read the existing Supabase-managed GitHub App secrets server-side, create a short-lived in-memory App JWT, call only `GET /app`, request one installation token restricted to the canonical starter repository and approved Metadata read, Administration read/write and Contents read/write permissions, emit redacted evidence and fail closed.
- [ ] The Gate 8A route must expose no private key, JWT, installation token or Authorization header to browser DTOs, logs, files, environment exports or evidence. Credentials exist only in server memory and are discarded immediately after use. Installation-wide token fallback is forbidden.
- [ ] Gate 8A does not authorize provider enablement, repository generation, customer repository creation, customer or production mutation, starter changes, App permission changes, installation-scope expansion, migration execution or general production Edge activation. Keep `LWS_GITHUB_PROVIDER_ENABLED=false`.
- [ ] STOP after the minimal deployment is verified fail-closed. No GitHub API call is authorized until OWNER Gate 6.

### OWNER GATE 6: Test installation and external side effect

- [ ] OWNER approves use of the Gate 8A harness for the first real GitHub authentication and token-scope test against the dedicated test App installation and exact selected canonical template repository. This gate does not authorize repository creation or mutation.
- [ ] STOP before the first real GitHub API call. A failed repository-scoped template-generation contract blocks activation; installation-wide token scope is forbidden as a workaround.
- [ ] After approval, perform the first authentication test with a short-lived in-memory App JWT using `GET /app`, then request one installation token restricted to the canonical template repository and the approved Metadata read, Administration write and Contents write permissions. Discard both credentials immediately, record only redacted status/request/scope/expiry evidence and perform no repository mutation. STOP for OWNER review and Gate 5B continuation.

### OWNER GATE 5B: Live rotation / revocation evidence

- [ ] Generate a second GitHub App private key and store it as the active Supabase Edge secret before revoking the previous key.
- [ ] Verify new-key App authentication and narrowly repository-scoped installation-token issuance, revoke the previous key, prove old-key authentication is denied and prove the new key remains valid.
- [ ] Record only redacted key identifiers, timestamps, HTTP status, GitHub request IDs, repository/permission scope and expiry; never record PEM, JWT or installation-token material. Keep `LWS_GITHUB_PROVIDER_ENABLED=false`.
- [ ] STOP until OWNER approves Gate 5B evidence. This approval does not authorize provider enablement, Edge deployment, installation-scope expansion, customer repository creation or production mutation.

### Task 13 continuation after OWNER Gate 5B

- [ ] Step 6: After Gate 5B approval, run the documented test-island command once, capture request IDs/external IDs/hashes, and verify no non-test repository is listed, read, changed or deleted.
- [ ] Step 7: Commit only harness/tests/evidence schema with `git commit -m "test(repository): add GitHub test-island contract"`; do not commit credentials or raw tokens.

### Task 14: Complete bootstrap provenance and recovery cases

**Files:**
- Modify: `supabase/functions/_shared/github-repository-provider.ts`
- Modify: `supabase/functions/_shared/github-repository-provider.test.ts`
- Modify: `supabase/functions/_shared/repository-provisioning.ts`
- Modify: `supabase/functions/_shared/repository-provisioning.test.ts`
- Test: provider and provisioning Deno tests

**Interfaces:**
- Produces: verified initial-tree provenance plus distinct marker commit SHA and reconciliation evidence

- [ ] Step 1: Add failing tests from Gate 6 evidence for exact repository-scoped behavior, external-ID capture, generated-tree comparison and marker serialization byte shape.
- [ ] Step 2: Run focused tests; expect failures at each unimplemented evidence/recovery check.
- [ ] Step 3: Add only the required provider normalization/recovery logic; preserve test/production configuration separation.
- [ ] Step 4: Re-run focused tests and require pass for happy path, source race, timeout after create, missing marker and conflicting marker.
- [ ] Step 5: Run the complete `_shared` Deno suite.
- [ ] Step 6: Confirm a foreign or ambiguous repository always ends `QUARANTINED` and is never overwritten/deleted.
- [ ] Step 7: Commit with `git commit -m "fix(repository): harden starter provenance recovery"`.

## PHASE F — development workspace integration

### Task 15: Expose repository lifecycle in the existing Website managed child

**Files:**
- Modify: `assets/js/operator-website-execution.mjs`
- Modify: `assets/js/operator-website-execution-child.mjs`
- Modify: `assets/js/operator-module-registry.mjs`
- Modify: `scripts/operator-website-execution.test.mjs`
- Modify: `scripts/operator-project-requirements.test.mjs`
- Test: both Operator test files

**Interfaces:**
- Consumes: exact workspace projection and server `permitted_actions`
- Produces: pending/provisioning/ready/failed/blocked/quarantined states, provision intent and launcher/file actions in the existing `website-{quote_request_id}` child

- [ ] Step 1: Add tests for exact new workspace keys/states, action visibility, owner+AAL2 command, in-flight retention and fail-closed malformed/cross-context response handling.
- [ ] Step 2: Run `node --test scripts/operator-website-execution.test.mjs scripts/operator-project-requirements.test.mjs`; expect missing states/actions.
- [ ] Step 3: Extend validators/view/rendering minimally; never infer authority from role alone and never expose credentials or arbitrary repository URLs.
- [ ] Step 4: Re-run focused tests and require pass.
- [ ] Step 5: Run `node --test scripts/operator-workspace.test.mjs scripts/website-execution-requirements-live-preview.test.mjs`.
- [ ] Step 6: Confirm Requirements remains the adjacent authority, no GitHub Issues duplication exists and no new module/slot was added.
- [ ] Step 7: Commit with `git commit -m "feat(operator): show repository lifecycle in website workspace"`.

### Task 16: Add the context-bound local VS Code launcher

**Files:**
- Create: `scripts/website-workspace-launcher.mjs`
- Create: `scripts/website-workspace-launcher.test.mjs`
- Modify: `assets/js/operator-website-execution-child.mjs`
- Modify: `scripts/operator-website-execution.test.mjs`
- Test: launcher and Website Execution tests

**Interfaces:**
- Consumes: short-lived server launcher manifest containing authorized context, external repository ID, marker identity and canonical clone root token
- Produces: dedicated clone/open operation rooted by context UUID; human Git auth remains outside the App

- [ ] Step 1: Add fake filesystem/process tests for canonical root derivation, existing marker/remote/external-ID checks, traversal, junction/symlink escape, context A/B substitution and command argument safety.
- [ ] Step 2: Run `node --test scripts/website-workspace-launcher.test.mjs`; expect missing launcher.
- [ ] Step 3: Implement dry-run/testable clone/open orchestration with context-scoped temp/env/log/watch roots; do not embed App tokens or authenticated remotes.
- [ ] Step 4: Re-run focused launcher tests and require pass.
- [ ] Step 5: Add Operator tests proving the launcher action appears only for verified `REPOSITORY_READY`, then run both focused suites.
- [ ] Step 6: Document in CLI help that this is application-mediated isolation; shared hostile hosts require separate OS identity/ACL or VM/container.
- [ ] Step 7: Commit with `git commit -m "feat(workspace): add context-bound VS Code launcher"`.

## PHASE G — project files read boundary

### Task 17: Implement the server-only project-file read policy

**Files:**
- Create: `supabase/functions/_shared/website-project-files.ts`
- Create: `supabase/functions/_shared/website-project-files.test.ts`
- Modify: `supabase/functions/commercial-operator-command/handler.ts`
- Modify: `supabase/functions/commercial-operator-command/index.ts`
- Modify: `supabase/functions/commercial-operator-command/handler.test.ts`
- Modify: `supabase/functions/commercial-operator-command/caller-jwt-read-path.test.ts`
- Test: all listed Deno tests

**Interfaces:**
- Adds action: `read_website_project_file`
- Produces: escaped text metadata/content or inert symlink/submodule/binary metadata; no GitHub URL/token

- [ ] Step 1: Add exact-key, owner+AAL2, context binding, allowed ref, normalized path, traversal/NUL/backslash/encoding, 1 MiB ceiling, count, MIME and extension tests.
- [ ] Step 2: Run focused Deno tests; expect missing action/policy.
- [ ] Step 3: Implement server resolution by bound external repository ID and restricted provider read; treat HTML/SVG/Markdown as untrusted text and set `nosniff` response metadata.
- [ ] Step 4: Re-run focused tests and require pass.
- [ ] Step 5: Add context A/B substitution, XSS filenames/content, symlink/submodule and temporary-download-URL leakage tests; rerun.
- [ ] Step 6: Verify no browser write route and no `.github/workflows`/`.lws/project.json` mutation method exists.
- [ ] Step 7: Commit with `git commit -m "feat(repository): add bounded project-file reads"`.

### Task 18: Add the Project Files view to the existing managed child

**Files:**
- Create: `assets/js/operator-project-files.mjs`
- Create: `operator/test/project-files.html`
- Create: `scripts/operator-project-files.test.mjs`
- Modify: `assets/js/operator-website-execution-child.mjs`
- Modify: `assets/js/operator-module-registry.mjs`
- Modify: `scripts/operator-website-execution.test.mjs`
- Test: Project Files, Website Execution and workspace tests

**Interfaces:**
- Consumes: bounded file DTO and existing Website child context
- Produces: read-only tree/file presentation inside the same managed child; content rendered as text, never trusted markup

- [ ] Step 1: Add tests for lazy bounded listing, escaped metadata/content, binary/symlink/submodule state, size rejection, refresh retention and authorization clear.
- [ ] Step 2: Run `node --test scripts/operator-project-files.test.mjs scripts/operator-website-execution.test.mjs`; expect missing module/view behavior.
- [ ] Step 3: Implement the read-only view and wire the existing `Projectbestanden` action without creating another slot or repository authority.
- [ ] Step 4: Re-run focused tests and require pass.
- [ ] Step 5: Run `node --test scripts/operator-workspace.test.mjs scripts/website-execution-requirements-live-preview.test.mjs`.
- [ ] Step 6: Inspect DOM tests for no `innerHTML` use with provider values, no download URL forwarding and no write controls.
- [ ] Step 7: Commit with `git commit -m "feat(operator): add read-only project files"`.

## PHASE H — isolation/security regression gates

### Task 19: Enforce the complete negative island contract

**Files:**
- Create: `scripts/website-repository-isolation.test.mjs`
- Modify: `supabase/tests/website_repository_provisioning_v1.sql`
- Modify: `scripts/operator-workspace.test.mjs`
- Modify: `scripts/dossier-continuity-regression-gate.mjs`
- Modify: `scripts/dossier-continuity-regression-gate.test.mjs`
- Test: all listed isolation suites

**Interfaces:**
- Consumes: two real-shaped contexts, same-customer/different-context pair, synthetic test context, Website/SDF identities and substituted resource IDs
- Produces: every exact `PASS`/`NEE`/zero outcome from design section 20.12

- [ ] Step 1: Add failing database/provider/Edge/launcher/files tests for cross-context read/write/open/bind and test-to-real mutation.
- [ ] Step 2: Run focused pgTAP and Node isolation suites; expect missing negative-contract outputs.
- [ ] Step 3: Add only local authority fixes needed to make every substituted identifier fail closed; do not weaken service-role or App-side context checks.
- [ ] Step 4: Re-run focused suites and require all 15 exact section 20.12 outputs.
- [ ] Step 5: Run Website/SDF, Multi-Screen and continuity regressions: `node --test scripts/operator-workspace.test.mjs scripts/dossier-continuity-regression-gate.test.mjs scripts/dossier-continuity-release-integration.test.mjs`.
- [ ] Step 6: Scan repository changes and generated fixtures to prove customer source entered neither core nor SDF paths and no shared repository/worktree was introduced.
- [ ] Step 7: Commit with `git commit -m "test(isolation): enforce customer repository islands"`.

### Task 20: Add provider security and release gating

**Files:**
- Create: `scripts/website-repository-release-gate.mjs`
- Create: `scripts/website-repository-release-gate.test.mjs`
- Modify: `.github/workflows/deploy-commercial-operator-command.yml`
- Modify: `scripts/dossier-continuity-release-integration.test.mjs`
- Test: release-gate and workflow contract tests

**Interfaces:**
- Consumes: local test evidence, App permission inventory, key-rotation rehearsal, test-island evidence, quarantine report and exact isolation outputs
- Produces: `WEBSITE_REPOSITORY_RELEASE_ALLOWED=JA|NEE`; deployment remains impossible on missing/stale evidence

- [ ] Step 1: Add tests for absent/expired evidence, permission drift, broad installation scope, unresolved quarantine, secret scan failure, failed negative contract and non-main release authority.
- [ ] Step 2: Run `node --test scripts/website-repository-release-gate.test.mjs scripts/dossier-continuity-release-integration.test.mjs`; expect missing gate/workflow step.
- [ ] Step 3: Implement a read-only evidence gate and insert it before Edge deployment; keep the provider feature flag disabled by default.
- [ ] Step 4: Re-run focused tests and require pass for deny and allow fixtures.
- [ ] Step 5: Run `./scripts/invoke-dossier-continuity-release-gate.ps1 -Phase Local` only with the repository's required local environment; if unavailable, record the unmet prerequisite and do not claim release readiness.
- [ ] Step 6: Review workflow permissions (`contents: read`), secret exposure, environment protection and the absence of GitHub repository deletion/cleanup automation.
- [ ] Step 7: Commit with `git commit -m "ci(repository): gate provider release evidence"`.

## PHASE I — preview/build integration readiness

### Task 21: Define and prove the isolated preview/build boundary without activation

**Files:**
- Create: `supabase/functions/_shared/website-preview-build-contract.ts`
- Create: `supabase/functions/_shared/website-preview-build-contract.test.ts`
- Create: `scripts/website-preview-isolation.test.mjs`
- Modify: `scripts/dossier-continuity-regression-gate.mjs`
- Modify: `scripts/dossier-continuity-regression-gate.test.mjs`
- Test: preview contract and isolation tests

**Interfaces:**
- Consumes: context ID, external repository ID, exact commit SHA, lockfile/toolchain/config hashes and broker-issued one-context capabilities
- Produces: immutable build ID plus context-scoped source/output/cache/artifact/preview descriptors; no worker or deployment activation

- [ ] Step 1: Add failing tests for context-prefixed mutable cache, context/build artifact path, exact commit binding, audience-bound preview token and PRE_PROJECT production denial.
- [ ] Step 2: Run `deno test supabase/functions/_shared/website-preview-build-contract.test.ts` and `node --test scripts/website-preview-isolation.test.mjs`; expect missing contracts.
- [ ] Step 3: Implement pure validators/build descriptors only: disposable non-privileged sandbox requirements, immutable install, limits, no host socket/sibling mount/provider credential/ambient identity and allowlisted registry egress.
- [ ] Step 4: Re-run focused tests and require pass.
- [ ] Step 5: Add malicious lifecycle-script fixtures for sibling read, secret read, network escape, resource exhaustion and cross-context output; the readiness harness must reject any runner lacking enforceable controls.
- [ ] Step 6: Confirm this task creates no preview, bucket, CDN route, deployment credential, worker or production target; actual infrastructure requires a separate approved design and OWNER gate.
- [ ] Step 7: Commit with `git commit -m "test(preview): define isolated build readiness"`.

### OWNER GATE 7: First real test repository provisioning

- [ ] After Tasks 1-21 pass and Gate 6 evidence is accepted, OWNER approves one end-to-end synthetic test-dossier provisioning operation. Verify database claim, scoped tokens, private repository, tree, marker, binding, launcher/files denial for another context and non-production preview denial.
- [ ] STOP on any ambiguous external outcome, permission drift, leaked value, mismatched marker/tree, cross-context access or unresolved quarantine. Do not delete or repair automatically.

### OWNER GATE 8B: Production activation

- [ ] OWNER reviews all local/test-island evidence, exact App permissions, Only-select-repositories scope, key rotation, timeout/orphan recovery, quarantine queue, 14 negative isolation outcomes, starter release and continuity gate.
- [ ] OWNER separately authorizes migration execution, Edge deployment and feature-flag enablement. These are distinct controlled operations with rollback/pause instructions; no approval is inferred from implementation completion.
- [ ] STOP until explicit `OWNER PRODUCTION ACTIVATION: JA` is recorded. Push and production/customer mutation remain separately authorized.

## Test Matrix

| Layer | Command/evidence | Required result |
| --- | --- | --- |
| UNIT | `deno test --allow-env --allow-read supabase/functions/_shared/*.test.ts` | Provider contracts, token scope, redaction, paths, provenance and preview descriptors pass |
| EDGE | `deno test --allow-env supabase/functions/commercial-operator-command/handler.test.ts supabase/functions/commercial-operator-command/caller-jwt-read-path.test.ts` | Exact DTOs, caller JWT, AAL2, disabled flag and stable errors pass |
| PGTAP | `npx supabase test db supabase/tests/website_repository_provisioning_v1.sql` | Lifecycle, claims, replay, locks, binding, quarantine and audit pass |
| OPERATOR | `node --test scripts/operator-website-execution.test.mjs scripts/operator-project-requirements.test.mjs scripts/operator-project-files.test.mjs` | Existing managed child and read-only views pass |
| MULTISCREEN | `node --test scripts/operator-workspace.test.mjs` | One `website-*` module-slot, re-resolution, revoke and focus behavior pass |
| PRE_PROJECT | `npx supabase test db supabase/tests/website_concept_pre_project_v1.sql supabase/tests/website_execution_workspace_v1.sql` | Existing concept/workspace authority and production denial pass |
| REPOSITORY PROVIDER | Deno fake-HTTP suites plus OWNER-approved `scripts/github-repository-provider-test-island.mjs --execute` | Scoped generation/tree/marker/recovery evidence passes |
| ISOLATION | pgTAP plus `node --test scripts/website-repository-isolation.test.mjs scripts/website-workspace-launcher.test.mjs scripts/website-preview-isolation.test.mjs` | All 15 negative island outcomes pass |
| SECURITY | token/redaction/SSRF/XSS/traversal/symlink/replay tests and secret scan | No credential leak, host escape, trusted markup or cross-context authority |
| CONTINUITY | `node --test scripts/dossier-continuity-regression-gate.test.mjs scripts/dossier-continuity-release-integration.test.mjs` | Existing dossier, Website/SDF and release behavior preserved |
| BROWSER | `node --test scripts/website-execution-requirements-live-preview.test.mjs` plus starter `npx playwright test tests/starter-browser.spec.mjs` | Desktop/mobile, Requirements adjacency, accessibility and reduced motion pass |
| RELEASE | `node --test scripts/website-repository-release-gate.test.mjs` then approved local continuity gate | Deny by default; `JA` only with current complete evidence |

## Design Traceability

| Spec sections | Implemented or proven by |
| --- | --- |
| 1-4 summary, current state, decisions, rejected alternatives | Execution Rules, Fixed Contracts, Tasks 1, 11, 19 |
| 5 GitHub App architecture | Tasks 2-4, OWNER Gates 3-6, Task 20 |
| 6-11 provider, ownership, naming, secrets, concurrency, recovery | Tasks 1-10, 13-14, OWNER Gates 1, 3-7 |
| 12-14 starter technology, design and versioning | Tasks 11-14, OWNER Gate 2 |
| 15-17 workspace, Requirements and project files | Tasks 15-18 |
| 18 preview architecture | Task 21 and OWNER Gate 8B; activation excluded |
| 19 promotion | Tasks 5-7, 19 and 21 regression assertions |
| 20.1-20.12 island isolation | Tasks 16-21 and exact negative contract in Task 19 |
| 21 threat model | Tasks 2-4, 7, 9, 14, 17, 19-21 |
| 22 audit | Tasks 4, 7, 10, 13, 20 |
| 23 data model | Tasks 5-7 |
| 24 Edge contracts | Tasks 8-10 and 17 |
| 25 testing | Every task plus Test Matrix |
| 26 implementation phases | Phases A-I and OWNER Gates 1-8, with Gate 8 split into 8A and 8B |
| 27 release boundaries | Execution Rules, Tasks 20-21 and OWNER Gates 8A-8B |

## Final Self-Review and Plan Commit

- [ ] Verify every task has concrete Create/Modify/Test paths, consumed/produced interfaces, an observed failing test, expected failure, minimal implementation, passing rerun, adjacent regression, scope review and commit boundary.
- [ ] Verify every design section maps to at least one task or OWNER gate and every external side effect is preceded by an explicit STOP.
- [ ] Verify the inert V1 provider contract is not reinterpreted, customer source never enters core, one repository/workspace/files/preview/cache/build/artifact namespace exists per context, and promotion preserves that island.
- [ ] Verify the eight numbered OWNER gates are present, with Gate 5 split into Gate 5A and Gate 5B and Gate 8 split into Gate 8A and Gate 8B. Verify Gate 8A authorizes only the minimal secret-resident test harness deployment, Gate 8B retains final production activation authority, and no GitHub App, secret, repository, API call, migration, deploy, push or production mutation was performed while writing this plan.
- [ ] Search this plan case-insensitively for unfinished markers and require none; examples in the fixed contracts are intentional executable shapes, not deferred decisions.
- [ ] Validate exact status outputs:

  ```text
  SPEC_REQUIREMENTS_COVERED=JA
  PLACEHOLDERS=0
  TYPE_CONSISTENCY=PASS
  ISLAND_REQUIREMENTS_COVERED=JA
  EXTERNAL_SIDE_EFFECTS_GATED=JA
  PLAN_SCOPE_CLEAN=JA
  ```

- [ ] Run `git diff --check -- docs/superpowers/plans/2026-09-13-github-repository-provider-and-website-starter-implementation-plan.md` and a direct trailing-whitespace scan because the file is initially untracked.
- [ ] Run `git status --short`; require exactly the three preserved pre-existing untracked V2 files plus this plan, with no staged or tracked modifications.
- [ ] Stage only this file:

  ```powershell
  git add -- docs/superpowers/plans/2026-09-13-github-repository-provider-and-website-starter-implementation-plan.md
  git diff --cached --name-only
  ```

  Expected: exactly `docs/superpowers/plans/2026-09-13-github-repository-provider-and-website-starter-implementation-plan.md`.

- [ ] Commit locally without push:

  ```powershell
  git commit -m "docs: plan GitHub repository provider and website starter"
  ```

- [ ] Verify the commit contains exactly one file, staging is empty, tracked worktree changes are zero and the three V2 files remain untracked and preserved.
- [ ] STOP. Do not begin implementation. Present the local commit SHA and wait for explicit OWNER approval of the execution method.