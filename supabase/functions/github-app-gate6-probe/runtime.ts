const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const EXPECTED_APP_ID = "4932372";
const EXPECTED_INSTALLATION_ID = "161436785";
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

function validPrivateKey(value: string): boolean {
  const lines = value.replaceAll("\r\n", "\n").split("\n");
  const body = lines.slice(1, -1).join("");
  return lines.length >= 3 && lines[0] === "-----BEGIN PRIVATE KEY-----" &&
    lines.at(-1) === "-----END PRIVATE KEY-----" && body.length >= 64 &&
    body.length % 4 === 0 && /^[A-Za-z0-9+/]+={0,2}$/.test(body);
}

export function loadGate6ProbeConfig(
  environment: Gate6ProbeEnvironment = Deno.env,
): Gate6ProbeConfig {
  if (environment.get("LWS_GITHUB_PROVIDER_ENABLED") !== "false") invalid();
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
    !NUMERIC_ID.test(repositoryId) || !validPrivateKey(privateKey)
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

function decodePem(privateKey: string): ArrayBuffer {
  const encoded = privateKey.replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "").replaceAll(/\s/g, "");
  const binary = atob(encoded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

export async function signGitHubAppJwt(
  privateKey: string,
  appId: string,
  now = Date.now(),
): Promise<string> {
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
  const key = await crypto.subtle.importKey(
    "pkcs8",
    decodePem(privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}
