import type {
  GitHubAppConfig,
  GitHubProviderTarget,
} from "./github-app-config.ts";
import {
  GitHubTokenAcquireDiagnosticError,
  type GitHubTokenAcquireSubphase,
  type GitHubTokenLeaseCheck,
  type GitHubTokenResponseCheck,
  hasValidatedGitHubTokenResponseCheck,
} from "./repository-provisioning-diagnostics.ts";
import { isGitHubInstallationAccessToken } from "./github-installation-token.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const ORGANIZATION = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/;
const MAX_TOKEN_LIFETIME_MS = 60 * 60 * 1000;
const MAX_CLOCK_SKEW_MS = 60 * 1000;

export type GitHubTokenOperation =
  | "STARTER_SNAPSHOT_READ"
  | "WEBSITE_PROJECT_FILES_READ"
  | "WEBSITE_PROJECT_FILES_WRITE"
  | "LAB_REPOSITORY_CREATE"
  | "LAB_REPOSITORY_READ"
  | "LAB_REPOSITORY_WRITE";

export type GitHubTokenRequest = Readonly<{
  websiteWorkContextId: string;
  target: GitHubProviderTarget;
  organization: string;
  operation: GitHubTokenOperation;
  repositoryIds: readonly string[];
}>;

export type GitHubTokenAuthority = Readonly<{
  websiteWorkContextId: string;
  target: GitHubProviderTarget;
  organization: string;
  repositoryIds: readonly string[];
}>;

export type GitHubInstallationPermissions =
  | Readonly<{ metadata: "read"; administration: "write" }>
  | Readonly<{ metadata: "read"; contents: "read" }>
  | Readonly<{ metadata: "read"; contents: "write" }>;

export type GitHubTokenExchangeInput = Readonly<{
  installationId: string;
  appJwt: string;
  repositoryIds: readonly string[];
  permissions: GitHubInstallationPermissions;
}>;

export type GitHubInstallationTokenLease = Readonly<{
  token: string;
  expiresAt: string;
}>;

export type GitHubAppTokenBrokerDependencies = Readonly<{
  now(): number;
  sign(privateKey: string, signingInput: string): Promise<Uint8Array>;
  exchange(
    input: GitHubTokenExchangeInput,
    signal?: AbortSignal,
  ): Promise<unknown>;
}>;

export type GitHubTokenExchangeFailureKind =
  | "TIMEOUT"
  | "RATE_LIMITED"
  | "FORBIDDEN"
  | "UNEXPECTED_REDIRECT";

export class GitHubTokenExchangeFailure extends Error {
  constructor(readonly kind: GitHubTokenExchangeFailureKind) {
    super("GITHUB_TOKEN_EXCHANGE_FAILURE");
    this.name = "GitHubTokenExchangeFailure";
  }
}

export class GitHubTokenBrokerError extends GitHubTokenAcquireDiagnosticError {
  readonly code: string;

  constructor(
    code: string,
    tokenAcquireSubphase?: GitHubTokenAcquireSubphase,
    tokenLeaseCheck?: GitHubTokenLeaseCheck,
    tokenResponseCheck?: GitHubTokenResponseCheck,
  ) {
    super(code, tokenAcquireSubphase, tokenLeaseCheck, tokenResponseCheck);
    this.name = "GitHubTokenBrokerError";
    this.code = code;
  }
}

function exactKeys(value: object, keys: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === keys.length && keys.every((key) => key in value);
}

