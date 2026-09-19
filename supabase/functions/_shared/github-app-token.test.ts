import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import type { GitHubAppConfig } from "./github-app-config.ts";
import {
  createGitHubAppTokenBroker,
  GitHubTokenBrokerError,
  GitHubTokenExchangeFailure,
  type GitHubTokenRequest,
} from "./github-app-token.ts";
import { createGitHubHttpClient, GitHubHttpError } from "./github-http.ts";
import { GitHubTokenAcquireDiagnosticError } from "./repository-provisioning-diagnostics.ts";

const NOW = Date.parse("2026-09-13T12:00:00.000Z");
const CONTEXT_ID = "0198abcd-1234-7000-8000-0123456789ab";
const CUSTOMER_REPOSITORY_ID = "987654322";
const PRIVATE_KEY = [
  "-----BEGIN " + "PRIVATE KEY-----",
  "QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFB",
  "-----END " + "PRIVATE KEY-----",
].join("\n");
const INSTALLATION_TOKEN = "gh" + `s_${"a".repeat(36)}`;

function config(target: "TEST" | "PRODUCTION" = "TEST"): GitHubAppConfig {
  const value = {
    enabled: true as const,
    target,
    appId: "123456",
    installationId: "654321",
    organization: target === "TEST"
      ? "lorenzo-web-solutions-lab"
      : "lorenzo-web-solutions",
    templateOwner: target === "TEST"
      ? "lorenzo-web-solutions-lab"
      : "lorenzo-web-solutions",
    templateName: "lws-website-starter",
    templateRepositoryId: "987654321",
    starterVersion: "1.0.0",
    starterCommitSha: "a".repeat(40),
    starterTreeSha256: "b".repeat(64),
  };
  Object.defineProperty(value, "privateKey", {
    value: PRIVATE_KEY,
    enumerable: false,
  });
  return Object.freeze(value) as GitHubAppConfig;
}

function request(
  overrides: Partial<GitHubTokenRequest> = {},
): GitHubTokenRequest {
  return Object.freeze({
    websiteWorkContextId: CONTEXT_ID,
    target: "TEST",
    organization: "lorenzo-web-solutions-lab",
    operation: "LAB_REPOSITORY_WRITE",
    repositoryIds: Object.freeze([CUSTOMER_REPOSITORY_ID]),
    ...overrides,
  });
}

function authority(
  overrides: Record<string, unknown> = {},
) {
  return Object.freeze({
    websiteWorkContextId: CONTEXT_ID,
    target: "TEST" as const,
    organization: "lorenzo-web-solutions-lab",
    repositoryIds: Object.freeze([CUSTOMER_REPOSITORY_ID]),
    ...overrides,
  });
}

function decodeJson(segment: string): Record<string, unknown> {
  const normalized = segment.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized.padEnd(
    normalized.length + ((4 - normalized.length % 4) % 4),
    "=",
  );
  return JSON.parse(atob(padded));
}

function harness(response: unknown = {
  token: INSTALLATION_TOKEN,
  expiresAt: "2026-09-13T12:55:00.000Z",
  repositorySelection: "selected",
  permissions: { metadata: "read", contents: "write" },
}) {
  const signCalls: unknown[] = [];
  const exchangeCalls: unknown[] = [];
  const broker = createGitHubAppTokenBroker({
    now: () => NOW,
    sign: (privateKey, signingInput) => {
      signCalls.push({ privateKey, signingInput });
      return Promise.resolve(new Uint8Array([1, 2, 3, 4]));
    },
    exchange: (input) => {
      exchangeCalls.push(input);
      return Promise.resolve(response);
    },
  });
  return { broker, signCalls, exchangeCalls };
}

function tokenSubphase(error: unknown): string | undefined {
  return (error as { tokenAcquireSubphase?: string }).tokenAcquireSubphase;
}

function leaseCheck(error: unknown): string | undefined {
  return (error as { tokenLeaseCheck?: string }).tokenLeaseCheck;
}

function responseCheck(error: unknown): string | undefined {
  return (error as { tokenResponseCheck?: string }).tokenResponseCheck;
}

