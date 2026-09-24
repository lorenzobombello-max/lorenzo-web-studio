import { sanitizeStaticPreviewHtml } from "./website-project-preview-sanitizer.ts";

// Validates a built artifact tree (e.g. an Astro `dist/` directory)
// before it is ever read for upload. This is the standalone,
// directly-callable form of the manifest-validation logic proven in
// checkpoint 009-git001c-astro-preview-build-plan.md §14.1/§16.3: every
// tree entry is inspected with `lstat` (never `stat`), so a symlink is
// detected as itself and never dereferenced/followed; every accepted
// regular file's canonical (`realPath`) location is required to stay
// within the declared root, rejecting anything a malformed/malicious
// build could have smuggled outside of it. This same check is intended to
// run twice in the real pipeline (once where the artifact is produced,
// once again after it is transferred to the uploading job) - see §14.1
// "dubbel gecontroleerd" - never trusted from only one side; the second
// pass is `readWebsiteProjectPreviewArtifactFinalBytes` below, which
// independently re-derives (not merely re-reads) the exact final bytes
// for one already-accepted path.
//
// HTML/SVG handling (checkpoint §14.3, "safe AND functional" - not just
// safe-by-blocking-everything for every asset type):
//   - `.html`/`.htm` files are sanitized via the single, shared
//     `sanitizeStaticPreviewHtml` (website-project-preview-sanitizer.ts -
//     the exact same sanitizer the existing synchronous single-file
//     preview builder uses, never a second, divergent copy). The
//     sanitized bytes - not the raw source bytes - are what gets hashed,
//     accepted, and later served: this is what makes HTML both safe
//     (scripts/dangerous constructs stripped) and functional (still
//     rendered, not blocked outright).
//   - `.svg` files are rejected outright (`ASSET_TYPE_BLOCKED`), per the
//     checkpoint's interim decision: no SVG sanitizer has been vetted for
//     this platform, so SVGs remain a documented, visible functional
//     limitation (favicon/social-card missing) rather than an unaudited
//     pass-through. This is a deliberate, narrower asset-type policy -
//     not a general HTML-sanitizer-regex reused for XML/SVG, which would
//     repeat the "wrong validator for the format" mistake this checkpoint
//     explicitly called out.
export class WebsiteProjectPreviewArtifactManifestError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "WebsiteProjectPreviewArtifactManifestError";
  }
}

function fail(code: string): never {
  throw new WebsiteProjectPreviewArtifactManifestError(code);
}

export type WebsiteProjectPreviewArtifactManifestEntry = Readonly<{
  path: string;
  bytes: number;
  sha256: string;
  contentType: string;
}>;

export type WebsiteProjectPreviewArtifactRejection = Readonly<{
  path: string;
  reason:
    | "SYMLINK_REJECTED"
    | "PATH_TRAVERSAL_REJECTED"
    | "UNSUPPORTED_NODE_TYPE"
    | "UNRESOLVABLE_PATH"
    | "FILE_TOO_LARGE"
    | "ASSET_TYPE_BLOCKED"
    | "MARKUP_UNSAFE";
}>;

export type WebsiteProjectPreviewArtifactManifest = Readonly<{
  root: string;
  accepted: readonly WebsiteProjectPreviewArtifactManifestEntry[];
  rejected: readonly WebsiteProjectPreviewArtifactRejection[];
  totalBytes: number;
}>;

export type WebsiteProjectPreviewArtifactManifestLimits = Readonly<{
  maxFileBytes: number;
  maxTotalBytes: number;
  maxFileCount: number;
}>;

// Matches the standard values proposed in checkpoint §11: 5 MiB per file,
// 50 MiB total per build, 500 files.
export const DEFAULT_ARTIFACT_MANIFEST_LIMITS: WebsiteProjectPreviewArtifactManifestLimits =
  Object.freeze({
    maxFileBytes: 5 * 1024 * 1024,
    maxTotalBytes: 50 * 1024 * 1024,
    maxFileCount: 500,
  });

