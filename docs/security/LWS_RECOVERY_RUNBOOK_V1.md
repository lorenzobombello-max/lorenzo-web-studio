# LWS Recovery Runbook V1

Status: `DRAFT FOR OWNER REVIEW - PROCEDURE ONLY`

Baseline date: `2026-09-05`

This runbook does not authorize or execute a backup, restore, configuration change, deployment, credential operation or destructive action. Every real invocation requires separate OWNER approval, an identified recovery target and an isolated validation plan.

## Roles

- `OWNER`: declares the incident, approves recovery scope and authorizes reopening.
- `Incident commander`: owns chronology, decisions, communications and stop/go gates.
- `Recovery operator`: performs only separately approved recovery actions.
- `Independent verifier`: verifies source, manifests, integrity and acceptance evidence; this role must not self-approve its own recovery execution.
- `Business validator`: confirms customer, commercial, financial or HR usability without changing unrelated records.

No credential, token, private key, recovery code or customer document content may be copied into the incident record.

## 1. Incident Classification

1. Assign a unique incident reference and UTC start time.
2. Classify impact: availability loss, database data loss/corruption, Storage object loss, identity/authorization loss, configuration loss, integrity concern or combined disaster.
3. Determine the highest affected recovery priority from the dataset register.
4. Mark uncertain impact as `UNKNOWN`; do not downgrade it without evidence.
5. Record whether confidentiality or signing authority may be compromised. If so, use the separately approved incident-response and credential-rotation process before recovery proceeds.

## 2. Data-Loss Detection

1. Preserve read-only observations, alert timestamps, provider status and relevant audit references.
2. Identify the earliest known-good state, first known-bad state and detection time in UTC.
3. Distinguish missing database rows, inconsistent metadata and missing Storage bytes.
4. Do not infer an object exists from a database metadata row or checksum.
5. Do not run repair, cleanup or replay during detection.

## 3. Freeze Further Destructive Actions

1. Declare destructive operations frozen through the approved operational channel.
2. Confirm purge remains fail-closed and no bypass or legacy destructive path is enabled.
3. Preserve dual-control and AAL2 requirements.
4. Record active jobs or external deliveries that could expand the incident window.
5. Any technical kill-switch or configuration mutation requires separate OWNER authorization; this document alone does not authorize it.

## 4. Identify Affected Dataset And Time Window

1. Map affected records and objects to `LWS_RECOVERY_DATASET_REGISTER_V1.md`.
2. Record authoritative identifiers, lifecycle revisions and last known source mutation times.
3. Build a dependency list across database records, Auth identities, Storage objects, functions and configuration.
4. Separate customer/business scope from unrelated datasets.
5. Treat every unresolved dependency as `UNKNOWN` and fail closed.

## 5. Determine Required Restore Point

1. Select the latest candidate restore point before the first known-bad mutation.
2. Compare the candidate with the current database RPO and the actual provider restore points.
3. Calculate the expected data-loss interval and identify transactions requiring controlled reconciliation.
4. Verify that independent Storage versions exist for the same consistency boundary. If they do not, a database restore cannot be declared a complete recovery.
5. Obtain OWNER approval of the selected recovery point, expected loss and validation plan.

## 6. Database Restore Preparation

1. Prefer an isolated recovery environment. Never begin with an in-place production restore unless separately authorized after impact review.
2. Record the immutable provider backup reference, type, timestamp and retention deadline.
3. Inventory extensions, schemas, custom roles, replication/subscription dependencies, scheduled jobs and migration ledger state.
4. Prepare validation queries that are read-only and bounded. Do not include personal content in evidence output.
5. Define downtime, communication, rollback boundary and stop conditions.
6. Require a second person to verify the selected project and restore point before execution.

## 7. Storage Restore Preparation

