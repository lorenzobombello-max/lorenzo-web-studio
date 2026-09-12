# Website Concept / PRE_PROJECT V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Track every checkbox and stop at each commit boundary.

**Goal:** Let an AAL2 owner start one durable, explicitly non-commercial Website concept from an active production Website dossier and open it in the existing Website Execution Workspace before quotation, acceptance, payment, or commercial release exists.

**Architecture:** Add a separate `website_concepts` authority and one stable `website_work_contexts` identity. Keep `commercial_projects` and Project Requirements unchanged. Re-anchor only Website Execution metadata to the work-context, expose one server-authoritative `website_work` projection, and preserve the existing `website-{quote_request_id}` Multi-Screen slot.

**Tech Stack:** PostgreSQL/Supabase migrations, forced RLS, pgTAP, Deno Edge Functions, static JavaScript ES modules, Node test runner, Playwright.

**Spec:** `docs/superpowers/specs/2026-09-12-website-concept-pre-project-design.md` at approved commit `72d1ac3eb5694345ffa528ec6e9bbbb9bc61ff73`.

## Global Constraints

- Implement the vertical slice in Tasks 1-8 before broader hardening.
- Do not create a fake or nullable-lineage `commercial_projects` row for a concept.
- Do not weaken quotation, acceptance, payment, Finance, milestone, commercial release, `PROJECT_WORK_STARTED`, preview-access, publication, or live-site authorities.
- Do not make `project_requirements_boards` or `project_requirements` polymorphic in V1. PRE_PROJECT returns the exact empty state `Requirements volgen na intake-sync.`
- Do not implement intake-to-requirements synchronization.
- Do not implement concept-to-project promotion. `PROMOTED` is only a schema-valid future lifecycle shape; V1 exposes no promotion command or action.
- Use one `website_work_context_id` and one existing `website-{quote_request_id}` slot. Do not create concept-specific Website modules, slots, builders, repositories, or task boards.
- The browser sends only bounded intent. It never sends actor identity, role, mode, briefing status, release state, classification, or `created_by`.
- Every mutation uses caller JWT, active owner resolution, AAL2, exact input keys, expected revision, idempotency fingerprinting, locking, and immutable audit.
- Tables force RLS and grant no direct table access to `public`, `anon`, `authenticated`, or `service_role`.
- Concept start creates no external repository, provider request, email, Finance state, payment state, publication right, or customer access.
- Preserve complete same-record snapshots during refresh and command flight. Clear immediately on cross-dossier switch. Authorization failure and revocation override retention.
- All migrations are forward-only. Never edit an already committed migration.
- This plan authorizes implementation work only after owner approval. Migration execution against production, push, deploy, and production mutation require separate authorization.

## Contract Summary

The browser-visible dossier projection is exact and closed:

```text
website_work = {
  state: NONE | PRE_PROJECT | OFFICIAL_PROJECT,
  quote_request_id: uuid,
  concept_id: uuid | null,
  project_id: uuid | null,
  website_work_context_id: uuid | null,
  mode: PRE_PROJECT | OFFICIAL_PROJECT | null,
  briefing_status: LIMITED | COMPLETE | null,
  commercially_released: boolean,
  revision: positive integer,
  permitted_actions: (CAN_START_WEBSITE_CONCEPT | OPEN_WEBSITE)[]
}
```

The start request is exact:

```json
{
  "action": "start_website_concept",
  "quote_request_id": "uuid",
  "expected_website_work_revision": 1,
  "idempotency_key": "uuid"
}
```

The Website Execution read request becomes exact:

```json
{
  "action": "get_website_execution_workspace",
  "quote_request_id": "uuid"
}
```

## Planned Files

### Create

- `supabase/migrations/20260912130000_add_website_concept_work_context_foundation_v1.sql`
- `supabase/migrations/20260912131000_add_website_concept_authority_v1.sql`
- `supabase/migrations/20260912132000_reanchor_website_execution_workspace_v1.sql`
- `supabase/tests/website_concept_pre_project_v1.sql`
- `scripts/operator-dossiers-website-concept.test.mjs`
- `scripts/operator-website-concept-stability.test.mjs`
- `scripts/website-concept-pre-project-live-preview.test.mjs`
- `docs/superpowers/checkpoints/2026-09-12-website-concept-pre-project-v1-verification.md`

### Modify

- `supabase/functions/commercial-operator-command/handler.ts`
- `supabase/functions/commercial-operator-command/index.ts`
- `supabase/functions/commercial-operator-command/handler.test.ts`
- `supabase/tests/operator_application_handoff.sql`
- `supabase/tests/project_requirements_board_v1.sql`
- `assets/js/operator-dossiers.mjs`
- `assets/js/operator-website-execution.mjs`
- `assets/js/operator-website-execution-child.mjs`
- `assets/js/operator-module-registry.mjs`
- `scripts/operator-dossiers.test.mjs`
- `scripts/operator-website-execution.test.mjs`
- `scripts/operator-workspace.test.mjs`
- `scripts/dossier-continuity-release-integration.test.mjs`

### Explicitly Untouched

