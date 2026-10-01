# C3-R1 customer-function repair manifest - 2026-10-01

Status: **LOCAL REPAIR CANDIDATE; NO EXTERNAL MUTATION AUTHORIZED**.

This manifest records the bounded repair for the missing `commercial-customer-approval` Edge Function. Preparation performed no push, remote binding write, deploy, merge, remote migration, workflow run, fixture, trial or official-document/intake change.

## 1. Identity and preserved history

- Release worktree: `C:\Users\info\Project-Worktrees\lorenzo-web-studio-c3-r1-release-20261001`.
- Branch: `release/c3-r1-20261001`.
- Repair parent: `45084d86f0e0e1f6841488c128c521e3b7960b9e`.
- Pinned base: `b3980407c7e90d66c432d4dc6284398aeaa213ca`.
- Historical manifest: `docs/superpowers/release/2026-10-01-c3-r1-release-manifest.md`.
- Historical manifest Git blob: `80125ec484aa9ea8a93efd1e72fd0a365e597f80`; it remains byte-unchanged.
- Historical payload: 77 files, 46 migrations and 31 non-migrations, SHA-256 `70df0e9d309ba197fb20529f6f90f71b1e20ad75aced8bd6589f40a48fec5264`.
- Repaired payload: 81 files, 46 migrations and 35 non-migrations, SHA-256 `4c951b4f9e5dedfc766d904b3864ccc8c2f3448fd3e48f62f732bc8cabf39653`.

The repaired hash is over the 81 sorted lines `<prospective-git-blob><two spaces><relative-path><LF>`, using `git hash-object --path` so repository filters are applied. Both control manifests are excluded from the payload count and hash. The final local repair commit is recorded after commit creation in C3.17 and the operational handover because a commit cannot contain its own hash.

## 2. Exact repaired payload inventory