function sameValues(
  left: readonly string[],
  right: readonly string[],
): boolean {
  return left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

function validRepositoryIds(
  value: unknown,
  expectedLength: 0 | 1,
): value is readonly string[] {
  return Array.isArray(value) && value.length === expectedLength &&
    value.every((id) => typeof id === "string" && NUMERIC_ID.test(id));
}

function validAuthority(
  config: GitHubAppConfig,
  request: GitHubTokenRequest,
  authority: GitHubTokenAuthority,
): boolean {
  if (
    !exactKeys(request, [
      "websiteWorkContextId",
      "target",
      "organization",
      "operation",
      "repositoryIds",
    ]) ||
    !exactKeys(authority, [
      "websiteWorkContextId",
      "target",
      "organization",
      "repositoryIds",
    ]) ||
    !UUID.test(request.websiteWorkContextId) ||
    request.websiteWorkContextId !== authority.websiteWorkContextId ||
    request.target !== authority.target || request.target !== config.target ||
    !ORGANIZATION.test(request.organization) ||
    request.organization !== authority.organization ||
    request.organization !== config.organization ||
    ![
      "STARTER_SNAPSHOT_READ",
      "WEBSITE_PROJECT_FILES_READ",
      "WEBSITE_PROJECT_FILES_WRITE",
      "LAB_REPOSITORY_CREATE",
      "LAB_REPOSITORY_READ",
      "LAB_REPOSITORY_WRITE",
    ]
      .includes(request.operation)
  ) return false;

  const repositoryCount = request.operation === "LAB_REPOSITORY_CREATE" ? 0 : 1;
  if (
    !validRepositoryIds(request.repositoryIds, repositoryCount) ||
    !validRepositoryIds(authority.repositoryIds, repositoryCount) ||
    !sameValues(request.repositoryIds, authority.repositoryIds)
  ) return false;

  if (request.operation === "LAB_REPOSITORY_CREATE") {
    return request.target === "TEST";
  }
  if (request.operation === "STARTER_SNAPSHOT_READ") {
    return request.target === "PRODUCTION" &&
      request.repositoryIds[0] === config.templateRepositoryId;
  }
  if (request.operation === "WEBSITE_PROJECT_FILES_READ") return true;
  if (request.operation === "WEBSITE_PROJECT_FILES_WRITE") return true;
  return request.target === "TEST";
}

function permissionsFor(
  operation: GitHubTokenOperation,
): GitHubInstallationPermissions {
  if (operation === "STARTER_SNAPSHOT_READ") {
    return Object.freeze({ metadata: "read", contents: "read" });
  }
  if (operation === "LAB_REPOSITORY_READ") {
    return Object.freeze({ metadata: "read", contents: "read" });
  }
  if (operation === "WEBSITE_PROJECT_FILES_READ") {
    return Object.freeze({ metadata: "read", contents: "read" });
  }
  if (operation === "WEBSITE_PROJECT_FILES_WRITE") {
    return Object.freeze({ metadata: "read", contents: "write" });
  }
  if (operation === "LAB_REPOSITORY_CREATE") {
    return Object.freeze({ metadata: "read", administration: "write" });
  }
  return Object.freeze({ metadata: "read", contents: "write" });
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}

function encodeJson(value: Record<string, unknown>): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function samePermissions(
  value: unknown,
  expected: GitHubInstallationPermissions,
): boolean {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const permissions = value as Record<string, unknown>;
  return exactKeys(permissions, Object.keys(expected)) &&
    Object.entries(expected).every(([key, level]) =>
      permissions[key] === level
    );
}

function validateResponse(
  value: unknown,
  expectedPermissions: GitHubInstallationPermissions,
  now: number,
): Readonly<{ token: string; expiresAt: string }> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new GitHubTokenBrokerError(
      "GITHUB_TOKEN_RESPONSE_INVALID",
      "TOKEN_LEASE_VALIDATE",
    );
  }
  const response = value as Record<string, unknown>;
  const token = String(response.token || "");
  const expiresAt = String(response.expiresAt || "");
  const expiry = Date.parse(expiresAt);
  const hasRepositorySelection = Object.hasOwn(
    response,
    "repositorySelection",
  );
  if (
    !exactKeys(
      response,
      hasRepositorySelection
        ? ["token", "expiresAt", "repositorySelection", "permissions"]
        : ["token", "expiresAt", "permissions"],
    )
  ) {
    throw new GitHubTokenBrokerError(
      "GITHUB_TOKEN_RESPONSE_INVALID",
      "TOKEN_LEASE_VALIDATE",
    );
  }
  if (!isGitHubInstallationAccessToken(token)) {
    throw new GitHubTokenBrokerError(
      "GITHUB_TOKEN_RESPONSE_INVALID",
      "TOKEN_LEASE_VALIDATE",
      "LEASE_TOKEN_FORMAT_VALIDATE",
    );
  }
  if (
    hasRepositorySelection && response.repositorySelection !== "all" &&
    response.repositorySelection !== "selected"
  ) {
    throw new GitHubTokenBrokerError(
      "GITHUB_TOKEN_RESPONSE_INVALID",
      "TOKEN_LEASE_VALIDATE",
    );
  }
  if (!samePermissions(response.permissions, expectedPermissions)) {
    throw new GitHubTokenBrokerError(
      "GITHUB_TOKEN_RESPONSE_INVALID",
      "TOKEN_LEASE_VALIDATE",
    );
  }
  if (!Number.isFinite(expiry)) {
    throw new GitHubTokenBrokerError(
      "GITHUB_TOKEN_RESPONSE_INVALID",
      "TOKEN_LEASE_VALIDATE",
    );
  }
  if (expiry <= now) {
    throw new GitHubTokenBrokerError(
      "GITHUB_TOKEN_RESPONSE_INVALID",
      "TOKEN_LEASE_VALIDATE",
      "LEASE_EXPIRY_LOWER_BOUND",
    );
  }
  if (expiry > now + MAX_TOKEN_LIFETIME_MS + MAX_CLOCK_SKEW_MS) {
    throw new GitHubTokenBrokerError(
      "GITHUB_TOKEN_RESPONSE_INVALID",
      "TOKEN_LEASE_VALIDATE",
      "LEASE_EXPIRY_UPPER_BOUND",
    );
  }
  return { token, expiresAt };
}

