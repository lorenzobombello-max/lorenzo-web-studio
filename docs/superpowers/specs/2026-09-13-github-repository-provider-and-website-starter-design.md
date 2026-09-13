# GitHub Repository Provider and Website Starter Design

Status: design complete, implementation not authorized
Date: 2026-09-13
Scope: PRE_PROJECT repository provisioning, customer website starter, development and preview boundaries
Decision owner: LWS owner

## 1. Executive summary

LWS will provision one private, LWS-organization-owned GitHub repository for each `website_work_context_id`. A server-side GitHub App is the only repository-provider identity. It creates the repository from one private canonical LWS website template, writes an immutable context marker, verifies the result, and binds verified repository metadata to the existing `website_execution_workspaces` authority.

The permanent rule is **IEDER DOSSIER = EIGEN EILAND**. The business island is the dossier; the technical website isolation key is `website_work_context_id`. No customer source, mutable worktree, cache, artifact, preview or Git history is shared across work contexts. The GitHub App is a control-plane authority and does not turn customer repositories into a shared data plane.

The canonical starter uses Astro with static output. It supports semantic HTML, SEO, responsive media, motion and optional 3D client islands without requiring a runtime SaaS dependency. Every generated repository gets independent history and pinned starter provenance. Existing repositories never receive automatic starter rewrites.

This document authorizes no execution. GitHub App registration or installation, secret creation, external repository creation, Edge activation, migration execution, deployment, push and production or customer mutation remain prohibited until separately reviewed and approved.

## 2. Current state

- `website_work_contexts` is the lifecycle and technical isolation identity.
- `website_execution_workspaces` is the single technical workspace authority and permits one workspace per work context.
- PRE_PROJECT provisioning creates a workspace in `PENDING_REPOSITORY` without an external side effect.
- Owner identity, AAL2, caller JWT, context locking and idempotency are already enforced by database authority.
- The Operator sends authority-minimal commands and already presents the development area beside the Requirements panel.
- Requirements are project-bound and read through existing owner-authorized projections.
- Preview readiness is already fail-closed against project requirements.
- The local `RepositoryProvisioningService` and fake tests define an inert server-side orchestration boundary. They have no executable caller and are not changed by this design.
- There is no installed GitHub App, provider credential, repository-create adapter, repository sync, customer starter repository or customer deployment integration.
- Existing core-repository workflows deploy only LWS core surfaces and are not a customer repository provider.

## 3. Decisions

| Subject | Decision |
| --- | --- |
| Provider identity | GitHub App installation access token |
| App owner | LWS-controlled GitHub Organization |
| Repository owner | LWS-controlled GitHub Organization |
| Customer repository | One private repository per `website_work_context_id` |
| Repository name | `lws-web-<website_work_context_id-without-hyphens>` |
| Default branch | `main` |
| Starter source | Separate private LWS GitHub Template Repository |
| Starter technology | Astro, static output |
| Template branches copied | Default branch only |
| Provider runtime | Server-side LWS Edge/control-plane function only |
| Browser credentials | Forbidden |
| Token persistence | Forbidden; memory-only and discarded after request |
| Token lifetime | GitHub installation-token lifetime, no more than one hour |
| Webhook in V1 | No |
| Browser project-file writes in V1 | No |
| PRE_PROJECT production publication | No |
| Existing repository upgrades | Explicit reviewed merge or migration only |

## 4. Alternatives rejected

### Personal access token

Rejected because it couples provisioning to a person, commonly carries broad long-lived authority, complicates rotation and weakens attributable app-level audit.

### OAuth user token

Rejected because repository creation is an LWS system responsibility, not delegated user behavior. User token availability and permission would make the lifecycle nondeterministic.

### Shared customer repository or monorepo

Rejected because branch, checkout, cache, build, artifact and access mistakes can cross dossier boundaries. Repository-level isolation is the required blast-radius boundary.

### Fork per customer

Rejected because fork networks create unnecessary ancestry and policy coupling. A template-generated repository has independent history and ownership.

### Copy files into the LWS core repository

Rejected because customer source must never enter a core product repository.

### Static HTML/CSS/JS starter

Rejected as the canonical choice. It has minimal tooling but scales poorly for reusable page composition, content structure, asset pipelines and controlled interactive islands.

### Vite vanilla/modules starter

Rejected as the canonical choice. It is strong for client-side tooling but does not supply Astro's first-class static page, layout, content and SEO model.

### Runtime web framework or CMS dependency

Rejected for the base starter. New websites must build to portable static output without requiring a continuously running application server or SaaS CMS.

### Browser IDE in V1