1. `.github/workflows/convert-website-delivery-pdf.yml`
2. `deno.lock`
3. `scripts/website-delivery-pdf/conversion-task-http-runner.ts`
4. `scripts/website-delivery-pdf/conversion-task-runner.ts`
5. `scripts/website-delivery-pdf/libreoffice-pdf-exporter.ts`
6. `scripts/website-delivery-pdf/libreoffice/Dockerfile`
7. `scripts/website-delivery-pdf/run-conversion-task.ts`
8. `supabase/config.toml`
9. `supabase/functions/_shared/github-app-config.ts`
10. `supabase/functions/_shared/github-app-token.ts`
11. `supabase/functions/_shared/website-delivery-pdf-oidc.ts`
12. `supabase/functions/_shared/website-delivery-pdf-session.ts`
13. `supabase/functions/_shared/website-delivery-pdf-transfer.ts`
14. `supabase/functions/_shared/website-delivery-pdf-validation.ts`
15. `supabase/functions/_shared/website-delivery-pdf-workflow-dispatch.ts`
16. `supabase/functions/_shared/website-delivery-pdf-workflow-starter.ts`
17. `supabase/functions/commercial-customer-approval/document-runtime.test.ts`
18. `supabase/functions/commercial-customer-approval/handler.test.ts`
19. `supabase/functions/commercial-customer-approval/handler.ts`
20. `supabase/functions/commercial-customer-approval/index.ts`
21. `supabase/functions/commercial-operator-command/assets/LWS_WEBSITE_AGREEMENT_NL_BE_CONCEPT_v1.docx`
22. `supabase/functions/commercial-operator-command/assets/LWS_WEBSITE_DELIVERY_DOCUMENT_OPL_W_01_v1.docx`
23. `supabase/functions/commercial-operator-command/assets/LWS_WEBSITE_DELIVERY_DOCUMENT_OPL_W_01_v2.docx`
24. `supabase/functions/commercial-operator-command/assets/LWS_WEBSITE_INVOICE_FINAL_REMAINDER_NONPRODUCTION_v1.docx`
25. `supabase/functions/commercial-operator-command/assets/LWS_WEBSITE_INVOICE_M1_40_NONPRODUCTION_v1.docx`
26. `supabase/functions/commercial-operator-command/assets/LWS_WEBSITE_INVOICE_M2_40_NONPRODUCTION_v1.docx`
27. `supabase/functions/commercial-operator-command/assets/LWS_WEBSITE_QUOTATION_NL_BE_OFFICIAL_v1.docx`
28. `supabase/functions/commercial-operator-command/handler.ts`
29. `supabase/functions/commercial-operator-command/index.ts`
30. `supabase/functions/commercial-operator-command/quotation-runtime.ts`
31. `supabase/functions/commercial-operator-command/website-commercial-renderer-edge.ts`
32. `supabase/functions/commercial-operator-command/website-delivery-renderer-edge.ts`
33. `supabase/functions/commercial-operator-command/website-quotation-renderer-edge.ts`
34. `supabase/functions/website-delivery-pdf-conversion/handler.ts`
35. `supabase/functions/website-delivery-pdf-conversion/index.ts`
36. `supabase/migrations/20260923130000_promote_official_website_quotation_template_v2.sql`
37. `supabase/migrations/20260926120000_add_website_commercial_document_concepts_v1.sql`
38. `supabase/migrations/20260927003000_add_website_agreement_registration_status_v1.sql`
39. `supabase/migrations/20260927005000_add_website_quotation_payment_term_release_gate_v1.sql`
40. `supabase/migrations/20260927006000_add_website_document_flow_operator_routes_v1.sql`
41. `supabase/migrations/20260927007000_add_website_preview_ready_from_build_v1.sql`
42. `supabase/migrations/20260928000000_add_commercial_customer_preview_session_v1.sql`
43. `supabase/migrations/20260928001000_add_commercial_customer_approval_gateway_v1.sql`
44. `supabase/migrations/20260928002000_harden_commercial_customer_approval_replay_v1.sql`
45. `supabase/migrations/20260928003000_add_website_delivery_document_package_1_v1.sql`
46. `supabase/migrations/20260928004000_require_website_delivery_legal_form_v1.sql`
47. `supabase/migrations/20260928005000_add_quotation_identity_legal_form_v1.sql`
48. `supabase/migrations/20260928006000_preserve_quotation_identity_v1_compatibility.sql`
49. `supabase/migrations/20260928007000_add_website_delivery_document_viewing_package_2_v1.sql`
50. `supabase/migrations/20260928008000_add_customer_delivery_document_view_resolution_v1.sql`
51. `supabase/migrations/20260928009000_add_operator_delivery_document_view_resolution_v1.sql`
52. `supabase/migrations/20260928010000_revalidate_current_delivery_document_receipts_v1.sql`
53. `supabase/migrations/20260928011000_bind_customer_acceptance_to_viewed_delivery_document_v1.sql`
54. `supabase/migrations/20260928012000_prepare_delivery_document_before_customer_acceptance_v1.sql`
55. `supabase/migrations/20260928013000_serialize_customer_acceptance_replay_v1.sql`
56. `supabase/migrations/20260928014000_freeze_delivery_document_registration_after_acceptance_v1.sql`
57. `supabase/migrations/20260929001000_add_website_delivery_pdf_conversion_tasks_v1.sql`
58. `supabase/migrations/20260929002000_add_website_delivery_pdf_conversion_execution_v1.sql`
59. `supabase/migrations/20260929003000_fix_website_delivery_pdf_claim_replay_result_v1.sql`
60. `supabase/migrations/20260929004000_add_website_delivery_pdf_conversion_recovery_v2.sql`
61. `supabase/migrations/20260929005000_serialize_website_delivery_pdf_completion_takeover_v2.sql`
62. `supabase/migrations/20260929006000_harden_website_delivery_pdf_completion_v3.sql`
63. `supabase/migrations/20260929007000_add_website_delivery_pdf_orphan_cleanup_v1.sql`
64. `supabase/migrations/20260929007500_repair_website_delivery_pdf_c1_review_v1.sql`
65. `supabase/migrations/20260929007600_reject_incomplete_pdf_cleanup_workflow_claims_v1.sql`
66. `supabase/migrations/20260929008000_add_website_delivery_pdf_dispatch_authority_v1.sql`
67. `supabase/migrations/20260929008100_converge_website_delivery_pdf_dispatch_authority_v1.sql`
68. `supabase/migrations/20261001001000_add_website_delivery_pdf_recovery_authority_v1.sql`
69. `supabase/migrations/20261001002000_distinguish_website_delivery_pdf_rerun_policy_v1.sql`
70. `supabase/migrations/20261001003000_remove_negative_readback_redispatch_authority_v1.sql`
71. `supabase/migrations/20261001004000_bind_accepted_website_delivery_pdf_run_v1.sql`
72. `supabase/migrations/20261001005000_stabilize_website_delivery_pdf_run_inspection_v1.sql`
73. `supabase/migrations/20261001006000_reconcile_website_delivery_pdf_recovery_v1.sql`
74. `supabase/migrations/20261001007000_close_website_delivery_pdf_recovery_visibility_v1.sql`
75. `supabase/migrations/20261001008000_serialize_website_delivery_pdf_recovery_cleanup_v1.sql`
76. `supabase/migrations/20261001009000_advance_website_delivery_pdf_recovery_provider_status_v1.sql`
77. `supabase/migrations/20261001010000_reject_incomplete_website_delivery_pdf_provider_completion_v1.sql`
78. `supabase/migrations/20261001011000_add_website_delivery_pdf_c3_trial_authority_v1.sql`
79. `supabase/migrations/20261001012000_repair_website_delivery_pdf_c3_trial_pricing_v1.sql`
80. `supabase/migrations/20261001013000_repair_website_delivery_pdf_c3_trial_identity_v1.sql`
81. `supabase/migrations/20261001014000_repair_website_delivery_pdf_c3_trial_issuance_v1.sql`

