# Website Work Requirements Closure Implementation Plan

Date: 2026-09-19
Status: planning complete; controller review required before implementation
Planning base: `98fd210487f2a712278eb070f0051a3f822b9ce3` (`feat(website): render safe project file content`)
Production main observed during planning: `17e2411f2608e5ec079ae73f51d3265efce3b68f`
Scope: local implementation plan only. This document authorizes no feature code, migration execution, database mutation, push, Edge deploy, or Pages deploy.

## 1. Outcome and invariants

Close the remaining Website business-work gap before the original Project Files Phase A Task 10/11 release gates. An authorized operator must receive a durable structured worklist derived from submitted/reviewed customer Website intake while the dossier is still `PRE_PROJECT`. This must not require or imply a quotation, quotation acceptance, invoice, payment, commercial project release, or production publication right.

The implementation must preserve these invariants:

1. `quote_request_id` is a dossier/request identity only. Its presence is never evidence that a quotation exists.
2. `website_work_context_id` is the primary Website-work authority before and after promotion.
3. One Website work context has at most one Website requirements board. Integrated and detached presentations are views of that same persisted board.
4. `project_id` is not required by the Website requirements authority in `PRE_PROJECT`; no nullable retrofit is made to the commercial Requirements tables.
5. Existing `project_requirements_boards`, `project_requirements`, `project_requirement_verifications`, their accepted-quotation provenance, and their RPC behavior remain unchanged.
6. Browser checkbox state, browser-selected refs, and opener data never create completion authority.
7. Every mutation is revision-bound, idempotent, caller-authorized, audited, and cross-context checked.
8. Promotion updates the existing work context and attaches commercial lineage; it does not copy, replace, or recreate the Website requirements board.
9. Tasks 2-9 Project Files behavior and read-only guarantees remain intact.

## 2. Reviewed current architecture

### 2.1 Commercial Requirements authority

The existing implementation is intentionally commercial:

- `supabase/migrations/20260910040000_add_project_requirements_board_foundation_v1.sql` defines `project_requirements_boards` and `project_requirements`. Both require `commercial_projects.project_id`; the board also requires `source_approval_id` and an accepted quotation payload hash.
- `supabase/migrations/20260910041000_add_project_requirements_board_projection_v1.sql` provides the authorized board projection and lifecycle command surface.
- `supabase/migrations/20260910051000_add_project_requirement_verification_v1.sql` adds append-only verification, evidence-driven system completion, and readiness integration.
- `supabase/tests/project_requirements_board_v1.sql` proves accepted-quotation source validation, composite project binding, forced RLS, no direct browser table access, idempotency, lifecycle revisions, server-projected actions, audit, and verification.
- `assets/js/operator-project-requirements.mjs` validates the exact DTO, status/mode/verification enums, progress arithmetic, filters, and bounded mutation intents.
- `assets/js/operator-project-requirements-child.mjs` renders safe text, re-resolves dossier authority, and currently shows the explicit PRE_PROJECT placeholder supplied by Website Execution.

These are design patterns, not storage to weaken. No implementation task may make commercial `project_id` nullable, remove quotation/approval foreign keys, expand accepted-scope source types, or make commercial authority polymorphic.

### 2.2 Website work identity and workspace

- `supabase/migrations/20260912130000_add_website_concept_work_context_foundation_v1.sql` establishes `website_concepts` and lifecycle-neutral `website_work_contexts`. `PRE_PROJECT` requires a concept and null project; `OFFICIAL_PROJECT` requires a project. The context ID is stable by design.
- `supabase/migrations/20260912131000_add_website_concept_authority_v1.sql` projects `get_operator_website_work_v1`.
- `supabase/migrations/20260912132000_reanchor_website_execution_workspace_v1.sql` binds Website Execution to `website_work_context_id` and provides `get_website_execution_workspace_v2`.
- `supabase/migrations/20260913100000_add_pre_project_technical_workspace_provisioning_v1.sql` preserves one Website workspace for PRE_PROJECT without a commercial project.
- Current Website Execution contract version 3 returns `requirements = { state: "NOT_AVAILABLE", message: "Requirements volgen na intake-sync." }` for PRE_PROJECT. `assets/js/operator-website-execution.mjs` validates that placeholder and uses commercial Requirements only for an official project.
- Project Files Tasks 2-9 bind reads to `website_work_context_id`, `website_workspace_id`, `binding_revision`, and the server-resolved canonical commit. Those authorities are the evidence boundary to reuse, not redesign.

### 2.3 Intake authority

`supabase/migrations/20260903010000_add_operator_dossier_substance_projection_v1.sql` exposes an allowlisted Website intake projection through `get_operator_dossier_substance_v1`. It contains the fields listed by the controller, including Website description/audience/goals, pages/features, shop, booking, languages, detailed modules, design/brand, content/media, domain/hosting/maintenance, SEO, social/integrations, priorities, notes, and confirmation.

The sync must read the authoritative intake row server-side. It must require `request_kind = 'website'`, production dossier authority, status in `submitted`/`reviewed`, non-null `submitted_at`, and `confirmation = true`. The browser-projected substance is useful presentation data but is not sync input authority.

### 2.4 Managed multi-window behavior

The managed workspace already owns singleton slot routing, focus, lease/claim, invalidation, revoke, and re-resolution. Requirements uses `req-<quote_request_id>` and Website uses `website-<quote_request_id>`. The child derives only the dossier UUID from its managed slot and re-fetches authority. It does not use `window.open` or trust URL query data.

The existing behavior must remain: first open claims one Requirements child; a later open focuses it. The closure changes the PRE_PROJECT data source, not the slot identity or workspace count.

### 2.5 Promotion state

Schema guards already define the legal promoted shape (`website_concepts.concept_status = 'PROMOTED'`, `promoted_project_id`, and the same context changing to `OFFICIAL_PROJECT`). No public production promotion command currently owns that transition. Requirements continuity therefore belongs in the future explicit promotion transaction planned below; it must not be left to an ad hoc migration or UI switch.

### 2.6 Original release route

`docs/superpowers/plans/2026-09-17-website-execution-project-files-phase-a-implementation-plan.md` defines:

- Task 10: verification-only cross-context, resource, and mutation isolation with no commit.
- Task 11: complete local Phase A release gate and checkpoint, still without deployment authorization.

Requirements Closure implementation and tests must finish first. Then the equivalent Task 10 matrix is extended with Requirements cross-context/no-write cases, followed by the complete Task 11 gate. Production actions remain controller decisions after both pass.

## 3. Exact authority and schema model

### 3.1 Additive Website requirements authority

Create a separate, narrowly named authority; do not alter the commercial tables:

