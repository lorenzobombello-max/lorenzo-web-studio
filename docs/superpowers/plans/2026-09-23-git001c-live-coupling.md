# GIT-001C Live Coupling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Couple the locally proven async customer-source preview build to GitHub Actions and a private production preview host without weakening operator AAL2 or dispatching before every trust boundary is production-proven.

**Architecture:** The operator's AAL2-authorized acquire creates one lease plus one server-authorized build ID. A platform-repository GitHub Actions workflow obtains a one-repository, `contents:read` GitHub App installation token for fetch, builds without credentials on an isolated network, and uses platform-workflow OIDC to upload bounded raw files into private Supabase Storage. A catch-all Cloudflare Pages Function at `preview.lorenzowebsolutions.be` receives every website path and proxies it through a purpose-authenticated Supabase Edge origin; the origin keeps service-role/private-Storage authority inside Supabase, exchanges one-time handoffs for host-only sessions, and streams only session-bound build assets.

**Tech Stack:** PostgreSQL 17, Supabase Edge Functions/Storage/Auth, Cloudflare Pages Functions on Workers Paid, Deno 2.9.5, GitHub Actions OIDC, GitHub App installation tokens, Docker, Astro 7.3.2.

**Spec:** `docs/superpowers/checkpoints/2026-09-23-git001c-astro-preview-build-local-verification.md`

## Global Constraints

- Work only on `git001c-astro-preview-build-20260922`; preserve dirty work.
- `NO_SECOND_CREATE` remains HARD; never create a second customer repository.
- No production migration, deployment, workflow dispatch, DNS change, paid activation, push, or merge without a separate explicit approval.
- Keep operator control-plane RPCs caller-JWT plus AAL2; workflow data-plane RPCs remain service-role only and bound to the delegated lease.
- Customer source identity and platform workflow identity remain separate trust domains.
- Build containers receive no OIDC token, installation token, service role, or reusable platform secret.
- Never delete customer repository data during rollback.

## Review Focus

- GitHub legacy and immutable OIDC subjects must both bind to the exact platform repository ID, ref, workflow ref, run, audience, lease, and build.
- A caller-selected build ID must fail at authority resolution and direct token/session inserts.
- A streamed upload that lies about `Content-Length` must stop at 5 MiB + 1 without invoking Storage.
- Storage cleanup must remain retryable after upload completion or object deletion fails.
- Preview routing must reject decoded traversal/backslashes/null bytes and map `/directory/` to `directory/index.html`.

---

### Task 1: Finish Production-Path Integration Evidence

**Files:**
- Modify: `supabase/functions/website-project-preview-artifact/index.ts`
- Modify: `supabase/functions/_shared/website-project-preview-e2e-real-build.integration.test.ts`
- Test: `supabase/functions/website-project-preview-artifact/handler.test.ts`

**Interfaces:**
- Consumes: `createWebsiteProjectPreviewArtifactReceiptService()` and the service-role RPCs introduced through migration `20260923110000`.
- Produces: `createWebsiteProjectPreviewArtifactRuntime(env, fetch)` returning the exact service passed to `handleWebsiteProjectPreviewArtifact()`.

- [x] **Step 1: Extract the runtime factory without changing the deployed handler contract.** Move environment parsing and RPC/Storage adapters from module initialization into `createWebsiteProjectPreviewArtifactRuntime`; keep `Deno.serve` as a thin composition root.
- [x] **Step 2: Add a RED integration that invokes HTTP `issue`, `begin`, raw `upload`, and `finalize`.** Use locally signed GitHub OIDC plus local JWKS, real local PostgreSQL RPCs, and the private `website-project-previews` bucket; assert the server-authorized build ID and customer commit are preserved.
- [x] **Step 3: Extend failure assertions.** Prove wrong platform repository ID, wrong workflow ref, wrong build ID, receipt replay, incomplete manifest, expiry, concurrent claim, and abort/remove retry fail closed.
- [x] **Step 4: Run the exact production-path integration.** Run `deno test --allow-all supabase/functions/_shared/website-project-preview-e2e-real-build.integration.test.ts`; expect the exact customer commit `1f19bf01c61c6da79fa4c7374333a91b70f9bf48`, same-run direct-network denial, HTTP upload chain, private Storage serving, and cleanup to pass.
- [x] **Step 5: Request independent review.** Reviewer must confirm the test imports the production runtime factory and does not duplicate adapters.