function normalizedExchangeError(error: unknown): GitHubTokenBrokerError {
  if (error instanceof GitHubTokenAcquireDiagnosticError) {
    return new GitHubTokenBrokerError(
      "GITHUB_TOKEN_EXCHANGE_FAILED",
      error.tokenAcquireSubphase,
      error.tokenLeaseCheck,
      hasValidatedGitHubTokenResponseCheck(error)
        ? error.tokenResponseCheck
        : undefined,
    );
  }
  if (error instanceof GitHubTokenExchangeFailure) {
    const codes: Record<GitHubTokenExchangeFailureKind, string> = {
      TIMEOUT: "GITHUB_TOKEN_TIMEOUT",
      RATE_LIMITED: "GITHUB_TOKEN_RATE_LIMITED",
      FORBIDDEN: "GITHUB_TOKEN_FORBIDDEN",
      UNEXPECTED_REDIRECT: "GITHUB_TOKEN_REDIRECT_DENIED",
    };
    const subphase = error.kind === "TIMEOUT"
      ? "TOKEN_HTTP_REQUEST"
      : "TOKEN_HTTP_STATUS";
    return new GitHubTokenBrokerError(codes[error.kind], subphase);
  }
  return new GitHubTokenBrokerError(
    "GITHUB_TOKEN_EXCHANGE_FAILED",
    "TOKEN_ADAPTER_PROJECT",
  );
}

export function createGitHubAppTokenBroker(
  dependencies: GitHubAppTokenBrokerDependencies,
) {
  return Object.freeze({
    async issue(
      config: GitHubAppConfig,
      request: GitHubTokenRequest,
      authority: GitHubTokenAuthority,
      signal?: AbortSignal,
    ): Promise<GitHubInstallationTokenLease> {
      if (!validAuthority(config, request, authority)) {
        throw new GitHubTokenBrokerError(
          "GITHUB_TOKEN_AUTHORITY_INVALID",
          "TOKEN_AUTHORITY_VALIDATE",
        );
      }
      const now = dependencies.now();
      const issuedAt = Math.floor(now / 1000) - 60;
      const expiresAt = Math.floor(now / 1000) + 540;
      const signingInput = [
        encodeJson({ alg: "RS256", typ: "JWT" }),
        encodeJson({ iat: issuedAt, exp: expiresAt, iss: config.appId }),
      ].join(".");
      let signature: Uint8Array;
      try {
        signature = await dependencies.sign(config.privateKey, signingInput);
      } catch {
        throw new GitHubTokenBrokerError(
          "GITHUB_APP_SIGNING_FAILED",
          "TOKEN_JWT_SIGN",
        );
      }
      if (!(signature instanceof Uint8Array) || signature.length === 0) {
        throw new GitHubTokenBrokerError(
          "GITHUB_APP_SIGNING_FAILED",
          "TOKEN_JWT_SIGN",
        );
      }
      const appJwt = `${signingInput}.${base64Url(signature)}`;
      const permissions = permissionsFor(request.operation);
      let rawResponse: unknown;
      try {
        rawResponse = await dependencies.exchange(
          Object.freeze({
            installationId: config.installationId,
            appJwt,
            repositoryIds: Object.freeze([...request.repositoryIds]),
            permissions,
          }),
          signal,
        );
      } catch (error) {
        throw normalizedExchangeError(error);
      }
      const response = validateResponse(
        rawResponse,
        permissions,
        dependencies.now(),
      );
      const lease = { expiresAt: response.expiresAt };
      Object.defineProperty(lease, "token", {
        value: response.token,
        enumerable: false,
        configurable: false,
        writable: false,
      });
      return Object.freeze(lease) as GitHubInstallationTokenLease;
    },
  });
}
