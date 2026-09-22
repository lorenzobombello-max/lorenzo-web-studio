import type { GitHubAppConfig } from "./github-app-config.ts";
import {
  GITHUB_TOKEN_BROKER_CODES,
  GITHUB_TOKEN_EXCHANGE_HTTP_CLASSES,
  type GitHubInstallationTokenLease,
  type GitHubTokenAuthority,
  type GitHubTokenRequest,
} from "./github-app-token.ts";
import {
  getValidatedGitHubHttpStatus,
  GitHubHttpError,
  type GitHubHttpOperation,
  type GitHubHttpResult,
} from "./github-http.ts";
import {
  GITHUB_TOKEN_ACQUIRE_SUBPHASES,
  hasValidatedGitHubTokenAcquireDiagnostic,
  hasValidatedGitHubTokenLeaseCheck,
  hasValidatedGitHubTokenResponseCheck,
} from "./repository-provisioning-diagnostics.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const OWNER = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/;
const REPOSITORY = /^[A-Za-z0-9._-]{1,100}$/;
const NODE_ID = /^[A-Za-z0-9_=-]{1,128}$/;
const SHA = /^[0-9a-f]{40}$/;
const REF =
  /^(?:heads|tags)\/[A-Za-z0-9](?:[A-Za-z0-9._\/-]{0,253}[A-Za-z0-9])?$/;
const TOKEN = /^(?:ghs_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{20,})$/;
const MAX_FILE_BYTES = 1_048_576;

export type WebsiteProjectFilesAuthority = Readonly<{
  leaseId: string;
  actorAuthUserId: string;
  quoteRequestId: string;
  websiteWorkContextId: string;
  websiteWorkspaceId: string;
  bindingRevision: number;
  repositoryProvider: "GITHUB";
  repositoryOwner: string;
  repositoryName: string;
  repositoryExternalId: string;
  repositoryNodeId: string;
  defaultBranch: string;
  repositoryRef: string;
  refLabel: string;
  markerOperationId: string;
  expiresAt: string;
}>;

export type ProviderTreeEntry = Readonly<{
  name: string;
  canonicalPath: string;
  mode: string;
  objectType: "blob" | "tree" | "commit";
  objectSha: string;
  size: number | null;
}>;

export type WebsiteProjectFilesSnapshot = Readonly<{
  commitSha: string;
  rootTreeSha: string;
  repositoryDisplayName: string;
}>;

export type WebsiteProjectFilesDirectory = Readonly<{
  directoryTreeSha: string;
  entries: readonly ProviderTreeEntry[];
}>;

export type WebsiteProjectFilesProviderFile = Readonly<{
  path: string;
  canonicalPath: string;
  mode: "100644" | "100755";
  objectType: "blob";
  declaredSize: number | null;
  bytes: Uint8Array;
}>;

export type WebsiteProjectFilesProviderWrite = Readonly<{
  commitSha: string;
  created: boolean;
}>;

export type WebsiteProjectFilesProvider = Readonly<{
  resolveSnapshot(
    authority: WebsiteProjectFilesAuthority,
  ): Promise<WebsiteProjectFilesSnapshot>;
  listDirectory(
    input: Readonly<{
      authority: WebsiteProjectFilesAuthority;
      commitSha: string;
      rootTreeSha: string;
      directoryTreeSha: string | null;
      path: string;
    }>,
  ): Promise<WebsiteProjectFilesDirectory>;
  readFile(
    input: Readonly<{
      authority: WebsiteProjectFilesAuthority;
      commitSha: string;
      rootTreeSha: string;
      path: string;
    }>,
  ): Promise<WebsiteProjectFilesProviderFile>;
  writeFile?(
    input: Readonly<{
      authority: WebsiteProjectFilesAuthority;
      parentCommitSha: string;
      rootTreeSha: string;
      path: string;
      bytes: Uint8Array;
    }>,
  ): Promise<WebsiteProjectFilesProviderWrite>;
}>;

export class WebsiteProjectFilesProviderError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "WebsiteProjectFilesProviderError";
  }
}

