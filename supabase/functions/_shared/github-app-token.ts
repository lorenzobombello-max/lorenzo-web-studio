import type {
  GitHubAppConfig,
  GitHubProviderTarget,
} from "./github-app-config.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const ORGANIZATION = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/;
const MAX_TOKEN_LIFETIME_MS = 60 * 60 * 1000;

export type GitHubTokenOperation =
  | "TEMPLATE_GENERATION"
  | "REPOSITORY_CONTENTS";

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
  exchange(input: GitHubTokenExchangeInput): Promise<unknown>;
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

export class GitHubTokenBrokerError extends Error {
  readonly code: string;

  constructor(code: string) {
    super(code);
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

function validRepositoryIds(value: unknown): value is readonly string[] {
  return Array.isArray(value) && value.length === 1 &&
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
    !validRepositoryIds(request.repositoryIds) ||
    !validRepositoryIds(authority.repositoryIds) ||
    !sameValues(request.repositoryIds, authority.repositoryIds) ||
    !["TEMPLATE_GENERATION", "REPOSITORY_CONTENTS"].includes(request.operation)
  ) return false;

  return request.operation !== "TEMPLATE_GENERATION" ||
    request.repositoryIds[0] === config.templateRepositoryId;
}

function permissionsFor(
  operation: GitHubTokenOperation,
): GitHubInstallationPermissions {
  return operation === "TEMPLATE_GENERATION"
    ? Object.freeze({ metadata: "read", administration: "write" })
    : Object.freeze({ metadata: "read", contents: "write" });
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
    throw new GitHubTokenBrokerError("GITHUB_TOKEN_RESPONSE_INVALID");
  }
  const response = value as Record<string, unknown>;
  const token = String(response.token || "");
  const expiresAt = String(response.expiresAt || "");
  const expiry = Date.parse(expiresAt);
  if (
    !exactKeys(response, [
      "token",
      "expiresAt",
      "repositorySelection",
      "permissions",
    ]) || !/^[A-Za-z0-9_]{20,512}$/.test(token) ||
    response.repositorySelection !== "selected" ||
    !samePermissions(response.permissions, expectedPermissions) ||
    !Number.isFinite(expiry) || expiry <= now ||
    expiry > now + MAX_TOKEN_LIFETIME_MS
  ) throw new GitHubTokenBrokerError("GITHUB_TOKEN_RESPONSE_INVALID");
  return { token, expiresAt };
}

function normalizedExchangeError(error: unknown): GitHubTokenBrokerError {
  if (error instanceof GitHubTokenExchangeFailure) {
    const codes: Record<GitHubTokenExchangeFailureKind, string> = {
      TIMEOUT: "GITHUB_TOKEN_TIMEOUT",
      RATE_LIMITED: "GITHUB_TOKEN_RATE_LIMITED",
      FORBIDDEN: "GITHUB_TOKEN_FORBIDDEN",
      UNEXPECTED_REDIRECT: "GITHUB_TOKEN_REDIRECT_DENIED",
    };
    return new GitHubTokenBrokerError(codes[error.kind]);
  }
  return new GitHubTokenBrokerError("GITHUB_TOKEN_EXCHANGE_FAILED");
}

export function createGitHubAppTokenBroker(
  dependencies: GitHubAppTokenBrokerDependencies,
) {
  return Object.freeze({
    async issue(
      config: GitHubAppConfig,
      request: GitHubTokenRequest,
      authority: GitHubTokenAuthority,
    ): Promise<GitHubInstallationTokenLease> {
      if (!validAuthority(config, request, authority)) {
        throw new GitHubTokenBrokerError("GITHUB_TOKEN_AUTHORITY_INVALID");
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
        throw new GitHubTokenBrokerError("GITHUB_APP_SIGNING_FAILED");
      }
      if (!(signature instanceof Uint8Array) || signature.length === 0) {
        throw new GitHubTokenBrokerError("GITHUB_APP_SIGNING_FAILED");
      }
      const appJwt = `${signingInput}.${base64Url(signature)}`;
      const permissions = permissionsFor(request.operation);
      let rawResponse: unknown;
      try {
        rawResponse = await dependencies.exchange(Object.freeze({
          installationId: config.installationId,
          appJwt,
          repositoryIds: Object.freeze([...request.repositoryIds]),
          permissions,
        }));
      } catch (error) {
        throw normalizedExchangeError(error);
      }
      const response = validateResponse(rawResponse, permissions, now);
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
