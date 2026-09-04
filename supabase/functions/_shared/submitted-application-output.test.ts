import { assertEquals } from "jsr:@std/assert@1";
import { assertRejects } from "jsr:@std/assert@1";
import {
  enrichOperatorApplicationDetailWithOutput,
  loadSubmittedApplicationOutput,
  loadSubmittedApplicationOutputForOperator,
} from "./submitted-application-output.ts";

const requestId = "11111111-1111-4111-8111-111111111111";
const intakeId = "22222222-2222-4222-8222-222222222222";
const tokenHash = "a".repeat(64);

const request = {
  id: requestId,
  record_classification: "production",
  application_reference: "LWS-AAN-2026-0042",
  name: "Test Klant",
  company: "Test BV",
  email: "test@example.test",
  phone: null,
  website_type: "Bedrijfswebsite",
  budget: "EUR 5.000 - EUR 7.500",
  timing: "Binnen 3 maanden",
};

const intake = {
  id: intakeId,
  quote_request_id: requestId,
  status: "submitted",
  submitted_at: "2026-08-28T13:14:51.504Z",
  access_token_hash: tokenHash,
  access_token_expires_at: "2026-08-01T00:00:00.000Z",
  access_token_revoked_at: null,
  requested_pages: ["Home", "Contact"],
  website_goals: [],
  requested_features: [],
  shop_required: false,
  booking_required: false,
  languages: ["nl"],
  additional_languages: [],
  design_styles: [],
  brand_colors: [],
  inspiration_sites: [],
  image_support: [],
  social_channels: [],
  integrations: [],
  priorities: [],
};

const snapshot = {
  id: "33333333-3333-4333-8333-333333333333",
  intake_id: intakeId,
  snapshot_contract_version: 3,
  config_version: "2026-08-16-v3",
  config_hash: "b".repeat(64),
  normalized_evidence: {},
  calculation: { knownMinimumMinor: 350000, currency: "EUR", vatBasis: "exclusive" },
  package_advice: {},
  budget_evaluation: { status: "within", originalLabel: "EUR 5.000 - EUR 7.500" },
  package_definition: { id: "professional_v2" },
  recurring_services: [],
};

const integrity = {
  snapshot_id: snapshot.id,
  algorithm_version: "hmac-sha256-v1",
  key_id: "v1",
  mac: "c".repeat(64),
};

function client(rows: Record<string, Record<string, unknown> | null>, rpcData: Record<string, unknown> = {}) {
  const calls: string[] = [];
  return {
    calls,
    from(table: string) {
      calls.push(`from:${table}`);
      return {
        select() { return this; },
        eq() { return this; },
        maybeSingle() { return Promise.resolve({ data: rows[table] ?? null, error: null }); },
      };
    },
    rpc(name: string) {
      calls.push(`rpc:${name}`);
      return Promise.resolve({ data: rpcData[name] ?? [], error: null });
    },
  };
}

for (const [state, tokenState] of [
  ["expired", { access_token_expires_at: "2026-08-01T00:00:00.000Z", access_token_revoked_at: null }],
  ["revoked", { access_token_expires_at: "2026-09-01T00:00:00.000Z", access_token_revoked_at: "2026-08-27T00:00:00.000Z" }],
] as const) {
  Deno.test(`operator loads submitted dossier when customer token is ${state}`, async () => {
    const caller = client({}, {
      get_operator_submitted_application_intake_v1: { ...intake, ...tokenState },
      get_operator_submitted_application_pricing_snapshot_v1: snapshot,
      get_operator_submitted_application_request_v1: request,
    });
    const service = client({}, {
      get_pricing_snapshot_integrity_for_operator_v1: [integrity],
    });
    const verifiedContexts: string[] = [];
    const result = await loadSubmittedApplicationOutputForOperator(
      caller as never,
      service as never,
      requestId,
      requestId,
      async (_snapshot, context) => {
        verifiedContexts.push(context);
        return true;
      },
    );

    assertEquals(result?.requestId, requestId);
    assertEquals(result?.output.applicationReference, "LWS-AAN-2026-0042");
    assertEquals(verifiedContexts, [intakeId]);
    assertEquals(caller.calls.includes("rpc:get_operator_submitted_application_intake_v1"), true);
    assertEquals(caller.calls.includes("rpc:get_operator_submitted_application_pricing_snapshot_v1"), true);
    assertEquals(caller.calls.includes("rpc:get_operator_submitted_application_request_v1"), true);
    assertEquals(service.calls.includes("from:quote_request_intakes"), false);
    assertEquals(service.calls.includes("from:quote_requests"), false);
    assertEquals(service.calls.includes("from:quote_request_pricing_snapshots"), false);
    assertEquals(service.calls.includes("rpc:get_pricing_snapshot_integrity_for_operator_v1"), true);
    assertEquals(service.calls.includes("from:quote_request_pricing_snapshot_integrity"), false);
  });
}