type ProviderDependencies = Readonly<{
  config: GitHubAppConfig;
  signal: AbortSignal;
  tokenBroker: Readonly<{
    issue(
      config: GitHubAppConfig,
      request: GitHubTokenRequest,
      authority: GitHubTokenAuthority,
      signal?: AbortSignal,
    ): Promise<GitHubInstallationTokenLease>;
  }>;
  httpClient: Readonly<{
    execute(
      operation: GitHubHttpOperation,
      signal?: AbortSignal,
    ): Promise<GitHubHttpResult>;
  }>;
}>;

function fail(code: string): never {
  throw new WebsiteProjectFilesProviderError(code);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(
  value: Record<string, unknown>,
  keys: readonly string[],
): boolean {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  return actual.length === expected.length &&
    actual.every((key, index) => key === expected[index]);
}

function validRef(value: string): boolean {
  return REF.test(value) && !value.includes("..") &&
    !value.includes("@{") && !value.endsWith(".") &&
    !value.endsWith(".lock") &&
    value.split("/").every((segment) =>
      segment !== "" && segment !== "." && segment !== ".."
    );
}

function validAuthority(
  value: WebsiteProjectFilesAuthority,
  config: GitHubAppConfig,
): boolean {
  if (!isRecord(value)) return false;
  return exactKeys(value, [
    "leaseId",
    "actorAuthUserId",
    "quoteRequestId",
    "websiteWorkContextId",
    "websiteWorkspaceId",
    "bindingRevision",
    "repositoryProvider",
    "repositoryOwner",
    "repositoryName",
    "repositoryExternalId",
    "repositoryNodeId",
    "defaultBranch",
    "repositoryRef",
    "refLabel",
    "markerOperationId",
    "expiresAt",
  ]) && UUID.test(value.leaseId) && UUID.test(value.actorAuthUserId) &&
    UUID.test(value.quoteRequestId) && UUID.test(value.websiteWorkContextId) &&
    UUID.test(value.websiteWorkspaceId) && UUID.test(value.markerOperationId) &&
    Number.isSafeInteger(value.bindingRevision) && value.bindingRevision > 0 &&
    value.repositoryProvider === "GITHUB" &&
    OWNER.test(value.repositoryOwner) &&
    value.repositoryOwner === config.organization &&
    REPOSITORY.test(value.repositoryName) &&
    NUMERIC_ID.test(value.repositoryExternalId) &&
    NODE_ID.test(value.repositoryNodeId) &&
    value.defaultBranch.length > 0 &&
    value.repositoryRef === `heads/${value.defaultBranch}` &&
    validRef(value.repositoryRef) && value.refLabel === value.defaultBranch &&
    Number.isFinite(Date.parse(value.expiresAt));
}

// Pure classification, reused by both the throwing normalize() below and the
// safe server-side failure log -- guarantees the logged diagnostic_code is
// always exactly the same value the client-visible thrown error carries,
// without duplicating the mapping logic.
function classifyProjectFilesFailure(error: unknown): string {
  if (error instanceof WebsiteProjectFilesProviderError) return error.code;
  const code = isRecord(error) && typeof error.code === "string"
    ? error.code
    : error instanceof Error
    ? error.message
    : "";
  if (code.includes("TIMEOUT") || code.includes("ABORT")) {
    return "PROJECT_FILES_PROVIDER_TIMEOUT";
  }
  if (code.includes("RATE_LIMIT") || code.includes("THROTTL")) {
    return "PROJECT_FILES_PROVIDER_THROTTLED";
  }
  if (code.includes("NOT_FOUND") || code.includes("GONE")) {
    return "PROJECT_FILES_SNAPSHOT_UNAVAILABLE";
  }
  return "PROJECT_FILES_PROVIDER_UNAVAILABLE";
}

function normalize(error: unknown): never {
  if (error instanceof WebsiteProjectFilesProviderError) throw error;
  return fail(classifyProjectFilesFailure(error));
}

// Maps each GitHub HTTP operation kind this provider ever issues to the
// safe, machine-readable Project Files failure stage it belongs to. Only
// used for observability labeling -- never for control flow.
const PROJECT_FILES_OPERATION_STAGES: Readonly<Record<string, string>> = Object.freeze({
  WEBSITE_PROJECT_FILES_REPOSITORY_METADATA: "REPOSITORY_METADATA",
  WEBSITE_PROJECT_FILES_READ_REF: "REF_READ",
  WEBSITE_PROJECT_FILES_READ_COMMIT: "COMMIT_READ",
  WEBSITE_PROJECT_FILES_READ_MARKER: "MARKER_READ",
  WEBSITE_PROJECT_FILES_READ_TREE: "TREE_READ",
  READ_BLOB: "BLOB_READ",
  CREATE_BLOB: "CREATE_BLOB",
  CREATE_TREE: "CREATE_TREE",
  CREATE_COMMIT: "CREATE_COMMIT",
  UPDATE_REF: "UPDATE_REF",
  WRITE_PROJECT_MARKER: "WRITE_MARKER",
});

// Extracts only already-safe, already-validated token-broker fields from a
// caught TOKEN_ACQUIRE failure. Uses the existing trusted validators
// (hasValidatedGitHubTokenAcquireDiagnostic/...LeaseCheck/...ResponseCheck)
// rather than a bare `instanceof` check -- these are WeakSet-backed and can
// only ever be true for objects that passed through the real, validating
// constructor, so a prototype-forged object can never satisfy them. Every
// individual field is additionally re-checked against its own exported
// closed enum before being included, so nothing beyond the pre-approved
// whitelists can ever reach the log even if a future caller mutates one of
// these (readonly, but defense in depth) fields after construction.
function safeTokenAcquireFailureFields(error: unknown): Readonly<Record<string, string>> {
  if (!hasValidatedGitHubTokenAcquireDiagnostic(error)) return Object.freeze({});
  const fields: Record<string, string> = {};
  const brokerCode = (error as { code?: unknown }).code;
  if (
    typeof brokerCode === "string" &&
    (GITHUB_TOKEN_BROKER_CODES as readonly string[]).includes(brokerCode)
  ) {
    fields.token_broker_code = brokerCode;
  }
  if (
    error.tokenAcquireSubphase !== undefined &&
    (GITHUB_TOKEN_ACQUIRE_SUBPHASES as readonly string[]).includes(
      error.tokenAcquireSubphase,
    )
  ) {
    fields.token_acquire_subphase = error.tokenAcquireSubphase;
  }
  if (hasValidatedGitHubTokenLeaseCheck(error)) {
    fields.token_lease_check = error.tokenLeaseCheck;
  }
  if (hasValidatedGitHubTokenResponseCheck(error)) {
    fields.token_response_check = error.tokenResponseCheck;
  }
  const exchangeClass = (error as { tokenExchangeHttpClass?: unknown })
    .tokenExchangeHttpClass;
  if (
    error.tokenAcquireSubphase === "TOKEN_HTTP_STATUS" &&
    typeof exchangeClass === "string" &&
    (GITHUB_TOKEN_EXCHANGE_HTTP_CLASSES as readonly string[]).includes(exchangeClass)
  ) {
    fields.token_exchange_http_class = exchangeClass;
    const exchangeStatus = (error as { tokenExchangeHttpStatus?: unknown })
      .tokenExchangeHttpStatus;
    if (
      exchangeClass === "GITHUB_HTTP_CONFLICT" &&
      (exchangeStatus === 409 || exchangeStatus === 422)
    ) {
      fields.token_exchange_http_status = String(exchangeStatus);
    }
  }
  return Object.freeze(fields);
}

// Extracts only already-safe, already-validated fields from a caught
// GitHubHttpError -- never raw provider bodies, headers, tokens, JWTs,
// private keys, or Authorization values. Absence on any other error shape
// is always handled the same safe way (no fields).
function safeGithubHttpFailureFields(error: unknown): Readonly<Record<string, string>> {
  if (error instanceof GitHubHttpError) {
    const status = getValidatedGitHubHttpStatus(error);
    return Object.freeze({
      github_http_class: error.code,
      ...(error.boundary !== undefined
        ? { github_http_boundary: error.boundary }
        : {}),
      ...(status !== null ? { github_http_status: String(status) } : {}),
    });
  }
  return Object.freeze({});
}

// Safe, sanitized failure log record for server-side observability only.
// Contains no JWTs, tokens, Authorization headers, private key material, or
// raw provider/database payloads -- only the pre-approved action/stage/code
// plus (only when present) already-safe, already-validated GitHub fields.
// Exported so tests can assert its exact shape without needing to intercept
// console output.
export function buildProjectFilesFailureLog(
  action: string,
  stage: string,
  error: unknown,
): Readonly<Record<string, string>> {
  return Object.freeze({
    event: "LWS_GIT001_PROJECT_FILES_FAILURE",
    action,
    stage,
    diagnostic_code: classifyProjectFilesFailure(error),
    ...(stage === "TOKEN_ACQUIRE"
      ? safeTokenAcquireFailureFields(error)
      : safeGithubHttpFailureFields(error)),
  });
}

// Never reaches the browser/client -- the thrown (and unchanged) normalize()
// result is the only thing callers ever see.
function logProjectFilesFailure(
  action: string,
  stage: string,
  error: unknown,
): void {
  console.error(JSON.stringify(buildProjectFilesFailureLog(action, stage, error)));
}

function decodeMarker(value: unknown): Record<string, unknown> {
  if (typeof value !== "string" || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) {
    return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  }
  try {
    const bytes = Uint8Array.from(
      atob(value),
      (character) => character.charCodeAt(0),
    );
    const parsed = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(bytes),
    );
    if (!isRecord(parsed)) {
      return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
    }
    return parsed;
  } catch (error) {
    if (error instanceof WebsiteProjectFilesProviderError) throw error;
    return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  }
}

