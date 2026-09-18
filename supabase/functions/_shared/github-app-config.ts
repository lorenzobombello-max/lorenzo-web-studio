import { normalizeGitHubAppPrivateKey } from "./github-app-private-key.ts";

export const GITHUB_PROVIDER_DISABLED = "GITHUB_PROVIDER_DISABLED";
export const GITHUB_CONFIGURATION_INVALID = "GITHUB_CONFIGURATION_INVALID";

const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const GITHUB_OWNER = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/;
const GITHUB_REPOSITORY = /^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,98}[A-Za-z0-9])?$/;
const GIT_OBJECT_ID = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const SHA256 = /^[0-9a-f]{64}$/;
const SEMANTIC_VERSION =
  /^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;
const TASK13_STARTER_NAME = "lws-website-starter";
const TASK13_STARTER_REPOSITORY_ID = "1368684860";
const TASK13_STARTER_VERSION = "1.0.0";
const TASK13_STARTER_COMMIT_SHA = "47e7d7aad37afaa0b3e921fac349a87d2dd2816a";
const TASK13_STARTER_TREE_SHA256 =
  "6b4a76bf8a64ad91dc18fabe410f032670f03578d2d4c2123dba7cc0e98b5957";

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
  starterTreeSha256: string;
  privateKey: string;
}>;

export type GitHubTask13RuntimeConfig = Readonly<{
  production: GitHubAppConfig;
  lab: GitHubAppConfig;
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
  const productionInstallationId = read(
    environment,
    "LWS_GITHUB_APP_INSTALLATION_ID",
  );
  const installationId = target === "TEST"
    ? read(environment, "LWS_GITHUB_LAB_INSTALLATION_ID")
    : productionInstallationId;
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
  const starterTreeSha256 = read(
    environment,
    "LWS_GITHUB_STARTER_TREE_SHA256",
  );
  let privateKey: string;
  try {
    privateKey = normalizeGitHubAppPrivateKey(
      read(environment, "LWS_GITHUB_APP_PRIVATE_KEY"),
    );
  } catch {
    invalid();
  }

  if (
    (target !== "TEST" && target !== "PRODUCTION") ||
    !NUMERIC_ID.test(appId) || !NUMERIC_ID.test(productionInstallationId) ||
    !NUMERIC_ID.test(installationId) ||
    target === "TEST" && installationId === productionInstallationId ||
    !GITHUB_OWNER.test(testOrganization) ||
    !GITHUB_OWNER.test(productionOrganization) ||
    testOrganization.toLowerCase() === productionOrganization.toLowerCase() ||
    !GITHUB_OWNER.test(templateOwner) ||
    !GITHUB_REPOSITORY.test(templateName) ||
    !NUMERIC_ID.test(templateRepositoryId) ||
    !SEMANTIC_VERSION.test(starterVersion) ||
    !GIT_OBJECT_ID.test(starterCommitSha) ||
    !SHA256.test(starterTreeSha256)
  ) invalid();

  const organization = target === "TEST"
    ? testOrganization
    : productionOrganization;
  if (templateOwner.toLowerCase() !== productionOrganization.toLowerCase()) {
    invalid();
  }

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
    starterTreeSha256,
  };
  Object.defineProperty(config, "privateKey", {
    value: privateKey,
    enumerable: false,
    configurable: false,
    writable: false,
  });
  return Object.freeze(config) as GitHubAppConfig;
}

export function loadGitHubTask13RuntimeConfig(
  environment: GitHubProviderEnvironment = Deno.env,
): GitHubTask13RuntimeConfig {
  if (
    environment.get("LWS_GITHUB_PROVIDER_ENABLED") !== "false" ||
    environment.get("LWS_GITHUB_APP_INSTALLATION_ID")?.trim() !==
      "161436785" ||
    environment.get("LWS_GITHUB_LAB_INSTALLATION_ID")?.trim() !==
      "161461160" ||
    environment.get("LWS_GITHUB_PRODUCTION_ORGANIZATION")?.trim() !==
      "lorenzo-web-solutions" ||
    environment.get("LWS_GITHUB_TEST_ORGANIZATION")?.trim() !==
      "lorenzo-web-solutions-lab" ||
    environment.get("LWS_GITHUB_TEMPLATE_OWNER")?.trim() !==
      "lorenzo-web-solutions"
  ) invalid();

  const forTarget = (target: GitHubProviderTarget): GitHubAppConfig =>
    loadGitHubAppConfig(Object.freeze({
      get(name: string): string | undefined {
        if (name === "LWS_GITHUB_PROVIDER_ENABLED") return "true";
        if (name === "LWS_GITHUB_PROVIDER_TARGET") return target;
        if (name === "LWS_GITHUB_TEMPLATE_NAME") {
          return TASK13_STARTER_NAME;
        }
        if (name === "LWS_GITHUB_TEMPLATE_REPOSITORY_ID") {
          return TASK13_STARTER_REPOSITORY_ID;
        }
        if (name === "LWS_GITHUB_STARTER_VERSION") {
          return TASK13_STARTER_VERSION;
        }
        if (name === "LWS_GITHUB_STARTER_COMMIT_SHA") {
          return TASK13_STARTER_COMMIT_SHA;
        }
        if (name === "LWS_GITHUB_STARTER_TREE_SHA256") {
          return TASK13_STARTER_TREE_SHA256;
        }
        return environment.get(name);
      },
    }));
  const production = forTarget("PRODUCTION");
  const lab = forTarget("TEST");
  if (production.privateKey !== lab.privateKey) invalid();
  return Object.freeze({ production, lab });
}
