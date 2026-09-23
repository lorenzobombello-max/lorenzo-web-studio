import { assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import {
  createLocalWebsiteProjectPreviewHostingGateway,
  normalizeWebsiteProjectPreviewAssetPath,
} from "./website-project-preview-local-hosting-gateway.ts";

function extractCookieValue(setCookieHeader: string | null): string {
  const match = /lws_preview_session=([0-9a-f]+)/.exec(setCookieHeader ?? "");
  if (!match) throw new Error("no session cookie in response");
  return match[1];
}

Deno.test("normalizes directory navigation and rejects decoded traversal paths", () => {
  assertEquals(normalizeWebsiteProjectPreviewAssetPath("/"), "index.html");
  assertEquals(normalizeWebsiteProjectPreviewAssetPath("/about/"), "about/index.html");
  assertEquals(normalizeWebsiteProjectPreviewAssetPath("/about/team.html"), "about/team.html");
  for (const path of ["/../secret", "/%2e%2e/secret", "/about%5csecret", "/bad%00path", "/%zz"]) {
    assertEquals(normalizeWebsiteProjectPreviewAssetPath(path), null, path);
  }
});

Deno.test("full flow: publish -> handoff -> cookie -> serve HTML, CSS and an image", async () => {
  const gateway = await createLocalWebsiteProjectPreviewHostingGateway();
  try {
    const buildId = "build-real-flow";
    gateway.registerBuild({ previewBuildId: buildId, actorAuthUserId: "actor-a" });
    gateway.putAsset({
      previewBuildId: buildId,
      relativePath: "index.html",
      contentType: "text/html; charset=utf-8",
      bytes: new TextEncoder().encode("<html><body><h1>hi</h1></body></html>"),
    });
    gateway.putAsset({
      previewBuildId: buildId,
      relativePath: "_astro/style.css",
      contentType: "text/css; charset=utf-8",
      bytes: new TextEncoder().encode("body{color:red}"),
    });
    const pngBytes = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4]);
    gateway.putAsset({
      previewBuildId: buildId,
      relativePath: "hero.png",
      contentType: "image/png",
      bytes: pngBytes,
    });

    const session = await gateway.publish({
      previewBuildId: buildId,
      actorAuthUserId: "actor-a",
      manifest: { root: "", accepted: [], rejected: [], totalBytes: 0 },
      buildStatus: "PASS",
    });
    assertEquals(session.handoffUrl.startsWith(gateway.baseUrl), true);

    const handoffResponse = await fetch(session.handoffUrl, { redirect: "manual" });
    assertEquals(handoffResponse.status, 302);
    const setCookie = handoffResponse.headers.get("set-cookie");
    assertEquals(setCookie?.includes("HttpOnly"), true);
    assertEquals(setCookie?.includes("Secure"), true);
    assertEquals(setCookie?.includes("SameSite=Lax"), true);
    assertEquals(setCookie?.includes("Path=/"), true);
    assertEquals(setCookie?.includes("Domain="), false);
    const cookieValue = extractCookieValue(setCookie);
    await handoffResponse.body?.cancel();

    const htmlResponse = await fetch(`${gateway.baseUrl}/`, {
      headers: { cookie: `lws_preview_session=${cookieValue}` },
    });
    assertEquals(htmlResponse.status, 200);
    assertEquals(htmlResponse.headers.get("content-type"), "text/html; charset=utf-8");
    assertEquals(await htmlResponse.text(), "<html><body><h1>hi</h1></body></html>");

    const cssResponse = await fetch(`${gateway.baseUrl}/_astro/style.css`, {
      headers: { cookie: `lws_preview_session=${cookieValue}` },
    });
    assertEquals(cssResponse.status, 200);
    assertEquals(await cssResponse.text(), "body{color:red}");

    const imageResponse = await fetch(`${gateway.baseUrl}/hero.png`, {
      headers: { cookie: `lws_preview_session=${cookieValue}` },
    });
    assertEquals(imageResponse.status, 200);
    assertEquals(imageResponse.headers.get("content-type"), "image/png");
    const imageBytes = new Uint8Array(await imageResponse.arrayBuffer());
    assertEquals(imageBytes, pngBytes);
  } finally {
    await gateway.close();
  }
});

