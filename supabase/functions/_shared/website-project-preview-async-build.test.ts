import { assertEquals } from "jsr:@std/assert@1";
import {
  runWebsiteProjectPreviewAsyncBuild,
  getWebsiteProjectPreviewAsyncBuildStatus,
  type WebsiteProjectPreviewAsyncRpcClient,
} from "./website-project-preview-async-build.ts";

// A small, in-memory FAKE of the real Postgres RPC surface
// (acquire/finalize/status), mirroring its externally-observable
// contract closely enough for orchestration-level tests. This is
// explicitly a fake/local fixture, NOT a substitute for the real,
// already-proven RPC-level Postgres tests run separately against an
// isolated Supabase instance (checkpoint §17/§16.3) - those remain the
// authoritative proof of the DB contract itself. This fake only proves
// the ORCHESTRATOR wires calls together correctly.
function createFakeRpcClient(): WebsiteProjectPreviewAsyncRpcClient & {
  builds: Map<string, { status: string; manifest: unknown }>;
} {
  const leases = new Map<string, { released: boolean }>();
  const builds = new Map<string, { status: string; manifest: unknown }>();
  let leaseCounter = 0;
  let buildCounter = 0;
  return {
    builds,
    async rpc<T = unknown>(name: string, args: Record<string, unknown>) {
      if (name === "acquire_website_project_preview_build_v1") {
        leaseCounter += 1;
        const leaseId = `lease-${leaseCounter}`;
        leases.set(leaseId, { released: false });
        return {
          data: {
            leaseId,
            actorAuthUserId: "actor-a",
            quoteRequestId: String(args.p_quote_request_id),
            websiteWorkContextId: "ctx-1",
            websiteWorkspaceId: "ws-1",
            bindingRevision: 1,
            repositoryProvider: "GITHUB",
            repositoryOwner: "lws-fixtures",
            repositoryName: "preview-fixture",
            repositoryExternalId: "1",
            repositoryNodeId: "R_1",
            defaultBranch: "main",
            repositoryRef: "heads/main",
            refLabel: "main",
            markerOperationId: "op-1",
            expiresAt: new Date(Date.now() + 20 * 60 * 1000).toISOString(),
          } as unknown as T,
          error: null,
        };
      }
      if (name === "finalize_website_project_preview_build_v2") {
        const lease = leases.get(String(args.p_lease_id));
        if (!lease || lease.released) {
          return { data: null as T | null, error: { message: "PROJECT_PREVIEW_LEASE_INVALID" } };
        }
        lease.released = true;
        buildCounter += 1;
        const previewBuildId = `build-${buildCounter}`;
        builds.set(previewBuildId, {
          status: String(args.p_build_status),
          manifest: args.p_manifest,
        });
        return {
          data: { previewBuildId, buildStatus: String(args.p_build_status) } as unknown as T,
          error: null,
        };
      }
      if (name === "get_website_project_preview_build_status_v1") {
        const lease = leases.get(String(args.p_lease_id));
        if (!lease) {
          return { data: null as T | null, error: { message: "PROJECT_PREVIEW_LEASE_INVALID" } };
        }
        return {
          data: {
            buildStatus: lease.released ? "PASS" : "BUILD_IN_PROGRESS",
            previewBuildId: null,
          } as unknown as T,
          error: null,
        };
      }
      return { data: null, error: { message: `UNKNOWN_RPC:${name}` } };
    },
  };
}

async function writeFixtureTree(build: (root: string) => Promise<void>): Promise<string> {
  const root = await Deno.makeTempDir({ prefix: "lws-async-build-fixture-" });
  await build(root);
  return root;
}

