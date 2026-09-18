import type { Gate6ProbeConfig } from "./runtime.ts";
import {
  GitHubAppGate6ProbeError,
  type GitHubAppGate6ProbeInput,
} from "./probe.ts";

export type Gate6PreProbeFailedPhase =
  | "REQUEST_PARSE"
  | "CALLER_VERIFICATION"
  | "AAL2_VERIFICATION"
  | "OWNER_AUTHORIZATION"
  | "CONFIGURATION_LOAD"
  | "PRIVATE_KEY_IMPORT_OR_SIGNER_INIT"
  | "PROBE_DEPENDENCY_INIT"
  | "PROBE_INVOCATION"
  | "RESPONSE_PROJECTION"
  | "UNKNOWN_INTERNAL";

export class Gate6PreProbeError extends Error {
  constructor(readonly failedPhase: Gate6PreProbeFailedPhase) {
    super("GITHUB_APP_GATE6_PROBE_FAILED");
    this.name = "Gate6PreProbeError";
  }
}

async function stage<T>(
  failedPhase: Gate6PreProbeFailedPhase,
  operation: () => T | Promise<T>,
): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    if (
      error instanceof Gate6PreProbeError ||
      error instanceof GitHubAppGate6ProbeError
    ) throw error;
    throw new Gate6PreProbeError(failedPhase);
  }
}

export async function runGate6PreProbePipeline<
  Configuration,
  Signer,
  ProbeDependencies,
  Result,
>(
  dependencies: Readonly<{
    loadConfiguration(): Configuration | Promise<Configuration>;
    initializeSigner(configuration: Configuration): Signer | Promise<Signer>;
    initializeDependencies(
      configuration: Configuration,
      signer: Signer,
    ): ProbeDependencies | Promise<ProbeDependencies>;
    invokeProbe(dependencies: ProbeDependencies): Result | Promise<Result>;
  }>,
): Promise<Result> {
  const configuration = await stage(
    "CONFIGURATION_LOAD",
    dependencies.loadConfiguration,
  );
  const signer = await stage(
    "PRIVATE_KEY_IMPORT_OR_SIGNER_INIT",
    () => dependencies.initializeSigner(configuration),
  );
  const probeDependencies = await stage(
    "PROBE_DEPENDENCY_INIT",
    () => dependencies.initializeDependencies(configuration, signer),
  );
  return await stage(
    "PROBE_INVOCATION",
    () => dependencies.invokeProbe(probeDependencies),
  );
}

export function createGitHubAppGate6ProbeInput(
  config: Gate6ProbeConfig,
  signAppJwt: GitHubAppGate6ProbeInput["signAppJwt"],
  fetcher: GitHubAppGate6ProbeInput["fetch"],
): GitHubAppGate6ProbeInput {
  const input = {
    appId: config.appId,
    installationId: config.installationId,
    repositoryId: config.repositoryId,
    repositoryOwner: config.repositoryOwner,
    repositoryName: config.repositoryName,
    signAppJwt,
    fetch: fetcher,
  };
  Object.defineProperty(input, "privateKey", {
    value: config.privateKey,
    enumerable: false,
    configurable: false,
    writable: false,
  });
  return Object.freeze(input) as GitHubAppGate6ProbeInput;
}
