import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  verifyGitHubActionsOidcToken,
  WebsiteProjectPreviewOidcError,
} from "./website-project-preview-oidc-broker.ts";

const encoder = new TextEncoder();

function base64Url(value: Uint8Array | string): string {
  const bytes = typeof value === "string" ? encoder.encode(value) : value;
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-")
    .replaceAll("/", "_").replaceAll("=", "");
}

async function fixture(overrides: Record<string, unknown> = {}) {
  const keys = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const publicJwk = await crypto.subtle.exportKey("jwk", keys.publicKey);
  const now = Math.floor(Date.now() / 1000);
  const claims = {
    iss: "https://token.actions.githubusercontent.com",
    aud: "lws-preview-artifact-receipt",
    sub: "repo:lorenzo-web-solutions/platform:ref:refs/heads/main",
    repository: "lorenzo-web-solutions/platform",
    repository_id: "9001",
    sha: "c".repeat(40),
    ref: "refs/heads/main",
    run_id: "9876",
    workflow_ref: "lorenzo-web-solutions/platform/.github/workflows/build-website-project-preview.yml@refs/heads/main",
    iat: now - 5,
    nbf: now - 5,
    exp: now + 60,
    ...overrides,
  };
  const encodedHeader = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT", kid: "test-key" }));
  const encodedPayload = base64Url(JSON.stringify(claims));
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    keys.privateKey,
    encoder.encode(signingInput),
  );
  return {
    token: `${signingInput}.${base64Url(new Uint8Array(signature))}`,
    fetch: async () => Response.json({ keys: [{ ...publicJwk, kid: "test-key", alg: "RS256", use: "sig" }] }),
  };
}

const expected = {
  audience: "lws-preview-artifact-receipt",
  workflowRepository: "lorenzo-web-solutions/platform",
  workflowRepositoryId: "9001",
  workflowRef: "lorenzo-web-solutions/platform/.github/workflows/build-website-project-preview.yml@refs/heads/main",
  workflowRefName: "refs/heads/main",
  customerRepository: "acme/site",
  customerRepositoryId: "1234",
  customerCommitSha: "a".repeat(40),
  runId: "9876",
  leaseId: "11111111-1111-4111-8111-111111111111",
  buildId: "22222222-2222-4222-8222-222222222222",
};

Deno.test("binds GitHub OIDC to the platform workflow while retaining separate customer authority", async () => {
  const oidc = await fixture();
  const claims = await verifyGitHubActionsOidcToken(oidc.token, expected, {
    fetch: oidc.fetch,
    jwksUrl: "https://token.actions.githubusercontent.com/.well-known/jwks",
  });
  assertEquals(claims.workflowRepositoryId, expected.workflowRepositoryId);
  assertEquals(claims.customerRepositoryId, expected.customerRepositoryId);
  assertEquals(claims.customerCommitSha, expected.customerCommitSha);
  assertEquals(claims.leaseId, expected.leaseId);
  assertEquals(claims.buildId, expected.buildId);
});

Deno.test("accepts GitHub's immutable repository-id subject format", async () => {
  const oidc = await fixture({
    sub: "repo:lorenzo-web-solutions@123456/platform@9001:ref:refs/heads/main",
  });
  const claims = await verifyGitHubActionsOidcToken(oidc.token, expected, { fetch: oidc.fetch });
  assertEquals(claims.workflowRepositoryId, "9001");
});

Deno.test("rejects wrong platform repository, ref, workflow, expiry, and tampering", async () => {
  for (const [override, expectedError] of [
    [{ repository_id: "9999" }, "OIDC_REPOSITORY_MISMATCH"],
    [{ ref: "refs/heads/develop", sub: "repo:lorenzo-web-solutions/platform:ref:refs/heads/develop" }, "OIDC_REF_MISMATCH"],
    [{ workflow_ref: "lorenzo-web-solutions/platform/.github/workflows/other.yml@refs/heads/main" }, "OIDC_WORKFLOW_MISMATCH"],
    [{ exp: Math.floor(Date.now() / 1000) - 1 }, "OIDC_TOKEN_EXPIRED"],
  ] as const) {
    const oidc = await fixture(override);
    await assertRejects(
      () => verifyGitHubActionsOidcToken(oidc.token, expected, { fetch: oidc.fetch }),
      WebsiteProjectPreviewOidcError,
      expectedError,
    );
  }
  const oidc = await fixture();
  await assertRejects(
    () => verifyGitHubActionsOidcToken(`${oidc.token.slice(0, -2)}xx`, expected, { fetch: oidc.fetch }),
    WebsiteProjectPreviewOidcError,
    "OIDC_SIGNATURE_INVALID",
  );
});