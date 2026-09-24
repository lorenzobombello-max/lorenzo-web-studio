import type {
  WebsiteProjectFilesAuthority,
  WebsiteProjectFilesProvider,
} from "./website-project-files-provider.ts";
import { inspectWebsiteProjectFile } from "./website-project-files-policy.ts";
import {
  sanitizeStaticPreviewHtml,
  sha256Hex,
} from "./website-project-preview-sanitizer.ts";

const SHA = /^[0-9a-f]{40}$/;

const PREVIEW_BUCKET = "website-project-previews";
const DEFAULT_SIGNED_URL_TTL_SECONDS = 300;

export type WebsiteProjectPreviewBuildResult = Readonly<{
  contract_version: 1;
  quote_request_id: string;
  website_work_context_id: string;
  website_workspace_id: string;
  workspace_state: "REPOSITORY_READY";
  repository: Readonly<{ display_name: string; binding_revision: number }>;
  snapshot: Readonly<{ commit_sha: string; ref_label: string }>;
  build: Readonly<{
    status: "PASS";
    built_at: string;
    source_path: "index.html";
    sanitization: "STATIC_PREVIEW_SANITIZER_V1";
    idempotency_key: string;
  }>;
  preview: Readonly<{
    storage_bucket_id: string;
    storage_object_path: string;
    media_type: "text/html";
    sha256: string;
    byte_count: number;
    signed_url: string;
    expires_at: string;
    reuse_status: "CREATED" | "REUSED";
  }>;
}>;

type StorageUploadResult = Readonly<{
  data: unknown;
  error: Readonly<{ message?: string }> | null;
}>;

type StorageSignedUrlResult = Readonly<{
  data: Readonly<{ signedUrl: string }> | null;
  error: Readonly<{ message?: string }> | null;
}>;

type WebsiteProjectPreviewStorage = Readonly<{
  upload(
    path: string,
    bytes: Uint8Array,
    options: Readonly<{ contentType: string; upsert: false }>,
  ): PromiseLike<StorageUploadResult>;
  createSignedUrl(
    path: string,
    expiresInSeconds: number,
  ): PromiseLike<StorageSignedUrlResult>;
}>;

type WebsiteProjectPreviewBuilderDependencies = Readonly<{
  provider: WebsiteProjectFilesProvider;
  storage: WebsiteProjectPreviewStorage;
  now?: () => number;
  signedUrlTtlSeconds?: number;
}>;

export class WebsiteProjectPreviewBuilderError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "WebsiteProjectPreviewBuilderError";
  }
}

function fail(code: string): never {
  throw new WebsiteProjectPreviewBuilderError(code);
}

function objectPath(
  authority: WebsiteProjectFilesAuthority,
  commitSha: string,
  htmlSha: string,
): string {
  return [
    "contexts",
    authority.websiteWorkContextId,
    "workspaces",
    authority.websiteWorkspaceId,
    "commits",
    commitSha,
    `index-${htmlSha}.html`,
  ].join("/");
}

function isAlreadyExistsError(message: string): boolean {
  const lowered = message.toLowerCase();
  return lowered.includes("already exists") || lowered.includes("duplicate");
}

function normalize(error: unknown): never {
  if (error instanceof WebsiteProjectPreviewBuilderError) throw error;
  const code = error instanceof Error ? error.message : "";
  if ([
    "PROJECT_FILES_PROVIDER_TIMEOUT",
    "PROJECT_FILES_PROVIDER_THROTTLED",
    "PROJECT_FILES_PROVIDER_UNAVAILABLE",
    "PROJECT_FILES_PROVIDER_RESPONSE_INVALID",
    "PROJECT_FILES_SNAPSHOT_UNAVAILABLE",
    "PROJECT_FILE_NOT_FOUND",
    "PROJECT_PATH_KIND_MISMATCH",
    "FILE_TOO_LARGE",
    "BINARY_UNSUPPORTED",
    "UNSUPPORTED_ENCODING",
    "SENSITIVE_FILE_BLOCKED",
    "SENSITIVE_CLASSIFICATION_UNAVAILABLE",
  ].includes(code)) {
    return fail(code);
  }
  if (code === "PREVIEW_MARKUP_INVALID" || code === "PREVIEW_MARKUP_UNSAFE") {
    return fail(code);
  }
  return fail("PROJECT_FILES_PROVIDER_UNAVAILABLE");
}

