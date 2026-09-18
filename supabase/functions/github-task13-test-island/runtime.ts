import type { GitHubTask13RuntimeConfig } from "../_shared/github-app-config.ts";
import type { GitHubHttpClient } from "../_shared/github-http.ts";
import type { GitHubRepositoryRuntimeDependencies } from "../_shared/github-repository-runtime.ts";
import type {
  RepositoryProvisioningCommandV2,
  RepositoryProvisioningProviderV2,
  RepositoryProvisioningResultV2,
  RepositoryStarterProvenance,
} from "../_shared/repository-provisioning.ts";
import {
  RepositoryProvisioningClaimDiagnosticError,
  RepositoryProvisioningProviderDiagnosticError,
  RepositoryProvisioningRuntimeDiagnosticError,
} from "../_shared/repository-provisioning-diagnostics.ts";
import type { RepositoryProvisioningRuntimeStoreV2 } from "../_shared/repository-provisioning-store-v2.ts";

export const TASK13_PRECLAIM_PHASES = [
  "REQUEST_VALIDATION",
  "CALLER_VERIFICATION",
  "AAL2_VERIFICATION",
  "OWNER_AUTHORIZATION",
  "RUNTIME_CONFIG_LOAD",
  "STARTER_PROVENANCE_LOAD",
  "GITHUB_APP_SIGNER_INIT",
  "PRODUCTION_TOKEN_BROKER_INIT",
  "LAB_TOKEN_BROKER_INIT",
  "STORE_ADAPTER_INIT",
  "PROVIDER_INIT",
  "RUNTIME_ASSEMBLY",
  "COMMAND_VALIDATION",
  "RUNTIME_PROVISION_INVOCATION",
  "UNKNOWN_PRECLAIM_ERROR",
] as const;

export type Task13PreclaimPhase = (typeof TASK13_PRECLAIM_PHASES)[number];

export class RepositoryPreclaimDiagnosticError extends Error {
  constructor(readonly phase: Task13PreclaimPhase) {
    if (!TASK13_PRECLAIM_PHASES.includes(phase)) {
      throw new Error("TASK13_PRECLAIM_DIAGNOSTIC_INVALID");
    }
    super("TASK13_PRECLAIM_FAILED");
    this.name = "RepositoryPreclaimDiagnosticError";
  }
}

type Input = Omit<RepositoryProvisioningCommandV2, "starter">;
type Signer = (signingInput: string) => Promise<Uint8Array>;
type TokenBroker = GitHubRepositoryRuntimeDependencies["tokenBroker"];
type Runtime = Readonly<{
  provision(
    command: RepositoryProvisioningCommandV2,
  ): Promise<RepositoryProvisioningResultV2>;
}>;

export interface Task13PreclaimDependencies {
  loadConfig(): GitHubTask13RuntimeConfig;
  loadStarterProvenance(
    config: GitHubTask13RuntimeConfig,
  ): RepositoryStarterProvenance;
  initializeSigner(config: GitHubTask13RuntimeConfig): Promise<Signer>;
  createHttpClient(): GitHubHttpClient;
  createProductionTokenBroker(
    input: Readonly<{
      config: GitHubTask13RuntimeConfig;
      signer: Signer;
      http: GitHubHttpClient;
    }>,
  ): TokenBroker;
  createLabTokenBroker(
    input: Readonly<{
      config: GitHubTask13RuntimeConfig;
      signer: Signer;
      http: GitHubHttpClient;
    }>,
  ): TokenBroker;
  createStore(jwt: string): RepositoryProvisioningRuntimeStoreV2;
  createProvider(
    config: GitHubTask13RuntimeConfig,
    dependencies: GitHubRepositoryRuntimeDependencies,
  ): RepositoryProvisioningProviderV2;
  createRuntime(
    provider: RepositoryProvisioningProviderV2,
    store: RepositoryProvisioningRuntimeStoreV2,
  ): Runtime;
  validateCommand(
    input: Input,
    starter: RepositoryStarterProvenance,
  ): RepositoryProvisioningCommandV2;
}

async function phase<T>(
  name: Task13PreclaimPhase,
  action: () => T | Promise<T>,
  preserveDownstreamDiagnostics = false,
): Promise<T> {
  try {
    return await action();
  } catch (error) {
    if (
      preserveDownstreamDiagnostics &&
        (error instanceof RepositoryProvisioningClaimDiagnosticError ||
          error instanceof RepositoryProvisioningProviderDiagnosticError ||
          error instanceof RepositoryProvisioningRuntimeDiagnosticError) ||
      error instanceof RepositoryPreclaimDiagnosticError
    ) throw error;
    throw new RepositoryPreclaimDiagnosticError(name);
  }
}

export function createTask13PreclaimExecutor(
  dependencies: Task13PreclaimDependencies,
) {
  return async (input: Input, jwt: string) => {
    const config = await phase(
      "RUNTIME_CONFIG_LOAD",
      dependencies.loadConfig,
    );
    const starter = await phase(
      "STARTER_PROVENANCE_LOAD",
      () => dependencies.loadStarterProvenance(config),
    );
    const signer = await phase(
      "GITHUB_APP_SIGNER_INIT",
      () => dependencies.initializeSigner(config),
    );
    const http = await phase("RUNTIME_ASSEMBLY", dependencies.createHttpClient);
    const brokerInput = Object.freeze({ config, signer, http });
    const productionTokenBroker = await phase(
      "PRODUCTION_TOKEN_BROKER_INIT",
      () => dependencies.createProductionTokenBroker(brokerInput),
    );
    const labTokenBroker = await phase(
      "LAB_TOKEN_BROKER_INIT",
      () => dependencies.createLabTokenBroker(brokerInput),
    );
    const store = await phase(
      "STORE_ADAPTER_INIT",
      () => dependencies.createStore(jwt),
    );
    const tokenBroker: TokenBroker = Object.freeze({
      issue: (appConfig, request, authority) =>
        (appConfig.target === "PRODUCTION"
          ? productionTokenBroker
          : labTokenBroker).issue(appConfig, request, authority),
    });
    const provider = await phase(
      "PROVIDER_INIT",
      () => dependencies.createProvider(config, { store, tokenBroker, http }),
    );
    const runtime = await phase(
      "RUNTIME_ASSEMBLY",
      () => dependencies.createRuntime(provider, store),
    );
    const command = await phase(
      "COMMAND_VALIDATION",
      () => dependencies.validateCommand(input, starter),
    );
    return await phase(
      "RUNTIME_PROVISION_INVOCATION",
      () => runtime.provision(command),
      true,
    );
  };
}
