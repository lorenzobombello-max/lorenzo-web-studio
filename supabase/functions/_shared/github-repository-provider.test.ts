import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import {
  computeSnapshotDigest,
  createGitHubRepositoryProvider,
  GitHubLabCreateDiagnosticError,
  GitHubLabCreateOutcomeUnknownError,
  GitHubLabPostCreateDiagnosticError,
  type GitHubRepositoryProviderDependencies,
  GitHubRepositoryProviderError,
  GitHubStarterReadDiagnosticError,
  type GitHubStarterSnapshot,
} from "./github-repository-provider.ts";
import {
  GITHUB_LAB_CREATE_SUBPHASES,
  GITHUB_LAB_POST_CREATE_SUBPHASES,
} from "./repository-provisioning-diagnostics.ts";

const CONTEXT_ID = "0198abcd-1234-7000-8000-0123456789ab";
const OPERATION_ID = "d2140000-0000-4000-8000-000000000001";
const REPOSITORY = "lws-web-0198abcd1234700080000123456789ab";
const SOURCE_COMMIT = "a".repeat(40);
const MARKER_COMMIT = "b".repeat(40);
const SOURCE_INSTALLATION = "161436785";
const LAB_INSTALLATION = "161461160";
const SOURCE_REPOSITORY_ID = "1368684860";
const LAB_REPOSITORY_ID = "1369000001";

const entries = Object.freeze([
  Object.freeze({
    path: "README.md",
    mode: "100644",
    type: "blob" as const,
    content: new TextEncoder().encode("starter\n"),
  }),
  Object.freeze({
    path: "src/index.ts",
    mode: "100644",
    type: "blob" as const,
    content: new TextEncoder().encode("export {};\n"),
  }),
]);

function marker(treeSha256: string) {
  return `${
    JSON.stringify(
      {
        schema_version: 1,
        environment: "TEST",
        organization: "lorenzo-web-solutions-lab",
        website_work_context_id: CONTEXT_ID,
        repository_provisioning_operation_id: OPERATION_ID,
        starter_source: "lorenzo-web-solutions/lws-website-starter",
        starter_version: "v1.0.0",
        starter_commit_sha: SOURCE_COMMIT,
        starter_tree_sha256: treeSha256,
      },
      null,
      2,
    )
  }\n`;
}

async function fixture() {
  const treeSha256 = await computeSnapshotDigest(entries);
  const snapshot: GitHubStarterSnapshot = Object.freeze({
    installationId: SOURCE_INSTALLATION,
    repositoryId: SOURCE_REPOSITORY_ID,
    owner: "lorenzo-web-solutions",
    repository: "lws-website-starter",
    commitSha: SOURCE_COMMIT,
    entries,
  });
  const config = Object.freeze({
    source: Object.freeze({
      installationId: SOURCE_INSTALLATION,
      owner: "lorenzo-web-solutions",
      repository: "lws-website-starter",
      repositoryId: SOURCE_REPOSITORY_ID,
      version: "1.0.0",
      commitSha: SOURCE_COMMIT,
      treeSha256,
    }),
    lab: Object.freeze({
      installationId: LAB_INSTALLATION,
      organization: "lorenzo-web-solutions-lab",
    }),
  });
  const request = Object.freeze({
    contractVersion: 2 as const,
    operationId: OPERATION_ID,
    websiteWorkContextId: CONTEXT_ID,
    repositoryName: REPOSITORY,
    visibility: "PRIVATE" as const,
    defaultBranch: "main" as const,
    bootstrap: "GITHUB_SNAPSHOT" as const,
    starter: Object.freeze({
      source: "lorenzo-web-solutions/lws-website-starter",
      version: "1.0.0",
      commitSha: SOURCE_COMMIT,
      templateRepositoryId: SOURCE_REPOSITORY_ID,
    }),
  });
  return { treeSha256, snapshot, config, request };
}

