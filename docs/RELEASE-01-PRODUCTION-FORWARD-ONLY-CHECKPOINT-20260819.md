# RELEASE-01 Production Forward-Only Checkpoint

Status date: 2026-08-19

## Production Authority

- Repository: `lorenzobombello-max/lorenzo-web-studio`.
- True remote `main`: `5592804b7c3c6b5e347ec0946bcf3ef552e92c2c`.
- Fetched `origin/main`: `5592804b7c3c6b5e347ec0946bcf3ef552e92c2c`.
- Latest GitHub Pages production deployment: ID `5959625202`, SHA `5592804b7c3c6b5e347ec0946bcf3ef552e92c2c`, state `success`, completed `2026-08-18T09:10:25Z`.
- Sole production authority for this checkpoint: current remote production `main`, which equals the current successful Pages SHA.

## Hard Release Contract

1. Every production release is built forward from freshly fetched current remote `main` and the current production HEAD.
2. Old worktrees, branches, backups, ZIP files, Golden Masters, Customer Core copies, and historical snapshots are read-only reference or recovery sources. They are never direct production release sources.
3. A historical change may return only as a targeted delta, cherry-pick, or forward port on current remote `main`, with evidence that unrelated production bytes remain unchanged.
4. Force push, history rewrite, and resetting production `main` to an older state are forbidden.
5. Any deviation is a hard stop.

## Preservation Gate Record

Configured VS Code workspace roots:

- `C:/Users/info/OneDrive/lorenzo-web-studio`: present Git worktree, branch `main`, local HEAD `a1f3ecf719efc9dd541e7148c0ec7f7d4ba788eb`, ahead 2 and behind 59 relative to `origin/main` at gate time.
- `C:/Users/info/OneDrive/LWS-private-docs`: configured but not present on disk at gate time.

Original main worktree at gate time:

- worktrees found: 35 total, consisting of the original main worktree plus the 34 historical worktrees listed below;
- staged files: 0;
- unstaged files: 30;
- untracked files: 40;
- total porcelain entries: 70;
- preservation rule: do not reset, restore, clean, stash, stage, or include these files in RELEASE-01.

The exact gate output is represented by Git itself in the untouched original worktree. RELEASE-01 was created in a separate worktree from exact remote-main SHA `5592804b...`, never from local `main`.

## Historical Worktrees And Branches

All pre-existing non-authoritative worktrees found at the gate are historical release sources:

| Worktree suffix | Branch or state | HEAD |
|---|---|---|
| `lws-hero-descenders-worktree-20260814` | `fix/hero-descenders` | `20e3276` |
| `lorenzo-web-studio-budget-guard-compat` | `fix/budget-guard-cache-compat-20260811` | `28d6a3b` |
| `lorenzo-web-studio-rollback` | `rollback/package-clarity-20260811` | `1d41dbc` |
| `budget-guard-final-release-20260816` | detached | `74636ab` |
| `budget-guard-freeze-production-20260816` | `fix/portfolio-regression-live-20260816` | `26d778b` |
| `budget-guard-v2-freeze-20260816` | `chore/budget-guard-v2-contract-freeze-20260816` | `9f61650` |
| `content-completion-20260813` | `feature/process-about-faq-content-20260813` | `fc640a1` |
| `d3e1-d3e10-integration-20260815` | `integration/d3e1-d3e10-production-baseline-20260815` | `cf6b1ad` |
| `d3e9-public-acceptance-20260815` | `feature/d3e9-public-quotation-acceptance-20260815` | `20e3276` |
| `dark-intake-release-20260816` | `release/dark-intake-20260816` | `a5bf5a0` |
| `faq-g-release-20260818` | detached | `345c8d9` |
| `intake-i1-hosting-normalization-20260813` | `fix/intake-i1-hosting-normalization-20260813` | `74ac8ff` |
| `intake-save-production-20260816` | detached | `3867b6b` |
| `intake-save-reopen-20260816` | `fix/intake-save-reopen-20260816` | `98714e6` |
| `language-pricing-20260816` | `fix/budget-guard-v2-language-pricing-20260816` | `5a3afeb` |
| `mobile-root-canvas-20260813` | `fix/mobile-root-canvas-20260813` | `24fd33a` |
| `operator-auth-deploy-20260817` | `deploy/operator-auth-session-path-20260817` | `515fda4` |
| `operator-dashboard-20260818` | detached | `4807b81` |
| `phase5o-r-service-role-remediation-20260816` | `phase5o-r/service-role-privilege-remediation-20260816` | `26d778b` |
| `phase5o-r2-trigger-acl-remediation-20260817` | `phase5o-r2/trigger-function-acl-remediation-20260817` | `26d778b` |
| `phase5o-r3-null-guc-remediation-20260817` | `phase5o-r3/null-guc-guard-remediation-20260817` | `26d778b` |
| `phase5p-b-migration-packaging-20260816` | `phase5p-b/migration-packaging-remediation-20260816` | `26d778b` |
| `phase5p-i-operator-auth-20260817` | `phase5p-i/operator-auth-session-path-20260817` | `26d778b` |
| `post-auth-owner-checkpoint-20260817` | `docs/post-auth-owner-session-20260817` | `1f68782` |
| `preview-semantics-20260811` | `integration/preview-budget-semantics-20260811` | `a9e936e` |
| `pricing-catalog-v1-20260812` | `feature/pricing-catalog-v1-20260812` | `e54ec3b` |
| `pricing-integration-20260812` | `integration/pricing-catalog-v1-20260812` | `c8ac524` |
| `production-db-release-20260812` | detached | `24fd33a` |
| `professional-semantics-tests-20260813` | `fix/professional-semantics-regressions-20260813` | `6f3951c` |
| `r3-migration-source-reconciliation-20260817` | `reconcile/r3-migration-source-20260817` | `7830895` |
| `service-details-20260813` | `feature/service-detail-pages-20260813` | `6bb4c29` |
| `slimme-documentenflow-20260817` | `feature/slimme-documentenflow-20260817` | `e690204` |
| `typography-descenders-20260816` | `fix/commercial-heading-descenders-20260816` | `21fb63c` |
| `website-p1-completion-20260813` | `fix/website-p1-completion-20260813` | `4bf37e3` |

