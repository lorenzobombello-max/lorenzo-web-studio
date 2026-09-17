import {
  githubAppPrivateKeyToPkcs8,
  isValidGitHubAppPrivateKey,
} from "../_shared/github-app-private-key.ts";

const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const EXPECTED_SUPABASE_URL = "https://xcsptvntvrizwhskaphr.supabase.co";
const EXPECTED_APP_ID = "4932372";
const EXPECTED_INSTALLATION_ID = "161436785";
const EXPECTED_REPOSITORY_ID = "1368684860";
const EXPECTED_OWNER = "lorenzo-web-solutions";
const EXPECTED_REPOSITORY = "lws-website-starter";

export type Gate6ProbeEnvironment = Readonly<{
  get(name: string): string | undefined;
}>;

export type Gate6ProbeConfig = Readonly<{
  appId: string;
  installationId: string;
  repositoryId: string;
  repositoryOwner: string;
  repositoryName: string;
  privateKey: string;
}>;

export type Gate6ProbeConfigurationCheck =
  | "SUPABASE_URL_INVALID"
  | "PUBLISHABLE_KEYS_MISSING"
  | "PUBLISHABLE_KEYS_JSON_INVALID"
  | "PUBLISHABLE_KEYS_DEFAULT_MISSING"
  | "PUBLISHABLE_KEYS_DEFAULT_INVALID"
  | "PROVIDER_DISABLED_REQUIRED"
  | "APP_ID_INVALID"
  | "INSTALLATION_ID_INVALID"
  | "REPOSITORY_ID_INVALID"
  | "TEMPLATE_OWNER_INVALID"
  | "TEMPLATE_NAME_INVALID"
  | "PRIVATE_KEY_MISSING"
  | "PRIVATE_KEY_PEM_INVALID";

export type Gate6ProbeConfigurationDiagnosis = Readonly<{
  configuration_valid: boolean;
  failed_check: Gate6ProbeConfigurationCheck | null;
  checks: Readonly<{
    supabase_url: Readonly<{ present: boolean; shape_valid: boolean }>;
    publishable_keys: Readonly<{
      present: boolean;
      parseable: boolean;
      shape_valid: boolean;
    }>;
    provider_enabled: Readonly<{ present: boolean; shape_valid: boolean }>;
    app_id: Readonly<{ present: boolean; valid_integer: boolean }>;
    installation_id: Readonly<{ present: boolean; valid_integer: boolean }>;
    repository_id: Readonly<{ present: boolean; valid_integer: boolean }>;
    template_owner: Readonly<{ present: boolean; shape_valid: boolean }>;
    template_name: Readonly<{ present: boolean; shape_valid: boolean }>;
    private_key: Readonly<{ present: boolean; pem_shape_valid: boolean }>;
  }>;
}>;

export class Gate6ProbeConfigurationError extends Error {
  constructor() {
    super("GATE6_PROBE_CONFIGURATION_INVALID");
    this.name = "Gate6ProbeConfigurationError";
  }
}

function invalid(): never {
  throw new Gate6ProbeConfigurationError();
}

function read(environment: Gate6ProbeEnvironment, name: string): string {
  const value = environment.get(name)?.trim();
  return value || invalid();
}

function present(value: string | undefined): boolean {
  return typeof value === "string" && value.trim().length > 0;
}

function inspectPublishableKeys(value: string | undefined) {
  const status = {
    present: present(value),
    parseable: false,
    shape_valid: false,
  };
  if (!status.present) {
    return { status, key: null, failed: "PUBLISHABLE_KEYS_MISSING" as const };
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(value as string);
    status.parseable = true;
  } catch {
    return {
      status,
      key: null,
      failed: "PUBLISHABLE_KEYS_JSON_INVALID" as const,
    };
  }
  if (
    !parsed || typeof parsed !== "object" || Array.isArray(parsed) ||
    Object.getPrototypeOf(parsed) !== Object.prototype ||
    !Object.hasOwn(parsed, "default")
  ) {
    return {
      status,
      key: null,
      failed: "PUBLISHABLE_KEYS_DEFAULT_MISSING" as const,
    };
  }
  const entries = parsed as Record<string, unknown>;
  const key = entries.default;
  if (
    Object.values(entries).some((entry) =>
      typeof entry !== "string" || !entry
    ) ||
    typeof key !== "string" || !/^sb_publishable_[A-Za-z0-9_-]+$/.test(key)
  ) {
    return {
      status,
      key: null,
      failed: "PUBLISHABLE_KEYS_DEFAULT_INVALID" as const,
    };
  }
  status.shape_valid = true;
  return { status, key, failed: null };
}