- Existing committed migrations, especially `20260817004131_add_phase5or3_commercial_authority.sql` and `20260910010000_add_operator_project_start_gate_v1.sql` through `20260910061000_project_requirement_permitted_actions_v1.sql`
- `public.commercial_projects`, commercial start/release commands, Finance/payment/milestone authorities
- `public.project_requirements_boards`, `public.project_requirements`, their accepted-quotation source validator, and their lifecycle commands
- quotation, acceptance, email, customer preview-access, publication, DNS, and hosting authorities
- `dist-open-application/**` and `dist-release/**` until a separately authorized release build

## Vertical Slice

### Task 1: Lock the pre-project acceptance test and preservation baseline

**Files:**
- Create: `supabase/tests/website_concept_pre_project_v1.sql`
- Modify: none
- Test: `supabase/tests/website_concept_pre_project_v1.sql`, `supabase/tests/operator_application_handoff.sql`, `supabase/tests/project_requirements_board_v1.sql`

**Interfaces:**
- Characterizes: `public.get_operator_application_v1(uuid,text)`, `public.commercial_projects`, Website Execution and Requirements authorities
- Produces: one executable end-to-end database specification before implementation

- [ ] Create the pgTAP file with `begin`, pgTAP extension, `search_path = public, lws_internal, extensions`, `no_plan()`, `finish()`, and `rollback`.
- [ ] Add fixtures for an ACTIVE production Website dossier with submitted intake, an ACTIVE production Website dossier without submitted intake, a non-Website dossier, a trashed Website dossier, active owner/admin/operations-manager/operator identities, and owner JWTs at AAL1/AAL2.
- [ ] Add the first vertical-slice assertions: eligible AAL2 owner projection contains `CAN_START_WEBSITE_CONCEPT`; start returns PRE_PROJECT; exactly one concept and context exist; detail then contains `OPEN_WEBSITE`; Website workspace read succeeds with `project_id = null` and `workspace = null`.
- [ ] Snapshot counts for quotation approvals/issuances/acceptances, commercial customers/projects, obligations, payment expectations/evidence/reconciliations, email jobs, preview access, and project/site publication state before start; assert every count remains unchanged afterward.
- [ ] Assert the existing official project fixture still returns `OFFICIAL_PROJECT`, still reads its Website workspace, and existing Requirements projection remains project-bound.
- [ ] Run FAIL:

  ```powershell
  npx supabase test db supabase/tests/website_concept_pre_project_v1.sql
  ```

  Expected: missing `website_concepts`, `website_work_contexts`, `get_operator_website_work_v1`, and `start_website_concept_v1` contracts. Existing preservation tests must still PASS:

  ```powershell
  npx supabase test db supabase/tests/operator_application_handoff.sql
  npx supabase test db supabase/tests/project_requirements_board_v1.sql
  ```

- [ ] Commit only the characterization test:

  ```powershell
  git add supabase/tests/website_concept_pre_project_v1.sql
  git commit -m "test(concept): define pre-project vertical slice"
  ```

### Task 2: Add concept, work-context, event, and idempotency roots

**Files:**
- Create: `supabase/migrations/20260912130000_add_website_concept_work_context_foundation_v1.sql`
- Modify: `supabase/tests/website_concept_pre_project_v1.sql`

**Interfaces:**
- Consumes: `quote_requests(id)`, `commercial_projects(project_id)`, `commercial_operators(operator_id)`
- Produces: `website_concepts`, `website_work_contexts`, `website_concept_events`, `website_concept_idempotency_ledger`

- [ ] First add failing schema tests for every column, FK, unique binding, status/phase shape, positive revisions, timestamps, forced RLS, revoked table privileges, and immutable event/idempotency guards.
- [ ] Run FAIL and require missing-relation/constraint failures:

  ```powershell
  npx supabase test db supabase/tests/website_concept_pre_project_v1.sql
  ```

- [ ] Add `website_concepts` exactly as the spec contracts: one row per `quote_request_id`; mode fixed to `PRE_PROJECT`; briefing `LIMITED|COMPLETE`; `commercially_released` fixed false; `ACTIVE|PROMOTED` shape; optional future `promoted_project_id`; positive revision; server-owned creator/timestamps.
- [ ] Add `website_work_contexts` with unique dossier, concept, and project bindings; `PRE_PROJECT|OFFICIAL_PROJECT` shape; stable positive revision; and deferrable binding validation so concept plus context can be inserted atomically.
- [ ] Add concept-scoped immutable events and idempotency ledger with unique `(actor_id, command_type, idempotency_key)` and `(quote_request_id, command_type)`. Store only safe complete result snapshots.
- [ ] Add command guards for concept/context writes and immutable update/delete guards for event and ledger rows. No browser role receives direct table privileges.
- [ ] Add trigger validation under lock that concept/context roots resolve to the same production Website `quote_request_id`; future official bindings must resolve through accepted commercial lineage without changing that lineage.
- [ ] Run PASS and regressions:

  ```powershell
  npx supabase db reset
  npx supabase test db supabase/tests/website_concept_pre_project_v1.sql
  npx supabase test db supabase/tests/operator_application_handoff.sql
  npx supabase test db supabase/tests/project_requirements_board_v1.sql
  ```

- [ ] Commit:

  ```powershell
  git add supabase/migrations/20260912130000_add_website_concept_work_context_foundation_v1.sql supabase/tests/website_concept_pre_project_v1.sql
  git commit -m "feat(concept): add pre-project authority roots"
  ```

