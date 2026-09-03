# Operator Owner-Flow Regression Audit - 2026-09-03

## Decision

`OPERATOR_FUNCTIONAL_BASELINE_RESTORED: YES`

The Dossiers state-consistency, trash-first, Multi-Screen preservation, final dossier-copy controls and six-module automatic-refresh contracts are green. The production-equivalent artifact built and verified successfully, and the complete pgTAP run passed. The authenticated production owner shell was inspected read-only and exposed all six modules. Post-deployment acceptance on the production origin remains mandatory; no real email or customer mutation was performed.

## Six-Module Automatic Refresh Checkpoint

`OPERATOR_AUTOMATIC_REFRESH_BASELINE: CONTRACT PASS / OWNER SHELL PASS`

- Dossiers, Finance, Personnel, Recruitment and Calendar use one shared 8-second lifecycle per mounted module. Messages uses recipient-scoped Supabase Realtime with the same 8-second lifecycle only as fallback/recovery. Manual `Vernieuwen` remains available.
- Dashboard navigation dispatches the active module only after panel visibility changes. The previous module stops its interval; the newly active module starts one interval and requests a prompt refresh. Repeated navigation does not stack timers.
- Only the active, visible and unblocked module requests data. Focus, visibility return and module reactivation request prompt refresh; concurrent calls coalesce; disposal removes timer and listeners.
- Background failures preserve the current valid UI and recover on the next cadence. Dossiers retains canonical selection checks; Finance refreshes only its active tab; Messages preserves its BroadcastChannel invalidation and uses polling only as recovery.
- Open dialogs and active mutations block cadence. Dossiers additionally blocks dirty assignment input; Recruitment blocks vacancy/publication writes; Messages blocks compose/send/mark-read; Finance blocks all owned dialogs.
- Standalone Multi-Screen child modules use the same initializer and own exactly one lifecycle. Workspace lease, Web Locks, BroadcastChannel, refresh-resume, logout and revoke contracts remain unchanged.
- Combined six-module/dashboard/Multi-Screen contracts passed 295/295. The complete frontend/static run passed 438/438. Edge/shared Deno passed 585/585. Focused local Messages authority, Dossiers lifecycle and trash-first pgTAP passed 57/57, 57/57 and 21/21.
- The authenticated production owner shell was observed read-only with OWNER authority and all six module entries. The exact artifact shell also loaded all six entries locally. Artifact authentication cannot be classified on localhost because the production-bound callback-origin contract and cross-origin Supabase session/RPC path correctly fail closed; it must be accepted after deployment on the production origin.

## Eight-Second And Realtime Tuning

- The shared constant is exactly `8000`; the built coordinator fired once after 8.011 seconds in browser instrumentation. Focus/visibility/reactivation remain immediate and coalesced.
- Two local authenticated Supabase clients proved the Messages path: `MESSAGE_PERSISTED_AT=2026-09-03T02:18:13.896495+00:00`, `MESSAGE_VISIBLE_AT=2026-09-03T02:18:14.396Z`, `MESSAGE_LATENCY_MS=500`.
- The recipient received one Realtime event, the canonical list RPC contained one matching message at the first/newest position, unread state was correct and duplicate count was zero.
- Forced websocket disconnect/connect produced two subscription establishments; the next message produced one event and zero duplicates. Reconnect recovery passed.
- Realtime publishes only `operator_message_recipients`, never canonical `operator_messages` content. Forced RLS and a bounded current-active-operator predicate expose only the authenticated recipient's delivery rows; every mutation remains RPC-only.
- Browser-DOM Realtime acceptance remains blocked because the integrated browser replaces the external Supabase SDK with a restricted adapter without `channel`. The checked-in 2.112.3 SRI digest independently matches the CDN bytes, so production code was not changed for this tool-specific interception.
- Browser request load at 8-second cadence is 7.5 ticks/minute: Finance 1 request/tick, Personnel 1, Recruitment 2, Calendar 1, Messages fallback 1. Dossiers owner idle is 5, selected Pending 6, selected Active 11 and selected Trash worst-case 12.
- Worst-case selected-Trash Dossiers load is 90 requests/minute per active Operator: 1 Operator 90, 5 Operators 450, 10 Operators 900 and 20 Operators 1800. Only the active module polls. The burst is bounded but is the known hotspot; no authority endpoints were merged in this focused tuning step.