Deno.test("a handoff token can be used exactly once", async () => {
  const gateway = await createLocalWebsiteProjectPreviewHostingGateway();
  try {
    const buildId = "build-single-use";
    gateway.registerBuild({ previewBuildId: buildId, actorAuthUserId: "actor-a" });
    gateway.putAsset({
      previewBuildId: buildId,
      relativePath: "index.html",
      contentType: "text/html; charset=utf-8",
      bytes: new TextEncoder().encode("<html></html>"),
    });
    const session = await gateway.publish({
      previewBuildId: buildId,
      actorAuthUserId: "actor-a",
      manifest: { root: "", accepted: [], rejected: [], totalBytes: 0 },
      buildStatus: "PASS",
    });

    const first = await fetch(session.handoffUrl, { redirect: "manual" });
    assertEquals(first.status, 302);
    await first.body?.cancel();

    const second = await fetch(session.handoffUrl, { redirect: "manual" });
    assertEquals(second.status, 403);
    await second.body?.cancel();
  } finally {
    await gateway.close();
  }
});

Deno.test("a session cookie from build A is never accepted for build B's assets (cross-build isolation)", async () => {
  const gateway = await createLocalWebsiteProjectPreviewHostingGateway();
  try {
    for (const [buildId, marker] of [["build-a", "AAA"], ["build-b", "BBB"]] as const) {
      gateway.registerBuild({ previewBuildId: buildId, actorAuthUserId: "actor-a" });
      gateway.putAsset({
        previewBuildId: buildId,
        relativePath: "index.html",
        contentType: "text/html; charset=utf-8",
        bytes: new TextEncoder().encode(`<html>${marker}</html>`),
      });
    }
    const sessionA = await gateway.publish({
      previewBuildId: "build-a",
      actorAuthUserId: "actor-a",
      manifest: { root: "", accepted: [], rejected: [], totalBytes: 0 },
      buildStatus: "PASS",
    });
    const sessionB = await gateway.publish({
      previewBuildId: "build-b",
      actorAuthUserId: "actor-a",
      manifest: { root: "", accepted: [], rejected: [], totalBytes: 0 },
      buildStatus: "PASS",
    });

    const handoffA = await fetch(sessionA.handoffUrl, { redirect: "manual" });
    const cookieA = extractCookieValue(handoffA.headers.get("set-cookie"));
    await handoffA.body?.cancel();
    const handoffB = await fetch(sessionB.handoffUrl, { redirect: "manual" });
    const cookieB = extractCookieValue(handoffB.headers.get("set-cookie"));
    await handoffB.body?.cancel();
    assertNotEquals(cookieA, cookieB);

    const responseWithCookieA = await fetch(`${gateway.baseUrl}/`, {
      headers: { cookie: `lws_preview_session=${cookieA}` },
    });
    assertEquals(await responseWithCookieA.text(), "<html>AAA</html>");

    const responseWithCookieB = await fetch(`${gateway.baseUrl}/`, {
      headers: { cookie: `lws_preview_session=${cookieB}` },
    });
    assertEquals(await responseWithCookieB.text(), "<html>BBB</html>");
  } finally {
    await gateway.close();
  }
});

Deno.test("no session cookie is rejected outright", async () => {
  const gateway = await createLocalWebsiteProjectPreviewHostingGateway();
  try {
    const response = await fetch(`${gateway.baseUrl}/`);
    assertEquals(response.status, 401);
    await response.body?.cancel();
  } finally {
    await gateway.close();
  }
});

Deno.test("a forged/unknown session cookie value is rejected", async () => {
  const gateway = await createLocalWebsiteProjectPreviewHostingGateway();
  try {
    const response = await fetch(`${gateway.baseUrl}/`, {
      headers: { cookie: "lws_preview_session=" + "0".repeat(64) },
    });
    assertEquals(response.status, 401);
    await response.body?.cancel();
  } finally {
    await gateway.close();
  }
});

Deno.test("a handoff token bound to a different build is rejected even with a valid signature", async () => {
  const gateway = await createLocalWebsiteProjectPreviewHostingGateway();
  try {
    gateway.registerBuild({ previewBuildId: "build-x", actorAuthUserId: "actor-a" });
    gateway.putAsset({
      previewBuildId: "build-x",
      relativePath: "index.html",
      contentType: "text/html; charset=utf-8",
      bytes: new TextEncoder().encode("<html></html>"),
    });
    const session = await gateway.publish({
      previewBuildId: "build-x",
      actorAuthUserId: "actor-a",
      manifest: { root: "", accepted: [], rejected: [], totalBytes: 0 },
      buildStatus: "PASS",
    });
    const forgedUrl = session.handoffUrl.replace("build=build-x", "build=build-y");
    const response = await fetch(forgedUrl, { redirect: "manual" });
    assertEquals(response.status, 403);
    await response.body?.cancel();
  } finally {
    await gateway.close();
  }
});
