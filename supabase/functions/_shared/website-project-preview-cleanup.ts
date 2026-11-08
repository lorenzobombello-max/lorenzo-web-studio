import type { PreviewDispatchRpc } from "./website-project-preview-dispatch.ts";
type PreviewStorage = { remove(paths: string[]): PromiseLike<{ error: unknown }> };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function cleanupFailedPreviewArtifacts(client: PreviewDispatchRpc, storage: PreviewStorage, buildId: string) {
  if (!UUID.test(buildId)) throw new Error("PROJECT_PREVIEW_CLEANUP_AUTHORITY_INVALID");
  const { data, error } = await client.rpc("get_website_project_preview_failed_storage_paths_v1", { p_build_id: buildId });
  if (error || !Array.isArray(data) || data.some((path) => typeof path !== "string"
    || !path.startsWith(`${buildId}/`) || path.includes("..") || !/^[A-Za-z0-9._/-]+$/.test(path))) {
    throw new Error("PROJECT_PREVIEW_CLEANUP_AUTHORITY_INVALID");
  }
  for (let offset = 0; offset < data.length; offset += 100) {
    const { error: storageError } = await storage.remove(data.slice(offset, offset + 100));
    if (storageError) throw new Error("PROJECT_PREVIEW_CLEANUP_FAILED");
  }
}

export async function sweepPreviewDeadlines(client: PreviewDispatchRpc, storage: PreviewStorage) {
  const expired = await client.rpc("expire_website_project_preview_dispatches_v1", {});
  if (expired.error || typeof expired.data !== "number" || !Number.isSafeInteger(expired.data) || expired.data < 0) {
    throw new Error("PROJECT_PREVIEW_EXPIRY_FAILED");
  }
  const candidates = await client.rpc("get_website_project_preview_cleanup_candidates_v1", {});
  if (candidates.error || !Array.isArray(candidates.data) || candidates.data.length > 100
    || candidates.data.some((id) => typeof id !== "string" || !UUID.test(id))) {
    throw new Error("PROJECT_PREVIEW_CLEANUP_AUTHORITY_INVALID");
  }
  for (const buildId of candidates.data) {
    await cleanupFailedPreviewArtifacts(client, storage, buildId);
    const checked = await client.rpc("record_website_project_preview_cleanup_checked_v1", { p_build_id: buildId });
    if (checked.error || checked.data !== true) throw new Error("PROJECT_PREVIEW_CLEANUP_RECORD_FAILED");
  }
  return { expired: expired.data, cleanupChecked: candidates.data.length };
}
