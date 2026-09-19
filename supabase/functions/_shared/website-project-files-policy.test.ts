import {
  assert,
  assertEquals,
  assertFalse,
  assertThrows,
} from "jsr:@std/assert@1";
import {
  classifyWebsiteProjectDirectoryEntry,
  classifyWebsiteProjectPath,
  inspectWebsiteProjectFile,
  normalizeWebsiteProjectPath,
  WebsiteProjectFilesPolicyError,
} from "./website-project-files-policy.ts";

const encoder = new TextEncoder();

function assertPolicyError(
  action: () => unknown,
  code: string,
): WebsiteProjectFilesPolicyError {
  const error = assertThrows(
    action,
    WebsiteProjectFilesPolicyError,
    code,
  );
  assertEquals(error.code, code);
  assertEquals(Object.keys(error).sort(), ["code", "name"]);
  return error;
}

function safeBlob(overrides: Record<string, unknown> = {}) {
  return {
    name: "index.ts",
    expectedPath: "src/index.ts",
    canonicalPath: "src/index.ts",
    mode: "100644",
    objectType: "blob",
    objectSha: "a".repeat(40),
    size: 42,
    ...overrides,
  };
}

function readableFile(overrides: Record<string, unknown> = {}) {
  const bytes = encoder.encode("export const ready = true;\n");
  return {
    path: "src/index.ts",
    canonicalPath: "src/index.ts",
    mode: "100644",
    objectType: "blob",
    declaredSize: bytes.byteLength,
    bytes,
    mediaType: "text/plain",
    ...overrides,
  };
}

Deno.test("path policy accepts root only for directory lists", () => {
  assertEquals(normalizeWebsiteProjectPath("", { allowRoot: true }), "");
  assertPolicyError(
    () => normalizeWebsiteProjectPath("", { allowRoot: false }),
    "INVALID_PROJECT_PATH",
  );
  assertEquals(
    normalizeWebsiteProjectPath("src/components/Header.astro", {
      allowRoot: false,
    }),
    "src/components/Header.astro",
  );
});

Deno.test("path policy rejects absolute drive UNC URL and backslash forms", () => {
  for (
    const path of [
      "/etc/passwd",
      "C:/secret.txt",
      "C:\\secret.txt",
      "\\\\server\\share\\secret.txt",
      "//server/share/secret.txt",
      "https://example.test/file.txt",
      "ssh://example.test/file.txt",
      "src\\index.ts",
      "src/file.txt/",
    ]
  ) {
    assertPolicyError(
      () => normalizeWebsiteProjectPath(path, { allowRoot: false }),
      "INVALID_PROJECT_PATH",
    );
  }
});

Deno.test("path policy rejects empty dot dotdot null control and invalid Unicode segments", () => {
  for (
    const path of [
      "src//index.ts",
      "src/./index.ts",
      "src/../index.ts",
      "src/\u0000index.ts",
      "src/\u001findex.ts",
      "src/\u007findex.ts",
      "src/\ud800index.ts",
      "src/\udc00index.ts",
    ]
  ) {
    assertPolicyError(
      () => normalizeWebsiteProjectPath(path, { allowRoot: false }),
      "INVALID_PROJECT_PATH",
    );
  }
});

Deno.test("path policy rejects percent encoded separator dot and null tricks", () => {
  for (
    const path of [
      "src%2fsecret.txt",
      "src/%2E%2E/secret.txt",
      "src/%2e/index.ts",
      "src/%5Csecret.txt",
      "src/%00secret.txt",
      "src/%252fsecret.txt",
      "src/%252E%252E/secret.txt",
    ]
  ) {
    assertPolicyError(
      () => normalizeWebsiteProjectPath(path, { allowRoot: false }),
      "INVALID_PROJECT_PATH",
    );
  }
  assertEquals(
    normalizeWebsiteProjectPath("src/100%25-safe.txt", { allowRoot: false }),
    "src/100%25-safe.txt",
  );
});

