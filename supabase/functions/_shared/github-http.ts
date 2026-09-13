import type { GitHubInstallationPermissions } from "./github-app-token.ts";

const API_ORIGIN = "https://api.github.com";
const ALLOWED_REDIRECT_HOSTS = new Set(["api.github.com", "github.com"]);
const API_VERSION = "2022-11-28";
const JSON_MEDIA_TYPE = "application/vnd.github+json";
const DEFAULT_TIMEOUT_MILLISECONDS = 10_000;
const SMALL_RESPONSE_BYTES = 256 * 1024;
const TREE_RESPONSE_BYTES = 8 * 1024 * 1024;
const MARKER_BYTES = 64 * 1024;
const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const OWNER = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/;
const REPOSITORY = /^[A-Za-z0-9._-]{1,100}$/;
const SHA = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const TOKEN = /^[^\s]{20,512}$/;
const APP_JWT = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;

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
  | (RepositoryCoordinates & Readonly<{ kind: "REPOSITORY_METADATA" }>)
  | (
    & RepositoryCoordinates
    & Readonly<{
      kind: "REPOSITORY_TREE";
      treeRef: string;
    }>
  )
  | Readonly<{
    kind: "GENERATE_REPOSITORY";
    templateOwner: string;
    templateRepository: string;
    owner: string;
    repository: string;
    description: string;
    token: string;
  }>
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
    repositorySelection: "selected";
    permissions: GitHubInstallationPermissions;
  }>
  | GitHubRepositoryMetadata
  | Readonly<{
    sha: string;
    truncated: false;
    entries: readonly GitHubTreeEntry[];
  }>
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

export class GitHubHttpError extends Error {
  constructor(
    readonly code: GitHubHttpErrorCode,
    readonly requestId: string | null = null,
    readonly retryAt: string | null = null,
  ) {
    super(code);
    this.name = "GitHubHttpError";
  }
}

export type GitHubHttpClient = Readonly<{
  execute(operation: GitHubHttpOperation): Promise<GitHubHttpResult>;
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
    TOKEN.test(value.token);
}