### Task 3: Add the server-authoritative Website work projection

**Files:**
- Create: `supabase/migrations/20260912131000_add_website_concept_authority_v1.sql`
- Modify: `supabase/tests/website_concept_pre_project_v1.sql`, `supabase/tests/operator_application_handoff.sql`

**Interfaces:**
- Produces: `lws_internal.website_briefing_status_v1(uuid)`, `public.get_operator_website_work_v1(uuid)`, revised `public.get_operator_application_v1(uuid,text)` projection
- Preserves: existing application detail keys and commercial `project` projection

- [ ] Add failing tests for the exact closed `website_work` object in `NONE`, `PRE_PROJECT`, and `OFFICIAL_PROJECT` states.
- [ ] Assert `revision = 1` for eligible `NONE`, so the first command has an explicit optimistic-concurrency value; non-eligible reads remain `NONE` but omit `CAN_START_WEBSITE_CONCEPT`.
- [ ] Assert `CAN_START_WEBSITE_CONCEPT` is present only for an ACTIVE AAL2 owner and eligible active production Website dossier. AAL1 owner, admin, operations manager, operator, SDF, archived, trashed, purged, existing-concept, existing-context, and official-project cases return no start action.
- [ ] Assert `OPEN_WEBSITE` is projected for readable PRE_PROJECT and eligible official Website work, while role restrictions come from existing dossier-read authority.
- [ ] Run FAIL and require missing projection/action failures.
- [ ] Implement briefing status from submitted/reviewed intake plus non-null `submitted_at`; never accept it as input.
- [ ] Implement one fail-closed helper that resolves caller, dossier lifecycle, product/classification, concept, context, and commercial lineage and returns the exact DTO. Catch no binding mismatch as `NONE`; raise `WEBSITE_WORK_CONTEXT_BINDING_MISMATCH`.
- [ ] Replace only the latest `get_operator_application_v1(uuid,text)` definition in the new migration and append `website_work`; preserve all existing keys and authorization by delegating to its immediate predecessor or reproducing its exact current projection.
- [ ] Run PASS:

  ```powershell
  npx supabase test db supabase/tests/website_concept_pre_project_v1.sql
  npx supabase test db supabase/tests/operator_application_handoff.sql
  npx supabase test db supabase/tests/operator_dossier_detail_lifecycle_projection.sql
  ```

- [ ] Commit:

  ```powershell
  git add supabase/migrations/20260912131000_add_website_concept_authority_v1.sql supabase/tests/website_concept_pre_project_v1.sql supabase/tests/operator_application_handoff.sql
  git commit -m "feat(concept): project website work authority"
  ```

### Task 4: Implement the owner-only idempotent start command

**Files:**
- Modify: `supabase/migrations/20260912131000_add_website_concept_authority_v1.sql`, `supabase/tests/website_concept_pre_project_v1.sql`

**Interfaces:**
- Produces: `public.start_website_concept_v1(uuid,bigint,uuid)`
- Returns: the complete post-command `website_work` snapshot plus `replayed`

- [ ] Add failing tests for exact function signature, authenticated-only execute grant, active owner, AAL2, expected revision, request/product/classification/lifecycle checks, and absence of direct internal function grants.
- [ ] Add failing replay tests: same actor/key/fingerprint returns the same concept/context with `replayed=true`; same key plus changed request or expected revision returns `IDEMPOTENCY_CONFLICT`; another key after creation returns `WEBSITE_CONCEPT_ALREADY_EXISTS`.
- [ ] Add a two-session concurrency case using the repository's existing `dblink` pattern; assert exactly one concept, context, event, and ledger result survives.
- [ ] Run FAIL and require missing-command failures.
- [ ] Implement the command in one transaction: require `auth.uid()`, active owner, `assert_operator_aal2_v1()`, advisory lock by idempotency key, row lock on request, recompute eligibility, verify revision, derive briefing status, insert concept/context/event/ledger, and return one complete snapshot.
- [ ] Set command-local guards only around authorized inserts and clear them before return. Let transaction rollback remove all four rows on any injected failure.
- [ ] Fingerprint exactly authority version, server-resolved actor, command type, request id, and expected revision. Never include browser-supplied identity or derived state.
- [ ] Run PASS plus AAL2 regression:

  ```powershell
  npx supabase test db supabase/tests/website_concept_pre_project_v1.sql
  npx supabase test db supabase/tests/operator_mfa_aal2_authority_v1.sql
  ```

- [ ] Commit:

  ```powershell
  git add supabase/migrations/20260912131000_add_website_concept_authority_v1.sql supabase/tests/website_concept_pre_project_v1.sql
  git commit -m "feat(concept): add owner start command"
  ```

### Task 5: Route the bounded command through the caller-JWT Edge boundary

**Files:**
- Modify: `supabase/functions/commercial-operator-command/handler.ts`, `supabase/functions/commercial-operator-command/index.ts`, `supabase/functions/commercial-operator-command/handler.test.ts`

**Interfaces:**
- Adds action: `start_website_concept`
- Changes action input: `get_website_execution_workspace` accepts only `action,quote_request_id`
- Calls: `start_website_concept_v1`, later `get_website_execution_workspace_v2`

