# PRE_PROJECT Repository Provider V2 Design

Date: 2026-09-13
Status: Local provider boundary only
Production actions: Forbidden

## Audit Result

| Capability | Result | Evidence |
| --- | --- | --- |
| `EXISTING_GITHUB_PROVIDER` | `NEE` | No GitHub API client or provider implementation in tracked executable code. |
| `EXISTING_REPO_CREATE_ADAPTER` | `NEE` | No repository-create call, SDK, or server transport exists. |
| `EXISTING_GITHUB_APP` | `NEE` | No GitHub App identity, installation flow, or permission configuration exists. |
| `EXISTING_GITHUB_SECRET_STORAGE` | `NEE` | Edge Functions use server environment bindings generally, but no GitHub credential binding exists. |
| `EXISTING_BRANCH_BOOTSTRAP` | `NEE` | No branch creation, commit, push, or repository initialization helper exists. |
| `EXISTING_REPO_SYNC` | `NEE` | No repository metadata synchronization path exists. |
| `EXISTING_WEBHOOK_INTEGRATION` | `NEE` | Existing webhook code is Resend-specific; no GitHub webhook receiver exists. |
| `EXISTING_WEBSITE_TEMPLATE` | `NEE` | The current static product site is not identified as a reusable customer template. |
| `EXISTING_STARTER_REPO` | `NEE` | No starter repository or starter identifier is present. |
| `EXISTING_BUILD_SYSTEM` | `BEPERKT` | PowerShell assembles this repository's static Pages artifact; it is not a customer-project bootstrap system. |

The two GitHub Actions workflows only check out this repository. Their repository permission is `contents: read`; Pages receives only its deployment permissions. They do not establish repository provisioning authority.

## Decision

Because no safe provider or canonical starter exists, this version stops at `RepositoryProvisioningService` and a fake provider/store contract in tests. It does not add a GitHub SDK, HTTP call, GitHub credential, Edge route, database mutation, migration, repository, branch, commit, webhook, deploy, or production action.

`website_execution_workspaces` remains the only workspace authority. The existing row stays `PENDING_REPOSITORY`; no fabricated repository coordinates are written. The existing Website Execution child remains bound to `website_work_context_id`, and its Requirements panel continues to consume the projection for that same context. No parallel work context or Requirements authority is introduced.

## Service Contract

The service accepts only trusted server-side identifiers:

- `websiteWorkspaceId`;
- `websiteWorkContextId`;
- `idempotencyKey`;
- a server-derived repository name.

Repository owner, provider identity, visibility, branch, credentials, URLs, source files, project identity, and customer content are not accepted from browser input.

The store must atomically claim the operation and return one of:

- `CLAIMED`: this caller may invoke the provider;
- `REPLAY`: return the already verified binding without invoking the provider;
- `IN_PROGRESS`: fail closed while another claimant owns the operation.

The provider request is fixed to GitHub-neutral repository semantics required by the later adapter: private visibility, `main` as default branch, and `bootstrap: NONE`. `NONE` is mandatory because this audit found no canonical starter and no framework choice is authorized.

A provider result is accepted only when it contains the exact allowlisted binding fields, identifies a private GitHub repository, matches the requested server-derived name, and contains no credential or arbitrary URL field. Binding is performed against both the claimed workspace and its existing work context. Provider and binding failures are reduced to stable codes; upstream messages are not propagated.

## Later Activation Gate

A real adapter may be added only after a separate decision supplies all of:

1. a reviewed server-side GitHub App installation model with repository-scoped permissions;
2. an approved GitHub credential binding outside browser and database payloads;
3. deterministic organization and repository naming policy;
4. atomic claim/bind persistence for the existing PRE_PROJECT workspace;
5. a canonical, versioned website starter or an explicit empty-repository decision;
6. local contract tests using a fake provider before any external acceptance test;
7. explicit authorization for the first external repository creation.

Until then, the service has no executable production caller.
