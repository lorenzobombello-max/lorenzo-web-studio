import {
  classifyWebsiteProjectDirectoryEntry,
  classifyWebsiteProjectPath,
  inspectWebsiteProjectFile,
  normalizeWebsiteProjectPath,
  type SensitiveContentClassifier,
  type WebsiteProjectDirectoryEntry,
} from "./website-project-files-policy.ts";
import {
  signWebsiteProjectFilesCursor,
  verifyWebsiteProjectFilesCursor,
} from "./website-project-files-cursor.ts";
import type {
  ProviderTreeEntry,
  WebsiteProjectFilesAuthority,
  WebsiteProjectFilesProvider,
} from "./website-project-files-provider.ts";

const PAGE_SIZE = 500;
const MAX_ENVELOPE_BYTES = 524_288;
const SHA = /^[0-9a-f]{40}$/;

export type WebsiteProjectDirectoryResult = Readonly<{
  contract_version: 1;
  quote_request_id: string;
  website_work_context_id: string;
  workspace_state: "REPOSITORY_READY";
  repository: Readonly<{ display_name: string; binding_revision: number }>;
  snapshot: Readonly<{ commit_sha: string; ref_label: string }>;
  directory: string;
  entries: readonly WebsiteProjectDirectoryEntry[];
  next_cursor: string | null;
}>;

export type WebsiteProjectFileResult = Readonly<{
  contract_version: 1;
  quote_request_id: string;
  website_work_context_id: string;
  workspace_state: "REPOSITORY_READY";
  repository: Readonly<{ display_name: string; binding_revision: number }>;
  snapshot: Readonly<{ commit_sha: string; ref_label: string }>;
  file: Readonly<{
    path: string;
    size_bytes: number;
    media_type: "text/plain";
    encoding: "utf-8";
    content: string;
  }>;
}>;

export type WebsiteProjectFileSaveResult = Readonly<{
  contract_version: 1;
  quote_request_id: string;
  website_work_context_id: string;
  workspace_state: "REPOSITORY_READY";
  repository: Readonly<{ display_name: string; binding_revision: number }>;
  snapshot: Readonly<{ commit_sha: string; ref_label: string }>;
  file: Readonly<{ path: string; created: boolean }>;
}>;

export type WebsiteProjectFilesService = Readonly<{
  list(
    input: Readonly<{
      authority: WebsiteProjectFilesAuthority;
      path: string;
      cursor: string | null;
    }>,
  ): Promise<WebsiteProjectDirectoryResult>;
  read(
    input: Readonly<{
      authority: WebsiteProjectFilesAuthority;
      path: string;
    }>,
  ): Promise<WebsiteProjectFileResult>;
  save(
    input: Readonly<{
      authority: WebsiteProjectFilesAuthority;
      path: string;
      content: string;
      expectedCommitSha: string;
    }>,
  ): Promise<WebsiteProjectFileSaveResult>;
}>;

export class WebsiteProjectFilesServiceError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "WebsiteProjectFilesServiceError";
  }
}

type ServiceDependencies = Readonly<{
  provider: WebsiteProjectFilesProvider;
  cursorSecret?: string;
  now?: () => number;
  classifier?: SensitiveContentClassifier;
}>;

function fail(code: string): never {
  throw new WebsiteProjectFilesServiceError(code);
}