Deno.test("path policy rejects non-NFC and NFKC separator ambiguity", () => {
  for (
    const path of [
      "caf\u0065\u0301/menu.ts",
      "safe\uff0fsecret.txt",
      "safe/\uff0e\uff0e/secret.txt",
      "safe\ufe68secret.txt",
      "config/\uff0eenv",
    ]
  ) {
    assertPolicyError(
      () => normalizeWebsiteProjectPath(path, { allowRoot: false }),
      "INVALID_PROJECT_PATH",
    );
  }
  assertEquals(
    normalizeWebsiteProjectPath("caf\u00e9/menu.ts", { allowRoot: false }),
    "caf\u00e9/menu.ts",
  );
});

Deno.test("path policy enforces exact UTF-8 path and segment byte boundaries", () => {
  const path1024 = [
    "a".repeat(254),
    "b".repeat(254),
    "c".repeat(254),
    "d".repeat(254),
    "tail",
  ].join("/");
  const path1025 = `${path1024}x`;
  assertEquals(encoder.encode(path1024).byteLength, 1024);
  assertEquals(encoder.encode(path1025).byteLength, 1025);
  assertEquals(
    normalizeWebsiteProjectPath(path1024, { allowRoot: false }),
    path1024,
  );
  assertPolicyError(
    () => normalizeWebsiteProjectPath(path1025, { allowRoot: false }),
    "INVALID_PROJECT_PATH",
  );

  const segments64 = Array.from({ length: 64 }, (_, index) => `s${index}`).join(
    "/",
  );
  const segments65 = `${segments64}/overflow`;
  assertEquals(
    normalizeWebsiteProjectPath(segments64, { allowRoot: false }),
    segments64,
  );
  assertPolicyError(
    () => normalizeWebsiteProjectPath(segments65, { allowRoot: false }),
    "INVALID_PROJECT_PATH",
  );

  assertEquals(
    normalizeWebsiteProjectPath(`src/${"e".repeat(255)}`, {
      allowRoot: false,
    }),
    `src/${"e".repeat(255)}`,
  );
  assertPolicyError(
    () =>
      normalizeWebsiteProjectPath(`src/${"e".repeat(256)}`, {
        allowRoot: false,
      }),
    "INVALID_PROJECT_PATH",
  );
  assertEquals(
    normalizeWebsiteProjectPath(`src/${"\u00e9".repeat(127)}a`, {
      allowRoot: false,
    }),
    `src/${"\u00e9".repeat(127)}a`,
  );
  assertPolicyError(
    () =>
      normalizeWebsiteProjectPath(`src/${"\u00e9".repeat(128)}`, {
        allowRoot: false,
      }),
    "INVALID_PROJECT_PATH",
  );
});

Deno.test("blocked credential pathname contract is exact and fully redacted", () => {
  const blocked = [
    ".env",
    ".env.local",
    ".env.production",
    "cert.pem",
    "private.key",
    "identity.p12",
    "identity.pfx",
    "id_rsa",
    "id_ed25519",
    "id_ecdsa",
    "id_dsa",
    ".git-credentials",
    ".netrc",
    ".npmrc",
    ".pypirc",
    "credentials.json",
    "service-account.json",
    ".git/config",
    "src/.git/objects/value",
    ".lws/project.json",
  ];
  for (const path of blocked) {
    assertEquals(classifyWebsiteProjectPath(path), "BLOCKED_CREDENTIAL");
    const name = path.split("/").at(-1)!;
    const entry = classifyWebsiteProjectDirectoryEntry(safeBlob({
      name,
      expectedPath: path,
      canonicalPath: path,
      size: 999,
      objectSha: "b".repeat(40),
    }));
    assertEquals(entry, {
      entry_type: "BLOCKED_CREDENTIAL",
      name: "Geblokkeerd bestand",
      kind: "UNSUPPORTED",
      readability: "SENSITIVE_BLOCKED",
      selectable: false,
    });
    const serialized = JSON.stringify(entry);
    assertFalse(serialized.includes(name));
    assertFalse(serialized.includes(path));
    assertFalse(serialized.includes("999"));
    assertFalse(serialized.includes("b".repeat(40)));
  }
});

