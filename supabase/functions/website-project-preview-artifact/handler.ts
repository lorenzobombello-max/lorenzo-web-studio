import type { WebsiteProjectPreviewArtifactManifestEntry } from "../_shared/website-project-preview-artifact-receipt.ts";

const MAX_FILE_BYTES = 5 * 1024 * 1024;

type ArtifactService = Readonly<{
  issue(input: Readonly<{ oidcToken: string; leaseId: string; buildId: string; workflowRunId: string }>): PromiseLike<unknown>;
  begin?(input: Readonly<{
    receiptToken: string;
    leaseId: string;
    buildId: string;
    repositoryId: string;
    commitSha: string;
    workflowRunId: string;
    primaryRelativePath: string;
    buildStatus: "PASS" | "PASS_WITH_WARNINGS";
    manifest: readonly WebsiteProjectPreviewArtifactManifestEntry[];
  }>): PromiseLike<unknown>;
  uploadFile?(input: Readonly<{
    sessionToken: string;
    leaseId: string;
    buildId: string;
    repositoryId: string;
    commitSha: string;
    workflowRunId: string;
    relativePath: string;
    contentType: string;
    sha256: string;
    bytes: Uint8Array;
  }>): PromiseLike<unknown>;
  finalize?(input: Readonly<{
    sessionToken: string;
    leaseId: string;
    buildId: string;
    repositoryId: string;
    commitSha: string;
    workflowRunId: string;
  }>): PromiseLike<unknown>;
  abort?(input: Readonly<{
    sessionToken: string;
    leaseId: string;
    buildId: string;
    repositoryId: string;
    commitSha: string;
    workflowRunId: string;
  }>): PromiseLike<unknown>;
}>;

function response(status: number, body: unknown): Response {
  return Response.json(body, { status, headers: { "cache-control": "no-store" } });
}

function bearer(request: Request): string {
  return request.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "";
}

function header(request: Request, name: string): string {
  return request.headers.get(name) ?? "";
}

async function readBoundedBody(request: Request, maxBytes: number): Promise<Uint8Array> {
  const declared = request.headers.get("content-length");
  const declaredLength = declared === null ? null : Number(declared);
  if (declaredLength !== null
    && (!Number.isSafeInteger(declaredLength) || declaredLength < 0 || declaredLength > maxBytes)) {
    throw new Error("ARTIFACT_FILE_TOO_LARGE");
  }
  const reader = request.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    totalBytes += value.byteLength;
    if (totalBytes > maxBytes) {
      await reader.cancel("ARTIFACT_FILE_TOO_LARGE").catch(() => {});
      throw new Error("ARTIFACT_FILE_TOO_LARGE");
    }
    chunks.push(value);
  }
  if (declaredLength !== null && totalBytes !== declaredLength) throw new Error("ARTIFACT_BODY_INVALID");
  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

export async function handleWebsiteProjectPreviewArtifact(
  request: Request,
  service: ArtifactService,
): Promise<Response> {
  if (request.method !== "POST") return response(405, { ok: false, code: "METHOD_NOT_ALLOWED" });
  try {
    if (new URL(request.url).searchParams.get("action") === "upload") {
      if (!service.uploadFile) throw new Error("ARTIFACT_ACTION_UNAVAILABLE");
      const bytes = await readBoundedBody(request, MAX_FILE_BYTES);
      const result = await service.uploadFile({
        sessionToken: bearer(request),
        leaseId: header(request, "x-lws-lease-id"),
        buildId: header(request, "x-lws-build-id"),
        repositoryId: header(request, "x-lws-repository-id"),
        commitSha: header(request, "x-lws-commit-sha"),
        workflowRunId: header(request, "x-lws-workflow-run-id"),
        relativePath: header(request, "x-lws-relative-path"),
        contentType: header(request, "content-type"),
        sha256: header(request, "x-lws-sha256"),
        bytes,
      });
      return response(200, { ok: true, ...result as object });
    }
    const body = await request.json() as Record<string, unknown>;
    if (body.action === "issue") {
      const result = await service.issue({
        oidcToken: bearer(request),
        leaseId: String(body.leaseId ?? ""),
        buildId: String(body.buildId ?? ""),
        workflowRunId: String(body.workflowRunId ?? ""),
      });
      return response(200, { ok: true, ...result as object });
    }
    if (body.action === "begin") {
      if (!service.begin) throw new Error("ARTIFACT_ACTION_UNAVAILABLE");
      const rawManifest = Array.isArray(body.manifest) ? body.manifest : [];
      const manifest = rawManifest.map((value) => {
        if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("ARTIFACT_BODY_INVALID");
        const entry = value as Record<string, unknown>;
        return {
          relativePath: String(entry.relativePath ?? ""),
          contentType: String(entry.contentType ?? ""),
          sha256: String(entry.sha256 ?? ""),
          bytes: Number(entry.bytes),
        };
      });
      const buildStatus = String(body.buildStatus ?? "");
      if (buildStatus !== "PASS" && buildStatus !== "PASS_WITH_WARNINGS") throw new Error("ARTIFACT_STATUS_INVALID");
      const result = await service.begin({
        receiptToken: bearer(request),
        leaseId: String(body.leaseId ?? ""),
        buildId: String(body.buildId ?? ""),
        repositoryId: String(body.repositoryId ?? ""),
        commitSha: String(body.commitSha ?? ""),
        workflowRunId: String(body.workflowRunId ?? ""),
        primaryRelativePath: String(body.primaryRelativePath ?? ""),
        buildStatus,
        manifest,
      });
      return response(200, { ok: true, ...result as object });
    }
    if (body.action === "finalize" || body.action === "abort") {
      const operation = body.action === "finalize" ? service.finalize : service.abort;
      if (!operation) throw new Error("ARTIFACT_ACTION_UNAVAILABLE");
      const result = await operation({
        sessionToken: bearer(request),
        leaseId: String(body.leaseId ?? ""),
        buildId: String(body.buildId ?? ""),
        repositoryId: String(body.repositoryId ?? ""),
        commitSha: String(body.commitSha ?? ""),
        workflowRunId: String(body.workflowRunId ?? ""),
      });
      return response(200, { ok: true, ...result as object });
    }
    return response(400, { ok: false, code: "ACTION_INVALID" });
  } catch (error) {
    const code = error instanceof Error ? error.message : "ARTIFACT_REQUEST_FAILED";
    const status = code === "ARTIFACT_FILE_TOO_LARGE" ? 413
      : /FORBIDDEN|INVALID|MISMATCH|EXPIRED|BLOCKED/.test(code) ? 403 : 503;
    return response(status, { ok: false, code });
  }
}