### Task 2: Implement the OIDC-Gated GitHub App Fetch Broker

**Files:**
- Create: `supabase/functions/website-project-preview-source-token/handler.ts`
- Create: `supabase/functions/website-project-preview-source-token/index.ts`
- Create: `supabase/functions/website-project-preview-source-token/handler.test.ts`
- Modify: `.github/workflows/build-website-project-preview.yml`
- Modify: `supabase/config.toml`

**Interfaces:**
- Consumes: platform OIDC authority fields and lease/customer source authority resolved server-side.
- Produces: one short-lived installation token response containing `token` and `expires_at`; token permissions are exactly `{ contents: "read" }` and `repository_ids` contains exactly the authorized customer repository ID.

- [x] **Step 1: Write RED broker tests.** Cover valid platform OIDC, legacy/immutable subject, wrong run/repository/ref/workflow, expired lease, wrong customer repository, and requested permissions wider than `contents:read`.
- [x] **Step 2: Implement handler and server adapter.** Verify GitHub OIDC, resolve lease authority, create a GitHub App JWT server-side, call `POST /app/installations/{installation_id}/access_tokens` with one `repository_ids` entry and `{ "contents": "read" }`, and never return the app JWT.
- [x] **Step 3: Replace the workflow hard fail.** Fetch obtains its own OIDC token, calls the broker, checks out only `repository_owner/repository_name` at exact `commit_sha`, verifies `git rev-parse HEAD`, removes `.git`, uploads the source artifact, and unsets the installation token before completion.
- [x] **Step 4: Prove credential separation.** Workflow static test must assert build/upload jobs cannot reference the installation token and build has no `id-token: write`.
- [x] **Step 5: Run broker and workflow tests.** Run the targeted Deno tests plus the workflow contract test; expect all fail-closed cases and token-placement assertions to pass.

### Task 3: Implement the Cloudflare Pages Front Door and Supabase Origin

**Files:**
- Create: `cloudflare/website-project-preview-host/functions/[[path]].ts`
- Create: `cloudflare/website-project-preview-host/functions/preview-host.test.ts`
- Create from reviewed examples: `cloudflare/website-project-preview-host/wrangler.jsonc`
- Create from reviewed example: `cloudflare/website-project-preview-host/public/_routes.json`
- Create: `supabase/functions/website-project-preview-host/handler.ts`
- Create: `supabase/functions/website-project-preview-host/index.ts`
- Create: `supabase/functions/website-project-preview-host/handler.test.ts`
- Modify: `supabase/config.toml`
- Create: additive migration for atomic one-time handoff consumption and independent viewer-session token rotation.
- Reuse: `supabase/functions/_shared/website-project-preview-hosting-gateway.ts`
- Reuse: `supabase/functions/_shared/website-project-preview-local-hosting-gateway.ts`

**Interfaces:**
- Consumes: one-time handoff token, server-side preview session/build resolution, private Storage object path `{authorized_build_id}/{relative_path}`, and a purpose-specific Worker-to-origin secret.
- Produces: public `GET /handoff?token=...` plus arbitrary website paths on `preview.lorenzowebsolutions.be`, a rotated `HttpOnly; Secure; SameSite=Lax; Path=/` host-only cookie, and session-bound asset responses. `_routes.json` includes `/*`, so every path invokes auth and no static fallback can bypass the Function.