| Table | Purpose and required binding |
|---|---|
| `public.website_requirements_boards` | One board per `website_work_context_id`; stores matching `quote_request_id`, board/sync state, mapping version, current intake snapshot identity/hash, positive revision, timestamps, and creator. No `project_id` authority. |
| `public.website_requirements` | Stable item identity under a board/context; deterministic `source_key`, source provenance/hash, item number/order, safe title/description/category, status, completion mode/rule, applicability/source-review state, evidence summary, and revision. |
| `public.website_requirement_sync_runs` | Immutable idempotent record of intake ID/version/hash, mapping version, request fingerprint, created/updated/retired/review-required counts, actor, command ID, and result. |
| `public.website_requirement_events` | Immutable lifecycle/source-change audit events bound to context, board, item when applicable, actor/system identity, command ID, prior/new revision, reason, and minimized safe metadata. |
| `public.website_requirement_verifications` | Append-only verification attempts bound to item, context, workspace, binding revision, canonical commit, rule key/version, result, evidence reference/hash, verifier identity, and timestamp. |

Controller-authoritative primary keys:

| Table | Exact primary key |
|---|---|
| `public.website_requirements_boards` | `requirements_board_id uuid primary key` |
| `public.website_requirements` | `requirement_id uuid primary key` |
| `public.website_requirement_sync_runs` | `sync_run_id uuid primary key` |
| `public.website_requirement_events` | `event_id uuid primary key` |
| `public.website_requirement_verifications` | `verification_id uuid primary key` |

`operation_id`, unqualified `id`, `record_id`, `log_id`, or another substitute is forbidden for these five root identities.

Exact work-context and dossier authority target:

- Task 1 adds additive constraint `website_work_contexts_context_quote_unique` on `public.website_work_contexts (website_work_context_id, quote_request_id)`. This exists solely to provide the composite FK target; it does not change PRE_PROJECT semantics or make `quote_request_id` a commercial quotation fact.
- `website_work_context_id` remains the primary technical Website identity. `quote_request_id` is the exact dossier binding.

Exact board authority:

- `public.website_requirements_boards` includes `requirements_board_id uuid primary key`, `website_work_context_id uuid not null`, and `quote_request_id uuid not null` as required authority columns.
- Primary key: `(requirements_board_id)`.
- Constraint `website_requirements_boards_context_unique`: `unique (website_work_context_id)`, enforcing one logical board per work context.
- Constraint `website_requirements_boards_context_quote_fk`: `foreign key (website_work_context_id, quote_request_id) references public.website_work_contexts (website_work_context_id, quote_request_id)`.
- Constraint `website_requirements_boards_authority_unique`: `unique (requirements_board_id, website_work_context_id, quote_request_id)`, providing the exact child authority target.

Exact requirement item authority:

- `public.website_requirements` includes required authority columns `requirement_id uuid primary key`, `requirements_board_id uuid not null`, `website_work_context_id uuid not null`, and `quote_request_id uuid not null`.
- Primary key: `(requirement_id)`.
- Constraint `website_requirements_board_fk`: `foreign key (requirements_board_id, website_work_context_id, quote_request_id) references public.website_requirements_boards (requirements_board_id, website_work_context_id, quote_request_id)`.
- Constraint `website_requirements_authority_unique`: `unique (requirement_id, requirements_board_id, website_work_context_id, quote_request_id)`, providing the exact requirement-level authority target.

Exact sync-run authority:

- `public.website_requirement_sync_runs` includes required authority columns `sync_run_id uuid primary key`, `requirements_board_id uuid not null`, `website_work_context_id uuid not null`, and `quote_request_id uuid not null`.
- Primary key: `(sync_run_id)`.
- Constraint `website_requirement_sync_runs_board_fk`: `foreign key (requirements_board_id, website_work_context_id, quote_request_id) references public.website_requirements_boards (requirements_board_id, website_work_context_id, quote_request_id)`.
- This is the immutable/idempotent intake-sync root. Task 1 creates only its durable shape and guards; Task 2 owns synchronization commands.

Exact event authority:

- `public.website_requirement_events` includes required authority columns `event_id uuid primary key`, `requirements_board_id uuid not null`, `website_work_context_id uuid not null`, and `quote_request_id uuid not null`; `requirement_id uuid` is nullable only for board-level events.
- Primary key: `(event_id)`.
- Constraint `website_requirement_events_board_fk`: `foreign key (requirements_board_id, website_work_context_id, quote_request_id) references public.website_requirements_boards (requirements_board_id, website_work_context_id, quote_request_id)`.
- Constraint `website_requirement_events_requirement_fk`: `foreign key (requirement_id, requirements_board_id, website_work_context_id, quote_request_id) references public.website_requirements (requirement_id, requirements_board_id, website_work_context_id, quote_request_id)` with normal PostgreSQL `MATCH SIMPLE` semantics. A null `requirement_id` permits a board-level event; a non-null value requires the exact requirement/board/context/quote binding.

Exact verification authority:

- `public.website_requirement_verifications` includes NOT NULL authority columns `verification_id uuid primary key`, `requirement_id uuid not null`, `requirements_board_id uuid not null`, `website_work_context_id uuid not null`, and `quote_request_id uuid not null`.
- Primary key: `(verification_id)`.
- Constraint `website_requirement_verifications_requirement_fk`: `foreign key (requirement_id, requirements_board_id, website_work_context_id, quote_request_id) references public.website_requirements (requirement_id, requirements_board_id, website_work_context_id, quote_request_id)`.
- Verification records remain append-only and immutable.

Additional required constraints:

- Unique item by `(requirements_board_id, source_key)` and deterministic unique item/order values among current items.
- The composite foreign keys, not application checks alone, reject context/quote, board/context, item/board, sync/board, event/board, and verification/item substitution.
- Context binding permits both phases without changing the board ID.
- `PENDING`, `ACTIVE`, `BLOCKED`, `COMPLETED`; `AUTO`, `OPERATOR`, `HYBRID`, `EXTERNAL`; `PASS`, `FAIL`, `UNKNOWN`, `NOT_APPLICABLE` retain their current meanings.
- A separate applicability/source-review field (`CURRENT`, `CHANGE_PENDING`, `REMOVAL_PENDING`, `RETIRED`) preserves the four execution statuses while making intake drift explicit.
- At most one `ACTIVE` current requirement per Website work context, matching the current worklist interaction model.
- Definitions and identities cannot be directly rewritten after work starts. Events and verifications cannot be updated or deleted.
- Forced RLS on all five tables; no table privileges for `public`, `anon`, `authenticated`, or `service_role`.
- Command guards permit writes only through reviewed functions. Security-definer functions use fixed search paths and re-resolve the human JWT or trusted verifier.
- Verification ingestion grants function execution only to the trusted backend principal; it is absent from browser routing. This does not grant that principal direct table authority or permit a browser to supply service-role credentials.
- None of the five Website requirements roots has a commercial `project_id` authority or an accepted-quotation, quotation-approval, invoice, payment, or commercial-project FK. PRE_PROJECT remains valid while the context and workspace project IDs are null and `commercially_released = false`.

### 3.2 Authorization policy

| Operation | Required authority |
|---|---|
| Read board/summary/history | Caller JWT; `ACTIVE` owner/admin/operations manager, or exact active assigned operator under existing dossier assignment policy. |
| Initial sync/resync; resolve source change | Caller JWT; `ACTIVE` owner or operations manager; AAL2; exact dossier/context; expected board/context revision; idempotency key. |
| Start/block; complete OPERATOR portion | Caller JWT; `ACTIVE` assigned operator or management; AAL2; server-projected action; expected item revision; idempotency key. |
| Reopen/correct | Caller JWT; `ACTIVE` owner or operations manager; AAL2; reason; expected item/board revision; idempotency key. |
| AUTO verification ingestion | Trusted backend verifier only, never a browser intent; exact closed evidence envelope and rule registry; actor/workspace/context binding revalidated. |
| HYBRID completion | Current PASS verification plus authorized human attestation; neither half alone completes. |
| EXTERNAL completion | PASS from an approved external evidence adapter; ordinary operators may block/reopen but cannot fabricate external PASS. |

