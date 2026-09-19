import type { GitHubInstallationPermissions } from "./github-app-token.ts";
import {
  GitHubTokenAcquireDiagnosticError,
  type GitHubTokenAcquireSubphase,
  type GitHubTokenResponseCheck,
} from "./repository-provisioning-diagnostics.ts";
import { isGitHubInstallationAccessToken } from "./github-installation-token.ts";
import {
  createGitHubRefReadDiagnostic,
  type GitHubRefReadDiagnostic,
  validateGitHubRefReadDiagnostic,
} from "./github-ref-read-diagnostic.ts";

const API_ORIGIN = "https://api.github.com";
const GRAPHQL_URL = `${API_ORIGIN}/graphql`;
const ALLOWED_REDIRECT_HOSTS = new Set(["api.github.com", "github.com"]);
const API_VERSION = "2022-11-28";
const JSON_MEDIA_TYPE = "application/vnd.github+json";
const DEFAULT_TIMEOUT_MILLISECONDS = 10_000;
const INSTALLATION_PROOF_RESPONSE_BYTES = 64 * 1024;
const SMALL_RESPONSE_BYTES = 256 * 1024;
const TREE_RESPONSE_BYTES = 8 * 1024 * 1024;
const MARKER_BYTES = 64 * 1024;
const BOOTSTRAP_BYTES = 64 * 1024;
const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const OWNER = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/;
const REPOSITORY = /^[A-Za-z0-9._-]{1,100}$/;
const SHA = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const REF =
  /^(?:heads|tags)\/[A-Za-z0-9](?:[A-Za-z0-9._\/-]{0,253}[A-Za-z0-9])?$/;
const APP_JWT = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;
const MAX_CLOCK_SKEW_MILLISECONDS = 60 * 1000;

type RepositoryCoordinates = Readonly<{
  owner: string;
  repository: string;
  token: string;
}>;

export type GitHubHttpOperation =
  | Readonly<{
    kind: "TOKEN_EXCHANGE";
    installationId: string;
    appJwt: string;
    repositoryIds: readonly string[];
    permissions: GitHubInstallationPermissions;
  }>
  | Readonly<{
    kind: "REPOSITORY_INSTALLATION_PROOF";
    owner: string;
    repository: string;
    expectedInstallationId: string;
    expectedOrganization: string;
    appJwt: string;
  }>
  | (RepositoryCoordinates & Readonly<{ kind: "REPOSITORY_METADATA" }>)
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "WEBSITE_PROJECT_FILES_REPOSITORY_METADATA";
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "WEBSITE_PROJECT_FILES_READ_REF";
      ref: string;
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "WEBSITE_PROJECT_FILES_READ_TREE";
      treeRef: string;
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "WEBSITE_PROJECT_FILES_READ_MARKER";
      ref: string;
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "WEBSITE_PROJECT_FILES_READ_COMMIT";
      commitSha: string;
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "READ_REF";
      ref: "heads/main";
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "REPOSITORY_EMPTY_PROOF";
      expectedRepositoryId: string;
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "REPOSITORY_TREE";
      treeRef: string;
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "READ_BLOB";
      blobSha: string;
    }>
  )
  | Readonly<{
    kind: "CREATE_REPOSITORY";
    owner: string;
    repository: string;
    description: string;
    token: string;
  }>
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "CREATE_BLOB";
      contentBase64: string;
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "CREATE_TREE";
      entries: readonly Readonly<{
        path: string;
        mode: string;
        type: "blob";
        sha: string;
      }>[];
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "CREATE_COMMIT";
      message: "chore: initialize approved starter snapshot";
      treeSha: string;
      parentSha?: string;
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "CREATE_REF";
      commitSha: string;
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "CREATE_BOOTSTRAP_FILE";
      contentBase64: string;
      branch: "main";
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "READ_BOOTSTRAP_FILE";
      ref: string;
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "READ_BOOTSTRAP_COMMIT";
      commitSha: string;
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "UPDATE_REF";
      commitSha: string;
      force: false;
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "WRITE_PROJECT_MARKER";
      message: string;
      contentBase64: string;
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "READ_PROJECT_MARKER";
      ref: string;
    }>
  )
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "COMMIT_METADATA";
      commitSha: string;
    }>
  );

export type GitHubHttpResult =
  | Readonly<{
    token: string;
    expiresAt: string;
    repositorySelection?: "all" | "selected";
    permissions: GitHubInstallationPermissions;
  }>
  | Readonly<{ proven: true }>
  | Readonly<{ empty: true }>
  | GitHubRepositoryMetadata
  | Readonly<{
    sha: string;
    truncated: false;
    entries: readonly GitHubTreeEntry[];
  }>
  | Readonly<{
    sha: string;
    encoding: "base64";
    contentBase64: string;
    size: number;
  }>
  | Readonly<{ sha: string }>
  | Readonly<{ ref: string; commitSha: string }>
  | Readonly<{
    path: ".lws/bootstrap.json";
    contentSha: string;
    commitSha: string;
    parentCount: number;
  }>
  | Readonly<{
    path: ".lws/bootstrap.json";
    sha: string;
    encoding: "base64";
    contentBase64: string;
    size: number;
  }>
  | Readonly<{ sha: string; treeSha: string; parentCount: number }>
  | Readonly<{ contentSha: string; commitSha: string }>
  | Readonly<{
    path: ".lws/project.json";
    sha: string;
    encoding: "base64";
    contentBase64: string;
    size: number;
  }>
  | Readonly<{ sha: string; treeSha: string }>;

export type GitHubRepositoryMetadata = Readonly<{
  repositoryId: string;
  nodeId: string;
  owner: string;
  name: string;
  fullName: string;
  private: boolean;
  defaultBranch: string;
  description: string | null;
  createdAt: string;
}>;

export type GitHubTreeEntry = Readonly<{
  path: string;
  mode: string;
  type: "blob" | "tree" | "commit";
  sha: string;
  size?: number;
}>;

