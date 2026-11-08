# Astro preview dispatch (local MVP-045B)

This implementation is inactive until its migration, Edge functions, reviewed
workflow revisions, configuration and deadline scheduler are separately approved
and released. Writing the migration does not apply it or activate a scheduler.
There is no production verification implied by local unit or static tests.

## Request and authority

For dossier 006 only, the existing preview request first acquires an actual
OWNER/AAL2 file-read lease and calls the existing server-side provider's
`resolveSnapshot`. That verifies the private repository identity, default branch
and marker at the resolved commit. A service-role-only reconciliation RPC consumes
that 15-second authority, checks the old projection by CAS, records a separate
audit row and updates `last_commit_sha`. It never fabricates a file write.
The acquired preview and dispatch both receive the verified SHA, not the old UI
projection. No new client proof or navigation action is accepted.

The reconciliation migration `20261108000100` restricts the quote, context,
workspace, canonical operation and repository identity to 006. It installs no
data patch. Finalization takes the preview lifecycle gate before operator,
context, workspace, canonical operation and read-lease locks; expiry is checked
after waiting. Revoked owners, changed bindings, stale CAS, valid write/build
leases and any unresolved dispatch (including expired UNKNOWN) fail closed.
Terminal history is never removed to allow retry. Other dossiers' existing
request behavior is unchanged.

The Operator request acquires its existing OWNER/AAL2 preview authority once.
A separate durable claim records `ATTEMPTED` before any GitHub dispatch. The
customer repository binding and exact workspace commit are revalidated in the
database. The workflow SHA must also exist in the database's protected
`website_project_preview_workflow_revisions` allowlist. That table is deliberately
empty in this migration; no runtime principal can populate it.

One claimed attempt makes one POST to the platform's existing
[Astro workflow](../.github/workflows/build-website-project-preview.yml).
Only HTTP 204 means accepted. Definite 400/401/403/404/422 responses are rejected;
other responses, transport failures and uncertain delivery remain `UNKNOWN`.
There is no automatic redispatch. A process crash after the claim can leave
`ATTEMPTED`; the deadline handles that case without guessing whether GitHub
received the request. This is at-most-once initiation, not exactly-once delivery.

The Operator displays requested, queued, uncertain and executing states
separately. Polling reads status; it never creates another request.

## Worker boundary

Source-token issuance verifies GitHub OIDC signature, audience, platform
repository/id, branch, workflow path, exact reviewed workflow SHA, event and
`run_attempt=1`. Only then does an atomic run claim bind the lease/build to one
workflow run. Replaying a source claim, a different run and GitHub reruns fail.
The source response supplies canonical customer repository/id/commit metadata;
the workflow compares its inputs with that authority before customer checkout.

Artifact-token issuance verifies the same OIDC identity and already-claimed run.
Finalization revalidates the current binding and serializes against failure and
expiry using the same advisory lock. Legacy actor finalizers reject managed
leases; unmanaged legacy builds keep their previous behavior.

### MVP-045D lock and release correction

Every preview lease acquisition, dispatch/run claim, legacy release/finalizer,
success/failure transition and expiry batch enters one transaction-scoped
`website-project-preview-lifecycle:v1` advisory gate before its row locks.
This intentionally serializes short preview transactions across workspaces.
Never hold this transaction open across HTTP, a build or Storage I/O.
Callers must enter through the public wrappers, without first taking other
application row locks in the same transaction. Administrative maintenance must
take the same gate first or quiesce callers; arbitrary external SQL is not covered.

Where authority rows are needed, their order matches file-write acquisition:
operator, work context, workspace, canonical operation. Lease locks then follow
source-writelease, previewlease, dispatch record. Success already owns both
lease locks before the retained upload finalizer takes its session lock.
Existing per-file upload/abort transactions do not acquire the lifecycle gate
after a session lock. They must retain that property.

Authorization re-reads release/expiry after the blocking authority/lease locks.
Acquisition checks its retained helper's result before returning; expired or
released authority raises an exception and rolls back that acquisition.
Dispatch claim repeats the check after the workflow-approval lock, immediately
before INSERT; run claim repeats it after the dispatch-row lock, immediately
before UPDATE. These are `clock_timestamp()` checks, not transaction-start time.
Failure cleanup deliberately does not require an unexpired lease or an active
actor. A terminal replay reports no transition internally; the expiry integer
counts only newly applied `DEADLINE_EXCEEDED` transitions.
The transition flag is stripped from public failure/outcome results.

