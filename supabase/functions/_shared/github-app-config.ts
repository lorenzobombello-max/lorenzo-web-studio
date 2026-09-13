export const GITHUB_PROVIDER_DISABLED = "GITHUB_PROVIDER_DISABLED";
export const GITHUB_CONFIGURATION_INVALID = "GITHUB_CONFIGURATION_INVALID";

const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const GITHUB_OWNER = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/;
const GITHUB_REPOSITORY = /^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,98}[A-Za-z0-9])?$/;
const GIT_OBJECT_ID = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const SEMANTIC_VERSION =
  /^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;

export type GitHubProviderTarget = "TEST" | "PRODUCTION";

export type GitHubProviderEnvironment = Readonly<{
  get(name: string): string | undefined;
}>;

export type GitHubAppConfig = Readonly<{
  enabled: true;
  target: GitHubProviderTarget;
  appId: string;
  installationId: string;
  organization: string;
  templateOwner: string;
  templateName: string;
  templateRepositoryId: string;
  starterVersion: string;
  starterCommitSha: string;
  privateKey: string;
}>;

export class GitHubProviderDisabledError extends Error {
  readonly code = GITHUB_PROVIDER_DISABLED;

  constructor() {
    super(GITHUB_PROVIDER_DISABLED);
    this.name = "GitHubProviderDisabledError";
  }
}

export class GitHubAppConfigurationError extends Error {
  readonly code = GITHUB_CONFIGURATION_INVALID;

  constructor() {
    super(GITHUB_CONFIGURATION_INVALID);
    this.name = "GitHubAppConfigurationError";
  }
}

function invalid(): never {
  throw new GitHubAppConfigurationError();
}

function read(
  environment: GitHubProviderEnvironment,
  name: string,
): string {
  const value = environment.get(name)?.trim();
  if (!value) invalid();
  return value;
}

function validPrivateKey(value: string): boolean {
  const lines = value.replaceAll("\r\n", "\n").split("\n");
  if (
    lines.length < 3 || lines[0] !== "-----BEGIN PRIVATE KEY-----" ||
    lines.at(-1) !== "-----END PRIVATE KEY-----"
  ) return false;
  const body = lines.slice(1, -1).join("");
  return body.length >= 64 && body.length % 4 === 0 &&
    /^[A-Za-z0-9+/]+={0,2}$/.test(body);
}

export function loadGitHubAppConfig(
  environment: GitHubProviderEnvironment = Deno.env,
): GitHubAppConfig {
  const enabled = environment.get("LWS_GITHUB_PROVIDER_ENABLED");
  if (enabled === undefined || enabled === "" || enabled === "false") {
    throw new GitHubProviderDisabledError();
  }
  if (enabled !== "true") invalid();

  const target = read(environment, "LWS_GITHUB_PROVIDER_TARGET");
  const appId = read(environment, "LWS_GITHUB_APP_ID");
  const installationId = read(
    environment,
    "LWS_GITHUB_APP_INSTALLATION_ID",
  );
  const testOrganization = read(
    environment,
    "LWS_GITHUB_TEST_ORGANIZATION",
  );
  const productionOrganization = read(
    environment,
    "LWS_GITHUB_PRODUCTION_ORGANIZATION",
  );
  const templateOwner = read(environment, "LWS_GITHUB_TEMPLATE_OWNER");
  const templateName = read(environment, "LWS_GITHUB_TEMPLATE_NAME");
  const templateRepositoryId = read(
    environment,
    "LWS_GITHUB_TEMPLATE_REPOSITORY_ID",
  );
  const starterVersion = read(environment, "LWS_GITHUB_STARTER_VERSION");
  const starterCommitSha = read(
    environment,
    "LWS_GITHUB_STARTER_COMMIT_SHA",
  );
  const privateKey = read(environment, "LWS_GITHUB_APP_PRIVATE_KEY").replaceAll(
    "\r\n",
    "\n",
  );

  if (
    (target !== "TEST" && target !== "PRODUCTION") ||
    !NUMERIC_ID.test(appId) || !NUMERIC_ID.test(installationId) ||
    !GITHUB_OWNER.test(testOrganization) ||
    !GITHUB_OWNER.test(productionOrganization) ||
    testOrganization.toLowerCase() === productionOrganization.toLowerCase() ||
    !GITHUB_OWNER.test(templateOwner) ||
    !GITHUB_REPOSITORY.test(templateName) ||
    !NUMERIC_ID.test(templateRepositoryId) ||
    !SEMANTIC_VERSION.test(starterVersion) ||
    !GIT_OBJECT_ID.test(starterCommitSha) || !validPrivateKey(privateKey)
  ) invalid();

  const organization = target === "TEST"
    ? testOrganization
    : productionOrganization;
  if (templateOwner.toLowerCase() !== organization.toLowerCase()) invalid();

  const config = {
    enabled: true,
    target,
    appId,
    installationId,
    organization,
    templateOwner,
    templateName,
    templateRepositoryId,
    starterVersion,
    starterCommitSha,
  };
  Object.defineProperty(config, "privateKey", {
    value: privateKey,
    enumerable: false,
    configurable: false,
    writable: false,
  });
  return Object.freeze(config) as GitHubAppConfig;
}