async function task13TokenAcquisition(
  rawResponse: unknown,
  clocks: Readonly<{
    httpNow(): number;
    brokerNow(): number;
  }> = { httpNow: () => NOW, brokerNow: () => NOW },
  tokenRequest: GitHubTokenRequest = request(),
  tokenAuthority: ReturnType<typeof authority> = authority(),
) {
  const http = createGitHubHttpClient({
    now: clocks.httpNow,
    fetch: () =>
      Promise.resolve(
        new Response(JSON.stringify(rawResponse), {
          headers: { "content-type": "application/json; charset=utf-8" },
        }),
      ),
  });
  const broker = createGitHubAppTokenBroker({
    now: clocks.brokerNow,
    sign: () => Promise.resolve(new Uint8Array([1, 2, 3, 4])),
    exchange: async (input) => {
      const result = await http.execute({
        kind: "TOKEN_EXCHANGE",
        installationId: input.installationId,
        appJwt: input.appJwt,
        repositoryIds: input.repositoryIds,
        permissions: input.permissions,
      });
      if (!("expiresAt" in result) || !("token" in result)) {
        throw new Error("GITHUB_TOKEN_EXCHANGE_FAILED");
      }
      return {
        token: result.token,
        expiresAt: result.expiresAt,
        ...("repositorySelection" in result
          ? { repositorySelection: result.repositorySelection }
          : {}),
        permissions: result.permissions,
      };
    },
  });
  return await broker.issue(
    config(tokenRequest.target),
    tokenRequest,
    tokenAuthority,
  );
}

Deno.test("GitHub App broker signs a short-lived JWT and requests one exact repository scope", async () => {
  const test = harness();
  const lease = await test.broker.issue(
    config(),
    request(),
    authority(),
  );

  assertEquals(lease.token, INSTALLATION_TOKEN);
  assertEquals(lease.expiresAt, "2026-09-13T12:55:00.000Z");
  assertEquals(Object.keys(lease), ["expiresAt"]);
  assertEquals(JSON.stringify(lease).includes(INSTALLATION_TOKEN), false);
  assertEquals(Object.getOwnPropertyDescriptor(lease, "token"), {
    value: INSTALLATION_TOKEN,
    writable: false,
    enumerable: false,
    configurable: false,
  });
  assertEquals(Object.isFrozen(lease), true);
  assertEquals(test.signCalls.length, 1);
  const signCall = test.signCalls[0] as {
    privateKey: string;
    signingInput: string;
  };
  assertEquals(signCall.privateKey, PRIVATE_KEY);
  const [encodedHeader, encodedPayload] = signCall.signingInput.split(".");
  assertEquals(decodeJson(encodedHeader), { alg: "RS256", typ: "JWT" });
  assertEquals(decodeJson(encodedPayload), {
    iat: Math.floor(NOW / 1000) - 60,
    exp: Math.floor(NOW / 1000) + 540,
    iss: "123456",
  });
  assertEquals(test.exchangeCalls, [{
    installationId: "654321",
    appJwt: `${signCall.signingInput}.AQIDBA`,
    repositoryIds: [CUSTOMER_REPOSITORY_ID],
    permissions: { metadata: "read", contents: "write" },
  }]);
});

Deno.test("GitHub App broker issues production-compatible project-file read scope only", async () => {
  for (const target of ["TEST", "PRODUCTION"] as const) {
    const organization = target === "TEST"
      ? "lorenzo-web-solutions-lab"
      : "lorenzo-web-solutions";
    const test = harness({
      token: INSTALLATION_TOKEN,
      expiresAt: "2026-09-13T12:55:00.000Z",
      repositorySelection: "selected",
      permissions: { metadata: "read", contents: "read" },
    });
    await test.broker.issue(
      config(target),
      request({
        target,
        organization,
        operation: "WEBSITE_PROJECT_FILES_READ",
      }),
      authority({ target, organization }),
    );
    assertEquals(test.exchangeCalls, [{
      installationId: "654321",
      appJwt: (test.exchangeCalls[0] as { appJwt: string }).appJwt,
      repositoryIds: [CUSTOMER_REPOSITORY_ID],
      permissions: { metadata: "read", contents: "read" },
    }]);
  }
});

Deno.test("GitHub App broker classifies token authority validation", async () => {
  const test = harness();
  const error = await assertRejects(
    () =>
      test.broker.issue(
        config(),
        request({ repositoryIds: [] }),
        authority({ repositoryIds: [] }),
      ),
    GitHubTokenBrokerError,
    "GITHUB_TOKEN_AUTHORITY_INVALID",
  );
  assertEquals(tokenSubphase(error), "TOKEN_AUTHORITY_VALIDATE");
});

Deno.test("GitHub App broker classifies token JWT signing", async () => {
  const broker = createGitHubAppTokenBroker({
    now: () => NOW,
    sign: () => Promise.reject(new Error("synthetic signing failure")),
    exchange: () => Promise.resolve({}),
  });
  const error = await assertRejects(
    () => broker.issue(config(), request(), authority()),
    GitHubTokenBrokerError,
    "GITHUB_APP_SIGNING_FAILED",
  );
  assertEquals(tokenSubphase(error), "TOKEN_JWT_SIGN");
});

Deno.test("GitHub App broker classifies token adapter projection", async () => {
  const broker = createGitHubAppTokenBroker({
    now: () => NOW,
    sign: () => Promise.resolve(new Uint8Array([1, 2, 3, 4])),
    exchange: () => Promise.reject(new Error("synthetic adapter failure")),
  });
  const error = await assertRejects(
    () => broker.issue(config(), request(), authority()),
    GitHubTokenBrokerError,
    "GITHUB_TOKEN_EXCHANGE_FAILED",
  );
  assertEquals(tokenSubphase(error), "TOKEN_ADAPTER_PROJECT");
});

