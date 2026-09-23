import {
  buildWebsiteProjectPreviewArtifactManifest,
  readWebsiteProjectPreviewArtifactFinalBytes,
} from "../supabase/functions/_shared/website-project-preview-artifact-manifest.ts";

type Binding = Readonly<{
  leaseId: string;
  buildId: string;
  repositoryId: string;
  commitSha: string;
  workflowRunId: string;
}>;

function required(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`REQUIRED_ENV_MISSING:${name}`);
  return value;
}

async function jsonRequest(
  endpoint: string,
  token: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const result = await response.json() as Record<string, unknown>;
  if (!response.ok || result.ok !== true) throw new Error(String(result.code ?? `ARTIFACT_HTTP_${response.status}`));
  return result;
}

async function githubOidcToken(audience: string): Promise<string> {
  const requestUrl = new URL(required("ACTIONS_ID_TOKEN_REQUEST_URL"));
  requestUrl.searchParams.set("audience", audience);
  const response = await fetch(requestUrl, {
    headers: { authorization: `Bearer ${required("ACTIONS_ID_TOKEN_REQUEST_TOKEN")}` },
  });
  const result = await response.json() as Record<string, unknown>;
  if (!response.ok || typeof result.value !== "string" || !result.value) throw new Error("GITHUB_OIDC_UNAVAILABLE");
  return result.value;
}

async function uploadFile(
  endpoint: string,
  sessionToken: string,
  binding: Binding,
  entry: Readonly<{ path: string; contentType: string; sha256: string }>,
  bytes: Uint8Array,
): Promise<void> {
  const uploadUrl = new URL(endpoint);
  uploadUrl.searchParams.set("action", "upload");
  const response = await fetch(uploadUrl, {
    method: "POST",
    headers: {
      authorization: `Bearer ${sessionToken}`,
      "content-type": entry.contentType,
      "content-length": String(bytes.byteLength),
      "x-lws-lease-id": binding.leaseId,
      "x-lws-build-id": binding.buildId,
      "x-lws-repository-id": binding.repositoryId,
      "x-lws-commit-sha": binding.commitSha,
      "x-lws-workflow-run-id": binding.workflowRunId,
      "x-lws-relative-path": entry.path,
      "x-lws-sha256": entry.sha256,
    },
    body: Uint8Array.from(bytes).buffer,
  });
  const result = await response.json() as Record<string, unknown>;
  if (!response.ok || result.ok !== true) throw new Error(String(result.code ?? `ARTIFACT_HTTP_${response.status}`));
}

export async function runWebsiteProjectPreviewUpload(): Promise<void> {
  const endpoint = required("LWS_PREVIEW_ARTIFACT_ENDPOINT");
  const audience = required("LWS_PREVIEW_OIDC_AUDIENCE");
  const distRoot = required("LWS_PREVIEW_DIST_ROOT");
  const binding: Binding = {
    leaseId: required("LWS_PREVIEW_LEASE_ID"),
    buildId: required("LWS_PREVIEW_BUILD_ID"),
    repositoryId: required("LWS_PREVIEW_REPOSITORY_ID"),
    commitSha: required("LWS_PREVIEW_COMMIT_SHA"),
    workflowRunId: required("GITHUB_RUN_ID"),
  };
  const manifest = await buildWebsiteProjectPreviewArtifactManifest(distRoot);
  const primaryRelativePath = manifest.accepted.some((entry) => entry.path === "index.html") ? "index.html" : "";
  if (!primaryRelativePath) throw new Error("ARTIFACT_PRIMARY_PATH_MISSING");
  const buildStatus = manifest.rejected.length > 0 ? "PASS_WITH_WARNINGS" : "PASS";
  const oidcToken = await githubOidcToken(audience);
  const issued = await jsonRequest(endpoint, oidcToken, {
    action: "issue",
    leaseId: binding.leaseId,
    buildId: binding.buildId,
    workflowRunId: binding.workflowRunId,
  });
  const receiptToken = String(issued.token ?? "");
  const opened = await jsonRequest(endpoint, receiptToken, {
    action: "begin",
    ...binding,
    primaryRelativePath,
    buildStatus,
    manifest: manifest.accepted.map((entry) => ({
      relativePath: entry.path,
      contentType: entry.contentType,
      sha256: entry.sha256,
      bytes: entry.bytes,
    })),
  });
  const sessionToken = String(opened.sessionToken ?? "");
  if (!sessionToken) throw new Error("ARTIFACT_SESSION_TOKEN_MISSING");
  try {
    for (const entry of manifest.accepted) {
      const bytes = await readWebsiteProjectPreviewArtifactFinalBytes(distRoot, entry.path);
      await uploadFile(endpoint, sessionToken, binding, entry, bytes);
    }
    await jsonRequest(endpoint, sessionToken, { action: "finalize", ...binding });
  } catch (error) {
    await jsonRequest(endpoint, sessionToken, { action: "abort", ...binding }).catch(() => {});
    throw error;
  }
}

if (import.meta.main) await runWebsiteProjectPreviewUpload();