## 3. Bounded repair delta

Exactly four files were added from the source worktree, byte-identically:

| File | SHA-256 | Bytes |
|---|---|---:|
| `supabase/functions/commercial-customer-approval/index.ts` | `b9fac8241e317b2c2e3d2d1da8b0b3dc8436835511cea272cff238b99e909491` | 11154 |
| `supabase/functions/commercial-customer-approval/handler.ts` | `c332e45a91b31e861c530e92abc1962fe850d71e4d4e5c75831f9040e0a1fc17` | 20496 |
| `supabase/functions/commercial-customer-approval/handler.test.ts` | `fdd2175eb94af2aff039474ebd10ed53e1a8c6c2bf0402058b2db6aeca31d9f1` | 24544 |
| `supabase/functions/commercial-customer-approval/document-runtime.test.ts` | `8b39583bca11e2ad065427828d45984f78a457630b9f03b4884cd22d82ac718c` | 3711 |

The only existing payload file changed by this repair is `supabase/config.toml`, now SHA-256 `f0bce9db82c17ddaa35bd3e816dfd830265c05c34aff26d8e0a8a9872f42bd70`, with exactly one added entry:

```toml
[functions.commercial-customer-approval]
verify_jwt = false
```

No asset is imported by the customer function. Its only local runtime dependency, `supabase/functions/_shared/supabase-key-bindings.ts`, already exists in the pinned base. `deno.lock` already resolves `npm:@supabase/supabase-js@2` and `jsr:@std/assert@1`; it did not change in this repair. No script, migration, workflow, official document or intake file was added or changed.

## 4. Runtime chain and required binding

The release-local runtime chain is:

1. `POST /session` hashes the customer access token and new random session token, calls `redeem_customer_preview_access_v1`, and sets the host-only secure session cookie.
2. `GET /context` resolves the active approval context with `resolve_customer_approval_context_v1`.
3. `GET /document` calls `resolve_customer_website_delivery_document_view_v1`, downloads the registered private PDF, verifies exact byte length and SHA-256, and only then calls `register_website_delivery_document_access_receipt_v1` with `viewer_kind='CUSTOMER'` and the exact served hash/length.
4. `POST /approval` requires same-origin active confirmation, the viewed document version/hash and the session's current receipt, then calls `execute_customer_commercial_command_v1` with `command_type='submit_customer_approval'`.

