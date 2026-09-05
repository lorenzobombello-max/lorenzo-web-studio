# LWS Storage Backup Identity And RLS Activation Design V1

Evidence date: `2026-09-05`

Phase: `P0-6E.6B`, continuation from the fixed MODEL A baseline

Artifact status: `DESIGN_ONLY_NOT_ACTIVATABLE`

Production activation: `NO-GO`

## 1. Scope And Preserved Baseline

This is not a new phase and does not redesign P0-6E.6B MODEL A. The fixed route is:

```text
MODEL_A_KNOWN_BUCKET_OBJECT_ONLY
exact known bucket names
ListObjectsV2 + GetObject
storage.objects SELECT
no ListBuckets
no storage.buckets SELECT
```

The exact bucket allowlist is:

- `customer-request-quarantine`;
- `quotation-artifacts`;
- `recruitment-cvs`;
- `supplier-documents`.

This slice produced only local design, tests, inert SQL candidates, and a static verifier. It created no Auth user or secret, executed no SQL, called no production Storage endpoint, and performed no deployment.

## 2. Dedicated Identity Contract

The future identity name is `lws-storage-backup-reader`. It must be a dedicated Supabase Auth user used only by the backup runtime. It may not be an operator, customer, shared automation identity, service role, database role, or S3 access-key identity.

Activation binds RLS to one exact `auth.users.id` UUID through `auth.uid()`. Email, mutable user metadata, role-name text, and a generic `authenticated` check are insufficient identity selectors.

The UUID may enter a materialized activation artifact only after evidence proves all of the following:

1. it is a valid non-zero UUID belonging to `lws-storage-backup-reader`;
2. it is not assigned to any application user or operator;
3. the identity has no unrelated role, membership, profile, owner mapping, or application authority;
4. the reviewer records the evidence without recording credentials or tokens.

The inert candidate deliberately contains no deployable example UUID. Its activation guard and invalid replacement token must be removed only in a separately reviewed materialization step.

## 3. RLS Policy Contract

The proposed policy is one permissive `SELECT` policy on `storage.objects`, for `authenticated`, constrained by:

```text
auth.uid() = exact dedicated backup Auth UUID
AND bucket_id IN exact four-bucket allowlist
```

It grants no `INSERT`, `UPDATE`, `DELETE`, or `ALL` policy and creates no `storage.buckets` policy, function, RPC, database role, `SECURITY DEFINER` path, service-role path, or S3 access key.

Official Storage references state that object listing and private authenticated download each require `storage.objects SELECT`, while neither requires `storage.buckets` authority. `ListObjectsV2` and `GetObject` are supported S3 endpoints. Therefore one exact object policy supports the two required backup operations without bucket enumeration.

Supabase documents operation-aware helpers and the identifiers `object.list` and `storage.object.get_authenticated`. MODEL A does not need an operation helper: its single policy intentionally supports both LIST and GET. No unproven S3 helper mapping is placed in activatable SQL.

## 4. Inherited Authority And OR Composition

PostgreSQL permissive policies combine with OR semantics. The new SELECT-only policy cannot by itself prove that the same Auth identity has no authority inherited from another policy.

P0-6E.4 evidence records one current Storage policy:

| Policy | Command | Role | Condition |
| --- | --- | --- | --- |
| `recruitment_cvs_owner_read_v1` | `SELECT` | `authenticated` | `recruitment-cvs` plus active commercial owner mapping for `auth.uid()` |

The `2026-09-05` read-only authority closure proves the database-role path for an ordinary future `authenticated` session: direct schema `USAGE` and table `SELECT`, no parent-role membership, no superuser or `BYPASSRLS`, no ownership, RLS enabled, and `FORCE RLS` disabled. It also proves that `service_role` bypasses RLS and that relation owner `supabase_storage_admin` has owner bypass while `FORCE RLS` remains disabled; neither authority is permitted for the backup runtime.

For the future backup UUID, the existing owner-policy branch remains `UNPROVEN`, not `SAFE`, until evidence excludes an active commercial-owner mapping and every other application identity path. This is now an identity-mapping uncertainty, not an ACL, membership, ownership, role-attribute, or RLS-flag uncertainty. The recorded inventory contained no write policy, but activation still requires a fresh complete live inventory because policy and privilege state can change.

Each applicable policy must be classified independently for `SELECT`, `INSERT`, `UPDATE`, and `DELETE`:

- `SAFE`: the condition demonstrably excludes the dedicated UUID or grants only the intended read;
- `UNSAFE`: the dedicated UUID can satisfy an unrelated or write condition;
- `UNPROVEN`: completeness or condition outcome is unknown.

Any `UNSAFE` or `UNPROVEN` write axis blocks activation. Unknown policy conditions fail closed. A policy for `authenticated`, `public`, or another role inherited by the identity must be included.

## 5. Session And Secret Lifecycle

The S3 client must use a Supabase user access JWT as the S3 session token. Generated S3 access keys and service-role credentials bypass RLS or exceed the route and are rejected.

