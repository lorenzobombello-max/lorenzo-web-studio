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
sync_website_requirements_from_intake_v1(p_quote_request_id uuid, p_website_work_context_id uuid, p_expected_board_revision bigint, p_idempotency_key uuid) -> jsonb
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