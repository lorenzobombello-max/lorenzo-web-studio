import { pathToFileURL } from "node:url";

const TEST_ORGANIZATION = "lorenzo-web-solutions-lab";
const PRODUCTION_ORGANIZATION = "lorenzo-web-solutions";
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const NUMERIC_ID = /^[1-9][0-9]{0,29}$/;
const NODE_ID = /^[A-Za-z0-9_-]{6,128}$/;
const SHA = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const DOSSIER_ID = /^[A-Za-z0-9][A-Za-z0-9_-]{2,127}$/;

export const APPROVED_STARTER = Object.freeze({
  source: "lorenzo-web-solutions/lws-website-starter",
  version: "v1.0.0",
  commitSha: "47e7d7aad37afaa0b3e921fac349a87d2dd2816a",
  treeSha256:
    "6b4a76bf8a64ad91dc18fabe410f032670f03578d2d4c2123dba7cc0e98b5957",
  repositoryId: "1368684860",
});

function fail(code) {
  throw new Error(code);
}

function exactKeys(value, expected) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const actual = Object.keys(value).sort();
  const allowed = [...expected].sort();
  return actual.length === allowed.length &&
    actual.every((key, index) => key === allowed[index]);
}

function repositoryNameForContext(websiteWorkContextId) {
  if (!UUID.test(websiteWorkContextId)) fail("WEBSITE_WORK_CONTEXT_INVALID");
  return `lws-web-${websiteWorkContextId.toLowerCase().replaceAll("-", "")}`;
}

function validateBrowserRequest(value) {
  if (
    !exactKeys(
      value,
      Object.hasOwn(value || {}, "organization")
        ? ["dossierId", "organization"]
        : ["dossierId"],
    )
  ) fail("BROWSER_DTO_INVALID");
  if (!DOSSIER_ID.test(value.dossierId)) fail("BROWSER_DTO_INVALID");
  if (
    Object.hasOwn(value, "organization") &&
    value.organization !== TEST_ORGANIZATION
  ) fail("TEST_ORGANIZATION_REQUIRED");
  return Object.freeze({ dossierId: value.dossierId });
}

function validateContext(value) {
  if (
    !exactKeys(value, [
      "environment",
      "synthetic",
      "realCustomer",
      "websiteWorkspaceId",
      "websiteWorkContextId",
      "idempotencyKey",
    ])
  ) fail("AUTHORITATIVE_CONTEXT_INVALID");
  if (value.environment !== "TEST") fail("TEST_CONTEXT_REQUIRED");
  if (value.synthetic !== true || value.realCustomer !== false) {
    fail("SYNTHETIC_CONTEXT_REQUIRED");
  }
  if (
    !UUID.test(value.websiteWorkspaceId) ||
    !UUID.test(value.websiteWorkContextId) ||
    !UUID.test(value.idempotencyKey)
  ) fail("AUTHORITATIVE_CONTEXT_INVALID");
  return Object.freeze({ ...value });
}

function validProviderResult(value, request) {
  return exactKeys(value, [
    "provider",
    "providerRepositoryId",
    "providerNodeId",
    "owner",
    "name",
    "visibility",
    "defaultBranch",
    "starterSource",
    "starterVersion",
    "starterCommitSha",
    "starterTreeSha256",
    "repositoryMarkerCommitSha",
    "markerWebsiteWorkContextId",
  ]) && value.provider === "GITHUB" &&
    NUMERIC_ID.test(value.providerRepositoryId) &&
    NODE_ID.test(value.providerNodeId) &&
    value.owner === TEST_ORGANIZATION &&
    value.owner !== PRODUCTION_ORGANIZATION &&
    value.name === request.repositoryName &&
    value.visibility === "PRIVATE" &&
    value.defaultBranch === "main" &&
    value.starterSource === APPROVED_STARTER.source &&
    value.starterVersion === APPROVED_STARTER.version &&
    value.starterCommitSha === APPROVED_STARTER.commitSha &&
    value.starterTreeSha256 === APPROVED_STARTER.treeSha256 &&
    SHA.test(value.repositoryMarkerCommitSha) &&
    value.markerWebsiteWorkContextId === request.websiteWorkContextId;
}

function providerRequest(context, mode) {
  return Object.freeze({
    mode,
    websiteWorkspaceId: context.websiteWorkspaceId,
    websiteWorkContextId: context.websiteWorkContextId,
    idempotencyKey: context.idempotencyKey,
    repositoryName: repositoryNameForContext(context.websiteWorkContextId),
    sourcePrincipal: Object.freeze({
      target: "PRODUCTION",
      organization: PRODUCTION_ORGANIZATION,
      repository: "lws-website-starter",
      repositoryIds: Object.freeze([APPROVED_STARTER.repositoryId]),
      permissions: Object.freeze({ metadata: "read", contents: "read" }),
    }),
    labPrincipal: Object.freeze({
      target: "TEST",
      organization: TEST_ORGANIZATION,
      create: Object.freeze({
        repositoryIds: Object.freeze([]),
        permissions: Object.freeze({
          metadata: "read",
          administration: "write",
        }),
      }),
      repository: Object.freeze({
        scope: "CAPTURED_REPOSITORY_ID",
        permissions: Object.freeze({ metadata: "read", contents: "write" }),
      }),
    }),
    starter: APPROVED_STARTER,
  });
}

