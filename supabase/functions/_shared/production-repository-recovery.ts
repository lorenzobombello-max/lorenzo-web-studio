import type { GitHubAppConfig } from "./github-app-config.ts";
import {
  GITHUB_TOKEN_EXCHANGE_HTTP_CLASSES,
  type GitHubInstallationTokenLease,
  type GitHubTokenAuthority,
  type GitHubTokenExchangeHttpClass,
  type GitHubTokenExchangeHttpStatus,
  type GitHubTokenRequest,
} from "./github-app-token.ts";
import {
  GitHubHttpError,
  type GitHubHttpOperation,
  type GitHubHttpResult,
  type GitHubRepositoryMetadata,
  type GitHubTreeEntry,
} from "./github-http.ts";
import {
  createProductionRepositoryCompletionProofCapability,
  createProductionRepositoryStateInspectionCapability,
  GitHubRepositoryStateInspectionError,
  type GitHubRepositoryCompletionProof,
  type GitHubRepositoryStateClassification,
  type GitHubRepositoryStateInspectionAuthority,
} from "./github-repository-state-inspector.ts";
import { computeGitHubSnapshotDigest } from "./github-snapshot-digest.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const NUMERIC_ID = /^[1-9][0-9]{0,15}$/;
const NODE_ID = /^[A-Za-z0-9_-]{6,255}$/;
const SHA = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const SHA256 = /^[0-9a-f]{64}$/;
const AUTHORITY_KEYS = [
  "operation_id",
  "website_work_context_id",
  "website_workspace_id",
  "repository_external_id",
  "repository_node_id",
  "repository_owner",
  "repository_name",
  "starter_source",
  "starter_version",
  "starter_commit_sha",
] as const;

export type ProductionRepositoryRecoveryInput = Readonly<{
  quoteRequestId: string;
  websiteWorkContextId: string;
  websiteWorkspaceId: string;
}>;

type Authority = Readonly<{
  operationId: string;
  websiteWorkContextId: string;
  websiteWorkspaceId: string;
  repositoryId: string;
  repositoryNodeId: string;
  owner: string;
  repository: string;
  starterSource: string;
  starterVersion: string;
  starterCommitSha: string;
  markerContent: string;
}>;

type RecoveryHttpOperation = Extract<GitHubHttpOperation, {
  kind:
    | "REPOSITORY_METADATA"
    | "REPOSITORY_EMPTY_PROOF"
    | "REPOSITORY_TREE"
    | "READ_BLOB"
    | "CREATE_BLOB"
    | "CREATE_TREE"
    | "CREATE_COMMIT"
    | "CREATE_BOOTSTRAP_FILE"
    | "READ_REF"
    | "UPDATE_REF"
    | "WRITE_PROJECT_MARKER"
    | "READ_PROJECT_MARKER"
    | "COMMIT_METADATA"
    | "READ_COMMIT";
}>;

type RpcResult = Readonly<{ data: unknown; error: unknown }>;
type Dependencies = Readonly<{
  config: GitHubAppConfig;
  actor: Readonly<{ authUserId: string; aal: "aal2" }>;
  callerRpc(name: string, parameters: Readonly<Record<string, unknown>>): PromiseLike<RpcResult>;
  serviceRpc(name: string, parameters: Readonly<Record<string, unknown>>): PromiseLike<RpcResult>;
  tokenBroker: Readonly<{
    issue(
      config: GitHubAppConfig,
      request: GitHubTokenRequest,
      authority: GitHubTokenAuthority,
    ): Promise<GitHubInstallationTokenLease>;
  }>;
  http: Readonly<{
    execute(operation: RecoveryHttpOperation): Promise<GitHubHttpResult>;
  }>;
}>;

type SnapshotEntry = Readonly<{
  path: string;
  mode: string;
  type: "blob";
  content: Uint8Array;
}>;

export type ProductionRepositoryRecoveryResult = Readonly<{
  status: "ALREADY_COMPLETE" | "RECOVERED_FROM_EMPTY" | "RECOVERED_MARKER_ONLY";
  operationId: string;
  binding: unknown;
}>;

// Safe, machine-readable recovery failure stages. These are the ONLY values
// that may ever reach the HTTP response or a server log for a recovery
// failure; the underlying exception (which may carry provider/database
// detail) is never surfaced past `guard`.
export type ProductionRepositoryRecoveryStage =
  | "CONFIG_LOAD"
  | "AUTHORITY_RPC"
  | "AUTHORITY_VALIDATE"
  | "REPOSITORY_INSPECT"
  | "TARGET_TOKEN_ACQUIRE"
  | "STARTER_TOKEN_ACQUIRE"
  | "STARTER_SNAPSHOT_READ"
  | "EMPTY_REPOSITORY_INITIALIZE"
  | "MARKER_WRITE"
  | "COMPLETION_PROOF"
  | "FINALIZE_RPC"
  | "RESPONSE_VALIDATE";