No role, phase, `project_id`, mode, permitted action, source provenance, verifier identity, commit, or workspace binding supplied by the browser is trusted as authority.

## 4. Deterministic intake-to-requirements model

### 4.1 Canonical source snapshot

An internal function selects the intake row uniquely bound to the context's `quote_request_id` and requires its current revision to be `submitted` or `reviewed`, with non-null `submitted_at` and `confirmation = true`. The existing one-intake-per-dossier constraint is part of the proof; zero or more than one eligible row fails closed rather than choosing by timestamp. The function projects only the reviewed allowlist in a fixed key order, normalizes strings (trim and normalized line endings), normalizes arrays as ordered unique values according to field semantics, preserves typed booleans/numbers, and calculates SHA-256 over canonical JSON. Nulls, empty strings, empty arrays/objects, false optional feature flags, and detail objects whose enabling flag is not true produce no requirement.

Every generated item stores only safe provenance:

```json
{
  "authority_type": "SUBMITTED_WEBSITE_INTAKE",
  "intake_id": "uuid",
  "intake_revision": 7,
  "submitted_at": "timestamp",
  "source_path": "requested_pages",
  "source_key": "page:contact",
  "source_value_sha256": "64 lowercase hex",
  "mapping_version": 1
}
```

The projection may expose a safe source label, but not hidden intake fields or raw source blobs. Full customer text appears only in allowlisted requirement title/description fields with existing length limits and is always rendered with `textContent`.

### 4.2 Mapping catalog version 1

The mapper is a server-owned versioned catalog, not a prompt or browser algorithm:

| Source group | Generation rule | Category | Default mode |
|---|---|---|---|
| `business_description`, `target_audience`, `website_goals`, `primary_conversion_goal` | One requirement per non-empty scalar/list entry; stable keys by field and normalized entry | `CONTENT`/`OTHER` | `OPERATOR` |
| `has_existing_website`, `existing_website_url`, `elements_to_keep`, `improvement_areas` | Generate only from explicit existing-site request or non-empty preserve/improve content | `DESIGN`/`CONTENT` | `OPERATOR` |
| `requested_pages`, `other_pages`, `page_scope_details` | One page/module item per explicit non-empty selection/detail; canonical page key and fixed catalog order, then normalized custom-page order | `PAGE` | `HYBRID` where route evidence exists, otherwise `OPERATOR` |
| `requested_features`, `quote_form_details`, `download_details`, `newsletter_details` | One feature/module item per explicit enabled feature or non-empty detail | `FORM`/`INTEGRATION`/`AUTOMATION` | `HYBRID` unless no machine proof exists |
| `shop_required`, `shop_details` | Generate only when shop is true; details refine separate stable items without inventing omitted scope | `ECOMMERCE` | `HYBRID`/`EXTERNAL` for provider-dependent parts |
| `booking_required`, `booking_details` | Generate only when booking is true | `INTEGRATION` | `HYBRID`/`EXTERNAL` |
| `languages`, `primary_language`, `additional_languages`, `multilingual_details` | Generate only explicit languages and non-empty translation/SEO details | `CONTENT`/`SEO` | `HYBRID` or `OPERATOR` |
| design/brand/logo/color/inspiration/disliked fields | Generate only explicit non-empty direction or asset status | `DESIGN` | `OPERATOR` |
| content/image fields and `content_media_details` | Generate only explicit content/media responsibilities | `CONTENT`/`MULTIMEDIA` | `OPERATOR`/`HYBRID` |
| domain/hosting/maintenance fields and details | Generate only explicit status/support/interest | `TECHNICAL` | `EXTERNAL` or `OPERATOR` |
| SEO fields/details/keywords | Generate only explicit priority/scope/keywords | `SEO` | `HYBRID`/`OPERATOR` |
| `social_channels`, `integrations` | One item per explicit channel/integration | `INTEGRATION` | `EXTERNAL`/`HYBRID` |
| deadline fields/details, `priorities`, `additional_notes` | Generate only non-empty customer facts; never infer deliverables from a date alone | `OTHER` | `OPERATOR` |

`confirmation` is an eligibility fact, not a work item. `brand_status`, `content_status`, `image_status`, `domain_status`, and `hosting_status` generate work only when their explicit value denotes an action/responsibility; values such as "ready/already supplied" become provenance/context, not fabricated work.

Stable `source_key` is based on semantic field plus catalog key, not item position or mutable text. `item_number` and `sort_order` are assigned from the fixed group order and stable per-group key order. Repeated sync of the same canonical intake hash and mapping version returns the recorded result and creates no rows/events.

### 4.3 Later intake revision

Sync locks context, board, current items, and intake row. It computes the complete proposed set before writing and fails atomically on malformed data, unsupported values, stale expected revision, mismatched context, or ambiguous identity.

- New source key: create one `PENDING` item and event.
- Same key and same value hash: no item change.
- Changed/removed item still `PENDING` and never started/verified: update or retire deterministically, increment revision, and append an event.
- Changed/removed `ACTIVE`, `BLOCKED`, or `COMPLETED` item: preserve definition, status, progress, and evidence; set `CHANGE_PENDING` or `REMOVAL_PENDING`; store the proposed safe definition/hash in the immutable sync record; set board sync state `REVIEW_REQUIRED`; append an event. Readiness fails closed until resolution.
- Management resolution `KEEP`: acknowledge the newer source with reason while preserving the execution definition and history.
- Resolution `ACCEPT_CHANGE`: apply the reviewed definition. A completed item is reopened to `PENDING`, its current verification becomes `UNKNOWN`, and an invalidation event/verification record is appended.
- Resolution `RETIRE`: mark applicability `RETIRED`, exclude it from current progress, preserve all prior lifecycle/evidence rows, and require reason. It never deletes the item.

This makes legitimate revision safe without silently rewriting completed customer work.

## 5. Lifecycle, progress, and audit

The transition core mirrors the proven commercial pattern but is context-bound:

```text
PENDING --start--> ACTIVE
ACTIVE --block(reason)--> BLOCKED
BLOCKED --start--> ACTIVE
ACTIVE --operator/hybrid complete--> COMPLETED
PENDING/ACTIVE/BLOCKED --authoritative AUTO or EXTERNAL PASS--> COMPLETED
COMPLETED --management reopen(reason)--> PENDING
```