- [ ] Add Deno tests proving exact-key acceptance for the three-field start intent and rejection of `actor_id`, `role`, `mode`, `briefing_status`, `commercially_released`, `created_by`, `project_id`, credentials, and unknown keys.
- [ ] Add route tests proving start forwards caller JWT client transport to `start_website_concept_v1` with `p_quote_request_id`, `p_expected_website_work_revision`, and `p_idempotency_key` only.
- [ ] Add error mapping tests for AAL2/owner denial to 403, stale revision/idempotency/already-exists to 409, and unknown dossier to 404. Preserve CORS and no-store behavior.
- [ ] Change the Website workspace read validator test first: `project_id` is rejected as browser authority and the route forwards only `p_quote_request_id`.
- [ ] Run FAIL:

  ```powershell
  deno test --allow-env supabase/functions/commercial-operator-command/handler.test.ts
  ```

- [ ] Add the action allowlist, exact request normalization, transport branch, and narrow error mappings. Do not add service-role fallback or accept actor identity from the request.
- [ ] Run PASS:

  ```powershell
  deno test --allow-env supabase/functions/commercial-operator-command/handler.test.ts
  ```

- [ ] Commit:

  ```powershell
  git add supabase/functions/commercial-operator-command/handler.ts supabase/functions/commercial-operator-command/index.ts supabase/functions/commercial-operator-command/handler.test.ts
  git commit -m "feat(concept): route bounded start intent"
  ```

### Task 6: Render and start Website concepts in Dossiers

**Files:**
- Create: `scripts/operator-dossiers-website-concept.test.mjs`
- Modify: `assets/js/operator-dossiers.mjs`, `scripts/operator-dossiers.test.mjs`

**Interfaces:**
- Consumes: `detail.website_work.permitted_actions`
- Emits: exact `start_website_concept` intent and existing `website-{quote_request_id}` open request

- [ ] Add Node tests for strict `website_work` validation: reject unknown state/action, mismatched request id, PRE_PROJECT without concept/context, OFFICIAL_PROJECT without project/context, PRE_PROJECT with `commercially_released=true`, and duplicate actions.
- [ ] Add presentation tests for `Nog geen websiteconcept`, `PRE_PROJECT / CONCEPT`, `LIMITED|COMPLETE`, `Niet commercieel vrijgegeven`, `WEBSITE-CONCEPT STARTEN`, and `WEBSITE OPENEN`.
- [ ] Assert the start button depends only on `permitted_actions`; tests must show a browser `identity.role="owner"` cannot fabricate it and a server-permitted action renders without locally recomputing dossier eligibility.
- [ ] Assert clicking start opens a blocking confirmation with exact text `Voorlopig concept starten — dit is nog geen commerciële bestelling`; cancel sends zero commands.
- [ ] Assert confirmation sends only the exact bounded request with a fresh UUID idempotency key, disables repeat activation while pending, validates the complete returned snapshot, then atomically renders PRE_PROJECT without page reload.
- [ ] Assert `WEBSITE OPENEN` uses `projectWorkspaceSlot` nowhere and requests the existing Dossiers module slot from `websiteExecutionSlot(quote_request_id)`.
- [ ] Run FAIL:

  ```powershell
  node --test scripts/operator-dossiers-website-concept.test.mjs scripts/operator-dossiers.test.mjs
  ```

- [ ] Add a small Website-work validator/presenter in `operator-dossiers.mjs`, add `start_website_concept` to `DOSSIER_GATEWAY_ACTIONS`, wire the existing delegated click handler, and use the repository's existing dialog/confirmation primitive. Do not add a second module.
- [ ] Run PASS and Project regression:

  ```powershell
  node --test scripts/operator-dossiers-website-concept.test.mjs scripts/operator-dossiers.test.mjs scripts/operator-project-workspace.test.mjs
  ```

- [ ] Commit:

  ```powershell
  git add assets/js/operator-dossiers.mjs scripts/operator-dossiers-website-concept.test.mjs scripts/operator-dossiers.test.mjs
  git commit -m "feat(operator): start website concepts from dossiers"
  ```

### Task 7: Re-anchor Website Execution to the stable work-context

**Files:**
- Create: `supabase/migrations/20260912132000_reanchor_website_execution_workspace_v1.sql`
- Modify: `supabase/tests/website_concept_pre_project_v1.sql`, `scripts/operator-website-execution.test.mjs`

**Interfaces:**
- Adds: `website_execution_workspaces.website_work_context_id`
- Produces: `public.get_website_execution_workspace_v2(uuid)`
- Preserves: repository uniqueness and all provider/branch/URL/commit constraints

