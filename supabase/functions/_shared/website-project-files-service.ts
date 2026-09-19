import {
  classifyWebsiteProjectDirectoryEntry,
  normalizeWebsiteProjectPath,
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

export type WebsiteProjectFilesService = Readonly<{
  list(
    input: Readonly<{
      authority: WebsiteProjectFilesAuthority;
      path: string;
      cursor: string | null;
    }>,
  ): Promise<WebsiteProjectDirectoryResult>;
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

function normalize(error: unknown): never {
  if (error instanceof WebsiteProjectFilesServiceError) throw error;
  const code = codeOf(error);
  const allowed = new Set([
    "INVALID_PROJECT_PATH",
    "PROJECT_FILES_CURSOR_INVALID",
    "PROJECT_FILES_CURSOR_CONFIGURATION_ERROR",
    "PROJECT_FILES_PROVIDER_RESPONSE_INVALID",
    "PROJECT_FILES_PROVIDER_TIMEOUT",
    "PROJECT_FILES_PROVIDER_THROTTLED",
    "PROJECT_FILES_PROVIDER_UNAVAILABLE",
    "PROJECT_FILES_SNAPSHOT_UNAVAILABLE",
    "REPOSITORY_BINDING_STALE",
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
  });
}
