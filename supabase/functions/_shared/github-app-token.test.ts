import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import type { GitHubAppConfig } from "./github-app-config.ts";
import {
  createGitHubAppTokenBroker,
  GitHubTokenBrokerError,
  GitHubTokenExchangeFailure,
  type GitHubTokenRequest,
} from "./github-app-token.ts";

const NOW = Date.parse("2026-09-13T12:00:00.000Z");
const CONTEXT_ID = "0198abcd-1234-7000-8000-0123456789ab";
const CUSTOMER_REPOSITORY_ID = "987654322";
const PRIVATE_KEY = [
  "-----BEGIN " + "PRIVATE KEY-----",
  "QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFB",
  "-----END " + "PRIVATE KEY-----",
].join("\n");
const INSTALLATION_TOKEN = "gh" + "s_synthetic_installation_token_value";

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
    operation: "REPOSITORY_CONTENTS",
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

Deno.test("GitHub App broker derives exact permissions for template generation", async () => {
  const test = harness({
    token: INSTALLATION_TOKEN,
    expiresAt: "2026-09-13T12:55:00.000Z",
    repositorySelection: "selected",
    permissions: { metadata: "read", administration: "write" },
  });
  const templateRequest = request({
    operation: "TEMPLATE_GENERATION",
    repositoryIds: ["987654321"],
  });

  await test.broker.issue(
    config(),
    templateRequest,
    authority({ repositoryIds: ["987654321"] }),
  );

  assertEquals(
    (test.exchangeCalls[0] as Record<string, unknown>).permissions,
    { metadata: "read", administration: "write" },
  );
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
        request({
          operation: "TEMPLATE_GENERATION",
          repositoryIds: [CUSTOMER_REPOSITORY_ID],
        }),
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

Deno.test("GitHub App broker rejects malformed, expired or overly long token responses", async () => {
  for (
    const response of [
      null,
      {},
      {
        token: "",
        expiresAt: "2026-09-13T12:55:00.000Z",
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
        expiresAt: "2026-09-13T13:00:01.000Z",
        repositorySelection: "selected",
        permissions: { metadata: "read", contents: "write" },
      },
      {
        token: INSTALLATION_TOKEN,
        expiresAt: "2026-09-13T12:55:00.000Z",
        repositorySelection: "all",
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
