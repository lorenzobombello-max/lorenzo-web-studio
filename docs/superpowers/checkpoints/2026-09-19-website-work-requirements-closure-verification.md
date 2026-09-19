# Website Work Requirements Closure Verification

Date: 2026-09-19
Status: `TASK9_CLOSED_PASS`
Task: `Prove closure acceptance and prepare Phase A re-entry`
Canonical plan: `docs/superpowers/plans/2026-09-19-website-work-requirements-closure-implementation-plan.md`
Candidate before Task 9: `a1429f62f2f965f7ea6cf91b654a3b4d6d3f272e`
Task 9 security test SHA-256: `0116570d5ad01d1ed9142ff640404fa545b15499c1c54dca5a47999d16df8235`

## Closure Status

| Task | Implementation state | Implementation commit |
|---|---|---|
| Task 1 | CLOSED / PASS | `ce9f7e1` `feat(website): add context requirements authority` |
| Task 2 | CLOSED / PASS | `9451175` `feat(website): sync intake requirements idempotently` |
| Task 3 | CLOSED / PASS | `4a906cb` `feat(website): add requirements lifecycle api` |
| Task 4 | CLOSED / PASS | `0b1b187` `feat(website): verify requirement completion evidence` |
| Task 5 | CLOSED / PASS | `6d301d9` `feat(website): route requirements command intents` |
| Task 6 | CLOSED / PASS | `0f2a2e3` `feat(website): show requirements workspace summary` |
| Task 7 | CLOSED / PASS | `db3ccb9` `feat(website): detach context requirements worklist` |
| Task 8 | CLOSED / PASS | `a1429f62f2f965f7ea6cf91b654a3b4d6d3f272e` `feat(website): preserve requirements on promotion` |
| Task 9 | CLOSED / PASS candidate | Security release `37/37`; complete matrix green |

Task 2 also retains its focused post-implementation foundation regression commit `4f4b4ee`.

## Bootstrap Evidence

The required fresh local reset was run with `npx supabase db reset`. It stopped at the known pre-migration invariant `23503/OP_01_AUTH_ACCOUNT_MISMATCH`. Recovery used only the repository-approved fixture:

```powershell
npx supabase db query --local --file supabase/local-bootstrap/operator-auth-identities.sql
npx supabase migration up --local
```

The fixture and migration continuation succeeded. No ad-hoc `auth.users` insert, `docker exec` SQL mutation, handwritten bootstrap SQL, linked project, remote database, or remote recovery path was used.

`REPOSITORY_APPROVED_BOOTSTRAP_USED=JA`
`AD_HOC_AUTH_USERS_INSERTS=NEE`

## Executed Test Matrix

### Database

| Suite | Result |
|---|---:|
| `supabase/tests/website_requirements_foundation_v1.sql` | `40/40 PASS` |
| `supabase/tests/website_requirements_intake_sync_v1.sql` | `90/90 PASS` |
| `supabase/tests/website_requirements_lifecycle_v1.sql` | `68/68 PASS` |
| `supabase/tests/website_requirement_verification_v1.sql` | `58/58 PASS` |
| `supabase/tests/website_requirements_promotion_v1.sql` | `42/42 PASS` |
| `supabase/tests/website_requirements_security_release_v1.sql` | `37/37 PASS` |
| `supabase/tests/project_requirements_board_v1.sql` | `179/179 PASS` |
| `supabase/tests/website_concept_pre_project_v1.sql` | `173/173 PASS` |
| `supabase/tests/website_execution_workspace_v1.sql` | `12/12 PASS` |
| `supabase/tests/website_project_files_phase_a_v1.sql` | `254/254 PASS` |
| `supabase/tests/operator_mfa_aal2_authority_v1.sql` | `7/7 PASS` |
| Total | `960/960 PASS` |

### Edge And Shared Runtime

| Command | Result |
|---|---:|
| Shared verification/policy/cursor/provider/service Deno command | `77/77 PASS` |
| `deno test --allow-env --allow-read supabase/functions/commercial-operator-command/handler.test.ts` | `164/164 PASS` |
| `deno check supabase/functions/commercial-operator-command/index.ts` | `PASS` |
| Counted tests | `241/241 PASS` |

### Frontend And Repository Gates