function projectMetadata(
  value: unknown,
  authority: WebsiteProjectFilesAuthority,
): string {
  if (!isRecord(value)) return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  if (
    value.repositoryId !== authority.repositoryExternalId ||
    value.nodeId !== authority.repositoryNodeId ||
    value.owner !== authority.repositoryOwner ||
    value.name !== authority.repositoryName ||
    value.fullName !==
      `${authority.repositoryOwner}/${authority.repositoryName}` ||
    value.private !== true || value.defaultBranch !== authority.defaultBranch
  ) return fail("REPOSITORY_BINDING_STALE");
  return value.fullName;
}

function projectRef(
  value: unknown,
  authority: WebsiteProjectFilesAuthority,
): string {
  if (
    !isRecord(value) || value.ref !== `refs/${authority.repositoryRef}` ||
    typeof value.commitSha !== "string" || !SHA.test(value.commitSha)
  ) return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  return value.commitSha;
}

function projectCommit(value: unknown, expectedSha: string): string {
  if (
    !isRecord(value) || value.sha !== expectedSha ||
    typeof value.treeSha !== "string" || !SHA.test(value.treeSha)
  ) return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  return value.treeSha;
}

function projectSha(value: unknown): string {
  if (!isRecord(value) || typeof value.sha !== "string" || !SHA.test(value.sha)) {
    return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  }
  return value.sha;
}

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function verifyMarker(
  value: unknown,
  authority: WebsiteProjectFilesAuthority,
  expectedEnvironment: "TEST" | "PRODUCTION",
): void {
  if (
    !isRecord(value) || value.path !== ".lws/project.json" ||
    value.encoding !== "base64" || typeof value.sha !== "string" ||
    !SHA.test(value.sha) || !Number.isSafeInteger(value.size) ||
    (value.size as number) < 1 || (value.size as number) > 65_536
  ) return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  const marker = decodeMarker(value.contentBase64);
  if (
    marker.schema_version !== 1 ||
    marker.environment !== expectedEnvironment ||
    marker.organization !== authority.repositoryOwner ||
    marker.website_work_context_id !== authority.websiteWorkContextId ||
    marker.repository_provisioning_operation_id !== authority.markerOperationId
  ) return fail("REPOSITORY_BINDING_STALE");
}