1. Enumerate every required bucket, object path, version/reference, byte count and checksum from an approved manifest.
2. Confirm the recovery source is independent of the affected primary project/account.
3. Confirm capture time is after the last relevant object mutation and consistent with the selected database point.
4. Confirm retention has not expired and source objects are readable by the designated recovery role.
5. Plan restoration into an isolated destination first, with no overwrite of production objects.
6. If any required object lacks valid evidence, mark the dataset recovery incomplete and stop.

## 8. Auth, MFA And Operator Identity Reconciliation

1. Reconcile restored `auth.users` identities against operator profile and commercial-operator UUID bindings.
2. Verify account confirmation, active/disabled/revoked state and role authority.
3. Verify MFA enrollment and required AAL without disclosing factors or recovery material.
4. Identify identities created, disabled, revoked or rebound after the restore point.
5. Review session and token invalidation requirements because older database state and current signing/config state may diverge.
6. Prove at least two authorized recovery actors can complete required dual-control actions without lockout.
7. Do not recreate, remove or rebind an identity without separate OWNER approval.

## 9. Edge, Configuration And Secrets Reconstruction

1. Bind source reconstruction to an approved git commit and dependency locks.
2. Compare the migration ledger with tracked migrations; do not replay migrations solely because files exist.
3. Inventory Edge Function versions, routing, schedules and required variable names without recording values.
4. Reconstruct Auth settings, redirect origins, signing configuration, Storage settings, GitHub Pages settings and DNS from approved configuration evidence.
5. Retrieve secret values only through the approved secret-custody process and directly into the target system; never place them in tickets, logs or this runbook.
6. Do not deploy or rotate configuration during preparation.

## 10. Integrity Validation

1. Verify database constraints, migration ledger, row counts and required cross-table references.
2. Verify each required Storage object against manifest checksum, byte count and expected type.
3. Reconcile database metadata with actual object presence; report missing and orphaned objects.
4. Verify immutable event chains, object fingerprints and authoritative snapshots.
5. Verify Auth UUID bindings, role boundaries, RLS and critical AAL2 controls.
6. Record validation outcomes as `PROVEN`, `PARTIAL`, `UNKNOWN` or `MISSING`. Any critical non-`PROVEN` result blocks reopening.

## 11. Business Validation

1. Use synthetic or explicitly approved bounded records whenever possible.
2. Validate representative active customer, website, SDF, finance, Document Inbox, recruitment and workforce workflows according to recovery priority.
3. Confirm quotation and document artifacts open and match their registered checksums.
4. Confirm financial totals and lifecycle states reconcile without generating invoices, messages or customer deliveries.
5. Obtain signed OWNER/business-validator acceptance and record unresolved exceptions.

## 12. Controlled Reopening

1. Reopen only after technical and business validation meet the approved acceptance criteria.
2. Restore access in priority order: P0 control plane, P1 active operations, then approved P2/P3 datasets.
3. Keep purge and unrelated destructive actions disabled until P0-6G is separately approved and deployed.
4. Monitor authentication, authorization, database, function and object integrity signals during the agreed observation window.
5. Define and communicate the point of no return before any production cutover.

## 13. Post-Incident Evidence

Record without secrets or customer contents:

- incident and approval references;
- affected datasets and time window;
- chosen backup and Storage recovery references;
- responsible operator and independent verifier;
- start/end timestamps, achieved RPO and achieved RTO;
- manifest and checksum results;
- Auth/config reconciliation result;
- technical and business acceptance;
- losses, exceptions, follow-up owners and deadlines.

## 14. Lessons Learned

1. Compare achieved RPO/RTO with targets.
2. Identify missing evidence, manual steps, lockout risks and provider/account dependencies.
3. Update the policy, dataset register and runbook through review; never rewrite incident evidence.
4. Create separately approved remediation work for failed controls.
5. Schedule the next isolated restore test and record its scope.

## Stop Conditions

Stop recovery and escalate to the OWNER when the source is not independently verifiable, a checksum differs, required Storage bytes are absent, identity authority is ambiguous, retention expired, the proposed action would mutate unapproved production state, or the expected data loss exceeds the approved boundary.
