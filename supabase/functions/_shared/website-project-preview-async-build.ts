// Orchestrates the asynchronous preview-build pipeline end to end:
// acquire -> fetch source -> build in an isolated sandbox -> validate the
// resulting artifact manifest -> upload each accepted asset -> finalize.
// Every external effect (the RPC calls, fetching source, running the
// sandbox build, uploading bytes) is dependency-injected - this module
// contains only the orchestration logic itself, matching checkpoint
// 009-git001c-astro-preview-build-plan.md §16.1's three-job design
// (fetch/build/upload) without assuming any particular concrete
// implementation of any of those jobs.
import {
  buildWebsiteProjectPreviewArtifactManifest,
  DEFAULT_ARTIFACT_MANIFEST_LIMITS,
  readWebsiteProjectPreviewArtifactFinalBytes,
  type WebsiteProjectPreviewArtifactManifest,
  type WebsiteProjectPreviewArtifactManifestLimits,
} from "./website-project-preview-artifact-manifest.ts";
import { sha256Hex } from "./website-project-preview-sanitizer.ts";
import type { WebsiteProjectFilesAuthority } from "./website-project-files-provider.ts";

export class WebsiteProjectPreviewAsyncBuildError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "WebsiteProjectPreviewAsyncBuildError";
  }
}

function fail(code: string): never {
  throw new WebsiteProjectPreviewAsyncBuildError(code);
}

export type WebsiteProjectPreviewRpcResult<T> = Readonly<{
  data: T | null;
  error: Readonly<{ message?: string }> | null;
}>;

export type WebsiteProjectPreviewAsyncRpcClient = Readonly<{
  rpc<T = unknown>(
    name: string,
    args: Record<string, unknown>,
  ): PromiseLike<WebsiteProjectPreviewRpcResult<T>>;
}>;

export type WebsiteProjectPreviewSourceFetcher = Readonly<{
  // Materializes the exact, authorized commit's source tree into a local
  // directory and returns its path (checkpoint §16.1 job 1, "fetch").
  fetchSource(
    input: Readonly<{
      authority: WebsiteProjectFilesAuthority;
      expectedCommitSha: string;
    }>,
  ): Promise<Readonly<{ sourceRoot: string }>>;
}>;

export type WebsiteProjectPreviewSandboxBuilder = Readonly<{
  // Runs the isolated build (checkpoint §14.1/§16.1 job 2, "build")
  // against an already-fetched source directory and returns the path to
  // its build output directory (e.g. `dist/`).
  build(
    input: Readonly<{ sourceRoot: string }>,
  ): Promise<Readonly<{ distRoot: string }>>;
}>;

export type WebsiteProjectPreviewArtifactUploader = Readonly<{
  // Uploads exactly the already-manifested, independently re-derived
  // bytes for one accepted entry (checkpoint §16.1 job 3, "upload").
  upload(
    input: Readonly<{
      relativePath: string;
      contentType: string;
      bytes: Uint8Array;
    }>,
  ): Promise<void>;
  remove(relativePaths: readonly string[]): Promise<void>;
}>;

export type WebsiteProjectPreviewAsyncBuildDependencies = Readonly<{
  rpcClient: WebsiteProjectPreviewAsyncRpcClient;
  sourceFetcher: WebsiteProjectPreviewSourceFetcher;
  sandboxBuilder: WebsiteProjectPreviewSandboxBuilder;
  artifactUploader: WebsiteProjectPreviewArtifactUploader;
  manifestLimits?: WebsiteProjectPreviewArtifactManifestLimits;
  primaryRelativePath?: string;
}>;

export type WebsiteProjectPreviewAsyncBuildOutcome = Readonly<{
  leaseId: string;
  previewBuildId: string;
  buildStatus: "PASS" | "PASS_WITH_WARNINGS" | "FAILED";
  manifest: WebsiteProjectPreviewArtifactManifest;
}>;

async function rpcOrFail<T>(
  client: WebsiteProjectPreviewAsyncRpcClient,
  name: string,
  args: Record<string, unknown>,
): Promise<T> {
  const result = await client.rpc<T>(name, args);
  if (result.error) fail(String(result.error.message || "RPC_FAILED"));
  if (result.data === null || result.data === undefined) {
    fail("RPC_RESPONSE_EMPTY");
  }
  return result.data;
}