Rejected because it would imply filesystem, credential, process and terminal capabilities that the Operator does not own. V1 links the authorized context to a real local VS Code clone.

## 5. GitHub App architecture

The GitHub App is owned by the LWS GitHub Organization and installed only on the LWS organization that owns the private template and customer repositories. Installation uses **Only select repositories** and initially selects only the private canonical template. GitHub automatically grants the App access to repositories that the App creates; unrelated LWS and customer repositories therefore remain outside the installation. GitHub Apps have no permissions by default; the installation receives only the repository permissions required by the approved provider operations.

Minimum V1 permissions:

| Permission | Level | Purpose |
| --- | --- | --- |
| Repository metadata | Read | Verify owner, external ID, name, visibility and default branch |
| Repository administration | Write | Generate/create the private organization repository |
| Repository contents | Write | Read template/content provenance and create `.lws/project.json` |

`Workflows`, `Actions`, `Deployments`, `Pages`, `Issues`, `Pull requests`, `Members`, `Webhooks` and secret-management permissions are not granted in V1. `Workflows: write` becomes relevant only if a later approved command edits `.github/workflows`; the V1 provider must reject that path.

The provider creates a short-lived App JWT from the App ID and private key, exchanges it with the configured installation ID for an installation token, and uses the token only in memory. Installation tokens expire after one hour. Every token request supplies an explicit repository selection and the minimum permissions for that operation. The creation token selects only the canonical template repository ID; after GitHub adds the newly created repository to the installation, marker, read and reconciliation tokens select only the new repository ID. Test-organization contract evidence must prove template generation works with this scope before activation. Failure of that test blocks release and requires owner review of a revised authority design; minting an installation-wide token is not a fallback.

GitHub permission categories are coarser than provider methods. Even a repository-scoped token with `Administration: write` or `Contents: write` can technically perform actions that the provider does not expose. Fixed endpoint routing, denylisted destructive methods, request-shape contract tests, short token lifetime and GitHub audit correlation are mandatory compensating controls. The provider has no delete, transfer, archive, visibility-change, branch-rewrite or arbitrary-content method.

No App JWT, installation token, private key, temporary clone token or authenticated Git URL is returned to the browser, persisted in PostgreSQL, written to repository content, included in an exception, or emitted to logs and audit payloads.

## 6. Repository provider

The provider is a server-only adapter behind `RepositoryProvisioningProvider`. It accepts normalized internal authority, not arbitrary GitHub coordinates from the browser. Before activation, the current inert contract must receive a reviewed versioned extension for starter source/version/SHA, template bootstrap and marker verification; the existing `bootstrap: "NONE"` request is not silently reinterpreted.

The orchestration sequence is:

1. Revalidate owner, AAL2, workspace, work context, lifecycle and permitted action in database authority.
2. Claim a durable operation using workspace ID, context ID, command idempotency key and fingerprint.
3. Derive the repository name and expected owner internally.
4. Resolve the approved starter release and exact source commit SHA.
5. Mint a just-in-time installation token.
6. Generate a private repository from the template default branch with `include_all_branches=false`.
7. Persist the returned external repository ID and node ID as soon as the durable operation can safely record them.
8. Verify organization, deterministic name, private visibility, `main`, installation access and generated source tree.
9. Create `.lws/project.json` serially and capture its commit SHA.
10. Re-read and verify the context marker.
11. Bind the exact verified metadata to the locked workspace/context and transition it to `REPOSITORY_READY`.
12. Emit a redacted audit event and discard credentials.

The provider follows redirects only when the target remains HTTPS on an explicit `github.com` or `api.github.com` allowlist. It never accepts a caller-supplied host, owner, template or absolute URL.

## 7. Repository ownership

All provisioned repositories are owned by the configured LWS GitHub Organization. They are private at creation and must remain private while bound to PRE_PROJECT. Personal accounts and customer organizations are not V1 owners.

Organization ownership centralizes lifecycle policy, App installation, recovery and offboarding while repository-per-context isolation limits data-plane blast radius. Human access is granted only through context-specific or portfolio-scoped organization teams under a documented least-privilege policy. Before production enablement, that policy must define approval, repository grant, periodic review, offboarding, credential storage, emergency access and GitHub audit review. Broad organization owners are privileged administrators outside ordinary dossier authorization; their actions are auditable break-glass activity and are not represented as cross-context denial. The provider command cannot add people or teams.

Repository transfer, visibility change, archive and deletion are separate owner-approved commands. Provisioning has no delete capability.

## 8. Naming

The canonical repository name is:

```text
lws-web-<website_work_context_id lowercased, with hyphens removed>
```

For example, UUID `0198abcd-1234-7000-8000-0123456789ab` maps to `lws-web-0198abcd1234700080000123456789ab`.