Deno.test("environment templates pass the name gate and still require content scanning", () => {
  for (const path of [".env.example", ".env.sample", ".env.template"]) {
    assertEquals(classifyWebsiteProjectPath(path), "SAFE");
    assertEquals(
      inspectWebsiteProjectFile(readableFile({
        path,
        canonicalPath: path,
        bytes: encoder.encode("API_KEY=example\n"),
        declaredSize: 16,
      })).readability,
      "TEXT",
    );
    assertPolicyError(
      () =>
        inspectWebsiteProjectFile(readableFile({
          path,
          canonicalPath: path,
          bytes: encoder.encode("API_KEY=real-production-value\n"),
          declaredSize: 30,
        })),
      "SENSITIVE_FILE_BLOCKED",
    );
  }
});

Deno.test("provider token basename rule blocks every authoritative example", () => {
  const blocked = [
    ".github-token",
    ".gitlab-token",
    ".npm-token",
    ".provider-token",
    "github-token",
    "gitlab-token",
    "npm-token",
    "provider-token",
    "github_token",
    "github.token",
    "githubtoken",
    ".github-token.local",
    "github-token.backup",
    "gitlab_token_prod",
    "npm.token.dev",
    "PROVIDER-TOKEN",
    ".GITHUB-TOKEN",
  ];
  for (const basename of blocked) {
    assertEquals(
      classifyWebsiteProjectPath(`config/${basename}`),
      "BLOCKED_CREDENTIAL",
    );
  }
});

Deno.test("provider token basename rule allows authoritative examples and near misses", () => {
  const allowed = [
    "github-actions.yml",
    "provider-config.json",
    "npm-package.json",
    "tokenizer.ts",
    "github-tokenizer.txt",
    "gitlab-ci.yml",
    "package.json",
    "build-token-view.mjs",
    "githubxtoken",
    "github-tokenizer",
    "github-token!backup",
    "github-token.",
    "github-token.-bad",
    "github-token.\u00e9",
  ];
  for (const basename of allowed) {
    assertEquals(classifyWebsiteProjectPath(`config/${basename}`), "SAFE");
  }
  for (
    const basename of ["github.token-a", "GitLab_Token.9", ".NPMTOKEN_dev"]
  ) {
    assertEquals(
      classifyWebsiteProjectPath(`config/${basename}`),
      "BLOCKED_CREDENTIAL",
    );
  }
});

Deno.test("directory metadata mapping is exact and never guesses content state", () => {
  assertEquals(
    classifyWebsiteProjectDirectoryEntry(safeBlob({
      name: "src",
      expectedPath: "src",
      canonicalPath: "src",
      mode: "040000",
      objectType: "tree",
      size: null,
    })),
    {
      entry_type: "ENTRY",
      name: "src",
      path: "src",
      kind: "DIRECTORY",
      size_bytes: null,
      readability: "DIRECTORY",
      selectable: true,
    },
  );
  assertEquals(classifyWebsiteProjectDirectoryEntry(safeBlob()), {
    entry_type: "ENTRY",
    name: "index.ts",
    path: "src/index.ts",
    kind: "FILE",
    size_bytes: 42,
    readability: "READABLE_CANDIDATE",
    selectable: true,
  });
  assertEquals(
    classifyWebsiteProjectDirectoryEntry(safeBlob({ size: null })),
    {
      entry_type: "ENTRY",
      name: "index.ts",
      path: "src/index.ts",
      kind: "FILE",
      size_bytes: null,
      readability: "READABLE_CANDIDATE",
      selectable: true,
    },
  );
  assertEquals(
    classifyWebsiteProjectDirectoryEntry(safeBlob({ size: 1_048_577 })),
    {
      entry_type: "ENTRY",
      name: "index.ts",
      path: "src/index.ts",
      kind: "FILE",
      size_bytes: 1_048_577,
      readability: "TOO_LARGE",
      selectable: false,
    },
  );
});