Deno.test("GitHub App broker preserves every first causal token boundary", async () => {
  const scenarios = [
    ["GITHUB_HTTP_OPERATION_INVALID", "TOKEN_REQUEST_PREPARE"],
    ["GITHUB_HTTP_NETWORK_ERROR", "TOKEN_HTTP_REQUEST"],
    ["GITHUB_HTTP_UNAUTHORIZED", "TOKEN_HTTP_STATUS"],
    ["GITHUB_HTTP_RESPONSE_INVALID", "TOKEN_CONTENT_TYPE_VALIDATE"],
    ["GITHUB_HTTP_RESPONSE_TOO_LARGE", "TOKEN_RESPONSE_BODY_READ"],
    ["GITHUB_HTTP_RESPONSE_INVALID", "TOKEN_JSON_PARSE"],
    ["GITHUB_HTTP_RESPONSE_INVALID", "TOKEN_RESPONSE_SCHEMA"],
  ] as const;
  for (const [code, subphase] of scenarios) {
    const broker = createGitHubAppTokenBroker({
      now: () => NOW,
      sign: () => Promise.resolve(new Uint8Array([1, 2, 3, 4])),
      exchange: () =>
        Promise.reject(new GitHubHttpError(code, null, null, subphase)),
    });
    const error = await assertRejects(
      () => broker.issue(config(), request(), authority()),
      GitHubTokenBrokerError,
    );
    assertEquals(tokenSubphase(error), subphase);
  }
});

Deno.test("GitHub App broker preserves a trusted token response check", async () => {
  const broker = createGitHubAppTokenBroker({
    now: () => NOW,
    sign: () => Promise.resolve(new Uint8Array([1, 2, 3, 4])),
    exchange: () =>
      Promise.reject(
        new GitHubHttpError(
          "GITHUB_HTTP_RESPONSE_INVALID",
          null,
          null,
          "TOKEN_RESPONSE_SCHEMA",
          "RESPONSE_SCHEMA",
          "TOKEN_SCHEMA_REPOSITORY_SELECTION",
        ),
      ),
  });
  const error = await assertRejects(
    () => broker.issue(config(), request(), authority()),
    GitHubTokenBrokerError,
    "GITHUB_TOKEN_EXCHANGE_FAILED",
  );
  assertEquals(tokenSubphase(error), "TOKEN_RESPONSE_SCHEMA");
  assertEquals(responseCheck(error), "TOKEN_SCHEMA_REPOSITORY_SELECTION");
});

Deno.test("GitHub App broker does not fabricate a prototype-forged response check", async () => {
  const forged = Object.assign(
    Object.create(GitHubTokenAcquireDiagnosticError.prototype),
    {
      tokenAcquireSubphase: "TOKEN_RESPONSE_SCHEMA",
      tokenResponseCheck: "TOKEN_SCHEMA_REPOSITORY_SELECTION",
    },
  );
  const broker = createGitHubAppTokenBroker({
    now: () => NOW,
    sign: () => Promise.resolve(new Uint8Array([1, 2, 3, 4])),
    exchange: () => Promise.reject(forged),
  });
  const error = await assertRejects(
    () => broker.issue(config(), request(), authority()),
    GitHubTokenBrokerError,
    "GITHUB_TOKEN_EXCHANGE_FAILED",
  );
  assertEquals(responseCheck(error), undefined);
});

Deno.test("GitHub App broker classifies token lease validation", async () => {
  const test = harness({});
  const error = await assertRejects(
    () => test.broker.issue(config(), request(), authority()),
    GitHubTokenBrokerError,
    "GITHUB_TOKEN_RESPONSE_INVALID",
  );
  assertEquals(tokenSubphase(error), "TOKEN_LEASE_VALIDATE");
});

Deno.test("GitHub App broker classifies the remaining lease checks", async () => {
  for (
    const [response, expected] of [
      [{
        token: "synthetic-token-value-123456789",
        expiresAt: "2026-09-13T12:55:00.000Z",
        repositorySelection: "selected",
        permissions: { metadata: "read", contents: "write" },
      }, "LEASE_TOKEN_FORMAT_VALIDATE"],
      [{
        token: INSTALLATION_TOKEN,
        expiresAt: "2026-09-13T12:00:00.000Z",
        repositorySelection: "selected",
        permissions: { metadata: "read", contents: "write" },
      }, "LEASE_EXPIRY_LOWER_BOUND"],
    ] as const
  ) {
    const test = harness(response);
    const error = await assertRejects(
      () => test.broker.issue(config(), request(), authority()),
      GitHubTokenBrokerError,
      "GITHUB_TOKEN_RESPONSE_INVALID",
    );
    assertEquals(tokenSubphase(error), "TOKEN_LEASE_VALIDATE");
    assertEquals(leaseCheck(error), expected);
  }
});