- Exactly one transition core owns row locks, expected revision, allowed transition, completion-mode policy, verification policy, event append, board revision/progress recalculation, and idempotent result.
- `complete` is never projected for `AUTO` or `EXTERNAL`. For `HYBRID`, it is projected only after a current PASS for the exact rule/workspace snapshot.
- Reopen appends a correction event, invalidates current completion evidence with a new immutable invalidation record, clears completion fields, returns status to `PENDING`, increments item/board revisions, and recalculates summary.
- Progress counts only required `CURRENT` items: total, completed, open (`PENDING` + `ACTIVE`), blocked. Any source-review conflict makes readiness `BLOCKED` even when numeric completion is 100%.
- Read projection returns customer/dossier context, requirement number, title, description, category, safe source label/path, status, completion mode, verification state, progress, source-review state, and server-projected permitted actions.

## 6. Evidence-driven automatic checkoff

### 6.1 Rule ownership

Create a closed internal rule registry keyed by `(completion_rule_key, completion_rule_version)`. A rule declares allowed mode, evidence type, required workspace states, freshness policy, and evaluator. Unknown/disabled/version-mismatched rules return `UNKNOWN` and cannot complete.

Initial reviewed rules should be deliberately small:

| Rule | Eligible use | Evidence and result |
|---|---|---|
| `website_route_present` v1 | Generated page item, `HYBRID` | Server Project Files provider resolves the expected route in the current canonical tree. This proves route presence only, not copy/design correctness. |
| `website_module_present` v1 | Explicit technical module, `HYBRID` | Expected allowlisted file/module exists at canonical commit. |
| `website_test_suite_passed` v1 | Technical acceptance item, `AUTO`/`HYBRID` | Trusted test run records suite ID/version, PASS, canonical commit, and workspace binding. |
| `approved_content_present` v1 | Narrow content marker, `HYBRID` | Server classifier proves a versioned safe marker at canonical commit; semantic quality remains operator-owned. |
| approved provider rules | Domain/hosting/integration item, `EXTERNAL` | Trusted provider adapter proves exact configured resource without exposing credentials. |

Most goals, branding, copy quality, customer preference, and subjective design requirements remain `OPERATOR`. No broad "file exists means customer requirement complete" rule is permitted.

### 6.2 Evidence envelope and completion

Every verification binds:

- `website_work_context_id` and `website_workspace_id`;
- current workspace `binding_revision`;
- server-resolved current canonical commit SHA and repository marker/binding identity where applicable;
- requirement ID/revision and source hash;
- completion rule key/version;
- result (`PASS`, `FAIL`, `UNKNOWN`, `NOT_APPLICABLE`);
- opaque safe `evidence_reference`, evidence SHA-256, verifier identity, and timestamp.

The verifier obtains commit and binding from server authority after acquiring the same read lease/budget controls as Project Files. Browser-selected commit/ref is rejected. A PASS atomically appends verification and invokes the transition core for an eligible `AUTO` item or an `EXTERNAL` item backed by its approved provider adapter. `HYBRID` stores PASS and enables human completion. FAIL/UNKNOWN never complete. Binding revision, canonical commit, rule version, source hash, or requirement revision changes make prior PASS non-current; history remains immutable.

## 7. PRE_PROJECT API and Edge contracts

Planned SQL contracts (exact names to lock in RED tests before implementation):

```text
get_website_requirements_board_v1(quote_request_id uuid, website_work_context_id uuid) -> jsonb
sync_website_requirements_from_intake_v1(quote_request_id uuid, website_work_context_id uuid, expected_board_revision bigint, idempotency_key uuid) -> jsonb
start_website_requirement_v1(quote_request_id uuid, website_work_context_id uuid, requirement_id uuid, expected_revision bigint, idempotency_key uuid) -> jsonb
block_website_requirement_v1(quote_request_id uuid, website_work_context_id uuid, requirement_id uuid, expected_revision bigint, reason text, idempotency_key uuid) -> jsonb
complete_website_requirement_v1(quote_request_id uuid, website_work_context_id uuid, requirement_id uuid, expected_revision bigint, attestation jsonb, idempotency_key uuid) -> jsonb
reopen_website_requirement_v1(quote_request_id uuid, website_work_context_id uuid, requirement_id uuid, expected_revision bigint, reason text, idempotency_key uuid) -> jsonb
resolve_website_requirement_source_change_v1(quote_request_id uuid, website_work_context_id uuid, requirement_id uuid, expected_revision bigint, resolution text, reason text, idempotency_key uuid) -> jsonb
record_website_requirement_verification_v1(verification envelope...) -> jsonb
promote_website_concept_v1(quote_request_id uuid, website_work_context_id uuid, project_id uuid, expected_context_revision bigint, idempotency_key uuid) -> jsonb
```

Browser Edge intents are exact and surplus-key rejecting:

- `get_website_requirements_board`
- `sync_website_requirements_from_intake`
- `start_website_requirement`
- `block_website_requirement`
- `complete_website_requirement`
- `reopen_website_requirement`
- `resolve_website_requirement_source_change`
- `promote_website_concept` (added with Task 8; owner+AAL2, exact project/context/revision/idempotency payload)

There is no browser intent for verification ingestion or provider evidence. `commercial-operator-command` forwards the caller JWT and only bounded locators/revisions/reasons/attestations/idempotency keys. It never accepts role, mode, provenance, progress, permitted actions, verifier, workspace IDs for mutation, commit/ref, repository IDs, tokens, or completion state from the browser.

## 8. Frontend and controlled views

### 8.1 Shared Website requirements contract

Evolve `assets/js/operator-project-requirements.mjs` into a shared presentation/validation module without weakening the existing commercial validator. Add a separate `validateWebsiteRequirementsBoard` and Website request/action builders requiring `quoteRequestId + websiteWorkContextId` and nullable `projectId` only as projected context. Keep commercial functions and exact DTO tests intact.

The Website projection contract increments `get_website_execution_workspace_v2` to a reviewed contract version and replaces the PRE_PROJECT placeholder with a closed requirements summary:

```json
{
  "state": "READY",
  "requirements_board_id": "uuid",
  "board_revision": 12,
  "completed": 4,
  "total": 9,
  "open": 4,
  "blocked": 1,
  "review_required": 0
}
```

`NO_BOARD`, `INTAKE_NOT_ELIGIBLE`, and `REVIEW_REQUIRED` are explicit server states. The Website child shows summary progress, completed/open/blocked counts, and a `Requirements openen` command. It does not embed the full board over the Project Files surface, preserving the large workspace.

### 8.2 Full Requirements child

Keep `req-<quote_request_id>`. `requirementsChildContext` re-resolves detail and binds exact `quote_request_id`, `website_work_context_id`, mode, context revision, and optional project. It always requests the Website context board when one exists, in both PRE_PROJECT and OFFICIAL_PROJECT. It does not switch to or copy the commercial board after promotion.

Render with DOM text APIs only:

- customer and dossier context;
- number, title, description, category, safe source/provenance label;
- status, completion mode, verification state, source-review state;
- progress and server-projected actions;
- reason/attestation/source-change dialogs with bounded text.

Same-record refresh retains the last complete snapshot. Cross-dossier/context switch, logout, revoke, authorization loss, binding mismatch, or child disposal clears sensitive board state immediately. Mutations refetch the authoritative board before invalidating `dossiers`; stale revisions are never retried automatically.

### 8.3 Detachable behavior

