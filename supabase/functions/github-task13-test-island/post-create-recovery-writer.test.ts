import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  GITHUB_LAB_POST_CREATE_SUBPHASES,
} from "../_shared/repository-provisioning-diagnostics.ts";
import { GitHubLabPostCreateDiagnosticError } from "../_shared/github-repository-provider.ts";

const OPERATION_ID = "e646ae44-ec5d-46b6-96e3-b1023b9e1b68";
const CONTEXT_ID = "33a61b58-1d55-4624-bdb7-3c724d35ebcc";
const WORKSPACE_ID = "4dfe44a5-60d0-4728-b62b-ef87aa838976";
const REPOSITORY_ID = "1371224564";
const OWNER = "lorenzo-web-solutions-lab";
const REPOSITORY = "lws-web-33a61b581d554624bdb73c724d35ebcc";

type Classification =
  | "EMPTY_OR_UNINITIALIZED"
  | "ALREADY_COMPLETE"
  | "MARKER_MISSING"
  | "CONFLICT";

type RecoveryInput = Readonly<{
  operationId: string;
  websiteWorkContextId: string;
  websiteWorkspaceId: string;
}>;

type RecoveryAuthority = Readonly<{
  operationId: string;
  websiteWorkContextId: string;
  websiteWorkspaceId: string;
  repositoryId: string;
  owner: string;
  repository: string;
  installationId: string;
  starterSource: string;
  starterVersion: string;
  starterCommitSha: string;
  starterTreeSha256: string;
  markerContent: string;
}>;

type Inspection = Readonly<{
  state: Classification;
  authority: RecoveryAuthority;
}>;

type Dependencies = Readonly<{
  inspect(input: RecoveryInput): Promise<Inspection>;
  writeCanonicalSnapshotToEmptyRepository(
    authority: RecoveryAuthority,
  ): Promise<Readonly<{ outcome: "WRITTEN" | "RACE" }>>;
  writeMissingMarker(
    authority: RecoveryAuthority,
  ): Promise<Readonly<{ outcome: "WRITTEN" | "RACE" }>>;
}>;

type Writer = Readonly<{
  recover(input: RecoveryInput): Promise<
    Readonly<{
      status:
        | "ALREADY_COMPLETE"
        | "RECOVERED_FROM_EMPTY"
        | "RECOVERED_MARKER_ONLY";
    }>
  >;
}>;

type Module = Readonly<{
  createTask13PostCreateRecoveryWriter?: (
    dependencies: Dependencies,
  ) => Writer;
}>;

async function implementation(): Promise<Module> {
  try {
    return await import("./post-create-recovery-writer.ts") as Module;
  } catch {
    return {};
  }
}

const input = Object.freeze({
  operationId: OPERATION_ID,
  websiteWorkContextId: CONTEXT_ID,
  websiteWorkspaceId: WORKSPACE_ID,
});

function authority(overrides: Partial<RecoveryAuthority> = {}) {
  return Object.freeze({
    operationId: OPERATION_ID,
    websiteWorkContextId: CONTEXT_ID,
    websiteWorkspaceId: WORKSPACE_ID,
    repositoryId: REPOSITORY_ID,
    owner: OWNER,
    repository: REPOSITORY,
    installationId: "161461160",
    starterSource: "lorenzo-web-solutions/lws-website-starter",
    starterVersion: "1.0.0",
    starterCommitSha: "a".repeat(40),
    starterTreeSha256: "b".repeat(64),
    markerContent: '{"canonical":true}\n',
    ...overrides,
  });
}

async function harness(
  states: readonly Classification[],
  overrides: Partial<Dependencies> = {},
) {
  const module = await implementation();
  assert(
    typeof module.createTask13PostCreateRecoveryWriter === "function",
    "post-create recovery writer implementation is missing",
  );
  const calls: string[] = [];
  let inspection = 0;
  const dependencies: Dependencies = {
    inspect(value) {
      calls.push("INSPECT");
      const state = states[inspection++];
      if (!state) return Promise.reject(new Error("unexpected inspection"));
      assertEquals(value, input);
      return Promise.resolve({ state, authority: authority() });
    },
    writeCanonicalSnapshotToEmptyRepository(value) {
      calls.push("WRITE_EMPTY");
      assertEquals(value, authority());
      return Promise.resolve({ outcome: "WRITTEN" });
    },
    writeMissingMarker(value) {
      calls.push("WRITE_MARKER");
      assertEquals(value, authority());
      return Promise.resolve({ outcome: "WRITTEN" });
    },
    ...overrides,
  };
  return {
    calls,
    dependencies,
    writer: module.createTask13PostCreateRecoveryWriter(dependencies),
  };
}

