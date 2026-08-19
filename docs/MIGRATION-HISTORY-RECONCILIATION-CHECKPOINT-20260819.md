# Migration History Reconciliation Checkpoint - 2026-08-19

## Reason

Production migration history contained three applied versions that were absent from the repository. Their absence blocked a safe dry-run for the approved recurring-services migration `20260819120000`.

These files restore local migration-ledger parity only. They do not claim historical Git provenance.

> Reconstructed from verified production/deployment evidence; not historical Git-authoritative source.

## Reconstructed versions

### 20260817200645 - enable_rls_on_commercial_authority_tables

- Source: exact statement stored in the production `supabase_migrations` ledger.
- Historical Git provenance: none found after refs, tags, reflogs, unreachable objects, worktrees and GitHub history were searched.
- Production-ledger statement SHA-256: `fe8284ccfa2f0a9b6243d40657f693caf6e53647286bf9a71df92819c18eeb7a`.
- Reconstructed working-file SHA-256: `73c91b083c8c4bb92507de0df53053fd42f564e61b552030d446aa9915d6a46a`.
- The differing file hash is solely CRLF checkout representation; LF-normalized statement bytes are exactly 1,290 bytes and match the production-ledger statement SHA-256.

### 20260817201755 - harden_quote_requests_updated_at_search_path

- Source: exact statement stored in the production `supabase_migrations` ledger.
- Historical Git provenance: none found.
- Statement and reconstructed file SHA-256: `fa5df156ad9f5a3f6e2ff8d13b0da2a836f7df13a8e44b0df4a4574df05c3a6f`.

### 20260818044749 - align_full_v5_pricing_validation

- Source: verified loose deployed source in the existing Slimme Documentenflow worktree.
- Source path: `supabase/migrations/20260818044749_align_full_v5_pricing_validation.sql`.
- Historical Git provenance: none; the source remained untracked.
- Session evidence records its creation, focused `99/99` validation, isolated deployment and post-deployment verification.
- Production ledger contains five statements. Each statement occurs byte-equivalently and in the same order in the loose source; only statement separators and whitespace exist outside them.
- Source and reconstructed file SHA-256: `a22e1b834a7d921bf3001d6a14274a544c06e033825185e3fc16263cc979686c`.

## Preserved pending remediation

The approved recurring-services migration remains a separate ancestor commit artifact:

- Version: `20260819120000`
- File: `supabase/migrations/20260819120000_persist_snapshot_v3_recurring_services.sql`
- SHA-256: `c8cabab50dbf1f39be89c4a30e7d1c85cbf7ea2c6482a0d1a97409d56d8cc0f4`

No production database mutation, migration repair, database pull, database push or production deployment was performed during this reconciliation.

## Recurring Snapshot V3 compatibility remediation

A clean local rebuild initially failed when `20260819120000` followed the exact reconstructed `20260818044749` migration. The recurring-services migration expected older strict-V3 allowlist fragments, while `20260818044749` had already installed the direct `2.0.0` / `2026-08-16-v3` function definition.

The stale three-fragment rewrite was replaced by an exact fail-closed SHA-256 precondition over `pg_get_functiondef(public.is_strict_pricing_snapshot_v3(...))`. The only accepted predecessor fingerprint is:

`7f24bf90b5ed7617b8fd0a425af82768e9570f60e69b831f9ee78038d24fe8c0`

That predecessor already contains the approved active package, extra-page and Budget Guard semantics, so no function rewrite is needed. Any definition change, including a one-byte behavioral tamper, fails with `STRICT_V3_APPROVED_PREDECESSOR_NOT_FOUND`.

- Previous `20260819120000` SHA-256: `c8cabab50dbf1f39be89c4a30e7d1c85cbf7ea2c6482a0d1a97409d56d8cc0f4`
- Remediated `20260819120000` SHA-256: `27e611a4b53bf7846f8e07a54f61270411899e74988721cd3904f5dbd39e5e20`
- Clean local database reset: PASS
- Focused predecessor and recurring persistence tests: 26/26 PASS
- Complete pgTAP suite: 893/893 PASS
- Complete Deno intake/pricing suite: 221/221 PASS
- Database error-level lint: 0
- Diagnostics: 0
- `git diff --check`: PASS