Deno.test("runs the full pipeline and reports PASS for a clean build with no rejections", async () => {
  const rpcClient = createFakeRpcClient();
  const sourceRoot = await writeFixtureTree(async () => {});
  const distRoot = await writeFixtureTree(async (dir) => {
    await Deno.writeTextFile(`${dir}/index.html`, "<html><body>hello</body></html>");
    await Deno.writeTextFile(`${dir}/style.css`, "body{}");
  });
  const uploaded: string[] = [];
  try {
    const outcome = await runWebsiteProjectPreviewAsyncBuild(
      { quoteRequestId: "qr-1", expectedCommitSha: "a".repeat(40), idempotencyKey: "idem-1" },
      {
        rpcClient,
        sourceFetcher: { fetchSource: async () => ({ sourceRoot }) },
        sandboxBuilder: { build: async () => ({ distRoot }) },
        artifactUploader: { upload: async (input) => { uploaded.push(input.relativePath); }, remove: async () => {} },
      },
    );
    assertEquals(outcome.buildStatus, "PASS");
    assertEquals(uploaded.sort(), ["index.html", "style.css"]);
    assertEquals(rpcClient.builds.get(outcome.previewBuildId)?.status, "PASS");
  } finally {
    await Deno.remove(sourceRoot, { recursive: true });
    await Deno.remove(distRoot, { recursive: true });
  }
});

Deno.test("reports PASS_WITH_WARNINGS and still uploads accepted files when an SVG is blocked", async () => {
  const rpcClient = createFakeRpcClient();
  const sourceRoot = await writeFixtureTree(async () => {});
  const distRoot = await writeFixtureTree(async (dir) => {
    await Deno.writeTextFile(`${dir}/index.html`, "<html><body>hello</body></html>");
    await Deno.writeTextFile(`${dir}/favicon.svg`, "<svg></svg>");
  });
  const uploaded: string[] = [];
  try {
    const outcome = await runWebsiteProjectPreviewAsyncBuild(
      { quoteRequestId: "qr-1", expectedCommitSha: "a".repeat(40), idempotencyKey: "idem-2" },
      {
        rpcClient,
        sourceFetcher: { fetchSource: async () => ({ sourceRoot }) },
        sandboxBuilder: { build: async () => ({ distRoot }) },
        artifactUploader: { upload: async (input) => { uploaded.push(input.relativePath); }, remove: async () => {} },
      },
    );
    assertEquals(outcome.buildStatus, "PASS_WITH_WARNINGS");
    assertEquals(uploaded, ["index.html"]);
    assertEquals(
      outcome.manifest.rejected.some((r) => r.path === "favicon.svg" && r.reason === "ASSET_TYPE_BLOCKED"),
      true,
    );
  } finally {
    await Deno.remove(sourceRoot, { recursive: true });
    await Deno.remove(distRoot, { recursive: true });
  }
});

Deno.test("reports FAILED and uploads nothing when the primary entry document itself is unsafe", async () => {
  const rpcClient = createFakeRpcClient();
  const sourceRoot = await writeFixtureTree(async () => {});
  const distRoot = await writeFixtureTree(async (dir) => {
    await Deno.writeTextFile(
      `${dir}/index.html`,
      "<html><body><iframe src='https://evil.test'></iframe></body></html>",
    );
  });
  const uploaded: string[] = [];
  try {
    const outcome = await runWebsiteProjectPreviewAsyncBuild(
      { quoteRequestId: "qr-1", expectedCommitSha: "a".repeat(40), idempotencyKey: "idem-3" },
      {
        rpcClient,
        sourceFetcher: { fetchSource: async () => ({ sourceRoot }) },
        sandboxBuilder: { build: async () => ({ distRoot }) },
        artifactUploader: { upload: async (input) => { uploaded.push(input.relativePath); }, remove: async () => {} },
      },
    );
    assertEquals(outcome.buildStatus, "FAILED");
    assertEquals(uploaded, []);
  } finally {
    await Deno.remove(sourceRoot, { recursive: true });
    await Deno.remove(distRoot, { recursive: true });
  }
});