The old release RPC rejects every managed lease (including terminal ones) with
`42501 / PROJECT_PREVIEW_MANAGED_RELEASE_FORBIDDEN`. It is not a cancellation
API. Unmanaged leases delegate to the retained original implementation,
including its actor check, idempotent release and existing AAL behavior.
No dispatch record is removed to enable a second attempt.

## Build and artifact behavior

The existing fetch/build/upload separation remains. The build job has no GitHub
permissions or OIDC access. Its non-root, read-only-root container receives only
source, an internal network and the npm proxy. The LF configuration directory is
mounted read-only, without anonymous config volumes. A network gate requires
direct egress denial, registry CONNECT 200 and non-registry CONNECT 403 before
`npm ci --ignore-scripts`; npm fetch retries are disabled.

Static output is checked before artifact transfer and again before upload.
Unknown extensions and mismatched extension/media-type pairs are rejected by
the upload service as well. HTML continues through the existing sanitizer;
hashes describe the final sanitized bytes, not necessarily raw build bytes.
SVG remains deliberately unsupported. The proven customer output therefore
has six accepted files and two rejected SVG files, leading to
`PASS_WITH_WARNINGS`, not an unrestricted visual-acceptance claim.

## Completion, deadline and cleanup

The [completion workflow](../.github/workflows/complete-website-project-preview.yml)
uses its own OIDC identity and runs only trusted platform code. It never
downloads or executes customer artifacts. The service independently reads the
original GitHub run and jobs, checking repository, workflow path/revision, event,
attempt, run ID and lease/build correlation before classifying a failure.

Fetch/build/upload errors, cancellation and timeout create a FAILED build and
release only the associated preview/source leases. A workflow reporting success
without an already-committed artifact finalization becomes `FINALIZATION_MISSING`.
An existing PASS/PASS_WITH_WARNINGS always wins over a late callback.

The trusted [deadline entrypoint](../supabase/functions/website-project-preview-completion/deadline.ts)
expires at most 100 pending dispatches per invocation and checks at most 100
failed-build cleanup candidates. Only dossier006 is eligible for this scheduled
sweep: migration `20261108000300` fixes the
quote/context/workspace in database authority for expiry, candidate enumeration,
storage-path authorization and cleanup recording. The deadline adapter permits
only these four scoped RPCs. Existing general worker contracts are unchanged.
Local two-dossier PostgreSQL fixtures verify the other dossier's full lease,
source lease, dispatch, upload and file evidence remains unchanged; a transport
test verifies only authorized storage paths are removed.
The existing completion function exposes
`POST /website-project-preview-completion/deadline`, requiring the dedicated
`LWS_PREVIEW_DEADLINE_AUTOMATION_SECRET` (32–256 bytes); it never accepts caller
build IDs or paths. Other completion requests still require GitHub OIDC.
Migration `20261108000200` adds administrator-only registration/invocation/removal
functions using the existing pg_cron, pg_net and Vault installation. It does not
activate a job during migration. Provision the same secret in Vault as
`website_project_preview_deadline_secret`, deploy the endpoint, then explicitly
call `schedule_website_project_preview_deadline_v1()` to register one minute job.
The destination is fixed to this production project's completion endpoint.
Never put the secret in a cron command, frontend, evidence file or command output.
Check both `cron.job_run_details` and `net._http_response`: queue acceptance is
not sweep success. Require HTTP 200 with `ok:true`; timeout, 401 and 503 stop
release acceptance. Errors return only `PREVIEW_DEADLINE_SWEEP_FAILED`, never
provider details. `unschedule_website_project_preview_deadline_v1()` stops only
this job without deleting leases, dispatches or evidence.
Storage removal uses only database-derived file paths under that build's UUID.
Failures are surfaced, never reported as successful cleanup.

Failed builds remain eligible for periodic cleanup after a two-minute delay,
rotating by last cleanup check. Repeated *cleanup checks*, unlike dispatch
retries, are deliberate: an in-flight Storage write may settle after an initial
cleanup. There is no terminal transition back to RUNNING or PASS.

## Release prerequisites (not performed here)