This name is deterministic, stable, collision-safe for UUID identity, lowercase, GitHub-compatible and contains no customer name, domain, email, quote number or other mutable or identifying business data. The provider rejects rather than sanitizes a value that cannot be derived from a valid bound UUID. Renames are outside V1 because the deterministic name is reconciliation evidence.

## 9. Secret management

The later runtime configuration requires only:

- GitHub App ID;
- GitHub App installation ID;
- LWS organization login;
- private template owner/name;
- GitHub App private key reference.

The private key is stored in the approved server-side secret manager and exposed only to the provider runtime. It is not stored in repository variables, public environment files, database rows or browser configuration. Runtime logs must redact authorization headers, JWTs, installation tokens, PEM material, signed URLs and Git remotes containing credentials.

Rotation creates a new App private key, updates the secret-manager version, verifies token issuance, then revokes the previous key. Suspected disclosure immediately pauses provider commands, revokes the key or installation, invalidates active operational claims for review and starts the audit procedure.

## 10. Idempotency and concurrency

The command idempotency fingerprint covers `website_workspace_id`, `website_work_context_id`, deterministic repository name, starter source, starter version and starter commit SHA. Reusing a key with another fingerprint fails closed.

Only one active repository-provisioning operation is allowed per workspace and per work context. A database claim is committed before the external call. Concurrent callers receive the existing terminal result or `REPOSITORY_PROVISIONING_IN_PROGRESS`; they do not call GitHub.

GitHub repository creation and database binding are not one transaction. Correctness therefore relies on deterministic naming, durable operation state, external ID capture, context-marker verification and reconciliation. A timeout is always treated as an unknown outcome, never as proof that no repository was created.

## 11. Recovery and reconciliation

Operation states are `CLAIMED`, `CREATING`, `EXTERNAL_CREATED`, `VERIFYING`, `BOUND`, `RETRYABLE_FAILED`, `BLOCKED`, `QUARANTINED` and `TERMINAL_FAILED`. Workspace states become `PENDING_REPOSITORY`, `REPOSITORY_PROVISIONING`, `REPOSITORY_READY`, `REPOSITORY_FAILED` and existing `READY` where its later lifecycle meaning remains valid.

Reconciliation uses all available evidence:

- configured organization;
- deterministic repository name;
- captured external repository ID and node ID;
- private visibility;
- default branch `main`;
- current installation access;
- exact `.lws/project.json` context and operation identity;
- approved starter source, version and source commit SHA.

A same-name repository is never adopted solely by name. If its marker is absent, malformed or bound to another context/operation, the operation becomes `QUARANTINED`. The provider neither overwrites its marker nor deletes the repository.

Quarantine resolution is a separate owner+AAL2 command with a second idempotency key and immutable evidence snapshot. For a markerless repository, repair is permitted only when organization, deterministic name, captured external ID/node ID, private visibility, creation timestamp, GitHub App actor, initial tree and original operation all match and no conflicting binding exists. The command writes the expected marker, verifies it, and transitions `QUARANTINED -> VERIFYING -> BOUND`. Any conflict permits only `QUARANTINED -> TERMINAL_FAILED`; deletion or rename requires another explicit repository-lifecycle design. Quarantines have no automatic expiry, remain non-launchable/non-previewable, and raise an owner alert after 24 hours until resolved. Every decision and evidence hash is audited.

Timeouts, connection failures, GitHub 5xx responses and rate limits use bounded exponential backoff with jitter, at most five automatic attempts in 24 hours. `Retry-After` and GitHub rate-limit reset headers take precedence. HTTP 401/403 pauses in `BLOCKED` until configuration or permission is corrected. Validation, ownership, visibility, marker or cross-context mismatches fail closed without automatic retry.

No orphan is automatically deleted. A verified orphan can be bound only when its external ID, marker, organization, private visibility and operation identity all match the durable claim. Unverified orphans remain quarantined for owner-reviewed disposition.

## 12. Starter technology

Astro with static output is the canonical starter technology.

| Criterion | Static HTML/CSS/JS | Vite vanilla/modules | Astro static |
| --- | --- | --- | --- |
| Portable static output | Strong | Strong | Strong |
| Semantic page/layout model | Manual | Manual | Strong |
| SEO defaults | Manual | Manual | Strong |
| Client JavaScript control | Manual | Strong | Strong through islands |
| Motion and 3D extensibility | Possible | Strong | Strong through client islands |
| Content maintainability | Weak at scale | Moderate | Strong |
| AI editability | Simple but repetitive | Moderate | Strong, explicit file conventions |
| Runtime SaaS dependency | None | None | None |

