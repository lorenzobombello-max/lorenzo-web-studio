const API_ORIGIN = "https://api.github.com";
const TIMEOUT_MILLISECONDS = 10_000;
const MAX_RESPONSE_BYTES = 64 * 1024;
const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const EXPECTED_APP_ID = "4932372";
const EXPECTED_INSTALLATION_ID = "161436785";
const EXPECTED_OWNER = "lorenzo-web-solutions";
const EXPECTED_REPOSITORY = "lws-website-starter";

type Fetch = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;

export type GitHubAppGate6ProbeInput = Readonly<{
  appId: string;
  installationId: string;
  privateKey: string;
  repositoryId: string;
  repositoryOwner: string;
  repositoryName: string;
  signAppJwt(privateKey: string, appId: string): Promise<string>;
  fetch: Fetch;
  timeoutMilliseconds?: number;
}>;

export class GitHubAppGate6ProbeError extends Error {
  constructor() {
    super("GITHUB_APP_GATE6_PROBE_FAILED");
    this.name = "GitHubAppGate6ProbeError";
  }
}

function fail(): never {
  throw new GitHubAppGate6ProbeError();
}

function exactKeys(value: object, keys: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === keys.length && keys.every((key) => key in value);
}

async function boundedJson(response: Response): Promise<unknown> {
  if (!response.ok || !response.body) fail();
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > MAX_RESPONSE_BYTES) fail();
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
    fail();
  }
}

async function githubJson(
  fetcher: Fetch,
  path: string,
  token: string,
  timeoutMilliseconds: number,
  method = "GET",
  body?: unknown,
): Promise<unknown> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMilliseconds);
  try {
    const response = await fetcher(`${API_ORIGIN}${path}`, {
      method,
      redirect: "error",
      signal: controller.signal,
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": "2022-11-28",
        ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    return await boundedJson(response);
  } catch (error) {
    if (error instanceof GitHubAppGate6ProbeError) throw error;
    fail();
  } finally {
    clearTimeout(timeout);
  }
}

export async function executeGitHubAppGate6Probe(
  input: GitHubAppGate6ProbeInput,
) {
  const timeoutMilliseconds = input.timeoutMilliseconds ?? TIMEOUT_MILLISECONDS;
  if (
    input.appId !== EXPECTED_APP_ID ||
    input.installationId !== EXPECTED_INSTALLATION_ID ||
    input.repositoryOwner !== EXPECTED_OWNER ||
    input.repositoryName !== EXPECTED_REPOSITORY ||
    !NUMERIC_ID.test(input.repositoryId) || !input.privateKey ||
    !Number.isSafeInteger(timeoutMilliseconds) || timeoutMilliseconds < 1 ||
    timeoutMilliseconds > TIMEOUT_MILLISECONDS
  ) fail();

  const appJwt = await input.signAppJwt(input.privateKey, input.appId);
  const app = await githubJson(
    input.fetch,
    "/app",
    appJwt,
    timeoutMilliseconds,
  );
  const tokenResponse = await githubJson(
    input.fetch,
    `/app/installations/${EXPECTED_INSTALLATION_ID}/access_tokens`,
    appJwt,
    timeoutMilliseconds,
    "POST",
    {
      repository_ids: [Number(input.repositoryId)],
      permissions: { contents: "read", metadata: "read" },
    },
  );
  if (
    !app || typeof app !== "object" || Array.isArray(app) ||
    typeof (app as Record<string, unknown>).id !== "number" ||
    String((app as Record<string, unknown>).id) !== EXPECTED_APP_ID ||
    typeof (app as Record<string, unknown>).slug !== "string" ||
    !tokenResponse || typeof tokenResponse !== "object" ||
    Array.isArray(tokenResponse)
  ) fail();
  const lease = tokenResponse as Record<string, unknown>;
  const permissions = lease.permissions as Record<string, unknown> | undefined;
  if (
    typeof lease.token !== "string" || lease.token.length < 20 ||
    lease.repository_selection !== "selected" || !permissions ||
    !exactKeys(permissions, ["contents", "metadata"]) ||
    permissions.contents !== "read" || permissions.metadata !== "read"
  ) fail();

  const repository = await githubJson(
    input.fetch,
    `/repos/${EXPECTED_OWNER}/${EXPECTED_REPOSITORY}`,
    lease.token,
    timeoutMilliseconds,
  );
  if (
    !repository || typeof repository !== "object" || Array.isArray(repository)
  ) {
    fail();
  }
  const record = repository as Record<string, unknown>;
  if (
    String(record.id || "") !== input.repositoryId ||
    record.full_name !== `${EXPECTED_OWNER}/${EXPECTED_REPOSITORY}` ||
    record.private !== true || typeof record.default_branch !== "string" ||
    !record.default_branch
  ) fail();

  return Object.freeze({
    app: Object.freeze({
      id: EXPECTED_APP_ID,
      slug: String((app as Record<string, unknown>).slug),
    }),
    repository: Object.freeze({
      id: input.repositoryId,
      full_name: `${EXPECTED_OWNER}/${EXPECTED_REPOSITORY}`,
      private: true,
      default_branch: record.default_branch,
    }),
    installation: Object.freeze({
      repository_selection: "selected" as const,
      permissions: Object.freeze({
        contents: "read" as const,
        metadata: "read" as const,
      }),
    }),
  });
}
