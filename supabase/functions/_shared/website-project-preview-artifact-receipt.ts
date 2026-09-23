import type { WebsiteProjectPreviewOidcAuthority } from "./website-project-preview-oidc-broker.ts";

const SHA = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const DIGITS = /^[1-9][0-9]*$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PATH = /^[A-Za-z0-9._/-]+$/;
const MAX_FILES = 500;
const MAX_FILE_BYTES = 5 * 1024 * 1024;
const MAX_TOTAL_BYTES = 50 * 1024 * 1024;
const ALLOWED_MEDIA_TYPES = new Set([
  "text/html",
  "text/css",
  "text/javascript",
  "application/json",
  "application/xml",
  "text/plain",
  "image/png",
  "image/jpeg",
  "image/gif",
  "image/webp",
  "image/avif",
  "image/x-icon",
  "font/woff",
  "font/woff2",
  "application/octet-stream",
]);

export class WebsiteProjectPreviewArtifactReceiptError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "WebsiteProjectPreviewArtifactReceiptError";
  }
}

function fail(code: string): never {
  throw new WebsiteProjectPreviewArtifactReceiptError(code);
}

function toHex(bytes: Uint8Array): string {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  return toHex(new Uint8Array(await crypto.subtle.digest("SHA-256", Uint8Array.from(bytes).buffer)));
}

export type WebsiteProjectPreviewArtifactReceiptFile = Readonly<{
  relativePath: string;
  contentType: string;
  sha256: string;
  bytes: Uint8Array;
}>;

export type WebsiteProjectPreviewArtifactManifestEntry = Readonly<{
  relativePath: string;
  contentType: string;
  sha256: string;
  bytes: number;
}>;

type ArtifactBinding = Readonly<{
  leaseId: string;
  buildId: string;
  repositoryId: string;
  commitSha: string;
  workflowRunId: string;
}>;

export type WebsiteProjectPreviewArtifactReceiptDependencies = Readonly<{
  resolveAuthority(input: Readonly<{
    leaseId: string;
    buildId: string;
    workflowRunId: string;
  }>): PromiseLike<WebsiteProjectPreviewOidcAuthority>;
  verifyOidc(
    token: string,
    expected: WebsiteProjectPreviewOidcAuthority,
  ): PromiseLike<WebsiteProjectPreviewOidcAuthority>;
  issueToken(input: Readonly<{
    tokenHash: string;
    authority: WebsiteProjectPreviewOidcAuthority;
    ttlSeconds: number;
  }>): PromiseLike<Readonly<{ expiresAt: string }>>;
  openSession(input: Readonly<{
    receiptTokenHash: string;
    sessionTokenHash: string;
    binding: ArtifactBinding;
    primaryRelativePath: string;
    buildStatus: "PASS" | "PASS_WITH_WARNINGS";
    manifest: readonly WebsiteProjectPreviewArtifactManifestEntry[];
    ttlSeconds: number;
  }>): PromiseLike<Readonly<{ expiresAt: string }>>;
  claimFile(input: Readonly<{
    sessionTokenHash: string;
    binding: ArtifactBinding;
    file: WebsiteProjectPreviewArtifactManifestEntry;
  }>): PromiseLike<void>;
  completeFile(input: Readonly<{
    sessionTokenHash: string;
    binding: ArtifactBinding;
    relativePath: string;
  }>): PromiseLike<void>;
  finalizeSession(input: Readonly<{
    sessionTokenHash: string;
    binding: ArtifactBinding;
  }>): PromiseLike<Readonly<{ previewBuildId: string; buildStatus: string }>>;
  abortSession(input: Readonly<{
    sessionTokenHash: string;
    binding: ArtifactBinding;
  }>): PromiseLike<Readonly<{ uploadedPaths: readonly string[] }>>;
  upload(input: Readonly<{
    buildId: string;
    relativePath: string;
    contentType: string;
    bytes: Uint8Array;
  }>): PromiseLike<void>;
  remove(relativePaths: readonly string[], buildId: string): PromiseLike<void>;
  randomBytes(): Uint8Array;
}>;

function validateBinding(input: Readonly<{
  leaseId: string;
  buildId: string;
  repositoryId?: string;
  commitSha?: string;
  workflowRunId: string;
}>): void {
  if (!UUID.test(input.leaseId) || !UUID.test(input.buildId) || !DIGITS.test(input.workflowRunId)
    || (input.repositoryId !== undefined && !DIGITS.test(input.repositoryId))
    || (input.commitSha !== undefined && !SHA.test(input.commitSha))) {
    fail("ARTIFACT_AUTHORITY_INVALID");
  }
}