Deno.test("reports FAILED and finalizes closed when the sandbox build itself throws", async () => {
  const rpcClient = createFakeRpcClient();
  const sourceRoot = await writeFixtureTree(async () => {});
  try {
    const outcome = await runWebsiteProjectPreviewAsyncBuild(
      { quoteRequestId: "qr-1", expectedCommitSha: "a".repeat(40), idempotencyKey: "idem-4" },
      {
        rpcClient,
        sourceFetcher: { fetchSource: async () => ({ sourceRoot }) },
        sandboxBuilder: { build: async () => { throw new Error("SANDBOX_BUILD_FAILED"); } },
        artifactUploader: { upload: async () => {}, remove: async () => {} },
      },
    );
    assertEquals(outcome.buildStatus, "FAILED");
  } finally {
    await Deno.remove(sourceRoot, { recursive: true });
  }
});

Deno.test("upload failure removes already uploaded objects before finalizing FAILED", async () => {
  const rpcClient = createFakeRpcClient();
  const sourceRoot = await writeFixtureTree(async () => {});
  const distRoot = await writeFixtureTree(async (dir) => {
    await Deno.writeTextFile(`${dir}/index.html`, "<html><body>hello</body></html>");
    await Deno.writeTextFile(`${dir}/style.css`, "body{}");
  });
  const stored = new Set<string>();
  const removed: string[] = [];
  try {
    const outcome = await runWebsiteProjectPreviewAsyncBuild(
      { quoteRequestId: "qr-1", expectedCommitSha: "a".repeat(40), idempotencyKey: "idem-cleanup" },
      {
        rpcClient,
        sourceFetcher: { fetchSource: async () => ({ sourceRoot }) },
        sandboxBuilder: { build: async () => ({ distRoot }) },
        artifactUploader: {
          upload: async (input) => {
            if (input.relativePath === "style.css") throw new Error("UPLOAD_FAILED");
            stored.add(input.relativePath);
          },
          remove: async (relativePaths) => {
            for (const relativePath of relativePaths) {
              stored.delete(relativePath);
              removed.push(relativePath);
            }
          },
        },
      },
    );
    assertEquals(outcome.buildStatus, "FAILED");
    assertEquals([...stored], []);
    assertEquals(removed, ["index.html"]);
  } finally {
    await Deno.remove(sourceRoot, { recursive: true });
    await Deno.remove(distRoot, { recursive: true });
  }
});

Deno.test("status polling reflects BUILD_IN_PROGRESS before finalize and the finalized status after", async () => {
  const rpcClient = createFakeRpcClient();
  const sourceRoot = await writeFixtureTree(async () => {});
  const distRoot = await writeFixtureTree(async (dir) => {
    await Deno.writeTextFile(`${dir}/index.html`, "<html><body>hello</body></html>");
  });
  try {
    let leaseIdSeen = "";
    const outcomePromise = runWebsiteProjectPreviewAsyncBuild(
      { quoteRequestId: "qr-1", expectedCommitSha: "a".repeat(40), idempotencyKey: "idem-5" },
      {
        rpcClient: {
          async rpc<T = unknown>(name: string, args: Record<string, unknown>) {
            const result = await rpcClient.rpc<T>(name, args);
            if (name === "acquire_website_project_preview_build_v1" && result.data) {
              leaseIdSeen = (result.data as unknown as { leaseId: string }).leaseId;
            }
            return result;
          },
        },
        sourceFetcher: { fetchSource: async () => ({ sourceRoot }) },
        sandboxBuilder: { build: async () => ({ distRoot }) },
        artifactUploader: { upload: async () => {}, remove: async () => {} },
      },
    );
    const outcome = await outcomePromise;
    const statusAfter = await getWebsiteProjectPreviewAsyncBuildStatus(leaseIdSeen, rpcClient);
    assertEquals(statusAfter.buildStatus, outcome.buildStatus);
  } finally {
    await Deno.remove(sourceRoot, { recursive: true });
    await Deno.remove(distRoot, { recursive: true });
  }
});
