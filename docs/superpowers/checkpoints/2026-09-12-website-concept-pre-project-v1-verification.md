# Website Concept PRE_PROJECT V1 Verification

Date: 2026-09-12
Baseline: `72d1ac3eb5694345ffa528ec6e9bbbb9bc61ff73`
Branch: `fix/dossier-continuity-project-integration-20260912`

## Result

Feature acceptance: PASS.
Full local gate: INCOMPLETE because one pre-existing handoff fixture cannot pass its own AAL2 setup and the CI wrapper exposes production-only phases. No production preflight, push, deploy, remote migration, release distribution, or production-data mutation was performed.

## Implementation History

- `1992886` test(concept): define pre-project vertical slice
- `b122984` feat(concept): add pre-project authority roots
- `9b4973d` feat(concept): project website work authority
- `d58303c` feat(concept): add owner start command
- `8ecb916` feat(concept): route bounded start intent
- `9af382c` feat(operator): start website concepts from dossiers
- `041f4dd` feat(website): bind execution to work context
- `eedd91d` feat(website): open pre-project execution workspace
- `bf96c98` fix(operator): retain website concept snapshots
- `f31f9ab` fix(website): retain pre-project child snapshot
- `033472d` test(workspace): prove pre-project slot continuity
- `e7708c8` test(concept): harden authority isolation
- `f1a2444` test(concept): verify refresh frame stability
- `68c9bbd` test(requirements): accept retained website snapshots

## Executed Gates

- `npx supabase db reset`: PASS; all migrations applied locally through `20260912132000`.
- `npx supabase test db supabase/tests/website_concept_pre_project_v1.sql`: PASS, 155/155.
- `npx supabase test db supabase/tests/project_requirements_board_v1.sql`: PASS, 179/179.
- `npx supabase test db supabase/tests/operator_mfa_aal2_authority_v1.sql`: PASS, 7/7.
- `deno test --allow-env --allow-read supabase/functions/commercial-operator-command/handler.test.ts`: PASS, 134/134. `--allow-read` is required by existing source/config assertions; the plan's command without it is rejected by Deno permissions.
- Combined operator frontend command from Task 14: PASS, 153/153 after the narrow shared Requirements assertion correction in `68c9bbd`.
- `node --test scripts/website-concept-pre-project-live-preview.test.mjs scripts/dossier-continuity-release-integration.test.mjs`: PASS, 8/8.
- `powershell -ExecutionPolicy Bypass -File scripts/invoke-dossier-continuity-release-gate.ps1 -Phase Local`: PASS, 18/18 and `DOSSIER_CONTINUITY_LOCAL_GATE=PASS`.

## Documented Gate Constraints

`supabase/tests/operator_application_handoff.sql` stops during fixture setup after 10/122 assertions with `HUMAN_JWT_REQUIRED`. It inserts `commercial_operators` before establishing a human AAL2 JWT, while the pre-existing `20260904160000_require_operator_aal2_for_critical_actions_v1.sql` trigger requires AAL2 for that insert. The PRE_PROJECT migration diff does not alter this guard. This unrelated fixture was not weakened or bypassed.

`scripts/invoke-dossier-continuity-ci-gate.ps1` requires `PreDeploy` or `PostDeploy`, uses the production Supabase URL, and has no `Local` phase. It was not run because the approved plan prohibits a production preflight. The supported local release gate above was run instead.

## Scope And Security Review

- Migration diff contains four added forward-only files; no existing migration changed.
- No `dist-open-application` or `dist-release` file changed.
- New SQL revokes direct table/function authority and exposes only intended authenticated wrappers; owner, active status, human JWT, and AAL2 remain server-enforced.
- Added `commercial_projects`, payment, and promotion terms are read-only compatibility/invariant checks or future-boundary schema fields. There is no concept promotion command and no direct concept insert into `commercial_projects`.
- No intake-to-Requirements sync, customer notification, Finance/payment/milestone mutation, publication/live activation, or `concept-*` Multi-Screen slot was added.
- Browser intent remains exact-key bounded; actor, role, mode, release, project, and context authority are server-derived.
- Uncommitted local harness artifacts remain intentionally excluded: `deno.lock`, `supabase/config.toml`, `supabase/.branches/_current_branch`, and `supabase/roles.sql`.

## Acceptance Matrix

| Criterion | Result |
|---|---|
| Active dossier shows Website work | JA |
| Owner can start concept with AAL2 | JA |
| Confirmation dialog | JA |
| PRE_PROJECT persists | JA |
| Website open is visible and opens execution | JA |
| No quotation, payment, or commercial release required | JA |
| No customer notification or Finance mutation | JA |
| No publication right | JA |
| Duplicate concept blocked and replay deterministic | JA |
| Same-dossier refresh stable | JA |
| Cross-dossier and authorization invalidation clear immediately | JA |
| One stable work context | JA |
| Existing official Website work remains valid | JA |
| Requirements remains commercial/project-bound | JA |
| Existing Multi-Screen lifecycle remains intact | JA |
| Browser intent bounded and caller-JWT scoped | JA |
| No promotion implementation or intake sync | JA |

## Review Decision

The PRE_PROJECT implementation is locally reviewable and its feature-specific acceptance matrix passes. Treat the repository-wide gate as not fully green until the independent handoff fixture establishes AAL2 before protected operator writes. Production release remains outside this checkpoint.