async function validateFiles(
  files: readonly WebsiteProjectPreviewArtifactReceiptFile[],
): Promise<readonly WebsiteProjectPreviewArtifactReceiptFile[]> {
  if (files.length < 1 || files.length > MAX_FILES) fail("ARTIFACT_FILE_COUNT_INVALID");
  const paths = new Set<string>();
  const validated: WebsiteProjectPreviewArtifactReceiptFile[] = [];
  let totalBytes = 0;
  for (const file of files) {
    const mediaType = file.contentType.split(";", 1)[0].trim().toLowerCase();
    if (!PATH.test(file.relativePath) || file.relativePath.startsWith("/")
      || file.relativePath.includes("..") || paths.has(file.relativePath)) {
      fail("ARTIFACT_PATH_INVALID");
    }
    if (!ALLOWED_MEDIA_TYPES.has(mediaType)) fail("ARTIFACT_TYPE_BLOCKED");
    if (!SHA256.test(file.sha256)) fail("ARTIFACT_HASH_INVALID");
    const bytes = Uint8Array.from(file.bytes);
    if (bytes.byteLength > MAX_FILE_BYTES) fail("ARTIFACT_FILE_TOO_LARGE");
    totalBytes += bytes.byteLength;
    if (totalBytes > MAX_TOTAL_BYTES) fail("ARTIFACT_TOTAL_TOO_LARGE");
    if (await sha256Hex(bytes) !== file.sha256) fail("ARTIFACT_HASH_MISMATCH");
    paths.add(file.relativePath);
    validated.push(Object.freeze({ ...file, contentType: file.contentType.trim(), bytes }));
  }
  return Object.freeze(validated);
}

function validateManifest(
  manifest: readonly WebsiteProjectPreviewArtifactManifestEntry[],
  primaryRelativePath: string,
): readonly WebsiteProjectPreviewArtifactManifestEntry[] {
  if (manifest.length < 1 || manifest.length > MAX_FILES) fail("ARTIFACT_FILE_COUNT_INVALID");
  const paths = new Set<string>();
  let totalBytes = 0;
  const validated = manifest.map((entry) => {
    const mediaType = entry.contentType.split(";", 1)[0].trim().toLowerCase();
    if (!PATH.test(entry.relativePath) || entry.relativePath.startsWith("/")
      || entry.relativePath.includes("..") || paths.has(entry.relativePath)) {
      fail("ARTIFACT_PATH_INVALID");
    }
    if (!ALLOWED_MEDIA_TYPES.has(mediaType)) fail("ARTIFACT_TYPE_BLOCKED");
    if (!SHA256.test(entry.sha256)) fail("ARTIFACT_HASH_INVALID");
    if (!Number.isSafeInteger(entry.bytes) || entry.bytes < 0 || entry.bytes > MAX_FILE_BYTES) {
      fail("ARTIFACT_FILE_TOO_LARGE");
    }
    totalBytes += entry.bytes;
    if (totalBytes > MAX_TOTAL_BYTES) fail("ARTIFACT_TOTAL_TOO_LARGE");
    paths.add(entry.relativePath);
    return Object.freeze({ ...entry, contentType: entry.contentType.trim() });
  });
  if (!paths.has(primaryRelativePath)) fail("ARTIFACT_PRIMARY_PATH_INVALID");
  return Object.freeze(validated);
}

function validateSessionToken(sessionToken: string): void {
  if (!SHA256.test(sessionToken)) fail("ARTIFACT_SESSION_TOKEN_INVALID");
}

