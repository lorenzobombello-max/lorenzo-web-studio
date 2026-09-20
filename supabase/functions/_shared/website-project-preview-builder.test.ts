import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import type {
  WebsiteProjectFilesAuthority,
  WebsiteProjectFilesProvider,
} from "./website-project-files-provider.ts";
import {
  createWebsiteProjectPreviewBuilder,
  WebsiteProjectPreviewBuilderError,
} from "./website-project-preview-builder.ts";

const COMMIT = "a".repeat(40);
const ROOT = "b".repeat(40);

const authority: WebsiteProjectFilesAuthority = Object.freeze({
  leaseId: "10000000-0000-4000-8000-000000000010",
  actorAuthUserId: "10000000-0000-4000-8000-000000000011",
  quoteRequestId: "10000000-0000-4000-8000-000000000012",
  websiteWorkContextId: "10000000-0000-4000-8000-000000000013",
  websiteWorkspaceId: "10000000-0000-4000-8000-000000000014",
  bindingRevision: 7,
  repositoryProvider: "GITHUB",
  repositoryOwner: "lws-phase-a-fixtures",
  repositoryName: "project-a",
  repositoryExternalId: "7100000001",
  repositoryNodeId: "R_context_a",
  defaultBranch: "main",
  repositoryRef: "heads/main",
  refLabel: "main",
  markerOperationId: "10000000-0000-4000-8000-000000000015",
  expiresAt: "2099-01-01T00:00:00.000Z",
});

function harness(options: {
  commitSha?: string;
  html?: string;
  uploadError?: string | null;
  signedUrlError?: string | null;
} = {}) {
  const providerCalls: string[] = [];
  const storageCalls: string[] = [];
  const provider = Object.freeze({
    resolveSnapshot() {
      providerCalls.push("resolveSnapshot");
      return Promise.resolve({
        commitSha: options.commitSha ?? COMMIT,
        rootTreeSha: ROOT,
        repositoryDisplayName: "lws-phase-a-fixtures/project-a",
      });
    },
    readFile() {
      providerCalls.push("readFile");
      return Promise.resolve({
        path: "index.html",
        canonicalPath: "index.html",
        mode: "100644",
        objectType: "blob" as const,
        declaredSize: null,
        bytes: new TextEncoder().encode(
          options.html ?? "<!doctype html><h1>Hello</h1><script>alert(1)</script>",
        ),
      });
    },
  }) as unknown as WebsiteProjectFilesProvider;

  const storage = Object.freeze({
    upload(path: string) {
      storageCalls.push(`upload:${path}`);
      if (options.uploadError) {
        return Promise.resolve({
          data: null,
          error: { message: options.uploadError },
        });
      }
      return Promise.resolve({ data: { path }, error: null });
    },
    createSignedUrl(path: string) {
      storageCalls.push(`createSignedUrl:${path}`);
      if (options.signedUrlError) {
        return Promise.resolve({
          data: null,
          error: { message: options.signedUrlError },
        });
      }
      return Promise.resolve({
        data: { signedUrl: `https://storage.test/${path}` },
        error: null,
      });
    },
  });

  return {
    providerCalls,
    storageCalls,
    builder: createWebsiteProjectPreviewBuilder({
      provider,
      storage,
      now: () => Date.parse("2099-01-01T00:00:00.000Z"),
      signedUrlTtlSeconds: 300,
    }),
  };
}

Deno.test("preview build reads exact commit and writes immutable artifact", async () => {
  const test = harness();
  const result = await test.builder.build({
    authority,
    expectedCommitSha: COMMIT,
    idempotencyKey: "10000000-0000-4000-8000-000000000099",
  });
  assertEquals(result.snapshot.commit_sha, COMMIT);
  assertEquals(result.build.status, "PASS");
  assertEquals(result.preview.storage_bucket_id, "website-project-previews");
  assertEquals(result.preview.storage_object_path.includes(COMMIT), true);
  assertEquals(result.preview.signed_url.startsWith("https://storage.test/"), true);
  assertEquals(test.providerCalls, ["resolveSnapshot", "readFile"]);
  assertEquals(test.storageCalls.length, 2);
});

Deno.test("preview build rejects stale expected commit", async () => {
  const test = harness({ commitSha: "b".repeat(40) });
  await assertRejects(
    () =>
      test.builder.build({
        authority,
        expectedCommitSha: COMMIT,
        idempotencyKey: "10000000-0000-4000-8000-000000000099",
      }),
    WebsiteProjectPreviewBuilderError,
    "PROJECT_FILES_STALE_REVISION",
  );
  assertEquals(test.providerCalls, ["resolveSnapshot"]);
});

Deno.test("preview build rejects dangerous static markup", async () => {
  const test = harness({
    html: "<!doctype html><iframe src='https://evil.test'></iframe>",
  });
  await assertRejects(
    () =>
      test.builder.build({
        authority,
        expectedCommitSha: COMMIT,
        idempotencyKey: "10000000-0000-4000-8000-000000000099",
      }),
    WebsiteProjectPreviewBuilderError,
    "PREVIEW_MARKUP_UNSAFE",
  );
  assertEquals(test.storageCalls.length, 0);
});

Deno.test("preview build reuses immutable artifact when upload path already exists", async () => {
  const test = harness({ uploadError: "The resource already exists" });
  const result = await test.builder.build({
    authority,
    expectedCommitSha: COMMIT,
    idempotencyKey: "10000000-0000-4000-8000-000000000099",
  });
  assertEquals(result.preview.reuse_status, "REUSED");
  assertEquals(test.storageCalls.length, 2);
});

Deno.test("preview build fails closed when signed URL generation fails", async () => {
  const test = harness({ signedUrlError: "signed-url-failed" });
  await assertRejects(
    () =>
      test.builder.build({
        authority,
        expectedCommitSha: COMMIT,
        idempotencyKey: "10000000-0000-4000-8000-000000000099",
      }),
    WebsiteProjectPreviewBuilderError,
    "PREVIEW_SIGNED_URL_FAILED",
  );
});