Only the minimum Auth bootstrap/session material may be stored in the protected server-side secret store. Database URLs, database passwords, service-role keys, generated S3 access keys, and Postgres credentials are prohibited. Passwords, access tokens, refresh tokens, and session material must never enter source control, logs, stack traces, manifests, backup packages, telemetry, or error responses.

The unattended runtime contract is:

1. load protected bootstrap/session material without logging it;
2. serialize refresh-token use so rotation cannot race;
3. refresh before every Storage operation when the access token is expired or near expiry;
4. verify the resulting authenticated user against the exact approved UUID;
5. construct the S3 session-token client only after that verification;
6. execute only `ListObjectsV2` and `GetObject` against the four configured buckets;
7. discard access-token material from memory as soon as practical;
8. persist a rotated refresh token atomically and recover safely after restart.

Refresh failure, missing session, revoked session, disabled or deleted identity, wrong UUID, malformed token, unknown lifecycle state, excessive clock skew, or exhausted retry/rate-limit budget must abort before any Storage call. A `429` uses bounded backoff and does not fall back to broader credentials. Refresh is rate-limited by IP; the reviewed default is 1800 token refresh requests per hour with bursts up to 30.

Refresh tokens are normally single-use and rotate. Reuse outside documented exceptions can terminate the session. Sign-out revokes refresh capability, but an issued access JWT can remain valid until expiry; the design therefore uses short-lived access tokens and treats emergency revocation as complete only after the remaining JWT lifetime or an additional verified session check.

## 6. Activation Sequence

Every step is a stop gate:

1. Reconfirm the fixed MODEL A artifact hashes and an empty staging area.
2. Create the dedicated Auth user through an approved production change outside this design phase.
3. Capture its UUID and prove identity exclusivity without capturing credentials.
4. Obtain a fresh, complete live inventory of Storage policies, grants, role inheritance, and relevant application identity mappings.
5. Classify inherited authority for all four commands; resolve every `UNSAFE` and `UNPROVEN` write path.
6. Materialize a new SQL artifact with the exact proven UUID; remove the design guard and invalid token; do not alter the bucket or command contract.
7. Run the static verifier and independent review over the materialized artifact and rollback.
8. Prepare protected runtime secret storage and prove serialized refresh, atomic rotation, restart recovery, redaction, rate-limit handling, and fail-closed behavior.
9. Apply the reviewed policy through the approved deployment path.
10. Verify policy definition and effective identity before any content read.
11. Execute the positive and negative plan below using only synthetic data.
12. Capture sanitized evidence, approve production backup separately, or roll back immediately on any mismatch.

## 7. Positive And Negative Proof Plan

Positive proof requires:

- authenticated user resolution equals the exact approved UUID;
- paginated `ListObjectsV2` succeeds in each exact bucket;
- `GetObject` succeeds for the synthetic object in each exact bucket;
- downloaded bytes have the expected SHA-256 digest;
- no `ListBuckets` call occurs.

Negative proof requires denial for:

- LIST and GET against a fifth bucket;
- `PutObject` and overwrite/upsert;
- multipart upload initiation, parts, and completion;
- `DeleteObject` and bulk delete;
- copy destination and move;
- bucket create, update, and delete;
- an operator token attempting backup scope;
- the backup token attempting unrelated application authority.

A transport error, missing test fixture, or unexecuted request is not denial evidence. Each negative test must prove that the authenticated request reached the authorization boundary and was denied, with no resulting mutation.

## 8. Synthetic Object Plan

No customer object may be used. Before activation testing, an already authorized operator creates a small deterministic local payload, records its SHA-256, and uploads one uniquely named copy to each target bucket through an existing approved path. The backup identity itself never uploads test data.

After policy activation, the backup route lists, downloads, and checksum-verifies only those objects. An existing authorized operator removes them after evidence capture. Creation, reads, checksums, and cleanup are recorded without object bytes, credentials, or tokens.

## 9. Rollback And Emergency Disable

The rollback candidate drops only `lws_storage_backup_reader_select_v1` from `storage.objects`. It does not alter existing policies, tables, schemas, functions, roles, buckets, or objects.

Rollback triggers include any unexpected inherited authority, wrong-identity success, fifth-bucket access, successful mutation, verifier failure, secret exposure, refresh ambiguity, or unexplained policy drift. Stop the backup process first, revoke the dedicated session or disable the identity, apply the exact rollback through the approved path, and verify the policy is absent. Account/session removal and synthetic-object cleanup are separate reviewed actions.

Because an access JWT can remain valid until expiry after sign-out, emergency handling must not assume that refresh-token revocation instantly invalidates an already issued JWT.

## 10. Static Verifier

Run:

```powershell
node scripts/security/storage-backup-s3-minimum-authority/verify-storage-backup-s3-minimum-authority.mjs
```

For the inert design artifact, the required result is:

```text
structureValid true
activationReady false
verdict NO-GO
```

A future activation check must also supply evidence for the exact UUID, collision exclusion, complete policy inventory, inherited authority, session lifecycle, and positive/negative tests. The design marker itself intentionally prevents an activation-ready verdict.

