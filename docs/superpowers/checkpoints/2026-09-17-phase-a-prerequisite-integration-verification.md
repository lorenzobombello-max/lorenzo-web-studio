# Phase A Prerequisite Integration Verification

PLAN_AUTHORITY_SHA=6d06fed6fec07d878dfcffbd7891feda251ac5f6
FIRST_PARENT=b94e29b1d304622378a8b69f010ae68dbb90054c
SECOND_PARENT=4dd420b4510df55642a8b1e2e1b91dfc4a61155e
COMMON_MERGE_BASE=a8ccd6da08fbd07c0f88b90f99cb93497abdb2f7
CONFLICT_COUNT=8
CURRENT_ONLY_COUNT=7
COMBINE_COUNT=1
IDENTICAL_OVERLAP_COUNT=5
RIGHT_ONLY_PATH_COUNT=78
TASK13_MIGRATION_COUNT=7
TASK13_PGTAP_FILE_COUNT=5
ALL_EIGHT_EXACT_PREREQUISITES_EXPECTED=JA
NO_SECOND_CREATE=HARD
TASK13_RECOVERY_REPEAT=FORBIDDEN
TASK13_FINALIZATION_REPEAT=FORBIDDEN
RECOVERY_RPC_CALLS_EXECUTED=0
FINALIZATION_RPC_CALLS_EXECUTED=0
PROVIDER_WRITE_CALLS_EXECUTED=0
REPOSITORY_CREATE_CALLS_EXECUTED=0
TASK2_STARTED=NEE
PUSHES=0
DEPLOYS=0
REMOTE_MIGRATIONS=0
REMOTE_MUTATIONS=0
REPOSITORY_CREATES=0

## Task L Disposition

TASK_L_RESULT=PASS_WITH_KNOWN_DATABASE_BLOCKER
TASK_L_NON_DATABASE_GATES=PASS
TASK_L_DATABASE_GATE=BLOCKED_PENDING_SEPARATE_CONTROLLER_REPAIR
TASK_L_DATABASE_BLOCKER_CONTROLLER_DISPOSITION=ACCEPTED_FOR_INTEGRATION_MERGE

## Test Evidence

V118_HANDLER_COMMAND=deno test --node-modules-dir=none --no-lock --allow-env --allow-read supabase/functions/commercial-operator-command/handler.test.ts
V118_HANDLER_RESULT=PASS_141_PASSED_0_FAILED
WEBSITE_EXECUTION_FRONTEND_COMMAND=node --test scripts/operator-website-execution.test.mjs
WEBSITE_EXECUTION_FRONTEND_RESULT=PASS_29_PASSED_0_FAILED
PREREQUISITE_MANIFEST_COMMAND=git ls-files --error-unmatch supabase/functions/_shared/repository-provisioning.ts supabase/functions/_shared/github-app-config.ts supabase/functions/_shared/github-app-config.test.ts supabase/functions/_shared/github-app-private-key.ts supabase/functions/_shared/github-installation-token.ts supabase/functions/_shared/github-app-token.ts supabase/functions/_shared/github-app-token.test.ts supabase/functions/_shared/github-http.ts supabase/functions/_shared/github-http.test.ts supabase/functions/_shared/github-ref-read-diagnostic.ts supabase/migrations/20260914090000_add_website_repository_provisioning_v1.sql
PREREQUISITE_MANIFEST_RESULT=PASS_11_PATHS
DENO_CHECK_COMMAND=deno check --no-lock supabase/functions/_shared/github-app-config.ts supabase/functions/_shared/github-app-private-key.ts supabase/functions/_shared/github-installation-token.ts supabase/functions/_shared/github-app-token.ts supabase/functions/_shared/github-http.ts supabase/functions/_shared/github-ref-read-diagnostic.ts
DENO_CHECK_RESULT=PASS
GITHUB_APP_PREREQUISITE_TEST_COMMAND=deno test --node-modules-dir=none --no-lock --allow-env --allow-read supabase/functions/_shared/github-app-config.test.ts supabase/functions/_shared/github-app-token.test.ts supabase/functions/_shared/github-http.test.ts
GITHUB_APP_PREREQUISITE_TEST_RESULT=PASS_87_PASSED_0_FAILED
CACHE_RECONCILIATION_TEST_COMMAND=node --test scripts/operator-auth.test.mjs scripts/operator-calendar.test.mjs scripts/operator-dashboard.test.mjs scripts/operator-dossiers.test.mjs scripts/operator-mfa.test.mjs scripts/operator-profile-welcome.test.mjs scripts/operator-project-requirements.test.mjs
CACHE_RECONCILIATION_TESTS=PASS_357_PASSED_0_FAILED
MANAGED_WORKSPACE_FRONTEND_COMMAND=node --test scripts/operator-workspace.test.mjs
MANAGED_WORKSPACE_FRONTEND_RESULT=PASS_44_PASSED_0_FAILED
CACHE_CHAIN_RECONCILIATION=PASS
AUTHORITATIVE_CACHE_GENERATION=20260917-pre-project-workspace-r2
CACHE_PRODUCTION_FILES_CHANGED=7
CACHE_TEST_FILES_CHANGED=7
STALE_ACTIVE_CACHE_TOKENS_REMAINING=0
DENO_VERSION=2.9.5
DENO_CHECK_COMMAND_USES_NO_LOCK=JA
DENO_LOCK_INDEX_BLOB=134d5eda38130b9f61eb8c84b941e50e1522dc3b
DENO_LOCK_WORKTREE_EQUALS_INDEX=JA
DENO_LOCK_STAGED_CHANGE=NEE
DENO_LOCK_UNSTAGED_CHANGE=NEE