async function harness(
  overrides: Partial<GitHubRepositoryProviderDependencies> = {},
) {
  const base = await fixture();
  const calls: string[] = [];
  const dependencies: GitHubRepositoryProviderDependencies = {
    readStarter: () => {
      calls.push("PRODUCTION_READ");
      return Promise.resolve(base.snapshot);
    },
    createLab: () => {
      calls.push("LAB_CREATE");
      return Promise.resolve(Object.freeze({
        installationId: LAB_INSTALLATION,
        repositoryId: LAB_REPOSITORY_ID,
        nodeId: "R_lab_repository_node",
        owner: "lorenzo-web-solutions-lab",
        name: REPOSITORY,
        private: true,
        defaultBranch: "main" as const,
      }));
    },
    reconcileLab: () => {
      calls.push("LAB_RECONCILE");
      return Promise.resolve(Object.freeze({ state: "AMBIGUOUS" as const }));
    },
    quarantineLab: () => {
      calls.push("LAB_QUARANTINE");
      return Promise.resolve();
    },
    captureLabIdentity: () => {
      calls.push("LAB_CAPTURE");
      return Promise.resolve();
    },
    writeLabSnapshot: (input) => {
      calls.push("LAB_WRITE");
      assertEquals(input.markerContent, marker(base.treeSha256));
      return Promise.resolve(Object.freeze({
        snapshotCommitSha: "c".repeat(40),
        markerCommitSha: MARKER_COMMIT,
      }));
    },
    readLabBinding: () => {
      calls.push("LAB_READBACK");
      return Promise.resolve(Object.freeze({
        installationId: LAB_INSTALLATION,
        repositoryId: LAB_REPOSITORY_ID,
        nodeId: "R_lab_repository_node",
        owner: "lorenzo-web-solutions-lab",
        name: REPOSITORY,
        private: true,
        defaultBranch: "main" as const,
        sourceTreeSha256: base.treeSha256,
        markerContent: marker(base.treeSha256),
        markerCommitSha: MARKER_COMMIT,
      }));
    },
    ...overrides,
  };
  return {
    ...base,
    calls,
    dependencies,
    provider: createGitHubRepositoryProvider(base.config, dependencies),
  };
}

Deno.test("two-principal provider reads and verifies production before exactly one LAB create", async () => {
  const test = await harness();
  const result = await test.provider.provision(test.request);

  assertEquals(test.calls, [
    "PRODUCTION_READ",
    "LAB_CREATE",
    "LAB_CAPTURE",
    "LAB_WRITE",
    "LAB_READBACK",
  ]);
  assertEquals(result, {
    provider: "GITHUB",
    providerRepositoryId: LAB_REPOSITORY_ID,
    providerNodeId: "R_lab_repository_node",
    owner: "lorenzo-web-solutions-lab",
    name: REPOSITORY,
    visibility: "PRIVATE",
    defaultBranch: "main",
    starterSource: "lorenzo-web-solutions/lws-website-starter",
    starterVersion: "1.0.0",
    starterCommitSha: SOURCE_COMMIT,
    repositoryMarkerCommitSha: MARKER_COMMIT,
  });
});

Deno.test("source installation, identity, commit and digest mismatches create nothing", async () => {
  const base = await fixture();
  for (
    const snapshot of [
      { ...base.snapshot, installationId: LAB_INSTALLATION },
      { ...base.snapshot, repositoryId: "999999999" },
      { ...base.snapshot, owner: "lorenzo-web-solutions-lab" },
      { ...base.snapshot, commitSha: "d".repeat(40) },
      {
        ...base.snapshot,
        entries: [{
          ...entries[0],
          content: new TextEncoder().encode("changed\n"),
        }],
      },
    ]
  ) {
    let creates = 0;
    const test = await harness({
      readStarter: () => Promise.resolve(snapshot as GitHubStarterSnapshot),
      createLab: () => {
        creates++;
        return Promise.reject(new Error("must not create"));
      },
    });
    await assertRejects(
      () => test.provider.provision(test.request),
      GitHubRepositoryProviderError,
      "GITHUB_STARTER_SNAPSHOT_INVALID",
    );
    assertEquals(creates, 0);
  }
});