const STAGE_DIAGNOSTIC_CODES: Readonly<Record<ProductionRepositoryRecoveryStage, string>> = Object.freeze({
  CONFIG_LOAD: "PRODUCTION_REPOSITORY_RECOVERY_CONFIG_FAILED",
  AUTHORITY_RPC: "PRODUCTION_REPOSITORY_RECOVERY_AUTHORITY_FAILED",
  AUTHORITY_VALIDATE: "PRODUCTION_REPOSITORY_RECOVERY_AUTHORITY_INVALID",
  REPOSITORY_INSPECT: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_FAILED",
  TARGET_TOKEN_ACQUIRE: "PRODUCTION_REPOSITORY_RECOVERY_TARGET_TOKEN_FAILED",
  STARTER_TOKEN_ACQUIRE: "PRODUCTION_REPOSITORY_RECOVERY_STARTER_TOKEN_FAILED",
  STARTER_SNAPSHOT_READ: "PRODUCTION_REPOSITORY_RECOVERY_SNAPSHOT_FAILED",
  EMPTY_REPOSITORY_INITIALIZE: "PRODUCTION_REPOSITORY_RECOVERY_INITIALIZE_FAILED",
  MARKER_WRITE: "PRODUCTION_REPOSITORY_RECOVERY_MARKER_FAILED",
  COMPLETION_PROOF: "PRODUCTION_REPOSITORY_RECOVERY_PROOF_FAILED",
  FINALIZE_RPC: "PRODUCTION_REPOSITORY_RECOVERY_FINALIZE_FAILED",
  RESPONSE_VALIDATE: "PRODUCTION_REPOSITORY_RECOVERY_RESPONSE_INVALID",
});

// REPOSITORY_INSPECT is a single guard() boundary wrapping several distinct
// GitHub read substeps (token acquire, metadata read, ref read, snapshot
// read, marker read). Without this map every one of those failures
// collapsed into one generic code, making the exact failing substep
// unprovable from the safe diagnostic alone. Each value here is itself a
// pre-approved, whitelisted, safe machine-readable code (no raw provider
// detail) -- this only narrows WHICH known substep failed.
const REPOSITORY_INSPECT_SUBSTEP_DIAGNOSTIC_CODES = Object.freeze({
  TOKEN_ACQUIRE: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_FAILED",
  TOKEN_AUTHORITY_FAILED: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_AUTHORITY_FAILED",
  TOKEN_SIGNING_FAILED: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_SIGNING_FAILED",
  TOKEN_EXCHANGE_FAILED: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_FAILED",
  TOKEN_EXCHANGE_REQUEST_PREPARE_FAILED: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_REQUEST_PREPARE_FAILED",
  TOKEN_EXCHANGE_HTTP_REQUEST_FAILED: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_HTTP_REQUEST_FAILED",
  TOKEN_EXCHANGE_HTTP_STATUS_FAILED: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_HTTP_STATUS_FAILED",
  TOKEN_EXCHANGE_CONTENT_TYPE_FAILED: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_CONTENT_TYPE_FAILED",
  TOKEN_EXCHANGE_BODY_READ_FAILED: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_BODY_READ_FAILED",
  TOKEN_EXCHANGE_JSON_PARSE_FAILED: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_JSON_PARSE_FAILED",
  TOKEN_EXCHANGE_RESPONSE_SCHEMA_FAILED: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_RESPONSE_SCHEMA_FAILED",
  TOKEN_EXCHANGE_ADAPTER_FAILED: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_EXCHANGE_ADAPTER_FAILED",
  TOKEN_FORBIDDEN: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_FORBIDDEN",
  TOKEN_RESPONSE_INVALID: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_TOKEN_RESPONSE_INVALID",
  METADATA_READ: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_METADATA_FAILED",
  REF_READ: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_REF_READ_FAILED",
  SNAPSHOT_READ: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_SNAPSHOT_FAILED",
  MARKER_READ: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_MARKER_FAILED",
  IDENTITY_MISMATCH: "PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_IDENTITY_MISMATCH",
});
type RepositoryInspectSubstep = keyof typeof REPOSITORY_INSPECT_SUBSTEP_DIAGNOSTIC_CODES;