| Command | Result |
|---|---:|
| Four-file Requirements/Execution/Project Files/Workspace Node command | `167/167 PASS` |
| `npm run test:page-end` | `8/8 PASS` |
| `npm run test:visual-contract` | `7/7 PASS` |

No result was inherited from an earlier task; every command above was rerun during Task 9.

## Acceptance Matrix

| Acceptance ID | Result | Executable evidence |
|---|---|---|
| `PRE_PROJECT_REQUIREMENTS_WITHOUT_QUOTATION` | PASS | Foundation, intake sync, security release |
| `PRE_PROJECT_REQUIREMENTS_WITHOUT_QUOTATION_ACCEPTANCE` | PASS | Lifecycle and security release null-project fixture |
| `PRE_PROJECT_REQUIREMENTS_WITHOUT_INVOICE` | PASS | Security release authority snapshot delta `0` |
| `PRE_PROJECT_REQUIREMENTS_WITHOUT_PAYMENT` | PASS | Security release payment snapshot delta `0` |
| `CUSTOMER_INTAKE_TO_STRUCTURED_WORKLIST` | PASS | Intake sync `90/90` |
| `NO_DUPLICATE_REQUIREMENTS_AFTER_RESYNC` | PASS | Intake sync plus rejected A/B sync in security release |
| `PERSISTENT_PROGRESS` | PASS | Lifecycle, frontend refresh/state synchronization, security release |
| `START_BLOCK_COMPLETE_REOPEN` | PASS | Lifecycle `68/68` |
| `SOURCE_RESOLUTION` | PASS | Lifecycle `68/68` |
| `TASK3_IDEMPOTENCY` | PASS | Lifecycle replay/conflict plus security release replay |
| `TASK3_BOARD_PROJECTION` | PASS | Lifecycle projection and A-only security projection |
| `TASK5_BROWSER_EDGE_ROUTING` | PASS | Handler `164/164` and caller-JWT SQL ACL checks |
| `AUTHORITATIVE_AUTO_CHECKOFF` | PASS | Verification `58/58`; browser PASS rejected in security release |
| `AUTHORITATIVE_EXTERNAL_CHECKOFF` | PASS | Empty EXTERNAL registry and exact rejection |
| `AUTO_EVIDENCE_BOUND_TO_CURRENT_WORKSPACE` | PASS | Verification substitutions and A/B authority rejection |
| `TASK4_EVIDENCE_SCHEMAS` | PASS | Verification SQL and shared verifier Deno tests |
| `TASK4_VERIFICATION_IDEMPOTENCY` | PASS | Verification replay/conflict/concurrency; rejected attempts insert zero rows |
| `TASK4_HYBRID_COMPLETION_BRIDGE` | PASS | Verification SQL bridge cases |
| `MANUAL_CORRECTION_REOPEN` | PASS | Lifecycle and verification regressions |
| `AUDIT_HISTORY` | PASS | Immutable ACLs, exact accepted event, zero rejected events |
| `CROSS_DOSSIER_ISOLATION` | PASS | Synthetic A/B read, sync, lifecycle, verification and promotion substitutions |
| `DETACHABLE_REQUIREMENTS_WINDOW` | PASS | Frontend managed-workspace suite |
| `SECOND_CLICK_FOCUSES_EXISTING_WINDOW` | PASS | Frontend singleton suite |
| `NO_DUPLICATE_WORKSPACE_AUTHORITY` | PASS | SQL one-context/one-workspace/one-board count and frontend singleton |
| `INTEGRATED_AND_DETACHED_STATE_MATCH` | PASS | Shared Website board authority and frontend invalidation/refetch |
| `LOGOUT_REVOKE_CONTEXT_SWITCH_INVALIDATES_WINDOW` | PASS | Frontend workspace/Requirements invalidation tests |
| `PRE_PROJECT_TO_OFFICIAL_PROJECT_CONTINUITY` | PASS | Promotion `42/42`, frontend promotion tests, A/B promotion rejection |
| `TASKS_2_TO_9_REGRESSION_PASS` | PASS | Complete database, Deno, Node and public-page matrix above |

`TASK9_ACCEPTANCE_IDS=28/28 PASS`

## Synthetic Isolation And No-Write Evidence