## Dossiers Continuation Checkpoint

`DOSSIERS_STATE_CONSISTENCY_RESTORED: YES`

- Every full list replacement revalidates selection against the current visible authoritative dataset.
- Manual and cadence refresh can reselect only when the post-load canonical selection and query still match their captured values. A cleared selection cannot be resurrected by an older asynchronous refresh.
- Pending, Active, Archived and Trash counters come from server count/facet routes rather than the visible page length.
- Pending deletion is trash-first; permanent purge is available only from Trash. Historical dossier preview, PDF/download and print controls remain available.
- Synthetic real-browser cases A-K passed on desktop and mobile. Zone/product/filter/search changes, manual refresh, cadence refresh, archive, trash, restore and purge all produced the expected list, selection, detail and counter states.
- The neutral detail state remained visually authoritative after a zone switch and after waiting beyond the refresh cadence: hidden detail panels computed to `display:none`, painted no stale customer content and produced no horizontal overflow.
- Local lifecycle transitions proved Pending 1->0 / Trash 1->2, Trash 2->1 / Pending 0->1, and Trash 1->0 after permanent purge. All destructive records were synthetic and local.
- `PRODUCTION_DESTRUCTIVE_MUTATION: NO`.

## Final Dossier Action Controls Checkpoint

`FINAL_DOSSIER_ACTION_CONTROLS_RESTORED: YES`

- A distinct non-destructive `Dossierkopie` block now exposes the exact owner controls `Preview`, `Download PDF` and `Afdrukken` before lifecycle and destructive actions.
- All three controls reuse `application-dossier-copy.js`; no second presentation, PDF, download or print pipeline was introduced.
- Availability is explicit and tested: Active, Archived and Trash Website dossiers with a server-issued immutable `application` are supported. Pending Website records, Website details without `application`, and Slimme Documentenflow records are unsupported and keep the block hidden.
- Actions capture the current visible authoritative selection and immutable application. After the lazy import resolves, both are revalidated; a cleared or changed selection fails closed.
- Selection change or clear closes the preview and removes its reference and rendered content. A hidden old modal action produced no download after the selected record left the visible dataset.
- Built-artifact acceptance passed for two Website dossiers. Dossier 1 rendered reference `LWS-AAN-2026-0099`, customer `Alpha Local Dossier`, seven preview sections, a 3,275-byte `%PDF-` file named `aanvraag-LWS-AAN-2026-0099.pdf`, and matching print HTML/CSS. Dossier 2 independently rendered `LWS-AAN-2026-0100` / `Beta Local Dossier`, a 3,274-byte `%PDF-` file with the matching filename, and matching print HTML/CSS.
- The first dossier preview was closed and fully emptied before dossier 2 rendered. Switching to Pending left zero selected cards, hid the controls, closed and emptied the dialog, and prevented a programmatic old download action.
- The requested post-controls browser cadence repetition could not be classified: a second integrated-browser context stalled before `createClient` while external deferred bootstrap remained pending. The previously completed 6.651-second automatic refresh result and current executable cadence contracts remain green, but they are not represented as a new post-controls browser PASS.
- `PRODUCTION_DESTRUCTIVE_MUTATION: NO`.

## Multi-Screen Preservation Checkpoint

`MULTISCREEN_ENTRY_CONTROL_PRESERVED: YES`

