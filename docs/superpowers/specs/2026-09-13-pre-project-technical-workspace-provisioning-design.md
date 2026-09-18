# PRE_PROJECT Technical Workspace Provisioning Design

Date: 2026-09-13
Status: Approved for local implementation
Production actions: Forbidden

## Decision

Reuse `website_execution_workspaces` as the single technical-workspace authority. The existing V2 reanchor already makes `project_id` nullable, requires a unique `website_work_context_id`, and reads PRE_PROJECT without fabricating a commercial project. This change adds lifecycle and provenance fields plus one owner-only provisioning command; it does not introduce a parallel workspace table.

## Lifecycle Authority

`website_work_contexts` remains the lifecycle identity. A workspace can be provisioned only for an ACTIVE Website dossier whose server-resolved work projection is `PRE_PROJECT`, has `OPEN_WEBSITE`, and matches the resolved context. The initial state is `PENDING_REPOSITORY`. Repository linking and readiness are later server transitions, not browser claims.

`OFFICIAL_PROJECT` continues through the existing project authority and read path. This command is PRE_PROJECT-only and cannot create or infer a `commercial_projects` row.

## Data Model

The existing workspace row remains keyed by `website_workspace_id` and uniquely bound to `website_work_context_id`. Existing columns continue to hold repository, branch, preview, build and commit references. The forward-only delta:

- adds `workspace_state` with `PENDING_REPOSITORY` and `READY`;
- makes repository owner/name optional only while state is `PENDING_REPOSITORY`;
- records `provisioned_by` and `provisioned_at` as immutable provenance;
- preserves nullable `project_id` for PRE_PROJECT and requires it for OFFICIAL_PROJECT through the existing context guard;
- keeps production URL derived from `commercial_project_sites`; PRE_PROJECT never stores or fabricates one.

No secret, token, source code or local filesystem path is stored.

## Idempotency And Concurrency

The command accepts only `quote_request_id` and `idempotency_key`. The server resolves every identity and locks the Website work context. The existing unique constraint on `website_work_context_id` prevents duplicate workspaces. A dedicated idempotency ledger binds actor, command key and request fingerprint to the immutable result.

The first valid call inserts one pending workspace and emits `TECHNICAL_WORKSPACE_PROVISIONED`. An exact replay returns the same result without another workspace. A new idempotency key for an already provisioned context returns the existing workspace and emits one `TECHNICAL_WORKSPACE_REUSED` event for that command. Conflicting key reuse fails closed.

## Security Boundary

The SQL authority derives the caller through the existing authenticated operator model and permits only an ACTIVE owner. It verifies an ACTIVE, non-trashed Website dossier and the server-owned PRE_PROJECT work projection. Anonymous, inactive, revoked, non-owner, wrong-dossier and cross-context calls fail before mutation.

The client cannot submit `project_id`, workspace identity, repository coordinates, branch, preview URL, production URL or commit metadata. Edge validates an exact request shape and forwards only the two approved locators.

## Repository Provider Boundary

No repository provider integration exists in the released executable code. Provisioning therefore creates an internal workspace intent in `PENDING_REPOSITORY`; it does not call GitHub or invent repository metadata. A later provider adapter may claim a pending workspace server-side and bind externally verified repository identifiers. Browser code will never receive provider credentials.

## PRE_PROJECT And Official Projects

PRE_PROJECT rows have `project_id = NULL`, remain non-commercial, and may expose only internal development state. Preview remains nullable and production URL remains unavailable. OFFICIAL_PROJECT rows retain their project binding and existing commercial preview/publication authorities.

Promotion is a later transaction that must update the existing work context and workspace binding under the established context guard. This change neither implements promotion nor changes commercial state.

## Failure And Rollback Semantics

Validation, workspace insertion, idempotency recording and audit insertion occur in one transaction. Any failure rolls back all four. External side effects do not occur, so no compensating GitHub action is needed. The migration is forward-only and preserves existing rows.

## Audit

Append-only technical-workspace events record `TECHNICAL_WORKSPACE_PROVISIONED` or `TECHNICAL_WORKSPACE_REUSED`, actor, quote request, work context, workspace, mode and timestamp. Reads do not emit events. Event payloads contain no secrets or customer content.

## UI Command Contract

When V2 returns `workspace = null` for an eligible PRE_PROJECT owner, Website Execution shows `Technische werkruimte starten`. A confirmation explicitly states that no order, invoice, payment or publication right is created. Confirming sends only:

```json
{
  "action": "provision_website_execution_workspace",
  "quote_request_id": "uuid",
  "idempotency_key": "uuid"
}
```

After success the child refetches V2. The development surface remains in the existing managed Website child, displays the pending repository state, and places the existing server-authoritative Requirements projection beside it. `Projectbestanden` focuses this same surface rather than returning to dossiers/main.