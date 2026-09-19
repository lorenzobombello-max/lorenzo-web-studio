import {
  assertEquals,
  assertRejects,
} from "jsr:@std/assert@1";
import {
  canonicalEvidenceSha256,
  evaluateWebsiteRequirement,
  WebsiteRequirementVerificationError,
  type WebsiteRequirementVerificationAuthority,
} from "./website-requirement-verification.ts";
import type {
  WebsiteProjectFilesAuthority,
  WebsiteProjectFilesProvider,
} from "./website-project-files-provider.ts";
import { WebsiteProjectFilesProviderError } from "./website-project-files-provider.ts";

const CONTEXT_ID = "10000000-0000-4000-8000-000000000001";
const QUOTE_ID = "10000000-0000-4000-8000-000000000002";
const BOARD_ID = "10000000-0000-4000-8000-000000000003";
const REQUIREMENT_ID = "10000000-0000-4000-8000-000000000004";
const WORKSPACE_ID = "10000000-0000-4000-8000-000000000005";
const COMMIT_SHA = "a".repeat(40);
const ROOT_TREE_SHA = "b".repeat(40);
const OBJECT_SHA = "c".repeat(40);
const SOURCE_SHA = "d".repeat(64);
const NOW = new Date("2026-09-19T12:00:00.000Z");

function authority(
  overrides: Partial<WebsiteRequirementVerificationAuthority> = {},
): WebsiteRequirementVerificationAuthority {
  return {
    contract_version: 1,
    quote_request_id: QUOTE_ID,
    website_work_context_id: CONTEXT_ID,
    requirements_board_id: BOARD_ID,
    requirement_id: REQUIREMENT_ID,
    requirement_revision: 7,
    completion_mode: "HYBRID",
    rule_key: "website_route_present",
    rule_version: 1,
    source_value_sha256: SOURCE_SHA,
    source_review_state: "CURRENT",
    verification_target: { kind: "DIRECTORY_PATH", value: "pages/about" },
    workspace: {
      website_workspace_id: WORKSPACE_ID,
      binding_revision: 3,
      repository_provider: "GITHUB",
      repository_owner: "lws-fixtures",
      repository_name: "site",
      repository_external_id: "7000000001",
      repository_node_id: "R_task4",
      repository_ref: "heads/main",
      ref_label: "main",
      last_commit_sha: COMMIT_SHA,
      workspace_state: "REPOSITORY_READY",
      repository_operation_state: "COMPLETE",
    },
    ...overrides,
  };
}

function projectFilesAuthority(): WebsiteProjectFilesAuthority {
  return {
    leaseId: "10000000-0000-4000-8000-000000000010",
    actorAuthUserId: "10000000-0000-4000-8000-000000000011",
    quoteRequestId: QUOTE_ID,
    websiteWorkContextId: CONTEXT_ID,
    websiteWorkspaceId: WORKSPACE_ID,
    bindingRevision: 3,
    repositoryProvider: "GITHUB",
    repositoryOwner: "lws-fixtures",
    repositoryName: "site",
    repositoryExternalId: "7000000001",
    repositoryNodeId: "R_task4",
    defaultBranch: "main",
    repositoryRef: "heads/main",
    refLabel: "main",
    markerOperationId: "10000000-0000-4000-8000-000000000012",
    expiresAt: "2026-09-19T12:05:00.000Z",
  };
}

function provider(overrides: Partial<WebsiteProjectFilesProvider> = {}) {
  let snapshotCalls = 0;
  let listCalls = 0;
  let readCalls = 0;
  const value: WebsiteProjectFilesProvider = {
    async resolveSnapshot() {
      snapshotCalls++;
      return {
        commitSha: COMMIT_SHA,
        rootTreeSha: ROOT_TREE_SHA,
        repositoryDisplayName: "lws-fixtures/site",
      };
    },
    async listDirectory(input) {
      listCalls++;
      return { directoryTreeSha: OBJECT_SHA, entries: [] };
    },
    async readFile(input) {
      readCalls++;
      const bytes = new TextEncoder().encode("export const ready = true;\n");
      return {
        path: input.path,
        canonicalPath: input.path,
        mode: "100644",
        objectType: "blob",
        declaredSize: bytes.byteLength,
        bytes,
      };
    },
    ...overrides,
  };
  return {
    value,
    counts: () => ({ snapshotCalls, listCalls, readCalls }),
  };
}