DIALOG_EXPECTATION_RECONCILIATION=PASS
DIALOG_EXPECTED_COUNT=18
DIALOG_ACTUAL_COUNT=18
DIALOG_AUTHORITY_COMPLIANT_COUNT=18
DIALOG_AUTHORITY_NONCOMPLIANT_COUNT=0
DIALOG_EXPECTED_ORIGINAL_ENTRIES_PRESERVED=14
DIALOG_EXPECTED_ENTRIES_ADDED=4
DIALOG_PRODUCTION_FILES_CHANGED=0

RECRUITMENT_TEST_CONTRACT_RECONCILIATION=PASS
RECRUITMENT_ROOT_CAUSE=PREEXISTING_STALE_TEST_REGEX
RECRUITMENT_GENERIC_CANDIDATE_COPY_ALLOWED=JA
RETIRED_PLACEHOLDER_REINTRODUCTION_BLOCKED=JA
SYNTHETIC_FIXTURE_LEAK_PROTECTION_PRESERVED=JA
HR_CONTRACT_AUTHORITY_PROTECTION_PRESERVED=JA
PRODUCTION_RECRUITMENT_MARKUP_CHANGED=NEE

RESPONSIVE_CSS_ASSERTION_RECONCILIATION=PASS
RESPONSIVE_ROOT_CAUSE=PREEXISTING_STALE_CSS_REGEX
RESPONSIVE_BREAKPOINT_PRESENT=JA
RESPONSIVE_RECRUITMENT_HEADING_SELECTOR_PRESENT=JA
RESPONSIVE_RECRUITMENT_HEADING_FLEX_DIRECTION_COLUMN=JA
RESPONSIVE_ASSERTION_GROUPING_INDEPENDENT=JA
RESPONSIVE_ASSERTION_FORMATTING_INDEPENDENT=JA
PRODUCTION_CSS_CHANGED=NEE

