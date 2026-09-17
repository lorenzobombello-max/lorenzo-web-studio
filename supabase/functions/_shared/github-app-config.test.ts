import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  GITHUB_CONFIGURATION_INVALID,
  GITHUB_PROVIDER_DISABLED,
  GitHubAppConfigurationError,
  GitHubProviderDisabledError,
  type GitHubProviderEnvironment,
  loadGitHubAppConfig,
  loadGitHubTask13RuntimeConfig,
} from "./github-app-config.ts";

function pem(label: string, bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  const encoded = btoa(binary).match(/.{1,64}/g)?.join("\n") || "";
  return `-----BEGIN ${label}-----\n${encoded}\n-----END ${label}-----`;
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
const syntheticPkcs8Pem = pem("PRIVATE KEY", syntheticPkcs8Bytes);
const syntheticPkcs1Pem = pem(
  "RSA PRIVATE KEY",
  extractPkcs1(syntheticPkcs8Bytes),
);
const privateKey = syntheticPkcs8Pem;

function environment(
  overrides: Record<string, string | undefined> = {},
): GitHubProviderEnvironment {
  const values: Record<string, string | undefined> = {
    LWS_GITHUB_PROVIDER_ENABLED: "true",
    LWS_GITHUB_PROVIDER_TARGET: "TEST",
    LWS_GITHUB_APP_ID: "123456",
    LWS_GITHUB_APP_INSTALLATION_ID: "654321",
    LWS_GITHUB_LAB_INSTALLATION_ID: "765432",
    LWS_GITHUB_TEST_ORGANIZATION: "lws-provider-test",
    LWS_GITHUB_PRODUCTION_ORGANIZATION: "lws-production",
    LWS_GITHUB_TEMPLATE_OWNER: "lws-production",
    LWS_GITHUB_TEMPLATE_NAME: "lws-website-starter",
    LWS_GITHUB_TEMPLATE_REPOSITORY_ID: "987654321",
    LWS_GITHUB_STARTER_VERSION: "1.0.0",
    LWS_GITHUB_STARTER_COMMIT_SHA: "a".repeat(40),
    LWS_GITHUB_STARTER_TREE_SHA256: "b".repeat(64),
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
    installationId: "765432",
    organization: "lws-provider-test",
    templateOwner: "lws-production",
    templateName: "lws-website-starter",
    templateRepositoryId: "987654321",
    starterVersion: "1.0.0",
    starterCommitSha: "a".repeat(40),
    starterTreeSha256: "b".repeat(64),
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
    LWS_GITHUB_LAB_INSTALLATION_ID: undefined,
    LWS_GITHUB_TEMPLATE_OWNER: "lws-production",
  }));

  assertEquals(config.target, "PRODUCTION");
  assertEquals(config.installationId, "654321");
  assertEquals(config.organization, "lws-production");
  assertEquals(config.templateOwner, "lws-production");
});