export type GitHubHttpErrorCode =
  | "GITHUB_HTTP_OPERATION_INVALID"
  | "GITHUB_HTTP_REDIRECT_DENIED"
  | "GITHUB_HTTP_RESPONSE_INVALID"
  | "GITHUB_HTTP_RESPONSE_TOO_LARGE"
  | "GITHUB_HTTP_UNAUTHORIZED"
  | "GITHUB_HTTP_FORBIDDEN"
  | "GITHUB_HTTP_NOT_FOUND"
  | "GITHUB_HTTP_CONFLICT"
  | "GITHUB_HTTP_RATE_LIMITED"
  | "GITHUB_HTTP_SERVER_ERROR"
  | "GITHUB_HTTP_TIMEOUT"
  | "GITHUB_HTTP_NETWORK_ERROR"
  | "GITHUB_HTTP_FAILED";

export const GITHUB_HTTP_FAILURE_BOUNDARIES = [
  "REQUEST_PREPARE",
  "HTTP_REQUEST",
  "HTTP_STATUS",
  "CONTENT_TYPE",
  "BODY_READ",
  "JSON_PARSE",
  "RESPONSE_SCHEMA",
] as const;

export type GitHubHttpFailureBoundary =
  (typeof GITHUB_HTTP_FAILURE_BOUNDARIES)[number];

const githubHttpBoundaryDiagnostics = new WeakSet<object>();
const githubHttpRefReadDiagnostics = new WeakMap<
  object,
  GitHubRefReadDiagnostic
>();
const githubHttpStatuses = new WeakMap<object, number>();

function isTrustedGitHubHttpError(value: unknown): value is GitHubHttpError {
  return typeof value === "object" && value !== null &&
    githubHttpRefReadDiagnostics.has(value);
}

export class GitHubHttpError extends GitHubTokenAcquireDiagnosticError {
  constructor(
    readonly code: GitHubHttpErrorCode,
    readonly requestId: string | null = null,
    readonly retryAt: string | null = null,
    tokenAcquireSubphase?: GitHubTokenAcquireSubphase,
    readonly boundary?: GitHubHttpFailureBoundary,
    tokenResponseCheck?: GitHubTokenResponseCheck,
    status?: number,
  ) {
    if (
      boundary !== undefined &&
      !GITHUB_HTTP_FAILURE_BOUNDARIES.includes(boundary)
    ) throw new Error("GITHUB_HTTP_DIAGNOSTIC_INVALID");
    super(code, tokenAcquireSubphase, undefined, tokenResponseCheck);
    this.name = "GitHubHttpError";
    Object.defineProperty(this, "boundary", {
      value: boundary,
      enumerable: true,
      writable: false,
      configurable: false,
    });
    if (boundary !== undefined) githubHttpBoundaryDiagnostics.add(this);
    githubHttpRefReadDiagnostics.set(
      this,
      createGitHubRefReadDiagnostic(boundary, code),
    );
    if (status === 409 || status === 422) githubHttpStatuses.set(this, status);
  }
}

export function getValidatedGitHubHttpStatus(value: unknown): number | null {
  return typeof value === "object" && value !== null
    ? githubHttpStatuses.get(value) ?? null
    : null;
}

export function hasValidatedGitHubHttpBoundary(
  value: GitHubHttpError,
): value is GitHubHttpError & { readonly boundary: GitHubHttpFailureBoundary } {
  return githubHttpBoundaryDiagnostics.has(value);
}

export function getValidatedGitHubHttpRefReadDiagnostic(
  value: unknown,
): GitHubRefReadDiagnostic {
  return validateGitHubRefReadDiagnostic(
    typeof value === "object" && value !== null
      ? githubHttpRefReadDiagnostics.get(value)
      : undefined,
  );
}

export type GitHubHttpClient = Readonly<{
  execute(
    operation: GitHubHttpOperation,
    signal?: AbortSignal,
  ): Promise<GitHubHttpResult>;
}>;

export type GitHubHttpClientDependencies = Readonly<{
  fetch: typeof fetch;
  timeoutMilliseconds?: number;
  now?: () => number;
}>;

type PreparedRequest = Readonly<{
  url: string;
  init: RequestInit;
  responseBytes: number;
  project(value: unknown): GitHubHttpResult;
  successStatus?: number;
}>;