1. Review and apply the prerequisite migrations and the new local draft only
   under separate authorization. Run the supplied
   [SQL contract scenario](../supabase/tests/website_project_preview_dispatch_v1.sql)
   using disposable pre-seeded OWNER/AAL2 fixtures, never production fixtures.
   The file is not a self-provisioning database test.
2. Verify real two-session contention: duplicate claims; two run claims;
   finalization versus failure/expiry; owner revocation or repository rebinding;
   upload abort/in-flight cleanup. Static text tests and mocked RPCs do not
   prove database transaction behavior.
3. Run filesystem/symlink tests on a permitted environment. Windows without
   symlink privilege cannot run all of the existing filesystem cases.
4. Reuse the existing `LWS_DELIVERY_PDF_DISPATCH_APP_ID`,
   `LWS_DELIVERY_PDF_DISPATCH_INSTALLATION_ID` and
   `LWS_DELIVERY_PDF_DISPATCH_PRIVATE_KEY` configuration. No new App or copied
   secrets are required. The preview loader deliberately uses the same validated
   platform configuration; it does not fall back to another installation.
   Verify that installation includes `lorenzobombello-max/lorenzo-web-studio`
   (repository ID `1320223175`) and grants Actions write and Metadata read.
   The token broker restricts each token to that single repository and rejects
   unexpected permission levels. The customer repository App is not a substitute.
   Dispatch tokens request Actions write; completion tokens request Actions read.
   Existing PDF dispatch behavior and customer source-token scopes are unchanged.
5. Set `LWS_PREVIEW_WORKFLOW_SHA` to a reviewed platform commit and separately
   approve that same SHA in the protected database allowlist. Dispatch targets
   `main`; movement of main causes OIDC revision rejection rather than building
   under an unreviewed workflow. Keep deployment pins synchronized intentionally.
6. Preserve existing source/artifact OIDC and Storage settings. Configure the
   completion endpoint plus `LWS_PREVIEW_COMPLETION_OIDC_AUDIENCE` and the
   separately reviewed `LWS_PREVIEW_COMPLETION_WORKFLOW_SHA`. Deploy the completion
   function with gateway JWT verification disabled only because its handler
   verifies GitHub OIDC itself, like the existing source/artifact endpoints.
7. Approve and activate a bounded trusted schedule for the deadline entrypoint;
   alert on expiry or cleanup errors. Without that schedule, deadline reads are
   fail-closed but durable expiry/cleanup is not guaranteed to run.
8. Perform one separately approved end-to-end workflow acceptance, including
   artifact hosting, cancellation and finalization. No real workflow dispatch,
   new customer build or production mutation was performed for this local task.

## Transactional stop and rollback contract (not executed)

This is a release gate, not permission to run SQL. The current draft has never
been applied. A production recovery needs its own approved, pinned recovery
script and evidence. Prefer stopped/drained operation over a destructive down
migration. Disabling a reviewed SHA alone is NOT a kill switch: recorded intents,
run claims already admitted, issued tokens and running jobs may still exist.

### Installation evidence and stop conditions

Before any authorized installation, capture the seven displaced public functions:

| Public function and argument types | Retained internal name |
|---|---|
| `acquire_website_project_preview_build_v1(uuid,text,uuid)` | `acquire_preview_pre_dispatch_v1` |
| `release_website_project_preview_build_v1(uuid)` | `release_preview_pre_dispatch_v1` |
| `resolve_website_project_preview_artifact_authority_v1(uuid,uuid,bigint)` | `resolve_preview_pre_dispatch_v1` |
| `finalize_website_project_preview_upload_session_v1(text,uuid,uuid,bigint,text,bigint)` | `finalize_preview_upload_pre_dispatch_v1` |
| `get_website_project_preview_build_status_v1(uuid)` | `get_preview_status_pre_dispatch_v1` |
| `finalize_website_project_preview_build_v1(uuid,text,text,text,bigint,text)` | `finalize_preview_legacy_single_v1` |
| `finalize_website_project_preview_build_v2(uuid,text,text,text,jsonb)` | `finalize_preview_legacy_multi_v2` |

Save OID, namespace/name/identity arguments, `pg_get_functiondef`, `prosrc`,
owner, raw `proacl`, effective ACL including grantor/grantee/grant options,
`prosecdef`, `proconfig`, volatility, comments and dependent object OIDs.
Inventory grants to ALL roles, not only the four named runtime roles: any
unexpected grant surviving on an internal original is a STOP condition.
Record migration SQL SHA256 and the actual `supabase_migrations.schema_migrations`
row/column representation for version `20261027220000` (expected absent before
first install). Do not assume that registry has a checksum column.