Deno.test("GitHub App broker accepts a synthetic stateless installation token", async () => {
  const test = harness({
    token: `ghs_4932372_${"a".repeat(40)}.${"b".repeat(40)}.${"c".repeat(40)}`,
    expiresAt: "2026-09-13T12:55:00.000Z",
    repositorySelection: "selected",
    permissions: { metadata: "read", contents: "write" },
  });

  await test.broker.issue(config(), request(), authority());
});

Deno.test("GitHub HTTP accepts a synthetic 520-plus installation token", async () => {
  const token = `ghs_4932372_${"a".repeat(170)}.${"b".repeat(170)}.${
    "c".repeat(170)
  }`;
  await task13TokenAcquisition({
    token,
    expires_at: "2026-09-13T12:55:00.000Z",
    repository_selection: "selected",
    permissions: { metadata: "read", contents: "write" },
  });
});

Deno.test("Task 13 classifies broker upper bound after wall-clock rollback", async () => {
  let brokerNowCalls = 0;
  const error = await assertRejects(
    () =>
      task13TokenAcquisition({
        token: INSTALLATION_TOKEN,
        expires_at: "2026-09-13T13:01:00.000Z",
        repository_selection: "selected",
        permissions: { metadata: "read", contents: "write" },
      }, {
        httpNow: () => NOW,
        brokerNow: () => brokerNowCalls++ === 0 ? NOW : NOW - 1,
      }),
    GitHubTokenBrokerError,
    "GITHUB_TOKEN_RESPONSE_INVALID",
  );
  assertEquals(tokenSubphase(error), "TOKEN_LEASE_VALIDATE");
  assertEquals(leaseCheck(error), "LEASE_EXPIRY_UPPER_BOUND");
});

Deno.test("GitHub App broker derives exact permissions for LAB repository writes", async () => {
  const test = harness({
    token: INSTALLATION_TOKEN,
    expiresAt: "2026-09-13T12:55:00.000Z",
    repositorySelection: "selected",
    permissions: { metadata: "read", contents: "write" },
  });

  await test.broker.issue(
    config(),
    request(),
    authority(),
  );

  assertEquals(
    (test.exchangeCalls[0] as Record<string, unknown>).permissions,
    { metadata: "read", contents: "write" },
  );
});

Deno.test("GitHub App broker derives read-only permissions for LAB repository inspection", async () => {
  const test = harness({
    token: INSTALLATION_TOKEN,
    expiresAt: "2026-09-13T12:55:00.000Z",
    repositorySelection: "selected",
    permissions: { metadata: "read", contents: "read" },
  });

  await test.broker.issue(
    config(),
    request(
      { operation: "LAB_REPOSITORY_READ" } as unknown as Partial<
        GitHubTokenRequest
      >,
    ),
    authority(),
  );

  assertEquals(
    (test.exchangeCalls[0] as Record<string, unknown>).permissions,
    { metadata: "read", contents: "read" },
  );
});

Deno.test("GitHub App broker separates production snapshot read from LAB create authority", async () => {
  const productionRead = harness({
    token: INSTALLATION_TOKEN,
    expiresAt: "2026-09-13T12:55:00.000Z",
    repositorySelection: "selected",
    permissions: { metadata: "read", contents: "read" },
  });
  await productionRead.broker.issue(
    config("PRODUCTION"),
    request({
      target: "PRODUCTION",
      organization: "lorenzo-web-solutions",
      operation: "STARTER_SNAPSHOT_READ",
      repositoryIds: ["987654321"],
    }),
    authority({
      target: "PRODUCTION",
      organization: "lorenzo-web-solutions",
      repositoryIds: ["987654321"],
    }),
  );

  assertEquals(productionRead.exchangeCalls, [{
    installationId: "654321",
    appJwt: (productionRead.exchangeCalls[0] as Record<string, unknown>).appJwt,
    repositoryIds: ["987654321"],
    permissions: { metadata: "read", contents: "read" },
  }]);

  const labCreate = harness({
    token: INSTALLATION_TOKEN,
    expiresAt: "2026-09-13T12:55:00.000Z",
    repositorySelection: "selected",
    permissions: { metadata: "read", administration: "write" },
  });
  await labCreate.broker.issue(
    config("TEST"),
    request({
      operation: "LAB_REPOSITORY_CREATE",
      repositoryIds: [],
    }),
    authority({ repositoryIds: [] }),
  );

  assertEquals(labCreate.exchangeCalls, [{
    installationId: "654321",
    appJwt: (labCreate.exchangeCalls[0] as Record<string, unknown>).appJwt,
    repositoryIds: [],
    permissions: { metadata: "read", administration: "write" },
  }]);
});