// Thrown ONLY with a pre-approved, whitelisted diagnostic code (see
// STAGE_DIAGNOSTIC_CODES / REPOSITORY_INSPECT_SUBSTEP_DIAGNOSTIC_CODES
// above). The original underlying error (which may be a raw GitHubHttpError,
// a network failure, or an RPC error carrying provider/database detail) is
// intentionally discarded by `guard` and never attached to this error, so
// this class can never leak sensitive detail.
export class ProductionRepositoryRecoveryStageError extends Error {
  readonly stage: ProductionRepositoryRecoveryStage;
  // Carries only the already-safe, already-whitelisted GitHub HTTP status
  // class (e.g. a 4xx/5xx bucket) for a token-exchange HTTP-status failure --
  // never the raw provider status, body, or headers. Populated only from an
  // upstream GitHubRepositoryStateInspectionError's own validated field, so
  // this class still never receives or stores unvalidated/raw error detail.
  readonly tokenExchangeHttpClass?: GitHubTokenExchangeHttpClass;
  // The exact numeric GitHub HTTP status, but ONLY ever 409 or 422 and ONLY
  // ever alongside tokenExchangeHttpClass === "GITHUB_HTTP_CONFLICT" -- every
  // other status stays fully described by the class alone.
  readonly tokenExchangeHttpStatus?: GitHubTokenExchangeHttpStatus;
  constructor(
    stage: ProductionRepositoryRecoveryStage,
    inspectSubstep?: RepositoryInspectSubstep,
    tokenExchangeHttpClass?: GitHubTokenExchangeHttpClass,
    tokenExchangeHttpStatus?: GitHubTokenExchangeHttpStatus,
  ) {
    if (inspectSubstep !== undefined && stage !== "REPOSITORY_INSPECT") {
      throw new Error("PRODUCTION_REPOSITORY_RECOVERY_STAGE_ERROR_INVALID");
    }
    if (
      tokenExchangeHttpClass !== undefined &&
      (inspectSubstep !== "TOKEN_EXCHANGE_HTTP_STATUS_FAILED" ||
        !GITHUB_TOKEN_EXCHANGE_HTTP_CLASSES.includes(tokenExchangeHttpClass))
    ) {
      throw new Error("PRODUCTION_REPOSITORY_RECOVERY_STAGE_ERROR_INVALID");
    }
    if (
      tokenExchangeHttpStatus !== undefined &&
      (tokenExchangeHttpClass !== "GITHUB_HTTP_CONFLICT" ||
        (tokenExchangeHttpStatus !== 409 && tokenExchangeHttpStatus !== 422))
    ) {
      throw new Error("PRODUCTION_REPOSITORY_RECOVERY_STAGE_ERROR_INVALID");
    }
    super(
      inspectSubstep !== undefined
        ? REPOSITORY_INSPECT_SUBSTEP_DIAGNOSTIC_CODES[inspectSubstep]
        : STAGE_DIAGNOSTIC_CODES[stage],
    );
    this.name = "ProductionRepositoryRecoveryStageError";
    this.stage = stage;
    this.tokenExchangeHttpClass = tokenExchangeHttpClass;
    this.tokenExchangeHttpStatus = tokenExchangeHttpStatus;
  }
}

// Classifies a REPOSITORY_INSPECT failure into one of the known, safe
// substep codes above using only the already-safe, already-sanitized
// diagnostic surface exported by the inspector module (never the raw
// error/provider payload). Returns undefined for anything unrecognized, so
// `guard` falls back to the generic PRODUCTION_REPOSITORY_RECOVERY_INSPECTION_FAILED
// code and still fails closed.
function classifyRepositoryInspectionFailure(error: unknown): RepositoryInspectSubstep | undefined {
  if (!(error instanceof GitHubRepositoryStateInspectionError)) return undefined;
  if (error.code === "REPOSITORY_IDENTITY_MISMATCH") return "IDENTITY_MISMATCH";
  switch (error.postCreateSubphase) {
    case "LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE":
      switch (error.tokenBrokerCode) {
        case "GITHUB_TOKEN_AUTHORITY_INVALID":
          return "TOKEN_AUTHORITY_FAILED";
        case "GITHUB_APP_SIGNING_FAILED":
          return "TOKEN_SIGNING_FAILED";
        case "GITHUB_TOKEN_EXCHANGE_FAILED":
        case "GITHUB_TOKEN_TIMEOUT":
        case "GITHUB_TOKEN_RATE_LIMITED":
        case "GITHUB_TOKEN_REDIRECT_DENIED":
          switch (error.tokenAcquireSubphase) {
            case "TOKEN_REQUEST_PREPARE":
              return "TOKEN_EXCHANGE_REQUEST_PREPARE_FAILED";
            case "TOKEN_HTTP_REQUEST":
              return "TOKEN_EXCHANGE_HTTP_REQUEST_FAILED";
            case "TOKEN_HTTP_STATUS":
              return "TOKEN_EXCHANGE_HTTP_STATUS_FAILED";
            case "TOKEN_CONTENT_TYPE_VALIDATE":
              return "TOKEN_EXCHANGE_CONTENT_TYPE_FAILED";
            case "TOKEN_RESPONSE_BODY_READ":
              return "TOKEN_EXCHANGE_BODY_READ_FAILED";
            case "TOKEN_JSON_PARSE":
              return "TOKEN_EXCHANGE_JSON_PARSE_FAILED";
            case "TOKEN_RESPONSE_SCHEMA":
              return "TOKEN_EXCHANGE_RESPONSE_SCHEMA_FAILED";
            case "TOKEN_ADAPTER_PROJECT":
              return "TOKEN_EXCHANGE_ADAPTER_FAILED";
            default:
              return "TOKEN_EXCHANGE_FAILED";
          }
        case "GITHUB_TOKEN_FORBIDDEN":
          return "TOKEN_FORBIDDEN";
        case "GITHUB_TOKEN_RESPONSE_INVALID":
          return "TOKEN_RESPONSE_INVALID";
        default:
          return "TOKEN_ACQUIRE";
      }
    case "LAB_POST_CREATE_METADATA_READ":
      return "METADATA_READ";
    case "LAB_POST_CREATE_SNAPSHOT_READBACK":
      return error.snapshotReadbackCheck === "REF_READ" ? "REF_READ" : "SNAPSHOT_READ";
    case "LAB_POST_CREATE_PROVENANCE_VALIDATE":
      return "SNAPSHOT_READ";
    case "LAB_POST_CREATE_MARKER_READBACK":
      return "MARKER_READ";
    default:
      return undefined;
  }
}