## 11. Evidence Package

A production approval package must contain sanitized records of:

- dedicated identity creation and exact UUID verification;
- identity-collision and unrelated-authority exclusion;
- complete policy and role inventory captured immediately before activation;
- materialized policy and exact rollback hashes;
- static verifier and independent review results;
- policy deployment and readback;
- session bootstrap, refresh, rotation, restart, revocation, and redaction tests;
- positive LIST, GET, pagination, and SHA-256 results;
- every negative authorization result and post-test no-mutation proof;
- synthetic object creation and cleanup;
- final staging, regression, deployment, and operator sign-off state.

No evidence artifact may contain a password, access JWT, refresh token, cookie, Authorization header, service key, S3 key, database URL, or object content.

## 12. Open Obligations

These obligations remain open and may not be collapsed into the local design result:

| Obligation | Status |
| --- | --- |
| dedicated Auth user exists | `MISSING` |
| exact production Auth UUID | `MISSING` |
| application/operator identity collision excluded | `NOT_PROVEN` |
| current ACL, membership, role-attribute, ownership and RLS inventory | `PROVEN_AT_2026-09-05_OBSERVATION` |
| complete current production policy inventory | `PROVEN_AT_2026-09-05_OBSERVATION` |
| inherited SELECT outcome for future UUID under owner policy | `NOT_PROVEN_IDENTITY_MAPPING` |
| inherited INSERT/UPDATE/DELETE absence at activation | `NOT_PROVEN` |
| materialized UUID-bound activation SQL | `MISSING` |
| protected bootstrap and session secret store | `OPEN` |
| serialized refresh and atomic rotation | `OPEN` |
| restart, expiry, revocation, and rate-limit proof | `OPEN` |
| positive LIST/GET/checksum evidence | `OPEN` |
| complete negative operation evidence | `OPEN` |
| encrypted local Storage backup | `MISSING` |
| offsite Storage backup | `MISSING` |
| restore proof | `NOT_PROVEN` |
| production activation | `NO-GO` |

## 13. Official Sources

Accessed on `2026-09-05`:

- <https://supabase.com/docs/guides/storage/s3/authentication>
- <https://supabase.com/docs/guides/storage/s3/compatibility>
- <https://supabase.com/docs/guides/storage/security/access-control>
- <https://supabase.com/docs/guides/storage/schema/helper-functions>
- <https://supabase.com/docs/guides/auth/sessions>
- <https://supabase.com/docs/guides/auth/rate-limits>
- <https://supabase.com/docs/reference/javascript/auth-refreshsession>

## 14. End State

```text
P0_6E6B_MODEL_A_PRESERVED ja
DEDICATED_IDENTITY_CONTRACT_DEFINED ja
EXACT_AUTH_UID_BINDING_REQUIRED ja
EXACT_FOUR_BUCKETS_REQUIRED ja
LIST_OBJECTS_V2_ALLOWED ja
GET_OBJECT_ALLOWED ja
LIST_BUCKETS_ALLOWED nee
STORAGE_BUCKETS_SELECT_REQUIRED nee
STORAGE_OBJECTS_SELECT_REQUIRED ja
STORAGE_WRITE_POLICY_CREATED nee
SERVICE_ROLE_ROUTE_ALLOWED nee
S3_ACCESS_KEY_ROUTE_ALLOWED nee

CURRENT_OWNER_POLICY_OR_COMPOSITION_MODELED ja
CURRENT_INHERITED_SELECT SAFE_NIET_BEWEZEN
CURRENT_INHERITED_WRITES SAFE_NIET_BEWEZEN_AT_ACTIVATION_TIME

SESSION_LIFECYCLE_DEFINED ja
FAIL_CLOSED_ZERO_STORAGE_CALLS ja
STATIC_VERIFIER_PRESENT ja
INERT_SQL_CANDIDATE_PRESENT ja
EXACT_ROLLBACK_PRESENT ja
INDEPENDENT_REVIEW_BLOCKING_HIGH none
INDEPENDENT_REVIEW_MEDIUM none_after_fix

CURRENT_PROJECT_FEASIBILITY UNPROVEN
PRODUCTION_ACTIVATION_READY nee
PRODUCTION_ACTIVATION NO-GO

PRODUCTION_CONTENT_READ_EXECUTED nee
PRODUCTION_SQL_EXECUTED nee
REMOTE_AUTH_USER_CREATED nee
REMOTE_POLICY_MUTATION none
REAL_SECRET_CREATED nee
PRODUCTION_STORAGE_WRITE none
PRODUCTION_STORAGE_DOWNLOAD none
PRODUCTION_BACKUP_CREATED nee

REGRESSION_PASS ja
ASSERTIONS_EXECUTED 423/423
TESTS_DISCOVERED 424
TESTS_SKIPPED 1_HISTORICAL_OPT_IN_LOCAL_POSTGRESQL
STAGING_EMPTY ja
FROZEN_HISTORICAL_HASHES_UNCHANGED ja

PUSH none
DEPLOY none
```