- First click requests managed slot `req-<quote_request_id>`; second click routes through the existing master and focuses the existing child.
- Integrated summary and detached child use the same read RPC and persisted board ID/revision.
- No second Website workspace or independent requirements cache is created.
- URL/slot contains only the non-secret dossier UUID already covered by the managed-window contract. JWT, context ID, workspace ID, repository external ID, installation ID, token, and capability never enter the URL.
- The child independently re-resolves `website_work_context_id` from the dossier; opener messages are navigation hints only.
- Existing lease, epoch, sequence, revoke, duplicate-focus, and invalidation protocols remain authoritative.

## 9. PRE_PROJECT to OFFICIAL_PROJECT continuity

The future promotion command is one transaction under active owner + AAL2 authority:

1. Lock request, concept, context, official commercial project, Website workspace, and Website requirements board.
2. Prove the commercial project has valid accepted quotation lineage for exactly the same `quote_request_id` without changing any commercial Requirements invariant.
3. Require expected context revision and reject mismatched/existing project binding.
4. Set concept `PROMOTED` and `promoted_project_id`; update the same context to `OFFICIAL_PROJECT` and its project ID.
5. Update the existing Website workspace's compatibility `project_id` under its context guard, preserving `website_workspace_id`, repository identity, binding, and Project Files state.
6. Do not update the Website requirements board identity or item identities. Its context FK and quote binding remain valid automatically.
7. Append immutable promotion evidence referencing the same board ID/revision and counts. Do not copy or synthesize completed work.
8. Invalidate existing `website-*` and `req-*` slots; both re-resolve the same context/board under the new phase.

The Website context board remains the Website worklist after promotion. The pre-existing commercial Project Requirements board remains a separate accepted-commercial-scope authority and is neither merged into nor substituted for the Website board. If both exist, API/UI labels and readiness consumers keep their meanings explicit: Website execution progress comes from the context board; commercial release gates continue to use the commercial board. Promotion records lineage and reports divergence for review but never rewrites either history.

## 10. Exact implementation file map

Planned creates:

- `supabase/migrations/20260919100000_add_website_requirements_foundation_v1.sql`
- `supabase/migrations/20260919101000_add_website_requirements_intake_sync_v1.sql`
- `supabase/migrations/20260919102000_add_website_requirements_lifecycle_projection_v1.sql`
- `supabase/migrations/20260919103000_add_website_requirement_verification_v1.sql`
- `supabase/migrations/20260919104000_add_website_requirements_promotion_continuity_v1.sql`
- `supabase/tests/website_requirements_foundation_v1.sql`
- `supabase/tests/website_requirements_intake_sync_v1.sql`
- `supabase/tests/website_requirements_lifecycle_v1.sql`
- `supabase/tests/website_requirement_verification_v1.sql`
- `supabase/tests/website_requirements_promotion_v1.sql`
- `supabase/tests/website_requirements_security_release_v1.sql`
- `supabase/functions/_shared/website-requirement-verification.ts`
- `supabase/functions/_shared/website-requirement-verification.test.ts`
- `docs/superpowers/checkpoints/2026-09-19-website-work-requirements-closure-verification.md` in implementation Task 9, not during this planning task

Planned modifications:

- `supabase/migrations/20260912131000_add_website_concept_authority_v1.sql` is not edited; later migrations use `create or replace` where a projection contract must evolve.
- `supabase/functions/commercial-operator-command/handler.ts`
- `supabase/functions/commercial-operator-command/handler.test.ts`
- `assets/js/operator-project-requirements.mjs`
- `assets/js/operator-project-requirements-child.mjs`
- `assets/js/operator-website-execution.mjs`
- `assets/js/operator-website-execution-child.mjs`
- `assets/css/operator-dashboard.css`
- `scripts/operator-project-requirements.test.mjs`
- `scripts/operator-website-execution.test.mjs`
- `scripts/operator-workspace.test.mjs`
- `docs/superpowers/checkpoints/2026-09-17-website-execution-project-files-phase-a-verification.md` only when the original Task 11 is actually rerun after closure.

Existing commercial migration files are reference-only and must not be modified.

## 11. TDD implementation tasks and commit boundaries

### Task 1: Add the context-bound Website requirements foundation

**FILES**
- CREATE: `supabase/migrations/20260919100000_add_website_requirements_foundation_v1.sql`; `supabase/tests/website_requirements_foundation_v1.sql`
- MODIFY: none
- TEST: `supabase/tests/website_requirements_foundation_v1.sql`; regression `supabase/tests/project_requirements_board_v1.sql`

**INTERFACES**
- Five additive Website requirements tables with exact PKs `requirements_board_id`, `requirement_id`, `sync_run_id`, `event_id`, and `verification_id`; additive `website_work_contexts_context_quote_unique`; exact named board/item/sync/event/verification composite authority FKs; command guards; immutable sync/events/verifications; forced RLS; revoked direct privileges.

**RED TEST FIRST**
- Assert the exact five PK names and types; required authority columns; named unique constraints and composite FKs from section 3.1; all other exact columns/types/NOT NULL/checks/indexes; positive revisions and timestamp shapes; PRE_PROJECT null-project operation; one board per context; immutable sync/events/verifications; and zero changed constraints/functions on the three commercial Requirements tables.
- Build synthetic CONTEXT_A and CONTEXT_B and prove database-enforced rejection of `CONTEXT_A + QUOTE_B`, `BOARD_A + CONTEXT_B`, `REQUIREMENT_A + BOARD_B`, `SYNC_A + BOARD_B`, `EVENT_A + BOARD_B`, and `VERIFICATION_A + REQUIREMENT_B`. Application checks alone do not satisfy this gate.
- Prove the five Website roots contain no required or authoritative `project_id`, accepted-quotation FK, quotation-approval FK, invoice FK, payment FK, or commercial-project FK; PRE_PROJECT works with null project and `commercially_released = false`.

**IMPLEMENTATION**
- Add the exact schema, the additive `website_work_contexts_context_quote_unique` target, named composite authority constraints, immutability guards, and internal command guards only. Do not expose sync, lifecycle, verification-ingestion, promotion, or browser RPCs yet. Do not modify any existing commercial Requirements table, constraint, provenance rule, or RPC.

**GREEN TESTS**
- `npx supabase test db supabase/tests/website_requirements_foundation_v1.sql`
- `npx supabase test db supabase/tests/project_requirements_board_v1.sql`

**SECURITY / SCOPE GATE**
- Prove forced RLS and no direct runtime-role table privileges; schema contains no token/secret/raw repository URL or nullable commercial authority. Require `SCHEMA_IDENTITIES_FULLY_EXPLICIT=JA`, `PRIMARY_KEYS_FULLY_EXPLICIT=JA`, `COMPOSITE_FKS_FULLY_EXPLICIT=JA`, `CROSS_CONTEXT_BINDING_DATABASE_ENFORCED=JA`, `PROJECT_ID_REQUIRED_FOR_PRE_PROJECT=NEE`, `QUOTATION_DEPENDENCY=NEE`, and `COMMERCIAL_REQUIREMENTS_AUTHORITY_CHANGED=NEE` before implementation proceeds.

**EXACT COMMIT SUBJECT**
- `feat(website): add context requirements authority`

