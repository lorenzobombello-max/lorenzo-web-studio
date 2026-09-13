import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  GITHUB_CONFIGURATION_INVALID,
  GITHUB_PROVIDER_DISABLED,
  GitHubAppConfigurationError,
  GitHubProviderDisabledError,
  type GitHubProviderEnvironment,
  loadGitHubAppConfig,
} from "./github-app-config.ts";

const privateKey = [
  "-----BEGIN " + "PRIVATE KEY-----",
  "QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFB",
  "-----END " + "PRIVATE KEY-----",
].join("\n");

function environment(
  overrides: Record<string, string | undefined> = {},
): GitHubProviderEnvironment {
  const values: Record<string, string | undefined> = {
    LWS_GITHUB_PROVIDER_ENABLED: "true",
    LWS_GITHUB_PROVIDER_TARGET: "TEST",
    LWS_GITHUB_APP_ID: "123456",
    LWS_GITHUB_APP_INSTALLATION_ID: "654321",
    LWS_GITHUB_TEST_ORGANIZATION: "lws-provider-test",
    LWS_GITHUB_PRODUCTION_ORGANIZATION: "lws-production",
    LWS_GITHUB_TEMPLATE_OWNER: "lws-provider-test",
    LWS_GITHUB_TEMPLATE_NAME: "lws-website-starter",
    LWS_GITHUB_TEMPLATE_REPOSITORY_ID: "987654321",
    LWS_GITHUB_STARTER_VERSION: "1.0.0",
    LWS_GITHUB_STARTER_COMMIT_SHA: "a".repeat(40),
    LWS_GITHUB_APP_PRIVATE_KEY: privateKey,
    ...overrides,
  };
  return Object.freeze({ get: (name: string) => values[name] });
}

function assertDisabled(source: GitHubProviderEnvironment): void {
  const error = assertThrows(
    () => loadGitHubAppConfig(source),
    GitHubProviderDisabledError,
    GITHUB_PROVIDER_DISABLED,
  );
  assertEquals(error.code, GITHUB_PROVIDER_DISABLED);
}

function assertInvalid(source: GitHubProviderEnvironment): void {
  const error = assertThrows(
    () => loadGitHubAppConfig(source),
    GitHubAppConfigurationError,
    GITHUB_CONFIGURATION_INVALID,
  );
  assertEquals(error.code, GITHUB_CONFIGURATION_INVALID);
}

Deno.test("GitHub provider configuration is disabled by default and accepts only an exact enabled flag", () => {
  assertDisabled(environment({ LWS_GITHUB_PROVIDER_ENABLED: undefined }));
  assertDisabled(environment({ LWS_GITHUB_PROVIDER_ENABLED: "false" }));
  for (
    const value of [
      "yes",
      "TRUE",
      " true",
      "true ",
      " false",
      "False",
      "1",
      "0",
    ]
  ) {
    assertInvalid(environment({ LWS_GITHUB_PROVIDER_ENABLED: value }));
  }
});

Deno.test("GitHub provider configuration returns one frozen test-island binding", () => {
  const config = loadGitHubAppConfig(environment());

  assertEquals({ ...config }, {
    enabled: true,
    target: "TEST",
    appId: "123456",
    installationId: "654321",
    organization: "lws-provider-test",
    templateOwner: "lws-provider-test",
    templateName: "lws-website-starter",
    templateRepositoryId: "987654321",
    starterVersion: "1.0.0",
    starterCommitSha: "a".repeat(40),
  });
  assertEquals(config.privateKey, privateKey);
  assertEquals(Object.keys(config).includes("privateKey"), false);
  assertEquals(JSON.stringify(config).includes(privateKey), false);
  assertEquals(Object.isFrozen(config), true);
});

Deno.test("GitHub provider configuration normalizes Windows PEM lines and trims scalar bindings", () => {
  const config = loadGitHubAppConfig(environment({
    LWS_GITHUB_APP_ID: " 123456 ",
    LWS_GITHUB_STARTER_COMMIT_SHA: ` ${"a".repeat(40)} `,
    LWS_GITHUB_APP_PRIVATE_KEY: privateKey.replaceAll("\n", "\r\n"),
  }));

  assertEquals(config.appId, "123456");
  assertEquals(config.starterCommitSha, "a".repeat(40));
  assertEquals(config.privateKey, privateKey);
});

