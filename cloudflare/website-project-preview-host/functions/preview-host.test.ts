import { assertEquals } from "jsr:@std/assert@1";
import { handlePagesPreviewRequest } from "./[[path]].ts";

const env = {
  LWS_PREVIEW_ORIGIN_URL: "https://project.supabase.co/functions/v1/website-project-preview-host",
  LWS_PREVIEW_ORIGIN_TOKEN: "purpose-secret",
};

Deno.test("Pages preview forwards exact path query cookie and purpose secret without caching", async () => {
  let received: Request | undefined;
  const response = await handlePagesPreviewRequest(
    new Request("https://preview.lorenzowebsolutions.be/about/?mode=preview", {
      headers: { cookie: "lws_preview_session=viewer" },
    }),
    env,
    async (request) => {
      received = request instanceof Request ? request : new Request(request);
      return new Response("<h1>About</h1>", {
        headers: {
          "x-lws-preview-content-type": "text/html; charset=utf-8",
          "set-cookie": "lws_preview_session=viewer; HttpOnly; Secure; SameSite=Lax; Path=/",
        },
      });
    },
  );

  if (!received) throw new Error("origin was not called");
  assertEquals(received.url, `${env.LWS_PREVIEW_ORIGIN_URL}/about/?mode=preview`);
  assertEquals(received.headers.get("cookie"), "lws_preview_session=viewer");
  assertEquals(received.headers.get("x-lws-preview-origin-token"), "purpose-secret");
  assertEquals(received.headers.get("x-lws-preview-path"), "/about/?mode=preview");
  assertEquals(response.headers.get("content-type"), "text/html; charset=utf-8");
  assertEquals(response.headers.get("x-lws-preview-content-type"), null);
  assertEquals(response.headers.get("cache-control"), "private, no-store");
  assertEquals(response.headers.get("set-cookie")?.includes("HttpOnly"), true);
});

Deno.test("Pages preview redirects pages.dev and never forwards the origin secret to clients", async () => {
  let calls = 0;
  const response = await handlePagesPreviewRequest(
    new Request("https://lws-website-project-preview-host.pages.dev/about/?x=1"),
    env,
    async () => { calls += 1; return new Response(); },
  );
  assertEquals(response.status, 308);
  assertEquals(response.headers.get("location"), "https://preview.lorenzowebsolutions.be/about/?x=1");
  assertEquals(response.headers.get("x-lws-preview-origin-token"), null);
  assertEquals(calls, 0);
});

Deno.test("Pages preview fails closed on invalid configuration or origin failure", async () => {
  const invalid = await handlePagesPreviewRequest(new Request("https://preview.lorenzowebsolutions.be/"), {
    LWS_PREVIEW_ORIGIN_URL: "http://unsafe.example",
    LWS_PREVIEW_ORIGIN_TOKEN: "",
  }, fetch);
  const failed = await handlePagesPreviewRequest(
    new Request("https://preview.lorenzowebsolutions.be/"),
    env,
    async () => { throw new Error("origin details"); },
  );
  assertEquals(invalid.status, 503);
  assertEquals(failed.status, 502);
});