Deno.test("starter failures retain only closed snapshot, digest, and identity subphases", async () => {
  const base = await fixture();
  const invalidDigestContent = new Uint8Array([1]);
  Object.defineProperty(invalidDigestContent, Symbol.iterator, {
    value() {
      throw new Error("raw digest failure");
    },
  });
  const scenarios = [
    {
      readStarter: () =>
        Promise.reject(
          new GitHubStarterReadDiagnosticError("STARTER_METADATA_READ"),
        ),
      subphase: "STARTER_METADATA_READ",
    },
    {
      readStarter: () => Promise.resolve({ ...base.snapshot, entries: [] }),
      subphase: "STARTER_SNAPSHOT_VALIDATE",
    },
    {
      readStarter: () =>
        Promise.resolve({
          ...base.snapshot,
          entries: [{ ...entries[0], path: null as never }],
        }),
      subphase: "STARTER_SNAPSHOT_VALIDATE",
    },
    {
      readStarter: () =>
        Promise.resolve({
          ...base.snapshot,
          entries: [{ ...entries[0], content: invalidDigestContent }],
        }),
      subphase: "STARTER_DIGEST_CALCULATE",
    },
    {
      readStarter: () =>
        Promise.resolve({
          ...base.snapshot,
          entries: [{
            ...entries[0],
            content: new TextEncoder().encode("changed\n"),
          }],
        }),
      subphase: "STARTER_DIGEST_COMPARE",
    },
    {
      readStarter: () =>
        Promise.resolve({ ...base.snapshot, repositoryId: "999999999" }),
      subphase: "STARTER_IDENTITY_VALIDATE",
    },
  ] as const;

  for (const scenario of scenarios) {
    const test = await harness({ readStarter: scenario.readStarter });
    const error = await assertRejects(
      () => test.provider.provision(test.request),
      GitHubRepositoryProviderError,
      "GITHUB_STARTER_SNAPSHOT_INVALID",
    );
    assertEquals(error.subphase, scenario.subphase);
    assertEquals(test.calls.includes("LAB_CREATE"), false);
  }
});

Deno.test("unknown starter error remains closed without inventing a subphase", async () => {
  const secret = "raw upstream token Authorization private key";
  const upstream = new Error(secret, {
    cause: { stack: secret, details: secret, hint: secret },
  });
  const test = await harness({
    readStarter: () => Promise.reject(upstream),
  });
  const error = await assertRejects(
    () => test.provider.provision(test.request),
    GitHubRepositoryProviderError,
    "GITHUB_STARTER_SNAPSHOT_INVALID",
  );
  assertEquals(error.subphase, undefined);
  assertEquals(
    `${error.message}\n${error.stack}\n${JSON.stringify(error)}`.includes(
      secret,
    ),
    false,
  );
});

Deno.test("production and LAB installation authority cannot cross", async () => {
  const base = await fixture();
  const test = await harness();
  assertThrows(
    () =>
      createGitHubRepositoryProvider({
        ...base.config,
        lab: { ...base.config.lab, installationId: SOURCE_INSTALLATION },
      }, test.dependencies),
    GitHubRepositoryProviderError,
    "GITHUB_REPOSITORY_PROVIDER_CONFIG_INVALID",
  );
});

Deno.test("post-create failure never triggers a second create", async () => {
  let creates = 0;
  const test = await harness({
    createLab: async () => {
      creates++;
      return {
        installationId: LAB_INSTALLATION,
        repositoryId: LAB_REPOSITORY_ID,
        nodeId: "R_lab_repository_node",
        owner: "lorenzo-web-solutions-lab",
        name: REPOSITORY,
        private: true,
        defaultBranch: "main",
      };
    },
    writeLabSnapshot: () =>
      Promise.reject(new Error("synthetic write failure")),
  });
  await assertRejects(
    () => test.provider.provision(test.request),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_POST_CREATE_FAILED",
  );
  assertEquals(creates, 1);
});

