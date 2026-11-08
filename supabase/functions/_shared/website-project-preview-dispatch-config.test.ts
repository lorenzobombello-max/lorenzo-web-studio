import assert from "node:assert/strict";
import { loadWebsiteProjectPreviewDispatchAppConfig } from "./github-app-config.ts";
import { createGitHubAppTokenBroker } from "./github-app-token.ts";

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
  const broker = createGitHubAppTokenBroker({
    now: Date.now,
    sign: async () => new Uint8Array([1, 2, 3]),
    exchange: async (input) => {
      assert.deepEqual(input.repositoryIds, ["1320223175"]);
      assert.deepEqual(input.permissions, { metadata: "read", actions: actionPermission });
      return { token: "gh" + `s_${"a".repeat(36)}`, expiresAt: new Date(Date.now() + 60000).toISOString(),
        repositorySelection: "selected", permissions: input.permissions };
    },
  });
  const authority = { websiteWorkContextId: "11111111-1111-4111-8111-111111111111",
    target: "PRODUCTION" as const, organization: config.organization, repositoryIds: [config.repositoryId] };
  await broker.issue(config, { ...authority, operation: "WEBSITE_PROJECT_PREVIEW_DISPATCH" }, authority);
  actionPermission = "read";
  await broker.issue(config, { ...authority, operation: "WEBSITE_PROJECT_PREVIEW_MONITOR" }, authority);
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
