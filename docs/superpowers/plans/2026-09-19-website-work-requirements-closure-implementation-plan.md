# Website Work Requirements Closure Implementation Plan

Date: 2026-09-19
Status: planning complete; controller review required before implementation
Planning base: `98fd210487f2a712278eb070f0051a3f822b9ce3` (`feat(website): render safe project file content`)
Task 8 contract correction base: `db3ccb9b6d735ce0221089dfbdcf2909be6f9aa3` (`feat(website): detach context requirements worklist`)
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
- Command guards permit writes only through reviewed functions. Security-definer functions use fixed search paths and re-resolve the human JWT or exact trusted verifier authority.
- Verification ingestion grants `record_website_requirement_verification_v1` execution only to `service_role`; it is absent from browser routing. In addition to the EXECUTE grant boundary, both Task 4 RPCs require server-resolved `auth.jwt()->>'role' = 'service_role'` and otherwise raise `TRUSTED_WEBSITE_REQUIREMENTS_VERIFIER_REQUIRED`. The record RPC writes `verified_by='SYSTEM:website_requirements_verifier'` and rejects browser, owner, operations-manager, admin, operator, and other authenticated-human direct ingestion. `service_role` retains no direct table privileges and its credential may never cross the browser boundary.
- None of the five Website requirements roots has a commercial `project_id` authority or an accepted-quotation, quotation-approval, invoice, payment, or commercial-project FK. PRE_PROJECT remains valid while the context and workspace project IDs are null and `commercially_released = false`.

### 3.2 Authorization policy

| Operation | Required authority |
|---|---|
| Read board/summary/history | Caller JWT; `ACTIVE` owner, admin, or operations manager; or `ACTIVE` operator whose exact active dossier assignment matches `quote_request_id`. AAL2 is not required. Admin is read-only. Reviewer, read-only, profile-only, and every other role are denied. |
| Initial sync/resync | Caller JWT; `ACTIVE` owner or operations manager; AAL2; exact dossier/context; expected board revision under the Task 2 contract; idempotency key. |
| Resolve source change | Caller JWT; `ACTIVE` owner or operations manager; AAL2; exact dossier/context/requirement; expected requirement revision; idempotency key. |
| Start/block; complete OPERATOR portion | Caller JWT; `ACTIVE` owner or operations manager, or `ACTIVE` operator whose exact active dossier assignment matches `quote_request_id`; admin is denied; AAL2; server-projected action; expected requirement revision; idempotency key. |
| Reopen/correct | Caller JWT; `ACTIVE` owner or operations manager only; admin and operator are denied; AAL2; reason; expected requirement revision; idempotency key. |
| AUTO/HYBRID verification ingestion | `service_role` only through `record_website_requirement_verification_v1`, never a browser intent; `verified_by='SYSTEM:website_requirements_verifier'`; exact closed evidence envelope and rule registry; context/requirement/workspace/binding/ref/commit/source authority revalidated under lock. |
| HYBRID completion | Current PASS verification plus authorized human attestation; neither half alone completes. |
| EXTERNAL completion | Fail closed in Task 4 v1 with `UNKNOWN_WEBSITE_REQUIREMENT_RULE`. The v1 EXTERNAL registry is empty; no browser, human actor, generic provider, or adapter can complete an EXTERNAL requirement without a later controller-approved provider-specific contract. |

For Task 3, `management` means exactly `owner` or `operations_manager`. It never includes admin or operator. All Task 3 mutations require AAL2. The primary authority is always exact `website_work_context_id + quote_request_id`; `project_id` is nullable informational read context only and is never accepted or derived as mutation authority.

No role, phase, `project_id`, mode, permitted action, source provenance, verifier identity, commit, or workspace binding supplied by the browser is trusted as authority.

## 4. Deterministic intake-to-requirements model

### 4.1 Task 1 field reuse and Task 2 extension

Task 2 reuses the exact Task 1 columns and does not introduce aliases:

- Board: `revision`, `sync_state`, `mapping_version`, `current_intake_id`, `current_intake_revision`, and `current_intake_snapshot_sha256`.
- Requirement: `source_review_state` (the persisted name for the source-state model), `source_key`, `source_value_sha256`, `source_reference`, `status`, `required`, `completion_mode`, `completion_rule_key`, `completion_rule_version`, `item_number`, `sort_order`, and `revision`.
- Sync run: `intake_id`, `intake_revision`, `intake_snapshot_sha256`, `mapping_version`, `request_fingerprint`, `created_count`, `updated_count`, `retired_count`, `review_required_count`, `actor_id`, `command_id`, and `result`.

Task 2 adds only `public.website_requirement_sync_runs.proposed_changes jsonb not null` as a new persisted sync-contract field, constrained to a JSON array without forbidden keys. The exact expanded action counts are stored in the existing `result`; no duplicate scalar count, state, revision, provenance, or hash columns are added. Historical Task 1 migrations remain unchanged.

### 4.2 Fixed authority, defaults, and eligibility

Mapping version is exactly `1`. Every requirement emitted by Task 2 has `required = true`, `status = 'PENDING'`, `source_review_state = 'CURRENT'`, `completion_mode = 'OPERATOR'`, `completion_rule_key = null`, and `completion_rule_version = null`. `requirement_id` is its persistent UUID identity; `source_key` is its persistent semantic matching identity and is never derived from array position, `item_number`, `sort_order`, `requirement_id`, or mutable display text. Task 4 alone may later promote specifically reviewed items to `AUTO` or `HYBRID` with evidence rules.

The server selects exactly one intake through `website_work_context_id -> website_work_contexts.quote_request_id -> quote_request_intakes.quote_request_id`. It requires `quote_requests.record_classification = 'production'`, `quote_requests.request_kind = 'website'`, intake status `submitted` or `reviewed`, non-null `submitted_at`, and `confirmation = true`. Zero or more than one eligible row fails closed. `quote_request_intakes.draft_revision` is the exact `intake_revision`; `lifecycle_revision` is not mapping content authority. No quotation, approval, issuance, acceptance, commercial project, invoice, or payment join is an eligibility prerequisite.

Initial sync and resync require an `ACTIVE` operator with role `owner` or `operations_manager`, AAL2, exact context/dossier authority, expected board revision, and an idempotency key. Actor identity comes from server-side auth/session authority and is never accepted from the browser.

### 4.3 Canonical normalization and hashing

Canonical text normalization is exact: Unicode NFKC; CRLF and CR to LF; removal of control characters U+0000-U+0008, U+000B, U+000C, U+000E-U+001F, and U+007F; leading/trailing whitespace trim; an empty result becomes null and is suppressed. Normal internal newlines remain.

Arrays normalize every string with canonical text normalization, remove empties, deduplicate by normalized identity, and use deterministic order. Fixed catalog arrays use the catalog order below. Free-text arrays sort by `lower(normalized_value)`, then exact `normalized_value`; browser order is not authority. Booleans remain JSON booleans and numbers remain JSON numbers. Objects retain only explicitly allowlisted keys, recursively suppress null/empty values and unknown keys, and use canonical key order. Raw intake JSON is never stored.

The fixed catalog order is exact:

- `website_goals`: `professional_presence`, `generate_leads`, `quote_requests`, `contact_requests`, `appointments`, `reservations`, `sell_products`, `sell_services`, `portfolio`, `information`, `recruitment`, `other`.
- `requested_pages`: `home`, `about`, `services`, `products`, `portfolio`, `team`, `pricing`, `faq`, `reviews`, `blog`, `contact`, `quote_request`, `reservations`, `shop`, `jobs`, `gallery`, `other`.
- `requested_features`: `contact_form`, `quote_form`, `google_maps`, `social_links`, `reviews`, `gallery`, `newsletter`, `whatsapp`, `appointments`, `reservations`, `shop`, `online_payment`, `customer_login`, `downloads`, `search`, `multilingual`, `other`, `unsure`, `online_payment_products`, `online_payment_reservations`, `online_payment_appointments`, `online_payment_services`, `online_payment_registrations`, `online_payment_deposit`, `online_payment_other`.
- `design_styles`: `modern`, `business`, `minimal`, `elegant`, `luxury`, `warm`, `playful`, `creative`, `technical`, `industrial`, `calm`, `unsure`, `other`.
- `image_support`: `optimize_existing`, `ai_images`, `stock_images`, `professional_photography`, `none`, `unsure`.
- `priorities`: `professional_appearance`, `usability`, `more_requests`, `more_sales`, `mobile_experience`, `performance`, `seo`, `easy_management`, `fast_delivery`, `stay_within_budget`, `differentiate`, `other`.

In the catalog below, "relevant" has one exact meaning: a normalized scalar is non-null and non-empty, an array/object has at least one retained value, a boolean is `true`, and a canonical number is present. A retained `false` may provide context inside a source already activated by another value, but never activates a requirement by itself.

Language input is NFKC-normalized, trimmed, lowercased, and changes underscore to hyphen. Accent-insensitive base-language alias matching is exact: `nl|nederlands|dutch -> nl`; `fr|frans|francais|french -> fr`; `en|engels|english -> en`; `de|duits|deutsch|german -> de`; `it|italiaans|italiano|italian -> it`; `es|spaans|espanol|spanish -> es`. `primary_language` wins; if absent, the first valid legacy `languages` value is primary. Additional languages are normalized, deduplicated, stripped of primary, and deterministically sorted. Unknown languages are retained by normalized identity in `unknown_languages`.

`other_pages` splits only on LF/CRLF/CR and semicolon, never comma. Parts use canonical text normalization, drop empties, deduplicate case-insensitively, and sort by lowercase then exact name. Each custom page uses `page:custom:<hash16>`, where `hash16` is the first 16 lowercase hexadecimal characters of SHA-256 over `lower(normalized_custom_page_name)`.

`integrations` is a normalized free-text array. Each value uses `integration:external:<hash16>` with the same lowercase-name hash rule. Unknown `requested_features` never use the reserved `feature:custom:<hash16>` pattern and fail with `WEBSITE_REQUIREMENTS_MAPPING_UNSUPPORTED`.

For every emitted source, `source_value_sha256` is lowercase SHA-256 hex over the compact canonical JSON representation of only its allowlisted canonical source value. It excludes item/order IDs, browser data, and timestamps other than explicit source authority. The complete projection is exactly `{"mapping_version":1,"sources":[{"source_key":"...","source_value":<canonical safe JSON>}]}`, with sources in catalog order and dynamic peers lexicographically ordered. `intake_snapshot_sha256` is lowercase SHA-256 hex over that compact canonical JSON. Budget/commercial fields do not affect it.

Safe `source_reference` has exactly `authority_type`, `intake_id`, `intake_revision`, `submitted_at`, `source_path`, `source_key`, `source_value_sha256`, and `mapping_version`. `authority_type` is `WEBSITE_INTAKE`, `source_path` is `mapping_v1/<source_key>`, and `mapping_version` is `1`. It contains no raw blob, browser payload, token, credential, pricing snapshot, or hidden field.

Every description is exactly `Klantvraag uit bevestigde Website-intake. Bron: <source_key>. Details: <canonical_source_json>`. If longer than 1200 characters, take exactly its first 1187 characters and append `... [verkort]`.

The following never generate requirements: `budget_confirmed`, `budget_update_category`, `budget_notes`, `budget_update_category_scheme`, `budget_update_category_code`, `selected_package_definition_id`, and `confirmation`. Confirmation is eligibility only.

### 4.4 Exhaustive mapping catalog version 1

Only present/activated sources emit rows. Fixed order is the table order; custom pages occupy position 19 lexicographically, and dynamic external integrations occupy position 40 lexicographically. `item_number` and `sort_order` are the one-based row number of the complete current canonical set. They are presentation only and do not affect identity or source-change detection.

| Order | `source_key` | Exact title | Category | Emit and exact canonical source value |
|---:|---|---|---|---|
| 1 | `brief:site_direction` | `Verwerk briefing, doelgroep en doelen` | `CONTENT` | Emit if any value is non-empty. Object keys: `business_description`, `target_audience`, `website_goals`, `primary_conversion_goal`, `priorities`, `additional_notes`. |
| 2 | `site:existing` | `Behoud en verbeter relevante delen van de bestaande website` | `DESIGN` | Emit if `has_existing_website = true` or any other value is non-empty. Object keys: `has_existing_website`, `existing_website_url`, `elements_to_keep`, `improvement_areas`. |
| 3-18 | `page:<page_id>` | `Bouw pagina: <label>` | `PAGE` | Emit for exact `requested_pages` membership. Object keys: `requested`, `scope`, and for jobs `jobs_application`; suppressed keys are omitted. Scope may also activate `portfolio`, `reviews`, `blog`, `jobs`, or `gallery` unless null/empty/semantically `none`. |
| 19 | `page:custom:<hash16>` | `Bouw pagina: <normalized_custom_page_name>` | `PAGE` | One per normalized `other_pages` value. Object key: `name`. `linked_page_or_module` is the normalized name. |
| 20 | `module:shop` | `Bouw webshopfunctionaliteit` | `ECOMMERCE` | Emit for `shop_required = true`, feature/page `shop`, or non-empty details. Object keys: `shop_required`, `requested_feature`, `requested_page`, `shop_details`; detail keys: `approx_product_count`, `complex_product_count`, `payment_provider_count`, `shipping_scope`, `categories`, `online_payments`, `shipping`, `pickup`, `pickup_scope`, `existing_catalog`, `customer_accounts`, `catalog_import`, `erp_api`. |
| 21 | `module:booking` | `Bouw reservatie- of boekingsfunctionaliteit` | `INTEGRATION` | Emit for `booking_required = true`, feature `appointments`/`reservations`, page `reservations`, goal `appointments`/`reservations`, or non-empty details. Object keys: `booking_required`, `requested_features`, `requested_page`, `website_goals`, `booking_details`; detail keys: `tier`, `type`, `existing_system`, `existing_system_name`, `calendar_integration`. |
| 22 | `module:forms` | `Bouw formulieren en aanvraagflow` | `FORM` | Emit for feature `contact_form`/`quote_form`, page `quote_request`, goal `generate_leads`/`quote_requests`/`contact_requests`, or non-empty details. Object keys: `requested_features`, `requested_page`, `website_goals`, `quote_form_details`; detail keys: `file_uploads`, `database_workflow`, `automated_processing`, `review_approval`, `custom_logic`, `form_count`, `structure_scope`. |
| 23 | `module:payments` | `Implementeer online betalingen` | `ECOMMERCE` | Emit for any payment feature or `shop_details.online_payments = true`. Object keys: `requested_features`, `shop_online_payments`. |
| 24 | `module:multilingual` | `Implementeer meertaligheid` | `CONTENT` | Emit for feature `multilingual`, non-empty additional/unknown languages, or non-empty details. Object keys: `primary_language`, `additional_languages`, `unknown_languages`, `multilingual_details`; detail keys: `final_translations_supplied`, `same_structure`, `translation_required`, `seo_per_language`, `advanced_seo_research`, `language_specific_integrations`, `complex_scope`. |
| 25 | `design:visual_direction` | `Pas de afgesproken visuele richting toe` | `DESIGN` | Emit if any value is non-empty. Object keys: `design_styles`, `inspiration_sites`, `disliked_styles`. |
| 26 | `design:brand_assets` | `Verwerk logo, kleuren en huisstijl` | `DESIGN` | Emit if any value is relevant. Object keys: `brand_status`, `logo_status`, `brand_colors`, `branding_tier`. |
| 27 | `content:copy` | `Werk websitecopy uit` | `CONTENT` | Emit if any value is relevant. Object keys: `content_status`, `copywriting_scope`, `copy_page_count`. |
| 28 | `content:images` | `Werk beeldmateriaal uit` | `MULTIMEDIA` | Emit if any value is relevant. Object keys: `image_status`, `image_support`, `image_work_scope`, `paid_stock_handling`. |
| 29 | `feature:downloads` | `Implementeer downloads en documenttoegang` | `DOCUMENT_FLOW` | Emit for feature `downloads` or non-empty details. Object keys: `requested`, `access`. |
| 30 | `feature:newsletter` | `Implementeer nieuwsbriefkoppeling` | `INTEGRATION` | Emit for feature `newsletter` or non-empty details. Object keys: `requested`, `scope`, `analytics`, `custom_integration`. |
| 31 | `feature:search` | `Implementeer zoekfunctie` | `TECHNICAL` | Emit for feature `search` or non-empty/non-`none` `page_scope_details.search`. Object keys: `requested`, `scope`. |
| 32 | `feature:customer_login` | `Implementeer klantlogin` | `AUTH` | Emit for feature `customer_login`. Object key: `requested`. |
| 33 | `feature:gallery` | `Implementeer galerijfunctionaliteit` | `MULTIMEDIA` | Emit for feature `gallery`. Object key: `requested`; may coexist with `page:gallery`. |
| 34 | `feature:reviews` | `Implementeer reviewfunctionaliteit` | `INTEGRATION` | Emit for feature `reviews`. Object key: `requested`; may coexist with `page:reviews`. |
| 35 | `feature:manual_scope` | `Werk nog te bepalen functionaliteit uit` | `OTHER` | Emit for feature `other` or `unsure`. Object keys: `requested_features`, `additional_notes`. |
| 36 | `integration:google_maps` | `Integreer Google Maps` | `INTEGRATION` | Emit for feature `google_maps`. Object key: `requested`. |
| 37 | `integration:social_links` | `Implementeer social-links op de website` | `INTEGRATION` | Emit for feature `social_links`. Object key: `requested`. |
| 38 | `integration:whatsapp` | `Integreer WhatsApp-contact` | `INTEGRATION` | Emit for feature `whatsapp`. Object key: `requested`. |
| 39 | `integration:social_channels` | `Koppel sociale kanalen` | `INTEGRATION` | Emit for non-empty normalized `social_channels`. Object key: `social_channels`. |
| 40 | `integration:external:<hash16>` | `Integreer externe koppeling: <normalized_integration_name>` | `INTEGRATION` | One per normalized `integrations` value. Object key: `name`; `linked_page_or_module` is the `source_key`. |
| 41 | `technical:domain` | `Configureer domein` | `TECHNICAL` | Emit if any value is relevant. Object keys: `domain_status`, `domain_name`, `domain_service`. |
| 42 | `technical:hosting` | `Configureer hosting` | `TECHNICAL` | Emit if any value is relevant. Object keys: `hosting_status`, `hosting_support`, `details_hosting_support`. |
| 43 | `technical:maintenance` | `Configureer onderhoudsafspraken` | `TECHNICAL` | Emit only for top-level/details interest `yes`, `maybe`, or `info_requested`, or plan `care`/`care_plus`. Object keys: `maintenance_interest`, `details_maintenance_interest`, `maintenance_plan`. `no` alone does not emit. |
| 44 | `seo:scope` | `Implementeer SEO-scope` | `SEO` | Emit if any value is relevant. Object keys: `seo_priority`, `seo_keywords`, `scope`, `extra_language_seo`, `advanced_language_seo`. |
| 45 | `constraint:deadline` | `Respecteer afgesproken deadline` | `OTHER` | Emit if any value is relevant. Object keys: `deadline_date`, `deadline_reason`, `commercially_critical`, `hard_deadline`. |