Deno.test("post-create snapshot preparation failure retains its first causal boundary", async () => {
  const base = await fixture();
  const content = base.snapshot.entries[0].content.slice();
  Object.defineProperty(content, "slice", {
    value() {
      throw new Error("synthetic snapshot preparation failure");
    },
  });
  const test = await harness({
    readStarter: () =>
      Promise.resolve({
        ...base.snapshot,
        entries: [
          { ...base.snapshot.entries[0], content },
          base.snapshot.entries[1],
        ],
      }),
  });
  const error = await assertRejects(
    () => test.provider.provision(test.request),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_POST_CREATE_FAILED",
  );
  assertEquals(
    String(error.subphase),
    "LAB_POST_CREATE_SNAPSHOT_PREPARE",
  );
  assertEquals(test.calls.filter((call) => call === "LAB_CREATE").length, 1);
  assertEquals(test.calls.includes("LAB_WRITE"), false);
});

Deno.test("post-create write result validation retains its first causal boundary", async () => {
  const test = await harness({
    writeLabSnapshot: () =>
      Promise.resolve({
        snapshotCommitSha: "c".repeat(40),
        markerCommitSha: "invalid",
      }),
  });
  const error = await assertRejects(
    () => test.provider.provision(test.request),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_POST_CREATE_FAILED",
  );
  assertEquals(
    String(error.subphase),
    "LAB_POST_CREATE_WRITE_RESULT_VALIDATE",
  );
  assertEquals(test.calls.filter((call) => call === "LAB_CREATE").length, 1);
  assertEquals(test.calls.includes("LAB_READBACK"), false);
});

Deno.test("post-create diagnostics use the exact closed allowlist", () => {
  assertEquals(GITHUB_LAB_POST_CREATE_SUBPHASES, [
    "LAB_POST_CREATE_WRITE_TOKEN_ACQUIRE",
    "LAB_POST_CREATE_SNAPSHOT_PREPARE",
    "LAB_POST_CREATE_BLOB_WRITE",
    "LAB_POST_CREATE_TREE_WRITE",
    "LAB_POST_CREATE_COMMIT_WRITE",
    "LAB_POST_CREATE_REF_WRITE",
    "LAB_POST_CREATE_MARKER_WRITE",
    "LAB_POST_CREATE_WRITE_RESULT_VALIDATE",
    "LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE",
    "LAB_POST_CREATE_METADATA_READ",
    "LAB_POST_CREATE_SNAPSHOT_READBACK",
    "LAB_POST_CREATE_MARKER_READBACK",
    "LAB_POST_CREATE_PROVENANCE_VALIDATE",
  ]);
  for (const subphase of GITHUB_LAB_POST_CREATE_SUBPHASES) {
    const error = new GitHubLabPostCreateDiagnosticError(subphase);
    assertEquals(error.subphase, subphase);
    assertThrows(
      () => Object.assign(error, { subphase: "LAB_POST_CREATE_BLOB_WRITE" }),
      TypeError,
    );
  }
  assertThrows(
    () =>
      new GitHubLabPostCreateDiagnosticError(
        "UNKNOWN_POST_CREATE_BOUNDARY" as never,
      ),
    Error,
    "GITHUB_LAB_POST_CREATE_DIAGNOSTIC_INVALID",
  );
});

Deno.test("provider preserves only a genuine first post-create boundary", async () => {
  const genuine = await harness({
    writeLabSnapshot: () =>
      Promise.reject(
        new GitHubLabPostCreateDiagnosticError(
          "LAB_POST_CREATE_BLOB_WRITE",
        ),
      ),
  });
  const genuineError = await assertRejects(
    () => genuine.provider.provision(genuine.request),
    GitHubRepositoryProviderError,
  );
  assertEquals(genuineError.subphase, "LAB_POST_CREATE_BLOB_WRITE");

  const forged = Object.assign(
    Object.create(GitHubLabPostCreateDiagnosticError.prototype),
    { subphase: "LAB_POST_CREATE_TREE_WRITE" },
  );
  const untrusted = await harness({
    writeLabSnapshot: () => Promise.reject(forged),
  });
  const untrustedError = await assertRejects(
    () => untrusted.provider.provision(untrusted.request),
    GitHubRepositoryProviderError,
  );
  assertEquals(untrustedError.subphase, undefined);
});

