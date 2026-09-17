import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import type { GitHubTask13RuntimeConfig } from "../_shared/github-app-config.ts";
import {
  GitHubHttpError,
  type GitHubHttpOperation,
} from "../_shared/github-http.ts";
import {
  GitHubLabPrivateVisibilityUnprovenError,
  GitHubLabRepositoryTokenError,
} from "../_shared/github-repository-runtime.ts";
import {
  createTask13LabReadonlyReconciler,
  TASK13_SYNTHETIC_AUTHORITY,
  Task13LabReadonlyError,
} from "./readonly-reconciliation.ts";

const TOKEN = `ghs_${"a".repeat(36)}`;

function config(): GitHubTask13RuntimeConfig {
  const common = {
    enabled: true as const,
    appId: "4932372",
    templateOwner: "lorenzo-web-solutions",
    templateName: "lws-website-starter",
    templateRepositoryId: "1368684860",
    starterVersion: "1.0.0",
    starterCommitSha: "a".repeat(40),
    starterTreeSha256: "b".repeat(64),
    privateKey: "synthetic-private-key",
  };
  return Object.freeze({
    production: Object.freeze({
      ...common,
      target: "PRODUCTION" as const,
      installationId: "161436785",
      organization: "lorenzo-web-solutions",
    }),
    lab: Object.freeze({
      ...common,
      target: "TEST" as const,
      installationId: TASK13_SYNTHETIC_AUTHORITY.installationId,
      organization: TASK13_SYNTHETIC_AUTHORITY.organization,
    }),
  });
}

function harness(input: Readonly<{
  visibility?: boolean;
  tokenError?: unknown;
  httpResult?: unknown;
  httpError?: unknown;
}> = {}) {
  const tokenCalls: unknown[] = [];
  const httpCalls: GitHubHttpOperation[] = [];
  const reconcile = createTask13LabReadonlyReconciler(config(), {
    readRepository(readInput) {
      tokenCalls.push(readInput);
      if (input.tokenError) {
        return Promise.reject(new GitHubLabRepositoryTokenError());
      }
      if (!input.visibility) {
        return Promise.reject(new GitHubLabPrivateVisibilityUnprovenError());
      }
      httpCalls.push({
        kind: "REPOSITORY_METADATA",
        owner: readInput.organization,
        repository: readInput.repository,
        token: TOKEN,
      });
      if (input.httpError) return Promise.reject(input.httpError);
      return Promise.resolve(input.httpResult as never);
    },
  });
  return { reconcile, tokenCalls, httpCalls };
}

Deno.test("readonly reconciliation stops before metadata when private LAB visibility is unproven", async () => {
  const test = harness();
  const error = await assertRejects(
    test.reconcile,
    Task13LabReadonlyError,
    "TASK13_LAB_PRIVATE_VISIBILITY_UNPROVEN",
  );
  assertEquals(error.code, "TASK13_LAB_PRIVATE_VISIBILITY_UNPROVEN");
  assertEquals(test.tokenCalls.length, 1);
  assertEquals(test.httpCalls, []);
});

Deno.test("readonly reconciliation derives only the fixed LAB target", async () => {
  const test = harness();
  await assertRejects(test.reconcile, Task13LabReadonlyError);
  assertEquals(test.tokenCalls[0], {
    websiteWorkContextId: TASK13_SYNTHETIC_AUTHORITY.websiteWorkContextId,
    organization: "lorenzo-web-solutions-lab",
    repository: "lws-web-33a61b581d554624bdb73c724d35ebcc",
  });
});

Deno.test("readonly reconciliation returns found false only after proven visibility and exact 404", async () => {
  const test = harness({
    visibility: true,
    httpError: new GitHubHttpError("GITHUB_HTTP_NOT_FOUND"),
  });
  assertEquals(await test.reconcile(), {
    principal_type: "GITHUB_APP_INSTALLATION",
    installation_id_match: true,
    private_lab_visibility_proven: true,
    found: false,
  });
  assertEquals(
    test.httpCalls.map((operation) => ({ ...operation, token: "redacted" })),
    [{
      kind: "REPOSITORY_METADATA",
      owner: "lorenzo-web-solutions-lab",
      repository: "lws-web-33a61b581d554624bdb73c724d35ebcc",
      token: "redacted",
    }],
  );
});

Deno.test("readonly reconciliation projects only safe exact repository metadata", async () => {
  const test = harness({
    visibility: true,
    httpResult: {
      repositoryId: "1369000001",
      nodeId: "R_task13_repository",
      owner: TASK13_SYNTHETIC_AUTHORITY.organization,
      name: TASK13_SYNTHETIC_AUTHORITY.repository,
      fullName:
        `${TASK13_SYNTHETIC_AUTHORITY.organization}/${TASK13_SYNTHETIC_AUTHORITY.repository}`,
      private: true,
      defaultBranch: "main",
      description: null,
      createdAt: "2026-09-14T12:00:00.000Z",
    },
  });
  assertEquals(await test.reconcile(), {
    principal_type: "GITHUB_APP_INSTALLATION",
    installation_id_match: true,
    private_lab_visibility_proven: true,
    found: true,
    repository_id: "1369000001",
    node_id_present: true,
    owner: "lorenzo-web-solutions-lab",
    name: "lws-web-33a61b581d554624bdb73c724d35ebcc",
    private: true,
    visibility: "PRIVATE",
    default_branch_present: true,
    created_at_present: true,
  });
  assertEquals(test.httpCalls.length, 1);
});

Deno.test("readonly reconciliation closes token transport and response failures", async () => {
  const scenarios = [
    {
      input: { tokenError: new Error("raw token secret") },
      code: "TASK13_LAB_RECONCILIATION_TOKEN_FAILED",
      reads: 0,
    },
    {
      input: { visibility: true, httpError: new Error("raw transport secret") },
      code: "TASK13_LAB_RECONCILIATION_READ_FAILED",
      reads: 1,
    },
    {
      input: {
        visibility: true,
        httpError: new GitHubHttpError("GITHUB_HTTP_RESPONSE_INVALID"),
      },
      code: "TASK13_LAB_RECONCILIATION_RESPONSE_INVALID",
      reads: 1,
    },
    {
      input: {
        visibility: true,
        httpResult: {
          repositoryId: "1369000001",
          nodeId: "R_task13_repository",
          owner: "attacker",
          name: TASK13_SYNTHETIC_AUTHORITY.repository,
          private: true,
          defaultBranch: "main",
          description: null,
          createdAt: "2026-09-14T12:00:00.000Z",
        },
      },
      code: "TASK13_LAB_RECONCILIATION_RESPONSE_INVALID",
      reads: 1,
    },
    {
      input: {
        visibility: true,
        httpResult: {
          repositoryId: "1369000001",
          nodeId: "R_task13_repository",
          owner: TASK13_SYNTHETIC_AUTHORITY.organization,
          name: TASK13_SYNTHETIC_AUTHORITY.repository,
          private: true,
          defaultBranch: "main",
          description: null,
          createdAt: "not-a-timestamp",
        },
      },
      code: "TASK13_LAB_RECONCILIATION_RESPONSE_INVALID",
      reads: 1,
    },
  ] as const;
  for (const scenario of scenarios) {
    const test = harness(scenario.input);
    const error = await assertRejects(test.reconcile, Task13LabReadonlyError);
    assertEquals(error.code, scenario.code);
    assertEquals(test.httpCalls.length, scenario.reads);
    assertEquals(JSON.stringify(error).includes("raw"), false);
  }
});
