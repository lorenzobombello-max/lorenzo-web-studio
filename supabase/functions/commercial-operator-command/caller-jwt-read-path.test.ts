import { assertEquals } from "jsr:@std/assert@1";
import {
  createUnsignedTestJwt,
  handleCommercialOperator,
  withCommercialOperatorCors,
} from "./handler.ts";

const userId = "a1000000-0000-4000-8000-000000000001";
const callerJwt = createUnsignedTestJwt({
  sub: userId,
  role: "authenticated",
  aal: "aal1",
  exp: 4102444800,
});

function request(body: Record<string, unknown>, token?: string) {
  const headers = new Headers({ "Content-Type": "application/json" });
  if (token) headers.set("Authorization", `Bearer ${token}`);
  return new Request("https://example.test", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

function pendingItem() {
  return {
    quote_request_id: "a1800000-0000-4000-8000-000000000091",
    intake_id: "a1800000-0000-4000-8000-000000000092",
    name: "Pending owner read",
    organization: null,
    support_reference: "#5C19F9DD",
    email: "pending@example.test",
    phone: null,
    request_kind: "website",
    sdf_package: null,
    website_type: "Website op maat",
    invitation_created_at: "2099-01-01T10:00:00Z",
    invitation_sent_at: null,
    invitation_delivery_status: null,
    intake_status: "invited",
    effective_access: "ACTIVE",
    access_token_expires_at: "2099-01-08T10:00:00Z",
    lifecycle_revision: 0,
    retention_state: "ACTIVE",
    archived_at: null,
    retention_revision: 0,
    can_permanently_delete: true,
    delete_block_reason: null,
    started_at: null,
    current_reminder_cycle: 0,
    reminder_1_sent_at: null,
    reminder_2_sent_at: null,
    last_activity_at: "2099-01-01T10:00:00Z",
    dossier_state: "ACTIVE",
    dossier_revision: 0,
    seen_at: null,
  };
}

function dependencies(
  observedJwts: string[],
  pendingItems: Record<string, unknown>[] = [],
) {
  return {
    now: () => Date.now(),
    verifyUser: async () => ({ id: userId }),
    authorizeApplicationReader: async () => undefined,
    verifyOperatorCursor: async () => null,
    executeApplicationListV2: async (
      jwt: string,
      actorAuthUserId: string,
    ) => {
      observedJwts.push(jwt);
      assertEquals(actorAuthUserId, userId);
      return { items: [], has_more: false, next_position: null };
    },
    executePendingIntakes: async (
      jwt: string,
      actorAuthUserId: string,
      retentionState: string,
    ) => {
      observedJwts.push(jwt);
      assertEquals(actorAuthUserId, userId);
      assertEquals(retentionState, "ACTIVE");
      return { items: pendingItems };
    },
    executePendingIntakeCount: async (jwt: string, actorAuthUserId: string) => {
      observedJwts.push(jwt);
      assertEquals(actorAuthUserId, userId);
      return { active_count: 0 };
    },
    executeDossierSubstance: async () => ({}),
    executeMarkDossierSeen: async () => ({}),
    signOperatorCursor: async () => "unused",
    executeApplicationFacetsV2: async (
      jwt: string,
      actorAuthUserId: string,
    ) => {
      observedJwts.push(jwt);
      assertEquals(actorAuthUserId, userId);
      return {};
    },
    executeApplicationAction: async () => ({}),
    consumeRateLimit: async () => ({ allowed: true, retry_after_seconds: 0 }),
    executeCommand: async () => ({}),
  };
}

Deno.test("dashboard dossier read RPCs use caller JWT instead of service role", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  for (
    const [rpc, expectedCallsites] of [
      ["list_operator_pending_intakes_v1", 1],
      ["list_operator_pending_sdf_intakes_v1", 3],
      ["count_operator_active_pending_intakes_v1", 1],
      ["list_operator_applications_v2", 1],
      ["get_operator_dossier_facets_v2", 1],
      ["get_operator_dossier_substance_v1", 1],
    ]
  ) {
    const callsites = source.match(
      new RegExp(
        `(?:serviceClient\\(\\)|clientFor\\(jwt\\))\\.rpc\\(\\s*"${rpc}"`,
        "g",
      ),
    ) || [];
    assertEquals(callsites.length, expectedCallsites);
    assertEquals(
      callsites.every((callsite) => callsite.startsWith("clientFor(jwt)")),
      true,
    );
  }
});

Deno.test("valid AAL1 owner JWT reaches dashboard dossier read transports", async () => {
  const observedJwts: string[] = [];
  const deps = dependencies(observedJwts);
  const pending = await handleCommercialOperator(
    request({ action: "list_pending_intakes", retention_state: "ACTIVE" }, callerJwt),
    deps,
  );
  const active = await handleCommercialOperator(
    request({
      action: "list_applications_v2",
      zone: "ACTIVE",
      operational_status: null,
      year: null,
      quarter: null,
      request_kind: null,
      search: null,
      cursor: null,
      limit: 50,
    }, callerJwt),
    deps,
  );
  const count = await handleCommercialOperator(
    request({ action: "count_pending_intakes" }, callerJwt),
    deps,
  );
  const facets = await handleCommercialOperator(
    request({
      action: "get_application_facets_v2",
      zone: "ACTIVE",
      operational_status: null,
      request_kind: null,
      search: null,
    }, callerJwt),
    deps,
  );

  assertEquals(pending.status, 200);
  assertEquals(active.status, 200);
  assertEquals((await active.clone().json()).result.has_more, false);
  assertEquals(count.status, 200);
  assertEquals(facets.status, 200);
  assertEquals(observedJwts, [callerJwt, callerJwt, callerJwt, callerJwt]);
});

Deno.test("missing and invalid JWT fail closed before read dispatch", async () => {
  let verifyCalls = 0;
  const deps = {
    ...dependencies([]),
    verifyUser: async () => {
      verifyCalls += 1;
      return { id: userId };
    },
  };

  const missing = await handleCommercialOperator(
    request({ action: "list_pending_intakes" }),
    deps,
  );
  const invalid = await handleCommercialOperator(
    request({ action: "list_pending_intakes" }, "not-a-jwt"),
    deps,
  );

  assertEquals(missing.status, 401);
  assertEquals(invalid.status, 401);
  assertEquals(verifyCalls, 0);
});

Deno.test("pending read accepts the current dossier seen-state DTO", async () => {
  const response = await handleCommercialOperator(
    request({ action: "list_pending_intakes", retention_state: "ACTIVE" }, callerJwt),
    dependencies([], [pendingItem()]),
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.result.items[0].dossier_state, "ACTIVE");
  assertEquals(body.result.items[0].seen_at, null);
});

Deno.test("dossier read preflight preserves required Supabase headers", async () => {
  let dispatched = false;
  const response = await withCommercialOperatorCors(
    new Request("https://example.test", {
      method: "OPTIONS",
      headers: {
        Origin: "https://lorenzowebsolutions.be",
        "Access-Control-Request-Headers":
          "apikey,authorization,content-type,x-client-info",
      },
    }),
    () => {
      dispatched = true;
      return new Response(null, { status: 200 });
    },
  );

  assertEquals(response.status, 204);
  assertEquals(dispatched, false);
  const allowed = new Set(
    (response.headers.get("Access-Control-Allow-Headers") || "")
      .split(",")
      .map((header) => header.trim()),
  );
  for (const header of ["apikey", "authorization", "content-type", "x-client-info"]) {
    assertEquals(allowed.has(header), true);
  }
});