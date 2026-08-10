import {
  mapAdminPricingReadRow,
  mapCustomerPricingReadRow,
} from "./pricing-read-dto.ts";

export interface PricingReadResponse {
  status: 200 | 401 | 409 | 500;
  body: Record<string, unknown>;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

export function customerPricingReadResponse(
  row: unknown,
  readFailed: boolean,
): PricingReadResponse {
  if (readFailed) {
    return {
      status: 500,
      body: {
        ok: false,
        code: "CUSTOMER_PRICING_READ_FAILED",
        message: "Pricing is unavailable.",
      },
    };
  }
  if (!isRecord(row)) {
    return {
      status: 401,
      body: {
        ok: false,
        code: "INVALID_INTAKE_TOKEN",
        message: "The intake link is invalid or expired.",
      },
    };
  }
  if (row.intake_status !== "submitted" && row.intake_status !== "reviewed") {
    return {
      status: 409,
      body: {
        ok: false,
        code: "PRICING_RESULT_NOT_AVAILABLE",
        message: "Pricing is unavailable.",
      },
    };
  }

  try {
    return {
      status: 200,
      body: { ok: true, pricing: mapCustomerPricingReadRow(row) },
    };
  } catch {
    return {
      status: 500,
      body: {
        ok: false,
        code: "CUSTOMER_PRICING_READ_FAILED",
        message: "Pricing is unavailable.",
      },
    };
  }
}

export function adminPricingReadResponse(
  row: unknown,
  readFailed: boolean,
): PricingReadResponse {
  if (readFailed) {
    return {
      status: 500,
      body: {
        ok: false,
        code: "ADMIN_PRICING_READ_FAILED",
        message: "Admin pricing is unavailable.",
      },
    };
  }
  if (!isRecord(row)) {
    return {
      status: 401,
      body: {
        ok: false,
        code: "INVALID_ADMIN_CAPABILITY",
        message: "Admin pricing is unavailable.",
      },
    };
  }
  if (row.intake_status !== "submitted") {
    return {
      status: 409,
      body: {
        ok: false,
        code: "PRICING_RESULT_NOT_AVAILABLE",
        message: "Admin pricing is unavailable.",
      },
    };
  }

  try {
    return {
      status: 200,
      body: { ok: true, pricing: mapAdminPricingReadRow(row) },
    };
  } catch {
    return {
      status: 500,
      body: {
        ok: false,
        code: "ADMIN_PRICING_READ_FAILED",
        message: "Admin pricing is unavailable.",
      },
    };
  }
}