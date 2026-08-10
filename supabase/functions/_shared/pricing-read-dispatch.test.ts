import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  dispatchPricingRead,
  type PricingReadRpcClient,
} from "./pricing-read-dispatch.ts";
import {
  createPricingSnapshotIntegrity,
  verifyPricingSnapshotIntegrity,
} from "./pricing-snapshot-integrity.ts";

const token = "A".repeat(43);
const origin = "https://lorenzowebsolutions.be";

function dependencies(expectedActor: "customer" | "admin") {
  return {
    hashCustomerToken: (value: string) => {
      assertEquals(expectedActor, "customer");
      assertEquals(value, token);
      return Promise.resolve("c".repeat(64));
    },
    hashAdminToken: (value: string) => {
      assertEquals(expectedActor, "admin");
      assertEquals(value, token);
      return Promise.resolve("a".repeat(64));
    },
    verifyIntegrity: () => Promise.resolve(true),
  };
}

Deno.test("customer dispatch uses intake hash domain, customer RPC, mapper, and security headers", async () => {
  let call:
    | { functionName: string; parameters: Record<string, unknown> }
    | null = null;
  const client: PricingReadRpcClient = {
    rpc(functionName, parameters) {
      call = { functionName, parameters };
      return Promise.resolve({
        data: [{
          intake_status: "submitted",
          snapshot_present: true,
          snapshot_contract_version: 2,
          calculation_basis: "starter_floor",
          currency: "EUR",
          vat_basis: "exclusive",
          known_minimum_minor: 220000,
          contains_from_pricing: true,
          manual_review_required: false,
          manual_reason_count: 0,
          budget_contract_version: 2,
          evidence_provenance: "budget_guard_v1",
          budget_status: "possibly_compatible_with_category",
          outside_budget_wishes: false,
          integrity_snapshot: { snapshotContractVersion: 2 },
          integrity_context: "32c31000-0000-4000-8000-000000000001",
          integrity_metadata: { algorithmVersion: "hmac-sha256-v1" },
          futureInternalSecret: "never-return",
        }],
        error: null,
      });
    },
  };

  const response = await dispatchPricingRead(
    "customer",
    token,
    origin,
    client,
    dependencies("customer"),
  );
  const body = await response.json();

  assertEquals(call, {
    functionName: "inspect_customer_pricing_read_v2",
    parameters: { p_access_token_hash: "c".repeat(64) },
  });
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(response.headers.get("referrer-policy"), "no-referrer");
  assertEquals(response.headers.get("access-control-allow-origin"), origin);
  assertEquals(body.pricing.indicativeStartingPrice.amountMinor, 220000);
  assertEquals(JSON.stringify(body).includes("futureInternalSecret"), false);
});

Deno.test("admin dispatch uses separate admin hash domain and admin RPC", async () => {
  let call:
    | { functionName: string; parameters: Record<string, unknown> }
    | null = null;
  const client: PricingReadRpcClient = {
    rpc(functionName, parameters) {
      call = { functionName, parameters };
      return Promise.resolve({
        data: [{
          intake_status: "submitted",
          snapshot_present: false,
          snapshot_contract_version: null,
          snapshot_created_at: null,
          rawSnapshot: { secret: true },
        }],
        error: null,
      });
    },
  };

  const response = await dispatchPricingRead(
    "admin",
    token,
    origin,
    client,
    dependencies("admin"),
  );
  const body = await response.json();

  assertEquals(call, {
    functionName: "inspect_admin_pricing_read_v2",
    parameters: { p_admin_access_token_hash: "a".repeat(64) },
  });
  assertEquals(response.status, 200);
  assertEquals(body.pricing.availability, "unavailable");
  assertEquals(JSON.stringify(body).includes("rawSnapshot"), false);
});

Deno.test("dispatch maps invalid tokens and RPC errors without leaking internals", async () => {
  let rpcCalls = 0;
  const client: PricingReadRpcClient = {
    rpc() {
      rpcCalls += 1;
      return Promise.resolve({
        data: { internal: "row" },
        error: { message: "database detail" },
      });
    },
  };

  const invalid = await dispatchPricingRead(
    "customer",
    "invalid",
    origin,
    client,
    dependencies("customer"),
  );
  assertEquals(invalid.status, 401);
  assertEquals(rpcCalls, 0);

  const failed = await dispatchPricingRead(
    "admin",
    token,
    origin,
    client,
    dependencies("admin"),
  );
  const body = await failed.json();
  assertEquals(failed.status, 500);
  assertEquals(body.code, "ADMIN_PRICING_READ_FAILED");
  assertEquals(JSON.stringify(body).includes("database detail"), false);
  assertEquals(failed.headers.get("cache-control"), "no-store");
  assertEquals(failed.headers.get("referrer-policy"), "no-referrer");
});

