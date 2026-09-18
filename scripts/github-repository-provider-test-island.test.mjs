import assert from "node:assert/strict";
import test from "node:test";

import {
  APPROVED_STARTER,
  createTestIslandHarness,
  parseTestIslandArguments,
} from "./github-repository-provider-test-island.mjs";

const TEST_ORGANIZATION = "lorenzo-web-solutions-lab";
const PRODUCTION_ORGANIZATION = "lorenzo-web-solutions";
const WEBSITE_WORK_CONTEXT_ID = "d1120000-0000-4000-8000-000000000001";
const OTHER_WEBSITE_WORK_CONTEXT_ID = "d1120000-0000-4000-8000-000000000002";

function syntheticContext(overrides = {}) {
  return Object.freeze({
    environment: "TEST",
    synthetic: true,
    realCustomer: false,
    websiteWorkspaceId: "d1110000-0000-4000-8000-000000000001",
    websiteWorkContextId: WEBSITE_WORK_CONTEXT_ID,
    idempotencyKey: "d1130000-0000-4000-8000-000000000001",
    ...overrides,
  });
}

function validProviderResult(overrides = {}) {
  return Object.freeze({
    provider: "GITHUB",
    providerRepositoryId: "2000000001",
    providerNodeId: "R_test_island_000001",
    owner: TEST_ORGANIZATION,
    name: "lws-web-d1120000000040008000000000000001",
    visibility: "PRIVATE",
    defaultBranch: "main",
    starterSource: APPROVED_STARTER.source,
    starterVersion: APPROVED_STARTER.version,
    starterCommitSha: APPROVED_STARTER.commitSha,
    starterTreeSha256: APPROVED_STARTER.treeSha256,
    repositoryMarkerCommitSha: "a".repeat(40),
    markerWebsiteWorkContextId: WEBSITE_WORK_CONTEXT_ID,
    ...overrides,
  });
}

function fixture(providerResult = validProviderResult()) {
  const calls = [];
  const logs = [];
  const harness = createTestIslandHarness({
    resolveContext: async () => syntheticContext(),
    provider: {
      dryRun: async (request) => {
        calls.push(request);
        return providerResult;
      },
    },
    log: (entry) => logs.push(entry),
  });
  return { harness, calls, logs };
}

test("dry-run is default and --execute remains explicitly gated", () => {
  assert.deepEqual(parseTestIslandArguments([]), { execute: false });
  assert.deepEqual(parseTestIslandArguments(["--execute"]), { execute: true });
  assert.throws(
    () => parseTestIslandArguments(["--unknown"]),
    /ARGUMENT_INVALID/,
  );
});

test("execute mode calls only the injected server-side route and never local GitHub authority", async () => {
  const calls = [];
  const harness = createTestIslandHarness({
    resolveContext: async () => syntheticContext(),
    provider: {
      dryRun: async () => validProviderResult(),
      executeServerRoute: async (request) => {
        calls.push(request);
        return validProviderResult();
      },
    },
    ownerGate6Approved: true,
    log: () => {},
  });
  const evidence = await harness.run(
    { dossierId: "synthetic-dossier-1" },
    { execute: true },
  );
  assert.equal(calls.length, 1);
  assert.equal(evidence.mode, "EXECUTE");
  assert.equal(evidence.externalMutations, 1);
  assert.equal(Object.hasOwn(calls[0], "token"), false);
  assert.equal(Object.hasOwn(calls[0], "privateKey"), false);
});

test("standalone execute remains fail-closed without a server route client", async () => {
  const { harness } = fixture();
  await assert.rejects(
    () => harness.run({ dossierId: "synthetic-dossier-1" }, { execute: true }),
    /LIVE_EXECUTION_NOT_AUTHORIZED/,
  );
});

test("TEST environment resolves only the lab organization", async () => {
  const { harness } = fixture();
  const evidence = await harness.prepare({ dossierId: "synthetic-dossier-1" });
  assert.equal(evidence.target.environment, "TEST");
  assert.equal(evidence.target.organization, TEST_ORGANIZATION);
});

test("production organization substitution is denied before provider use", async () => {
  const testCase = fixture();
  await assert.rejects(
    () =>
      testCase.harness.prepare({
        dossierId: "synthetic-dossier-1",
        organization: PRODUCTION_ORGANIZATION,
      }),
    /TEST_ORGANIZATION_REQUIRED/,
  );
  assert.equal(testCase.calls.length, 0);
});

test("production context cannot target the test organization", async () => {
  const calls = [];
  const harness = createTestIslandHarness({
    resolveContext: async () => syntheticContext({ environment: "PRODUCTION" }),
    provider: { dryRun: async (request) => calls.push(request) },
    log: () => {},
  });
  await assert.rejects(
    () => harness.prepare({ dossierId: "synthetic-dossier-1" }),
    /TEST_CONTEXT_REQUIRED/,
  );
  assert.equal(calls.length, 0);
});

test("repository target is deterministic from website_work_context_id", async () => {
  const first = fixture();
  const second = fixture();
  const firstEvidence = await first.harness.prepare({
    dossierId: "synthetic-dossier-1",
  });
  const secondEvidence = await second.harness.prepare({
    dossierId: "synthetic-dossier-1",
  });
  assert.equal(
    firstEvidence.target.repository,
    secondEvidence.target.repository,
  );
  assert.equal(
    firstEvidence.target.repository,
    "lws-web-d1120000000040008000000000000001",
  );
});

