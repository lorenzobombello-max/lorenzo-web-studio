import type { CompletionInput } from "./service.ts";

export async function handlePreviewCompletion(request: Request, service: {
  complete(input: CompletionInput): Promise<Record<string, unknown>>;
}): Promise<Response> {
  const headers = { "cache-control": "no-store" };
  if (request.method !== "POST") return Response.json({ ok: false, code: "METHOD_NOT_ALLOWED" }, { status: 405, headers });
  const token = request.headers.get("authorization")?.match(/^Bearer (\S+)$/)?.[1];
  if (!token || token.length > 16384) return Response.json({ ok: false, code: "COMPLETION_OIDC_REQUIRED" }, { status: 401, headers });
  let body: Record<string, unknown>;
  try {
    const reader = request.body?.getReader();
    if (!reader) throw new Error("EMPTY_BODY");
    const chunks: Uint8Array[] = [];
    let length = 0;
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        length += value.length;
        if (length > 4096) { await reader.cancel(); throw new Error("BODY_TOO_LARGE"); }
        chunks.push(value);
      }
    } finally { reader.releaseLock(); }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    body = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    const keys = ["leaseId", "buildId", "workflowRunId", "monitorRunId"];
    if (!body || Array.isArray(body) || Object.keys(body).length !== keys.length
      || keys.some((key) => typeof body[key] !== "string")) throw new Error("INVALID_BODY");
  } catch {
    return Response.json({ ok: false, code: "COMPLETION_BODY_INVALID" }, { status: 400, headers });
  }
  try {
    const result = await service.complete({
      leaseId: String(body.leaseId), buildId: String(body.buildId), workflowRunId: String(body.workflowRunId),
      monitorRunId: String(body.monitorRunId), oidcToken: token,
    });
    return Response.json({ ok: true, state: result.state }, { headers });
  } catch {
    return Response.json({ ok: false, code: "COMPLETION_NOT_CONFIRMED" }, { status: 503, headers });
  }
}
