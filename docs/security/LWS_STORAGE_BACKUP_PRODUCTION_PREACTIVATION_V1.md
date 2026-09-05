# LWS Storage Backup Production Pre-Activation V1

Status: `GO - READ-ONLY PREACTIVATION COMPLETE; PRODUCTION ACTIVATION NO-GO`

Recovery classification: `B - PARTIAL_LOCAL_WORK_RECOVERABLE`

## 1. Scope And Recovery Continuity

P0-6E.6C is the read-only preactivation continuation of the fixed P0-6E.6B MODEL A design. An unexpected computer shutdown occurred after the live reads and local evaluator work, but before the evidence record and dossier were completed.

The recovery inspection found no zero-byte files, conflict markers, syntax damage or TODO/WIP recovery markers. The recovered evaluator and focused tests were executable. No implementation was reconstructed from assumptions.

This phase authorizes no production mutation, Auth-user creation, policy application, secret creation, Storage operation, commit, push or deployment.

## 2. Evidence Classes

### RECOVERED_TRANSCRIPT_EVIDENCE

The preserved session transcript proves:

- production project `xcsptvntvrizwhskaphr`, branch `main`, label `Production` was verified before the catalog read;
- one fixed read-only `pg_catalog.pg_policies` statement was executed;
- the complete fixed query result contained exactly one row and was below the 100-row display limit;
- the row was permissive authenticated `SELECT` policy `recruitment_cvs_owner_read_v1` on `storage.objects`;
- no `storage.buckets` policy and no `INSERT`, `UPDATE`, `DELETE` or `ALL` policy was present;
- target policy `lws_storage_backup_reader_select_v1` was absent;
- the Auth users view was read completely (`Total: 6 users`) and contained no exact intended identity-name match;
- no Auth user, policy, secret or Storage operation was created or executed.

The recovered facts are stored locally in ignored file `scripts/security/storage-backup-production-preactivation/evidence.local.json`. It contains no email address, Auth UUID, credential, token or other personal data.

### NEW_LOCAL_INTEGRATION

After recovery, local work only:

- bound transcript provenance to trusted artifact ID `p0-6e.6c-recovered-transcript-20260905`, exact artifact type/version/source reference and SHA-256 `f5eec339137e0b9b799c13cf7fa1d5704dbe7b6eface03fa93f38f4d564ffe0f`;
- added deterministic canonical JSON serialization with sorted object keys and SHA-256 over every artifact field except the digest field itself;
- restricted caller input to the exact artifact ID and digest reference; caller-supplied recovery labels, booleans or overrides are rejected;
- made missing, malformed, stale, ambiguous, modified or hash-mismatched recovered evidence fail closed;
- integrated the one-policy inventory with permissive OR semantics;
- separated proven write isolation from identity-dependent read authority;
- preserved the inert candidate and activation `NO-GO` contract;
- documented and tested the integrated decision.

At that recovery-integration point, no live read was repeated. A later, separately scoped authority closure used the official Management API read-only query endpoint as described below.

### READ_ONLY_AUTHORITY_CLOSURE

On `2026-09-05`, the official `POST /v1/projects/{ref}/database/query/read-only` route was validated before the catalog inventory. The probe returned HTTP `201`, `current_user = supabase_read_only_user`, `session_user = supabase_read_only_user`, and `transaction_read_only = on`. The route requires `database:read` / `database_read` and is distinct from the CLI login-role endpoint. No login role or other database object was created.

One fixed, schema-qualified catalog query then returned the complete role, membership, `storage` schema ACL, `storage.objects` table and column ACL, relation owner/RLS flags, and policy inventory. The sanitized result is retained in `scripts/security/storage-inventory-production-preactivation/evidence.local.json`; it contains no bearer, cookie, password, connection string, Auth UUID, email address, or object data.

The ignored artifact is the sole source of recovered facts. The evaluator reads no project, inventory, collision, schema, MODEL A, Auth-state or production-safety claim from caller input. Artifact integrity must pass before any recovered fact is evaluated. Changing one fact changes the canonical digest and makes the artifact `NO-GO` until a separately reviewed tracked trust anchor is updated.

## 3. Production Project And Inventory

| Decision input | Result |
| --- | --- |
| Production project reference | `VERIFIED` |
| Live policy inventory read | `YES` |
| Inventory complete within fixed query scope | `YES` |
| Live policy rows | `1` |
| Target backup policy collision | `ABSENT` |
| Intended identity-name collision | `ABSENT_AT_OBSERVATION` |

The identity-name result does not prove the future Auth UUID cannot receive a commercial owner mapping. UUID and owner-mapping exclusion remain activation obligations.

## 4. Live Policy Interpretation

The only observed relevant policy was:

| Policy | Table | Mode | Role | Command | Classification |
| --- | --- | --- | --- | --- | --- |
| `recruitment_cvs_owner_read_v1` | `storage.objects` | permissive | `authenticated` | `SELECT` | `IDENTITY_DEPENDENT` |

