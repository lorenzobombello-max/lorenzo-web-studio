import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  createUnsignedTestJwt,
  type GitHubAppGate6ProbeDependencies,
  handleGitHubAppGate6Probe,
} from "./handler.ts";
import {
  executeGitHubAppGate6Probe,
  GitHubAppGate6ProbeError,
} from "./probe.ts";
import {
  createGitHubAppGate6ProbeInput,
  Gate6PreProbeError,
  runGate6PreProbePipeline,
} from "./preprobe.ts";
import {
  diagnoseGate6ProbeConfiguration,
  Gate6ProbeConfigurationError,
  loadGate6ProbeConfig,
  signGitHubAppJwt,
} from "./runtime.ts";

const NOW = Date.parse("2026-09-13T12:00:00.000Z");
const OWNER_ID = "c9bcd3ef-1e7e-4889-8a12-db827f1b97b0";
const APP_JWT = "synthetic.app.jwt";
const INSTALLATION_TOKEN = "ghs_synthetic_installation_token";
let SYNTHETIC_PRIVATE_KEY = "";

function pem(label: string, bytes: Uint8Array, newline = "\n"): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  const encoded = btoa(binary).match(/.{1,64}/g)?.join(newline) || "";
  return `-----BEGIN ${label}-----${newline}${encoded}${newline}-----END ${label}-----`;
}

function readDerLength(bytes: Uint8Array, offset: number) {
  const first = bytes[offset];
  if ((first & 0x80) === 0) return { length: first, bytes: 1 };
  const count = first & 0x7f;
  let length = 0;
  for (let index = 0; index < count; index += 1) {
    length = length * 256 + bytes[offset + 1 + index];
  }
  return { length, bytes: count + 1 };
}

function extractPkcs1(pkcs8: Uint8Array): Uint8Array {
  const outerLength = readDerLength(pkcs8, 1);
  let offset = 1 + outerLength.bytes;
  for (let child = 0; child < 3; child += 1) {
    const tag = pkcs8[offset];
    const length = readDerLength(pkcs8, offset + 1);
    const contentOffset = offset + 1 + length.bytes;
    if (child === 2 && tag === 0x04) {
      return pkcs8.slice(contentOffset, contentOffset + length.length);
    }
    offset = contentOffset + length.length;
  }
  throw new Error("SYNTHETIC_PKCS8_INVALID");
}

const syntheticKeyPair = await crypto.subtle.generateKey(
  {
    name: "RSASSA-PKCS1-v1_5",
    modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]),
    hash: "SHA-256",
  },
  true,
  ["sign", "verify"],
);
const syntheticPkcs8Bytes = new Uint8Array(
  await crypto.subtle.exportKey("pkcs8", syntheticKeyPair.privateKey),
);
const SYNTHETIC_PKCS8_PEM = pem("PRIVATE KEY", syntheticPkcs8Bytes);
const SYNTHETIC_PKCS1_PEM = pem(
  "RSA PRIVATE KEY",
  extractPkcs1(syntheticPkcs8Bytes),
);
SYNTHETIC_PRIVATE_KEY = SYNTHETIC_PKCS8_PEM;