Deno.test("canonical evidence hash uses recursively sorted compact JSON", async () => {
  const first = await canonicalEvidenceSha256({ z: [3, { b: 2, a: 1 }], a: "é" });
  const second = await canonicalEvidenceSha256({ a: "e\u0301", z: [3, { a: 1, b: 2 }] });
  assertEquals(first, second);
  assertEquals(first, "ec9197534aec86f1ce287ab12ed5464bc10169978f6e45bb4b0f3bd877ebb24c");
});

Deno.test("repository route emits exact PASS evidence with one snapshot and one lookup", async () => {
  const fake = provider();
  const result = await evaluateWebsiteRequirement(
    { authority: authority(), projectFilesAuthority: projectFilesAuthority() },
    { provider: fake.value, now: () => NOW },
  );
  assertEquals(result.result, "PASS");
  assertEquals(result.expiresAt, null);
  assertEquals(Object.keys(result.evidenceReference).sort(), [
    "binding_revision",
    "commit_sha",
    "contract_version",
    "details",
    "evidence_type",
    "observed_at",
    "repository_ref",
    "requirement_source_sha256",
    "website_work_context_id",
    "website_workspace_id",
  ]);
  assertEquals(result.evidenceReference.details, {
    path: "pages/about",
    object_type: "tree",
    object_sha: OBJECT_SHA,
  });
  assertEquals(fake.counts(), { snapshotCalls: 1, listCalls: 1, readCalls: 0 });
});

Deno.test("repository file uses one bounded read and never trusts a browser target", async () => {
  const fake = provider();
  const result = await evaluateWebsiteRequirement(
    {
      authority: authority({
        rule_key: "website_module_present",
        verification_target: { kind: "FILE_PATH", value: "src/module.ts" },
      }),
      projectFilesAuthority: projectFilesAuthority(),
    },
    { provider: fake.value, now: () => NOW },
  );
  assertEquals(result.result, "PASS");
  assertEquals(result.evidenceReference.details.path, "src/module.ts");
  assertEquals(result.evidenceReference.details.object_type, "blob");
  assertEquals(fake.counts(), { snapshotCalls: 1, listCalls: 0, readCalls: 1 });
});

Deno.test("content marker requires the exact source-bound line", async () => {
  const marker = `LWS_APPROVED_CONTENT_V1:${SOURCE_SHA}`;
  const bytes = new TextEncoder().encode(`heading\n${marker}\n`);
  const fake = provider({
    async readFile(input) {
      return {
        path: input.path,
        canonicalPath: input.path,
        mode: "100644",
        objectType: "blob",
        declaredSize: bytes.byteLength,
        bytes,
      };
    },
  });
  const result = await evaluateWebsiteRequirement(
    {
      authority: authority({
        rule_key: "approved_content_present",
        verification_target: { kind: "FILE_PATH", value: "content/about.txt" },
      }),
      projectFilesAuthority: projectFilesAuthority(),
    },
    { provider: fake.value, now: () => NOW },
  );
  assertEquals(result.result, "PASS");
  assertEquals(result.evidenceReference.details.marker_key, "LWS_APPROVED_CONTENT");
  assertEquals(result.evidenceReference.details.marker_version, 1);
  assertEquals(
    result.evidenceReference.details.marker_sha256,
    "4d96280e240a6ac3256a70dc7343c20f97f4d559bfa2508d321d82621fadf8ba",
  );
});