The starter pins Node and package-manager versions, commits its lockfile, builds with `astro build`, and emits static `dist/`. JavaScript is opt-in per component. Three.js or another heavy client library is added only when a customer design requires it and remains isolated to that customer's repository.

## 13. Starter/template design

The canonical starter is a separate private repository marked as a GitHub Template Repository. It is not the LWS website, Operator, SDF or Marketing repository. The template default branch is `main`; customer generation copies only that branch.

Required starter contents:

```text
src/
  components/
  layouts/
  pages/
  styles/
public/
scripts/
astro.config.mjs
package.json
package-lock.json
tsconfig.json
.editorconfig
.gitignore
README.md
```

The starter supplies accessible semantic structure, responsive tokens, metadata/SEO helpers, sitemap and robots defaults, image handling, reduced-motion behavior, error/404 output, lint/type/build scripts and a deterministic static build. It contains no customer data, credentials, production domain, analytics secret, reusable customer content or active deployment credential.

`.lws/project.json` is not a generic template value. The provider creates it after generation with:

```json
{
  "schema_version": 1,
  "website_work_context_id": "<bound UUID>",
  "repository_provisioning_operation_id": "<bound UUID>",
  "starter_source": "<approved organization/repository>",
  "starter_version": "<semantic version>",
  "starter_commit_sha": "<40 or 64 lowercase hexadecimal Git object ID>"
}
```

The values are non-secret and contain no customer PII. The provider serializes the marker itself; it never performs text substitution across starter source files.

## 14. Starter versioning

Each approved starter release has an immutable semantic version tag and an exact source commit SHA. The provider configuration maps one active semantic version to one reviewed commit on the template default branch.

GitHub template generation does not accept a commit ref. Release publication therefore protects `main` and semantic release tags with GitHub rulesets, disallows force-push/deletion, restricts bypass to audited break-glass owners and freezes starter changes while generation holds an LWS release lock. The provider binds the template repository's immutable external ID, resolves `main`, verifies it equals the approved release SHA immediately before generation, then compares the generated initial tree to the approved source tree before binding. The comparison recursively sorts paths and requires equality of path, Git object type, file mode and blob content hash while excluding no path; the later marker commit is verified separately. A mismatch quarantines the result.

Workspace metadata records `starter_source`, `starter_version` and exact `starter_commit_sha`. The customer repository's own marker commit SHA is separate provenance.

New starter releases affect only future provisioning. Existing customer repositories receive changes through an explicit, reviewed branch/merge or a version-specific migration procedure with customer-context tests. Automatic force-push, reset, rebase or destructive synchronization is forbidden.

## 15. Development workspace

V1 development is a real local VS Code workspace backed by a dedicated clone of the bound private repository. The Operator is a context and launcher surface, not a browser IDE.

The local clone root is derived from `website_work_context_id`, not customer-entered text. A launcher verifies the authenticated owner, exact context binding, repository external ID and marker before clone/open. Each context gets a separate filesystem root, Git metadata directory, branch state, dependency directory and process environment.

Installation tokens are not placed in remote URLs or credential files by the Operator. Human local Git authentication uses separately governed developer tooling. The server-side App credential is never reused as a developer credential.

## 16. Requirements panel

The existing Requirements panel remains the requirements authority beside the development area. Repository provisioning does not duplicate requirements into GitHub issues, starter files or free-form repository metadata.

The panel loads by the already-authorized project/work-context relationship. Requirement mutations continue through their own owner/AAL2/idempotent database commands. Repository access does not imply requirement access, and requirement access does not imply arbitrary repository access. Preview readiness remains fail-closed on the authoritative requirements evaluator.

## 17. Project files

V1 project-file reads follow:

```text
Owner browser -> LWS Edge authority -> context/workspace binding -> GitHub App -> bound repository
```

The browser submits `website_work_context_id`, a normalized relative path and an approved ref selector. It cannot submit owner, repository URL, installation ID or GitHub host. The server resolves the bound repository by external ID and applies:

- owner plus AAL2 authorization;
- exact context/workspace/repository binding;
- `main` or an explicitly bound branch/commit only;
- normalized relative paths with no traversal, NUL, backslash ambiguity or encoded bypass;
- file/directory response count limits;
- a conservative response-size ceiling no greater than 1 MiB per file in V1;
- text MIME/extension allowlists for inline display;
- forced download or rejection for binary/active content;
- output escaping and `nosniff` response behavior;
- no forwarding of GitHub temporary download URLs.

Symlinks and submodules are returned only as inert metadata in V1; the server does not dereference targets. HTML, SVG and Markdown are never injected as trusted Operator markup.