The old local branches shown by `git branch --all` are governed by the same historical-source rule, including `branding-revert*`, `temp-branding-revert-check`, `prepublish-cleanup-audit`, all `feature/*`, `fix/*`, `integration/*`, `phase5*`, `reconcile/*`, `release/*`, and `rollback/*` refs other than current remote `main`.

## Protected Baseline And Pre-Release Gate

`.release/production-preservation.json` registers protected paths for global layout, fonts/typography, header, footer, responsive/mobile basis, intake pricing/Budget Guard, operator auth, documentenflow, and the production build/deployment contract. These paths may change only when explicitly listed in a release scope.

Before staging or pushing, create a release scope based on `.release/scopes/RELEASE-01.json`, then run:

```powershell
./scripts/test-production-release.ps1 -ScopeFile .release/scopes/<release>.json
```

The gate fetches remote `main`, verifies the true remote SHA, proves the release branch is not behind and is based forward-only on it, prints the exact diff and staged/untracked lists, requires zero unexpected files, requires zero undeclared protected/generated changes, and runs `git diff --check`. A declared historical source requires written forward-port proof. Any mismatch is a hard stop. Full historical file restores are forbidden unless explicitly scoped and preservation-proven.

## Post-Deployment Regression Contract

GitHub Pages `success` is necessary but not sufficient. Every relevant deployment must verify all affected public routes. A layout-related release must check desktop, mobile, horizontal overflow, footer/page-end, the relevant page behavior, and console/startup errors. Record the tested production SHA, routes, viewports, results, and reviewer. RELEASE-01 performs no broad visual audit.

## Visual Baseline Strategy

`.release/visual-baselines/manifest.json` starts empty. Register desktop/mobile references only after an individual page is explicitly accepted. References are review evidence, not automatic approval; unexpected layout, font, footer, or spacing differences block release pending review.

## Exact RELEASE-01 Status And Resume

- Isolated worktree: `C:/Users/info/Project-Worktrees/lorenzo-web-studio-release-01-forward-only-20260819`.
- Branch: `release/production-forward-only-protection-20260819`, created directly at remote-main authority `5592804b...`.
- Local governance commit: the commit containing this checkpoint; it is not a production authority unless later reviewed and forward-integrated from then-current remote `main`.
- Production website files changed: no.
- Supabase code, configuration, migrations, functions, secrets, or data changed: no.
- Pushes: none.
- Deployments: none.
- Next session must start by reading this checkpoint and running the preservation gate against freshly fetched remote `main`.
- Exact next task: `GLOBAL-MOBILE-01` root-cause analysis and repair.
- Do not start `GLOBAL-MOBILE-01` in RELEASE-01.