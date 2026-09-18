import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  GitHubHttpError,
  type GitHubHttpOperation,
} from "../_shared/github-http.ts";
import {
  createExactRepositoryInstallationVisibilityProof,
  RepositoryInstallationVisibilityProofError,
} from "./repository-installation-visibility.ts";

const APP_JWT = "synthetic.app.jwt";
const AUTHORITY = Object.freeze({
  appId: "4932372",
  installationId: "161461160",
  organization: "lorenzo-web-solutions-lab",
  repository: "lws-web-33a61b581d554624bdb73c724d35ebcc",
});

function harness(input: Readonly<{
  httpError?: unknown;
  result?: unknown;
  signingError?: unknown;
}> = {}) {
  const calls: string[] = [];
  const operations: GitHubHttpOperation[] = [];
  const prove = createExactRepositoryInstallationVisibilityProof(AUTHORITY, {
    signAppJwt(appId) {
      calls.push("APP_JWT_SIGN");
      assertEquals(appId, AUTHORITY.appId);
      if (input.signingError) return Promise.reject(input.signingError);
      return Promise.resolve(APP_JWT);
    },
    http: {
      execute(operation) {
        calls.push("REPOSITORY_INSTALLATION_PROOF");
        operations.push(operation);
        if (input.httpError) return Promise.reject(input.httpError);
        return Promise.resolve((input.result ?? { proven: true }) as never);
      },
    },
  });
  return { prove, calls, operations };
}

Deno.test("exact repository-installation visibility proof signs and reads only fixed authority", async () => {
  const test = harness();
  assertEquals(await test.prove(), true);
  assertEquals(test.calls, ["APP_JWT_SIGN", "REPOSITORY_INSTALLATION_PROOF"]);
  assertEquals(test.operations, [{
    kind: "REPOSITORY_INSTALLATION_PROOF",
    owner: AUTHORITY.organization,
    repository: AUTHORITY.repository,
    expectedInstallationId: AUTHORITY.installationId,
    expectedOrganization: AUTHORITY.organization,
    appJwt: APP_JWT,
  }]);
});

Deno.test("repository-installation proof 404 means visibility unproven only", async () => {
  const test = harness({
    httpError: new GitHubHttpError("GITHUB_HTTP_NOT_FOUND"),
  });
  assertEquals(await test.prove(), false);
});

Deno.test("repository-installation proof preserves validated non-404 HTTP boundaries", async () => {
  const upstream = new GitHubHttpError(
    "GITHUB_HTTP_RESPONSE_INVALID",
    null,
    null,
    undefined,
    "RESPONSE_SCHEMA",
  );
  const test = harness({ httpError: upstream });
  const error = await assertRejects(test.prove, GitHubHttpError);
  assertEquals(error, upstream);
  assertEquals(error.boundary, "RESPONSE_SCHEMA");
});

Deno.test("repository-installation proof failures are closed", async () => {
  const secret = "raw App JWT Authorization stack cause details hint";
  for (
    const input of [
      { signingError: new Error(secret) },
      { httpError: new Error(secret) },
      { result: { proven: false, raw: secret } },
    ]
  ) {
    const test = harness(input);
    const error = await assertRejects(
      test.prove,
      RepositoryInstallationVisibilityProofError,
    );
    assertEquals(
      (error as Error).message,
      "REPOSITORY_INSTALLATION_VISIBILITY_PROOF_FAILED",
    );
    assertEquals(JSON.stringify(error).includes(secret), false);
  }
});