Its predicate allows reads from bucket `recruitment-cvs` when `auth.uid()` maps to an active commercial operator with role `owner`.

PostgreSQL permissive policies OR-compose. Therefore this policy cannot be ignored when the future backup policy is added.

The authority closure proves:

- `authenticated` has direct schema `USAGE` and direct relation `SELECT`;
- `authenticated` has no parent-role membership, is not superuser, has no `BYPASSRLS`, and is not relation owner;
- `storage.objects` has RLS enabled and `FORCE RLS` disabled, so `authenticated` is governed by RLS;
- `service_role` has direct `SELECT` and `BYPASSRLS`;
- `supabase_storage_admin` owns `storage.objects`; because `FORCE RLS` is disabled, its owner bypass is active;
- no column-level ACL adds another SELECT path.

Therefore the database-role inheritance question for the future ordinary `authenticated` session is closed: `ROLE_INHERITED_SELECT_SAFE = ja`. The existing permissive policy remains an identity-dependent branch. Because the dedicated Auth identity and exact UUID do not exist yet, its future commercial-owner mapping cannot yet be evaluated:

- `INHERITED_SELECT_SAFE = unproven`;
- `CURRENT_ROLE_INHERITANCE_AUTHORITY_SAFE = ja`;
- `BACKUP_IDENTITY_COULD_INHERIT_RECRUITMENT_OWNER_READ = unproven`.

No optimistic upgrade of the future UUID-dependent policy result to `SAFE` or `nee` is made.

## 5. Write Isolation

The complete fixed-scope inventory contained no authenticated/public `INSERT`, `UPDATE`, `DELETE` or `ALL` policy. The evaluator therefore reports:

- `INHERITED_INSERT_SAFE = ja`;
- `INHERITED_UPDATE_SAFE = ja`;
- `INHERITED_DELETE_SAFE = ja`;
- `BACKUP_IDENTITY_WRITE_ISOLATION = ja`.

This proves write isolation only for the observed complete preactivation inventory. The policy inventory must be refreshed and re-evaluated immediately before activation.

## 6. Schema Compatibility

P0-6E.4 live schema evidence is reused without a new query. It proves `storage.objects.bucket_id` is `text` and the other observed Storage schema fields are compatible. The P0-6E.6B policy requires only `storage.objects`, `bucket_id`, object-name prefix semantics and `auth.uid()`.

`LIVE_SCHEMA_COMPATIBLE_WITH_6B_POLICY = ja`.

## 7. MODEL A Integration

MODEL A remains unchanged:

- exact known buckets: `customer-request-quarantine`, `quotation-artifacts`, `recruitment-cvs`, `supplier-documents`;
- no `ListBuckets`;
- no `storage.buckets SELECT`;
- `ListObjectsV2` through `storage.objects SELECT`;
- `GetObject` through `storage.objects SELECT`.

Official Supabase Storage S3 session-token behavior plus existing live schema evidence support these preconditions. No S3 request was executed.

`MODEL_A_LIVE_PRECONDITIONS_COMPATIBLE = ja`.

## 8. Evaluator Decision

The read-only gate first requires exact caller reference fields and a recovery artifact matching the tracked ID, SHA-256, type, version and source reference. Only then may it read the artifact facts and require verified project identity, complete inventory, no target-policy collision, compatible schema and MODEL A, absent intended identity-name collision, absent future Auth user and UUID, an inert candidate, no unsafe write axis, and SELECT authority that is either safe or explicitly identity-dependent.

The identity-dependent SELECT is allowed only for proposing the separately approved identity-creation phase. It remains an explicit blocker for policy activation until the exact UUID is known and owner-mapping collision is excluded.

- `PREACTIVATION_READONLY_GATE = GO`;
- `POLICY_CANDIDATE_ACTIVATABLE = nee`;
- `PRODUCTION_ACTIVATION_READY = nee`.

## 9. Candidate And Production Safety

- 6B candidate remains inert.
- Dedicated Auth user was not created.
- Auth UUID was not captured.
- Real secret was not created.
- Production policy mutation: none.
- Production Storage LIST/GET/write: none.
- Production backup: not created.
- Commit, push and deploy: none.

## 10. Open Obligations

- real dedicated backup identity creation: `OPEN`;
- exact Auth UUID capture: `OPEN`;
- exact UUID owner-mapping collision exclusion: `OPEN`;
- fresh complete policy inventory at activation: `OPEN`;
- fresh ACL, membership, role-attribute, ownership and RLS-flag inventory at activation: `OPEN`;
- production SELECT-only LIST+GET policy apply: `OPEN`;
- production policy verification: `OPEN`;
- runtime secret creation: `OPEN`;
- session/bootstrap configuration: `OPEN`;
- refresh lifecycle live proof: `OPEN`;
- synthetic test object preparation: `OPEN`;
- live S3 ListObjectsV2 allowed bucket: `OPEN`;
- live S3 GetObject test object: `OPEN`;
- live denied fifth-bucket LIST: `OPEN`;
- live denied fifth-bucket GET: `OPEN`;
- live denied PUT: `OPEN`;
- live denied overwrite: `OPEN`;
- live denied multipart: `OPEN`;
- live denied DELETE: `OPEN`;
- live denied COPY/MOVE: `OPEN`;
- checksum verification: `OPEN`;
- encrypted local Storage backup: `MISSING`;
- offsite Storage backup: `MISSING`;
- restore proof: `NOT PROVEN`;
- purge: `NO-GO`.

