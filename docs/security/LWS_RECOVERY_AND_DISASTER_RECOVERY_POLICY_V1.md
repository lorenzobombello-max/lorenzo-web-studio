# LWS Recovery and Disaster Recovery Policy V1

Status: `DRAFT FOR OWNER REVIEW`

Baseline date: `2026-09-05`

This document records recovery policy only. It does not activate backups or PITR, perform a restore, change Supabase or Storage configuration, deploy code, publish security work, or authorize physical purge.

## 1. Scope

This policy covers:

- the production PostgreSQL database, including customer and business data;
- Supabase Storage buckets and their stored document bytes;
- Supabase Auth identities, MFA factors, operator identity bindings and roles;
- Edge Functions, shared runtime code and dependency locks;
- secrets and manually managed platform configuration, without recording secret values;
- GitHub Pages source, build verification and deployment configuration;
- audit and security events;
- migrations and other configuration required to reconstruct service behavior.

## 2. Recovery Principles

1. A backup is valid only when an authorized restore can be demonstrated and its integrity and business usability can be verified.
2. A database backup is not a Storage backup. Database backup coverage of Storage metadata does not imply recovery of object bytes.
3. Metadata, fingerprints, checksums and tombstones are evidence about data; none is itself a backup or restore source.
4. A copy controlled only through the primary provider or primary administrative account is not independent recovery.
5. Irreversible purge requires current, server-verified, object-bound evidence that all required database records and Storage objects are recoverable.
6. A tombstone, audit event or application soft-delete state is never accepted as a restore source.
7. `UNKNOWN`, `MISSING`, expired, stale, incomplete or unverifiable evidence fails closed.
8. Recovery evidence must not contain passwords, tokens, signing material, API keys, customer document contents or other secrets.
9. Recovery procedures must preserve least privilege, dual control and AAL2 requirements. An emergency is not authority to bypass security controls.
10. Production recovery and destructive-action wiring require separate OWNER approval.

## 3. Current Proven State

| Capability | Current status | Evidence boundary |
| --- | --- | --- |
| Automated database backup | `PROVEN` | Supabase lists daily physical restore points. |
| Database backup retention | `PROVEN: 7 days` | Pro-plan policy; eight dated restore points currently span approximately seven days. |
| Latest available database restore point | `PROVEN: 2026-09-05 05:28:57 UTC` | Displayed as a physical backup with a Restore action. No restore was initiated. |
| PITR | `MISSING` | Dashboard offers PITR as an add-on; it is not enabled. |
| Database restore procedure | `PARTIAL` | Provider restore control and general procedure exist; no LWS-specific recovery runbook had been tested. |
| Database restore test | `MISSING` | No completed LWS restore-test evidence was found. Whether any undocumented historical test occurred remains `UNKNOWN`. |
| Storage backup | `MISSING` | Database backup explicitly excludes Storage object bytes. No separate backup was found. |
| Storage versioning or byte-level soft delete | `MISSING` | No configured capability or recovery evidence was found. Application lifecycle metadata is not object recovery. |
| Independent/offsite backup | `MISSING` | No independently controlled provider/account copy was found. |
| Configuration recovery | `PARTIAL` | Source, migrations and Pages workflow are versioned; platform settings and secret values are not fully reproducible from git. |
| Auth recovery | `PARTIAL` | Auth database state is within the physical database boundary, but MFA, signing/config and lockout reconciliation are untested. |
| Current database RPO | `PARTIAL: approximately <= 24 hours` | Daily backups only; no PITR. |
| Current Storage and total-system RPO | `MISSING: unbounded` | No object-byte backup exists. |
| Current RTO | `UNKNOWN` | No isolated timed restore test exists. |
| Authoritative object backup evidence | `MISSING` | P0-3D deliberately returns `BACKUP_EVIDENCE_UNAVAILABLE`. |

The four known private business buckets are `customer-request-quarantine`, `recruitment-cvs`, `supplier-documents` and `quotation-artifacts`. Their presence, object metadata and checksums do not change the `MISSING` Storage-backup classification.

## 4. Target State

These are recovery objectives, not current capabilities:

| Objective | Target |
| --- | --- |
| Database RPO | `<= 2 minutes` |
| Storage RPO | `<= 1 hour` |
| Critical-service RTO | `<= 4 hours` |
| Full document restore RTO | `<= 8 hours` |

Targets are met only after implementation and a successful, timed, isolated restore test. Enabling a feature or creating a copy without restore validation is insufficient.

## 5. Recovery Priority Matrix