Deno.test("customer amount is disclosed only after real producer proof verification", async () => {
  const secret = "dispatch-integrity-test-key-material-00000000000001";
  const snapshot = {
    snapshotContractVersion: 2,
    pricingConfigVersion: "1.0.0",
    pricingConfigHash: "a".repeat(64),
    normalizedScope: {
      standardPages: ["home"],
      standardPageCount: 1,
      primaryLanguage: "nl",
      additionalLanguages: [],
      unknownLanguages: [],
      modules: [],
      manualComponents: [],
    },
    calculation: {
      basis: "starter_floor",
      currency: "EUR",
      vatBasis: "exclusive",
      knownMinimumMinor: 180000,
      containsFromPricing: true,
      manualReviewRequired: false,
      manualReasons: [],
      appliedRules: [{
        ruleId: "starter_floor",
        mode: "from",
        amountMinor: 180000,
        quantity: 1,
        knownMinimumContributionMinor: 180000,
      }],
    },
    packageAdvice: {
      status: "none",
      reasons: [],
      advisoryOnly: true,
      selectedPackage: null,
    },
    budgetEvaluation: {
      contractVersion: 2,
      evidenceProvenance: "budget_guard_v1",
      categoryScheme: "budget_guard_v1",
      categoryCode: "3200_to_6000_inclusive",
      originalLabel: "EUR 3.200 t/m EUR 6.000",
      status: "possibly_compatible_with_category",
      outsideBudgetWishes: false,
    },
  };
  const integrityContext = "32c31000-0000-4000-8000-000000000001";
  const integrity = await createPricingSnapshotIntegrity(
    snapshot,
    integrityContext,
    "v1",
    secret,
  );
  const row = {
    intake_status: "submitted",
    snapshot_present: true,
    snapshot_contract_version: 2,
    calculation_basis: "starter_floor",
    currency: "EUR",
    vat_basis: "exclusive",
    known_minimum_minor: 180000,
    contains_from_pricing: true,
    manual_review_required: false,
    manual_reason_count: 0,
    budget_contract_version: 2,
    evidence_provenance: "budget_guard_v1",
    budget_status: "possibly_compatible_with_category",
    outside_budget_wishes: false,
    integrity_snapshot: snapshot,
    integrity_context: integrityContext,
    integrity_metadata: integrity,
  };
  let rpcRow: Record<string, unknown> = row;
  const client: PricingReadRpcClient = {
    rpc: () => Promise.resolve({ data: [rpcRow], error: null }),
  };
  const actualDependencies = {
    ...dependencies("customer"),
    verifyIntegrity: (value: object, context: string, metadata: unknown) =>
      verifyPricingSnapshotIntegrity(value, context, metadata, () => secret),
  };

  const authentic = await dispatchPricingRead(
    "customer",
    token,
    origin,
    client,
    actualDependencies,
  );
  const authenticBody = await authentic.json();
  assertEquals(
    authenticBody.pricing.indicativeStartingPrice.amountMinor,
    180000,
  );

  rpcRow = structuredClone(row);
  rpcRow.known_minimum_minor = 220000;
  (rpcRow.integrity_snapshot as typeof snapshot).calculation.knownMinimumMinor =
    220000;
  const forged = await dispatchPricingRead(
    "customer",
    token,
    origin,
    client,
    actualDependencies,
  );
  const forgedBody = await forged.json();
  assertEquals(forgedBody.pricing.pricingState, "pricing_result_unavailable");
  assert(!("indicativeStartingPrice" in forgedBody.pricing));

  rpcRow = { ...row, integrity_metadata: null };
  const proofless = await dispatchPricingRead(
    "customer",
    token,
    origin,
    client,
    actualDependencies,
  );
  const prooflessBody = await proofless.json();
  assertEquals(
    prooflessBody.pricing.pricingState,
    "pricing_result_unavailable",
  );
  assert(!("indicativeStartingPrice" in prooflessBody.pricing));
});