Deno.test("known symlink and Git-link metadata are inert and non-selectable", () => {
  assertEquals(
    classifyWebsiteProjectDirectoryEntry(safeBlob({
      mode: "120000",
      objectType: "blob",
    })),
    {
      entry_type: "ENTRY",
      name: "index.ts",
      path: "src/index.ts",
      kind: "UNSUPPORTED",
      size_bytes: 42,
      readability: "UNSUPPORTED",
      selectable: false,
    },
  );
  assertEquals(
    classifyWebsiteProjectDirectoryEntry(safeBlob({
      mode: "160000",
      objectType: "commit",
      size: null,
    })),
    {
      entry_type: "ENTRY",
      name: "index.ts",
      path: "src/index.ts",
      kind: "UNSUPPORTED",
      size_bytes: null,
      readability: "UNSUPPORTED",
      selectable: false,
    },
  );
});

Deno.test("unknown malformed and integrity-invalid metadata fails the whole request closed", () => {
  const invalid = [
    safeBlob({ objectType: "unknown" }),
    safeBlob({ mode: "100644", objectType: "tree" }),
    safeBlob({ mode: "040000", objectType: "blob" }),
    safeBlob({ mode: "160000", objectType: "blob" }),
    safeBlob({ name: "" }),
    safeBlob({ objectSha: "bad" }),
    safeBlob({ size: -1 }),
    safeBlob({ size: 1.5 }),
    safeBlob({ canonicalPath: "src/other.ts" }),
    safeBlob({ redirected: true }),
    safeBlob({ rootEscaped: true }),
    safeBlob({ redirected: "true" }),
    safeBlob({ rootEscaped: 1 }),
  ];
  for (const input of invalid) {
    assertPolicyError(
      () => classifyWebsiteProjectDirectoryEntry(input),
      "PROJECT_FILES_PROVIDER_RESPONSE_INVALID",
    );
  }
});

Deno.test("provider canonical path mismatch and root escape fail closed", () => {
  for (
    const input of [
      readableFile({ canonicalPath: "src/other.ts" }),
      readableFile({ redirected: true }),
      readableFile({ rootEscaped: true }),
    ]
  ) {
    assertPolicyError(
      () => inspectWebsiteProjectFile(input),
      "PROJECT_FILES_PROVIDER_RESPONSE_INVALID",
    );
  }
});

Deno.test("direct read of symlink or commit fails closed without target use", () => {
  for (
    const input of [
      readableFile({
        mode: "120000",
        objectType: "blob",
        target: "../../secret",
      }),
      readableFile({
        mode: "160000",
        objectType: "commit",
        target: "other-repository",
      }),
    ]
  ) {
    const error = assertPolicyError(
      () => inspectWebsiteProjectFile(input),
      "PROJECT_PATH_KIND_MISMATCH",
    );
    assertFalse(JSON.stringify(error).includes("target"));
    assertFalse(JSON.stringify(error).includes("secret"));
    assertFalse(JSON.stringify(error).includes("other-repository"));
  }
});

Deno.test("content classifier blocks private keys and authenticated remotes", () => {
  for (
    const text of [
      "-----BEGIN PRIVATE KEY-----\nnot-a-real-key\n",
      "-----BEGIN ENCRYPTED PRIVATE KEY-----\nnot-a-real-key\n",
      "remote=https://user:credential@example.test/owner/repository.git\n",
      "remote=ssh://git:credential@example.test/owner/repository.git\n",
    ]
  ) {
    const bytes = encoder.encode(text);
    assertPolicyError(
      () =>
        inspectWebsiteProjectFile(
          readableFile({ bytes, declaredSize: bytes.length }),
        ),
      "SENSITIVE_FILE_BLOCKED",
    );
  }
});

Deno.test("deterministic sensitive checks cannot be bypassed by classifier SAFE", () => {
  const text = "-----BEGIN PRIVATE KEY-----\nnot-a-real-key\n";
  const bytes = encoder.encode(text);
  assertPolicyError(
    () =>
      inspectWebsiteProjectFile(readableFile({
        bytes,
        declaredSize: bytes.length,
        classifier: { classify: () => "SAFE" },
      })),
    "SENSITIVE_FILE_BLOCKED",
  );
});

