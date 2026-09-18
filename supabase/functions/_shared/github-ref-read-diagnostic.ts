function pair<const Boundary extends string, const Code extends string>(
  boundary: Boundary,
  code: Code,
) {
  return Object.freeze([boundary, code] as const);
}

export const GITHUB_REF_READ_DIAGNOSTIC_COMBINATIONS = Object.freeze(
  [
    pair("REQUEST_PREPARE", "GITHUB_HTTP_OPERATION_INVALID"),
    pair("HTTP_REQUEST", "GITHUB_HTTP_TIMEOUT"),
    pair("HTTP_REQUEST", "GITHUB_HTTP_NETWORK_ERROR"),
    pair("HTTP_STATUS", "GITHUB_HTTP_REDIRECT_DENIED"),
    pair("HTTP_STATUS", "GITHUB_HTTP_UNAUTHORIZED"),
    pair("HTTP_STATUS", "GITHUB_HTTP_FORBIDDEN"),
    pair("HTTP_STATUS", "GITHUB_HTTP_NOT_FOUND"),
    pair("HTTP_STATUS", "GITHUB_HTTP_CONFLICT"),
    pair("HTTP_STATUS", "GITHUB_HTTP_RATE_LIMITED"),
    pair("HTTP_STATUS", "GITHUB_HTTP_SERVER_ERROR"),
    pair("HTTP_STATUS", "GITHUB_HTTP_FAILED"),
    pair("CONTENT_TYPE", "GITHUB_HTTP_RESPONSE_INVALID"),
    pair("BODY_READ", "GITHUB_HTTP_RESPONSE_INVALID"),
    pair("BODY_READ", "GITHUB_HTTP_RESPONSE_TOO_LARGE"),
    pair("BODY_READ", "GITHUB_HTTP_NETWORK_ERROR"),
    pair("JSON_PARSE", "GITHUB_HTTP_RESPONSE_INVALID"),
    pair("RESPONSE_SCHEMA", "GITHUB_HTTP_RESPONSE_INVALID"),
  ] as const,
);

type KnownCombination =
  (typeof GITHUB_REF_READ_DIAGNOSTIC_COMBINATIONS)[number];

type DiagnosticForCombination<Combination extends KnownCombination> =
  Combination extends readonly [
    infer Boundary extends string,
    infer Code extends string,
  ] ? Readonly<{ boundary: Boundary; code: Code }>
    : never;

export type GitHubRefReadDiagnostic =
  | DiagnosticForCombination<KnownCombination>
  | Readonly<{ boundary: "UNKNOWN"; code: "UNKNOWN" }>;

const UNKNOWN = Object.freeze(
  {
    boundary: "UNKNOWN",
    code: "UNKNOWN",
  } as const,
);
const combinations = new Set(
  GITHUB_REF_READ_DIAGNOSTIC_COMBINATIONS.map(([boundary, code]) =>
    `${boundary}:${code}`
  ),
);
const trustedDiagnostics = new WeakSet<object>([UNKNOWN]);

export function createGitHubRefReadDiagnostic(
  boundary: string | undefined,
  code: string,
): GitHubRefReadDiagnostic {
  if (
    typeof boundary !== "string" ||
    typeof code !== "string" ||
    !combinations.has(`${boundary}:${code}`)
  ) return UNKNOWN;
  const diagnostic = Object.freeze({
    boundary,
    code,
  }) as GitHubRefReadDiagnostic;
  trustedDiagnostics.add(diagnostic);
  return diagnostic;
}

export function validateGitHubRefReadDiagnostic(
  value: unknown,
): GitHubRefReadDiagnostic {
  return typeof value === "object" && value !== null &&
      trustedDiagnostics.has(value)
    ? value as GitHubRefReadDiagnostic
    : UNKNOWN;
}