## 11. Verification

Focused P0-6E.6C: `46/46 PASS`.

The independent read-only review found zero BLOCKING and zero HIGH findings. Its timestamp-provenance MEDIUM was fixed test-first by requiring canonical UTC timestamps for both recovered observations. The remaining LOW notes are fail-closed policy-regex behavior and a live PostgreSQL guard test that is outside this read-only preactivation scope.

The renewed owner review after artifact/hash binding found zero BLOCKING, HIGH, MEDIUM or LOW findings. It verified the fixed trust anchor, canonical serialization, exact digest match, caller-override rejection, stale/ambiguous artifact rejection and unconditional activation `NO-GO` boundary.

The complete 14-file security regression produced:

- total: `470`;
- executed: `469`;
- passed: `469`;
- failed: `0`;
- skipped: `1`.

The single skip is the existing opt-in local PostgreSQL export/encrypt/restore/cleanup integration test. It is environment-dependent and unrelated to P0-6E.6C.

## 12. Exact Decision

```text
P0_6E6C_CRASH_RECOVERY_INTEGRATED ja
P0_6E6C_READONLY_PREACTIVATION_COMPLETE ja

PRODUCTION_PROJECT_REFERENCE_VERIFIED ja
LIVE_POLICY_INVENTORY_READ ja
POLICY_INVENTORY_COMPLETE ja
LIVE_POLICY_ROWS 1

BACKUP_POLICY_NAME_COLLISION_CLEAR ja

LIVE_SCHEMA_COMPATIBLE_WITH_6B_POLICY ja
MODEL_A_LIVE_PRECONDITIONS_COMPATIBLE ja

INHERITED_AUTHORITY_LIVE_AUDIT_COMPLETE ja
ROLE_INHERITED_SELECT_SAFE ja
EFFECTIVE_SELECT_AUTHORITY_AUTHENTICATED DIRECT_SELECT_RLS_ENFORCED
EFFECTIVE_SELECT_AUTHORITY_SERVICE_ROLE DIRECT_SELECT_BYPASSRLS
EFFECTIVE_SELECT_AUTHORITY_SUPABASE_STORAGE_ADMIN OWNER_SELECT_OWNER_BYPASS
FORCE_RLS_STATUS DISABLED
OWNER_BYPASS_STATUS ACTIVE_FOR_SUPABASE_STORAGE_ADMIN
INHERITED_SELECT_SAFE unproven
INHERITED_INSERT_SAFE ja
INHERITED_UPDATE_SAFE ja
INHERITED_DELETE_SAFE ja

RECRUITMENT_OWNER_READ_FOR_FUTURE_BACKUP_UUID unproven
BACKUP_IDENTITY_COULD_INHERIT_RECRUITMENT_OWNER_READ unproven
BACKUP_IDENTITY_WRITE_ISOLATION ja

DEDICATED_BACKUP_IDENTITY_NAME_AVAILABLE ja

PRODUCTION_AUTH_USER_CREATED nee
AUTH_UUID_CAPTURED nee
REAL_SECRET_CREATED nee

POLICY_CANDIDATE_STILL_INERT ja
POLICY_CANDIDATE_ACTIVATABLE nee

PRODUCTION_POLICY_MUTATION none
PRODUCTION_STORAGE_LIST_EXECUTED nee
PRODUCTION_STORAGE_GET_EXECUTED nee
PRODUCTION_STORAGE_WRITE none
PRODUCTION_BACKUP_CREATED nee

PREACTIVATION_READONLY_GATE GO
PRODUCTION_ACTIVATION_READY nee

FOCUSED_ASSERTIONS 46/46

FULL_SECURITY_TESTS_TOTAL 470
FULL_SECURITY_TESTS_EXECUTED 469
FULL_SECURITY_TESTS_PASS 469
FULL_SECURITY_TESTS_FAIL 0
FULL_SECURITY_TESTS_SKIP 1

REGRESSION_PASS ja
STAGING_EMPTY ja
PREEXISTING_FILES_UNCHANGED ja
EVIDENCE_IGNORED ja
EVIDENCE_TRACKED nee

PUSH none
DEPLOY none

BLOCKER none_for_P0-6E.6C; production activation remains blocked by the open obligations

GO/NO-GO P0-6E.6C owner review: GO
```

`GO` means only that the crash-interrupted P0-6E.6C read-only preactivation phase is reconstructed, documented and verified. It does not authorize production activation.