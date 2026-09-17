import {
  type GitHubRefReadDiagnostic,
  validateGitHubRefReadDiagnostic,
} from "./github-ref-read-diagnostic.ts";

export const REPOSITORY_CLAIM_FAILURE_PHASES = [
  "CLAIM_RPC_INVOCATION",
  "CLAIM_RPC_HTTP_OR_POSTGREST",
  "CLAIM_RPC_AUTHORITY",
  "CLAIM_RPC_DATABASE_EXCEPTION",
  "CLAIM_RPC_RESPONSE_VALIDATION",
  "UNKNOWN_CLAIM_ERROR",
] as const;

export type RepositoryProvisioningClaimFailurePhase =
  (typeof REPOSITORY_CLAIM_FAILURE_PHASES)[number];

export class RepositoryProvisioningClaimDiagnosticError extends Error {
  constructor(
    readonly phase: RepositoryProvisioningClaimFailurePhase,
    readonly sqlstateClass?: string,
  ) {
    if (!REPOSITORY_CLAIM_FAILURE_PHASES.includes(phase)) {
      throw new Error("REPOSITORY_PROVISIONING_CLAIM_DIAGNOSTIC_INVALID");
    }
    super("REPOSITORY_PROVISIONING_CLAIM_FAILED");
    this.name = "RepositoryProvisioningClaimDiagnosticError";
  }
}

export const REPOSITORY_PROVIDER_FAILURE_PHASES = [
  "GITHUB_REPOSITORY_PROVIDER_CONFIG_INVALID",
  "GITHUB_REPOSITORY_PROVIDER_REQUEST_INVALID",
  "GITHUB_STARTER_SNAPSHOT_INVALID",
  "GITHUB_LAB_CREATE_FAILED",
  "GITHUB_LAB_QUARANTINE_FAILED",
  "GITHUB_LAB_RECONCILIATION_AMBIGUOUS",
  "GITHUB_LAB_POST_CREATE_FAILED",
  "GITHUB_LAB_BINDING_INVALID",
] as const;

export type RepositoryProvisioningProviderFailurePhase =
  (typeof REPOSITORY_PROVIDER_FAILURE_PHASES)[number];

export const REPOSITORY_STARTER_READ_SUBPHASES = [
  "STARTER_TOKEN_ACQUIRE",
  "STARTER_METADATA_READ",
  "STARTER_TREE_READ",
  "STARTER_TREE_VALIDATE",
  "STARTER_BLOB_READ",
  "STARTER_BLOB_VALIDATE",
  "STARTER_SNAPSHOT_VALIDATE",
  "STARTER_DIGEST_CALCULATE",
  "STARTER_DIGEST_COMPARE",
  "STARTER_IDENTITY_VALIDATE",
] as const;

export type RepositoryStarterReadSubphase =
  (typeof REPOSITORY_STARTER_READ_SUBPHASES)[number];

export const GITHUB_LAB_CREATE_SUBPHASES = [
  "LAB_TOKEN_ACQUIRE",
  "LAB_CREATE_REQUEST_PREPARE",
  "LAB_CREATE_HTTP_REQUEST",
  "LAB_CREATE_HTTP_STATUS",
  "LAB_CREATE_CONTENT_TYPE",
  "LAB_CREATE_BODY_READ",
  "LAB_CREATE_JSON_PARSE",
  "LAB_CREATE_RESPONSE_SCHEMA",
  "LAB_CREATE_ADAPTER_PROJECT",
] as const;

export type GitHubLabCreateSubphase =
  (typeof GITHUB_LAB_CREATE_SUBPHASES)[number];

export const GITHUB_LAB_POST_CREATE_SUBPHASES = [
  "LAB_POST_CREATE_WRITE_TOKEN_ACQUIRE",
  "LAB_POST_CREATE_SNAPSHOT_PREPARE",
  "LAB_POST_CREATE_BLOB_WRITE",
  "LAB_POST_CREATE_TREE_WRITE",
  "LAB_POST_CREATE_COMMIT_WRITE",
  "LAB_POST_CREATE_REF_WRITE",
  "LAB_POST_CREATE_MARKER_WRITE",
  "LAB_POST_CREATE_WRITE_RESULT_VALIDATE",
  "LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE",
  "LAB_POST_CREATE_METADATA_READ",
  "LAB_POST_CREATE_SNAPSHOT_READBACK",
  "LAB_POST_CREATE_MARKER_READBACK",
  "LAB_POST_CREATE_PROVENANCE_VALIDATE",
] as const;

export type GitHubLabPostCreateSubphase =
  (typeof GITHUB_LAB_POST_CREATE_SUBPHASES)[number];

export const GITHUB_SNAPSHOT_READBACK_CHECKS = Object.freeze(
  [
    "REF_READ",
    "COMMIT_READ",
    "TREE_READ",
    "BLOB_READ",
    "UNKNOWN",
  ] as const,
);

