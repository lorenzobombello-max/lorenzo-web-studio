import { buildWebsiteProjectPreviewArtifactManifest } from "../supabase/functions/_shared/website-project-preview-artifact-manifest.ts";

export async function validatePreviewDist(root: string) {
  const manifest = await buildWebsiteProjectPreviewArtifactManifest(root);
  if (!manifest.accepted.some((entry) => entry.path === "index.html")) throw new Error("ARTIFACT_PRIMARY_PATH_MISSING");
  if (manifest.rejected.some((entry) => entry.reason !== "ASSET_TYPE_BLOCKED" || !entry.path.toLowerCase().endsWith(".svg"))) {
    throw new Error("ARTIFACT_TREE_UNSAFE");
  }
  return manifest;
}
if (import.meta.main) {
  const root = Deno.args[0];
  if (!root) throw new Error("ARTIFACT_ROOT_REQUIRED");
  const manifest = await validatePreviewDist(root);
  console.log(JSON.stringify({ accepted: manifest.accepted.length, rejected: manifest.rejected.length, bytes: manifest.totalBytes }));
}