### Task 2: Implement deterministic submitted-intake synchronization

**FILES**
- CREATE: `supabase/migrations/20260919101000_add_website_requirements_intake_sync_v1.sql`; `supabase/tests/website_requirements_intake_sync_v1.sql`
- MODIFY: none
- TEST: new sync pgTAP; `supabase/tests/website_concept_pre_project_v1.sql`

**INTERFACES**
- Internal canonical intake projector/mapper; `sync_website_requirements_from_intake_v1`; immutable sync runs; source-change resolution contract.

**RED TEST FIRST**
- Cover every allowlisted source group, empty/null/false suppression, stable keys/order, exact replay, changed-key resync, concurrent sync, non-submitted/unconfirmed intake, stale revision, ACTIVE/COMPLETED drift, and wrong-context substitution.

**IMPLEMENTATION**
- Implement mapping v1 and atomic diff rules from section 4. The server reads intake directly; browser payload never supplies answers.

**GREEN TESTS**
- `npx supabase test db supabase/tests/website_requirements_intake_sync_v1.sql`
- `npx supabase test db supabase/tests/website_concept_pre_project_v1.sql`

**SECURITY / SCOPE GATE**
- Assert no quotation/approval/issuance/acceptance/invoice/payment joins are eligibility prerequisites; sync changes no commercial, mail, preview, publication, or repository-operation rows.

**EXACT COMMIT SUBJECT**
- `feat(website): sync intake requirements idempotently`

### Task 3: Add board projection and lifecycle commands

**FILES**
- CREATE: `supabase/migrations/20260919102000_add_website_requirements_lifecycle_projection_v1.sql`; `supabase/tests/website_requirements_lifecycle_v1.sql`
- MODIFY: none
- TEST: new lifecycle pgTAP; commercial Requirements regression

**INTERFACES**
- `get_website_requirements_board_v1`; start/block/complete/reopen/source-resolution RPCs; shared private transition/readiness/action projectors.

**RED TEST FIRST**
- Assert caller JWT, active role/assignment, AAL2 mutation gates, exact binding, all legal/illegal transitions, one ACTIVE item, revisions, idempotency conflicts, permitted actions, reopen invalidation, progress arithmetic, and audit append.

**IMPLEMENTATION**
- Implement one locked transition core and closed projection. Manual completion is allowed only for `OPERATOR`, or `HYBRID` with current PASS.

**GREEN TESTS**
- `npx supabase test db supabase/tests/website_requirements_lifecycle_v1.sql`
- `npx supabase test db supabase/tests/project_requirements_board_v1.sql`

**SECURITY / SCOPE GATE**
- Denied callers receive no board metadata; no RPC accepts or derives authority from `project_id`; audit metadata is minimized and secret-key checked.

**EXACT COMMIT SUBJECT**
- `feat(website): add requirements lifecycle api`

### Task 4: Add evidence verification and automatic checkoff

**FILES**
- CREATE: `supabase/migrations/20260919103000_add_website_requirement_verification_v1.sql`; `supabase/tests/website_requirement_verification_v1.sql`; `supabase/functions/_shared/website-requirement-verification.ts`; `supabase/functions/_shared/website-requirement-verification.test.ts`
- MODIFY: none
- TEST: new pgTAP and Deno verification suites; Project Files provider/service regressions

**INTERFACES**
- Closed rule registry/evaluator; trusted `record_website_requirement_verification_v1`; evidence envelope tied to canonical workspace snapshot.

**RED TEST FIRST**
- Reject browser caller, browser-selected SHA/ref, stale binding/revision/commit, unknown rule/version, cross-context workspace, mismatched source hash, and insufficient evidence. Prove AUTO PASS completes, approved-provider EXTERNAL PASS completes, an operator cannot fabricate EXTERNAL completion, FAIL/UNKNOWN do not complete, HYBRID requires both halves, and reopen invalidates without deleting history.

**IMPLEMENTATION**
- Implement only reviewed v1 rules. Reuse Project Files read policy/provider boundaries and server canonical commit resolution; add no repository mutation dependency.

**GREEN TESTS**
- `npx supabase test db supabase/tests/website_requirement_verification_v1.sql`
- `deno test --allow-env supabase/functions/_shared/website-requirement-verification.test.ts supabase/functions/_shared/website-project-files-policy.test.ts supabase/functions/_shared/website-project-files-provider.test.ts supabase/functions/_shared/website-project-files-service.test.ts`

**SECURITY / SCOPE GATE**
- Static dependency and runtime spies show verification can read bounded evidence but cannot create repositories, write files, commit/push, build, publish, release, invoice, or pay.

**EXACT COMMIT SUBJECT**
- `feat(website): verify requirement completion evidence`

### Task 5: Route exact PRE_PROJECT browser intents

**FILES**
- CREATE: none
- MODIFY: `supabase/functions/commercial-operator-command/handler.ts`; `supabase/functions/commercial-operator-command/handler.test.ts`
- TEST: handler tests plus all existing Website/Requirements intent tests

**INTERFACES**
- Exact read/sync/lifecycle/source-resolution action schemas from section 7; caller JWT forwarding; stable error mapping.

**RED TEST FIRST**
- Add one positive and malformed/surplus/missing/wrong-type test per Task 5 intent; cross-context substitutions; AAL1/inactive/revoked caller; and assertions that no verification or browser service-role intent exists. Promotion routing remains absent until Task 8.

**IMPLEMENTATION**
- Extend the existing action allowlist, request parser, and RPC dispatch with bounded arguments only.

**GREEN TESTS**
- `deno test --allow-env --allow-read supabase/functions/commercial-operator-command/handler.test.ts`
- `deno check supabase/functions/commercial-operator-command/index.ts`

**SECURITY / SCOPE GATE**
- No credentials, repository external IDs, raw context tokens, role claims, source answers, or completion claims cross the browser contract.

**EXACT COMMIT SUBJECT**
- `feat(website): route requirements command intents`

### Task 6: Integrate Website summary and shared client contracts

**FILES**
- CREATE: none
- MODIFY: `assets/js/operator-project-requirements.mjs`; `assets/js/operator-website-execution.mjs`; `assets/js/operator-website-execution-child.mjs`; `assets/css/operator-dashboard.css`; `scripts/operator-project-requirements.test.mjs`; `scripts/operator-website-execution.test.mjs`
- TEST: the two modified Node suites and Project Files frontend regression

**INTERFACES**
- Separate exact Website board DTO validator/builders; Website Execution summary DTO; `Requirements openen` managed-slot command.

**RED TEST FIRST**
- Test PRE_PROJECT null project, exact context/board binding, summary arithmetic, malformed/surplus DTO rejection, safe text-only rendering, no fake progress, stale summary handling, and Project Files panel dimensions remaining unobstructed.

**IMPLEMENTATION**
- Preserve commercial validators. Replace the PRE_PROJECT placeholder with server summary and a compact open action; do not mount the full list over the working surface.

**GREEN TESTS**
- `node --test scripts/operator-project-requirements.test.mjs scripts/operator-website-execution.test.mjs scripts/operator-website-project-files.test.mjs`

