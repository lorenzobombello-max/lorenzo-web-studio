import { assertEquals } from "jsr:@std/assert@1";
import { createUnsignedTestJwt, handleCommercialOperator, withCommercialOperatorCors } from "./handler.ts";

const userId = "a1000000-0000-4000-8000-000000000001";
const jwt = createUnsignedTestJwt({ sub: userId, role: "authenticated", exp: 4102444800 });

function request(body: Record<string, unknown>, token = jwt) {
  return new Request("https://example.test", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", Origin: "https://lorenzowebsolutions.be" },
    body: JSON.stringify(body)
  });
}

function dependencies() {
  const calls: Array<{ jwt: string; input: Record<string, unknown> }> = [];
  return {
    calls,
    deps: {
      now: ()=>Date.now(),
      verifyUser: async ()=>({ id: userId }),
      consumeRateLimit: async ()=>({ allowed: true, retry_after_seconds: 0 }),
      executeCommand: async ()=>({ command: true }),
      executeApplicationAction: async (token: string, input: Record<string, unknown>)=>{
        calls.push({ jwt: token, input });
        return { action: input.action };
      }
    }
  };
}

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
  assertEquals(harness.calls[0].input, { action: "get_application_detail", quote_request_id: null, application_reference: "LWS-AAN-2099-0001" });
  const ambiguous = await handleCommercialOperator(request({ action: "get_application_detail", quote_request_id: userId, application_reference: "LWS-AAN-2099-0001" }), harness.deps);
  assertEquals(ambiguous.status, 400);
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

Deno.test("promotion requires server-shaped locator and idempotency UUID", async ()=>{
  const harness = dependencies();
  const invalid = await handleCommercialOperator(request({ action: "promote_accepted_application", quote_request_id: userId, idempotency_key: "bad" }), harness.deps);
  assertEquals(invalid.status, 400);
  const valid = await handleCommercialOperator(request({ action: "promote_accepted_application", quote_request_id: userId, idempotency_key: "a1800000-0000-4000-8000-000000000001" }), harness.deps);
  assertEquals(valid.status, 200);
  assertEquals(harness.calls.length, 1);
});

Deno.test("service role JWT cannot enter application actions", async ()=>{
  const harness = dependencies();
  const serviceJwt = createUnsignedTestJwt({ sub: userId, role: "service_role", exp: 4102444800 });
  const response = await handleCommercialOperator(request({ action: "list_applications" }, serviceJwt), harness.deps);
  assertEquals(response.status, 401);
  assertEquals(harness.calls.length, 0);
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