Deno.test("Task 13 token chain accepts absent LAB repository-selection metadata", async () => {
  const lease = await task13TokenAcquisition(
    {
      token: INSTALLATION_TOKEN,
      expires_at: "2026-09-13T12:55:00.000Z",
      permissions: { metadata: "read", administration: "write" },
    },
    undefined,
    request({
      operation: "LAB_REPOSITORY_CREATE",
      repositoryIds: [],
    }),
    authority({ repositoryIds: [] }),
  );

  assertEquals(lease.expiresAt, "2026-09-13T12:55:00.000Z");
});

Deno.test("Task 13 token chain accepts all LAB repository-selection metadata", async () => {
  const lease = await task13TokenAcquisition(
    {
      token: INSTALLATION_TOKEN,
      expires_at: "2026-09-13T12:55:00.000Z",
      repository_selection: "all",
      permissions: { metadata: "read", administration: "write" },
    },
    undefined,
    request({
      operation: "LAB_REPOSITORY_CREATE",
      repositoryIds: [],
    }),
    authority({ repositoryIds: [] }),
  );

  assertEquals(lease.expiresAt, "2026-09-13T12:55:00.000Z");
});

Deno.test("GitHub App broker accepts absent projected repository-selection metadata", async () => {
  const test = harness({
    token: INSTALLATION_TOKEN,
    expiresAt: "2026-09-13T12:55:00.000Z",
    permissions: { metadata: "read", contents: "write" },
  });

  const lease = await test.broker.issue(config(), request(), authority());

  assertEquals(lease.expiresAt, "2026-09-13T12:55:00.000Z");
});

Deno.test("GitHub App broker accepts all projected repository-selection metadata", async () => {
  const test = harness({
    token: INSTALLATION_TOKEN,
    expiresAt: "2026-09-13T12:55:00.000Z",
    repositorySelection: "all",
    permissions: { metadata: "read", contents: "write" },
  });

  const lease = await test.broker.issue(config(), request(), authority());

  assertEquals(lease.expiresAt, "2026-09-13T12:55:00.000Z");
});

Deno.test("Task 13 production token acquisition accepts bounded positive GitHub server clock skew", async () => {
  let clock = NOW;
  let signingInput = "";
  const requests: Request[] = [];
  const productionConfig = {
    enabled: true as const,
    target: "PRODUCTION" as const,
    appId: "4932372",
    installationId: "161436785",
    organization: "lorenzo-web-solutions",
    templateOwner: "lorenzo-web-solutions",
    templateName: "lws-website-starter",
    templateRepositoryId: "1368684860",
    starterVersion: "1.0.0",
    starterCommitSha: "a".repeat(40),
    starterTreeSha256: "b".repeat(64),
  };
  Object.defineProperty(productionConfig, "privateKey", {
    value: PRIVATE_KEY,
    enumerable: false,
  });
  const http = createGitHubHttpClient({
    now: () => clock,
    fetch(input, init) {
      requests.push(new Request(input, init));
      clock = NOW + 2_000;
      return Promise.resolve(
        new Response(
          JSON.stringify({
            token: INSTALLATION_TOKEN,
            expires_at: new Date(NOW + 5_000 + 60 * 60 * 1000).toISOString(),
            repository_selection: "selected",
            permissions: { metadata: "read", contents: "read" },
          }),
          { headers: { "content-type": "application/json" } },
        ),
      );
    },
  });
  const broker = createGitHubAppTokenBroker({
    now: () => clock,
    sign(privateKey, value) {
      assertEquals(privateKey, PRIVATE_KEY);
      signingInput = value;
      clock = NOW + 1_000;
      return Promise.resolve(new Uint8Array([1, 2, 3, 4]));
    },
    exchange: async (input) => {
      const result = await http.execute({
        kind: "TOKEN_EXCHANGE",
        installationId: input.installationId,
        appJwt: input.appJwt,
        repositoryIds: input.repositoryIds,
        permissions: input.permissions,
      });
      if (!("token" in result) || !("expiresAt" in result)) {
        throw new Error("GITHUB_TOKEN_EXCHANGE_FAILED");
      }
      return {
        token: result.token,
        expiresAt: result.expiresAt,
        repositorySelection: result.repositorySelection,
        permissions: result.permissions,
      };
    },
  });
  const tokenRequest = Object.freeze({
    websiteWorkContextId: CONTEXT_ID,
    target: "PRODUCTION" as const,
    organization: "lorenzo-web-solutions",
    operation: "STARTER_SNAPSHOT_READ" as const,
    repositoryIds: Object.freeze(["1368684860"]),
  });

  const lease = await broker.issue(
    productionConfig as GitHubAppConfig,
    tokenRequest,
    Object.freeze({
      websiteWorkContextId: CONTEXT_ID,
      target: "PRODUCTION" as const,
      organization: "lorenzo-web-solutions",
      repositoryIds: Object.freeze(["1368684860"]),
    }),
  );

  assertEquals(Object.keys(productionConfig).includes("privateKey"), false);
  assertEquals(requests.length, 1);
  assertEquals(
    requests[0].url,
    "https://api.github.com/app/installations/161436785/access_tokens",
  );
  assertEquals(requests[0].method, "POST");
  assertEquals(
    requests[0].headers.get("accept"),
    "application/vnd.github+json",
  );
  assertEquals(requests[0].headers.get("x-github-api-version"), "2022-11-28");
  assertEquals(requests[0].headers.get("content-type"), "application/json");
  assertEquals(await requests[0].json(), {
    repository_ids: [1368684860],
    permissions: { metadata: "read", contents: "read" },
  });
  const [, encodedPayload] = signingInput.split(".");
  assertEquals(decodeJson(encodedPayload), {
    iat: Math.floor(NOW / 1000) - 60,
    exp: Math.floor(NOW / 1000) + 540,
    iss: "4932372",
  });
  assertEquals(lease.expiresAt, "2026-09-13T13:00:05.000Z");
  assertEquals(lease.token, INSTALLATION_TOKEN);
});