CONFLICT_MARKER_COMMAND=git grep --cached -n -E '^(<<<<<<<|=======|>>>>>>>)' -- .
CONFLICT_MARKER_RESULT=PASS_0_MATCHES
UNMERGED_ENTRY_COMMAND=git diff --name-only --diff-filter=U
UNMERGED_ENTRY_RESULT=PASS_0_PATHS
DEPENDENCY_GRAPH_NO_WRITE_COMMAND=git grep --cached -n -E 'CREATE_REPOSITORY|CREATE_BLOB|CREATE_TREE|CREATE_COMMIT|CREATE_REF|UPDATE_REF|WRITE_PROJECT_MARKER|RepositoryProvisioningServiceV2|postCreateRecovery|postRecoveryFinalizer' -- "assets/js/application-dossier-copy.js" "assets/js/operator-auth-client.mjs" "assets/js/operator-auth-core.mjs" "assets/js/operator-auto-refresh.mjs" "assets/js/operator-calendar-leave.mjs" "assets/js/operator-calendar.mjs" "assets/js/operator-dossiers.mjs" "assets/js/operator-finance.mjs" "assets/js/operator-messages.mjs" "assets/js/operator-mfa.mjs" "assets/js/operator-module-registry.mjs" "assets/js/operator-project-requirements-child.mjs" "assets/js/operator-project-requirements.mjs" "assets/js/operator-project-workspace-child.mjs" "assets/js/operator-project-workspace.mjs" "assets/js/operator-recruitment-applications.mjs" "assets/js/operator-recruitment-tests.mjs" "assets/js/operator-recruitment.mjs" "assets/js/operator-refresh-heartbeat.mjs" "assets/js/operator-vat-readiness.mjs" "assets/js/operator-website-execution-child.mjs" "assets/js/operator-website-execution.mjs" "assets/js/operator-window-guard.mjs" "assets/js/operator-window-host.mjs" "assets/js/operator-workforce.mjs" "assets/js/operator-workspace-child.mjs" "assets/js/operator-workspace-protocol.mjs" "assets/js/sdf-qualification-review.mjs" "operator/window/index.html" "supabase/functions/_shared/application-output.ts" "supabase/functions/_shared/cors.ts" "supabase/functions/_shared/customer-request-upload-capability.ts" "supabase/functions/_shared/email-delivery.ts" "supabase/functions/_shared/email-templates.ts" "supabase/functions/_shared/operator-cursor.ts" "supabase/functions/_shared/pricing-catalog.ts" "supabase/functions/_shared/pricing-config.ts" "supabase/functions/_shared/pricing-snapshot-integrity.ts" "supabase/functions/_shared/quotation-acceptance-capability.ts" "supabase/functions/_shared/quotation-approval-integrity.ts" "supabase/functions/_shared/quotation-email-orchestration.ts" "supabase/functions/_shared/request-kind.ts" "supabase/functions/_shared/security.ts" "supabase/functions/_shared/submitted-application-output.ts" "supabase/functions/_shared/supabase-key-bindings.ts" "supabase/functions/_shared/types.ts" "supabase/functions/commercial-operator-command/handler.ts" "supabase/functions/commercial-operator-command/index.ts" "supabase/functions/commercial-operator-command/quotation-orchestrator.ts" "supabase/functions/commercial-operator-command/quotation-renderer-edge.ts" "supabase/functions/commercial-operator-command/quotation-runtime.ts" "supabase/functions/commercial-operator-command/sdf-quotation-renderer-edge.ts" "supabase/functions/commercial-operator-command/vat-readiness.ts"
DEPENDENCY_GRAPH_NO_WRITE_RESULT=PASS_0_REACHABLE_WRITES
V118_PRESERVATION_COMMAND=git diff --cached --name-only b94e29b1d304622378a8b69f010ae68dbb90054c -- scripts/operator-website-execution.test.mjs supabase/functions/commercial-operator-command/handler.test.ts supabase/functions/commercial-operator-command/handler.ts supabase/functions/commercial-operator-command/index.ts supabase/migrations/20260913100000_add_pre_project_technical_workspace_provisioning_v1.sql supabase/tests/website_concept_pre_project_v1.sql
V118_PRESERVATION_RESULT=PASS_5_EXACT_FIRST_PARENT_BLOBS_1_ASSERTION_ONLY_COMBINE

## Database Evidence

LOCAL_STACK_START_RESULT=FAIL
LOCAL_STACK_START_ERROR=LegacyMigrationApplyError
LOCAL_BOOTSTRAP_ERROR=OP_01_AUTH_ACCOUNT_MISMATCH
PGTAP_TARGET_TEST_REACHED=NEE
PGTAP_TARGET_RESULT=NOT_REACHED
DATABASE_GATE=BLOCKED_PENDING_SEPARATE_CONTROLLER_REPAIR
DATABASE_BLOCKER_ACCEPTED_BY_CONTROLLER_FOR_TASK_L=JA