Fixed page IDs and labels in positions 3-18 are exactly: `home -> Home`, `about -> Over ons`, `services -> Diensten`, `products -> Producten`, `portfolio -> Portfolio`, `team -> Team`, `pricing -> Prijzen`, `faq -> FAQ`, `reviews -> Reviews`, `blog -> Blog`, `contact -> Contact`, `quote_request -> Offerteaanvraag`, `reservations -> Reservaties`, `shop -> Shop`, `jobs -> Vacatures`, and `gallery -> Galerij`. Their `linked_page_or_module` is the `page_id`. All fixed module, feature, and integration rows use their own `source_key` as `linked_page_or_module`; all other fixed rows use null.

The `requested_features` catalog is exhaustive: `contact_form -> module:forms`; `quote_form -> module:forms`; `google_maps -> integration:google_maps`; `social_links -> integration:social_links`; `reviews -> feature:reviews`; `gallery -> feature:gallery`; `newsletter -> feature:newsletter`; `whatsapp -> integration:whatsapp`; `appointments|reservations -> module:booking`; `shop -> module:shop`; `online_payment|online_payment_products|online_payment_reservations|online_payment_appointments|online_payment_services|online_payment_registrations|online_payment_deposit|online_payment_other -> module:payments`; `customer_login -> feature:customer_login`; `downloads -> feature:downloads`; `search -> feature:search`; `multilingual -> module:multilingual`; `other|unsure -> feature:manual_scope`. Any other persisted value fails closed with `WEBSITE_REQUIREMENTS_MAPPING_UNSUPPORTED`.

### 4.5 Exact sync, result, idempotency, and proposed changes

The exact command is:

```text
public.sync_website_requirements_from_intake_v1(
  p_quote_request_id uuid,
  p_website_work_context_id uuid,
  p_expected_board_revision bigint,
  p_idempotency_key uuid
) returns jsonb
```

No browser parameter may supply intake answers, source identity/hash, mapping version, requirement definition, category, actor, or project authority. If no board exists, expected revision must be `0`; otherwise it must equal the current server-side board `revision`. Stale input fails closed, except an exact replay may return its stored result before stale-revision rejection.

Result root keys are exactly `contract_version`, `outcome`, `quote_request_id`, `website_work_context_id`, `requirements_board_id`, `board_revision`, `intake_id`, `intake_revision`, `intake_sha256`, `mapping_version`, `sync_run_id`, `replayed`, `review_required`, and `counts`. Both contract and mapping version are `1`. Outcome is exactly `SYNCED`, `REPLAYED`, or `REVIEW_REQUIRED`. `REPLAYED` requires `replayed=true`; `REVIEW_REQUIRED` requires `replayed=false` and `review_required=true`; `SYNCED` requires both booleans false. `counts` has exactly non-negative integer keys `created`, `updated`, `unchanged`, `retired`, `change_pending`, `removal_pending`, and `revived`.

Command identity is server-derived `actor_id + p_idempotency_key` (`command_id` stores the idempotency key). The server hashes exactly `quote_request_id`, `website_work_context_id`, `p_expected_board_revision`, `intake_id`, `intake_revision`, `intake_sha256`, and `mapping_version` into `request_fingerprint`. Same command identity and fingerprint returns the exact stored result without writes. Same command identity with another fingerprint fails `WEBSITE_REQUIREMENTS_IDEMPOTENCY_CONFLICT`. The same board/intake ID/revision/hash/mapping version may reuse the stored logical result without side effects.

`proposed_changes` is an immutable JSON array sorted by `source_key`. Each element has exactly `source_key`, `action`, `requirement_id`, `previous_source_value_sha256`, `proposed_source_value_sha256`, and `proposed_definition`. Action is exactly `CREATE`, `UPDATE_SAFE`, `UNCHANGED`, `RETIRE`, `REVIVE`, `CHANGE_PENDING`, or `REMOVAL_PENDING`. Requirement ID is UUID or null only for `CREATE`; hashes are lowercase 64-hex or null. Proposed definition is null when inapplicable, otherwise has exactly `title`, `description`, `category`, `linked_page_or_module`, `required`, `completion_mode`, `completion_rule_key`, `completion_rule_version`, and `source_reference`. It contains no lifecycle status, progress, evidence, or browser data.

### 4.6 Exact resync and concurrency model

The complete proposed set is computed before writes. The transaction locks, in order, the exact `website_work_contexts` row as primary serialization boundary, the exact eligible intake row, the board if present, all existing board requirements, and relevant sync/idempotency authority. Malformed, unsupported, stale, mismatched, or ambiguous input fails atomically. Concurrent syncs for one context cannot create two boards, duplicate requirements, lost updates, or multiple logical results.

- Same `source_key` and hash: `UNCHANGED`; no definition/lifecycle/evidence/revision reset. A presentation-only order update does not create source drift.
- New key: `CREATE`; new UUID, `PENDING`, `CURRENT`, required, and operator-only.
- Changed `PENDING` + `CURRENT`: `UPDATE_SAFE`; preserve UUID, update safe definition/provenance/hash, remain `PENDING` + `CURRENT`.
- Removed safe `PENDING`: `RETIRE`; preserve UUID and history, set `source_review_state='RETIRED'` and `required=false`; never delete.
- Reappearing retired key: `REVIVE`; reuse UUID, update safe definition/provenance/hash, set `PENDING`, `CURRENT`, and required.
- Changed `ACTIVE` or `BLOCKED`: `CHANGE_PENDING`; preserve current definition, status, progress, timestamps, blocked reason, evidence, verification/completion history; set `source_review_state='CHANGE_PENDING'`; proposal exists only in immutable sync run.
- Removed `ACTIVE` or `BLOCKED`: `REMOVAL_PENDING`; preserve all execution state and evidence; never delete.
- Changed `COMPLETED`: `CHANGE_PENDING`; preserve current definition, UUID, completion, evidence, and verification history; never reopen automatically.
- Removed `COMPLETED`: `REMOVAL_PENDING`; preserve completion and evidence; never delete or reopen.

Any `CHANGE_PENDING` or `REMOVAL_PENDING` sets board `sync_state='REVIEW_REQUIRED'`; without either it is `CURRENT`. Task 2 does not implement `KEEP_EXISTING`, `ACCEPT_CHANGE`, management `RETIRE`, lifecycle commands, verification ingestion, AUTO/EXTERNAL verification, or automatic completion. Source resolution remains Task 3 and evidence automation remains Task 4.

## 5. Lifecycle, progress, and audit

### 5.1 Revision, locking, and one-active contract

Every Task 3 mutation RPC accepts `p_expected_revision bigint`. It means exactly the target `website_requirements.revision`, never board, context, or sync revision. The caller sends no expected board or context revision. A stale target revision raises SQLSTATE `40001` with message `CONCURRENT_MODIFICATION`. Every successful non-replay mutation increments both target requirement revision and board revision by exactly one; `website_work_contexts.revision` remains unchanged.

The exact lock order is:

1. Authorize the server-resolved actor, role, assignment, and AAL2.
2. Acquire an advisory transaction lock for the idempotency identity.
3. Lock the exact `website_work_contexts` row `FOR UPDATE`.
4. Lock the exact `website_requirements_boards` row `FOR UPDATE`.
5. Lock the target `website_requirements` row `FOR UPDATE`.
6. For START, check for a conflicting ACTIVE requirement under the already locked board.
7. For source resolution, lock/select the current authoritative Task 2 sync proposal.

This order must remain compatible with Task 2 context/board/requirements serialization. At most one requirement with `status='ACTIVE'` may exist per `website_work_context_id`, regardless of `source_review_state`. If Task 1/2 do not enforce this at database level, Task 3 adds the exact partial unique index required.

### 5.2 Exact lifecycle transitions

The context-bound transition matrix is exact:

```text
PENDING + CURRENT --start--> ACTIVE
BLOCKED + CURRENT --start--> ACTIVE
ACTIVE + CURRENT --block(reason)--> BLOCKED
ACTIVE + CURRENT + OPERATOR attestation --complete--> COMPLETED
ACTIVE + CURRENT + HYBRID current PASS + attestation --complete--> COMPLETED
COMPLETED + CURRENT --management reopen(reason)--> PENDING
```

All unlisted transitions fail. START requires no other ACTIVE requirement. `PENDING -> ACTIVE` sets `started_at=now`, clears `blocked_reason`, and does not mutate evidence or source fields. `BLOCKED -> ACTIVE` preserves existing `started_at`, clears `blocked_reason`, and does not mutate evidence or source fields.

BLOCK is allowed only from `ACTIVE + CURRENT`. Its normalized trimmed reason is required and 1..500 characters. It preserves `started_at`, sets status `BLOCKED` and `blocked_reason` to the normalized reason, and does not mutate evidence or source fields.

COMPLETE is allowed only from `ACTIVE + CURRENT`. `OPERATOR` requires the exact attestation object `{"attestation":"<trimmed text>"}` with no surplus keys and text length 1..500; it sets `verification_result='NOT_APPLICABLE'`. `HYBRID` requires the same human attestation plus an already current authoritative PASS and preserves that PASS. Both set status `COMPLETED`, `completed_at=now`, `completed_by='OPERATOR:<operator_id>'`, and `evidence_reference` to the exact human attestation. `AUTO` and `EXTERNAL` can never be manually completed in Task 3.

REOPEN is allowed only from `COMPLETED + CURRENT` by management with AAL2 and a normalized reason of 1..500 characters. It sets status `PENDING`; clears `started_at`, `blocked_reason`, `completed_at`, `completed_by`, and `evidence_reference`; sets verification result to `NOT_APPLICABLE` for `OPERATOR` and `UNKNOWN` otherwise; and preserves requirement identity, events, and immutable verification history.

Task 3 performs no verification ingestion. Evidence invalidation is represented by the new requirement revision, clearing current evidence where required, resetting verification result where required, and appending `WEBSITE_REQUIREMENT_EVIDENCE_INVALIDATED`. Existing verification rows are never changed or deleted. Task 4 later treats currentness as revision-bound.

For Task 4, every successful non-replay verification mutation increments the requirement revision and board revision exactly once and leaves the work-context revision unchanged. The inserted immutable verification row stores the resulting new requirement revision. A current HYBRID PASS enables the Task 3 human completion at that revision. That completion increments the requirement again, making the PASS historical for new mutations. For readiness of the already completed HYBRID item only, that PASS remains completion evidence when its revision equals current requirement revision minus one and the matching `WEBSITE_REQUIREMENT_COMPLETED` event metadata has `previous_revision` equal to the verification revision and `new_revision` equal to current requirement revision; rule, source, workspace, binding, ref, commit, and expiry must still be coherent.

### 5.3 Source proposal authority and resolution

Source resolution never accepts `proposed_definition`, source hash, or `source_reference` from the browser. The server obtains the proposal only from an immutable Task 2 sync run matching the current board's `requirements_board_id`, `current_intake_id`, `current_intake_revision`, `current_intake_snapshot_sha256`, and `mapping_version`. Its `proposed_changes` must contain exactly one entry matching both target `requirement_id` and `source_key`, with an action compatible with the current source-review state; otherwise it fails closed with `WEBSITE_REQUIREMENT_SOURCE_PROPOSAL_NOT_FOUND` or `WEBSITE_REQUIREMENT_SOURCE_STATE_MISMATCH` as applicable.

Every source resolution requires management, AAL2, and a normalized reason of 1..500 characters. Exact resolution values are `KEEP_EXISTING`, `ACCEPT_CHANGE`, and `RETIRE`.

- `ACCEPT_CHANGE` is allowed only for `CHANGE_PENDING`. Apply the exact `proposed_definition`, `proposed_source_value_sha256`, and proposed `source_reference` from the current immutable sync run; preserve `requirement_id`; set `source_review_state='CURRENT'`, set `required` from the proposal, reset lifecycle to `PENDING`, clear `started_at`, `blocked_reason`, `completed_at`, `completed_by`, and `evidence_reference`, and set verification result to `NOT_APPLICABLE` for new `OPERATOR` mode or `UNKNOWN` otherwise. Preserve prior immutable history. If prior lifecycle/evidence existed, append `WEBSITE_REQUIREMENT_EVIDENCE_INVALIDATED`.
- `KEEP_EXISTING` is allowed for `CHANGE_PENDING` or `REMOVAL_PENDING`. Preserve exactly title, description, category, linked page/module, required, completion mode/rule, source hash/reference, lifecycle status/timestamps/reason/completer, evidence reference, and verification result. Set only `source_review_state='CURRENT'`, revisions, and events. A later materially new sync may flag the source again.
- `RETIRE` is allowed only for `REMOVAL_PENDING`. Never delete. Preserve requirement ID and immutable history; set `source_review_state='RETIRED'` and `required=false`. `PENDING` stays `PENDING`. `ACTIVE` and `BLOCKED` become `PENDING` and clear `started_at` and `blocked_reason`; if current evidence exists, clear current evidence, reset verification state, and append evidence invalidation. `COMPLETED` stays `COMPLETED` and preserves completion, evidence, and verification history. Retired items do not count toward progress or readiness.

After every source-resolution mutation, atomically set board `sync_state='REVIEW_REQUIRED'` if any item remains `CHANGE_PENDING` or `REMOVAL_PENDING`; otherwise set it to `CURRENT`. One unresolved item always keeps the board in review.

### 5.4 Progress and readiness

Progress has exactly `required_total`, `required_completed`, `required_open`, `required_blocked`, and `review_pending`. Only `required=true AND source_review_state='CURRENT'` contributes to the first four. Open means `PENDING + ACTIVE`; blocked means `BLOCKED`; review pending means every `CHANGE_PENDING + REMOVAL_PENDING` item regardless of required flag.

Readiness has exactly `ready_for_preview`, `readiness`, and `reason`. `readiness` is `READY`, `BLOCKED`, or `UNKNOWN`. Evaluate in this exact priority:

1. No board: `ready_for_preview=false`, `UNKNOWN`, `REQUIREMENTS_BOARD_MISSING`.
2. `review_pending > 0` or board review state: false, `BLOCKED`, `REQUIREMENTS_REVIEW_REQUIRED`.
3. `required_total = 0`: false, `BLOCKED`, `REQUIRED_REQUIREMENTS_MISSING`.
4. `required_blocked > 0`: false, `BLOCKED`, `REQUIRED_REQUIREMENT_BLOCKED`.
5. Any `required=true`, `source_review_state='CURRENT'`, `status='COMPLETED'` HYBRID or AUTO item without valid completion evidence: false, `BLOCKED`, `REQUIREMENT_VERIFICATION_STALE`.
6. `required_open > 0`: false, `BLOCKED`, `REQUIRED_REQUIREMENTS_OPEN`.
7. Otherwise: `ready_for_preview=true`, `READY`, `ALL_REQUIRED_REQUIREMENTS_COMPLETED`.

Progress keys and arithmetic remain exactly unchanged. A completed OPERATOR item continues to use the Task 3 human-attestation model and is not subject to the Task 4 verification-currentness gate.

### 5.5 Permitted actions

The only Task 3 client action names are `start_website_requirement`, `block_website_requirement`, `complete_website_requirement`, `reopen_website_requirement`, `accept_website_requirement_source_change`, `keep_existing_website_requirement_source`, and `retire_website_requirement_source`.

The three source-resolution names are also the only browser action names for those resolutions. A generic browser action named `resolve_website_requirement_source_change` does not exist. Task 5 maps each of the three names to the shared server RPC with its fixed server argument from section 7; the browser never supplies `resolution`.

- `CHANGE_PENDING`: management sees accept and keep; all others see none.
- `REMOVAL_PENDING`: management sees keep and retire; all others see none.
- `RETIRED`: none.
- `CURRENT + PENDING/BLOCKED`: an authorized lifecycle actor sees start only when no other ACTIVE item exists.
- `CURRENT + ACTIVE`: an authorized lifecycle actor sees block; also complete for `OPERATOR`, or for `HYBRID` only with current PASS. `AUTO`/`EXTERNAL` never show manual complete.
- `CURRENT + COMPLETED`: management sees reopen.

### 5.6 Closed board projection

`get_website_requirements_board_v1` returns exactly root keys `contract_version`, `quote_request_id`, `website_work_context_id`, `project_id`, `phase`, `context`, `board`, `items`, `progress`, `readiness`, and `empty_state`. Contract version is `1`; `project_id` is nullable informational context only.

`context` has exactly `customer`, `dossier_reference`, and `assigned_operator`. Assigned operator is null or exactly `{operator_id, display_name}` and contains no other operator metadata.

`board` is null when absent, otherwise has exactly `requirements_board_id`, `sync_state`, `revision`, `mapping_version`, `current_intake_id`, `current_intake_revision`, and `current_intake_snapshot_sha256`.

Each item has exactly `requirement_id`, `item_number`, `title`, `description`, `category`, `source`, `linked_page_or_module`, `status`, `completion_mode`, `sort_order`, `required`, `started_at`, `completed_at`, `verification_result`, `blocked_reason`, `revision`, `source_review_state`, and `permitted_actions`.

Safe `source` has exactly `authority_type`, `source_key`, `intake_id`, `intake_revision`, `submitted_at`, and `mapping_version`. It never exposes source hashes, raw intake, proposals, tokens, or credentials. `empty_state` is exactly `NO_BOARD` when an eligible context has no board, `INTAKE_NOT_ELIGIBLE` when the server determines that the intake is not eligible, and null when a board exists. Both empty states require null `board`, no items, and zero progress; intake eligibility is never inferred by a client.

### 5.7 Mutation result and idempotency

Every mutation returns exactly root keys `contract_version`, `command`, `quote_request_id`, `website_work_context_id`, `requirements_board_id`, `requirement_id`, `previous_status`, `status`, `previous_source_review_state`, `source_review_state`, `resolution`, `requirement_revision`, `board_revision`, and `replayed`. Contract version is `1`; command is exactly `START`, `BLOCK`, `COMPLETE`, `REOPEN`, or `RESOLVE_SOURCE`; resolution is null except for `RESOLVE_SOURCE`.

Task 3 may add one supporting authority, not a second Requirements root: `public.website_requirement_command_ledger`. Its exact core columns are `operation_id uuid primary key`, non-null `actor_id`, `quote_request_id`, `website_work_context_id`, `requirements_board_id`, `requirement_id`, `command_type`, `idempotency_key`, `request_fingerprint char(64)`, `result jsonb`, and `created_at timestamptz`. Its exact composite requirement authority FK uses `(requirement_id, requirements_board_id, website_work_context_id, quote_request_id)`. It has unique `(actor_id, command_type, idempotency_key)`, forced RLS, no direct privileges for `public`, `anon`, `authenticated`, or `service_role`, and writes only through the reviewed Task 3 command core.