Deno.test("GitHub App broker accepts exact one-hour and clock-skew boundaries", async () => {
  for (
    const expiresAt of [
      "2026-09-13T13:00:00.000Z",
      "2026-09-13T13:01:00.000Z",
    ]
  ) {
    const test = harness({
      token: INSTALLATION_TOKEN,
      expiresAt,
      repositorySelection: "selected",
      permissions: { metadata: "read", contents: "write" },
    });

    const lease = await test.broker.issue(config(), request(), authority());

    assertEquals(lease.expiresAt, expiresAt);
  }
});

Deno.test("Task 13 characterizes GitHub installation token response shapes", async () => {
  const base = {
    token: INSTALLATION_TOKEN,
    expires_at: "2026-09-13T12:55:00.000Z",
  };
  const permissions = { metadata: "read", contents: "write" };
  for (
    const [fixture, accepted] of [
      [{ ...base }, false],
      [{ ...base, permissions }, true],
      [{ ...base, permissions, repositories: [{ id: 987654322 }] }, true],
      [{ ...base, permissions, repository_selection: "selected" }, true],
      [{
        ...base,
        permissions,
        repository_selection: "selected",
        unknown_provider_field: "ignored",
      }, true],
      [{ ...base, permissions, repository_selection: "selected" }, true],
      [{ ...base, permissions }, true],
      [{
        ...base,
        permissions: { ...permissions, workflows: "read" },
        repository_selection: "selected",
      }, false],
      [{
        ...base,
        permissions: { contents: "write", metadata: "read" },
        repository_selection: "selected",
      }, true],
      [{
        ...base,
        permissions: { contents: "write" },
        repository_selection: "selected",
      }, false],
      [{
        ...base,
        permissions: { metadata: "Read", contents: "write" },
        repository_selection: "selected",
      }, false],
      [{
        ...base,
        permissions,
        repository_selection: "selected",
        repositories: [],
      }, true],
      [{
        ...base,
        permissions,
        repository_selection: "selected",
        repositories: [{ id: 987654322 }],
      }, true],
      [{
        ...base,
        permissions,
        repository_selection: "selected",
        repositories: [{ id: "987654322" }],
      }, true],
    ] as const
  ) {
    let passed = true;
    try {
      await task13TokenAcquisition(fixture);
    } catch {
      passed = false;
    }
    assertEquals(passed, accepted);
  }
});

Deno.test("Task 13 applies one GitHub installation-token contract across HTTP and broker", async () => {
  const statelessToken = `ghs_4932372_${"a".repeat(170)}.${"b".repeat(170)}.${
    "c".repeat(170)
  }`;
  const fixtures = [
    ["classic", `ghs_${"a".repeat(36)}`, true],
    ["stateless_dots", statelessToken, true],
    ["underscore", `ghs_${"a".repeat(18)}_${"b".repeat(18)}`, true],
    ["hyphen", `ghs_${"a".repeat(18)}-${"b".repeat(18)}`, true],
    ["whitespace", `ghs_${"a".repeat(18)} ${"b".repeat(18)}`, false],
    ["newline", `ghs_${"a".repeat(18)}\n${"b".repeat(18)}`, false],
    ["wrong_prefix", `ghp_${"a".repeat(36)}`, false],
    ["too_short", `ghs_${"a".repeat(35)}`, false],
    ["malformed", `ghs_${"a".repeat(18)}+${"b".repeat(18)}`, false],
  ] as const;
  for (const [, token, accepted] of fixtures) {
    const http = createGitHubHttpClient({
      now: () => NOW,
      fetch: () =>
        Promise.resolve(
          new Response(
            JSON.stringify({
              token,
              expires_at: "2026-09-13T12:55:00.000Z",
              repository_selection: "selected",
              permissions: { metadata: "read", contents: "write" },
            }),
            { headers: { "content-type": "application/json" } },
          ),
        ),
    });
    let httpPassed = true;
    try {
      await http.execute({
        kind: "TOKEN_EXCHANGE",
        installationId: "654321",
        appJwt: "synthetic.app.jwt",
        repositoryIds: [CUSTOMER_REPOSITORY_ID],
        permissions: { metadata: "read", contents: "write" },
      });
    } catch {
      httpPassed = false;
    }
    assertEquals(httpPassed, accepted);

    let brokerPassed = true;
    try {
      await task13TokenAcquisition({
        token,
        expires_at: "2026-09-13T12:55:00.000Z",
        repository_selection: "selected",
        permissions: { metadata: "read", contents: "write" },
      });
    } catch {
      brokerPassed = false;
    }
    assertEquals(brokerPassed, accepted);
  }
});