Browser file writes are not a V1 feature. A later write command must be server-side, path-allowlisted and idempotent, require the expected blob SHA and expected branch head commit SHA, create a normal auditable commit, reject `.github/workflows`, `.lws/project.json` and secret-like files, and fail on concurrent change.

## 18. Preview architecture

Each context has a dedicated preview namespace derived from `website_work_context_id` and an immutable build ID. Preview routing, storage, logs, cache and artifacts carry both identities. A preview resolver checks the authorized context and exact build binding before returning content.

Builds run from an exact repository commit in the disposable sandbox defined in section 20.7. Dependency and build caches use a key beginning with the context UUID plus lockfile hash, toolchain version and build configuration hash. Artifacts are written to a context/build prefix and are never fetched by an unscoped artifact ID or prefix alone.

PRE_PROJECT may create only an access-controlled non-production preview after requirements readiness and build verification. It cannot update a production domain, public Pages site, customer DNS or shared production bucket. Promotion to production is a later explicit authority boundary.

## 19. Promotion

PRE_PROJECT promotion retains the same `website_work_context_id`, workspace row, repository external ID, Git history, files, requirements board and provenance. Promotion changes lifecycle and permitted actions; it does not copy source to another customer repository or create a new island.

Before promotion, authority verifies repository privacy, marker identity, starter provenance, latest commit, requirements readiness, preview evidence and absence of unresolved quarantined operations. Production publication requires a separate owner-authorized, idempotent command and a separately designed deployment credential boundary.

Rollback selects a previously verified commit/build inside the same island. It never points one context at another context's artifact.

## 20. ISLAND ISOLATION ARCHITECTURE

### 20.1 LWS product islands

Website, SDF, Operator, Marketing and the public LWS Website are separate product islands with separate source ownership and deployment authority. Security is an overarching control plane that sets policy and validates access; it is not a shared mutable customer data plane.

Customer website source is permitted only in that customer's bound website repository. It is forbidden in the LWS core repository, Operator repository, SDF repository, Marketing repository and another customer's repository.

### 20.2 Dossier and customer islands

The dossier is the business island. `website_work_context_id` is the technical website isolation key inside that dossier. A customer may have multiple contexts; those contexts remain isolated even when they share the same customer identity.

For each work context there is at most one authoritative:

- technical workspace;
- private repository and repository binding;
- development clone/worktree root;
- files namespace;
- preview namespace;
- Git history and active branch context;
- cache namespace;
- build namespace;
- artifact namespace.

No mutable object above is reused across contexts. Shared immutable toolchain packages may exist only in a content-addressed, read-only global cache whose outputs are copied into a context-scoped cache and whose key contains no customer material. A context can never publish into or evict another context's mutable cache.

### 20.3 Test islands

Synthetic and test dossiers are full isolated islands. They use explicit test organization/repository policy, test storage prefixes, test preview routes, test caches and test credentials. A test identity cannot resolve, bind, mutate, deploy or clean up a real-customer resource.

Test cleanup selects resources by verified test marker plus exact test context and external ID. Name prefix alone is insufficient. Production credentials are unavailable to test runtimes.

### 20.4 Control plane versus data plane

The control plane contains owner authorization, lifecycle commands, idempotency claims, GitHub App token issuance, binding verification, audit and reconciliation. The data plane contains each context's source, Git history, local clone, build inputs, cache, artifacts and previews.

The GitHub App may centrally authorize a provider operation, but every data-plane request is resolved through the caller's authorized context to one bound external repository ID. Central credentials never justify cross-context listing or broad data return.

### 20.5 Repository isolation

One context maps to one private repository. Unique database constraints cover work context, workspace and external repository ID. Binding requires matching workspace and context under row lock. A repository already bound anywhere else is rejected even if a caller can access it in GitHub.

Repository metadata is treated as untrusted external input. Owner, name, node ID, visibility, default branch and marker are verified and escaped before display. Repository URLs are derived from the configured GitHub host and verified owner/name, not accepted as authority.

### 20.6 Workspace and filesystem isolation

Workspace launch resolves a canonical root from the context UUID. The launcher prevents path traversal, junction/symlink escape and reuse of an existing root whose `.lws/project.json`, Git remote and external ID do not match. Shared customer worktrees are forbidden.

Processes start with the context root as working directory and a context-scoped temporary directory. Environment, logs and file watchers are scoped to that root. Cleanup verifies the canonical root and marker before deletion and never follows links outside it.

