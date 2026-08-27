import { assertEquals } from "jsr:@std/assert@1";
import {
  createUnsignedTestJwt,
  executeAssignmentOperatorRosterTransport,
  executeDossierAssignmentMutationTransport,
  executeDossierAssignmentReadTransport,
  executeDossierLifecycleTransport,
  executeCustomerRequestTransport,
  executeCurrentOperatorIdentityTransport,
  executeOperatorPersonalQueueTransport,
  handleCommercialOperator,
  withCommercialOperatorCors
} from "./handler.ts";
import { OPERATOR_CURSOR_TTL_MS, signOperatorCursor, verifyOperatorCursor } from "../_shared/operator-cursor.ts";
import { executeCallerJwtAssignmentRosterAction, executeCallerJwtCurrentOperatorIdentityAction, executeCallerJwtCustomerRequestAction, executeCallerJwtCustomerRequestSmokeFixtureAction, executeCallerJwtCustomerRequestUploadAction, executeCallerJwtDossierAssignmentAction, executeCallerJwtOperatorPersonalQueueAction } from "./index.ts";

const userId = "a1000000-0000-4000-8000-000000000001";
const jwt = createUnsignedTestJwt({ sub: userId, role: "authenticated", exp: 4102444800 });
const cursorSecret = "ERERERERERERERERERERERERERERERERERERERERERE";

function request(body: Record<string, unknown>, token = jwt) {
  return new Request("https://example.test", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", Origin: "https://lorenzowebsolutions.be" },
    body: JSON.stringify(body)
  });
}

function cursorRequest(input: Record<string, unknown>) {
  return {
    zone: input.zone as "ACTIVE" | "ARCHIVED" | "TRASHED" | "ACTIVE_ARCHIVED",
    operationalStatus: input.operational_status as string | null,
    year: input.year as number | null,
    quarter: input.quarter as "Q1" | "Q2" | "Q3" | "Q4" | null,
    requestKind: input.request_kind as "website" | "slimme_documentenflow" | null,
    search: input.search as string | null,
  };
}

function dependencies(overrides: Record<string, unknown> = {}) {
  const calls: Array<{ jwt: string; input: Record<string, unknown> }> = [];
  const events: string[] = [];
  return {
    calls,
    events,
    deps: {
      now: ()=>Date.now(),
      verifyUser: async ()=>({ id: userId }),
      authorizeApplicationReader: async ()=>{ events.push("preflight"); },
      verifyOperatorCursor: async (cursor: string, input: Record<string, unknown>)=>{
        events.push("verify");
        return await verifyOperatorCursor(cursor, cursorRequest(input), { now: 4_102_444_800_001, secret: cursorSecret });
      },
      executeApplicationListV2: async ()=>{
        events.push("core");
        return {
          items: [{ quote_request_id: userId }],
          has_more: true,
          next_position: { dossier_date: "2099-01-02T10:20:30+00:00", quote_request_id: userId }
        };
      },
      signOperatorCursor: async (position: Record<string, string>, input: Record<string, unknown>)=>{
        events.push("sign");
        return await signOperatorCursor({
          dossierDate: position.dossier_date,
          quoteRequestId: position.quote_request_id,
        }, cursorRequest(input), { now: 4_102_444_800_001, secret: cursorSecret });
      },
      executeApplicationFacetsV2: async ()=>{
        events.push("facets");
        return { years: [] };
      },
      consumeRateLimit: async ()=>({ allowed: true, retry_after_seconds: 0 }),
      executeCommand: async ()=>({ command: true }),
      executeApplicationAction: async (token: string, input: Record<string, unknown>)=>{
        calls.push({ jwt: token, input });
        return { action: input.action };
      },
      ...overrides,
    }
  };
}

const v2Input = {
  action: "list_applications_v2",
  zone: "ACTIVE_ARCHIVED",
  operational_status: "SUBMITTED",
  year: 2099,
  quarter: "Q1",
  request_kind: "website",
  search: "Example",
  limit: 1,
};

Deno.test("allowed production preflight returns the complete CORS contract without side effects", async ()=>{
  let nextCalls = 0;
  const response = await withCommercialOperatorCors(new Request("https://example.test", {
    method: "OPTIONS",
    headers: {
      Origin: "https://lorenzowebsolutions.be",
      "Access-Control-Request-Method": "POST",
      "Access-Control-Request-Headers": "authorization,content-type"
    }
  }), async ()=>{
    nextCalls += 1;
    return new Response(null, { status: 500 });
  });
  assertEquals(response.status, 204);
  assertEquals(response.headers.get("access-control-allow-origin"), "https://lorenzowebsolutions.be");
  assertEquals(response.headers.get("access-control-allow-headers"), "authorization,content-type,idempotency-key,x-requested-with");
  assertEquals(response.headers.get("access-control-allow-methods"), "GET,POST,OPTIONS");
  assertEquals(nextCalls, 0);
});

Deno.test("allowed production success and error responses include CORS", async ()=>{
  const successHarness = dependencies();
  const success = await withCommercialOperatorCors(request({ action: "list_applications" }),
    ()=>handleCommercialOperator(request({ action: "list_applications" }), successHarness.deps));
  assertEquals(success.status, 200);
  assertEquals(success.headers.get("access-control-allow-origin"), "https://lorenzowebsolutions.be");

  const error = await withCommercialOperatorCors(new Request("https://example.test", {
    method: "GET",
    headers: { Origin: "https://lorenzowebsolutions.be" }
  }), ()=>handleCommercialOperator(new Request("https://example.test", { method: "GET" }), dependencies().deps));
  assertEquals(error.status, 405);
  assertEquals(error.headers.get("access-control-allow-origin"), "https://lorenzowebsolutions.be");
});

Deno.test("disallowed origin is rejected before handler execution", async ()=>{
  let nextCalls = 0;
  const response = await withCommercialOperatorCors(new Request("https://example.test", {
    method: "POST",
    headers: { Origin: "https://attacker.example" }
  }), async ()=>{
    nextCalls += 1;
    return new Response(null, { status: 200 });
  });
  assertEquals(response.status, 403);
  assertEquals(response.headers.get("access-control-allow-origin"), "https://lorenzowebsolutions.be");
  assertEquals(nextCalls, 0);
});

Deno.test("application list uses the verified human JWT and bounded pagination", async ()=>{
  const harness = dependencies();
  const response = await handleCommercialOperator(request({ action: "list_applications", limit: 25, offset: 5 }), harness.deps);
  assertEquals(response.status, 200);
  assertEquals(harness.calls, [{ jwt, input: { action: "list_applications", limit: 25, offset: 5 } }]);
});

Deno.test("application detail requires exactly one valid locator", async ()=>{
  const harness = dependencies();
  const response = await handleCommercialOperator(request({ action: "get_application_detail", application_reference: "LWS-AAN-2099-0001" }), harness.deps);
  assertEquals(response.status, 200);
  assertEquals(harness.calls[0].input, { action: "get_application_detail", quote_request_id: null, application_reference: "LWS-AAN-2099-0001", support_reference: null });
  for (const applicationReference of ["lws-aan-2099-0001", " LWS-AAN-2099-0001 "]) {
    assertEquals((await handleCommercialOperator(request({
      action: "get_application_detail",
      application_reference: applicationReference
    }), harness.deps)).status, 400);
  }
  const ambiguous = await handleCommercialOperator(request({ action: "get_application_detail", quote_request_id: userId, application_reference: "LWS-AAN-2099-0001" }), harness.deps);
  assertEquals(ambiguous.status, 400);
  assertEquals(harness.calls.length, 1);
});