function exactKeys(value: object, expected: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  const allowed = [...expected].sort();
  return actual.length === allowed.length &&
    actual.every((key, index) => key === allowed[index]);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function validCoordinates(value: RepositoryCoordinates): boolean {
  return OWNER.test(value.owner) && validRepositoryName(value.repository) &&
    isGitHubInstallationAccessToken(value.token);
}

function validRepositoryName(value: string): boolean {
  return REPOSITORY.test(value) && value !== "." && value !== "..";
}

function validRef(value: string): boolean {
  return REF.test(value) && !value.includes("..") &&
    !value.includes("@{") && !value.endsWith(".") &&
    !value.endsWith(".lock") &&
    value.split("/").every((segment) =>
      segment !== "" && segment !== "." && segment !== ".."
    );
}

function validNumericId(value: unknown): value is string {
  if (typeof value !== "string" || !NUMERIC_ID.test(value)) return false;
  const numeric = Number(value);
  return Number.isSafeInteger(numeric) && String(numeric) === value;
}

function validPermissions(
  value: unknown,
): value is GitHubInstallationPermissions {
  if (!isRecord(value)) return false;
  return exactKeys(value, ["metadata", "administration"]) &&
      value.metadata === "read" && value.administration === "write" ||
    exactKeys(value, ["metadata", "contents"]) &&
      value.metadata === "read" && value.contents === "read" ||
    exactKeys(value, ["metadata", "contents"]) &&
      value.metadata === "read" && value.contents === "write";
}

function samePermissions(
  value: GitHubInstallationPermissions,
  expected: GitHubInstallationPermissions,
): boolean {
  return exactKeys(value, Object.keys(expected)) &&
    Object.entries(expected).every(([key, level]) =>
      (value as unknown as Record<string, unknown>)[key] === level
    );
}

function bearer(token: string): HeadersInit {
  return {
    "accept": JSON_MEDIA_TYPE,
    "authorization": `Bearer ${token}`,
    "content-type": "application/json",
    "x-github-api-version": API_VERSION,
  };
}

function jsonRequest(
  method: "POST" | "PUT" | "PATCH",
  token: string,
  body: unknown,
): RequestInit {
  return {
    method,
    headers: bearer(token),
    body: JSON.stringify(body),
    redirect: "manual",
  };
}

function getRequest(token: string): RequestInit {
  return { method: "GET", headers: bearer(token), redirect: "manual" };
}

function appJwtGetRequest(appJwt: string): RequestInit {
  return { method: "GET", headers: bearer(appJwt), redirect: "error" };
}

function invalidOperation(
  tokenAcquireSubphase?: GitHubTokenAcquireSubphase,
): never {
  throw new GitHubHttpError(
    "GITHUB_HTTP_OPERATION_INVALID",
    null,
    null,
    tokenAcquireSubphase,
    "REQUEST_PREPARE",
  );
}

function prepare(
  operation: GitHubHttpOperation,
  now: () => number,
): PreparedRequest {
  if (!isRecord(operation) || typeof operation.kind !== "string") {
    return invalidOperation();
  }
  switch (operation.kind) {
    case "TOKEN_EXCHANGE": {
      if (
        !exactKeys(operation, [
          "kind",
          "installationId",
          "appJwt",
          "repositoryIds",
          "permissions",
        ]) || !validNumericId(operation.installationId) ||
        !APP_JWT.test(operation.appJwt) ||
        !Array.isArray(operation.repositoryIds) ||
        operation.repositoryIds.length > 1 ||
        !operation.repositoryIds.every(validNumericId) ||
        !validPermissions(operation.permissions)
      ) return invalidOperation("TOKEN_REQUEST_PREPARE");
      const body: Record<string, unknown> = {
        permissions: operation.permissions,
      };
      if (operation.repositoryIds.length === 1) {
        body.repository_ids = operation.repositoryIds.map(Number);
      }
      return {
        url:
          `${API_ORIGIN}/app/installations/${operation.installationId}/access_tokens`,
        init: jsonRequest("POST", operation.appJwt, body),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: (value) => projectToken(value, operation.permissions, now()),
      };
    }
    case "REPOSITORY_INSTALLATION_PROOF": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "expectedInstallationId",
          "expectedOrganization",
          "appJwt",
        ]) || !OWNER.test(operation.owner) ||
        !validRepositoryName(operation.repository) ||
        operation.expectedOrganization !== operation.owner ||
        !validNumericId(operation.expectedInstallationId) ||
        !APP_JWT.test(operation.appJwt)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/installation`,
        init: appJwtGetRequest(operation.appJwt),
        responseBytes: INSTALLATION_PROOF_RESPONSE_BYTES,
        project: (value) =>
          projectRepositoryInstallation(
            value,
            operation.expectedInstallationId,
            operation.expectedOrganization,
          ),
      };
    }
    case "REPOSITORY_METADATA": {
      if (
        !exactKeys(operation, ["kind", "owner", "repository", "token"]) ||
        !validCoordinates(operation)
      ) return invalidOperation();
      return {
        url: `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}`,
        init: getRequest(operation.token),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: projectRepository,
      };
    }
    case "WEBSITE_PROJECT_FILES_REPOSITORY_METADATA": {
      if (
        !exactKeys(operation, ["kind", "owner", "repository", "token"]) ||
        !validCoordinates(operation)
      ) return invalidOperation();
      return {
        url: `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}`,
        init: getRequest(operation.token),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: projectRepository,
      };
    }
    case "WEBSITE_PROJECT_FILES_READ_REF": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "ref",
          "token",
        ]) ||
        !validCoordinates(operation) || !validRef(operation.ref)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/git/ref/${operation.ref}`,
        init: getRequest(operation.token),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: (value) => projectRefRead(value, `refs/${operation.ref}`),
      };
    }
    case "WEBSITE_PROJECT_FILES_READ_TREE": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "treeRef",
          "token",
        ]) ||
        !validCoordinates(operation) || !SHA.test(operation.treeRef)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/git/trees/${operation.treeRef}`,
        init: getRequest(operation.token),
        responseBytes: TREE_RESPONSE_BYTES,
        project: projectTree,
      };
    }
    case "WEBSITE_PROJECT_FILES_READ_MARKER": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "ref",
          "token",
        ]) ||
        !validCoordinates(operation) || !SHA.test(operation.ref)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/contents/.lws/project.json?ref=${operation.ref}`,
        init: getRequest(operation.token),
        responseBytes: MARKER_BYTES,
        project: projectMarkerRead,
      };
    }
    case "WEBSITE_PROJECT_FILES_READ_COMMIT": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "commitSha",
          "token",
        ]) ||
        !validCoordinates(operation) || !SHA.test(operation.commitSha)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/commits/${operation.commitSha}`,
        init: getRequest(operation.token),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: projectCommit,
      };
    }
    case "READ_REF": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "ref",
          "token",
        ]) || !validCoordinates(operation) || operation.ref !== "heads/main"
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/git/ref/${operation.ref}`,
        init: getRequest(operation.token),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: (value) => projectRefRead(value, "refs/heads/main"),
      };
    }
    case "REPOSITORY_EMPTY_PROOF": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "expectedRepositoryId",
          "token",
        ]) || !validCoordinates(operation) ||
        !validNumericId(operation.expectedRepositoryId)
      ) return invalidOperation();
      return {
        url: GRAPHQL_URL,
        init: jsonRequest("POST", operation.token, {
          query:
            "query RepositoryEmptyProof($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { databaseId nameWithOwner isEmpty defaultBranchRef { name } } }",
          variables: {
            owner: operation.owner,
            name: operation.repository,
          },
        }),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: (value) =>
          projectRepositoryEmptyProof(
            value,
            operation.owner,
            operation.repository,
            operation.expectedRepositoryId,
          ),
      };
    }
    case "REPOSITORY_TREE": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "treeRef",
          "token",
        ]) || !validCoordinates(operation) || !SHA.test(operation.treeRef)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/git/trees/${operation.treeRef}?recursive=1`,
        init: getRequest(operation.token),
        responseBytes: TREE_RESPONSE_BYTES,
        project: projectTree,
      };
    }
    case "READ_BLOB": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "blobSha",
          "token",
        ]) || !validCoordinates(operation) || !SHA.test(operation.blobSha)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/git/blobs/${operation.blobSha}`,
        init: getRequest(operation.token),
        responseBytes: TREE_RESPONSE_BYTES,
        project: projectBlob,
      };
    }
    case "CREATE_REPOSITORY": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "description",
          "token",
        ]) || !OWNER.test(operation.owner) ||
        !validRepositoryName(operation.repository) ||
        !isGitHubInstallationAccessToken(operation.token) ||
        !operation.description || operation.description.length > 256 ||
        /[\r\n]/.test(operation.description)
      ) return invalidOperation();
      return {
        url: `${API_ORIGIN}/orgs/${operation.owner}/repos`,
        init: jsonRequest("POST", operation.token, {
          name: operation.repository,
          description: operation.description,
          private: true,
          auto_init: false,
        }),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: projectRepository,
      };
    }
    case "CREATE_BLOB": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "contentBase64",
          "token",
        ]) || !validCoordinates(operation) ||
        !validBase64(operation.contentBase64, TREE_RESPONSE_BYTES)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/git/blobs`,
        init: jsonRequest("POST", operation.token, {
          content: operation.contentBase64,
          encoding: "base64",
        }),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: projectSha,
      };
    }
    case "CREATE_TREE": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "entries",
          "token",
        ]) ||
        !validCoordinates(operation) || !Array.isArray(operation.entries) ||
        operation.entries.length === 0 || operation.entries.length > 10_000 ||
        !operation.entries.every((entry) =>
          isRecord(entry) &&
          exactKeys(entry, ["path", "mode", "type", "sha"]) &&
          validTreePath(String(entry.path || "")) &&
          /^[0-7]{6}$/.test(String(entry.mode || "")) &&
          entry.type === "blob" && SHA.test(String(entry.sha || ""))
        )
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/git/trees`,
        init: jsonRequest("POST", operation.token, { tree: operation.entries }),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: projectSha,
      };
    }
    case "CREATE_COMMIT": {
      const keys = operation.parentSha === undefined
        ? ["kind", "owner", "repository", "message", "treeSha", "token"]
        : [
          "kind",
          "owner",
          "repository",
          "message",
          "treeSha",
          "parentSha",
          "token",
        ];
      if (
        !exactKeys(operation, keys) || !validCoordinates(operation) ||
        operation.message !== "chore: initialize approved starter snapshot" ||
        !SHA.test(operation.treeSha) ||
        operation.parentSha !== undefined && !SHA.test(operation.parentSha)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/git/commits`,
        init: jsonRequest("POST", operation.token, {
          message: operation.message,
          tree: operation.treeSha,
          parents: operation.parentSha === undefined
            ? []
            : [operation.parentSha],
        }),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: projectSha,
      };
    }
    case "CREATE_REF": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "commitSha",
          "token",
        ]) || !validCoordinates(operation) || !SHA.test(operation.commitSha)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/git/refs`,
        init: jsonRequest("POST", operation.token, {
          ref: "refs/heads/main",
          sha: operation.commitSha,
        }),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: projectRef,
      };
    }
    case "CREATE_BOOTSTRAP_FILE": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "contentBase64",
          "branch",
          "token",
        ]) || !validCoordinates(operation) || operation.branch !== "main" ||
        !validBase64(operation.contentBase64, BOOTSTRAP_BYTES)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/contents/.lws/bootstrap.json`,
        init: jsonRequest("PUT", operation.token, {
          message: "chore: initialize recovery bootstrap",
          content: operation.contentBase64,
          branch: operation.branch,
        }),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: projectBootstrapWrite,
        successStatus: 201,
      };
    }
    case "READ_BOOTSTRAP_FILE": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "ref",
          "token",
        ]) || !validCoordinates(operation) ||
        operation.ref !== "main" && !SHA.test(operation.ref)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/contents/.lws/bootstrap.json?ref=${operation.ref}`,
        init: getRequest(operation.token),
        responseBytes: BOOTSTRAP_BYTES,
        project: projectBootstrapRead,
      };
    }
    case "READ_BOOTSTRAP_COMMIT": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "commitSha",
          "token",
        ]) || !validCoordinates(operation) || !SHA.test(operation.commitSha)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/git/commits/${operation.commitSha}`,
        init: getRequest(operation.token),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: projectBootstrapCommit,
      };
    }
    case "UPDATE_REF": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "commitSha",
          "force",
          "token",
        ]) || !validCoordinates(operation) || !SHA.test(operation.commitSha) ||
        operation.force !== false
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/git/refs/heads/main`,
        init: jsonRequest("PATCH", operation.token, {
          sha: operation.commitSha,
          force: false,
        }),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: projectRef,
      };
    }
    case "WRITE_PROJECT_MARKER": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "message",
          "contentBase64",
          "token",
        ]) || !validCoordinates(operation) ||
        operation.message !== "chore: bind project context" ||
        !BASE64.test(operation.contentBase64) ||
        operation.contentBase64.length > Math.ceil(MARKER_BYTES / 3) * 4
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/contents/.lws/project.json`,
        init: jsonRequest("PUT", operation.token, {
          message: operation.message,
          content: operation.contentBase64,
        }),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: projectMarkerWrite,
      };
    }
    case "READ_PROJECT_MARKER": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "ref",
          "token",
        ]) || !validCoordinates(operation) || !SHA.test(operation.ref)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/contents/.lws/project.json?ref=${operation.ref}`,
        init: getRequest(operation.token),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: projectMarkerRead,
      };
    }
    case "COMMIT_METADATA": {
      if (
        !exactKeys(operation, [
          "kind",
          "owner",
          "repository",
          "commitSha",
          "token",
        ]) || !validCoordinates(operation) || !SHA.test(operation.commitSha)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.owner}/${operation.repository}/commits/${operation.commitSha}`,
        init: getRequest(operation.token),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: projectCommit,
      };
    }
    default:
      return invalidOperation();
  }
}

function invalidResponse(
  tokenAcquireSubphase?: GitHubTokenAcquireSubphase,
  boundary: GitHubHttpFailureBoundary = "RESPONSE_SCHEMA",
  tokenResponseCheck?: GitHubTokenResponseCheck,
): never {
  throw new GitHubHttpError(
    "GITHUB_HTTP_RESPONSE_INVALID",
    null,
    null,
    tokenAcquireSubphase,
    boundary,
    tokenResponseCheck,
  );
}

function validTreePath(path: string): boolean {
  return path.length > 0 && path.length <= 1024 && !path.startsWith("/") &&
    !path.includes("\\") && !path.split("/").includes("..") &&
    path !== ".lws/project.json";
}

function validBase64(value: string, maximumBytes: number): boolean {
  if (!BASE64.test(value) || value.length > Math.ceil(maximumBytes / 3) * 4) {
    return false;
  }
  try {
    return atob(value).length <= maximumBytes;
  } catch {
    return false;
  }
}

function stringField(
  value: Record<string, unknown>,
  key: string,
  pattern?: RegExp,
  tokenAcquireSubphase?: GitHubTokenAcquireSubphase,
  tokenResponseCheck?: GitHubTokenResponseCheck,
): string {
  const field = value[key];
  if (typeof field !== "string" || !field || pattern && !pattern.test(field)) {
    return invalidResponse(
      tokenAcquireSubphase,
      "RESPONSE_SCHEMA",
      tokenResponseCheck,
    );
  }
  return field;
}

function projectToken(
  value: unknown,
  expectedPermissions: GitHubInstallationPermissions,
  now: number,
): GitHubHttpResult {
  if (!isRecord(value)) {
    return invalidResponse(
      "TOKEN_RESPONSE_SCHEMA",
      "RESPONSE_SCHEMA",
      "TOKEN_SCHEMA_OBJECT",
    );
  }
  if (!validPermissions(value.permissions)) {
    return invalidResponse(
      "TOKEN_RESPONSE_SCHEMA",
      "RESPONSE_SCHEMA",
      "TOKEN_SCHEMA_PERMISSIONS_SHAPE",
    );
  }
  const token = stringField(
    value,
    "token",
    undefined,
    "TOKEN_RESPONSE_SCHEMA",
    "TOKEN_SCHEMA_TOKEN",
  );
  if (!isGitHubInstallationAccessToken(token)) {
    return invalidResponse(
      "TOKEN_RESPONSE_SCHEMA",
      "RESPONSE_SCHEMA",
      "TOKEN_SCHEMA_TOKEN",
    );
  }
  const expiresAt = stringField(
    value,
    "expires_at",
    undefined,
    "TOKEN_RESPONSE_SCHEMA",
    "TOKEN_SCHEMA_EXPIRY",
  );
  const expiry = Date.parse(expiresAt);
  if (
    !Number.isFinite(expiry) || expiry <= now ||
    expiry > now + 60 * 60 * 1000 + MAX_CLOCK_SKEW_MILLISECONDS
  ) {
    return invalidResponse(
      "TOKEN_RESPONSE_SCHEMA",
      "RESPONSE_SCHEMA",
      "TOKEN_SCHEMA_EXPIRY",
    );
  }
  const hasRepositorySelection = Object.hasOwn(
    value,
    "repository_selection",
  );
  const repositorySelection = value.repository_selection;
  if (
    hasRepositorySelection && repositorySelection !== "all" &&
    repositorySelection !== "selected"
  ) {
    return invalidResponse(
      "TOKEN_RESPONSE_SCHEMA",
      "RESPONSE_SCHEMA",
      "TOKEN_SCHEMA_REPOSITORY_SELECTION",
    );
  }
  if (!samePermissions(value.permissions, expectedPermissions)) {
    return invalidResponse(
      "TOKEN_RESPONSE_SCHEMA",
      "RESPONSE_SCHEMA",
      "TOKEN_SCHEMA_PERMISSION_PARITY",
    );
  }
  const result = {
    expiresAt,
    ...(hasRepositorySelection
      ? {
        repositorySelection: repositorySelection as "all" | "selected",
      }
      : {}),
    permissions: Object.freeze({ ...value.permissions }),
  } as {
    token: string;
    expiresAt: string;
    repositorySelection?: "all" | "selected";
    permissions: GitHubInstallationPermissions;
  };
  Object.defineProperty(result, "token", {
    value: token,
    writable: false,
    enumerable: false,
    configurable: false,
  });
  return Object.freeze(result);
}

function projectRepositoryInstallation(
  value: unknown,
  expectedInstallationId: string,
  expectedOrganization: string,
): Readonly<{ proven: true }> {
  if (!isRecord(value) || !isRecord(value.account)) return invalidResponse();
  if (
    typeof value.id !== "number" || !Number.isSafeInteger(value.id) ||
    String(value.id) !== expectedInstallationId ||
    value.account.login !== expectedOrganization ||
    value.account.type !== "Organization" ||
    value.target_type !== "Organization" ||
    value.repository_selection !== "selected" ||
    value.suspended_at !== null
  ) return invalidResponse();
  return Object.freeze({ proven: true as const });
}

function projectRepositoryEmptyProof(
  value: unknown,
  expectedOwner: string,
  expectedRepository: string,
  expectedRepositoryId: string,
): Readonly<{ empty: true }> {
  if (
    !isRecord(value) || !exactKeys(value, ["data"]) ||
    !isRecord(value.data) || !exactKeys(value.data, ["repository"]) ||
    !isRecord(value.data.repository) ||
    !exactKeys(value.data.repository, [
      "databaseId",
      "nameWithOwner",
      "isEmpty",
      "defaultBranchRef",
    ])
  ) return invalidResponse();
  const repository = value.data.repository;
  if (
    typeof repository.databaseId !== "number" ||
    !Number.isSafeInteger(repository.databaseId) ||
    String(repository.databaseId) !== expectedRepositoryId ||
    repository.nameWithOwner !== `${expectedOwner}/${expectedRepository}` ||
    repository.isEmpty !== true || repository.defaultBranchRef !== null
  ) return invalidResponse();
  return Object.freeze({ empty: true as const });
}

function projectRepository(value: unknown): GitHubRepositoryMetadata {
  if (!isRecord(value) || !isRecord(value.owner)) return invalidResponse();
  const repositoryId = typeof value.id === "number" &&
      Number.isSafeInteger(value.id) && value.id > 0
    ? String(value.id)
    : invalidResponse();
  const owner = stringField(value.owner, "login", OWNER);
  const name = stringField(value, "name", REPOSITORY);
  const fullName = stringField(value, "full_name");
  const defaultBranch = stringField(value, "default_branch", REPOSITORY);
  const createdAt = stringField(value, "created_at");
  if (
    fullName !== `${owner}/${name}` || typeof value.private !== "boolean" ||
    !Number.isFinite(Date.parse(createdAt))
  ) return invalidResponse();
  return Object.freeze({
    repositoryId,
    nodeId: stringField(value, "node_id"),
    owner,
    name,
    fullName,
    private: value.private,
    defaultBranch,
    description: value.description === null
      ? null
      : stringField(value, "description"),
    createdAt,
  });
}

function projectRefRead(value: unknown, expectedRef: string): GitHubHttpResult {
  if (!isRecord(value)) return invalidResponse();
  const ref = Object.getOwnPropertyDescriptor(value, "ref");
  const object = Object.getOwnPropertyDescriptor(value, "object");
  if (
    !ref || !("value" in ref) || ref.value !== expectedRef ||
    !object || !("value" in object) || !isRecord(object.value)
  ) return invalidResponse();
  const type = Object.getOwnPropertyDescriptor(object.value, "type");
  const sha = Object.getOwnPropertyDescriptor(object.value, "sha");
  if (
    !type || !("value" in type) || type.value !== "commit" ||
    !sha || !("value" in sha) || typeof sha.value !== "string" ||
    !SHA.test(sha.value)
  ) return invalidResponse();
  return Object.freeze({
    ref: expectedRef,
    commitSha: sha.value,
  });
}

function projectTree(value: unknown): GitHubHttpResult {
  if (
    !isRecord(value) || !SHA.test(String(value.sha || "")) ||
    value.truncated !== false || !Array.isArray(value.tree)
  ) return invalidResponse();
  const entries = value.tree.map((entry): GitHubTreeEntry => {
    if (!isRecord(entry)) return invalidResponse();
    const path = stringField(entry, "path");
    const mode = stringField(entry, "mode", /^[0-7]{6}$/);
    const type = entry.type;
    const sha = stringField(entry, "sha", SHA);
    if (
      path.length > 1024 || path.startsWith("/") || path.includes("\\") ||
      path.split("/").includes("..") ||
      !["blob", "tree", "commit"].includes(String(type))
    ) return invalidResponse();
    const projected: {
      path: string;
      mode: string;
      type: "blob" | "tree" | "commit";
      sha: string;
      size?: number;
    } = { path, mode, type: type as "blob" | "tree" | "commit", sha };
    if (entry.size !== undefined) {
      if (!Number.isSafeInteger(entry.size) || Number(entry.size) < 0) {
        return invalidResponse();
      }
      projected.size = Number(entry.size);
    }
    return Object.freeze(projected);
  });
  return Object.freeze({
    sha: String(value.sha),
    truncated: false as const,
    entries: Object.freeze(entries),
  });
}

function projectBlob(value: unknown): GitHubHttpResult {
  if (!isRecord(value) || value.encoding !== "base64") return invalidResponse();
  const contentBase64 = stringField(value, "content").replaceAll("\n", "");
  if (
    !Number.isSafeInteger(value.size) || Number(value.size) < 0 ||
    !validBase64(contentBase64, TREE_RESPONSE_BYTES) ||
    atob(contentBase64).length !== Number(value.size)
  ) return invalidResponse();
  return Object.freeze({
    sha: stringField(value, "sha", SHA),
    encoding: "base64" as const,
    contentBase64,
    size: Number(value.size),
  });
}

function projectSha(value: unknown): GitHubHttpResult {
  if (!isRecord(value)) return invalidResponse();
  return Object.freeze({ sha: stringField(value, "sha", SHA) });
}

function projectRef(value: unknown): GitHubHttpResult {
  if (
    !isRecord(value) || value.ref !== "refs/heads/main" ||
    !isRecord(value.object)
  ) return invalidResponse();
  return Object.freeze({
    ref: "refs/heads/main" as const,
    commitSha: stringField(value.object, "sha", SHA),
  });
}

function projectMarkerWrite(value: unknown): GitHubHttpResult {
  if (!isRecord(value) || !isRecord(value.content) || !isRecord(value.commit)) {
    return invalidResponse();
  }
  return Object.freeze({
    contentSha: stringField(value.content, "sha", SHA),
    commitSha: stringField(value.commit, "sha", SHA),
  });
}

function projectBootstrapWrite(value: unknown): GitHubHttpResult {
  if (
    !isRecord(value) || !isRecord(value.content) || !isRecord(value.commit) ||
    value.content.path !== ".lws/bootstrap.json" ||
    !Array.isArray(value.commit.parents)
  ) return invalidResponse();
  return Object.freeze({
    path: ".lws/bootstrap.json" as const,
    contentSha: stringField(value.content, "sha", SHA),
    commitSha: stringField(value.commit, "sha", SHA),
    parentCount: value.commit.parents.length,
  });
}

function projectBootstrapRead(value: unknown): GitHubHttpResult {
  if (!isRecord(value) || value.path !== ".lws/bootstrap.json") {
    return invalidResponse();
  }
  const contentBase64 = stringField(value, "content").replaceAll("\n", "");
  if (
    value.encoding !== "base64" ||
    !Number.isSafeInteger(value.size) || Number(value.size) < 0 ||
    Number(value.size) > BOOTSTRAP_BYTES ||
    !validBase64(contentBase64, BOOTSTRAP_BYTES) ||
    atob(contentBase64).length !== Number(value.size)
  ) return invalidResponse();
  return Object.freeze({
    path: ".lws/bootstrap.json" as const,
    sha: stringField(value, "sha", SHA),
    encoding: "base64" as const,
    contentBase64,
    size: Number(value.size),
  });
}

function projectBootstrapCommit(value: unknown): GitHubHttpResult {
  if (
    !isRecord(value) || !isRecord(value.tree) || !Array.isArray(value.parents)
  ) return invalidResponse();
  return Object.freeze({
    sha: stringField(value, "sha", SHA),
    treeSha: stringField(value.tree, "sha", SHA),
    parentCount: value.parents.length,
  });
}

function projectMarkerRead(value: unknown): GitHubHttpResult {
  if (!isRecord(value) || value.path !== ".lws/project.json") {
    return invalidResponse();
  }
  const contentBase64 = stringField(value, "content").replaceAll("\n", "");
  let decodedLength: number;
  try {
    decodedLength = atob(contentBase64).length;
  } catch {
    return invalidResponse();
  }
  if (
    value.encoding !== "base64" || !BASE64.test(contentBase64) ||
    !Number.isSafeInteger(value.size) || Number(value.size) < 0 ||
    Number(value.size) > MARKER_BYTES || Number(value.size) !== decodedLength
  ) return invalidResponse();
  return Object.freeze({
    path: ".lws/project.json" as const,
    sha: stringField(value, "sha", SHA),
    encoding: "base64" as const,
    contentBase64,
    size: Number(value.size),
  });
}

function projectCommit(value: unknown): GitHubHttpResult {
  if (
    !isRecord(value) || !isRecord(value.commit) ||
    !isRecord(value.commit.tree)
  ) return invalidResponse();
  return Object.freeze({
    sha: stringField(value, "sha", SHA),
    treeSha: stringField(value.commit.tree, "sha", SHA),
  });
}

function safeRequestId(response: Response): string | null {
  const value = response.headers.get("x-github-request-id");
  return value && /^[A-Za-z0-9_.:-]{1,128}$/.test(value) ? value : null;
}

function retryAt(response: Response, now: number): string | null {
  const retryAfter = response.headers.get("retry-after");
  if (retryAfter && /^\d{1,6}$/.test(retryAfter)) {
    return new Date(now + Number(retryAfter) * 1000).toISOString();
  }
  if (retryAfter) {
    const timestamp = Date.parse(retryAfter);
    if (Number.isFinite(timestamp) && timestamp > now) {
      return new Date(timestamp).toISOString();
    }
  }
  const reset = response.headers.get("x-ratelimit-reset");
  if (reset && /^\d{10}$/.test(reset)) {
    return new Date(Number(reset) * 1000).toISOString();
  }
  return null;
}

function statusError(response: Response, now: number): GitHubHttpError {
  const requestId = safeRequestId(response);
  const rateLimited = response.status === 429 || response.status === 403 &&
      (response.headers.get("x-ratelimit-remaining") === "0" ||
        response.headers.has("retry-after"));
  if (rateLimited) {
    return new GitHubHttpError(
      "GITHUB_HTTP_RATE_LIMITED",
      requestId,
      retryAt(response, now),
      undefined,
      "HTTP_STATUS",
    );
  }
  const code: GitHubHttpErrorCode = response.status === 401
    ? "GITHUB_HTTP_UNAUTHORIZED"
    : response.status === 403
    ? "GITHUB_HTTP_FORBIDDEN"
    : response.status === 404
    ? "GITHUB_HTTP_NOT_FOUND"
    : response.status === 409 || response.status === 422
    ? "GITHUB_HTTP_CONFLICT"
    : response.status >= 500
    ? "GITHUB_HTTP_SERVER_ERROR"
    : "GITHUB_HTTP_FAILED";
  return new GitHubHttpError(
    code,
    requestId,
    null,
    undefined,
    "HTTP_STATUS",
    undefined,
    response.status,
  );
}

async function boundedJson(
  response: Response,
  maximumBytes: number,
  tokenExchange: boolean,
): Promise<unknown> {
  const contentType = response.headers.get("content-type") || "";
  if (!/^application\/(?:[a-z0-9.+-]*\+)?json(?:\s*;|$)/i.test(contentType)) {
    return invalidResponse(
      tokenExchange ? "TOKEN_CONTENT_TYPE_VALIDATE" : undefined,
      "CONTENT_TYPE",
    );
  }
  const declaredLength = response.headers.get("content-length");
  if (
    declaredLength && /^\d+$/.test(declaredLength) &&
    Number(declaredLength) > maximumBytes
  ) {
    throw new GitHubHttpError(
      "GITHUB_HTTP_RESPONSE_TOO_LARGE",
      null,
      null,
      tokenExchange ? "TOKEN_RESPONSE_BODY_READ" : undefined,
      "BODY_READ",
    );
  }
  if (!response.body) {
    return invalidResponse(
      tokenExchange ? "TOKEN_RESPONSE_BODY_READ" : undefined,
      "BODY_READ",
    );
  }
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maximumBytes) {
        await reader.cancel();
        throw new GitHubHttpError(
          "GITHUB_HTTP_RESPONSE_TOO_LARGE",
          null,
          null,
          tokenExchange ? "TOKEN_RESPONSE_BODY_READ" : undefined,
          "BODY_READ",
        );
      }
      chunks.push(value);
    }
  } catch (error) {
    if (isTrustedGitHubHttpError(error)) throw error;
    if (tokenExchange) {
      throw new GitHubHttpError(
        "GITHUB_HTTP_NETWORK_ERROR",
        null,
        null,
        "TOKEN_RESPONSE_BODY_READ",
        "BODY_READ",
      );
    }
    throw new GitHubHttpError(
      "GITHUB_HTTP_NETWORK_ERROR",
      null,
      null,
      undefined,
      "BODY_READ",
    );
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    return invalidResponse(
      tokenExchange ? "TOKEN_JSON_PARSE" : undefined,
      "JSON_PARSE",
    );
  }
}

function allowedRedirect(
  location: string | null,
  method: string,
): string | null {
  if (!location || method !== "GET") return null;
  let target: URL;
  try {
    target = new URL(location);
  } catch {
    return null;
  }
  return target.protocol === "https:" &&
      ALLOWED_REDIRECT_HOSTS.has(target.hostname) &&
      (target.port === "" || target.port === "443") &&
      target.username === "" && target.password === ""
    ? target.href
    : null;
}

function isRedirect(response: Response): boolean {
  return [301, 302, 303, 307, 308].includes(response.status);
}

export function createGitHubHttpClient(
  dependencies: GitHubHttpClientDependencies,
): GitHubHttpClient {
  const timeoutMilliseconds = dependencies.timeoutMilliseconds ??
    DEFAULT_TIMEOUT_MILLISECONDS;
  if (
    typeof dependencies.fetch !== "function" ||
    !Number.isSafeInteger(timeoutMilliseconds) || timeoutMilliseconds < 1 ||
    timeoutMilliseconds > 60_000
  ) throw new GitHubHttpError("GITHUB_HTTP_OPERATION_INVALID");
  const now = dependencies.now ?? Date.now;

  return Object.freeze({
    async execute(
      operation: GitHubHttpOperation,
      signal?: AbortSignal,
    ): Promise<GitHubHttpResult> {
      const tokenExchange = isRecord(operation) &&
        operation.kind === "TOKEN_EXCHANGE";
      const projectFilesRead = isRecord(operation) &&
        typeof operation.kind === "string" &&
        operation.kind.startsWith("WEBSITE_PROJECT_FILES_");
      if (projectFilesRead && !(signal instanceof AbortSignal)) {
        throw new GitHubHttpError("GITHUB_HTTP_OPERATION_INVALID");
      }
      const request = prepare(operation, now);
      const controller = projectFilesRead ? null : new AbortController();
      const timeout = controller === null
        ? null
        : setTimeout(() => controller.abort(), timeoutMilliseconds);
      const requestSignal = projectFilesRead ? signal : controller!.signal;
      const init = { ...request.init, signal: requestSignal };
      try {
        let response = await dependencies.fetch(request.url, init);
        if (isRedirect(response)) {
          if (projectFilesRead) {
            throw new GitHubHttpError(
              "GITHUB_HTTP_REDIRECT_DENIED",
              null,
              null,
              undefined,
              "HTTP_STATUS",
            );
          }
          const target = allowedRedirect(
            response.headers.get("location"),
            String(init.method),
          );
          if (!target) {
            throw new GitHubHttpError(
              "GITHUB_HTTP_REDIRECT_DENIED",
              null,
              null,
              tokenExchange ? "TOKEN_HTTP_STATUS" : undefined,
              "HTTP_STATUS",
            );
          }
          const redirectedHeaders = new Headers(init.headers);
          if (new URL(target).origin !== new URL(request.url).origin) {
            redirectedHeaders.delete("authorization");
          }
          response = await dependencies.fetch(target, {
            ...init,
            headers: redirectedHeaders,
          });
          if (isRedirect(response)) {
            throw new GitHubHttpError(
              "GITHUB_HTTP_REDIRECT_DENIED",
              null,
              null,
              tokenExchange ? "TOKEN_HTTP_STATUS" : undefined,
              "HTTP_STATUS",
            );
          }
        }
        if (!response.ok) {
          const error = statusError(response, now());
          throw tokenExchange
            ? new GitHubHttpError(
              error.code,
              error.requestId,
              error.retryAt,
              "TOKEN_HTTP_STATUS",
              error.boundary,
            )
            : error;
        }
        if (
          request.successStatus !== undefined &&
          response.status !== request.successStatus
        ) {
          throw new GitHubHttpError(
            "GITHUB_HTTP_FAILED",
            safeRequestId(response),
            null,
            undefined,
            "HTTP_STATUS",
          );
        }
        return request.project(
          await boundedJson(response, request.responseBytes, tokenExchange),
        );
      } catch (error) {
        if (isTrustedGitHubHttpError(error)) throw error;
        if (requestSignal?.aborted) {
          throw new GitHubHttpError(
            "GITHUB_HTTP_TIMEOUT",
            null,
            null,
            tokenExchange ? "TOKEN_HTTP_REQUEST" : undefined,
            "HTTP_REQUEST",
          );
        }
        throw new GitHubHttpError(
          "GITHUB_HTTP_NETWORK_ERROR",
          null,
          null,
          tokenExchange ? "TOKEN_HTTP_REQUEST" : undefined,
          "HTTP_REQUEST",
        );
      } finally {
        if (timeout !== null) clearTimeout(timeout);
      }
    },
  });
}