The canonical fingerprint input is exactly contract version 1, server actor ID, command type, quote request ID, work context ID, requirement ID, expected requirement revision, normalized reason or null, canonical attestation or null, and resolution or null. Same actor, command type, key, and fingerprint returns the stored result with `replayed=true` and performs no mutation, event, or revision increment. Same unique identity with a different fingerprint raises SQLSTATE `P0001`, message `WEBSITE_REQUIREMENT_IDEMPOTENCY_CONFLICT`.

### 5.8 Audit events

Task 3 event types are exactly `WEBSITE_REQUIREMENT_STARTED`, `WEBSITE_REQUIREMENT_BLOCKED`, `WEBSITE_REQUIREMENT_COMPLETED`, `WEBSITE_REQUIREMENT_REOPENED`, `WEBSITE_REQUIREMENT_SOURCE_CHANGE_ACCEPTED`, `WEBSITE_REQUIREMENT_SOURCE_KEPT`, `WEBSITE_REQUIREMENT_RETIRED`, and `WEBSITE_REQUIREMENT_EVIDENCE_INVALIDATED`.

Every Task 3 event metadata object has exactly `requirements_board_id`, `requirement_id`, `source_key`, `previous_status`, `new_status`, `previous_source_review_state`, `new_source_review_state`, `previous_revision`, `new_revision`, `board_revision`, `reason`, `resolution`, and `sync_run_id`. Unused values are JSON null, never omitted. Raw proposal, raw attestation, raw evidence, tokens, and credentials are forbidden.

### 5.9 Exact Task 3 errors

The exact SQLSTATE/message pairs are: `22023/INVALID_WEBSITE_REQUIREMENT_COMMAND`, `22023/WEBSITE_REQUIREMENT_BLOCK_REASON_REQUIRED`, `22023/WEBSITE_REQUIREMENT_REOPEN_REASON_REQUIRED`, `22023/WEBSITE_REQUIREMENT_ATTESTATION_REQUIRED`, `22023/INVALID_WEBSITE_REQUIREMENT_SOURCE_RESOLUTION`, `42501/WEBSITE_REQUIREMENTS_ACCESS_DENIED`, `42501/WEBSITE_REQUIREMENT_ROLE_DENIED`, `42501/WEBSITE_REQUIREMENT_ASSIGNMENT_DENIED`, `42501/AAL2_REQUIRED`, `P0001/WEBSITE_REQUIREMENT_NOT_FOUND`, `P0001/WEBSITE_REQUIREMENTS_BOARD_NOT_FOUND`, `P0001/WEBSITE_ACTIVE_REQUIREMENT_CONFLICT`, `P0001/WEBSITE_REQUIREMENT_SOURCE_PROPOSAL_NOT_FOUND`, `P0001/WEBSITE_REQUIREMENT_IDEMPOTENCY_CONFLICT`, `40001/CONCURRENT_MODIFICATION`, `55000/INVALID_WEBSITE_REQUIREMENT_TRANSITION`, `55000/WEBSITE_REQUIREMENT_SOURCE_REVIEW_REQUIRED`, `55000/WEBSITE_REQUIREMENT_SOURCE_STATE_MISMATCH`, and `55000/WEBSITE_REQUIREMENT_VERIFICATION_REQUIRED`.

## 6. Evidence-driven automatic checkoff

### 6.1 Closed v1 rule registry

The internal registry is closed and keyed by `(completion_rule_key, completion_rule_version)`. Task 4 v1 contains exactly these four entries and no others:

| Rule key/version | Allowed modes | Evidence type | Persisted target interpretation | Freshness |
|---|---|---|---|---|
| `website_route_present` v1 | `HYBRID` | `REPOSITORY_ROUTE` | `linked_page_or_module` is a canonical repository-relative directory path. | No time expiry; exact current workspace, binding, ref, commit, source hash, and requirement revision. |
| `website_module_present` v1 | `HYBRID` | `REPOSITORY_FILE` | `linked_page_or_module` is a canonical repository-relative file path. | No time expiry; the same exact authority/currentness checks. |
| `website_test_suite_passed` v1 | `AUTO`, `HYBRID` | `TEST_RUN` | `linked_page_or_module` is `suite_id`, matching `^[a-z][a-z0-9_-]{0,79}$`; `suite_version=1`. | 24 hours. |
| `approved_content_present` v1 | `HYBRID` | `CONTENT_MARKER` | `linked_page_or_module` is a canonical repository-relative readable-text file path. | No time expiry; the same exact authority/currentness checks. |

The exact Task 4 v1 evidence-type set is `REPOSITORY_ROUTE`, `REPOSITORY_FILE`, `TEST_RUN`, and `CONTENT_MARKER`. `EXTERNAL_PROVIDER` does not exist. The EXTERNAL registry is empty because no provider-specific resource identity/configuration is authoritatively bound to a Website requirement. Every EXTERNAL rule key/version, including generic names such as `approved_provider_resource`, `generic_provider`, or `external_resource`, fails with `UNKNOWN_WEBSITE_REQUIREMENT_RULE`. Future EXTERNAL support requires a separate controller-approved provider-specific rule and adapter contract.

Task 4 does not convert OPERATOR requirements to HYBRID or AUTO and does not add rules to existing Task 2 items. Task 2 generated items remain `completion_mode='OPERATOR'`. Most goals, branding, copy quality, customer preference, and subjective design requirements therefore remain human-owned. No broad file-existence rule proves subjective completion.

### 6.2 Common evidence reference and hash

Every verification uses an exact `evidence_reference` object with keys `contract_version`, `evidence_type`, `website_work_context_id`, `website_workspace_id`, `binding_revision`, `repository_ref`, `commit_sha`, `requirement_source_sha256`, `observed_at`, and `details`; no extra key is allowed. `contract_version=1`. The trusted evaluator assembles all common values server-side. Browser input determines none of context, workspace, binding revision, repository ref, commit SHA, source hash, or result.

Common binding requires:

- evidence context equals the target requirement context;
- evidence workspace equals the current bound Website workspace;
- evidence binding revision equals current workspace binding revision;
- evidence repository ref equals the current database-authorized full repository ref;
- provider-resolved canonical commit equals both evidence `commit_sha` and current database-bound `website_execution_workspaces.last_commit_sha`;
- evidence source hash equals current lowercase `website_requirements.source_value_sha256`;
- `observed_at` is RFC3339 UTC.

`evidence_sha256` is lowercase SHA-256 over UTF-8 canonical JSON of exactly `evidence_reference`: object keys lexicographically sorted, array order preserved, no insignificant whitespace, and strings normalized. An existing helper may be reused only after byte-equivalence is proven with test vectors; otherwise Task 4 creates a private helper and matching vectors. The existing requirement storage column `website_requirements.evidence_summary` stores the current safe `evidence_reference`; references in lifecycle behavior to current `evidence_reference` mean this existing column and do not authorize a second column.

### 6.3 Exact evidence details and evaluation

`REPOSITORY_ROUTE.details` has exactly `path`, `object_type`, and `object_sha`. `path` is the normalized rule target, `object_type='tree'`, and `object_sha` is lowercase 40-hex. PASS means that target tree exists in the exact canonical snapshot. Authoritative not-found or path-kind mismatch is FAIL. Provider unavailable, timeout, throttle, or unsafe/unavailable provider state is UNKNOWN.

`REPOSITORY_FILE.details` has exactly `path`, `object_type`, and `object_sha`. `path` is the normalized rule target, `object_type='blob'`, and `object_sha` is lowercase 40-hex. PASS means that target blob exists in the exact canonical snapshot. Authoritative not-found or path-kind mismatch is FAIL. Provider unavailable, timeout, throttle, or a sensitive/unsafe target that cannot be authoritatively read is UNKNOWN.

`TEST_RUN.details` has exactly `suite_id`, `suite_version`, and `run_id`. `suite_id` equals the validated rule target, `suite_version=1`, and `run_id` is safe opaque text of 1..120 characters. Result is exactly PASS, FAIL, or UNKNOWN and comes only from `TrustedWebsiteTestRunSource`, bound to context, workspace, binding, repository ref, commit, suite ID, and suite version. `observed_at` is at most five minutes in the future and no more than 24 hours old at record time; `expires_at=observed_at + interval '24 hours'`.

`CONTENT_MARKER.details` has exactly `path`, `marker_key`, `marker_version`, and `marker_sha256`. `path` is the normalized target, `marker_key='LWS_APPROVED_CONTENT'`, `marker_version=1`, and `marker_sha256` is lowercase SHA-256 of the exact UTF-8 bytes of the required trimmed line `LWS_APPROVED_CONTENT_V1:<current lowercase source_value_sha256>`. PASS means that exact marker line exists in a safely readable UTF-8 file. A safely present file without the marker is FAIL. Provider/content-classifier unavailability or a target that cannot be read safely is UNKNOWN.

For REPOSITORY_ROUTE, REPOSITORY_FILE, and CONTENT_MARKER, `observed_at` must be within minus five through plus five minutes of record time and `expires_at` is null. These types have no independent time expiry.

### 6.4 Exact currentness and HYBRID completion evidence

A verification PASS is current only when all conditions hold: `source_review_state='CURRENT'`; current requirement rule key/version equals verification rule key/version; verification result is PASS; verification requirement revision equals current requirement revision; evidence source hash, context, workspace, binding revision, repository ref, and commit equal current authority; expiry is null or future; and evidence type is the exact registered type for the rule.

Every successful non-replay verification mutation increments requirement and board revision by exactly one, leaves work-context revision unchanged, and writes that resulting requirement revision into the immutable verification row. Old rows remain history and never count as current for a new mutation.

HYBRID PASS does not auto-complete. It stores current PASS and enables the Task 3 authorized human completion. Task 3 then increments the requirement revision, so that PASS becomes historical for new mutations. For readiness of that already completed HYBRID item only, the latest matching PASS remains completion evidence if its requirement revision equals current revision minus one and matching `WEBSITE_REQUIREMENT_COMPLETED` event metadata has `previous_revision` equal to that PASS revision and `new_revision` equal to current revision. Rule, source, workspace, binding, ref, commit, evidence type, and expiry must remain coherent. This exception proves only the completed HYBRID transition; it never makes the old PASS current for another mutation.

Task 3 `WEBSITE_REQUIREMENT_EVIDENCE_INVALIDATED` remains the mutation event for reopen/source invalidation. Time expiry and workspace, binding, ref, or commit drift without mutation create no event; currentness simply becomes false.

### 6.5 Result handling and automatic completion

Task 4 verification rows contain only PASS, FAIL, or UNKNOWN. NOT_APPLICABLE is a requirement projection state and is never inserted as a Task 4 verification row. OPERATOR completion remains entirely under the Task 3 human-attestation contract, with no required verification or automatic completion.

Only `website_test_suite_passed` v1 may use AUTO. A PASS may be recorded for a CURRENT requirement in PENDING, ACTIVE, BLOCKED, or COMPLETED state. For PENDING, ACTIVE, or BLOCKED AUTO PASS, atomically set status COMPLETED, `completed_at=now`, `completed_by='SYSTEM:website_requirements_verifier'`, `blocked_reason=null`, current evidence to the safe evidence reference, and `verification_result='PASS'`; preserve `started_at`; set `auto_completed=true`. For an already COMPLETED AUTO item, preserve `completed_at` and `completed_by`, refresh current verification/evidence and PASS state, and set `auto_completed=false`; there is no new lifecycle transition.

FAIL or UNKNOWN may be recorded for any eligible non-OPERATOR rule. They never reopen or complete, preserve lifecycle status and completion timestamps/actor, set current evidence to the safe evidence reference, set requirement verification result to FAIL or UNKNOWN, increment requirement and board revision exactly once, and set `auto_completed=false`.

Task 4 v1 never completes EXTERNAL because its registry is empty. An EXTERNAL key/version fails before verification insertion with `UNKNOWN_WEBSITE_REQUIREMENT_RULE`.

### 6.6 Trusted evaluator and Project Files boundary

`website-requirement-verification.ts` implements deterministic evaluation using existing read-only Project Files provider and policy primitives. It defines an injected read-only `TrustedWebsiteTestRunSource` whose return object has exactly `suiteId`, `suiteVersion`, `runId`, `result`, and `observedAt`; result is PASS, FAIL, or UNKNOWN. Its input binds exactly context, workspace, binding, repository ref, commit, suite, and suite version. Task 4 executes no shell command, accepts no browser test result, and adds no production wiring outside its four files.

Repository evaluation resolves exactly one provider snapshot from the database-authorized `repositoryRef`, performs at most one bounded target lookup/read, applies existing sensitive-path/content policy, obeys the existing operation-wide timeout, and performs no recursive repository scan. Provider/network reads occur before the SQL mutation transaction. The SQL RPC then revalidates every authority against locked database rows. The provider-resolved commit must exactly equal current workspace `last_commit_sha`; Task 4 never changes `last_commit_sha`.

Task 4 adds no GitHub writer and performs no repository creation, file write, commit, push, build, publish, release, invoice, payment, Project Files mutation, or other provider mutation. PASS/FAIL/UNKNOWN derives only from deterministic Project Files facts or `TrustedWebsiteTestRunSource`; AI never decides authoritative PASS.

### 6.7 Verification authority projection

Task 4 adds service-role-only stable SECURITY DEFINER function:

```text
public.get_website_requirement_verification_authority_v1(
  p_quote_request_id uuid,
  p_website_work_context_id uuid,
  p_requirement_id uuid,
  p_expected_revision bigint
) returns jsonb
```

Its exact root keys are `contract_version`, `quote_request_id`, `website_work_context_id`, `requirements_board_id`, `requirement_id`, `requirement_revision`, `completion_mode`, `rule_key`, `rule_version`, `source_value_sha256`, `source_review_state`, `verification_target`, and `workspace`. `contract_version=1`.

`verification_target` has exactly `kind` and `value`. Kind is DIRECTORY_PATH for `website_route_present`, FILE_PATH for `website_module_present` and `approved_content_present`, or SUITE_ID for `website_test_suite_passed`. Value derives only from persisted `linked_page_or_module` and is validated by its rule.

`workspace` has exactly `website_workspace_id`, `binding_revision`, `repository_provider`, `repository_owner`, `repository_name`, `repository_external_id`, `repository_node_id`, `repository_ref`, `ref_label`, `last_commit_sha`, `workspace_state`, and `repository_operation_state`. It contains no token, secret, installation credential, or provider request ID. It requires `workspace_state='REPOSITORY_READY'`, `repository_operation_state='COMPLETE'`, `repository_provider='GITHUB'`, and complete repository identity/binding; otherwise it fails `WEBSITE_REQUIREMENT_WORKSPACE_NOT_READY`.

### 6.8 Record RPC and result

The exact VOLATILE SECURITY DEFINER RPC with fixed search path is:

```text
public.record_website_requirement_verification_v1(
  p_quote_request_id uuid,
  p_website_work_context_id uuid,
  p_requirement_id uuid,
  p_expected_revision bigint,
  p_rule_key text,
  p_rule_version integer,
  p_result text,
  p_evidence_reference jsonb,
  p_idempotency_key uuid
) returns jsonb
```

Only `service_role` receives EXECUTE; both Task 4 RPCs additionally require `auth.jwt()->>'role' = 'service_role'`; direct authenticated/browser invocation is denied. The record RPC revalidates trusted authority and always records `verified_by='SYSTEM:website_requirements_verifier'`.

Result has exactly `contract_version`, `verification_id`, `quote_request_id`, `website_work_context_id`, `requirements_board_id`, `requirement_id`, `requirement_revision`, `board_revision`, `rule_key`, `rule_version`, `result`, `status`, `auto_completed`, and `replayed`; no extra keys. Contract version is 1.

### 6.9 Verification idempotency

Task 4 creates `public.website_requirement_verification_commands` with exact core columns `operation_id uuid primary key`, `quote_request_id uuid not null`, `website_work_context_id uuid not null`, `requirements_board_id uuid not null`, `requirement_id uuid not null`, `idempotency_key uuid not null`, `request_fingerprint char(64) not null`, `result jsonb not null`, and `created_at timestamptz not null default clock_timestamp()`. Its composite requirement/board/context/quote FK targets the exact Website requirement authority. `idempotency_key` is unique. It has forced RLS, no direct privileges for public, anon, authenticated, or service_role, and is written only by the trusted verification core.

The canonical fingerprint contains exactly contract version 1, `verified_by='SYSTEM:website_requirements_verifier'`, quote request ID, work-context ID, requirement ID, expected requirement revision, rule key, rule version, result, and evidence SHA-256. Same key and fingerprint returns the stored result with `replayed=true` before stale-revision rejection and causes no verification row, event, revision increment, or auto completion. Same key with another fingerprint raises `P0001/WEBSITE_REQUIREMENT_VERIFICATION_IDEMPOTENCY_CONFLICT`.

### 6.10 Locking and mutation order

The exact SQL order is: verify service_role/trusted principal; advisory transaction lock on idempotency key; context row FOR UPDATE; board row FOR UPDATE; requirement row FOR UPDATE; current Website workspace/binding row FOR UPDATE; revalidate rule/source/workspace/binding/ref/commit/evidence; insert immutable verification; update requirement exactly once; update board revision exactly once; append events; insert idempotency result. Stale expected requirement revision raises `40001/CONCURRENT_MODIFICATION`. This serialization prevents concurrent duplicate PASS, lost revisions, duplicate automatic completion, and duplicate events.

### 6.11 Task 4 events

Task 4 emits exactly `WEBSITE_REQUIREMENT_VERIFICATION_RECORDED` for every successful non-replay verification and `WEBSITE_REQUIREMENT_AUTO_COMPLETED` only when that mutation changes PENDING, ACTIVE, or BLOCKED to COMPLETED. Actor is `SYSTEM:website_requirements_verifier`.

Every Task 4 event metadata object has exactly `verification_id`, `requirements_board_id`, `requirement_id`, `rule_key`, `rule_version`, `evidence_type`, `evidence_sha256`, `result`, `previous_status`, `new_status`, `previous_revision`, `new_revision`, `board_revision`, and `auto_completed`. It contains no raw evidence, file content, provider error/body/token/request ID, or other secret.

### 6.12 Exact Task 4 errors