function validName(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= 255 &&
    !value.includes("/") && !value.includes("\\") && value !== "." &&
    value !== ".." &&
    value.normalize("NFC") === value && value.normalize("NFKC") === value;
}

function projectTree(
  value: unknown,
  expectedTree: string,
  path: string,
): readonly ProviderTreeEntry[] {
  if (
    !isRecord(value) || value.sha !== expectedTree ||
    value.truncated !== false ||
    !Array.isArray(value.entries)
  ) return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  return Object.freeze(value.entries.map((raw) => {
    if (
      !isRecord(raw) || !validName(raw.path) || typeof raw.mode !== "string" ||
      typeof raw.type !== "string" || typeof raw.sha !== "string" ||
      !SHA.test(raw.sha)
    ) {
      return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
    }
    const validMode = raw.type === "tree" && raw.mode === "040000" ||
      raw.type === "commit" && raw.mode === "160000" ||
      raw.type === "blob" && ["100644", "100755", "120000"].includes(raw.mode);
    if (!validMode) return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
    if (
      raw.size !== undefined && raw.size !== null &&
      (!Number.isSafeInteger(raw.size) || (raw.size as number) < 0)
    ) {
      return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
    }
    return Object.freeze({
      name: raw.path,
      canonicalPath: path ? `${path}/${raw.path}` : raw.path,
      mode: raw.mode,
      objectType: raw.type as "blob" | "tree" | "commit",
      objectSha: raw.sha,
      size: typeof raw.size === "number" ? raw.size : null,
    });
  }));
}

