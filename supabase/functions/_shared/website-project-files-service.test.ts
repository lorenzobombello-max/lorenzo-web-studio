import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import type {
  ProviderTreeEntry,
  WebsiteProjectFilesAuthority,
  WebsiteProjectFilesProvider,
} from "./website-project-files-provider.ts";
import {
  createWebsiteProjectFilesService,
  WebsiteProjectFilesServiceError,
} from "./website-project-files-service.ts";

const SECRET = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE";
const COMMIT = "a".repeat(40);
const ROOT = "b".repeat(40);
const DIRECTORY_TREE = "c".repeat(40);

const authority = Object.freeze({
  leaseId: "10000000-0000-4000-8000-000000000010",
  actorAuthUserId: "10000000-0000-4000-8000-000000000011",
  quoteRequestId: "10000000-0000-4000-8000-000000000012",
  websiteWorkContextId: "10000000-0000-4000-8000-000000000013",
  websiteWorkspaceId: "10000000-0000-4000-8000-000000000014",
  bindingRevision: 7,
  repositoryProvider: "GITHUB" as const,
  repositoryOwner: "lws-phase-a-fixtures",
  repositoryName: "project-a",
  repositoryExternalId: "7100000001",
  repositoryNodeId: "R_context_a",
  defaultBranch: "main",
  repositoryRef: "heads/main",
  refLabel: "main",
  markerOperationId: "10000000-0000-4000-8000-000000000015",
  expiresAt: "2099-01-01T00:00:00.000Z",
}) satisfies WebsiteProjectFilesAuthority;

function entry(
  name: string,
  objectType: "blob" | "tree" | "commit" = "blob",
  mode = objectType === "tree"
    ? "040000"
    : objectType === "commit"
    ? "160000"
    : "100644",
  size: number | null = objectType === "tree" ? null : 10,
  prefix = "",
): ProviderTreeEntry {
  return Object.freeze({
    name,
    canonicalPath: prefix ? `${prefix}/${name}` : name,
    mode,
    objectType,
    objectSha: "d".repeat(40),
    size,
  });
}

function harness(entries: readonly ProviderTreeEntry[], options: {
  fail?: Error;
  directoryTreeSha?: string;
  now?: number;
} = {}) {
  const resolveCalls: WebsiteProjectFilesAuthority[] = [];
  const listCalls: unknown[] = [];
  const provider: WebsiteProjectFilesProvider = Object.freeze({
    resolveSnapshot(input: WebsiteProjectFilesAuthority) {
      resolveCalls.push(input);
      if (options.fail) return Promise.reject(options.fail);
      return Promise.resolve({
        commitSha: COMMIT,
        rootTreeSha: ROOT,
        repositoryDisplayName: "lws-phase-a-fixtures/project-a",
      });
    },
    listDirectory(
      input: Readonly<{
        authority: WebsiteProjectFilesAuthority;
        commitSha: string;
        rootTreeSha: string;
        directoryTreeSha: string | null;
        path: string;
      }>,
    ) {
      listCalls.push(input);
      if (options.fail) return Promise.reject(options.fail);
      return Promise.resolve({
        directoryTreeSha: options.directoryTreeSha ?? DIRECTORY_TREE,
        entries,
      });
    },
  });
  const service = createWebsiteProjectFilesService({
    provider,
    cursorSecret: SECRET,
    now: () => options.now ?? 1_800_000_000_000,
  });
  return { service, resolveCalls, listCalls };
}

Deno.test("service lists root, nested, and empty directories lazily", async () => {
  for (
    const [path, entries] of [
      ["", [entry("src", "tree")]],
      ["src/components", [
        entry("Header.ts", "blob", "100644", 20, "src/components"),
      ]],
      ["empty", []],
    ] as const
  ) {
    const test = harness(entries);
    const result = await test.service.list({ authority, path, cursor: null });
    assertEquals(result.directory, path);
    assertEquals(result.entries.length, entries.length);
    assertEquals(test.resolveCalls.length, 1);
    assertEquals(test.listCalls.length, 1);
    assertEquals((test.listCalls[0] as { path: string }).path, path);
  }
});

Deno.test("service sorts directories first then Unicode code points", async () => {
  const test = harness([
    entry("z.txt"),
    entry("é.txt"),
    entry("A.txt"),
    entry("z-dir", "tree"),
    entry("A-dir", "tree"),
  ]);
  const result = await test.service.list({ authority, path: "", cursor: null });
  assertEquals(result.entries.map((value: { name: string }) => value.name), [
    "A-dir",
    "z-dir",
    "A.txt",
    "z.txt",
    "é.txt",
  ]);
});