function validRepositoryName(value: string): boolean {
  return REPOSITORY.test(value) && value !== "." && value !== "..";
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
  method: "POST" | "PUT",
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

function invalidOperation(): never {
  throw new GitHubHttpError("GITHUB_HTTP_OPERATION_INVALID");
}

function prepare(operation: GitHubHttpOperation, now: number): PreparedRequest {
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
        operation.repositoryIds.length !== 1 ||
        !validNumericId(operation.repositoryIds[0]) ||
        !validPermissions(operation.permissions)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/app/installations/${operation.installationId}/access_tokens`,
        init: jsonRequest("POST", operation.appJwt, {
          repository_ids: operation.repositoryIds.map(Number),
          permissions: operation.permissions,
        }),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: (value) => projectToken(value, operation.permissions, now),
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
    case "GENERATE_REPOSITORY": {
      if (
        !exactKeys(operation, [
          "kind",
          "templateOwner",
          "templateRepository",
          "owner",
          "repository",
          "description",
          "token",
        ]) || !OWNER.test(operation.templateOwner) ||
        !validRepositoryName(operation.templateRepository) ||
        !OWNER.test(operation.owner) ||
        !validRepositoryName(operation.repository) ||
        !TOKEN.test(operation.token) || !operation.description ||
        operation.description.length > 256 ||
        /[\r\n]/.test(operation.description)
      ) return invalidOperation();
      return {
        url:
          `${API_ORIGIN}/repos/${operation.templateOwner}/${operation.templateRepository}/generate`,
        init: jsonRequest("POST", operation.token, {
          owner: operation.owner,
          name: operation.repository,
          description: operation.description,
          include_all_branches: false,
          private: true,
        }),
        responseBytes: SMALL_RESPONSE_BYTES,
        project: projectRepository,
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

function invalidResponse(): never {
  throw new GitHubHttpError("GITHUB_HTTP_RESPONSE_INVALID");
}

function stringField(
  value: Record<string, unknown>,
  key: string,
  pattern?: RegExp,
): string {
  const field = value[key];
  if (typeof field !== "string" || !field || pattern && !pattern.test(field)) {
    return invalidResponse();
  }
  return field;
}

function projectToken(
  value: unknown,
  expectedPermissions: GitHubInstallationPermissions,
  now: number,
): GitHubHttpResult {
  if (!isRecord(value) || !validPermissions(value.permissions)) {
    return invalidResponse();
  }
  const token = stringField(value, "token", TOKEN);
  const expiresAt = stringField(value, "expires_at");
  const expiry = Date.parse(expiresAt);
  if (
    !Number.isFinite(expiry) || expiry <= now ||
    expiry > now + 60 * 60 * 1000 ||
    value.repository_selection !== "selected" ||
    !samePermissions(value.permissions, expectedPermissions)
  ) return invalidResponse();
  const result = {
    expiresAt,
    repositorySelection: "selected" as const,
    permissions: Object.freeze({ ...value.permissions }),
  } as {
    token: string;
    expiresAt: string;
    repositorySelection: "selected";
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
  if (
    fullName !== `${owner}/${name}` || typeof value.private !== "boolean"
  ) return invalidResponse();
  return Object.freeze({
    repositoryId,
    nodeId: stringField(value, "node_id"),
    owner,
    name,
    fullName,
    private: value.private,
    defaultBranch,
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

function projectMarkerWrite(value: unknown): GitHubHttpResult {
  if (!isRecord(value) || !isRecord(value.content) || !isRecord(value.commit)) {
    return invalidResponse();
  }
  return Object.freeze({
    contentSha: stringField(value.content, "sha", SHA),
    commitSha: stringField(value.commit, "sha", SHA),
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
  return new GitHubHttpError(code, requestId);
}

async function boundedJson(
  response: Response,
  maximumBytes: number,
): Promise<unknown> {
  const contentType = response.headers.get("content-type") || "";
  if (!/^application\/(?:[a-z0-9.+-]*\+)?json(?:\s*;|$)/i.test(contentType)) {
    return invalidResponse();
  }
  const declaredLength = response.headers.get("content-length");
  if (
    declaredLength && /^\d+$/.test(declaredLength) &&
    Number(declaredLength) > maximumBytes
  ) throw new GitHubHttpError("GITHUB_HTTP_RESPONSE_TOO_LARGE");
  if (!response.body) return invalidResponse();
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
        throw new GitHubHttpError("GITHUB_HTTP_RESPONSE_TOO_LARGE");
      }
      chunks.push(value);
    }
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
    return invalidResponse();
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
    async execute(operation: GitHubHttpOperation): Promise<GitHubHttpResult> {
      const request = prepare(operation, now());
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), timeoutMilliseconds);
      const init = { ...request.init, signal: controller.signal };
      try {
        let response = await dependencies.fetch(request.url, init);
        if (isRedirect(response)) {
          const target = allowedRedirect(
            response.headers.get("location"),
            String(init.method),
          );
          if (!target) {
            throw new GitHubHttpError("GITHUB_HTTP_REDIRECT_DENIED");
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
            throw new GitHubHttpError("GITHUB_HTTP_REDIRECT_DENIED");
          }
        }
        if (!response.ok) throw statusError(response, now());
        return request.project(
          await boundedJson(response, request.responseBytes),
        );
      } catch (error) {
        if (error instanceof GitHubHttpError) throw error;
        if (
          controller.signal.aborted ||
          error instanceof DOMException && error.name === "AbortError"
        ) {
          throw new GitHubHttpError("GITHUB_HTTP_TIMEOUT");
        }
        throw new GitHubHttpError("GITHUB_HTTP_NETWORK_ERROR");
      } finally {
        clearTimeout(timeout);
      }
    },
  });
}
