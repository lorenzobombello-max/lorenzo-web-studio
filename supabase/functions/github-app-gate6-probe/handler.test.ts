import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { createUnsignedTestJwt, handleGitHubAppGate6Probe } from "./handler.ts";
import { executeGitHubAppGate6Probe } from "./probe.ts";
import {
  Gate6ProbeConfigurationError,
  loadGate6ProbeConfig,
} from "./runtime.ts";

const NOW = Date.parse("2026-09-13T12:00:00.000Z");
const OWNER_ID = "c9bcd3ef-1e7e-4889-8a12-db827f1b97b0";
const APP_JWT = "synthetic.app.jwt";
const INSTALLATION_TOKEN = "ghs_synthetic_installation_token";

function jwt(overrides: Record<string, unknown> = {}) {
  return createUnsignedTestJwt({
    sub: OWNER_ID,
    role: "authenticated",
    aal: "aal2",
    exp: 4102444800,
    ...overrides,
  });
}

function request(body: unknown, token = jwt()) {
  return new Request("https://example.test/github-app-gate6-probe", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function dependencies() {
  let probeCalls = 0;
  return {
    get probeCalls() {
      return probeCalls;
    },
    value: {
      now: () => NOW,
      verifyUser: async () => ({ id: OWNER_ID }),
      authorizeOwner: async () => undefined,
      executeProbe: async () => {
        probeCalls += 1;
        return Object.freeze(
          {
            app: { id: "4932372", slug: "lws-repository-provider" },
            repository: {
              id: "987654321",
              full_name: "lorenzo-web-solutions/lws-website-starter",
              private: true,
              default_branch: "main",
            },
            installation: {
              repository_selection: "selected",
              permissions: { contents: "read", metadata: "read" },
            },
          } as const,
        );
      },
    },
  };
}

Deno.test("Gate 6 probe accepts only the exact fixed action DTO", async () => {
  const deps = dependencies();
  const accepted = await handleGitHubAppGate6Probe(
    request({ action: "run_gate6_probe" }),
    deps.value,
  );
  assertEquals(accepted.status, 200);
  assertEquals(deps.probeCalls, 1);

  for (
    const body of [
      {},
      { action: "run_gate6_probe", owner: "attacker" },
      { action: "run_gate6_probe", repository: "other" },
      { action: "run_gate6_probe", installation_id: "1" },
      { action: "run_gate6_probe", permissions: {} },
      { action: "run_gate6_probe", url: "https://example.test" },
      { action: "delete_repository" },
    ]
  ) {
    const response = await handleGitHubAppGate6Probe(request(body), deps.value);
    assertEquals(response.status, 400);
  }
  assertEquals(deps.probeCalls, 1);
});

Deno.test("Gate 6 probe requires a verified human owner with AAL2", async () => {
  for (
    const token of [
      "not-a-jwt",
      jwt({ role: "service_role" }),
      jwt({ aal: "aal1" }),
      jwt({ exp: 1 }),
    ]
  ) {
    const deps = dependencies();
    const response = await handleGitHubAppGate6Probe(
      request({ action: "run_gate6_probe" }, token),
      deps.value,
    );
    assertEquals([401, 403].includes(response.status), true);
    assertEquals(deps.probeCalls, 0);
  }

  const denied = dependencies();
  denied.value.authorizeOwner = async () => {
    throw new Error("OWNER_REQUIRED");
  };
  const response = await handleGitHubAppGate6Probe(
    request({ action: "run_gate6_probe" }),
    denied.value,
  );
  assertEquals(response.status, 403);
  assertEquals(denied.probeCalls, 0);
});

Deno.test("Gate 6 response is exact, no-store, and contains no credentials", async () => {
  const deps = dependencies();
  const response = await handleGitHubAppGate6Probe(
    request({ action: "run_gate6_probe" }),
    deps.value,
  );
  const text = await response.text();
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(JSON.parse(text), {
    ok: true,
    code: "GITHUB_APP_GATE6_PROBE_PASSED",
    result: await deps.value.executeProbe(),
  });
  for (const secret of [APP_JWT, INSTALLATION_TOKEN, "PRIVATE KEY", "Bearer"]) {
    assertEquals(text.includes(secret), false);
  }
});

Deno.test("Gate 6 transport uses only GET /app and one exact repository token", async () => {
  const calls: Array<{ url: string; method: string; authorization: string }> =
    [];
  const result = await executeGitHubAppGate6Probe({
    appId: "4932372",
    installationId: "161436785",
    privateKey: "synthetic-private-key",
    repositoryId: "987654321",
    repositoryOwner: "lorenzo-web-solutions",
    repositoryName: "lws-website-starter",
    signAppJwt: async () => APP_JWT,
    fetch: async (input, init) => {
      const call = new Request(input, init);
      calls.push({
        url: call.url,
        method: call.method,
        authorization: call.headers.get("authorization") || "",
      });
      const path = new URL(call.url).pathname;
      if (path === "/app") {
        return Response.json({ id: 4932372, slug: "lws-repository-provider" });
      }
      if (path.endsWith("/access_tokens")) {
        const body = await call.json();
        assertEquals(body, {
          repository_ids: [987654321],
          permissions: { contents: "read", metadata: "read" },
        });
        return Response.json({
          token: INSTALLATION_TOKEN,
          expires_at: "2026-09-13T12:55:00.000Z",
          repository_selection: "selected",
          permissions: { contents: "read", metadata: "read" },
        });
      }
      if (path === "/repos/lorenzo-web-solutions/lws-website-starter") {
        return Response.json({
          id: 987654321,
          full_name: "lorenzo-web-solutions/lws-website-starter",
          private: true,
          default_branch: "main",
        });
      }
      return new Response(null, { status: 500 });
    },
  });

  assertEquals(
    calls.map(({ url, method }) => [new URL(url).pathname, method]),
    [
      ["/app", "GET"],
      ["/app/installations/161436785/access_tokens", "POST"],
      ["/repos/lorenzo-web-solutions/lws-website-starter", "GET"],
    ],
  );
  assertEquals(calls[0].authorization, `Bearer ${APP_JWT}`);
  assertEquals(calls[2].authorization, `Bearer ${INSTALLATION_TOKEN}`);
  assertEquals(
    result.repository.full_name,
    "lorenzo-web-solutions/lws-website-starter",
  );
  assertEquals(JSON.stringify(result).includes(INSTALLATION_TOKEN), false);
});

Deno.test("Gate 6 configuration requires the provider to remain disabled", async () => {
  const values = new Map([
    ["LWS_GITHUB_PROVIDER_ENABLED", "false"],
    ["LWS_GITHUB_APP_ID", "4932372"],
    ["LWS_GITHUB_APP_INSTALLATION_ID", "161436785"],
    ["LWS_GITHUB_TEMPLATE_REPOSITORY_ID", "987654321"],
    ["LWS_GITHUB_TEMPLATE_OWNER", "lorenzo-web-solutions"],
    ["LWS_GITHUB_TEMPLATE_NAME", "lws-website-starter"],
    [
      "LWS_GITHUB_APP_PRIVATE_KEY",
      `-----BEGIN PRIVATE KEY-----\n${
        "A".repeat(64)
      }\n-----END PRIVATE KEY-----`,
    ],
  ]);
  const environment = { get: (name: string) => values.get(name) };
  const config = loadGate6ProbeConfig(environment);
  assertEquals(Object.keys(config).includes("privateKey"), false);
  assertEquals(JSON.stringify(config).includes("PRIVATE KEY"), false);

  for (const enabled of [undefined, "", "true", "TRUE"]) {
    if (enabled === undefined) values.delete("LWS_GITHUB_PROVIDER_ENABLED");
    else values.set("LWS_GITHUB_PROVIDER_ENABLED", enabled);
    await assertRejects(
      async () => loadGate6ProbeConfig(environment),
      Gate6ProbeConfigurationError,
    );
  }
});

Deno.test("Gate 6 transport fails closed for HTTP, malformed, network, and timeout failures", async () => {
  const base = {
    appId: "4932372",
    installationId: "161436785",
    privateKey: "synthetic-private-key",
    repositoryId: "987654321",
    repositoryOwner: "lorenzo-web-solutions",
    repositoryName: "lws-website-starter",
    signAppJwt: async () => APP_JWT,
  };
  const failures: Array<
    (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>
  > = [
    async () => new Response("unauthorized", { status: 401 }),
    async () => new Response("forbidden", { status: 403 }),
    async () => new Response("not-json", { status: 200 }),
    async () => {
      throw new Error("network details must not escape");
    },
    (_input, init) =>
      new Promise((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () =>
          reject(new DOMException("aborted", "AbortError")));
      }),
  ];

  for (const fetcher of failures) {
    const error = await assertRejects(() =>
      executeGitHubAppGate6Probe({
        ...base,
        fetch: fetcher,
        timeoutMilliseconds: 1,
      })
    );
    assertEquals(error instanceof Error, true);
    assertEquals((error as Error).message, "GITHUB_APP_GATE6_PROBE_FAILED");
    assertEquals(JSON.stringify(error).includes(APP_JWT), false);
  }
});
