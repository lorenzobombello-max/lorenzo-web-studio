import { assert, assertEquals } from "jsr:@std/assert@1";
import { createTask13RecoveryHandler } from "./index.ts";

const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
const recoveryInspectionSource = await Deno.readTextFile(
  new URL("./recovery-prerequisite-inspection.ts", import.meta.url),
);
const readonlyStart = source.indexOf("const createReadonlyReconciler = async");
const readonlyEnd = source.indexOf("const response =", readonlyStart);
const readonlyComposition = source.slice(readonlyStart, readonlyEnd);
const recoveryStart = source.indexOf("const createRecoveryWriter = async");
const recoveryEnd = source.indexOf("const response =", recoveryStart);
const recoveryComposition = source.slice(recoveryStart, recoveryEnd);
const finalizerStart = source.indexOf(
  "const finalizePostRecoveryRepository = async",
);
const finalizerEnd = source.indexOf("const createRecoveryWriter = async");
const finalizerComposition = source.slice(finalizerStart, finalizerEnd);
const recoveryHandlerStart = source.indexOf(
  "recoverPostCreateExistingRepository: async",
);
const recoveryHandlerEnd = source.indexOf("\n        },", recoveryHandlerStart);
const recoveryHandler = source.slice(recoveryHandlerStart, recoveryHandlerEnd);

Deno.test("Task 13 production authority uses its guarded read RPC", () => {
  assert(source.includes("verify_task13_synthetic_context_authority_v1"));
  assertEquals(source.includes('.from("website_work_contexts")'), false);
  assertEquals(source.includes('.from("website_execution_workspaces")'), false);
});

Deno.test("Task 13 production index wires the real App-JWT visibility proof", () => {
  assert(readonlyStart >= 0 && readonlyEnd > readonlyStart);
  assert(readonlyComposition.includes("initializeGitHubAppJwtSigner("));
  assert(
    readonlyComposition.includes(
      "createExactRepositoryInstallationVisibilityProof(",
    ),
  );
  assert(readonlyComposition.includes("TASK13_SYNTHETIC_AUTHORITY.repository"));
  assert(readonlyComposition.includes("return await proveVisibility()"));
  assertEquals(readonlyComposition.includes("() => false"), false);
});

Deno.test("Task 13 production readonly composition cannot reach mutation dependencies", () => {
  for (
    const forbidden of [
      "createStore(",
      ".claim(",
      ".resume(",
      ".fail(",
      ".bind(",
      "createProvider(",
      "createRuntime(",
      ".capture(",
      ".quarantine(",
      "CREATE_REPOSITORY",
      "CREATE_BOOTSTRAP_FILE",
      "UPDATE_REF",
      "WRITE_PROJECT_MARKER",
    ]
  ) {
    assertEquals(readonlyComposition.includes(forbidden), false, forbidden);
  }
});

Deno.test("Task 13 production graph wires recovery authority and repository inspector", () => {
  assert(source.includes("createTask13RecoveryPrerequisiteInspection"));
  assert(source.includes("createGitHubRepositoryStateInspectionCapability"));
  assert(
    recoveryInspectionSource.includes(
      "get_task13_repository_recovery_authority_v1",
    ),
  );
});

Deno.test("Task 13 production finalizer has one read-proof and dedicated transition graph", () => {
  assert(finalizerStart >= 0 && finalizerEnd > finalizerStart);
  assert(
    finalizerComposition.includes(
      "createGitHubRepositoryCompletionProofCapability",
    ),
  );
  assert(
    finalizerComposition.includes(
      '"get_task13_repository_recovery_authority_v1"',
    ),
  );
  assert(
    finalizerComposition.includes("store.finalizeRecoveredRepository("),
  );
  assert(
    finalizerComposition.includes("const authorityClient = clientFor(jwt)"),
  );
  assert(finalizerComposition.includes("serviceClient.rpc(name, arguments_)"));
  assert(finalizerComposition.includes("actorAuthUserId: actor.authUserId"));
  for (
    const forbidden of [
      "createTask13PostCreateRecoveryWriter",
      "createTask13PostCreateRecoveryWriteCapability",
      "writeCanonicalSnapshotToEmptyRepository",
      "writeMissingMarker",
      ".claim(",
      ".resume(",
      ".bind(",
      ".fail(",
      ".quarantine(",
      "CREATE_REPOSITORY",
      "CREATE_BOOTSTRAP_FILE",
      "UPDATE_REF",
      "WRITE_PROJECT_MARKER",
    ]
  ) assertEquals(finalizerComposition.includes(forbidden), false, forbidden);
});

Deno.test("Task 13 production index composes only the narrow recovery writer path", () => {
  assert(source.includes('from "./post-create-recovery-writer.ts"'));
  assert(source.includes('from "./post-create-recovery-write-capability.ts"'));
  assert(recoveryStart >= 0 && recoveryEnd > recoveryStart);
  assert(
    recoveryComposition.includes("createTask13RecoveryAuthorityInspection"),
  );
  assert(recoveryComposition.includes("createTask13PostCreateRecoveryWriter"));
  assert(
    recoveryComposition.includes(
      "createTask13PostCreateRecoveryWriteCapability",
    ),
  );
  for (
    const forbidden of [
      "createProvider(",
      "createRuntime(",
      "createStore(",
      ".claim(",
      ".resume(",
      ".bind(",
      ".fail(",
      ".quarantine(",
      "CREATE_REPOSITORY",
      "UPDATE_REF",
    ]
  ) assertEquals(recoveryComposition.includes(forbidden), false, forbidden);
});

Deno.test("Task 13 production recovery callback invokes only writer recovery", async () => {
  assert(
    recoveryHandlerStart >= 0 && recoveryHandlerEnd > recoveryHandlerStart,
  );
  assert(
    recoveryHandler.includes("recoverPostCreateExistingRepository(jwt, input)"),
  );
  for (
    const forbidden of [
      "execute(",
      "createProvider(",
      "createRuntime(",
      "createStore(",
      ".claim(",
      ".resume(",
      ".bind(",
      ".fail(",
      ".quarantine(",
      "CREATE_REPOSITORY",
      "UPDATE_REF",
    ]
  ) assertEquals(recoveryHandler.includes(forbidden), false, forbidden);

  const calls: unknown[] = [];
  const input = Object.freeze({
    operationId: "e646ae44-ec5d-46b6-96e3-b1023b9e1b68",
    websiteWorkContextId: "33a61b58-1d55-4624-bdb7-3c724d35ebcc",
    websiteWorkspaceId: "4dfe44a5-60d0-4728-b62b-ef87aa838976",
  });
  const recover = createTask13RecoveryHandler(async (jwt) => {
    calls.push(["CREATE_WRITER", jwt]);
    return Object.freeze({
      recover(received: typeof input) {
        calls.push(["RECOVER", received]);
        return Promise.resolve(
          Object.freeze({ status: "ALREADY_COMPLETE" as const }),
        );
      },
    });
  });
  assertEquals(await recover("verified-caller-jwt", input), {
    status: "ALREADY_COMPLETE",
  });
  assertEquals(calls, [
    ["CREATE_WRITER", "verified-caller-jwt"],
    ["RECOVER", input],
  ]);
});