export function createWebsiteProjectPreviewArtifactReceiptService(
  dependencies: WebsiteProjectPreviewArtifactReceiptDependencies,
) {
  return Object.freeze({
    async issue(input: Readonly<{
      oidcToken: string;
      leaseId: string;
      buildId: string;
      workflowRunId: string;
    }>): Promise<Readonly<{ token: string; expiresAt: string }>> {
      validateBinding(input);
      const authority = await dependencies.resolveAuthority(input);
      if (authority.leaseId !== input.leaseId || authority.buildId !== input.buildId
        || authority.runId !== input.workflowRunId) {
        fail("ARTIFACT_AUTHORITY_MISMATCH");
      }
      await dependencies.verifyOidc(input.oidcToken, authority);
      const randomBytes = dependencies.randomBytes();
      if (randomBytes.byteLength !== 32) fail("ARTIFACT_TOKEN_GENERATION_FAILED");
      const token = toHex(randomBytes);
      const tokenHash = await sha256Hex(new TextEncoder().encode(token));
      const issued = await dependencies.issueToken({ tokenHash, authority, ttlSeconds: 300 });
      return Object.freeze({ token, expiresAt: issued.expiresAt });
    },

    async begin(input: ArtifactBinding & Readonly<{
      receiptToken: string;
      primaryRelativePath: string;
      buildStatus: "PASS" | "PASS_WITH_WARNINGS";
      manifest: readonly WebsiteProjectPreviewArtifactManifestEntry[];
    }>): Promise<Readonly<{ sessionToken: string; expiresAt: string }>> {
      validateBinding(input);
      if (!SHA256.test(input.receiptToken)) fail("ARTIFACT_TOKEN_INVALID");
      const manifest = validateManifest(input.manifest, input.primaryRelativePath);
      const randomBytes = dependencies.randomBytes();
      if (randomBytes.byteLength !== 32) fail("ARTIFACT_TOKEN_GENERATION_FAILED");
      const sessionToken = toHex(randomBytes);
      const [receiptTokenHash, sessionTokenHash] = await Promise.all([
        sha256Hex(new TextEncoder().encode(input.receiptToken)),
        sha256Hex(new TextEncoder().encode(sessionToken)),
      ]);
      const binding: ArtifactBinding = input;
      const opened = await dependencies.openSession({
        receiptTokenHash,
        sessionTokenHash,
        binding,
        primaryRelativePath: input.primaryRelativePath,
        buildStatus: input.buildStatus,
        manifest,
        ttlSeconds: 600,
      });
      return Object.freeze({ sessionToken, expiresAt: opened.expiresAt });
    },

    async uploadFile(input: ArtifactBinding & WebsiteProjectPreviewArtifactReceiptFile & Readonly<{
      sessionToken: string;
    }>): Promise<Readonly<{ relativePath: string; bytes: number }>> {
      validateBinding(input);
      validateSessionToken(input.sessionToken);
      const [file] = await validateFiles([input]);
      const sessionTokenHash = await sha256Hex(new TextEncoder().encode(input.sessionToken));
      const binding: ArtifactBinding = input;
      const manifestEntry: WebsiteProjectPreviewArtifactManifestEntry = {
        relativePath: file.relativePath,
        contentType: file.contentType,
        sha256: file.sha256,
        bytes: file.bytes.byteLength,
      };
      try {
        await dependencies.claimFile({ sessionTokenHash, binding, file: manifestEntry });
        await dependencies.upload({ buildId: input.buildId, ...file });
        await dependencies.completeFile({ sessionTokenHash, binding, relativePath: file.relativePath });
      } catch (error) {
        const aborted = await dependencies.abortSession({ sessionTokenHash, binding });
        if (aborted.uploadedPaths.length > 0) await dependencies.remove(aborted.uploadedPaths, input.buildId);
        throw error;
      }
      return Object.freeze({ relativePath: file.relativePath, bytes: file.bytes.byteLength });
    },

    async finalize(input: ArtifactBinding & Readonly<{ sessionToken: string }>): Promise<Readonly<{
      previewBuildId: string;
      buildStatus: string;
    }>> {
      validateBinding(input);
      validateSessionToken(input.sessionToken);
      const sessionTokenHash = await sha256Hex(new TextEncoder().encode(input.sessionToken));
      const binding: ArtifactBinding = input;
      try {
        return Object.freeze(await dependencies.finalizeSession({ sessionTokenHash, binding }));
      } catch (error) {
        const aborted = await dependencies.abortSession({ sessionTokenHash, binding });
        if (aborted.uploadedPaths.length > 0) await dependencies.remove(aborted.uploadedPaths, input.buildId);
        throw error;
      }
    },

    async abort(input: ArtifactBinding & Readonly<{ sessionToken: string }>): Promise<Readonly<{
      removedPaths: readonly string[];
    }>> {
      validateBinding(input);
      validateSessionToken(input.sessionToken);
      const sessionTokenHash = await sha256Hex(new TextEncoder().encode(input.sessionToken));
      const binding: ArtifactBinding = input;
      const aborted = await dependencies.abortSession({ sessionTokenHash, binding });
      if (aborted.uploadedPaths.length > 0) await dependencies.remove(aborted.uploadedPaths, input.buildId);
      return Object.freeze({ removedPaths: Object.freeze([...aborted.uploadedPaths]) });
    },

  });
}