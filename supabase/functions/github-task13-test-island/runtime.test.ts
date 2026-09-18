import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { GitHubRepositoryProviderError } from "../_shared/github-repository-provider.ts";
import { RepositoryProvisioningClaimDiagnosticError } from "../_shared/repository-provisioning-diagnostics.ts";
import {
  createTask13PreclaimExecutor,
  RepositoryPreclaimDiagnosticError,
  type Task13PreclaimDependencies,
} from "./runtime.ts";

const INPUT = Object.freeze({
  contractVersion: 2 as const,
  websiteWorkspaceId: "d2110000-0000-4000-8000-000000000001",
  websiteWorkContextId: "d2120000-0000-4000-8000-000000000001",
  idempotencyKey: "d2130000-0000-4000-8000-000000000001",
});

function dependencies(): Task13PreclaimDependencies {
  const broker = { issue: () => Promise.reject(new Error("not called")) };
  const store = { claim() {}, bind() {}, fail() {} };
  const provider = { provision() {} };
  const runtime = { provision: () => Promise.resolve({}) };
  return {
    loadConfig: () => ({
      production: { target: "PRODUCTION" },
      lab: { target: "TEST" },
    }),
    loadStarterProvenance: () => ({
      source: "lorenzo-web-solutions/lws-website-starter",
      version: "1.0.0",
      commitSha: "a".repeat(40),
      templateRepositoryId: "1368684860",
    }),
    initializeSigner: () => Promise.resolve(() => Promise.resolve("signature")),
    createHttpClient: () => ({ execute() {} }),
    createProductionTokenBroker: () => broker,
    createLabTokenBroker: () => broker,
    createStore: () => store,
    createProvider: () => provider,
    createRuntime: () => runtime,
    validateCommand: (
      input: Parameters<Task13PreclaimDependencies["validateCommand"]>[0],
      starter: Parameters<Task13PreclaimDependencies["validateCommand"]>[1],
    ) => Object.freeze({ ...input, starter }),
  } as unknown as Task13PreclaimDependencies;
}

Deno.test("Task 13 pre-claim assembly classifies every factory boundary", async () => {
  const scenarios = [
    ["loadConfig", "RUNTIME_CONFIG_LOAD"],
    ["loadStarterProvenance", "STARTER_PROVENANCE_LOAD"],
    ["initializeSigner", "GITHUB_APP_SIGNER_INIT"],
    ["createProductionTokenBroker", "PRODUCTION_TOKEN_BROKER_INIT"],
    ["createLabTokenBroker", "LAB_TOKEN_BROKER_INIT"],
    ["createStore", "STORE_ADAPTER_INIT"],
    ["createProvider", "PROVIDER_INIT"],
    ["createRuntime", "RUNTIME_ASSEMBLY"],
    ["validateCommand", "COMMAND_VALIDATION"],
  ] as const;

  for (const [boundary, phase] of scenarios) {
    const values = dependencies() as unknown as Record<string, unknown>;
    values[boundary] = () => {
      throw new Error("raw secret from boundary");
    };
    const execute = createTask13PreclaimExecutor(
      values as unknown as Task13PreclaimDependencies,
    );
    const error = await assertRejects(
      () => execute(INPUT, "redacted-jwt"),
      RepositoryPreclaimDiagnosticError,
    );
    assertEquals(error.phase, phase, boundary);
    assertEquals(JSON.stringify(error).includes("raw secret"), false);
  }
});

Deno.test("Task 13 pre-claim assembly does not preserve downstream diagnostics before invocation", async () => {
  const providerDependencies = dependencies();
  providerDependencies.createProvider = () => {
    throw new GitHubRepositoryProviderError(
      "GITHUB_REPOSITORY_PROVIDER_CONFIG_INVALID",
    );
  };
  const provider = await assertRejects(
    () =>
      createTask13PreclaimExecutor(providerDependencies)(
        INPUT,
        "redacted-jwt",
      ),
    RepositoryPreclaimDiagnosticError,
  );
  assertEquals(provider.phase, "PROVIDER_INIT");

  const claimDependencies = dependencies();
  claimDependencies.createStore = () => {
    throw new RepositoryProvisioningClaimDiagnosticError(
      "CLAIM_RPC_INVOCATION",
    );
  };
  const claim = await assertRejects(
    () =>
      createTask13PreclaimExecutor(claimDependencies)(INPUT, "redacted-jwt"),
    RepositoryPreclaimDiagnosticError,
  );
  assertEquals(claim.phase, "STORE_ADAPTER_INIT");
});

Deno.test("Task 13 pre-claim assembly classifies runtime invocation and preserves StoreV2 diagnostics", async () => {
  const invocationDependencies = dependencies();
  invocationDependencies.createRuntime = () => ({
    provision: () => Promise.reject(new Error("runtime secret")),
  });
  const invocation = await assertRejects(
    () =>
      createTask13PreclaimExecutor(invocationDependencies)(
        INPUT,
        "redacted-jwt",
      ),
    RepositoryPreclaimDiagnosticError,
  );
  assertEquals(invocation.phase, "RUNTIME_PROVISION_INVOCATION");

  const claimDependencies = dependencies();
  claimDependencies.createRuntime = () => ({
    provision: () =>
      Promise.reject(
        new RepositoryProvisioningClaimDiagnosticError(
          "CLAIM_RPC_DATABASE_EXCEPTION",
          "23",
        ),
      ),
  });
  const claim = await assertRejects(
    () =>
      createTask13PreclaimExecutor(claimDependencies)(INPUT, "redacted-jwt"),
    RepositoryProvisioningClaimDiagnosticError,
  );
  assertEquals(claim.phase, "CLAIM_RPC_DATABASE_EXCEPTION");
  assertEquals(claim.sqlstateClass, "23");

  const providerDependencies = dependencies();
  providerDependencies.createRuntime = () => ({
    provision: () =>
      Promise.reject(
        new GitHubRepositoryProviderError("GITHUB_STARTER_SNAPSHOT_INVALID"),
      ),
  });
  const provider = await assertRejects(
    () =>
      createTask13PreclaimExecutor(providerDependencies)(
        INPUT,
        "redacted-jwt",
      ),
    GitHubRepositoryProviderError,
  );
  assertEquals(provider.code, "GITHUB_STARTER_SNAPSHOT_INVALID");

  let provisionCalls = 0;
  const successfulResult = Object.freeze({
    provider: "GITHUB" as const,
    providerRepositoryId: "1369000001",
    providerNodeId: "R_task13_repository",
    owner: "lorenzo-web-solutions-lab",
    name: "lws-web-d2120000000040008000000000000001",
    visibility: "PRIVATE" as const,
    defaultBranch: "main" as const,
    starterSource: "lorenzo-web-solutions/lws-website-starter",
    starterVersion: "1.0.0",
    starterCommitSha: "a".repeat(40),
    repositoryMarkerCommitSha: "b".repeat(40),
    replayed: false,
  });
  const successfulDependencies = dependencies();
  successfulDependencies.createRuntime = () => ({
    provision: () => {
      provisionCalls++;
      return Promise.resolve(successfulResult);
    },
  });
  assertEquals(
    await createTask13PreclaimExecutor(successfulDependencies)(
      INPUT,
      "redacted-jwt",
    ),
    successfulResult,
  );
  assertEquals(provisionCalls, 1);
});