In the authorized disposable database, prove that the migration runner commits
DDL, privilege changes and registration atomically. Inject an error after a
function move and before registration; rollback must leave all original OIDs,
definitions, ACLs and registration unchanged and no partial dispatch tables.
An explicit BEGIN missing from a draft is not proof of non-atomic execution.
If the runner separates registration, STOP until an approved transactional
runner/recovery script covers both. Never repair registration by hand afterward.

STOP on missing snapshots, wrong original OIDs, changed definitions/owners/ACLs,
unexpected dependencies, nonterminal dispatches during structural rollback,
unaccounted workers/tokens, lock/statement timeout, or any failed catalog assertion.
No retry, CASCADE, direct system-catalog update, table truncation or forced lease
release is allowed as a recovery shortcut.

### Phase 1: stop intake and drain, retaining completion

1. Pause Operator preview intake and the dispatcher outside the database;
   wait for already admitted HTTP requests to finish. Inventory ATTEMPTED,
   ACCEPTED, UNKNOWN and RUNNING rows and all correlated GitHub runs. Do not
   resend any uncertain dispatch. External control-plane actions need separate
   approval; none are performed by this local correction.
2. In one bounded transaction, take the central gate FIRST, disable the reviewed
   revision allowlist and revoke runtime execution of acquisition and dispatch
   claim. Commit with the stop evidence. Keep run authorization, completion,
   upload finalization and expiry available to drain recorded work. Already
   waiting calls may have passed an EXECUTE check before revocation; revocation
   alone is not proof that those calls vanished. Observe their completion.
3. Allow known workflows to finish, or cancel them only with explicit separate
   permission. Keep the existing completion/expiry/failed-Storage cleanup paths
   active. Unknown delivery must reach the deadline, not be manually reset.
   Verify every dispatch is terminal, associated leases are released, sessions
   are FINALIZED/ABORTED, and cleanup has settled. Preserve successful artifacts.
4. Close source/artifact/completion ingress and disable their invokers only after
   drain. Wait for in-flight database calls, jobs and issued OIDC/receipt/source
   credentials to expire or finish, using their actual configured TTLs. Confirm
   no queued callback can reach a restored legacy route. A late callback during
   drain may only replay the terminal result, never overwrite PASS. A callback
   during structural recovery must be rejected at ingress and by revoked ACLs.
   If any of this cannot be demonstrated, remain stopped with the new lifecycle
   and dedup ledger intact; do NOT restore legacy mutation routes.

### Phase 2: one compensating transaction, no ledger deletion

With ingress stopped and sessions quiescent, begin a bounded recovery transaction
and take the central gate before all row/catalog locks. Recheck terminal/drain
conditions and the seven original OIDs against the saved catalog snapshot.
Revoke all new mutation/authorization RPC grants. Keep the original functions'
captured ACLs for restoration, distinct from the wrappers' temporary stop ACLs.

Drop only the seven new public wrappers using RESTRICT, after enumerating and
explicitly handling dependencies in the approved recovery script. Rename the
seven retained originals and move them back to `public` with ALTER FUNCTION.
Do not recreate the original functions: ALTER retains their OIDs and original
definitions. Restore/verify original owner, configuration, security properties,
comments and exact captured ACLs, including grant options and grantors.
If exact ACL restoration cannot be expressed safely (including a NULL raw ACL
that GRANT/REVOKE cannot reproduce), STOP and roll back; do not edit `pg_proc`.
Catalog comparisons must pass before commit. Restored runtime ACLs do not imply
intake may resume: ingress stays stopped until the recovery acceptance passes.

Retain dispatches, unique lease/build/run constraints, workflow revisions,
leases, upload records, builds and the internal coordination helpers. New
nonlegacy RPCs remain non-executable by runtime roles, even when retained for
audit. These are dedup tombstones, not disposable deployment data.

Keep the original migration registration. Register an approved, separately
versioned compensating recovery migration in the SAME transaction as restoration;
record its pinned checksum externally if the registry has no checksum field.
Do not delete the original version or pretend the retained schema is uninstalled.
Future activation needs a new reviewed forward migration that reuses the ledger,
never a replay of this CREATE TABLE draft. Any later data retirement requires
separate retention approval and proof that no old lease/build/run can authorize
again. Transaction failure leaves both schema and migration registry unchanged.