Deno.test("authoritative not-found is FAIL and provider unavailability is UNKNOWN", async () => {
  const missing = provider({
    async listDirectory() {
      throw new WebsiteProjectFilesProviderError("PROJECT_FILES_SNAPSHOT_UNAVAILABLE");
    },
  });
  const missingResult = await evaluateWebsiteRequirement(
    { authority: authority(), projectFilesAuthority: projectFilesAuthority() },
    { provider: missing.value, now: () => NOW },
  );
  assertEquals(missingResult.result, "FAIL");

  const unavailable = provider({
    async readFile() {
      throw new WebsiteProjectFilesProviderError("PROJECT_FILES_PROVIDER_TIMEOUT");
    },
  });
  const unavailableResult = await evaluateWebsiteRequirement(
    {
      authority: authority({
        rule_key: "website_module_present",
        verification_target: { kind: "FILE_PATH", value: "src/module.ts" },
      }),
      projectFilesAuthority: projectFilesAuthority(),
    },
    { provider: unavailable.value, now: () => NOW },
  );
  assertEquals(unavailableResult.result, "UNKNOWN");
});

Deno.test("expired authority and sensitive targets fail closed before target reads", async () => {
  const expiredProvider = provider();
  await assertRejects(
    () => evaluateWebsiteRequirement(
      {
        authority: authority(),
        projectFilesAuthority: {
          ...projectFilesAuthority(),
          expiresAt: "2026-09-19T11:59:59.999Z",
        },
      },
      { provider: expiredProvider.value, now: () => NOW },
    ),
    WebsiteRequirementVerificationError,
    "WEBSITE_REQUIREMENT_VERIFICATION_STALE",
  );
  assertEquals(expiredProvider.counts(), { snapshotCalls: 0, listCalls: 0, readCalls: 0 });

  const blockedProvider = provider();
  const blocked = await evaluateWebsiteRequirement(
    {
      authority: authority({
        rule_key: "website_module_present",
        verification_target: { kind: "FILE_PATH", value: ".env" },
      }),
      projectFilesAuthority: projectFilesAuthority(),
    },
    { provider: blockedProvider.value, now: () => NOW },
  );
  assertEquals(blocked.result, "UNKNOWN");
  assertEquals(blockedProvider.counts(), { snapshotCalls: 1, listCalls: 0, readCalls: 0 });
});

Deno.test("trusted test source is bound and produces a 24 hour expiry", async () => {
  const fake = provider();
  const result = await evaluateWebsiteRequirement(
    {
      authority: authority({
        completion_mode: "AUTO",
        rule_key: "website_test_suite_passed",
        verification_target: { kind: "SUITE_ID", value: "release_smoke" },
      }),
      projectFilesAuthority: projectFilesAuthority(),
    },
    {
      provider: fake.value,
      now: () => NOW,
      testRunSource: {
        async read(input: Readonly<{ suiteId: string }>) {
          assertEquals(input.suiteId, "release_smoke");
          return {
            suiteId: input.suiteId,
            suiteVersion: 1,
            runId: "run-42",
            result: "PASS",
            observedAt: NOW.toISOString(),
          };
        },
      },
    },
  );
  assertEquals(result.result, "PASS");
  assertEquals(result.expiresAt, "2026-09-20T12:00:00.000Z");
  assertEquals(fake.counts(), { snapshotCalls: 1, listCalls: 0, readCalls: 0 });
});

Deno.test("unknown rules and authority drift fail closed", async () => {
  const fake = provider();
  await assertRejects(
    () => evaluateWebsiteRequirement(
      {
        authority: authority({ rule_key: "approved_provider_resource" }),
        projectFilesAuthority: projectFilesAuthority(),
      },
      { provider: fake.value, now: () => NOW },
    ),
    WebsiteRequirementVerificationError,
    "UNKNOWN_WEBSITE_REQUIREMENT_RULE",
  );
  await assertRejects(
    () => evaluateWebsiteRequirement(
      {
        authority: authority(),
        projectFilesAuthority: projectFilesAuthority(),
      },
      {
        provider: provider({
          async resolveSnapshot() {
            return {
              commitSha: "f".repeat(40),
              rootTreeSha: ROOT_TREE_SHA,
              repositoryDisplayName: "lws-fixtures/site",
            };
          },
        }).value,
        now: () => NOW,
      },
    ),
    WebsiteRequirementVerificationError,
    "WEBSITE_REQUIREMENT_COMMIT_MISMATCH",
  );
});