function configurationValues() {
  return new Map<string, string>([
    ["SUPABASE_URL", "https://xcsptvntvrizwhskaphr.supabase.co"],
    ["SUPABASE_PUBLISHABLE_KEYS", '{"default":"sb_publishable_synthetic"}'],
    ["LWS_GITHUB_PROVIDER_ENABLED", "false"],
    ["LWS_GITHUB_APP_ID", "4932372"],
    ["LWS_GITHUB_APP_INSTALLATION_ID", "161436785"],
    ["LWS_GITHUB_TEMPLATE_REPOSITORY_ID", "1368684860"],
    ["LWS_GITHUB_TEMPLATE_OWNER", "lorenzo-web-solutions"],
    ["LWS_GITHUB_TEMPLATE_NAME", "lws-website-starter"],
    ["LWS_GITHUB_APP_PRIVATE_KEY", SYNTHETIC_PRIVATE_KEY],
  ]);
}

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
  let diagnosticCalls = 0;
  return {
    get probeCalls() {
      return probeCalls;
    },
    get diagnosticCalls() {
      return diagnosticCalls;
    },
    value: {
      now: () => NOW,
      verifyUser: async () => ({ id: OWNER_ID }),
      authorizeOwner: async () => undefined,
      diagnoseConfiguration: async () => {
        diagnosticCalls += 1;
        return {
          configuration_valid: false,
          failed_check: "PRIVATE_KEY_PEM_INVALID",
        } as const;
      },
      executeProbe: async () => {
        probeCalls += 1;
        return Object.freeze(
          {
            app: { id: "4932372", slug: "lws-repository-provider" },
            repository: {
              id: "1368684860",
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
      projectProbeResult: (
        result: Parameters<
          GitHubAppGate6ProbeDependencies["projectProbeResult"]
        >[0],
      ) => result,
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

Deno.test("Gate 6 configuration diagnosis is owner-only and never calls GitHub", async () => {
  const authorized = dependencies();
  const response = await handleGitHubAppGate6Probe(
    request({ action: "diagnose_configuration" }),
    authorized.value,
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    ok: true,
    code: "GATE6_CONFIGURATION_DIAGNOSIS",
    result: {
      configuration_valid: false,
      failed_check: "PRIVATE_KEY_PEM_INVALID",
    },
  });
  assertEquals(authorized.diagnosticCalls, 1);
  assertEquals(authorized.probeCalls, 0);

  const unauthorized = dependencies();
  const denied = await handleGitHubAppGate6Probe(
    request({ action: "diagnose_configuration" }, jwt({ aal: "aal1" })),
    unauthorized.value,
  );
  assertEquals(denied.status, 403);
  assertEquals(unauthorized.diagnosticCalls, 0);
  assertEquals(unauthorized.probeCalls, 0);
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
    repositoryId: "1368684860",
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
          repository_ids: [1368684860],
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
          id: 1368684860,
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
  const values = configurationValues();
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

Deno.test("Gate 6 configuration diagnosis returns only fixed check names", () => {
  const cases: Array<readonly [string, string | null, string]> = [
    ["SUPABASE_URL", null, "SUPABASE_URL_INVALID"],
    ["SUPABASE_PUBLISHABLE_KEYS", null, "PUBLISHABLE_KEYS_MISSING"],
    ["SUPABASE_PUBLISHABLE_KEYS", "not-json", "PUBLISHABLE_KEYS_JSON_INVALID"],
    ["SUPABASE_PUBLISHABLE_KEYS", "{}", "PUBLISHABLE_KEYS_DEFAULT_MISSING"],
    [
      "SUPABASE_PUBLISHABLE_KEYS",
      '{"default":"legacy-anon-key"}',
      "PUBLISHABLE_KEYS_DEFAULT_INVALID",
    ],
    ["LWS_GITHUB_PROVIDER_ENABLED", "true", "PROVIDER_DISABLED_REQUIRED"],
    ["LWS_GITHUB_APP_ID", "invalid", "APP_ID_INVALID"],
    ["LWS_GITHUB_APP_INSTALLATION_ID", "invalid", "INSTALLATION_ID_INVALID"],
    ["LWS_GITHUB_TEMPLATE_REPOSITORY_ID", "invalid", "REPOSITORY_ID_INVALID"],
    ["LWS_GITHUB_TEMPLATE_REPOSITORY_ID", "987654321", "REPOSITORY_ID_INVALID"],
    ["LWS_GITHUB_TEMPLATE_OWNER", "", "TEMPLATE_OWNER_INVALID"],
    ["LWS_GITHUB_TEMPLATE_NAME", "", "TEMPLATE_NAME_INVALID"],
    ["LWS_GITHUB_APP_PRIVATE_KEY", null, "PRIVATE_KEY_MISSING"],
    ["LWS_GITHUB_APP_PRIVATE_KEY", "not-pem", "PRIVATE_KEY_PEM_INVALID"],
  ];

  for (const [name, value, failedCheck] of cases) {
    const values = configurationValues();
    if (value === null) values.delete(name);
    else values.set(name, value);
    const diagnosis = diagnoseGate6ProbeConfiguration({
      get: (key) => values.get(key),
    });
    assertEquals(diagnosis.configuration_valid, false);
    assertEquals(diagnosis.failed_check, failedCheck);
    assertEquals(
      JSON.stringify(diagnosis).includes(SYNTHETIC_PRIVATE_KEY),
      false,
    );
    assertEquals(
      JSON.stringify(diagnosis).includes("sb_publishable_synthetic"),
      false,
    );
  }
});

Deno.test("Gate 6 accepts and signs with synthetic PKCS1 and PKCS8 RSA keys", async () => {
  for (
    const privateKey of [
      SYNTHETIC_PKCS1_PEM,
      SYNTHETIC_PKCS1_PEM.replaceAll("\n", "\r\n"),
      SYNTHETIC_PKCS8_PEM,
      SYNTHETIC_PKCS8_PEM.replaceAll("\n", "\r\n"),
    ]
  ) {
    const values = configurationValues();
    values.set("LWS_GITHUB_APP_PRIVATE_KEY", privateKey);
    const diagnosis = diagnoseGate6ProbeConfiguration({
      get: (key) => values.get(key),
    });
    assertEquals(diagnosis.configuration_valid, true);
    assertEquals(diagnosis.failed_check, null);
    const signed = await signGitHubAppJwt(privateKey, "4932372", NOW);
    assertEquals(signed.split(".").length, 3);
    assertEquals(signed.includes(privateKey), false);
  }
});

Deno.test("Gate 6 rejects malformed and wrong-type private key PEM", () => {
  const cases = [
    SYNTHETIC_PKCS1_PEM.replace("-----BEGIN RSA PRIVATE KEY-----\n", ""),
    SYNTHETIC_PKCS1_PEM.replace("\n-----END RSA PRIVATE KEY-----", ""),
    "-----BEGIN RSA PRIVATE KEY-----\nnot+base64!\n-----END RSA PRIVATE KEY-----",
    pem("PUBLIC KEY", syntheticPkcs8Bytes),
  ];
  for (const privateKey of cases) {
    const values = configurationValues();
    values.set("LWS_GITHUB_APP_PRIVATE_KEY", privateKey);
    const diagnosis = diagnoseGate6ProbeConfiguration({
      get: (key) => values.get(key),
    });
    assertEquals(diagnosis.configuration_valid, false);
    assertEquals(diagnosis.failed_check, "PRIVATE_KEY_PEM_INVALID");
    assertEquals(JSON.stringify(diagnosis).includes(privateKey), false);
  }
});

Deno.test("malformed private key reaches no GitHub fetch", async () => {
  let fetchCalls = 0;
  await assertRejects(() =>
    executeGitHubAppGate6Probe({
      appId: "4932372",
      installationId: "161436785",
      privateKey:
        "-----BEGIN RSA PRIVATE KEY-----\ninvalid\n-----END RSA PRIVATE KEY-----",
      repositoryId: "1368684860",
      repositoryOwner: "lorenzo-web-solutions",
      repositoryName: "lws-website-starter",
      signAppJwt: (privateKey, appId) =>
        signGitHubAppJwt(privateKey, appId, NOW),
      fetch: async () => {
        fetchCalls += 1;
        return new Response(null, { status: 500 });
      },
    })
  );
  assertEquals(fetchCalls, 0);
});

Deno.test("Gate 6 transport fails closed for HTTP, malformed, network, and timeout failures", async () => {
  const base = {
    appId: "4932372",
    installationId: "161436785",
    privateKey: "synthetic-private-key",
    repositoryId: "1368684860",
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

Deno.test("Gate 6 transport rejects a different numeric repository ID before fetch", async () => {
  let fetchCalls = 0;
  await assertRejects(() =>
    executeGitHubAppGate6Probe({
      appId: "4932372",
      installationId: "161436785",
      privateKey: "synthetic-private-key",
      repositoryId: "987654321",
      repositoryOwner: "lorenzo-web-solutions",
      repositoryName: "lws-website-starter",
      signAppJwt: async () => APP_JWT,
      fetch: async () => {
        fetchCalls += 1;
        return new Response(null, { status: 500 });
      },
    })
  );
  assertEquals(fetchCalls, 0);
});

const VALID_APP_RESPONSE = Object.freeze({
  id: 4932372,
  slug: "lws-repository-provider",
});
const VALID_TOKEN_RESPONSE = Object.freeze({
  token: INSTALLATION_TOKEN,
  repository_selection: "selected",
  permissions: { contents: "read", metadata: "read" },
});
const VALID_REPOSITORY_RESPONSE = Object.freeze({
  id: 1368684860,
  full_name: "lorenzo-web-solutions/lws-website-starter",
  private: true,
  default_branch: "main",
});

function phaseProbeInput(): Parameters<typeof executeGitHubAppGate6Probe>[0] {
  return {
    appId: "4932372",
    installationId: "161436785",
    privateKey: "synthetic-private-key",
    repositoryId: "1368684860",
    repositoryOwner: "lorenzo-web-solutions",
    repositoryName: "lws-website-starter",
    signAppJwt: async () => APP_JWT,
    fetch: async (input: RequestInfo | URL, _init?: RequestInit) => {
      const path = new URL(String(input)).pathname;
      if (path === "/app") return Response.json(VALID_APP_RESPONSE);
      if (path.endsWith("/access_tokens")) {
        return Response.json(VALID_TOKEN_RESPONSE);
      }
      return Response.json(VALID_REPOSITORY_RESPONSE);
    },
  };
}

async function assertFailedPhase(
  overrides: Partial<ReturnType<typeof phaseProbeInput>>,
  failedPhase: string,
  httpStatusClass?: string,
) {
  const error = await assertRejects(() =>
    executeGitHubAppGate6Probe({
      ...phaseProbeInput(),
      ...overrides,
    })
  ) as GitHubAppGate6ProbeError;
  assertEquals(error instanceof GitHubAppGate6ProbeError, true);
  assertEquals(error.message, "GITHUB_APP_GATE6_PROBE_FAILED");
  assertEquals(error.failedPhase, failedPhase);
  assertEquals(error.httpStatusClass, httpStatusClass);
  const serialized = JSON.stringify(error);
  for (
    const secret of [
      APP_JWT,
      INSTALLATION_TOKEN,
      "Authorization",
      "PRIVATE KEY",
      "network-secret",
      "raw-github-body",
    ]
  ) {
    assertEquals(serialized.includes(secret), false);
  }
}

function transportFailure(mode: "http" | "network" | "timeout") {
  if (mode === "http") {
    return async () => new Response("raw-github-body", { status: 401 });
  }
  if (mode === "network") {
    return async () => {
      throw new Error("network-secret");
    };
  }
  return (_input: RequestInfo | URL, init?: RequestInit) =>
    new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener(
        "abort",
        () => reject(new DOMException("network-secret", "AbortError")),
      );
    });
}

Deno.test("Gate 6 local failures map to fixed request and signing phases", async () => {
  await assertFailedPhase(
    {
      signAppJwt: async () => {
        throw new Error("PRIVATE KEY signing detail");
      },
    },
    "APP_JWT_SIGNING",
  );

  for (const mode of ["http", "network", "timeout"] as const) {
    await assertFailedPhase(
      {
        fetch: transportFailure(mode),
        ...(mode === "timeout" ? { timeoutMilliseconds: 1 } : {}),
      },
      "GET_APP_REQUEST",
      mode === "http" ? "4xx" : undefined,
    );
  }

  for (const mode of ["http", "network", "timeout"] as const) {
    let calls = 0;
    const failure = transportFailure(mode);
    await assertFailedPhase(
      {
        timeoutMilliseconds: mode === "timeout" ? 1 : undefined,
        fetch: (input, init) => {
          calls += 1;
          return calls === 1
            ? Promise.resolve(Response.json(VALID_APP_RESPONSE))
            : failure(input, init);
        },
      },
      "INSTALLATION_TOKEN_REQUEST",
      mode === "http" ? "4xx" : undefined,
    );
  }

  let repositoryCalls = 0;
  await assertFailedPhase(
    {
      fetch: async () => {
        repositoryCalls += 1;
        if (repositoryCalls === 1) return Response.json(VALID_APP_RESPONSE);
        if (repositoryCalls === 2) return Response.json(VALID_TOKEN_RESPONSE);
        return new Response("raw-github-body", { status: 503 });
      },
    },
    "REPOSITORY_METADATA_REQUEST",
    "5xx",
  );
});

Deno.test("Gate 6 local failures map to fixed response validation phases", async () => {
  for (
    const appResponse of [
      new Response("raw-github-body"),
      Response.json({ ...VALID_APP_RESPONSE, id: 1 }),
    ]
  ) {
    await assertFailedPhase(
      { fetch: async () => appResponse.clone() },
      "GET_APP_RESPONSE_VALIDATION",
    );
  }

  for (
    const tokenResponse of [
      new Response("raw-github-body"),
      Response.json({
        ...VALID_TOKEN_RESPONSE,
        permissions: { contents: "write", metadata: "read" },
      }),
    ]
  ) {
    let calls = 0;
    await assertFailedPhase(
      {
        fetch: async () => {
          calls += 1;
          return calls === 1
            ? Response.json(VALID_APP_RESPONSE)
            : tokenResponse.clone();
        },
      },
      "INSTALLATION_TOKEN_RESPONSE_VALIDATION",
    );
  }

  await assertFailedPhase(
    {
      fetch: async (input) => {
        const path = new URL(String(input)).pathname;
        if (path === "/app") return Response.json(VALID_APP_RESPONSE);
        if (path.endsWith("/access_tokens")) {
          return Response.json(VALID_TOKEN_RESPONSE);
        }
        return Response.json({ ...VALID_REPOSITORY_RESPONSE, id: 1 });
      },
    },
    "REPOSITORY_METADATA_VALIDATION",
  );
});

Deno.test("Gate 6 failure response exposes only the fixed diagnostic boundary", async () => {
  const phases = [
    "APP_JWT_SIGNING",
    "GET_APP_REQUEST",
    "GET_APP_RESPONSE_VALIDATION",
    "INSTALLATION_TOKEN_REQUEST",
    "INSTALLATION_TOKEN_RESPONSE_VALIDATION",
    "REPOSITORY_METADATA_REQUEST",
    "REPOSITORY_METADATA_VALIDATION",
  ] as const;

  for (const failedPhase of phases) {
    const deps = dependencies();
    deps.value.executeProbe = async () => {
      throw new GitHubAppGate6ProbeError(failedPhase, "4xx");
    };
    const response = await handleGitHubAppGate6Probe(
      request({ action: "run_gate6_probe" }),
      deps.value,
    );
    assertEquals(response.status, 502);
    assertEquals(await response.json(), {
      ok: false,
      code: "GITHUB_APP_GATE6_PROBE_FAILED",
      failed_phase: failedPhase,
      http_status_class: "4xx",
    });
  }

  const deps = dependencies();
  deps.value.executeProbe = async () => {
    throw new Error("token=secret Authorization: Bearer secret stack");
  };
  const response = await handleGitHubAppGate6Probe(
    request({ action: "run_gate6_probe" }),
    deps.value,
  );
  const text = await response.text();
  assertEquals(JSON.parse(text), {
    ok: false,
    code: "GITHUB_APP_GATE6_PROBE_FAILED",
    failed_phase: "PROBE_INVOCATION",
  });
  for (const secret of ["token=secret", "Authorization", "Bearer", "stack"]) {
    assertEquals(text.includes(secret), false);
  }
});

Deno.test("Gate 6 classifies a caller verification exception before probe invocation", async () => {
  const deps = dependencies();
  deps.value.verifyUser = async () => {
    throw new Error("upstream caller verification detail");
  };
  const response = await handleGitHubAppGate6Probe(
    request({ action: "run_gate6_probe" }),
    deps.value,
  );
  assertEquals(response.status, 502);
  assertEquals(await response.json(), {
    ok: false,
    code: "GITHUB_APP_GATE6_PROBE_FAILED",
    failed_phase: "CALLER_VERIFICATION",
  });
  assertEquals(deps.probeCalls, 0);
});

Deno.test("Gate 6 classifies request, AAL2, and owner failures", async () => {
  const cases = [
    {
      request: request({ invalid: true }),
      mutate: (_deps: ReturnType<typeof dependencies>) => undefined,
      status: 400,
      phase: "REQUEST_PARSE",
    },
    {
      request: request({ action: "run_gate6_probe" }, jwt({ aal: "aal1" })),
      mutate: (_deps: ReturnType<typeof dependencies>) => undefined,
      status: 403,
      phase: "AAL2_VERIFICATION",
    },
    {
      request: request({ action: "run_gate6_probe" }),
      mutate: (deps: ReturnType<typeof dependencies>) => {
        deps.value.authorizeOwner = async () => {
          throw new Error("owner lookup detail");
        };
      },
      status: 403,
      phase: "OWNER_AUTHORIZATION",
    },
  ] as const;

  for (const testCase of cases) {
    const deps = dependencies();
    testCase.mutate(deps);
    const response = await handleGitHubAppGate6Probe(
      testCase.request,
      deps.value,
    );
    assertEquals(response.status, testCase.status);
    assertEquals(await response.json(), {
      ok: false,
      code: "GITHUB_APP_GATE6_PROBE_FAILED",
      failed_phase: testCase.phase,
    });
    assertEquals(deps.probeCalls, 0);
  }
});

function pipelineDependencies() {
  return {
    loadConfiguration: async () => "configuration",
    initializeSigner: async () => "signer",
    initializeDependencies: async () => "probe-dependencies",
    invokeProbe: async () => "probe-result",
  };
}

Deno.test("Gate 6 pipeline classifies every pre-probe preparation boundary", async () => {
  const cases = [
    ["loadConfiguration", "CONFIGURATION_LOAD"],
    ["initializeSigner", "PRIVATE_KEY_IMPORT_OR_SIGNER_INIT"],
    ["initializeDependencies", "PROBE_DEPENDENCY_INIT"],
    ["invokeProbe", "PROBE_INVOCATION"],
  ] as const;

  for (const [operation, failedPhase] of cases) {
    const deps = pipelineDependencies();
    deps[operation] = async () => {
      throw new Error(`${operation} secret detail`);
    };
    const error = await assertRejects(() =>
      runGate6PreProbePipeline(deps)
    ) as Gate6PreProbeError;
    assertEquals(error instanceof Gate6PreProbeError, true);
    assertEquals(error.message, "GITHUB_APP_GATE6_PROBE_FAILED");
    assertEquals(error.failedPhase, failedPhase);
    assertEquals(JSON.stringify(error).includes("secret detail"), false);
  }
});

Deno.test("Gate 6 pipeline preserves existing GitHub failure phases", async () => {
  const deps = pipelineDependencies();
  deps.invokeProbe = async () => {
    throw new GitHubAppGate6ProbeError("GET_APP_REQUEST", "5xx");
  };
  const error = await assertRejects(() =>
    runGate6PreProbePipeline(deps)
  ) as GitHubAppGate6ProbeError;
  assertEquals(error instanceof GitHubAppGate6ProbeError, true);
  assertEquals(error.failedPhase, "GET_APP_REQUEST");
  assertEquals(error.httpStatusClass, "5xx");
});

Deno.test("Gate 6 probe dependency initialization preserves the non-enumerable private key", () => {
  const config = loadGate6ProbeConfig({
    get: (name) => configurationValues().get(name),
  });
  const input = createGitHubAppGate6ProbeInput(
    config,
    async () => APP_JWT,
    async () => new Response(null, { status: 500 }),
  );
  assertEquals(Object.keys(config).includes("privateKey"), false);
  assertEquals(Object.keys(input).includes("privateKey"), false);
  assertEquals(input.privateKey, SYNTHETIC_PRIVATE_KEY);
  assertEquals(JSON.stringify(config).includes(SYNTHETIC_PRIVATE_KEY), false);
  assertEquals(JSON.stringify(input).includes(SYNTHETIC_PRIVATE_KEY), false);
});

Deno.test("Gate 6 classifies response projection and truly unexpected errors", async () => {
  const projection = dependencies();
  projection.value.projectProbeResult = () => {
    throw new Error("projection secret detail");
  };
  const projectionResponse = await handleGitHubAppGate6Probe(
    request({ action: "run_gate6_probe" }),
    projection.value,
  );
  assertEquals(await projectionResponse.json(), {
    ok: false,
    code: "GITHUB_APP_GATE6_PROBE_FAILED",
    failed_phase: "RESPONSE_PROJECTION",
  });

  const unexpected = dependencies();
  unexpected.value.now = () => {
    throw new Error("unexpected secret detail");
  };
  const unexpectedResponse = await handleGitHubAppGate6Probe(
    request({ action: "run_gate6_probe" }),
    unexpected.value,
  );
  assertEquals(await unexpectedResponse.json(), {
    ok: false,
    code: "GITHUB_APP_GATE6_PROBE_FAILED",
    failed_phase: "UNKNOWN_INTERNAL",
  });
});
