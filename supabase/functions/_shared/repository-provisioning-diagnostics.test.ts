import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  GitHubTokenAcquireDiagnosticError,
  type GitHubTokenAcquireHttpStatus,
} from "./repository-provisioning-diagnostics.ts";

// ==========================================================================
// GitHubTokenAcquireDiagnosticError.tokenAcquireHttpStatus contract
// ==========================================================================
//
// This is the shared base class both github-http.ts's GitHubHttpError and
// github-app-token.ts's GitHubTokenBrokerError extend. It carries the
// already-safe, already-validated exact numeric GitHub HTTP status, but ONLY
// ever one of the two conflict-class statuses (409/422) -- proven directly
// here, independent of either subclass, so the contract itself is pinned
// regardless of how callers further up the chain choose to use it.

Deno.test("GitHubTokenAcquireDiagnosticError accepts the exact safe numeric status (409 and 422)", () => {
  for (const status of [409, 422] as const) {
    const error = new GitHubTokenAcquireDiagnosticError(
      "GITHUB_TOKEN_EXCHANGE_FAILURE",
      "TOKEN_HTTP_STATUS",
      undefined,
      undefined,
      status,
    );
    assertEquals(error.tokenAcquireHttpStatus, status);
    assertEquals(error.tokenAcquireSubphase, "TOKEN_HTTP_STATUS");
  }
});

Deno.test("GitHubTokenAcquireDiagnosticError rejects any numeric status outside the 409/422 whitelist", () => {
  for (const status of [400, 418, 500] as const) {
    assertThrows(
      () =>
        new GitHubTokenAcquireDiagnosticError(
          "GITHUB_TOKEN_EXCHANGE_FAILURE",
          "TOKEN_HTTP_STATUS",
          undefined,
          undefined,
          // deno-lint-ignore no-explicit-any
          status as any,
        ),
      Error,
      "GITHUB_TOKEN_ACQUIRE_HTTP_STATUS_INVALID",
    );
  }
});

Deno.test("GitHubTokenAcquireDiagnosticError rejects arbitrary non-numeric or out-of-range values", () => {
  for (const value of [0, -409, 409.5, NaN, Infinity] as const) {
    assertThrows(
      () =>
        new GitHubTokenAcquireDiagnosticError(
          "GITHUB_TOKEN_EXCHANGE_FAILURE",
          "TOKEN_HTTP_STATUS",
          undefined,
          undefined,
          // deno-lint-ignore no-explicit-any
          value as any,
        ),
      Error,
      "GITHUB_TOKEN_ACQUIRE_HTTP_STATUS_INVALID",
    );
  }
});

Deno.test("GitHubTokenAcquireDiagnosticError treats absence of the status as valid regardless of subphase", () => {
  const withSubphase = new GitHubTokenAcquireDiagnosticError(
    "GITHUB_TOKEN_EXCHANGE_FAILURE",
    "TOKEN_HTTP_STATUS",
  );
  assertEquals(withSubphase.tokenAcquireHttpStatus, undefined);

  const withoutSubphase = new GitHubTokenAcquireDiagnosticError(
    "GITHUB_TOKEN_EXCHANGE_FAILURE",
  );
  assertEquals(withoutSubphase.tokenAcquireHttpStatus, undefined);

  // The base class intentionally does not require TOKEN_HTTP_STATUS to
  // accept a status (context-specific gating belongs to the subclasses one
  // layer up), but every already-existing caller in this codebase only ever
  // supplies the status alongside TOKEN_HTTP_STATUS -- this proves the base
  // class does not itself force that pairing, so it stays reusable and
  // GitHubHttpError's generic (non-token-exchange) repository-read errors,
  // which never set tokenAcquireSubphase at all, are unaffected.
  const genericReadStatus: GitHubTokenAcquireHttpStatus = 409;
  const genericRead = new GitHubTokenAcquireDiagnosticError(
    "GITHUB_HTTP_CONFLICT",
    undefined,
    undefined,
    undefined,
    genericReadStatus,
  );
  assertEquals(genericRead.tokenAcquireHttpStatus, 409);
});

Deno.test("GitHubTokenAcquireDiagnosticError never introduces public/raw provider information", () => {
  const error = new GitHubTokenAcquireDiagnosticError(
    "GITHUB_TOKEN_EXCHANGE_FAILURE",
    "TOKEN_HTTP_STATUS",
    undefined,
    undefined,
    409,
  );
  const serialized = `${error.message}\n${error.stack}\n${
    JSON.stringify(error)
  }`;
  assert(!/authorization|bearer|jwt|private.?key|ghs_[a-z0-9]{30,}/i.test(serialized));
  // Only the pre-approved enum members (plus the class's own `name` and the
  // always-declared, here-undefined `tokenLeaseCheck` field) appear -- no
  // raw response body, no headers, no request id, no provider-authored text.
  assertEquals(Object.keys(error).sort(), [
    "name",
    "tokenAcquireHttpStatus",
    "tokenAcquireSubphase",
    "tokenLeaseCheck",
  ]);
});