function codeOf(error: unknown): string {
  if (
    error && typeof error === "object" && "code" in error &&
    typeof error.code === "string"
  ) return error.code;
  if (error instanceof Error) return error.message;
  return "PROJECT_FILES_PROVIDER_UNAVAILABLE";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(
  value: Record<string, unknown>,
  expected: readonly string[],
) {
  const actual = Object.keys(value).sort();
  const allowed = [...expected].sort();
  return actual.length === allowed.length &&
    actual.every((key, index) => key === allowed[index]);
}

function normalize(error: unknown): never {
  if (error instanceof WebsiteProjectFilesServiceError) throw error;
  const code = codeOf(error);
  const allowed = new Set([
    "INVALID_REQUEST",
    "INVALID_PROJECT_PATH",
    "PROJECT_FILES_CURSOR_INVALID",
    "PROJECT_FILES_CURSOR_CONFIGURATION_ERROR",
    "PROJECT_FILES_PROVIDER_RESPONSE_INVALID",
    "PROJECT_FILES_PROVIDER_TIMEOUT",
    "PROJECT_FILES_PROVIDER_THROTTLED",
    "PROJECT_FILES_PROVIDER_UNAVAILABLE",
    "PROJECT_FILES_SNAPSHOT_UNAVAILABLE",
    "PROJECT_FILE_NOT_FOUND",
    "PROJECT_PATH_KIND_MISMATCH",
    "FILE_TOO_LARGE",
    "BINARY_UNSUPPORTED",
    "UNSUPPORTED_ENCODING",
    "SENSITIVE_FILE_BLOCKED",
    "SENSITIVE_CLASSIFICATION_UNAVAILABLE",
    "REPOSITORY_BINDING_STALE",
    "PROJECT_FILES_STALE_REVISION",
  ]);
  return fail(allowed.has(code) ? code : "PROJECT_FILES_PROVIDER_UNAVAILABLE");
}

function compareCodePoints(left: string, right: string): number {
  const leftPoints = Array.from(left, (value) => value.codePointAt(0)!);
  const rightPoints = Array.from(right, (value) => value.codePointAt(0)!);
  const length = Math.min(leftPoints.length, rightPoints.length);
  for (let index = 0; index < length; index++) {
    if (leftPoints[index] !== rightPoints[index]) {
      return leftPoints[index] - rightPoints[index];
    }
  }
  return leftPoints.length - rightPoints.length;
}

function directoryFirst(
  left: ProviderTreeEntry,
  right: ProviderTreeEntry,
): number {
  const leftDirectory = left.objectType === "tree" && left.mode === "040000";
  const rightDirectory = right.objectType === "tree" && right.mode === "040000";
  if (leftDirectory !== rightDirectory) return leftDirectory ? -1 : 1;
  return compareCodePoints(left.name, right.name);
}

function project(entry: ProviderTreeEntry): WebsiteProjectDirectoryEntry {
  return classifyWebsiteProjectDirectoryEntry({
    name: entry.name,
    expectedPath: entry.canonicalPath,
    canonicalPath: entry.canonicalPath,
    mode: entry.mode,
    objectType: entry.objectType,
    objectSha: entry.objectSha,
    size: entry.size,
  });
}

function envelopeBytes(result: WebsiteProjectDirectoryResult): number {
  return new TextEncoder().encode(JSON.stringify({
    ok: true,
    code: "APPLICATION_ACTION_ACCEPTED",
    result,
  })).byteLength;
}

export function createWebsiteProjectFilesService(
  dependencies: ServiceDependencies,
): WebsiteProjectFilesService {
  if (
    !dependencies ||
    typeof dependencies.provider?.resolveSnapshot !== "function" ||
    typeof dependencies.provider?.listDirectory !== "function" ||
    typeof dependencies.provider?.readFile !== "function" ||
    dependencies.now !== undefined && typeof dependencies.now !== "function"
  ) {
    return fail("PROJECT_FILES_SERVICE_CONFIGURATION_ERROR");
  }

  function cursorDependencies() {
    return {
      now: dependencies.now?.(),
      secret: dependencies.cursorSecret,
    };
  }

  return Object.freeze({
    async list(input) {
      try {
        if (
          !input || typeof input !== "object" ||
          typeof input.path !== "string" ||
          input.cursor !== null && typeof input.cursor !== "string"
        ) {
          return fail("INVALID_PROJECT_PATH");
        }
        const directory = normalizeWebsiteProjectPath(input.path, {
          allowRoot: true,
        });
        let commitSha: string;
        let rootTreeSha: string;
        let directoryTreeSha: string | null;
        let offset: number;
        let displayName: string;

        if (input.cursor === null) {
          const snapshot = await dependencies.provider.resolveSnapshot(
            input.authority,
          );
          commitSha = snapshot.commitSha;
          rootTreeSha = snapshot.rootTreeSha;
          directoryTreeSha = null;
          offset = 0;
          displayName = snapshot.repositoryDisplayName;
        } else {
          const payload = await verifyWebsiteProjectFilesCursor(
            input.cursor,
            {
              actorAuthUserId: input.authority.actorAuthUserId,
              websiteWorkContextId: input.authority.websiteWorkContextId,
              repositoryExternalId: input.authority.repositoryExternalId,
              bindingRevision: input.authority.bindingRevision,
              directory,
            },
            cursorDependencies(),
          );
          commitSha = payload.commitSha;
          rootTreeSha = payload.rootTreeSha;
          directoryTreeSha = payload.directoryTreeSha;
          offset = payload.offset;
          displayName =
            `${input.authority.repositoryOwner}/${input.authority.repositoryName}`;
        }

        const listing = await dependencies.provider.listDirectory({
          authority: input.authority,
          commitSha,
          rootTreeSha,
          directoryTreeSha,
          path: directory,
        });
        const sorted = [...listing.entries].sort(directoryFirst);
        if (offset > sorted.length) return fail("PROJECT_FILES_CURSOR_INVALID");
        const page = sorted.slice(offset, offset + PAGE_SIZE).map(project);
        const nextOffset = offset + page.length;
        const nextCursor = nextOffset < sorted.length
          ? await signWebsiteProjectFilesCursor({
            actorAuthUserId: input.authority.actorAuthUserId,
            websiteWorkContextId: input.authority.websiteWorkContextId,
            repositoryExternalId: input.authority.repositoryExternalId,
            bindingRevision: input.authority.bindingRevision,
            commitSha,
            rootTreeSha,
            directory,
            directoryTreeSha: listing.directoryTreeSha,
            offset: nextOffset,
          }, cursorDependencies())
          : null;
        const result: WebsiteProjectDirectoryResult = Object.freeze({
          contract_version: 1,
          quote_request_id: input.authority.quoteRequestId,
          website_work_context_id: input.authority.websiteWorkContextId,
          workspace_state: "REPOSITORY_READY",
          repository: Object.freeze({
            display_name: displayName,
            binding_revision: input.authority.bindingRevision,
          }),
          snapshot: Object.freeze({
            commit_sha: commitSha,
            ref_label: input.authority.refLabel,
          }),
          directory,
          entries: Object.freeze(page),
          next_cursor: nextCursor,
        });
        if (envelopeBytes(result) > MAX_ENVELOPE_BYTES) {
          return fail("PROJECT_FILES_RESPONSE_TOO_LARGE");
        }
        return result;
      } catch (error) {
        return normalize(error);
      }
    },

    async read(input) {
      try {
        if (
          !isRecord(input) || !exactKeys(input, ["authority", "path"]) ||
          typeof input.path !== "string"
        ) return fail("INVALID_REQUEST");
        const path = normalizeWebsiteProjectPath(input.path, {
          allowRoot: false,
        });
        if (classifyWebsiteProjectPath(path) === "BLOCKED_CREDENTIAL") {
          return fail("SENSITIVE_FILE_BLOCKED");
        }
        const snapshot = await dependencies.provider.resolveSnapshot(
          input.authority,
        );
        const providerFile = await dependencies.provider.readFile({
          authority: input.authority,
          commitSha: snapshot.commitSha,
          rootTreeSha: snapshot.rootTreeSha,
          path,
        });
        const inspected = inspectWebsiteProjectFile({
          path,
          canonicalPath: providerFile.canonicalPath,
          mode: providerFile.mode,
          objectType: providerFile.objectType,
          declaredSize: providerFile.declaredSize,
          bytes: providerFile.bytes,
          classifier: dependencies.classifier,
        });
        return Object.freeze({
          contract_version: 1,
          quote_request_id: input.authority.quoteRequestId,
          website_work_context_id: input.authority.websiteWorkContextId,
          workspace_state: "REPOSITORY_READY",
          repository: Object.freeze({
            display_name: snapshot.repositoryDisplayName,
            binding_revision: input.authority.bindingRevision,
          }),
          snapshot: Object.freeze({
            commit_sha: snapshot.commitSha,
            ref_label: input.authority.refLabel,
          }),
          file: Object.freeze({
            path: inspected.path,
            size_bytes: inspected.size_bytes,
            media_type: inspected.media_type,
            encoding: inspected.encoding,
            content: inspected.content,
          }),
        });
      } catch (error) {
        return normalize(error);
      }
    },

    async save(input) {
      try {
        if (
          !isRecord(input) ||
          !exactKeys(input, [
            "authority",
            "content",
            "expectedCommitSha",
            "path",
          ]) ||
          typeof input.path !== "string" ||
          typeof input.content !== "string" ||
          typeof input.expectedCommitSha !== "string" ||
          !SHA.test(input.expectedCommitSha) ||
          typeof dependencies.provider.writeFile !== "function"
        ) return fail("INVALID_REQUEST");
        const path = normalizeWebsiteProjectPath(input.path, {
          allowRoot: false,
        });
        if (classifyWebsiteProjectPath(path) === "BLOCKED_CREDENTIAL") {
          return fail("SENSITIVE_FILE_BLOCKED");
        }
        const bytes = new TextEncoder().encode(input.content);
        const inspected = inspectWebsiteProjectFile({
          path,
          canonicalPath: path,
          mode: "100644",
          objectType: "blob",
          declaredSize: bytes.byteLength,
          bytes,
          classifier: dependencies.classifier,
        });
        if (inspected.content !== input.content) {
          return fail("UNSUPPORTED_ENCODING");
        }
        const snapshot = await dependencies.provider.resolveSnapshot(
          input.authority,
        );
        if (snapshot.commitSha !== input.expectedCommitSha) {
          return fail("PROJECT_FILES_STALE_REVISION");
        }
        const written = await dependencies.provider.writeFile({
          authority: input.authority,
          parentCommitSha: snapshot.commitSha,
          rootTreeSha: snapshot.rootTreeSha,
          path,
          bytes,
        });
        if (
          !written || !SHA.test(written.commitSha) ||
          typeof written.created !== "boolean"
        ) return fail("PROJECT_FILES_PROVIDER_RESPONSE_INVALID");
        return Object.freeze({
          contract_version: 1,
          quote_request_id: input.authority.quoteRequestId,
          website_work_context_id: input.authority.websiteWorkContextId,
          workspace_state: "REPOSITORY_READY",
          repository: Object.freeze({
            display_name: snapshot.repositoryDisplayName,
            binding_revision: input.authority.bindingRevision,
          }),
          snapshot: Object.freeze({
            commit_sha: written.commitSha,
            ref_label: input.authority.refLabel,
          }),
          file: Object.freeze({ path, created: written.created }),
        });
      } catch (error) {
        return normalize(error);
      }
    },
  });
}