export function diagnoseGate6ProbeConfiguration(
  environment: Gate6ProbeEnvironment = Deno.env,
): Gate6ProbeConfigurationDiagnosis {
  const supabaseUrl = environment.get("SUPABASE_URL");
  const publishable = inspectPublishableKeys(
    environment.get("SUPABASE_PUBLISHABLE_KEYS"),
  );
  const provider = environment.get("LWS_GITHUB_PROVIDER_ENABLED");
  const appId = environment.get("LWS_GITHUB_APP_ID");
  const installationId = environment.get("LWS_GITHUB_APP_INSTALLATION_ID");
  const repositoryId = environment.get("LWS_GITHUB_TEMPLATE_REPOSITORY_ID");
  const owner = environment.get("LWS_GITHUB_TEMPLATE_OWNER");
  const name = environment.get("LWS_GITHUB_TEMPLATE_NAME");
  const privateKey = environment.get("LWS_GITHUB_APP_PRIVATE_KEY");
  const checks = Object.freeze({
    supabase_url: Object.freeze({
      present: present(supabaseUrl),
      shape_valid: supabaseUrl === EXPECTED_SUPABASE_URL,
    }),
    publishable_keys: Object.freeze(publishable.status),
    provider_enabled: Object.freeze({
      present: present(provider),
      shape_valid: provider === "false",
    }),
    app_id: Object.freeze({
      present: present(appId),
      valid_integer: typeof appId === "string" && NUMERIC_ID.test(appId),
    }),
    installation_id: Object.freeze({
      present: present(installationId),
      valid_integer: typeof installationId === "string" &&
        NUMERIC_ID.test(installationId),
    }),
    repository_id: Object.freeze({
      present: present(repositoryId),
      valid_integer: typeof repositoryId === "string" &&
        NUMERIC_ID.test(repositoryId),
    }),
    template_owner: Object.freeze({
      present: present(owner),
      shape_valid: owner === EXPECTED_OWNER,
    }),
    template_name: Object.freeze({
      present: present(name),
      shape_valid: name === EXPECTED_REPOSITORY,
    }),
    private_key: Object.freeze({
      present: present(privateKey),
      pem_shape_valid: typeof privateKey === "string" &&
        isValidGitHubAppPrivateKey(privateKey),
    }),
  });
  const failedCheck: Gate6ProbeConfigurationCheck | null =
    (supabaseUrl !== EXPECTED_SUPABASE_URL ? "SUPABASE_URL_INVALID" : null) ??
      publishable.failed ??
      (provider !== "false" ? "PROVIDER_DISABLED_REQUIRED" : null) ??
      (appId !== EXPECTED_APP_ID ? "APP_ID_INVALID" : null) ??
      (installationId !== EXPECTED_INSTALLATION_ID
        ? "INSTALLATION_ID_INVALID"
        : null) ??
      (repositoryId !== EXPECTED_REPOSITORY_ID
        ? "REPOSITORY_ID_INVALID"
        : null) ??
      (owner !== EXPECTED_OWNER ? "TEMPLATE_OWNER_INVALID" : null) ??
      (name !== EXPECTED_REPOSITORY ? "TEMPLATE_NAME_INVALID" : null) ??
      (!checks.private_key.present ? "PRIVATE_KEY_MISSING" : null) ??
      (!checks.private_key.pem_shape_valid ? "PRIVATE_KEY_PEM_INVALID" : null);
  return Object.freeze({
    configuration_valid: failedCheck === null,
    failed_check: failedCheck,
    checks,
  });
}

export function loadGate6ProbePublishableKey(
  environment: Gate6ProbeEnvironment = Deno.env,
): string {
  const result = inspectPublishableKeys(
    environment.get("SUPABASE_PUBLISHABLE_KEYS"),
  );
  if (!result.key) invalid();
  return result.key;
}

export function loadGate6ProbeConfig(
  environment: Gate6ProbeEnvironment = Deno.env,
): Gate6ProbeConfig {
  if (!diagnoseGate6ProbeConfiguration(environment).configuration_valid) {
    invalid();
  }
  const appId = read(environment, "LWS_GITHUB_APP_ID");
  const installationId = read(environment, "LWS_GITHUB_APP_INSTALLATION_ID");
  const repositoryId = read(environment, "LWS_GITHUB_TEMPLATE_REPOSITORY_ID");
  const repositoryOwner = read(environment, "LWS_GITHUB_TEMPLATE_OWNER");
  const repositoryName = read(environment, "LWS_GITHUB_TEMPLATE_NAME");
  const privateKey = read(environment, "LWS_GITHUB_APP_PRIVATE_KEY").replaceAll(
    "\r\n",
    "\n",
  );
  if (
    appId !== EXPECTED_APP_ID || installationId !== EXPECTED_INSTALLATION_ID ||
    repositoryOwner !== EXPECTED_OWNER ||
    repositoryName !== EXPECTED_REPOSITORY ||
    !NUMERIC_ID.test(repositoryId) ||
    !isValidGitHubAppPrivateKey(privateKey)
  ) invalid();
  const config = {
    appId,
    installationId,
    repositoryId,
    repositoryOwner,
    repositoryName,
  };
  Object.defineProperty(config, "privateKey", {
    value: privateKey,
    enumerable: false,
    configurable: false,
    writable: false,
  });
  return Object.freeze(config) as Gate6ProbeConfig;
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}

export async function signGitHubAppJwt(
  privateKey: string,
  appId: string,
  now = Date.now(),
): Promise<string> {
  const signer = await initializeGitHubAppJwtSigner(privateKey);
  return await signer(appId, now);
}

export async function initializeGitHubAppJwtSigner(privateKey: string) {
  const signInput = await initializeGitHubAppInputSigner(privateKey);
  return async (appId: string, now = Date.now()): Promise<string> => {
    const encode = (value: Record<string, unknown>) =>
      base64Url(new TextEncoder().encode(JSON.stringify(value)));
    const signingInput = [
      encode({ alg: "RS256", typ: "JWT" }),
      encode({
        iat: Math.floor(now / 1000) - 60,
        exp: Math.floor(now / 1000) + 540,
        iss: appId,
      }),
    ].join(".");
    return `${signingInput}.${base64Url(await signInput(signingInput))}`;
  };
}

export async function initializeGitHubAppInputSigner(privateKey: string) {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    githubAppPrivateKeyToPkcs8(privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return async (signingInput: string): Promise<Uint8Array> => {
    const signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(signingInput),
    );
    return new Uint8Array(signature);
  };
}
