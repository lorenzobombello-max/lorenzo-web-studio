// Single, shared implementation of the static-preview HTML sanitizer and
// its supporting sha256 helper. Extracted out of
// website-project-preview-builder.ts so the asynchronous, multi-file
// preview pipeline (website-project-preview-artifact-manifest.ts) can
// reuse the exact same, single sanitization logic rather than defining a
// second, divergent copy of these regexes - the duplicate-validator
// drift previously found and fixed in
// website-project-files-provider.ts (GIT-001, root-cause fix) is exactly
// the failure mode this extraction avoids repeating.
const DANGEROUS_PATTERN =
  /<iframe\b|<object\b|<embed\b|<meta\b[^>]*http-equiv\s*=\s*["']?refresh["']?|<base\b|javascript\s*:/iu;
const INLINE_HANDLER_PATTERN =
  /\son[a-z0-9_-]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/giu;
const SCRIPT_TAG_PATTERN =
  /<script\b[^>]*>[\s\S]*?<\/script\s*>|<script\b[^>]*\/\s*>/giu;

export class WebsiteProjectPreviewSanitizationError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "WebsiteProjectPreviewSanitizationError";
  }
}

function fail(code: string): never {
  throw new WebsiteProjectPreviewSanitizationError(code);
}

export function sanitizeStaticPreviewHtml(content: string): string {
  if (typeof content !== "string" || content.length < 1) {
    return fail("PREVIEW_MARKUP_INVALID");
  }
  if (DANGEROUS_PATTERN.test(content)) {
    return fail("PREVIEW_MARKUP_UNSAFE");
  }
  const withoutScripts = content.replaceAll(SCRIPT_TAG_PATTERN, "");
  const withoutInlineHandlers = withoutScripts.replaceAll(
    INLINE_HANDLER_PATTERN,
    "",
  );
  return withoutInlineHandlers;
}

export function sha256Hex(bytes: Uint8Array): Promise<string> {
  const buffer = Uint8Array.from(bytes).buffer;
  return crypto.subtle.digest("SHA-256", buffer).then((digest) =>
    [...new Uint8Array(digest)].map((byte) =>
      byte.toString(16).padStart(2, "0")
    ).join("")
  );
}