function decodeBlob(
  value: GitHubHttpResult,
  expectedSha: string,
  declaredSize: number | null,
): Uint8Array {
  if (!isRecord(value)) return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  const blob = value as Record<string, unknown>;
  if (
    !exactKeys(blob, [
      "sha",
      "encoding",
      "contentBase64",
      "size",
    ]) || blob.sha !== expectedSha || blob.encoding !== "base64" ||
    typeof blob.contentBase64 !== "string" ||
    !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(
      blob.contentBase64,
    ) || !Number.isSafeInteger(blob.size) || (blob.size as number) < 0
  ) return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  if ((blob.size as number) > MAX_FILE_BYTES) return fail("FILE_TOO_LARGE");
  if (
    declaredSize !== null &&
    (blob.size as number) !== declaredSize
  ) return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  if (blob.contentBase64.length > Math.ceil(MAX_FILE_BYTES / 3) * 4) {
    return fail("FILE_TOO_LARGE");
  }
  let bytes: Uint8Array;
  try {
    bytes = Uint8Array.from(
      atob(blob.contentBase64),
      (character) => character.charCodeAt(0),
    );
  } catch {
    return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  }
  if (bytes.byteLength > MAX_FILE_BYTES) return fail("FILE_TOO_LARGE");
  if (bytes.byteLength !== blob.size) {
    return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  }
  let canonical = "";
  for (const byte of bytes) canonical += String.fromCharCode(byte);
  if (btoa(canonical) !== blob.contentBase64) {
    return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
  }
  return bytes;
}