// Fixed, narrow extension allowlist->content-type map. Anything not
// listed here still gets a safe, generic content type
// (application/octet-stream) rather than being guessed/sniffed from
// content - guessing content type from bytes is itself a historical
// source of browser content-sniffing vulnerabilities.
const CONTENT_TYPES: Readonly<Record<string, string>> = Object.freeze({
  html: "text/html; charset=utf-8",
  htm: "text/html; charset=utf-8",
  css: "text/css; charset=utf-8",
  js: "text/javascript; charset=utf-8",
  mjs: "text/javascript; charset=utf-8",
  json: "application/json; charset=utf-8",
  xml: "application/xml; charset=utf-8",
  txt: "text/plain; charset=utf-8",
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  gif: "image/gif",
  webp: "image/webp",
  avif: "image/avif",
  ico: "image/x-icon",
  woff: "font/woff",
  woff2: "font/woff2",
});

const BLOCKED_EXTENSIONS: ReadonlySet<string> = new Set(["svg"]);

function extensionOf(relativePath: string): string {
  const lastSegment = relativePath.split(/[\\/]/).pop() ?? relativePath;
  const dot = lastSegment.lastIndexOf(".");
  return dot < 0 ? "" : lastSegment.slice(dot + 1).toLowerCase();
}

function contentTypeFor(extension: string): string {
  return CONTENT_TYPES[extension] ?? "application/octet-stream";
}

function sha256Hex(bytes: Uint8Array): Promise<string> {
  const buffer = Uint8Array.from(bytes).buffer;
  return crypto.subtle.digest("SHA-256", buffer).then((digest) =>
    [...new Uint8Array(digest)].map((byte) =>
      byte.toString(16).padStart(2, "0")
    ).join("")
  );
}

// Applies the single, shared HTML sanitizer to accepted `.html`/`.htm`
// bytes. Returns the sanitized bytes on success, or `null` if the content
// could not be safely decoded/sanitized - callers treat `null` as a
// MARKUP_UNSAFE rejection, never as an empty-but-accepted file.
async function sanitizeIfHtml(
  extension: string,
  rawBytes: Uint8Array,
): Promise<Uint8Array | null> {
  if (extension !== "html" && extension !== "htm") return rawBytes;
  let text: string;
  try {
    // `fatal: true` refuses to silently replace invalid byte sequences -
    // a file that isn't valid UTF-8 text is not safely sanitizable as
    // HTML and must be rejected, not passed through with mangled bytes.
    text = new TextDecoder("utf-8", { fatal: true }).decode(rawBytes);
  } catch {
    return null;
  }
  try {
    const sanitized = sanitizeStaticPreviewHtml(text);
    return new TextEncoder().encode(sanitized);
  } catch {
    return null;
  }
}

function withinRoot(canonicalRoot: string, canonicalPath: string): boolean {
  if (canonicalPath === canonicalRoot) return true;
  const separators = ["/", "\\"];
  return separators.some((separator) =>
    canonicalPath.startsWith(canonicalRoot + separator)
  );
}

// Re-derives the canonical, final bytes for exactly one already-accepted
// manifest path, independently of `buildWebsiteProjectPreviewArtifactManifest`.
// This is the "second, independent check" referenced throughout this
// module's design notes: an uploading step must call this - not trust a
// manifest entry's `sha256` field blindly - and compare the resulting
// hash against the manifest to prove the bytes it is about to upload are
// exactly what was validated, not something substituted in between.
// Re-applies every safety check (symlink rejection, path-containment,
// size limit, HTML sanitization, SVG blocking) from scratch.
export async function readWebsiteProjectPreviewArtifactFinalBytes(
  root: string,
  relativePath: string,
  limits: WebsiteProjectPreviewArtifactManifestLimits =
    DEFAULT_ARTIFACT_MANIFEST_LIMITS,
): Promise<Uint8Array> {
  const canonicalRoot = await Deno.realPath(root);
  const full = `${canonicalRoot}/${relativePath}`;
  const info = await Deno.lstat(full);
  if (info.isSymlink) fail("SYMLINK_REJECTED");
  if (!info.isFile) fail("UNSUPPORTED_NODE_TYPE");
  let canonical: string;
  try {
    canonical = await Deno.realPath(full);
  } catch {
    fail("UNRESOLVABLE_PATH");
  }
  if (!withinRoot(canonicalRoot, canonical)) fail("PATH_TRAVERSAL_REJECTED");
  const rawBytes = await Deno.readFile(full);
  if (rawBytes.byteLength > limits.maxFileBytes) fail("FILE_TOO_LARGE");
  const extension = extensionOf(relativePath);
  if (BLOCKED_EXTENSIONS.has(extension)) fail("ASSET_TYPE_BLOCKED");
  const finalBytes = await sanitizeIfHtml(extension, rawBytes);
  if (finalBytes === null) fail("MARKUP_UNSAFE");
  return finalBytes;
}