// Extracts the already-safe, already-whitelisted GitHub token-exchange HTTP
// status class from a repository-inspection failure, but only for the exact
// substep it applies to (TOKEN_EXCHANGE_HTTP_STATUS_FAILED). Returns
// undefined for every other substep/error shape, so absence is always
// handled the same safe way as before this field existed.
function classifyRepositoryInspectionTokenExchangeHttpClass(
  error: unknown,
  substep: RepositoryInspectSubstep | undefined,
): GitHubTokenExchangeHttpClass | undefined {
  if (substep !== "TOKEN_EXCHANGE_HTTP_STATUS_FAILED") return undefined;
  if (!(error instanceof GitHubRepositoryStateInspectionError)) return undefined;
  return error.tokenExchangeHttpClass;
}

// Extracts the already-safe, already-validated exact numeric GitHub HTTP
// status (409 or 422 only) from a repository-inspection failure. Only ever
// meaningful alongside the GITHUB_HTTP_CONFLICT class; every other class
// (401/403/404/429/5xx/...) is already fully described by the class alone
// and must never gain a fabricated numeric status here.
function classifyRepositoryInspectionTokenExchangeHttpStatus(
  error: unknown,
  substep: RepositoryInspectSubstep | undefined,
  httpClass: GitHubTokenExchangeHttpClass | undefined,
): GitHubTokenExchangeHttpStatus | undefined {
  if (substep !== "TOKEN_EXCHANGE_HTTP_STATUS_FAILED") return undefined;
  if (httpClass !== "GITHUB_HTTP_CONFLICT") return undefined;
  if (!(error instanceof GitHubRepositoryStateInspectionError)) return undefined;
  return error.tokenExchangeHttpStatus;
}

// Returns the safe diagnostic code for a recovery failure, or null if the
// error did not originate from the recovery stage machinery below (in which
// case callers must continue to fail closed to a generic error code).
export function productionRepositoryRecoveryDiagnosticCode(error: unknown): string | null {
  return error instanceof ProductionRepositoryRecoveryStageError ? error.message : null;
}

// Runs `run` and, on any failure, reclassifies it as a stage-tagged,
// pre-approved diagnostic error. Already stage-tagged errors (thrown by a
// more specific inner `guard`) pass through unchanged so the most precise
// stage is always preserved. This is the single choke point that prevents
// raw provider/database error detail from ever escaping this module.
async function guard<T>(
  stage: ProductionRepositoryRecoveryStage,
  run: () => T | Promise<T>,
): Promise<T> {
  try {
    return await run();
  } catch (error) {
    if (error instanceof ProductionRepositoryRecoveryStageError) throw error;
    throw new ProductionRepositoryRecoveryStageError(stage);
  }
}