export type GitHubSnapshotReadbackCheck =
  (typeof GITHUB_SNAPSHOT_READBACK_CHECKS)[number];

export type RepositoryProviderSubphase =
  | RepositoryStarterReadSubphase
  | GitHubLabCreateSubphase
  | GitHubLabPostCreateSubphase;

const GITHUB_LAB_DIRECT_FAILURE_SUBPHASES = [
  "LAB_TOKEN_ACQUIRE",
  "LAB_CREATE_REQUEST_PREPARE",
  "LAB_CREATE_HTTP_STATUS",
] as const;
const GITHUB_LAB_UNCERTAIN_OUTCOME_SUBPHASES = [
  "LAB_CREATE_HTTP_REQUEST",
  "LAB_CREATE_HTTP_STATUS",
  "LAB_CREATE_CONTENT_TYPE",
  "LAB_CREATE_BODY_READ",
  "LAB_CREATE_JSON_PARSE",
  "LAB_CREATE_RESPONSE_SCHEMA",
  "LAB_CREATE_ADAPTER_PROJECT",
] as const;
const githubLabCreateDiagnostics = new WeakSet<object>();
const githubLabPostCreateDiagnostics = new WeakSet<object>();
const githubLabPostCreateDiagnosticErrors = new WeakSet<object>();

export const GITHUB_TOKEN_ACQUIRE_SUBPHASES = [
  "TOKEN_AUTHORITY_VALIDATE",
  "TOKEN_JWT_SIGN",
  "TOKEN_REQUEST_PREPARE",
  "TOKEN_HTTP_REQUEST",
  "TOKEN_HTTP_STATUS",
  "TOKEN_CONTENT_TYPE_VALIDATE",
  "TOKEN_RESPONSE_BODY_READ",
  "TOKEN_JSON_PARSE",
  "TOKEN_RESPONSE_SCHEMA",
  "TOKEN_ADAPTER_PROJECT",
  "TOKEN_LEASE_VALIDATE",
] as const;

export type GitHubTokenAcquireSubphase =
  (typeof GITHUB_TOKEN_ACQUIRE_SUBPHASES)[number];

export const GITHUB_TOKEN_LEASE_CHECKS = [
  "LEASE_TOKEN_FORMAT_VALIDATE",
  "LEASE_EXPIRY_LOWER_BOUND",
  "LEASE_EXPIRY_UPPER_BOUND",
] as const;

export type GitHubTokenLeaseCheck = (typeof GITHUB_TOKEN_LEASE_CHECKS)[number];

export const GITHUB_TOKEN_RESPONSE_CHECKS = [
  "TOKEN_SCHEMA_OBJECT",
  "TOKEN_SCHEMA_TOKEN",
  "TOKEN_SCHEMA_EXPIRY",
  "TOKEN_SCHEMA_PERMISSIONS_SHAPE",
  "TOKEN_SCHEMA_PERMISSION_PARITY",
  "TOKEN_SCHEMA_REPOSITORY_SELECTION",
] as const;

export type GitHubTokenResponseCheck =
  (typeof GITHUB_TOKEN_RESPONSE_CHECKS)[number];

export class GitHubLabPostCreateDiagnosticError extends Error {
  declare readonly snapshotReadbackCheck?: GitHubSnapshotReadbackCheck;

  constructor(
    readonly subphase: GitHubLabPostCreateSubphase,
    snapshotReadbackCheck?: GitHubSnapshotReadbackCheck,
    refReadDiagnostic?: GitHubRefReadDiagnostic,
  ) {
    if (
      !GITHUB_LAB_POST_CREATE_SUBPHASES.includes(subphase) ||
      snapshotReadbackCheck !== undefined &&
        (subphase !== "LAB_POST_CREATE_SNAPSHOT_READBACK" ||
          !GITHUB_SNAPSHOT_READBACK_CHECKS.includes(snapshotReadbackCheck))
    ) {
      throw new Error("GITHUB_LAB_POST_CREATE_DIAGNOSTIC_INVALID");
    }
    super("GITHUB_LAB_POST_CREATE_FAILED");
    this.name = "GitHubLabPostCreateDiagnosticError";
    Object.defineProperty(this, "subphase", {
      value: subphase,
      enumerable: true,
      writable: false,
      configurable: false,
    });
    Object.defineProperty(this, "snapshotReadbackCheck", {
      value: snapshotReadbackCheck,
      enumerable: true,
      writable: false,
      configurable: false,
    });
    githubLabPostCreateDiagnosticErrors.add(this);
    if (
      subphase === "LAB_POST_CREATE_SNAPSHOT_READBACK" &&
      snapshotReadbackCheck === "REF_READ"
    ) {
      githubLabPostCreateRefReadDiagnostics.set(
        this,
        validateGitHubRefReadDiagnostic(refReadDiagnostic),
      );
    }
  }
}