async function walk(
  canonicalRoot: string,
  root: string,
  dir: string,
  limits: WebsiteProjectPreviewArtifactManifestLimits,
  accepted: WebsiteProjectPreviewArtifactManifestEntry[],
  rejected: WebsiteProjectPreviewArtifactRejection[],
): Promise<number> {
  let runningTotal = 0;
  for await (const entry of Deno.readDir(dir)) {
    const full = `${dir}/${entry.name}`;
    const relative = full.slice(root.length + 1);
    const info = await Deno.lstat(full);
    if (info.isSymlink) {
      rejected.push({ path: relative, reason: "SYMLINK_REJECTED" });
      continue;
    }
    if (info.isDirectory) {
      runningTotal += await walk(
        canonicalRoot,
        root,
        full,
        limits,
        accepted,
        rejected,
      );
      continue;
    }
    if (!info.isFile) {
      rejected.push({ path: relative, reason: "UNSUPPORTED_NODE_TYPE" });
      continue;
    }
    let canonical: string;
    try {
      canonical = await Deno.realPath(full);
    } catch {
      rejected.push({ path: relative, reason: "UNRESOLVABLE_PATH" });
      continue;
    }
    if (!withinRoot(canonicalRoot, canonical)) {
      rejected.push({ path: relative, reason: "PATH_TRAVERSAL_REJECTED" });
      continue;
    }
    if (info.size > limits.maxFileBytes) {
      rejected.push({ path: relative, reason: "FILE_TOO_LARGE" });
      continue;
    }
    const extension = extensionOf(relative);
    if (BLOCKED_EXTENSIONS.has(extension)) {
      rejected.push({ path: relative, reason: "ASSET_TYPE_BLOCKED" });
      continue;
    }
    const rawBytes = await Deno.readFile(full);
    // Authoritative, read-time size check - the lstat-based check above
    // is only a cheap fast-path that avoids reading obviously-oversized
    // files; a file that changed between lstat and read must still be
    // caught here rather than trusted from the earlier, now-stale stat.
    if (rawBytes.byteLength > limits.maxFileBytes) {
      rejected.push({ path: relative, reason: "FILE_TOO_LARGE" });
      continue;
    }
    const finalBytes = await sanitizeIfHtml(extension, rawBytes);
    if (finalBytes === null) {
      rejected.push({ path: relative, reason: "MARKUP_UNSAFE" });
      continue;
    }
    const sha256 = await sha256Hex(finalBytes);
    accepted.push({
      path: relative,
      bytes: finalBytes.byteLength,
      sha256,
      contentType: contentTypeFor(extension),
    });
    runningTotal += finalBytes.byteLength;
  }
  return runningTotal;
}

// Builds the full accept/reject manifest for a build's output directory.
// Never throws for an individual bad entry - every entry is reported, not
// silently dropped - but does throw for a whole-tree limit violation
// (too many accepted files, or total accepted bytes over budget), since
// those are build-level, not entry-level, failures.
export async function buildWebsiteProjectPreviewArtifactManifest(
  root: string,
  limits: WebsiteProjectPreviewArtifactManifestLimits =
    DEFAULT_ARTIFACT_MANIFEST_LIMITS,
): Promise<WebsiteProjectPreviewArtifactManifest> {
  const canonicalRoot = await Deno.realPath(root);
  const accepted: WebsiteProjectPreviewArtifactManifestEntry[] = [];
  const rejected: WebsiteProjectPreviewArtifactRejection[] = [];
  const totalBytes = await walk(
    canonicalRoot,
    canonicalRoot,
    canonicalRoot,
    limits,
    accepted,
    rejected,
  );
  if (accepted.length > limits.maxFileCount) {
    fail("TOO_MANY_FILES");
  }
  if (totalBytes > limits.maxTotalBytes) {
    fail("TOTAL_SIZE_EXCEEDED");
  }
  return Object.freeze({
    root: canonicalRoot,
    accepted: Object.freeze(accepted),
    rejected: Object.freeze(rejected),
    totalBytes,
  });
}