- Root cause of the locally missing button was the module-only QA harness: it initialized Dossiers without the dashboard workspace master, so the fail-closed launch control correctly remained hidden. The real owner dashboard shell binds and reveals it only after workspace acquisition.
- The final built `/operator/dashboard/?module=dossiers` route displayed `Open in nieuw venster` followed by `Vernieuwen` in the production control group.
- The master-generated child URL targeted `/operator/window/?module=dossiers`, included only workspace bootstrap identifiers, and contained no role or token authority. The child independently authorized, joined the workspace, mounted the current Dossiers initializer and remained unlocked.
- A second launch focused the existing managed child instead of opening a duplicate. Master refresh resumed the workspace from history state without locking the child. Logout revoked the workspace and closed the child.
- Synthetic local external-request authority changed the Pending counter from 1 to 2 and added `#AA000099` to the queue automatically in 6.651 seconds, with no manual refresh or browser reload.
- The selected card now uses the existing turquoise Operator selected state, retains its lifecycle badge and exposes exactly one `aria-current="true"`. Clearing selection removes the selected styling.
- The Active assignment form now activates its existing isolated `assignment-form` layout: operator, reassignment reason and Save controls render as a stable two-column grid without page overflow.

## Classification

- A: historical behavior restored without reducing existing functionality.
- B: current behavior is intentional and supported by historical/server-authority evidence.
- C: test or fixture drift; runtime behavior is not changed to satisfy the stale expectation.
- D: unresolved acceptance item or release blocker.

## Owner Module Matrix

| Module | Before | Current | Expected | Class | Exercised controls and boundary | Visual result | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Dossiers | Historical list refresh ran every 25 seconds while visible. | Shared 8-second active-module cadence; quiet failure recovery; dirty assignment, command and dialog blocking; canonical selection guard retained. | Preserve only a still-visible selection; neutral detail after dataset changes; no polling while blocked or inactive. | A | Manual/cadence refresh, lifecycle, exact copy controls, server counters and standalone registration. | Contract PASS; prior synthetic browser A-K PASS; new real-owner run blocked. | PASS (contract) |
| Finance | No reliable automatic refresh across the active Finance surface. | Shared cadence force-refreshes only the active tab; open owned dialogs block; current data survives failure. | No inactive-tab requests or form overwrite. | A | Active-tab, failure/recovery, dialog and disposal contracts. | 12/12 focused refresh/Finance tests passed. | PASS (contract) |
| Workforce / Personnel | Read-only projection required manual refresh. | Shared cadence updates only while active and preserves valid rows through failure. | Preserve read-only behavior; do not invent a mutation. | A/B | Read projection, active-panel gating, failure/recovery and standalone registration. | 10/10 focused combined tests passed. | PASS (contract) |
| Recruitment | Vacancy/publication authority existed without reliable cadence. | Vacancy and publication controllers refresh together; dialogs and mutations block. | Preserve every existing write and never overwrite an edit. | A/B | CRUD/publication authority, active gating and failure/recovery. | 8/8 focused combined tests passed. | PASS (contract) |
| Messages | BroadcastChannel invalidation existed but had no cross-session Realtime delivery. | Recipient-scoped Supabase Realtime plus BroadcastChannel and 8-second active fallback; compose/send/mark-read block. | Immediate delivery without exposing message content; recover missed events without draft overwrite. | A/B | Two authenticated local contexts, persist/websocket/list projection, reconnect, fallback and cleanup. | 500 ms measured; one event; zero duplicates; reconnect PASS. | PASS (integration) |
| Calendar | Calendar projection required manual refresh. | Shared cadence quietly reloads the active range/view; current table survives failure. | Preserve navigation/view and block inactive requests. | A/B | Date controls, range/view preservation, failure/recovery and standalone registration. | 7/7 focused combined tests passed. | PASS (contract) |

## Shared Navigation, Auth And Multi-Screen

| Surface | Evidence | Result |
| --- | --- | --- |
| Owner module navigation | Dossiers, Finance, Workforce, Recruitment, Messages and Calendar route/load contracts are covered in the 438-test frontend run. | PASS |
| Multi-Screen protocol | Web Locks duplicate denial, BroadcastChannel hints, six module URLs, duplicate focus, server lease renewal/status, revoke, sign-out, expiry and fail-closed behavior are covered in `operator-workspace.test.mjs`. No token/role authority is placed in child URLs or Web Storage. | PASS (contract) |
| Authenticated browser master/child session | The built dashboard and child routes passed with the safe synthetic-local authority adapter, including independent child join, duplicate focus, refresh resume and logout close. The authenticated production owner shell was also observed read-only with OWNER authority and all six modules; no production lease was mutated. | PASS (synthetic-local flow) / PASS (production shell) |
| Cache delivery | Dashboard/window guards, registry and all six module imports use `20260903-auto-refresh-8s`; unchanged CSS remains on `20260903-owner-flow-audit`. | PASS (source contract) |