Deno.test("post-create provider subphases reject cross-phase pairing", () => {
  assertThrows(
    () =>
      new GitHubRepositoryProviderError(
        "GITHUB_LAB_CREATE_FAILED",
        "LAB_POST_CREATE_BLOB_WRITE" as never,
      ),
    Error,
    "REPOSITORY_PROVISIONING_PROVIDER_DIAGNOSTIC_INVALID",
  );
  assertThrows(
    () =>
      new GitHubRepositoryProviderError(
        "GITHUB_LAB_POST_CREATE_FAILED",
        "LAB_CREATE_HTTP_STATUS" as never,
      ),
    Error,
    "REPOSITORY_PROVISIONING_PROVIDER_DIAGNOSTIC_INVALID",
  );
});

Deno.test("durable capture failure quarantines before writes and never creates twice", async () => {
  let creates = 0;
  const test = await harness({
    createLab: async () => {
      creates++;
      return {
        installationId: LAB_INSTALLATION,
        repositoryId: LAB_REPOSITORY_ID,
        nodeId: "R_lab_repository_node",
        owner: "lorenzo-web-solutions-lab",
        name: REPOSITORY,
        private: true,
        defaultBranch: "main",
      };
    },
    captureLabIdentity: () => {
      test.calls.push("LAB_CAPTURE");
      return Promise.reject(new Error("synthetic capture failure"));
    },
  });
  await assertRejects(
    () => test.provider.provision(test.request),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_POST_CREATE_FAILED",
  );
  assertEquals(creates, 1);
  assertEquals(test.calls, [
    "PRODUCTION_READ",
    "LAB_CAPTURE",
    "LAB_QUARANTINE",
  ]);
});

Deno.test("unknown create outcome reconciles an exact identity without a second create", async () => {
  let creates = 0;
  const test = await harness({
    createLab: () => {
      creates++;
      return Promise.reject(
        new GitHubLabCreateOutcomeUnknownError("LAB_CREATE_HTTP_REQUEST"),
      );
    },
    reconcileLab: () => {
      test.calls.push("LAB_RECONCILE");
      return Promise.resolve({
        state: "MATCH",
        identity: {
          installationId: LAB_INSTALLATION,
          repositoryId: LAB_REPOSITORY_ID,
          nodeId: "R_lab_repository_node",
          owner: "lorenzo-web-solutions-lab",
          name: REPOSITORY,
          private: true,
          defaultBranch: "main",
        },
      });
    },
  });

  await test.provider.provision(test.request);
  assertEquals(creates, 1);
  assertEquals(test.calls, [
    "PRODUCTION_READ",
    "LAB_RECONCILE",
    "LAB_CAPTURE",
    "LAB_WRITE",
    "LAB_READBACK",
  ]);
});

Deno.test("ambiguous create reconciliation quarantines without writes or retry", async () => {
  let creates = 0;
  const test = await harness({
    createLab: () => {
      creates++;
      return Promise.reject(
        new GitHubLabCreateOutcomeUnknownError("LAB_CREATE_HTTP_REQUEST"),
      );
    },
  });

  await assertRejects(
    () => test.provider.provision(test.request),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_RECONCILIATION_AMBIGUOUS",
  );
  assertEquals(creates, 1);
  assertEquals(test.calls, [
    "PRODUCTION_READ",
    "LAB_RECONCILE",
    "LAB_QUARANTINE",
  ]);
});