// Safe, sanitized failure log record for server-side observability only.
// Contains no JWTs, tokens, Authorization headers, private key material, or
// raw provider/database payloads -- only the pre-approved stage and code,
// plus (only when present) the already-safe, already-whitelisted GitHub
// token-exchange HTTP status class for the one substep it applies to, and
// (only for the GITHUB_HTTP_CONFLICT class) the exact already-validated
// numeric status (409 or 422 only -- never any other value).
export function productionRepositoryRecoveryFailureLog(
  error: unknown,
): Readonly<Record<string, string>> {
  if (!(error instanceof ProductionRepositoryRecoveryStageError)) {
    return Object.freeze({
      event: "LWS_GIT001_RECOVERY_FAILURE",
      action: "recover_existing_website_repository",
      stage: "UNKNOWN",
      diagnostic_code: "UNCLASSIFIED",
    });
  }
  return Object.freeze({
    event: "LWS_GIT001_RECOVERY_FAILURE",
    action: "recover_existing_website_repository",
    stage: error.stage,
    diagnostic_code: error.message,
    ...(error.tokenExchangeHttpClass !== undefined
      ? { token_exchange_http_class: error.tokenExchangeHttpClass }
      : {}),
    ...(error.tokenExchangeHttpStatus !== undefined
      ? { token_exchange_http_status: String(error.tokenExchangeHttpStatus) }
      : {}),
  });
}

// Wraps the full recovery action (including the pre-flight config/signer
// setup performed by the caller before `recover()` is invoked) so that any
// failure -- classified or not -- is safely logged server-side before being
// re-thrown unchanged to the caller.
export async function withProductionRepositoryRecoveryFailureLogging<T>(
  action: () => Promise<T>,
  logger: (entry: string) => void = (entry) => console.error(entry),
): Promise<T> {
  try {
    return await action();
  } catch (error) {
    logger(JSON.stringify(productionRepositoryRecoveryFailureLog(error)));
    throw error;
  }
}

// Exposed so `executeCallerJwtWebsiteRepositoryRecoveryAction` can classify
// its own pre-flight (CONFIG_LOAD) failures using the same stage machinery.
export { guard as guardProductionRepositoryRecoveryStage };

function fail(): never {
  throw new Error("PRODUCTION_REPOSITORY_RECOVERY_FAILED");
}

function exactRecord(
  value: unknown,
  keys: readonly string[],
): value is Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  const actual = Reflect.ownKeys(value).sort();
  const expected = [...keys].sort();
  const descriptors = Object.getOwnPropertyDescriptors(value);
  return (prototype === Object.prototype || prototype === null) &&
    actual.length === expected.length &&
    actual.every((key, index) => key === expected[index]) &&
    keys.every((key) =>
      descriptors[key]?.enumerable === true &&
      Object.hasOwn(descriptors[key], "value")
    );
}