export function createWebsiteProjectPreviewBuilder(
  dependencies: WebsiteProjectPreviewBuilderDependencies,
): Readonly<{
  build(input: Readonly<{
    authority: WebsiteProjectFilesAuthority;
    expectedCommitSha: string;
    idempotencyKey: string;
  }>): Promise<WebsiteProjectPreviewBuildResult>;
}> {
  if (
    !dependencies ||
    typeof dependencies.provider?.resolveSnapshot !== "function" ||
    typeof dependencies.provider?.readFile !== "function" ||
    typeof dependencies.storage?.upload !== "function" ||
    typeof dependencies.storage?.createSignedUrl !== "function"
  ) {
    return fail("PREVIEW_BUILDER_CONFIGURATION_ERROR");
  }
  const now = dependencies.now ?? (() => Date.now());
  const signedUrlTtlSeconds = dependencies.signedUrlTtlSeconds ??
    DEFAULT_SIGNED_URL_TTL_SECONDS;
  if (!Number.isInteger(signedUrlTtlSeconds) || signedUrlTtlSeconds < 30) {
    return fail("PREVIEW_BUILDER_CONFIGURATION_ERROR");
  }

  return Object.freeze({
    async build(input) {
      try {
        if (
          !input || typeof input !== "object" ||
          typeof input.expectedCommitSha !== "string" ||
          !SHA.test(input.expectedCommitSha) ||
          typeof input.idempotencyKey !== "string" ||
          input.idempotencyKey.length < 1
        ) {
          return fail("INVALID_REQUEST");
        }

        const snapshot = await dependencies.provider.resolveSnapshot(
          input.authority,
        );
        if (snapshot.commitSha !== input.expectedCommitSha) {
          return fail("PROJECT_FILES_STALE_REVISION");
        }

        const providerFile = await dependencies.provider.readFile({
          authority: input.authority,
          commitSha: snapshot.commitSha,
          rootTreeSha: snapshot.rootTreeSha,
          path: "index.html",
        });
        const inspected = inspectWebsiteProjectFile({
          path: "index.html",
          canonicalPath: providerFile.canonicalPath,
          mode: providerFile.mode,
          objectType: providerFile.objectType,
          declaredSize: providerFile.declaredSize,
          bytes: providerFile.bytes,
        });
        const sanitized = sanitizeStaticPreviewHtml(inspected.content);
        const sanitizedBytes = new TextEncoder().encode(sanitized);
        const sanitizedSha = await sha256Hex(sanitizedBytes);

        const path = objectPath(input.authority, snapshot.commitSha, sanitizedSha);
        const upload = await dependencies.storage.upload(path, sanitizedBytes, {
          contentType: "text/html",
          upsert: false,
        });
        let reuseStatus: "CREATED" | "REUSED" = "CREATED";
        if (upload.error) {
          const message = String(upload.error.message || "");
          if (isAlreadyExistsError(message)) {
            reuseStatus = "REUSED";
          } else {
            return fail("PREVIEW_ARTIFACT_STORAGE_FAILED");
          }
        }

        const signed = await dependencies.storage.createSignedUrl(
          path,
          signedUrlTtlSeconds,
        );
        if (signed.error || !signed.data?.signedUrl) {
          return fail("PREVIEW_SIGNED_URL_FAILED");
        }

        const builtAt = new Date(now()).toISOString();
        const expiresAt = new Date(
          Date.parse(builtAt) + signedUrlTtlSeconds * 1000,
        ).toISOString();

        return Object.freeze({
          contract_version: 1,
          quote_request_id: input.authority.quoteRequestId,
          website_work_context_id: input.authority.websiteWorkContextId,
          website_workspace_id: input.authority.websiteWorkspaceId,
          workspace_state: "REPOSITORY_READY",
          repository: Object.freeze({
            display_name: snapshot.repositoryDisplayName,
            binding_revision: input.authority.bindingRevision,
          }),
          snapshot: Object.freeze({
            commit_sha: snapshot.commitSha,
            ref_label: input.authority.refLabel,
          }),
          build: Object.freeze({
            status: "PASS",
            built_at: builtAt,
            source_path: "index.html",
            sanitization: "STATIC_PREVIEW_SANITIZER_V1",
            idempotency_key: input.idempotencyKey,
          }),
          preview: Object.freeze({
            storage_bucket_id: PREVIEW_BUCKET,
            storage_object_path: path,
            media_type: "text/html",
            sha256: sanitizedSha,
            byte_count: sanitizedBytes.byteLength,
            signed_url: signed.data.signedUrl,
            expires_at: expiresAt,
            reuse_status: reuseStatus,
          }),
        });
      } catch (error) {
        return normalize(error);
      }
    },
  });
}