Deno.test("recovery writer dependency surface structurally excludes create provider store and destructive capabilities", async () => {
  const source = await Deno.readTextFile(
    new URL("./post-create-recovery-writer.ts", import.meta.url),
  ).catch(() => "");
  assert(
    source.length > 0,
    "post-create recovery writer implementation is missing",
  );
  for (
    const forbidden of [
      "CREATE_REPOSITORY",
      "createRepository",
      "createLab",
      "provider.provision",
      ".claim(",
      ".resume(",
      ".bind(",
      ".quarantine(",
      "deleteRepository",
      "renameRepository",
      "transferRepository",
      "forceUpdateRef",
      "idempotencyKey",
    ]
  ) assertEquals(source.includes(forbidden), false, forbidden);
});

Deno.test("ALREADY_COMPLETE is a closed repeatable no-op", async () => {
  const test = await harness(["ALREADY_COMPLETE", "ALREADY_COMPLETE"]);
  assertEquals(await test.writer.recover(input), {
    status: "ALREADY_COMPLETE",
  });
  assertEquals(await test.writer.recover(input), {
    status: "ALREADY_COMPLETE",
  });
  assertEquals(test.calls, ["INSPECT", "INSPECT"]);
});

Deno.test("CONFLICT fails closed without any write", async () => {
  const test = await harness(["CONFLICT"]);
  await assertRejects(() => test.writer.recover(input));
  assertEquals(test.calls, ["INSPECT"]);
});

Deno.test("MARKER_MISSING performs only marker create-once and mandatory readback", async () => {
  const test = await harness(["MARKER_MISSING", "ALREADY_COMPLETE"]);
  assertEquals(await test.writer.recover(input), {
    status: "RECOVERED_MARKER_ONLY",
  });
  assertEquals(test.calls, ["INSPECT", "WRITE_MARKER", "INSPECT"]);
});

Deno.test("EMPTY performs only canonical initial write and mandatory readback", async () => {
  const test = await harness(["EMPTY_OR_UNINITIALIZED", "ALREADY_COMPLETE"]);
  assertEquals(await test.writer.recover(input), {
    status: "RECOVERED_FROM_EMPTY",
  });
  assertEquals(test.calls, ["INSPECT", "WRITE_EMPTY", "INSPECT"]);
});

Deno.test("empty ref race accepts complete or continues through marker-only", async () => {
  for (
    const scenario of [
      {
        states: ["EMPTY_OR_UNINITIALIZED", "ALREADY_COMPLETE"] as const,
        calls: ["INSPECT", "WRITE_EMPTY", "INSPECT"],
      },
      {
        states: [
          "EMPTY_OR_UNINITIALIZED",
          "MARKER_MISSING",
          "ALREADY_COMPLETE",
        ] as const,
        calls: [
          "INSPECT",
          "WRITE_EMPTY",
          "INSPECT",
          "WRITE_MARKER",
          "INSPECT",
        ],
      },
    ]
  ) {
    const test = await harness(scenario.states, {
      writeCanonicalSnapshotToEmptyRepository() {
        test.calls.push("WRITE_EMPTY");
        return Promise.resolve({ outcome: "RACE" });
      },
    });
    assertEquals(await test.writer.recover(input), {
      status: "RECOVERED_FROM_EMPTY",
    });
    assertEquals(test.calls, scenario.calls);
  }
});

Deno.test("empty ref race fails closed on conflict or still-empty state", async () => {
  for (const state of ["CONFLICT", "EMPTY_OR_UNINITIALIZED"] as const) {
    const test = await harness(["EMPTY_OR_UNINITIALIZED", state], {
      writeCanonicalSnapshotToEmptyRepository() {
        test.calls.push("WRITE_EMPTY");
        return Promise.resolve({ outcome: "RACE" });
      },
    });
    await assertRejects(() => test.writer.recover(input));
    assertEquals(test.calls, ["INSPECT", "WRITE_EMPTY", "INSPECT"]);
  }
});

Deno.test("marker race succeeds only when exact final state is complete", async () => {
  for (const finalState of ["ALREADY_COMPLETE", "CONFLICT"] as const) {
    const test = await harness(["MARKER_MISSING", finalState], {
      writeMissingMarker() {
        test.calls.push("WRITE_MARKER");
        return Promise.resolve({ outcome: "RACE" });
      },
    });
    if (finalState === "ALREADY_COMPLETE") {
      assertEquals(await test.writer.recover(input), {
        status: "RECOVERED_MARKER_ONLY",
      });
    } else {
      await assertRejects(() => test.writer.recover(input));
    }
    assertEquals(test.calls, ["INSPECT", "WRITE_MARKER", "INSPECT"]);
  }
});

