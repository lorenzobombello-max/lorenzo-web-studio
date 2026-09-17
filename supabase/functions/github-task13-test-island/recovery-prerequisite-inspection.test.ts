import {
  assert,
  assertEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1";
import { GitHubRepositoryStateInspectionError } from "../_shared/github-repository-state-inspector.ts";
import { GitHubLabPostCreateDiagnosticError } from "../_shared/repository-provisioning-diagnostics.ts";
import { createGitHubRefReadDiagnostic } from "../_shared/github-ref-read-diagnostic.ts";
import {
  hasValidatedTask13RecoveryAuthorityDiagnostic,
  TASK13_RECOVERY_INSPECTION_FAILURE_PHASES,
  Task13RecoveryAuthorityDiagnosticError,
} from "./recovery-prerequisite-inspection.ts";

const OPERATION_ID = "e646ae44-ec5d-46b6-96e3-b1023b9e1b68";
const CONTEXT_ID = "33a61b58-1d55-4624-bdb7-3c724d35ebcc";
const WORKSPACE_ID = "4dfe44a5-60d0-4728-b62b-ef87aa838976";
const REPOSITORY_ID = "1371224564";
const OWNER = "lorenzo-web-solutions-lab";
const REPOSITORY = "lws-web-33a61b581d554624bdb73c724d35ebcc";

type Capability = (
  input: Readonly<{
    operationId: string;
    websiteWorkContextId: string;
    websiteWorkspaceId: string;
  }>,
) => Promise<
  Readonly<{
    authority_valid: true;
    repository_identity_valid: true;
    state_classification: string;
  }>
>;

type Module = Readonly<{
  createTask13RecoveryPrerequisiteInspection?: (
    config: unknown,
    dependencies: unknown,
  ) => Capability;
  createTask13RecoveryAuthorityInspection?: (
    config: unknown,
    dependencies: unknown,
  ) => (input: Parameters<Capability>[0]) => Promise<
    Readonly<{
      state: string;
      authority: Record<string, unknown>;
    }>
  >;
  Task13RecoveryPrerequisiteInspectionError?: new (code: string) => Error;
  getValidatedTask13RefReadDiagnostic?: (
    value: unknown,
  ) => Readonly<{ boundary: string; code: string }>;
}>;

async function implementation(): Promise<Module> {
  try {
    return await import(
      "./recovery-prerequisite-inspection.ts"
    ) as unknown as Module;
  } catch {
    return {};
  }
}

function authority(overrides: Record<string, unknown> = {}) {
  return {
    operation_found: true,
    operation_id: OPERATION_ID,
    website_work_context_id: CONTEXT_ID,
    website_workspace_id: WORKSPACE_ID,
    operation_state: "TERMINAL_FAILED",
    failure_code: "REPOSITORY_PROVIDER_FAILED",
    external_created_at_present: true,
    repository_external_id: REPOSITORY_ID,
    target_owner: OWNER,
    target_repository_name: REPOSITORY,
    bound_at_present: false,
    quarantine_present: false,
    customer_binding_present: false,
    dossier_binding_present: false,
    repository_binding_present: false,
    ...overrides,
  };
}

function config() {
  return {
    production: {
      templateOwner: "lorenzo-web-solutions",
      templateName: "lws-website-starter",
    },
    lab: {
      target: "TEST",
      organization: OWNER,
      installationId: "161461160",
      starterVersion: "1.0.0",
      starterCommitSha: "a".repeat(40),
      starterTreeSha256: "b".repeat(64),
    },
  };
}

async function capability(
  authorityResult: unknown,
  classification = "ALREADY_COMPLETE",
) {
  const module = await implementation();
  assert(
    typeof module.createTask13RecoveryPrerequisiteInspection === "function",
    "read-only recovery prerequisite composition is missing",
  );
  const rpcCalls: unknown[] = [];
  const inspectorCalls: unknown[] = [];
  const inspect = module.createTask13RecoveryPrerequisiteInspection(
    config(),
    {
      rpc: (name: string, parameters: Record<string, unknown>) => {
        rpcCalls.push({ name, parameters });
        return Promise.resolve({ data: authorityResult, error: null });
      },
      inspectRepository: (input: unknown) => {
        inspectorCalls.push(input);
        return Promise.resolve({ state: classification });
      },
    },
  );
  return { inspect, rpcCalls, inspectorCalls };
}

const input = Object.freeze({
  operationId: OPERATION_ID,
  websiteWorkContextId: CONTEXT_ID,
  websiteWorkspaceId: WORKSPACE_ID,
});

Deno.test("recovery prerequisite adapter uses exact RPC and three UUID arguments", async () => {
  const test = await capability(authority());
  await test.inspect(input);
  assertEquals(test.rpcCalls, [{
    name: "get_task13_repository_recovery_authority_v1",
    parameters: {
      p_operation_id: OPERATION_ID,
      p_website_work_context_id: CONTEXT_ID,
      p_website_workspace_id: WORKSPACE_ID,
    },
  }]);
  assertEquals(JSON.stringify(test.rpcCalls).includes("idempotency"), false);
});

Deno.test("recovery prerequisite inspection source remains strictly read-only", async () => {
  const source = await Deno.readTextFile(
    new URL("./recovery-prerequisite-inspection.ts", import.meta.url),
  );
  for (
    const forbidden of [
      "CREATE_REPOSITORY",
      "CREATE_BOOTSTRAP_FILE",
      "UPDATE_REF",
      "WRITE_PROJECT_MARKER",
      ".insert(",
      ".update(",
      ".delete(",
      ".bind(",
      ".fail(",
    ]
  ) assertEquals(source.includes(forbidden), false, forbidden);
});

Deno.test("recovery prerequisite adapter rejects malformed and non-exact RPC results", async () => {
  const accessorAuthority = authority() as Record<string, unknown>;
  Object.defineProperty(accessorAuthority, "repository_external_id", {
    get: () => REPOSITORY_ID,
    enumerable: true,
  });
  const hiddenAuthority = authority() as Record<string | symbol, unknown>;
  Object.defineProperty(hiddenAuthority, "hidden", { value: "secret" });
  const symbolAuthority = authority() as Record<string | symbol, unknown>;
  symbolAuthority[Symbol("secret")] = "secret";
  const proxyAuthority = new Proxy(authority(), {
    ownKeys: () => {
      throw new Error("proxy secret");
    },
  });
  for (
    const result of [
      null,
      [],
      { ...authority(), operation_id: undefined },
      { ...authority(), unknown_authority: true },
      Object.assign(Object.create({ forged: true }), authority()),
      accessorAuthority,
      hiddenAuthority,
      symbolAuthority,
      proxyAuthority,
    ]
  ) {
    const test = await capability(result);
    await assertRejects(() => test.inspect(input));
    assertEquals(test.inspectorCalls.length, 0);
  }
});

Deno.test("recovery prerequisite authority blocks every unsafe operation or binding state", async () => {
  for (
    const unsafe of [
      { operation_found: false },
      { operation_id: "11111111-1111-4111-8111-111111111111" },
      { website_work_context_id: "11111111-1111-4111-8111-111111111111" },
      { website_workspace_id: "11111111-1111-4111-8111-111111111111" },
      { operation_state: "FAILED" },
      { failure_code: "OTHER" },
      { external_created_at_present: false },
      { repository_external_id: null },
      { repository_external_id: "not-numeric" },
      { target_owner: "lorenzo-web-solutions" },
      { target_repository_name: "caller-controlled" },
      { bound_at_present: true },
      { customer_binding_present: true },
      { dossier_binding_present: true },
      { repository_binding_present: true },
      { quarantine_present: true },
    ]
  ) {
    const test = await capability(authority(unsafe));
    await assertRejects(() => test.inspect(input));
    assertEquals(test.inspectorCalls.length, 0);
  }
});

Deno.test("recovery prerequisite inspector receives only server authority", async () => {
  const test = await capability(authority());
  await test.inspect(input);
  assertEquals(test.inspectorCalls.length, 1);
  assertEquals(test.inspectorCalls[0], {
    websiteWorkContextId: CONTEXT_ID,
    repositoryId: REPOSITORY_ID,
    owner: OWNER,
    repository: REPOSITORY,
    private: true,
    defaultBranch: "main",
    snapshotTreeSha256: "b".repeat(64),
    markerContent: JSON.stringify(
      {
        schema_version: 1,
        environment: "TEST",
        organization: OWNER,
        website_work_context_id: CONTEXT_ID,
        repository_provisioning_operation_id: OPERATION_ID,
        starter_source: "lorenzo-web-solutions/lws-website-starter",
        starter_version: "v1.0.0",
        starter_commit_sha: "a".repeat(40),
        starter_tree_sha256: "b".repeat(64),
      },
      null,
      2,
    ) + "\n",
  });
});

Deno.test("internal recovery inspection projects exact server-derived write authority", async () => {
  const module = await implementation();
  assert(
    typeof module.createTask13RecoveryAuthorityInspection === "function",
    "server-authoritative recovery writer inspection is missing",
  );
  const inspect = module.createTask13RecoveryAuthorityInspection(config(), {
    rpc: () => Promise.resolve({ data: authority(), error: null }),
    inspectRepository: () =>
      Promise.resolve({ state: "EMPTY_OR_UNINITIALIZED" }),
  });
  assertEquals(await inspect(input), {
    state: "EMPTY_OR_UNINITIALIZED",
    authority: {
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
      markerContent: JSON.stringify(
        {
          schema_version: 1,
          environment: "TEST",
          organization: OWNER,
          website_work_context_id: CONTEXT_ID,
          repository_provisioning_operation_id: OPERATION_ID,
          starter_source: "lorenzo-web-solutions/lws-website-starter",
          starter_version: "v1.0.0",
          starter_commit_sha: "a".repeat(40),
          starter_tree_sha256: "b".repeat(64),
        },
        null,
        2,
      ) + "\n",
    },
  });
});

Deno.test("recovery prerequisite composition passes through only closed classifications", async () => {
  for (
    const state of [
      "EMPTY_OR_UNINITIALIZED",
      "ALREADY_COMPLETE",
      "MARKER_MISSING",
      "CONFLICT",
    ]
  ) {
    const test = await capability(authority(), state);
    assertEquals(await test.inspect(input), {
      authority_valid: true,
      repository_identity_valid: true,
      state_classification: state,
    });
  }
  const uncertain = await capability(authority(), "UNKNOWN");
  await assertRejects(() => uncertain.inspect(input));
});

Deno.test("recovery prerequisite composition fails closed on transport uncertainty", async () => {
  const module = await implementation();
  assert(
    typeof module.createTask13RecoveryPrerequisiteInspection === "function",
  );
  for (
    const rpc of [
      () => Promise.resolve({ data: authority(), error: { message: "raw" } }),
      () => Promise.reject(new Error("raw RPC transport detail")),
    ]
  ) {
    let inspectorCalls = 0;
    const inspect = module.createTask13RecoveryPrerequisiteInspection(
      config(),
      {
        rpc,
        inspectRepository: () => {
          inspectorCalls++;
          return Promise.resolve({ state: "ALREADY_COMPLETE" });
        },
      },
    );
    await assertRejects(() => inspect(input));
    assertEquals(inspectorCalls, 0);
  }

  const inspect = module.createTask13RecoveryPrerequisiteInspection(config(), {
    rpc: () => Promise.resolve({ data: authority(), error: null }),
    inspectRepository: () =>
      Promise.reject(new Error("raw GitHub transport detail")),
  });
  await assertRejects(() => inspect(input));
});

Deno.test("recovery prerequisite authority classifies only RPC infrastructure", async () => {
  const module = await implementation();
  assert(
    typeof module.createTask13RecoveryPrerequisiteInspection === "function",
  );
  for (
    const rpc of [
      () => Promise.resolve(null as never),
      () => Promise.resolve({ data: null, error: null }),
      () => Promise.resolve({ data: authority(), error: { message: "raw" } }),
      () => Promise.reject(new Error("raw RPC transport detail")),
    ]
  ) {
    const inspect = module.createTask13RecoveryPrerequisiteInspection(
      config(),
      {
        rpc,
        inspectRepository: () =>
          Promise.reject(new Error("inspector must not run")),
      },
    );
    const error = await assertRejects(() => inspect(input)) as Error & {
      failedInspectionPhase?: string;
    };
    assertEquals(error.failedInspectionPhase, "RECOVERY_AUTHORITY");
  }

  const rejected = await capability(authority({ bound_at_present: true }));
  const rejection = await assertRejects(() => rejected.inspect(input)) as
    & Error
    & { failedInspectionPhase?: string };
  assertEquals(rejection.failedInspectionPhase, undefined);
});

Deno.test("recovery authority diagnostic is immutable and cannot be prototype forged", () => {
  const error = new Task13RecoveryAuthorityDiagnosticError();
  assertEquals(hasValidatedTask13RecoveryAuthorityDiagnostic(error), true);
  assertThrows(
    () =>
      Object.assign(error, {
        failedInspectionPhase: "LAB_POST_CREATE_METADATA_READ",
      }),
    TypeError,
  );
  const forged = Object.assign(
    Object.create(Task13RecoveryAuthorityDiagnosticError.prototype),
    { failedInspectionPhase: "RECOVERY_AUTHORITY" },
  );
  assertEquals(hasValidatedTask13RecoveryAuthorityDiagnostic(forged), false);
});

Deno.test("recovery inspection failure phases are frozen at runtime", () => {
  assertEquals(
    Object.isFrozen(TASK13_RECOVERY_INSPECTION_FAILURE_PHASES),
    true,
  );
  assertThrows(
    () =>
      (TASK13_RECOVERY_INSPECTION_FAILURE_PHASES as unknown as string[]).push(
        "LAB_POST_CREATE_BLOB_WRITE",
      ),
    TypeError,
  );
});

Deno.test("recovery prerequisite preserves every first causal readback boundary", async () => {
  const module = await implementation();
  assert(typeof module.createTask13RecoveryAuthorityInspection === "function");
  for (
    const subphase of [
      "LAB_POST_CREATE_READBACK_TOKEN_ACQUIRE",
      "LAB_POST_CREATE_METADATA_READ",
      "LAB_POST_CREATE_SNAPSHOT_READBACK",
      "LAB_POST_CREATE_MARKER_READBACK",
      "LAB_POST_CREATE_PROVENANCE_VALIDATE",
    ] as const
  ) {
    for (
      const diagnostic of [
        new GitHubRepositoryStateInspectionError(
          "REPOSITORY_STATE_UNCERTAIN",
          subphase,
        ),
        new GitHubLabPostCreateDiagnosticError(subphase),
      ]
    ) {
      const inspect = module.createTask13RecoveryAuthorityInspection(config(), {
        rpc: () => Promise.resolve({ data: authority(), error: null }),
        inspectRepository: () => Promise.reject(diagnostic),
      });
      const error = await assertRejects(
        () => inspect(input),
        GitHubLabPostCreateDiagnosticError,
      );
      assertEquals(error.subphase, subphase);
    }
  }
});

Deno.test("internal recovery inspection preserves trusted readback diagnostics", async () => {
  const module = await implementation();
  assert(typeof module.createTask13RecoveryAuthorityInspection === "function");
  const DiagnosticStateError =
    GitHubRepositoryStateInspectionError as unknown as new (
      code: "REPOSITORY_STATE_UNCERTAIN",
      subphase: "LAB_POST_CREATE_SNAPSHOT_READBACK",
    ) => Error;
  const inspect = module.createTask13RecoveryAuthorityInspection(config(), {
    rpc: () => Promise.resolve({ data: authority(), error: null }),
    inspectRepository: () =>
      Promise.reject(
        new DiagnosticStateError(
          "REPOSITORY_STATE_UNCERTAIN",
          "LAB_POST_CREATE_SNAPSHOT_READBACK",
        ),
      ),
  });
  const error = await assertRejects(
    () => inspect(input),
    GitHubLabPostCreateDiagnosticError,
  );
  assertEquals(error.subphase, "LAB_POST_CREATE_SNAPSHOT_READBACK");
});

Deno.test("recovery prerequisite preserves the first causal snapshot check", async () => {
  const module = await implementation();
  assert(typeof module.createTask13RecoveryAuthorityInspection === "function");
  const DiagnosticStateError =
    GitHubRepositoryStateInspectionError as unknown as new (
      code: "REPOSITORY_STATE_UNCERTAIN",
      subphase: "LAB_POST_CREATE_SNAPSHOT_READBACK",
      snapshotReadbackCheck: "TREE_READ",
    ) => Error;
  const inspect = module.createTask13RecoveryAuthorityInspection(config(), {
    rpc: () => Promise.resolve({ data: authority(), error: null }),
    inspectRepository: () =>
      Promise.reject(
        new DiagnosticStateError(
          "REPOSITORY_STATE_UNCERTAIN",
          "LAB_POST_CREATE_SNAPSHOT_READBACK",
          "TREE_READ",
        ),
      ),
  });
  const error = await assertRejects(
    () => inspect(input),
    GitHubLabPostCreateDiagnosticError,
  ) as GitHubLabPostCreateDiagnosticError & {
    snapshotReadbackCheck?: string;
  };
  assertEquals(error.subphase, "LAB_POST_CREATE_SNAPSHOT_READBACK");
  assertEquals(error.snapshotReadbackCheck, "TREE_READ");
});

Deno.test("recovery prerequisite preserves one trusted REF_READ pair", async () => {
  const module = await implementation();
  assert(typeof module.createTask13RecoveryAuthorityInspection === "function");
  assert(
    typeof module.getValidatedTask13RefReadDiagnostic === "function",
    "trusted recovery REF_READ diagnostic accessor is missing",
  );
  const DiagnosticStateError =
    GitHubRepositoryStateInspectionError as unknown as new (
      code: "REPOSITORY_STATE_UNCERTAIN",
      subphase: "LAB_POST_CREATE_SNAPSHOT_READBACK",
      check: "REF_READ",
      diagnostic: Readonly<{ boundary: string; code: string }>,
    ) => Error;
  const inspect = module.createTask13RecoveryAuthorityInspection(config(), {
    rpc: () => Promise.resolve({ data: authority(), error: null }),
    inspectRepository: () =>
      Promise.reject(
        new DiagnosticStateError(
          "REPOSITORY_STATE_UNCERTAIN",
          "LAB_POST_CREATE_SNAPSHOT_READBACK",
          "REF_READ",
          createGitHubRefReadDiagnostic(
            "HTTP_STATUS",
            "GITHUB_HTTP_FORBIDDEN",
          ),
        ),
      ),
  });
  const error = await assertRejects(
    () => inspect(input),
    GitHubLabPostCreateDiagnosticError,
  );
  assertEquals(module.getValidatedTask13RefReadDiagnostic(error), {
    boundary: "HTTP_STATUS",
    code: "GITHUB_HTTP_FORBIDDEN",
  });
  let trapCalls = 0;
  const hostile = new Proxy({}, {
    get() {
      trapCalls++;
      throw new Error("raw proxy detail");
    },
  });
  assertEquals(module.getValidatedTask13RefReadDiagnostic(hostile), {
    boundary: "UNKNOWN",
    code: "UNKNOWN",
  });
  assertEquals(trapCalls, 0);
});

Deno.test("recovery prerequisite composition source has no mutation dependency", async () => {
  const source = await Deno.readTextFile(
    new URL("./recovery-prerequisite-inspection.ts", import.meta.url),
  ).catch(() => "");
  assert(source.length > 0, "recovery prerequisite composition is missing");
  for (
    const forbidden of [
      "CREATE_REPOSITORY",
      "createRepository",
      "createLab",
      "provider.provision",
      "writeLabSnapshot",
      ".claim(",
      ".resume(",
      ".bind(",
      ".quarantine(",
      "CREATE_REF",
      "WRITE_PROJECT_MARKER",
      "CREATE_BLOB",
      "CREATE_TREE",
      "CREATE_COMMIT",
      "UPDATE_REF",
    ]
  ) assertEquals(source.includes(forbidden), false, forbidden);
});

Deno.test("recovery prerequisite composition rejects forged inspector results", async () => {
  const module = await implementation();
  assert(
    typeof module.createTask13RecoveryPrerequisiteInspection === "function",
  );
  const hidden = { state: "ALREADY_COMPLETE" };
  Object.defineProperty(hidden, "raw", { value: "secret" });
  const symbol = Object.assign(
    { state: "ALREADY_COMPLETE" },
    { [Symbol("raw")]: "secret" },
  );
  const proxy = new Proxy({ state: "ALREADY_COMPLETE" }, {
    ownKeys: () => {
      throw new Error("proxy secret");
    },
  });
  for (
    const result of [
      { state: "ALREADY_COMPLETE", raw: "secret" },
      Object.assign(Object.create({ raw: "secret" }), {
        state: "ALREADY_COMPLETE",
      }),
      Object.defineProperty({}, "state", {
        get: () => "ALREADY_COMPLETE",
        enumerable: true,
      }),
      hidden,
      symbol,
      proxy,
    ]
  ) {
    const inspect = module.createTask13RecoveryPrerequisiteInspection(
      config(),
      {
        rpc: () => Promise.resolve({ data: authority(), error: null }),
        inspectRepository: () => Promise.resolve(result),
      },
    );
    await assertRejects(() => inspect(input));
  }
});