- [ ] Add failing pgTAP assertions that every existing valid Website commercial project receives exactly one OFFICIAL_PROJECT context and every existing workspace is backfilled to it before `website_work_context_id` becomes not null and unique.
- [ ] Add failing assertions that legacy `project_id`/`quote_request_id`, while retained during compatibility, equal their context projection and cannot be changed independently.
- [ ] Add PRE_PROJECT read tests returning `contract_version=2`, `mode=PRE_PROJECT`, concept/context ids, `project=null`, `workspace=null`, `commercially_released=false`, briefing status, and Requirements state/message.
- [ ] Add OFFICIAL_PROJECT compatibility tests returning the same repository, branch, preview, commit, project view, and production URL behavior as V1.
- [ ] Run FAIL and require missing-column/function failures.
- [ ] In the migration, backfill one deterministic context per existing Website commercial project through exact quotation/acceptance/request lineage, then add and validate the workspace context FK. Abort the migration on ambiguous or mismatched lineage; never guess.
- [ ] Add a guard that derives/checks legacy locators from context. Keep the old columns only as compatibility projections; do not permit them as independent authority.
- [ ] Implement `get_website_execution_workspace_v2(p_quote_request_id uuid)` with caller authorization and exact context resolution. PRE_PROJECT bypasses commercial start gates only for technical workspace read; OFFICIAL_PROJECT still composes the existing commercial project/start-gate authority.
- [ ] Revoke V1 execute after Edge cutover in this same migration only if no remaining runtime caller exists; otherwise leave it executable but prove the new action no longer invokes it. Never loosen V1 semantics.
- [ ] Run PASS:

  ```powershell
  npx supabase db reset
  npx supabase test db supabase/tests/website_concept_pre_project_v1.sql
  npx supabase test db supabase/tests/project_requirements_board_v1.sql
  node --test scripts/operator-website-execution.test.mjs
  ```

- [ ] Commit:

  ```powershell
  git add supabase/migrations/20260912132000_reanchor_website_execution_workspace_v1.sql supabase/tests/website_concept_pre_project_v1.sql scripts/operator-website-execution.test.mjs
  git commit -m "feat(website): bind execution to work context"
  ```

### Task 8: Open PRE_PROJECT in the existing Website managed child

**Files:**
- Modify: `assets/js/operator-website-execution.mjs`, `assets/js/operator-website-execution-child.mjs`, `assets/js/operator-module-registry.mjs`, `scripts/operator-website-execution.test.mjs`

**Interfaces:**
- Preserves: `websiteExecutionSlot(quoteRequestId)` and Dossiers `website-*` registry dispatch
- Removes PRE_PROJECT dependency on: `projectWorkspaceRequest(detail)` and Requirements RPC

- [ ] Add tests that `websiteExecutionRequest(detail)` accepts a validated PRE_PROJECT `website_work` with no project id and emits only `action,quote_request_id`.
- [ ] Add exact V2 response validation tests for request/context/concept/project binding, phase, briefing, release flag, workspace context id, safe URLs, and unknown/malformed values. Reject the whole response on any mismatch.
- [ ] Add child tests proving it derives context from `detail.website_work`, not `projectWorkspaceRequest(detail)`, and independently re-fetches dossier plus Website workspace after mount.
- [ ] Add PRE_PROJECT rendering assertions: `Voorlopig concept`, `Niet commercieel vrijgegeven`, briefing status, stable unlinked technical workspace, and `Requirements volgen na intake-sync.`
- [ ] Assert PRE_PROJECT never calls `get_project_requirements_board`, never renders `Terug naar Project`, and contains no Finance, release, publish, production activation, customer preview, or mail control. OFFICIAL_PROJECT keeps existing Requirements and back-navigation behavior.
- [ ] Run FAIL:

  ```powershell
  node --test scripts/operator-website-execution.test.mjs
  ```

- [ ] Update Website Execution DTO validation/view and child context. Branch only on validated server `mode`; PRE_PROJECT supplies the explicit Requirements empty state, OFFICIAL_PROJECT continues the existing Requirements request.
- [ ] Preserve the `website-*` registry branch and module-slot singleton. Change cache-buster query versions only on imports touched by this feature.
- [ ] Run PASS:

  ```powershell
  node --test scripts/operator-website-execution.test.mjs scripts/operator-workspace.test.mjs
  ```

- [ ] Commit:

  ```powershell
  git add assets/js/operator-website-execution.mjs assets/js/operator-website-execution-child.mjs assets/js/operator-module-registry.mjs scripts/operator-website-execution.test.mjs
  git commit -m "feat(website): open pre-project execution workspace"
  ```

At this checkpoint, stop and demonstrate the vertical slice locally: eligible owner sees start, exact confirmation creates one PRE_PROJECT, Dossiers shows `WEBSITE OPENEN`, and the existing Website child opens without quotation/project/payment/release. Do not start Tasks 9-14 until this slice passes.

## Hardening

### Task 9: Enforce Dossiers snapshot stability for concept reads and commands

**Files:**
- Create: `scripts/operator-website-concept-stability.test.mjs`
- Modify: `assets/js/operator-dossiers.mjs`, `scripts/operator-dossiers.test.mjs`

**Interfaces:**
- Produces: retained complete dossier/website-work presentation keyed by `quote_request_id`

- [ ] Add deterministic tests for: first load may show loading; same-record background refresh retains the complete snapshot; start command retains the old NONE snapshot while pending; validated success atomically swaps to PRE_PROJECT; malformed response/network failure retains the prior snapshot plus non-destructive error; cross-dossier switch clears immediately; authorization failure clears despite retention.
- [ ] Assert no same-record phase writes `-`, null, empty text, `hidden`, or generic loading into previously valid Website-work fields.
- [ ] Run FAIL:

  ```powershell
  node --test scripts/operator-website-concept-stability.test.mjs
  ```