## Cross-Boundary Flows

| Boundary | Before / defect | Current / expected | Server connection | Result |
| --- | --- | --- | --- | --- |
| Intake notification creation | A newer partial unique index made the predecessor's unqualified `ON CONFLICT` target invalid. | Forward-only migration restores the matching partial conflict target. | PostgreSQL function authority; focused pgTAP 2/2 and lifecycle/reminder set 56/56. | PASS / A |
| Intake lifecycle expiry | An old test still expected seven days after reminders changed the canonical cycle. | Shared authority remains fourteen days, with reminders at days 3, 7 and 13; constructors retain no local fallback. | Commit `133678d`; PostgreSQL shared expiry authority. | PASS / C |
| Intake/application concurrency | Fixed identities and incomplete cleanup made reruns collide with current triggers. | Unique synthetic identities and trigger-complete cleanup. | Local Supabase and Edge integration only. | PASS / C |
| SDF confirmation subject | One provider assertion expected obsolete copy. | Assertion now matches the canonical deliverability subject; template source was not changed. | Shared email template to automation provider payload. | PASS / C |
| Customer/intake/document/quotation boundaries | Seven synthetic local integration/concurrency flows completed consecutively. | Server-owned mutation and cleanup paths remain authoritative. | Local Supabase/Edge only; no production mutation or delivery. | PASS |

## Validation Evidence

- Frontend/static contracts: 438/438 passed after 8-second and Realtime tuning.
- Combined six-module/dashboard/Multi-Screen contracts: 295/295 passed.
- Multi-Screen focused contracts: 35/35 passed. Auth focused contracts: 47/47 passed.
- Focused Dossiers/dashboard/Auth/Multi-Screen contracts: 308/308 passed after the final controls; the Dossiers-only slice passed 14/14 after each edit.
- Focused Operator auth/dashboard/Dossiers/Finance/Multi-Screen: 315/315 passed.
- Edge/shared Deno tests: 585/585 passed in this session.
- Commercial Operator Edge subset: 138/138 passed.
- Operator dossier lifecycle pgTAP: 57/57 passed locally and rolled back.
- Dossier trash-first restoration pgTAP: 21/21 passed locally and rolled back.
- SDF provider/template subset: 36/36 passed.
- Operator module-authority pgTAP subset: 900 assertions across 23 files passed.
- Intake lifecycle/reminder/conflict pgTAP: 56/56 passed.
- Seven local integration/concurrency flows passed consecutively.
- Complete pgTAP run: 136 files, 5,004 assertions, PASS.
- Production-equivalent Pages artifact: 428 files; verifier reported zero forbidden files, broken links, Functions/social/Auth mismatches, missing files and legacy paths.
- Release-island classification: `WEBSITE_CHANGED_BY_RELEASE: NO`, `SDF_RUNTIME_CHANGED_BY_RELEASE: NO`, `MARKETING_CHANGED_BY_RELEASE: NO`.
- Diagnostics for changed refresh, Messages and SQL files: no errors.

## Release Readiness

The twelve historical pgTAP fixtures were aligned with current authority without weakening runtime contracts: hard-delete fixtures now transition through Trash, VAT fixtures use canonical provenance, SDF fixtures confirm required scope classification, and Operations Manager fixtures create authoritative submitted SDF intakes. The complete clean run passed all 136 files and 5,004 assertions.

Website and Marketing protected surfaces have no release diff. SDF customer runtime has no release diff; SDF-named changes are fixture alignment around existing classification and projection authority. Operator, database authority and build-artifact changes are the release scope.

All pre-release blockers are closed. Commit and forward-only push are permitted after the final diff check. Production acceptance remains a post-deployment gate and must use the real production origin; localhost callback adaptation is not accepted as a substitute.