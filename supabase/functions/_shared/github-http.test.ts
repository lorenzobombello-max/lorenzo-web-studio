import {
  assert,
  assertEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1";
import {
  createGitHubRefReadDiagnostic,
  GITHUB_REF_READ_DIAGNOSTIC_COMBINATIONS,
  validateGitHubRefReadDiagnostic,
} from "./github-ref-read-diagnostic.ts";
import {
  createGitHubHttpClient,
  GitHubHttpError,
  type GitHubHttpOperation,
} from "./github-http.ts";

const TOKEN = `ghs_${"a".repeat(36)}`;
const APP_JWT = "synthetic.app.jwt";
const SHA = "a".repeat(40);
const TREE_SHA = "b".repeat(40);
const CONTENT_SHA = "c".repeat(40);
const REPOSITORY_ID = "987654321";
const INSTALLATION_ID = "123456789";
const NOW = Date.parse("2026-09-13T12:00:00.000Z");
const OWNER = "lorenzo-web-solutions-lab";
const REPOSITORY = "lws-web-01994f12a00070008000000000000001";
const TEMPLATE = "lws-website-starter";

function json(
  value: unknown,
  status = 200,
  headers: HeadersInit = {},
): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

function repositoryResponse(name = REPOSITORY) {
  return {
    id: Number(REPOSITORY_ID),
    node_id: "R_test_node_1",
    name,
    full_name: `${OWNER}/${name}`,
    private: true,
    owner: { login: OWNER },
    default_branch: "main",
    description: "Synthetic Task 13 test island",
    created_at: "2026-09-13T12:00:00.000Z",
  };
}

function operation(
  value: GitHubHttpOperation,
): GitHubHttpOperation {
  return value;
}

function tokenResponse(overrides: Record<string, unknown> = {}) {
  return {
    token: TOKEN,
    expires_at: "2026-09-13T12:55:00.000Z",
    repository_selection: "selected",
    permissions: { metadata: "read", administration: "write" },
    ...overrides,
  };
}

function executeTokenExchange(
  client: ReturnType<typeof createGitHubHttpClient>,
) {
  return client.execute(operation({
    kind: "TOKEN_EXCHANGE",
    installationId: INSTALLATION_ID,
    appJwt: APP_JWT,
    repositoryIds: [REPOSITORY_ID],
    permissions: { metadata: "read", administration: "write" },
  }));
}

function executeLabTokenExchange(
  client: ReturnType<typeof createGitHubHttpClient>,
) {
  return client.execute(operation({
    kind: "TOKEN_EXCHANGE",
    installationId: INSTALLATION_ID,
    appJwt: APP_JWT,
    repositoryIds: [],
    permissions: { metadata: "read", administration: "write" },
  }));
}

function tokenSubphase(error: unknown): string | undefined {
  return (error as { tokenAcquireSubphase?: string }).tokenAcquireSubphase;
}

function tokenResponseCheck(error: unknown): string | undefined {
  return (error as { tokenResponseCheck?: string }).tokenResponseCheck;
}

async function tokenSchemaError(response: unknown): Promise<GitHubHttpError> {
  const client = createGitHubHttpClient({
    now: () => NOW,
    fetch: () => Promise.resolve(json(response)),
  });
  const error = await assertRejects(
    () => executeTokenExchange(client),
    GitHubHttpError,
    "GITHUB_HTTP_RESPONSE_INVALID",
  );
  assertEquals(tokenSubphase(error), "TOKEN_RESPONSE_SCHEMA");
  return error;
}

function repositoryInstallationProof(): GitHubHttpOperation {
  return {
    kind: "REPOSITORY_INSTALLATION_PROOF",
    owner: "lorenzo-web-solutions-lab",
    repository: "lws-web-33a61b581d554624bdb73c724d35ebcc",
    expectedInstallationId: "161461160",
    expectedOrganization: "lorenzo-web-solutions-lab",
    appJwt: APP_JWT,
  };
}

Deno.test("GitHub HTTP project-file reads use authorized ref, non-recursive tree, and shared signal", async () => {
  const seen: Array<{ url: string; signal: AbortSignal | null | undefined }> =
    [];
  const signal = new AbortController().signal;
  const client = createGitHubHttpClient({
    fetch(input, init) {
      const url = String(input);
      seen.push({ url, signal: init?.signal });
      if (url.includes("/git/ref/")) {
        return Promise.resolve(json({
          ref: "refs/heads/release/approved",
          object: { type: "commit", sha: SHA },
        }));
      }
      return Promise.resolve(json({
        sha: TREE_SHA,
        truncated: false,
        tree: [{ path: "src", mode: "040000", type: "tree", sha: CONTENT_SHA }],
      }));
    },
  });

  const ref = await client.execute(
    operation({
      kind: "WEBSITE_PROJECT_FILES_READ_REF",
      owner: OWNER,
      repository: REPOSITORY,
      ref: "heads/release/approved",
      token: TOKEN,
    }),
    signal,
  );
  const tree = await client.execute(
    operation({
      kind: "WEBSITE_PROJECT_FILES_READ_TREE",
      owner: OWNER,
      repository: REPOSITORY,
      treeRef: TREE_SHA,
      token: TOKEN,
    }),
    signal,
  );

  assertEquals(ref, { ref: "refs/heads/release/approved", commitSha: SHA });
  assertEquals(tree, {
    sha: TREE_SHA,
    truncated: false,
    entries: [{ path: "src", mode: "040000", type: "tree", sha: CONTENT_SHA }],
  });
  assertEquals(seen.map((value) => value.url), [
    `${"https://api.github.com"}/repos/${OWNER}/${REPOSITORY}/git/ref/heads/release/approved`,
    `${"https://api.github.com"}/repos/${OWNER}/${REPOSITORY}/git/trees/${TREE_SHA}`,
  ]);
  assert(seen.every((value) => value.signal === signal));
});

Deno.test("GitHub HTTP project-file reads deny redirects without a second attempt", async () => {
  let attempts = 0;
  const client = createGitHubHttpClient({
    fetch() {
      attempts++;
      return Promise.resolve(
        new Response(null, {
          status: 302,
          headers: { location: "https://api.github.com/redirected" },
        }),
      );
    },
  });
  await assertRejects(
    () =>
      client.execute(
        operation({
          kind: "WEBSITE_PROJECT_FILES_REPOSITORY_METADATA",
          owner: OWNER,
          repository: REPOSITORY,
          token: TOKEN,
        }),
        new AbortController().signal,
      ),
    GitHubHttpError,
    "GITHUB_HTTP_REDIRECT_DENIED",
  );
  assertEquals(attempts, 1);
});

Deno.test("GitHub HTTP project-file ref read rejects ambiguous refs before fetch", async () => {
  let attempts = 0;
  const client = createGitHubHttpClient({
    fetch() {
      attempts++;
      return Promise.resolve(json({}));
    },
  });
  await assertRejects(
    () =>
      client.execute(
        operation({
          kind: "WEBSITE_PROJECT_FILES_READ_REF",
          owner: OWNER,
          repository: REPOSITORY,
          ref: "heads/../main",
          token: TOKEN,
        }),
        new AbortController().signal,
      ),
    GitHubHttpError,
    "GITHUB_HTTP_OPERATION_INVALID",
  );
  assertEquals(attempts, 0);
});

Deno.test("GitHub HTTP proves one exact repository installation with an App JWT", async () => {
  const requests: Request[] = [];
  const client = createGitHubHttpClient({
    fetch(input, init) {
      requests.push(new Request(input, init));
      return Promise.resolve(json({
        id: 161461160,
        account: {
          login: "lorenzo-web-solutions-lab",
          type: "Organization",
        },
        repository_selection: "selected",
        target_type: "Organization",
        suspended_at: null,
      }));
    },
  });

  const result = await client.execute(repositoryInstallationProof());

  assertEquals<unknown>(result, { proven: true });
  assertEquals(requests.length, 1);
  assertEquals(requests[0].method, "GET");
  assertEquals(requests[0].redirect, "error");
  assertEquals(
    requests[0].url,
    "https://api.github.com/repos/lorenzo-web-solutions-lab/lws-web-33a61b581d554624bdb73c724d35ebcc/installation",
  );
  assertEquals(requests[0].headers.get("authorization"), `Bearer ${APP_JWT}`);
});

Deno.test("GitHub HTTP repository-installation proof rejects every unproven response closed", async () => {
  const positive = {
    id: 161461160,
    account: {
      login: "lorenzo-web-solutions-lab",
      type: "Organization",
    },
    repository_selection: "selected",
    target_type: "Organization",
    suspended_at: null,
  };
  const invalidResponses = [
    null,
    { ...positive, id: "161461160" },
    { ...positive, id: 161461161 },
    { ...positive, account: { ...positive.account, login: "other" } },
    { ...positive, account: { ...positive.account, type: "User" } },
    { ...positive, repository_selection: "all" },
    { ...positive, target_type: "User" },
    { ...positive, suspended_at: "2026-09-13T12:00:00Z" },
    { ...positive, suspended_at: undefined },
  ];
  for (const body of invalidResponses) {
    const client = createGitHubHttpClient({
      fetch: () => Promise.resolve(json(body)),
    });
    const error = await assertRejects(
      () => client.execute(repositoryInstallationProof()),
      GitHubHttpError,
      "GITHUB_HTTP_RESPONSE_INVALID",
    );
    assertEquals(error.boundary, "RESPONSE_SCHEMA");
  }
});

Deno.test("GitHub HTTP repository-installation proof preserves bounded closed failures", async () => {
  const secret = "raw-response-token-jwt-private-key-stack-cause-details-hint";
  const cases = [
    {
      code: "GITHUB_HTTP_NOT_FOUND",
      boundary: "HTTP_STATUS",
      fetch: () => Promise.resolve(json({ raw: secret }, 404)),
    },
    {
      code: "GITHUB_HTTP_NETWORK_ERROR",
      boundary: "HTTP_REQUEST",
      fetch: () => Promise.reject(new Error(secret)),
    },
    {
      code: "GITHUB_HTTP_RESPONSE_INVALID",
      boundary: "CONTENT_TYPE",
      fetch: () => Promise.resolve(new Response(secret)),
    },
    {
      code: "GITHUB_HTTP_NETWORK_ERROR",
      boundary: "BODY_READ",
      fetch: () =>
        Promise.resolve(
          new Response(
            new ReadableStream({
              pull(controller) {
                controller.error(new Error(secret));
              },
            }),
            { headers: { "content-type": "application/json" } },
          ),
        ),
    },
    {
      code: "GITHUB_HTTP_RESPONSE_INVALID",
      boundary: "JSON_PARSE",
      fetch: () =>
        Promise.resolve(
          new Response(`{"${secret}":`, {
            headers: { "content-type": "application/json" },
          }),
        ),
    },
    {
      code: "GITHUB_HTTP_RESPONSE_TOO_LARGE",
      boundary: "BODY_READ",
      fetch: () =>
        Promise.resolve(
          new Response("{}", {
            headers: {
              "content-type": "application/json",
              "content-length": String(64 * 1024 + 1),
            },
          }),
        ),
    },
  ] as const;

  for (const scenario of cases) {
    const client = createGitHubHttpClient({ fetch: scenario.fetch });
    const error = await assertRejects(
      () => client.execute(repositoryInstallationProof()),
      GitHubHttpError,
    );
    assertEquals(error.code, scenario.code);
    assertEquals(error.boundary, scenario.boundary);
    assertEquals(JSON.stringify(error).includes(secret), false);
  }
});

Deno.test("GitHub HTTP client routes only the fixed provider operations and projects responses", async () => {
  const requests: Request[] = [];
  const client = createGitHubHttpClient({
    now: () => NOW,
    fetch(input, init) {
      const request = new Request(input, init);
      requests.push(request);
      const path = new URL(request.url).pathname;
      if (path.endsWith("/access_tokens")) {
        return Promise.resolve(json({
          token: TOKEN,
          expires_at: "2026-09-13T12:55:00.000Z",
          repository_selection: "selected",
          permissions: { metadata: "read", administration: "write" },
        }));
      }
      if (path.includes("/git/trees/")) {
        return Promise.resolve(json({
          sha: TREE_SHA,
          truncated: false,
          tree: [{
            path: "src/index.astro",
            mode: "100644",
            type: "blob",
            sha: CONTENT_SHA,
            size: 42,
          }],
        }));
      }
      if (
        path.endsWith("/contents/.lws/project.json") && request.method === "PUT"
      ) {
        return Promise.resolve(json({
          content: { sha: CONTENT_SHA },
          commit: { sha: SHA },
        }, 201));
      }
      if (path.endsWith("/contents/.lws/project.json")) {
        return Promise.resolve(json({
          path: ".lws/project.json",
          sha: CONTENT_SHA,
          encoding: "base64",
          content: "eyJzY2hlbWFfdmVyc2lvbiI6MX0=\n",
          size: 20,
        }));
      }
      if (path.includes("/commits/")) {
        return Promise.resolve(
          json({ sha: SHA, commit: { tree: { sha: TREE_SHA } } }),
        );
      }
      return Promise.resolve(json(repositoryResponse()));
    },
  });

  const tokenLease = await client.execute(operation({
    kind: "TOKEN_EXCHANGE",
    installationId: INSTALLATION_ID,
    appJwt: APP_JWT,
    repositoryIds: [REPOSITORY_ID],
    permissions: { metadata: "read", administration: "write" },
  }));
  assertEquals((tokenLease as { token?: string }).token, TOKEN);
  assertEquals<unknown>({ ...tokenLease }, {
    expiresAt: "2026-09-13T12:55:00.000Z",
    repositorySelection: "selected",
    permissions: { metadata: "read", administration: "write" },
  });
  assertEquals(Object.keys(tokenLease), [
    "expiresAt",
    "repositorySelection",
    "permissions",
  ]);

  const metadata = await client.execute(operation({
    kind: "REPOSITORY_METADATA",
    owner: OWNER,
    repository: REPOSITORY,
    token: TOKEN,
  }));
  assertEquals(metadata, {
    repositoryId: REPOSITORY_ID,
    nodeId: "R_test_node_1",
    owner: OWNER,
    name: REPOSITORY,
    fullName: `${OWNER}/${REPOSITORY}`,
    private: true,
    defaultBranch: "main",
    description: "Synthetic Task 13 test island",
    createdAt: "2026-09-13T12:00:00.000Z",
  });

  const tree = await client.execute(operation({
    kind: "REPOSITORY_TREE",
    owner: OWNER,
    repository: TEMPLATE,
    treeRef: SHA,
    token: TOKEN,
  }));
  assertEquals(tree, {
    sha: TREE_SHA,
    truncated: false,
    entries: [{
      path: "src/index.astro",
      mode: "100644",
      type: "blob",
      sha: CONTENT_SHA,
      size: 42,
    }],
  });

  await client.execute(operation({
    kind: "WRITE_PROJECT_MARKER",
    owner: OWNER,
    repository: REPOSITORY,
    message: "chore: bind project context",
    contentBase64: "eyJzY2hlbWFfdmVyc2lvbiI6MX0=",
    token: TOKEN,
  }));
  await client.execute(operation({
    kind: "READ_PROJECT_MARKER",
    owner: OWNER,
    repository: REPOSITORY,
    ref: SHA,
    token: TOKEN,
  }));
  await client.execute(operation({
    kind: "COMMIT_METADATA",
    owner: OWNER,
    repository: REPOSITORY,
    commitSha: SHA,
    token: TOKEN,
  }));

  assertEquals(
    requests.map((request) => [request.method, request.url]),
    [
      [
        "POST",
        `https://api.github.com/app/installations/${INSTALLATION_ID}/access_tokens`,
      ],
      ["GET", `https://api.github.com/repos/${OWNER}/${REPOSITORY}`],
      [
        "GET",
        `https://api.github.com/repos/${OWNER}/${TEMPLATE}/git/trees/${SHA}?recursive=1`,
      ],
      [
        "PUT",
        `https://api.github.com/repos/${OWNER}/${REPOSITORY}/contents/.lws/project.json`,
      ],
      [
        "GET",
        `https://api.github.com/repos/${OWNER}/${REPOSITORY}/contents/.lws/project.json?ref=${SHA}`,
      ],
      [
        "GET",
        `https://api.github.com/repos/${OWNER}/${REPOSITORY}/commits/${SHA}`,
      ],
    ],
  );
  assertEquals(await requests[0].json(), {
    repository_ids: [Number(REPOSITORY_ID)],
    permissions: { metadata: "read", administration: "write" },
  });
  assertEquals(await requests[3].json(), {
    message: "chore: bind project context",
    content: "eyJzY2hlbWFfdmVyc2lvbiI6MX0=",
  });
  assertEquals(
    requests.every((request) =>
      request.headers.get("accept") === "application/vnd.github+json" &&
      request.headers.get("x-github-api-version") === "2022-11-28"
    ),
    true,
  );
});

Deno.test("GitHub HTTP classifies token request preparation", async () => {
  const client = createGitHubHttpClient({
    fetch: () => Promise.resolve(json({})),
  });
  const error = await assertRejects(
    () =>
      client.execute({
        kind: "TOKEN_EXCHANGE",
        installationId: "invalid",
        appJwt: APP_JWT,
        repositoryIds: [REPOSITORY_ID],
        permissions: { metadata: "read", administration: "write" },
      }),
    GitHubHttpError,
    "GITHUB_HTTP_OPERATION_INVALID",
  );
  assertEquals(tokenSubphase(error), "TOKEN_REQUEST_PREPARE");
});

Deno.test("GitHub HTTP reads the exact main ref without mutation", async () => {
  const requests: Request[] = [];
  const client = createGitHubHttpClient({
    fetch: (input, init) => {
      requests.push(new Request(input, init));
      return Promise.resolve(json({
        ref: "refs/heads/main",
        object: { type: "commit", sha: SHA },
      }));
    },
  });

  const result = await client.execute({
    kind: "READ_REF",
    owner: OWNER,
    repository: REPOSITORY,
    ref: "heads/main",
    token: TOKEN,
  } as unknown as GitHubHttpOperation);

  assertEquals(result, { ref: "refs/heads/main", commitSha: SHA });
  assertEquals(requests.length, 1);
  assertEquals(requests[0].method, "GET");
  assertEquals(
    requests[0].url,
    `https://api.github.com/repos/${OWNER}/${REPOSITORY}/git/ref/heads/main`,
  );
  assertEquals(requests[0].redirect, "manual");
});

Deno.test("GitHub HTTP exposes only trusted valid REF_READ diagnostic pairs", async () => {
  type Diagnostic = Readonly<{ boundary: string; code: string }>;
  const implementation = await import("./github-http.ts") as unknown as {
    getValidatedGitHubHttpRefReadDiagnostic?: (value: unknown) => Diagnostic;
  };
  assert(
    typeof implementation.getValidatedGitHubHttpRefReadDiagnostic ===
      "function",
    "trusted REF_READ diagnostic accessor is missing",
  );
  const readRef = (fetchImpl: typeof fetch, timeoutMilliseconds = 1_000) =>
    createGitHubHttpClient({ fetch: fetchImpl, timeoutMilliseconds }).execute({
      kind: "READ_REF",
      owner: OWNER,
      repository: REPOSITORY,
      ref: "heads/main",
      token: TOKEN,
    });
  const scenarios = [
    [
      "forbidden",
      () => Promise.resolve(json({}, 403)),
      "HTTP_STATUS",
      "GITHUB_HTTP_FORBIDDEN",
    ],
    [
      "rate limit",
      () => Promise.resolve(json({}, 429)),
      "HTTP_STATUS",
      "GITHUB_HTTP_RATE_LIMITED",
    ],
    [
      "network",
      () => Promise.reject(new Error("raw network failure")),
      "HTTP_REQUEST",
      "GITHUB_HTTP_NETWORK_ERROR",
    ],
    [
      "content type",
      () => Promise.resolve(new Response("not json")),
      "CONTENT_TYPE",
      "GITHUB_HTTP_RESPONSE_INVALID",
    ],
    [
      "body read",
      () =>
        Promise.resolve(
          new Response(
            new ReadableStream({
              pull(controller) {
                controller.error(new Error("raw body failure"));
              },
            }),
            { headers: { "content-type": "application/json" } },
          ),
        ),
      "BODY_READ",
      "GITHUB_HTTP_NETWORK_ERROR",
    ],
    [
      "json parse",
      () =>
        Promise.resolve(
          new Response("{", {
            headers: { "content-type": "application/json" },
          }),
        ),
      "JSON_PARSE",
      "GITHUB_HTTP_RESPONSE_INVALID",
    ],
    [
      "schema",
      () => Promise.resolve(json({})),
      "RESPONSE_SCHEMA",
      "GITHUB_HTTP_RESPONSE_INVALID",
    ],
  ] as const;
  for (const [name, fetchImpl, boundary, code] of scenarios) {
    const error = await assertRejects(
      () => readRef(fetchImpl as typeof fetch),
      GitHubHttpError,
      undefined,
      name,
    );
    const diagnostic = implementation.getValidatedGitHubHttpRefReadDiagnostic(
      error,
    );
    assertEquals(diagnostic, { boundary, code }, name);
    assertEquals(Object.isFrozen(diagnostic), true, name);
  }

  const timeout = await assertRejects(
    () =>
      readRef(
        (_input, init) =>
          new Promise((_resolve, reject) =>
            init?.signal?.addEventListener("abort", () =>
              reject(new DOMException("raw timeout", "AbortError")))
          ),
        1,
      ),
    GitHubHttpError,
  );
  assertEquals(
    implementation.getValidatedGitHubHttpRefReadDiagnostic(timeout),
    { boundary: "HTTP_REQUEST", code: "GITHUB_HTTP_TIMEOUT" },
  );
  const timeoutDiagnostic = implementation
    .getValidatedGitHubHttpRefReadDiagnostic(timeout);
  assertThrows(
    () => Object.assign(timeoutDiagnostic, { boundary: "HTTP_STATUS" }),
    TypeError,
  );
  assertThrows(
    () =>
      Object.assign(timeout, {
        code: "GITHUB_HTTP_FORBIDDEN",
        boundary: "HTTP_STATUS",
      }),
    TypeError,
  );
  assertEquals(
    implementation.getValidatedGitHubHttpRefReadDiagnostic(timeout),
    { boundary: "HTTP_REQUEST", code: "GITHUB_HTTP_TIMEOUT" },
  );

  const invalidPair = new GitHubHttpError(
    "GITHUB_HTTP_NETWORK_ERROR",
    null,
    null,
    undefined,
    "HTTP_STATUS",
  );
  assertEquals(
    implementation.getValidatedGitHubHttpRefReadDiagnostic(invalidPair),
    { boundary: "UNKNOWN", code: "UNKNOWN" },
  );
  Object.assign(invalidPair, { code: "GITHUB_HTTP_FORBIDDEN" });
  assertEquals(
    implementation.getValidatedGitHubHttpRefReadDiagnostic(invalidPair),
    { boundary: "UNKNOWN", code: "UNKNOWN" },
  );

  let getterCalls = 0;
  const forged = Object.defineProperty({}, "boundary", {
    get() {
      getterCalls++;
      return "HTTP_STATUS";
    },
  });
  const proxy = new Proxy(forged, {
    get() {
      getterCalls++;
      throw new Error("proxy trap");
    },
  });
  assertEquals(
    implementation.getValidatedGitHubHttpRefReadDiagnostic(proxy),
    { boundary: "UNKNOWN", code: "UNKNOWN" },
  );
  assertEquals(getterCalls, 0);

  let prototypeTrapCalls = 0;
  const hostileThrowable = new Proxy({}, {
    getPrototypeOf() {
      prototypeTrapCalls++;
      throw new Error("raw prototype trap");
    },
  });
  const closed = await assertRejects(
    () => readRef(() => Promise.reject(hostileThrowable)),
    GitHubHttpError,
    "GITHUB_HTTP_NETWORK_ERROR",
  );
  assertEquals(
    implementation.getValidatedGitHubHttpRefReadDiagnostic(closed),
    { boundary: "HTTP_REQUEST", code: "GITHUB_HTTP_NETWORK_ERROR" },
  );
  assertEquals(prototypeTrapCalls, 0);
});

Deno.test("GitHub HTTP REF_READ diagnostic allowlist accepts every exact pair", async () => {
  const implementation = await import("./github-http.ts") as unknown as {
    getValidatedGitHubHttpRefReadDiagnostic?: (
      value: unknown,
    ) => Readonly<{ boundary: string; code: string }>;
  };
  assert(
    typeof implementation.getValidatedGitHubHttpRefReadDiagnostic ===
      "function",
  );
  assertEquals(GITHUB_REF_READ_DIAGNOSTIC_COMBINATIONS.length, 17);
  for (const [boundary, code] of GITHUB_REF_READ_DIAGNOSTIC_COMBINATIONS) {
    const diagnostic = createGitHubRefReadDiagnostic(boundary, code);
    assertEquals(diagnostic.boundary, boundary);
    assertEquals(diagnostic.code, code);
    assert(validateGitHubRefReadDiagnostic(diagnostic) === diagnostic);
    assert(Object.isFrozen(diagnostic));
    const error = new GitHubHttpError(
      code,
      null,
      null,
      undefined,
      boundary,
    );
    assertEquals(
      implementation.getValidatedGitHubHttpRefReadDiagnostic(error),
      { boundary, code },
    );
  }
});

Deno.test("GitHub HTTP REF_READ diagnostic factory rejects runtime types without hooks", () => {
  const createRuntimeDiagnostic = createGitHubRefReadDiagnostic as unknown as (
    boundary: unknown,
    code: unknown,
  ) => Readonly<{ boundary: string; code: string }>;
  const unknown = validateGitHubRefReadDiagnostic(undefined);
  const cases: ReadonlyArray<
    readonly [
      string,
      (label: string, state: { hooks: number }) => unknown,
    ]
  > = [
    ["undefined", () => undefined],
    ["null", () => null],
    ["boolean", () => false],
    ["number", () => 42],
    ["NaN", () => Number.NaN],
    ["bigint", () => 1n],
    ["symbol", () => Symbol("synthetic")],
    ["empty array", () => []],
    ["array containing valid label", (label) => [label]],
    ["boxed valid string", (label) => new String(label)],
    ["plain object", () => ({})],
    ["function", () => function testOnly() {}],
    ["coercible function", (label, state) => {
      const value = function testOnly() {};
      Object.defineProperty(value, Symbol.toPrimitive, {
        value: () => {
          state.hooks++;
          return label;
        },
      });
      return value;
    }],
    ["Symbol.toPrimitive object", (label, state) => ({
      [Symbol.toPrimitive]() {
        state.hooks++;
        return label;
      },
    })],
    ["toString object", (label, state) => ({
      toString() {
        state.hooks++;
        return label;
      },
    })],
    ["valueOf object", (_label, state) => ({
      valueOf() {
        state.hooks++;
        return 1;
      },
    })],
    ["throwing coercion", (_label, state) => ({
      [Symbol.toPrimitive]() {
        state.hooks++;
        throw new Error("synthetic coercion throw");
      },
    })],
    [
      "coercion getter",
      (_label, state) =>
        Object.defineProperty({}, Symbol.toPrimitive, {
          get() {
            state.hooks++;
            throw new Error("synthetic getter throw");
          },
        }),
    ],
    ["object with toJSON", (label, state) => ({
      [Symbol.toPrimitive]() {
        state.hooks++;
        return label;
      },
      toJSON() {
        state.hooks++;
        return "synthetic canary";
      },
    })],
    ["hostile proxy", (_label, state) =>
      new Proxy({}, {
        get() {
          state.hooks++;
          throw new Error("synthetic proxy get");
        },
        getPrototypeOf() {
          state.hooks++;
          throw new Error("synthetic proxy prototype");
        },
        ownKeys() {
          state.hooks++;
          throw new Error("synthetic proxy keys");
        },
      })],
    ["revoked object proxy", () => {
      const value = Proxy.revocable({}, {});
      value.revoke();
      return value.proxy;
    }],
    ["revoked function proxy", () => {
      const value = Proxy.revocable(function testOnly() {}, {});
      value.revoke();
      return value.proxy;
    }],
  ];

  const failures: string[] = [];
  for (
    const [parameter, label, counterpart] of [
      ["boundary", "HTTP_STATUS", "GITHUB_HTTP_FORBIDDEN"],
      ["code", "GITHUB_HTTP_FORBIDDEN", "HTTP_STATUS"],
    ] as const
  ) {
    for (const [name, createValue] of cases) {
      try {
        const state = { hooks: 0 };
        const value = createValue(label, state);
        const diagnostic = parameter === "boundary"
          ? createRuntimeDiagnostic(value, counterpart)
          : createRuntimeDiagnostic(counterpart, value);
        assert(diagnostic === unknown, `${parameter}/${name} was accepted`);
        assert(
          validateGitHubRefReadDiagnostic(diagnostic) === unknown,
          `${parameter}/${name} was trusted`,
        );
        assertEquals(state.hooks, 0, `${parameter}/${name} invoked a hook`);
        assertEquals(
          JSON.stringify(diagnostic),
          '{"boundary":"UNKNOWN","code":"UNKNOWN"}',
        );
        assertEquals(
          state.hooks,
          0,
          `${parameter}/${name} invoked a serialization hook`,
        );
        assert(Object.isFrozen(diagnostic));
        assertEquals(Reflect.ownKeys(diagnostic), ["boundary", "code"]);
      } catch (error) {
        failures.push(`${parameter}/${name}: ${String(error)}`);
      }
    }
  }
  assertEquals(failures, []);

  for (
    const [boundary, code] of [
      ["", "GITHUB_HTTP_FORBIDDEN"],
      ["HTTP_STATUS", ""],
      ["HTTP_STATUS", "not-a-code"],
      ["not-a-boundary", "GITHUB_HTTP_FORBIDDEN"],
      ["UNKNOWN", "UNKNOWN"],
    ]
  ) {
    assert(createGitHubRefReadDiagnostic(boundary, code) === unknown);
  }
});

Deno.test("GitHub HTTP REF_READ diagnostic allowlist is deeply immutable", () => {
  assert(Object.isFrozen(GITHUB_REF_READ_DIAGNOSTIC_COMBINATIONS));
  for (const combination of GITHUB_REF_READ_DIAGNOSTIC_COMBINATIONS) {
    assert(Object.isFrozen(combination));
    assertThrows(() => {
      (combination as unknown as string[])[0] = "UNKNOWN";
    });
  }
});

async function executeRefFixture(fixture: unknown) {
  let fetchCalls = 0;
  const client = createGitHubHttpClient({
    fetch: () => {
      fetchCalls++;
      return Promise.resolve(json(fixture));
    },
  });
  const result = await client.execute({
    kind: "READ_REF",
    owner: OWNER,
    repository: REPOSITORY,
    ref: "heads/main",
    token: TOKEN,
  });
  return { result, fetchCalls };
}

const refFixture = () => ({
  ref: "refs/heads/main",
  object: { type: "commit", sha: SHA },
});

for (
  const [name, fixture] of [
    ["top-level node_id", {
      ...refFixture(),
      node_id: "REF_kwDOSyntheticMain",
    }],
    ["top-level url", {
      ...refFixture(),
      url: "https://api.github.com/repos/example/example/git/refs/heads/main",
    }],
    ["object url", {
      ...refFixture(),
      object: {
        ...refFixture().object,
        url:
          "https://api.github.com/repos/example/example/git/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      },
    }],
    [
      "all documented metadata",
      JSON.parse(JSON.stringify({
        ...refFixture(),
        node_id: "REF_kwDOSyntheticMain",
        url: "https://api.github.com/repos/example/example/git/refs/heads/main",
        object: {
          ...refFixture().object,
          url:
            "https://api.github.com/repos/example/example/git/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        },
        installation_id: "not-authority",
        repository_id: "not-authority",
        ["__proto__"]: { polluted: true },
        constructor: { authority: true },
        prototype: { authority: true },
      })),
    ],
  ] as const
) {
  Deno.test(`GitHub HTTP READ_REF ignores unused ${name}`, async () => {
    const { result, fetchCalls } = await executeRefFixture(fixture);
    assertEquals(result, { ref: "refs/heads/main", commitSha: SHA });
    assertEquals(Reflect.ownKeys(result).sort(), ["commitSha", "ref"]);
    assertEquals(Object.getPrototypeOf(result), Object.prototype);
    assertEquals(Object.isFrozen(result), true);
    assertEquals(fetchCalls, 1);
    assertEquals("polluted" in result, false);
  });
}

Deno.test("GitHub HTTP READ_REF rejects malformed required fields with the existing diagnostic", async () => {
  for (
    const fixture of [
      null,
      [],
      {},
      { object: { type: "commit", sha: SHA } },
      { ...refFixture(), ref: "refs/heads/other" },
      { ...refFixture(), ref: undefined },
      { ...refFixture(), object: null },
      { ...refFixture(), object: { sha: SHA } },
      { ...refFixture(), object: { type: "tag", sha: SHA } },
      { ...refFixture(), object: { type: "commit" } },
      { ...refFixture(), object: { type: "commit", sha: 42 } },
      { ...refFixture(), object: { type: "commit", sha: "not-a-sha" } },
      {
        node_id: "REF_kwDOSyntheticMain",
        url: "https://api.github.com/repos/example/example/git/refs/heads/main",
        object: { type: "commit", sha: SHA },
      },
      {
        ref: "refs/heads/other",
        object: {
          type: "commit",
          sha: SHA,
          url:
            "https://api.github.com/repos/example/example/git/commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        },
      },
    ]
  ) {
    const error = await assertRejects(
      () => executeRefFixture(fixture),
      GitHubHttpError,
      "GITHUB_HTTP_RESPONSE_INVALID",
    );
    assertEquals(error.boundary, "RESPONSE_SCHEMA");
  }
});

Deno.test("GitHub HTTP classifies token network requests", async () => {
  const client = createGitHubHttpClient({
    fetch: () => Promise.reject(new Error("synthetic network failure")),
  });
  const error = await assertRejects(
    () => executeTokenExchange(client),
    GitHubHttpError,
    "GITHUB_HTTP_NETWORK_ERROR",
  );
  assertEquals(tokenSubphase(error), "TOKEN_HTTP_REQUEST");
});

Deno.test("GitHub HTTP classifies token HTTP status", async () => {
  const client = createGitHubHttpClient({
    fetch: () => Promise.resolve(json({}, 401)),
  });
  const error = await assertRejects(
    () => executeTokenExchange(client),
    GitHubHttpError,
    "GITHUB_HTTP_UNAUTHORIZED",
  );
  assertEquals(tokenSubphase(error), "TOKEN_HTTP_STATUS");
});

Deno.test("GitHub HTTP classifies token content type validation", async () => {
  const client = createGitHubHttpClient({
    fetch: () =>
      Promise.resolve(
        new Response("{}", {
          headers: { "content-type": "text/plain" },
        }),
      ),
  });
  const error = await assertRejects(
    () => executeTokenExchange(client),
    GitHubHttpError,
    "GITHUB_HTTP_RESPONSE_INVALID",
  );
  assertEquals(tokenSubphase(error), "TOKEN_CONTENT_TYPE_VALIDATE");
});

Deno.test("GitHub HTTP classifies token response body reads", async () => {
  const client = createGitHubHttpClient({
    fetch: () =>
      Promise.resolve(
        new Response("{}", {
          headers: {
            "content-type": "application/json",
            "content-length": "1000000",
          },
        }),
      ),
  });
  const error = await assertRejects(
    () => executeTokenExchange(client),
    GitHubHttpError,
    "GITHUB_HTTP_RESPONSE_TOO_LARGE",
  );
  assertEquals(tokenSubphase(error), "TOKEN_RESPONSE_BODY_READ");
});

Deno.test("GitHub HTTP keeps token stream failures at the body-read boundary", async () => {
  const client = createGitHubHttpClient({
    fetch: () =>
      Promise.resolve(
        new Response(
          new ReadableStream({
            pull(controller) {
              controller.error(new Error("synthetic stream failure"));
            },
          }),
          {
            headers: { "content-type": "application/json" },
          },
        ),
      ),
  });
  const error = await assertRejects(
    () => executeTokenExchange(client),
    GitHubHttpError,
    "GITHUB_HTTP_NETWORK_ERROR",
  );
  assertEquals(tokenSubphase(error), "TOKEN_RESPONSE_BODY_READ");
});

Deno.test("GitHub HTTP classifies token JSON parsing", async () => {
  const client = createGitHubHttpClient({
    fetch: () =>
      Promise.resolve(
        new Response("{", {
          headers: { "content-type": "application/json" },
        }),
      ),
  });
  const error = await assertRejects(
    () => executeTokenExchange(client),
    GitHubHttpError,
    "GITHUB_HTTP_RESPONSE_INVALID",
  );
  assertEquals(tokenSubphase(error), "TOKEN_JSON_PARSE");
});

Deno.test("GitHub HTTP classifies token response schema", async () => {
  const client = createGitHubHttpClient({
    now: () => NOW,
    fetch: () => Promise.resolve(json({})),
  });
  const error = await assertRejects(
    () => executeTokenExchange(client),
    GitHubHttpError,
    "GITHUB_HTTP_RESPONSE_INVALID",
  );
  assertEquals(tokenSubphase(error), "TOKEN_RESPONSE_SCHEMA");
});

Deno.test("GitHub HTTP accepts absent token repository-selection metadata", async () => {
  const client = createGitHubHttpClient({
    now: () => NOW,
    fetch: () =>
      Promise.resolve(json({
        token: TOKEN,
        expires_at: "2026-09-13T12:55:00.000Z",
        permissions: { metadata: "read", administration: "write" },
      })),
  });

  const result = await executeLabTokenExchange(client);

  assertEquals("repositorySelection" in result, false);
});

Deno.test("GitHub HTTP accepts all token repository-selection metadata", async () => {
  const client = createGitHubHttpClient({
    now: () => NOW,
    fetch: () =>
      Promise.resolve(json(tokenResponse({
        repository_selection: "all",
      }))),
  });

  const result = await executeLabTokenExchange(client);

  assertEquals(
    (result as { repositorySelection?: unknown }).repositorySelection,
    "all",
  );
});

Deno.test("GitHub HTTP keeps selected token repository-selection metadata", async () => {
  const client = createGitHubHttpClient({
    now: () => NOW,
    fetch: () => Promise.resolve(json(tokenResponse())),
  });

  const result = await executeLabTokenExchange(client);

  assertEquals(
    "repositorySelection" in result && result.repositorySelection,
    "selected",
  );
});

Deno.test("GitHub HTTP rejects malformed present token repository-selection metadata", async () => {
  for (const repositorySelection of [null, 7, {}, [], "invalid-value"]) {
    const error = await tokenSchemaError(tokenResponse({
      repository_selection: repositorySelection,
    }));
    assertEquals(
      tokenResponseCheck(error),
      "TOKEN_SCHEMA_REPOSITORY_SELECTION",
    );
  }
});

Deno.test("GitHub HTTP classifies token permission-shape response checks", async () => {
  const error = await tokenSchemaError(tokenResponse({ permissions: null }));
  assertEquals(tokenResponseCheck(error), "TOKEN_SCHEMA_PERMISSIONS_SHAPE");
});

Deno.test("GitHub HTTP classifies token permission-parity response checks", async () => {
  const error = await tokenSchemaError(tokenResponse({
    permissions: { metadata: "read", contents: "read" },
  }));
  assertEquals(tokenResponseCheck(error), "TOKEN_SCHEMA_PERMISSION_PARITY");
});

Deno.test("GitHub HTTP classifies token-value response checks", async () => {
  const error = await tokenSchemaError(tokenResponse({
    token: "synthetic-malformed-token",
  }));
  assertEquals(tokenResponseCheck(error), "TOKEN_SCHEMA_TOKEN");
});

Deno.test("GitHub HTTP classifies token expiry response checks", async () => {
  const error = await tokenSchemaError(tokenResponse({
    expires_at: "synthetic-malformed-expiry",
  }));
  assertEquals(tokenResponseCheck(error), "TOKEN_SCHEMA_EXPIRY");
});

Deno.test("GitHub HTTP classifies token object response checks", async () => {
  const error = await tokenSchemaError([]);
  assertEquals(tokenResponseCheck(error), "TOKEN_SCHEMA_OBJECT");
});

Deno.test("GitHub HTTP client accepts realistic GitHub JSON content types", async () => {
  for (
    const contentType of [
      "application/json",
      "application/json; charset=utf-8",
      "application/json; charset=UTF-8",
      "application/json ; charset=utf-8",
    ]
  ) {
    const client = createGitHubHttpClient({
      now: () => NOW,
      fetch: () =>
        Promise.resolve(json(tokenResponse(), 200, {
          "content-type": contentType,
        })),
    });

    const lease = await client.execute(operation({
      kind: "TOKEN_EXCHANGE",
      installationId: INSTALLATION_ID,
      appJwt: APP_JWT,
      repositoryIds: [REPOSITORY_ID],
      permissions: { metadata: "read", administration: "write" },
    }));

    assertEquals("expiresAt" in lease, true);
  }

  const missingContentType = createGitHubHttpClient({
    now: () => NOW,
    fetch: () =>
      Promise.resolve(
        new Response(new TextEncoder().encode(JSON.stringify(tokenResponse()))),
      ),
  });
  await assertRejects(
    () =>
      missingContentType.execute(operation({
        kind: "TOKEN_EXCHANGE",
        installationId: INSTALLATION_ID,
        appJwt: APP_JWT,
        repositoryIds: [REPOSITORY_ID],
        permissions: { metadata: "read", administration: "write" },
      })),
    GitHubHttpError,
    "GITHUB_HTTP_RESPONSE_INVALID",
  );
});

Deno.test("GitHub HTTP proves emptiness only from exact GraphQL repository identity", async () => {
  const requests: Request[] = [];
  const client = createGitHubHttpClient({
    fetch(input, init) {
      requests.push(new Request(input, init));
      return Promise.resolve(json({
        data: {
          repository: {
            databaseId: Number(REPOSITORY_ID),
            nameWithOwner: `${OWNER}/${REPOSITORY}`,
            isEmpty: true,
            defaultBranchRef: null,
          },
        },
      }));
    },
  });
  const result = await client.execute(operation({
    kind: "REPOSITORY_EMPTY_PROOF",
    owner: OWNER,
    repository: REPOSITORY,
    expectedRepositoryId: REPOSITORY_ID,
    token: TOKEN,
  }));
  assertEquals(result, { empty: true });
  assertEquals(requests.length, 1);
  assertEquals(requests[0].url, "https://api.github.com/graphql");
  assertEquals(requests[0].method, "POST");
  assertEquals(await requests[0].json(), {
    query:
      "query RepositoryEmptyProof($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { databaseId nameWithOwner isEmpty defaultBranchRef { name } } }",
    variables: { owner: OWNER, name: REPOSITORY },
  });
});

Deno.test("GitHub HTTP rejects every incomplete or contradictory empty proof", async () => {
  const valid = {
    data: {
      repository: {
        databaseId: Number(REPOSITORY_ID),
        nameWithOwner: `${OWNER}/${REPOSITORY}`,
        isEmpty: true,
        defaultBranchRef: null,
      },
    },
  };
  for (
    const body of [
      null,
      {},
      { ...valid, errors: [{ type: "FORBIDDEN" }] },
      { data: { repository: null } },
      { data: { repository: { ...valid.data.repository, databaseId: 1 } } },
      {
        data: {
          repository: {
            ...valid.data.repository,
            nameWithOwner: `attacker/${REPOSITORY}`,
          },
        },
      },
      { data: { repository: { ...valid.data.repository, isEmpty: false } } },
      {
        data: {
          repository: {
            ...valid.data.repository,
            defaultBranchRef: { name: "main" },
          },
        },
      },
    ]
  ) {
    const client = createGitHubHttpClient({
      fetch: () => Promise.resolve(json(body)),
    });
    await assertRejects(
      () =>
        client.execute(operation({
          kind: "REPOSITORY_EMPTY_PROOF",
          owner: OWNER,
          repository: REPOSITORY,
          expectedRepositoryId: REPOSITORY_ID,
          token: TOKEN,
        })),
      GitHubHttpError,
      "GITHUB_HTTP_RESPONSE_INVALID",
    );
  }
});

Deno.test("GitHub HTTP bootstrap Contents operations are create-only and strictly projected", async () => {
  const requests: Request[] = [];
  const responses = [
    json({
      content: { path: ".lws/bootstrap.json", sha: CONTENT_SHA },
      commit: { sha: SHA, parents: [] },
    }, 201),
    json({
      path: ".lws/bootstrap.json",
      sha: CONTENT_SHA,
      encoding: "base64",
      content: btoa("bootstrap\n"),
      size: 10,
    }),
  ];
  const client = createGitHubHttpClient({
    fetch(input, init) {
      requests.push(new Request(input, init));
      return Promise.resolve(responses.shift()!);
    },
  });
  assertEquals(
    await client.execute(operation({
      kind: "CREATE_BOOTSTRAP_FILE",
      owner: OWNER,
      repository: REPOSITORY,
      contentBase64: btoa("bootstrap\n"),
      branch: "main",
      token: TOKEN,
    })),
    {
      path: ".lws/bootstrap.json",
      contentSha: CONTENT_SHA,
      commitSha: SHA,
      parentCount: 0,
    },
  );
  const bootstrapBody = await requests[0].json();
  assertEquals(bootstrapBody, {
    message: "chore: initialize recovery bootstrap",
    content: btoa("bootstrap\n"),
    branch: "main",
  });
  assertEquals("sha" in bootstrapBody, false);
  assertEquals(
    await client.execute(operation({
      kind: "READ_BOOTSTRAP_FILE",
      owner: OWNER,
      repository: REPOSITORY,
      ref: "main",
      token: TOKEN,
    })),
    {
      path: ".lws/bootstrap.json",
      sha: CONTENT_SHA,
      encoding: "base64",
      contentBase64: btoa("bootstrap\n"),
      size: 10,
    },
  );
  assertEquals(
    requests.map((request) => [request.method, request.url]),
    [
      [
        "PUT",
        `https://api.github.com/repos/${OWNER}/${REPOSITORY}/contents/.lws/bootstrap.json`,
      ],
      [
        "GET",
        `https://api.github.com/repos/${OWNER}/${REPOSITORY}/contents/.lws/bootstrap.json?ref=main`,
      ],
    ],
  );
});

Deno.test("GitHub HTTP projects immutable bootstrap commit ancestry", async () => {
  const requests: Request[] = [];
  const client = createGitHubHttpClient({
    fetch(input, init) {
      requests.push(new Request(input, init));
      return Promise.resolve(json({
        sha: SHA,
        tree: { sha: TREE_SHA },
        parents: [],
      }));
    },
  });
  assertEquals(
    await client.execute(operation({
      kind: "READ_BOOTSTRAP_COMMIT",
      owner: OWNER,
      repository: REPOSITORY,
      commitSha: SHA,
      token: TOKEN,
    })),
    { sha: SHA, treeSha: TREE_SHA, parentCount: 0 },
  );
  assertEquals(requests[0].method, "GET");
  assertEquals(
    requests[0].url,
    `https://api.github.com/repos/${OWNER}/${REPOSITORY}/git/commits/${SHA}`,
  );

  for (
    const body of [{ sha: SHA, tree: { sha: TREE_SHA } }, {
      sha: SHA,
      tree: { sha: TREE_SHA },
      parents: null,
    }]
  ) {
    const malformed = createGitHubHttpClient({
      fetch: () => Promise.resolve(json(body)),
    });
    await assertRejects(
      () =>
        malformed.execute(operation({
          kind: "READ_BOOTSTRAP_COMMIT",
          owner: OWNER,
          repository: REPOSITORY,
          commitSha: SHA,
          token: TOKEN,
        })),
      GitHubHttpError,
      "GITHUB_HTTP_RESPONSE_INVALID",
    );
  }
});

Deno.test("GitHub HTTP canonical commit is parented and ref publication is non-force", async () => {
  const requests: Request[] = [];
  const client = createGitHubHttpClient({
    fetch(input, init) {
      const request = new Request(input, init);
      requests.push(request);
      return Promise.resolve(
        request.method === "POST"
          ? json({ sha: SHA }, 201)
          : json({ ref: "refs/heads/main", object: { sha: SHA } }),
      );
    },
  });
  await client.execute(operation({
    kind: "CREATE_COMMIT",
    owner: OWNER,
    repository: REPOSITORY,
    message: "chore: initialize approved starter snapshot",
    treeSha: TREE_SHA,
    parentSha: CONTENT_SHA,
    token: TOKEN,
  }));
  await client.execute(operation({
    kind: "UPDATE_REF",
    owner: OWNER,
    repository: REPOSITORY,
    commitSha: SHA,
    force: false,
    token: TOKEN,
  }));
  assertEquals(await requests[0].json(), {
    message: "chore: initialize approved starter snapshot",
    tree: TREE_SHA,
    parents: [CONTENT_SHA],
  });
  assertEquals(requests[1].method, "PATCH");
  assertEquals(await requests[1].json(), { sha: SHA, force: false });
});

Deno.test("GitHub HTTP client supports only the explicit snapshot read-then-write primitives", async () => {
  const requests: Request[] = [];
  const client = createGitHubHttpClient({
    now: () => NOW,
    fetch(input, init) {
      const request = new Request(input, init);
      requests.push(request);
      const path = new URL(request.url).pathname;
      if (path.endsWith("/access_tokens")) {
        return Promise.resolve(json({
          token: TOKEN,
          expires_at: "2026-09-13T12:55:00.000Z",
          repository_selection: "selected",
          permissions: { metadata: "read", administration: "write" },
        }, 201));
      }
      if (path === `/orgs/${OWNER}/repos`) {
        return Promise.resolve(json(repositoryResponse(), 201));
      }
      if (path.includes("/git/blobs/") && request.method === "GET") {
        return Promise.resolve(json({
          sha: CONTENT_SHA,
          encoding: "base64",
          content: "c3RhcnRlcgo=\n",
          size: 8,
        }));
      }
      if (path.endsWith("/git/blobs")) {
        return Promise.resolve(json({ sha: CONTENT_SHA }, 201));
      }
      if (path.endsWith("/git/trees")) {
        return Promise.resolve(json({ sha: TREE_SHA }, 201));
      }
      if (path.endsWith("/git/commits")) {
        return Promise.resolve(json({ sha: SHA }, 201));
      }
      if (path.endsWith("/git/refs")) {
        return Promise.resolve(
          json({ ref: "refs/heads/main", object: { sha: SHA } }, 201),
        );
      }
      return Promise.resolve(json({}));
    },
  });

  await client.execute(operation({
    kind: "TOKEN_EXCHANGE",
    installationId: INSTALLATION_ID,
    appJwt: APP_JWT,
    repositoryIds: [],
    permissions: { metadata: "read", administration: "write" },
  }));
  assertEquals(await requests[0].json(), {
    permissions: { metadata: "read", administration: "write" },
  });

  assertEquals(
    await client.execute(operation({
      kind: "READ_BLOB",
      owner: "lorenzo-web-solutions",
      repository: TEMPLATE,
      blobSha: CONTENT_SHA,
      token: TOKEN,
    })),
    {
      sha: CONTENT_SHA,
      encoding: "base64",
      contentBase64: "c3RhcnRlcgo=",
      size: 8,
    },
  );
  await client.execute(operation({
    kind: "CREATE_REPOSITORY",
    owner: OWNER,
    repository: REPOSITORY,
    description: "Synthetic Task 13 test island",
    token: TOKEN,
  }));
  await client.execute(operation({
    kind: "CREATE_BLOB",
    owner: OWNER,
    repository: REPOSITORY,
    contentBase64: "c3RhcnRlcgo=",
    token: TOKEN,
  }));
  await client.execute(operation({
    kind: "CREATE_TREE",
    owner: OWNER,
    repository: REPOSITORY,
    entries: [{
      path: "README.md",
      mode: "100644",
      type: "blob",
      sha: CONTENT_SHA,
    }],
    token: TOKEN,
  }));
  await client.execute(operation({
    kind: "CREATE_COMMIT",
    owner: OWNER,
    repository: REPOSITORY,
    message: "chore: initialize approved starter snapshot",
    treeSha: TREE_SHA,
    token: TOKEN,
  }));
  await client.execute(operation({
    kind: "CREATE_REF",
    owner: OWNER,
    repository: REPOSITORY,
    commitSha: SHA,
    token: TOKEN,
  }));

  assertEquals(
    requests.map((request) => [request.method, new URL(request.url).pathname]),
    [
      ["POST", `/app/installations/${INSTALLATION_ID}/access_tokens`],
      [
        "GET",
        `/repos/lorenzo-web-solutions/${TEMPLATE}/git/blobs/${CONTENT_SHA}`,
      ],
      ["POST", `/orgs/${OWNER}/repos`],
      ["POST", `/repos/${OWNER}/${REPOSITORY}/git/blobs`],
      ["POST", `/repos/${OWNER}/${REPOSITORY}/git/trees`],
      ["POST", `/repos/${OWNER}/${REPOSITORY}/git/commits`],
      ["POST", `/repos/${OWNER}/${REPOSITORY}/git/refs`],
    ],
  );
});

Deno.test("GitHub HTTP client rejects caller routing and destructive capabilities before fetch", async () => {
  let requests = 0;
  const client = createGitHubHttpClient({
    fetch() {
      requests++;
      return Promise.resolve(json({}));
    },
  });
  const invalid = [
    {
      ...operation({
        kind: "REPOSITORY_METADATA",
        owner: OWNER,
        repository: REPOSITORY,
        token: TOKEN,
      }),
      url: "https://attacker.invalid",
    },
    {
      ...operation({
        kind: "REPOSITORY_METADATA",
        owner: OWNER,
        repository: REPOSITORY,
        token: TOKEN,
      }),
      method: "DELETE",
    },
    {
      ...operation({
        kind: "READ_PROJECT_MARKER",
        owner: OWNER,
        repository: REPOSITORY,
        ref: SHA,
        token: TOKEN,
      }),
      path: ".github/workflows/deploy.yml",
    },
    {
      kind: "DELETE_REPOSITORY",
      owner: OWNER,
      repository: REPOSITORY,
      token: TOKEN,
    },
    {
      kind: "TRANSFER_REPOSITORY",
      owner: OWNER,
      repository: REPOSITORY,
      token: TOKEN,
    },
    {
      kind: "ARCHIVE_REPOSITORY",
      owner: OWNER,
      repository: REPOSITORY,
      token: TOKEN,
    },
    {
      kind: "CHANGE_VISIBILITY",
      owner: OWNER,
      repository: REPOSITORY,
      token: TOKEN,
    },
    {
      kind: "WRITE_CONTENT",
      owner: OWNER,
      repository: REPOSITORY,
      path: "README.md",
      token: TOKEN,
    },
    {
      kind: "GENERATE_REPOSITORY",
      templateOwner: "lorenzo-web-solutions",
      templateRepository: TEMPLATE,
      owner: OWNER,
      repository: REPOSITORY,
      token: TOKEN,
    },
    operation({
      kind: "TOKEN_EXCHANGE",
      installationId: INSTALLATION_ID,
      appJwt: APP_JWT,
      repositoryIds: ["9999999999999999"],
      permissions: { metadata: "read", administration: "write" },
    }),
    operation({
      kind: "REPOSITORY_METADATA",
      owner: OWNER,
      repository: "..",
      token: TOKEN,
    }),
  ];
  for (const descriptor of invalid) {
    await assertRejects(
      () => client.execute(descriptor as unknown as GitHubHttpOperation),
      GitHubHttpError,
      "GITHUB_HTTP_OPERATION_INVALID",
    );
  }
  assertEquals(requests, 0);
});

Deno.test("GitHub HTTP client permits one allowlisted HTTPS redirect and denies all other redirects", async () => {
  const allowedCalls: string[] = [];
  const authorization: Array<string | null> = [];
  const allowed = createGitHubHttpClient({
    fetch(input, init) {
      const request = new Request(input, init);
      const url = request.url;
      allowedCalls.push(url);
      authorization.push(request.headers.get("authorization"));
      return Promise.resolve(
        allowedCalls.length === 1
          ? new Response(null, {
            status: 307,
            headers: { location: `https://github.com/${OWNER}/${REPOSITORY}` },
          })
          : json(repositoryResponse()),
      );
    },
  });
  await allowed.execute(operation({
    kind: "REPOSITORY_METADATA",
    owner: OWNER,
    repository: REPOSITORY,
    token: TOKEN,
  }));
  assertEquals(allowedCalls, [
    `https://api.github.com/repos/${OWNER}/${REPOSITORY}`,
    `https://github.com/${OWNER}/${REPOSITORY}`,
  ]);
  assertEquals(authorization, [`Bearer ${TOKEN}`, null]);

  for (
    const location of [
      "http://api.github.com/repos/x/y",
      "https://api.github.com.attacker.invalid/repos/x/y",
      "https://github.com:444/repos/x/y",
      "https://example.test/repos/x/y",
      "/second-redirect",
    ]
  ) {
    let calls = 0;
    const client = createGitHubHttpClient({
      fetch() {
        calls++;
        return Promise.resolve(
          new Response(null, {
            status: 302,
            headers: { location },
          }),
        );
      },
    });
    await assertRejects(
      () =>
        client.execute(operation({
          kind: "REPOSITORY_METADATA",
          owner: OWNER,
          repository: REPOSITORY,
          token: TOKEN,
        })),
      GitHubHttpError,
      "GITHUB_HTTP_REDIRECT_DENIED",
    );
    assertEquals(calls, 1);
  }
});

Deno.test("GitHub HTTP accepts a 520-plus stateless installation token", async () => {
  const token = `ghs_4932372_${"a".repeat(170)}.${"b".repeat(170)}.${
    "c".repeat(170)
  }`;
  const client = createGitHubHttpClient({
    now: () => NOW,
    fetch: () => Promise.resolve(json(tokenResponse({ token }))),
  });

  const result = await client.execute(operation({
    kind: "TOKEN_EXCHANGE",
    installationId: INSTALLATION_ID,
    appJwt: APP_JWT,
    repositoryIds: [REPOSITORY_ID],
    permissions: { metadata: "read", administration: "write" },
  }));

  assertEquals((result as { token?: string }).token, token);
});

Deno.test("GitHub HTTP client enforces media type, response ceilings and response schemas", async () => {
  const malformed = [
    new Response("not json", {
      status: 200,
      headers: { "content-type": "text/plain" },
    }),
    new Response("{", {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
    json({ id: Number(REPOSITORY_ID), private: true }),
  ];
  for (const response of malformed) {
    const client = createGitHubHttpClient({
      fetch: () => Promise.resolve(response),
    });
    await assertRejects(
      () =>
        client.execute(operation({
          kind: "REPOSITORY_METADATA",
          owner: OWNER,
          repository: REPOSITORY,
          token: TOKEN,
        })),
      GitHubHttpError,
      "GITHUB_HTTP_RESPONSE_INVALID",
    );
  }

  const declaredOversized = createGitHubHttpClient({
    fetch: () =>
      Promise.resolve(
        new Response(JSON.stringify(repositoryResponse()), {
          status: 200,
          headers: {
            "content-type": "application/json",
            "content-length": String(300_000),
          },
        }),
      ),
  });
  await assertRejects(
    () =>
      declaredOversized.execute(operation({
        kind: "REPOSITORY_METADATA",
        owner: OWNER,
        repository: REPOSITORY,
        token: TOKEN,
      })),
    GitHubHttpError,
    "GITHUB_HTTP_RESPONSE_TOO_LARGE",
  );

  const oversizedTree = json({
    sha: TREE_SHA,
    truncated: false,
    tree: [{
      path: "x".repeat(8_400_000),
      mode: "100644",
      type: "blob",
      sha: SHA,
    }],
  });
  const treeClient = createGitHubHttpClient({
    fetch: () => Promise.resolve(oversizedTree),
  });
  await assertRejects(
    () =>
      treeClient.execute(operation({
        kind: "REPOSITORY_TREE",
        owner: OWNER,
        repository: TEMPLATE,
        treeRef: SHA,
        token: TOKEN,
      })),
    GitHubHttpError,
    "GITHUB_HTTP_RESPONSE_TOO_LARGE",
  );

  for (
    const response of [
      {
        expires_at: "2026-09-13T12:55:00.000Z",
        repository_selection: "selected",
        permissions: { metadata: "read", administration: "write" },
      },
      {
        token: TOKEN,
        repository_selection: "selected",
        permissions: { metadata: "read", administration: "write" },
      },
      {
        token: TOKEN,
        expires_at: "not-an-iso-timestamp",
        repository_selection: "selected",
        permissions: { metadata: "read", administration: "write" },
      },
      {
        token: TOKEN,
        expires_at: "2026-09-13T12:00:00.000Z",
        repository_selection: "selected",
        permissions: { metadata: "read", administration: "write" },
      },
      {
        token: TOKEN,
        expires_at: "2026-09-13T12:55:00.000Z",
        repository_selection: "selected",
        permissions: { metadata: "read", contents: "write" },
      },
      {
        token: TOKEN,
        expires_at: "2026-09-13T11:59:59.000Z",
        repository_selection: "selected",
        permissions: { metadata: "read", administration: "write" },
      },
      {
        token: TOKEN,
        expires_at: "2026-09-13T13:01:00.001Z",
        repository_selection: "selected",
        permissions: { metadata: "read", administration: "write" },
      },
    ]
  ) {
    const invalidToken = createGitHubHttpClient({
      now: () => NOW,
      fetch: () => Promise.resolve(json(response)),
    });
    await assertRejects(
      () =>
        invalidToken.execute(operation({
          kind: "TOKEN_EXCHANGE",
          installationId: INSTALLATION_ID,
          appJwt: APP_JWT,
          repositoryIds: [REPOSITORY_ID],
          permissions: { metadata: "read", administration: "write" },
        })),
      GitHubHttpError,
      "GITHUB_HTTP_RESPONSE_INVALID",
    );
  }

  for (
    const expiresAt of [
      "2026-09-13T13:00:00.000Z",
      "2026-09-13T13:01:00.000Z",
    ]
  ) {
    const boundaryClient = createGitHubHttpClient({
      now: () => NOW,
      fetch: () =>
        Promise.resolve(json({
          token: TOKEN,
          expires_at: expiresAt,
          repository_selection: "selected",
          permissions: { metadata: "read", administration: "write" },
        })),
    });
    const lease = await boundaryClient.execute(operation({
      kind: "TOKEN_EXCHANGE",
      installationId: INSTALLATION_ID,
      appJwt: APP_JWT,
      repositoryIds: [REPOSITORY_ID],
      permissions: { metadata: "read", administration: "write" },
    }));

    assertEquals("expiresAt" in lease && lease.expiresAt, expiresAt);
  }

  const markerSizeMismatch = createGitHubHttpClient({
    fetch: () =>
      Promise.resolve(json({
        path: ".lws/project.json",
        sha: CONTENT_SHA,
        encoding: "base64",
        content: "e30=",
        size: 3,
      })),
  });
  await assertRejects(
    () =>
      markerSizeMismatch.execute(operation({
        kind: "READ_PROJECT_MARKER",
        owner: OWNER,
        repository: REPOSITORY,
        ref: SHA,
        token: TOKEN,
      })),
    GitHubHttpError,
    "GITHUB_HTTP_RESPONSE_INVALID",
  );
});

Deno.test("GitHub HTTP preserves closed create failure boundaries", async () => {
  const create = () =>
    operation({
      kind: "CREATE_REPOSITORY",
      owner: OWNER,
      repository: REPOSITORY,
      description: "LWS Task 13 operation d2140000-0000-4000-8000-000000000001",
      token: TOKEN,
    });
  const cases = [
    {
      boundary: "HTTP_REQUEST",
      fetch: () => Promise.reject(new Error("transport")),
    },
    {
      boundary: "HTTP_STATUS",
      fetch: () => Promise.resolve(json({}, 403)),
    },
    {
      boundary: "CONTENT_TYPE",
      fetch: () => Promise.resolve(new Response("not json")),
    },
    {
      boundary: "BODY_READ",
      fetch: () =>
        Promise.resolve(
          new Response(
            new ReadableStream({
              pull(controller) {
                controller.error(new Error("body read"));
              },
            }),
            { headers: { "content-type": "application/json" } },
          ),
        ),
    },
    {
      boundary: "JSON_PARSE",
      fetch: () =>
        Promise.resolve(
          new Response("{", {
            headers: { "content-type": "application/json" },
          }),
        ),
    },
    {
      boundary: "RESPONSE_SCHEMA",
      fetch: () => Promise.resolve(json({ id: Number(REPOSITORY_ID) })),
    },
  ] as const;

  const invalidPrepare = createGitHubHttpClient({
    fetch: () => Promise.resolve(json(repositoryResponse())),
  });
  const prepareError = await assertRejects(
    () =>
      invalidPrepare.execute({
        ...create(),
        description: "invalid\ndescription",
      } as GitHubHttpOperation),
    GitHubHttpError,
  );
  assertEquals(prepareError.boundary, "REQUEST_PREPARE");

  for (const scenario of cases) {
    const client = createGitHubHttpClient({ fetch: scenario.fetch });
    const error = await assertRejects(
      () => client.execute(create()),
      GitHubHttpError,
    );
    assertEquals(error.boundary, scenario.boundary);
  }

  const success = createGitHubHttpClient({
    fetch: () => Promise.resolve(json(repositoryResponse(), 201)),
  });
  assertEquals(
    (await success.execute(create()) as { repositoryId: string }).repositoryId,
    REPOSITORY_ID,
  );
});

Deno.test("GitHub HTTP boundary metadata is immutable", () => {
  const error = new GitHubHttpError(
    "GITHUB_HTTP_NETWORK_ERROR",
    null,
    null,
    undefined,
    "HTTP_REQUEST",
  );
  assertThrows(
    () => Object.assign(error, { boundary: "HTTP_STATUS" }),
    TypeError,
  );
  assertEquals(error.boundary, "HTTP_REQUEST");
});

Deno.test("GitHub HTTP client normalizes status, retry and timeout failures", async () => {
  const cases = [
    [401, "GITHUB_HTTP_UNAUTHORIZED", null],
    [403, "GITHUB_HTTP_FORBIDDEN", null],
    [404, "GITHUB_HTTP_NOT_FOUND", null],
    [409, "GITHUB_HTTP_CONFLICT", null],
    [422, "GITHUB_HTTP_CONFLICT", null],
    [429, "GITHUB_HTTP_RATE_LIMITED", "2026-09-13T12:01:00.000Z"],
    [500, "GITHUB_HTTP_SERVER_ERROR", null],
  ] as const;
  for (const [status, code, retryAt] of cases) {
    const client = createGitHubHttpClient({
      fetch: () =>
        Promise.resolve(json(
          { message: `raw ${TOKEN}` },
          status,
          {
            "x-github-request-id": "REQ_123",
            ...(status === 429 ? { "x-ratelimit-reset": "1789300860" } : {}),
          },
        )),
    });
    const error = await assertRejects(
      () =>
        client.execute(operation({
          kind: "REPOSITORY_METADATA",
          owner: OWNER,
          repository: REPOSITORY,
          token: TOKEN,
        })),
      GitHubHttpError,
      code,
    );
    assertEquals(error.requestId, "REQ_123");
    assertEquals(error.retryAt, retryAt);
    assertEquals(
      `${error.message}\n${error.stack}\n${JSON.stringify(error)}`.includes(
        TOKEN,
      ),
      false,
    );
  }

  const secondaryLimit = createGitHubHttpClient({
    now: () => NOW,
    fetch: () => Promise.resolve(json({}, 403, { "retry-after": "30" })),
  });
  const secondaryError = await assertRejects(
    () =>
      secondaryLimit.execute(operation({
        kind: "REPOSITORY_METADATA",
        owner: OWNER,
        repository: REPOSITORY,
        token: TOKEN,
      })),
    GitHubHttpError,
    "GITHUB_HTTP_RATE_LIMITED",
  );
  assertEquals(secondaryError.retryAt, "2026-09-13T12:00:30.000Z");

  const timeout = createGitHubHttpClient({
    timeoutMilliseconds: 5,
    fetch: (_input, init) =>
      new Promise((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () =>
          reject(new DOMException("raw timeout", "AbortError")));
      }),
  });
  await assertRejects(
    () =>
      timeout.execute(operation({
        kind: "REPOSITORY_METADATA",
        owner: OWNER,
        repository: REPOSITORY,
        token: TOKEN,
      })),
    GitHubHttpError,
    "GITHUB_HTTP_TIMEOUT",
  );
});

Deno.test("GitHub HTTP errors never disclose raw bodies, headers, credentials or URLs", async () => {
  const rawUrl = `https://api.github.com/repos/${OWNER}/${REPOSITORY}`;
  const rawHeader = "private-header-value";
  const client = createGitHubHttpClient({
    fetch: () =>
      Promise.resolve(json(
        { message: `${TOKEN} ${APP_JWT} ${rawUrl}` },
        403,
        { "x-private-debug": rawHeader, "x-github-request-id": "REQ_SAFE" },
      )),
  });
  const error = await assertRejects(
    () =>
      client.execute(operation({
        kind: "REPOSITORY_METADATA",
        owner: OWNER,
        repository: REPOSITORY,
        token: TOKEN,
      })),
    GitHubHttpError,
    "GITHUB_HTTP_FORBIDDEN",
  );
  const serialized = `${error.message}\n${error.stack}\n${
    JSON.stringify(error)
  }`;
  for (
    const forbidden of [TOKEN, APP_JWT, rawUrl, rawHeader, OWNER, REPOSITORY]
  ) {
    assertEquals(serialized.includes(forbidden), false);
  }
  assertEquals(error.requestId, "REQ_SAFE");
});