- [ ] Add one pure retain helper following `retainWebsiteQuotationAuthorities` and retained Project workspace patterns. Retain the whole validated Website-work/dossier presentation, not individual labels.
- [ ] Ensure background refresh builds detail, substance, and Website-work validation before one state commit; do not clear on request start or catch.
- [ ] Run PASS plus existing refresh regressions:

  ```powershell
  node --test scripts/operator-website-concept-stability.test.mjs scripts/operator-dossiers-pricing-refresh.test.mjs scripts/operator-dossiers-trash-refresh.test.mjs scripts/operator-project-workspace.test.mjs
  ```

- [ ] Commit:

  ```powershell
  git add assets/js/operator-dossiers.mjs scripts/operator-website-concept-stability.test.mjs scripts/operator-dossiers.test.mjs
  git commit -m "fix(operator): retain website concept snapshots"
  ```

### Task 10: Enforce Website child snapshot stability and fail-closed invalidation

**Files:**
- Modify: `assets/js/operator-website-execution-child.mjs`, `scripts/operator-website-execution.test.mjs`, `scripts/operator-website-concept-stability.test.mjs`

**Interfaces:**
- Preserves: last complete child snapshot during 8-second refresh
- Invalidates by: existing Website slot plus `website_work_context_id`/revision in the resolved snapshot

- [ ] Add tests that same-context background refresh keeps context, concept badge, briefing, Requirements empty state, and repository fields mounted until a full response validates.
- [ ] Add tests for malformed workspace, context revision mismatch, network failure, context phase change, authorization denial, lease loss, and dispose. Only denial/lease/dispose may clear sensitive content immediately.
- [ ] Run FAIL with the focused stability test.
- [ ] Keep one frozen `currentSnapshot`; render only after detail and workspace resolve to the same request/context/revision. Background errors update only a separate status message.
- [ ] Ensure `refreshGeneration` prevents stale generations from replacing a newer snapshot and `dispose()` remains terminal.
- [ ] Run PASS:

  ```powershell
  node --test scripts/operator-website-concept-stability.test.mjs scripts/operator-website-execution.test.mjs
  ```

- [ ] Commit:

  ```powershell
  git add assets/js/operator-website-execution-child.mjs scripts/operator-website-execution.test.mjs scripts/operator-website-concept-stability.test.mjs
  git commit -m "fix(website): retain pre-project child snapshot"
  ```

### Task 11: Prove Multi-Screen singleton, duplicate focus, revoke, and re-resolution

**Files:**
- Modify: `scripts/operator-workspace.test.mjs`, `scripts/operator-website-execution.test.mjs`
- Product code: only if a test exposes a local defect in existing generic lifecycle code

**Interfaces:**
- Reuses: Dossiers module, `website-{quote_request_id}`, module-slot claim, server lease, local lock, epoch/sequence, invalidation

- [ ] Add tests that NONE-to-PRE_PROJECT does not change slot identity; opening twice requests the same module-slot and focuses the incumbent child; no `concept-*` slot is accepted or generated.
- [ ] Add tests that a child bootstrap carries no concept/project authority, and the child independently resolves `get_application_detail` plus `get_website_execution_workspace` after join.
- [ ] Add tests that server revoke, expired lease, invalid epoch/sequence, role/status change, and binding mismatch lock/clear the child; local opener state cannot keep it open.
- [ ] Add an invalidation test with the existing Website slot and context revision; stale/replayed invalidations cannot overwrite a newer snapshot.
- [ ] Run FAIL/PASS:

  ```powershell
  node --test scripts/operator-workspace.test.mjs scripts/operator-website-execution.test.mjs
  ```

- [ ] Commit tests and only any minimal generic fix they require:

  ```powershell
  git add scripts/operator-workspace.test.mjs scripts/operator-website-execution.test.mjs assets/js/operator-workspace-master.mjs assets/js/operator-workspace-child.mjs assets/js/operator-workspace-protocol.mjs assets/js/operator-window-guard.mjs
  git commit -m "test(workspace): prove pre-project slot continuity"
  ```

  Before committing, omit unchanged product files from `git add`.

### Task 12: Complete authority, concurrency, and negative side-effect proofs

**Files:**
- Modify: `supabase/tests/website_concept_pre_project_v1.sql`, `supabase/functions/commercial-operator-command/handler.test.ts`

**Interfaces:**
- Covers: role matrix, exact payload, replay/conflict, transactional rollback, immutable roots, commercial isolation

- [ ] Add the complete role matrix: owner AAL2 allowed; owner AAL1, admin, operations manager, operator, reviewer/read-only, disabled/revoked operator, anonymous, and service-role direct execution denied.
- [ ] Add all ineligible dossier cases: unknown, SDF, non-production, archived, trashed, purged, existing concept, orphan/conflicting context, official project, and changed expected revision.
- [ ] Add SQL injection/procedure shadow tests for fixed `search_path`; assert function owners are non-browser principals and grants expose only intended authenticated wrappers.
- [ ] Add immutable/update/delete tests for concept events and idempotency rows, direct-write guard tests for concept/context, and duplicate unique-key race assertions.
- [ ] Inject a failing event write in a transaction-local test and prove concept/context/ledger all roll back.
- [ ] Compare row counts and authoritative snapshots before/after success and every denial for quotation, acceptance, commercial project/customer, Finance, obligations, payments, milestones, customer email, preview access, site/publication, and `audit_events`/`PROJECT_WORK_STARTED`.
- [ ] Run PASS:

  ```powershell
  npx supabase test db supabase/tests/website_concept_pre_project_v1.sql
  deno test --allow-env supabase/functions/commercial-operator-command/handler.test.ts
  ```