The local VS Code launcher is an application-mediated isolation boundary, not a claim that LWS can restrict a Windows administrator who directly browses the host filesystem. The negative workspace test uses an actor/session authorized for context A but not B and verifies that Operator and launcher resolution cannot open B. Machines shared by mutually distrusting developers require a managed per-context VM/container or separate OS identity and ACLs; otherwise they are not an approved multi-tenant workspace host. Developer Git credentials must be repository-scoped, and broad organization-owner credentials are break-glass authority subject to the human-access controls in section 7.

### 20.7 Cache, build and artifact isolation

Every mutable cache key begins with `website_work_context_id`. Every build record binds context, repository external ID and commit SHA. Every artifact path binds context and build ID. Prefixes are addressing, not authorization: a trusted broker issues job-scoped, short-lived capabilities for one context/prefix, and storage/cache/CDN policy denies unscoped list, read, write, purge and promotion. Server-derived ownership metadata is checked on every operation; guessing or substituting an artifact ID is insufficient.

Builds execute repository-controlled package lifecycle and build code only in a disposable non-privileged sandbox. The sandbox has no host socket, sibling mount, provider/deployment credential or ambient cloud identity; receives read-only source plus one context-scoped output capability; uses an allowlisted dependency-registry egress policy; enforces CPU, memory, process, disk and time limits; runs immutable lockfile installation; and is destroyed after the job. Build output cannot write to a shared public root. Promotion copies or references only artifacts whose recorded context equals the promoted context.

### 20.8 Preview and deployment isolation

Preview host/path, access token, storage prefix and build record are unique per context. Preview tokens are audience-bound, short-lived and cannot be replayed against another context. Caches include the context in both application and CDN keys, while CDN read/purge operations additionally require the broker-issued context capability and verified ownership metadata.

Production domains and deployment targets are separate explicit bindings. A PRE_PROJECT context has no production deployment permission. Deployment never infers a target from repository content.

### 20.9 Website versus SDF isolation

Website source and build artifacts never enter SDF storage. SDF documents and customer financial/commercial payloads never enter the website repository. Shared dossier identity may be referenced through opaque IDs in the control plane, but each product applies its own authorization and storage rules.

The Website provider cannot call SDF mutation commands. SDF credentials cannot read or mutate website repositories. Operator projections may compose redacted status from both products without merging their data planes.

### 20.10 Cross-context authorization

Every command independently verifies caller, owner role, AAL2 where mutation occurs, dossier relation, work context, workspace, repository binding and lifecycle. The server derives downstream resource identifiers after authorization. Caller-supplied repository IDs, URLs, cache keys, artifact prefixes and preview targets are never trusted.

A service-role or GitHub App credential bypasses third-party row security technically, so application authority must enforce the same context equality before every external call. Audit records both requested context and resolved resource identity.

### 20.11 PRE_PROJECT promotion

Promotion preserves the island. It changes status and permissions on the same bound resources. New repository creation, repository transfer, source copy, cache adoption from another context and artifact rebinding are forbidden during promotion.

### 20.12 Negative isolation contract

The release gate requires these exact outcomes:

```text
DOSSIER_A_CANNOT_READ_DOSSIER_B_REPOSITORY=PASS
DOSSIER_A_CANNOT_WRITE_DOSSIER_B_REPOSITORY=PASS
DOSSIER_A_CANNOT_OPEN_DOSSIER_B_WORKSPACE=PASS
DOSSIER_A_CANNOT_ACCESS_DOSSIER_B_FILES=PASS
DOSSIER_A_CANNOT_USE_DOSSIER_B_PREVIEW=PASS
DOSSIER_A_CANNOT_REUSE_DOSSIER_B_CACHE=PASS
SAME_CUSTOMER_DIFFERENT_CONTEXT_ISOLATED=PASS
TEST_DOSSIER_CANNOT_MUTATE_REAL_CUSTOMER=PASS
CORE_REPOSITORY_RECEIVES_CUSTOMER_SOURCE=NEE
SHARED_CUSTOMER_WORKTREE=NEE
SHARED_CUSTOMER_REPOSITORY=NEE
CROSS_CONTEXT_REPOSITORY_BIND_DENIED=PASS
CROSS_CONTEXT_WORKSPACE_BIND_DENIED=PASS
CROSS_CONTEXT_ARTIFACT_LEAK=0
CROSS_CONTEXT_CACHE_LEAK=0
```

Tests must use two real-shaped contexts and attempt identifier substitution at every API, database, filesystem, storage, cache, CDN, preview, worker-capability and artifact boundary. They include malicious package lifecycle/build scripts attempting network egress, host-socket access, sibling filesystem reads, secret reads, resource exhaustion and cross-context output writes. A UI-hidden action, UUID prefix or directory name is not an authorization test.

## 21. Threat model