export function createWebsiteProjectFilesProvider(
  dependencies: ProviderDependencies,
): WebsiteProjectFilesProvider {
  if (
    !dependencies || typeof dependencies !== "object" || !dependencies.config ||
    !(dependencies.signal instanceof AbortSignal) ||
    typeof dependencies.tokenBroker?.issue !== "function" ||
    typeof dependencies.httpClient?.execute !== "function"
  ) return fail("PROJECT_FILES_PROVIDER_CONFIGURATION_ERROR");

  async function access(
    authority: WebsiteProjectFilesAuthority,
    operation: "WEBSITE_PROJECT_FILES_READ" | "WEBSITE_PROJECT_FILES_WRITE" =
      "WEBSITE_PROJECT_FILES_READ",
  ): Promise<string> {
    if (!validAuthority(authority, dependencies.config)) {
      return fail("REPOSITORY_BINDING_STALE");
    }
    try {
      const lease = await dependencies.tokenBroker.issue(
        dependencies.config,
        Object.freeze({
          websiteWorkContextId: authority.websiteWorkContextId,
          target: dependencies.config.target,
          organization: authority.repositoryOwner,
          operation,
          repositoryIds: Object.freeze([authority.repositoryExternalId]),
        }),
        Object.freeze({
          websiteWorkContextId: authority.websiteWorkContextId,
          target: dependencies.config.target,
          organization: authority.repositoryOwner,
          repositoryIds: Object.freeze([authority.repositoryExternalId]),
        }),
        dependencies.signal,
      );
      if (!TOKEN.test(lease.token)) {
        return fail("PROJECT_FILES_PROVIDER_UNAVAILABLE");
      }
      return lease.token;
    } catch (error) {
      logProjectFilesFailure(operation, "TOKEN_ACQUIRE", error);
      return normalize(error);
    }
  }

  async function execute(
    operation: GitHubHttpOperation,
  ): Promise<GitHubHttpResult> {
    try {
      return await dependencies.httpClient.execute(
        operation,
        dependencies.signal,
      );
    } catch (error) {
      logProjectFilesFailure(
        operation.kind,
        PROJECT_FILES_OPERATION_STAGES[operation.kind] ?? operation.kind,
        error,
      );
      return normalize(error);
    }
  }

  function coordinates(authority: WebsiteProjectFilesAuthority, token: string) {
    return {
      owner: authority.repositoryOwner,
      repository: authority.repositoryName,
      token,
    };
  }

  return Object.freeze({
    async resolveSnapshot(authority) {
      const token = await access(authority);
      const base = coordinates(authority, token);
      const repositoryDisplayName = projectMetadata(
        await execute({
          kind: "WEBSITE_PROJECT_FILES_REPOSITORY_METADATA",
          ...base,
        }),
        authority,
      );
      const commitSha = projectRef(
        await execute({
          kind: "WEBSITE_PROJECT_FILES_READ_REF",
          ...base,
          ref: authority.repositoryRef,
        }),
        authority,
      );
      const rootTreeSha = projectCommit(
        await execute({
          kind: "WEBSITE_PROJECT_FILES_READ_COMMIT",
          ...base,
          commitSha,
        }),
        commitSha,
      );
      verifyMarker(
        await execute({
          kind: "WEBSITE_PROJECT_FILES_READ_MARKER",
          ...base,
          ref: commitSha,
        }),
        authority,
        dependencies.config.target,
      );
      return Object.freeze({ commitSha, rootTreeSha, repositoryDisplayName });
    },

    async listDirectory(input) {
      if (
        !isRecord(input) ||
        !validAuthority(input.authority, dependencies.config) ||
        !SHA.test(input.commitSha) || !SHA.test(input.rootTreeSha) ||
        input.directoryTreeSha !== null && !SHA.test(input.directoryTreeSha) ||
        typeof input.path !== "string"
      ) return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
      const token = await access(input.authority);
      const base = coordinates(input.authority, token);
      let treeSha = input.directoryTreeSha ?? input.rootTreeSha;
      if (input.directoryTreeSha === null && input.path !== "") {
        let traversed = "";
        for (const segment of input.path.split("/")) {
          if (!validName(segment)) {
            return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
          }
          const level = projectTree(
            await execute({
              kind: "WEBSITE_PROJECT_FILES_READ_TREE",
              ...base,
              treeRef: treeSha,
            }),
            treeSha,
            traversed,
          );
          const next = level.find((entry) => entry.name === segment);
          if (!next || next.objectType !== "tree" || next.mode !== "040000") {
            return fail("PROJECT_FILES_SNAPSHOT_UNAVAILABLE");
          }
          treeSha = next.objectSha;
          traversed = traversed ? `${traversed}/${segment}` : segment;
        }
      }
      const entries = projectTree(
        await execute({
          kind: "WEBSITE_PROJECT_FILES_READ_TREE",
          ...base,
          treeRef: treeSha,
        }),
        treeSha,
        input.path,
      );
      return Object.freeze({ directoryTreeSha: treeSha, entries });
    },

    async readFile(input) {
      if (
        !isRecord(input) || !exactKeys(input, [
          "authority",
          "commitSha",
          "rootTreeSha",
          "path",
        ]) || !validAuthority(input.authority, dependencies.config) ||
        !SHA.test(input.commitSha) || !SHA.test(input.rootTreeSha) ||
        typeof input.path !== "string" || input.path === ""
      ) return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
      const segments = input.path.split("/");
      if (!segments.every(validName)) {
        return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
      }
      const token = await access(input.authority);
      const base = coordinates(input.authority, token);
      let treeSha = input.rootTreeSha;
      let traversed = "";
      for (let index = 0; index < segments.length; index++) {
        const entries = projectTree(
          await execute({
            kind: "WEBSITE_PROJECT_FILES_READ_TREE",
            ...base,
            treeRef: treeSha,
          }),
          treeSha,
          traversed,
        );
        const segment = segments[index];
        const target = entries.find((entry) => entry.name === segment);
        if (!target) return fail("PROJECT_FILE_NOT_FOUND");
        const final = index === segments.length - 1;
        if (!final) {
          if (target.objectType !== "tree" || target.mode !== "040000") {
            return fail("PROJECT_PATH_KIND_MISMATCH");
          }
          treeSha = target.objectSha;
          traversed = traversed ? `${traversed}/${segment}` : segment;
          continue;
        }
        if (
          target.objectType !== "blob" ||
          target.mode !== "100644" && target.mode !== "100755"
        ) return fail("PROJECT_PATH_KIND_MISMATCH");
        if (target.size !== null && target.size > MAX_FILE_BYTES) {
          return fail("FILE_TOO_LARGE");
        }
        const bytes = decodeBlob(
          await execute({
            kind: "READ_BLOB",
            ...base,
            blobSha: target.objectSha,
          }),
          target.objectSha,
          target.size,
        );
        return Object.freeze({
          path: input.path,
          canonicalPath: target.canonicalPath,
          mode: target.mode,
          objectType: "blob" as const,
          declaredSize: target.size,
          bytes: Uint8Array.from(bytes),
        });
      }
      return fail("PROJECT_FILE_NOT_FOUND");
    },

    async writeFile(input) {
      if (
        !isRecord(input) || !exactKeys(input, [
          "authority",
          "bytes",
          "parentCommitSha",
          "path",
          "rootTreeSha",
        ]) || !validAuthority(input.authority, dependencies.config) ||
        !SHA.test(input.parentCommitSha) || !SHA.test(input.rootTreeSha) ||
        typeof input.path !== "string" || input.path === "" ||
        !(input.bytes instanceof Uint8Array) ||
        input.bytes.byteLength > MAX_FILE_BYTES
      ) return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
      const segments = input.path.split("/");
      if (!segments.every(validName)) {
        return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
      }
      const token = await access(
        input.authority,
        "WEBSITE_PROJECT_FILES_WRITE",
      );
      const base = coordinates(input.authority, token);
      const currentCommit = projectRef(
        await execute({
          kind: "WEBSITE_PROJECT_FILES_READ_REF",
          ...base,
          ref: input.authority.repositoryRef,
        }),
        input.authority,
      );
      if (currentCommit !== input.parentCommitSha) {
        return fail("PROJECT_FILES_STALE_REVISION");
      }

      let treeSha = input.rootTreeSha;
      let traversed = "";
      let created = false;
      for (let index = 0; index < segments.length; index++) {
        const entries = projectTree(
          await execute({
            kind: "WEBSITE_PROJECT_FILES_READ_TREE",
            ...base,
            treeRef: treeSha,
          }),
          treeSha,
          traversed,
        );
        const target = entries.find((entry) => entry.name === segments[index]);
        const final = index === segments.length - 1;
        if (final) {
          if (!target) {
            created = true;
          } else if (
            target.objectType !== "blob" ||
            target.mode !== "100644" && target.mode !== "100755"
          ) return fail("PROJECT_PATH_KIND_MISMATCH");
          break;
        }
        if (!target || target.objectType !== "tree" || target.mode !== "040000") {
          return fail("PROJECT_PATH_KIND_MISMATCH");
        }
        treeSha = target.objectSha;
        traversed = traversed ? `${traversed}/${segments[index]}` : segments[index];
      }

      const blobSha = projectSha(await execute({
        kind: "CREATE_BLOB",
        ...base,
        contentBase64: encodeBase64(input.bytes),
      }));
      const nextTreeSha = projectSha(await execute({
        kind: "CREATE_TREE",
        ...base,
        baseTreeSha: input.rootTreeSha,
        entries: Object.freeze([Object.freeze({
          path: input.path,
          mode: "100644",
          type: "blob" as const,
          sha: blobSha,
        })]),
      }));
      const commitSha = projectSha(await execute({
        kind: "CREATE_COMMIT",
        ...base,
        message: "chore: save website project file",
        treeSha: nextTreeSha,
        parentSha: input.parentCommitSha,
      }));
      const publishedCommit = projectRef(await execute({
        kind: "UPDATE_REF",
        ...base,
        commitSha,
        force: false,
        ref: input.authority.repositoryRef,
      }), input.authority);
      if (publishedCommit !== commitSha) {
        return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
      }
      return Object.freeze({ commitSha, created });
    },
  });
}
