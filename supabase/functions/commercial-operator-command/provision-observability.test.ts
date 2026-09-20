import { assertEquals } from "jsr:@std/assert@1";
import {
  GitHubAppConfigurationError,
  GitHubProviderDisabledError,
} from "../_shared/github-app-config.ts";
import {
  RepositoryProvisioningClaimDiagnosticError,
  RepositoryProvisioningProviderDiagnosticError,
  RepositoryProvisioningRuntimeDiagnosticError,
} from "../_shared/repository-provisioning-diagnostics.ts";
import {
  WEBSITE_REPOSITORY_PROVISION_STAGES,
  websiteRepositoryProvisionFailureLog,
  withWebsiteRepositoryProvisionFailureLogging,
} from "./index.ts";

Deno.test("repository provision observability exposes the complete stage contract", () => {
  assertEquals(WEBSITE_REPOSITORY_PROVISION_STAGES, [
    "CONFIG_LOAD",
    "TARGET_VALIDATE",
    "SIGNER_INIT",
    "STORE_INIT",
    "PROVIDER_INIT",
    "RUNTIME_PROVISION",
  ]);
});

Deno.test("provider-disabled configuration failure uses only its closed classifier", () => {
  assertEquals(
    websiteRepositoryProvisionFailureLog(
      "CONFIG_LOAD",
      new GitHubProviderDisabledError(),
    ),
    {
      event: "LWS_GIT001_PROVISION_FAILURE",
      action: "provision_website_repository",
      stage: "CONFIG_LOAD",
      error_name: "GitHubProviderDisabledError",
      diagnostic_code: "GITHUB_PROVIDER_DISABLED",
    },
  );
});

Deno.test("invalid GitHub configuration uses only its closed classifier", () => {
  assertEquals(
    websiteRepositoryProvisionFailureLog(
      "CONFIG_LOAD",
      new GitHubAppConfigurationError(),
    ),
    {
      event: "LWS_GIT001_PROVISION_FAILURE",
      action: "provision_website_repository",
      stage: "CONFIG_LOAD",
      error_name: "GitHubAppConfigurationError",
      diagnostic_code: "GITHUB_CONFIGURATION_INVALID",
    },
  );
});

Deno.test("production authority failure uses only its fixed classifier", () => {
  assertEquals(
    websiteRepositoryProvisionFailureLog(
      "TARGET_VALIDATE",
      new Error("PRODUCTION_GITHUB_AUTHORITY_REQUIRED"),
    ),
    {
      event: "LWS_GIT001_PROVISION_FAILURE",
      action: "provision_website_repository",
      stage: "TARGET_VALIDATE",
      error_name: "Error",
      diagnostic_code: "PRODUCTION_GITHUB_AUTHORITY_REQUIRED",
    },
  );
});

Deno.test("claim diagnostics log only the closed claim phase and SQLSTATE class", () => {
  assertEquals(
    websiteRepositoryProvisionFailureLog(
      "RUNTIME_PROVISION",
      new RepositoryProvisioningClaimDiagnosticError(
        "CLAIM_RPC_DATABASE_EXCEPTION",
        "23",
      ),
    ),
    {
      event: "LWS_GIT001_PROVISION_FAILURE",
      action: "provision_website_repository",
      stage: "RUNTIME_PROVISION",
      error_name: "RepositoryProvisioningClaimDiagnosticError",
      diagnostic_code: "REPOSITORY_PROVISIONING_CLAIM_FAILED",
      claim_phase: "CLAIM_RPC_DATABASE_EXCEPTION",
      sqlstate_class: "23",
    },
  );
});

Deno.test("runtime diagnostics use only the validated runtime phase", () => {
  assertEquals(
    websiteRepositoryProvisionFailureLog(
      "RUNTIME_PROVISION",
      new RepositoryProvisioningRuntimeDiagnosticError(
        "INVALID_REPOSITORY_PROVISIONING_COMMAND_V2",
      ),
    ),
    {
      event: "LWS_GIT001_PROVISION_FAILURE",
      action: "provision_website_repository",
      stage: "RUNTIME_PROVISION",
      error_name: "RepositoryProvisioningRuntimeDiagnosticError",
      diagnostic_code: "INVALID_REPOSITORY_PROVISIONING_COMMAND_V2",
    },
  );
});

Deno.test("provider diagnostics expose only validated provider and token fields", () => {
  assertEquals(
    websiteRepositoryProvisionFailureLog(
      "RUNTIME_PROVISION",
      new RepositoryProvisioningProviderDiagnosticError(
        "GITHUB_STARTER_SNAPSHOT_INVALID",
        "STARTER_TOKEN_ACQUIRE",
        "TOKEN_RESPONSE_SCHEMA",
        undefined,
        "TOKEN_SCHEMA_TOKEN",
      ),
    ),
    {
      event: "LWS_GIT001_PROVISION_FAILURE",
      action: "provision_website_repository",
      stage: "RUNTIME_PROVISION",
      error_name: "RepositoryProvisioningProviderDiagnosticError",
      diagnostic_code: "GITHUB_STARTER_SNAPSHOT_INVALID",
      provider_phase: "GITHUB_STARTER_SNAPSHOT_INVALID",
      provider_subphase: "STARTER_TOKEN_ACQUIRE",
      token_acquire_subphase: "TOKEN_RESPONSE_SCHEMA",
      token_response_check: "TOKEN_SCHEMA_TOKEN",
    },
  );
});

Deno.test("unknown failures log once without message stack or sensitive strings and rethrow unchanged", async () => {
  const sensitive = [
    "Bearer secret.jwt.value",
    "ghs_secret_installation_token",
    "PRIVATE KEY secret",
    "customer@example.test",
  ].join(" ");
  const error = new Error(sensitive);
  const entries: string[] = [];
  let caught: unknown;
  try {
    await withWebsiteRepositoryProvisionFailureLogging(
      async (setStage) => {
        setStage("SIGNER_INIT");
        throw error;
      },
      (entry) => entries.push(entry),
    );
  } catch (failure) {
    caught = failure;
  }
  assertEquals(caught, error);
  assertEquals(entries.length, 1);
  assertEquals(JSON.parse(entries[0]), {
    event: "LWS_GIT001_PROVISION_FAILURE",
    action: "provision_website_repository",
    stage: "SIGNER_INIT",
    error_name: "Error",
    diagnostic_code: "UNCLASSIFIED",
  });
  for (
    const forbidden of [
      "Bearer",
      "ghs_",
      "PRIVATE KEY",
      "customer@example",
      "stack",
      "cause",
    ]
  ) {
    assertEquals(entries[0].includes(forbidden), false, forbidden);
  }
});

Deno.test("successful provisioning boundary writes no failure log", async () => {
  const entries: string[] = [];
  const result = await withWebsiteRepositoryProvisionFailureLogging(
    async (setStage) => {
      setStage("RUNTIME_PROVISION");
      return "READY";
    },
    (entry) => entries.push(entry),
  );
  assertEquals(result, "READY");
  assertEquals(entries, []);
});
