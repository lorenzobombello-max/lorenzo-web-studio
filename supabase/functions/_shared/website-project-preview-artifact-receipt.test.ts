import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  createWebsiteProjectPreviewArtifactReceiptService,
  WebsiteProjectPreviewArtifactReceiptError,
} from "./website-project-preview-artifact-receipt.ts";

const authority = Object.freeze({
  audience: "lws-preview-artifact-receipt",
  workflowRepository: "lorenzo/platform",
  workflowRepositoryId: "9001",
  workflowRef: "lorenzo/platform/.github/workflows/build.yml@refs/heads/main",
  workflowRefName: "refs/heads/main",
  customerRepository: "lorenzo/customer-site",
  customerRepositoryId: "7300000001",
  customerCommitSha: "a".repeat(40),
  runId: "9876",
  leaseId: "d1000000-0000-4000-8000-000000000001",
  buildId: "d2000000-0000-4000-8000-000000000001",
});

function dependencies() {
  const calls: Array<Readonly<{ name: string; value?: string }>> = [];
  return {
    calls,
    dependencies: {
      resolveAuthority: async () => authority,
      verifyOidc: async (_token: string, expected: typeof authority) => {
        calls.push({ name: "verify", value: expected.workflowRepository });
        return expected;
      },
      issueToken: async (input: Readonly<{ tokenHash: string }>) => {
        calls.push({ name: "issue", value: input.tokenHash });
        return { expiresAt: "2026-09-23T10:05:00.000Z" };
      },
      openSession: async (input: Readonly<{ receiptTokenHash: string; sessionTokenHash: string }>) => {
        calls.push({ name: "open", value: `${input.receiptTokenHash}:${input.sessionTokenHash}` });
        return { expiresAt: "2026-09-23T10:10:00.000Z" };
      },
      claimFile: async (input: Readonly<{ file: Readonly<{ relativePath: string }> }>) => {
        calls.push({ name: "claim", value: input.file.relativePath });
      },
      completeFile: async (input: Readonly<{ relativePath: string }>) => {
        calls.push({ name: "complete", value: input.relativePath });
      },
      finalizeSession: async () => {
        calls.push({ name: "finalize" });
        return { previewBuildId: "d3000000-0000-4000-8000-000000000001", buildStatus: "PASS" };
      },
      abortSession: async () => {
        calls.push({ name: "abort" });
        return { uploadedPaths: ["index.html"] };
      },
      upload: async (input: Readonly<{ relativePath: string }>) => {
        calls.push({ name: "upload", value: input.relativePath });
      },
      remove: async (paths: readonly string[]) => {
        for (const path of paths) calls.push({ name: "remove", value: path });
      },
      randomBytes: () => new Uint8Array(32).fill(7),
    },
  };
}

Deno.test("artifact broker resolves authority server-side and persists only a token hash", async () => {
  const fixture = dependencies();
  const service = createWebsiteProjectPreviewArtifactReceiptService(fixture.dependencies);
  const result = await service.issue({
    oidcToken: "signed-oidc-token",
    leaseId: authority.leaseId,
    buildId: authority.buildId,
    workflowRunId: authority.runId,
  });

  assertEquals(result.token, "0707070707070707070707070707070707070707070707070707070707070707");
  assertEquals(result.expiresAt, "2026-09-23T10:05:00.000Z");
  assertEquals(fixture.calls.map((call) => call.name), ["verify", "issue"]);
  assertEquals(fixture.calls[1].value === result.token, false);
  assertEquals(fixture.calls[1].value?.length, 64);
});

Deno.test("one-time receipt authorization opens one hash-only bounded upload session", async () => {
  const fixture = dependencies();
  const service = createWebsiteProjectPreviewArtifactReceiptService(fixture.dependencies);
  const result = await service.begin({
    receiptToken: "f".repeat(64),
    leaseId: authority.leaseId,
    buildId: authority.buildId,
    repositoryId: authority.customerRepositoryId,
    commitSha: authority.customerCommitSha,
    workflowRunId: authority.runId,
    primaryRelativePath: "index.html",
    buildStatus: "PASS",
    manifest: [{ relativePath: "index.html", contentType: "text/html", sha256: "b".repeat(64), bytes: 18 }],
  });

  assertEquals(result.sessionToken, "0707070707070707070707070707070707070707070707070707070707070707");
  assertEquals(result.expiresAt, "2026-09-23T10:10:00.000Z");
  assertEquals(fixture.calls.map((call) => call.name), ["open"]);
  const [receiptHash, sessionHash] = fixture.calls[0].value!.split(":");
  assertEquals(receiptHash.length, 64);
  assertEquals(sessionHash.length, 64);
  assertEquals(receiptHash === "f".repeat(64), false);
  assertEquals(sessionHash === result.sessionToken, false);
});

