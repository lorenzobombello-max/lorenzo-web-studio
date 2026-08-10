import { assertEquals } from "jsr:@std/assert@1";
import {
  adminPricingReadResponse,
  customerPricingReadResponse,
} from "./pricing-read-response.ts";

const customerRow = {
  intake_status: "submitted",
  snapshot_present: false,
  snapshot_contract_version: null,
  futureInternalSecret: "never-return",
};

const adminRow = {
  intake_status: "submitted",
  snapshot_present: false,
  snapshot_contract_version: null,
  snapshot_created_at: null,
  futureInternalSecret: "never-return",
};

Deno.test("customer read rejects missing capability without source details", () => {
  assertEquals(customerPricingReadResponse(null, false), {
    status: 401,
    body: {
      ok: false,
      code: "INVALID_INTAKE_TOKEN",
      message: "The intake link is invalid or expired.",
    },
  });
});

Deno.test("admin read rejects missing capability on its separate boundary", () => {
  assertEquals(adminPricingReadResponse(null, false), {
    status: 401,
    body: {
      ok: false,
      code: "INVALID_ADMIN_CAPABILITY",
      message: "Admin pricing is unavailable.",
    },
  });
});

Deno.test("pricing reads reject wrong lifecycle", () => {
  assertEquals(customerPricingReadResponse({ intake_status: "in_progress" }, false).status, 409);
  assertEquals(adminPricingReadResponse({ intake_status: "reviewed" }, false).status, 409);
});

Deno.test("customer missing snapshot returns safe unavailable DTO", () => {
  assertEquals(customerPricingReadResponse(customerRow, false), {
    status: 200,
    body: {
      ok: true,
      pricing: {
        presentationContractVersion: 1,
        requestStatus: "submitted",
        pricingState: "pricing_result_unavailable",
        requiresPersonalReview: true,
        formalQuotationRequired: true,
        budgetIndicator: "not_reliably_comparable",
      },
    },
  });
});

Deno.test("admin missing snapshot returns safe unavailable DTO", () => {
  assertEquals(adminPricingReadResponse(adminRow, false), {
    status: 200,
    body: {
      ok: true,
      pricing: {
        presentationContractVersion: 1,
        requestStatus: "submitted",
        availability: "unavailable",
        historicalResult: true,
      },
    },
  });
});

Deno.test("projection errors and malformed rows fail closed", () => {
  assertEquals(customerPricingReadResponse(customerRow, true).status, 500);
  assertEquals(adminPricingReadResponse(adminRow, true).status, 500);
  const customer = customerPricingReadResponse({
    ...customerRow,
    snapshot_present: true,
    known_minimum_minor: 220000,
    rawSnapshot: { secret: true },
  }, false);
  assertEquals(customer, {
    status: 200,
    body: {
      ok: true,
      pricing: {
        presentationContractVersion: 1,
        requestStatus: "submitted",
        pricingState: "pricing_result_unavailable",
        requiresPersonalReview: true,
        formalQuotationRequired: true,
        budgetIndicator: "not_reliably_comparable",
      },
    },
  });
  const admin = adminPricingReadResponse({
    ...adminRow,
    snapshot_present: true,
    snapshot_contract_version: 2,
    calculation: { knownMinimumMinor: 220000 },
    rawSnapshot: { secret: true },
  }, false);
  assertEquals(admin, {
    status: 200,
    body: {
      ok: true,
      pricing: {
        presentationContractVersion: 1,
        requestStatus: "submitted",
        availability: "unavailable",
        historicalResult: true,
      },
    },
  });
  const serialized = JSON.stringify({ customer: customer.body, admin: admin.body });
  assertEquals(serialized.includes("knownMinimumMinor"), false);
  assertEquals(serialized.includes("rawSnapshot"), false);
  assertEquals(serialized.includes("calculation"), false);
});

Deno.test("unknown projection fields are never serialized", () => {
  const customer = JSON.stringify(customerPricingReadResponse(customerRow, false).body);
  const admin = JSON.stringify(adminPricingReadResponse(adminRow, false).body);
  assertEquals(customer.includes("futureInternalSecret"), false);
  assertEquals(admin.includes("futureInternalSecret"), false);
});