- [ ] Commit:

  ```powershell
  git add supabase/tests/website_concept_pre_project_v1.sql supabase/functions/commercial-operator-command/handler.test.ts
  git commit -m "test(concept): harden authority isolation"
  ```

### Task 13: Add browser frame-sampling proof for Dossiers and managed child

**Files:**
- Create: `scripts/website-concept-pre-project-live-preview.test.mjs`
- Modify: `scripts/dossier-continuity-release-integration.test.mjs`
- Reuse: existing preview/test fixtures; do not add production routes

**Interfaces:**
- Samples: Dossiers concept card and Website managed child over at least three 8-second refresh cycles

- [ ] Build a local deterministic fixture/harness that alternates successful, delayed, failed, and malformed same-record reads after one valid PRE_PROJECT snapshot. Include a separate cross-dossier transition and authorization-revocation case.
- [ ] Add Playwright sampling every 16 ms plus a `MutationObserver`. Record hidden state and text for concept badge, briefing, non-commercial label, Website-open control, repository/empty state, and Requirements message.
- [ ] Require zero same-record frames with hidden valid content, `-`, `null`, blank values, or loading text after the first valid snapshot. Require immediate removal on cross-dossier switch and revoke.
- [ ] Assert no console error, page error, duplicate child, layout overlap, horizontal overflow, or unsafe external link. Run desktop and mobile viewport coverage used by existing continuity tests.
- [ ] Run FAIL before wiring the fixture, then PASS:

  ```powershell
  node --test scripts/website-concept-pre-project-live-preview.test.mjs
  node --test scripts/dossier-continuity-release-integration.test.mjs
  ```

- [ ] Commit:

  ```powershell
  git add scripts/website-concept-pre-project-live-preview.test.mjs scripts/dossier-continuity-release-integration.test.mjs
  git commit -m "test(concept): verify refresh frame stability"
  ```

### Task 14: Run the full local gate and produce a review checkpoint

**Files:**
- Create: `docs/superpowers/checkpoints/2026-09-12-website-concept-pre-project-v1-verification.md`
- Modify: none unless a test exposes a defect in this feature
- Validate: all files changed by Tasks 1-13

**Interfaces:**
- Produces: a reviewable local implementation history; no deployment artifact or production mutation

- [ ] Reset the local database and run focused database contracts:

  ```powershell
  npx supabase db reset
  npx supabase test db supabase/tests/website_concept_pre_project_v1.sql
  npx supabase test db supabase/tests/operator_application_handoff.sql
  npx supabase test db supabase/tests/project_requirements_board_v1.sql
  npx supabase test db supabase/tests/operator_mfa_aal2_authority_v1.sql
  ```

- [ ] Run Edge and frontend suites:

  ```powershell
  deno test --allow-env supabase/functions/commercial-operator-command/handler.test.ts
  node --test scripts/operator-dossiers.test.mjs scripts/operator-dossiers-website-concept.test.mjs scripts/operator-website-concept-stability.test.mjs scripts/operator-project-workspace.test.mjs scripts/operator-project-requirements.test.mjs scripts/operator-website-execution.test.mjs scripts/operator-workspace.test.mjs
  node --test scripts/website-concept-pre-project-live-preview.test.mjs scripts/dossier-continuity-release-integration.test.mjs
  ```

- [ ] Run repository continuity gates without release/deploy:

  ```powershell
  powershell -ExecutionPolicy Bypass -File scripts/invoke-dossier-continuity-ci-gate.ps1
  powershell -ExecutionPolicy Bypass -File scripts/invoke-dossier-continuity-release-gate.ps1
  ```

- [ ] Inspect schema/role diffs and prove no direct privilege expansion, no changed existing migration, no generated `dist-*` changes, and no forbidden scope:

  ```powershell
  git diff --check
  git diff --name-only 72d1ac3eb5694345ffa528ec6e9bbbb9bc61ff73..HEAD
  git status --short --untracked-files=all
  git diff 72d1ac3eb5694345ffa528ec6e9bbbb9bc61ff73..HEAD -- supabase/migrations
  ```

- [ ] Scan for forbidden implementation terms outside tests/docs and manually inspect every match: promotion command, intake sync, direct `commercial_projects` concept insert, customer mail, Finance/payment/milestone mutation, publication/live activation, `concept-*` slot, client-supplied actor/role/mode.
- [ ] Record exact commands, PASS outputs, commit hashes, schema/role review, changed-file scope, and every acceptance-matrix result in the verification checkpoint. Do not generate release distributions, run a production preflight, apply remote migrations, push, or deploy.
- [ ] If Task 14 requires a code correction, make one narrowly scoped fix commit and rerun the failing focused test plus the full gate before writing the checkpoint.
- [ ] Commit only the verification evidence:

  ```powershell
  git add docs/superpowers/checkpoints/2026-09-12-website-concept-pre-project-v1-verification.md
  git commit -m "docs(concept): record pre-project verification"
  ```

