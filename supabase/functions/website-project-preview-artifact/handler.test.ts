import { assertEquals } from "jsr:@std/assert@1";
import { handleWebsiteProjectPreviewArtifact } from "./handler.ts";

Deno.test("artifact endpoint forwards OIDC bearer only to issue", async () => {
  let received: unknown;
  const response = await handleWebsiteProjectPreviewArtifact(
    new Request("http://local/", {
      method: "POST",
      headers: { authorization: "Bearer oidc.jwt", "content-type": "application/json" },
      body: JSON.stringify({ action: "issue", leaseId: "lease", buildId: "build", workflowRunId: "42" }),
    }),
    {
      issue: async (input) => {
        received = input;
        return { token: "receipt", expiresAt: "later" };
      },
    },
  );
  assertEquals(response.status, 200);
  assertEquals(received, {
    oidcToken: "oidc.jwt",
    leaseId: "lease",
    buildId: "build",
    workflowRunId: "42",
  });
});

Deno.test("artifact endpoint begins a bounded upload session with the receipt bearer", async () => {
  let received: { receiptToken: string; manifest: readonly unknown[] } | undefined;
  const service = {
    issue: async () => ({}),
    receive: async () => ({}),
    begin: async (input: { receiptToken: string; manifest: readonly unknown[] }) => {
      received = input;
      return { sessionToken: "session-token", expiresAt: "later" };
    },
  };
  const response = await handleWebsiteProjectPreviewArtifact(
    new Request("http://local/", {
      method: "POST",
      headers: { authorization: "Bearer receipt-token", "content-type": "application/json" },
      body: JSON.stringify({
        action: "begin",
        leaseId: "lease",
        buildId: "build",
        repositoryId: "1",
        commitSha: "a".repeat(40),
        workflowRunId: "42",
        primaryRelativePath: "index.html",
        buildStatus: "PASS",
        manifest: [{ relativePath: "index.html", contentType: "text/html", sha256: "b".repeat(64), bytes: 2 }],
      }),
    }),
    service,
  );
  assertEquals(response.status, 200);
  assertEquals(received?.receiptToken, "receipt-token");
  assertEquals(received?.manifest.length, 1);
});

Deno.test("artifact endpoint forwards one raw file body with the session bearer", async () => {
  let received: { sessionToken: string; relativePath: string; bytes: Uint8Array } | undefined;
  const service = {
    issue: async () => ({}),
    receive: async () => ({}),
    uploadFile: async (input: typeof received extends infer _ ? any : never) => {
      received = input;
      return { relativePath: input.relativePath, bytes: input.bytes.byteLength };
    },
  };
  const response = await handleWebsiteProjectPreviewArtifact(
    new Request("http://local/?action=upload", {
      method: "POST",
      headers: {
        authorization: "Bearer session-token",
        "content-type": "text/html; charset=utf-8",
        "content-length": "2",
        "x-lws-lease-id": "lease",
        "x-lws-build-id": "build",
        "x-lws-repository-id": "1",
        "x-lws-commit-sha": "a".repeat(40),
        "x-lws-workflow-run-id": "42",
        "x-lws-relative-path": "index.html",
        "x-lws-sha256": "b".repeat(64),
      },
      body: new Uint8Array([111, 107]),
    }),
    service,
  );
  assertEquals(response.status, 200);
  assertEquals(received?.sessionToken, "session-token");
  assertEquals(received?.relativePath, "index.html");
  assertEquals([...received!.bytes], [111, 107]);
});

Deno.test("artifact endpoint stops reading as soon as a streamed body exceeds five MiB", async () => {
  let pulls = 0;
  let serviceCalled = false;
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      pulls += 1;
      if (pulls === 1) controller.enqueue(new Uint8Array(5 * 1024 * 1024));
      else if (pulls === 2) controller.enqueue(new Uint8Array([1]));
      else {
        controller.enqueue(new Uint8Array([2]));
        controller.close();
      }
    },
  }, { highWaterMark: 0 });
  const service = {
    issue: async () => ({}),
    uploadFile: async () => {
      serviceCalled = true;
      return {};
    },
  };
  const response = await handleWebsiteProjectPreviewArtifact(
    new Request("http://local/?action=upload", {
      method: "POST",
      headers: { "content-length": "1" },
      body,
    }),
    service,
  );
  assertEquals(response.status, 413);
  assertEquals(serviceCalled, false);
  assertEquals(pulls, 2);
});

Deno.test("artifact endpoint rejects unknown actions and methods", async () => {
  const service = { issue: async () => ({}), receive: async () => ({}) };
  const action = await handleWebsiteProjectPreviewArtifact(
    new Request("http://local/", { method: "POST", body: JSON.stringify({ action: "other" }) }),
    service,
  );
  assertEquals(action.status, 400);
  const method = await handleWebsiteProjectPreviewArtifact(new Request("http://local/"), service);
  assertEquals(method.status, 405);
});