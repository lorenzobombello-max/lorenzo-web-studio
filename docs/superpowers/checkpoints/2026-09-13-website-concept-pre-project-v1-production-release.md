# Website Concept PRE_PROJECT V1 Production Release

Date: 2026-09-13
Branch: `fix/dossier-continuity-project-integration-20260912`
Production SHA: `20239aa6c46828add91a576432da271144af3b6d`

## Result

- Production schema, Edge function, main branch and protected Pages release: PASS.
- Production continuity release gate: PASS.
- Live concept-start acceptance: BLOCKED, not failed.
- End-to-end production acceptance: INCOMPLETE.

No live concept was started. Production currently has no eligible disposable synthetic Website dossier. Nathalie/Yuna is real customer data and must remain read-only. The only ACTIVE Website dossier is continuity/VAT sentinel `LWS-AAN-2026-0006`, which must remain unchanged. Creating another production dossier would invalidate the protected `2 / 1 / 1 / 0` continuity baseline.

## Production Migrations

Controlled `supabase db push --linked --include-all` was used only after an exact dry-run proved 13 migrations in the approved order with no unexpected migration.

Prerequisites:

1. `20260910010000_add_operator_project_start_gate_v1.sql`
2. `20260910020000_add_start_project_work_v1.sql`
3. `20260910030000_add_website_execution_workspace_v1.sql`
4. `20260910040000_add_project_requirements_board_foundation_v1.sql`
5. `20260910041000_add_project_requirements_board_projection_v1.sql`
6. `20260910050000_add_project_requirement_lifecycle_v1.sql`
7. `20260910051000_add_project_requirement_verification_v1.sql`
8. `20260910060000_guard_preview_ready_with_requirements_v1.sql`
9. `20260910061000_project_requirement_permitted_actions_v1.sql`

PRE_PROJECT V1:

1. `20260912130000_add_website_concept_work_context_foundation_v1.sql`
2. `20260912131000_add_website_concept_authority_v1.sql`
3. `20260912131500_add_website_concept_start_command_v1.sql`
4. `20260912132000_reanchor_website_execution_workspace_v1.sql`

Post-apply verification showed all 13 versions aligned, zero local-only versions, zero remote-only versions, all requested objects present, and a following dry-run reported the remote database up to date. No migration repair, history insert, timestamp rewrite, reset or direct SQL migration bypass was used.

## Edge Release

- Function: `commercial-operator-command`
- Status: `ACTIVE`
- Version: `97` (previously `96`)
- SHA-256: `2b580855f9c347a7a2d45e950b7d87e4375312c2cac6736359e9217701e3ff09`

The deployed request accepts the fixed `action` discriminator plus `quote_request_id`, `expected_website_work_revision` and `idempotency_key`; only those three bounded values are forwarded to the RPC. Actor, role, AAL, mode, release state, concept identity and work-context identity remain server-derived.

## Main And Pages

- Non-force push: `c7f7bf22b0e609d5bb180c8a4ae99436d2b400c5..20239aa6c46828add91a576432da271144af3b6d`
- `origin/main`: `20239aa6c46828add91a576432da271144af3b6d`
- Workflow: `Deploy Static Site to GitHub Pages #407`
- Workflow run ID: `34739180878`
- Overall conclusion: `success` in 1m42s

| Job | Conclusion | Duration |
| --- | --- | ---: |
| `continuity-predeploy` | success | 27s |
| `build` | success | 18s |
| `deploy` | success | 10s |
| `continuity-postdeploy` | success | 24s |
| `release-approved` | success | 4s |

The workflow's authenticated protected gate published final release approval only after successful predeploy and postdeploy continuity checks.

## Verification Evidence

- Core pgTAP: 346 passed (`155` PRE_PROJECT, `179` Requirements, `12` Website execution).
- Node/frontend/release integration: 159 passed.
- Edge: 165 passed.
- Local continuity gate: 18 passed and `DOSSIER_CONTINUITY_LOCAL_GATE=PASS`.
- Repaired dossier fixture suites: 70 passed.
- Finance suites: 67 passed.
- VAT/pricing repaired group: 58 passed.
- Pricing base: 9 passed.

The earlier fixture blocker was repaired by establishing bounded human AAL2 context before protected operator writes. Production authority code was not weakened.

## Authority And Safety

Verified locally against the production migration set:

| Assertion | Result |
| --- | --- |
| Active AAL2 owner can start one eligible concept | PASS |
| AAL1 owner cannot start | PASS |
| Admin receives no start action | PASS |
| Operations manager/operator cannot start | PASS |
| Anonymous caller has no execute grant | PASS |
| Duplicate concept is blocked | PASS |
| Exact idempotent replay reuses concept and context | PASS |
| Fake/client-supplied project identity is impossible | PASS |
| Quotation/acceptance/commercial/payment/mail/preview/publication counts remain unchanged | PASS |
| Commercial release remains false | PASS |

These are schema, Edge and local integration proofs. They are not represented as a live production mutation test.

## Continuity

Post-migration and protected workflow evidence remained:

| Measure | Value |
| --- | ---: |
| `TOTAL_RAW` | 2 |
| `PENDING` | 1 |
| `ACTIVE` | 1 |
| `TRASHED` | 0 |
| `COUNT_DRIFT` | NEE |

- Nathalie/Yuna: present, not trashed and unchanged.
- Sentinel `LWS-AAN-2026-0006`: ACTIVE, not trashed and unchanged.
- Immediately after deployment: `website_concepts=0`, `website_work_contexts=0`.
- No unplanned customer, commercial or VAT mutation was performed.

## Live Acceptance Boundary

The deployed UI and owner session were inspected read-only on protected sentinel `LWS-AAN-2026-0006`. Website work rendered `Nog geen websiteconcept`, `Niet beschikbaar`, `Niet commercieel vrijgegeven` and `WEBSITE-CONCEPT STARTEN`. Opening the action showed `Voorlopig concept starten — dit is nog geen commerciële bestelling` with `Annuleren` and `Concept starten`. Only `Annuleren` was selected. The dialog closed, the same dossier and values remained mounted, and the start action remained available.

The final database snapshot after cancellation remained `2 / 1 / 1 / 0`, with `website_concepts=0` and `website_work_contexts=0`; Nathalie/Yuna and the sentinel remained ACTIVE and not trashed. This proves the confirmation cancel path was a no-op.

The protected sentinel was not used for a concept start. The existing internal smoke authority creates `internal_e2e` Customer Request data, not an eligible `website + production + ACTIVE` dossier. Test-only pgTAP fixtures use privileged rollback-scoped setup and are not a production fixture mechanism.

Therefore these production-live assertions remain `NOT_VERIFIED`:

- live concept start after the verified confirmation cancel no-op;
- persistence after refresh and reopen;
- duplicate start and same work-context reuse;
- managed Website child opening after a real PRE_PROJECT start;
- three genuine 8-second live refresh cycles and invalid-frame counts;
- live non-owner mutation attempts;
- live before/after proof for all commercial side-effect surfaces.

Resume only after a separately approved disposable production fixture exists, or an eligible dossier is explicitly authorized without touching protected customer/sentinel records or invalidating the continuity baseline.

## Repository State

The release commit excluded local harness artifacts: `deno.lock`, `supabase/config.toml`, `supabase/.branches/` and `supabase/roles.sql`. They remain uncommitted and were not reverted.

No repository tooling or documented destination exists for a central Google Drive checkpoint update. That external update was therefore not attempted.