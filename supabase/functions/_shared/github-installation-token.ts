const GITHUB_INSTALLATION_ACCESS_TOKEN = /^ghs_[A-Za-z0-9._-]{36,}$/;

export function isGitHubInstallationAccessToken(
  value: unknown,
): value is string {
  return typeof value === "string" &&
    GITHUB_INSTALLATION_ACCESS_TOKEN.test(value);
}
