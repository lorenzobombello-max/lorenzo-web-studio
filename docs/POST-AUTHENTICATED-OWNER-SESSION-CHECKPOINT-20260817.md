# Post-Authenticated Owner Session Checkpoint

Date: 2026-08-17
Status: **PASS - first real human production owner authentication verified**

## Release identity

- Production site: `https://lorenzowebsolutions.be/operator/`
- Deployed source commit: `515fda40eebffb3832cd6236ec4f78a7bf492196`
- Pages run: `31982818963` (`completed / success`)
- Database migration parity: `43/43`
- Parent deployment manifest SHA-256: `877a48f90716f654ce0fe0c892672acf255df5af2441de5021159727d88f4e9c`

## Human session evidence

Lorenzo completed the first real production sign-in with the registered owner Gmail account. Lorenzo observed the production operator page showing:

- `Sessie actief`
- the registered owner/operator email address
- `Autorisatie: Databasegestuurd`
- `Afmelden`

The active authenticated tab was not navigated, reloaded, refreshed, signed out, or otherwise used by this verification. The shared automation tab remained the earlier unauthenticated callback probe and was not substituted for Lorenzo's active tab.

Production Auth independently recorded:

- Auth user UUID: `993a4b95-0d63-48e7-9733-0bda6422b50f`
- provider: `email`
- email confirmed: `true`
- email identities: `1`
- last sign-in: `2026-08-17 00:49:38.106696+00`

Together, the human-visible authenticated shell and the independently recorded Auth sign-in establish that the production human authentication path is operational.

## Server-side identity and authority

The registered Auth identity resolves in production to:

- operator UUID: `2f1810a9-84f5-4b26-93d3-3934a2970c46`
- role: `owner`
- status: `ACTIVE`
- `OWNER_BOOTSTRAPPED` events: `1`

Live function-definition checks confirmed that the authorization resolver:

- derives the caller from `auth.uid()`;
- reads `commercial_operators`;
- reads `commercial_operator_project_grants`;
- is called by `execute_commercial_command_v2`;
- requires the database owner role for operator-status administration.

All three authority tables retain RLS and FORCE RLS. `authenticated` and `service_role` retain no direct SELECT or DML privileges on those tables. `authenticated` cannot execute the resolver directly, and `service_role` has no `USAGE` on `lws_internal`.

The browser shell reads only the supported SDK session email. It contains no custom local/session storage, owner-role assignment or comparison, operator/project/grant identity fields, or browser-derived authorization decision. `Databasegestuurd` is display copy, not an authority grant.

## Current capability boundary

The production operator shell exposes no forms and only one button: local sign-out. It exposes no customer, project, grant, commercial command, invoice, or fiscal controls.

The live database grants `authenticated` execution only on the current commercial RPC boundary:

- `consume_commercial_operator_rate_limit_v1`
- `execute_commercial_command_v2`
- `get_commercial_project_view_v2`
- `set_commercial_operator_status_v1`

Each RPC remains subject to server-side identity, operator status, role, project scope, command allowlist, and/or owner checks. Customer commercial RPCs remain service-role only. The Edge function rejects caller-supplied identity fields and accepts only its fixed non-fiscal operator command allowlist.

No authenticated RPC or Edge command was invoked during this verification because command execution and rate-limit consumption can write state. The non-mutating unauthenticated Edge boundary check returned HTTP 401 as expected.

Customer accounts remain explicitly out of scope. The architecture remains Lorenzo/operator authentication plus controlled customer access links; there is no customer login or account system.

## Preservation results

- migrations: `43/43`
- `commercial-operator-command`: `ACTIVE`, version `1`, `verify_jwt=true`
- Edge deployment SHA-256: `a7d15591c8ff54f35e36069dcfdccb81939ed5c3f78fda71a5f9774d25e3a68a`
- exact active owner rows: `1`
- owner bootstrap events: `1`
- operator rate-limit rows: `0`
- customers: `0`
- projects: `0`
- grants: `0`
- workflow events: `0`
- audit events: `0`
- fiscal production: disabled and unchanged

The verification performed zero database, Auth, owner, RLS/policy, migration, secret, Edge deployment, customer, project, grant, workflow, invoice, or fiscal writes. The human sign-in itself updated normal Supabase Auth sign-in telemetry before this read-only verification began.

## Decision

The first real human production owner session is verified. Authentication is operational; the expected Auth identity maps to the expected ACTIVE owner; authorization remains database-driven; current browser and server capability boundaries remain unchanged; and the 43/43 security baseline is preserved.

Stop here. Do not begin a new commercial/business-flow phase or customer-account work from this checkpoint.