Deno.test("raw file upload claims expected path before Storage and completes after upload", async () => {
  const fixture = dependencies();
  const service = createWebsiteProjectPreviewArtifactReceiptService(fixture.dependencies);
  const bytes = new TextEncoder().encode("<h1>Preview</h1>");
  const sha256 = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
  const result = await service.uploadFile({
    sessionToken: "e".repeat(64),
    leaseId: authority.leaseId,
    buildId: authority.buildId,
    repositoryId: authority.customerRepositoryId,
    commitSha: authority.customerCommitSha,
    workflowRunId: authority.runId,
    relativePath: "index.html",
    contentType: "text/html; charset=utf-8",
    sha256,
    bytes,
  });

  assertEquals(result, { relativePath: "index.html", bytes: bytes.byteLength });
  assertEquals(fixture.calls.map((call) => call.name), ["claim", "upload", "complete"]);
});

Deno.test("completion failure aborts and removes the already-uploaded object", async () => {
  const fixture = dependencies();
  fixture.dependencies.completeFile = async () => {
    fixture.calls.push({ name: "complete" });
    throw new Error("COMPLETE_FAILED");
  };
  const service = createWebsiteProjectPreviewArtifactReceiptService(fixture.dependencies);
  const bytes = new TextEncoder().encode("<h1>Preview</h1>");
  const sha256 = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
  await assertRejects(() => service.uploadFile({
    sessionToken: "e".repeat(64),
    leaseId: authority.leaseId,
    buildId: authority.buildId,
    repositoryId: authority.customerRepositoryId,
    commitSha: authority.customerCommitSha,
    workflowRunId: authority.runId,
    relativePath: "index.html",
    contentType: "text/html",
    sha256,
    bytes,
  }), Error, "COMPLETE_FAILED");
  assertEquals(fixture.calls.map((call) => call.name), ["claim", "upload", "complete", "abort", "remove"]);
});

Deno.test("explicit abort retries cleanup after an earlier Storage remove failure", async () => {
  const fixture = dependencies();
  let attempts = 0;
  fixture.dependencies.remove = async () => {
    attempts += 1;
    if (attempts === 1) throw new Error("REMOVE_FAILED");
    fixture.calls.push({ name: "remove", value: "index.html" });
  };
  const service = createWebsiteProjectPreviewArtifactReceiptService(fixture.dependencies);
  const input = {
    sessionToken: "e".repeat(64),
    leaseId: authority.leaseId,
    buildId: authority.buildId,
    repositoryId: authority.customerRepositoryId,
    commitSha: authority.customerCommitSha,
    workflowRunId: authority.runId,
  };
  await assertRejects(() => service.abort(input), Error, "REMOVE_FAILED");
  assertEquals(await service.abort(input), { removedPaths: ["index.html"] });
  assertEquals(attempts, 2);
});

Deno.test("incomplete workflow finalize aborts session and removes stored objects", async () => {
  const fixture = dependencies();
  fixture.dependencies.finalizeSession = async () => {
    fixture.calls.push({ name: "finalize" });
    throw new Error("ARTIFACT_SESSION_INCOMPLETE");
  };
  const service = createWebsiteProjectPreviewArtifactReceiptService(fixture.dependencies);
  await assertRejects(
    () => service.finalize({
      sessionToken: "e".repeat(64),
      leaseId: authority.leaseId,
      buildId: authority.buildId,
      repositoryId: authority.customerRepositoryId,
      commitSha: authority.customerCommitSha,
      workflowRunId: authority.runId,
    }),
    Error,
    "ARTIFACT_SESSION_INCOMPLETE",
  );
  assertEquals(fixture.calls.map((call) => call.name), ["finalize", "abort", "remove"]);
});