The exact SQLSTATE/message pairs are `42501/TRUSTED_WEBSITE_REQUIREMENTS_VERIFIER_REQUIRED`, `22023/INVALID_WEBSITE_REQUIREMENT_VERIFICATION_COMMAND`, `22023/UNKNOWN_WEBSITE_REQUIREMENT_RULE`, `22023/INVALID_WEBSITE_REQUIREMENT_VERIFICATION_EVIDENCE`, `22023/WEBSITE_REQUIREMENT_VERIFICATION_STALE`, `P0001/WEBSITE_REQUIREMENT_NOT_FOUND`, `P0001/WEBSITE_REQUIREMENTS_BOARD_NOT_FOUND`, `P0001/WEBSITE_REQUIREMENT_VERIFICATION_IDEMPOTENCY_CONFLICT`, `40001/CONCURRENT_MODIFICATION`, `23514/WEBSITE_REQUIREMENT_RULE_MISMATCH`, `23514/WEBSITE_REQUIREMENT_WORKSPACE_MISMATCH`, `23514/WEBSITE_REQUIREMENT_BINDING_MISMATCH`, `23514/WEBSITE_REQUIREMENT_REF_MISMATCH`, `23514/WEBSITE_REQUIREMENT_COMMIT_MISMATCH`, `23514/WEBSITE_REQUIREMENT_SOURCE_MISMATCH`, `55000/WEBSITE_REQUIREMENT_SOURCE_REVIEW_REQUIRED`, `55000/WEBSITE_REQUIREMENT_VERIFICATION_MODE_UNSUPPORTED`, and `55000/WEBSITE_REQUIREMENT_WORKSPACE_NOT_READY`.

Task 4 operates entirely on the PRE_PROJECT Website root and must not require or mutate a commercial project, commercial requirements root, quote commercial state, invoice, payment, build, publish, or release authority. It adds no browser intent and no production routing: only Task 5 may expose the already-defined human lifecycle intents through the existing browser Edge boundary, while both verification RPCs remain server-only and unavailable through that boundary.

## 7. PRE_PROJECT API and Edge contracts

Planned SQL contracts (exact names to lock in RED tests before implementation):

```text
get_website_requirements_board_v1(p_quote_request_id uuid, p_website_work_context_id uuid) -> jsonb
sync_website_requirements_from_intake_v1(p_quote_request_id uuid, p_website_work_context_id uuid, p_expected_board_revision bigint, p_idempotency_key uuid) -> jsonb
start_website_requirement_v1(p_quote_request_id uuid, p_website_work_context_id uuid, p_requirement_id uuid, p_expected_revision bigint, p_idempotency_key uuid) -> jsonb
block_website_requirement_v1(p_quote_request_id uuid, p_website_work_context_id uuid, p_requirement_id uuid, p_expected_revision bigint, p_reason text, p_idempotency_key uuid) -> jsonb
complete_website_requirement_v1(p_quote_request_id uuid, p_website_work_context_id uuid, p_requirement_id uuid, p_expected_revision bigint, p_attestation jsonb, p_idempotency_key uuid) -> jsonb
reopen_website_requirement_v1(p_quote_request_id uuid, p_website_work_context_id uuid, p_requirement_id uuid, p_expected_revision bigint, p_reason text, p_idempotency_key uuid) -> jsonb
resolve_website_requirement_source_change_v1(p_quote_request_id uuid, p_website_work_context_id uuid, p_requirement_id uuid, p_expected_revision bigint, p_resolution text, p_reason text, p_idempotency_key uuid) -> jsonb
get_website_requirement_verification_authority_v1(p_quote_request_id uuid, p_website_work_context_id uuid, p_requirement_id uuid, p_expected_revision bigint) -> jsonb
record_website_requirement_verification_v1(p_quote_request_id uuid, p_website_work_context_id uuid, p_requirement_id uuid, p_expected_revision bigint, p_rule_key text, p_rule_version integer, p_result text, p_evidence_reference jsonb, p_idempotency_key uuid) -> jsonb
promote_website_concept_v1(p_quote_request_id uuid, p_website_work_context_id uuid, p_expected_context_revision bigint, p_idempotency_key uuid) -> jsonb
```

Task 5 exposes exactly these nine browser Edge actions and no generic source-resolution action:

1. `get_website_requirements_board`
2. `sync_website_requirements_from_intake`
3. `start_website_requirement`
4. `block_website_requirement`
5. `complete_website_requirement`
6. `reopen_website_requirement`
7. `accept_website_requirement_source_change`
8. `keep_existing_website_requirement_source`
9. `retire_website_requirement_source`

`resolve_website_requirement_source_change` is not a browser action. `promote_website_concept` remains absent until Task 8.

### 7.1 Exact closed Task 5 request schemas

Every request rejects missing, surplus, or incorrectly typed keys with HTTP 400 and `INVALID_REQUEST`. `quote_request_id`, `website_work_context_id`, `requirement_id` when present, and `idempotency_key` when present must be UUIDs. Integer revisions must be safe integers. The exact allowed keys are:

| Browser action | Exact request keys and constraints |
|---|---|
| `get_website_requirements_board` | `action`, `quote_request_id`, `website_work_context_id` |
| `sync_website_requirements_from_intake` | `action`, `quote_request_id`, `website_work_context_id`, `expected_board_revision`, `idempotency_key`; revision is at least 0 |
| `start_website_requirement` | `action`, `quote_request_id`, `website_work_context_id`, `requirement_id`, `expected_revision`, `idempotency_key`; revision is at least 1 |
| `block_website_requirement` | `action`, `quote_request_id`, `website_work_context_id`, `requirement_id`, `expected_revision`, `reason`, `idempotency_key`; revision is at least 1 and normalized trimmed reason is 1..500 characters |
| `complete_website_requirement` | `action`, `quote_request_id`, `website_work_context_id`, `requirement_id`, `expected_revision`, `attestation`, `idempotency_key`; revision is at least 1 and attestation is exactly `{"attestation":"<trimmed text>"}` with no surplus key and text length 1..500 |
| `reopen_website_requirement` | `action`, `quote_request_id`, `website_work_context_id`, `requirement_id`, `expected_revision`, `reason`, `idempotency_key`; revision is at least 1 and normalized trimmed reason is 1..500 characters |
| `accept_website_requirement_source_change` | `action`, `quote_request_id`, `website_work_context_id`, `requirement_id`, `expected_revision`, `reason`, `idempotency_key`; revision is at least 1 and normalized trimmed reason is 1..500 characters |
| `keep_existing_website_requirement_source` | `action`, `quote_request_id`, `website_work_context_id`, `requirement_id`, `expected_revision`, `reason`, `idempotency_key`; revision is at least 1 and normalized trimmed reason is 1..500 characters |
| `retire_website_requirement_source` | `action`, `quote_request_id`, `website_work_context_id`, `requirement_id`, `expected_revision`, `reason`, `idempotency_key`; revision is at least 1 and normalized trimmed reason is 1..500 characters |

The browser never supplies intake content, source keys or hashes, mapping data, proposed definitions, `resolution`, `source_reference`, completion mode/result/state, actor/operator/role/status, `project_id`, `requirements_board_id`, verifier identity, repository ref, commit SHA, Website workspace ID, binding revision, tokens, or credentials. The Task 5 path is only browser -> `commercial-operator-command` -> caller-JWT RPC; it performs no direct table, board, requirement, verification, Project Files, repository, GitHub, or provider write.

### 7.2 Exact Task 5 dispatch and authority

All nine actions use a Supabase client constructed from the caller JWT. Task 5 never impersonates a caller with `service_role`. The server RPC remains the sole authority for actor, role, assignment, AAL2, context/dossier binding, permitted transition, and source proposal.

| Browser action | RPC and exact fixed dispatch |
|---|---|
| `get_website_requirements_board` | `get_website_requirements_board_v1`; direct parameter mapping |
| `sync_website_requirements_from_intake` | `sync_website_requirements_from_intake_v1`; direct parameter mapping |
| `start_website_requirement` | `start_website_requirement_v1`; direct parameter mapping |
| `block_website_requirement` | `block_website_requirement_v1`; direct parameter mapping |
| `complete_website_requirement` | `complete_website_requirement_v1`; direct parameter mapping |
| `reopen_website_requirement` | `reopen_website_requirement_v1`; direct parameter mapping |
| `accept_website_requirement_source_change` | `resolve_website_requirement_source_change_v1`; fixed `p_resolution='ACCEPT_CHANGE'` |
| `keep_existing_website_requirement_source` | `resolve_website_requirement_source_change_v1`; fixed `p_resolution='KEEP_EXISTING'` |
| `retire_website_requirement_source` | `resolve_website_requirement_source_change_v1`; fixed `p_resolution='RETIRE'` |

Read requires no AAL2 and permits an active owner, admin, operations manager, or exact active assigned operator. Sync requires owner or operations manager and AAL2. Start, block, and complete require owner, operations manager, or exact active assigned operator and AAL2. Reopen and all source resolutions require owner or operations manager and AAL2. Admin remains read-only; unassigned operator, reviewer, read-only, profile-only, inactive, revoked, and every other role are denied. The handler does not reproduce this policy; the RPC validates it.

Every mutation requires an `idempotency_key`; read does not. Task 5 validates the UUID and transports it unchanged. It never creates or replaces a key. Task 6 request builders later create one `crypto.randomUUID()` per new user intent and reuse that same key for a retry of that intent. Task 5 tests use fixed synthetic UUIDs. Only the server computes and evaluates the request fingerprint.

### 7.3 Private Edge response validation

Task 5 adds private fail-closed transport validators in `commercial-operator-command/handler.ts`; Task 6 separately owns reusable frontend validators and builders. The Task 5 validators protect the Edge-to-browser boundary and are not business authority.

The board validator accepts exactly the section 5.6 root and nested DTO shapes. It requires `contract_version=1`, exact request `quote_request_id` and `website_work_context_id`, and rejects missing or unknown keys.

The sync validator accepts exactly the section 4.5 root and nested `counts` shapes. It requires `contract_version=1`, `mapping_version=1`, exact request quote/context correlation, and rejects missing or unknown keys.

The mutation validator accepts exactly the section 5.7 root shape, requires `contract_version=1`, exact request quote/context/requirement correlation, and rejects missing or unknown keys. Lifecycle response correlation is exact: start is `command='START'` with null resolution; block is `BLOCK` with null resolution; complete is `COMPLETE` with null resolution; reopen is `REOPEN` with null resolution. Source response correlation is exact: all three use `command='RESOLVE_SOURCE'`, with respectively `ACCEPT_CHANGE`, `KEEP_EXISTING`, and `RETIRE`. Any malformed shape, surplus or missing key, broken request correlation, or impossible command/resolution fails with HTTP 500 and `SERVER_RESPONSE_INVALID`; no raw response crosses the browser boundary.

Successful validated results retain the existing envelope exactly: `{"ok":true,"code":"APPLICATION_ACTION_ACCEPTED","result":<validated result>}`.

### 7.4 Closed browser-safe error mapping

Task 5 maps only the following explicit backend messages. No SQLSTATE, stack, query, provider response/body, raw backend message, or internal identifier outside a validated DTO may reach the browser.

| Browser response | Exact allowlisted backend messages |
|---|---|
| HTTP 403, `OPERATOR_NOT_AUTHORIZED` | `AAL2_REQUIRED`, `MFA_AAL2_REQUIRED`, `HUMAN_JWT_REQUIRED`, `WEBSITE_REQUIREMENTS_ACCESS_DENIED`, `WEBSITE_REQUIREMENTS_SYNC_FORBIDDEN`, `WEBSITE_REQUIREMENT_ROLE_DENIED`, `WEBSITE_REQUIREMENT_ASSIGNMENT_DENIED` |
| HTTP 404, `NOT_FOUND` | `WEBSITE_REQUIREMENT_NOT_FOUND`, `WEBSITE_REQUIREMENTS_BOARD_NOT_FOUND` |
| HTTP 409, `CONCURRENT_MODIFICATION` | `CONCURRENT_MODIFICATION` |
| HTTP 409, `IDEMPOTENCY_CONFLICT` | `WEBSITE_REQUIREMENTS_IDEMPOTENCY_CONFLICT`, `WEBSITE_REQUIREMENT_IDEMPOTENCY_CONFLICT` |
| HTTP 400, `INVALID_REQUEST` | `INVALID_WEBSITE_REQUIREMENTS_SYNC_COMMAND`, `WEBSITE_REQUIREMENTS_CONTEXT_MISMATCH`, `INVALID_WEBSITE_REQUIREMENT_COMMAND`, `WEBSITE_REQUIREMENT_BLOCK_REASON_REQUIRED`, `WEBSITE_REQUIREMENT_REOPEN_REASON_REQUIRED`, `WEBSITE_REQUIREMENT_ATTESTATION_REQUIRED`, `INVALID_WEBSITE_REQUIREMENT_SOURCE_RESOLUTION` |
| HTTP 409, `COMMAND_REJECTED` | `WEBSITE_REQUIREMENTS_INTAKE_NOT_ELIGIBLE`, `WEBSITE_REQUIREMENTS_MAPPING_UNSUPPORTED`, `WEBSITE_ACTIVE_REQUIREMENT_CONFLICT`, `WEBSITE_REQUIREMENT_SOURCE_PROPOSAL_NOT_FOUND`, `INVALID_WEBSITE_REQUIREMENT_TRANSITION`, `WEBSITE_REQUIREMENT_SOURCE_REVIEW_REQUIRED`, `WEBSITE_REQUIREMENT_SOURCE_STATE_MISMATCH`, `WEBSITE_REQUIREMENT_VERIFICATION_REQUIRED`, `DIRECT_WEBSITE_REQUIREMENT_WRITE_FORBIDDEN`, `WEBSITE_REQUIREMENT_ROOT_IMMUTABLE`, `WEBSITE_REQUIREMENT_IDENTITY_IMMUTABLE`, `STARTED_WEBSITE_REQUIREMENT_DEFINITION_IMMUTABLE` |

This table explicitly enumerates every Website Requirements message thrown by the current Task 2 sync migration and every Task 3 message from section 5.9. Any non-allowlisted backend error maps to HTTP 500 and `INTERNAL_ERROR` without raw detail.

### 7.5 Preserved boundaries

There is no browser intent for `record_website_requirement_verification_v1`, verification ingestion, or provider evidence. Task 5 imports no Task 4 verifier into the browser action path and adds no service-role verification dispatch. `project_id` remains nullable projection context and is not a request or authority for any Task 5 action. PRE_PROJECT read and mutations require no quotation, acceptance, invoice, payment, commercial release, or project. Existing commercial Requirements routes and authority remain unchanged.

## 8. Frontend and controlled views

### 8.1 Shared Website requirements contract

Task 6 is a client-only integration. It creates no migration, RPC, Edge handler/index change, Website workspace backend projection, contract-version bump, or `get_website_execution_workspace_v4`. The existing Website Execution workspace DTO remains unchanged, and its existing `requirements` placeholder is not Website Requirements authority.

For both PRE_PROJECT and OFFICIAL_PROJECT, the only Task 6 Website Requirements summary authority is the validated result of browser action `get_website_requirements_board`, routed by Task 5 to `get_website_requirements_board_v1`. After Website context resolution, the child calls:

```js
websiteRequirementsBoardRequest({
  quoteRequestId,
  websiteWorkContextId,
})
```

through the existing authorized gateway. It never uses `get_project_requirements_board`, `projectRequirementsRequest`, `projectRequirementsSummary`, or `buildProjectRequirementAction` as Website Requirements authority. Those existing commercial exports and their behavior remain unchanged for the separate commercial Project Requirements flow; they are not made polymorphic.

`assets/js/operator-project-requirements.mjs` adds exactly these Website exports:

- `websiteRequirementsBoardRequest`
- `websiteRequirementsSyncRequest`
- `websiteRequirementStartRequest`
- `websiteRequirementBlockRequest`
- `websiteRequirementCompleteRequest`
- `websiteRequirementReopenRequest`
- `websiteRequirementAcceptSourceChangeRequest`
- `websiteRequirementKeepExistingSourceRequest`
- `websiteRequirementRetireSourceRequest`
- `validateWebsiteRequirementsBoard`
- `validateWebsiteRequirementsSyncResult`
- `validateWebsiteRequirementMutationResult`
- `createWebsiteRequirementMutationIntent`

`assets/js/operator-website-execution.mjs` exports `websiteRequirementsSummary` with the exact summary contract below.

#### 8.1.1 Exact Website request builders

The nine builders return frozen requests with exactly the Task 5 request keys and actions:

| Builder | Action | Exact output keys after normalization |
|---|---|---|
| `websiteRequirementsBoardRequest` | `get_website_requirements_board` | `action`, `quote_request_id`, `website_work_context_id` |
| `websiteRequirementsSyncRequest` | `sync_website_requirements_from_intake` | `action`, `quote_request_id`, `website_work_context_id`, `expected_board_revision`, `idempotency_key` |
| `websiteRequirementStartRequest` | `start_website_requirement` | `action`, `quote_request_id`, `website_work_context_id`, `requirement_id`, `expected_revision`, `idempotency_key` |
| `websiteRequirementBlockRequest` | `block_website_requirement` | `action`, `quote_request_id`, `website_work_context_id`, `requirement_id`, `expected_revision`, `reason`, `idempotency_key` |
| `websiteRequirementCompleteRequest` | `complete_website_requirement` | `action`, `quote_request_id`, `website_work_context_id`, `requirement_id`, `expected_revision`, `attestation`, `idempotency_key` |
| `websiteRequirementReopenRequest` | `reopen_website_requirement` | `action`, `quote_request_id`, `website_work_context_id`, `requirement_id`, `expected_revision`, `reason`, `idempotency_key` |
| `websiteRequirementAcceptSourceChangeRequest` | `accept_website_requirement_source_change` | `action`, `quote_request_id`, `website_work_context_id`, `requirement_id`, `expected_revision`, `reason`, `idempotency_key` |
| `websiteRequirementKeepExistingSourceRequest` | `keep_existing_website_requirement_source` | `action`, `quote_request_id`, `website_work_context_id`, `requirement_id`, `expected_revision`, `reason`, `idempotency_key` |
| `websiteRequirementRetireSourceRequest` | `retire_website_requirement_source` | `action`, `quote_request_id`, `website_work_context_id`, `requirement_id`, `expected_revision`, `reason`, `idempotency_key` |

UUIDs, safe-integer revision bounds, and trimmed reason/attestation bounds are exactly section 7.1. Complete emits exactly `attestation: {attestation: "<trimmed 1..500>"}`. A source-change builder never accepts or emits a free `resolution` key.

No Website builder accepts or emits `project_id`, `requirements_board_id`, `actor`, `actor_id`, `operator_id`, `operator_role`, `role`, `status`, `source_reference`, a source hash, proposed definition, `completion_mode`, `verification_result`, `verified_by`, `website_workspace_id`, `binding_revision`, `repository_ref`, `commit_sha`, or `resolution`.

#### 8.1.2 Exact Website response validators

`validateWebsiteRequirementsBoard` validates exactly the section 5.6 Task 3 Website board DTO: `contract_version=1`; exact root and nested keys; valid UUIDs, revisions, enums, and hashes where present; and exact correlation to expected `quoteRequestId` and `websiteWorkContextId`. `permitted_actions` accepts only the seven server action names in section 5.5. Any missing, surplus, malformed, or unknown nested key or permitted action invalidates the complete board. The client never derives an action from status, role, assignment, AAL2, completion mode, or source-review state.