| Threat | Prevention | Detection | Recovery |
| --- | --- | --- | --- |
| GitHub App private-key leak | Secret manager, runtime-only access, no logs/database/browser | Secret scanning, token/audit anomaly review | Pause provider, revoke key, rotate, review affected operations |
| Installation-token leak | JIT memory-only token, <=1 hour, narrow repository scope after creation | Redaction tests and GitHub audit correlation | Revoke installation if active risk, rotate App key, quarantine operations |
| Malicious repository name | Derive from validated UUID; no caller name | Command fingerprint and derived-name audit | Reject command; no external call |
| Cross-dossier repository bind | Locked context/workspace equality and unique external ID | Negative database/Edge/provider tests | Reject and quarantine attempted binding |
| Privilege escalation | Owner+AAL2, server-derived targets, least App permissions | Auth-denial and permission-drift monitoring | Pause command surface and correct policy |
| SSRF | Fixed HTTPS GitHub hosts and endpoints; restricted redirects | Outbound host telemetry | Abort request and quarantine operation |
| GitHub response spoofing | TLS, fixed API host, validate schema/IDs/owner/marker | Provider schema failures and reconciliation mismatch | Discard result, retry only when safe, quarantine ambiguity |
| Replay abuse | Durable idempotency key and immutable fingerprint | Replay/mismatch audit event | Return original result or reject mismatch |
| Orphan repository | Claim before call, deterministic name, early external-ID persistence | Reconciler by operation/name/ID/marker | Verified bind or owner-reviewed quarantine; no auto-delete |
| Compromised starter | Protected release process, immutable tag/SHA, reviewed dependencies | Tree verification, CI and provenance audit | Disable release, block provisioning, publish reviewed successor |
| Malicious starter commit race | Serialize release/generation; verify approved SHA and generated tree | SHA/tree mismatch | Quarantine generated repository |
| XSS in metadata or files | Treat GitHub data as untrusted; escape; MIME allowlist; `nosniff` | Browser security tests | Block rendering and correct sanitizer/policy |
| Webhook forgery | No webhook endpoint in V1 | Route inventory asserts absence | Keep disabled; later require signature and delivery replay defense |

## 22. Audit

Audit events are append-only and contain operation ID, idempotency fingerprint, actor, workspace ID, work-context ID, action, previous/new state, provider, configured organization, derived repository name, external repository ID when known, starter provenance, attempt number, stable result code, GitHub request ID and timestamps.

Audit events exclude source content, file content, customer PII, PEM data, JWTs, installation tokens, authorization headers, temporary clone/download URLs and raw provider error bodies. Provider errors are mapped to stable codes; detailed redacted diagnostics remain in restricted operational logs with retention policy.

GitHub organization audit evidence is correlated using repository external ID, App identity, GitHub request ID and time window. The database operation record remains the LWS lifecycle authority; GitHub audit does not replace it.

## 23. Data model impact

A later migration is required before executable provider integration. It extends `website_execution_workspaces` with:

| Column | Meaning |
| --- | --- |
| `repository_external_id` | Immutable GitHub numeric repository ID |
| `repository_node_id` | GitHub global node ID |
| `repository_visibility` | Must be `private` for this lifecycle |
| `repository_state` | Repository-specific state |
| `starter_source` | Approved template `owner/name` |
| `starter_version` | Semantic starter release |
| `starter_commit_sha` | Exact source template commit |
| `repository_marker_commit_sha` | Commit that added the context marker |
| `repository_bound_at` | Verified binding timestamp |

`repository_url` and `repository_html_url` are derived from configured GitHub host plus verified owner/name; they are not independent authority. Existing URL fields may remain compatibility projections during migration but cannot establish identity.

A separate durable `website_repository_provisioning_operations` table records operation ID, workspace/context IDs, idempotency key/fingerprint, derived name, starter provenance, state, attempt count, stable failure code, retry time, external repository ID/node ID when known and timestamps.

Required constraints include:

- unique `website_work_context_id` in workspaces;
- unique repository external ID where non-null;
- one terminal binding per workspace/context;
- one active provisioning operation per workspace/context;
- immutable workspace/context/operation identity;
- state-shape checks requiring complete metadata only in ready states;
- `private` visibility for bound PRE_PROJECT repositories;
- no secret, token or source-content columns;
- trigger/RPC rejection of cross-context or cross-workspace binding.

Existing state constraints must be migrated explicitly to include `REPOSITORY_PROVISIONING`, `REPOSITORY_READY` and `REPOSITORY_FAILED`. The migration must preserve current rows and fail if an existing row violates the new shape.

## 24. Edge contracts

### Provision repository

Browser request remains authority-minimal:

