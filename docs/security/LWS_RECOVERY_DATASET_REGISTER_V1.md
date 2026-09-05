# LWS Recovery Dataset Register V1

Status: `DRAFT FOR OWNER REVIEW`

Baseline date: `2026-09-05`

This register classifies evidence observed during the P0-6 read-only audit. Evidence statuses are limited to `PROVEN`, `PARTIAL`, `UNKNOWN` and `MISSING`. Targets are policy objectives and must not be read as current capabilities.

## Status Definitions

- `PROVEN`: directly supported by current repository or provider evidence.
- `PARTIAL`: part of the requirement is proven, but material recovery coverage or validation is absent.
- `UNKNOWN`: the audit could not establish the state.
- `MISSING`: evidence establishes that the capability is absent, or no required mechanism exists.

## Recovery Register

| Dataset | Authoritative source | Classification | Current backup | Current retention | Restore mechanism | Restore tested | Independent/offsite | Current RPO | Current RTO | Target RPO | Target RTO | Confidentiality | Integrity requirement | Priority | Current gap |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Customer/commercial requests | PostgreSQL: quote requests, intakes, customer requests and associated authority records | DB | `PROVEN` | `PARTIAL`: physical backup 7 days; business retention varies | `PARTIAL`: whole-project physical restore | `MISSING` | `MISSING` | `PARTIAL`: approximately <=24h | `UNKNOWN` | <=2 min | <=4h | Confidential customer/business | Exact relational graph, lifecycle, references and immutable evidence | P1 | No PITR, independent copy, granular procedure or restore test |
| Website dossiers | PostgreSQL: commercial projects, quotations, acceptances, lifecycle and assignment authorities | DB | `PROVEN` | `PARTIAL`: physical backup 7 days; lifecycle retention exists only for selected flows | `PARTIAL`: whole-project physical restore | `MISSING` | `MISSING` | `PARTIAL`: approximately <=24h | `UNKNOWN` | <=2 min | <=4h | Confidential customer/commercial | Referential integrity, accepted commercial state, lifecycle revision and event chain | P1 | No tested point/object restore and no independent backup |
| SDF dossiers | PostgreSQL: SDF intake, quotation, billing, project and lifecycle authorities | DB | `PROVEN` | `PARTIAL`: physical backup 7 days; no complete recovery retention authority | `PARTIAL`: whole-project physical restore | `MISSING` | `MISSING` | `PARTIAL`: approximately <=24h | `UNKNOWN` | <=2 min | <=4h | Highly confidential customer/workflow | Complete cross-table authority chain, hashes, status and billing coherence | P1 | No PITR, isolated restore test or complete object-aware recovery |
| Dossier documents | PostgreSQL manifests plus Storage objects in applicable private buckets | DB + Storage | `PARTIAL`: metadata covered, bytes not covered | `PARTIAL`: database backup 7 days; object retention not proven | `MISSING`: database restore cannot restore deleted object bytes | `MISSING` | `MISSING` | `MISSING`: object-byte RPO unbounded | `UNKNOWN` | DB <=2 min; Storage <=1h | <=8h | Highly confidential customer documents | Manifest completeness, exact object path, byte count and checksum | P1 | No Storage backup, version recovery or object restore procedure |
| Finance records | PostgreSQL: projects, invoices, payment evidence and business expenses; supplier documents in Storage | DB + Storage | `PARTIAL`: DB proven, document bytes missing | `PARTIAL`: database backup 7 days; financial/document retention authority incomplete | `PARTIAL`: DB restore only | `MISSING` | `MISSING` | `PARTIAL`: DB <=24h; object bytes unbounded | `UNKNOWN` | DB <=2 min; Storage <=1h | <=4h core; <=8h documents | Highly confidential financial | Amount, currency, VAT, issuance/payment chain and document checksum must reconcile | P1 | Storage gap can make restored financial records incomplete |
| Document Inbox | PostgreSQL inbox items, extraction/proposal/confirmation events and linked Storage objects | DB + Storage | `PARTIAL`: DB proven, source bytes missing | `PARTIAL`: database backup 7 days; object retention not proven | `PARTIAL`: DB restore only | `MISSING` | `MISSING` | `PARTIAL`: DB <=24h; object bytes unbounded | `UNKNOWN` | DB <=2 min; Storage <=1h | <=4h core; <=8h documents | Highly confidential financial/customer | Original bytes, extraction evidence, human confirmation and processing events must bind | P1 | A restored row may reference an unrecoverable source document |
| Recruitment | PostgreSQL applications/tests plus CV objects in `recruitment-cvs` | DB + Storage | `PARTIAL`: DB proven, CV bytes missing | `PARTIAL`: database backup 7 days; HR/privacy retention not fully established | `PARTIAL`: DB restore only | `MISSING` | `MISSING` | `PARTIAL`: DB <=24h; CV bytes unbounded | `UNKNOWN` | DB <=2 min; Storage <=1h | <=8h | Restricted personal data | Candidate identity, consent/context, immutable test assignment and CV checksum | P2 `REVIEW REQUIRED` | One current CV object has no demonstrated backup or restore path |
| Workforce/HR | PostgreSQL: employees, calendar entries, leave requests and events | DB | `PROVEN` | `PARTIAL`: physical backup 7 days; HR/legal retention authority not complete | `PARTIAL`: whole-project physical restore | `MISSING` | `MISSING` | `PARTIAL`: approximately <=24h | `UNKNOWN` | <=2 min | <=8h | Restricted employment data | Identity, employment status, calendar and leave event consistency | P2 `REVIEW REQUIRED` | No tested restore, independent copy or finalized retention authority |
| Operator identities/roles | Supabase Auth plus PostgreSQL operator profiles, operator authorities and UUID bindings | Auth + DB + config | `PROVEN`: database state only | `PARTIAL`: physical backup 7 days; identity/session policy incomplete | `PARTIAL`: DB restore followed by mandatory reconciliation | `MISSING` | `MISSING` | `PARTIAL`: approximately <=24h | `UNKNOWN` | <=2 min | <=4h | Restricted identity/security | Exact Auth UUID binding, role/status, MFA/AAL and revocation state | P0 | MFA/signing/session reconciliation and lockout recovery are untested |
| Audit/security events | PostgreSQL audit/event tables; local-only P0-3A-E security authorities | DB + code | `PARTIAL`: production DB backed up; local security commits are not remote | `PARTIAL`: database backup 7 days; complete audit retention authority unknown | `PARTIAL`: DB restore plus local git source | `MISSING` | `MISSING` | `PARTIAL`: production DB <=24h; local-only code loss possible | `UNKNOWN` | <=2 min | <=4h | Restricted security evidence | Append-only ordering, actor, action, object fingerprint and chain completeness | P0 for trust evidence; otherwise P3 `REVIEW REQUIRED` | Local machine is the only proven custody for P0-3A-E commits |
| Storage documents | Supabase Storage: `customer-request-quarantine`, `recruitment-cvs`, `supplier-documents`, `quotation-artifacts` | Storage | `MISSING` | `UNKNOWN` | `MISSING` | `MISSING` | `MISSING` | `MISSING`: unbounded | `MISSING` | <=1h | <=8h | Highly confidential mixed documents | Complete object manifest, immutable checksum, byte count, MIME and recoverable version | P1/P2 `REVIEW REQUIRED` | Database backups explicitly exclude object bytes |
| Migrations/configuration | Git repository, migration files, Edge source, lockfiles, Pages workflow and manually managed platform configuration | Code + config | `PARTIAL` | `UNKNOWN` | `PARTIAL`: git reconstruction covers tracked source only | `MISSING` | `PARTIAL`: GitHub plus local clone, but no independent archive is proven | `UNKNOWN` | `UNKNOWN` | <=24h after each approved change | <=4h | Internal security-sensitive | Commit identity, dependency locks, migration ledger and approved configuration inventory | P0 | P0-3A-E are local-only; Edge/Auth/secrets/platform settings are not fully codified |

