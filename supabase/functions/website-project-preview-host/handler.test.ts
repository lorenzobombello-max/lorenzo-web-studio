import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { handleWebsiteProjectPreviewHost } from "./handler.ts";

const secret = "purpose-secret";
const buildId = "22222222-2222-4222-8222-222222222222";
const viewerToken = "d".repeat(64);

function service(overrides: Record<string, unknown> = {}) {
  return {
    originToken: secret,
    randomBytes: () => new Uint8Array(32).fill(7),
    consumeHandoff: async () => ({ expiresAt: "2026-09-23T12:30:00.000Z" }),
    resolveSession: async () => ({
      previewBuildId: buildId,
      artifacts: [
        { relativePath: "index.html", contentType: "text/html; charset=utf-8", sha256: "a".repeat(64), bytes: 13 },
        { relativePath: "about/index.html", contentType: "text/html; charset=utf-8", sha256: "b".repeat(64), bytes: 5 },
        { relativePath: "styles.css", contentType: "text/css", sha256: "c".repeat(64), bytes: 4 },
      ],
    }),
    download: async (path: string) => new TextEncoder().encode(path.endsWith("index.html") ? "<h1>Preview</h1>" : "body"),
    ...overrides,
  };
}

function originRequest(path: string, init: RequestInit = {}) {
  const headers = new Headers(init.headers);
  headers.set("x-lws-preview-origin-token", secret);
  headers.set("x-lws-preview-path", path);
  return new Request(`https://origin.local${path}`, { ...init, headers });
}

Deno.test("preview origin rejects unauthenticated direct requests before dependencies", async () => {
  let called = false;
  const response = await handleWebsiteProjectPreviewHost(new Request("https://origin.local/"), service({
    resolveSession: async () => { called = true; throw new Error("unexpected"); },
  }));
  assertEquals(response.status, 403);
  assertEquals(called, false);
});

Deno.test("preview origin atomically rotates one handoff into a host-only viewer cookie", async () => {
  let consumed: { handoffTokenHash: string; viewerSessionTokenHash: string } | undefined;
  const response = await handleWebsiteProjectPreviewHost(originRequest("/handoff?token=handoff-token"), service({
    consumeHandoff: async (input: { handoffTokenHash: string; viewerSessionTokenHash: string }) => {
      consumed = input;
      return { expiresAt: "2026-09-23T12:30:00.000Z" };
    },
  }));
  assertEquals(response.status, 302);
  assertEquals(response.headers.get("location"), "/");
  const cookie = response.headers.get("set-cookie") ?? "";
  assertStringIncludes(cookie, "lws_preview_session=");
  assertStringIncludes(cookie, "HttpOnly; Secure; SameSite=Lax; Path=/");
  assertEquals(cookie.includes("Domain="), false);
  if (!consumed) throw new Error("handoff was not consumed");
  assertEquals(typeof consumed.handoffTokenHash, "string");
  assertEquals(consumed.handoffTokenHash.length, 64);
  assertEquals(consumed.viewerSessionTokenHash.length, 64);
  assertEquals(consumed.handoffTokenHash === consumed.viewerSessionTokenHash, false);
});

Deno.test("preview origin resolves viewer session and serves only manifest-bound build assets", async () => {
  const downloads: string[] = [];
  const bound = service({ download: async (path: string) => { downloads.push(path); return new TextEncoder().encode("<h1>Preview</h1>"); } });
  for (const path of ["/", "/about/"]) {
    const response = await handleWebsiteProjectPreviewHost(originRequest(path, {
      headers: { cookie: `lws_preview_session=${viewerToken}` },
    }), bound);
    assertEquals(response.status, 200);
    assertEquals(response.headers.get("x-lws-preview-content-type"), "text/html; charset=utf-8");
    assertEquals(response.headers.get("cache-control"), "private, no-store");
  }
  assertEquals(downloads, [`${buildId}/index.html`, `${buildId}/about/index.html`]);

  const absent = await handleWebsiteProjectPreviewHost(originRequest("/blocked.svg", {
    headers: { cookie: `lws_preview_session=${viewerToken}` },
  }), bound);
  assertEquals(absent.status, 404);
  assertEquals(downloads.length, 2);
});

Deno.test("preview origin rejects malformed and traversal paths", async () => {
  for (const path of ["/%", "/%252e%252e/secret", "/folder%255csecret", "/null%2500byte"]) {
    const response = await handleWebsiteProjectPreviewHost(originRequest(path, {
      headers: { cookie: `lws_preview_session=${viewerToken}` },
    }), service());
    assertEquals(response.status, 400, path);
  }
});

Deno.test("preview origin rejects absent or expired viewer sessions", async () => {
  const absent = await handleWebsiteProjectPreviewHost(originRequest("/"), service());
  const expired = await handleWebsiteProjectPreviewHost(originRequest("/", {
    headers: { cookie: `lws_preview_session=${"e".repeat(64)}` },
  }), service({ resolveSession: async () => { throw new Error("PROJECT_PREVIEW_SESSION_INVALID"); } }));
  assertEquals(absent.status, 401);
  assertEquals(expired.status, 401);
});
