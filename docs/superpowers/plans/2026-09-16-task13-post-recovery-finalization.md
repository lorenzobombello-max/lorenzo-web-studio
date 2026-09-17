# Task 13 Post-Recovery Finalization Plan

## Scope

Implement one dedicated, narrow post-recovery finalizer for an existing repository whose server-side GitHub inspection is `ALREADY_COMPLETE` while its durable provisioning operation is `TERMINAL_FAILED` and its workspace is `REPOSITORY_FAILED`.

The finalizer atomically produces the existing normal terminal state:

- provisioning operation `BOUND` with `bound_at`;
- execution workspace `REPOSITORY_READY` with the verified repository and starter provenance fields;
- exactly one `REPOSITORY_BOUND` event.

This plan does not authorize deployment, remote migration application, live finalization, GitHub mutation, repository creation, recovery invocation, commit, push, or Task 14 work. `NO_SECOND_CREATE` remains hard.

## A. Dedicated Database Transition

1. Add a new forward-only migration defining a dedicated `finalize_recovered_website_repository_v1` RPC. Do not edit historical migrations.
2. Write RED pgTAP coverage first for success, denial, replay, conflicting replay, and state/workspace/identity mismatches.
3. Require authenticated human OWNER+AAL2 authority and exact operation/workspace/context identity.
4. Lock the operation and workspace in one transaction.
5. Accept only `TERMINAL_FAILED` plus `REPOSITORY_FAILED`, or an exact idempotent replay of `BOUND` plus `REPOSITORY_READY`.
6. Validate a closed server-verified binding against the operation identity and provenance. Reject arbitrary states, cross-context identity, alternate repository identity, malformed visibility/default branch, and incomplete provenance.
7. Atomically bind the workspace, transition the operation, and insert exactly one `REPOSITORY_BOUND` event. Do not mutate `website_work_contexts`.

## B. Store Adapter

1. Add RED unit/contract tests for one narrow recovery-finalization method on the V2 provisioning store.
2. Add exact input and closed output types for operation/workspace/context plus `VerifiedRepositoryBindingV2`.
3. Call only the dedicated recovery-finalization RPC; do not reuse generic `resume`, `claim`, or raw object passthrough semantics.
4. Validate the returned `BOUND` operation and exact binding before returning.

## C. OWNER+AAL2 Server Action

1. Add RED tests for authentication, AAL2, OWNER, synthetic authority, state classification, identity mismatch, success, replay, and side-effect boundaries.
2. Add a minimal Task13 action accepting only action, operation ID, work-context ID, and workspace ID.
3. Reuse the existing human caller and synthetic authority guards.
4. Re-read database recovery authority and perform a fresh read-only GitHub inspection immediately before finalization.
5. Require exactly `ALREADY_COMPLETE` and derive the complete verified binding exclusively from server-side configuration, durable authority, and GitHub readback.
6. Compare the repository identity to the durable external identity and invoke the dedicated store method exactly once.
7. Return a closed minimal result containing only terminal operation/workspace status and replay classification. Do not return commit SHAs, tokens, raw provider responses, or provenance blobs.
8. Add no GitHub write, create, recovery, or Step 6 sibling path.

## D. Handler Contract

1. Extend exact request parsing and dependency typing for the finalization action.
2. Preserve existing bearer, human caller, AAL2, OWNER, and synthetic authority behavior.
3. Project only the approved closed response shape and fail closed for every malformed dependency result.
4. Wire production dependencies through the existing Task13 index/runtime boundary.

## E. `REPOSITORY_READY` Frontend Projection

1. Write RED frontend tests before implementation.
2. Preserve existing `PENDING_REPOSITORY` and legacy `READY` behavior.
3. Accept `REPOSITORY_READY` only with complete, valid repository owner/name fields and the existing closed workspace projection.
4. Reuse existing safe GitHub and VS Code URL construction; reject malformed or missing bound repository fields.
5. Keep the existing server-authoritative `[WEBSITE OPENEN]` route and controls unchanged. Add no duplicate activation button.

## F. Verification And Security Review

1. Run focused pgTAP, store, Task13 handler/runtime, state-inspection, and Website Execution tests after each implementation slice.
2. Run the relevant complete `_shared`, Task13, frontend, and provider test-island suites without double-counting overlapping runs.
3. Run supported frozen Deno checks, format checks, lint with existing exclusions, `git diff --check`, and credential/exposure scans.
4. Compare changed files against the external pre-edit backup/hash baseline.
5. Run a separate read-only security review over the final delta. Treat any scope expansion, client authority injection, race, replay defect, duplicate event, GitHub write/create/recovery path, or permissive frontend projection as blocking.
6. Stop and report for controller review. Do not deploy or invoke the finalizer live.