## Storage Inventory

| Bucket | Business content | Current backup | Versioning/soft delete | Independent copy | Restore procedure |
| --- | --- | --- | --- | --- | --- |
| `customer-request-quarantine` | Customer-provided PDF, PNG and JPEG uploads | `MISSING` | `MISSING` | `MISSING` | `MISSING` |
| `recruitment-cvs` | Candidate CV files in PDF, DOC and DOCX | `MISSING` | `MISSING` | `MISSING` | `MISSING` |
| `supplier-documents` | Invoices, credit notes, receipts, contracts and other supplier evidence | `MISSING` | `MISSING` | `MISSING` | `MISSING` |
| `quotation-artifacts` | Issued quotation DOCX and PDF artifacts | `MISSING` | `MISSING` | `MISSING` | `MISSING` |

Database rows recording a bucket, path, checksum or deletion status are `PARTIAL` integrity evidence only. They do not improve the backup classification of the object bytes.

## Register Review Rules

- Review this register after every approved recovery architecture change, restore test, new business dataset or new Storage bucket.
- Promote a status only when evidence is linked and independently reviewable.
- A provider feature shown as available but not enabled remains `MISSING`.
- An undocumented historical action remains `UNKNOWN`; it cannot be treated as a test.
- Priority uncertainties remain `REVIEW REQUIRED` until the OWNER confirms business and legal impact.