const githubLabPostCreateRefReadDiagnostics = new WeakMap<
  object,
  GitHubRefReadDiagnostic
>();

export function hasValidatedGitHubLabPostCreateDiagnosticError(
  value: unknown,
): value is GitHubLabPostCreateDiagnosticError {
  return typeof value === "object" && value !== null &&
    githubLabPostCreateDiagnosticErrors.has(value);
}

export function getValidatedGitHubLabPostCreateRefReadDiagnostic(
  value: unknown,
): GitHubRefReadDiagnostic {
  return validateGitHubRefReadDiagnostic(
    typeof value === "object" && value !== null
      ? githubLabPostCreateRefReadDiagnostics.get(value)
      : undefined,
  );
}

const githubTokenAcquireDiagnostics = new WeakSet<object>();
const githubTokenLeaseDiagnostics = new WeakSet<object>();
const githubTokenResponseDiagnostics = new WeakSet<object>();

export class GitHubTokenAcquireDiagnosticError extends Error {
  readonly tokenLeaseCheck?: GitHubTokenLeaseCheck;
  declare readonly tokenResponseCheck?: GitHubTokenResponseCheck;

  constructor(
    message: string,
    readonly tokenAcquireSubphase?: GitHubTokenAcquireSubphase,
    tokenLeaseCheck?: GitHubTokenLeaseCheck,
    tokenResponseCheck?: GitHubTokenResponseCheck,
  ) {
    if (
      tokenAcquireSubphase !== undefined &&
      !GITHUB_TOKEN_ACQUIRE_SUBPHASES.includes(tokenAcquireSubphase)
    ) throw new Error("GITHUB_TOKEN_ACQUIRE_DIAGNOSTIC_INVALID");
    if (
      tokenLeaseCheck !== undefined &&
      (tokenAcquireSubphase !== "TOKEN_LEASE_VALIDATE" ||
        !GITHUB_TOKEN_LEASE_CHECKS.includes(tokenLeaseCheck))
    ) throw new Error("GITHUB_TOKEN_LEASE_DIAGNOSTIC_INVALID");
    if (
      tokenResponseCheck !== undefined &&
      (tokenAcquireSubphase !== "TOKEN_RESPONSE_SCHEMA" ||
        !GITHUB_TOKEN_RESPONSE_CHECKS.includes(tokenResponseCheck))
    ) throw new Error("GITHUB_TOKEN_RESPONSE_DIAGNOSTIC_INVALID");
    super(message);
    this.name = "GitHubTokenAcquireDiagnosticError";
    Object.defineProperty(this, "tokenAcquireSubphase", {
      value: tokenAcquireSubphase,
      enumerable: true,
      writable: false,
      configurable: false,
    });
    if (tokenLeaseCheck !== undefined) {
      Object.defineProperty(this, "tokenLeaseCheck", {
        value: tokenLeaseCheck,
        enumerable: true,
        writable: false,
        configurable: false,
      });
      githubTokenLeaseDiagnostics.add(this);
    }
    if (tokenResponseCheck !== undefined) {
      Object.defineProperty(this, "tokenResponseCheck", {
        value: tokenResponseCheck,
        enumerable: true,
        writable: false,
        configurable: false,
      });
      githubTokenResponseDiagnostics.add(this);
    }
    githubTokenAcquireDiagnostics.add(this);
  }
}

export function hasValidatedGitHubTokenAcquireDiagnostic(
  value: unknown,
): value is GitHubTokenAcquireDiagnosticError {
  return typeof value === "object" && value !== null &&
    githubTokenAcquireDiagnostics.has(value);
}

export function hasValidatedGitHubTokenLeaseCheck(
  value: GitHubTokenAcquireDiagnosticError,
): value is GitHubTokenAcquireDiagnosticError & {
  readonly tokenLeaseCheck: GitHubTokenLeaseCheck;
} {
  return githubTokenLeaseDiagnostics.has(value);
}

export function hasValidatedGitHubTokenResponseCheck(
  value: GitHubTokenAcquireDiagnosticError,
): value is GitHubTokenAcquireDiagnosticError & {
  readonly tokenResponseCheck: GitHubTokenResponseCheck;
} {
  return githubTokenResponseDiagnostics.has(value);
}