- [x] **Step 1: Write RED front-door and origin tests.** Cover direct-origin requests without the purpose secret, one-time handoff replay, 30-minute session expiry, cross-build denial, `/` and `/about/`, assets, malformed encoding, encoded traversal, backslashes, null bytes, missing objects, blocked SVG absence, and exact response content types.
- [x] **Step 2: Add atomic handoff rotation.** Extend the existing hash-only preview-session persistence with one additive service-role RPC that consumes the handoff hash once, stores a freshly generated viewer-session hash, and leaves the existing 30-minute expiry/revocation and cleanup authority intact.
- [x] **Step 3: Implement the Supabase Edge origin.** Require the purpose-specific origin secret before all work, call the existing service-role session resolver, normalize paths with `normalizeWebsiteProjectPreviewAssetPath`, fetch `{previewBuildId}/{relativePath}` from private `website-project-previews` Storage, and return bytes plus an internal authoritative content-type header and `Cache-Control: private, no-store`.
- [x] **Step 4: Implement the Cloudflare Pages Function.** Use `functions/[[path]].ts` plus `_routes.json` include `/*`; forward method, original path/query and preview cookie to the fixed Supabase origin with the origin secret, restore the authoritative content type, remove internal headers, preserve `Set-Cookie`/redirect status, force fail-closed behavior, and never cache authenticated responses. Redirect the project `pages.dev` production hostname to the custom hostname so it is not a second usable preview origin.
- [x] **Step 5: Run local HTTP integration.** Assert real HTML/CSS/image navigation, directory indexes, one-time exchange, session isolation, expiry, normal website paths and cleanup against local PostgreSQL/private Storage through both layers.
- [ ] **Step 6: Keep routing activation gated.** First associate `preview.lorenzowebsolutions.be` with the Pages project, then add only the OVH CNAME `preview` to the assigned `<project>.pages.dev` hostname and verify managed TLS; do not migrate authoritative DNS and do not buy or activate a Supabase custom domain.

### Task 4: Production Preflight Without Deployment

**Files:**
- Modify: `docs/superpowers/checkpoints/2026-09-23-git001c-astro-preview-build-local-verification.md`
- Modify: `.superpowers/sdd/009-git001c-astro-preview-build-plan/progress.md`

**Interfaces:**
- Consumes: deployable migrations/functions/workflow from Tasks 1-3.
- Produces: signed-off, value-free configuration inventory and ordered deployment runbook.

- [x] **Step 1: Inventory production state read-only.** Captured in the local verification checkpoint. Supabase, public DNS and repository/commit identity were readable; GitHub App/Actions, Cloudflare and OVH account state were unavailable, and the production workspace row could not be queried without an unavailable database credential. These are recorded as hard pre-deployment blockers, not assumed values. The target `pages.dev` hostname/CNAME remains explicitly unknown.
- [x] **Step 2: Record configuration names without values.** In addition to the existing OIDC/source/artifact/GitHub App names, require public `LWS_PREVIEW_HOST_URL=https://preview.lorenzowebsolutions.be`, Worker `LWS_PREVIEW_ORIGIN_URL`, and matching Worker/Supabase secret `LWS_PREVIEW_ORIGIN_TOKEN`. Never place the token or Supabase service-role value in source or Wrangler `vars`.
- [x] **Step 3: Validate permissions read-only.** GitHub workflow jobs: fetch `id-token:write`, upload `id-token:write`, build no OIDC; App installation token: one repository and `contents:read`; Supabase RPC grants: workflow functions service-role only, operator acquire/finalize/session functions authenticated only.
- [ ] **Step 4: Run final local gate.** Run full Deno typechecked suite, Linux manifest suite, operator mounted tests, exact-source production-path integration, receipt concurrency, upload-session integration, and workflow static tests; attach exact counts and command outputs.
- [ ] **Step 5: Obtain explicit approvals.** Required approvals are the Cloudflare Workers Paid minimum of `$5 USD/account/month` plus metered overage, one new OVH CNAME for `preview`, production migration/deploy, controlled 0006 dispatch, and use of the existing customer repository/commit. Absence of any approval is a hard stop.

### Task 5: Controlled Deployment and 0006 Dispatch

**Files:**
- No source edits during execution; use reviewed artifacts from the approved commit.

**Interfaces:**
- Consumes: explicit Task 4 approvals and one reviewed commit SHA.
- Produces: one auditable 0006 workflow run or a fail-closed rollback with customer data untouched.