Deno.test("LAB readback denies installation, organization, context and marker mismatches", async () => {
  const base = await fixture();
  for (
    const readback of [
      { installationId: SOURCE_INSTALLATION },
      { owner: "lorenzo-web-solutions" },
      { repositoryId: "999999999" },
      {
        markerContent: marker(base.treeSha256).replace(
          CONTEXT_ID,
          crypto.randomUUID(),
        ),
      },
      {
        markerContent: marker(base.treeSha256).replace(
          OPERATION_ID,
          crypto.randomUUID(),
        ),
      },
      { sourceTreeSha256: "f".repeat(64) },
    ]
  ) {
    const test = await harness({
      readLabBinding: () =>
        Promise.resolve({
          installationId: LAB_INSTALLATION,
          repositoryId: LAB_REPOSITORY_ID,
          nodeId: "R_lab_repository_node",
          owner: "lorenzo-web-solutions-lab",
          name: REPOSITORY,
          private: true,
          defaultBranch: "main",
          sourceTreeSha256: base.treeSha256,
          markerContent: marker(base.treeSha256),
          markerCommitSha: MARKER_COMMIT,
          ...readback,
        } as never),
    });
    await assertRejects(
      () => test.provider.provision(test.request),
      GitHubRepositoryProviderError,
      "GITHUB_LAB_BINDING_INVALID",
    );
    assertEquals(test.calls.filter((call) => call === "LAB_CREATE").length, 1);
  }
});

Deno.test("provider errors and result expose no credentials or source bytes", async () => {
  const secret = "ghs_synthetic_secret_token_value";
  const test = await harness({
    writeLabSnapshot: () => Promise.reject(new Error(secret)),
  });
  const error = await assertRejects(
    () => test.provider.provision(test.request),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_POST_CREATE_FAILED",
  );
  assertEquals(
    `${error.message}\n${error.stack}\n${JSON.stringify(error)}`.includes(
      secret,
    ),
    false,
  );
});

Deno.test("LAB create diagnostics reject unknown labels", () => {
  assertThrows(
    () => new GitHubLabCreateOutcomeUnknownError("FORGED" as never),
    Error,
    "GITHUB_LAB_CREATE_DIAGNOSTIC_INVALID",
  );
  assertThrows(
    () =>
      new GitHubRepositoryProviderError(
        "GITHUB_LAB_CREATE_FAILED",
        "FORGED" as never,
      ),
    Error,
    "REPOSITORY_PROVISIONING_PROVIDER_DIAGNOSTIC_INVALID",
  );
});

Deno.test("LAB create diagnostics use the exact closed allowlist", () => {
  assertEquals(GITHUB_LAB_CREATE_SUBPHASES, [
    "LAB_TOKEN_ACQUIRE",
    "LAB_CREATE_REQUEST_PREPARE",
    "LAB_CREATE_HTTP_REQUEST",
    "LAB_CREATE_HTTP_STATUS",
    "LAB_CREATE_CONTENT_TYPE",
    "LAB_CREATE_BODY_READ",
    "LAB_CREATE_JSON_PARSE",
    "LAB_CREATE_RESPONSE_SCHEMA",
    "LAB_CREATE_ADAPTER_PROJECT",
  ]);
  assertThrows(
    () =>
      new GitHubRepositoryProviderError(
        "GITHUB_LAB_CREATE_FAILED",
        "LAB_CREATE_HTTP_REQUEST",
      ),
    Error,
    "REPOSITORY_PROVISIONING_PROVIDER_DIAGNOSTIC_INVALID",
  );
  assertThrows(
    () =>
      new GitHubRepositoryProviderError(
        "GITHUB_LAB_RECONCILIATION_AMBIGUOUS",
        "LAB_TOKEN_ACQUIRE",
      ),
    Error,
    "REPOSITORY_PROVISIONING_PROVIDER_DIAGNOSTIC_INVALID",
  );
});