Deno.test("GitHub App broker rejects empty, duplicate, broad and cross-context repository authority", async () => {
  for (
    const [tokenRequest, serverAuthority] of [
      [request({ repositoryIds: [] }), authority({ repositoryIds: [] })],
      [
        request({
          repositoryIds: [CUSTOMER_REPOSITORY_ID, CUSTOMER_REPOSITORY_ID],
        }),
        authority({ repositoryIds: [CUSTOMER_REPOSITORY_ID] }),
      ],
      [
        request({ repositoryIds: [CUSTOMER_REPOSITORY_ID, "987654323"] }),
        authority({ repositoryIds: [CUSTOMER_REPOSITORY_ID, "987654323"] }),
      ],
      [request(), authority({ websiteWorkContextId: crypto.randomUUID() })],
      [request(), authority({ repositoryIds: ["987654323"] })],
      [
        request(),
        {
          ...authority(),
          operation: "LAB_REPOSITORY_WRITE",
        } as unknown as ReturnType<typeof authority>,
      ],
      [
        request({ operation: "TEMPLATE_GENERATION" as never }),
        authority(),
      ],
      [
        {
          ...request(),
          callerRepositoryName: "browser-controlled",
        } as unknown as GitHubTokenRequest,
        authority(),
      ],
      [
        request(),
        {
          ...authority(),
          installationId: "browser-controlled",
        } as unknown as ReturnType<typeof authority>,
      ],
    ] as const
  ) {
    const test = harness();
    await assertRejects(
      () => test.broker.issue(config(), tokenRequest, serverAuthority),
      GitHubTokenBrokerError,
      "GITHUB_TOKEN_AUTHORITY_INVALID",
    );
    assertEquals(test.signCalls, []);
    assertEquals(test.exchangeCalls, []);
  }
});

Deno.test("GitHub App broker normalizes signing failures and never exchanges an invalid signature", async () => {
  for (
    const sign of [
      () => Promise.reject(new Error(`raw ${PRIVATE_KEY}`)),
      () => Promise.resolve(new Uint8Array()),
    ]
  ) {
    const exchangeCalls: unknown[] = [];
    const broker = createGitHubAppTokenBroker({
      now: () => NOW,
      sign,
      exchange: (input) => {
        exchangeCalls.push(input);
        return Promise.resolve({});
      },
    });
    const error = await assertRejects(
      () => broker.issue(config(), request(), authority()),
      GitHubTokenBrokerError,
      "GITHUB_APP_SIGNING_FAILED",
    );
    const serialized = `${error.message}\n${error.stack}\n${
      JSON.stringify(error)
    }`;
    assertEquals(serialized.includes(PRIVATE_KEY), false);
    assertEquals(exchangeCalls, []);
  }
});

Deno.test("GitHub App broker denies TEST and PRODUCTION organization crossover", async () => {
  for (
    const [appConfig, tokenRequest, serverAuthority] of [
      [
        config("TEST"),
        request({ organization: "lorenzo-web-solutions" }),
        authority({ organization: "lorenzo-web-solutions" }),
      ],
      [
        config("PRODUCTION"),
        request({
          target: "PRODUCTION",
          organization: "lorenzo-web-solutions-lab",
        }),
        authority({
          target: "PRODUCTION",
          organization: "lorenzo-web-solutions-lab",
        }),
      ],
      [config("TEST"), request({ target: "PRODUCTION" }), authority()],
    ] as const
  ) {
    const test = harness();
    await assertRejects(
      () => test.broker.issue(appConfig, tokenRequest, serverAuthority),
      GitHubTokenBrokerError,
      "GITHUB_TOKEN_AUTHORITY_INVALID",
    );
    assertEquals(test.exchangeCalls, []);
  }
});