test("canonical starter provenance is fixed to the approved release", async () => {
  const { harness } = fixture();
  const evidence = await harness.prepare({ dossierId: "synthetic-dossier-1" });
  assert.deepEqual(evidence.starter, {
    source: "lorenzo-web-solutions/lws-website-starter",
    version: "v1.0.0",
    commitSha: "47e7d7aad37afaa0b3e921fac349a87d2dd2816a",
    treeSha256:
      "6b4a76bf8a64ad91dc18fabe410f032670f03578d2d4c2123dba7cc0e98b5957",
    repositoryId: "1368684860",
  });
});

test("cross-context marker and repository identity mismatches are denied", async () => {
  for (
    const result of [
      validProviderResult({
        markerWebsiteWorkContextId: OTHER_WEBSITE_WORK_CONTEXT_ID,
      }),
      validProviderResult({ providerRepositoryId: "not-numeric" }),
      validProviderResult({ name: "shared-customer-repository" }),
      validProviderResult({ starterTreeSha256: "b".repeat(64) }),
    ]
  ) {
    const testCase = fixture(result);
    await assert.rejects(
      () => testCase.harness.prepare({ dossierId: "synthetic-dossier-1" }),
      /PROVIDER_RESULT_INVALID/,
    );
  }
});

test("same customer cannot mix distinct website work contexts", async () => {
  const calls = [];
  const harness = createTestIslandHarness({
    resolveContext: async ({ dossierId }) =>
      syntheticContext({
        websiteWorkContextId: dossierId.endsWith("2")
          ? OTHER_WEBSITE_WORK_CONTEXT_ID
          : WEBSITE_WORK_CONTEXT_ID,
      }),
    provider: {
      dryRun: async (request) => {
        calls.push(request);
        return validProviderResult({
          name: request.repositoryName,
          markerWebsiteWorkContextId: request.websiteWorkContextId,
        });
      },
    },
    log: () => {},
  });
  const first = await harness.prepare({ dossierId: "synthetic-customer-1" });
  const second = await harness.prepare({ dossierId: "synthetic-customer-2" });
  assert.notEqual(first.target.repository, second.target.repository);
  assert.equal(calls.length, 2);
});

test("test dossier cannot mutate a real customer or accept malformed results", async () => {
  for (
    const context of [
      syntheticContext({ synthetic: false }),
      syntheticContext({ realCustomer: true }),
    ]
  ) {
    const calls = [];
    const harness = createTestIslandHarness({
      resolveContext: async () => context,
      provider: { dryRun: async (request) => calls.push(request) },
      log: () => {},
    });
    await assert.rejects(
      () => harness.prepare({ dossierId: "synthetic-dossier-1" }),
      /SYNTHETIC_CONTEXT_REQUIRED/,
    );
    assert.equal(calls.length, 0);
  }

  const malformed = fixture({ unexpected: true });
  await assert.rejects(
    () => malformed.harness.prepare({ dossierId: "synthetic-dossier-1" }),
    /PROVIDER_RESULT_INVALID/,
  );
});

test("browser DTO rejects credentials and Website/SDF shortcut authority", async () => {
  const privateKey =
    "-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----";
  const token = "synthetic_installation_token_value";
  const testCase = fixture();
  for (
    const forbidden of [
      { privateKey },
      { token },
      { websiteId: "website-shortcut" },
      { sdfId: "sdf-shortcut" },
    ]
  ) {
    await assert.rejects(
      () =>
        testCase.harness.prepare({
          dossierId: "synthetic-dossier-1",
          ...forbidden,
        }),
      /BROWSER_DTO_INVALID/,
    );
  }
  const evidence = await testCase.harness.prepare({
    dossierId: "synthetic-dossier-1",
  });
  const serialized = JSON.stringify({ evidence, logs: testCase.logs });
  assert.doesNotMatch(
    serialized,
    /PRIVATE KEY|synthetic_installation_token_value/,
  );
  assert.deepEqual(Object.keys(evidence).sort(), [
    "externalMutations",
    "mode",
    "principals",
    "provider",
    "starter",
    "target",
    "websiteWorkContextId",
  ]);
});

test("dry-run produces zero external mutations and no shared mutable worktree", async () => {
  const testCase = fixture();
  const evidence = await testCase.harness.prepare({
    dossierId: "synthetic-dossier-1",
  });
  assert.equal(evidence.mode, "DRY_RUN");
  assert.equal(evidence.externalMutations, 0);
  assert.equal(testCase.calls.length, 1);
  assert.equal(testCase.calls[0].mode, "DRY_RUN");
  assert.equal(Object.hasOwn(testCase.calls[0], "worktree"), false);
  assert.equal(Object.hasOwn(testCase.calls[0], "token"), false);
  assert.equal(Object.hasOwn(testCase.calls[0], "privateKey"), false);
  assert.equal(Object.hasOwn(testCase.calls[0], "permissions"), false);
  assert.deepEqual(testCase.calls[0].sourcePrincipal.repositoryIds, [
    APPROVED_STARTER.repositoryId,
  ]);
  assert.deepEqual(testCase.calls[0].sourcePrincipal.permissions, {
    metadata: "read",
    contents: "read",
  });
  assert.deepEqual(testCase.calls[0].labPrincipal.create.repositoryIds, []);
  assert.deepEqual(testCase.calls[0].labPrincipal.create.permissions, {
    metadata: "read",
    administration: "write",
  });
  assert.deepEqual(testCase.calls[0].labPrincipal.repository, {
    scope: "CAPTURED_REPOSITORY_ID",
    permissions: { metadata: "read", contents: "write" },
  });
});