**SECURITY / SCOPE GATE**
- No HTML injection, client-derived actions/progress, local persistence, URL authority, or Task 2-9 behavior change.

**EXACT COMMIT SUBJECT**
- `feat(website): show requirements workspace summary`

### Task 7: Complete the Requirements child and detachable singleton flow

**FILES**
- CREATE: none
- MODIFY: `assets/js/operator-project-requirements-child.mjs`; `assets/css/operator-dashboard.css`; `scripts/operator-project-requirements.test.mjs`; `scripts/operator-workspace.test.mjs`
- TEST: Requirements and workspace managed-window suites

**INTERFACES**
- `req-<quote_request_id>` full context board; filters/actions/source state; sibling Website open; managed focus/invalidation/revoke.

**RED TEST FIRST**
- Test first click opens one child, second click focuses it, no duplicate claim/workspace, same board revision in integrated/detached views, mutation refresh/invalidation, logout/revoke/context switch clear, opener substitution ignored, and no authority/token IDs in URLs.

**IMPLEMENTATION**
- Replace PRE_PROJECT placeholder branch with Website board fetch/render/action flow. Continue safe DOM rendering and existing managed-window protocols.

**GREEN TESTS**
- `node --test scripts/operator-project-requirements.test.mjs scripts/operator-workspace.test.mjs scripts/operator-website-execution.test.mjs`

**SECURITY / SCOPE GATE**
- Child re-resolves context on every authoritative refresh; denied/mismatch state clears immediately; no `window.open`, direct Supabase table call, or independent Website workspace.

**EXACT COMMIT SUBJECT**
- `feat(website): detach context requirements worklist`

### Task 8: Preserve requirements through official-project promotion

**FILES**
- CREATE: `supabase/migrations/20260919104000_add_website_requirements_promotion_continuity_v1.sql`; `supabase/tests/website_requirements_promotion_v1.sql`
- MODIFY: `supabase/functions/commercial-operator-command/handler.ts`; `supabase/functions/commercial-operator-command/handler.test.ts`; `scripts/operator-project-requirements.test.mjs`; `scripts/operator-website-execution.test.mjs`; `scripts/operator-workspace.test.mjs`
- TEST: promotion, concept, workspace, commercial Requirements, and frontend phase-switch suites

**INTERFACES**
- Owner+AAL2 `promote_website_concept` Edge intent and `promote_website_concept_v1` RPC; same context/workspace/board projection after phase switch; slot invalidation.

**RED TEST FIRST**
- Prove valid accepted commercial lineage is required for promotion, but not for prior PRE_PROJECT work. Assert same context/workspace/board/item IDs, revisions/progress/evidence/events, exact quote binding, idempotent replay, stale/cross-dossier rejection, and rollback on injected failure.

**IMPLEMENTATION**
- Implement the single transaction in section 9. Add no copy path and no automatic commercial release, invoice/payment, publication, or commercial Requirements mutation.

**GREEN TESTS**
- `npx supabase test db supabase/tests/website_requirements_promotion_v1.sql`
- `npx supabase test db supabase/tests/website_concept_pre_project_v1.sql supabase/tests/website_execution_workspace_v1.sql supabase/tests/project_requirements_board_v1.sql`
- `deno test --allow-env --allow-read supabase/functions/commercial-operator-command/handler.test.ts`
- `node --test scripts/operator-project-requirements.test.mjs scripts/operator-website-execution.test.mjs scripts/operator-workspace.test.mjs`

**SECURITY / SCOPE GATE**
- Before/after table snapshots prove no copied board/item/history, no commercial invariant weakening, and no Finance/mail/provider/publication side effect.

**EXACT COMMIT SUBJECT**
- `feat(website): preserve requirements on promotion`

### Task 9: Prove closure acceptance and prepare Phase A re-entry

**FILES**
- CREATE: `supabase/tests/website_requirements_security_release_v1.sql`; `docs/superpowers/checkpoints/2026-09-19-website-work-requirements-closure-verification.md`
- MODIFY: none; any missing acceptance case or product defect returns to its exact owning Task 1-8 file list and receives a focused RED/GREEN repair commit before Task 9 restarts
- TEST: complete acceptance matrix below and Tasks 2-9 regressions

**INTERFACES**
- Executable cross-context/no-write evidence and local closure checkpoint; no deployment authorization.

**RED TEST FIRST**
- Assemble two dossier/context/workspace/board fixtures and explicit A/B substitutions across read, sync, lifecycle, verification, window invalidation, and promotion. Snapshot commercial, Finance, mail, repository-operation, build, preview, publication, and production-release authorities.

**IMPLEMENTATION**
- Add tests/checkpoint only. Any product defect is fixed at its owning earlier task boundary, then the full Task 9 matrix restarts.

**GREEN TESTS**
- Run section 12 in full and record exact counts/SHAs/no-write snapshots.

**SECURITY / SCOPE GATE**
- Require zero cross-dossier data, zero unauthorized writes, zero browser service-role authority, no secret output, clean worktree except checkpoint before its commit, and `git diff --check` pass.

**EXACT COMMIT SUBJECT**
- `test(website): verify requirements closure isolation`

Planned implementation task count: 9. Planned green-path implementation commit count: 9. A defect discovered by Task 9 must return to its owning task and receive an additional focused repair commit, increasing the actual count rather than being folded into Task 9; Task 9 then restarts. Verification-only reruns of original Phase A Task 10 create no commit; original Task 11 retains its separately specified checkpoint commit.

## 12. Executable local acceptance matrix

