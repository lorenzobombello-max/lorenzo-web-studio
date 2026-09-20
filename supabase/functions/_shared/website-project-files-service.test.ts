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
const NEXT_COMMIT = "e".repeat(40);
const NEXT_ROOT = "f".repeat(40);

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
  snapshots?: readonly Readonly<{
    commitSha: string;
    rootTreeSha: string;
    repositoryDisplayName: string;
  }>[];
  readResult?: Readonly<{
    path: string;
    canonicalPath: string;
    mode: string;
    objectType: "blob";
    declaredSize: number | null;
    bytes: Uint8Array;
  }>;
  classifier?: Readonly<{
    classify(
      input: Readonly<{
        path: string;
        bytes: Uint8Array;
        text: string;
      }>,
    ): "SAFE" | "SENSITIVE" | "UNAVAILABLE";
  }>;
} = {}) {
  const resolveCalls: WebsiteProjectFilesAuthority[] = [];
  const listCalls: unknown[] = [];
  const readCalls: unknown[] = [];
  let snapshotIndex = 0;
  const provider = Object.freeze({
    resolveSnapshot(input: WebsiteProjectFilesAuthority) {
      resolveCalls.push(input);
      if (options.fail) return Promise.reject(options.fail);
      const fallback = {
        commitSha: COMMIT,
        rootTreeSha: ROOT,
        repositoryDisplayName: "lws-phase-a-fixtures/project-a",
      };
      const snapshots = options.snapshots ?? [fallback];
      const snapshot =
        snapshots[Math.min(snapshotIndex++, snapshots.length - 1)];
      return Promise.resolve(snapshot);
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
    readFile(input: unknown) {
      readCalls.push(input);
      if (options.fail) return Promise.reject(options.fail);
      return Promise.resolve(
        options.readResult ?? {
          path: "safe.txt",
          canonicalPath: "safe.txt",
          mode: "100644",
          objectType: "blob" as const,
          declaredSize: 4,
          bytes: new TextEncoder().encode("safe"),
        },
      );
    },
  }) as unknown as WebsiteProjectFilesProvider;
  const dependencies = {
    provider,
    cursorSecret: SECRET,
    now: () => options.now ?? 1_800_000_000_000,
    classifier: options.classifier,
  };
  const service = createWebsiteProjectFilesService(dependencies);
  return { service, resolveCalls, listCalls, readCalls };
}

type ReadCapableService = Readonly<{
  read(
    input: Readonly<{
      authority: WebsiteProjectFilesAuthority;
      path: string;
    }>,
  ): Promise<Record<string, unknown>>;
}>;

function readCapable(value: unknown): ReadCapableService {
  return value as ReadCapableService;
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

Deno.test("service exposes bounded file operations without provider primitives", () => {
  const test = harness([]);
  assertEquals(Object.keys(test.service).sort(), ["list", "read", "save"]);
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

Deno.test("successful safe text read", async () => {
  const test = harness([]);
  const result = await readCapable(test.service).read({
    authority,
    path: "safe.txt",
  });
  assertEquals(result, {
    contract_version: 1,
    quote_request_id: authority.quoteRequestId,
    website_work_context_id: authority.websiteWorkContextId,
    workspace_state: "REPOSITORY_READY",
    repository: {
      display_name: "lws-phase-a-fixtures/project-a",
      binding_revision: 7,
    },
    snapshot: { commit_sha: COMMIT, ref_label: "main" },
    file: {
      path: "safe.txt",
      size_bytes: 4,
      media_type: "text/plain",
      encoding: "utf-8",
      content: "safe",
    },
  });
  assertEquals(Object.keys(result), [
    "contract_version",
    "quote_request_id",
    "website_work_context_id",
    "workspace_state",
    "repository",
    "snapshot",
    "file",
  ]);
});

Deno.test("save persists allowed text with expected commit concurrency", async () => {
  const writes: unknown[] = [];
  const provider = Object.freeze({
    resolveSnapshot() {
      return Promise.resolve({
        commitSha: COMMIT,
        rootTreeSha: ROOT,
        repositoryDisplayName: "lws-phase-a-fixtures/project-a",
      });
    },
    listDirectory() {
      return Promise.resolve({ directoryTreeSha: ROOT, entries: [] });
    },
    readFile() {
      return Promise.reject(new Error("PROJECT_FILE_NOT_FOUND"));
    },
    writeFile(input: unknown) {
      writes.push(input);
      return Promise.resolve({ commitSha: NEXT_COMMIT, created: false });
    },
  }) as unknown as WebsiteProjectFilesProvider;
  const service = createWebsiteProjectFilesService({ provider });

  const updated = await service.save({
    authority,
    path: "index.html",
    content: "<!doctype html><h1>HIT001</h1>",
    expectedCommitSha: COMMIT,
  });

  assertEquals(updated.snapshot.commit_sha, NEXT_COMMIT);
  assertEquals(updated.file.path, "index.html");
  assertEquals(updated.file.created, false);
  assertEquals(writes.length, 1);
  await assertRejects(
    () => service.save({
      authority,
      path: "src/new.html",
      content: "<p>new</p>",
      expectedCommitSha: "9".repeat(40),
    }),
    WebsiteProjectFilesServiceError,
    "PROJECT_FILES_STALE_REVISION",
  );
  assertEquals(writes.length, 1);
});

Deno.test("direct read always resolves fresh snapshot", async () => {
  const test = harness([], {
    snapshots: [
      {
        commitSha: COMMIT,
        rootTreeSha: ROOT,
        repositoryDisplayName: "lws-phase-a-fixtures/project-a",
      },
      {
        commitSha: NEXT_COMMIT,
        rootTreeSha: NEXT_ROOT,
        repositoryDisplayName: "lws-phase-a-fixtures/project-a",
      },
    ],
  });
  const service = readCapable(test.service);
  await service.read({ authority, path: "safe.txt" });
  const second = await service.read({ authority, path: "safe.txt" });
  assertEquals(test.resolveCalls.length, 2);
  assertEquals(
    test.readCalls[1] as Record<string, unknown>,
    {
      authority,
      commitSha: NEXT_COMMIT,
      rootTreeSha: NEXT_ROOT,
      path: "safe.txt",
    },
  );
  assertEquals(
    (second.snapshot as { commit_sha: string }).commit_sha,
    NEXT_COMMIT,
  );
});

Deno.test("browser cannot supply commit/ref and stale historical commit cannot be selected", async () => {
  for (
    const extra of [
      { commitSha: COMMIT },
      { commit: COMMIT },
      { ref: "heads/historical" },
      { branch: "historical" },
      { cursor: "opaque" },
    ]
  ) {
    const test = harness([]);
    await assertRejects(
      () =>
        readCapable(test.service).read({
          authority,
          path: "safe.txt",
          ...extra,
        } as never),
      WebsiteProjectFilesServiceError,
      "INVALID_REQUEST",
    );
    assertEquals(test.resolveCalls.length, 0);
    assertEquals(test.readCalls.length, 0);
  }
});

Deno.test("provider declared oversize and decoded oversize return no partial content", async () => {
  for (
    const [declaredSize, bytes] of [
      [1_048_577, new Uint8Array(0)],
      [null, new Uint8Array(1_048_577).fill(0x61)],
    ] as const
  ) {
    const test = harness([], {
      readResult: {
        path: "large.txt",
        canonicalPath: "large.txt",
        mode: "100644",
        objectType: "blob",
        declaredSize,
        bytes,
      },
    });
    const error = await assertRejects(
      () => readCapable(test.service).read({ authority, path: "large.txt" }),
      WebsiteProjectFilesServiceError,
      "FILE_TOO_LARGE",
    );
    assertEquals(JSON.stringify(error).includes("content"), false);
  }
});

Deno.test("strict UTF-8 rejects malformed, UTF-16, and legacy encodings", async () => {
  const cases = [
    new Uint8Array([0xc3, 0x28]),
    new Uint8Array([0xff, 0xfe, 0x41, 0x00]),
    new Uint8Array([0xe9]),
  ];
  for (const bytes of cases) {
    const test = harness([], {
      readResult: {
        path: "encoding.txt",
        canonicalPath: "encoding.txt",
        mode: "100644",
        objectType: "blob",
        declaredSize: bytes.byteLength,
        bytes,
      },
    });
    await assertRejects(
      () => readCapable(test.service).read({ authority, path: "encoding.txt" }),
      WebsiteProjectFilesServiceError,
      "UNSUPPORTED_ENCODING",
    );
  }
});

Deno.test("binary content returns no partial content", async () => {
  const bytes = new Uint8Array([0x61, 0x00, 0x62]);
  const test = harness([], {
    readResult: {
      path: "binary.txt",
      canonicalPath: "binary.txt",
      mode: "100644",
      objectType: "blob",
      declaredSize: bytes.byteLength,
      bytes,
    },
  });
  const error = await assertRejects(
    () => readCapable(test.service).read({ authority, path: "binary.txt" }),
    WebsiteProjectFilesServiceError,
    "BINARY_UNSUPPORTED",
  );
  assertEquals(JSON.stringify(error).includes("a\u0000b"), false);
});

Deno.test("sensitive pathname fails before provider read", async () => {
  const test = harness([]);
  await assertRejects(
    () => readCapable(test.service).read({ authority, path: ".env" }),
    WebsiteProjectFilesServiceError,
    "SENSITIVE_FILE_BLOCKED",
  );
  assertEquals(test.resolveCalls.length, 0);
  assertEquals(test.readCalls.length, 0);
});

Deno.test("sensitive content and unavailable classifier fail closed", async () => {
  const cases = [
    {
      text: "client_secret=real-production-secret",
      classifier: undefined,
      expected: "SENSITIVE_FILE_BLOCKED",
    },
    {
      text: "ordinary text",
      classifier: { classify: () => "UNAVAILABLE" as const },
      expected: "SENSITIVE_CLASSIFICATION_UNAVAILABLE",
    },
    {
      text: "ordinary text",
      classifier: {
        classify: () => {
          throw new Error("classifier raw failure");
        },
      },
      expected: "SENSITIVE_CLASSIFICATION_UNAVAILABLE",
    },
  ];
  for (const scenario of cases) {
    const bytes = new TextEncoder().encode(scenario.text);
    const test = harness([], {
      classifier: scenario.classifier,
      readResult: {
        path: "safe.txt",
        canonicalPath: "safe.txt",
        mode: "100644",
        objectType: "blob",
        declaredSize: bytes.byteLength,
        bytes,
      },
    });
    const error = await assertRejects(
      () => readCapable(test.service).read({ authority, path: "safe.txt" }),
      WebsiteProjectFilesServiceError,
      scenario.expected,
    );
    assertEquals(JSON.stringify(error).includes(scenario.text), false);
  }
});

Deno.test("provider canonical path mismatch returns no content", async () => {
  const bytes = new TextEncoder().encode("safe");
  const test = harness([], {
    readResult: {
      path: "safe.txt",
      canonicalPath: "other.txt",
      mode: "100644",
      objectType: "blob",
      declaredSize: bytes.byteLength,
      bytes,
    },
  });
  const error = await assertRejects(
    () => readCapable(test.service).read({ authority, path: "safe.txt" }),
    WebsiteProjectFilesServiceError,
    "PROJECT_FILES_PROVIDER_RESPONSE_INVALID",
  );
  assertEquals(JSON.stringify(error).includes("safe"), false);
});

Deno.test("UTF-8 BOM is removed while exact byte count is retained", async () => {
  const bytes = new Uint8Array([0xef, 0xbb, 0xbf, 0x73, 0x61, 0x66, 0x65]);
  const test = harness([], {
    readResult: {
      path: "safe.txt",
      canonicalPath: "safe.txt",
      mode: "100644",
      objectType: "blob",
      declaredSize: bytes.byteLength,
      bytes,
    },
  });
  const result = await readCapable(test.service).read({
    authority,
    path: "safe.txt",
  });
  assertEquals(result.file, {
    path: "safe.txt",
    size_bytes: 7,
    media_type: "text/plain",
    encoding: "utf-8",
    content: "safe",
  });
});

Deno.test("file read exposes no provider, download, data, object, signed URL, token, or SHA", async () => {
  const result = await readCapable(harness([]).service).read({
    authority,
    path: "safe.txt",
  });
  const serialized = JSON.stringify(result);
  for (
    const forbidden of [
      "raw.githubusercontent.com",
      "download_url",
      "data:",
      "blob:",
      "object_url",
      "signed_url",
      "ghs_",
      "objectSha",
    ]
  ) assertEquals(serialized.includes(forbidden), false);
});

Deno.test("file provider failures remain stable and leak no raw details", async () => {
  for (
    const code of [
      "PROJECT_FILE_NOT_FOUND",
      "PROJECT_PATH_KIND_MISMATCH",
      "PROJECT_FILES_SNAPSHOT_UNAVAILABLE",
      "PROJECT_FILES_PROVIDER_UNAVAILABLE",
      "PROJECT_FILES_PROVIDER_TIMEOUT",
      "PROJECT_FILES_PROVIDER_THROTTLED",
      "PROJECT_FILES_PROVIDER_RESPONSE_INVALID",
    ]
  ) {
    const test = harness([], { fail: new Error(code) });
    const error = await assertRejects(
      () => readCapable(test.service).read({ authority, path: "safe.txt" }),
      WebsiteProjectFilesServiceError,
      code,
    );
    assertEquals(JSON.stringify(error).includes("github.com"), false);
  }
});
