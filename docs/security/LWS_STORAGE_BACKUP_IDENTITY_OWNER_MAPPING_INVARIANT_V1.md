# LWS Storage Backup Identity Owner-Mapping Invariant V1

Status: `LOCAL DESIGN ONLY - NOT ACTIVATED`

Design date: `2026-09-06`

## 1. Purpose

This design defines the database invariant for the future dedicated Storage backup Auth identity:

> The exact backup Auth UUID must never occur in `public.commercial_operators` with both `status = 'ACTIVE'` and `role = 'owner'`.

This artifact does not create an Auth user, choose a UUID, execute SQL, add a constraint, change a policy, access Storage, deploy, or authorize activation.

## 2. Required Boundary

The invariant is bound to the immutable Auth UUID, not to email, display name, JWT metadata, application metadata, or a PostgreSQL role name. Those labels are mutable or belong to a different authority plane.

The future constraint must enforce this predicate on every row of `public.commercial_operators`:

```sql
auth_user_id <> '<EXACT_BACKUP_AUTH_UUID>'::uuid
or status <> 'ACTIVE'
or role <> 'owner'
```

The placeholder makes this document non-activatable. A migration candidate may be prepared only after the dedicated Auth identity exists and its exact UUID has been independently verified.

## 3. Enforcement Design

Use a named table `CHECK` constraint on `public.commercial_operators`. Do not implement the rule only in an RPC, RLS policy, application check, trigger, email convention, or operator workflow.

The future activation sequence is fail-closed:

1. create the dedicated Auth identity under separate owner approval;
2. capture and independently verify its exact UUID without storing credentials;
3. prove there is no existing `commercial_operators` row for that UUID;
4. substitute the exact UUID into a reviewed migration candidate;
5. add the constraint as `NOT VALID`;
6. validate the constraint in the same approved change window;
7. verify the constraint is present and validated (`convalidated = true`);
8. only after that evidence, consider the UUID-bound Storage `SELECT` policy in a separate review.

Failure or uncertainty at any step is `NO-GO`. The backup policy must not be activated while the constraint is absent, unvalidated, disabled, or bound to a different UUID.

## 4. Why A Table Constraint

A row constraint is evaluated for direct inserts and updates regardless of which approved write path attempts the mapping. It has no cross-table race and cannot be bypassed by calling a different application RPC. Existing AAL2 protections remain defense in depth; they are not the invariant itself.

PostgreSQL superusers and sufficiently privileged table owners can alter or drop database constraints. Therefore the operational authority model must continue to prohibit the backup runtime from receiving superuser, `BYPASSRLS`, owner, DDL, or role-membership authority. Constraint-presence verification is required after every production schema change affecting `commercial_operators` or backup identity authority.

## 5. Required Pre-Activation Tests

Run these tests only in an isolated database or an explicitly approved production transaction that is guaranteed to roll back:

- inserting the exact backup UUID as `ACTIVE owner` fails with the named constraint;
- updating that UUID from another role or status to `ACTIVE owner` fails;
- updating an existing `ACTIVE owner` row to the backup UUID fails;
- the backup UUID with a non-owner role is not rejected by this specific invariant;
- the backup UUID with a non-active status is not rejected by this specific invariant;
- another Auth UUID can retain the existing valid owner behavior;
- catalog evidence proves the constraint definition contains the exact UUID and `convalidated = true`;
- fresh policy, ACL, role-attribute, and transitive-membership evidence still passes the separate authority review.

These are design requirements, not authorization to create fixtures or mutate production.

## 6. Local Fail-Closed Generator

The local generator is implemented in `scripts/security/storage-backup-owner-mapping-guard/storage-backup-owner-mapping-guard.mjs`.

- It accepts only one explicit canonical, non-zero UUID through `--auth-uuid`.
- Missing, malformed, uppercase, placeholder, zero, whitespace-padded, or extra input fails before SQL is returned or written to stdout.
- Generated SQL adds only the named row-local `CHECK` to `public.commercial_operators`, first as `NOT VALID` and then validates it.
- The row-local predicate covers INSERT and every UPDATE ordering, including changing role/status separately and changing an existing owner's `auth_user_id`.
- Other Auth UUIDs and non-`ACTIVE owner` states for the backup UUID remain outside this invariant.
- Every generated candidate contains an executable unconditional stop and remains `LOCAL_CANDIDATE_NOT_PRODUCTION_ACTIVATABLE`.

Focused local tests cover generator rejection, no-output CLI behavior, candidate structure, INSERT, both UPDATE shapes, both role/status orderings, and unaffected records. They do not execute the candidate against production or authorize removal of the activation guard.

## 7. Review Gates

`BACKUP_IDENTITY_OWNER_MAPPING_BLOCK = designed` means only that the enforcement mechanism and validation contract are specified locally.

Activation remains `NO-GO` until all of the following are proven:

- exact backup Auth UUID exists and is independently verified;
- no current commercial operator mapping exists for that UUID;
- the exact-UUID constraint candidate has passed isolated positive and negative tests;
- the applied constraint is present and validated;
- complete current effective Storage `SELECT` authority is documented;
- the backup runtime cannot assume `service_role`, a Storage owner role, table ownership, superuser, `BYPASSRLS`, or any inherited equivalent;
- the UUID-bound backup policy is separately reviewed and approved.

## 8. Current Outcome

- Local invariant design: `DESIGNED`.
- Fail-closed generator: `IMPLEMENTED`.
- Focused local tests: `10/10 PASS`.
- Exact UUID binding: `MISSING`.
- UUID-bound migration candidate: `NOT MATERIALIZED`.
- Candidate activation state: `NO-GO`.
- Production constraint: `NOT CREATED`.
- Production mutation: `NONE BY THIS DESIGN ARTIFACT`.
