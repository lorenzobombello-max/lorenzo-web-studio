import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import type { GitHubAppConfig } from "../_shared/github-app-config.ts";
import {
  createGitHubAppTokenBroker,
  GitHubTokenBrokerError,
} from "../_shared/github-app-token.ts";
import { createWebsiteProjectPreviewGitHubTokenExchange } from "./index.ts";

const NOW = Date.parse("2026-09-23T12:00:00.000Z");
const CONTEXT_ID = "11111111-1111-4111-8111-111111111111";
const REPOSITORY_ID = "1378797607";
const INSTALLATION_TOKEN = `ghs_${"a".repeat(40)}`;

const CONFIG = Object.freeze({
  enabled: true,
  target: "PRODUCTION",
  appId: "4932372",
  installationId: "161436785",
  organization: "lorenzo-web-solutions",
  templateOwner: "lorenzo-web-solutions",
  templateName: "lws-website-starter",
  templateRepositoryId: "1368684860",
  starterVersion: "1.0.0",
  starterCommitSha: "47e7d7aad37afaa0b3e921fac349a87d2dd2816a",
  starterTreeSha256: "6b4a76bf8a64ad91dc18fabe410f032670f03578d2d4c2123dba7cc0e98b5957",
  privateKey: "test-only-private-key",
}) as GitHubAppConfig;

function tokenResponse(permissions: unknown, includePermissions = true): Record<string, unknown> {
  return {
    token: INSTALLATION_TOKEN,
    expires_at: "2026-09-23T12:30:00.000Z",
    repository_selection: "selected",
    ...(includePermissions ? { permissions } : {}),
  };
}

function harness(responseBody: Record<string, unknown>) {
  let requestBody: unknown;
  const runtimeFetch: typeof fetch = async (_input, init) => {
    requestBody = JSON.parse(String(init?.body));
    return Response.json(responseBody);
  };
  const broker = createGitHubAppTokenBroker({
    now: () => NOW,
    sign: () => Promise.resolve(new Uint8Array([1, 2, 3, 4])),
    exchange: createWebsiteProjectPreviewGitHubTokenExchange(runtimeFetch),
  });
  const issue = () => broker.issue(
    CONFIG,
    {
      websiteWorkContextId: CONTEXT_ID,
      target: "PRODUCTION",
      organization: "lorenzo-web-solutions",
      operation: "WEBSITE_PROJECT_FILES_READ",
      repositoryIds: [REPOSITORY_ID],
    },
    {
      websiteWorkContextId: CONTEXT_ID,
      target: "PRODUCTION",
      organization: "lorenzo-web-solutions",
      repositoryIds: [REPOSITORY_ID],
    },
  );
  return { issue, requestBody: () => requestBody };
}

Deno.test("preview token adapter accepts exact read-only GitHub response permissions", async () => {
  const test = harness(tokenResponse({ metadata: "read", contents: "read" }));

  const lease = await test.issue();

  assertEquals(lease.expiresAt, "2026-09-23T12:30:00.000Z");
  assertEquals(test.requestBody(), {
    repository_ids: [1378797607],
    permissions: { metadata: "read", contents: "read" },
  });
});

Deno.test("preview token adapter rejects missing GitHub response permissions without returning a token", async () => {
  const test = harness(tokenResponse(undefined, false));

  await assertRejects(
    test.issue,
    GitHubTokenBrokerError,
    "GITHUB_TOKEN_RESPONSE_INVALID",
  );
});

Deno.test("preview token adapter rejects invalid or broader GitHub response permissions without returning a token", async () => {
  for (const permissions of [
    { metadata: "read", contents: "invalid" },
    { metadata: "read", contents: "write" },
    { metadata: "read", contents: "read", administration: "write" },
  ]) {
    const test = harness(tokenResponse(permissions));

    await assertRejects(
      test.issue,
      GitHubTokenBrokerError,
      "GITHUB_TOKEN_RESPONSE_INVALID",
    );
  }
});