Deno.test("GitHub provider configuration never falls back from TEST to the production installation", () => {
  assertInvalid(environment({ LWS_GITHUB_LAB_INSTALLATION_ID: undefined }));
  assertInvalid(environment({ LWS_GITHUB_LAB_INSTALLATION_ID: "" }));
  assertInvalid(environment({ LWS_GITHUB_LAB_INSTALLATION_ID: "654321" }));
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
      "LWS_GITHUB_STARTER_TREE_SHA256",
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
      { LWS_GITHUB_STARTER_TREE_SHA256: "ABCDEF".repeat(11) },
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

Deno.test("Task 13 runtime loads both fixed principals only while the global provider remains disabled", () => {
  const config = loadGitHubTask13RuntimeConfig(environment({
    LWS_GITHUB_PROVIDER_ENABLED: "false",
    LWS_GITHUB_APP_INSTALLATION_ID: "161436785",
    LWS_GITHUB_LAB_INSTALLATION_ID: "161461160",
    LWS_GITHUB_PRODUCTION_ORGANIZATION: "lorenzo-web-solutions",
    LWS_GITHUB_TEST_ORGANIZATION: "lorenzo-web-solutions-lab",
    LWS_GITHUB_TEMPLATE_OWNER: "lorenzo-web-solutions",
  }));

  assertEquals(config.production.target, "PRODUCTION");
  assertEquals(config.production.installationId, "161436785");
  assertEquals(config.lab.target, "TEST");
  assertEquals(config.lab.installationId, "161461160");
  assertEquals(Object.keys(config.production).includes("privateKey"), false);
  assertEquals(Object.keys(config.lab).includes("privateKey"), false);
});

Deno.test("Task 13 normalizes PKCS1 and PKCS8 to one non-enumerable signer input", () => {
  for (const input of [syntheticPkcs1Pem, syntheticPkcs8Pem]) {
    const config = loadGitHubTask13RuntimeConfig(environment({
      LWS_GITHUB_PROVIDER_ENABLED: "false",
      LWS_GITHUB_APP_INSTALLATION_ID: "161436785",
      LWS_GITHUB_LAB_INSTALLATION_ID: "161461160",
      LWS_GITHUB_PRODUCTION_ORGANIZATION: "lorenzo-web-solutions",
      LWS_GITHUB_TEST_ORGANIZATION: "lorenzo-web-solutions-lab",
      LWS_GITHUB_TEMPLATE_OWNER: "lorenzo-web-solutions",
      LWS_GITHUB_APP_PRIVATE_KEY: input,
    }));

    assertEquals(config.production.privateKey, syntheticPkcs8Pem);
    assertEquals(config.lab.privateKey, syntheticPkcs8Pem);
    assertEquals(Object.keys(config.production).includes("privateKey"), false);
    assertEquals(Object.keys(config.lab).includes("privateKey"), false);
    assertEquals(JSON.stringify(config).includes(input), false);
  }
});

Deno.test("Task 13 rejects empty and malformed private keys without disclosure", () => {
  for (const input of ["", "not-a-private-key"]) {
    assertThrows(
      () =>
        loadGitHubTask13RuntimeConfig(environment({
          LWS_GITHUB_PROVIDER_ENABLED: "false",
          LWS_GITHUB_APP_INSTALLATION_ID: "161436785",
          LWS_GITHUB_LAB_INSTALLATION_ID: "161461160",
          LWS_GITHUB_PRODUCTION_ORGANIZATION: "lorenzo-web-solutions",
          LWS_GITHUB_TEST_ORGANIZATION: "lorenzo-web-solutions-lab",
          LWS_GITHUB_TEMPLATE_OWNER: "lorenzo-web-solutions",
          LWS_GITHUB_APP_PRIVATE_KEY: input,
        })),
      GitHubAppConfigurationError,
      GITHUB_CONFIGURATION_INVALID,
    );
  }
});

Deno.test("Task 13 runtime uses immutable public starter provenance instead of remote secrets", () => {
  const config = loadGitHubTask13RuntimeConfig(environment({
    LWS_GITHUB_PROVIDER_ENABLED: "false",
    LWS_GITHUB_APP_INSTALLATION_ID: "161436785",
    LWS_GITHUB_LAB_INSTALLATION_ID: "161461160",
    LWS_GITHUB_PRODUCTION_ORGANIZATION: "lorenzo-web-solutions",
    LWS_GITHUB_TEST_ORGANIZATION: "lorenzo-web-solutions-lab",
    LWS_GITHUB_TEMPLATE_OWNER: "lorenzo-web-solutions",
    LWS_GITHUB_STARTER_VERSION: undefined,
    LWS_GITHUB_STARTER_COMMIT_SHA: undefined,
    LWS_GITHUB_STARTER_TREE_SHA256: undefined,
  }));

  assertEquals(config.production.starterVersion, "1.0.0");
  assertEquals(
    config.production.starterCommitSha,
    "47e7d7aad37afaa0b3e921fac349a87d2dd2816a",
  );
  assertEquals(
    config.production.starterTreeSha256,
    "6b4a76bf8a64ad91dc18fabe410f032670f03578d2d4c2123dba7cc0e98b5957",
  );
  assertEquals(config.lab.starterVersion, config.production.starterVersion);
  assertEquals(config.lab.starterCommitSha, config.production.starterCommitSha);
  assertEquals(
    config.lab.starterTreeSha256,
    config.production.starterTreeSha256,
  );
});

Deno.test("Task 13 runtime denies provider enablement and principal drift", () => {
  for (
    const overrides of [
      { LWS_GITHUB_PROVIDER_ENABLED: "true" },
      { LWS_GITHUB_APP_INSTALLATION_ID: "161461160" },
      { LWS_GITHUB_LAB_INSTALLATION_ID: "161436785" },
      { LWS_GITHUB_PRODUCTION_ORGANIZATION: "lorenzo-web-solutions-lab" },
      { LWS_GITHUB_TEST_ORGANIZATION: "lorenzo-web-solutions" },
    ]
  ) {
    assertThrows(
      () =>
        loadGitHubTask13RuntimeConfig(environment({
          LWS_GITHUB_PROVIDER_ENABLED: "false",
          LWS_GITHUB_APP_INSTALLATION_ID: "161436785",
          LWS_GITHUB_LAB_INSTALLATION_ID: "161461160",
          LWS_GITHUB_PRODUCTION_ORGANIZATION: "lorenzo-web-solutions",
          LWS_GITHUB_TEST_ORGANIZATION: "lorenzo-web-solutions-lab",
          LWS_GITHUB_TEMPLATE_OWNER: "lorenzo-web-solutions",
          ...overrides,
        })),
      GitHubAppConfigurationError,
      GITHUB_CONFIGURATION_INVALID,
    );
  }
});