## Smallest remaining PostgreSQL test phase (not run)

Use only a separately authorized disposable PostgreSQL fixture, not a new
Supabase project or production database. No GitHub dispatch or customer build is
needed. Each contention scenario uses fresh leases and commits its fixture before
starting two independent connections. Set per-connection `lock_timeout='8s'` and
`statement_timeout='15s'`; observe blocking through `pg_blocking_pids`, not sleeps
alone. Hold blockers no longer than five seconds. Never automatically retry.

1. Run the extended SQL contract scenario above with three valid leases. It
   checks managed release denial, unchanged unmanaged AAL1/idempotent release,
   expired authorization without run mutation, one terminal failure, and expiry
   counts 1 then 0. Its fixture edits are rolled back; it does not prove waiting.
2. R1: connection A begins and acquires a preview using the public acquisition
   wrapper, leaving the transaction open. B calls failure finalization for that
   same already-dispatched lease and must wait on the central advisory gate,
   not hold the preview row while waiting for source. Commit A; B must finish
   with one terminal build and both leases released. Repeat with failure first,
   acquisition second, and with an expiry batch over two distinct workspaces.
   No `40P01`, duplicate build or reauthorized terminal lease is acceptable.
   A released/expired acquisition result must now raise LEASE_INVALID rather
   than return stale authority. Also hold an acquisition behind an authority-row
   blocker until its existing lease expires; no valid authority may escape.
3. R3 dispatch boundary: set a fresh lease expiry a few seconds ahead. A locks
   its reviewed workflow-revision row FOR UPDATE. B calls dispatch claim,
   demonstrably waits there, then A commits after the lease deadline. Expect
   `42501 / PROJECT_PREVIEW_LEASE_INVALID` and no dispatch inserted.
4. R3 run boundary: for a committed ATTEMPTED fixture expiring shortly, A locks
   its dispatch row FOR UPDATE directly (test-only blocker). B calls run claim,
   waits there past expiry, then A commits. Expect the same closed error and
   unchanged workflow_run_id/source_claimed_at/state. Repeat with blockers on
   operator, context, workspace, operation, source and preview rows to exercise
   the binding helper's final validity check. Administrative test blockers must
   only commit/rollback; they must not call a lifecycle RPC while holding a row.
5. Race duplicate dispatch/run claims: exactly one dispatchAllowed=true and
   one authorized run. Race success with failure and expiry in both orders:
   one terminal winner, late failure never overwrites PASS/PASS_WITH_WARNINGS,
   success cannot resurrect FAILED, and only actual deadline transitions count.
   Race managed release with a claim: if release wins before management begins,
   the claim fails; if claim wins, release is denied and the live lease remains.
6. Exercise stop with a waiting claim, UNKNOWN delivery, a running worker and a
   late callback. Structural rollback must refuse until quiescent. Inject a
   failure between wrapper removal and original restoration: ROLLBACK must
   preserve the installed contract/registry. Then test a full compensating
   transaction against saved OIDs, raw/effective ACLs, owners/configuration,
   dependencies, registry and unchanged dedup row/constraint inventory.
   Old identities remain non-replayable after a separately tested forward resume.

Structural Node checks inspect the unapplied draft's lock paths and guards;
they do not execute SQL, validate PL/pgSQL compilation, prove deadlock freedom,
measure contention or certify transactional rollback. All six runtime groups
above remain required before release. Global-gate latency and timeout behavior
also require measurement under representative concurrent local calls.

## Local repair validation (2026-11-08)

The scoped release must include `assets/js/operator-website-preview-build.mjs`
and the child controller's existing status/reason forwarding. The module registry
and child status-module import use `20261108-preview-status-r1` to invalidate both
previous cache keys. Preview and GitHub navigation handlers remain unchanged.
`preview-frontend-contract.test.ts` exercises the backend dispatcher and control
action with the frontend module selected by that import chain: HTTP 204 is queued,
HTTP 503 is uncertain (warning, not confirmed progress), and polling never
redispatches. External GitHub/RPC transport is synthetic in this local test.