Before any later deployment, Supabase must contain the additional function binding:

- `LWS_COMMERCIAL_CUSTOMER_APPROVAL_ORIGIN`: the exact approved HTTPS origin that serves the customer page, with no path. For the direct Supabase function URL this is `https://xcsptvntvrizwhskaphr.supabase.co`; a reviewed custom reverse-proxy origin must instead use that exact public origin.

The platform-provided `SUPABASE_URL` and the existing JSON `SUPABASE_SECRET_KEYS` binding with non-empty `default` `sb_secret_...` entry remain required. No value is stored in this manifest. The `__Host-` session cookie requires HTTPS outside local tests.

## 5. Local verification and limits

All commands were run with the release worktree explicitly selected.

- RED: after adding only the two tests, `deno test --frozen supabase/functions/commercial-customer-approval/` failed with exactly two `TS2307` errors for missing `index.ts` and `handler.ts`.
- GREEN: after adding the two runtime files, the same command passed `25/25` with zero failures.
- `deno check --node-modules-dir=auto --frozen supabase/functions/commercial-customer-approval/index.ts`: passed.
- Static/RPC chain control: 15 required route/RPC/binding checks and three ordering checks passed against only release-local runtime and eight selected migrations.
- Editor diagnostics for the function/config slice: none.
- Raw `deno lint` reports 28 inherited findings limited to `no-import-prefix` for established inline `npm:/jsr:` imports and `require-await` in async test doubles. The source files were deliberately preserved byte-identically. `deno lint --rules-exclude=no-import-prefix,require-await supabase/functions/commercial-customer-approval/` checked all four files with no other finding.

These static/RPC controls and function tests are **not** a complete browser test, database integration test, deployed-function test or production trial. No browser exercised this repaired release, no database/storage fixture was created, and no production/customer request occurred.

## 6. Independent review

An independent read-only review of the exact local repair found no blocking issue in the customer session/PDF/receipt/approval chain, security controls, runtime imports, selected RPC migrations, function configuration, required binding, payload scope or documented release order. It confirmed that no additional runtime file, asset, dependency, workflow or migration is required for this bounded function repair.

The review remains static and advisory. Its residual gaps are the same explicit evidence boundary above: mocked RPC/storage tests do not prove a real browser, database/storage integration, deployed function or production/customer flow. Payload inventory and aggregate hash were separately recomputed by the preparation controls rather than delegated to the reviewer. No external action is authorized by the review.

## 7. Required later release sequence

This is a recovery sequence, not authorization:

1. Independently review this exact local commit, 81-file inventory and hash; keep PR #60 draft until the customer function gate closes.
2. Under separate publication authorization, push only the reviewed repair commit to `release/c3-r1-20261001`. Re-read PR head, base/main and payload hash; a release-branch push must start no workflow.
3. Under separate binding authorization, set only `LWS_COMMERCIAL_CUSTOMER_APPROVAL_ORIGIN` to the approved HTTPS origin without echoing its value. Read back the exact name and preserve all existing delivery-PDF names; do not set hold or cleanup bindings.
4. Deploy only `commercial-customer-approval` from the exact reviewed release commit:

```powershell
npx supabase functions deploy commercial-customer-approval --project-ref xcsptvntvrizwhskaphr --no-verify-jwt --use-api --workdir C:\Users\info\Project-Worktrees\lorenzo-web-studio-c3-r1-release-20261001
```

5. Read back function name, ID, version, digest, `ACTIVE` and `verify_jwt=false`. A non-mutating page reachability check may verify configuration, but it is not proof of session/PDF/receipt/acceptance behavior. Do not create a fixture or use a real customer as verification.
6. Only after the binding and customer-function deployment/readback are accepted may PR #60 be marked ready again. Re-run the existing merge gate before merging; merge still has the separately controlled automatic operator and Pages consequences.

No migration is part of this repair: the 46 migrations were already applied and read back. Do not run migration repair, deploy the operator/conversion/cleanup functions, dispatch the PDF workflow or perform a fixture/trial as part of the customer-function recovery gate.