Deno.test("authority and inspection failures perform zero writes", async () => {
  for (
    const failure of [
      "wrong operation",
      "wrong context",
      "wrong workspace",
      "wrong state",
      "wrong failure code",
      "missing external created at",
      "missing repository id",
      "bound operation",
      "customer binding",
      "dossier binding",
      "repository binding",
      "quarantine",
      "repository identity mismatch",
      "inspection uncertainty",
    ]
  ) {
    const test = await harness([], {
      inspect() {
        test.calls.push("INSPECT");
        return Promise.reject(new Error(failure));
      },
    });
    await assertRejects(() => test.writer.recover(input));
    assertEquals(test.calls, ["INSPECT"], failure);
  }
});

Deno.test("malformed forged and mismatched inspection authority performs zero writes", async () => {
  const invalid = [
    { state: "ALREADY_COMPLETE", authority: authority(), extra: true },
    { state: "UNKNOWN", authority: authority() },
    {
      state: "ALREADY_COMPLETE",
      authority: authority({ operationId: crypto.randomUUID() }),
    },
    {
      state: "ALREADY_COMPLETE",
      authority: authority({ websiteWorkContextId: crypto.randomUUID() }),
    },
    {
      state: "ALREADY_COMPLETE",
      authority: authority({ websiteWorkspaceId: crypto.randomUUID() }),
    },
    {
      state: "ALREADY_COMPLETE",
      authority: authority({ repositoryId: "invalid" }),
    },
    {
      state: "ALREADY_COMPLETE",
      authority: authority({ owner: "other-owner" }),
    },
    Object.assign(Object.create({ forged: true }), {
      state: "ALREADY_COMPLETE",
      authority: authority(),
    }),
  ];
  for (const result of invalid) {
    const test = await harness([], {
      inspect() {
        test.calls.push("INSPECT");
        return Promise.resolve(result as Inspection);
      },
    });
    await assertRejects(() => test.writer.recover(input));
    assertEquals(test.calls, ["INSPECT"]);
  }
});

Deno.test("invalid or prototype-bearing write outcomes fail before readback", async () => {
  for (
    const result of [
      { outcome: "UNKNOWN" },
      { outcome: "WRITTEN", extra: true },
      Object.assign(Object.create({ forged: true }), { outcome: "WRITTEN" }),
    ]
  ) {
    const test = await harness(["EMPTY_OR_UNINITIALIZED"], {
      writeCanonicalSnapshotToEmptyRepository() {
        test.calls.push("WRITE_EMPTY");
        return Promise.resolve(result as { outcome: "WRITTEN" });
      },
    });
    await assertRejects(() => test.writer.recover(input));
    assertEquals(test.calls, ["INSPECT", "WRITE_EMPTY"]);
  }
});

Deno.test("all existing post-create diagnostics remain the first causal boundary", async () => {
  for (const subphase of GITHUB_LAB_POST_CREATE_SUBPHASES) {
    const diagnostic = new GitHubLabPostCreateDiagnosticError(subphase);
    const test = await harness(["EMPTY_OR_UNINITIALIZED"], {
      writeCanonicalSnapshotToEmptyRepository() {
        test.calls.push("WRITE_EMPTY");
        return Promise.reject(diagnostic);
      },
    });
    const error = await assertRejects(() => test.writer.recover(input));
    assertEquals(error, diagnostic, subphase);
    assertEquals(test.calls, ["INSPECT", "WRITE_EMPTY"]);
    assertEquals(JSON.stringify(error).includes("token"), false);
  }
});

Deno.test("successful empty recovery is repeat-safe on the next execution", async () => {
  const test = await harness([
    "EMPTY_OR_UNINITIALIZED",
    "ALREADY_COMPLETE",
    "ALREADY_COMPLETE",
  ]);
  assertEquals(await test.writer.recover(input), {
    status: "RECOVERED_FROM_EMPTY",
  });
  assertEquals(await test.writer.recover(input), {
    status: "ALREADY_COMPLETE",
  });
  assertEquals(test.calls, [
    "INSPECT",
    "WRITE_EMPTY",
    "INSPECT",
    "INSPECT",
  ]);
});