function redactedEvidence(request, result, externalMutations) {
  return Object.freeze({
    mode: request.mode,
    websiteWorkContextId: request.websiteWorkContextId,
    target: Object.freeze({
      environment: request.labPrincipal.target,
      organization: request.labPrincipal.organization,
      repository: request.repositoryName,
    }),
    principals: Object.freeze({
      source: request.sourcePrincipal,
      lab: request.labPrincipal,
    }),
    starter: APPROVED_STARTER,
    provider: Object.freeze({
      repositoryId: result.providerRepositoryId,
      nodeId: result.providerNodeId,
      markerCommitSha: result.repositoryMarkerCommitSha,
      treeEquality: true,
      markerReadback: true,
    }),
    externalMutations,
  });
}

export function parseTestIslandArguments(arguments_) {
  if (arguments_.length === 0) return Object.freeze({ execute: false });
  if (arguments_.length === 1 && arguments_[0] === "--execute") {
    return Object.freeze({ execute: true });
  }
  fail("ARGUMENT_INVALID");
}

export function createTestIslandHarness(dependencies) {
  if (
    !dependencies || typeof dependencies.resolveContext !== "function" ||
    !dependencies.provider ||
    typeof dependencies.provider.dryRun !== "function" ||
    typeof dependencies.log !== "function"
  ) fail("HARNESS_DEPENDENCIES_INVALID");

  async function run(
    browserRequest,
    options = Object.freeze({ execute: false }),
  ) {
    const requestDto = validateBrowserRequest(browserRequest);
    const context = validateContext(
      await dependencies.resolveContext(requestDto),
    );
    const execute = options?.execute === true;
    const mode = execute ? "EXECUTE" : "DRY_RUN";
    if (
      execute &&
      typeof dependencies.provider.executeServerRoute !== "function"
    ) fail("LIVE_EXECUTION_NOT_AUTHORIZED");
    const operation = execute
      ? dependencies.provider.executeServerRoute
      : dependencies.provider.dryRun;
    const request = providerRequest(context, mode);
    const result = await operation(request);
    if (!validProviderResult(result, request)) fail("PROVIDER_RESULT_INVALID");
    const externalMutations = execute ? 1 : 0;
    const evidence = redactedEvidence(request, result, externalMutations);
    dependencies.log(Object.freeze({
      event: "GITHUB_TEST_ISLAND_EVIDENCE",
      mode: evidence.mode,
      websiteWorkContextId: evidence.websiteWorkContextId,
      organization: evidence.target.organization,
      repository: evidence.target.repository,
      repositoryId: evidence.provider.repositoryId,
      externalMutations,
    }));
    return evidence;
  }

  return Object.freeze({
    prepare(browserRequest) {
      return run(browserRequest, Object.freeze({ execute: false }));
    },
    run,
  });
}

function localDryRunHarness() {
  const context = Object.freeze({
    environment: "TEST",
    synthetic: true,
    realCustomer: false,
    websiteWorkspaceId: "d1110000-0000-4000-8000-000000000001",
    websiteWorkContextId: "d1120000-0000-4000-8000-000000000001",
    idempotencyKey: "d1130000-0000-4000-8000-000000000001",
  });
  return createTestIslandHarness({
    resolveContext: async () => context,
    provider: {
      dryRun: async (request) =>
        Object.freeze({
          provider: "GITHUB",
          providerRepositoryId: "2000000001",
          providerNodeId: "R_test_island_000001",
          owner: request.labPrincipal.organization,
          name: request.repositoryName,
          visibility: "PRIVATE",
          defaultBranch: "main",
          starterSource: request.starter.source,
          starterVersion: request.starter.version,
          starterCommitSha: request.starter.commitSha,
          starterTreeSha256: request.starter.treeSha256,
          repositoryMarkerCommitSha: "a".repeat(40),
          markerWebsiteWorkContextId: request.websiteWorkContextId,
        }),
    },
    log: () => {},
  });
}

if (
  process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url
) {
  const options = parseTestIslandArguments(process.argv.slice(2));
  if (options.execute) fail("LIVE_EXECUTION_NOT_AUTHORIZED");
  const evidence = await localDryRunHarness().prepare({
    dossierId: "synthetic-dossier-1",
  });
  console.log(JSON.stringify(evidence));
}