export async function runWebsiteProjectPreviewAsyncBuild(
  input: Readonly<{
    quoteRequestId: string;
    expectedCommitSha: string;
    idempotencyKey: string;
  }>,
  dependencies: WebsiteProjectPreviewAsyncBuildDependencies,
): Promise<WebsiteProjectPreviewAsyncBuildOutcome> {
  const limits = dependencies.manifestLimits ?? DEFAULT_ARTIFACT_MANIFEST_LIMITS;
  const primaryRelativePath = dependencies.primaryRelativePath ?? "index.html";

  const authority = await rpcOrFail<WebsiteProjectFilesAuthority & { leaseId: string }>(
    dependencies.rpcClient,
    "acquire_website_project_preview_build_v1",
    {
      p_quote_request_id: input.quoteRequestId,
      p_expected_commit_sha: input.expectedCommitSha,
      p_idempotency_key: input.idempotencyKey,
    },
  );
  const leaseId = authority.leaseId;

  let manifest: WebsiteProjectPreviewArtifactManifest;
  let buildStatus: "PASS" | "PASS_WITH_WARNINGS" | "FAILED";
  const uploadedPaths: string[] = [];
  let uploadsCleaned = false;
  async function cleanupUploads(): Promise<void> {
    if (uploadsCleaned || uploadedPaths.length === 0) return;
    await dependencies.artifactUploader.remove(uploadedPaths);
    uploadsCleaned = true;
  }
  try {
    const { sourceRoot } = await dependencies.sourceFetcher.fetchSource({
      authority,
      expectedCommitSha: input.expectedCommitSha,
    });
    const { distRoot } = await dependencies.sandboxBuilder.build({ sourceRoot });
    manifest = await buildWebsiteProjectPreviewArtifactManifest(distRoot, limits);

    const primaryAccepted = manifest.accepted.some((entry) =>
      entry.path === primaryRelativePath
    );
    if (!primaryAccepted) {
      buildStatus = "FAILED";
    } else if (manifest.rejected.length > 0) {
      buildStatus = "PASS_WITH_WARNINGS";
    } else {
      buildStatus = "PASS";
    }

    if (buildStatus !== "FAILED") {
      for (const entry of manifest.accepted) {
        // Independent, second re-derivation of the exact bytes to upload
        // (checkpoint §14.1 "dubbel gecontroleerd") - never trusts the
        // manifest's recorded hash alone; recomputes it from freshly
        // re-read, freshly re-validated bytes and compares.
        const bytes = await readWebsiteProjectPreviewArtifactFinalBytes(
          distRoot,
          entry.path,
          limits,
        );
        const recomputedHash = await sha256Hex(bytes);
        if (recomputedHash !== entry.sha256) {
          fail("ARTIFACT_HASH_MISMATCH");
        }
        await dependencies.artifactUploader.upload({
          relativePath: entry.path,
          contentType: entry.contentType,
          bytes,
        });
        uploadedPaths.push(entry.path);
      }
    }
  } catch (error) {
    await cleanupUploads();
    buildStatus = "FAILED";
    manifest = Object.freeze({
      root: "",
      accepted: Object.freeze([]),
      rejected: Object.freeze([]),
      totalBytes: 0,
    });
    // A build-pipeline failure still finalizes (as FAILED) rather than
    // leaving the lease to expire silently - the operator UI's status
    // poll must see a definitive terminal state, not an indefinite spin,
    // per checkpoint §16.1's frontend-polling design.
    void error;
  }

  let finalizeResult: Readonly<{ previewBuildId: string; buildStatus: string }>;
  try {
    finalizeResult = await rpcOrFail(
      dependencies.rpcClient,
      "finalize_website_project_preview_build_v2",
      {
        p_lease_id: leaseId,
        p_expected_commit_sha: input.expectedCommitSha,
        p_build_status: buildStatus,
        p_primary_relative_path: buildStatus === "FAILED" ? null : primaryRelativePath,
        p_manifest: buildStatus === "FAILED"
          ? null
          : manifest.accepted.map((entry) => ({
            relative_path: entry.path,
            content_type: entry.contentType,
            sha256: entry.sha256,
            bytes: entry.bytes,
          })),
      },
    );
  } catch (error) {
    await cleanupUploads();
    throw error;
  }

  return Object.freeze({
    leaseId,
    previewBuildId: finalizeResult.previewBuildId,
    buildStatus: finalizeResult.buildStatus as "PASS" | "PASS_WITH_WARNINGS" | "FAILED",
    manifest,
  });
}

export async function getWebsiteProjectPreviewAsyncBuildStatus(
  leaseId: string,
  rpcClient: WebsiteProjectPreviewAsyncRpcClient,
): Promise<Readonly<{ buildStatus: string; previewBuildId: string | null }>> {
  return await rpcOrFail(rpcClient, "get_website_project_preview_build_status_v1", {
    p_lease_id: leaseId,
  });
}