Deno.test("LAB create intermediate diagnostics are immutable and trusted", async () => {
  for (
    const error of [
      new GitHubLabCreateDiagnosticError("LAB_CREATE_HTTP_STATUS"),
      new GitHubLabCreateOutcomeUnknownError("LAB_CREATE_HTTP_REQUEST"),
    ]
  ) {
    assertThrows(
      () => Object.assign(error, { subphase: "LAB_CREATE_JSON_PARSE" }),
      TypeError,
    );
  }

  const forged = Object.assign(
    Object.create(GitHubLabCreateDiagnosticError.prototype),
    { subphase: "LAB_CREATE_HTTP_STATUS" },
  );
  const test = await harness({
    createLab: () => Promise.reject(forged),
  });
  const failure = await assertRejects(
    () => test.provider.provision(test.request),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_CREATE_FAILED",
  );
  assertEquals(failure.subphase, undefined);
});

Deno.test("provider preserves trusted LAB token acquisition diagnostics", async () => {
  const test = await harness({
    createLab: () =>
      Promise.reject(
        new GitHubLabCreateDiagnosticError(
          "LAB_TOKEN_ACQUIRE",
          "TOKEN_LEASE_VALIDATE",
          "LEASE_TOKEN_FORMAT_VALIDATE",
        ),
      ),
  });
  const failure = await assertRejects(
    () => test.provider.provision(test.request),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_CREATE_FAILED",
  );
  assertEquals(failure.subphase, "LAB_TOKEN_ACQUIRE");
  assertEquals(failure.tokenAcquireSubphase, "TOKEN_LEASE_VALIDATE");
  assertEquals(failure.tokenLeaseCheck, "LEASE_TOKEN_FORMAT_VALIDATE");
  assertEquals(test.calls, ["PRODUCTION_READ"]);
});

Deno.test("provider preserves a trusted LAB token response check", async () => {
  const Constructor = GitHubLabCreateDiagnosticError as unknown as new (
    subphase: "LAB_TOKEN_ACQUIRE",
    tokenAcquireSubphase: "TOKEN_RESPONSE_SCHEMA",
    tokenLeaseCheck: undefined,
    tokenResponseCheck: "TOKEN_SCHEMA_REPOSITORY_SELECTION",
  ) => GitHubLabCreateDiagnosticError & { tokenResponseCheck?: string };
  const test = await harness({
    createLab: () =>
      Promise.reject(
        new Constructor(
          "LAB_TOKEN_ACQUIRE",
          "TOKEN_RESPONSE_SCHEMA",
          undefined,
          "TOKEN_SCHEMA_REPOSITORY_SELECTION",
        ),
      ),
  });
  const failure = await assertRejects(
    () => test.provider.provision(test.request),
    GitHubRepositoryProviderError,
    "GITHUB_LAB_CREATE_FAILED",
  );
  assertEquals(failure.tokenAcquireSubphase, "TOKEN_RESPONSE_SCHEMA");
  assertEquals(
    (failure as { tokenResponseCheck?: string }).tokenResponseCheck,
    "TOKEN_SCHEMA_REPOSITORY_SELECTION",
  );
  assertEquals(test.calls, ["PRODUCTION_READ"]);
});

Deno.test("LAB token diagnostics reject nested fields on other create subphases", () => {
  assertThrows(
    () =>
      new GitHubLabCreateDiagnosticError(
        "LAB_TOKEN_ACQUIRE",
        "FORGED_TOKEN_STAGE" as never,
      ),
    Error,
    "GITHUB_TOKEN_ACQUIRE_DIAGNOSTIC_INVALID",
  );
  assertThrows(
    () =>
      new GitHubLabCreateDiagnosticError(
        "LAB_CREATE_HTTP_STATUS",
        "TOKEN_HTTP_STATUS",
      ),
    Error,
    "GITHUB_LAB_CREATE_DIAGNOSTIC_INVALID",
  );
  assertThrows(
    () =>
      new GitHubRepositoryProviderError(
        "GITHUB_LAB_CREATE_FAILED",
        "LAB_CREATE_HTTP_STATUS",
        "TOKEN_HTTP_STATUS",
      ),
    Error,
    "REPOSITORY_PROVISIONING_PROVIDER_DIAGNOSTIC_INVALID",
  );
});