## Acceptance Matrix

| Criterion | Owning task | Exact executable proof |
|---|---:|---|
| `ACTIVE_DOSSIER_SHOWS_WEBSITE_WORK=JA` | 3, 6 | `website_concept_pre_project_v1.sql`; `operator-dossiers-website-concept.test.mjs` |
| `OWNER_CAN_START_CONCEPT=JA` | 4, 5, 6 | pgTAP start-command case; handler exact-route test; Dossiers click test |
| `CONFIRMATION_DIALOG=JA` | 6 | exact confirmation/cancel cases in `operator-dossiers-website-concept.test.mjs` |
| `PRE_PROJECT_PERSISTS=JA` | 2, 4 | pgTAP durable concept/context/event/replay cases |
| `WEBSITE_OPEN_VISIBLE=JA` | 6 | PRE_PROJECT presentation case |
| `WEBSITE_EXECUTION_OPENS=JA` | 7, 8, 11 | V2 workspace pgTAP; Website child test; singleton/re-resolution test |
| `NO_QUOTE_REQUIRED=JA` | 1, 4, 12 | no-quotation fixture starts; quotation snapshots unchanged |
| `NO_PAYMENT_REQUIRED=JA` | 1, 4, 12 | no-payment fixture starts; all payment tables unchanged |
| `NO_COMMERCIAL_RELEASE_REQUIRED=JA` | 1, 4, 7, 12 | PRE_PROJECT read without start gate; no project/release event mutation |
| `NO_CUSTOMER_NOTIFICATION=JA` | 1, 12 | email job and delivery authority counts unchanged |
| `NO_FINANCE_MUTATION=JA` | 1, 12 | Finance/obligation/payment snapshots unchanged |
| `NO_PUBLICATION_RIGHT=JA` | 8, 12 | no child publication controls; site/preview-access authorities unchanged |
| `DUPLICATE_CONCEPT_BLOCKED=JA` | 2, 4, 12 | unique constraints, replay/conflict, and concurrent dblink cases |
| `SAME_DOSSIER_REFRESH_STABLE=JA` | 9, 10, 13 | deterministic retention tests plus 16 ms sampling for three cycles |
| AAL2 and owner-only authority | 3, 4, 5, 12 | role matrix, MFA regression, handler mapping |
| Browser intent is bounded | 5, 6 | exact-key rejection and exact outbound body tests |
| One stable work-context | 2, 4, 7 | one-per-dossier constraints, start result, official backfill tests |
| Existing official Website work remains valid | 1, 3, 7, 8 | official fixture database and JS compatibility tests |
| Requirements remains commercial | 1, 7, 8, 14 | unchanged Requirements tests; PRE_PROJECT makes no Requirements RPC |
| Existing Multi-Screen lifecycle remains intact | 8, 11, 14 | `operator-workspace.test.mjs` and Website child tests |
| Cross-dossier data never leaks | 9, 13 | immediate-clear unit and browser cases |
| Revocation overrides retention | 10, 11, 13 | child revoke/lease/authorization tests |
| No promotion implementation | 12, 14 | action/function/slot scan and changed-file review |
| No intake-to-requirements sync | 8, 14 | explicit empty state and changed-file review |
| No weakened commercial authority | 1, 7, 12, 14 | unchanged migrations, regressions, side-effect snapshots, role diff |

## Self-Review Checklist

- [ ] Every V1 requirement in sections 4, 5, 6, 7, 8, 9, 10, 11, and 14 of the approved spec maps to a task and executable test above.
- [ ] No placeholder names, unfinished markers, generic function names, or unspecified migration timestamps remain.
- [ ] Function and action signatures match across SQL, Edge validation, Edge transport, frontend request builders, and tests.
- [ ] `get_website_execution_workspace` accepts only `quote_request_id`; PRE_PROJECT never requires `projectWorkspaceRequest(detail)`.
- [ ] Existing `project_requirements_*` tables/functions retain their project and accepted-quotation authority.
- [ ] The plan creates no promotion action/function/UI and no intake-sync logic.
- [ ] Exactly one `website_work_context_id` survives across the designed future promotion boundary; V1 never copies workspace state.
- [ ] The full UI Stability Contract covers first load, same-record refresh, command flight, malformed/network failure, cross-dossier switch, revocation, and master/child frame sampling.
- [ ] No task asks to edit generated distributions before an authorized release.
- [ ] No task asks to push, deploy, apply a remote migration, or mutate production.

## Stop Conditions

Stop implementation and return to design review if any of these occur:

- an eligible PRE_PROJECT cannot open without inserting or weakening a `commercial_projects` row;
- Requirements must be made non-commercial to render the Website child;
- an existing workspace cannot be mapped unambiguously to one dossier/project context;
- the command cannot atomically create concept, context, event, and idempotency result;
- the caller JWT, active owner, or AAL2 check would need to move into browser logic;
- preserving one `website-{quote_request_id}` slot would require bypassing server lease/claim authority;
- a same-record refresh cannot retain a complete validated snapshot without exposing stale data across dossiers;
- any focused regression shows quotation, acceptance, Finance, payment, mail, preview-access, publication, Project, Requirements, or official Website behavior changed.