function base64(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function bytes(value: string): Uint8Array {
  return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
}

function sha(value: unknown): string {
  if (!exactRecord(value, ["sha"]) || !SHA.test(String(value.sha))) fail();
  return String(value.sha);
}

function markerContent(config: GitHubAppConfig, authority: Omit<Authority, "markerContent">): string {
  return `${JSON.stringify({
    schema_version: 1,
    environment: "PRODUCTION",
    organization: authority.owner,
    website_work_context_id: authority.websiteWorkContextId,
    repository_provisioning_operation_id: authority.operationId,
    starter_source: authority.starterSource,
    starter_version: `v${authority.starterVersion}`,
    starter_commit_sha: authority.starterCommitSha,
    starter_tree_sha256: config.starterTreeSha256,
  }, null, 2)}\n`;
}

function projectAuthority(
  value: unknown,
  input: ProductionRepositoryRecoveryInput,
  config: GitHubAppConfig,
): Authority {
  if (
    !exactRecord(value, AUTHORITY_KEYS) ||
    value.website_work_context_id !== input.websiteWorkContextId ||
    value.website_workspace_id !== input.websiteWorkspaceId ||
    typeof value.operation_id !== "string" || !UUID.test(value.operation_id) ||
    typeof value.repository_external_id !== "string" ||
    !NUMERIC_ID.test(value.repository_external_id) ||
    typeof value.repository_node_id !== "string" ||
    !NODE_ID.test(value.repository_node_id) ||
    value.repository_owner !== config.organization ||
    value.repository_name !==
      `lws-web-${input.websiteWorkContextId.toLowerCase().replaceAll("-", "")}` ||
    value.starter_source !== `${config.templateOwner}/${config.templateName}` ||
    value.starter_version !== config.starterVersion ||
    value.starter_commit_sha !== config.starterCommitSha ||
    !SHA.test(String(value.starter_commit_sha)) ||
    !SHA256.test(config.starterTreeSha256)
  ) fail();
  const authority = Object.freeze({
    operationId: value.operation_id,
    websiteWorkContextId: value.website_work_context_id,
    websiteWorkspaceId: value.website_workspace_id,
    repositoryId: value.repository_external_id,
    repositoryNodeId: value.repository_node_id,
    owner: value.repository_owner,
    repository: value.repository_name,
    starterSource: value.starter_source,
    starterVersion: value.starter_version,
    starterCommitSha: value.starter_commit_sha,
  } as Omit<Authority, "markerContent">);
  return Object.freeze({
    ...authority,
    markerContent: markerContent(config, authority),
  });
}

function inspectionAuthority(
  config: GitHubAppConfig,
  authority: Authority,
): GitHubRepositoryStateInspectionAuthority {
  return Object.freeze({
    websiteWorkContextId: authority.websiteWorkContextId,
    repositoryId: authority.repositoryId,
    owner: authority.owner,
    repository: authority.repository,
    private: true,
    defaultBranch: "main",
    snapshotTreeSha256: config.starterTreeSha256,
    markerContent: authority.markerContent,
  });
}

async function issue(
  dependencies: Dependencies,
  authority: Authority,
  operation: "STARTER_SNAPSHOT_READ" | "PRODUCTION_REPOSITORY_WRITE",
  repositoryId: string,
): Promise<string> {
  const request = Object.freeze({
    websiteWorkContextId: authority.websiteWorkContextId,
    target: "PRODUCTION" as const,
    organization: dependencies.config.organization,
    operation,
    repositoryIds: Object.freeze([repositoryId]),
  });
  const lease = await dependencies.tokenBroker.issue(
    dependencies.config,
    request,
    Object.freeze({
      websiteWorkContextId: request.websiteWorkContextId,
      target: request.target,
      organization: request.organization,
      repositoryIds: request.repositoryIds,
    }),
  );
  if (!lease || typeof lease.token !== "string") fail();
  return lease.token;
}

async function prepareSnapshot(
  dependencies: Dependencies,
  authority: Authority,
): Promise<readonly SnapshotEntry[]> {
  const config = dependencies.config;
  const token = await guard("STARTER_TOKEN_ACQUIRE", () =>
    issue(
      dependencies,
      authority,
      "STARTER_SNAPSHOT_READ",
      config.templateRepositoryId,
    ));
  return await guard("STARTER_SNAPSHOT_READ", async () => {
    const metadata = await dependencies.http.execute({
      kind: "REPOSITORY_METADATA",
      owner: config.templateOwner,
      repository: config.templateName,
      token,
    }) as GitHubRepositoryMetadata;
    if (
      metadata.repositoryId !== config.templateRepositoryId ||
      metadata.owner !== config.templateOwner || metadata.name !== config.templateName
    ) fail();
    const tree = await dependencies.http.execute({
      kind: "REPOSITORY_TREE",
      owner: config.templateOwner,
      repository: config.templateName,
      treeRef: authority.starterCommitSha,
      token,
    }) as Readonly<{ sha: string; truncated: false; entries: readonly GitHubTreeEntry[] }>;
    if (!tree || tree.truncated !== false || !Array.isArray(tree.entries)) fail();
    const entries: SnapshotEntry[] = [];
    for (const entry of tree.entries) {
      if (entry.type === "tree") continue;
      if (entry.type !== "blob") fail();
      const blob = await dependencies.http.execute({
        kind: "READ_BLOB",
        owner: config.templateOwner,
        repository: config.templateName,
        blobSha: entry.sha,
        token,
      }) as Readonly<{ sha: string; encoding: "base64"; contentBase64: string; size: number }>;
      const content = bytes(blob.contentBase64);
      if (blob.sha !== entry.sha || blob.encoding !== "base64" || content.byteLength !== blob.size) fail();
      entries.push(Object.freeze({
        path: entry.path,
        mode: entry.mode,
        type: "blob" as const,
        content,
      }));
    }
    if (await computeGitHubSnapshotDigest(entries) !== config.starterTreeSha256) fail();
    return Object.freeze(entries);
  });
}

async function confirmTarget(
  dependencies: Dependencies,
  authority: Authority,
  token: string,
): Promise<void> {
  await guard("TARGET_TOKEN_ACQUIRE", async () => {
    const metadata = await dependencies.http.execute({
      kind: "REPOSITORY_METADATA",
      owner: authority.owner,
      repository: authority.repository,
      token,
    }) as GitHubRepositoryMetadata;
    if (
      metadata.repositoryId !== authority.repositoryId ||
      metadata.nodeId !== authority.repositoryNodeId ||
      metadata.owner !== authority.owner || metadata.name !== authority.repository ||
      metadata.fullName !== `${authority.owner}/${authority.repository}` ||
      metadata.private !== true || metadata.defaultBranch !== "main"
    ) fail();
  });
}

function conflict(error: unknown): boolean {
  return error instanceof GitHubHttpError && error.code === "GITHUB_HTTP_CONFLICT";
}

async function writeMarker(
  dependencies: Dependencies,
  authority: Authority,
  token: string,
): Promise<void> {
  try {
    const result: unknown = await dependencies.http.execute({
      kind: "WRITE_PROJECT_MARKER",
      owner: authority.owner,
      repository: authority.repository,
      message: "chore: bind project context",
      contentBase64: base64(new TextEncoder().encode(authority.markerContent)),
      token,
    });
    if (!exactRecord(result, ["contentSha", "commitSha"]) ||
      !SHA.test(String(result.contentSha)) || !SHA.test(String(result.commitSha))) fail();
  } catch (error) {
    if (!conflict(error)) throw error;
  }
}

async function initializeEmptyRepository(
  dependencies: Dependencies,
  authority: Authority,
): Promise<void> {
  const token = await guard("TARGET_TOKEN_ACQUIRE", () =>
    issue(
      dependencies,
      authority,
      "PRODUCTION_REPOSITORY_WRITE",
      authority.repositoryId,
    ));
  await confirmTarget(dependencies, authority, token);
  const entries = await prepareSnapshot(dependencies, authority);
  await guard("EMPTY_REPOSITORY_INITIALIZE", async () => {
    const bootstrap = `${JSON.stringify({
      schema_version: 1,
      purpose: "PRODUCTION_EXISTING_REPOSITORY_RECOVERY",
      environment: "PRODUCTION",
      organization: authority.owner,
      repository: authority.repository,
      repository_id: authority.repositoryId,
      website_work_context_id: authority.websiteWorkContextId,
      website_workspace_id: authority.websiteWorkspaceId,
      repository_provisioning_operation_id: authority.operationId,
    }, null, 2)}\n`;
    const created: unknown = await dependencies.http.execute({
      kind: "CREATE_BOOTSTRAP_FILE",
      owner: authority.owner,
      repository: authority.repository,
      contentBase64: base64(new TextEncoder().encode(bootstrap)),
      branch: "main",
      token,
    });
    if (!exactRecord(created, ["path", "contentSha", "commitSha", "parentCount"]) ||
      created.path !== ".lws/bootstrap.json" || !SHA.test(String(created.commitSha)) ||
      created.parentCount !== 0) fail();

    const treeEntries: Array<Readonly<{ path: string; mode: string; type: "blob"; sha: string }>> = [];
    for (const entry of entries) {
      treeEntries.push(Object.freeze({
        path: entry.path,
        mode: entry.mode,
        type: "blob",
        sha: sha(await dependencies.http.execute({
          kind: "CREATE_BLOB",
          owner: authority.owner,
          repository: authority.repository,
          contentBase64: base64(entry.content),
          token,
        })),
      }));
    }
    const treeSha = sha(await dependencies.http.execute({
      kind: "CREATE_TREE",
      owner: authority.owner,
      repository: authority.repository,
      entries: Object.freeze(treeEntries),
      token,
    }));
    const commitSha = sha(await dependencies.http.execute({
      kind: "CREATE_COMMIT",
      owner: authority.owner,
      repository: authority.repository,
      message: "chore: initialize approved starter snapshot",
      treeSha,
      parentSha: String(created.commitSha),
      token,
    }));
    const ref: unknown = await dependencies.http.execute({
      kind: "UPDATE_REF",
      owner: authority.owner,
      repository: authority.repository,
      commitSha,
      force: false,
      token,
    });
    if (!exactRecord(ref, ["ref", "commitSha"]) || ref.ref !== "refs/heads/main" || ref.commitSha !== commitSha) fail();
  });
  await guard("MARKER_WRITE", () => writeMarker(dependencies, authority, token));
}

async function completeMarker(
  dependencies: Dependencies,
  authority: Authority,
): Promise<void> {
  const token = await guard("TARGET_TOKEN_ACQUIRE", () =>
    issue(
      dependencies,
      authority,
      "PRODUCTION_REPOSITORY_WRITE",
      authority.repositoryId,
    ));
  await confirmTarget(dependencies, authority, token);
  await guard("MARKER_WRITE", () => writeMarker(dependencies, authority, token));
}

function verification(authority: Authority, proof: GitHubRepositoryCompletionProof) {
  if (
    proof.providerRepositoryId !== authority.repositoryId ||
    proof.providerNodeId !== authority.repositoryNodeId ||
    proof.owner !== authority.owner || proof.name !== authority.repository ||
    proof.visibility !== "PRIVATE" || proof.defaultBranch !== "main" ||
    !SHA.test(proof.repositoryMarkerCommitSha)
  ) fail();
  return Object.freeze({
    operation_id: authority.operationId,
    website_workspace_id: authority.websiteWorkspaceId,
    website_work_context_id: authority.websiteWorkContextId,
    repository_external_id: proof.providerRepositoryId,
    repository_node_id: proof.providerNodeId,
    repository_owner: proof.owner,
    repository_name: proof.name,
    repository_visibility: "private",
    default_branch: proof.defaultBranch,
    starter_source: authority.starterSource,
    starter_version: authority.starterVersion,
    starter_commit_sha: authority.starterCommitSha,
    repository_marker_commit_sha: proof.repositoryMarkerCommitSha,
  });
}

export function createProductionRepositoryRecovery(dependencies: Dependencies) {
  if (
    !dependencies || dependencies.config?.target !== "PRODUCTION" ||
    dependencies.config.organization !== "lorenzo-web-solutions" ||
    !UUID.test(dependencies.actor?.authUserId) || dependencies.actor.aal !== "aal2" ||
    typeof dependencies.callerRpc !== "function" ||
    typeof dependencies.serviceRpc !== "function" ||
    typeof dependencies.tokenBroker?.issue !== "function" ||
    typeof dependencies.http?.execute !== "function"
  ) fail();

  return Object.freeze({
    async recover(input: ProductionRepositoryRecoveryInput): Promise<ProductionRepositoryRecoveryResult> {
      if (!input || !UUID.test(input.quoteRequestId) ||
        !UUID.test(input.websiteWorkContextId) || !UUID.test(input.websiteWorkspaceId)) fail();
      const authorityData = await guard("AUTHORITY_RPC", async () => {
        const authorityResult = await dependencies.callerRpc(
          "get_production_website_repository_recovery_authority_v1",
          Object.freeze({
            p_quote_request_id: input.quoteRequestId,
            p_website_work_context_id: input.websiteWorkContextId,
            p_website_workspace_id: input.websiteWorkspaceId,
          }),
        );
        if (!authorityResult || authorityResult.error) fail();
        return authorityResult.data;
      });
      const authority = await guard("AUTHORITY_VALIDATE", () =>
        projectAuthority(authorityData, input, dependencies.config));
      const expected = inspectionAuthority(dependencies.config, authority);
      const inspect = createProductionRepositoryStateInspectionCapability(
        dependencies.config,
        expected,
        { tokenBroker: dependencies.tokenBroker, http: dependencies.http },
      );
      const initial = await guard("REPOSITORY_INSPECT", async () => {
        try {
          const result = await inspect();
          if (result.state === "CONFLICT") fail();
          return result;
        } catch (error) {
          if (error instanceof ProductionRepositoryRecoveryStageError) throw error;
          const substep = classifyRepositoryInspectionFailure(error);
          const httpClass = classifyRepositoryInspectionTokenExchangeHttpClass(error, substep);
          throw new ProductionRepositoryRecoveryStageError(
            "REPOSITORY_INSPECT",
            substep,
            httpClass,
            classifyRepositoryInspectionTokenExchangeHttpStatus(error, substep, httpClass),
          );
        }
      });
      let status: ProductionRepositoryRecoveryResult["status"];
      if (initial.state === "EMPTY_OR_UNINITIALIZED") {
        await initializeEmptyRepository(dependencies, authority);
        status = "RECOVERED_FROM_EMPTY";
      } else if (initial.state === "MARKER_MISSING") {
        await completeMarker(dependencies, authority);
        status = "RECOVERED_MARKER_ONLY";
      } else if (initial.state === "ALREADY_COMPLETE") {
        status = "ALREADY_COMPLETE";
      } else {
        const exhaustive: never = initial.state as never;
        return exhaustive;
      }
      const prove = createProductionRepositoryCompletionProofCapability(
        dependencies.config,
        expected,
        { tokenBroker: dependencies.tokenBroker, http: dependencies.http },
      );
      const completed = await guard("COMPLETION_PROOF", async () => {
        const result = await prove();
        if (!result || result.state !== "ALREADY_COMPLETE") fail();
        return result;
      });
      const verified = await guard("COMPLETION_PROOF", () => verification(authority, completed.proof));
      const finalized = await guard("FINALIZE_RPC", async () => {
        const result = await dependencies.serviceRpc(
          "finalize_production_website_repository_recovery_v1",
          Object.freeze({
            p_quote_request_id: input.quoteRequestId,
            p_operation_id: authority.operationId,
            p_verification: verified,
            p_actor_auth_user_id: dependencies.actor.authUserId,
            p_actor_aal: dependencies.actor.aal,
          }),
        );
        if (!result || result.error) fail();
        return result;
      });
      return Object.freeze({
        status,
        operationId: authority.operationId,
        binding: finalized.data,
      });
    },
  });
}

export type ProductionRecoveryRepositoryState = GitHubRepositoryStateClassification;