Deno.test("service projects readable, unknown-size, oversize, blocked, symlink, and Git-link entries", async () => {
  const test = harness([
    entry("safe.txt"),
    entry("unknown.txt", "blob", "100644", null),
    entry("large.txt", "blob", "100644", 1_048_577),
    entry(".env"),
    entry("link", "blob", "120000", 20),
    entry("module", "commit", "160000", null),
  ]);
  const result = await test.service.list({ authority, path: "", cursor: null });
  assertEquals(result.entries[0], {
    entry_type: "BLOCKED_CREDENTIAL",
    name: "Geblokkeerd bestand",
    kind: "UNSUPPORTED",
    readability: "SENSITIVE_BLOCKED",
    selectable: false,
  });
  assertEquals(
    result.entries.slice(1).map((value: { readability: string }) =>
      value.readability
    ),
    [
      "TOO_LARGE",
      "UNSUPPORTED",
      "UNSUPPORTED",
      "READABLE_CANDIDATE",
      "READABLE_CANDIDATE",
    ],
  );
});

Deno.test("service limits one page to 500 and cursor continuation stays on immutable snapshot", async () => {
  const entries = Array.from(
    { length: 501 },
    (_, index) => entry(`file-${String(index).padStart(3, "0")}.txt`),
  );
  const first = harness(entries, { now: 1_800_000_000_000 });
  const page = await first.service.list({ authority, path: "", cursor: null });
  assertEquals(page.entries.length, 500);
  assert(typeof page.next_cursor === "string");
  assertEquals(first.resolveCalls.length, 1);

  const moved = harness(entries, { now: 1_800_000_000_001 });
  const continuation = await moved.service.list({
    authority,
    path: "",
    cursor: page.next_cursor,
  });
  assertEquals(continuation.entries.length, 1);
  assertEquals(moved.resolveCalls.length, 0);
  assertEquals((moved.listCalls[0] as { commitSha: string }).commitSha, COMMIT);
  assertEquals(
    (moved.listCalls[0] as { directoryTreeSha: string }).directoryTreeSha,
    DIRECTORY_TREE,
  );
});

Deno.test("service enforces complete UTF-8 gateway envelope ceiling without truncating entries", async () => {
  const safe = harness([entry("x".repeat(100) + ".txt")]);
  const result = await safe.service.list({ authority, path: "", cursor: null });
  const envelope = {
    ok: true,
    code: "APPLICATION_ACTION_ACCEPTED",
    result,
  };
  assert(
    new TextEncoder().encode(JSON.stringify(envelope)).byteLength <= 524_288,
  );

  const deepPrefix = Array.from({ length: 4 }, () => "p".repeat(200)).join("/");
  const huge = harness(Array.from({ length: 500 }, (_, index) =>
    entry(
      `${String(index).padStart(3, "0")}-${"x".repeat(190)}.txt`,
      "blob",
      "100644",
      10,
      deepPrefix,
    )));
  await assertRejects(
    () => huge.service.list({ authority, path: "", cursor: null }),
    WebsiteProjectFilesServiceError,
    "PROJECT_FILES_RESPONSE_TOO_LARGE",
  );
});

Deno.test("service rejects invalid cursor and normalizes snapshot unavailable", async () => {
  const invalid = harness([]);
  await assertRejects(
    () => invalid.service.list({ authority, path: "", cursor: "invalid" }),
    WebsiteProjectFilesServiceError,
    "PROJECT_FILES_CURSOR_INVALID",
  );
  const unavailable = harness([], {
    fail: new Error("PROJECT_FILES_SNAPSHOT_UNAVAILABLE"),
  });
  await assertRejects(
    () => unavailable.service.list({ authority, path: "", cursor: null }),
    WebsiteProjectFilesServiceError,
    "PROJECT_FILES_SNAPSHOT_UNAVAILABLE",
  );
});

Deno.test("service fails malformed provider entries closed with zero partial listing", async () => {
  const test = harness([
    entry("safe.txt"),
    Object.freeze({ ...entry("bad.txt"), canonicalPath: "other.txt" }),
  ]);
  await assertRejects(
    () => test.service.list({ authority, path: "", cursor: null }),
    WebsiteProjectFilesServiceError,
    "PROJECT_FILES_PROVIDER_RESPONSE_INVALID",
  );
});

Deno.test("Phase A provider dependency graph exposes read operations only", () => {
  const test = harness([]);
  assertEquals(Object.keys(test.service), ["list"]);
  assertEquals("read" in test.service, false);
  assertEquals(
    [
      "acquire",
      "release",
      "CREATE_REPOSITORY",
      "CREATE_BLOB",
      "CREATE_TREE",
      "CREATE_COMMIT",
      "CREATE_REF",
      "UPDATE_REF",
      "WRITE_PROJECT_MARKER",
      "RepositoryProvisioningServiceV2",
    ].some((name) => name in test.service),
    false,
  );
});
