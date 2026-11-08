import assert from "node:assert/strict";
import { loadWebsiteProjectPreviewDispatchAppConfig } from "./github-app-config.ts";
import { createGitHubAppTokenBroker } from "./github-app-token.ts";
import { createGitHubHttpClient } from "./github-http.ts";

Deno.test("preview reuses the existing platform App without expanding repository or Actions scope", async () => {
  const keys = await crypto.subtle.generateKey({
    name: "RSASSA-PKCS1-v1_5", modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256",
  }, true, ["sign", "verify"]);
  const encoded = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.exportKey("pkcs8", keys.privateKey))));
  const pem = ["-----BEGIN PRIVATE KEY-----", encoded, "-----END PRIVATE KEY-----"].join("\n");
  const values: Record<string, string> = {
    LWS_DELIVERY_PDF_DISPATCH_APP_ID: "123",
    LWS_DELIVERY_PDF_DISPATCH_INSTALLATION_ID: "456",
    LWS_DELIVERY_PDF_DISPATCH_PRIVATE_KEY: pem,
  };
  const config = loadWebsiteProjectPreviewDispatchAppConfig({ get: (name) => values[name] });
  assert.equal(config.appId, "123");
  assert.equal(config.installationId, "456");
  assert.equal(config.repositoryId, "1320223175");
  assert.equal(JSON.stringify(config).includes(pem), false);
  let actionPermission = "write";
  let exchanges = 0;
  const http = createGitHubHttpClient({
    fetch: async (input, init) => {
      const request = new Request(input, init);
      assert.equal(request.url, "https://api.github.com/app/installations/456/access_tokens");
      const body = await request.json();
      assert.deepEqual(body.repository_ids, [1320223175]);
      assert.deepEqual(body.permissions, { metadata: "read", actions: actionPermission });
      exchanges++;
      return Response.json({
        token: "gh" + `s_${"a".repeat(36)}`, expires_at: new Date(Date.now() + 60000).toISOString(),
        repository_selection: "selected", permissions: body.permissions,
      });
    },
  });
  const broker = createGitHubAppTokenBroker({
    now: Date.now,
    sign: async () => new Uint8Array([1, 2, 3]),
    exchange: async (input) => {
      assert.deepEqual(input.repositoryIds, ["1320223175"]);
      assert.deepEqual(input.permissions, { metadata: "read", actions: actionPermission });
      const result = await http.execute({ kind: "TOKEN_EXCHANGE",
        installationId: input.installationId, appJwt: input.appJwt,
        repositoryIds: input.repositoryIds, permissions: input.permissions });
      if (!("token" in result) || !("expiresAt" in result)) throw new Error("TOKEN_EXCHANGE_INVALID");
      return result;
    },
  });
  const authority = { websiteWorkContextId: "11111111-1111-4111-8111-111111111111",
    target: "PRODUCTION" as const, organization: config.organization, repositoryIds: [config.repositoryId] };
  await broker.issue(config, { ...authority, operation: "WEBSITE_PROJECT_PREVIEW_DISPATCH" }, authority);
  actionPermission = "read";
  await broker.issue(config, { ...authority, operation: "WEBSITE_PROJECT_PREVIEW_MONITOR" }, authority);
  assert.equal(exchanges, 2);
  await assert.rejects(() => broker.issue(config, {
    ...authority, repositoryIds: ["123"], operation: "WEBSITE_PROJECT_PREVIEW_DISPATCH",
  }, { ...authority, repositoryIds: ["123"] }));
  await assert.rejects(() => broker.issue(config, {
    ...authority, operation: "WEBSITE_PROJECT_FILES_WRITE",
  }, authority));
  for (const name of Object.keys(values)) {
    assert.throws(() => loadWebsiteProjectPreviewDispatchAppConfig({
      get: (key) => key === name ? undefined : values[key],
    }), /GITHUB_CONFIGURATION_INVALID/);
  }
  assert.throws(() => loadWebsiteProjectPreviewDispatchAppConfig({
    get: (name) => values[name.replace("LWS_PREVIEW_DISPATCH", "LWS_DELIVERY_PDF_DISPATCH")]
      && name.startsWith("LWS_PREVIEW_DISPATCH")
      ? values[name.replace("LWS_PREVIEW_DISPATCH", "LWS_DELIVERY_PDF_DISPATCH")]
      : undefined,
  }), /GITHUB_CONFIGURATION_INVALID/);
  assert.throws(() => loadWebsiteProjectPreviewDispatchAppConfig({ get: () => undefined }));
});