export class RepositoryProvisioningProviderDiagnosticError
  extends GitHubTokenAcquireDiagnosticError {
  constructor(
    readonly phase: RepositoryProvisioningProviderFailurePhase,
    readonly subphase?: RepositoryProviderSubphase,
    tokenAcquireSubphase?: GitHubTokenAcquireSubphase,
    tokenLeaseCheck?: GitHubTokenLeaseCheck,
    tokenResponseCheck?: GitHubTokenResponseCheck,
  ) {
    if (
      !REPOSITORY_PROVIDER_FAILURE_PHASES.includes(phase) ||
      subphase !== undefined &&
        (phase === "GITHUB_STARTER_SNAPSHOT_INVALID"
          ? !REPOSITORY_STARTER_READ_SUBPHASES.includes(
            subphase as RepositoryStarterReadSubphase,
          )
          : phase === "GITHUB_LAB_CREATE_FAILED"
          ? !GITHUB_LAB_DIRECT_FAILURE_SUBPHASES.includes(
            subphase as typeof GITHUB_LAB_DIRECT_FAILURE_SUBPHASES[number],
          )
          : phase === "GITHUB_LAB_RECONCILIATION_AMBIGUOUS"
          ? !GITHUB_LAB_UNCERTAIN_OUTCOME_SUBPHASES.includes(
            subphase as typeof GITHUB_LAB_UNCERTAIN_OUTCOME_SUBPHASES[number],
          )
          : phase === "GITHUB_LAB_POST_CREATE_FAILED"
          ? !GITHUB_LAB_POST_CREATE_SUBPHASES.includes(
            subphase as GitHubLabPostCreateSubphase,
          )
          : true) ||
      tokenAcquireSubphase !== undefined &&
        !(
          phase === "GITHUB_STARTER_SNAPSHOT_INVALID" &&
            subphase === "STARTER_TOKEN_ACQUIRE" ||
          phase === "GITHUB_LAB_CREATE_FAILED" &&
            subphase === "LAB_TOKEN_ACQUIRE"
        )
    ) {
      throw new Error("REPOSITORY_PROVISIONING_PROVIDER_DIAGNOSTIC_INVALID");
    }
    super(phase, tokenAcquireSubphase, tokenLeaseCheck, tokenResponseCheck);
    this.name = "RepositoryProvisioningProviderDiagnosticError";
    Object.defineProperties(this, {
      phase: {
        value: phase,
        enumerable: true,
        writable: false,
        configurable: false,
      },
      subphase: {
        value: subphase,
        enumerable: true,
        writable: false,
        configurable: false,
      },
    });
    if (
      subphase !== undefined &&
      (phase === "GITHUB_LAB_CREATE_FAILED" ||
        phase === "GITHUB_LAB_RECONCILIATION_AMBIGUOUS") &&
      GITHUB_LAB_CREATE_SUBPHASES.includes(
        subphase as GitHubLabCreateSubphase,
      )
    ) githubLabCreateDiagnostics.add(this);
    if (
      phase === "GITHUB_LAB_POST_CREATE_FAILED" &&
      subphase !== undefined &&
      GITHUB_LAB_POST_CREATE_SUBPHASES.includes(
        subphase as GitHubLabPostCreateSubphase,
      )
    ) githubLabPostCreateDiagnostics.add(this);
  }
}

export function hasValidatedGitHubLabCreateSubphase(
  value: RepositoryProvisioningProviderDiagnosticError,
): value is RepositoryProvisioningProviderDiagnosticError & {
  readonly subphase: GitHubLabCreateSubphase;
} {
  return githubLabCreateDiagnostics.has(value);
}

export function hasValidatedGitHubLabPostCreateSubphase(
  value: RepositoryProvisioningProviderDiagnosticError,
): value is RepositoryProvisioningProviderDiagnosticError & {
  readonly subphase: GitHubLabPostCreateSubphase;
} {
  return githubLabPostCreateDiagnostics.has(value);
}

export const REPOSITORY_RUNTIME_FAILURE_PHASES = [
  "INVALID_REPOSITORY_PROVISIONING_COMMAND_V2",
  "INVALID_REPOSITORY_PROVISIONING_CLAIM",
  "REPOSITORY_PROVISIONING_IN_PROGRESS",
  "INVALID_REPOSITORY_BINDING_V2",
  "REPOSITORY_PROVIDER_FAILED",
  "INVALID_REPOSITORY_PROVIDER_RESULT_V2",
  "REPOSITORY_BINDING_FAILED",
] as const;

export type RepositoryProvisioningRuntimeFailurePhase =
  (typeof REPOSITORY_RUNTIME_FAILURE_PHASES)[number];

export class RepositoryProvisioningRuntimeDiagnosticError extends Error {
  constructor(readonly phase: RepositoryProvisioningRuntimeFailurePhase) {
    if (!REPOSITORY_RUNTIME_FAILURE_PHASES.includes(phase)) {
      throw new Error("REPOSITORY_PROVISIONING_RUNTIME_DIAGNOSTIC_INVALID");
    }
    super(phase);
    this.name = "RepositoryProvisioningRuntimeDiagnosticError";
  }
}