Deno.test("GitHub App broker rejects malformed or expired token responses", async () => {
  for (
    const response of [
      null,
      {},
      {
        expiresAt: "2026-09-13T12:55:00.000Z",
        repositorySelection: "selected",
        permissions: { metadata: "read", contents: "write" },
      },
      {
        token: INSTALLATION_TOKEN,
        repositorySelection: "selected",
        permissions: { metadata: "read", contents: "write" },
      },
      {
        token: "",
        expiresAt: "2026-09-13T12:55:00.000Z",
        repositorySelection: "selected",
        permissions: { metadata: "read", contents: "write" },
      },
      {
        token: INSTALLATION_TOKEN,
        expiresAt: "not-an-iso-timestamp",
        repositorySelection: "selected",
        permissions: { metadata: "read", contents: "write" },
      },
      {
        token: INSTALLATION_TOKEN,
        expiresAt: "2026-09-13T12:00:00.000Z",
        repositorySelection: "selected",
        permissions: { metadata: "read", contents: "write" },
      },
      {
        token: INSTALLATION_TOKEN,
        expiresAt: "2026-09-13T11:59:59.000Z",
        repositorySelection: "selected",
        permissions: { metadata: "read", contents: "write" },
      },
      {
        token: INSTALLATION_TOKEN,
        expiresAt: "2026-09-13T13:01:00.001Z",
        repositorySelection: "selected",
        permissions: { metadata: "read", contents: "write" },
      },
      {
        token: INSTALLATION_TOKEN,
        expiresAt: "2026-09-13T12:55:00.000Z",
        repositorySelection: null,
        permissions: { metadata: "read", contents: "write" },
      },
      {
        token: INSTALLATION_TOKEN,
        expiresAt: "2026-09-13T12:55:00.000Z",
        repositorySelection: 7,
        permissions: { metadata: "read", contents: "write" },
      },
      {
        token: INSTALLATION_TOKEN,
        expiresAt: "2026-09-13T12:55:00.000Z",
        repositorySelection: {},
        permissions: { metadata: "read", contents: "write" },
      },
      {
        token: INSTALLATION_TOKEN,
        expiresAt: "2026-09-13T12:55:00.000Z",
        repositorySelection: [],
        permissions: { metadata: "read", contents: "write" },
      },
      {
        token: INSTALLATION_TOKEN,
        expiresAt: "2026-09-13T12:55:00.000Z",
        repositorySelection: "invalid-value",
        permissions: { metadata: "read", contents: "write" },
      },
      {
        token: INSTALLATION_TOKEN,
        expiresAt: "2026-09-13T12:55:00.000Z",
        repositorySelection: "selected",
        permissions: {
          metadata: "read",
          contents: "write",
          workflows: "write",
        },
      },
    ]
  ) {
    const test = harness(response);
    await assertRejects(
      () => test.broker.issue(config(), request(), authority()),
      GitHubTokenBrokerError,
      "GITHUB_TOKEN_RESPONSE_INVALID",
    );
  }
});

Deno.test("GitHub App broker normalizes exchange failures without leaking credentials", async () => {
  for (
    const [failure, expectedCode] of [
      [new GitHubTokenExchangeFailure("TIMEOUT"), "GITHUB_TOKEN_TIMEOUT"],
      [
        new GitHubTokenExchangeFailure("RATE_LIMITED"),
        "GITHUB_TOKEN_RATE_LIMITED",
      ],
      [new GitHubTokenExchangeFailure("FORBIDDEN"), "GITHUB_TOKEN_FORBIDDEN"],
      [
        new GitHubTokenExchangeFailure("UNEXPECTED_REDIRECT"),
        "GITHUB_TOKEN_REDIRECT_DENIED",
      ],
      [
        new Error(`raw ${PRIVATE_KEY} ${INSTALLATION_TOKEN}`),
        "GITHUB_TOKEN_EXCHANGE_FAILED",
      ],
    ] as const
  ) {
    const output: unknown[][] = [];
    let appJwt = "";
    const broker = createGitHubAppTokenBroker({
      now: () => NOW,
      sign: () => Promise.resolve(new Uint8Array([1, 2, 3, 4])),
      exchange: (input) => {
        appJwt = input.appJwt;
        return Promise.reject(failure);
      },
    });
    const original = {
      log: console.log,
      warn: console.warn,
      error: console.error,
    };
    console.log = (...values) => output.push(values);
    console.warn = (...values) => output.push(values);
    console.error = (...values) => output.push(values);
    try {
      const error = await assertRejects(
        () => broker.issue(config(), request(), authority()),
        GitHubTokenBrokerError,
        expectedCode,
      );
      const serialized = `${error.message}\n${error.stack}\n${
        JSON.stringify(error)
      }`;
      assertEquals(serialized.includes(PRIVATE_KEY), false);
      assertEquals(serialized.includes(INSTALLATION_TOKEN), false);
      assertEquals(serialized.includes(appJwt), false);
      assertEquals(output, []);
    } finally {
      console.log = original.log;
      console.warn = original.warn;
      console.error = original.error;
    }
  }
});