- [ ] **Step 1: Create the recovery checkpoint.** Record database backup/PITR state, current migrations/functions/domain/DNS, reviewed commit SHA, customer repository ID, exact customer commit, and responsible operator.
- [ ] **Step 2: Apply additive migrations in timestamp order.** Apply through `20260923110000`; verify columns, triggers, RPC definitions, and grants before function deployment.
- [ ] **Step 3: Deploy functions while workflow remains undispatched.** Deploy artifact broker, source-token broker and the purpose-authenticated Supabase preview origin; set reviewed secrets/config; prove direct origin calls without the Worker secret fail before any database or Storage access.
- [ ] **Step 4: Deploy Pages Functions without DNS.** Direct-upload the reviewed catch-all Function/config to one Pages project, configure the encrypted origin token, set fail-closed quota behavior, and prove the assigned `pages.dev` deployment through negative origin/auth probes before making it discoverable to customers.
- [ ] **Step 5: Associate the custom subdomain and add one OVH CNAME.** Add `preview.lorenzowebsolutions.be` to the Pages project first, then create OVH CNAME `preview` to the assigned `<project>.pages.dev`, verify managed TLS, redirect the default production hostname to the custom hostname, set `LWS_PREVIEW_HOST_URL`, and verify all paths, host-only cookie, HTML content type, no public Storage access and no authenticated caching. On failure remove only this CNAME/domain association and leave apex, `www`, MX/TXT, website, mail, Supabase Auth and customer data intact.
- [ ] **Step 6: Merge/publish the reviewed workflow commit.** Confirm workflow remains `workflow_dispatch` only and resolve its exact platform repository ID/ref/workflow ref into function configuration.
- [ ] **Step 7: Acquire one 0006 authority through the AAL2 operator path.** Capture returned lease ID and server-authorized build ID; independently resolve customer repository ID and exact commit; never invent workflow inputs client-side.
- [ ] **Step 8: Dispatch exactly once.** Supply repository owner/name/ID, exact commit SHA, lease ID, and authorized build ID; watch fetch, isolated build, bounded upload, finalize, status, handoff, and browser asset navigation.
- [ ] **Step 9: Evaluate success.** Require exact checkout SHA, direct-network denial, no credential in build, matching platform OIDC, all manifest files received, terminal `PASS` or `PASS_WITH_WARNINGS`, private Storage, and session-bound HTML/CSS/image navigation.
- [ ] **Step 10: Execute fail-closed rollback if needed.** Disable dispatch/source-token endpoint, revoke preview sessions, abort upload session and retry object cleanup, release lease, remove the Worker custom-domain route or revert additive migration only where dependency-safe, and do not delete or mutate the customer repository.
- [ ] **Step 11: Close evidence.** Append workflow run ID, immutable logs, final status, preview checks, cleanup/retention result, costs, and rollback decision to both checkpoints. Keep GIT-001C OPEN until independent review accepts production evidence.

## Official Provider Basis

- GitHub OIDC: `repository`/`repository_id` identify the workflow repository; `ref`, `workflow_ref`, `run_id`, custom `aud`, and legacy/immutable `sub` forms are official claims. `id-token: write` only permits requesting the JWT.
- GitHub App tokens: `repository_ids` can narrow access to one installation repository; `permissions` can narrow to `contents:read`; token expiry is one hour.
- Supabase Storage: private access is RLS-controlled; service keys bypass RLS and must remain server-only.
- Supabase states that Edge Functions do not support HTML responses and that Supabase custom domains are not intended for frontend hosting; functions remain under `/functions/v1/<function>`, so the `$10/domain/month/project` add-on does not provide the required root-path preview host.
- Cloudflare Pages officially permits an externally managed subdomain via CNAME to `<project>.pages.dev`; authoritative nameservers need not move. Pages Functions support a catch-all route and `_routes.json` include `/*`. Function invocations use Workers pricing. Workers Paid currently has a `$5 USD/account/month` minimum, includes 10 million requests and 30 million CPU milliseconds monthly, then charges `$0.30/million` requests and `$0.02/million` CPU milliseconds; Worker egress is not charged.
- Official sources checked 2026-09-23: `https://supabase.com/docs/guides/platform/custom-domains`, `https://supabase.com/docs/guides/functions/http-methods`, `https://supabase.com/pricing`, `https://developers.cloudflare.com/pages/configuration/custom-domains/`, `https://developers.cloudflare.com/pages/functions/routing/`, `https://developers.cloudflare.com/pages/functions/pricing/`, and `https://developers.cloudflare.com/workers/platform/pricing/`.