`validateWebsiteRequirementsSyncResult` accepts exactly root keys `contract_version`, `outcome`, `quote_request_id`, `website_work_context_id`, `requirements_board_id`, `board_revision`, `intake_id`, `intake_revision`, `intake_sha256`, `mapping_version`, `sync_run_id`, `replayed`, `review_required`, and `counts`. `counts` has exactly `created`, `updated`, `unchanged`, `retired`, `change_pending`, `removal_pending`, and `revived`. It requires `contract_version=1`, `mapping_version=1`, exact quote/context correlation, and rejects missing, surplus, or malformed keys.

`validateWebsiteRequirementMutationResult` accepts exactly root keys `contract_version`, `command`, `quote_request_id`, `website_work_context_id`, `requirements_board_id`, `requirement_id`, `previous_status`, `status`, `previous_source_review_state`, `source_review_state`, `resolution`, `requirement_revision`, `board_revision`, and `replayed`. It requires `contract_version=1`, exact quote/context/requirement correlation, and exact Task 5 command/resolution correlation. Missing, surplus, malformed, or impossible command/resolution data fails closed.

These frontend validators are reusable client boundaries. They do not replace or weaken the independent private Task 5 Edge-to-browser validators.

#### 8.1.3 Client idempotency intent

Define exactly:

```js
createWebsiteRequirementMutationIntent(
  builder,
  builderArguments,
  randomUUID = crypto.randomUUID,
)
```

One call represents one new user intent. It calls `randomUUID` exactly once, supplies that UUID to the supplied Task 6 mutation builder, and returns exactly the immutable object `{idempotencyKey, request}`. The request is frozen; its key is never replaced or recomputed. Repeating the same intent later reuses the exact same intent object, request, and key. A new intent creates a new object and UUID.

Task 6 only provides and tests this helper; it executes no Website Requirements mutation. Task 7 later owns the active pending-intent reference and mutation interaction. Task 7 may retain the same intent only after network failure or timeout without a definitive response, HTTP 500 `INTERNAL_ERROR`, or HTTP 500 `SERVER_RESPONSE_INVALID`. It discards the intent after an authoritative success, explicit user cancel, changed action, changed requirement target, changed reason, changed attestation, HTTP 400 `INVALID_REQUEST`, HTTP 403 `OPERATOR_NOT_AUTHORIZED`, HTTP 404 `NOT_FOUND`, HTTP 409 `CONCURRENT_MODIFICATION`, HTTP 409 `IDEMPOTENCY_CONFLICT`, or HTTP 409 `COMMAND_REJECTED`. A later submit then creates a new intent and UUID.

Client intent identity is not a server fingerprint, security authority, or idempotency-fingerprint authority. The server remains the sole fingerprint authority.

#### 8.1.4 Exact Website summary

`websiteRequirementsSummary` accepts only a projection returned by `validateWebsiteRequirementsBoard`; it never accepts the raw Website workspace `requirements` placeholder or a commercial Project Requirements DTO. It returns a frozen object with exactly `state`, `requirements_board_id`, `board_revision`, `completed`, `total`, `open`, `blocked`, and `review_required`. The only DTO states are `READY`, `NO_BOARD`, `INTAKE_NOT_ELIGIBLE`, and `REVIEW_REQUIRED`; there is no persisted fifth state and specifically no `BLOCKED` summary state.

| State | Board ID/revision | Counts | Review flag | Sole selection authority |
|---|---|---|---|---|
| `NO_BOARD` | both null | all four counts `0` | `false` | validated server `empty_state='NO_BOARD'` |
| `INTAKE_NOT_ELIGIBLE` | both null | all four counts null | `false` | validated server `empty_state='INTAKE_NOT_ELIGIBLE'` |
| `READY` | `board.requirements_board_id`, `board.revision` | copy server progress | `false` | validated board not requiring review |
| `REVIEW_REQUIRED` | `board.requirements_board_id`, `board.revision` | copy server progress | `true` | validated `board.sync_state='REVIEW_REQUIRED'` |

For `READY` and `REVIEW_REQUIRED`, `total`, `completed`, `open`, and `blocked` copy `progress.required_total`, `progress.required_completed`, `progress.required_open`, and `progress.required_blocked`. They are non-negative safe integers and must satisfy `completed + open + blocked = total`. This is a validator consistency check. Display uses these server values directly and never scans items as progress authority. A positive blocked count is displayed while state remains `READY` or `REVIEW_REQUIRED` according to server sync state.

#### 8.1.5 Isolated summary presentation

The Website child summary presentation has exactly `LOADING`, `NO_BOARD`, `INTAKE_NOT_ELIGIBLE`, `READY`, `REVIEW_REQUIRED`, `ERROR`, and `STALE_PRESENTATION`. `STALE_PRESENTATION` is UI-only and never a summary DTO state.

- `LOADING`: before the first valid response, show loading without old commercial Requirements data.
- `NO_BOARD`: heading `WEBSITE REQUIREMENTS`; copy `Nog geen Website Requirements-board beschikbaar.`
- `INTAKE_NOT_ELIGIBLE`: heading `WEBSITE REQUIREMENTS`; copy `Website Requirements zijn nog niet beschikbaar voor deze intake.`
- `READY`: show server `completed / total`, `open`, and `blocked`.
- `REVIEW_REQUIRED`: show the same server counts plus `Wijzigingen uit de intake moeten eerst beoordeeld worden.`
- `ERROR`: when the first Requirements read fails, show `Requirements konden niet veilig worden geladen.` without raw backend error.
- `STALE_PRESENTATION`: when a background refresh fails after a valid summary, retain that exact summary and show `Requirements konden niet worden vernieuwd. Laatst geldige gegevens blijven zichtbaar.` Counters/state are not changed and no action is newly enabled.

A Requirements-only read failure never moves the full Website child to global error. Repository links, the Website workspace, and Project Files remain usable. Rendering uses text-only DOM APIs and does not mount the full board over or reduce the existing Project Files working surface.

Task 6 renders a compact, always-disabled button labelled `Requirements openen` with adjacent copy `De volledige Website Requirements-werkruimte wordt in de volgende stap geactiveerd.` It performs no `requestOpen`, does not call `requirementsBoardSlot`, creates no `req-<quote_request_id>` singleton route, and opens no child/window. Task 7 owns that behavior.

Task 6 starts no AAL2/MFA flow and executes no sync, start, block, complete, reopen, accept, keep, or retire operation. It adds no verification ingestion UI, AUTO PASS button, manual trusted verifier, evidence upload authority, or `record_website_requirement_verification` route. It performs no Project Files, repository, or GitHub write.

### 8.2 Full Requirements child

Task 7 introduces exactly two closed Requirements slot families and no others:

| Mode | Exact slot | Phase | Exclusive authority |
|---|---|---|---|
| `WEBSITE` | `req-<quote_request_id>` | PRE_PROJECT and OFFICIAL_PROJECT | `get_website_requirements_board` and the Task 5 Website Requirements browser actions |
| `COMMERCIAL_PROJECT` | `project-req-<quote_request_id>` | OFFICIAL_PROJECT only | Existing `get_project_requirements_board` and existing commercial Project Requirements mutations |

`project-req-` plus a canonical UUID is exactly 48 characters and fits the existing slot-key maximum; the generic slot-length contract is unchanged. `requirementsBoardSlot` and `quoteRequestIdFromRequirementsBoardSlot` remain exclusively Website helpers for `req-*`. Task 7 adds `projectRequirementsBoardSlot` and `quoteRequestIdFromProjectRequirementsBoardSlot` exclusively for `project-req-*`. `requirementsInvalidationMatches` remains the exact-quote Website matcher; Task 7 adds `projectRequirementsInvalidationMatches` for exact-quote commercial matching. Neither matcher accepts the other family or another dossier.

`operator-project-requirements-child.mjs` remains the only full Requirements child implementation. Its mode is selected solely by the validated slot prefix. It never selects authority from role, project ID, lifecycle status, completion mode, URL query data, opener/window messages, or browser state. The module registry performs only closed routing and must test prefixes in this exact shadow-safe order: `project-req-`, `req-`, `website-`, `project-`. Both Requirements prefixes mount `initializeOperatorProjectRequirements` and receive `requireAal2`. The registry determines no dossier, project, role, assignment, AAL2, Website context, or Requirement authority.

For every authoritative refresh, the child parses the slot, requests `get_application_detail` and dossier substance, derives the server-backed context, performs the mode-specific board read, validates the exact response, and only then renders. Website mode binds exact `quoteRequestId`, `websiteWorkContextId`, nullable `conceptId`/`projectId`, mode, dossier reference, and customer. Commercial mode requires server-derived OFFICIAL_PROJECT, project ID, quote ID, and dossier binding; a PRE_PROJECT `project-req-*` slot fails closed. Website mode always uses the Website context board in both phases and never switches to or copies the commercial board. Commercial mode preserves existing `projectRequirementsRequest`, `validateProjectRequirementsBoard`, `projectRequirementsView`, existing summary behavior where used, `buildProjectRequirementAction`, filters, cards, actions, mutations, and DTO authority; only its slot namespace changes.

The commercial Project Workspace open action changes to `projectRequirementsBoardSlot(currentContext.quoteRequestId)`. Website Execution activates its Task 6 `Requirements openen` button whenever a valid Website context exists and removes or hides the Task 6 next-step copy. Its click calls only `options.requestOpen?.("dossiers", requirementsBoardSlot(currentSnapshot.context.quoteRequestId))`; it uses no direct `window.open`, URL construction, or project ID.

The integrated Website surface remains the compact Task 6 summary. There is no second full-board implementation and no full board mounted over Website Execution or Project Files. The one full Website board is the managed `dossiers:req-<quote_request_id>` child, usable through the existing workspace/window infrastructure. The commercial singleton is separately `dossiers:project-req-<quote_request_id>`; therefore Website and commercial children never share identity or authority.

Website mode renders with DOM text APIs only and uses validated server order without drag/drop or client mutation of `sort_order`/`item_number`. Presentation filters are exactly `ALL`, `ACTIVE`, `OPEN`, and `COMPLETED`: ALL preserves all validated items; ACTIVE means `status=ACTIVE`; OPEN means `PENDING`, `ACTIVE`, or `BLOCKED`; COMPLETED means `status=COMPLETED`. Filtering is presentation only. Cards expose only item number, title, description, category, safe source/provenance fields, linked page/module, status, completion mode, required, verification result, blocked reason, revision, source-review state, and permitted actions. They never expose raw intake, proposed definitions/hashes, or a client-computed diff. `CHANGE_PENDING` shows `Nieuwe intake-informatie wacht op beoordeling.`; `REMOVAL_PENDING` shows `Deze vereiste komt niet meer voor in de actuele intake en wacht op beoordeling.`

Website action labels are exact:

| Server-projected action | Label |
|---|---|
| `start_website_requirement` | `Start` |
| `block_website_requirement` | `Blokkeren` |
| `complete_website_requirement` | `Afronden` |
| `reopen_website_requirement` | `Heropenen` |
| `accept_website_requirement_source_change` | `Wijziging aanvaarden` |
| `keep_existing_website_requirement_source` | `Bestaande vereiste behouden` |
| `retire_website_requirement_source` | `Vereiste uitfaseren` |

Buttons arise only from validated `permitted_actions`; no client derivation may use status, role, assignment, AAL2, completion mode, or source-review state. An unknown action invalidates the entire board response.

Website mode has one convenience sync control labelled `Intake synchroniseren`. It is visible for browser-presented owner and operations-manager identities in `NO_BOARD`, `READY`, and `REVIEW_REQUIRED`, and hidden or disabled in `INTAKE_NOT_ELIGIBLE`, `LOADING`, `ERROR`, or mutation `PENDING`. This visibility is not security authority. The server remains final authority. The request uses exactly `board?.revision ?? 0`. A click creates one new immutable Task 6 intent, performs `requireAal2`, executes the Task 5 request, validates with `validateWebsiteRequirementsSyncResult`, treats a validated replay as authoritative success, discards the intent, refetches and validates the Website board, renders only the fresh projection, and publishes existing `dossiers` invalidation.

At most one Website Requirements mutation intent may be pending per child. START is confirmed by its direct click and has no free input. BLOCK, COMPLETE, REOPEN, ACCEPT, KEEP, and RETIRE use inline forms, never `window.prompt`. Their exact textarea labels are respectively `Reden blokkering`, `Uitvoeringsbevestiging`, `Reden heropening`, `Reden wijziging aanvaarden`, `Reden bestaande vereiste behouden`, and `Reden vereiste uitfaseren`. Every value is trimmed and bounded to 1..500 characters. COMPLETE delegates the exact `{attestation: {attestation: "<trimmed>"}}` shape to its Task 6 builder. Source actions have no free resolution input. Form cancel performs no mutation, creates no pre-submit intent, closes the form, and returns focus to the originating action.

An intent is created only on a valid confirmed form submit or direct START/SYNC click through `createWebsiteRequirementMutationIntent`. Its immutable context snapshot contains the slot, quote ID, Website context ID, optional requirement ID, frozen request, and idempotency key. Every Website mutation attempt, including retry of the same intent, calls `options.requireAal2()` before gateway execution. Missing or rejected AAL2 makes no gateway call and shows a safe authorization message. Frontend AAL2 is only a UX gate; the server remains final authority for AAL2, role, assignment, context, revision, transition, and source resolution.

The same intent object/request/key is retained only for a network failure or timeout without a definitive HTTP response, HTTP 500 `INTERNAL_ERROR`, or HTTP 500 `SERVER_RESPONSE_INVALID`. Show `Uitkomst niet bevestigd. Opnieuw proberen gebruikt dezelfde veilige aanvraag.` and a button labelled `Opnieuw proberen`; retry reruns AAL2 and reuses the same frozen request and key. Discard the intent after validated success, explicit cancel, slot/context/action/target/reason/attestation change, or definitive HTTP 400 `INVALID_REQUEST`, 403 `OPERATOR_NOT_AUTHORIZED`, 404 `NOT_FOUND`, 409 `CONCURRENT_MODIFICATION`, 409 `IDEMPOTENCY_CONFLICT`, or 409 `COMMAND_REJECTED`. A later submit creates a new intent and UUID.

Definitive safe messages are exact: `Aanvraag is ongeldig. Controleer de invoer.`, `Je hebt geen toestemming voor deze actie.`, `De vereiste is niet meer beschikbaar.`, `De gegevens zijn gewijzigd. Het bord wordt vernieuwd.`, `Deze aanvraag kon niet veilig worden herhaald. Het bord wordt vernieuwd.`, and `Deze actie is niet meer toegestaan. Het bord wordt vernieuwd.` in the error order above. The three 409 classes refetch authoritatively. Raw error messages, SQLSTATE, backend bodies, stacks, provider details, and internal queries are never rendered.

After validated success, discard the pending intent, clear the action form, refetch the authoritative Website board, render only the validated fresh board, and publish existing `dossiers` invalidation. There is no optimistic UI. If success is authoritative but refetch fails, retain the last validated pre-mutation snapshot as stale presentation, show `Actie uitgevoerd, maar het bord kon niet veilig worden vernieuwd.`, and still publish invalidation without inventing status or counts.

Root read states are exactly `LOADING`, `NO_BOARD`, `INTAKE_NOT_ELIGIBLE`, `READY`, `REVIEW_REQUIRED`, `ERROR`, and `STALE`. Transient mutation states are exactly `IDLE`, `FORM_OPEN`, `PENDING`, `AMBIGUOUS_RETRY`, and `DEFINITIVE_ERROR`; they never replace board authority. NO_BOARD renders no cards/item actions and exposes sync only to the convenience roles above. INTAKE_NOT_ELIGIBLE is informative only and exposes no cards, sync, or mutations. REVIEW_REQUIRED shows `Wijzigingen uit de intake moeten eerst beoordeeld worden.`

The existing generation guard discards stale reads. Before applying a mutation result, the child verifies it is not disposed and that slot, server-derived context binding, and workspace epoch remain current. A result for an old context never updates current UI and its pending intent never migrates; a validated success may still publish general `dossiers` invalidation. Slot/context switch discards the intent, clears forms and sensitive board data, and re-resolves authority. Same-record background refresh may retain the last complete validated snapshot. Cross-dossier/context mismatch, logout, revoke, authorization loss, lease loss, binding mismatch, or child disposal clears sensitive state immediately. Context mismatch renders a safe denied/error state and need not itself close the window.

After successful full-child mount, focus the Requirements heading. Opening an inline form focuses its first textarea; cancel or Escape before submit closes it and returns focus to the trigger. Escape during PENDING does not cancel the request. Successful authoritative refetch focuses the heading. Status and mutation messages use the existing `aria-live` status region and are never color-only. No new animation may ignore `prefers-reduced-motion`.

Responsive behavior reuses only the existing 900px and 540px CSS breakpoints, with no JavaScript viewport authority. Above 900px the existing multi-column card layout may remain. At or below 900px cards/forms are one column with no horizontal content overflow. At or below 540px action controls/form buttons may stack full width. Acceptance viewports are 1440x900, 900x700, and 390x844. Requirements uses normal document/page scrolling and no fixed-height nested Requirements scroller. Task 7 defines no new popup minimum; managed-window infrastructure remains owner.

### 8.3 Detachable behavior

- Website full-board open follows exactly Website Execution `Requirements openen` -> existing `requestOpen` -> `module=dossiers` -> `slot=req-<quote_request_id>` -> existing workspace master -> managed Requirements child. No new route or protocol exists.
- Use only existing `managedChildUrl`, workspace master, operator window host, `OPEN_REQUEST`, `FOCUS_REQUEST`, `INVALIDATE`, `HEARTBEAT`, `LOCK`, `SHUTDOWN`, workspace epoch, and lease. Add no BroadcastChannel and perform no direct `window.open` in Requirements code.
- The exact Website singleton is `dossiers:req-<quote_request_id>`. A duplicate open creates no second child; the existing window receives `focus()` and `FOCUS_REQUEST`. The commercial singleton is independently `dossiers:project-req-<quote_request_id>`.
- Integrated summary and managed full child use the same Website read RPC and persisted board ID/revision. No second Website workspace or independent Requirements cache is created.
- URL/slot contains only the non-secret dossier UUID already covered by the managed-window contract. JWT, context ID, workspace ID, repository external ID, installation ID, token, capability, actor, role, assignment, AAL2, board, requirement, or revision never enters the URL or navigation event.
- The child independently re-resolves context on every authoritative refresh; opener/window messages are navigation hints only. Existing lease, epoch, sequence, revoke, duplicate-focus, invalidation, lock, and shutdown protocols remain unchanged and authoritative.
- Existing logout/SHUTDOWN closes or clears the child. Revoke or lease loss locks and clears sensitive content; no stale board remains visible.

## 9. PRE_PROJECT to OFFICIAL_PROJECT continuity