```json
{
  "website_workspace_id": "uuid",
  "website_work_context_id": "uuid",
  "idempotency_key": "uuid"
}
```

Repository name, owner, visibility, template, branch and credentials are server-derived. The Edge function requires owner+AAL2, calls a database claim RPC, invokes the provider only for `CLAIMED`, and completes binding through a second database authority RPC. `REPLAY` returns the stored result; `IN_PROGRESS` returns a stable conflict.

### Read project file

```json
{
  "website_work_context_id": "uuid",
  "path": "src/pages/index.astro",
  "ref": "main"
}
```

The function derives workspace and repository, applies read policy, and returns escaped content metadata plus content only when allowed. It never returns a provider token or temporary GitHub URL.

### Reconcile operation

Only an owner-authorized operational command or scheduled trusted worker can submit an operation ID. It cannot choose a replacement repository. Reconciliation verifies the original durable claim and returns `BOUND`, `RETRY_SCHEDULED`, `BLOCKED`, `QUARANTINED` or `TERMINAL_FAILED`.

Stable error families include invalid command, unauthorized context, invalid lifecycle, claim conflict, configuration blocked, provider unavailable, rate limited, external outcome unknown, repository identity mismatch, marker mismatch, starter provenance mismatch, cross-context bind denied and binding failed.

## 25. Testing

### Unit and contract tests

- Exact command key validation and server-derived provider request.
- GitHub response schema, external ID, owner, visibility, branch and marker validation.
- Name derivation for valid/invalid UUIDs.
- Token and error redaction.
- Redirect/host/path/ref/MIME/size allowlists.
- Idempotent replay, fingerprint mismatch and concurrent claim behavior.
- Provider never invokes delete, transfer, visibility change or workflow mutation.

### Database tests

- Owner, AAL2 and caller JWT requirements.
- Workspace/context locking and immutable identity.
- Unique external repository ID and one active operation.
- Every legal and illegal state transition.
- Cross-context/workspace binding denial.
- Replay returns exact stored terminal result.
- No repository-ready shape with partial provenance.

### Provider integration tests

Run against a dedicated test organization and test App only after separate approval. Cover successful template generation, private-template denial, token expiry, rate limit, 5xx, timeout after create, same-name foreign repository, missing/mismatched marker, source-tree race and recovery from captured external ID. Cleanup is owner-reviewed or uses a separately approved test-only cleanup command with marker verification.

### Starter tests

- Clean install from committed lockfile.
- Typecheck, lint and static production build.
- HTML semantics, metadata, sitemap, robots, 404 and asset paths.
- Accessibility and reduced-motion checks.
- Desktop/mobile Playwright screenshots.
- Optional canvas pixel check when a starter release includes a 3D reference fixture.
- No secret-like values, customer content or active deployment configuration.

### Isolation and security tests

Run the exact negative contract in section 20.12 across database, Edge, provider, filesystem launcher, cache, artifacts and preview. Add token-leak snapshots, XSS payloads in repository metadata/file names/content, traversal and symlink escape attempts, SSRF host mutations and replay storms.

## 26. Implementation phases

1. Owner approves this design and the isolation contract.
2. Create and security-review the separate private Astro template repository and immutable starter release process.
3. Register the LWS GitHub App with the stated minimum permissions; install it only after credential and incident procedures are approved.
4. Add the repository-operation migration, constraints, claims, binding authority and pgTAP tests without activating external calls.
5. Implement App JWT/token broker and GitHub provider behind the existing inert interface with fake HTTP contract tests.
6. Add reconciliation and quarantine operations before enabling repository creation.
7. Add the owner+AAL2 Edge command behind a disabled feature flag and test-organization allowlist.
8. Run approved test-island integration and negative isolation suites.
9. Add local VS Code launcher and read-only project-file projection.
10. Design and validate isolated preview build/storage separately.
11. Conduct owner security/release review before any production enablement.

Each phase has its own rollback and approval. Completing a phase does not authorize the next one.

## 27. Release boundaries

This design phase changes documentation only. It does not authorize or perform:

- GitHub App registration or installation;
- secret, private key, PAT or OAuth-token creation;
- external repository or template creation;
- external GitHub API calls;
- Edge function activation;
- migration execution;
- project-file writes;
- webhook creation;
- preview or production deployment;
- push to any remote;
- production or customer mutation.

The first executable release must remain deny-by-default behind an owner-controlled feature flag and test-organization allowlist. Production release requires evidence for all tests in sections 20.12 and 25, least-permission verification, key rotation rehearsal, timeout/orphan reconciliation, quarantine review and an explicit owner go/no-go decision.

Owner review is the hard stop for this document.