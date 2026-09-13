import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  createGitHubHttpClient,
  GitHubHttpError,
  type GitHubHttpOperation,
} from "./github-http.ts";

const TOKEN = "synthetic_installation_token_123456789";
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
  };
}

function operation(
  value: GitHubHttpOperation,
): GitHubHttpOperation {
  return value;
}

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
      if (path.endsWith("/generate")) {
        return Promise.resolve(json(repositoryResponse(), 201));
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
    kind: "GENERATE_REPOSITORY",
    templateOwner: OWNER,
    templateRepository: TEMPLATE,
    owner: OWNER,
    repository: REPOSITORY,
    description: "Provisioned by Lorenzo Web Solutions",
    token: TOKEN,
  }));
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
      ["POST", `https://api.github.com/repos/${OWNER}/${TEMPLATE}/generate`],
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
    owner: OWNER,
    name: REPOSITORY,
    description: "Provisioned by Lorenzo Web Solutions",
    include_all_branches: false,
    private: true,
  });
  assertEquals(await requests[4].json(), {
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
        expires_at: "2026-09-13T13:00:01.000Z",
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