Task 8 promotes exactly one existing Website work context from `PRE_PROJECT` to `OFFICIAL_PROJECT`. It creates no new Website context, Website workspace, Website Requirements board, requirement item, verification history, repository binding, Project Files state, or quote identity. Promotion is not a commercial release and performs no invoice, payment, commercial release, publication, deployment, repository write, Project Files write, GitHub write, Finance mutation, or mail/provider side effect.

### 9.1 Role, caller, and server-derived project authority

Promotion is caller-JWT-only and requires an active `owner` at AAL2. Admin, operations manager, assigned operator, and every other role are denied. Frontend MFA is only a UX gate; the RPC remains final authority. Task 8 uses no service role.

The browser never supplies `project_id`. The Edge layer never trusts browser project authority. The server resolves exactly one canonical eligible `commercial_projects.project_id` through the existing accepted quotation, issuance, approval, and acceptance lineage for the same `quote_request_id`. The canonical project must exist; the issuance belongs to that project and has status `ISSUED`; approval and acceptance belong to the same quote request and Website dossier; and no cross-dossier binding may occur. Payment, invoice, project release, and commercial release are not prerequisites. Zero eligible projects raises `WEBSITE_PROMOTION_PROJECT_NOT_FOUND`; more than one raises `WEBSITE_PROMOTION_PROJECT_AMBIGUOUS`. Arbitrary selection is forbidden.

### 9.2 Exact browser action, request, and RPC

The exact browser action is `promote_website_concept`. Its request has exactly these root keys and no others:

```text
action
quote_request_id
website_work_context_id
expected_context_revision
idempotency_key
```

`action` is exactly `promote_website_concept`; both identities and the idempotency key are UUIDs; `expected_context_revision` is a safe integer at least 1. Missing, surplus, or malformed keys fail closed. Forbidden browser authority includes at minimum `project_id`, `concept_id`, `actor`, `actor_id`, `role`, `operator_id`, `customer_id`, `requirements_board_id`, `website_workspace_id`, `repository_ref`, `commit_sha`, `commercially_released`, `payment_state`, `quotation_id`, and `acceptance_id`.

The exact RPC is:

```text
public.promote_website_concept_v1(
  p_quote_request_id uuid,
  p_website_work_context_id uuid,
  p_expected_context_revision bigint,
  p_idempotency_key uuid
) returns jsonb
```

There is no `p_project_id`. The only browser concurrency authority is `expected_context_revision`; the browser sends no board revision, workspace binding revision, concept revision, or project revision.

### 9.3 Exact response contract

The RPC and Edge validator use exactly these response root keys:

```text
contract_version
outcome
quote_request_id
website_work_context_id
concept_id
project_id
previous_phase
phase
previous_context_revision
context_revision
website_workspace_id
workspace_binding_revision
requirements_board_id
requirements_board_revision
promotion_event_id
promoted_at
replayed
```

`contract_version=1`, `outcome='PROMOTED'`, `previous_phase='PRE_PROJECT'`, and `phase='OFFICIAL_PROJECT'`. Quote and context IDs exactly match the request. `previous_context_revision` equals the requested expected revision and `context_revision=previous_context_revision+1`. Concept, project, and promotion event IDs are UUIDs; `promoted_at` is a valid timestamp; `replayed` is boolean.

`website_workspace_id` and `workspace_binding_revision` are either both null or both non-null. When non-null, the workspace ID is a UUID and binding revision is a safe integer at least 1. `requirements_board_id` and `requirements_board_revision` follow the same paired-nullability rule; when non-null, the board ID is a UUID and revision is a safe integer at least 1. Missing, surplus, malformed, or request-uncorrelated response data fails closed.

### 9.4 Promotion command ledger and idempotency

Task 8 creates `public.website_concept_promotion_commands` as the server-only idempotency ledger with at least exactly these columns:

```text
idempotency_key uuid primary key
request_fingerprint_sha256 text not null
actor_id uuid not null
quote_request_id uuid not null
website_work_context_id uuid not null
expected_context_revision bigint not null
status text not null
response_payload jsonb null
promotion_event_id uuid null
created_at timestamptz not null
completed_at timestamptz null
```

Allowed status values are exactly `PENDING` and `COMPLETED`. No browser/runtime role receives direct insert, update, delete, or read authority; only the reviewed server/RPC path owns the ledger.

The server computes the canonical fingerprint over exactly contract version 1, action `promote_website_concept`, server-derived `actor_id`, `quote_request_id`, `website_work_context_id`, and `expected_context_revision`. The browser never computes it. The same idempotency key and same fingerprint after successful promotion performs no write and creates no audit event; it returns the same logical result with `replayed=true`. Initial success returns `replayed=false`. The same key with another fingerprint raises `WEBSITE_CONCEPT_PROMOTION_IDEMPOTENCY_CONFLICT`. A new key after the context is already `OFFICIAL_PROJECT` is not replay: it raises `WEBSITE_CONCEPT_ALREADY_PROMOTED`, creates no audit row, and performs no write.

### 9.5 Immutable promotion audit

Task 8 creates append-only `public.website_work_context_promotion_events` with at least exactly these columns:

```text
promotion_event_id uuid primary key
event_type text not null
quote_request_id uuid not null
website_work_context_id uuid not null
concept_id uuid not null
project_id uuid not null
actor_id uuid not null
previous_phase text not null
phase text not null
previous_context_revision bigint not null
context_revision bigint not null
created_at timestamptz not null
```

`event_type` is exactly `WEBSITE_WORK_CONTEXT_PROMOTED`, `previous_phase='PRE_PROJECT'`, and `phase='OFFICIAL_PROJECT'`. One successful initial promotion creates exactly one event. Same-key replay and every failure create none. Browser/runtime roles cannot update or delete history.

### 9.6 Exact continuity and mutations

Promotion preserves exactly the same `quote_request_id`, `website_work_context_id`, optional `website_workspace_id`, optional `requirements_board_id`, every `requirement_id`, all sync-history identities, existing requirement-event identities, verification/evidence identities, repository-binding identities, and Project Files identities/state. It creates no copy, replacement, merge, or synthesized completion.

The existing Website concept changes only its relevant promotion fields: `concept_status` uses the existing promoted schema value, `promoted_project_id` becomes the server-derived project, `promoted_at` changes, `revision` increments by one, and `updated_at` changes. No concept is created.

The existing Website work context changes exactly as follows: `phase` changes from `PRE_PROJECT` to `OFFICIAL_PROJECT`; `project_id` changes from null to the server-derived project; `revision` increments by one; and `updated_at` changes. Its ID and quote binding remain unchanged.

If a Website execution workspace exists, only compatibility `project_id` changes from null to the official project; `updated_at` may change. Its ID, `binding_revision`, `workspace_state`, repository owner/name and full repository identity, preview branch/URL, last commit SHA, repository provenance, and Project Files provenance/state remain unchanged. If no workspace exists, promotion may still succeed and creates none.

If a Website Requirements board exists, its ID, revision, state, rows, progress, and history remain unchanged. Every requirement keeps its ID, revision, status, active state, `source_review_state`, and evidence. Permitted actions are reprojected after refresh and are not copied or persisted by promotion. If no board exists, promotion may still succeed and creates none.

Existing verification rows, evidence hashes, `observed_at`, repository evidence, workspace/binding evidence, and immutable history remain unchanged. Promotion does not invalidate evidence, require reverification, create a verification PASS, bypass the trusted verifier, or ingest verification.

Website Requirements remain the `req-<quote_request_id>` authority. Commercial Project Requirements remain the independent `project-req-<quote_request_id>` authority. Promotion never creates a commercial board from the Website board and never converts or merges either authority.

### 9.7 Concurrency, transaction, and lock order

`expected_context_revision` must exactly equal the locked `website_work_contexts.revision` while phase is `PRE_PROJECT`; a mismatch raises `CONCURRENT_MODIFICATION`. After successful caller authentication, owner/AAL2 checks, and closed input validation, the exact transaction order is:

1. Resolve canonical idempotency ledger identity and fingerprint.
2. Handle same-key replay or fingerprint conflict.
3. Lock the exact `website_work_contexts` row `FOR UPDATE`.
4. Lock the exact `website_concepts` row `FOR UPDATE`.
5. Resolve and lock exactly one canonical eligible `commercial_projects` row `FOR UPDATE`.
6. Validate accepted quotation, issuance, approval, acceptance, and dossier lineage.
7. Lock the existing `website_execution_workspaces` row `FOR UPDATE` when present.
8. Lock the existing `website_requirements_boards` row `FOR UPDATE` when present.
9. Validate `PRE_PROJECT`, null project binding, exact context/dossier identity, and expected context revision.
10. Update the Website concept.
11. Update the Website work context.
12. Bind existing workspace `project_id` when a workspace exists.
13. Insert exactly one `WEBSITE_WORK_CONTEXT_PROMOTED` event.
14. Construct the exact response.
15. Mark the command ledger `COMPLETED` and store the response/event identity.
16. Return.

All work occurs in one SQL transaction. Promotion is atomic; partial promotion is impossible. Failure rolls back concept, context, workspace, event, and completed-command state. There is no completed command row or promotion event after failure.

### 9.8 Exact backend errors and safe Edge mapping

The Edge layer exposes only these mappings:

| HTTP/code | Exact backend messages |
|---|---|
| 403, `OPERATOR_NOT_AUTHORIZED` | `AAL2_REQUIRED`, `WEBSITE_CONCEPT_PROMOTION_ACCESS_DENIED`, `WEBSITE_CONCEPT_PROMOTION_ROLE_DENIED` |
| 404, `NOT_FOUND` | `WEBSITE_WORK_CONTEXT_NOT_FOUND`, `WEBSITE_CONCEPT_NOT_FOUND`, `WEBSITE_PROMOTION_PROJECT_NOT_FOUND` |
| 409, `CONCURRENT_MODIFICATION` | `CONCURRENT_MODIFICATION` |
| 409, `IDEMPOTENCY_CONFLICT` | `WEBSITE_CONCEPT_PROMOTION_IDEMPOTENCY_CONFLICT` |
| 400, `INVALID_REQUEST` | `INVALID_WEBSITE_CONCEPT_PROMOTION`, `INVALID_WEBSITE_CONCEPT_PROMOTION_ARGUMENT` |
| 409, `COMMAND_REJECTED` | `WEBSITE_CONCEPT_NOT_PRE_PROJECT`, `WEBSITE_CONCEPT_ALREADY_PROMOTED`, `WEBSITE_PROMOTION_PROJECT_AMBIGUOUS`, `WEBSITE_PROMOTION_LINEAGE_MISMATCH`, `WEBSITE_PROMOTION_PROJECT_NOT_ELIGIBLE`, `WEBSITE_PROMOTION_CONTEXT_MISMATCH`, `WEBSITE_PROMOTION_WORKSPACE_MISMATCH` |

Every other backend error maps to HTTP 500 `INTERNAL_ERROR`. No SQLSTATE, query, stack, raw backend body/message, provider detail, or secret crosses the browser boundary.

### 9.9 Edge parser, validator, and caller-JWT dispatch

Task 8 modifies both `commercial-operator-command/handler.ts` and `index.ts`. The handler adds the closed `promote_website_concept` type/parser, exact-key rejection, private exact response validator, and safe error mapping. The index adds caller-JWT dispatch to `promote_website_concept_v1` with exactly `p_quote_request_id`, `p_website_work_context_id`, `p_expected_context_revision`, and `p_idempotency_key`. It sends no `p_project_id` and uses no service role.

### 9.10 Frontend builders and immutable intent

`assets/js/operator-website-execution.mjs` adds exactly these exports:

- `websiteConceptPromotionRequest`
- `validateWebsiteConceptPromotionResult`
- `createWebsiteConceptPromotionIntent`

`websiteConceptPromotionRequest` accepts `quoteRequestId`, `websiteWorkContextId`, `expectedContextRevision`, and `idempotencyKey`, and returns the exact frozen section 9.2 browser request without `project_id`. `validateWebsiteConceptPromotionResult` validates the exact section 9.3 shape, paired nullability, invariants, and request correlation; unknown or missing keys fail closed.

`createWebsiteConceptPromotionIntent(context, randomUUID = crypto.randomUUID)` calls `randomUUID` exactly once and returns a frozen object with exactly `idempotencyKey`, `request`, `quoteRequestId`, `websiteWorkContextId`, and `expectedContextRevision`. Those values and the request are immutable. Retrying the same returned intent reuses the same request and key. A newly confirmed intent receives a new UUID.

### 9.11 Promotion UI and AAL2 flow

Promotion UI exists only in the Website Execution Workspace in `assets/js/operator-website-execution-child.mjs`; the Website Requirements child never initiates promotion. The exact button label is `Naar officieel project`. Convenience visibility requires browser identity role `owner` and the current validated context mode `PRE_PROJECT`; it is hidden for non-owner and `OFFICIAL_PROJECT`. Browser visibility is not authority. The button is disabled during `PENDING` or active ambiguous retry execution, and parallel promotion intents are forbidden.

Exact UI copy is:

- Confirmation: `Website-context promoveren naar het officiële project? De bestaande werkruimte, Website Requirements, historie en verificaties blijven behouden. Dit maakt geen factuur, betaling, publicatie of deployment aan.`
- Pending: `Website-context wordt gekoppeld aan het officiële project.`
- Success: `Website-context is gekoppeld aan het officiële project.`
- Generic failure: `Promotie kon niet veilig worden uitgevoerd.`
- Ambiguous result: `Uitkomst niet bevestigd. Opnieuw proberen gebruikt dezelfde veilige promotieaanvraag.`
- Retry button: `Opnieuw proberen`

Every first attempt and every retry calls `options.requireAal2()` before gateway execution. If it is missing or rejects, make no gateway call, discard an unexecuted new intent, and show a safe authorization message. After AAL2 and before gateway execution, recheck that the child is not disposed and the current server-derived snapshot still has the same quote ID, same Website work-context ID, `mode='PRE_PROJECT'`, and the same context revision as the intent. Otherwise send no request.

### 9.12 Retry, definitive errors, and authoritative refresh

Retain the same intent only for network failure without a definitive response, timeout without a definitive response, HTTP 500 `INTERNAL_ERROR`, or HTTP 500 `SERVER_RESPONSE_INVALID`. Discard it after validated success, explicit cancellation before send, context/slot switch, HTTP 400 `INVALID_REQUEST`, HTTP 403 `OPERATOR_NOT_AUTHORIZED`, HTTP 404 `NOT_FOUND`, HTTP 409 `CONCURRENT_MODIFICATION`, HTTP 409 `IDEMPOTENCY_CONFLICT`, or HTTP 409 `COMMAND_REJECTED`.

Exact frontend safe messages are:

| Browser result | Exact copy |
|---|---|
| 400 `INVALID_REQUEST` | `Aanvraag is ongeldig. Vernieuw de Website Workspace en probeer opnieuw.` |
| 403 `OPERATOR_NOT_AUTHORIZED` | `Je hebt geen toestemming om deze Website-context te promoveren.` |
| 404 `NOT_FOUND` | `Het officiële project of de Website-context is niet meer beschikbaar.` |
| 409 `CONCURRENT_MODIFICATION` | `De Website-context is gewijzigd. De werkruimte wordt vernieuwd.` |
| 409 `IDEMPOTENCY_CONFLICT` | `Deze promotieaanvraag kon niet veilig worden herhaald. De werkruimte wordt vernieuwd.` |
| 409 `COMMAND_REJECTED` | `Promotie is niet meer toegestaan. De werkruimte wordt vernieuwd.` |

`NOT_FOUND`, `CONCURRENT_MODIFICATION`, `IDEMPOTENCY_CONFLICT`, and `COMMAND_REJECTED` discard the intent and trigger an authoritative Website Workspace refresh.

After validated success and a current-context check: discard the promotion intent; show the exact success copy; authoritatively refresh Website Execution; re-resolve application detail, context, and workspace; require `mode='OFFICIAL_PROJECT'` and the same `website_work_context_id`; then publish the existing `dossiers` invalidation. If authoritative success occurred but local refresh fails, do not restore PRE_PROJECT, publish invalidation, and show exactly `Promotie uitgevoerd, maar de Website Workspace kon niet veilig worden vernieuwd.` The next valid refresh determines server state.

### 9.13 Slot, stale-response, logout, and revoke continuity

The Website Execution slot remains `website-<quote_request_id>` and Website Requirements remains `req-<quote_request_id>`. No child recreation is required. The existing Task 7 Requirements child performs no promotion; existing `dossiers` invalidation, auto-refresh, and server context re-resolution refresh the same singleton and same board in place. Task 8 opens no Project Workspace automatically; generic invalidation may refresh an already open dossier child.

The immutable promotion intent binds `quoteRequestId`, `websiteWorkContextId`, `expectedContextRevision`, request, and idempotency key. If the child is disposed, workspace is revoked/locked, slot/context changes, or server-derived context mismatches before response application, the result does not update the current UI and the pending intent is not transferred. A validated success may still publish generic `dossiers` invalidation.

Logout and revoke reuse existing workspace `LOCK` and `SHUTDOWN`; Task 8 adds no custom promotion messaging protocol and retains no sensitive promotion state after revoke.

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
- `supabase/functions/commercial-operator-command/index.ts`
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
- Prove sections 4.1-4.6 exactly: every fixed and dynamic source key, exhaustive feature handling, exact titles/categories/operator mode, canonical normalization/hashes/order, excluded commercial fields, exact result and proposed-change JSON, exact replay/conflict, every resync action, concurrency locks, eligibility, actor/AAL2 policy, stale revision, and wrong-context substitution. Any unknown feature must prove `WEBSITE_REQUIREMENTS_MAPPING_UNSUPPORTED`.

**IMPLEMENTATION**
- Implement mapping version 1 and atomic diff rules exactly as sections 4.1-4.6 define. Reuse every named Task 1 field, add only the specified `proposed_changes` sync-run field, and accept only the four documented command parameters. The server reads intake directly; browser payload never supplies answers or mapping authority.

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
- Exact section 7 `get_website_requirements_board_v1`, start/block/complete/reopen/source-resolution RPCs; shared private transition/readiness/action projectors; supporting `website_requirement_command_ledger` from section 5.7.

**RED TEST FIRST**
- Assert sections 3.2 and 5 exactly: caller JWT; exact read/mutation roles and assignment; read without AAL2; every mutation with AAL2; exact context/quote/item binding; transition and source-resolution matrices; reason and attestation validation; one ACTIVE item; expected requirement revision semantics; lock compatibility; requirement/board increments with unchanged context revision; ledger fingerprint/replay/conflict; exact DTO and mutation result keys; permitted actions; board review clearing; progress/readiness priority; event types/metadata; errors; evidence invalidation; immutable history; and PRE_PROJECT without commercial dependencies.

**IMPLEMENTATION**
- Implement sections 5 and 7 without deviation: one locked transition core, closed projection, exact source proposal resolution, command ledger, immutable events, and database-level one-ACTIVE enforcement. Manual completion is allowed only for `OPERATOR`, or `HYBRID` with a current PASS. Task 3 does not ingest verification, create AUTO/EXTERNAL PASS, read repository/test/provider evidence, or perform automatic completion.