Deno.test("content token classifiers enforce exact minimum and token boundaries", () => {
  const blocked = [
    `ghp_${"a".repeat(36)}`,
    `github_pat_${"a".repeat(82)}`,
    `glpat-${"a".repeat(20)}`,
    `glpat-${"a".repeat(24)}`,
    `npm_${"a".repeat(36)}`,
    `before (${`ghp_${"a".repeat(36)}`}) after`,
  ];
  for (const text of blocked) {
    const bytes = encoder.encode(text);
    assertPolicyError(
      () =>
        inspectWebsiteProjectFile(
          readableFile({ bytes, declaredSize: bytes.length }),
        ),
      "SENSITIVE_FILE_BLOCKED",
    );
  }

  const allowed = [
    `ghp_${"a".repeat(35)}`,
    `github_pat_${"a".repeat(81)}`,
    `glpat-${"a".repeat(19)}`,
    `npm_${"a".repeat(35)}`,
    `xghp_${"a".repeat(36)}`,
    `ghp_${"a".repeat(36)}x`,
    `xgithub_pat_${"a".repeat(82)}`,
    `github_pat_${"a".repeat(82)}x`,
    `xglpat-${"a".repeat(20)}`,
    `xnpm_${"a".repeat(36)}`,
  ];
  for (const text of allowed) {
    const bytes = encoder.encode(text);
    assertEquals(
      inspectWebsiteProjectFile(
        readableFile({ bytes, declaredSize: bytes.length }),
      ).readability,
      "TEXT",
    );
  }
});

Deno.test("credential assignment classifier blocks real values and permits explicit dummies", () => {
  for (
    const key of [
      "password",
      "passwd",
      "secret",
      "token",
      "api_key",
      "apikey",
      "private_key",
      "client_secret",
      "API-KEY",
    ]
  ) {
    const bytes = encoder.encode(`${key}=real-value\n`);
    assertPolicyError(
      () =>
        inspectWebsiteProjectFile(
          readableFile({ bytes, declaredSize: bytes.length }),
        ),
      "SENSITIVE_FILE_BLOCKED",
    );
  }
  for (
    const text of [
      "export API_KEY=real-value\n",
      '{"password":"real-value"}',
      "const client_secret = 'real-value';",
    ]
  ) {
    const bytes = encoder.encode(text);
    assertPolicyError(
      () =>
        inspectWebsiteProjectFile(
          readableFile({ bytes, declaredSize: bytes.length }),
        ),
      "SENSITIVE_FILE_BLOCKED",
    );
  }
  for (
    const value of [
      "",
      "example",
      "sample",
      "dummy",
      "changeme",
      "replace-me",
      "${TOKEN_VALUE}",
    ]
  ) {
    const bytes = encoder.encode(`client_secret=${value}\n`);
    assertEquals(
      inspectWebsiteProjectFile(
        readableFile({ bytes, declaredSize: bytes.length }),
      ).readability,
      "TEXT",
    );
  }
});

Deno.test("classifier exception and unavailable result fail closed without content", () => {
  const secret = "classifier-sensitive-body-fragment";
  for (
    const classifier of [
      { classify: () => "UNAVAILABLE" as const },
      {
        classify: () => {
          throw new Error(secret);
        },
      },
    ]
  ) {
    const bytes = encoder.encode(secret);
    const error = assertPolicyError(
      () =>
        inspectWebsiteProjectFile(readableFile({
          bytes,
          declaredSize: bytes.length,
          classifier,
        })),
      "SENSITIVE_CLASSIFICATION_UNAVAILABLE",
    );
    const serialized = `${error.message}\n${error.stack}\n${
      JSON.stringify(error)
    }`;
    assertFalse(serialized.includes(secret));
    assertFalse("content" in error);
    assertFalse("bytes" in error);
  }
});