`supabase/tests/website_requirements_security_release_v1.sql` creates two synthetic dossiers with distinct quote request, intake, concept, `website_work_context_id`, workspace, board and requirement identities. It executes mixed A/B substitutions across board read, intake sync, lifecycle mutation, trusted verification authority and promotion.

Observed contract:

- Context A projection contains only the A requirement and no B requirement or B repository node metadata.
- Mixed quote/context read and sync fail closed.
- A lifecycle command cannot target the B requirement and leaves B revision unchanged.
- An authenticated browser owner cannot manufacture verification PASS/evidence.
- Service-role verification authority cannot substitute a B requirement under A context.
- Cross-dossier promotion creates neither a command ledger row nor a promotion event.
- One accepted lifecycle mutation creates exactly one immutable event; replay creates no duplicate write.
- One Website context retains exactly one workspace and one board.

The in-transaction authority snapshot compared before and after all accepted/rejected release checks and produced exact equality. Recorded deltas:

| Authority | Delta |
|---|---:|
| `commercial_projects` | `0` |
| `project_requirements_boards` / `project_requirements` | `0 / 0` |
| `payment_evidence` / `payment_expectations` / `payment_reconciliations` | `0 / 0 / 0` |
| `sdf_m1_invoice_candidates` / `sdf_m1_invoice_issuances` | `0 / 0` |
| `quote_request_email_jobs` / quotation email orchestrations | `0 / 0` |
| `website_repository_provisioning_operations` | `0` |
| `preview_access` / `preview_sessions` / `preview_versions` | `0 / 0 / 0` |
| rejected promotion events | `0` |

No repository create/write, GitHub mutation, commit, push, build, preview mutation, publication, deployment, invoice, payment, mail or production-release action was reachable from the tested Requirements paths. The Project Files provider dependency graph remained read-only.

## Authority And Security Closure

- Website Requirements authority remains exact `website_work_context_id + quote_request_id` with one context-bound board.
- Server-projected permitted actions, requirement/board revisions, idempotency and one-ACTIVE enforcement remain authoritative.
- Commercial Project Requirements remain a separate accepted-commercial-scope root. No copy, merge, nullable authority weakening or polymorphic substitution occurred.
- Promotion preserves the Website context, workspace, board, requirement, event, verification/evidence, repository binding and Project Files identities. It creates no duplicate Website authority.
- Trusted verification ingestion remains `service_role`-only; direct table writes remain denied even to `service_role`.
- Browser/Edge Requirements mutations remain caller-JWT paths. `SERVICE_ROLE_BROWSER_PATH=0`.
- Browser input cannot supply trusted PASS, verification result, evidence ref/SHA, project authority, role, actor, workspace binding, repository ref or commit authority.
- Mismatch responses expose no foreign dossier metadata or raw backend/provider details.
- Project Files, repository and GitHub boundaries remained read-only and independently authorized.

`CROSS_CONTEXT_ISOLATION=PASS`
`COMMERCIAL_REQUIREMENTS_SEPARATION=PASS`
`PROMOTION_CONTINUITY=PASS`
`VERIFICATION_AUTHORITY=PASS`
`NO_WRITE_SNAPSHOTS=PASS`
`PROJECT_FILES_REPOSITORY_GITHUB_BOUNDARY=PASS`

## Git And Release Boundary

Before checkpoint creation, `git diff --check` passed and the only worktree entry was the new security-release test. `deno.lock` was checked by Git object hash after the Deno runs and exactly matched `HEAD` object `134d5eda38130b9f61eb8c84b941e50e1522dc3b`.

Task 9 changes exactly:

- `supabase/tests/website_requirements_security_release_v1.sql`
- `docs/superpowers/checkpoints/2026-09-19-website-work-requirements-closure-verification.md`

Task 9 authorizes no release or Phase A execution:

`PUSHES=0`
`DEPLOYS=0`
`REMOTE_MIGRATIONS=0`
`REMOTE_DATABASE_MUTATIONS=0`
`PRODUCTION_RELEASE_ACTIONS=0`
`TASK10_STARTED=NEE`

Requirements Closure is technically green at the Task 9 boundary. Original Phase A Task 10 verification-only and Task 11 remain separate, unauthorized gates. No push, deployment, remote migration, remote database mutation, repository provisioning or production action may follow without new controller authorization.