**GREEN TESTS**
- `npx supabase test db supabase/tests/website_requirements_lifecycle_v1.sql`
- `npx supabase test db supabase/tests/project_requirements_board_v1.sql`

**SECURITY / SCOPE GATE**
- Denied callers receive no board metadata; no RPC accepts or derives authority from `project_id`; audit metadata uses the exact safe shape and is secret-key checked. Require `TASK3_CONTRACT_UNAMBIGUOUS=JA`, `LIFECYCLE_TRANSITIONS_FULLY_EXPLICIT=JA`, `SOURCE_RESOLUTION_TRANSITIONS_FULLY_EXPLICIT=JA`, `ROLE_MODEL_FULLY_EXPLICIT=JA`, `REVISION_MODEL_FULLY_EXPLICIT=JA`, `LOCK_MODEL_FULLY_EXPLICIT=JA`, `IDEMPOTENCY_MODEL_FULLY_EXPLICIT=JA`, `EVENT_MODEL_FULLY_EXPLICIT=JA`, `RESULT_JSON_FULLY_EXPLICIT=JA`, `BOARD_DTO_FULLY_EXPLICIT=JA`, `PERMITTED_ACTION_MATRIX_FULLY_EXPLICIT=JA`, `ATTESTATION_SCHEMA_FULLY_EXPLICIT=JA`, `BOARD_REVIEW_CLEARING_FULLY_EXPLICIT=JA`, `TASK4_BOUNDARY_PRESERVED=JA`, and `COMMERCIAL_DEPENDENCY=NEE`.

**EXACT COMMIT SUBJECT**
- `feat(website): add requirements lifecycle api`

### Task 4: Add evidence verification and automatic checkoff

**FILES**
- CREATE: `supabase/migrations/20260919103000_add_website_requirement_verification_v1.sql`; `supabase/tests/website_requirement_verification_v1.sql`; `supabase/functions/_shared/website-requirement-verification.ts`; `supabase/functions/_shared/website-requirement-verification.test.ts`
- MODIFY: none
- TEST: new pgTAP and Deno verification suites; Project Files provider/service regressions

**INTERFACES**
- Exact service-role-only authority projection and verification RPC from sections 6.7-6.8; four-entry closed rule registry; exact evidence schemas/hash/currentness; immutable verification plus verification-command ledger; Task 3 transition/readiness bridge.

**RED TEST FIRST**
- Assert exact rule/type registry and every evidence details schema/hash vector. Reject browser/human caller, browser-selected SHA/ref/result, stale or substituted context/workspace/binding/ref/commit/source/requirement revision, unknown/mismatched rule/version/mode, unsafe target, malformed timing, wrong workspace state, NOT_APPLICABLE rows, and insufficient evidence. Prove exact replay/conflict and lock behavior; AUTO PASS status matrix; FAIL/UNKNOWN preservation; HYBRID current PASS plus human completion bridge; completed-HYBRID readiness evidence; EXTERNAL v1 fail-closed; exact revisions/results/events/errors; immutable history; PRE_PROJECT with no commercial dependency; and no commercial authority change.

**IMPLEMENTATION**
- Implement sections 6.1-6.12 exactly. Reuse Project Files read policy/provider boundaries, resolve one bounded canonical snapshot before the SQL transaction, and revalidate all authority under the exact SQL locks. Task 4 owns trusted verification ingestion, repository/test evidence, AUTO PASS completion, and the HYBRID PASS bridge. It does not convert Task 2 OPERATOR items, execute tests, add production wiring, create an EXTERNAL adapter/rule, or mutate repositories/providers/commercial authority.

**GREEN TESTS**
- `npx supabase test db supabase/tests/website_requirement_verification_v1.sql`
- `deno test --allow-env supabase/functions/_shared/website-requirement-verification.test.ts supabase/functions/_shared/website-project-files-policy.test.ts supabase/functions/_shared/website-project-files-provider.test.ts supabase/functions/_shared/website-project-files-service.test.ts`

**SECURITY / SCOPE GATE**
- Static dependency and runtime spies show at most one snapshot resolve and one bounded target read, with no recursive scan, and prove verification cannot create repositories, write files, commit/push, build, publish, release, invoice, or pay. Require `TASK4_CONTRACT_UNAMBIGUOUS=JA`, `RULE_REGISTRY_FULLY_EXPLICIT=JA`, `EVIDENCE_SCHEMAS_FULLY_EXPLICIT=JA`, `EVIDENCE_HASH_MODEL_FULLY_EXPLICIT=JA`, `CURRENTNESS_MODEL_FULLY_EXPLICIT=JA`, `TRUSTED_CALLER_MODEL_FULLY_EXPLICIT=JA`, `AUTO_COMPLETION_MODEL_FULLY_EXPLICIT=JA`, `HYBRID_COMPLETION_BRIDGE_FULLY_EXPLICIT=JA`, `IDEMPOTENCY_MODEL_FULLY_EXPLICIT=JA`, `LOCK_MODEL_FULLY_EXPLICIT=JA`, `EVENT_MODEL_FULLY_EXPLICIT=JA`, `ERROR_MODEL_FULLY_EXPLICIT=JA`, `RESULT_JSON_FULLY_EXPLICIT=JA`, `PROJECT_FILES_BOUNDARY_FULLY_EXPLICIT=JA`, `TASK5_BOUNDARY_PRESERVED=JA`, and `EXTERNAL_V1_FAIL_CLOSED=JA`.

**EXACT COMMIT SUBJECT**
- `feat(website): verify requirement completion evidence`

### Task 5: Route exact PRE_PROJECT browser intents

**FILES**
- CREATE: none
- MODIFY: `supabase/functions/commercial-operator-command/handler.ts`; `supabase/functions/commercial-operator-command/handler.test.ts`; `supabase/functions/commercial-operator-command/index.ts`
- TEST: handler tests plus all existing Website/Requirements intent tests

**INTERFACES**
- Exactly nine closed read/sync/lifecycle/source-resolution browser actions from section 7; caller-JWT forwarding; fixed source-resolution dispatch; private exact response validators; closed browser-safe error mapping; existing success/error envelopes.

**RED TEST FIRST**
- Test all nine positive routes; exact keys; surplus/missing/wrong-type rejection; UUIDs; revision bounds; reason and attestation bounds/shapes; caller-JWT forwarding without service role; exact RPC names/arguments and fixed source resolutions; exact response shapes and request correlation; unknown response-key rejection; every allowlisted safe error; unknown backend error redaction; AAL1/inactive/revoked caller; role/assignment denial; cross-context substitution; stale revision; replay/conflict; PRE_PROJECT null project; and absence of verification and promotion actions. Promotion routing remains absent until Task 8.

**IMPLEMENTATION**
- In `handler.ts`, add only the nine actions, exact input types/parser/field validation, private fail-closed response validators, and safe error mappings while preserving existing envelopes. In `index.ts`, add only production caller-JWT RPC dispatch for those nine actions and exact `p_*` arguments; map each source action to its fixed resolution. Add no UI, service-role path, Task 4 verification route, or commercial Requirements behavior change.

**GREEN TESTS**
- `deno test --allow-env --allow-read supabase/functions/commercial-operator-command/handler.test.ts`
- `deno check supabase/functions/commercial-operator-command/index.ts`

**SECURITY / SCOPE GATE**
- No credentials, repository external IDs, raw context tokens, role claims, source answers, completion claims, browser-selected source resolution, direct table writes, Project Files writes, repository/GitHub/provider writes, or Task 4 verifier authority cross the browser contract. Require `TASK5_CONTRACT_UNAMBIGUOUS=JA`, `ACTION_CATALOG_FULLY_EXPLICIT=JA`, `REQUEST_SHAPES_FULLY_EXPLICIT=JA`, `RESPONSE_SHAPES_FULLY_EXPLICIT=JA`, `AAL2_MODEL_FULLY_EXPLICIT=JA`, `ROLE_MODEL_FULLY_EXPLICIT=JA`, `IDEMPOTENCY_TRANSPORT_FULLY_EXPLICIT=JA`, `ERROR_MAPPING_FULLY_EXPLICIT=JA`, `FRONTEND_AUTHORITY_MODEL_FULLY_EXPLICIT=JA`, `TASK4_TRUST_BOUNDARY_FULLY_EXPLICIT=JA`, `TASK6_BOUNDARY_FULLY_EXPLICIT=JA`, `TASK7_BOUNDARY_FULLY_EXPLICIT=JA`, and `INDEX_DISPATCH_SCOPE_EXPLICIT=JA`.

**EXACT COMMIT SUBJECT**
- `feat(website): route requirements command intents`

### Task 6: Integrate Website summary and shared client contracts

**FILES**
- CREATE: none
- MODIFY: `assets/js/operator-project-requirements.mjs`; `assets/js/operator-website-execution.mjs`; `assets/js/operator-website-execution-child.mjs`; `assets/css/operator-dashboard.css`; `scripts/operator-project-requirements.test.mjs`; `scripts/operator-website-execution.test.mjs`
- TEST: the two modified Node suites and Project Files frontend regression

**INTERFACES**
- Exact section 8.1 Website exports, nine builders, three fail-closed response validators, immutable mutation-intent helper, Website-board summary DTO, isolated summary states, and always-disabled `Requirements openen` control. Task 5 private transport validators remain the independent Edge-to-browser boundary.

**RED TEST FIRST**
- Test all nine exact export names, actions, keysets, and forbidden authority-field absence; exact board/sync/mutation validation including nested surplus keys, malformed responses, correlation, and unknown permitted-action rejection; PRE_PROJECT requests without `project_id`; OFFICIAL_PROJECT using the same Website context authority; one UUID per immutable intent, same-intent retry identity, and new-intent UUID replacement; exact `NO_BOARD`, `INTAKE_NOT_ELIGIBLE`, `READY`, and `REVIEW_REQUIRED` summaries; arithmetic consistency and no item-scan progress authority; `LOADING`, local `ERROR`, and retained `STALE_PRESENTATION`; usable Website/Project Files surfaces during Requirements failure; visible disabled `Requirements openen` with no `requestOpen` or `requirementsBoardSlot`; no lifecycle/source forms or verification ingestion; and unchanged commercial Project Requirements and Project Files regressions.

**IMPLEMENTATION**
- Preserve all commercial validators/exports and the existing Website workspace DTO. For PRE_PROJECT and OFFICIAL_PROJECT, independently fetch and validate `get_website_requirements_board`, derive only the closed section 8.1 summary, and render its local state without making the whole Website child fail. Add the reusable builders, validators, and intent helper, but execute no mutation. Remove the current Website-path commercial `requirementsBoardSlot`/`requestOpen` behavior and render the compact open control disabled. Do not mount the full list over the working surface. Add no migration, RPC, backend projection/version, Edge route, singleton, child bootstrap, AAL2 interaction, Project Files write, repository write, or GitHub write.

**GREEN TESTS**
- `node --test scripts/operator-project-requirements.test.mjs scripts/operator-website-execution.test.mjs scripts/operator-website-project-files.test.mjs`

**SECURITY / SCOPE GATE**
- No HTML injection, client-derived actions/progress, local persistence, URL authority, commercial Requirements authority reuse, or Task 2-9 behavior change. Require `TASK6_CONTRACT_UNAMBIGUOUS=JA`, `FILE_SCOPE_FULLY_EXPLICIT=JA`, `CLIENT_ACTION_CATALOG_FULLY_EXPLICIT=JA`, `BUILDER_EXPORT_NAMES_FULLY_EXPLICIT=JA`, `REQUEST_BUILDERS_FULLY_EXPLICIT=JA`, `IDEMPOTENCY_CLIENT_MODEL_FULLY_EXPLICIT=JA`, `RETRY_OWNER_MODEL_FULLY_EXPLICIT=JA`, `RESPONSE_VALIDATORS_FULLY_EXPLICIT=JA`, `SUMMARY_AUTHORITY_SOURCE_FULLY_EXPLICIT=JA`, `SUMMARY_MODEL_FULLY_EXPLICIT=JA`, `SUMMARY_NULLABILITY_FULLY_EXPLICIT=JA`, `SUMMARY_ARITHMETIC_FULLY_EXPLICIT=JA`, `STALE_PRESENTATION_FULLY_EXPLICIT=JA`, `OPEN_REQUIREMENTS_BEHAVIOR_FULLY_EXPLICIT=JA`, `UI_STATE_MODEL_FULLY_EXPLICIT=JA`, `COMMERCIAL_REQUIREMENTS_ISOLATION_FULLY_EXPLICIT=JA`, `TASK7_BOUNDARY_FULLY_EXPLICIT=JA`, `PRE_PROJECT_MODEL_FULLY_EXPLICIT=JA`, and `BACKEND_EXPANSION_REQUIRED=NEE`.

**EXACT COMMIT SUBJECT**
- `feat(website): show requirements workspace summary`

### Task 7: Complete the Requirements child and detachable singleton flow

**FILES**
- CREATE: none
- MODIFY exactly: `assets/js/operator-project-requirements.mjs`; `assets/js/operator-project-requirements-child.mjs`; `assets/js/operator-project-workspace-child.mjs`; `assets/js/operator-website-execution-child.mjs`; `assets/js/operator-module-registry.mjs`; `assets/css/operator-dashboard.css`; `scripts/operator-project-requirements.test.mjs`; `scripts/operator-project-workspace.test.mjs`; `scripts/operator-website-execution.test.mjs`; `scripts/operator-workspace.test.mjs`
- TEST: the four modified Node suites plus unchanged regression-only `scripts/operator-website-project-files.test.mjs`

**INTERFACES**
- Exact section 8.2 Website `req-*` and commercial `project-req-*` slot helpers/matchers; one dual-mode child selected only by validated prefix; Task 6 Website builders/validators/intent helper; Task 5 browser actions; existing commercial Requirements interfaces; Website and Project open controls; existing managed focus/invalidation/revoke protocols.

**RED TEST FIRST**
- Lock the complete section 8.2-8.3 contract before implementation. At minimum prove exact parsing and rejection for Website `req-*`, commercial `project-req-*`, invalid/mixed slots, and exact-quote invalidation; registry tests `project-req-*` before `project-*`; PRE_PROJECT and OFFICIAL_PROJECT Website boards; PRE_PROJECT commercial fail-closed; commercial Project Requirements unchanged; no cross-authority dispatch; every root and transient UI state; exact filters and server order; unknown action rejection; sync visibility/revision/AAL2; all seven item actions; bounded inline forms with no Website `window.prompt`; one pending intent, same-intent ambiguous retry, definitive discard/new UUID, stale read/mutation/context switch, success refetch/invalidation, and safe error copies.
- Prove Website button -> `req-*`, Project button -> `project-req-*`, first click opens one managed child, duplicate Website open focuses it with `FOCUS_REQUEST`, no duplicate claim/workspace, integrated/detached views share board ID/revision, logout/revoke/lease/context mismatch clear, opener substitution is ignored, and URLs/events contain no authority/token IDs. Prove no verification ingestion and unchanged Project Files behavior. Test CSS/accessibility at 1440x900, 900x700, and 390x844.

**IMPLEMENTATION**
- Implement sections 8.2-8.3 without deviation. Add exact slot helpers and matchers; route `project-req-*` before `project-*`; pass `requireAal2` to both Requirements modes; switch Project Workspace to the commercial slot; activate Website Execution's Task 6 button for the Website slot; preserve the embedded summary; and keep one child implementation with authority selected only from the validated prefix.
- In Website mode replace the placeholder with exact board fetch/validation/rendering, filters, sync, lifecycle/source actions, inline forms, one immutable intent, AAL2-before-every-attempt, closed retry/error handling, authoritative refetch, invalidation, stale/context guards, accessibility, and responsive behavior. Preserve commercial mode business logic and authority except for its namespace. Use existing managed-window protocols only.
- Add no backend, migration, Edge, database mutation, verification ingestion, promotion, Project Files/repository/GitHub write, new route, BroadcastChannel, popup minimum, independent cache/workspace, optimistic state, or direct `window.open`.

**GREEN TESTS**
- `node --test scripts/operator-project-requirements.test.mjs scripts/operator-project-workspace.test.mjs scripts/operator-website-execution.test.mjs scripts/operator-workspace.test.mjs scripts/operator-website-project-files.test.mjs`

**SECURITY / SCOPE GATE**
- Child re-resolves context on every authoritative refresh; mode derives only from exact slot prefix; denied/mismatch/revoke/lease/context-switch state clears immediately; Website/commercial authority never crosses; server-projected actions alone create buttons; every Website mutation is AAL2-gated, revision-bound, idempotent, and refetched; no raw error, optimistic state, `window.open`, direct table call, independent workspace/cache, verification path, Project Files write, repository/GitHub write, or Task 8 behavior.
- Require `TASK7_CONTRACT_UNAMBIGUOUS=JA`, `FILE_SCOPE_FULLY_EXPLICIT=JA`, `WEBSITE_SLOT_MODEL_FULLY_EXPLICIT=JA`, `COMMERCIAL_SLOT_MODEL_FULLY_EXPLICIT=JA`, `REGISTRY_PREFIX_ORDER_FULLY_EXPLICIT=JA`, `COMMERCIAL_REQ_ROUTE_SEPARATION_FULLY_EXPLICIT=JA`, `INTEGRATED_VIEW_FULLY_EXPLICIT=JA`, `DETACHED_VIEW_FULLY_EXPLICIT=JA`, `CHILD_BOOTSTRAP_FULLY_EXPLICIT=JA`, `SYNC_UI_FULLY_EXPLICIT=JA`, `LIFECYCLE_UI_FULLY_EXPLICIT=JA`, `SOURCE_RESOLUTION_UI_FULLY_EXPLICIT=JA`, `IDEMPOTENCY_LIFECYCLE_FULLY_EXPLICIT=JA`, `AAL2_UI_MODEL_FULLY_EXPLICIT=JA`, `INVALIDATION_MODEL_FULLY_EXPLICIT=JA`, `LOGOUT_REVOKE_MODEL_FULLY_EXPLICIT=JA`, `STALE_MUTATION_MODEL_FULLY_EXPLICIT=JA`, `UI_STATE_MODEL_FULLY_EXPLICIT=JA`, `RESPONSIVE_MODEL_FULLY_EXPLICIT=JA`, `ACCESSIBILITY_MODEL_FULLY_EXPLICIT=JA`, and `TASK8_BOUNDARY_FULLY_EXPLICIT=JA`.

**EXACT COMMIT SUBJECT**
- `feat(website): detach context requirements worklist`

### Task 8: Preserve requirements through official-project promotion