Run `node scripts\website-project-preview-repair-local.cjs all` from the source
root. This provisions its own pinned Supabase PostgreSQL container with
`--network none`, no host ports, and disposable credentials. Real Auth and Storage
migrations run in that container's network namespace before **all repository
migrations**, including the pending dispatch and reconciliation migrations.
It uses the existing local identity bootstrap and synthetic fixture definitions;
it never connects to a production database or inspects unrelated containers.
The `all` entrypoint removes its own container and anonymous volumes in `finally`.
It refuses an existing container-name collision instead of deleting it.

Executed successfully:

- The existing dispatch SQL contract, against three isolated synthetic workspace
  leases (real PostgreSQL functions, not RPC mocks).
- Fourteen pgTAP reconciliation assertions: service-only ACL, AAL2, stale CAS,
  binding change, owner revocation, actual head update/audit/consumption, actual
  preview acquisition at the verified SHA, busy leases, unresolved UNKNOWN and
  expired read authority.
- Real competing connections: duplicate dispatch/run claims each have one
  winner; an operator lock held for 16 seconds forces reconciliation to reject
  its expired read authority after waiting.
- Real competing success/failure/expiry transactions now cover both terminal
  winners: exactly one build, both leases released, upload FINALIZED or ABORTED,
  and no resurrection. Competing owner revocation and repository rebinding
  reject waiting run claims without recording a run. Rebinding fixture setup
  disables triggers only inside the isolated, network-disabled test database.
- Fourteen two-dossier scheduled-cleanup assertions cover active and failed
  non006 dispatches, storage-path denial, cleanup-write denial, service ACLs and
  unchanged non006 lease/source/dispatch/upload/file evidence.
- Deno shared runtime tests: 125 passed (`--allow-read` is needed by existing
  provider tests), including provider identity/marker cases, configuration/token,
  dispatch and reconciliation tests. Operator preview routing: four passed with
  `--no-lock --node-modules-dir=none --allow-env --allow-read`.
  Reconciliation also rejects an invalid finalization response or a reported
  read-lease release failure; neither may produce a success result or dispatch.
- Node dispatch contract: nine passed. These remain structural tests, not SQL
  evidence.

These are local synthetic/provider-transport tests plus actual PostgreSQL
execution, **not** a live GitHub dispatch, customer-site build, remote head
attestation, hosted preview acceptance or production validation. The older
release matrix above still applies to scenarios not listed here; the dispatch
SQL scenario and the listed contention cases are no longer unexecuted.

Publication was separately authorized on 2026-11-08, contingent on release gates.
The review scope is
the pending preview backend/worker/workflow package already described above,
the shared reconciliation module, its Operator request wiring, migration
`20261108000100`, and related tests/docs. Preserve the existing shared PDF App
configuration; no new secrets. Release must separately authorize the pending
dispatch migration, reviewed immutable workflow SHA and DB allowlist, Edge
functions, existing hosting/artifact/OIDC settings and deadline scheduling.
Do not publish this entire non-git source copy, overwrite the protected
navigation release, touch the customer repository, or directly patch customer
rows. A permitted 006 OWNER/AAL2 request performs reconciliation only after the
server verifies the then-current head.

### Production dispatch transport correction (2026-11-08)

The first normal 006 request reconciled the Dutch repository head, then failed
closed before any GitHub workflow run: the shared HTTP adapter did not admit
the exact `metadata:read` plus `actions:read|write` permission shapes already
required by the preview token broker. The adapter now admits those exact shapes
without relaxing response equality or repository authority. The configuration
test now crosses the real HTTP adapter rather than mocking the token exchange;
it reproduced the failure before the correction. All 91 focused HTTP/broker/
preview-configuration tests pass afterward.

The terminal rejected dispatch is retained. No automatic retry or replacement
build is authorized by this correction. A hosted seven-page preview has not
been verified.
# Existing preview status in the workspace

The read-only `get_website_execution_workspace_v7` projection retains the v6
authorization and workspace fields and adds `preview_artifact`. It selects only
a successful artifact for the current dossier, workspace, repository binding and
commit. `PASS_WITH_WARNINGS` is preserved, rather than read from the legacy
workspace build columns. Missing or stale artifacts yield `null`.

The frontend accepts both earlier contracts and v7. Its status labels use the
artifact evidence; the preview and GitHub popup handlers are unchanged. Reading
the status does not acquire a lease, dispatch a workflow, or create a preview
session. Publish the compatible frontend before switching the backend to v7.

Focused database validation: `node scripts/website-project-preview-repair-local.cjs all-projection`.
