import { automationSecretMatches } from "../intake-reminder-worker/handler.ts";

export async function handlePreviewDeadline(
  request: Request,
  secret: string,
  sweep: () => Promise<{ expired: number; cleanupChecked: number }>,
): Promise<Response> {
  const reply = (status: number, body: Record<string, unknown>) =>
    Response.json(body, { status, headers: { "cache-control": "no-store" } });
  if (request.method !== "POST") return reply(405, { ok: false, code: "METHOD_NOT_ALLOWED" });
  const provided = request.headers.get("x-lws-automation-secret");
  if (!provided || provided.length > 256 || !await automationSecretMatches(provided, secret)) {
    return reply(401, { ok: false, code: "UNAUTHORIZED" });
  }
  try {
    const reader = request.body?.getReader();
    let text = "";
    let size = 0;
    if (reader) {
      const decoder = new TextDecoder();
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > 1024) { await reader.cancel(); throw new Error("BODY_TOO_LARGE"); }
        text += decoder.decode(value, { stream: true });
      }
      text += decoder.decode();
    }
    const body = JSON.parse(text);
    if (!body || Array.isArray(body) || typeof body !== "object" || Object.keys(body).length) {
      throw new Error("INVALID_BODY");
    }
  } catch {
    return reply(400, { ok: false, code: "INVALID_REQUEST" });
  }
  try {
    return reply(200, { ok: true, ...await sweep() });
  } catch {
    return reply(503, { ok: false, code: "PREVIEW_DEADLINE_SWEEP_FAILED" });
  }
}