| Priority | Recovery scope | Business impact | Classification |
| --- | --- | --- | --- |
| `P0` | Auth/operator access, security controls, production database core authority | Required to establish trusted control and prevent unauthorized or inconsistent recovery. | `PROVEN PRIORITY` |
| `P1` | Active customer requests and website dossiers, SDF, finance, Document Inbox | Active delivery, customer obligations and financial operations cannot be trusted without these datasets. | `PROVEN PRIORITY` |
| `P2` | Recruitment, workforce/HR, quotations and artifact bytes | Material privacy, employment and commercial impact; exact sequencing against P1 depends on the incident. | `REVIEW REQUIRED` |
| `P3` | Historical, audit and archive data where legally and operationally appropriate | Usually follows active operations, but security/audit evidence needed to establish trust is promoted to P0. | `REVIEW REQUIRED` |

Audit/security evidence is not uniformly P3: records required to prove authority, integrity or incident scope are P0. Legal retention and active disputes may also promote historical records. The incident commander must document every priority override.

## 6. Recovery Governance

- The OWNER declares a recovery incident and appoints an incident commander and independent verifier.
- Recovery source selection, execution and verification are separate responsibilities where practicable.
- Recovery uses the dataset register and `LWS_RECOVERY_RUNBOOK_V1.md`.
- No destructive action is reopened until restored identities, security controls, relational integrity and required Storage objects are validated.
- Evidence is retained according to approved legal, contractual and operational retention. No retention duration may be invented when its authority is `UNKNOWN`.
- Recovery records use UTC and identify the source, restore point, responsible actors, validation results and exceptions without embedding secrets or customer content.

## 7. P0-6 Implementation Roadmap

| Phase | Objective | Dependencies | Production impact | Required tests | Rollback boundary | OWNER approval |
| --- | --- | --- | --- | --- | --- | --- |
| `P0-6B` | Independent encrypted database backup with offsite retention. | Approved policy, data classification, retention authority, encryption/key-custody design. | Backup reads and new external storage only after approval; no restore or purge wiring. | Backup completion, encryption, manifest/checksum, access denial and isolated restore rehearsal. | Disable new backup jobs without deleting valid retained copies or evidence. | `ja` |
| `P0-6C` | Storage backup/versioning, checksum manifests and provider/account separation. | Bucket inventory, object lifecycle rules, independent destination and key custody. | Read/copy production objects only after approval; no source mutation. | Incremental capture, deletion/version recovery, checksum mismatch, missing-object and isolated restore tests. | Stop replication while preserving source objects, independent copies and append-only evidence. | `ja` |
| `P0-6D` | Auth/MFA/signing, Edge secrets and platform configuration recovery. | Configuration inventory, custody model, break-glass roles and rotation policy. | No active setting or secret change until separately approved. | Configuration reconstruction, identity reconciliation, lockout, signing continuity and secret-rotation rehearsal. | Revert only the tested configuration change; never restore obsolete secrets blindly. | `ja` |
| `P0-6E` | Isolated full restore test and technical/business validation. | B/C/D complete, isolated target, approved sanitized validation data and runbook. | None to production; production remains read-only during evidence collection. | Timed database, Storage, Auth, function/config, integrity and business acceptance tests against RPO/RTO. | Destroy the isolated recovery environment after evidence retention; production remains untouched. | `ja` |
| `P0-6F` | Server-side authoritative object backup evidence registry and verifier, initially shadow mode. | Successful E evidence and approved evidence contract. | New local/migration work first; any remote migration or shadow deployment needs separate approval. | Immutability, actor authority, object binding, freshness, manifest completeness, checksum, independence, expiry and restore-test gates. | Disable verifier evaluation without weakening the existing fail-closed purge result. | `ja` |
| `P0-6G` | Separately approved wiring from verified evidence to the P0-3D purge gate. | F proven in shadow mode, reviewed operational runbook, monitored rollback plan. | High-risk production security change; purge remains disabled until explicit release approval. | End-to-end dual-control, AAL2, retention, backup evidence, replay, stale evidence and fail-closed tests. | Kill switch and forward-only corrective release; no bypass to legacy purge paths. | `ja` |

## 8. Local-Only Security Commit Risk

P0-3A through P0-3E currently exist on no remote branch. Their commits are recoverable only from the current local repository/worktree and therefore form a recovery single point of failure.

- Do not push these commits as part of P0-6A.
- Do not create a remote branch without a separate OWNER decision.
- Review repository visibility, access control, confidentiality, branch protection and acceptable remote custody before any remote preservation.
- Do not publish security code merely to remove this risk; preservation requires its own approved handling decision.

## 9. Current Decision

- `P0-6A_OWNER_REVIEW: GO`
- `P0-6_IMPLEMENTATION: NOT YET EXECUTED`
- `P0-3D_PURGE_UNBLOCK: NO-GO`
- `PRODUCTION_WIRING: NO-GO`
- `LEGACY_KEY_SOAK_IMPACT: NONE`