Deno.test("application detail normalizes one support-reference locator", async ()=>{
  const harness = dependencies();
  const response = await handleCommercialOperator(request({ action: "get_application_detail", support_reference: " f98b2f08 " }), harness.deps);
  assertEquals(response.status, 200);
  assertEquals(harness.calls[0].input, { action: "get_application_detail", quote_request_id: null, application_reference: null, support_reference: "#F98B2F08" });

  for (const body of [
    { action: "get_application_detail", support_reference: "#F98B2F0" },
    { action: "get_application_detail", support_reference: "#F98B2F08", quote_request_id: userId },
    { action: "promote_accepted_application", support_reference: "#F98B2F08", idempotency_key: "a1800000-0000-4000-8000-000000000001" }
  ]) {
    assertEquals((await handleCommercialOperator(request(body), harness.deps)).status, 400);
  }
  assertEquals(harness.calls.length, 1);
});

Deno.test("dossier assignment read accepts only one normalized reference", async ()=>{
  for (const [dossierReference, normalizedReference] of [
    [" LWS-AAN-2099-0001 ", "LWS-AAN-2099-0001"],
    [" f98b2f08 ", "#F98B2F08"],
    ["#f98b2f08", "#F98B2F08"]
  ]) {
    const harness = dependencies();
    const response = await handleCommercialOperator(request({
      action: "get_dossier_assignment",
      dossier_reference: dossierReference
    }), harness.deps);
    assertEquals(response.status, 200);
    assertEquals(harness.calls, [{
      jwt,
      input: { action: "get_dossier_assignment", dossier_reference: normalizedReference }
    }]);
    assertEquals(await response.json(), {
      ok: true,
      code: "APPLICATION_ACTION_ACCEPTED",
      result: { action: "get_dossier_assignment" }
    });
  }

  for (const invalid of [
    {},
    { dossier_reference: "invalid" },
    { dossier_reference: "LWS-AAN-2099-0001", quote_request_id: userId },
    { dossier_reference: "LWS-AAN-2099-0001", actor_id: userId }
  ]) {
    const harness = dependencies();
    const response = await handleCommercialOperator(request({
      action: "get_dossier_assignment",
      ...invalid
    }), harness.deps);
    assertEquals(response.status, 400);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("assignment roster accepts only the fixed read action", async ()=>{
  const harness = dependencies();
  const response = await handleCommercialOperator(request({
    action: "get_assignment_operator_roster"
  }), harness.deps);
  assertEquals(response.status, 200);
  assertEquals(harness.calls, [{
    jwt,
    input: { action: "get_assignment_operator_roster" }
  }]);
  assertEquals(await response.json(), {
    ok: true,
    code: "APPLICATION_ACTION_ACCEPTED",
    result: { action: "get_assignment_operator_roster" }
  });

  for (const extra of [{ role: "operator" }, { status: "ACTIVE" }, { actor_id: userId }]) {
    const invalidHarness = dependencies();
    const invalidResponse = await handleCommercialOperator(request({
      action: "get_assignment_operator_roster",
      ...extra
    }), invalidHarness.deps);
    assertEquals(invalidResponse.status, 400);
    assertEquals(invalidHarness.calls.length, 0);
  }
});

Deno.test("assignment roster uses the exact RPC and exposes only eligible picker fields", async ()=>{
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const result = await executeAssignmentOperatorRosterTransport({
    rpc: (name: string, args: Record<string, unknown>)=>{
      calls.push({ name, args });
      return Promise.resolve({
        data: [
          { operator_id: "a1800000-0000-4000-8000-000000000060", display_name: "Active Operator", role: "operator", status: "ACTIVE", auth_user_id: userId, email: "private@example.test", history: [{ event_type: "PRIVATE" }] },
          { operator_id: "a1800000-0000-4000-8000-000000000061", display_name: "Manager", role: "operations_manager", status: "ACTIVE" },
          { operator_id: "a1800000-0000-4000-8000-000000000062", display_name: "Owner", role: "owner", status: "ACTIVE" },
          { operator_id: "a1800000-0000-4000-8000-000000000063", display_name: "Disabled", role: "operator", status: "DISABLED" },
          { operator_id: "a1800000-0000-4000-8000-000000000064", display_name: "Revoked", role: "operator", status: "REVOKED" },
        ],
        error: null
      });
    }
  });
  assertEquals(calls, [{ name: "get_operations_manager_roster_v1", args: {} }]);
  assertEquals(result, [{
    operator_id: "a1800000-0000-4000-8000-000000000060",
    display_name: "Active Operator"
  }]);
  assertEquals(Object.keys(result[0]), ["operator_id", "display_name"]);
});

Deno.test("assignment roster preserves a valid empty eligible result", async ()=>{
  const result = await executeAssignmentOperatorRosterTransport({
    rpc: ()=>Promise.resolve({ data: [], error: null })
  });
  assertEquals(result, []);
});

Deno.test("index assignment roster dispatch constructs its RPC client from the caller JWT", async ()=>{
  const clientForCalls: string[] = [];
  const rpcCalls: string[] = [];
  const result = await executeCallerJwtAssignmentRosterAction(jwt, (token: string)=>{
    clientForCalls.push(token);
    return {
      rpc: (name: string)=>{
        rpcCalls.push(name);
        return Promise.resolve({ data: [], error: null });
      }
    };
  });
  assertEquals(clientForCalls, [jwt]);
  assertEquals(rpcCalls, ["get_operations_manager_roster_v1"]);
  assertEquals(result, []);
});

Deno.test("assignment roster errors use stable authorization and internal contracts", async ()=>{
  for (const [databaseCode, status, responseCode] of [
    ["OPERATIONS_MANAGER_ROSTER_READER_REQUIRED", 403, "OPERATOR_NOT_AUTHORIZED"],
    ["OPERATOR_REVOKED", 403, "OPERATOR_NOT_AUTHORIZED"],
    ["UNEXPECTED_ROSTER_FAILURE", 500, "INTERNAL_ERROR"]
  ] as const) {
    const harness = dependencies({ executeApplicationAction: async ()=>{ throw new Error(databaseCode); } });
    const response = await handleCommercialOperator(request({
      action: "get_assignment_operator_roster"
    }), harness.deps);
    assertEquals(response.status, status);
    assertEquals((await response.json()).code, responseCode);
  }
});

Deno.test("personal dossier queue accepts only bounded cursor pagination without client authority", async ()=>{
  for (const [body, input] of [
    [{ action: "get_my_assigned_dossiers" }, { action: "get_my_assigned_dossiers", cursor: null, limit: 25 }],
    [{ action: "get_my_assigned_dossiers", cursor: "aabb", limit: 100 }, { action: "get_my_assigned_dossiers", cursor: "aabb", limit: 100 }],
  ] as const) {
    const harness = dependencies();
    const response = await handleCommercialOperator(request(body), harness.deps);
    assertEquals(response.status, 200);
    assertEquals(harness.calls, [{ jwt, input }]);
  }

  for (const invalid of [
    { operator_id: userId }, { assignee_operator_id: userId }, { auth_user_id: userId },
    { role: "operator" }, { status: "ACTIVE" }, { cursor: "" }, { cursor: 1 },
    { limit: 0 }, { limit: -1 }, { limit: 1.5 }, { limit: 101 }, { limit: null },
  ]) {
    const harness = dependencies();
    const response = await handleCommercialOperator(request({ action: "get_my_assigned_dossiers", ...invalid }), harness.deps);
    assertEquals(response.status, 400);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("personal dossier queue transport uses the exact caller-scoped RPC", async ()=>{
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const safeResult = { items: [{ reference: "LWS-AAN-2099-0001" }], has_more: false, next_cursor: null };
  const result = await executeOperatorPersonalQueueTransport({
    rpc: (name: string, args: Record<string, unknown>)=>{
      calls.push({ name, args });
      return Promise.resolve({ data: safeResult, error: null });
    }
  }, { action: "get_my_assigned_dossiers", cursor: "aabb", limit: 25 });
  assertEquals(calls, [{
    name: "get_operator_personal_dossier_queue_v1",
    args: { p_cursor: "aabb", p_limit: 25 }
  }]);
  assertEquals(result, safeResult);
});

Deno.test("personal dossier queue index dispatch constructs only a caller JWT client", async ()=>{
  const clientForCalls: string[] = [];
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const result = await executeCallerJwtOperatorPersonalQueueAction(
    jwt,
    { action: "get_my_assigned_dossiers", cursor: null, limit: 25 },
    (token: string)=>{
      clientForCalls.push(token);
      return {
        rpc: (name: string, args: Record<string, unknown>)=>{
          rpcCalls.push({ name, args });
          return Promise.resolve({ data: { items: [], has_more: false, next_cursor: null }, error: null });
        }
      };
    }
  );
  assertEquals(clientForCalls, [jwt]);
  assertEquals(rpcCalls, [{
    name: "get_operator_personal_dossier_queue_v1",
    args: { p_cursor: null, p_limit: 25 }
  }]);
  assertEquals(result, { items: [], has_more: false, next_cursor: null });
});

Deno.test("personal dossier queue rejects service role JWT before dispatch", async ()=>{
  const serviceJwt = createUnsignedTestJwt({ sub: userId, role: "service_role", exp: 4102444800 });
  const harness = dependencies();
  const response = await handleCommercialOperator(request({ action: "get_my_assigned_dossiers" }, serviceJwt), harness.deps);
  assertEquals(response.status, 401);
  assertEquals((await response.json()).code, "HUMAN_JWT_REQUIRED");
  assertEquals(harness.calls.length, 0);
});

Deno.test("personal dossier queue errors use stable public envelopes", async ()=>{
  for (const [databaseCode, status, responseCode] of [
    ["OPERATOR_PERSONAL_QUEUE_READER_REQUIRED", 403, "OPERATOR_NOT_AUTHORIZED"],
    ["OPERATOR_DISABLED", 403, "OPERATOR_NOT_AUTHORIZED"],
    ["INVALID_OPERATOR_PERSONAL_QUEUE_CURSOR", 400, "INVALID_REQUEST"],
    ["INVALID_OPERATOR_PERSONAL_QUEUE_LIMIT", 400, "INVALID_REQUEST"],
    ["UNEXPECTED_PERSONAL_QUEUE_FAILURE", 500, "INTERNAL_ERROR"],
  ] as const) {
    const harness = dependencies({ executeApplicationAction: async ()=>{ throw new Error(databaseCode); } });
    const response = await handleCommercialOperator(request({ action: "get_my_assigned_dossiers" }), harness.deps);
    assertEquals(response.status, status);
    assertEquals(await response.json(), { ok: false, code: responseCode });
  }
});

Deno.test("existing assignment Edge actions remain registered alongside personal queue", async ()=>{
  for (const body of [
    { action: "get_dossier_assignment", dossier_reference: "LWS-AAN-2099-0001" },
    { action: "get_assignment_operator_roster" },
    {
      action: "assign_dossier", dossier_reference: "LWS-AAN-2099-0001",
      assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
      expected_revision: 2, idempotency_key: "a1800000-0000-4000-8000-000000000051"
    },
  ]) {
    const response = await handleCommercialOperator(request(body), dependencies().deps);
    assertEquals(response.status, 200);
  }
});

Deno.test("dossier assignment mutation validates and normalizes the fixed command shape", async ()=>{
  for (const [reasonInput, normalizedReason] of [
    [undefined, null],
    [null, null],
    ["   ", null],
    ["  Capacity rebalance  ", "Capacity rebalance"]
  ]) {
    const harness = dependencies();
    const body: Record<string, unknown> = {
      action: "assign_dossier",
      dossier_reference: " f98b2f08 ",
      assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
      expected_revision: 2,
      idempotency_key: "a1800000-0000-4000-8000-000000000051"
    };
    if (reasonInput !== undefined) body.reason = reasonInput;
    const response = await handleCommercialOperator(request(body), harness.deps);
    assertEquals(response.status, 200);
    assertEquals(harness.calls, [{
      jwt,
      input: {
        action: "assign_dossier",
        dossier_reference: "#F98B2F08",
        assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
        expected_revision: 2,
        idempotency_key: "a1800000-0000-4000-8000-000000000051",
        reason: normalizedReason
      }
    }]);
  }

  for (const invalid of [
    { dossier_reference: undefined },
    { dossier_reference: "invalid" },
    { assignee_operator_id: "invalid" },
    { expected_revision: -1 },
    { expected_revision: 1.5 },
    { idempotency_key: "invalid" },
    { reason: 42 },
    { reason: "x".repeat(501) },
    { auth_user_id: userId },
    { role: "owner" },
    { capability: userId }
  ]) {
    const harness = dependencies();
    const response = await handleCommercialOperator(request({
      action: "assign_dossier",
      dossier_reference: "LWS-AAN-2099-0001",
      assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
      expected_revision: 2,
      idempotency_key: "a1800000-0000-4000-8000-000000000051",
      ...invalid
    }), harness.deps);
    assertEquals(response.status, 400);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("assignment transports call exact RPCs through the supplied human client", async ()=>{
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const readResult = {
    assignment_state: "ASSIGNED",
    assignee_operator_id: userId,
    assignee_display_name: "Assigned Operator",
    revision: 2,
    assigned_at: "2099-01-01T00:00:00Z"
  };
  const mutationResult = {
    assignment_state: "ASSIGNED",
    assignee_operator_id: userId,
    revision: 3,
    assigned_at: "2099-01-01T00:00:01Z",
    no_change: false,
    replayed: false
  };
  const client = {
    rpc: (name: string, args: Record<string, unknown>)=>{
      calls.push({ name, args });
      return Promise.resolve({
        data: name === "get_operator_dossier_assignment_v1" ? readResult : mutationResult,
        error: null
      });
    }
  };
  const actualReadResult = await executeDossierAssignmentReadTransport(client, {
    action: "get_dossier_assignment",
    dossier_reference: "#F98B2F08"
  });
  const actualMutationResult = await executeDossierAssignmentMutationTransport(client, {
    action: "assign_dossier",
    dossier_reference: "#F98B2F08",
    assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
    expected_revision: 2,
    idempotency_key: "a1800000-0000-4000-8000-000000000051",
    reason: null
  });
  assertEquals(calls, [
    {
      name: "get_operator_dossier_assignment_v1",
      args: { p_dossier_reference: "#F98B2F08" }
    },
    {
      name: "assign_operator_dossier_v1",
      args: {
        p_dossier_reference: "#F98B2F08",
        p_assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
        p_expected_revision: 2,
        p_idempotency_key: "a1800000-0000-4000-8000-000000000051",
        p_reason: null
      }
    }
  ]);
  assertEquals(actualReadResult, readResult);
  assertEquals(actualMutationResult, mutationResult);
});

Deno.test("index assignment dispatch constructs both RPC clients from the caller JWT", async ()=>{
  const clientForCalls: string[] = [];
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const clientFor = (token: string)=>{
    clientForCalls.push(token);
    return {
      rpc: (name: string, args: Record<string, unknown>)=>{
        rpcCalls.push({ name, args });
        return Promise.resolve({ data: { assignment_state: "ASSIGNED" }, error: null });
      }
    };
  };

  await executeCallerJwtDossierAssignmentAction(jwt, {
    action: "get_dossier_assignment",
    dossier_reference: "#F98B2F08"
  }, clientFor);
  await executeCallerJwtDossierAssignmentAction(jwt, {
    action: "assign_dossier",
    dossier_reference: "#F98B2F08",
    assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
    expected_revision: 2,
    idempotency_key: "a1800000-0000-4000-8000-000000000051",
    reason: null
  }, clientFor);

  assertEquals(clientForCalls, [jwt, jwt]);
  assertEquals(rpcCalls.map(({ name })=>name), [
    "get_operator_dossier_assignment_v1",
    "assign_operator_dossier_v1"
  ]);
});

Deno.test("assignment success variants pass through without synthetic state", async ()=>{
  for (const result of [
    { assignment_state: "ASSIGNED", assignee_operator_id: userId, revision: 1, assigned_at: "2099-01-01T00:00:00Z", no_change: false, replayed: false },
    { assignment_state: "ASSIGNED", assignee_operator_id: userId, revision: 1, assigned_at: "2099-01-01T00:00:00Z", no_change: true, replayed: false },
    { assignment_state: "ASSIGNED", assignee_operator_id: userId, revision: 1, assigned_at: "2099-01-01T00:00:00Z", no_change: false, replayed: true }
  ]) {
    const harness = dependencies({ executeApplicationAction: async ()=>result });
    const response = await handleCommercialOperator(request({
      action: "assign_dossier",
      dossier_reference: "LWS-AAN-2099-0001",
      assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
      expected_revision: 0,
      idempotency_key: "a1800000-0000-4000-8000-000000000051"
    }), harness.deps);
    assertEquals(response.status, 200);
    assertEquals((await response.json()).result, result);
  }
});

Deno.test("assignment database errors expose stable transport contracts", async ()=>{
  for (const [databaseCode, status, responseCode] of [
    ["DOSSIER_ASSIGNMENT_ACTOR_REQUIRED", 403, "OPERATOR_NOT_AUTHORIZED"],
    ["DOSSIER_ASSIGNMENT_READER_REQUIRED", 403, "OPERATOR_NOT_AUTHORIZED"],
    ["DOSSIER_NOT_FOUND", 404, "DOSSIER_NOT_FOUND"],
    ["AMBIGUOUS_DOSSIER_REFERENCE", 409, "AMBIGUOUS_DOSSIER_REFERENCE"],
    ["ASSIGNEE_OPERATOR_NOT_FOUND", 404, "ASSIGNEE_OPERATOR_NOT_FOUND"],
    ["ASSIGNEE_NOT_ELIGIBLE", 409, "ASSIGNEE_NOT_ELIGIBLE"],
    ["OPERATOR_DOSSIER_ASSIGNMENT_STATE_REQUIRED", 409, "COMMAND_REJECTED"],
    ["CONCURRENT_MODIFICATION", 409, "CONCURRENT_MODIFICATION"],
    ["IDEMPOTENCY_CONFLICT", 409, "IDEMPOTENCY_CONFLICT"],
    ["INVALID_DOSSIER_REFERENCE", 400, "INVALID_REQUEST"],
    ["INVALID_DOSSIER_ASSIGNMENT_COMMAND", 400, "INVALID_REQUEST"],
    ["REASSIGNMENT_REASON_REQUIRED", 400, "INVALID_REQUEST"],
    ["UNEXPECTED_ASSIGNMENT_FAILURE", 500, "INTERNAL_ERROR"]
  ] as const) {
    const harness = dependencies({ executeApplicationAction: async ()=>{ throw new Error(databaseCode); } });
    const response = await handleCommercialOperator(request({
      action: "assign_dossier",
      dossier_reference: "LWS-AAN-2099-0001",
      assignee_operator_id: "a1800000-0000-4000-8000-000000000050",
      expected_revision: 0,
      idempotency_key: "a1800000-0000-4000-8000-000000000051"
    }), harness.deps);
    assertEquals(response.status, status);
    assertEquals((await response.json()).code, responseCode);
  }
});

Deno.test("project dossier accepts only one server-authorized project UUID", async ()=>{
  const harness = dependencies();
  const response = await handleCommercialOperator(request({ action: "get_project_dossier", project_id: userId }), harness.deps);
  assertEquals(response.status, 200);
  assertEquals(harness.calls[0], { jwt, input: { action: "get_project_dossier", project_id: userId } });
  const invalid = await handleCommercialOperator(request({ action: "get_project_dossier", project_id: "not-a-project" }), harness.deps);
  assertEquals(invalid.status, 400);
  assertEquals(harness.calls.length, 1);
});

Deno.test("project site actions use a fixed validated command shape", async ()=>{
  for (const [action, operation, expectedRevision] of [
    ["bind_project_site", "INITIAL_BIND", 0],
    ["rotate_project_site", "ROTATION", 1]
  ]) {
    const harness = dependencies();
    const response = await handleCommercialOperator(request({
      action,
      project_id: userId,
      expected_revision: expectedRevision,
      idempotency_key: "a1800000-0000-4000-8000-000000000009",
      canonical_domain: "project.example",
      evidence: "Approved operator site command"
    }), harness.deps);
    assertEquals(response.status, 200);
    assertEquals(harness.calls[0].input, {
      action,
      project_id: userId,
      operation,
      expected_revision: expectedRevision,
      idempotency_key: "a1800000-0000-4000-8000-000000000009",
      canonical_domain: "project.example",
      evidence: "Approved operator site command"
    });
  }

  for (const invalid of [
    { canonical_domain: "https://project.example" },
    { canonical_domain: "Project.example" },
    { canonical_domain: "project.example/path" },
    { evidence: "" },
    { expected_revision: -1 }
  ]) {
    const harness = dependencies();
    const response = await handleCommercialOperator(request({
      action: "rotate_project_site",
      project_id: userId,
      expected_revision: 1,
      idempotency_key: "a1800000-0000-4000-8000-000000000009",
      canonical_domain: "project.example",
      evidence: "Approved operator site command",
      ...invalid
    }), harness.deps);
    assertEquals(response.status, 400);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("promotion requires server-shaped locator and idempotency UUID", async ()=>{
  const harness = dependencies();
  const invalid = await handleCommercialOperator(request({ action: "promote_accepted_application", quote_request_id: userId, idempotency_key: "bad" }), harness.deps);
  assertEquals(invalid.status, 400);
  const valid = await handleCommercialOperator(request({ action: "promote_accepted_application", quote_request_id: userId, idempotency_key: "a1800000-0000-4000-8000-000000000001" }), harness.deps);
  assertEquals(valid.status, 200);
  assertEquals(harness.calls.length, 1);
});

Deno.test("service role JWT cannot enter application actions", async ()=>{
  const serviceJwt = createUnsignedTestJwt({ sub: userId, role: "service_role", exp: 4102444800 });
  for (const action of ["list_applications", "get_assignment_operator_roster"]) {
    const harness = dependencies();
    const response = await handleCommercialOperator(request({ action }, serviceJwt), harness.deps);
    assertEquals(response.status, 401);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("intake lifecycle actions require the fixed revisioned command shape", async ()=>{
  for (const [action, eventType] of [
    ["interrupt_intake", "INTERRUPTED"],
    ["resume_intake", "RESUMED"],
    ["cancel_intake", "CANCELLED"],
    ["reactivate_intake", "REACTIVATED"]
  ]) {
    const harness = dependencies();
    const response = await handleCommercialOperator(request({
      action,
      intake_id: "a1800000-0000-4000-8000-000000000030",
      expected_revision: 2,
      idempotency_key: "a1800000-0000-4000-8000-000000000031",
      reason: "  Operator lifecycle reason  "
    }), harness.deps);
    assertEquals(response.status, 200);
    assertEquals(harness.calls[0].input, {
      action,
      intake_id: "a1800000-0000-4000-8000-000000000030",
      event_type: eventType,
      expected_revision: 2,
      idempotency_key: "a1800000-0000-4000-8000-000000000031",
      reason: "Operator lifecycle reason"
    });
  }

  for (const invalid of [
    { expected_revision: -1 },
    { idempotency_key: "invalid" },
    { reason: "" },
    { reason: "x".repeat(501) },
    { access_token: "forbidden" }
  ]) {
    const harness = dependencies();
    const response = await handleCommercialOperator(request({
      action: "interrupt_intake",
      intake_id: "a1800000-0000-4000-8000-000000000030",
      expected_revision: 2,
      idempotency_key: "a1800000-0000-4000-8000-000000000031",
      reason: "Reason",
      ...invalid
    }), harness.deps);
    assertEquals(response.status, 400);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("intake lifecycle database errors retain existing HTTP contracts", async ()=>{
  for (const [databaseCode, status, responseCode] of [
    ["CONCURRENT_MODIFICATION", 409, "CONCURRENT_MODIFICATION"],
    ["INVALID_INTAKE_LIFECYCLE_TRANSITION", 409, "COMMAND_REJECTED"],
    ["IDEMPOTENCY_CONFLICT", 409, "IDEMPOTENCY_CONFLICT"],
    ["INTAKE_NOT_FOUND", 404, "INTAKE_NOT_FOUND"],
    ["OPERATOR_REVOKED", 403, "OPERATOR_NOT_AUTHORIZED"]
  ] as const) {
    const harness = dependencies();
    harness.deps.executeApplicationAction = async ()=>{
      throw new Error(databaseCode);
    };
    const result = await handleCommercialOperator(request({
      action: "interrupt_intake",
      intake_id: "a1800000-0000-4000-8000-000000000030",
      expected_revision: 2,
      idempotency_key: "a1800000-0000-4000-8000-000000000031",
      reason: "Reason"
    }), harness.deps);
    assertEquals(result.status, status);
    assertEquals((await result.json()).code, responseCode);
  }
});

Deno.test("dossier lifecycle actions require the fixed revisioned command shape", async ()=>{
  for (const [action, eventType] of [
    ["archive_dossier", "ARCHIVED"],
    ["reactivate_dossier", "REACTIVATED"],
    ["trash_dossier", "TRASHED"],
    ["restore_dossier", "RESTORED"]
  ]) {
    const harness = dependencies();
    const response = await handleCommercialOperator(request({
      action,
      quote_request_id: "a1800000-0000-4000-8000-000000000040",
      expected_revision: 3,
      idempotency_key: "a1800000-0000-4000-8000-000000000041",
      reason: "  Operator dossier reason  "
    }), harness.deps);
    assertEquals(response.status, 200);
    assertEquals(harness.calls[0].input, {
      action,
      quote_request_id: "a1800000-0000-4000-8000-000000000040",
      event_type: eventType,
      expected_revision: 3,
      idempotency_key: "a1800000-0000-4000-8000-000000000041",
      reason: "Operator dossier reason"
    });
  }

  for (const invalid of [
    { quote_request_id: "invalid" },
    { expected_revision: -1 },
    { idempotency_key: "invalid" },
    { reason: "" },
    { reason: "x".repeat(501) },
    { event_type: "TRASHED" },
    { actor_operator_id: userId },
    { deletion_eligible_at: "2099-01-01T00:00:00Z" }
  ]) {
    const harness = dependencies();
    const response = await handleCommercialOperator(request({
      action: "trash_dossier",
      quote_request_id: "a1800000-0000-4000-8000-000000000040",
      expected_revision: 3,
      idempotency_key: "a1800000-0000-4000-8000-000000000041",
      reason: "Reason",
      ...invalid
    }), harness.deps);
    assertEquals(response.status, 400);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("dossier lifecycle database errors expose only stable public contracts", async ()=>{
  for (const [databaseCode, status, responseCode] of [
    ["DOSSIER_NOT_FOUND", 404, "DOSSIER_NOT_FOUND"],
    ["CONCURRENT_MODIFICATION", 409, "CONCURRENT_MODIFICATION"],
    ["IDEMPOTENCY_CONFLICT", 409, "IDEMPOTENCY_CONFLICT"],
    ["INVALID_OPERATOR_DOSSIER_TRANSITION", 409, "COMMAND_REJECTED"],
    ["LEGACY_TEST_CLEANUP_AUTHORITY_REQUIRED", 409, "COMMAND_REJECTED"],
    ["LEGACY_TEST_CLEANUP_IDENTITY_MISMATCH", 409, "COMMAND_REJECTED"],
    ["LEGACY_TEST_CLEANUP_QUOTATION_BLOCKER_PRESENT", 409, "COMMAND_REJECTED"],
    ["LEGACY_TEST_CLEANUP_COMMERCIAL_BLOCKER_PRESENT", 409, "COMMAND_REJECTED"],
    ["LEGACY_TEST_CLEANUP_PAYMENT_BLOCKER_PRESENT", 409, "COMMAND_REJECTED"],
    ["LEGACY_TEST_CLEANUP_SDF_BLOCKER_PRESENT", 409, "COMMAND_REJECTED"],
    ["TRASHED_DOSSIER_BLOCKER_CREATION_DENIED", 409, "COMMAND_REJECTED"],
    ["EDGE_DOSSIER_CAPABILITY_REQUIRED", 403, "OPERATOR_NOT_AUTHORIZED"]
  ] as const) {
    const harness = dependencies();
    harness.deps.executeApplicationAction = async ()=>{
      throw new Error(databaseCode);
    };
    const result = await handleCommercialOperator(request({
      action: "trash_dossier",
      quote_request_id: "a1800000-0000-4000-8000-000000000040",
      expected_revision: 3,
      idempotency_key: "a1800000-0000-4000-8000-000000000041",
      reason: "Reason"
    }), harness.deps);
    assertEquals(result.status, status);
    assertEquals((await result.json()).code, responseCode);
  }
});

Deno.test("dossier lifecycle transport issues server capability before JWT-bound command", async ()=>{
  const calls: Array<{ client: string; name: string; args: Record<string, unknown> }> = [];
  const capability = "a1800000-0000-4000-8000-000000000042";
  const input = {
    action: "trash_dossier",
    quote_request_id: "a1800000-0000-4000-8000-000000000040",
    event_type: "TRASHED",
    expected_revision: 3,
    idempotency_key: "a1800000-0000-4000-8000-000000000041",
    reason: "Operator dossier reason"
  };
  const issueCapability = (args: Record<string, unknown>)=>{
    calls.push({ client: "service", name: "issue_operator_dossier_lifecycle_edge_capability_v1", args });
    return Promise.resolve({ data: capability, error: null });
  };
  const executeCommand = (args: Record<string, unknown>)=>{
    calls.push({ client: "human", name: "execute_operator_dossier_lifecycle_command_v1", args });
    return Promise.resolve({ data: { state: "TRASHED", revision: 4 }, error: null });
  };

  assertEquals(
    await executeDossierLifecycleTransport(issueCapability, executeCommand, userId, input),
    { state: "TRASHED", revision: 4 }
  );
  assertEquals(calls, [
    {
      client: "service",
      name: "issue_operator_dossier_lifecycle_edge_capability_v1",
      args: {
        p_actor_auth_user_id: userId,
        p_quote_request_id: input.quote_request_id,
        p_event_type: input.event_type,
        p_expected_revision: input.expected_revision,
        p_idempotency_key: input.idempotency_key,
        p_reason: input.reason
      }
    },
    {
      client: "human",
      name: "execute_operator_dossier_lifecycle_command_v1",
      args: {
        p_quote_request_id: input.quote_request_id,
        p_event_type: input.event_type,
        p_expected_revision: input.expected_revision,
        p_idempotency_key: input.idempotency_key,
        p_reason: input.reason,
        p_edge_capability: capability
      }
    }
  ]);
});

Deno.test("existing commercial command path remains rate limited and unchanged", async ()=>{
  const harness = dependencies();
  let rateLimitCalls = 0;
  harness.deps.consumeRateLimit = async ()=>{
    rateLimitCalls += 1;
    return { allowed: true, retry_after_seconds: 0 };
  };
  const response = await handleCommercialOperator(request({
    project_id: userId,
    command_type: "archive_project",
    expected_state: "DELIVERED",
    expected_revision: 2,
    idempotency_key: "a1800000-0000-4000-8000-000000000001",
    payload: {}
  }), harness.deps);
  assertEquals(response.status, 200);
  assertEquals(rateLimitCalls, 1);
  assertEquals(harness.calls.length, 0);
});

Deno.test("internal E2E creation accepts only the fixed owner-command shape", async ()=>{
  const harness = dependencies();
  const valid = await handleCommercialOperator(request({
    action: "create_internal_e2e_run",
    idempotency_key: "a1800000-0000-4000-8000-000000000010",
    run_label: "production smoke",
    ttl_minutes: 30
  }), harness.deps);
  assertEquals(valid.status, 200);
  assertEquals(harness.calls[0].input, {
    action: "create_internal_e2e_run",
    idempotency_key: "a1800000-0000-4000-8000-000000000010",
    run_label: "production smoke",
    ttl_minutes: 30
  });
  for (const forbidden of [
    { classification: "internal_e2e" },
    { email: "attacker@example.test" },
    { mailbox: "attacker@example.test" }
  ]) {
    const blocked = await handleCommercialOperator(request({
      action: "create_internal_e2e_run",
      idempotency_key: "a1800000-0000-4000-8000-000000000011",
      run_label: "blocked",
      ttl_minutes: 30,
      ...forbidden
    }), harness.deps);
    assertEquals(blocked.status, 400);
  }
  assertEquals(harness.calls.length, 1);
});

Deno.test("Customer Request smoke fixture accepts only an idempotency key", async ()=>{
  const harness = dependencies();
  const valid = await handleCommercialOperator(request({
    action: "create_customer_request_smoke_fixture",
    idempotency_key: "a1800000-0000-4000-8000-000000000030",
  }), harness.deps);
  assertEquals(valid.status, 200);
  assertEquals(harness.calls[0].input, {
    action: "create_customer_request_smoke_fixture",
    idempotency_key: "a1800000-0000-4000-8000-000000000030",
  });
  for (const forbidden of [
    { run_label: "caller controlled" },
    { customer_id: userId },
    { project_id: userId },
    { quote_request_id: userId },
    { name: "Real Person" },
    { email: "real@example.com" },
    { record_classification: "production" },
    { request_reference: "LWS-VRZ-2099-9999" },
  ]) {
    const blocked = await handleCommercialOperator(request({
      action: "create_customer_request_smoke_fixture",
      idempotency_key: "a1800000-0000-4000-8000-000000000031",
      ...forbidden,
    }), harness.deps);
    assertEquals(blocked.status, 400);
  }
  assertEquals(harness.calls.length, 1);
});

Deno.test("Customer Request smoke fixture uses one atomic caller-JWT RPC", async ()=>{
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const result = await executeCallerJwtCustomerRequestSmokeFixtureAction(
    jwt,
    "a1800000-0000-4000-8000-000000000030",
    (token: string)=>({
      rpc: async (name: string, args: Record<string, unknown>)=>{
        assertEquals(token, jwt);
        calls.push({ name, args });
        return { data: { run_id: userId, request_id: "a1800000-0000-4000-8000-000000000031" }, error: null };
      },
    }),
  );
  assertEquals(calls, [{
    name: "create_customer_request_smoke_fixture_v1",
    args: { p_idempotency_key: "a1800000-0000-4000-8000-000000000030" },
  }]);
  assertEquals(result, { run_id: userId, request_id: "a1800000-0000-4000-8000-000000000031" });
});

Deno.test("internal E2E finalization requires a terminal state and revision", async ()=>{
  const harness = dependencies();
  const valid = await handleCommercialOperator(request({
    action: "finalize_internal_e2e_run",
    run_id: "a1800000-0000-4000-8000-000000000020",
    terminal_status: "PASSED",
    expected_revision: 0,
    idempotency_key: "a1800000-0000-4000-8000-000000000021"
  }), harness.deps);
  assertEquals(valid.status, 200);
  const active = await handleCommercialOperator(request({
    action: "finalize_internal_e2e_run",
    run_id: "a1800000-0000-4000-8000-000000000020",
    terminal_status: "ACTIVE",
    expected_revision: 0,
    idempotency_key: "a1800000-0000-4000-8000-000000000022"
  }), harness.deps);
  assertEquals(active.status, 400);
  assertEquals(harness.calls.length, 1);
});

Deno.test("v2 list preserves preflight verify core sign order and hides raw position", async ()=>{
  const harness = dependencies();
  const signed = await signOperatorCursor({
    dossierDate: "2099-01-03T10:20:30+00:00",
    quoteRequestId: userId,
  }, cursorRequest(v2Input), { now: 4_102_444_800_000, secret: cursorSecret });
  const response = await handleCommercialOperator(request({ ...v2Input, cursor: signed }), harness.deps);
  assertEquals(response.status, 200);
  assertEquals(harness.events, ["preflight", "verify", "core", "sign"]);
  const body = await response.json();
  assertEquals(Array.isArray(body.result.items), true);
  assertEquals(typeof body.result.next_cursor, "string");
  assertEquals("next_position" in body.result, false);
});

Deno.test("v2 list rejects forged position, changed search/filter, expired, and malformed cursors before core", async ()=>{
  const signed = await signOperatorCursor({
    dossierDate: "2099-01-03T10:20:30+00:00",
    quoteRequestId: userId,
  }, cursorRequest(v2Input), { now: 4_102_444_800_000, secret: cursorSecret });
  const parts = signed.split(".");
  const payloadPart = parts[1].replace(/-/g, "+").replace(/_/g, "/");
  const payload = JSON.parse(atob(payloadPart.padEnd(Math.ceil(payloadPart.length / 4) * 4, "=")));
  payload.dossierDate = "2999-01-01T00:00:00+00:00";
  payload.quoteRequestId = "ffffffff-ffff-4fff-8fff-ffffffffffff";
  const binary = JSON.stringify(payload);
  const forged = `v1.${btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "")}.${parts[2]}`;
  for (const input of [
    { ...v2Input, cursor: forged },
    { ...v2Input, search: "Changed", cursor: signed },
    { ...v2Input, zone: "ACTIVE", cursor: signed },
    { ...v2Input, cursor: "malformed" },
  ]) {
    const harness = dependencies();
    const response = await handleCommercialOperator(request(input), harness.deps);
    assertEquals(response.status, 400);
    assertEquals(harness.events.includes("core"), false);
  }
  const expiredHarness = dependencies({
    verifyOperatorCursor: async (cursor: string, input: Record<string, unknown>)=>
      await verifyOperatorCursor(cursor, cursorRequest(input), {
        now: 4_102_444_800_000 + OPERATOR_CURSOR_TTL_MS,
        secret: cursorSecret,
      })
  });
  assertEquals((await handleCommercialOperator(request({ ...v2Input, cursor: signed }), expiredHarness.deps)).status, 400);
});

Deno.test("v2 facets uses preflight and actor-bound core without cursor signing", async ()=>{
  const harness = dependencies();
  const response = await handleCommercialOperator(request({
    action: "get_application_facets_v2",
    zone: "ACTIVE_ARCHIVED",
    operational_status: null,
    request_kind: null,
    search: null,
  }), harness.deps);
  assertEquals(response.status, 200);
  assertEquals(harness.events, ["preflight", "facets"]);
});

Deno.test("v2 list fails closed for unauthorized actor, missing secret, and invalid DB core response", async ()=>{
  const unauthorized = dependencies({ authorizeApplicationReader: async ()=>{ throw new Error("APPLICATION_SCOPE_DENIED"); } });
  assertEquals((await handleCommercialOperator(request(v2Input), unauthorized.deps)).status, 403);

  const missingSecret = dependencies({
    signOperatorCursor: async (position: Record<string, string>, input: Record<string, unknown>)=>
      await signOperatorCursor({ dossierDate: position.dossier_date, quoteRequestId: position.quote_request_id }, cursorRequest(input), { secret: "short" })
  });
  assertEquals((await handleCommercialOperator(request(v2Input), missingSecret.deps)).status, 500);

  const invalidCore = dependencies({ executeApplicationListV2: async ()=>({ items: [], has_more: true, next_position: null }) });
  assertEquals((await handleCommercialOperator(request(v2Input), invalidCore.deps)).status, 500);
});

Deno.test("Customer Requests actions accept only bounded operational input", async ()=>{
  const requestId = "a1800000-0000-4000-8000-000000000070";
  const idempotencyKey = "a1800000-0000-4000-8000-000000000071";
  for (const [body, input] of [
    [
      { action: "list_customer_requests_for_dossier", dossier_reference: " lws-aan-2099-0001 " },
      { action: "list_customer_requests_for_dossier", dossier_reference: "LWS-AAN-2099-0001", cursor: null, limit: 25 },
    ],
    [
      { action: "get_customer_request", request_id: requestId },
      { action: "get_customer_request", request_id: requestId },
    ],
    [
      { action: "transition_customer_request", request_id: requestId, command_type: "START", expected_revision: 2, idempotency_key: idempotencyKey },
      { action: "transition_customer_request", request_id: requestId, command_type: "START", expected_revision: 2, idempotency_key: idempotencyKey },
    ],
  ] as const) {
    const harness = dependencies();
    const response = await handleCommercialOperator(request(body), harness.deps);
    assertEquals(response.status, 200);
    assertEquals(harness.calls, [{ jwt, input }]);
  }

  for (const invalid of [
    { action: "list_customer_requests_for_dossier", dossier_reference: "LWS-AAN-2099-0001", quote_request_id: requestId },
    { action: "list_customer_requests_for_dossier", dossier_reference: "LWS-AAN-2099-0001", customer_id: requestId },
    { action: "list_customer_requests_for_dossier", dossier_reference: "LWS-AAN-2099-0001", role: "operator" },
    { action: "list_customer_requests_for_dossier", dossier_reference: "invalid" },
    { action: "list_customer_requests_for_dossier", dossier_reference: "LWS-AAN-2099-0001", cursor: "" },
    { action: "list_customer_requests_for_dossier", dossier_reference: "LWS-AAN-2099-0001", limit: 101 },
    { action: "get_customer_request", request_id: "invalid" },
    { action: "get_customer_request", request_id: requestId, project_id: requestId },
    { action: "transition_customer_request", request_id: requestId, command_type: "TRIAGE", expected_revision: 2, idempotency_key: idempotencyKey },
    { action: "transition_customer_request", request_id: requestId, command_type: "START", expected_revision: -1, idempotency_key: idempotencyKey },
    { action: "transition_customer_request", request_id: requestId, command_type: "START", expected_revision: 2, idempotency_key: idempotencyKey, payload: {} },
  ]) {
    const harness = dependencies();
    const response = await handleCommercialOperator(request(invalid), harness.deps);
    assertEquals(response.status, 400);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("Customer Requests transport uses exact caller-scoped RPCs", async ()=>{
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const client = {
    rpc: (name: string, args: Record<string, unknown>)=>{
      calls.push({ name, args });
      return Promise.resolve({ data: { ok: true }, error: null });
    }
  };
  await executeCustomerRequestTransport(client, {
    action: "list_customer_requests_for_dossier", dossier_reference: "LWS-AAN-2099-0001", cursor: "aabb", limit: 25,
  });
  await executeCustomerRequestTransport(client, {
    action: "get_customer_request", request_id: "a1800000-0000-4000-8000-000000000070",
  });
  await executeCustomerRequestTransport(client, {
    action: "transition_customer_request", request_id: "a1800000-0000-4000-8000-000000000070",
    command_type: "RESUME", expected_revision: 4, idempotency_key: "a1800000-0000-4000-8000-000000000071",
  });
  assertEquals(calls, [
    { name: "get_customer_requests_for_dossier_v1", args: { p_dossier_reference: "LWS-AAN-2099-0001", p_cursor: "aabb", p_limit: 25 } },
    { name: "get_customer_request_v1", args: { p_request_id: "a1800000-0000-4000-8000-000000000070" } },
    {
      name: "transition_customer_request_v1",
      args: {
        p_request_id: "a1800000-0000-4000-8000-000000000070", p_command_type: "RESUME",
        p_expected_revision: 4, p_idempotency_key: "a1800000-0000-4000-8000-000000000071", p_payload: {},
      },
    },
  ]);
});

Deno.test("Customer Requests index dispatch constructs only a caller JWT client", async ()=>{
  const clientForCalls: string[] = [];
  const rpcCalls: string[] = [];
  const result = await executeCallerJwtCustomerRequestAction(jwt, {
    action: "get_customer_request", request_id: "a1800000-0000-4000-8000-000000000070",
  }, (token: string)=>{
    clientForCalls.push(token);
    return {
      rpc: (name: string)=>{
        rpcCalls.push(name);
        return Promise.resolve({ data: { request_id: "a1800000-0000-4000-8000-000000000070" }, error: null });
      },
    };
  });
  assertEquals(clientForCalls, [jwt]);
  assertEquals(rpcCalls, ["get_customer_request_v1"]);
  assertEquals(result, { request_id: "a1800000-0000-4000-8000-000000000070" });
});

Deno.test("Customer Request upload-link actions accept only authority-minimal input", async ()=>{
  const requestId = "a1800000-0000-4000-8000-000000000070";
  const uploadRequestId = "a1800000-0000-4000-8000-000000000072";
  const idempotencyKey = "a1800000-0000-4000-8000-000000000071";
  for (const [body, input] of [
    [
      { action: "create_customer_request_upload_link", request_id: requestId, idempotency_key: idempotencyKey },
      { action: "create_customer_request_upload_link", request_id: requestId, idempotency_key: idempotencyKey },
    ],
    [
      { action: "revoke_customer_request_upload_link", upload_request_id: uploadRequestId, reason: " Klant vroeg intrekking ", idempotency_key: idempotencyKey },
      { action: "revoke_customer_request_upload_link", upload_request_id: uploadRequestId, reason: "Klant vroeg intrekking", idempotency_key: idempotencyKey },
    ],
  ] as const) {
    const harness = dependencies();
    assertEquals((await handleCommercialOperator(request(body), harness.deps)).status, 200);
    assertEquals(harness.calls, [{ jwt, input }]);
  }
  for (const invalid of [
    { action: "create_customer_request_upload_link", request_id: requestId, idempotency_key: idempotencyKey, customer_id: requestId },
    { action: "create_customer_request_upload_link", request_id: "invalid", idempotency_key: idempotencyKey },
    { action: "revoke_customer_request_upload_link", upload_request_id: uploadRequestId, reason: "", idempotency_key: idempotencyKey },
    { action: "revoke_customer_request_upload_link", upload_request_id: uploadRequestId, request_id: requestId, reason: "x", idempotency_key: idempotencyKey },
  ]) {
    const harness = dependencies();
    assertEquals((await handleCommercialOperator(request(invalid), harness.deps)).status, 400);
    assertEquals(harness.calls.length, 0);
  }
});

Deno.test("Customer Request upload-link create is digest-only and retry-stable", async ()=>{
  Deno.env.set("CUSTOMER_REQUEST_UPLOAD_CAPABILITY_SECRET", "u".repeat(32));
  Deno.env.set("SITE_URL", "https://lorenzowebsolutions.be");
  const requestId = "a1800000-0000-4000-8000-000000000070";
  const idempotencyKey = "a1800000-0000-4000-8000-000000000071";
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const clientFor = (token: string)=>({ rpc: async (name: string, args: Record<string, unknown>)=>{
    assertEquals(token, jwt);
    calls.push({ name, args });
    return { data: { state: "ACTIVE", upload_request_id: "a1800000-0000-4000-8000-000000000072", expires_at: "2099-01-01T00:00:00Z" }, error: null };
  } });
  const input = { action: "create_customer_request_upload_link" as const, request_id: requestId, idempotency_key: idempotencyKey };
  const first = await executeCallerJwtCustomerRequestUploadAction(jwt, input, clientFor);
  const second = await executeCallerJwtCustomerRequestUploadAction(jwt, input, clientFor);
  assertEquals(first, second);
  assertEquals(calls.map((call)=>call.name), ["create_customer_request_upload_request_v1", "create_customer_request_upload_request_v1"]);
  assertEquals(calls[0].args.p_token_digest, calls[1].args.p_token_digest);
  assertEquals(typeof calls[0].args.p_token_digest, "string");
  assertEquals(JSON.stringify(calls).includes(new URL((first as Record<string, string>).upload_url).hash.slice(7)), false);
});

Deno.test("Customer Request upload-link revoke uses only caller JWT and capability id", async ()=>{
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const result = await executeCallerJwtCustomerRequestUploadAction(jwt, {
    action: "revoke_customer_request_upload_link",
    upload_request_id: "a1800000-0000-4000-8000-000000000072",
    reason: "Klant vroeg intrekking",
    idempotency_key: "a1800000-0000-4000-8000-000000000071",
  }, (token: string)=>({ rpc: async (name: string, args: Record<string, unknown>)=>{
    assertEquals(token, jwt); calls.push({ name, args }); return { data: { state: "REVOKED" }, error: null };
  } }));
  assertEquals(result, { state: "REVOKED" });
  assertEquals(calls, [{ name: "revoke_customer_request_upload_request_v1", args: {
    p_upload_request_id: "a1800000-0000-4000-8000-000000000072",
    p_reason: "Klant vroeg intrekking",
    p_idempotency_key: "a1800000-0000-4000-8000-000000000071",
  } }]);
});

Deno.test("Customer Requests reject service role and expose stable error envelopes", async ()=>{
  const serviceJwt = createUnsignedTestJwt({ sub: userId, role: "service_role", exp: 4102444800 });
  const serviceHarness = dependencies();
  const serviceResponse = await handleCommercialOperator(request({
    action: "get_customer_request", request_id: "a1800000-0000-4000-8000-000000000070",
  }, serviceJwt), serviceHarness.deps);
  assertEquals(serviceResponse.status, 401);
  assertEquals((await serviceResponse.json()).code, "HUMAN_JWT_REQUIRED");
  assertEquals(serviceHarness.calls.length, 0);

  for (const [databaseCode, status, responseCode] of [
    ["CUSTOMER_REQUEST_ACCESS_DENIED", 403, "OPERATOR_NOT_AUTHORIZED"],
    ["INVALID_CUSTOMER_REQUEST_LIST_CURSOR", 400, "INVALID_REQUEST"],
    ["CONCURRENT_MODIFICATION", 409, "CONCURRENT_MODIFICATION"],
    ["INVALID_CUSTOMER_REQUEST_TRANSITION", 409, "COMMAND_REJECTED"],
    ["UNEXPECTED_CUSTOMER_REQUEST_FAILURE", 500, "INTERNAL_ERROR"],
  ] as const) {
    const harness = dependencies({ executeApplicationAction: async ()=>{ throw new Error(databaseCode); } });
    const response = await handleCommercialOperator(request({
      action: "get_customer_request", request_id: "a1800000-0000-4000-8000-000000000070",
    }), harness.deps);
    assertEquals(response.status, status);
    assertEquals((await response.json()).code, responseCode);
  }
});

Deno.test("current operator identity accepts only the fixed presentation action", async ()=>{
  const harness = dependencies();
  const response = await handleCommercialOperator(request({ action: "get_current_operator_identity" }), harness.deps);
  assertEquals(response.status, 200);
  assertEquals(harness.calls, [{ jwt, input: { action: "get_current_operator_identity" } }]);

  for (const extra of [{ operator_id: userId }, { role: "owner" }, { status: "ACTIVE" }, { email: "private@example.test" }]) {
    const invalidHarness = dependencies();
    const invalidResponse = await handleCommercialOperator(request({ action: "get_current_operator_identity", ...extra }), invalidHarness.deps);
    assertEquals(invalidResponse.status, 400);
    assertEquals(invalidHarness.calls.length, 0);
  }
});

Deno.test("current operator identity transport exposes only the safe projection", async ()=>{
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const result = await executeCurrentOperatorIdentityTransport({
    rpc: (name: string, args: Record<string, unknown>)=>{
      calls.push({ name, args });
      return Promise.resolve({ data: { display_name: "Current Operator", role: "operator", status: "ACTIVE" }, error: null });
    }
  });
  assertEquals(calls, [{ name: "get_current_operator_identity_v1", args: {} }]);
  assertEquals(result, { display_name: "Current Operator", role: "operator", status: "ACTIVE" });
  assertEquals(Object.keys(result), ["display_name", "role", "status"]);
});

Deno.test("current operator identity index dispatch constructs only a caller JWT client", async ()=>{
  const clientForCalls: string[] = [];
  const rpcCalls: string[] = [];
  const result = await executeCallerJwtCurrentOperatorIdentityAction(jwt, (token: string)=>{
    clientForCalls.push(token);
    return {
      rpc: (name: string)=>{
        rpcCalls.push(name);
        return Promise.resolve({ data: { display_name: "Owner", role: "owner", status: "ACTIVE" }, error: null });
      }
    };
  });
  assertEquals(clientForCalls, [jwt]);
  assertEquals(rpcCalls, ["get_current_operator_identity_v1"]);
  assertEquals(result, { display_name: "Owner", role: "owner", status: "ACTIVE" });
});

Deno.test("current operator identity errors use stable authorization envelopes", async ()=>{
  for (const databaseCode of ["UNKNOWN_OPERATOR", "OPERATOR_DISABLED", "OPERATOR_REVOKED", "OPERATOR_INACTIVE"]) {
    const harness = dependencies({ executeApplicationAction: async ()=>{ throw new Error(databaseCode); } });
    const response = await handleCommercialOperator(request({ action: "get_current_operator_identity" }), harness.deps);
    assertEquals(response.status, 403);
    assertEquals(await response.json(), { ok: false, code: "OPERATOR_NOT_AUTHORIZED" });
  }
});