**FILES**
- CREATE: `supabase/migrations/20260919104000_add_website_requirements_promotion_continuity_v1.sql`; `supabase/tests/website_requirements_promotion_v1.sql`
- MODIFY exactly: `supabase/functions/commercial-operator-command/handler.ts`; `supabase/functions/commercial-operator-command/handler.test.ts`; `supabase/functions/commercial-operator-command/index.ts`; `assets/js/operator-website-execution.mjs`; `assets/js/operator-website-execution-child.mjs`; `scripts/operator-project-requirements.test.mjs`; `scripts/operator-website-execution.test.mjs`; `scripts/operator-workspace.test.mjs`
- TEST: promotion, concept, workspace, commercial Requirements, and frontend phase-switch suites

**INTERFACES**
- Exact section 9 owner+AAL2 `promote_website_concept` browser intent; server-derived canonical project; caller-JWT `promote_website_concept_v1` dispatch; closed request/result validation; promotion command ledger; append-only promotion audit; same context/workspace/board projection after phase switch; Website Workspace UI; slot invalidation.

**RED TEST FIRST**
- pgTAP proves owner+AAL2 success; server-derived project with no browser project authority; valid accepted lineage; same context/workspace/board/item IDs; unchanged board/item revisions, verification/history, repository binding, and binding revision; concept/context revision increments; only workspace `project_id` changes; promotion without workspace or board succeeds without creating either; same-key replay creates no event/write; same-key changed fingerprint conflicts; new key after success is rejected as already promoted; stale expected context revision; zero/multiple eligible project; cross-dossier mismatch; wrong phase; non-owner; AAL1; and injected-failure full rollback.
- Edge tests prove the closed request parser; surplus `project_id` rejection; exact response validator and request correlation; caller-JWT dispatch with exact RPC arguments; safe error mapping; unknown-error redaction; and absence of service-role authority.
- Frontend tests prove owner/PRE_PROJECT button visibility; OFFICIAL_PROJECT and non-owner hiding; exact confirmation/status/error copy; request without `project_id`; AAL2 and post-AAL2 context recheck; one immutable intent; same-key ambiguous retry; definitive discard; safe errors and required refresh; successful same-context OFFICIAL_PROJECT refetch; authoritative-success/local-refresh failure; ignored stale response after context switch; unchanged `website-*` and `req-*` slots; promotion-free Requirements child with in-place refresh; and zero Project Files, repository, or GitHub writes.

**IMPLEMENTATION**
- Implement section 9 without deviation. Add the two exact migration tables and exact caller-JWT RPC transaction; derive the project server-side; preserve every Website identity, board/item revision, verification, repository binding, and Project Files state; add the exact handler parser/validator/error mapping and index dispatch; add the three Website Execution exports and promotion UI with exact AAL2/retry/stale/success behavior. Add no copy path, service role, automatic Project Workspace open, commercial release, invoice/payment, publication/deployment, commercial Requirements mutation, verification ingestion, Project Files write, repository write, or GitHub write.

**GREEN TESTS**
- `npx supabase test db supabase/tests/website_requirements_promotion_v1.sql`
- `npx supabase test db supabase/tests/website_requirement_verification_v1.sql`
- `npx supabase test db supabase/tests/website_requirements_lifecycle_v1.sql`
- `npx supabase test db supabase/tests/website_requirements_intake_sync_v1.sql`
- `npx supabase test db supabase/tests/website_requirements_foundation_v1.sql`
- `npx supabase test db supabase/tests/website_concept_pre_project_v1.sql`
- `npx supabase test db supabase/tests/website_execution_workspace_v1.sql`
- `npx supabase test db supabase/tests/project_requirements_board_v1.sql`
- `deno test --allow-env --allow-read supabase/functions/commercial-operator-command/handler.test.ts`
- `deno check supabase/functions/commercial-operator-command/handler.ts`
- `deno check supabase/functions/commercial-operator-command/index.ts`
- `node --test scripts/operator-project-requirements.test.mjs scripts/operator-website-execution.test.mjs scripts/operator-workspace.test.mjs scripts/operator-website-project-files.test.mjs`

**SECURITY / SCOPE GATE**
- Before/after table snapshots prove no copied board/item/history, no commercial invariant weakening, and no Finance/mail/provider/publication side effect. Local database bootstrap, if required, uses only `supabase/local-bootstrap/operator-auth-identities.sql` and never an ad-hoc `auth.users` insert.
- Require `TASK8_CONTRACT_UNAMBIGUOUS=JA`, `FILE_SCOPE_FULLY_EXPLICIT=JA`, `PROMOTION_TRIGGER_FULLY_EXPLICIT=JA`, `PROMOTION_RPC_FULLY_EXPLICIT=JA`, `PROMOTION_REQUEST_FULLY_EXPLICIT=JA`, `PROMOTION_RESPONSE_FULLY_EXPLICIT=JA`, `PROJECT_ID_SERVER_DERIVED=JA`, `ROLE_MODEL_FULLY_EXPLICIT=JA`, `AAL2_MODEL_FULLY_EXPLICIT=JA`, `IDEMPOTENCY_MODEL_FULLY_EXPLICIT=JA`, `CONCURRENCY_MODEL_FULLY_EXPLICIT=JA`, `TRANSACTION_MODEL_FULLY_EXPLICIT=JA`, `COMMERCIAL_LINEAGE_FULLY_EXPLICIT=JA`, `CONTEXT_CONTINUITY_FULLY_EXPLICIT=JA`, `WORKSPACE_CONTINUITY_FULLY_EXPLICIT=JA`, `BOARD_CONTINUITY_FULLY_EXPLICIT=JA`, `VERIFICATION_CONTINUITY_FULLY_EXPLICIT=JA`, `AUDIT_MODEL_FULLY_EXPLICIT=JA`, `FRONTEND_TRIGGER_FULLY_EXPLICIT=JA`, `FRONTEND_SUCCESS_FLOW_FULLY_EXPLICIT=JA`, `STALE_RESPONSE_MODEL_FULLY_EXPLICIT=JA`, `ERROR_MAPPING_FULLY_EXPLICIT=JA`, `INDEX_DISPATCH_SCOPE_EXPLICIT=JA`, `TASK9_BOUNDARY_FULLY_EXPLICIT=JA`, and `SERVICE_ROLE_USED=NEE` before implementation proceeds.

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
| `PERSISTENT_PROGRESS` | Mutate, reconnect/refetch integrated and detached views | Same server status/revision/exact progress and readiness keys/counts |
| `START_BLOCK_COMPLETE_REOPEN` | Lifecycle pgTAP transition table over every status/source-state/mode/role combination | Only exact legal transitions; one ACTIVE; reasons/attestation; item+board revision increments; context revision unchanged; exact events/results/errors |
| `SOURCE_RESOLUTION` | Resolve CHANGE_PENDING and REMOVAL_PENDING through every resolution and lifecycle state | Exact proposal authority, preserve/reset behavior, evidence invalidation, no delete, and one unresolved item keeps REVIEW_REQUIRED |
| `TASK3_IDEMPOTENCY` | Replay each lifecycle/source command and reuse each key with changed fingerprint | Exact stored result without writes; conflict code; no duplicate event or revision increment |
| `TASK3_BOARD_PROJECTION` | Read absent/current/review boards under every role/assignment | Exact closed root/context/board/item/source/progress/readiness/action DTO; denied callers receive no metadata |
| `TASK5_BROWSER_EDGE_ROUTING` | Exercise all nine actions with exact/malformed/surplus requests, caller-JWT spies, response mutations, every allowlisted backend error, cross-context substitutions, replay/conflict, and forbidden action names | Exact RPC/argument/fixed-resolution dispatch; private fail-closed response correlation; stable redacted errors; null project accepted; no generic resolution, verification, promotion, service-role, direct-table, Project Files, repository, GitHub, or provider path |
| `AUTHORITATIVE_AUTO_CHECKOFF` | Trusted `website_test_suite_passed` v1 PASS vs browser claim over PENDING/ACTIVE/BLOCKED/COMPLETED | Exact AUTO status matrix; browser cannot ingest or choose result/ref/SHA |
| `AUTHORITATIVE_EXTERNAL_CHECKOFF` | Every EXTERNAL key/version, including generic provider names | `UNKNOWN_WEBSITE_REQUIREMENT_RULE`; no verification or completion; v1 registry remains empty |
| `AUTO_EVIDENCE_BOUND_TO_CURRENT_WORKSPACE` | Substitute context/workspace/binding/ref/commit/source/requirement/rule versions and expiry | Every stale/substituted envelope fails closed with its exact Task 4 error |
| `TASK4_EVIDENCE_SCHEMAS` | Evaluate all four evidence types, exact detail keys, timing bounds, canonical hash vectors, PASS/FAIL/UNKNOWN | Exact deterministic result; NOT_APPLICABLE insertion and surplus/malformed evidence rejected |
| `TASK4_VERIFICATION_IDEMPOTENCY` | Replay before stale check; same key with changed fingerprint; concurrent duplicate PASS | Stored replay only; exact conflict; one verification/update/event/result and no duplicate completion |
| `TASK4_HYBRID_COMPLETION_BRIDGE` | Current PASS, Task 3 human completion, subsequent readiness and new mutation attempt | PASS enables but does not complete; prior-revision PASS proves only matching completed transition and is not current for mutation |
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

### 13.1 Mandatory pre-Task 10 evidence alignment

Task 10 remains verification-only and cannot author missing evidence. Before Task 10 may start, run one separately authorized test-only alignment with this closed scope:

```text
PRE_TASK10_EVIDENCE_ALIGNMENT_CREATE=GEEN
PRE_TASK10_EVIDENCE_ALIGNMENT_MODIFY=supabase/tests/website_requirements_lifecycle_v1.sql; supabase/tests/website_project_files_phase_a_v1.sql
PRE_TASK10_EVIDENCE_ALIGNMENT_DELETE=GEEN
PRODUCT_CODE_FILES=0
MIGRATION_FILES=0
PRE_TASK10_ALIGNMENT_PRODUCT_CODE_CHANGES=VERBODEN
```

No other test, product, migration, Edge, handler, shared-runtime, frontend, documentation, generated, or lockfile path belongs to this alignment.

The existing test authorities own the missing evidence as follows:

1. `SOURCE_CHANGE_CROSS_SUBSTITUTION` belongs only to `supabase/tests/website_requirements_lifecycle_v1.sql`. That suite already owns `resolve_website_requirement_source_change_v1`, all three exact resolutions `ACCEPT_CHANGE`, `KEEP_EXISTING`, and `RETIRE`, the source proposal/evidence/revision/event effects, and the existing two-context lifecycle denial fixture. Extend that fixture with one foreign-context attempt for each resolution. Each attempt must use the context A quote/context with the context B requirement, fail with `WEBSITE_REQUIREMENT_NOT_FOUND`, disclose no B metadata, and leave both contexts' requirement rows, board revisions, source proposals, verification state, and event history unchanged.
2. `PROJECT_FILES_TO_REQUIREMENTS_NO_WRITE_SNAPSHOT` belongs only to `supabase/tests/website_project_files_phase_a_v1.sql`. That suite owns the caller-JWT OWNER+AAL2 acquire/release RPC boundary and already snapshots repository operations/events and complete workspace binding rows around DIRECTORY/FILE authority acquisition and release. Add synthetic Website Requirements board/item/event/verification state for both existing Project Files contexts to that same before/after snapshot and require exact equality after the existing successful, denied, rate-limited, concurrent, expired, and foreign-release paths. Board revision, item status/revision, progress inputs, events/history, and verification rows must remain unchanged.

No additional test file is required. The SQL snapshot is the database-mutation boundary because the production Project Files route calls only `acquire_website_project_files_read_v1`, the pure provider/service read path, and `release_website_project_files_read_v1`. The existing static provider dependency test and runtime mutation spies remain responsible for proving that the provider/service segment exposes no Requirements or repository write operation. No service, handler, or frontend test may be modified for this alignment.

Run this exact alignment matrix after the two test edits:

```powershell
npx supabase test db supabase/tests/website_requirements_lifecycle_v1.sql
npx supabase test db supabase/tests/website_requirements_security_release_v1.sql
npx supabase test db supabase/tests/website_project_files_phase_a_v1.sql
deno test --allow-env supabase/functions/_shared/website-project-files-provider.test.ts --filter "provider exposes no write method"
```

All four commands must pass. The lifecycle suite must prove all three foreign source-resolution attempts fail closed without writes. The security-release regression must retain its two-context Requirements-to-repository/provider/workspace no-write snapshot. The Project Files suite must prove its expanded Requirements snapshot remains exactly equal. The filtered provider test must report zero reachable repository/provision/build/preview/publication mutation calls.

If an added assertion exposes a product defect, stop with `PRODUCT_DEFECT_FOUND=JA` and return to controller review. Do not change product code, migrations, Edge code, handlers, shared runtime, or frontend code in the alignment. Do not weaken or delete an assertion. Do not create the alignment commit until all four commands pass and the exact two-file scope is clean under `git diff --check`.

The successful alignment creates exactly one local test-only commit:

```text
PRE_TASK10_ALIGNMENT_COMMIT_SUBJECT=test(website): align phase a re-entry evidence
PRE_TASK10_ALIGNMENT_COMMIT_COUNT=1
PRE_TASK10_ALIGNMENT_PUSHES=0
PRE_TASK10_ALIGNMENT_DEPLOYS=0
PRE_TASK10_ALIGNMENT_REMOTE_MIGRATIONS=0
PRE_TASK10_ALIGNMENT_REMOTE_DATABASE_MUTATIONS=0
```

Use this exact scope and commit gate after all four alignment commands pass:

```powershell
git status --short
git diff --check
git diff --name-only
git add -- supabase/tests/website_requirements_lifecycle_v1.sql supabase/tests/website_project_files_phase_a_v1.sql
git diff --cached --check
git diff --cached --name-only
git commit -m "test(website): align phase a re-entry evidence"
git rev-parse HEAD
git rev-parse HEAD^
git log -1 --format=%s
git status --short
git diff --check
git diff-tree --no-commit-id --name-only -r HEAD
```

Before the commit, `git status --short`, `git diff --name-only`, and `git diff --cached --name-only` must identify exactly the two files listed by `PRE_TASK10_EVIDENCE_ALIGNMENT_MODIFY`; `git diff --check` and `git diff --cached --check` must pass. After the commit, the parent must be the controller-approved pre-alignment HEAD, the subject and two-file tree must be exact, and the worktree must be clean. `deno.lock` and every generated file must remain byte-for-byte unchanged. Any third path or ancestry movement stops the alignment without cleanup, reset, restore, stash, rebase, merge, or cherry-pick. Task 10 starts only from that clean alignment commit after separate controller authorization.

### 13.2 Expanded verification-only Task 10

Re-run original Phase A Task 10 from the September 17 plan as verification-only. Task 10 creates, modifies, and deletes no file and creates no commit. Run this exact expanded command matrix; it retains every original Task 10 command and adds only the focused Requirements suites that own the re-entry substitutions and no-write evidence:

```powershell
npx supabase test db supabase/tests/website_project_files_phase_a_v1.sql
deno test --allow-env supabase/functions/_shared/website-project-files-policy.test.ts supabase/functions/_shared/website-project-files-cursor.test.ts supabase/functions/_shared/website-project-files-provider.test.ts supabase/functions/_shared/website-project-files-service.test.ts
deno test --allow-env --allow-read supabase/functions/commercial-operator-command/handler.test.ts
node --test scripts/operator-website-project-files.test.mjs scripts/operator-website-execution.test.mjs scripts/operator-workspace.test.mjs
npx supabase test db supabase/tests/website_requirements_intake_sync_v1.sql
npx supabase test db supabase/tests/website_requirements_lifecycle_v1.sql
npx supabase test db supabase/tests/website_requirement_verification_v1.sql
npx supabase test db supabase/tests/website_requirements_promotion_v1.sql
npx supabase test db supabase/tests/website_requirements_security_release_v1.sql
```

The expanded matrix must prove all of the following together:

- Board, context, intake, item, and verification identities from context B cannot be substituted under context A. Every foreign substitution fails closed without metadata, result, cursor reuse, stale UI content, or write.
- Source-change substitution covers `ACCEPT_CHANGE`, `KEEP_EXISTING`, and `RETIRE`. Promotion substitution fails before project selection and creates no command or event.
- Requirements reads and verification attempts leave repository operations/events and provider/workspace binding unchanged.
- Project Files DIRECTORY/FILE acquire/read/release paths leave Website Requirements board revision, item state/revisions, progress inputs, events/history, and verification state unchanged.
- The original 60-second 30/10 budgets, four concurrent reads, 10-second timeout, 500-entry limit, complete-envelope 512 KiB limit, 1 MiB file limit, cursor expiry, provider oversized-body behavior, classifier outage, one provider attempt per injected failure, cursor boundaries, and lease lifecycle remain exact.
- Caller-JWT, active OWNER, AAL2, and canonical context/workspace/binding/ref/commit checks remain authoritative. Mutation spies remain exactly zero for repository create/provision, GitHub POST/PATCH/PUT/DELETE, commit/push, build/preview, publication, production release, and Task14 calls.

Task 10 passes only when every command passes, the required cases use two synthetic contexts where applicable, every foreign substitution fails closed, every no-write snapshot is exactly equal, every mutation counter is zero, `git status --short` is empty, `git diff --check` passes, and Task 10 created zero files, modifications, deletions, and commits.

Task 10 stops immediately when required evidence is absent; a command fails; provider content or foreign metadata leaks; foreign authority is accepted; a mutation counter is nonzero; a no-write snapshot differs; ancestry or baseline moves unexpectedly; the worktree becomes dirty; or a product defect is found. Task 10 performs no repair. A defect returns to its exact owning prior-task file and commit boundary under new controller authorization, after which the complete pre-Task10 alignment and Task 10 matrices restart.

```text
TASK10_VERIFICATION_ONLY=JA
TASK10_FILES_CHANGED=0
TASK10_COMMITS_CREATED=0
TASK10_PUSHES=0
TASK10_DEPLOYS=0
```

### 13.3 Separate Task 11 release gate

Only after Task 10 passes and a controller separately authorizes Task 11 may the original Phase A Task 11 from the September 17 plan run. Its database list must include all six new Website Requirements pgTAP files and the commercial Requirements regression. Its Deno list must include the verification suite. Its frontend list must include Requirements singleton/state synchronization. Preserve the original ancestry/baseline checks, exact assertion counts, public-page regressions, no-write proof, and checkpoint format.

Update `docs/superpowers/checkpoints/2026-09-17-website-execution-project-files-phase-a-verification.md` only during Task 11 with both Project Files and Requirements Closure evidence. Set `DEPLOY_AUTHORIZED=NEE` and `PUSH_AUTHORIZED=NEE` unless a later controller authorization explicitly changes them.

Task 11 is a separate local release gate with its own checkpoint commit. Task 11 does not authorize a push, deployment, remote migration, remote database mutation, repository provisioning, or production action. Even after Task 11 passes, only a later controller-reviewed and separately authorized action may consider push, main promotion, remote migrations, Edge deployment, or Pages production deployment.

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