Deno.test("decoded file size boundary is exact and content is never truncated", () => {
  const maximum = new Uint8Array(1_048_576).fill(0x61);
  const result = inspectWebsiteProjectFile(readableFile({
    bytes: maximum,
    declaredSize: maximum.length,
  }));
  assertEquals(result.readability, "TEXT");
  assertEquals(result.size_bytes, 1_048_576);
  assertEquals(result.content.length, 1_048_576);

  const oversized = new Uint8Array(1_048_577).fill(0x61);
  const error = assertPolicyError(
    () =>
      inspectWebsiteProjectFile(readableFile({
        bytes: oversized,
        declaredSize: oversized.length,
      })),
    "FILE_TOO_LARGE",
  );
  assertFalse("content" in error);
  assertFalse("bytes" in error);
});

Deno.test("unknown declared provider size remains readable under the byte limit", () => {
  const bytes = encoder.encode("safe\n");
  assertEquals(
    inspectWebsiteProjectFile(readableFile({
      bytes,
      declaredSize: null,
    })),
    {
      readability: "TEXT",
      path: "src/index.ts",
      size_bytes: bytes.length,
      media_type: "text/plain",
      encoding: "utf-8",
      content: "safe\n",
    },
  );
});

Deno.test("UTF-8 BOM is removed from accepted complete text", () => {
  const bytes = new Uint8Array([
    0xef,
    0xbb,
    0xbf,
    ...encoder.encode("hello\n"),
  ]);
  assertEquals(
    inspectWebsiteProjectFile(
      readableFile({ bytes, declaredSize: bytes.length }),
    ),
    {
      readability: "TEXT",
      path: "src/index.ts",
      size_bytes: bytes.length,
      media_type: "text/plain",
      encoding: "utf-8",
      content: "hello\n",
    },
  );
});

Deno.test("malformed UTF-8 UTF-16 and legacy bytes are unsupported encoding", () => {
  for (
    const bytes of [
      new Uint8Array([0xc3, 0x28]),
      new Uint8Array([0xff, 0xfe, 0x61, 0x00]),
      new Uint8Array([0xfe, 0xff, 0x00, 0x61]),
      new Uint8Array([0x63, 0x61, 0x66, 0xe9]),
      new Uint8Array([0x00, 0xff]),
    ]
  ) {
    assertPolicyError(
      () =>
        inspectWebsiteProjectFile(
          readableFile({ bytes, declaredSize: bytes.length }),
        ),
      "UNSUPPORTED_ENCODING",
    );
  }
});

Deno.test("null bytes and forbidden control density above one percent are binary", () => {
  const nullBytes = encoder.encode("safe\u0000text");
  assertPolicyError(
    () =>
      inspectWebsiteProjectFile(
        readableFile({ bytes: nullBytes, declaredSize: nullBytes.length }),
      ),
    "BINARY_UNSUPPORTED",
  );

  const onePercent = new Uint8Array(100).fill(0x61);
  onePercent[0] = 0x01;
  assertEquals(
    inspectWebsiteProjectFile(
      readableFile({ bytes: onePercent, declaredSize: onePercent.length }),
    ).readability,
    "TEXT",
  );

  const aboveOnePercent = new Uint8Array(100).fill(0x61);
  aboveOnePercent[0] = 0x01;
  aboveOnePercent[1] = 0x02;
  assertPolicyError(
    () =>
      inspectWebsiteProjectFile(
        readableFile({
          bytes: aboveOnePercent,
          declaredSize: aboveOnePercent.length,
        }),
      ),
    "BINARY_UNSUPPORTED",
  );
});

Deno.test("policy errors expose stable codes only and redact unsafe inputs", () => {
  const unsafe = "https://user:super-secret@example.test/repository";
  const error = assertPolicyError(
    () => normalizeWebsiteProjectPath(unsafe, { allowRoot: false }),
    "INVALID_PROJECT_PATH",
  );
  const serialized = `${error.message}\n${error.stack}\n${
    JSON.stringify(error)
  }`;
  assertFalse(serialized.includes(unsafe));
  assertFalse(serialized.includes("super-secret"));
  assertEquals(error.cause, undefined);
});