Deno.test("customer loader remains bound to token-protected inspection RPCs", async () => {
  const customer = client({ quote_request_intakes: intake, quote_requests: request });
  const result = await loadSubmittedApplicationOutput(customer as never, tokenHash);

  assertEquals(result, null);
  assertEquals(customer.calls.includes("rpc:inspect_quote_request_intake_details_v4"), true);
  assertEquals(customer.calls.includes("rpc:inspect_customer_pricing_read_v3"), true);
});

Deno.test("operator loader remains fail closed when the integrity RPC returns no record", async () => {
  const caller = client({}, {
    get_operator_submitted_application_intake_v1: intake,
    get_operator_submitted_application_pricing_snapshot_v1: snapshot,
    get_operator_submitted_application_request_v1: request,
  });
  const service = client({});
  const failures: string[] = [];
  const result = await loadSubmittedApplicationOutputForOperator(
    caller as never,
    service as never,
    requestId,
    requestId,
    async () => true,
    (reason) => failures.push(reason),
  );

  assertEquals(result, null);
  assertEquals(failures, ["integrity_record_unavailable"]);
});

Deno.test("operator loader rejects malformed or tampered integrity and remains fail closed", async () => {
  const caller = client({}, {
    get_operator_submitted_application_intake_v1: intake,
    get_operator_submitted_application_pricing_snapshot_v1: snapshot,
    get_operator_submitted_application_request_v1: request,
  });
  const service = client({}, {
    get_pricing_snapshot_integrity_for_operator_v1: [integrity],
  });
  const failures: string[] = [];
  const result = await loadSubmittedApplicationOutputForOperator(
    caller as never,
    service as never,
    requestId,
    requestId,
    async () => false,
    (reason) => failures.push(reason),
  );

  assertEquals(result, null);
  assertEquals(failures, ["integrity_verification_failed"]);
});

Deno.test("legacy trashed detail remains available when modern submitted output is absent", () => {
  const detail = {
    quote_request_id: requestId,
    request_kind: "website",
    dossier_lifecycle: { state: "TRASHED", revision: 3 },
  };

  assertEquals(enrichOperatorApplicationDetailWithOutput(detail, null), {
    ...detail,
    application: null,
  });
});

Deno.test("non-trashed detail remains fail closed when submitted output is absent", async () => {
  await assertRejects(
    async () => enrichOperatorApplicationDetailWithOutput({
      quote_request_id: requestId,
      request_kind: "website",
      dossier_lifecycle: { state: "ACTIVE", revision: 3 },
    }, null),
    Error,
    "APPLICATION_OUTPUT_UNAVAILABLE",
  );
});

Deno.test("operator detail enrichment rejects output from another dossier", async () => {
  await assertRejects(
    async () => enrichOperatorApplicationDetailWithOutput({
      quote_request_id: requestId,
      request_kind: "website",
      dossier_lifecycle: { state: "ACTIVE", revision: 3 },
    }, {
      requestId: "44444444-4444-4444-8444-444444444444",
      output: {} as never,
    }),
    Error,
    "APPLICATION_OUTPUT_UNAVAILABLE",
  );
});