Deno.test("GitHub provider configuration selects production independently from the test organization", () => {
  const config = loadGitHubAppConfig(environment({
    LWS_GITHUB_PROVIDER_TARGET: "PRODUCTION",
    LWS_GITHUB_TEMPLATE_OWNER: "lws-production",
  }));

  assertEquals(config.target, "PRODUCTION");
  assertEquals(config.organization, "lws-production");
  assertEquals(config.templateOwner, "lws-production");
});

Deno.test("GitHub provider configuration rejects every missing required binding", () => {
  for (
    const name of [
      "LWS_GITHUB_PROVIDER_TARGET",
      "LWS_GITHUB_APP_ID",
      "LWS_GITHUB_APP_INSTALLATION_ID",
      "LWS_GITHUB_TEST_ORGANIZATION",
      "LWS_GITHUB_PRODUCTION_ORGANIZATION",
      "LWS_GITHUB_TEMPLATE_OWNER",
      "LWS_GITHUB_TEMPLATE_NAME",
      "LWS_GITHUB_TEMPLATE_REPOSITORY_ID",
      "LWS_GITHUB_STARTER_VERSION",
      "LWS_GITHUB_STARTER_COMMIT_SHA",
      "LWS_GITHUB_APP_PRIVATE_KEY",
    ]
  ) {
    assertInvalid(environment({ [name]: undefined }));
    assertInvalid(environment({ [name]: "" }));
  }
});

Deno.test("GitHub provider configuration rejects malformed identifiers and release provenance", () => {
  for (
    const overrides of [
      { LWS_GITHUB_PROVIDER_TARGET: "STAGING" },
      { LWS_GITHUB_APP_ID: "0" },
      { LWS_GITHUB_APP_ID: "12x" },
      { LWS_GITHUB_APP_INSTALLATION_ID: "-1" },
      { LWS_GITHUB_TEST_ORGANIZATION: "../test" },
      { LWS_GITHUB_PRODUCTION_ORGANIZATION: "lws-provider-test" },
      { LWS_GITHUB_TEMPLATE_OWNER: "another-organization" },
      { LWS_GITHUB_TEMPLATE_NAME: ".hidden" },
      { LWS_GITHUB_TEMPLATE_REPOSITORY_ID: "not-numeric" },
      { LWS_GITHUB_STARTER_VERSION: "latest" },
      { LWS_GITHUB_STARTER_COMMIT_SHA: "ABCDEF".repeat(7) },
      { LWS_GITHUB_APP_PRIVATE_KEY: "not-a-private-key" },
      {
        LWS_GITHUB_APP_PRIVATE_KEY: [
          "-----BEGIN " + "RSA PRIVATE KEY-----",
          privateKey.split("\n")[1],
          "-----END " + "RSA PRIVATE KEY-----",
        ].join("\n"),
      },
    ]
  ) {
    assertInvalid(environment(overrides));
  }
});

Deno.test("GitHub provider configuration rejects PAT and OAuth-like credentials without disclosure", () => {
  const sensitiveValues = [
    "gh" + "p_examplePersonalAccessToken",
    "github" + "_pat_exampleFineGrainedToken",
    "gh" + "o_exampleOAuthToken",
    "gh" + "u_exampleUserToken",
  ];
  const output: unknown[][] = [];
  const original = {
    log: console.log,
    warn: console.warn,
    error: console.error,
  };
  console.log = (...values) => output.push(values);
  console.warn = (...values) => output.push(values);
  console.error = (...values) => output.push(values);
  try {
    for (const sensitiveValue of sensitiveValues) {
      const error = assertThrows(
        () =>
          loadGitHubAppConfig(environment({
            LWS_GITHUB_APP_PRIVATE_KEY: sensitiveValue,
          })),
        GitHubAppConfigurationError,
        GITHUB_CONFIGURATION_INVALID,
      );
      assertEquals(error.message.includes(sensitiveValue), false);
      assertEquals(error.stack?.includes(sensitiveValue) ?? false, false);
    }
    assertEquals(output, []);
  } finally {
    console.log = original.log;
    console.warn = original.warn;
    console.error = original.error;
  }
});
