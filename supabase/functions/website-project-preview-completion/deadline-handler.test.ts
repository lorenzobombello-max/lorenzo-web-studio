import { assertEquals } from "jsr:@std/assert";
import { handlePreviewDeadline } from "./deadline-handler.ts";

const secret = "deadline-only-".repeat(4);
const request = (provided = secret, method = "POST", body = "{}") => new Request(
  "https://example.test/functions/v1/website-project-preview-completion/deadline",
  { method, headers: { "x-lws-automation-secret": provided }, ...(method === "POST" ? { body } : {}) },
);

Deno.test("deadline denies public, wrong and unconfigured authority without sweeping", async () => {
  let calls = 0;
  const sweep = async () => { calls++; return { expired: 0, cleanupChecked: 0 }; };
  for (const [provided, expected] of [["", secret], ["x".repeat(52), secret], [secret, ""]]) {
    assertEquals((await handlePreviewDeadline(request(provided), expected, sweep)).status, 401);
  }
  assertEquals(calls, 0);
});

Deno.test("deadline rejects method and arbitrary caller input without sweeping", async () => {
  let calls = 0;
  const sweep = async () => { calls++; return { expired: 0, cleanupChecked: 0 }; };
  assertEquals((await handlePreviewDeadline(request(secret, "GET"), secret, sweep)).status, 405);
  for (const body of ['{"buildId":"other"}', "null", "[]", "{", " ".repeat(1025)]) {
    assertEquals((await handlePreviewDeadline(request(secret, "POST", body), secret, sweep)).status, 400);
  }
  assertEquals(calls, 0);
});

Deno.test("deadline invokes existing sweep exactly once and returns bounded counters", async () => {
  let calls = 0;
  const response = await handlePreviewDeadline(request(), secret, async () => {
    calls++;
    return { expired: 2, cleanupChecked: 3 };
  });
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { ok: true, expired: 2, cleanupChecked: 3 });
  assertEquals(calls, 1);
});

Deno.test("deadline exposes failure status without leaking error or retrying", async () => {
  let calls = 0;
  const response = await handlePreviewDeadline(request(), secret, async () => {
    calls++;
    throw new Error("sensitive provider credential");
  });
  assertEquals(response.status, 503);
  assertEquals(await response.json(), { ok: false, code: "PREVIEW_DEADLINE_SWEEP_FAILED" });
  assertEquals(calls, 1);
});