| Acceptance ID | Executable proof | Required result |
|---|---|---|
| `PRE_PROJECT_REQUIREMENTS_WITHOUT_QUOTATION` | Sync fixture has no approval/draft/issuance rows | Board/items created; quotation tables unchanged |
| `PRE_PROJECT_REQUIREMENTS_WITHOUT_QUOTATION_ACCEPTANCE` | No acceptance/customer/project fixture | Read/lifecycle work with null project |
| `PRE_PROJECT_REQUIREMENTS_WITHOUT_INVOICE` | Snapshot obligations/invoice-related authorities | Progress works; counts unchanged |
| `PRE_PROJECT_REQUIREMENTS_WITHOUT_PAYMENT` | Snapshot expectations/evidence/reconciliations | Progress works; counts unchanged |
| `CUSTOMER_INTAKE_TO_STRUCTURED_WORKLIST` | Mapping fixture exercises all source groups | Exact expected source keys/order/categories/modes/provenance |
| `NO_DUPLICATE_REQUIREMENTS_AFTER_RESYNC` | Same sync twice and concurrently | Same board/items; one immutable sync result per key/fingerprint |
| `PERSISTENT_PROGRESS` | Mutate, reconnect/refetch integrated and detached views | Same server status/revision/counts |
| `START_BLOCK_COMPLETE_REOPEN` | Lifecycle pgTAP transition table | Only legal transitions; reasons/revisions/events preserved |
| `AUTHORITATIVE_AUTO_CHECKOFF` | Trusted PASS vs browser claim | Trusted current PASS can complete AUTO; browser cannot |
| `AUTHORITATIVE_EXTERNAL_CHECKOFF` | Approved adapter PASS vs operator/browser claim | Trusted current provider PASS can complete EXTERNAL; operator/browser cannot |
| `AUTO_EVIDENCE_BOUND_TO_CURRENT_WORKSPACE` | Substitute context/workspace/binding/commit/rule versions | Every stale/substituted envelope fails closed |
| `MANUAL_CORRECTION_REOPEN` | Reopen completed AUTO/OPERATOR/HYBRID items | PENDING, evidence non-current, progress recalculated, history retained |
| `AUDIT_HISTORY` | Query immutable events/sync/verifications | Complete ordered history; update/delete denied |
| `CROSS_DOSSIER_ISOLATION` | Context A with every identity from B | No metadata/result/write; stable denial |
| `DETACHABLE_REQUIREMENTS_WINDOW` | Managed workspace harness click/open | One `req-*` child displays full board |
| `SECOND_CLICK_FOCUSES_EXISTING_WINDOW` | Repeat same open request | Existing child focused; no second claim |
| `NO_DUPLICATE_WORKSPACE_AUTHORITY` | Count Website workspace/context/board after opens | One of each authority root |
| `INTEGRATED_AND_DETACHED_STATE_MATCH` | Compare validated board ID/revision/counts after each mutation | Exact match after invalidation/refetch |
| `LOGOUT_REVOKE_CONTEXT_SWITCH_INVALIDATES_WINDOW` | Trigger logout, revoke, dossier switch, context revision/binding loss | Detached and integrated sensitive state clears; no stale action remains |
| `PRE_PROJECT_TO_OFFICIAL_PROJECT_CONTINUITY` | Promote fixture and compare identities/history | Same context/workspace/board/items/evidence/events |
| `TASKS_2_TO_9_REGRESSION_PASS` | Existing Phase A database/Deno/Node commands | All pass; zero mutation-spy calls |

Run at minimum:

```powershell
npx supabase db reset
npx supabase test db supabase/tests/website_requirements_foundation_v1.sql
npx supabase test db supabase/tests/website_requirements_intake_sync_v1.sql
npx supabase test db supabase/tests/website_requirements_lifecycle_v1.sql
npx supabase test db supabase/tests/website_requirement_verification_v1.sql
npx supabase test db supabase/tests/website_requirements_promotion_v1.sql
npx supabase test db supabase/tests/website_requirements_security_release_v1.sql
npx supabase test db supabase/tests/project_requirements_board_v1.sql
npx supabase test db supabase/tests/website_concept_pre_project_v1.sql
npx supabase test db supabase/tests/website_execution_workspace_v1.sql
npx supabase test db supabase/tests/website_project_files_phase_a_v1.sql
npx supabase test db supabase/tests/operator_mfa_aal2_authority_v1.sql
deno test --allow-env supabase/functions/_shared/website-requirement-verification.test.ts supabase/functions/_shared/website-project-files-policy.test.ts supabase/functions/_shared/website-project-files-cursor.test.ts supabase/functions/_shared/website-project-files-provider.test.ts supabase/functions/_shared/website-project-files-service.test.ts
deno test --allow-env --allow-read supabase/functions/commercial-operator-command/handler.test.ts
deno check supabase/functions/commercial-operator-command/index.ts
node --test scripts/operator-project-requirements.test.mjs scripts/operator-website-execution.test.mjs scripts/operator-website-project-files.test.mjs scripts/operator-workspace.test.mjs
npm run test:page-end
npm run test:visual-contract
```

## 13. Original Phase A Task 10/11 re-entry

After all nine closure tasks and their checkpoint pass:

1. Re-run the original Phase A Task 10 as verification-only. Extend its two-context substitution matrix to include board/context/intake/item/verification IDs; include source-change and promotion substitutions; retain all existing resource limits and Project Files mutation spies. Add table snapshots proving Requirements reads/verifications do not create repository operations or mutate provider/workspace binding, and that Project Files reads do not mutate requirements progress. Require clean status and no Task 10 commit.
2. Run original Phase A Task 11 from the September 17 plan. Its database list must include all six new Website requirements pgTAP files and the commercial Requirements regression. Its Deno list must include the verification suite. Its frontend list must include Requirements singleton/state synchronization. Preserve the original ancestry/baseline checks, exact assertion counts, public-page regressions, no-write proof, and checkpoint format.
3. Update the Phase A verification checkpoint only during Task 11 with both Project Files and Requirements Closure evidence. Set `DEPLOY_AUTHORIZED=NEE` and `PUSH_AUTHORIZED=NEE` unless a later controller authorization explicitly changes them.
4. Only after controller review of the green Task 10/11 evidence may a separate action consider push, main promotion, remote migrations, Edge deployment, or Pages production deployment.

## 14. Design self-review and stop gates

| Risk reviewed | Resolution / mandatory stop |
|---|---|
| Duplicate business authority | Website context board owns Website execution work; commercial board retains accepted commercial scope. Neither silently substitutes for the other. |
| Commercial authority weakening | No existing commercial table/FK/source validator/RPC is changed. Commercial regressions run in Tasks 1, 3, 8, 9. |
| Quotation dependency retained | PRE_PROJECT sync/lifecycle fixtures contain no quotation records. Any quotation join in eligibility is a failing test. |
| PRE_PROJECT project requirement | Website board/items have no project authority; null project is tested throughout. |
| Intake drift | Canonical hash/version plus explicit `CHANGE_PENDING`/`REMOVAL_PENDING`; readiness fails closed. |
| Duplicate sync | Context/item uniqueness, row locks, expected revision, idempotency fingerprint, and concurrent tests. |
| Unsafe auto completion | Closed versioned rules, trusted verifier, canonical workspace evidence, no browser verification intent. |
| Missing reopen/correction | Management reopen and source-resolution paths invalidate evidence, append history, and recalculate progress. |
| Missing audit | Immutable sync, lifecycle, promotion, and verification facts; no update/delete. |
| Multi-window duplicate state | Existing singleton `req-*` slot; both views fetch one board; revoke/context clear tests. |
| Unsafe URL handoff | Slot contains only quote request UUID; child server-resolves context. No credentials or raw authority in URL. |
| Promotion data loss | Same context/workspace/board/item identities asserted before/after; no copy API exists. |
| Task 2-9 regression | Existing Project Files database, provider, Edge, frontend, no-write, and resource gates rerun unchanged. |

Immediate implementation stop conditions include: unexplained production/base ancestry movement; any need to weaken commercial Requirements; ambiguous intake identity; inability to bind canonical evidence server-side; cross-context metadata exposure; direct browser table write; unexpected service-role browser path; duplicate board/workspace; promotion requiring copy; unrelated failing baseline not documented; or any production action without new controller authorization.

## 15. Planning authorization record

This planning task creates only this document. It starts neither original Task 10 nor Task 11. It creates no migration, feature code, test, checkpoint, database mutation, push, or deployment.

`QUOTATION_REQUIRED_FOR_PRE_PROJECT=NEE`
`QUOTATION_ACCEPTANCE_REQUIRED_FOR_PRE_PROJECT=NEE`
`INVOICE_REQUIRED_FOR_PRE_PROJECT=NEE`
`PAYMENT_REQUIRED_FOR_PRE_PROJECT=NEE`